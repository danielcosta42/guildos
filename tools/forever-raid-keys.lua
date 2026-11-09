-- Which planned raid a night is, by map id, in each game's own table (issue #291), run against the
-- real Core/Core.lua, Core/Compat.lua and Modules/RaidTracker.lua, once as each game.
--
-- WoW: Forever reuses Classic's map ids: its Onyxia's Lair is map 249, and map 534 there is not TBC's
-- Hyjal Summit. A Forever night stamped with TBC's "hyjal" would be matched to nothing, or to the
-- wrong raid; one with no key at all is matched by the site from the instance's name.
--
--   luajit -e 'ADDON="."' tools/forever-raid-keys.lua
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

local INSTANCE
local asked

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    function f:Hide() end
    return f
  end
  function hooksecurefunc() end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MAINLINE = 5, 1
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70707", "", 16001 end
    WOW_PROJECT_ID = 99
  elseif game == "anniversary" then
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_ID = 5
  else
    function GetBuildInfo() return "12.0.0", "60000", "", 120000 end
    WOW_PROJECT_ID = 1
  end
  function GetRealmName() return "Realm" end
  function UnitName() return "Me" end
  function GetServerTime() return 1790000000 end
  function IsInGuild() return true end
  function GetInstanceInfo() return unpack(INSTANCE) end
  C_Timer = { After = function() end, NewTicker = function() end, NewTimer = function() return { Cancel = function() end } end }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  GuildOS.db = { raidTracker = {}, settings = {} }
  GuildOS.SafeCall = function(_, fn, ...) return fn(...) end
  asked = nil
  GuildOS.CompanionImport = { RaidFor = function(_, key) asked = key; return key and ("raid-" .. key) or nil end }
  local RT = GuildOS.RaidTracker
  RT.TakeSnapshot = function() end
  RT.GetCurrentGroup = function() return nil end
  RT.SetGroupTag = function() end
  return RT
end

-- What a session started in this instance is stamped with.
local function stamp(RT, mapId, name, size)
  INSTANCE = { name, "raid", 0, "", size, 0, false, mapId }
  RT.trackingActive, RT.currentRaid, asked = false, nil, nil
  RT:StartSession(mapId)
  return RT.currentRaid and RT.currentRaid.raidId, asked
end

-- ── WoW: Forever ────────────────────────────────────────────────────
INSTANCE = { "", "none", 0, "", 0, 0, false, 0 }
local RT = load("forever")
check(not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail, "the harness runs as WoW: Forever")
check(RT:RaidKeyOf(249) == "forever-onyxia", "Forever's Onyxia's Lair is the site's forever-onyxia")
check(RT:RaidKeyOf(534) == nil, "map 534 is never TBC's hyjal on Forever")
check(RT:RaidKeyOf(532) == nil, "nor any other TBC map")
check(RT:RaidKeyOf(2912) == nil, "nor a Midnight one")

local id, key = stamp(RT, 249, "Onyxia's Lair", 40)
check(key == "forever-onyxia" and id == "raid-forever-onyxia", "an Onyxia night asks for and keeps the planned raid")
id, key = stamp(RT, 534, "Hyjal Summit", 20)
check(key == nil and id == nil, "a Forever night in an unknown map goes up with no raidId, for the site to match by name")

-- ── Anniversary: as it was ──────────────────────────────────────────
INSTANCE = { "", "none", 0, "", 0, 0, false, 0 }
RT = load("anniversary")
check(GuildOS.Client.isAnniversary, "the harness runs as Anniversary")
check(RT:RaidKeyOf(534) == "hyjal", "TBC's Hyjal Summit is still hyjal on Anniversary")
check(RT:RaidKeyOf(532) == "kara", "and Karazhan still kara")
check(RT:RaidKeyOf(249) == nil, "Forever's key never reaches Anniversary")
id, key = stamp(RT, 534, "Hyjal Summit", 25)
check(key == "hyjal" and id == "raid-hyjal", "a TBC Hyjal night is stamped as before")

-- ── Retail: as it was ───────────────────────────────────────────────
INSTANCE = { "", "none", 0, "", 0, 0, false, 0 }
RT = load("retail")
check(GuildOS.Client.isRetail, "the harness runs as retail")
check(RT:RaidKeyOf(2912) == "midnight-voidspire", "Midnight's raids keep their keys")
check(RT:RaidKeyOf(249) == nil, "Forever's key never reaches retail")

print("forever-raid-keys: " .. checks .. " checks passed")
