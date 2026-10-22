-- The core on retail (issue #184), run against the real Core/Compat.lua, Modules/CoreManager.lua and
-- Modules/RaidTools.lua under a stubbed retail client, and the same files as WoW: Forever and as TBC
-- Anniversary.
--
-- The core screen's raid-buff coverage was TBC's list and empty everywhere else, so retail showed no
-- buffs at all, while Raid Tools has Midnight's. And the role a member starts in came from the class
-- alone, while on retail the client names the role of the spec a member plays. This proves retail's
-- composition reads Raid Tools' table (one list, named by the client from the spell), that a scanned
-- spec sets the role a member starts in, melee or ranged by the spec, and that Forever and
-- Anniversary keep their lists and their class roles.
--
--   luajit -e 'ADDON="."' tools/retail-core.lua
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
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  if game == "retail" then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  elseif game == "forever" then
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  else
    function GetBuildInfo() return "2.5.6", "70006", "", 20506 end
    WOW_PROJECT_ID = 5
  end
  function GetRealmName() return "Azralon" end
  function GetNormalizedRealmName() return "Azralon" end
  function GetServerTime() return 1791000000 end
  -- The client names a spell in the reader's language.
  C_Spell = { GetSpellInfo = function(id) return { name = "spell:" .. id, spellID = id } end }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  dofile(ADDON .. "/Modules/RaidTools.lua")
  GuildOS.db = { cores = {}, members = {} }
  return GuildOS.CoreManager, GuildOS.RaidTools
end

local function withCore(CM, members)
  GuildOS.db.cores.Main = { members = members }
  return CM:GetComposition("Main")
end

-- ── 1. Retail: the composition's buffs are Raid Tools' ─────────────────
local CM, RT = load("retail")
check(GuildOS.Client.isRetail, "the stub is retail")
local comp = withCore(CM, {
  ["Ana-Azralon"] = { class = "PRIEST", role = "healer" },
  ["Bo-Gallywix"] = { class = "MAGE", role = "rdps" },
  ["Cy-Azralon"]  = { class = "EVOKER", role = "rdps" },
})
check(#comp.buffStatus == #RT.BUFFS and #RT.BUFFS > 0, "retail lists every one of Raid Tools' buffs")
local want = RT:ResolveCoverage(RT.BUFFS, RT:GetClassCounts({ { class = "PRIEST" }, { class = "MAGE" }, { class = "EVOKER" } }))
for i, w in ipairs(want) do
  local got = comp.buffStatus[i]
  check(got and got.name == w.name and got.covered == w.covered,
    "buff " .. i .. " is Raid Tools' own entry, in its order (" .. tostring(w.name) .. ")")
end
local byName = {}
for _, b in ipairs(comp.buffStatus) do byName[b.name] = b end
check(byName["spell:21562"] and byName["spell:21562"].covered, "Power Word: Fortitude is named by the client and covered by the priest")
check(byName["spell:1459"] and byName["spell:1459"].covered, "Arcane Intellect is covered by the mage")
check(byName["spell:364342"] and byName["spell:364342"].covered, "Blessing of the Bronze is covered by the evoker")
check(byName["spell:6673"] and not byName["spell:6673"].covered, "Battle Shout is missing: no warrior")
check(byName["spell:21562"].source == "PRIEST", "a buff still names the class that brings it")
C_Spell = nil
comp = withCore(CM, { ["Ana-Azralon"] = { class = "PRIEST" } })
check(comp.buffStatus[1].name == "Power Word: Fortitude", "a spell the client cannot name falls back to Raid Tools' English")

-- ── 2. Retail: a scanned spec sets the role a member starts in ─────────
local M = GuildOS.db.members
M["Bo-Gallywix"]  = { spec = { specID = 255, tree = "Survival", role = "DAMAGER" } }
M["Cy-Azralon"]   = { spec = { specID = 253, tree = "Beast Mastery", role = "DAMAGER" } }
M["Di-Azralon"]   = { spec = { specID = 1480, tree = "Devourer", role = "DAMAGER" } }
M["Ed-Azralon"]   = { spec = { specID = 581, tree = "Vengeance", role = "TANK" } }
M["Fa-Azralon"]   = { spec = { specID = 65, tree = "Holy", role = "HEALER" } }
M["Gu-Azralon"]   = { spec = { specID = 1473, tree = "Augmentation", role = "DAMAGER" } }
M["Hu-Azralon"]   = { spec = { specID = 72, tree = "Fury", role = "DAMAGER" } }
M["Iz-Azralon"]   = { spec = { specID = 65, tree = "Holy", role = "HEALER" } }   -- a healer spec on a warrior: corrupt
check(CM:DefaultRole("HUNTER", "Bo-Gallywix") == "mdps", "Survival starts in melee")
check(CM:DefaultRole("HUNTER", "Cy-Azralon") == "rdps", "Beast Mastery starts in ranged")
check(CM:DefaultRole("DEMONHUNTER", "Di-Azralon") == "rdps", "Devourer starts in ranged")
check(CM:DefaultRole("DEMONHUNTER", "Ed-Azralon") == "tank", "Vengeance starts as a tank")
check(CM:DefaultRole("PALADIN", "Fa-Azralon") == "healer", "a Holy paladin starts as a healer")
check(CM:DefaultRole("EVOKER", "Gu-Azralon") == "rdps", "Augmentation starts in ranged")
check(CM:DefaultRole("WARRIOR", "Hu-Azralon") == "mdps", "Fury starts in melee")
check(CM:DefaultRole("WARRIOR", "Iz-Azralon") == "mdps", "a role the class cannot play falls back to the class's own")
check(CM:DefaultRole("DEMONHUNTER", "Nobody-Azralon") == "mdps" and CM:DefaultRole("DEMONHUNTER") == "mdps",
  "no scanned spec: the class's own")
check(CM:RoleFor("DEMONHUNTER", nil, "Ed-Azralon") == "tank", "a sign-up with no pick takes the spec's role")
check(CM:RoleFor("DEMONHUNTER", "mdps", "Ed-Azralon") == "mdps", "a picked role the class can play is kept")
check(CM:RoleFor("PALADIN", "rdps", "Fa-Azralon") == "healer", "a pick the class cannot play takes the spec's role")
check(CM:GetRoleForClass("HUNTER", "Bo-Gallywix") == "mdps", "the core screen's default asks the same rule")
check(CM:SpecRole({ tree = "Holy", points = { 41, 5, 15 } }) == nil, "a classic spec names no role")

-- Every caller hands the member's key over.
local function src(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
check(src("UI/FeaturePanels.lua"):find("CM:RoleFor(pClass, f.pickedRole, playerKey)", 1, true),
  "the sign-up window offers the spec's role first")
local panel = src("UI/CorePanel.lua")
check(panel:find("GuildOS.CoreManager:DefaultRole(class, key)", 1, true)
  and panel:find("InferRole(captureGM.class, addGMKey)", 1, true),
  "the core screen's member picker starts a member in their spec's role")
local cm = src("Modules/CoreManager.lua")
check(cm:find("self:RoleFor(cls, role, playerKey)", 1, true) and cm:find("self:RoleFor(cls, info.role, playerKey)", 1, true),
  "my own sign-up, and the officer who stores one, ask with the member's key")

-- ── 3. Forever keeps its empty list and its class roles ────────────────
CM = load("forever")
check(not GuildOS.Client.isRetail and not GuildOS.Client.isAnniversary, "the stub is Forever")
comp = withCore(CM, { ["Ana"] = { class = "PRIEST" } })
check(#comp.buffStatus == 0, "Forever lists no raid buffs (issue #92)")
GuildOS.db.members["Bo"] = { spec = { specID = 255, role = "DAMAGER" } }
check(CM:DefaultRole("HUNTER", "Bo") == "rdps" and CM:RoleFor("PRIEST", nil, "Bo") == "rdps",
  "Forever starts a member in the class's role")

-- ── 4. Anniversary keeps TBC's list ───────────────────────────────────
CM = load("anniversary")
check(GuildOS.Client.isAnniversary, "the stub is Anniversary")
comp = withCore(CM, { ["Ana-Azralon"] = { class = "PRIEST" } })
check(#comp.buffStatus == 11 and comp.buffStatus[5].name == "Power Word: Fortitude" and comp.buffStatus[5].covered
  and not comp.buffStatus[1].covered, "Anniversary keeps TBC's eleven buffs")
check(CM:DefaultRole("PRIEST", "Ana-Azralon") == "healer", "and its class roles")

print(("retail-core: %d checks passed"):format(checks))
