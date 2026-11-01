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
local DRAWN = 6        -- the insignias this addon carries (Media/renown-<series>-<n>.tga)
local SERIES = { Horde = "renown-horde-", Alliance = "renown-alliance-" }

local function plain(text) return GuildOS.CompanionImport.Inert(text) end

-- The block's part, or nil: no companion, no site, or nothing earned or measured yet.
function Achievements:Data()
    if not GuildOS:IsFeatureEnabled("achievements") then return nil end
    local block = GuildOS.CompanionImport and GuildOS.CompanionImport:GuildBlock()
    local a = block and block.achievements
    return type(a) == "table" and a or nil
end

function Achievements:Renown()
    local a = self:Data()
    return a and tonumber(a.level) or nil, a and tonumber(a.renown) or 0
end

-- The level's insignia (guildos.me, specs/068): its texture, in the series of the character's faction, which
-- is the guild's, past what this addon carries the highest it has; and its title, ready in the guild's language.
-- The texture is nil with no faction to read, and either is nil when the site sent none, or sent it badly.
function Achievements:Insignia()
    local a = self:Data()
    local n = a and tonumber(a.insignia)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local series = not GuildOS.Compat.IsSecret(faction) and SERIES[faction]
    local tex = series and n and n >= 1 and ("Interface\\AddOns\\GuildOS\\Media\\" .. series .. math.min(DRAWN, math.floor(n))) or nil
    return tex, a and type(a.title) == "string" and plain(a.title) or nil
end

-- What was earned, the newest first, each { title, at, key }. A row the site sent badly is dropped.
function Achievements:Earned()
    local a, out = self:Data(), {}
    for _, e in ipairs(a and type(a.earned) == "table" and a.earned or {}) do
        if type(e) == "table" and type(e.title) == "string" then
            out[#out + 1] = {
                id = tostring(e.id),
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

-- What the login digest has not said yet. `at` is the fact's date, older than the upload that
-- told it, so it cannot be compared with the last login: each one is remembered instead. The first
-- time, all of them count as said: somebody installing the addon has no news of the guild's past.
function Achievements:Unseen()
    local seen = GuildOS.db.digest and GuildOS.db.digest.achievementsSeen
    local out = {}
    for _, e in ipairs(seen and self:Earned() or {}) do
        if not seen[e.id .. ":" .. e.at] then out[#out + 1] = e end
    end
    return out
end

function Achievements:MarkSeen()
    local digest = GuildOS.db.digest
    if not digest then return end
    digest.achievementsSeen = digest.achievementsSeen or {}
    for _, e in ipairs(self:Earned()) do digest.achievementsSeen[e.id .. ":" .. e.at] = true end
end

-- The login digest's new ones. `told` is what guildos.me says in this digest (guildos-web #259): a rare
-- one is a line of its feed too, and is not told twice.
function Achievements:GetDigestLines(told)
    local out = {}
    for _, e in ipairs(self:Unseen()) do
        if #out < DIGEST_NEW and not (told and told["achievement.earned|" .. e.at]) then
            out[#out + 1] = string.format(L["Achievement: %s"], e.title)
        end
    end
    return out
end

-- The nearest to done, for a digest that already has something to say.
function Achievements:NextLine()
    local nearest = self:Next()[1]
    return nearest and string.format(L["Next: %s (%d/%d)"], nearest.title, nearest.current, nearest.target) or nil
end
