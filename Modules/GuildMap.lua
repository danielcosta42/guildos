----------------------------------------------------------------------
-- Guild OS - Live Guild Map (data + sync layer)
-- Shares where each guildmate is. ZONE level (mapID) is shared for
-- everyone while the feature is on; exact live x/y is an explicit OPT-IN
-- (db.guildMapPrefs.shareExact) and is NEVER sent inside an instance.
--
-- Security (same rules as LFGBoard / RECRUIT_STATS):
--   * Identity is the comm ENVELOPE sender, never the payload body:
--     db.mapPeers is keyed by the sender's Name-Realm, so a peer can only
--     ever place its OWN pin, never forge someone else's location.
--   * Accepted ONLY over GUILD (HandlePosition drops anything else), which
--     kills whisper/party position injection.
--   * Every incoming number is clamped: mapID must be a positive number and
--     x,y are clamped to [0,1], so a hostile or corrupt packet cannot break
--     the map UI.
--   * class/level come from the guild ROSTER (or the member DB cache), never
--     from the payload, so those cannot be spoofed either.
--   * Exact x/y is opt-in (shareExact) and instance-safe: it is only ever
--     SENT when the local player enabled it AND is not inside an instance.
----------------------------------------------------------------------
local GuildMap = {}
BRutus.GuildMap = GuildMap
local LibSerialize = LibStub("LibSerialize")

local PEER_TTL           = 300   -- drop a peer we have not heard from in 5 min
local BROADCAST_THROTTLE = 10    -- minimum seconds between our own position sends

-- True while the player is in any instance (dungeon/raid/BG/arena). Used to
-- guarantee exact coordinates never leak from inside an instance, on top of
-- C_Map already returning nil there.
local function inInstance()
    if IsInInstance then
        local isIn = IsInInstance()
        return isIn and true or false
    end
    return false
end

----------------------------------------------------------------------
-- Pure helpers (unit tested; take explicit inputs, touch no db/time/comm)
----------------------------------------------------------------------

-- Clamp one coordinate to [0,1]. nil / NaN / non-number all collapse to nil
-- (unknown), a value below 0 to 0 and above 1 to 1.
local function clamp01(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end   -- nil / not a number / NaN
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Normalize an incoming (mapID, x, y). The mapID must be a positive number or
-- the whole position is rejected (returns nil): a peer with no usable zone is
-- not placed. x,y are clamped to [0,1] and may be nil (zone-only). This is the
-- whole defence against a hostile packet feeding absurd coordinates to the UI.
function GuildMap:_ClampPos(mapID, x, y)
    mapID = tonumber(mapID)
    if not mapID or mapID ~= mapID then return nil end   -- nil / not a number / NaN
    mapID = math.floor(mapID)
    if mapID <= 0 then return nil end
    return mapID, clamp01(x), clamp01(y)
end

-- Sort a peer list in place by display name (case-insensitive), tie-broken by
-- key so two members with the same short name (connected realms) keep a stable,
-- total order and never swap rows between repaints. Returns the same list.
function GuildMap:_SortPeers(list)
    table.sort(list or {}, function(a, b)
        local an = (a.name or ""):lower()
        local bn = (b.name or ""):lower()
        if an ~= bn then return an < bn end
        return (a.key or "") < (b.key or "")
    end)
    return list
end

-- Drop peers whose last report is older than `ttl` (default PEER_TTL). Mutates
-- store in place; returns how many were removed. A row exactly ttl old is kept.
function GuildMap:_Prune(store, now, ttl)
    if not store then return 0 end
    now = now or 0
    ttl = ttl or PEER_TTL
    local removed = 0
    for k, e in pairs(store) do
        local ts = (type(e) == "table" and tonumber(e.ts)) or 0
        if (now - ts) > ttl then
            store[k] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Aggregate a fake-able store into the sorted list the UI renders. Pure
-- (explicit store + now + optional onlineSet + ttl) so a self test pins the
-- filter and sort. A peer is included only when it has a usable zone
-- (mapID > 0), its report is within ttl, and (if an onlineSet is given) it is
-- currently online. Each row: { key, name, mapID, x, y, exact, class, level,
-- ts }. x,y are nil for a zone-only peer.
function GuildMap:_ActivePeers(store, now, onlineSet, ttl)
    now = now or 0
    ttl = ttl or PEER_TTL
    local out = {}
    for key, e in pairs(store or {}) do
        if type(e) == "table" then
            local mid = tonumber(e.mapID)
            local ts = tonumber(e.ts) or 0
            if mid and mid > 0 and (now - ts) <= ttl
                and (not onlineSet or onlineSet[key]) then
                out[#out + 1] = {
                    key   = key,
                    name  = key:match("^([^-]+)") or key,
                    mapID = mid,
                    x     = e.x,
                    y     = e.y,
                    exact = e.exact and true or false,
                    class = e.class,
                    level = e.level,
                    ts    = e.ts,
                }
            end
        end
    end
    return self:_SortPeers(out)
end

----------------------------------------------------------------------
-- Roster lookups (impure: read the live roster / member DB, never the payload)
----------------------------------------------------------------------

-- class/level for a member key, resolved from the guild roster first
-- (authoritative) and the cached member DB as a fallback. Never trusts the
-- payload. Returns (classFile, level) or (nil, nil).
function GuildMap:_ResolveClassLevel(key)
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            if BRutus:GetPlayerKey(short, realm) == key then
                return classFile, level
            end
        end
    end
    local m = BRutus.db and BRutus.db.members and BRutus.db.members[key]
    if type(m) == "table" then return m.class, m.level end
    return nil, nil
end

-- { [key] = true } for every guild member currently online.
function GuildMap:_BuildOnlineSet()
    local set = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if name and isOnline then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            set[BRutus:GetPlayerKey(short, realm)] = true
        end
    end
    return set
end

----------------------------------------------------------------------
-- Local position read + broadcast
----------------------------------------------------------------------

-- Build this client's own compact position packet, or nil when there is no
-- usable zone yet (loading screen). Always carries the mapID; carries exact
-- x,y ONLY when the player enabled shareExact and is not inside an instance.
function GuildMap:_ReadPosition()
    local mapID = tonumber(BRutus.Compat.GetBestMapForUnit("player"))
    if not mapID or mapID <= 0 then return nil end
    local packet = { mapID = mapID, exact = false }
    local prefs = BRutus.db and BRutus.db.guildMapPrefs
    if prefs and prefs.shareExact and not inInstance() then
        local x, y = BRutus.Compat.GetPlayerMapPosition(mapID, "player")
        x, y = tonumber(x), tonumber(y)
        if x and y then
            packet.x = x
            packet.y = y
            packet.exact = true
        end
    end
    return packet
end

-- Send our own position over GUILD. Throttled to one send per BROADCAST_THROTTLE
-- seconds unless `force` (the login/periodic request answer, which must converge
-- a guildmate who just logged in). Returns true when a packet actually went out.
function GuildMap:Broadcast(force)
    if not BRutus.CommSystem or not IsInGuild() then return false end
    local now = GetTime()
    if not force and (now - (self._lastBroadcast or 0)) < BROADCAST_THROTTLE then
        return false
    end
    local packet = self:_ReadPosition()
    if not packet then return false end
    self._lastBroadcast = now
    BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.MAP_POS,
        LibSerialize:Serialize(packet))
    return true
