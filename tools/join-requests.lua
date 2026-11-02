-- The join request, from both sides (specs/071-o-recrutamento in guildos-web, Tasks B4 and B5), run
-- against the real Core, Compat, Utils, LibDeflate, CompanionExport, CompanionImport, GuildFinder,
-- RecruitBeacon, ChehulGossip and JoinRequests, under a stubbed client and a stubbed mesh.
--
-- From the guildless side: a request is saved and repeated every 300 seconds while online; CRA
-- officer and member update the screen and do NOT stop it, invited and declined do; the screen never
-- says "delivered" without a CRA; three open at most; fourteen days and it expires; joining a guild
-- clears the queue; with no peer heard the contact names are the way; with no whisper nothing is tried;
-- the queue goes to GuildOSDB.recruitOutboxWire as a GOSOUTB1 on logout.
--
-- From the guild's side: CRQ makes one row however many times it comes, a member answers CRA member and
-- relays over GUILD, an officer answers CRA officer, a decision goes over GUILD and every client answers
-- the state to the next CRQ, Invite is live only for a request heard in the last 360 seconds (or one that
-- came from the site) and only from a click, text off the network is inert, one line and cut by
-- character, and joinRequests is an optional field of the export that can fail alone.
--
--   luajit -e 'ADDON="."' tools/join-requests.lua
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

local HOUR, DAY = 3600, 86400
local NOW = 1793750400 + 20 * DAY
local GUILD, officer, canInvite = nil, false, true
local whispers, guildMsgs, invites, banned = {}, {}, {}, {}
local frames, tickers = {}, {}

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
-- A frame that remembers the events it asked for and the scripts it was given, so a test can fire them.
function CreateFrame()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70245", "", 11500 end
WOW_PROJECT_ID = 99
function UnitFullName() return "Chehul", "Costa" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Normal" end
function GetNormalizedRealmName() return "Normal" end
function UnitName() return "Chehul" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 12 end
function UnitFactionGroup() return "Horde" end
function GetLocale() return "enUS" end
function GetCurrentRegion() return 1 end
function GetServerTime() return NOW end
function GetTime() return 1 end
date, time = os.date, os.time
function IsInGuild() return GUILD ~= nil end
function GetGuildInfo() return GUILD, "Rank", 0 end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function IsInInstance() return false end
function CanGuildInvite() return canInvite end
function GuildInvite(name) invites[#invites + 1] = name end
function SendChatMessage() error("nothing here may reach a public channel") end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function strsplit(delim, s)
  local out, from = {}, 1
  while true do
    local at = s:find(delim, from, true)
    if not at then out[#out + 1] = s:sub(from); break end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + 1
  end
  return unpack(out)
end
C_Timer = {
  After = function() end,
  NewTicker = function(interval, fn) tickers[#tickers + 1] = { interval = interval, fn = fn }; return { Cancel = function() end } end,
}
Enum = { SendAddonMessageResult = {} }
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) return registry[name] end })
GuildOSDB = {}

