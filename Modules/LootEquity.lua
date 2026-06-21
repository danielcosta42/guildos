----------------------------------------------------------------------
-- Guild OS - Loot Equity
-- Analytics over the loot history (LootTracker) — who has received how
-- much, how many epics, and their share of all loot. Helps officers
-- spread loot fairly. Pure read-only aggregation (Rule 2 / Rule 10).
----------------------------------------------------------------------
local LootEquity = {}
BRutus.LootEquity = LootEquity
local L = BRutus.L

-- Build the equity report.
-- Returns (list, grandTotal). Each row:
--   { name, total, epics, last (ts), share (0..100) } sorted by total desc.
function LootEquity:GetReport()
    local byPlayer = {}
    local grand = 0
    for _, e in ipairs(BRutus.db.lootHistory or {}) do
        local p = e.player or "?"
        local rec = byPlayer[p]
        if not rec then
            rec = { name = p, total = 0, epics = 0, last = 0 }
            byPlayer[p] = rec
        end
        local qty = e.quantity or 1
        rec.total = rec.total + qty
        grand = grand + qty

        local q = e.quality
        if not q and e.itemLink then q = select(3, GetItemInfo(e.itemLink)) end
        if q and q >= 4 then rec.epics = rec.epics + 1 end

        if (e.timestamp or 0) > rec.last then rec.last = e.timestamp or 0 end
    end

    local list = {}
    for _, rec in pairs(byPlayer) do
        rec.share = grand > 0 and (rec.total / grand * 100) or 0
        list[#list + 1] = rec
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name:lower() < b.name:lower()
    end)
    return list, grand
end

-- Print a top-N summary to chat.
function LootEquity:PrintSummary(limit)
    local list, grand = self:GetReport()
    if grand == 0 then
        BRutus:Print(L["No loot recorded yet."])
        return
    end
    BRutus:Print(string.format(L["Loot equity — %d items across %d players:"], grand, #list))
    for i = 1, math.min(limit or 10, #list) do
        local r = list[i]
        BRutus:Print(string.format(L["  %d. %s — %d items (%d epics, %.0f%%)"],
            i, r.name, r.total, r.epics, r.share))
    end
end
