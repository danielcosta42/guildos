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

local VERSION = 2
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

CN.peers     = CN.peers or {}     -- [shortName] = { addons=set, class, level, caps, ts }
CN.providers = CN.providers or {} -- [tag] = { caps=function|nil, onPeer=function|nil }

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

-- CHN1|H|<addons +joined>|<class>|<level>|<caps ,joined>
function CN:BuildHello()
    local _, class = UnitClass("player")
    local level = UnitLevel("player") or 0
    return table.concat({
        CN.PROTO, "H", LocalTags(), class or "", tostring(level), MergedCaps(),
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
    local proto, op, addons, class, level, caps = strsplit("|", payload)
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
    local isNew = CN.peers[short] == nil
    CN.peers[short] = {
        addons = set,
        class  = (class ~= "" and class) or nil,
        level  = tonumber(level),
        caps   = caps or "",
        ts     = time(),
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
-- Bootstrap: register our receive handler with the mesh + start on login.
-- ---------------------------------------------------------------------------
if Mesh then
    Mesh:Register(CN.PREFIX, OnHello)
end

CN.frame = CN.frame or CreateFrame("Frame")
CN.frame:RegisterEvent("PLAYER_LOGIN")
CN.frame:SetScript("OnEvent", function() CN:Start() end)
if C_Timer and C_Timer.After then
    C_Timer.After(8, function() CN:Start() end)
end

return CN
