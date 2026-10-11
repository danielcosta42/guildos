-- The attendance a roll is judged by is the raid's own core's (issue #134), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CoreManager.lua, Modules/RaidTracker.lua and
-- Modules/LootMaster.lua, on a Forever build.
--
-- A raider can be on several cores (#132). The loot rules (minimum attendance for MS, the attendance
-- tiebreaker) are the raid's core's config, so the attendance compared to them is that core's too:
-- not the core where the raider has the most raids. A core none of whose nights count (a 10 on Forever,
-- or a core on its first raid) has no figure to judge by, and the raider keeps the old one.
--
--   luajit -e 'ADDON="."' tools/loot-attendance.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Lead", "Er" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetInstanceInfo() return "X", "raid", 14, "", 20, 0, false, 9001 end
function GetRealmName() return "Realm" end
local NOW = 1791000000
function GetServerTime() return NOW end
function GetTime() return 1 end
time = os.time
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInRaid() return true end
function SendChatMessage() end
function GetLootMethod() return "master", 0 end
function GetNumGroupMembers() return 0 end
function UnitClass() return "Mage", "MAGE" end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CoreManager.lua")
dofile(ADDON .. "/Modules/RaidTracker.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
GuildOS.db = { settings = {}, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { minAttendancePct = 75, attTiebreaker = true },
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local RT, CM, LM = GuildOS.RaidTracker, GuildOS.CoreManager, GuildOS.LootMaster
RT.currentGroupTag = ""
CM:Create("Twenty"); CM:Create("Other"); CM:Create("Ten"); CM:Create("Fresh")

local WEEK, seq = 7 * 86400, 0
local function night(week, id, size, tag, players)
  local t = NOW - week * WEEK
  local members, set = {}, {}
  for _, p in ipairs(players) do
    local k = GuildOS:GetPlayerKey(p, GetRealmName())
    members[k] = { name = p, hasConsumes = true }
    set[k] = true
  end
  seq = seq + 1
  GuildOS.db.raidTracker.sessions[t + seq] = { instanceID = id, name = "R", size = size, groupTag = tag, startTime = t,
    endTime = t + 3 * 3600, isGuildRaid = true, players = set, encounters = {},
    snapshots = { { time = t, members = members }, { time = t + 3 * 3600, members = members } } }
end
-- Ana: both nights of the Twenty; half of the Other's six, so the Other is where she raids most;
-- the Ten's two nights, which never count for progression on Forever.
night(0, 9020, 20, "Twenty", { "Ana", "Bo" })
night(1, 9020, 20, "Twenty", { "Ana", "Bo" })
for w = 0, 5 do
  night(w, 9021, 20, "Other", w % 2 == 0 and { "Ana", "Bo" } or { "Bo" })
end
night(0, 9010, 10, "Ten", { "Ana", "Bo" })
night(1, 9010, 10, "Ten", { "Ana", "Bo" })
RT:RebuildAttendanceFromSessions()

-- The figure the roll is judged by, and what an MS roll becomes, with `tag` the raid's core.
local function roll(tag)
  RT:SetGroupTag(tag)
  local att = LM:GetPlayerContext("Ana").att25
  LM.activeLoot, LM.rolls = {}, {}
  LM:RegisterRoll("Ana", "MS", 50)
  local r = LM.rolls[GuildOS:GetPlayerKey("Ana")]
  return att, r and r.rollType
end

local att, kind = roll("")
check(att == 50 and kind == "OS", "with no core active, as before: the Other, where Ana raids most, 50%, so her MS is OS")
att, kind = roll("Twenty")
check(att == 100 and kind == "MS", "in a raid of the Twenty, Ana is judged by the Twenty's 100%, and her MS stands")
att, kind = roll("Other")
check(att == 50 and kind == "OS", "in a raid of the Other, by the Other's 50%: below the 75% minimum, MS becomes OS")
att, kind = roll("Ten")
check(att == 50, "a core none of whose nights count has no figure: Ana keeps the old one, not 0%")
att, kind = roll("Fresh")
check(att == 50, "and a core on its first raid the same")

print(("loot-attendance: %d checks passed"):format(checks))
