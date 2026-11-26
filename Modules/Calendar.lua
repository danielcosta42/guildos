----------------------------------------------------------------------
-- Guild OS - Calendar / Signups
-- Officers create events; members RSVP (Yes/Tentative/No) with their role.
-- Synced via SyncService (domain "event"): create/update/cancel are officer
-- actions, rsvp is a member action recorded per player on every client. This is
-- the "Plan A" synced addon board — it does NOT depend on C_Calendar (which is
-- unreliable on the Anniversary client).
----------------------------------------------------------------------
local Calendar = {}
GuildOS.Calendar = Calendar
local L = GuildOS.L

Calendar.STATUS = { YES = "yes", TENTATIVE = "tentative", NO = "no" }
Calendar.ROLES  = { "TANK", "HEALER", "DPS" }

-- The sizes an event of a kind offers (issue #283): a dungeon is a party of five, every other kind the
-- game's raid sizes.
function Calendar.SizesFor(kind, raidSizes)
    if kind == "DUNGEON" then return { 5 } end
    return raidSizes
end

-- The same character, whether or not a realm is written: on retail the whole key, as IsOfficerByName.
local function sameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if GuildOS.Client and GuildOS.Client.isRetail and GuildOS.KeyOfRosterName then
        return GuildOS:KeyOfRosterName(a) == GuildOS:KeyOfRosterName(b)
    end
    return (a:match("^([^-]+)") or a) == (b:match("^([^-]+)") or b)
end

-- Whether a write from `sender` may touch an event (issue #283): an officer any; a creator who is not
-- one only an event under their own name, never a raid from the site. `existing` is the stored event
-- (nil for a new one), `incoming` what the write carries.
function Calendar.MayWriteRemote(existing, incoming, sender, officer)
    if officer then return true end
    -- Each one on its own: ipairs over { existing, incoming } stops at a nil existing, and a new event
    -- under somebody else's name went through unread.
    local function theirs(e)
        if type(e) ~= "table" then return true end
        if type(e.id) == "string" and e.id:sub(1, 4) == "web:" then return false end
        return sameName(e.author, sender)
    end
    return (existing ~= nil or incoming ~= nil) and theirs(existing) and theirs(incoming)
end

-- Whether this client may change or delete an event: an officer any, a creator their own (issue #283).
function Calendar:MayManage(e)
    if GuildOS:IsOfficer() then return true end
    return type(e) == "table" and not self:IsWebEvent(e) and GuildOS:MayCreateEvents()
        and sameName(e.author, GuildOS.Compat.PlayerName())
end

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

----------------------------------------------------------------------
-- The kinds a creator who is not an officer may create (issue #308)
----------------------------------------------------------------------
-- The guild's, as the ranks that create events are: an officer's choice, stamped and published on
-- guildcfg (`eventkinds`, newest wins, two in one second settle on the fewer kinds) and re-sent with
-- the ranks. Unset, every kind, as before #308; an officer always creates every kind. Held when an
-- event is created or changed here and again when one arrives (OnSync). The payload carries no `max`:
-- a client before this reads an unknown guildcfg action as the officer threshold, and one with no
-- `max` it ignores, so it goes on taking every kind from a member, as it always did.
local KINDS_FUTURE_SLACK = 300   -- seconds a stamp may run ahead of this client's clock, as the ranks'

-- Known kinds only, once each, in KINDS order; nil when `list` is no list.
function Calendar.CleanKinds(list)
    if type(list) ~= "table" then return nil end
    local want = {}
    for _, k in pairs(list) do
        if type(k) == "string" and KIND_SET[k] then want[k] = true end
    end
    local out = {}
    for _, k in ipairs(Calendar.KINDS) do
        if want[k] then out[#out + 1] = k end
    end
    return out
end

local function settings() return GuildOS.db and GuildOS.db.settings end

-- The kinds open to members, as a set; nil when the guild never chose (every kind).
function Calendar:MemberKinds()
    local s = settings()
    local list = s and Calendar.CleanKinds(s.eventKinds)
    if not list then return nil end
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    return set
end

function Calendar:KindOpenToMembers(kind)
    local set = self:MemberKinds()
    return set == nil or set[normalizeKind(kind)] == true
end

-- Whether this client creates an event of `kind`: an officer every kind, a rank that creates events
-- only a kind open to members.
function Calendar:MayCreateKind(kind)
    if GuildOS:IsOfficer() then return true end
    return GuildOS:MayCreateEvents() and self:KindOpenToMembers(kind)
end

-- The kinds this client creates, in KINDS order: the editor's pills.
function Calendar:CreatableKinds()
    local out = {}
    for _, k in ipairs(self.KINDS) do
        if self:MayCreateKind(k) then out[#out + 1] = k end
    end
    return out
end

-- Only an officer changes it; the stamp only moves forward. Whether it was taken.
function Calendar:SetMemberKinds(list)
    if not GuildOS:IsOfficer() then return false end
    local kinds = Calendar.CleanKinds(list)
    local s = settings()
    if not (kinds and s) then return false end
    s.eventKinds = kinds
    s.eventKindsAt = math.max(GetServerTime(), (s.eventKindsAt or 0) + 1)
    self:PublishMemberKinds()
    return true
end

-- To the guild when it changes, and on the officers' regular sync and their answer to a request. Only
-- a choice somebody made: a guild that never chose sends nothing.
function Calendar:PublishMemberKinds()
    local s = settings()
    local kinds = s and s.eventKindsAt and Calendar.CleanKinds(s.eventKinds)
    if not (kinds and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    GuildOS.SyncService:Publish("guildcfg", "eventkinds", { kinds = kinds }, { rev = s.eventKindsAt })
end

-- From an officer over GUILD (SyncService checked both). Two changes in the same second settle on the
-- fewer kinds, then on the list that, written in KINDS order and joined by commas, sorts first as text
-- ("DUNGEON" before "RAID"): the same answer on every client whatever the order.
function Calendar:OnMemberKindsSync(env)
    local data = type(env) == "table" and env.data
    local s = settings()
    if type(data) ~= "table" or not s then return end
    local kinds = Calendar.CleanKinds(data.kinds)
    local at = tonumber(env.rev)
    -- `at > 0` also turns away NaN, which compares false to everything.
    if not (kinds and at and at > 0 and at < math.huge) then return end
    at = math.min(at, GetServerTime() + KINDS_FUTURE_SLACK)
    local held, heldKinds = s.eventKindsAt, Calendar.CleanKinds(s.eventKinds)
    if held and at < held then return end
    if held and at == held and heldKinds then
        if #kinds > #heldKinds then return end
        if #kinds == #heldKinds and table.concat(kinds, ",") >= table.concat(heldKinds, ",") then return end
    end
    s.eventKinds, s.eventKindsAt = kinds, at
    self:Refresh()
end

-- The dungeons the editor offers for a Dungeon event (issue #308), as guildos.me offers them to book
-- (#491): the game's own that have a boss to clear, by name, then the classic ones guilds book most.
-- Names only: a pick becomes the title, and "Other" leaves the title to be typed. Empty where the game
-- has no catalogue (Anniversary, retail), where the title is typed as before.
function Calendar:DungeonChoices()
    local cat = GuildOS.ForeverDungeons
    if not cat then return {} end
    local out = {}
    for _, d in pairs(cat.byInstance or {}) do
        if type(d.name) == "string" and type(d.bosses) == "table" and #d.bosses > 0 then out[#out + 1] = d.name end
    end
    table.sort(out)
    for _, name in ipairs(cat.classic or {}) do out[#out + 1] = name end
    return out
end

function Calendar:Initialize()
    GuildOS.db.calendar = GuildOS.db.calendar or { events = {} }
    GuildOS.db.calendar.events = GuildOS.db.calendar.events or {}
    GuildOS.db.calendar.deleted = GuildOS.db.calendar.deleted or {}
    self:PruneTombstones()
    if GuildOS.SyncService then
        GuildOS.SyncService:On("event", function(env, sender) Calendar:OnSync(env, sender) end)
    end
    -- Repeating events (#267): an officer's client fills the next weeks in from OFFICER_START
    -- (Core/Core.lua), which waits for the rank as long as it takes.
end

function Calendar:GetEvents() return GuildOS.db.calendar.events end

-- Deletion tombstones: a small id->timestamp set so a hard delete cannot be
-- undone by a straggling create/update for the same event still in flight on
-- the guild channel, and so old events truly disappear instead of lingering
-- forever as canceled records. Pruned after TOMBSTONE_TTL.
local TOMBSTONE_TTL = 30 * 86400
local YEARLY_DAYS = 733   -- how far ahead a yearly series is filled in (#358)
function Calendar:Tombstones() return GuildOS.db.calendar.deleted end
function Calendar:IsDeleted(id) return self:Tombstones()[id] ~= nil end

-- Series ended (#267): series id -> when. Kept far longer than a tombstone, since a series can be
-- ended weeks before a stale officer's client tries to fill it in again.
local ENDED_TTL = 365 * 86400
function Calendar:EndedSeries()
    GuildOS.db.calendar.ended = GuildOS.db.calendar.ended or {}
    return GuildOS.db.calendar.ended
end
function Calendar:IsSeriesEnded(sid) return sid ~= nil and self:EndedSeries()[sid] ~= nil end

function Calendar:PruneTombstones()
    local now = GetServerTime()
    for id, ts in pairs(self:Tombstones()) do
        -- A series date deleted ahead of time stays deleted until its day has passed: a yearly date
        -- is filled in up to a year ahead, far past TOMBSTONE_TTL (#358).
        -- Only a real date, no further ahead than a series is ever filled in.
        local y, m, d = tostring(id):match(":(%d%d%d%d)(%d%d)(%d%d)$")
        y, m, d = tonumber(y), tonumber(m), tonumber(d)
        local dayOf = y and m >= 1 and m <= 12 and d >= 1 and d <= 31
            and time({ year = y, month = m, day = d, hour = 23, min = 59 })
        local ahead = dayOf and dayOf > now and dayOf <= now + YEARLY_DAYS * 86400
        if (ts or 0) < now - TOMBSTONE_TTL and not ahead then self:Tombstones()[id] = nil end
    end
    for sid, ts in pairs(self:EndedSeries()) do
        if (ts or 0) < now - ENDED_TTL then self:EndedSeries()[sid] = nil end
    end
end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

local function keyOf(name)
    local short = (name or ""):match("^([^-]+)") or name
    -- Retail: the sender's own realm, or two connected-realm namesakes are one person (ADR-0026).
    local realm = GuildOS.Client.isRetail and (name or ""):match("^[^-]+%-(.+)$") or GetRealmName()
    return GuildOS:GetPlayerKey(short, realm)
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
    -- A raid planned on the site counts the site's answers: nobody signs up for it in the game (#146).
    -- An allied seat is still approved in the game, and counts with them.
    -- One of the site's events that is not a raid (#652): the site's counts, with nobody's name or role.
    if self:IsSiteEvent(e) then
        comp.yes, comp.tentative = e.site.going or 0, e.site.maybe or 0
        return comp
    end
    local answers
    if self:IsWebEvent(e) then
        answers = self:WebSignups(e)
        for _, r in pairs(e.rsvps or {}) do
            if r.ally then answers[#answers + 1] = r end
        end
    else
        answers = e and e.rsvps or {}
    end
    for _, r in pairs(answers) do
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
        return { string.format(L["%s soon: %s at %s"], self:KindLabel(e.kind), e.title, GuildOS:LocalDate("%a %H:%M", e.when)) }
    end
    return nil
end

----------------------------------------------------------------------
-- Mutations (officer: create/cancel · member: rsvp)
----------------------------------------------------------------------
local function newEvent(title, when, size, note, kind, shareAlliance)
    return {
        id = newId(), title = title, when = when, size = tonumber(size) or GuildOS.Client.defaultRaidSize,
        note = note or "", kind = normalizeKind(kind),
        author = GuildOS.Compat.PlayerName(), createdAt = GetServerTime(),
        canceled = false, rsvps = {},
        -- OPT IN. An event is private to the guild unless an officer says so,
        -- and a MISSING field means private, so every event that existed
        -- before this feature stays inside the guild.
        shareAlliance = shareAlliance and true or false,
    }
end

-- Stores a new event and tells the guild.
function Calendar:_Add(e)
    self:GetEvents()[e.id] = e
    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", e.id)
        GuildOS.SyncService:Publish("event", "create", { event = {
            id = e.id, title = e.title, when = e.when, size = e.size,
            note = e.note, kind = e.kind, author = e.author, createdAt = e.createdAt,
            shareAlliance = e.shareAlliance, series = e.series,
        } }, { rev = rev })
    end
end

-- The rank, the kind (issue #308) and the fields every new event needs; nil, with the reason said, when
-- one is missing.
local function validNew(title, when, kind)
    if not GuildOS:MayCreateEvents() then
        GuildOS:Print(L["|cffFF4444Your rank cannot create events.|r"])
        return nil
    end
    if not Calendar:MayCreateKind(kind) then
        GuildOS:Print(L["|cffFF4444Your rank cannot create this type of event.|r"])
        return nil
    end
    title = strtrim(title or "")
    when = tonumber(when)
    if title == "" or not when then
        GuildOS:Print(L["An event needs a title and a date/time."])
        return nil
    end
    return title, when
end

function Calendar:Create(title, when, size, note, kind, shareAlliance)
    title, when = validNew(title, when, kind)
    if not title then return end
    local e = newEvent(title, when, size, note, kind, shareAlliance)
    self:_Add(e)
    self:Refresh()
    return e
end

----------------------------------------------------------------------
-- Events that repeat (#267). A series is plain events, one per date, each carrying the rule in
-- `series` = { id, rep, first, hour, min, untilT? }: a client from before this sees ordinary events,
-- every date keeps its own answers, and the id is the series' plus the date, so two officers filling
-- the same series in reach the same events. The calendar holds SERIES_DAYS ahead, and an officer's
-- client fills the rest in as days pass (TopUpSeries). A date deleted by hand leaves a tombstone, which
-- outlives the window, so it is not brought back.
----------------------------------------------------------------------
Calendar.REPEATS = { "none", "weekly", "biweekly", "daily", "everyother", "monthnth", "monthday", "yearly" }
local SERIES_DAYS = 28    -- under TOMBSTONE_TTL
local SERIES_CAP = 16     -- dates per fill, whatever the rule
local STEP_DAYS = { weekly = 7, biweekly = 14, daily = 1, everyother = 2 }
local MONTHLY = { monthnth = true, monthday = true }
-- A yearly date (#358) is a year apart: the window reaches two years and a fill makes the next two,
-- so a birthday is always on the calendar, and skipping one year (deleting that date) still leaves the
-- series a date to be found by and filled in from. A client from before this reads the rule as unknown
-- and keeps the date as an ordinary event.
local YEARLY_CAP = 2
local function knownRep(rep) return STEP_DAYS[rep] or MONTHLY[rep] or rep == "yearly" end

local function noonOf(y, m, d) return time({ year = y, month = m, day = d, hour = 12 }) end
local function daysIn(y, m) return date("*t", noonOf(y, m + 1, 0)).day end

-- What a repeat reads off its first date: the weekday, which one of the month it is, the day.
function Calendar.RepeatOf(rep, first)
    local t = date("*t", first)
    return { rep = rep, nth = math.floor((t.day - 1) / 7) + 1, wday = t.wday, day = t.day }
end

-- Pure: the dates of `rule` from `first`, within [fromT, toT], at most `cap`. On the wall clock: the
-- hour stays the hour across a summer-time change. A month without the day is skipped, never moved.
function Calendar._Occurrences(rule, first, fromT, toT, cap)
    local base = date("*t", first)
    local hour, min = rule.hour or base.hour, rule.min or base.min
    local out = {}
    local function keep(ts)
        if ts >= first and ts >= fromT and ts <= toT and #out < cap then out[#out + 1] = ts end
    end
    local step = STEP_DAYS[rule.rep]
    if step then
        -- One step early: a summer-time change can move a date an hour across fromT.
        local k = math.max(0, math.floor((fromT - first) / (step * 86400)) - 1)
        while #out < cap do
            local ts = time({ year = base.year, month = base.month, day = base.day + k * step, hour = hour, min = min })
            if ts > toT then break end
            keep(ts)
            k = k + 1
        end
    elseif MONTHLY[rule.rep] then
        local r = Calendar.RepeatOf(rule.rep, first)
        for k = 0, 600 do
            local m1 = date("*t", noonOf(base.year, base.month + k, 1))
            local day = rule.rep == "monthday" and r.day or (1 + (r.wday - m1.wday) % 7 + (r.nth - 1) * 7)
            if day <= daysIn(m1.year, m1.month) then
                local ts = time({ year = m1.year, month = m1.month, day = day, hour = hour, min = min })
                if ts > toT or #out >= cap then break end
                keep(ts)
            end
        end
    elseif rule.rep == "yearly" then
        -- The same day every year; 29 February falls on the 28th when the year has none.
        for k = 0, 200 do
            local y = base.year + k
            local day = math.min(base.day, daysIn(y, base.month))
            local ts = time({ year = y, month = base.month, day = day, hour = hour, min = min })
            if ts > toT or #out >= cap then break end
            keep(ts)
        end
    else
        keep(first)
    end
    return out
end

local function occurrenceId(sid, ts) return sid .. ":" .. date("%Y%m%d", ts) end

-- A series' rule, cleaned like anything off the guild channel, or nil.
local function cleanSeries(s)
    if type(s) ~= "table" or type(s.id) ~= "string" or not tonumber(s.first) then return nil end
    if not knownRep(s.rep) then return nil end
    local function n(v, lo, hi) v = tonumber(v); return (v and v >= lo and v <= hi) and math.floor(v) or nil end
    return { id = s.id:sub(1, 40), rep = s.rep, first = tonumber(s.first), hour = n(s.hour, 0, 23),
             min = n(s.min, 0, 59), untilT = tonumber(s.untilT) }
end

-- Creates the dates of `template`'s series from now (or its first date) to SERIES_DAYS on, the ones
-- not there yet and never deleted. Returns how many.
function Calendar:_FillSeries(template, now)
    local s = template.series
    local from = math.max(now, s.first)
    local yearly = s.rep == "yearly"
    local to = from + (yearly and YEARLY_DAYS or SERIES_DAYS) * 86400 - 1   -- four weeks, the fifth week's date not yet
    if s.untilT then to = math.min(to, s.untilT) end
    local n = 0
    for _, ts in ipairs(Calendar._Occurrences(s, s.first, from, to, yearly and YEARLY_CAP or SERIES_CAP)) do
        local id = occurrenceId(s.id, ts)
        if not self:GetEvents()[id] and not self:IsDeleted(id) then
            local e = newEvent(template.title, ts, template.size, template.note, template.kind, template.shareAlliance)
            e.id = id
            e.series = cleanSeries(s)
            self:_Add(e)
            n = n + 1
        end
    end
    return n
end

-- An officer's event that repeats: `rep` one of REPEATS. "none" is an ordinary event. Returns how
-- many dates were created, nil when nothing could be.
function Calendar:CreateSeries(title, when, size, note, kind, shareAlliance, rep)
    if not knownRep(rep) then
        return self:Create(title, when, size, note, kind, shareAlliance) and 1 or nil
    end
    title, when = validNew(title, when, kind)
    if not title then return nil end
    local t = date("*t", when)
    local template = newEvent(title, when, size, note, kind, shareAlliance)
    template.series = { id = newId(), rep = rep, first = when, hour = t.hour, min = t.min }
    local n = self:_FillSeries(template, GetServerTime())
    self:Refresh()
    return n
end

-- An officer's client fills every series in up to SERIES_DAYS ahead, from its latest date (whose
-- title, hour and the rest the new ones copy). An ended series is never filled in, and one that
-- stops at a date stops there. Only a client on the series' own clock fills it in: the hour is a wall
-- clock, and an officer in another time zone would put the dates at their own 20:00 and name them
-- after their own calendar day. A date of the series that reads its hour here proves the clock.
-- Returns how many.
function Calendar:TopUpSeries()
    if not GuildOS:IsOfficer() then return 0 end
    local latest, untilT, sameClock = {}, {}, {}
    for _, e in pairs(self:GetEvents()) do
        local s = cleanSeries(e.series)
        if s and not self:IsSeriesEnded(s.id) then
            if s.untilT then untilT[s.id] = math.min(untilT[s.id] or s.untilT, s.untilT) end
            if not latest[s.id] or (e.when or 0) > (latest[s.id].when or 0) then latest[s.id] = e end
            local t = date("*t", e.when or 0)
            if s.hour == nil or (t.hour == s.hour and t.min == (s.min or 0)) then sameClock[s.id] = true end
        end
    end
    local n = 0
    for sid, e in pairs(latest) do
        if sameClock[sid] then
            local template = { title = e.title, size = e.size, note = e.note, kind = e.kind,
                               shareAlliance = e.shareAlliance, series = cleanSeries(e.series) }
            template.series.untilT = untilT[sid]
            n = n + self:_FillSeries(template, GetServerTime())
        end
    end
    if n > 0 then self:Refresh() end
    return n
end

local function sameSeries(e, sid) return type(e.series) == "table" and e.series.id == sid end

-- An officer's edit of one date and every later one of its series: each keeps its own day and takes
-- the new hour, title and the rest. Earlier dates stay; answers survive. Not a series: Update.
function Calendar:UpdateSeries(id, title, when, size, note, kind, shareAlliance)
    local e = self:GetEvents()[id]
    if not e or type(e.series) ~= "table" or not self:MayManage(e) then
        return self:Update(id, title, when, size, note, kind, shareAlliance)
    end
    when = tonumber(when) or e.when
    local t = date("*t", when)
    local sid, from = e.series.id, e.when
    local later = {}
    for oid, o in pairs(self:GetEvents()) do
        if sameSeries(o, sid) and (o.when or 0) >= from and not o.canceled then later[#later + 1] = oid end
    end
    for _, oid in ipairs(later) do
        local o = self:GetEvents()[oid]
        local d = date("*t", o.when)
        local at = oid == id and when or time({ year = d.year, month = d.month, day = d.day, hour = t.hour, min = t.min })
        o.series.hour, o.series.min = t.hour, t.min
        self:Update(oid, title, at, size, note, kind, shareAlliance)
    end
end

-- An officer ends a series from one date on: that date and every later one go, and the series is
-- marked ended for every client, a `delete` of the series' own id (a client before this keeps it as a
-- harmless tombstone). The latest date before the end also says where it ended. Not a series: Delete.
function Calendar:EndSeries(id)
    local e = self:GetEvents()[id]
    if not e or type(e.series) ~= "table" or not self:MayManage(e) then return self:Delete(id) end
    local sid, cut = e.series.id, e.when
    local drop, last = {}, nil
    for oid, o in pairs(self:GetEvents()) do
        if sameSeries(o, sid) then
            if (o.when or 0) >= cut then
                drop[#drop + 1] = oid
            elseif not o.canceled and (not last or (o.when or 0) > (last.when or 0)) then
                last = o
            end
        end
    end
    for _, oid in ipairs(drop) do self:Delete(oid) end
    self:EndedSeries()[sid] = GetServerTime()
    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", sid)
        GuildOS.SyncService:Publish("event", "delete", { id = sid, series = true }, { rev = rev })
    end
    if last then
        last.series.untilT = cut - 1
        self:Update(last.id, last.title, last.when, last.size, last.note, last.kind, last.shareAlliance)
    end
end

----------------------------------------------------------------------
-- A raid planned on the website, as one guild event.
--
-- The id is derived from the site's raidId rather than minted, and that
-- is the whole point: Calendar:Create mints a random one and publishes
-- it, so every officer running the companion would have turned the same
-- night into a different event and broadcast it. Sharing the id lets the
-- sync converge on one, whoever gets there first.
--
-- Officers only, like every other write here. A member running the
-- companion simply does not publish; the event reaches them the ordinary
-- way, from an officer who did.
----------------------------------------------------------------------
local WEB_ID_PREFIX = "web:"

-- A raid planned on the site. Its id is the site's, so every client can tell, whoever imported it;
-- `e.web` only ever existed on the importing officer's (#146).
function Calendar:IsWebEvent(e)
    return type(e) == "table" and type(e.id) == "string" and e.id:sub(1, #WEB_ID_PREFIX) == WEB_ID_PREFIX
end

-- Who answered on the site, as the guild's calendar shows it (#146): a copy for reading, since
-- signing up happens there. Built from the companion's roster on an officer's client, and cleaned
-- wherever it is read, like anything off the guild channel: the names end up in text, and a client
-- from before this kept what it was sent as it came.
local WEB_STATUS = { yes = true, pending = true, tentative = true, wait = true, no = true }
local WEB_ROLE = { TANK = "TANK", HEALER = "HEALER", DPS = "DPS", MELEE = "DPS", RANGED = "DPS" }
local WEB_SIGNUPS_MAX = 80

local function cleanWebSignups(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, s in ipairs(list) do
        if #out >= WEB_SIGNUPS_MAX then break end
        if type(s) == "table" and type(s.name) == "string" and WEB_STATUS[s.status] then
            local name = GuildOS:SanitizeUserText(s.name, 48)
            if name ~= "" then
                out[#out + 1] = {
                    name = name,
                    class = type(s.class) == "string" and GuildOS:SanitizeUserText(s.class, 16) or "",
                    role = WEB_ROLE[s.role] or "DPS",
                    status = s.status,
                }
            end
        end
    end
    return out
end

--- The site's answers on a web raid, cleaned; an empty list for any other event.
function Calendar:WebSignups(e)
    return self:IsWebEvent(e) and cleanWebSignups(e.signups) or {}
end

-- The site's answers grouped the way the raid's Discord post groups them: late is coming, somebody
-- waiting for the officers' approval is not counted until approved, the waitlist is its own line,
-- and somebody the officers refused is out. A roster from a site before v2 has only the invitable,
-- all of them coming.
local function webSignupsOf(roster)
    local list = {}
    for _, s in ipairs(roster.signups or roster.members or {}) do
        local status = "yes"
        if s.status == "no" or s.why == "refused" then status = "no"
        elseif s.status == "tentative" then status = "tentative"
        elseif s.why == "wait" then status = "wait"
        elseif s.why == "pending" then status = "pending" end
        list[#list + 1] = { name = s.name, class = s.class, role = s.slot, status = status }
    end
    return cleanWebSignups(list)
end

local function signupsKey(list)
    local t = {}
    for _, s in ipairs(list or {}) do t[#t + 1] = s.name .. ":" .. s.status .. ":" .. s.role end
    return table.concat(t, ",")
end

-- An event as it goes out on the guild channel: everything a create or an update replaces on every
-- client. Left out, a field goes: the site's list once did, and what the raid was put in the game's
-- calendar as would (#263).
local function wireOf(e)
    local site, canceled = type(e.site) == "table" and e.site or nil, nil
    if site then canceled = e.canceled == true end
    return {
        id = e.id, title = e.title, when = e.when, size = e.size,
        note = e.note, kind = e.kind, author = e.author, createdAt = e.createdAt,
        shareAlliance = e.shareAlliance, signups = e.signups, signupsAt = e.signupsAt,
        game = e.game, gameAt = e.gameAt, clock = e.clock, series = e.series,
        -- An event from the site that is not a raid (#652): its place and counts, and whether it is cancelled, so
        -- one the site sends again after it left comes back on every client, not only on the importing officer's.
        site = site, canceled = canceled,
    }
end

-- The raid's time on the clock it was created on (guildos-web #411): { year, month, day, hour, minute },
-- a real date and time, else nil. The game's calendar shows the raid as these numbers.
local function cleanClock(c)
    if type(c) ~= "table" then return nil end
    local y, m, d, h, mi = tonumber(c.year), tonumber(c.month), tonumber(c.day), tonumber(c.hour), tonumber(c.minute)
    local whole = function(v, lo, hi) return v and v == math.floor(v) and v >= lo and v <= hi end
    if not (whole(y, 2000, 2200) and whole(m, 1, 12) and whole(d, 1, 31) and whole(h, 0, 23) and whole(mi, 0, 59)) then return nil end
    return { year = y, month = m, day = d, hour = h, minute = mi }
end

local function sameClock(a, b)
    if a == nil or b == nil then return a == b end
    return a.year == b.year and a.month == b.month and a.day == b.day and a.hour == b.hour and a.minute == b.minute
end

-- What a site raid was put in the game's calendar as, cleaned like anything off the guild channel:
-- { title, at }, false once taken out of it, nil when unknown.
local function cleanGame(g)
    if g == false then return false end
    if type(g) ~= "table" or type(g.title) ~= "string" or not tonumber(g.at) then return nil end
    return { title = GuildOS:SanitizeUserText(g.title, 64), at = tonumber(g.at) }
end

-- What an event from the site that is not a raid carries beside a raid's fields (#652): { where?, going, maybe },
-- cleaned like anything off the guild channel; nil when it is none.
local SITE_COUNT_MAX = 100000
local function cleanSite(v)
    if type(v) ~= "table" then return nil end
    local function count(n)
        n = GuildOS.Finite(n)
        return n and n == math.floor(n) and n >= 0 and n <= SITE_COUNT_MAX and n or 0
    end
    local where = type(v.where) == "string" and GuildOS:SanitizeUserText(v.where, 240) or ""
    return { where = where ~= "" and where or nil, going = count(v.going), maybe = count(v.maybe) }
end

local function sameSite(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.where == b.where and a.going == b.going and a.maybe == b.maybe
end

--- Whether an event is one of the site's that is not a raid (#652): a site event (`web:<id>`) with what only those
--- carry. Its answers are the site's counts, it has nobody to invite and it never goes to the game's own calendar.
function Calendar:IsSiteEvent(e)
    return self:IsWebEvent(e) and type(e.site) == "table"
end

function Calendar:WebEventId(roster)
    if not roster or roster.raidId == nil or roster.raidId == "" then return nil end
    return WEB_ID_PREFIX .. tostring(roster.raidId)
end

--- Create or refresh the guild event for a roster that came from the site.
--- Returns the event, or nil when there is nothing to publish.
---
--- `answeredAt` is when the site gave this roster (the companion's ack). The list of answers only
--- moves forward: an officer whose companion stopped, with an old Inbox.lua left behind, would
--- otherwise send the guild old answers at every login, and a fresher officer send them back at
--- theirs (#146; ADR-0025 does the same for cores). Clamped to now, so a PC clock running ahead
--- cannot freeze the list.
function Calendar:UpsertWebRaid(roster, answeredAt)
    local id = self:WebEventId(roster)
    if not id then return nil end
    if not GuildOS:IsOfficer() then return nil end

    local when = tonumber(roster.startsAt) or 0
    if when <= 0 then return nil end
    local clock = cleanClock(roster.clock)

    local title = strtrim(roster.title or "")
    if title == "" then title = roster.instance or L["Raid"] end
    local size = tonumber(roster.size) or 0               -- the site's capacity for the raid
    if size < 1 then size = #(roster.members or {}) end
    if size < 1 then size = GuildOS.Client.defaultRaidSize end

    local events = self:GetEvents()
    local e = events[id]
    answeredAt = math.min(tonumber(answeredAt) or 0, GetServerTime())
    local signups, signupsAt = webSignupsOf(roster), answeredAt
    if e and e.signups and (e.signupsAt or 0) >= answeredAt then
        signups, signupsAt = self:WebSignups(e), e.signupsAt or 0
    end

    -- Nothing moved: republishing would only churn the guild channel and bump
    -- a revision for a change nobody made.
    if e and not e.canceled and e.title == title and e.when == when and e.size == size and sameClock(e.clock, clock)
        and signupsKey(self:WebSignups(e)) == signupsKey(signups) then
        -- The same answers, said again later: the time moves here and nothing goes out. The
        -- companion rewrites its inbox every hour whether or not anybody answered.
        e.signupsAt = math.max(e.signupsAt or 0, signupsAt)
        return e
    end

    local isNew = (e == nil)
    if isNew then
        e = {
            id = id, author = GuildOS.Compat.PlayerName(), createdAt = GetServerTime(),
            canceled = false, rsvps = {},
            -- Private to the guild, like anything else born here. The site
            -- hands over a roster; it does not get to widen the audience.
            shareAlliance = false,
        }
        events[id] = e
    end

    e.canceled = false
    e.title = title
    e.when  = when
    e.clock = clock
    e.size  = size
    e.kind  = "RAID"
    e.note  = L["Planned on the website."]
    -- Signing up happens on the site; the guild reads the list where it looks (#146).
    e.signups, e.signupsAt = signups, signupsAt

    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", id)
        GuildOS.SyncService:Publish("event", isNew and "create" or "update", { event = wireOf(e) }, { rev = rev })
    end
    self:Refresh()
    return e
end

--- Create or refresh the guild event for one of the site's events that is not a raid (guildos-web #652, the
--- GOSGILD1's `events`, read by CompanionImport:SiteEvents): of its type (SOCIAL, PVP, OTHER), from the site, with
--- its place and "N going · N maybe", nobody to invite and no list of names. Officers only, like UpsertWebRaid, and
--- forward only by `answeredAt` (the companion's ack): an older inbox than the one that brought what is here
--- changes nothing. Returns the event, or nil.
function Calendar:UpsertSiteEvent(ev, answeredAt)
    if type(ev) ~= "table" or type(ev.id) ~= "string" or ev.id == "" then return nil end
    if not GuildOS:IsOfficer() then return nil end
    local id = WEB_ID_PREFIX .. ev.id
    local when = tonumber(ev.startsAt) or 0
    if when <= 0 or self:IsDeleted(id) then return nil end

    local events = self:GetEvents()
    local e = events[id]
    -- The site's id names a raid or an event, never both: a raid of this id is left as it is.
    if e and not self:IsSiteEvent(e) then return nil end
    answeredAt = math.min(tonumber(answeredAt) or 0, GetServerTime())
    if e and (tonumber(e.signupsAt) or 0) > answeredAt then return e end

    local kind = normalizeKind(ev.kind)
    local title = GuildOS:SanitizeUserText(ev.title, 192)
    if title == "" then title = self:KindLabel(kind) end
    local clock = cleanClock(ev.clock)
    local site = cleanSite(ev)

    -- Nothing moved: the same event said again later only moves its time. The note is this client's language and
    -- is not compared, or two officers reading two languages would republish it at every login.
    if e and not e.canceled and e.title == title and e.when == when and e.kind == kind and sameClock(e.clock, clock)
        and sameSite(e.site, site) then
        e.signupsAt = math.max(tonumber(e.signupsAt) or 0, answeredAt)
        return e
    end

    local isNew = (e == nil)
    if isNew then
        e = {
            id = id, author = GuildOS.Compat.PlayerName(), createdAt = GetServerTime(),
            rsvps = {}, shareAlliance = false, size = GuildOS.Client.defaultRaidSize,
        }
        events[id] = e
    end
    e.canceled = false
    e.title, e.when, e.clock, e.kind = title, when, clock, kind
    e.note = site.where and string.format(L["From the website. Where: %s"], site.where) or L["From the website."]
    -- Answered on the site, counted there: no names travel, and nobody answers it in the game.
    e.signups, e.signupsAt, e.site = {}, answeredAt, site

    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", id)
        GuildOS.SyncService:Publish("event", isNew and "create" or "update", { event = wireOf(e) }, { rev = rev })
    end
    self:Refresh()
    return e
end

--- Takes off the calendar the site's events that are not raids which the site no longer sends (#652), where the
--- inbox can tell (`info`, CompanionImport:SiteEventsInfo; the reasoning is GameCalendar.SiteEventGone). Cancelled,
--- as an officer cancels one, so it goes on every client; it comes back if the site sends it again.
function Calendar:DropSiteEvents(info)
    local GC = GuildOS.GameCalendar
    if not (GuildOS:IsOfficer() and GC and GC.SiteEventGone and type(info) == "table") then return end
    local now, gone = GetServerTime(), {}
    for id, e in pairs(self:GetEvents()) do
        if not e.canceled and self:IsSiteEvent(e) and GC.SiteEventGone(e, info, now) then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do self:Cancel(id) end
end

--- What a site raid was put in the game's calendar as ({ title, at }), or false once taken out of it,
--- shared with the other officers (#263). Stamped with the time, so on another client the newer
--- answer wins and an update from a client before this, which carries none, takes nothing back.
function Calendar:SetGameEvent(id, game)
    local e = self:GetEvents()[id]
    if not e or not self:IsWebEvent(e) then return end
    e.game = game or false
    e.gameAt = GetServerTime()
    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", id)
        GuildOS.SyncService:Publish("event", "update", { event = wireOf(e) }, { rev = rev })
    end
    self:Refresh()
end

function Calendar:Cancel(id)
    local e = self:GetEvents()[id]
    if not self:MayManage(e) then return end
    if not e then return end
    e.canceled = true
    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", id)
        GuildOS.SyncService:Publish("event", "cancel", { id = id }, { rev = rev })
    end
    self:Refresh()
end

-- Officer edit of an existing event (title / date+time / size / description).
-- RSVPs are preserved; a fresh revision makes the change win on every client.
function Calendar:Update(id, title, when, size, note, kind, shareAlliance)
    if not self:MayManage(self:GetEvents()[id]) then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    local e = self:GetEvents()[id]
    if not e or e.canceled then return end
    -- An event becomes only a kind its creator may create (#308). Kept as it is, it stays theirs to edit,
    -- reschedule and end, whatever the officers closed since.
    if normalizeKind(kind) ~= normalizeKind(e.kind) and not self:MayCreateKind(kind) then
        GuildOS:Print(L["|cffFF4444Your rank cannot create this type of event.|r"])
        return
    end
    title = strtrim(title or "")
    when = tonumber(when)
    if title == "" or not when then
        GuildOS:Print(L["An event needs a title and a date/time."])
        return
    end
    e.title = title
    e.when  = when
    e.size  = tonumber(size) or e.size or GuildOS.Client.defaultRaidSize
    e.note  = note or ""
    e.kind  = normalizeKind(kind)
    -- nil leaves the current setting alone, so a caller that does not know
    -- about sharing can never silently expose an event.
    if shareAlliance ~= nil then
        e.shareAlliance = shareAlliance and true or false
    end
    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", id)
        -- An edit replaces the event on every client: wireOf leaves nothing behind.
        GuildOS.SyncService:Publish("event", "update", { event = wireOf(e) }, { rev = rev })
    end
    self:Refresh()
    return e
end

-- Officer removal of an event. Unlike Cancel (which only hides it), this drops
-- the record and records a tombstone so it cannot be resurrected by a create/
-- update that is still propagating on the guild channel.
function Calendar:Delete(id)
    local e = self:GetEvents()[id]
    if not self:MayManage(e) then return end
    if not e then return end
    self:GetEvents()[id] = nil
    self:Tombstones()[id] = GetServerTime()
    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("event", id)
        GuildOS.SyncService:Publish("event", "delete", { id = id }, { rev = rev })
    end
    self:Refresh()
end

-- Set the local player's RSVP. status = "yes"/"tentative"/"no"; role optional.
function Calendar:Rsvp(id, status, role)
    local e = self:GetEvents()[id]
    if not e or e.canceled then return end
    e.rsvps = e.rsvps or {}
    local _, class = UnitClass("player")
    e.rsvps[keyOf(GuildOS.Compat.PlayerName())] = {
        status = status, role = role, class = class,
        name = GuildOS.Compat.PlayerName(), ts = GetServerTime(),
    }
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("event", "rsvp", { id = id, status = status, role = role, class = class })
    end
    self:Refresh()
end

function Calendar:MyRsvp(e)
    return e and e.rsvps and e.rsvps[keyOf(GuildOS.Compat.PlayerName())] or nil
end

----------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------
-- The event writes a creator who is not an officer may send (SyncService.RANKED_ACTIONS).
local function rankedAct(act)
    local ranked = GuildOS.SyncService and GuildOS.SyncService.RANKED_ACTIONS
    return ranked ~= nil and ranked.event ~= nil and ranked.event[act] == true
end

-- An event of the series `sid`, for a write that names the series rather than a date.
function Calendar:AnyOfSeries(sid)
    for _, e in pairs(self:GetEvents()) do
        if type(e.series) == "table" and e.series.id == sid then return e end
    end
end

function Calendar:OnSync(env, sender)
    local d = env.data
    -- A creator who is not an officer passed the wire for their own events only (issue #283).
    if rankedAct(env.act) and not GuildOS:IsOfficerByName(sender) then
        local id = type(d) == "table" and (d.id or (type(d.event) == "table" and d.event.id))
        local existing = id and (self:GetEvents()[id] or (d.series and self:AnyOfSeries(id))) or nil
        local incoming = type(d) == "table" and d.event or nil
        if not Calendar.MayWriteRemote(existing, incoming, sender, false) then return end
        -- And only a kind the officers opened to them (#308), unless the event is one this client holds
        -- already and keeps its kind: editing, rescheduling, ending, cancelling or deleting it stays theirs.
        local keeps = type(existing) == "table" and type(incoming) == "table"
            and normalizeKind(existing.kind) == normalizeKind(incoming.kind)
        if type(incoming) == "table" and not keeps and not self:KindOpenToMembers(incoming.kind) then return end
    end
    if (env.act == "create" or env.act == "update") and d and d.event then
        local e = d.event
        local existing = self:GetEvents()[e.id]
        -- #267: a client before this edits a date without its rule: the date keeps the rule it had.
        local had = existing and cleanSeries(existing.series)
        if e.series == nil and had and type(e.id) == "string" and e.id:sub(1, #had.id + 1) == had.id .. ":" then
            e.series = existing.series
        end
        local series = cleanSeries(e.series)
        -- A new date of a series this client knows is ended: a stale officer filled it in. Dropped.
        local ended = series and not existing and self:IsSeriesEnded(series.id)
        if not ended and not self:IsDeleted(e.id) and GuildOS.SyncService:ShouldApply("event", e.id, env.rev) then
            local wireCanceled = e.canceled == true
            e.rsvps    = (existing and existing.rsvps) or {}
            e.canceled = (existing and existing.canceled) or false
            e.shareAlliance = e.shareAlliance and true or false
            if self:IsWebEvent(e) then
                -- Forward only here too: an officer's old inbox, or an edit from a client before
                -- this one that sends no list, does not take back what the guild already has.
                local at = math.min(tonumber(e.signupsAt) or 0, GetServerTime())
                if existing and existing.signups and (existing.signupsAt or 0) > at then
                    e.signups, e.signupsAt = existing.signups, existing.signupsAt
                else
                    e.signups, e.signupsAt = cleanWebSignups(e.signups), at
                end
                -- What it was put in the game's calendar as (#263): the newer answer wins, held to now
                -- like the list, and an update that carries none (a client before this) takes nothing back.
                local gameAt = tonumber(e.gameAt)
                if gameAt then gameAt = math.min(gameAt, GetServerTime()) end
                if gameAt and (not existing or (tonumber(existing.gameAt) or 0) <= gameAt) then
                    e.game, e.gameAt = cleanGame(e.game), gameAt
                else
                    e.game, e.gameAt = existing and existing.game, existing and existing.gameAt
                end
                e.clock = cleanClock(e.clock)
                -- One of the site's events that is not a raid (#652): its counts, no names, never in the game's own
                -- calendar; and cancelled or not as the officer who sent it has it, so one the site sends again after
                -- it left comes back here too.
                e.site = cleanSite(e.site)
                if e.site then
                    e.signups, e.game, e.gameAt = {}, nil, nil
                    e.canceled = wireCanceled
                end
            else
                e.signups, e.signupsAt = nil, nil
                e.game, e.gameAt, e.clock, e.site = nil, nil, nil, nil
            end
            e.series = cleanSeries(e.series)   -- #267: the rule of a repeating event, checked
            self:GetEvents()[e.id] = e
            GuildOS.SyncService:SetRevision("event", e.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "delete" and d and d.id then
        if GuildOS.SyncService:ShouldApply("event", d.id, env.rev) then
            -- #267: the end of a whole series, kept so no date of it is filled in or taken in again.
            if d.series then self:EndedSeries()[d.id] = GetServerTime() end
            self:GetEvents()[d.id] = nil
            self:Tombstones()[d.id] = GetServerTime()
            GuildOS.SyncService:SetRevision("event", d.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "cancel" and d and d.id then
        if GuildOS.SyncService:ShouldApply("event", d.id, env.rev) then
            local e = self:GetEvents()[d.id]
            if e then e.canceled = true end
            GuildOS.SyncService:SetRevision("event", d.id, env.rev)
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
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

