----------------------------------------------------------------------
-- Guild OS — SoftRes System
-- Imports soft reservation data from softres.it.
-- Supports the Gargul export format (base64 → zlib → JSON) and
-- the legacy CSV format (ItemId,Name,Class,Note,Plus).
----------------------------------------------------------------------
local SoftRes = {}
BRutus.SoftRes = SoftRes

local L = BRutus.L
local C = BRutus.Colors

----------------------------------------------------------------------
-- Base64 decoder (standard RFC 4648, no external library needed)
----------------------------------------------------------------------
local _B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local _B64MAP = {}
for i = 0, 63 do _B64MAP[_B64:sub(i+1, i+1)] = i end

local function Base64Decode(str)
    str = str:gsub("[^%w+/=]", "")
    local out = {}
    for i = 1, #str, 4 do
        local b0 = _B64MAP[str:sub(i,   i  )] or 0
        local b1 = _B64MAP[str:sub(i+1, i+1)] or 0
        local b2 = _B64MAP[str:sub(i+2, i+2)] or 0
        local b3 = _B64MAP[str:sub(i+3, i+3)] or 0
        out[#out+1] = string.char(b0 * 4 + math.floor(b1 / 16))
        if str:sub(i+2, i+2) ~= "=" then
            out[#out+1] = string.char((b1 % 16) * 16 + math.floor(b2 / 4))
        end
        if str:sub(i+3, i+3) ~= "=" then
            out[#out+1] = string.char((b2 % 4) * 64 + b3)
        end
    end
    return table.concat(out)
end

----------------------------------------------------------------------
-- Minimal recursive-descent JSON decoder
-- Handles objects, arrays, strings, numbers, booleans, null.
----------------------------------------------------------------------
local function JsonDecode(s)
    local pos = 1

    local function skip()
        local np = s:match("^%s*()", pos)
        if np then pos = np end
    end

    local parseValue  -- forward declaration (used by parseArray/parseObject)

    local function parseString()
        pos = pos + 1  -- consume opening "
        local parts, start = {}, pos
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == '"' then
                parts[#parts+1] = s:sub(start, pos - 1)
                pos = pos + 1
                return table.concat(parts)
            elseif c == '\\' then
                parts[#parts+1] = s:sub(start, pos - 1)
                pos = pos + 1
                local e = s:sub(pos, pos)
                parts[#parts+1] = (e == 'n' and '\n') or (e == 'r' and '\r')
                              or  (e == 't' and '\t') or e
                pos   = pos + 1
                start = pos
            else
                pos = pos + 1
            end
        end
        return table.concat(parts)
    end

    local function parseNumber()
        local n, np = s:match("^(-?%d+%.?%d*)()", pos)
        if n then pos = np end
        return tonumber(n)
    end

    local function parseArray()
        pos = pos + 1  -- consume [
        local arr = {}
        skip()
        if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
        while true do
            arr[#arr+1] = parseValue()
            skip()
            local c = s:sub(pos, pos)
            if c == ']' then pos = pos + 1; break end
            if c == ',' then pos = pos + 1 end
        end
        return arr
    end

    local function parseObject()
        pos = pos + 1  -- consume {
        local obj = {}
        skip()
        if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
        while true do
            skip()
            local k = parseString()
            skip()
            pos = pos + 1  -- consume :
            obj[k] = parseValue()
            skip()
            local c = s:sub(pos, pos)
            if c == '}' then pos = pos + 1; break end
            if c == ',' then pos = pos + 1 end
        end
        return obj
    end

    parseValue = function()
        skip()
        local c = s:sub(pos, pos)
        if     c == '"' then return parseString()
        elseif c == '{' then return parseObject()
        elseif c == '[' then return parseArray()
        elseif c == 't' then pos = pos + 4; return true
        elseif c == 'f' then pos = pos + 5; return false
        elseif c == 'n' then pos = pos + 4; return nil
        else                  return parseNumber()
        end
    end

    return parseValue()
end

----------------------------------------------------------------------
-- Initialize: ensure DB keys exist
----------------------------------------------------------------------
function SoftRes:Initialize()
    if not BRutus.db then return end
    BRutus.db.softRes = BRutus.db.softRes or { items = {}, meta = {}, distributed = {} }
    self:HookTooltips()
end

----------------------------------------------------------------------
-- Import: auto-detect format (Gargul base64 or CSV) and load
----------------------------------------------------------------------
function SoftRes:Import(raw)
    if not raw or raw == "" then
        BRutus:Print(L["SoftRes: no data to import."])
        return false
    end
    raw = raw:gsub("^%s+", ""):gsub("%s+$", "")

    -- CSV detection: header row or first field is a plain number followed by comma
    if raw:match("^ItemId,") or raw:match("^%d+,[^|]") then
        return self:ImportCSV(raw)
    end

    return self:ImportGargul(raw)
end

----------------------------------------------------------------------
-- Gargul export: base64 → zlib decompress → JSON
----------------------------------------------------------------------
function SoftRes:ImportGargul(raw)
    local compressed = Base64Decode(raw)
    if not compressed or #compressed == 0 then
        BRutus:Print(L["SoftRes: could not base64-decode import string."])
        return false
    end

    local LibDeflate = LibStub and LibStub("LibDeflate", true)
    if not LibDeflate then
        BRutus:Print(L["SoftRes: LibDeflate not available."])
        return false
    end

    local jsonStr = LibDeflate:DecompressZlib(compressed)
    if not jsonStr then
        BRutus:Print(L["SoftRes: decompression failed. Make sure you copied the full Gargul export."])
        return false
    end

    local ok, data = pcall(JsonDecode, jsonStr)
    if not ok or type(data) ~= "table" then
        BRutus:Print(L["SoftRes: failed to parse JSON. The import string may be corrupted."])
        return false
    end

    return self:LoadFromParsed(data, "gargul")
end

----------------------------------------------------------------------
-- Legacy CSV: ItemId,Name,Class,Note,Plus
-- Also accepts a simpler two-column format: ItemId,Name
----------------------------------------------------------------------
function SoftRes:ImportCSV(raw)
    local items = {}
    local first = true
    for line in (raw .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if first and (line:match("^ItemId") or line:match("^itemid")) then
            first = false
        elseif line ~= "" then
            first = false
            local id, name, class, note, plus = line:match("^(%d+),([^,]*),?([^,]*),?([^,]*),?(%d*)")
            if id and name and name ~= "" then
                local itemId = tonumber(id)
                if itemId then
                    items[itemId] = items[itemId] or {}
                    table.insert(items[itemId], {
                        name     = name,
                        class    = class or "",
                        note     = note or "",
                        plusOnes = tonumber(plus) or 0,
                    })
                end
            end
        end
    end
    return self:LoadItems(items, "csv", nil)
end

----------------------------------------------------------------------
-- Parse the decoded Gargul JSON structure
----------------------------------------------------------------------
function SoftRes:LoadFromParsed(data, source)
    local items = {}

    -- softreserves: each entry has a player name and a list of item IDs
    if type(data.softreserves) == "table" then
        for _, sr in ipairs(data.softreserves) do
            local name  = sr.name  or sr.Name  or ""
            local class = sr.class or sr.Class or ""
            local note  = sr.note  or ""
            local plus  = sr.plusOnes or 0
            local list  = sr.Items or sr.items or {}
            if name ~= "" and type(list) == "table" then
                for _, rawId in ipairs(list) do
                    local itemId = tonumber(rawId)
                    if itemId then
                        items[itemId] = items[itemId] or {}
                        table.insert(items[itemId], {
                            name     = name,
                            class    = class,
                            note     = note,
                            plusOnes = plus,
                        })
                    end
                end
            end
        end
    end

    -- hardreserves: item reserved for a specific player
    if type(data.hardreserves) == "table" then
        for _, hr in ipairs(data.hardreserves) do
            local itemId = tonumber(hr.id or hr.Id)
            local for_   = hr["for"] or ""
            if itemId and for_ ~= "" then
                items[itemId] = items[itemId] or {}
                table.insert(items[itemId], {
                    name     = for_,
                    class    = "",
                    note     = hr.note or "",
                    plusOnes = 0,
                    hard     = true,
                })
            end
        end
    end

    return self:LoadItems(items, source, data.metadata)
end

----------------------------------------------------------------------
-- Commit item table to DB and print a summary
----------------------------------------------------------------------
function SoftRes:LoadItems(items, source, meta)
    BRutus.db.softRes = {
        items       = items,
        distributed = {},
        meta        = {
            importedAt   = time(),
            raidStartsAt = meta and (meta.raidStartsAt or 0) or 0,
            source       = source or "unknown",
            listId       = meta and (meta.id or "") or "",
        },
    }

    -- Count unique items and players
    local itemCount, playerSeen = 0, {}
    for _, list in pairs(items) do
        itemCount = itemCount + 1
        for _, e in ipairs(list) do
            playerSeen[strlower(e.name or "")] = true
        end
    end
    local playerCount = 0
    for _ in pairs(playerSeen) do playerCount = playerCount + 1 end

    BRutus:Print(string.format(L["SoftRes imported: %d items, %d reservations (%s)"],
        itemCount, playerCount, source))

    -- Notify UI to refresh if the SoftRes panel is visible
    if BRutus.softResRefresh then BRutus.softResRefresh() end

    return true
end

----------------------------------------------------------------------
-- Accessors
----------------------------------------------------------------------
function SoftRes:GetDB()
    return BRutus.db and BRutus.db.softRes
end

-- Raw list of reservers for an item (all players, any status)
function SoftRes:GetReserves(itemId)
    local db = self:GetDB()
    return (db and db.items[itemId]) or {}
end

-- Returns reservers enriched with an inRaid flag, in-raid players first
function SoftRes:GetReservesForDisplay(itemId)
    local list = self:GetReserves(itemId)
    if #list == 0 then return {} end

    local inRaid = {}
    local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, numMembers do
        local n = UnitName("raid" .. i)
        if n then inRaid[strlower(n)] = true end
    end
    -- Solo / test: treat the local player as "in raid"
    local me = UnitName("player")
    if me then inRaid[strlower(me)] = true end

    local out = {}
    for _, e in ipairs(list) do
        out[#out+1] = {
            name     = e.name,
            class    = e.class,
            note     = e.note,
            plusOnes = e.plusOnes,
            hard     = e.hard,
            inRaid   = inRaid[strlower(e.name or "")] or false,
        }
    end
    table.sort(out, function(a, b)
        if a.inRaid ~= b.inRaid then return a.inRaid end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- Only in-raid soft reservers for an item
function SoftRes:GetInRaidReserves(itemId)
    local out = {}
    for _, e in ipairs(self:GetReservesForDisplay(itemId)) do
        if e.inRaid then out[#out+1] = e end
    end
    return out
end

-- All items that have at least one reservation, sorted by itemId
function SoftRes:GetAllItems()
    local db = self:GetDB()
    if not db then return {} end
    local out = {}
    for itemId, list in pairs(db.items) do
        out[#out+1] = { itemId = itemId, count = #list }
    end
    table.sort(out, function(a, b) return a.itemId < b.itemId end)
    return out
end

-- Mark an item as distributed to a player (so the UI can flag it)
function SoftRes:MarkDistributed(itemId, playerName)
    local db = self:GetDB()
    if not db then return end
    db.distributed = db.distributed or {}
    db.distributed[itemId] = db.distributed[itemId] or {}
    db.distributed[itemId][strlower(playerName)] = true
end

function SoftRes:IsDistributed(itemId, playerName)
    local db = self:GetDB()
    if not db or not db.distributed then return false end
    return db.distributed[itemId] and db.distributed[itemId][strlower(playerName or "")]
end

function SoftRes:Clear()
    if BRutus.db then
        BRutus.db.softRes = { items = {}, meta = {}, distributed = {} }
    end
    BRutus:Print(L["SoftRes data cleared."])
    if BRutus.softResRefresh then BRutus.softResRefresh() end
end

----------------------------------------------------------------------
-- Tooltip: show soft reservers when hovering an item
----------------------------------------------------------------------
function SoftRes:HookTooltips()
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
        local _, link = tt:GetItem()
        if not link then return end
        local itemId = tonumber(link:match("item:(%d+)"))
        if not itemId then return end
        local reserves = SoftRes:GetReservesForDisplay(itemId)
        if #reserves == 0 then return end

        tt:AddLine(" ")
        tt:AddLine(L["Soft Reserves:"], C.gold.r, C.gold.g, C.gold.b)
        for i, e in ipairs(reserves) do
            if i > 5 then
                tt:AddLine(string.format("  ... +%d %s", #reserves - 5, L["more"]),
                    0.55, 0.55, 0.55)
                break
            end
            local r, g, b = e.inRaid and 0.3 or 0.5, e.inRaid and 1.0 or 0.5, e.inRaid and 0.3 or 0.5
            local label = "  " .. (e.name or "?")
            if e.hard     then label = label .. " [HR]"            end
            if (e.plusOnes or 0) > 0 then label = label .. " (+" .. e.plusOnes .. ")" end
            if e.note and e.note ~= "" then label = label .. "  – " .. e.note end
            tt:AddLine(label, r, g, b)
        end
        tt:Show()
    end)
end
