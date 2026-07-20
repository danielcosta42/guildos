----------------------------------------------------------------------
-- Guild OS - Sync Service (protocol v2)
--
-- A thin, versioned publish/subscribe layer that sits ON TOP of
-- CommSystem's transport (serialize -> compress -> chunk). New
-- shared-state features (points/DKP, calendar events, guild bank,
-- polls, ...) publish through here instead of inventing ad-hoc message
-- strings, so they automatically get:
--   * a versioned envelope (protocol version + addon version)
--   * messageId dedup (drops echoes and re-deliveries)
--   * per-entity revision checks (highest revision wins)
--   * officer-domain write-permission enforcement
--   * optional ACK for critical messages (award/delete) with one retry
--
-- Backward compatible: this is carried as a single new CommSystem wire
-- type ("SV"). Every legacy message type keeps working untouched.
--
-- Addresses ADR-0010 (central type inventory) and ADR-0012 (protocol
-- versioning) for all *new* domains.
----------------------------------------------------------------------
local SyncService = {}
BRutus.SyncService = SyncService

local LibSerialize = LibStub("LibSerialize")

SyncService.PROTOCOL_VERSION = 2
SyncService.ENVELOPE_MSGTYPE = "SV"   -- CommSystem wire tag carrying a v2 envelope

-- Domains whose WRITES require the sender to be a verified guild officer.
-- Reads (snapshots applied locally) are still gated by these because the
-- sender is the writer. Member-level actions inside an officer domain are
-- whitelisted in MEMBER_ACTIONS below.
SyncService.OFFICER_DOMAINS = {
    points   = true,   -- DKP / EPGP / loot council economy
    event    = true,   -- calendar event create/update/delete (rsvp is member-level)
    poll     = true,   -- poll create/close (vote is member-level)
    bulletin = true,   -- officer announcements
    ban      = true,   -- blacklist add/remove (officer-authoritative)
    audit    = true,   -- guild audit trail (officer-authoritative, id-deduped)
}

-- Actions any guild member may perform even inside an officer domain.
SyncService.MEMBER_ACTIONS = {
    rsvp = true,   -- event signup
    vote = true,   -- poll vote
}

SyncService.handlers    = {}   -- [domain] = function(env, sender)
SyncService.seenIds     = {}   -- messageId dedup set
SyncService.seenCount   = 0
SyncService.pendingAcks = {}   -- [id] = { tries, payload, target, priority, dom, act }

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function SyncService:Initialize()
    -- Persistent revision store: db.sync.rev[domain][entityKey] = number
    BRutus.db.sync = BRutus.db.sync or {}
    BRutus.db.sync.rev = BRutus.db.sync.rev or {}
    self.seenIds = {}
    self.seenCount = 0
    self.pendingAcks = {}
end

