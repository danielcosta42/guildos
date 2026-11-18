-- The night of a raid from the site (this repo's #385): while it lasts, the loot reads that raid's soft
-- reserves, priorities and wishlists from db.siteLoot; outside it, and for anybody the site has no list
-- of, it reads the game's own tables, which a night never writes. Run against the real Core, Compat,
-- Utils, Data, CoreManager, RaidTracker, Points, LootRule, LootMaster, WishlistSystem, SoftResSystem,
-- CompanionImport and SiteLoot, under a stubbed client with a fake clock.
--
--   * the window is LootRule's own (two hours before the start, eight after);
--   * inside it a roll's candidates carry the site's reserve (hard), prio place and wishlist place, and
--     the guild's wishlist still counts for whoever the site has none of, nobody listed twice;
--   * outside it, before and after, everything is the game's;
--   * a hidden sheet is not said in chat and not in another player's tooltip, and the roll still sees it;
--   * the game's four tables are the same after a night as before;
--   * ListsFromSite / PriosFromSite ignore the window and want an `at` of the last three days.
--
--   luajit -e 'ADDON="."' tools/site-night.lua
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

-- ── A client: frames that take any call, a raid, a clock ────────────
local function widget(fields)
  local w = fields or {}
  w.scripts = {}
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    if k == "SetText" then return function(self, t) self.text = t end end
    if k == "GetText" then return function(self) return self.text or "" end end
    if k == "GetWidth" or k == "GetHeight" then return function() return 80 end end
    if k == "Hide" then return function(self) self.hidden = true end end
    if k == "Show" then return function(self) self.hidden = false end end
    if k == "IsShown" then return function(self) return not self.hidden end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return widget() end end
    if k == "GetChildren" or k == "GetRegions" then return function() return end end
    if type(k) == "string" and k:find("^%u") then return function() end end
    return nil
  end })
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
format, strlower, tinsert = string.format, string.lower, table.insert
function CreateFrame(kind) return widget({ kind = kind }) end
UIParent, GameTooltip, UISpecialFrames = widget(), widget(), {}
ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 = widget(), widget(), widget()
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
function IsInRaid() return true end
function IsInGroup() return true end
function SendChatMessage() end
function GetLootMethod() return "master", 0 end
local raid = { "Lead", "Ana", "Bo", "Cy", "Dee" }
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end
function InCombatLockdown() return false end
function GetNumGroupMembers() return #raid end
function UnitClass() return "Mage", "MAGE" end
function UnitName(unit)
  if unit == "player" then return "Lead" end
  local i = tonumber(tostring(unit):match("^raid(%d+)$"))
  return i and raid[i] or nil
end
function UnitExists(unit) return UnitName(unit) ~= nil end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs, SlashCmdList = {}, {}
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Modules/CoreManager.lua")
dofile(ADDON .. "/Modules/RaidTracker.lua")
dofile(ADDON .. "/Modules/Points.lua")
dofile(ADDON .. "/Modules/WishlistSystem.lua")
dofile(ADDON .. "/Modules/SoftResSystem.lua")
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/SiteLoot.lua")

-- The game's tables, built once and copied so a night can be shown not to have touched them.
local ITEM, OTHER = 28770, 28771
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
local function gameTables()
  return {
    softRes = { items = { [ITEM] = { { name = "Bo", class = "MAGE", note = "", plusOnes = 0 } } },
      meta = {}, distributed = {} },
    lootPrios = { [ITEM] = { { name = "Cy", class = "MAGE", order = 1 }, { name = "Ana", class = "MAGE", order = 2 } } },
    wishlists = { ["Lead-Realm"] = { { itemId = ITEM, order = 1 } } },
    guildWishlists = {
      ana = { name = "Ana", class = "MAGE", wishlist = { { itemId = ITEM, order = 3 } } },
      dee = { name = "Dee", class = "MAGE", wishlist = { { itemId = ITEM, order = 2 }, { itemId = OTHER, order = 1 } } },
    },
  }
