-- Raids on retail (issue #166), run against the real Core files and Modules/RaidTracker.lua under a
-- stubbed retail client and a stubbed WoW: Forever one.
--
-- Retail raids are flex (10 to 30) on Normal and Heroic and 20 on Mythic, and a size says nothing
-- about whether a night counts. What counts is the difficulty: Normal, Heroic and Mythic (14, 15, 16)
-- are tracked and every one of them is progression; Raid Finder (17), timewalking (33) and the rest
-- are not tracked at all. This proves that, the label the progression figures carry, and that the
-- session says its difficulty when it starts; and that Forever keeps tracking every raid by size.
--
--   luajit -e 'ADDON="."' tools/retail-raids.lua
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

local printed = {}
local INSTANCE = { "The Voidspire", "raid", 15, "Heroic", 30, 0, true, 2912 }
local function load(retail)
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return 1791000000 end
  time = os.time
  function GetRealmName() return "Azralon" end
  function UnitName() return "Ana" end
  function GetInstanceInfo() return unpack(INSTANCE) end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.db = { settings = { modules = {} }, members = {}, raidTracker = { sessions = {} } }
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  return GuildOS.RaidTracker
end

-- ── Retail ──────────────────────────────────────────────────────────
local RT = load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
for _, d in ipairs({ { 14, true, "Normal" }, { 15, true, "Heroic" }, { 16, true, "Mythic" },
                     { 17, false, "Raid Finder" }, { 33, false, "timewalking" }, { 3, false, "legacy 10" } }) do
  check(RT:IsTracked(2912, d[1]) == d[2], d[3] .. (d[2] and " is" or " is not") .. " tracked on retail")
end
check(RT:Is25Man(2912, 30, 15) and RT:Is25Man(2912, 20, 16) and RT:Is25Man(2912, 12, 14),
  "every tracked retail raid is progression, whatever its size")
-- A night with no difficulty (relayed by an addon before issue #177) or on one nobody tracks does
-- not count, as on guildos.me (issue #182).
check(not RT:Is25Man(2912, 20) and not RT:Is25Man(2912, 20, 17), "a retail night counts by its difficulty")
check(RT:ProgLabel("No 25-man raids recorded for group: ") == "No N/H/M raids recorded for group: ",
  "the progression label names the difficulties")
check(RT:ProgLabel("(%d/%d raids, 25-man)") == "(%d/%d raids, N/H/M)", "in every label")
-- Every locale's progression label names the difficulties and no size (issue #177): "N/H/M
-- jogadores" said "N/H/M players".
local SIZE_LEFT = { "-man", "er", " jogadores", " jugadores", " joueurs", " giocatori", " чел", "인", " 인", "人", " 人" }
for _, locale in ipairs({ "enUS", "deDE", "esES", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW", "itIT" }) do
  for line in io.lines(ADDON .. "/Locales/" .. locale .. ".lua") do
    local key, value = line:match('^L%["(.-)"%]%s*=%s*"(.*)"%s*$')
    if key and key:find("25%-man") and value:find("25") then
      local out = RT:ProgLabel(value)
      check(not out:find("25") and out:find("N/H/M", 1, true), locale .. ": " .. value .. " names the difficulties")
      for _, w in ipairs(SIZE_LEFT) do
        check(not out:find("N/H/M" .. w, 1, true), locale .. ": " .. out .. " says no size")
      end
    end
  end
end
check(RT:ProgLabel("Presença em 25 jogadores") == "Presença em N/H/M", "the Portuguese label reads N/H/M alone")

RT.TakeSnapshot = function() end
printed = {}
RT:StartSession(2912)
local said = table.concat(printed, "\n")
check(said:find("The Voidspire (Heroic)", 1, true) ~= nil, "the session says its difficulty when it starts")
check(RT.currentRaid.difficulty == 15, "and keeps it")
check(RT:DifficultyLabel(RT.currentRaid) == "H" and RT:DifficultyLabel({ difficulty = 17 }) == nil
  and RT:DifficultyLabel(nil) == nil, "a session's difficulty has a letter for the screen")

-- A difficulty name Midnight keeps secret is never compared or joined (issue #177). Lua never calls
-- __eq between a table and a string, so the compare is checked in the source: IsSecret comes first.
local SECRET = setmetatable({}, { __eq = function() error("a secret was compared") end,
                                  __concat = function() error("a secret was joined") end })
INSTANCE = { "The Voidspire", "raid", 15, SECRET, 30, 0, true, 2912 }
GuildOS.Compat.IsSecret = function(v) return v == SECRET end
-- A secret string is still a string to type(); only comparing or joining it raises.
local realType = type
type = function(v) if rawequal(v, SECRET) then return "string" end return realType(v) end
printed = {}
local okSecret, errSecret = pcall(RT.StartSession, RT, 2912)
type = realType
check(okSecret, "a secret difficulty name does not raise: " .. tostring(errSecret))
local rtSrc = io.open(ADDON .. "/Modules/RaidTracker.lua", "rb"):read("*a")
local guard, compare = rtSrc:find("IsSecret(difficultyName)", 1, true), rtSrc:find('difficultyName ~= ""', 1, true)
check(guard and compare and guard < compare, "the secret check comes before the name is compared")
check(table.concat(printed, " "):find("The Voidspire", 1, true) ~= nil, "and the session still starts")
INSTANCE = { "The Voidspire", "raid", 15, "Heroic", 30, 0, true, 2912 }

-- The difficulty goes in the raid sync, and a copy without it is filled by one that has it.
local sent
LibStub = function() return { Serialize = function(_, t) return t end, Deserialize = function(_, t) return true, t end } end
function IsInGuild() return true end
function GuildOS:IsOfficer() return true end
GuildOS.CommSystem = { MSG_TYPES = { RAID_DATA = "RAID_DATA" }, SendMessage = function(_, _, p) sent = p end }
C_Timer.NewTimer = function() return { Cancel = function() end } end
GuildOS.db.raidTracker.sessions = { [100] = { instanceID = 2912, difficulty = 16, startTime = 100, players = {} } }
RT:BroadcastRaidData()
check(sent.sessions[100].difficulty == 16, "the raid sync carries the difficulty")
GuildOS.db.raidTracker.sessions = { [100] = { instanceID = 2912, startTime = 100, players = {} } }
RT:HandleIncoming(sent)
check(GuildOS.db.raidTracker.sessions[100].difficulty == 16, "a session that lacked it takes it from the sync")

-- Back in on Heroic during the Normal session's grace: a new session, not the Normal one resumed.
C_Timer.NewTimer = function() return { Cancel = function() end } end
RT.currentRaid, RT.trackingActive, RT.endTimer = nil, false, nil
GuildOS.db.raidTracker.sessions = {}
INSTANCE = { "The Voidspire", "raid", 14, "Normal", 30, 0, true, 2912 }
RT:CheckZone()
INSTANCE = { "Dornogal", "none", 0, "", 0, 0, false, 0 }
RT:CheckZone()
check(RT.endTimer ~= nil, "leaving starts the grace")
INSTANCE = { "The Voidspire", "raid", 15, "Heroic", 30, 0, true, 2912 }
printed = {}
RT:CheckZone()
check(RT.currentRaid.difficulty == 15 and RT:DifficultyLabel(RT.currentRaid) == "H",
  "Heroic inside the grace starts a Heroic session")
check(not table.concat(printed, " "):find("Raid resumed", 1, true), "and the Normal one is not resumed")
INSTANCE = { "Dornogal", "none", 0, "", 0, 0, false, 0 }
RT:CheckZone()
INSTANCE = { "The Voidspire", "raid", 15, "Heroic", 30, 0, true, 2912 }
printed = {}
RT:CheckZone()
check(table.concat(printed, " "):find("Raid resumed", 1, true) and RT.currentRaid.difficulty == 15,
  "back on the same difficulty, the session resumes")

-- A switch of difficulty under a running session, with no grace pending, is a new session too.
INSTANCE = { "The Voidspire", "raid", 16, "Mythic", 20, 0, true, 2912 }
RT:CheckZone()
check(RT.currentRaid.difficulty == 16, "a running session that finds itself on Mythic gives way to a Mythic one")

-- The officer's core pick carries over to the next difficulty, picked in the raid or on the run-back.
local now = 1791000000
GetServerTime = function() return now end
function UnitClass() return "Warrior", "WARRIOR" end
function GetNumGroupMembers() return 1 end
function IsInRaid() return true end
function UnitExists() return false end
GuildOS.CoreManager = { CoreForGroup = function() return "Core 1", 1, 1 end }
RT.IsGuildRaid = function() return true end
RT.RebuildAttendanceFromSessions = function() end
-- The real module, snapshots included: a snapshot is where detection would take the core back.
dofile(ADDON .. "/Modules/RaidTracker.lua")
RT = GuildOS.RaidTracker
RT.IsGuildRaid = function() return true end
RT.RebuildAttendanceFromSessions = function() end
for _, onRunBack in ipairs({ false, true }) do
  RT.currentRaid, RT.trackingActive, RT.endTimer = nil, false, nil
  GuildOS.db.raidTracker.corePick = nil
  INSTANCE = { "The Voidspire", "raid", 14, "Normal", 30, 0, true, 2912 }
  RT:CheckZone()
  if not onRunBack then RT:PickCore("Core 2") end
  now = now + 1800
  INSTANCE = { "Dornogal", "none", 0, "", 0, 0, false, 0 }
  RT:CheckZone()
  if onRunBack then RT:PickCore("Core 2") end
  now = now + 120
  INSTANCE = { "The Voidspire", "raid", 15, "Heroic", 30, 0, true, 2912 }
  RT:CheckZone()
  RT:TakeSnapshot("periodic")
  check(RT.currentRaid.difficulty == 15 and RT.currentRaid.groupTag == "Core 2" and RT:GetCurrentGroup() == "Core 2",
    "Heroic keeps the core the officer picked " .. (onRunBack and "on the run-back" or "in Normal"))
end
RT.currentRaid, RT.trackingActive, RT.endTimer = nil, false, nil

-- Normal and Heroic the same night are two lockouts, never merged into one session.
GuildOS.db.raidTracker.sessions = {
  [1000] = { instanceID = 2912, difficulty = 14, startTime = 1000, endTime = 2000, players = { ["Ana-Azralon"] = true } },
  [2100] = { instanceID = 2912, difficulty = 15, startTime = 2100, endTime = 3000, players = { ["Ana-Azralon"] = true } },
}
RT:MergeDuplicateSessions()
local s = GuildOS.db.raidTracker.sessions
check(s[1000] and s[2100] and s[1000].difficulty == 14 and s[2100].difficulty == 15,
  "a raid's Normal and Heroic stay two sessions")

-- ── WoW: Forever keeps its rule ─────────────────────────────────────
RT = load(false)
check(not GuildOS.Client.isRetail, "the stub is Forever")
check(RT:IsTracked(9001, 3) and RT:IsTracked(9001, 17), "Forever tracks every raid")
check(RT:Is25Man(9001, 20) and not RT:Is25Man(9001, 10), "Forever's progression is 20 and up")
check(RT:ProgLabel("(%d/%d raids, 25-man)") == "(%d/%d raids, 20+ man)", "Forever's label is 20+")

print(("retail-raids: %d checks passed"):format(checks))
