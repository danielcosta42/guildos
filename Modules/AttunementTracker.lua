----------------------------------------------------------------------
-- BRutus Guild Manager - Attunement Tracker
-- Tracks TBC raid attunements via quest completion checks
--
-- NOTE on TBC Anniversary account-wide attunements:
-- The Anniversary realm allows alts to enter attuned raids without
-- completing the attunement chains themselves. This is enforced
-- server-side and does NOT set any quest completion flags that the
-- client API can detect. Investigation confirmed:
--   - IsQuestFlaggedCompleted returns false for all attunement quests
--     on alts that have account-wide access
--   - The quest IDs that do appear completed on those alts (e.g.
--     10120, 10140, 10289, 10291) are regular Hellfire Peninsula
--     quests (confirmed from questcache.wdb), not attunement flags
--   - Quest 10291 is definitively "Report to Nazgrel" (Thrallmar)
--   - Quest 10120 is in zone 3483 (Hellfire Peninsula), Horde type
-- Therefore, attunement status for alts with account-wide access
-- will show as incomplete in this addon. This is a known limitation.
----------------------------------------------------------------------
local AttunementTracker = {}
BRutus.AttunementTracker = AttunementTracker
local L = BRutus.L

----------------------------------------------------------------------
-- TBC Attunement Data
-- Quest IDs for attunement chains
----------------------------------------------------------------------
AttunementTracker.ATTUNEMENTS = {
    {
        name = "Karazhan",
        short = "Kara",
        icon = "Interface\\Icons\\INV_Misc_Key_07",
        tier = "T4",
        quests = {
            { id = 9824,  name = "Arcane Disturbances" },
            { id = 9825,  name = "Restless Activity" },
            { id = 9826,  name = "Contact from Dalaran" },
            { id = 9829,  name = "Khadgar" },
            { id = 9831,  name = "Entry Into Karazhan" },
            { id = 9832,  name = "The Second and Third Fragments" },
            { id = 9836,  name = "The Master's Touch" },
            { id = 9837,  name = "Return to Khadgar" },
            { id = 9838,  name = "The Violet Eye" },
        },
        finalQuestId = 9838,
        -- The Master's Key (item 24490) is awarded at quest completion and
        -- physically exists in the keyring/bags. Checking possession is a
        -- secondary confirmation that survives edge cases where the quest
        -- flag was not cached correctly on a given login.
        keyItemId = 24490,
    },
    {
        name = "Gruul's Lair",
        short = "Gruul",
        icon = "Interface\\Icons\\INV_Misc_MonsterClaw_04",
        tier = "T4",
        quests = {},
        finalQuestId = nil,
        note = "No attunement required",
        alwaysComplete = true,
    },
    {
        name = "Magtheridon's Lair",
        short = "Mag",
        icon = "Interface\\Icons\\Spell_Fire_FelFlameRing",
        tier = "T4",
        quests = {},
        finalQuestId = nil,
        note = "No attunement required",
        alwaysComplete = true,
    },
    {
        name = "Serpentshrine Cavern",
        short = "SSC",
        icon = "Interface\\Icons\\INV_Misc_MonsterScales_17",
        tier = "T5",
        quests = {
            { id = 10901, name = "The Mark of Vashj" },
        },
        finalQuestId = 10901,
        note = "Removed in patch 2.1.0 - Tracking for reference",
    },
    {
        name = "Tempest Keep: The Eye",
        short = "TK",
        icon = "Interface\\Icons\\INV_Misc_Gem_NetherDragonEye",
        tier = "T5",
        quests = {
            { id = 10888, name = "Trial of the Naaru: Mercy" },
            { id = 10889, name = "Trial of the Naaru: Strength" },
            { id = 10890, name = "Trial of the Naaru: Tenacity" },
            { id = 10906, name = "Trial of the Naaru: Magtheridon" },
        },
        finalQuestId = 10906,
        note = "Removed in patch 2.1.0 - Tracking for reference",
    },
    {
        name = "Hyjal Summit",
        short = "Hyjal",
        icon = "Interface\\Icons\\INV_Misc_Branch_01",
        tier = "T6",
        quests = {
            { id = 10445, name = "The Vials of Eternity" },
        },
        finalQuestId = 10445,
        note = "Removed in patch 2.1.0 - Tracking for reference",
    },
    {
        name = "Black Temple",
        short = "BT",
        icon = "Interface\\Icons\\INV_Weapon_Glaive_01",
        tier = "T6",
        quests = {
            { id = 10563, name = "Tablets of Baa'ri" },
            { id = 10564, name = "Oronu the Elder" },
            { id = 10565, name = "The Ashtongue Corruptors" },
            { id = 10567, name = "The Warden's Cage" },
            { id = 10568, name = "Proof of Allegiance" },
            { id = 10570, name = "Akama" },
            { id = 10575, name = "Seer Udalo" },
            { id = 10576, name = "A Mysterious Portent" },
            { id = 10577, name = "The Ata'mal Terrace" },
            { id = 10578, name = "Akama's Promise" },
            { id = 10944, name = "The Secret Compromised" },
            { id = 10946, name = "Ruse of the Ashtongue" },
            { id = 10947, name = "An Artifact From the Past" },
            { id = 10948, name = "The Hostage Soul" },
            { id = 10949, name = "Entry Into the Black Temple" },
            { id = 10985, name = "A Distraction for Akama" },
        },
        finalQuestId = 10985,
    },
    {
        name = "Sunwell Plateau",
        short = "SWP",
        icon = "Interface\\Icons\\Spell_Holy_SummonLightwell",
        tier = "T6.5",
        quests = {},
        finalQuestId = nil,
        note = "No attunement required",
        alwaysComplete = true,
    },
}

