-- The member history (issue #425), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/CommSystem.lua, Modules/SyncService.lua, Modules/RosterLog.lua, Modules/MemberHistory.lua,
-- Modules/BanList.lua, Modules/PugInspector.lua and Modules/ExportImport.lua under a stubbed client.
--
-- Each member's passages (joined, left, how and by whom) and rank changes, kept past the Roster Log's
-- 90 days, with a ceiling: from the log's live and synced events, from a diff of the whole roster
-- against the one last seen (once a minute at most, officers only; what changed while the officer was
-- away is told once at login), and from the officers' records over the audit domain. The days are the
-- client's calendar days (time zone, year turn, leap year). The officer is told who was a member before
-- at an invite, a join and a whisper; the log gains rejoins, level ups, note changes and returns from
-- inactivity; the log and the former members export with English headers.
--
--   luajit -e 'ADDON="."' tools/member-history.lua
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
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local frames = {}
function CreateFrame()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(ev) self.events[ev] = true end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
function hooksecurefunc() end
function debugstack() return "" end
function GetBuildInfo() return "1.60.1", "70450", "", 16001 end   -- WoW: Forever: keys are the name alone
WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 1, 5, 99
function GetRealmName() return "Realm" end
local now = 1794139200
function GetServerTime() return now end
local clock = 1
function GetTime() return clock end
local afters = {}
function GuildRoster() end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
GameTooltip = { HasScript = function() return true end, HookScript = function() end }
date = os.date
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetLocale() return "ptBR" end
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."

-- The guild: { name, rankName, rankIndex, level, note, officerNote, online, daysOffline }. Ranks 0..1 are officers.
local ROSTER = {}
local function roster(list) ROSTER = list end
local me, viewOfficerNotes = "Off", true
function UnitName() return me end
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1], r[2], r[3], r[4], "WARRIOR", "", r[5], r[6], r[7] end
end
function GetGuildRosterLastOnline(i)
  local r = ROSTER[i]
  if r and not r[7] then return 0, 0, r[8] or 0, 0 end
end
function CanViewOfficerNote() return viewOfficerNotes end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", r[2], r[3] end end
  return "Guild", "Member", 5
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local registry, store, n = {}, {}, 0
LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = copy(t); return "s" .. n end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, copy(store[s]) end return false end
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
dofile(ADDON .. "/Modules/MemberHistory.lua")
dofile(ADDON .. "/Modules/BanList.lua")
dofile(ADDON .. "/Modules/PugInspector.lua")
dofile(ADDON .. "/Modules/ExportImport.lua")
function GuildOS:IsOnGuildDB() return true end
GuildOS.isGuilded = true
local CS, SS, RL, MH, BL = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.RosterLog, GuildOS.MemberHistory, GuildOS.BanList
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end
local function deliver(msg, sender)
  CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, "GUILD", sender)
end
local function K(name) return GuildOS:GetPlayerKey(name) end
local function hist(m) local env = store[m.data]; return env and env.dom == "audit" and env.act == "hist" and env.data.r end

-- ── 1. Days: the client's calendar, whatever the zone or the year ─────────
check(MH.DayNumber(1970, 1, 1) == 0, "1970-01-01 is day 0")
check(MH.DayNumber(2000, 3, 1) == 11017, "2000-03-01 is day 11017")
check(MH.DayNumber(2025, 1, 1) - MH.DayNumber(2024, 1, 1) == 366, "2024 is a leap year")
check(MH.DayNumber(2026, 1, 1) - MH.DayNumber(2025, 12, 31) == 1, "the year turns in a day")
local function zone(hours) return function(_, ts) return os.date("!*t", ts + hours * 3600) end end
local utc = os.time({ year = 2025, month = 12, day = 31, hour = 2, min = 30 }) -- any instant; zones below are explicit
-- An instant whose UTC date is known: 2026-01-01 02:30 UTC.
local T = 1767234600
check(os.date("!%Y-%m-%d %H:%M", T) == "2026-01-01 02:30", "the fixture's instant")
check(MH.DaysBetween(T, T + 40 * 60, zone(-3)) == 1, "Brasília: 31/12 23:30 to 01/01 00:10 is one day")
check(MH.DaysBetween(T, T + 40 * 60, zone(9)) == 0, "Seoul: the same two moments are one day, 11:30 to 12:10")
check(MH.DaysBetween(T - 200 * DAY, T, zone(-3)) == 200, "200 days ago is 200 days")
check(MH.DaysBetween(T, T - DAY, zone(0)) == -1 and MH.DaysBetween(nil, T) == nil, "backwards and unknown")
check(utc ~= nil, "os.time answers")

