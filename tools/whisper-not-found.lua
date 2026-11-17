-- The "No player named" line of GuildOS's own addon whispers (issue #326), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua, Modules/AllianceSync.lua, Modules/Alliance.lua and
-- Modules/CraftNet.lua under a stubbed WoW: Forever client, on a fake mesh and a fake clock.
--
-- An addon whisper to somebody who logged off a moment ago makes the client print ERR_CHAT_PLAYER_NOT_FOUND_S, once
-- per part of the message, in every chat frame. The vendored mesh hides the line only for the names it whispers
-- itself, and the bridge's heartbeat (AllianceSync:Tick, every 120 s, to any peer heard in the last 600 s) and the
-- login probe (ProbeStaleGuilds, blind) whispered through Mesh:Whisper noting nothing: on Forever a player saw the
-- yellow line spam the chat. The rules: the heartbeat, the probe, CraftNet's answer and a targeted CommSystem message
-- each hide that line for their target, whichever way the game spells the name back (case, hyphen or space, a realm
-- on the end); every part of a long message is hidden, however long the parts take; anybody else's line, any other
-- line and a line once the window is over still show; a secret line is left alone unread; a client with no chat
-- filter is no error. And a scan of every Lua file the TOC loads (Libs and the vendored ChehulNet.lua aside) fails on
-- any addon whisper that does not note its target first, so a new one cannot let the line through either.
-- Chat whispers a player sends (SendChatMessage) are not ours to hide: the line is their answer.
--
--   luajit -e 'ADDON="."' tools/whisper-not-found.lua
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

local NOT_FOUND = "No player named '%s' is currently playing."
local PART = 255   -- bytes of one addon message part: a longer one leaves in several, each answered on its own

-- ── The clock ───────────────────────────────────────────────────────────
local clock, queue = 0, {}

local function at(when, fn)
  local i = #queue
  while i > 0 and queue[i].when > when do i = i - 1 end
  table.insert(queue, i + 1, { when = when, fn = fn })
end

local function run(seconds)
  local stop = clock + seconds
  while queue[1] and queue[1].when <= stop do
    local item = table.remove(queue, 1)
    clock = item.when
    item.fn()
  end
  clock = stop
end

-- A value that raises on any use but passing it along, like the client's secrets.
local function raises() error("a secret was read") end
local SECRET = setmetatable({}, { __index = raises, __concat = raises, __len = raises, __lt = raises, __le = raises,
                                  __tostring = raises, __call = raises })
local rawType = type
type = function(v) return rawequal(v, SECRET) and "string" or rawType(v) end
issecretvalue = function(v) return rawequal(v, SECRET) end

-- ── The chat: the filters a chat frame runs, and what reaches it ────────
local filters, chat = {}, {}
ChatFrame_AddMessageEventFilter = function(event, fn)
  filters[event] = filters[event] or {}
  table.insert(filters[event], fn)
end

