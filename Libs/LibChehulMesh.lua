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
-- v8 (chehulnet#3): a realm item reached 3 peers and stopped there; the guild of whoever got it never heard it; the
-- flush still drew YELL's 34% share; the fan-out took names nobody confirmed; a new peer waited up to a minute for
-- an exchange; and the mesh did not know which addons a peer runs. Now:
--   * RELAY: :Realm(prefix, payload, key, true) marks an item for relaying. It goes to peers that run v8 in an
--     envelope on ChehulRelay ("RL1|id|hops|origin|prefix|payload"), raw to the others as before. A v8 client
--     takes each origin/id once, hands it to the host as dist "RELAY" with the origin as sender (claimed, not
--     verified) only for prefixes the host declared with :Relayable, and passes it on while hops remain to
--     RELAY_FANOUT v8 peers outside its guild, never back to who sent it. Hosts trust dist "GUILD" (GuildOS's
--     officer ads, Lodestar's guild boards), so a relayed item is never handed over as GUILD or WHISPER, and the
--     control prefixes (alerts, ping, peers, probe, relay) are never relayed.
--   * GUILD RELAY: who gets an envelope by whisper says it once on GUILD after 0.5-3 s, unless the same item comes
--     on GUILD first: one whisper into a guild reaches all of it. Who gets it on GUILD passes nothing on.
--   * a budget per minute for relay whispers and guild relays; nothing from an instance or a chat lockdown.
--   * the flush draws YELL_PERCENT only while YELL lives: a whisper outside an instance has no prefix throttle.
--   * the fan-out draws heard peers first (they answered); named ones only fill what is missing.
--   * a peer outside the guild heard for the first time gets an exchange within seconds (PEX_EAGER a minute).
--   * :Seed(name) takes a name a host knows runs Chehul (an author of its data); :Tag(name, tags, version) keeps
--     the addons and mesh version a peer's HELLO gave, and :Peers(tag) lists the fresh ones running that addon.
-- v9 (chehulnet#5): on 2026-11-10 the server took ChehulNetH again, with no new build and no hotfix about chat: the
-- INVALID_NAME of 11-08 looks like a block on that one name after the launch's peak of "No player named". What
-- weighs on the server is ours, so:
--   * ONE CHANNEL PER RULESET where the game has regional unique names (Forever): ChehulNet + faction + HC, RPPvP,
--     RP, PvP or PvE (C_GameRules). A whisper does not cross rulesets, and the faction-wide list sent every realm
--     item drawn from another ruleset to a "No player named". A client the game put back in the old faction channel
--     leaves it once. Without regional unique names (Anniversary, retail) the name is the one it was.
--   * THE LIST IS READ RARELY: on joining, then after DIR_READ plus a jitter fixed per client, and only while the
--     client has fewer than DIR_ENOUGH confirmed links (it was every client, every 120 s, the whole list).
--   * THE DIRECTORY ONLY FILLS: realm items draw heard peers first, members of a list read within DIR_FRESH after.
--   * A BRAKE: NF_LIMIT "No player named" for names the mesh whispered within NF_WINDOW and the realm bus and the
--     peer exchange use heard peers only, until the count drops.
--   * WRONG_PASSWORD or BANNED (someone took the channel and locked it) lead to the same name with a number (…2, up
--     to DIR_MAX_NUM), one step per refusal. INVALID_NAME still ends the directory for the session, no other name.
-- v10 (chehulnet#9): Warmth, the family's campfire addon, announces a camp on the realm bus under ChehulCamp. The
-- prefix joins the family's relayed prefixes, so a client that runs GuildOS, Lodestar or PartyLens and not Warmth
-- still passes a camp's announce on. Low rate by design: one announce per camp every four minutes.
-- v11 (chehulnet#11): someone took ChehulNetH and changed its password (CurseForge report, 2026-11-10). Besides the
-- WRONG_PASSWORD notice the game fires CHANNEL_PASSWORD_REQUEST, and Blizzard's UI answers it with a password box,
-- on each of our joins and on each login, when the game rejoins the channels saved at logout. v10 heard only the
-- notice, so the box stayed. Now, for a channel whose name starts with DIR_PREFIX:
--   * the box is closed at once and again a frame later, except in gamepad mode: closing a Blizzard dialog from an
--     addon runs its close callbacks tainted, and in gamepad mode those include the gamepad's popup handler (the
--     taint of guildos#315). There the player cancels it.
--   * the directory's own channel steps to the next number, as WRONG_PASSWORD does (whichever comes first steps;
--     the other finds the name already changed).
--   * any other family channel (the faction-wide one of v5–v8, one this session moved away from) is left, so the
--     game stops saving it and the next login asks nothing. Its notices stay out of the chat.

local VERSION = 11
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
    s.nf = s.nf or 0
    s.rlIn = s.rlIn or 0; s.rlOut = s.rlOut or 0; s.rlFwd = s.rlFwd or 0; s.rlGuild = s.rlGuild or 0; s.rlDup = s.rlDup or 0
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
M.DIR_REFRESH     = 120 -- seconds between directory checks (join state, stale whispers); v9 reads the list rarely
M.DIR_READ        = 600 -- v9: a list read after this long (plus the client's jitter), while links are few
M.DIR_JITTER      = 180 -- v9: up to this many seconds added to DIR_READ, fixed per client so reads spread out
M.DIR_ENOUGH      = 6   -- v9: with this many confirmed links the list is not read at all
M.DIR_FRESH       = 960 -- v9: members of a list older than this are not whispered (longer than a read's cycle:
                        -- DIR_READ + DIR_JITTER + one DIR_REFRESH tick, so a client that reads is never left without)
M.DIR_FIRST_TRIES = 3   -- v9: list reads asked before the first one arrives, then at the DIR_READ pace
M.DIR_MAX_NUM     = 5   -- v9: …2..…5 after a WRONG_PASSWORD or BANNED
M.NF_WINDOW       = 600 -- v9: the brake's window, in seconds
M.NF_LIMIT        = 20  -- v9: "No player named" in the window that put the brake on
M.TRIED_SECONDS   = 30  -- seconds a "No player named" line for a name the directory whispered stays hidden
M.BAD_SECONDS     = 600 -- seconds a name that answered "No player named" stays off the directory
M.dir.tried = M.dir.tried or {} -- [whisper target] = GetTime() until which its not-found line is ours
M.dir.bad   = M.dir.bad or {}   -- [whisper target] = time() until which it is not picked
M.dir.raw   = M.dir.raw or {}   -- [spelling we whisper] = the roster's own spelling, when they differ
M.dir.past  = M.dir.past or {}  -- v9: channel names this session moved away from (their notices stay out of chat)

M.nf     = M.nf or {}     -- v9: time() of each "No player named" for a name the mesh whispered, within NF_WINDOW
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

-- v8: the relay.
M.relay     = M.relay or {}
M.relay.seen    = M.relay.seen or {}    -- [origin/id] = { at, guild }: each item taken once
M.relay.seq     = M.relay.seq or 0
M.relay.budget  = M.relay.budget or { window = 0, used = 0 }
M.relay.gbudget = M.relay.gbudget or { window = 0, used = 0 }
M.relay.origins = M.relay.origins or { window = 0, count = {} } -- [origin] = items passed on this minute
M.relay.senders = M.relay.senders or { window = 0, count = {} } -- [whisperer] = items passed on this minute
M.relayable = M.relayable or {}   -- [prefix] = true: a host takes relayed items of it (dist "RELAY")
M.pex.eager = M.pex.eager or { window = 0, used = 0 }
M.RELAY_PREFIX       = "ChehulRelay"
M.RELAY_HOPS         = 3    -- hops an item may still make after the first whisper
M.RELAY_FANOUT       = 2    -- peers each relay passes an item on to
M.RELAY_BUDGET       = 30   -- relay whispers a minute at most
M.GUILD_RELAY_BUDGET = 6    -- guild relays a minute at most
M.GUILD_RELAY_DELAY  = 3    -- a guild relay waits 0.5..this seconds, and drops when the guild already said it
M.SEEN_TTL           = 900
M.SEEN_MAX           = 400
M.RELAY_MAX          = 2000 -- bytes of relayed payload at most
M.PEX_EAGER          = 3    -- exchanges a minute with peers heard for the first time
M.RELAY_PER_ORIGIN   = 5    -- items of one claimed origin a client passes on a minute
M.RELAY_PER_SENDER   = 10   -- items one whisperer (the real sender, not the claimed origin) gets passed on a minute
-- What the family relays even where no host takes it (the opaque hop): GuildOS craft and recruitment, Lodestar quests
-- and races, PartyLens's board, ChehulNet's trace, Warmth's camps (v10). A host adds its own with :Relayable.
M.FAMILY = { ChehulCraft = true, ChehulRecruit = true, ChehulQuest = true, LSRace = true, PartyLens = true,
    ChehulTrace = true, ChehulCamp = true }
-- Never relayed nor handed over relayed: what these carry rests on who sent it.
M.CONTROL = { ChehulAlert = true, ChehulPing = true, ChehulPeers = true, ChehulProbe = true, ChehulRelay = true }

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

-- v9: the brake. "No player named" answers within NF_WINDOW; NF_LIMIT of them and only heard peers are whispered.
local function NotFoundCount()
    local now, kept = time(), {}
    for _, at in ipairs(M.nf) do
        if now - at < M.NF_WINDOW then kept[#kept + 1] = at end
    end
    M.nf = kept
    return #kept
end

local function Tripped()
    return NotFoundCount() >= M.NF_LIMIT
end

local function Heard(v, now)
    return v.heard ~= nil and now - v.heard <= M.HEARD_TTL
end

-- v9: members of a list read within DIR_FRESH may be whispered; an older list only tells who joined.
local function DirFresh()
    return M.dir.at ~= nil and time() - M.dir.at <= M.DIR_FRESH and #M.dir.names > 0
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
    local new = not v.heard or now - v.heard > M.HEARD_TTL
    v.heard = now
    M.dir.bad[name] = nil -- it is online: an old "No player named" no longer counts
    if dist == "GUILD" then v.guild = true end
    if new and not v.guild and M._eagerPex then M._eagerPex(name) end
    for _, fn in ipairs(M.stores) do
        local ok, t = pcall(fn)
        if ok and type(t) == "table" then t[name] = now end
    end
end

-- The fresh peers outside my guild: who a realm item may go to. With `tag`, only those whose HELLO named it (v8).
function M:Peers(tag)
    local now, out = time(), {}
    for name, v in pairs(M.view) do
        if not v.guild and Fresh(v, name, now) and (not tag or (v.tags and v.tags[tag])) then out[#out + 1] = name end
    end
    return out
end

-- v8: heard (confirmed) fresh peers outside the guild, and the fresh peers known to take the relay.
function M:NotFoundCount() return NotFoundCount() end
function M:Tripped() return Tripped() end

function M:LinkCount()
    local now, n = time(), 0
    for name, v in pairs(M.view) do
        if not v.guild and v.heard and now - v.heard <= M.HEARD_TTL and Usable(name) then n = n + 1 end
    end
    return n
end

function M:V8Count()
    local now, n = time(), 0
    for name, v in pairs(M.view) do
        if v.v8 and Fresh(v, name, now) then n = n + 1 end
    end
    return n
end

-- v8: a name a host knows runs Chehul (the author of something it got), taken as named.
function M:Seed(name)
    Learn(name, "named")
end

-- v8: what a peer's HELLO said: its addon tags (a set or "a+b") and its mesh version.
function M:Tag(name, tags, version)
    if type(name) ~= "string" or Secret(name) then return end
    local v = M.view[WhisperName(name)]
    if not v then return end
    if type(tags) == "string" and not Secret(tags) then
        local set = {}
        for t in tags:gmatch("[^+]+") do set[t] = true end
        tags = set
    end
    if type(tags) == "table" then v.tags = tags end
    version = tonumber(version)
    if version then
        v.mv = version
        if version >= 8 then v.v8 = true end
    end
end

-- v8: a host takes relayed items of `prefix` (handed over as dist "RELAY", the origin as a claimed sender).
function M:Relayable(prefix)
    if type(prefix) == "string" and prefix ~= "" and not M.CONTROL[prefix] then M.relayable[prefix] = true end
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
function M:Realm(prefix, payload, coalesceKey, relay)
    if type(prefix) ~= "string" or type(payload) ~= "string" then return end
    relay = relay and not M.CONTROL[prefix] and #payload <= M.RELAY_MAX or nil
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
    M._realmQueue[key] = { prefix = prefix, payload = payload, relay = relay }
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
    local now, braked = time(), Tripped()
    for _, name in ipairs(M:Peers()) do
        if not braked or Heard(M.view[name], now) then return true end
    end
    return not braked and DirFresh()
end

-- `k` distinct names at random among directory members and fresh peers outside the guild: heard peers and the
-- directory first (v8), names only passed on fill what is missing. `want(name)` narrows the choice.
-- v9: the directory only fills, from a list read within DIR_FRESH; with the brake on, heard peers only.
local function Pick(k, want, except)
    local now, seen, sure, named, out = time(), {}, {}, {}, {}
    local braked = Tripped()
    if except then for _, n in ipairs(except) do seen[n] = true end end
    local function add(name, list)
        if not seen[name] and (not want or want(name)) then seen[name], list[#list + 1] = true, name end
    end
    for _, name in ipairs(M:Peers()) do
        local v = M.view[name]
        if Heard(v, now) then add(name, sure) elseif not braked then add(name, named) end
    end
    if not braked and DirFresh() then
        for _, name in ipairs(M.dir.names) do
            if not (M.view[name] and M.view[name].guild) then add(name, named) end -- the guild gets it on GUILD
        end
    end
    for _, pool in ipairs({ sure, named }) do
        while #pool > 0 and #out < k do
            out[#out + 1] = table.remove(pool, math.random(1, #pool))
        end
    end
    return out
end

-- A whisper to a name that may have logged off: its "No player named" line, if one comes, is hidden and acted on.
local function WhisperTried(prefix, payload, name)
    M.dir.tried[name] = (GetTime and GetTime() or 0) + M.TRIED_SECONDS
    return Send(prefix, payload, "WHISPER", name)
end

-- ---------------------------------------------------------------------------
-- Relay (v8)
-- ---------------------------------------------------------------------------
-- My name as whispers spell it: "First Surname" on WoW: Forever, the plain name elsewhere.
local function MyName()
    if not UnitFullName then return nil end
    local first, second = UnitFullName("player")
    if type(first) ~= "string" or Secret(first) or Secret(second) then return nil end
    local surname = C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname and C_PlayerInfo.ShouldDisplaySurname()
    if surname and type(second) == "string" and second ~= "" then return first .. " " .. second end
    return first
end

local function Spend(b, limit)
    local now = time()
    if now - b.window >= 60 then b.window, b.used = now, 0 end
    if b.used >= limit then return false end
    b.used = b.used + 1
    return true
end

local function Envelope(id, hops, origin, prefix, payload)
    return table.concat({ "RL1", id, tostring(hops), origin, prefix, payload }, "|")
end

-- Remember an item; drop the oldest past SEEN_MAX and anything past SEEN_TTL.
local function See(key, guild)
    local seen, now = M.relay.seen, time()
    local e = seen[key]
    if e then
        if guild then e.guild = true end
        return false
    end
    local n, oldest, oldestAt = 0, nil, nil
    for k, v in pairs(seen) do
        if now - v.at > M.SEEN_TTL then
            seen[k] = nil
        else
            n = n + 1
            if not oldestAt or v.at < oldestAt then oldest, oldestAt = k, v.at end
        end
    end
    if n >= M.SEEN_MAX and oldest then seen[oldest] = nil end
    seen[key] = { at = now, guild = guild or nil }
    return true
end

local function IsV8(name)
    local v = M.view[name]
    return v and v.v8 or false
end

-- A new realm item of mine to be relayed: its envelope (or nil when I cannot say who I am).
local function NewEnvelope(item)
    local me = MyName()
    if not me or me:find("[,|]") then return nil end
    M.relay.seq = (M.relay.seq + 1) % 65536
    -- the random part keeps a forger from guessing my next id and taking its place in everyone's seen list
    local id = string.format("%x%04x%04x", time(), M.relay.seq, math.random(0, 0xffff))
    See(me .. "/" .. id)
    return Envelope(id, M.RELAY_HOPS, me, item.prefix, item.payload)
end

-- A claimed origin may fill RELAY_PER_ORIGIN of the passes a minute, and the real whisperer RELAY_PER_SENDER: an
-- origin is only claimed, so a spammer changing it on every item is still capped by who it is.
local function Used(o, who)
    local now = time()
    if now - o.window >= 60 then o.window, o.count = now, {} end
    return o.count[who] or 0
end

local function OriginRoom(origin, via)
    local s, o = M.relay.senders, M.relay.origins
    if Used(s, via) >= M.RELAY_PER_SENDER or Used(o, origin) >= M.RELAY_PER_ORIGIN then return false end
    s.count[via], o.count[origin] = Used(s, via) + 1, Used(o, origin) + 1 -- both counted only when both have room
    return true
end

local function SaidInGuild(key)
    local e = M.relay.seen[key]
    return e and e.guild
end

local function OnRelay(payload, sender, dist)
    if type(payload) ~= "string" or Secret(payload) or type(sender) ~= "string" or Secret(sender) then return end
    -- Where YELL lives (Anniversary) nothing is relayed. Before the session's first YELL tells which game this is,
    -- an envelope is handed to the host (on Forever that probe may be minutes away) but passed on nowhere.
    if M.probed.YELL then return end
    local id, hops, origin, prefix, inner = payload:match("^RL1|(%x+)|(%d)|([^|]+)|([%w_]+)|(.*)$")
    hops = tonumber(hops)
    if not id or #id > 16 or hops > M.RELAY_HOPS or #prefix > 16 or #inner > M.RELAY_MAX or M.CONTROL[prefix] then
        return
    end
    if origin:find(",", 1, true) or #origin > 48 then return end
    local via = WhisperName(sender)
    if IsMe(via) then return end -- my own guild relay, echoed back by the game
    if M.view[via] then M.view[via].v8 = true end
    origin = WhisperName(origin)
    if IsMe(origin) then return end
    local key = origin .. "/" .. id
    local fromGuild = dist == "GUILD"
    if not See(key, fromGuild) then
        M.stats.rlDup = M.stats.rlDup + 1
        return
    end
    M.stats.rlIn = M.stats.rlIn + 1
    Learn(origin, "named")
    local h = M.relayable[prefix] and M.handlers[prefix]
    if h then pcall(h, inner, origin, "RELAY", via, hops) end
    if dist ~= "WHISPER" or not M.dead.YELL or Quiet() then return end
    if not (M.FAMILY[prefix] or M.relayable[prefix]) or not OriginRoom(origin, via) then return end
    -- Into my guild, once, unless a guild mate says it first. An item from a guild mate: the guild has it already.
    local fromMate = M.view[origin] and M.view[origin].guild
    if not fromMate and IsInGuild and IsInGuild() and C_Timer and C_Timer.After then
        C_Timer.After(0.5 + math.random() * (M.GUILD_RELAY_DELAY - 0.5), function()
            if SaidInGuild(key) or Quiet() or not Spend(M.relay.gbudget, M.GUILD_RELAY_BUDGET) then return end
            local e = M.relay.seen[key] -- it may have left the list meanwhile (SEEN_MAX)
            if e then e.guild = true end
            if Send(M.RELAY_PREFIX, Envelope(id, 0, origin, prefix, inner), "GUILD") then
                M.stats.rlGuild = M.stats.rlGuild + 1
            end
        end)
    end
    if hops < 1 then return end
    for _, name in ipairs(Pick(M.RELAY_FANOUT, IsV8, { via, origin })) do
        if not Spend(M.relay.budget, M.RELAY_BUDGET) then break end
        if WhisperTried(M.RELAY_PREFIX, Envelope(id, hops - 1, origin, prefix, inner), name) then
            M.stats.rlFwd = M.stats.rlFwd + 1
        end
    end
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
        local envelope = item.relay and NewEnvelope(item)
        for _, name in ipairs(Pick(M.REALM_FANOUT)) do
            local wrapped = envelope and IsV8(name)
            if WhisperTried(wrapped and M.RELAY_PREFIX or item.prefix, wrapped and envelope or item.payload, name) then
                M.stats.dirSent = M.stats.dirSent + 1
                if wrapped then M.stats.rlOut = M.stats.rlOut + 1 end
            end
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
    -- The share keeps YELL under the public chat limit; a whisper outside an instance has no such limit (v8).
    if not (CanYell() and math.random(1, 100) <= M.YELL_PERCENT) and not CanWhisperWide() then
        return
    end
    M._draining = true
    EmitNextYell(0)
end
M.FlushRealm = FlushRealm

-- ---------------------------------------------------------------------------
-- Directory (v5): the member list of one hidden channel per faction. Nobody talks in it.
-- ---------------------------------------------------------------------------
-- v9: a list dropped (another channel now): the next check reads the new one, as on joining.
local function DropList()
    M.dir.names, M.dir.count, M.dir.index, M.dir.at, M.dir.asks, M.dir.askedAt = {}, 0, nil, nil, nil, nil
end

-- v9: the ruleset, where the game has regional unique names (Forever); nil elsewhere (Anniversary, retail).
local function Ruleset()
    local unique = RegionalUniqueNamesEnabled
    if type(unique) ~= "function" then return nil end
    local ok, on = pcall(unique)
    local rules, active = Enum and Enum.GameRule, C_GameRules and C_GameRules.IsGameRuleActive
    if not ok or on ~= true or type(rules) ~= "table" or type(active) ~= "function" then return nil end
    -- these names are not in the client's generated docs: if any is missing, keep the faction's name rather than
    -- put every ruleset in "PvE" without a word (the DIAG's dirch shows which name a client uses)
    if rules.HardcoreRuleset == nil or rules.RPRuleset == nil or rules.PvPRuleset == nil then return nil end
    local function is(rule)
        local done, yes = pcall(active, rules[rule])
        return done and yes == true
    end
    if is("HardcoreRuleset") then return "HC" end
    local rp, pvp = is("RPRuleset"), is("PvPRuleset")
    return (rp and pvp and "RPPvP") or (rp and "RP") or (pvp and "PvP") or "PvE"
end

-- The faction's channel of v5–v8, and (v9) the one in use: plus the ruleset, plus a number after a lock.
local function FactionName()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return M.DIR_PREFIX .. ((type(faction) == "string" and faction ~= "") and faction:sub(1, 1) or "N")
end

local function ChannelName()
    local num = M.dir.num or 1
    return FactionName() .. (Ruleset() or "") .. (num > 1 and tostring(num) or "")
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
    -- v9: the name may come out otherwise once the game knows the rules (a ruleset read before it did): the old
    -- channel is left and its list dropped, at most twice a session
    local want, justLeft = ChannelName(), nil
    if not M.dir.channel then
        M.dir.channel = want
    elseif M.dir.channel ~= want and (M.dir.renames or 0) < 2 then -- past the limit the channel stays as it is
        local old = M.dir.channel
        M.dir.renames, M.dir.past[old] = (M.dir.renames or 0) + 1, true
        justLeft = old -- left here: not again below in the same frame (a leave takes a moment to show)
        local inOld, oldId = pcall(GetChannelName, old)
        if inOld and tonumber(oldId) and tonumber(oldId) > 0 and LeaveChannelByName then pcall(LeaveChannelByName, old) end
        DropList()
        M.dir.retried, M.dir.rejoinAt, M.dir.channel = nil, nil, want
    end
    -- v9: the faction-wide channel of v5–v8 spans every ruleset; the game may put this client back in it at any
    -- point of the login, so it is looked for on every check and left once it shows up
    local legacy = FactionName()
    if M.dir.channel ~= legacy and not M.dir.legacyLeft and justLeft ~= legacy then
        M.dir.legacy = legacy
        local inOld, oldId = pcall(GetChannelName, legacy)
        if inOld and tonumber(oldId) and tonumber(oldId) > 0 and LeaveChannelByName then
            M.dir.legacyLeft = true
            pcall(LeaveChannelByName, legacy)
        end
    end
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
local LOCKED = { WRONG_PASSWORD = true, BANNED = true } -- v9: someone else holds the channel; the name is fine
local function OnNotice(kind, channel, base)
    local name = M.dir.channel
    if not name or M.dir.refused or Secret(kind) or Secret(channel) or Secret(base) or not REFUSED[kind] then return end
    if base ~= name and not (type(channel) == "string" and channel:find(name, 1, true)) then return end
    DropList()
    local ok, id = pcall(GetChannelName, name)
    if ok and tonumber(id) and tonumber(id) > 0 and LeaveChannelByName then pcall(LeaveChannelByName, name) end
    if LOCKED[kind] and (M.dir.num or 1) < M.DIR_MAX_NUM then
        M.dir.past[name] = true
        M.dir.num = (M.dir.num or 1) + 1
        M.dir.channel, M.dir.retried, M.dir.rejoinAt = ChannelName(), nil, time() + 3
        M.stats.dirMoves = (M.stats.dirMoves or 0) + 1
        if C_Timer and C_Timer.After then C_Timer.After(3, JoinDirectory) end
        return
    end
    M.dir.refused = kind
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
    M.dir.index, M.dir.asks, M.dir.askedAt = mine, (M.dir.asks or 0) + 1, time() -- v9
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
    M.nf[#M.nf + 1] = time() -- v9: the brake counts it
    M.stats.nf = M.stats.nf + 1
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
    if Secret(channel) or Secret(base) then return false end
    if type(base) == "string" and M.dir.past[base] then return true end -- v9: a channel this session left
    for _, name in ipairs({ M.dir.channel or false, M.dir.legacy or false }) do -- v9: the old faction channel too
        if name and (base == name or (type(channel) == "string" and channel:find(name, 1, true) ~= nil)) then
            return true
        end
    end
    return false
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

-- v11: closing a Blizzard dialog from here runs its close callbacks tainted; in gamepad mode they include the
-- gamepad's popup handler (guildos#315). Unknown counts as on.
local function GamepadOn()
    if not (C_GamePad and C_GamePad.IsEnabled) then return false end
    local ok, on = pcall(C_GamePad.IsEnabled)
    return not ok or on == true
end

local function CloseBox(name)
    if not StaticPopup_Hide or GamepadOn() then return end
    pcall(StaticPopup_Hide, "CHAT_CHANNEL_PASSWORD", name)
    -- whichever handler showed it may run after this one
    if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(StaticPopup_Hide, "CHAT_CHANNEL_PASSWORD", name) end) end
end

-- v11: the server wants a password for a family channel: someone holds it.
local function OnPasswordRequest(name)
    if type(name) ~= "string" or Secret(name) or name:lower():sub(1, #M.DIR_PREFIX) ~= M.DIR_PREFIX:lower() then return end
    CloseBox(name)
    local mine = M.dir.channel
    if M.dir.on and mine and name:lower() == mine:lower() then
        OnNotice("WRONG_PASSWORD", nil, mine)
        return
    end
    -- not the one in use: a saved channel the game rejoined at login, or one already moved away from
    M.dir.past[name] = true
    InstallFilters()
    if LeaveChannelByName then pcall(LeaveChannelByName, name) end
end

-- One frame and one ticker, bound to THIS version's functions (a superseded one's are cancelled/replaced).
M.dirFrame = M.dirFrame or (CreateFrame and CreateFrame("Frame")) or nil
if M.dirFrame then
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "CHANNEL_ROSTER_UPDATE")
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "PLAYER_ENTERING_WORLD")
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "CHAT_MSG_CHANNEL_NOTICE")
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "CHAT_MSG_CHANNEL_NOTICE_USER")
    pcall(M.dirFrame.RegisterEvent, M.dirFrame, "CHANNEL_PASSWORD_REQUEST") -- v11
    -- a channel notice: (kind, player, language, "N. Channel", player2, flags, zoneChannelID, index, baseName)
    M.dirFrame:SetScript("OnEvent", function(_, event, a, b, _, d, _, _, _, _, i)
        if event == "CHANNEL_ROSTER_UPDATE" then
            OnRoster(a, b)
        elseif event == "CHANNEL_PASSWORD_REQUEST" then
            OnPasswordRequest(a)
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
        -- v9: the whole list, from the server, only when it is old and links are few
        M.dir.jitter = M.dir.jitter or math.random(0, M.DIR_JITTER)
        local last = M.dir.at or ((M.dir.asks or 0) >= M.DIR_FIRST_TRIES and M.dir.askedAt) or nil
        if not last or (time() - last >= M.DIR_READ + M.dir.jitter and M:LinkCount() < M.DIR_ENOUGH) then
            RequestRoster()
        end
    end)
end

-- v9: a list an older copy read belongs to the faction-wide channel: not this version's directory
if M.dir.channel and M.dir.channel ~= ChannelName() then
    DropList()
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
    local braked = Tripped() -- v9: with the brake on, heard peers only
    for name, v in pairs(M.view) do
        if not braked or (Heard(v, now) and Usable(name)) then
            if Fresh(v, name, now) then
                if not bestAt or (v.asked or 0) < bestAt then best, bestAt = name, v.asked or 0 end
            elseif v.stored and not v.asked and Usable(name) then
                pool[#pool + 1] = name
            end
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
    if M.view[asker] then M.view[asker].asked = now end -- my answer is our exchange: no eager one on top (v8)
    if now - (pex.replied[asker] or 0) < M.PEX_REPLY_GAP then return end
    if now - pex.window >= 60 then pex.window, pex.answers = now, 0 end
    if pex.answers >= M.PEX_BUDGET then return end
    pex.replied[asker], pex.answers = now, pex.answers + 1
    WhisperTried(M.PEX_PREFIX, "PX1|a|" .. Sample(asker), asker) -- it may log off before the answer leaves
end
M:Register(M.PEX_PREFIX, OnPex)
M:Register(M.RELAY_PREFIX, OnRelay)

-- v8: a peer outside the guild heard for the first time gets my sample within seconds, not at its turn.
M._eagerPex = function(name)
    if not M.dead.YELL or not (C_Timer and C_Timer.After) then return end
    C_Timer.After(3 + math.random() * 5, function()
        local v = M.view[name]
        local now = time()
        if not v or v.guild or Quiet() or (v.asked and now - v.asked < M.PEX_INTERVAL) then return end
        if not Spend(M.pex.eager, M.PEX_EAGER) then return end
        LoadStores()
        v.asked = now
        WhisperTried(M.PEX_PREFIX, "PX1|q|" .. Sample(name), name)
    end)
end

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
