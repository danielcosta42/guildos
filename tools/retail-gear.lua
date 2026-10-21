-- Gear on retail (issue #166), run against the real Core/Compat.lua, Core/Data.lua, Core/Utils.lua,
-- Modules/DataCollector.lua and Modules/GearAudit.lua under a stubbed retail client and a stubbed
-- WoW: Forever one.
--
-- On retail an item's level is not the one GetItemInfo gives: upgrades, crafting and the track an
-- item dropped from all move it, and C_Item.GetDetailedItemLevelInfo answers the real one. The
-- character's average is the game's own. A link can carry four gems. Midnight enchants the head,
-- shoulder, chest, legs, feet, both rings and both weapons, never a shield or an off-hand frill
-- (cloak and wrist enchants are gone; issue #177), and an item
-- level's colour band would be stale every season, so it is neutral there. Forever keeps its rules.
--
--   luajit -e 'ADDON="."' tools/retail-gear.lua
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

local LINK = "|cffa335ee|Hitem:212345:7364:213743:213746:213743:213749:::80::::::|h[Helm]|h|r"
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
  function GetServerTime() return 1791000000 end
  function GetRealmName() return "Azralon" end
  strsplit = function(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return unpack(out)
  end
  tinsert = table.insert
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  -- The base level is 200; the item as worn is 665. The character's average is the game's 668.
  C_Item = {
    GetItemInfo = function() return "Helm", LINK, 4, 200 end,
    -- 1001 is a fist weapon, 1002 a shield: classID 2 and 4.
    GetItemInfoInstant = function(id) return id, "", "", "", 0, id == 1001 and 2 or 4, 0 end,
    GetDetailedItemLevelInfo = function() return 665, false, 200 end,
  }
  function GetAverageItemLevel() return 670.4, 668.6, 669 end
  function GetInventoryItemLink(_, slot) return slot == 1 and LINK or nil end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test",
              SelfTest = { Register = function() end } }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/DataCollector.lua")
  dofile(ADDON .. "/Modules/GearAudit.lua")
end

-- ── Retail ──────────────────────────────────────────────────────────
load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
check(GuildOS.Compat.ItemLevel(LINK, 200) == 665, "an item's level is the one it is worn at")
check(GuildOS.Compat.AverageItemLevel() == 668, "the average is the game's, equipped")
local gear = GuildOS.DataCollector:CollectGear()
check(gear[1] and gear[1].ilvl == 665, "collected gear carries the worn level")
local enchant, gems = GuildOS.DataCollector:ParseItemLink(LINK)
check(enchant == 7364 and #gems == 4, "a link's enchant and its four gems")
check(table.concat(GuildOS.GearAudit:GetEnchantableSlots(), ",") == "1,3,5,7,8,11,12,16,17", "Midnight's enchant slots")
local GA = GuildOS.GearAudit
local function item(id) return { id = id, name = "Item " .. id } end
local missing = table.concat(GA:MissingEnchants({ [7] = item(7), [16] = item(1001), [17] = item(1001) }), ",")
check(missing == GuildOS.SlotNames[7] .. "," .. GuildOS.SlotNames[16] .. "," .. GuildOS.SlotNames[17],
  "unenchanted legs and both weapons of a dual wielder are flagged: " .. missing)
check(not GA:NeedsEnchant(17, item(1002)) and #GA:MissingEnchants({ [17] = item(1002) }) == 0,
  "a shield in the off hand is never flagged")
check(GA:NeedsEnchant(17, item(1001)) and not GA:NeedsEnchant(15, item(1001)) and not GA:NeedsEnchant(7, nil),
  "a weapon off hand needs one; a cloak and an empty slot do not")
local enchanted = item(1001); enchanted.enchantId = 7981
check(#GA:MissingEnchants({ [17] = enchanted }) == 0, "an enchanted off-hand weapon is not flagged")
local memberDetail = io.open(ADDON .. "/UI/MemberDetail.lua", "rb"):read("*a")
check(memberDetail:find("GearAudit:NeedsEnchant(slotId, item)", 1, true) ~= nil, "the member sheet warns by the same rule")
local shown = GuildOS:FormatItemLevel(665)
check(shown:find("665", 1, true) and shown:find("|cffffffff", 1, true), "an item level is shown with no colour band")

-- ── WoW: Forever keeps its rules ────────────────────────────────────
load(false)
check(not GuildOS.Client.isRetail, "the stub is Forever")
check(GuildOS.Compat.ItemLevel(LINK, 200) == 200, "Forever keeps the base level")
check(GuildOS.Compat.AverageItemLevel() == nil, "Forever averages its own slots")
check(table.concat(GuildOS.GearAudit:GetEnchantableSlots(), ",") == "1,3,5,7,8,9,10,15,16", "Forever keeps its enchant slots")
check(GuildOS:FormatItemLevel(141):find("|cffff7f00", 1, true) ~= nil, "Forever keeps its colour bands")

print(("retail-gear: %d checks passed"):format(checks))
