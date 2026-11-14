-- The addon reads what the site emits (guildos-web#516), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Modules/CoreManager.lua, Modules/RaidTracker.lua,
-- Modules/Points.lua, Modules/LootRule.lua, Modules/LootMaster.lua, Modules/CompanionImport.lua and
-- Modules/RaidPlan.lua, with the rules the site's fourteen ready-made models emit at their default
-- answers (tools/data/loot-rule-models.json, written from apps/web/lib/loot-rule-models.ts):
--   * every model either reads whole and a small roll ends in the order the model documents, or is
--     refused whole with the piece of the contract this client does not apply yet. Since issue #337 the
--     rare systems play too (SR+, karma, Suicide Kings, zero-sum, a summed score), each with the effects
--     its model documents;
--   * the pieces behind them: who may ask (an account's least, a reserve, the night's limit, block or
--     downgrade), the order (any account high or low, a ratio, a hard reserve) and what an award
--     changes (a share of the balance, the price to enter, a counter emptied or charged);
--   * a counter the rule feeds per raid and per boss;
--   * the rule comes with the night's roster (GOSROST1 v5): read as untrusted input, in force for
--     that raid over the core's and the guild's, frozen for the night, refused whole when this
--     client cannot read it, with one line in the plan window that says so.
--
--   luajit -e 'ADDON="."' tools/loot-contract.lua
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
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/RaidPlan.lua")
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
-- What the raid tracker and the lists say of each raider, set by each scene.
local att, recv, reserves, prios, wishes = {}, {}, {}, {}, {}
LM.GetPlayerContext = function(_, name) return { att25 = att[name] or 100, recvThisLockout = recv[name] or 0 } end
LM.ShowRollFrame = function() end
LM.StopListeningForRolls = function() end
function GuildOS:Print(msg) printed[#printed + 1] = msg end
local shown = 0
function GuildOS:UpdateLootSystemUI() shown = shown + 1 end
local function quiet() said, sent, printed, published = {}, {}, {}, {} end
local function all(list) return table.concat(list, "\n") end
local function activate(name) RT:SetGroupTag(name) end

GuildOS.Companion = { IsEnabled = function() return true end }
GuildOS.SoftRes = {
  GetReserves = function() return reserves end,
  GetInRaidReserves = function() return {} end,
}
GuildOS.Wishlist = { GetItemInterest = function() return wishes end }
local Import, Plan = GuildOS.CompanionImport, GuildOS.RaidPlan
local LD = LibStub("LibDeflate")

local LINK = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r"
local ITEM = 28770

-- ── The site's rules, as the site wrote them ────────────────────────
local text = assert(io.open(ADDON .. "/tools/data/loot-rule-models.json", "rb")):read("*a")
local fixtures = GuildOS.JsonDecode(text)
check(type(fixtures) == "table" and type(fixtures.models) == "table", "the fixtures read")
-- One rule's own JSON, cut from the file: what goes inside the roster's string.
local function jsonOf(name)
  local line = text:match('\n "' .. name:gsub("%p", "%%%0") .. '": (%b{})')
  check(line, "the fixture holds " .. name)
  return line
end
local MODELS = { "rolls", "plus1", "softres", "srplus", "hardres", "wishlist", "council", "dkp", "dkpbid",
  "zerosum", "epgp", "sk", "karma", "ranked" }
local count = 0
for _ in pairs(fixtures.models) do count = count + 1 end
check(count == #MODELS, "fourteen models, as the site has")

-- A roster from the site carrying a rule, as the wire string the companion writes.
local function wire(raidId, startsAt, ruleJson)
  local json = string.format('{"fmt":"GOSROST1","v":5,"raidId":"%s","title":"Raid %s","startsAt":%d,'
    .. '"instanceKey":"kara","members":[{"key":"Ana","name":"Ana","class":"MAGE"}]%s}',
    raidId, raidId, startsAt, ruleJson and (',"lootRule":' .. ruleJson) or "")
  return "GOSROST1:" .. LD:EncodeForPrint(LD:CompressDeflate(json))
end
-- The night starts over: nothing kept, nothing in hand.
local function dawn()
  GuildOS.db.lootNight, GuildOS.db.companionRoster, LR.nightSeen, LR.nightKept = nil, nil, nil, nil
  LM.activeLoot, LM.rolls = nil, {}
  GuildOS.db.lootMaster.awardHistory = {}
  GuildOS.db.points = {}
  P:Initialize()
  att, recv, reserves, prios, wishes = {}, {}, {}, {}, {}
  GuildOS.db.lootPrios = { [ITEM] = prios }
end
local raidSeq = 0
-- The roster of tonight's raid arrives with this rule.
local function tonight(ruleJson)
  dawn()
  raidSeq = raidSeq + 1
  local n, err = Import:Load(wire("r" .. raidSeq, NOW, ruleJson))
  check(n == 1, "the roster loads (" .. tostring(err) .. ")")
  return GuildOS.db.companionRoster
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

-- ── 1. Every model: read whole and played, or refused whole ─────────
local supported, refused = {}, {}
local function plays(name)
  local ok, why = LR:Validate(fixtures.models[name] or fixtures.variants[name])
  check(ok, name .. " is a rule this client reads whole (" .. tostring(why) .. ")")
  local roster = tonight(jsonOf(name))
  check(LR:Active().model == (name:match("^[^:]+")) and GuildOS.db.lootNight ~= nil,
    name .. ": the night's rule is the one in force")
  check((LR:NightStatus()) == "active", name .. ": and the plan window can say so")
  supported[#supported + 1] = name
  return roster
end
local function isRefused(name, piece)
  local rule = fixtures.models[name] or fixtures.variants[name]
  local ok, why = LR:Validate(rule)
  check(ok == false and why == "unsupported: " .. piece, name .. " is refused for " .. piece .. " (" .. tostring(why) .. ")")
  check(LR:Unsupported(why) == piece and LR:UnsupportedText(piece), name .. ": and the piece has words")
  tonight(jsonOf(name))
  check(LR:Night() == nil and LR:Active().model == "rolls" and GuildOS.db.lootNight == nil,
    name .. ": refused whole, the guild's rule stays in force")
  local state, _, missing = LR:NightStatus()
  check(state == "refused" and missing == piece, name .. ": the refusal names what is missing")
  local line, warning = Plan:LootRuleLine()
  check(warning and line:find("needs a newer GuildOS", 1, true) and line:find(LR:UnsupportedText(piece), 1, true),
    name .. ": the plan window says it in one line: " .. tostring(line))
  announce()
  check(LM.activeLoot.rule.model == "rolls" and not LM.activeLoot.night, name .. ": and an item is announced by the guild's rule")
  LM:CancelRolling()
  refused[#refused + 1] = name
end

-- rolls: the answer, then fewer items received, then the roll. The master looter decides.
plays("rolls")
recv = { Bo = 1 }
announce()
check(said[1]:find("[ROLL]", 1, true) and said[1]:find("30s", 1, true), "rolls: announced as a roll, for the rule's 30 seconds")
LM:RegisterRoll("Ana", "MS", 10)
LM:RegisterRoll("Bo", "MS", 90)
LM:RegisterRoll("Cy", "OS", 100)
check(order() == "Ana,Bo,Cy", "rolls: MS before OS, fewer items received before the roll: " .. order())
check(LM.activeLoot ~= nil and not LM.activeLoot.delivered, "rolls: the order names the winner and the master looter's click gives the item")
LM:CancelRolling()

-- plus1: the answer, then whoever has fewer +1 this lockout, then the roll.
plays("plus1")
check(LR:Counters()[1].key == "plus1" and LR:Counters()[1].reset == "lockout", "plus1: the counter resets per lockout")
P:AddCounter("plus1", K("Bo"), 1, "lockout")
announce()
LM:RegisterRoll("Ana", "MS", 10)
LM:RegisterRoll("Bo", "MS", 90)
LM:RegisterRoll("Cy", "OS", 100)
check(order() == "Ana,Bo,Cy", "plus1: no +1 before one +1, whatever the roll: " .. order())
LM:AwardLoot("Ana")
check(P:Counter("plus1", K("Ana")) == 1, "plus1: winning main spec counts")
announce()
LM:RegisterRoll("Cy", "OS", 5)
LM:EndRolling(true)
LM:AwardLoot("Cy")
check(P:Counter("plus1", K("Cy")) == 0, "plus1: winning off spec does not, by default")

-- softres: a reserve before the answer, then the roll.
plays("softres")
reserves = { { name = "Cy" } }
announce()
LM:RegisterRoll("Ana", "MS", 99)
LM:RegisterRoll("Bo", "OS", 50)
LM:RegisterRoll("Cy", "OS", 1)
check(order() == "Cy,Ana,Bo", "softres: the reserve wins over a main spec roll: " .. order())
LM:CancelRolling()

-- hardres: a hard reserve, then a soft one, then the answer, then the roll.
plays("hardres")
reserves = { { name = "Cy" }, { name = "Dee", hard = true } }
announce()
LM:RegisterRoll("Ana", "MS", 99)
LM:RegisterRoll("Cy", "OS", 50)
LM:RegisterRoll("Dee", "OS", 1)
check(order() == "Dee,Cy,Ana", "hardres: hard before soft before none: " .. order())
LM:CancelRolling()

-- wishlist: the answer, officer priority, wishlist place, fewer received, the roll. The night's rule
-- opens its roll for everyone: none of the wishlist shortcuts of the loot systems of before.
plays("wishlist")
prios[1] = { name = "Bo" }
wishes = { { name = "Ana", order = 1 }, { name = "Cy", order = 1 } }
announce()
check(LM.activeLoot.night and LM.restrictedRollers == nil and said[1]:find("[ROLL]", 1, true),
  "wishlist: two raiders tied on the wishlist do not close the roll to the rest")
LM:RegisterRoll("Ana", "MS", 99)
LM:RegisterRoll("Bo", "MS", 2)
LM:RegisterRoll("Cy", "MS", 50)
LM:RegisterRoll("Dee", "MS", 100)
check(order() == "Bo,Ana,Cy,Dee", "wishlist: officer priority, then the wishlist, then the roll: " .. order())
LM:CancelRolling()

-- dkp: the answer, then the points, then the roll; a fixed price, off spec for half.
plays("dkp")
check(GuildOS:GetLootSystem() == "dkp" and GuildOS:LootSystemUsesPoints() and GuildOS:LootSystemShowsDKP(),
  "dkp: with the night's rule in force the loot system reads as DKP, whatever the guild chose")
check(GuildOS:GetLootSystem("") == "rolls", "dkp: and the guild's own choice is untouched")
P:Award(K("Ana"), 50, "seed")
P:Award(K("Bo"), 80, "seed")
P:Award(K("Cy"), 30, "seed")
announce()
check(said[1]:find("[DKP]", 1, true), "dkp: announced as a DKP roll: " .. tostring(said[1]))
LM:RegisterRoll("Ana", "MS", 99)
LM:RegisterRoll("Bo", "MS", 1)
LM:RegisterRoll("Cy", "OS", 100)
check(order() == "Bo,Ana,Cy", "dkp: more points before fewer, MS before OS: " .. order())
LM:AwardLoot("Bo")
check(P:Get(K("Bo")) == 70, "dkp: the winner pays the rule's fixed 10")
announce()
LM:RegisterRoll("Cy", "OS", 100)
LM:EndRolling(true)
LM:AwardLoot("Cy")
check(P:Get(K("Cy")) == 25, "dkp: and off spec pays half")

-- dkpbid: whoever cannot bid the least is out; the highest bid wins and is what the winner pays.
plays("dkpbid")
P:Award(K("Ana"), 100, "seed")
P:Award(K("Bo"), 60, "seed")
announce()
check(sent[1]:find("=b", 1, true) and LM.activeLoot.rule.time == 45, "dkpbid: the buttons ask for a bid, for 45 seconds")
check(LM:TakeAnswer("Bo", "MS", 50) and LM:TakeAnswer("Ana", "MS", 70), "dkpbid: two open bids are in, each over the last")
check(LM:RegisterRoll("Dee", "MS", nil, { bid = 1 }) == nil and all(said):find("Dee: not in this roll (0 points, 1 needed to enter)", 1, true),
  "dkpbid: with less than the least bid in points, no roll: " .. tostring(said[#said]))
check(order() == "Ana,Bo", "dkpbid: the highest bid first: " .. order())
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 30, "dkpbid: the winner pays their bid")

-- epgp: the answer, then EP over GP (the rule's own base GP of 100), then the roll; the item's GP.
plays("epgp")
GuildOS.db.points.config.itemCost = 40
P:Award(K("Ana"), 300, "seed")
P:Award(K("Bo"), 500, "seed")
P:Charge(K("Bo"), 400, "an item")
announce()
check(said[1]:find("[EPGP]", 1, true), "epgp: announced as an EPGP roll: " .. tostring(said[1]))
LM:RegisterRoll("Ana", "MS", 1)
LM:RegisterRoll("Bo", "MS", 99)
check(LM.rolls[K("Ana")].ep == 300 and LM.rolls[K("Bo")].gp == 400, "epgp: a candidate carries what was earned and what was spent")
check(order() == "Ana,Bo", "epgp: 300 / 100 before 500 / 500, whatever the roll: " .. order())
check(LM.activeLoot.decidedBy == "ratio", "epgp: and the ratio is what decided")
LM:AwardLoot("Ana")
check(P:GP(K("Ana")) == 40, "epgp: the winner's GP grows by the item's price on the guild's table")

-- ranked: the answer, officer priority, the wishlist, whoever waited longer, attendance in steps, the roll.
plays("ranked")
P:AddCounter("wait", K("Ana"), 3, "never")
P:AddCounter("wait", K("Bo"), 1, "never")
att = { Cy = 100, Ana = 80, Bo = 80 }
announce()
LM:RegisterRoll("Ana", "MS", 1)
LM:RegisterRoll("Bo", "MS", 99)
LM:RegisterRoll("Cy", "MS", 50)
check(order() == "Ana,Bo,Cy", "ranked: three raids waited before one before none: " .. order())
LM:AwardLoot("Ana")
check(P:Counter("wait", K("Ana")) == 0 and P:Counter("wait", K("Bo")) == 1, "ranked: the winner's wait ends with the item")
check(LM:UndoLastAward() and P:Counter("wait", K("Ana")) == 3, "ranked: and an undo gives the wait back")
-- The wait is fed by each raid attended, once whoever ends it.
local session = { startTime = NOW - 7200, endTime = NOW, snapshots = { { members = { [K("Ana")] = true, [K("Cy")] = true } } } }
quiet()
check(P:OnRaidEnd(session) == 0, "ranked: with the points' own awards off, the raid's end gives no points")
check(P:Counter("wait", K("Ana")) == 4 and P:Counter("wait", K("Cy")) == 1 and P:Counter("wait", K("Bo")) == 1,
  "ranked: a raid attended adds one to the wait of whoever was there")
check(published[1] and published[1].act == "cdelta" and #published[1].data.entries == 2, "ranked: told to the officers as the counters' own entries")
P:OnRaidEnd(session)
check(P:Counter("wait", K("Ana")) == 4, "ranked: the same raid ended twice counts once")

-- srplus (issue #337): a reserve, the answer, then the roll with the SR+ account added to a main spec
-- roll. The account grows by ten a raid attended, up to fifty, and the winner's goes back to nothing.
plays("srplus")
check(LR:RollBonus() == "srplus" and LR:Counter("srplus").type == "bonus", "srplus: the roll adds the SR+ account")
P:AddCounter("srplus", K("Ana"), 30, "never")
P:AddCounter("srplus", K("Dee"), 45, "never")
reserves = { { name = "Ana" }, { name = "Bo" } }
announce()
LM:RegisterRoll("Ana", "MS", 40)
LM:RegisterRoll("Bo", "MS", 60)
LM:RegisterRoll("Cy", "MS", 100)
LM:RegisterRoll("Dee", "OS", 99)
check(order() == "Ana,Bo,Cy,Dee", "srplus: among who reserved, 40 + 30 beats 60; no reserve after them; off spec last: " .. order())
check(LR:BonusOf(LM.activeLoot.sortedResults[1], LM:Rule()) == 30 and LR:BonusOf(LM.activeLoot.sortedResults[4], LM:Rule()) == 0,
  "srplus: the bonus is a main spec roll's, never an off spec one's")
check(LM.activeLoot.decidedBy == "roll" and all(said):find("Ana - MS (40 + 30)", 1, true), "srplus: the winner line says the roll and the bonus apart: " .. all(said))
LM:AwardLoot("Ana")
check(P:Counter("srplus", K("Ana")) == 0 and P:Counter("srplus", K("Dee")) == 45, "srplus: the winner's SR+ goes back to nothing, nobody else's moves")
check(LM:UndoLastAward() and P:Counter("srplus", K("Ana")) == 30, "srplus: and an undo gives it back")
session = { startTime = NOW - 7200, endTime = NOW, snapshots = { { members = { [K("Ana")] = true, [K("Dee")] = true, [K("Bo")] = true } } } }
P:OnRaidEnd(session)
check(P:Counter("srplus", K("Ana")) == 40 and P:Counter("srplus", K("Bo")) == 10 and P:Counter("srplus", K("Dee")) == 50,
  "srplus: a raid attended adds ten, never past the cap of fifty")

isRefused("council", "council")

-- zerosum (issue #337): the answer, the points, the roll; a fixed price of ten, off spec for half, and
-- what was paid goes back to whoever is in the raid in equal shares, the remainder dropped.
plays("zerosum")
P:Award(K("Ana"), 50, "seed")
P:Award(K("Bo"), 80, "seed")
announce()
LM:RegisterRoll("Ana", "MS", 99)
LM:RegisterRoll("Bo", "MS", 1)
check(order() == "Bo,Ana", "zerosum: more points first: " .. order())
quiet()
LM:AwardLoot("Bo")
check(P:Get(K("Bo")) == 72 and P:Get(K("Ana")) == 52 and P:Get(K("Lead")) == 2 and P:Get(K("Cy")) == 2 and P:Get(K("Dee")) == 2,
  "zerosum: the winner pays ten and each of the five in the raid gets two")
local total = 0
for _, name in ipairs(raid) do total = total + P:Get(K(name)) end
check(total == 130, "zerosum: the raid's points add up to what they were: " .. total)
check(#published == 2 and #published[2].data.entries == 5 and published[2].data.entries[1].kind == "split",
  "zerosum: each share is an entry of the log, told to the officers")
check(LM:UndoLastAward() and P:Get(K("Bo")) == 80 and P:Get(K("Ana")) == 50 and P:Get(K("Cy")) == 0, "zerosum: an undo takes every share back")
announce()
LM:RegisterRoll("Ana", "OS", 5)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 46 and P:Get(K("Cy")) == 1, "zerosum: off spec pays five, one each")

-- sk (issue #337): main spec goes to whoever is highest on the list, with no roll, and the winner
-- drops to the end; off spec is a free roll, and moves nobody.
plays("sk")
check(LR:Queue("sk") and not LR:Queue("sk").frozen, "sk: a queue account, as the site emits it")
announce()
check(table.concat(P:Queue("sk"), ",") == table.concat({ K("Ana"), K("Bo"), K("Cy"), K("Dee"), K("Lead") }, ","),
  "sk: the raid joins the list when the first item is announced: " .. table.concat(P:Queue("sk"), ","))
check(LM:TakeAnswer("Cy", "MS") and LM:TakeAnswer("Bo", "MS") and LM:TakeAnswer("Dee", "OS"), "sk: answers are in")
check(LM.rolls[K("Cy")].roll == nil and LM.rolls[K("Dee")].roll ~= nil, "sk: main spec asks for no roll, off spec for one")
check(order() == "Bo,Cy,Dee", "sk: higher on the list first, main spec before off spec: " .. order())
check(LM.activeLoot.decidedBy == "account", "sk: and the list is what decided")
LM:AwardLoot("Bo")
check(table.concat(P:Queue("sk"), ",") == table.concat({ K("Ana"), K("Cy"), K("Dee"), K("Lead"), K("Bo") }, ","),
  "sk: the winner drops to the end and everyone below moves up: " .. table.concat(P:Queue("sk"), ","))
announce()
LM:TakeAnswer("Dee", "OS")
LM:EndRolling(true)
LM:AwardLoot("Dee")
check(P:QueuePos("sk", K("Dee")) == 3, "sk: an off spec win moves nobody")
check(LM:UndoLastAward() and LM:UndoLastAward() and table.concat(P:Queue("sk"), ",") == table.concat({ K("Ana"), K("Bo"), K("Cy"), K("Dee"), K("Lead") }, ","),
  "sk: an undo gives back the exact order")

-- karma (issue #337): the answer, then the roll with the karma added to a main spec roll. The winner
-- with karma loses half of it; an off spec win costs nothing.
plays("karma")
P:AddCounter("karma", K("Ana"), 41, "never")
P:AddCounter("karma", K("Bo"), 10, "never")
announce()
LM:RegisterRoll("Ana", "MS", 30)
LM:RegisterRoll("Bo", "MS", 60)
LM:RegisterRoll("Cy", "OS", 100)
check(order() == "Ana,Bo,Cy", "karma: 30 + 41 beats 60 + 10: " .. order())
LM:AwardLoot("Ana")
check(P:Counter("karma", K("Ana")) == 20 and P:Counter("karma", K("Bo")) == 10, "karma: the winner loses half, rounded: " .. P:Counter("karma", K("Ana")))
announce()
LM:RegisterRoll("Bo", "OS", 50)
LM:EndRolling(true)
LM:AwardLoot("Bo")
check(P:Counter("karma", K("Bo")) == 10, "karma: an off spec win, rolled without karma, costs none")
check(LM:UndoLastAward() and LM:UndoLastAward() and P:Counter("karma", K("Ana")) == 41, "karma: an undo gives it back")
session = { startTime = NOW - 3600, endTime = NOW, snapshots = { { members = { [K("Ana")] = true } } } }
P:AddCounter("karma", K("Ana"), 57, "never")
P:OnRaidEnd(session)
check(P:Counter("karma", K("Ana")) == 100, "karma: five a raid attended, never past the cap of a hundred: " .. P:Counter("karma", K("Ana")))

local modelsPlayed, modelsRefused = #supported, #refused
check(modelsPlayed == 13 and modelsRefused == 1, string.format("thirteen models play and one waits: %d and %d", modelsPlayed, modelsRefused))
for _, name in ipairs(MODELS) do
  local found = false
  for _, n in ipairs(supported) do found = found or n == name end
  for _, n in ipairs(refused) do found = found or n == name end
  check(found, name .. " was either played or refused")
end

-- ── 2. The same models with other answers ───────────────────────────
-- softres, only who reserved, two items a night at most.
plays("softres:onlyReserved")
reserves = { { name = "Ana" }, { name = "Bo" } }
recv = { Bo = 2 }
announce()
check(LM:RegisterRoll("Cy", "MS", 99) == nil and said[#said]:find("Cy: not in this roll (the item was not reserved)", 1, true),
  "without a reserve on the item, no roll: " .. tostring(said[#said]))
check(LM:RegisterRoll("Bo", "MS", 99) == nil and said[#said]:find("2 items received tonight, the limit is 2", 1, true),
  "nor at the night's limit: " .. tostring(said[#said]))
check(LM:RegisterRoll("Bo", "PASS", 0) ~= nil, "a pass is nobody's to refuse")
check(LM:RegisterRoll("Ana", "MS", 1) ~= nil and order() == "Ana", "who reserved and has room rolls")
LM:CancelRolling()

-- rolls with a least attendance: below it a main spec answer is read as off spec, as always.
plays("rolls:minAtt")
att = { Ana = 40, Bo = 95, Cy = 91 }
announce()
LM:RegisterRoll("Ana", "MS", 100)
check(LM.rolls[K("Ana")].rollType == "OS" and said[#said]:find("MS converted to OS (attendance 40% below minimum 50%)", 1, true),
  "the line of before: " .. tostring(said[#said]))
LM:RegisterRoll("Bo", "MS", 5)
LM:RegisterRoll("Cy", "MS", 50)
check(order() == "Cy,Bo,Ana", "95% and 91% fall in the same step of ten, so the roll decides between them: " .. order())
LM:CancelRolling()

plays("dkpbid:second")
P:Award(K("Ana"), 100, "seed")
P:Award(K("Bo"), 60, "seed")
announce()
LM:TakeAnswer("Bo", "MS", 50)
LM:TakeAnswer("Ana", "MS", 70)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 49, "second price: one step over the bid that was beaten")

plays("epgp:fixed")
P:Award(K("Ana"), 300, "seed")
P:Award(K("Bo"), 50, "seed")
announce()
check(LM:RegisterRoll("Bo", "MS", 99) == nil and said[#said]:find("EP: 50, 100 needed", 1, true), "below the least EP, no roll: " .. tostring(said[#said]))
LM:RegisterRoll("Ana", "OS", 1)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:GP(K("Ana")) == 25, "a fixed GP price, and off spec for half of it")

-- karma, losing all of it.
plays("karma:all")
P:AddCounter("karma", K("Ana"), 41, "never")
announce()
LM:RegisterRoll("Ana", "MS", 30)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Counter("karma", K("Ana")) == 0, "karma, all of it: the winner's karma is gone")

-- ranked by a summed score: officer priority (first place ten points), a tenth of the attendance, and
-- the raids waited.
plays("ranked:score")
prios[1] = { name = "Bo" }
att = { Ana = 80, Bo = 50, Cy = 100 }
P:AddCounter("wait", K("Ana"), 3, "never")
announce()
LM:RegisterRoll("Ana", "MS", 1)
LM:RegisterRoll("Bo", "MS", 2)
LM:RegisterRoll("Cy", "MS", 99)
check(order() == "Bo,Ana,Cy", "score: 10 + 5 + 0 before 0 + 8 + 3 before 0 + 10 + 0: " .. order())
local score, parts = LR:ScoreOf(LM.rolls[K("Ana")], LM:Rule())
check(score == 11 and #parts == 3 and parts[2].k == "attendance" and parts[2].points == 8 and parts[3].points == 3,
  "score: the total and its parts are there for the window to show")
check(LM.activeLoot.decidedBy == "score", "score: and the score is what decided")
LM:CancelRolling()

-- zero-sum by bids: the winner pays the bid, shared among the raid, the remainder dropped.
plays("zerosum:bid")
P:Award(K("Ana"), 100, "seed")
P:Award(K("Bo"), 60, "seed")
announce()
LM:TakeAnswer("Bo", "MS", 50)
LM:TakeAnswer("Ana", "MS", 73)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 41 and P:Get(K("Bo")) == 74 and P:Get(K("Cy")) == 14, "zero-sum by bids: 73 paid, 14 to each of five, 3 dropped")

-- ── 3. The pieces, one at a time ────────────────────────────────────
local function rule(more)
  local r = { v = 1, model = "custom", order = { { k = "response" }, { k = "roll" } } }
  for k, v in pairs(more or {}) do r[k] = v end
  return r
end
local function reads(r, what) local ok, why = LR:Validate(r); check(ok, what .. " (" .. tostring(why) .. ")") end
local function no(r, why, what)
  local ok, got = LR:Validate(r)
  check(ok == false and (why == nil or got == why), "refused: " .. what .. " (" .. tostring(got) .. ")")
end
local wait = { key = "wait", type = "counter" }

-- Who may ask.
reads(rule({ filters = { { k = "account", acct = "dkp", min = 4, act = "block" } } }), "an account's least, on the points")
reads(rule({ accounts = { wait }, filters = { { k = "account", acct = "wait", min = 1, act = "downgrade", from = "MS", to = "OS" } } }),
  "a counter's least, downgrading")
reads(rule({ filters = { { k = "attendance", min = 50, act = "block" } } }), "attendance that blocks")
reads(rule({ filters = { { k = "reserved", act = "downgrade", from = "MS", to = "OS" } } }), "no reserve that downgrades")
no(rule({ filters = { { k = "account", acct = "tokens", min = 1, act = "block" } } }), "unknown filter", "a filter on an account nobody declared")
no(rule({ filters = { { k = "received", max = 1.5, act = "block" } } }), "unknown filter", "half an item")
no(rule({ filters = { { k = "received", max = 2, act = "ban" } } }), "unknown filter", "an act it does not know")
no(rule({ filters = { { k = "reserved", act = "block", from = "MS" } } }), "unknown filter", "a block that names an answer")
no(rule({ filters = { { k = "reserved", act = "downgrade", from = "MS", to = "MS" } } }), "unknown filter", "an answer downgraded to itself")
no(rule({ filters = { { k = "reserved", act = "block", why = "x" } } }), "unknown filter", "a field it never heard of")
local c = { att25 = 40, recvCount = 2, dkp = 3, ep = 10, gp = 0, accts = { wait = 0 } }
local filtered = rule({ accounts = { wait }, filters = {
  { k = "attendance", min = 50, act = "downgrade", from = "MS", to = "OS" },
  { k = "account", acct = "dkp", min = 4, act = "block" },
} })
local answer, by = LR:AnswerFor(c, "MS", filtered)
check(answer == nil and by.k == "account", "a downgraded answer is still judged by the filters after it")
c.dkp = 4
answer, by = LR:AnswerFor(c, "MS", filtered)
check(answer == "OS" and by.k == "attendance", "and comes out downgraded when they let it through")
check(LR:AnswerFor(c, "PASS", rule({ filters = { { k = "reserved", act = "block" } } })) == "PASS", "a pass goes through every filter")

-- The order.
reads(rule({ order = { { k = "account", acct = "dkp", dir = "low" }, { k = "account", acct = "ep" }, { k = "roll" } } }),
  "the points' own accounts as criteria, undeclared")
reads(rule({ accounts = { wait }, order = { { k = "ratio", num = "ep", den = "wait" } } }), "a ratio of any two accounts")
no(rule({ order = { { k = "ratio", num = "ep", den = "ep" } } }), "unknown account", "an account over itself")
no(rule({ order = { { k = "ratio", num = "ep" } } }), "unknown account", "a ratio with no divisor")
no(rule({ order = { { k = "roll", bonus = "karma" } } }), "unknown account", "a roll with a bonus nobody declared")
no(rule({ accounts = { wait }, order = { { k = "roll", bonus = "wait" } } }), "unknown account", "a roll with a counter for a bonus")
reads(rule({ accounts = { { key = "karma", type = "bonus", cap = 100 } }, order = { { k = "roll", bonus = "karma" } } }), "a roll with a bonus account")
no(rule({ order = { { k = "upgrade" } } }), "unsupported: upgrade", "the size of the upgrade, which no candidate row carries")
no(rule({ order = { { k = "score", parts = {} } } }), "score", "a score of no parts")
no(rule({ order = { { k = "score", parts = { { k = "roll", w = 1 } } } } }), "score", "a score of a part it does not offer")
no(rule({ order = { { k = "score", parts = { { k = "attendance", w = 0 } } } } }), "score", "a part that weighs nothing")
no(rule({ order = { { k = "score", parts = { { k = "attendance", w = 1, formula = "x*2" } } } } }), "score", "a part with a formula")
reads(rule({ accounts = { wait }, order = { { k = "score", parts = { { k = "wishlist", w = 1 }, { k = "attendance", w = 0.1 }, { k = "account", acct = "wait", w = 1 } } } } }),
  "a summed score, as the contract writes it")
no(rule({ order = { { k = "roll", acct = "dkp" } } }), "unknown criterion", "a field that is another criterion's")
local list = LR:Sort({
  { name = "A", dkp = 10, ep = 100, gp = 0 }, { name = "B", dkp = 5, ep = 100, gp = 100 }, { name = "C", dkp = 7, ep = 500, gp = 50 },
}, rule({ order = { { k = "account", acct = "dkp", dir = "low" } } }))
check(list[1].name == "B" and list[3].name == "A", "an account low first")
LR:Sort(list, rule({ order = { { k = "ratio", num = "ep", den = "gp" } } }))
check(list[1].name == "A" and list[2].name == "C" and list[3].name == "B", "EP over GP, the divisor never under one")
LR:Sort(list, rule({ order = { { k = "ratio", num = "ep", den = "gp" } }, accounts = { { key = "gp", type = "balance", start = 1000 } } }))
check(list[1].name == "C", "and with the rule's own base GP, which changes who is first")

-- The accounts.
reads(rule({ accounts = { { key = "dkp", type = "balance", name = "DKP", start = 0, cap = 500, floor = 0,
  decay = { pct = 10, round = "down" }, earn = { { key = "boss", auto = "boss", value = 3 }, { key = "mats", name = "Mats", value = 1, weekly = 5 } } } } }),
  "the points' own account, declared as the site declares it")
no(rule({ accounts = { { key = "gold", type = "balance" } } }), "unsupported: balance", "a second points account")
no(rule({ accounts = { { key = "wait", type = "counter", cap = 5 } } }), "unsupported: counter", "a counter with a cap")
no(rule({ accounts = { { key = "wait", type = "counter", earn = { { key = "late", auto = "late", value = 1 } } } } }), "unsupported: earn",
  "a counter fed by something this client does not feed it by")
no(rule({ accounts = { { key = "wait", type = "counter", earn = { { key = "mats", value = 1 } } } } }), "unsupported: earn", "a counter fed by hand")
no(rule({ accounts = { { key = "dkp", type = "balance", decay = { pct = 0 } } } }), "accounts", "a decay of nothing")
no(rule({ accounts = { { key = "dkp", type = "balance", colour = "red" } } }), "accounts", "a field it never heard of")
no(rule({ accounts = { wait, wait } }), "accounts", "the same account twice")
no(rule({ colour = "red" }), "unknown field", "a block it never heard of")
no(rule({ decide = { by = "vote" } }), "decide", "a decider it does not know")
no(rule({ decide = { by = "council" } }), "unsupported: council", "a council")
reads(rule({ decide = { by = "auto" } }), "the order decides")
reads(rule({ decide = { by = "holder" } }), "whoever holds the item decides")
reads(rule({ exceptions = { { on = { cat = "recipe" }, to = "bank" } } }), "an exception (tools/loot-exceptions.lua)")
reads(rule({ exceptions = {} }), "no exception at all")

-- What an award changes.
reads(rule({ effects = { { k = "charge", acct = "dkp", price = "fraction", value = 0.5 } } }), "half of what the winner holds")
reads(rule({ effects = { { k = "charge", acct = "dkp", price = "all" } } }), "all of it")
reads(rule({ effects = { { k = "entry", acct = "dkp", value = 4, refund = 0.5 } } }), "a price to enter, half back")
reads(rule({ accounts = { wait }, effects = { { k = "reset", acct = "wait" }, { k = "charge", acct = "wait", price = "fixed", value = 2 } } }),
  "a counter emptied, a counter charged")
no(rule({ effects = { { k = "charge", acct = "dkp", price = "fraction", value = 1.5 } } }), "effects", "more than all of it")
no(rule({ effects = { { k = "charge", acct = "dkp", price = "all", value = 1 } } }), "effects", "all, and a figure")
no(rule({ effects = { { k = "entry", acct = "gp", value = 4 } } }), "effects", "a price to enter on another account")
no(rule({ effects = { { k = "entry", acct = "dkp", value = 4, refund = 2 } } }), "effects", "twice the price back")
no(rule({ effects = { { k = "reset", acct = "dkp" } } }), "effects", "the points emptied by an award")
no(rule({ accounts = { wait }, effects = { { k = "charge", acct = "wait", price = "bid" } } }), "effects", "a bid paid in a counter")
no(rule({ effects = { { k = "charge", acct = "dkp", price = "all" }, { k = "charge", acct = "gp", price = "table" } } }), "effects",
  "two prices in points")
reads(rule({ effects = { { k = "split", acct = "dkp" } } }), "what was paid shared among the raid")
no(rule({ effects = { { k = "split", acct = "gp" } } }), "effects", "a share of anything but the points")
no(rule({ accounts = { wait }, effects = { { k = "bottom", acct = "wait" } } }), "effects", "the end of a counter")
reads(rule({ accounts = { { key = "sk", type = "queue", frozen = true, newcomer = "random" } }, effects = { { k = "bottom", acct = "sk" } } }),
  "the end of a queue")
no(rule({ accounts = { { key = "sk", type = "queue", newcomer = "top" } } }), "accounts", "a place for newcomers it does not know")
no(rule({ accounts = { { key = "sk", type = "queue", cap = 5 } } }), "accounts", "a queue with a cap")
no(rule({ accounts = { { key = "wait", type = "counter", frozen = true } } }), "accounts", "a counter that is frozen")

-- Played: a share of the balance, the price to enter, a counter charged.
local function nightOf(r)
  dawn()
  raidSeq = raidSeq + 1
  GuildOS.db.companionRoster = { raidId = "p" .. raidSeq, startsAt = NOW, title = "T", members = {}, lootRule = r }
  check(LR:Active() == GuildOS.db.lootNight.rule, "the rule is the night's")
end
nightOf(rule({ effects = { { k = "charge", acct = "dkp", price = "fraction", value = 0.5 } } }))
P:Award(K("Ana"), 81, "seed")
announce()
LM:RegisterRoll("Ana", "MS", 50)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 40, "half of 81 is paid, rounded: " .. P:Get(K("Ana")))
nightOf(rule({ effects = { { k = "charge", acct = "dkp", price = "all" } },
  responses = { { key = "MS" }, { key = "OS", cost = 0 } } }))
P:Award(K("Ana"), 81, "seed")
P:Award(K("Bo"), 20, "seed")
announce()
LM:RegisterRoll("Ana", "MS", 50)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 0, "all of it")
announce()
LM:RegisterRoll("Bo", "OS", 50)
LM:EndRolling(true)
LM:AwardLoot("Bo")
check(P:Get(K("Bo")) == 20, "and a free answer pays nothing of it")

nightOf(rule({ order = { { k = "response" }, { k = "roll" } }, effects = { { k = "entry", acct = "dkp", value = 4, refund = 0.5 } } }))
check(GuildOS.db.points.config.entryCost == nil, "the pool itself asks nothing to enter")
for _, name in ipairs({ "Ana", "Bo", "Cy" }) do P:Award(K(name), 10, "seed") end
announce()
LM:RegisterRoll("Ana", "MS", 90)
LM:RegisterRoll("Bo", "MS", 50)
LM:RegisterRoll("Cy", "MS", 10)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 6 and P:Get(K("Bo")) == 8 and P:Get(K("Cy")) == 8,
  "the rule's price to enter: the winner pays 4, whoever lost 4 less the half given back")
check(LM:UndoLastAward() and P:Get(K("Ana")) == 10 and P:Get(K("Bo")) == 10, "and an undo gives every one of them back")

nightOf(rule({ accounts = { { key = "token", type = "counter", name = "Tokens", earn = { { key = "boss", auto = "boss", value = 2 } } } },
  order = { { k = "response" }, { k = "account", acct = "token", dir = "high" }, { k = "roll" } },
  effects = { { k = "charge", acct = "token", price = "fixed", value = 3 } } }))
-- A boss dies: the raid leader's client gives the counter to the raid.
P:OnBossKill("Attumen")
P:OnBossKill("Moroes")
check(P:Counter("token", K("Ana")) == 4 and P:Counter("token", K("Lead")) == 4, "a counter fed per boss, by the raid leader's client")
leader = false
P:OnBossKill("Maiden")
leader = true
check(P:Counter("token", K("Ana")) == 4, "and by nobody else's")
announce()
LM:RegisterRoll("Ana", "MS", 1)
LM:RegisterRoll("Cy", "MS", 99)
check(order() == "Cy,Ana", "both hold four, so the roll decides: " .. order())
LM:AwardLoot("Ana")
check(P:Counter("token", K("Ana")) == 1, "the winner pays three of the counter")
announce()
LM:RegisterRoll("Ana", "MS", 1)
LM:EndRolling(true)
LM:AwardLoot("Ana")
check(P:Counter("token", K("Ana")) == 0, "and never more than they hold")
check(LM:UndoLastAward() and P:Counter("token", K("Ana")) == 1, "an undo gives it back")

-- ── 4. The rule arrives with the night's roster ─────────────────────
-- Untrusted input: what is kept is a copy held to a size, and no rule at all is said to be none.
check(Import.ReadLootRule(nil) == nil, "a roster with no rule carries none")
check(Import.ReadLootRule("rolls") == false and Import.ReadLootRule(7) == false, "something that is no rule at all is kept as refused")
local deep = {}
local at = deep
for _ = 1, 20 do at.x = {}; at = at.x end
check(Import.ReadLootRule(deep) == false, "nor a table nested past any rule")
local wide = {}
for i = 1, 3000 do wide[i] = i end
check(Import.ReadLootRule({ order = wide }) == false, "nor one with thousands of fields")
check(Import.ReadLootRule({ model = string.rep("x", 500) }) == false, "nor a text no rule holds")
check(Import.ReadLootRule({ order = { function() end } }) == false, "nor anything that is not data")
local own = { v = 1, order = { { k = "roll" } } }
local kept = Import.ReadLootRule(own)
check(kept and kept ~= own and kept.order[1].k == "roll", "a rule is kept as a copy")

-- A roster from before v5, or with no rule saved: nothing to say, nothing in force.
tonight(nil)
check(GuildOS.db.companionRoster.lootRule == nil and LR:NightStatus() == nil and Plan:LootRuleLine() == nil and LR:Night() == nil,
  "a roster that carries no rule changes nothing")
check(LR:Active().model == "rolls", "the guild's rule is in force")

-- Not a rule at all: refused, and said so in one line.
dawn()
check(Import:Load(wire("bad", NOW, '"rolls"')) == 1 and GuildOS.db.companionRoster.lootRule == false, "a roster whose rule is not one still loads")
local line, warning = Plan:LootRuleLine()
check(warning and line == "This raid's loot rule needs a newer GuildOS. The guild's own rule stays in force." and LR:Night() == nil,
  "and the plan window says the raid's rule was not read: " .. tostring(line))
dawn()
Import:Load(wire("bad2", NOW, '{"v":2,"order":[{"k":"roll"}]}'))
check(LR:Night() == nil and (LR:NightStatus()) == "refused", "a rule of a version from the future is refused whole")
dawn()
Import:Load(wire("bad3", NOW, '{"v":1,"order":[{"k":"roll"}],"mood":"good"}'))
check(LR:Night() == nil and (LR:NightStatus()) == "refused", "and so is one with a block this client never heard of")

-- In force only for its night, and only in the raid.
dawn()
inRaid = false
Import:Load(wire("n1", NOW, jsonOf("dkp")))
check(LR:Night() == nil and LR:Active().model == "rolls", "outside a raid the night's rule is not taken")
line, warning = Plan:LootRuleLine()
check(not warning and line == "Loot rule: DKP (fixed price) (in force once the raid is on)", "the plan window names it and says when: " .. tostring(line))
inRaid = true
check(LR:Active().model == "dkp", "in the raid it is the rule in force")
line = Plan:LootRuleLine()
check(line == "Loot rule: DKP (fixed price) (in force for this raid)", "and the plan window says so: " .. tostring(line))
dawn()
Import:Load(wire("n2", NOW + 3 * 3600, jsonOf("dkp")))
check(LR:Night() == nil, "a raid three hours away is not tonight's yet")
dawn()
Import:Load(wire("n3", NOW - 9 * 3600, jsonOf("dkp")))
check(LR:Night() == nil, "nor one that started nine hours ago")

-- Above the core's and the guild's.
dawn()
CM:Create("Alpha")
GuildOS:SetLootSystem("plus1", "Alpha")
RT:SetGroupTag("Alpha")
check(LR:Active().model == "plus1", "a core runs +1")
Import:Load(wire("n4", NOW, jsonOf("dkp")))
check(LR:Active().model == "dkp" and LR:For("Alpha").model == "plus1", "the night's rule comes before the core's, which is kept as it was")
RT:SetGroupTag("")

-- Frozen for the night.
local frozen = LR:Night()
Import:Load(wire("n4", NOW, jsonOf("rolls")))
check(GuildOS.db.companionRoster.lootRule.model == "rolls" and LR:Night() == frozen and LR:Active().model == "dkp",
  "the same raid imported again with another rule changes nothing tonight")
Import:Load(wire("n4", NOW, nil))
check(LR:Night() == frozen, "nor does the rule being taken off the raid")
frozen.order[1].k = "response"
check(GuildOS.db.companionRoster.lootRule ~= frozen, "what is frozen is a copy")
-- After a reload the kept rule is read again; one this client no longer reads is dropped.
LR.nightKept, LR.nightSeen = nil, nil
check(LR:Night() == frozen, "kept across a reload")
LR.nightKept = nil
GuildOS.db.lootNight.rule.order[1].k = "nonsense"
check(LR:Night() == nil and GuildOS.db.lootNight == nil, "a kept rule that no longer reads is dropped, never applied in part")
-- Another raid's night takes over; the night ending gives the guild its rule back.
dawn()
Import:Load(wire("n5", NOW, jsonOf("dkp")))
check(LR:Active().model == "dkp", "tonight's first raid")
Import:Load(wire("n6", NOW + 600, jsonOf("plus1")))
check(LR:Active().model == "plus1" and GuildOS.db.lootNight.raidId == "n6", "the roster of another raid of tonight brings its own rule")
Import:Load(wire("n7", NOW + 600, nil))
check(LR:Night() == nil and LR:Active().model == "rolls", "and one with no rule goes back to the guild's")
dawn()
Import:Load(wire("n8", NOW, jsonOf("dkp")))
check(LR:Active().model == "dkp", "a night")
NOW = NOW + 9 * 3600
check(LR:Night() == nil and GuildOS.db.lootNight == nil and LR:Active().model == "rolls", "is over eight hours after its start")
NOW = NOW - 9 * 3600

-- A guild that hands its loot to another addon takes no rule from the site.
dawn()
GuildOS.db.settings.lootSystem = "external"
Import:Load(wire("n9", NOW, jsonOf("dkp")))
check(LR:Night() == nil and not GuildOS:LootSystemActive(), "external stays external")
GuildOS.db.settings.lootSystem = "rolls"

-- An item keeps the night's rule it was announced under.
dawn()
Import:Load(wire("n10", NOW, jsonOf("dkp")))
announce()
local announced = LM.activeLoot.rule
NOW = NOW + 9 * 3600
check(LR:Active().model == "rolls" and LM:Rule() == announced and LM:System() == "dkp", "a roll open when the night ends finishes by its rule")
NOW = NOW - 9 * 3600
LM:CancelRolling()

print(("loot-contract: %d checks passed (%d models play, %d wait)"):format(checks, modelsPlayed, modelsRefused))
