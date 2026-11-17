-- The lockout week is the region's (guildos-web#199), run against the real Core/Compat.lua and
-- Modules/RaidTracker.lua under each region the client can answer.
--
-- The week used to start on Tuesday 00:00 UTC. The game resets each region at its own hour, and the
-- client's Cfg_Regions table says when: the Americas on Tuesday at 15:00 UTC, Europe on Wednesday at
-- 04:00 UTC, Korea and Taiwan on Wednesday at 23:00 UTC. A Monday-night raid in Brasília, after 21:00,
-- landed in the next week, and a Tuesday-night raid in Europe too. This proves the week is the
-- region's, that a client that does not say is the Americas, that lockouts and attendance follow it,
-- that the raids panel groups its sessions by the same helper, and that the self-test compares the
-- table with the client's own count of the seconds to the reset. guildos.me keeps the same table
-- (packages/wow/src/reset.ts); tools/attendance-parity.lua checks the two to the digit.
--
--   luajit -e 'ADDON="."' tools/reset-week.lua
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

local HOUR, DAY, WEEK = 3600, 86400, 604800
local regionId = 1  -- what GetCurrentRegion() answers
local NOW = 1791000000

local function load()
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  -- TBC Anniversary, where Gruul counts by its id; the week is every game's.
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 1, 5, 5
  function GetBuildInfo() return "2.5.6", "70006", "", 20506 end
  function GetCurrentRegion() return regionId end
  function GetServerTime() return NOW end
  function GetRealmName() return "Firemaw" end
  function UnitName() return "Ana" end
  function IsInGuild() return true end
  function IsInRaid() return false end
  function GetNumGroupMembers() return 0 end
  function GetInstanceInfo() return "Gruul's Lair", "raid", 0, "", 25, 0, false, 565 end
  C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
  function LibStub() return nil end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
  function GuildOS:Print() end
  function GuildOS:IsOfficer() return true end
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  GuildOS.CoreManager = { GetPenalties = function() return { LATE = 10, LEFT_EARLY = 10, NO_CONSUMES = 10 } end }
  return GuildOS.RaidTracker
end

local RT = load()
local DAYS = { "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed" }  -- 1 Jan 1970 was a Thursday
local function when(t)
  return DAYS[math.floor(t / DAY) % 7 + 1] .. string.format(" %02d:%02d", math.floor(t % DAY / HOUR), math.floor(t % HOUR / 60))
end

-- ── 1. The table is the client's Cfg_Regions.Raidorigin ────────────────
local O = RT.RESET_ORIGIN
check(O.us == 1127228400 and O.kr == 1135810800 and O.eu == 1135742400 and O.tw == 1135810800,
  "each region's origin is Cfg_Regions.Raidorigin, rows 1 to 4")
check(when(O.us) == "Tue 15:00", "the Americas reset on Tuesday at 15:00 UTC, not " .. when(O.us))
check(when(O.eu) == "Wed 04:00", "Europe on Wednesday at 04:00 UTC, not " .. when(O.eu))
check(when(O.kr) == "Wed 23:00" and when(O.tw) == "Wed 23:00", "Korea and Taiwan on Wednesday at 23:00 UTC")

-- Thursday 22 Oct 2026, 00:00 UTC (Wednesday 21:00 in Brasília), and the Tuesday after it.
local THU = 1792627200
local TUE = THU + 5 * DAY
check(when(THU) == "Thu 00:00" and when(TUE) == "Tue 00:00", "the dates below are what they say")

-- ── 2. The Americas: Monday night in Brasília is the week before ───────
regionId = 1
local week = RT:GetWeekNum(THU)
check(RT:GetWeekNum(TUE + HOUR) == week, "Monday 22:00 in Brasília (Tuesday 01:00 UTC) is still Wednesday's week")
check(RT:GetWeekNum(TUE + 15 * HOUR - 1) == week and RT:GetWeekNum(TUE + 15 * HOUR) == week + 1,
  "the Americas turn over at Tuesday 15:00 UTC")
check(RT:WeekStart(week + 1) == TUE + 15 * HOUR, "a week starts at its reset")
check(RT:WeekStart(week) == TUE + 15 * HOUR - WEEK, "and the one before, a week earlier")

-- ── 3. Europe: Tuesday night is the last night of the week ─────────────
regionId = 3
week = RT:GetWeekNum(THU)
check(RT:GetWeekNum(TUE + 20 * HOUR) == week, "Tuesday 21:00 in Paris (20:00 UTC) is still Thursday's week")
check(RT:GetWeekNum(TUE + DAY + 4 * HOUR - 1) == week and RT:GetWeekNum(TUE + DAY + 4 * HOUR) == week + 1,
  "Europe turns over at Wednesday 04:00 UTC")

-- ── 4. Korea and Taiwan ────────────────────────────────────────────────
for _, id in ipairs({ 2, 4 }) do
  regionId = id
  local before = RT:GetWeekNum(TUE + DAY + 23 * HOUR - 1)
  check(RT:GetWeekNum(TUE + DAY + 23 * HOUR) == before + 1, "region " .. id .. " turns over at Wednesday 23:00 UTC")
end

