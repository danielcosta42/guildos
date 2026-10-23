----------------------------------------------------------------------
-- Guild OS - Consumable Checker
-- Inspects raid members for expected buffs/consumables before pulls
----------------------------------------------------------------------
-- TBC Anniversary's flasks, elixirs, food and weapon buffs, and retail's Midnight flask, food,
-- augment rune and weapon enhancement (issue #187; the buffs are Data/ConsumablesRetail.lua's).
-- WoW: Forever has no table: there this module does not exist, and every reader already treats a
-- missing module as absent (ADR-0014, ADR-0026).
local client = GuildOS.Client
if not (client.isAnniversary or client.isRetail) then return end
local isRetail = client.isRetail

local ConsumableChecker = {}
GuildOS.ConsumableChecker = ConsumableChecker
local L = GuildOS.L

-- TBC consumable buff IDs grouped by category
ConsumableChecker.CONSUMABLES = {
    flask = {
        label = L["Flask"],
        buffs = {
            [17627] = "Flask of Distilled Wisdom",
            [17626] = "Flask of the Titans",
            [17628] = "Flask of Supreme Power",
            [17629] = "Flask of Chromatic Resistance",
            [28518] = "Flask of Fortification",
            [28519] = "Flask of Mighty Restoration",
            [28520] = "Flask of Relentless Assault",
            [28521] = "Flask of Blinding Light",
            [28540] = "Flask of Pure Death",
            [33053] = "Mr. Pinchy's Blessing",
            [42735] = "Flask of Chromatic Wonder",
            [40567] = "Unstable Flask of the Bandit",
            [40568] = "Unstable Flask of the Elder",
            [40572] = "Unstable Flask of the Beast",
            [40573] = "Unstable Flask of the Physician",
            [40575] = "Unstable Flask of the Soldier",
            [40576] = "Unstable Flask of the Sorcerer",
        },
    },
    food = {
        label = L["Food Buff"],
        buffs = {
            [33254] = "Well Fed (20 Stam/Spirit)",
            [33257] = "Well Fed (20 Agi/Spirit)",
            [33261] = "Well Fed (20 Str/Spirit)",
            [33263] = "Well Fed (Spell Dmg/Spirit)",
            [33265] = "Well Fed (Healing/Spirit)",
            [33268] = "Well Fed (Hit/Spirit)",
            [33272] = "Well Fed (AP/Spirit)",
            [43730] = "Electrified",
            [43722] = "Enlightened",
        },
    },
    weaponBuff = {
        label = L["Weapon Buff"],
        buffs = {
            -- Wizard Oils
            [25123] = "Brilliant Wizard Oil",
            [25122] = "Superior Wizard Oil",
            [28898] = "Blessed Wizard Oil",
            -- Mana Oils
            [25120] = "Brilliant Mana Oil",
            [28891] = "Superior Mana Oil",
            [28892] = "Blessed Mana Oil",
            -- Weapon Coatings
            [28893] = "Blessed Weapon Coating",
            -- Sharpening Stones & Weightstones (apply player aura in TBC)
            [34003] = "Adamantite Sharpening Stone",
            [34004] = "Adamantite Weightstone",
            [22746] = "Elemental Sharpening Stone",
            [23552] = "Dense Sharpening Stone",
            [23557] = "Dense Weightstone",
        },
    },
    battleElixir = {
        label = L["Battle Elixir"],
        buffs = {
            [28490] = "Elixir of Major Strength",
            [28491] = "Elixir of Healing Power",
            [28493] = "Elixir of Major Frost Power",
            [28497] = "Elixir of Major Agility",
            [28501] = "Elixir of Major Firepower",
            [28503] = "Elixir of Major Shadow Power",
            [33720] = "Onslaught Elixir",
            [33726] = "Elixir of Mastery",
            [38954] = "Fel Strength Elixir",
            [54452] = "Adept's Elixir",
        },
    },
    guardianElixir = {
        label = L["Guardian Elixir"],
        buffs = {
            [28502] = "Elixir of Major Mageblood",
            [28509] = "Elixir of Major Defense",
            [28514] = "Elixir of Empowerment",
            [39625] = "Elixir of Major Fortitude",
            [39627] = "Elixir of Draenic Wisdom",
            [39628] = "Elixir of Ironskin",
        },
    },
}

ConsumableChecker.lastCheck = nil

-- Display order and representative spell IDs for column icons
ConsumableChecker.COLUMN_ORDER = {
    { key = "flask",          icon = 28521  }, -- Flask of Blinding Light
    { key = "food",           icon = 33254  }, -- Well Fed
    { key = "weaponBuff",     icon = 25123  }, -- Brilliant Wizard Oil
    { key = "battleElixir",   icon = 28497  }, -- Elixir of Major Agility
    { key = "guardianElixir", icon = 28502  }, -- Elixir of Major Mageblood
}

----------------------------------------------------------------------
-- Retail (issue #187): Midnight's buffs by spell id, from the client's own data. A weapon oil or
-- stone is a temporary enchant, not an aura: only my own can be read (Compat.MainHandTempEnchant).
----------------------------------------------------------------------
local RETAIL_ORDER = { "flask", "food", "rune", "weapon" }
local READ_TTL = 600   -- seconds a reading taken out of combat answers for a snapshot taken in it

if isRetail then
    local catalog = GuildOS.ConsumableCatalog or {}
    local function set(ids)
        local s = {}
        for _, id in ipairs(ids or {}) do s[id] = true end
        return s
    end
    ConsumableChecker.CONSUMABLES = {
        flask  = { label = L["Flask"],        buffs = set(catalog.flask) },
        food   = { label = L["Food Buff"],    buffs = set(catalog.food) },
        rune   = { label = L["Augment Rune"], buffs = set(catalog.rune) },
        weapon = { label = L["Weapon Buff"] },
    }
end

-- Both of two readings: false when either is known to be off, true when both are on, nil otherwise.
local function both(a, b)
    if a == false or b == false then return false end
    if a and b then return true end
    return nil
end

-- The readings kept for this session, by player key: { at = GetTime(), on = verdict } (Rule 6).
local function memory()
    local state = GuildOS.State
    if not state then return {} end
    state.consumables = state.consumables or {}
    state.consumables.reads = state.consumables.reads or {}
    return state.consumables.reads
end

function ConsumableChecker:Initialize()
    if not GuildOS.db.consumableChecks then
        GuildOS.db.consumableChecks = { lastResults = {} }
    end
    -- Retail reads auras before the pull, out of combat: the ready check is when a raid looks (issue #187).
    -- Read when it starts and again when it ends: whoever eats or flasks in answer to it is read with
    -- the food on, and that later reading is the one the pull's snapshot uses.
    if isRetail and not self.frame then
        self.frame = CreateFrame("Frame")
        GuildOS.Compat.RegisterEvent(self.frame, "READY_CHECK")
        GuildOS.Compat.RegisterEvent(self.frame, "READY_CHECK_FINISHED")
        self.frame:SetScript("OnEvent", function() ConsumableChecker:OnReadyCheck() end)
    end
end

-- A ready check starting or ending, on retail: the raid's consumables are read quietly, for the
-- screens and for the snapshot the pull takes in combat.
function ConsumableChecker:OnReadyCheck()
    self:CheckRaid(true)
end

-- One unit's consumables on retail, per category: the buff's spell id (or true for my weapon), false
-- when the client showed all the unit's buffs and none of them, nil when it could not tell. In combat,
-- or with the auras secret, everything is nil: unknown is never missing.
function ConsumableChecker:ReadUnit(unit)
    local out = {}
    local ids, complete = GuildOS.Compat.UnitBuffIDs(unit)
    for _, catKey in ipairs(RETAIL_ORDER) do
        local buffs = self.CONSUMABLES[catKey].buffs
        if buffs then
            for _, id in ipairs(ids or {}) do
                if buffs[id] then out[catKey] = id break end
            end
            if not out[catKey] and ids and complete then out[catKey] = false end
        end
    end
    if GuildOS.Compat.IsPlayer(unit) then out.weapon = GuildOS.Compat.MainHandTempEnchant() end
    return out
end

-- Remember a raider's flask-and-food verdict, read out of combat.
function ConsumableChecker:Remember(key, on)
    if key and on ~= nil then memory()[key] = { at = GetTime(), on = on } end
end

-- The verdict read for a raider in the last READ_TTL seconds, or nil.
function ConsumableChecker:Recent(key)
    local r = key and memory()[key]
    if r and GetTime() - r.at <= READ_TTL then return r.on end
    return nil
end

-- TBC: a flask or a battle elixir, and food.
local function tbcVerdict(CC, unit)
    local hasFlaskOrElixir = false
    local hasFood = false

    -- Check flask
    for buffID in pairs(CC.CONSUMABLES.flask.buffs) do
        if CC:UnitHasBuff(unit, buffID) then
            hasFlaskOrElixir = true
            break
        end
    end

    -- If no flask, check battle elixir as alternative
    if not hasFlaskOrElixir then
        for buffID in pairs(CC.CONSUMABLES.battleElixir.buffs) do
            if CC:UnitHasBuff(unit, buffID) then
                hasFlaskOrElixir = true
                break
            end
        end
    end

    -- Check food
    for buffID in pairs(CC.CONSUMABLES.food.buffs) do
        if CC:UnitHasBuff(unit, buffID) then
            hasFood = true
            break
        end
    end

    return hasFlaskOrElixir and hasFood
end

-- Whether a raider has their flask and their food, for the attendance snapshot (RaidTracker): true or
-- false; on retail nil when the client could not read it, now or out of combat in the last
-- READ_TTL seconds (the ready check before the pull), which never costs the penalty (issue #187).
function ConsumableChecker:RaidVerdict(unit, key)
    if not isRetail then return tbcVerdict(self, unit) end
    local read = self:ReadUnit(unit)
    local on = both(read.flask, read.food)
    if on ~= nil then
        self:Remember(key, on)
        return on
    end
    return self:Recent(key)
end

-- Retail: a raider's row from what the client could read. `unknown` lists what it could not; the
-- weapon is listed for me alone, since nobody else's can ever be read.
local function fillRetail(CC, result, unit)
    local read = CC:ReadUnit(unit)
    local mine = GuildOS.Compat.IsPlayer(unit)
    result.unknown = {}
    for _, catKey in ipairs(RETAIL_ORDER) do
        local v, label = read[catKey], CC.CONSUMABLES[catKey].label
        if v then
            local id = tonumber(v)
            result.buffs[catKey] = { id = id, name = id and GuildOS.Compat.GetSpellInfo(id) or label }
        elseif v == false then
            table.insert(result.missing, label)
        elseif catKey ~= "weapon" or mine then
            table.insert(result.unknown, label)
        end
    end
    CC:Remember(result.playerKey, both(read.flask, read.food))
end

-- `quiet`: no word when not in a raid (the ready check asks in a party too).
function ConsumableChecker:CheckRaid(quiet)
    if not IsInRaid() then
        if not quiet then GuildOS:Print(L["You are not in a raid."]) end
        return nil
    end

    local results = {}
    local numMembers = GetNumGroupMembers()

    for i = 1, numMembers do
        local unit = "raid" .. i
        -- A member whose identity is secret, or who reports no name, is skipped.
        local name, realm, class
        if UnitExists(unit) and UnitIsConnected(unit) then name, realm, class = GuildOS.Compat.UnitIdentity(unit) end
        if name then
            local playerKey = GuildOS:GetPlayerKey(name, realm)

            local playerResult = {
                name = name,
                class = class,
                playerKey = playerKey,
                buffs = {},
                missing = {},
            }

            if isRetail then
                fillRetail(self, playerResult, unit)
            else
                -- Check each consumable category
                for catKey, category in pairs(self.CONSUMABLES) do
                    local found = false
                    local foundName = nil
                    local foundID = nil
                    for buffID, buffName in pairs(category.buffs) do
                        local auraName = self:UnitHasBuff(unit, buffID, buffName)
                        if auraName then
                            found = true
                            foundName = buffName
                            foundID = buffID
                            break
                        end
                    end
                    if found then
                        playerResult.buffs[catKey] = { name = foundName, id = foundID }
                    else
                        table.insert(playerResult.missing, category.label)
                    end
                end
            end

            results[playerKey] = playerResult
        end
    end

    self.lastCheck = {
        time = GetServerTime(),
        results = results,
    }
    GuildOS.db.consumableChecks.lastResults = results
    return results
end

function ConsumableChecker:UnitHasBuff(unit, spellID, _nameHint)
    -- Pre-resolve the localized spell name from the client so the match
    -- works on any locale (PT-BR, EN-US, etc.) without hardcoded strings.
    local localizedName = GuildOS.Compat.GetSpellInfo(spellID)

    for i = 1, 40 do
        -- TBC Anniversary UnitBuff returns (pos 10 = spellId):
        --   name, icon, count, debuffType, duration, expirationTime,
        --   source, isStealable, nameplateShowPersonal, spellId, ...
        local name, _, _, _, _, _, _, _, _, auraId = GuildOS.Compat.UnitBuff(unit, i)
        if not name then break end
        -- Primary check: spell ID match (locale-independent)
        if auraId == spellID then
            return name
        end
        -- Secondary: match by localized name from GetSpellInfo
        if localizedName and name == localizedName then
            return name
        end
    end
    return nil
end

function ConsumableChecker:GetLastResults()
    return self.lastCheck and self.lastCheck.results or GuildOS.db.consumableChecks.lastResults or {}
end

function ConsumableChecker:GetMissingCount(results)
    results = results or self:GetLastResults()
    local count = 0
    for _, player in pairs(results) do
        if #player.missing > 0 then
            count = count + 1
        end
    end
    return count
end

-- Retail: how many raiders had something the client could not read (out of range, or kept secret);
-- 0 on Anniversary, which reads every aura (issue #187).
function ConsumableChecker:GetUnknownCount(results)
    results = results or self:GetLastResults()
    local count = 0
    for _, player in pairs(results) do
        if type(player.unknown) == "table" and #player.unknown > 0 then count = count + 1 end
    end
    return count
end

-- The popup's tally: the raiders missing something (a list), how many there are, how many are ready,
-- and how many the client could not read and are neither (retail; issue #187).
function ConsumableChecker:Tally(results)
    local problems, total, ready, unread = {}, 0, 0, 0
    for _, p in pairs(results or {}) do
        total = total + 1
        if p.missing and #p.missing > 0 then
            problems[#problems + 1] = p
        elseif type(p.unknown) == "table" and #p.unknown > 0 then
            unread = unread + 1
        else
            ready = ready + 1
        end
    end
    return problems, total, ready, unread
end

function ConsumableChecker:ReportToChat(channel)
    local results = self:GetLastResults()
    if not results or not next(results) then
        GuildOS:Print(L["No results. Use /guildos to check consumables first."])
        return
    end
    -- An encounter's chat lockdown (Midnight, Forever) drops the lines without an error (issue #187).
    if GuildOS.Compat.InChatLockdown and GuildOS.Compat.InChatLockdown() then
        GuildOS:Print(L["Chat is locked during the encounter: announce after it."])
        return
    end

    local missing = {}
    for _, player in pairs(results) do
        if #player.missing > 0 then
            table.insert(missing, player.name .. ": " .. table.concat(player.missing, ", "))
        end
    end

    if #missing == 0 then
        SendChatMessage(L["[Guild OS] Consumable check: All OK!"], channel or "RAID")
    else
        SendChatMessage(L["[Guild OS] Consumable check - Missing:"], channel or "RAID")
        for _, line in ipairs(missing) do
            SendChatMessage("  " .. line, channel or "RAID")
        end
    end
end
