-- LibChehulMesh v5 (issue #276), the real file under a stubbed client: on WoW: Forever the game refuses SAY and
-- YELL addon messages (InvalidChatType, measured by the CehulNet backoffice, build 1.60.1.70862), and the realm
-- bus has to go by whisper to the members of a hidden channel's list. On TBC Anniversary YELL lives and nothing
-- changes.
--
--   luajit -e 'ADDON="."' tools/chehulmesh.lua
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

math.randomseed(7)
local now, timers = 0, {}
local function advance(s)
  local target = now + s
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > target then break end
    table.remove(timers, 1)
    now = t.at
    if not t.dead then t.fn() end
  end
  now = target
end

--- A client of `game` ("forever" or "anniversary") with the real library loaded. `before` runs first (an older
--- copy left by an addon not yet updated). Returns the library and what it sent, raw and through AceComm.
local function client(game, before)
  now, timers = 0, {}
  _G.ChehulMesh = nil
  local w = { raw = {}, comm = {}, joined = {}, selected = {}, filters = {}, events = {} }
  w.results = game == "forever" and { SAY = 4, YELL = 4 } or { SAY = 0, YELL = 0 }
  w.instance, w.lockdown, w.channelId = false, false, 0
  w.display = { { "General", false }, { "Channels", true }, { "ChehulNetH", false } }
  w.roster = {}

  function time() return 1790000000 + math.floor(now) end
  C_Timer = {
    After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end,
    NewTicker = function(d, fn)
      local t = { Cancel = function(self) self.dead = true end }
      local function tick() if t.dead then return end fn(); timers[#timers + 1] = { at = now + d, fn = tick } end
      timers[#timers + 1] = { at = now + d, fn = tick }
      return t
    end,
  }
  function CreateFrame()
    local f = { scripts = {} }
    function f:RegisterEvent(e) w.events[e] = self end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:UnregisterAllEvents() end
    return f
  end
  Enum = { SendAddonMessageResult = { Success = 0, InvalidChatType = 4, AddOnMessageLockdown = 11 } }
  C_ChatInfo = {
    SendAddonMessage = function(prefix, payload, dist, target)
      w.raw[#w.raw + 1] = { prefix = prefix, payload = payload, dist = dist, target = target }
      return w.results[dist] or 0
    end,
    InChatMessagingLockdown = function() return w.lockdown end,
    GetChannelRosterInfo = function(_, i) local r = w.roster[i]; return r[1], false, false, r[2] end,
  }
  local AceComm = {
    RegisterComm = function() end,
    SendCommMessage = function(_, prefix, payload, dist, target)
      w.comm[#w.comm + 1] = { prefix = prefix, payload = payload, dist = dist, target = target }
    end,
  }
  function LibStub(name) if name == "AceComm-3.0" then return AceComm end end
  function IsInInstance() return w.instance end
  function UnitIsGhost() return false end
  function IsInGuild() return true end
  function IsInGroup() return false end
  function IsInRaid() return false end
  function UnitFactionGroup() return "Horde" end
  function UnitGUID() return "Player-1-SELF" end
  function JoinTemporaryChannel(name, password) w.joined[#w.joined + 1] = { name = name, password = password }; w.channelId = 6 end
  function GetChannelName() return w.channelId end
  function GetNumDisplayChannels() return #w.display end
  function GetChannelDisplayInfo(i) return w.display[i][1], w.display[i][2] end
  function SetSelectedDisplayChannel(i) w.selected[#w.selected + 1] = i end
  function ChatFrame_AddMessageEventFilter(event, fn) w.filters[event] = fn end
  ChatFrameUtil, ChannelFrame, issecretvalue, InCombatLockdown = nil, nil, nil, nil

  if before then before() end
  dofile(ADDON .. "/Libs/LibChehulMesh.lua")
  local M = _G.ChehulMesh
  M.YELL_PERCENT = 100 -- every flush flushes: the share is a load knob, not what is tested here
  w.fire = function(event, ...) local f = w.events[event]; f.scripts.OnEvent(f, event, ...) end
  return M, w
end

local function count(list, field, value)
  local n = 0
  for _, m in ipairs(list) do if m[field] == value then n = n + 1 end end
  return n
end

-- ── WoW: Forever ────────────────────────────────────────────────────────
local M, w = client("forever")
check(M.version >= 5, "the library is v5 or later")
check(M:Proximity("ChehulNet", "hello") == false and M.dead.SAY == "InvalidChatType",
  "the first SAY goes raw, and the game's InvalidChatType marks the bus dead")
check(#w.raw == 1 and w.raw[1].dist == "SAY" and #w.comm == 0, "it went raw, not through AceComm, which reads no result")
check(M:Proximity("ChehulNet", "hello") == false and #w.raw == 1 and M.stats.refused == 2,
  "a dead bus sends nothing more this session, and counts the refusal")
check(#w.joined == 0, "a dead SAY alone joins no directory")

M:Realm("ChehulRecruit", "CRB|beacon", "ChehulRecruit:beacon")
M.FlushRealm()
check(M.dead.YELL == "InvalidChatType" and not M.CanYell(), "the realm flush's first YELL finds it dead too")
check(#w.joined == 1 and w.joined[1].name == "ChehulNetH" and w.joined[1].password == M.DIR_PASSWORD,
  "and that joins the directory: one passworded channel per faction")
check(count(w.comm, "dist", "WHISPER") == 0 and M.stats.realmSent == 0, "with nobody listed yet, the item goes nowhere")

local hide = w.filters.CHAT_MSG_CHANNEL_NOTICE
check(hide and hide(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "6. ChehulNetH", "", "", 0, 6, "ChehulNetH") == true,
  "the directory's join line is hidden from the chat windows")
check(hide(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "1. General", "", "", 1, 1, "General") == false,
  "and no other channel's")

advance(15)
check(w.selected[1] == 1 and w.selected[2] == 3, "the list is asked for by selecting another channel first, then ours")
w.roster = { { "Chehul Costa", "Player-1-SELF" }, { "Ana Lima-Realm8PvP", "Player-8-A" }, { "Bia Rocha", "Player-2-B" },
  { "Caio Nunes", "Player-3-C" } }
w.fire("CHANNEL_ROSTER_UPDATE", 1, 9)
check(M.dir.count == 0, "another channel's list is not ours")
w.fire("CHANNEL_ROSTER_UPDATE", 3, 4)
check(M.dir.count == 3 and M.dir.names[1] == "Ana Lima", "ours: everyone but me (by GUID), as whispers reach them on Forever")

local before = #w.comm
M:Realm("LSRace", "R1|R|record", "LSRace:R")
M.FlushRealm()
local sent, targets = {}, {}
for i = before + 1, #w.comm do
  local m = w.comm[i]
  if m.dist == "WHISPER" then sent[#sent + 1] = m; targets[m.target] = true end
end
local distinct = 0
for _ in pairs(targets) do distinct = distinct + 1 end
check(#sent == M.REALM_FANOUT and distinct == M.REALM_FANOUT and sent[1].payload == "R1|R|record",
  "a realm item goes by whisper to REALM_FANOUT distinct directory members")
check(count(w.raw, "dist", "YELL") == 1 and M.stats.dirSent == M.REALM_FANOUT, "and never again by YELL")

before = #w.comm
w.instance = true
M:Realm("LSRace", "R1|R|in an instance", "LSRace:R")
M.FlushRealm()
check(#w.comm == before, "nothing goes from inside an instance: a whisper there counts against the prefix throttle")
w.instance, w.lockdown = false, true
M.FlushRealm()
check(#w.comm == before, "nor in a chat lockdown")
w.lockdown = false
M.FlushRealm()
check(#w.comm == before + M.REALM_FANOUT, "the queued item goes once both lift")
check(M:HealthLine():find("dead SAY,YELL", 1, true) and M:HealthLine():find("dir 3", 1, true),
  "the health line names the dead buses and the directory's size")

advance(M.DIR_REFRESH)
check(#w.selected >= 4, "the list is read again every DIR_REFRESH seconds")
check(M.DIR_REFRESH <= 120, "and often enough that a member who logged off does not linger (v6, issue #278)")

-- ── v6 (issue #278): a member who logged off answers "No player named" ──
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
local notFound = w.filters.CHAT_MSG_SYSTEM
check(notFound ~= nil, "the directory watches the system lines for its own whispers' not-found answers")
w.fire("CHANNEL_ROSTER_UPDATE", 3, 4)
for _ = 1, 3 do M:Realm("LSRace", "R1|R|again", "LSRace:R"); M.FlushRealm() end -- every member gets tried
check(notFound(nil, "CHAT_MSG_SYSTEM", "No player named 'Bia Rocha' is currently playing.") == true,
  "the line for a member the directory whispered is hidden from the chat windows")
check(notFound(nil, "CHAT_MSG_SYSTEM", "No player named 'Bia Rocha' is currently playing.") == true,
  "in every window that runs the filter, not just the first")
local left = {}
for _, n in ipairs(M.dir.names) do left[n] = true end
check(not left["Bia Rocha"] and M.dir.count == 2, "and the member leaves the list at once")
check(notFound(nil, "CHAT_MSG_SYSTEM", "No player named 'Zeca Strange' is currently playing.") == false,
  "a line for a name the directory never whispered passes untouched")
before = #w.comm
for _ = 1, 6 do M:Realm("LSRace", "R1|R|more " .. _, "LSRace:R" .. _); M.FlushRealm() end
local toBia = 0
for i = before + 1, #w.comm do if w.comm[i].target == "Bia Rocha" then toBia = toBia + 1 end end
check(toBia == 0, "nor is whispered again")
w.fire("CHANNEL_ROSTER_UPDATE", 3, 4)
left = {}
for _, n in ipairs(M.dir.names) do left[n] = true end
check(not left["Bia Rocha"] and left["Caio Nunes"], "a fresh read keeps it out while BAD_SECONDS last")
-- Ana came as "Ana Lima-Realm8PvP": the plain spelling failing earns one try in the roster's own.
check(notFound(nil, "CHAT_MSG_SYSTEM", "No player named 'Ana Lima' is currently playing.") == true,
  "the plain spelling's not-found line is hidden too")
notFound(nil, "CHAT_MSG_SYSTEM", "No player named 'Ana Lima' is currently playing.") -- a second chat window
local tries = 0
for _, n in ipairs(M.dir.names) do
  left[n] = true
  if n == "Ana Lima-Realm8PvP" then tries = tries + 1 end
end
check(tries == 1, "a plain spelling that found nobody gets one try in the roster's spelling, once per window set")
w.fire("CHANNEL_ROSTER_UPDATE", 3, 4)
left = {}
for _, n in ipairs(M.dir.names) do left[n] = true end
check(left["Ana Lima-Realm8PvP"] and not left["Ana Lima"], "and a fresh read keeps that spelling")
now = now + M.BAD_SECONDS + 1
w.fire("CHANNEL_ROSTER_UPDATE", 3, 4)
left = {}
for _, n in ipairs(M.dir.names) do left[n] = true end
check(left["Bia Rocha"] and left["Ana Lima"], "after BAD_SECONDS a name is tried again")

-- ── TBC Anniversary: YELL lives ─────────────────────────────────────────
M, w = client("anniversary")
check(M:Yell("ChehulNet", "hello") == true and M.probed.YELL and not M.dead.YELL, "the first YELL goes raw and the game takes it")
check(M:Yell("ChehulNet", "hello again") == true and #w.raw == 1 and count(w.comm, "dist", "YELL") == 1,
  "then YELL goes through AceComm as it always did")
M:Realm("LSRace", "R1|R|record", "LSRace:R")
M.FlushRealm()
check(count(w.comm, "dist", "YELL") == 2 and count(w.comm, "dist", "WHISPER") == 0 and #w.joined == 0,
  "the realm bus stays YELL, and no directory is joined")

-- ── A v4 copy loaded first keeps its handlers ───────────────────────────
local handled
M, w = client("forever", function()
  _G.ChehulMesh = { version = 4, handlers = { ChehulNet = function() handled = true end }, _realmQueue = {},
    stats = { ok = 3, fail = 0, recv = 1, yell = 0, realmQueued = 0, realmSent = 0, realmDropped = 0 } }
end)
check(M.version >= 5 and M.handlers.ChehulNet and M.stats.ok == 3 and M.stats.refused == 0,
  "a v5+ loaded after a v4 takes over with the handlers and counters it found")

print(string.format("chehulmesh: %d checks passed", checks))
