----------------------------------------------------------------------
-- RecruitBeacon — guild recruitment over the Chehul mesh, with GOSSIP RELAY so
-- an ad lives in the network even when no officer is online.
--
-- Two sides on the shared transport _G.ChehulMesh:
--   * Officers compose an ad (roles/classes wanted, languages, guild focus,
--     days, a note, how long to stay live) and re-broadcast it while online.
--   * EVERY client caches ads it hears (persisted, capped, expiry-pruned) and
--     relays a rotating subset each cycle. So the ad propagates epidemically and
--     survives any single officer/relayer logging off, up to its officer-set TTL.
--     A client that logs back in re-seeds the network from its persisted cache.
--
-- Reach per hop is YELL (zone/city-wide, same-faction/layer); multi-hop gossip
-- spreads it across zones and relayers over time. Freshness uses GetServerTime()
-- (consistent across a realm): version = edit time (newer content wins); expiry
-- = "live until" (slides forward while the officer broadcasts, then counts down).
--
-- ── OPEN PROTOCOL (shared contract; any Chehul addon may broadcast/relay/consume)
--   prefix : "ChehulRecruit"
--   ad     : "CR2|guild|faction|needs|days|note|langs|focus|version|expiry"
--     needs/langs/focus : '+'-joined tokens · days/note : free text (no '|')
--     version, expiry   : GetServerTime() integers
--   ad (CR3): "CR3|name|f|w|p|d|s|e|pc|l|fo|r|c|lo|t|ct|u|v|x" - the site's GosrecrAd, fields in the
--     order of specs/071; lists '+'-joined, d ','-joined, '|' never inside a field. Whisper and GUILD
--     only. It has no removal: it leaves by x, and x is cut to 72 hours ahead on the way in.
----------------------------------------------------------------------
local RB = {}
GuildOS.RecruitBeacon = RB

RB.PREFIX = "ChehulRecruit"
RB.PROTO  = "CR2"
RB.PROTO3 = "CR3"

RB.BROADCAST_INTERVAL = 60    -- officer re-broadcast cadence (also refreshes expiry)
RB.RELAY_INTERVAL     = 30    -- everyone: relay a subset of cached ads
RB.RELAY_PER_TICK     = 4     -- cap ads yelled per relay cycle (anti-spam)
RB.CACHE_CAP          = 40    -- max cached ads (evict soonest-to-expire over cap)
RB.DEFAULT_TTL_DAYS   = 7
RB.MAX_AHEAD          = 72 * 3600   -- a CR3's validity is cut to this far ahead on arrival
RB.CLOCK_SKEW         = 600         -- seconds a version may be ahead of this clock: a forged future one would hold a digest seat for good

-- Vocabulary the officer picks from / a recruit filters on.
RB.ROLE_TOKENS  = { "TANK", "HEALER", "DPS" }
RB.CLASS_TOKENS = GuildOS.Client.classes   -- this game's classes (thirteen on retail)
RB.FOCUS_TOKENS = { "RAID", "PVP", "CASUAL", "LEVELING", "SOCIAL", "RP" }
RB.LANG_TOKENS  = { "enUS", "ptBR", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW", "itIT" }

RB.onUpdate = nil        -- UI hook (inbox panel sets it)
local relayCursor = 0
local CR3_FIELDS = 19         -- the name of the message and the 18 fields after it
local CR3_MAX    = 2048       -- bytes; a whole one is under a kilobyte

local function now() return (GetServerTime and GetServerTime()) or time() end
local function sanitize(s) return (tostring(s or ""):gsub("|", "/")) end
local function joinList(t) return table.concat(t or {}, "+") end
local function splitSet(s)
    local set = {}
    for t in string.gmatch(s or "", "[^+]+") do set[t] = true end
    return set
end

----------------------------------------------------------------------
-- Officer's editable ad. db.recruitBeacon = {
--   enabled, needs={}, langs={}, focus={}, days="", note="", ttlDays, version }
----------------------------------------------------------------------
function RB:GetAd()
    if not GuildOS.db then return nil end
    local ad = GuildOS.db.recruitBeacon
    if not ad then
        ad = { enabled = false, needs = {}, langs = {}, focus = {},
               days = "", note = "", ttlDays = self.DEFAULT_TTL_DAYS, version = 0 }
        GuildOS.db.recruitBeacon = ad
    end
    ad.needs   = ad.needs   or {}
    ad.langs   = ad.langs   or {}
    ad.focus   = ad.focus   or {}
    ad.ttlDays = ad.ttlDays or self.DEFAULT_TTL_DAYS
    ad.version = ad.version or 0
    return ad
