----------------------------------------------------------------------
-- Guild OS - My quests in the guild LFG (issue #450)
-- The player's quest log, as the Groups tab's "My quests" cards: group, elite and dungeon quests first.
-- Read through Compat.QuestLog, again a moment after QUEST_LOG_UPDATE (the event comes in bursts; one
-- read answers them all, and the event itself makes no garbage).
--
-- Privacy: the log never crosses the wire. A listing carries only the quests the player picked (id and
-- title, capped), and, with the opt-in "share" preference (off by default), up to SHARE_MAX ids of the
-- group quests in the log. Every client compares what it hears with its own log, locally.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Q = { list = {}, byId = {}, raw = {} }
GuildOS.GroupQuests = Q

Q.PICK_MAX = 3          -- quests one "I am looking" listing names
Q.SHARE_MAX = 8         -- ids of group quests the opt-in shares
Q.TITLE_MAX = 48        -- bytes of a quest's title on the wire
local ID_MAX = 16777215 -- a quest id is a positive integer under 2^24
local REFRESH_DELAY = 1 -- seconds from the first QUEST_LOG_UPDATE of a burst to the read

local pending, lastSig = false, nil

local function wipe(t) for k in pairs(t) do t[k] = nil end end

-- Group quests first, the log's order otherwise.
local function before(a, b)
    if a.group ~= b.group then return a.group end
    return a.order < b.order
end

-- Read the log now. Returns whether the quests in it changed since the last read.
function Q:Refresh()
    local raw, n = GuildOS.Compat.QuestLog(self.raw)
    self.read = true
    local list, byId = self.list, self.byId
    wipe(byId)
    for i = #list, 1, -1 do list[i] = nil end
    local sig = 0
    for i = 1, n do
        local q = raw[i]
        if not byId[q.id] then
            byId[q.id] = q
            list[#list + 1] = q
            sig = (sig * 31 + q.id + (q.group and 7 or 0)) % 2147483647
        end
    end
    table.sort(list, before)
    sig = sig + #list * 1000003
    local changed = sig ~= lastSig
    lastSig = sig
    return changed
end

local function refreshNow()
    pending = false
    if Q:Refresh() and GuildOS.LFGBoard then GuildOS.LFGBoard:Refresh() end
end
Q._RefreshNow = refreshNow

local function onEvent()
    if pending then return end
    pending = true
    GuildOS.Compat.After(REFRESH_DELAY, refreshNow)
end
Q._OnEvent = onEvent

function Q:Initialize()
    if self.frame then return end
    self.frame = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(self.frame, "QUEST_LOG_UPDATE")
    self.frame:SetScript("OnEvent", onEvent)
end

-- The quests in my log, group ones first (read once on first ask).
function Q:List()
    if not self.read then self:Refresh() end
    return self.list
end

function Q:Get(id)
    if not self.read then self:Refresh() end
    return self.byId[id]
end

function Q:Has(id) return id ~= nil and self:Get(id) ~= nil end

-- A quest's title as I read it: my log's (in my language), else what the listing said.
function Q:Title(id, said)
    local q = self:Get(id)
    if q then return q.title end
    return (said and said ~= "") and said or GuildOS.L["A quest"]
end

-- The ids of group quests in my log, for the opt-in: up to SHARE_MAX, none of `skip` ({ {id} }).
function Q:SharedIds(skip)
    local out, seen = {}, {}
    for _, q in ipairs(skip or {}) do seen[q.id] = true end
    for _, q in ipairs(self:List()) do
        if #out >= self.SHARE_MAX then break end
        if q.group and not seen[q.id] then out[#out + 1] = q.id end
    end
    return out
end

-- Whether a listing (a seeker's entry) names quest `id`: picked, or shared from the log.
function Q:Lists(e, id)
    if not e or not id then return false end
    for _, q in ipairs(e.quests or {}) do if q.id == id then return true end end
    for _, x in ipairs(e.shared or {}) do if x == id then return true end end
    return false
end

-- The first quest a listing names that is in my log, or nil.
function Q:InMyLog(e)
    for _, q in ipairs(e and e.quests or {}) do if self:Has(q.id) then return q.id end end
    for _, x in ipairs(e and e.shared or {}) do if self:Has(x) then return x end end
    return nil
end

----------------------------------------------------------------------
-- Off the wire (pure, unit tested)
----------------------------------------------------------------------
function Q:_SanitizeId(v)
    if type(v) ~= "number" or v ~= v or v < 1 or v > ID_MAX or v ~= math.floor(v) then return nil end
    return v
end

-- One quest: { id, t } with a whole id and a plain title, or nil.
function Q:_SanitizeQuest(q)
    if type(q) ~= "table" then return nil end
    local id = self:_SanitizeId(q.id)
    if not id then return nil end
    local t = type(q.t) == "string" and GuildOS:SanitizeUserText(q.t, self.TITLE_MAX) or ""
    return { id = id, t = t }
end

-- Up to `max` quests, each once, in the order they came.
function Q:_SanitizeQuests(list, max)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    max = max or self.PICK_MAX
    for i = 1, max * 2 do
        local q = self:_SanitizeQuest(list[i])
        if q and not seen[q.id] and #out < max then
            seen[q.id] = true
            out[#out + 1] = q
        end
    end
    return out
end

-- Up to `max` ids, each once.
function Q:_SanitizeIds(list, max)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    max = max or self.SHARE_MAX
    for i = 1, max * 2 do
        local id = self:_SanitizeId(list[i])
        if id and not seen[id] and #out < max then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end
