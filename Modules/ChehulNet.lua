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
-- v4: receives ChehulAlert broadcasts and shows a dismissible popup in the host addon's
-- identity (CN:EnableAlerts{accent,title,priority,store}). One popup per client (highest
-- priority wins); "Dismiss" persists the alert id so it never shows again.
-- v5: alert popups are gated to an ALLOWLIST of sender names (CN.ALERT_SENDERS) — only the
-- operator's own characters can fire a popup. Names are unique per realm and the alert
-- buses are realm-local, so this is, in practice, "only alerts from the backoffice I run".

local VERSION = 5
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
-- Network alerts: receive a ChehulAlert broadcast and show a dismissible popup styled in
-- the HOST addon's identity. An addon opts in via:
--   CN:EnableAlerts{ accent={r,g,b}, title="PartyLens", priority=3, store=function() return tbl end }
-- Highest priority wins, so with several Chehul addons installed exactly ONE popup shows.
-- `store()` returns the addon's SavedVariables table of forever-dismissed alert ids.
-- ---------------------------------------------------------------------------
CN.ALERT_PREFIX = "ChehulAlert"
CN.alertSeen = CN.alertSeen or {} -- [key]=true, dedupe re-broadcasts within a session
-- ONLY these characters (lowercased short names) may fire an alert popup — everyone else is
-- ignored. Character names are unique per realm and the alert buses are realm-local, so in
-- practice this is "only alerts from the operator's own backoffice". Edit to add operator alts.
CN.ALERT_SENDERS = CN.ALERT_SENDERS or { ["chehul"] = true }

function CN:EnableAlerts(opts)
    if type(opts) ~= "table" or type(opts.store) ~= "function" then
        return
    end
    if CN._alert and (opts.priority or 0) <= (CN._alert.priority or 0) then
        return
    end
    CN._alert = {
        accent   = opts.accent or { 0.208, 0.941, 0.773 },
        title    = opts.title or "ChehulNet",
        priority = opts.priority or 0,
        store    = opts.store,
    }
end

