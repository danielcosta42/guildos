-- LibChehulMesh v4 - shared mesh for the Chehul addon family (PartyLens, GuildOS,
-- ProfessionHelper, Lodestar). SHIP THIS FILE IDENTICAL in each addon.
--
-- Transport is now AceComm-3.0 + ChatThrottleLib (bundled) — proper priority-based
-- rate limiting (no more disconnect-from-spam) + automatic message chunking (no more
-- manual byte budgets). One instance at _G.ChehulMesh; first addon to load wins.
--
-- BUSES (all automatic, all work from timers — measured on this client):
--   :Guild / :Group / :Proximity(SAY) / :Yell / :Whisper(target)   -> fire-and-forget
--   :Realm(prefix, payload [, key])  -> the WIDE bus. The old click-flushed CHANNEL is
--     DEAD here (timer channel-send is gated; the click-flush delivered 0 in practice),
--     so realm-wide now rides YELL — zone-wide (whole city, >> SAY's ~40yd), timer-safe,
--     exactly how NovaWorldBuffs syncs. Coalesced by key + probabilistic (only a subset
--     yells each cycle, anti-spam) + gated to non-instance/non-ghost. Callers already do
--     Guild/Proximity themselves, so :Realm adds the zone-wide YELL on top. YELL is
--     layer-local (like SAY), so cross-LAYER reach still comes from Guild + Whisper.
--
--     CRITICAL: SAY/YELL ride the PUBLIC-chat pipe, governed by the client's strict
--     chat-message rate limit ("The number of messages that can be sent is limited").
--     ChatThrottleLib does NOT model that limit (it only paces the addon byte-throttle),
--     so the realm flush PACES itself: at most YELL_PER_FLUSH yells per cycle, spaced
--     YELL_GAP seconds apart, off a size-bounded queue. ALWAYS pass a stable, low-
--     cardinality coalesceKey — feeding per-item/unbounded data without one is what
--     floods the limit (a per-node feed with no key made every item its own queue slot).
--
-- RECEIVE: :Register(prefix, handler) - handler(payload, sender, dist) fires for any
-- distribution (Guild/Group/SAY/YELL/Whisper) of that prefix.
--
-- v5: WoW: Forever (and retail) refuse SAY and YELL addon messages outright: InvalidChatType (4), measured by
-- the CehulNet backoffice in cities and in a dungeon, from clicks and from timers, build 1.60.1.70862. They also
-- refuse addon messages on custom channels. AceComm never reads the result, so v4 counted every yell as sent
-- and the realm bus reached nobody. Now:
--   * the first SAY and the first YELL of a session go raw through C_ChatInfo.SendAddonMessage, which answers.
--     A bus the game calls InvalidChatType is dead for the session (M.dead): :Proximity/:Yell return false,
--     CanYell() says no. Where it works (TBC Anniversary) the message simply went out, and nothing changes.
--   * once YELL is dead, a DIRECTORY: one hidden, passworded channel per faction that every client joins, never
--     to talk in it (the game refuses that) but to read its member list, which the server still hands out. It
--     is how WoWForeverRace, Overlord and HeadHunter cross the realm on Forever (same faction, every home
--     server). :Realm then flushes each item by whisper to REALM_FANOUT random members of it; callers that relay
--     (beacons, race digests, the HELLO) spread it on from there. Nothing goes from inside an instance or a
--     chat lockdown: a whisper there counts against the prefix throttle, and a lockdown holds it anyway.
-- v6: a member who logs off stays on the directory until the next read, and the realm flush's whisper to them
-- printed "No player named X is currently playing" in every v5 client's chat (launch peak, 2026-11-08). Now
-- that line is hidden for a name the directory whispered in the last TRIED_SECONDS, the name leaves the list at
-- once and stays out for BAD_SECONDS, and a name the roster gave with a realm is tried once in that spelling
-- before it goes. The list is read every 120 s instead of 300.
-- v7 (chehulnet#1): on 2026-11-08 the Forever server began answering INVALID_NAME to ChehulNetH (other channel names
-- still join, same build). At login the game put clients back in the saved channel, the server refused it, the
-- channel stayed listed but disabled, and v6 took GetChannelName > 0 for "in" and never read a member: the realm bus
-- reached nobody outside the guild. A refusal that looks deliberate is not dodged with another name. Now:
--   * a refusal notice (INVALID_NAME, WRONG_PASSWORD, BANNED) marks the directory refused for the session
--     (M.dir.refused): the list empties, the client leaves the dead channel and stops joining. A channel listed but
--     disabled gets one leave and one join, and the server's answer decides.
--   * PEERS replace the directory: every sender heard on a registered prefix (guild, group, whisper) is a peer,
--     guild ones marked; once YELL is dead a client whispers a sample of the peers it heard to one peer every
--     PEX_INTERVAL ("ChehulPeers", PX1|q|names), and gets that peer's sample back (PX1|a), rate-limited per asker
--     and per minute. The realm flush whispers fresh peers outside the guild, plus directory members where the
--     directory still works. Hosts may pass a SavedVariables table (Mesh:PeerStore) so the next login starts the
--     exchange with names it knew; those get no realm item until they answer.
--   * every prefix an older copy registered is pointed at this version's receive route, so its senders count.

local VERSION = 7
if _G.ChehulMesh and (_G.ChehulMesh.version or 0) >= VERSION then
    return
end

local M = _G.ChehulMesh or {}
_G.ChehulMesh = M

-- Cleanly take over from an older (v1/v2) instance: silence its CHAT_MSG_ADDON receive
-- frame so we don't double-dispatch during a mixed-version transition. Its old
-- WorldFrame click-flush hooks become harmless no-ops (we never fill its channel queue).
if M.frame and M.frame.UnregisterAllEvents then
    pcall(M.frame.UnregisterAllEvents, M.frame)
end

M.version    = VERSION
M.PREFIX_ROOT = "Chehul"
M.CHANNEL    = "ChehulMesh" -- kept for compatibility; the channel is no longer used to send
M.handlers   = M.handlers or {} -- [prefix] = handler(payload, sender, dist); KEPT across an
                                -- upgrade so a still-old sibling's registrations survive (they
                                -- get re-registered with AceComm below).