end

-- Zone-change handler. Fires on ZONE_CHANGED_NEW_AREA / PLAYER_ENTERING_WORLD.
-- Leading-edge send, plus ONE trailing send scheduled at the end of the throttle
-- window so the final zone after a burst of rapid zone edges is still published
-- without a message per edge.
function GuildMap:OnZoneEvent()
    local now = GetTime()
    local elapsed = now - (self._lastBroadcast or 0)
    if elapsed >= BROADCAST_THROTTLE then
        self:Broadcast()
    elseif not self._pendingSend then
        self._pendingSend = true
        BRutus.Compat.After((BROADCAST_THROTTLE - elapsed) + 0.05, function()
            self._pendingSend = false
            self:Broadcast()
        end)
    end
end

----------------------------------------------------------------------
-- Receive
----------------------------------------------------------------------

-- Incoming position. Identity is the ENVELOPE sender (never the payload) and it
-- must arrive over GUILD. The entry is keyed by that sender, every number is
-- clamped, and class/level are pulled from the roster (not the packet), so a
-- member can only ever place its own pin and a hostile packet cannot break the
-- UI. exact is honored only when real coordinates survived the clamp.
function GuildMap:HandlePosition(sender, data, channel)
    if channel ~= "GUILD" then return end
    if not sender then return end
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end
    local mapID, x, y = self:_ClampPos(p.mapID, p.x, p.y)
    if not mapID then return end
    local short = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = BRutus:GetPlayerKey(short, realm)
    local class, level = self:_ResolveClassLevel(key)
    local exact = (p.exact == true) and x ~= nil and y ~= nil
    local now = time()
    BRutus.db.mapPeers = BRutus.db.mapPeers or {}
    BRutus.db.mapPeers[key] = {
        mapID = mapID,
        x     = exact and x or nil,
        y     = exact and y or nil,
        exact = exact,
        class = class,
        level = level,
        ts    = now,
    }
    self:_Prune(BRutus.db.mapPeers, now)
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Aggregate for the UI (thin wrapper over the pure _ActivePeers)
----------------------------------------------------------------------

-- Online guildmates with a known position, sorted by name. Task 2 (UI) renders
-- this. Returns rows shaped like _ActivePeers documents.
function GuildMap:GetPeers(now)
    now = now or time()
    local store = (BRutus.db and BRutus.db.mapPeers) or {}
    return self:_ActivePeers(store, now, self:_BuildOnlineSet(), PEER_TTL)
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function GuildMap:Initialize()
    BRutus.db.guildMapPrefs = BRutus.db.guildMapPrefs or {}
    if BRutus.db.guildMapPrefs.shareExact == nil then
        BRutus.db.guildMapPrefs.shareExact = false
    end
    BRutus.db.mapPeers = BRutus.db.mapPeers or {}
    self:_Prune(BRutus.db.mapPeers, time())

    local f = CreateFrame("Frame")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        GuildMap:OnZoneEvent()
    end)
    self._frame = f

    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Self tests (pure helpers only; no db/time/comm touched)
