-- The member sheet's stats on retail (issue #184), run against the real Core/Compat.lua and
-- Modules/DataCollector.lua under a stubbed retail client and a stubbed WoW: Forever one.
--
-- The sheet showed the classic HP, MP, STR, AGI, STA, INT and SPI everywhere, and asked UnitStat for
-- a fifth stat (spirit) retail does not have. Retail's character sheet is the spec's primary stat,
-- stamina, and four ratings in percent: crit, haste, mastery and versatility. This proves retail
-- collects those, read through Compat and never a secret one, never asks for spirit, and that
-- Forever keeps its seven.
--
--   luajit -e 'ADDON="."' tools/retail-stats.lua
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

local SECRET = {}
local SPEC = 1
local function load(retail)
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  function GetRealmName() return "Azralon" end
  issecretvalue = function(v) return v == SECRET end
  function UnitHealthMax() return 500000 end
  function UnitPowerMax() return 250000 end
  -- Retail's UnitStat knows four stats; a fifth is an error there, as the client gives one.
  function UnitStat(_, i)
    if retail and i == 5 then error("UnitStat: no fifth stat on retail") end
    return ({ 1100, 9000, 40000, 1200, 300 })[i]
  end
  -- A Beast Mastery hunter: agility (2) is the primary stat.
  C_SpecializationInfo = {
    GetSpecialization = function() return SPEC end,
    GetSpecializationInfo = function(i) if i == 1 then return 253, "Beast Mastery", "", 0, "DAMAGER", 2 end end,
  }
  CR_VERSATILITY_DAMAGE_DONE = 29
  -- Spell crit decides: its weakest school (2, at 30) beats melee and ranged; its strongest is 35.
  function GetCritChance() return 20.123 end
  function GetRangedCritChance() return 25.456 end
  function GetSpellCritChance(school) return 28 + school end
  function GetHaste() return 15.5 end
  function GetMasteryEffect() return 30.25, 1.2 end
  function GetCombatRatingBonus(cr) return cr == 29 and 5 or 0 end
  function GetVersatilityBonus(cr) return cr == 29 and 1 or 0 end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), SelfTest = { Register = function() end } }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Modules/DataCollector.lua")
  GuildOS.UI, GuildOS.Colors = {}, {}
  dofile(ADDON .. "/UI/MemberDetail.lua")
  return GuildOS.DataCollector, GuildOS.Compat
end

-- The sheet's cells as "label=text" in order.
local function cells(stats)
  local out = {}
  for _, c in ipairs(GuildOS:MemberStatCells(stats)) do out[#out + 1] = c.label .. "=" .. c.text end
  return table.concat(out, " ")
end

-- ── 1. Retail: the spec's primary stat, stamina and the four ratings ───
local DC, Compat = load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
local ok, s = pcall(DC.CollectStats, DC)
check(ok, "collecting stats on retail asks for no fifth stat: " .. tostring(s))
check(s.health == 500000 and s.stamina == 40000, "health and stamina are read")
check(s.primary == "agility" and s.agility == 9000, "the spec's primary stat is named and read")
check(s.strength == nil and s.intellect == nil, "the other two primary stats are not shown")
check(s.spirit == nil and s.mana == nil, "no spirit, and no mana bar")
check(s.crit == 30, "crit is the best of melee, ranged and the weakest spell school: " .. tostring(s.crit))
check(s.haste == 15.5 and s.mastery == 30.25 and s.versatility == 6, "haste, mastery, and versatility's rating plus its bonus")
GetSpellCritChance = function(school) return 10 + school end
check(DC:CollectStats().crit == 25.46, "ranged wins when it beats every school, to two decimals")

-- The sheet draws them: the primary stat by which one it is, the ratings in percent.
local sheet = cells(s)
check(sheet == "HP=500000 AGI=9000 STA=40000 Crit=30.0% Haste=15.5% Mastery=30.3% Vers=6.0%",
  "retail's sheet: HP, the primary stat, stamina and the four ratings in percent (" .. sheet .. ")")
check(cells({ health = 1, stamina = 2 }) == "HP=1 STA=2 Crit=0.0% Haste=0.0% Mastery=0.0% Vers=0.0%",
  "a member who sent no primary stat shows none, and missing ratings read 0")
local ok2, odd = pcall(cells, { primary = "intellect", intellect = "lots", crit = "high", haste = {}, mastery = "12.5" })
check(ok2 and odd == "HP=0 INT=0 STA=0 Crit=0.0% Haste=0.0% Mastery=12.5% Vers=0.0%",
  "a guildmate's value that is not a number shows 0 rather than stopping the sheet: " .. tostring(odd))
check(pcall(cells, "nonsense") and cells("nonsense") == "", "and stats that are not a table draw nothing")

GetHaste = function() return SECRET end
GetCritChance, GetRangedCritChance, GetSpellCritChance = nil, nil, nil
s = DC:CollectStats()
check(s.haste == nil, "a secret rating is left out")
check(s.crit == nil, "and so is one the client cannot give")
SPEC = 0
s = DC:CollectStats()
check(s.primary == nil and s.stamina == 40000, "before there is a spec, no primary stat: stamina still shows")
C_SpecializationInfo.GetSpecialization = function() return SECRET end
check(Compat.PrimaryStat() == nil, "a secret spec index names no primary stat")

-- ── 2. Forever keeps its seven ────────────────────────────────────────
SPEC = 1
DC, Compat = load(false)
check(not GuildOS.Client.isRetail, "the stub is Forever")
s = DC:CollectStats()
check(s.health == 500000 and s.mana == 250000 and s.strength == 1100 and s.agility == 9000 and s.stamina == 40000
  and s.intellect == 1200 and s.spirit == 300, "Forever collects HP, MP and the five classic stats")
check(s.crit == nil and s.primary == nil, "and no retail rating")
check(Compat.SecondaryStats() == nil and Compat.PrimaryStat() == nil, "Compat reads no rating off retail")
sheet = cells(s)
check(sheet == "HP=500000 MP=250000 STR=1100 AGI=9000 STA=40000 INT=1200 SPI=300",
  "Forever's sheet keeps its seven (" .. sheet .. ")")

local f = assert(io.open(ADDON .. "/UI/MemberDetail.lua", "rb"))
local md = f:read("*a")
f:close()
check(md:find("GuildOS:MemberStatCells(data.stats)", 1, true) and md:find("value:SetText(stat.text)", 1, true),
  "the sheet draws exactly these cells")

print(("retail-stats: %d checks passed"):format(checks))
