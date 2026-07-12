----------------------------------------------------------------------
-- Guild OS - Resistances
-- Aggregates the per-member resistance-gear data that DataCollector scans
-- (max wearable per school, from equipped + bags) into a guild overview for
-- the raid resistance fights. Business logic only, no UI (Rule 2 / Rule 10).
--
-- Resistance in TBC is a per-fight, single-school stat, so we track each school
-- independently and judge it against that school's headline encounter:
--   Shadow -> Mother Shahraz (raid-wide)   Nature/Frost -> Hydross (tanks)
--   Fire   -> Leotheras demon phase        Arcane -> Solarian
----------------------------------------------------------------------
local Resistances = {}
BRutus.Resistances = Resistances
local L = BRutus.L

-- Display order (most impactful first). `target` = a solid raid-member set for that
-- school (guidance, not a hard cap); `fight` = the encounter that drives it. Colours
-- are the school's flavour colour, used for the column headers.
Resistances.SCHOOLS = {
    { key = "shadow", label = L["Shadow"], r = 0.80, g = 0.40, b = 1.00, target = 174, fight = L["Mother Shahraz"] },
    { key = "nature", label = L["Nature"], r = 0.36, g = 0.83, b = 0.36, target = 150, fight = L["Hydross"] },
    { key = "frost",  label = L["Frost"],  r = 0.41, g = 0.80, b = 1.00, target = 150, fight = L["Hydross"] },
    { key = "fire",   label = L["Fire"],   r = 1.00, g = 0.48, b = 0.27, target = 100, fight = L["Leotheras"] },
    { key = "arcane", label = L["Arcane"], r = 0.85, g = 0.55, b = 1.00, target = 75,  fight = L["Solarian"] },
}

-- Rate a value against a school's target set: "ready" (has a solid set),
-- "partial" (halfway there), "low" (a few pieces), "none" (nothing).
function Resistances:Tier(value, target)
    value = value or 0
    if value <= 0 then return "none" end
    if value >= target then return "ready" end
    if value >= (target * 0.5) then return "partial" end
    return "low"
end

-- Grid rows: every member we hold resistance data for (i.e. Guild OS users who've
-- scanned), sorted by name. Each: { key, name, class, res = {fire,nature,frost,
-- shadow,arcane} }. A member with the addon but no resistance gear still shows
-- (all zeros) so an officer can see who is missing a set, not just who has one.
function Resistances:GetRows()
    local rows = {}
    if not BRutus.db or not BRutus.db.members then
        return rows
    end
    for key, m in pairs(BRutus.db.members) do
        if type(m) == "table" and m.name and type(m.resistances) == "table" then
            rows[#rows + 1] = { key = key, name = m.name, class = m.class, res = m.resistances }
        end
    end
    table.sort(rows, function(a, b) return (a.name or "") < (b.name or "") end)
    return rows
end

-- How many members have a solid set for a given school (for a header count).
function Resistances:CountReady(schoolKey, target)
    local n = 0
    for _, r in ipairs(self:GetRows()) do
        if (r.res[schoolKey] or 0) >= target then n = n + 1 end
    end
    return n
end
