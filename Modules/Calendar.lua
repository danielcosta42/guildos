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
