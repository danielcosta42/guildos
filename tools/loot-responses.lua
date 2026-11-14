-- How raiders answer a roll (issue #334), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Core/Data.lua, Modules/CoreManager.lua, Modules/Points.lua, Modules/LootRule.lua,
-- Modules/LootMaster.lua and UI/FeaturePanels.lua:
--   * a rule's answers are objects (key, label, what each asks for, +1, cost), and a rule with a
--     malformed one is refused whole; the rules of before come out with MS and OS as they were;
--   * the loot master sends the buttons (ASK) before the announce every client reads, a client from
--     before reads only the announce and a new client with a loot master from before keeps MS / OS;
--   * an answer travels by addon message: only a raid member's counts, only for the roll that is open,
--     only the master looter draws the roll, and nothing a raider sends is ever read as a roll;
--   * a /roll line still counts, as the rule's first (1-100) and second (1-99) answer;
--   * the +1: it adds on an answer that counts, orders the next roll, resets per night, per lockout or
--     never, travels between officers in the points' op log and comes off on an undo;
--   * bids: open ones go over the best by a step, sealed ones reach the loot master by whisper and
--     nobody else before the end, a bid over the bidder's points is refused, the winner pays the bid
--     or the second price, and the points history keeps both;
--   * an answer's cost multiplies the item's price;
--   * the loot master types in the answer of a raider with no addon;
--   * the officer's changes to the answers go through LootRule, and the windows draw.
--
--   luajit -e 'ADDON="."' tools/loot-responses.lua
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
    -- A method takes any call; a field the code keeps on a frame (f.ticker) is not there until set.
    if type(k) == "string" and k:find("^%u") then return function() end end
    return nil
  end })
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
format, strlower = string.format, string.lower
function CreateFrame(kind) local w = widget({ kind = kind }); widgets[#widgets + 1] = w; return w end
UIParent, GameTooltip = widget(), widget()
RAID_CLASS_COLORS = {}
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetInstanceInfo() return "Karazhan", "raid", 9, "", 10, 0, false, 532 end
function GetRealmName() return "Realm" end
local NOW, CLOCK = 1791000000, 100
function GetServerTime() return NOW end
function GetTime() return CLOCK end
time, date = os.time, os.date
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInRaid() return true end
function IsInGroup() return true end
function SendChatMessage() end
-- The raid's first is its master looter, as the game names one: by their place in the raid.
local lootMethod = { "master", nil, 1 }
function GetLootMethod() return lootMethod[1], lootMethod[2], lootMethod[3] end
local raid = { "Lead", "Ana", "Bo", "Cy", "Dee" }
function UnitIsGroupLeader(unit) return unit == "raid1" or unit == "player" end
function UnitIsGroupAssistant(unit) return unit == "raid2" end
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
dofile(ADDON .. "/Modules/Points.lua")
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
GuildOS.db = { settings = { lootSystem = "rolls" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { awardHistory = {}, dkpMinBid = 10, dkpBidTime = 45 }, points = {},
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local LM, LR, P = GuildOS.LootMaster, GuildOS.LootRule, GuildOS.Points
GuildOS.IsOfficer = function() return true end
GuildOS.IsOfficerByName = function() return true end
function GuildOS:ApplyFont() end
-- What the officers' sync would carry.
local published = {}
GuildOS.SyncService = {
  On = function() end, ShouldApply = function() return true end, SetRevision = function() end,
  NextRevision = function() return 1 end,
  Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end,
}
P:Initialize()
local cfg = GuildOS.db.points.config
local function K(name) return GuildOS:GetPlayerKey(name) end

-- Everything this client sends or says, in order.
local sent, whispered, said, printed = {}, {}, {}, {}
local isML = true
LM.SafeSendAddon = function(_, _, payload, channel) sent[#sent + 1] = payload; check(channel == "RAID", "the raid channel") end
LM.SendEcho = function(_, payload) sent[#sent + 1] = payload end
GuildOS.Compat.SendAddonMessageNow = function(_, text, channel, target)
  whispered[#whispered + 1] = { text = text, channel = channel, target = target }
end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.IsMasterLooter = function() return isML end
LM.GetPlayerContext = function() return { att25 = 100, recvThisLockout = 0 } end
local realRollFrame = LM.ShowRollFrame
LM.ShowRollFrame = function() end
function GuildOS:Print(msg) printed[#printed + 1] = msg end
local function quiet() sent, whispered, said, printed = {}, {}, {}, {} end
local function all(list) return table.concat(list, "\n") end

-- The rolls the loot master's client draws, in order.
local draws, drawn = {}, 0
local realRandom = math.random
math.random = function(a, b)
  if a == 1 and (b == 100 or b == 99) then
    drawn = drawn + 1
    return table.remove(draws, 1) or 50
  end
  return realRandom(a, b)
end

local LINK = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r"
local function announce()
  quiet()
  LM.lootWindowOpen = false
  LM:AnnounceItem(LINK, nil)
  return LM.activeLoot.sid
end
-- An answer as a raider's client sends it, heard by this one.
local function answer(from, sid, key, bid, note, channel)
  local msg = string.format("ANS|%s|%s|%d", sid, key, bid or 0)
  if note then msg = msg .. "|" .. note end
  LM:OnAddonMessage(LM.PREFIX, msg, channel or "RAID", from .. "-Realm")
end
local function row(name) return LM.rolls[K(name)] end

-- ── 1. The answers of a rule ────────────────────────────────────────
local legacy = LR:FromLegacy("rolls", {})
check(#legacy.responses == 2 and legacy.responses[1].key == "MS" and legacy.responses[2].key == "OS",
  "the rule of before asks for MS, then OS")
check(legacy.responses[1].ask == "roll" and legacy.responses[1].plus == true and legacy.responses[1].cost == 1,
  "MS is a roll, counts for the +1 and pays the price")
check(legacy.responses[2].ask == "roll" and legacy.responses[2].plus == false and legacy.responses[2].cost == 1,
  "OS is a roll, does not count and pays the same price as before")
check(legacy.time == nil and LM:RollTime() == 30, "and its time is the roll duration of the loot settings")
for _, system in ipairs({ "rolls", "tmb", "wishlist", "dkp", "epgp", "plus1", "dkpbid", "dkpsealed" }) do
  check(LR:Validate(LR:FromLegacy(system, { dkpMinBid = 10, dkpBidTime = 45 })), system .. " is a rule this client reads")
end

local function with(responses, more)
  local rule = { v = 1, order = { { k = "response" }, { k = "roll" } }, responses = responses }
  for k, v in pairs(more or {}) do rule[k] = v end
  return rule
end
local function refused(rule, what) check(not LR:Validate(rule), "refused: " .. what) end
check(LR:Validate(with({ { key = "MS" } })), "a key alone is an answer: a roll, at the item's price")
check(LR:Validate(with({ { key = "TMOG", label = "Transmog", ask = "none", plus = false, cost = 0, note = true } })),
  "an answer with every field")
refused(with({ "MS", "OS" }), "the answers as bare names, as before #334")
refused(with({}), "no answer at all")
refused(with({ { key = "ms" } }), "a key in small letters")
refused(with({ { key = "TOOLONGKEY" } }), "a key of more than eight")
refused(with({ { key = "" } }), "an empty key")
refused(with({ { key = "M S" } }), "a key with a space")
refused(with({ { key = "PASS" } }), "a pass as an answer")
refused(with({ { key = "MS" }, { key = "MS" } }), "the same key twice")
refused(with({ { key = "MS", ask = "dance" } }), "an ask this client never heard of")
refused(with({ { key = "MS", cost = -1 } }), "a price below nothing")
refused(with({ { key = "MS", cost = "1" } }), "a price that is not a number")
refused(with({ { key = "MS", cost = 11 } }), "a price multiplied past ten")
refused(with({ { key = "MS", plus = 1 } }), "a +1 that is not yes or no")
refused(with({ { key = "MS", label = "" } }), "an empty label")
refused(with({ { key = "MS", label = "a|cffff0000red" } }), "a label with a colour code")
refused(with({ { key = "MS", label = "one;two" } }), "a label with the message's separator")
refused(with({ { key = "MS", label = string.rep("x", 25) } }), "a label too long for its button")
local eleven = {}
for i = 1, 11 do eleven[i] = { key = "K" .. i } end
refused(with(eleven), "eleven answers")
eleven[11] = nil
check(LR:Validate(with(eleven)), "ten answers are a rule")
refused(with({ { key = "MS" } }, { time = 4 }), "four seconds to answer")
refused(with({ { key = "MS" } }, { time = 301 }), "more than five minutes to answer")
refused(with({ { key = "MS" } }, { time = 30.5 }), "half a second")
check(LR:Validate(with({ { key = "MS" } }, { time = 300 })), "five minutes are a time")
refused(with({ { key = "MS" } }, { bid = { min = -1 } }), "a least bid below nothing")
refused(with({ { key = "MS" } }, { bid = { step = 0 } }), "a bid step of nothing")
refused(with({ { key = "MS" } }, { bid = { sealed = "yes" } }), "sealed that is not yes or no")
refused(with({ { key = "MS" } }, { accounts = { { key = "plus1", type = "ledger" } } }), "an account of a kind it does not know")
refused(with({ { key = "MS" } }, { accounts = { { key = "dkp", type = "counter" } } }), "a counter under the points' own key")
refused(with({ { key = "MS" } }, { accounts = { { key = "plus1", type = "counter", reset = "weekly" } } }), "a reset it does not know")
refused(with({ { key = "MS" } }, { effects = { { k = "add", acct = "plus1", value = 1 } } }), "adding to an account the rule does not keep")
refused(with({ { key = "MS" } }, { effects = { { k = "charge", price = "auction" } } }), "a price it does not know")
refused(with({ { key = "MS" } }, { effects = { { k = "charge", price = "bid" }, { k = "charge", price = "second" } } }),
  "two prices for one item")
refused({ v = 1, order = { { k = "account", acct = "plus1" } } }, "ordering by an account the rule does not keep")
check(LR:Validate({ v = 1, accounts = { { key = "plus1", type = "counter" }, { key = "tier", type = "counter" } },
  order = { { k = "account", acct = "plus1", dir = "low" }, { k = "account", acct = "tier", dir = "low" }, { k = "roll" } } }),
  "an account criterion once per account")
refused({ v = 1, accounts = { { key = "plus1", type = "counter" } },
  order = { { k = "account", acct = "plus1" }, { k = "account", acct = "plus1" } } }, "the same account twice")

-- The answer criterion ranks by place, whatever the keys.
local own = with({ { key = "BIS" }, { key = "UPG" }, { key = "TMOG", ask = "none", cost = 0 } })
local order = LR:Sort({
  { name = "A", rollType = "TMOG" }, { name = "B", rollType = "UPG", roll = 99 },
  { name = "C", rollType = "BIS", roll = 1 }, { name = "D", rollType = "PASS" },
}, own)
check(order[1].name == "C" and order[2].name == "B" and order[3].name == "A" and order[4].name == "D",
  "the first answer before the second, the third after, a pass last")

-- ── 2. The buttons on the wire ──────────────────────────────────────
check(LR:Encode(legacy, 30) == "30,-,0,1;MS=r;OS=r", "MS and OS as the popup needs them: " .. LR:Encode(legacy, 30))
local spec = LR:Decode(LR:Encode(legacy, 30))
check(spec and spec.time == 30 and not spec.bids and #spec.responses == 2 and spec.responses[1].label == "MS"
  and spec.responses[2].ask == "roll", "and read back")
local rich = with({
  { key = "BIS", label = "Best in slot", ask = "bid" }, { key = "UPG", label = "Upgrade", ask = "bid", cost = 0.5 },
  { key = "TMOG", label = "Transmog", ask = "none", cost = 0, note = true },
}, { bid = { sealed = true, min = 10, step = 5 } })
check(LR:Validate(rich), "a rule of three answers, two of them bids")
spec = LR:Decode(LR:Encode(rich, 45))
check(spec.time == 45 and spec.bids and spec.sealed and spec.min == 10 and spec.step == 5, "the bids' rules travel")
check(spec.responses[1].label == "Best in slot" and spec.responses[1].ask == "bid" and not spec.responses[1].note,
  "an answer travels with its label and what it asks for")
check(spec.responses[3].key == "TMOG" and spec.responses[3].ask == "none" and spec.responses[3].note == true,
  "and whether it needs a note")
local wide = {}
for i = 1, 10 do wide[i] = { key = "ANSWER" .. (i % 10) .. "X", label = string.rep("w", 23) .. (i % 10), ask = "roll" } end
local encoded = LR:Encode(with(wide), 300)
check(#("ASK|FFFFF|" .. encoded) <= 255, "ten answers with the longest labels still fit one addon message: " .. #encoded)
spec = LR:Decode(encoded)
check(spec and #spec.responses == 10 and spec.responses[1].label == wide[1].label
  and spec.responses[10].label == wide[10].key, "the labels that fit are kept, and a button without one shows its key")
for _, bad in ipairs({ "", "30,-,0,1", "30,-,0,1;", "4,-,0,1;MS=r", "30,x,0,1;MS=r", "30,-,0,0;MS=r", "30,-,0,1;ms=r",
    "30,-,0,1;MS=q", "30,-,0,1;MS=r;MS=r", "30,-,0,1;PASS=r", "30,-,0,1;MS=ra|cffff0000b", "30,-,0,1;MS=b",
    "30,o,0,1;MS=r", "30,-,0,1;MS", string.rep("30,-,0,1;MS=r", 30) }) do
  check(LR:Decode(bad) == nil, "a message that is not the buttons is not read: " .. bad:sub(1, 30))
end
check(LR:Decode(nil) == nil and LR:Decode({}) == nil, "nor anything that is not text")

-- ── 3. The loot master announces: the buttons, then the announce of always ──
local sid = announce()
check(#sent == 2 and sent[1] == "ASK|" .. sid .. "|30,-,0,1;MS=r;OS=r", "the buttons go first: " .. tostring(sent[1]))
check(sent[2] == "ANNOUNCE|" .. LINK .. "|30|28770|0", "then the announce, as it always was: " .. tostring(sent[2]))
check(said[1] == "[ROLL] " .. LINK .. "  -  /roll 1-100 = MS  -  /roll 1-99 = OS  -  30s", "and the raid warning of before")
-- A client from before reads its messages this way (LootMaster:OnAddonMessage before #334).
local function oldClient(msg)
  local cmd, rest = msg:match("^(%w+)|(.+)$")
  if cmd ~= "ANNOUNCE" then return cmd == "UNDO" or cmd == "AWARD" end
  local link, duration, itemId, flag = rest:match("^(.+)|(%d+)|(%d+)|([01])$")
  return link, tonumber(duration), tonumber(itemId), flag
end
check(oldClient(sent[1]) == false, "a client from before does nothing with the buttons")
local oldLink, oldTime, oldItem = oldClient(sent[2])
check(oldLink == LINK and oldTime == 30 and oldItem == 28770, "and shows its MS / OS popup for the announce")

-- ── 4. A raider's client: the popup the loot master's rule asks for ──
isML = false
local popups = {}
local realPopup = LM.ShowRollPopup
LM.ShowRollPopup = function(_, link, duration, itemId, ask) popups[#popups + 1] = { link = link, duration = duration, itemId = itemId, ask = ask } end
local function hear(msg, from) LM:OnAddonMessage(LM.PREFIX, msg, "RAID", from or "Lead-Realm") end
hear("ASK|A1|45,s,10,5;BIS=bBest in slot;TMOG=NTransmog")
hear("ANNOUNCE|" .. LINK .. "|45|28770|0")
check(#popups == 1 and popups[1].ask and popups[1].ask.responses[1].label == "Best in slot" and popups[1].duration == 45,
  "the buttons that came with the announce are the popup's")
check(LM.heard and LM.heard.sid == "A1" and LM.heard.sender == "Lead-Realm", "and the roll being answered is that loot master's")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
check(#popups == 2 and popups[2].ask == nil and LM.heard == nil,
  "an announce alone, from a loot master on a version from before: the MS / OS popup")
hear("ASK|A2|30,-,0,1;MS=r;OS=r", "Ana-Realm")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0", "Lead-Realm")
check(popups[3].ask == nil, "buttons from one sender never dress another's announce")
hear("ASK|A3|30,-,0,1;MS=r;OS=r")
CLOCK = CLOCK + 60
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
check(popups[4].ask == nil, "nor do buttons heard a minute ago")
hear("ASK|A4|30,-,0,1;MS=r;;OS=r")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
check(popups[5].ask == nil, "and buttons this client cannot read whole leave the MS / OS popup")
LM:OnAddonMessage(LM.PREFIX, "ASK|A5|30,-,0,1;MS=r;OS=r", "WHISPER", "Lead-Realm")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
check(popups[6].ask == nil, "buttons never come by whisper")

-- Only the raid's master looter opens a roll. A raider who replays the buttons and the announce used
-- to become who every answer went to, sealed bids among them, and the master looter got none.
hear("ASK|D1|30,s,10,1;MS=bMS;OS=bOS")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
local shown = #popups
check(LM.heard and LM.heard.sender == "Lead-Realm" and LM.heard.sid == "D1", "the master looter's sealed roll is the one being answered")
hear("ASK|D1|30,s,10,1;MS=bMS;OS=bOS", "Bo-Realm")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0", "Bo-Realm")
check(#popups == shown and LM.heard and LM.heard.sender == "Lead-Realm" and LM.heard.sid == "D1",
  "a raider who replays the buttons and the announce opens nothing and takes nobody's answers")
hear("ASK|FFFF|30,s,10,1;MS=bMS;OS=bOS", "Bo-Realm")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0", "Bo-Realm")
check(#popups == shown and LM.heard.sid == "D1", "nor does a raider's made-up roll replace the one that is open")
quiet()
LM:SendAnswer("MS", 500, "")
check(#whispered == 1 and whispered[1].target == "Lead-Realm" and whispered[1].text == "ANS|D1|MS|500" and #sent == 0,
  "so the sealed bid still goes to the master looter and to nobody else")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0", "Zed-Realm")
check(#popups == shown, "an announce from outside the raid is nothing")
-- Where the game names no master looter, the raid's leader and its assistants are read, nobody else.
lootMethod = { "group" }
hear("ASK|D2|30,-,0,1;MS=r;OS=r", "Bo-Realm")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0", "Bo-Realm")
check(#popups == shown and LM.heard.sid == "D1", "with no master looter named, a raider's announce is still nothing")
hear("ASK|D3|30,-,0,1;MS=r;OS=r", "Ana-Realm")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0", "Ana-Realm")
check(#popups == shown + 1 and LM.heard.sid == "D3" and LM.heard.sender == "Ana-Realm", "an assistant's is read")
hear("ASK|D4|30,-,0,1;MS=r;OS=r")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
check(#popups == shown + 2 and LM.heard.sid == "D4", "and the leader's")
lootMethod = { "master", nil, 1 }
hear("ROLL|D4|Lead|MS|100", "Ana-Realm")
-- On a client with surnames a first name alone names the master looter only when one raider has it.
GuildOS.Client.has.surnames = true
raid[1], raid[2] = "Lead Silva", "Lead Costa"
check(LM:IsFromMasterLooter("Lead Silva") == true and LM:IsFromMasterLooter("Lead Costa") == false,
  "with surnames, the whole name says who the master looter is")
check(LM:IsFromMasterLooter("Lead") == false, "and a first name two raiders share is nobody's")
raid[2] = "Ana Costa"
check(LM:IsFromMasterLooter("Lead") == true and LM:IsFromMasterLooter("Ana") == false,
  "a first name only one raider has is theirs")
raid[1], raid[2] = "Lead", "Ana"
GuildOS.Client.has.surnames = false

-- The button clicked: the answer goes to the loot master, a sealed bid by whisper only.
hear("ASK|B1|30,-,0,1;MS=r;OS=r")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
quiet()
check(LM:SendAnswer("MS", 0, "") == true and sent[1] == "ANS|B1|MS|0" and #whispered == 0, "a roll's answer goes over the raid: " .. tostring(sent[1]))
hear("ASK|B2|45,s,10,5;BIS=bBest in slot;TMOG=NTransmog")
hear("ANNOUNCE|" .. LINK .. "|45|28770|0")
quiet()
LM:SendAnswer("BIS", 80, "")
check(#sent == 0 and #whispered == 1 and whispered[1].text == "ANS|B2|BIS|80" and whispered[1].channel == "WHISPER"
  and whispered[1].target == "Lead-Realm", "a sealed bid is whispered to the loot master and never sent to the raid")
LM:SendAnswer("TMOG", 0, "for my |cffff0000alt|r\n")
check(sent[1] == "ANS|B2|TMOG|0|for my cffff0000altr", "a note travels without its colour codes: " .. tostring(sent[1]))
hear("ASK|B3|30,o,10,5;BIS=bBest in slot")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
quiet()
LM:SendAnswer("BIS", 80, "")
check(sent[1] == "ANS|B3|BIS|80" and #whispered == 0, "an open bid goes over the raid")
LM.heard = nil
check(LM:SendAnswer("MS", 0, "") == false, "with no roll heard, nothing is sent")

-- What the loot master says back is shown, and only the loot master's.
hear("ASK|C1|30,o,10,5;BIS=bBest in slot;MS=r")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
quiet()
hear("ROLL|C1|Lead|MS|77")
check(#printed == 1 and printed[1]:find("77", 1, true) and printed[1]:find("MS", 1, true), "the roll the loot master drew for me is shown to me")
hear("ROLL|C1|Ana|MS|12")
check(#printed == 1, "somebody else's roll is theirs to see")
hear("ROLL|C1|Lead|MS|100", "Ana-Realm")
check(#printed == 1, "a roll said by anybody but the loot master is nothing")
hear("ROLL|ZZ|Lead|MS|100")
check(#printed == 1, "nor one for another roll")
hear("BID|C1|Ana|BIS|40")
check(LM.heard.high == 40, "an open bid is the best so far")
hear("BID|C1|Bo|BIS|30")
check(LM.heard.high == 40, "and a lower one does not replace it")
hear("NO|C1|Lead|balance|0")
check(printed[#printed]:find("more than the points you hold", 1, true), "a refusal says why")
hear("NO|C1|Lead|low|45")
check(printed[#printed]:find("at least 45", 1, true), "and what would be enough")
LM.ShowRollPopup = realPopup
isML = true

-- ── 5. The loot master's client: answers by addon message ───────────
sid = announce()
draws, drawn = { 57, 12, 99 }, 0
quiet()
answer("Ana", sid, "MS")
check(row("Ana") and row("Ana").rollType == "MS" and row("Ana").roll == 57 and drawn == 1,
  "a raid member's answer is kept, with the roll this client drew")
check(sent[1] == "ROLL|" .. sid .. "|Ana|MS|57", "and the roll is told to the raid's addons: " .. tostring(sent[1]))
check(#said == 0, "with no line of its own in the raid's chat")
answer("Ana", sid, "MS")
answer("Ana", sid, "OS")
check(row("Ana").roll == 57 and row("Ana").rollType == "OS" and drawn == 1, "answering again changes the answer, never the roll")
answer("Ana", sid, "PASS")
check(row("Ana").rollType == "PASS" and sent[#sent] == "ACK|" .. sid .. "|Ana|PASS", "a pass is a pass")
answer("Ana", sid, "MS")
check(row("Ana").roll == 57 and drawn == 1, "and coming back from it brings the same roll back")
answer("Bo", sid, "OS")
check(row("Bo").roll == 12 and drawn == 2, "the second answer's roll is drawn too")

-- Forged: who answered is the sender, and only a raid member's answer for the open roll counts.
answer("Zed", sid, "MS")
check(row("Zed") == nil and drawn == 2, "an answer from outside the raid is nothing")
answer("Cy", "FFFF", "MS")
check(row("Cy") == nil, "nor an answer for another roll")
LM:OnAddonMessage(LM.PREFIX, "ANS|" .. sid .. "|MS|0", "GUILD", "Cy-Realm")
check(row("Cy") == nil, "nor one that came by the guild channel")
LM:OnAddonMessage(LM.PREFIX, "ANS|" .. sid .. "|XX|0", "RAID", "Cy-Realm")
check(row("Cy") == nil and sent[#sent]:find("^NO|" .. sid .. "|Cy|unknown|"), "an answer the rule does not have is refused, and told so")
for _, junk in ipairs({ "ANS|", "ANS|" .. sid, "ANS|" .. sid .. "|MS", "ANS|" .. sid .. "|MS|abc", "ANS|" .. sid .. "|ms|0",
    "ANS|" .. sid .. "|MS|99999999", "ANS|" .. sid .. "|MS|0|" .. string.rep("n", 200), "ANS|" .. sid .. "|MS|-5" }) do
  LM:OnAddonMessage(LM.PREFIX, junk, "RAID", "Cy-Realm")
  check(row("Cy") == nil, "a malformed answer is nothing: " .. junk:sub(1, 30))
end
-- A raider says a roll was drawn for them: this client reads no roll it did not draw.
LM:OnAddonMessage(LM.PREFIX, "ROLL|" .. sid .. "|Cy|MS|100", "RAID", "Cy-Realm")
LM:OnAddonMessage(LM.PREFIX, "ROLL|" .. sid .. "|Ana|MS|100", "RAID", "Cy-Realm")
LM:OnAddonMessage(LM.PREFIX, "BID|" .. sid .. "|Cy|MS|100", "RAID", "Cy-Realm")
check(row("Cy") == nil and row("Ana").roll == 57, "a roll a raider claims is never a roll")
isML = false
answer("Cy", sid, "MS")
check(row("Cy") == nil and drawn == 2, "and a client that is not the master looter draws no roll")
isML = true
-- A roll for the tied only.
LM.restrictedRollers = { ana = true, bo = true }
answer("Cy", sid, "MS")
check(row("Cy") == nil, "in a roll for a tie, only the tied answer")
LM.restrictedRollers = nil
answer("Cy", sid, "MS")
check(row("Cy").roll == 99 and drawn == 3, "and outside one, anybody in the raid does")

-- A client from before answers by /roll, read from chat where chat shows it.
LM.rollFormat = "%s rolls %d (%d-%d)"
LM:ProcessSystemRoll("Dee rolls 88 (1-100)")
check(row("Dee").rollType == "MS" and row("Dee").roll == 88 and not row("Dee").drawn, "/roll 1-100 from a client from before is the first answer")
-- This check used to read a second /roll as a new number (31): a roll again by another range. The
-- range still says the answer; the number is the first one read.
LM:ProcessSystemRoll("Dee rolls 31 (1-99)")
check(row("Dee").rollType == "OS" and row("Dee").roll == 88, "/roll 1-99 is the second answer, and the first number read stays")
LM:ProcessSystemRoll("Zed rolls 100 (1-100)")
check(row("Zed") == nil, "and still only from the raid")
LM:ProcessSystemRoll("Ana rolls 100 (1-100)")
check(row("Ana").roll == 57 and row("Ana").rollType == "MS", "a /roll after a button changes the answer, never the roll this client drew")
quiet()
LM:EndRolling(true)
check(said[1] == "[Rolls] Cy MS 99, Ana MS 57, Bo OS 12", "the rolls this client drew are told to the raid in one line: " .. tostring(said[1]))
check(LM.activeLoot.sortedResults[1].name == "Cy" and said[2]:find("[WINNER] Cy - MS (99)", 1, true) and #said == 2,
  "and the roll ends as always: " .. tostring(said[2]))
answer("Bo", sid, "MS")
check(row("Bo").rollType == "OS", "and an answer after the end changes nothing")
LM:CancelRolling()

-- One roll a player and an item, whatever is answered in between. An answer that asks for no roll
-- (or a pass, or a bid) used to empty the row, and the next roll answer drew again: 7, 31, 96...
check(LR:Set(with({ { key = "MS" }, { key = "OS" }, { key = "WAIT", ask = "none" } })) == true, "a rule with an answer that asks for no roll")
sid = announce()
draws, drawn = { 7, 31, 96, 64 }, 0
answer("Ana", sid, "OS")
answer("Ana", sid, "WAIT")
check(row("Ana").rollType == "WAIT" and row("Ana").roll == nil, "an answer with no roll shows none")
answer("Ana", sid, "OS")
check(row("Ana").roll == 7 and drawn == 1, "and going back to a roll brings the first one back, with no new draw")
answer("Ana", sid, "WAIT"); answer("Ana", sid, "MS"); answer("Ana", sid, "PASS"); answer("Ana", sid, "OS")
check(row("Ana").roll == 7 and drawn == 1, "however many times the answer alternates")
LM:ProcessSystemRoll("Ana rolls 100 (1-100)")
check(row("Ana").roll == 7 and row("Ana").rollType == "MS" and row("Ana").drawn, "a /roll after a button never replaces the roll drawn")
LM:ProcessSystemRoll("Dee rolls 3 (1-100)")
answer("Dee", sid, "PASS"); answer("Dee", sid, "MS")
check(row("Dee").roll == 3 and drawn == 1 and not row("Dee").drawn, "a button after a /roll and a pass keeps the /roll read")
LM:ProcessSystemRoll("Dee rolls 95 (1-100)")
check(row("Dee").roll == 3, "and a second /roll is not a second chance")
check(LM:EnterAnswer("cy", "MS") ~= nil and row("Cy").roll == 31 and drawn == 2, "a roll the loot master enters for a raider is drawn once")
LM:EnterAnswer("cy", "WAIT")
answer("Cy", sid, "MS")
check(row("Cy").roll == 31 and drawn == 2, "and is the raider's own from then on, whoever answers")
LM:CancelRolling()
sid = announce()
answer("Ana", sid, "MS")
check(row("Ana").roll == 96 and drawn == 3, "the next item is a new roll")
LM:CancelRolling()
check(LR:Set(nil) == true, "back to the loot system's rule")

-- ── 6. Answers of the guild's own ───────────────────────────────────
check(LR:Set(with({ { key = "BIS", label = "Best in slot" }, { key = "UPG", label = "Upgrade", cost = 0.5 },
  { key = "TMOG", label = "Transmog", ask = "none", cost = 0, note = true } }, { time = 20 })) == true, "an officer's answers are the rule")
sid = announce()
check(sent[1] == "ASK|" .. sid .. "|20,-,0,1;BIS=rBest in slot;UPG=rUpgrade;TMOG=NTransmog", "the buttons are the rule's: " .. sent[1])
check(sent[2] == "ANNOUNCE|" .. LINK .. "|20|28770|0" and LM.activeLoot.endTime == NOW + 20, "and the time too")
check(said[1] == "[ROLL] " .. LINK .. "  -  /roll 1-100 = Best in slot  -  /roll 1-99 = Upgrade  -  other answers in the GuildOS window, or tell the loot master  -  20s",
  "the raid warning names them: " .. said[1])
LM:ProcessSystemRoll("Dee rolls 40 (1-100)")
LM:ProcessSystemRoll("Bo rolls 90 (1-99)")
check(row("Dee").rollType == "BIS" and row("Bo").rollType == "UPG", "/roll 1-100 and 1-99 are the rule's first and second answers")
quiet()
answer("Ana", sid, "TMOG")
check(row("Ana") == nil and sent[1]:find("^NO|" .. sid .. "|Ana|note|"), "an answer that needs a note is refused without one")
answer("Ana", sid, "TMOG", 0, "for the |cffff0000red|r set")
check(row("Ana").rollType == "TMOG" and row("Ana").roll == nil and row("Ana").note == "for the cffff0000redr set",
  "with one it is kept, with no roll and no colour code")
check(sent[#sent] == "ACK|" .. sid .. "|Ana|TMOG", "and acknowledged")
LM:EndRolling(true)
local res = LM.activeLoot.sortedResults
check(res[1].name == "Dee" and res[2].name == "Bo" and res[3].name == "Ana", "the first answer wins over a higher roll in the second")
LM:CancelRolling()
quiet()
LM.rolls = { a = { name = "Ana", rollType = "TMOG" } }
LM.activeLoot = { link = LINK, itemId = 28770 }
LM:EndRolling(true)
check(said[1] == "[WINNER] Ana - Transmog - " .. LINK, "a winner with no roll is named without one: " .. tostring(said[1]))
LM:CancelRolling()

-- The price each answer pays (the cost multiplier).
GuildOS.db.settings.lootSystem = "dkp"
cfg.itemCost = 20
local function awardTo(name, rollType, extra)
  LM.activeLoot = { link = LINK, itemId = 28770, sid = "1" }
  LM.rolls = {}
  LM:RegisterRoll(name, rollType, 50, extra)
  local before = P:Get(K(name))
  LM:EndRolling(true)
  LM:AwardLoot(name)
  return before - P:Get(K(name)), GuildOS.db.lootMaster.awardHistory[1]
end
check(awardTo("Ana", "BIS") == 20, "the first answer pays the item's price")
check(awardTo("Bo", "UPG") == 10, "an answer at half price pays half")
local paidFree, freeAward = awardTo("Cy", "TMOG")
check(paidFree == 0 and freeAward.charged == nil, "and a free answer pays nothing")
cfg.itemCost = 15
check(awardTo("Bo", "UPG") == 8, "half of an odd price is rounded")
LM.activeLoot = { link = LINK, itemId = 28770 }
LM.rolls = {}
local before = P:Get(K("Dee"))
LM:AwardLoot("Dee")
check(before - P:Get(K("Dee")) == 15, "an item given with no answer pays the item's price, as before")
check(LR:Set(nil) == true, "back to the loot system's rule")
cfg.itemCost = 20
check(awardTo("Ana", "MS") == 20 and awardTo("Bo", "OS") == 20, "with nothing changed, MS and OS pay what they paid")
cfg.itemCost = 0

-- ── 7. The +1 ───────────────────────────────────────────────────────
GuildOS:SetLootSystem("plus1")
local plus1 = LR:Active()
check(plus1.model == "plus1" and plus1.order[2].k == "account" and plus1.order[2].acct == "plus1" and plus1.order[2].dir == "low"
  and plus1.order[1].k == "response" and plus1.order[3].k == "roll", "+1: the answer, then the counter, then the roll")
check(not GuildOS:LootSystemUsesPoints(), "+1 spends no points")
local found = false
for _, sys in ipairs(GuildOS:LootSystemsHere()) do found = found or sys.key == "plus1" end
check(found, "+1 is a loot system the guild can pick")
local function rollOff(rolls)
  sid = announce()
  check(sent[1] == "ASK|" .. sid .. "|30,-,0,1;MS=r;OS=r", "+1 asks for MS and OS")
  for _, r in ipairs(rolls) do LM:RegisterRoll(r[1], r[2], r[3]) end
  LM:EndRolling(true)
  return LM.activeLoot.sortedResults
end
published = {}
res = rollOff({ { "Ana", "MS", 90 }, { "Bo", "MS", 10 } })
check(res[1].name == "Ana" and LM.activeLoot.decidedBy == "roll", "with nobody ahead, the roll decides")
LM:AwardLoot("Ana")
check(P:Counter("plus1", K("Ana")) == 1 and P:Counter("plus1", K("Bo")) == 0, "winning main spec is a +1")
check(#published == 1 and published[1].dom == "points" and published[1].act == "cdelta"
  and published[1].data.entries[1].acct == "plus1" and published[1].data.entries[1].delta == 1,
  "told to the officers in the points' op log, under an action a client from before does not read as points")
check(P:Get(K("Ana")) == GuildOS.db.points.standings[K("Ana")].current, "and it never touches the points")
res = rollOff({ { "Ana", "MS", 99 }, { "Bo", "MS", 5 }, { "Cy", "OS", 100 } })
check(res[1].name == "Bo" and res[2].name == "Ana" and res[3].name == "Cy", "next item: fewer +1 comes before a higher roll, and OS after")
check(LM.activeLoot.decidedBy == "account" and said[#said]:find("[by the counter]", 1, true), "and the winner line says the counter decided")
check(row("Ana").accts.plus1 == 1 and row("Bo").accts.plus1 == 0, "the Master Loot window's rows carry the counter")
LM:AwardLoot("Bo")
res = rollOff({ { "Ana", "OS", 5 }, { "Cy", "OS", 3 } })
LM:AwardLoot("Ana")
check(P:Counter("plus1", K("Ana")) == 1, "winning off spec is no +1")
res = rollOff({ { "Ana", "MS", 5 }, { "Bo", "MS", 3 }, { "Cy", "MS", 1 } })
check(res[1].name == "Cy" and res[2].name == "Ana", "one each, and the one with none wins")
LM:AwardLoot("Cy")

-- Undo: the +1 comes off.
check(P:Counter("plus1", K("Cy")) == 1, "Cy's +1 is counted")
local undone = LM:UndoLastAward()
check(undone and undone.player == "Cy" and P:Counter("plus1", K("Cy")) == 0, "undoing the award takes the +1 back")
check(published[#published].act == "cdelta" and published[#published].data.entries[1].delta == -1, "and the officers are told")
undone = LM:UndoLastAward()
check(undone.player == "Ana" and P:Counter("plus1", K("Ana")) == 1, "undoing an off spec award takes none")

-- Between officers: each entry once, whatever the order, and a client's own figures in the snapshot.
local mine = GuildOS.db.points
local theirs = { mode = "dkp", config = {}, standings = {}, log = {}, appliedOps = {}, appliedCount = 0 }
GuildOS.db.points = theirs
for _ = 1, 2 do
  for _, pub in ipairs(published) do
    local copy = { entries = {} }
    for i, e in ipairs(pub.data.entries) do
      copy.entries[i] = {}
      for k, v in pairs(e) do copy.entries[i][k] = v end
    end
    P:OnSync({ act = pub.act, data = copy })
  end
end
check(P:Counter("plus1", K("Ana")) == 1 and P:Counter("plus1", K("Bo")) == 1 and P:Counter("plus1", K("Cy")) == 0,
  "another officer's client ends on the same counters, however often the entries arrive")
check(next(theirs.standings) == nil, "and reads none of them as points")
for _, bad in ipairs({
  { op = "x1", key = "Ana-Realm", acct = "plus1", rs = "night", per = NOW, delta = 5000 },
  { op = "x2", key = "Ana-Realm", acct = "PLUS 1", rs = "night", per = NOW, delta = 1 },
  { op = "x3", key = "Ana-Realm", acct = "plus1", rs = "hourly", per = NOW, delta = 1 },
  { op = "x4", key = "Ana-Realm", acct = "plus1", rs = "night", per = "now", delta = 1 },
  { op = "x5", key = "Ana-Realm", acct = "plus1", rs = "night", per = NOW, delta = 0.5 },
  { op = "x6", key = 7, acct = "plus1", rs = "night", per = NOW, delta = 1 },
  "not an entry",
}) do
  P:OnSync({ act = "cdelta", data = { entries = { bad } } })
end
check(P:Counter("plus1", K("Ana")) == 1, "an entry that is not a counter's adds nothing")
published = {}
GuildOS.db.points = mine
P:BroadcastSnapshot()
local snap = published[1].data
check(snap.accounts and snap.accounts.plus1.v[K("Ana")] == 1, "the snapshot carries the counters")
GuildOS.db.points = theirs
theirs.accounts = nil
P:OnSync({ act = "snapshot", rev = 2, data = { core = "", mode = "dkp", config = {}, standings = {},
  accounts = { plus1 = { rs = "night", per = NOW, v = { ["Ana-Realm"] = 1, ["Bo-Realm"] = "many", [5] = 1 } },
    ["BAD KEY"] = { rs = "night", per = NOW, v = {} }, tier = "nonsense" } } })
check(theirs.accounts.plus1.v[K("Ana")] == 1 and theirs.accounts.plus1.v[K("Bo")] == nil and theirs.accounts["BAD KEY"] == nil
  and theirs.accounts.tier == nil, "and a client takes from it only what is a counter")
P:OnSync({ act = "snapshot", rev = 3, data = { core = "", mode = "dkp", config = {}, standings = {} } })
check(theirs.accounts.plus1.v[K("Ana")] == 1, "a snapshot from an officer on a version from before leaves the counters alone")
GuildOS.db.points = mine

-- Reset: per night, per lockout, never.
check(P:Counter("plus1", K("Ana")) == 1, "tonight Ana has one")
NOW = NOW + 3 * 3600
check(P:Counter("plus1", K("Ana")) == 1, "three hours on, the same night")
NOW = NOW + 20 * 3600
check(P:Counter("plus1", K("Ana")) == 0, "the next night, everyone starts over")
res = rollOff({ { "Ana", "MS", 90 }, { "Bo", "MS", 10 } })
check(res[1].name == "Ana" and row("Ana").accts.plus1 == 0, "and the roll decides again")
LM:AwardLoot("Ana")
check(P:Counter("plus1", K("Ana")) == 1 and P:Counter("plus1", K("Bo")) == 0, "the new night counts from nothing")
-- A raid session is the night: its start names it, however long it runs.
GuildOS.RaidTracker = { currentRaid = { startTime = NOW }, GetCurrentGroup = function() return "" end,
  GetWeekNum = function(_, ts) return math.floor(ts / 604800) end }
NOW = NOW + 13 * 3600
check(P:Counter("plus1", K("Ana")) == 1, "the same raid session is the same night, thirteen hours in")
GuildOS.RaidTracker.currentRaid = { startTime = NOW }
check(P:Counter("plus1", K("Ana")) == 0, "a new session is a new night")
-- An undo of last night's award takes nothing off tonight.
res = rollOff({ { "Bo", "MS", 90 } })
LM:AwardLoot("Bo")
local last = GuildOS.db.lootMaster.awardHistory
check(last[1].player == "Bo" and last[2].player == "Ana", "two awards, one a night")
last[1].undone = true
LM:UndoLastAward()
check(P:Counter("plus1", K("Bo")) == 1, "undoing last night's award leaves tonight's counters alone")
last[1].undone = nil

check(LR:SetCounterReset("plus1", "lockout") == true and LR:Counters()[1].reset == "lockout", "an officer makes the +1 last the lockout")
res = rollOff({ { "Cy", "MS", 90 } })
LM:AwardLoot("Cy")
check(P:Counter("plus1", K("Cy")) == 1 and P:Counter("plus1", K("Bo")) == 0, "a counter that resets another way starts over")
NOW = NOW + 2 * 86400
GuildOS.RaidTracker.currentRaid = { startTime = NOW }
local week = math.floor(NOW / 604800)
if math.floor((NOW - 2 * 86400) / 604800) == week then
  check(P:Counter("plus1", K("Cy")) == 1, "two days on, in the same lockout, it stands")
end
NOW = (week + 1) * 604800 + 60
check(P:Counter("plus1", K("Cy")) == 0, "past the weekly reset it is gone")
check(LR:SetCounterReset("plus1", "never") == true, "or never resets")
res = rollOff({ { "Cy", "MS", 90 } })
LM:AwardLoot("Cy")
NOW = NOW + 90 * 86400
check(P:Counter("plus1", K("Cy")) == 1, "three months on, a counter that never resets stands")
GuildOS.RaidTracker = nil
check(LR:Set(nil) == true, "back to the +1 as it comes")

-- ── 8. Open bids ────────────────────────────────────────────────────
GuildOS:SetLootSystem("dkpbid")
local bidRule = LR:Active()
check(bidRule.model == "dkpbid" and bidRule.bid.sealed == false and bidRule.bid.min == 10 and bidRule.time == 45,
  "DKP bidding: open, with the least bid and the time the loot settings had")
check(GuildOS:LootSystemUsesPoints(), "it spends the points")
check(LR:ChargeEffect(bidRule).price == "bid", "and the winner pays their bid")
for _, who in ipairs({ "Ana", "Bo", "Cy", "Dee", "Lead" }) do
  P:Adjust(K(who), 100 - P:Get(K(who)), "set", "adjust")
end
P:Adjust(K("Dee"), -70, "set", "adjust")
check(P:Get(K("Ana")) == 100 and P:Get(K("Dee")) == 30, "a hundred points each, thirty for Dee")
sid = announce()
check(sent[1] == "ASK|" .. sid .. "|45,o,10,1;MS=b;OS=b", "the popup is told the bids are open, from 10: " .. sent[1])
check(said[1]:find("bids from 10 in the GuildOS window", 1, true), "and the raid warning says how to bid: " .. said[1])
quiet()
answer("Ana", sid, "MS", 40)
check(row("Ana").bid == 40 and row("Ana").roll == nil, "a bid is kept, with no roll")
check(sent[1] == "BID|" .. sid .. "|Ana|MS|40" and said[1] == "[Loot] Ana: MS, bid 40", "an open bid is told to the raid")
answer("Bo", sid, "MS", 40)
check(row("Bo") == nil and sent[#sent] == "NO|" .. sid .. "|Bo|low|41", "the next bid has to go over it: " .. sent[#sent])
answer("Bo", sid, "MS", 55)
check(row("Bo").bid == 55, "and one that does is kept")
answer("Ana", sid, "MS", 50)
check(row("Ana").bid == 40 and sent[#sent]:find("|low|56$"), "a bid under the best is refused, the one before it stands")
answer("Cy", sid, "MS", 5)
check(row("Cy") == nil and sent[#sent] == "NO|" .. sid .. "|Cy|bid|10", "a bid under the least is refused")
answer("Dee", sid, "MS", 60)
check(row("Dee") == nil and sent[#sent] == "NO|" .. sid .. "|Dee|balance|0", "a bid over the bidder's points is refused: " .. sent[#sent])
answer("Dee", sid, "OS", 30)
check(row("Dee").bid == 30, "an off spec bid is its own run of bids")
LM:ProcessSystemRoll("Cy rolls 100 (1-100)")
check(row("Cy") == nil, "a /roll is no bid")
answer("Ana", sid, "MS", 70)
LM:EndRolling(true)
res = LM.activeLoot.sortedResults
check(res[1].name == "Ana" and res[2].name == "Bo" and res[3].name == "Dee", "the highest main spec bid wins, off spec after")
check(said[#said]:find("[WINNER] Ana - MS (bid 70)", 1, true), "the winner line says the bid: " .. said[#said])
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 30, "the winner pays the bid")
local line = GuildOS.db.points.log[1]
check(line.delta == -70 and line.reason:find("bid 70, paid 70", 1, true), "and the points history keeps the bid and the price: " .. line.reason)
undone = LM:UndoLastAward()
check(undone.player == "Ana" and P:Get(K("Ana")) == 100, "an undo gives the bid back")

-- ── 9. Sealed bids, second price ────────────────────────────────────
GuildOS:SetLootSystem("dkpsealed")
check(LR:Active().bid.sealed == true and LR:ChargeEffect().price == "second", "sealed bids, and the winner pays the second price")
sid = announce()
check(sent[1] == "ASK|" .. sid .. "|45,s,10,1;MS=b;OS=b", "the popup is told the bids are sealed")
quiet()
answer("Ana", sid, "MS", 80, nil, "WHISPER")
answer("Bo", sid, "MS", 50, nil, "WHISPER")
answer("Cy", sid, "MS", 95, nil, "WHISPER")
answer("Cy", sid, "MS", 20, nil, "WHISPER")
answer("Dee", sid, "MS", 31, nil, "WHISPER")
check(row("Ana").bid == 80 and row("Bo").bid == 50, "sealed bids reach the loot master by whisper")
check(row("Cy").bid == 20, "a sealed bid can be changed, down too, until the end")
check(row("Dee") == nil, "and one over the bidder's points is refused all the same")
check(sent[1] == "ACK|" .. sid .. "|Ana|MS", "a sealed bid is acknowledged")
local before_end = all(sent) .. "\n" .. all(said) .. "\n" .. all(printed)
check(not before_end:find("80", 1, true) and not before_end:find("50", 1, true) and not before_end:find("%f[%d]20%f[%D]"),
  "and no figure of a sealed bid leaves the loot master's client before the end:\n" .. before_end)
check(#whispered == 0, "nor is anything whispered back")
LM:OnAddonMessage(LM.PREFIX, "ANNOUNCE|" .. LINK .. "|30|1|0", "WHISPER", "Zed-Realm")
LM:OnAddonMessage(LM.PREFIX, "ANS|" .. sid .. "|MS|99", "WHISPER", "Zed-Realm")
check(row("Zed") == nil, "a whisper from outside the raid is nothing")
LM:EndRolling(true)
res = LM.activeLoot.sortedResults
check(res[1].name == "Ana" and res[2].name == "Bo" and res[3].name == "Cy", "the highest sealed bid wins")
LM:AwardLoot("Ana")
check(P:Get(K("Ana")) == 100 - 51, "and pays one over the second bid, not its own")
line = GuildOS.db.points.log[1]
check(line.delta == -51 and line.reason:find("bid 80, paid 51", 1, true), "the points history keeps both: " .. line.reason)
LM:UndoLastAward()
check(P:Get(K("Ana")) == 100, "an undo gives back what was paid")
sid = announce()
answer("Bo", sid, "MS", 90, nil, "WHISPER")
answer("Cy", sid, "OS", 60, nil, "WHISPER")
LM:EndRolling(true)
LM:AwardLoot("Bo")
check(P:Get(K("Bo")) == 90, "alone in the answer, the winner pays the least bid")
LM:UndoLastAward()
check(LR:PriceFor({ rollType = "MS", bid = 30 }, { { rollType = "MS", bid = 30 } }) == 30, "two equal bids: the price never passes the winner's own")
check(LR:SetBidField("step", 5) == true and LR:PriceFor({ rollType = "MS", bid = 80 }, { { rollType = "MS", bid = 50 } }) == 55,
  "with a step of five, one step over the second")
check(LR:Set(nil) == true, "back to the sealed bids as they come")

-- ── 10. The loot master types in an answer ──────────────────────────
GuildOS:SetLootSystem("dkpbid")
sid = announce()
quiet()
local entered, why, n = LM:EnterAnswer("ana", "MS", 25)
check(entered and row("Ana").bid == 25 and sent[1] == "BID|" .. sid .. "|Ana|MS|25", "a raider's bid, typed in by the loot master in any case")
entered, why = LM:EnterAnswer("Zed", "MS", 25)
check(entered == nil and why == "raid" and row("Zed") == nil, "but never for somebody outside the raid")
entered, why, n = LM:EnterAnswer("Bo", "MS", 25)
check(entered == nil and why == "low" and n == 26, "and held to the same rules as any bid")
entered, why = LM:EnterAnswer("Dee", "MS", 31)
check(entered == nil and why == "balance", "the bidder's points among them")
entered = LM:EnterAnswer("Lead", "OS", 12)
check(entered and row("Lead").bid == 12, "the loot master's own answer goes the same way")
isML = false
entered, why = LM:EnterAnswer("Bo", "MS", 60)
check(entered == nil and why == "ml" and row("Bo") == nil, "only the master looter types answers in")
isML = true
LM:CancelRolling()
GuildOS:SetLootSystem("rolls")
sid = announce()
draws, drawn = { 64 }, 0
entered = LM:EnterAnswer("Cy", "OS")
check(entered and row("Cy").roll == 64 and row("Cy").rollType == "OS" and drawn == 1, "an answer by a roll, typed in, gets its roll here too")
check(LM:WhyNot("raid") == "Only a raid member can answer." and LM:WhyNot("low", 26):find("26", 1, true), "every refusal has its words")
LM:CancelRolling()

-- ── 11. An officer's changes to the answers ─────────────────────────
check(not LR:IsCustom(), "the guild starts on its loot system's rule")
check(LR:AddResponse("tmog", " Transmog ") == true and LR:IsCustom(), "an answer added makes the rule the guild's own")
local now = LR:Responses()
check(#now == 3 and now[3].key == "TMOG" and now[3].label == "Transmog" and now[3].ask == "roll" and now[3].cost == 1,
  "its key in capitals, its label trimmed, a roll at the item's price")
check(LR:Active().model == "custom", "and the rule says it was changed by hand")
check(LR:AddResponse("TMOG") == false and #LR:Responses() == 3, "the same key again is refused")
check(LR:SetResponseField(3, "ask", "none") == true and LR:SetResponseField(3, "cost", "0") == true
  and LR:SetResponseField(3, "label", "Looks") == true, "what it asks for, its price and its label change")
now = LR:Responses()
check(now[3].ask == "none" and now[3].cost == 0 and now[3].label == "Looks", "and are kept")
check(LR:SetResponseField(3, "cost", "abc") == false and LR:SetResponseField(3, "cost", 99) == false and LR:Responses()[3].cost == 0,
  "a price that is not one is refused")
check(LR:SetResponseField(9, "ask", "bid") == false and LR:SetResponseField(1, "key", "X") == false, "nor an answer or a field that is not there")
check(LR:MoveResponse(3, -1) == true and LR:Responses()[2].key == "TMOG" and LR:Responses()[3].key == "OS", "an answer moves up")
check(LR:MoveResponse(1, -1) == false and LR:MoveResponse(3, 1) == false, "but not past either end")
check(LR:MoveResponse(2, 1) == true and LR:Responses()[3].key == "TMOG", "and down")
check(LR:SetResponseField(2, "ask", "bid") == true, "an answer becomes a bid")
local hasBid, hasRoll = false, false
for _, e in ipairs(LR:Active().order) do hasBid = hasBid or e.k == "bid"; hasRoll = hasRoll or e.k == "roll" end
check(hasBid and hasRoll and LR:HasBids(), "and the order then compares by the bid")
check(LR:SetPrice("second") == true and LR:ChargeEffect().price == "second", "what the winner pays changes")
check(LR:SetPrice("table") == true and LR:ChargeEffect() == nil, "and goes back to the item's price")
check(LR:SetBidField("sealed", true) == true and LR:SetBidField("min", "15") == true, "the bids' rules change")
local isSealed, least = LR:BidRules()
check(isSealed and least == 15, "and are kept")
check(LR:SetBidField("min", -3) == false and LR:SetBidField("auction", 1) == false, "but not to nonsense")
check(LR:SetTime(60) == true and LM:RollTime() == 60, "the time to answer changes")
check(LR:SetTime(3) == false and LR:SetTime("soon") == true and LM:RollTime() == 30, "within five seconds to five minutes; none is the loot settings'")
check(LR:RemoveResponse(3) == true and #LR:Responses() == 2, "an answer is removed")
check(LR:RemoveResponse(1) == true and LR:RemoveResponse(1) == false and #LR:Responses() == 1, "down to one, never to none")
GuildOS.IsOfficer = function() return false end
check(LR:AddResponse("NEW") == false and #LR:Responses() == 1, "and only an officer changes any of it")
GuildOS.IsOfficer = function() return true end
GuildOS:SetLootSystem("rolls")
check(not LR:IsCustom() and #LR:Responses() == 2 and LR:Responses()[1].key == "MS", "picking a loot system puts its rule in force again")

-- ── 12. The windows draw, and their buttons reach the module ────────
GuildOS.UI = setmetatable({
  CreateButton = function(_, _, text)
    local b = widget({ text = tostring(text), label = widget() })
    buttons[#buttons + 1] = b
    return b
  end,
  CreateCheckbox = function() return widget({ checkbox = widget() }) end,
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
local function boxes()
  local out = {}
  for _, w in ipairs(widgets) do
    if w.kind == "EditBox" then out[#out + 1] = w end
  end
  return out
end

-- The raider's popup, with the rule's buttons.
isML = false
hear("ASK|D1|30,o,10,5;BIS=bBest in slot;UPG=rUpgrade;TMOG=NTransmog;ALT=r;A5=r;A6=r")
widgets, buttons = {}, {}
local ok, err = pcall(function() hear("ANNOUNCE|" .. LINK .. "|30|28770|0") end)
check(ok, "the popup draws with seven buttons, a bid and a note: " .. tostring(err))
check(button("Best in slot") and button("Transmog") and button("A6") and button("Pass") and #buttons == 7, "one button an answer, and Pass")
local popup = LM.rollPopup
check(popup.highText and popup.replyText and #boxes() == 2, "with a box for the bid, one for the note, and the best bid so far")
quiet()
click("Best in slot")
check(#sent == 0 and popup.replyText.text == "Type your bid first." and not popup.hidden, "a bid button with no bid typed sends nothing")
boxes()[1].text = "40"
click("Best in slot")
check(sent[1] == "ANS|D1|BIS|40" and not popup.hidden, "with one, the bid goes, and the popup stays for the next: " .. tostring(sent[1]))
hear("BID|D1|Ana|BIS|45")
check(popup.highText.text == "Highest bid: 45 (Ana)", "the best bid so far is shown: " .. tostring(popup.highText.text))
hear("NO|D1|Lead|low|50")
check(popup.replyText.text:find("at least 50", 1, true), "and a refusal, where the bid was typed")
quiet()
click("Transmog")
check(#sent == 0 and not popup.hidden, "an answer that needs a note is not sent without one")
boxes()[2].text = "for my alt"
click("Transmog")
check(sent[1] == "ANS|D1|TMOG|0|for my alt" and popup.hidden, "with one it goes, and the popup closes")
-- The default rule: the three buttons where they always were.
hear("ASK|D2|30,-,0,1;MS=r;OS=r")
widgets, buttons = {}, {}
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
check(#buttons == 3 and buttons[1].text == "MS" and buttons[2].text == "OS" and buttons[3].text == "Pass" and #boxes() == 0,
  "with nothing changed the popup is MS, OS and Pass")
quiet()
local rolled = 0
function RandomRoll() rolled = rolled + 1 end
click("OS")
check(sent[1] == "ANS|D2|OS|0" and rolled == 0, "and a click answers by the addon, with no /roll")
hear("ASK|D3|30,-,0,1;MS=r;OS=r")
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
quiet()
click("Pass")
check(sent[1] == "ANS|D3|PASS|0" and LM.rollPopup.hidden, "Pass says so to the loot master")
-- A loot master from before: the popup of before, by /roll.
widgets, buttons = {}, {}
hear("ANNOUNCE|" .. LINK .. "|30|28770|0")
quiet()
click("MS")
check(rolled == 1 and #sent == 0, "with a loot master on a version from before, MS is /roll 1-100 as always")
isML = true

-- The Master Loot roll frame: the "answer for" strip and the rows.
LM.ShowRollFrame = realRollFrame
GuildOS:SetLootSystem("dkpbid")
widgets, buttons = {}, {}
ok, err = pcall(function() sid = announce() end)
check(ok, "the roll frame draws: " .. tostring(err))
check(button("Enter answer") and button("MS") and button("OS"), "with the strip to type an answer in, and the loot master's own buttons")
local strip = boxes()
strip[1].text, strip[2].text = "Bo", "33"
click("Enter answer")
check(row("Bo") and row("Bo").bid == 33 and row("Bo").rollType == "MS" and strip[1].text == "", "a typed answer is entered for the raider")
strip[1].text, strip[2].text = "Zed", "50"
quiet()
click("Enter answer")
check(row("Zed") == nil and printed[1]:find("Only a raid member", 1, true) and strip[1].text == "Zed", "and one for nobody in the raid is said to be so")
local cycle
for _, b in ipairs(buttons) do
  if b.text == "MS" and b.scripts.OnClick and not b.scripts.OnEnter then cycle = b end
end
check(cycle, "the answer to type in is a button")
cycle.scripts.OnClick(cycle)
check(cycle.label.text == "OS", "that a click turns to the next answer")
strip[1].text, strip[2].text = "Cy", "20"
click("Enter answer")
check(row("Cy").rollType == "OS" and row("Cy").bid == 20, "and the answer entered is that one")
ok, err = pcall(function()
  LM.rolls[K("Dee")] = { name = "Dee", class = "MAGE", rollType = "PASS", roll = 0 }
  LM.rolls[K("Ana")] = { name = "Ana", class = "MAGE", rollType = "MS", bid = 60, note = "hi", accts = { plus1 = 2 }, dkp = 100 }
  LM:RefreshRollFrame()
  LM:EndRolling(true)
  LM:UpdateRollTimer()
end)
check(ok, "the rows draw with a bid, a pass, a note and a counter: " .. tostring(err))
LM:CancelRolling()

-- The loot settings: the answers' editor.
dofile(ADDON .. "/UI/FeaturePanels.lua")
GuildOS.CreateRolePicker = function() return widget() end
GuildOS.ShowPointsFrame = function() end
local content = widget()
local function draw()
  widgets, buttons = {}, {}
  local drew, problem = pcall(GuildOS.RefreshSettingsPanel, GuildOS, content, "loot")
  check(drew, "the loot settings draw (" .. tostring(problem) .. ")")
end
GuildOS:SetLootSystem("rolls")
draw()
check(button("Add answer") and button("Roll") and button("Remove") and button("Down") and not button("+1"),
  "the loot settings list the answers, with no +1 where the rule keeps none")
check(button("MS > OS +1") and button("DKP bidding") and button("DKP sealed second-price"), "and offer the three new loot systems")
check(not button("Back to the loot system's rule"), "with nothing changed there is nothing to go back to")
click("Roll")
check(LR:Responses()[2].ask == "bid" and LR:HasBids() and LR:IsCustom(), "a click on what an answer asks for changes the rule, through LootRule")
check(button("Sealed") and button("Their bid") and button("Back to the loot system's rule"), "the bids' own settings show once an answer bids")
click("Sealed")
check((LR:BidRules()) == true, "sealed is a click")
click("The second bid, plus a step")
check(LR:ChargeEffect().price == "second", "and so is the price")
click("Down")
check(LR:Responses()[1].key == "OS", "Down moves an answer")
for _, w in ipairs(boxes()) do
  if w.text == "30" and w.save then w.save("90") break end
end
check(LM:RollTime() == 90, "the time to answer is saved from its box")
printed = {}
for _, w in ipairs(boxes()) do
  if w.text == "90" and w.save then w.save("1") break end
end
check(LM:RollTime() == 90 and #printed == 1, "and a time that is none is refused, with a word to the officer")
click("Back to the loot system's rule")
check(not LR:IsCustom() and LR:Responses()[1].key == "MS", "back to the loot system's rule")
click("MS > OS +1")
check(GuildOS:GetLootSystem() == "plus1", "picking +1 is a click")
check(button("+1") and button("Each raid night") and button("Each lockout") and button("Never"), "its answers say which count, and when the counter starts over")
click("Each lockout")
check(LR:Counters()[1].reset == "lockout", "and that is a click too")
click("DKP sealed second-price")
check(GuildOS:GetLootSystem() == "dkpsealed" and not LR:IsCustom() and button("Open DKP Window"), "DKP by sealed bids shows the points' settings")

math.random = realRandom
print(("loot-responses: %d checks passed"):format(checks))
