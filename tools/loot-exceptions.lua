-- Exceptions per item (issue #335), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Core/Data.lua, Modules/CoreManager.lua, Modules/RaidTracker.lua, Modules/Points.lua,
-- Modules/LootRule.lua, Modules/LootMaster.lua and UI/FeaturePanels.lua:
--   * a rule's exceptions are read whole or the rule is refused;
--   * each category is recognised from what the client says of the item (recipe, mount, bind on equip,
--     legendary, below the loot threshold) or from the game's list (tier), and "nobody asked" only at
--     the roll's end;
--   * the most specific exception wins: the item, then the boss, then the category, then the raid;
--   * a fixed destination has no roll: the bank character or the disenchanter gets the item, the raid
--     is told which exception said so, and nobody is charged; with no character set, nothing is given;
--   * an exception's own order decides its item, and the announce says which exception applied;
--   * a rule with no exception does what it always did with an item nobody rolled for, and the Send to
--     Disenchant button is as it was;
--   * the officer's exceptions go through LootRule, and the editor draws.
--
--   luajit -e 'ADDON="."' tools/loot-exceptions.lua
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
local widgets, buttons = {}, {}
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
function CreateFrame(kind) local w = widget({ kind = kind }); widgets[#widgets + 1] = w; return w end
UIParent, GameTooltip, UISpecialFrames = widget(), widget(), {}
RAID_CLASS_COLORS = {}
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetInstanceInfo() return "Karazhan", "raid", 9, "", 10, 0, false, 532 end
function GetRealmName() return "Realm" end
local NOW = 1791000000
function GetServerTime() return NOW end
function GetTime() return 100 end
time, date = os.time, os.date
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInRaid() return true end
function IsInGroup() return true end
function SendChatMessage() end
function GetLootMethod() return "master", 0 end
local raid = { "Lead", "Ana", "Bo", "Cy" }
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
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
GuildOS.db = { settings = { lootSystem = "rolls" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { awardHistory = {} }, points = {},
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local LM, LR, P, CM, RT = GuildOS.LootMaster, GuildOS.LootRule, GuildOS.Points, GuildOS.CoreManager, GuildOS.RaidTracker
local officer = true
GuildOS.IsOfficer = function() return officer end
local officers = { ["Off-Realm"] = true }
GuildOS.IsOfficerByName = function(_, name) return officers[name] == true end
function GuildOS:ApplyFont() end
-- What the officers' sync carries, and the handlers it would call.
local published, handlers = {}, {}
GuildOS.SyncService = {
  On = function(_, dom, fn) handlers[dom] = fn end,
  ShouldApply = function() return true end, SetRevision = function() end, NextRevision = function() return 1 end,
  Publish = function(_, dom, act, data, opts)
    published[#published + 1] = { dom = dom, act = act, data = data, rev = opts and opts.rev }
  end,
}
P:Initialize()
CM:InitSync()
local function K(name) return GuildOS:GetPlayerKey(name) end

local said, sent, printed = {}, {}, {}
LM.SafeSendAddon = function(_, _, payload) sent[#sent + 1] = payload end
LM.SendEcho = function() end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.IsMasterLooter = function() return true end
LM.GetPlayerContext = function() return { att25 = 100, recvThisLockout = 0 } end
LM.ShowRollFrame = function() end
LM.StopListeningForRolls = function() end
function GuildOS:Print(msg) printed[#printed + 1] = msg end
local shown = 0
function GuildOS:UpdateLootSystemUI() shown = shown + 1 end
local function quiet() said, sent, printed, published = {}, {}, {}, {} end
local function all(list) return table.concat(list, "\n") end

LM.QueueForTrade = function() end
local wishes = {}
GuildOS.Wishlist = { GetItemInterest = function() return wishes end }

-- What the client says of each item: quality, class, subclass, how it binds.
local ITEMS = {
  [28770] = { name = "Nathrezim Mindblade", quality = 4, classID = 2, subclassID = 15, bind = 1 },
  [30000] = { name = "Plans: Something", quality = 4, classID = 9, subclassID = 4, bind = 1 },
  [30001] = { name = "Fiery Warhorse's Reins", quality = 4, classID = 15, subclassID = 5, bind = 1 },
  [30002] = { name = "World Drop Belt", quality = 4, classID = 4, subclassID = 1, bind = 2 },
  [30003] = { name = "Warglaive", quality = 5, classID = 2, subclassID = 7, bind = 1 },
  [30004] = { name = "Green Bracers", quality = 2, classID = 4, subclassID = 1, bind = 1 },
  [30005] = { name = "Helm Token", quality = 4, classID = 15, subclassID = 0, bind = 1 },
}
function GetItemInfo(item)
  local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
  local it = ITEMS[id]
  if not it then return nil end
  return it.name, "[" .. it.name .. "]", it.quality, 115, 70, "", "", 1, "", 0, 0, it.classID, it.subclassID, it.bind
end
local function link(id) return "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[" .. ITEMS[id].name .. "]|h|r" end
local LINK = link(28770)
local function announce(id)
  quiet()
  LM.lootWindowOpen = false
  LM:AnnounceItem(link(id or 28770), nil)
end
local function lastAward() return GuildOS.db.lootMaster.awardHistory[1] end
local function base(exceptions, more)
  local r = { v = 1, model = "custom", order = { { k = "response" }, { k = "roll" } }, exceptions = exceptions }
  for k, v in pairs(more or {}) do r[k] = v end
  return r
end

-- ── 1. A rule's exceptions, read whole ──────────────────────────────
local function reads(r, what) local ok, why = LR:Validate(r); check(ok, what .. " (" .. tostring(why) .. ")") end
local function no(r, what, why)
  local ok, got = LR:Validate(r)
  check(ok == false and (why == nil or got == why), "refused: " .. what .. " (" .. tostring(got) .. ")")
end
reads(base({
  { on = { items = { 19019 } }, name = "Thunderfury", set = { order = { { k = "wishlist" } }, decide = { by = "ml" } } },
  { on = { cat = "recipe" }, to = "bank" },
  { on = { cat = "unclaimed" }, to = "de" },
}), "the contract's own example")
reads(base({ { on = { boss = 652 }, to = "de" }, { on = { raid = 532 }, set = { filters = {} } } }), "a boss and a raid")
reads(base({ { on = { cat = "boe", raid = 532 }, to = "bank" } }), "two things an item must be at once")
no(base({ { on = {}, to = "bank" } }), "an exception on nothing")
no(base({ { to = "bank" } }), "an exception with no items named")
no(base({ { on = { cat = "pets" }, to = "bank" } }), "a category it does not know")
no(base({ { on = { cat = "recipe" }, to = "vendor" } }), "a destination it does not know")
no(base({ { on = { cat = "recipe" } } }), "neither a destination nor blocks")
no(base({ { on = { cat = "recipe" }, to = "bank", set = { order = { { k = "roll" } } } } }), "both a destination and blocks")
no(base({ { on = { cat = "recipe" }, set = {} } }), "blocks, and none of them")
no(base({ { on = { cat = "recipe" }, set = { time = 10 } } }), "a block an exception cannot swap")
no(base({ { on = { cat = "recipe" }, set = { order = { { k = "parse" } } } } }), "an order it cannot read", "unknown criterion")
no(base({ { on = { cat = "recipe" }, set = { decide = { by = "council", council = { quorum = 0 } } } } }), "a council of no quorum inside an exception", "decide")
no(base({ { on = { cat = "recipe" }, set = { effects = { { k = "add", acct = "plus1", value = 1 } } } } }), "an effect on an account the rule does not keep")
no(base({ { on = { items = {} }, to = "bank" } }), "an empty list of items")
no(base({ { on = { items = { 0 } }, to = "bank" } }), "an item id that is none")
no(base({ { on = { items = { "19019" } }, to = "bank" } }), "an item id as text")
no(base({ { on = { boss = 1.5 }, to = "bank" } }), "half a boss")
no(base({ { on = { cat = "recipe", zone = 3 }, to = "bank" } }), "a field it never heard of")
no(base({ { on = { cat = "recipe" }, to = "bank", name = "a|cffff0000b" } }), "a name with a colour code")
local many = {}
for i = 1, 21 do many[i] = { on = { items = { i } }, to = "bank" } end
no(base(many), "twenty-one exceptions")
many[21] = nil
reads(base(many), "twenty are a rule")
local forty = {}
for i = 1, 41 do forty[i] = i end
no(base({ { on = { items = forty }, to = "bank" } }), "forty-one items in one exception")

-- ── 2. The categories, from what the client says of the item ────────
local function cats(id) return LR:Categories(LM:ItemFacts(link(id), nil)) end
local function only(id, cat)
  local got = cats(id)
  local n = 0
  for _ in pairs(got) do n = n + 1 end
  return got[cat] == true and n == 1
end
check(next(cats(28770)) == nil, "an epic sword is in no category")
check(only(30000, "recipe"), "a recipe by its item class")
check(only(30001, "mount"), "a mount by its class and subclass")
check(only(30002, "boe"), "bind on equip by how it binds")
check(only(30003, "legendary"), "a legendary by its quality")
check(only(30004, "trash"), "an uncommon item under a loot threshold of rare")
LM:SetLootThreshold(2)
check(next(cats(30004)) == nil, "and not under a threshold of uncommon")
LM:SetLootThreshold(3)
for game, list in pairs(LR.TIER_ITEMS) do
  check(next(list) == nil, "the shipped tier list of " .. game .. " is empty: no id goes in unchecked")
end
check(cats(30005).tier == nil, "so no item is a tier piece yet")
LR.TIER_ITEMS[GuildOS.Client.game][30005] = true
check(only(30005, "tier"), "an item on this game's list is one")
check(LR:ExceptionFor(base({ { on = { cat = "unclaimed" }, to = "de" } }), LM:ItemFacts(LINK), false) == nil,
  "nobody asked is never said of an item being announced")
check(LR:ExceptionFor(base({ { on = { cat = "unclaimed" }, to = "de" } }), LM:ItemFacts(LINK), true) ~= nil,
  "only at the roll's end")
-- The raid, and the boss while its loot window is open a short while after the kill.
local facts = LM:ItemFacts(LINK, nil)
check(facts.raid == 532 and facts.boss == nil and facts.id == 28770 and facts.threshold == 3, "an item knows its raid")
RT.currentRaid = { startTime = NOW - 3600, encounters = { { id = 652, success = true, endTime = NOW - 60 } } }
LM.lootWindowOpen = true
check(LM:ItemFacts(LINK, 1).boss == 652, "and, in the loot window of a boss killed a minute ago, its boss")
check(LM:ItemFacts(LINK, nil).boss == nil, "an item rolled from the bags names no boss")
RT.currentRaid.encounters[1].endTime = NOW - 3600
check(LM:ItemFacts(LINK, 1).boss == nil, "nor does a loot window an hour after the kill")
RT.currentRaid.encounters[1] = { id = 652, success = false, endTime = NOW - 60 }
check(LM:ItemFacts(LINK, 1).boss == nil, "nor a wipe")
LM.lootWindowOpen = false
RT.currentRaid = nil

-- ── 3. The most specific wins ───────────────────────────────────────
local byRaid = { on = { raid = 532 }, to = "de", name = "raid" }
local byCat = { on = { cat = "boe" }, to = "de", name = "cat" }
local byBoss = { on = { boss = 652 }, to = "de", name = "boss" }
local byItem = { on = { items = { 1, 30002 } }, to = "de", name = "item" }
local ladder = base({ byRaid, byCat, byBoss, byItem })   -- least specific first: place is not what decides
local it = { id = 30002, bindType = 2, boss = 652, raid = 532, quality = 4, threshold = 3 }
check(LR:ExceptionFor(ladder, it) == byItem, "the item's own exception before any other")
it.id = 9
check(LR:ExceptionFor(ladder, it) == byBoss, "then the boss's")
it.boss = 7
check(LR:ExceptionFor(ladder, it) == byCat, "then the category's")
it.bindType = 1
check(LR:ExceptionFor(ladder, it) == byRaid, "then the raid's")
it.raid = 1
check(LR:ExceptionFor(ladder, it) == nil, "and an item none of them names follows the rule")
local first, second = { on = { cat = "boe" }, to = "bank" }, { on = { cat = "legendary" }, to = "de" }
check(LR:ExceptionFor(base({ first, second }), { bindType = 2, quality = 5 }) == first, "between two as specific, the first")
local both = { on = { cat = "boe", raid = 532 }, to = "bank" }
check(LR:ExceptionFor(base({ both }), { bindType = 2, raid = 1 }) == nil and LR:ExceptionFor(base({ both }), { bindType = 2, raid = 532 }) == both,
  "an exception on two things asks for both")

-- ── 4. A fixed destination: no roll ─────────────────────────────────
check(LR:Set(base({ { on = { cat = "recipe" }, to = "bank" }, { on = { cat = "mount" }, to = "de" } },
  { effects = { { k = "charge", acct = "dkp", price = "fixed", value = 10 } } })) == true, "recipes to the bank, mounts to the disenchanter")
GuildOS.db.points.config.itemCost = 10
announce(30000)
check(LM.activeLoot == nil and #sent == 0 and #said == 0 and printed[#printed]:find("No bank character set.", 1, true)
  and lastAward() == nil, "with no bank character named, the loot master is told and nothing is given")
LM:SetBank(" Banker ")
check(LM:GetBank() == "Banker" and GuildOS.db.lootMaster.bank == "Banker", "the bank character is kept with the loot settings")
announce(30000)
check(said[1] == "[Loot] " .. link(30000) .. " goes to the guild bank (Banker) - exception: recipes",
  "a recipe goes to the bank, and the raid is told which exception said so: " .. tostring(said[1]))
check(#said == 1 and not all(sent):find("ASK|", 1, true) and not all(sent):find("ANNOUNCE|", 1, true), "with no roll opened")
check(lastAward().player == "Banker" and lastAward().itemId == 30000 and LM.activeLoot == nil, "the item is awarded to the bank character")
check(P:Get(K("Banker")) == 0 and lastAward().charged == nil, "who pays nothing for it")
announce(30001)
check(LM.activeLoot == nil and printed[#printed]:find("No disenchanter set.", 1, true) and lastAward().itemId == 30000,
  "with no disenchanter named, the same")
LM:SetDisenchanter("Dis")
announce(30001)
check(said[1] == "[Loot] " .. link(30001) .. " goes to Disenchant (Dis) - exception: mounts" and lastAward().player == "Dis",
  "a mount goes to the disenchanter: " .. tostring(said[1]))
announce()
check(LM.activeLoot and LM.activeLoot.exception == nil and said[1]:find("[ROLL]", 1, true) and not said[1]:find("exception", 1, true),
  "an item no exception names is rolled for as always")
LM:CancelRolling()
-- Each core its own bank character, as its disenchanter.
CM:Create("Alpha")
RT:SetGroupTag("Alpha")
check(LM:GetBank() == "Banker", "a core with no bank character of its own uses the guild's")
LM:SetBank("Alphabank")
RT:SetGroupTag("")
check(LM:GetBank() == "Banker" and CM:GetLootConfig("Alpha").bank == "Alphabank", "and one it names is its own")

-- ── 5. Nobody asked ─────────────────────────────────────────────────
LR:Set(base({ { on = { cat = "unclaimed" }, to = "de" } }))
announce()
check(LM.activeLoot and said[1]:find("[ROLL]", 1, true), "the item is rolled for first")
LM:EndRolling(true)
check(all(said):find("No roll received", 1, true) and said[#said] == "[Loot] " .. LINK .. " - nobody rolled. Sending to Disenchant: Dis",
  "nobody asked: it goes to the disenchanter, in the words of always: " .. tostring(said[#said]))
check(lastAward().player == "Dis" and lastAward().itemId == 28770 and LM.activeLoot == nil, "and is awarded there")
announce()
LM:RegisterRoll("Ana", "MS", 50)
LM:RegisterRoll("Bo", "PASS", 0)
LM:EndRolling(true)
check(LM.activeLoot and LM.activeLoot.sortedResults[1].name == "Ana" and lastAward().player == "Dis" and #GuildOS.db.lootMaster.awardHistory == 3,
  "somebody asked: the roll ends as always and nothing is sent anywhere")
LM:CancelRolling()
announce()
LM:RegisterRoll("Bo", "PASS", 0)
LM:EndRolling(true)
check(lastAward().player == "Dis" and #GuildOS.db.lootMaster.awardHistory == 4, "a roll of passes only is nobody asking")
LR:Set(base({ { on = { cat = "unclaimed" }, to = "bank" } }))
announce()
LM:EndRolling(true)
check(lastAward().player == "Banker" and said[#said]:find("goes to the guild bank (Banker) - exception: nobody asked", 1, true),
  "or to the bank, when the rule says so: " .. tostring(said[#said]))
LM.IsMasterLooter = function() return false end
announce()
LM:EndRolling(true)
check(#GuildOS.db.lootMaster.awardHistory == 5 and LM.activeLoot ~= nil, "only the master looter's client sends it")
LM.IsMasterLooter = function() return true end
LM:CancelRolling()

-- ── 6. An exception's own order ─────────────────────────────────────
local thunder = { on = { items = { 28770 } }, name = "Mindblade", set = { order = { { k = "wishlist" }, { k = "roll" } }, decide = { by = "ml" } } }
local withOwn = base({ thunder, { on = { raid = 532 }, set = { order = { { k = "roll" } } } } }, { time = 20 })
check(LR:Set(withOwn) == true, "an item with an order of its own, and a raid with another")
wishes = { { name = "Bo", order = 1 } }
announce()
check(LM.activeLoot.exception == thunder and LM.activeLoot.rule ~= withOwn and LM.activeLoot.baseRule == withOwn,
  "the item is announced by its exception's rule")
check(said[1]:find("exception: Mindblade", 1, true) and said[1]:find("[ROLL]", 1, true), "and the announce says which exception applied: " .. tostring(said[1]))
check(LM.activeLoot.rule.order[1].k == "wishlist" and LM.activeLoot.rule.decide.by == "ml" and LM.activeLoot.rule.time == 20
  and LM.activeLoot.rule.responses == withOwn.responses, "the blocks it names are swapped, and every other is the rule's")
check(LM.restrictedRollers == nil, "its roll is open to everyone: the exception's order is the whole order")
LM:RegisterRoll("Ana", "MS", 99)
LM:RegisterRoll("Bo", "OS", 1)
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "Bo" and LM.activeLoot.decidedBy == "wishlist",
  "and its order decides: the wishlist before everything, the answer not at all")
LM:CancelRolling()
wishes = {}
announce(30003)
check(LM.activeLoot.exception == withOwn.exceptions[2] and said[1]:find("exception: raid 532", 1, true),
  "another item of the raid follows the raid's exception, named by what it is on: " .. tostring(said[1]))
LM:RegisterRoll("Ana", "OS", 99)
LM:RegisterRoll("Bo", "MS", 1)
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "Ana", "where only the roll decides")
-- The rule changes under the open roll: the item keeps its exception's.
LR:Set(nil)
check(LM:Rule().order[1].k == "roll" and LR:Active().exceptions == nil, "an item keeps the exception it was announced under")
LM:CancelRolling()

-- ── 7. No exception: as it always was ───────────────────────────────
check(LR:Active().model == "rolls" and LR:Active().exceptions == nil, "the loot system's rule has no exception")
announce()
check(said[1] == "[ROLL] " .. LINK .. "  -  /roll 1-100 = MS  -  /roll 1-99 = OS  -  30s", "the announce of always: " .. tostring(said[1]))
local before = #GuildOS.db.lootMaster.awardHistory
LM:EndRolling(true)
check(#GuildOS.db.lootMaster.awardHistory == before and LM.activeLoot ~= nil and said[#said]:find("No roll received", 1, true),
  "nobody rolled: the raid is told and the item waits for the loot master, as before")
quiet()
LM:SendToDisenchanter(LM.activeLoot.link, LM.activeLoot.slot, LM.activeLoot.itemId)
check(said[1] == "[Loot] " .. LINK .. " delivered to Disenchant (Dis)" and lastAward().player == "Dis" and LM.activeLoot == nil,
  "whose Send to Disenchant button does what it did: " .. tostring(said[1]))
announce(30004)
check(LM.activeLoot and LM.activeLoot.exception == nil and said[1]:find("[ROLL]", 1, true), "and an item below the threshold is rolled for when the loot master announces it")
LM:CancelRolling()

-- ── 8. An officer's exceptions ──────────────────────────────────────
check(LR:AddException({ kind = "cat", value = "recipe", to = "bank" }) == true and LR:IsCustom(), "an exception is added to the guild's rule")
check(LR:Active().exceptions[1].on.cat == "recipe" and LR:Active().exceptions[1].to == "bank", "and kept")
check(LR:AddException({ kind = "items", value = "28770, 30003", order = { "wishlist", "roll" } }) == true, "items typed as ids, with an order of their own")
local added = LR:Active().exceptions[2]
check(added.on.items[1] == 28770 and added.on.items[2] == 30003 and added.set.order[1].k == "wishlist" and added.set.order[2].k == "roll",
  "the ids and the order are read")
check(LR:AddException({ kind = "boss", value = "652", to = "de" }) == true and LR:Active().exceptions[3].on.boss == 652, "a boss by its encounter id")
check(LR:AddException({ kind = "raid", value = 532, to = "de" }) == true, "a raid by its instance id")
check(LR:AddException({ kind = "items", value = "none", to = "bank" }) == false, "items with no id are refused")
check(LR:AddException({ kind = "boss", value = "Attumen", to = "bank" }) == false, "and a boss that is no id")
check(LR:AddException({ kind = "cat", value = "recipe", order = {} }) == false, "and an order of nothing")
check(LR:AddException({ kind = "cat", value = "recipe", order = { "parse" } }) == false, "and an order it cannot read")
check(LR:AddException({ kind = "zone", value = 1, to = "bank" }) == false and LR:AddException("recipe") == false, "and a kind it does not know")
check(#LR:Active().exceptions == 4, "none of which changed the rule")
check(LR:RemoveException(1) == true and #LR:Active().exceptions == 3 and LR:Active().exceptions[1].on.items, "an exception is removed")
check(LR:RemoveException(9) == false, "but not one that is not there")
GuildOS.IsOfficer = function() return false end
check(LR:AddException({ kind = "cat", value = "boe", to = "de" }) == false and #LR:Active().exceptions == 3, "and only an officer changes them")
GuildOS.IsOfficer = function() return true end
check(LR:AddException({ kind = "cat", value = "boe", to = "de" }, "Alpha") == true and LR:IsCustom("Alpha")
  and #LR:For("Alpha").exceptions == 4 and #LR:For("").exceptions == 3, "a core's exceptions are the core's")
LR:Set(nil, "Alpha")
LR:RemoveException(1); LR:RemoveException(1)
check(LR:RemoveException(1) == true and LR:Active().exceptions == nil, "the last one removed leaves a rule with none")
LR:Set(nil)

-- ── 9. The editor draws, and its buttons reach LootRule ─────────────
GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })
GuildOS.UI = setmetatable({
  CreateButton = function(_, _, text)
    local b = widget({ text = tostring(text), label = widget() })
    buttons[#buttons + 1] = b
    return b
  end,
  CreateCheckbox = function() return widget({ checkbox = widget() }) end,
  CreateScrollFrame = function() return widget(), widget() end,
  AttachSaveButton = function(_, box, onSave)
    box.saveButton = widget({ text = "Save" })
    box.save = function(t) box.text = t; onSave(box) end
    return box.saveButton
  end,
}, { __index = function() return function() return widget() end end })
local function button(text)
  for i = #buttons, 1, -1 do
    if buttons[i].text == text then return buttons[i] end
  end
end
local function click(text)
  local b = button(text)
  check(b and b.scripts.OnClick, "there is a button " .. text)
  b.scripts.OnClick(b)
end
dofile(ADDON .. "/UI/FeaturePanels.lua")
GuildOS.CreateRolePicker = function() return widget() end
GuildOS.ShowPointsFrame = function() end
local content = widget()
local function draw()
  widgets, buttons = {}, {}
  local drew, problem = pcall(GuildOS.RefreshSettingsPanel, GuildOS, content, "loot")
  check(drew, "the loot settings draw (" .. tostring(problem) .. ")")
end
GuildOS.RefreshSettingsPanel = (function(real)
  return function(self, c, cat)
    widgets, buttons = {}, {}
    return real(self, c, cat)
  end
end)(GuildOS.RefreshSettingsPanel)
draw()
check(button("Add exception") and button("Category") and button("recipes") and button("To the bank"), "the editor offers an exception to add")
click("Add exception")
check(LR:Active().exceptions and LR:Active().exceptions[1].on.cat == "recipe" and LR:Active().exceptions[1].to == "bank",
  "a click adds the one shown: recipes to the bank")
check(button("Remove") ~= nil, "which is listed with a way to remove it")
click("recipes")
click("To the bank")
check(button("bind on equip") and button("To the disenchanter"), "the category and the destination turn with a click")
click("To the disenchanter")
check(button("Another order") and button("wishlist place") and button("the roll"), "another order offers the criteria")
click("wishlist place")
click("the roll")
check(button("Clear order") and not button("wishlist place"), "a criterion picked is next in the order, and offered no more")
click("Add exception")
local made = LR:Active().exceptions[2]
check(made and made.on.cat == "boe" and made.set.order[1].k == "wishlist" and made.set.order[2].k == "roll",
  "and the exception added is decided by the order picked")
click("Category")
check(button("Item ids"), "the kind turns with a click too")
click("Another order")
check(button("To the bank"), "and the destination comes round to the bank")
local typed
for _, w in ipairs(widgets) do
  if w.kind == "EditBox" and w.scripts.OnTextChanged then typed = w end
end
check(typed, "items are typed in a box")
typed.text = "28770"
typed.scripts.OnTextChanged(typed)
click("Add exception")
check(#LR:Active().exceptions == 3 and LR:Active().exceptions[3].on.items[1] == 28770, "an item's exception is added from what was typed")
quiet()
typed = nil
for _, w in ipairs(widgets) do
  if w.kind == "EditBox" and w.scripts.OnTextChanged then typed = w end
end
typed.text = "nothing"
typed.scripts.OnTextChanged(typed)
click("Add exception")
check(#LR:Active().exceptions == 3 and #printed == 1, "and one that is none is refused, with a word to the officer")
LR:Set(nil)

print(("loot-exceptions: %d checks passed"):format(checks))