local function system(line)
  for _, fn in ipairs(filters.CHAT_MSG_SYSTEM or {}) do
    if fn({}, "CHAT_MSG_SYSTEM", line) then return end
  end
  chat[#chat + 1] = line
end

local function shown(name)
  local n, line = 0, NOT_FOUND:format(name)
  for _, l in ipairs(chat) do if l == line then n = n + 1 end end
  return n
end

-- ── The world: who is online, and how the game spells a name it cannot find ───
local online, echo = {}, {}
local world = { partGap = 0.1 }   -- seconds between two parts of one message leaving
local whispers = {}               -- every addon whisper that left: { target, text, at }

-- Each part of a whisper to somebody gone answers the line, in the spelling the game uses for them.
local function whisper(target, text)
  whispers[#whispers + 1] = { target = target, text = text, at = clock }
  if online[target] then return end
  for i = 1, math.max(1, math.ceil(#text / PART)) do
    at(clock + 0.2 + (i - 1) * world.partGap, function() system(NOT_FOUND:format(echo[target] or target)) end)
  end
end

-- ── The client: WoW: Forever, "Chehul Costa" of "Minha Guilda" ──────────
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent, RAID_CLASS_COLORS = {}, {}
ERR_CHAT_PLAYER_NOT_FOUND_S = NOT_FOUND
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function GetTime() return clock end
time = function() return 1790000000 + math.floor(clock) end
GetServerTime = time
function hooksecurefunc() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(delim, s)
  local out, from = {}, 1
  while true do
    local hit = s:find(delim, from, true)
    if not hit then out[#out + 1] = s:sub(from); break end
    out[#out + 1] = s:sub(from, hit - 1)
    from = hit + 1
  end
  return unpack(out)
end
strmatch = string.match
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
function UnitName() return "Chehul" end
function UnitFullName() return "Chehul", "Costa" end
function GetRealmName() return "Classic Beta PvE" end
function GetNormalizedRealmName() return "ClassicBetaPvE" end
function IsInGuild() return true end
function GetGuildInfo() return "Minha Guilda", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInInstance() return false, "none" end
C_Timer = {
  After = function(delay, fn) at(clock + delay, fn) end,
  NewTicker = function() return { Cancel = function() end } end,
}
C_ChatInfo = {
  InChatMessagingLockdown = function() return false end,
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(_, text, channel, target)
    if channel == "WHISPER" then whisper(target, text) end
    return true
  end,
}
ChatThrottleLib = {
  SendAddonMessage = function(_, _, _, text, channel, target, _, callback)
    if channel == "WHISPER" then whisper(target, text) end
    if callback then callback(nil, true) end
  end,
}
-- The shared mesh, as GuildOS sees it: a whisper leaves whole, in parts, and Mesh:Whisper notes nothing.
ChehulMesh = {
  Whisper = function(_, _, payload, target) whisper(target, payload); return true end,
  Register = function() end, Guild = function() return true end, Proximity = function() return true end,
  Realm = function() end,
}
-- Presence: "Bruno Melo" of "Outra Guilda" was heard 590 s ago, and has logged off since.
ChehulNet = { Peers = function() return { ["Bruno Melo"] = { ts = time() - 590 } } end }

dofile(ADDON .. "/Libs/LibStub.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
GuildOSDB = {}
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }),
            SelfTest = { Register = function() end } }
dofile(ADDON .. "/Core/Config.lua")
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/AllianceSync.lua")
dofile(ADDON .. "/Modules/Alliance.lua")
dofile(ADDON .. "/Modules/CraftNet.lua")
check(not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail and GuildOS.Client.has.surnames,
      "the stub is WoW: Forever, with surnames")

local A, AS = GuildOS.Alliance, GuildOS.AllianceSync
GuildOS.Mesh = { GetPeerGuild = function(_, short) return short == "Bruno Melo" and "Outra Guilda" or nil end }
A.AmBridge = function() return true end   -- the election is not what this is about
GuildOS.db = {
  members = {},
  alliance = { tag = "BR", guilds = {
    ["Minha Guilda"]    = { ambassadors = { "Chehul Costa" } },
    ["Outra Guilda"]    = { ambassadors = { "Bruno Melo" } },
    -- Silent for over an hour and invisible: the probe whispers its ambassadors blind, as the pact spells them.
    ["Terceira Guilda"] = { ambassadors = { "Dora-Rosa", "Eva Lima-Azralon" } },
  } },
}
echo["Dora-Rosa"], echo["Eva Lima-Azralon"] = "Dora Rosa", "Eva Lima"

-- ── 1. The bridge's heartbeat: a peer presence still lists, gone since ──
check(A:PeerTarget("Outra Guilda") == "Bruno Melo", "presence still names a peer heard 590 s ago")
AS:Tick()
check(#whispers == 1 and whispers[1].target == "Bruno Melo", "the heartbeat whispers that peer")
run(1)
check(#chat == 0, "and the line the game answers is hidden: the heartbeat noted its target")
check(#(filters.CHAT_MSG_SYSTEM or {}) == 1, "by one filter on the system chat")
run(130)
AS:Tick()
run(1)
check(#whispers == 2 and #chat == 0, "and so is the next tick's, 120 s on")

-- ── 2. The login probe, blind, to the pact's own spelling ───────────────
AS:ProbeStaleGuilds()
check(#whispers == 4 and AS.stats.probes == 2, "the probe whispers the silent guild's two ambassadors")
run(1)
check(#chat == 0, "and both lines are hidden, a hyphen for a space and a realm on the end included")

-- ── 3. CraftNet answers an asker who has just logged off ────────────────
GuildOS.RecipeTracker = { LocalCrafts = function() return "Alchemy" end }
echo["Fábio Reis-Azralon"] = "Fábio Reis"
GuildOS.CraftNet:OnMessage("CC1|Q|1234|q1", "Fábio Reis-Azralon", "YELL")
check(#whispers == 5 and whispers[5].target == "Fábio Reis-Azralon", "CraftNet whispers its answer to the asker")
run(1)
check(#chat == 0, "and that line is hidden too")

-- Text that does not compress, so it leaves in as many parts as its length says.
math.randomseed(326)
local function noise(n)
  local out = {}
  for i = 1, n do out[i] = string.char(math.random(33, 122)) end
  return table.concat(out)
end

-- ── 4. A targeted CommSystem message, in several chunks ─────────────────
local before = #whispers
echo["gil souza"] = "Gil Souza"
GuildOS.CommSystem:SendMessage("RS", noise(2000), "gil souza")
run(5)
check(#whispers - before >= 3 and whispers[#whispers].target == "gil souza",
      "CommSystem whispers a guildmate, chunk by chunk")
check(#chat == 0, "and every chunk's line is hidden, the game's capitals included")

-- ── 5. A long message: each part answers, for as long as the parts take ───
world.partGap = 4
A:Send("PUSH", { blob = noise(30 * PART) }, "Hugo Alves")
check(math.ceil(#whispers[#whispers].text / PART) * world.partGap > 3 * 30,
      "the push takes three windows and more to answer, part by part")
run(200)
check(#chat == 0, "and it is hidden from the first line to the last")
world.partGap = 0.1

-- ── 6. Only our lines, only while they are ours ─────────────────────────
system(NOT_FOUND:format("Iris Prado"))
check(shown("Iris Prado") == 1, "somebody else's line still shows")
system("Iris Prado has come online.")
check(#chat == 2, "and so does every other line")
run(60)
system(NOT_FOUND:format("Bruno Melo"))
check(shown("Bruno Melo") == 1, "once the window is over the same name's line shows again")
system(SECRET)
check(chat[#chat] == SECRET, "a line in lockdown is secret: left alone")
check(#GuildOS.State.errors == 0, "and never read, which would raise")

-- ── 7. The shared helper ────────────────────────────────────────────────
local gone = {}
GuildOS:OnWhisperNotFound(function(name) gone[#gone + 1] = name end)
check(GuildOS:NoteWhisper("joana-lins") == true, "a note says a filter is there to hide the line")
system(NOT_FOUND:format("Joana Lins"))
check(shown("Joana Lins") == 0 and gone[1] == "Joana Lins", "a hidden line is handed on, spelled as the game wrote it")
check(GuildOS:NoteWhisper(SECRET) == false and #GuildOS.State.errors == 0, "a secret name is not read")
local broken = GuildOS.MatchFormat
GuildOS.MatchFormat = function() error("the filter broke") end
system("anything at all")
check(chat[#chat] == "anything at all", "a filter that breaks costs a chat frame nothing")
check(#GuildOS.State.errors == 1, "and is recorded")
system("anything else")
check(#GuildOS.State.errors == 1, "once")
GuildOS.MatchFormat = broken
check(#(filters.CHAT_MSG_SYSTEM or {}) == 1, "however many whispers went, the filter went in once")

GuildOS.State.whispers, ChatFrame_AddMessageEventFilter = nil, nil
check(GuildOS:NoteWhisper("Bruno Melo") == false and #GuildOS.State.errors == 1,
      "a client with no chat filter notes the name, says so, and that is no error")

-- ── 8. Every addon whisper of GuildOS's own notes its target first ──────
COMPAT_GUARD_LIBRARY = true
local G = dofile(ADDON .. "/tools/compat-guard.lua")
COMPAT_GUARD_LIBRARY = nil
local VENDORED = { ["Modules/ChehulNet.lua"] = true }   -- shipped verbatim from danielcosta42/chehulnet
local NOTE_REACH = 3                                    -- lines above a send its NoteWhisper may stand on

-- file:line of each addon whisper in `src` with no NoteWhisper on its line or the NOTE_REACH above it, and how
-- many whispers it found. A whisper is a mesh's :Whisper, or an addon message sent with "WHISPER" on the line.
local function scan(rel, src)
  local raw, code = {}, {}
  for l in (src .. "\n"):gmatch("([^\n]*)\n") do raw[#raw + 1] = l end
  for l in (G.blank(src) .. "\n"):gmatch("([^\n]*)\n") do code[#code + 1] = l end
  local misses, found = {}, 0
  for i, line in ipairs(code) do
    local viaMesh = line:find("[Mm]esh%s*:%s*Whisper%s*%(") ~= nil
    local viaAddon = (line:find("SendAddonMessage%w*%s*%(") or line:find("SendCommMessage%s*%("))
      and ((raw[i] or ""):find('"WHISPER"', 1, true) or (raw[i + 1] or ""):find('"WHISPER"', 1, true))
    if viaMesh or viaAddon then
      found = found + 1
      local noted = false
      for j = math.max(1, i - NOTE_REACH), i do
        if code[j]:find("NoteWhisper%s*%(") then noted = true end
      end
      if not noted then misses[#misses + 1] = rel .. ":" .. i end
    end
  end
  return misses, found
end

local unnoted = scan("new.lua", 'local mesh = _G.ChehulMesh\nmesh:Whisper(P, "x", name)\n')
check(#unnoted == 1, "the scan catches a mesh whisper that notes nothing")
unnoted = scan("new.lua", 'Compat.SendAddonMessage(P, msg,\n    "WHISPER", name)\n')
check(#unnoted == 1, "and an addon message whose WHISPER is on the next line")
unnoted = scan("new.lua", 'GuildOS:NoteWhisper(name)\nmesh:Whisper(P, "x", name)\n-- mesh:Whisper(P, "x", n)\n')
check(#unnoted == 0, "and lets one that notes its target pass, and a comment")

local misses, perFile = {}, {}
for _, rel in ipairs(G.files(ADDON)) do
  local fh = not VENDORED[rel] and io.open(ADDON .. "/" .. rel, "rb")
  if fh then
    local m, found = scan(rel, fh:read("*a"))
    fh:close()
    perFile[rel] = found
    for _, hit in ipairs(m) do misses[#misses + 1] = hit end
  end
end
check(#misses == 0, "every addon whisper notes its target first (GuildOS:NoteWhisper): " .. table.concat(misses, ", "))
check((perFile["Modules/Alliance.lua"] or 0) >= 1 and (perFile["Modules/CraftNet.lua"] or 0) >= 1
  and (perFile["Modules/CommSystem.lua"] or 0) >= 1 and (perFile["Modules/ChehulGossip.lua"] or 0) >= 2,
  "and the scan sees the whispers it guards: the alliance, CraftNet, CommSystem and the gossip")

print(("whisper-not-found: %d checks passed"):format(checks))
