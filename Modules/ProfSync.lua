----------------------------------------------------------------------
-- Guild OS - Profession sync (WoW: Forever, issue #31)
--
-- The "prof" SyncService domain. A member announces a summary: rank, max, specialization
-- and a hash of the recipe list, per profession. A guildmate whose stored hash differs asks
-- for that one list; the crafter answers once, by whisper, or on the guild channel when
-- several asked within a few seconds. Lists travel once per change, never on a timer.
--
--   sum   GUILD          { p = { [line] = { r, m, s, h, n } } }
--   ask   GUILD          {}                           everyone answers with its own sum
--   req   WHISPER        { l = { line, ... } }
--   list  WHISPER|GUILD  { l = line, h = hash, r = { ids }, x = { extra ids } }
----------------------------------------------------------------------
if BRutus.Client.isAnniversary then return end

local ProfSync = {}
BRutus.ProfSync = ProfSync

local Compat = BRutus.Compat
local DOMAIN = "prof"
ProfSync.SUMMARY_EVERY = 600   -- heartbeat summary
ProfSync.CHANGE_DELAY = 10     -- one summary for a burst of changes
ProfSync.AGGREGATE = 3         -- requests for a line gathered before answering
ProfSync.REASK_AFTER = 120     -- a list that never came is asked for again

function ProfSync:Initialize()
    self.asked = {}      -- [sender .. ":" .. line] = { h = hash, at = time }
    self.outgoing = {}   -- [line] = { [requester] = true }
    BRutus.SyncService:On(DOMAIN, function(env, sender) ProfSync:OnEnvelope(env, sender) end)
    Compat.After(math.random(5, 15), function()
        ProfSync:PublishSummary()
        BRutus.SyncService:Publish(DOMAIN, "ask", {})
    end)
    Compat.NewTicker(self.SUMMARY_EVERY, function() ProfSync:PublishSummary() end)
end

function ProfSync:PublishSummary()
    self.summaryPending = false
    BRutus.SyncService:Publish(DOMAIN, "sum", { p = BRutus.Professions:OwnSummary() })
end

function ProfSync:ScheduleSummary(delay)
    if self.summaryPending then return end
    self.summaryPending = true
    Compat.After(delay or self.CHANGE_DELAY, function() self:PublishSummary() end)
end

-- The member key of a guildmate sender, or nil when the sender is not in the guild roster.
-- The key comes from who sent the message, never from what it says.
function ProfSync:SenderKey(sender)
    if type(sender) ~= "string" then return nil end
    local short = sender:match("^([^-]+)") or sender
    local suffix = sender:match("-(.+)$")
    if not BRutus:GetMemberRecord(short, suffix) then return nil end
    return BRutus:GetPlayerKey(short, (not BRutus:GetClientRealm()) and suffix or nil)
end

function ProfSync:OnEnvelope(env, sender)
    local key = self:SenderKey(sender)
    local data = env and env.data
    if not key or type(data) ~= "table" then return end
    if env.act == "sum" then
        self:OnSummary(key, sender, data.p)
    elseif env.act == "ask" then
        self:ScheduleSummary(math.random(1, 8))
    elseif env.act == "req" then
        self:OnRequest(sender, data.l)
    elseif env.act == "list" then
        BRutus.Professions:ApplyList(key, data.l, data.h, data.r, data.x)
    end
end

function ProfSync:OnSummary(key, sender, p)
    local need = BRutus.Professions:ApplySummary(key, p)
    if not need or #need == 0 then return end
    local rec = BRutus.Professions:Get(key)
    local now = GetServerTime()
    local ask = {}
    for _, line in ipairs(need) do
        local tag = sender .. ":" .. line
        local h = rec.profs[line].h
        local a = self.asked[tag]
        if not a or a.h ~= h or now - a.at > self.REASK_AFTER then
            self.asked[tag] = { h = h, at = now }
            ask[#ask + 1] = line
        end
    end
    if #ask == 0 then return end
    Compat.After(math.random(2, 6), function()
        BRutus.SyncService:Publish(DOMAIN, "req", { l = ask }, { target = sender })
    end)
end

function ProfSync:OnRequest(sender, lines)
    if type(lines) ~= "table" or #lines > BRutus.Professions.MAX_LINES then return end
    for _, line in ipairs(lines) do
        if type(line) == "number" and BRutus.Professions:OwnLine(line) then
            local waiting = self.outgoing[line]
            if not waiting then
                waiting = {}
                self.outgoing[line] = waiting
                Compat.After(self.AGGREGATE, function() self:FlushLine(line) end)
            end
            waiting[sender] = true
        end
    end
end

-- Answer everyone who asked for a line: a whisper for one, the guild channel for several.
function ProfSync:FlushLine(line)
    local waiting = self.outgoing[line]
    self.outgoing[line] = nil
    local e = BRutus.Professions:OwnLine(line)
    if not (waiting and e and e.recipes) then return end
    local only, count = nil, 0
    for name in pairs(waiting) do
        only, count = name, count + 1
    end
    BRutus.SyncService:Publish(DOMAIN, "list", { l = line, h = e.h, r = e.recipes, x = e.extra or {} },
        { target = count == 1 and only or nil })
end
