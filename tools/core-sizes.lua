-- The raid formats a core can plan for, per game (issue #89), run against the real
-- Core/Core.lua, Core/Compat.lua and Modules/CoreManager.lua, once as each game.
--
-- CoreManager knew TBC's 10 and 25 only, and its setter turned anything but 10 into 25: a
-- WoW: Forever guild, whose raids are 10 and 20 with Onyxia at 40, could plan for neither.
--
--   luajit -e 'ADDON="."' tools/core-sizes.lua
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

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  function GetRealmName() return "Realm" end
  function GetServerTime() return 1790000000 end
  Enum = { SendAddonMessageResult = {} }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  BRutus.db = { cores = {} }
  local CM = BRutus.CoreManager
  CM:Create("Main")
  return CM
end

local function list(t) return table.concat(t, ",") end
local function targetsAddUp(CM)
  for _, size in ipairs(CM:RaidSizes()) do
    local t = CM:RaidTargets(size)
    if not t or t.tank + t.healer + t.mdps + t.rdps ~= size then return false, size end
  end
  return true
end

-- ── 1. WoW: Forever: 10, 20 and 40 ──────────────────────────────────────
local CM = load("forever")
check(list(CM:RaidSizes()) == "10,20,40", "Forever: a core plans for 10, 20 or 40 players")
check(CM:GetRaidSize("Main") == 20, "Forever: a new core is a 20-player one, the size of each tier's main raid")
check(CM:NextRaidSize(10) == 20 and CM:NextRaidSize(20) == 40 and CM:NextRaidSize(40) == 10,
  "Forever: the format button goes 10, 20, 40 and round")
CM:SetRaidSize("Main", 40)
check(CM:GetRaidSize("Main") == 40, "Forever: 40 is kept")
CM:SetRaidSize("Main", 10)
check(CM:GetRaidSize("Main") == 10, "Forever: 10 is kept")
CM:SetRaidSize("Main", 25)
check(CM:GetRaidSize("Main") == 20 and BRutus.db.cores.Main.raidSize == 20,
  "Forever: a size the game does not have is stored as the default, not 25")
BRutus.db.cores.Main.raidSize = 25                      -- saved by a version that only knew TBC
check(CM:GetRaidSize("Main") == 20 and CM:NextRaidSize(CM:GetRaidSize("Main")) == 40 and CM:NextRaidSize(25) == 40,
  "Forever: a 25 saved before reads as the default, and the button moves on from it")
check(CM:RaidTargets(25) == CM:RaidTargets(20) and CM:RaidTargets(nil) == CM:RaidTargets(20),
  "Forever: a size the game lacks is planned with the default's targets, never TBC's 25")
local ok, bad = targetsAddUp(CM)
check(ok, "Forever: every format's composition adds up to its size (" .. tostring(bad) .. ")")

-- ── 2. TBC Anniversary: as it was ───────────────────────────────────────
CM = load("anniversary")
check(list(CM:RaidSizes()) == "10,25", "Anniversary: a core plans for 10 or 25 players, as before")
check(CM:GetRaidSize("Main") == 25, "Anniversary: a new core is still a 25-player one")
check(CM:NextRaidSize(10) == 25 and CM:NextRaidSize(25) == 10, "Anniversary: the button still goes 10, 25 and round")
CM:SetRaidSize("Main", 10)
check(CM:GetRaidSize("Main") == 10, "Anniversary: 10 is kept")
CM:SetRaidSize("Main", 40)
check(CM:GetRaidSize("Main") == 25 and BRutus.db.cores.Main.raidSize == 25,
  "Anniversary: a size the game does not have becomes 25")
ok, bad = targetsAddUp(CM)
check(ok, "Anniversary: every format's composition adds up to its size (" .. tostring(bad) .. ")")
local function same(t, T, H, M, R) return t.tank == T and t.healer == H and t.mdps == M and t.rdps == R end
check(same(CM:RaidTargets(25), 2, 6, 9, 8) and same(CM:RaidTargets(10), 2, 2, 3, 3),
  "Anniversary: the targets are the ones it had")

-- ── 3. The screens ask CoreManager, not their own list ──────────────────
local function read(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local panel = read("UI/CorePanel.lua")
check(panel:find("CM:NextRaidSize(", 1, true) and panel:find("CM:SetRaidSize(coreName, curSize)", 1, true)
  and not panel:find("(curSize == 25) and 10 or 25", 1, true) and not panel:find('"25-man"', 1, true),
  "the core's format button cycles through CoreManager's sizes")
for _, path in ipairs({ "UI/CorePanel.lua", "UI/FeaturePanels.lua" }) do
  check(not read(path):find("RAID_TARGETS%s*%["), path .. " asks RaidTargets, never indexes RAID_TARGETS itself")
end

print(("core-sizes: %d checks passed"):format(checks))
