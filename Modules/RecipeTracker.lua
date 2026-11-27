----------------------------------------------------------------------
-- Guild OS - Recipe Tracker
-- Scans and shares tradeskill recipes across the guild
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local RecipeTracker = {}
GuildOS.RecipeTracker = RecipeTracker
local L = GuildOS.L

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function RecipeTracker:Initialize()
    self.scanPending = false
    self.lastScanTime = {}

    local frame = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(frame, "TRADE_SKILL_SHOW")
    -- The old craft window (Enchanting in some clients). A client built without
    -- it — Forever runs the retail tradeskill UI — never fires this.
    GuildOS.Compat.RegisterEvent(frame, "CRAFT_SHOW", true)
    frame:SetScript("OnEvent", function(_, event)
        if event == "TRADE_SKILL_SHOW" then
            RecipeTracker:DebounceScan("trade")
        elseif event == "CRAFT_SHOW" then
            RecipeTracker:DebounceScan("craft")
        end
    end)

    -- Ensure DB table exists
    if not GuildOS.db.recipes then
        GuildOS.db.recipes = {}
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

    for _, professions in pairs(GuildOS.db.recipes or {}) do
        for profName, recipes in pairs(professions) do
            if not profLookup[profName] then profLookup[profName] = {} end
            for _, r in ipairs(recipes) do
                if r.spellId then
                    if r.name then
                        profLookup[profName][strlower(r.name)] = r.spellId
                    end
                    local localName = GuildOS.Compat.GetSpellInfo(r.spellId)
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
    for _, professions in pairs(GuildOS.db.recipes or {}) do
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
        GuildOS:Print(format(L["|cff00ff00Recipes:|r enriched %d entries with IDs."], enriched))
    end
    if purged > 0 then
        GuildOS:Print(format(L["|cffFFD700Recipes:|r purged %d old entries without IDs. They will be restored on next scan/sync."], purged))
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

    local skillName = GuildOS.DataCollector:GetCanonicalProfName(rawSkillName)

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
            if itemId then self:KeepReagents(itemId, i) end
        end
    end

    self:StoreMyRecipes(skillName, recipes)
end

