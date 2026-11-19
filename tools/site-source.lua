-- Who is the source of a list (this repo's #385): when the site holds the player's wishlist, or the
-- guild's priorities, the game shows them read-only and neither sends nor applies the addon-to-addon
-- broadcasts for that data. A guild the site sends nothing to behaves as it always did. Run against the
-- real Core, Compat, Utils, Data, WishlistSystem, SiteLoot and UI/FeaturePanels (the wishlist editor and
-- the prio modal), on a recording UI.
--
--   * my list is the site's: the editor's add / order / remove / sync controls are hidden and the panel
--     says so with an "Edit on the site" button that opens the copyable address https://guildos.me/wishlist;
--     the three mutators refuse (and the table stays as it was); my WL is not sent;
--   * the priorities are the site's: the modal has no save, no search and no row controls, its button
--     opens https://guildos.me; LP is not sent and an incoming one is not applied;
--   * the site's data stale (older than three days), absent, or somebody else's: nothing changes.
--
--   luajit -e 'ADDON="."' tools/site-source.lua
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

-- ── A client: a recording UI, a clock, a comm channel ──────────────
local stub
stub = setmetatable({}, {
  __index = function(_, k)
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetFrameLevel" or k == "GetStringHeight" or k == "GetStringWidth" then
      return function() return 40 end
    end
    return stub
  end,
  __call = function() return stub end,
})
local rec = {}
local function widget(fields)
  local w = fields or {}
  w.scripts = {}
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" or k == "HookScript" then return function(self, name, fn) self.scripts[name] = fn end end
    if k == "SetText" then return function(self, t) self.text = t end end
    if k == "GetText" then return function(self) return self.text or "" end end
    if k == "Hide" then return function(self) self.hidden = true end end
    if k == "Show" then return function(self) self.hidden = false end end
    if k == "IsShown" then return function(self) return not self.hidden end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return widget() end end
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetFrameLevel" or k == "GetStringHeight" or k == "GetStringWidth" then
      return function() return 40 end
    end
    if type(k) == "string" and k:find("^%u") then return function() return stub end end
    return nil
  end })
