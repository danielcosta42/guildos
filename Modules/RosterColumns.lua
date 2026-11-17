----------------------------------------------------------------------
-- Guild OS - Roster columns
-- Which columns the member list shows, and in what order (issue #178). The choice is the
-- account's, like the interface style: GuildOSDB.rosterColumns, the shown keys in order, nil for
-- the default. Member is never in it: it is always shown, always first.
--
-- `offered(key)` says whether this reader may show a column here. A stored key that is not offered
-- is skipped, never removed: an officer who loses the rank and gets it back finds the layout they
-- had. What the columns are and how they draw is UI/RosterFrame.lua's.
----------------------------------------------------------------------
local RosterColumns = {}
GuildOS.RosterColumns = RosterColumns

-- The list as it was before anyone could change it.
RosterColumns.DEFAULT = { "level", "class", "avgIlvl", "race", "lastSeen", "professions", "zone" }

-- The stored choice, or a copy of the default. Anything but a list of strings reads as the default;
-- repeats and Member are dropped.
local function current()
    local list = type(GuildOSDB) == "table" and GuildOSDB.rosterColumns
    local out, seen = {}, { name = true }
    if type(list) == "table" then
        for _, k in ipairs(list) do
            if type(k) ~= "string" then out = nil break end
            if not seen[k] then seen[k] = true; out[#out + 1] = k end
        end
        if out then return out end
    end
    out = {}
    for i, k in ipairs(RosterColumns.DEFAULT) do out[i] = k end
    return out
end

local function indexOf(list, key)
    for i, k in ipairs(list) do
        if k == key then return i end
    end
end

-- The shown columns, in order, that `offered` lets this reader see.
function RosterColumns:Visible(offered)
    local out = {}
    for _, k in ipairs(current()) do
        if offered(k) then out[#out + 1] = k end
    end
    return out
end

-- On goes to the end; off comes out.
function RosterColumns:SetShown(key, on)
    if key == "name" then return end
    local list = current()
    local at = indexOf(list, key)
    if on and not at then
        list[#list + 1] = key
    elseif not on and at then
        table.remove(list, at)
    else
        return
    end
    GuildOSDB.rosterColumns = list
end

-- One place left (-1) or right (1), past any column this reader is not offered.
function RosterColumns:Move(key, delta, offered)
    local list = current()
    local at = indexOf(list, key)
    if not at or not offered(key) then return end
    local to = at + delta
    while list[to] and not offered(list[to]) do to = to + delta end
    if not list[to] then return end
    list[at], list[to] = list[to], list[at]
    GuildOSDB.rosterColumns = list
end

function RosterColumns:Reset()
    GuildOSDB.rosterColumns = nil
end