-- What a recipe of the open tradeskill window needs, kept on this character only (craft orders,
-- issue #389: the crafter tells the order's author). Anniversary's catalog has no reagents.
local MAX_REAGENTS = 8
function RecipeTracker:KeepReagents(itemId, index)
    if not (GetTradeSkillNumReagents and GetTradeSkillReagentInfo and GetTradeSkillReagentItemLink) then return end
    local n = tonumber(GetTradeSkillNumReagents(index)) or 0
    if n == 0 then return end
    local flat = {}
    for j = 1, math.min(n, MAX_REAGENTS) do
        local _, _, count = GetTradeSkillReagentInfo(index, j)
        local link = GetTradeSkillReagentItemLink(index, j)
        local id = link and tonumber(link:match("item:(%d+)"))
        if not (id and tonumber(count)) then return end   -- not loaded yet: the next scan has it
        flat[#flat + 1] = id
        flat[#flat + 1] = tonumber(count)
    end
    GuildOS.db.craftReagents = GuildOS.db.craftReagents or {}
    GuildOS.db.craftReagents[itemId] = flat
    -- How many one craft makes (ammo, some reagents make several): the least it promises.
    local made = GetTradeSkillNumMade and tonumber((GetTradeSkillNumMade(index)))
    GuildOS.db.craftYield = GuildOS.db.craftYield or {}
    GuildOS.db.craftYield[itemId] = (made and made >= 1) and math.floor(made) or nil
end

----------------------------------------------------------------------
-- Scan Craft window (Enchanting in some TBC clients)
----------------------------------------------------------------------
function RecipeTracker:ScanCraft()
    -- WoW: Forever has no Craft frame at all: the whole family is absent.
    if not GetCraftDisplaySkillLine or not GetCraftInfo then return end

    local rawSkillName = GetCraftDisplaySkillLine()
    if not rawSkillName or rawSkillName == "" or rawSkillName == "UNKNOWN" then return end

    local skillName = GuildOS.DataCollector:GetCanonicalProfName(rawSkillName)

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
    local name = GuildOS.Compat.PlayerName()
    local realm = GetRealmName()
    local key = GuildOS:GetPlayerKey(name, realm)

    if not GuildOS.db.recipes[key] then
        GuildOS.db.recipes[key] = {}
    end

    -- Remove old localized keys that map to the same canonical profession
    local DC = GuildOS.DataCollector
    if DC and DC.GetCanonicalProfName then
        for oldKey, _ in pairs(GuildOS.db.recipes[key]) do
            if oldKey ~= profName and DC:GetCanonicalProfName(oldKey) == profName then
                GuildOS.db.recipes[key][oldKey] = nil
            end
        end
    end

    local old = GuildOS.db.recipes[key][profName]
    GuildOS.db.recipes[key][profName] = recipes

    -- Track scan timestamps per profession
    if not GuildOS.db.recipeScanTimes then
        GuildOS.db.recipeScanTimes = {}
    end
    GuildOS.db.recipeScanTimes[profName] = time()

    -- Every opening of the window used to print and send the whole list (audit D3): a line only when the
    -- count moved, and the list to the guild only when it changed.
    if not old or #old ~= #recipes then
        GuildOS:Print(string.format(L["|cff00ff00Recipes scanned:|r %d %s recipes indexed."], #recipes, L[profName]))
    end
    local changed = not old or RecipeTracker.Hash(old) ~= RecipeTracker.Hash(recipes)

    -- Dismiss the profession reminder if all professions are now scanned
    if GuildOS.profReminderFrame then
        GuildOS:CheckAndDismissProfessionReminder()
    end

    -- Broadcast to guild
    if changed then self:BroadcastRecipes(profName, recipes) end
end

----------------------------------------------------------------------
-- Recipes by hash (audit D3). The member broadcast carries one hash per profession of my lists; a
-- guildmate whose copy hashes differently asks for that list by whisper ("RA"), and I answer once on
-- GUILD for everybody who asked within ASK_GATHER seconds. A list goes when it changes or is asked for,
-- never on a timer.
----------------------------------------------------------------------
RecipeTracker.ASK_GATHER = 3      -- seconds asks for one list are gathered before it goes out
RecipeTracker.ANSWER_GAP = 60     -- seconds between two answers with the same list
RecipeTracker.REASK_AFTER = 120   -- seconds before a list that never came is asked for again
RecipeTracker.MAX_PROFS = 16      -- professions read from one broadcast's hashes
local hashOf = setmetatable({}, { __mode = "k" })   -- [recipe list] = { h = its hash, n = its length }

-- Adler-32 of the recipes' names, sorted: the same list hashes the same on every client of one locale,
-- whatever spell IDs a receiver merged in (MergeSpellIds keeps the names).
function RecipeTracker.Hash(recipes)
    if type(recipes) ~= "table" then return nil end
    local held = hashOf[recipes]
    if held and held.n == #recipes then return held.h end
    local names = {}
    for _, r in ipairs(recipes) do
        if type(r) == "table" then names[#names + 1] = tostring(r.name or r.spellId or r.itemId or "") end
    end
    table.sort(names)
    local h = LibStub("LibDeflate"):Adler32(table.concat(names, "\n"))
    hashOf[recipes] = { h = h, n = #recipes }
    return h
end

-- { [profession] = hash } of my own lists, or nil when I have none.
function RecipeTracker:OwnHashes()
    local key = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
    local mine = GuildOS.db.recipes and GuildOS.db.recipes[key]
    if type(mine) ~= "table" then return nil end
    local out
    for prof, list in pairs(mine) do
        local h = self.Hash(list)
        if h then
            out = out or {}
            out[prof] = h
        end
    end
    return out
end

-- A guildmate's hashes, from their broadcast: each list held differently (or not at all) is asked for.
function RecipeTracker:OnHashes(key, sender, rh)
    self._asked = self._asked or {}
    local held = GuildOS.db.recipes and GuildOS.db.recipes[key]
    local DC, n, now = GuildOS.DataCollector, 0, GetTime()
    for prof, h in pairs(rh) do
        n = n + 1
        if n > self.MAX_PROFS then break end
        if type(prof) == "string" and type(h) == "number" then
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(prof) or prof
            local list = held and held[canonical]
            local id = key .. "\0" .. canonical
            local last = self._asked[id]
            if (not list or self.Hash(list) ~= h) and not (last and last.h == h and now - last.at < self.REASK_AFTER) then
                self._asked[id] = { h = h, at = now }
                GuildOS.CommSystem:SendMessage("RA", prof, sender)
            end
        end
    end
end

-- A guildmate asked for my list of `prof`: it goes on GUILD once the asks of the next seconds are in.
function RecipeTracker:OnAsk(_sender, prof)
    if type(prof) ~= "string" or not IsInGuild() then return end
    local key = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
    local list = GuildOS.db.recipes and GuildOS.db.recipes[key] and GuildOS.db.recipes[key][prof]
    if type(list) ~= "table" then return end
    self._answerDue = self._answerDue or {}
    self._answeredAt = self._answeredAt or {}
    if self._answerDue[prof] then return end
    local last = self._answeredAt[prof]
    local wait = self.ASK_GATHER
    if last then wait = math.max(wait, last + self.ANSWER_GAP - GetTime()) end
    self._answerDue[prof] = true
    GuildOS.Compat.After(wait, function()
        self._answerDue[prof], self._answeredAt[prof] = nil, GetTime()
        local now = GuildOS.db.recipes and GuildOS.db.recipes[key] and GuildOS.db.recipes[key][prof]
        if type(now) == "table" then self:BroadcastRecipes(prof, now) end
    end)
end

----------------------------------------------------------------------
-- Broadcast recipes via CommSystem
----------------------------------------------------------------------
function RecipeTracker:BroadcastRecipes(profName, recipes)
    if not GuildOS.CommSystem then return end
    if not IsInGuild() then return end

    local LibSerialize = LibStub("GuildOS-LibSerialize")
    local data = {
        prof = profName,
        recipes = recipes,
    }
    local serialized = LibSerialize:Serialize(data)
    GuildOS.CommSystem:SendMessage("RC", serialized)
end

----------------------------------------------------------------------
-- Handle incoming recipe data from another guild member
----------------------------------------------------------------------
function RecipeTracker:HandleIncoming(sender, data)
    local LibSerialize = LibStub("GuildOS-LibSerialize")
    local ok, recipeData = LibSerialize:Deserialize(data)
    if not ok or type(recipeData) ~= "table" then return end

    local profName = recipeData.prof
    local recipes = recipeData.recipes
    if not profName or not recipes then return end

    -- Normalize profession name to canonical English
    local DC = GuildOS.DataCollector
    if DC and DC.GetCanonicalProfName then
        profName = DC:GetCanonicalProfName(profName)
    end

    -- Build player key from sender
    local senderName = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = GuildOS:GetPlayerKey(senderName, realm)

    if not GuildOS.db.recipes[key] then
        GuildOS.db.recipes[key] = {}
    end

    -- Remove old localized keys that map to the same canonical profession
    for oldKey, _ in pairs(GuildOS.db.recipes[key]) do
        if oldKey ~= profName and DC and DC:GetCanonicalProfName(oldKey) == profName then
            GuildOS.db.recipes[key][oldKey] = nil
        end
    end

    -- Preserve spellIds: merge from existing data into incoming
    self:MergeSpellIds(GuildOS.db.recipes[key][profName], recipes)

    GuildOS.db.recipes[key][profName] = recipes
end

----------------------------------------------------------------------
-- Get all known professions across the guild
----------------------------------------------------------------------
function RecipeTracker:GetAllProfessions()
    local profs = {}
    local seen = {}
    local DC = GuildOS.DataCollector
    for _, playerRecipes in pairs(GuildOS.db.recipes or {}) do
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
    local DC = GuildOS.DataCollector

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
    for playerKey, professions in pairs(GuildOS.db.recipes or {}) do
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
                            local spellName = GuildOS.Compat.GetSpellInfo(recipe.spellId)
                            if spellName and spellName ~= "" then
                                displayName = spellName
                            end
                        end
                        if recipe.itemId and (not displayName or displayName == recipe.name) then
                            local itemName = GuildOS.Compat.GetItemInfo(recipe.itemId)
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
    local DC = GuildOS.DataCollector
    for playerKey, professions in pairs(GuildOS.db.recipes or {}) do
        local playerName = playerKey:match("^([^-]+)") or playerKey
        for profName, recipes in pairs(professions) do
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
            local memberData = GuildOS.db and GuildOS.db.members and GuildOS.db.members[playerKey]
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
    -- WoW: Forever reads the professions model: no index to rebuild (issue #33).
    if GuildOS.ProfDirectory then return GuildOS.ProfDirectory.CraftersForItem(itemId) end
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
    if GuildOS.ProfDirectory then return GuildOS.ProfDirectory.CraftersForSpell(spellId) end
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
    local key = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
    local professions = GuildOS.db and GuildOS.db.recipes and GuildOS.db.recipes[key]
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
-- The short crafter list of a tooltip (issue #389). With 900 members the full list ran off the
-- screen: at most `max` crafters, the online ones (by name); when nobody is online, the offline
-- ones seen most recently. `presence[shortName] = { online, ago }` (ago: hours since seen, nil
-- when unknown). Returns the shown crafters, how many are left out, and how many of those are online.
----------------------------------------------------------------------
RecipeTracker.TOOLTIP_MAX = 3

function RecipeTracker.TooltipPick(crafters, presence, max)
    max = max or RecipeTracker.TOOLTIP_MAX
    presence = presence or {}
    local online = 0
    for _, c in ipairs(crafters or {}) do
        local p = presence[c.playerName]
        if p and p.online then online = online + 1 end
    end
    local wantOnline = online > 0
    -- a before b, among the crafters of the pool shown
    local function before(a, b)
        if not wantOnline then
            local pa, pb = presence[a.playerName], presence[b.playerName]
            local ta, tb = pa and pa.ago, pb and pb.ago
            if ta ~= tb then
                if ta == nil then return false end
                if tb == nil then return true end
                return ta < tb
            end
        end
        return (a.playerName or "") < (b.playerName or "")
    end
    -- The best `max` in one pass, no sort of the whole list.
    local shown = {}
    for _, c in ipairs(crafters or {}) do
        local p = presence[c.playerName]
        if ((p and p.online) and true or false) == wantOnline then
            local i = #shown + 1
            while i > 1 and before(c, shown[i - 1]) do i = i - 1 end
            if i <= max then
                table.insert(shown, i, c)
                if #shown > max then shown[#shown] = nil end
            end
        end
    end
    local total = #(crafters or {})
    local restOnline = wantOnline and (online - #shown) or 0
    return shown, total - #shown, restOnline
end

-- Who on the roster is online and how long ago the others were seen, read at most every 10 s
-- (a tooltip asks on every redraw, and the item tooltips are not all GameTooltip).
local PRESENCE_TTL = 10
function RecipeTracker:GetPresence()
    local now = GetTime and GetTime() or 0
    if self._presence and now - (self._presenceAt or 0) < PRESENCE_TTL then return self._presence end
    local out = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local fullName, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if fullName then
            local short = fullName:match("^([^-]+)") or fullName
            local ago
            if not isOnline and GetGuildRosterLastOnline then
                local y, mo, d, h = GetGuildRosterLastOnline(i)
                if y or mo or d or h then
                    ago = (((tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0)) * 24) + (tonumber(h) or 0)
                end
            end
            out[short] = { online = isOnline and true or false, ago = ago }
        end
    end
    self._presence, self._presenceAt = out, now
    return out
end

----------------------------------------------------------------------
-- Hook GameTooltip to show crafters for items
----------------------------------------------------------------------
function RecipeTracker:HookTooltips()
    local C = GuildOS.Colors

    -- Shared: append the short crafter list to a tooltip
    local function AppendCrafters(tooltip, crafters, label)
        if not crafters then return end
        local presence = RecipeTracker:GetPresence()
        local shown, rest, restOnline = RecipeTracker.TooltipPick(crafters, presence)

        tooltip:AddLine(" ")
        tooltip:AddLine(label or L["Crafted by:"], C.accent.r, C.accent.g, C.accent.b)
        for _, c in ipairs(shown) do
            local cc = c.class and GuildOS.ClassColors[c.class] or C.white
            local p = presence[c.playerName]
            local status = (p and p.online) and L[" |cff00ff00(online)|r"] or L[" |cff666666(offline)|r"]
            tooltip:AddDoubleLine("  " .. c.playerName .. status, c.profName and L[c.profName] or "", cc.r, cc.g, cc.b, 0.6, 0.6, 0.6)
        end
        -- The rest as one count, and the way to order it (Alt-click opens it in the Crafts tab).
        local more = ""
        if rest > 0 then
            more = (restOnline > 0 and string.format(L["+%d more (%d online)"], rest, restOnline)
                or string.format(L["+%d more"], rest)) .. " · "
        end
        local hint = GuildOS.CraftOrders and L["Alt-click to order"] or L["/gos craft for all"]
        if rest > 0 or GuildOS.CraftOrders then
            tooltip:AddLine("  " .. more .. hint, C.textDim.r, C.textDim.g, C.textDim.b)
        end

        tooltip:Show()
    end

    -- Item tooltip handler
    local function OnTooltipSetItem(tooltip)
        if not GuildOS.db or not GuildOS.db.recipes then return end
        if not GuildOS:ShowsItemTooltipInfo(tooltip) then return end

        local _, link = GuildOS.Compat.TooltipItem(tooltip)
        if not link then return end

        local itemId = tonumber(link:match("item:(%d+)"))
        if not itemId then return end

        local crafters = RecipeTracker:GetCraftersForItem(itemId)
        AppendCrafters(tooltip, crafters, L["Crafted by:"])
        -- WoW: Forever knows every recipe, so it can say when nobody in the guild makes this (issue #33).
        if not crafters and GuildOS.ProfDirectory and #GuildOS.ProfDirectory.ItemRecipes(itemId) > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine(L["Nobody in the guild crafts this"], C.textDim.r, C.textDim.g, C.textDim.b)
            tooltip:Show()
        end
    end

    -- Spell tooltip handler (tradeskill window, spellbook, action bars)
    local function OnTooltipSetSpell(tooltip)
        if not GuildOS.db or not GuildOS.db.recipes then return end

        local _, spellId = GuildOS.Compat.TooltipSpell(tooltip)
        if not spellId then return end

        local crafters = RecipeTracker:GetCraftersForSpell(spellId)
        AppendCrafters(tooltip, crafters, L["Enchanted by:"])
    end

    -- Item hooks (a tooltip that is not built yet is skipped)
    GuildOS.Compat.HookTooltip(GameTooltip, "OnTooltipSetItem", OnTooltipSetItem)
    GuildOS.Compat.HookTooltip(ItemRefTooltip, "OnTooltipSetItem", OnTooltipSetItem)
    GuildOS.Compat.HookTooltip(ShoppingTooltip1, "OnTooltipSetItem", OnTooltipSetItem)
    GuildOS.Compat.HookTooltip(ShoppingTooltip2, "OnTooltipSetItem", OnTooltipSetItem)

    -- Spell/enchant hooks: OnTooltipSetSpell fires for both tradeskill hover AND
    -- enchant: hyperlinks, so no need for a separate SetHyperlink hook.
    GuildOS.Compat.HookTooltip(GameTooltip, "OnTooltipSetSpell", OnTooltipSetSpell)
    GuildOS.Compat.HookTooltip(ItemRefTooltip, "OnTooltipSetSpell", OnTooltipSetSpell)
end