end
local function reset() rec = { buttons = {} } end
reset()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
format, strlower, tinsert = string.format, string.lower, table.insert
function CreateFrame(kind) return widget({ kind = kind }) end
UIParent, GameTooltip, UISpecialFrames = widget(), widget(), {}
ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 = widget(), widget(), widget()
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll() end
RAID_CLASS_COLORS = {}
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetInstanceInfo() return "Karazhan", "raid", 9, "", 10, 0, false, 532 end
function GetRealmName() return "Realm" end
local NOW = 1791000000
local clock = NOW
function GetServerTime() return clock end
function time() return clock end
function GetTime() return 100 end
date = os.date
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInRaid() return false end
function IsInGroup() return false end
function UnitClass() return "Mage", "MAGE" end
function UnitName() return "Lead" end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs, SlashCmdList = {}, {}
-- The comm layer's serializer, as the identity: what is sent is what the other side reads.
local registry = {
  ["GuildOS-LibSerialize"] = {
    Serialize = function(_, v) return v end,
    Deserialize = function(_, v) return true, v end,
  },
}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/RaidTracker.lua")
dofile(ADDON .. "/Modules/WishlistSystem.lua")
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/SiteLoot.lua")
GuildOS.UI = setmetatable({
  GetFeature = function() return nil end,
  CreateButton = function(_, _, t) local b = widget({ label = tostring(t) }); rec.buttons[#rec.buttons + 1] = b; return b end,
  CreateInput = function() return widget({}) end,
  CreateText = function(_, _, t) return widget({ text = tostring(t) }) end,
}, { __index = function() return function() return stub end end })
dofile(ADDON .. "/UI/FeaturePanels.lua")
function GuildOS:ApplyFont() end
GuildOS.IsOfficer = function() return true end

local WL, SL = GuildOS.Wishlist, GuildOS.SiteLoot
local ITEM, OTHER = 28770, 28771
local MYKEY = GuildOS:GetPlayerKey("Lead")
local LINK = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r"
function WL:ItemFacts(id) return "Item " .. id, "|Hitem:" .. id .. "|h", 4 end
local function copyOf(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copyOf(x) end
  return out
end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local sent, printed, popups = {}, {}, {}
GuildOS.CommSystem = { SendMessage = function(_, kind) sent[#sent + 1] = kind end }
function GuildOS:Print(m) printed[#printed + 1] = m end
function GuildOS:ShowExportPopup(title, text) popups[#popups + 1] = { title = title, text = text } end
local function clear() sent, printed, popups = {}, {}, {} end

local function gameTables()
  return {
    wishlists = { [MYKEY] = { { itemId = ITEM, itemLink = LINK, order = 1, isOffspec = false },
                              { itemId = OTHER, itemLink = "", order = 2, isOffspec = true } } },
    guildWishlists = { lead = { name = "Lead", class = "MAGE", wishlist = { { itemId = ITEM, order = 1 } } } },
    lootPrios = { [ITEM] = { { name = "Cy", class = "MAGE", order = 1 }, { name = "Ana", class = "MAGE", order = 2 } } },
  }
end
GuildOS.db = { settings = {}, members = {}, altLinks = {}, cores = {}, lootHistory = {}, lootMaster = { awardHistory = {} },
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local function resetGame()
  for k, v in pairs(gameTables()) do GuildOS.db[k] = v end
end
resetGame()

-- What the site sent: a raid carrying `lists` (keyed as guildWishlists is) and `prios`.
local function siteSent(lists, prios, at)
  GuildOS.db.siteLoot = { at = at or clock, raids = { r1 = { startsAt = NOW, instanceKey = "kara",
    wishlists = lists, prios = prios } } }
end
local MINE = { lead = { name = "Lead", class = "MAGE", wishlist = { { itemId = OTHER, order = 1, isOffspec = false } } } }
local THEIRS = { ana = { name = "Ana", class = "MAGE", wishlist = { { itemId = OTHER, order = 1, isOffspec = false } } } }
local SITE_PRIOS = { [ITEM] = { { name = "Bo", class = "MAGE", order = 1 } } }

-- The wishlist editor, as the panel leaves it after a refresh.
local function wishlistPanel()
  reset()
  GuildOS.WishlistFrame = nil
  GuildOS:ShowWishlistFrame()
  return GuildOS.WishlistFrame
end
local function hiddenAll(f, names)
  for _, n in ipairs(names) do
    if not (f[n] and f[n].hidden) then return false, n end
  end
  return true
end
local EDITOR = { "msBtn", "osBtn", "addBox", "addBtn", "syncBtn" }
local function rowControls(f)
  for i, row in ipairs(f.rows) do
    if not row.hidden then
      for _, n in ipairs({ "upBtn", "downBtn", "removeBtn" }) do
        if not row[n].hidden then return false, i .. "." .. n end
      end
    end
  end
  return true
end
local function rowControlsShown(f)
  local any = false
  for _, row in ipairs(f.rows) do
    if not row.hidden then
      any = true
      for _, n in ipairs({ "upBtn", "downBtn", "removeBtn" }) do
        if row[n].hidden then return false end
      end
    end
  end
  return any
end

-- ── 1. My wishlist is the site's ────────────────────────────────────
siteSent(MINE)
check(SL:ListsFromSite(WL.StoreKey(MYKEY, "Lead")), "the helper says my list is the site's")
local f = wishlistPanel()
local ok, which = hiddenAll(f, EDITOR)
check(ok, "the editor's controls are hidden: " .. tostring(which))
check(rowControls(f), "no row has order or remove controls")
check(f.siteLine and not f.siteLine.hidden and f.siteLine.text == "Your list comes from the site.", "the panel says the list comes from the site")
check(f.siteBtn and not f.siteBtn.hidden and f.siteBtn.label == "Edit on the site", "and offers Edit on the site")
clear()
f.siteBtn.scripts.OnClick()
check(#popups == 1 and popups[1].text == "https://guildos.me/wishlist", "the button shows exactly https://guildos.me/wishlist")
check(not popups[1].text:find("Lead", 1, true), "with no character in it")

local before = copyOf(GuildOS.db.wishlists)
local guildBefore = copyOf(GuildOS.db.guildWishlists)
clear()
check(WL:AddToWishlist(OTHER + 1, LINK, false) == false, "add refuses")
check(WL:RemoveFromWishlist(ITEM) == false, "remove refuses")
check(WL:ReorderWishlist(ITEM, 1) == false, "reorder refuses")
check(same(GuildOS.db.wishlists, before), "my wishlist is exactly as it was")
check(same(GuildOS.db.guildWishlists, guildBefore), "and so is the guild's copy of it")
check(#printed == 3 and printed[1] == printed[2], "each refusal is one local line")
check(#sent == 0, "a refusal sends nothing")
WL:BroadcastMyWishlist()
WL:BroadcastMyWishlist(true)
check(#sent == 0, "my WL is not sent, forced or not")
check(same(GuildOS.db.guildWishlists, guildBefore), "and not stored as a broadcast of mine either")

-- ── 2. The prios are the site's ─────────────────────────────────────
siteSent(THEIRS, SITE_PRIOS)
check(SL:PriosFromSite(), "the helper says the priorities are the site's")
reset()
GuildOS.PrioModal = nil
GuildOS:ShowPrioModal()
local m = GuildOS.PrioModal
check(m.saveBtn and m.saveBtn.hidden, "the modal has no Save and Sync")
check(m.searchBox.hidden and m.loadBtn.hidden, "no search to load an item to edit")
check(m.siteLine and not m.siteLine.hidden and m.siteLine.text == "The guild's priorities come from the site.", "the modal says so")
check(m.siteBtn and not m.siteBtn.hidden and m.siteBtn.label == "Edit on the site", "and offers Edit on the site")
clear()
m.siteBtn.scripts.OnClick()
check(#popups == 1 and popups[1].text == "https://guildos.me", "that button shows exactly https://guildos.me")
for _, row in ipairs(m.rows) do
  for _, n in ipairs({ "upBtn", "downBtn", "removeBtn" }) do check(row[n].hidden, "row " .. n .. " is hidden") end
end
-- Somebody else's list does not lock mine.
f = wishlistPanel()
check(not f.addBtn.hidden and not f.syncBtn.hidden, "a list of somebody else leaves my editor open (4)")
check(f.siteLine.hidden and f.siteBtn.hidden, "and says nothing about the site")

local gameBefore = copyOf(GuildOS.db.lootPrios)
clear()
WL:BroadcastLootPrios()
check(#sent == 0, "LP is not sent")
WL:HandleLootPriosBroadcast("Cy", { [ITEM] = { { name = "Zed", class = "MAGE", order = 1 } } })
check(same(GuildOS.db.lootPrios, gameBefore), "an incoming LP leaves db.lootPrios as it was")
check(#printed == 0, "and nothing is said of it")

-- ── 3. Nothing from the site: as before ─────────────────────────────
local function asBefore(label)
  f = wishlistPanel()
  local shown = true
  for _, n in ipairs(EDITOR) do if f[n].hidden then shown = false end end
  check(shown, label .. ": the editor's controls are there")
  check(f.siteLine.hidden and f.siteBtn.hidden, label .. ": no site line")
  check(rowControlsShown(f), label .. ": the rows keep their order and remove controls")
  clear()
  WL:AddToWishlist(OTHER + 1, LINK, false)
  check(#GuildOS.db.wishlists[MYKEY] == 3 and #sent == 1 and sent[1] == "WL", label .. ": add writes and sends WL")
  clear()
  WL:ReorderWishlist(OTHER + 1, -1)
  check(GuildOS.db.wishlists[MYKEY][2].itemId == OTHER + 1 and sent[1] == "WL", label .. ": reorder writes and sends")
  clear()
  WL:RemoveFromWishlist(OTHER + 1)
  check(#GuildOS.db.wishlists[MYKEY] == 2 and sent[1] == "WL", label .. ": remove writes and sends")
  clear()
  WL:BroadcastMyWishlist(true)
  check(sent[1] == "WL", label .. ": WL is sent")
  clear()
  WL:BroadcastLootPrios()
  check(sent[1] == "LP", label .. ": LP is sent")
  local payload = { [OTHER] = { { name = "Zed", class = "MAGE", order = 1 } } }
  WL:HandleLootPriosBroadcast("Cy", payload)
  check(GuildOS.db.lootPrios == payload, label .. ": an incoming LP applies")
  reset()
  GuildOS.PrioModal = nil
  GuildOS:ShowPrioModal()
  m = GuildOS.PrioModal
  check(not m.saveBtn.hidden and not m.searchBox.hidden and not m.loadBtn.hidden, label .. ": the modal is editable")
  check(m.siteLine.hidden and m.siteBtn.hidden, label .. ": and has no site line")
  resetGame()
end

GuildOS.db.siteLoot = nil
asBefore("no siteLoot")
siteSent(MINE, SITE_PRIOS, NOW - 3 * 86400 - 1)
check(not SL:ListsFromSite(WL.StoreKey(MYKEY, "Lead")) and not SL:PriosFromSite(), "four days is older than the site's word")
asBefore("stale")
siteSent(THEIRS, nil)
asBefore("somebody else's list and no prios")
siteSent(nil, nil)
asBefore("a raid with nothing")

-- ── 4. The save of the modal is guarded too ─────────────────────────
resetGame()
siteSent(nil, SITE_PRIOS)
reset()
GuildOS.PrioModal = nil
GuildOS:ShowPrioModal()
m = GuildOS.PrioModal
m.currentItemId, m.prioData = ITEM, { { name = "Zed", class = "MAGE" } }
clear()
m.saveBtn.scripts.OnClick()
check(same(GuildOS.db.lootPrios, gameTables().lootPrios) and #sent == 0, "even a click on a hidden Save writes and sends nothing")

-- The editors come back when the site's word runs out.
clock = NOW + 4 * 86400
f = wishlistPanel()
siteSent(MINE, SITE_PRIOS, NOW)
check(not SL:ListsFromSite(WL.StoreKey(MYKEY, "Lead")), "the clock moved on: the site is no longer the source")
f = wishlistPanel()
check(not f.addBtn.hidden and f.siteLine.hidden, "and the editor is back")

print(string.format("site-source: %d checks passed", checks))
