-- ChehulNet - shared cross-addon presence handshake for the Chehul addon family
-- (PartyLens, ProfessionHelper, GuildOS). SHIP THIS FILE IDENTICAL in each addon.
--
-- A single instance lives at _G.ChehulNet; whichever addon loads first creates it,
-- the rest reuse it and call ChehulNet:Register(tag, capsFn, onPeer). Every addon
-- stays fully standalone; when two are present they recognise each other.
--
-- Transport is LibChehulMesh (_G.ChehulMesh): presence rides guild + group + SAY
-- proximity AND the realm-wide dedicated channel, so a HELLO reaches the whole
-- realm/faction, not just your guild. Discovery is two-way (reply on first contact).
--
-- v3: the HELLO now carries the sender's LAYER (mapID:zoneUID) so the whole mesh is
-- layer-aware, not just PartyLens users. Addons with real layer detection (PartyLens)
-- register CN.layerProvider; the rest use a built-in minimal detector (creature-GUID
-- field 5 = zoneUID) so GuildOS/ProfessionHelper users report their layer too.

local VERSION = 3
if _G.ChehulNet and (_G.ChehulNet.version or 0) >= VERSION then
    return
end

local CN = _G.ChehulNet or {}
_G.ChehulNet = CN

CN.version        = VERSION
CN.PREFIX         = "ChehulNet"
CN.PROTO          = "CHN1"
CN.HELLO_INTERVAL = 180 -- re-announce presence this often (seconds)
CN.PEER_TTL       = 600 -- forget a peer not heard within this

CN.peers     = CN.peers or {}     -- [shortName] = { addons=set, class, level, caps, mapID, zoneUID, ts }
CN.providers = CN.providers or {} -- [tag] = { caps=function|nil, onPeer=function|nil }
CN.layer     = CN.layer or { mapID = 0, zoneUID = 0 } -- built-in detection (non-PL addons)

local Mesh = _G.ChehulMesh -- shared transport (loaded before this file)

local function MyShortName()
    return UnitName("player") or ""
end

