----------------------------------------------------------------------
-- BRutus Guild Manager - Loot Tracker
-- Records items awarded by the Master Looter (officer-only).
-- History is populated exclusively via RecordMLAward;
-- generic CHAT_MSG_LOOT is NOT tracked.
----------------------------------------------------------------------
local LootTracker = {}
BRutus.LootTracker = LootTracker

function LootTracker:Initialize()
    if not BRutus.db.lootHistory then
        BRutus.db.lootHistory = {}
    end
end

-- Record a master-loot award to the persistent history.
-- Called by LootMaster:AwardLoot (locally) and by the AWARD
-- addon message handler (peers, officer-verified).
function LootTracker:RecordMLAward(entry)
    if not BRutus.db.lootHistory then
        BRutus.db.lootHistory = {}
    end
    table.insert(BRutus.db.lootHistory, 1, entry)
    while #BRutus.db.lootHistory > 500 do
        table.remove(BRutus.db.lootHistory)
    end
end

function LootTracker:GetHistory(limit)
    limit = limit or 50
    local result = {}
    for i = 1, math.min(limit, #BRutus.db.lootHistory) do
        result[i] = BRutus.db.lootHistory[i]
    end
    return result
end

function LootTracker:GetPlayerLoot(playerKey, limit)
    limit = limit or 20
    local result = {}
    for _, entry in ipairs(BRutus.db.lootHistory) do
        if entry.playerKey == playerKey then
            table.insert(result, entry)
            if #result >= limit then break end
        end
    end
    return result
end

function LootTracker:GetLootCount(playerKey)
    local count = 0
    for _, entry in ipairs(BRutus.db.lootHistory) do
        if entry.playerKey == playerKey then
            count = count + 1
        end
    end
    return count
end

function LootTracker:GetRaidLoot(raidName, limit)
    limit = limit or 50
    local result = {}
    for _, entry in ipairs(BRutus.db.lootHistory) do
        if entry.raid == raidName then
            table.insert(result, entry)
            if #result >= limit then break end
        end
    end
    return result
end

function LootTracker:DeleteEntry(index)
    if BRutus.db.lootHistory[index] then
        table.remove(BRutus.db.lootHistory, index)
    end
end

function LootTracker:ClearHistory()
    wipe(BRutus.db.lootHistory)
end

----------------------------------------------------------------------
-- Loot equity: cross-reference items received with raid attendance so
-- officers can spot who is dry (high attendance, few items) vs over-fed
-- (low attendance, many items). One row per member with loot or raids.
-- Row: { name, key, class, online, items, attendance, raids, perRaid }
----------------------------------------------------------------------
function LootTracker:GetGuildLootEquity()
    local rows = {}
    local RT = BRutus.RaidTracker
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local items = self:GetLootCount(key)
            local att, raids = 0, 0
            if RT then
                att = RT:GetAttendance25ManPercent(key) or 0
                local a = RT:GetAttendance(key)
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