-- ── 5. A client that does not say is the Americas ──────────────────────
for _, answer in ipairs({ 5, 0, false }) do
  regionId = answer or nil
  check(RT:GetWeekNum(TUE + HOUR) == RT:GetWeekNum(THU) and RT:GetWeekNum(TUE + 15 * HOUR) == RT:GetWeekNum(THU) + 1,
    "region " .. tostring(answer) .. " counts the Americas' week")
end
local compat = GuildOS.Compat
GuildOS.Compat = nil
check(RT:GetWeekNum(TUE + HOUR) == RT:GetWeekNum(THU), "with no Compat at all, the Americas")
GuildOS.Compat = compat

-- ── 6. Lockouts and attendance follow the region's week ────────────────
local function nights(list)
  local out = {}
  for _, n in ipairs(list) do
    local members = { [n[2]] = { name = n[2], class = "MAGE", online = true, hasConsumes = true } }
    out[n[1]] = { instanceID = 565, groupTag = "", startTime = n[1], players = { [n[2]] = true },
                  snapshots = { { time = n[1], members = members }, { time = n[1] + HOUR, members = members } } }
  end
  GuildOS.db = { raidTracker = { sessions = out, attendance = {}, deletedSessions = {} } }
  RT:RebuildAttendanceFromSessions()
end

-- Gruul on Wednesday night and on Monday night, in Brasília: one lockout in the Americas, where
-- Tuesday 00:00 UTC made it two.
regionId = 1
nights({ { THU, "Ana" }, { TUE + HOUR, "Bia" } })
check(RT:GetTotal25ManSessions("") == 1, "Wednesday and Monday nights in Brasília are one lockout")
check(RT:GetAttendance25ManPercent("Ana", "") == 90 and RT:GetAttendance25ManPercent("Bia", "") == 90,
  "one chance: Ana left before its last frame, Bia came after its first")

-- Thursday and Tuesday nights in Europe: one lockout there, two in the Americas.
regionId = 3
nights({ { THU + 19 * HOUR, "Ana" }, { TUE + 20 * HOUR, "Bia" } })
check(RT:GetTotal25ManSessions("") == 1, "Thursday and Tuesday nights in Europe are one lockout")
regionId = 1
RT:RebuildAttendanceFromSessions()
check(RT:GetTotal25ManSessions("") == 2, "the same nights in the Americas are two")

-- ── 7. The raids panel groups by the same week ─────────────────────────
local function src(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local panel = src("UI/FeaturePanels.lua")
check(not panel:find("1136246400", 1, true) and not panel:find("TUESDAY_EPOCH", 1, true),
  "the raids panel keeps no epoch of its own")
check(panel:find("GuildOS.RaidTracker:GetWeekNum(startTime)", 1, true)
  and panel:find("GuildOS.RaidTracker:WeekStart(weekNum)", 1, true),
  "the raids panel groups sessions by RaidTracker's week")
check(not src("Modules/RaidTracker.lua"):find("1136246400", 1, true), "nothing counts from Tuesday 00:00 UTC")

-- ── 8. The self-test compares the table with the client's own count ────
local cases = {}
GuildOS.SelfTest = { Register = function(_, name, fn) cases[name] = fn end }
RT:_RegisterTests()
local selftest = cases["raidtracker.weekly_reset"]
check(selftest ~= nil, "the weekly reset has a self-test")

regionId = 1
NOW = TUE + 10 * HOUR                         -- five hours before the Americas reset
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 5 * HOUR end }
check(selftest() == true, "the Americas' table agrees with a client five hours from its reset")
regionId = 3
local ok, msg = selftest()
check(ok == false and msg and msg:find("eu", 1, true), "a Europe client five hours from a reset disagrees, and says where: " .. tostring(msg))
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 18 * HOUR end }
check(selftest() == true, "and agrees eighteen hours from it")
C_DateAndTime = nil
check(selftest() == true, "a client without the call has nothing to compare")

-- ── 9. The parity fixtures' nights either side of the reset ────────────
-- Core 3's Gruul on Wednesday night and Monday night in Brasília and Tuesday night in Paris: two
-- lockouts in the Americas (Wednesday's with Monday's, then Tuesday's), one in Europe. The site reads
-- the same answers out of the fixtures (apps/web/test/parity.test.ts).
local function parity(region)
  REGION = region  -- the parity tool's own global, a region's name
  local out = {}
  local write = io.write
  io.write = function(s) out[#out + 1] = s end
  dofile(ADDON .. "/tools/attendance-parity.lua")
  io.write = write
  local json, got = table.concat(out), {}
  for _, who in ipairs({ "Quarta", "Segunda", "Terca" }) do
    got[who] = tonumber(json:match('"' .. who .. '%-Firemaw":(%d+)'))
  end
  return got, json:match('"region":"(%a+)"')
end
local us, usRegion = parity(nil)
check(usRegion == "us" and us.Quarta == 45 and us.Segunda == 45 and us.Terca == 50,
  "the Americas: Wednesday and Monday are one lockout of two, Tuesday the other")
local eu, euRegion = parity("eu")
check(euRegion == "eu" and eu.Quarta == 90 and eu.Segunda == 80 and eu.Terca == 90, "Europe: one lockout of all three")

print(("reset-week: %d checks passed"):format(checks))
