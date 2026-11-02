----------------------------------------------------------------------
-- Guild OS - ChehulGossip (specs/071-o-recrutamento in guildos-web, "ChehulNet")
-- Carries what a client holds past the zone and the layer of whoever yells. YELL, the mesh's widest
-- bus, stops at both, and an addon WHISPER crosses them from a timer. So every client keeps its own
-- list of who it has heard on the prefix and, each round, trades a digest with two of them: what the
-- other lacks comes back, with a few names, and the names are what cross zones.
--
-- All of it is GuildOS's alone: Libs/LibChehulMesh.lua and Modules/ChehulNet.lua ship identical in the
-- sibling addons and do not change. It moves up into them once it has been measured in the field.
-- Nothing here knows about recruitment: a topic says what it holds, and a topic's name is the first
-- field of its payload (RecruitBeacon's is "CR3").
--
--   CRB|ad|version|guild|officer  the beacon, from every client. Empty where there is nothing; guild
--                                 and officer only while the sender's guild is recruiting
--   CRD|name:v,name:v,...         a digest, up to DIGEST_MAX pairs: the newest, then the rest in rotation
--   CRG|name                      asks for one payload
--   CRP|name,name,...             up to PEX_MAX peers heard lately, only to who sent me a digest
--   CRW|token|try                 the whisper test, only ever sent to myself
--
-- The mesh keeps one handler per prefix and RecruitBeacon owns it: everything arriving goes to
-- :Receive first, and what nobody here routes (CR2 above all) goes back to RecruitBeacon.
----------------------------------------------------------------------
local Gossip = {}
GuildOS.ChehulGossip = Gossip

local Compat = GuildOS.Compat

Gossip.ROUND_SECONDS  = 120     -- a client opens exchanges this often at most
Gossip.ROUND_PEERS    = 2       -- peers a round talks to
Gossip.DIGEST_MAX     = 12      -- pairs in a digest
Gossip.DIGEST_NEWEST  = 4       -- of them, the seats kept for the newest ads by version
Gossip.REPLY_MAX      = 4       -- payloads in one answer
Gossip.PEX_MAX        = 5       -- names in a CRP
Gossip.HEARD_OF_MAX   = 10      -- names off lists held at once: what a round's two answers bring
Gossip.PEER_FRESH     = 300     -- seconds a peer stays on the list unheard
Gossip.BEACON_SECONDS = 180
Gossip.CHANNEL        = false   -- the beacon's route by a created channel: only a new version turns it on
Gossip.SENDER_MAX     = 30      -- messages heard from one sender per ROUND_SECONDS; a relayer's CR2 stays under it

local PREFIX        = "ChehulRecruit"       -- RecruitBeacon registers it
local BEACON_KEY    = PREFIX .. ":beacon"   -- Mesh:Realm coalesces on it: only ever one beacon waits to be yelled
local ROUND_JITTER  = 30      -- seconds added to a round and never taken off, so two rounds never share a ROUND_SECONDS
local TEST_DELAY    = 10      -- seconds after login before the whisper test
local TEST_WAIT     = 5       -- seconds an echo gets before the next spelling
local TRIED_SECONDS = 30      -- seconds the "no such player" line of a name I whispered stays hidden
local PAYLOAD_MAX   = 2048    -- bytes; a whole CR3 is under it, and a multi-part message can be anything
local NAME_MAX      = 96      -- bytes of a name: two names of three-byte letters and a realm
local GUILD_CHARS   = 24      -- the game's own limit

GuildOS.State.gossip = {
    peers     = {},   -- [whole name] = { name, at, guild, officer, heardOf, since, count, answered, served }
    topics    = {},   -- [name] = { digest, want, pull, push }
    routes    = {},   -- [first field] = fn(payload, sender, dist)
    tried     = {},   -- [whole name] = when the error line stops being hidden
    asked     = {},   -- [key] = version asked for this round
    asks      = 0,    -- questions asked this round
    dialed    = {},   -- [whole name] = true: a digest went there this round, and one list of names may come back
    failed    = {},   -- [error text] = true: each kind recorded once
    allowance = 0,    -- whispers left this round for answering anybody
    turns     = { digest = 0, beacon = 0 },   -- where each rotation stands
    stats     = { rounds = 0, adsIn = 0, adsOut = 0, dropped = 0 },
}
local S = GuildOS.State.gossip

-- What a round may answer: ROUND_PEERS answers of REPLY_MAX ads and a list of names. Without it the
-- traffic grows with the network: every client that heard somebody yell can ask that one somebody.
local function Allowance()
    return Gossip.ROUND_PEERS * (Gossip.REPLY_MAX + 1)
end
S.allowance = Allowance()

----------------------------------------------------------------------
-- An error here ends here: it never reaches a timer, the mesh, the boot or the export.
----------------------------------------------------------------------
local function Fail(err)
    local msg = "ChehulGossip: " .. tostring(err)
    if S.failed[msg] then return end
    S.failed[msg] = true
    GuildOS:RecordError(msg)
end

local function Guarded(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    Fail(result)
end

-- Nothing goes out inside an instance or in a chat lockdown: a boss fight is no time to gossip, and
-- the lockdown would only hold it all for later.
local function Quiet()
    return (IsInInstance and IsInInstance()) or Compat.InChatLockdown()
end

----------------------------------------------------------------------
-- Names
----------------------------------------------------------------------

-- Somebody's whole name. A sender on my realm arrives with the realm cut off, and that, passed on in a
-- CRP, reaches nobody from a connected realm. On WoW: Forever no realm tells anyone apart (a name is
-- unique in its region) and a sender's is whichever its client answers, so there it goes.
local function Whole(name)
    if GuildOS:RealmBound() then return GuildOS:KeyOfRosterName(name) end
    local first, surname = name:match("^([^%s%-]+)[%s%-]([^%s%-]+)")
    return first and (first .. " " .. surname) or name
end

local function IsName(name)
    return type(name) == "string" and name ~= "" and #name <= NAME_MAX and not name:find("[|,:%c]")
end

local function IsMe(whole)
    S.me = S.me or Whole(Compat.PlayerName())
    return whole == S.me
end

local function GuildText(guild)
    local text = GuildOS:Utf8Head(GuildOS:SanitizeUserText(guild), GUILD_CHARS)
    return text ~= "" and text or nil
end

-- `max` of `list` at random, in place.
local function Sample(list, max)
    local n = math.min(max, #list)
    for i = 1, n do
        local j = math.random(i, #list)
        list[i], list[j] = list[j], list[i]
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- What the digest and the beacon hold, in an order that makes a rotation of it mean something. A
-- name on the wire has neither ',' nor ':', and what is no name does not go out.
local function Holdings()
    local list = {}
    for _, topic in pairs(S.topics) do
        for _, entry in ipairs(Guarded(topic.digest) or {}) do
            local key = entry[1]:gsub("[,:]", " ")
            if IsName(key) then list[#list + 1] = { key = key, version = entry[2], topic = topic } end
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

-- The digest's two kinds of seat: the newest ads, and the rest for the rotation to walk. A rotation
-- alone leaves a new ad waiting for its turn among forty, an hour to cross fifty clients. Seated, it
-- goes in every digest at no cost: the digest is the same size, and nothing is sent on suspicion.
local function Seats(holdings)
    local byAge, newest, rest, seated = {}, {}, {}, {}
    for i, held in ipairs(holdings) do byAge[i] = held end
    table.sort(byAge, function(a, b)
        if a.version ~= b.version then return a.version > b.version end
        return a.key < b.key
    end)
    for i = 1, math.min(Gossip.DIGEST_NEWEST, #byAge) do
        newest[i], seated[byAge[i]] = byAge[i], true
    end
    for _, held in ipairs(holdings) do
        if not seated[held] then rest[#rest + 1] = held end
    end
    return newest, rest
end

-- The next `max` entries of a rotation. Digest and beacon each keep their own, or an ad a beacon
-- announced would be one a digest skips.
local function Turn(which, list, max)
    local out = {}
    for _ = 1, math.min(max, #list) do
        S.turns[which] = S.turns[which] % #list + 1
        out[#out + 1] = list[S.turns[which]]
    end
    return out
end

-- One answer out of the round's allowance; what it cannot pay for is a discard, and the asker gets
-- another chance from another peer next round.
local function Spend()
    if S.allowance > 0 then
        S.allowance = S.allowance - 1
        return true
    end
    S.stats.dropped = S.stats.dropped + 1
    return false
end

local function CanAnswer()
    return Gossip:CanWhisper() and not Quiet()
end

-- One ad to `peer`, who takes REPLY_MAX in a round however they ask: the allowance is for everybody,
-- and one sender asking twenty ways would otherwise spend it all.
local function Serve(peer, ad)
    if (peer.served or 0) >= Gossip.REPLY_MAX then
        S.stats.dropped = S.stats.dropped + 1
        return false
    end
    if not Spend() then return false end
    peer.served = (peer.served or 0) + 1
    S.stats.adsOut = S.stats.adsOut + 1
    Gossip:Whisper(peer.name, ad)
    return true
end

-- Asks `sender` for what they hold if I want it, once a round, however many have it. REPLY_MAX
-- questions a round: no peer gives one asker more, and the rest of the allowance is for answering.
local function Ask(key, version, sender)
    if S.asks >= Gossip.REPLY_MAX or (S.asked[key] or -1) >= version then return end
    for _, topic in pairs(S.topics) do
        if Guarded(topic.want, key, version) then
            if Spend() then
                S.asks, S.asked[key] = S.asks + 1, version
                Gossip:Whisper(sender, "CRG|" .. key)
            end
            return
        end
    end
end

-- Who a round talks to. A name off a list takes one seat at most: that seat is how a round reaches
-- past what it hears, and the rest go to who I heard myself, so that a list can never replace them.
local function Pick(peers)
    local heard, told = {}, {}
    for _, peer in ipairs(peers) do
        local kind = peer.heardOf and told or heard
        kind[#kind + 1] = peer
    end
    Sample(told, 1)
    Sample(heard, Gossip.ROUND_PEERS - #told)
    heard[#heard + 1] = told[1]
    return heard
end

----------------------------------------------------------------------
-- The whisper test. Nothing proves that an addon whisper to "First Surname" arrives on WoW: Forever,
-- so a client tries it on itself: the space the game writes, then the hyphen of the character folders.
-- A name with no surname has nothing to choose. Until one comes back :CanWhisper() is false.
----------------------------------------------------------------------
local function TryNext(test)
    if S.test ~= test then return end   -- an echo already settled it
    -- First: a try that raises must not take the next spelling down with it.
    Compat.After(TEST_WAIT, function() Guarded(TryNext, test) end)
    -- A try that finds the door shut waits behind it, a login inside an instance included: otherwise
    -- walking in mid-test would read as "no whisper" for the whole session.
    if Quiet() then return end
    test.at = test.at + 1
    local try = test.tries[test.at]
    if not try then
        S.test = nil
        return
    end
    S.tried[Whole(try.name)] = GetTime() + TRIED_SECONDS
    Compat.SendAddonMessageNow(PREFIX, "CRW|" .. test.token .. "|" .. test.at, "WHISPER", try.name)
end

local function StartTest()
    local me = Compat.PlayerName()
    local tries = { { name = me, spelling = "plain" } }
    if GuildOS.Client.has.surnames and me:find(" ", 1, true) then
        tries = { { name = me, spelling = "space" }, { name = (me:gsub(" ", "-")), spelling = "hyphen" } }
    end
    S.test = { tries = tries, at = 0, token = tostring(math.random(1, 2147483647)) }
    TryNext(S.test)
end

-- The token keeps anybody else from telling me that my whisper works.
local function OnTest(payload)
    local test = S.test
    if not test then return end
    local _, token, at = strsplit("|", payload)
    local try = token == test.token and test.tries[tonumber(at) or 0]
    if try then S.whisper, S.test = try.spelling, nil end
end

-- The client's "no such player" line, for a name I tried and nobody else's. A peer that answers this
-- way has logged off, and is not worth another round. Chat in lockdown is secret, and a chat frame
-- is no place to raise.
local function IsTried(msg)
    if Compat.IsSecret(msg) or not next(S.tried) then return false end
    local args = GuildOS:MatchFormat(msg, ERR_CHAT_PLAYER_NOT_FOUND_S)
    local name = args and Whole(args[1])
    local till = name and S.tried[name]
    if not till or GetTime() > till then return false end
    S.peers[name] = nil
    return true
end

local function HideNotFound(_, _, msg)
    return Guarded(IsTried, msg)
end

----------------------------------------------------------------------
-- What arrives
----------------------------------------------------------------------
local function OnBeacon(payload, sender)
    local _, key, version, guild, officer = strsplit("|", payload)
    Gossip:Note(sender, guild or "", officer == "1")
    version = tonumber(version)
    if IsName(key) and version and CanAnswer() then Ask(key, version, sender) end
end

-- An answer to a digest, one per sender per round. One that fits says all the sender holds, so what it
-- leaves out is what they lack. A full one has left things out on purpose, and sending on suspicion would
-- be REPLY_MAX ads a round between two clients holding the same forty. It still proves one thing: its
-- first seats are the sender's newest, so an ad newer than the last of them that it does not list is
-- one it lacks, or it would have a seat. Anything older comes from asking, the other way, when my
-- digest lists it.
local function OnDigest(payload, sender)
    if not CanAnswer() then return end
    local peer = S.peers[Whole(sender)]
    if peer.answered or S.allowance <= 0 then
        S.stats.dropped = S.stats.dropped + 1
        return
    end
    peer.answered = true
    local listed, order = {}, {}
    for name, version in payload:gmatch("([^,:|]+):(%d+)") do
        if #order >= Gossip.DIGEST_MAX then break end
        if IsName(name) and not listed[name] then
            order[#order + 1] = name
            listed[name] = tonumber(version)
        end
    end
    -- The names go first, because they are what crosses zones: an answer that has spent itself on ads
    -- and questions leaves its asker knowing nobody new. Only who I heard myself: passed on from a
    -- list, a name that logged off would circle for ever.
    local names = {}
    for _, known in ipairs(Gossip:Peers()) do
        if not known.heardOf and known ~= peer then names[#names + 1] = known.name end
    end
    Sample(names, Gossip.PEX_MAX)
    if #names > 0 and Spend() then Gossip:Whisper(peer.name, "CRP|" .. table.concat(names, ",")) end
    local proved = #order < Gossip.DIGEST_MAX and -1 or listed[order[Gossip.DIGEST_NEWEST]]
    for _, held in ipairs(Holdings()) do
        local theirs = listed[held.key]
        if (theirs and theirs < held.version) or (not theirs and held.version > proved) then
            local ad = Guarded(held.topic.pull, held.key)
            if type(ad) == "string" and not Serve(peer, ad) then break end
        end
    end
    for _, name in ipairs(order) do Ask(name, listed[name], peer.name) end   -- in its order: newest first
end

local function OnGet(payload, sender)
    if not CanAnswer() then return end
    local key = payload:sub(#"CRG|" + 1)
    if not IsName(key) then return end
    for _, topic in pairs(S.topics) do
        local ad = Guarded(topic.pull, key)
        if type(ad) == "string" then
            Serve(S.peers[Whole(sender)], ad)
            return
        end
    end
end

-- A list of names is read only from somebody I sent a digest this round, and once: a list from anybody
-- is a way to fill my rounds with strangers. A name off it is somebody to try, for as long as a peer is
-- fresh; hearing of them again does not renew it. Only hearing them does.
local function OnNames(payload, sender)
    local from = Whole(sender)
    if not S.dialed[from] then
        S.stats.dropped = S.stats.dropped + 1
        return
    end
    S.dialed[from] = nil
    local room = Gossip.HEARD_OF_MAX
    for _, peer in ipairs(Gossip:Peers()) do
        if peer.heardOf then room = room - 1 end
    end
    local count = 0
    for name in payload:sub(#"CRP|" + 1):gmatch("[^,]+") do
        count = count + 1
        if count > Gossip.PEX_MAX or room <= 0 then break end
        if IsName(name) then
            local whole = Whole(name)
            if not IsMe(whole) and not S.peers[whole] then
                S.peers[whole] = { name = whole, at = GetTime(), heardOf = true }
                room = room - 1
            end
        end
    end
end

S.routes.CRB, S.routes.CRD, S.routes.CRG, S.routes.CRP = OnBeacon, OnDigest, OnGet, OnNames

-- Everything on the prefix makes a peer, whoever it is for. Returns whether it stops here.
local function Route(payload, sender, dist)
    if Compat.IsSecret(payload, sender) or type(payload) ~= "string" or #payload > PAYLOAD_MAX or not IsName(sender) then
        return true
    end
    local op = payload:match("^[^|]*")
    if op == "CRW" then
        OnTest(payload)
        return true
    end
    local route = S.routes[op]
    if IsMe(Whole(sender)) then return route ~= nil end   -- GUILD and YELL come back to who sent them
    local peer, now = Gossip:Note(sender), GetTime()
    if not peer.since or now - peer.since >= Gossip.ROUND_SECONDS then peer.since, peer.count = now, 0 end
    peer.count = peer.count + 1
    if peer.count > Gossip.SENDER_MAX then
        S.stats.dropped = S.stats.dropped + 1
        return true
    end
    if not route then return false end
    route(payload, sender, dist)
    return true
end

----------------------------------------------------------------------
-- Timers
----------------------------------------------------------------------

-- A beacon: presence for whoever hears it, and one ad in turn for whoever lacks it. A guild is
-- recruiting when its own ad is among what this client holds.
function Gossip:Beacon()
    local mesh = _G.ChehulMesh
    if Quiet() or not mesh then return end
    local holdings = Holdings()
    local ad = Turn("beacon", holdings, 1)[1]
    local guild, officer = "", ""
    local mine = GetGuildInfo("player")
    if mine then
        for _, held in ipairs(holdings) do
            if held.key == mine then
                guild, officer = mine, GuildOS:IsOfficer() and "1" or "0"
                break
            end
        end
    end
    local payload = table.concat({ "CRB", ad and ad.key or "", ad and ad.version or "", guild, officer }, "|")
    mesh:Guild(PREFIX, payload)
    mesh:Group(PREFIX, payload)
    mesh:Realm(PREFIX, payload, BEACON_KEY)
end

-- One round: the allowance comes back, and a digest goes to up to ROUND_PEERS peers. An empty digest
-- still goes: that is how a newcomer says it holds nothing.
function Gossip:Round()
    S.allowance, S.asks, S.asked, S.dialed = Allowance(), 0, {}, {}
    local now = GetTime()
    for name, till in pairs(S.tried) do
        if now > till then S.tried[name] = nil end
    end
    local peers = self:Peers()   -- asked before anything can stop the round: this is what prunes the list
    for _, peer in ipairs(peers) do peer.answered, peer.served = nil, nil end
    if not CanAnswer() then return end
    local picks = Pick(peers)
    if #picks == 0 then return end
    local newest, rest = Seats(Holdings())
    for _, peer in ipairs(picks) do
        local listed = {}
        for _, held in ipairs(newest) do listed[#listed + 1] = held.key .. ":" .. held.version end
        for _, held in ipairs(Turn("digest", rest, self.DIGEST_MAX - #newest)) do
            listed[#listed + 1] = held.key .. ":" .. held.version
        end
        S.dialed[peer.name] = true
        self:Whisper(peer.name, "CRD|" .. table.concat(listed, ","))
    end
    S.stats.rounds = S.stats.rounds + 1
end

-- Not a ticker: the variation has to add to the gap, not move the same tick around.
local function ScheduleRound()
    Compat.After(Gossip.ROUND_SECONDS + math.random(0, ROUND_JITTER), function()
        Guarded(Gossip.Round, Gossip)
        ScheduleRound()
    end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Starts the gossip on WoW: Forever and retail; Anniversary keeps the plain beacon.
function Gossip:Initialize()
    if S.started or GuildOS.Client.isAnniversary then return end
    S.started = true
    -- A try at an offline name prints a line, and none may: with no filter there is no test, so no whisper.
    local filtered = Guarded(Compat.AddChatFilter, "CHAT_MSG_SYSTEM", HideNotFound)
    Compat.After(TEST_DELAY, function()
        if filtered then Guarded(StartTest) end
        Guarded(Gossip.Beacon, Gossip)
    end)
    Compat.NewTicker(self.BEACON_SECONDS, function() Guarded(Gossip.Beacon, Gossip) end)
    ScheduleRound()
end

-- A message on the prefix, from RecruitBeacon's one handler. True when it stops here; false hands it
-- back, which is what CR2 needs.
function Gossip:Receive(payload, sender, dist)
    if not S.started then return false end
    local ok, stopped = pcall(Route, payload, sender, dist)
    if ok then return stopped end
    Fail(stopped)
    return true
end

-- Routes messages whose first field is `op` to fn(payload, sender, dist).
function Gossip:On(op, fn)
    S.routes[op] = fn
end

-- Registers a topic: `name` is the first field of its payloads. spec = { digest = fn() -> {{key, version}},
-- want = fn(key, version) -> bool, pull = fn(key) -> payload|nil, push = fn(payload, sender) }.
function Gossip:Topic(name, spec)
    S.topics[name] = spec
    self:On(name, function(payload, sender)
        S.stats.adsIn = S.stats.adsIn + 1
        spec.push(payload, sender)
    end)
end

-- Records a peer heard just now, by the whole sender, and returns it. `guild` "" says they are not
-- recruiting; nil says nothing about it.
function Gossip:Note(sender, guild, officer)
    if not IsName(sender) then return nil end
    local name = Whole(sender)
    if IsMe(name) then return nil end
    local peer = S.peers[name]
    if not peer then
        peer = { name = name }
        S.peers[name] = peer
    end
    peer.at, peer.heardOf = GetTime(), nil
    if guild then
        peer.guild = GuildText(guild)
        peer.officer = (peer.guild and officer) and true or false
    end
    return peer
end

-- The peers heard in the last PEER_FRESH seconds, latest first; the stale ones go here.
function Gossip:Peers()
    local list, now = {}, GetTime()
    for name, peer in pairs(S.peers) do
        if now - peer.at > self.PEER_FRESH then
            S.peers[name] = nil
        else
            list[#list + 1] = peer
        end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    return list
end

-- Who to reach `guild` through: an officer heard lately, else a member; nil with nobody. Second value: officer.
function Gossip:PeerFor(guild)
    local wanted, best = GuildText(guild), nil
    if not wanted then return nil end
    for _, peer in ipairs(self:Peers()) do
        if peer.guild == wanted and (not best or (peer.officer and not best.officer)) then best = peer end
    end
    if best then return best.name, best.officer end
    return nil
end

-- What the Audit panel reads. `whisper` is the spelling the test kept, false with none.
function Gossip:Stats()
    local s = S.stats
    return { rounds = s.rounds, adsIn = s.adsIn, adsOut = s.adsOut, dropped = s.dropped,
             peers = #self:Peers(), whisper = S.whisper or false }
end

-- `name` as this client's whispers reach it: whole, in the spelling the test kept.
function Gossip:WhisperName(name)
    local whole = Whole(name)
    if S.whisper == "hyphen" then return (whole:gsub(" ", "-")) end
    return whole
end

-- Whether a whisper from this client arrives: its own came back this session.
function Gossip:CanWhisper()
    return S.whisper ~= nil
end

-- An addon whisper to `name`, its error line hidden while it is tried. False when nothing went.
function Gossip:Whisper(name, payload)
    local mesh = _G.ChehulMesh
    if not (mesh and self:CanWhisper()) or Quiet() then return false end
    local target = self:WhisperName(name)
    S.tried[Whole(target)] = GetTime() + TRIED_SECONDS
    return mesh:Whisper(PREFIX, payload, target)
end
