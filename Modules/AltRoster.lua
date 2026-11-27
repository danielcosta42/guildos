----------------------------------------------------------------------
-- Guild OS - AltRoster
-- Aggregation over db.altLinks (main/alt grouping + "True Roster"
-- unique-player counts). Linking itself lives in Core/Utils (LinkAlt).
----------------------------------------------------------------------
local AltRoster = {}
GuildOS.AltRoster = AltRoster

function AltRoster:Initialize()
    self:_RegisterTests()
end

local function shortName(key)
    if not key then return "" end
    return key:match("^([^-]+)") or key
end

function AltRoster:GetMain(key, links)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
    return links[key] or key
end

function AltRoster:IsAlt(key, links)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
    return links[key] ~= nil
end

function AltRoster:GetAltTag(key, links)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
    local m = links[key]
    if not m then return nil end
    return string.format(GuildOS.L["alt of %s"], shortName(m))
end

function AltRoster:HasAlts(key, links)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
    for _, main in pairs(links) do
        if main == key then return true end
    end
    return false
end

-- Guild Roster Manager's tag (#269): "[Floyd]" on an alt of Floyd, "[M]" on a main with alts, nil
-- on somebody with neither.
function AltRoster:ShortTag(key, links)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
    local m = links[key]
    if m then return "[" .. shortName(m) .. "]" end
    if self:HasAlts(key, links) then return GuildOS.L["[M]"] end
    return nil
end

-- roster: array of member keys present in the guild. Returns groups keyed
-- by canonical main, the count of unique mains (unique players) and total
-- chars observed.
function AltRoster:BuildTrueRoster(roster, links)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
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

-- Which character of each alt group runs GuildOS (#general on Discord: alts showed as "no addon" though the
-- player's main runs it): carriers[main] = the key in that group whose GuildOS this client heard most recently
-- (a `lastUpdate` in db.members), for every group that has one; a character linked to nobody is its own group.
-- One pass over the links and the members, so a whole roster reads it once.
function AltRoster:AddonCarriers(links, members)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
    members = members or (GuildOS.db and GuildOS.db.members) or {}
    local out, at = {}, {}
    for key, d in pairs(members) do
        local heard = type(d) == "table" and tonumber(d.lastUpdate) or 0
        if heard > 0 then
            local main = links[key]
            if type(main) ~= "string" or main == "" then main = key end
            if not at[main] or heard > at[main] then out[main], at[main] = key, heard end
        end
    end
    return out
end

-- The character of `key`'s group that runs GuildOS (AddonCarriers, or a map from it), or nil: `key` itself
-- when its own GuildOS was heard.
function AltRoster:AddonCarrier(key, carriers, links, members)
    links = links or (GuildOS.db and GuildOS.db.altLinks) or {}
    members = members or (GuildOS.db and GuildOS.db.members) or {}
    local own = members[key]
    if type(own) == "table" and (tonumber(own.lastUpdate) or 0) > 0 then return key end
    carriers = carriers or self:AddonCarriers(links, members)
    local main = links[key]
    if type(main) ~= "string" or main == "" then main = key end
    return carriers[main]
end

----------------------------------------------------------------------
-- Live wrappers
----------------------------------------------------------------------
function GuildOS:GetAltTag(key)
    return AltRoster:GetAltTag(key)
end

function GuildOS:GetTrueRoster()
    local roster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then
            local short = full:match("^([^-]+)") or full
            local realm = full:match("-(.+)$") or GetRealmName()
            roster[#roster + 1] = GuildOS:GetPlayerKey(short, realm)
        end
    end
    return AltRoster:BuildTrueRoster(roster)
end

-- GetTrueRoster's two counts alone (unique players, characters), with no table a member: the roster's tiles
-- read them at every refresh (memory audit, memoria.md).
local countSeen = {}
function GuildOS:TrueRosterCounts()
    local links = (GuildOS.db and GuildOS.db.altLinks) or {}
    for k in pairs(countSeen) do countSeen[k] = nil end
    local unique, total = 0, 0
    for i = 1, GetNumGuildMembers() or 0 do
        local full = GetGuildRosterInfo(i)
        if full then
            local short = full:match("^([^-]+)") or full
            local key = GuildOS:GetPlayerKey(short, full:match("-(.+)$") or GetRealmName())
            local main = links[key] or key
            total = total + 1
            if not countSeen[main] then countSeen[main], unique = true, unique + 1 end
        end
    end
    return unique, total
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function AltRoster:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
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
