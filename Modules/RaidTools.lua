----------------------------------------------------------------------
-- Guild OS - Raid Tools
-- Composition / buff coverage / cooldown coverage for the current group
-- (or online guild members when not grouped). Business logic only.
----------------------------------------------------------------------
local RaidTools = {}
BRutus.RaidTools = RaidTools
local L = BRutus.L

-- Class display order for the composition breakdown.
RaidTools.CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

-- Key raid-wide buffs and the classes that provide them (TBC).
RaidTools.BUFFS = {
    { name = L["Stamina"],        classes = { PRIEST = true } },
    { name = L["Intellect"],      classes = { MAGE = true } },
    { name = L["Spirit"],         classes = { PRIEST = true } },
    { name = L["Stats (GotW)"],   classes = { DRUID = true } },
    { name = L["Attack Power"],    classes = { WARRIOR = true, PALADIN = true } },
    { name = L["Blessings"],      classes = { PALADIN = true } },
    { name = L["Totems"],         classes = { SHAMAN = true } },
}

-- Key raid cooldowns and their provider classes.
RaidTools.COOLDOWNS = {
    { name = L["Bloodlust/Heroism"], classes = { SHAMAN = true } },
    { name = L["Battle Rez"],        classes = { DRUID = true } },
    { name = L["Innervate"],         classes = { DRUID = true } },
    { name = L["Power Infusion"],    classes = { PRIEST = true } },
    { name = L["Misdirection"],      classes = { HUNTER = true } },
    { name = L["Soulstone"],         classes = { WARLOCK = true } },
    { name = L["Salvation"],         classes = { PALADIN = true } },
}

-- Returns (list, sourceLabel). list = { { name, class }, ... }.
-- Uses the raid/party if grouped, otherwise online guild members.
function RaidTools:GetSource()
    local list = {}
    if IsInRaid() then
        local n = GetNumGroupMembers() or 0
        for i = 1, n do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if name then
                list[#list + 1] = { name = name:match("^([^-]+)") or name, class = classFile or "" }
            end
        end
        return list, L["Current raid"]
    elseif IsInGroup() then
        local _, classFile = UnitClass("player")
        list[#list + 1] = { name = UnitName("player"), class = classFile or "" }
        for i = 1, (GetNumGroupMembers() or 1) - 1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local _, cf = UnitClass(unit)
                list[#list + 1] = { name = UnitName(unit), class = cf or "" }
            end
        end
        return list, L["Current party"]
    end
    -- Fallback: online guild members.
    local num = GetNumGuildMembers() or 0
    for i = 1, num do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and isOnline then
            list[#list + 1] = { name = name:match("^([^-]+)") or name, class = classFile or "" }
        end
    end
    return list, L["Online guild members"]
end

-- Count members per class for a source list.
function RaidTools:GetClassCounts(list)
    local counts = {}
    for _, m in ipairs(list) do
        if m.class and m.class ~= "" then
            counts[m.class] = (counts[m.class] or 0) + 1
        end
    end
    return counts
end

-- For each definition in `defs` (BUFFS or COOLDOWNS), resolve which present
-- classes provide it. Returns { { name, covered, providers = {classFile,...} }, ... }.
function RaidTools:ResolveCoverage(defs, classCounts)
    local result = {}
    for _, def in ipairs(defs) do
        local providers = {}
        for classFile in pairs(def.classes) do
            if (classCounts[classFile] or 0) > 0 then
                providers[#providers + 1] = classFile
            end
        end
        result[#result + 1] = {
            name = def.name,
            covered = #providers > 0,
            providers = providers,
        }
    end
    return result
end
