----------------------------------------------------------------------
-- BRutus Guild Manager - Consumable Checker
-- Inspects raid members for expected buffs/consumables before pulls
----------------------------------------------------------------------
local ConsumableChecker = {}
BRutus.ConsumableChecker = ConsumableChecker
local L = BRutus.L

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

function ConsumableChecker:Initialize()
    if not BRutus.db.consumableChecks then
        BRutus.db.consumableChecks = { lastResults = {} }
    end
end

function ConsumableChecker:CheckRaid()
    if not IsInRaid() then
        BRutus:Print(L["You are not in a raid."])
        return nil
    end

    local results = {}
    local numMembers = GetNumGroupMembers()

    for i = 1, numMembers do
        local unit = "raid" .. i
        if UnitExists(unit) and UnitIsConnected(unit) then
            local name = UnitName(unit)
            local class = select(2, UnitClass(unit))
            local realm = select(2, UnitName(unit))
            realm = realm and realm ~= "" and realm or GetRealmName()
            local playerKey = name .. "-" .. realm

            local playerResult = {
                name = name,
                class = class,
                playerKey = playerKey,
                buffs = {},
                missing = {},
            }

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

            results[playerKey] = playerResult
        end
    end

    self.lastCheck = {
        time = GetServerTime(),
        results = results,
    }
    BRutus.db.consumableChecks.lastResults = results
    return results
end

function ConsumableChecker:UnitHasBuff(unit, spellID, _nameHint)
    -- Pre-resolve the localized spell name from the client so the match
    -- works on any locale (PT-BR, EN-US, etc.) without hardcoded strings.
    local localizedName = GetSpellInfo and GetSpellInfo(spellID) or nil

    for i = 1, 40 do
        -- TBC Anniversary UnitBuff returns (pos 10 = spellId):
        --   name, icon, count, debuffType, duration, expirationTime,
        --   source, isStealable, nameplateShowPersonal, spellId, ...
        local name, _, _, _, _, _, _, _, _, auraId = UnitBuff(unit, i)
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
    return self.lastCheck and self.lastCheck.results or BRutus.db.consumableChecks.lastResults or {}
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

function ConsumableChecker:ReportToChat(channel)
    local results = self:GetLastResults()
    if not results or not next(results) then
        BRutus:Print(L["No results. Use /guildos to check consumables first."])
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
