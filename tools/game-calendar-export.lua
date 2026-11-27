-- The game's calendar in the companion export (specs/game-calendar-export), run against the real Core/Compat.lua,
-- Modules/GameCalendar.lua and Modules/CalendarSnapshot.lua under a stubbed WoW: Forever client.
--
-- What this holds: the guild's events (guild events and announcements, never a holiday) come in with a stable key
-- (the game's id, else start and title), their title, start, kind and guild-event flag; their description, creator
-- and invites come from opening each one, one at a time, never in combat, never while the game's calendar window
-- is open or an officer has an event open in Guild OS, and each one again only after its details grow old; the
-- list is asked for through Compat.CalendarRequest (once a minute at most); an event that is gone leaves the
-- snapshot, one that stays keeps its details; a role comes from the site's sign-up when the event is a site raid;
-- a secret name is never kept; the export's block is what the spec says, soonest first.
--
--   luajit -e 'ADDON="."' tools/game-calendar-export.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- 2026-11-27 21:00:00 UTC; the realm on UTC.
local NOW = 1795813200
local CLOCK = 1000
function GetServerTime() return NOW end
function GetTime() return CLOCK end
function GetBuildInfo() return "1.60.1", "71139", "", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local combat = false
function InCombatLockdown() return combat end
local allFrames = {}
function CreateFrame()
  local f = { scripts = {}, events = {} }
  allFrames[#allFrames + 1] = f
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  return f
end
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = CLOCK + d, fn = fn } end,
  NewTicker = function() return { Cancel = function() end } end }
local function runTimers()
  local n = 0
  while #timers > 0 and n < 1000 do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = table.remove(timers, 1)
    if t.at > CLOCK then CLOCK = t.at end
    t.fn()
    n = n + 1
  end
end
Enum = { CalendarEventType = { Raid = 0 } }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
C_DateAndTime = { GetCurrentCalendarTime = function()   -- the realm's clock follows the server's, on UTC
  local t = os.date("!*t", NOW)
  return { year = t.year, month = t.month, monthDay = t.day, hour = t.hour, minute = t.min }
end }

