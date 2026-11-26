-- The alliance the GreenWall way (issue #348), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Libs (LibDeflate, LibSerialize), Modules/AllianceSync.lua, Modules/Alliance.lua,
-- Modules/AllianceChat.lua, Modules/GuildChat.lua and Modules/AllianceLink.lua under a stubbed client.
--
-- One client of "Guilda A". Proves:
--   * the alliance code is read and refused when it is broken; an officer saves it, the guild hands it
--     on (set / ask / have), the newest wins, a removal sticks, and only an officer's copy counts;
--   * it is the pact every module reads, it names no ambassadors, and the whisper ops that built the
--     old pact do nothing under it;
--   * the hidden channel is joined with the key and taken out of the chat frames, and its lines never
--     print raw;
--   * a line of /g the player sends from a chat box or the Guild tab goes on the channel, inside the
--     key press; officer chat never does;
--   * a channel line from an allied guild is drawn as /g by the frame's own handler, tagged, in the
--     frames that show /g only; ours, our own guild's /g, an unknown or blocked guild's are not; a
--     stale roster never drops a line; the room's lines go to the alliance feed, our guild's too;
--     a line too long for its frame goes in parts;
--   * a data op is believed for the guild it names only with the key's proof for its sender;
--   * the short code goes in the guild master's public note and every member reads it from there,
--     nobody online; the guilds are learned from the channel, the mesh and the proofs; the relay
--     asks back a newer holder and keeps a copy that came before the roster (issue #431).
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
dofile(ADDON .. "/Modules/AllianceSync.lua")
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

local A, Link, Chat, GC = GuildOS.Alliance, GuildOS.AllianceLink, GuildOS.AllianceChat, GuildOS.GuildChat
local index = {}
GuildOS.AllianceSync.MemberIndex = function() return index end
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
local key = Link.NewKey()
check(#key == Link.KEY_LEN and key:match("^%w+$"), "a new key is alphanumeric")
check(Link.Decode(Link.Encode("G", "abc", "oi gente")) == "G", "a channel line round-trips")
local k2, c2, t2 = Link.Decode("Gabc oi gente")
check(k2 == "G" and c2 == "abc" and t2 == "oi gente", "decoded into kind, code and text")
check(Link.Decode("oi gente") == nil, "a human line is not ours")
check(#Link.Encode("G", "abc", string.rep("é", 200)) <= 255, "a long line fits the chat line")

-- ── 2. The pact comes from the alliance code ───────────────────────────
check(A:Get() == nil, "no code, no pact")
GuildOS.db.alliance = { tag = "OLD", guilds = { ["Guilda A"] = { ambassadors = { "Ana" } }, ["Guilda Z"] = { ambassadors = { "Zed" } } } }
check(A:Get().tag == "OLD" and not A.InLink(), "without the line, the old pact")
local suggest = Link.Parse(Link:Suggest())
check(suggest and suggest.tag == "OLD" and suggest.open, "the panel offers a short code made from the old pact's tag")
setCode(line)
local pact = A:Get()
check(pact and pact.source == "link" and pact.tag == "NUCLEO", "the code wins over the old pact")
check(pact.guilds["Guilda C"] and #pact.guilds["Guilda C"].ambassadors == 0, "and names no ambassadors")
check(A.InLink(), "the pact is the code's")
check(A:CanAdminister(), "an officer administers it")
local ok, err = A:Invite("Zed")
check(not ok and err == "This alliance is set in Alliance > Setup. Change it there.", "the whisper ops that build a pact do nothing")
check(not A:Leave() and not A:Create("X", "Y"), "leave and create too")
setCode("GOS=NUCLEO:Kx7Pq2Lm9Z:Guilda B;Guilda C")
check(A:Get().tag == "OLD", "a code that does not name this guild is not this guild's pact")
setCode(line)

-- ── 3. The hidden channel ──────────────────────────────────────────────
joined["GOSOLD"] = ""
local left = {}
function LeaveChannelByName(name) left[#left + 1] = name; joined[name] = nil end
check(Chat:EnsureJoined(), "the watchdog joins it")
check(left[1] == "GOSOLD" and #left == 1, "and leaves the old pact's public channel")
check(joined["GOSANUCLEO"] == "Kx7Pq2Lm9Z", "with the key as the password")
check(#removed == 1 and removed[1].frame == ChatFrame1 and removed[1].name == "GOSANUCLEO", "and takes it out of the frame that listed it")
local hidden = filters.CHAT_MSG_CHANNEL[1](nil, "CHAT_MSG_CHANNEL", "Gabc x", "Bob", "", "", "", "", 0, 5, "GOSANUCLEO")
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
  recv.fn(recv, "CHAT_MSG_CHANNEL", msg, author, "Common", "5. GOSANUCLEO", "", "", 0, 5, chan or "GOSANUCLEO", 0, 77, guid)
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
index.cid = { guild = "Guilda C" }
hear("G" .. Link.Code("Guilda B") .. " mudou de guilda", "Cid-Realm")
check(#replayed[1] == 1 and replayed[1][1].args[1]:find("[Guilda B]", 1, true),
  "a stale roster does not drop the line: the guild comes from the code (issue #431)")
reset()
ignored["Bob-Realm"] = true
hear("G" .. Link.Code("Guilda B") .. " ignorado", "Bob-Realm")
check(#replayed[1] == 0, "an ignored speaker is not shown")
ignored["Bob-Realm"] = nil
GuildOS.db.allianceLinkBlocked["Guilda B"] = true
hear("G" .. Link.Code("Guilda B") .. " bloqueado", "Bob-Realm")
check(#replayed[1] == 0, "a blocked guild is not shown")
GuildOS.db.allianceLinkBlocked["Guilda B"] = nil
Chat:Prefs().guildBridge = false
hear("G" .. Link.Code("Guilda B") .. " desligado", "Bob-Realm")
check(#replayed[1] == 0, "the preference off shows nothing")
Chat:Prefs().guildBridge = true
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

-- ── 6. Data ops: the key's proof, not a list of names ──────────────────
whispers = {}
A:Send("HEAD", { revs = {} }, "Bob-Realm")
local _, _, blob = strsplit("|", whispers[1].payload, 3)
local data = A.Decode(blob)
check(data._g == "Guilda A" and data._k == Link.Proof("Kx7Pq2Lm9Z", "Ana"), "every op names our guild and carries the proof")
local got
A.ops.HEAD = function(_, _, guild) got = guild end
local function op(name, tbl, sender)
  A:OnMessage(A.PROTO .. "|" .. name .. "|" .. A.Encode(tbl), sender, "WHISPER")
end
op("HEAD", { revs = {}, _g = "Guilda B", _k = Link.Proof("Kx7Pq2Lm9Z", "Bob") }, "Bob-Realm")
check(got == "Guilda B", "the right proof speaks for the guild it names")
got = nil
op("HEAD", { revs = {}, _g = "Guilda B", _k = Link.Proof("Kx7Pq2Lm9Z", "Bob") }, "Eve-Realm")
check(got == nil, "somebody else's proof does not")
op("HEAD", { revs = {}, _g = "Guilda B", _k = Link.Proof("outra", "Bob") }, "Bob-Realm")
check(got == nil, "nor a proof from another key")
op("HEAD", { revs = {}, _g = "Guilda A", _k = Link.Proof("Kx7Pq2Lm9Z", "Bob") }, "Bob-Realm")
check(got == nil, "nobody speaks for our own guild")
op("HEAD", { revs = {}, _g = "Guilda Z", _k = Link.Proof("Kx7Pq2Lm9Z", "Zed") }, "Zed-Realm")
check(got == nil, "nor for a guild outside the line")
-- Audit B21: an alliance invite or join request, from the network, waits its turn in the popup queue.
do
  local realQueue, realDialog = GuildOS.ShowWhenClear, GuildOS.ShowDialog
  local queued, opened = {}, {}
  GuildOS.ShowWhenClear = function(_, key, fn) queued[#queued + 1] = { key = key, fn = fn } end
  GuildOS.ShowDialog = function(_, which) opened[#opened + 1] = which; return { which = which } end
  local fake = setmetatable({
    Get = function() return nil end,
    GuildOfSender = function() return "Guilda B" end,
  }, { __index = A })
  local realSan = A.SanitizePact
  A.SanitizePact = function() return { tag = "ALI", name = "Alianca" } end
  fake:_OnInvite({}, "Bob-Realm")
  A.SanitizePact = realSan
  check(#queued == 1 and queued[1].key:find("^allyinvite:") and #opened == 0, "B21: an alliance invite queues, not straight on screen")
  local dlg = queued[1].fn()
  check(opened[1] == "GUILDOS_ALLY_INVITE" and dlg and dlg.which == "GUILDOS_ALLY_INVITE", "B21: and opens its dialog, returned to the queue")
  queued, opened = {}, {}
  fake.Get = function() return { tag = "ALI" } end
  fake.CanAdminister = function() return true end
  fake.IsMemberGuild = function() return false end
  fake.IsBlocked = function() return false end
  local realNorm = A.NormalizeTag
  A.NormalizeTag = function(t) return t end
  fake:_OnJoinRequest({ tag = "ALI", guild = "Guilda C" }, "Cid-Realm")
  A.NormalizeTag = realNorm
  check(#queued == 1 and queued[1].key:find("^allyrequest:") and #opened == 0, "B21: a join request queues too")
  dlg = queued[1].fn()
  check(opened[1] == "GUILDOS_ALLY_REQUEST" and dlg, "B21: and opens when its turn comes")
  GuildOS.ShowWhenClear, GuildOS.ShowDialog = realQueue, realDialog
end

local pacts = 0
A._OnPact = function() pacts = pacts + 1 end
A._OnInvite = function() pacts = pacts + 1 end
op("PACT", { _g = "Guilda B", _k = Link.Proof("Kx7Pq2Lm9Z", "Bob") }, "Bob-Realm")
op("INV", {}, "Bob-Realm")
check(pacts == 0, "the old pact's ops do nothing under the line")

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
check(A:Get().source == "link", "and is the pact at once")

local sync = syncHandlers.allylink
check(type(sync) == "function", "the module listens to the guild's sync")
local function env(act, data) return { act = act, data = data } end
local line2 = Link.Build("NUCLEO", "Kx7Pq2Lm9Z", { "Guilda A", "Guilda B", "Guilda C", "Guilda D" })
sync(env("set", { line = line2, rev = held.rev - 5, by = "Ofi-Realm" }), "Ofi-Realm")
check(GuildOS.db.allianceLink.line == line, "an older revision does not replace the code")
sync(env("set", { line = line2, rev = held.rev + 10, by = "Ofi-Realm" }), "Ofi-Realm")
check(GuildOS.db.allianceLink.line == line2 and A:Get().guilds["Guilda D"], "a newer one from an officer does, and is the pact")
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
check(GuildOS.db.allianceLink.line == nil and A:Get().tag == "OLD", "the code is gone for the guild")
local off = GuildOS.db.allianceLink.rev
sync(env("have", { line = line, rev = off - 1, by = "Ofi-Realm" }), "Leo-Realm")
check(GuildOS.db.allianceLink.line == nil, "an older copy does not bring it back")

-- At login the client asks the guild for anything newer than it holds.
published = {}
Link._asked = nil
local login
for _, f in ipairs(frames) do if f.events.PLAYER_ENTERING_WORLD and f.fn then login = f end end
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
check(A:Get().open and A:Get().guilds["Guilda A"], "an open code is a pact with our guild in it")

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

-- ── Guilds are learned, nobody lists them ──────────────────────────────
setCode(short, GuildOS.db.allianceLink.rev + 1)
Link._noteSeen = "Nova-Realm\0" .. gmNote
check(A:Get().guilds["Guilda B"] == nil, "a guild nobody heard from is not known yet")
-- From the mesh: the speaker's presence names their guild.
local peerGuild = { Bia = "Guilda Bela" }
GuildOS.Mesh = { GetPeerGuild = function(_, n) return peerGuild[n] end, GetPeerAlliance = function(_, n) return peerGuild[n] and "NUCLEO" end }
reset()
hear("G" .. Link.Code("Guilda Bela") .. " cheguei", "Bia-Realm")
check(#replayed[1] == 1 and replayed[1][1].args[1]:find("[Guilda Bela]", 1, true), "a new guild's line is drawn under its name")
check(A:Get().guilds["Guilda Bela"], "and the guild is learned")
reset()
hear("G" .. Link.Code("Guilda Bela") .. " de novo", "Outro-Realm")
check(#replayed[1] == 1 and replayed[1][1].args[1]:find("[Guilda Bela]", 1, true), "its code is known from then on")
reset()
hear("Gq9z ninguem sabe", "Xis-Realm")
check(#replayed[1] == 1, "a line of a guild not met yet is shown all the same, never dropped")
-- From a data op with the key's proof.
op("HEAD", { revs = {}, _g = "Guilda Nova", _k = Link.Proof("Kx7Pq2Lm9Z", "Nil") }, "Nil-Realm")
check(A:Get().guilds["Guilda Nova"], "a guild proving the key in a data op is learned")
op("HEAD", { revs = {}, _g = "Guilda Falsa", _k = Link.Proof("errada", "Fal") }, "Fal-Realm")
check(A:Get().guilds["Guilda Falsa"] == nil, "a wrong proof teaches nothing")
-- From the mesh alone: only a candidate.
peerGuild.Cid = "Guilda Cid"
_G.ChehulNet = { Peers = function() return { Cid = { ts = 1 }, Bia = { ts = 1 } } end }
local cands = Link:Candidates()
check(cands["Guilda Cid"] == "Cid" and cands["Guilda Bela"] == nil, "the mesh's guilds of our tag are candidates, the known ones are not")
check(A:Get().guilds["Guilda Cid"] == nil, "a candidate is not a guild of ours until it proves the key")
-- Forgotten after a month of silence.
GuildOS.db.allianceLinkLearned.NUCLEO["Guilda Nova"] = NOW - Link.LEARN_TTL - 1
Link._learnRev = (Link._learnRev or 0) + 1
check(A:Get().guilds["Guilda Nova"] == nil, "a guild silent for a month is forgotten")
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

print(("alliance-link: %d checks passed"):format(checks))
