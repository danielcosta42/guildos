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
--   * ListsFromSite / PriosFromSite ignore whether the player is in the raid, and want the companion's own
--     stamp (GuildOSInboxAck.at) of the last three days, read live (R18), and a raid whose every place this
--     client can stamp (R20), in its night or still to come;
--   * a night of two places is the same raid's sheet in either (R19);
--   * hidden priorities (R21): no line of the raid's chat names a prio place, the loot master reads it locally.
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
local instance = 532   -- Karazhan; another number is another place
function GetInstanceInfo() return "Karazhan", "raid", 9, "", 10, 0, false, instance end
function GetRealmName() return "Realm" end
local NOW = 1791000000
local clock = NOW
function GetServerTime() return clock end
local skew = 0   -- this PC's clock against the realm's
function time() return clock + skew end
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

-- What the site holds for the night of raid r1, in the addon's own shapes, one entry per raid.
local function siteNight(over)
  local s = {
    startsAt = NOW, instanceKey = "kara",
    softres = { items = { [ITEM] = { { name = "Ana", class = "MAGE", note = "", plusOnes = 0, hard = true } } } },
    prios = { [ITEM] = { { name = "Bo", class = "MAGE", order = 1 }, { name = "Ana", class = "MAGE", order = 2 } } },
    wishlists = {
      ana = { name = "Ana", class = "MAGE", wishlist = { { itemId = ITEM, order = 1, isOffspec = false } } },
      bo = { name = "Bo", class = "MAGE", wishlist = { { itemId = ITEM, order = 4, isOffspec = true } } },
    },
  }
  for k, v in pairs(over or {}) do s[k] = v end
  GuildOS.db.siteLoot = { raids = { r1 = s } }
  -- Nothing in memory from an earlier read, and a companion that answered from the site just now.
  GuildOS.CompanionImport._siteRaids = nil
  _G.GuildOSInboxAck = { at = time(), members = 1 }
  return s
