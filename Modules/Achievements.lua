----------------------------------------------------------------------
-- Guild OS - Achievements (issue #216, guildos.me #245)
--
-- What the guild earned, as guildos.me says it through the inbox (GOSGILD1). Titles come ready in the
-- guild's language, so this holds no catalogue and judges no rule: it reads and shows.
--
-- WoW: Forever only.
----------------------------------------------------------------------
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

local Achievements = {}
GuildOS.Achievements = Achievements
local L = GuildOS.L

local DIGEST_NEW = 3   -- new ones named in one digest

local function plain(text) return GuildOS.CompanionImport.Inert(text) end

-- The block's part, or nil: no companion, no site, or nothing earned or measured yet.
function Achievements:Data()
    local block = GuildOS.CompanionImport and GuildOS.CompanionImport:GuildBlock()
    local a = block and block.achievements
    return type(a) == "table" and a or nil
end

function Achievements:Renown()
    local a = self:Data()
    return a and tonumber(a.level) or nil, a and tonumber(a.renown) or 0
end

-- What was earned, the newest first, each { title, at, key }. A row the site sent badly is dropped.
function Achievements:Earned()
    local a, out = self:Data(), {}
    for _, e in ipairs(a and type(a.earned) == "table" and a.earned or {}) do
        if type(e) == "table" and type(e.title) == "string" then
            out[#out + 1] = {
                title = plain(e.title),
                at = tonumber(e.at) or 0,
                key = type(e.key) == "string" and GuildOS:LocalMemberKey(e.key) or nil,
            }
        end
    end
    return out
end

-- The nearest to done, each { title, current, target }.
function Achievements:Next()
    local a, out = self:Data(), {}
    for _, e in ipairs(a and type(a.next) == "table" and a.next or {}) do
        local current, target = type(e) == "table" and tonumber(e.current), type(e) == "table" and tonumber(e.target)
        if current and target and target > 0 and type(e.title) == "string" then
            out[#out + 1] = { title = plain(e.title), current = current, target = target }
        end
    end
    return out
end

-- A member's own, for their roster tooltip.
function Achievements:Of(key)
    local out = {}
    for _, e in ipairs(self:Earned()) do
        if e.key == key then out[#out + 1] = e.title end
    end
    return out
end

-- The login digest: what is new since the last login, and the nearest.
function Achievements:GetDigestLines(since)
    local out = {}
    for _, e in ipairs(self:Earned()) do
        if e.at > (since or 0) and #out < DIGEST_NEW then
            out[#out + 1] = string.format(L["Achievement: %s"], e.title)
        end
    end
    local nearest = self:Next()[1]
    if nearest then
        out[#out + 1] = string.format(L["Next: %s (%d/%d)"], nearest.title, nearest.current, nearest.target)
    end
    return out
end
