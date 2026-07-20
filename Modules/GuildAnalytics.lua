----------------------------------------------------------------------
-- Guild OS - Guild Analytics
-- Composition distributions (class / level / rank / zone) as pure
-- aggregation over the guild roster, shown as bars in a /gos analytics window.
----------------------------------------------------------------------
local GuildAnalytics = {}
BRutus.GuildAnalytics = GuildAnalytics

GuildAnalytics.DIMENSIONS = { "class", "level", "rank", "zone" }

function GuildAnalytics:Initialize()
    self:_RegisterTests()
end

function GuildAnalytics:_LevelBracket(level)
    level = level or 0
    if level >= 70 then return "70" end
    local lo = math.floor(level / 10) * 10
    if lo == 0 then return "1-9" end
    return lo .. "-" .. (lo + 9)
end

function GuildAnalytics:BuildRoster()
    local roster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            roster[#roster + 1] = { class = classFile, level = level, rank = rank, zone = zone, online = online }
        end
    end
    return roster
end

function GuildAnalytics:Distribution(dim, onlineOnly, roster)
    roster = roster or self:BuildRoster()
    local counts, order, total = {}, {}, 0
    for _, m in ipairs(roster) do
        if (not onlineOnly) or m.online then
            local key, colorKey
            if dim == "class" then key = m.class or "?"; colorKey = m.class
            elseif dim == "level" then key = self:_LevelBracket(m.level)
            elseif dim == "rank" then key = m.rank or "?"
            elseif dim == "zone" then key = (m.zone and m.zone ~= "" and m.zone) or "?"
            else key = "?" end
            if not counts[key] then counts[key] = { count = 0, colorKey = colorKey }; order[#order + 1] = key end
            counts[key].count = counts[key].count + 1
            total = total + 1
        end
    end
    local out = {}
    for _, k in ipairs(order) do
        out[#out + 1] = { label = k, count = counts[k].count, colorKey = counts[k].colorKey }
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.label) < tostring(b.label)
    end)
    for _, e in ipairs(out) do e.pct = total > 0 and (e.count / total * 100) or 0 end
    return out, total
end

-- (Note: for dim=="class", label is the class file token; the UI localizes via
-- LOCALIZED_CLASS_NAMES_MALE and colors via RAID_CLASS_COLORS. Keeping the raw
-- token here keeps Distribution pure and testable.)

function GuildAnalytics:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("analytics.class", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false }, { class = "WARRIOR", online = true } }
        local out, total = GuildAnalytics:Distribution("class", false, roster)
        if total ~= 3 then return false, "total" end
        if out[1].label ~= "MAGE" or out[1].count ~= 2 then return false, "top bucket" end
        return true
    end)
    S:Register("analytics.online_filter", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false } }
        local _, total = GuildAnalytics:Distribution("class", true, roster)
        if total ~= 1 then return false, "online-only" end
        return true
    end)
    S:Register("analytics.level_bracket", function()
        if GuildAnalytics:_LevelBracket(70) ~= "70" then return false, "70" end
        if GuildAnalytics:_LevelBracket(65) ~= "60-69" then return false, "60-69" end
        if GuildAnalytics:_LevelBracket(5) ~= "1-9" then return false, "1-9" end
        return true
    end)
    S:Register("analytics.pct", function()
        local roster = { { class = "MAGE" }, { class = "MAGE" }, { class = "ROGUE" }, { class = "ROGUE" } }
        local out = GuildAnalytics:Distribution("class", false, roster)
        if math.abs(out[1].pct - 50) > 0.01 then return false, "pct" end
        return true
    end)
end
