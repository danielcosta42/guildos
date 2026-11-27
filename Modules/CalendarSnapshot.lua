----------------------------------------------------------------------
-- Guild OS - the game's calendar, for the companion export (specs/game-calendar-export)
--
-- The guild's events in WoW: Forever's own calendar, as this player sees them, and who answered each:
-- read in the background, kept in the guild's db (GuildOS.db.gameCalendar), and carried by the companion
-- export as `gameCalendar` (Modules/CompanionExport.lua), which is built at logout when the game can no
-- longer be asked.
--
--   * The list: the guild's events (guild events with sign-up and announcements) from a day back to
--     WINDOW_DAYS ahead, from the day's lists the game hands over after OpenCalendar. The request goes
--     through Compat.CalendarRequest, which asks at most once a minute; this module asks every
--     REQUEST_EVERY seconds at most.
--   * The details: an event's description, its creator and its invites (name, answer) are only known once
--     the game opens it. One event at a time, OPEN_GAP seconds apart, at most DETAILS_PER_PASS a pass, each
--     again after DETAILS_TTL: never in combat, never while the game's calendar window is open or the
--     officer has an event open in Guild OS (GameCalendar's two-click update), never while another answer is
--     awaited.
--   * The key: the game's event id when the client gives one ("e<id>"), else the start and the title
--     ("t<start>:<title>"), so a re-read finds the same event and the site can keep it.
--   * The role: the game's invite carries none; when the event is a raid of the site (its description
--     carries the mark, GameCalendar.RaidIdIn), the role the site's sign-up gave.
--
-- WoW: Forever only (Compat.CalendarAvailable). Business logic only.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Snapshot = {}
GuildOS.CalendarSnapshot = Snapshot

local Compat = GuildOS.Compat

local WINDOW_BACK = 86400           -- seconds back an event is still listed
local WINDOW_DAYS = 28              -- days ahead
local REQUEST_EVERY = 900           -- seconds between two passes
local FIRST_PASS = 45               -- seconds after login
local OPEN_GAP = 5                  -- seconds between two events opened
local OPEN_WAIT = 8                 -- seconds an open is left to its answer
local READ_DELAY = 1                -- seconds after the answer before reading (the invites come right after)
local DETAILS_PER_PASS = 3          -- events opened in one pass
local DETAILS_TTL = 1800            -- seconds an event's details are kept before they are read again
local EVENTS_MAX = 40               -- events kept
local INVITES_MAX = 200             -- invites kept per event
local TITLE_MAX, DESC_MAX, NAME_MAX = 64, 512, 64

Snapshot.EVENTS_MAX, Snapshot.INVITES_MAX = EVENTS_MAX, INVITES_MAX

local function store()
    local db = GuildOS.db
    if not db then return nil end
    db.gameCalendar = type(db.gameCalendar) == "table" and db.gameCalendar or {}
    local s = db.gameCalendar
    s.events = type(s.events) == "table" and s.events or {}
    return s
end

local function clip(v, n)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[%c]", " ")
    if #v > n then
        v = v:sub(1, n)
        -- never through a multi-byte letter
        while #v > 0 and v:byte(#v) >= 128 and v:byte(#v) < 192 do v = v:sub(1, #v - 1) end
        if #v > 0 and v:byte(#v) >= 192 then v = v:sub(1, #v - 1) end
    end
    return v
end
local function clipText(v, n)   -- a description keeps its lines
    if type(v) ~= "string" then return nil end
    v = v:gsub("[%z\1-\9\11-\31]", " ")
    if #v > n then v = clip(v, n) end
    return v
end

--- The stable key of a day's event: its id, else its start and title. Pure.
function Snapshot.KeyOf(e)
    local id = e.eventID
    if id ~= nil and (type(id) == "number" or type(id) == "string") and tostring(id) ~= "" and tostring(id) ~= "0" then
        return "e" .. tostring(id)
    end
    return "t" .. tostring(math.floor(tonumber(e.startsAt) or 0)) .. ":" .. tostring(e.title or "")
end

