-- The shared ChehulNet presence library (Modules/ChehulNet.lua, shipped identical in Lodestar's
-- Libs/ChehulNet.lua) on WoW: Forever and on Anniversary (issue #130), run against the real file
-- with a stubbed mesh and client.
--
-- On Forever UnitName("player") is the first name only while every addon-message sender is
-- "First Surname": v7 took its own HELLO for a peer's, and its alert allowlist ("chehul") never
-- matched the operator's "Chehul Costa". v8 knows itself by its full name and allows the
-- operator's characters by theirs.
--
--   luajit -e 'ADDON="."' tools/chehulnet.lua
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

local function stubFrame()
  local f = {}
  for _, m in ipairs({ "RegisterEvent", "SetScript", "Hide", "Show", "SetPoint", "SetSize" }) do f[m] = function() end end
  return f
end

--- A client of the given game, with the real library loaded over a stubbed mesh. `before` runs first
--- (to load an older copy, say). Returns the library and what it sent and showed.
local function client(game, before)
  _G.ChehulNet, _G.ChehulMesh = nil, nil
  local handlers, whispers, shown = {}, {}, {}
  _G.ChehulMesh = {
    Register = function(_, prefix, fn) handlers[prefix] = fn end,
    Whisper = function(_, prefix, msg, target) whispers[#whispers + 1] = { prefix = prefix, msg = msg, target = target } end,
    Guild = function() end, Group = function() end, Say = function() end, Realm = function() end, Yell = function() end,
  }
  function CreateFrame() return stubFrame() end
  C_Timer = { After = function() end, NewTicker = function() end }
  function GetTime() return 100 end
  function time() return 1790000000 end
  function UnitClass() return "Paladin", "PALADIN" end
  function UnitLevel() return 30 end
  function UnitExists() return false end
  function Ambiguate(name) return (name:gsub("%-.*$", "")) end
  strsplit = function(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return (table.unpack or unpack)(out)
  end
  GetBuildInfo, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = nil, nil, nil
  if game == "forever" then
    function UnitName() return "Chehul" end
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  elseif game == "retail" then
    -- The realm in UnitFullName's second slot, and a surname flag that must not be believed.
    function UnitName() return "Chehul" end
    function UnitFullName() return "Chehul", "Azralon" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
  else
    function UnitName() return "Chehul" end
    function UnitFullName() return "Chehul", "Nightslayer" end
    C_PlayerInfo = nil
  end
  if before then before() end
  dofile(ADDON .. "/Modules/ChehulNet.lua")
  local CN = _G.ChehulNet
  CN.ShowAlert = function(_, key, text) shown[#shown + 1] = { key = key, text = text } end
  CN:EnableAlerts({ store = function() return {} end, priority = 1 })
  return CN, handlers, whispers, shown
end

local function hello(from) return "CHN1|H|ls|DRUID|28|v=1.2.0,lvl=28|1453:12", from end

-- ── Forever ─────────────────────────────────────────────────────────────
local CN, on, whispers, shown = client("forever")
check(CN.version >= 8, "the library is v8 or later")
on.ChehulNet(hello("Chehul Costa-ClassicBetaPvE2"), "Chehul Costa-ClassicBetaPvE2", "GUILD")
check(CN.peers["Chehul Costa"] == nil and #whispers == 0,
  "Forever: its own HELLO, sent as First Surname, is not taken for a peer's, nor answered")
on.ChehulNet(hello("Ana Lima-ClassicBetaPvE2"), "Ana Lima-ClassicBetaPvE2", "GUILD")
check(CN.peers["Ana Lima"] ~= nil and #whispers == 0,
  "a guildmate's is a peer, and not answered: 500 clients would whisper each other after a restart")
on.ChehulNet(hello("Bia Rocha-ClassicBetaPvE2"), "Bia Rocha-ClassicBetaPvE2", "YELL")
on.ChehulNet(hello("Caio Nunes-ClassicBetaPvE2"), "Caio Nunes-ClassicBetaPvE2", "SAY")
check(CN.peers["Bia Rocha"] ~= nil and CN.peers["Caio Nunes"] ~= nil and #whispers == 0,
  "nor is one heard by yell or say")
on.ChehulNet(hello("Davi Melo-ClassicBetaPvE2"), "Davi Melo-ClassicBetaPvE2", "PARTY")
check(CN.peers["Davi Melo"] ~= nil and #whispers == 1 and whispers[1].target == "Davi Melo-ClassicBetaPvE2",
  "a groupmate's is answered at once: the audience is bounded")
on.ChehulNet(hello("Davi Melo-ClassicBetaPvE2"), "Davi Melo-ClassicBetaPvE2", "PARTY")
check(#whispers == 1, "and only the first time")
on.ChehulNet(hello("Elza Dias-ClassicBetaPvE2"), "Elza Dias-ClassicBetaPvE2", "RAID")
on.ChehulNet(hello("Fabi Reis-ClassicBetaPvE2"), "Fabi Reis-ClassicBetaPvE2", "INSTANCE_CHAT")
check(#whispers == 3, "a raid or an instance group too")
whispers[1], whispers[2], whispers[3] = nil, nil, nil
on.ChehulNet(hello("Gil Paz-ClassicBetaPvE2"), "Gil Paz-ClassicBetaPvE2", "WHISPER")
check(CN.peers["Gil Paz"] ~= nil and #whispers == 0, "a whispered HELLO is never answered: no ping-pong")

local function helloLevel(from, level) return "CHN1|H|ls|DRUID|" .. level .. "|v=1.2.0|1453:12", from end
on.ChehulNet(helloLevel("Hugo Luz", "28"), "Hugo Luz", "GUILD")
check(CN.peers["Hugo Luz"].level == 28, "a HELLO's level counts")
for i, bad in ipairs({ "inf", "nan", "-1", "0", "999", "1.5", "lixo", "" }) do
  local name = "Falso " .. i
  on.ChehulNet(helloLevel(name, bad), name, "GUILD")
  check(CN.peers[name] ~= nil and CN.peers[name].level == nil, "a level of '" .. bad .. "' does not, and the peer stays")
end
on.ChehulNet(hello("Chehul Druida"), "Chehul Druida", "GUILD")
check(CN.peers["Chehul Druida"] ~= nil, "another character of the same first name is somebody else")

on.ChehulAlert("ALERT|n1|Lodestar 2.3 is out", "Chehul Costa-ClassicBetaPvE2")
check(#shown == 1 and shown[1].text == "Lodestar 2.3 is out", "the operator's notice from Chehul Costa shows")
on.ChehulAlert("ALERT|n2|from the druid", "Chehul Druida")
on.ChehulAlert("ALERT|n3|from the shaman", "Chehul Shammy")
check(#shown == 3, "and from his other characters")
on.ChehulAlert("ALERT|n6|from Forever", "Chehul Lightdrizzle-ClassicBetaPvE2")
check(#shown == 4, "and from Chehul Lightdrizzle, his WoW: Forever character (v11, issue #276)")
on.ChehulAlert("ALERT|n4|free gold", "Chehul Impostor")
check(#shown == 4, "a stranger who took the first name Chehul shows nothing")

-- A v7 copy loaded first (an addon not yet updated) still ends up allowing the new names.
local v7 = function()
  _G.ChehulNet = { version = 7, ALERT_SENDERS = { ["chehul"] = true }, peers = {}, providers = {}, alertSeen = {} }
end
CN, on, whispers, shown = client("forever", v7)
on.ChehulAlert("ALERT|n5|after a v7", "Chehul Costa")
check(#shown == 1 and CN.ALERT_SENDERS["chehul costa"] and CN.ALERT_SENDERS["chehul"],
  "a v8 loaded after a v7 adds the operator's names to the list it found")

-- ── Anniversary ─────────────────────────────────────────────────────────
CN, on, whispers, shown = client("anniversary")
on.ChehulNet(hello("Chehul-Nightslayer"), "Chehul-Nightslayer", "GUILD")
check(CN.peers["Chehul"] == nil and #whispers == 0, "Anniversary: its own HELLO, by its one name, is still its own")
on.ChehulAlert("ALERT|a1|realm notice", "Chehul-Nightslayer")
check(#shown == 1, "and the operator's notice still shows")

-- ── Retail (v9, issue #184) ─────────────────────────────────────────────
CN, on, whispers = client("retail")
check(CN.version >= 9, "the library is v9 or later")
on.ChehulNet(hello("Chehul-Azralon"), "Chehul-Azralon", "GUILD")
check(CN.peers["Chehul"] == nil and CN.peers["Chehul Azralon"] == nil and #whispers == 0,
  "retail: its own HELLO is its own, the realm never read as a surname")
on.ChehulNet(hello("Ana-Azralon"), "Ana-Azralon", "GUILD")
check(CN.peers["Ana"] ~= nil and #whispers == 0, "a guildmate's is a peer, unanswered")
local v8 = function()
  _G.ChehulNet = { version = 8, ALERT_SENDERS = { ["chehul costa"] = true }, peers = {}, providers = {}, alertSeen = {} }
end
CN = client("retail", v8)
check(CN.version == 11, "a v11 loaded after a v8 (an addon not yet updated) takes over")
local v9 = function()
  _G.ChehulNet = { version = 9, ALERT_SENDERS = { ["chehul costa"] = true }, peers = {}, providers = {}, alertSeen = {} }
end
CN, on, whispers = client("forever", v9)
check(CN.version == 11, "and after a v9")
on.ChehulNet(hello("Ana Lima"), "Ana Lima", "GUILD")
check(CN.peers["Ana Lima"] ~= nil and #whispers == 0, "and its guild HELLOs go unanswered from then on")

-- ── DIAG (v11, issue #276): the backoffice asks a node for its health ───
CN, on, whispers = client("forever")
CN:RegisterDiag("gos", function() return "wsp=space;rounds=3" end)
_G.ChehulMesh.stats = { ok = 9, fail = 1, refused = 4, dirSent = 6 }
_G.ChehulMesh.dead, _G.ChehulMesh.dir = { YELL = "InvalidChatType", SAY = "InvalidChatType" }, { count = 17 }
on.ChehulPing("DIAG|d1|0", "Ana Lima", "WHISPER")
check(#whispers == 0, "a stranger's DIAG is not answered")
on.ChehulPing("DIAG|d1|0", "Chehul Costa-ClassicBetaPvE2", "WHISPER")
local diag = whispers[1] and whispers[1].msg or ""
check(#whispers == 1 and whispers[1].prefix == "ChehulPing" and diag:find("^DIAGR|d1|WHISPER|"),
  "the operator's DIAG is answered by whisper, with the bus it came on")
check(diag:find("cn=11;", 1, true) and diag:find("fail=1;", 1, true) and diag:find("gos.wsp=space;gos.rounds=3", 1, true),
  "the answer carries the lib version, the mesh's counters and what the host registered")
check(diag:find("dir=17", 1, true) and diag:find("dead=SAY+YELL", 1, true) and diag:find("refused=4", 1, true),
  "and the directory, the buses the game refuses and how many sends it refused (LibChehulMesh v5)")
on.ChehulPing("DIAG|d1|0", "Chehul Costa-ClassicBetaPvE2", "GUILD")
check(#whispers == 1, "one id is answered once, however many buses it came on")
on.ChehulPing("PING|p1|12.5", "Ana Lima", "GUILD")
check(#whispers == 2 and whispers[2].msg == "PONG|p1|12.5|GUILD", "PING still answers anybody")

print(string.format("chehulnet: %d checks passed", checks))
