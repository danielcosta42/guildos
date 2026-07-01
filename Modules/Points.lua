----------------------------------------------------------------------
-- Guild OS - Points (DKP / EPGP / Loot Council)
--
-- A guild loot-points economy. Mutations are event-sourced: every award
-- or charge is a log entry with a unique opId, applied locally and then
-- published as a SyncService "delta". Receivers apply each opId once
-- (idempotent), so concurrent officers and re-deliveries never
-- double-count. Officers can also push an authoritative "snapshot"
-- (revision-checked) to reconcile newcomers.
--
-- Modes:
--   dkp      - flat points, spent on items
--   epgp     - effort/gear (earned vs spent shown as a ratio)
--   council  - points are informational only (no enforced spend)
----------------------------------------------------------------------
local Points = {}
BRutus.Points = Points
local L = BRutus.L

local LOG_MAX = 500
local OPS_MAX = 2000

----------------------------------------------------------------------
-- Active pool resolver
-- Returns the points DB for the currently active core, or the global
-- db.points when no named core is active (ungrouped raids).
----------------------------------------------------------------------
function Points:GetDB()
    if BRutus.CoreManager then
        return BRutus.CoreManager:GetPointsDB()
    end
    return BRutus.db.points
end

-- Returns the points DB for a specific core (used during sync routing).
function Points:GetDBForCore(coreName)
    if BRutus.CoreManager then
        return BRutus.CoreManager:GetPointsDB(coreName)
    end
    return BRutus.db.points
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function Points:Initialize()
    -- Ensure the global/ungrouped pool is well-formed
    local p = BRutus.db.points or {}
    BRutus.db.points = p
    p.mode = p.mode or "dkp"
    p.config = p.config or {}
    local c = p.config
    if c.bossAward      == nil then c.bossAward      = 10    end
    if c.onTimeAward    == nil then c.onTimeAward     = 0     end
    if c.startingPoints == nil then c.startingPoints  = 0     end
    if c.decayPct       == nil then c.decayPct        = 0     end
    if c.autoAward      == nil then c.autoAward       = false end
    if c.itemCost       == nil then c.itemCost         = 0     end
    p.standings    = p.standings    or {}
    p.log          = p.log          or {}
    p.appliedOps   = p.appliedOps   or {}
    p.appliedCount = p.appliedCount or 0

    if BRutus.SyncService then
        BRutus.SyncService:On("points", function(env, sender) Points:OnSync(env, sender) end)
    end
end

-- Internal helpers — always use the active pool via GetDB()
local function cfg()       return Points:GetDB().config    end
local function standings()  return Points:GetDB().standings end

local function newOp()
    return string.format("%X-%04X", GetServerTime(), math.random(0, 0xFFFF))
end

----------------------------------------------------------------------
-- Accessors
----------------------------------------------------------------------
function Points:GetMode() return self:GetDB().mode end

function Points:SetMode(mode)
    if not BRutus:IsOfficer() then return end
    if mode ~= "dkp" and mode ~= "epgp" and mode ~= "council" then return end
    self:GetDB().mode = mode
    self:BroadcastSnapshot()
    self:Refresh()
end

function Points:Get(key)
    local s = standings()[key]
    return s and s.current or cfg().startingPoints
end

