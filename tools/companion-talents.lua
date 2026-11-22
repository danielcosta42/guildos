-- The talents and the random suffix the companion export carries (issue #399), run against the real
-- Core/Compat.lua, Core/Data.lua, Core/Utils.lua, Modules/SpecChecker.lua and
-- Modules/DataCollector.lua under a stubbed WoW: Forever client, then an Anniversary and a retail one.
--
-- A character is more than its item ids: an "of the Monkey" cloak has its stats in the suffix, and
-- the tree is what the character does with them. Talents go by the game's own talent id
-- (definitionID) and rank; the suffix is the link's field after the four gems, sign kept. Both are
-- absent when unknown. tools/companion-payload.lua checks how they reach the payload.
--
--   luajit -e 'ADDON="."' tools/companion-talents.lua
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

-- ── The trait API: nodes, the entry each one has chosen, and its rank ────────────
-- [nodeID] = { entryID, rank }; [entryID] = definitionID. Node 3 is a choice node: its active entry
-- is the second of its two.
local nodes, defs, configID, inspectConfig
local function useTraits()
  C_ClassTalents = { GetActiveConfigID = function() return configID end }
  C_Traits = {
    GetConfigInfo = function(id)
      if id == configID or (inspectConfig and id == inspectConfig) then return { ID = id, treeIDs = { 1082 } } end
      return nil
    end,
    GetTreeNodes = function()
      local ids = {}
      for id in pairs(nodes) do ids[#ids + 1] = id end
      return ids
    end,
    GetNodeInfo = function(_, id)
      local n = nodes[id]
      return { ID = id, posX = 1000, currentRank = n[2], ranksPurchased = n[2],
               activeEntry = n[1] and { entryID = n[1], rank = n[2] } or nil }
    end,
    GetEntryInfo = function(_, entryID) return defs[entryID] and { definitionID = defs[entryID] } or nil end,
  }
end

local LINKS = {
  -- No suffix: its field is 0.
  [1]  = "|cffa335ee|Hitem:12620:1503:0:0:0:0:0:0:60|h[Enchanted Thorium Helm]|h|r",
  -- A cloak with a suffix, as a modern client writes it: empty fields between.
  [15] = "|cff1eff00|Hitem:10148:2621:::::590:12345:60:::::|h[Mighty Cloak of the Monkey]|h|r",
  -- A negative suffix id keeps its sign.
  [16] = "|cff1eff00|Hitem:15216::::::-22:987654:60|h[Rune Sword of Agility]|h|r",
  -- Short: no suffix field at all.
  [17] = "|cffffffff|Hitem:6948|h[Hearthstone]|h|r",
}

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  function hooksecurefunc() end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "71037", "", 16001 end
    WOW_PROJECT_ID = 99
    GetNumTalentTabs, GetNumTalents, GetTalentInfo = nil, nil, nil
  elseif game == "anniversary" then
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_ID = 5
    function GetNumTalentTabs() return 3 end
    function GetNumTalents() return 0 end
    function GetTalentInfo() return nil end
  else
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  end
  function GetServerTime() return 1791000000 end
  time = function() return 1791000000 end
  function GetRealmName() return "Classic Beta PvE 2" end
  function UnitName() return "Chehul" end
  function UnitFullName() return "Chehul", "Costa" end
  function UnitClass() return "Warrior", "WARRIOR" end
  strsplit = function(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return unpack(out)
  end
  tinsert = table.insert
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  C_Item = {
    GetItemInfo = function(link) return link:match("%[(.-)%]"), link, 2, 50 end,
    GetItemInfoInstant = function(id) return id, "", "", "", 0, 4, 0 end,
  }
  function GetItemInfo(link) return C_Item.GetItemInfo(link) end
  function GetInventoryItemLink(_, slot) return LINKS[slot] end
  Enum = { SendAddonMessageResult = {} }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test",
              SelfTest = { Register = function() end } }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/SpecChecker.lua")
  dofile(ADDON .. "/Modules/DataCollector.lua")
  GuildOS.db = { members = {} }
end

local function json(list)
  local parts = {}
  for _, p in ipairs(list or {}) do parts[#parts + 1] = "[" .. p[1] .. "," .. p[2] .. "]" end
  return "[" .. table.concat(parts, ",") .. "]"
end

-- ── WoW: Forever ────────────────────────────────────────────────────────
load("forever")
check(not GuildOS.Client.isRetail and not GuildOS.Client.isAnniversary, "the stub is Forever")
local Compat, SpecChecker, DC = GuildOS.Compat, GuildOS.SpecChecker, GuildOS.DataCollector

configID, inspectConfig = 7, nil
nodes = { [101] = { 501, 3 }, [102] = { 502, 0 }, [103] = { 504, 1 }, [104] = { nil, 2 } }
defs = { [501] = 135489, [502] = 135470, [503] = 135500, [504] = 135469 }
useTraits()
local talents, why = SpecChecker:CollectOwnTalents()
check(json(talents) == "[[135469,1],[135489,3]]",
  "only the talents with a rank, by definitionID, sorted; the choice node's chosen entry: " .. json(talents) .. " " .. tostring(why))

-- Absent when there is nothing to read, and the caller is told why.
nodes = { [101] = { 501, 0 } }
talents, why = SpecChecker:CollectOwnTalents()
check(talents == nil and why == "no-points", "no point bought: nil, no-points (never an empty tree)")
configID = nil
talents, why = SpecChecker:CollectOwnTalents()
check(talents == nil and why == "no-config", "the tree not loaded: nil, no-config")
configID = 7
local entryInfo = C_Traits.GetEntryInfo
C_Traits.GetEntryInfo = nil
talents, why = Compat.TraitTalents()
check(talents == nil and why == "no-api", "a trait API without entries: no-api")
C_Traits.GetEntryInfo = function() error("the client said no") end
nodes = { [101] = { 501, 2 } }
talents, why = Compat.TraitTalents()
check(talents == nil and why == "error", "a trait API that raises is caught: nil, error")
C_Traits.GetEntryInfo = entryInfo
C_ClassTalents, C_Traits = nil, nil
talents, why = SpecChecker:CollectOwnTalents()
check(talents == nil and why == "no-api", "no trait API at all: no-api")
useTraits()

-- The collect keeps what it read before while the tree is not readable, and the broadcast carries it.
nodes = { [101] = { 501, 3 } }
local own = GuildOS:GetPlayerKey(Compat.PlayerName(), GetRealmName())
UnitLevel = function() return 60 end
UnitRace = function() return "Orc", "Orc" end
UnitSex = function() return 2 end
UnitStat = function() return 10 end
UnitHealthMax = function() return 1000 end
UnitPowerMax = function() return 500 end
GuildOS.Compat.IsSecret = GuildOS.Compat.IsSecret or function() return false end
DC.CollectProfessions = function() return {} end
DC.CollectResistances = function() return nil end
SpecChecker.CollectOwnSpec = function() return nil, "no-points" end
local data = DC:CollectMyData()
check(json(data.talents) == "[[135489,3]]", "the collect keeps the talents on my row: " .. json(data.talents))
configID = nil
data = DC:CollectMyData()
check(json(data.talents) == "[[135489,3]]", "a tree not loaded yet does not blank the talents read before")
check(json(DC:GetBroadcastData().talents) == "[[135489,3]]", "the broadcast carries the talents")
configID = 7

-- The suffix, from the link: the field after the four gems, sign kept, nil without one.
local enchant, gems, suffix = DC:ParseItemLink(LINKS[1])
check(enchant == 1503 and #gems == 0 and suffix == nil, "a link whose suffix field is 0 has no suffix")
enchant, _, suffix = DC:ParseItemLink(LINKS[15])
check(enchant == 2621 and suffix == 590, "a link with empty fields still gives its suffix: " .. tostring(suffix))
_, _, suffix = DC:ParseItemLink(LINKS[16])
check(suffix == -22, "a negative suffix id keeps its sign: " .. tostring(suffix))
_, _, suffix = DC:ParseItemLink(LINKS[17])
check(suffix == nil, "a link with no suffix field has no suffix")
_, gems, suffix = DC:ParseItemLink(nil)
check(#gems == 0 and suffix == nil, "no link: nothing")
local gear = DC:CollectGear()
check(gear[15].suffix == 590 and gear[16].suffix == -22 and gear[1].suffix == nil, "the collected gear carries each slot's suffix")
GuildOS.db.myData = { name = "Chehul", class = "WARRIOR", gear = gear }
local sent = DC:GetBroadcastData()
check(sent.gear[15].suffix == 590 and sent.gear[1].suffix == nil, "the broadcast gear carries the suffix, absent without one")
check(sent.talents == nil, "no talents read: none in the broadcast")

-- A guildmate's broadcast lands on their row: talents and suffix, merged like every field.
GuildOS.RefreshRosterUI = function() end
local ok = DC:StoreReceivedData("Fulano-Classic Beta PvE 2",
  { name = "Fulano", class = "PRIEST", lastUpdate = 1, talents = { { 135001, 5 } }, gear = { [15] = { id = 10148, suffix = 590 } } })
local row = GuildOS.db.members["Fulano-Classic Beta PvE 2"]
check(ok and json(row.talents) == "[[135001,5]]" and row.gear[15].suffix == 590, "a received record keeps talents and suffix")

-- Inspect: the talents come along when the client lets the trait API read the inspected tree.
check(SpecChecker:InspectedTalents() == nil, "no inspect config on the client: no inspected talents")
Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
inspectConfig = -1
check(json(SpecChecker:InspectedTalents()) == "[[135489,3]]", "the inspect config reads the inspected tree")
local rec = { lastUpdate = 1 }
SpecChecker:KeepInspectedTalents(rec, { { 1, 1 } })
check(json(rec.talents) == "[[1,1]]", "an inspect is newer than an old broadcast: kept")
rec = { lastUpdate = time(), talents = { { 2, 2 } } }
SpecChecker:KeepInspectedTalents(rec, { { 1, 1 } })
check(json(rec.talents) == "[[2,2]]", "the member's own reading as new as the inspect wins")
Constants, inspectConfig = nil, nil

-- ── TBC Anniversary and retail: no talents by id ─────────────────────────
for _, game in ipairs({ "anniversary", "retail" }) do
  load(game)
  configID = 7
  nodes = { [101] = { 501, 3 } }
  defs = { [501] = 135489 }
  useTraits()
  Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
  local t, w = GuildOS.SpecChecker:CollectOwnTalents()
  check(t == nil and w == "no-api", game .. ": the talents are not collected")
  check(GuildOS.SpecChecker:InspectedTalents() == nil, game .. ": nor read from an inspect")
  local _, _, s = GuildOS.DataCollector:ParseItemLink(LINKS[15])
  check(s == 590, game .. ": the suffix is read from the link all the same")
  Constants = nil
end

print(("companion-talents: %d checks passed"):format(checks))
