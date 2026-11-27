----------------------------------------------------------------------
-- Guild OS - Live Guild Map (data + sync layer; issue #449, specs/salao/mapa.md)
--
-- Where each guildmate really is, in real time, while somebody looks:
--   * A client that has the world map open (or minimap dots with a guildmate in its zone) WATCHES: it
--     sends "MW:<map>" over GUILD, again every WATCH_PING seconds, and "MW:0" when it stops.
--   * A client that is being watched (its own map is the watched map or under it) SENDS its position,
--     "MP:<map>,<x>,<y>,<facing>,<flags>[,<instance>]", over GUILD: every FAST_MIN s while it moves,
--     at least every FAST_MAX s; on a continent or world view, or for the minimap, the slow pace. A watch
--     not renewed for WATCH_TTL seconds ends. Nobody watching: nothing, except one line on a zone change.
--   * Party and raid members are read on this client, never sent.
--
-- Security (as LFGBoard / RECRUIT_STATS): identity is the envelope sender, never the payload; GUILD only;
-- every number is clamped; class and level come from the roster. Privacy: "Share my position with the guild"
-- (on unless turned off); off, this client never sends a position. Nothing is sent in an instance in
-- combat or during a boss, in a chat lockdown, or when the client keeps the position secret; in an
-- instance only its name goes, never coordinates.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local GuildMap = {}
GuildOS.GuildMap = GuildMap

-- The protocol's numbers (specs/salao/mapa.md, tools/guild-map.lua holds them to the budget).
GuildMap.WATCH_PING  = 20     -- a watcher renews its watch this often
GuildMap.WATCH_TTL   = 30     -- a watch not renewed this long ends
GuildMap.FAST_MIN    = 2      -- watched on its own zone: at most this often while moving
GuildMap.FAST_MAX    = 10     -- and at least this often
GuildMap.SLOW_MIN    = 10     -- a continent or world view, or the minimap: at most this often
GuildMap.SLOW_MAX    = 25     -- and at least this often (under STALE_FADE, so a still pin never fades)
GuildMap.CROWD_RATE  = 5      -- messages a second one map may cost the guild, however many are on it
GuildMap.MOVE_EPS    = 0.0015 -- of the map's width: under this a guildmate "did not move"
GuildMap.WHERE_GAP   = 10     -- the zone-change line, at most this often
GuildMap.STALE_FADE  = 30     -- a pin starts fading this many seconds after its last update
GuildMap.STALE_GONE  = 120    -- and is gone after this many
GuildMap.PING_GAP    = 2      -- a watcher never pings more often than this
GuildMap.JITTER      = 1.5    -- a peer answers a new watch within this many seconds, spread
GuildMap.MAX_INST    = 40     -- bytes of an instance's name

-- OpenMap (github.com/openmap-world/openmap, MIT; WoW: Forever and retail) draws guild members on the map too, from
-- its own GUILD line "L1<tab>map<tab>x<tab>y<tab>class<tab>level" (prefix OpenMapLoc, every 10 s moving, 60 s
-- still, only from those who turned its "Share where you are" on) and "L0" (stopped). This client READS it, never
-- sends it: a guildmate with OpenMap but not Guild OS shows here too, and one with both shows once (Guild OS's own
-- line wins). While OpenMap's own map draws guildmates, Guild OS draws no pin for those it draws (OnOpenMap) and
-- lists them. specs/salao/mapa.md "OpenMap".
GuildMap.OPENMAP_ADDON  = "OpenMap"      -- its folder
GuildMap.OPENMAP_PREFIX = "OpenMapLoc"
GuildMap.OPENMAP_GAP    = 2              -- one guildmate's OpenMap lines, at most this often (more are dropped)
GuildMap.OPENMAP_FADE   = 70             -- its pins fade after this (it sends a still place once a minute)
GuildMap.OPENMAP_GONE   = 150            -- and go after this (OpenMap's own GONE_AFTER)

-- Flags of a position line.
GuildMap.F_COMBAT, GuildMap.F_INSTANCE, GuildMap.F_WHERE = 1, 2, 4

local floor, max, min, sqrt, cos, sin = math.floor, math.max, math.min, math.sqrt, math.cos, math.sin
local TWO_PI = 2 * math.pi

local function now() return GetTime() end

----------------------------------------------------------------------
-- Pure: the wire (tools/guild-map.lua)
----------------------------------------------------------------------

local function clamp01(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end
GuildMap._Clamp01 = clamp01

-- A position as its line: "1453,5123,6234,31,0", or "1453,,,,2,Karazhan" in an instance. x and y in 1/10000 of
-- the map, facing in 1/64 of a turn; the instance's name with no comma, cut to MAX_INST bytes.
function GuildMap:EncodePos(p)
    local x, y = clamp01(p.x), clamp01(p.y)
    local flags = floor(tonumber(p.flags) or 0)
    local parts = { tostring(floor(tonumber(p.mapID) or 0)),
        x and tostring(floor(x * 9999 + 0.5)) or "", y and tostring(floor(y * 9999 + 0.5)) or "",
        p.facing and tostring(floor(((p.facing % TWO_PI) / TWO_PI) * 64 + 0.5) % 64) or "", tostring(flags) }
    if p.inst and p.inst ~= "" then
        local name = tostring(p.inst):gsub("[,%c]", " ")
        if #name > self.MAX_INST then
            name = name:sub(1, self.MAX_INST):gsub("[\192-\255][\128-\191]*$", "")
        end
        parts[6] = name
    end
    return table.concat(parts, ",")
end

-- A line back to { mapID, x, y, facing, flags, inst }, or nil for anything malformed. "-" is a retraction
-- (the sender stopped sharing): { retract = true }. The map must be a positive number unless the line is an
-- instance's (its map may be unknown, 0). Coordinates come back both or neither.
function GuildMap:DecodePos(s)
    if type(s) ~= "string" or #s > 120 then return nil end
    if s == "-" then return { retract = true } end
    local m, xs, ys, fs, fl, inst = s:match("^(%d+),(%d*),(%d*),(%d*),(%d+),?(.*)$")
    if not m then return nil end
    local flags = tonumber(fl)
    if not flags or flags > 255 then return nil end
    local mapID = tonumber(m)
    local isInst = flags % 4 >= 2
    if not mapID or (mapID <= 0 and not isInst) or mapID > 1000000 then return nil end
    local p = { mapID = mapID, flags = flags }
    local x, y = tonumber(xs), tonumber(ys)
    if x and y and not isInst then
        p.x, p.y = clamp01(x / 9999), clamp01(y / 9999)
    end
    local f = tonumber(fs)
    if f then p.facing = (f % 64) / 64 * TWO_PI end
    if inst and inst ~= "" then p.inst = inst:sub(1, self.MAX_INST) end
    return p
end

-- A watch: "1453" (the world map on 1453), "1453s" (the slow pace: the minimap), "0" (stopped).
function GuildMap:EncodeWatch(scope, slow)
    if not scope then return "0" end
    return tostring(floor(scope)) .. (slow and "s" or "")
end

function GuildMap:DecodeWatch(s)
    if type(s) ~= "string" then return nil end
    local m, slow = s:match("^(%d+)(s?)$")
    m = tonumber(m)
    if not m or m > 1000000 then return nil end
    return m, slow == "s"
end

-- OpenMap's line (untrusted): { mapID, x, y } for "L1", { retract = true } for "L0", nil for anything else (its
-- hellos and version lines, or a malformed line). Its class and level are not read: the roster gives them.
function GuildMap:DecodeOpenMap(s)
    if type(s) ~= "string" or #s > 100 then return nil end
    if s == "L0" then return { retract = true } end
    local m, xs, ys = s:match("^L1\t(%d+)\t([%d%.]+)\t([%d%.]+)")
    local mapID, x, y = tonumber(m), GuildOS.Finite(xs), GuildOS.Finite(ys)
    if not (mapID and x and y) or mapID <= 0 or mapID > 1000000 then return nil end
    if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
    return { mapID = mapID, x = x, y = y, flags = 0 }
end

----------------------------------------------------------------------
-- Pure: who sends, and when
----------------------------------------------------------------------

-- The pace a peer owes its watchers: "fast", "slow" or nil (nobody watches it). `chain` is the peer's map and
-- the maps above it, { [mapID] = mapType }; a watch on one of them counts, slow when it asked to be or when
-- it is a continent or higher (mapType 0..2), where two seconds of running do not show.
function GuildMap:_Tier(chain, watchers, t)
    local best
    for _, w in pairs(watchers or {}) do
        if w.untilT and w.untilT >= t then
            local mt = chain and chain[w.scope]
            if mt ~= nil then
                if not w.slow and not (mt >= 0 and mt <= 2) then return "fast" end
                best = "slow"
            end
        end
    end
    return best
end

-- The least and most seconds between two positions at a pace, `crowd` guildmates sending on the same map:
-- the guild's cost on one map stays near CROWD_RATE messages a second however many are there.
function GuildMap:_Intervals(tier, crowd)
    if tier == "fast" then
        local lo = max(self.FAST_MIN, (crowd or 0) / self.CROWD_RATE)
        return lo, max(self.FAST_MAX, lo)
    end
    local lo = max(self.SLOW_MIN, (crowd or 0) / self.CROWD_RATE)
    return lo, max(self.SLOW_MAX, lo)
end

-- Whether a position goes now. `last` is what went last ({ t, mapID, x, y, flags }), nil for never.
function GuildMap:_ShouldSend(last, pos, t, tier, crowd)
    if not pos or not tier then return false end
    if not last then return true end
    local el = t - last.t
    if pos.mapID ~= last.mapID or (pos.flags or 0) ~= (last.flags or 0) then return el >= 1 end
    local lo, hi = self:_Intervals(tier, crowd)
    if el >= hi then return true end
    if el < lo then return false end
    if pos.x and last.x then
        local dx, dy = pos.x - last.x, pos.y - last.y
        return dx * dx + dy * dy >= self.MOVE_EPS * self.MOVE_EPS
    end
    return (pos.x ~= nil) ~= (last.x ~= nil)
end

-- Whether a peer owes its watchers a position now, and at which pace. The crowd that spreads the pace is the
-- guildmates heard on the same map for the fast pace (`crowdMap`), all of them for the slow one (`crowdAll`):
-- a continent or world view costs the guild CROWD_RATE messages a second at most, as one zone does.
function GuildMap:_Owe(last, pos, t, chain, watchers, crowdMap, crowdAll)
    local tier = self:_Tier(chain, watchers, t)
    local crowd = tier == "fast" and crowdMap or crowdAll
    return self:_ShouldSend(last, pos, t, tier, crowd), tier
end

----------------------------------------------------------------------
-- Pure: drawing helpers
----------------------------------------------------------------------

-- How opaque a pin `age` seconds old is: 1 until STALE_FADE, down to 0.3 at STALE_GONE, 0 after.
-- `fade` and `gone` for another pace (OpenMap's lines).
function GuildMap:_StaleAlpha(age, fade, gone)
    fade, gone = fade or self.STALE_FADE, gone or self.STALE_GONE
    if age <= fade then return 1 end
    if age > gone then return 0 end
    return 1 - 0.7 * (age - fade) / (gone - fade)
end

-- How long a peer's pin stays whole and how long it stays at all: OpenMap's lines come slower.
function GuildMap:_Lifetimes(p)
    if p.via == "openmap" then return self.OPENMAP_FADE, self.OPENMAP_GONE end
    return self.STALE_FADE, self.STALE_GONE
end

-- Where a peer is drawn at time t: from its last drawn spot to its newest one over lerpDur seconds.
function GuildMap:_Lerp(p, t)
    if not p.x then return nil end
    if not p.fromX or not p.lerpDur or p.lerpDur <= 0 then return p.x, p.y end
    local k = (t - (p.lerpT or 0)) / p.lerpDur
    if k >= 1 then return p.x, p.y end
    if k < 0 then k = 0 end
    return p.fromX + (p.x - p.fromX) * k, p.fromY + (p.y - p.fromY) * k
end

-- How map `from` lies on map `shown`: ax, bx, ay, by with shownX = ax + bx * x and shownY = ay + by * y (both
-- maps are flat projections of the same ground, so the relation is affine), or nil. `api` gives MapToWorld,
-- WorldToMap, MapRectOnMap and MapInfo (Compat in the game, stubs in the harness). A direct rectangle first; then
-- world yards (a neighbouring zone, a continent from a zone); then up the parent chain one rectangle at a time.
function GuildMap:_Transform(shown, from, api)
    if from == shown then return 0, 1, 0, 1 end
    local x0, x1, y0, y1 = api.MapRectOnMap(from, shown)
    if x0 and x1 and x1 > x0 and y1 > y0 then return x0, x1 - x0, y0, y1 - y0 end
    local c0, w0x, w0y = api.MapToWorld(from, 0, 0)
    local c1, w1x, w1y = api.MapToWorld(from, 1, 1)
    if c0 and c0 == c1 then
        local s0x, s0y = api.WorldToMap(c0, w0x, w0y, shown)
        local s1x, s1y = api.WorldToMap(c1, w1x, w1y, shown)
        if s0x and s1x and s1x > s0x and s1y > s0y then return s0x, s1x - s0x, s0y, s1y - s0y end
    end
    local ax, bx, ay, by, cur = 0, 1, 0, 1, from
    for _ = 1, 8 do
        local info = api.MapInfo(cur)
        local parent = info and info.parent
        if not parent or parent == 0 then return nil end
        local a0, a1, b0, b1 = api.MapRectOnMap(cur, parent)
        if not (a0 and a1 and a1 > a0 and b1 > b0) then return nil end
        ax, bx = a0 + ax * (a1 - a0), bx * (a1 - a0)
        ay, by = b0 + ay * (b1 - b0), by * (b1 - b0)
        cur = parent
        if cur == shown then return ax, bx, ay, by end
    end
    return nil
end

-- The game's maps do not move: a transform, once found, is kept (only for the game's own api).
local transforms = {}
local yards = {}   -- [mapID] = { width, height } in yards, or false (_MapYards)
function GuildMap:_TransformCached(shown, from, api)
    if api ~= GuildOS.Compat then return self:_Transform(shown, from, api) end
    local k = from .. ">" .. shown
    local t = transforms[k]
    if t == nil then
        local ax, bx, ay, by = self:_Transform(shown, from, api)
        t = ax and { ax, bx, ay, by } or false
        transforms[k] = t
    end
    if not t then return nil end
    return t[1], t[2], t[3], t[4]
end

-- A point (x, y) of map `mapID` on map `shown` (0..1), or nil when it is not on it.
function GuildMap:_PlaceOn(shown, mapID, x, y, api)
    if not (shown and mapID and x and y) then return nil end
    local ax, bx, ay, by = self:_TransformCached(shown, mapID, api or GuildOS.Compat)
    if not ax then return nil end
    local sx, sy = ax + bx * x, ay + by * y
    if sx < 0 or sx > 1 or sy < 0 or sy > 1 then return nil end
    return sx, sy
end

-- A map's width and height in yards (east-west, north-south), or nil.
-- Kept per map for the game's own api (the minimap dots ask ten times a second; each read made four vectors).
function GuildMap:_MapYards(mapID, api)
    if api == GuildOS.Compat and mapID then
        local y = yards[mapID]
        if y == nil then
            local w, h = self:_MapYardsOf(mapID, api)
            y = w and { w, h } or false
            yards[mapID] = y
        end
        if y then return y[1], y[2] end
        return nil
    end
    return self:_MapYardsOf(mapID, api)
end
function GuildMap:_MapYardsOf(mapID, api)
    local c0, ax, ay = api.MapToWorld(mapID, 0, 0)
    local c1, bx, by = api.MapToWorld(mapID, 1, 1)
    if not c0 or c0 ~= c1 then return nil end
    local w, h = ay - by, ax - bx   -- worldY grows west, worldX north
    if w <= 0 or h <= 0 then return nil end
    return w, h
end

-- The minimap's radius in yards at a zoom level, outdoors or in (the game's own scales).
local MM_OUT = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local MM_IN = { [0] = 300, 240, 180, 120, 80, 50 }
function GuildMap:_MinimapRadius(zoom, indoors)
    local t = indoors and MM_IN or MM_OUT
    return (t[zoom or 0] or t[0]) / 2
end

-- Where a guildmate dx yards east and dy yards south of the player sits on a round minimap: px, py from its
-- centre (y up), whether it was held at the edge, and the distance in yards. `facing` turns it with a
-- rotating minimap (nil: north up).
function GuildMap:_MinimapOffset(dx, dy, radiusYd, radiusPx, facing)
    local ex, ny = dx, -dy
    if facing then
        local c, s = cos(facing), sin(facing)
        ex, ny = ex * c + ny * s, -ex * s + ny * c
    end
    local k = radiusPx / radiusYd
    local px, py = ex * k, ny * k
    local d = sqrt(px * px + py * py)
    local edge = false
    if d > radiusPx then
        px, py, edge = px * radiusPx / d, py * radiusPx / d, true
    end
    return px, py, edge, sqrt(dx * dx + dy * dy)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
GuildMap.peers = {}      -- [key] = what the guildmate sent (see HandlePosition)
GuildMap.group = {}      -- [key] = a party or raid member read here
GuildMap.watchers = {}   -- [senderKey] = { scope, slow, untilT }
GuildMap.openMapSeen = {} -- [key] = when this client last heard the guildmate's OpenMap line (what OpenMap draws)
GuildMap.watch = {}      -- [reason] = scope: this client's own watches ("worldmap", "minimap")
GuildMap.sent = nil      -- what this client last sent: { t, mapID, x, y, flags }
GuildMap.stats = { sent = 0, pings = 0, bytes = 0, received = 0 }

local function prefs()
    local db = GuildOS.db
    if not db then return {} end
    db.guildMapPrefs = type(db.guildMapPrefs) == "table" and db.guildMapPrefs or {}
    return db.guildMapPrefs
end

-- "Share my position with the guild": on unless the player turned it off.
function GuildMap:IsSharing() return prefs().share ~= false end

-- Turning it off sends one retraction, so guildmates' pins go at once; nothing more ever goes until it is on.
function GuildMap:SetSharing(on)
    local was = self:IsSharing()
    prefs().share = on and true or false
    if was and not on then
        self:_Send("MP", "-")
        self.sent = nil
    end
    if self.uiRefresh then self.uiRefresh() end
end

-- The guildmates-in-your-zone dots on the minimap (#271): on unless turned off.
function GuildMap:IsMinimapDots() return prefs().minimapDots ~= false end

function GuildMap:SetMinimapDots(on)
    prefs().minimapDots = on and true or false
    if not on then self:SetWatch("minimap", nil) end
    if self.uiRefresh then self.uiRefresh() end
end

-- The list on the world map: shown unless closed (its X); /gos map brings it back.
function GuildMap:IsListShown() return prefs().list ~= false end
function GuildMap:SetListShown(on) prefs().list = on and true or false end

----------------------------------------------------------------------
-- Roster (class, level, zone come from here, never from a payload)
----------------------------------------------------------------------
-- Read again at most every ROSTER_TTL seconds, or after a roster update (_rosterStale), into the same table and
-- the same entry per member (memory audit, memoria.md: a new table per member each time was the map's garbage).
local ROSTER_TTL = 30
local rosterStamp = 0
function GuildMap:_Roster()
    local t = now()
    local r = self._roster
    if r and not self._rosterStale and t - self._rosterAt < ROSTER_TTL then return r end
    if not r then r = {}; self._roster = r end
    rosterStamp = rosterStamp + 1
    local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, n do
        local full, _, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if type(full) == "string" then
            local key = GuildOS:KeyOfRosterName(full)
            if key then
                local m = r[key]
                if not m then m = {}; r[key] = m end
                m.level, m.zone, m.online, m.class = level, zone, online and true or false, classFile
                m.name, m.stamp = full:match("^([^-]+)") or full, rosterStamp
            end
        end
    end
    for key, m in pairs(r) do if m.stamp ~= rosterStamp then r[key] = nil end end
    self._rosterAt, self._rosterStale = t, nil
    return r
end

function GuildMap:_Member(key)
    local m = self:_Roster()[key]
    if m then return m end
    local d = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
    if type(d) == "table" then return { class = d.class, level = d.level } end
    return nil
end

----------------------------------------------------------------------
-- Maps (cached chains)
----------------------------------------------------------------------
local chains = {}
-- The client's maps do not change in a session; C_Map.GetMapInfo answers a new table each call, and the minimap
-- watch asks once a second. Kept per map (false: no map), with the chains, until the next zone change.
local infos, zones = {}, {}
local function mapInfo(id)
    if not id then return nil end
    local info = infos[id]
    if info == nil then
        info = GuildOS.Compat.MapInfo(id) or false
        infos[id] = info
    end
    return info or nil
end
GuildMap._MapInfo = function(_, id) return mapInfo(id) end
-- { [mapID] = mapType } for a map and everything above it (mapType -1 where unknown).
function GuildMap:_Chain(mapID)
    if not mapID then return nil end
    if chains[mapID] then return chains[mapID] end
    local c, cur = {}, mapID
    for _ = 1, 10 do
        local info = mapInfo(cur)
        c[cur] = (info and info.mapType) or -1
        local parent = info and info.parent
        if not parent or parent == 0 or c[parent] then break end
        cur = parent
    end
    chains[mapID] = c
    return c
end

-- The zone a map belongs to: the first of its chain that is a zone (mapType 3), else the map itself.
local function zoneOf(mapID)
    local cur = mapID
    for _ = 1, 10 do
        local info = cur and mapInfo(cur)
        if not info then return mapID end
        if info.mapType == 3 then return cur end
        if not info.parent or info.parent == 0 then return mapID end
        cur = info.parent
    end
    return mapID
end
function GuildMap:_ZoneOf(mapID)
    if not mapID then return nil end
    local z = zones[mapID]
    if z == nil then
        z = zoneOf(mapID)
        zones[mapID] = z
    end
    return z
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------
function GuildMap:_Send(kind, payload)
    local comm = GuildOS.CommSystem
    if not comm or not IsInGuild() then return false end
    local code = comm.MSG_TYPES[kind == "MW" and "MAP_WATCH" or "MAP_POS"]
    comm:SendMessage(code, payload, nil, "NORMAL", kind == "MW" and "map watch" or "map position")
    if kind == "MW" then self.stats.pings = self.stats.pings + 1 else self.stats.sent = self.stats.sent + 1 end
    return true
end

-- This client's position as it may leave, or nil and why not: "off" (not shared), "locked" (chat lockdown),
-- "combat" (in an instance in combat or a boss), "nomap" (no map, or a secret one). In an instance: its name,
-- no coordinates.
function GuildMap:_ReadSelf()
    if not self:IsSharing() then return nil, "off" end
    local Compat = GuildOS.Compat
    if Compat.InChatLockdown and Compat.InChatLockdown() then return nil, "locked" end
    local combat = Compat.InCombat() or (UnitAffectingCombat and UnitAffectingCombat("player") == true)
    local inside, _, iname = Compat.InstanceState()
    if inside then
        if combat or Compat.IsEncounterInProgress() then return nil, "combat" end
        local map = Compat.GetBestMapForUnit("player") or 0
        return { mapID = map, flags = self.F_INSTANCE, inst = iname }
    end
    local map = Compat.GetBestMapForUnit("player")
    if not map or map <= 0 then return nil, "nomap" end
    local x, y = Compat.GetPlayerMapPosition(map, "player")
    return { mapID = map, x = x, y = y, facing = x and Compat.PlayerFacing() or nil,
        flags = combat and self.F_COMBAT or 0 }
end

-- How many guildmates were heard lately on map `mapID`, and in all (the crowds the pace spreads over).
function GuildMap:_Crowd(mapID, t)
    local here, all = 0, 0
    for _, p in pairs(self.peers) do
        if t - p.t <= 30 and p.via ~= "openmap" then
            all = all + 1
            if p.mapID == mapID then here = here + 1 end
        end
    end
    return here, all
end

-- One position, if it is owed now. `where` marks the zone-change line (sent whether watched or not).
function GuildMap:_MaybeSend(t, where)
    local pos = self:_ReadSelf()
    if not pos then return false end
    local chain = self:_Chain(pos.mapID)
    if where then
        if self.sent and t - self.sent.t < self.WHERE_GAP and self.sent.mapID == pos.mapID then return false end
        if not self:_Tier(chain, self.watchers, t) then pos.flags = pos.flags + self.F_WHERE end
    else
        local here, all = self:_Crowd(pos.mapID, t)
        if not self:_Owe(self.sent, pos, t, chain, self.watchers, here, all) then return false end
    end
    local line = self:EncodePos(pos)
    if not self:_Send("MP", line) then return false end
    self.sent = { t = t, mapID = pos.mapID, x = pos.x, y = pos.y, flags = pos.flags % 4 }
    return true
end

----------------------------------------------------------------------
-- Watching (this client looks)
----------------------------------------------------------------------

-- The watch this client holds: the world map's (fast) before the minimap's (slow).
function GuildMap:_CurrentWatch()
    if self.watch.worldmap then return self.watch.worldmap, false end
    if self.watch.minimap then return self.watch.minimap, true end
    return nil
end

-- Start, move or end one of this client's watches. The ping goes at once (at most every PING_GAP seconds; the
-- last change is never lost).
function GuildMap:SetWatch(reason, scope)
    if self.watch[reason] == scope then return end
    local a, b = self:_CurrentWatch()
    self.watch[reason] = scope
    local c, d = self:_CurrentWatch()
    if a == c and b == d then return end   -- the watch that goes out is the same: nothing to say
    self:_PingSoon()
end

function GuildMap:_PingSoon()
    local t = now()
    local gap = t - (self._pingAt or -math.huge)
    if gap >= self.PING_GAP then return self:_Ping(t) end
    if self._pingPending then return end
    self._pingPending = true
    GuildOS.Compat.After(self.PING_GAP - gap + 0.05, function()
        self._pingPending = false
        self:_Ping(now())
    end)
end

function GuildMap:_Ping(t)
    local scope, slow = self:_CurrentWatch()
    local line = scope and self:EncodeWatch(scope, slow) or nil
    if not line then
        if self._pinged then self:_Send("MW", "0") end
        self._pinged, self._pingAt = nil, t
        return
    end
    self:_Send("MW", line)
    self._pinged, self._pingAt = line, t
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

-- A watch from a guildmate (GUILD only). A new one, or one that moved, is answered within JITTER seconds.
function GuildMap:HandleWatch(sender, data, channel)
    if channel ~= "GUILD" or not sender then return end
    local scope, slow = self:DecodeWatch(data)
    if not scope then return end
    local key = GuildOS:SenderKey(sender)
    if not key then return end
    if scope == 0 then self.watchers[key] = nil; return end
    local old = self.watchers[key]
    self.watchers[key] = { scope = scope, slow = slow, untilT = now() + self.WATCH_TTL }
    if not old or old.scope ~= scope or old.slow ~= slow then
        self.sent = self.sent and { t = -math.huge, mapID = self.sent.mapID, x = self.sent.x, y = self.sent.y,
            flags = self.sent.flags } or nil
        if not self._answerPending then
            self._answerPending = true
            GuildOS.Compat.After(math.random() * self.JITTER, function()
                self._answerPending = false
                self:_MaybeSend(now())
            end)
        end
    end
end

-- A guildmate's position (GUILD only), keyed by the envelope sender. The pin glides from where it is drawn to
-- the new spot over the time since the last one (at most FAST_MAX); a new map snaps.
function GuildMap:HandlePosition(sender, data, channel)
    if channel ~= "GUILD" or not sender then return end
    local p = self:DecodePos(data)
    if not p then return end
    local key = GuildOS:SenderKey(sender)
    if not key then return end
    self.stats.received = self.stats.received + 1
    if p.retract then
        self.peers[key] = nil
        if self.uiRefresh then self.uiRefresh() end
        return
    end
    self:_Store(key, p, now())
end

-- A peer's new place, gliding from where it is drawn (a new map snaps). Class, level and name from the roster.
function GuildMap:_Store(key, p, t)
    local old = self.peers[key]
    local m = self:_Member(key) or {}
    p.key, p.t = key, t
    p.name = m.name or key:match("^([^-]+)") or key
    p.class, p.level = m.class, m.level
    if old and old.mapID == p.mapID and old.x and p.x then
        local cx, cy = self:_Lerp(old, t)
        p.fromX, p.fromY = cx, cy
        p.lerpT, p.lerpDur = t, min(self.FAST_MAX, max(0.5, t - old.t))
    end
    self.peers[key] = p
    if self.uiRefresh then self.uiRefresh() end
end

-- OpenMap's line (GUILD only, from a guildmate on the roster, never this client's own). Read, never answered.
-- Guild OS's own line from the same guildmate wins while it is fresh; an OpenMap "L0" removes only OpenMap's pin.
-- Every valid line is remembered in openMapSeen (OpenMap draws that guildmate itself: GuildMap:OnOpenMap).
function GuildMap:HandleOpenMap(sender, text, channel)
    if channel ~= "GUILD" or type(sender) ~= "string" then return end
    local p = self:DecodeOpenMap(text)
    if not p then return end
    local key = GuildOS:SenderKey(sender)
    if not key or key == GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) then return end
    local t, old = now(), self.peers[key]
    if p.retract then
        self.openMapSeen[key] = nil
        if old and old.via == "openmap" then
            self.peers[key] = nil
        end
        if self.uiRefresh then self.uiRefresh() end
        return
    end
    local seen = self.openMapSeen[key]
    if seen and t - seen < self.OPENMAP_GAP then return end
    if not self:_Roster()[key] or not mapInfo(p.mapID) then return end
    self.openMapSeen[key] = t
    self.stats.openmap = (self.stats.openmap or 0) + 1
    if old and old.via ~= "openmap" and t - old.t <= self.STALE_GONE then return end
    p.via = "openmap"
    self:_Store(key, p, t)