end
GuildOS.db = { settings = { lootSystem = "rolls" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { awardHistory = {} }, points = {},
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
for k, v in pairs(gameTables()) do GuildOS.db[k] = v end
local BEFORE = copyOf(gameTables())

local LM, SR, WL, SL = GuildOS.LootMaster, GuildOS.SoftRes, GuildOS.Wishlist, GuildOS.SiteLoot
check(SL and SR and WL, "the modules are there")
GuildOS.IsOfficer = function() return true end
GuildOS.IsOfficerByName = function() return true end
function GuildOS:ApplyFont() end
GuildOS.Points:Initialize()
WL:RebuildItemIndex()

local said, printed = {}, {}
LM.SafeSendAddon = function() end
LM.SendEcho = function() end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.IsMasterLooter = function() return true end
LM.GetPlayerContext = function() return { att25 = 100, recvThisLockout = 0 } end
LM.ShowRollFrame = function() end
LM.StopListeningForRolls = function() end
function GuildOS:Print(msg) printed[#printed + 1] = msg end
function GuildOS:UpdateLootSystemUI() end
function GuildOS:ShowsItemTooltipInfo() return true end
local LINK = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r"
local function K(name) return GuildOS:GetPlayerKey(name) end

-- What the site holds for the night, in the addon's own shapes.
local function siteNight(over)
  local s = {
    raidId = "r1", startsAt = NOW, at = NOW,
    softres = { items = { [ITEM] = { { name = "Ana", class = "MAGE", note = "", plusOnes = 0, hard = true } } } },
    prios = { [ITEM] = { { name = "Bo", class = "MAGE", order = 1 }, { name = "Ana", class = "MAGE", order = 2 } } },
    wishlists = {
      ana = { name = "Ana", class = "MAGE", wishlist = { { itemId = ITEM, order = 1, isOffspec = false } } },
      bo = { name = "Bo", class = "MAGE", wishlist = { { itemId = ITEM, order = 4, isOffspec = true } } },
    },
  }
  for k, v in pairs(over or {}) do s[k] = v end
  GuildOS.db.siteLoot = s
  return s
end
local function names(list)
  local out = {}
  for _, e in ipairs(list or {}) do out[#out + 1] = e.name end
  table.sort(out)
  return table.concat(out, ",")
end

-- A roll of the item by the raid; the candidates the master looter's table would hold.
local function roll()
  said, printed = {}, {}
  LM.activeLoot, LM.rolls = nil, {}
  LM.lootWindowOpen = false
  LM:AnnounceItem(LINK, nil)
  for _, n in ipairs({ "Ana", "Bo", "Cy", "Dee" }) do LM:RegisterRoll(n, "MS", 10) end
  local c = LM.rolls
  return function(n) return c[K(n)] end
end

-- ── 1. Inside the window ────────────────────────────────────────────
siteNight()
check(SL:Active(NOW) and SL:Active(NOW - 2 * 3600) and SL:Active(NOW + 8 * 3600), "active from two hours before to eight after")
check(not SL:Active(NOW - 2 * 3600 - 1) and not SL:Active(NOW + 8 * 3600 + 1), "and not a second outside")
check(SL:Active() , "the default clock is time()")
check(SL:Reserves() and SL:Prios() and SL:WishlistOf("ana") and not SL:WishlistOf("cy"), "the three readers answer in the night")
check(names(SR:GetReserves(ITEM)) == "Ana", "reserves: the site's, not the game's Bo")
check(names(SR:GetInRaidReserves(ITEM)) == "Ana", "and the ones in the raid")

local c = roll()
check(c("Ana").softRes and c("Ana").softRes.hard == true, "a roll: Ana's reserve is the site's, a hard one")
check(c("Bo").softRes == nil, "and Bo's game reserve is not counted")
check(c("Bo").prioOrder == 1 and c("Ana").prioOrder == 2 and c("Cy").prioOrder == nil,
  "prio places are the site's, Cy's game prio is not counted")
check(c("Ana").wishlist and c("Ana").wishlist.order == 1, "Ana's wishlist place is the site's (1, the game said 3)")
check(c("Bo").wishlist and c("Bo").wishlist.order == 4, "Bo's too")
check(c("Dee").wishlist and c("Dee").wishlist.order == 2, "Dee has no site list: the game's order, 2, still counts")
check(c("Cy").wishlist == nil, "Cy has none anywhere")
local rows = LM:ResolvePrioList(ITEM)
check(rows and #rows == 2 and rows[1].name == "Bo" and rows[2].name == "Ana", "ResolvePrioList reads the site's")
local council = LM:ResolveWishlistCouncil(ITEM)
local seen = {}
for _, e in ipairs(council or {}) do seen[e.name] = (seen[e.name] or 0) + 1 end
check(seen.Ana == 1 and seen.Bo == 1 and seen.Dee == 1 and not seen.Cy, "the wishlist council: one row each, the site's and the game's")

local interest = WL:GetItemInterest(ITEM)
check(#interest == 3 and names(interest) == "Ana,Bo,Dee", "GetItemInterest merges without duplicates: " .. names(interest))
local byName = {}
for _, e in ipairs(interest) do byName[e.name] = e end
check(byName.Ana.order == 1 and byName.Ana.type == "wishlist" and byName.Bo.isOffspec == true and byName.Dee.order == 2,
  "with the site's entries for its people and the game's for the rest")
check(interest[1].name == "Ana" and interest[2].name == "Dee" and interest[3].name == "Bo", "in order")
check(WL:GetItemInterest(OTHER) and #WL:GetItemInterest(OTHER) == 1 and WL:GetItemInterest(OTHER)[1].name == "Dee",
  "an item the site says nothing of is the game's")
local rowsFor, top = LM:InterestFor(ITEM)
check(#rowsFor == 3 and top and top.name == "Ana", "InterestFor goes through the merge")
local mine = LM:Standing(ITEM)
check(not mine.reserved and not mine.prio and not mine.wishlist, "Standing: for Lead, none of it")
local saved = GuildOS.Compat.PlayerName
GuildOS.Compat.PlayerName = function() return "Ana" end
mine = LM:Standing(ITEM)
check(mine.reserved and mine.hard and mine.prio == 2 and mine.wishlist == 1, "Standing: Ana's places are the site's")
GuildOS.Compat.PlayerName = saved
-- The persistent index is the game's: a night never rebuilds it from the site.
local indexed = {}
for _, e in ipairs(WL.itemIndex[ITEM]) do indexed[#indexed + 1] = e.name .. e.order end
table.sort(indexed)
check(table.concat(indexed, ",") == "Ana3,Dee2", "the item index still holds the game's lists only")

-- ── 2. Outside the window the game's ────────────────────────────────
for _, when in ipairs({ NOW - 3 * 3600, NOW + 9 * 3600 }) do
  clock = when
  check(not SL:Active() and SL:Reserves() == nil and SL:Prios() == nil and SL:WishlistOf("ana") == nil, "outside: nothing from the site")
  c = roll()
  check(c("Bo").softRes and not c("Bo").softRes.hard and c("Ana").softRes == nil, "outside: the game's reserve")
  check(c("Cy").prioOrder == 1 and c("Ana").prioOrder == 2 and c("Bo").prioOrder == nil, "outside: the game's prios")
  check(c("Ana").wishlist.order == 3 and c("Dee").wishlist.order == 2 and c("Bo").wishlist == nil, "outside: the game's wishlists")
  check(names(WL:GetItemInterest(ITEM)) == "Ana,Dee" and WL:GetItemInterest(ITEM) == WL.itemIndex[ITEM],
    "outside: the index itself, as before")
end
clock = NOW

-- ── 3. A hidden sheet ────────────────────────────────────────────────
siteNight()
GuildOS.db.siteLoot.softres.hidden = true
said, printed = {}, {}
LM:AnnounceSoftReserves(ITEM)
check(#said == 0, "hidden: nothing said in chat")
check(#printed == 1, "hidden: the master looter is told, locally, that it was not")
GuildOS.db.siteLoot.softres.hidden = nil
said, printed = {}, {}
LM:AnnounceSoftReserves(ITEM)
check(#said == 1 and said[1]:find("Ana", 1, true) and #printed == 0, "not hidden: announced as ever")
GuildOS.db.siteLoot.softres.hidden = true

local function tooltipLines()
  local lines, hooks = {}, {}
  local old = GuildOS.Compat.HookTooltip
  GuildOS.Compat.HookTooltip = function(tt, _, fn) if tt == GameTooltip then hooks[#hooks + 1] = fn end end
  local oldItem = GuildOS.Compat.TooltipItem
  GuildOS.Compat.TooltipItem = function() return nil, LINK end
  SR:HookTooltips()
  local tt = { AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() end }
  for _, fn in ipairs(hooks) do fn(tt) end
  GuildOS.Compat.HookTooltip, GuildOS.Compat.TooltipItem = old, oldItem
  return table.concat(lines, "\n")
end
check(not tooltipLines():find("Ana", 1, true), "hidden: Ana's reserve is not in the tooltip of Lead")
GuildOS.Compat.PlayerName = function() return "Ana" end
check(tooltipLines():find("Ana", 1, true), "hidden: but a player's own reserve still shows")
GuildOS.Compat.PlayerName = saved
c = roll()
check(c("Ana").softRes and c("Ana").softRes.hard, "hidden: the roll still sees the reserve")
check(names(SR:GetInRaidReserves(ITEM)) == "Ana", "hidden: and the loot master's window")
GuildOS.db.siteLoot.softres.hidden = nil
check(tooltipLines():find("Ana", 1, true), "visible: the tooltip lists it")

-- ── 4. The game's tables after the nights ───────────────────────────
for _, k in ipairs({ "softRes", "lootPrios", "wishlists", "guildWishlists" }) do
  check(same(GuildOS.db[k], BEFORE[k]), k .. " is what it was before any night")
end

-- ── 5. Where the lists come from, whatever the hour ─────────────────
siteNight()
check(SL:ListsFromSite("ana") == true and SL:ListsFromSite("cy") == false, "lists: the site holds Ana's, not Cy's")
check(SL:PriosFromSite() == true, "prios: the site holds them")
clock = NOW + 30 * 3600
check(not SL:Active() and SL:ListsFromSite("ana") and SL:PriosFromSite(), "and the night being over does not change it")
clock = NOW + 3 * 86400
check(SL:ListsFromSite("ana") and SL:PriosFromSite(), "three days after is still the site's")
clock = NOW + 3 * 86400 + 1
check(SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false, "older than three days: the game's again")
clock = NOW
GuildOS.db.siteLoot.at = nil
check(SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false, "no stamp, no claim")
GuildOS.db.siteLoot = nil
check(not SL:Active() and SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false
  and SL:Reserves() == nil and SL:Prios() == nil and SL:WishlistOf("ana") == nil, "no siteLoot: nothing")
c = roll()
check(c("Bo").softRes and c("Cy").prioOrder == 1 and c("Ana").wishlist.order == 3, "and the roll is the game's")
siteNight({ prios = false })
check(SL:PriosFromSite() == false and SL:Prios() == nil, "a night with no prios holds none")

-- ConsumeInbox stamps `at` with the clock of the read.
do
  local LD = LibStub("LibDeflate")
  local function wire(json) return "GOSROST1:" .. LD:EncodeForPrint(LD:CompressDeflate(json)) end
  _G.GuildOSInbox = { wire('{"fmt":"GOSROST1","v":6,"raidId":"rx","title":"T","startsAt":' .. NOW
    .. ',"instanceKey":"karazhan","members":[{"key":"Ana","name":"Ana","class":"MAGE"}],'
    .. '"wishlists":[{"key":"Ana-Realm","name":"Ana","class":"MAGE","items":[{"id":28770,"o":1}]}]}') }
  _G.GuildOSInboxAck, GuildOS.CompanionImport._lastInbox, GuildOS.db.settings.companion = nil, nil, true
  GuildOS.db.siteLoot = nil
  function GuildOS:GetSetting(k) return self.db.settings[k] end
  check(GuildOS.CompanionImport:ConsumeInbox(), "the inbox is read")
  check(GuildOS.db.siteLoot and GuildOS.db.siteLoot.at == clock, "and stamped with the time of the read")
  check(SL:ListsFromSite("ana"), "so the list is the site's")
end
-- A body over the cap is refused before anything is copied.
do
  local big = "GOSROST1:" .. string.rep("A", 524289)
  local r, err = GuildOS.CompanionImport:Parse(big)
  check(r == nil and err, "an oversized body is refused")
end
for _, k in ipairs({ "softRes", "lootPrios", "wishlists", "guildWishlists" }) do
  check(same(GuildOS.db[k], BEFORE[k]), k .. " is still what it was after the inbox too")
end

print("site-night: " .. checks .. " checks passed")
