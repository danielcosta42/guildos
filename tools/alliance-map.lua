-- Allies on the world map, by zone (site spec 123, issue #449), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/GuildMap.lua and Modules/AllianceMap.lua under a stubbed client with a small fake Outland,
-- and a stubbed AllianceLink (its share, channel and guild naming are tools/alliance-link.lua's).
--
--   luajit -e 'ADDON="."' tools/alliance-map.lua
--
-- What it holds: the line (encoding, decoding, clamping, every malformed payload refused); sending gated by the
-- leader's switch (map.send), the player's privacy ("Share my position with the guild"), an instance (in combat or
-- not), the chat lockdown, a throttled channel or whisper queue, and the channel probe; the low pace (moving at
-- most every MOVE_MIN s, still every STILL_MAX s) and its cost over an hour; the retraction when sharing stops;
-- receiving gated by map.recv and "Show guildmates on my map", kept and drawn only in the receiver's own zone,
-- never our guild's, never a flood; and the guild's own map tables (and so the minimap) never holding an ally.
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
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-6) end

-- ── The client ──────────────────────────────────────────────────────────
strmatch = string.match
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterAllEvents() end
  function f:SetScript(_, fn) self.fn = fn end
  frames[#frames + 1] = f
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.5", "60000", "", 20505 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function UnitFullName() return "Me", "Realm" end
function IsInGuild() return true end
function GetNumGuildMembers() return 0 end
Enum = { SendAddonMessageResult = {} }
local clock = 1000
function GetTime() return clock end
function time() return 1790000000 + math.floor(clock) end
local tickers = {}
C_Timer = {
  After = function(_, fn) fn() end,
  NewTicker = function(d, fn) tickers[#tickers + 1] = { d = d, fn = fn }; return { Cancel = function() end } end,
}

-- A fake Outland: the continent 1945, the zones Shattrath 1955 and Terokkar 1952, a micro map 9999 in Shattrath.
local MAPS = {
  [946]  = { name = "Cosmic", mapType = 0, parentMapID = 0 },
  [1945] = { name = "Outland", mapType = 2, parentMapID = 946 },
  [1955] = { name = "Shattrath City", mapType = 3, parentMapID = 1945 },
  [1952] = { name = "Terokkar Forest", mapType = 3, parentMapID = 1945 },
  [9999] = { name = "Lower City", mapType = 5, parentMapID = 1955 },
}
local function vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
CreateVector2D = vec
local me = { map = 1955, x = 0.5, y = 0.5 }
local inInstance, combat, lockdown = false, false, false
function IsInInstance() return inInstance, inInstance and "raid" or "none" end
function GetInstanceInfo() return "Karazhan" end
function InCombatLockdown() return combat end
function UnitAffectingCombat() return combat end
function IsEncounterInProgress() return false end
C_Map = {
  GetBestMapForUnit = function(unit) if unit == "player" then return me.map end end,
  GetPlayerMapPosition = function(map, unit)
    if unit ~= "player" then return nil end
    if map == me.map then return vec(me.x, me.y) end
    if me.map == 9999 and map == 1955 then return vec(0.75 + me.x / 4, 0.75 + me.y / 4) end
  end,
  GetMapInfo = function(id) return MAPS[id] end,
}
-- What leaves on the channel: C_ChatInfo.SendAddonMessage (no ChatThrottleLib here), caught.
local out = {}
C_ChatInfo = {
  InChatMessagingLockdown = function() return lockdown end,
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, text, channel, target)
    out[#out + 1] = { prefix = prefix, text = text, channel = channel, target = target, t = clock }
    return true
  end,
}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/GuildMap.lua")
dofile(ADDON .. "/Modules/AllianceMap.lua")
GuildOS.db = { members = {} }
local GM, AM = GuildOS.GuildMap, GuildOS.AllianceMap

-- The alliance, stubbed: our guild "Guilda A" (code aaa), allies "Guilda B" (bbb) and "Guilda C" (ccc, blocked
-- here), the channel #5, and the leader's map switch.
local share = { send = true, recv = true }
local active, index, throttled = true, 5, false
GuildOS.Alliance = { MyGuildName = function() return "Guilda A" end,
  MemberInfo = function(_, name) if name == "Bia" then return { class = "WARRIOR", level = 70 } end end }
GuildOS.AllianceLink = {
  Active = function() return active end,
  Shares = function(_, item, dir) return item == "map" and share[dir] == true end,
  ChannelIndex = function() return active and index or nil end,
  ChannelName = function() return active and "GOSAPACTOabc123" or nil end,
  Throttled = function() return throttled end,
  Code = function(g) return ({ ["Guilda A"] = "aaa", ["Guilda B"] = "bbb", ["Guilda C"] = "ccc" })[g] end,
  IsMe = function(author) return author == "Me-Realm" end,
  Speaker = function(author) return (author:gsub("%-Realm$", "")) end,
  GuildOfLine = function(_, code, _, kind)
    check(kind ~= "A", "a map line is never named as a room line (our own guild would count)")
    if code == "bbb" then return "Guilda B" end
    return nil   -- ours (aaa), a blocked guild (ccc), an unknown one
  end,
}
AM:Initialize()
check(#tickers == 1 and tickers[1].d == AM.TICK, "one slow ticker drives the sending")
local recv
for _, f in ipairs(frames) do if f.events.CHAT_MSG_ADDON and f.fn and f ~= GM._openMapFrame then recv = f end end

local function reset()
  out, AM.sent, AM.allies = {}, nil, {}
  me.map, me.x, me.y = 1955, 0.5, 0.5
  inInstance, combat, lockdown, throttled, active = false, false, false, false, true
  share.send, share.recv = true, true
  GuildOS.db.guildMapPrefs = {}
end
-- Seconds pass, a Tick each TICK seconds, the player walking `step` of the map east each second.
local function run(seconds, step)
  for s = 1, seconds do
    clock = clock + 1
    me.x = math.min(1, me.x + (step or 0))
    if s % AM.TICK == 0 then AM:Tick(clock) end
  end
end
-- A line heard from the alliance channel, as the client hands it.
local function hear(sender, text, localID, name)
  recv.fn(recv, "CHAT_MSG_ADDON", AM.PREFIX, text, "CHANNEL", sender, name or "5. GOSAPACTOabc123", 0, localID or 5,
    name or "GOSAPACTOabc123", 0)
end

-- ── 1. The line ─────────────────────────────────────────────────────────
check(AM.Encode("bbb", { mapID = 1955, x = 0.25, y = 0.75 }) == "1,bbb,1955,2500,7499", "a position: zone, x, y")
check(AM.Encode("bbb", nil) == "1,bbb,-", "a retraction")
check(AM.Encode("bbb", { mapID = 1955, x = 2, y = -1 }) == "1,bbb,1955,9999,0", "coordinates clamped when sent")
check(AM.Encode("bb", { mapID = 1955, x = 0.1, y = 0.1 }) == nil and AM.Encode("bbb", { mapID = 0, x = 0.1, y = 0.1 }) == nil
  and AM.Encode("bbb", { mapID = 1955 }) == nil, "no line for a bad code, map or position")
local p = AM.Decode("1,bbb,1955,2500,7499")
check(p and p.code == "bbb" and p.mapID == 1955 and near(p.x, 2500 / 9999) and near(p.y, 7499 / 9999), "decoded back")
p = AM.Decode("1,bbb,1955,99999,0")
check(p and p.x == 1 and p.y == 0, "an x past the map is clamped on receipt")
local r = AM.Decode("1,bbb,-")
check(r and r.retract and r.code == "bbb", "a retraction decodes")
for _, bad in ipairs({ "", "1,bbb", "2,bbb,1955,1,1", "1,bbb,1955,1,1,1", "1,bb,1955,1,1", "1,bbb,0,1,1",
                       "1,bbb,99999999,1,1", "1,bbb,1955,-1,5", "1,bbb,1955,1.5,5", "1,bbb,1955,123456,5",
                       "1,b|b,1955,1,1", "1,bbb,1955,1,1\n", string.rep("1", 41), "1,bbb,1955,,", "1,bbb,-x" }) do
  check(AM.Decode(bad) == nil, "a malformed line is refused: " .. ("%q"):format(bad))
end
check(AM.Decode(nil) == nil and AM.Decode({}) == nil and AM.Decode(5) == nil, "and anything not a string")
check(#AM.Encode("bbb", { mapID = 1000000, x = 1, y = 1 }) <= AM.LINE_MAX, "the longest line fits LINE_MAX")
check(AM.GuildTag("Guilda B") == "GB" and AM.GuildTag("Ordem do Dragão") == "ODD" and AM.GuildTag("") == "?",
  "a pin's tag: the guild's initials")

-- ── 2. Sending: what gates it ───────────────────────────────────────────
reset()
AM:Tick(clock)
check(#out == 1 and out[1].prefix == AM.PREFIX and out[1].channel == "CHANNEL" and out[1].target == 5,
  "sharing on: the position goes on the alliance channel, as an addon message")
check(out[1].text == "1,aaa,1955,5000,5000", "with our guild's code, the zone and the coordinates only: " .. out[1].text)
reset()
share.send = false
run(120, 0.01)
check(#out == 0, "map.send off (the leader's switch): nothing goes")
reset()
GM:SetSharing(false)
run(120, 0.01)
check(#out == 0, "\"Share my position with the guild\" off: nothing goes")
reset()
inInstance = true
run(120, 0.01)
check(#out == 0, "in an instance: nothing goes")
combat = true
run(30)
check(#out == 0, "nor in combat in an instance")
reset()
combat = true
AM:Tick(clock)
check(#out == 1, "in combat in the open world the position still goes, as the guild's map")
reset()
lockdown = true
run(60, 0.01)
check(#out == 0, "a chat lockdown: nothing goes")
reset()
throttled = true
run(60, 0.01)
check(#out == 0, "the channel said \"throttled\" lately: nothing goes")
reset()
GuildOS.WhisperQueue = { INTERVAL = 4, Interval = function() return 8 end }
run(60, 0.01)
check(#out == 0, "the whisper queue is backing off after \"You are doing that too fast\": nothing goes")
GuildOS.WhisperQueue = nil
reset()
GuildOSDB = { probeChannel = { timer = false, click = true } }
run(60, 0.01)
check(#out == 0, "the channel probe measured a timer's addon message refused: nothing goes")
GuildOSDB = nil
reset()
active = false
run(60, 0.01)
check(#out == 0, "no alliance: nothing goes")
reset()
me.map = 9999
AM:Tick(clock)
check(#out == 1 and out[1].text:match("^1,aaa,1955,") , "inside a micro map: the zone's map and the place on it")

-- ── 3. The low pace ─────────────────────────────────────────────────────
reset()
run(600, 0.0005)   -- walking all along
local gaps, prev = {}, nil
for _, m in ipairs(out) do if prev then gaps[#gaps + 1] = m.t - prev end; prev = m.t end
local least = math.huge
for _, g in ipairs(gaps) do least = math.min(least, g) end
check(#out >= 600 / (AM.MOVE_MIN + AM.TICK) and least >= AM.MOVE_MIN,
  ("moving: a position every MOVE_MIN s at most (%d in 10 min, the closest %ds apart)"):format(#out, least))
reset()
AM:Tick(clock)
run(600)   -- standing still
check(#out == 1 + math.floor(600 / AM.STILL_MAX), ("still: one every STILL_MAX s (%d in 10 min)"):format(#out))
reset()
AM:Tick(clock)
me.map = 1952
run(AM.MOVE_MIN - AM.TICK)
check(#out == 1, "a new zone waits for MOVE_MIN too")
run(AM.TICK)
check(#out == 2 and out[2].text:match("^1,aaa,1952,"), "then goes, with the new zone")
-- The whole hour's cost, for one client walking: well under what the server lets an addon say on a channel.
reset()
run(3600, 0.0001)
local perMin = #out / 60
print(("alliance-map: one client wandering slowly for an hour: %d lines, %.1f a minute, %d bytes each at most"):format(#out, perMin,
  AM.LINE_MAX))
check(perMin <= 60 / AM.MOVE_MIN + 1e-9, "at most 4 lines a minute from any client")

-- ── 4. The retraction ───────────────────────────────────────────────────
reset()
AM:Tick(clock)
GM:SetSharing(false)
out = {}
AM:Tick(clock + 1)
check(#out == 1 and out[1].text == "1,aaa,-", "sharing turned off: one retraction on the channel")
AM:Tick(clock + 30)
check(#out == 1, "and nothing more")
reset()
AM:Tick(clock)
inInstance = true
out = {}
AM:Tick(clock + 1)
check(#out == 1 and out[1].text == "1,aaa,-", "entering an instance: one retraction")
reset()
AM:Tick(clock)
share.send = false
out = {}
AM:Tick(clock + 1)
check(#out == 1 and out[1].text == "1,aaa,-", "the leader turning the map off: one retraction")

-- ── 5. Receiving ────────────────────────────────────────────────────────
reset()
hear("Bia-Realm", "1,bbb,1955,2500,2500")
local allies = AM:GetAllies(clock)
check(#allies == 1 and allies[1].name == "Bia" and allies[1].guild == "Guilda B" and near(allies[1].x, 2500 / 9999)
  and allies[1].class == "WARRIOR" and allies[1].ally, "an ally in my zone: drawn, with the guild, class from the directory")
check(GM.peers["Bia-Realm"] == nil and next(GM.peers) == nil, "never in the guild's own map tables")
local drawnByGuild = 0
GM:ForEachLive(clock, function() drawnByGuild = drawnByGuild + 1 end)
check(drawnByGuild == 0 and #GM:GetPeers(clock) == 0,
  "so the guild's map and the MINIMAP (GuildMap:ForEachLive) never draw an ally")
reset()
hear("Bia-Realm", "1,bbb,9999,2500,2500")
check(#AM:GetAllies(clock) == 1, "an ally on a micro map of my zone: drawn (the zone is the same)")
reset()
hear("Bia-Realm", "1,bbb,1952,2500,2500")
check(#AM:GetAllies(clock) == 0 and next(AM.allies) == nil, "an ally in another zone: not kept at all")
reset()
hear("Bia-Realm", "1,bbb,1955,2500,2500")
me.map = 1952
check(#AM:GetAllies(clock) == 0, "I change zone: the ally of the old one is not drawn")
me.map = 1955
check(#AM:GetAllies(clock) == 1, "back: drawn again while fresh")
inInstance = true
check(#AM:GetAllies(clock) == 0, "in an instance: no ally drawn")
inInstance = false
reset()
share.recv = false
hear("Bia-Realm", "1,bbb,1955,2500,2500")
check(next(AM.allies) == nil, "map.recv off: nothing kept")
share.recv = true
hear("Bia-Realm", "1,bbb,1955,2500,2500")
share.recv = false
check(#AM:GetAllies(clock) == 0, "and nothing drawn once it goes off")
reset()
GM:SetShowingOthers(false)
hear("Bia-Realm", "1,bbb,1955,2500,2500")
check(next(AM.allies) == nil, "\"Show guildmates on my map\" off: nothing kept")
reset()
hear("Ana-Realm", "1,aaa,1955,2500,2500")
check(next(AM.allies) == nil, "a line with our own guild's code: not an ally (the guild's map has them)")
hear("Cid-Realm", "1,ccc,1955,2500,2500")
check(next(AM.allies) == nil, "a blocked or unknown guild: dropped")
hear("Me-Realm", "1,bbb,1955,2500,2500")
check(next(AM.allies) == nil, "our own echo: dropped")
hear("Bia-Realm", "1,bbb,1955,2500,2500", 7, "General")
check(next(AM.allies) == nil, "another channel: not ours")
recv.fn(recv, "CHAT_MSG_ADDON", AM.PREFIX, "1,bbb,1955,2500,2500", "GUILD", "Bia-Realm", "", 0, 0, "", 0)
check(next(AM.allies) == nil, "the prefix on GUILD: not the alliance's")
for _, bad in ipairs({ "1,bbb,1955,abc,1", "garbage", "1,bbb,1955,2500" }) do
  hear("Bia-Realm", bad)
end
check(next(AM.allies) == nil and AM.stats.dropped > 0, "malformed payloads: dropped")
reset()
hear("Bia-Realm", "1,bbb,1955,2500,2500")
clock = clock + 2
hear("Bia-Realm", "1,bbb,1955,9000,9000")
check(near(AM.allies["Bia-Realm"].x, 2500 / 9999), "a sender faster than SENDER_GAP: the extra line is dropped")
clock = clock + AM.SENDER_GAP
hear("Bia-Realm", "1,bbb,1955,9000,9000")
check(near(AM.allies["Bia-Realm"].x, 9000 / 9999), "at the pace: taken")
hear("Bia-Realm", "1,bbb,-")
check(AM.allies["Bia-Realm"] == nil, "a retraction removes the pin at once")
reset()
hear("Bia-Realm", "1,bbb,1955,2500,2500")
clock = clock + AM.FADE + 10
local a = AM:GetAllies(clock)[1]
check(a and a.alpha < 1 and a.alpha > 0, "a pin fades after FADE")
clock = clock + AM.GONE
AM:Tick(clock)
check(#AM:GetAllies(clock) == 0 and next(AM.allies) == nil, "and is gone after GONE")
reset()
for i = 1, AM.MAX_ALLIES + 20 do hear("Ally" .. i .. "-Realm", "1,bbb,1955,100,100") end
local n = 0
for _ in pairs(AM.allies) do n = n + 1 end
check(n == AM.MAX_ALLIES, "at most MAX_ALLIES allies kept")

print(("alliance-map: %d checks passed"):format(checks))
