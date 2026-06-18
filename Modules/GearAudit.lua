----------------------------------------------------------------------
-- Guild OS - Gear Audit
-- Guild-wide enchant audit built from the synced gear data that
-- DataCollector already stores per member (db.members[key].gear).
-- Business logic only — no UI (Rule 2 / Rule 10).
----------------------------------------------------------------------
local GearAudit = {}
BRutus.GearAudit = GearAudit

-- Inventory slots where a missing enchant is a real problem in TBC.
-- Mirrors UI/MemberDetail.lua ENCHANT_WARNING_SLOTS:
-- 1 Head, 3 Shoulder, 5 Chest, 7 Legs, 8 Feet, 9 Wrist, 10 Hands,
-- 15 Back, 16 Main Hand.
local ENCHANTABLE_SLOTS = { 1, 3, 5, 7, 8, 9, 10, 15, 16 }

function GearAudit:GetEnchantableSlots()
    return ENCHANTABLE_SLOTS
end

-- One row per guild member that has synced gear data, listing the
-- equipped-but-unenchanted slots. Sorted by most-missing first.
-- Row: { name, key, class, online, avgIlvl, missing = { slotName, ... }, missingCount }
function GearAudit:GetGuildEnchantAudit()
    local rows = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local data = BRutus.db.members[key]
            local gear = data and data.gear
            if gear then
                local missing = {}
                for _, slotId in ipairs(ENCHANTABLE_SLOTS) do
                    local item = gear[slotId]
                    -- Only flag slots that actually have an item equipped.
                    if item and item.name and item.name ~= "" then
                        if not (item.enchantId and item.enchantId > 0) then
                            missing[#missing + 1] = BRutus.SlotNames[slotId] or ("Slot " .. slotId)
                        end
                    end
                end
                rows[#rows + 1] = {
                    name = short, key = key, class = classFile or "",
                    online = isOnline, avgIlvl = data.avgIlvl or 0,
                    missing = missing, missingCount = #missing,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.missingCount ~= b.missingCount then return a.missingCount > b.missingCount end
        return a.name:lower() < b.name:lower()
    end)
    return rows
end