local handler
_G.ChehulMesh = {
  Register = function(_, _, fn) handler = fn end,
  Guild = function(_, prefix, payload) guildMsgs[#guildMsgs + 1] = payload; assert(prefix == "ChehulRecruit") end,
  Group = function() end,
  Realm = function() end,
  Whisper = function(_, prefix, payload, target)
    assert(prefix == "ChehulRecruit")
    whispers[#whispers + 1] = { payload = payload, target = target }
    return true
  end,
}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/GuildFinder.lua")
dofile(ADDON .. "/Modules/ChehulGossip.lua")
dofile(ADDON .. "/Modules/RecruitBeacon.lua")
dofile(ADDON .. "/Modules/JoinRequests.lua")
function GuildOS:IsOfficer() return officer end
GuildOS.BanList = { IsBanned = function(_, name) return banned[name] end }

local JR, Gossip, RB, Import, Companion = GuildOS.JoinRequests, GuildOS.ChehulGossip, GuildOS.RecruitBeacon,
  GuildOS.CompanionImport, GuildOS.Companion
local S = GuildOS.State.gossip
local errors = {}
GuildOS.RecordError = function(_, msg) errors[#errors + 1] = msg end
local LibDeflate = LibStub("LibDeflate")

local function reset()
  GuildOSDB = {}
  GuildOS.db = { settings = { companion = true }, profile = { prefRoles = { HEALER = true } } }
  GUILD, officer, canInvite = nil, false, true
  whispers, guildMsgs, invites, banned = {}, {}, {}, {}
  NOW = 1793750400 + 20 * DAY
  for k in pairs(S.peers) do S.peers[k] = nil end
  S.whisper = "space"
  GuildOSInbox = nil
  Import._blockRaw, Import._blockData = nil, nil
end

local function utf8ok(s)
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local n = b < 0x80 and 1 or (b >= 0xC2 and b < 0xE0) and 2 or (b >= 0xE0 and b < 0xF0) and 3 or (b >= 0xF0 and b < 0xF5) and 4 or nil
    if not n or i + n - 1 > #s then return false end
    for k = 1, n - 1 do
      local c = s:byte(i + k)
      if c < 0x80 or c > 0xBF then return false end
    end
    i = i + n
  end
  return true
end

local ASHEN = { n = "Ashen Vow", u = "ashen-vow", ct = { "Bia Reis", "Caio Dias" }, f = "H", w = "normal:us" }
local function adNamed(n) return { n = n, u = n:lower():gsub("%s", "-"), ct = { "Dora Lima" } } end
local function ticker300()
  for _, t in ipairs(tickers) do if t.interval == 300 then return t end end
end

-- ── The interface the rest relies on ────────────────────────────────────
reset()
Gossip:Initialize()
RB:Initialize()
JR:Initialize()
check(JR and JR.Send and JR.Outbox and JR.Status and JR.OnCRA and JR.OnCRQ and JR.ForExport and JR.Decide
  and JR.OpenCount and JR.List, "the module has the interface the plan names")
check(handler, "RecruitBeacon's handler is on the mesh")

-- ── B4: a request leaves, and is repeated ───────────────────────────────
Gossip:Note("Ana Lima", "Ashen Vow", true)
local req, why = JR:Send(ASHEN, "Jogo toda noite")
check(req and req.id and req.id:match("^%w%w%w%w%w%w%w%w%w%w$"), "a request has a ten-character alphanumeric id: " .. tostring(why))
check(req.character == "Chehul Costa" and req.class == "PALADIN" and req.level == 12 and req.role == "HEALER", "it carries who asks")
check(#JR:Outbox() == 1 and JR:Outbox()[1].id == req.id, "and is saved")
local wirePayload = "CRQ|" .. req.id .. "|Chehul Costa|PALADIN|12|HEALER|Ashen Vow|Jogo toda noite"
check(#whispers == 1 and whispers[1].target == "Ana Lima" and whispers[1].payload == wirePayload, "it goes at once to the officer heard from that guild")
check(JR:Status(req.id) == "stored", "with no answer the screen says it is only kept here")
local tick = ticker300()
check(tick, "and a timer repeats it every 300 seconds")
tick.fn()
check(#whispers == 2 and whispers[2].payload == wirePayload, "the same message again, the same id")

-- CRA officer and member: the screen changes, the repetition does not stop.
handler("CRA|" .. req.id .. "|officer|Ana Lima", "Ana Lima", "WHISPER")
local state, by = JR:Status(req.id)
check(state == "officer" and by == "Ana Lima", "CRA officer: delivered to an officer, and who")
tick.fn()
check(#whispers == 3, "and it keeps repeating")
handler("CRA|" .. req.id .. "|member|Bruno Reis", "Bruno Reis", "WHISPER")
check(JR:Status(req.id) == "officer", "a member's CRA after an officer's does not take the officer back")
tick.fn()
check(#whispers == 4, "CRA member does not stop it either")
handler("CRA|ZZZZZZZZZZ|invited|Eve", "Eve", "WHISPER")
check(JR:Status("ZZZZZZZZZZ") == nil and JR:Status(req.id) == "officer", "a CRA for a request I never made is nothing")
handler("CRA|" .. req.id .. "|officer|Eve\ncff00ff00" .. string.rep("公", 80), "Eve", "WHISPER")
local _, eveBy = JR:Status(req.id)
check(utf8ok(eveBy) and not eveBy:find("%c") and GuildOS:Utf8Len(eveBy) <= 40, "who answered is inert, one line and cut by character")
handler("CRA|" .. req.id .. "|invited|Ana Lima", "Ana Lima", "WHISPER")
check(JR:Status(req.id) == "invited", "CRA invited ends it")
tick.fn()
check(#whispers == 4, "and nothing is sent after")
handler("CRA|" .. req.id .. "|officer|Ana Lima", "Ana Lima", "WHISPER")
check(JR:Status(req.id) == "invited", "a late officer does not reopen it")

-- declined stops too
reset()
Gossip:Note("Ana Lima", "Ashen Vow", true)
req = JR:Send(ASHEN)
handler("CRA|" .. req.id .. "|declined|Ana Lima", "Ana Lima", "WHISPER")
whispers = {}
ticker300().fn()
check(JR:Status(req.id) == "declined" and #whispers == 0, "CRA declined ends it")
check(req.note == nil, "a request with no note has none")

-- three open at most, and once per guild
reset()
check(JR:Send(adNamed("One")) and JR:Send(adNamed("Two")) and JR:Send(adNamed("Three")), "three open requests are fine")
local fourth, reason = JR:Send(adNamed("Four"))
check(fourth == nil and reason == "too-many", "the fourth is refused")
local again, reason2 = JR:Send(adNamed("One"))
check(again == nil and reason2 == "already", "and so is a second to the same guild")
local o3 = JR:Outbox()
handler("CRA|" .. o3[1].id .. "|declined|X", "X", "WHISPER")
check(JR:Send(adNamed("Four")) ~= nil, "a closed one makes room")

-- text the player typed, and a long one
reset()
req = JR:Send(ASHEN, "a|cffff0000b\nc" .. string.rep("公会", 100))
check(not req.note:find("|", 1, true) and not req.note:find("%c") and utf8ok(req.note) and GuildOS:Utf8Len(req.note) == 120, "a note is inert, one line and 120 characters")

-- fourteen days
reset()
Gossip:Note("Ana Lima", "Ashen Vow", true)
req = JR:Send(ASHEN)
NOW = NOW + 14 * DAY + 1
whispers = {}
ticker300().fn()
check(JR:Status(req.id) == "expired" and #whispers == 0, "after fourteen days it is expired and not repeated")
check(JR:Send(ASHEN) ~= nil, "and the guild can be asked again")

-- no peer heard: the contact names; no whisper: nothing
reset()
req = JR:Send(ASHEN, "oi")
local targets = {}
for _, w in ipairs(whispers) do targets[#targets + 1] = w.target end
check(table.concat(targets, ",") == "Bia Reis,Caio Dias", "with nobody heard the ad's contact names are the way: " .. table.concat(targets, ","))
reset()
S.whisper = nil
req = JR:Send(ASHEN, "oi")
check(#whispers == 0 and req and JR:Status(req.id) == "stored", "with no whisper that works nothing is tried, and it is kept")
ticker300().fn()
check(#whispers == 0, "not by the timer either")

-- joining a guild clears the queue
reset()
JR:Send(ASHEN)
GUILD = "Ashen Vow"
fire("PLAYER_GUILD_UPDATE")
check(#JR:Outbox() == 0, "entering a guild clears the queue")
check(JR:Send(ASHEN) == nil, "and a character in a guild asks nobody")

-- the queue for the companion
reset()
Gossip:Note("Ana Lima", "Ashen Vow", true)
req = JR:Send(ASHEN, "Jogo toda noite")
JR:Send(adNamed("Two"))
fire("PLAYER_LOGOUT")
local wire = GuildOSDB.recruitOutboxWire
check(type(wire) == "string" and wire:sub(1, 9) == "GOSOUTB1:", "the queue is written on logout as a GOSOUTB1")
local function decode(text)
  local body = LibDeflate:DecompressDeflate(LibDeflate:DecodeForPrint(text:sub(10)))
  return GuildOS.JsonDecode(body)
end
local out = decode(wire)
check(out.fmt == "GOSOUTB1" and out.v == 1 and #out.requests == 2, "it decodes to the contract's payload")
local first
for _, r in ipairs(out.requests) do if r.id == req.id then first = r end end
check(first and first.slug == "ashen-vow" and first.character == "Chehul Costa" and first.class == "PALADIN" and first.level == 12
  and first.role == "HEALER" and first.note == "Jogo toda noite" and first.at == NOW, "with each request as the contract says")
handler("CRA|" .. req.id .. "|declined|Ana Lima", "Ana Lima", "WHISPER")
fire("PLAYER_LOGOUT")
check(#decode(GuildOSDB.recruitOutboxWire).requests == 1, "an answered request is not sent again")
for _, r in ipairs(JR:Outbox()) do handler("CRA|" .. r.id .. "|declined|Ana Lima", "Ana Lima", "WHISPER") end
fire("PLAYER_LOGOUT")
check(GuildOSDB.recruitOutboxWire == nil, "and with nothing open there is no string")

-- ── B5: the guild's side ────────────────────────────────────────────────
local function crq(id, name, over)
  over = over or {}
  return table.concat({ "CRQ", id, name or "Marta Vilar", over.class or "WARRIOR", over.level or "9", over.role or "TANK",
    over.guild or "Ashen Vow", over.note or "Procuro guilda" }, "|")
end
local function find(id)
  for _, r in ipairs(JR:List()) do if r.id == id then return r end end
end
local function guildSaw(text)
  for _, m in ipairs(guildMsgs) do if m == text then return true end end
  return false
end

reset()
GUILD, officer = "Ashen Vow", false
local msg = crq("abc123DEF4")
handler(msg, "Marta Vilar", "WHISPER")
local row = find("abc123DEF4")
check(row and row.character == "Marta Vilar" and row.class == "WARRIOR" and row.level == 9 and row.role == "TANK"
  and row.note == "Procuro guilda" and row.status == "open" and row.source == "addon", "a CRQ makes a row")
check(whispers[1] and whispers[1].target == "Marta Vilar" and whispers[1].payload == "CRA|abc123DEF4|member|Chehul Costa",
  "a member answers CRA member")
check(guildSaw(msg), "and passes it on over GUILD")
check(GuildOS.db.joinRequests and GuildOS.db.joinRequests.abc123DEF4, "kept in db.joinRequests by id")
NOW = NOW + 100
local before = #guildMsgs
handler(msg, "Marta Vilar", "WHISPER")
check(#JR:List() == 1 and find("abc123DEF4").seen == NOW, "the same CRQ again is one row, heard again")
check(#guildMsgs == before + 1, "(and passed on again: the guild's seen is fresh)")

-- a copy over GUILD: stored, not answered, not passed on again
local whispersBefore, guildBefore = #whispers, #guildMsgs
handler(crq("ghi789JKL0", "Davi Rocha", { class = "MAGE", level = "14", role = "DPS" }), "Bruno Reis", "GUILD")
local viaBruno = find("ghi789JKL0")
check(viaBruno and viaBruno.relayedBy == "Bruno Reis", "a request relayed over GUILD is kept, with who relayed it")
check(#whispers == whispersBefore and #guildMsgs == guildBefore, "and neither answered nor relayed again")

-- an officer answers as one
reset()
GUILD, officer = "Ashen Vow", true
handler(crq("officer123"), "Marta Vilar", "WHISPER")
check(whispers[1].payload == "CRA|officer123|officer|Chehul Costa", "an officer answers CRA officer")
check(JR:OpenCount() == 1, "and has one open")

-- who is ignored
reset()
GUILD = "Ashen Vow"
banned["Marta Vilar"] = true
handler(crq("ban1234567"), "Marta Vilar", "WHISPER")
check(#JR:List() == 0 and #whispers == 0, "somebody on the ban list is ignored")
banned = {}
handler(crq("other12345", "Marta Vilar", { guild = "Another Guild" }), "Marta Vilar", "WHISPER")
check(#JR:List() == 0, "a request for another guild is not mine")
handler(crq("forged1234", "Third Party"), "Marta Vilar", "WHISPER")
check(#JR:List() == 0, "a whisper that names somebody else is not their request")
for _, bad in ipairs({ "CRQ|short|Marta Vilar|WARRIOR|9|TANK|Ashen Vow|x", "CRQ|abc123DEF4|Marta Vilar", "CRQ|abc123DEF4|Marta Vilar|WARRIOR|9|TANK|Ashen Vow|a|b",
    "CRQ|abc123DEF4||WARRIOR|9|TANK|Ashen Vow|x", "CRQ|" .. string.rep("a", 11) .. "|Marta Vilar|WARRIOR|9|TANK|Ashen Vow|x" }) do
  handler(bad, "Marta Vilar", "WHISPER")
end
check(#JR:List() == 0, "malformed ones are not requests")
handler(crq("junk123456", "Marta Vilar", { class = "NOTACLASS", level = "abc", role = "BARD" }), "Marta Vilar", "WHISPER")
local junk = find("junk123456")
check(junk and junk.class == nil and junk.level == nil and junk.role == nil, "a class, level or role outside the closed sets is absent, never kept")

-- text off the network
reset()
GUILD = "Ashen Vow"
local han = string.rep("公会招募", 60)
handler(crq("han1234567", "Marta" .. string.rep("公", 60), { note = han }), "Bruno Reis", "GUILD")
local hanRow = find("han1234567")
check(hanRow and GuildOS:Utf8Len(hanRow.note) == 120 and utf8ok(hanRow.note) and utf8ok(hanRow.character) and GuildOS:Utf8Len(hanRow.character) <= 48,
  "a name and a note are cut by character")
handler(crq("ctl1234567", "Bad\nName", { note = "one\r\ntwo\ttab" }), "Bruno Reis", "GUILD")
local ctl = find("ctl1234567")
check(ctl and not ctl.character:find("%c") and not ctl.note:find("%c"), "and carry no line break")

-- decisions
reset()
GUILD, officer = "Ashen Vow", true
handler(crq("dec1234567"), "Marta Vilar", "WHISPER")
whispers, guildMsgs = {}, {}
check(JR:Decide("dec1234567", "declined") == true, "an officer declines")
local d = find("dec1234567")
check(d.status == "declined" and d.decidedBy == "Chehul Costa", "the row is closed, and says by whom")
check(guildSaw("CRA|dec1234567|declined|Chehul Costa"), "the decision goes over GUILD")
check(JR:Decide("dec1234567", "invited") == false and find("dec1234567").status == "declined", "the first decision wins")
whispers = {}
handler(crq("dec1234567"), "Marta Vilar", "WHISPER")
check(find("dec1234567").status == "declined", "a repeated CRQ does not reopen it")
check(whispers[1] and whispers[1].payload == "CRA|dec1234567|declined|Chehul Costa", "and is answered with the state")
check(JR:Decide("nope", "declined") == false and JR:Decide("dec1234567", "joined") == false, "an unknown id or a state that is not a decision does nothing")

-- another officer's decision over GUILD closes my row
reset()
GUILD = "Ashen Vow"
handler(crq("peer123456"), "Marta Vilar", "WHISPER")
handler("CRA|peer123456|invited|Ana Lima", "Ana Lima", "GUILD")
check(find("peer123456").status == "invited" and find("peer123456").decidedBy == "Ana Lima", "a decision heard on GUILD closes the row here")
handler("CRA|peer123456|declined|Eve", "Eve", "GUILD")
check(find("peer123456").status == "invited", "and the first one stands")
handler(crq("peer654321"), "Marta Vilar", "WHISPER")
handler("CRA|peer654321|invited|Eve", "Eve", "WHISPER")
check(find("peer654321").status == "open", "a decision not heard on GUILD is not a decision")
handler("CRA|peer654321|officer|Eve", "Eve", "GUILD")
check(find("peer654321").status == "open", "nor is an answer that is not one")

-- Invite: a click, a live request, a right to invite
reset()
GUILD, officer = "Ashen Vow", true
handler(crq("inv1234567"), "Marta Vilar", "WHISPER")
check(JR:CanInvite("inv1234567") == true, "a request heard now can be invited")
NOW = NOW + 359
check(JR:CanInvite("inv1234567") == true, "still, at 359 seconds")
NOW = NOW + 2
check(JR:CanInvite("inv1234567") == false, "not after 360: whoever is online repeats it, so silence is offline")
NOW = NOW - 2
canInvite = false
check(JR:CanInvite("inv1234567") == false and JR:Invite("inv1234567") == false and #invites == 0, "without the right to invite nothing is invited")
canInvite = true
guildMsgs = {}
check(JR:Invite("inv1234567") == true and invites[1] == "Marta Vilar", "Invite hands the game the name as it was given")
check(find("inv1234567").status == "invited" and guildSaw("CRA|inv1234567|invited|Chehul Costa"), "and the decision is made and told")
check(JR:Invite("inv1234567") == false and #invites == 1, "once")
check(JR:CanInvite("nope") == false, "an unknown request is not invitable")

-- bounded
reset()
GUILD = "Ashen Vow"
for i = 1, 50 do
  handler(crq(string.format("id%08d", i), "Player " .. i), "Player " .. i, "WHISPER")
  NOW = NOW + 1
end
check(#JR:List() == 50, "fifty are kept")
for i = 1, 3 do JR:Decide(string.format("id%08d", i), "declined") end
handler(crq("id00000051", "Player 51"), "Player 51", "WHISPER")
check(#JR:List() == 50 and find("id00000051") and not find("id00000001"), "the 51st pushes out the oldest closed one")
for i = 4, 50 do JR:Decide(string.format("id%08d", i), "declined") end
JR:Decide("id00000051", "declined")
handler(crq("id00000052", "Player 52"), "Player 52", "WHISPER")
check(#JR:List() == 50 and find("id00000052") and not find("id00000002"), "closed ones go oldest first")
reset()
GUILD = "Ashen Vow"
for i = 1, 50 do handler(crq(string.format("id%08d", i), "Player " .. i), "Player " .. i, "WHISPER") end
handler(crq("id00000099", "Player 99"), "Player 99", "WHISPER")
check(#JR:List() == 50 and not find("id00000099"), "fifty open: the new one waits for room, nothing open is dropped")

-- fourteen days, on this side
reset()
GUILD = "Ashen Vow"
handler(crq("old1234567"), "Marta Vilar", "WHISPER")
NOW = NOW + 14 * DAY + 1
JR:Prune()
check(find("old1234567").status == "expired" and JR:OpenCount() == 0, "a request nobody answered expires in fourteen days")

-- A screen that listens hears the changes, and one that errors costs the others nothing.
reset()
GUILD, officer = "Ashen Vow", true
local heardChanges = 0
JR:Listen(function() error("a screen that breaks") end)
JR:Listen(function() heardChanges = heardChanges + 1 end)
handler(crq("lis1234567"), "Marta Vilar", "WHISPER")
JR:Decide("lis1234567", "declined")
check(heardChanges == 2, "a screen hears a request come and a request decided, whatever the other screen does")

print(("join-requests: %d checks passed"):format(checks))
