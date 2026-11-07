-- The game's own calendar, through Core/Compat.lua (guildos-web specs/075, guildos#263), run against the
-- real Compat under a stubbed WoW: Forever client.
--
-- The calendar keeps the realm's clock and the site sends UTC: a raid at 21:00 UTC on a realm three
-- hours behind has to land at 18:00 on the right day, also across a month's end. The calendar reads
-- months relative to whichever one its window shows, so a player browsing next month must not shift
-- where the addon looks. Creating is a guild event with sign-up, never an announcement (WoW: Forever
-- has none, measured 2026-11-06). Nothing here is offered on TBC Anniversary or retail.
--
--   luajit -e 'ADDON="."' tools/game-calendar-compat.lua
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

-- ── A WoW: Forever client ─────────────────────────────────────────────
-- 2026-11-06 21:00:00 UTC
local NOW = 1793998800
function GetServerTime() return NOW end
function GetTime() return 1000 end
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local allFrames = {}
function CreateFrame()
  local f = { scripts = {}, events = {} }
  allFrames[#allFrames + 1] = f
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  return f
end
C_Timer = { After = function() end }
Enum = { CalendarEventType = { Raid = 0, Dungeon = 1, PvP = 2, Meeting = 3, Other = 4 } }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

-- The realm runs three hours behind UTC: its calendar says 18:00 on the 6th.
local realm = { year = 2026, month = 11, monthDay = 6, weekday = 6, hour = 18, minute = 0 }
C_DateAndTime = { GetCurrentCalendarTime = function() return realm end }

-- The calendar's window shows `shown`; GetMonthInfo(offset) is relative to it.
local shown = { year = 2026, month = 11 }
local daysIn = { [10] = 31, [11] = 30, [12] = 31 }
local dayEvents = {}   -- ["2026-11-8"] = { event, ... }
local calls = {}
local function at(y, m, d) return y .. "-" .. m .. "-" .. d end
local function rec(name, ...) calls[#calls + 1] = { name = name, args = { ... } } end
C_Calendar = {
  OpenCalendar = function() rec("OpenCalendar") end,
  GetMonthInfo = function(offset)
    local idx = shown.year * 12 + (shown.month - 1) + offset
    local y, m = math.floor(idx / 12), idx % 12 + 1
    return { month = m, year = y, numDays = daysIn[m] or 30, firstWeekday = 1 }
  end,
  GetNumDayEvents = function(offset, day)
    local mi = C_Calendar.GetMonthInfo(offset)
    return #(dayEvents[at(mi.year, mi.month, day)] or {})
  end,
  GetDayEvent = function(offset, day, index)
    local mi = C_Calendar.GetMonthInfo(offset)
    return (dayEvents[at(mi.year, mi.month, day)] or {})[index]
  end,
  CreateGuildSignUpEvent = function() rec("CreateGuildSignUpEvent") end,
  CreateGuildAnnouncementEvent = function() rec("CreateGuildAnnouncementEvent") end,
  CreatePlayerEvent = function() rec("CreatePlayerEvent") end,
  EventSetTitle = function(t) rec("EventSetTitle", t) end,
  EventSetDescription = function(t) rec("EventSetDescription", t) end,
  EventSetDate = function(m, d, y) rec("EventSetDate", m, d, y) end,
  EventSetTime = function(h, mi) rec("EventSetTime", h, mi) end,
  EventSetType = function(t) rec("EventSetType", t) end,
  AddEvent = function() rec("AddEvent") end,
  OpenEvent = function(o, d, i) rec("OpenEvent", o, d, i); return true end,
  UpdateEvent = function() rec("UpdateEvent") end,
  CloseEvent = function() rec("CloseEvent") end,
  ContextMenuSelectEvent = function(o, d, i) rec("ContextMenuSelectEvent", o, d, i) end,
  ContextMenuEventRemove = function() rec("ContextMenuEventRemove") end,
}
local function find(name)
  for _, c in ipairs(calls) do if c.name == name then return c end end
end

dofile(ADDON .. "/Core/Compat.lua")
local Compat = GuildOS.Compat
local function fireAll(ev, ...)
  for _, f in ipairs(allFrames) do
    if f.events[ev] and f.scripts.OnEvent then f.scripts.OnEvent(f, ev, ...) end
  end
end

-- ── 1. The realm's clock ──────────────────────────────────────────────
check(Compat.RealmOffset() == -3 * 3600, "the realm runs three hours behind UTC")
local t = Compat.RealmClock(NOW)
check(t.year == 2026 and t.month == 11 and t.day == 6 and t.hour == 18 and t.minute == 0, "21:00 UTC is 18:00 on the realm, same day")
check(Compat.EpochOfRealm(t) == NOW, "and back to the same instant")
-- 2026-12-01 00:30 UTC is 2026-11-30 21:30 on the realm.
local dec1 = 1796085000
local back = Compat.RealmClock(dec1)
check(back.year == 2026 and back.month == 11 and back.day == 30 and back.hour == 21 and back.minute == 30,
  "across a month's end: the last day of the month before")
check(Compat.EpochOfRealm(back) == dec1, "and back")

-- ── 2. Reading the guild's events ─────────────────────────────────────
dayEvents[at(2026, 11, 8)] = {
  { title = "Feast of Winter Veil", calendarType = "HOLIDAY", startTime = { year = 2026, month = 11, monthDay = 8, hour = 0, minute = 0 } },
  { title = "Karazhan", calendarType = "GUILD_EVENT", startTime = { year = 2026, month = 11, monthDay = 8, hour = 18, minute = 0 } },
}
dayEvents[at(2026, 12, 2)] = {
  { title = "Gruul", calendarType = "GUILD_EVENT", startTime = { year = 2026, month = 12, monthDay = 2, hour = 20, minute = 30 } },
}
check(Compat.CalendarGuildEvents(NOW, NOW + 28 * 86400) == nil,
  "before the game has read its calendar, its events are unknown, never none (final review I5)")
calls = {}
Compat.CalendarRequest()
Compat.CalendarRequest()
local opens = 0
for _, c in ipairs(calls) do if c.name == "OpenCalendar" then opens = opens + 1 end end
check(opens == 1, "the calendar is asked for once, not at every look (M6)")
fireAll("CALENDAR_UPDATE_EVENT_LIST")
calls = {}
local evs = Compat.CalendarGuildEvents(NOW, NOW + 28 * 86400)
check(#evs == 2, "two guild events, the holiday left out")
check(not find("OpenCalendar"), "reading never asks the game again: no request loop off its own answer")
check(evs[1].title == "Karazhan" and evs[1].startsAt == NOW + 2 * 86400 and evs[1].day == 8 and evs[1].index == 2,
  "a guild event's start in UTC, and where it sits")
check(evs[2].title == "Gruul" and evs[2].offset == 1, "next month's event, one month on from the one shown")
-- The player is looking at December: the events are the same, only the offsets move.
shown = { year = 2026, month = 12 }
local evs2 = Compat.CalendarGuildEvents(NOW, NOW + 28 * 86400)
check(#evs2 == 2 and evs2[1].offset == -1 and evs2[2].offset == 0, "the month shown never shifts what is read")
shown = { year = 2026, month = 11 }
check(#Compat.CalendarGuildEvents(NOW + 3 * 86400, NOW + 28 * 86400) == 1, "only the events in the window")

-- ── 3. Creating ───────────────────────────────────────────────────────
calls = {}
local ok = Compat.CalendarCreateGuildEvent({ title = "Karazhan", description = "x\nguildos:r1", startsAt = NOW + 86400 })
check(ok == true, "created")
check(find("CreateGuildSignUpEvent") and not find("CreateGuildAnnouncementEvent") and not find("CreatePlayerEvent"),
  "a guild event with sign-up, never an announcement")
local d = find("EventSetDate")
check(d and d.args[1] == 11 and d.args[2] == 7 and d.args[3] == 2026, "the date on the realm's calendar: month, day, year")
local tm = find("EventSetTime")
check(tm and tm.args[1] == 18 and tm.args[2] == 0, "the hour on the realm's clock")
check(find("EventSetType") and find("EventSetType").args[1] == 0, "typed as a raid")
check(calls[#calls].name == "AddEvent", "added last")
C_Calendar.AddEvent = function() error("blocked") end
local ok2, err2 = Compat.CalendarCreateGuildEvent({ title = "K", description = "", startsAt = NOW })
check(ok2 == false and type(err2) == "string", "a raising call is a refusal, never an error")
C_Calendar.AddEvent = function() rec("AddEvent") end

-- ── 4. Editing and removing ───────────────────────────────────────────
calls = {}
check(Compat.CalendarOpenEvent({ offset = 0, day = 8, index = 2 }) == true and find("OpenEvent").args[3] == 2, "opened where it sits")
calls = {}
check(Compat.CalendarApplyEdit({ title = "Kara", description = "y", startsAt = NOW + 86400 }) == true, "edited")
check(find("EventSetTitle").args[1] == "Kara" and find("UpdateEvent") and calls[#calls].name == "CloseEvent", "renamed, saved, closed")
calls = {}
check(Compat.CalendarApplyEdit({ title = "Kara", startsAt = NOW + 86400 }) == true and not find("EventSetDescription"),
  "no description given, the one in the game is left as people wrote it (final review I6)")
C_Calendar.GetEventInfo = function()
  return { title = "Karazhan", time = { year = 2026, month = 11, monthDay = 8, hour = 18, minute = 0 } }
end
local open = Compat.CalendarOpenedEvent()
check(open and open.title == "Karazhan" and open.startsAt == NOW + 2 * 86400, "the event the game has open, in UTC (I2)")
C_Calendar.GetEventInfo = function() return nil end
check(Compat.CalendarOpenedEvent() == nil, "none open: nil")
calls = {}
check(Compat.CalendarRemove({ offset = 0, day = 8, index = 2 }) == true, "removed")
check(find("ContextMenuSelectEvent").args[2] == 8 and find("ContextMenuEventRemove"), "selected, then removed")

-- ── 5. Only on WoW: Forever ───────────────────────────────────────────
check(Compat.CalendarAvailable() == true, "on WoW: Forever the calendar is offered")
GuildOS.Client.isAnniversary = true
check(Compat.CalendarAvailable() == false, "never on TBC Anniversary")
GuildOS.Client.isAnniversary, GuildOS.Client.isRetail = false, true
check(Compat.CalendarAvailable() == false, "nor on retail, not measured there")

io.write(string.format("game-calendar-compat: %d checks passed\n", checks))
