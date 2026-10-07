-- Guild chat kept for the Guild tab (issue #124), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua and Modules/GuildChat.lua.
--
-- Every line of /g, the player's own included, lands in the guild's own log, the last 200
-- across sessions; a line the client keeps secret is skipped; Enter sends to /g.
--
--   luajit -e 'ADDON="."' tools/guild-chat.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(_, fn) self.fn = fn end
  frames[#frames + 1] = f
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Ana" end
local NOW = 1790000000
function GetServerTime() return NOW end
time = function() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function() end, NewTicker = function() end }
function Ambiguate(name) return (name:gsub("%-Realm$", "")) end
local classes = { ["Player-1-A"] = "MAGE", ["Player-1-B"] = "PRIEST" }
local secret = {}   -- a value the client keeps secret; asking the game about one errors, as it does there
function GetPlayerInfoByGUID(guid)
  if guid == secret then error("secret GUID") end
  if guid == "Player-1-S" then return secret, secret end
  local c = classes[guid]; if c then return c:lower(), c end
end
local sent = {}
function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/GuildChat.lua")
GuildOS.db, GuildOS.isGuilded = {}, true

local GC = GuildOS.GuildChat
GC:Initialize()

local function say(msg, author, guid)
  for _, f in ipairs(frames) do
    if f.events.CHAT_MSG_GUILD then
      f.fn(f, "CHAT_MSG_GUILD", msg, author, "", "", author, "", 0, 0, "", 0, 1, guid)
    end
  end
end

local notified = 0
GC:OnRefresh(function() notified = notified + 1 end)

-- ── Capture ─────────────────────────────────────────────────────────────
say("boa noite", "Bruna-Realm", "Player-1-B")
local log = GC:Log()
check(#log == 1 and log[1].n == "Bruna" and log[1].c == "PRIEST" and log[1].m == "boa noite" and log[1].t == NOW,
  "a line of /g is kept: who said it, their class, what and when")
check(GuildOS.db.guildChatLog == log, "in the guild's own saved data, so it is there after a reload")
check(notified == 1, "and whoever shows the feed is told")
say("oi", "Ana-Realm", "Player-1-A")
check(#log == 2 and log[2].n == "Ana" and log[2].c == "MAGE", "the player's own lines are kept too")

local link = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
say("olha " .. link .. "\nnovo", "Bruna-Realm", "Player-1-B")
check(log[3].m == "olha " .. link .. " novo", "an item link is kept whole, a line break is not")
say("sem guid", "Caio-Realm", nil)
check(log[4].n == "Caio" and log[4].c == nil, "a line with no class to read is kept without one")

-- ── Secret ──────────────────────────────────────────────────────────────
issecretvalue = function(v) return v == secret end
say(secret, "Bruna-Realm", "Player-1-B")
say("x", secret, "Player-1-B")
check(#log == 4, "a line or a speaker the client keeps secret is skipped")
say("y", "Bruna-Realm", secret)
check(#log == 5 and log[5].m == "y" and log[5].c == nil, "a secret GUID only loses the class")
say("z", "Bruna-Realm", "Player-1-S")
check(#log == 6 and log[6].c == nil, "and so does a class the client answers secret")
issecretvalue = nil

-- ── The cap ─────────────────────────────────────────────────────────────
for i = 1, 250 do say("line " .. i, "Bruna-Realm", "Player-1-B") end
check(#log == GC.MAX_LOG and GC.MAX_LOG == 200, "the log keeps the last 200 lines")
check(log[1].m == "line 51" and log[200].m == "line 250", "dropping the oldest")

-- ── Another guild ───────────────────────────────────────────────────────
GuildOS.db = {}
check(#GC:Log() == 0, "another guild's data starts its own log")

-- ── Send ────────────────────────────────────────────────────────────────
check(GC:Send("  boa |cffff0000raid|r  ") == true, "Enter sends")
check(#sent == 1 and sent[1].chan == "GUILD" and sent[1].msg == "boa cffff0000raidr",
  "to /g, trimmed and with no escape code")
check(GC:Send("   ") == false and #sent == 1, "an empty box sends nothing")
GC:Send(string.rep("a", 300))
check(#sent[2].msg == 240, "a long line is cut to 240 bytes")
check(#GC:Log() == 0, "the sent line is not logged twice: it shows when the game echoes it back")

-- Forever drops a line sent while an encounter locks chat, without an error (as CallToArms knows).
local locked = true
C_ChatInfo = { InChatMessagingLockdown = function() return locked end }
local ok, why = GC:Send("bora")
check(ok == false and why == "locked" and #sent == 2, "in a chat lockdown nothing is sent, and Send says why")
locked = false
check(GC:Send("bora") == true and sent[3].msg == "bora", "and once it lifts, it is")
C_ChatInfo = nil

-- ── Outside a guild ─────────────────────────────────────────────────────
-- The data the addon resolved at login is a guildless one, shared by every guildless character on the
-- realm: a guild joined since then is not written into it.
GuildOS.isGuilded = false
say("bem-vindo", "Bruna-Realm", "Player-1-B")
check(#GC:Log() == 0, "a character the addon does not know to be in a guild keeps nothing")
GuildOS.isGuilded = true

-- ── The server's own history (WoW: Forever, issue #126) ─────────────────
-- Measured on Forever: the guild's club streams hold what was said while the player was offline,
-- each message as { messageId = { epoch (microseconds), position }, author = { name, classID }, content }.
-- Read the way Blizzard_Communities reads them: GetMessagesBefore from the newest of the last range.
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] then f.fn(f, event, ...) end
  end
end
check(select(2, GC:Entries()) == false and GC:Streams() == nil,
  "a client without C_Club shows the addon's own log, and no list of channels")
-- On the client a secret keeps its type: a secret name or text is still a string, so type() lets it through.
local secretName, secretText, secretEpoch = "Nome Secreto", "texto secreto", 4242e6
issecretvalue = function(v) return v == secret or v == secretName or v == secretText or v == secretEpoch end

-- Enum.ClubStreamType on Forever: General 0, Guild 1, Officer 2, Discord 3, Other 4 (ClubDocumentation.lua).
local club = { id = "C1", streams = { { streamId = "2", streamType = 2, name = "Officer" },
                                      { streamId = "9", streamType = 4, name = "Raid Team" },
                                      { streamId = "5", streamType = 3, name = "Ponte Discord" },
                                      { streamId = "0", streamType = 0, name = "General" },
                                      { streamId = "8", streamType = 4, name = secretName },
                                      { streamId = "7", streamType = 1, name = "Guild" } },
              msgs = {}, other = {}, asked = {}, said = {}, focus = {}, emptyRange = {} }
local function msgsOf(s) if s == "7" then return club.msgs end return club.other[s] or {} end
local locked = false
-- In a chat lockdown these answer secrets (SecretInChatMessagingLockdown): reading one there is a bug.
local function readable(what) if locked then error(what .. " read in a chat lockdown") end end
C_ChatInfo = { InChatMessagingLockdown = function() return locked end }
local function message(epoch, name, classID, content, destroyed)
  return { messageId = { epoch = epoch, position = 0 }, author = { name = name, classID = classID },
           content = content, destroyed = destroyed }
end
C_Club = {
  GetGuildClubId = function() return club.id end,
  GetStreams = function() readable("GetStreams"); return club.streams end,
  GetMessageRanges = function(c, s)
    readable("GetMessageRanges")
    local list = msgsOf(s)
    -- An empty range: its newest before its oldest, as Blizzard_Communities' RangeIsEmpty reads one.
    if club.emptyRange[s] then
      return { { oldestMessageId = { epoch = 2, position = 0 }, newestMessageId = { epoch = 1, position = 0 } } }
    end
    if c ~= club.id or #list == 0 then return {} end
    return { { oldestMessageId = list[1].messageId, newestMessageId = list[#list].messageId } }
  end,
  GetMessagesBefore = function(_, s, newest, count)
    readable("GetMessagesBefore")
    local list, upTo = msgsOf(s), 0
    for i, m in ipairs(list) do if m.messageId == newest then upTo = i end end
    local out = {}
    for i = math.max(1, upTo - count + 1), upTo do out[#out + 1] = list[i] end
    return out
  end,
  FocusStream = function(c, s) club.focus[s] = (club.focus[s] or 0) + 1; club.focused = c .. "/" .. s end,
  UnfocusStream = function(c, s) club.focus[s] = (club.focus[s] or 0) - 1; if club.focused == c .. "/" .. s then club.focused = nil end end,
  RequestMoreMessagesBefore = function(c, s, id, count)
    readable("RequestMoreMessagesBefore")
    club.asked[#club.asked + 1] = { c = c, s = s, id = id, count = count }
  end,
  SendMessage = function(c, s, text) club.said[#club.said + 1] = { c = c, s = s, text = text } end,
}
local CLASSES = { [8] = "MAGE", [5] = "PRIEST" }
function GetClassInfo(id) if CLASSES[id] then return "x", CLASSES[id], id end end

say("antes do servidor", "Bruna-Realm", "Player-1-B")
local entries, server = GC:Entries()
check(server == false and entries[1].m == "antes do servidor",
  "while the server has nothing loaded, the tab shows the addon's own log")
GC:Watch(true)
check(club.focused == "C1/7" and #club.asked == 1 and club.asked[1].s == "7" and club.asked[1].id == nil,
  "and opening it focuses the stream and asks for its recent lines, as the Communities window does")
GC:Watch(false)
check(club.focused == nil, "closing it stops")

local E = 1790000000 * 1e6
club.msgs = {
  message(E - 86400e6, "Elyndora Saurfang", 8, "proc a skill"),
  message(E - 3600e6, "Apagada Silva", 5, "isso some", true),
  message(E - 1800e6, "Oculta Costa", 5, secretText),
  message(secretEpoch, "Hora Secreta", 5, "quando?"),
  message(E - 60e6, "Chehul Costa", 5, "tamo |cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r\njunto"),
}
entries, server = GC:Entries()
check(server == true and #entries == 2, "once it has, the tab shows the server's lines, and only those")
check(entries[1].n == "Elyndora Saurfang" and entries[1].c == "MAGE" and entries[1].t == 1790000000 - 86400
  and entries[1].m == "proc a skill", "each with its speaker, class and time, from yesterday too")
check(entries[2].n == "Chehul Costa" and entries[2].m == "tamo |cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r junto",
  "oldest first, the link kept, the line break not; deleted lines and secret times or texts left out")

club.msgs[1].author.name = secretName
check(#GC:Entries() == 1, "a message whose speaker is secret is skipped")
club.msgs[1].author.name = "Elyndora Saurfang"

-- Opening the tab: the stream is focused, and older lines are asked for while there are fewer than 200.
GC:Watch(true)
local ask = club.asked[#club.asked]
check(club.focused == "C1/7" and #club.asked == 2 and ask.s == "7" and ask.id == club.msgs[1].messageId
  and ask.count == 198, "opening the tab asks for the 198 lines before the oldest it has")
-- The Now card and Guild > Chat can both show /g: the server hears the first open and the last close.
GC:Watch(true)
check(club.focus["7"] == 1 and #club.asked == 2, "a second feed on the same channel focuses nothing more")
GC:Watch(false)
check(club.focused == "C1/7", "and closing one of the two leaves it focused")
GC:Watch(false)
check(club.focused == nil and club.focus["7"] == 0, "closing the last stops")
GC:Watch(false)
GC:Watch(true)
GC:Watch(false)
check(club.focus["7"] == 0 and club.focused == nil, "and a close with nothing open does nothing: the next open and close still pair")

local many = {}
for i = 1, 250 do many[i] = message(E + i * 1e6, "Bruna Lima", 5, "linha " .. i) end
club.msgs = many
entries = GC:Entries()
check(#entries == 200 and entries[1].m == "linha 51" and entries[200].m == "linha 250", "the last 200 of the server's lines")
local asks = #club.asked
GC:Watch(true)
check(#club.asked == asks, "with 200 in hand nothing more is asked for")
GC:Watch(false)

-- Live: anything in the guild's club redraws the tab; another club, or a secret one, does not.
notified = 0
fire("CLUB_MESSAGE_ADDED", "C1", "7")
fire("CLUB_MESSAGE_HISTORY_RECEIVED", "C1", "7")
fire("CLUB_MESSAGE_ADDED", "C1", "2")
check(notified == 3, "a new line, or older ones arriving, in any of the guild's channels redraws the tab")
fire("CLUB_STREAM_ADDED", "C1", "11")
fire("CLUB_STREAM_REMOVED", "C1", "9")
fire("CLUB_STREAMS_LOADED", "C1")
check(notified == 6, "and so does a channel made, removed, or the list arriving")
fire("CLUB_MESSAGE_ADDED", "C2", "1")
fire("CLUB_STREAM_ADDED", "C2", "1")
fire("CLUB_MESSAGE_ADDED", secret, secret)
check(notified == 6, "a line or a channel in another club, or a secret one, does not")

-- ── Every channel of the guild ──────────────────────────────────────────
local streams = GC:Streams()
check(streams and #streams == 3 and streams[1].kind == "guild" and streams[1].id == "7"
  and streams[2].kind == "officer" and streams[2].id == "2"
  and streams[3].kind == "other" and streams[3].id == "9" and streams[3].name == "Raid Team",
  "Guild, Officer, then the channels the guild made; not General, Discord, or one whose name is secret")
local officer, raidTeam = streams[2], streams[3]
club.other["2"] = { message(E - 120e6, "Chefe Lima", 8, "pauta da reuniao") }
entries, server = GC:Entries(officer)
check(server == true and #entries == 1 and entries[1].m == "pauta da reuniao", "each channel shows its own lines")
check(#GC:Entries(raidTeam) == 0, "and one with nothing loaded shows nothing, never the guild's log")
club.emptyRange["9"] = true
GC:Watch(true, raidTeam)
ask = club.asked[#club.asked]
check(#GC:Entries(raidTeam) == 0 and ask.s == "9" and ask.id == nil,
  "an empty range counts as nothing held: the recent lines are asked for")
GC:Watch(false, raidTeam)
club.emptyRange["9"] = nil
GC:Watch(true, officer)
ask = club.asked[#club.asked]
check(club.focused == "C1/2" and ask.s == "2" and ask.count == 199, "opening one focuses it and asks for its older lines")
GC:Watch(false, officer)

check(GC:Send("oi chefes", officer) == true and sent[#sent].chan == "OFFICER" and sent[#sent].msg == "oi chefes",
  "a line in the Officer tab goes to /o")
check(GC:Send("bora |cffff0000x|r", raidTeam) == true and #club.said == 1 and club.said[1].c == "C1"
  and club.said[1].s == "9" and club.said[1].text == "bora cffff0000xr",
  "one in a channel the guild made goes to that channel, cleaned like any other")
check(GC:Send("todos", streams[1]) == true and sent[#sent].chan == "GUILD", "and the Guild tab's to /g")
check(GC:Send("sumiu", { id = "99", kind = "other" }) == false and #club.said == 1,
  "a channel gone by the time Enter is pressed sends nothing")

-- ── A chat lockdown ─────────────────────────────────────────────────────
-- The club's lists and messages arrive secret: nothing is read, the feed keeps what it shows.
locked = true
local asked = #club.asked
check(GC:Entries() == nil and GC:Entries(officer) == nil and GC:Streams() == nil,
  "in a chat lockdown nothing is read: no lines, no channels, and not the local log either")
GC:Watch(true)
check(club.focused == "C1/7" and #club.asked == asked, "opening /g still focuses it, by the id already known, and asks nothing")
GC:Watch(false)
GC:Watch(true, officer)
check(club.focused == "C1/2", "and so does a named channel")
check(pcall(GuildOS.Compat.RequestOlderGuildChat, 10) and #club.asked == asked,
  "and asking the server for older lines, called directly, reads and asks nothing")
GC:Watch(false, officer)
ok, why = GC:Send("agora", raidTeam)
check(ok == false and why == "locked" and #club.said == 1, "a chat lockdown holds every channel's line")
locked = false

C_Club, GetClassInfo, issecretvalue, C_ChatInfo = nil, nil, nil, nil

-- ── Wired in ────────────────────────────────────────────────────────────
local function read(path) local f = assert(io.open(ADDON .. "/" .. path, "rb")); local t = f:read("*a"); f:close(); return t end
local toc = read("GuildOS.toc")
local at, ui = toc:find("Modules\\GuildChat.lua", 1, true), toc:find("UI\\CommunityPanel.lua", 1, true)
check(at and ui and at < ui, "the TOC loads the module, before the panel that shows it")
check(read("Core/Core.lua"):find('{ "GuildChat" }', 1, true), "and it starts with the others, for every player")

print(string.format("guild-chat: %d checks passed", checks))
