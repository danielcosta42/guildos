----------------------------------------------------------------------
-- BRutus Guild Manager - Recipe Tracker
-- Scans and shares tradeskill recipes across the guild
----------------------------------------------------------------------
local RecipeTracker = {}
BRutus.RecipeTracker = RecipeTracker
local L = BRutus.L

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function RecipeTracker:Initialize()
    self.scanPending = false
    self.lastScanTime = {}

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("TRADE_SKILL_SHOW")
    -- Craft API event (Enchanting in some clients)
    frame:RegisterEvent("CRAFT_SHOW")
    frame:SetScript("OnEvent", function(_, event)
        if event == "TRADE_SKILL_SHOW" then
            RecipeTracker:DebounceScan("trade")
        elseif event == "CRAFT_SHOW" then
            RecipeTracker:DebounceScan("craft")
        end
    end)

    -- Ensure DB table exists
    if not BRutus.db.recipes then
        BRutus.db.recipes = {}
    end

    -- Enrich stored recipes: propagate spellIds from players who have them
    -- to same-locale players who don't (same name = same locale)
    self:EnrichStoredRecipes()

    -- Hook tooltips to show crafters
    self:HookTooltips()
end

----------------------------------------------------------------------
-- Clean stored recipe data: enrich where possible, purge the rest.
-- Recipes without spellId AND without itemId are old locale-dependent
-- data that cause cross-locale duplication. After enrichment attempts,
-- any remaining ID-less entries are removed. The data will be
-- repopulated with proper IDs on the next scan or sync.
----------------------------------------------------------------------
function RecipeTracker:EnrichStoredRecipes()
    -- Phase 1: Build name→spellId per profession from ALL recipes that have spellId
    local profLookup = {} -- profName → { lowerName → spellId }

    for _, professions in pairs(BRutus.db.recipes or {}) do
        for profName, recipes in pairs(professions) do
            if not profLookup[profName] then profLookup[profName] = {} end
            for _, r in ipairs(recipes) do
                if r.spellId then
                    if r.name then
                        profLookup[profName][strlower(r.name)] = r.spellId
                    end
                    local localName = GetSpellInfo(r.spellId)
                    if localName and localName ~= "" then
                        profLookup[profName][strlower(localName)] = r.spellId
                    end
                end
            end
        end
    end

    -- Phase 2: Enrich where possible, then purge remaining ID-less entries
    local enriched = 0
    local purged = 0
    for _, professions in pairs(BRutus.db.recipes or {}) do
        for profName, recipes in pairs(professions) do
            local lookup = profLookup[profName]
            -- Reverse iterate so we can remove in-place
            for i = #recipes, 1, -1 do
                local r = recipes[i]
                -- Try to enrich first
                if not r.spellId and r.name and lookup then
                    local sid = lookup[strlower(r.name)]
                    if sid then
                        r.spellId = sid
                        enriched = enriched + 1
                    end
                end
                -- Purge if still no ID
                if not r.spellId and not r.itemId then
                    table.remove(recipes, i)
                    purged = purged + 1
                end
            end
        end
    end

    if enriched > 0 then
        BRutus:Print(format(L["|cff00ff00Recipes:|r enriched %d entries with IDs."], enriched))
    end
    if purged > 0 then
        BRutus:Print(format(L["|cffFFD700Recipes:|r purged %d old entries without IDs. They will be restored on next scan/sync."], purged))
    end
end

----------------------------------------------------------------------
-- Helper: merge spellIds from existing recipes into incoming recipes.
-- Same player = same locale, so names match.
-- Also uses cross-player lookup as fallback.
----------------------------------------------------------------------
function RecipeTracker:MergeSpellIds(existing, incoming)
    if not existing or not incoming then return end

    -- Build name→spellId from existing data
    local lookup = {}
    for _, r in ipairs(existing) do
        if r.name then
            if r.spellId then
                lookup[strlower(r.name)] = r.spellId
            end
        end
    end

    -- Enrich incoming
    for _, r in ipairs(incoming) do
        if not r.spellId and r.name then
            local sid = lookup[strlower(r.name)]
            if sid then
                r.spellId = sid
            end
        end
    end
end

