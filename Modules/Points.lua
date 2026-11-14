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
function Points:GetDB()
    if GuildOS.CoreManager then
        return GuildOS.CoreManager:GetPointsDB()
    end
    return GuildOS.db.points
end

-- Returns the points DB for a specific core (used during sync routing).
function Points:GetDBForCore(coreName)
    if GuildOS.CoreManager then
        return GuildOS.CoreManager:GetPointsDB(coreName)
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
-- The pool `coreName` names: nil is the active core's, "" the guild's own.
local function poolOf(coreName)
    if coreName == nil then return Points:GetDB() end
    return Points:GetDBForCore(coreName)
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
    -- Retail names a guildmate with their realm, as its loot history does: two namesakes on connected
    -- realms are two standings (ADR-0026). Elsewhere the name alone, as always.
    local short = GuildOS.Client.isRetail and key or (key:match("^([^-]+)") or key)
    local class = (GuildOS.db.members[key] and GuildOS.db.members[key].class) or ""
    -- Tag with the active core so receivers can route to the right pool
    local coreName = GuildOS.CoreManager and GuildOS.CoreManager:GetActiveName() or ""
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
        local week = math.floor((e.ts or 0) / WEEK)
        pool.weekly = pool.weekly or {}
        for w in pairs(pool.weekly) do
            if w < week - 1 then pool.weekly[w] = nil end
        end
        local t = pool.weekly[week] or {}
        pool.weekly[week] = t
        local wk = e.key .. "|" .. e.rk
        t[wk] = (t[wk] or 0) + e.delta
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
    if GuildOS.SyncService then
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
    local c = (pool or self:GetDB()).config
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
    local c = self:GetDB().config
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

-- What `rk` has given `key` in the week of `ts`.
function Points:WeeklyEarned(key, rk, ts, pool)
    pool = pool or self:GetDB()
    local t = pool.weekly and pool.weekly[math.floor((ts or GetServerTime()) / WEEK)]
    return (t and t[key .. "|" .. rk]) or 0
end

-- How much of `amount` `key` may still earn, and what held the rest back ("weekly", "cap" or nil).
-- EPGP has no cap: EP only matters against GP.
function Points:Room(key, amount, rk, pool)
    pool = pool or self:GetDB()
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
    local pool = self:GetDB()
    if not (pool and pool.config and pool.config.autoAward) then return end
    if not GuildOS:IsOfficer() then return end
    if not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return end
    local amount = cfg().bossAward or 0
    if amount <= 0 then return end
    self:AwardRaidGroup(amount, encounterName or L["Boss kill"])
end

