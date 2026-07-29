----------------------------------------------------------------------
-- Guild OS - Calendar / Signups
-- Officers create events; members RSVP (Yes/Tentative/No) with their role.
-- Synced via SyncService (domain "event"): create/update/cancel are officer
-- actions, rsvp is a member action recorded per player on every client. This is
-- the "Plan A" synced addon board — it does NOT depend on C_Calendar (which is
-- unreliable on the Anniversary client).
----------------------------------------------------------------------
local Calendar = {}
BRutus.Calendar = Calendar
local L = BRutus.L

Calendar.STATUS = { YES = "yes", TENTATIVE = "tentative", NO = "no" }
Calendar.ROLES  = { "TANK", "HEALER", "DPS" }

-- Event categories. Order drives the picker; RAID is the default so legacy
-- events (created before kinds existed) read back as raids.
Calendar.KINDS = { "RAID", "DUNGEON", "PVP", "FARM", "SOCIAL", "OTHER" }
Calendar.DEFAULT_KIND = "RAID"

local KIND_SET = {}
for _, k in ipairs(Calendar.KINDS) do KIND_SET[k] = true end
local function normalizeKind(k) return (k and KIND_SET[k]) and k or Calendar.DEFAULT_KIND end

-- Localized display label for a category token.
function Calendar:KindLabel(k)
    k = normalizeKind(k)
    local map = {
        RAID = L["Raid"], DUNGEON = L["Dungeon"], PVP = L["PvP"],
        FARM = L["Farm"], SOCIAL = L["Social"], OTHER = L["Other"],
    }
    return map[k] or k
end

function Calendar:Initialize()
    BRutus.db.calendar = BRutus.db.calendar or { events = {} }
    BRutus.db.calendar.events = BRutus.db.calendar.events or {}
    BRutus.db.calendar.deleted = BRutus.db.calendar.deleted or {}
    self:PruneTombstones()
    if BRutus.SyncService then
        BRutus.SyncService:On("event", function(env, sender) Calendar:OnSync(env, sender) end)
    end

    -- Alliance wiring. Both are no-ops until this guild joins a pact.
    if GuildOS.Alliance then
        GuildOS.Alliance:RegisterOp("EVT", function(data, sender, guild)
            Calendar:OnAllianceEvent(data, sender, guild)
        end)
    end
    if GuildOS.AllianceSync then
        GuildOS.AllianceSync:Register("events", {
            priority = "NORMAL",
            cap = 50,
            build = function()
                return Calendar._BuildAllianceEvents(Calendar:GetEvents(), GetServerTime(), 50)
            end,
            -- A fresh allied calendar is exactly when a new collision can
            -- appear, so check right here instead of waiting for a panel open.
            apply = function()
                Calendar:_AnnounceNewConflicts()
            end,
        })
    end
    self:_RegisterTests()
end