local SCAN_COOLDOWN = 5 -- seconds between scans of the same type

function RecipeTracker:DebounceScan(scanType)
    local now = GetTime()
    if self.lastScanTime[scanType] and (now - self.lastScanTime[scanType]) < SCAN_COOLDOWN then
        return
    end
    self.lastScanTime[scanType] = now

    C_Timer.After(0.3, function()
        if scanType == "trade" then
            RecipeTracker:ScanTradeSkill()
        elseif scanType == "craft" then
            RecipeTracker:ScanCraft()
        end
    end)
end

----------------------------------------------------------------------
-- Scan the currently open TradeSkill window
----------------------------------------------------------------------
function RecipeTracker:ScanTradeSkill()
    if not GetTradeSkillLine then return end

    local rawSkillName = GetTradeSkillLine()
    if not rawSkillName or rawSkillName == "" or rawSkillName == "UNKNOWN" then return end

    local skillName = BRutus.DataCollector:GetCanonicalProfName(rawSkillName)

    local numSkills = GetNumTradeSkills and GetNumTradeSkills() or 0
    if numSkills == 0 then return end

    local recipes = {}
    for i = 1, numSkills do
        local name, skillType = GetTradeSkillInfo(i)
        -- skillType: "header"/"subheader" = category, otherwise it's a recipe
        if name and skillType ~= "header" and skillType ~= "subheader" then
            local itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
            local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
            local itemId
            if itemLink then
                itemId = tonumber(itemLink:match("item:(%d+)"))
            end
            local spellId
            if recipeLink then
                spellId = tonumber(recipeLink:match("enchant:(%d+)") or recipeLink:match("spell:(%d+)"))
            end
            -- Fallback: extract enchant ID from item link if it's an enchant link
            if not spellId and itemLink then
                spellId = tonumber(itemLink:match("enchant:(%d+)"))
            end
            table.insert(recipes, {
                name = name,
                itemId = itemId,
                spellId = spellId,
            })
        end
    end

    self:StoreMyRecipes(skillName, recipes)
end

----------------------------------------------------------------------
-- Scan Craft window (Enchanting in some TBC clients)
----------------------------------------------------------------------
function RecipeTracker:ScanCraft()
    if not GetCraftDisplaySkillLine then return end

    local rawSkillName = GetCraftDisplaySkillLine()
    if not rawSkillName or rawSkillName == "" or rawSkillName == "UNKNOWN" then return end

    local skillName = BRutus.DataCollector:GetCanonicalProfName(rawSkillName)

    local numCrafts = GetNumCrafts and GetNumCrafts() or 0
    if numCrafts == 0 then return end

    local recipes = {}
    for i = 1, numCrafts do
        local name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" and craftType ~= "subheader" then
            local itemLink = GetCraftItemLink and GetCraftItemLink(i)
            local spellLink = GetCraftSpellLink and GetCraftSpellLink(i)
            local itemId
            if itemLink then
                itemId = tonumber(itemLink:match("item:(%d+)"))
            end
            local spellId
            -- Try spell link first
            if spellLink then
                spellId = tonumber(spellLink:match("enchant:(%d+)") or spellLink:match("spell:(%d+)"))
            end
            -- Enchanting: GetCraftItemLink returns enchant:XXXXX, extract as spellId
            if not spellId and itemLink then
                spellId = tonumber(itemLink:match("enchant:(%d+)"))
            end
            table.insert(recipes, {
                name = name,
                itemId = itemId,
                spellId = spellId,
            })
        end
    end

    self:StoreMyRecipes(skillName, recipes)
end

