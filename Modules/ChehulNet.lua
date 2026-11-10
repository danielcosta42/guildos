-- ChehulNet - shared cross-addon presence handshake for the Chehul addon family
-- (PartyLens, ProfessionHelper, GuildOS). SHIP THIS FILE IDENTICAL in each addon.
--
-- A single instance lives at _G.ChehulNet; whichever addon loads first creates it,
-- the rest reuse it and call ChehulNet:Register(tag, capsFn, onPeer). Every addon
-- stays fully standalone; when two are present they recognise each other.
--
-- Transport is LibChehulMesh (_G.ChehulMesh): presence rides guild + group + SAY
-- proximity AND the realm-wide dedicated channel, so a HELLO reaches the whole
-- realm/faction, not just your guild. A group answers on first contact; the rest meet on the heartbeat.
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
-- v6: the operator now SEES their own alert too (no self-skip) — confirmation it went out +
-- solo-testable. Still deduped by id, still allowlist-gated.
-- v7: the alert is now a QUIET, persistent top BANNER (no sound, no big centered popup) —
-- subtle but always visible until the operator clicks × (dismiss forever).
-- v8: WoW: Forever. A client knows itself by its full name ("First Surname", the way every
-- addon-message sender arrives), not by UnitName's first name: v7 took its own HELLO for a peer's
-- and answered itself. ALERT_SENDERS names the operator's characters in full, and a v8 loading
-- after a v7 adds them to the list it finds.
-- v9: retail. There UnitFullName's second slot is the realm, whatever ShouldDisplaySurname says, so
-- a retail client knows itself by UnitName: v8 could read "Name Realm" as a name and surname.
-- v10: launch day. A HELLO heard on a wide bus (GUILD, SAY, YELL) is no longer answered by whisper:
-- 500 clients on a realm would send each other some 125k whispers after a restart, and the peer's
-- own heartbeat brings the same news within HELLO_INTERVAL. A group's audience is bounded, so a
-- groupmate is still answered at once. A HELLO's level counts only as a whole number from 1 to 255.
-- v11: DIAG, for the backoffice (the CehulNet addon). "DIAG|<id>|<sent>" on ChehulPing is answered by
-- whisper "DIAGR|<id>|<arrivalDist>|k=v;k=v": the lib versions this client runs, the mesh's counters,
-- its layer, instance and chat lockdown, plus what each host adds through CN:RegisterDiag(tag, fn).
-- Only the operator's characters (ALERT_SENDERS) are answered, each id once; one heard on a wide bus
-- waits a random 0-DIAG_JITTER seconds, so a census never lands as one burst. ALERT_SENDERS gains
-- "Chehul Lightdrizzle", the operator's character on WoW: Forever.
-- v12: the DIAG also says the client's guild, how many peers it heard on GUILD within PEER_TTL (gpeers) and how
-- many of those are in the mesh's directory (gdir). The directory lists only clients with LibChehulMesh v5+, and a
-- guild is where an older client is still heard; so the backoffice can estimate the whole network from the
-- directory and the share each guild has updated. A peer remembers when it was last heard on GUILD (gts), since a
-- HELLO whispered through the directory comes in later and would otherwise hide that.
-- v13 (chehulnet#1): the Forever server refused the directory's channel, and LibChehulMesh v7 reaches outside the
-- guild through peers it heard instead. The DIAG says how many fresh peers the mesh knows (view) and why the
-- directory is refused (dirx, empty when it is not).
-- v14 (chehulnet#3): LibChehulMesh v8 relays realm items and needs to know which peers take the relay. The HELLO's
-- caps carry the mesh version (mv=), and a HELLO heard tells the mesh the peer's addons and version (Mesh:Tag), so
-- a host can ask the mesh for the peers running it (Mesh:Peers(tag)). The DIAG says how many confirmed links the
-- mesh holds (links), how many peers take the relay (v8), what the relay did (rl=in/out/fwd/guild/dup) and the
-- last traces (trace=id:seconds:hops,..., newest first). CN:Trace() sends a trace by the relay; the backoffice reads
-- its reach in the DIAGs.
-- v15 (chehulnet#5): LibChehulMesh v9 brakes when its whispers keep finding nobody and keeps one directory per
-- ruleset. The DIAG says how many "No player named" the mesh got within its window (nf), whether the brake is on
-- (trip), which channel the directory uses (dirch) and how old its list is in seconds (dirage, empty before a read).

local VERSION = 15
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
CN.REPLY_ON       = { PARTY = true, RAID = true, INSTANCE_CHAT = true } -- buses a new peer is answered on

CN.peers     = CN.peers or {}     -- [shortName] = { addons=set, class, level, caps, mapID, zoneUID, ts }
CN.providers = CN.providers or {} -- [tag] = { caps=function|nil, onPeer=function|nil }
CN.layer     = CN.layer or { mapID = 0, zoneUID = 0 } -- built-in detection (non-PL addons)

local Mesh = _G.ChehulMesh -- shared transport (loaded before this file)

-- A retail client: the mainline project past interface 100000, the two signals GuildOS's
-- Client.isRetail reads (WoW: Forever may answer the mainline id; its interface is 16001). This
-- file ships identical in other addons and cannot ask GuildOS, so it reads them itself (v9).
local function IsRetail()
    local interface = GetBuildInfo and select(4, GetBuildInfo())
    return WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and (tonumber(interface) or 0) >= 100000
end

-- My own name as every addon-message sender writes it. On WoW: Forever UnitName gives the first
-- name only, and UnitFullName returns the first name and the surname apart (the realm, elsewhere;
-- never a surname on retail, as GuildOS's Client.has.surnames says).
local function MyShortName()
    if not IsRetail() and C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname and C_PlayerInfo.ShouldDisplaySurname() then
        local first, surname = UnitFullName("player")
        local secret = issecretvalue and (issecretvalue(first) or issecretvalue(surname))
        if not secret and first and surname and surname ~= "" then
            return first .. " " .. surname
        end
    end
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
    if Mesh and tonumber(Mesh.version) then
        parts[1] = "mv=" .. Mesh.version -- v14: the relay goes in an envelope only to peers whose mesh takes it
    end
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
    -- A restricted unit's GUID is a secret value; it cannot be split, so no layer is read from it.
    if not guid or (issecretvalue and issecretvalue(guid)) then
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

-- A level off the network: a whole number in range or nothing (tonumber lets "inf" and "nan" through).
local function HelloLevel(level)
    local n = tonumber(level)
    if n and n >= 1 and n <= 255 and n == math.floor(n) then
        return n
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
    if Mesh and Mesh.Tag then
        pcall(Mesh.Tag, Mesh, sender, set, caps and ("," .. caps):match(",mv=(%d+)")) -- v14
    end
    local old = CN.peers[short]
    local isNew = old == nil
    CN.peers[short] = {
        addons  = set,
        class   = (class ~= "" and class) or nil,
        level   = HelloLevel(level),
        caps    = caps or "",
        mapID   = mapID,
        zoneUID = zoneUID,
        ts      = time(),
        gts     = (dist == "GUILD") and time() or (old and old.gts) or nil, -- last heard on GUILD (v12)
    }
    -- Reply once to a newcomer heard in the group, so discovery there is two-way at once. Wider
    -- buses wait for the heartbeat; a whispered reply arrives as "WHISPER" -> no ping-pong.
    if isNew and CN.REPLY_ON[dist] and Mesh then
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
CN.DIAG_JITTER = 4                  -- seconds a DIAG heard on a wide bus may wait before its answer
CN.diag        = CN.diag or {}      -- [tag] = fn() -> "k=v;k=v" (host-specific health, v11)
CN.diagSeen    = CN.diagSeen or {}  -- [id] = true: each DIAG id is answered once
CN._t0         = CN._t0 or (GetTime and GetTime()) or 0

-- A host adds its own health to the DIAG answer (keys go out prefixed with the tag).
function CN:RegisterDiag(tag, fn)
    if type(tag) == "string" and tag ~= "" and type(fn) == "function" then
        CN.diag[tag] = fn
    end
end

function CN:BuildDiag()
    local s = (Mesh and Mesh.stats) or {}
    local ace = LibStub and LibStub("AceComm-3.0", true)
    local ctl = _G.ChatThrottleLib
    local mapID, zoneUID = CN:MyLayer()
    local build = GetBuildInfo and select(2, GetBuildInfo())
    local lock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local peers = 0
    for _ in pairs(CN.peers) do
        peers = peers + 1
    end
    local parts = {
        "cn=" .. CN.version, "mesh=" .. ((Mesh and Mesh.version) or 0), "ace=" .. (ace and 1 or 0),
        "ctl=" .. ((ctl and ctl.version) or 0), "ctlq=" .. ((ctl and ctl.bQueueing) and 1 or 0),
        "tags=" .. LocalTags(), "ok=" .. (s.ok or 0), "fail=" .. (s.fail or 0), "recv=" .. (s.recv or 0),
        "yell=" .. (s.yell or 0), "rq=" .. (s.realmQueued or 0), "rs=" .. (s.realmSent or 0),
        "rd=" .. (s.realmDropped or 0), "qn=" .. ((Mesh and Mesh._realmQueueCount) or 0), "peers=" .. peers,
        "layer=" .. (mapID or 0) .. ":" .. (zoneUID or 0), "map=" .. (tonumber(map) or 0),
        "inst=" .. ((IsInInstance and IsInInstance()) and 1 or 0), "lock=" .. (lock and 1 or 0),
        "up=" .. math.floor(((GetTime and GetTime()) or 0) - CN._t0), "build=" .. tostring(build or "?"),
        "refused=" .. (s.refused or 0), "dirSent=" .. (s.dirSent or 0),
        "dir=" .. ((Mesh and Mesh.dir and Mesh.dir.count) or 0),
        "view=" .. ((Mesh and Mesh.PeerCount and Mesh:PeerCount()) or 0),
        "dirx=" .. (tostring((Mesh and Mesh.dir and Mesh.dir.refused) or ""):gsub("[|;=]", " ")),
        "links=" .. ((Mesh and Mesh.LinkCount and Mesh:LinkCount()) or 0),
        "nf=" .. ((Mesh and Mesh.NotFoundCount and Mesh:NotFoundCount()) or 0),
        "trip=" .. ((Mesh and Mesh.Tripped and Mesh:Tripped()) and 1 or 0),
        "dirch=" .. (tostring((Mesh and Mesh.dir and Mesh.dir.channel) or ""):gsub("[|;=]", " ")),
        "dirage=" .. ((Mesh and Mesh.dir and tonumber(Mesh.dir.at)) and (time() - Mesh.dir.at) or ""),
        "v8=" .. ((Mesh and Mesh.V8Count and Mesh:V8Count()) or 0),
        "rl=" .. table.concat({ s.rlIn or 0, s.rlOut or 0, s.rlFwd or 0, s.rlGuild or 0, s.rlDup or 0 }, "/"),
        "trace=" .. (function()
            local out = {}
            for i, t in ipairs(CN.traces) do out[i] = table.concat({ t.id, t.secs, t.hops }, ":") end
            return table.concat(out, ",")
        end)(),
    }
    local dead = {}
    for dist in pairs((Mesh and Mesh.dead) or {}) do
        dead[#dead + 1] = dist
    end
    table.sort(dead)
    parts[#parts + 1] = "dead=" .. table.concat(dead, "+")
    -- v12: the guild, its peers heard on GUILD, and how many of them are in the directory.
    local guild = IsInGuild and IsInGuild() and GetGuildInfo and GetGuildInfo("player")
    local inDir = {}
    for _, name in ipairs((Mesh and Mesh.dir and Mesh.dir.names) or {}) do
        inDir[(Ambiguate and Ambiguate(name, "short")) or name] = true
    end
    local gpeers, gdir, cutoff = 0, 0, time() - CN.PEER_TTL
    for name, p in pairs(CN.peers) do
        if (p.gts or 0) >= cutoff then
            gpeers = gpeers + 1
            if inDir[name] then
                gdir = gdir + 1
            end
        end
    end
    parts[#parts + 1] = "guild=" .. ((type(guild) == "string" and guild:gsub("[|;=]", " ")) or "")
    parts[#parts + 1] = "gpeers=" .. gpeers
    parts[#parts + 1] = "gdir=" .. gdir
    for tag, fn in pairs(CN.diag) do
        local ok, extra = pcall(fn)
        if ok and type(extra) == "string" then
            for kv in extra:gmatch("[^;]+") do
                parts[#parts + 1] = tag .. "." .. (kv:gsub("|", " "))
            end
        end
    end
    return table.concat(parts, ";")
end

local function OnPing(payload, sender, dist)
    if type(payload) ~= "string" or not sender or not Mesh then
        return
    end
    local kind, id, sent = strsplit("|", payload)
    if kind == "PING" then
        Mesh:Whisper(CN.PING_PREFIX,
            table.concat({ "PONG", id or "?", sent or "0", dist or "?" }, "|"), sender)
    elseif kind == "DIAG" and id and id ~= "" and not CN.diagSeen[id] then
        local short = (Ambiguate and Ambiguate(sender, "short")) or sender
        if not CN.ALERT_SENDERS[short:lower()] then
            return -- only the operator's backoffice is told a node's health
        end
        CN.diagSeen[id] = true
        local function answer()
            Mesh:Whisper(CN.PING_PREFIX, table.concat({ "DIAGR", id, dist or "?", CN:BuildDiag() }, "|"), sender)
        end
        if dist == "WHISPER" or not (C_Timer and C_Timer.After) then
            answer()
        else
            C_Timer.After(math.random() * CN.DIAG_JITTER, answer)
        end
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
-- On WoW: Forever a name is "First Surname", unique per region: the first name alone is anybody's.
-- Added to whatever an older copy left, which is what a v8 loading after a v7 finds.
CN.ALERT_SENDERS = CN.ALERT_SENDERS or {}
for _, name in ipairs({ "chehul", "chehul costa", "chehul druida", "chehul shammy", "chehul lightdrizzle" }) do
    CN.ALERT_SENDERS[name] = true
end

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

-- A QUIET, persistent top banner (not a loud centered popup, no sound). Stays visible
-- until the operator clicks × (which dismisses the id forever). Themed by the host addon's
-- accent (a thin left bar + hairline underline + the addon name in its colour).
local alertFrame
local function EnsureAlertFrame()
    if alertFrame then
        return alertFrame
    end
    local fr = CreateFrame("Frame", "ChehulNetAlertBanner", UIParent)
    fr:SetSize(460, 28)
    fr:SetPoint("TOP", 0, -6)
    fr:SetFrameStrata("HIGH")
    fr:EnableMouse(true)
    fr:SetMovable(true)
    fr:RegisterForDrag("LeftButton")
    fr:SetScript("OnDragStart", fr.StartMoving)
    fr:SetScript("OnDragStop", fr.StopMovingOrSizing)
    fr.bg = fr:CreateTexture(nil, "BACKGROUND"); fr.bg:SetAllPoints()
    fr.bg:SetColorTexture(0.04, 0.05, 0.07, 0.86)
    fr.accentBar = fr:CreateTexture(nil, "ARTWORK")
    fr.accentBar:SetPoint("TOPLEFT"); fr.accentBar:SetPoint("BOTTOMLEFT"); fr.accentBar:SetWidth(3)
    fr.underline = fr:CreateTexture(nil, "ARTWORK")
    fr.underline:SetPoint("BOTTOMLEFT"); fr.underline:SetPoint("BOTTOMRIGHT"); fr.underline:SetHeight(1)
    fr.title = fr:CreateFontString(nil, "OVERLAY"); fr.title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    fr.title:SetPoint("LEFT", 12, 0)
    fr.msg = fr:CreateFontString(nil, "OVERLAY"); fr.msg:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    fr.msg:SetPoint("LEFT", fr.title, "RIGHT", 8, 0); fr.msg:SetPoint("RIGHT", -28, 0)
    fr.msg:SetJustifyH("LEFT"); fr.msg:SetWordWrap(false); fr.msg:SetTextColor(0.82, 0.85, 0.89, 1)
    -- × = dismiss forever (there's no "close for now" — the banner lives until dismissed).
    fr.close = CreateFrame("Button", nil, fr); fr.close:SetSize(20, 20); fr.close:SetPoint("RIGHT", -5, 0)
    fr.close.txt = fr.close:CreateFontString(nil, "OVERLAY")
    fr.close.txt:SetFont("Fonts\\FRIZQT__.TTF", 14, ""); fr.close.txt:SetPoint("CENTER")
    fr.close.txt:SetText("\195\151"); fr.close.txt:SetTextColor(0.55, 0.60, 0.66, 1)
    fr.close:SetScript("OnEnter", function() fr.close.txt:SetTextColor(0.9, 0.5, 0.5, 1) end)
    fr.close:SetScript("OnLeave", function() fr.close.txt:SetTextColor(0.55, 0.60, 0.66, 1) end)
    fr:Hide()
    alertFrame = fr
    return fr
end

function CN:ShowAlert(key, text)
    if not CN._alert then
        return
    end
    local acc = CN._alert.accent
    local fr = EnsureAlertFrame()
    fr.accentBar:SetColorTexture(acc[1], acc[2], acc[3], 0.95)
    fr.underline:SetColorTexture(acc[1], acc[2], acc[3], 0.35)
    fr.title:SetText(CN._alert.title)
    fr.title:SetTextColor(acc[1], acc[2], acc[3], 1)
    fr.msg:SetText(text or "")
    fr.close:SetScript("OnClick", function()
        local ok, store = pcall(CN._alert.store)
        if ok and type(store) == "table" then store[key] = true end
        fr:Hide()
    end)
    fr:Show() -- quiet + persistent: no sound, stays until × (dismiss forever)
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
    if not short then
        return
    end
    if not CN.ALERT_SENDERS[short:lower()] then
        return -- not an authorized alert sender (only the operator's chars pop up)
    end
    -- NOTE: we intentionally DO NOT skip our own alert — the operator sees it too (over the
    -- YELL/SAY self-echo), as confirmation it went out and so a solo test works. Deduped by
    -- id, so a re-broadcast never re-pops it.
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
    CN:ShowAlert(key, text or "")
end

-- ---------------------------------------------------------------------------
-- Trace (v14): the operator sends one item by the relay; each client keeps the last one it took (id, seconds on the
-- way, hops left), and the backoffice's DIAG census reads the reach. A relayed trace's origin is claimed, so a
-- forged one cannot be told from the operator's: the DIAG keeps the last TRACE_KEEP fresh ones (TRACE_AGE) and the
-- backoffice looks for the id it sent. One whispered or said on GUILD (an authentic sender) is kept only from the operator. Server time on
-- both ends, so the seconds are the way and not two clocks apart.
-- ---------------------------------------------------------------------------
CN.TRACE_PREFIX = "ChehulTrace"
CN.TRACE_KEEP   = 5
CN.TRACE_AGE    = 600 -- a trace sent longer ago than this is stale: a forger cannot replay old ones
CN.traces       = CN.traces or {}

local function Now()
    return (GetServerTime and GetServerTime()) or time()
end

function CN:Trace()
    if not (Mesh and Mesh.Realm) then return nil end
    local id = string.format("%x", math.random(0, 0x7fffffff))
    local payload = table.concat({ "TR1", id, tostring(Now()) }, "|")
    Mesh:Guild(CN.TRACE_PREFIX, payload)
    Mesh:Realm(CN.TRACE_PREFIX, payload, CN.TRACE_PREFIX, true)
    return id
end

local function OnTrace(payload, sender, dist, _, hops)
    if type(payload) ~= "string" or type(sender) ~= "string" then return end
    if issecretvalue and (issecretvalue(payload) or issecretvalue(sender)) then return end
    local id, sent = payload:match("^TR1|(%x+)|(%d+)$")
    local short = (Ambiguate and Ambiguate(sender, "short")) or sender
    if not id or #id > 8 or (dist ~= "RELAY" and not CN.ALERT_SENDERS[short:lower()]) then return end
    if math.abs(Now() - tonumber(sent)) > CN.TRACE_AGE then return end
    for _, t in ipairs(CN.traces) do
        if t.id == id then return end -- the first copy is the one that counts
    end
    table.insert(CN.traces, 1, { id = id, secs = math.max(0, Now() - tonumber(sent)), hops = tonumber(hops) or "-" })
    CN.traces[CN.TRACE_KEEP + 1] = nil
end

-- ---------------------------------------------------------------------------
-- Bootstrap: register our receive handler with the mesh + start on login. Also drive
-- the built-in layer detector off target/mouseover (a no-op when a provider is set).
-- ---------------------------------------------------------------------------
if Mesh then
    Mesh:Register(CN.PREFIX, OnHello)
    Mesh:Register(CN.PING_PREFIX, OnPing)
    Mesh:Register(CN.ALERT_PREFIX, OnAlert)
    Mesh:Register(CN.TRACE_PREFIX, OnTrace)
    if Mesh.Relayable then Mesh:Relayable(CN.TRACE_PREFIX) end
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