function Calendar:_RegisterTests()
    if not BRutus.SelfTest then
        return
    end

    BRutus.SelfTest:Register("calendar.alliance_slot_decision", function()
        local D = Calendar._AllianceSlotDecision
        local future = { when = 2000, size = 10 }
        if D(future, 3, 1000) ~= "ok" then return false, "open event must be ok" end
        if D(future, 10, 1000) ~= "full" then return false, "at capacity must be full" end
        if D(future, 11, 1000) ~= "full" then return false, "over capacity must be full" end
        if D({ when = 500, size = 10 }, 0, 1000) ~= "past" then return false, "past event" end
        if D({ when = 2000, size = 10, canceled = true }, 0, 1000) ~= "canceled" then
            return false, "canceled event"
        end
        if D(nil, 0, 1000) ~= "gone" then return false, "missing event" end
        if D({ when = 2000 }, 25, 1000) ~= "full" then return false, "default size 25" end
        return true
    end)

    BRutus.SelfTest:Register("calendar.alliance_conflicts", function()
        local F = Calendar._FindConflicts
        local mine = {
            { id = "m1", title = "MC",   when = 100000, names = { "Ann", "Bob", "Cid" } },
            { id = "m2", title = "Kara", when = 500000, names = { "Ann" } },
        }
        local theirs = {
            { id = "t1", title = "BWL", when = 103000, guild = "G B", names = { "bob", "Cid", "Dan" } },
            { id = "t2", title = "ZG",  when = 900000, guild = "G C", names = { "Ann" } },
        }
        local out = F(mine, theirs, 7200)   -- 2h window
        if #out ~= 1 then return false, "expected 1 collision, got " .. #out end
        local c = out[1]
        if c.mine.id ~= "m1" or c.theirs.id ~= "t1" then return false, "wrong pair matched" end
        -- Name matching must be case insensitive: "bob" and "Bob" are one person.
        if c.sharedCount ~= 2 then return false, "expected 2 shared, got " .. c.sharedCount end
        if c.shared[1] ~= "Bob" or c.shared[2] ~= "Cid" then
            return false, "shared names wrong: " .. table.concat(c.shared, ",")
        end
        -- Outside the window nothing collides, however many names overlap.
        if #F(mine, theirs, 60) ~= 0 then return false, "narrow window still matched" end
        -- Most double-booked first.
        local many = {
            { id = "m9", title = "A", when = 100000, names = { "Ann", "Bob", "Cid" } },
        }
        local two = {
            { id = "t8", title = "B", when = 100100, guild = "G", names = { "Zed" } },
            { id = "t9", title = "C", when = 100200, guild = "G", names = { "Ann", "Bob", "Cid" } },
        }
        local ranked = F(many, two, 7200)
        if ranked[1].theirs.id ~= "t9" then return false, "not ranked by shared count" end
        if #F(nil, theirs, 7200) ~= 0 then return false, "nil must not error" end
        return true
    end)

    BRutus.SelfTest:Register("calendar.alliance_events_build", function()
        local events = {
            a1 = { id = "a1", title = "MC",   when = 2000, size = 40,
                   rsvps = { x = { status = "yes" }, y = { status = "no" } } },
            a2 = { id = "a2", title = "Past", when = 500,  size = 10 },
            a3 = { id = "a3", title = "Gone", when = 3000, size = 10, canceled = true },
            a4 = { id = "a4", title = "Kara", when = 2500, size = 10 },
        }
        local out = Calendar._BuildAllianceEvents(events, 1000, 50)
        if #out ~= 2 then return false, "expected 2 upcoming events, got " .. #out end
        if out[1].id ~= "a1" or out[2].id ~= "a4" then return false, "not sorted by id" end
        if out[1].yes ~= 1 then return false, "yes count wrong: " .. tostring(out[1].yes) end
        if type(out[1].names) ~= "table" then return false, "signup names missing" end
        if #Calendar._BuildAllianceEvents(events, 1000, 1) ~= 1 then return false, "cap not enforced" end
        if #Calendar._BuildAllianceEvents(nil, 1000, 50) ~= 0 then return false, "nil must not error" end
        return true
    end)
end

function Calendar:GetEvents() return BRutus.db.calendar.events end

-- Deletion tombstones: a small id->timestamp set so a hard delete cannot be
-- undone by a straggling create/update for the same event still in flight on
-- the guild channel, and so old events truly disappear instead of lingering
-- forever as canceled records. Pruned after TOMBSTONE_TTL.
local TOMBSTONE_TTL = 30 * 86400
function Calendar:Tombstones() return BRutus.db.calendar.deleted end
function Calendar:IsDeleted(id) return self:Tombstones()[id] ~= nil end
function Calendar:PruneTombstones()
    local cutoff = GetServerTime() - TOMBSTONE_TTL
    for id, ts in pairs(self:Tombstones()) do
        if (ts or 0) < cutoff then self:Tombstones()[id] = nil end
    end
end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

local function keyOf(name)
    local short = (name or ""):match("^([^-]+)") or name
    return BRutus:GetPlayerKey(short, GetRealmName())
end

----------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------
-- Upcoming events (not canceled; drops those >3h past), soonest first.
function Calendar:GetUpcoming(includePast)
    local nowT = GetServerTime()
    local list = {}
    for _, e in pairs(self:GetEvents()) do
        if not e.canceled and (includePast or (e.when or 0) > nowT - 3 * 3600) then
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b) return (a.when or 0) < (b.when or 0) end)
    return list
end

function Calendar:NextEvent()
    return self:GetUpcoming(false)[1]
end

