-- ChehulNet - shared cross-addon presence handshake for the Chehul addon family
-- (PartyLens, ProfessionHelper, GuildOS). SHIP THIS FILE IDENTICAL in each addon.
--
-- A single instance lives at _G.ChehulNet: whichever addon loads first creates it,
-- the rest reuse it and call ChehulNet:Register(tag, capsFn, onPeer). Every addon
-- stays fully standalone; when two are present (same account, or same realm/guild)
-- they recognise each other and can enrich (e.g. "this player is also a crafter").
--
-- Transport is the hardened, delivering bus set (guild + group + SAY proximity;
-- CHANNEL addon messages are blocked on this client). A handshake's realm-wide
-- reach is inherently bounded to those buses - that is by design, not a bug.

local VERSION = 1

-- A sibling addon already loaded an equal/newer ChehulNet: reuse it, do nothing.
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

-- ---------------------------------------------------------------------------
-- Low-level send (hidden addon message; never throws).
-- ---------------------------------------------------------------------------
local function RawSend(payload, dist, target)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if fn then
        pcall(fn, CN.PREFIX, payload, dist, target)
    end
end

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
    if not next(CN.providers) then
        return
    end
    local payload = self:BuildHello()
    if IsInGuild and IsInGuild() then
        RawSend(payload, "GUILD")
    end
    if IsInGroup and IsInGroup() then
        RawSend(payload, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
    end
    RawSend(payload, "SAY") -- proximity (city / auction-house hubs)
end

function CN:Prune()
    local now = time()
    for name, p in pairs(CN.peers) do
        if (now - (p.ts or 0)) > CN.PEER_TTL then
            CN.peers[name] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Inbound handshake.
-- ---------------------------------------------------------------------------
function CN:OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= CN.PREFIX or not sender or type(text) ~= "string" then
        return
    end
    local proto, op, addons, class, level, caps = strsplit("|", text)
    if proto ~= CN.PROTO then
        return
    end
    local short = (Ambiguate and Ambiguate(sender, "short")) or sender
    if short == MyShortName() then
        return -- ignore our own broadcast
    end
    if op == "H" then
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
        -- Reply once to a newcomer heard via a broadcast (not a whisper), so
        -- discovery is two-way even without a shared guild. Their whispered reply
        -- carries channel == "WHISPER", so it never triggers another reply.
        if isNew and channel ~= "WHISPER" then
            RawSend(self:BuildHello(), "WHISPER", sender)
        end
        for _, p in pairs(CN.providers) do
            if p.onPeer then
                pcall(p.onPeer, short, CN.peers[short])
            end
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

-- Count peers heard, optionally only those running a given addon tag.
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
-- Bootstrap: register the prefix + one shared event frame.
-- ---------------------------------------------------------------------------
do
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if reg then
        pcall(reg, CN.PREFIX)
    end

    CN.frame = CN.frame or CreateFrame("Frame")
    CN.frame:RegisterEvent("CHAT_MSG_ADDON")
    CN.frame:RegisterEvent("PLAYER_LOGIN")
    CN.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            CN:OnAddonMessage(...)
        elseif event == "PLAYER_LOGIN" then
            CN:Start()
        end
    end)

    -- If we somehow loaded after PLAYER_LOGIN, start anyway.
    if C_Timer and C_Timer.After then
        C_Timer.After(8, function() CN:Start() end)
    end
end
