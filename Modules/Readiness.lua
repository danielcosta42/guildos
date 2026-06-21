----------------------------------------------------------------------
-- Guild OS - Raid Readiness
-- Pure aggregator: answers "is this member ready to raid?" by combining
-- data that other modules already collect/sync — attunements, missing
-- enchants, item level, and (when checked in raid) consumables.
-- No new sync, no persistence. Business logic only (Rule 2 / Rule 10).
----------------------------------------------------------------------
local Readiness = {}
BRutus.Readiness = Readiness

-- Status ranking for sorting (most actionable first).
local STATUS_RANK = { notready = 0, warn = 1, ready = 2, nodata = 3 }

----------------------------------------------------------------------
-- Raids you can target a readiness check at (the quest-attunement raids).
-- Returns { { short, name, tier }, ... } or {}.
----------------------------------------------------------------------
function Readiness:GetTargets()
    if not BRutus.AttunementTracker then return {} end
    return BRutus.AttunementTracker:GetGuildColumns()
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
    if BRutus.GearAudit then
        for _, r in ipairs(BRutus.GearAudit:GetGuildEnchantAudit()) do
            enchantByKey[r.key] = r
        end
    end

    -- Index the last consumable check by lowercase short name (live, in-raid).
    local consumeByName = {}
    if BRutus.ConsumableChecker then
        for _, res in pairs(BRutus.ConsumableChecker:GetLastResults() or {}) do
            local short = (res.name or ""):match("^([^-]+)") or res.name
            if short and short ~= "" then consumeByName[short:lower()] = res end
        end
    end

    local rows = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local m = BRutus.db.members[key]

            -- Attunement progress (account-wide effective).
            local attDone, attTotal, targetOk = 0, 0, nil
            if BRutus.AttunementTracker then
                local atts = BRutus.AttunementTracker:GetEffectiveAttunements(key)
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

            -- Consumables (nil = never checked / not in raid).
            local cres = consumeByName[short:lower()]
            local missCons = cres and #cres.missing or nil

            local ilvl = (m and m.avgIlvl) or 0

            local status
            if targetShort and targetOk == false then
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
                ilvl = ilvl, hasGear = hasGear,
                attDone = attDone, attTotal = attTotal, targetOk = targetOk,
                missEnch = missEnch, missCons = missCons,
                status = status,
            }
        end
    end

    table.sort(rows, function(a, b)
        local ra, rb = STATUS_RANK[a.status] or 9, STATUS_RANK[b.status] or 9
        if ra ~= rb then return ra < rb end
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