-- Heroic Key Quest IDs
AttunementTracker.HEROIC_KEYS = {
    {
        name = "Hellfire Citadel (Honor Hold/Thrallmar)",
        short = "HC: HFC",
        faction = "both",
        repFaction = { alliance = "Honor Hold", horde = "Thrallmar" },
        repRequired = "Revered",
    },
    {
        name = "Coilfang Reservoir (Cenarion Expedition)",
        short = "HC: CF",
        repFaction = "Cenarion Expedition",
        repRequired = "Revered",
    },
    {
        name = "Auchindoun (Lower City)",
        short = "HC: Auch",
        repFaction = "Lower City",
        repRequired = "Revered",
    },
    {
        name = "Tempest Keep (The Sha'tar)",
        short = "HC: TK",
        repFaction = "The Sha'tar",
        repRequired = "Revered",
    },
    {
        name = "Caverns of Time (Keepers of Time)",
        short = "HC: CoT",
        repFaction = "Keepers of Time",
        repRequired = "Revered",
    },
}

function AttunementTracker:Initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:SetScript("OnEvent", function(_, event)
        if event == "QUEST_TURNED_IN" then
            C_Timer.After(1, function() AttunementTracker:ScanAttunements() end)
        end
    end)
end

----------------------------------------------------------------------
-- Scan all attunement progress
----------------------------------------------------------------------
function AttunementTracker:ScanAttunements()
    local attunements = {}

    -- Check raid attunements
    for _, attunement in ipairs(self.ATTUNEMENTS) do
        local entry = {
            name = attunement.name,
            short = attunement.short,
            tier = attunement.tier,
            icon = attunement.icon,
        }

        if attunement.alwaysComplete then
            entry.complete = true
            entry.progress = 1.0
            entry.questsDone = 0
            entry.questsTotal = 0
        else
            local done = 0
            local total = #attunement.quests
            local questStatus = {}

            for _, quest in ipairs(attunement.quests) do
                local isComplete = self:IsQuestComplete(quest.id)
                questStatus[quest.id] = isComplete
                if isComplete then
                    done = done + 1
                end
            end

            entry.complete = attunement.finalQuestId and questStatus[attunement.finalQuestId] or false
            -- Secondary check: if the attunement awards a physical key item,
            -- verify possession as well. This catches cases where the quest
            -- flag is not yet cached but the character already has the key
            -- (e.g. Karazhan Master's Key, item 24490).
            if not entry.complete and attunement.keyItemId then
                entry.complete = (GetItemCount(attunement.keyItemId) or 0) > 0
            end
            entry.progress = total > 0 and (done / total) or 0
            entry.questsDone = done
            entry.questsTotal = total
            entry.questStatus = questStatus
        end

        table.insert(attunements, entry)
    end

    -- Store in player data
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = BRutus:GetPlayerKey(name, realm)

    if BRutus.db.members[key] then
        BRutus.db.members[key].attunements = attunements
    end
    if BRutus.db.myData then
        BRutus.db.myData.attunements = attunements
    end

    return attunements
end

----------------------------------------------------------------------
-- Check if a quest is completed
----------------------------------------------------------------------
function AttunementTracker:IsQuestComplete(questId)
    -- Use C_QuestLog if available (TBC Classic may have it)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questId)
    end
    -- Fallback
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(questId)
    end
    return false
