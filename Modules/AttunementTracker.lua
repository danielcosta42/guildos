----------------------------------------------------------------------
-- Guild OS - Attunement Tracker
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
-- TBC content on TBC Anniversary; on WoW: Forever one table of its own, Onyxia's Lair (Ricki): the
-- Drakefire Amulet's quest chains. On retail this module does not exist, and every reader already
-- treats a missing module as absent (ADR-0014).
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
if GuildOS.Client.isRetail then return end
local ANNIVERSARY = GuildOS.Client.isAnniversary

local AttunementTracker = {}
GuildOS.AttunementTracker = AttunementTracker
local L = GuildOS.L

----------------------------------------------------------------------
-- TBC Attunement Data
-- Quest IDs for attunement chains
----------------------------------------------------------------------
AttunementTracker.TBC_ATTUNEMENTS = {
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
            { id = 10884, name = "Trial of the Naaru: Mercy" },
            { id = 10885, name = "Trial of the Naaru: Strength" },
            { id = 10886, name = "Trial of the Naaru: Tenacity" },
            { id = 10888, name = "Trial of the Naaru: Magtheridon" },
        },
        finalQuestId = 10888,
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
            -- Aldor path (10568→10571→10574→10575) OR Scryers path (10683→10684→10685→10686).
            -- Each pair uses `ids` so either variant counts as that step done.
            { ids = {10568, 10683}, name = "Tablets of Baa'ri" },
            { ids = {10571, 10684}, name = "Oronu the Elder" },
            { ids = {10574, 10685}, name = "The Ashtongue Corruptors" },
            { ids = {10575, 10686}, name = "The Warden's Cage" },
            -- Shared path after both faction chains merge
            { id = 10622, name = "Proof of Allegiance" },
            { id = 10628, name = "Akama" },
            { id = 10705, name = "Seer Udalo" },
            { id = 10706, name = "A Mysterious Portent" },
            { id = 10707, name = "The Ata'mal Terrace" },
            { id = 10708, name = "Akama's Promise" },
            -- Requires kills in SSC, The Eye, and Hyjal before final turn-in
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

