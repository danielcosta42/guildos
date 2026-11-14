-- The accounts of the loot rule (issues #309, #319), run against the real Core/Core.lua,
-- Modules/CoreManager.lua, Modules/Points.lua, Modules/LootRule.lua and Modules/LootMaster.lua:
--   * with nothing set, points behave as before;
--   * a cap holds earnings back and the history says so; a refund is never held back;
--   * the guild's named reasons give their value, as many times as asked, up to their weekly cap;
--   * decay rounds to the nearest, up or down;
--   * a raid's end gives on time or late, stayed or left early, and the raid, once whoever ends it;
--   * a roll that costs to enter: everyone who asked pays, whoever lost gets part back, whoever cannot
--     pay is out of the roll, and an undo gives every one of them back what they paid;
--   * EPGP: priority is EP / (GP + base), under the minimum EP comes last, an item's GP follows its slot
--     and item level or the guild's own price, decay takes both sides, and the roll's end reads priority.
--
--   luajit -e 'ADDON="."' tools/loot-points.lua
--
-- Exits 1 on the first failed check.
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
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
local player = "Lead"   -- whose client this is: the raid's end is run from two officers' clients
function UnitFullName() return player, "Er" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetInstanceInfo() return "Onyxia's Lair", "raid", 9, "", 40, 0, false, 249 end
function GetRealmName() return "Realm" end
local NOW = 1791000000
function GetServerTime() return NOW end
function GetTime() return 1 end
time = os.time
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInRaid() return true end
function SendChatMessage() end
function GetLootMethod() return "master", 0 end
function GetNumGroupMembers() return 0 end
function UnitClass() return "Mage", "MAGE" end
function UnitName() return player end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CoreManager.lua")
dofile(ADDON .. "/Modules/Points.lua")
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
GuildOS.db = { settings = { lootSystem = "dkp" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { awardHistory = {} }, points = {},
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local LM, LR, P = GuildOS.LootMaster, GuildOS.LootRule, GuildOS.Points
GuildOS.IsOfficer = function() return true end
GuildOS.IsOfficerByName = function() return true end
P:Initialize()
local cfg = GuildOS.db.points.config
local function K(name) return GuildOS:GetPlayerKey(name) end
local function top() return GuildOS.db.points.log[1] end

local said = {}
LM.SafeSendAddon = function() end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.StopListeningForRolls = function() end
LM.IsMasterLooter = function() return true end

-- ── Nothing set: as before ──────────────────────────────────────────
P:Award(K("Ana"), 30, "boss")
check(P:Get(K("Ana")) == 30 and top().reason == "boss", "with no cap, an award adds whole")
check(P:PriceOf("|Hitem:1|h[x]|h") == 0, "and an item costs nothing until the guild says what")

-- ── The cap ─────────────────────────────────────────────────────────
cfg.cap = 25
P:Award(K("Bo"), 5, "raid")
P:Award(K("Bo"), 30, "boss")
check(P:Get(K("Bo")) == 25, "an earning stops at the cap")
check(top().delta == 20 and top().reason:find("cap reached: 20 of 30", 1, true), "and the history says how much fit: " .. top().reason)
P:Award(K("Bo"), 5, "boss")
check(P:Get(K("Bo")) == 25 and top().delta == 0 and top().reason:find("cap reached: 0 of 5", 1, true),
  "at the cap nothing adds, and the line is still there")
P:Charge(K("Bo"), 10, "item")
P:Refund(K("Bo"), 10, "undo")
check(P:Get(K("Bo")) == 25, "a charge and its refund leave the points where they were")
cfg.cap = 20
P:Refund(K("Bo"), 3, "undo")
check(P:Get(K("Bo")) == 28, "and a refund is never held to the cap")
cfg.cap = 0

-- ── Named reasons, with a weekly cap ────────────────────────────────
check(P:SetReason("Material donation", "Material donation", 1, 5), "an officer adds a reason")
check(P:SetReason("Gold", "Gold donation", 1, 2), "and another")
local mats = P:GetReasons()[1]
check(mats.key == "material" and mats.value == 1 and mats.weekly == 5, "its key is cut from its name")
local before = P:Get(K("Cy"))
P:AwardReason(K("Cy"), "material", 3)
check(P:Get(K("Cy")) == before + 3 and top().reason == "Material donation" and top().rk == "material",
  "three stacks give three points, under the reason's name")
P:AwardReason(K("Cy"), "material", 4)
check(P:Get(K("Cy")) == before + 5, "the fourth and fifth fit the week; the sixth and seventh do not")
check(top().reason:find("weekly cap reached: 2 of 4", 1, true), "and the history says so: " .. top().reason)
P:AwardReason(K("Cy"), "gold", 1)
check(P:Get(K("Cy")) == before + 6, "another reason has its own week")
P:AwardReason(K("Dee"), "material", 5)
check(P:Get(K("Dee")) == 5, "and another player their own")
local realNow = GetServerTime
function GetServerTime() return realNow() + 7 * 86400 end
P:AwardReason(K("Cy"), "material", 1)
check(P:Get(K("Cy")) == before + 7, "a week later the reason gives again")
GetServerTime = realNow
-- The week is the game's reset week, not a calendar week from Thursday 00:00 UTC, which fell in the
-- middle of the raid week: the cap paid on Wednesday at 23:00 and again on Thursday at 01:00.
GuildOS.RaidTracker = { GetCurrentGroup = function() return "" end,
  GetWeekNum = function(_, ts) return math.floor((ts - 1127228400) / 604800) end }   -- the Americas' reset
local thursday = math.floor(realNow() / 604800) * 604800 + 5 * 604800   -- a Thursday, 00:00 UTC
local clock = thursday - 3600
function GetServerTime() return clock end
before = P:Get(K("Bo"))
P:AwardReason(K("Bo"), "material", 5)
clock = thursday + 3600
P:AwardReason(K("Bo"), "material", 5)
check(P:Get(K("Bo")) == before + 5 and top().reason:find("weekly cap reached: 0 of 5", 1, true),
  "Wednesday 23:00 and Thursday 01:00 UTC are one reset week: the cap pays once")
-- The snapshot carries the week's figures: an officer who only got the snapshot does not pay again.
local sentSnap
GuildOS.SyncService = { NextRevision = function() return 1 end, ShouldApply = function() return true end,
  SetRevision = function() end, Publish = function(_, _, act, data) if act == "snapshot" then sentSnap = data end end }
P:BroadcastSnapshot()
check(sentSnap.weekly and sentSnap.weekly.v[K("Bo") .. "|material"] == 5, "the snapshot carries what each reason gave this week")
local home, away = GuildOS.db.points, { mode = "dkp", config = cfg, standings = {}, log = {}, appliedOps = {}, appliedCount = 0 }
GuildOS.db.points = away
P:OnSync({ act = "snapshot", rev = 1, data = { core = "", mode = "dkp", config = cfg, standings = { [K("Bo")] = { current = before + 5, earned = 5, spent = 0 } },
  weekly = { w = sentSnap.weekly.w, v = { [K("Bo") .. "|material"] = 5, [K("Cy") .. "|material"] = "many", [7] = 1 } } } })
P:AwardReason(K("Bo"), "material", 1)
check(P:Get(K("Bo")) == before + 5 and top().reason:find("weekly cap reached: 0 of 1", 1, true),
  "an officer who got the snapshot alone holds the cap too: " .. tostring(top() and top().reason))
P:AwardReason(K("Cy"), "material", 1)
check(top().delta == 1, "and takes from it only what is a figure")
P:OnSync({ act = "snapshot", rev = 2, data = { core = "", mode = "dkp", config = cfg,
  weekly = { w = sentSnap.weekly.w - 1, v = { [K("Dee") .. "|material"] = 5 } } } })
P:AwardReason(K("Dee"), "material", 1)
check(top().delta == 1, "another week's figures are not this week's")
GuildOS.db.points = home
GuildOS.SyncService = nil
-- Across the reset (Tuesday 15:00 UTC for the Americas) the reason gives again.
clock = 1127228400 + math.floor((thursday - 1127228400) / 604800 + 1) * 604800 + 3600
P:AwardReason(K("Bo"), "material", 2)
check(P:Get(K("Bo")) == before + 7, "after the weekly reset the reason gives again")
GetServerTime = realNow
GuildOS.RaidTracker = nil
check(P:AwardReason(K("Cy"), "nothing") == nil, "a reason the guild never set gives nothing")
check(P:SetReason("gold") and #P:GetReasons() == 1, "a reason with no value is removed")

-- ── Decay rounding ──────────────────────────────────────────────────
local function decayOf(points, how)
  GuildOS.db.points.standings = { [K("Eve")] = { current = points, earned = points, spent = 0, name = "Eve" } }
  cfg.decayRound = how
  P:ApplyDecay(10)
  return points - P:Get(K("Eve"))
end
check(decayOf(14, nil) == 1 and decayOf(15, nil) == 2, "to the nearest, as before: 1.4 is 1 and 1.5 is 2")
check(decayOf(11, "up") == 2 and decayOf(10, "up") == 1, "up: 1.1 is 2, and 1 stays 1")
check(decayOf(19, "down") == 1, "down: 1.9 is 1")
check(decayOf(0, "up") == 0, "and nothing decays from nothing")
cfg.decayRound = nil

-- ── The raid's end ──────────────────────────────────────────────────
-- Two officers' clients, each with its own copy of the pool and its own session of the same raid: Lead,
-- who leads it, zoned in first and Off thirty-seven seconds later, so the two sessions start apart.
-- (This check used to end one session object twice on one client, which could not fail: the awards
-- were named after the session's start, each client's own, and two clients paid the raid twice.)
GuildOS.db.points.standings = {}
cfg.onTimeAward, cfg.lateAward, cfg.stayedAward, cfg.leftEarlyAward, cfg.raidAward = 2, 1, 2, 1, 5
local poolLead = GuildOS.db.points
local function emptyPool() return { mode = "dkp", config = cfg, standings = {}, log = {}, appliedOps = {}, appliedCount = 0 } end
local poolOff = emptyPool()
local wire = {}
GuildOS.SyncService = { Publish = function(_, _, act, data) wire[#wire + 1] = { act = act, data = data } end }
local function client(name, pool) player = name; GuildOS.db.points = pool end
local function hears() for _, env in ipairs(wire) do P:OnSync(env) end end
local LEAD, OFF = K("Lead Er"), K("Off Er")
local function raidOf(start, leader, late)
  return { instanceID = 249, leader = leader, startTime = start, endTime = 1791000000, snapshots = {
    { time = 1, members = { [K("Ana")] = true, [K("Bo")] = true, [K("Cy")] = (not late) or nil } },
    { time = 2, members = { [K("Ana")] = true, [K("Bo")] = true, [K("Cy")] = true } },
    { time = 3, members = { [K("Ana")] = true, [K("Cy")] = true } },
  } }
end
local session = raidOf(1790990000, LEAD, true)
check(P:OnRaidEnd(session) == 0, "with the auto-award off, a raid's end gives nothing")
cfg.autoAward = true
client("Off", poolOff)
check(P:OnRaidEnd(raidOf(1790990037, LEAD, true)) == 0 and P:Get(K("Ana")) == 0,
  "the client of an officer who does not lead the raid pays nothing")
client("Lead", poolLead)
check(P:OnRaidEnd(session) == 9, "the leader's client gives three awards to each of the three")
check(P:Get(K("Ana")) == 9, "there from the start to the end: 2 + 2 + 5")
check(P:Get(K("Bo")) == 8, "left early: 2 + 1 + 5")
check(P:Get(K("Cy")) == 8, "arrived late: 1 + 2 + 5")
check(P:OnRaidEnd(session) == 0 and P:Get(K("Ana")) == 9, "ended again on the same client: nothing twice")
client("Off", poolOff)
hears()
check(P:Get(K("Ana")) == 9 and P:Get(K("Cy")) == 8, "the other officer's client hears the awards once")
-- The lead passes to Off before Off's session closes, and Off's client saw Cy there from the start.
check(P:OnRaidEnd(raidOf(1790990037, OFF, false)) == 0 and P:Get(K("Ana")) == 9 and P:Get(K("Cy")) == 8,
  "a second client that ends the same raid, its session begun 37 seconds apart, pays nothing again")
hears()
check(P:Get(K("Ana")) == 9, "and hearing the same awards again changes nothing")
check(P:RaidNight(raidOf(1790990000)) == P:RaidNight(raidOf(1790990037))
  and P:RaidNight(raidOf(1790990000)) ~= P:RaidNight(raidOf(1790990000 + 86400)), "the raid night is the same on both, and another the day after")
-- A leader who is no officer: the officer the session saw whose key sorts first pays, on every client.
local isOfficerByName = GuildOS.IsOfficerByName
GuildOS.IsOfficerByName = function(_, name) return name == LEAD or name == OFF end
local function pugRaid(start)
  return { instanceID = 249, leader = K("Pug"), startTime = start, endTime = 1791090000, snapshots = {
    { time = 1, members = { [K("Ana")] = true, [LEAD] = true, [OFF] = true } } } }
end
client("Off", emptyPool())
check(P:OnRaidEnd(pugRaid(1791080037)) == 0, "with a leader who is no officer, the officer second by name pays nothing")
client("Lead", emptyPool())
check(P:OnRaidEnd(pugRaid(1791080000)) == 9 and P:Get(K("Ana")) == 9, "and the first by name pays, alone")
GuildOS.IsOfficerByName = isOfficerByName
GuildOS.SyncService = nil
client("Lead", poolLead)
cfg.autoAward = false
cfg.onTimeAward, cfg.lateAward, cfg.stayedAward, cfg.leftEarlyAward, cfg.raidAward = 0, 0, 0, 0, 0

-- ── A roll that costs to enter ──────────────────────────────────────
local LINK = "|cffa335ee|Hitem:16914::::::::60:::::|h[Netherwind Crown]|h|r"
function GetItemInfo() return "Netherwind Crown", LINK, 4, 76, 60, "Armor", "Cloth", 1, "INVTYPE_HEAD" end
GuildOS.db.points.standings = {}
cfg.entryCost, cfg.refundPct = 4, 50
P:Award(K("Ana"), 10, "x"); P:Award(K("Bo"), 10, "x"); P:Award(K("Cy"), 3, "x")
local rule = LR:Active()
check(rule.filters[1] and rule.filters[1].k == "points" and rule.filters[1].min == 4, "the rule closes the roll to whoever cannot pay it")
LM.GetPlayerContext = function() return { att25 = 100, recvThisLockout = 0 } end
said = {}
LM.activeLoot = { link = LINK, itemId = 16914 }
LM.rolls = {}
LM:RegisterRoll("Ana", "MS", 50)
LM:RegisterRoll("Bo", "MS", 90)
LM:RegisterRoll("Cy", "MS", 99)
check(LM.rolls[K("Cy")] == nil and said[#said]:find("not in this roll", 1, true), "3 points against 4 to enter: out, and told why")
LM:EndRolling(true)
LM.pendingTrades = {}
LM:AwardLoot("Bo", true)
check(P:Get(K("Bo")) == 6, "the winner pays the 4 to enter")
check(P:Get(K("Ana")) == 8, "whoever lost pays 4 and gets 2 back")
check(P:Get(K("Cy")) == 3, "and whoever was out pays nothing")
local lost
for _, e in ipairs(GuildOS.db.points.log) do
  if e.key == K("Ana") and e.delta == -2 then lost = e end
end
check(lost and lost.reason:find("4 paid, 2 back", 1, true), "the history says what was paid and what came back")
local award = LM:LastAward()
check(award and award.paid and #award.paid == 2, "the award keeps what each paid")
LM:UndoLastAward()
check(P:Get(K("Bo")) == 10 and P:Get(K("Ana")) == 10, "and an undo gives every one of them back what they paid")
cfg.entryCost, cfg.refundPct = 0, 0
check(#LR:Active().filters == 0, "with no cost to enter, the roll is open again")

-- ── EPGP ────────────────────────────────────────────────────────────
GuildOS.db.points.standings = {}
GuildOS:SetLootSystem("epgp")
check(P:GetMode() == "epgp", "choosing the EPGP system puts the points in EPGP")
check(GuildOS:LootSystemUsesPoints() and GuildOS:LootSystemShowsDKP(), "and it runs on the points window")
cfg.itemCost, cfg.baseGP, cfg.minEP, cfg.gpRefIlvl = 100, 50, 0, 0
P:Award(K("Ana"), 300, "boss"); P:Award(K("Bo"), 300, "boss"); P:Award(K("Cy"), 100, "boss")
check(P:EP(K("Ana")) == 300 and P:GP(K("Ana")) == 50 and P:PR(K("Ana")) == 6, "priority is EP over GP plus the base")
check(P:PriceOf(LINK) == 100, "a head costs what a chest does")
function GetItemInfo() return "Ring", LINK, 4, 76, 60, "Armor", "Misc", 1, "INVTYPE_FINGER" end
check(P:PriceOf(LINK) == 50, "a ring half of it")
cfg.gpRefIlvl = 50
check(P:PriceOf(LINK) == 100, "26 item levels above the reference, twice: 50 becomes 100")
cfg.gpRefIlvl = 0
P:SetItemPrice(16914, 77)
check(P:PriceOf(LINK) == 77, "the guild's own price for an item comes before any of it")
P:SetItemPrice(16914, 0)
function GetItemInfo() return "Netherwind Crown", LINK, 4, 76, 60, "Armor", "Cloth", 1, "INVTYPE_HEAD" end

check(LR:Active().order[2].k == "pr", "the EPGP rule reads priority after the answer")
LM.activeLoot = { link = LINK, itemId = 16914 }
LM.rolls = {}
LM:RegisterRoll("Ana", "MS", 5)
LM:RegisterRoll("Bo", "MS", 99)
LM:RegisterRoll("Cy", "MS", 100)
P:Charge(K("Bo"), 100, "an earlier item")
LM.rolls[K("Bo")].pr = P:PR(K("Bo"))
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "Ana" and LM.activeLoot.decidedBy == "pr",
  "the highest priority wins over the highest roll")
LM:AwardLoot("Ana", true)
check(P:GP(K("Ana")) == 150 and P:EP(K("Ana")) == 300 and P:PR(K("Ana")) == 2, "the award adds the item's GP, and EP stays")
LM:UndoLastAward()
check(P:GP(K("Ana")) == 50 and P:EP(K("Ana")) == 300, "an undo takes the GP back off, and adds no EP")

cfg.minEP = 200
check(P:PR(K("Cy")) < P:PR(K("Bo")), "under the minimum EP comes after everyone who has it")
cfg.minEP = 0

P:ApplyDecay(10)
check(P:EP(K("Bo")) == 270 and P:GP(K("Bo")) == 140, "decay takes a tenth of EP and of GP: 300 and 100 become 270 and 90, plus the base")
local list = P:GetStandings()
check(list[1].pr and list[1].pr >= list[2].pr and list[2].pr >= list[3].pr, "the standings read by priority")

GuildOS:SetLootSystem("dkp")
check(P:GetMode() == "dkp" and P:EP(K("Bo")) == 270, "back to DKP, the same rows are still there")

print(("loot-points: %d checks passed"):format(checks))