-- [prefix] = true once an AceComm receive callback is installed. v3-SPECIFIC field name
-- ON PURPOSE: the old v1/v2 used `_registered` for a DIFFERENT meaning (game addon-prefix
-- registration), so reusing it would make Ensure() early-return and leave the mesh
-- receive-DEAD after a v2->v3 upgrade. Do NOT rename this back to `_registered`.
M._commReg = M._commReg or {}
M._realmQueue = M._realmQueue or {} -- [prefix\tkey] = { prefix, payload } pending YELL flush
-- Recompute the queue size (a carried-over instance may already hold items) and clear any
-- in-flight drain flag from a superseded version.
M._realmQueueCount = 0
for _ in pairs(M._realmQueue) do M._realmQueueCount = M._realmQueueCount + 1 end
M._draining = false
M.stats = M.stats or {}
do
    local s = M.stats
    s.ok = s.ok or 0; s.fail = s.fail or 0; s.recv = s.recv or 0
    s.yell = s.yell or 0; s.realmQueued = s.realmQueued or 0; s.realmSent = s.realmSent or 0
    s.realmDropped = s.realmDropped or 0
    s.refused = s.refused or 0; s.dirSent = s.dirSent or 0
end
M.dead   = M.dead or {}   -- [dist] = "InvalidChatType": a bus the game refused this session (v5)
M.probed = M.probed or {} -- [dist] = true: the game took a raw send on it once, so it lives
M.dir    = M.dir or { names = {}, count = 0 } -- the directory's members (whisper spelling), carried on upgrade

M.YELL_PERCENT    = 34  -- like NWB: only ~1/3 of clients yell each cycle (zone-level anti-spam)
M.REALM_INTERVAL  = 25  -- seconds between YELL-flush cycles
M.YELL_GAP        = 2   -- seconds between individual YELLs within a flush. Public SAY/YELL are
                        -- governed by the strict chat-message rate limit, which ChatThrottleLib
                        -- does NOT pace — so we space them ourselves.
M.YELL_PER_FLUSH  = 4   -- max YELLs emitted per flush cycle; the remainder stays queued (coalesced)
M.REALM_QUEUE_MAX = 40  -- hard cap on distinct queued realm items; new keys past this are dropped
M.REALM_FANOUT    = 3   -- directory members a realm item goes to, by whisper, once YELL is dead
M.DIR_PREFIX      = "ChehulNet" -- the directory channel: this plus the faction's initial (A/H)
-- ponytail: the password ships in every copy, so it keeps chat clients out, not a griefer who reads it.
M.DIR_PASSWORD    = "chehulmesh"
M.DIR_REFRESH     = 120 -- seconds between member-list reads; the server sends the list only on a selection
M.TRIED_SECONDS   = 30  -- seconds a "No player named" line for a name the directory whispered stays hidden
M.BAD_SECONDS     = 600 -- seconds a name that answered "No player named" stays off the directory
M.dir.tried = M.dir.tried or {} -- [whisper target] = GetTime() until which its not-found line is ours
M.dir.bad   = M.dir.bad or {}   -- [whisper target] = time() until which it is not picked
M.dir.raw   = M.dir.raw or {}   -- [spelling we whisper] = the roster's own spelling, when they differ