end

----------------------------------------------------------------------
-- Guildmates' campfires (WoW: Forever; chehulnet AGENTS.md "ChehulCamp", specs/salao/mapa.md "Fogueiras")
--
-- Warmth (the family's campfire addon) and the ChehulNet beacon (v17: on unless the player turned it off) announce
-- a fire the player lit on the ChehulCamp prefix, in Warmth's wire (Warmth's Core/Wire.lua, version C2):
--   C2|A|map|x|y|zuid|tier(+flags)|n|age|objects|people|note   a named announce (guild and group)
--   C2|X                                                      the camp ended
--   C2|S|map|x|y|zuid|tier(+flags)                            an ownerless sighting (the realm bus; not drawn here)
-- x, y in 1/10000 of the map, age in minutes, people "Name~c" separated by ";" (c: the class as one letter), objects
-- the camp's object indexes. The beacon sends "C2|A|map|x|y|zuid|<tier>l|1|age||Name~c|", again every four minutes
-- while near it. This client READS the A and X that come over GUILD from a guildmate on the roster, never sends one
-- (the beacon, Modules/ChehulNet.lua, does) and never relays one (the mesh does). Its own AceComm route on the
-- prefix, not Mesh:Register: that would take the prefix's handler from the mesh, which relays Warmth's camps. Off
-- WoW: Forever there are no camp kits; with Warmth loaded, Warmth draws the camps itself (with their circle), so this
-- layer is off.
----------------------------------------------------------------------
GuildMap.CAMP_PREFIX = "ChehulCamp"
GuildMap.CAMP_ADDON  = "Warmth"
GuildMap.CAMP_LIFE   = 3600   -- a beacon's camp ("l") burns at most this long (the beacon's CAMP_LIFE)
GuildMap.CAMP_QUIET  = 600    -- a camp not heard again this long is gone (the beat comes every 240 s)
GuildMap.CAMP_GAP    = 2      -- one guildmate's camp lines, at most this often (more are dropped)
GuildMap.CAMP_MAX    = 60     -- camps kept at most (one a guildmate)
GuildMap.CAMP_BYTES  = 255    -- a line longer than one addon message is not a camp
-- Warmth's limits (Core/Wire.lua): a line these break is one Warmth refuses too.
GuildMap.CAMP_AGE_MAX  = 1440 -- minutes
GuildMap.CAMP_COUNT    = 40   -- people in the circle
GuildMap.CAMP_PEOPLE   = 9    -- people an announce names
GuildMap.CAMP_OBJECTS  = { 3, 5, 10 }  -- objects a camp of each tier holds (Warmth's W.SLOTS)
GuildMap.CAMP_NAME_MAX = 40

GuildMap.camps = {}      -- [key] = { key, name, class, mapID, x, y, tier, lit, heard, life }

-- The kit's tier (1..3, ChehulNet.CAMP_KITS) as its name.
local function tierName(tier)
    local L = GuildOS.L
    if tier == 3 then return L["Expert"] end
    if tier == 2 then return L["Journeyman"] end
    return L["Basic"]
end

-- A line split at "|" into at most `limit` fields, the last keeping the rest (as strsplit with a limit).
local function splitBars(s, limit)
    local out, pos = {}, 1
    while #out < limit - 1 do
        local i = s:find("|", pos, true)
        if not i then break end
        out[#out + 1] = s:sub(pos, i - 1)
        pos = i + 1
    end
    out[#out + 1] = s:sub(pos)
    return out
end

-- A whole number off the wire in lo..hi, or nil.
local function wireInt(s, lo, hi)
    if type(s) ~= "string" or #s > 10 or not s:match("^%d+$") then return nil end
    local n = tonumber(s)
    return (n and n >= lo and n <= hi) and n or nil
end

-- A name as Warmth lets it travel.
local function goodName(name, most)
    return type(name) == "string" and #name >= 1 and #name <= most and not name:find("[|;~%c]")
end

-- A camp's line (untrusted) as { mapID, x, y, tier, age (seconds), family } for a named announce, { ended = true }
-- for "C2|X", nil for anything else (a sighting, a join, an invite, a malformed line). The same checks as Warmth's
-- Wire.Decode: the tier's flag letters (up to four, lowercase) are skipped but "l" (the beacon's); objects, people
-- and the note are checked and not kept. Who lit it is the envelope's sender, never the people field.
function GuildMap:DecodeCamp(s)
    if type(s) ~= "string" or #s > self.CAMP_BYTES then return nil end   -- (a note may hold anything; it is not read)
    if s == "C2|X" then return { ended = true } end
    if s:sub(1, 5) ~= "C2|A|" then return nil end
    local f = splitBars(s, 12)
    if #f < 12 then return nil end
    local mapID = wireInt(f[3], 1, 99999)
    local x, y = wireInt(f[4], 0, 10000), wireInt(f[5], 0, 10000)
    local zuid = wireInt(f[6], 0, 2147483647)
    local digit, flags = f[7]:match("^(%d)(%l?%l?%l?%l?)$")
    local tier = wireInt(digit, 1, #self.CAMP_OBJECTS)
    local n, age = wireInt(f[8], 0, self.CAMP_COUNT), wireInt(f[9], 0, self.CAMP_AGE_MAX)
    if not (mapID and x and y and zuid and tier and n and age) or (x == 0 and y == 0) then return nil end
    local objs = 0
    for item in f[10]:gmatch("[^,]+") do
        objs = objs + 1
        if not wireInt(item, 1, 999) or objs > self.CAMP_OBJECTS[tier] then return nil end
    end
    local people = 0
    for item in f[11]:gmatch("[^;]+") do
        people = people + 1
        if people > self.CAMP_PEOPLE or not goodName(item:match("^(.-)~%l$"), self.CAMP_NAME_MAX) then return nil end
    end
    return { mapID = mapID, x = x / 10000, y = y / 10000, tier = tier, age = age * 60,
        family = flags:find("l", 1, true) ~= nil }
end

-- Whether the campfire layer is on here: WoW: Forever, and Warmth not loaded (it draws them itself).
function GuildMap:CampsOn()
    local c = GuildOS.Client
    if not c or c.isAnniversary or c.isRetail then return false end
    return not GuildOS.Compat.IsAddOnLoaded(self.CAMP_ADDON)
end

-- A camp line (GUILD only, from a guildmate on the roster, never this client's own): the camp kept or ended.
function GuildMap:HandleCamp(sender, text, channel)
    if channel ~= "GUILD" or type(sender) ~= "string" or not self:CampsOn() then return end
    local c = self:DecodeCamp(text)
    if not c then return end
    local key = GuildOS:SenderKey(sender)
    if not key or key == GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) then return end
    local m = self:_Roster()[key]
    if not m then return end
    local t, old = now(), self.camps[key]
    if c.ended then
        if old then
            self.camps[key] = nil
            if self.uiRefresh then self.uiRefresh() end
        end
        return
    end
    if old and t - old.heard < self.CAMP_GAP then return end
    if not old then
        local n = 0
        for _ in pairs(self.camps) do n = n + 1 end
        if n >= self.CAMP_MAX then return end
    end
    if not mapInfo(c.mapID) then return end
    self.camps[key] = { key = key, name = m.name or key:match("^([^-]+)") or key, class = m.class,
        mapID = c.mapID, x = c.x, y = c.y, tier = c.tier, lit = t - c.age, heard = t,
        life = c.family and self.CAMP_LIFE or self.CAMP_AGE_MAX * 60 }
    self.stats.camps = (self.stats.camps or 0) + 1
    if self.uiRefresh then self.uiRefresh() end
end

-- Drop the camps that burnt out (a beacon's CAMP_LIFE since lit, Warmth's own CAMP_AGE_MAX) or went quiet
-- (CAMP_QUIET since heard).
function GuildMap:_PruneCamps(t)
    for k, c in pairs(self.camps) do
        if t - c.lit >= (c.life or self.CAMP_LIFE) or t - c.heard > self.CAMP_QUIET then self.camps[k] = nil end
    end
end

-- The guildmates' camps to draw, sorted by name: { key, name, class, mapID, x, y, tier, tierName, zone, age };
-- none while the layer is off.
function GuildMap:GetCamps(t)
    t = t or now()
    local out = {}
    if not self:CampsOn() then return out end
    self:_PruneCamps(t)
    for _, c in pairs(self.camps) do
        out[#out + 1] = { key = c.key, name = c.name, class = c.class, mapID = c.mapID, x = c.x, y = c.y,
            tier = c.tier, tierName = tierName(c.tier), zone = self:_MapName(c.mapID),
            age = t - c.lit }
    end
    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

-- The tooltip's line: "<Name> lit a campfire in <Zone> · <tier> level".
function GuildMap:CampText(c)
    return string.format(GuildOS.L["%s lit a campfire in %s · %s level"], c.name or "?",
        c.zone or GuildOS.L["Unknown zone"], c.tierName or GuildOS.L["Basic"])
end

-- Listens on ChehulCamp through Guild OS's own AceComm route (the raw event where AceComm is missing). WoW:
-- Forever only; registering the prefix sends nothing.
function GuildMap:_ListenCamps()
    local c = GuildOS.Client
    if self._campComm or not c or c.isAnniversary or c.isRetail then return end
    local function onCamp(prefix, text, channel, sender)
        if prefix ~= GuildMap.CAMP_PREFIX or GuildOS.Compat.IsSecret(text, channel, sender) then return end
        GuildOS:SafeCall(GuildMap.HandleCamp, GuildMap, sender, text, channel)
    end
    local ace = LibStub and LibStub("AceComm-3.0", true)
    self._campComm = {}
    if ace and ace.RegisterComm then
        ace.RegisterComm(self._campComm, self.CAMP_PREFIX, onCamp)
        return
    end
    pcall(GuildOS.Compat.RegisterAddonPrefix, self.CAMP_PREFIX)
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, ...) onCamp(...) end)
    self._campComm.frame = f
end

----------------------------------------------------------------------
-- The group, read here
----------------------------------------------------------------------
-- The group's units and which of them were read, kept between reads (twice a second): each member's entry is
-- filled again in place (memoria.md).
local groupUnits, groupSeen = {}, {}
function GuildMap:_ReadGroup(t)
    local Compat = GuildOS.Compat
    local seen = groupSeen
    for k in pairs(seen) do seen[k] = nil end
    if not Compat.InstanceState() then
        for _, u in ipairs(Compat.GroupUnits(groupUnits)) do
            local m = self:_Roster()[u.key]
            if m then
                local map = Compat.GetBestMapForUnit(u.unit)
                local x, y
                if map then x, y = Compat.GetPlayerMapPosition(map, u.unit) end
                if map and x then
                    local e = self.group[u.key]
                    local fromX, fromY, lerpT, lerpDur
                    if e and e.mapID == map and e.x then
                        fromX, fromY = self:_Lerp(e, t)
                        lerpT, lerpDur = t, max(0.1, t - e.t)
                    end
                    if not e then e = {}; self.group[u.key] = e end
                    e.key, e.name, e.class, e.level = u.key, m.name or u.name, m.class or u.class, m.level
                    e.mapID, e.x, e.y, e.flags, e.t, e.isGroup = map, x, y, 0, t, true
                    e.fromX, e.fromY, e.lerpT, e.lerpDur = fromX, fromY, lerpT, lerpDur
                    seen[u.key] = true
                end
            end
        end
    end
    for k in pairs(self.group) do if not seen[k] then self.group[k] = nil end end
end

----------------------------------------------------------------------
-- For the UI
----------------------------------------------------------------------

local mapNames = {}
function GuildMap:_MapName(mapID)
    if not mapID or mapID <= 0 then return nil end
    local n = mapNames[mapID]
    if n == nil then
        n = GuildOS.Compat.GetMapName(mapID) or false
        mapNames[mapID] = n
    end
    return n or nil
end

-- Every guildmate whose place is known, sorted by name: { key, name, class, level, mapID, x, y (drawn now),
-- alpha, age, flags, inst, isGroup, zone, via, onOpenMap (OpenMap draws them: Guild OS lists them, no pin) }. Group members come from here; the rest from what they sent,
-- within STALE_GONE.
function GuildMap:GetPeers(t)
    t = t or now()
    self:_FreshGroup(t)
    local out, seen = {}, {}
    local function add(p)
        local age = t - p.t
        local fade, gone = self:_Lifetimes(p)
        if age > gone then return end
        local x, y = self:_Lerp(p, t)
        local inst = p.flags and p.flags % 4 >= 2
        out[#out + 1] = { key = p.key, name = p.name, class = p.class, level = p.level, mapID = p.mapID,
            x = x, y = y, alpha = self:_StaleAlpha(age, fade, gone), age = age, flags = p.flags or 0, inst = p.inst,
            isGroup = p.isGroup, combat = p.flags and p.flags % 2 == 1, inInstance = inst, via = p.via,
            onOpenMap = self:OnOpenMap(p, t), zone = (inst and p.inst) or self:_MapName(p.mapID) }
        seen[p.key] = true
    end
    for _, p in pairs(self.group) do add(p) end
    for k, p in pairs(self.peers) do if not seen[k] then add(p) end end
    table.sort(out, function(a, b)
        local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
        if an ~= bn then return an < bn end
        return (a.key or "") < (b.key or "")
    end)
    return out
end

-- The group, read again at most every 0.5 s (a 40-man raid is 40 reads).
function GuildMap:_FreshGroup(t)
    if t - (self._groupAt or -math.huge) >= 0.5 then
        self._groupAt = t
        self:_ReadGroup(t)
    end
end

-- fn(p, x, y, alpha) for every guildmate drawn at time t (x, y nil when only the zone is known), group members
-- first, but those OpenMap draws itself (OnOpenMap); nothing allocated, for what redraws many times a second.
function GuildMap:ForEachLive(t, fn)
    self:_FreshGroup(t)
    for _, p in pairs(self.group) do
        if not self:OnOpenMap(p, t) then
            local x, y = self:_Lerp(p, t)
            fn(p, x, y, 1)
        end
    end
    for k, p in pairs(self.peers) do
        local age = t - p.t
        local fade, gone = self:_Lifetimes(p)
        if not self.group[k] and age <= gone and not self:OnOpenMap(p, t) then
            local x, y = self:_Lerp(p, t)
            fn(p, x, y, self:_StaleAlpha(age, fade, gone))
        end
    end
end

-- Drop what is older than STALE_GONE and the watches that ended.
function GuildMap:_Prune(t)
    for k, p in pairs(self.peers) do
        local _, gone = self:_Lifetimes(p)
        if t - p.t > gone then self.peers[k] = nil end
    end
    for k, w in pairs(self.watchers) do if w.untilT < t then self.watchers[k] = nil end end
    for k, seen in pairs(self.openMapSeen) do if t - seen > self.OPENMAP_GONE then self.openMapSeen[k] = nil end end
    self:_PruneCamps(t)
end

-- The online guildmates the roster puts in the shown zone that have no place known here (no Guild OS, no OpenMap
-- sharing, or not sharing): their names, sorted. OpenMap shows them as a badge on the zone; the list names them. The
-- roster's zone is a name, so only a zone's own map (or a map inside it) matches; `known` holds the keys drawn.
function GuildMap:RosterOnlyHere(shownMap, known)
    local out = {}
    local zone = shownMap and self:_ZoneOf(shownMap)
    local info = zone and mapInfo(zone)
    if not info or info.mapType ~= 3 then return out end
    local name = GuildOS.Compat.GetMapName(zone)
    if not name then return out end
    local me = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
    for key, m in pairs(self:_Roster()) do
        if m.online and key ~= me and m.zone == name and not (known and known[key]) then out[#out + 1] = m.name or key end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

-- OpenMap: whether it is loaded here, and what its own settings say.
function GuildMap:OpenMapLoaded() return GuildOS.Compat.IsAddOnLoaded(self.OPENMAP_ADDON) end

-- OpenMap's settings, read only (OpenMapDB.worldmap, its account-wide save; never written): `guild`, whether its
-- map draws guild members ("Guild members on the map", on by default), and `group`, whether it draws the party and
-- raid ("Party and raid members", on by default; Blizzard's own dots stand in where its map is not shown). Its map
-- off draws neither. nil without OpenMap; an unknown save reads as its defaults.
function GuildMap:OpenMapState()
    if not self:OpenMapLoaded() then return nil end
    local db = _G.OpenMapDB   -- (another addon's saved table: read, never written)
    local w = type(db) == "table" and type(db.worldmap) == "table" and db.worldmap or nil
    if not w then return { guild = true, group = true } end
    local on = w.enabled ~= false
    return { guild = on and w.guild ~= false, group = on and w.group ~= false }
end

-- OpenMap's settings as last read: read again when the world map opens (RefreshOpenMap) and at most every
-- OPENMAP_RECHECK seconds otherwise (from Tick), never per frame. nil when OpenMap does not draw guildmates here.
GuildMap.OPENMAP_RECHECK = 30
function GuildMap:RefreshOpenMap(t)
    t = t or now()
    local st = self:OpenMapState()
    self._openMap = st and st.guild and st or nil
    self._openMapAt = t
    return self._openMap
end

function GuildMap:_OpenMapCoord(t)
    if not self._openMapAt or t - self._openMapAt >= self.OPENMAP_RECHECK then self:RefreshOpenMap(t) end
    return self._openMap
end

-- Whether OpenMap already draws guildmate `p` on this client (so Guild OS draws no pin or dot for them): only
-- while OpenMap's "Guild members on the map" is on; a group member when its "Party and raid members" is on too
-- (OpenMap leaves the group out of its guild dots); anyone else when their OpenMap line was heard within
-- OPENMAP_GONE (OpenMap's own lifetime for a dot). The world map's list still names everybody.
function GuildMap:OnOpenMap(p, t)
    local om = self:_OpenMapCoord(t)
    if not om then return false end
    if p.isGroup then return om.group and true or false end
    local seen = self.openMapSeen[p.key]
    return seen ~= nil and t - seen <= self.OPENMAP_GONE
end

-- Whether some online guildmate's roster line names the zone `mapID` is in (the minimap watch's reason).
function GuildMap:_ZoneHasGuildmates(zoneMap)
    local info = mapInfo(zoneMap)   -- kept per map (once a second, the client's GetMapInfo made a table)
    local name = info and info.name
    if not name then return false end
    local me = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
    for key, m in pairs(self:_Roster()) do
        if m.online and key ~= me and m.zone == name then return true end
    end
    return false
end

-- The minimap's watch: on while the dots are on, outside an instance, with a guildmate in the zone.
function GuildMap:_UpdateMinimapWatch()
    local Compat = GuildOS.Compat
    local scope
    if self:IsMinimapDots() and not Compat.InstanceState() then
        local map = Compat.GetBestMapForUnit("player")
        local zone = map and self:_ZoneOf(map)
        if zone and self:_ZoneHasGuildmates(zone) then scope = zone end
    end
    self:SetWatch("minimap", scope)
end

-- Once a second: renew this client's watch, owe its watchers a position, forget the stale.
function GuildMap:Tick()
    local t = now()
    self:_Prune(t)
    self:_UpdateMinimapWatch()
    if self._pinged and t - (self._pingAt or 0) >= self.WATCH_PING then self:_Ping(t) end
    if next(self.watchers) then self:_MaybeSend(t) end
end

-- A zone change: the one line that goes unwatched (at most every WHERE_GAP seconds).
function GuildMap:OnZoneEvent()
    chains, infos, zones, yards = {}, {}, {}, {}
    GuildOS.Compat.After(2, function() GuildMap:_MaybeSend(now(), true) end)
    if self.uiRefresh then self.uiRefresh() end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function GuildMap:Initialize()
    local db = GuildOS.db
    db.mapPeers = nil   -- positions are live only; the old map's saved peers are not read (B23)
    if type(GuildOSDB) == "table" then GuildOSDB.openMapNotice = nil end   -- (the test builds' OpenMap notice, gone)
    prefs()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "ZONE_CHANGED_NEW_AREA")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_ENTERING_WORLD")
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(_, event)
        if event == "GUILD_ROSTER_UPDATE" then GuildMap._rosterStale = true; return end
        GuildMap:OnZoneEvent()
    end)
    self._frame = f
    -- OpenMap's lines: read only (HandleOpenMap). Registering the prefix sends nothing.
    pcall(GuildOS.Compat.RegisterAddonPrefix, self.OPENMAP_PREFIX)
    local om = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(om, "CHAT_MSG_ADDON")
    om:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
        if prefix ~= GuildMap.OPENMAP_PREFIX or GuildOS.Compat.IsSecret(text, channel, sender) then return end
        GuildOS:SafeCall(GuildMap.HandleOpenMap, GuildMap, sender, text, channel)
    end)
    self._openMapFrame = om
    self:_ListenCamps()   -- guildmates' campfires (WoW: Forever)
    self._ticker = GuildOS.Compat.NewTicker(1, function() GuildOS:SafeCall(GuildMap.Tick, GuildMap) end)
end
