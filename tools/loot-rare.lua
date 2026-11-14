-- The rare loot systems of issue #337, run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Core/Data.lua, Modules/CoreManager.lua, Modules/RaidTracker.lua, Modules/Points.lua, Modules/LootRule.lua,
-- Modules/LootMaster.lua, UI/FeaturePanels.lua and UI/PointsPanel.lua:
--   * a queue account (Suicide Kings): read by the place in it, the winner to the end, the classic rule
--     that whoever is absent keeps their slot, newcomers at the end or at a random place, the whole order
--     synced between two officers through the points' op log and snapshot, and an undo that gives back
--     the exact order;
--   * a bonus account added to the roll of an answer that counts (karma, SR+), with a cap, charged only
--     when the winning answer used it;
--   * a summed score of parts, with no formula anywhere;
--   * what was paid shared among the raid (zero-sum DKP), each share an entry, taken back by an undo;
--   * "Suicide Kings" and "Karma" as loot systems of the picker;
--   * the points window and the rule editor draw them.
--
--   luajit -e 'ADDON="."' tools/loot-rare.lua
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
local inRaid, leader = true, true
function IsInRaid() return inRaid end
function IsInGroup() return true end
function SendChatMessage() end
function GetLootMethod() return "master", 0 end
local raid = { "Lead", "Ana", "Bo", "Cy", "Dee" }
function UnitIsGroupLeader() return leader end
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
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
local function freshDb(system)
  return { settings = { lootSystem = system or "rolls" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
    lootMaster = { awardHistory = {} }, points = {},
    raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
end
GuildOS.db = freshDb()
local LM, LR, P, CM = GuildOS.LootMaster, GuildOS.LootRule, GuildOS.Points, GuildOS.CoreManager
local officer = true
GuildOS.IsOfficer = function() return officer end
GuildOS.IsOfficerByName = function() return true end
function GuildOS:ApplyFont() end
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
local function keys(...)
  local out = {}
  for i, name in ipairs({ ... }) do out[i] = K(name) end
  return out
end
local function names(list)
  local out = {}
  for i, key in ipairs(list) do out[i] = key:match("^([^-]+)") end
  return table.concat(out, ",")
end

local said, sent = {}, {}
LM.SafeSendAddon = function(_, _, payload) sent[#sent + 1] = payload end
LM.SendEcho = function() end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.IsMasterLooter = function() return true end
local att, prios, wishes = {}, {}, {}
LM.GetPlayerContext = function(_, name) return { att25 = att[name] or 100, recvThisLockout = 0 } end
LM.ShowRollFrame = function() end
LM.StopListeningForRolls = function() end
function GuildOS:Print() end
function GuildOS:UpdateLootSystemUI() end
GuildOS.Wishlist = { GetItemInterest = function() return wishes end }
local function quiet() said, sent, published = {}, {}, {} end
local function all(list) return table.concat(list, "\n") end

local LINK = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r"
local ITEM = 28770
-- A night starts over under the guild's own rule `r` (nil: the loot system's).
local function night(r, system)
  GuildOS.db = freshDb(system)
  GuildOS.db.lootPrios = { [ITEM] = prios }
  P:Initialize()
  LM.activeLoot, LM.rolls = nil, {}
  att, prios, wishes = {}, {}, {}
  GuildOS.db.lootPrios = { [ITEM] = prios }
  raid = { "Lead", "Ana", "Bo", "Cy", "Dee" }
  if r then
    local ok, why = LR:Set(r)
    check(ok, "the rule is one this client reads (" .. tostring(why) .. ")")
  end
  quiet()
end
local function announce()
  quiet()
  LM.lootWindowOpen = false
  LM:AnnounceItem(LINK, nil)
end
local function order()
  LM:EndRolling(true)
  local out = {}
  for i, r in ipairs(LM.activeLoot.sortedResults) do out[i] = r.name end
  return table.concat(out, ",")
end
local function rule(more)
  local r = { v = 1, model = "custom", order = { { k = "response" }, { k = "roll" } } }
  for k, v in pairs(more or {}) do r[k] = v end
  return r
end

-- ── 1. A queue account ──────────────────────────────────────────────
local function skRule(frozen, newcomer)
  return rule({
    responses = { { key = "MS", ask = "none", plus = true }, { key = "OS", ask = "roll", plus = false, cost = 0 } },
    accounts = { { key = "sk", type = "queue", name = "SK", frozen = frozen, newcomer = newcomer } },
    order = { { k = "response" }, { k = "account", acct = "sk", dir = "low" }, { k = "roll" } },
    effects = { { k = "bottom", acct = "sk" } },
  })
end
night(skRule(false))
check(#P:Queue("sk") == 0 and P:QueuePos("sk", K("Ana")) == nil, "a queue starts empty")
announce()
check(names(P:Queue("sk")) == "Ana,Bo,Cy,Dee,Lead", "the raid joins at the end, by name, when an item is announced: " .. names(P:Queue("sk")))
check(#published == 1 and published[1].act == "qset" and published[1].data.entries[1].seq == 1,
  "told to the officers as the queue's own entry, which a client from before does not read as points")
announce()
check(#published == 0, "a raid the queue already holds changes nothing")
-- Somebody who joined the raid late answers: they join the queue then.
raid[#raid + 1] = "Eve"
check(LM:TakeAnswer("Eve", "MS") and P:QueuePos("sk", K("Eve")) == 6 and LM.rolls[K("Eve")].accts.sk == 6,
  "whoever answers without a place joins at the end, and the answer carries the place")
LM:TakeAnswer("Cy", "MS")
LM:TakeAnswer("Bo", "MS")
LM:TakeAnswer("Ana", "OS")
check(LM.rolls[K("Cy")].roll == nil and LM.rolls[K("Ana")].roll ~= nil, "an answer that asks for no roll draws none")
check(order() == "Bo,Cy,Eve,Ana", "the place decides among main spec; off spec after, whatever its place: " .. order())
check(LM.activeLoot.decidedBy == "account" and all(said):find("[by the counter]", 1, true), "and the raid is told the account decided")
check(LM:AccountsText(LM.rolls[K("Cy")], LM:Rule()):find("#3", 1, true), "the roll frame shows the place")
LM:AwardLoot("Bo")
check(names(P:Queue("sk")) == "Ana,Cy,Dee,Lead,Eve,Bo", "the winner drops to the end; everyone below moves up: " .. names(P:Queue("sk")))
local award = GuildOS.db.lootMaster.awardHistory[1]
check(award.queue and #award.queue == 1 and award.queue[1].from == 2 and award.queue[1].to == 6 and award.queue[1].slots == nil,
  "the award keeps the move, small, for an undo")
-- Off spec is a free roll: nobody moves.
announce()
LM:TakeAnswer("Ana", "OS")
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(names(P:Queue("sk")) == "Ana,Cy,Dee,Lead,Eve,Bo" and GuildOS.db.lootMaster.awardHistory[1].queue == nil, "an off spec win moves nobody")
check(LM:UndoLastAward() and LM:UndoLastAward() and names(P:Queue("sk")) == "Ana,Bo,Cy,Dee,Lead,Eve", "an undo gives back the exact order")
-- An item given straight from the loot window, with no answer, moves nobody.
LM:SetActiveLoot(LINK, nil, ITEM)
LM:AwardLoot("Cy")
check(P:QueuePos("sk", K("Cy")) == 3, "an item given with no answer moves nobody")

-- The classic rule: only who is in the raid moves up, whoever is absent keeps their slot.
night(skRule(true))
P:SetQueue("sk", keys("Ana", "Zed", "Bo", "Yan", "Cy", "Dee", "Xia"))
raid = { "Lead", "Ana", "Bo", "Cy", "Dee" }
announce()
check(names(P:Queue("sk")) == "Ana,Zed,Bo,Yan,Cy,Dee,Xia,Lead", "a raider the list never saw joins at the end: " .. names(P:Queue("sk")))
LM:TakeAnswer("Ana", "MS")
LM:TakeAnswer("Cy", "MS")
check(order() == "Ana,Cy", "first in line wins")
LM:AwardLoot("Ana")
check(names(P:Queue("sk")) == "Bo,Zed,Cy,Yan,Dee,Lead,Xia,Ana",
  "frozen: Zed, Yan and Xia, absent, keep their slots; the raiders move up one raider's slot; the winner takes the last raider's: " .. names(P:Queue("sk")))
award = GuildOS.db.lootMaster.awardHistory[1]
check(award.queue[1].slots and #award.queue[1].slots == 5, "the move keeps the slots that took part")
check(LM:UndoLastAward() and names(P:Queue("sk")) == "Ana,Zed,Bo,Yan,Cy,Dee,Xia,Lead", "and an undo puts every one of them back")
-- The last raider in line wins: nobody to move up past.
announce()
LM:TakeAnswer("Lead", "MS")
LM:EndRolling(true)
LM:AwardLoot("Lead")
check(names(P:Queue("sk")) == "Ana,Zed,Bo,Yan,Cy,Dee,Xia,Lead" and GuildOS.db.lootMaster.awardHistory[1].queue == nil,
  "the last raider in line stays where they are")
-- The queue changed between the award and its undo: the winner alone goes back to their slot.
announce()
LM:TakeAnswer("Bo", "MS")
LM:EndRolling(true)
LM:AwardLoot("Bo")
check(names(P:Queue("sk")) == "Ana,Zed,Cy,Yan,Dee,Lead,Xia,Bo", "Bo drops: " .. names(P:Queue("sk")))
P:SetQueue("sk", keys("Ana", "Zed", "Cy", "Yan", "Dee", "Lead", "Bo", "Xia"))
check(LM:UndoLastAward() and P:QueuePos("sk", K("Bo")) == 3, "an undo after another change still gives the winner their slot back: " .. names(P:Queue("sk")))

-- Newcomers at a random place.
night(skRule(false, "random"))
P:SetQueue("sk", keys("Zed", "Yan"))
local realRandom = math.random
math.random = function(a) return a end   -- always the first place offered
announce()
math.random = realRandom
check(names(P:Queue("sk")) == "Lead,Dee,Cy,Bo,Ana,Zed,Yan", "each newcomer is put at a place drawn among the whole list: " .. names(P:Queue("sk")))

-- Two officers: the queue travels in the points' op log, and the newest order wins on both.
night(skRule(false))
local dbA, dbB = GuildOS.db, freshDb()
local function asB(fn)
  GuildOS.db = dbB
  if not dbB.points.standings then P:Initialize() end
  fn()
  GuildOS.db = dbA
end
local function deliver(list, sender)
  for _, m in ipairs(list) do
    if m.dom == "points" then handlers.points({ act = m.act, data = m.data, rev = m.rev }, sender or "Lead-Realm") end
  end
end
announce()
LM:TakeAnswer("Cy", "MS")
LM:EndRolling(true)
LM:AwardLoot("Cy")
local fromA = published
check(#fromA == 2 and fromA[1].act == "qset" and fromA[2].act == "qset", "officer A told the join and the move")
asB(function()
  -- Out of order: the move first, then the join it came after.
  deliver({ fromA[2] })
  check(names(P:Queue("sk")) == "Ana,Bo,Dee,Lead,Cy", "officer B reads the move: " .. names(P:Queue("sk")))
  deliver({ fromA[1] })
  check(names(P:Queue("sk")) == "Ana,Bo,Dee,Lead,Cy", "an older order that arrives late changes nothing")
  deliver({ fromA[2] })
  check(P:GetDB().queues.sk.seq == 2, "nor does the same entry twice")
end)
-- Both change it at once: the same sequence number settles by the entry's own name, on both clients.
quiet()
P:SetQueue("sk", keys("Bo", "Ana", "Dee", "Lead", "Cy"))
local aSet = published
local bSet
asB(function()
  quiet()
  P:SetQueue("sk", keys("Dee", "Ana", "Bo", "Lead", "Cy"))
  bSet = published
  deliver(aSet)
end)
deliver(bSet)
local finalA = names(P:Queue("sk"))
asB(function() check(names(P:Queue("sk")) == finalA, "two officers changing the queue at once end on the same order: " .. finalA) end)
-- An undo by officer A reaches officer B as the exact order.
quiet()
P:SetQueue("sk", keys("Ana", "Bo", "Dee", "Lead", "Cy"))
deliver({})
local reset = published
asB(function() deliver(reset) end)
announce()
LM:TakeAnswer("Ana", "MS")
LM:EndRolling(true)
LM:AwardLoot("Ana")
local move = published
quiet()
check(LM:UndoLastAward() and names(P:Queue("sk")) == "Ana,Bo,Dee,Lead,Cy", "officer A undoes the award")
local undo = published
asB(function()
  deliver(move)
  check(names(P:Queue("sk")) == "Bo,Dee,Lead,Cy,Ana", "officer B saw the award")
  deliver(undo)
  check(names(P:Queue("sk")) == "Ana,Bo,Dee,Lead,Cy", "and the undo gives it the exact order back")
end)
-- The snapshot carries the queues, for an officer who missed the entries.
quiet()
P:BroadcastSnapshot()
local snapshot = published
check(snapshot[1].act == "snapshot" and snapshot[1].data.queues.sk, "the snapshot carries the queues")
dbB = freshDb()
asB(function()
  deliver(snapshot)
  check(names(P:Queue("sk")) == "Ana,Bo,Dee,Lead,Cy", "an officer who missed every entry reads them off the snapshot")
end)
-- Untrusted: an entry that is not a queue's is not applied.
local function forged(e)
  local before = names(P:Queue("sk"))
  handlers.points({ act = "qset", data = { entries = { e } } }, "Off-Realm")
  return names(P:Queue("sk")) == before
end
forged({ op = "Z1", acct = "sk", seq = 99, list = { K("Ana"), K("Ana"), 7 } })
check(names(P:Queue("sk")) == "Ana", "a name twice is kept once, and what is no name is not kept: " .. names(P:Queue("sk")))
P:SetQueue("sk", keys("Ana", "Bo", "Dee", "Lead", "Cy"))
check(forged({ op = "Z2", acct = "sk", seq = 1e12, list = { K("Bo") } }), "nor a sequence number past any queue's")
check(forged({ op = "Z3", acct = "SK!", seq = 500, list = { K("Bo") } }), "nor an account that is no key")
check(forged({ op = "Z4", acct = "sk", seq = 500.5, list = { K("Bo") } }), "nor half a sequence number")
check(forged({ op = "Z5", acct = "sk", seq = 500, list = { string.rep("x", 200) } }), "nor a name no player has")
check(forged({ op = "Z6", acct = "sk", seq = 500, list = "Bo" }), "nor a list that is no list")
local long = {}
for i = 1, 300 do long[i] = "P" .. i end
check(forged({ op = "Z7", acct = "sk", seq = 500, list = long }), "nor three hundred players")
-- Somebody who is no officer keeps the queue here and tells nobody.
officer = false
quiet()
P:SetQueue("sk", keys("Bo", "Ana"))
check(#published == 0 and names(P:Queue("sk")) == "Bo,Ana", "a loot master who is no officer keeps the queue here and tells nobody")
officer = true

-- ── 2. A bonus account ──────────────────────────────────────────────
local function karmaRule(price, value, more)
  local r = rule({
    responses = { { key = "MS", plus = true }, { key = "OS", plus = false } },
    accounts = { { key = "karma", type = "bonus", name = "Karma", cap = 100, earn = { { key = "raid", auto = "raid", value = 5 } } } },
    order = { { k = "response" }, { k = "roll", bonus = "karma" } },
    effects = { { k = "charge", acct = "karma", price = price or "fraction", value = value } },
  })
  for k, v in pairs(more or {}) do r[k] = v end
  return r
end
night(karmaRule("fraction", 0.5))
P:AddCounter("karma", K("Ana"), 30, "never")
P:AddCounter("karma", K("Bo"), 80, "never")
announce()
LM:RegisterRoll("Ana", "MS", 70)
LM:RegisterRoll("Bo", "OS", 99)
LM:RegisterRoll("Cy", "MS", 95)
check(order() == "Ana,Cy,Bo", "70 + 30 beats 95 + 0; an off spec roll is not added to: " .. order())
local rows = LM.rolls
check(LR:BonusOf(rows[K("Ana")], LM:Rule()) == 30 and LR:BonusOf(rows[K("Bo")], LM:Rule()) == 0, "the bonus is the answer's that counts")
check(LM:RollText(rows[K("Ana")], LM:Rule()) == "70 |cffFF9900+30|r = 100" and LM:RollText(rows[K("Bo")], LM:Rule()) == "99",
  "the roll frame shows the roll and the bonus apart: " .. LM:RollText(rows[K("Ana")], LM:Rule()))
check(LM:AccountsText(rows[K("Bo")], LM:Rule()):find("Karma 80", 1, true), "and what each one holds on the account")
check(all(said):find("Ana - MS (70 + 30)", 1, true), "the winner line too")
LM:AwardLoot("Ana")
check(P:Counter("karma", K("Ana")) == 15, "the winner who rolled with karma loses half")
announce()
LM:RegisterRoll("Bo", "OS", 10)
LM:EndRolling(true)
LM:AwardLoot("Bo")
check(P:Counter("karma", K("Bo")) == 80, "a win by an answer that did not use the bonus charges none of it")
check(LM:UndoLastAward() and LM:UndoLastAward() and P:Counter("karma", K("Ana")) == 30, "an undo gives the karma back")
-- A pass and an answer with no roll have no bonus.
check(LR:BonusOf({ rollType = "PASS", roll = 0, accts = { karma = 50 } }, LM:Rule()) == 0
  and LR:BonusOf({ rollType = "MS", accts = { karma = 50 } }, LM:Rule()) == 0, "no roll, no bonus")
-- All of it.
night(karmaRule("all"))
P:AddCounter("karma", K("Ana"), 30, "never")
announce()
LM:RegisterRoll("Ana", "MS", 1)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Counter("karma", K("Ana")) == 0, "all of it")
-- The cap: what a raid gives never goes past it, nor what an award adds.
night(karmaRule("fraction", 0.5, { effects = { { k = "add", acct = "karma", value = 10 } } }))
P:AddCounter("karma", K("Ana"), 98, "never")
P:AddCounter("karma", K("Bo"), 50, "never")
local session = { startTime = 1790990000, endTime = 1791000000, snapshots = { { members = { [K("Ana")] = true, [K("Bo")] = true, [K("Cy")] = true } } } }
P:OnRaidEnd(session)
check(P:Counter("karma", K("Ana")) == 100 and P:Counter("karma", K("Bo")) == 55 and P:Counter("karma", K("Cy")) == 5,
  "a raid attended adds five, and only what fits under the cap")
P:OnRaidEnd(session)
check(P:Counter("karma", K("Bo")) == 55, "the same raid ended twice counts once")
announce()
LM:RegisterRoll("Ana", "MS", 1)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Counter("karma", K("Ana")) == 100, "an award that adds to a full account adds nothing")
check(names({ P:CounterStandings("karma")[1].key, P:CounterStandings("karma")[2].key }) == "Ana,Bo", "the account's standings, the most first")
-- What a rule may say of one.
local function refused(r, what)
  local ok, why = LR:Validate(r)
  check(ok == false, "refused: " .. what .. " (" .. tostring(why) .. ")")
end
refused(karmaRule("fraction", 0.5, { accounts = { { key = "karma", type = "bonus", start = 5 } } }), "a bonus account that starts at something")
refused(karmaRule("fraction", 0.5, { accounts = { { key = "karma", type = "bonus", cap = 0 } } }), "a cap of nothing")
refused(karmaRule("fraction", 0.5, { accounts = { { key = "karma", type = "bonus", decay = { pct = 10 } } } }), "a bonus account that decays")
refused(karmaRule("bid"), "a bid paid in karma")
refused(rule({ accounts = { { key = "dkp", type = "bonus" } } }), "the points as a bonus account")

-- ── 3. A summed score ───────────────────────────────────────────────
night(rule({
  accounts = { { key = "wait", type = "counter", name = "Wait" } },
  order = { { k = "response" }, { k = "score", parts = {
    { k = "wishlist", w = 2 }, { k = "prio", w = 1 }, { k = "attendance", w = 0.1 }, { k = "account", acct = "wait", w = 1 },
    { k = "received", w = -3 } } }, { k = "roll" } },
}))
wishes[1], wishes[2] = { name = "Ana", order = 1 }, { name = "Bo", order = 3 }
prios[1] = { name = "Bo" }
att = { Ana = 90, Bo = 60, Cy = 100 }
P:AddCounter("wait", K("Cy"), 4, "never")
LM.GetPlayerContext = function(_, name) return { att25 = att[name] or 100, recvThisLockout = name == "Ana" and 2 or 0 } end
-- The night's rule opens its roll to everyone; the guild's own takes the wishlist shortcuts of before,
-- which is not what is being looked at here.
LM.activeLoot = { link = LINK, itemId = ITEM, rule = LR:Active(), system = "rolls", sid = "A1" }
LM.rolls = {}
LM:RegisterRoll("Ana", "MS", 1, { quiet = true })
LM:RegisterRoll("Bo", "MS", 2, { quiet = true })
LM:RegisterRoll("Cy", "MS", 3, { quiet = true })
LM:RegisterRoll("Dee", "OS", 100, { quiet = true })
-- Ana: 2*10 + 0 + 9 + 0 - 6 = 23.  Bo: 2*8 + 10 + 6 + 0 = 32.  Cy: 0 + 0 + 10 + 4 = 14.
check(order() == "Bo,Ana,Cy,Dee", "the larger score first, the answer before it: " .. order())
local total, parts = LR:ScoreOf(LM.rolls[K("Ana")], LM:Rule())
check(total == 23 and #parts == 5 and parts[1].points == 20 and parts[5].points == -6, "the total, and each part's share of it")
check(LR:ScoreOf(LM.rolls[K("Bo")], LM:Rule()) == 32 and LR:ScoreOf(LM.rolls[K("Cy")], LM:Rule()) == 14, "every candidate's")
check(LM.activeLoot.decidedBy == "score" and LR:Label("score") == "the score", "and the score is what decided")
check(LM:AccountsText(LM.rolls[K("Ana")], LM:Rule()):find("score 23.0", 1, true), "the roll frame shows the total")
local tip = LM:RowTip(LM.rolls[K("Ana")], LM:Rule())
check(#tip == 6 and tip[1] == "Score: 23.0" and tip[2] == "wishlist place: 10 x 2 = 20.0" and tip[5] == "Wait: 0 x 1 = 0.0"
  and tip[6] == "items received: 2 x -3 = -6.0", "and its tooltip the parts: " .. table.concat(tip, " / "))
check(LR:ScoreOf(LM.rolls[K("Ana")], rule()) == nil and #LM:RowTip({ name = "X" }, rule()) == 0, "a rule with no score shows none")
LM:CancelRolling()
LM.GetPlayerContext = function(_, name) return { att25 = att[name] or 100, recvThisLockout = 0 } end
-- A place past the tenth is worth nothing, as no place at all.
check(LR:ScoreOf({ wishlist = { order = 11 } }, rule({ order = { { k = "score", parts = { { k = "wishlist", w = 1 } } } } })) == 0
  and LR:ScoreOf({ wishlist = { order = 10 } }, rule({ order = { { k = "score", parts = { { k = "wishlist", w = 1 } } } } })) == 1,
  "the tenth place is worth one, the eleventh nothing")
refused(rule({ order = { { k = "score", parts = { { k = "attendance", w = 1 }, { k = "attendance", w = 2 } } } } }), "a part twice")
refused(rule({ order = { { k = "score", parts = { { k = "account", acct = "nope", w = 1 } } } } }), "a part on an account nobody declared")
refused(rule({ order = { { k = "score", parts = { { k = "attendance", w = 1000 } } } } }), "a weight past any")
refused(rule({ order = { { k = "score", parts = { { k = "attendance", w = 1 } } }, { k = "score", parts = { { k = "prio", w = 1 } } } } }), "two scores")

-- ── 4. What was paid, shared among the raid ─────────────────────────
night(rule({
  order = { { k = "response" }, { k = "points" }, { k = "roll" } },
  effects = { { k = "charge", acct = "dkp", price = "fixed", value = 23 }, { k = "split", acct = "dkp" } },
}))
P:Award(K("Ana"), 100, "seed")
announce()
LM:RegisterRoll("Ana", "MS", 50)
LM:EndRolling(true)
quiet()
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 81 and P:Get(K("Bo")) == 4 and P:Get(K("Lead")) == 4, "23 paid: four to each of the five in the raid, the winner too, three dropped")
award = GuildOS.db.lootMaster.awardHistory[1]
check(award.charged == 23 and #award.split == 5 and award.split[1].amount == 4, "the award keeps the shares for an undo")
local log = P:GetLog(5)
check(log[1].kind == "split" and log[1].reason == "Share of " .. LINK and log[1].delta == 4, "each share is a line of the history: " .. tostring(log[1].reason))
check(#published == 2 and published[1].act == "delta" and #published[2].data.entries == 5, "and an entry told to the officers")
check(all(said):find("4 points each to 5 raiders", 1, true), "the raid is told: " .. all(said))
quiet()
check(LM:UndoLastAward() and P:Get(K("Ana")) == 100 and P:Get(K("Bo")) == 0 and P:Get(K("Lead")) == 0, "an undo takes every share back and gives the price back")
check(#published == 2, "in two messages, whatever the raid's size")
-- A price smaller than the raid shares nothing.
LR:Set(rule({ effects = { { k = "charge", acct = "dkp", price = "fixed", value = 3 }, { k = "split" } } }))
announce()
LM:RegisterRoll("Ana", "MS", 50)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 97 and P:Get(K("Bo")) == 0 and GuildOS.db.lootMaster.awardHistory[1].split == nil, "three among five is nothing each")
-- A fixed destination costs nothing and shares nothing.
check(#P:Split({}, 10, "x") == 0 and #P:Split(keys("Ana"), 0, "x") == 0, "nobody to share with, or nothing to share")
officer = false
check(#P:Split(keys("Ana"), 10, "x") == 0, "and only an officer's client shares")
officer = true
refused(rule({ effects = { { k = "split" }, { k = "split" } } }), "two shares")
refused(rule({ effects = { { k = "split", value = 2 } } }), "a share with a figure")

-- ── 5. Suicide Kings and Karma, as loot systems of the picker ───────
local offered = {}
for _, sys in ipairs(GuildOS:LootSystemsHere()) do offered[sys.key] = GuildOS:LootSystemLabel(sys) end
check(offered.sk == "Suicide Kings" and offered.karma == "Karma", "the picker offers both")
night(nil, "sk")
local sk = LR:Active()
check(LR:Validate(sk) and sk.model == "sk" and LR:Queue("sk").frozen == true and LR:Queue("sk").newcomer == "bottom"
  and sk.responses[1].ask == "none" and sk.effects[1].k == "bottom", "Suicide Kings is a rule this client reads, with the classic freeze")
check(GuildOS:LootSystemShowsDKP() and not GuildOS:LootSystemUsesPoints(), "its list is looked at in the points window, though it spends no points")
announce()
LM:TakeAnswer("Dee", "MS")
LM:TakeAnswer("Bo", "MS")
check(order() == "Bo,Dee" and LM:AwardLoot("Bo") == nil and P:QueuePos("sk", K("Bo")) == 5, "and it plays: " .. names(P:Queue("sk")))
night(nil, "karma")
local karma = LR:Active()
check(LR:Validate(karma) and karma.model == "karma" and LR:RollBonus() == "karma" and LR:Counter("karma").cap == 100,
  "Karma is a rule this client reads")
check(GuildOS:LootSystemShowsDKP(), "and its account is looked at in the points window")
P:AddCounter("karma", K("Ana"), 40, "never")
announce()
check(said[1]:find("[ROLL]", 1, true), "announced as a roll")
LM:RegisterRoll("Ana", "MS", 20)
LM:RegisterRoll("Bo", "MS", 55)
check(order() == "Ana,Bo", "20 + 40 beats 55")
LM:AwardLoot("Ana")
check(P:Counter("karma", K("Ana")) == 20, "and the winner loses half")
night(nil, "rolls")
check(not GuildOS:LootSystemShowsDKP(), "a guild on plain rolls is offered no points window, as before")
night(nil, "plus1")
check(not GuildOS:LootSystemShowsDKP(), "nor one on +1")

-- ── 6. The windows draw them ────────────────────────────────────────
GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })
GuildOS.UI = setmetatable({
  CreateButton = function(_, _, text)
    local b = widget({ text = tostring(text), label = widget() })
    buttons[#buttons + 1] = b
    return b
  end,
  CreateCheckbox = function() return widget({ checkbox = widget() }) end,
  CreateScrollFrame = function() return widget(), widget() end,
  CreateText = function(_, _, text) return widget({ text = text }) end,
  AttachSaveButton = function(_, box, onSave)
    box.saveButton = widget({ text = "Save" })
    box.save = function(text) box.text = text; onSave(box) end
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
function GuildOS:GetClassColor() return 1, 1, 1 end
function GuildOS:ColorText(t) return t end
dofile(ADDON .. "/UI/FeaturePanels.lua")
dofile(ADDON .. "/UI/PointsPanel.lua")

-- The rule editor: the queue's two options.
night(nil, "sk")
widgets, buttons = {}, {}
local drew, problem = pcall(GuildOS.ShowLootRuleEditor, GuildOS, "")
check(drew, "the rule editor draws a rule with a queue (" .. tostring(problem) .. ")")
check(button("Only who is in the raid moves up") and button("At a random place"), "with the queue's options")
click("Everyone below moves up")
check(LR:IsCustom() and LR:Queue("sk").frozen == false, "a click changes the rule")
click("At a random place")
check(LR:Queue("sk").newcomer == "random", "and so does the other")
check(select(2, LR:SetQueueField("sk", "seq", 1)) == "accounts", "the queue has no other option to set")

-- The points window: the account picker.
P:SetQueue("sk", keys("Bo", "Ana"))
widgets, buttons = {}, {}
drew, problem = pcall(GuildOS.ShowPointsFrame, GuildOS)
check(drew, "the points window draws (" .. tostring(problem) .. ")")
local picker
for _, b in ipairs(buttons) do
  if b.label.text == "Account: Points" then picker = b end
end
check(picker and not picker.hidden, "with a button that says which account is shown")
picker.scripts.OnClick(picker)
check(picker.label.text == "Account: Suicide Kings", "a click shows the rule's queue: " .. tostring(picker.label.text))
picker.scripts.OnClick(picker)
check(picker.label.text == "Account: Points", "and another goes back to the points")
LR:Set(nil)
GuildOS.db.settings.lootSystem = "rolls"
P:Refresh()
check(picker.hidden, "a rule that keeps no account hides the button")

print(("loot-rare: %d checks passed"):format(checks))
