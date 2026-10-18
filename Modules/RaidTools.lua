----------------------------------------------------------------------
-- Guild OS - Raid Tools
-- Composition / buff coverage / cooldown coverage for the current group
-- (or online guild members when not grouped). Business logic only.
----------------------------------------------------------------------
local RaidTools = {}
GuildOS.RaidTools = RaidTools
local L = GuildOS.L

-- Class display order for the composition breakdown: this game's classes (thirteen on retail).
RaidTools.CLASS_ORDER = GuildOS.Client.classes

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
    { name = L["Bloodlust/Heroism"], classes = { SHAMAN = true }, tbc = true },  -- TBC spells (ADR-0014)
    { name = L["Battle Rez"],        classes = { DRUID = true } },
    { name = L["Innervate"],         classes = { DRUID = true } },
    { name = L["Power Infusion"],    classes = { PRIEST = true } },
    { name = L["Misdirection"],      classes = { HUNTER = true }, tbc = true },
    { name = L["Soulstone"],         classes = { WARLOCK = true } },
    { name = L["Salvation"],         classes = { PALADIN = true } },
}

-- Retail's (Midnight, ADR-0026): one class per raid buff, and the cooldowns several classes share.
-- `spell` names the entry in the reader's language; `name` is the fallback while the client has no
-- name for it. Checked against build 12.1.5.70448's SpellName.
if GuildOS.Client.isRetail then
    RaidTools.BUFFS = {
        { spell = 21562,  name = "Power Word: Fortitude",  classes = { PRIEST = true } },
        { spell = 1459,   name = "Arcane Intellect",       classes = { MAGE = true } },
        { spell = 1126,   name = "Mark of the Wild",       classes = { DRUID = true } },
        { spell = 6673,   name = "Battle Shout",           classes = { WARRIOR = true } },
        { spell = 462854, name = "Skyfury",                classes = { SHAMAN = true } },
        { spell = 364342, name = "Blessing of the Bronze", classes = { EVOKER = true } },
        { spell = 8647,   name = "Mystic Touch",           classes = { MONK = true } },
        { spell = 1490,   name = "Chaos Brand",            classes = { DEMONHUNTER = true } },
        { spell = 257284, name = "Hunter's Mark",          classes = { HUNTER = true } },
        { spell = 465,    name = "Devotion Aura",          classes = { PALADIN = true } },
    }
    RaidTools.COOLDOWNS = {
        { spell = 2825,  name = "Bloodlust",      classes = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true } },
        { spell = 20484, name = "Rebirth",        classes = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true } },
        { spell = 29166, name = "Innervate",      classes = { DRUID = true } },
        { spell = 10060, name = "Power Infusion", classes = { PRIEST = true } },
        { spell = 20707, name = "Soulstone",      classes = { WARLOCK = true } },
    }
end

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
        list[#list + 1] = { name = GuildOS.Compat.PlayerName(), class = classFile or "" }
        for i = 1, (GetNumGroupMembers() or 1) - 1 do
            local unit = "party" .. i
            local nm, _, cf
            if UnitExists(unit) then nm, _, cf = GuildOS.Compat.UnitIdentity(unit) end
            if nm then
                list[#list + 1] = { name = nm, class = cf or "" }
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
        if not def.tbc or GuildOS.Client.isAnniversary then  -- TBC-only spells stay off other clients (ADR-0014)
            local providers = {}
            for classFile in pairs(def.classes) do
                if (classCounts[classFile] or 0) > 0 then
                    providers[#providers + 1] = classFile
                end
            end
            result[#result + 1] = {
                name = (def.spell and GuildOS.Compat.GetSpellInfo(def.spell)) or def.name,
                covered = #providers > 0,
                providers = providers,
            }
        end
    end
    return result
end