-- Called by RaidTracker when a guild raid's session is saved (issue #309): on time or late, stayed or
-- left early, and the raid itself, for everyone the session saw. Each award's op is the session's own,
-- so two officers' clients ending the same raid give it once.
function Points:OnRaidEnd(session)
    local pool = self:GetDB()
    if not GuildOS:IsOfficer() or type(session) ~= "table" then return 0 end
    local snaps = session.snapshots or {}
    local first, last = snaps[1], snaps[#snaps]
    if not (first and first.members) then return 0 end
    local seen, everyone = {}, {}
    for _, snap in ipairs(snaps) do
        for key in pairs(snap.members or {}) do
            if not seen[key] then seen[key] = true; everyone[#everyone + 1] = key end
        end
    end
    -- The counters the loot rule feeds per raid attended, whatever the points' own switch says; the
    -- session names each entry, so two officers' clients ending the same raid give it once.
    self:EarnCounters("raid", everyone, string.format("%X", session.startTime or 0))
    if not (pool and pool.config and pool.config.autoAward) then return 0 end
    local c = pool.config
    local entries = {}
    local function give(key, amount, label, tag)
        amount = tonumber(amount) or 0
        if amount <= 0 then return end
        local op = string.format("S%X-%s-%s", session.startTime or 0, tag, key)
        if pool.appliedOps[op] then return end
        local e = self:EarnEntry(key, amount, label, "raid")
        e.op, e.ts = op, session.endTime or e.ts
        self:ApplyEntry(e); self:MarkApplied(e.op)
        entries[#entries + 1] = e
    end
    for key in pairs(seen) do
        if first.members[key] then give(key, c.onTimeAward, L["On time"], "ot")
        else give(key, c.lateAward, L["Late"], "lt") end
        if last.members[key] then give(key, c.stayedAward, L["Stayed until the end"], "st")
        else give(key, c.leftEarlyAward, L["Left early"], "le") end
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
function Points:PriceOf(itemLink)
    local c = cfg()
    local base = tonumber(c.itemCost) or 0
    local itemId = itemLink and tonumber(tostring(itemLink):match("item:(%d+)"))
    local own = itemId and type(c.itemPrices) == "table" and tonumber(c.itemPrices[itemId])
    if own then return own end
    if self:GetMode() ~= "epgp" or base <= 0 or not itemLink then return base end
    local _, _, _, ilvl, _, _, _, _, equipLoc = GuildOS.Compat.GetItemInfo(itemLink)
    local gp = base * (SLOT_GP[equipLoc or ""] or 1)
    local ref = tonumber(c.gpRefIlvl) or 0
    if ref > 0 and tonumber(ilvl) then gp = gp * 2 ^ ((ilvl - ref) / GP_ILVL_STEP) end
    return math.max(1, math.floor(gp + 0.5))
end

-- The guild's own price for one item (nil or 0 goes back to the rule). Officer only.
function Points:SetItemPrice(itemId, price)
    if not GuildOS:IsOfficer() or not tonumber(itemId) then return false end
    local c = self:GetDB().config
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
    local back = math.floor(entry * math.min(100, math.max(0, refundPct)) / 100)
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
-- pool.accounts[acct] = { rs = "night"|"lockout"|"never", per = <period>, v = { [key] = n } }
-- Every entry names the period it was made in. An entry of a newer period empties the account before
-- it adds; one of an older period is late and adds nothing, so every client ends on the same figures
-- in whatever order the entries reach it.
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
    pool = pool or self:GetDB()
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
    pool = pool or self:GetDB()
    pool.accounts = pool.accounts or {}
    local a = pool.accounts[e.acct]
    if not a or a.rs ~= e.rs then
        -- A new account, or one whose rule now resets another way: it starts over.
        a = { rs = e.rs, per = e.per, v = {} }
        pool.accounts[e.acct] = a
    elseif not samePeriod(a.rs, e.per, a.per) then
        if e.per < a.per then return false end
        a.per, a.v = e.per, {}
    end
    local n = (a.v[e.key] or 0) + e.delta
    a.v[e.key] = n > 0 and n or nil
    return true
end

-- Add `delta` (negative to give back) to `key` on the counter `acct`, which resets the way `reset`
-- says. `per` is the period of the entry being undone; nil is now. Kept here whoever awards, and told
-- to the guild when an officer does. Returns the entry, for an undo.
function Points:AddCounter(acct, key, delta, reset, per)
    local e = self:MakeEntry(key, delta, "", "counter")
    e.acct, e.rs = acct, COUNTER_RESETS[reset] and reset or "never"
    e.per = per or self:CounterPeriod(e.rs)
    if not self:ApplyCounterEntry(e) then return nil end
    self:MarkApplied(e.op)
    if GuildOS:IsOfficer() and GuildOS.SyncService then
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
    local pool = self:GetDB()
    if not (pool and pool.appliedOps) then return 0 end
    local entries = {}
    for _, a in ipairs(LR:Counters()) do
        for _, earn in ipairs(a.earn or {}) do
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
        if GuildOS.SyncService then GuildOS.SyncService:Publish("points", "cdelta", { entries = entries }) end
        self:Refresh()
    end
    return #entries
end

-- Everyone on a counter or a bonus account with something on it: { { key, name, class, value }, ... },
-- the most first. For the points window.
function Points:CounterStandings(acct, pool)
    pool = pool or self:GetDB()
    local a = pool.accounts and pool.accounts[acct]
    local list = {}
    for key in pairs(a and a.v or {}) do
        local value = self:Counter(acct, key, pool)
        if value > 0 then
            local m = GuildOS.db.members and GuildOS.db.members[key]
            list[#list + 1] = { key = key, name = key:match("^([^-]+)") or key, class = (m and m.class) or "", value = value }
        end
    end
    table.sort(list, function(x, y)
        if x.value ~= y.value then return x.value > y.value end
        return x.name:lower() < y.name:lower()
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
    pool = pool or self:GetDB()
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
    pool = pool or self:GetDB()
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
    local pool = self:GetDB()
    local q = pool.queues and pool.queues[acct]
    local e = {
        op = newOp(), acct = acct, seq = (q and q.seq or 0) + 1, list = list,
        author = GuildOS.Compat.PlayerName(), ts = GetServerTime(),
        core = GuildOS.CoreManager and GuildOS.CoreManager:GetActiveName() or "",
    }
    if not self:ApplyQueueEntry(e, pool) then return nil end
    self:MarkApplied(e.op, pool)
    if GuildOS:IsOfficer() and GuildOS.SyncService then
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

-- The accounts of a snapshot, as this client keeps them: every figure checked, every key its own.
local function localAccounts(accounts)
    local out = {}
    for acct, a in pairs(accounts) do
        if type(acct) == "string" and acct:find("^[a-z0-9]+$") and #acct <= 8 and type(a) == "table"
            and COUNTER_RESETS[a.rs] and type(a.per) == "number" and type(a.v) == "table" then
            local v = {}
            for key, n in pairs(a.v) do
                if type(key) == "string" and type(n) == "number" and n > 0 and n < math.huge then
                    key = GuildOS:LocalMemberKey(key)
                    v[key] = (v[key] or 0) + math.floor(n)
                end
            end
            out[acct] = { rs = a.rs, per = a.per, v = v }
        end
    end
    return out
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
            e.key = GuildOS:LocalMemberKey(e.key)   -- the sending officer's key, as this client's (#97)
            local pool = self:GetDBForCore(e.core)
            if e.op and not pool.appliedOps[e.op] then
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
                e.key = GuildOS:LocalMemberKey(e.key)
                local pool = self:GetDBForCore(e.core)
                if not pool.appliedOps[e.op] then
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
                local pool = self:GetDBForCore(e.core)
                if not pool.appliedOps[e.op] then
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
        local pool = self:GetDBForCore(d.core)
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
            if type(d.accounts) == "table" then pool.accounts = localAccounts(d.accounts) end
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
    if coreName == nil then coreName = GuildOS.CoreManager and GuildOS.CoreManager:GetActiveName() or "" end
    local pool  = poolOf(coreName)
    local domain = (coreName ~= "") and ("points:" .. coreName) or "points"
    local rev = GuildOS.SyncService:NextRevision(domain, "standings")
    GuildOS.SyncService:Publish("points", "snapshot", {
        core     = coreName,
        mode     = pool.mode,
        config   = pool.config,
        standings = pool.standings,
        accounts = pool.accounts,
        queues   = pool.queues,
    }, { rev = rev })
end

----------------------------------------------------------------------
-- UI refresh hook (set by the Points window when built).
----------------------------------------------------------------------
function Points:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end
