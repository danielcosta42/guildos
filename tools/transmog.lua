-- The transmog a slot shows (issue #201), run against the real Core/Compat.lua, Core/Data.lua,
-- Core/Utils.lua and Modules/DataCollector.lua under a stubbed WoW: Forever client and a stubbed
-- TBC Anniversary one.
--
-- guildos.me drew a character in the items it wears, so a transmogged one was drawn in someone
-- else's clothes. The game answers per slot with C_Transmog.GetSlotVisualInfo, taking the plain
-- table TransmogLocationMixin:GetData builds; the addon keeps the applied source id, or true for a
-- slot the transmog hides, and nothing when the slot shows its own item. Unread on Forever until
-- its launch on 4 November, so every answer it cannot use is no transmog, never an error.
--
--   luajit -e 'ADDON="."' tools/transmog.lua
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

local LINK = "|cffa335ee|Hitem:212345::::::::60::::::|h[Helm]|h|r"
-- What the game answers per slot: 1 transmogged, 3 its own item said as itself, 5 no transmog (0),
-- 15 hidden, 7 an error.
local VISUAL = {
  [1] = { baseSourceID = 6000, appliedSourceID = 7000, isHideVisual = false },
  [3] = { baseSourceID = 6100, appliedSourceID = 6100, isHideVisual = false },
  [5] = { baseSourceID = 6200, appliedSourceID = 0, isHideVisual = false },
  [15] = { baseSourceID = 6300, appliedSourceID = 77345, isHideVisual = true },
}
local asked = {}
local function load(anniversary)
  if anniversary then
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_ID = 5
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  function GetServerTime() return 1791000000 end
  function GetRealmName() return "Realm" end
  function UnitName() return "Chehul" end
  strsplit = function(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return unpack(out)
  end
  tinsert = table.insert
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  C_Item = { GetItemInfo = function() return "Helm", LINK, 4, 60 end }
  function GetInventoryItemLink(_, slot) return VISUAL[slot] and LINK or (slot == 7 and LINK) or nil end
  Enum = { TransmogType = { Appearance = 0, Illusion = 1 }, TransmogModification = { Main = 0, Secondary = 1 } }
  asked = {}
  C_Transmog = {
    GetSlotVisualInfo = function(location)
      asked[#asked + 1] = location
      if location.slotID == 7 then error("bad location") end
      return VISUAL[location.slotID]
    end,
  }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test",
              SelfTest = { Register = function() end } }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/DataCollector.lua")
end

-- ── WoW: Forever ─────────────────────────────────────────────────────
load(false)
local T = GuildOS.Compat.Transmog
check(T(1) == 7000, "a transmogged slot answers the applied source id")
local loc = asked[#asked]
check(loc.slotID == 1 and loc.type == 0 and loc.modification == 0,
  "the location is TransmogLocationMixin:GetData's table: slotID, appearance, main")
check(T(3) == nil, "a slot that shows its own item is no transmog")
check(T(5) == nil, "0, the game's NoTransmogID, is no transmog")
check(T(15) == true, "a slot the transmog hides says so")
check(T(7) == nil, "an error from the game is no transmog, never an error here")
local before = #asked
check(T(2) == nil and T(11) == nil and T(13) == nil and #asked == before,
  "neck, rings and trinkets are never asked")
C_Transmog = nil
check(T(1) == nil, "a client without C_Transmog has no transmog")

C_Transmog = { GetSlotVisualInfo = function(l) return VISUAL[l.slotID] end }
local gear = GuildOS.DataCollector:CollectGear()
check(gear[1].transmog == 7000 and gear[15].transmog == true and gear[5].transmog == nil and gear[7].transmog == nil,
  "collected gear carries what each slot shows")

-- The sync to the rest of the guild keeps it: the receiver stores what it is sent.
GuildOS.db = { myData = { name = "Chehul", gear = gear }, profile = {} }
local sent = GuildOS.DataCollector:GetBroadcastData()
check(sent and sent.gear and sent.gear[1].transmog == 7000 and sent.gear[15].transmog == true
  and sent.gear[5].transmog == nil, "the broadcast carries the transmog")

-- ── TBC Anniversary ──────────────────────────────────────────────────
load(true)
check(GuildOS.Client.isAnniversary, "the stub is Anniversary")
check(GuildOS.Compat.Transmog(1) == nil and #asked == 0, "Anniversary has no transmog and is never asked")

print(("transmog: %d checks passed"):format(checks))
