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
    -- Where the journal exists (WoW: Forever) the cap comes from it, written by whoever dinged: one
    -- source, not two (audit B24).
    if not GuildOS.Journal and prevLevel and prevLevel < cap and (data.level or 0) >= cap then
        self:Record("ding", key, name, tostring(cap))
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
-- What happened since `since`, as data (#449: the Chronicle's Activity draws it in categories, the login
-- digest says it in lines). `told` is what guildos.me says in this digest (guildos-web #259): a ding it tells is
-- not told twice. Returns
--   dings          { key, name, at } newest first, each person once, whichever source told it
--   attunes        { key, name, at } newest first, each person once
--   levels         { level, names } highest level first, each person once per level
--   clears         { id, name, names, first } a dungeon's clears, each person once; first: the guild's first of it
--   anniversaries  { key, name, years }
----------------------------------------------------------------------
local function short(k) return (k:match("^(.-)%-[^-]*$") or k) end

function Milestones:Collect(since, told)
    since = since or 0
    local m = { dings = {}, attunes = {}, levels = {}, clears = {}, anniversaries = {} }
    local dinged, attuned = {}, {}
    local function isTold(key, k)
        return told ~= nil and (told["member.level60|" .. tostring(key)] or told["member.level60|" .. tostring(k)]) and true or false
    end
    -- The cap comes from two places (#449): the fifty events (a ding seen in synced member data, written before
    -- audit B24, or where there is no journal) and WoW: Forever's journal. Merged by the member's key, each once:
    -- before, a ding both held was told twice, the same names in two runs one under the other.
    local function ding(key, name, at)
        local k = GuildOS:LocalMemberKey(key)
        if type(k) ~= "string" or dinged[k] or isTold(key, k) then return end
        dinged[k] = true
        m.dings[#m.dings + 1] = { key = k, name = name or short(k), at = at or 0 }
    end

    for _, ev in ipairs((GuildOS.db.milestones and GuildOS.db.milestones.events) or {}) do
        if (ev.ts or 0) > since and ev.key then
            if ev.type == "ding" then
                ding(ev.key, ev.name, ev.ts)
            elseif ev.type == "attune" then
                local k = GuildOS:LocalMemberKey(ev.key)
                if not attuned[k] then
                    attuned[k] = true
                    m.attunes[#m.attunes + 1] = { key = k, name = ev.name or short(k), at = ev.ts or 0 }
                end
            end
        end
    end

    -- WoW: Forever's journal (issue #211): the milestones every ten levels and the dungeon clears, grouped by
    -- level and by dungeon, each person once. Read from the journal, which keeps a month of them, not from the
    -- fifty events above, which a launch week would flood.
    local levels, clears = {}, {}
    local firsts = GuildOS.db.journal and GuildOS.db.journal.firsts or {}
    for _, e in ipairs(GuildOS.Journal and GuildOS.Journal:GetSince(since) or {}) do
        local k = GuildOS:LocalMemberKey(e.subjectKey)
        if e.type == "member.level60" then
            ding(e.subjectKey, short(k), e.at)
        elseif e.type == "member.level" and e.data.level then
            local g = levels[e.data.level] or { level = e.data.level, who = {} }
            levels[e.data.level] = g
            g.who[k] = true
        elseif e.type == "dungeon.clear" then
            local id = e.data.dungeonId or e.data.dungeonName
            local g = clears[id] or { id = id, name = e.data.dungeonName or id, who = {} }
            clears[id] = g
            g.who[k] = true
            local f = firsts[id]
            if f and f.at > since and math.abs((e.at or 0) - f.at) <= 120 then g.first = true end
        end
    end
    local function names(who)
        local out = {}
        for k in pairs(who) do out[#out + 1] = short(k) end
        table.sort(out)
        return out
    end
    for _, g in pairs(levels) do m.levels[#m.levels + 1] = { level = g.level, names = names(g.who) } end
    table.sort(m.levels, function(a, b) return a.level > b.level end)
    for _, g in pairs(clears) do m.clears[#m.clears + 1] = { id = g.id, name = g.name, names = names(g.who), first = g.first } end
    table.sort(m.clears, function(a, b) return tostring(a.name) < tostring(b.name) end)
    table.sort(m.dings, function(a, b) return a.at > b.at end)
    table.sort(m.attunes, function(a, b) return a.at > b.at end)

    -- Guild anniversaries: first-seen date crossed a whole-year boundary since `since`.
    local now = GetServerTime()
    for key, ts in pairs(GuildOS.db.firstSeen or {}) do
        if ts and ts > 0 then
            local yNow = math.floor((now - ts) / YEAR)
            local ySince = math.floor((math.max(since, ts) - ts) / YEAR)
            if yNow >= 1 and yNow > ySince then
                m.anniversaries[#m.anniversaries + 1] = { key = key, name = key:match("^([^-]+)") or key, years = yNow }
            end
        end
    end
    table.sort(m.anniversaries, function(a, b) return a.name < b.name end)
    return m
end

-- The lines of what Collect returned, by category: levels (the cap, attunements, every ten levels), dungeons
-- (the clears) and members (the anniversaries).
function Milestones:Lines(m)
    local cap = tostring(GuildOS.Client.maxLevel)
    local out = { levels = {}, dungeons = {}, members = {} }
    local function add(cat, line) out[cat][#out[cat] + 1] = line end
    for _, d in ipairs(m.dings) do add("levels", string.format(L["%s reached level %s!"], d.name, cap)) end
    for _, a in ipairs(m.attunes) do add("levels", string.format(L["%s completed a new attunement"], a.name)) end
    for _, g in ipairs(m.levels) do
        local n = #g.names
        add("levels", n <= NAMED and string.format(L["Level %s reached by %s"], tostring(g.level), table.concat(g.names, ", "))
            or string.format(L["%d members reached level %s"], n, tostring(g.level)))
    end
    for _, g in ipairs(m.clears) do
        local n = #g.names
        add("dungeons", n <= NAMED and string.format(L["Dungeon cleared — %s: %s"], g.name, table.concat(g.names, ", "))
            or string.format(L["Dungeon cleared — %s: %d members"], g.name, n))
    end
    for _, a in ipairs(m.anniversaries) do
        add("members", string.format(L["%s is celebrating %d year(s) with the guild!"], a.name, a.years))
    end
    return out
end

-- Digest lines for milestones + guild anniversaries since `since`, in one list.
function Milestones:GetDigestLines(since, told)
    local by = self:Lines(self:Collect(since, told))
    local out = {}
    for _, cat in ipairs({ "levels", "dungeons", "members" }) do
        for _, line in ipairs(by[cat]) do out[#out + 1] = line end
    end
    return out
end
