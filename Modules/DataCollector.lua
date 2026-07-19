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
    -- Cache/talent readiness events: on a cold first login the item cache and
    -- talents may not be loaded when we first collect, producing a snapshot with
    -- avgIlvl=0 / no spec. These let us correct and re-broadcast the moment the
    -- data becomes available, instead of leaving peers with a partial snapshot
    -- until the next 5-minute tick. (pcall: not all client flavors expose them.)
    pcall(function() frame:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
    pcall(function() frame:RegisterEvent("PLAYER_TALENT_UPDATE") end)
    pcall(function() frame:RegisterEvent("CHARACTER_POINTS_CHANGED") end)
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
        elseif event == "GET_ITEM_INFO_RECEIVED" or event == "PLAYER_TALENT_UPDATE"
            or event == "CHARACTER_POINTS_CHANGED" then
            -- Only react while a prior snapshot was known-incomplete (these events,
            -- GET_ITEM_INFO_RECEIVED especially, fire very frequently). Debounce so
            -- a burst of cache-fills collapses into a single refresh, and cap the
            -- attempts so an item that never resolves can't cause endless churn
            -- (the 300s ticker remains a fallback).
            if not DataCollector._snapshotIncomplete then return end
            if DataCollector._refreshPending then return end
            if (DataCollector._refreshAttempts or 0) >= 8 then return end
            DataCollector._refreshPending = true
            DataCollector._refreshAttempts = (DataCollector._refreshAttempts or 0) + 1
            C_Timer.After(1, function()
                DataCollector._refreshPending = false
                DataCollector:CollectMyData()
                -- If the snapshot is now complete, push the corrected data
                -- (force past the throttle so it isn't swallowed).
                if not DataCollector._snapshotIncomplete and BRutus.CommSystem then
                    BRutus.CommSystem:BroadcastMyData(true)
                end
            end)
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
    local gear, gearIncomplete = self:CollectGear()
    data.gear = gear
    data.avgIlvl = self:CalculateAvgIlvl(data.gear)

    -- Collect professions
    data.professions = self:CollectProfessions()

    -- Collect basic stats
    data.stats = self:CollectStats()

    -- Collect own spec (requires talents to be loaded)
    local specMissing = false
    if BRutus.SpecChecker then
        local spec = BRutus.SpecChecker:CollectOwnSpec()
        if spec then data.spec = spec else specMissing = true end
    end

    -- Collect resistance gear: the MAX wearable resistance per school from everything
    -- I own (equipped + bags), NOT just what's equipped now — so officers can see who
    -- can field a Nature/Frost/Shadow set (Hydross, Mother Shahraz...) even when it's
    -- sitting in bags. Only my OWN client can see my bags, so each player reports their
    -- own; it rides the normal member-data sync.
    data.resistances = self:CollectResistances()

    BRutus.db.members[key] = data
    BRutus.db.myData = data

    -- Flag a partial first-open snapshot (cold item cache / talents not loaded)
    -- so the cache/talent readiness events can re-collect + re-broadcast once
    -- the data resolves, rather than leaving peers with 0-ilvl / spec-less data.
    self._snapshotIncomplete = gearIncomplete or specMissing

    return data
end

----------------------------------------------------------------------
-- Collect resistance gear (max wearable per school, from equipped + bags)
--
-- We report, per school, the best set the player COULD assemble from items they
-- own: for each equip slot take the single highest-resistance item (top two for
-- rings/trinkets) and sum. Each school is computed independently, which is exactly
-- what matters in TBC — resistance is a per-fight, single-school stat (Hydross =
-- Nature/Frost, Mother Shahraz = Shadow), so nobody wears all schools at once.
--
-- Resistances are read by SCANNING THE ITEM TOOLTIP, not GetItemStats: on this
-- (Anniversary) client GetItemStats only returns armor (RESISTANCE0) + primary stats
-- and omits the magic-school resistances entirely (verified — a Fire Resistance item
-- reported only RESISTANCE0_NAME/armor). The tooltip always shows "+N Fire Resistance"
-- lines, and the localized school name comes from the RESISTANCEx_NAME global, so this
-- is locale-independent. Only carried bags (0-4) are scannable off-bank, so a
-- bank-stashed set counts only while the bank is open.
----------------------------------------------------------------------
-- Hidden tooltip used to read item resistance lines.
local resScanTip
local function ResScanTip()
    if not resScanTip then
        resScanTip = CreateFrame("GameTooltip", "GuildOSResScanTip", nil, "GameTooltipTemplate")
        resScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return resScanTip
end

-- Localized "Fire Resistance"/"Nature Resistance"/... -> our school key (2=Fire,
-- 3=Nature, 4=Frost, 5=Shadow, 6=Arcane in WoW's resistance/school order).
local resNameToSchool
local function ResNameMap()
    if resNameToSchool then
        return resNameToSchool
    end
    resNameToSchool = {}
    local idx = { fire = 2, nature = 3, frost = 4, shadow = 5, arcane = 6 }
    for school, i in pairs(idx) do
        local nm = _G["RESISTANCE" .. i .. "_NAME"]
        if nm and nm ~= "" then
            resNameToSchool[nm] = school
        end
    end
    return resNameToSchool
end

-- Resistance per school for one item, read from its tooltip ("+N Fire Resistance").
-- Returns a { school = value } table, or nil.
local function ItemResistances(link)
    local tip = ResScanTip()
    tip:ClearLines()
    if not pcall(tip.SetHyperlink, tip, link) then
        return nil
    end
    local names = ResNameMap()
    local out
    for i = 2, tip:NumLines() do
        local fs = _G["GuildOSResScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            for nm, school in pairs(names) do
                if text:find(nm, 1, true) then
                    local n = tonumber(text:match("%d+"))
                    if n and n > 0 then
                        out = out or {}
                        out[school] = math.max(out[school] or 0, n)
                    end
                end
            end
        end
    end
    return out
end

-- How many of each equip bucket a character can wear at once.
local RES_BUCKET_CAP = {
    Head = 1, Neck = 1, Shoulder = 1, Back = 1, Chest = 1, Wrist = 1, Hands = 1,
    Waist = 1, Legs = 1, Feet = 1, Finger = 2, Trinket = 2,
    MainHand = 1, OffHand = 1, Ranged = 1,
}
local RES_LOC_TO_BUCKET = {
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_CLOAK = "Back", INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest",
    INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "MainHand", INVTYPE_WEAPONMAINHAND = "MainHand", INVTYPE_2HWEAPON = "MainHand",
    INVTYPE_WEAPONOFFHAND = "OffHand", INVTYPE_SHIELD = "OffHand", INVTYPE_HOLDABLE = "OffHand",
    INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Ranged",
    INVTYPE_RELIC = "Ranged",
}

function DataCollector:CollectResistances()
    -- Gather every candidate item link: equipped slots + carried bags.
    local links = {}
    for _, slotInfo in ipairs(BRutus.SlotIDs) do
        local l = GetInventoryItemLink("player", slotInfo.id)
        if l then links[#links + 1] = l end
    end
    for bag = 0, 4 do
        local n = (C_Container and C_Container.GetContainerNumSlots
            and C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local l = C_Container and C_Container.GetContainerItemLink
                and C_Container.GetContainerItemLink(bag, slot)
            if l then links[#links + 1] = l end
        end
    end

    -- pool[bucket][school] = list of resistance values seen for that slot bucket.
    local pool = {}
    for _, link in ipairs(links) do
        local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
        local bucket = equipLoc and RES_LOC_TO_BUCKET[equipLoc]
        if bucket then
            local itemRes = ItemResistances(link)
            if itemRes then
                for school, v in pairs(itemRes) do
                    if v > 0 then
                        pool[bucket] = pool[bucket] or {}
                        pool[bucket][school] = pool[bucket][school] or {}
                        local list = pool[bucket][school]
                        list[#list + 1] = v
                    end
                end
            end
        end
    end

    -- Sum the top-N (N = bucket capacity) per bucket, per school.
    local res = { fire = 0, nature = 0, frost = 0, shadow = 0, arcane = 0 }
    for bucket, cap in pairs(RES_BUCKET_CAP) do
        local schools = pool[bucket]
        if schools then
            for school, list in pairs(schools) do
                table.sort(list, function(a, b) return a > b end)
                for i = 1, math.min(cap, #list) do
                    res[school] = res[school] + list[i]
                end
            end
        end
    end
    return res
end

----------------------------------------------------------------------
-- Collect equipped gear
----------------------------------------------------------------------
-- Returns (gear, incomplete). `incomplete` is true when an equipped slot has a
-- link but GetItemInfo has not resolved it yet (cold item cache) — the caller
-- uses this to schedule a corrective re-collect once the cache fills.
function DataCollector:CollectGear()
    local gear = {}
    local incomplete = false

    for _, slotInfo in ipairs(BRutus.SlotIDs) do
        local slotId = slotInfo.id
        local itemLink = GetInventoryItemLink("player", slotId)

        if itemLink then
            local itemName, _, itemQuality, itemLevel, _, _, _, _, _, _ = GetItemInfo(itemLink)
            if not itemName or not itemLevel or itemLevel == 0 then
                incomplete = true  -- item not in cache yet; name/ilvl unresolved
            end
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

    return gear, incomplete
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

    -- Include self-declared roles (the player's own preference; the Raider
    -- Roster shows these unless an officer overrides). Merged generically by
    -- StoreReceivedData into db.members[key].prefRoles.
    if BRutus.db.profile and BRutus.db.profile.prefRoles then
        clean.prefRoles = BRutus.db.profile.prefRoles
    end

    -- Include resistance gear (small { fire,nature,frost,shadow,arcane } table).
    -- StoreReceivedData merges every key generically, so the receiver stores it too.
    if myData.resistances then
        clean.resistances = myData.resistances
    end

    -- Include recipes (keyed by profession)
    local myKey = BRutus:GetPlayerKey(myData.name, myData.realm or GetRealmName())
    if BRutus.db.recipes and BRutus.db.recipes[myKey] then
        clean.recipes = BRutus.db.recipes[myKey]
    end

    return clean
end