----------------------------------------------------------------------
-- Store scanned recipes for local player
----------------------------------------------------------------------
function RecipeTracker:StoreMyRecipes(profName, recipes)
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = BRutus:GetPlayerKey(name, realm)

    if not BRutus.db.recipes[key] then
        BRutus.db.recipes[key] = {}
    end

    -- Remove old localized keys that map to the same canonical profession
    local DC = BRutus.DataCollector
    if DC and DC.GetCanonicalProfName then
        for oldKey, _ in pairs(BRutus.db.recipes[key]) do
            if oldKey ~= profName and DC:GetCanonicalProfName(oldKey) == profName then
                BRutus.db.recipes[key][oldKey] = nil
            end
        end
    end

    BRutus.db.recipes[key][profName] = recipes

    -- Track scan timestamps per profession
    if not BRutus.db.recipeScanTimes then
        BRutus.db.recipeScanTimes = {}
    end
    BRutus.db.recipeScanTimes[profName] = time()

    BRutus:Print(string.format(L["|cff00ff00Recipes scanned:|r %d %s recipes indexed."], #recipes, profName))

    -- Dismiss the profession reminder if all professions are now scanned
    if BRutus.profReminderFrame then
        BRutus:CheckAndDismissProfessionReminder()
    end

    -- Broadcast to guild
    self:BroadcastRecipes(profName, recipes)
end

----------------------------------------------------------------------
-- Broadcast recipes via CommSystem
----------------------------------------------------------------------
function RecipeTracker:BroadcastRecipes(profName, recipes)
    if not BRutus.CommSystem then return end
    if not IsInGuild() then return end

    local LibSerialize = LibStub("LibSerialize")
    local data = {
        prof = profName,
        recipes = recipes,
    }
    local serialized = LibSerialize:Serialize(data)
    BRutus.CommSystem:SendMessage("RC", serialized)
end

----------------------------------------------------------------------
-- Handle incoming recipe data from another guild member
----------------------------------------------------------------------
function RecipeTracker:HandleIncoming(sender, data)
    local LibSerialize = LibStub("LibSerialize")
    local ok, recipeData = LibSerialize:Deserialize(data)
    if not ok or type(recipeData) ~= "table" then return end

    local profName = recipeData.prof
    local recipes = recipeData.recipes
    if not profName or not recipes then return end

    -- Normalize profession name to canonical English
    local DC = BRutus.DataCollector
    if DC and DC.GetCanonicalProfName then
        profName = DC:GetCanonicalProfName(profName)
    end

    -- Build player key from sender
    local senderName = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = BRutus:GetPlayerKey(senderName, realm)

    if not BRutus.db.recipes[key] then
        BRutus.db.recipes[key] = {}
    end

    -- Remove old localized keys that map to the same canonical profession
    for oldKey, _ in pairs(BRutus.db.recipes[key]) do
        if oldKey ~= profName and DC and DC:GetCanonicalProfName(oldKey) == profName then
            BRutus.db.recipes[key][oldKey] = nil
        end
    end

    -- Preserve spellIds: merge from existing data into incoming
    self:MergeSpellIds(BRutus.db.recipes[key][profName], recipes)

    BRutus.db.recipes[key][profName] = recipes
end

----------------------------------------------------------------------
-- Get all known professions across the guild
----------------------------------------------------------------------
function RecipeTracker:GetAllProfessions()
    local profs = {}
    local seen = {}
    local DC = BRutus.DataCollector
    for _, playerRecipes in pairs(BRutus.db.recipes or {}) do
        for profName, _ in pairs(playerRecipes) do
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
            local isGathering = DC and DC.IsGatheringProfession and DC:IsGatheringProfession(canonical)
            local isKnown = not DC or not DC.IsKnownProfession or DC:IsKnownProfession(canonical)
            if not seen[canonical] and not isGathering and isKnown then
                seen[canonical] = true
                table.insert(profs, canonical)
            end
        end
    end
    table.sort(profs)
    return profs
end

----------------------------------------------------------------------
-- Build a flat searchable list of all recipes (grouped by ID)
-- Groups by spellId or itemId to be locale-independent.
-- Resolves display name via GetSpellInfo/GetItemInfo for the local client.
----------------------------------------------------------------------
function RecipeTracker:BuildRecipeIndex()
    local grouped = {}
    local DC = BRutus.DataCollector

    -- nameToKey: maps "name|prof" → recipeKey for recipes that have IDs
    -- Stores both the original sender name and the locally resolved name
    -- so name-only recipes from ANY locale can find a match.
    local nameToKey = {}

    local function addCrafter(recipeKey, playerKey, playerName)
        if not grouped[recipeKey]._crafterSeen[playerKey] then
            grouped[recipeKey]._crafterSeen[playerKey] = true
            table.insert(grouped[recipeKey].crafters, {
                playerKey = playerKey,
                playerName = playerName,
            })
        end
    end

    -- First pass: group all recipes; build name→key lookup from ID-based entries
    local nameOnlyQueue = {}
    for playerKey, professions in pairs(BRutus.db.recipes or {}) do
        local playerName = playerKey:match("^([^-]+)") or playerKey
        for profName, recipes in pairs(professions) do
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
            -- Skip gathering profs and unknown profs (e.g. Poisons, old stale data)
            local isGathering = DC and DC.IsGatheringProfession and DC:IsGatheringProfession(canonical)
            local isKnown = not DC or not DC.IsKnownProfession or DC:IsKnownProfession(canonical)
            if not isGathering and isKnown then
            for _, recipe in ipairs(recipes) do
                local recipeKey
                if recipe.spellId then
                    recipeKey = "s" .. recipe.spellId .. "|" .. canonical
                elseif recipe.itemId then
                    recipeKey = "i" .. recipe.itemId .. "|" .. canonical
                end

                if recipeKey then
                    -- ID-based recipe
                    if not grouped[recipeKey] then
                        local displayName = recipe.name
                        if recipe.spellId then
                            local spellName = GetSpellInfo(recipe.spellId)
                            if spellName and spellName ~= "" then
                                displayName = spellName
                            end
                        end
                        if recipe.itemId and (not displayName or displayName == recipe.name) then
                            local itemName = GetItemInfo(recipe.itemId)
                            if itemName and itemName ~= "" then
                                displayName = itemName
                            end
                        end

                        grouped[recipeKey] = {
                            name = displayName or recipe.name or "?",
                            itemId = recipe.itemId,
                            spellId = recipe.spellId,
                            profName = canonical,
                            crafters = {},
                            _crafterSeen = {},
                        }

                        -- Map both the original name and the resolved name to this key
                        if recipe.name then
                            nameToKey[strlower(recipe.name) .. "|" .. canonical] = recipeKey
                        end
                        if displayName and displayName ~= recipe.name then
                            nameToKey[strlower(displayName) .. "|" .. canonical] = recipeKey
                        end
                    else
                        -- Entry exists; register additional name variants
                        if recipe.name then
                            nameToKey[strlower(recipe.name) .. "|" .. canonical] = recipeKey
                        end
                    end
                    addCrafter(recipeKey, playerKey, playerName)
                else
                    -- No ID — queue for second pass
                    table.insert(nameOnlyQueue, {
                        recipe = recipe,
                        playerKey = playerKey,
                        playerName = playerName,
                        canonical = canonical,
                    })
                end
            end
            end -- if not isGathering and isKnown
        end
    end

    -- Second pass: merge name-only recipes into ID-based groups when possible.
    -- If no ID match exists, SKIP the recipe entirely — name-only entries from
    -- other locales cause duplication and cannot be reliably deduplicated.
    for _, entry in ipairs(nameOnlyQueue) do
        local recipe = entry.recipe
        local canonical = entry.canonical
        local lookupKey = strlower(recipe.name or "") .. "|" .. canonical
        local recipeKey = nameToKey[lookupKey]

        if recipeKey then
            addCrafter(recipeKey, entry.playerKey, entry.playerName)
        end
        -- else: skip — this recipe has no ID and no name match; it would cause dupes
    end

    -- Third pass: merge remaining entries that share the same display name + profession
    local byDisplayKey = {}
    local mergeTargets = {}
    for key, entry in pairs(grouped) do
        local displayKey = strlower(entry.name or "") .. "|" .. (entry.profName or "")
        if byDisplayKey[displayKey] then
            local target = byDisplayKey[displayKey]
            for _, crafter in ipairs(entry.crafters) do
                if not grouped[target]._crafterSeen[crafter.playerKey] then
                    grouped[target]._crafterSeen[crafter.playerKey] = true
                    table.insert(grouped[target].crafters, crafter)
                end
            end
            if not grouped[target].spellId and entry.spellId then
                grouped[target].spellId = entry.spellId
            end
            if not grouped[target].itemId and entry.itemId then
                grouped[target].itemId = entry.itemId
            end
            mergeTargets[key] = true
        else
            byDisplayKey[displayKey] = key
        end
    end
    for key in pairs(mergeTargets) do
        grouped[key] = nil
    end

    local index = {}
    for _, entry in pairs(grouped) do
        entry._crafterSeen = nil
        table.insert(index, entry)
    end
    return index
end

----------------------------------------------------------------------
-- Search recipes by query, optional profession filter
-- Returns results sorted: online first, then by recipe name
----------------------------------------------------------------------
function RecipeTracker:Search(query, profFilter)
    local index = self:BuildRecipeIndex()
    local results = {}
    local lowerQuery = query and strlower(strtrim(query)) or ""

    -- Build online set from guild roster
    local onlineSet = self:GetOnlineSet()

    for _, entry in ipairs(index) do
        local passProf = (not profFilter or profFilter == "All" or entry.profName == profFilter)
        local passQuery = true
        if lowerQuery ~= "" then
            passQuery = strlower(entry.name):find(lowerQuery, 1, true) ~= nil
        end

        if passProf and passQuery then
            -- Mark which crafters are online
            local hasOnline = false
            for _, crafter in ipairs(entry.crafters) do
                crafter.isOnline = onlineSet[crafter.playerName] or false
                if crafter.isOnline then hasOnline = true end
            end
            -- Sort crafters: online first, then alphabetical
            table.sort(entry.crafters, function(a, b)
                if a.isOnline ~= b.isOnline then return a.isOnline end
                return a.playerName < b.playerName
            end)
            entry.hasOnline = hasOnline
            table.insert(results, entry)
        end
    end

    -- Sort: recipes with online crafters first, then by name
    table.sort(results, function(a, b)
        if a.hasOnline ~= b.hasOnline then return a.hasOnline end
        return a.name < b.name
    end)

    return results
end

----------------------------------------------------------------------
-- Build a set of online guild member names
----------------------------------------------------------------------
function RecipeTracker:GetOnlineSet()
    local set = {}
    local numMembers = GetNumGuildMembers() or 0
    for i = 1, numMembers do
        local fullName, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if fullName and isOnline then
            local shortName = fullName:match("^([^-]+)") or fullName
            set[shortName] = true
        end
    end
    return set
end

----------------------------------------------------------------------
-- Build cached itemId → crafters and spellId → crafters lookups
----------------------------------------------------------------------
function RecipeTracker:BuildItemCrafterIndex()
    local itemIndex = {}
    local spellIndex = {}
    local DC = BRutus.DataCollector
    for playerKey, professions in pairs(BRutus.db.recipes or {}) do
        local playerName = playerKey:match("^([^-]+)") or playerKey
        for profName, recipes in pairs(professions) do
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
            local memberData = BRutus.db and BRutus.db.members and BRutus.db.members[playerKey]
            local crafterInfo = {
                playerKey = playerKey,
                playerName = playerName,
                class = memberData and memberData.class,
                profName = canonical,
            }
            for _, recipe in ipairs(recipes) do
                if recipe.itemId then
                    if not itemIndex[recipe.itemId] then
                        itemIndex[recipe.itemId] = {}
                    end
                    local found = false
                    for _, c in ipairs(itemIndex[recipe.itemId]) do
                        if c.playerKey == playerKey then found = true break end
                    end
                    if not found then
                        table.insert(itemIndex[recipe.itemId], crafterInfo)
                    end
                end
                if recipe.spellId then
                    if not spellIndex[recipe.spellId] then
                        spellIndex[recipe.spellId] = {}
                    end
                    local found = false
                    for _, c in ipairs(spellIndex[recipe.spellId]) do
                        if c.playerKey == playerKey then found = true break end
                    end
                    if not found then
                        table.insert(spellIndex[recipe.spellId], crafterInfo)
                    end
                end
            end
        end
    end
    self._itemCrafterIndex = itemIndex
    self._spellCrafterIndex = spellIndex
    self._itemCrafterIndexTime = GetTime()
    return itemIndex
end

function RecipeTracker:GetCraftersForItem(itemId)
    if not itemId then return nil end
    -- Rebuild cache every 30 seconds
    if not self._itemCrafterIndex or not self._itemCrafterIndexTime
       or (GetTime() - self._itemCrafterIndexTime) > 30 then
        self:BuildItemCrafterIndex()
    end
    local crafters = self._itemCrafterIndex[itemId]
    if not crafters or #crafters == 0 then return nil end
    return crafters
end

function RecipeTracker:GetCraftersForSpell(spellId)
    if not spellId then return nil end
    -- Rebuild cache every 30 seconds
    if not self._spellCrafterIndex or not self._itemCrafterIndexTime
       or (GetTime() - self._itemCrafterIndexTime) > 30 then
        self:BuildItemCrafterIndex()
    end
    local crafters = self._spellCrafterIndex[spellId]
    if not crafters or #crafters == 0 then return nil end
    return crafters
end

----------------------------------------------------------------------
-- Can the LOCAL player craft this item? Returns the profession name if so,
-- else nil. Reads only our own scanned recipes (db.recipes[myKey]) — used to
-- answer realm-wide CraftNet queries authoritatively for ourselves.
----------------------------------------------------------------------
function RecipeTracker:LocalCrafts(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    local key = BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
    local professions = BRutus.db and BRutus.db.recipes and BRutus.db.recipes[key]
    if not professions then return nil end
    for profName, recipes in pairs(professions) do
        for _, r in ipairs(recipes) do
            if r.itemId == itemId then
                return profName
            end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Hook GameTooltip to show crafters for items
----------------------------------------------------------------------
function RecipeTracker:HookTooltips()
    local C = BRutus.Colors
    local onlineSet

    -- Shared: append crafter lines to a tooltip
    local function AppendCrafters(tooltip, crafters, label)
        if not crafters then return end

        -- Refresh online set (cached per tooltip show)
        if not onlineSet then
            onlineSet = RecipeTracker:GetOnlineSet()
        end

        -- Sort: online first, then alphabetical
        local sorted = {}
        for _, c in ipairs(crafters) do
            table.insert(sorted, c)
        end
        table.sort(sorted, function(a, b)
            local aOn = onlineSet[a.playerName] and 1 or 0
            local bOn = onlineSet[b.playerName] and 1 or 0
            if aOn ~= bOn then return aOn > bOn end
            return a.playerName < b.playerName
        end)

        tooltip:AddLine(" ")
        tooltip:AddLine(label or L["Crafted by:"], C.accent.r, C.accent.g, C.accent.b)
        for _, c in ipairs(sorted) do
            local cc = c.class and BRutus.ClassColors[c.class] or C.white
            local status = onlineSet[c.playerName] and L[" |cff00ff00(online)|r"] or L[" |cff666666(offline)|r"]
            tooltip:AddDoubleLine("  " .. c.playerName .. status, c.profName, cc.r, cc.g, cc.b, 0.6, 0.6, 0.6)
        end

        tooltip:Show()
    end

    -- Item tooltip handler
    local function OnTooltipSetItem(tooltip)
        if not BRutus.db or not BRutus.db.recipes then return end

        local _, link = tooltip:GetItem()
        if not link then return end

        local itemId = tonumber(link:match("item:(%d+)"))
        if not itemId then return end

        local crafters = RecipeTracker:GetCraftersForItem(itemId)
        AppendCrafters(tooltip, crafters, L["Crafted by:"])
    end

    -- Spell tooltip handler (tradeskill window, spellbook, action bars)
    local function OnTooltipSetSpell(tooltip)
        if not BRutus.db or not BRutus.db.recipes then return end

        local _, spellId = tooltip:GetSpell()
        if not spellId then return end

        local crafters = RecipeTracker:GetCraftersForSpell(spellId)
        AppendCrafters(tooltip, crafters, L["Enchanted by:"])
    end

    -- Clear online cache when tooltip hides
    GameTooltip:HookScript("OnTooltipCleared", function()
        onlineSet = nil
    end)

    -- Item hooks
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ShoppingTooltip1 then
        ShoppingTooltip1:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ShoppingTooltip2 then
        ShoppingTooltip2:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end

    -- Spell/enchant hooks: OnTooltipSetSpell fires for both tradeskill hover AND
    -- enchant: hyperlinks, so no need for a separate SetHyperlink hook.
    GameTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
    end
end
