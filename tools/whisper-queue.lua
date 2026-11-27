-- The WhisperQueue (issue #393), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua and
-- Core/WhisperQueue.lua under a stubbed WoW: Forever client, on a fake clock and a fake server that answers a
-- client whispering past its limit with ERR_GENERIC_THROTTLE, as WoW: Forever does.
--
-- The rules: off WoW: Forever nothing waits; on it a burst of BURST parts goes, then one part every INTERVAL;
-- a payload pays its AceComm parts; "high" goes first and is never dropped, "low" makes room and goes stale;
-- the error doubles the interval and empties the bucket, and each quiet RECOVER_SECONDS halves it back; a chat
-- line waits for a click where the game wants one, and a click's own whisper goes at once and is paid for;
-- the realm bus takes an item only when every whisper the mesh will send for it is paid; and an hour of the
-- load the issue measured (the realm relay, the gossip, sync answers) never draws the error from the server.
--
--   luajit -e 'ADDON="."' tools/whisper-queue.lua
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

-- ── The clock ───────────────────────────────────────────────────────────
local clock, timers = 0, {}

local function at(when, fn)
  local i = #timers
  while i > 0 and timers[i].when > when do i = i - 1 end
  table.insert(timers, i + 1, { when = when, fn = fn })
end

local function run(seconds)
  local stop = clock + seconds
  while timers[1] and timers[1].when <= stop do
    local item = table.remove(timers, 1)
    clock = item.when
    item.fn()
  end
  clock = stop
end

-- ── The server: every whisper that reaches it, and its limit ────────────
local THROTTLE = "You are doing that too fast."
local server = { limit = nil, log = {}, errors = 0 }
local onError   -- the queue's UI_ERROR_MESSAGE handler

local function inLast(seconds)
  local n = 0
  for _, t in ipairs(server.log) do if t > clock - seconds then n = n + 1 end end
  return n
end

-- One message on the wire. Past the limit in the last minute the server refuses it and says so.
local function wire(n)
  for _ = 1, n or 1 do
    if server.limit and inLast(60) >= server.limit then
      server.errors = server.errors + 1
      if onError then onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE) end
    else
      server.log[#server.log + 1] = clock
    end
  end
end

local function parts(text) return #text <= 255 and 1 or math.ceil(#text / 254) end

-- The worst minute of the log: the most whispers in any 60 seconds.
local function worstMinute()
  local worst, from = 0, 1
  for i, t in ipairs(server.log) do
    while server.log[from] <= t - 60 do from = from + 1 end
    worst = math.max(worst, i - from + 1)
  end
  return worst
end

-- ── The client: WoW: Forever ────────────────────────────────────────────
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent, RAID_CLASS_COLORS = {}, {}
ERR_GENERIC_THROTTLE = THROTTLE
function CreateFrame()
  local f = {}
  f.RegisterEvent = function() end
  f.SetScript = function(_, script, fn) if script == "OnEvent" then onError = fn end end
  return setmetatable(f, { __index = function() return function() end end })
end
function GetTime() return clock end
time = function() return 1790000000 + math.floor(clock) end
GetServerTime = time
function hooksecurefunc() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function UnitName() return "Chehul" end
function UnitFullName() return "Chehul", "Costa" end
function GetRealmName() return "Classic Beta PvE" end
function IsInGuild() return true end
function IsInInstance() return false, "none" end
C_Timer = {
  After = function(delay, fn) at(clock + delay, fn) end,
  NewTicker = function() return { Cancel = function() end } end,
}
local chatSent = {}
C_ChatInfo = {
  InChatMessagingLockdown = function() return false end,
  SendChatMessage = function(text, chatType, _, target)
    if chatType == "WHISPER" then chatSent[#chatSent + 1] = { target = target, text = text }; wire(1) end
  end,
}

GuildOSDB = {}
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }),
            SelfTest = { Register = function() end } }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/WhisperQueue.lua")
