-- Craft orders (issue #389), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua and
-- Modules/CraftOrders.lua.
--
-- An order belongs to its sender; it is open to every crafter until one accepts, and when two accept
-- at once every client keeps the same one; an order sent to one crafter is only theirs to take or
-- decline; only the crafter gives it back or finishes it, only the author cancels; what arrives is
-- cleaned and clamped; a login's question is answered once; a finished trade and a sent mail move
-- the order on; the materials are put in whole stacks and one split.
--
--   luajit -e 'ADDON="."' tools/craft-orders.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent = {}
RAID_CLASS_COLORS = {}
local function widget()
  local w = { scripts = {} }
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    return function() end
  end })
end
function CreateFrame() return widget() end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
PLAYER = "Ana"
function UnitName() return PLAYER end
function UnitClass() return "Warrior", "WARRIOR" end
local NOW, CLOCK = 1790000000, 1000
function GetServerTime() return NOW end
function GetTime() return CLOCK end
time = function() return NOW end
date = os.date
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function() end, NewTicker = function() end }
function GetNumGuildMembers() return 0 end
function IsInGuild() return true end
function GetLocale() return "enUS" end
local ITEMS = { [100] = "Bracers", [1] = "Copper Bar", [2] = "Coarse Thread" }
function GetItemInfo(id) id = tonumber(tostring(id):match("(%d+)")); local n = ITEMS[id]; return n, n and ("item:" .. id) end

-- The bags: { [bag] = { [slot] = { id, count, locked } } }, with the cursor and the slots it fills.
local BAGS, cursor, dropped = {}, nil, {}
function GetContainerNumSlots(bag) return BAGS[bag] and 16 or 0 end
function GetContainerItemInfo(bag, slot)
  local s = BAGS[bag] and BAGS[bag][slot]
  if not s then return nil end
  return nil, s.c, s.locked, 1, nil, nil, "item:" .. s.id, nil, nil, s.id
end
function PickupContainerItem(bag, slot)
  local s = BAGS[bag][slot]
  cursor = { id = s.id, c = s.c }
  s.locked = true
end
function SplitContainerItem(bag, slot, n)
  local s = BAGS[bag][slot]
  check(n >= 1 and n < s.c, "a split takes less than the stack")
  cursor = { id = s.id, c = n }
  s.locked = true
end
function CursorHasItem() return cursor ~= nil end
function ClearCursor() cursor = nil end
function GetItemCount(id)
  local n = 0
  for _, bag in pairs(BAGS) do for _, s in pairs(bag) do if s.id == id then n = n + s.c end end end
  return n
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")

