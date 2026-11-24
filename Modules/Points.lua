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
--
-- The accounts of the loot rule (issues #309, #319), every one off until the guild sets it:
--   * a cap (earnings above it do not add, and the history says so);
--   * reasons to earn beyond the boss: on time or late, stayed or left early, the whole raid, and the
--     guild's own named reasons (a donation, consumables handed in), each with its weekly cap;
--   * decay rounded up, down or to the nearest;
--   * a price to enter a roll, part of it given back to whoever loses;
--   * EPGP: EP is what was earned, GP what was spent, priority is EP / (GP + base GP), an item's GP
--     comes from its slot and item level or from the guild's own table, and decay takes both.
--
-- Counter accounts (issue #334): a second kind of account beside the points, a small whole number per
-- character that an award adds to and that goes back to nothing each raid night, each lockout or
-- never (the "+1" of MS > OS +1). They live in the pool, travel in the same op log under their own
-- action ("cdelta": a client from before reads no counter as points) and in the snapshot.
--
-- Since issue #337 the rare accounts too:
--   * a bonus account is a counter whose figure is added to a roll, and may have a cap (karma, SR+);
--   * a queue account is an ordered list of players (Suicide Kings). Its whole order travels in the same
--     op log under its own action ("qset") with a sequence number, so the newest order wins on every
--     client in whatever order the entries reach it, and in the snapshot;
--   * what was charged for an item can be shared among the raid (zero-sum DKP), each share an entry.
--
-- On retail too since issue #185: boss-kill EP, awards, decay and standings as anywhere else. With no
-- Master Loot there, an item is charged when an award by trade is recorded (TradeCouncil).
----------------------------------------------------------------------

local Points = {}
GuildOS.Points = Points
local L = GuildOS.L

local LOG_MAX = 500
local OPS_MAX = 2000
local WEEK = 604800               -- seconds: a reason's weekly cap counts within one of these
local MAX_REASONS = 12            -- named reasons a pool keeps
local EARN_KINDS = { award = true, raid = true, reason = true }   -- what the caps hold back

-- An item's GP by where it is worn, against the price of a chest piece (the EPGP addons' own table).
local SLOT_GP = {
    INVTYPE_HEAD = 1, INVTYPE_CHEST = 1, INVTYPE_ROBE = 1, INVTYPE_LEGS = 1, INVTYPE_2HWEAPON = 2,
    INVTYPE_SHOULDER = 0.75, INVTYPE_HAND = 0.75, INVTYPE_WAIST = 0.75, INVTYPE_FEET = 0.75,
    INVTYPE_TRINKET = 0.75,
    INVTYPE_WRIST = 0.5, INVTYPE_NECK = 0.5, INVTYPE_CLOAK = 0.5, INVTYPE_FINGER = 0.5,
    INVTYPE_HOLDABLE = 0.5, INVTYPE_SHIELD = 0.5, INVTYPE_RANGED = 0.5, INVTYPE_RANGEDRIGHT = 0.5,
    INVTYPE_THROWN = 0.5, INVTYPE_RELIC = 0.5,
    INVTYPE_WEAPON = 1.5, INVTYPE_WEAPONMAINHAND = 1.5, INVTYPE_WEAPONOFFHAND = 0.5,
}
local GP_ILVL_STEP = 26           -- item levels in which an item's GP doubles
local NIGHT = 43200               -- seconds: two counter entries closer than this are the same raid night
local COUNTER_MAX = 100           -- the most one entry moves a counter by
local COUNTER_RESETS = { never = true, night = true, lockout = true }
local QUEUE_MAX = 200             -- players one queue holds
local QUEUE_KEY_MAX = 64          -- bytes of a player's key in a queue

----------------------------------------------------------------------
-- Active pool resolver
-- Returns the points DB for the currently active core, or the global
-- db.points when no named core is active (ungrouped raids).
----------------------------------------------------------------------
-- A group whose points go to its elenco's pool (issue #352, CoreManager:PoolOwner) reads and writes the
-- elenco's: its own name never names a pool then, here or in what is told to the other officers.
local function ownerOf(name)
    local CM = GuildOS.CoreManager
    if CM and CM.PoolOwner and type(name) == "string" and name ~= "" then return CM:PoolOwner(name) end
    return name
end

-- nil while `InCore` names a core this client does not have (CoreManager:GetPointsDB): no pool, and
-- every caller that charges or gives checks it (LootMaster's `pointsReady`).
function Points:GetDB()
    local CM = GuildOS.CoreManager
    if CM then
        local scope = self.scope
        if scope == nil and CM.PoolOwner then
            local active = CM:GetActiveName()
            local owner = ownerOf(active)
            if owner ~= active then scope = owner end
        end
        return CM:GetPointsDB(scope)
    end
    return GuildOS.db.points
end

-- An empty pool that is no one's, for this module's own reads and writes while there is none: what is
-- written there goes nowhere, and nothing of it is told to the other officers (canTell).
local function nowhere()
    return { nowhere = true, mode = "dkp", config = {}, standings = {}, log = {}, appliedOps = {}, appliedCount = 0 }
end
function Points:Pool()
    return self:GetDB() or nowhere()
end

-- The core whose pool is being read and written: the raid's active one, or the one `InCore` names.
-- A raid tag no core has here (a linked guild makes none, #339) is a raid outside a core: "", the
-- guild's pool, which is the one GetDB reads for it, as 1.24.0 did: points, counters, queues and
-- charges made here all go there, tagged "", and the officer is told so (TellMissingCore).
function Points:ActiveCore()
    if self.scope ~= nil then return self.scope end
    local CM = GuildOS.CoreManager
    local name = CM and CM:GetActiveName() or ""
    if name ~= "" and not CM:GetCore(name) then
        self:TellMissingCore(name)
        return ""
    end
    return ownerOf(name)
end

-- Says to an officer, once a raid night (the raid tracker's session; once a login outside one), that
-- the raid's core `name` is not on this client yet, so what it gives tonight goes to the guild's pool.
local missingTold = {}
function Points:TellMissingCore(name)
    if not (GuildOS.IsOfficer and GuildOS:IsOfficer()) then return end
    local RT = GuildOS.RaidTracker
    local night = RT and type(RT.currentRaid) == "table" and RT.currentRaid.startTime or 0
    local key = tostring(name) .. "\0" .. tostring(night)
    if missingTold[key] then return end
    missingTold[key] = true
    GuildOS:Print(string.format(L["This client does not have the core %s yet: tonight's points go to the guild's pool."], tostring(name)))
end

-- Runs `fn(...)` with the pool of the core `coreName` ("" is the guild's own) as the one every read,
-- charge, counter and queue of this module works on, whatever core is the raid's by then; entries are
-- tagged with it, so the other officers' clients route them to the same pool. An item is announced
-- under one core and is given, paid for and undone in that core's accounts (LootMaster, issue #338).
-- nil runs `fn` on the active core, as everything outside a roll does.
local function inScope(self, scope, fn, ...)
    local was = self.scope
    self.scope = scope
    local ok, a, b, c = pcall(fn, ...)
    self.scope = was
    if not ok then error(a, 0) end
    return a, b, c
end
function Points:InCore(coreName, fn, ...)
    if coreName == nil then return fn(...) end
    return inScope(self, ownerOf(coreName), fn, ...)
end

-- The pool the core `coreName`'s points are in now (a group with the elenco's pool: the elenco's, #352),
-- to be kept with what was given in it; and `fn(...)` run on a pool kept so (`poolName`, never resolved
-- again), so an undo gives back where the award took from, whatever the group's pool setting is by then.
function Points:PoolOf(coreName) return ownerOf(coreName) end
function Points:InPool(poolName, fn, ...)
    if poolName == nil then return fn(...) end
    return inScope(self, poolName, fn, ...)
end

-- Returns the points DB for a specific core (used during sync routing).
-- nil for a core this client does not have: the sync skips those entries, unapplied, until it arrives.
function Points:GetDBForCore(coreName)
    if GuildOS.CoreManager then
        return GuildOS.CoreManager:GetPointsDB(ownerOf(coreName))
    end
    return GuildOS.db.points
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function Points:Initialize()
    -- Ensure the global/ungrouped pool is well-formed
    local p = GuildOS.db.points or {}
    GuildOS.db.points = p
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

    if GuildOS.SyncService then
        GuildOS.SyncService:On("points", function(env, sender) Points:OnSync(env, sender) end)
    end
    -- What was kept for a core that this client has by now (CoreManager initializes first).
    self:ReplayAllWaiting()
end

-- Internal helpers — always use the active pool via GetDB()
local function cfg()       return Points:Pool().config    end
local function standings()  return Points:Pool().standings end

-- An entry's own name: the second, sixteen random bits, then who made it (a short hash of the
-- author's name) and a count that only grows while this client runs. The first two alone, as every
-- entry was named before, met too often: a share to each of forty raiders is forty entries in one
-- second, one batch in ninety carried two with one name, and every other officer's client dropped the
-- second as already applied. Old names are still names: nothing reads inside one.
local opSeq = 0
local function authorId()
    local name = GuildOS.Compat.PlayerName() or ""
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 0x10000 end
    return h
end
local function newOp()
    opSeq = opSeq + 1
    return string.format("%X-%04X.%04X.%X", GetServerTime(), math.random(0, 0xFFFF), authorId(), opSeq)
end

----------------------------------------------------------------------
-- Accessors
----------------------------------------------------------------------
-- The pool `coreName` names: nil is the active core's, "" the guild's own.
local function poolOf(coreName)
    if coreName == nil then return Points:Pool() end
    return Points:GetDBForCore(coreName) or nowhere()
end

-- Whether what this module just wrote may be told to the other officers: never an entry for a core
-- this client has no pool for (written nowhere here, it would be applied elsewhere alone).
local function canTell()
    return GuildOS.SyncService ~= nil and Points:GetDB() ~= nil
end

-- `coreName` (issue #338): another core's pool than the active one's, when a core picks its own loot
-- system.
function Points:GetMode(coreName) return poolOf(coreName).mode end

function Points:SetMode(mode, coreName)
    if not GuildOS:IsOfficer() then return end
    if mode ~= "dkp" and mode ~= "epgp" and mode ~= "council" then return end
    poolOf(coreName).mode = mode
    self:BroadcastSnapshot(coreName)
    self:Refresh()
end

-- The key a name typed in the points window means. On retail a guildmate on a connected realm is typed
-- with their realm ("Ana-Gallywix"), and a name without one is this realm's (issue #185); elsewhere the
-- name on this client's realm, as always.
function Points:KeyOf(name)
    if GuildOS.Client.isRetail then return GuildOS:KeyOfRosterName(name) end
    return GuildOS:GetPlayerKey(name, GetRealmName())
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
    -- EPGP reads the list by priority (issue #319).
    local epgp = self:GetMode() == "epgp"
    if epgp then
        for _, row in ipairs(list) do row.pr = self:PR(row.key) end
    end
    table.sort(list, function(a, b)
        if epgp and a.pr ~= b.pr then return a.pr > b.pr end
        if a.current ~= b.current then return a.current > b.current end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

function Points:GetLog(limit)
    local log = self:Pool().log
    if not limit or limit >= #log then return log end
    local out = {}
    for i = 1, limit do out[i] = log[i] end
    return out
end

----------------------------------------------------------------------
-- Event entries
----------------------------------------------------------------------
function Points:MakeEntry(key, delta, reason, kind)
    -- Retail names a guildmate with their realm, as its loot history does: two namesakes on connected
    -- realms are two standings (ADR-0026). Elsewhere the name alone, as always.
    local short = GuildOS.Client.isRetail and key or (key:match("^([^-]+)") or key)
    local class = (GuildOS.db.members[key] and GuildOS.db.members[key].class) or ""
    -- Tag with the active core so receivers can route to the right pool
    local coreName = self:ActiveCore()
    return {
        op = newOp(), key = key, name = short, class = class,
        delta = delta, reason = reason or "", kind = kind or "adjust",
        author = GuildOS.Compat.PlayerName(), ts = GetServerTime(),
        core = coreName,
    }
end

-- Apply an entry to a specific pool (nil → active pool).
function Points:ApplyEntry(e, pool)
    if not e or not e.key or not e.delta then return end
    pool = pool or self:Pool()
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
    -- EPGP names the side an entry moves (issue #319): decay takes from what was earned (EP) and from
    -- what was spent (GP), which no sign alone can say.
    if e.acct == "ep" then
        s.earned = math.max(0, (s.earned or 0) + e.delta)
    elseif e.acct == "gp" then
        s.spent = math.max(0, (s.spent or 0) - e.delta)
    elseif e.delta >= 0 then
        s.earned = (s.earned or 0) + e.delta
    else
        s.spent = (s.spent or 0) + (-e.delta)
    end
    -- What a reason has given this week, for its weekly cap (issue #309).
    if e.rk and e.delta > 0 then
        local week, now = self:Week(e.ts), self:Week()
        pool.weekly = pool.weekly or {}
        -- This week's and last week's are kept, counted from today and not from the entry: an entry
        -- dated weeks ago, arriving late from another officer, used to wipe this week's count and the
        -- cap paid again. Anything else (a week counted another way before among it) goes.
        for w in pairs(pool.weekly) do
            if w ~= now and w ~= now - 1 then pool.weekly[w] = nil end
        end
        if week == now or week == now - 1 then
            local t = pool.weekly[week] or {}
            pool.weekly[week] = t
            local wk = e.key .. "|" .. e.rk
            t[wk] = (t[wk] or 0) + e.delta
        end
    end
    local log = pool.log
    table.insert(log, 1, {
        ts = e.ts, key = e.key, name = e.name, delta = e.delta,
        reason = e.reason, author = e.author, kind = e.kind, rk = e.rk,
    })
    while #log > LOG_MAX do table.remove(log) end
end

-- Mark an op as applied in a specific pool (nil → active pool).
function Points:MarkApplied(op, pool)
    if not op then return end
    pool = pool or self:Pool()
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
    if canTell() then
        GuildOS.SyncService:Publish("points", "delta", { entries = entries })
    end
end

----------------------------------------------------------------------
-- Officer mutations
----------------------------------------------------------------------
----------------------------------------------------------------------
-- The caps (issue #309): how much of an earning still fits.
----------------------------------------------------------------------
-- The guild's named reasons to earn: { { key, name, value, weekly }, ... } (weekly 0 or nil: no cap).
function Points:GetReasons(pool)
    local c = (pool or self:Pool()).config
    return (c and type(c.reasons) == "table") and c.reasons or {}
end

function Points:GetReason(rk, pool)
    for _, r in ipairs(self:GetReasons(pool)) do
        if r.key == rk then return r end
    end
    return nil
end

-- Add, change (same key) or, with no value, remove a named reason. Officer only.
function Points:SetReason(rk, name, value, weekly)
    if not GuildOS:IsOfficer() then return false end
    rk = tostring(rk or ""):lower():gsub("[^a-z0-9]", ""):sub(1, 8)
    if rk == "" then return false end
    local c = self:Pool().config
    local list = {}
    for _, r in ipairs(self:GetReasons()) do
        if r.key ~= rk then list[#list + 1] = r end
    end
    value = tonumber(value)
    if value and value > 0 then
        if #list >= MAX_REASONS then return false end
        list[#list + 1] = {
            key = rk, name = strtrim(tostring(name or rk)):sub(1, 40), value = math.floor(value),
            weekly = math.max(0, math.floor(tonumber(weekly) or 0)),
        }
    end
    c.reasons = list
    self:BroadcastSnapshot()
    self:Refresh()
    return true
end

-- The week a reason's cap counts in: the game's own, from one weekly reset of the region to the next
-- (RaidTracker:GetWeekNum, the lockout week). It used to be a week of the calendar from Thursday 00:00
-- UTC, in the middle of the raid week: the cap paid on Wednesday night and again on Thursday morning.
function Points:Week(ts)
    ts = tonumber(ts) or GetServerTime()
    local RT = GuildOS.RaidTracker
    if RT and RT.GetWeekNum then return RT:GetWeekNum(ts) end
    return math.floor(ts / WEEK)
end

-- What `rk` has given `key` in the week of `ts`.
function Points:WeeklyEarned(key, rk, ts, pool)
    pool = pool or self:Pool()
    local t = pool.weekly and pool.weekly[self:Week(ts)]
    return (t and t[key .. "|" .. rk]) or 0
end

-- This week's figures of a snapshot into this client's: the higher of each. An officer who missed the
-- entries of a named reason, and only got the snapshot, used to pay its weekly cap again.
function Points:MergeWeekly(pool, weekly)
    if type(weekly) ~= "table" or type(weekly.v) ~= "table" then return end
    local week = self:Week()
    if weekly.w ~= week then return end
    pool.weekly = pool.weekly or {}
    local t = pool.weekly[week] or {}
    pool.weekly[week] = t
    for wk, n in pairs(weekly.v) do
        if type(wk) == "string" and #wk <= 160 and type(n) == "number" and n > 0 and n < math.huge then
            local key, rk = wk:match("^(.+)|([a-z0-9]+)$")
            if key then
                wk = GuildOS:LocalMemberKey(key) .. "|" .. rk
                t[wk] = math.max(t[wk] or 0, math.floor(n))
            end
        end
    end
end

-- How much of `amount` `key` may still earn, and what held the rest back ("weekly", "cap" or nil).
-- EPGP has no cap: EP only matters against GP.
function Points:Room(key, amount, rk, pool)
    pool = pool or self:Pool()
    local c, why = pool.config or {}, nil
    local reason = rk and self:GetReason(rk, pool)
    if reason and (reason.weekly or 0) > 0 then
        local left = math.max(0, reason.weekly - self:WeeklyEarned(key, rk, nil, pool))
        if left < amount then amount, why = left, "weekly" end
    end
    local cap = tonumber(c.cap) or 0
    if cap > 0 and pool.mode ~= "epgp" then
        local s = pool.standings[key]
        local left = math.max(0, cap - (s and s.current or c.startingPoints or 0))
        if left < amount then amount, why = left, "cap" end
    end
    return amount, why
end

-- An earning as an entry, held to the caps. What did not fit is said in the entry's reason, and an
-- earning that fits nowhere still leaves its line in the history, with nothing added.
function Points:EarnEntry(key, amount, reason, kind, rk)
    local fits, why = self:Room(key, amount, rk)
    reason = reason or ""
    if why == "cap" then
        reason = string.format(L["%s (cap reached: %d of %d)"], reason, fits, amount)
    elseif why == "weekly" then
        reason = string.format(L["%s (weekly cap reached: %d of %d)"], reason, fits, amount)
    end
    local e = self:MakeEntry(key, fits, reason, kind)
    e.rk = rk
    if self:GetMode() == "epgp" then e.acct = "ep" end
    return e
end

-- Award (positive) or charge (negative) a single player. reason is free text. An award is held to the
-- caps; a refund or an undo (any other kind) is not.
function Points:Adjust(key, amount, reason, kind, rk)
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Points are officer-managed.|r"])
        return nil
    end
    if not key or not amount or amount == 0 then return nil end
    local e
    if amount > 0 and EARN_KINDS[kind or ""] then
        e = self:EarnEntry(key, amount, reason, kind, rk)
    else
        e = self:MakeEntry(key, amount, reason, kind)
        if self:GetMode() == "epgp" then e.acct = amount < 0 and "gp" or (kind == "undo" and "gp" or "ep") end
    end
    self:ApplyEntry(e)
    self:MarkApplied(e.op)
    publishDelta({ e })
    self:Refresh()
    return e
end

function Points:Award(key, amount, reason) return self:Adjust(key, math.abs(amount), reason, "award") end
function Points:Charge(key, amount, reason) return self:Adjust(key, -math.abs(amount), reason, "spend") end
-- Give back what a charge took: never held to a cap, and in EPGP it comes off the GP.
function Points:Refund(key, amount, reason) return self:Adjust(key, math.abs(amount), reason, "undo") end

-- One of the guild's named reasons, `times` over (a stack donated, a dungeon run), up to its weekly cap.
function Points:AwardReason(key, rk, times)
    local r = self:GetReason(rk)
    if not r then return nil end
    times = math.max(1, math.floor(tonumber(times) or 1))
    return self:Adjust(key, r.value * times, r.name, "reason", rk)
end

-- The award row of the Loot window's Accounts tab (issue #346): who, a named reason or a typed one,
-- how many times or how many points, and whether it is an award or a charge. A named reason given is
-- its points `times` over, held to its weekly cap; charged, it takes its points `times` over. A typed
-- reason moves `amount` points. Returns the entry, or nil and why ("name", "amount", "reason").
function Points:AwardRow(spec)
    spec = spec or {}
    local name = strtrim(tostring(spec.name or ""))
    if name == "" then return nil, "name" end
    local key = self:KeyOf(name)
    local times = math.max(1, math.floor(tonumber(spec.times) or 1))
    if spec.reason then
        local r = self:GetReason(spec.reason)
        if not r then return nil, "reason" end
        if spec.charge then return self:Charge(key, r.value * times, r.name) end
        return self:AwardReason(key, r.key, times)
    end
    local amount = math.abs(math.floor(tonumber(spec.amount) or 0))
    if amount == 0 then return nil, "amount" end
    local note = strtrim(tostring(spec.note or ""))
    return self:Adjust(key, spec.charge and -amount or amount, note, spec.charge and "spend" or "award")
end

-- One of the points' settings of a core's pool ("" the guild's), from the Accounts tab (issue #346):
-- the figures are whole and not below zero (the percentages not above a hundred), the switches yes or
-- no, the decay's rounding one of three. The pool's officers hear it. Returns the value kept, or nil.
local CONFIG_NUMBERS = {
    bossAward = true, raidAward = true, onTimeAward = true, lateAward = true, stayedAward = true,
    leftEarlyAward = true, startingPoints = true, cap = true, itemCost = true, entryCost = true,
    gpRefIlvl = true, baseGP = true, minEP = true,
}
local CONFIG_PERCENTS = { decayPct = true, refundPct = true }
local CONFIG_SWITCHES = { autoAward = true, raidEndAwards = true }
local DECAY_ROUNDS = { near = true, up = true, down = true }
function Points:SetConfigKey(key, value, coreName)
    if not GuildOS:IsOfficer() then return nil end
    if CONFIG_NUMBERS[key] or CONFIG_PERCENTS[key] then
        value = math.floor(tonumber(value) or 0)
        if value < 0 then value = 0 end
        if CONFIG_PERCENTS[key] and value > 100 then value = 100 end
    elseif CONFIG_SWITCHES[key] then
        value = value and true or false
    elseif key == "decayRound" then
        if not DECAY_ROUNDS[value] then return nil end
    else
        return nil
    end
    local pool = poolOf(coreName)
    pool.config = pool.config or {}
    pool.config[key] = value
    self:BroadcastSnapshot(coreName)
    self:Refresh()
    return value
end

-- Award the same amount to every player currently in the raid.
function Points:AwardRaidGroup(amount, reason)
    if not GuildOS:IsOfficer() then return 0 end
    if not IsInRaid() then
        GuildOS:Print(L["You are not in a raid."])
        return 0
    end
    local entries = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = "raid" .. i
        local nm, realm, cls
        if UnitExists(unit) then nm, realm, cls = GuildOS.Compat.UnitIdentity(unit) end
        if nm then
            realm = (realm and realm ~= "") and realm or GetRealmName()
            local key = GuildOS:GetPlayerKey(nm, realm)
            local e = self:EarnEntry(key, math.abs(amount), reason, "raid")
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
    if not GuildOS:IsOfficer() then return 0 end
    pct = pct or cfg().decayPct or 0
    if pct <= 0 then return 0 end
    -- Rounded the way the guild says (issue #309): to the nearest as always, up or down.
    local how = cfg().decayRound
    local function part(n)
        local x = math.max(0, n or 0) * pct / 100
        if how == "up" then return math.ceil(x) end
        if how == "down" then return math.floor(x) end
        return math.floor(x + 0.5)
    end
    local entries, epgp = {}, self:GetMode() == "epgp"
    local label = string.format(L["Decay %d%%"], pct)
    for key, s in pairs(standings()) do
        if epgp then
            -- Both sides decay (issue #319): EP down, and GP down, which gives priority back.
            local ep, gp = part(s.earned), part(s.spent)
            if ep > 0 then
                local e = self:MakeEntry(key, -ep, label .. " (EP)", "decay"); e.acct = "ep"
                entries[#entries + 1] = e
            end
            if gp > 0 then
                local e = self:MakeEntry(key, gp, label .. " (GP)", "decay"); e.acct = "gp"
                entries[#entries + 1] = e
            end
        else
            local dec = part(s.current)
            if dec > 0 then entries[#entries + 1] = self:MakeEntry(key, -dec, label, "decay") end
        end
    end
    for _, e in ipairs(entries) do self:ApplyEntry(e); self:MarkApplied(e.op) end
    if #entries > 0 then publishDelta(entries) end
    -- A client from before EPGP's two sides reads a decay as plain points: the snapshot sets it right.
    if epgp and #entries > 0 then self:BroadcastSnapshot() end
    self:Refresh()
    return #entries
end

-- Called by RaidTracker on a successful boss kill (raid-leader gated so
-- exactly one client awards). No-op unless auto-award is enabled.
function Points:OnBossKill(encounterName)
    -- The counters the loot rule feeds per boss, whatever the points' own switch says.
    if UnitIsGroupLeader and UnitIsGroupLeader("player") and IsInRaid() then
        local keys = {}
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local nm, realm
            if UnitExists(unit) then nm, realm = GuildOS.Compat.UnitIdentity(unit) end
            if nm then keys[#keys + 1] = GuildOS:GetPlayerKey(nm, (realm and realm ~= "") and realm or GetRealmName()) end
        end
        self:EarnCounters("boss", keys)
    end
    -- A pool not set up yet (the module switched off in Settings, so never initialized) awards nothing.
    local pool = self:Pool()
    if not (pool and pool.config and pool.config.autoAward) then return end
    if not GuildOS:IsOfficer() then return end
    if not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return end
    local amount = cfg().bossAward or 0
    if amount <= 0 then return end
    self:AwardRaidGroup(amount, encounterName or L["Boss kill"])
end

-- The raid night a session belongs to, the same on every client that was in the raid: the instance (on
-- retail its difficulty too), the lockout week and the day of the week the raid began, counted from the
-- region's reset hour, which is no raid's hour. A session's own start is each client's zone-in time: two
-- officers who walked in half a minute apart held two "sessions", and each paid the raid's end.
function Points:RaidNight(session)
    local RT = GuildOS.RaidTracker
    local start = tonumber(session.startTime) or 0
    local origin = (RT and RT.ResetOrigin and RT:ResetOrigin()) or 0
    local day = math.floor((start - origin) / 86400)
    local week = (RT and RT.GetWeekNum) and RT:GetWeekNum(start) or math.floor(day / 7)
    local night = string.format("%d.%d.%d", tonumber(session.instanceID) or 0, week, day - week * 7)
    local difficulty = tonumber(session.difficulty)
    return difficulty and (night .. "d" .. difficulty) or night
end

-- The one client that pays a raid's end, by the key of its player: the raid's leader as the session
-- last saw one (RaidTracker keeps it; by the time a session closes the raid is often disbanded), as a
-- boss kill is paid by the leader's client. When the leader is no officer, or the session never saw one,
-- the officer the session saw whose key sorts first: every client works out the same one. An officer
-- chosen this way who does not run GuildOS pays nothing, and the awards are then an officer's to give
-- by hand; paying from two clients is the worse mistake.
function Points:RaidEndPayer(session, everyone)
    local leader = session.leader
    if type(leader) == "string" and GuildOS:IsOfficerByName(leader) then return leader end
    local first
    for _, key in ipairs(everyone) do
        if (not first or key < first) and GuildOS:IsOfficerByName(key) then first = key end
    end
    return first
end

-- Called by RaidTracker when a guild raid's session is saved (issue #309): on time or late, stayed or
-- left early, and the raid itself, for everyone the session saw. One client pays (RaidEndPayer), and
-- each award's op is the raid night's own (RaidNight), so a second client that ends the same raid, or
-- the same client ending it again after a /reload, gives nothing twice.
-- Everyone a session's snapshots saw, by key: as a set and as a list.
local function sessionKeys(session)
    local seen, everyone = {}, {}
    for _, snap in ipairs(type(session) == "table" and session.snapshots or {}) do
        for key in pairs(type(snap) == "table" and snap.members or {}) do
            if not seen[key] then seen[key] = true; everyone[#everyone + 1] = key end
        end
    end
    return seen, everyone
end

function Points:OnRaidEnd(session)
    local pool = self:Pool()
    if not GuildOS:IsOfficer() or type(session) ~= "table" then return 0 end
    local snaps = session.snapshots or {}
    local first, last = snaps[1], snaps[#snaps]
    if not (first and first.members) then return 0 end
    local seen, everyone = sessionKeys(session)
    if self:RaidEndPayer(session, everyone) ~= GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) then return 0 end
    local night = self:RaidNight(session)
    -- The counters the loot rule feeds per raid attended, whatever the points' own switch says; the
    -- raid night names each entry.
    self:EarnCounters("raid", everyone, night)
    -- And a bonus kept per item (SR+ by item, issue #433), by what each of them reserved tonight.
    self:EarnItemBonuses(session, everyone, night)
    -- Only once an officer has switched them on (`raidEndAwards`, off until then). `onTimeAward` sat in
    -- the settings for years with nothing reading it: a guild that typed a figure there long ago, and
    -- has the boss auto-award on, would have started paying it at every raid's end without being asked.
    if not (pool and pool.config and pool.config.raidEndAwards == true) then return 0 end
    local c = pool.config
    local entries = {}
    -- `tag` is what the award is of: arriving (on time or late) and leaving (to the end or early) are
    -- one award each, whichever of the two a client saw.
    local function give(key, amount, label, tag)
        amount = tonumber(amount) or 0
        if amount <= 0 then return end
        local op = string.format("S%s-%s-%s", night, tag, key)
        if pool.appliedOps[op] then return end
        local e = self:EarnEntry(key, amount, label, "raid")
        e.op, e.ts = op, session.endTime or e.ts
        self:ApplyEntry(e); self:MarkApplied(e.op)
        entries[#entries + 1] = e
    end
    for key in pairs(seen) do
        if first.members[key] then give(key, c.onTimeAward, L["On time"], "in")
        else give(key, c.lateAward, L["Late"], "in") end
        if last.members[key] then give(key, c.stayedAward, L["Stayed until the end"], "out")
        else give(key, c.leftEarlyAward, L["Left early"], "out") end
        give(key, c.raidAward, L["Raid attended"], "rd")
    end
    if #entries > 0 then publishDelta(entries) end
    self:Refresh()
    return #entries
end

----------------------------------------------------------------------
-- EPGP (issue #319)
----------------------------------------------------------------------
function Points:EP(key)
    local s = standings()[key]
    return s and s.earned or 0
end

function Points:GP(key)
    local s = standings()[key]
    return (s and s.spent or 0) + (tonumber(cfg().baseGP) or 0)
end

-- Priority: EP / GP, with GP never under 1 so a new raider divides by something. Below the EP the
-- guild asks for there is no priority: after everyone who has it.
function Points:PR(key)
    local ep = self:EP(key)
    local pr = ep / math.max(1, self:GP(key))
    if ep < (tonumber(cfg().minEP) or 0) then return pr - 1e6 end
    return pr
end

-- What an item costs the winner: the guild's own price for that item, else in EPGP its GP by slot and
-- item level against the price of a chest piece, else the one price per item.
-- `system` is the loot system the item is given under (nil: the one in force). The price is worked out
-- by slot and item level only under the EPGP loot system, or once the guild has set a reference item
-- level: a guild on another loot system whose points were in the EPGP mode of before paid the one price
-- per item, and still does (a ring is not suddenly half price).
function Points:PriceOf(itemLink, system)
    local c = cfg()
    local base = tonumber(c.itemCost) or 0
    local itemId = itemLink and tonumber(tostring(itemLink):match("item:(%d+)"))
    local own = itemId and type(c.itemPrices) == "table" and tonumber(c.itemPrices[itemId])
    if own then return own end
    local ref = tonumber(c.gpRefIlvl) or 0
    system = system or (GuildOS.GetLootSystem and GuildOS:GetLootSystem())
    if not (system == "epgp" or ref > 0) or base <= 0 or not itemLink then return base end
    local _, _, _, ilvl, _, _, _, _, equipLoc = GuildOS.Compat.GetItemInfo(itemLink)
    local gp = base * (SLOT_GP[equipLoc or ""] or 1)
    if ref > 0 and tonumber(ilvl) then gp = gp * 2 ^ ((ilvl - ref) / GP_ILVL_STEP) end
    return math.max(1, math.floor(gp + 0.5))
end

-- The guild's own price for one item (nil or 0 goes back to the rule). Officer only.
function Points:SetItemPrice(itemId, price)
    if not GuildOS:IsOfficer() or not tonumber(itemId) then return false end
    local c = self:Pool().config
    c.itemPrices = type(c.itemPrices) == "table" and c.itemPrices or {}
    price = tonumber(price)
    c.itemPrices[tonumber(itemId)] = (price and price > 0) and math.floor(price) or nil
    self:BroadcastSnapshot()
    return true
end

-- The price to enter a roll (issue #309): everyone who asked pays it, and whoever lost gets part of it
-- back. `asked` is the list of keys; returns what each paid in the end, { { key, amount }, ... }, for
-- an undo to give back.
-- `entry` and `refundPct` are the loot rule's own when it names them (its "entry" effect); without
-- them, the pool's settings as before.
function Points:ChargeEntry(asked, winnerKey, itemName, entry, refundPct)
    local c = cfg()
    entry = tonumber(entry) or tonumber(c.entryCost) or 0
    if entry <= 0 or not GuildOS:IsOfficer() then return {} end
    refundPct = tonumber(refundPct) or tonumber(c.refundPct) or 0
    -- To the nearest: 29% of 100 is 29, which a floor (and 0.29 * 100 being a hair under 29) made 28.
    local back = math.floor(entry * math.min(100, math.max(0, refundPct)) / 100 + 0.5)
    local paid, entries = {}, {}
    for _, key in ipairs(asked) do
        local e
        if key == winnerKey then
            e = self:MakeEntry(key, -entry, string.format(L["Rolled for %s"], itemName), "spend")
        elseif entry - back > 0 then
            e = self:MakeEntry(key, -(entry - back),
                string.format(L["Lost the roll for %s (%d paid, %d back)"], itemName, entry, back), "spend")
        end
        if e then
            if self:GetMode() == "epgp" then e.acct = "gp" end
            self:ApplyEntry(e); self:MarkApplied(e.op)
            entries[#entries + 1] = e
            paid[#paid + 1] = { key = key, amount = -e.delta }
        end
    end
    if #entries > 0 then publishDelta(entries) end
    self:Refresh()
    return paid
end

----------------------------------------------------------------------
-- Counter accounts (issue #334)
-- pool.accounts[acct] = { rs = "night"|"lockout"|"never", per = <period>, v = { [key] = n },
--                         t = { [key] = <when the key's figure last moved> } }
-- Every entry names the period it was made in. An entry of a newer period empties the account before
-- it adds; one of an older period is late and adds nothing, so every client ends on the same figures
-- in whatever order the entries reach it.
-- A snapshot never replaces an account (MergeAccounts): one of an older period changes nothing, one of
-- a newer period is taken whole, and within the same period each key keeps the figure that moved last
-- (`t`), or the higher one where either side cannot say when. An officer's snapshot from before
-- tonight's raid used to wipe tonight's +1, and the next item went to the wrong raider.
----------------------------------------------------------------------
-- The period `now` falls in: the raid session's start for a night (or the moment itself with no
-- session on), the lockout week, and one period for ever.
function Points:CounterPeriod(reset, now)
    now = now or GetServerTime()
    if reset == "lockout" then
        local RT = GuildOS.RaidTracker
        return (RT and RT.GetWeekNum) and RT:GetWeekNum(now) or math.floor(now / WEEK)
    elseif reset == "night" then
        local raid = GuildOS.RaidTracker and GuildOS.RaidTracker.currentRaid
        return (raid and tonumber(raid.startTime)) or now
    end
    return 0
end

local function samePeriod(reset, a, b)
    if reset == "night" then return math.abs(a - b) < NIGHT end
    return a == b
end

-- What `key` holds on the counter `acct`: nothing once its period is over.
function Points:Counter(acct, key, pool)
    pool = pool or self:Pool()
    local a = pool.accounts and pool.accounts[acct]
    if not a then return 0 end
    local now = self:CounterPeriod(a.rs)
    if now > a.per and not samePeriod(a.rs, now, a.per) then return 0 end
    return a.v[key] or 0
end

-- Whether `e` is a counter entry this client can apply: a peer's are read as carefully as its own.
local function counterEntry(e)
    return type(e) == "table" and type(e.key) == "string" and e.key ~= ""
        and type(e.acct) == "string" and #e.acct <= 8 and e.acct:find("^[a-z0-9]+$") ~= nil
        and COUNTER_RESETS[e.rs] == true
        and type(e.per) == "number" and e.per >= 0 and e.per < math.huge
        and type(e.delta) == "number" and e.delta == math.floor(e.delta)
        and e.delta ~= 0 and math.abs(e.delta) <= COUNTER_MAX
end

function Points:ApplyCounterEntry(e, pool)
    if not counterEntry(e) then return false end
    pool = pool or self:Pool()
    pool.accounts = pool.accounts or {}
    local a = pool.accounts[e.acct]
    if not a or a.rs ~= e.rs then
        -- A new account, or one whose rule now resets another way: it starts over.
        a = { rs = e.rs, per = e.per, v = {} }
        pool.accounts[e.acct] = a
    elseif not samePeriod(a.rs, e.per, a.per) then
        if e.per < a.per then return false end
        a.per, a.v, a.t = e.per, {}, {}
    end
    local n = (a.v[e.key] or 0) + e.delta
    a.v[e.key] = n > 0 and n or nil
    -- When this key's figure last moved, for a snapshot to be merged by (MergeAccounts).
    local ts = tonumber(e.ts)
    if ts and ts > 0 and ts < math.huge then
        a.t = a.t or {}
        a.t[e.key] = math.max(a.t[e.key] or 0, ts)
    end
    return true
end

-- Add `delta` (negative to give back) to `key` on the counter `acct`, which resets the way `reset`
-- says. `per` is the period of the entry being undone; nil is now. Kept here whoever awards, and told
-- to the guild when an officer does. Returns the entry, for an undo.
-- `op` names the entry after what caused it (an award, LootMaster), so every client that makes it for
-- the same cause makes it once: nil when it was already made here.
function Points:AddCounter(acct, key, delta, reset, per, op)
    local e = self:MakeEntry(key, delta, "", "counter")
    e.acct, e.rs = acct, COUNTER_RESETS[reset] and reset or "never"
    e.per = per or self:CounterPeriod(e.rs)
    if op then
        if self:Pool().appliedOps[op] then return nil end
        e.op = op
    end
    if not self:ApplyCounterEntry(e) then return nil end
    self:MarkApplied(e.op)
    if GuildOS:IsOfficer() and canTell() then
        GuildOS.SyncService:Publish("points", "cdelta", { entries = { e } })
    end
    self:Refresh()
    return e
end

-- What the loot rule in force gives a counter by itself (its accounts' `earn`, with `auto` "raid" or
-- "boss"): `auto` happened for everyone in `keys`. `tag` makes each entry's name the event's own, so
-- every officer's client that saw the event gives it once; without one the caller is the only client
-- that gives it (the raid leader's, on a boss kill). Returns how many entries were made.
function Points:EarnCounters(auto, keys, tag)
    local LR = GuildOS.LootRule
    if not (LR and LR.Active and GuildOS:IsOfficer()) then return 0 end
    local pool = self:Pool()
    if not (pool and pool.appliedOps) then return 0 end
    local entries = {}
    for _, a in ipairs(LR:Counters()) do
        -- A bonus kept per item is fed by what was reserved (EarnItemBonuses), never by the key alone.
        for _, earn in ipairs(a.scope ~= "item" and a.earn or {}) do
            if earn.auto == auto then
                for _, key in ipairs(keys) do
                    -- An account with a cap (a bonus, issue #337) never grows past it.
                    local value = earn.value
                    if a.cap then value = math.min(value, math.max(0, a.cap - self:Counter(a.key, key, pool))) end
                    local e = self:MakeEntry(key, value, "", "counter")
                    e.acct, e.rs = a.key, COUNTER_RESETS[a.reset] and a.reset or "never"
                    e.per = self:CounterPeriod(e.rs)
                    if tag then e.op = string.format("C%s-%s-%s-%s", tag, a.key, earn.key, key) end
                    if not pool.appliedOps[e.op] and self:ApplyCounterEntry(e, pool) then
                        self:MarkApplied(e.op, pool)
                        entries[#entries + 1] = e
                    end
                end
            end
        end
    end
    if #entries > 0 then
        if canTell() then GuildOS.SyncService:Publish("points", "cdelta", { entries = entries }) end
        self:Refresh()
    end
    return #entries
end

-- Tonight's sheet for the raid `session`: the site's while its night lasts, else the imported one only
-- when it was imported for this raid (in the night before it began, up to its end). An import is never
-- cleared by itself: last week's, or another raid's, would grow last week's reserves again or wipe
-- everybody's (issue #433).
local function sheetOf(session)
    local site = GuildOS.SiteLoot and GuildOS.SiteLoot.Reserves and GuildOS.SiteLoot:Reserves()
    if site then return site.items end
    local db = GuildOS.SoftRes and GuildOS.SoftRes.GetDB and GuildOS.SoftRes:GetDB()
    local meta = db and db.meta or {}
    local at = tonumber(meta.importedAt) or 0
    local start = tonumber(session.startTime) or 0
    local from = start - NIGHT
    -- Two raids in one evening: a sheet imported before the earlier one ended was that raid's.
    local saved = GuildOS.db and GuildOS.db.raidTracker and GuildOS.db.raidTracker.sessions
    for _, other in pairs(type(saved) == "table" and saved or {}) do
        local ended = type(other) == "table" and other ~= session and tonumber(other.endTime)
        if ended and ended <= start and ended > from then from = ended end
    end
    local to = tonumber(session.endTime) or GetServerTime()
    if db and at >= from and at <= to then return db.items end
    return nil
end

-- The items each of `keys` reserved on tonight's sheet: { [key] = { [itemId] = true } }, or nil when no
-- sheet is in force (none imported for this raid, none from the site, or retail, which has none).
-- Matched by the character's name, as the reserves name them.
local function reservedBy(session, keys)
    local items = GuildOS.SoftRes and sheetOf(session)
    if type(items) ~= "table" or next(items) == nil then return nil end
    local byName = {}
    for itemId, list in pairs(items) do
        for _, e in ipairs(type(list) == "table" and list or {}) do
            local name = type(e) == "table" and type(e.name) == "string" and string.lower(e.name) or nil
            if name and tonumber(itemId) then
                byName[name] = byName[name] or {}
                byName[name][tonumber(itemId)] = true
            end
        end
    end
    local out = {}
    for _, key in ipairs(keys) do
        out[key] = byName[string.lower(key:match("^([^-]+)") or key)] or {}
    end
    return out
end

-- What each of `keys` was given on the raid night of `session`: { [key] = { [itemId] = true } }, from
-- the loot history up to the raid's end, back to a night before its start: a raid broken in two
-- sessions is one night, and its entries are named after the night.
local function wonIn(session, keys)
    local out, want = {}, {}
    for _, key in ipairs(keys) do want[key] = true; out[key] = {} end
    local from = (tonumber(session.startTime) or 0) - NIGHT
    local to = tonumber(session.endTime) or GetServerTime()
    for _, e in ipairs(GuildOS.db and GuildOS.db.lootHistory or {}) do
        local ts = tonumber(e.timestamp) or 0
        -- A master looter's award names the item by its link only.
        local itemId = tonumber(e.itemId) or (type(e.itemLink) == "string" and tonumber(e.itemLink:match("item:(%d+)")))
        if ts >= from and ts <= to and want[e.playerKey] and itemId and not e.undone then
            out[e.playerKey][itemId] = true
        end
    end
    return out
end

-- A bonus kept per item (SR+ by item, issue #433), at a raid's end: for everyone who was there, each
-- item they reserved tonight and were not given grows by the account's "raid" earn, never past its cap;
-- each item they hold a figure on and did not reserve tonight goes back to nothing, since only reserves
-- in a row add up. Whoever missed the raid keeps what they hold. With no sheet in force nothing moves:
-- a night nobody imported reserves for wipes nobody's. Each entry is named after the raid night, so the
-- same raid ended twice counts once. Returns how many entries were made.
function Points:EarnItemBonuses(session, keys, night)
    local LR = GuildOS.LootRule
    if not (LR and LR.Active and GuildOS:IsOfficer()) then return 0 end
    local pool = self:Pool()
    if not (pool and pool.appliedOps) then return 0 end
    local accounts = {}
    for _, a in ipairs(LR:Counters()) do
        if a.scope == "item" then accounts[#accounts + 1] = a end
    end
    if #accounts == 0 then return 0 end
    local reserved = reservedBy(session, keys)
    if not reserved then return 0 end
    local won = wonIn(session, keys)
    local entries = {}
    -- One entry moves a counter by a hundred at most: a larger move takes several, each named apart.
    local function give(a, key, delta, op)
        local step = 0
        while delta ~= 0 do
            local d = math.max(-COUNTER_MAX, math.min(COUNTER_MAX, delta))
            step = step + 1
            local e = self:MakeEntry(key, d, "", "counter")
            e.acct, e.rs = a.key, COUNTER_RESETS[a.reset] and a.reset or "never"
            e.per = self:CounterPeriod(e.rs)
            e.op = string.format("%s%s-%s-%s.%d", op, night or "", a.key, key, step)
            if pool.appliedOps[e.op] or not self:ApplyCounterEntry(e, pool) then return end
            self:MarkApplied(e.op, pool)
            entries[#entries + 1] = e
            delta = delta - d
        end
    end
    for _, a in ipairs(accounts) do
        local value = 0
        for _, earn in ipairs(a.earn or {}) do
            if earn.auto == "raid" then value = value + earn.value end
        end
        local held = pool.accounts and pool.accounts[a.key]
        for _, key in ipairs(keys) do
            -- What this player holds a figure on and did not reserve tonight starts over.
            local prefix, stale = key .. "#", {}
            for k in pairs(held and held.v or {}) do
                local itemId = k:sub(1, #prefix) == prefix and tonumber(k:sub(#prefix + 1)) or nil
                if itemId and not reserved[key][itemId] then stale[#stale + 1] = k end
            end
            for _, k in ipairs(stale) do give(a, k, -self:Counter(a.key, k, pool), "Z") end
            -- What they reserved and were not given grows.
            for itemId in pairs(value > 0 and reserved[key] or {}) do
                if not won[key][itemId] then
                    local k = LR:CounterKey(a, key, itemId)
                    local grow = value
                    if a.cap then grow = math.min(grow, math.max(0, a.cap - self:Counter(a.key, k, pool))) end
                    give(a, k, grow, "I")
                end
            end
        end
    end
    if #entries > 0 then
        if canTell() then GuildOS.SyncService:Publish("points", "cdelta", { entries = entries }) end
        self:Refresh()
    end
    return #entries
end

-- Everyone on a counter or a bonus account with something on it: { { key, name, class, value }, ... },
-- the most first. For the points window.
function Points:CounterStandings(acct, pool)
    pool = pool or self:Pool()
    local a = pool.accounts and pool.accounts[acct]
    local list = {}
    for key in pairs(a and a.v or {}) do
        local value = self:Counter(acct, key, pool)
        if value > 0 then
            -- A bonus kept per item (issue #433) is held at "Name-Realm#itemId": one row per item.
            local who, item = key:match("^(.-)#(%d+)$")
            who = who or key
            local m = GuildOS.db.members and GuildOS.db.members[who]
            list[#list + 1] = { key = key, name = who:match("^([^-]+)") or who, class = (m and m.class) or "",
                value = value, itemId = tonumber(item) }
        end
    end
    table.sort(list, function(x, y)
        if x.value ~= y.value then return x.value > y.value end
        if x.name:lower() ~= y.name:lower() then return x.name:lower() < y.name:lower() end
        return (x.itemId or 0) < (y.itemId or 0)
    end)
    return list
end

----------------------------------------------------------------------
-- Who is in the raid now, by key: who a zero-sum share goes to, and who moves up a queue.
----------------------------------------------------------------------
function Points:RaidKeys()
    local keys, seen = {}, {}
    if not IsInRaid() then return keys end
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local nm, realm
        if UnitExists(unit) then nm, realm = GuildOS.Compat.UnitIdentity(unit) end
        local key = nm and GuildOS:GetPlayerKey(nm, (realm and realm ~= "") and realm or GetRealmName())
        if key and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    return keys
end

----------------------------------------------------------------------
-- Zero-sum (issue #337): what the winner was charged for an item, shared equally among `keys` (whoever
-- is in the raid, the winner too), the remainder dropped. Each share is an entry of the log, never held
-- to a cap. Returns what each got, { { key, amount }, ... }, for an undo to take back.
----------------------------------------------------------------------
function Points:Split(keys, total, reason)
    local shares = {}
    total = math.floor(tonumber(total) or 0)
    if not GuildOS:IsOfficer() or #keys == 0 or total <= 0 then return shares end
    local share = math.floor(total / #keys)
    if share <= 0 then return shares end
    local entries = {}
    local epgp = self:GetMode() == "epgp"
    for _, key in ipairs(keys) do
        local e = self:MakeEntry(key, share, reason, "split")
        if epgp then e.acct = "ep" end
        self:ApplyEntry(e); self:MarkApplied(e.op)
        entries[#entries + 1] = e
        shares[#shares + 1] = { key = key, amount = share }
    end
    publishDelta(entries)
    self:Refresh()
    return shares
end

-- The shares of a split taken back, as they were given.
function Points:UndoSplit(shares, reason)
    if not GuildOS:IsOfficer() then return 0 end
    local entries = {}
    local epgp = self:GetMode() == "epgp"
    for _, s in ipairs(shares or {}) do
        local e = self:MakeEntry(s.key, -s.amount, reason, "undo")
        if epgp then e.acct = "ep" end
        self:ApplyEntry(e); self:MarkApplied(e.op)
        entries[#entries + 1] = e
    end
    if #entries > 0 then publishDelta(entries) end
    self:Refresh()
    return #entries
end

----------------------------------------------------------------------
-- Queue accounts (issue #337)
-- pool.queues[acct] = { seq = n, op = <the entry that set it>, list = { key, ... } }, the first of the
-- list first in line. Every change is an entry that carries the whole order and the queue's next
-- sequence number: an entry with a higher number replaces the order, one with a lower number is late and
-- changes nothing, and two with the same number settle by their op, so every client ends on the same
-- order in whatever order the entries reach it.
----------------------------------------------------------------------
-- The order of the queue `acct`, first in line first. Not a copy: never changed by a caller.
function Points:Queue(acct, pool)
    pool = pool or self:Pool()
    local q = pool.queues and pool.queues[acct]
    return q and q.list or {}
end

-- The place of `key` in the queue, or nil.
function Points:QueuePos(acct, key, pool)
    for i, k in ipairs(self:Queue(acct, pool)) do
        if k == key then return i end
    end
    return nil
end

-- Whether `e` is a queue entry this client can apply: a peer's are read as carefully as its own.
local function queueEntry(e)
    if not (type(e) == "table" and type(e.op) == "string" and type(e.acct) == "string" and #e.acct <= 8
        and e.acct:find("^[a-z0-9]+$") and type(e.seq) == "number" and e.seq == math.floor(e.seq)
        and e.seq >= 1 and e.seq < 2 ^ 31 and type(e.list) == "table") then
        return false
    end
    local n, seen = 0, {}
    for _ in pairs(e.list) do n = n + 1 end
    if n ~= #e.list or n > QUEUE_MAX then return false end
    for _, key in ipairs(e.list) do
        if type(key) ~= "string" or key == "" or #key > QUEUE_KEY_MAX or key:find("%c") or seen[key] then return false end
        seen[key] = true
    end
    return true
end

function Points:ApplyQueueEntry(e, pool)
    if not queueEntry(e) then return false end
    pool = pool or self:Pool()
    pool.queues = pool.queues or {}
    local q = pool.queues[e.acct]
    if q and (e.seq < q.seq or (e.seq == q.seq and e.op <= q.op)) then return false end
    local list = {}
    for i, key in ipairs(e.list) do list[i] = key end
    pool.queues[e.acct] = { seq = e.seq, op = e.op, list = list }
    return true
end

-- The queue's order becomes `list`. Kept here whoever awards, and told to the guild when an officer
-- does, as a counter's entry is. Returns the entry, or nil.
function Points:SetQueue(acct, list)
    local pool = self:Pool()
    local q = pool.queues and pool.queues[acct]
    local e = {
        op = newOp(), acct = acct, seq = (q and q.seq or 0) + 1, list = list,
        author = GuildOS.Compat.PlayerName(), ts = GetServerTime(),
        core = self:ActiveCore(),
    }
    if not self:ApplyQueueEntry(e, pool) then return nil end
    self:MarkApplied(e.op, pool)
    if GuildOS:IsOfficer() and canTell() then
        GuildOS.SyncService:Publish("points", "qset", { entries = { e } })
    end
    self:Refresh()
    return e
end

-- Whoever of `keys` the queue does not hold joins it: at the end, in the order of their names (so two
-- clients that add the same raid end on the same order), or each at a random place when `newcomer` is
-- "random". Returns how many joined.
function Points:QueueJoin(acct, keys, newcomer)
    local list, held, fresh = {}, {}, {}
    for i, key in ipairs(self:Queue(acct)) do list[i], held[key] = key, true end
    for _, key in ipairs(keys) do
        if not held[key] and #list + #fresh < QUEUE_MAX then
            held[key] = true
            fresh[#fresh + 1] = key
        end
    end
    if #fresh == 0 then return 0 end
    table.sort(fresh, function(a, b) return a:lower() < b:lower() end)
    for _, key in ipairs(fresh) do
        if newcomer == "random" then
            table.insert(list, math.random(1, #list + 1), key)
        else
            list[#list + 1] = key
        end
    end
    return self:SetQueue(acct, list) and #fresh or 0
end

-- The winner goes to the end of the queue. `frozen` is the classic Suicide Kings rule: only whoever
-- is in the raid (`present`, a list of keys) moves up, and whoever is absent keeps their slot, so the
-- winner lands in the slot of the last raider below them. Without it everyone below moves up and the
-- winner is last of all. Returns the move, { acct, key, slots }, for an undo; nil when nothing moved.
function Points:QueueBottom(acct, key, present, frozen)
    local old = self:Queue(acct)
    local from = self:QueuePos(acct, key)
    if not from then return nil end
    local here = {}
    for _, k in ipairs(present or {}) do here[k] = true end
    -- The slots that take part: the winner's, and every one below it (held by a raider, when frozen).
    local slots = { from }
    for i = from + 1, #old do
        if not frozen or here[old[i]] then slots[#slots + 1] = i end
    end
    if #slots < 2 then return nil end
    local list = {}
    for i, k in ipairs(old) do list[i] = k end
    for n = 1, #slots - 1 do list[slots[n]] = old[slots[n + 1]] end
    list[slots[#slots]] = key
    if not self:SetQueue(acct, list) then return nil end
    -- Slots in a row (nobody absent between them) are kept as their first and last alone.
    if slots[#slots] - slots[1] == #slots - 1 then return { acct = acct, key = key, from = slots[1], to = slots[#slots] } end
    return { acct = acct, key = key, slots = slots }
end

-- A move of `QueueBottom` taken back: everyone it moved goes back to the slot they had. When the
-- queue changed in between so that the winner is no longer where the move left them, the winner alone
-- goes back to their slot.
function Points:QueueUndo(move)
    if type(move) ~= "table" or not move.acct then return false end
    local old = self:Queue(move.acct)
    local slots = move.slots
    if not slots then
        slots = {}
        for i = move.from, move.to do slots[#slots + 1] = i end
    end
    local list = {}
    for i, k in ipairs(old) do list[i] = k end
    if old[slots[#slots]] == move.key then
        for n = #slots, 2, -1 do list[slots[n]] = old[slots[n - 1]] end
        list[slots[1]] = move.key
    else
        local at = self:QueuePos(move.acct, move.key)
        if not at then return false end
        table.remove(list, at)
        table.insert(list, math.min(slots[1], #list + 1), move.key)
    end
    return self:SetQueue(move.acct, list) ~= nil
end

-- The queue for the points window: { { key, name, class, value = <place> }, ... }, first in line first.
function Points:QueueStandings(acct, pool)
    local list = {}
    for i, key in ipairs(self:Queue(acct, pool)) do
        local m = GuildOS.db.members and GuildOS.db.members[key]
        list[i] = { key = key, name = key:match("^([^-]+)") or key, class = (m and m.class) or "", value = i }
    end
    return list
end

-- The queues of a snapshot, as this client keeps them: each read as an entry is.
local function localQueues(queues)
    local out = {}
    for acct, q in pairs(queues) do
        if type(q) == "table" and type(q.list) == "table" then
            local list, seen = {}, {}
            for _, key in ipairs(q.list) do
                if type(key) == "string" then
                    key = GuildOS:LocalMemberKey(key)
                    if not seen[key] then seen[key] = true; list[#list + 1] = key end
                end
            end
            local e = { op = q.op, acct = acct, seq = q.seq, list = list }
            if queueEntry(e) then out[acct] = e end
        end
    end
    return out
end

-- A counter key another client built, as this client keys it: the member's part rebuilt (issue #97),
-- and a bonus kept per item (issue #433) keeping its "#itemId", which LocalMemberKey alone would cut off
-- on WoW: Forever along with the realm.
local function localCounterKey(key)
    local who, item = key:match("^(.-)(#%d+)$")
    if who and who ~= "" then return GuildOS:LocalMemberKey(who) .. item end
    return GuildOS:LocalMemberKey(key)
end

-- The accounts of a snapshot, as this client keeps them: every figure checked, every key its own.
local function localAccounts(accounts)
    local out = {}
    for acct, a in pairs(accounts) do
        if type(acct) == "string" and acct:find("^[a-z0-9]+$") and #acct <= 8 and type(a) == "table"
            and COUNTER_RESETS[a.rs] and type(a.per) == "number" and type(a.v) == "table" then
            local v = {}
            for key, n in pairs(a.v) do
                if type(key) == "string" and type(n) == "number" and n > 0 and n < math.huge then
                    key = localCounterKey(key)
                    v[key] = (v[key] or 0) + math.floor(n)
                end
            end
            local t = {}
            for key, at in pairs(type(a.t) == "table" and a.t or {}) do
                if type(key) == "string" and type(at) == "number" and at > 0 and at < math.huge then
                    key = localCounterKey(key)
                    t[key] = math.max(t[key] or 0, at)
                end
            end
            out[acct] = { rs = a.rs, per = a.per, v = v, t = t }
        end
    end
    return out
end

-- A snapshot's accounts into this client's, account by account (see "Counter accounts" above).
function Points:MergeAccounts(pool, accounts)
    pool.accounts = pool.accounts or {}
    for acct, theirs in pairs(localAccounts(accounts)) do
        local mine = pool.accounts[acct]
        if not mine then
            pool.accounts[acct] = theirs
        elseif mine.rs ~= theirs.rs then
            -- Reset another way than here: two periods that cannot be compared. What is here stays,
            -- unless it is empty; the entry that changes how an account resets says so by itself.
            if next(mine.v) == nil then pool.accounts[acct] = theirs end
        elseif samePeriod(mine.rs, theirs.per, mine.per) then
            mine.t = mine.t or {}
            local keys = {}
            for key in pairs(mine.v) do keys[key] = true end
            for key in pairs(theirs.v) do keys[key] = true end
            for key in pairs(mine.t) do keys[key] = true end
            for key in pairs(theirs.t) do keys[key] = true end
            for key in pairs(keys) do
                local mineAt, theirsAt = mine.t[key] or 0, theirs.t[key] or 0
                local has, got = mine.v[key] or 0, theirs.v[key] or 0
                if mineAt > 0 and theirsAt > 0 and mineAt ~= theirsAt then
                    if theirsAt > mineAt then has = got end
                else
                    has = math.max(has, got)
                end
                mine.v[key] = has > 0 and has or nil
                if math.max(mineAt, theirsAt) > 0 then mine.t[key] = math.max(mineAt, theirsAt) end
            end
        elseif theirs.per > mine.per then
            pool.accounts[acct] = theirs
        end
    end
end

----------------------------------------------------------------------
-- Sync (domain "points")
-- Delta entries carry a `core` field so receivers route them to the
-- right pool. Snapshots carry `core` in the payload.
-- Old clients without the `core` field fall back to global db.points.
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Entries for a core this client does not have (yet), kept until it arrives (review of #339)
-- An entry is published once, with no ack, and SyncService drops an envelope it has seen: skipped
-- unkept, nothing would ever bring it back. db.pointsWaiting[core] holds them, in the order heard, as
-- { act, e, at }; the core created, imported or renamed into existence here plays them
-- (ReplayWaiting), each applied once (appliedOps). Bounded as SavedVariables must be: WAIT_MAX entries
-- a core (the oldest go first), WAIT_CORES cores (the one heard of longest ago goes), WAIT_AGE seconds.
----------------------------------------------------------------------
local WAIT_MAX, WAIT_CORES, WAIT_AGE = 200, 8, 30 * 86400

local function waiting()
    local w = GuildOS.db.pointsWaiting
    if type(w) ~= "table" then w = {}; GuildOS.db.pointsWaiting = w end
    return w
end

-- The name an entry gives a core is the sender's: what was kept here before a rename, and an officer
-- whose client has not seen it yet, still say the old one. db.pointsAliases[old] = { to, at } is each
-- rename here (CoreManager's moveCore, NoteRename), at most ALIAS_MAX, let go after WAIT_AGE as what
-- is kept is.
local ALIAS_MAX = 16

function Points:NoteRename(oldName, newName)
    if type(oldName) ~= "string" or type(newName) ~= "string" or oldName == newName or #oldName > 96 then return end
    local a = GuildOS.db.pointsAliases
    if type(a) ~= "table" then a = {}; GuildOS.db.pointsAliases = a end
    local now = GetServerTime()
    a[newName] = nil                       -- a core's own name now, no one's alias
    a[oldName] = { to = newName, at = now }
    local n, oldest, oldestAt = 0, nil, math.huge
    for name, to in pairs(a) do
        local at = type(to) == "table" and tonumber(to.at) or 0
        if at < now - WAIT_AGE then a[name] = nil else
            n = n + 1
            if at < oldestAt then oldest, oldestAt = name, at end
        end
    end
    if n > ALIAS_MAX and oldest then a[oldest] = nil end
    if next(a) == nil then GuildOS.db.pointsAliases = nil end
end

-- The core this client has for the name `name` an entry gives, or nil. Its own name; else where a
-- rename here took it (pointsAliases); else the Discord core known here under another name (named by
-- its tag, coreFor): the one whose Discord name it is, or whose tag it reduces to (the name it had on
-- Discord when it was made, before a rename this client never saw).
function Points:CoreNamed(name)
    local cores = GuildOS.db and GuildOS.db.cores
    if type(name) ~= "string" or name == "" or type(cores) ~= "table" then return nil end
    local a, since = GuildOS.db.pointsAliases, GetServerTime() - WAIT_AGE
    for _ = 1, ALIAS_MAX + 1 do
        if type(cores[name]) == "table" then return name end
        local to = type(a) == "table" and a[name]
        if not (type(to) == "table" and type(to.to) == "string" and (tonumber(to.at) or 0) >= since) then break end
        name = to.to
    end
    -- A Discord core known here under another name: by the Discord name it carries, or by the tag the
    -- name reduces to. Only when exactly one core answers: a name the Discord reused can point at two
    -- (one core remembers it as its Discord name, another holds its tag), and an entry applied to the
    -- wrong core is worse than an entry kept until it is clear.
    local CM = GuildOS.CoreManager
    local slug = CM and CM.Slug and CM.Slug(name)
    local found, many = nil, false
    for here, core in pairs(cores) do
        if type(core) == "table" and type(core.discordTag) == "string"
            and (core.discordName == name or core.discordTag == slug) then
            if found and found ~= here then many = true end
            found = here
        end
    end
    return (not many) and found or nil
end

-- The pool an entry naming `core` goes to: the guild's for none, the core's this client has for it
-- (CoreNamed), nil while it has none.
local function poolFor(core)
    if core == nil or core == "" then return Points:GetDBForCore(core) end
    local here = Points:CoreNamed(core)
    return here and Points:GetDBForCore(here) or nil
end

-- Keeps `e` (an entry of `act`) for the core it names, when that is a core this client lacks.
local function keepForLater(act, e)
    local core = e.core
    if type(core) ~= "string" or core == "" or #core > 96 or type(e.op) ~= "string" then return end
    local w, now = waiting(), GetServerTime()
    local list = w[core]
    if type(list) ~= "table" then
        local n, oldest, oldestAt = 0, nil, math.huge
        for name, l in pairs(w) do
            n = n + 1
            local last = type(l) == "table" and l[#l] and tonumber(l[#l].at) or 0
            if last < oldestAt then oldest, oldestAt = name, last end
        end
        if n >= WAIT_CORES and oldest then w[oldest] = nil end
        list = {}
        w[core] = list
    end
    for _, kept in ipairs(list) do
        if type(kept) == "table" and type(kept.e) == "table" and kept.e.op == e.op then return end
    end
    list[#list + 1] = { act = act, e = e, at = now }
    while #list > WAIT_MAX do table.remove(list, 1) end
end
Points.KeepForLater = keepForLater

-- Plays what was kept for `coreName`, now that this client has it, under that name or one that is it
-- (CoreNamed: renamed here, or the Discord's); what is too old is let go. Returns how many entries were
-- played.
function Points:ReplayWaiting(coreName)
    local w = GuildOS.db and GuildOS.db.pointsWaiting
    if type(w) ~= "table" or type(coreName) ~= "string" then return 0 end
    if not self:GetDBForCore(coreName) then return 0 end
    local names = {}
    for name, list in pairs(w) do
        if type(list) == "table" and self:CoreNamed(name) == coreName then names[#names + 1] = name end
    end
    table.sort(names)
    local since, n = GetServerTime() - WAIT_AGE, 0
    for _, name in ipairs(names) do
        local list = w[name]
        w[name] = nil
        for _, kept in ipairs(list) do
            if type(kept) == "table" and type(kept.e) == "table" and (tonumber(kept.at) or 0) >= since
                and (kept.act == "delta" or kept.act == "cdelta" or kept.act == "qset") then
                kept.e.core = coreName
                self:OnSync({ act = kept.act, data = { entries = { kept.e } } })
                n = n + 1
            end
        end
    end
    if next(w) == nil then GuildOS.db.pointsWaiting = nil end
    return n
end

-- Every core kept for that this client has by now (at login: the inbox's import ran first), and what
-- is too old let go.
function Points:ReplayAllWaiting()
    local w = GuildOS.db and GuildOS.db.pointsWaiting
    if type(w) ~= "table" then return end
    local since, names = GetServerTime() - WAIT_AGE, {}
    for name, list in pairs(w) do
        local last = type(list) == "table" and list[#list] and tonumber(list[#list].at) or 0
        if type(name) ~= "string" or last < since then w[name] = nil else names[#names + 1] = name end
    end
    for _, name in ipairs(names) do
        local here = self:CoreNamed(name)
        if here then self:ReplayWaiting(here) end
    end
    if GuildOS.db.pointsWaiting and next(GuildOS.db.pointsWaiting) == nil then GuildOS.db.pointsWaiting = nil end
end

function Points:OnSync(env)
    local d = env.data
    if env.act == "delta" and d and d.entries then
        local applied = false
        for _, e in ipairs(d.entries) do
            e.key = GuildOS:LocalMemberKey(e.key)   -- the sending officer's key, as this client's (#97)
            -- A core this client does not have (yet): kept, never marked, so it lands once it arrives.
            local pool = poolFor(e.core)
            if not pool then keepForLater("delta", e) end
            if pool and e.op and not pool.appliedOps[e.op] then
                self:ApplyEntry(e, pool)
                self:MarkApplied(e.op, pool)
                applied = true
            end
        end
        if applied then self:Refresh() end
    elseif env.act == "cdelta" and type(d) == "table" and type(d.entries) == "table" then
        -- The counters' own entries (issue #334), each applied once like the points'.
        local applied = false
        for _, e in ipairs(d.entries) do
            if type(e) == "table" and type(e.key) == "string" and type(e.op) == "string" then
                e.key = localCounterKey(e.key)
                local pool = poolFor(e.core)
                if not pool then keepForLater("cdelta", e) end
                if pool and not pool.appliedOps[e.op] then
                    applied = self:ApplyCounterEntry(e, pool) or applied
                    self:MarkApplied(e.op, pool)
                end
            end
        end
        if applied then self:Refresh() end
    elseif env.act == "qset" and type(d) == "table" and type(d.entries) == "table" then
        -- The queues' own entries (issue #337), each applied once; the newest order wins.
        local applied = false
        for _, e in ipairs(d.entries) do
            if type(e) == "table" and type(e.op) == "string" and type(e.list) == "table" then
                local pool = poolFor(e.core)
                if not pool then keepForLater("qset", e) end
                -- A group's own queue, from a client that does not know it uses its elenco's (#352): as
                -- with its snapshot, the elenco's queue here is not the group's and is left alone.
                local here = pool and type(e.core) == "string" and e.core ~= "" and self:CoreNamed(e.core)
                if here and ownerOf(here) ~= here then
                    self:MarkApplied(e.op, pool)
                elseif pool and not pool.appliedOps[e.op] then
                    local list, seen = {}, {}
                    for _, key in ipairs(e.list) do
                        if type(key) == "string" then
                            key = GuildOS:LocalMemberKey(key)
                            if not seen[key] then seen[key] = true; list[#list + 1] = key end
                        end
                    end
                    applied = self:ApplyQueueEntry({ op = e.op, acct = e.acct, seq = e.seq, list = list }, pool) or applied
                    self:MarkApplied(e.op, pool)
                end
            end
        end
        if applied then self:Refresh() end
    elseif env.act == "snapshot" and d then
        -- A group's own pool, from a client that does not know it uses its elenco's (#352): the elenco's
        -- standings here are not the group's, and are left alone.
        if ownerOf(d.core) ~= d.core then return end
        local pool = self:GetDBForCore(d.core)
        -- A core this client does not have: no pool to write, and its revision left unread, so the
        -- officer's next snapshot for it lands once the core does.
        if not pool then return end
        -- Use a composite revision key so per-core snapshots don't
        -- overwrite each other's revision counter.
        local domain = d.core and ("points:" .. d.core) or "points"
        if GuildOS.SyncService:ShouldApply(domain, "standings", env.rev) then
            if d.mode     then pool.mode     = d.mode     end
            if d.config   then pool.config   = d.config   end
            if d.standings then
                -- Keyed this client's way; one member under two of the sender's keys adds up (#97).
                pool.standings = GuildOS:LocalizeMemberTable(d.standings, function(a, b)
                    -- Each record began at the starting points: counted once (#97).
                    a.current = (a.current or 0) + (b.current or 0) - ((pool.config and pool.config.startingPoints) or 0)
                    a.earned  = (a.earned or 0) + (b.earned or 0)
                    a.spent   = (a.spent or 0) + (b.spent or 0)
                    return a
                end)
            end
            -- The counters, when the officer's client keeps them (issue #334); one from before says
            -- nothing of them, and they stay as they are here.
            -- Merged, never replaced: a snapshot older than tonight leaves tonight's figures alone.
            if type(d.accounts) == "table" then self:MergeAccounts(pool, d.accounts) end
            -- What each named reason has given this week, for its cap: the higher figure of each.
            self:MergeWeekly(pool, d.weekly)
            -- The queues (issue #337): each one's newest order wins, as with its entries.
            if type(d.queues) == "table" then
                for _, e in pairs(localQueues(d.queues)) do self:ApplyQueueEntry(e, pool) end
            end
            GuildOS.SyncService:SetRevision(domain, "standings", env.rev)
            self:Refresh()
        end
    end
end

-- Officer authoritative snapshot (mode + config + full standings).
-- Broadcasts for the currently active core, or for the one `coreName` names (issue #338).
function Points:BroadcastSnapshot(coreName)
    if not GuildOS:IsOfficer() then return end
    if not GuildOS.SyncService then return end
    -- A group with the elenco's pool tells the elenco's (#352); ActiveCore says it already, or the pool
    -- InPool keeps as it is.
    if coreName == nil then coreName = self:ActiveCore() else coreName = ownerOf(coreName) end
    local pool  = poolOf(coreName)
    if pool.nowhere then return end   -- a core this client does not have: nothing of its own to tell
    local domain = (coreName ~= "") and ("points:" .. coreName) or "points"
    local rev = GuildOS.SyncService:NextRevision(domain, "standings")
    GuildOS.SyncService:Publish("points", "snapshot", {
        core     = coreName,
        mode     = pool.mode,
        config   = pool.config,
        standings = pool.standings,
        accounts = pool.accounts,
        queues   = pool.queues,
        -- This week's figures of the named reasons' caps; a client from before reads none of it.
        weekly   = { w = self:Week(), v = (pool.weekly and pool.weekly[self:Week()]) or {} },
    }, { rev = rev })
end

----------------------------------------------------------------------
-- UI refresh hook (set by the Points window when built).
----------------------------------------------------------------------
function Points:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end
