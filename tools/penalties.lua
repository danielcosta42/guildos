-- Attendance penalties (issue #55), run against the real Core/Core.lua, Core/Compat.lua,
-- Modules/CoreManager.lua and Modules/RaidTracker.lua.
--
-- Penalties could only be changed per Core: a raid outside a core always lost 10 for late,
-- 10 for leaving early and 10 for no consumables, and a guild without cores could not turn
-- them off. The guild now has its own weights, which raids outside a core use and a core
-- without its own inherits.
--
--   luajit -e 'ADDON="."' tools/penalties.lua
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

-- ── The client the files need while they load ───────────────────────────
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
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Modules/CoreManager.lua")
dofile(ADDON .. "/Modules/RaidTracker.lua")
local CM, RT = GuildOS.CoreManager, GuildOS.RaidTracker
GuildOS.db = { cores = {}, raidTracker = { sessions = {}, attendance = {} } }

local function same(p, late, early, dry)
  return p.LATE == late and p.LEFT_EARLY == early and p.NO_CONSUMES == dry
end

-- ── The guild's own weights ─────────────────────────────────────────────
check(same(CM:GetPenalties(""), 10, 10, 10), "out of the box a raid outside a core loses 10, 10 and 10")
check(same(RT:GetPenalties(""), 10, 10, 10), "and the tracker reads the same")
CM:SetPenalty("LATE", 0, "")
check(same(CM:GetPenalties(""), 0, 10, 10), "a raid outside a core can have its own weights")
check(GuildOS.db.attendancePenalties.LATE == 0, "kept by CoreManager, outside the raid tracker's data")
CM:SetPenalty("NO_CONSUMES", 250, "")
CM:SetPenalty("LEFT_EARLY", -5, "")
check(same(CM:GetPenalties(""), 0, 0, 100), "a weight is held between 0 and 100")

-- ── A core inherits what it did not set ─────────────────────────────────
CM:Create("Main")
check(same(CM:GetPenalties("Main"), 0, 0, 100), "a core with no weights of its own takes the guild's")
CM:SetPenalty("LATE", 5, "Main")
check(same(CM:GetPenalties("Main"), 5, 0, 100), "and one it set is its own")
check(same(CM:GetPenalties(""), 0, 0, 100), "which leaves the guild's alone")

-- ── Attendance is scored with them ──────────────────────────────────────
-- One 25-man night outside a core, where Late arrived after the first snapshot and had no consumables.
local function night(start)
  local members = { ["On-Realm"] = { hasConsumes = true }, ["Late-Realm"] = { hasConsumes = false } }
  return { instanceID = 564, startTime = start, groupTag = "",
           players = { ["On-Realm"] = true, ["Late-Realm"] = true },
           snapshots = { { time = start, members = { ["On-Realm"] = { hasConsumes = true } } },
                         { time = start + 3600, members = members } } }
end
GuildOS.db.raidTracker.sessions = { [1789000000] = night(1789000000) }
for _, k in ipairs({ "LATE", "LEFT_EARLY", "NO_CONSUMES" }) do CM:SetPenalty(k, 0, "") end
RT:RebuildAttendanceFromSessions()
check(RT:GetAttendance25ManPercent("Late-Realm", "") == 100, "with every weight at 0, arriving late costs nothing")
CM:SetPenalty("LATE", 10, "")
CM:SetPenalty("NO_CONSUMES", 10, "")
RT:RebuildAttendanceFromSessions()
check(RT:GetAttendance25ManPercent("Late-Realm", "") == 80, "with 10 and 10 back, the same night scores 80")
check(RT:GetAttendance25ManPercent("On-Realm", "") == 100, "and somebody on time keeps 100")

print(("penalties: %d checks passed"):format(checks))
