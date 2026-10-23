-- The wishlist on retail (issue #185), run against the real Core, Compat, Utils, WishlistSystem,
-- LootTracker, the slash router and the feature registry, under a stubbed retail client on Tol Barad
-- (with a stubbed Encounter Journal) and a stubbed WoW: Forever one.
--
-- Retail's raid items are not TBC's static lists: they come from the Encounter Journal at run time, for
-- Midnight's four raids (journal instances 1307 The Voidspire, 1314 The Dreamrift, 1308 March on
-- Quel'Danas, 1320 The Venomous Abyss), read with every class's loot and put back as the player left
-- the journal, never while it is open. An item the client has not cached yet is still found by the name
-- the journal gave. Wishlists are kept by the whole Name-Realm, taken from who sent them, so namesakes
-- on connected realms never merge and nobody files a list under someone else's name. An item counts as
-- delivered when the history has it as mine: personal loot, or an award recorded by trade.
--
--   luajit -e 'ADDON="."' tools/retail-wishlist.lua
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

local NOW = 1791000000
local printed, frames, sent = {}, {}, {}
-- The journal: each raid's loot, one row per item, as C_EncounterJournal.GetLootInfoByIndex gives it.
local JOURNAL = {
  [1307] = { name = "The Voidspire", loot = {
    { itemID = 250001, name = "Voidforged Helm", encounterID = 2733, link = "|cnIQ4:|Hitem:250001::::::::90:::::|h[Voidforged Helm]|h|r" },
    { itemID = 250002, name = "Dreamrift Band", encounterID = 2734 } } },
  [1314] = { name = "The Dreamrift", loot = { { itemID = 250010, name = nil, encounterID = 2740 } } },
  [1308] = { name = "March on Quel'Danas", loot = { { itemID = 250020, name = "Sunwell Shard", encounterID = 2750 } } },
  [1320] = { name = "The Venomous Abyss", loot = {} },   -- not loaded yet: the list comes later
}
local BOSSES = { [2733] = "Imperator Averzian", [2734] = "Vorasius", [2740] = "Chimaerus", [2750] = "Belo'ren" }
local ej = { selected = nil, class = 7, spec = 263, slot = 4, reads = 0 }
local CACHED = { [250001] = { "Voidforged Helm", 4 } }   -- what GetItemInfo knows

local function stubJournal()
  function EJ_SelectInstance(id) ej.selected = id end
  function EJ_SelectEncounter(id) ej.encounter = id end
  function EJ_GetNumLoot()
    ej.reads = ej.reads + 1
    local j = JOURNAL[ej.selected]
    if not j or ej.class ~= 0 then return j and 1 or 0 end   -- a class filter would hide loot
    return #j.loot
  end
  function EJ_GetLootFilter() return ej.class, ej.spec end
  function EJ_SetLootFilter(c, s) ej.class, ej.spec = c, s end
  function EJ_GetEncounterInfo(id) return BOSSES[id] end
  function EJ_GetInstanceInfo(id) return JOURNAL[id or ej.selected] and JOURNAL[id or ej.selected].name end
  C_EncounterJournal = {
    GetLootInfoByIndex = function(i) local j = JOURNAL[ej.selected]; return j and j.loot[i] end,
    GetSlotFilter = function() return ej.slot end,
    ResetSlotFilter = function() ej.slot = 15 end,
    SetSlotFilter = function(s) ej.slot = s end,
  }
end

local function load(retail)
  printed, frames, sent = {}, {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  function issecretvalue() return false end
  function CreateFrame()
    local f = { events = {}, scripts = {} }
    function f.RegisterEvent(self, e) self.events[e] = true end
    function f.UnregisterEvent(self, e) self.events[e] = nil end
    function f.SetScript(self, what, fn) self.scripts[what] = fn end
    frames[#frames + 1] = f
    return setmetatable(f, { __index = function() return function() end end })
  end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return NOW end
  time = function() return NOW end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function wipe(t) for k in pairs(t) do t[k] = nil end return t end
  strlower, format = string.lower, string.format
  function IsInGuild() return true end
  function GetGuildInfo() return "Jardim Escola", "Officer", 1, "Azralon" end
  function GetRealmName() return retail and "Tol Barad" or "Classic Beta PvE" end
  function GetNormalizedRealmName() return retail and "TolBarad" or "ClassicBetaPvE" end
  local roster = { "Chehul-TolBarad", "Ana-Gallywix", "Ana-TolBarad" }
  function GetNumGuildMembers() return #roster end
  function GetGuildRosterInfo(i) return roster[i] end
  function UnitName() return "Chehul" end
  function UnitClass() return "Druid", "DRUID", 11 end
  C_Item = { GetItemInfo = function(item)
    local id = tonumber(tostring(item):match("item:(%d+)") or item)
    local it = CACHED[id]
    if it then return it[1], "|cnIQ" .. it[2] .. ":|Hitem:" .. id .. "::::::::90:::::|h[" .. it[1] .. "]|h|r", it[2] end
  end }
  C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
    { __call = function() return { Serialize = function(_, t) return t end,
                                   Deserialize = function(_, t) return true, t end } end })
  SlashCmdList = {}
  EJ_SelectInstance, EJ_GetNumLoot, C_EncounterJournal, EncounterJournal = nil, nil, nil, nil
  if retail then stubJournal() end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return true end
  GuildOS.db = { settings = { modules = {} }, members = {}, lootHistory = {} }
  GuildOS.CommSystem = { SendMessage = function(_, t, data) sent[#sent + 1] = { t = t, data = data } end }
  dofile(ADDON .. "/Modules/WishlistSystem.lua")
end

local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- ── 1. Retail: the wishlist is here, its items from the journal ───────
load(true)
local W = GuildOS.Wishlist
check(W ~= nil, "the wishlist loads on retail (issue #185)")
check(W.JOURNAL_RAIDS[1] == 1307 and W.JOURNAL_RAIDS[2] == 1314 and W.JOURNAL_RAIDS[3] == 1308
  and W.JOURNAL_RAIDS[4] == 1320, "Midnight's four raids, by journal instance")
W:Initialize()
check(W:GetItemInterest(250001) ~= nil and W:GetItemInterest(250002) ~= nil and W:GetItemInterest(250020) ~= nil,
  "the journal's items are searchable")
check(W:GetItemInterest(21882) == nil, "TBC's raid catalogue is not")
check(ej.class == 7 and ej.spec == 263 and ej.slot == 4, "the journal's class and slot filters are put back")
local entry = W:CatalogEntry(250002)
check(entry and entry.name == "Dreamrift Band" and entry.raid == "The Voidspire" and entry.boss == "Vorasius",
  "an item knows its name, raid and boss from the journal")
-- Not cached: the journal's name stands in; cached: the client's own answer.
local name, link, quality = W:ItemFacts(250002)
check(name == "Dreamrift Band" and quality == 4, "an item the client has not cached is named by the journal")
name, link = W:ItemFacts(250001)
check(name == "Voidforged Helm" and link:find("item:250001", 1, true), "a cached one by the client")
check(W:ItemFacts(250010) == nil, "an item with no name anywhere yet has none")

-- The Venomous Abyss had no list yet: it is read again when the journal's data arrives.
check(W:GetItemInterest(250030) == nil, "a raid whose list has not arrived has no items yet")
JOURNAL[1320].loot = { { itemID = 250030, name = "Fang of Ula'tek", encounterID = 2760 } }
JOURNAL[1314].loot[1].name = "Rift Sigil"
fire("EJ_LOOT_DATA_RECIEVED")
check(W:GetItemInterest(250030) ~= nil and W:CatalogEntry(250010).name == "Rift Sigil",
  "the journal's data arriving fills in what was missing")
local reads = ej.reads
fire("EJ_LOOT_DATA_RECIEVED")
check(ej.reads == reads, "once complete, the journal is not read again")

-- The journal open: never read under the player's eyes, and their instance put back after a read.
EncounterJournal = { IsShown = function() return true end, instanceID = 1302, encounterID = 2600 }
reads = ej.reads
W:LoadJournal(true)
check(ej.reads == reads, "the journal is not read while it is open")
EncounterJournal.IsShown = function() return false end
W:LoadJournal(true)
check(ej.reads > reads and ej.selected == 1302 and ej.encounter == 2600,
  "after a read, the instance the journal last showed is selected again")
EncounterJournal = nil

-- ── 2. My list, keyed by my whole name ────────────────────────────────
W:AddToWishlist(250002, nil, false)
local mine = W:GetMyList()
check(#mine == 1 and mine[1].itemId == 250002, "an item the client has not cached can be wished for")
check(sent[#sent].t == "WL" and sent[#sent].data.name == "Chehul-TolBarad", "my list goes out under my whole name")
check(GuildOS.db.guildWishlists["chehul-tolbarad"] ~= nil, "and is kept under it")

-- Guildmates' lists are kept by who sent them, never by the name inside.
W:HandleWishlistBroadcast("Ana-Gallywix", { name = "Bob", class = "MAGE", wishlist = { { itemId = 250001, order = 1 } } }, "GUILD")
W:HandleWishlistBroadcast("Ana", { name = "Ana", class = "PRIEST", wishlist = { { itemId = 250001, order = 2 } } }, "GUILD")
W:HandleWishlistBroadcast("Chehul-TolBarad", { name = "Chehul", class = "DRUID", wishlist = {} }, "GUILD")
-- Only a guildmate's list, and only over GUILD.
W:HandleWishlistBroadcast("Mallory-Nemesis", { name = "Mallory", class = "ROGUE", wishlist = { { itemId = 250001, order = 1 } } }, "GUILD")
W:HandleWishlistBroadcast("Ana-TolBarad", { name = "Ana", class = "PRIEST", wishlist = { { itemId = 250002, order = 1 } } }, "WHISPER")
check(GuildOS.db.guildWishlists["mallory-nemesis"] == nil, "a list from outside the guild is not kept")
check(GuildOS.db.guildWishlists["ana-tolbarad"].wishlist[1].itemId == 250001, "nor one that came by whisper")
local gw = GuildOS.db.guildWishlists
check(gw["ana-gallywix"] and gw["ana-gallywix"].name == "Ana-Gallywix" and gw.bob == nil,
  "a list is filed under its sender's whole name, not the one it claims")
check(gw["ana-tolbarad"] and gw["ana-tolbarad"].name == "Ana-TolBarad", "a sender with no realm is on mine")
check(#gw["chehul-tolbarad"].wishlist == 1, "my own echo does not replace my list")
local who = {}
for _, e in ipairs(W:GetItemInterest(250001)) do who[e.name] = e.order end
check(who["Ana-Gallywix"] == 1 and who["Ana-TolBarad"] == 2, "two namesakes wish for the same item apart")
check(W:ListFor("Ana-Gallywix", "Ana") == gw["ana-gallywix"], "a member's list is found by their key")

-- ── 3. Delivered: personal loot or an award by trade ──────────────────
check(not W:IsItemDelivered(250002), "nothing delivered yet")
GuildOS.db.lootHistory = { { itemId = 250002, playerKey = "Ana-Gallywix", player = "Ana-Gallywix", timestamp = NOW } }
check(not W:IsItemDelivered(250002), "another player's item is not mine")
GuildOS.db.lootHistory[2] = { itemId = 250002, playerKey = "Chehul-TolBarad", player = "Chehul-TolBarad", timestamp = NOW }
check(W:IsItemDelivered(250002), "my personal loot of it is delivered")
GuildOS.db.lootHistory = { { itemLink = "|Hitem:250002::|h[x]|h", playerKey = "Chehul-TolBarad", awarded = true,
  from = "Ana-Gallywix", timestamp = NOW } }
check(W:IsItemDelivered(250002), "so is an award recorded by trade")
printed = {}
W:RemoveFromWishlist(250002)
check(#W:GetMyList() == 1, "a delivered item stays on the list")

-- ── 4. The verbs and the tab ──────────────────────────────────────────
dofile(ADDON .. "/Core/Commands.lua")
local opened = 0
GuildOS.ShowWishlistFrame = function() opened = opened + 1 end
printed = {}
check(pcall(SlashCmdList.GUILDOS, "wish") and opened == 1, "/gos wish opens the wishlist on retail")
check(not table.concat(printed, " "):find("Not available on this client.", 1, true), "and does not say it is absent")
printed = {}
SlashCmdList.GUILDOS("softres")
check(table.concat(printed, " "):find("Not available on this client.", 1, true), "soft reserves still are")
GuildOS.UI = {}
dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Features.lua")
check(not GuildOS.UI:IsFeatureAbsent(GuildOS.UI:GetFeature("wishlist")), "the wishlist tab is on retail")

-- ── 5. Forever: as before ─────────────────────────────────────────────
load(false)
W = GuildOS.Wishlist
W:Initialize()
check(W.catalog == nil or next(W.catalog) == nil, "Forever reads no journal")
CACHED[250002] = { "Dreamrift Band", 4 }
W:AddToWishlist(250002, nil, false)
check(sent[#sent].data.name == "Chehul" and GuildOS.db.guildWishlists.chehul ~= nil, "Forever keys a list by the name, as before")
W:HandleWishlistBroadcast("Ana-Gallywix", { name = "Ana", class = "MAGE", wishlist = { { itemId = 250001, order = 1 } } })
check(GuildOS.db.guildWishlists.ana ~= nil, "and a guildmate's by the name it carries")
GuildOS.db.lootHistory = { { itemId = 250002, playerKey = GuildOS:GetPlayerKey("Chehul"), timestamp = NOW } }
check(not W:IsItemDelivered(250002), "Forever counts only a master-loot award as delivered")
GuildOS.db.lootHistory[1].fromML = true
check(W:IsItemDelivered(250002), "as before")

print(("retail-wishlist: %d checks passed"):format(checks))
