-- The live guild map (issue #449, specs/salao/mapa.md), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua and Modules/GuildMap.lua, under a stubbed client with a small fake Outland, and the real
-- LibDeflate for the bytes on the wire.
--
--   luajit -e 'ADDON="."' tools/guild-map.lua
--
-- What it holds: the line's encoding and decoding; the watch protocol (nothing sent unwatched, a watch answered,
-- the fast and slow paces, the watch ending); the watcher's own pings; secret values, instances, combat and the
-- chat lockdown; privacy off; what arrives (GUILD only, the glide, the fade, the removal); the group read here;
-- pin placement between maps; the minimap's bearing; and THE BUDGET: 100 online guildmates, 3 watchers, under
-- BUDGET_MSGS messages a second for the whole guild, each under BUDGET_BYTES bytes on the wire.
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

-- The budget (specs/salao/mapa.md "Orçamento"), for 100 guildmates online and 3 with the map open, however
-- they are spread: every client's positions and pings together, in messages a second, averaged over 5 minutes.
local BUDGET_MSGS = 10
local BUDGET_PER_CLIENT = 0.5    -- messages a second from any one client
local BUDGET_BYTES = 40          -- one message on the wire, after compression and the channel's encoding

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-6) end

-- ── The client ──────────────────────────────────────────────────────────
strmatch = string.match
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:UnregisterAllEvents() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.5", "60000", "", 20505 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function UnitFullName() return "Me", "Realm" end
function IsInGuild() return true end
Enum = { SendAddonMessageResult = {} }
local clock = 1000
function GetTime() return clock end
function time() return 1790000000 + math.floor(clock) end

-- Timers run when the clock passes them.
local timers = {}
C_Timer = {
  After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end,
  NewTicker = function(d, fn) return { Cancel = function() end } end,
}
local function runTimers()
  local again = true
  while again do
    again = false
    for i, t in ipairs(timers) do
      if t.at <= clock then table.remove(timers, i); t.fn(); again = true; break end
    end
  end
end

-- The guild roster: me and five guildmates, all online.
local ROSTER = {
  { "Me", 70, "Shattrath City", "MAGE" }, { "Ann", 70, "Shattrath City", "PRIEST" },
  { "Bob", 68, "Terokkar Forest", "WARRIOR" }, { "Cat", 70, "Shattrath City", "DRUID" },
  { "Dee", 61, "Hellfire Peninsula", "ROGUE" }, { "Watcher", 70, "Shattrath City", "SHAMAN" },
}
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1], "Member", 1, r[2], r[4], r[3], "", "", true, 0, r[4] end
end

-- A fake Outland: the continent 1945 (worldX north from 5000 to -5000, worldY west from 5000 to -5000: 10 000
-- yards each way), Shattrath 1955 and Terokkar 1952 on it, a micro map 9999 inside Shattrath, the cosmic 946.
local MAPS = {
  [946]  = { name = "Cosmic", mapType = 0, parentMapID = 0 },
  [1945] = { name = "Outland", mapType = 2, parentMapID = 946 },
  [1955] = { name = "Shattrath City", mapType = 3, parentMapID = 1945 },
  [1952] = { name = "Terokkar Forest", mapType = 3, parentMapID = 1945 },
  [1944] = { name = "Hellfire Peninsula", mapType = 3, parentMapID = 1945 },
  [9999] = { name = "Lower City", mapType = 5, parentMapID = 1955 },
  [3457] = { name = "Karazhan", mapType = 4, parentMapID = 0 },
}
local RECTS = {   -- a map on its parent: minX, maxX, minY, maxY
  [1955] = { 0.40, 0.50, 0.60, 0.70 }, [1952] = { 0.35, 0.60, 0.60, 0.85 }, [1944] = { 0.55, 0.75, 0.30, 0.55 },
  [9999] = { 0.50, 1.00, 0.50, 1.00 },
}
local function onContinent(map, x, y)   -- a point of a zone (or the continent) as continent 0..1
  if map == 1945 then return x, y end
  local r = RECTS[map]
  if not r or MAPS[map].parentMapID ~= 1945 then return nil end
  return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3])