----------------------------------------------------------------------
function GuildMap:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    S:Register("guildmap.clamp_pos", function()
        local m, x, y = GuildMap:_ClampPos(1453, 0.5, 0.25)
        if m ~= 1453 or x ~= 0.5 or y ~= 0.25 then return false, "valid pos kept" end
        m, x, y = GuildMap:_ClampPos(1453, 1.7, -0.3)
        if m ~= 1453 or x ~= 1 or y ~= 0 then return false, "x,y clamped to [0,1]" end
        m, x, y = GuildMap:_ClampPos(1453, "nope", nil)
        if m ~= 1453 or x ~= nil or y ~= nil then return false, "garbage coords -> nil, map kept" end
        local nan = math.huge - math.huge
        if GuildMap:_ClampPos(nan, 0.5, 0.5) ~= nil then return false, "NaN mapID rejected" end
        if GuildMap:_ClampPos(0, 0.5, 0.5) ~= nil then return false, "zero mapID rejected" end
        if GuildMap:_ClampPos(-3, 0.5, 0.5) ~= nil then return false, "negative mapID rejected" end
        if GuildMap:_ClampPos("x", 0.5, 0.5) ~= nil then return false, "non-number mapID rejected" end
        if GuildMap:_ClampPos(nil, 0.5, 0.5) ~= nil then return false, "nil mapID rejected" end
        if GuildMap:_ClampPos(12.9, 0.5, 0.5) ~= 12 then return false, "mapID floored" end
        return true
    end)

    S:Register("guildmap.prune", function()
        local now = 1000000
        local store = {
            ["A-R"] = { mapID = 1, ts = now - 100 },
            ["B-R"] = { mapID = 1, ts = now - (PEER_TTL + 50) },
            ["C-R"] = { mapID = 1, ts = now - PEER_TTL },   -- exactly TTL: kept
        }
        local removed = GuildMap:_Prune(store, now)
        if removed ~= 1 then return false, "one stale dropped" end
        if store["A-R"] == nil then return false, "fresh kept" end
        if store["B-R"] ~= nil then return false, "stale dropped" end
        if store["C-R"] == nil then return false, "exactly TTL kept" end
        if GuildMap:_Prune(nil, now) ~= 0 then return false, "nil store safe" end
        return true
    end)

    S:Register("guildmap.sort_peers", function()
        local list = {
            { key = "Cara-R", name = "Cara" },
            { key = "ann-R",  name = "ann" },
            { key = "Bob-R",  name = "Bob" },
        }
        GuildMap:_SortPeers(list)
        if list[1].name ~= "ann" or list[2].name ~= "Bob" or list[3].name ~= "Cara" then
            return false, "case-insensitive name sort"
        end
        local tie = {
            { key = "Bob-RealmB", name = "Bob" },
            { key = "Bob-RealmA", name = "Bob" },
        }
        GuildMap:_SortPeers(tie)
        if tie[1].key ~= "Bob-RealmA" or tie[2].key ~= "Bob-RealmB" then
            return false, "equal names sort by key"
        end
        return true
    end)

    S:Register("guildmap.active_peers", function()
        local now = 2000000
        local store = {
            ["Ann-R"]   = { mapID = 1453, x = 0.5, y = 0.6, exact = true,  class = "MAGE",    level = 70, ts = now - 10 },
            ["Bob-R"]   = { mapID = 1454,                    exact = false, class = "WARRIOR", level = 68, ts = now - 20 },
            ["Old-R"]   = { mapID = 1453, ts = now - (PEER_TTL + 100) },   -- stale: dropped
            ["NoMap-R"] = { mapID = 0,    ts = now },                      -- no zone: dropped
            ["Off-R"]   = { mapID = 1453, ts = now },                      -- online filter drops
        }
        local online = { ["Ann-R"] = true, ["Bob-R"] = true, ["Old-R"] = true, ["NoMap-R"] = true }
        local peers = GuildMap:_ActivePeers(store, now, online, PEER_TTL)
        if #peers ~= 2 then return false, "stale / no-map / offline excluded" end
        if peers[1].name ~= "Ann" or peers[2].name ~= "Bob" then return false, "sorted by name" end
        if peers[1].exact ~= true or peers[1].x ~= 0.5 or peers[1].y ~= 0.6 then return false, "exact carried" end
        if peers[2].exact ~= false or peers[2].x ~= nil then return false, "zone-only peer has no coords" end
        if peers[1].class ~= "MAGE" or peers[1].level ~= 70 then return false, "class/level carried" end
        local all = GuildMap:_ActivePeers(store, now, nil, PEER_TTL)
        if #all ~= 3 then return false, "nil online set includes Off-R too" end
        return true
    end)
end
