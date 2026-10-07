-- Which raids count for progression attendance on WoW: Forever (issue #90), run against the real
-- Core, Compat, Utils, CoreManager and RaidTracker under a stubbed client.
--
-- Only TBC's 25-player raids counted, by instance id, and only the raids RaidTracker listed were
-- tracked at all: on Forever no raid was recorded, nothing counted, and the screens said
-- "25-man". The owner's decision: on Forever every raid is tracked, and the 20- and 40-player
-- ones count, never the 10s, known by the size the game gives on the way in, so the raids of
-- 9 December work with no list of ids. Anniversary is unchanged.
--
--   luajit -e 'ADDON="."' tools/forever-progression.lua
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

GROUPSIZE = 0
local INSTANCE, NOW, store, sentData = { "Hyjal Summit", "raid", 14, "", 20, 0, false, 9001 }, 1791000000, {}, nil
local printed = {}
local function load(game)
  printed = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  function CreateFrame()
    return setmetatable({}, { __index = function() return function() end end })
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Lead", "Er" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Leader" end
  end
  function GetInstanceInfo() return unpack(INSTANCE) end
  function GetRealmName() return "Realm" end
  function GetServerTime() return NOW end
  function GetTime() return 1 end
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1 end
  function GetNumGuildMembers() return 0 end
  function IsInRaid() return true end
  function GetNumGroupMembers() return GROUPSIZE end
  function UnitClass() return "Mage", "MAGE" end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  LibStub("GuildOS-LibSerialize").Serialize = function(_, t) store[#store + 1] = t; return "#" .. #store end
  LibStub("GuildOS-LibSerialize").Deserialize = function(_, s)
    local t = store[tonumber((s or ""):match("^#(%d+)$") or "")]
    return t ~= nil, t
  end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  GuildOS.db = { settings = {}, members = {}, altLinks = {}, cores = {},
                raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
  GuildOS.CommSystem = { MSG_TYPES = { RAID_DATA = "RD" }, SendMessage = function(_, _, data) sentData = data end }
  local RT = GuildOS.RaidTracker
  RT.CheckPlayerConsumes = function() return false end
  RT.BroadcastRaidData = RT.BroadcastRaidData
  return RT
end

-- A night of `size` players in `instanceID`, everybody there all night.
local function night(RT, startTime, instanceID, size, players)
  local members = {}
  for _, p in ipairs(players) do members[GuildOS:GetPlayerKey(p)] = { name = p, hasConsumes = true } end
  local set = {}
  for k in pairs(members) do set[k] = true end
  GuildOS.db.raidTracker.sessions[startTime] = {
    instanceID = instanceID, name = "Raid", size = size, groupTag = "", startTime = startTime,
    endTime = startTime + 3 * 3600, isGuildRaid = true, players = set, encounters = {},
    snapshots = { { time = startTime, members = members }, { time = startTime + 3 * 3600, members = members } },
  }
end
local WEEK = 7 * 86400

-- ── WoW: Forever ─────────────────────────────────────────────────────────
local RT = load("forever")
check(RT:IsTracked(9001) and RT:IsTracked(409), "forever: every raid is tracked, ids nobody has listed included")
check(RT:Is25Man(9001, 20) and RT:Is25Man(9002, 40) and RT:Is25Man(9003, 25), "forever: a raid of 20 or more counts")
check(not RT:Is25Man(9004, 10) and not RT:Is25Man(565, nil) and not RT:Is25Man(565, "x"),
  "forever: a 10 does not, nor a night with no size, whatever its id")

INSTANCE = { "Hyjal Summit", "raid", 14, "", 20, 0, false, 9001 }
RT:CheckZone()
check(RT.currentRaid and RT.currentRaid.instanceID == 9001 and RT.currentRaid.name == "Hyjal Summit"
  and RT.currentRaid.size == 20, "forever: entering a raid nobody listed starts a session, named and sized by the game")
local startLine = false
for _, m in ipairs(printed) do if m:find("Hyjal Summit (20)", 1, true) then startLine = true end end
check(startLine, "forever: the start line names the size, so day one shows what the game said")

-- A size the game had not given yet is read again at the next snapshot of the same raid.
RT = load("forever")
INSTANCE = { "Hyjal Summit", "raid", 14, "", 0, 0, false, 9001 }
RT:CheckZone()
check(RT.currentRaid and RT.currentRaid.size == nil, "forever: a size of 0 is no size")
INSTANCE = { "Hyjal Summit", "raid", 14, "", 20, 0, false, 9001 }
GROUPSIZE = 1
UnitExists = function() return false end
RT:TakeSnapshot("periodic")
GROUPSIZE = 0
check(RT.currentRaid.size == 20, "forever: and the next snapshot reads it")
INSTANCE = { "Hyjal Summit", "raid", 14, "", 40, 0, false, 9001 }
GROUPSIZE = 1
RT:TakeSnapshot("periodic")
check(RT.currentRaid.size == 20, "forever: a size already read is not read again")
RT.currentRaid.size = nil
INSTANCE = { "Deadmines", "party", 1, "", 5, 0, false, 36 }
RT:TakeSnapshot("periodic")
GROUPSIZE = 0
check(RT.currentRaid.size == nil, "forever: nor is another instance's, as in a dungeon during the grace period")
INSTANCE = { "Hyjal Summit", "raid", 14, "", 20, 0, false, 9001 }
RT = load("forever")
INSTANCE = { "Deadmines", "party", 1, "", 5, 0, false, 36 }
RT:CheckZone()
check(RT.currentRaid == nil, "forever: a dungeon is not a raid")

-- Attendance: the 20 counts, the 10 does not.
RT = load("forever")
night(RT, NOW, 9001, 20, { "Ann", "Bob" })
night(RT, NOW + WEEK, 9001, 20, { "Ann" })
night(RT, NOW + 2 * WEEK, 9010, 10, { "Bob" })
night(RT, NOW + 3 * WEEK, 9040, 40, { "Ann", "Bob" })
RT:RebuildAttendanceFromSessions()
local att = GuildOS.db.raidTracker.attendance[""]
local ann, bob = att[GuildOS:GetPlayerKey("Ann")], att[GuildOS:GetPlayerKey("Bob")]
check(RT:GetTotal25ManSessions() == 3, "forever: the 20s and the 40 are the progression nights, the 10 is not")
check(ann.raids25 == 3 and bob.raids25 == 2 and bob.raids == 3, "forever: everybody's progression count leaves the 10 out")
check(RT:GetAttendance25ManPercent(GuildOS:GetPlayerKey("Ann")) == 100 and RT:GetAttendance25ManPercent(GuildOS:GetPlayerKey("Bob")) == 67,
  "forever: and so does the percentage")
local recent = RT:GetRecentSessions(10, true)
check(#recent == 3, "forever: the progression filter shows the 20s and the 40")

-- The size travels to the other officers, and a merge keeps it.
RT:BroadcastRaidData()
local payload = store[tonumber(sentData:match("#(%d+)"))]
check(payload.sessions[NOW].size == 20 and payload.sessions[NOW + 2 * WEEK].size == 10, "forever: the broadcast carries each night's size")
local mine = GuildOS.db.raidTracker
RT = load("forever")
RT:HandleIncoming(sentData)
check(GuildOS.db.raidTracker.sessions[NOW] and GuildOS.db.raidTracker.sessions[NOW].size == 20, "forever: an officer who receives it keeps it")
check(mine ~= GuildOS.db.raidTracker, "the receiving officer is another database")
-- An officer on an older addon relays the night without its size or its pug mark; the copy
-- that has them, heard later, fills them in.
RT = load("forever")
GuildOS.db.raidTracker.sessions[NOW] = { instanceID = 9001, startTime = NOW, endTime = NOW + 3600, players = {}, encounters = {} }
GuildOS.db.raidTracker.sessions[NOW + WEEK] = { instanceID = 9001, size = 20, startTime = NOW + WEEK, players = {}, encounters = {} }
RT:HandleIncoming((function()
  store[#store + 1] = { sessions = {
    [NOW] = { instanceID = 9001, size = 20, isGuildRaid = false, startTime = NOW, players = {}, encounters = {} },
    [NOW + WEEK] = { instanceID = 9001, size = 40, isGuildRaid = true, startTime = NOW + WEEK, players = {}, encounters = {} },
  } }
  return "#" .. #store
end)())
local relayed = GuildOS.db.raidTracker.sessions[NOW]
check(relayed.size == 20 and relayed.isGuildRaid == false, "forever: a copy that lost the size and the pug mark gets them back")
check(GuildOS.db.raidTracker.sessions[NOW + WEEK].size == 20, "forever: a size already known is not replaced")
RT = load("forever")
night(RT, NOW, 9001, 20, { "Ann" })
GuildOS.db.raidTracker.sessions[NOW].isGuildRaid = false
RT:BroadcastRaidData()
check(store[tonumber(sentData:match("#(%d+)"))].sessions[NOW].isGuildRaid == false, "the broadcast carries the pug mark")

RT = load("forever")
GuildOS.db.raidTracker.sessions[NOW] = { instanceID = 9001, size = 20, startTime = NOW, endTime = NOW + 600, players = {}, encounters = {} }
GuildOS.db.raidTracker.sessions[NOW + 900] = { instanceID = 9001, size = 0, startTime = NOW + 900, endTime = NOW + 3600,
  players = {}, encounters = {} }
RT:MergeDuplicateSessions()
local only
for _, s in pairs(GuildOS.db.raidTracker.sessions) do only = s end
check(only.size == 20, "forever: a merge keeps the size the first half had, over a 0")
RT = load("forever")
GuildOS.db.raidTracker.sessions[NOW] = { instanceID = 9001, size = 0, startTime = NOW, endTime = NOW + 600, players = {}, encounters = {} }
GuildOS.db.raidTracker.sessions[NOW + 900] = { instanceID = 9001, size = 20, startTime = NOW + 900, endTime = NOW + 3600,
  players = {}, encounters = {} }
RT:MergeDuplicateSessions()
for _, s in pairs(GuildOS.db.raidTracker.sessions) do only = s end
check(only.size == 20, "forever: and the second half's, when the first half's was a 0")
RT = load("forever")
GuildOS.db.raidTracker.sessions[NOW] = { instanceID = 9001, startTime = NOW, endTime = NOW + 600, players = {}, encounters = {} }
GuildOS.db.raidTracker.sessions[NOW + 900] = { instanceID = 9001, size = 20, startTime = NOW + 900, endTime = NOW + 3600,
  players = {}, encounters = {} }
RT:MergeDuplicateSessions()
local merged, n = nil, 0
for _, s in pairs(GuildOS.db.raidTracker.sessions) do merged, n = s, n + 1 end
check(n == 1 and merged.size == 20, "forever: two halves of one night merged keep the size either half had")

RT = load("forever")
night(RT, NOW, 9001, 20, { "Ann" })
night(RT, NOW + 3600, 9001, nil, { "Ann" })   -- the same lockout, a recording with no size
RT:RebuildAttendanceFromSessions()
check(GuildOS.db.raidTracker.attendance[""][GuildOS:GetPlayerKey("Ann")].raids25 == 1,
  "forever: a lockout counts when any of its recordings has the size, whichever came last")

-- The screens say 20+.
check(RT:ProgLabel("Member Attendance — 25-man only") == "Member Attendance — 20+ man only", "forever: the English label says 20+")
check(RT:ProgLabel("Presença de Membros — apenas 25 jogadores") == "Presença de Membros — apenas 20+ jogadores",
  "forever: and so does a translated one")
check(string.format(RT:ProgLabel("RAID ATTENDANCE%s  --  %d%%  (%d/%d raids, 25-man)"), "", 50, 1, 2)
  == "RAID ATTENDANCE  --  50%  (1/2 raids, 20+ man)", "forever: a format string still formats")
check(RT:ProgLabel(nil) == nil, "forever: nothing to label is left alone")
local _, why = RT:ExportForTMB("Main")
check(why and why:find("20+", 1, true), "forever: the TMB export's message says 20+")

-- ── Anniversary: unchanged ───────────────────────────────────────────────
RT = load("anniversary")
check(RT:IsTracked(565) and not RT:IsTracked(9001), "anniversary: only the listed raids are tracked")
INSTANCE = { "Somewhere", "raid", 14, "", 20, 0, false, 9001 }
RT:CheckZone()
check(RT.currentRaid == nil, "anniversary: an unlisted raid starts nothing")
check(RT:Is25Man(565, nil) and RT:Is25Man(565, 10) and not RT:Is25Man(532, 25) and not RT:Is25Man(9001, 40),
  "anniversary: progression is by id, whatever size a session carries")
INSTANCE = { "Gruuls Unterschlupf", "raid", 4, "", 25, 0, false, 565 }
RT:CheckZone()
check(RT.currentRaid and RT.currentRaid.name == "Gruul's Lair" and RT.currentRaid.size == 25,
  "anniversary: a listed raid still starts, with its list name over the client's language, and keeps its size too")
check(RT:ProgLabel("Member Attendance — 25-man only") == "Member Attendance — 25-man only", "anniversary: the label says 25-man")
RT = load("anniversary")
night(RT, NOW, 565, nil, { "Ann" })
night(RT, NOW + WEEK, 532, nil, { "Ann" })
RT:RebuildAttendanceFromSessions()
check(RT:GetTotal25ManSessions() == 1 and GuildOS.db.raidTracker.attendance[""][GuildOS:GetPlayerKey("Ann")].raids25 == 1,
  "anniversary: Gruul counts and Karazhan does not, as before")

print(("forever-progression: %d checks passed"):format(checks))