end

-- Any edit bumps the version so relayers adopt the new content.
function RB:SetAdField(key, value)
    local ad = self:GetAd()
    if not ad then return end
    ad[key] = value
    ad.version = now()
end

-- Bump the version after an in-place edit of a list field (needs/langs/focus).
function RB:MarkEdited()
    local ad = self:GetAd()
    if ad then ad.version = now() end
end

----------------------------------------------------------------------
-- Persisted relay/inbox cache: db.recruitRelay[guild] = {
--   guild, faction, needs=set, days, note, langs=set, focus=set,
--   version, expiry, from }
----------------------------------------------------------------------
function RB:Cache()
    if not GuildOS.db then return {} end
    GuildOS.db.recruitRelay = GuildOS.db.recruitRelay or {}
    return GuildOS.db.recruitRelay
end

function RB:Prune()
    self:Prune3()
    local cache, n = self:Cache(), now()
    for g, ad in pairs(cache) do
        if (ad.expiry or 0) <= n then cache[g] = nil end
    end
    -- Enforce cap: drop the soonest-to-expire beyond CACHE_CAP.
    local list = {}
    for _, ad in pairs(cache) do list[#list + 1] = ad end
    if #list > self.CACHE_CAP then
        table.sort(list, function(a, b) return (a.expiry or 0) < (b.expiry or 0) end)
        for i = 1, #list - self.CACHE_CAP do cache[list[i].guild] = nil end
    end
end

----------------------------------------------------------------------
-- The CR3 cache, db.recruitAds[key] = a GuildFinder ad (the site's shape, no heard or verified: those are
-- worked out when it is read, never stored). The key is the guild's name as the digest spells it.
----------------------------------------------------------------------
function RB:Cache3()
    if not GuildOS.db then return {} end
    GuildOS.db.recruitAds = GuildOS.db.recruitAds or {}
    return GuildOS.db.recruitAds
end

-- Whether `key` names this character's own guild. The site and the game do not agree on the case of a name.
local function IsOwnGuild(key)
    local mine = GetGuildInfo and GetGuildInfo("player")
    return mine ~= nil and mine ~= "" and (mine:gsub("[,:]", " ")):lower() == key:lower()
end

-- A CR3 leaves by expiring and by the cap, never because a message said so. The cap takes the soonest to
-- expire, and among those the oldest version: one export gives a whole list the same validity. The
-- guild's own ad holds no seat among them: it is what says the guild in the beacon, and the night with more
-- guilds than seats is the night it matters.
function RB:Prune3()
    local cache, n = self:Cache3(), now()
    local list = {}
    for key, ad in pairs(cache) do
        if (ad.x or 0) <= n then
            cache[key] = nil
        elseif not IsOwnGuild(key) then
            list[#list + 1] = ad
        end
    end
    if #list > self.CACHE_CAP then
        table.sort(list, function(a, b)
            if a.x ~= b.x then return a.x < b.x end
            if a.v ~= b.v then return a.v < b.v end
            return a.key < b.key
        end)
        for i = 1, #list - self.CACHE_CAP do cache[list[i].key] = nil end
    end
end

-- The CR3 ads heard, minus the player's own guild (as GetInbox leaves it out), as copies.
function RB:Heard3()
    self:Prune3()
    local mine = GetGuildInfo and GetGuildInfo("player")
    local out = {}
    for _, ad in pairs(self:Cache3()) do
        if not (mine and mine == ad.n) then
            local copy = {}
            for k, v in pairs(ad) do copy[k] = v end
            out[#out + 1] = copy
        end
    end
    return out
end

local function field(v) return v == nil and "" or (tostring(v):gsub("|", "")) end
local function join(t, sep, strip)
    local out = {}
    for i, v in ipairs(t or {}) do out[i] = strip and (tostring(v):gsub("[|+,]", " ")) or tostring(v) end
    return table.concat(out, sep)
end

-- A CR3 payload out of an ad. Nothing in a field may be a '|', and a contact may not hold the list's '+'.
function RB:AdToPayload(ad)
    return table.concat({
        self.PROTO3, field(ad.n), field(ad.f), field(ad.w), field(ad.p), join(ad.d, ","), field(ad.s), field(ad.e),
        field(ad.pc), join(ad.l, "+"), join(ad.fo, "+"), join(ad.r, "+"), join(ad.c, "+"), field(ad.lo), field(ad.t),
        join(ad.ct, "+", true), field(ad.u), field(ad.v), field(ad.x),
    }, "|")
end

local function splitList(s, sep)
    local out = {}
    for item in string.gmatch(s or "", "[^" .. sep .. "]+") do out[#out + 1] = item end
    return out
end

-- Keeps a CR3 ad: a newer version replaces, an older does not, the same version only renews the validity.
local function Store(ad)
    local cache = RB:Cache3()
    local cur = cache[ad.key]
    if cur then
        if ad.v < cur.v then return false end
        if ad.v == cur.v then
            if ad.x <= cur.x then return false end
            cur.x = ad.x
            return true
        end
    end
    cache[ad.key] = ad
    RB:Prune3()
    return true
end

-- The ad in a CR3 payload, cleaned by GuildFinder (every text inert, one line, cut by character; every
-- list a closed set), or nil. `x` is cut to 72 hours ahead whatever came; one already past is no ad and
-- deletes nothing; a version from the future is refused.
local function ReadCR3(payload)
    local GF = GuildOS.GuildFinder
    if type(payload) ~= "string" or #payload > CR3_MAX or not GF then return nil end
    local f = { strsplit("|", payload) }
    if f[1] ~= RB.PROTO3 or #f < CR3_FIELDS then return nil end
    local v, x, t = tonumber(f[18]), tonumber(f[19]), now()
    if not v or not x or v <= 0 or v > t + RB.CLOCK_SKEW or x <= t then return nil end
    local days = {}
    for _, d in ipairs(splitList(f[6], ",")) do days[#days + 1] = tonumber(d) end
    local ad = GF:Normalize({
        n = f[2], f = f[3], w = f[4], p = f[5], d = days, s = tonumber(f[7]), e = tonumber(f[8]), pc = f[9],
        l = splitList(f[10], "+"), fo = splitList(f[11], "+"), r = splitList(f[12], "+"), c = splitList(f[13], "+"),
        lo = f[14], t = f[15], ct = splitList(f[16], "+"), u = f[17], v = math.floor(v), x = math.min(math.floor(x), t + RB.MAX_AHEAD),
    })
    if not ad then return nil end
    ad.heard, ad.verified, ad.dt, ad.m = nil, nil, nil, nil
    ad.key = (ad.n:gsub("[,:]", " "))
    return ad
end

-- A CR3 off the network. True when it was kept or renewed something. This guild's own ad comes from its
-- site block, or from an officer over GUILD: that is how a member holds it, says the guild in its beacon and
-- takes a request. By any other road a peer cannot hold its slot, a whisper in an officer's name least of
-- all (IsOfficerByName drops the realm). A roster not loaded yet vouches for nobody, and the officer's
-- next repeat lands.
function RB:IngestCR3(payload, sender, dist)
    local ad = ReadCR3(payload)
    if not ad then return false end
    if IsOwnGuild(ad.key) and not (dist == "GUILD" and GuildOS:IsOfficerByName(sender)) then return false end
    if not Store(ad) then return false end
    if self.onUpdate then pcall(self.onUpdate) end
    return true
end

-- The guild's own ad, out of the site's GOSGILD1, into the cache under the name the game spells (it is
-- what the beacon compares to know this guild recruits). Nil with none.
function RB:SeedOwnAd()
    local Import = GuildOS.CompanionImport
    local mine = GetGuildInfo and GetGuildInfo("player")
    local own = Import and Import.OwnRecruitAd and Import:OwnRecruitAd()
    if not own or not mine or mine == "" then return nil end
    own.n, own.key = mine, (mine:gsub("[,:]", " "))
    own.dt, own.m = nil, nil
    own.x = math.min(own.x, now() + self.MAX_AHEAD)
    self:Cache3()[own.key] = own   -- unconditional: whatever sat in the slot, the site's ad is the guild's
    self:Prune3()
    return own
end

-- What this client can hand over, by key: the CR3 cache and the live ads of the site's list, which is how
-- the companion's list reaches who has no companion (the owner's call in specs/071). One ad per name: the
-- newer version, and at the same version the list's, which no peer wrote. The list is read here and never
-- copied into the cache: forty seats would not hold it, and the seal stays with whoever's own list it is.
local function Held()
    RB:SeedOwnAd()
    RB:Prune3()
    local held, t = {}, now()
    for key, ad in pairs(RB:Cache3()) do held[key] = ad end
    local GF = GuildOS.GuildFinder
    for _, ad in ipairs(GF and GF:Directory() or {}) do
        local key = ad.n:gsub("[,:]", " ")
        local cur = held[key]
        if ad.x > t and (not cur or ad.v >= cur.v) then held[key] = ad end
    end
    return held
end

----------------------------------------------------------------------
-- Init: register receiver + officer-broadcast + gossip-relay tickers.
----------------------------------------------------------------------
function RB:Initialize()
    self:Prune()
    local mesh = _G.ChehulMesh
    if mesh and not self._registered then
        self._registered = true
        -- The mesh keeps one handler per prefix: the gossip reads the first field, and CR2 comes back here.
        mesh:Register(self.PREFIX, function(payload, sender, dist)
            local gossip = GuildOS.ChehulGossip
            if not (gossip and gossip:Receive(payload, sender, dist)) then RB:OnMessage(payload, sender) end
        end)
    end
    local gossip = GuildOS.ChehulGossip
    if gossip and gossip.Topic and not self._topic then
        self._topic = true
        -- The gossip trades CR3 by guild name and version, out of what this client holds (Held). The digest
        -- holds the guild's own ad: that is how the beacon knows this guild recruits.
        gossip:Topic(self.PROTO3, {
            digest = function()
                local out = {}
                for key, ad in pairs(Held()) do out[#out + 1] = { key, ad.v } end
                return out
            end,
            want = function(key, version)
                if type(version) ~= "number" or version > now() + RB.CLOCK_SKEW then return false end
                -- Never asked for: it comes by GUILD from an officer, and a guildmate would only refuse what it got.
                if IsOwnGuild(key) then return false end
                local cur = Held()[key]
                return not cur or cur.v < version
            end,
            pull = function(key)
                local ad = Held()[key]
                if ad and ad.x > now() then return RB:AdToPayload(ad) end
            end,
            push = function(payload, sender, dist) RB:IngestCR3(payload, sender, dist) end,
        })
    end
    if C_Timer and C_Timer.NewTicker then
        if not self._bcast then
            self._bcast = C_Timer.NewTicker(self.BROADCAST_INTERVAL, function() GuildOS:SafeCall(RB.Broadcast, RB) end)
            if C_Timer.After then C_Timer.After(8, function() GuildOS:SafeCall(RB.Broadcast, RB) end) end
        end
        if not self._relay then
            self._relay = C_Timer.NewTicker(self.RELAY_INTERVAL, function() GuildOS:SafeCall(RB.RelayTick, RB) end)
        end
    end
end

----------------------------------------------------------------------
-- Build the wire payload from a cache record.
----------------------------------------------------------------------
local function RecordToPayload(r)
    return table.concat({
        RB.PROTO, sanitize(r.guild), r.faction or "H",
        joinList(r.needsList or {}), sanitize(r.days), sanitize(r.note),
        joinList(r.langsList or {}), joinList(r.focusList or {}),
        tostring(r.version or 0), tostring(r.expiry or 0), sanitize(r.author or ""),
    }, "|")
end

-- Serialize a *cache* record (which stores sets) back to a payload.
local function CacheRecordToPayload(ad)
    local function setToList(s) local l = {} for k in pairs(s or {}) do l[#l+1] = k end return l end
    return RecordToPayload({
        guild = ad.guild, faction = ad.faction,
        needsList = setToList(ad.needs), days = ad.days, note = ad.note,
        langsList = setToList(ad.langs), focusList = setToList(ad.focus),
        version = ad.version, expiry = ad.expiry, author = ad.from,
    })
end

----------------------------------------------------------------------
-- Officer side: broadcast the guild's ad (guild bus + zone-wide YELL) and seed
-- it into our own cache so guildmates relay it too. Refreshes expiry each cycle
-- (keeps the ad alive while any officer is online; it decays after they leave).
----------------------------------------------------------------------
-- The site's ad as a CR2, for the clients that predate CR3.
local function OwnAdAsCR2(own, guild, faction)
    local needs, langs, focus = {}, {}, {}
    for _, t in ipairs(own.r or {}) do needs[#needs + 1] = t end
    for _, t in ipairs(own.c or {}) do needs[#needs + 1] = t end
    local code = {}
    for k, v in pairs(GuildOS.GuildFinder.CR2_LANG) do code[v] = k end
    for _, l in ipairs(own.l or {}) do if code[l] then langs[#langs + 1] = code[l] end end
    for _, t in ipairs(own.fo or {}) do focus[#focus + 1] = t end
    if own.pc == "casual" then focus[#focus + 1] = "CASUAL" end
    return RecordToPayload({
        guild = guild, faction = own.f or faction, needsList = needs, days = "", note = own.p or "",
        langsList = langs, focusList = focus, version = own.v, expiry = own.x, author = GuildOS.Compat.PlayerName(),
    })
end

function RB:Broadcast()
    if not (GuildOS.IsOfficer and GuildOS:IsOfficer()) then return end
    if IsInGuild and not IsInGuild() then return end
    -- A raid is no time for the ad: it pauses where the gossip does, and the ticker picks it up on the way out.
    local gossip = GuildOS.ChehulGossip
    if gossip and gossip.Quiet and gossip:Quiet() then return end
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not guild or guild == "" then return end
    local mesh = _G.ChehulMesh
    if not mesh then return end

    -- The site's ad, when there is one, is what the guild spreads: a CR3 to the guild (the beacon and the
    -- gossip carry it from there) and a CR2 of it for old clients. The /gos beacon ad is the fallback.
    local own = self:SeedOwnAd()
    if own then
        local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "A" or "H"
        local cr2 = OwnAdAsCR2(own, guild, faction)
        self:Ingest(cr2, GuildOS.Compat.PlayerName())
        mesh:Guild(self.PREFIX, self:AdToPayload(own))
        mesh:Guild(self.PREFIX, cr2)
        mesh:Realm(self.PREFIX, cr2, self.PREFIX .. ":" .. guild)
        return
    end

    local ad = self:GetAd()
    if not ad or not ad.enabled then return end

    local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "A" or "H"
    local expiry  = now() + (ad.ttlDays or self.DEFAULT_TTL_DAYS) * 86400
    local payload = RecordToPayload({
        guild = guild, faction = faction,
        needsList = ad.needs, days = ad.days, note = ad.note,
        langsList = ad.langs, focusList = ad.focus,
        version = ad.version, expiry = expiry, author = GuildOS.Compat.PlayerName(),
    })

    self:Ingest(payload, GuildOS.Compat.PlayerName())     -- seed our own cache (we relay it too)
    mesh:Guild(self.PREFIX, payload)
    mesh:Realm(self.PREFIX, payload, self.PREFIX .. ":" .. guild)
end

----------------------------------------------------------------------
-- Gossip relay: re-yell a rotating subset of non-expired cached ads. Runs on
-- EVERY client, which is what keeps ads alive with no officer online.
----------------------------------------------------------------------
function RB:RelayTick()
    self:Prune()
    local mesh = _G.ChehulMesh
    if not mesh then return end
    local list = {}
    for _, ad in pairs(self:Cache()) do list[#list + 1] = ad end
    if #list == 0 then return end
    table.sort(list, function(a, b) return a.guild < b.guild end)  -- stable rotation order
    for _ = 1, math.min(self.RELAY_PER_TICK, #list) do
        relayCursor = (relayCursor % #list) + 1
        local ad = list[relayCursor]
        mesh:Realm(self.PREFIX, CacheRecordToPayload(ad), self.PREFIX .. ":" .. ad.guild)
    end
end

----------------------------------------------------------------------
-- Ingest a wire payload into the cache (freshness-checked). Shared by receive
-- and by our own broadcast seeding.
----------------------------------------------------------------------
function RB:Ingest(payload, sender)
    if type(payload) ~= "string" then return end
    local proto, guild, faction, needs, days, note, langs, focus, version, expiry, author = strsplit("|", payload)
    if proto ~= self.PROTO or not guild or guild == "" then return end
    version = tonumber(version) or 0
    expiry  = tonumber(expiry) or 0

    local cache = self:Cache()
    local cur = cache[guild]

    -- Takedown / already-expired: drop any stored copy, don't cache.
    if expiry <= now() then
        if cur and version >= (cur.version or 0) then cache[guild] = nil end
        return
    end

    -- Keep newer content; among equal versions, keep the fresher (higher) expiry.
    if cur and not (version > (cur.version or 0)
                    or (version == (cur.version or 0) and expiry > (cur.expiry or 0))) then
        return
    end

    cache[guild] = {
        guild = guild, faction = faction,
        needs = splitSet(needs), days = days or "", note = note or "",
        langs = splitSet(langs), focus = splitSet(focus),
        version = version, expiry = expiry,
        -- Whisper target = the ad's author (origin officer), carried in the payload
        -- so it survives relays; fall back to a prior value or the direct sender.
        from = (author and author ~= "" and author) or (cur and cur.from) or sender,
    }
    self:Prune()
    if self.onUpdate then pcall(self.onUpdate) end
end

function RB:OnMessage(payload, sender)
    self:Ingest(payload, sender)
end

----------------------------------------------------------------------
-- Received ads for display (freshest first), excluding our own guild.
----------------------------------------------------------------------
function RB:GetInbox()
    self:Prune()
    local myGuild = GetGuildInfo and GetGuildInfo("player")
    local list = {}
    for _, ad in pairs(self:Cache()) do
        if not (myGuild and myGuild == ad.guild) then
            list[#list + 1] = ad
        end
    end
    table.sort(list, function(a, b) return (a.version or 0) > (b.version or 0) end)
    return list
end

-- Does an ad want the local player's class?
function RB:AdMatchesMe(ad)
    if not ad or not ad.needs then return false end
    local _, class = UnitClass("player")
    return class ~= nil and ad.needs[class] == true
end
