-- The game's guild event log read once a login (specs/salao/log-e-renomes.md), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua, Modules/SyncService.lua, Modules/RosterLog.lua,
-- Modules/MemberHistory.lua and Modules/GuildEventLog.lua under a stubbed client.
--
-- A client without the log does nothing and says nothing. On an officer's client, after the roster settled and
-- the first diff ran, out of combat, the log is asked for once: the officer each diff line lacked is filled in
-- (who removed a "gone", who invited a join, who promoted), the member's history follows, a change nobody here saw
-- is added as an approximate event and sent to the officers, the next login adds nothing again, a line deleted
-- here stays deleted, and another officer's copy of the same game line folds into this one.
--
--   luajit -e 'ADDON="."' tools/guild-event-log.lua
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

local DAY, HOUR = 86400, 3600
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
function GetTime() return 1 end
local afters = {}
function GuildRoster() end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end }
local function runAfters()
  local list = afters
  afters = {}
  for _, fn in ipairs(list) do fn() end
end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
GameTooltip = { HasScript = function() return true end, HookScript = function() end }
date = os.date
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetLocale() return "enUS" end
local inCombat = false
function InCombatLockdown() return inCombat end
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."

-- The guild: { name, rankName, rankIndex, level, note, officerNote, online, daysOffline }. Ranks 0..1 are officers.
local ROSTER = {}
local function roster(list) ROSTER = list end
local me = "Off"
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
function CanViewOfficerNote() return true end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", r[2], r[3] end end
  return "Guild", "Member", 5
end