M.view   = M.view or {}   -- [name] = { heard, named, guild, asked, stored } (v7): the Chehul clients this one knows
M.stores = M.stores or {} -- functions from :PeerStore, each returning a SavedVariables table of name -> time()
M.pex    = M.pex or { replied = {}, window = 0, answers = 0 }
M.PEX_PREFIX    = "ChehulPeers"
M.PEX_INTERVAL  = 60     -- seconds between this client's exchanges
M.PEX_SAMPLE    = 8      -- names in one exchange
M.PEX_REPLY_GAP = 60     -- one answer per asker per this
M.PEX_BUDGET    = 6      -- answers per minute at most
M.HEARD_TTL     = 900    -- a peer heard within this is fresh
M.NAMED_TTL     = 600    -- a name a peer passed on is fresh this long
M.STORE_TTL     = 259200 -- saved names older than three days are dropped
M.VIEW_MAX      = 300

-- ---------------------------------------------------------------------------
-- Peers (v7)
-- ---------------------------------------------------------------------------
local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- "First Surname-Realm" whispers as "First Surname" on WoW: Forever (the Name-Realm form does not arrive there,
-- WoWForeverRace measured). A name with no space is a realm-bound one and keeps its realm.
local function WhisperName(name)
    return name:match("^(%S+ %S+)%-%S+$") or name
end

-- ponytail: on retail a same-named player of another realm passes for me and is not learned; harmless.
local function IsMe(name)
    if not UnitFullName then return false end
    local first, second = UnitFullName("player") -- both values: `a and f()` would keep only the first
    if type(first) ~= "string" or Secret(first) or Secret(second) then return false end
    local short = name:match("^[^%-]+") or name
    return short == first or (type(second) == "string" and short == first .. " " .. second)
end

local function Usable(name)
    local till = M.dir.bad[name]
    return not till or time() > till
end

local function Fresh(v, name, now)
    if not Usable(name) then return false end
    return (v.heard and now - v.heard <= M.HEARD_TTL) or (v.named and now - v.named <= M.NAMED_TTL) or false
end

-- `how` is "heard" (it sent me something on `dist`) or "named" (a peer passed it on).
local function Learn(name, how, dist)
    if type(name) ~= "string" or Secret(name) or name == "" or #name > 48 or name:find("[,|]") then return end
    name = WhisperName(name)
    if IsMe(name) then return end
    local now, v = time(), M.view[name]
    if not v then
        local count, oldest, oldestAt = 0, nil, nil
        for k, p in pairs(M.view) do
            count = count + 1
            local at = math.max(p.heard or 0, p.named or 0, p.stored or 0)
            if not oldestAt or at < oldestAt then oldest, oldestAt = k, at end
        end
        if count >= M.VIEW_MAX and oldest then M.view[oldest] = nil end
        v = {}
        M.view[name] = v
    end
    if how == "named" then
        v.named = now
        return
    end
    v.heard = now
    M.dir.bad[name] = nil -- it is online: an old "No player named" no longer counts
    if dist == "GUILD" then v.guild = true end
    for _, fn in ipairs(M.stores) do
        local ok, t = pcall(fn)
        if ok and type(t) == "table" then t[name] = now end
    end
end

