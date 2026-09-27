----------------------------------------------------------------------
-- Guild OS - Professions (WoW: Forever, issue #31)
--
-- Every member's professions, levels and recipes, by skill-line and recipe ID. The player's
-- own come from GetProfessionInfo and, recipe by recipe, IsPlayerSpell over the static catalog
-- (Data/ProfCatalogForever.lua): nobody has to open a window. Members without the addon come
-- from the Communities roster (the profession, no rank). ProfSync carries the addon records
-- between guildmates; Project() keeps the legacy shapes (members[].professions, db.recipes)
-- that the roster, member detail, recipes panel, tooltips, CraftNet and the export read.
----------------------------------------------------------------------
if BRutus.Client.isAnniversary then return end

local Professions = {}
BRutus.Professions = Professions

local Compat = BRutus.Compat
local LibDeflate = LibStub("LibDeflate")

Professions.MAX_LINES = 7
Professions.MAX_RECIPES = 1500
Professions.MAX_EXTRA = 200
local SCAN_DELAY = 2      -- seconds of quiet before a rescan
local WINDOW_DELAY = 1    -- the window fires TRADE_SKILL_LIST_UPDATE in bursts
local NATIVE_EVERY = 60   -- the Communities roster is read at most this often

local function catalog() return BRutus.ProfCatalog end

function Professions.OwnKey()
    return BRutus:GetPlayerKey(Compat.PlayerName())
end

-- Sorted copy of a list of positive integer IDs, duplicates dropped; nil when it is not a
-- table of IDs or runs past cap.
function Professions.IdList(t, cap)
    if type(t) ~= "table" or #t > cap then return nil end
    local out, seen = {}, {}
    for i = 1, #t do
        local v = t[i]
        if type(v) ~= "number" or v < 1 or v > 2147483647 or v % 1 ~= 0 then return nil end
        if not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    table.sort(out)
    return out
end

-- Adler-32 of the sorted recipe and extra IDs: what a summary announces and a list must match.
function Professions.Hash(recipes, extra)
    local all = {}
    for _, v in ipairs(recipes or {}) do all[#all + 1] = v end
    for _, v in ipairs(extra or {}) do all[#all + 1] = v end
    table.sort(all)
    return LibDeflate:Adler32(table.concat(all, ","))
end

function Professions:Initialize()
    BRutus.db.professions = BRutus.db.professions or {}
    self.index, self.scanned, self.nativeAt = nil, false, 0
    local f = CreateFrame("Frame")
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE",
                             "TRADE_SKILL_LIST_UPDATE", "GUILD_ROSTER_UPDATE" }) do
        Compat.RegisterEvent(f, event)
    end
    f:SetScript("OnEvent", function(_, event) Professions:OnEvent(event) end)
    Compat.After(4, function() Professions:Scan() end)
end

function Professions:OnEvent(event)
    if event == "TRADE_SKILL_LIST_UPDATE" then
        self:ScheduleWindow()
    elseif event == "GUILD_ROSTER_UPDATE" then
        self:ReadNative()
    else
        self:ScheduleScan()
    end
end

function Professions:ScheduleScan()
    if self.scanPending then return end
    self.scanPending = true
    Compat.After(SCAN_DELAY, function()
        self.scanPending = false
        self:Scan()
    end)
end

function Professions:ScheduleWindow()
    if self.windowPending then return end
    self.windowPending = true
    Compat.After(WINDOW_DELAY, function()
        self.windowPending = false
        self:ReadWindow()
    end)
end

----------------------------------------------------------------------
-- The player's own professions
----------------------------------------------------------------------
function Professions:ReadLine(line, rank, maxRank, old)
    local cat = catalog()
    local recipes, extra = {}, {}
    for _, id in ipairs(cat.byLine[line] or {}) do
        if Compat.IsPlayerSpell(id) then recipes[#recipes + 1] = id end
    end
    for _, id in ipairs((old and old.extra) or {}) do
        if Compat.IsPlayerSpell(id) then extra[#extra + 1] = id end
    end
    local spec
    for specID, specLine in pairs(cat.specs) do
        if specLine == line and Compat.IsPlayerSpell(specID) and (not spec or specID < spec) then spec = specID end
    end
    return { rank = tonumber(rank) or 0, max = tonumber(maxRank) or 0, spec = spec, recipes = recipes,
             extra = extra, n = #recipes + #extra, h = self.Hash(recipes, extra) }
end

local function sameLine(a, b)
    return b ~= nil and a.rank == b.rank and a.max == b.max and a.spec == b.spec and a.h == b.h
end

-- Read the player's professions, specializations and learned recipes. Returns true when the
-- record changed (and then republishes the summary).
function Professions:Scan()
    local cat = catalog()
    local key = self.OwnKey()
    if not (cat and key) then return false end
    self.scanned = true
    local old = BRutus.db.professions[key]
    local oldProfs = (old and old.src == "addon" and old.profs) or {}
    local profs = {}
    local slots = { Compat.GetProfessions() }
    for i = 1, table.maxn(slots) do
        local index = slots[i]
        if type(index) == "number" then
            local _, _, rank, maxRank, _, _, line = Compat.GetProfessionInfo(index)
            if type(line) == "number" and cat.professions[line] then
                profs[line] = self:ReadLine(line, rank, maxRank, oldProfs[line])
            end
        end
    end
    local changed = not old or old.src ~= "addon"
    for line, p in pairs(profs) do
        if not sameLine(p, oldProfs[line]) then changed = true end
    end
    for line in pairs(oldProfs) do
        if not profs[line] then changed = true end
    end
    if not changed then return false end
    BRutus.db.professions[key] = { src = "addon", ts = GetServerTime(), profs = profs }
    self:Changed(key)
    if BRutus.ProfSync then BRutus.ProfSync:ScheduleSummary() end
    return true
end

-- The own window, once settled: learned recipes the catalog lacks become the line's extra
-- (a beta build newer than the catalog).
function Professions:ReadWindow()
    local cat = catalog()
    local line, learned = Compat.TradeSkillLearned()
    local key = self.OwnKey()
    local rec = key and BRutus.db.professions[key]
    local p = line and rec and rec.src == "addon" and rec.profs[line]
    if not (cat and p) then return end
    local extra = {}
    for _, id in ipairs(learned) do
        if not cat.recipes[id] then extra[#extra + 1] = id end
    end
    extra = self.IdList(extra, self.MAX_EXTRA) or p.extra
    local h = self.Hash(p.recipes, extra)
    if h == p.h then return end
    p.extra, p.h, p.n = extra, h, #p.recipes + #extra
    rec.ts = GetServerTime()
    self:Changed(key)
    if BRutus.ProfSync then BRutus.ProfSync:ScheduleSummary() end
end

----------------------------------------------------------------------
-- Members without the addon: the Communities roster's professions, no rank
----------------------------------------------------------------------
function Professions:ReadNative()
    local now = GetServerTime()
    if now - (self.nativeAt or 0) < NATIVE_EVERY then return end
    self.nativeAt = now
    local cat = catalog()
    local members = Compat.GuildMemberProfessions()
    if not (cat and members) then return end
    local db = BRutus.db.professions
    for _, m in ipairs(members) do
        local short = m.name:match("^([^-]+)") or m.name
        local key = BRutus:GetPlayerKey(short, m.name:match("-(.+)$"))
        local rec = key and db[key]
        if key and (not rec or rec.src == "native") then
            local profs = {}
            for _, line in ipairs(m.lines) do
                if cat.professions[line] then profs[line] = {} end
            end
            local same = rec ~= nil
            for line in pairs(profs) do
                if not (rec and rec.profs[line]) then same = false end
            end
            for line in pairs((rec and rec.profs) or {}) do
                if not profs[line] then same = false end
            end
            if not next(profs) then
                if rec then
                    db[key] = nil
                    self:Changed(key)
                end
            elseif not same then
                db[key] = { src = "native", ts = now, profs = profs }
                self:Changed(key)
            end
        end
    end
end

----------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------
function Professions:Get(key) return BRutus.db.professions[key] end

function Professions:CraftersOf(recipeID)
    if not self.index then
        local index = {}
        for key, rec in pairs(BRutus.db.professions) do
            for _, e in pairs(rec.profs) do
                for _, list in ipairs({ e.recipes or {}, e.extra or {} }) do
                    for _, id in ipairs(list) do
                        index[id] = index[id] or {}
                        index[id][#index[id] + 1] = key
                    end
                end
            end
        end
        for _, keys in pairs(index) do table.sort(keys) end
        self.index = index
    end
    return self.index[recipeID] or {}
end

function Professions:KnowsRecipe(key, recipeID)
    for _, k in ipairs(self:CraftersOf(recipeID)) do
        if k == key then return true end
    end
    return false
end

function Professions:Members(line)
    local out = {}
    for key, rec in pairs(BRutus.db.professions) do
        if rec.profs[line] then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

----------------------------------------------------------------------
-- What ProfSync sends and applies
----------------------------------------------------------------------
function Professions:OwnSummary()
    if not self.scanned then self:Scan() end
    local rec = BRutus.db.professions[self.OwnKey()]
    local out = {}
    for line, e in pairs((rec and rec.src == "addon" and rec.profs) or {}) do
        out[line] = { r = e.rank, m = e.max, s = e.spec, h = e.h, n = e.n }
    end
    return out
end

function Professions:OwnLine(line)
    local rec = BRutus.db.professions[self.OwnKey()]
    return (rec and rec.src == "addon" and rec.profs[line]) or nil
end

local function int(v, lo, hi)
    return type(v) == "number" and v >= lo and v <= hi and v % 1 == 0
end

-- A guildmate's summary. Returns the lines whose recipe list this client still needs, or nil
-- when the summary is malformed (then nothing is applied).
function Professions:ApplySummary(key, p)
    local cat = catalog()
    if not cat or type(p) ~= "table" then return nil end
    local lines, count = {}, 0
    for line, s in pairs(p) do
        count = count + 1
        if count > self.MAX_LINES or type(s) ~= "table" or not cat.professions[line]
            or not int(s.r, 0, 1000) or not int(s.m, 0, 1000) or not int(s.h, 0, 4294967295)
            or not int(s.n, 0, self.MAX_RECIPES + self.MAX_EXTRA)
            or (s.s ~= nil and not int(s.s, 1, 2147483647)) then
            return nil
        end
        lines[line] = s
    end
    local db = BRutus.db.professions
    local old = db[key]
    local oldProfs = (old and old.src == "addon" and old.profs) or {}
    local profs, need = {}, {}
    for line, s in pairs(lines) do
        local o = oldProfs[line]
        local e = { rank = s.r, max = s.m, spec = s.s, h = s.h, n = s.n }
        if o and o.h == s.h and o.recipes then
            e.recipes, e.extra = o.recipes, o.extra
        elseif s.n == 0 then
            e.recipes, e.extra = {}, {}
        else
            need[#need + 1] = line
        end
        profs[line] = e
    end
    db[key] = { src = "addon", ts = GetServerTime(), profs = profs }
    self:Changed(key)
    table.sort(need)
    return need
end

-- A guildmate's recipe list for one line. Stored only when the IDs hash to what the list
-- says and to what that member's latest summary announced, and not already held.
function Professions:ApplyList(key, line, h, recipes, extra)
    local rec = BRutus.db.professions[key]
    local e = rec and rec.src == "addon" and rec.profs[line]
    if not e or e.h ~= h or e.recipes then return false end
    recipes = self.IdList(recipes or {}, self.MAX_RECIPES)
    extra = self.IdList(extra or {}, self.MAX_EXTRA)
    if not recipes or not extra or self.Hash(recipes, extra) ~= h then return false end
    e.recipes, e.extra = recipes, extra
    self:Changed(key)
    return true
end

----------------------------------------------------------------------
-- Legacy adapter
----------------------------------------------------------------------
function Professions:Changed(key)
    self.index = nil
    self:Project(key)
end

-- Write the shapes the existing surfaces read: members[key].professions (DataCollector's
-- { name, rank, maxRank, isPrimary }, canonical English name) and db.recipes[key][name]
-- (RecipeTracker's { name, itemId, spellId }). A native record has no rank.
function Professions:Project(key)
    local cat = catalog()
    local rec = BRutus.db.professions[key]
    local members = BRutus.db.members
    BRutus.db.recipes = BRutus.db.recipes or {}
    if not rec then
        if members[key] then members[key].professions = nil end
        BRutus.db.recipes[key] = nil
        return
    end
    local list, byProf = {}, {}
    for line, e in pairs(rec.profs) do
        local meta = cat.professions[line]
        if meta then
            list[#list + 1] = { name = meta.en, rank = e.rank, maxRank = e.max, isPrimary = meta.primary }
            if e.recipes then
                local out = {}
                for _, id in ipairs(e.recipes) do
                    local r = cat.recipes[id]
                    local item = r and r[cat.F.out]
                    out[#out + 1] = { name = Compat.GetSpellInfo(id) or ("#" .. id),
                                      itemId = (item and item > 0) and item or nil, spellId = id }
                end
                for _, id in ipairs(e.extra or {}) do
                    out[#out + 1] = { name = Compat.GetSpellInfo(id) or ("#" .. id), spellId = id }
                end
                byProf[meta.en] = out
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    members[key] = members[key] or {}
    members[key].professions = list
    BRutus.db.recipes[key] = next(byProf) and byProf or nil
end

-- The player's own professions in DataCollector's shape, for the member broadcast. Scans first
-- if the login scan has not run yet, so the broadcast never goes out empty.
function Professions:OwnLegacyList()
    if not self.scanned then self:Scan() end
    local m = BRutus.db.members[self.OwnKey()]
    return (m and m.professions) or {}
end
