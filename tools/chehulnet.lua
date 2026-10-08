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
  if game == "forever" then
    function UnitName() return "Chehul" end
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
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
check(CN.peers["Ana Lima"] ~= nil and #whispers == 1 and whispers[1].target == "Ana Lima-ClassicBetaPvE2",
  "a guildmate's is, and answered once")
on.ChehulNet(hello("Chehul Druida"), "Chehul Druida", "GUILD")
check(CN.peers["Chehul Druida"] ~= nil, "another character of the same first name is somebody else")

on.ChehulAlert("ALERT|n1|Lodestar 2.3 is out", "Chehul Costa-ClassicBetaPvE2")
check(#shown == 1 and shown[1].text == "Lodestar 2.3 is out", "the operator's notice from Chehul Costa shows")
on.ChehulAlert("ALERT|n2|from the druid", "Chehul Druida")
on.ChehulAlert("ALERT|n3|from the shaman", "Chehul Shammy")
check(#shown == 3, "and from his other characters")
on.ChehulAlert("ALERT|n4|free gold", "Chehul Impostor")
check(#shown == 3, "a stranger who took the first name Chehul shows nothing")

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

print(string.format("chehulnet: %d checks passed", checks))
