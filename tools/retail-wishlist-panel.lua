-- The officers' wishlist panel on retail (this repo's #385), run against the real Core, Compat, Data, Style,
-- Utils, WishlistSystem, LootMaster, SiteLoot and UI/RosterFrame.lua under a stubbed retail client.
--
-- Retail is personal loot only (ADR-0026): Modules/LootMaster.lua returns before it defines GuildOS.LootMaster.
-- The panel read the priorities through LootMaster:AllPrios() and threw on every repopulate there, for every
-- guild. This proves it fills on retail from the game's own db.lootPrios (a prio star on a guildmate who has
-- one), and that the same panel on TBC Anniversary still reads them through LootMaster.
--
--   luajit -e 'ADDON="."' tools/retail-wishlist-panel.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. tostring(what) .. "\n")
    os.exit(1)
  end
end

-- A frame that takes any call; it keeps its scripts, its text and its children so they can be read back.
local function widget(parent)
  local w = { scripts = {}, children = {}, shown = true }
  if parent and parent.children then parent.children[#parent.children + 1] = w end
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    if k == "HookScript" then
      return function(self, name, fn)
        local prev = self.scripts[name]
        self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
      end
    end
    if k == "GetScript" then return function(self, name) return self.scripts[name] end end
    if k == "SetText" then return function(self, t) self.text = t end end
    if k == "GetText" then return function(self) return self.text or "" end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "Show" then return function(self) self.shown = true end end
    if k == "IsShown" or k == "IsVisible" then return function(self) return self.shown end end
    if k == "CreateFontString" or k == "CreateTexture" then return function(self) return widget(self) end end
    if k == "GetChildren" or k == "GetRegions" then return function(self) return unpack(self.children) end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetStringWidth" or k == "GetStringHeight" then
      return function() return 40 end
    end
    if k == "GetFrameLevel" then return function() return 1 end end
    if type(k) == "string" and k:find("^%u") then return function() end end
    return nil
  end })
end

local function texts(f, out)
  out = out or {}
  if f.text then out[#out + 1] = tostring(f.text) end
  for _, c in ipairs(f.children or {}) do texts(c, out) end
  return out
end

local function load(retail)
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_ID = 5
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame(_, name, parent)
    local f = widget(parent)
    if name then _G[name] = f end
    return f
  end
  UIParent, GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 = widget(), widget(), widget(), widget(), widget()
  UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
  RAID_CLASS_COLORS, CLASS_ICON_TCOORDS = {}, {}
  function hooksecurefunc() end
  function debugstack() return "" end
  function issecretvalue() return false end
  function GetServerTime() return 1791000000 end
  time = function() return 1791000000 end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function wipe(t) for k in pairs(t) do t[k] = nil end return t end
  strlower, format, tinsert = string.lower, string.format, table.insert
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1, "Azralon" end
  function GetRealmName() return "Azralon" end
  function GetNormalizedRealmName() return "Azralon" end
  function GetNumGuildMembers() return 0 end
  function UnitName() return "Ana" end
  function UnitClass() return "Mage", "MAGE" end
  function IsInRaid() return false end
  function GetNumGroupMembers() return 0 end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  C_Item = { GetItemInfo = function() return nil end }
  Enum = { SendAddonMessageResult = {} }
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  GuildOS.SelfTest = { Register = function() end }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Style.lua")
  GuildOS.Style:Resolve()
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return true end
  function GuildOS:ApplyFont() end
  function GuildOS:Print() end
  GuildOS.UI = setmetatable({ GAP = 6 }, { __index = function() return function(_, parent) return widget(parent) end end })
  local key = retail and "Bo-Azralon" or "Bo"
  GuildOS.db = { settings = { modules = {} }, members = {}, lootHistory = {},
    guildWishlists = { [strlower(key)] = { name = key, class = "MAGE", wishlist = { { itemId = 250001, order = 1 } } } },
    lootPrios = { [250001] = { { name = key, class = "MAGE", order = 1 } } } }
  dofile(ADDON .. "/Modules/WishlistSystem.lua")
  dofile(ADDON .. "/Modules/LootRule.lua")
  dofile(ADDON .. "/Modules/LootMaster.lua")
  dofile(ADDON .. "/Modules/SiteLoot.lua")
  dofile(ADDON .. "/UI/Spacing.lua"); if GuildOS.UI then rawset(GuildOS.UI, "SP", GuildOS.Spacing) end   -- the spacing standard (#449)
  dofile(ADDON .. "/UI/RosterFrame.lua")
end

for _, retail in ipairs({ true, false }) do
  local game = retail and "retail" or "Anniversary"
  load(retail)
  check(GuildOS.Client.isRetail == retail, game .. ": the stub is " .. game)
  check((GuildOS.LootMaster == nil) == retail, game .. ": LootMaster is " .. (retail and "absent" or "there"))
  local parent = widget()
  GuildOS:CreateWishlistGuildPanel(parent, parent)
  local show = parent.scripts.OnShow
  check(show, game .. ": the panel fills itself when shown")
  local ok, err = pcall(show, parent)
  check(ok, game .. ": showing the officers' wishlist panel does not throw: " .. tostring(err))
  local all = table.concat(texts(parent), "\n")
  check(all:find(retail and "Bo-Azralon" or "Bo", 1, true), game .. ": the guildmate's list is listed")
  check(all:find("*", 1, true), game .. ": with the prio star from the game's own priorities")
  -- And again, as the search box and the item cache repopulate it.
  ok, err = pcall(show, parent)
  check(ok, game .. ": a repopulate does not throw either: " .. tostring(err))
end

print(("retail-wishlist-panel: %d checks passed"):format(checks))