-- Sorted standings list: { { key, name, class, current, earned, spent }, ... }
function Points:GetStandings()
    local list = {}
    for key, s in pairs(standings()) do
        list[#list + 1] = {
            key = key, name = s.name or (key:match("^([^-]+)") or key),
            class = s.class or "", current = s.current or 0,
            earned = s.earned or 0, spent = s.spent or 0,
        }
    end
    table.sort(list, function(a, b)
        if a.current ~= b.current then return a.current > b.current end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

function Points:GetLog(limit)
    local log = self:GetDB().log
    if not limit or limit >= #log then return log end
    local out = {}
    for i = 1, limit do out[i] = log[i] end
    return out
end

----------------------------------------------------------------------
-- Event entries
----------------------------------------------------------------------
function Points:MakeEntry(key, delta, reason, kind)
    local short = key:match("^([^-]+)") or key
    local class = (BRutus.db.members[key] and BRutus.db.members[key].class) or ""
    -- Tag with the active core so receivers can route to the right pool
    local coreName = BRutus.CoreManager and BRutus.CoreManager:GetActiveName() or ""
    return {
        op = newOp(), key = key, name = short, class = class,
        delta = delta, reason = reason or "", kind = kind or "adjust",
        author = UnitName("player"), ts = GetServerTime(),
        core = coreName,
    }
end

-- Apply an entry to a specific pool (nil → active pool).
function Points:ApplyEntry(e, pool)
    if not e or not e.key or not e.delta then return end
    pool = pool or self:GetDB()
    local stnd = pool.standings
    local s = stnd[e.key]
    if not s then
        s = {
            current = (pool.config and pool.config.startingPoints or 0),
            earned = 0, spent = 0, name = e.name, class = e.class,
        }
        stnd[e.key] = s
    end
    if e.name then s.name = e.name end
    if e.class and e.class ~= "" then s.class = e.class end
    s.current = (s.current or 0) + e.delta
    if e.delta >= 0 then
        s.earned = (s.earned or 0) + e.delta
    else
        s.spent = (s.spent or 0) + (-e.delta)
    end
    local log = pool.log
    table.insert(log, 1, {
        ts = e.ts, key = e.key, name = e.name, delta = e.delta,
        reason = e.reason, author = e.author, kind = e.kind,
    })
    while #log > LOG_MAX do table.remove(log) end
end

-- Mark an op as applied in a specific pool (nil → active pool).
function Points:MarkApplied(op, pool)
    if not op then return end
    pool = pool or self:GetDB()
    if not pool.appliedOps[op] then
        pool.appliedOps[op] = true
        pool.appliedCount = (pool.appliedCount or 0) + 1
        if pool.appliedCount > OPS_MAX then
            wipe(pool.appliedOps)
            pool.appliedCount = 0
        end
    end
end

local function publishDelta(entries)
    if BRutus.SyncService then
        BRutus.SyncService:Publish("points", "delta", { entries = entries })
    end
end

----------------------------------------------------------------------
-- Officer mutations
----------------------------------------------------------------------
-- Award (positive) or charge (negative) a single player. reason is free text.
function Points:Adjust(key, amount, reason, kind)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Points are officer-managed.|r"])
        return nil
    end
    if not key or not amount or amount == 0 then return nil end
    local e = self:MakeEntry(key, amount, reason, kind)
    self:ApplyEntry(e)
    self:MarkApplied(e.op)
    publishDelta({ e })
    self:Refresh()
    return e
end

function Points:Award(key, amount, reason) return self:Adjust(key, math.abs(amount), reason, "award") end
function Points:Charge(key, amount, reason) return self:Adjust(key, -math.abs(amount), reason, "spend") end

-- Award the same amount to every player currently in the raid.
function Points:AwardRaidGroup(amount, reason)
    if not BRutus:IsOfficer() then return 0 end
    if not IsInRaid() then
        BRutus:Print(L["You are not in a raid."])
        return 0
    end
    local entries = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = "raid" .. i
        if UnitExists(unit) then
            local nm = UnitName(unit)
            local _, cls = UnitClass(unit)
            local realm = select(2, UnitName(unit))
            realm = (realm and realm ~= "") and realm or GetRealmName()
            local key = BRutus:GetPlayerKey(nm, realm)
            local e = self:MakeEntry(key, math.abs(amount), reason, "raid")
            if cls and cls ~= "" then e.class = cls end
            entries[#entries + 1] = e
        end
    end
    for _, e in ipairs(entries) do self:ApplyEntry(e); self:MarkApplied(e.op) end
    if #entries > 0 then publishDelta(entries) end
    self:Refresh()
    return #entries
end

-- Weekly decay: subtract pct% of every player's current points.
function Points:ApplyDecay(pct)
    if not BRutus:IsOfficer() then return 0 end
    pct = pct or cfg().decayPct or 0
    if pct <= 0 then return 0 end
    local entries = {}
    for key, s in pairs(standings()) do
        local dec = math.floor((s.current or 0) * pct / 100 + 0.5)
        if dec > 0 then
            entries[#entries + 1] = self:MakeEntry(key, -dec, string.format(L["Decay %d%%"], pct), "decay")
        end
    end
    for _, e in ipairs(entries) do self:ApplyEntry(e); self:MarkApplied(e.op) end
    if #entries > 0 then publishDelta(entries) end
    self:Refresh()
    return #entries
end

-- Called by RaidTracker on a successful boss kill (raid-leader gated so
-- exactly one client awards). No-op unless auto-award is enabled.
function Points:OnBossKill(encounterName)
    if not cfg().autoAward then return end
    if not BRutus:IsOfficer() then return end
    if not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return end
    local amount = cfg().bossAward or 0
    if amount <= 0 then return end
    self:AwardRaidGroup(amount, encounterName or L["Boss kill"])
end

----------------------------------------------------------------------
-- Sync (domain "points")
-- Delta entries carry a `core` field so receivers route them to the
-- right pool. Snapshots carry `core` in the payload.
-- Old clients without the `core` field fall back to global db.points.
----------------------------------------------------------------------
function Points:OnSync(env)
    local d = env.data
    if env.act == "delta" and d and d.entries then
        local applied = false
        for _, e in ipairs(d.entries) do
            local pool = self:GetDBForCore(e.core)
            if e.op and not pool.appliedOps[e.op] then
                self:ApplyEntry(e, pool)
                self:MarkApplied(e.op, pool)
                applied = true
            end
        end
        if applied then self:Refresh() end
    elseif env.act == "snapshot" and d then
        local pool = self:GetDBForCore(d.core)
        -- Use a composite revision key so per-core snapshots don't
        -- overwrite each other's revision counter.
        local domain = d.core and ("points:" .. d.core) or "points"
        if BRutus.SyncService:ShouldApply(domain, "standings", env.rev) then
            if d.mode     then pool.mode     = d.mode     end
            if d.config   then pool.config   = d.config   end
            if d.standings then pool.standings = d.standings end
            BRutus.SyncService:SetRevision(domain, "standings", env.rev)
            self:Refresh()
        end
    end
end

-- Officer authoritative snapshot (mode + config + full standings).
-- Broadcasts for the currently active core.
function Points:BroadcastSnapshot()
    if not BRutus:IsOfficer() then return end
    if not BRutus.SyncService then return end
    local coreName = BRutus.CoreManager and BRutus.CoreManager:GetActiveName() or ""
    local pool  = self:GetDB()
    local domain = (coreName ~= "") and ("points:" .. coreName) or "points"
    local rev = BRutus.SyncService:NextRevision(domain, "standings")
    BRutus.SyncService:Publish("points", "snapshot", {
        core     = coreName,
        mode     = pool.mode,
        config   = pool.config,
        standings = pool.standings,
    }, { rev = rev })
end

----------------------------------------------------------------------
-- UI refresh hook (set by the Points window when built).
----------------------------------------------------------------------
function Points:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end
