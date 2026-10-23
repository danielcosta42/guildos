-- The loot council by trade on retail (issue #185), run against the real Core, Compat, Utils,
-- LootTracker, Points, WishlistSystem, TradeCouncil and the slash router, under a stubbed retail client
-- on Tol Barad (bags, tooltip data, the trade window, /roll, addon and chat messages) and a stubbed
-- Forever one.
--
-- Retail has no Master Loot. A guildmate who received a personal item that can still be traded offers
-- it to the raid; the raid's guildmates answer Need, Greed or Pass with what they wear in that slot, and
-- a Need or Greed rolls the server's /roll, bound to the answer when it is seen just after it; an
-- officer, or the holder under the guild's free roll, awards it; and when the holder trades it to the
-- winner the award goes into the loot history (the drop's row becomes the winner's, stamped with the
-- drop's time on every client) and, where the guild runs DKP, the officer who gave it charges it. A
-- holder's word alone (D) records nothing: only an award this client saw given, to somebody who asked
-- for it and is in the guild. A trade of an offered item to anyone else records nothing and says so.
-- The trade window of a personal item is only on its tooltip, a TradeTimeRemaining line read with the
-- client's own duration strings. Only a guildmate's message over RAID is read, a link only when it is
-- one item link; a secret one is never touched; a lockdown holds what is sent until it lifts.
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
local SECRET_STRS = {}   -- strings the client keeps secret: a string, as a secret chat payload is
local printed, frames, addon, chat, rolls = {}, {}, {}, {}, {}
local lockdown, inRaid = false, true
-- The guild across connected realms; rank 1 is an officer. I am Chehul, an officer.
local ROSTER = { { "Chehul-TolBarad", 1 }, { "Ana-Gallywix", 4 }, { "Bob-TolBarad", 4 }, { "Off-TolBarad", 1 },
  { "Cid-TolBarad", 4 } }
local function leave(key) for i, r in ipairs(ROSTER) do if r[1] == key then table.remove(ROSTER, i) return end end end
local function link(id, name, q) return ("|cnIQ%d:|Hitem:%d::::::::90:::::|h[%s]|h|r"):format(q or 4, id, name) end
local HELM, BAND, RING1, RING2, CAPE = link(250001, "Voidforged Helm"), link(250002, "Dreamrift Band"),
  link(240011, "Old Band", 4), link(240012, "Older Band", 4), link(250003, "Gloomweave Cloak")
-- A crafted item, its quality an atlas inside the name, as retail links it.
local CRAFTED = "|cnIQ4:|Hitem:240020::::::::90:::::|h[Crafted Band |A:Professions-ChatIcon-Quality-Tier3:17:15::1|a]|h|r"
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
  printed, frames, addon, chat, rolls = {}, {}, {}, {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  function issecretvalue(v) return rawequal(v, SECRET) or (type(v) == "string" and SECRET_STRS[v] == true) end
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
  function RandomRoll(low, high) rolls[#rolls + 1] = { low, high } end
  RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
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
-- The server's /roll line, as everybody in the raid sees it.
local function rolled(name, n, low, high)
  fire("CHAT_MSG_SYSTEM", RANDOM_ROLL_RESULT:format(name, n, low or 1, high or 100))
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
check(GuildOS:DisplayKey("Bob-TolBarad") == "Bob" and GuildOS:DisplayKey("Ana-Gallywix") == "Ana-Gallywix",
  "a guildmate on my realm reads by name, one on a connected realm with it")

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
-- The helm dropped for me ten minutes ago: its row in my history carries the drop's time.
local DROP = NOW - 600
GuildOS.db.lootHistory = { { itemLink = HELM, itemId = 250001, player = "Chehul-TolBarad", playerKey = "Chehul-TolBarad",
  timestamp = DROP, raid = "The Voidspire", encounterID = 3176, quality = 4 } }
local o = TC:Offer(HELM)
check(o and o.holder == "Chehul-TolBarad" and o.link == HELM and o.itemId == 250001 and o.free == true,
  "my helm is offered, as a free roll (the guild rolls)")
check(o.expires == NOW + 5400 + 60 and o.timeKnown, "until its trade window closes, a minute's slack for the whole minutes it is read in")
check(o.dropTs == DROP, "with the time it dropped")
local sent = lastAddon()
check(sent.prefix == "GuildOSTC" and sent.channel == "RAID" and sent.text == ("O|%s|1|5400|%d|%s"):format(o.id, DROP, HELM),
  "the offer goes to the raid: id, free, seconds, the drop's time, link")
check(GuildShow == o.id, "and the council opens on it")
printed = {}
check(TC:Offer(HELM) == o and said("You are already offering that item."), "an item is offered once")

-- ── 4. Answers, and the server's roll ─────────────────────────────────
incoming(("A|%s|N|%s"):format(o.id, RING1), "Ana-Gallywix")
rolled("Ana-Gallywix", 40)
incoming(("A|%s|G|"):format(o.id), "Bob")
rolled("Bob", 70)
incoming(("A|%s|N|"):format(o.id), "Stranger-Nemesis")
incoming(("A|%s|N|"):format(o.id), "Off-TolBarad", "GUILD")
incoming(("A|%s|N|"):format(o.id), SECRET)
incoming(SECRET, "Off-TolBarad")
local hidden = ("A|%s|N|  "):format(o.id)   -- a whole answer, but a secret string
SECRET_STRS[hidden] = true
incoming(hidden, "Off-TolBarad")
SECRET_STRS["Off-TolBarad"] = true
incoming(("A|%s|N|"):format(o.id), "Off-TolBarad")
SECRET_STRS["Off-TolBarad"] = nil
incoming(("A|%s|N|"):format(o.id), "Chehul-TolBarad")
check(o.answers["Ana-Gallywix"] and o.answers["Ana-Gallywix"].choice == "N" and o.answers["Ana-Gallywix"].equipped == RING1,
  "a guildmate on a connected realm answers, with what they wear")
check(o.answers["Ana-Gallywix"].roll == 40, "and the /roll seen just after the answer is its roll")
check(o.answers["Bob-TolBarad"] and o.answers["Bob-TolBarad"].choice == "G" and o.answers["Bob-TolBarad"].roll == 70,
  "a guildmate on my realm, named and rolled with it")
check(o.answers["Stranger-Nemesis"] == nil and o.answers["Off-TolBarad"] == nil and o.answers["Chehul-TolBarad"] == nil,
  "a stranger's answer, one not over RAID, a secret one (a table or a string) and my own echo are not read")
-- A roll seen before the answer is not its roll; nor one of another range; nor one after the wait.
rolled("Off", 99)
incoming(("A|%s|P|"):format(o.id), "Off-TolBarad")
rolled("Off", 98)
check(o.answers["Off-TolBarad"].choice == "P" and o.answers["Off-TolBarad"].roll == nil, "a Pass waits for no roll")
incoming(("A|%s|N|"):format(o.id), "Off-TolBarad")
rolled("Off", 77, 1, 50)
check(o.answers["Off-TolBarad"].roll == nil, "a roll before the answer, or of another range, is not the answer's")
rolled("Off", 5)
check(o.answers["Off-TolBarad"].roll == 5, "the next 1-100 roll after it is")
-- Fishing for a better roll: another /roll, or another answer, changes nothing.
rolled("Ana-Gallywix", 100)
incoming(("A|%s|G|"):format(o.id), "Ana-Gallywix")
incoming(("A|%s|N|"):format(o.id), "Ana-Gallywix")
rolled("Ana-Gallywix", 100)
check(o.answers["Ana-Gallywix"].choice == "N" and o.answers["Ana-Gallywix"].roll == 40,
  "a player's later /roll, or a changed answer, never rolls again")
-- An answer whose roll is not seen in time ranks after those with one.
incoming(("A|%s|N|"):format(o.id), "Cid-TolBarad")
NOW = NOW + 11
rolled("Cid", 100)
NOW = NOW - 11
check(o.answers["Cid-TolBarad"].roll == nil, "a roll seen after the wait is not bound")
local rows = TC:Ranked(o)
local order = {}
for i, r in ipairs(rows) do order[i] = r.key end
check(table.concat(order, " ") == "Ana-Gallywix Off-TolBarad Cid-TolBarad Bob-TolBarad",
  "Need before Greed; within Need the higher roll first, and an answer with no roll seen last: " .. table.concat(order, " "))
-- The guild's system first, then the roll.
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
check(rows[1].key == "Bob-TolBarad" and rows[1].roll == 70, "in a free roll, the higher roll first (Bob's roll kept from his Greed)")

-- ── 5. Awarding, and the trade ────────────────────────────────────────
GuildOS.db.settings.lootSystem = nil
TC:Award(o.id, "Stranger-Nemesis")
incoming(("A|%s|P|"):format(o.id), "Off-TolBarad")
TC:Award(o.id, "Off-TolBarad")
check(o.award == nil, "nobody who did not ask for it, and never a Pass, is awarded")
local realIsOfficer = GuildOS.IsOfficer
GuildOS.IsOfficer = function() return false end
TC:Award(o.id, "Ana-Gallywix")
check(o.award and o.award.winner == "Ana-Gallywix" and o.award.by == "Chehul-TolBarad",
  "the holder of a free roll awards it, officer or not")
check(lastAddon().text == ("W|%s|Ana-Gallywix"):format(o.id), "the award goes to the raid")
check(chat[#chat].channel == "RAID" and chat[#chat].text:find("Ana-Gallywix", 1, true), "and the winner is announced")
GuildOS.IsOfficer = realIsOfficer
-- The trade: the winner's realm read from the trade window; my helm in it; "Trade complete."
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
  and row.awarded and row.from == "Chehul-TolBarad" and row.raid == "The Voidspire" and row.timestamp == DROP,
  "the award is recorded: my row of that drop becomes the winner's, at the drop's time")
check(o.done and o.closed and lastAddon().text == ("D|%s|Ana-Gallywix|Chehul-TolBarad"):format(o.id),
  "however long the winner took, and the raid hears it went through: winner and who awarded it")
check(GuildOS.Wishlist:IsItemDelivered(250001) == false, "the item is the winner's now, not mine")

-- Awarded to Ana, traded to Bob: nothing recorded, and it says so.
local o2 = TC:Offer(BAND)
check(o2.dropTs == NOW, "an item with no drop of mine in the history is stamped when offered")
incoming(("A|%s|N|"):format(o2.id), "Ana-Gallywix")
incoming(("A|%s|N|"):format(o2.id), "Bob-TolBarad")
TC:Award(o2.id, "Ana-Gallywix")
npc, tradeSlots = { "Bob" }, {}
fire("TRADE_SHOW")
tradeSlots = { BAND }
fire("TRADE_ACCEPT_UPDATE", 1, 1)
printed = {}
local before = #GuildOS.db.lootHistory
fire("UI_INFO_MESSAGE", 999, "Trade complete.")
check(#GuildOS.db.lootHistory == before and said("who was not awarded it: nothing was recorded."),
  "awarded to one and traded to another records nothing, and says so")
check(o2.closed and not o2.done and lastAddon().text == "X|" .. o2.id, "and the offer is over for the raid too")
-- A second "Trade complete." with no trade window opened since is nothing.
fire("UI_INFO_MESSAGE", 999, "Trade complete.")
check(#GuildOS.db.lootHistory == before, "a second 'Trade complete.' with no trade open is nothing")

-- ── 6. Somebody else's offer: who is believed, what is recorded, who charges ─
GuildOS.db.settings.lootSystem = "dkp"
GuildOS.Points:GetDB().config.itemCost = 20
local ANA_DROP = NOW - 300
local id = "65A1B2C30001"
incoming(("O|%s|0|3600|%d|%s"):format(id, ANA_DROP, CAPE), "Ana-Gallywix")
local o3 = TC:Get(id)
check(o3 and o3.holder == "Ana-Gallywix" and not o3.free and o3.expires == NOW + 3600 + 60 and o3.dropTs == ANA_DROP,
  "a guildmate's offer arrives, with its drop's time")
check(GuildShow == id, "and the council opens on it")
incoming(("O|%s|1|60|%d|%s"):format(id, NOW, HELM), "Bob")
check(TC:Get(id).holder == "Ana-Gallywix" and TC:Get(id).link == CAPE, "nobody takes over an offer's id")
incoming(("O|%s|0|0|%d|%s"):format("65A1B2C30002", NOW, CAPE), "Stranger-Nemesis")
check(TC:Get("65A1B2C30002") == nil, "a stranger offers nothing to the guild")
local BAD = { "|Hitem:250003|h[Cloak]|h", CAPE .. "|Hitem:1|h", "x " .. CAPE, "|cff00ff00|Hitem:abc|h[x]|h|r",
  "|cnIQ4:|Hitem:1|h[a]|h|r|cffff0000|Hplayer:Officer-TolBarad|h[Officer]|h|r says: give Bob 500 DKP |Hitem:2|h[b]|h|r",
  "|cnIQ4:|Hitem:1|h[x|TInterface/Icons/INV_Misc_QuestionMark:2000:2000|t]|h|r",
  "|cnIQ4:|Hitem:1|h[x\n\n\n[Raid Warning] wipe]|h|r", "|cnIQ4:|Hitem:1|h[x\nRaid Warning: wipe]|h|r" }
for i, bad in ipairs(BAD) do
  incoming(("O|65A1B2C301%02d|0|0|%d|%s"):format(i, NOW, bad), "Bob-TolBarad")
  check(TC:Get(("65A1B2C301%02d"):format(i)) == nil, "an offer whose link is not one item link is not taken: " .. bad)
end
-- A holder's free roll is believed only where the guild's loot system is the free roll.
incoming(("O|%s|1|3600|%d|%s"):format("65A1B2C30020", NOW, CAPE), "Bob-TolBarad")
local greedy = TC:Get("65A1B2C30020")
check(greedy and not greedy.free, "under DKP a holder's offer is no free roll, whatever it says")
incoming(("A|%s|N|"):format(greedy.id), "Ana-Gallywix")
incoming(("W|%s|Ana-Gallywix"):format(greedy.id), "Bob-TolBarad")
check(greedy.award == nil, "so its holder cannot award it")
incoming(("A|%s|N|"):format(id), "Ana-Gallywix")
check(o3.answers["Ana-Gallywix"] == nil, "a holder does not answer their own offer")
local nRolls = #rolls
TC:Answer(id, "N")
check(lastAddon().text == ("A|%s|N|"):format(id) and o3.answers["Chehul-TolBarad"].choice == "N",
  "I answer Need, with no cloak worn to replace")
check(#rolls == nRolls + 1 and rolls[#rolls][1] == 1 and rolls[#rolls][2] == 100, "and roll the server's /roll 1-100")
rolled("Chehul", 63)
check(o3.answers["Chehul-TolBarad"].roll == 63, "which every client, mine too, binds to my answer")
TC:Answer(id, "G")
TC:Answer(id, "P")
TC:Answer(id, "N")
check(#rolls == nRolls + 1 and o3.answers["Chehul-TolBarad"].roll == 63, "changing my answer never rolls again")
incoming(("A|%s|P|"):format(id), "Chehul-TolBarad")
check(o3.answers["Chehul-TolBarad"].choice == "N", "an echo of my own answer changes nothing")
incoming(("A|%s|G|%s"):format(id, "|Hitem:1|h"), "Bob-TolBarad")
check(o3.answers["Bob-TolBarad"].choice == "G" and o3.answers["Bob-TolBarad"].equipped == nil,
  "an answer's equipped item that is not one item link is left out")
incoming(("A|%s|N|%s"):format(id, CRAFTED), "Cid-TolBarad")
check(o3.answers["Cid-TolBarad"].equipped == CRAFTED, "a crafted item, its quality an atlas in its name, is one item link")
-- An award from somebody who may not give it, or to somebody who did not ask or left the guild.
incoming(("W|%s|Bob-TolBarad"):format(id), "Ana-Gallywix")
incoming(("W|%s|Bob-TolBarad"):format(id), "Bob-TolBarad")
incoming(("W|%s|Off-TolBarad"):format(id), "Off-TolBarad")
check(o3.award == nil, "neither the holder of a council offer nor a member awards it, nor anyone to who did not ask")
leave("Cid-TolBarad")
incoming(("W|%s|Cid-TolBarad"):format(id), "Off-TolBarad")
check(o3.award == nil, "nor to somebody no longer in the guild")
table.insert(ROSTER, { "Cid-TolBarad", 4 })
-- I, an officer, award it to Bob.
TC:Award(id, "Bob-TolBarad")
check(o3.award and o3.award.by == "Chehul-TolBarad" and lastAddon().text == ("W|%s|Bob-TolBarad"):format(id),
  "an officer awards it")
-- Another officer awards it to Cid at the same moment; then Cid leaves the guild.
incoming(("W|%s|Cid-TolBarad"):format(id), "Off-TolBarad")
check(o3.award.winner == "Cid-TolBarad" and o3.award.by == "Off-TolBarad", "the later award is the one this client shows")
leave("Cid-TolBarad")
-- My client saw Ana's drop a second after hers.
GuildOS.db.lootHistory = { { itemLink = CAPE, itemId = 250003, player = "Ana-Gallywix", playerKey = "Ana-Gallywix",
  timestamp = ANA_DROP + 1, raid = "The Voidspire", encounterID = 3176, quality = 3 } }
local pointsBefore = GuildOS.Points:Get("Bob-TolBarad")
incoming(("D|%s|Bob-TolBarad|Chehul-TolBarad"):format(id), "Off-TolBarad")
incoming(("D|%s|Bob-TolBarad|Bob-TolBarad"):format(id), "Ana-Gallywix")
incoming(("D|%s|Bob-TolBarad"):format(id), "Ana-Gallywix")
incoming(("D|%s|Bob-TolBarad|Off-TolBarad"):format(id), "Ana-Gallywix")
incoming(("D|%s|Cid-TolBarad|Off-TolBarad"):format(id), "Ana-Gallywix")
check(GuildOS.db.lootHistory[1].playerKey == "Ana-Gallywix" and not o3.done,
  "only the holder's word counts, for an award this client saw given, to a guildmate who asked")
table.insert(ROSTER, { "Cid-TolBarad", 4 })
incoming(("D|%s|Bob-TolBarad|Chehul-TolBarad"):format(id), "Ana-Gallywix")
row = GuildOS.db.lootHistory[1]
check(o3.done and #GuildOS.db.lootHistory == 1 and row.playerKey == "Bob-TolBarad" and row.awarded
  and row.from == "Ana-Gallywix" and row.timestamp == ANA_DROP,
  "the holder's trade of my award is recorded: the drop's row becomes Bob's, at the holder's drop time")
check(o3.award.winner == "Bob-TolBarad" and o3.award.by == "Chehul-TolBarad", "the holder's award is the one recorded")
check(GuildOS.Points:Get("Bob-TolBarad") == pointsBefore - 20, "and the officer who gave it, I, charge the item's cost")
incoming(("D|%s|Bob-TolBarad|Chehul-TolBarad"):format(id), "Ana-Gallywix")
check(#GuildOS.db.lootHistory == 1 and GuildOS.Points:Get("Bob-TolBarad") == pointsBefore - 20, "once")

-- The forge: an offer and a D, with no award given and no answer, charge nobody and write no row.
local anaBefore = GuildOS.Points:Get("Ana-Gallywix")
GuildOS.db.lootHistory = {}
for i = 1, 3 do
  incoming(("O|DEAD0%d|0|0|%d|%s"):format(i, NOW, CAPE), "Bob-TolBarad")
  incoming(("D|DEAD0%d|Ana-Gallywix|Chehul-TolBarad"):format(i), "Bob-TolBarad")
end
incoming(("A|DEAD01|N|"):format(), "Ana-Gallywix")
incoming("D|DEAD01|Ana-Gallywix|Chehul-TolBarad", "Bob-TolBarad")
incoming("D|DEAD01|Ana-Gallywix|Off-TolBarad", "Bob-TolBarad")
check(GuildOS.Points:Get("Ana-Gallywix") == anaBefore and #GuildOS.db.lootHistory == 0,
  "a forged D, answered or not, charges nobody and records nothing")
-- Under the free roll a holder's own D needs no W seen, but still somebody who asked for the item.
GuildOS.db.settings.lootSystem = nil
incoming(("O|FEE01|1|0|%d|%s"):format(NOW, CAPE), "Bob-TolBarad")
incoming("D|FEE01|Ana-Gallywix|Bob-TolBarad", "Bob-TolBarad")
check(not TC:Get("FEE01").done and #GuildOS.db.lootHistory == 0, "a free roll's D to somebody who never asked records nothing")
incoming("A|FEE01|N|", "Ana-Gallywix")
incoming("A|FEE01|P|", "Ana-Gallywix")
incoming("D|FEE01|Ana-Gallywix|Bob-TolBarad", "Bob-TolBarad")
check(not TC:Get("FEE01").done, "nor to somebody who asked and then passed")
incoming("A|FEE01|G|", "Ana-Gallywix")
incoming("D|FEE01|Ana-Gallywix|Bob-TolBarad", "Bob-TolBarad")
check(TC:Get("FEE01").done and #GuildOS.db.lootHistory == 1 and GuildOS.Points:Get("Ana-Gallywix") == anaBefore,
  "a free roll's holder's D to somebody who asked is recorded, and charges nothing")
GuildOS.db.lootHistory = {}
GuildOS.db.settings.lootSystem = "dkp"

-- Another officer's award: believed and recorded here, charged by that officer, not here.
local id4 = "65A1B2C30003"
incoming(("O|%s|0|0|%d|%s"):format(id4, NOW, BAND), "Bob-TolBarad")
local o4 = TC:Get(id4)
check(o4.timeKnown == false and o4.expires == NOW + 7200, "an offer whose trade time was not read runs at most two hours")
incoming(("A|%s|N|"):format(id4), "Ana-Gallywix")
incoming(("A|%s|N|"):format(id4), "Cid-TolBarad")
incoming(("W|%s|Ana-Gallywix"):format(id4), "Off-TolBarad")
check(o4.award and o4.award.winner == "Ana-Gallywix" and o4.award.by == "Off-TolBarad", "another officer's award is believed")
-- This client read the trade time a minute short and closed the offer; the holder's trade still records.
o4.closed = true
incoming(("W|%s|Cid-TolBarad"):format(id4), "Off-TolBarad")
check(o4.award.winner == "Ana-Gallywix", "a closed offer takes no more awards")
incoming(("D|%s|Ana-Gallywix|Off-TolBarad"):format(id4), "Bob-TolBarad")
check(#GuildOS.db.lootHistory == 1 and o4.done and GuildOS.Points:Get("Ana-Gallywix") == anaBefore,
  "a trade another officer awarded is recorded here, even on an offer closed here, and not charged here")
-- Withdrawals.
local id7 = "65A1B2C30007"
incoming(("O|%s|0|0|%d|%s"):format(id7, NOW, HELM), "Bob-TolBarad")
incoming("X|" .. id7, "Ana-Gallywix")
check(not TC:Get(id7).closed, "a member withdraws nobody else's offer")
incoming("X|" .. id7, "Bob-TolBarad")
check(TC:Get(id7).closed, "its holder does")
-- Time runs out.
local id5 = "65A1B2C30004"
incoming(("O|%s|1|600|%d|%s"):format(id5, NOW, CAPE), "Bob-TolBarad")
NOW = NOW + 661
local open = {}
for _, x in ipairs(TC:OpenOffers()) do open[x.id] = true end
check(not open[id5] and TC:Get(id5).closed, "an offer whose trade window closed is over")

-- ── 6b. An answer an award names stands; the roll follows the answer out; the holder's word on time ─
GuildOS.db.settings.lootSystem = "dkp"
GuildOS.db.lootHistory = {}
-- Ana asked, I awarded her; then she clicks Pass. Her answer stands, and Bob's trade records and charges.
incoming(("O|%s|0|0|%d|%s"):format("65A1B2C30030", NOW - 100, HELM), "Bob-TolBarad")
local o30 = TC:Get("65A1B2C30030")
incoming("A|65A1B2C30030|N|", "Ana-Gallywix")
TC:Award("65A1B2C30030", "Ana-Gallywix")
incoming("A|65A1B2C30030|P|", "Ana-Gallywix")
check(o30.answers["Ana-Gallywix"].choice == "N", "once an award names a player, their answer stands")
local anaPts = GuildOS.Points:Get("Ana-Gallywix")
incoming("D|65A1B2C30030|Ana-Gallywix|Chehul-TolBarad", "Bob-TolBarad")
check(o30.done and GuildOS.db.lootHistory[1] and GuildOS.db.lootHistory[1].playerKey == "Ana-Gallywix"
  and GuildOS.Points:Get("Ana-Gallywix") == anaPts - 20, "so the trade of her award still records, and is charged")
-- Awarded to me by another officer: my own Pass is refused, and says why.
incoming(("O|%s|0|0|%d|%s"):format("65A1B2C30031", NOW - 100, CAPE), "Bob-TolBarad")
TC:Answer("65A1B2C30031", "N")
incoming("W|65A1B2C30031|Chehul-TolBarad", "Off-TolBarad")
local sentBefore = #addon
printed = {}
TC:Answer("65A1B2C30031", "P")
check(TC:Get("65A1B2C30031").answers["Chehul-TolBarad"].choice == "N" and #addon == sentBefore
  and said("The item was awarded to you"), "my answer stands once I am awarded, and I am told so")
-- A holder naming themselves as the giver on a council offer is believed by nobody.
incoming(("O|%s|0|0|%d|%s"):format("65A1B2C30032", NOW - 100, CAPE), "Bob-TolBarad")
incoming("A|65A1B2C30032|N|", "Ana-Gallywix")
incoming("D|65A1B2C30032|Ana-Gallywix|Bob-TolBarad", "Bob-TolBarad")
check(not TC:Get("65A1B2C30032").done, "a council offer's holder cannot give the award themselves")
-- The holder's drop time is believed only inside the trade window it could have come from.
for i, drop in ipairs({ 0, NOW + 3600, 99999999999, NOW - 7200 - 61 }) do
  incoming(("O|65A1B2C3004%d|0|0|%d|%s"):format(i, drop, CAPE), "Bob-TolBarad")
  check(TC:Get(("65A1B2C3004%d"):format(i)).dropTs == NOW, "a drop time outside the window is the offer's: " .. drop)
end
incoming(("O|65A1B2C30045|0|0|%d|%s"):format(NOW - 7200, CAPE), "Bob-TolBarad")
check(TC:Get("65A1B2C30045").dropTs == NOW - 7200, "one inside it is kept")
-- One item link: the colour a link's own, the quality atlas at a chat icon's size, no escapes.
local LINKS = {
  { false, "|cnIQ4:|Hitem:1|h[x |A:Professions-ChatIcon-Quality-Tier3:2000:2000::1|a]|h|r" },
  { false, "|cFAKE TEXT BEFORE THE LINK |Hitem:1|h[x]|h|r" },
  { false, "|cnIQ4:|Hitem:1|h[a||b]|h|r" },
  { false, "|cnIQ4:|Hitem:1|h[a|nb]|h|r" },
  { false, "|cnIQ4:|Hitem:1|h[x |A:SomeHugeArt:17:15::1|a]|h|r" },
  { true, "|cffa335ee|Hitem:250001::::::::90:::::|h[Voidforged Helm]|h|r" },
  { true, CRAFTED },
}
for i, case in ipairs(LINKS) do
  local oid = ("65A1B2C3005%d"):format(i)
  incoming(("O|%s|0|0|%d|%s"):format(oid, NOW, case[2]), "Bob-TolBarad")
  check((TC:Get(oid) ~= nil) == case[1], (case[1] and "an item link is taken: " or "not one item link: ") .. case[2])
end
-- The earliest answer still waiting takes a player's roll; a secret roll line is nobody's.
incoming(("O|%s|0|0|%d|%s"):format("65A1B2C30060", NOW, CAPE), "Bob-TolBarad")
incoming(("O|%s|0|0|%d|%s"):format("65A1B2C30061", NOW, HELM), "Bob-TolBarad")
incoming("A|65A1B2C30060|N|", "Cid-TolBarad")
incoming("A|65A1B2C30061|N|", "Cid-TolBarad")
local secretLine = RANDOM_ROLL_RESULT:format("Cid", 50, 1, 100)
SECRET_STRS[secretLine] = true
fire("CHAT_MSG_SYSTEM", secretLine)
SECRET_STRS[secretLine] = nil
check(TC:Get("65A1B2C30060").answers["Cid-TolBarad"].roll == nil, "a roll line the client keeps secret is nobody's")
rolled("Cid", 11)
rolled("Cid", 22)
check(TC:Get("65A1B2C30060").answers["Cid-TolBarad"].roll == 11 and TC:Get("65A1B2C30061").answers["Cid-TolBarad"].roll == 22,
  "one player's rolls go to their waiting answers in the order they answered")
-- My roll waits for my answer to go out: held behind what a lockdown kept, it rolls when that is sent.
incoming(("O|%s|0|0|%d|%s"):format("65A1B2C30070", NOW, CAPE), "Bob-TolBarad")
lockdown = true
C.SendAddonMessage("GuildOS", "some sync", "GUILD")
lockdown = false
local nr, na = #rolls, #addon
TC:Answer("65A1B2C30070", "N")
check(#rolls == nr and #addon == na, "an answer held behind another message has not gone out, and has not rolled")
C.FlushHeldMessages()
check(addon[#addon].text == "A|65A1B2C30070|N|" and #rolls == nr + 1, "once it goes out, the roll follows it")

-- ── 7. Midnight's lockdown holds what is sent, and an answer waits for it ─
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
local id8 = "65A1B2C30008"
incoming(("O|%s|0|0|%d|%s"):format(id8, NOW, CAPE), "Bob-TolBarad")
nRolls = #rolls
printed = {}
TC:Answer(id8, "N")
check(TC:Get(id8).answers["Chehul-TolBarad"] == nil and #rolls == nRolls and said("Chat is locked"),
  "in a lockdown no answer goes and no roll is made, and it says so")
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