----------------------------------------------------------------------
-- WoW: Forever: Onyxia's Lair (Ricki). The classic chains, one per faction, by quest id as Classic Era
-- has them: wowhead classic, read 2026-11-27 (https://www.wowhead.com/classic/quest=4903 and the series
-- boxes of quests 4182, 4264, 4322, 6403, 6502, 6566, 6567, 6569, 6582-6585, 6602), the order checked against
-- warcraft.wiki.gg (https://warcraft.wiki.gg/wiki/Onyxia%27s_Lair_attunement). UNVERIFIED on Forever: its
-- guides name the Horde chain's first quest "Blood and Thunder", which may be a new quest. The Drakefire
-- Amulet (item 16309, bags or bank) is the confirmation that holds whatever the quest ids turn out to be.
-- `factions`: the chain the player's faction walks; the Horde's three Tests of Skulls are one step each.
----------------------------------------------------------------------
AttunementTracker.FOREVER_ATTUNEMENTS = {
    {
        name = "Onyxia's Lair",
        short = "Ony",
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        tier = "T2",
        unverified = true,
        keyItemId = 16309,   -- Drakefire Amulet
        factions = {
            Horde = {
                finalQuestId = 6602,
                quests = {
                    { id = 4903, name = "Warlord's Command" },
                    { id = 4941, name = "Eitrigg's Wisdom" },
                    { id = 4974, name = "For The Horde!" },
                    { id = 6566, name = "What the Wind Carries" },
                    { id = 6567, name = "The Champion of the Horde" },
                    { id = 6568, name = "The Testament of Rexxar" },
                    { id = 6569, name = "Oculus Illusions" },
                    { id = 6570, name = "Emberstrife" },
                    { id = 6582, name = "The Test of Skulls, Scryer" },
                    { id = 6583, name = "The Test of Skulls, Somnus" },
                    { id = 6584, name = "The Test of Skulls, Chronalis" },
                    { id = 6585, name = "The Test of Skulls, Axtroz" },
                    { id = 6601, name = "Ascension..." },
                    { id = 6602, name = "Blood of the Black Dragon Champion" },
                },
            },
            Alliance = {
                finalQuestId = 6502,
                quests = {
                    { id = 4182, name = "Dragonkin Menace" },
                    { id = 4183, name = "The True Masters" },
                    { id = 4184, name = "The True Masters" },
                    { id = 4185, name = "The True Masters" },
                    { id = 4186, name = "The True Masters" },
                    { id = 4223, name = "The True Masters" },
                    { id = 4224, name = "The True Masters" },
                    { id = 4241, name = "Marshal Windsor" },
                    { id = 4242, name = "Abandoned Hope" },
                    { id = 4264, name = "A Crumpled Up Note" },
                    { id = 4282, name = "A Shred of Hope" },
                    { id = 4322, name = "Jail Break!" },
                    { id = 6402, name = "Stormwind Rendezvous" },
                    { id = 6403, name = "The Great Masquerade" },
                    { id = 6501, name = "The Dragon's Eye" },
                    { id = 6502, name = "Drakefire Amulet" },
                },
            },
        },
    },
}

-- This game's table: TBC's on Anniversary, Onyxia's alone on Forever.
AttunementTracker.ATTUNEMENTS = ANNIVERSARY and AttunementTracker.TBC_ATTUNEMENTS or AttunementTracker.FOREVER_ATTUNEMENTS

-- The chain `attunement` asks of a player of `faction` ("Horde"/"Alliance"): { quests, finalQuestId }. A
-- table with no factions is the same for both; one whose faction is unknown has no quests to read, and
-- only its key item says anything.
function AttunementTracker.ChainOf(attunement, faction)
    if not attunement.factions then return attunement end
    return attunement.factions[faction or ""] or { quests = {}, finalQuestId = nil }
end

-- Heroic Key Quest IDs (TBC Anniversary)
AttunementTracker.HEROIC_KEYS = ANNIVERSARY and {
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
} or {}

function AttunementTracker:Initialize()
    local frame = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(frame, "QUEST_TURNED_IN")
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
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil

    -- Check raid attunements
    for _, attunement in ipairs(self.ATTUNEMENTS) do
        local chain = AttunementTracker.ChainOf(attunement, faction)
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
            local total = #chain.quests
            local questStatus = {}

            for _, quest in ipairs(chain.quests) do
                local isComplete = false
                if quest.ids then
                    -- OR-logic: Aldor/Scryers parallel paths — done if ANY variant is complete
                    for _, qid in ipairs(quest.ids) do
                        local ok = self:IsQuestComplete(qid)
                        questStatus[qid] = ok
                        if ok then isComplete = true end
                    end
                else
                    isComplete = self:IsQuestComplete(quest.id)
                    questStatus[quest.id] = isComplete
                end
                if isComplete then done = done + 1 end
            end

            entry.complete = chain.finalQuestId and questStatus[chain.finalQuestId] or false
            -- Secondary check: if the attunement awards a physical key item,
            -- verify possession as well. This catches cases where the quest
            -- flag is not yet cached but the character already has the key
            -- (e.g. Karazhan Master's Key, item 24490).
            -- On Forever the bank counts too: an amulet kept there is still the door (Onyxia).
            if not entry.complete and attunement.keyItemId then
                entry.complete = (GuildOS.Compat.GetItemCount(attunement.keyItemId, not ANNIVERSARY) or 0) > 0
            end
            entry.progress = total > 0 and (done / total) or 0
            if entry.complete and not ANNIVERSARY then entry.progress = 1 end
            entry.questsDone = done
            entry.questsTotal = total
            entry.questStatus = questStatus
        end

        table.insert(attunements, entry)
    end

    -- Store in player data
    local name = GuildOS.Compat.PlayerName()
    local realm = GetRealmName()
    local key = GuildOS:GetPlayerKey(name, realm)

    if GuildOS.db.members[key] then
        GuildOS.db.members[key].attunements = attunements
    end
    if GuildOS.db.myData then
        GuildOS.db.myData.attunements = attunements
    end

    return attunements
end

----------------------------------------------------------------------
-- Check if a quest is completed
----------------------------------------------------------------------
function AttunementTracker:IsQuestComplete(questId)
    return GuildOS.Compat.IsQuestComplete(questId) and true or false
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
    local data = GuildOS.db.members[playerKey]
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
        if not def.alwaysComplete and ((def.finalQuestId and #def.quests > 0) or def.factions) then
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
            local key = GuildOS:GetPlayerKey(short, realm)
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
        color = GuildOS.Colors.green
    elseif done > 0 or inProgress > 0 then
        color = GuildOS.Colors.gold
    else
        color = GuildOS.Colors.red
    end

    local label = done .. "/" .. total
    if done == total then
        label = label .. " OK"
    end

    return GuildOS:ColorText(label, color.r, color.g, color.b)
end
