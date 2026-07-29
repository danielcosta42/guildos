----------------------------------------------------------------------
-- Guild OS - Alliance data sync
--
-- Moves domain snapshots (roster, and later craft/events/lfg/board) between
-- allied guilds and then INTO the local guild. Two very different hops:
--
--   cross-guild : bridge  <-> bridge, over WHISPER on the ChehulAlly protocol.
--                 Expensive and rate limited, so it is HEAD/PULL/PUSH: a cheap
--                 revision heartbeat, and a transfer only when someone is behind.
--   intra-guild : bridge  ->  everyone, over SyncService on the GUILD channel.
--                 Free and reliable, so a regular member never sends anything
--                 cross-guild; it just receives.
--
-- WHY THE BRIDGE OWNS THE LOCAL SNAPSHOT: any online member may ANSWER a PULL
-- for its own guild (inside the alliance that data is public, and it removes the
-- single point of failure). For that to be consistent, every member must hold an
-- IDENTICAL copy, so the bridge alone builds and revisions our own guild's
-- snapshot and fans it out. Members never build their own.
--
-- DOMAIN CONTRACT: `build` MUST return a deterministically ordered array (sort
-- your keys), because the fingerprint that decides "did anything change" is a
-- hash of the serialized result. An unordered table would churn the revision.
----------------------------------------------------------------------
local AllianceSync = {}
GuildOS.AllianceSync = AllianceSync

local LibSerialize = LibStub("LibSerialize")

AllianceSync.TICK        = 120   -- seconds between bridge heartbeats
AllianceSync.PUSH_WINDOW = 60    -- min seconds between two PUSHes of a domain to one peer
AllianceSync.ROSTER_CAP  = 300   -- imported members per guild

AllianceSync.domains = {}   -- [name] = { build = fn, apply = fn, cap = n, priority = string }

local function normKey(name)
    if not name or name == "" then
        return nil
    end
    local short = name:match("^([^-]+)") or name
    local realm = name:match("-(.+)$") or GetRealmName()
    return BRutus:GetPlayerKey(short, realm)
end

local function Ally()
    return GuildOS.Alliance
end

----------------------------------------------------------------------
-- Pure helpers
----------------------------------------------------------------------

-- Are we behind this peer on a domain?
function AllianceSync.ShouldPull(localRev, remoteRev)
    local r = tonumber(remoteRev)
    if not r then
        return false
    end
    return r > (tonumber(localRev) or 0)
end

-- Simple sliding window. `lastAt` nil means "never sent", which always passes.
function AllianceSync.RateLimitOk(lastAt, now, window)
    if not lastAt then
        return true
    end
    return ((tonumber(now) or 0) - lastAt) >= (tonumber(window) or 0)
end

-- Who may inject an alliance snapshot into our guild over the guild channel.
-- "alliance" is deliberately NOT a SyncService officer domain, because the
-- bridge is usually not an officer, so the trust check lives here instead.
function AllianceSync.TrustedFanout(senderKey, bridgeKey, isOfficer)
    if not senderKey or senderKey == "" then
        return false
    end
    if isOfficer then
        return true
    end
    return senderKey == bridgeKey
end

