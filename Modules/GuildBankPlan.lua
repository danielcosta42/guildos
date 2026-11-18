----------------------------------------------------------------------
-- Guild OS - Guild bank: the order a tab is kept in (issue #380)
-- Pure and frame-free, so tools/guild-bank.lua runs it as it is: what group an item belongs to,
-- the order items sort in, and the next move that brings a tab closer to that order. Organizing
-- (Modules/GuildBank.lua) asks for one move, makes it, waits for the server and asks again on what
-- the tab really holds, so a deposit in the middle, a move the server refused or a stack the game
-- merged differently never leaves a plan out of date.
----------------------------------------------------------------------
local Plan = {}
GuildOS.GuildBankPlan = Plan

-- The groups an item is shown and sorted under, in order. Keyed by the game's item class id, which
-- is the same number on every client (Enum.ItemClass): 0 consumable, 1 container, 2 weapon, 3 gem,
-- 4 armor, 5 reagent, 6 projectile, 7 trade goods, 8 item enhancement, 9 recipe, 11 quiver,
-- 12 quest, 13 key, 15 miscellaneous, 16 glyph, 17 battle pet, 18 token, 19 profession.
Plan.GROUPS = { "consumable", "trade", "enhance", "recipe", "gear", "bags", "other" }
local GROUP_OF_CLASS = {
    [0] = "consumable",
    [7] = "trade", [5] = "trade", [19] = "trade",
    [3] = "enhance", [8] = "enhance",
    [9] = "recipe", [16] = "recipe",
    [2] = "gear", [4] = "gear",
    [1] = "bags", [11] = "bags", [6] = "bags",
}
local GROUP_RANK = {}
for i, g in ipairs(Plan.GROUPS) do GROUP_RANK[g] = i end

local MAX_QUALITY = 9      -- above any quality the game has (8 is heirloom/WoW token)
local MAX_LEVEL = 9999     -- above any item level the game has

-- The group an item class belongs to.
function Plan.GroupOf(classID)
    return GROUP_OF_CLASS[tonumber(classID) or -1] or "other"
end

-- The position of a group in Plan.GROUPS (1 first), for sorting.
function Plan.GroupRank(group)
    return GROUP_RANK[group] or #Plan.GROUPS
end

-- The sort key of an item, as a string that compares in the order the bank is kept: group, class,
-- subclass, best quality first, highest item level first, name, item id. `info` holds what is known:
-- { id, classID, subClassID, quality, level, name }; a name the client has not cached yet sorts by
-- id alone, after the named items of its kind, so the order never depends on what loaded first.
function Plan.SortKey(info)
    local classID = tonumber(info.classID) or 99
    local sub = tonumber(info.subClassID) or 99
    local quality = math.min(MAX_QUALITY, math.max(0, tonumber(info.quality) or 0))
    local level = math.min(MAX_LEVEL, math.max(0, tonumber(info.level) or 0))
    local name = type(info.name) == "string" and info.name:lower() or "\255"
    return string.format("%02d%03d%03d%d%04d", Plan.GroupRank(Plan.GroupOf(classID)), classID, sub,
        MAX_QUALITY - quality, MAX_LEVEL - level) .. name .. "\1" .. string.format("%010d", tonumber(info.id) or 0)
end

----------------------------------------------------------------------
-- Planning. A tab is `slots`, an array 1..size where each entry is nil (empty) or
-- { k = key, c = count }, and `rank[key]` is the key's sort key. `stack[key]` is how many fit in
-- one slot (1 when unknown: such an item is never merged).
----------------------------------------------------------------------

-- The stacks a tab would hold once organized, in slot order: every item's stacks merged as far as
-- they go and sorted. What the Organized view draws, and what PlanMove works towards.
function Plan.Target(slots, size, rank, stack)
    local totals, order = {}, {}
    for i = 1, size do
        local s = slots[i]
        if s then
            if not totals[s.k] then order[#order + 1] = s.k end
            totals[s.k] = (totals[s.k] or 0) + s.c
        end
    end
    table.sort(order, function(a, b)
        local ra, rb = rank[a] or "", rank[b] or ""
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local out = {}
    for _, k in ipairs(order) do
        local per = math.max(1, tonumber(stack[k]) or 1)
        local left = totals[k]
        while left > 0 do
            local c = math.min(per, left)
            out[#out + 1] = { k = k, c = c }
            left = left - c
        end
    end
    return out
end

-- The first merge left: two stacks of one item that are not full. The bigger takes from the smaller
-- (ties: the earlier slot takes, the later slot gives), so the item ends in as few slots as it can.
local function nextMerge(slots, size, stack)
    local partial = {}
    for i = 1, size do
        local s = slots[i]
        if s then
            local per = math.max(1, tonumber(stack[s.k]) or 1)
            if s.c < per then
                local list = partial[s.k]
                if not list then list = {}; partial[s.k] = list end
                list[#list + 1] = i
            end
        end
    end
    local best
    for k, list in pairs(partial) do
        if #list >= 2 then
            local to, from = list[1], list[1]
            for _, i in ipairs(list) do
                if slots[i].c > slots[to].c then to = i end
                if slots[i].c < slots[from].c or (slots[i].c == slots[from].c and i > from) then from = i end
            end
            if to == from then to = list[1] ~= from and list[1] or list[2] end
            local per = math.max(1, tonumber(stack[k]) or 1)
            local n = math.min(slots[from].c, per - slots[to].c)
            -- The lowest slot first, so two runs on the same tab make the same moves.
            if not best or math.min(from, to) < math.min(best.from, best.to) then
                best = { op = n < slots[from].c and "split" or "move", from = from, to = to, count = n }
            end
        end
    end
    return best
end

-- The next move that brings the tab closer to Plan.Target, or nil when it already holds it.
-- The guild bank does not swap: an item dropped on a slot holding another item is refused and
-- stays on the cursor (#380). So a move only ever drops into an empty slot or onto the same item:
--   { op = "split", from, to, count } takes `count` off `from` onto the same item at `to`;
--   { op = "move", from, to } picks `from` up and drops it into the empty `to`, or onto the same
--   item there (a merge).
-- The first slot out of order is filled from a later slot holding exactly what it should; when it
-- holds something else, that is first moved out to an empty slot: its own place if that is empty,
-- else the last empty slot of the tab. With no empty slot and no merge left a full tab cannot be
-- ordered: nil, "full".
function Plan.PlanMove(slots, size, rank, stack)
    local merge = nextMerge(slots, size, stack)
    if merge then return merge end
    local target = Plan.Target(slots, size, rank, stack)
    for i, want in ipairs(target) do
        local cur = slots[i]
        if not (cur and cur.k == want.k and cur.c == want.c) then
            if not cur then
                for j = i + 1, size do
                    local s = slots[j]
                    if s and s.k == want.k and s.c == want.c then
                        return { op = "move", from = j, to = i }
                    end
                end
                return nil   -- not reachable once every merge is made; never loop on it
            end
            -- Move what is in the way out: home if its place is free, else to the end of the tab.
            local park
            for k = i + 1, size do
                local w = target[k]
                if not slots[k] and w and w.k == cur.k and w.c == cur.c then park = k; break end
            end
            if not park then
                for k = size, i + 1, -1 do
                    if not slots[k] then park = k; break end
                end
            end
            if not park then return nil, "full" end
            return { op = "move", from = i, to = park }
        end
    end
    return nil
end

-- What a move does to `slots`, as the game does it. The harness plays a whole run with it, and the
-- Organized view could; the real tab is always read back from the game.
function Plan.Apply(slots, move, stack)
    local a, b = slots[move.from], slots[move.to]
    if not a then return end
    if move.op == "split" then
        if not b or b.k ~= a.k then return end
        b.c = b.c + move.count
        a.c = a.c - move.count
        if a.c <= 0 then slots[move.from] = nil end
        return
    end
    if not b then
        slots[move.to], slots[move.from] = a, nil
    elseif b.k == a.k then
        local per = math.max(1, tonumber(stack[a.k]) or 1)
        local total = a.c + b.c
        b.c = math.min(per, total)
        a.c = total - b.c
        if a.c <= 0 then slots[move.from] = nil end
    else
        slots[move.to], slots[move.from] = a, b
    end
end

-- How many moves a run would take, playing it on a copy (capped at `limit`): the progress bar's
-- total, and the harness's proof that every run ends. Second return: "full" when the tab cannot be
-- put in order without a free slot.
function Plan.CountMoves(slots, size, rank, stack, limit)
    local copy = {}
    for i = 1, size do
        local s = slots[i]
        if s then copy[i] = { k = s.k, c = s.c } end
    end
    local n = 0
    while n < limit do
        local m, why = Plan.PlanMove(copy, size, rank, stack)
        if not m then return n, why end
        Plan.Apply(copy, m, stack)
        n = n + 1
    end
    return n
end
