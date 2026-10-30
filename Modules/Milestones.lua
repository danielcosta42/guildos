----------------------------------------------------------------------
-- Guild OS - Milestones & Anniversaries
-- Detects guildmate milestones from synced data (dinged the level cap, completed a
-- new attunement) and guild-join anniversaries (from first-seen). These
-- surface in the login digest. Detection is fed by DataCollector when it
-- stores received member data.
----------------------------------------------------------------------
local Milestones = {}
GuildOS.Milestones = Milestones
local L = GuildOS.L

local MAX = 50
local YEAR = 365 * 86400
local NAMED = 3   -- names in one digest line; past that, a count
local FOREVER = not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail

function Milestones:Initialize()
    GuildOS.db.milestones = GuildOS.db.milestones or { events = {} }
    GuildOS.db.milestones.events = GuildOS.db.milestones.events or {}
end

function Milestones:Record(mtype, key, name, detail)
    if not GuildOS.db.milestones then return end
    local ev = GuildOS.db.milestones.events
    table.insert(ev, 1, { type = mtype, key = key, name = name, detail = detail, ts = GetServerTime() })
    while #ev > MAX do table.remove(ev) end
end

----------------------------------------------------------------------
-- Called by DataCollector after storing received member data.
-- `prevLevel` / `prevAttune` are the pre-merge values; `hadPrior` is
-- false on the first sync of a member (so we don't fire for everyone).
----------------------------------------------------------------------
function Milestones:Check(key, data, prevLevel, prevAttune, hadPrior)
    if not hadPrior or not data then return end
    local name = data.name or (key:match("^([^-]+)") or key)

    local cap = GuildOS.Client.maxLevel
    if prevLevel and prevLevel < cap and (data.level or 0) >= cap then
        self:Record("ding", key, name, tostring(cap))
    elseif FOREVER and prevLevel and math.floor((data.level or 0) / 10) > math.floor(prevLevel / 10) then
        -- WoW: Forever's journal milestones, every ten levels below the cap (issue #211): the highest
        -- one crossed, as guildos.me counts them.
        self:Record("level", key, name, tostring(math.floor(data.level / 10) * 10))
    end

    local newCount = 0
    if data.attunements then
        for _, a in ipairs(data.attunements) do
            if a.complete then newCount = newCount + 1 end
        end
    end
    if prevAttune and newCount > prevAttune then
        self:Record("attune", key, name, tostring(newCount))
    end
end

----------------------------------------------------------------------
-- Digest lines for milestones + guild anniversaries since `since`.
----------------------------------------------------------------------
function Milestones:GetDigestLines(since)
    since = since or 0
    local out = {}

    local byLevel, levels = {}, {}
    for _, ev in ipairs((GuildOS.db.milestones and GuildOS.db.milestones.events) or {}) do
        if (ev.ts or 0) > since then
            if ev.type == "ding" then
                out[#out + 1] = string.format(L["%s reached level %s!"], ev.name or "?", ev.detail or tostring(GuildOS.Client.maxLevel))
            elseif ev.type == "attune" then
                out[#out + 1] = string.format(L["%s completed a new attunement"], ev.name or "?")
            elseif ev.type == "level" and ev.detail then
                if not byLevel[ev.detail] then byLevel[ev.detail] = {}; levels[#levels + 1] = ev.detail end
                table.insert(byLevel[ev.detail], ev.name or "?")
            end
        end
    end
    -- The journal's milestones, one line per level: a few names, or how many (issue #211).
    table.sort(levels, function(a, b) return tonumber(a) > tonumber(b) end)
    for _, lv in ipairs(levels) do
        local names = byLevel[lv]
        table.sort(names)
        out[#out + 1] = #names <= NAMED and string.format(L["%s reached level %s!"], table.concat(names, ", "), lv)
            or string.format(L["%d members reached level %s"], #names, lv)
    end

    -- Guild anniversaries: first-seen date crossed a whole-year boundary
    -- since the last login.
    local now = GetServerTime()
    for key, ts in pairs(GuildOS.db.firstSeen or {}) do
        if ts and ts > 0 then
            local yNow = math.floor((now - ts) / YEAR)
            local ySince = math.floor((math.max(since, ts) - ts) / YEAR)
            if yNow >= 1 and yNow > ySince then
                local nm = key:match("^([^-]+)") or key
                out[#out + 1] = string.format(L["%s is celebrating %d year(s) with the guild!"], nm, yNow)
            end
        end
    end

    return out
end
