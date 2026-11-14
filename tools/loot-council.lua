-- The loot council and the record of every award (issue #336), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Modules/CoreManager.lua, Modules/RaidTracker.lua,
-- Modules/Points.lua, Modules/LootRule.lua, Modules/LootMaster.lua, Modules/LootCouncil.lua,
-- Modules/LootTracker.lua, Modules/CompanionExport.lua, UI/FeaturePanels.lua and UI/LootCouncil.lua:
--   * who is on the council: by guild rank, read off this client's own roster, and by name;
--   * the vote: opened by the master looter's client when the answers close, the candidates in the
--     rule's order, one vote a member (a new one replaces the old), a candidate who does not vote on
--     their own item, an anonymous council whose votes are whispered and whose record keeps only the
--     totals, a quorum reached and not reached, a tie broken by the rule's order;
--   * untrusted input: a vote from somebody off the council, outside the raid, for another session, or
--     dressed as somebody else's; a vote opened or closed by anybody but the master looter;
--   * the record ("why") of every award, whoever decides: a roll, a council, an exception, a single
--     candidate; kept with the loot history, pruned with it, sent to the site, gone with an undo;
--   * the rule's note flag, the rule editor's Council section, "Loot council" in the picker, and the
--     window on both sides.
--
--   luajit -e 'ADDON="."' tools/loot-council.lua
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
-- This client's player and guild rank, and the guild roster: { { "Name-Realm", rankIndex }, ... }.
local me, myRank = "Lead", 0
local guild = { { "Lead-Realm", 0 }, { "Ana-Realm", 1 }, { "Bo-Realm", 1 }, { "Cy-Realm", 4 }, { "Dee-Realm", 4 }, { "Eve-Realm", 1 } }
function GetGuildInfo() return "Guild", "Rank", myRank end
function GetNumGuildMembers() return #guild end
function GetGuildRosterInfo(i) return guild[i] and guild[i][1], "Rank", guild[i] and guild[i][2] end
function GuildControlGetNumRanks() return 3 end
function GuildControlGetRankName(i) return ({ "Guild Master", "Officer", "Raider" })[i] end
local inRaid, leader = true, true
function IsInRaid() return inRaid end
function IsInGroup() return true end
function SendChatMessage() end
function GetLootMethod() return "master", nil, 1 end   -- the raid's first is its master looter
local raid = { "Lead", "Ana", "Bo", "Cy", "Dee", "Fay" }   -- Fay is in the raid and not in the guild; Eve the reverse
function UnitIsGroupLeader() return leader end
function UnitIsGroupAssistant() return false end
function InCombatLockdown() return false end
function GetNumGroupMembers() return #raid end
function UnitClass() return "Mage", "MAGE" end
function UnitName(unit)
  if unit == "player" then return me end
  local i = tonumber(tostring(unit):match("^raid(%d+)$"))
  return i and raid[i] or nil
end
function UnitExists(unit) return UnitName(unit) ~= nil end
local timers = {}   -- what a timer would run, for a scene to run when its time is up
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function(_, fn) timers[#timers + 1] = fn; return { Cancel = function() end } end }
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
dofile(ADDON .. "/Modules/LootCouncil.lua")
dofile(ADDON .. "/Modules/LootTracker.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
local function freshDb(system)
  return { settings = { lootSystem = system or "rolls" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
    lootMaster = { awardHistory = {} }, points = {},
    raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
end
GuildOS.db = freshDb()
local LM, LR, P, CM, LC, LT = GuildOS.LootMaster, GuildOS.LootRule, GuildOS.Points, GuildOS.CoreManager, GuildOS.LootCouncil,
  GuildOS.LootTracker
GuildOS.IsOfficer = function() return true end
GuildOS.IsOfficerByName = function() return true end
function GuildOS:ApplyFont() end
function GuildOS:NoteWhisper() end
GuildOS.SyncService = {
  On = function() end, ShouldApply = function() return true end, SetRevision = function() end,
  NextRevision = function() return 1 end, Publish = function() end,
}
P:Initialize()
CM:InitSync()
local function K(name) return GuildOS:GetPlayerKey(name) end

-- What each side sends: the master looter's echoes to the raid, a raider's messages to the raid, and
-- what is whispered.
local said, echo, sent, whispered = {}, {}, {}, {}
local isML = true
LM.SafeSendAddon = function(_, _, payload) sent[#sent + 1] = payload end
LM.SendEcho = function(_, payload) echo[#echo + 1] = payload end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.IsMasterLooter = function() return isML end
GuildOS.Compat.SendAddonMessageNow = function(_, text, channel, target)
  whispered[#whispered + 1] = { text = text, channel = channel, target = target }
end
local att, recv, wishes, reserves = {}, {}, {}, {}
LM.GetPlayerContext = function(_, name) return { att25 = att[name] or 100, recvThisLockout = recv[name] or 0 } end
LM.ShowRollFrame = function() end
LM.StopListeningForRolls = function() end
function GuildOS:Print() end
function GuildOS:UpdateLootSystemUI() end
GuildOS.Wishlist = { GetItemInterest = function() return wishes end }
GuildOS.SoftRes = { GetReserves = function() return reserves end, GetInRaidReserves = function() return {} end }
local function quiet() said, echo, sent, whispered = {}, {}, {}, {} end
local function all(list) return table.concat(list, "\n") end
local function heard(prefix)
  for i = #echo, 1, -1 do
    if echo[i]:sub(1, #prefix) == prefix then return echo[i] end
  end
end

local LINK = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r"
local ITEM = 28770
-- A night starts over under the guild's own rule `r` (nil: the loot system's).
local function night(r, system)
  GuildOS.db = freshDb(system)
  P:Initialize()
  LM.activeLoot, LM.rolls = nil, {}
  GuildOS.State.lootCouncil = nil
  att, recv, wishes, reserves, timers = {}, {}, {}, {}, {}
  me, myRank, isML = "Lead", 0, true
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
local function councilRule(council, more)
  local r = {
    v = 1, model = "council", time = 45,
    responses = { { key = "MS", ask = "none", plus = true }, { key = "OS", ask = "none" } },
    order = { { k = "response" }, { k = "wishlist" }, { k = "received" }, { k = "attendance", band = 10 } },
    decide = { by = "council", council = council },
  }
  for k, v in pairs(more or {}) do r[k] = v end
  return r
end
-- A vote from a raider's client, as the master looter's hears it.
local function vote(sender, text, channel)
  LM:OnAddonMessage(LM.PREFIX, text, channel or "RAID", sender .. "-Realm")
end
-- Whether two values are the same, table by table.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
local function json(v) return GuildOS.Companion.EncodeJson(v) end

-- ── 1. Who is on the council ────────────────────────────────────────
check(LC:IsMember("Ana", { ranks = { 0, 1 } }) and LC:IsMember("Lead", { ranks = { 0, 1 } }), "a member by guild rank")
check(LC:IsMember("Ana-Realm", { ranks = { 1 } }), "the rank is read off the roster by the name the game gives, realm or not")
check(not LC:IsMember("Cy", { ranks = { 0, 1 } }), "a raider of another rank is not one")
check(not LC:IsMember("Fay", { ranks = { 0, 1, 4 } }) and LC:RankOf("Fay") == nil, "nor somebody the guild roster does not hold")
check(LC:IsMember("Fay", { names = { "Fay" } }) and LC:IsMember("fay", { names = { "Fay" } }), "a member by name, whatever the guild says of them")
check(not LC:IsMember("Ana", { names = { "Fay" } }), "a council of names alone has no rank on it")
check(LC:IsMember("Cy", { ranks = { 0 }, names = { "Cy" } }) and LC:IsMember("Lead", { ranks = { 0 }, names = { "Cy" } }), "ranks and names together")
check(LC:IsMember("Bo", {}) and not LC:IsMember("Cy", {}), "with neither, the guild's officers: ranks 0 to the officer threshold")
GuildOS.db.settings.officerMaxRank = 0
check(not LC:IsMember("Bo", {}) and LC:IsMember("Lead", {}), "wherever the guild put that threshold")
GuildOS.db.settings.officerMaxRank = nil
check(not LC:IsMember("", { ranks = { 0 } }) and not LC:IsMember(nil, { ranks = { 0 } }) and not LC:IsMember("Ana", nil), "nobody is nobody's member")

-- ── 2. A vote, start to finish ──────────────────────────────────────
night(councilRule({ ranks = { 0, 1 }, quorum = 2 }))
wishes = { { name = "Dee", order = 1 } }
announce()
check(echo[1] == nil and sent[1]:find("ASK|", 1, true) and sent[1]:find("45,-,0,1;MS=n;OS=n", 1, true), "the item is announced as any other: " .. tostring(sent[1]))
LM:TakeAnswer("Cy", "MS")
LM:TakeAnswer("Dee", "MS")
LM:TakeAnswer("Fay", "OS", nil, "for my off spec")
quiet()
check(order() == "Dee,Cy,Fay", "the answers close in the rule's order: " .. order())
local session = LM.activeLoot.council
local sid = LM.activeLoot.sid
check(session and session.open and session.sid == sid and #session.candidates == 3 and LC:Session() == session, "and a vote opens on that item")
check(all(said):find("3 candidates, the council votes (45s)", 1, true) and not all(said):find("[WINNER]", 1, true),
  "the raid is told a council votes, in place of a winner: " .. all(said))
check(echo[1] == ("COPEN|%s|45|-|2|01|%s"):format(sid, LINK), "the vote is opened to the raid: " .. tostring(echo[1]))
check(echo[2] == ("CCAND|%s|1|Dee|MS|0|0|100|0|0|1|0|0||"):format(sid) and echo[4] == ("CCAND|%s|3|Fay|OS|0|0|100|0|0|0|0|0||for my off spec"):format(sid),
  "with each candidate, in the rule's order, and what the rule knows of them: " .. tostring(echo[2]) .. " / " .. tostring(echo[4]))
check(#timers == 2, "and its time starts running, after the roll's own")
LM:EndRolling(true)
check(LM.activeLoot.council == session and not heard("COPEN|" .. sid .. "|45|-|2|01|x"), "ending the roll twice opens no second vote")

-- Forged: off the council, outside the raid, for another session, dressed as somebody else's.
quiet()
vote("Cy", "CVOTE|" .. sid .. "|2")
check(next(session.votes) == nil and echo[1] == ("CNO|%s|Cy|member"):format(sid), "a raider off the council has no vote, and is told so: " .. tostring(echo[1]))
quiet()
vote("Eve", "CVOTE|" .. sid .. "|2")
check(next(session.votes) == nil and #echo == 0, "an officer who is not in the raid has none either")
vote("Ana", "CVOTE|FFFF|2")
check(next(session.votes) == nil, "a vote for another session is not one for this item")
vote("Cy", "CVOTE|" .. sid .. "|2|Ana")
vote("Cy", "CVOTE|" .. sid .. "|Ana|2")
check(next(session.votes) == nil, "a vote that names its voter is read by nobody: the voter is whoever sent it")
vote("Ana", "CVOTE|" .. sid .. "|" .. string.rep("9", 30))
vote("Ana", "CVOTE|" .. sid .. "|-1")
check(next(session.votes) == nil, "nor one that is not a place")
isML = false
vote("Ana", "CVOTE|" .. sid .. "|2")
isML = true
check(next(session.votes) == nil, "and only the master looter's client counts votes")

-- One vote a member; a new one replaces the old; 0 takes it back.
quiet()
vote("Ana", "CVOTE|" .. sid .. "|2")
check(session.votes.Ana == 2 and session.open, "a member's vote is in, and one of two is no quorum")
check(echo[1] == ("CTALLY|%s|2=1"):format(sid) and echo[2] == ("CWHO|%s|Ana|2"):format(sid), "the council sees the running tally, and who voted for whom")
vote("Ana", "CVOTE|" .. sid .. "|1")
local _, count = LC:Tally(session)
check(session.votes.Ana == 1 and count == 1 and heard("CTALLY") == ("CTALLY|%s|1=1"):format(sid), "a new vote replaces the old one")
vote("Ana", "CVOTE|" .. sid .. "|0")
_, count = LC:Tally(session)
check(session.votes.Ana == nil and count == 0 and heard("CTALLY") == ("CTALLY|%s|-"):format(sid), "0 takes it back")
quiet()
vote("Ana", "CVOTE|" .. sid .. "|9")
check(echo[1] == ("CNO|%s|Ana|unknown"):format(sid), "a place no candidate has is refused")
vote("Ana", "CVOTE|" .. sid .. "|2")
quiet()
vote("Bo", "CVOTE|" .. sid .. "|2")
check(not session.open and session.reason == "quorum" and session.proposed == "Cy", "the second vote is the quorum: the vote closes and proposes")
check(heard("CCLOSE") == ("CCLOSE|%s|q|2"):format(sid) and all(said):find("the council proposes Cy (2 of 2 votes)", 1, true),
  "the raid is told who the council proposes: " .. all(said))
quiet()
vote("Lead", "CVOTE|" .. sid .. "|1")
check(session.votes.Lead == nil and echo[1] == ("CNO|%s|Lead|closed"):format(sid), "a vote after the close is not counted")
local status = LC:StatusText(LC:View())
check(status == "The council proposes Cy. The master looter confirms with Award.", "the master looter reads the proposal: " .. status)

-- The master looter confirms with Award: the record says the council decided, in the exact shape.
local ruleAt = GuildOS.db.settings.lootRuleAt
LM:AwardLoot("Cy")
local entry = GuildOS.db.lootHistory[1]
local expected = {
  v = 1, rule = "council", ruleAt = ruleAt, decidedBy = "council",
  candidates = {
    { name = "Cy", answer = "MS", roll = 0, bid = 0, values = { received = 0, attendance = 100 } },
    { name = "Dee", answer = "MS", roll = 0, bid = 0, values = { wishlist = 1, received = 0, attendance = 100 } },
    { name = "Fay", answer = "OS", roll = 0, bid = 0, values = { received = 0, attendance = 100 } },
  },
  votes = { anon = false, quorum = 2, cast = { { by = "Ana", ["for"] = "Cy" }, { by = "Bo", ["for"] = "Cy" } }, tally = { Cy = 2 } },
}
check(entry.player == "Cy" and same(entry.why, expected), "a council award's record: " .. json(entry.why))
check(ruleAt and ruleAt > 0, "stamped with when the guild's rule was last changed")
check(json(GuildOS.Companion.LootWhy(entry.why)) == '{"candidates":[{"answer":"MS","bid":0,"name":"Cy","roll":0,"values":{"attendance":100,"received":0}},'
  .. '{"answer":"MS","bid":0,"name":"Dee","roll":0,"values":{"attendance":100,"received":0,"wishlist":1}},'
  .. '{"answer":"OS","bid":0,"name":"Fay","roll":0,"values":{"attendance":100,"received":0}}],"decidedBy":"council","rule":"council","ruleAt":'
  .. ruleAt .. ',"v":1,"votes":{"anon":false,"cast":[{"by":"Ana","for":"Cy"},{"by":"Bo","for":"Cy"}],"quorum":2,"tally":{"Cy":2}}}',
  "and as it goes to the site: " .. json(GuildOS.Companion.LootWhy(entry.why)))
check(LM.activeLoot == nil, "the item is given")
-- An undo takes the award back, record and all.
local undone = LM:UndoLastAward()
check(undone and undone.player == "Cy" and #GuildOS.db.lootHistory == 0, "an undo of a council award takes its line, and the record with it")

-- ── 3. A candidate on the council ───────────────────────────────────
night(councilRule({ ranks = { 0, 1 }, quorum = 2 }))
announce()
LM:TakeAnswer("Ana", "MS")
LM:TakeAnswer("Cy", "MS")
LM:EndRolling(true)
session, sid = LM.activeLoot.council, LM.activeLoot.sid
quiet()
vote("Ana", "CVOTE|" .. sid .. "|1")
check(session.votes.Ana == nil and echo[1] == ("CNO|%s|Ana|self"):format(sid), "a member who is a candidate does not vote on that item")
LM:CancelRolling()
check(not session.open and session.reason == "cancel" and session.proposed == nil and heard("CCLOSE") == ("CCLOSE|%s|x|0"):format(sid),
  "cancelling the roll ends its vote, and proposes nobody")
night(councilRule({ ranks = { 0, 1 }, quorum = 2, self = true }))
announce()
LM:TakeAnswer("Ana", "MS")
LM:TakeAnswer("Cy", "MS")
LM:EndRolling(true)
session, sid = LM.activeLoot.council, LM.activeLoot.sid
check(echo[#echo - 2] == ("COPEN|%s|45|s|2|01|%s"):format(sid, LINK), "a council whose candidates vote says so: " .. tostring(echo[#echo - 2]))
vote("Ana", "CVOTE|" .. sid .. "|1")
check(session.votes.Ana == 1, "and with self on, they do")

-- ── 4. A tie goes to whoever the rule's order puts first ────────────
vote("Bo", "CVOTE|" .. sid .. "|2")
check(not session.open and session.proposed == "Ana", "one vote each: the rule's order breaks the tie")
-- The master looter gives it to somebody else: the record says the master looter decided.
LM:AwardLoot("Cy")
local why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "ml" and why.candidates[1].name == "Cy" and why.candidates[2].name == "Ana" and why.votes.tally.Ana == 1
  and why.votes.tally.Cy == 1, "awarded against the proposal: the winner first, the votes kept, decided by the master looter")

-- ── 5. The quorum not reached ───────────────────────────────────────
night(councilRule({ ranks = { 0, 1 }, quorum = 3 }, { time = 10 }))
announce()
LM:TakeAnswer("Cy", "MS")
LM:TakeAnswer("Dee", "MS")
LM:EndRolling(true)
session, sid = LM.activeLoot.council, LM.activeLoot.sid
check(session.seconds == 30 and session.endsAt == NOW + 30, "a vote stays open thirty seconds at least, whatever the rule's time")
vote("Ana", "CVOTE|" .. sid .. "|2")
check(session.open, "one vote of three: still open")
check(LC:StatusText(LC:View()) == "Council vote: 1 of 3 votes needed, 30s left", "the master looter reads where it stands")
quiet()
timers[#timers]()
check(not session.open and session.reason == "timeout" and session.noQuorum and session.proposed == nil, "time is up with no quorum: nobody is proposed")
check(all(said):find("no quorum (1 of 3 votes): the master looter decides", 1, true) and heard("CCLOSE") == ("CCLOSE|%s|t|0"):format(sid),
  "and the raid is told the master looter decides: " .. all(said))
check(LC:StatusText(LC:View()) == "No proposal from the council: the master looter decides.", "so is the master looter")
timers[#timers]()
check(session.reason == "timeout", "a timer that fires twice changes nothing")
LM:AwardLoot("Dee")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "ml" and why.votes.quorum == 3 and why.votes.tally.Dee == 1 and #why.votes.cast == 1 and why.candidates[1].name == "Dee",
  "the record says the master looter decided, with the votes there were: " .. json(why))
-- An old timer of that item, after the next one is announced, closes nothing.
announce()
LM:TakeAnswer("Cy", "MS")
LM:TakeAnswer("Dee", "MS")
LM:EndRolling(true)
session = LM.activeLoot.council
timers[2]()
check(session.open, "the vote's timer of the item before does not close this one's vote")
-- The master looter ends the vote: whoever has the most votes is proposed, quorum or not.
vote("Bo", "CVOTE|" .. LM.activeLoot.sid .. "|2")
check(LC:EndVote() == "Dee" and session.reason == "ml" and session.proposed == "Dee", "the master looter ends the vote: the leader is proposed")
LM:AwardLoot("Dee")
check(GuildOS.db.lootHistory[1].why.decidedBy == "council", "and confirming them is the council's decision")
-- Awarding while the vote is open ends it there.
announce()
LM:TakeAnswer("Cy", "MS")
LM:TakeAnswer("Dee", "MS")
LM:EndRolling(true)
session = LM.activeLoot.council
vote("Ana", "CVOTE|" .. LM.activeLoot.sid .. "|1")
LM:AwardLoot("Cy")
check(not session.open and GuildOS.db.lootHistory[1].why.decidedBy == "council" and GuildOS.db.lootHistory[1].why.votes.tally.Cy == 1,
  "an award while the vote is open ends it; the leader awarded is the council's")
-- No vote at all, no quorum asked for: the master looter decides.
night(councilRule({ ranks = { 0, 1 } }))
announce()
LM:TakeAnswer("Cy", "MS")
LM:TakeAnswer("Dee", "MS")
LM:EndRolling(true)
session = LM.activeLoot.council
check(echo[#echo - 2]:find("|45|-|0|01|", 1, true), "a council with no quorum says none: " .. echo[#echo - 2])
quiet()
timers[#timers]()
check(session.proposed == nil and all(said):find("nobody voted: the master looter decides", 1, true), "nobody voted: " .. all(said))
LM:AwardLoot("Cy")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "ml" and why.votes.quorum == 0 and why.votes.tally == nil and #why.votes.cast == 0
  and json(GuildOS.Companion.LootWhy(why).votes) == '{"anon":false,"cast":[],"quorum":0}', "the record has the vote that nobody cast")

-- ── 6. An anonymous council, by name, from a member's own client ────
night(councilRule({ names = { "Fay", "Ana" }, anon = true, quorum = 2 }))
announce()
LM:TakeAnswer("Cy", "MS")
LM:TakeAnswer("Dee", "MS")
quiet()
LM:EndRolling(true)
session, sid = LM.activeLoot.council, LM.activeLoot.sid
local opened = echo
check(opened[1] == ("COPEN|%s|45|a|2|-|%s"):format(sid, LINK) and opened[2] == ("CMEM|%s|Fay,Ana"):format(sid),
  "an anonymous council of names: no rank, and the members named: " .. opened[1] .. " / " .. opened[2])
-- Ana's client.
local shown = 0
GuildOS.ShowLootCouncil = function() shown = shown + 1 end
local function asRaider(name, rank, fn)
  me, myRank, isML = name, rank, false
  fn()
  me, myRank, isML = "Lead", 0, true
end
local function hear(list, sender)
  for _, text in ipairs(list) do LM:OnAddonMessage(LM.PREFIX, text, "RAID", (sender or "Lead") .. "-Realm") end
end
asRaider("Ana", 1, function()
  hear(opened, "Cy")
  check(GuildOS.State.lootCouncil == nil and shown == 0, "a vote opened by anybody but the master looter is not one")
  hear({ opened[1] })
  local w = GuildOS.State.lootCouncil
  check(w and w.sid == sid and w.ml == "Lead-Realm" and w.anon and not w.member and shown == 0, "the master looter's is; by rank Ana is not on this council")
  hear({ opened[2], opened[3], opened[4] })
  check(w.member and shown == 1, "by name she is, and her window opens")
  local view = LC:View()
  check(#view.candidates == 2 and view.candidates[1].name == "Cy" and view.candidates[2].name == "Dee" and view.canVote and not view.isML,
    "she sees the candidates in the rule's order, and may vote")
  hear({ ("CCAND|%s|2|Mallory|MS|0|0|100|0|0|0|0|0||"):format(sid) }, "Cy")
  hear({ ("CCLOSE|%s|q|1"):format(sid) }, "Cy")
  hear({ ("CCAND|FFFF|2|Mallory|MS|0|0|100|0|0|0|0|0||") })
  check(w.candidates[2].name == "Dee" and w.open, "a candidate or a close from anybody else, or for another session, changes nothing")
  quiet()
  check(LC:Vote(1) == true and #sent == 0 and #whispered == 1 and whispered[1].channel == "WHISPER" and whispered[1].target == "Lead-Realm"
    and whispered[1].text == ("CVOTE|%s|1"):format(sid), "an anonymous vote is whispered to the master looter, as a sealed bid is")
  check(LC:View().mine == 1, "and her window shows her own vote at once")
end)
quiet()
vote("Ana", "CVOTE|" .. sid .. "|1", "WHISPER")
check(session.votes.Ana == 1 and echo[1] == ("CTALLY|%s|1=1"):format(sid) and #echo == 1, "counted, and the raid hears the total and never who")
local tally = echo
asRaider("Ana", 1, function()
  hear(tally)
  hear({ ("CWHO|%s|Ana|1"):format(sid) })
  local view = LC:View()
  check(view.candidates[1].votes == 1 and #view.candidates[1].voters == 0 and view.cast == 1, "the council sees the totals, and no names")
  check(LC:StatusText(view) == "Council vote: 1 of 2 votes needed, 45s left", "and where the vote stands")
end)
-- A raider who is not on it sees no window and has no vote.
asRaider("Cy", 4, function()
  GuildOS.State.lootCouncil = nil
  shown = 0
  hear(opened)
  local view = LC:View()
  check(shown == 0 and view and not view.canVote and view.whyNot == "member", "a raider off the council is shown no window")
  quiet()
  local ok, why2 = LC:Vote(1)
  check(ok == false and why2 == "member" and #sent == 0 and #whispered == 0, "and their client sends no vote")
end)
-- Fay, by name and not of the guild, is the quorum. Her client, then the close.
quiet()
vote("Fay", "CVOTE|" .. sid .. "|1", "WHISPER")
check(not session.open and session.proposed == "Cy", "a member by name who is in no guild rank votes; the quorum is in")
local closed = echo
asRaider("Ana", 1, function()
  GuildOS.State.lootCouncil = nil
  hear(opened)
  hear(closed)
  local view = LC:View()
  check(not view.open and view.proposed == "Cy" and view.reason == "quorum" and not view.canVote, "the member's window reads the close and who is proposed")
end)
LM:AwardLoot("Cy")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "council" and why.votes.anon == true and why.votes.cast == nil and why.votes.tally.Cy == 2,
  "an anonymous council's record keeps the totals and not who voted for whom")
check(json(GuildOS.Companion.LootWhy(why).votes) == '{"anon":true,"quorum":2,"tally":{"Cy":2}}', "nor does the site ever get them")
-- An open council's vote goes over the raid, and a refusal reaches the voter's window.
night(councilRule({ ranks = { 0, 1 }, quorum = 2 }))
announce()
LM:TakeAnswer("Bo", "MS")
LM:TakeAnswer("Dee", "MS")
quiet()
LM:EndRolling(true)
session, sid = LM.activeLoot.council, LM.activeLoot.sid
opened = echo
asRaider("Bo", 1, function()
  GuildOS.State.lootCouncil = nil
  hear(opened)
  local view = LC:View()
  check(view.member and not view.canVote and view.whyNot == "self", "a member who is a candidate reads that they have no vote on this item")
  quiet()
  LC:Vote(2)
  check(#whispered == 0 and sent[1] == ("CVOTE|%s|2"):format(sid), "an open council's vote goes over the raid")
  hear({ ("CNO|%s|Bo|self"):format(sid) })
  check(LC:View().mine == nil and GuildOS.State.lootCouncil.refused == "self", "and the master looter's refusal takes it off the window")
end)
asRaider("Ana", 1, function()
  GuildOS.State.lootCouncil = nil
  hear(opened)
  hear({ ("CTALLY|%s|2=1"):format(sid), ("CWHO|%s|Lead|2"):format(sid) })
  local view = LC:View()
  check(view.candidates[2].votes == 1 and view.candidates[2].voters[1] == "Lead", "an open council's members see who voted for whom")
  hear({ ("CTALLY|%s|2=999,77=1"):format(sid) })
  check(LC:View().candidates[2].votes == 0, "a tally no raid could cast is not shown")
end)
-- A client from before knows none of these messages.
local module = GuildOS.LootCouncil
GuildOS.LootCouncil = nil
local quietly = pcall(function()
  hear(opened)
  vote("Ana", "CVOTE|" .. sid .. "|2")
  vote("Ana", "CVOTE|" .. sid .. "|2", "WHISPER")
end)
GuildOS.LootCouncil = module
check(quietly and next(session.votes) == nil, "a client without the council reads none of its messages, and nothing breaks")
LM:CancelRolling()
GuildOS.ShowLootCouncil = nil

-- ── 7. The record of every other award ──────────────────────────────
-- A roll: the candidates in the rule's order with what each criterion compared, and the criterion
-- that put the winner ahead.
local rolls = {
  v = 1, model = "softres",
  accounts = { { key = "plus1", type = "counter", name = "+1", reset = "night" } },
  order = { { k = "softres" }, { k = "response" }, { k = "account", acct = "plus1", dir = "low" }, { k = "attendance", band = 10 }, { k = "roll" } },
  effects = { { k = "add", acct = "plus1", value = 1 } },
}
night(rolls)
reserves = { { name = "Ana" } }
att = { Ana = 96, Bo = 80 }
P:AddCounter("plus1", K("Bo"), 1, "night")
announce()
LM:RegisterRoll("Ana", "MS", 41)
LM:RegisterRoll("Bo", "MS", 99)
LM:RegisterRoll("Cy", "OS", 77)
LM:RegisterRoll("Dee", "PASS", 0)
check(order() == "Ana,Bo,Cy" and LM.activeLoot.council == nil, "a rule with no council opens no vote: " .. order())
ruleAt = GuildOS.db.settings.lootRuleAt
LM:AwardLoot("Ana")
entry = GuildOS.db.lootHistory[1]
expected = {
  v = 1, rule = "softres", ruleAt = ruleAt, decidedBy = "softres",
  candidates = {
    { name = "Ana", answer = "MS", roll = 41, bid = 0, values = { softres = 1, ["account:plus1"] = 0, attendance = 96 } },
    { name = "Bo", answer = "MS", roll = 99, bid = 0, values = { softres = 0, ["account:plus1"] = 1, attendance = 80 } },
    { name = "Cy", answer = "OS", roll = 77, bid = 0, values = { softres = 0, ["account:plus1"] = 0, attendance = 100 } },
  },
}
check(same(entry.why, expected), "a roll award's record, with nobody who passed and no votes: " .. json(entry.why))
check(P:Counter("plus1", K("Ana")) == 1 and entry.why.candidates[1].values["account:plus1"] == 0, "the figures are the ones the order was read from, before the award moved any")
check(GuildOS.db.lootMaster.awardHistory[1].why == nil, "kept once, with the loot history, not a second time with the award log")
-- The master looter gives it to the second: "ml", the winner still first.
announce()
LM:RegisterRoll("Ana", "MS", 41)
LM:RegisterRoll("Bo", "MS", 99)
LM:EndRolling(true)
LM:AwardLoot("Bo")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "ml" and why.candidates[1].name == "Bo" and why.candidates[2].name == "Ana", "awarded against the order: decided by the master looter")
-- A single candidate.
announce()
LM:RegisterRoll("Cy", "OS", 5)
LM:EndRolling(true)
LM:AwardLoot("Cy")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "only" and #why.candidates == 1 and why.votes == nil and why.exception == nil, "a single candidate: \"only\"")
-- Every criterion tied: nothing in the rule told them apart.
reserves = {}
att = {}
LR:Set({ v = 1, model = "custom", order = { { k = "response" }, { k = "roll" } } })
announce()
LM:RegisterRoll("Cy", "MS", 50)
LM:RegisterRoll("Dee", "MS", 50)
LM:EndRolling(true)
LM:AwardLoot("Cy")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "ml" and why.rule == "custom" and why.candidates[1].values == nil, "a tie on every criterion is the master looter's to settle; no figure beside the roll, no values")
-- Before the roll ended, and with no roll at all.
announce()
LM:RegisterRoll("Cy", "MS", 10)
LM:RegisterRoll("Dee", "MS", 90)
LM:AwardLoot("Dee")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "roll" and why.candidates[1].name == "Dee" and why.candidates[1].roll == 90, "given before the roll's end: by the answers so far")
LM:SetActiveLoot(LINK, nil, ITEM)
LM:AwardLoot("Fay")
why = GuildOS.db.lootHistory[1].why
check(same(why, { v = 1, rule = "custom", ruleAt = GuildOS.db.settings.lootRuleAt, decidedBy = "ml",
  candidates = { { name = "Fay", answer = "", roll = 0, bid = 0 } } }), "given straight from the loot window: the winner, no answer, the master looter: " .. json(why))
-- Ten candidates at most.
raid = {}
for i = 1, 14 do raid[i] = "Raider" .. string.char(64 + i) end
announce()
for i = 1, 14 do LM:RegisterRoll(raid[i], "MS", i) end
LM:EndRolling(true)
LM:AwardLoot("RaiderN")
why = GuildOS.db.lootHistory[1].why
check(#why.candidates == 10 and why.candidates[1].name == "RaiderN" and why.candidates[10].name == "RaiderE", "ten candidates at most, the best of the order")
raid = { "Lead", "Ana", "Bo", "Cy", "Dee", "Fay" }
-- A loot system's own rule: no stamp. A bid.
night(nil, "dkpbid")
P:Award(K("Ana"), 100, "seed")
P:Award(K("Bo"), 60, "seed")
announce()
LM:TakeAnswer("Bo", "MS", 50)
LM:TakeAnswer("Ana", "MS", 70)
LM:EndRolling(true)
LM:AwardLoot("Ana")
why = GuildOS.db.lootHistory[1].why
check(why.rule == "dkpbid" and why.ruleAt == 0 and why.decidedBy == "bid" and why.candidates[1].bid == 70 and why.candidates[1].values.points == 100
  and why.candidates[2].bid == 50, "a loot system's rule has no stamp; a bid award: " .. json(why))
-- An exception that swaps blocks, and one with a fixed destination.
night({ v = 1, model = "rolls", order = { { k = "response" }, { k = "roll" } }, exceptions = {
  { on = { items = { ITEM } }, name = "Thunderfury", set = { order = { { k = "attendance" }, { k = "roll" } } } },
  { on = { items = { 19019 } }, name = "To the bank", to = "bank" },
} })
att = { Cy = 90, Dee = 60 }
announce()
LM:RegisterRoll("Cy", "OS", 1)
LM:RegisterRoll("Dee", "MS", 99)
check(order() == "Cy,Dee", "the exception's own order decides the item")
LM:AwardLoot("Cy")
why = GuildOS.db.lootHistory[1].why
check(why.exception == "Thunderfury" and why.decidedBy == "attendance" and why.rule == "rolls" and why.candidates[1].values.attendance == 90,
  "an exception award's record names the exception, and compares what its order compared: " .. json(why))
LM:SetBank("Banker")
LM.lootWindowOpen = false
LM:AnnounceItem("|cffff8000|Hitem:19019::::::::70:::::|h[Thunderfury]|h|r", nil)
why = GuildOS.db.lootHistory[1].why
check(GuildOS.db.lootHistory[1].player == "Banker" and same(why, { v = 1, rule = "rolls", ruleAt = GuildOS.db.settings.lootRuleAt,
  decidedBy = "ml", exception = "To the bank", candidates = { { name = "Banker", answer = "", roll = 0, bid = 0 } } }),
  "an item sent to the bank by an exception: " .. json(why))
-- A council inside an exception: that item is voted on, the rest is not.
night({ v = 1, model = "rolls", order = { { k = "response" }, { k = "roll" } }, exceptions = {
  { on = { items = { ITEM } }, name = "Legendary", set = { decide = { by = "council", council = { ranks = { 0, 1 }, quorum = 1 } } } },
} })
announce()
LM:RegisterRoll("Cy", "MS", 1)
LM:RegisterRoll("Dee", "MS", 99)
LM:EndRolling(true)
check(LM.activeLoot.council and LM.activeLoot.council.open, "an exception can hand one item to a council")
vote("Ana", "CVOTE|" .. LM.activeLoot.sid .. "|2")
LM:AwardLoot("Cy")
why = GuildOS.db.lootHistory[1].why
check(why.decidedBy == "council" and why.exception == "Legendary" and why.votes.quorum == 1, "and the record has both")

-- The stamp: the night's rule, a core's own, the guild's own, a loot system's.
night(nil, "rolls")
check(LR:Stamp() == 0, "a loot system's rule has no stamp")
LR:Set({ v = 1, order = { { k = "roll" } } })
check(LR:Stamp() == GuildOS.db.settings.lootRuleAt and LR:Stamp() > 0, "the guild's own rule: when an officer last saved it")
CM:Create("Alpha")
GuildOS.RaidTracker:SetGroupTag("Alpha")
check(LR:Stamp() == GuildOS.db.settings.lootRuleAt, "a core that follows the guild has the guild's")
GuildOS:SetLootSystem("plus1", "Alpha")
check(LR:Stamp() == 0, "a core on its own loot system has none")
LR:Set({ v = 1, order = { { k = "roll" } } }, "Alpha")
check(LR:Stamp() == GuildOS.db.cores.Alpha.lootMaster.lootAt and LR:Stamp() > 0, "a core's own rule: when it was last changed")
GuildOS.RaidTracker:SetGroupTag("")
GuildOS.db.companionRoster = { raidId = "r1", startsAt = NOW - 600, title = "T", members = {}, lootRule = { v = 1, model = "rolls", order = { { k = "roll" } } } }
check(LR:Active().model == "rolls" and LR:Stamp() == NOW - 600, "the raid night's rule: the night's start")
GuildOS.db.companionRoster, GuildOS.db.lootNight = nil, nil

-- Kept small: only the newest entries keep their record, and an entry recorded by a peer has none.
night(nil, "rolls")
for i = 1, 230 do
  LT:RecordMLAward({ itemLink = LINK, player = "P" .. i, timestamp = NOW + i, fromML = true, why = { v = 1, candidates = {} } })
end
local withWhy, last = 0, 0
for i, e in ipairs(GuildOS.db.lootHistory) do
  if e.why then withWhy, last = withWhy + 1, i end
end
check(#GuildOS.db.lootHistory == 230 and withWhy == 200 and last == 200 and GuildOS.db.lootHistory[1].player == "P230",
  "the record is kept on the two hundred newest entries: " .. withWhy)
GuildOS.db.lootHistory = {}
LM:OnAddonMessage(LM.PREFIX, "AWARD|Cy|28770|4|Karazhan|" .. LINK, "RAID", "Off-Realm")
check(#GuildOS.db.lootHistory == 1 and GuildOS.db.lootHistory[1].why == nil, "an award heard from another officer is recorded as before, with no record of why")

-- ── 8. The council reads a note with every answer ───────────────────
night(councilRule({ ranks = { 0, 1 }, note = true }))
check(LR:NeedsNote(LR:Responses()[1], LR:Active()) and LR:Encode(LR:Active()):find("MS=N;OS=N", 1, true), "the buttons ask for a note: " .. LR:Encode(LR:Active()))
announce()
local row, whyNot = LM:TakeAnswer("Cy", "MS")
check(row == nil and whyNot == "note", "an answer with no note is not taken")
check(LM:TakeAnswer("Cy", "MS", nil, "my last tier piece") and LM:TakeAnswer("Dee", "PASS"), "one with a note is; a pass needs none")
check(LM.rolls[K("Cy")].note == "my last tier piece", "and the note is kept for the council")
LM:CancelRolling()
local plain = councilRule({ ranks = { 0, 1 }, note = true })
plain.decide.by = "ml"
check(not LR:NeedsNote(plain.responses[1], plain) and LR:Encode(plain):find("MS=n", 1, true), "the council's flag is the council's: with another decider it asks for none")

-- ── 9. "Loot council" in the picker ─────────────────────────────────
local offered = {}
for _, sys in ipairs(GuildOS:LootSystemsHere()) do offered[sys.key] = GuildOS:LootSystemLabel(sys) end
check(offered.council == "Loot council", "the picker offers it")
night(nil, "council")
local ready = LR:Active()
check(LR:Validate(ready) and ready.model == "council" and LR:Council().quorum == 2 and same(LR:Council().ranks, { 0, 1 })
  and ready.responses[1].ask == "none" and ready.time == 60, "its rule: the guild's officers vote, two votes close it, nobody rolls")
GuildOS.db.settings.officerMaxRank = 2
check(same(LR:Council(LR:Active()).ranks, { 0, 1, 2 }), "the officers are whoever the guild's officer threshold says")
GuildOS.db.settings.officerMaxRank = nil
check(LR:PlaysWhole() and not LR:PlaysWhole({ v = 1, order = { { k = "roll" } } }), "a council's rule is played whole")
wishes = { { name = "Cy", order = 1 }, { name = "Dee", order = 1 } }
announce()
check(LM.restrictedRollers == nil and said[1]:find("[ROLL]", 1, true), "two raiders tied on the wishlist do not close the roll to the rest: " .. tostring(said[1]))
LM:TakeAnswer("Cy", "MS")
quiet()
LM:EndRolling(true)
check(LM.activeLoot.council == nil and all(said):find("[WINNER] Cy", 1, true), "one candidate needs no vote: " .. all(said))
LM:AwardLoot("Cy")
check(GuildOS.db.lootHistory[1].why.decidedBy == "only" and GuildOS.db.lootHistory[1].why.votes == nil, "and its record says so")

-- ── 10. The windows ─────────────────────────────────────────────────
GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })
local saves = {}
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
    saves[#saves + 1] = box
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
dofile(ADDON .. "/UI/LootCouncil.lua")

-- The rule editor's Council section.
night(nil, "rolls")
widgets, buttons, saves = {}, {}, {}
local drew, problem = pcall(GuildOS.ShowLootRuleEditor, GuildOS, "")
check(drew, "the rule editor draws (" .. tostring(problem) .. ")")
check(button("The order") and button("The master looter") and button("A council's vote") and not button("Officer"),
  "it asks who decides, and shows no council while none does")
click("A council's vote")
check(LR:IsCustom() and same(LR:Council(), { ranks = { 0, 1 }, quorum = 2 }), "a click hands the items to a council: the guild's officers, two votes")
check(button("Guild Master") and button("Officer") and button("Raider"), "with a button a guild rank")
click("Raider")
check(same(LR:Council().ranks, { 0, 1, 2 }), "a click puts a rank on the council")
click("Guild Master")
check(same(LR:Council().ranks, { 1, 2 }), "and another takes one off")
local function box(text)
  for i = #saves, 1, -1 do
    if saves[i].text == text then return saves[i] end
  end
end
check(box("2"), "the quorum is there to change")
box("2").save("3")
check(LR:Council().quorum == 3, "and saving it changes the rule")
box("3").save("")
check(LR:Council().quorum == nil, "empty is no quorum")
LR:SetCouncilField("names", "Fay, Gil  fay", "")
check(same(LR:Council().names, { "Fay", "Gil" }), "members by name, as typed, each once")
saves, buttons = {}, {}
GuildOS:ShowLootRuleEditor("")
check(box("Fay, Gil"), "shown as they were kept")
box("Fay, Gil").save("Hal")
check(same(LR:Council().names, { "Hal" }), "and saved from the editor's own box")
check(LR:SetCouncilField("anon", true) and LR:SetCouncilField("self", true) and LR:SetCouncilField("note", true)
  and LR:Council().anon and LR:Council().self and LR:Council().note, "the three switches")
check(select(2, LR:SetCouncilField("colour", "red")) == "decide" and LR:SetCouncilField("quorum", 99) == false, "nothing else, and no quorum past a raid")
click("The master looter")
check(LR:Council() == nil and LR:Active().decide.by == "ml" and select(2, LR:SetCouncilField("anon", true)) == "decide",
  "back to the master looter: no council to set")

-- The council window, on the master looter's client and on a member's.
night(councilRule({ ranks = { 0, 1 }, quorum = 3 }))
announce()
LM:TakeAnswer("Cy", "MS", nil, "bis")
LM:TakeAnswer("Dee", "MS")
widgets, buttons = {}, {}
quiet()
drew, problem = pcall(LM.EndRolling, LM, true)
check(drew, "the window draws when the vote opens (" .. tostring(problem) .. ")")
session, sid = LM.activeLoot.council, LM.activeLoot.sid
opened = { echo[1], echo[2], echo[3] }   -- the opening, and the two candidates
check(button("Vote") and button("End vote") and not button("End vote").hidden, "the master looter, a member, has a Vote button a candidate and ends the vote")
click("Vote")
check(session.votes.Lead == 2 and LC:View().mine == 2, "a click is a vote, counted here: the last row drawn is the second candidate")
check(button("Voted") and not button("Abstain").hidden, "the row says so, and the vote can be taken back")
click("Abstain")
check(session.votes.Lead == nil, "which is a click")
click("End vote")
check(not session.open and button("End vote").hidden, "ending the vote is a click too")
LM:CancelRolling()
asRaider("Ana", 1, function()
  GuildOS.State.lootCouncil = nil
  widgets, buttons = {}, {}
  local ok, err = pcall(hear, opened)
  check(ok, "a member's window draws from the master looter's messages (" .. tostring(err) .. ")")
  check(button("Vote") and (not button("End vote") or button("End vote").hidden), "with a Vote button, and no way to end the vote")
  quiet()
  click("Vote")
  check(sent[1] == ("CVOTE|%s|2"):format(sid), "whose click sends the vote to the master looter: " .. tostring(sent[1]) .. " " .. #whispered)
end)

print(("loot-council: %d checks passed"):format(checks))