-- ── 2. The merge rules, on a store of their own ───────────────────────────
local h = {}
check(MH.ApplyJoin(h, "Ana", 1000, false) == "join", "a first join opens a passage")
check(MH.ApplyJoin(h, "Ana", 1500, true) == nil, "a diff's join while a member changes nothing")
check(MH.ApplyLeave(h, "Ana", 5000, "kick", "Bob", false) and h.Ana.stints[1].leftAt == 5000, "a kick closes it")
check(not MH.ApplyLeave(h, "Ana", 6000, "gone", nil, true), "the next diff's 'gone' is the same departure")
check(not MH.ApplyLeave(h, "Ana", 5100, "kick", "Bob", false), "another officer's copy of the kick: one departure")
check(#h.Ana.stints == 1 and h.Ana.stints[1].how == "kick" and h.Ana.stints[1].by == "Bob", "kept as the kick, by Bob")
check(MH.ApplyJoin(h, "Ana", 9000, false) == "rejoin" and #h.Ana.stints == 2, "back again: a second passage, a rejoin")
-- Seen first by a diff, refined by the exact line that arrives later from another officer.
check(MH.ApplyLeave(h, "Ana", 20000, "gone", nil, true) and h.Ana.stints[2].leftEst, "a diff closes the passage, estimated")
check(MH.ApplyLeave(h, "Ana", 19000, "leave", nil, false), "the game's line, later off the network")
check(h.Ana.stints[2].leftAt == 19000 and not h.Ana.stints[2].leftEst and h.Ana.stints[2].how == "leave",
  "takes the exact time and the reason")
check(MH.ApplyJoin(h, "Ana", 15000, true) == nil, "a diff's join from before the last departure is old news")
-- A departure nobody saw the join of.
check(MH.ApplyLeave(h, "Cid", 3000, "leave", nil, false) and h.Cid.stints[1].joinAt == nil, "a passage with no start")
check(MH.ApplyJoin(h, "Cid", 1000, false) == "refined" and h.Cid.stints[1].joinAt == 1000, "an old join fills its start")
-- Ranks.
check(MH.ApplyRank(h, "Ana", 9500, nil, "Raider", "Bob", false), "a promotion")
check(not MH.ApplyRank(h, "Ana", 9600, "Member", "Raider", nil, true), "the diff's copy of it is dropped")
check(not MH.ApplyRank(h, "Ana", 9550, nil, "Raider", "Bob", false), "another officer's copy too")
check(MH.ApplyRank(h, "Ana", 12000, "Raider", "Officer", nil, true) and h.Ana.ranks[2].est, "a diff's own change")
check(MH.ApplyRank(h, "Ana", 11000, nil, "Officer", "Bob", false) and h.Ana.ranks[2].at == 11000 and h.Ana.ranks[2].by == "Bob",
  "refined by the exact line")
check(#h.Ana.ranks == 2 and h.Ana.ranks[2].from == "Raider", "two changes, the from kept")
-- The ceiling.
local c = {}
for i = 1, MH.MAX_STINTS + 5 do MH.ApplyJoin(c, "Z", i * 100, false); MH.ApplyLeave(c, "Z", i * 100 + 50, "leave", nil, false) end
check(#c.Z.stints == MH.MAX_STINTS and c.Z.stints[1].joinAt == 600, "at most MAX_STINTS passages, the oldest dropped")
for i = 1, MH.MAX_RANKS + 3 do MH.ApplyRank(c, "Z", i * 1000, nil, "R" .. i, nil, false) end
check(#c.Z.ranks == MH.MAX_RANKS, "at most MAX_RANKS rank changes")
local big = {}
for i = 1, 30 do MH.ApplyJoin(big, "F" .. i, 1, false); MH.ApplyLeave(big, "F" .. i, 100 + i, "leave", nil, false) end
for i = 1, 5 do MH.ApplyJoin(big, "P" .. i, 1, false) end
check(MH.Cap(big, 20) == 15 and big.F1 == nil and big.F16 ~= nil and big.F30 ~= nil and big.P1 ~= nil,
  "over the cap: the former members who left longest ago go, the present stay")
check(MH.Cap({ X = { stints = { { joinAt = 1 } } } }, 0) == 0, "a present member is never dropped")
check(MH.MAX_KEYS * (MH.MAX_STINTS * 80 + MH.MAX_RANKS * 70) < 8 * 1024 * 1024, "the documented bound: under 8 MB")

-- ── 3. The diff ───────────────────────────────────────────────────────────
local base = {
  Ana = { r = 3, rn = "Member", lv = 58, n = "x", o = "y", off = 0 },
  Bob = { r = 2, rn = "Raider", lv = 60, n = "", o = "", off = 45 },
  Cid = { r = 3, rn = "Member", lv = 20, n = "", o = nil, off = 0 },
}
local rows = {
  { key = "Ana", r = 2, rn = "Raider", lv = 60, n = "tank", o = "ok", off = 0 },
  { key = "Bob", r = 2, rn = "Raider", lv = 60, n = "", o = "", off = 0 },
  { key = "Dan", r = 4, rn = "Initiate", lv = 10, n = "", o = "", off = 0 },
}
local ch, shared = MH.Diff(base, rows, { levels = "milestones", maxLevel = 60, inactiveDays = 30 })
local kinds = {}
for _, x in ipairs(ch) do kinds[x.kind .. ":" .. x.key] = x end
check(shared, "the two rosters share members")
check(kinds["rank:Ana"] and kinds["rank:Ana"].up and kinds["rank:Ana"].to == "Raider", "Ana promoted")
check(kinds["level:Ana"] and kinds["level:Ana"].to == 60, "Ana's 60, a milestone")
check(kinds["note:Ana"] and kinds["onote:Ana"], "both notes changed")
check(kinds["back:Bob"] and kinds["back:Bob"].days == 45, "Bob back after 45 days")
check(kinds["join:Dan"] and kinds["gone:Cid"], "Dan new, Cid gone")
check(not MH.LevelWanted("milestones", 21, 25, 60) and MH.LevelWanted("milestones", 29, 30, 60)
  and MH.LevelWanted("all", 21, 22, 60) and not MH.LevelWanted("off", 59, 60, 60), "the level filter")
local _, none = MH.Diff(base, { { key = "Q", r = 1 } }, {})
check(not none, "a roster that shares nobody is no guild of newcomers")

-- ── 4. An officer's client: first look, then a removal while away ─────────
local function freshDb()
  return { settings = { officerMaxRank = 1, modules = {} }, members = {}, rosterLog = { events = {} },
    firstSeen = {}, banList = {} }
end
local db = freshDb()
GuildOS.db = db
-- What the client already held before #425: an old log and when GuildOS first saw each member.
db.rosterLog.events = {
  { action = "join", target = "Eva", timestamp = now - 85 * DAY, id = "e1" },
  { action = "kick", target = "Eva", author = "Off", timestamp = now - 65 * DAY, id = "e2" },
  { action = "promote", target = "Mem", author = "Off", detail = "Raider", timestamp = now - 10 * DAY, id = "e3" },
}
db.firstSeen = { [K("Mem")] = now - 400 * DAY }
db.foundingJoins = { [K("Mem")] = { joinedAt = now - 500 * DAY } }
roster({
  { "Off", "Officer", 1, 60, "", "", true },
  { "Off2", "Officer", 1, 60, "", "", false, 0 },
  { "Mem", "Raider", 2, 58, "dps", "core", false, 2 },
  { "Old", "Member", 3, 40, "", "", false, 40 },
})
SS:Initialize()
RL:Initialize()
RL._ready = true
BL:Initialize()
BL._ready = true
afters = {}
MH:Initialize()
check(#afters == 1, "the first diff waits for the login to settle")
MH:Scan()
check(db.memberHistoryBase == nil, "nothing is compared before it settles")
afters[1]()
check(db.memberHistoryMigrated, "the old data is migrated once")
check(#MH:Stints(K("Eva")) == 1 and MH:LastLeft(K("Eva")).how == "kick" and MH:LastLeft(K("Eva")).by == "Off", "Eva's passage from the old log")
check(MH:JoinedAt(K("Mem")) == now - 500 * DAY and select(2, MH:JoinedAt(K("Mem"))) == true,
  "Mem: since the founding date, the earlier one, and only as GuildOS saw it")
check(MH:Ranks(K("Mem"))[1].to == "Raider", "and the promotion from the old log")
check(MH:JoinedAt(K("Old")) == now, "Old: since now, all GuildOS knows")
check(db.memberHistoryBase and db.memberHistoryBase.m[K("Old")], "the roster is taken")
check(#printed == 0, "the first look tells nothing")

-- The officer logs off; Old is removed by Off2 and Mem reaches 60, then the officer is back.
now = now + 3 * DAY
roster({
  { "Off", "Officer", 1, 60, "", "", true },
  { "Off2", "Officer", 1, 60, "", "", false, 0 },
  { "Mem", "Raider", 2, 60, "dps", "core", false, 0 },
  { "New", "Initiate", 4, 10, "", "", true },
})
GuildOS.State.memberHistory = nil
afters, sent, printed = {}, {}, {}
MH:Initialize()
afters[1]()
local line = table.concat(printed, "\n")
check(line:find("Since your last login:", 1, true) and line:find("Old", 1, true) and line:find("New", 1, true),
  "at login: who left and who joined since the last one")
check(MH:IsFormer(K("Old")) and MH:LastLeft(K("Old")).leftEst and MH:LastLeft(K("Old")).how == "gone", "Old gone, estimated")
check(MH:JoinedAt(K("New")) == now, "New's passage")
local gone, level
for _, e in ipairs(db.rosterLog.events) do
  if e.action == "gone" and e.target == "Old" then gone = e end
  if e.action == "level" and e.target == "Mem" then level = e end
end
check(gone and gone.loc and gone.detail == "since your last login", "the log: Old gone, since the last login")
check(level and level.detail == "58 > 60", "the log: Mem's 60")
local recs = {}
for _, m in ipairs(sent) do local r = hist(m); if r then recs[#recs + 1] = r end end
check(#recs == 2, "two records to the officers: Old's departure and New's join")
printed = {}
GuildOS.State.coalesce.at.memberHistory = nil
MH:Scan()
check(#printed == 0, "and only once: the next diff says nothing")

-- The exact line from another officer, backfilled: the passage takes it.
deliver({ t = "SV", data = (function()
  return LibStub("GuildOS-LibSerialize"):Serialize({ v = 2, id = "x1", dom = "audit", act = "add",
    data = { evt = { action = "kick", target = "Old", author = "Off2", timestamp = now - DAY } } })
end)() }, "Off2")
check(MH:LastLeft(K("Old")).how == "kick" and MH:LastLeft(K("Old")).by == "Off2" and not MH:LastLeft(K("Old")).leftEst,
  "Old: removed by Off2, at the game's time")

-- ── 5. The warning: at an invite, a join and a whisper ────────────────────
now = now + 200 * DAY   -- Eva left 268 days ago
printed = {}
check(not BL:HoldInvite("Eva", function() end), "a former member's invite is never held")
local warn = printed[1] or ""
check(warn:find("Eva was a member", 1, true) and warn:find("(20 days)", 1, true) and warn:find("removed by Off", 1, true),
  "the officer reads when, for how long and how: " .. warn)
check(warn:find(GuildOS:DateText(now - 203 * DAY - 85 * DAY, "/%Y") .. " to " .. GuildOS:DateText(now - 203 * DAY - 65 * DAY, "/%Y"), 1, true), "with the dates as the client writes them")
-- Two passages: Eva rejoins (the game's line) and is told about.
printed = {}
fire("CHAT_MSG_SYSTEM", "Eva has joined the guild.")
local rejoin = db.rosterLog.events[#db.rosterLog.events]
check(rejoin.action == "join" and rejoin.rejoin, "the log files a rejoin")
check(printed[1] and printed[1]:find("Eva was a member", 1, true), "and the officer reads her past at the join")
fire("CHAT_MSG_SYSTEM", "Eva has left the guild.")
local total, count = MH:TenureDays(K("Eva"))
check(count == 2 and total == 20, "two passages, the days summed (the second one under a day)")
printed = {}
fire("CHAT_MSG_WHISPER", "hi, can I come back?", "Eva")
check(printed[1] and printed[1]:find("Eva was a member 2 times", 1, true), "a whisper: both passages, " .. tostring(printed[1]))
printed = {}
fire("CHAT_MSG_WHISPER", "again", "Eva")
check(#printed == 0, "once a session")
-- A member's client: nothing is told, nothing recorded.
me = "Mem"
printed = {}
check(not BL:HoldInvite("Eva", function() end) and #printed == 0, "a member is not told")
check(MH:FromAudit({ action = "join", target = "Zed", timestamp = now }) == nil and not db.memberHistory[K("Zed")],
  "and a member's client records nothing")
me = "Off"

-- ── 6. Records off the network ────────────────────────────────────────────
check(MH.ValidRecord({ k = "A", a = "x", t = 1 }, now) == nil, "an unknown act")
check(MH.ValidRecord({ k = "A", a = "j", t = now + 3600 }, now) == nil, "a time from the future")
check(MH.ValidRecord({ k = "A", a = "l", t = 1, h = "boom" }, now) == nil, "an unknown way to leave")
check(MH.ValidRecord({ k = "A", a = "r", t = 1 }, now) == nil, "a rank change to nothing")
check(MH.ValidRecord({ k = "A", a = "j", t = 0 / 0 }, now) == nil, "NaN")
local okRec = MH.ValidRecord({ k = "A", a = "l", t = 5, h = "kick", b = "B|cffff0000x" }, now)
check(okRec and okRec.b == "Bcffff0000x", "the officer's name cleaned")
-- Applied once per id, on an officer's client.
MH:OnSync({ r = { k = K("Gus"), a = "j", t = now - 50, e = true } })
check(MH:JoinedAt(K("Gus")) == now - 50, "another officer's diff: Gus joined")
-- Backfill: this client's records again, never a line of its own diff.
sent = {}
RL:Backfill()
local adds, hists = 0, 0
for _, m in ipairs(sent) do
  local env = store[m.data]
  if env and env.act == "add" then
    adds = adds + 1
    check(not env.data.evt.loc, "a line of this client's diff never goes out")
  elseif env and env.act == "hist" then hists = hists + 1 end
end
check(adds > 0 and hists == 2, "the log's tail and the two records")

-- The log's quotas (issue #425): this client's own lines (a level, a note, a return) make room among themselves,
-- never by pushing out the guild's events; and the backfill picks the last BACKFILL_N of what it may send.
local logStore = {}
for i = 1, 10 do RL:_Insert({ action = "join", target = "J" .. i, timestamp = 1000 + i * 10 }, logStore) end
for i = 1, RL.LOCAL_CAP + 50 do
  RL:_Insert({ action = "level", target = "L" .. i, detail = "1 > 2", timestamp = 2000 + i * 10, loc = true }, logStore)
end
local function tally(list)
  local real, loc = 0, 0
  for _, e in ipairs(list) do if e.loc then loc = loc + 1 else real = real + 1 end end
  return real, loc
end
local real, loc = tally(logStore)
check(real == 10 and loc == RL.LOCAL_CAP, "level-ups past their quota push out the oldest level-ups, not the joins")
check(logStore[1].target == "J1" and logStore[11].target == "L51", "the oldest of this client's lines went first")
for i = 1, RL.CAP do RL:_Insert({ action = "kick", target = "K" .. i, author = "Off", timestamp = 9000000 + i * 10 }, logStore) end
real, loc = tally(logStore)
check(real == RL.CAP and loc == RL.LOCAL_CAP, "the guild's events have their own CAP and leave the local lines be")
local events = GuildOS.db.rosterLog.events
local realBefore = tally(events)
for i = 1, RL.BACKFILL_N + 5 do
  RL:_Insert({ action = "note", target = "N" .. i, detail = "x", timestamp = now + i * 10, loc = true })
end
sent = {}
RL:Backfill()
adds = 0
for _, m in ipairs(sent) do
  local env = store[m.data]
  if env and env.act == "add" then adds = adds + 1 end
end
check(realBefore > 0 and adds == math.min(RL.BACKFILL_N, realBefore),
  "a tail of local lines does not leave the backfill empty: " .. adds .. " of " .. realBefore .. " sent")

-- ── 7. The export, the API, the Pug Inspector ─────────────────────────────
local text = GuildOS.Exporter:Build("former", "csv")
check(text and text:find("^Name,FirstJoined,LastLeft,How,By,Stints,TotalDays,Estimated\n"), "former: English headers")
check(text:find("\n" .. K("Eva") .. ",", 1, true) and text:find("\n" .. K("Old") .. ",", 1, true), "Eva and Old are former members")
text = GuildOS.Exporter:Build("log", "tsv")
check(text and text:find("^Date\tAction\tMember\tDetail\tBy\n") and text:find("\trejoin\tEva", 1, true),
  "log: English headers, a rejoin named")
me = "Mem"
check(select(2, GuildOS.Exporter:Build("former", "csv")) == "officer", "a member exports neither")
me = "Off"
local pug = GuildOS.PugInspector:Classify("Old", GuildOS.PugInspector:_LiveSources())
check(pug.tag == "Ex-member" and pug.detail and pug.detail:find("days in the guild", 1, true), "the Pug Inspector: when Old left")
local mate = GuildOS.PugInspector:Classify("Mem", GuildOS.PugInspector:_LiveSources())
check(mate.tag == "Guildmate", "a present member is a guildmate, whatever the history")
check(type(MH:Stints("Nobody")) == "table" and #MH:Stints("Nobody") == 0 and MH:JoinedAt("Nobody") == nil
  and MH:TenureDays("Nobody") == nil and MH:Describe("Nobody") == nil, "the API answers for nobody")

-- ── 8. Who invited (the game's guild event log, specs/salao/log-e-renomes.md) ──
local inv = {}
MH.ApplyJoin(inv, "Ivy", 10000, true)
check(MH.SetInviter(inv, "Ivy", 9000, "Off2", 7200) and inv.Ivy.stints[1].inv == "Off2",
  "a join the diff saw later: its inviter from the log, earlier than the diff's time")
check(not MH.SetInviter(inv, "Ivy", 9000, "Other", 7200), "one already known stays")
check(not MH.SetInviter(inv, "Nobody", 1, "X"), "nobody: nothing")
MH:FromAudit({ action = "join", target = "Ula", author = "Off2", timestamp = now - 60, approx = true, tol = 7200 })
check(MH:InvitedBy(K("Ula")) == "Off2", "an approximate join from the log, with its inviter")
check(MH:InvitedBy(K("Old")) == nil, "a former member: none for the current passage")
-- The Roster Log's approximate events: two copies of the game's line an hour apart are one, the officer filled in.
local apx = {}
check(RL:_Insert({ action = "kick", target = "Pip", timestamp = 50000, approx = true, tol = 7200 }, apx), "an approximate removal")
check(not RL:_Insert({ action = "kick", target = "Pip", author = "Off2", timestamp = 53000, approx = true, tol = 7200 }, apx)
  and #apx == 1 and apx[1].author == "Off2", "its copy fifty minutes on is the same line, and fills the officer")
check(RL:_Insert({ action = "kick", target = "Pip", timestamp = 50000 + 3 * 3600, approx = true, tol = 7200 }, apx),
  "three hours apart: another one")
-- Deleting a line: on this client only, never back from a backfill.
RL:_Insert({ action = "warn", target = "Pip", author = "Off", timestamp = now - 5, id = "w-pip" })
check(RL:Hide("w-pip") and not RL:_Insert({ action = "warn", target = "Pip", author = "Off", timestamp = now - 5, id = "w-pip" }),
  "a deleted line is refused when it comes back")

print(string.format("member-history: %d checks passed", checks))
