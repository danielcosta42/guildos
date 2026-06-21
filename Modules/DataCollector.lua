----------------------------------------------------------------------
-- BRutus Guild Manager - Data Collector
-- Collects gear, professions, and stats from the local player
-- and stores data received from other guild members
----------------------------------------------------------------------
local DataCollector = {}
BRutus.DataCollector = DataCollector

function DataCollector:Initialize()
    -- Register inventory change events
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
    frame:RegisterEvent("CHAT_MSG_SKILL")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            C_Timer.After(0.5, function()
                DataCollector:CollectMyData()
                -- Broadcast updated gear to guild after a short delay
                C_Timer.After(2, function()
                    if BRutus.CommSystem then
                        BRutus.CommSystem:BroadcastMyData()
                    end
                end)
            end)
        elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
            C_Timer.After(1, function() DataCollector:CollectProfessions() end)
        end
    end)
end

----------------------------------------------------------------------
-- Collect all local player data
----------------------------------------------------------------------
function DataCollector:CollectMyData()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = BRutus:GetPlayerKey(name, realm)

    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local race = UnitRace("player") or ""

    local data = BRutus.db.members[key] or {}
    data.name = name
    data.realm = realm
    data.class = class
    data.level = level
    data.race = race
    data.lastUpdate = time()

    -- Collect gear
    data.gear = self:CollectGear()
    data.avgIlvl = self:CalculateAvgIlvl(data.gear)

    -- Collect professions
    data.professions = self:CollectProfessions()

    -- Collect basic stats
    data.stats = self:CollectStats()

    -- Collect own spec (requires talents to be loaded)
    if BRutus.SpecChecker then
        local spec = BRutus.SpecChecker:CollectOwnSpec()
        if spec then data.spec = spec end
    end

    BRutus.db.members[key] = data
    BRutus.db.myData = data

    return data
end

----------------------------------------------------------------------
-- Collect equipped gear
----------------------------------------------------------------------
function DataCollector:CollectGear()
    local gear = {}

    for _, slotInfo in ipairs(BRutus.SlotIDs) do
        local slotId = slotInfo.id
        local itemLink = GetInventoryItemLink("player", slotId)

        if itemLink then
            local itemName, _, itemQuality, itemLevel, _, _, _, _, _, _ = GetItemInfo(itemLink)
            local itemId = tonumber(itemLink:match("item:(%d+)"))

            -- Parse enchant and gems from the item link
            -- TBC format: item:itemId:enchantId:gem1:gem2:gem3:gem4:suffixId:uniqueId:...
            local enchantId, gems = self:ParseItemLink(itemLink)

            gear[slotId] = {
                link = itemLink,
                id = itemId,
                name = itemName or "",
                quality = itemQuality or 0,
                ilvl = itemLevel or 0,
                enchantId = enchantId,
                gems = gems,
            }
        else
            gear[slotId] = nil
        end
    end

    return gear
end

----------------------------------------------------------------------
-- Parse enchant and gem IDs from an item link
----------------------------------------------------------------------
function DataCollector:ParseItemLink(link)
    if not link then return nil, {} end

    -- item:itemId:enchantId:gem1:gem2:gem3:gem4:suffixId:uniqueId:...
    local parts = { strsplit(":", link:match("item:([%d:-]+)") or "") }
    local enchantId = tonumber(parts[2]) or 0
    local gems = {}

    for i = 3, 5 do
        local gemId = tonumber(parts[i]) or 0
        if gemId > 0 then
            tinsert(gems, { id = gemId })
        end
    end

    return enchantId > 0 and enchantId or nil, gems
end

----------------------------------------------------------------------
-- Get enchant display name from enchant ID
-- Uses tooltip scanning as the only reliable method in Classic
----------------------------------------------------------------------
local ENCHANT_CACHE = {}

function DataCollector:GetEnchantName(enchantId)
    if not enchantId or enchantId == 0 then return nil end
    if ENCHANT_CACHE[enchantId] then return ENCHANT_CACHE[enchantId] end

    -- Build a fake item link with just the enchant to scan the tooltip
    -- Use a common white-quality item (Linen Cloth = 2589) as base
    local fakeLink = string.format("|cffffffff|Hitem:2589:%d:0:0:0:0:0:0:0|h[Scan]|h|r", enchantId)
    local tip = BRutus.scanTooltip
    if not tip then
        tip = CreateFrame("GameTooltip", "BRutusScanTooltip", nil, "GameTooltipTemplate")
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        BRutus.scanTooltip = tip
    end
    tip:ClearLines()
    tip:SetHyperlink(fakeLink)

    -- The enchant name appears on lines after the item name, look for green text
    for i = 2, tip:NumLines() do
        local line = _G["BRutusScanTooltipTextLeft" .. i]
        if line then
            local r, g, b = line:GetTextColor()
            -- Green text = enchant lines (r~0, g~1, b~0)
            if g > 0.8 and r < 0.2 and b < 0.2 then
                local text = line:GetText()
                if text and text ~= "" then
                    ENCHANT_CACHE[enchantId] = text
                    return text
                end
            end
        end
    end

    return nil
