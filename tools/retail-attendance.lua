-- Retail attendance as guildos.me counts it (issue #182), run against the real Modules/RaidTracker.lua
-- under a stubbed retail client, in the routine loop.
--
-- A retail lockout is core, instance, week and difficulty: Normal and Heroic in one week are two, as
-- in the game, and a night counts by its difficulty. Every reader of a lockout has to agree: the
-- overall count (or someone who ran both shows 200%), the progression count, and the recent nights
-- the raids panel filters and the missed streak walks. Then the parity fixture's retail mode, which
-- checks the site's retail numbers to the digit (tools/attendance-parity.lua with RETAIL set).
--
--   luajit -e 'ADDON="."' tools/retail-attendance.lua
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

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), Client = { isRetail = true } }
function GuildOS:Print() end
function GuildOS:IsOfficer() return true end
GuildOS.CoreManager = { GetPenalties = function() return { LATE = 10, LEFT_EARLY = 10, NO_CONSUMES = 10 } end }
function GetServerTime() return 1754380000 end
function GetRealmName() return "Azralon" end
function UnitName() return "Ana" end
function IsInGuild() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function GetInstanceInfo() return "The Voidspire", "raid", 14, "Normal", 30, 0, true, 2912 end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function LibStub() return nil end
dofile(ADDON .. "/Modules/RaidTracker.lua")
local RT = GuildOS.RaidTracker

-- Nights at The Voidspire, all in one week (T is a Tuesday), each with two frames.
local T, HOUR, DAY = 1754380000 + 7 * 604800, 3600, 86400
local function nights(list)
  local out = {}
  for _, n in ipairs(list) do
    local members, players = {}, {}
    for _, key in ipairs(n[3]) do
      members[key] = { name = key, class = "MAGE", online = true, hasConsumes = true }
      players[key] = true
    end
    out[n[2]] = { instanceID = 2912, difficulty = n[1], groupTag = "", startTime = n[2], players = players,
                  snapshots = { { time = n[2], members = members }, { time = n[2] + HOUR, members = members } } }
  end
  GuildOS.db = { raidTracker = { sessions = out, attendance = {}, deletedSessions = {} } }
  RT:RebuildAttendanceFromSessions()
end

-- Normal with Ana and Bia, then Heroic with Ana alone.
nights({ { 14, T, { "Ana", "Bia" } }, { 15, T + 2 * DAY, { "Ana" } } })
check(RT:GetTotalSessions("") == 2 and RT:GetTotal25ManSessions("") == 2, "Normal and Heroic in one week are two lockouts, overall and for progression")
check(RT:GetAttendancePercent("Ana", "") == 100 and RT:GetAttendance25ManPercent("Ana", "") == 100,
  "who ran both is 100%, never 200%")
check(RT:GetAttendancePercent("Bia", "") == 50 and RT:GetAttendance25ManPercent("Bia", "") == 50, "who missed the Heroic is 50%")
check(#RT:GetRecentSessions(10, true, true) == 2, "the progression filter keeps both nights")
check(RT:GetMissedStreak("Bia", "", 5) == 1 and RT:GetMissedStreak("Ana", "", 5) == 0, "Bia missed the last night, Ana none")

-- The same two nights on one difficulty are one lockout.
nights({ { 14, T, { "Ana", "Bia" } }, { 14, T + 2 * DAY, { "Ana" } } })
check(RT:GetTotalSessions("") == 1 and RT:GetTotal25ManSessions("") == 1, "one difficulty in one week is one lockout")

-- A night with no difficulty (relayed by an addon before issue #177) is a lockout of its own and no progression.
nights({ { nil, T, { "Ana" } } })
check(RT:GetTotalSessions("") == 1 and RT:GetTotal25ManSessions("") == 0 and #RT:GetRecentSessions(10, true, true) == 0,
  "a night with no difficulty counts for nothing")

-- The site's retail numbers, to the digit: the parity fixture in its retail mode, its output thrown away.
RETAIL = true
local write = io.write
io.write = function() end
dofile(ADDON .. "/tools/attendance-parity.lua")
io.write = write
checks = checks + 1

print(("retail-attendance: %d checks passed"):format(checks))