-- Compact roster rows, deterministically ordered so the fingerprint is stable.
function AllianceSync._BuildRoster(members, cap, altLinks)
    local out = {}
    if type(members) ~= "table" then
        return out
    end
    cap = tonumber(cap) or AllianceSync.ROSTER_CAP
    local keys = {}
    for key in pairs(members) do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if #out >= cap then
            break
        end
        local m = members[key]
        if type(m) == "table" and m.name then
            local profs
            if type(m.professions) == "table" then
                profs = {}
                for _, p in ipairs(m.professions) do
                    if type(p) == "table" and p.name then
                        profs[#profs + 1] = { n = p.name, r = tonumber(p.rank) or 0 }
                    end
                end
            end
            local main = altLinks and altLinks[key]
            out[#out + 1] = {
                n = BRutus:SanitizeUserText(m.name, 24),
                c = m.class,
                l = tonumber(m.level) or 0,
                p = profs,
                m = main and (main:match("^([^-]+)") or main) or nil,
            }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Domain registry
----------------------------------------------------------------------
function AllianceSync:Register(domain, spec)
    if type(domain) ~= "string" or type(spec) ~= "table" then
        return
    end
    if type(spec.build) ~= "function" then
        return
    end
    self.domains[domain] = {
        build    = spec.build,
        apply    = spec.apply,
        cap      = tonumber(spec.cap) or 0,
        priority = spec.priority or "NORMAL",
    }
end

----------------------------------------------------------------------
-- Snapshot store: db.allianceData[guild][domain] = { rev, data, fp, ts }
----------------------------------------------------------------------
function AllianceSync:_Store()
    BRutus.db.allianceData = BRutus.db.allianceData or {}
    return BRutus.db.allianceData
end

function AllianceSync:Remote(guild, domain)
    local store = BRutus.db and BRutus.db.allianceData
    local g = store and store[guild or ""]
    return g and g[domain or ""] or nil
end

function AllianceSync:_Write(guild, domain, rev, data, fp)
    local store = self:_Store()
    store[guild] = store[guild] or {}
    store[guild][domain] = {
        rev  = rev,
        data = data,
        fp   = fp,
        ts   = (GetServerTime and GetServerTime()) or time(),
    }
    self._indexDirty = true
end

-- { [lowercased short name] = allied guild name } across every cached roster.
-- Rebuilt lazily, only after a snapshot actually changed, because the chat
-- filter hits this on every single channel line.
function AllianceSync:MemberIndex()
    if self._index and not self._indexDirty then
        return self._index
    end
    local idx = {}
    local store = (BRutus.db and BRutus.db.allianceData) or {}
    for guild, domains in pairs(store) do
        local roster = domains.roster
        if roster and type(roster.data) == "table" then
            for _, row in ipairs(roster.data) do
                if type(row) == "table" and type(row.n) == "string" and row.n ~= "" then
                    idx[row.n:lower()] = guild
                end
            end
        end
    end
    self._index = idx
    self._indexDirty = false
    return idx
end

-- Refuses anything that is not strictly newer, so a late PUSH can never
-- overwrite fresher data.
-- An UNREGISTERED domain is still stored on purpose: a newer client may ship a
-- domain this one does not implement yet, and dropping it would stall that
-- domain's revision forever. _Apply simply no-ops for it.
function AllianceSync:StoreRemote(guild, domain, rev, data)
    if type(guild) ~= "string" or guild == "" then
        return false
    end
    if type(domain) ~= "string" or domain == "" then
        return false
    end
    if type(data) ~= "table" then
        return false
    end
    local r = tonumber(rev) or 0
    local cur = self:Remote(guild, domain)
    if cur and r <= (cur.rev or 0) then
        return false
    end
    self:_Write(guild, domain, r, data, nil)
    return true
end

----------------------------------------------------------------------
-- Local snapshot: built and revisioned by the BRIDGE only.
----------------------------------------------------------------------
function AllianceSync:Fingerprint(data)
    local ok, ser = pcall(function() return LibSerialize:Serialize(data) end)
    if not ok or type(ser) ~= "string" then
        return nil
    end
    return GuildOS.Alliance.Hash(ser)
end

function AllianceSync:RefreshLocal(domain)
    local spec = self.domains[domain]
    local mine = Ally() and Ally():MyGuildName()
    if not spec or not mine then
        return false
    end
    local ok, data = pcall(spec.build)
    if not ok or type(data) ~= "table" then
        return false
    end
    local fp = self:Fingerprint(data)
    local cur = self:Remote(mine, domain)
    if cur and fp and cur.fp == fp then
        return false   -- nothing changed; do not burn a revision
    end
    local now = (GetServerTime and GetServerTime()) or time()
    local rev = math.max(((cur and cur.rev) or 0) + 1, now)
    self:_Write(mine, domain, rev, data, fp)
    self:Fanout(mine, domain, rev, data)
    return true
end

----------------------------------------------------------------------
-- Intra-guild fanout (free, reliable, guild channel)
----------------------------------------------------------------------
function AllianceSync:Fanout(guild, domain, rev, data)
    if not BRutus.SyncService then
        return
    end
    BRutus.SyncService:Publish("alliance", "snap", {
        guild = guild, domain = domain, rev = rev, data = data,
    }, { priority = (self.domains[domain] and self.domains[domain].priority) or "NORMAL" })
end

function AllianceSync:OnGuildSnapshot(env, sender)
    local ally = Ally()
    if not ally or not ally:Get() then
        return
    end
    local senderKey = normKey(sender)
    if not AllianceSync.TrustedFanout(senderKey, ally:CurrentBridge(), BRutus:IsOfficerByName(sender)) then
        return
    end
    local d = env and env.data
    if type(d) ~= "table" then
        return
    end
    local guild = BRutus:SanitizeUserText(d.guild, GuildOS.Alliance.GUILD_NAME_MAX)
    if guild == "" or ally:IsBlocked(guild) then
        return
    end
    if guild ~= ally:MyGuildName() and not ally:IsMemberGuild(guild) then
        return
    end
    if self:StoreRemote(guild, d.domain, d.rev, d.data) then
        self:_Apply(guild, d.domain)
    end
end

function AllianceSync:_Apply(guild, domain)
    local spec = self.domains[domain]
    if not spec or not spec.apply then
        return
    end
    local entry = self:Remote(guild, domain)
    if entry then
        BRutus:SafeCall(spec.apply, guild, entry.data)
    end
end

----------------------------------------------------------------------
-- Cross-guild ops (whisper, bridge to bridge)
----------------------------------------------------------------------
function AllianceSync:_MyHead()
    local mine = Ally() and Ally():MyGuildName()
    local revs = {}
    if mine then
        for domain in pairs(self.domains) do
            local e = self:Remote(mine, domain)
            revs[domain] = (e and e.rev) or 0
        end
    end
    return { revs = revs }
end

function AllianceSync:OnHead(data, sender, senderGuild)
    if type(data) ~= "table" or type(data.revs) ~= "table" then
        return
    end
    for domain, rev in pairs(data.revs) do
        if type(domain) == "string" and self.domains[domain] then
            local mineOfThem = self:Remote(senderGuild, domain)
            if AllianceSync.ShouldPull(mineOfThem and mineOfThem.rev, rev) then
                Ally():Send("PULL", { domain = domain }, sender)
            end
        end
    end
end

function AllianceSync:OnPull(data, sender, _senderGuild)
    if type(data) ~= "table" then
        return
    end
    local domain = data.domain
    local spec = self.domains[domain or ""]
    local mine = Ally() and Ally():MyGuildName()
    if not spec or not mine then
        return
    end
    local now = (GetServerTime and GetServerTime()) or time()
    self._pushedAt = self._pushedAt or {}
    local slot = sender .. "\t" .. domain
    if not AllianceSync.RateLimitOk(self._pushedAt[slot], now, self.PUSH_WINDOW) then
        return
    end
    local entry = self:Remote(mine, domain)
    if not entry then
        return   -- the bridge has not built it yet; the next HEAD will re-trigger
    end
    self._pushedAt[slot] = now
    Ally():Send("PUSH", { domain = domain, rev = entry.rev, data = entry.data }, sender)
end

function AllianceSync:OnPush(data, _sender, senderGuild)
    if type(data) ~= "table" or type(data.domain) ~= "string" then
        return
    end
    -- The guild is taken from the pact lookup of the ENVELOPE sender, never
    -- from the payload, so a peer can only ever publish for its own guild.
    if self:StoreRemote(senderGuild, data.domain, data.rev, data.data) then
        self:_Apply(senderGuild, data.domain)
        self:Fanout(senderGuild, data.domain, tonumber(data.rev) or 0, data.data)
    end
end

function AllianceSync:Tick()
    local ally = Ally()
    local pact = ally and ally:Get()
    if not pact or not ally:AmBridge() then
        return
    end
    local mine = ally:MyGuildName()
    if not mine then
        return
    end
    for domain in pairs(self.domains) do
        self:RefreshLocal(domain)
    end
    local head = self:_MyHead()
    for guildName in pairs(pact.guilds) do
        if guildName ~= mine and not ally:IsBlocked(guildName) then
            -- Presence evidence only. Never whisper blind on a timer: an offline
            -- target prints a system message in the user's chat frame.
            local target = ally:PeerTarget(guildName)
            if target then
                ally:Send("HEAD", head, target)
            end
        end
    end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function AllianceSync:Initialize()
    self:_Store()
    self:_RegisterTests()

    local ally = Ally()
    if ally then
        ally:RegisterOp("HEAD", function(data, sender, guild) AllianceSync:OnHead(data, sender, guild) end)
        ally:RegisterOp("PULL", function(data, sender, guild) AllianceSync:OnPull(data, sender, guild) end)
        ally:RegisterOp("PUSH", function(data, sender, guild) AllianceSync:OnPush(data, sender, guild) end)
    end

    if BRutus.SyncService then
        BRutus.SyncService:On("alliance", function(env, sender)
            AllianceSync:OnGuildSnapshot(env, sender)
        end)
    end

    self:Register("roster", {
        priority = "NORMAL",
        cap = self.ROSTER_CAP,
        build = function()
            return AllianceSync._BuildRoster(
                BRutus.db.members, AllianceSync.ROSTER_CAP, BRutus.db.altLinks)
        end,
    })

    if BRutus.Compat and BRutus.Compat.NewTicker then
        BRutus.Compat.NewTicker(self.TICK, function() AllianceSync:Tick() end)
    end
end

----------------------------------------------------------------------
-- Self tests (run with /gos selftest)
----------------------------------------------------------------------
function AllianceSync:_RegisterTests()
    if not BRutus.SelfTest then
        return
    end

    BRutus.SelfTest:Register("alliancesync.should_pull", function()
        if not AllianceSync.ShouldPull(1, 2) then return false, "behind must pull" end
        if AllianceSync.ShouldPull(2, 2) then return false, "equal must not pull" end
        if AllianceSync.ShouldPull(3, 2) then return false, "ahead must not pull" end
        if AllianceSync.ShouldPull(nil, 2) ~= true then return false, "nil local counts as zero" end
        if AllianceSync.ShouldPull(1, nil) ~= false then return false, "nil remote must not pull" end
        return true
    end)

    BRutus.SelfTest:Register("alliancesync.rate_limit", function()
        if not AllianceSync.RateLimitOk(nil, 1000, 60) then return false, "first send must pass" end
        if AllianceSync.RateLimitOk(1000, 1030, 60) then return false, "inside the window must fail" end
        if not AllianceSync.RateLimitOk(1000, 1060, 60) then return false, "at the window must pass" end
        if not AllianceSync.RateLimitOk(1000, 9999, 60) then return false, "well past must pass" end
        return true
    end)

    BRutus.SelfTest:Register("alliancesync.trusted_fanout", function()
        if not AllianceSync.TrustedFanout("Ann-R", "Ann-R", false) then return false, "the bridge must be trusted" end
        if not AllianceSync.TrustedFanout("Ann-R", "Bob-R", true) then return false, "an officer must be trusted" end
        if AllianceSync.TrustedFanout("Ann-R", "Bob-R", false) then return false, "a random member must be refused" end
        if AllianceSync.TrustedFanout(nil, "Bob-R", false) then return false, "nil sender must be refused" end
        if AllianceSync.TrustedFanout("Ann-R", nil, false) then return false, "no bridge means no trust" end
        return true
    end)

    BRutus.SelfTest:Register("alliancesync.store_is_monotonic", function()
        local saved = BRutus.db.allianceData
        BRutus.db.allianceData = {}
        AllianceSync:StoreRemote("Guild B", "roster", 10, { a = 1 })
        AllianceSync:StoreRemote("Guild B", "roster", 5, { a = 2 })
        local got = AllianceSync:Remote("Guild B", "roster")
        local fail
        if not got then
            fail = "nothing stored"
        elseif got.rev ~= 10 then
            fail = "an older revision overwrote a newer one"
        elseif got.data.a ~= 1 then
            fail = "stale data applied"
        else
            AllianceSync:StoreRemote("Guild B", "roster", 11, { a = 3 })
            if AllianceSync:Remote("Guild B", "roster").data.a ~= 3 then
                fail = "newer revision rejected"
            end
        end
        BRutus.db.allianceData = saved
        if fail then return false, fail end
        return true
    end)

    BRutus.SelfTest:Register("alliancesync.roster_build", function()
        local src = {}
        for i = 1, 500 do
            src["P" .. i .. "-R"] = { name = "P" .. i, class = "MAGE", level = 70 }
        end
        local out = AllianceSync._BuildRoster(src, 300)
        if #out ~= 300 then return false, "cap not enforced: " .. #out end
        if not out[1].n then return false, "missing name field" end
        if out[1].l ~= 70 then return false, "missing level" end
        -- Deterministic order: the same input must produce the same first row.
        if AllianceSync._BuildRoster(src, 300)[1].n ~= out[1].n then
            return false, "build order is not deterministic"
        end
        if #AllianceSync._BuildRoster(nil, 300) ~= 0 then return false, "nil source must not error" end
        local linked = { ["A-R"] = { name = "A", class = "MAGE", level = 70 } }
        local withMain = AllianceSync._BuildRoster(linked, 10, { ["A-R"] = "Main-R" })
        if withMain[1].m ~= "Main" then return false, "main link not carried" end
        return true
    end)
end