end

----------------------------------------------------------------------
-- Calculate average item level
----------------------------------------------------------------------
function DataCollector:CalculateAvgIlvl(gear)
    if not gear then return 0 end

    local total = 0
    local count = 0

    for _, slotInfo in ipairs(BRutus.SlotIDs) do
        local item = gear[slotInfo.id]
        if item and item.ilvl and item.ilvl > 0 then
            total = total + item.ilvl
            count = count + 1
        end
    end

    if count == 0 then return 0 end
    return math.floor(total / count + 0.5)
end

----------------------------------------------------------------------
-- Collect professions
----------------------------------------------------------------------
function DataCollector:CollectProfessions()
    local profs = {}

    -- Get primary professions
    local numSkills = GetNumSkillLines()

    for i = 1, numSkills do
        local skillName, isHeader_, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)

        -- Check if it's a profession (locale-independent)
        if not isHeader_ and self:IsProfession(skillName) then
            table.insert(profs, {
                name = self:GetCanonicalProfName(skillName),
                rank = skillRank,
                maxRank = skillMaxRank,
                isPrimary = self:IsPrimaryProfession(skillName),
            })
        end
    end

    return profs
end

----------------------------------------------------------------------
-- Profession helpers (locale-independent via hardcoded multi-locale map)
----------------------------------------------------------------------

-- Maps ANY localized profession name -> { canonical, isPrimary }
local PROF_LOOKUP = {}

local function RegisterProf(canonical, isPrimary, names, isGathering)
    for _, name in ipairs(names) do
        PROF_LOOKUP[name] = { canonical = canonical, isPrimary = isPrimary, isGathering = isGathering or false }
    end
end

-- English, Portuguese (BR), Spanish, French, German, Russian, Korean, Chinese
RegisterProf("Alchemy", true, {
    "Alchemy", "Alquimia", "Alchimie", "Alchemie",
})
RegisterProf("Blacksmithing", true, {
    "Blacksmithing", "Ferraria", "Herrería", "Forge", "Schmiedekunst",
})
RegisterProf("Enchanting", true, {
    "Enchanting", "Encantamento", "Encantamiento", "Enchantement", "Verzauberkunst",
})
RegisterProf("Engineering", true, {
    "Engineering", "Engenharia", "Ingeniería", "Ingénierie", "Ingenieurskunst",
})
RegisterProf("Herbalism", true, {
    "Herbalism", "Herborismo", "Herboristería", "Herboristerie", "Kräuterkunde",
}, true)
RegisterProf("Jewelcrafting", true, {
    "Jewelcrafting", "Joalheria", "Joyería", "Joaillerie", "Juwelenschleifen",
})
RegisterProf("Leatherworking", true, {
    "Leatherworking", "Couraria", "Peletería", "Travail du cuir", "Lederverarbeitung",
})
RegisterProf("Mining", true, {
    "Mining", "Mineração", "Minería", "Minage", "Bergbau",
}, true)
RegisterProf("Skinning", true, {
    "Skinning", "Esfolamento", "Desuello", "Dépeçage", "Kürschnerei",
}, true)
RegisterProf("Tailoring", true, {
    "Tailoring", "Alfaiataria", "Sastrería", "Couture", "Schneiderei",
})
RegisterProf("Cooking", false, {
    "Cooking", "Culinária", "Cocina", "Cuisine", "Kochkunst",
})
RegisterProf("First Aid", false, {
    "First Aid", "Primeiros Socorros", "Primeros auxilios", "Secourisme", "Erste Hilfe",
})
RegisterProf("Fishing", false, {
    "Fishing", "Pesca", "Pêche", "Angeln",
}, true)
RegisterProf("Poisons", false, {
    "Poisons", "Venenos", "Venins", "Gifte",
}, true)

function DataCollector:IsProfession(name)
    return PROF_LOOKUP[name] ~= nil
end

function DataCollector:IsPrimaryProfession(name)
    local info = PROF_LOOKUP[name]
    return info and info.isPrimary or false
end

function DataCollector:GetCanonicalProfName(localizedName)
    local info = PROF_LOOKUP[localizedName]
    return info and info.canonical or localizedName
end

function DataCollector:IsKnownProfession(name)
    return PROF_LOOKUP[name] ~= nil
end

function DataCollector:IsGatheringProfession(name)
    local info = PROF_LOOKUP[name]
    return info and info.isGathering or false
end

