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
local roster = {}
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) local m = roster[i]; if m then return m[1], "Rank", m[2] end end
ERR_GUILD_INVITE_S = "You have invited %s to join your guild."
local specRole
C_SpecializationInfo = {
  GetSpecialization = function() return specRole and 1 or nil end,
  GetSpecializationInfo = function() return 73, "Protection", "", "", specRole end,
}
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
local onDb = true
function GuildOS:IsOfficer() return officer end
function GuildOS:IsOnGuildDB() return GUILD ~= nil and onDb end
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
  onDb, specRole = true, nil
  -- The guild's roster: two officers (rank 0 and 1), a plain member of rank 5.
  roster = { { "Ana Lima", 0 }, { "Chehul Costa", 1 }, { "Bruno Reis", 5 }, { "Eve Costa", 4 } }
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
check(#whispers == 4 and whispers[2].payload == wirePayload, "the same message again, the same id (the peer has not answered: the contact names too)")

-- CRA officer and member: the screen changes, the repetition does not stop.
handler("CRA|" .. req.id .. "|officer|Ana Lima", "Ana Lima", "WHISPER")
local state, by = JR:Status(req.id)
check(state == "officer" and by == "Ana Lima", "CRA officer: delivered to an officer, and who")
tick.fn()
check(#whispers == 5, "and it keeps repeating, to the peer that answered alone")
handler("CRA|" .. req.id .. "|member|Bruno Reis", "Bruno Reis", "WHISPER")
check(JR:Status(req.id) == "officer", "a member's CRA after an officer's does not take the officer back")
tick.fn()
check(#whispers == 6, "CRA member does not stop it either")
handler("CRA|ZZZZZZZZZZ|invited|Eve", "Eve", "WHISPER")
check(JR:Status("ZZZZZZZZZZ") == nil and JR:Status(req.id) == "officer", "a CRA for a request I never made is nothing")
handler("CRA|" .. req.id .. "|officer|Eve\ncff00ff00" .. string.rep("公", 80), "Eve", "WHISPER")
local _, eveBy = JR:Status(req.id)
check(utf8ok(eveBy) and not eveBy:find("%c") and GuildOS:Utf8Len(eveBy) <= 40, "who answered is inert, one line and cut by character")
handler("CRA|" .. req.id .. "|invited|Ana Lima", "Ana Lima", "WHISPER")
check(JR:Status(req.id) == "invited", "CRA invited ends it")
tick.fn()
check(#whispers == 6, "and nothing is sent after")
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
check(#guildMsgs == before, "(not relayed again so soon: see the relay gap below)")

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
check(find("inv1234567").status == "open" and not guildSaw("CRA|inv1234567|invited|Chehul Costa"),
  "and the row stays open until the game says the invite went (I3)")
fire("CHAT_MSG_SYSTEM", "You have invited Marta Vilar to join your guild.")
check(find("inv1234567").status == "invited" and guildSaw("CRA|inv1234567|invited|Chehul Costa"), "the game's line closes it, and it is told")
check(JR:Invite("inv1234567") == false and #invites == 1, "once")
check(JR:CanInvite("nope") == false, "an unknown request is not invitable")

-- bounded
reset()
GUILD, officer = "Ashen Vow", true
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

-- ── The export: an optional field, in v13 ───────────────────────────────
reset()
GUILD, officer = "Ashen Vow", true
handler(crq("exp1234567"), "Marta Vilar", "WHISPER")
handler(crq("exp7654321", "Davi Rocha", { class = "MAGE", level = "14", role = "DPS", note = "" }), "Davi Rocha", "WHISPER")
JR:Decide("exp7654321", "declined")
local list = JR:ForExport()
local byId = {}
for _, r in ipairs(list or {}) do byId[r.id] = r end
check(#list == 2 and byId.exp1234567.status == "open" and byId.exp1234567.character == "Marta Vilar" and byId.exp1234567.class == "WARRIOR"
  and byId.exp1234567.level == 9 and byId.exp1234567.role == "TANK" and byId.exp1234567.note == "Procuro guilda" and byId.exp1234567.at, "the contract's shape")
check(byId.exp1234567.decidedBy == nil and byId.exp7654321.status == "declined" and byId.exp7654321.decidedBy == "Chehul Costa", "decidedBy only where somebody decided")
check(byId.exp7654321.note == nil, "a field with nothing in it is absent, never empty or null")
for _, r in ipairs(list) do
  for k, v in pairs(r) do check(type(v) == "string" or type(v) == "number", "field " .. k .. " is a plain value") end
end
NOW = NOW + 15 * DAY
JR:Prune()
local later = JR:ForExport()
check(#later == 1 and later[1].id == "exp7654321", "an expired request is not told to the site: it has its own clock")
JR:Decide("exp1234567", "declined")
for _, r in pairs(GuildOS.db.joinRequests) do r.status = "expired" end
check(JR:ForExport() == nil, "and with nothing to tell the field is absent")

reset()
GUILD, officer = "Ashen Vow", true
GuildOS.Client.isAnniversary = false
roster = {}   -- the export walks the roster and needs members it has no data for
handler(crq("exp1234567"), "Marta Vilar", "WHISPER")
local payload = Companion:BuildPayload()
check(payload and payload.v == 13, "the payload is v13")
check(payload.joinRequests and #payload.joinRequests == 1 and payload.joinRequests[1].id == "exp1234567", "joinRequests rides the export")
local realExport = JR.ForExport
JR.ForExport = function() error("a bug in the requests") end
local ok, broken = pcall(Companion.BuildPayload, Companion)
check(ok and broken and broken.joinRequests == nil and broken.members ~= nil and broken.v == 13, "joinRequests failing is left out and the rest of the export goes")
check(#errors >= 1 and errors[#errors]:find("joinRequests", 1, true), "and the error is recorded")
JR.ForExport = realExport

-- ── The site's joinRequests in the block ────────────────────────────────
local function block(requests)
  local json = Companion.EncodeJson({ fmt = "GOSGILD1", v = 1, guild = "Ashen Vow", at = NOW - 60, joinRequests = requests })
  return "GOSGILD1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json))
end
reset()
GUILD, officer = "Ashen Vow", true
handler(crq("sit1234567"), "Marta Vilar", "WHISPER")
GuildOSInbox = { block({
  { id = "550e8400-e29b-41d4-a716-446655440000", character = "Davi Rocha", class = "MAGE", level = 14, role = "DPS", note = "Procuro", source = "site", status = "open", at = NOW - 3600 },
  { id = "sit1234567", character = "Marta Vilar", class = "WARRIOR", level = 9, role = "TANK", source = "addon", status = "declined", at = NOW - 100 },
  { id = "siteOldBBB2", character = "Gone Away", source = "site", status = "declined", at = NOW - 9000 },
  { id = "siteDupCCC3", character = "Davi Rocha", source = "site", status = "open", at = NOW - 50 },
  { id = "siteBadDDD4", character = "|cffff0000Eve", class = "NOTACLASS", level = 14, role = "BARD", source = "site", status = "open", at = NOW - 20 },
}) }
local site = Import:SiteJoinRequests()
check(site and #site == 5 and site[1].id == "550e8400-e29b-41d4-a716-446655440000", "the block's requests are read")
JR:Refresh()
local davi = find("550e8400-e29b-41d4-a716-446655440000")
check(davi and davi.source == "site" and davi.status == "open" and davi.character == "Davi Rocha" and davi.class == "MAGE" and davi.level == 14, "a request from the site becomes a row")
check(find("sit1234567").status == "declined" and find("sit1234567").decidedBy == "Discord", "a decision made in Discord closes the row here")
check(find("siteOldBBB2") == nil, "a closed request this client never had is not added")
check(find("siteDupCCC3") == nil, "a site request for somebody who already has one open is not a second row")
local eve = find("siteBadDDD4")
check(eve and not eve.character:find("|", 1, true) and eve.class == nil and eve.role == nil, "and what the site sent is cleaned the same way")
local n = #JR:List()
JR:Refresh()
check(#JR:List() == n, "reading it again adds nothing")
check(JR:CanInvite("550e8400-e29b-41d4-a716-446655440000") == true, "a site request can always be invited")
NOW = NOW + 3 * DAY
GuildOSInbox = { block({}) }
Import._blockRaw = nil
check(JR:CanInvite("550e8400-e29b-41d4-a716-446655440000") == true, "even when nobody has heard from the player in days")
check(JR:Decide("550e8400-e29b-41d4-a716-446655440000", "declined") and find("550e8400-e29b-41d4-a716-446655440000").status == "declined", "and decided here")
check(JR:ForExport()[1] ~= nil, "decisions about site requests go back up")

-- A screen that listens hears the changes, and one that errors costs the others nothing.
reset()
GUILD, officer = "Ashen Vow", true
local heardChanges = 0
JR:Listen(function() error("a screen that breaks") end)
JR:Listen(function() heardChanges = heardChanges + 1 end)
handler(crq("lis1234567"), "Marta Vilar", "WHISPER")
JR:Decide("lis1234567", "declined")
check(heardChanges == 2, "a screen hears a request come and a request decided, whatever the other screen does")

-- ── Fix round 1 ─────────────────────────────────────────────────────────
local UUID = "550e8400-e29b-41d4-a716-446655440000"
local UUID2 = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
local function openSite(id, character)
  Import._blockRaw = nil
  GuildOSInbox = { block({ { id = id, character = character or "Davi Rocha", source = "site", status = "open", at = NOW - 60 } }) }
  JR:Refresh()
end

-- C1: a guild heard only by an old CR2 has no slug, and can still be asked.
reset()
RB:Ingest("CR2|Old Guild|H|||oi|enUS||" .. (NOW - 50) .. "|" .. (NOW + 86400) .. "|Zed Rocha", "Zed")
local cr2ad
for _, a in ipairs(GuildOS.GuildFinder:All()) do if a.n == "Old Guild" then cr2ad = a end end
check(cr2ad and cr2ad.u == nil, "a card heard only by CR2 has no slug")
local c1, c1why = JR:Send(cr2ad, "oi")
check(c1 and c1why == nil, "and can still be asked: " .. tostring(c1why))
check(JR:Latest(cr2ad) == c1 and select(2, JR:Send(cr2ad)) == "already", "one per guild, by name when there is no slug")
check(whispers[1] and whispers[1].target == "Zed Rocha", "it goes to the contact the ad names")
fire("PLAYER_LOGOUT")
check(GuildOSDB.recruitOutboxWire == nil, "and the wire leaves out what the site cannot name by slug")
check(JR:Send(nil) == nil and select(2, JR:Send({ u = "x" })) == "no-ad", "an ad with no name is refused, with a reason")

-- C2: a plain member's CRA decides nothing, and so does a plain member's click.
reset(); GUILD, officer = "Ashen Vow", true
handler(crq("for1234567"), "Marta Vilar", "WHISPER")
handler("CRA|for1234567|declined|Ana Lima", "Eve Costa", "GUILD")
check(find("for1234567").status == "open" and JR:ForExport()[1].status == "open", "a member's CRA over GUILD decides nothing, and the export does not tell the site it did")
handler("CRA|for1234567|declined|Ana Lima", "Not On Roster", "GUILD")
check(find("for1234567").status == "open", "nor does somebody who is not on the roster")
officer = false
check(JR:Decide("for1234567", "declined") == false and find("for1234567").status == "open", "a client that is not an officer's cannot decide")
officer = true
handler("CRA|for1234567|declined|Ana Lima", "Ana Lima", "GUILD")
check(find("for1234567").status == "declined", "an officer's CRA does")

-- I1: a site request has a UUID for an id, and its decision crosses GUILD both ways.
reset(); GUILD, officer = "Ashen Vow", true
openSite(UUID)
check(find(UUID) and find(UUID).source == "site", "a request with a UUID id becomes a row")
handler("CRA|" .. UUID .. "|declined|Ana Lima", "Ana Lima", "GUILD")
check(find(UUID).status == "declined", "another officer's decision on it closes it here")
openSite(UUID2, "Marta Vilar")
guildMsgs = {}
check(JR:Decide(UUID2, "declined") and guildSaw("CRA|" .. UUID2 .. "|declined|Chehul Costa"), "and a decision made here is told to the guild")

-- I2: a decided request does not come back to life.
reset(); GUILD, officer = "Ashen Vow", true
handler(crq("reo1234567"), "Marta Vilar", "WHISPER")
JR:Decide("reo1234567", "declined")
whispers, guildMsgs = {}, {}
handler(crq("reo1234567"), "Bruno Reis", "GUILD")
check(guildSaw("CRA|reo1234567|declined|Chehul Costa"), "a relayed CRQ for a closed row makes the decider say so over GUILD")
check(whispers[1] and whispers[1].target == "Marta Vilar" and whispers[1].payload == "CRA|reo1234567|declined|Chehul Costa", "and tell the person")
whispers, guildMsgs = {}, {}
handler(crq("reo1234567"), "Bruno Reis", "GUILD")
check(#guildMsgs == 0 and #whispers == 0, "at most once per repetition")
NOW = NOW + JR.REPEAT_SECONDS
handler(crq("reo1234567"), "Bruno Reis", "GUILD")
check(guildSaw("CRA|reo1234567|declined|Chehul Costa"), "and again on the next one")
GuildOS.db.joinRequests = {}   -- a client that was offline when it was decided
officer = false
handler(crq("reo1234567"), "Bruno Reis", "GUILD")
check(find("reo1234567").status == "open", "it makes the row from the relay")
handler("CRA|reo1234567|declined|Chehul Costa", "Ana Lima", "GUILD")
check(find("reo1234567").status == "declined", "and the officer's word closes it")

-- I3: Invite closes the row only when the game says the invite went.
reset(); GUILD, officer = "Ashen Vow", true
handler(crq("inw1234567"), "Marta Vilar", "WHISPER")
JR:Invite("inw1234567")
NOW = NOW + 30
fire("CHAT_MSG_SYSTEM", "You have invited Marta Vilar to join your guild.")
check(find("inw1234567").status == "open", "a confirmation that comes late closes nothing")
check(JR:Invite("inw1234567") == true and #invites == 2, "and the officer can try again")
fire("CHAT_MSG_SYSTEM", "You have invited Somebody Else to join your guild.")
check(find("inw1234567").status == "open", "a confirmation for another name closes nothing")
issecretvalue = function(v) return v == "SECRET" end
fire("CHAT_MSG_SYSTEM", "SECRET")
issecretvalue = nil
check(find("inw1234567").status == "open", "nor does a line the client keeps secret")
fire("CHAT_MSG_SYSTEM", "You have invited Marta Vilar to join your guild.")
check(find("inw1234567").status == "invited", "the right line, in time, does")
reset(); GUILD, officer = "Ashen Vow", true
openSite(UUID)
JR:Invite(UUID)
check(invites[1] == "Davi Rocha" and find(UUID).status == "open", "a request from the site stays open too: the person may be offline")

-- I4: on retail the realm travels with the name, and the invite takes it as the game wants it.
reset(); GUILD, officer = "Ashen Vow", true
GuildOS.Client.isRetail, GuildOS.Client.has.surnames = true, false
check(JR:Me().character:find("^Chehul%-"), "on retail the name asked with carries its realm: " .. JR:Me().character)
handler(crq("rt11111111", "Ana-Gallywix"), "Ana-Gallywix", "WHISPER")
handler(crq("rt22222222", "Ana-Normal"), "Ana-Normal", "WHISPER")
check(find("rt11111111") and find("rt22222222"), "two Anas of different realms are two people")
JR:Invite("rt11111111"); JR:Invite("rt22222222")
check(invites[1] == "Ana-Gallywix" and invites[2] == "Ana", "the invite keeps a connected realm and drops this one's")
GuildOS.Client.isRetail, GuildOS.Client.has.surnames = false, true

-- I5: asked on the site, then in the game.
reset(); GUILD, officer = "Ashen Vow", true
openSite(UUID)
handler(crq("gam1234567", "Davi Rocha"), "Davi Rocha", "WHISPER")
check(whispers[1] and whispers[1].payload == "CRA|gam1234567|officer|Chehul Costa", "a game request from somebody with a site one open is answered under its own id")
check(find(UUID).seen == NOW and find(UUID).gameId == "gam1234567" and not find("gam1234567"), "and the site row is the one kept, heard now")
whispers = {}
JR:Decide(UUID, "declined")
check(whispers[1] and whispers[1].payload == "CRA|gam1234567|declined|Chehul Costa", "its decision reaches the person under that id")

-- M1: a peer that never answers does not hold the contact names.
reset()
Gossip:Note("Old Addon", "Ashen Vow", true)
req = JR:Send(ASHEN, "oi")
check(#whispers == 1 and whispers[1].target == "Old Addon", "first the peer")
whispers = {}
ticker300().fn()
local seenTargets = {}
for _, w in ipairs(whispers) do seenTargets[#seenTargets + 1] = w.target end
check(table.concat(seenTargets, ",") == "Old Addon,Bia Reis,Caio Dias", "with no answer the next round tries the contact names too: " .. table.concat(seenTargets, ","))
handler("CRA|" .. req.id .. "|member|Old Addon", "Old Addon", "WHISPER")
whispers = {}
ticker300().fn()
check(#whispers == 1, "an answer ends the extra tries")

-- M2: guild names compare without case.
reset(); GUILD = "Ashen Vow"
handler(crq("cas1234567", "Marta Vilar", { guild = "ASHEN vow" }), "Marta Vilar", "WHISPER")
check(find("cas1234567"), "a CRQ whose guild name differs in case is still mine")
reset()
Gossip:Note("Ana Lima", "ASHEN VOW", true)
JR:Send(ASHEN)
check(whispers[1] and whispers[1].target == "Ana Lima", "and so is a peer's guild")

-- M3: the queue does not outlive the asking.
reset()
JR:Send(ASHEN)
GUILD = "Ashen Vow"
ticker300().fn()
check(#JR:Outbox() == 0, "a tick in a guild clears the queue, event or not")

-- M4: nothing is written to a db that is not this guild's.
reset(); GUILD, officer = "Ashen Vow", true
onDb = false
handler(crq("ndb1234567"), "Marta Vilar", "WHISPER")
check(next(GuildOS.db.joinRequests or {}) == nil and #whispers == 0, "off the guild's db a request is nobody's")

-- M5: a corrupt row breaks no screen.
reset(); GUILD = "Ashen Vow"
GuildOS.db.joinRequests = { bad = "x", worse = { id = "w", status = "open" } }
check(pcall(JR.OpenCount, JR) and JR:OpenCount() == 0 and #JR:List() == 0, "a row that is not a row is dropped")

-- M6: the role comes from the spec when nothing was chosen.
reset(); GuildOS.db.profile = { prefRoles = {} }
check(JR:Me().role == nil, "no choice and no spec: absent")
specRole = "TANK"
check(JR:Me().role == "TANK", "the spec's role fills it in")
specRole = "DAMAGER"
check(JR:Me().role == "DPS", "a damage spec is DPS")
GuildOS.db.profile = { prefRoles = { HEALER = true } }
check(JR:Me().role == "HEALER", "a chosen role wins")

-- M7: whether the game can whisper is a fact the screen can ask.
reset()
check(JR:CanReach() == true, "with a whisper that works the guild can be reached from the game")
S.whisper = nil
check(JR:CanReach() == false, "and without one it cannot")

-- M9: a request from the site lights the officer's notice, once.
reset(); GUILD, officer = "Ashen Vow", true
local noticed = {}
GuildOS.JoinRequestsHeard = function(_, r) noticed[#noticed + 1] = r.id end
openSite(UUID)
JR:Refresh()
check(#noticed == 1 and noticed[1] == UUID, "a new site request gives the same notice, once")
GuildOS.JoinRequestsHeard = nil

-- M10 and M11: a request is relayed once per repetition, and drops are counted.
reset(); GUILD, officer = "Ashen Vow", false
handler(crq("rel1234567"), "Marta Vilar", "WHISPER")
local relayed = #guildMsgs
NOW = NOW + 100
handler(crq("rel1234567"), "Marta Vilar", "WHISPER")
check(#guildMsgs == relayed and find("rel1234567").seen == NOW, "heard again within the gap: seen is fresh, nothing is relayed")
NOW = NOW + 200
handler(crq("rel1234567"), "Marta Vilar", "WHISPER")
check(#guildMsgs == relayed + 1, "and relayed again at the next repetition")
local before = JR:Stats()
handler(crq("dr11111111", "Third Party"), "Marta Vilar", "WHISPER")
handler(crq("dr22222222", "Marta Vilar", { guild = "Another Guild" }), "Marta Vilar", "WHISPER")
local after = JR:Stats()
check(after.name == before.name + 1 and after.guild == before.guild + 1, "a name that is not the sender's and a guild that is not mine are counted")

-- B6 fix 1: a request decided while the person was offline does not come back as a new open one.
reset(); GUILD, officer = "Ashen Vow", true
local B6_NOTICED = {}
GuildOS.JoinRequestsHeard = function(_, r) B6_NOTICED[#B6_NOTICED + 1] = r.id end
openSite(UUID)
handler(crq("gam7654321", "Davi Rocha"), "Davi Rocha", "WHISPER")
check(find(UUID).gameId == "gam7654321", "the site's row keeps the game's id")
JR:Decide(UUID, "declined")
whispers, guildMsgs, B6_NOTICED = {}, {}, {}
handler(crq("gam7654321", "Davi Rocha"), "Davi Rocha", "WHISPER")
check(#JR:List() == 1 and find(UUID).status == "declined" and not find("gam7654321"), "the person comes back under the game's id: still one row, still declined")
check(#B6_NOTICED == 0 and JR:OpenCount() == 0, "and no officer is told about a new request")
check(whispers[1] and whispers[1].target == "Davi Rocha" and whispers[1].payload == "CRA|gam7654321|declined|Chehul Costa",
  "the person is told the decision under the id they know")
NOW = NOW + JR.REPEAT_SECONDS
handler(crq("gam7654321", "Davi Rocha"), "Bruno Reis", "GUILD")
check(guildSaw("CRA|" .. UUID .. "|declined|Chehul Costa") and #JR:List() == 1, "a relayed copy makes the decider say it again")
check(whispers[#whispers].payload == "CRA|gam7654321|declined|Chehul Costa", "to the person under the game's id")
-- the id is the game's, the name must still be the row's: an id says nothing about whose it is
whispers, guildMsgs = {}, {}
NOW = NOW + JR.REPEAT_SECONDS
handler(crq("gam7654321", "Somebody Else"), "Somebody Else", "WHISPER")
check(find(UUID).status == "declined" and JR:OpenCount() == 1 and find("gam7654321"), "the id of another person's row is not a way into it")
GuildOS.JoinRequestsHeard = nil

-- B6 fix 2: the invite's confirmation names the same person, whole.
reset(); GUILD, officer = "Ashen Vow", true
handler(crq("pre2222222", "Ana Lima"), "Ana Lima", "WHISPER")
JR:Invite("pre2222222")
fire("CHAT_MSG_SYSTEM", "You have invited Ana to join your guild.")
check(find("pre2222222").status == "open", "'Ana' is not 'Ana Lima': nothing closes")
fire("CHAT_MSG_SYSTEM", "You have invited Ana-Lima to join your guild.")
check(find("pre2222222").status == "invited", "the hyphen is the same person")
reset(); GUILD, officer = "Ashen Vow", true
handler(crq("pre3333333", "Ana"), "Ana", "WHISPER")
JR:Invite("pre3333333")
fire("CHAT_MSG_SYSTEM", "You have invited Ana-Gallywix to join your guild.")
check(find("pre3333333").status == "open", "a name with something after it is another person")
fire("CHAT_MSG_SYSTEM", "You have invited ana to join your guild.")
check(find("pre3333333").status == "invited", "case does not matter")
GuildOS.Client.isRetail, GuildOS.Client.has.surnames = true, false
reset(); GUILD, officer = "Ashen Vow", true
handler(crq("rt33333333", "Ana-Gallywix"), "Ana-Gallywix", "WHISPER")
JR:Invite("rt33333333")
fire("CHAT_MSG_SYSTEM", "You have invited Ana-Normal to join your guild.")
check(find("rt33333333").status == "open", "retail: the same name on another realm is somebody else")
fire("CHAT_MSG_SYSTEM", "You have invited Ana-Gallywix to join your guild.")
check(find("rt33333333").status == "invited", "retail: name and realm both given and the same")
reset(); GUILD, officer = "Ashen Vow", true
handler(crq("rt44444444", "Ana-Normal"), "Ana-Normal", "WHISPER")
JR:Invite("rt44444444")
fire("CHAT_MSG_SYSTEM", "You have invited Ana to join your guild.")
check(find("rt44444444").status == "invited", "retail: the game leaves this realm off, and a side with no realm compares the name")
GuildOS.Client.isRetail, GuildOS.Client.has.surnames = false, true

-- B6: what the Audit panel reads, kept in GuildOSDB and nowhere else.
reset(); GUILD, officer = "Ashen Vow", true
local beforeAudit = Gossip:Audit().requests
handler(crq("aud1111111", "Marta Vilar"), "Marta Vilar", "WHISPER")
JR:Invite("aud1111111")
fire("CHAT_MSG_SYSTEM", "You have invited Marta Vilar to join your guild.")
local audit = Gossip:Audit()
check(audit.requests.confirmed == beforeAudit.confirmed + 1 and audit.requests.invites == beforeAudit.invites + 1,
  "the invite and its confirmation are counted: " .. tostring(audit.requests.confirmed))
check(audit.requests.open == 0 and audit.requests.dropped.name >= 0 and audit.requests.dropped.guild >= 0, "with the drops")
check(audit.requests.asked == 0 and audit.requests.delivered == 0, "a guildless character's open and delivered requests are counted too")
check(audit.gossip.rounds ~= nil and audit.gossip.adsIn ~= nil and audit.gossip.adsOut ~= nil and audit.gossip.peers ~= nil
  and audit.gossip.dropped ~= nil, "the gossip's rounds, ads by origin, known peers and discards")
check(audit.gossip.whisper == "space", "and the spelling the whisper test kept")
check(GuildOSDB.recruitAudit and GuildOSDB.recruitAudit.requests.confirmed == audit.requests.confirmed, "all of it in GuildOSDB")
S.whisper = nil
check(Gossip:Audit().gossip.whisper == false, "no spelling came back: said so")
S.whisper = "space"
GuildOSDB.probeChannel = { timer = true, click = false, heard = { timer = true, click = false }, at = 5 }
check(Gossip:Audit().channel.timer == true and Gossip:Audit().channel.heard.click == false, "the channel probe's result rides along")
GuildOSDB.probeChannel = nil
check(Gossip:Audit().channel == false, "and its absence is said")
local oldJR = GuildOS.JoinRequests
GuildOS.JoinRequests = nil
check(pcall(Gossip.Audit, Gossip), "no counter to read costs nothing")
GuildOS.JoinRequests = oldJR
local realStats = JR.Stats
JR.Stats = function() error("an old save") end
check(pcall(Gossip.Audit, Gossip), "a counter that raises costs nothing either")
JR.Stats = realStats

-- B6: the guildless side's numbers.
reset()
Gossip:Note("Ana Lima", "Ashen Vow", true)
local mine = JR:Send(ASHEN, "oi")
check(Gossip:Audit().requests.asked == 1 and Gossip:Audit().requests.delivered == 0, "one asked, none delivered")
handler("CRA|" .. mine.id .. "|officer|Ana Lima", "Ana Lima", "WHISPER")
check(Gossip:Audit().requests.asked == 1 and Gossip:Audit().requests.delivered == 1, "an answer that says officer is a delivery")

-- B6 fix round 1: the game's id finds a row by the whole name, not by a prefix of it.
reset(); GUILD, officer = "Ashen Vow", true
openSite(UUID, "Ana Lima")
handler(crq("gam8888888", "Ana Lima"), "Ana Lima", "WHISPER")
JR:Decide(UUID, "declined")
whispers = {}
handler(crq("gam8888888", "Ana"), "Ana", "WHISPER")
check(find(UUID).status == "declined" and find(UUID).gameId == "gam8888888", "'Ana' holding the id does not touch the row of 'Ana Lima'")
check(not (whispers[1] and whispers[1].payload:find("declined", 1, true)), "and is not told its decision")

-- M12: the recruiting tab hides the section where the module never starts.
local roster_ui = io.open(ADDON .. "/UI/RosterFrame.lua", "rb"):read("*a")
check(roster_ui:find("isAnniversary", roster_ui:find("Join requests", 1, true), true), "the join requests section of the recruiting tab checks for Anniversary")

print(("join-requests: %d checks passed"):format(checks))