local function newId()
    return string.format("%04X%04X", math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

----------------------------------------------------------------------
-- Register a domain handler. fn(env, sender) is called for each valid,
-- non-duplicate envelope addressed to `domain`.
----------------------------------------------------------------------
function SyncService:On(domain, fn)
    self.handlers[domain] = fn
end

----------------------------------------------------------------------
-- Publish an envelope to the guild (or a single target).
-- opts (all optional):
--   target     send to a single player (WHISPER) instead of GUILD
--   priority   ChatThrottleLib priority ("BULK"|"NORMAL"|"ALERT")
--   rev        entity revision (receiver applies only if newer)
--   pv         payload schema version (default 1)
--   src        origin tag ("local"|"sync"|"migration"|"import")
--   requireAck request an ACK from `target` (target required); 1 retry
-- Returns the messageId, or nil if it could not be sent.
----------------------------------------------------------------------
function SyncService:Publish(domain, action, data, opts)
    if not IsInGuild() then return nil end
    opts = opts or {}

    local env = {
        v   = self.PROTOCOL_VERSION,
        id  = newId(),
        av  = BRutus.VERSION,
        dom = domain,
        act = action,
        ts  = (GetTime and GetTime()) or 0,
        rev = opts.rev,
        pv  = opts.pv or 1,
        src = opts.src or "local",
        data = data,
    }
    if opts.requireAck and opts.target then
        env.ack = true
    end

    local ok, serialized = pcall(function() return LibSerialize:Serialize(env) end)
    if not ok or type(serialized) ~= "string" then return nil end
    if not BRutus.CommSystem then return nil end

    BRutus.CommSystem:SendMessage(self.ENVELOPE_MSGTYPE, serialized, opts.target, opts.priority)

    if env.ack then
        self.pendingAcks[env.id] = {
            tries = 1, payload = serialized, target = opts.target,
            priority = opts.priority, dom = domain, act = action,
        }
        local id = env.id
        BRutus.Compat.After(10, function() self:RetryAck(id) end)
    end
    return env.id
end

----------------------------------------------------------------------
-- ACK retry: resend the IDENTICAL envelope (same id) so a receiver that
-- already applied it dedups it (no double-apply) but one that missed it
-- gets a second chance. Gives up after one retry.
----------------------------------------------------------------------
function SyncService:RetryAck(id)
    local p = self.pendingAcks[id]
    if not p then return end   -- already acked
    if p.tries >= 2 then
        self.pendingAcks[id] = nil
        BRutus.Logger.Warn(string.format("Sync: no ACK for %s/%s", tostring(p.dom), tostring(p.act)))
        return
    end
    p.tries = p.tries + 1
    BRutus.CommSystem:SendMessage(self.ENVELOPE_MSGTYPE, p.payload, p.target, p.priority)
    BRutus.Compat.After(10, function() self:RetryAck(id) end)
end

local function sendAck(refId, target)
    SyncService:Publish("ack", "ok", { ref = refId }, { target = target })
end

----------------------------------------------------------------------
-- Entry point called by CommSystem when an "SV" wire message arrives.
-- `raw` is the serialized v2 envelope (already de-chunked/decompressed).
----------------------------------------------------------------------
function SyncService:OnEnvelope(sender, raw)
    local ok, env = LibSerialize:Deserialize(raw)
    if not ok or type(env) ~= "table" then return end

    -- ACK frames clear a pending entry and never dispatch.
    if env.dom == "ack" then
        local ref = env.data and env.data.ref
        if ref then self.pendingAcks[ref] = nil end
        return
    end

    if not self:Validate(env, sender) then return end

    -- Duplicate: drop, but honour a re-ack request so a lost ACK recovers.
    if env.id and self:IsDuplicate(env.id) then
        if env.ack then sendAck(env.id, sender) end
        return
    end

    local handler = self.handlers[env.dom]
    if handler then
        BRutus:SafeCall(handler, env, sender)
    end

    if env.ack then sendAck(env.id, sender) end
end

----------------------------------------------------------------------
-- Validation: structure, protocol ceiling, and officer-domain writes.
----------------------------------------------------------------------
function SyncService:Validate(env, sender)
    if type(env) ~= "table" then return false end
    if not env.v or not env.id or not env.dom or not env.act then return false end
    if env.v > self.PROTOCOL_VERSION then return false end   -- newer protocol than we speak
    if self.OFFICER_DOMAINS[env.dom] and not self.MEMBER_ACTIONS[env.act] then
        if not BRutus:IsOfficerByName(sender) then return false end
    end
    return true
end

----------------------------------------------------------------------
-- Dedup: circular set of the last ~500 messageIds.
----------------------------------------------------------------------
function SyncService:IsDuplicate(id)
    if self.seenIds[id] then return true end
    self.seenIds[id] = true
    self.seenCount = self.seenCount + 1
    if self.seenCount > 500 then
        wipe(self.seenIds)
        self.seenCount = 0
    end
    return false
end

----------------------------------------------------------------------
-- Revision helpers (highest revision wins per entity, per domain).
----------------------------------------------------------------------
function SyncService:GetRevision(domain, key)
    local rev = BRutus.db.sync and BRutus.db.sync.rev and BRutus.db.sync.rev[domain]
    return (rev and rev[key]) or 0
end

-- True if an incoming revision should be applied. Unversioned (nil) always applies.
function SyncService:ShouldApply(domain, key, rev)
    if not rev then return true end
    return rev > self:GetRevision(domain, key)
end

-- Record a revision we have applied (only ever increases).
function SyncService:SetRevision(domain, key, rev)
    if not rev then return end
    BRutus.db.sync = BRutus.db.sync or {}
    BRutus.db.sync.rev = BRutus.db.sync.rev or {}
    BRutus.db.sync.rev[domain] = BRutus.db.sync.rev[domain] or {}
    local cur = BRutus.db.sync.rev[domain][key] or 0
    if rev > cur then BRutus.db.sync.rev[domain][key] = rev end
end

-- Allocate the next revision for an entity we are about to write+publish.
function SyncService:NextRevision(domain, key)
    BRutus.db.sync = BRutus.db.sync or {}
    BRutus.db.sync.rev = BRutus.db.sync.rev or {}
    BRutus.db.sync.rev[domain] = BRutus.db.sync.rev[domain] or {}
    local nxt = (BRutus.db.sync.rev[domain][key] or 0) + 1
    BRutus.db.sync.rev[domain][key] = nxt
    return nxt
end
