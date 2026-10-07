-- The talent tree on WoW: Forever (issue #41), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua and Modules/SpecChecker.lua under a stubbed client.
--
-- Forever has no talent tabs. Each class is one trait tree with the three classic trees
-- side by side in it, so a Restoration shaman published no spec at all and the site made
-- them Melee, the class's first role. The node positions below are the real ones, from
-- the TraitNode table of build 1.60.1.70009: if the reading of the layout is wrong, it is
-- wrong here.
--
--   luajit -e 'ADDON="."' tools/forever-spec.lua
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
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
function GetServerTime() return 1757800000 end
function GetRealmName() return "Classic Beta PvE 2" end
function UnitName() return "Chehul" end
function UnitFullName() return "Chehul", "Shammy" end
local class = "SHAMAN"
function UnitClass() return class, class end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/SpecChecker.lua")
local SpecChecker = GuildOS.SpecChecker
GuildOS.db = { members = {} }

-- ── The real trees ──────────────────────────────────────────────────────
-- [nodeID] = PosX. Shaman: Elemental 1020–2820, Enhancement 5020–6820, Restoration 9080–10880.
local SHAMAN = { [104724] = 9680, [104725] = 10280, [104726] = 10280, [104727] = 9680, [104728] = 10280, [104729] = 10280, [104730] = 9680, [104731] = 9080, [104732] = 10280, [104733] = 9680, [104734] = 9080, [104735] = 10280, [104736] = 9680, [104737] = 10880, [104738] = 9080, [104739] = 9680, [104740] = 5620, [104741] = 6220, [104742] = 6220, [104743] = 6220, [104744] = 5620, [104745] = 5020, [104746] = 5020, [104747] = 5620, [104748] = 6820, [104749] = 6220, [104750] = 5020, [104751] = 6820, [104752] = 6220, [104753] = 5620, [104754] = 5020, [104755] = 5620, [104756] = 6220, [104757] = 5020, [104758] = 1620, [104759] = 1620, [104760] = 2820, [104761] = 1020, [104762] = 2220, [104763] = 1620, [104764] = 1020, [104765] = 2220, [104766] = 2220, [104767] = 1620, [104768] = 1620, [104769] = 2820, [104770] = 2220, [104771] = 1020, [104772] = 2220, [104773] = 1620 }
-- Hunter: the same three bands, plus a stale Lightning Reflexes (104982) at 102800; the
-- live one (110859) is in Survival.
local HUNTER = { [104960] = 1620, [104961] = 1620, [104962] = 2220, [104963] = 2820, [104964] = 1620, [104965] = 1020, [104966] = 2820, [104967] = 2220, [104968] = 1020, [104969] = 2220, [104970] = 1620, [104972] = 2820, [104973] = 2220, [104974] = 1620, [104975] = 1020, [104976] = 2220, [104981] = 10880, [104982] = 102800, [104983] = 9080, [104984] = 9680, [104985] = 9680, [104986] = 10280, [104987] = 9680, [104988] = 9080, [104989] = 10280, [104990] = 10880, [104991] = 9080, [104992] = 10280, [104993] = 9680, [104994] = 9080, [104995] = 10280, [104996] = 9680, [104997] = 5620, [104998] = 6220, [104999] = 5020, [105000] = 6820, [105001] = 6220, [105002] = 6220, [105003] = 6820, [105004] = 5620, [105005] = 5020, [105006] = 5620, [105007] = 6820, [105008] = 6220, [105009] = 5620, [105011] = 6220, [105012] = 5620, [105013] = 5020, [110859] = 10280, [110860] = 10280, [110861] = 9680, [110870] = 5020 }

-- ── The trait API, over one tree and the ranks bought on it ─────────────
local tree, bought, configID = SHAMAN, {}, 7
local function useTraits()
  C_ClassTalents = { GetActiveConfigID = function() return configID end }
  C_Traits = {
    GetConfigInfo = function(id) return id and { ID = id, treeIDs = { 1082 } } or nil end,
    GetTreeNodes = function()
      local ids = {}
      for id in pairs(tree) do ids[#ids + 1] = id end
      return ids
    end,
    GetNodeInfo = function(_, id) return { ID = id, posX = tree[id], ranksPurchased = bought[id] or 0 } end,
  }
end
local function buy(ids, ranks)
  bought = {}
  for _, id in ipairs(ids) do bought[id] = ranks end
end

-- Anniversary's tab API is absent on Forever: that is what sends SpecChecker to the tree.
GetNumTalentTabs, GetNumTalents, GetTalentInfo = nil, nil, nil
useTraits()

-- A level 20 Restoration shaman: 11 points, all in the right-hand band.
buy({ 104739, 104729, 104736, 104735 }, 2) -- 8
bought[104734] = 3                         -- 11
local spec, why = SpecChecker:CollectOwnSpec()
check(spec and spec.tree == "Restoration", "a shaman with every point in the right-hand band is Restoration, not " .. tostring(spec and spec.tree or why))
check(spec.points[1] == 0 and spec.points[2] == 0 and spec.points[3] == 11, "the points land in the third tree")
local own = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
check(GuildOS.db.members[own] and GuildOS.db.members[own].spec == spec, "the spec is kept on the player's own row")

buy({ 104743, 104747, 104753 }, 3)
check(SpecChecker:CollectOwnSpec().tree == "Enhancement", "the middle band is Enhancement")
buy({ 104773, 104772, 104759 }, 3)
check(SpecChecker:CollectOwnSpec().tree == "Elemental", "the left band is Elemental")

-- The stale Hunter node counts for Survival, its nearest tree, and is not a fourth tree.
class, tree = "HUNTER", HUNTER
buy({ 104982 }, 5)
bought[104960] = 2
spec = SpecChecker:CollectOwnSpec()
check(spec and spec.tree == "Survival" and spec.points[3] == 5 and spec.points[1] == 2,
  "the stale Lightning Reflexes counts for Survival, got " .. tostring(spec and spec.tree))

-- Nothing to read yet: the collector waits rather than publishing a tree nobody picked.
buy({}, 0)
spec, why = SpecChecker:CollectOwnSpec()
check(spec == nil and why == "no-points", "no point spent is no spec yet, and says why")
configID = nil
spec, why = SpecChecker:CollectOwnSpec()
check(spec == nil and why == "no-config", "talents not loaded is no spec yet, and says why")

-- A client with neither tabs nor trait trees keeps saying no-api, which the collector
-- reads as absent for good.
C_ClassTalents, C_Traits = nil, nil
spec, why = SpecChecker:CollectOwnSpec()
check(spec == nil and why == "no-api", "no talent API of either kind is no-api")

-- Three trees are required: any other shape is not read as a spec.
check(SpecChecker.ColumnPoints({ { x = 0, points = 1 }, { x = 600, points = 1 } }) == nil, "one band is not three trees")

print(("forever-spec: %d checks passed"):format(checks))