local alertFrame
local function EnsureAlertFrame()
    if alertFrame then
        return alertFrame
    end
    local fr = CreateFrame("Frame", "ChehulNetAlertPopup", UIParent)
    fr:SetSize(384, 136)
    fr:SetPoint("TOP", 0, -150)
    fr:SetFrameStrata("DIALOG")
    fr:SetToplevel(true)
    fr:EnableMouse(true)
    fr:SetMovable(true)
    fr:RegisterForDrag("LeftButton")
    fr:SetScript("OnDragStart", fr.StartMoving)
    fr:SetScript("OnDragStop", fr.StopMovingOrSizing)
    fr.bg = fr:CreateTexture(nil, "BACKGROUND"); fr.bg:SetAllPoints()
    fr.bg:SetColorTexture(0.035, 0.047, 0.063, 0.97)
    fr.edges = {}
    local edgeDef = {
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    for _, d in ipairs(edgeDef) do
        local t = fr:CreateTexture(nil, "BORDER")
        t:SetPoint(d[1]); t:SetPoint(d[2])
        if d[3] then t:SetWidth(d[3]) end
        if d[4] then t:SetHeight(d[4]) end
        fr.edges[#fr.edges + 1] = t
    end
    fr.topbar = fr:CreateTexture(nil, "ARTWORK")
    fr.topbar:SetPoint("TOPLEFT", 1, -1); fr.topbar:SetPoint("TOPRIGHT", -1, -1); fr.topbar:SetHeight(3)
    fr.title = fr:CreateFontString(nil, "OVERLAY"); fr.title:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    fr.title:SetPoint("TOPLEFT", 14, -13)
    fr.from = fr:CreateFontString(nil, "OVERLAY"); fr.from:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    fr.from:SetPoint("TOPLEFT", 14, -32); fr.from:SetTextColor(0.55, 0.60, 0.66, 1)
    fr.msg = fr:CreateFontString(nil, "OVERLAY"); fr.msg:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fr.msg:SetPoint("TOPLEFT", 14, -52); fr.msg:SetPoint("RIGHT", -14, 0)
    fr.msg:SetJustifyH("LEFT"); fr.msg:SetHeight(42); fr.msg:SetTextColor(0.82, 0.85, 0.89, 1)
    -- Dismiss (never again).
    fr.dismiss = CreateFrame("Button", nil, fr)
    fr.dismiss:SetSize(210, 22); fr.dismiss:SetPoint("BOTTOMLEFT", 14, 12)
    fr.dismiss.bg = fr.dismiss:CreateTexture(nil, "BACKGROUND"); fr.dismiss.bg:SetAllPoints()
    fr.dismiss.txt = fr.dismiss:CreateFontString(nil, "OVERLAY")
    fr.dismiss.txt:SetFont("Fonts\\FRIZQT__.TTF", 11, ""); fr.dismiss.txt:SetPoint("CENTER")
    fr.dismiss.txt:SetText("Dismiss — don't show again")
    -- Close (this time only).
    fr.close = CreateFrame("Button", nil, fr); fr.close:SetSize(22, 22); fr.close:SetPoint("TOPRIGHT", -4, -4)
    fr.close.txt = fr.close:CreateFontString(nil, "OVERLAY")
    fr.close.txt:SetFont("Fonts\\FRIZQT__.TTF", 16, ""); fr.close.txt:SetPoint("CENTER")
    fr.close.txt:SetText("\195\151"); fr.close.txt:SetTextColor(0.75, 0.4, 0.4, 1)
    fr.close:SetScript("OnClick", function() fr:Hide() end)
    fr:Hide()
    alertFrame = fr
    return fr
end

function CN:ShowAlert(key, text, sender)
    if not CN._alert then
        return
    end
    local acc = CN._alert.accent
    local fr = EnsureAlertFrame()
    fr.topbar:SetColorTexture(acc[1], acc[2], acc[3], 0.9)
    for _, t in ipairs(fr.edges) do t:SetColorTexture(acc[1], acc[2], acc[3], 0.55) end
    fr.title:SetText(CN._alert.title .. "  \194\183  network alert")
    fr.title:SetTextColor(acc[1], acc[2], acc[3], 1)
    fr.from:SetText("from " .. (sender or "?"))
    fr.msg:SetText(text or "")
    fr.dismiss.bg:SetColorTexture(acc[1], acc[2], acc[3], 0.18)
    fr.dismiss.txt:SetTextColor(acc[1], acc[2], acc[3], 1)
    fr.dismiss:SetScript("OnClick", function()
        local ok, store = pcall(CN._alert.store)
        if ok and type(store) == "table" then store[key] = true end
        fr:Hide()
    end)
    fr:Show()
    if PlaySound then pcall(PlaySound, 8959) end -- RaidWarning
end

local function OnAlert(payload, sender)
    if type(payload) ~= "string" then
        return
    end
    local kind, id, text = strsplit("|", payload)
    if kind ~= "ALERT" or not id or id == "" then
        return
    end
    local short = (Ambiguate and Ambiguate(sender or "", "short")) or sender
    if not short or short == MyShortName() then
        return -- ignore my own alert
    end
    if not CN.ALERT_SENDERS[short:lower()] then
        return -- not an authorized alert sender (only the operator's chars pop up)
    end
    local key = short .. "#" .. id
    if CN.alertSeen[key] then
        return -- already handled this alert this session (it re-broadcasts on a timer)
    end
    CN.alertSeen[key] = true
    if not CN._alert then
        return -- no host addon registered a display on this client
    end
    local ok, store = pcall(CN._alert.store)
    if ok and type(store) == "table" and store[key] then
        return -- dismissed forever
    end
    CN:ShowAlert(key, text or "", short)
end

-- ---------------------------------------------------------------------------
-- Bootstrap: register our receive handler with the mesh + start on login. Also drive
-- the built-in layer detector off target/mouseover (a no-op when a provider is set).
-- ---------------------------------------------------------------------------
if Mesh then
    Mesh:Register(CN.PREFIX, OnHello)
    Mesh:Register(CN.PING_PREFIX, OnPing)
    Mesh:Register(CN.ALERT_PREFIX, OnAlert)
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
