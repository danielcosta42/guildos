----------------------------------------------------------------------
-- Guild OS - Raid Readiness
-- Pure aggregator: answers "is this member ready to raid?" by combining
-- data that other modules already collect/sync — attunements, missing
-- enchants, item level, and (when checked in raid) consumables.
-- No new sync, no persistence. Business logic only (Rule 2 / Rule 10).
----------------------------------------------------------------------
local Readiness = {}
GuildOS.Readiness = Readiness

-- Status ranking for sorting (most actionable first).
local STATUS_RANK = { notready = 0, warn = 1, ready = 2, nodata = 3 }

-- WoW: Forever has no attunements: the door to a raid is level 60 (issue #206, guildos.me #238).
local FOREVER = not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail
local MIN_ILVL_MAX = 1000
local STAMP_FUTURE_SLACK = 300   -- seconds an officer's stamp may run ahead of this clock, as the rank's

-- The raids that open on 9 December 2026, 00:00 UTC until the hour is known (guildos.me #241).
Readiness.FOREVER_RAIDS = {
    { key = "barrow-deeps", name = "Barrow Deeps", size = 10, opensAt = 1796774400 },
    { key = "hyjal", name = "Hyjal Summit", size = 20, opensAt = 1796774400 },
    { key = "onyxia", name = "Onyxia's Lair", size = 40, opensAt = 1796774400 },
}

local SHOWN_AFTER_OPEN = 7 * 86400   -- "the raids are open" stays a week, then the card goes
local CORES_SHOWN = 3
local RAID_SIZES = { 10, 20, 40 }
local DUNGEON_GROUP = 5
Readiness.DUNGEON_GROUP = DUNGEON_GROUP

----------------------------------------------------------------------
-- What the guild can form with who is at the cap, the same slices as guildos.me's: so many dungeon
-- groups, so many raids of each size. They do not add up: each says how many the whole guild makes.
-- Before the first raid, `short` says how many more for the next first thing, of `shortSize`. Pure.
----------------------------------------------------------------------
function Readiness.Slices(atCap)
    local s = { dungeons = math.floor(atCap / DUNGEON_GROUP), raids = {} }
    for _, size in ipairs(RAID_SIZES) do
        local count = math.floor(atCap / size)
        if count > 0 then s.raids[#s.raids + 1] = { size = size, count = count } end
    end
    if #s.raids == 0 then
        s.shortSize = atCap < DUNGEON_GROUP and DUNGEON_GROUP or RAID_SIZES[1]
        s.short = s.shortSize - atCap
    end
    return s
end

----------------------------------------------------------------------
-- The countdown to the raids on WoW: Forever (issue #207), from a report's rows: how many days, how
-- many of each core are at the cap (its titulars; up to three cores, largest first), how many of the
-- guild, and me. Nil off Forever, and a week after the raids opened.
-- Business logic only: UI/Dashboard.lua draws it.
----------------------------------------------------------------------
function Readiness:Countdown(rows, now)
    if not FOREVER then return nil end
    local target
    for _, r in ipairs(Readiness.FOREVER_RAIDS) do
        if now < r.opensAt + SHOWN_AFTER_OPEN and (not target or r.opensAt < target.opensAt) then target = r end
    end
    if not target then return nil end

    local cap = GuildOS.Client.maxLevel
    -- The guild roster's levels: somebody on a core who left the guild counts nowhere.
    local levelOf, atCap = {}, 0
    for _, r in ipairs(rows or {}) do
        levelOf[r.key] = r.level or 0
        if (r.level or 0) >= cap then atCap = atCap + 1 end
    end

    local cores = {}
    local CM = GuildOS.CoreManager
    for name, core in pairs(CM and CM:GetAll() or {}) do
        local ready = 0
        for key, rec in pairs(core.members or {}) do
            local main = type(rec) ~= "table" or rec.status ~= "bench"
            if main and (levelOf[GuildOS:LocalMemberKey(key)] or 0) >= cap then ready = ready + 1 end
        end
        cores[#cores + 1] = { name = name, size = CM:GetRaidSize(name), ready = ready }
    end
    table.sort(cores, function(a, b)
        if a.size ~= b.size then return a.size > b.size end
        return a.name < b.name
    end)
    while #cores > CORES_SHOWN do table.remove(cores) end

    local me
    local myKey = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
    for _, r in ipairs(rows or {}) do
        if r.key == myKey then me = r break end
    end

    return {
        opensAt = target.opensAt,
        open = now >= target.opensAt,
        -- Whole days left, rounded down as guildos.me counts them ("36d 04h" is 36): 0 is the last day.
        days = math.max(0, math.floor((target.opensAt - now) / 86400)),
        cap = cap,
        cores = cores,
        guild = { ready = atCap, slices = Readiness.Slices(atCap) },
        me = me,
    }
end

----------------------------------------------------------------------
-- A member's readiness on WoW: Forever, the same rule and the same cases as guildos.me's:
--   below the cap: not ready (the level);
--   no gear data (never published): ready, by level only — the door is public, nobody is
--     punished on the board for not running the addon;
--   under the guild's minimum item level, or an enchant missing: ready, with a warning.
-- `r` = { level, hasGear, ilvl, missEnch }. Returns status, reason, levelOnly. Pure.
----------------------------------------------------------------------
function Readiness.ForeverStatus(r, minIlvl, cap)
    if (r.level or 0) < cap then return "notready", "level", false end
    if not r.hasGear then return "ready", nil, true end
    if minIlvl and (r.ilvl or 0) < minIlvl then return "warn", "ilvl", false end
    if (r.missEnch or 0) > 0 then return "warn", "enchants", false end
    return "ready", nil, false
end

----------------------------------------------------------------------
-- The guild's minimum item level for a 60 (issue #206): an officer's, stamped, the newest stamp
-- winning on every client, as the officer threshold is (#81). Nil: no minimum.
----------------------------------------------------------------------
function Readiness:GetMinIlvl()
    local s = GuildOS.db and GuildOS.db.settings
    return s and s.readyMinIlvl or nil
end

-- Whether this client has heard the guild's minimum at all (set, cleared, or from an officer).
function Readiness:MinIlvlKnown()
    local s = GuildOS.db and GuildOS.db.settings
    return s ~= nil and s.readyMinIlvlAt ~= nil
end

local function sane(n)
    return n == nil or (type(n) == "number" and n == math.floor(n) and n >= 1 and n <= MIN_ILVL_MAX)
end

-- An officer sets it; nil or 0 clears it. Returns whether it was taken.
function Readiness:SetMinIlvl(n)
    if n == 0 then n = nil end
    if not FOREVER or not GuildOS:IsOfficer() or not sane(n) then return false end
    local s = GuildOS.db.settings
    s.readyMinIlvl = n
    s.readyMinIlvlAt = math.max(GetServerTime(), (s.readyMinIlvlAt or 0) + 1)
    self:PublishMinIlvl()
    return true
end

-- To the guild: when it changes, and again on the officers' regular sync, for a client that missed it.
function Readiness:PublishMinIlvl()
    if not FOREVER then return end
    local s = GuildOS.db and GuildOS.db.settings
    if not (s and s.readyMinIlvlAt and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    GuildOS.SyncService:Publish("guildcfg", "readymin", { min = s.readyMinIlvl }, { rev = s.readyMinIlvlAt })
end

-- From an officer (SyncService checked the officer and GUILD): the newest stamp wins, and two in the
-- same second settle on the lower minimum on every client.
function Readiness:OnMinIlvlSync(env)
    if not FOREVER then return end
    local data = env and env.data
    local min = type(data) == "table" and data.min or nil
    local at = env and tonumber(env.rev)
    if not sane(min) or not (at and at > 0 and at < math.huge) then return end
    at = math.min(at, GetServerTime() + STAMP_FUTURE_SLACK)
    local s = GuildOS.db.settings
    local held = s.readyMinIlvlAt
    if held and (at < held or (at == held and (min or 0) >= (s.readyMinIlvl or 0))) then return end
    s.readyMinIlvl, s.readyMinIlvlAt = min, at
end

----------------------------------------------------------------------
-- Raids you can target a readiness check at (the quest-attunement raids).
-- Returns { { short, name, tier }, ... } or {}.
----------------------------------------------------------------------
function Readiness:GetTargets()
    if not GuildOS.AttunementTracker then return {} end
    return GuildOS.AttunementTracker:GetGuildColumns()
end

----------------------------------------------------------------------
-- Build the readiness report for the whole guild roster.
-- `targetShort` (optional) is a raid short code (e.g. "BT"); when given,
-- members not attuned for that raid are flagged "notready".
-- Each row:
--   { name, key, class, online, ilvl, hasGear,
--     attDone, attTotal, targetOk(bool|nil),
--     missEnch(number), missCons(number|nil),
--     status = "ready"|"warn"|"notready"|"nodata" }
----------------------------------------------------------------------
function Readiness:GetReport(targetShort)
    -- Index missing-enchant data by player key (rows include 0-missing too).
    local enchantByKey = {}
    if GuildOS.GearAudit then
        for _, r in ipairs(GuildOS.GearAudit:GetGuildEnchantAudit()) do
            enchantByKey[r.key] = r
        end
    end

    -- Index the last consumable check by player key, and by lowercase short name (live, in-raid).
    -- On retail by the key alone: two namesakes on connected realms are two raiders (issue #187).
    local consumeByName, consumeByKey = {}, {}
    if GuildOS.ConsumableChecker then
        for key, res in pairs(GuildOS.ConsumableChecker:GetLastResults() or {}) do
            local short = (res.name or ""):match("^([^-]+)") or res.name
            if short and short ~= "" then consumeByName[short:lower()] = res end
            consumeByKey[res.playerKey or key] = res
        end
    end

    local rows = {}
    local minIlvl, cap = self:GetMinIlvl(), GuildOS.Client.maxLevel
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = GuildOS:GetPlayerKey(short, realm)
            local m = GuildOS.db.members[key]

            -- Attunement progress (account-wide effective).
            local attDone, attTotal, targetOk = 0, 0, nil
            if GuildOS.AttunementTracker then
                local atts = GuildOS.AttunementTracker:GetEffectiveAttunements(key)
                attTotal = #atts
                for _, a in ipairs(atts) do
                    if a.complete then attDone = attDone + 1 end
                    if targetShort and a.short == targetShort then
                        targetOk = a.complete and true or false
                    end
                end
            end

            -- Missing enchants (nil row = no synced gear).
            local er = enchantByKey[key]
            local hasGear = er ~= nil
            local missEnch = (er and er.missingCount) or 0

            -- Consumables (nil = never checked / not in raid / nothing the client could read: on retail
            -- unknown is never missing, issue #187).
            local cres = consumeByKey[key]
            if not cres and not GuildOS.Client.isRetail then cres = consumeByName[short:lower()] end
            local missCons = cres and #cres.missing or nil
            if missCons == 0 and not next(cres.buffs or {}) then missCons = nil end

            local ilvl = (m and m.avgIlvl) or 0

            local status, reason, levelOnly
            if FOREVER then
                status, reason, levelOnly = Readiness.ForeverStatus(
                    { level = level, hasGear = hasGear, ilvl = ilvl, missEnch = missEnch }, minIlvl, cap)
            elseif targetShort and targetOk == false then
                status = "notready"
            elseif (missEnch > 0) or (missCons and missCons > 0) then
                status = "warn"
            elseif not hasGear and attTotal == 0 then
                status = "nodata"
            else
                status = "ready"
            end

            rows[#rows + 1] = {
                name = short, key = key, class = classFile or "", online = isOnline,
                level = level or 0, ilvl = ilvl, hasGear = hasGear,
                attDone = attDone, attTotal = attTotal, targetOk = targetOk,
                missEnch = missEnch, missCons = missCons,
                status = status, reason = reason, levelOnly = levelOnly or false,
            }
        end
    end

    table.sort(rows, function(a, b)
        local ra, rb = STATUS_RANK[a.status] or 9, STATUS_RANK[b.status] or 9
        if ra ~= rb then return ra < rb end
        -- On Forever, the closest to the door first within a status (issue #207).
        if FOREVER and a.level ~= b.level then return a.level > b.level end
        return a.name:lower() < b.name:lower()
    end)
    return rows
end

----------------------------------------------------------------------
-- Aggregate counts for a report (or a freshly built one).
-- Returns counts table: { ready, warn, notready, nodata, total }.
----------------------------------------------------------------------
function Readiness:Summarize(rows)
    rows = rows or self:GetReport()
    local c = { ready = 0, warn = 0, notready = 0, nodata = 0, total = #rows }
    for _, r in ipairs(rows) do
        c[r.status] = (c[r.status] or 0) + 1
    end
    return c
end
