----------------------------------------------------------------------
-- Guild OS - Recipe Tracker
-- Scans and shares tradeskill recipes across the guild
--
-- TBC Anniversary keeps every member's lists in db.recipeIds (specs/salao/memoria.md):
--   db.recipeIds[key][prof] = { h = hash, spellId1, itemId1, spellId2, itemId2, ..., nm = { [i] = name } }
-- two numbers per recipe (0 where the scan had none), `h` the list's hash as the wire computes it (the
-- sorted names, RecipeTracker.Hash), and `nm` only the names the game cannot give back: every name of
-- this account's own characters (their lists go out again by name) and, for the others, a recipe
-- with no spell ID. The old shape (db.recipes[key][prof] = { { name, itemId, spellId }, ... }) is
-- what the network still carries; it is converted on arrival and on load (MigrateDB).
--
-- WoW: Forever and retail keep no copy at all: the same readers (RecipesOf, EachList, the crafter
-- indexes) read db.professions through the catalog (Modules/Professions.lua).
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local RecipeTracker = {}
GuildOS.RecipeTracker = RecipeTracker
local L = GuildOS.L

RecipeTracker.SCHEMA = 2   -- db.schema.recipes: 2 = compact lists in db.recipeIds

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

    -- The lists in their compact shape, once (and again whenever an older version wrote the old one).
    RecipeTracker.MigrateDB(GuildOS.db, self:OwnKeys())

    -- Enrich stored recipes: a recipe that came with a name and no ID gets the spell ID of a recipe of
    -- that name; the rest of them are purged.
    self:EnrichStoredRecipes()

    -- Hook tooltips to show crafters
    self:HookTooltips()
end

----------------------------------------------------------------------
-- The compact list (pure: unit-tested in tools/memory-compact.lua)
----------------------------------------------------------------------
local function nextCompact(c, i)
    i = i + 1
    local s = c[2 * i - 1]
    if s == nil then return nil end
    local it, nm = c[2 * i], c.nm
    return i, (s ~= 0) and s or nil, (it and it ~= 0) and it or nil, nm and nm[i] or nil
end
local function nextLegacy(c, i)
    i = i + 1
    local r = c[i]
    while r ~= nil and type(r) ~= "table" do
        i = i + 1
        r = c[i]
    end
    if r == nil then return nil end
    return i, tonumber(r.spellId), tonumber(r.itemId), type(r.name) == "string" and r.name or nil
end
local function noop() return nil end