local function LocalTags()
    local tags = {}
    for tag in pairs(CN.providers) do
        tags[#tags + 1] = tag
    end
    table.sort(tags)
    return table.concat(tags, "+")
end

local function MergedCaps()
    local parts = {}
    for _, p in pairs(CN.providers) do
        if p.caps then
            local ok, c = pcall(p.caps)
            if ok and type(c) == "string" and c ~= "" then
                parts[#parts + 1] = c
            end
        end
    end
    return table.concat(parts, ",")
end

-- Our current layer as (mapID, zoneUID). A richer provider (PartyLens's Layer module,
-- NWB-aware) wins when registered; otherwise the built-in detector below fills CN.layer.
-- 0/0 = not detected yet (the receiver treats that as "layer unknown").
function CN:MyLayer()
    if CN.layerProvider then
        local ok, m, z = pcall(CN.layerProvider)
        if ok and type(z) == "number" and z > 0 then
            return m or 0, z
        end
        return 0, 0
    end
    return CN.layer.mapID or 0, CN.layer.zoneUID or 0
end

-- Minimal built-in layer detection (used ONLY when no provider is registered): field 5
-- of a non-player creature's GUID is its zoneUID = the physical layer. Same technique
-- PartyLens/NWB use, reimplemented here so cross-addon peers still report a layer.
local function DetectLayer(unit)
    if CN.layerProvider then
        return -- a richer provider (PartyLens) owns our layer
    end
    if not UnitExists(unit) or UnitIsPlayer(unit)
        or (UnitPlayerControlled and UnitPlayerControlled(unit)) then
        return
    end
    local guid = UnitGUID(unit)
    if not guid then
        return
    end
    local kind, _, _, _, zoneUID = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then
        return
    end
    zoneUID = tonumber(zoneUID)
    if not zoneUID or zoneUID == 0 then
        return
    end
    CN.layer.mapID = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 0
    CN.layer.zoneUID = zoneUID
end

-- CHN1|H|<addons +joined>|<class>|<level>|<caps ,joined>|<mapID>:<zoneUID>
-- caps may contain ':' and ',' (e.g. "craft:Enchanting,lfg") but never '|', and the
-- layer field is the LAST '|' field, so the two never collide.
function CN:BuildHello()
    local _, class = UnitClass("player")
    local level = UnitLevel("player") or 0
    local mapID, zoneUID = CN:MyLayer()
    return table.concat({
        CN.PROTO, "H", LocalTags(), class or "", tostring(level), MergedCaps(),
        tostring(mapID or 0) .. ":" .. tostring(zoneUID or 0),
    }, "|")
end

function CN:Announce()
    if not next(CN.providers) or not Mesh then
        return
    end
    local payload = self:BuildHello()
    Mesh:Guild(CN.PREFIX, payload)
    Mesh:Group(CN.PREFIX, payload)
    Mesh:Proximity(CN.PREFIX, payload)
    Mesh:Realm(CN.PREFIX, payload, CN.PREFIX .. ":hello") -- realm-wide (coalesced)
end

function CN:Prune()
    local now = time()
    for name, p in pairs(CN.peers) do
        if (now - (p.ts or 0)) > CN.PEER_TTL then
            CN.peers[name] = nil
        end
    end
end

-- Inbound HELLO (routed here by LibChehulMesh for our prefix).
local function OnHello(payload, sender, dist)
    if type(payload) ~= "string" or not sender then
        return
    end
    local proto, op, addons, class, level, caps, layer = strsplit("|", payload)
    if proto ~= CN.PROTO or op ~= "H" then
        return
    end
    local short = (Ambiguate and Ambiguate(sender, "short")) or sender
    if short == MyShortName() then
        return -- ignore our own broadcast
    end
    local set = {}
    for t in string.gmatch(addons or "", "[^+]+") do
        set[t] = true
    end
    -- Layer field (v3+, optional): "mapID:zoneUID". Absent from v1/v2 senders -> 0/0.
    local mapID, zoneUID = 0, 0
    if layer and layer ~= "" then
        local m, z = strsplit(":", layer)
        mapID, zoneUID = tonumber(m) or 0, tonumber(z) or 0
    end
    local isNew = CN.peers[short] == nil
    CN.peers[short] = {
        addons  = set,
        class   = (class ~= "" and class) or nil,
        level   = tonumber(level),
        caps    = caps or "",
        mapID   = mapID,
        zoneUID = zoneUID,
        ts      = time(),
    }
    -- Reply once to a newcomer we heard via broadcast (not a whisper), so discovery
    -- is two-way. Their whispered reply arrives as dist "WHISPER" -> no ping-pong.
    if isNew and dist ~= "WHISPER" and Mesh then
        Mesh:Whisper(CN.PREFIX, CN:BuildHello(), sender)
    end
    for _, p in pairs(CN.providers) do
        if p.onPeer then
            pcall(p.onPeer, short, CN.peers[short])
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public API (called by each addon's wiring).
-- ---------------------------------------------------------------------------
function CN:Register(tag, capsFn, onPeer)
    if type(tag) ~= "string" or tag == "" then
        return
    end
    CN.providers[tag] = { caps = capsFn, onPeer = onPeer }
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function() CN:Announce() end)
    end
end

function CN:Peers()
    return CN.peers
end

function CN:PeerRuns(name, tag)
    local short = (Ambiguate and Ambiguate(name or "", "short")) or name
    local p = short and CN.peers[short]
    return (p ~= nil) and (p.addons[tag] == true)
end

function CN:Count(tag)
    local n = 0
    for _, p in pairs(CN.peers) do
        if not tag or p.addons[tag] then
            n = n + 1
        end
    end
    return n
end

function CN:Start()
    if CN._started then
        return
    end
    CN._started = true
    if C_Timer then
        if C_Timer.After then
            C_Timer.After(5, function() CN:Announce() end)
        end
        if C_Timer.NewTicker then
            CN.ticker = C_Timer.NewTicker(CN.HELLO_INTERVAL, function()
                CN:Prune()
                CN:Announce()
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- ChehulPing responder — answers the backoffice's RTT probe, so a ping works against
-- ANY Chehul-addon user (PartyLens/GuildOS/ProfessionHelper), not just other backoffices.
--   origin -> "PING|<id>|<sent>"           (over whisper)
--   here   -> "PONG|<id>|<sent>|<arrivalDist>"  (echo the bus it arrived on = the PATH)
-- The origin matches <id>, computes RTT = now - <sent> (its own clock), and shows the
-- <arrivalDist> so you can SEE which bus reached this peer.
-- ---------------------------------------------------------------------------
CN.PING_PREFIX = "ChehulPing"
local function OnPing(payload, sender, dist)
    if type(payload) ~= "string" or not sender or not Mesh then
        return
    end
    local kind, id, sent = strsplit("|", payload)
    if kind == "PING" then
        Mesh:Whisper(CN.PING_PREFIX,
            table.concat({ "PONG", id or "?", sent or "0", dist or "?" }, "|"), sender)
    end
end

-- ---------------------------------------------------------------------------
-- Bootstrap: register our receive handler with the mesh + start on login. Also drive
-- the built-in layer detector off target/mouseover (a no-op when a provider is set).
-- ---------------------------------------------------------------------------
if Mesh then
    Mesh:Register(CN.PREFIX, OnHello)
    Mesh:Register(CN.PING_PREFIX, OnPing)
end

CN.frame = CN.frame or CreateFrame("Frame")
CN.frame:RegisterEvent("PLAYER_LOGIN")
CN.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
CN.frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
CN.frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        DetectLayer("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        DetectLayer("mouseover")
    else
        CN:Start()
    end
end)
if C_Timer and C_Timer.After then
    C_Timer.After(8, function() CN:Start() end)
end

return CN