end

----------------------------------------------------------------------
-- Get effective attunements for a character.
-- Returns ONLY what that character's own client verified via the game
-- API (IsQuestFlaggedCompleted). Account-wide alt-propagation is
-- intentionally excluded: a character on a different Battle.net
-- account may share altLinks but does NOT share quest completions,
-- so relying on the alt system would produce false "Done" results.
----------------------------------------------------------------------
function AttunementTracker:GetEffectiveAttunements(playerKey)
    local data = BRutus.db.members[playerKey]
    local baseAtts = (data and data.attunements) or {}

    -- Index own attunements by short name
    local indexed = {}
    for _, att in ipairs(baseAtts) do
        indexed[att.short] = att
    end

    -- Return in canonical ATTUNEMENTS order
    local result = {}
    for _, attDef in ipairs(self.ATTUNEMENTS) do
        local e = indexed[attDef.short]
        if e then
            table.insert(result, e)
        end
    end
    return result
end

----------------------------------------------------------------------
-- Guild-wide attunement matrix (for the progression grid UI).
-- Columns are the raid attunements that actually require a quest chain
-- (alwaysComplete raids like Gruul/Mag/SWP are excluded).
----------------------------------------------------------------------
function AttunementTracker:GetGuildColumns()
    local cols = {}
    for _, def in ipairs(self.ATTUNEMENTS) do
        if not def.alwaysComplete and def.finalQuestId and #def.quests > 0 then
            cols[#cols + 1] = { short = def.short, name = def.name, tier = def.tier, icon = def.icon }
        end
    end
    return cols
end

-- Returns (columns, rows). Each row: { name, key, class, online, hasData,
-- doneCount, cells = { [short] = attEntry } }. Rows sort fully-attuned first,
-- then by completion count, then name.
function AttunementTracker:GetGuildMatrix()
    local cols = self:GetGuildColumns()
    local rows = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local atts = self:GetEffectiveAttunements(key)
            local cells, done = {}, 0
            for _, a in ipairs(atts) do
                cells[a.short] = a
            end
            for _, col in ipairs(cols) do
                local c = cells[col.short]
                if c and c.complete then done = done + 1 end
            end
            rows[#rows + 1] = {
                name = short, key = key, class = classFile or "",
                online = isOnline, hasData = (#atts > 0),
                doneCount = done, cells = cells,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.hasData ~= b.hasData then return a.hasData end
        if a.doneCount ~= b.doneCount then return a.doneCount > b.doneCount end
        return a.name:lower() < b.name:lower()
    end)
    return cols, rows
end

----------------------------------------------------------------------
-- Get compact summary for the roster column (e.g. "3/8")
----------------------------------------------------------------------
function AttunementTracker:GetAttunementSummary(playerKey)
    local atts = self:GetEffectiveAttunements(playerKey)
    if not atts or #atts == 0 then
        return L["No data"]
    end

    local total = #atts
    local done = 0
    local inProgress = 0
    for _, att in ipairs(atts) do
        if att.complete then
            done = done + 1
        elseif att.progress > 0 then
            inProgress = inProgress + 1
        end
    end

    local color
    if done == total then
        color = BRutus.Colors.green
    elseif done > 0 or inProgress > 0 then
        color = BRutus.Colors.gold
    else
        color = BRutus.Colors.red
    end

    local label = done .. "/" .. total
    if done == total then
        label = label .. " OK"
    end

    return BRutus:ColorText(label, color.r, color.g, color.b)
end