function Snapshot:Initialize()
    if not Compat.CalendarAvailable() then return end
    store()
    if not self.frame then
        self.frame = CreateFrame("Frame")
        Compat.RegisterEvent(self.frame, "CALENDAR_OPEN_EVENT")
        self.frame:SetScript("OnEvent", function() GuildOS:SafeCall(Snapshot.OnOpened, Snapshot) end)
        Compat.OnCalendarUpdate(function() GuildOS:SafeCall(Snapshot.OnList, Snapshot) end)
    end
    Compat.After(FIRST_PASS, function() GuildOS:SafeCall(Snapshot.Pass, Snapshot) end)
    if not self.ticker then
        self.ticker = Compat.NewTicker(REQUEST_EVERY, function() GuildOS:SafeCall(Snapshot.Pass, Snapshot) end)
    end
end

-- A pass: ask the game for its list (it answers with CALENDAR_UPDATE_EVENT_LIST, OnList), and read what it
-- already has.
function Snapshot:Pass()
    Compat.CalendarRequest()
    self:OnList()
end

-- The list the game holds now, into the snapshot: new events in, gone ones out, details kept for the ones
-- that stay. Then the details that are missing or old, a few at a time.
function Snapshot:OnList(now)
    now = now or GetServerTime()
    local list = Compat.CalendarGuildEvents(now - WINDOW_BACK, now + WINDOW_DAYS * 86400)
    if not list then return nil end   -- not read yet: unknown, never none
    local s = store()
    if not s then return nil end
    local events, seen = {}, {}
    table.sort(list, function(a, b) return a.startsAt < b.startsAt end)
    for _, e in ipairs(list) do
        local key = Snapshot.KeyOf(e)
        if not seen[key] and #events < EVENTS_MAX then
            seen[key] = true
            local held = s.events[key]
            local rec = {
                key = key, eventId = e.eventID ~= nil and tostring(e.eventID) or nil,
                title = clip(e.title, TITLE_MAX) or "", startsAt = math.floor(e.startsAt),
                calendarType = e.calendarType, guildEvent = e.calendarType == "GUILD_EVENT",
                eventType = tonumber(e.eventType), invitedBy = clip(e.invitedBy, NAME_MAX),
                where = { offset = e.offset, day = e.day, index = e.index },
            }
            if held and held.title == rec.title and held.startsAt == rec.startsAt then
                rec.description, rec.creator, rec.rsvps, rec.detailsAt = held.description, held.creator, held.rsvps, held.detailsAt
            end
            events[#events + 1] = rec
        end
    end
    local byKey = {}
    for _, rec in ipairs(events) do byKey[rec.key] = rec end
    s.events, s.at = byKey, now
    self:QueueDetails(now)
    return events
end

-- Whether opening an event now would get in the way of the player or of Guild OS's own calendar work.
function Snapshot:Busy()
    if InCombatLockdown and InCombatLockdown() then return true end
    if Compat.CalendarWindowShown() then return true end
    local GC = GuildOS.GameCalendar
    if GC and (GC._open ~= nil or (GC._pending and next(GC._pending) ~= nil)) then return true end
    return self._reading ~= nil
end

-- The events whose details are missing or older than DETAILS_TTL, soonest first; up to DETAILS_PER_PASS of
-- them are read, one after another.
function Snapshot:QueueDetails(now)
    local s = store()
    if not s or self._reading or (self._queue and #self._queue > 0) then return end
    local due = {}
    for _, rec in pairs(s.events) do
        if not rec.detailsAt or now - rec.detailsAt > DETAILS_TTL then due[#due + 1] = rec end
    end
    table.sort(due, function(a, b) return a.startsAt < b.startsAt end)
    self._queue = {}
    for i = 1, math.min(#due, DETAILS_PER_PASS) do self._queue[i] = due[i].key end
    self:NextDetail()
end

function Snapshot:NextDetail()
    local q = self._queue
    if not q or #q == 0 then return end
    if self:Busy() then
        Compat.After(OPEN_GAP, function() GuildOS:SafeCall(Snapshot.NextDetail, Snapshot) end)
        return
    end
    local key = table.remove(q, 1)
    local rec = store().events[key]
    if not rec or not rec.where then return self:NextDetail() end
    local ok = Compat.CalendarOpenEvent(rec.where)
    if ok ~= true then return self:NextDetail() end
    local reading = { key = key }
    self._reading = reading
    Compat.After(OPEN_WAIT, function()
        if Snapshot._reading == reading then   -- no answer: let it go
            Snapshot._reading = nil
            Compat.CalendarCloseEvent()
            GuildOS:SafeCall(Snapshot.NextDetail, Snapshot)
        end
    end)
end

-- The game opened the event asked for: read it a moment later (its invites arrive right behind), then close it.
function Snapshot:OnOpened()
    local reading = self._reading
    if not reading or reading.answered then return end
    reading.answered = true
    Compat.After(READ_DELAY, function()
        if Snapshot._reading ~= reading then return end
        GuildOS:SafeCall(Snapshot.ReadOpened, Snapshot, reading.key, GetServerTime())
        Snapshot._reading = nil
        Compat.CalendarCloseEvent()
        Compat.After(OPEN_GAP, function() GuildOS:SafeCall(Snapshot.NextDetail, Snapshot) end)
    end)
end

-- What the open event says, onto its record, when it is the event that was asked for (same title and start).
function Snapshot:ReadOpened(key, now)
    local rec = store().events[key]
    local d = Compat.CalendarEventDetails()
    if not rec or not d then return false end
    if (d.title and clip(d.title, TITLE_MAX) ~= rec.title) or (d.startsAt and d.startsAt ~= rec.startsAt) then return false end
    rec.description = clipText(d.description, DESC_MAX)
    rec.creator = clip(d.creator, NAME_MAX)
    local roles = self:SiteRoles(d.description)
    local rsvps = {}
    for _, inv in ipairs(d.invites or {}) do
        if #rsvps >= INVITES_MAX then break end
        local name = clip(inv.name, NAME_MAX)
        if name then
            rsvps[#rsvps + 1] = { name = name, status = inv.status or "unknown",
                role = type(inv.role) == "string" and inv.role or roles[name] or roles[(name:match("^([^-]+)") or name)] }
        end
    end
    rec.rsvps, rec.detailsAt = rsvps, now
    return true
end

-- The roles the site's sign-up gave, by name, when `description` marks a raid of the site.
function Snapshot:SiteRoles(description)
    local out = {}
    local GC, Cal = GuildOS.GameCalendar, GuildOS.Calendar
    local raidId = GC and GC.RaidIdIn and GC.RaidIdIn(description)
    if not (raidId and Cal and Cal.GetEvents and Cal.WebSignups) then return out end
    local e = Cal:GetEvents()["web:" .. raidId]
    if not e then return out end
    for _, su in ipairs(Cal:WebSignups(e) or {}) do
        if type(su.name) == "string" and type(su.role) == "string" then
            out[su.name] = su.role
            out[su.name:match("^([^-]+)") or su.name] = su.role
        end
    end
    return out
end

--- The export's block: { at, events = [ { key, eventId, title, startsAt, calendarType, guildEvent, eventType,
--- description, creator, invitedBy, detailsAt, rsvps = [ { name, status, role } ] } ] }, soonest first; nil
--- before the game's calendar was ever read here.
function Snapshot:ForExport()
    local s = GuildOS.db and GuildOS.db.gameCalendar
    if type(s) ~= "table" or not s.at or type(s.events) ~= "table" then return nil end
    local list = {}
    for _, rec in pairs(s.events) do
        local rsvps
        if type(rec.rsvps) == "table" then
            rsvps = {}
            for i, r in ipairs(rec.rsvps) do
                rsvps[i] = { name = r.name, status = r.status, role = r.role }
            end
        end
        list[#list + 1] = {
            key = rec.key, eventId = rec.eventId, title = rec.title, startsAt = rec.startsAt,
            calendarType = rec.calendarType, guildEvent = rec.guildEvent and true or false, eventType = rec.eventType,
            description = rec.description, creator = rec.creator, invitedBy = rec.invitedBy,
            detailsAt = rec.detailsAt, rsvps = rsvps,
        }
    end
    table.sort(list, function(a, b)
        if a.startsAt ~= b.startsAt then return a.startsAt < b.startsAt end
        return a.key < b.key
    end)
    return { at = s.at, events = list }
end