-- Signup rollup for one event: status counts + role/class tallies over YES.
function Calendar:GetComposition(e)
    local comp = { yes = 0, tentative = 0, no = 0, roles = { TANK = 0, HEALER = 0, DPS = 0 }, classes = {} }
    for _, r in pairs(e and e.rsvps or {}) do
        comp[r.status] = (comp[r.status] or 0) + 1
        if r.status == "yes" then
            if r.role then comp.roles[r.role] = (comp.roles[r.role] or 0) + 1 end
            if r.class then comp.classes[r.class] = (comp.classes[r.class] or 0) + 1 end
        end
    end
    return comp
end

-- Digest line when the next event is within the next 24h.
function Calendar:GetDigestLines()
    local e = self:NextEvent()
    if not e then return nil end
    local nowT = GetServerTime()
    local dt = (e.when or 0) - nowT
    if dt > 0 and dt < 24 * 3600 then
        return { string.format(L["%s soon: %s at %s"], self:KindLabel(e.kind), e.title, date("%a %H:%M", e.when)) }
    end
    return nil
end

----------------------------------------------------------------------
-- Mutations (officer: create/cancel · member: rsvp)
----------------------------------------------------------------------
function Calendar:Create(title, when, size, note, kind)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    title = strtrim(title or "")
    when = tonumber(when)
    if title == "" or not when then
        BRutus:Print(L["An event needs a title and a date/time."])
        return
    end
    local e = {
        id = newId(), title = title, when = when, size = tonumber(size) or 25,
        note = note or "", kind = normalizeKind(kind),
        author = UnitName("player"), createdAt = GetServerTime(),
        canceled = false, rsvps = {},
    }
    self:GetEvents()[e.id] = e
    if BRutus.SyncService then
        local rev = BRutus.SyncService:NextRevision("event", e.id)
        BRutus.SyncService:Publish("event", "create", { event = {
            id = e.id, title = e.title, when = e.when, size = e.size,
            note = e.note, kind = e.kind, author = e.author, createdAt = e.createdAt,
        } }, { rev = rev })
    end
    self:Refresh()
    return e
end

function Calendar:Cancel(id)
    if not BRutus:IsOfficer() then return end
    local e = self:GetEvents()[id]
    if not e then return end
    e.canceled = true
    if BRutus.SyncService then
        local rev = BRutus.SyncService:NextRevision("event", id)
        BRutus.SyncService:Publish("event", "cancel", { id = id }, { rev = rev })
    end
    self:Refresh()
end

-- Officer edit of an existing event (title / date+time / size / description).
-- RSVPs are preserved; a fresh revision makes the change win on every client.
function Calendar:Update(id, title, when, size, note, kind)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    local e = self:GetEvents()[id]
    if not e or e.canceled then return end
    title = strtrim(title or "")
    when = tonumber(when)
    if title == "" or not when then
        BRutus:Print(L["An event needs a title and a date/time."])
        return
    end
    e.title = title
    e.when  = when
    e.size  = tonumber(size) or e.size or 25
    e.note  = note or ""
    e.kind  = normalizeKind(kind)
    if BRutus.SyncService then
        local rev = BRutus.SyncService:NextRevision("event", id)
        BRutus.SyncService:Publish("event", "update", { event = {
            id = e.id, title = e.title, when = e.when, size = e.size,
            note = e.note, kind = e.kind, author = e.author, createdAt = e.createdAt,
        } }, { rev = rev })
    end
    self:Refresh()
    return e
end

-- Officer removal of an event. Unlike Cancel (which only hides it), this drops
-- the record and records a tombstone so it cannot be resurrected by a create/
-- update that is still propagating on the guild channel.
function Calendar:Delete(id)
    if not BRutus:IsOfficer() then return end
    local e = self:GetEvents()[id]
    if not e then return end
    self:GetEvents()[id] = nil
    self:Tombstones()[id] = GetServerTime()
    if BRutus.SyncService then
        local rev = BRutus.SyncService:NextRevision("event", id)
        BRutus.SyncService:Publish("event", "delete", { id = id }, { rev = rev })
    end
    self:Refresh()
end

-- Set the local player's RSVP. status = "yes"/"tentative"/"no"; role optional.
function Calendar:Rsvp(id, status, role)
    local e = self:GetEvents()[id]
    if not e or e.canceled then return end
    e.rsvps = e.rsvps or {}
    local _, class = UnitClass("player")
    e.rsvps[keyOf(UnitName("player"))] = {
        status = status, role = role, class = class,
        name = UnitName("player"), ts = GetServerTime(),
    }
    if BRutus.SyncService then
        BRutus.SyncService:Publish("event", "rsvp", { id = id, status = status, role = role, class = class })
    end
    self:Refresh()
