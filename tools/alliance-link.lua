-- The alliance the GreenWall way (issue #348), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Libs (LibDeflate, LibSerialize), Modules/Alliance.lua, Modules/AllianceChat.lua,
-- Modules/GuildChat.lua and Modules/AllianceLink.lua under a stubbed client.
--
-- One client of "Guilda A". Proves:
--   * the alliance code is read and refused when it is broken; an officer saves it, the guild hands it
--     on (set / ask / have), the newest wins, a removal sticks, and only an officer's copy counts;
--   * it is the alliance every module reads and names no ambassadors; the ambassador pact is gone and
--     its verbs say where alliances live now (audit #448, specs/salao/alianca.md §3.4);
--   * the hidden channel is joined with the key and taken out of the chat frames, its lines never
--     print raw, and the old pact's public channel is left once;
--   * a line of /g the player sends from a chat box or the Guild tab goes on the channel, inside the
--     key press; officer chat never does;
--   * a channel line from an allied guild is drawn as /g by the frame's own handler, tagged, in the
--     frames that show /g only; ours, our own guild's /g, an unknown guild's are not; the player's
--     switch turns the shared /g off; the room's lines go to the alliance feed, our guild's too;
--     a line too long for its frame goes in parts;
--   * who is on now is who was heard on the channel, and the mesh's GuildOS clients of the allied
--     guilds; a speaker's guild tags their whisper;
--   * the directory and open raids (GOSALLY1) answer nothing without the site's block, and what reads
--     them works once they do (the block itself: tools/guild-block.lua);
--   * an officer blocks an allied guild (review A): its /g and room lines are not shown, it is not on now,
--     /gos ally block|unblock, kept through a key change;
--   * the old pact's channel is left by each of the account's characters, never the code's own channel
--     when the names meet (reviews B, C);
--   * guildos.me's code (GOSGILD1 `alliance`) is held to its shape, wins over a pasted one and the GM's
--     note, is never written into the guild's copy; a new key leaves the old channel and joins with the
--     new one; a block that names none ends the alliance and leaves its channel, the dead code in the
--     note does not come back, another code an officer pasted does;
--   * the short code goes in the guild master's public note and every member reads it from there,
--     nobody online; the guilds are the ones heard on the channel; the relay asks back a newer
--     holder and keeps a copy that came before the roster (issue #431).
--
--   luajit -e 'ADDON="."' tools/alliance-link.lua
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

-- ── The client ──────────────────────────────────────────────────────────
local NOW = 1791000000
function GetServerTime() return NOW end
time = function() return NOW end
function GetTime() return NOW end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function GetNormalizedRealmName() return "Realm" end
function UnitName() return "Ana" end
function GetGuildInfo() return "Guilda A", "Officer", 1, nil end
function IsInGuild() return true end
function GetNumGuildMembers() return 0 end
function Ambiguate(name) return (tostring(name):gsub("%-.*$", "")) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
  local out, start = {}, 1
  while true do
    if n and #out == n - 1 then out[#out + 1] = s:sub(start); break end
    local i = s:find(sep, start, true)
    if not i then out[#out + 1] = s:sub(start); break end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + 1
  end
  return unpack(out)
end
function GetPlayerInfoByGUID(guid) if guid == "Player-1-B" then return "Mage", "MAGE" end end
CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s: "
NUM_CHAT_WINDOWS = 2


-- Channels: joined with a password, listed in frames, numbered.
local joined, channelArgs, removed = {}, {}, {}
function JoinTemporaryChannel(name, password) joined[name] = password; channelArgs[#channelArgs + 1] = { name, password } end
function GetChannelName(name) return joined[name] and 5 or 0 end
local frameChannels = { { "GOSANUCLEO", 0, "General", 1 }, {} }
function GetChatWindowChannels(i) return unpack(frameChannels[i] or {}) end
function ChatFrame_RemoveChannel(frame, name) removed[#removed + 1] = { frame = frame, name = name } end

local sent = {}
function SendChatMessage(msg, chatType, lang, target) sent[#sent + 1] = { msg = msg, chatType = chatType, target = target } end

-- Two chat frames: the first shows /g. The frame's handler records what it is handed.
local replayed = { {}, {} }
ChatFrame1 = { shows = true }
ChatFrame2 = { shows = false }
function ChatFrame_ContainsMessageGroup(f, group) return group == "GUILD" and f.shows end
function ChatFrame_MessageEventHandler(frame, event, ...)
  local i = frame == ChatFrame1 and 1 or 2
  replayed[i][#replayed[i] + 1] = { event = event, args = { ... } }
  return true
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

-- Chat filters, by event.
local filters = {}
function ChatFrame_AddMessageEventFilter(event, fn) filters[event] = filters[event] or {}; table.insert(filters[event], fn) end

-- The chat box and its ParseText, post-hooked as the game does.
local box = { attrs = {}, text = "" }
function box:GetAttribute(k) return self.attrs[k] end
function box:GetText() return self.text end
function box:ParseText() end
ChatFrame1EditBox = box
function hooksecurefunc(a, b, c)
  if type(a) == "table" then
    local orig = a[b]
    a[b] = function(...) local r = orig(...); c(...); return r end
  end
end

local ignored = {}
C_FriendList = { IsIgnored = function(name) return ignored[name] == true end }
local deferred, defer = {}, false
C_Timer = {
  After = function(_, fn) if defer then deferred[#deferred + 1] = fn else fn() end end,
  NewTicker = function() return { Cancel = function() end } end,
}

local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:UnregisterAllEvents() self.events = {} end
  function f:SetScript(_, fn) self.fn = fn end
  function f:HookScript() end
  frames[#frames + 1] = f
  return f
end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
}, { __call = function(_, name, silent)
  if registry[name] or silent then return registry[name] end
  error("no lib " .. name)
end })

local whispers = {}
ChehulMesh = {
  Register = function() end,
  Whisper = function(_, prefix, payload, target) whispers[#whispers + 1] = { prefix = prefix, payload = payload, target = target }; return true end,
  Guild = function() return true end,
}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test",
            SelfTest = { Register = function() end } }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Modules/Alliance.lua")
dofile(ADDON .. "/Modules/AllianceChat.lua")
dofile(ADDON .. "/Modules/GuildChat.lua")
dofile(ADDON .. "/Modules/AllianceLink.lua")
GuildOS.State = GuildOS.State or {}
GuildOS.isGuilded = true
GuildOS.db = { members = {} }
local officer = true
GuildOS.IsOfficer = function() return officer end
local officers = { ["Ofi-Realm"] = true, ["Ana-Realm"] = true }
GuildOS.IsOfficerByName = function(_, name) return officers[name] == true end
-- The guild's sync: what we publish, and the handler the module registers.
local published, syncHandlers = {}, {}
GuildOS.SyncService = {
  Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end,
  On = function(_, dom, fn) syncHandlers[dom] = fn end,
}
local function setCode(line, rev) GuildOS.db.allianceLink = { line = line, rev = rev or 1 } end
-- The hidden channel's name comes from the code: the tag and a hash of the key (follow-up 1).
local CH = GuildOS.AllianceLink.ChannelNameFor("NUCLEO", "Kx7Pq2Lm9Z")
frameChannels[1][1] = CH

local A, Link, Chat, GC = GuildOS.Alliance, GuildOS.AllianceLink, GuildOS.AllianceChat, GuildOS.GuildChat
local printed = {}
GuildOS.Print = function(_, msg) printed[#printed + 1] = msg end
Chat:Prefs()
Link:Initialize()
check(#(filters.CHAT_MSG_CHANNEL or {}) == 1, "the channel's lines get a filter")

-- ── 1. The line ────────────────────────────────────────────────────────
local line = Link.Build("nucleo", "Kx7Pq2Lm9Z", { "Guilda A", "Guilda B", "Guilda C" })
check(line == "GOS=NUCLEO:Kx7Pq2Lm9Z:Guilda A;Guilda B;Guilda C", "the line reads as documented")
local cfg = Link.Parse("Bem-vindos!\n" .. line .. "\nRaide quinta")
check(cfg and cfg.tag == "NUCLEO" and cfg.key == "Kx7Pq2Lm9Z" and #cfg.order == 3, "parsed out of any text around it")
check(cfg.guilds["Guilda B"] == Link.Code("Guilda B") and cfg.codes[Link.Code("Guilda C")] == "Guilda C", "codes both ways")
check(#Link.Code("Guilda B") == 3 and Link.Code("Guilda B") == Link.Code("Guilda B"), "a code is three characters, stable")
check(Link.Parse("GOS=NUCLEO:Kx7Pq2Lm9Z:Guilda A") == nil, "one guild is no alliance")
check(Link.Parse("GOS=NUCLEO:k:Guilda A;Guilda B") == nil, "a key too short is refused")
check(Link.Parse("GOS=...:Kx7Pq2Lm9Z:Guilda A;Guilda B") == nil, "a tag with nothing usable is refused")
check(Link.Parse("nada aqui") == nil and Link.Parse(nil) == nil, "no line, no alliance")
local short = Link.Build("nucleo", "Kx7Pq2Lm9Z")
check(short == "GOS=NUCLEO:Kx7Pq2Lm9Z", "the short code names no guild (issue #431)")
local sc = Link.Parse("Main do GM " .. short)
check(sc and sc.open and sc.tag == "NUCLEO" and sc.key == "Kx7Pq2Lm9Z" and sc.line == short, "read in the middle of a note")
check(#Link.Build(string.rep("T", 12), Link.NewKey()) <= Link.NOTE_MAX, "the longest short code fits a public note")
-- The hidden channel's name (follow-up 1): from the code alone, so every guild agrees; a new key is a new channel.
local longest = Link.ChannelNameFor(string.rep("T", 12), "Zz9Yy8Xx7W")
check(#longest == 22 and longest:match("^[A-Za-z0-9]+$") and longest:sub(1, 16) == "GOSA" .. string.rep("T", 12),
  "the longest channel name is 22 letters and digits, no hyphen, under the 31 the game keeps")
check(Link.ChannelNameFor("NUCLEO", "Kx7Pq2Lm9Z") == Link.ChannelNameFor("nucleo", "Kx7Pq2Lm9Z"), "the same code, the same channel")
check(Link.ChannelNameFor("NUCLEO", "Kx7Pq2Lm9Z") ~= Link.ChannelNameFor("NUCLEO", "Kx7Pq2Lm9Y"), "another key, another channel")
local key = Link.NewKey()
check(#key == Link.KEY_LEN and key:match("^%w+$"), "a new key is alphanumeric")
check(Link.Decode(Link.Encode("G", "abc", "oi gente")) == "G", "a channel line round-trips")
local k2, c2, t2 = Link.Decode("Gabc oi gente")
check(k2 == "G" and c2 == "abc" and t2 == "oi gente", "decoded into kind, code and text")
check(Link.Decode("oi gente") == nil, "a human line is not ours")
check(#Link.Encode("G", "abc", string.rep("é", 200)) <= 255, "a long line fits the chat line")

-- ── 2. The alliance comes from the alliance code ───────────────────────
check(A:Get() == nil and A:Name() == nil, "no code, no alliance")
setCode(line)
local pact = A:Get()
check(pact and pact.source == "link" and pact.tag == "NUCLEO" and A:Name() == "NUCLEO", "the code is the alliance")
check(pact.guilds["Guilda C"] and #pact.guilds["Guilda C"].ambassadors == 0, "and names no ambassadors")
check(A:CanAdminister(), "an officer of a guild in it may hide a line of the room")
setCode("GOS=NUCLEO:Kx7Pq2Lm9Z:Guilda B;Guilda C")
check(A:Get() == nil, "a code that does not name this guild is not this guild's alliance")
setCode(line)
-- The ambassador pact is gone (audit #448): its verbs say where alliances live now.
for _, verb in ipairs({ "create NUC Nucleo", "invite Zed", "leave", "join X-1", "code", "amb add Bob" }) do
  printed = {}
  A:HandleCommand(verb)
  check(#printed == 1 and printed[1] == "Alliances now live on guildos.me.", "/gos ally " .. verb .. ": the migration line")
end
printed = {}
A:HandleCommand("")
check(printed[1] == "Alliance NUCLEO [NUCLEO] - 3 guilds", "/gos ally: the alliance and its guilds")
for _, gone in ipairs({ "Create", "Invite", "Leave", "OnMessage", "Send", "ElectBridge", "SendToAmbassadors", "BoardPosts" }) do
  check(A[gone] == nil, "the pact's " .. gone .. " is gone")
end
check(GuildOS.AllianceSync == nil and Link.Candidates == nil and Link.Learn == nil, "and so are its sync and its mesh discovery")
check(Chat.PromoteAmbassadors == nil and Chat.EnsureAmbassadorOwnership == nil, "and the ambassadors' channel moderation")

-- ── 3. The hidden channel ──────────────────────────────────────────────
joined["GOSOLD"] = ""
GuildOS.db.allianceLeaveChannel = "GOSOLD"   -- kept by ResolveGuildDB when it cleared the old pact
local left = {}
function LeaveChannelByName(name) left[#left + 1] = name; joined[name] = nil end
check(Chat:EnsureJoined(), "the watchdog joins it")
check(left[1] == "GOSOLD" and #left == 1, "and leaves the old pact's public channel, once")
check(GuildOS.db.allianceLeaveChannel == "GOSOLD" and GuildOS.db.allianceLeftBy["Ana-Realm"] == true,
  "review B: the name stays for the account's other characters, this one marked as having left it")
check(joined[CH] == "Kx7Pq2Lm9Z", "with the key as the password")
check(#removed == 1 and removed[1].frame == ChatFrame1 and removed[1].name == CH, "and takes it out of the frame that listed it")
Chat:EnsureJoined()
check(#left == 1, "the old channel is left never again")
-- Review B: another character of the account, sharing the guild's db, is in the old channel too and leaves it.
local realUnitName = UnitName
UnitName = function() return "Bia" end
joined["GOSOLD"] = ""
Chat:EnsureJoined()
check(#left == 2 and left[2] == "GOSOLD" and GuildOS.db.allianceLeftBy["Bia-Realm"] == true,
  "review B: a second character of the account leaves the old channel as well")
UnitName = realUnitName
-- Review 2: the hidden channel as 1.27-1.43 named it (GOSA .. TAG, no hash of the key) is left once per character.
do
  local n = #left
  joined["GOSANUCLEO"] = "Kx7Pq2Lm9Z"
  Chat:EnsureJoined()
  check(#left == n + 1 and left[#left] == "GOSANUCLEO" and joined[CH] ~= nil,
    "review 2: the unhashed channel of the code in force is left, the hashed one kept")
  joined["GOSANUCLEO"] = "Kx7Pq2Lm9Z"
  Chat:EnsureJoined()
  check(#left == n + 1, "review 2: once per character (a channel joined again by hand stays)")
  UnitName = function() return "Bia" end
  Chat:EnsureJoined()
  check(#left == n + 2 and left[#left] == "GOSANUCLEO", "review 2: another character of the account leaves it too")
  UnitName = realUnitName
  joined["GOSANUCLEO"] = nil
end
-- Review C: an old pact's channel name that is the hidden channel in force is never left as the old one.
do
  local keepLink, keepLeft = GuildOS.db.allianceLink, GuildOS.db.allianceLeftBy
  local BR = Link.ChannelNameFor("BR", "Kx7Pq2Lm9Z")
  GuildOS.db.allianceLeftBy, GuildOS.db.allianceLeaveChannel = {}, BR
  setCode("GOS=BR:Kx7Pq2Lm9Z", 2)
  Link._pact = nil
  joined[BR] = "Kx7Pq2Lm9Z"
  local n = #left
  Chat:_LeaveLegacy()
  check(#left == n and joined[BR] ~= nil, "review C: the old name that is the channel in force is not left")
  GuildOS.db.allianceLink, GuildOS.db.allianceLeftBy, GuildOS.db.allianceLeaveChannel = keepLink, keepLeft, "GOSOLD"
  joined[BR] = nil
  Link._pact = nil
  GuildOS.db.allianceLinkJoined = nil
  Chat:EnsureJoined()
end
local hidden = filters.CHAT_MSG_CHANNEL[1](nil, "CHAT_MSG_CHANNEL", "Gabc x", "Bob", "", "", "", "", 0, 5, CH)
check(hidden == true, "its lines never print raw")
check(not filters.CHAT_MSG_CHANNEL[1](nil, "CHAT_MSG_CHANNEL", "oi", "Bob", "", "", "", "", 0, 1, "General"), "another channel passes")
check(filters.CHAT_MSG_CHANNEL_NOTICE and filters.CHAT_MSG_CHANNEL_JOIN, "its notices are filtered too")

-- ── 4. Out: the player's own words, in the key press ───────────────────
sent = {}
box.attrs.chatType, box.text = "GUILD", "alguem pra kara?"
box:ParseText(1)
check(#sent == 1 and sent[1].chatType == "CHANNEL" and sent[1].target == 5, "a line of /g goes on the channel")
check(sent[1].msg == "G" .. Link.Code("Guilda A") .. " alguem pra kara?", "framed with our guild's code")
sent = {}
box:ParseText(true)
check(#sent == 1, "a client that sends with true sends too (issue #431)")
sent = {}
box:ParseText(0)
check(#sent == 0, "only the send, not the typing")
box.attrs.chatType = "OFFICER"
box:ParseText(1)
check(#sent == 0, "officer chat never goes")
box.attrs.chatType = "SAY"
box:ParseText(1)
check(#sent == 0, "nor anything else")
GC:Send("pelo addon", nil)
local toChannel = 0
for _, m in ipairs(sent) do if m.chatType == "CHANNEL" then toChannel = toChannel + 1 end end
check(toChannel == 1, "the Guild tab's Send goes on the channel too")
sent = {}
Chat:Send("oi alianca")
check(#sent == 1 and sent[1].msg == "A" .. Link.Code("Guilda A") .. " oi alianca", "the room goes framed as A")
local log = Chat:Log()
check(log[#log].m == "oi alianca" and log[#log].g == "Guilda A", "and shows in our feed at once")

-- ── 5. In: drawn as /g ─────────────────────────────────────────────────
local recv
for _, f in ipairs(frames) do if f.events.CHAT_MSG_CHANNEL and f.fn then recv = f end end
local function hear(msg, author, chan, guid)
  recv.fn(recv, "CHAT_MSG_CHANNEL", msg, author, "Common", "5. " .. CH, "", "", 0, 5, chan or CH, 0, 77, guid)
end
local function reset() replayed[1], replayed[2] = {}, {} end
reset()
hear("G" .. Link.Code("Guilda B") .. " bora", "Bob-Realm", nil, "Player-1-B")
check(#replayed[1] == 1 and #replayed[2] == 0, "drawn in the frame that shows /g only")
local ev = replayed[1][1]
check(ev.event == "CHAT_MSG_GUILD", "as a line of /g")
check(ev.args[1]:find("[Guilda B]", 1, true) and ev.args[1]:find("bora", 1, true), "tagged with the guild")
check(ev.args[2] == "Bob-Realm" and ev.args[12] == "Player-1-B" and ev.args[11] == 77, "the sender, line and GUID of the channel line")
local entries = GC:Entries(nil)
check(entries[#entries].g == "Guilda B" and entries[#entries].c == "MAGE", "the Guild tab has it, with its guild and class")

reset()
hear("G" .. Link.Code("Guilda A") .. " falso", "Eve-Realm")
check(#replayed[1] == 0, "our own guild's code is not believed")
hear("Gzzz desconhecida", "Eve-Realm")
check(#replayed[1] == 0, "an unknown code is dropped")
hear("G" .. Link.Code("Guilda B") .. " eco", "Ana-Realm")
check(#replayed[1] == 0, "our own echo is dropped")
hear("G" .. Link.Code("Guilda B") .. " outro canal", "Bob-Realm", "General")
check(#replayed[1] == 0, "another channel is not ours")
hear("oi humano", "Bob-Realm")
check(#replayed[1] == 0, "a raw line is not ours")
hear("G" .. Link.Code("Guilda B") .. " pelo codigo", "Cid-Realm")
check(#replayed[1] == 1 and replayed[1][1].args[1]:find("[Guilda B]", 1, true),
  "the guild comes from the line's code, never from a roster (issue #431)")
reset()
ignored["Bob-Realm"] = true
hear("G" .. Link.Code("Guilda B") .. " ignorado", "Bob-Realm")
check(#replayed[1] == 0, "an ignored speaker is not shown")
ignored["Bob-Realm"] = nil
check(Chat:Prefs().guildBridge == true, "the shared /g is on by default")
printed = {}
A:HandleCommand("gchat off")
check(Chat:Prefs().guildBridge == false and printed[1]:find("Allied /g: hidden", 1, true), "/gos ally gchat off turns it off")
hear("G" .. Link.Code("Guilda B") .. " desligado", "Bob-Realm")
check(#replayed[1] == 0, "the switch off shows nothing")
A:HandleCommand("gchat on")
check(Chat:Prefs().guildBridge == true, "and on again")
local before = #Chat:Log()
hear("A" .. Link.Code("Guilda C") .. " oi sala", "Cy-Realm")
check(#replayed[1] == 0 and #Chat:Log() == before + 1, "a room line goes to the alliance feed, not /g")
check(Chat:Log()[#Chat:Log()].g == "Guilda C" and Chat:Log()[#Chat:Log()].n == "Cy", "with its guild and speaker")
before = #Chat:Log()
hear("A" .. Link.Code("Guilda A") .. " oi do colega", "Gui-Realm")
check(#replayed[1] == 0 and #Chat:Log() == before + 1 and Chat:Log()[#Chat:Log()].g == "Guilda A",
  "a guildmate's room line reaches our feed (issue #431)")

-- A line that does not fit with its frame goes in parts, nothing lost (issue #431).
local long = string.rep("palavra ", 40) .. "fim"
local parts = Link.Split("G", "abc", long)
check(#parts == 2, "a long line goes in two parts")
local joined = {}
for _, p in ipairs(parts) do
  check(#p <= Link.MAX_LINE, "each part fits a line of chat")
  local k, c, t = Link.Decode(p)
  check(k == "G" and c == "abc", "each part is framed")
  joined[#joined + 1] = t
end
check(table.concat(joined, " ") == long, "the parts carry the whole line, cut on a space")
check(#Link.Split("G", "abc", "curta") == 1, "a short line is one part")
check(#Link.Split("G", "abc", "   ") == 0, "a blank line is nothing")

-- A frame without a handler to replay through gets the line as /g reads.
local plain = Link.FormatPlain("Guilda B", "Bob-Realm", "oi")
check(plain:find("|Hchannel:GUILD|h[Guild]|h", 1, true) and plain:find("|Hplayer:Bob-Realm|h", 1, true), "the plain line reads as /g")

-- ── 6. Who is on now, and the site's hooks ─────────────────────────────
local online = A:OnlineNow()
local who = {}
for _, p in ipairs(online) do who[#who + 1] = p.name .. "@" .. p.guild end
check(table.concat(who, ",") == "Bob@Guilda B,Cid@Guilda B,Cy@Guilda C",
  "who is on now: the allied speakers heard on the channel, never ours (" .. table.concat(who, ",") .. ")")
local gl = A:Guilds()
check(gl[1].name == "Guilda A" and gl[1].mine and gl[2].name == "Guilda B" and gl[2].online == 2 and gl[3].online == 1,
  "the guilds, ours first, with how many are seen on")
NOW = NOW + A.ONLINE_FOR + 1
check(#A:OnlineNow() == 0, "a speaker silent for a while is no longer counted")
check(A:GuildOfMember("Bob-Realm") == "Guilda B" and A:GuildOfMember("Gui") == nil, "a speaker heard is known by guild, not ours")
local wf = filters.CHAT_MSG_WHISPER and filters.CHAT_MSG_WHISPER[1]
check(wf == nil, "the room's module is not started here: its whisper filter is tested below")
Chat:Initialize()
wf = filters.CHAT_MSG_WHISPER[1]
local _, tagged = wf(nil, "CHAT_MSG_WHISPER", "oi", "Bob-Realm")
check(tagged and tagged:find("[Guilda B]", 1, true), "an allied speaker's whisper carries their guild")
check(not wf(nil, "CHAT_MSG_WHISPER", "oi", "Estranho-Realm"), "a stranger's is left alone")
-- GOSALLY1 (alianca.md §3.2): empty until the site sends it, and what reads it works once it does.
check(#A:Directory() == 0 and #A:OpenRaids() == 0 and #A:FindCrafters(1234) == 0 and A:MemberInfo("Zeca") == nil,
  "the directory and the open raids answer nothing yet")
local realDir = A.Directory
A.Directory = function() return { { guild = "Guilda C", members = {
  { name = "Zeca", class = "MAGE", level = 70, role = "DPS", recipes = { [1234] = true }, prof = "Tailoring" } } } } end
local info = A:MemberInfo("Zeca-Realm")
check(info and info.guild == "Guilda C" and info.class == "MAGE" and A:GuildOfMember("Zeca") == "Guilda C",
  "a directory row names the guild and the class")
local crafters = A:FindCrafters(1234)
check(#crafters == 1 and crafters[1].name == "Zeca" and crafters[1].guild == "Guilda C" and not crafters[1].online,
  "and who crafts an item")
-- A channel line whose guild the key's list doesn't know is named from the directory, not "Allied guild" (#449).
check(Link:GuildOfLine(Link.Code("Guilda C"), "Zeca-Realm", "G") == "Guilda C",
  "a line from a guild only the site's directory knows carries that guild's name")
A.Directory = realDir

-- ── 7. Officers save the code, the guild hands it on ──────────────────
published = {}
officer = false
check(not Link:SetCode(line), "only an officer saves the code")
officer = true
check(not Link:SetCode("lixo"), "a broken code is refused")
check(not Link:SetCode("GOS=NUCLEO:Kx7Pq2Lm9Z:Guilda B;Guilda C"), "a code without this guild is refused")
local revBefore = GuildOS.db.allianceLink.rev
check(Link:SetCode("  " .. line .. "  "), "an officer saves it")
local held = GuildOS.db.allianceLink
check(held.line == line and held.rev > revBefore and held.by == "Ana-Realm", "kept with a newer revision and its author")
check(#published == 1 and published[1].dom == "allylink" and published[1].act == "set" and published[1].data.line == line,
      "and said to the guild at once")
check(A:Get().source == "link", "and is the alliance at once")

local sync = syncHandlers.allylink
check(type(sync) == "function", "the module listens to the guild's sync")
local function env(act, data) return { act = act, data = data } end
local line2 = Link.Build("NUCLEO", "Kx7Pq2Lm9Z", { "Guilda A", "Guilda B", "Guilda C", "Guilda D" })
sync(env("set", { line = line2, rev = held.rev - 5, by = "Ofi-Realm" }), "Ofi-Realm")
check(GuildOS.db.allianceLink.line == line, "an older revision does not replace the code")
sync(env("set", { line = line2, rev = held.rev + 10, by = "Ofi-Realm" }), "Ofi-Realm")
check(GuildOS.db.allianceLink.line == line2 and A:Get().guilds["Guilda D"], "a newer one from an officer does, and is the alliance")
local r = GuildOS.db.allianceLink.rev
sync(env("have", { line = line, rev = r + 1, by = "Leo-Realm" }), "Leo-Realm")
check(GuildOS.db.allianceLink.line == line2, "a relayed copy naming somebody who is not an officer is refused")
sync(env("have", { line = line, rev = r + 1, by = "Ofi-Realm" }), "Leo-Realm")
check(GuildOS.db.allianceLink.line == line and GuildOS.db.allianceLink.rev == r + 1, "a relayed officer's copy is taken from anybody")
sync(env("have", { line = "GOS=NUCLEO:Kx7Pq2Lm9Z:Guilda B;Guilda C", rev = r + 2, by = "Ofi-Realm" }), "Leo-Realm")
check(GuildOS.db.allianceLink.line == line, "a copy that does not name this guild is refused")

-- Somebody asks: one holder answers after a moment, unless another answered first.
published, defer, deferred = {}, true, {}
sync(env("ask", { rev = 0 }), "Novo-Realm")
check(#published == 0 and #deferred == 1, "the answer waits a moment")
deferred[1]()
check(#published == 1 and published[1].act == "have" and published[1].data.line == line, "then hands over the code")
published, deferred = {}, {}
sync(env("ask", { rev = 0 }), "Novo-Realm")
sync(env("have", { line = line, rev = GuildOS.db.allianceLink.rev, by = "Ofi-Realm" }), "Leo-Realm")
deferred[1]()
check(#published == 0, "and keeps quiet when somebody else answered")
published, deferred = {}, {}
sync(env("ask", { rev = GuildOS.db.allianceLink.rev }), "Leo-Realm")
check(#deferred == 0, "nobody answers who holds nothing newer")
defer = false

-- Turning it off is a revision too: an old copy never brings it back.
check(Link:SetCode(nil), "an officer turns it off")
check(GuildOS.db.allianceLink.line == nil and A:Get() == nil, "the code is gone for the guild")
local off = GuildOS.db.allianceLink.rev
sync(env("have", { line = line, rev = off - 1, by = "Ofi-Realm" }), "Leo-Realm")
check(GuildOS.db.allianceLink.line == nil, "an older copy does not bring it back")

-- At login the client asks the guild for anything newer than it holds.
published = {}
Link._asked = nil
local login
for _, f in ipairs(frames) do if f.events.PLAYER_ENTERING_WORLD and f.events.CHAT_MSG_CHANNEL and f.fn then login = f end end
login.fn(login, "PLAYER_ENTERING_WORLD")
check(#published == 1 and published[1].act == "ask" and published[1].data.rev == off, "at login it asks the guild")

-- ── 8. The guild master's note: nobody has to be online (issue #431) ──
check(Link.NoteLine("GM " .. short) == short, "the code is read out of the note")
check(Link.NoteLine("Main") == nil and Link.NoteLine(line) == nil, "no code, or the listed form, is no note code")
check(Link.WithNoteLine("GM", short) == "GM " .. short, "written after the note's words when they fit")
check(Link.WithNoteLine("Guild Master desde 2019", short) == short, "and alone when they do not")
check(Link.WithNoteLine("GM GOS=VELHA:abcd1234", short) == "GM " .. short, "an old code is replaced")
check(Link.WithNoteLine("GM " .. short, nil) == "GM", "and taken out on removal")

local gmNote, canNote, noteWrites = "GM", true, {}
local rosterRows = 1
GetNumGuildMembers = function() return rosterRows end
function GetGuildRosterInfo(i) if i == 1 then return "Rei-Realm", "Guild Master", 0, 70, "", "", gmNote end end
GuildOS.Compat.CanEditPublicNote = function() return canNote end
GuildOS.Compat.SetGuildPublicNote = function(name, text)
  noteWrites[#noteWrites + 1] = { name = name, text = text }; gmNote = text; return true
end
local roster
for _, f in ipairs(frames) do if f.events.GUILD_ROSTER_UPDATE and f.fn then roster = f end end
check(roster ~= nil, "the module reads the roster when it comes in")

-- Anniversary: the officer's save goes in the guild master's note.
local ok8, inNote = Link:SetCode(short)
check(ok8 and inNote and noteWrites[1].name == "Rei-Realm" and gmNote == "GM " .. short, "the save writes the GM's note")
check(GuildOS.db.allianceLink.note, "and remembers the note holds it")
check(A:Get().open and A:Get().guilds["Guilda A"], "an open code is an alliance with our guild in it")

-- A member with nothing, nobody online: the note alone sets them up.
GuildOS.db.allianceLink = { rev = 0 }
Link._noteSeen = nil
roster.fn(roster, "GUILD_ROSTER_UPDATE")
check(GuildOS.db.allianceLink.line == short and A:Get().source == "link", "a member gets the code from the GM's note at login")
check(not Link:ReadGuildMasterNote(), "the same note read twice changes nothing")
-- The note changes: it wins over ours.
local short2 = Link.Build("NUCLEO", "Zz9Yy8Xx7W")
gmNote = "GM " .. short2
roster.fn(roster, "GUILD_ROSTER_UPDATE")
check(GuildOS.db.allianceLink.line == short2, "a new code in the note replaces ours")
-- Taken out of the same guild master's note: a removal.
gmNote = "GM"
roster.fn(roster, "GUILD_ROSTER_UPDATE")
check(GuildOS.db.allianceLink.line == nil, "a code taken out of the GM's note is a removal")

-- A new guild master with an empty note: not a removal, and an officer's client writes it by itself.
setCode(short, 5)
Link._noteSeen = "Rei-Realm\0GM " .. short
noteWrites = {}
function GetGuildRosterInfo(i) if i == 1 then return "Nova-Realm", "Guild Master", 0, 70, "", "", gmNote end end
gmNote = ""
roster.fn(roster, "GUILD_ROSTER_UPDATE")
check(GuildOS.db.allianceLink.line == short, "a new GM without the code removes nothing")
check(#noteWrites == 1 and noteWrites[1].name == "Nova-Realm" and gmNote == short, "and an officer's client writes it in the new GM's note")
-- A member's client (not an officer) never writes.
officer = false
gmNote, noteWrites, Link._noteSeen = "", {}, nil
roster.fn(roster, "GUILD_ROSTER_UPDATE")
check(#noteWrites == 0, "a member's client never writes a note")
officer = true

-- Where the game forbids writing notes (WoW: Forever, retail): saved, and the guild hands it on by itself.
canNote, gmNote, noteWrites = false, "", {}
published = {}
local ok9, inNote9 = Link:SetCode(short2)
check(ok9 and not inNote9 and #noteWrites == 0 and published[1].act == "set", "no note write: saved, and the sync carries it")
-- Another code in a note this client cannot change: refused with a reason.
gmNote = "GM " .. short
local okNo, why = Link:SetCode(short2)
check(not okNo and type(why) == "string", "another code in a note we cannot change is not overruled")
canNote, gmNote = true, ""

-- A copy from the GM's note relayed by any member: taken when our own copy of the note says the same.
setCode(short, 50)
gmNote = "GM " .. short2
Link._noteSeen = "Nova-Realm\0GM " .. short2   -- as if read already, so only the relay acts
sync(env("have", { line = short2, rev = 60, by = Link.NOTE_BY }), "Membro-Realm")
check(GuildOS.db.allianceLink.line == short2, "a member's relay of the GM's note is taken")
sync(env("have", { line = Link.Build("FAKE", "abcd1234"), rev = 70, by = Link.NOTE_BY }), "Membro-Realm")
check(GuildOS.db.allianceLink.line == short2, "a relay the GM's note does not back is refused")
gmNote = ""

-- ── Guilds are heard on the channel, nobody lists them ─────────────────
setCode(short, GuildOS.db.allianceLink.rev + 1)
Link._noteSeen = "Nova-Realm\0" .. gmNote
check(A:Get().guilds["Guilda B"] == nil, "a guild nobody heard from is not known yet")
-- From the mesh: the speaker's presence names their guild.
local peerGuild = { Bia = "Guilda Bela" }
GuildOS.Mesh = { GetPeerGuild = function(_, n) return peerGuild[n] end }
reset()
hear("G" .. Link.Code("Guilda Bela") .. " cheguei", "Bia-Realm")
check(#replayed[1] == 1 and replayed[1][1].args[1]:find("[Guilda Bela]", 1, true), "a new guild's line is drawn under its name")
check(A:Get().guilds["Guilda Bela"], "and the guild is known from then on")
reset()
hear("G" .. Link.Code("Guilda Bela") .. " de novo", "Outro-Realm")
check(#replayed[1] == 1 and replayed[1][1].args[1]:find("[Guilda Bela]", 1, true), "its code is known from then on")
reset()
hear("Gq9z ninguem sabe", "Xis-Realm")
check(#replayed[1] == 1, "a line of a guild not met yet is shown all the same, never dropped")
-- The mesh's GuildOS clients of a guild of ours count as on now; of another guild, never.
peerGuild.Cid = "Guilda Cid"
_G.ChehulNet = { Peers = function() return { Cid = { ts = 1 }, Bia = { ts = 1 } } end }
local seen = {}
for _, p in ipairs(A:OnlineNow()) do seen[p.name] = p.guild end
check(seen.Bia == "Guilda Bela" and seen.Cid == nil, "the mesh's peers of the alliance's guilds are on now, nobody else's")
check(A:Get().guilds["Guilda Cid"] == nil, "the mesh alone teaches no guild")
-- Forgotten after a month of silence.
check(A:Get().guilds["Guilda Bela"], "a guild heard is kept")
GuildOS.db.allianceLinkLearned.NUCLEO["Guilda Bela"] = NOW - Link.LEARN_TTL - 1
Link._learnRev = (Link._learnRev or 0) + 1
check(A:Get().guilds["Guilda Bela"] == nil, "a guild silent for a month is forgotten")
_G.ChehulNet, GuildOS.Mesh = nil, nil
setCode(line, GuildOS.db.allianceLink.rev + 1)
rosterRows = 0
GetNumGuildMembers = function() return 0 end

-- ── 9. The relay works both ways, and waits for the roster ─────────────
published = {}
GuildOS.db.allianceLink.note = true
published, defer, deferred = {}, true, {}
sync(env("ask", { rev = 0 }), "Novo-Realm")
deferred[1]()
check(#published == 1 and published[1].act == "have", "a holder from the GM's note answers too: everybody hands it on")
GuildOS.db.allianceLink.note = nil
defer, deferred, published = false, {}, {}
-- Somebody holding NEWER asks: we ask back, so they answer.
published = {}
Link._askedAt = nil
sync(env("ask", { rev = GuildOS.db.allianceLink.rev + 100 }), "Veio-Realm")
check(#published == 1 and published[1].act == "ask", "an ask from a newer holder makes us ask back")
sync(env("ask", { rev = GuildOS.db.allianceLink.rev + 100 }), "Outro-Realm")
check(#published == 1, "and not once per asker")

-- A relayed officer's copy before the roster loads is kept, then taken.
local rr = GuildOS.db.allianceLink.rev
officers["Novo-Realm"] = nil
sync(env("have", { line = line2, rev = rr + 1, by = "Novo-Realm" }), "Leo-Realm")
check(GuildOS.db.allianceLink.line == line and Link._pending ~= nil, "with no roster yet the copy waits")
officers["Novo-Realm"] = true
GetNumGuildMembers = function() return 5 end
roster.fn(roster, "GUILD_ROSTER_UPDATE")
check(GuildOS.db.allianceLink.line == line2 and Link._pending == nil, "and is taken when the roster comes in")

-- ── 10. Blocking an allied guild (review A) ────────────────────────────
reset()
hear("G" .. Link.Code("Guilda B") .. " antes", "Bob-Realm")
check(#replayed[1] == 1, "a line of Guilda B is drawn before any block")
officer = false
local okB, whyB = A:Block("Guilda B")
check(not okB and whyB == "Only officers can do that.", "only an officer blocks a guild")
officer = true
printed = {}
A:HandleCommand("block Guilda B")
check(A:IsBlocked("Guilda B") and GuildOS.db.allianceLinkBlocked["Guilda B"] == true and printed[1] == "Blocked: Guilda B",
  "/gos ally block: kept in the guild's db, and said")
reset()
hear("G" .. Link.Code("Guilda B") .. " bloqueado", "Bob-Realm")
check(#replayed[1] == 0, "a blocked guild's /g is not drawn")
local logN = #Chat:Log()
hear("A" .. Link.Code("Guilda B") .. " sala bloqueada", "Bob-Realm")
check(#Chat:Log() == logN, "nor its lines in the room")
local onB = false
for _, p in ipairs(A:OnlineNow()) do onB = onB or p.guild == "Guilda B" end
check(not onB, "nor counted as on now")
check(not A:Block(""), "a block names a guild")
A:HandleCommand("unblock Guilda B")
check(not A:IsBlocked("Guilda B"), "/gos ally unblock lifts it")
reset()
hear("G" .. Link.Code("Guilda B") .. " voltei", "Bob-Realm")
check(#replayed[1] == 1, "and its lines are drawn again")
A:HandleCommand("block Guilda C")
check(A:Blocked()[1] == "Guilda C", "the blocked list, for the Officers' Room")

-- ── 11. guildos.me's code (GOSGILD1 `alliance`) wins, and its end is an end ──
local SITE, SITE2 = "GOS=PACTO:AbCdE12345", "GOS=PACTO:ZzYyXx9876"
local P1, P2 = Link.ChannelNameFor("PACTO", "AbCdE12345"), Link.ChannelNameFor("PACTO", "ZzYyXx9876")
local good = Link.ReadSiteCode({ code = SITE, name = "Pacto do Sul", version = 3 })
check(good and good.line == SITE and good.name == "Pacto do Sul" and good.version == 3, "the site's code reads")
local hostile = {
  "GOS=PACTO:AbCdE12345", 42, {},
  { code = SITE .. ":Guilda A;Guilda B", name = "Pacto", version = 1 },   -- the listed form is not the site's
  { code = "GOS=pacto:AbCdE12345", name = "Pacto", version = 1 },          -- lower-case tag
  { code = "GOS=PACTO:AbCdE1234", name = "Pacto", version = 1 },           -- a key of nine
  { code = "GOS=PACTO:AbCdE12345X", name = "Pacto", version = 1 },         -- a key of eleven
  { code = "GOS=ABCDEFGHIJKLM:AbCdE12345", name = "Pacto", version = 1 },  -- a tag of thirteen
  { code = "GOS=PA-CTO:AbCdE12345", name = "Pacto", version = 1 },
  { code = " " .. SITE, name = "Pacto", version = 1 },
  { code = SITE .. "\n", name = "Pacto", version = 1 },
  { code = SITE, name = "P", version = 1 },
  { code = SITE, name = string.rep("x", 49), version = 1 },
  { code = SITE, name = "Pa|cffff0000cto", version = 1 },
  { code = SITE, name = "Pacto\nNovo", version = 1 },
  { code = SITE, name = 7, version = 1 },
  { code = SITE, name = "Pacto", version = 0 },
  { code = SITE, name = "Pacto", version = 1.5 },
  { code = SITE, name = "Pacto", version = "3" },
  { code = SITE, name = "Pacto", version = 0 / 0 },
  { code = string.rep("G", 100000), name = "Pacto", version = 1 },
}
for i, bad in ipairs(hostile) do check(Link.ReadSiteCode(bad) == nil, "a hostile site code is refused (" .. i .. ")") end

local siteBlock
GuildOS.CompanionImport = { GuildBlock = function() return siteBlock end }
local heldBefore = GuildOS.db.allianceLink.line
published, left = {}, {}
-- (`joined` is the split test's above: the channels are read through the client's own GetChannelName.)
local function inChan(name) return GetChannelName(name) > 0 end
local function keyOf(name)
  for i = #channelArgs, 1, -1 do if channelArgs[i][1] == name then return channelArgs[i][2] end end
end
check(Chat:EnsureJoined() and inChan(CH), "the pasted code's channel is the one joined")
siteBlock = { alliance = { code = SITE, name = "Pacto do Sul", version = 3 } }
Chat:EnsureJoined()
local sp = A:Get()
check(sp and sp.site and sp.tag == "PACTO" and A:Name() == "Pacto do Sul" and A:FromSite() and Link:FromSite(),
  "the site's code is the alliance, with the site's name")
check(inChan(P1) and keyOf(P1) == "AbCdE12345" and not inChan(CH) and left[1] == CH,
  "its channel is joined with the site's key, and the pasted code's is left")
check(GuildOS.db.allianceLink.line == heldBefore and Link:Suggest() == heldBefore,
  "the site's code is never written into the guild's copy or offered to copy")
check(#published == 1 and published[1].act == "site" and published[1].data.line == SITE and published[1].data.version == 3
  and published[1].data.name == "Pacto do Sul", "an officer reading it in the block tells the guild, as the site's (follow-up 2)")
check(Link:SetCode(short) and A:Get().tag == "PACTO", "a code pasted while the site's is in force does not replace it")
siteBlock = nil
Chat:EnsureJoined()
check(A:FromSite(), "no block to read (a login, the companion off): the site's last code stands")
siteBlock = { alliance = { code = "GOS=x" } }
Chat:EnsureJoined()
check(A:FromSite() and A:Get().tag == "PACTO", "a damaged `alliance` is read as saying nothing, never as an end")

-- A new key (a guild left, or a reset): the channel keyed with the old one is left, then joined with the new.
left = {}
siteBlock = { alliance = { code = SITE2, name = "Pacto do Sul", version = 4 } }
Chat:EnsureJoined()
check(left[1] == P1 and P1 ~= P2, "a new key is a new channel, and the old one is left")
Chat:EnsureJoined()
check(inChan(P2) and keyOf(P2) == "ZzYyXx9876" and A:Get().version == 4, "and joins it again with the new key")
check(GuildOS.db.allianceLinkJoined["Ana-Realm"].key == "ZzYyXx9876", "remembered per character, with its key")
check(A:IsBlocked("Guilda C"), "a block outlives a key change")

-- The guild left the alliance: the block names none. The site's code ends, the channel is left, and the code
-- it left in the guild master's note (the same dead code) does not come back.
setCode(SITE2, GuildOS.db.allianceLink.rev + 1)
left = {}
siteBlock = { guild = "Guilda A" }
Chat:EnsureJoined()
check(A:Get() == nil and not Link:FromSite(), "a site code that disappears ends the alliance")
check(left[1] == P2 and not inChan(P2), "and leaves its channel")
check(GuildOS.db.allianceLinkSite == nil and GuildOS.db.allianceLinkSiteGone == SITE2, "the end is remembered")
Chat:EnsureJoined()
check(A:Get() == nil, "and stays an end")
-- A code an officer pasted by hand that is another one comes back into force: the chat only.
setCode(short, GuildOS.db.allianceLink.rev + 1)
check(A:Get() and A:Get().tag == "NUCLEO" and not A:FromSite(), "another code an officer pasted is the guild's again")
-- The dead code pasted again by an officer, on purpose, is theirs.
check(Link:SetCode(SITE2) and A:Get() and A:Get().tag == "PACTO" and GuildOS.db.allianceLinkSiteGone == nil,
  "an officer pasting that code again brings it back")
GuildOS.CompanionImport = nil

-- ── 12. The site's code reaches members without the companion, through the guild (follow-up 2) ──
local SITE3, SITE4 = "GOS=PACTO:Mm3Nn4Oo5P", "GOS=PACTO:Qq6Rr7Ss8T"
local P3 = Link.ChannelNameFor("PACTO", "Mm3Nn4Oo5P")
officer = false
GuildOS.db.allianceLinkSite, GuildOS.db.allianceLinkSiteGone = nil, nil
setCode(short, GuildOS.db.allianceLink.rev + 1)
Chat:EnsureJoined()
check(A:Get().tag == "NUCLEO" and not A:FromSite(), "a member with no companion: the pasted code")
local writesBefore = #noteWrites
sync(env("site", { line = SITE3, name = "Pacto do Sul", version = 5 }), "Leo-Realm")
check(not A:FromSite(), "a relay from somebody who is not an officer is refused on receipt too")
sync(env("site", { line = SITE3, name = "Pacto do Sul", version = 5 }), "Ofi-Realm")
check(A:FromSite() and A:Get().version == 5 and A:Name() == "Pacto do Sul", "an officer's relay is the site's code here")
Chat:EnsureJoined()
check(inChan(P3) and keyOf(P3) == "Mm3Nn4Oo5P" and not inChan(CH), "its channel joined, the pasted code's left")
check(#noteWrites == writesBefore and GuildOS.db.allianceLink.line == short, "never into the GM's note nor the guild's copy")
sync(env("site", { line = SITE2, name = "Pacto do Sul", version = 4 }), "Ofi-Realm")
check(A:Get().version == 5, "an older key version never replaces a newer one")
sync(env("site", { line = "GOS=PACTO:bad", name = "Pacto do Sul", version = 9 }), "Ofi-Realm")
sync(env("site", { line = SITE4 .. ":Guilda A;Guilda B", name = "Pacto do Sul", version = 9 }), "Ofi-Realm")
sync(env("site", { line = SITE4, name = "P|r", version = 9 }), "Ofi-Realm")
check(A:Get().version == 5, "a hostile relay is refused as the block's would be")
published = {}
Link._askedAt = nil
Link:Ask()
check(published[1].act == "ask" and published[1].data.site == SITE3, "at login a member asks with the site code it holds")
-- The end travels the same way.
sync(env("site", { gone = SITE3 }), "Leo-Realm")
check(A:FromSite(), "an end from a member is refused")
sync(env("site", { gone = SITE4 }), "Ofi-Realm")
check(A:FromSite(), "an end naming another code ends nothing")
left = {}
sync(env("site", { gone = SITE3 }), "Ofi-Realm")
check(A:FromSite(), "an end that does not say which key version it ended ends nothing")
sync(env("site", { gone = SITE3, version = 5 }), "Ofi-Realm")
Chat:EnsureJoined()
check(not A:FromSite() and A:Get().tag == "NUCLEO" and left[1] == P3 and not inChan(P3),
  "an officer's end: the member leaves the site's alliance and its channel; their own pasted code stands")
sync(env("site", { line = SITE3, name = "Pacto do Sul", version = 5 }), "Ofi-Realm")
check(not A:FromSite(), "the code the site ended is not brought back by a relay of that version")
check(GuildOS.db.allianceLinkSiteGoneOwn == nil, "an end heard from the guild is never this client's to tell")
-- Review 1: an end never touches a pasted code or the GM note's, only a site code held here.
setCode(SITE3, GuildOS.db.allianceLink.rev + 1)
check(A:Get() and A:Get().key == "Mm3Nn4Oo5P" and not A:FromSite(),
  "the same code pasted by hand stands, though a relayed end named it")
GuildOS.db.allianceLinkSiteGone, GuildOS.db.allianceLinkSiteGoneV = nil, nil
sync(env("site", { gone = SITE3, version = 5 }), "Ofi-Realm")
check(A:Get() and A:Get().key == "Mm3Nn4Oo5P" and GuildOS.db.allianceLinkSiteGone == nil,
  "an end for a code held only as a paste ends nothing and records nothing")
setCode(short, GuildOS.db.allianceLink.rev + 1)
GuildOS.db.allianceLinkSiteGone, GuildOS.db.allianceLinkSiteGoneV = SITE3, 5
sync(env("site", { line = SITE3, name = "Pacto do Sul", version = 6 }), "Ofi-Realm")
check(A:FromSite() and A:Get().version == 6, "a relay of a higher key version passes the end")
sync(env("site", { gone = SITE3, version = 5 }), "Ofi-Realm")
check(A:FromSite(), "an end of an older version does not end a newer one")
sync(env("site", { gone = SITE3, version = 6 }), "Ofi-Realm")
check(not A:FromSite() and A:Get().tag == "NUCLEO", "the end of the version held does")
-- A member's own block wins over any relay.
local mine
GuildOS.CompanionImport = { GuildBlock = function() return mine end }
mine = { alliance = { code = SITE4, name = "Pacto do Sul", version = 7 } }
Link:SyncSite()
sync(env("site", { line = "GOS=PACTO:Zz1Zz2Zz3Z", name = "Pacto do Sul", version = 9 }), "Ofi-Realm")
check(A:Get().version == 7 and A:Get().key == "Qq6Rr7Ss8T", "a client that reads the site itself ignores relays")
-- An officer answers a member's ask with what its own block says, once.
officer = true
local function answers(fromSite)
  published, deferred, defer = {}, {}, true
  Link._askedAt = nil
  sync(env("ask", { rev = GuildOS.db.allianceLink.rev, site = fromSite }), "Novo-Realm")
  for _, fn in ipairs(deferred) do fn() end
  defer = false
  local out = {}
  for _, m in ipairs(published) do if m.act == "site" then out[#out + 1] = m.data end end
  return out
end
local ans = answers("")
check(#ans == 1 and ans[1].line == SITE4 and ans[1].version == 7, "an officer answers a member who holds none")
check(#answers(SITE4) == 0, "and not one who holds the same")
mine = { guild = "Guilda A" }
Link:SyncSite()
check(#answers(SITE3) == 0 and #answers(short) == 0,
  "review 1: an officer never ends a code it did not see end itself, whatever the asker names (a pasted one too)")
ans = answers(SITE4)
check(#ans == 1 and ans[1].gone == SITE4 and ans[1].version == 7, "only the code its own block saw end, with its version")
-- A stale officer (a block saying nothing of an alliance it never held) answers nobody.
local keepGone = { GuildOS.db.allianceLinkSiteGone, GuildOS.db.allianceLinkSiteGoneV, GuildOS.db.allianceLinkSiteGoneOwn }
Link.ForgetGone()
check(#answers(SITE4) == 0, "a stale officer whose block names no alliance cannot end a live site code")
GuildOS.db.allianceLinkSiteGone, GuildOS.db.allianceLinkSiteGoneV, GuildOS.db.allianceLinkSiteGoneOwn = keepGone[1], keepGone[2], keepGone[3]
mine = { alliance = { code = SITE4, name = "Pacto do Sul", version = 7 } }
Link:SyncSite()
check(#answers("") == 1, "with the code back in the block, the officer answers again")
published, deferred, defer = {}, {}, true
sync(env("ask", { rev = 0, site = "" }), "Novo-Realm")
sync(env("site", { line = SITE4, name = "Pacto do Sul", version = 7 }), "Ofi-Realm")
for _, fn in ipairs(deferred) do fn() end
defer = false
local siteSent = 0
for _, m in ipairs(published) do if m.act == "site" then siteSent = siteSent + 1 end end
check(siteSent == 0, "nobody answers twice: another officer's relay first silences ours")
GuildOS.CompanionImport = nil

-- A code this client only had from a relay: a block that names no alliance (older than it) drops it here and tells
-- the guild nothing (audit #448 review).
do
  officer = true
  GuildOS.db.allianceLinkSite = nil; Link.ForgetGone()
  local blk = nil
  local realCI = GuildOS.CompanionImport
  GuildOS.CompanionImport = { GuildBlock = function() return blk end }
  sync(env("site", { line = SITE4, name = "Pacto do Sul", version = 7 }), "Ofi-Realm")
  check(GuildOS.db.allianceLinkSite and GuildOS.db.allianceLinkSite.relayed, "a relayed code is marked as relayed")
  published = {}
  blk = { guild = "Guilda A" }
  Link:SyncSite()
  local ended = false
  for _, m in ipairs(published) do if m.data and m.data.gone then ended = true end end
  check(not ended and not GuildOS.db.allianceLinkSiteGoneOwn and GuildOS.db.allianceLinkSite == nil,
    "an officer's block that never named a relayed code drops it, and never tells the guild it ended")
  -- The same code later named by this client's own block is its own: its end is told.
  sync(env("site", { line = SITE4, name = "Pacto do Sul", version = 7 }), "Ofi-Realm")
  blk = { guild = "Guilda A", alliance = { code = SITE4, name = "Pacto do Sul", version = 7 } }
  Link:SyncSite()
  check(GuildOS.db.allianceLinkSite and not GuildOS.db.allianceLinkSite.relayed, "an own block naming a relayed code makes it this client's own")
  published = {}
  blk = { guild = "Guilda A" }
  Link:SyncSite()
  local told = false
  for _, m in ipairs(published) do if m.data and m.data.gone == SITE4 then told = true end end
  check(told and GuildOS.db.allianceLinkSiteGoneOwn, "and when it ends, the guild is told")
  GuildOS.CompanionImport = realCI
end
print(("alliance-link: %d checks passed"):format(checks))