local timers = {}
GuildOS.Compat.After = function(d, fn) timers[#timers + 1] = { at = CLOCK + (d or 0), fn = fn } end
local function runTimers()
  while #timers > 0 do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = table.remove(timers, 1)
    if t.at > CLOCK then CLOCK = t.at end
    t.fn()
  end
end
local wire = {}
GuildOS.SyncService = {
  handlers = {},
  On = function(self, d, fn) self.handlers[d] = fn end,
  Publish = function(_, d, act, data) wire[#wire + 1] = { d = d, act = act, data = data } end,
}
local printed = {}
GuildOS.Print = function(_, msg) printed[#printed + 1] = msg end
-- Who crafts what: item 100 by Cid and Dan, and by me when CRAFTS_ME.
local CRAFTS_ME = false
GuildOS.RecipeTracker = {
  GetCraftersForItem = function(_, item)
    if item ~= 100 then return nil end
    local out = { { playerKey = GuildOS:GetPlayerKey("Cid", "Realm"), playerName = "Cid" },
                  { playerKey = GuildOS:GetPlayerKey("Dan", "Realm"), playerName = "Dan" } }
    if CRAFTS_ME then out[#out + 1] = { playerKey = GuildOS:GetPlayerKey("Ana", "Realm"), playerName = "Ana" } end
    return out
  end,
  LocalCrafts = function() return nil end,
}

dofile(ADDON .. "/Modules/CraftOrders.lua")
local O = GuildOS.CraftOrders
local K = O.KeyOf
local ANA, BEA, CID, DAN = K("Ana"), K("Bea"), K("Cid"), K("Dan")
check(ANA and ANA ~= BEA, "member keys")
check(O:MyKey() == ANA, "my key is the player's")

local function fresh()
  GuildOS.db = { settings = {}, members = {}, craftReagents = { [100] = { 1, 2, 2, 1 } } }
  wire, printed, timers = {}, {}, {}
  CRAFTS_ME = false
  O:ForgetCrafters()
  O.answeredAt, O.answerPending = nil, nil
  O:Initialize()
  timers = {}   -- the login's ask is checked on its own below
end
local function last(act)
  for i = #wire, 1, -1 do if wire[i].act == act then return wire[i] end end
end
local function from(sender, act, data)
  GuildOS.SyncService.handlers.craftorder({ act = act, data = data }, sender)
end

-- ── Placing ─────────────────────────────────────────────────────────────
fresh()
local o = O:Place(100, { n = 2, tip = 15000, note = "for| the raid", mode = "mats" })
check(o and o.st == "open" and o.who == ANA and o.n == 2 and o.tip == 15000, "an order is placed, open, mine")
check(o.note == "for the raid", "a note loses its pipes")
check(o.rg and o.rg[1] == 1 and o.rg[2] == 2, "the reagents this client knows go with it")
check(last("new") and last("new").data.id == o.id, "and it is sent")
check(#O:Rows("mine") == 1 and #O:Rows("open") == 0, "it is in My orders, not in the open ones (it is mine)")
for _ = 2, O.OPEN_PER do check(O:Place(100, {}), "up to five open") end
local none, why = O:Place(100, {})
check(none == nil and why, "a sixth is refused, and says why")
check(O:Place(0, {}) == nil and O:Place("x", {}) == nil, "no item, no order")
fresh()
local big = O:Place(100, { n = 25, tip = 2e12 })
check(big.n == O.MAX_N and big.tip == O.TIP_MAX, "too many items or too big a tip is clamped, not dropped")
GuildOS.db.craftYield = { [100] = 5 }
check(O:Yield(100) == 5 and O:Crafts({ item = 100, n = 12 }) == 3, "a craft that makes five: twelve take three crafts")
check(O:Needs({ item = 100, n = 12 })[1].need == 6, "and the materials of three crafts")
check(O:Yield(100, { y = 2 }) == 2, "the crafter's own yield first")

-- ── What arrives ────────────────────────────────────────────────────────
fresh()
from("Bea", "new", { id = "B1", who = "Ana", item = 100, n = 3, st = "done", cr = "Cid", ts = NOW })
local b1 = O:Get("B1")
check(b1 and b1.who == BEA, "the author is the sender, never what the order says")
check(b1.st == "open" and b1.cr == nil, "and it starts open, whatever it claims")
from("Bea", "new", { id = "B2", item = 100, n = 99 })
check(O:Get("B2") == nil, "more than twenty items: refused")
from("Bea", "new", { id = "B3", item = 100, n = 1, tip = -5 })
check(O:Get("B3") == nil, "a negative tip: refused")
from("Bea", "new", { id = "B4", item = 100, n = 1, ts = NOW + 99999 })
check(O:Get("B4").ts <= NOW + O.FUTURE, "a time from the future is clamped")
from("Bea", "new", { id = "B1", item = 100, n = 1 })
check(O:Get("B1").n == 3, "a known id is not replaced")

-- The inbox: an open order I cannot craft is not mine to see.
check(#O:Rows("open") == 0 and O:InboxCount() == 0, "nothing for me while I know no recipe for it")
check(#printed == 0, "and nothing said")
CRAFTS_ME = true; O:ForgetCrafters()
from("Bea", "new", { id = "B5", item = 100, n = 1 })
check(#printed == 1 and printed[1]:find("asks the guild's crafters"), "a new order I can craft is said once")
check(#O:Rows("open") == 3 and O:InboxCount() == 3, "and every open order for it waits for me")

-- ── Accepting ───────────────────────────────────────────────────────────
fresh()
from("Bea", "new", { id = "X", item = 100, n = 1, ts = NOW - 100 })
check(O:Apply("acc", { id = "X", at = NOW - 200 }, CID) == nil, "no acceptance from before the order")
check(O:Apply("acc", { id = "X", at = NOW }, BEA) == nil, "the author does not accept their own order")
check(O:Apply("acc", { id = "X", at = NOW, rg = { 1, 3 } }, CID), "a crafter accepts")
check(O:Get("X").st == "accepted" and O:Get("X").cr == CID, "and holds it")
check(O:Apply("acc", { id = "X", at = NOW + 5 }, DAN) == nil, "a later acceptance loses")
check(O:Apply("acc", { id = "X", at = NOW - 5 }, DAN) and O:Get("X").cr == DAN, "an earlier one wins: every client keeps the same")
check(O:Apply("acc", { id = "X", at = NOW - 5 }, CID) and O:Get("X").cr == CID, "at the same time, the lower name")
check(O.Wins(1, "b", 1, "a") == false and O.Wins(1, "a", 2, "a") == true, "the tie rule")
check(O:Apply("acc", { id = "X", at = NOW - 30 }, DAN) and O:Get("X").cr == DAN, "an earlier one within a minute still wins")
check(O:Apply("acc", { id = "X", at = NOW - 30 - O.TAKEOVER - 1 }, CID) == nil,
      "but not one far earlier: that is a takeover, not two at once")
O:Apply("mats", { id = "X" }, BEA)
check(O:Apply("acc", { id = "X", at = NOW - 31 }, CID) == nil and O:Get("X").cr == DAN,
      "once the materials went to a crafter, nobody takes the order from them")

-- Messages in any order end the same: an acceptance from before a release does not take it again.
fresh()
from("Bea", "new", { id = "R", item = 100, n = 1, ts = NOW - 100 })
O:Apply("acc", { id = "R", at = NOW - 90 }, CID)
O:Apply("rel", { id = "R", at = NOW - 88 }, CID)
check(O:Apply("acc", { id = "R", at = NOW - 89 }, DAN) == nil and O:Get("R").st == "open",
      "Dan's acceptance from before Cid gave it back arrives late: the order stays open")
check(O:Apply("acc", { id = "R", at = NOW - 80 }, DAN) and O:Get("R").cr == DAN, "a new one takes it")

-- The crafter who lost a tie hears it.
fresh()
CRAFTS_ME = true; O:ForgetCrafters()
from("Bea", "new", { id = "TIE", item = 100, n = 1, ts = NOW - 100 })
check(O:Act("TIE", "accept"), "I accept")
printed = {}
from("Dan", "acc", { id = "TIE", at = NOW - 50 })
check(O:Get("TIE").cr == DAN and printed[1] and printed[1]:find("same moment"), "Dan was first: I am told he keeps it")

-- ── Sent to one crafter ─────────────────────────────────────────────────
fresh()
from("Bea", "new", { id = "T", item = 100, n = 1, to = "Cid" })
check(O:Get("T").to == CID, "sent to Cid")
check(O:Apply("acc", { id = "T" }, DAN) == nil, "nobody else may take it")
check(O:Apply("dec", { id = "T" }, DAN) == nil, "nor decline it")
check(O:Apply("dec", { id = "T" }, CID) and O:Get("T").to == nil and O:Get("T").st == "open", "Cid declines: open to everyone")
check(O:Apply("acc", { id = "T" }, DAN), "and now Dan may take it")
from("Bea", "new", { id = "T2", item = 100, n = 1, to = "Ana" })
check(#O:Rows("forme") == 1 and O:Rows("forme")[1].id == "T2", "an order sent to me is For me")
check(printed[#printed]:find("asks you to craft"), "and says it was sent to me")
from("Bea", "new", { id = "T3", item = 100, n = 1, to = "Bea" })
check(O:Get("T3").to == nil, "sent to its own author: to nobody")

-- ── Giving back, materials, done, cancel ────────────────────────────────
fresh()
from("Bea", "new", { id = "M", item = 100, n = 1, mode = "mats" })
O:Apply("acc", { id = "M" }, CID)
check(O:Apply("rel", { id = "M" }, DAN) == nil, "only the crafter gives it back")
check(O:Apply("mats", { id = "M" }, DAN) == nil, "a stranger does not mark the materials")
check(O:Apply("mats", { id = "M" }, BEA) and O:Get("M").st == "mats", "the author marks them")
check(O:Apply("done", { id = "M" }, DAN) == nil, "a stranger does not finish it")
check(O:Apply("can", { id = "M" }, CID) == nil, "the crafter does not cancel it")
check(O:Apply("rel", { id = "M" }, CID) and O:Get("M").st == "open" and O:Get("M").cr == nil, "the crafter gives it back: open")
O:Apply("acc", { id = "M" }, DAN)
check(O:Apply("done", { id = "M" }, DAN) and O:Get("M").st == "done", "the crafter finishes it")
check(O:Apply("can", { id = "M" }, BEA) == nil, "a finished order is not cancelled")
from("Bea", "new", { id = "OWN", item = 100, n = 1, mode = "own" })
O:Apply("acc", { id = "OWN" }, CID)
check(O:Apply("mats", { id = "OWN" }, BEA) == nil, "no materials step when the crafter uses their own")
check(O:Apply("can", { id = "OWN" }, BEA) and O:Get("OWN").st == "cancelled", "the author cancels")
check(O:Apply("acc", { id = "OWN" }, DAN) == nil, "a cancelled order is not taken")
check(O:Apply("zzz", { id = "OWN" }, BEA) == nil and O:Apply("acc", { id = "nope" }, CID) == nil, "unknown acts and ids do nothing")

-- ── The author hears ────────────────────────────────────────────────────
fresh()
local mine = O:Place(100, {})
printed = {}
from("Cid", "acc", { id = mine.id, at = NOW })
check(printed[1] and printed[1]:find("accepted your order"), "my order accepted: said")
from("Cid", "done", { id = mine.id })
check(printed[2] and printed[2]:find("finished your order"), "finished: said")
from("Cid", "can", { id = mine.id })
check(#printed == 2, "a cancel from someone else does nothing")

-- ── Expiry and pruning ──────────────────────────────────────────────────
fresh()
from("Bea", "new", { id = "OLD", item = 100, n = 1, ts = NOW - 8 * 86400 })
check(O.StateOf(O:Get("OLD")) == "expired", "open a week and more: expired")
check(O:Apply("acc", { id = "OLD" }, CID) == nil, "an expired order is not taken")
check(O:Place(100, {}) and #O:Rows("open") == 0, "nor listed as open")
GuildOS.db.craftOrders.GONE = { id = "GONE", who = BEA, item = 100, n = 1, st = "done", ts = NOW - 30 * 86400, at = NOW - 20 * 86400 }
O:Prune()
check(O:Get("GONE") == nil, "a closed order goes after two weeks")
check(O:Get("OLD") ~= nil, "an expired one stays until two weeks after its last change")
GuildOS.db.craftOrders.OLD.at = NOW - 15 * 86400
O:Prune()
check(O:Get("OLD") == nil, "and then goes")

-- ── A login asks; one answers ───────────────────────────────────────────
fresh()
O:Place(100, {})
wire = {}
from("Eva", "ask", {})
from("Fay", "ask", {})
runTimers()
local haves = 0
for _, m in ipairs(wire) do if m.act == "have" then haves = haves + 1 end end
check(haves == 1, "two asks, one answer")
wire = {}
from("Gil", "ask", {})
runTimers()
check(last("have") == nil, "not twice in two minutes")
NOW = NOW + O.ANSWER_EVERY + 1
from("Bea", "new", { id = "NOTMINE", item = 100, n = 1 })
from("Hal", "ask", {})
runTimers()
local answer = last("have")
check(answer and #answer.data.l == 1 and answer.data.l[1].who == ANA, "I answer only for my own orders")

fresh()
from("Bea", "have", { l = { { id = "H1", who = "Bea", item = 100, n = 2, st = "accepted", cr = "Cid", ts = NOW, at = NOW },
                            { id = "H2", who = "Bea", item = 100, n = 999 } } })
check(O:Get("H1") and O:Get("H1").cr == CID and O:Get("H1").who == BEA, "an answer brings the orders I missed")
check(O:Get("H2") == nil, "a bad one in it is dropped")
from("Eve", "have", { l = { { id = "H1", who = "Eve", item = 100, n = 2, st = "cancelled", ts = NOW, at = NOW + 10 } } })
check(O:Get("H1").st == "accepted", "another author for a known order is not taken")
from("Cid", "have", { l = { { id = "H1", who = "Bea", item = 100, n = 2, st = "done", cr = "Cid", ts = NOW, at = NOW + 10 } } })
check(O:Get("H1").st == "done", "a newer state of a known order is")

-- An answer is a hint: it cannot cancel, revive, reassign, or speak for me.
fresh()
from("Bea", "new", { id = "F1", item = 100, n = 1 })
from("Dan", "have", { l = { { id = "F1", who = "Bea", item = 100, n = 1, st = "cancelled", ts = NOW, at = NOW + 60 } } })
check(O:Get("F1").st == "open", "an answer does not cancel an order")
O:Apply("acc", { id = "F1", at = NOW }, CID)
from("Dan", "have", { l = { { id = "F1", who = "Bea", item = 100, n = 1, st = "mats", cr = "Dan", ts = NOW, at = NOW + 60 } } })
check(O:Get("F1").cr == CID and O:Get("F1").st == "accepted", "nor hand it to another crafter")
O:Apply("can", { id = "F1" }, BEA)
from("Dan", "have", { l = { { id = "F1", who = "Bea", item = 100, n = 1, st = "accepted", cr = "Dan", ts = NOW, at = NOW + 60 } } })
check(O:Get("F1").st == "cancelled", "nor bring a cancelled one back")
from("Dan", "have", { l = { { id = "F2", who = "Ana", item = 100, n = 1, ts = NOW, at = NOW } } })
check(O:Get("F2") == nil, "nor put an order in my name")
from("Dan", "have", { l = { { id = "F3", who = "Bea", item = 100, n = 1, st = "cancelled", ts = NOW, at = NOW } } })
check(O:Get("F3") == nil, "a closed order I never knew is not kept")
local flood = {}
for i = 1, 8 do flood[i] = { id = "FL" .. i, who = "Eve", item = 100, n = 1, ts = NOW, at = NOW } end
from("Eve", "have", { l = flood })
local eve = 0
for _, x in pairs(GuildOS.db.craftOrders) do if x.who == K("Eve") then eve = eve + 1 end end
check(eve == O.OPEN_PER, "nor more open orders for one author than the cap")
local myOrder = O:Place(100, {})
from("Dan", "have", { l = { { id = myOrder.id, who = "Ana", item = 100, n = 1, st = "accepted", cr = "Dan", ts = NOW, at = NOW + 60 } } })
check(O:Get(myOrder.id).st == "open", "and my own orders come to me live, never from an answer")
from("Bea", "new", { id = "F4", item = 100, n = 1 })
from("Eve", "have", { l = { { id = "F4", who = "Bea", item = 100, n = 1, st = "done", cr = "Dan", ts = NOW, at = NOW + 60 } } })
check(O:Get("F4").st == "open", "an answer speaks only for its sender's orders: Eve cannot close Bea's")
from("Dan", "have", { l = { { id = "F5", who = "Bea", item = 100, n = 1, ts = NOW, at = NOW } } })
check(O:Get("F5") == nil, "nor bring an order in Bea's name")
from("Bea", "new", { id = "F6", item = 100, n = 1 })
from("Dan", "have", { l = { { id = "F6", who = "Bea", item = 100, n = 1, st = "done", cr = "Dan", ts = NOW, at = NOW + 60 } } })
check(O:Get("F6").st == "open", "naming oneself the crafter in an answer claims nothing")
from("Dan", "have", { l = { { id = "F7", who = "Bea", item = 100, n = 1, st = "accepted", cr = "Dan", ts = NOW, at = NOW } } })
check(O:Get("F7") == nil, "nor brings an order its author never sent")
from("Bea", "have", { l = { { id = "F4", who = "Bea", item = 100, n = 1, st = "cancelled", ts = NOW, at = NOW + 60 } } })
check(O:Get("F4").st == "cancelled", "the author's own answer may say it was cancelled")

-- A late acceptance dated just before another is a takeover, not "at once".
fresh()
from("Bea", "new", { id = "LATE", item = 100, n = 1, ts = NOW - 10 })
O:Apply("acc", { id = "LATE", at = NOW }, CID)
NOW = NOW + 7200
check(O:Apply("acc", { id = "LATE", at = NOW - 7201 }, DAN) == nil and O:Get("LATE").cr == CID,
      "heard two hours after it was sent: refused")
NOW = NOW - 7200

-- A crafter who took the order and gave it back before hearing an earlier acceptance: every client
-- ends with the earlier crafter, whichever order the messages came in.
fresh()
from("Bea", "new", { id = "RA", item = 100, n = 1, ts = NOW - 20 })
from("Bea", "new", { id = "RB", item = 100, n = 1, ts = NOW - 20 })
O:Apply("acc", { id = "RA", at = NOW - 9 }, DAN); O:Apply("rel", { id = "RA", at = NOW - 8 }, DAN)
O:Apply("acc", { id = "RA", at = NOW - 10 }, CID)
O:Apply("acc", { id = "RB", at = NOW - 10 }, CID)
O:Apply("acc", { id = "RB", at = NOW - 9 }, DAN); O:Apply("rel", { id = "RB", at = NOW - 8 }, DAN)
check(O:Get("RA").st == "accepted" and O:Get("RA").cr == CID, "Dan's acceptance and release first: Cid's earlier one holds")
check(O:Get("RB").st == "accepted" and O:Get("RB").cr == CID, "Cid's first: the same end")

-- The crafter's yield replaces the author's unknown one.
fresh()
local yo = O:Place(100, { n = 10 })
check(last("new").data.y == nil, "an author who does not know the yield sends none")
from("Cid", "acc", { id = yo.id, at = NOW, y = 5 })
check(O:Get(yo.id).y == 5 and O:Crafts(O:Get(yo.id)) == 2, "the crafter's yield is used: ten items, two crafts")

-- ── The trade and the mail ──────────────────────────────────────────────
fresh()
local t = O:Place(100, { n = 2, tip = 5000 })
from("Cid", "acc", { id = t.id, at = NOW })
local order, role = O:OrderWith(CID)
check(order and order.id == t.id and role == "author", "trading Cid: my order with him, as its author")
check(O:OrderWith(DAN) == nil, "nothing with Dan")
local wants, tip = O:ToHand(order, role)
check(#wants == 2 and wants[1].itemID == 1 and wants[1].need == 4 and wants[2].need == 2 and tip == 5000,
      "the materials for two, and the tip")
O:OnTradeDone(CID, { "item:1:0", "item:2:0" }, {}, true)
check(O:Get(t.id).st == "mats" and last("mats"), "the materials handed over: marked and sent")
check(O:Get(t.id).paid, "the tip is paid")
check(select(2, O:ToHand(O:Get(t.id), "author")) == 0, "and not asked again")
O:OnTradeDone(CID, {}, { "item:100:0" })
check(O:Get(t.id).st == "done", "the item received: done")

fresh()
from("Bea", "new", { id = "C1", item = 100, n = 1, mode = "own" })
CRAFTS_ME = true; O:ForgetCrafters()
check(O:Act("C1", "accept"), "I accept an order")
check(last("acc").data.rg, "and tell what it takes")
local rows = O:MailRows()
check(#rows == 1 and rows[1].role == "crafter" and rows[1].act == "done", "I can mail the item")
O:FillMail(rows[1])
check(O.mailPending and O.mailPending.to == "Bea", "the bar writes the mail to the author")
O:OnSendMail("Someone", "Hello")
O:OnMailSent()
check(O:Get("C1").st == "accepted" and O.mailPending, "another mail sent from the box does not move the order")
O:OnSendMail("bea", O.mailPending.subject)
O:OnMailSent()
check(O:Get("C1").st == "done", "the mail the bar wrote went: done")
check(#O:MailRows() == 0, "nothing more to mail")

-- Two orders with Cid: the trade moves the one whose item changed hands, whichever the bar picked.
fresh()
local p1 = O:Place(100, {})
local p2 = O:Place(2, { tip = 100 })
from("Cid", "acc", { id = p1.id, at = NOW })
from("Cid", "acc", { id = p2.id, at = NOW })
check(#O:OrdersWith(CID) == 2, "both are with Cid")
O.trade = { partner = CID, pick = p2.id }
check(O:OrderWith(CID).id == p2.id, "the bar's pick is the one the trade is about")
O:OnTradeDone(CID, {}, { "item:2:0" }, true, p2.id)
check(O:Get(p2.id).st == "done" and O:Get(p2.id).paid, "the second one, received, is done and its tip paid")
check(O:Get(p1.id).st == "accepted" and not O:Get(p1.id).paid, "the first one stays where it was")
O.trade = nil

-- Two orders for the same item: one item handed over moves one of them, never both, and always the
-- same one (the oldest, two of the same second by id).
fresh()
local q1 = O:Place(100, {}); local q2 = O:Place(100, {})
from("Cid", "acc", { id = q1.id, at = NOW }); from("Cid", "acc", { id = q2.id, at = NOW })
local first = O:OrdersWith(CID)[1].o.id
check(first == (q1.id < q2.id and q1.id or q2.id), "same second: the lower id is the older")
O:OnTradeDone(CID, {}, { "item:100:0" }, false, nil)
check(O:Get(first).st == "done", "one trade moves that one")
local doneCount = 0
for _, id in ipairs({ q1.id, q2.id }) do if O:Get(id).st == "done" then doneCount = doneCount + 1 end end
check(doneCount == 1, "and only that one: " .. doneCount)

-- Trading needs a unit: the target, or someone in the group; anyone else gets a whisper instead.
local traded
InitiateTrade = function(u) traded = u end
local TARGET
UnitName = function(u) if u == "target" then return TARGET end return PLAYER end
UnitExists = function(u) return u == "Gil" end
TARGET = "Cid"
check(GuildOS.Compat.InitiateTrade("Cid-Realm") and traded == "target", "the targeted player: traded")
check(GuildOS.Compat.InitiateTrade("Gil") and traded == "Gil", "a group member: traded by name")
traded = nil
check(not GuildOS.Compat.InitiateTrade("Hal") and traded == nil, "anyone else: not traded, so the caller whispers")
UnitName = function() return PLAYER end

-- ── Putting the items in ────────────────────────────────────────────────
BAGS = { [0] = { [1] = { id = 1, c = 3 }, [2] = { id = 1, c = 20 }, [3] = { id = 2, c = 1 } } }
cursor, dropped = nil, {}
local missing, full = O:PutItems({ { itemID = 1, need = 5 }, { itemID = 2, need = 2 } }, { 1, 2, 3, 4 },
  function(slot) dropped[#dropped + 1] = { slot = slot, id = cursor.id, c = cursor.c }; cursor = nil end)
check(#dropped == 3, "three slots used")
check(dropped[1].c == 3 and dropped[2].c == 2 and dropped[2].id == 1, "a whole stack, then a split for the rest")
check(missing[2] == 1 and not missing[1] and not full, "what is missing is said")
BAGS = { [0] = { [1] = { id = 1, c = 1 }, [2] = { id = 1, c = 1 }, [3] = { id = 1, c = 1 } } }
dropped = {}
missing, full = O:PutItems({ { itemID = 1, need = 3 } }, { 5, 6 },
  function(slot) dropped[#dropped + 1] = slot; cursor = nil end)
check(#dropped == 2 and full and missing[1] == 1, "out of slots: it stops and says so")

print(("craft-orders: %d checks passed"):format(checks))
