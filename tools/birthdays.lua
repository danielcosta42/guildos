-- Birthdays and join anniversaries (issue #428), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/SyncService.lua, Modules/Calendar.lua and Modules/Birthdays.lua.
--
-- What this holds: a birthday is a day and a month, read in the language's order; 29/02 falls on 28/02
-- in a year with none, by the same rule the calendar's yearly dates use; a birthday set on one
-- character shows on every character of its alt group; the calendar draws birthdays and join
-- anniversaries without a single event in db.events; unticking "Show my birthday" sends a tombstone
-- that removes it from other clients, and an older entry never brings it back; a member writes only for
-- their own characters, an officer for anybody; the join anniversary of somebody with several passages
-- counts from the current one, and a date from the first look at the guild makes none; the /g line goes
-- out once a day per person however many officers claim it.
--
--   luajit -e 'ADDON="."' tools/birthdays.lua
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

local DAY = 86400
local function at(y, m, d, hh) return os.time({ year = y, month = m, day = d, hour = hh or 12 }) end
local NOW = at(2027, 2, 28, 15)        -- 28 Feb 2027: no 29th that year
local myRank = 3                       -- a member
local ROSTER = { { "Chehul", 3 }, { "Chehalt", 3 }, { "Mira", 1 }, { "Bob", 3 }, { "Ana", 1 } }
local sent, store, chat = {}, {}, {}
local afters = {}

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function UnitName() return "Chehul" end
function GetRealmName() return "Normal" end
function GetNormalizedRealmName() return "Normal" end
function GetServerTime() return NOW end
function GetTime() return 1 end
function GetLocale() return "ptBR" end
-- The realm's clock is this machine's: its dates are the ones os.date shows, in any TZ.
C_DateAndTime = { GetCurrentCalendarTime = function()
  local t = os.date("*t", NOW)
  return { year = t.year, month = t.month, monthDay = t.day, hour = t.hour, minute = t.min }
end }
date, time = os.date, os.time
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function IsInGuild() return true end
function GetGuildInfo() return "Ashen Vow", "Rank", myRank end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1] .. "-Normal", "Rank", r[2], 60 end end
function SendChatMessage(text, kind) chat[#chat + 1] = { text = text, kind = kind } end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end, NewTicker = function() end }
Enum = { SendAddonMessageResult = {} }
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) store[#store + 1] = t; return tostring(#store) end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) return store[tonumber(s)] ~= nil, store[tonumber(s)] end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/Calendar.lua")
dofile(ADDON .. "/Modules/Birthdays.lua")
local G = GuildOS
G.CommSystem = { SendMessage = function(_, _, payload) sent[#sent + 1] = store[tonumber(payload)] end }
G.db = { members = {}, settings = {}, firstSeen = {}, altLinks = {}, calendar = { events = {}, deleted = {} } }
function G:IsOfficer() return myRank <= 1 end
function G:IsOfficerByName(name) return name:match("^Mira") ~= nil or name:match("^Ana") ~= nil end
function G:IsOnGuildDB() return true end
function G:Print() end
G.SyncService:Initialize()
local B = G.Birthdays
B:Initialize()
local Cal = G.Calendar
local key = function(n) return G:GetPlayerKey(n) end
local function from(sender, act, data)
  G.SyncService:OnEnvelope(sender, LibStub("GuildOS-LibSerialize"):Serialize(
    { v = 2, id = "E" .. #store, dom = "birthday", act = act, data = data }), "GUILD")
  B:Forget()
end
local function lastSent(act)
  for i = #sent, 1, -1 do if sent[i].dom == "birthday" and (not act or sent[i].act == act) then return sent[i] end end
end

-- ── A day and a month ───────────────────────────────────────────────────
check(B.Valid(29, 2) and not B.Valid(30, 2) and not B.Valid(0, 1) and not B.Valid(1, 13), "29/02 is a date, 30/02 is not")
local d, m = B.Parse("14/03", false)
check(d == 14 and m == 3, "14/03 is the 14th of March where the day comes first")
d, m = B.Parse("03/14", true)
check(d == 14 and m == 3, "03/14 is the 14th of March where the month comes first")
d, m = B.Parse("14/03", true)
check(d == 14 and m == 3, "and 14/03 typed there is still read, as it can only be one date")
d, m = B.Parse("14.03.1990", false)
check(d == 14 and m == 3, "a year after it is dropped: only the day and the month are kept")
check(B.Parse("31/02", false) == nil and B.Parse("hello", false) == nil and B.Parse("14/03 x", false) == nil, "nonsense is refused")

-- ── 29 February ─────────────────────────────────────────────────────────
check(B.OnDay(29, 2, 2027, 2, 28) and not B.OnDay(29, 2, 2028, 2, 28) and B.OnDay(29, 2, 2028, 2, 29),
  "29/02 is on the 28th in 2027 and on the 29th in 2028")
local occ = Cal._Occurrences({ rep = "yearly", hour = 12, min = 0 }, at(2024, 2, 29), at(2027, 1, 1), at(2027, 12, 31), 2)
check(#occ == 1 and os.date("%m-%d", occ[1]) == "02-28", "the calendar's yearly rule says the same")

-- ── My birthday, on every character of the group ────────────────────────
G.db.altLinks[key("Chehalt")] = key("Chehul")
sent = {}
check(B:SetMineText("29/02"), "a member gives their birthday")
local s = lastSent("set")
check(s and s.data.list[1].k == key("Chehul") and s.data.list[1].d == 29 and s.data.list[1].m == 2 and s.data.list[1].y == nil,
  "and tells the guild: day and month, no year")
local b = B:For(key("Chehalt"))
check(b and b.day == 29 and b.month == 2, "the birthday shows on the alt")
check(B:Mine() and B:Text(B:Mine()) == os.date("%d/%m", at(2000, 2, 29)), "and is written in the language's order")
check(B:TooltipLine(key("Chehalt")) == "Birthday: " .. os.date("%d/%m", at(2000, 2, 29)), "the roster card's line, on the alt too")
check(B:TooltipLine(key("Bob")) == nil, "and none for a member who shares none")

-- ── The calendar: virtual dates, nothing in db.events ───────────────────
G.db.firstSeenSince = at(2026, 1, 10)
G.db.firstSeen[key("Bob")] = at(2026, 2, 28, 18)     -- joined after the first look
G.db.firstSeen[key("Mira")] = at(2026, 1, 10)        -- there at the first look: no join date
local evs = B:VirtualEvents(at(2027, 2, 1, 0), at(2027, 2, 28, 23))
local bday, join
for _, e in ipairs(evs) do
  if e.kind == "BIRTHDAY" then bday = e elseif e.kind == "JOINDAY" then join = e end
end
check(bday and os.date("%Y-%m-%d", bday.when) == "2027-02-28" and bday.virtual, "the birthday of 29/02 is on the calendar on 28/02/2027")
check(#evs == 2 and join and join.title:find("Bob") and os.date("%m-%d", join.when) == "02-28", "and Bob's first year, once, for the group of one")
check(next(G.db.calendar.events) == nil and next(Cal:GetEvents()) == nil, "no event is written to db.events")
B:SetShows("join", false)
check(#B:VirtualEvents(at(2027, 2, 1, 0), at(2027, 2, 28, 23)) == 1, "the filter takes the join anniversaries off")
B:SetShows("join", true)
check(#B:VirtualEvents(at(2026, 2, 1, 0), at(2026, 2, 28, 23)) == 1, "the day somebody joined is not its own anniversary")

-- ── Today ───────────────────────────────────────────────────────────────
local today = B:Today(NOW)
check(#today == 2 and today[1].kind == "birthday" and today[2].kind == "join" and today[2].years == 1, "today: my birthday, and Bob's year")
check(#B:GetDigestLines(NOW) == 2 and not B:ToldToday(NOW), "two digest lines, not told yet")
B:MarkTold(NOW)
check(B:ToldToday(NOW) and not B:ToldToday(NOW + DAY), "told once a day")

-- ── The join anniversary with several passages ──────────────────────────
check(B.JoinAnchor({ { joinAt = at(2023, 5, 1), leftAt = at(2024, 1, 1) }, { joinAt = at(2025, 3, 2) } }, at(2025, 3, 2), 0)
  == at(2025, 3, 2), "several passages: the current one counts")
check(B.JoinAnchor({ { joinAt = at(2023, 5, 1), leftAt = at(2024, 1, 1) } }, at(2025, 6, 1), 0) == at(2025, 6, 1),
  "a passage the history saw close falls back to when GuildOS saw them again")
check(B.JoinAnchor({ { joinAt = at(2026, 1, 10), joinEst = true } }, nil, at(2026, 1, 10)) == nil,
  "an estimated start at the first look is no join")
local t, est = B.JoinAnchor({ { joinAt = at(2026, 1, 10) } }, nil, at(2026, 1, 10))
check(t == at(2026, 1, 10) and not est, "an exact one at that time is")
check(B.JoinAnchor({}, at(2026, 1, 10), at(2026, 1, 10)) == nil and B.JoinAnchor({}, nil, 0) == nil, "no date, no anniversary")
G.MemberHistory = { Stints = function(_, k)
  if k == key("Bob") then return { { joinAt = at(2020, 4, 1), leftAt = at(2021, 1, 1) }, { joinAt = at(2024, 2, 28, 20) } } end
  return {}
end }
B:Forget()
today = B:Today(NOW)
check(today[2] and today[2].years == 3, "the officer's history: Bob back in 2024, three years today")
G.MemberHistory = nil
B:Forget()

-- ── Who may write ───────────────────────────────────────────────────────
from("Bob-Normal", "set", { list = { { k = key("Mira"), d = 1, m = 1, at = NOW } } })
check(B:For(key("Mira")) == nil, "a member cannot set another member's birthday")
from("Bob-Normal", "set", { list = { { k = key("Bob"), d = 5, m = 6, at = NOW - 10 } } })
check(B:For(key("Bob")).day == 5, "but sets their own")
from("Mira-Normal", "set", { list = { { k = key("Bob"), d = 6, m = 6, at = NOW - 5 } } })
check(B:For(key("Bob")).day == 6, "an officer corrects it")
from("Bob-Normal", "set", { list = { { k = key("Bob"), d = 5, m = 6, at = NOW - 10 } } })
check(B:For(key("Bob")).day == 6, "the member's older entry, sent again at login, does not undo the correction")
from("Bob-Normal", "set", { list = { { k = key("Bob"), d = 31, m = 2, at = NOW } } })
check(B:For(key("Bob")).day == 6, "a date that is no date is dropped")
from("Bob-Normal", "set", { list = { { k = key("Bob"), d = 7, m = 6, at = NOW + 100 * DAY } } })
check(B:For(key("Bob")).day == 6, "an entry from the future is dropped")
ROSTER[#ROSTER + 1] = nil
from("Mira-Normal", "set", { list = { { k = key("Gone"), d = 1, m = 1, at = NOW } } })
check(G.db.birthdays[key("Gone")] == nil, "nobody the whole roster lacks is kept")

-- ── Unticked: a tombstone everywhere ────────────────────────────────────
sent = {}
check(B:ClearMine() and B:Mine() == nil and B:For(key("Chehalt")) == nil, "unticking removes it here, on every character")
check(B:TooltipLine(key("Chehalt")) == nil, "and from the roster card")
s = lastSent("set")
check(s and s.data.list[1].off == true and s.data.list[1].d == nil, "and sends a tombstone, with no date in it")
-- Another client holds my old entry; the tombstone reaches it.
G.db.birthdays[key("Chehul")] = { d = 29, m = 2, at = NOW - DAY }
B:Forget()
from("Chehul-Normal", "set", s.data)
check(B:For(key("Chehul")) == nil, "the tombstone removes it on the other client")
from("Mira-Normal", "set", { list = { { k = key("Chehul"), d = 29, m = 2, at = NOW - DAY } } })
check(B:For(key("Chehul")) == nil, "and an officer's old copy does not bring it back")
from("Bob-Normal", "set", { list = { { k = key("Chehalt"), d = 1, m = 1, at = NOW + 60 } } })
check(B:For(key("Chehul")) == nil, "nor a member who is not in the group")

-- ── Officers: the backfill and the answer to an old entry ───────────────
myRank = 1
sent = {}
B:Backfill()
s = lastSent("set")
check(s and #s.data.list >= 2, "an officer re-sends every entry, tombstones included")
sent = {}
from("Bob-Normal", "set", { list = { { k = key("Bob"), d = 5, m = 6, at = NOW - 10 } } })
s = lastSent("set")
check(s and s.data.list[1].k == key("Bob") and s.data.list[1].d == 6, "an officer answers an older entry with the newer one")
sent = {}
from("Bob-Normal", "set", { list = { { k = key("Bob"), d = 5, m = 6, at = NOW - 10 } } })
check(lastSent("set") == nil, "once a session")

-- ── The /g line: once a day per person ──────────────────────────────────
check(not B:AnnounceOn(), "the announcement is off by default")
G.db.birthdays[key("Mira")] = { d = 28, m = 2, at = NOW - 10 }
B:Forget()
sent, afters, chat = {}, {}, {}
B:CheckAnnounce(NOW)
check(lastSent("claim") == nil and #afters == 0, "off, nothing is claimed")
B:SetAnnounce(true)
B:CheckAnnounce(NOW)
local claims = 0
for _, e in ipairs(sent) do if e.dom == "birthday" and e.act == "claim" then claims = claims + 1 end end
check(claims == 2, "on: Mira's birthday and Bob's year are claimed")
B:CheckAnnounce(NOW)
local again = 0
for _, e in ipairs(sent) do if e.dom == "birthday" and e.act == "claim" then again = again + 1 end end
check(again == 2, "a second look while they wait claims nothing more")
-- Another officer, with a lower name, claims Mira's too: mine gives way. Bob's goes out.
from("Ana-Normal", "claim", { id = key("Mira"), day = 20270228 })
for _, fn in ipairs(afters) do fn() end
check(#chat == 1 and chat[1].kind == "GUILD" and chat[1].text:find("Bob"), "one line goes out: Bob's; Mira's gave way to Ana's claim")
check(lastSent("said") and lastSent("said").data.id == key("Bob"), "and the guild hears it was said")
-- A later look the same day, and another officer's later claim.
sent, afters = {}, {}
from("Ana-Normal", "said", { id = key("Mira"), day = 20270228 })
B:CheckAnnounce(NOW + 3600)
check(lastSent("claim") == nil, "an hour later nothing is claimed again: both were said today")
from("Mira-Normal", "claim", { id = key("Bob"), day = 20270228 })
check(lastSent("said") and lastSent("said").data.id == key("Bob"), "a late officer's claim is answered: it was said")
-- A higher name's claim does not stop mine.
G.db.birthdaySaid = {}
sent, afters, chat = {}, {}, {}
B:CheckAnnounce(NOW)
from("Zed-Normal", "claim", { id = key("Mira"), day = 20270228 })
for _, fn in ipairs(afters) do fn() end
check(#chat == 2, "a claim from a non-officer or a higher name does not stop mine")

-- ── Leaving ─────────────────────────────────────────────────────────────
B:Departed({ [key("Chehul")] = true })
check(G.db.birthdays[key("Mira")] == nil and G.db.birthdays[key("Chehul")] ~= nil, "whoever leaves takes their birthday along")

print(("birthdays: %d checks passed"):format(checks))
