----------------------------------------------------------------------
-- Guild OS - AltRoster
-- Aggregation over db.altLinks (main/alt grouping + "True Roster"
-- unique-player counts). Linking itself lives in Core/Utils (LinkAlt).
----------------------------------------------------------------------
local AltRoster = {}
BRutus.AltRoster = AltRoster

function AltRoster:Initialize()
    self:_RegisterTests()
end

local function shortName(key)
    if not key then return "" end
    return key:match("^([^-]+)") or key
end

function AltRoster:GetMain(key, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    return links[key] or key
end

function AltRoster:IsAlt(key, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    return links[key] ~= nil
end

function AltRoster:GetAltTag(key, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    local m = links[key]
    if not m then return nil end
    return string.format(BRutus.L["alt of %s"], shortName(m))
end

-- roster: array of member keys present in the guild. Returns groups keyed
-- by canonical main, the count of unique mains (unique players) and total
-- chars observed.
function AltRoster:BuildTrueRoster(roster, links)
    links = links or (BRutus.db and BRutus.db.altLinks) or {}
    local byMain = {}
    local order = {}
    for _, key in ipairs(roster) do
        local main = links[key] or key
        if not byMain[main] then
            byMain[main] = { main = main, alts = {} }
            order[#order + 1] = main
        end
        if main ~= key then
            table.insert(byMain[main].alts, key)
        end
    end
    local groups = {}
    for _, m in ipairs(order) do groups[#groups + 1] = byMain[m] end
    return { groups = groups, uniqueCount = #order, totalChars = #roster }
end

----------------------------------------------------------------------
-- Live wrappers
----------------------------------------------------------------------
function BRutus:GetAltTag(key)
    return AltRoster:GetAltTag(key)
end

function BRutus:GetTrueRoster()
    local roster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then
            local short = full:match("^([^-]+)") or full
            local realm = full:match("-(.+)$") or GetRealmName()
            roster[#roster + 1] = BRutus:GetPlayerKey(short, realm)
        end
    end
    return AltRoster:BuildTrueRoster(roster)
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function AltRoster:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    local links = { ["Alt1-R"] = "Main-R", ["Alt2-R"] = "Main-R" }
    S:Register("altroster.getmain", function()
        if AltRoster:GetMain("Alt1-R", links) ~= "Main-R" then return false, "alt->main" end
        if AltRoster:GetMain("Main-R", links) ~= "Main-R" then return false, "main->self" end
        return true
    end)
    S:Register("altroster.isalt", function()
        if not AltRoster:IsAlt("Alt1-R", links) or AltRoster:IsAlt("Main-R", links) then return false end
        return true
    end)
    S:Register("altroster.tag", function()
        local t = AltRoster:GetAltTag("Alt1-R", links)
        if not t or not t:find("Main", 1, true) then return false, tostring(t) end
        if AltRoster:GetAltTag("Main-R", links) ~= nil then return false, "main has no tag" end
        return true
    end)
    S:Register("altroster.truer", function()
        local r = AltRoster:BuildTrueRoster({ "Main-R", "Alt1-R", "Alt2-R", "Solo-R" }, links)
        -- 2 unique players (Main + Solo), 4 chars; Main group has 2 alts
        if r.uniqueCount ~= 2 or r.totalChars ~= 4 then return false, "counts" end
        for _, g in ipairs(r.groups) do
            if g.main == "Main-R" and #g.alts ~= 2 then return false, "alt count" end
        end
        return true
    end)
end