-- The fresh peers outside my guild: who a realm item may go to.
function M:Peers()
    local now, out = time(), {}
    for name, v in pairs(M.view) do
        if not v.guild and Fresh(v, name, now) then out[#out + 1] = name end
    end
    return out
end

function M:PeerCount()
    local now, n = time(), 0
    for name, v in pairs(M.view) do
        if Fresh(v, name, now) then n = n + 1 end
    end
    return n
end

-- fn() returns a SavedVariables table the mesh keeps name -> time() in, resolved when used (after the SV load).
function M:PeerStore(fn)
    if type(fn) == "function" then M.stores[#M.stores + 1] = fn end
end

-- ---------------------------------------------------------------------------
-- AceComm transport
-- ---------------------------------------------------------------------------
local AceComm = LibStub and LibStub("AceComm-3.0", true)
local COMM = M._comm or {}
M._comm = COMM

local function OnReceive(prefix, message, dist, sender)
    M.stats.recv = M.stats.recv + 1
    Learn(sender, "heard", dist)
    local h = M.handlers[prefix]
    if h then pcall(h, message, sender, dist) end
end
M._onReceive = OnReceive

-- Through the shared table, so a newer copy's OnReceive takes over routes an older one registered.
local function Route(prefix, message, distribution, sender)
    return M._onReceive(prefix, message, distribution, sender)
end

-- Ensure a prefix is registered with AceComm (server delivery + a receive route). Safe
-- to call for send-only prefixes: OnReceive just no-ops when no handler is registered.
local function Ensure(prefix)
    if not AceComm or M._commReg[prefix] then return end
    M._commReg[prefix] = true
    pcall(AceComm.RegisterComm, COMM, prefix, Route)
end

-- v7: an older copy's routes call its own OnReceive. Registering again on the same object replaces them.
if AceComm then
    for prefix in pairs(M._commReg) do
        pcall(AceComm.RegisterComm, COMM, prefix, Route)
    end
end

local RESULT = Enum and Enum.SendAddonMessageResult
local INVALID = RESULT and RESULT.InvalidChatType
local PROBE = { SAY = true, YELL = true }
local StartDirectory -- defined with the directory below

local function Send(prefix, payload, dist, target)
    if M.dead[dist] then M.stats.refused = M.stats.refused + 1; return false end
    if not AceComm then M.stats.fail = M.stats.fail + 1; return false end
    Ensure(prefix)
    -- The first SAY/YELL of a session goes raw, to read the game's answer. For a payload of 255 bytes or less
    -- that does not start with a control character, an AceComm single part is these very bytes.
    if PROBE[dist] and not M.probed[dist] and INVALID and C_ChatInfo and C_ChatInfo.SendAddonMessage
        and #payload <= 255 and not payload:find("^[\001-\009]") then
        local done, r = pcall(C_ChatInfo.SendAddonMessage, prefix, payload, dist, target)
        if done and r == INVALID then
            M.dead[dist] = "InvalidChatType"
            M.stats.refused = M.stats.refused + 1
            if dist == "YELL" and StartDirectory then StartDirectory() end
            return false
        end
        if done and (r == nil or r == true or r == 0) then
            M.probed[dist] = true
            M.stats.ok = M.stats.ok + 1
            return true
        end
        -- a throttle, a lockdown, anything else is no verdict: AceComm queues it as before
    end
    local ok = pcall(AceComm.SendCommMessage, COMM, prefix, payload, dist, target, "NORMAL")
    if ok then M.stats.ok = M.stats.ok + 1 else M.stats.fail = M.stats.fail + 1 end
    return ok
end
M.SendAddon = Send -- back-compat alias

-- Re-register (with AceComm) any handlers carried over from an upgraded older instance,
-- so receive keeps working even if the addon that registered them isn't reloaded.
for existing in pairs(M.handlers) do
    Ensure(existing)
end

-- ---------------------------------------------------------------------------
-- Receive registration
-- ---------------------------------------------------------------------------
function M:Register(prefix, handler)
    if type(prefix) ~= "string" or prefix == "" or type(handler) ~= "function" then
        return
    end
    M.handlers[prefix] = handler
    Ensure(prefix)
end

-- ---------------------------------------------------------------------------
-- Buses
-- ---------------------------------------------------------------------------
local function CanYell()
    if M.dead.YELL then return false end                       -- the game refuses it here (v5)
    if IsInInstance and IsInInstance() then return false end -- no yell in dungeons/raids/BGs/arenas
    if UnitIsGhost and UnitIsGhost("player") then return false end
    return true
end
M.CanYell = CanYell

function M:Guild(prefix, payload)
    if IsInGuild and not IsInGuild() then return false end
    return Send(prefix, payload, "GUILD")
end

function M:Group(prefix, payload)
    if IsInGroup and not IsInGroup() then return false end
    return Send(prefix, payload, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
end

function M:Proximity(prefix, payload)
    return Send(prefix, payload, "SAY")
end

function M:Yell(prefix, payload)
    if not CanYell() then return false end
    return Send(prefix, payload, "YELL")
end

function M:Whisper(prefix, payload, target)
    if not target or target == "" then return false end
    return Send(prefix, payload, "WHISPER", target)
end

-- Realm-wide (zone-wide via YELL): queue coalesced by key; flushed paced + capped.
function M:Realm(prefix, payload, coalesceKey)
    if type(prefix) ~= "string" or type(payload) ~= "string" then return end
    Ensure(prefix)
    local key = prefix .. "\t" .. (coalesceKey or payload)
    -- Bound the queue. An unbounded queue + a burst flush is exactly what let a chatty
    -- caller (per-node/per-listing WITHOUT a stable coalesceKey — its key falls back to
    -- the payload, so every item is distinct) pile up and spam the chat-rate limit.
    -- Updates to an already-queued key always pass; brand-new keys are dropped when full.
    if not M._realmQueue[key] then
        if M._realmQueueCount >= M.REALM_QUEUE_MAX then
            M.stats.realmDropped = M.stats.realmDropped + 1
            return
        end
        M._realmQueueCount = M._realmQueueCount + 1
    end
    M._realmQueue[key] = { prefix = prefix, payload = payload }
    M.stats.realmQueued = M.stats.realmQueued + 1
end

-- An instance or a chat lockdown holds whispers back.
local function Quiet()
    if IsInInstance and IsInInstance() then return true end
    local lockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    return (lockdown and lockdown()) and true or false
end

-- Whether whispers can carry a realm item now: YELL is dead, somebody is listed in the directory or a fresh peer
-- is known outside the guild (v7), and nothing holds whispers back.
local function CanWhisperWide()
    if not M.dead.YELL or Quiet() then return false end
    return #M.dir.names > 0 or #M:Peers() > 0
end

-- `k` distinct names at random among directory members and fresh peers outside the guild.
local function Pick(k)
    local pool, seen, out = {}, {}, {}
    for _, list in ipairs({ M.dir.names, M:Peers() }) do
        for _, name in ipairs(list) do
            if not seen[name] then seen[name], pool[#pool + 1] = true, name end
        end
    end
    while #pool > 0 and #out < k do
        out[#out + 1] = table.remove(pool, math.random(1, #pool))
    end
    return out
end

-- A whisper to a name that may have logged off: its "No player named" line, if one comes, is hidden and acted on.
local function WhisperTried(prefix, payload, name)
    M.dir.tried[name] = (GetTime and GetTime() or 0) + M.TRIED_SECONDS
    return Send(prefix, payload, "WHISPER", name)
end

-- Emit ONE queued realm item as YELL, then reschedule the next after YELL_GAP — one at a
-- time, capped at YELL_PER_FLUSH per cycle. Dumping the whole queue in a single frame (the
-- old behavior) let ChatThrottleLib release small yells faster than the public chat pipe
-- accepts, tripping ERR_CHAT_THROTTLED. Pacing keeps us under it.

local function EmitNextYell(sent)
    if sent >= M.YELL_PER_FLUSH or not (CanYell() or CanWhisperWide()) then
        M._draining = false
        return
    end
    local key = next(M._realmQueue)
    if not key then
        M._draining = false
        return
    end
    local item = M._realmQueue[key]
    M._realmQueue[key] = nil
    M._realmQueueCount = M._realmQueueCount - 1
    if CanYell() and Send(item.prefix, item.payload, "YELL") then
        M.stats.yell = M.stats.yell + 1
        M.stats.realmSent = M.stats.realmSent + 1
    elseif CanWhisperWide() then -- the yell just found the bus dead, or it was already
        for _, name in ipairs(Pick(M.REALM_FANOUT)) do
            if WhisperTried(item.prefix, item.payload, name) then M.stats.dirSent = M.stats.dirSent + 1 end
        end
        M.stats.realmSent = M.stats.realmSent + 1
    end
    if next(M._realmQueue) and C_Timer and C_Timer.After then
        C_Timer.After(M.YELL_GAP, function() EmitNextYell(sent + 1) end)
    else
        M._draining = false
    end
end

local function FlushRealm()
    if M._draining then return end
    if not next(M._realmQueue) then return end
    -- Only a subset of clients yell each cycle (zone-level anti-spam). Presence/data
    -- re-queues over cycles, so everything still radiates out zone-wide over time.
    -- The same share carries the directory's whispers: a realm item goes REALM_FANOUT whispers wide per client.
    -- A YELL not yet probed counts as alive: the first flush is what finds it dead.
    if not ((CanYell() or CanWhisperWide()) and math.random(1, 100) <= M.YELL_PERCENT) then
        return
    end
    M._draining = true
    EmitNextYell(0)
end
M.FlushRealm = FlushRealm

-- ---------------------------------------------------------------------------
-- Directory (v5): the member list of one hidden channel per faction. Nobody talks in it.
-- ---------------------------------------------------------------------------
local function ChannelName()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return M.DIR_PREFIX .. ((type(faction) == "string" and faction ~= "") and faction:sub(1, 1) or "N")
end

-- v7: a channel the server refused can stay in the client's list, disabled (GetChannelList: id, name, disabled...).
local function Disabled(name)
    if not GetChannelList then return false end
    local list = { pcall(GetChannelList) }
    if not list[1] then return false end
    for i = 2, #list - 2, 3 do
        if not Secret(list[i + 1]) and list[i + 1] == name then return list[i + 2] == true end
    end
    return false
end

local function JoinDirectory()
    if not M.dir.on or M.dir.refused or not JoinTemporaryChannel or (IsInInstance and IsInInstance()) then return end
    M.dir.channel = ChannelName()
    local ok, id = pcall(GetChannelName, M.dir.channel)
    if ok and tonumber(id) and tonumber(id) > 0 then
        if not Disabled(M.dir.channel) or M.dir.retried then return end
        -- once a session: leave the dead entry and ask again; the server's answer decides
        M.dir.retried, M.dir.rejoinAt = true, time() + 3
        if LeaveChannelByName then pcall(LeaveChannelByName, M.dir.channel) end
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                if not M.dir.refused then pcall(JoinTemporaryChannel, M.dir.channel, M.DIR_PASSWORD) end
            end)
        end
        return
    end
    if M.dir.rejoinAt and time() < M.dir.rejoinAt then return end -- the planned try is on its way
    pcall(JoinTemporaryChannel, M.dir.channel, M.DIR_PASSWORD)
end

-- v7: the server's refusal of the directory's channel ends it for the session.
local REFUSED = { INVALID_NAME = true, WRONG_PASSWORD = true, BANNED = true }
local function OnNotice(kind, channel, base)
    local name = M.dir.channel
    if not name or M.dir.refused or Secret(kind) or Secret(channel) or Secret(base) or not REFUSED[kind] then return end
    if base ~= name and not (type(channel) == "string" and channel:find(name, 1, true)) then return end
    M.dir.refused = kind
    M.dir.names, M.dir.count, M.dir.index = {}, 0, nil
    local ok, id = pcall(GetChannelName, name)
    if ok and tonumber(id) and tonumber(id) > 0 and LeaveChannelByName then pcall(LeaveChannelByName, name) end
end

-- The server sends a channel's list only when it is selected, and selecting another one first makes it send it
-- again (Overlord, measured 2026-11-06). Left alone while the player has the Channels window open or fights.
local function RequestRoster()
    if not (M.dir.channel and SetSelectedDisplayChannel and GetNumDisplayChannels and GetChannelDisplayInfo) then return end
    if (ChannelFrame and ChannelFrame.IsShown and ChannelFrame:IsShown()) or (InCombatLockdown and InCombatLockdown()) then return end
    local mine, other
    for i = 1, GetNumDisplayChannels() or 0 do
        local ok, name, header = pcall(GetChannelDisplayInfo, i)
        if ok and not header and type(name) == "string" and not Secret(name) then
            if name == M.dir.channel then mine = i elseif not other then other = i end
        end
    end
    if not mine then return end
    M.dir.index = mine
    if other then pcall(SetSelectedDisplayChannel, other) end
    pcall(SetSelectedDisplayChannel, mine)
end

local function OnRoster(displayIndex, count)
    if displayIndex ~= M.dir.index or not (C_ChatInfo and C_ChatInfo.GetChannelRosterInfo) then return end
    -- v7: the index may now hold another channel (ours was left); its members are not the directory
    local shown, name = pcall(GetChannelDisplayInfo, displayIndex)
    if not shown or Secret(name) or name ~= M.dir.channel then return end
    local me = UnitGUID and UnitGUID("player")
    local names = {}
    for i = 1, tonumber(count) or 0 do
        local ok, name, _, _, guid = pcall(C_ChatInfo.GetChannelRosterInfo, displayIndex, i)
        if ok and type(name) == "string" and not Secret(name) and not Secret(guid) and guid ~= me then
            local spelled = WhisperName(name)
            if spelled ~= name then M.dir.raw[spelled] = name end
            local raw = M.dir.raw[spelled]
            if Usable(spelled) then
                names[#names + 1] = spelled
            elseif raw and Usable(raw) then -- the plain spelling found nobody: the roster's own one, while it lasts
                names[#names + 1] = raw
            end
        end
    end
    M.dir.names, M.dir.count, M.dir.at = names, #names, time()
end

-- A name the directory whispered answered "No player named": it leaves the list now and is not picked for
-- BAD_SECONDS. A plain "First Surname" the roster gave with a realm gets one try in the roster's spelling.
local function Unreachable(name)
    local till = M.dir.bad[name]
    if till and time() <= till then return end -- every chat window runs the filter: act once
    M.dir.bad[name] = time() + M.BAD_SECONDS
    local names, kept = M.dir.names, {}
    for _, n in ipairs(names) do
        if n ~= name then kept[#kept + 1] = n end
    end
    local raw = M.dir.raw[name]
    if raw and raw ~= name and Usable(raw) then kept[#kept + 1] = raw end
    M.dir.names, M.dir.count = kept, #kept
end

local notFound -- ERR_CHAT_PLAYER_NOT_FOUND_S as a pattern; false when the client has no such string
local function NotFoundName(msg)
    if notFound == nil then
        local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
        notFound = false
        if type(fmt) == "string" and fmt:find("%s", 1, true) then
            local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
            notFound = "^" .. p:gsub("%%%%s", "(.+)") .. "$"
        end
    end
    return notFound and msg:match(notFound) or nil
end

-- The client's "No player named X" line, for X the directory whispered a moment ago: nobody's business in a
-- chat window. Anyone else's line passes untouched.
local function HideNotFound(_, _, msg)
    if Secret(msg) or type(msg) ~= "string" or not next(M.dir.tried) then return false end
    local name = NotFoundName(msg)
    local till = name and M.dir.tried[name]
    if not till or (GetTime and GetTime() or 0) > till then return false end
    Unreachable(name)
    return true
end

-- The join and leave lines of the directory are nobody's business in a chat window.
local function HideNotice(_, _, _, _, _, channel, _, _, _, _, base)
    local name = M.dir.channel
    if not name or Secret(channel) or Secret(base) then return false end
    return base == name or (type(channel) == "string" and channel:find(name, 1, true) ~= nil)
end

local function InstallFilters()
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add then return end
    if not M.dir.filtered then
        M.dir.filtered = true
        for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN",
            "CHAT_MSG_CHANNEL_LEAVE" }) do
            pcall(add, event, HideNotice)
        end
    end
    -- its own flag (v7): a v6 filter already in place just means two that act once; a v5 left none
    if not M.dir.notFoundFilter then
        M.dir.notFoundFilter = true
        pcall(add, "CHAT_MSG_SYSTEM", HideNotFound)
    end
end

StartDirectory = function()
    if M.dir.on then return end
    M.dir.on = true
    InstallFilters()
    JoinDirectory()
    if C_Timer and C_Timer.After then C_Timer.After(15, RequestRoster) end
end
-- v7: an older copy may have started the directory already, and a v5 one set `filtered` without the not-found
-- filter; v7 whispers saved and passed-on names, so that filter must be in before any of its whispers.
if M.dir.on then InstallFilters() end

-- One frame and one ticker, bound to THIS version's functions (a superseded one's are cancelled/replaced).
M.dirFrame = M.dirFrame or (CreateFrame and CreateFrame("Frame")) or nil
if M.dirFrame then
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "CHANNEL_ROSTER_UPDATE")
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "PLAYER_ENTERING_WORLD")
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "CHAT_MSG_CHANNEL_NOTICE")
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "CHAT_MSG_CHANNEL_NOTICE_USER")
    -- a channel notice: (kind, player, language, "N. Channel", player2, flags, zoneChannelID, index, baseName)
    M.dirFrame:SetScript("OnEvent", function(_, event, a, b, _, d, _, _, _, _, i)
        if event == "CHANNEL_ROSTER_UPDATE" then
            OnRoster(a, b)
        elseif event == "CHAT_MSG_CHANNEL_NOTICE" or event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
            OnNotice(a, d, i)
        elseif C_Timer and C_Timer.After then -- the game joins its own channels first; a join before them is lost
            C_Timer.After(12, JoinDirectory)
        end
    end)
end
if M._dirTicker and M._dirTicker.Cancel then pcall(function() M._dirTicker:Cancel() end) end
if C_Timer and C_Timer.NewTicker then
    M._dirTicker = C_Timer.NewTicker(M.DIR_REFRESH, function()
        if not M.dir.on then return end
        local now = GetTime and GetTime() or 0
        for name, till in pairs(M.dir.tried) do
            if now > till then M.dir.tried[name] = nil end
        end
        JoinDirectory()
        RequestRoster()
    end)
end

function M:Directory()
    return M.dir
end

function M:RefreshDirectory()
    JoinDirectory()
    RequestRoster()
end

-- ---------------------------------------------------------------------------
-- Peer exchange (v7), only where YELL is dead: PX1|q|names asks, PX1|a|names answers. Names are first-hand only.
-- ---------------------------------------------------------------------------
local function Sample(except)
    local now, pool, out, size = time(), {}, {}, 0
    for name, v in pairs(M.view) do
        if name ~= except and v.heard and now - v.heard <= M.HEARD_TTL and Usable(name) then pool[#pool + 1] = name end
    end
    while #pool > 0 and #out < M.PEX_SAMPLE do
        local name = table.remove(pool, math.random(1, #pool))
        if size + #name + 1 > 200 then break end
        out[#out + 1], size = name, size + #name + 1
    end
    return table.concat(out, ",")
end

-- Saved names come in once a session, as a start for the exchange; they are not fresh until they answer.
-- ponytail: a saved table grows with every peer heard in STORE_TTL (a few hundred); cap it if that ever bites.
local function LoadStores()
    if M.pex.loaded then return end
    M.pex.loaded = true
    local now = time()
    for _, fn in ipairs(M.stores) do
        local ok, t = pcall(fn)
        if ok and type(t) == "table" then
            for name, at in pairs(t) do
                if type(name) ~= "string" or type(at) ~= "number" or now - at > M.STORE_TTL then
                    t[name] = nil
                elseif not IsMe(name) then
                    M.view[name] = M.view[name] or {}
                    M.view[name].stored = math.max(M.view[name].stored or 0, at)
                end
            end
        end
    end
end

-- The fresh peer asked longest ago (guild ones too: they know people outside it); with none, a saved name not
-- asked yet this session.
local function PexTarget()
    local now, best, bestAt, pool = time(), nil, nil, {}
    for name, v in pairs(M.view) do
        if Fresh(v, name, now) then
            if not bestAt or (v.asked or 0) < bestAt then best, bestAt = name, v.asked or 0 end
        elseif v.stored and not v.asked and Usable(name) then
            pool[#pool + 1] = name
        end
    end
    return best or (#pool > 0 and pool[math.random(1, #pool)]) or nil
end

local function PexTick()
    if not M.dead.YELL or Quiet() then return end
    LoadStores()
    local now = time()
    for name, at in pairs(M.pex.replied) do
        if now - at >= M.PEX_REPLY_GAP then M.pex.replied[name] = nil end
    end
    local target = PexTarget()
    if not target then return end
    M.view[target].asked = now
    WhisperTried(M.PEX_PREFIX, "PX1|q|" .. Sample(target), target)
end

local function OnPex(payload, sender, dist)
    if dist ~= "WHISPER" or type(payload) ~= "string" or Secret(payload) or type(sender) ~= "string" or Secret(sender) then
        return
    end
    local kind, list = payload:match("^PX1|([qa])|(.*)$")
    if not kind then return end
    local n = 0
    for name in list:gmatch("[^,]+") do
        n = n + 1
        if n > M.PEX_SAMPLE then break end
        Learn(name, "named")
    end
    if kind ~= "q" or Quiet() then return end
    local now, asker, pex = time(), WhisperName(sender), M.pex
    if now - (pex.replied[asker] or 0) < M.PEX_REPLY_GAP then return end
    if now - pex.window >= 60 then pex.window, pex.answers = now, 0 end
    if pex.answers >= M.PEX_BUDGET then return end
    pex.replied[asker], pex.answers = now, pex.answers + 1
    WhisperTried(M.PEX_PREFIX, "PX1|a|" .. Sample(asker), asker) -- it may log off before the answer leaves
end
M:Register(M.PEX_PREFIX, OnPex)

if M._pexTicker and M._pexTicker.Cancel then pcall(function() M._pexTicker:Cancel() end) end
if C_Timer and C_Timer.NewTicker then
    M._pexTicker = C_Timer.NewTicker(M.PEX_INTERVAL, PexTick)
end

-- (Re)install the flush ticker bound to THIS version's FlushRealm. A superseded instance's
-- ticker still points at its own (possibly burst-y) flush, so cancel it first.
if M._realmTicker and M._realmTicker.Cancel then
    pcall(function() M._realmTicker:Cancel() end)
    M._realmTicker = nil
end
if C_Timer and C_Timer.NewTicker then
    M._realmTicker = C_Timer.NewTicker(M.REALM_INTERVAL, FlushRealm)
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------
function M:Stats()
    return M.stats
end

function M:HealthLine()
    local s = M.stats
    local line = string.format("addon %d ok", s.ok)
    if s.fail > 0 then line = line .. " \194\183 fail " .. s.fail end
    line = line .. " \194\183 yell " .. s.yell .. " \194\183 recv " .. s.recv
    if s.realmDropped > 0 then line = line .. " \194\183 drop " .. s.realmDropped end
    local dead = {}
    for dist in pairs(M.dead) do dead[#dead + 1] = dist end
    if #dead > 0 then
        table.sort(dead)
        line = line .. " \194\183 dead " .. table.concat(dead, ",") .. " \194\183 dir " .. M.dir.count
        if M.dir.refused then line = line .. " \194\183 dir refused " .. M.dir.refused end
        line = line .. " \194\183 view " .. M:PeerCount()
    end
    if not AceComm then line = line .. " \194\183 |cffff5555AceComm missing|r" end
    return line
end

return M