-- The game's log: { type, player1, player2, rank, years, months, days, hours }. Absent until a test installs it.
local LOG, queried = {}, 0
local function installLog()
  function QueryGuildEventLog() queried = queried + 1 end
  function GetNumGuildEvents() return #LOG end
  function GetGuildEventInfo(i) local e = LOG[i]; if e then return e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8] end end
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
dofile(ADDON .. "/Modules/GuildEventLog.lua")
function GuildOS:IsOnGuildDB() return true end
GuildOS.isGuilded = true
local CS, SS, RL, MH, GEL = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.RosterLog, GuildOS.MemberHistory, GuildOS.GuildEventLog
local Compat = GuildOS.Compat
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end
local function K(name) return GuildOS:GetPlayerKey(name) end
local function adds()
  local out = {}
  for _, m in ipairs(sent) do
    local env = store[m.data]
    if env and env.dom == "audit" and env.act == "add" then out[#out + 1] = env.data.evt end
  end
  return out
end
local function find(action, target)
  for _, e in ipairs(GuildOS.db.rosterLog.events) do
    if e.action == action and e.target == target then return e end
  end
end
local function count(action, target)
  local c = 0
  for _, e in ipairs(GuildOS.db.rosterLog.events) do
    if e.action == action and e.target == target then c = c + 1 end
  end
  return c
end

-- A login: the session forgotten, the modules started, every timer run (the settle, the diff, the question).
local function login()
  GuildOS.State.memberHistory, GuildOS.State.guildEventLog, GuildOS.State.coalesce = nil, nil, nil
  afters = {}
  RL:Initialize()
  RL._ready = true
  MH:Initialize()
  GEL:Initialize()
  for _ = 1, 4 do runAfters() end
end

local db = { settings = { officerMaxRank = 1, modules = {} }, members = {}, rosterLog = { events = {} }, firstSeen = {} }
GuildOS.db = db
SS:Initialize()

-- ── 1. No log on this client: nothing, silently ───────────────────────────
check(Compat.HasGuildEventLog() == false and Compat.GuildEventLog() == nil and Compat.QueryGuildEventLog() == false,
  "Compat answers no log, nil and false where the client has none")
roster({
  { "Off", "Officer", 1, 60, "", "", true },
  { "Off2", "Officer", 1, 60, "", "", false, 0 },
  { "Mem", "Member", 3, 58, "", "", false, 2 },
  { "Kid", "Member", 3, 40, "", "", false, 9 },
})
printed = {}
login()
check(queried == 0 and #printed == 0, "no log: no question, no line")
check(GuildOS.State.guildEventLog.done == true, "and it does not try again this session")
fire("GUILD_EVENT_LOG_UPDATE")
check(#db.rosterLog.events == 0, "an update nobody asked for changes nothing")

-- ── 2. Pure: the game's entries as the log's events ──────────────────────
installLog()
check(Compat.HasGuildEventLog(), "with the three calls the client has a log")
local ev = GEL.Events({
  { type = "invite", p1 = "Off2", p2 = "New", ago = 5 * HOUR, tol = 2 * HOUR },
  { type = "join", p1 = "New", ago = 5 * HOUR, tol = 2 * HOUR },
  { type = "remove", p1 = "Off2", p2 = "Kid", ago = 30 * HOUR, tol = 2 * HOUR },
  { type = "promote", p1 = "Off2", p2 = "Mem", rank = "Raider", ago = 10 * HOUR, tol = 2 * HOUR },
  { type = "bogus", p1 = "X", ago = 1 },
}, now)
check(#ev == 3 and ev[1].action == "kick" and ev[1].author == "Off2" and ev[1].target == "Kid", "a removal: the member and the officer")
check(ev[3].action == "join" and ev[3].author == "Off2", "an invite is the officer of the join it led to")
check(ev[2].action == "promote" and ev[2].detail == "Raider" and ev[2].timestamp == now - 10 * HOUR - 1800, "the middle of the game's hour")
LOG = { { "join", "Ana", nil, nil, 0, 2, 3, 4 } }
local raw = Compat.GuildEventLog()
check(#raw == 1 and raw[1].ago == ((2 * 30 + 3) * 24 + 4) * HOUR and raw[1].tol == 3 * DAY, "months ago: a wider tolerance")
issecretvalue = function(v) return v == "Ana" end
check(#Compat.GuildEventLog() == 0, "an entry with a secret part is left out")
issecretvalue = nil

-- ── 3. The first look, then a login after a night away ───────────────────
LOG = {}
login()
check(queried == 1, "asked once at login, after the first diff")
fire("GUILD_EVENT_LOG_UPDATE")
check(#db.rosterLog.events == 0, "an empty log: nothing")
login()
check(queried == 2, "one question a login")

now = now + DAY
roster({
  { "Off", "Officer", 1, 60, "", "", true },
  { "Off2", "Officer", 1, 60, "", "", false, 0 },
  { "Mem", "Raider", 2, 58, "", "", false, 0 },
  { "New", "Initiate", 4, 10, "", "", true },
})
LOG = {
  { "invite", "Off2", "New", nil, 0, 0, 0, 5 },
  { "join", "New", nil, nil, 0, 0, 0, 5 },
  { "remove", "Off2", "Kid", nil, 0, 0, 0, 20 },
  { "promote", "Off2", "Mem", "Raider", 0, 0, 0, 10 },
  { "join", "Zed", nil, nil, 0, 0, 0, 15 },
  { "quit", "Zed", nil, nil, 0, 0, 0, 12 },
  { "promote", "Off2", "Ghost", "Raider", 0, 4, 0, 0 },   -- four months ago: past the log's 90 days
}
sent = {}
local q0 = queried
inCombat = true
login()
check(queried == q0, "in combat: no question")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
check(queried == q0 + 1, "after the fight: the question")
check(find("gone", "Kid") and find("join", "New") and find("promote", "Mem"), "the diff saw Kid gone, New join, Mem promoted")
sent = {}
fire("GUILD_EVENT_LOG_UPDATE")
local kid = find("kick", "Kid")
check(kid and kid.author == "Off2" and kid.loc and not find("gone", "Kid"), "Kid's 'gone' is a removal by Off2")
check(find("join", "New").author == "Off2", "New's join: invited by Off2")
check(find("promote", "Mem").author == "Off2", "Mem's promotion: by Off2")
local zj, zq = find("join", "Zed"), find("leave", "Zed")
check(zj and zj.approx and zq and zq.approx and zq.author == nil, "Zed joined and left while away: two approximate events")
check(zq.timestamp == now - 12 * HOUR - 1800, "at the middle of the game's hour")
check(not find("promote", "Ghost"), "past the log's 90 days: left alone")
local out = adds()
check(#out == 2, "the two events this client added go to the officers, and only those (" .. #out .. ")")
-- The history.
local kidStint = MH:LastLeft(K("Kid"))
check(kidStint and kidStint.how == "kick" and kidStint.by == "Off2" and not kidStint.leftEst, "Kid's passage: removed by Off2")
check(kidStint.leftAt == now - 20 * HOUR - 1800, "at the log's time, not when the diff saw it")
check(MH:InvitedBy(K("New")) == "Off2", "New: invited by Off2")
local mr = MH:Ranks(K("Mem"))
check(mr[#mr].to == "Raider" and mr[#mr].by == "Off2" and not mr[#mr].est, "Mem's rank change: by Off2, at the log's time")
check(#MH:Stints(K("Zed")) == 1 and MH:LastLeft(K("Zed")).how == "leave", "Zed's passage from the log")

-- ── 4. The next login: the same log an hour older adds nothing ───────────
local before = #db.rosterLog.events
local zedStints = #MH:Stints(K("Zed"))
now = now + 3 * HOUR + 1200
for _, e in ipairs(LOG) do e[8] = e[8] + 3 end
sent = {}
login()
fire("GUILD_EVENT_LOG_UPDATE")
check(#db.rosterLog.events == before, "no duplicate at the next login (" .. #db.rosterLog.events .. " vs " .. before .. ")")
check(#adds() == 0, "and nothing sent")
check(#MH:Stints(K("Zed")) == zedStints and count("leave", "Zed") == 1, "nor a second passage")
fire("GUILD_EVENT_LOG_UPDATE")
check(#db.rosterLog.events == before, "a second update in the session is not read")

-- ── 5. A line deleted here stays deleted ─────────────────────────────────
check(RL:Hide(find("leave", "Zed").id) and not find("leave", "Zed"), "an officer deletes Zed's departure here")
login()
fire("GUILD_EVENT_LOG_UPDATE")
check(not find("leave", "Zed"), "the next login's log does not bring it back")
me = "Mem"
check(not RL:Hide(find("join", "Zed").id), "a member deletes nothing")
me = "Off"

-- ── 6. Another officer's copy of the same game line folds into this one ──
local zjoin = find("join", "Zed")
local copyEvt = { action = "join", target = "Zed", timestamp = zjoin.timestamp + 2400, approx = true, tol = 7200,
  id = "other-officer-id" }
RL:OnSync({ act = "add", data = { evt = copyEvt } }, "Off2")
check(count("join", "Zed") == 1, "an officer's approximate copy an hour apart is the same line")
RL:OnSync({ act = "add", data = { evt = { action = "promote", target = "Pat", author = "Off2", detail = "Raider",
  timestamp = now - 4 * HOUR, approx = true, tol = 7200, id = "p1" } } }, "Off2")
check(find("promote", "Pat") and find("promote", "Pat").author == "Off2", "one this client lacked is taken")

-- ── 7. A member's client never asks ──────────────────────────────────────
me = "Mem"
local q1 = queried
login()
check(queried == q1, "a member's client does not ask for the log")
me = "Off"

print(string.format("guild-event-log: %d checks passed", checks))