-- for i, spellId, itemId, name in RecipeTracker.Each(list) do ... end, over a compact list or one in the old
-- shape (a received payload, a fixture). spellId and itemId are nil where the scan had none; name is nil
-- where the list keeps none (the game's own name, GetSpellInfo, is the one to show).
function RecipeTracker.Each(list)
    if type(list) ~= "table" then return noop, nil, 0 end
    if type(list[1]) == "table" then return nextLegacy, list, 0 end
    return nextCompact, list, 0
end

function RecipeTracker.IsLegacy(list) return type(list) == "table" and type(list[1]) == "table" end

-- How many recipes a list holds.
function RecipeTracker.Count(list)
    if type(list) ~= "table" then return 0 end
    if type(list[1]) == "table" then return #list end
    return math.floor(#list / 2)
end

-- A list in the compact shape, from either shape. `keepNames`: every name is kept (the account's own
-- characters); else only the names of recipes with no spell ID. `h`: the hash to keep (else the list's
-- own, computed from its names as the wire does). An entry with no ID and no name is dropped.
function RecipeTracker.Pack(list, keepNames, h)
    local legacy = RecipeTracker.IsLegacy(list)
    local flat = {}
    local n, nm = 0, nil
    for _, s, it, name in RecipeTracker.Each(list) do
        if s or it or name then
            n = n + 1
            flat[2 * n - 1], flat[2 * n] = s or 0, it or 0
            if name and (keepNames or not s) then
                nm = nm or {}
                nm[n] = name
            end
        end
    end
    -- Built by a constructor, the array is exactly as long as the list (grown one by one it would round up to a
    -- power of two), as the SavedVariables loader makes it.
    -- `h` and `nm` in the same constructor, so adding them later does not round the array up again.
    h = h or (legacy and RecipeTracker.Hash(list)) or (type(list) == "table" and list.h) or nil
    local out
    if #flat <= 4000 then
        out = { h = h, nm = nm, unpack(flat) }
    else
        out, flat.h, flat.nm = flat, h, nm
    end
    if out.h == nil then out.h = RecipeTracker.Hash(RecipeTracker.Wire(out)) end
    return out
end

-- The old shape of a list, { { name, itemId, spellId }, ... }, what the network carries. A name the list
-- does not keep is the client's spell name (the sender's own lists keep theirs).
function RecipeTracker.Wire(list)
    local out = {}
    for _, s, it, name in RecipeTracker.Each(list) do
        if not name and s then name = GuildOS.Compat.GetSpellInfo(s) end
        out[#out + 1] = { name = name, itemId = it, spellId = s }
    end
    return out
end

-- A list's hash: the one it was stored with (the sender's), or for the old shape the names'.
function RecipeTracker.ListHash(list)
    if type(list) ~= "table" then return nil end
    if RecipeTracker.IsLegacy(list) then return RecipeTracker.Hash(list) end
    return list.h or RecipeTracker.Hash(RecipeTracker.Wire(list))
end

----------------------------------------------------------------------
-- Migration (db.schema.recipes). Idempotent: run at every load, it converts only what is in the old
-- shape (db.recipes, which only a version before this one writes) and leaves the compact lists as they
-- are. Nothing a reader uses is lost: the IDs, the hash, the own names and every name with no spell ID
-- stay; a name with a spell ID is the game's (GetSpellInfo). WoW: Forever and retail's db.recipes was a
-- view never saved: it just goes. Returns the lists converted.
----------------------------------------------------------------------
function RecipeTracker.MigrateDB(db, ownKeys)
    if type(db) ~= "table" then return 0 end
    db.schema = type(db.schema) == "table" and db.schema or {}
    local legacy = db.recipes
    db.recipes = nil
    local store = type(db.recipeIds) == "table" and db.recipeIds or {}
    db.recipeIds = store
    if GuildOS.Professions then
        db.schema.recipes = RecipeTracker.SCHEMA
        return 0
    end
    local n = 0
    if type(legacy) == "table" then
        for key, profs in pairs(legacy) do
            if type(key) == "string" and type(profs) == "table" then
                local dest = type(store[key]) == "table" and store[key] or {}
                for prof, list in pairs(profs) do
                    if type(prof) == "string" and type(list) == "table" then
                        dest[prof] = RecipeTracker.Pack(list, ownKeys and ownKeys[key])
                        n = n + 1
                    end
                end
                if next(dest) then store[key] = dest end
            end
        end
    end
    db.recipeIds = store
    db.schema.recipes = RecipeTracker.SCHEMA
    return n
end

-- This character's key and the account's other characters' (GuildOSDB.accountChars): the lists whose
-- names are kept.
function RecipeTracker:OwnKeys()
    local out = {}
    local me = GuildOS.Compat and GuildOS.Compat.PlayerName and GuildOS.Compat.PlayerName()
    if me then out[GuildOS:GetPlayerKey(me, GetRealmName())] = true end
    for key in pairs(type(GuildOSDB) == "table" and type(GuildOSDB.accountChars) == "table" and GuildOSDB.accountChars or {}) do
        if type(key) == "string" then out[key] = true end
    end
    return out
end

function RecipeTracker:MyKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
end

----------------------------------------------------------------------
-- Reading (every reader goes through these; WoW: Forever and retail read the professions model)
----------------------------------------------------------------------
-- The Anniversary store, created when missing; a list an older version (or a test) left in db.recipes is
-- converted first.
function RecipeTracker:Store()
    local db = GuildOS.db
    if not db then return {} end
    if db.recipes ~= nil or type(db.recipeIds) ~= "table" then RecipeTracker.MigrateDB(db, self:OwnKeys()) end
    return db.recipeIds
end

local function model() return GuildOS.Professions end

-- WoW: Forever and retail: a member's lines of English name `prof`, as iterator state.
local function foreverIter(key, prof)
    local P, cat = model(), GuildOS.ProfCatalog
    local rec = cat and GuildOS.db and GuildOS.db.professions and GuildOS.db.professions[key]
    if not rec then return noop end
    local lists = {}
    for line, e in pairs(rec.profs or {}) do
        local meta = cat.professions[line]
        if meta and meta.en == prof then
            local a, b = P.Lists(e)
            lists[#lists + 1] = a
            lists[#lists + 1] = b
        end
    end
    local li, i, n, F = 1, 0, 0, cat.F
    return function()
        while true do
            local l = lists[li]
            if not l then return nil end
            i = i + 1
            local id = l[i]
            if id then
                n = n + 1
                local r = cat.recipes[id]
                local out = r and r[F.out]
                return n, id, (out and out > 0) and out or nil, nil
            end
            li, i = li + 1, 0
        end
    end
end

-- WoW: Forever and retail: the English names of `key`'s lines that hold a recipe, as a set.
local function modelProfs(key)
    local cat, out = GuildOS.ProfCatalog, {}
    local rec = cat and GuildOS.db and GuildOS.db.professions and GuildOS.db.professions[key]
    for line, e in pairs((rec and rec.profs) or {}) do
        local meta = cat.professions[line]
        if meta then
            local a, b = model().Lists(e)
            if #a > 0 or #b > 0 then out[meta.en] = true end
        end
    end
    return out
end

-- for i, spellId, itemId, name in RecipeTracker:RecipesOf(key, prof) do ... end. `prof` is the English
-- profession name. name: see Each. WoW: Forever and retail read the professions model first, and a list
-- in the store only for a profession the model has none of.
function RecipeTracker:RecipesOf(key, prof)
    if model() and modelProfs(key)[prof] then return foreverIter(key, prof) end
    local profs = self:Store()[key]
    return RecipeTracker.Each(type(profs) == "table" and profs[prof] or nil)
end

-- The professions of `key` that hold a list, as a sorted array of names.
function RecipeTracker:ProfsOf(key)
    local set = model() and modelProfs(key) or {}
    for prof, list in pairs(self:Store()[key] or {}) do
        if type(list) == "table" then set[prof] = true end
    end
    local out = {}
    for prof in pairs(set) do out[#out + 1] = prof end
    table.sort(out)
    return out
end

-- for key, prof in RecipeTracker:EachList() do ... end: every (member, profession) holding a list.
function RecipeTracker:EachList()
    local flat, keys = {}, {}
    if model() then
        for key in pairs((GuildOS.db and GuildOS.db.professions) or {}) do keys[key] = true end
    end
    for key, profs in pairs(self:Store()) do
        if type(profs) == "table" then keys[key] = true end
    end
    for key in pairs(keys) do
        for _, prof in ipairs(self:ProfsOf(key)) do
            local n = #flat
            flat[n + 1], flat[n + 2] = key, prof
        end
    end
    local i = -1
    return function()
        i = i + 2
        return flat[i], flat[i + 1]
    end
end

-- How many recipes `key` knows in `prof`.
function RecipeTracker:CountOf(key, prof)
    if model() and modelProfs(key)[prof] then
        local n = 0
        for _ in foreverIter(key, prof) do n = n + 1 end
        return n
    end
    local profs = self:Store()[key]
    return RecipeTracker.Count(type(profs) == "table" and profs[prof] or nil)
end

-- The lists changed: the crafter indexes are rebuilt on their next read.
function RecipeTracker:Changed()
    self._itemCrafterIndex, self._spellCrafterIndex, self._itemCrafterIndexTime = nil, nil, nil
end

----------------------------------------------------------------------
-- Writing (Anniversary)
----------------------------------------------------------------------
-- Store `recipes` (either shape) as `key`'s list of `prof` (canonical English). A recipe that came with a
-- name and no spell ID gets the ID of the recipe of that name the member already had (MergeSpellIds' rule:
-- same member, same locale). The hash is the list's as it arrived, so it matches what the sender announces.
function RecipeTracker:Put(key, prof, recipes, keepNames)
    if model() or type(key) ~= "string" or type(prof) ~= "string" or type(recipes) ~= "table" then return nil end
    local store = self:Store()
    local profs = type(store[key]) == "table" and store[key] or {}
    store[key] = profs
    -- Remove old localized keys that map to the same canonical profession
    local DC = GuildOS.DataCollector
    if DC and DC.GetCanonicalProfName then
        for oldKey in pairs(profs) do
            if oldKey ~= prof and DC:GetCanonicalProfName(oldKey) == prof then profs[oldKey] = nil end
        end
    end
    local h = RecipeTracker.ListHash(recipes)
    local old = profs[prof]
    local nameOnly = false
    for _, s, it, name in RecipeTracker.Each(recipes) do
        if name and not s and not it then nameOnly = true break end
    end
    if nameOnly and old then
        local lookup = {}
        for _, s, _, name in RecipeTracker.Each(old) do
            name = name or (s and GuildOS.Compat.GetSpellInfo(s))
            if s and name then lookup[strlower(name)] = s end
        end
        local wire = RecipeTracker.IsLegacy(recipes) and recipes or RecipeTracker.Wire(recipes)
        for _, r in ipairs(wire) do
            if type(r) == "table" and not r.spellId and type(r.name) == "string" then r.spellId = lookup[strlower(r.name)] end
        end
        recipes = wire
    end
    local list = RecipeTracker.Pack(recipes, keepNames, h)
    profs[prof] = list
    self:Changed()
    return list, old
end

----------------------------------------------------------------------
-- Clean stored recipe data: enrich where possible, purge the rest.
-- Recipes without spellId AND without itemId are old locale-dependent
-- data that cause cross-locale duplication. After enrichment attempts,
-- any remaining ID-less entries are removed. The data will be
-- repopulated with proper IDs on the next scan or sync. Only a list that
-- holds such a recipe is touched (most hold none): its hash stays.
----------------------------------------------------------------------
function RecipeTracker:EnrichStoredRecipes()
    if model() then return end
    local store = self:Store()
    local dirty = {}
    for key, professions in pairs(store) do
        for profName, list in pairs(type(professions) == "table" and professions or {}) do
            for _, s, it in RecipeTracker.Each(list) do
                if not s and not it then
                    dirty[#dirty + 1] = { key, profName }
                    break
                end
            end
        end
    end
    if #dirty == 0 then return end

    -- Phase 1: name→spellId per profession, from every recipe with a spell ID
    local profLookup = {}
    for _, professions in pairs(store) do
        for profName, list in pairs(type(professions) == "table" and professions or {}) do
            local lookup = profLookup[profName] or {}
            profLookup[profName] = lookup
            for _, s, _, name in RecipeTracker.Each(list) do
                if s then
                    if name then lookup[strlower(name)] = s end
                    local localName = GuildOS.Compat.GetSpellInfo(s)
                    if localName and localName ~= "" then lookup[strlower(localName)] = s end
                end
            end
        end
    end

    -- Phase 2: enrich where possible, then purge remaining ID-less entries
    local enriched, purged = 0, 0
    local own = self:OwnKeys()
    for _, d in ipairs(dirty) do
        local key, profName = d[1], d[2]
        local list = store[key][profName]
        local lookup = profLookup[profName] or {}
        local kept = {}
        for _, s, it, name in RecipeTracker.Each(list) do
            if not s and not it and name then
                s = lookup[strlower(name)]
                if s then enriched = enriched + 1 end
            end
            if s or it then
                kept[#kept + 1] = { name = name, spellId = s, itemId = it }
            else
                purged = purged + 1
            end
        end
        store[key][profName] = RecipeTracker.Pack(kept, own[key], RecipeTracker.ListHash(list))
    end
    self:Changed()

    if enriched > 0 then
        GuildOS:Print(format(L["|cff00ff00Recipes:|r enriched %d entries with IDs."], enriched))
    end
    if purged > 0 then
        GuildOS:Print(format(L["|cffFFD700Recipes:|r purged %d old entries without IDs. They will be restored on next scan/sync."], purged))
    end
end

----------------------------------------------------------------------
-- Helper: merge spellIds from existing recipes into incoming recipes (both in the old shape).
-- Same player = same locale, so names match. Kept for callers of the old shape; Put does the same.
----------------------------------------------------------------------
function RecipeTracker:MergeSpellIds(existing, incoming)
    if not existing or not incoming then return end
    local lookup = {}
    for _, s, _, name in RecipeTracker.Each(existing) do
        if name and s then lookup[strlower(name)] = s end
    end
    for _, r in ipairs(incoming) do
        if type(r) == "table" and not r.spellId and r.name then
            local sid = lookup[strlower(r.name)]
            if sid then r.spellId = sid end
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
    if model() then return end   -- WoW: Forever and retail read the professions model (Modules/Professions.lua)
    local key = self:MyKey()
    local store = self:Store()
    local had = store[key] and store[key][profName]
    local oldCount, oldHash = had and RecipeTracker.Count(had), had and RecipeTracker.ListHash(had)
    -- Every name kept: this list goes out again by name, and its hash is the names'.
    local list = self:Put(key, profName, recipes, true)

    -- Track scan timestamps per profession
    if not GuildOS.db.recipeScanTimes then
        GuildOS.db.recipeScanTimes = {}
    end
    GuildOS.db.recipeScanTimes[profName] = time()

    -- Every opening of the window used to print and send the whole list (audit D3): a line only when the
    -- count moved, and the list to the guild only when it changed.
    if not had or oldCount ~= #recipes then
        GuildOS:Print(string.format(L["|cff00ff00Recipes scanned:|r %d %s recipes indexed."], #recipes, L[profName]))
    end
    local changed = not had or oldHash ~= (list and list.h)

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

-- LibDeflate's Adler-32; the same sum in plain Lua where the library is not there (a test's stub).
local function adler32(str)
    local LD = LibStub and LibStub("LibDeflate", true)
    if LD and LD.Adler32 then return LD:Adler32(str) end
    local a, b = 1, 0
    for i = 1, #str do
        a = (a + str:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

-- Adler-32 of the recipes' names, sorted: the same list hashes the same on every client of one locale,
-- whatever spell IDs a receiver merged in (MergeSpellIds keeps the names). Over a list in the old shape
-- (the wire's); a compact list keeps the hash it arrived with (ListHash).
function RecipeTracker.Hash(recipes)
    if type(recipes) ~= "table" then return nil end
    local held = hashOf[recipes]
    if held and held.n == #recipes then return held.h end
    local names = {}
    for _, r in ipairs(recipes) do
        if type(r) == "table" then names[#names + 1] = tostring(r.name or r.spellId or r.itemId or "") end
    end
    table.sort(names)
    local h = adler32(table.concat(names, "\n"))
    hashOf[recipes] = { h = h, n = #recipes }
    return h
end

-- { [profession] = hash } of my own lists, or nil when I have none.
function RecipeTracker:OwnHashes()
    if model() then return nil end
    local mine = self:Store()[self:MyKey()]
    if type(mine) ~= "table" then return nil end
    local out
    for prof, list in pairs(mine) do
        local h = RecipeTracker.ListHash(list)
        if h then
            out = out or {}
            out[prof] = h
        end
    end
    return out
end

-- A guildmate's hashes, from their broadcast: each list held differently (or not at all) is asked for.
function RecipeTracker:OnHashes(key, sender, rh)
    if model() then return end
    self._asked = self._asked or {}
    local held = self:Store()[key]
    local DC, n, now = GuildOS.DataCollector, 0, GetTime()
    for prof, h in pairs(rh) do
        n = n + 1
        if n > self.MAX_PROFS then break end
        if type(prof) == "string" and type(h) == "number" then
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(prof) or prof
            local list = held and held[canonical]
            local id = key .. "\0" .. canonical
            local last = self._asked[id]
            if (not list or RecipeTracker.ListHash(list) ~= h) and not (last and last.h == h and now - last.at < self.REASK_AFTER) then
                self._asked[id] = { h = h, at = now }
                GuildOS.CommSystem:SendMessage("RA", prof, sender)
            end
        end
    end
end

-- A guildmate asked for my list of `prof`: it goes on GUILD once the asks of the next seconds are in.
function RecipeTracker:OnAsk(_sender, prof)
    if type(prof) ~= "string" or not IsInGuild() or model() then return end
    local key = self:MyKey()
    local function mine()
        local profs = self:Store()[key]
        return type(profs) == "table" and profs[prof] or nil
    end
    if type(mine()) ~= "table" then return end
    self._answerDue = self._answerDue or {}
    self._answeredAt = self._answeredAt or {}
    if self._answerDue[prof] then return end
    local last = self._answeredAt[prof]
    local wait = self.ASK_GATHER
    if last then wait = math.max(wait, last + self.ANSWER_GAP - GetTime()) end
    self._answerDue[prof] = true
    GuildOS.Compat.After(wait, function()
        self._answerDue[prof], self._answeredAt[prof] = nil, GetTime()
        local now = mine()
        if type(now) == "table" then self:BroadcastRecipes(prof, RecipeTracker.Wire(now)) end
    end)
end

----------------------------------------------------------------------
-- Broadcast recipes via CommSystem, in the old shape ({ { name, itemId, spellId } }): every version reads it.
----------------------------------------------------------------------
function RecipeTracker:BroadcastRecipes(profName, recipes)
    if not GuildOS.CommSystem then return end
    if not IsInGuild() then return end

    local LibSerialize = LibStub("GuildOS-LibSerialize")
    local data = {
        prof = profName,
        recipes = RecipeTracker.IsLegacy(recipes) and recipes or RecipeTracker.Wire(recipes),
    }
    local serialized = LibSerialize:Serialize(data)
    GuildOS.CommSystem:SendMessage("RC", serialized)
end

----------------------------------------------------------------------
-- Handle incoming recipe data from another guild member (the old shape, converted here)
----------------------------------------------------------------------
function RecipeTracker:HandleIncoming(sender, data)
    if model() then return end   -- WoW: Forever and retail: ProfSync carries the lists
    local LibSerialize = LibStub("GuildOS-LibSerialize")
    local ok, recipeData = LibSerialize:Deserialize(data)
    if not ok or type(recipeData) ~= "table" then return end

    local profName = recipeData.prof
    local recipes = recipeData.recipes
    if type(profName) ~= "string" or type(recipes) ~= "table" then return end

    -- Normalize profession name to canonical English
    local DC = GuildOS.DataCollector
    if DC and DC.GetCanonicalProfName then
        profName = DC:GetCanonicalProfName(profName)
    end

    -- Build player key from sender
    local senderName = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = GuildOS:GetPlayerKey(senderName, realm)

    self:Put(key, profName, recipes, self:OwnKeys()[key])
end

----------------------------------------------------------------------
-- Get all known professions across the guild
----------------------------------------------------------------------
function RecipeTracker:GetAllProfessions()
    local profs = {}
    local seen = {}
    local DC = GuildOS.DataCollector
    for _, profName in self:EachList() do
        local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
        local isGathering = DC and DC.IsGatheringProfession and DC:IsGatheringProfession(canonical)
        local isKnown = not DC or not DC.IsKnownProfession or DC:IsKnownProfession(canonical)
        if not seen[canonical] and not isGathering and isKnown then
            seen[canonical] = true
            table.insert(profs, canonical)
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
    for playerKey, profName in self:EachList() do
        local playerName = playerKey:match("^([^-]+)") or playerKey
        do
            local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
            -- Skip gathering profs and unknown profs (e.g. Poisons, old stale data)
            local isGathering = DC and DC.IsGatheringProfession and DC:IsGatheringProfession(canonical)
            local isKnown = not DC or not DC.IsKnownProfession or DC:IsKnownProfession(canonical)
            if not isGathering and isKnown then
            for _, sid, iid, rname in self:RecipesOf(playerKey, profName) do
                local recipeKey
                if sid then
                    recipeKey = "s" .. sid .. "|" .. canonical
                elseif iid then
                    recipeKey = "i" .. iid .. "|" .. canonical
                end

                if recipeKey then
                    -- ID-based recipe
                    if not grouped[recipeKey] then
                        local displayName = rname
                        if sid then
                            local spellName = GuildOS.Compat.GetSpellInfo(sid)
                            if spellName and spellName ~= "" then
                                displayName = spellName
                            end
                        end
                        if iid and (not displayName or displayName == rname) then
                            local itemName = GuildOS.Compat.GetItemInfo(iid)
                            if itemName and itemName ~= "" then
                                displayName = itemName
                            end
                        end

                        grouped[recipeKey] = {
                            name = displayName or rname or (sid and ("#" .. sid)) or "?",
                            itemId = iid,
                            spellId = sid,
                            profName = canonical,
                            crafters = {},
                            _crafterSeen = {},
                        }

                        -- Map both the original name and the resolved name to this key
                        if rname then
                            nameToKey[strlower(rname) .. "|" .. canonical] = recipeKey
                        end
                        if displayName and displayName ~= rname then
                            nameToKey[strlower(displayName) .. "|" .. canonical] = recipeKey
                        end
                    else
                        -- Entry exists; register additional name variants. An item another crafter's scan
                        -- had fills one this entry lacks, whichever list came first (pairs order).
                        if iid and not grouped[recipeKey].itemId then grouped[recipeKey].itemId = iid end
                        if rname then
                            nameToKey[strlower(rname) .. "|" .. canonical] = recipeKey
                        end
                    end
                    addCrafter(recipeKey, playerKey, playerName)
                else
                    -- No ID — queue for second pass
                    table.insert(nameOnlyQueue, {
                        recipe = { name = rname },
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
    -- A member's crafter entry is shared by every recipe of one profession; one per member per ID.
    local function add(index, id, crafterInfo)
        local list = index[id]
        if not list then
            list = {}
            index[id] = list
        end
        for _, c in ipairs(list) do
            if c.playerKey == crafterInfo.playerKey then return end
        end
        list[#list + 1] = crafterInfo
    end
    for playerKey, profName in self:EachList() do
        local playerName = playerKey:match("^([^-]+)") or playerKey
        local canonical = DC and DC.GetCanonicalProfName and DC:GetCanonicalProfName(profName) or profName
        local memberData = GuildOS.db and GuildOS.db.members and GuildOS.db.members[playerKey]
        local crafterInfo = {
            playerKey = playerKey,
            playerName = playerName,
            class = memberData and memberData.class,
            profName = canonical,
        }
        for _, sid, iid in self:RecipesOf(playerKey, profName) do
            if iid then add(itemIndex, iid, crafterInfo) end
            if sid then add(spellIndex, sid, crafterInfo) end
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
-- else nil. Reads only our own scanned recipes (RecipesOf(myKey)) — used to
-- answer realm-wide CraftNet queries authoritatively for ourselves.
----------------------------------------------------------------------
function RecipeTracker:LocalCrafts(itemId)
    itemId = tonumber(itemId)
    if not itemId or not GuildOS.db then return nil end
    local key = self:MyKey()
    for _, profName in ipairs(self:ProfsOf(key)) do
        for _, _, iid in self:RecipesOf(key, profName) do
            if iid == itemId then return profName end
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
        if not GuildOS.db then return end
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
        if not GuildOS.db then return end

        local _, spellId = GuildOS.Compat.TooltipSpell(tooltip)
        if not spellId or GuildOS.Compat.IsSecret(spellId) then return end

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