end
local function vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
CreateVector2D = vec
local me = { map = 1955, x = 0.5, y = 0.5 }
local secret, mapAbsent = false, false
local SECRET = setmetatable({}, { __index = function() error("a secret was read") end })
function issecretvalue(v) return v == SECRET end
C_Map = {
  GetBestMapForUnit = function(unit)
    if mapAbsent then return nil end
    if secret then return SECRET end
    if unit == "player" then return me.map end
    if unit == "party1" then return 1955 end
  end,
  GetPlayerMapPosition = function(map, unit)
    if secret then return SECRET end
    if unit == "player" and map == me.map then return vec(me.x, me.y) end
    if unit == "party1" and map == 1955 then return vec(0.25, 0.75) end
  end,
  GetMapInfo = function(id) return MAPS[id] end,
  GetMapRectOnMap = function(child, parent)
    local r = RECTS[child]
    if r and MAPS[child].parentMapID == parent then return r[1], r[2], r[3], r[4] end
  end,
  GetWorldPosFromMapPos = function(map, v)
    local cx, cy = onContinent(map, v.x, v.y)
    if not cx then return nil end
    return 530, vec(5000 - cy * 10000, 5000 - cx * 10000)
  end,
  GetMapPosFromWorldPos = function(cont, v, map)
    if cont ~= 530 then return nil end
    local cx, cy = (5000 - v.y) / 10000, (5000 - v.x) / 10000
    if map == 1945 then return map, vec(cx, cy) end
    local r = RECTS[map]
    if not r or MAPS[map].parentMapID ~= 1945 then return nil end
    return map, vec((cx - r[1]) / (r[2] - r[1]), (cy - r[3]) / (r[4] - r[3]))
  end,
}
local facing = 0
function GetPlayerFacing() return facing end
local inInstance, instanceName, combat, lockdown, encounter = false, nil, false, false, false
function IsInInstance() return inInstance, inInstance and "party" or "none" end
function GetInstanceInfo() return instanceName end
function InCombatLockdown() return combat end
function UnitAffectingCombat() return combat end
function IsEncounterInProgress() return encounter end
C_ChatInfo = { InChatMessagingLockdown = function() return lockdown end }
local groupN = 0
function GetNumGroupMembers() return groupN end
function IsInRaid() return false end
function UnitClass(unit) if unit == "party1" then return "Priest", "PRIEST" end end
local realUnitName = UnitName
function UnitName(unit) if unit == "party1" then return "Ann", nil end return realUnitName(unit) end

