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
check(RT:Is25Man(2912, 30) and RT:Is25Man(2912, 20) and RT:Is25Man(2912, 12),
  "every tracked retail raid is progression, whatever its size")
check(RT:ProgLabel("No 25-man raids recorded for group: ") == "No N/H/M raids recorded for group: ",
  "the progression label names the difficulties")
check(RT:ProgLabel("(%d/%d raids, 25-man)") == "(%d/%d raids, N/H/M)", "in every label")

RT.TakeSnapshot = function() end
printed = {}
RT:StartSession(2912)
local said = table.concat(printed, "\n")
check(said:find("The Voidspire (Heroic)", 1, true) ~= nil, "the session says its difficulty when it starts")
check(RT.currentRaid.difficulty == 15, "and keeps it")

-- ── WoW: Forever keeps its rule ─────────────────────────────────────
RT = load(false)
check(not GuildOS.Client.isRetail, "the stub is Forever")
check(RT:IsTracked(9001, 3) and RT:IsTracked(9001, 17), "Forever tracks every raid")
check(RT:Is25Man(9001, 20) and not RT:Is25Man(9001, 10), "Forever's progression is 20 and up")
check(RT:ProgLabel("(%d/%d raids, 25-man)") == "(%d/%d raids, 20+ man)", "Forever's label is 20+")

print(("retail-raids: %d checks passed"):format(checks))