end
local function site() return GuildOS.db.siteLoot.raids.r1 end
local function officerView(on)   -- whether this client is an officer / the master looter
  GuildOS.IsOfficer = function() return on end
  LM.IsMasterLooter = function() return on end
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
check(SL:Active(), "the default clock is the realm's, GetServerTime()")
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
site().softres.hidden = true
said, printed = {}, {}
LM:AnnounceSoftReserves(ITEM)
check(#said == 0, "hidden: nothing said in chat")
check(#printed == 1, "hidden: the master looter is told, locally, that it was not")
site().softres.hidden = nil
said, printed = {}, {}
LM:AnnounceSoftReserves(ITEM)
check(#said == 1 and said[1]:find("Ana", 1, true) and #printed == 0, "not hidden: announced as ever")
site().softres.hidden = true

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
officerView(false)
check(not tooltipLines():find("Ana", 1, true), "hidden: Ana's reserve is not in the tooltip of a raider")
check(not SR:OthersVisible(), "hidden: the others' reserves are not a raider's to read")
GuildOS.Compat.PlayerName = function() return "Ana" end
check(tooltipLines():find("Ana", 1, true), "hidden: but a player's own reserve still shows")
GuildOS.Compat.PlayerName = saved
officerView(true)
check(SR:OthersVisible() and tooltipLines():find("Ana", 1, true), "hidden: the master looter and the officers read them")
c = roll()
check(c("Ana").softRes and c("Ana").softRes.hard, "hidden: the roll still sees the reserve")
check(names(SR:GetInRaidReserves(ITEM)) == "Ana", "hidden: and the loot master's window")
site().softres.hidden = nil
check(tooltipLines():find("Ana", 1, true), "visible: the tooltip lists it")

-- ── 4. The game's tables after the nights ───────────────────────────
for _, k in ipairs({ "softRes", "lootPrios", "wishlists", "guildWishlists" }) do
  check(same(GuildOS.db[k], BEFORE[k]), k .. " is what it was before any night")
end

-- ── 5. Where the lists come from, whatever the hour ─────────────────
siteNight()
check(SL:ListsFromSite("ana") == true and SL:ListsFromSite("cy") == false, "lists: the site holds Ana's, not Cy's")
check(SL:PriosFromSite() == true, "prios: the site holds them")
check(SL:ListInForce("ana").wishlist[1].order == 1 and SL:ListInForce("cy") == nil, "the list in force is the site's own")
-- Out of the instance, a night still to come: the source is the site's all the same.
instance = 565
check(not SL:Active() and SL:ListsFromSite("ana") and SL:PriosFromSite(), "being elsewhere does not change it")
instance = 532
clock = NOW - 30 * 3600
check(SL:ListsFromSite("ana") and SL:PriosFromSite(), "a day before the night is the site's too")
clock = NOW + 9 * 3600
check(SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false, "a night that is over speaks for nothing")
-- R18: the age is the companion's own stamp, read live, never the time the inbox was read.
siteNight({ startsAt = NOW + 5 * 86400 })
clock = NOW
check(SL:ListsFromSite("ana") and SL:PriosFromSite(), "a fresh stamp and a raid in five days: the site's")
_G.GuildOSInboxAck = { at = NOW - 3 * 86400 }
check(SL:ListsFromSite("ana") and SL:PriosFromSite(), "a stamp three days old is still the site's")
_G.GuildOSInboxAck = { at = NOW - 3 * 86400 - 1 }
check(SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false,
  "an older stamp with a fresh siteLoot: no source, the game's again")
_G.GuildOSInboxAck = { at = NOW }
clock = NOW + 3 * 86400 + 1
check(SL:ListsFromSite("ana") == false, "the stamp ages live: the clock moved, the same stamp is old now")
clock = NOW
for _, bad in ipairs({ false, "x", { at = "1791000000" }, { at = 0 / 0 }, { at = math.huge }, { at = 0 }, {} }) do
  _G.GuildOSInboxAck = bad or nil
  check(SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false,
    "no stamp, or one that is no plain number, is no source: " .. tostring(bad and bad.at))
end
_G.GuildOSInboxAck = { at = NOW }
GuildOS.db.siteLoot = nil
check(not SL:Active() and SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false
  and SL:Reserves() == nil and SL:Prios() == nil and SL:WishlistOf("ana") == nil, "no siteLoot: nothing")
c = roll()
check(c("Bo").softRes and c("Cy").prioOrder == 1 and c("Ana").wishlist.order == 3, "and the roll is the game's")
siteNight({ prios = false })
check(SL:PriosFromSite() == false and SL:Prios() == nil, "a night with no prios holds none")

-- Reading the inbox again stamps nothing: an old Inbox.lua read at every login is as old as its companion's stamp.
do
  local LD = LibStub("LibDeflate")
  local function wire(json) return "GOSROST1:" .. LD:EncodeForPrint(LD:CompressDeflate(json)) end
  _G.GuildOSInbox = { wire('{"fmt":"GOSROST1","v":6,"raidId":"rx","title":"T","startsAt":' .. NOW
    .. ',"instanceKey":"kara","members":[{"key":"Ana","name":"Ana","class":"MAGE"}],'
    .. '"wishlists":[{"key":"Ana-Realm","name":"Ana","class":"MAGE","items":[{"id":28770,"o":1}]}]}') }
  _G.GuildOSInboxAck, GuildOS.CompanionImport._lastInbox, GuildOS.db.settings.companion = nil, nil, true
  GuildOS.db.siteLoot = nil
  function GuildOS:GetSetting(k) return self.db.settings[k] end
  check(GuildOS.CompanionImport:ConsumeInbox(), "the inbox is read")
  check(GuildOS.db.siteLoot and GuildOS.db.siteLoot.at == nil and GuildOS.db.siteLoot.raids.rx, "and no read stamp is kept")
  check(not SL:ListsFromSite("ana"), "with no companion stamp (it does not own this folder) the list is the game's")
  _G.GuildOSInboxAck = { at = clock - 4 * 86400, members = 1 }
  GuildOS.CompanionImport._lastInbox = nil
  GuildOS.CompanionImport:ConsumeInbox()
  check(not SL:ListsFromSite("ana"), "a companion that stopped four days ago: read again at login, still the game's")
  _G.GuildOSInboxAck = { at = clock - 600, members = 1 }
  check(SL:ListsFromSite("ana"), "a companion that answered ten minutes ago: the site's")
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


-- ── 6. Two raids of the guild in one window: each is its own sheet ───
do
  GuildOS.CompanionImport._siteRaids = nil
  local RT = GuildOS.RaidTracker
  local function entry(who, startsAt)
    return { startsAt = startsAt, instanceKey = "kara",
      softres = { items = { [ITEM] = { { name = who, class = "MAGE", note = "", plusOnes = 0 } } } } }
  end
  GuildOS.db.siteLoot = { at = time(), raids = { first = entry("Ana", NOW), second = entry("Bo", NOW + 1800) } }
  -- A client stamped with its raid at zone-in keeps that raid's sheet the whole night, whatever the other's start.
  RT.currentRaid = { raidId = "first" }
  for _, when in ipairs({ NOW - 3000, NOW + 900, NOW + 2700, NOW + 5 * 3600 }) do
    clock = when
    check(SL:ActiveRaid() == "first" and names(SR:GetReserves(ITEM)) == "Ana",
      "stamped with the first raid, still the first's sheet at " .. (when - NOW) .. "s")
  end
  RT.currentRaid = { raidId = "second" }
  for _, when in ipairs({ NOW - 3000, NOW + 2700 }) do
    clock = when
    check(SL:ActiveRaid() == "second" and names(SR:GetReserves(ITEM)) == "Bo", "stamped with the second, its own at " .. (when - NOW) .. "s")
  end
  clock = NOW + 2700
  c = roll()
  check(c("Bo").softRes and c("Ana").softRes == nil, "a roll of the second raid reads the second's reserves only")
  clock = NOW + 9 * 3600
  check(not SL:Active() and SL:ActiveRaid() == nil, "stamped, but the raid's night is over: the game's tables")
  -- No stamp: the nearest start, and the same answer every time on a tie.
  RT.currentRaid = nil
  clock = NOW + 2700
  check(SL:ActiveRaid() == "second", "no stamp: the nearest start")
  clock = NOW - 3000
  check(SL:ActiveRaid() == "first", "and earlier, the first")
  RT.currentRaid = { raidId = "gone" }
  clock = NOW + 2700
  check(SL:ActiveRaid() == nil and SL:Reserves() == nil, "a stamp the site has no entry for is the game's tables, never another raid's")
  -- Kara A has no site loot, Kara B has a sheet: A's group, stamped A, never reads B's.
  GuildOS.db.siteLoot = { at = time(), raids = { second = entry("Bo", NOW + 1800) } }
  RT.currentRaid = { raidId = "first" }
  check(SL:ActiveRaid() == nil and names(SR:GetReserves(ITEM)) == "Bo" and SL:Reserves() == nil,
    "A has none and B has a sheet: A's group gets the game's (Bo is the game's reserver here), not B's")
  c = roll()
  check(c("Cy").prioOrder == 1 and c("Ana").wishlist and c("Ana").wishlist.order == 3, "and its roll reads the game's lists")
  RT.currentRaid = { raidId = "second" }
  check(SL:ActiveRaid() == "second", "B's group has B's sheet")
  GuildOS.db.siteLoot = { at = time(), raids = { first = entry("Ana", NOW), second = entry("Bo", NOW + 1800) } }
  RT.currentRaid = nil
  for i = 1, 25 do
    GuildOS.db.siteLoot = { at = time(), raids = { zeta = entry("Cy", NOW), alfa = entry("Dee", NOW), mid = entry("Ana", NOW) } }
    check(SL:ActiveRaid() == "alfa", "equal starts: by raidId, always the same (round " .. i .. ")")
  end
  instance = 565
  check(not SL:Active() and SL:Reserves() == nil, "in another instance, with no stamp, the site sheets are not used")
  instance = 532
  GuildOS.db.siteLoot = { at = time(), raids = { first = entry("Ana", NOW), second = entry("Bo", NOW + 1800) } }
  check(SL:ListsFromSite("ana") == false and SL:PriosFromSite() == false, "no list of anybody's in those entries")
  clock = NOW
end

-- ── 7. A /reload past the site's three hours keeps the night ─────────
do
  siteNight()
  clock = NOW + 4 * 3600
  local LD = LibStub("LibDeflate")
  local function wire(json) return "GOSROST1:" .. LD:EncodeForPrint(LD:CompressDeflate(json)) end
  -- The companion's next write: the started raid is not served any more, next week's is.
  _G.GuildOSInbox = { wire('{"fmt":"GOSROST1","v":6,"raidId":"r2","title":"T","startsAt":' .. (NOW + 7 * 86400)
    .. ',"instanceKey":"kara","members":[{"key":"Ana","name":"Ana","class":"MAGE"}]}') }
  _G.GuildOSInboxAck, GuildOS.CompanionImport._lastInbox, GuildOS.db.settings.companion = nil, nil, true
  GuildOS.CompanionImport:ConsumeInbox()
  check(GuildOS.db.siteLoot and GuildOS.db.siteLoot.raids.r1, "the raid the inbox stopped listing is kept")
  check(SL:Active() and names(SR:GetReserves(ITEM)) == "Ana", "and still the night's sheet at four hours in")
  clock = NOW + 9 * 3600
  GuildOS.CompanionImport._lastInbox = nil
  _G.GuildOSInbox[2] = nil
  GuildOS.CompanionImport:ConsumeInbox()
  check(GuildOS.db.siteLoot == nil, "once its night is over it goes, and with nothing else the table is nil")
  clock = NOW
end

-- ── 8. The window is the realm's clock, not this PC's ────────────────
do
  siteNight()
  for _, off in ipairs({ -3 * 3600, 3 * 3600 }) do
    skew = off
    check(SL:Active() and names(SR:GetReserves(ITEM)) == "Ana", "the PC clock " .. off .. "s off: the realm says it is the night")
    clock = NOW + 9 * 3600
    check(not SL:Active(), "and the realm's nine hours later is not")
    clock = NOW
  end
  skew = 0
end

-- ── 9. A hidden sheet never reaches the raid's chat ──────────────────
do
  local rule = GuildOS.LootRule
  siteNight({ prios = {}, wishlists = {} })
  site().softres.hidden = true
  officerView(true)
  said, printed = {}, {}
  LM.activeLoot, LM.rolls = nil, {}
  LM.lootWindowOpen = false
  LM:AnnounceItem(LINK, nil)
  LM:RegisterRoll("Ana", "MS", 90)
  LM:RegisterRoll("Bo", "MS", 10)
  said = {}
  LM:EndRolling(true)
  local line = table.concat(said, "\n")
  check(line:find("[WINNER]", 1, true) and line:find("Ana", 1, true), "hidden: a winner is announced")
  check(not line:find("Reserve", 1, true) and not line:find("reserve", 1, true), "hidden: without saying it was a reserve: " .. line)
  site().softres.hidden = nil
  said = {}
  LM.activeLoot, LM.rolls = nil, {}
  LM:AnnounceItem(LINK, nil)
  LM:RegisterRoll("Ana", "MS", 90)
  LM:RegisterRoll("Bo", "MS", 10)
  said = {}
  LM:EndRolling(true)
  check(table.concat(said, "\n"):find("Reserve", 1, true), "visible: the winner line says it as it always did")

  -- The filters of a rule that need a reserve: they depend on the roller's own reserve only, so a hidden
  -- sheet says them to that roller, never to the raid.
  local whispers = {}
  local realSend = SendChatMessage
  SendChatMessage = function(msg, channel, _, to) whispers[#whispers + 1] = { msg = msg, channel = channel, to = to } end
  local answerFor = rule.AnswerFor
  local function fresh()
    LM.activeLoot, LM.rolls = nil, {}
    LM:AnnounceItem(LINK, nil)
    said, whispers = {}, {}
  end
  local function raidHears(name)
    for _, m in ipairs(said) do if m:find(name, 1, true) then return true end end
    return false
  end
  local function whisperedTo(name)
    for _, w in ipairs(whispers) do if w.to == name and w.channel == "WHISPER" then return w.msg end end
  end
  site().softres.hidden = true
  rule.AnswerFor = function() return nil, { k = "reserved" } end
  fresh()
  LM:RegisterRoll("Cy", "MS", 10)
  LM:RegisterRoll("Cy", "MS", 10)
  check(LM.rolls[K("Cy")] == nil and not raidHears("Cy"), "hidden: the block line is not in the raid's chat")
  check(whisperedTo("Cy") and whisperedTo("Cy"):find("not reserved", 1, true) and #whispers == 1,
    "hidden: Cy is told it, alone, and once")
  rule.AnswerFor = function() return "OS", { k = "reserved", act = "downgrade", from = "MS", to = "OS" } end
  fresh()
  LM:RegisterRoll("Cy", "MS", 10)
  LM:RegisterRoll("Bo", "MS", 10)
  check(not raidHears("Cy") and not raidHears("Bo") and not raidHears("not reserved"),
    "hidden: the downgrade form names nobody in the raid's chat")
  check(whisperedTo("Cy") and whisperedTo("Cy"):find("read as", 1, true) and whisperedTo("Bo"), "hidden: each roller is whispered theirs")
  check(LM.rolls[K("Cy")] and LM.rolls[K("Cy")].rollType == "OS", "and the downgrade still applies")
  site().softres.hidden = nil
  fresh()
  LM:RegisterRoll("Cy", "MS", 10)
  check(raidHears("Cy") and #whispers == 0, "visible: the raid hears it, as it always did")
  rule.AnswerFor = function() return nil, { k = "reserved" } end
  fresh()
  LM:RegisterRoll("Cy", "MS", 10)
  check(table.concat(said, "\n"):find("not reserved", 1, true) and #whispers == 0, "visible: and so the block line")
  rule.AnswerFor = answerFor
  SendChatMessage = realSend
end

-- ── 10. A tie in the site's priorities is not a direct award ─────────
do
  siteNight({ softres = false, wishlists = false,
    prios = { [ITEM] = { { name = "Ana", class = "MAGE", order = 1 }, { name = "Bo", class = "MAGE", order = 1 },
                         { name = "Cy", class = "MAGE", order = 2 } } } })
  GuildOS.db.settings.lootSystem = "wishlist"
  local restricted, direct
  local oldR, oldA = LM.StartRestrictedRoll, LM.AutoCouncilAward
  LM.StartRestrictedRoll = function(_, tied) restricted = tied end
  LM.AutoCouncilAward = function(_, top) direct = top end
  LM.activeLoot, LM.rolls = nil, {}
  LM:AnnounceItem(LINK, nil)
  check(restricted and #restricted == 2 and direct == nil, "a tie at the top of the site's priorities: a roll among the tied, no direct award")
  check(restricted[1].name == "Ana" and restricted[2].name == "Bo", "the tied, and only them")
  -- The restricted roll says prio for a prio tie; the open roll names all of the tied.
  LM.StartRestrictedRoll, LM.AutoCouncilAward = oldR, oldA
  said, printed = {}, {}
  LM:StartRestrictedRoll(restricted, nil, LINK, nil, ITEM, "prio")
  check(table.concat(said, "\n"):find("Tie [prio #1]", 1, true) and table.concat(printed, "\n"):find("Prio tie", 1, true),
    "the restricted roll of a prio tie says prio")
  LM:CancelRolling()
  -- Forty tied names still fit a chat line.
  local forty = {}
  for i = 1, 40 do forty[i] = { name = "Player" .. string.format("%02d", i) .. "-Realm", class = "MAGE", order = 1 } end
  said, printed = {}, {}
  LM:StartRestrictedRoll(forty, nil, LINK, nil, ITEM, "prio")
  local tieLine = said[1] or ""
  check(#tieLine <= 255 and tieLine:find("Player01", 1, true) and tieLine:find("+%d+") , "forty tied: the roll line fits 255 bytes with a +N: " .. #tieLine)
  LM:CancelRolling()
  local tops = { name = "x", names = {} }
  for i = 1, 40 do tops.names[i] = forty[i].name end
  said = {}
  local tiePrios = GuildOS.db.siteLoot.raids.r1.prios
  GuildOS.db.siteLoot.raids.r1.prios = { [ITEM] = forty }
  GuildOS.db.settings.lootSystem = "rolls"
  LM.activeLoot, LM.rolls = nil, {}
  LM:AnnounceItem(LINK, nil)
  for _, m in ipairs(said) do check(#m <= 255 or m:find("|H", 1, true), "no chat line past 255 bytes: " .. #m) end
  check(LM:FitNames({ "A", "B" }, 100) == "A, B" and LM:FitNames(tops.names, 60):find("+%d+"), "FitNames keeps a short list whole and cuts a long one")
  GuildOS.db.siteLoot.raids.r1.prios = tiePrios
  GuildOS.db.settings.lootSystem = "rolls"
  said, printed = {}, {}
  LM.activeLoot, LM.rolls = nil, {}
  LM:AnnounceItem(LINK, nil)
  check(table.concat(said, "\n"):find("Ana, Bo are tied at official prio #1", 1, true), "an open roll names every one of the tied")
  GuildOS.db.settings.lootSystem = "wishlist"
  LM.StartRestrictedRoll, LM.AutoCouncilAward = function(_, tied) restricted = tied end, function(_, top) direct = top end
  -- Without a tie the top one is still prompted.
  siteNight({ softres = false, wishlists = false,
    prios = { [ITEM] = { { name = "Ana", class = "MAGE", order = 1 }, { name = "Bo", class = "MAGE", order = 2 } } } })
  restricted, direct = nil, nil
  LM.activeLoot, LM.rolls = nil, {}
  LM:AnnounceItem(LINK, nil)
  check(restricted == nil and direct and direct.name == "Ana", "no tie: the top prio is offered the award")
  -- The game's list is in positions: it never ties.
  GuildOS.db.siteLoot = nil
  restricted, direct = nil, nil
  LM.activeLoot, LM.rolls = nil, {}
  LM:AnnounceItem(LINK, nil)
  check(restricted == nil and direct and direct.name == "Cy", "the game's own list, as before")
  LM.StartRestrictedRoll, LM.AutoCouncilAward = oldR, oldA
  GuildOS.db.settings.lootSystem = "rolls"
end

-- ── 11. The screens read what the roll reads ─────────────────────────
do
  siteNight()
  check(LM:AllPrios()[ITEM][1].name == "Bo", "the prio screens: the site's list tonight")
  check(WL:ListFor("Ana-Realm", "Ana").wishlist[1].order == 1 and WL:AllLists().ana.wishlist[1].order == 1
    and WL:AllLists().dee, "the wishlist screens: the site's for its people, the game's for the rest")
  GuildOS.db.siteLoot = nil
  check(LM:AllPrios()[ITEM][1].name == "Cy" and WL:ListFor("Ana-Realm", "Ana").wishlist[1].order == 3, "and the game's otherwise")
end

-- ── 12. A night of two places is one raid's in both (R19) ────────────
do
  local RT = GuildOS.RaidTracker
  RT.currentRaid = nil
  siteNight({ instanceKey = "gruul", instanceKeys = { "gruul", "mag" } })
  instance = 565   -- Gruul's Lair
  check(SL:ActiveRaid() == "r1" and names(SR:GetReserves(ITEM)) == "Ana", "in Gruul's Lair, the raid's sheet")
  instance = 544   -- Magtheridon's Lair, the second place of the same night
  check(SL:ActiveRaid() == "r1" and names(SR:GetReserves(ITEM)) == "Ana", "and in Magtheridon's Lair the same raid's")
  instance = 532
  check(SL:ActiveRaid() == nil, "a third place is not that raid")
  siteNight({ instanceKey = "gruul" })
  instance = 544
  check(SL:ActiveRaid() == nil, "with one place only, Magtheridon's Lair is not a Gruul night")
  -- The session is stamped by the same match, so the attendance of the second place has its raid too.
  GuildOS.db.companionRaids = { { raidId = "r1", instanceKey = "gruul", instanceKeys = { "gruul", "mag" }, startsAt = NOW } }
  check(GuildOS.CompanionImport:RaidFor(RT:RaidKeyOf(544), NOW + 3600) == "r1", "the stamp in Magtheridon's Lair names the raid")
  GuildOS.db.companionRaids = nil
  instance = 532
end

-- ── 13. A raid this client cannot stamp locks nothing (R20) ──────────
do
  local c = GuildOS.Client
  siteNight({ instanceKey = "barrow-deeps" })
  check(not SL:ListsFromSite("ana") and not SL:PriosFromSite() and SL:ListInForce("ana") == nil,
    "a place with no map id here: the site's data is never used, so it is no source either")
  siteNight({ instanceKey = "kara", instanceKeys = { "kara", "barrow-deeps" } })
  check(not SL:ListsFromSite("ana"), "one place of the night with no map id: the game's list plays there, so it stays editable")
  siteNight({ instanceKey = "kara", instanceKeys = { "kara", "gruul" } })
  check(SL:ListsFromSite("ana"), "every place known: the site's")
  -- WoW: Forever has its own table: Onyxia is known, Barrow Deeps and Hyjal are not yet.
  local was = { c.isAnniversary, c.isRetail }
  c.isAnniversary, c.isRetail = false, false
  siteNight({ instanceKey = "forever-onyxia" })
  check(SL:ListsFromSite("ana"), "Forever: Onyxia's Lair has its map id")
  for _, key in ipairs({ "barrow-deeps", "forever-hyjal", "kara" }) do
    siteNight({ instanceKey = key })
    check(not SL:ListsFromSite("ana"), "Forever: " .. key .. " cannot be stamped here")
  end
  c.isAnniversary, c.isRetail = was[1], was[2]
end

-- ── 14. Hidden priorities never reach the raid's chat (R21) ──────────
do
  local RT = GuildOS.RaidTracker
  RT.currentRaid = nil
  local function chat() return table.concat(said, "\n") end
  local function local_() return table.concat(printed, "\n") end
  local function night(hidden, prios)
    siteNight({ softres = false, wishlists = false, priosHidden = hidden or nil,
      prios = prios or { [ITEM] = { { name = "Bo", class = "MAGE", order = 1 }, { name = "Ana", class = "MAGE", order = 2 } } } })
  end
  local tie = { [ITEM] = { { name = "Ana", class = "MAGE", order = 1 }, { name = "Bo", class = "MAGE", order = 1 } } }
  for _, hidden in ipairs({ true, false }) do
    local tag = hidden and "hidden" or "visible"
    -- Drop time, an open roll: who has prio #1.
    GuildOS.db.settings.lootSystem = "rolls"
    night(hidden)
    said, printed = {}, {}
    LM.activeLoot, LM.rolls = nil, {}
    LM:AnnounceItem(LINK, nil)
    check((chat():find("official prio", 1, true) ~= nil) == not hidden, tag .. ": the raid hears prio #1 only when open: " .. chat())
    check(not hidden or local_():find("Bo has official prio #1", 1, true), tag .. ": the loot master reads it")
    -- A roll's acknowledgement names the roller's place, and the winner's line the reason.
    said, printed = {}, {}
    LM:RegisterRoll("Bo", "MS", 90)
    LM:RegisterRoll("Ana", "MS", 10)
    check((chat():find("Official Prio", 1, true) ~= nil) == not hidden, tag .. ": the roll lines name a prio place only when open")
    check(not hidden or local_():find("Bo: MS (Official Prio #1)", 1, true), tag .. ": the loot master reads Bo's place")
    said, printed = {}, {}
    LM:EndRolling(true)
    check(chat():find("[WINNER]", 1, true) and chat():find("Bo", 1, true), tag .. ": the winner is named")
    check((chat():find("Official Prio", 1, true) ~= nil) == not hidden and not (hidden and chat():find("officer priority", 1, true)),
      tag .. ": the winner's line gives the prio reason only when open: " .. chat())
    check(not hidden or local_():find("Official Prio #1", 1, true), tag .. ": the loot master reads why")
    -- A tie at the top, an open roll.
    night(hidden, tie)
    said, printed = {}, {}
    LM.activeLoot, LM.rolls = nil, {}
    LM:AnnounceItem(LINK, nil)
    check((chat():find("tied at official prio", 1, true) ~= nil) == not hidden, tag .. ": the tie line only when open")
    check(not hidden or local_():find("Ana, Bo are tied at official prio #1", 1, true), tag .. ": the loot master reads the tie")
    -- The wishlist system: a direct award, and a tie's restricted roll.
    GuildOS.db.settings.lootSystem = "wishlist"
    night(hidden)
    said, printed = {}, {}
    LM.activeLoot, LM.rolls = nil, {}
    local showCouncil = LM.ShowCouncilResultFrame
    LM.ShowCouncilResultFrame = function() end
    LM:AnnounceItem(LINK, nil)
    LM.ShowCouncilResultFrame = showCouncil
    check(chat():find("goes to Bo", 1, true), tag .. ": the award names the winner")
    check((chat():find("Official Prio", 1, true) ~= nil) == not hidden, tag .. ": with the prio reason only when open: " .. chat())
    check(not hidden or local_():find("goes to Bo (Official Prio #1)", 1, true), tag .. ": the loot master reads the reason")
    night(hidden, tie)
    said, printed = {}, {}
    LM.activeLoot, LM.rolls = nil, {}
    LM:AnnounceItem(LINK, nil)
    check(LM.restrictedRollers and LM.restrictedRollers.ana and LM.restrictedRollers.bo and not LM.restrictedRollers.cy,
      tag .. ": the tied still roll among themselves")
    check((chat():find("Tie [prio", 1, true) ~= nil) == not hidden and (chat():find("prio", 1, true) ~= nil) == not hidden,
      tag .. ": the raid warning says prio only when open: " .. chat())
    check(not hidden or (chat():find("only Ana, Bo may roll", 1, true) and local_():find("Prio tie", 1, true)),
      tag .. ": hidden, it says who may roll and the loot master reads why")
    LM:CancelRolling()
  end
  -- The game's own priorities are said as they always were, whatever the site's marker.
  GuildOS.db.siteLoot = nil
  GuildOS.db.settings.lootSystem = "rolls"
  said, printed = {}, {}
  LM.activeLoot, LM.rolls = nil, {}
  LM:AnnounceItem(LINK, nil)
  check(chat():find("Cy has official prio #1", 1, true), "the game's priorities: the raid hears them, as before")
  check(not LM:PriosHidden(), "and nothing is hidden")
  LM:CancelRolling()
end

for _, k in ipairs({ "softRes", "lootPrios", "wishlists", "guildWishlists" }) do
  check(same(GuildOS.db[k], BEFORE[k]), k .. " is still what it was after all of it")
end

print("site-night: " .. checks .. " checks passed")
