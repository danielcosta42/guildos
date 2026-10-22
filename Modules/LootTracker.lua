----------------------------------------------------------------------
-- Guild OS - Loot Tracker
-- The loot history. On TBC Anniversary and WoW: Forever: items awarded
-- by the Master Looter (officer-only), via RecordMLAward; generic
-- CHAT_MSG_LOOT is NOT tracked. On retail, where loot is personal and
-- nobody hands anything out: what each guildmate received from a boss
-- inside a tracked raid session, via OnEncounterLoot (issue #183).
----------------------------------------------------------------------
local LootTracker = {}
GuildOS.LootTracker = LootTracker

local HISTORY_MAX = 500         -- entries kept, newest first
-- Personal loot (retail, issue #183).
local PERSONAL_MIN_QUALITY = 3  -- Rare: the loot master's default threshold (LootMaster.LOOT_THRESHOLD)
local PERSONAL_UNKNOWN_QUALITY = 4  -- an item neither cached nor coloured in its link: a boss's, as an ML award assumes
local REFIRE_WINDOW = 300       -- seconds; the same boss, item and player again within this is the same drop

function LootTracker:Initialize()
    if not GuildOS.db.lootHistory then
        GuildOS.db.lootHistory = {}
    end
    -- Retail only: Forever and Anniversary keep the master-loot path and nothing else (issue #183).
    if GuildOS.Client.isRetail then
        local frame = CreateFrame("Frame")
        GuildOS.Compat.RegisterEvent(frame, "ENCOUNTER_LOOT_RECEIVED")
        frame:SetScript("OnEvent", function(_, _, ...) LootTracker:OnEncounterLoot(...) end)
    end
end

local function remember(entry)
    if not GuildOS.db.lootHistory then
        GuildOS.db.lootHistory = {}
    end
    table.insert(GuildOS.db.lootHistory, 1, entry)
    while #GuildOS.db.lootHistory > HISTORY_MAX do
        table.remove(GuildOS.db.lootHistory)
    end
end

-- Record a master-loot award to the persistent history.
-- Called by LootMaster:AwardLoot (locally) and by the AWARD
-- addon message handler (peers, officer-verified).
function LootTracker:RecordMLAward(entry)
    remember(entry)
end

-- The raid session personal loot belongs to: a tracked one this client is standing in, on its
-- difficulty, as its snapshots and bosses are (RaidTracker:ElsewhereInGrace). Raid Finder of the same
-- raid, queued during the grace, is the same instance id with strangers' items (issue #183).
local function sessionHere()
    local RT = GuildOS.RaidTracker
    local session = RT and RT.trackingActive and RT.currentRaid
    if not session or RT:ElsewhereInGrace() then return nil end
    local _, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "raid" or instanceID ~= session.instanceID then return nil end
    if session.difficulty and tonumber(difficultyID) ~= session.difficulty then return nil end
    return session
end

-- Whether somebody is on this guild's roster, by their whole key: a guildmate on a connected realm is,
-- a namesake from a realm the guild is not on is not. A pickup raid's strangers are not the guild's
-- loot; on Forever an item needs an award from this guild's officer to be recorded at all (issue #183).
local function guildmate(playerKey)
    local name, realm = playerKey:match("^([^-]+)%-(.+)$")
    local idx = GuildOS.Compat.FindGuildRosterIndex(name or playerKey, realm)
    local full = idx and GetGuildRosterInfo(idx)
    return full ~= nil and GuildOS:KeyOfRosterName(full) == playerKey
end

-- An item's quality and name: the client's when it has the item cached, else what the link carries
-- (retail colours a link by quality, "|cnIQ4:", and names it in brackets).
local function itemFacts(itemLink)
    local name, _, quality = GuildOS.Compat.GetItemInfo(itemLink)
    quality = quality or tonumber(itemLink:match("|cnIQ(%d+):")) or PERSONAL_UNKNOWN_QUALITY
    return quality, name or itemLink:match("|h%[(.-)%]|h") or ""
end

-- Whether this drop was just recorded: the event can come again for the same item.
local function refired(encounterID, itemId, playerKey, now)
    for _, e in ipairs(GuildOS.db.lootHistory or {}) do
        if now - (tonumber(e.timestamp) or 0) > REFIRE_WINDOW then return false end
        if e.encounterID == encounterID and e.itemId == itemId and e.playerKey == playerKey then return true end
    end
    return false
end

-- Record one guildmate's personal loot from ENCOUNTER_LOOT_RECEIVED (retail, issue #183): every
-- guildmate's item, not only mine, in the shape an ML award has, named and keyed by the player's own
-- realm. The event names someone on this character's realm without one, so the bare name would mean
-- another person to an alt on a connected realm: `player` is the whole Name-Realm too.
function LootTracker:OnEncounterLoot(encounterID, itemID, itemLink, quantity, playerName, className)
    if not GuildOS.Client.isRetail then return end
    -- Midnight may hand any field as a secret, which is never compared, joined or stored; a record
    -- without it would be half a record, so the item is skipped whole.
    if GuildOS.Compat.IsSecret(encounterID, itemID, itemLink, quantity, playerName, className) then return end
    if type(itemLink) ~= "string" or type(playerName) ~= "string" or playerName == "" then return end
    if not GuildOS:IsFeatureEnabled("lootTracker") then return end
    local session = sessionHere()
    if not session then return end

    local quality, itemName = itemFacts(itemLink)
    if quality < PERSONAL_MIN_QUALITY then return end
    local name, realm = playerName:match("^([^-]+)%-(.+)$")
    local playerKey = GuildOS:GetPlayerKey(name or playerName, realm)
    if not guildmate(playerKey) then return end
    local itemId = tonumber(itemID) or tonumber(itemLink:match("item:(%d+)")) or 0
    local now = GetServerTime()
    if refired(encounterID, itemId, playerKey, now) then return end

    remember({
        itemLink    = itemLink,
        itemId      = itemId,
        itemName    = itemName,
        quality     = quality,
        player      = playerKey,
        playerKey   = playerKey,
        count       = tonumber(quantity) or 1,
        timestamp   = now,
        raid        = session.name or "",
        instanceID  = session.instanceID,
        encounterID = encounterID,
    })
end

function LootTracker:GetHistory(limit)
    limit = limit or 50
    local result = {}
    for i = 1, math.min(limit, #GuildOS.db.lootHistory) do
        result[i] = GuildOS.db.lootHistory[i]
    end
    return result
end

function LootTracker:GetPlayerLoot(playerKey, limit)
    limit = limit or 20
    local result = {}
    for _, entry in ipairs(GuildOS.db.lootHistory) do
        if entry.playerKey == playerKey then
            table.insert(result, entry)
            if #result >= limit then break end
        end
    end
    return result
end

function LootTracker:GetLootCount(playerKey)
    local count = 0
    for _, entry in ipairs(GuildOS.db.lootHistory) do
        if entry.playerKey == playerKey then
            count = count + 1
        end
    end
    return count
end

function LootTracker:GetRaidLoot(raidName, limit)
    limit = limit or 50
    local result = {}
    for _, entry in ipairs(GuildOS.db.lootHistory) do
        if entry.raid == raidName then
            table.insert(result, entry)
            if #result >= limit then break end
        end
    end
    return result
end

function LootTracker:DeleteEntry(index)
    if GuildOS.db.lootHistory[index] then
        table.remove(GuildOS.db.lootHistory, index)
    end
end

function LootTracker:ClearHistory()
    wipe(GuildOS.db.lootHistory)
end

----------------------------------------------------------------------
-- Loot equity: cross-reference items received with raid attendance so
-- officers can spot who is dry (high attendance, few items) vs over-fed
-- (low attendance, many items). One row per member with loot or raids.
-- Row: { name, key, class, online, items, attendance, raids, perRaid }
----------------------------------------------------------------------
function LootTracker:GetGuildLootEquity()
    local rows = {}
    local RT = GuildOS.RaidTracker
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = GuildOS:GetPlayerKey(short, realm)
            local items = self:GetLootCount(key)
            local att, raids = 0, 0
            if RT then
                -- One core for both figures: the one with the most nights that count (#134).
                local core = RT:GetPlayerGroup(key, "raids25")
                att = RT:GetAttendance25ManPercent(key, core) or 0
                local a = RT:GetAttendance(key, core)
                raids = (a and a.raids25) or 0
            end
            if items > 0 or raids > 0 then
                rows[#rows + 1] = {
                    name = short, key = key, class = classFile or "", online = isOnline,
                    items = items, attendance = att, raids = raids,
                    perRaid = raids > 0 and (items / raids) or 0,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.items ~= b.items then return a.items > b.items end
        return a.attendance > b.attendance
    end)
    return rows
end