local Q = GuildOS.WhisperQueue
check(GuildOS.Client.game == "FOREVER", "the stub is WoW: Forever")
check(onError ~= nil, "the queue listens for the game's error")

-- A fresh queue, at its defaults, with nothing sent yet.
local function reset()
  local S = Q._state
  S.items, S.tokens, S.realm, S.at, S.interval, S.stepAt, S.armed = {}, Q.BURST, Q.REALM_BURST, nil, Q.INTERVAL, 0, false
  for k in pairs(S.stats) do S.stats[k] = 0 end
  timers, server.log, server.errors, server.limit, chatSent = {}, {}, 0, nil, {}
  Q.enabled = nil
  ChehulMesh = nil
end

-- An addon whisper that reaches the fake server, part by part, and remembers what it was.
local sent = {}
local function addon(text, prio, target)
  return Q:PushAddon("GUILDOS", text, target or "Bruno Melo", prio, function()
    sent[#sent + 1] = text
    wire(parts(text))
  end)
end

-- ── 1. Off WoW: Forever nothing waits ───────────────────────────────────
reset()
Q.enabled = false
for i = 1, 30 do check(addon("off" .. i) == "sent", "off Forever a whisper goes at once") end
check(#server.log == 30 and Q:Pending() == 0, "all thirty, and nothing waits")
check(Q:Push("Bruno Melo", "oi") == "sent" and #chatSent == 1, "a chat line too")

-- ── 2. The pace: a burst, then one part every INTERVAL ──────────────────
reset()
sent = {}
for i = 1, 40 do addon("pace" .. i, "normal") end
check(#server.log == Q.BURST, "a burst of BURST goes at once, saw " .. #server.log)
check(Q:Pending() == 40 - Q.BURST, "and the rest waits")
run(60)
check(#server.log <= Q.BURST + 60 / Q.INTERVAL + 1, "a minute later no more than BURST + 60/INTERVAL, saw " .. #server.log)
run(600)
check(#server.log == 40 and Q:Pending() == 0, "and everything goes in the end")
for i = 1, 40 do check(sent[i] == "pace" .. i, "in the order it came") end
check(worstMinute() <= Q.BURST + 60 / Q.INTERVAL, "the worst minute stays under the limit, saw " .. worstMinute())

-- A payload pays its AceComm parts: a 2 KB ad is nine whispers, and what follows it waits for them.
reset()
sent = {}
local big = ("x"):rep(2048)
check(Q.Parts(big) == 9 and Q.Parts(("x"):rep(255)) == 1 and Q.Parts(("x"):rep(256)) == 2, "parts as AceComm cuts them")
addon(big, "low")
addon("after", "low")
check(#sent == 1, "the ad went, the next one waits for its parts")
run((9 - Q.BURST) * Q.INTERVAL + 0.5)
check(#sent == 1, "still waiting while the ad's debt is paid")
run(Q.INTERVAL + 0.5)
check(#sent == 2, "and goes once it is")

-- ── 3. Priority ─────────────────────────────────────────────────────────
reset()
sent = {}
for i = 1, 20 do addon("low" .. i, "low") end
addon("normal1", "normal")
check(addon("high1", "high") == "queued", "a high waits when the bucket is empty")
run(Q.INTERVAL + 0.1)
check(sent[#sent] == "high1", "and goes first, ahead of twenty lows and a normal")
run(Q.INTERVAL)
check(sent[#sent] == "normal1", "then the normal")

-- The queue full: a low makes room for a high, a high is never refused, a low past LOW_TTL is stale.
reset()
for i = 1, Q.QUEUE_MAX + Q.BURST do addon("fill" .. i, "low") end
check(Q:Pending() == Q.QUEUE_MAX, "the queue holds QUEUE_MAX")
check(addon("one more low", "low") == false, "a low past it is refused")
check(addon("urgent", "high") == "queued" and Q:Pending() == Q.QUEUE_MAX, "a high takes a low's place")
for i = 1, Q.QUEUE_MAX do addon("h" .. i, "high") end
check(addon("past it", "high") == "queued", "and a high is never refused")
reset()
sent = {}
for i = 1, 40 do addon("old" .. i, "low") end
addon("keep", "high")
run(Q.LOW_TTL + 2 * Q.INTERVAL)
local stale = Q:Stats().dropped
check(stale > 0 and Q:Pending() == 0, "lows that waited past LOW_TTL are dropped, " .. stale)
check(sent[Q.BURST + 1] == "keep", "and the high went first of what waited")

-- What found the door shut is no whisper: the bucket gets its part back.
reset()
Q:PushAddon("GUILDOS", "shut", "x", "low", function() return false end)
check(Q._state.tokens == Q.BURST and #server.log == 0, "a send that did nothing costs nothing")

-- ── 4. The error: back off, then come back slowly ───────────────────────
reset()
sent = {}
for i = 1, 200 do addon("flood" .. i, "normal") end
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)
check(Q:Interval() == 2 * Q.INTERVAL, "the error doubles the interval")
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)
check(Q:Interval() == 4 * Q.INTERVAL, "and again")
onError({}, "UI_ERROR_MESSAGE", 51, "Not enough mana")
check(Q:Interval() == 4 * Q.INTERVAL, "another error is not the throttle")
onError({}, "UI_ERROR_MESSAGE", THROTTLE)
check(Q:Interval() == 8 * Q.INTERVAL, "the older client's (message) form counts too")
for _ = 1, 10 do onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE) end
check(Q:Interval() == Q.MAX_INTERVAL, "and it stops at MAX_INTERVAL")
local before = #server.log
run(Q.RECOVER_SECONDS - 1)
check(#server.log - before <= 1, "while backed off almost nothing goes, saw " .. (#server.log - before))
run(2)
check(Q:Interval() == Q.MAX_INTERVAL / 2, "a quiet RECOVER_SECONDS halves it, " .. Q:Interval())
run(Q.RECOVER_SECONDS * 6)
check(Q:Interval() == Q.INTERVAL, "and the quiet minutes bring it back to INTERVAL")
check(Q:Stats().throttled == 13, "each error is counted")

-- A server stricter than INTERVAL: the queue finds its pace under it. Without the back-off it would be
-- refused once a minute for each part past 8, about seven a minute.
reset()
server.limit = 8
for t = 0, 3600, 5 do at(t, function() addon("sync" .. t, "low"); addon("sync" .. t .. "b", "low") end) end
run(3600)
print(("  a server of 8 a minute: %d refused in an hour, %d taken, interval %s"):format(server.errors, #server.log, Q:Interval()))
check(server.errors > 0, "a server that takes 8 a minute answers the flood with the error")
check(server.errors <= 60, "and the back-off keeps it to one a minute at most, saw " .. server.errors)
check(worstMinute() <= 8, "the server never took more than it allows")

-- ── 5. Chat lines and clicks ────────────────────────────────────────────
reset()
check(Q:Push("", "x") == false and Q:Push("Bruno Melo", "") == false, "a chat line needs a target and a text")
for i = 1, Q.BURST do Q:Push("Bruno Melo", "line" .. i, "high") end
check(#chatSent == Q.BURST, "a burst of chat lines goes")
check(Q:Push("Bruno Melo", "waits", "high") == "queued", "the next waits")
run(120)
check(#chatSent == Q.BURST, "from a timer, where the game wants a click for a chat line, nothing goes")
Q:Release()
check(#chatSent == Q.BURST + 1 and chatSent[#chatSent].text == "waits", "the next click sends it")
reset()
for i = 1, Q.BURST do addon("before" .. i, "normal") end
check(Q:SendNow("Bruno Melo", "warned") == true and #chatSent == 1, "a click's own whisper goes at once, bucket or not")
check(Q._state.tokens < 0, "and is paid for")
addon("behind", "normal")
check(Q:Pending() == 1, "so what comes after it waits longer")

-- ── 6. The realm bus ────────────────────────────────────────────────────
reset()
local realm = {}
ChehulMesh = {
  dead = {}, REALM_FANOUT = 3,
  Realm = function(_, prefix, payload, key)
    realm[#realm + 1] = key
    -- the mesh whispers it to REALM_FANOUT names at its flush, once YELL is dead
    if ChehulMesh.dead.YELL then at(clock + 5, function() for _ = 1, 3 do wire(parts(payload)) end end) end
  end,
}
check(Q:Realm("ChehulRecruit", "CR2|a", "k1") and Q:Realm("ChehulRecruit", "CR2|b", "k2"), "where YELL lives it goes straight in")
check(#realm == 2, "both")
ChehulMesh.dead.YELL = "InvalidChatType"
realm = {}
check(Q:Realm("ChehulRecruit", ("a"):rep(200), "k1") == true, "where YELL is dead the first one goes in")
check(Q:Realm("ChehulRecruit", ("b"):rep(200), "k2") == false, "the next must wait for the room its whispers take")
run(60)
check(Q:Realm("ChehulRecruit", ("b"):rep(200), "k2") == true, "a minute later it goes")
run(60)
for i = 1, 10 do addon("w" .. i, "low") end
check(Q:Pending() > 0, "with our own whispers waiting")
check(Q:Realm("ChehulRecruit", "c", "k3") == false, "the realm bus waits behind them")
check(Q:Stats().realmSkipped >= 2, "and what it refused is counted")

-- ── 7. An evening of the issue's load ───────────────────────────────────
-- RecruitBeacon:RelayTick offers four ads every 30 s, the gossip whispers a round's ten parts every two minutes
-- (a 2 KB ad among them), and a guild mate's sync answers come by whisper. The server takes 30 a minute.
reset()
server.limit = 30
ChehulMesh = {
  dead = { YELL = "InvalidChatType" }, REALM_FANOUT = 3,
  Realm = function(_, _, payload) at(clock + 10, function() for _ = 1, 3 do wire(parts(payload)) end end) end,
}
local offered, taken = 0, 0
for t = 0, 3600, 30 do
  at(t, function()
    for i = 1, 4 do
      offered = offered + 1
      if Q:Realm("ChehulRecruit", ("ad"):rep(110) .. i, "ad" .. i) then taken = taken + 1 end
    end
  end)
end
for t = 0, 3600, 120 do
  at(t + 7, function()
    addon(("CR3"):rep(680), "low", "Peer A")
    for i = 1, 4 do addon("CRG|" .. i, "low", "Peer B") end
    addon("CRD|digest", "low", "Peer C")
  end)
end
for t = 0, 3600, 300 do
  at(t + 50, function() for i = 1, 6 do addon("S:sync" .. i, "normal", "Guild Mate") end end)
end
run(3700)
print(("  an evening: %d refused, worst minute %d, realm ads %d of %d, %d dropped stale"):format(
  server.errors, worstMinute(), taken, offered, Q:Stats().dropped))
check(server.errors == 0, "an hour of it never draws the error, saw " .. server.errors)
check(worstMinute() <= 20, "the worst minute stays well under the server's 30, saw " .. worstMinute())
check(taken > 0 and taken < offered, ("the realm bus still carries ads, %d of %d offered"):format(taken, offered))
check(Q:Stats().sent > 0 and Q:Pending() == 0, "and everything of ours that was not stale went")

-- ── 8. One message cut in chunks is one unit ────────────────────────────
-- CommSystem cuts a whisper over 250 bytes into chunks that are each a whisper: the queue takes them all or
-- none, and none makes way alone, since a message missing one is lost whole.
local function group(n, prio, tag)
  local payloads = {}
  for i = 1, n do payloads[i] = (tag or "g") .. i end
  return Q:PushAddonGroup("GUILDOS", payloads, "Bruno Melo", prio, function(p) sent[#sent + 1] = p; wire(1) end)
end
reset()
sent = {}
check(group(10, "normal") == "queued" and #sent == Q.BURST and Q:Pending() == 10 - Q.BURST,
  "a message's chunks go in together, a burst of them goes, the rest waits")
run(600)
for i = 1, 10 do check(sent[i] == "g" .. i, "in order") end
reset()
for i = 1, Q.QUEUE_MAX + Q.BURST - 5 do addon("fill" .. i, "normal") end
check(Q:Pending() == Q.QUEUE_MAX - 5, "five places left")
check(group(8, "normal") == false and Q:Pending() == Q.QUEUE_MAX - 5, "eight chunks into five places: none goes in")
check(group(5, "normal") == "queued" and Q:Pending() == Q.QUEUE_MAX, "five do, all of them")
check(addon("one more", "normal") == false, "and nothing more of their rank")
-- Lows make way for a message's chunks, but only when enough of them can.
reset()
for i = 1, Q.QUEUE_MAX + Q.BURST - 3 do addon("n" .. i, "normal") end
for i = 1, 3 do addon("l" .. i, "low") end
check(group(7, "normal") == false and Q:Pending() == Q.QUEUE_MAX, "three lows cannot make room for seven: nothing pushed out")
check(group(3, "normal") == "queued" and Q:Pending() == Q.QUEUE_MAX, "they can for three")
-- A high pushing out one chunk of a waiting message pushes out the whole message.
reset()
for i = 1, Q.BURST do addon("b" .. i, "normal") end
for i = 1, Q.QUEUE_MAX - 6 do addon("n" .. i, "normal") end
check(group(6, "low", "c") == "queued" and Q:Pending() == Q.QUEUE_MAX, "a low message fills the queue")
check(addon("urgent", "high") == "queued", "a high comes")
check(Q:Pending() == Q.QUEUE_MAX - 5, "and the whole low message made way, not one chunk of it")
-- A chunk the game would not send: the rest of its message is no use and goes too.
reset()
sent = {}
for i = 1, Q.BURST do addon("b" .. i, "normal") end
local tries = 0
Q:PushAddonGroup("GUILDOS", { "x1", "x2", "x3" }, "Bruno Melo", "normal", function()
  tries = tries + 1
  return false
end)
run(60)
check(tries == 1 and Q:Pending() == 0, "one refused chunk drops its message, saw " .. tries .. " tries")
-- Off WoW: Forever it all goes at once.
reset()
sent = {}
Q.enabled = false
check(group(5, "normal") == "sent" and #sent == 5, "off Forever a message's chunks go at once")

-- ── 9. A long whisper reaches the other side whole ──────────────────────
-- CommSystem on both ends: the sender's chunks leave through the queue one every INTERVAL, slower while the
-- server throttles; the receiver waits for the next chunk as long as a whisper's chunks may take, and so
-- puts together a message of 40 chunks (~9 KB), which took the old fixed 30 s past its end.
reset()
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
local LD = LibStub("LibDeflate")
LD.CompressDeflate = function(_, s) return s end
LD.EncodeForWoWAddonChannel = function(_, s) return s end
LD.DecodeForWoWAddonChannel = function(_, s) return s end
LD.DecompressDeflate = function(_, s) return s end
GuildOS.State = GuildOS.State or {}
GuildOS.State.comm = GuildOS.State.comm or {}
GuildOS.PREFIX = GuildOS.PREFIX or "GuildOS"
dofile(ADDON .. "/Modules/CommSystem.lua")
local CS = GuildOS.CommSystem
local got = {}
GuildOS.RecipeTracker = { HandleIncoming = function(_, from, data) got[#got + 1] = { from = from, data = data } end }
local wireMsgs = {}
GuildOS.Compat.SendAddonMessage = function(_, msg, channel)
  check(channel == "WHISPER", "a whisper")
  wireMsgs[#wireMsgs + 1] = msg
  wire(1)
  CS:OnMessageReceived(msg, "WHISPER", "Bruno Melo")
end
local body = ("r"):rep(40 * CS.CHUNK_SIZE - 10)
CS:SendMessage("RC", body, "Bruno Melo")
check(#wireMsgs == Q.BURST and #got == 0, "a burst of the chunks goes, the rest waits in the queue")
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)   -- and the server throttles meanwhile
run(1800)
check(#wireMsgs == 40, "all forty chunks went, saw " .. #wireMsgs)
check(#got == 1 and got[1].data == body and got[1].from == "Bruno Melo", "and the receiver put the message together")
check(next(CS.pendingMessages) == nil and CS.syncStats.dropped == 0, "nothing left half-received, nothing counted lost")
-- A chunk that never comes: the receiver still gives up, once no chunk came for its window.
CS:OnMessageReceived("M:ABCD:1:3:half", "WHISPER", "Bruno Melo")
run(CS.WHISPER_CHUNK_SECONDS - 1)
check(CS.pendingMessages["Bruno Melo:ABCD"] ~= nil, "a whisper waits its window for the next chunk")
CS:OnMessageReceived("M:ABCD:2:3:more", "WHISPER", "Bruno Melo")
run(CS.WHISPER_CHUNK_SECONDS - 1)
check(CS.pendingMessages["Bruno Melo:ABCD"] ~= nil, "each chunk renews it")
run(2)
check(CS.pendingMessages["Bruno Melo:ABCD"] == nil and CS.syncStats.dropped == 1, "a window without one: lost, and counted")
CS:OnMessageReceived("M:BCDE:1:3:half", "GUILD", "Bruno Melo")
run(CS.CHUNK_SECONDS + 1)
check(CS.pendingMessages["Bruno Melo:BCDE"] == nil, "over GUILD the window stays CHUNK_SECONDS")

-- ── 10. The shared mesh, until its own budget lands (LibChehulMesh v12) ──
-- The error quiets the mesh's relay and realm flush for MESH_QUIET seconds where it has those knobs, and puts them
-- back as they were; where it has none nothing happens. Where the mesh asks a host before each whisper (whisperGate),
-- its whispers are paid from this queue's bucket.
reset()
check(pcall(Q.OnThrottle, Q) and Q:QuietMesh(10) == false, "with no mesh at all the guard does nothing")
reset()
ChehulMesh = { version = 11, dead = {} }
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)
check(ChehulMesh.RELAY_BUDGET == nil and ChehulMesh.YELL_PER_FLUSH == nil and ChehulMesh.whisperGate == nil,
  "a mesh without the knobs is not touched, and an old one gets no gate")
reset()
ChehulMesh = { version = 11, dead = {}, RELAY_BUDGET = 30, YELL_PER_FLUSH = 4 }
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)
check(ChehulMesh.RELAY_BUDGET == 0 and ChehulMesh.YELL_PER_FLUSH == 0, "the error quiets the mesh's relay and realm flush")
run(Q.MESH_QUIET / 2)
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)   -- again, halfway
run(Q.MESH_QUIET / 2 + 1)
check(ChehulMesh.RELAY_BUDGET == 0 and ChehulMesh.YELL_PER_FLUSH == 0, "a second error keeps it quiet past the first one's minute")
run(Q.MESH_QUIET / 2)
check(ChehulMesh.RELAY_BUDGET == 30 and ChehulMesh.YELL_PER_FLUSH == 4, "then the knobs come back as they were")
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)
ChehulMesh.RELAY_BUDGET = 6   -- the host or a newer lib changed it meanwhile
run(Q.MESH_QUIET + 1)
check(ChehulMesh.RELAY_BUDGET == 6 and ChehulMesh.YELL_PER_FLUSH == 4, "a value somebody else set meanwhile stands")
reset()
Q.enabled = false
ChehulMesh = { version = 11, dead = {}, RELAY_BUDGET = 30, YELL_PER_FLUSH = 4 }
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)
check(ChehulMesh.RELAY_BUDGET == 30, "off WoW: Forever the mesh is left alone")

-- v12's gate.
reset()
local meshSent = 0
ChehulMesh = { version = 12, dead = { YELL = "InvalidChatType" }, REALM_FANOUT = 2, RELAY_BUDGET = 6, YELL_PER_FLUSH = 4,
  Realm = function() end }
-- What the v12 mesh does before each whisper: asks the gate, sends only when it does not say false.
local function meshWhisper(parts_)
  local gate = ChehulMesh.whisperGate
  if gate and gate("Peer A", parts_ or 1, "ChehulRecruit") == false then return false end
  meshSent = meshSent + 1
  wire(parts_ or 1)
  return true
end
check(Q:HookMesh() and ChehulMesh.whisperGate == Q.MeshGate, "the gate is registered on a v12 mesh")
local other = function() return true end
ChehulMesh.whisperGate = other
check(not Q:HookMesh() and ChehulMesh.whisperGate == other, "never over another host's gate")
ChehulMesh.whisperGate = nil
Q:HookMesh()
local tokens0 = Q._state.tokens
check(meshWhisper(1) and Q._state.tokens == tokens0 - 1, "a mesh whisper is paid from the queue's bucket")
check(meshWhisper(2) and Q._state.tokens == tokens0 - 3, "by its parts")
check(meshWhisper(1) and Q._state.tokens < 1, "the last token goes")
check(not meshWhisper(1) and Q:Stats().meshVeto == 1, "an empty bucket vetoes the next")
run(60)
for i = 1, 10 do addon("ours" .. i, "normal") end
check(Q:Pending() > 0 and not meshWhisper(1), "while our own whispers wait, the mesh's wait behind them")
run(600)
check(Q:Pending() == 0 and meshWhisper(1), "and go once ours have")
-- A realm item :Realm paid for: its flush whispers draw on what it paid, not on the bucket again.
reset()
ChehulMesh = { version = 12, dead = { YELL = "InvalidChatType" }, REALM_FANOUT = 2, Realm = function() end }
Q:HookMesh()
check(Q:Realm("ChehulRecruit", "CR2|a", "k1"), "a realm item goes in, paid")
local afterRealm = Q._state.tokens
check(meshWhisper(1) and meshWhisper(1) and Q._state.tokens == afterRealm, "its two flush whispers pass on what it paid")
-- One of our own items whose send goes through the mesh is not paid twice.
reset()
ChehulMesh = { version = 12, dead = {}, Realm = function() end }
Q:HookMesh()
local before10 = Q._state.tokens
Q:PushAddon("ChehulRecruit", "x", "Peer A", "normal", function() return meshWhisper(1) end)
check(meshSent > 0 and Q._state.tokens == before10 - 1, "our own item sent through the mesh is paid once")
-- After the error, nothing through the gate for MESH_QUIET seconds.
onError({}, "UI_ERROR_MESSAGE", 51, THROTTLE)
run(Q.MESH_QUIET - 1)
Q._state.tokens = Q.BURST
check(not meshWhisper(1), "the gate holds the mesh for MESH_QUIET after the error")
run(2)
check(meshWhisper(1), "and lets it go after")
-- An evening of the mesh whispering on its own beside ours: with the gate, the server never draws the error.
reset()
server.limit = 30
ChehulMesh = { version = 12, dead = { YELL = "InvalidChatType" }, Realm = function() end }
Q:HookMesh()
for t = 0, 3600, 2 do at(t, function() meshWhisper(1) end) end
for t = 0, 3600, 20 do at(t + 1, function() addon("sync" .. t, "normal") end) end
run(3700)
check(server.errors == 0 and worstMinute() <= 30, ("mesh and queue together stay under the server's limit: %d errors, worst minute %d")
  :format(server.errors, worstMinute()))
check(Q:Pending() == 0, "and ours all went")
ChehulMesh = nil

print(("whisper-queue: %d checks passed"):format(checks))
