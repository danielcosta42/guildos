----------------------------------------------------------------------
-- Guild OS - Gear Audit
-- Guild-wide enchant audit built from the synced gear data that
-- DataCollector already stores per member (db.members[key].gear).
-- Business logic only — no UI (Rule 2 / Rule 10).
----------------------------------------------------------------------
local GearAudit = {}
GuildOS.GearAudit = GearAudit

-- Inventory slots where a missing enchant is a real problem, this game's (GuildOS.Client.enchantSlots):
-- TBC's 1 Head, 3 Shoulder, 5 Chest, 7 Legs, 8 Feet, 9 Wrist, 10 Hands, 15 Back, 16 Main Hand; on
-- retail Midnight's 1 Head, 3 Shoulder, 5 Chest, 7 Legs, 8 Feet, 11 and 12 the rings, 16 Main Hand
-- and 17 Off Hand when it holds a weapon.
local ENCHANTABLE_SLOTS = GuildOS.Client.enchantSlots
local OFF_HAND = 17
local IS_ENCHANTABLE = {}
for _, slot in ipairs(ENCHANTABLE_SLOTS) do IS_ENCHANTABLE[slot] = true end

function GearAudit:GetEnchantableSlots()
    return ENCHANTABLE_SLOTS
end

-- Whether an equipped `item` in `slotId` is one that should carry an enchant: the slot is this
-- game's, and an off hand is a weapon, never a shield or a frill (issue #177). The member sheet's
-- "Not enchanted" asks the same.
function GearAudit:NeedsEnchant(slotId, item)
    if not (IS_ENCHANTABLE[slotId] and item and item.name and item.name ~= "") then return false end
    return slotId ~= OFF_HAND or GuildOS.Compat.IsWeapon(item.id) == true
end

-- The names of the slots in `gear` that hold an item with no enchant. An empty slot is not flagged.
-- Also the roster's ENCHANTS column (#178).
function GearAudit:MissingEnchants(gear)
    local missing = {}
    for _, slotId in ipairs(ENCHANTABLE_SLOTS) do
        local item = gear[slotId]
        if self:NeedsEnchant(slotId, item) and not (item.enchantId and item.enchantId > 0) then
            missing[#missing + 1] = GuildOS.SlotNames[slotId] or ("Slot " .. slotId)
        end
    end
    return missing
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
            local key = GuildOS:GetPlayerKey(short, realm)
            local data = GuildOS.db.members[key]
            local gear = data and data.gear
            if gear then
                local missing = self:MissingEnchants(gear)
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
