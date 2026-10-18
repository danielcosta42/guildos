-- Retail's thirteen classes (issue #166), run against the real Core/Compat.lua, Core/Data.lua and the
-- modules that list classes, under a stubbed retail client and a stubbed WoW: Forever one.
--
-- Retail has the nine classic classes and four more: Death Knight, Demon Hunter, Monk and Evoker.
-- Every list of classes the addon offers (raid composition, recruitment, the beacon, roles and
-- colours) comes from GuildOS.Client.classes, so a retail guild's Evoker is counted, recruited and
-- coloured; Forever keeps its nine. Raid Tools' buffs and cooldowns are Midnight's on retail,
-- named by the client from the spell.
--
--   luajit -e 'ADDON="."' tools/retail-classes.lua
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
function GetServerTime() return 1791000000 end
time = os.time
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                       { __call = function() return {} end })
-- The client names a spell in the reader's language; here, in English.
local SPELLS = { [364342] = "Blessing of the Bronze", [2825] = "Bloodlust", [80353] = "Time Warp", [20484] = "Rebirth" }
C_Spell = { GetSpellInfo = function(id) return SPELLS[id] and { name = SPELLS[id] } or nil end }

local function load(retail)
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 99, 1, 5
  end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test",
              SelfTest = { Register = function() end } }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Modules/RaidTools.lua")
  dofile(ADDON .. "/Modules/RecruitBeacon.lua")
  dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
end

local NEW = { "DEATHKNIGHT", "DEMONHUNTER", "MONK", "EVOKER" }
local function has(list, x)
  for _, v in ipairs(list) do if v == x then return true end end
  return false
end

-- ── Retail ──────────────────────────────────────────────────────────
load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
for _, list in ipairs({
  { GuildOS.RaidTools.CLASS_ORDER, "Raid Tools' composition" },
  { GuildOS.RecruitBeacon.CLASS_TOKENS, "the recruit beacon" },
  { GuildOS.Recruitment.CLASSES, "recruitment" },
}) do
  check(#list[1] == 13, list[2] .. " lists thirteen classes on retail")
  for _, c in ipairs(NEW) do check(has(list[1], c), list[2] .. " lists " .. c .. " on retail") end
end
local CM = GuildOS.CoreManager
for _, c in ipairs(GuildOS.Client.classes) do
  check(GuildOS.ClassColors[c] ~= nil, c .. " has a colour")
  check(CM.CLASS_DEFAULT_ROLE[c] ~= nil, c .. " starts in a role")
  check(#CM:RolesFor(c) > 0, c .. " can sign up for a role")
  check(CM.CLASS_ROLES[c][CM.CLASS_DEFAULT_ROLE[c]], c .. "'s default role is one it can play")
end
check(CM.CLASS_ROLES.EVOKER.healer and CM.CLASS_ROLES.EVOKER.rdps and not CM.CLASS_ROLES.EVOKER.tank, "an Evoker heals or casts")
check(CM.CLASS_ROLES.HUNTER.mdps and CM.CLASS_ROLES.HUNTER.rdps, "a retail Hunter can be melee (Survival)")
-- A core's size is one retail raids have: flex up to 30, mythic at 20; no 40.
check(table.concat(CM:RaidSizes(), ",") == "10,20,30", "a retail core is 10, 20 or 30")
local t30 = CM:RaidTargets(30)
check(t30 and t30.tank + t30.healer + t30.mdps + t30.rdps == 30, "a 30-player core has a composition that adds up")

local RT = GuildOS.RaidTools
local function covered(defs, counts)
  local out = {}
  for _, d in ipairs(RT:ResolveCoverage(defs, counts)) do out[d.name] = d.covered end
  return out
end
local buffs = covered(RT.BUFFS, { EVOKER = 1 })
check(buffs["Blessing of the Bronze"] == true, "an Evoker brings Blessing of the Bronze on retail, named by the client")
check(buffs["Spirit"] == nil and buffs["Blessings"] == nil, "TBC's buffs are not retail's")
local cds = covered(RT.COOLDOWNS, { MAGE = 1 })
check(cds["Bloodlust"] == true, "a Mage covers Bloodlust on retail")
check(covered(RT.COOLDOWNS, { DEATHKNIGHT = 1 })["Rebirth"] == true, "a Death Knight covers the battle rez on retail")

-- ── WoW: Forever keeps its nine ─────────────────────────────────────
load(false)
check(not GuildOS.Client.isRetail, "the stub is Forever")
check(#GuildOS.RaidTools.CLASS_ORDER == 9 and #GuildOS.RecruitBeacon.CLASS_TOKENS == 9 and #GuildOS.Recruitment.CLASSES == 9,
  "Forever lists nine classes")
check(not has(GuildOS.Recruitment.CLASSES, "MONK"), "no Monk on Forever")
check(not GuildOS.CoreManager.CLASS_ROLES.HUNTER.mdps, "a Forever Hunter is ranged")
check(table.concat(GuildOS.CoreManager:RaidSizes(), ",") == "10,20,40", "a Forever core is 10, 20 or 40")
check(covered(GuildOS.RaidTools.BUFFS, { PRIEST = 1 })["Spirit"] == true, "Forever keeps its own buff list")

print(("retail-classes: %d checks passed"):format(checks))
