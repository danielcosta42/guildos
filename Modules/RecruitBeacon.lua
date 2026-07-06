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
----------------------------------------------------------------------
local RB = {}
GuildOS.RecruitBeacon = RB

RB.PREFIX = "ChehulRecruit"
RB.PROTO  = "CR2"

RB.BROADCAST_INTERVAL = 60    -- officer re-broadcast cadence (also refreshes expiry)
RB.RELAY_INTERVAL     = 30    -- everyone: relay a subset of cached ads
RB.RELAY_PER_TICK     = 4     -- cap ads yelled per relay cycle (anti-spam)
RB.CACHE_CAP          = 40    -- max cached ads (evict soonest-to-expire over cap)
RB.DEFAULT_TTL_DAYS   = 7

-- Vocabulary the officer picks from / a recruit filters on.
RB.ROLE_TOKENS  = { "TANK", "HEALER", "DPS" }
RB.CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                    "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
RB.FOCUS_TOKENS = { "RAID", "PVP", "CASUAL", "LEVELING", "SOCIAL", "RP" }
RB.LANG_TOKENS  = { "enUS", "ptBR", "esES", "deDE", "frFR", "ruRU" }

RB.onUpdate = nil        -- UI hook (inbox panel sets it)
local relayCursor = 0

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
    if not BRutus.db then return nil end
    local ad = BRutus.db.recruitBeacon
    if not ad then
        ad = { enabled = false, needs = {}, langs = {}, focus = {},
               days = "", note = "", ttlDays = self.DEFAULT_TTL_DAYS, version = 0 }
        BRutus.db.recruitBeacon = ad
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
    if not BRutus.db then return {} end
    BRutus.db.recruitRelay = BRutus.db.recruitRelay or {}
    return BRutus.db.recruitRelay
end

function RB:Prune()
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
-- Init: register receiver + officer-broadcast + gossip-relay tickers.
----------------------------------------------------------------------
function RB:Initialize()
    self:Prune()
    local mesh = _G.ChehulMesh
    if mesh and not self._registered then
        self._registered = true
        mesh:Register(self.PREFIX, function(payload, sender) RB:OnMessage(payload, sender) end)
    end
    if C_Timer and C_Timer.NewTicker then
        if not self._bcast then
            self._bcast = C_Timer.NewTicker(self.BROADCAST_INTERVAL, function() RB:Broadcast() end)
            if C_Timer.After then C_Timer.After(8, function() RB:Broadcast() end) end
        end
        if not self._relay then
            self._relay = C_Timer.NewTicker(self.RELAY_INTERVAL, function() RB:RelayTick() end)
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
function RB:Broadcast()
    local ad = self:GetAd()
    if not ad or not ad.enabled then return end
    if not (BRutus.IsOfficer and BRutus:IsOfficer()) then return end
    if IsInGuild and not IsInGuild() then return end
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not guild or guild == "" then return end
    local mesh = _G.ChehulMesh
    if not mesh then return end

    local faction = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance") and "A" or "H"
    local expiry  = now() + (ad.ttlDays or self.DEFAULT_TTL_DAYS) * 86400
    local payload = RecordToPayload({
        guild = guild, faction = faction,
        needsList = ad.needs, days = ad.days, note = ad.note,
        langsList = ad.langs, focusList = ad.focus,
        version = ad.version, expiry = expiry, author = UnitName("player"),
    })

    self:Ingest(payload, UnitName("player"))     -- seed our own cache (we relay it too)
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