local secret = setmetatable({}, {})
local silent = false   -- the game never answers an open
local fire
local dayEvents, details, opened, calls = {}, {}, nil, {}
local function key(m, d) return m .. "-" .. d end
C_Calendar = {
  OpenCalendar = function() calls[#calls + 1] = "OpenCalendar" end,
  GetMonthInfo = function(offset)
    local idx = 2026 * 12 + 10 + offset
    return { month = idx % 12 + 1, year = math.floor(idx / 12), numDays = 30 }
  end,
  GetNumDayEvents = function(offset, day)
    local mi = C_Calendar.GetMonthInfo(offset)
    return #(dayEvents[key(mi.month, day)] or {})
  end,
  GetDayEvent = function(offset, day, index)
    local mi = C_Calendar.GetMonthInfo(offset)
    return (dayEvents[key(mi.month, day)] or {})[index]
  end,
  AddEvent = function() end,
  OpenEvent = function(o, d, i)
    local mi = C_Calendar.GetMonthInfo(o)
    opened = dayEvents[key(mi.month, d)][i]
    calls[#calls + 1] = "OpenEvent:" .. opened.title
    if not silent then C_Timer.After(0.1, function() fire("CALENDAR_OPEN_EVENT") end) end
    return true
  end,
  CloseEvent = function() opened = nil; calls[#calls + 1] = "CloseEvent" end,
  GetEventInfo = function()
    if not opened then return nil end
    local d = details[opened.title] or {}
    return { title = opened.title, description = d.description, creator = d.creator, calendarType = opened.calendarType,
      time = opened.startTime }
  end,
  GetNumInvites = function() return opened and #((details[opened.title] or {}).invites or {}) or 0 end,
  EventGetInvite = function(i) return opened and details[opened.title].invites[i] end,
}

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
local Compat = GuildOS.Compat
Compat.IsSecret = function(...)
  for i = 1, select("#", ...) do if select(i, ...) == secret then return true end end
  return false
end
GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end
dofile(ADDON .. "/Modules/GameCalendar.lua")
dofile(ADDON .. "/Modules/CalendarSnapshot.lua")
local S = GuildOS.CalendarSnapshot
GuildOS.db = { settings = {}, members = {} }
function fire(ev, ...)
  for _, f in ipairs(allFrames) do
    if f.events[ev] and f.scripts.OnEvent then f.scripts.OnEvent(f, ev, ...) end
  end
end
local function opens()
  local n = 0
  for _, c in ipairs(calls) do if c:find("^OpenEvent") then n = n + 1 end end
  return n
end

-- The game's calendar: a raid of the site, an announcement, a holiday, an event two months out.
local function at(d, h) return { year = 2026, month = 11, monthDay = d, hour = h, minute = 0 } end
dayEvents[key(11, 28)] = {
  { title = "Feast", calendarType = "HOLIDAY", startTime = at(28, 0) },
  { title = "Onyxia", calendarType = "GUILD_EVENT", startTime = at(28, 20), eventID = 4401, eventType = 0, invitedBy = "Chehul" },
}
dayEvents[key(11, 29)] = { { title = "Social night", calendarType = "GUILD_ANNOUNCEMENT", startTime = at(29, 19) } }
details["Onyxia"] = { description = "Fire resist.\nguildos:r42", creator = "Chehul",
  invites = { { name = "Chehul", inviteStatus = 6, classFilename = "SHAMAN" }, { name = "Mira-Costa", inviteStatus = 2 },
              { name = secret, inviteStatus = 1 }, { name = "Tess", inviteStatus = 8 } } }
details["Social night"] = { description = "Drinks", creator = "Mira" }
-- The site's raid r42, with the roles its sign-ups gave.
GuildOS.Calendar = {
  GetEvents = function() return { ["web:r42"] = { id = "web:r42" } } end,
  WebSignups = function() return { { name = "Chehul", status = "signed", role = "TANK" }, { name = "Mira", status = "declined", role = "HEALER" } } end,
}

-- ── Not on Anniversary or retail; nothing before the game read its calendar ──
check(S:ForExport() == nil, "nothing to export before the calendar was ever read")
S:Initialize()
check(#timers == 1, "a first pass is set for after login")
CLOCK = CLOCK + 100
S:Pass()
check(calls[1] == "OpenCalendar" and opens() == 0 and S:ForExport() == nil,
  "the first pass asks the game for its calendar, and holds nothing until it answers")
S:Pass()
local asked = 0
for _, c in ipairs(calls) do if c == "OpenCalendar" then asked = asked + 1 end end
check(asked == 1, "asked through Compat.CalendarRequest: once a minute at most")

-- ── The game answers: the list, then each event opened in turn ──────────
fire("CALENDAR_UPDATE_EVENT_LIST")
local snap = S:ForExport()
check(snap and #snap.events == 2 and snap.at == NOW, "the guild's two events, the holiday left out")
local ony, social = snap.events[1], snap.events[2]
check(ony.key == "e4401" and ony.eventId == "4401" and ony.title == "Onyxia" and ony.guildEvent == true
  and ony.calendarType == "GUILD_EVENT" and ony.eventType == 0 and ony.invitedBy == "Chehul"
  and ony.startsAt == NOW + 86400 - 3600, "an event by its game id, with its start, kind and the guild-event flag")
check(social.key:find("^t%d+:Social night$") and social.guildEvent == false, "one with no id by its start and title; an announcement is no guild event")
check(opens() == 1 and calls[#calls] == "OpenEvent:Onyxia", "the soonest event is opened first, alone")
runTimers()
snap = S:ForExport()
ony = snap.events[1]
check(ony.description == "Fire resist.\nguildos:r42" and ony.creator == "Chehul" and ony.detailsAt == NOW,
  "its description and creator once the game opened it")
check(#ony.rsvps == 3 and ony.rsvps[1].name == "Chehul" and ony.rsvps[1].status == "signedup" and ony.rsvps[1].role == "TANK"
  and ony.rsvps[2].name == "Mira-Costa" and ony.rsvps[2].status == "declined" and ony.rsvps[2].role == "HEALER"
  and ony.rsvps[3].status == "tentative" and ony.rsvps[3].role == nil,
  "its answers, with the site's roles for a site raid, and nobody whose name is secret")
check(snap.events[2].creator == "Mira" and snap.events[2].rsvps and #snap.events[2].rsvps == 0, "then the next event, after a gap")
local closes = 0
for _, c in ipairs(calls) do if c == "CloseEvent" then closes = closes + 1 end end
check(closes == 2 and opened == nil, "each one closed after it is read")

-- ── Re-reads, gone events, and when not to open ─────────────────────────
calls = {}
NOW = NOW + 600
S:OnList()
check(opens() == 0, "details younger than half an hour are not read again")
NOW = NOW + 2000
combat = true
S:OnList()
check(opens() == 0, "never in combat")
combat = false
CalendarFrame = { IsShown = function() return true end }
runTimers()
check(opens() == 0, "never while the game's calendar window is open")
CalendarFrame = nil
GuildOS.GameCalendar._open = { id = "web:r42" }
CLOCK = CLOCK + 10
runTimers()
check(opens() == 0, "never while an officer has an event open in Guild OS")
GuildOS.GameCalendar._open = nil
CLOCK = CLOCK + 10
runTimers()
check(opens() == 2, "then both are read again, in their turn")
dayEvents[key(11, 29)] = nil
S:OnList()
snap = S:ForExport()
check(#snap.events == 1 and snap.events[1].key == "e4401" and #snap.events[1].rsvps == 3, "a gone event leaves; one that stays keeps its answers")
-- An open the game never answers is let go.
GuildOS.db.gameCalendar.events.e4401.detailsAt = nil
calls = {}
silent = true
S:OnList()
check(opens() == 1, "an event whose details are missing is opened")
runTimers()
silent = false
check(S._reading == nil and calls[#calls] == "CloseEvent", "an open left unanswered is let go")
-- A different event opened in between is not read as this one.
GuildOS.db.gameCalendar.events.e4401.detailsAt = nil
local realOpen = C_Calendar.OpenEvent
C_Calendar.OpenEvent = function(...)
  realOpen(...)
  opened = { title = "Something else", calendarType = "GUILD_EVENT", startTime = at(28, 20) }
  return true
end
S:QueueDetails(NOW)
runTimers()
C_Calendar.OpenEvent = realOpen
check(GuildOS.db.gameCalendar.events.e4401.detailsAt == nil, "another event open in the game is never read as this one")
check(S.KeyOf({ eventID = 0, startsAt = 5, title = "x" }) == "t5:x" and S.KeyOf({ eventID = "abc" }) == "eabc", "the key: the id, else start and title")

print(("game-calendar-export: %d checks passed"):format(checks))