end

function Calendar:MyRsvp(e)
    return e and e.rsvps and e.rsvps[keyOf(UnitName("player"))] or nil
end

----------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------
function Calendar:OnSync(env, sender)
    local d = env.data
    if (env.act == "create" or env.act == "update") and d and d.event then
        local e = d.event
        if not self:IsDeleted(e.id) and BRutus.SyncService:ShouldApply("event", e.id, env.rev) then
            local existing = self:GetEvents()[e.id]
            e.rsvps    = (existing and existing.rsvps) or {}
            e.canceled = (existing and existing.canceled) or false
            self:GetEvents()[e.id] = e
            BRutus.SyncService:SetRevision("event", e.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "delete" and d and d.id then
        if BRutus.SyncService:ShouldApply("event", d.id, env.rev) then
            self:GetEvents()[d.id] = nil
            self:Tombstones()[d.id] = GetServerTime()
            BRutus.SyncService:SetRevision("event", d.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "cancel" and d and d.id then
        if BRutus.SyncService:ShouldApply("event", d.id, env.rev) then
            local e = self:GetEvents()[d.id]
            if e then e.canceled = true end
            BRutus.SyncService:SetRevision("event", d.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "allyRsvp" and d and d.id and d.key then
        -- Officer-gated by SyncService (allyRsvp is not a MEMBER_ACTION), so
        -- only an officer can seat an allied player. Clears the same pending
        -- entry on every other officer's queue.
        local e = self:GetEvents()[d.id]
        if e and not e.canceled then
            e.rsvps = e.rsvps or {}
            e.rsvps[d.key] = {
                status = "yes", role = d.role, class = d.class,
                name = d.name, guild = d.guild, ally = true, ts = GetServerTime(),
            }
            if e.allyPending then e.allyPending[d.key] = nil end
            self:Refresh()
        end
    elseif env.act == "allyDecline" and d and d.id and d.key then
        local e = self:GetEvents()[d.id]
        if e and e.allyPending then
            e.allyPending[d.key] = nil
            self:Refresh()
        end
    elseif env.act == "rsvp" and d and d.id and d.status then
        local e = self:GetEvents()[d.id]
        if e and not e.canceled then
            e.rsvps = e.rsvps or {}
            e.rsvps[keyOf(sender)] = {
                status = d.status, role = d.role, class = d.class,
                name = (sender or ""):match("^([^-]+)") or sender, ts = GetServerTime(),
            }
            self:Refresh()
        end
    end
end

function Calendar:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Cross-guild signups (alliance)
--
-- Policy chosen in the design round: an allied player signs up freely and lands
-- in a PENDING queue that an officer of the owning guild approves one by one.
--
-- WHERE THE QUEUE LIVES: only on the ambassador clients of the owning guild.
-- The signer whispers the ambassadors it can see online, so the request only
-- ever reaches officers and its author is the unforgeable envelope sender. That
-- is simpler and tighter than fanning unapproved requests through the guild
-- channel, where any guildmate could have forged one. The cost is that a
-- request needs at least one ambassador online, which the UI says plainly.
--
-- Approval publishes "allyRsvp", an OFFICER action (SyncService gates it), so
-- the accepted signup reaches every guildmate and clears the other officers'
-- queues.
----------------------------------------------------------------------
Calendar.ALLY_NOTE_MAX = 60
Calendar.ALLY_MAX_PENDING = 30
-- Confirmed signup names shipped per event. A raid is 40, and the payload is
-- names * events, so this is the knob that keeps the events domain small.
Calendar.ALLY_NAME_CAP = 40

-- Pure. Can this event still take an alliance signup right now?
-- Returns "ok" | "gone" | "canceled" | "past" | "full".
function Calendar._AllianceSlotDecision(event, yesCount, now)
    if type(event) ~= "table" then
        return "gone"
    end
    if event.canceled then
        return "canceled"
    end
    if (tonumber(event.when) or 0) <= (tonumber(now) or 0) then
        return "past"
    end
    if (tonumber(yesCount) or 0) >= (tonumber(event.size) or 25) then
        return "full"
    end
    return "ok"
end

-- Compact upcoming-events snapshot for the alliance `events` domain. Past and
-- canceled events are dropped, so the payload shrinks on its own over time.
-- Sorted by id so the change fingerprint is stable.
function Calendar._BuildAllianceEvents(events, now, cap)
    local out = {}
    if type(events) ~= "table" then
        return out
    end
    cap = tonumber(cap) or 50
    local ids = {}
    for id, e in pairs(events) do
        if type(id) == "string" and type(e) == "table" and not e.canceled
            and (tonumber(e.when) or 0) > (tonumber(now) or 0) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if #out >= cap then
            break
        end
        local e = events[id]
        local yes = 0
        -- Names of the confirmed signups, sorted, capped. These are what makes
        -- cross-guild conflict detection able to say "and 4 of these people are
        -- signed to both", instead of only "these two raids collide in time".
        -- Guild rosters are public in-game, so this exposes nothing new.
        local names = {}
        for _, r in pairs(e.rsvps or {}) do
            if r.status == "yes" then
                yes = yes + 1
                if r.name then
                    names[#names + 1] = r.name
                end
            end
        end
        table.sort(names)
        while #names > Calendar.ALLY_NAME_CAP do
            table.remove(names)
        end
        out[#out + 1] = {
            id = id, title = e.title, when = e.when, size = e.size,
            kind = e.kind, note = e.note, author = e.author, yes = yes, names = names,
        }
    end
    return out
end

-- Upcoming events published by ALLIED guilds, soonest first.
function Calendar:AllianceEvents()
    local sync, ally = GuildOS.AllianceSync, GuildOS.Alliance
    local pact = ally and ally:Get()
    local out = {}
    if not sync or not pact then
        return out
    end
    local mine = ally:MyGuildName()
    local now = GetServerTime()
    for guildName in pairs(pact.guilds) do
        if guildName ~= mine and not ally:IsBlocked(guildName) then
            local entry = sync:Remote(guildName, "events")
            if entry and type(entry.data) == "table" then
                for _, e in ipairs(entry.data) do
                    if (tonumber(e.when) or 0) > now then
                        out[#out + 1] = {
                            id = e.id, title = e.title, when = e.when, size = e.size,
                            kind = e.kind, note = e.note, yes = e.yes,
                            names = e.names, guild = guildName,
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.when or 0) ~= (b.when or 0) then return (a.when or 0) < (b.when or 0) end
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end

----------------------------------------------------------------------
-- Conflict detection
--
-- With seven guilds the hard part is not sharing calendars, it is noticing
-- that two raids collide AND that the same people signed up for both. This is
-- pure computation over data already synced: no new domain, no new traffic.
----------------------------------------------------------------------
Calendar.CONFLICT_WINDOW = 2 * 3600   -- events starting within 2h of each other

-- Pure. `mine` and `theirs` are arrays of { id, title, when, guild, names },
-- where `names` is the array of short names signed up "yes". Returns one row
-- per colliding pair, worst overlap first.
function Calendar._FindConflicts(mine, theirs, window)
    local out = {}
    if type(mine) ~= "table" or type(theirs) ~= "table" then
        return out
    end
    window = tonumber(window) or Calendar.CONFLICT_WINDOW

    for _, a in ipairs(mine) do
        for _, b in ipairs(theirs) do
            local gap = math.abs((tonumber(a.when) or 0) - (tonumber(b.when) or 0))
            if gap <= window then
                local inB = {}
                for _, n in ipairs(b.names or {}) do
                    inB[tostring(n):lower()] = n
                end
                local shared = {}
                for _, n in ipairs(a.names or {}) do
                    if inB[tostring(n):lower()] then
                        shared[#shared + 1] = n
                    end
                end
                table.sort(shared)
                out[#out + 1] = {
                    mine = a, theirs = b, gap = gap,
                    shared = shared, sharedCount = #shared,
                }
            end
        end
    end

    -- Most people double-booked first; then the tightest collision; then a
    -- stable id tie-break so the list never reshuffles between repaints.
    table.sort(out, function(x, y)
        if x.sharedCount ~= y.sharedCount then return x.sharedCount > y.sharedCount end
        if x.gap ~= y.gap then return x.gap < y.gap end
        return tostring(x.mine.id) .. tostring(x.theirs.id)
             < tostring(y.mine.id) .. tostring(y.theirs.id)
    end)
    return out
end

-- Announce collisions that are NEW to this session, so an allied guild
-- scheduling on top of us surfaces the moment their snapshot lands instead of
-- waiting for somebody to open the panel. Session-scoped on purpose: repeating
-- the same warning on every login would train people to ignore it.
Calendar._seenConflicts = {}

function Calendar:_AnnounceNewConflicts()
    local chat = GuildOS.AllianceChat
    if not chat then
        return
    end
    for _, c in ipairs(self:AllianceConflicts()) do
        local key = tostring(c.mine.id) .. "|" .. tostring(c.theirs.id)
        if not Calendar._seenConflicts[key] then
            Calendar._seenConflicts[key] = true
            local text
            if c.sharedCount > 0 then
                text = string.format(L["Conflict: your %s clashes with %s of %s, %d signed to both"],
                    c.mine.title or "?", c.theirs.title or "?", c.theirs.guild or "?", c.sharedCount)
            else
                text = string.format(L["Conflict: your %s clashes with %s of %s"],
                    c.mine.title or "?", c.theirs.title or "?", c.theirs.guild or "?")
            end
            chat:AddSystem(text, "warn")
        end
    end
end

-- Live wrapper: our upcoming events against every allied guild's.
function Calendar:AllianceConflicts()
    local ally = GuildOS.Alliance
    if not ally or not ally:Get() then
        return {}
    end
    local now = GetServerTime()
    local mine = {}
    for _, e in ipairs(self:GetUpcoming()) do
        if not e.canceled and (tonumber(e.when) or 0) > now then
            local names = {}
            for _, r in pairs(e.rsvps or {}) do
                if r.status == "yes" and r.name then
                    names[#names + 1] = r.name
                end
            end
            mine[#mine + 1] = { id = e.id, title = e.title, when = e.when, names = names }
        end
    end
    local theirs = {}
    for _, e in ipairs(self:AllianceEvents()) do
        theirs[#theirs + 1] = {
            id = e.id, title = e.title, when = e.when, guild = e.guild,
            names = e.names or {},
        }
    end
    return Calendar._FindConflicts(mine, theirs, Calendar.CONFLICT_WINDOW)
end

function Calendar:AlliancePending(e)
    local out = {}
    for key, p in pairs((e and e.allyPending) or {}) do
        out[#out + 1] = {
            key = key, name = p.name, guild = p.guild, role = p.role,
            note = p.note, class = p.class, level = p.level, ts = p.ts,
        }
    end
    table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return out
end

----------------------------------------------------------------------
-- Signer side
----------------------------------------------------------------------
function Calendar:RequestAllianceSlot(eventId, guildName, role, note)
    local ally = GuildOS.Alliance
    if not ally or not ally:Get() then
        return false, L["This guild is not in an alliance yet."]
    end
    if not eventId or not guildName then
        return false, L["Pick an alliance event first."]
    end
    local sent = ally:SendToAmbassadors(guildName, "EVT", {
        kind    = "signup",
        eventId = eventId,
        role    = (role == "TANK" or role == "HEALER" or role == "DPS") and role or "DPS",
        note    = BRutus:SanitizeUserText(note, Calendar.ALLY_NOTE_MAX),
    })
    if sent == 0 then
        return false, L["No officer of that guild is online right now. Try the alliance channel."]
    end
    return true
end

----------------------------------------------------------------------
-- Receiving side (the ChehulAlly "EVT" op)
----------------------------------------------------------------------
function Calendar:OnAllianceEvent(data, sender, senderGuild)
    if type(data) ~= "table" then
        return
    end
    if data.kind == "signup" then
        self:_ReceiveSignup(data, sender, senderGuild)
    elseif data.kind == "result" then
        self:_ReceiveSignupResult(data, senderGuild)
    end
end

local function allyKey(name)
    local short = (name or ""):match("^([^-]+)") or name
    return "ally:" .. tostring(short)
end

function Calendar:_ReceiveSignup(data, sender, senderGuild)
    local ally = GuildOS.Alliance
    local e = self:GetEvents()[data.eventId or ""]
    local comp = e and self:GetComposition(e)
    local decision = Calendar._AllianceSlotDecision(e, comp and comp.yes, GetServerTime())
    if decision ~= "ok" then
        ally:Send("EVT", { kind = "result", eventId = data.eventId, ok = false, why = decision }, sender)
        return
    end

    e.allyPending = e.allyPending or {}
    local count = 0
    for _ in pairs(e.allyPending) do count = count + 1 end
    if count >= Calendar.ALLY_MAX_PENDING and not e.allyPending[allyKey(sender)] then
        ally:Send("EVT", { kind = "result", eventId = data.eventId, ok = false, why = "full" }, sender)
        return
    end

    -- Class and level come from the synced allied roster, never from the
    -- payload, exactly like the guild map takes class from the roster.
    local class, level
    local sync = GuildOS.AllianceSync
    local snap = sync and sync:Remote(senderGuild, "roster")
    local short = (sender or ""):match("^([^-]+)") or sender
    if snap and type(snap.data) == "table" then
        for _, row in ipairs(snap.data) do
            if row.n == short then
                class, level = row.c, row.l
                break
            end
        end
    end

    e.allyPending[allyKey(sender)] = {
        name  = short,
        guild = senderGuild,
        role  = (data.role == "TANK" or data.role == "HEALER" or data.role == "DPS") and data.role or "DPS",
        note  = BRutus:SanitizeUserText(data.note, Calendar.ALLY_NOTE_MAX),
        class = class,
        level = level,
        ts    = GetServerTime(),
    }
    BRutus:Print(string.format(L["%s of %s wants a slot in %s."], short, senderGuild, e.title or "?"))
    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:AddSystem(
            string.format(L["%s of %s wants a slot in %s."], short, senderGuild, e.title or "?"), "warn")
    end
    self:Refresh()
end

function Calendar:_ReceiveSignupResult(data, senderGuild)
    local why = data.why
    if data.ok then
        BRutus:Print(string.format(L["%s approved your slot request."], senderGuild or "?"))
    elseif why == "full" then
        BRutus:Print(L["That event filled up before your request arrived."])
    elseif why == "past" or why == "gone" or why == "canceled" then
        BRutus:Print(L["That event is no longer open."])
    else
        BRutus:Print(string.format(L["%s declined your slot request."], senderGuild or "?"))
    end
    self:Refresh()
end

----------------------------------------------------------------------
-- Officer decisions
----------------------------------------------------------------------
function Calendar:ApproveAlliance(eventId, key)
    if not BRutus:IsOfficer() then
        return false, L["|cffFF4444Officers only.|r"]
    end
    local e = self:GetEvents()[eventId or ""]
    local p = e and e.allyPending and e.allyPending[key or ""]
    if not p then
        return false
    end
    local comp = self:GetComposition(e)
    if Calendar._AllianceSlotDecision(e, comp.yes, GetServerTime()) ~= "ok" then
        return self:DeclineAlliance(eventId, key, "full")
    end

    e.rsvps = e.rsvps or {}
    e.rsvps[key] = {
        status = "yes", role = p.role, class = p.class,
        name = p.name, guild = p.guild, ally = true, ts = GetServerTime(),
    }
    e.allyPending[key] = nil

    if BRutus.SyncService then
        BRutus.SyncService:Publish("event", "allyRsvp", {
            id = eventId, key = key, name = p.name, guild = p.guild,
            role = p.role, class = p.class,
        })
    end
    local ally = GuildOS.Alliance
    if ally then
        ally:SendToAmbassadors(p.guild, "EVT", { kind = "result", eventId = eventId, ok = true })
        ally:Send("EVT", { kind = "result", eventId = eventId, ok = true }, p.name)
    end
    self:Refresh()
    return true
end

function Calendar:DeclineAlliance(eventId, key, why)
    if not BRutus:IsOfficer() then
        return false, L["|cffFF4444Officers only.|r"]
    end
    local e = self:GetEvents()[eventId or ""]
    local p = e and e.allyPending and e.allyPending[key or ""]
    if not p then
        return false
    end
    e.allyPending[key] = nil
    if BRutus.SyncService then
        BRutus.SyncService:Publish("event", "allyDecline", { id = eventId, key = key })
    end
    local ally = GuildOS.Alliance
    if ally then
        ally:Send("EVT", { kind = "result", eventId = eventId, ok = false, why = why }, p.name)
    end
    self:Refresh()
    return true
end
