-- The attendance a roll is judged by is the raid's own core's (issue #134), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua and Modules/LootMaster.lua.
--
-- A raider can be on several cores (#132). The loot rules (minimum attendance for MS, the attendance
-- tiebreaker) are the raid's core's config, so the attendance compared to them is that core's too:
-- not the core where the raider has the most raids, which on Forever can be a 10 whose nights never
-- count for progression, reading 0% in a 20.
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
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70170", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetRealmName() return "Realm" end
function UnitName() return "Chehul" end
function GetServerTime() return 1790000000 end
function GetTime() return 1000 end
time = function() return 1790000000 end
function IsInGuild() return true end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end, NewTicker = function() end }
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
GuildOS.db = { lootMaster = {}, lootHistory = {} }

-- Ana: every night of the 20, half of the 40's; she has the most raids on the 40.
local ATT = { Twenty = 100, Forty = 50 }
local asked = {}
local active = "Twenty"
GuildOS.RaidTracker = {
  GetCurrentGroup = function() return active end,
  GetAttendance25ManPercent = function(_, _, tag)
    asked[#asked + 1] = tag == nil and "(the raider's own)" or tag
    return tag == nil and ATT.Forty or ATT[tag] or 0
  end,
}
local LM = GuildOS.LootMaster

local ctx = LM:GetPlayerContext("Ana")
check(ctx.att25 == 100 and asked[#asked] == "Twenty", "in a raid of the 20, Ana is judged by the 20's attendance, not the 40's")
active = "Forty"
check(LM:GetPlayerContext("Ana").att25 == 50, "and in a raid of the 40, by the 40's")
active = ""
check(LM:GetPlayerContext("Ana").att25 == 50 and asked[#asked] == "(the raider's own)",
  "with no core active, as before: the core where the raider raids most")

print(("loot-attendance: %d checks passed"):format(checks))