----------------------------------------------------------------------
-- Collect basic stats
----------------------------------------------------------------------
function DataCollector:CollectStats()
    local stats = {}
    stats.health = UnitHealthMax("player")
    stats.mana = UnitPowerMax("player", 0) -- Mana

    -- Base stats
    stats.strength  = UnitStat("player", 1) or 0
    stats.agility   = UnitStat("player", 2) or 0
    stats.stamina   = UnitStat("player", 3) or 0
    stats.intellect = UnitStat("player", 4) or 0
    stats.spirit    = UnitStat("player", 5) or 0

    return stats
end

----------------------------------------------------------------------
-- Store data received from another player
----------------------------------------------------------------------
function DataCollector:StoreReceivedData(playerKey, data)
    if not data or type(data) ~= "table" then return end
    if not data.name or not data.class then return end

    -- Timestamp check: skip if incoming data is older than what we have
    local existing = BRutus.db.members[playerKey] or {}
    if existing.lastUpdate and data.lastUpdate and data.lastUpdate < existing.lastUpdate then
        return
    end

    -- Snapshot prior state for milestone detection BEFORE the merge mutates
    -- `existing`. hadPrior is false on the very first sync of a member, so
    -- milestones don't fire for everyone on the initial data exchange.
    local prevLevel = existing.level
    local hadPrior = prevLevel ~= nil
    local prevAttune = 0
    if existing.attunements then
        for _, a in ipairs(existing.attunements) do
            if a.complete then prevAttune = prevAttune + 1 end
        end
    end

    -- Merge with existing data (skip recipes, handled separately)
    for k, v in pairs(data) do
        if k ~= "recipes" then
            existing[k] = v
        end
    end
    existing.lastSync = time()

    BRutus.db.members[playerKey] = existing

    if BRutus.Milestones then
        BRutus.Milestones:Check(playerKey, existing, prevLevel, prevAttune, hadPrior)
    end

    -- Store recipes if included in broadcast
    if data.recipes then
        if not BRutus.db.recipes then BRutus.db.recipes = {} end
        if not BRutus.db.recipes[playerKey] then BRutus.db.recipes[playerKey] = {} end
        local DC = BRutus.DataCollector
        for profName, recipes in pairs(data.recipes) do
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
            -- Remove old localized keys that map to the same canonical profession
            for oldKey, _ in pairs(BRutus.db.recipes[playerKey]) do
                if oldKey ~= canonical and DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(oldKey) == canonical then
                    BRutus.db.recipes[playerKey][oldKey] = nil
                end
            end
            -- Preserve spellIds: merge from existing data into incoming
            -- (same player = same locale, names match)
            if BRutus.RecipeTracker then
                BRutus.RecipeTracker:MergeSpellIds(BRutus.db.recipes[playerKey][canonical], recipes)
            end
            BRutus.db.recipes[playerKey][canonical] = recipes
        end
    end

    -- Update trial snapshots if this player is a trial
    if BRutus.TrialTracker then
        BRutus.TrialTracker:UpdateSnapshots()
    end

    -- Refresh UI if open
    if BRutus.RosterFrame and BRutus.RosterFrame:IsShown() then
        BRutus.RosterFrame:RefreshRoster()
    end
end

----------------------------------------------------------------------
-- Get serializable data for broadcasting
----------------------------------------------------------------------
function DataCollector:GetBroadcastData()
    local myData = BRutus.db.myData
    if not myData then
        myData = self:CollectMyData()
    end

    -- Create a clean copy without item links (too long for comms)
    local clean = {
        name = myData.name,
        realm = myData.realm,
        class = myData.class,
        level = myData.level,
        race = myData.race,
        avgIlvl = myData.avgIlvl,
        lastUpdate = myData.lastUpdate,
        professions = myData.professions,
        stats = myData.stats,
        addonVersion = BRutus.VERSION,
    }

    -- Serialize gear with just essential info
    if myData.gear then
        clean.gear = {}
        for slotId, item in pairs(myData.gear) do
            local gearEntry = {
                id = item.id,
                name = item.name,
                quality = item.quality,
                ilvl = item.ilvl,
                enchantId = item.enchantId,
            }
            if item.gems and #item.gems > 0 then
                gearEntry.gems = {}
                for _, gem in ipairs(item.gems) do
                    tinsert(gearEntry.gems, { id = gem.id })
                end
            end
            clean.gear[slotId] = gearEntry
        end
    end

    -- Include attunements
    if myData.attunements then
        clean.attunements = myData.attunements
    end

    -- Include talent spec
    if myData.spec then
        clean.spec = myData.spec
    end

    -- Include recipes (keyed by profession)
    local myKey = BRutus:GetPlayerKey(myData.name, myData.realm or GetRealmName())
    if BRutus.db.recipes and BRutus.db.recipes[myKey] then
        clean.recipes = BRutus.db.recipes[myKey]
    end

    return clean
end
