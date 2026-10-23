-- The loot council by trade on retail (issue #185), run against the real Core, Compat, Utils,
-- LootTracker, Points, WishlistSystem, TradeCouncil and the slash router, under a stubbed retail client
-- on Tol Barad (bags, tooltip data, the trade window, addon and chat messages) and a stubbed Forever one.
--
-- Retail has no Master Loot. A guildmate who received a personal item that can still be traded offers
-- it to the raid; the raid's guildmates answer Need, Greed or Pass with what they wear in that slot; an
-- officer, or the holder under the guild's free roll, awards it; and when the holder trades it to the
-- winner the award goes into the loot history (the holder's row of that drop becomes the winner's) and,
-- where the guild runs DKP, the awarding officer charges it. A trade of an offered item to anyone else
-- records nothing and says so. The trade window of a personal item is only on its tooltip, a
-- TradeTimeRemaining line read with the client's own duration strings. Only a guildmate's message over
-- RAID is read; a secret one is never touched; a lockdown holds what is sent until it lifts.
--
--   luajit -e 'ADDON="."' tools/retail-loot-council.lua
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
local SECRET = setmetatable({}, { __tostring = function() error("a secret value was read") end,
  __concat = function() error("a secret value was joined") end, __eq = function() error("a secret value was compared") end })
local printed, frames, addon, chat = {}, {}, {}, {}
local lockdown, inRaid = false, true
-- The guild across connected realms; rank 1 is an officer. I am Chehul, an officer.
local ROSTER = { { "Chehul-TolBarad", 1 }, { "Ana-Gallywix", 4 }, { "Bob-TolBarad", 4 }, { "Off-TolBarad", 1 } }
local function link(id, name, q) return ("|cnIQ%d:|Hitem:%d::::::::90:::::|h[%s]|h|r"):format(q or 4, id, name) end
local HELM, BAND, RING1, RING2, CAPE = link(250001, "Voidforged Helm"), link(250002, "Dreamrift Band"),
  link(240011, "Old Band", 4), link(240012, "Older Band", 4), link(250003, "Gloomweave Cloak")
local ITEMS = {   -- name, quality, item level, equip location
  [250001] = { "Voidforged Helm", 4, 285, "INVTYPE_HEAD" }, [250002] = { "Dreamrift Band", 4, 285, "INVTYPE_FINGER" },
  [240011] = { "Old Band", 4, 250, "INVTYPE_FINGER" }, [240012] = { "Older Band", 4, 240, "INVTYPE_FINGER" },
  [250003] = { "Gloomweave Cloak", 3, 285, "INVTYPE_CLOAK" }, [250004] = { "Void Dust", 2, 1, "" },
}
local TRADE_LINE = "You may trade this item with players that were also eligible to loot this item for the next %s."
-- My bags: bag 0. A bound helm with 1h30 to trade, a ring with 45 min, a soulbound cloak, a green.
local BAGS
local function resetBags()
  BAGS = { [0] = {
    { itemID = 250001, hyperlink = HELM, quality = 4, isBound = true, trade = "1 hour 30 min" },
    { itemID = 250002, hyperlink = BAND, quality = 4, isBound = true, trade = "45 min" },
    { itemID = 250003, hyperlink = CAPE, quality = 3, isBound = true },
    { itemID = 250004, hyperlink = link(250004, "Void Dust", 2), quality = 2, isBound = true, trade = "1 hour 59 min" },
  } }
end
local WORN = { [11] = RING1, [12] = RING2, [1] = link(240001, "Cracked Helm") }
local npc, tradeSlots = nil, {}

local function load(retail)
  printed, frames, addon, chat = {}, {}, {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  function issecretvalue(v) return rawequal(v, SECRET) end
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
  function GetTime() return 0 end
  time = function() return NOW end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function wipe(t) for k in pairs(t) do t[k] = nil end return t end
  strlower, format = string.lower, string.format
  function IsInGuild() return true end
  function GetGuildInfo() return "Jardim Escola", "Officer", 1, "Azralon" end
  function GetRealmName() return "Tol Barad" end
  function GetNormalizedRealmName() return "TolBarad" end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i)
    local r = ROSTER[i]
    if r then return r[1], "Rank", r[2] end
  end
  function IsInRaid() return inRaid end
  function GetNumGroupMembers() return 4 end
  function UnitName(unit)
    if unit == "NPC" then if npc then return npc[1], npc[2] end return nil end
    return "Chehul"
  end
  function UnitClass() return "Druid", "DRUID", 11 end
  function UnitIsGroupLeader() return true end
  function GetInventoryItemLink(_, slot) return WORN[slot] end
  function GetTradePlayerItemLink(i) return tradeSlots[i] end
  ERR_TRADE_COMPLETE = "Trade complete."
  INT_SPELL_DURATION_HOURS, INT_SPELL_DURATION_MIN, INT_SPELL_DURATION_SEC = "%d |4hour:hours;", "%d min", "%d sec"
  Enum = { TooltipDataLineType = { TradeTimeRemaining = 36 } }
  C_Item = {
    GetItemInfo = function(item)
      local id = tonumber(tostring(item):match("item:(%d+)") or item)
      local it = ITEMS[id]
      if it then return it[1], link(id, it[1], it[2]), it[2], it[3] end
    end,
    GetItemInfoInstant = function(item)
      local id = tonumber(tostring(item):match("item:(%d+)") or item)
      local it = ITEMS[id]
      if it then return id, "Armor", "Misc", it[4] end
    end,
    GetDetailedItemLevelInfo = function(item)
      local it = ITEMS[tonumber(tostring(item):match("item:(%d+)"))]
      return it and it[3]
    end,
  }
  C_Container = {
    GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
  }
  C_TooltipInfo = { GetBagItem = function(bag, slot)
    local it = BAGS[bag] and BAGS[bag][slot]
    if not it then return nil end
    local lines = { { type = 22, leftText = "name" } }
    if it.trade then lines[#lines + 1] = { type = 36, leftText = TRADE_LINE:format(it.trade) } end
    return { lines = lines }
  end }
  C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel) addon[#addon + 1] = { prefix = prefix, text = text, channel = channel } end,
    InChatMessagingLockdown = function() return lockdown end,
    SendChatMessage = function(text, channel) chat[#chat + 1] = { text = text, channel = channel } end,
  }
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
    { __call = function() return { Serialize = function(_, t) return t end, Deserialize = function(_, t) return true, t end } end })
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.db = { settings = { modules = {} }, members = {}, lootHistory = {}, sync = { rev = {} } }
  GuildOS.SyncService = { On = function() end, Publish = function() end }
  dofile(ADDON .. "/Modules/LootTracker.lua")
  dofile(ADDON .. "/Modules/Points.lua")
  dofile(ADDON .. "/Modules/WishlistSystem.lua")
  dofile(ADDON .. "/Modules/TradeCouncil.lua")
  dofile(ADDON .. "/Core/Commands.lua")
end

local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function said(text) return table.concat(printed, "\n"):find(text, 1, true) ~= nil end
local function lastAddon() return addon[#addon] end
local function incoming(text, sender, channel)
  fire("CHAT_MSG_ADDON", "GuildOSTC", text, channel or "RAID", sender)
end

-- ── 1. Reading a personal item's trade window ─────────────────────────
load(true)
local C = GuildOS.Compat
check(C.TradeSeconds(TRADE_LINE:format("1 hour 30 min")) == 5400, "an hour and a half is read in seconds")
check(C.TradeSeconds(TRADE_LINE:format("2 hours")) == 7200 and C.TradeSeconds(TRADE_LINE:format("45 min")) == 2700,
  "and whole hours, and minutes alone")
check(C.TradeSeconds("no time here") == nil, "a line with no duration in it reads as unknown")
INT_SPELL_DURATION_HOURS, INT_SPELL_DURATION_MIN = "%d |4hora:horas;", "%d min"
check(C.TradeSeconds("Você pode negociar este item ... pelas próximas 1 hora 5 min.") == 3900,
  "in another language, by its own words")
INT_SPELL_DURATION_HOURS = "%d |4час:часа:часов;"
check(C.TradeSeconds("ещё 2 часа") == 7200, "with three plural forms too")
INT_SPELL_DURATION_HOURS, INT_SPELL_DURATION_MIN = "%d |4hour:hours;", "%d min"
resetBags()
local kind, secs = C.TradeTimeLeft(0, 1)
check(kind == "timed" and secs == 5400, "a bound item with its trade line is timed, with its seconds")
check(C.TradeTimeLeft(0, 3) == "bound", "a bound item without the line can no longer be traded")
BAGS[0][3].isBound = false
check(C.TradeTimeLeft(0, 3) == "free", "an item that is not bound is free to trade")
BAGS[0][3].isBound = true
check(C.TradeTimeLeft(0, 9) == nil, "an empty slot is nothing")
BAGS[0][2].isBound = SECRET
check(C.TradeTimeLeft(0, 2) == nil, "a secret answer is never read")
BAGS[0][2].isBound = true

-- ── 2. What I can offer ───────────────────────────────────────────────
local TC = GuildOS.TradeCouncil
check(TC ~= nil, "the loot council is on retail (issue #185)")
check(GuildOS:StartModule({ "TradeCouncil" }), "and starts")
local mine = TC:MyTradeableItems()
check(#mine == 2 and mine[1].link == BAND and mine[1].seconds == 2700 and mine[2].link == HELM,
  "my Rare-and-up items still tradeable, the soonest to close first; not the soulbound one nor the green")
check(TC:EquippedFor(BAND) == RING2, "for a ring, what I wear that it would replace: the lower of the two")
check(TC:EquippedFor(HELM) == WORN[1], "for a helm, my helm")

-- ── 3. Offering ───────────────────────────────────────────────────────
inRaid = false
printed = {}
check(TC:Offer(HELM) == nil and said("You must be in a raid to offer loot."), "an offer needs a raid")
inRaid = true
GuildOS.db.settings.lootSystem = "external"
printed = {}
check(TC:Offer(HELM) == nil and said("External / Off"), "nor when the guild hands loot out elsewhere")
GuildOS.db.settings.lootSystem = nil
printed = {}
check(TC:Offer(link(259999, "Nothing")) == nil and said("That item is not in your bags."), "an item I do not have")
check(TC:Offer(CAPE) == nil and said("That item can no longer be traded."), "an item past its trade window")
check(TC:Offer("not a link") == nil and said("Usage: /gos offer <item link>"), "nor a word that is no item")
local GuildShow
GuildOS.ShowTradeCouncil = function(_, id) GuildShow = id end
local o = TC:Offer(HELM)
check(o and o.holder == "Chehul-TolBarad" and o.link == HELM and o.itemId == 250001 and o.free == true,
  "my helm is offered, as a free roll (the guild rolls)")
check(o.expires == NOW + 5400 + 60 and o.timeKnown, "until its trade window closes, a minute's slack for the whole minutes it is read in")
local sent = lastAddon()
check(sent.prefix == "GuildOSTC" and sent.channel == "RAID" and sent.text == ("O|%s|1|5400|%s"):format(o.id, HELM),
  "the offer goes to the raid: id, free, seconds, link")
check(GuildShow == o.id, "and the council opens on it")
printed = {}
check(TC:Offer(HELM) == o and said("You are already offering that item."), "an item is offered once")

-- ── 4. Answers ────────────────────────────────────────────────────────
incoming(("A|%s|N|%s"):format(o.id, RING1), "Ana-Gallywix")
incoming(("A|%s|G|"):format(o.id), "Bob")
incoming(("A|%s|N|"):format(o.id), "Stranger-Nemesis")
incoming(("A|%s|N|"):format(o.id), "Off-TolBarad", "GUILD")
incoming(("A|%s|N|"):format(o.id), SECRET)
incoming(SECRET, "Off-TolBarad")
check(o.answers["Ana-Gallywix"] and o.answers["Ana-Gallywix"].choice == "N" and o.answers["Ana-Gallywix"].equipped == RING1,
  "a guildmate on a connected realm answers, with what they wear")
check(o.answers["Bob-TolBarad"] and o.answers["Bob-TolBarad"].choice == "G" and o.answers["Bob-TolBarad"].equipped == nil,
  "a guildmate on my realm, named with it")
check(o.answers["Stranger-Nemesis"] == nil and o.answers["Off-TolBarad"] == nil,
  "a stranger's answer, or one not over RAID, or a secret one, is not read")
incoming(("A|%s|P|"):format(o.id), "Off-TolBarad")
local rows = TC:Ranked(o)
check(#rows == 3 and rows[1].key == "Ana-Gallywix" and rows[2].key == "Bob-TolBarad" and rows[3].choice == "P",
  "Need before Greed before Pass")
check(rows[1].roll == TC.Roll(o.id, "Ana-Gallywix") and rows[1].roll >= 1 and rows[1].roll <= 100,
  "each answer carries a roll every screen computes alike, 1 to 100")
-- Two Needs: the guild's system decides, then the roll.
incoming(("A|%s|N|"):format(o.id), "Bob-TolBarad")
GuildOS.db.guildWishlists = {
  ["bob-tolbarad"] = { name = "Bob-TolBarad", wishlist = { { itemId = 250001, order = 1 } } },
  ["ana-gallywix"] = { name = "Ana-Gallywix", wishlist = { { itemId = 250001, order = 3 } } },
}
GuildOS.Wishlist:RebuildItemIndex()
GuildOS.db.settings.lootSystem = "wishlist"
rows = TC:Ranked(o)
check(rows[1].key == "Bob-TolBarad" and rows[1].wish == 1 and rows[2].wish == 3, "under the wishlist, the higher place first")
local wishers = TC:Wishers(o)
check(#wishers == 2 and wishers[1].key == "Bob-TolBarad" and wishers[1].answered, "the council shows who wished for it")
GuildOS.Points:Initialize()
GuildOS.Points:Award("Ana-Gallywix", 50, "x")
GuildOS.db.settings.lootSystem = "dkp"
rows = TC:Ranked(o)
check(rows[1].key == "Ana-Gallywix" and rows[1].points == 50, "under DKP, the most points first")
GuildOS.db.settings.lootSystem = nil
rows = TC:Ranked(o)
local a, b = TC.Roll(o.id, "Ana-Gallywix"), TC.Roll(o.id, "Bob-TolBarad")
check(rows[1].key == (a > b and "Ana-Gallywix" or "Bob-TolBarad"), "in a free roll, the higher roll first")

-- ── 5. Awarding, and the trade ────────────────────────────────────────
TC:Award(o.id, "Off-TolBarad")
check(o.award == nil, "a Pass is never awarded")
local realIsOfficer = GuildOS.IsOfficer
GuildOS.IsOfficer = function() return false end
TC:Award(o.id, "Ana-Gallywix")
check(o.award and o.award.winner == "Ana-Gallywix" and o.award.by == "Chehul-TolBarad",
  "the holder of a free roll awards it, officer or not")
check(lastAddon().text == ("W|%s|Ana-Gallywix"):format(o.id), "the award goes to the raid")
check(chat[#chat].channel == "RAID" and chat[#chat].text:find("Ana-Gallywix", 1, true), "and the winner is announced")
GuildOS.IsOfficer = realIsOfficer
-- The trade: the winner's realm read from the trade window; my helm in it; "Trade complete."
GuildOS.db.lootHistory = { { itemLink = HELM, itemId = 250001, player = "Chehul-TolBarad", playerKey = "Chehul-TolBarad",
  timestamp = NOW - 600, raid = "The Voidspire", encounterID = 3176, quality = 4 } }
npc = { "Ana", "Gallywix" }
printed = {}
fire("TRADE_SHOW")
check(said("Put " .. HELM .. " in the trade window"), "trading the winner, I am told what to put in")
tradeSlots = { HELM }
fire("TRADE_PLAYER_ITEM_CHANGED", 1)
fire("TRADE_ACCEPT_UPDATE", 1, 0)
NOW = NOW + 90   -- the winner takes a minute and a half to accept
fire("UI_INFO_MESSAGE", 999, "Trade complete.")
local row = GuildOS.db.lootHistory[1]
check(#GuildOS.db.lootHistory == 1 and row.playerKey == "Ana-Gallywix" and row.player == "Ana-Gallywix"
  and row.awarded and row.from == "Chehul-TolBarad" and row.raid == "The Voidspire",
  "the award is recorded: my row of that drop becomes the winner's")
check(o.done and o.closed and lastAddon().text == ("D|%s|Ana-Gallywix|Chehul-TolBarad"):format(o.id),
  "however long the winner took, and the raid hears it went through: winner and who awarded it")
check(GuildOS.Wishlist:IsItemDelivered(250001) == false, "the item is the winner's now, not mine")

-- An offered item traded to someone who was not awarded it: nothing recorded, and it says so.
local o2 = TC:Offer(BAND)
incoming(("A|%s|N|"):format(o2.id), "Ana-Gallywix")
npc, tradeSlots = { "Bob" }, {}
fire("TRADE_SHOW")
tradeSlots = { BAND }
fire("TRADE_ACCEPT_UPDATE", 1, 1)
printed = {}
local before = #GuildOS.db.lootHistory
fire("UI_INFO_MESSAGE", 999, "Trade complete.")
check(#GuildOS.db.lootHistory == before and said("who was not awarded it: nothing was recorded."),
  "a trade to anyone else records nothing, and says so")
check(o2.closed and not o2.done and lastAddon().text == "X|" .. o2.id, "and the offer is over for the raid too")
-- A second "Trade complete." with no trade window opened since is nothing.
fire("UI_INFO_MESSAGE", 999, "Trade complete.")
check(#GuildOS.db.lootHistory == before, "a second 'Trade complete.' with no trade open is nothing")

-- ── 6. Somebody else's offer: an officer awards, the holder's trade records, DKP charges ─
GuildOS.db.settings.lootSystem = "dkp"
GuildOS.Points:GetDB().config.itemCost = 20
local id = "65A1B2C30001"
incoming(("O|%s|0|3600|%s"):format(id, CAPE), "Ana-Gallywix")
local o3 = TC:Get(id)
check(o3 and o3.holder == "Ana-Gallywix" and not o3.free and o3.expires == NOW + 3600 + 60, "a guildmate's offer arrives")
check(GuildShow == id, "and the council opens on it")
incoming(("O|%s|1|60|%s"):format(id, HELM), "Bob")
check(TC:Get(id).holder == "Ana-Gallywix" and TC:Get(id).link == CAPE, "nobody takes over an offer's id")
incoming(("O|%s|0|0|%s"):format("65A1B2C30002", CAPE), "Stranger-Nemesis")
check(TC:Get("65A1B2C30002") == nil, "a stranger offers nothing to the guild")
for i, bad in ipairs({ "|Hitem:250003|h[Cloak]|h", CAPE .. "|Hitem:1|h", "x " .. CAPE, "|cff00ff00|Hitem:abc|h[x]|h|r" }) do
  incoming(("O|65A1B2C3001%d|0|0|%s"):format(i, bad), "Bob-TolBarad")
  check(TC:Get(("65A1B2C3001%d"):format(i)) == nil, "an offer whose link is not one whole item link is not taken: " .. bad)
end
-- A holder's free roll is believed only where the guild's loot system is the free roll.
incoming(("O|%s|1|3600|%s"):format("65A1B2C30020", CAPE), "Bob-TolBarad")
local greedy = TC:Get("65A1B2C30020")
check(greedy and not greedy.free, "under DKP a holder's offer is no free roll, whatever it says")
incoming(("A|%s|N|"):format(greedy.id), "Ana-Gallywix")
incoming(("W|%s|Ana-Gallywix"):format(greedy.id), "Bob-TolBarad")
check(greedy.award == nil, "so its holder cannot award it")
TC:Answer(id, "N")
check(lastAddon().text == ("A|%s|N|"):format(id) and o3.answers["Chehul-TolBarad"].choice == "N",
  "I answer Need, with no cloak worn to replace")
incoming(("A|%s|G|%s"):format(id, "|Hitem:1|h"), "Bob-TolBarad")
check(o3.answers["Bob-TolBarad"].choice == "G" and o3.answers["Bob-TolBarad"].equipped == nil,
  "an answer's equipped item that is not a whole link is left out")
-- An award from somebody who may not give it.
incoming(("W|%s|Bob-TolBarad"):format(id), "Ana-Gallywix")
incoming(("W|%s|Bob-TolBarad"):format(id), "Bob-TolBarad")
check(o3.award == nil, "neither the holder of a council offer nor a member awards it")
-- I, an officer, award it to Bob.
TC:Award(id, "Bob-TolBarad")
check(o3.award and o3.award.by == "Chehul-TolBarad" and lastAddon().text == ("W|%s|Bob-TolBarad"):format(id),
  "an officer awards it")
GuildOS.db.lootHistory = {}
local pointsBefore = GuildOS.Points:Get("Bob-TolBarad")
-- Another officer awards it to Ana at the same moment; Ana-Gallywix, the holder, saw mine last.
incoming(("W|%s|Ana-Gallywix"):format(id), "Off-TolBarad")
check(o3.award.winner == "Ana-Gallywix" and o3.award.by == "Off-TolBarad", "the later award is the one this client shows")
incoming(("D|%s|Bob-TolBarad|Chehul-TolBarad"):format(id), "Off-TolBarad")
incoming(("D|%s|Bob-TolBarad|Bob-TolBarad"):format(id), "Ana-Gallywix")
incoming(("D|%s|Bob-TolBarad"):format(id), "Ana-Gallywix")
check(#GuildOS.db.lootHistory == 0 and not o3.done,
  "only the holder's word counts, and only for an award somebody entitled gave")
incoming(("D|%s|Bob-TolBarad|Chehul-TolBarad"):format(id), "Ana-Gallywix")
row = GuildOS.db.lootHistory[1]
check(o3.done and row and row.playerKey == "Bob-TolBarad" and row.awarded and row.from == "Ana-Gallywix" and row.itemId == 250003,
  "the holder's trade is recorded here too, as a new row when this client missed the drop")
check(o3.award.winner == "Bob-TolBarad" and o3.award.by == "Chehul-TolBarad", "the holder's award is the one recorded")
check(GuildOS.Points:Get("Bob-TolBarad") == pointsBefore - 20, "and the officer who gave it, I, charge the item's cost")
incoming(("D|%s|Bob-TolBarad|Chehul-TolBarad"):format(id), "Ana-Gallywix")
check(#GuildOS.db.lootHistory == 1 and GuildOS.Points:Get("Bob-TolBarad") == pointsBefore - 20, "once")

-- Another officer's award: believed; a member's withdrawal of someone else's offer: not.
local id4 = "65A1B2C30003"
incoming(("O|%s|0|0|%s"):format(id4, BAND), "Bob-TolBarad")
local o4 = TC:Get(id4)
check(o4.timeKnown == false and o4.expires == NOW + 7200, "an offer whose trade time was not read runs at most two hours")
local id7 = "65A1B2C30007"
incoming(("O|%s|0|0|%s"):format(id7, HELM), "Bob-TolBarad")
incoming(("A|%s|N|"):format(id4), "Ana-Gallywix")
incoming(("W|%s|Ana-Gallywix"):format(id4), "Off-TolBarad")
check(o4.award and o4.award.winner == "Ana-Gallywix" and o4.award.by == "Off-TolBarad", "another officer's award is believed")
incoming("X|" .. id7, "Ana-Gallywix")
check(not TC:Get(id7).closed, "a member withdraws nobody else's offer")
incoming("X|" .. id7, "Bob-TolBarad")
check(TC:Get(id7).closed, "its holder does")
-- This client read the trade time a minute short and closed the offer; the holder's trade still records.
o4.closed = true
GuildOS.db.lootHistory = {}
incoming(("D|%s|Ana-Gallywix|Off-TolBarad"):format(id4), "Bob-TolBarad")
check(#GuildOS.db.lootHistory == 1 and o4.done and GuildOS.Points:Get("Ana-Gallywix") == 50,
  "a trade another officer awarded is recorded here, even on an offer closed here, and charged by that officer, not here")
-- Time runs out.
local id5 = "65A1B2C30004"
incoming(("O|%s|1|600|%s"):format(id5, CAPE), "Bob-TolBarad")
NOW = NOW + 661
local open = {}
for _, x in ipairs(TC:OpenOffers()) do open[x.id] = true end
check(not open[id5] and TC:Get(id5).closed, "an offer whose trade window closed is over")

-- ── 7. Midnight's lockdown holds what is sent ─────────────────────────
resetBags()
GuildOS.db.settings.lootSystem = nil
lockdown = true
local n = #addon
local o6 = TC:Offer(HELM)
check(o6 and #addon == n, "in a lockdown the offer is held, not lost")
lockdown = false
C.FlushHeldMessages()
check(#addon == n + 1 and addon[#addon].text:find("^O|" .. o6.id), "and goes out when it lifts")
incoming(("A|%s|N|"):format(o6.id), "Ana-Gallywix")
lockdown = true
local nc = #chat
printed = {}
TC:Award(o6.id, "Ana-Gallywix")
check(#chat == nc and said("goes to Ana-Gallywix"), "an announcement in a lockdown is printed instead of sent")
lockdown = false
C.FlushHeldMessages()

-- ── 8. The verb and the help ──────────────────────────────────────────
local offered
local realOffer = TC.Offer
TC.Offer = function(_, l) offered = l end
SlashCmdList.GUILDOS("offer " .. HELM)
check(offered == HELM, "/gos offer <item> offers it, its link as typed")
GuildShow = "none"
SlashCmdList.GUILDOS("offer")
check(GuildShow == nil, "/gos offer alone opens the loot council")
TC.Offer = realOffer
printed = {}
SlashCmdList.GUILDOS("help")
check(said("/gos offer [item]"), "the help lists it on retail")

-- ── 9. Forever: no such thing ─────────────────────────────────────────
load(false)
check(GuildOS.TradeCouncil == nil, "the loot council does not exist on Forever")
check(GuildOS:StartModule({ "TradeCouncil" }) == false, "and is skipped at start-up")
printed = {}
check(pcall(SlashCmdList.GUILDOS, "offer") and said("Not available on this client."), "/gos offer says it is not here")
printed = {}
SlashCmdList.GUILDOS("help")
check(not said("/gos offer"), "and the help does not list it")

print(("retail-loot-council: %d checks passed"):format(checks))