-- The real compression, for the bytes.
dofile(ADDON .. "/Libs/LibStub.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
local LD = LibStub("LibDeflate")
local function wireBytes(code, line)
  return #("S:" .. LD:EncodeForWoWAddonChannel(LD:CompressDeflate(code .. ":" .. line)))
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/GuildMap.lua")
local GM = GuildOS.GuildMap
GuildOS.db = { members = {} }

-- What leaves: CommSystem's SendMessage, caught.
local sent = {}
GuildOS.CommSystem = {
  MSG_TYPES = { MAP_POS = "MP", MAP_WATCH = "MW" },
  SendMessage = function(_, code, data, target, prio)
    sent[#sent + 1] = { code = code, data = data, target = target, prio = prio, t = clock }
  end,
}
local function count(code)
  local n = 0
  for _, m in ipairs(sent) do if m.code == code then n = n + 1 end end
  return n
end
local function last(code)
  for i = #sent, 1, -1 do if sent[i].code == code then return sent[i] end end
end
local function reset()
  sent = {}
  GM.watchers, GM.peers, GM.group, GM.watch, GM.sent = {}, {}, {}, {}, nil
  GM.openMapSeen = {}
  GM._pinged, GM._pingAt, GM._pingPending, GM._answerPending = nil, nil, nil, nil
  timers = {}
end
-- Seconds pass, a Tick each second, the player walking `step` of the map east each second.
local function run(seconds, step)
  for _ = 1, seconds do
    clock = clock + 1
    me.x = me.x + (step or 0)
    runTimers()
    GM:Tick()
  end
end
GM:Initialize()

-- ── 1. The wire ─────────────────────────────────────────────────────────
local line = GM:EncodePos({ mapID = 1955, x = 0.4512, y = 0.6234, facing = math.pi, flags = 0 })
check(line == "1955,4512,6233,32,0", "a position is a short line: map, x and y in 1/10000, facing in 1/64 turn, flags")
local p = GM:DecodePos(line)
check(p and p.mapID == 1955 and near(p.x, 0.4512, 1e-4) and near(p.y, 0.6233, 1e-4) and near(p.facing, math.pi, 0.1)
  and p.flags == 0, "and reads back")
check(GM:EncodePos({ mapID = 1955, x = 1.7, y = -2, flags = 1 }) == "1955,9999,0,,1", "coordinates are clamped to the map")
local inst = GM:EncodePos({ mapID = 3457, flags = GM.F_INSTANCE, inst = "Kara, zhan" .. string.rep("x", 60) })
check(not inst:find("%d+,%d") and #inst <= 60, "an instance's line has no coordinates, its name has no comma and is cut")
p = GM:DecodePos(inst)
check(p and p.flags == 2 and p.x == nil and p.inst and #p.inst <= GM.MAX_INST, "and reads back with no coordinates")
p = GM:DecodePos("3457,5000,5000,,2,Karazhan")
check(p and p.x == nil, "coordinates in an instance's line are thrown away")
check(GM:DecodePos("-").retract, "'-' is a retraction")
for _, bad in ipairs({ "", "x", "0,1,1,,0", "1955,1,1", "-5,1,1,,0", "1955,a,b,,0", "1955,1,1,,999", string.rep("9", 200) }) do
  check(GM:DecodePos(bad) == nil, "a malformed line is dropped: " .. bad:sub(1, 20))
end
check(GM:DecodePos(nil) == nil, "and nothing at all")
check(GM:EncodeWatch(1955) == "1955" and GM:EncodeWatch(1955, true) == "1955s" and GM:EncodeWatch(nil) == "0",
  "a watch is the map, 's' for the slow pace, 0 to stop")
local sc, slow = GM:DecodeWatch("1955s")
check(sc == 1955 and slow == true, "and reads back")
check(GM:DecodeWatch("nope") == nil and GM:DecodeWatch("1955x") == nil, "a malformed watch is dropped")
local posBytes = wireBytes("MP", "1955,4511,6233,32,0")
local instBytes = wireBytes("MP", GM:EncodePos({ mapID = 3457, flags = 2, inst = string.rep("Karazhan ", 6) }))
local watchBytes = wireBytes("MW", "1955s")
check(posBytes <= BUDGET_BYTES and instBytes <= BUDGET_BYTES + 20 and watchBytes <= 16,
  ("a message is tiny on the wire: position %d, instance %d, watch %d bytes"):format(posBytes, instBytes, watchBytes))
print(("guild-map: on the wire, a position is %d bytes, an instance line %d, a watch %d"):format(posBytes, instBytes, watchBytes))

-- ── 2. Nobody watches: nothing ──────────────────────────────────────────
reset()
run(120, 0.002)
check(count("MP") == 0, "nobody watching: no position goes, however the player moves")

-- One line on a zone change, cheap and throttled.
GM:OnZoneEvent()
run(3)
check(count("MP") == 1 and GM:DecodePos(last("MP").data).flags == GM.F_WHERE, "a zone change sends one 'where' line")
GM:OnZoneEvent(); run(3)
check(count("MP") == 1, "and a second within WHERE_GAP on the same map does not")

-- ── 3. A watch on my zone: the fast pace ────────────────────────────────
reset()
GM:HandleWatch("Watcher", "1955", "WHISPER")
check(next(GM.watchers) == nil, "a watch that did not come over GUILD is dropped")
GM:HandleWatch("Watcher", "1955", "GUILD")
run(2)
check(count("MP") == 1, "a new watch is answered within the jitter")
check(last("MP").prio == "NORMAL" and last("MP").target == nil, "over GUILD (no target), NORMAL priority")
local before = count("MP")
run(10, 0.003)
local moving = count("MP") - before
check(moving >= 4 and moving <= 5, "walking, a position every FAST_MIN (2) seconds (" .. moving .. " in 10 s)")
before = count("MP")
run(20, 0)
local still = count("MP") - before
check(still == 2, "standing still, one every FAST_MAX (10) seconds (" .. still .. " in 20 s)")
-- The watch is not renewed: 30 s after the last ping it ends.
run(15)
before = count("MP")
run(30, 0.003)
check(count("MP") == before, "a watch not renewed for WATCH_TTL seconds ends: nothing more goes")

-- Renewed, it keeps going; "0" stops it at once.
reset()
GM:HandleWatch("Watcher", "1955", "GUILD")
for _ = 1, 4 do run(20, 0.003); GM:HandleWatch("Watcher", "1955", "GUILD") end
check(count("MP") >= 30, "renewed every WATCH_PING seconds, the positions keep coming")
GM:HandleWatch("Watcher", "0", "GUILD")
before = count("MP")
run(20, 0.003)
check(count("MP") == before, "'MW:0' ends the watch at once")

-- ── 4. The slow pace and watches elsewhere ──────────────────────────────
reset()
GM:HandleWatch("Watcher", "1945", "GUILD")
run(2)
before = count("MP")
run(20, 0.003); GM:HandleWatch("Watcher", "1945", "GUILD"); run(20, 0.003)
local cont = count("MP") - before
check(cont >= 3 and cont <= 5, "a continent view: every SLOW_MIN (10) seconds while walking (" .. cont .. " in 40 s)")
reset()
GM:HandleWatch("Watcher", "1955s", "GUILD")
run(2); before = count("MP"); run(20, 0.003); GM:HandleWatch("Watcher", "1955s", "GUILD"); run(20, 0.003)
check(count("MP") - before <= 5, "the minimap's watch ('s') takes the slow pace too")
reset()
GM:HandleWatch("Watcher", "1952", "GUILD")
run(40, 0.003)
check(count("MP") == 0, "a watch on another zone owes this client nothing")
reset()
GM:HandleWatch("Watcher", "946", "GUILD")
run(3)
check(count("MP") == 1, "a world view (the cosmic map) covers every zone")

-- ── 5. This client watches ──────────────────────────────────────────────
reset()
GM:SetMinimapDots(false)
GM:SetWatch("worldmap", 1955)
check(count("MW") == 1 and last("MW").data == "1955", "opening the map sends the watch at once")
run(25)
check(count("MW") == 2, "and renews it every WATCH_PING seconds")
GM:SetWatch("worldmap", 1945)
GM:SetWatch("worldmap", 1952)
check(count("MW") == 3 and last("MW").data == "1945", "a new map renews it at once")
run(3)
check(count("MW") == 4 and last("MW").data == "1952", "and a second change within PING_GAP goes once, after it")
GM:SetWatch("worldmap", nil)
run(3)
check(last("MW").data == "0", "closing the map stops the watch")
before = count("MW"); run(60)
check(count("MW") == before, "and nothing more goes")
GM:SetMinimapDots(true)
run(3)
check(last("MW").data == "1955s", "the minimap watches its zone at the slow pace")
GM:SetWatch("worldmap", 1945)
run(3)
check(last("MW").data == "1945", "the world map's watch comes before the minimap's")
GM:SetWatch("worldmap", nil); run(3)
check(last("MW").data == "1955s", "and the minimap's is back when the map closes")

-- The minimap's own watch: only with a guildmate in the zone, never in an instance, never with the dots off.
reset()
GM:SetMinimapDots(true)
GM._roster = nil
run(2)
check(last("MW") and last("MW").data == "1955s", "minimap dots on, guildmates in my zone: the zone is watched")
GM:SetMinimapDots(false); run(3)
check(last("MW").data == "0", "dots off: the watch stops")
GM:SetMinimapDots(true)
inInstance, instanceName = true, "Karazhan"
run(3)
check(last("MW").data == "0", "in an instance: no minimap watch")
inInstance = false
for _, r in ipairs(ROSTER) do if r[1] ~= "Me" then r.saved, r[3] = r[3], "Nagrand" end end
GM._roster = nil; run(3)
check(last("MW").data == "0", "nobody of the guild in my zone: no minimap watch")
for _, r in ipairs(ROSTER) do if r.saved then r[3] = r.saved end end
GM._roster = nil
GM:SetMinimapDots(false)

-- ── 6. Secrets, instances, combat, the chat lockdown ────────────────────
local function watched(fn)
  reset()
  GM:HandleWatch("Watcher", "946", "GUILD")
  fn()
  run(15, 0.003)
  local out = {}
  for _, m in ipairs(sent) do if m.code == "MP" then out[#out + 1] = m.data end end
  return out
end
secret = true
check(#watched(function() end) == 0, "a secret map or position: nothing goes (and nothing secret is read)")
secret = false
mapAbsent = true
check(#watched(function() end) == 0, "no map at all: nothing goes")
mapAbsent = false
inInstance, instanceName = true, "Karazhan"
local lines = watched(function() end)
p = lines[1] and GM:DecodePos(lines[1])
check(#lines >= 1 and p.flags == GM.F_INSTANCE and p.x == nil and p.inst == "Karazhan" and not lines[1]:find(",%d+,%d+,"),
  "in an instance: only 'in an instance: <name>', never coordinates")
check(#lines <= 2, "and only when it changes or the heartbeat is due")
combat = true
check(#watched(function() end) == 0, "in an instance in combat: nothing at all")
combat, encounter = false, true
check(#watched(function() end) == 0, "during a boss: nothing at all")
encounter, inInstance = false, false
lockdown = true
check(#watched(function() end) == 0, "in a chat lockdown: nothing")
lockdown = false
combat = true
lines = watched(function() end)
check(#lines >= 1 and GM:DecodePos(lines[1]).flags == GM.F_COMBAT, "in combat in the open world: the position, flagged")
combat = false

-- ── 7. Privacy off ──────────────────────────────────────────────────────
reset()
check(GM:IsSharing(), "sharing my position is on by default")
GM:SetSharing(false)
check(count("MP") == 1 and last("MP").data == "-", "turning it off sends one retraction")
check(GuildOS.db.guildMapPrefs.share == false, "and is kept")
lines = watched(function() end)
check(#lines == 0, "off: nothing goes, even watched")
GM:OnZoneEvent(); run(5)
check(count("MP") == 0, "nor on a zone change")
GM:SetSharing(true)
check(count("MP") == 0, "turning it back on sends nothing by itself")

-- ── 8. What arrives ─────────────────────────────────────────────────────
reset()
GM:HandlePosition("Ann", "1955,2000,3000,,0", "WHISPER")
check(next(GM.peers) == nil, "a position that did not come over GUILD is dropped")
GM:HandlePosition("Ann", "garbage", "GUILD")
check(next(GM.peers) == nil, "a malformed one too")
GM:HandlePosition("Ann", "1955,2000,3000,,0", "GUILD")
local peers = GM:GetPeers()
check(#peers == 1 and peers[1].name == "Ann" and peers[1].class == "PRIEST" and peers[1].level == 70
  and peers[1].zone == "Shattrath City" and near(peers[1].x, 0.2, 1e-3), "a guildmate's position, class and level from the roster")
clock = clock + 2
GM:HandlePosition("Ann", "1955,4000,3000,,0", "GUILD")
clock = clock + 1
local mid = GM:GetPeers()[1]
check(mid.x > 0.2 and mid.x < 0.4, "the pin glides from the old spot to the new one (" .. mid.x .. ")")
clock = clock + 1.5
check(near(GM:GetPeers()[1].x, 0.4, 1e-3), "and arrives after the time between two updates")
clock = clock + GM.STALE_FADE
local faded = GM:GetPeers()[1]
check(faded.alpha < 1 and faded.alpha > 0.3, "a pin with no news for STALE_FADE seconds fades")
check(GM:_StaleAlpha(10) == 1 and near(GM:_StaleAlpha(120), 0.3) and GM:_StaleAlpha(121) == 0, "the fade's curve")
clock = clock + GM.STALE_GONE
check(#GM:GetPeers() == 0, "and is gone after STALE_GONE")
GM:_Prune(clock)
check(next(GM.peers) == nil, "and forgotten")
GM:HandlePosition("Bob", "1952,5000,5000,,0", "GUILD")
GM:HandlePosition("Bob", "-", "GUILD")
check(next(GM.peers) == nil, "a retraction removes the pin at once")
GM:HandlePosition("Dee", "3457,,,,2,Karazhan", "GUILD")
p = GM:GetPeers()[1]
check(p and p.inInstance and p.inst == "Karazhan" and p.x == nil, "a guildmate in an instance is listed with its name, not drawn")

-- ── 9. The group, read here ─────────────────────────────────────────────
reset()
groupN = 2
GM._groupAt = nil
peers = GM:GetPeers()
check(#peers == 1 and peers[1].isGroup and peers[1].name == "Ann" and near(peers[1].x, 0.25) and count("MP") == 0,
  "a guildmate in my party is drawn from this client's own read, nothing sent")
inInstance = true; GM._groupAt = nil
check(#GM:GetPeers() == 0, "not in an instance")
inInstance, groupN = false, 0; GM._groupAt = nil
GM:GetPeers()

-- ── 10. Placement between maps ──────────────────────────────────────────
local api = GuildOS.Compat
local x, y = GM:_PlaceOn(1955, 1955, 0.3, 0.4, api)
check(near(x, 0.3) and near(y, 0.4), "the same map: as is")
x, y = GM:_PlaceOn(1945, 1955, 0.5, 0.5, api)
check(near(x, 0.45) and near(y, 0.65), "a zone on its continent: through the map's rectangle")
x, y = GM:_PlaceOn(1952, 1955, 0.5, 0.5, api)
check(near(x, 0.4) and near(y, 0.2), "a neighbouring zone: through world yards")
x, y = GM:_PlaceOn(1945, 9999, 0.5, 0.5, api)
check(near(x, 0.4 + 0.75 * 0.1) and near(y, 0.6 + 0.75 * 0.1), "a micro map on the continent: up the parent chain")
check(GM:_PlaceOn(1944, 1955, 0.5, 0.5, api) == nil, "a point off the shown map is not drawn")
check(GM:_PlaceOn(1955, 3457, 0.5, 0.5, api) == nil, "an instance's map on a zone is not drawn")
local w, h = GM:_MapYards(1955, api)
check(near(w, 1000) and near(h, 1000), "Shattrath is 1000 yards each way")

-- ── 11. The minimap's bearing ───────────────────────────────────────────
local r = GM:_MinimapRadius(0, false)
check(near(r, 233.333, 0.01) and near(GM:_MinimapRadius(5, true), 25), "the minimap's radius in yards by zoom, outdoors and in")
local px, py, edge, yd = GM:_MinimapOffset(0, -50, 100, 70)
check(near(px, 0) and near(py, 35) and not edge and near(yd, 50), "50 yards north: straight up, half way out")
px, py = GM:_MinimapOffset(30, 0, 100, 70)
check(near(px, 21) and near(py, 0), "30 yards east: to the right")
px, py, edge = GM:_MinimapOffset(300, 400, 100, 70)
check(edge and near(math.sqrt(px * px + py * py), 70) and px > 0 and py < 0, "out of range: held at the edge, on its bearing")
px, py = GM:_MinimapOffset(-50, 0, 100, 70, math.pi / 2)
check(near(px, 0) and near(py, 35), "a rotating minimap, facing west: a guildmate to the west is straight ahead")
px, py = GM:_MinimapOffset(0, -50, 100, 70, math.pi / 2)
check(near(px, 35) and near(py, 0), "and one to the north is on the right")

-- ── 12. OpenMap's lines, read only (specs/salao/mapa.md "OpenMap") ───────
reset()
check(GM:DecodeOpenMap("L0").retract, "OpenMap's L0 is a retraction")
local om = GM:DecodeOpenMap("L1\t1955\t0.2500\t0.7500\tPRIEST\t70")
check(om and om.mapID == 1955 and near(om.x, 0.25) and near(om.y, 0.75), "OpenMap's L1: its map, x and y")
for _, bad in ipairs({ "L1\t1955\t1.5\t0.5\tMAGE\t70", "L1\t1955\t-0.1\t0.5", "L1\t0\t0.5\t0.5", "L1\t1955\tnan\t0.5",
    "L1\t1955\t0\t0", "L1\t1955\t0.5", "L1\t99999999\t0.5\t0.5", "H1\tv0.8.13\tForever", "V1\tx\ty",
    "L1\t1955\t1.2.3\t0.5", ("L1\t1955\t0.5\t0.5\t" .. string.rep("A", 120)), 42 }) do
  check(GM:DecodeOpenMap(bad) == nil, "a bad OpenMap line is dropped: " .. tostring(bad))
end
GM:HandleOpenMap("Ann", "L1\t1955\t0.2500\t0.7500\tMAGE\t1", "WHISPER")
check(next(GM.peers) == nil, "OpenMap's line only over GUILD")
GM:HandleOpenMap("Stranger", "L1\t1955\t0.25\t0.75", "GUILD")
check(next(GM.peers) == nil, "only from a guildmate on the roster")
GM:HandleOpenMap("Me", "L1\t1955\t0.25\t0.75", "GUILD")
check(next(GM.peers) == nil, "never this client's own")
GM:HandleOpenMap("Ann", "L1\t4242\t0.25\t0.75", "GUILD")
check(next(GM.peers) == nil, "nor on a map this client does not know")
GM:HandleOpenMap("Ann", "L1\t1955\t0.2500\t0.7500\tMAGE\t1", "GUILD")
p = GM:GetPeers()[1]
check(p and p.via == "openmap" and p.class == "PRIEST" and p.level == 70 and near(p.x, 0.25),
  "a guildmate with OpenMap shows, class and level from the roster (not the line's)")
check(count("MP") + count("MW") == 0, "reading OpenMap sends nothing")
clock = clock + 1
GM:HandleOpenMap("Ann", "L1\t1955\t0.9\t0.9", "GUILD")
check(near(GM.peers["Ann-Realm"].x, 0.25), "OpenMap lines faster than OPENMAP_GAP are dropped")
clock = clock + GM.STALE_FADE + 5
check(GM:GetPeers()[1].alpha == 1, "an OpenMap pin does not fade at Guild OS's pace (it sends a still place once a minute)")
clock = clock + (GM.OPENMAP_GONE - GM.STALE_FADE)
check(#GM:GetPeers() == 0, "and goes after OPENMAP_GONE")
GM:HandleOpenMap("Ann", "L1\t1955\t0.25\t0.75", "GUILD")
GM:HandleOpenMap("Ann", "L0", "GUILD")
check(next(GM.peers) == nil, "OpenMap's L0 removes its pin")
GM:HandlePosition("Bob", "1952,5000,5000,,0", "GUILD")
clock = clock + 3
GM:HandleOpenMap("Bob", "L1\t1952\t0.1\t0.1", "GUILD")
check(GM.peers["Bob-Realm"].via == nil and near(GM.peers["Bob-Realm"].x, 0.5, 1e-3), "a guildmate with both: Guild OS's own line wins")
GM:HandleOpenMap("Bob", "L0", "GUILD")
check(GM.peers["Bob-Realm"] ~= nil, "and OpenMap's L0 leaves Guild OS's pin alone")
clock = clock + GM.STALE_GONE + 1
GM:HandleOpenMap("Bob", "L1\t1952\t0.1\t0.1", "GUILD")
check(GM.peers["Bob-Realm"].via == "openmap", "once Guild OS's line is gone, OpenMap's shows")
clock = clock + 3
GM:HandlePosition("Bob", "1952,5000,5000,,0", "GUILD")
check(GM.peers["Bob-Realm"].via == nil, "and Guild OS's next line takes over again")
GM:HandleOpenMap("Cat", "L1\t1955\t0.3\t0.3", "GUILD")
local here, all = GM:_Crowd(1955, clock)
check(here == 0 and all == 1, "OpenMap's pins do not slow Guild OS's own pace (the crowd is Guild OS's senders)")

-- The roster's guildmates in the shown zone with no place known (OpenMap's zone badge, as the list's line).
reset()
local rosterOnly = GM:RosterOnlyHere(1955, {})
check(#rosterOnly == 3 and rosterOnly[1] == "Ann" and rosterOnly[2] == "Cat" and rosterOnly[3] == "Watcher",
  "online in Shattrath by the roster, sorted, never me")
check(#GM:RosterOnlyHere(1955, { ["Ann-Realm"] = true }) == 2, "minus those drawn")
check(#GM:RosterOnlyHere(9999, {}) == 3, "a micro map inside the zone counts as the zone")
check(#GM:RosterOnlyHere(1945, {}) == 0, "a continent has no roster line (the roster names zones)")

-- Coordination: while OpenMap's map draws guildmates, Guild OS draws no pin or dot for those it draws (its own
-- OpenMap-heard guildmates within OPENMAP_GONE; the group while its party dots are on) and lists everybody.
local loaded = {}
C_AddOns = { IsAddOnLoaded = function(n) return loaded[n] or false, loaded[n] or false end }
local function drawn()
  local out = {}
  GM:ForEachLive(clock, function(q) out[#out + 1] = q.key end)
  table.sort(out)
  return table.concat(out, ",")
end
local function listed()
  local out = {}
  for _, q in ipairs(GM:GetPeers()) do out[#out + 1] = q.key .. (q.onOpenMap and "*" or "") end
  return table.concat(out, ",")
end
local function recheck() GM:RefreshOpenMap(clock) end
GuildOSDB = { openMapNotice = { ["Me-Realm"] = "never" } }
GM:Initialize()
check(GuildOSDB.openMapNotice == nil and GM.CheckOpenMap == nil and GM.OpenMapListLine == nil,
  "the OpenMap notice is gone (and the test builds' answer with it)")
reset()
GM:HandlePosition("Bob", "1952,5000,5000,,0", "GUILD")          -- Guild OS only
GM:HandleOpenMap("Cat", "L1\t1955\t0.3\t0.3", "GUILD")          -- OpenMap only
GM:HandlePosition("Dee", "1952,2000,2000,,0", "GUILD")           -- both
GM:HandleOpenMap("Dee", "L1\t1952\t0.2\t0.2", "GUILD")
check(GM.peers["Dee-Realm"].via == nil and GM.openMapSeen["Dee-Realm"] == clock,
  "a guildmate with both: Guild OS's line kept, OpenMap's remembered")
groupN = 2; GM._groupAt = nil                                    -- Ann, in my party
recheck()
check(GM:OpenMapState() == nil and drawn() == "Ann-Realm,Bob-Realm,Cat-Realm,Dee-Realm",
  "no OpenMap: Guild OS draws everybody")
loaded.OpenMap = true
OpenMapDB = { worldmap = { enabled = true, guild = false, group = true } }
recheck()
check(drawn() == "Ann-Realm,Bob-Realm,Cat-Realm,Dee-Realm", "OpenMap with its guild members off: Guild OS draws everybody")
OpenMapDB.worldmap.guild = true
check(drawn() == "Ann-Realm,Bob-Realm,Cat-Realm,Dee-Realm", "OpenMap's settings are not read per frame")
clock = clock + GM.OPENMAP_RECHECK
check(drawn() == "Bob-Realm", "read again within OPENMAP_RECHECK: only who shares through Guild OS alone is drawn")
check(listed() == "Ann-Realm*,Bob-Realm,Cat-Realm*,Dee-Realm*", "and the list still names everybody, marked")
OpenMapDB.worldmap.group = false
recheck()
check(drawn() == "Ann-Realm,Bob-Realm", "OpenMap's party dots off: the group is Guild OS's to draw")
OpenMapDB.worldmap.group = true
GM:HandleOpenMap("Dee", "L0", "GUILD")
recheck()
check(drawn() == "Bob-Realm,Dee-Realm" and GM.peers["Dee-Realm"].via == nil,
  "OpenMap's L0: it no longer draws them, Guild OS does")
clock = clock + 10
GM:HandleOpenMap("Dee", "L1\t1952\t0.2\t0.2", "GUILD")
clock = clock + GM.OPENMAP_GONE + 1
GM:HandlePosition("Dee", "1952,2000,2000,,0", "GUILD")
GM:HandlePosition("Bob", "1952,5000,5000,,0", "GUILD")
GM:_Prune(clock)
check(drawn() == "Bob-Realm,Dee-Realm" and GM.openMapSeen["Dee-Realm"] == nil,
  "OpenMap silent past OPENMAP_GONE (its own lifetime): Guild OS draws them again")
OpenMapDB = { worldmap = { enabled = false, guild = true, group = true } }
recheck()
check(drawn() == "Ann-Realm,Bob-Realm,Dee-Realm", "OpenMap's map off: it draws nobody, Guild OS draws everybody")
OpenMapDB = nil
check(GM:OpenMapState().guild and GM:OpenMapState().group, "an unknown OpenMap save reads as its defaults")
loaded.OpenMap, OpenMapDB, C_AddOns, GuildOSDB = nil, nil, nil, nil
groupN = 0; GM._groupAt = nil
recheck()
reset()

-- ── 13. The budget: 100 online, 3 watchers ──────────────────────────────
-- Every peer runs the module's own decision (GM:_Owe) each half second over five minutes; the watchers renew
-- every WATCH_PING. A peer walking moves 7 yards a second on a 1000-yard zone.
local ZONES = {}
for i = 1, 20 do ZONES[i] = 5000 + i end
local function chainOf(z) return { [z] = 3, [1945] = 2, [946] = 0 } end
local function simulate(spread, watchScopes, movingShare, seconds)
  math.randomseed(42)
  local peersSim = {}
  for i = 1, 100 do
    peersSim[i] = { zone = spread and ZONES[(i - 1) % #ZONES + 1] or ZONES[1], x = math.random(), y = math.random(),
      moving = math.random() < movingShare, sends = 0, gaps = 0 }
  end
  local watchers = {}
  local msgs, t, step, heard = 0, 0, 0.5, {}
  local nextPing = 0
  while t < seconds do
    if t >= nextPing then
      for i, s in ipairs(watchScopes) do watchers["W" .. i] = { scope = s.scope, slow = s.slow, untilT = t + GM.WATCH_TTL } end
      msgs = msgs + #watchScopes
      nextPing = t + GM.WATCH_PING
    end
    local onMap, all = {}, 0
    for _, h in pairs(heard) do
      if t - h.t <= 30 then all = all + 1; onMap[h.zone] = (onMap[h.zone] or 0) + 1 end
    end
    for i, ps in ipairs(peersSim) do
      if ps.moving then ps.x = (ps.x + 0.007 * step) % 1 end
      local pos = { mapID = ps.zone, x = ps.x, y = ps.y, flags = 0 }
      local owe, tier = GM:_Owe(ps.last, pos, t, chainOf(ps.zone), watchers, onMap[ps.zone] or 0, all)
      if owe then
        if tier == "fast" and ps.last and ps.moving then ps.gaps = math.max(ps.gaps, t - ps.last.t) end
        ps.last = { t = t, mapID = pos.mapID, x = pos.x, y = pos.y, flags = 0 }
        ps.sends = ps.sends + 1
        msgs = msgs + 1
        heard[i] = { t = t, zone = ps.zone }
      end
    end
    t = t + step
  end
  local worst, gap = 0, 0
  for _, ps in ipairs(peersSim) do worst = math.max(worst, ps.sends / seconds); gap = math.max(gap, ps.gaps) end
  return msgs / seconds, worst, gap
end
local SIM = 300
local cases = {
  { "spread over 20 zones, 3 watchers on 3 zones", true, { { scope = ZONES[1] }, { scope = ZONES[2] }, { scope = ZONES[3] } } },
  { "all in one zone, 3 watchers on it", false, { { scope = ZONES[1] }, { scope = ZONES[1] }, { scope = ZONES[1] } } },
  { "spread, 1 watcher on the continent, 2 on zones", true, { { scope = 1945 }, { scope = ZONES[1] }, { scope = ZONES[2] } } },
  { "spread, 3 watchers on the world view", true, { { scope = 946 }, { scope = 946 }, { scope = 946 } } },
  { "spread, 3 minimap watchers", true, { { scope = ZONES[1], slow = true }, { scope = ZONES[2], slow = true }, { scope = ZONES[3], slow = true } } },
}
for _, c in ipairs(cases) do
  local rate, worst, gap = simulate(c[2], c[3], 0.6, SIM)
  print(("guild-map: budget, %s: %.2f msg/s guild-wide, %.2f msg/s from the busiest client"):format(c[1], rate, worst))
  check(rate <= BUDGET_MSGS, ("%s: %.2f msg/s stays under %d"):format(c[1], rate, BUDGET_MSGS))
  check(worst <= BUDGET_PER_CLIENT + 1e-9, ("%s: no client sends more than %.1f msg/s"):format(c[1], BUDGET_PER_CLIENT))
  if c[1]:find("^spread over") then
    check(gap <= GM.FAST_MAX + 0.5, "and a watched guildmate walking is never more than FAST_MAX seconds stale")
  end
end
local quiet = simulate(true, {}, 0.6, SIM)
check(quiet == 0, "nobody watching: the guild sends nothing")

-- OpenMap's way, for comparison: everybody who shares sends always, every 10 s moving and 60 s still (its
-- SEND_EVERY / STILL_EVERY), watched or not. Cheap per client, but the guild's cost grows with who is online and
-- never stops: why Guild OS keeps sending only to watchers.
local function alwaysOn(online, movingShare)
  return online * (movingShare / 10 + (1 - movingShare) / 60), 1 / 10
end
for _, n in ipairs({ 100, 200 }) do
  local rate, per = alwaysOn(n, 0.6)
  print(("guild-map: OpenMap's always-on cadence, %d sharing: %.2f msg/s guild-wide (nobody looking too), %.2f per client")
    :format(n, rate, per))
end
check(alwaysOn(100, 0.6) > quiet and alwaysOn(200, 0.6) > BUDGET_MSGS,
  "always sending would cost the guild even with nobody looking, and pass the budget at 200 online")
print(("guild-map: the guild's received bytes at the budget: %d B/s"):format(BUDGET_MSGS * posBytes))

print(("guild-map: %d checks passed"):format(checks))
