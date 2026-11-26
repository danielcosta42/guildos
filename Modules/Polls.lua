----------------------------------------------------------------------
-- Guild OS - Polls / Voting
-- Officers create a poll; members vote. Polls are broadcast via
-- SyncService (domain "poll"): "create"/"close" are officer actions,
-- "vote" is a member action recorded per voter on every client.
----------------------------------------------------------------------
local Polls = {}
GuildOS.Polls = Polls
local L = GuildOS.L

function Polls:Initialize()
    GuildOS.db.polls = GuildOS.db.polls or { list = {} }
    GuildOS.db.polls.list = GuildOS.db.polls.list or {}
    if GuildOS.SyncService then
        GuildOS.SyncService:On("poll", function(env, sender) Polls:OnSync(env, sender) end)
    end
end

function Polls:GetList() return GuildOS.db.polls.list end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

local function keyOf(name)
    local short = (name or ""):match("^([^-]+)") or name
    -- Retail: the sender's own realm, or two connected-realm namesakes are one person (ADR-0026).
    local realm = GuildOS.Client.isRetail and (name or ""):match("^[^-]+%-(.+)$") or GetRealmName()
    return GuildOS:GetPlayerKey(short, realm)
end

-- Sorted polls: open first, then newest.
function Polls:GetSorted()
    local list = {}
    for _, p in pairs(self:GetList()) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        if (a.closed and true or false) ~= (b.closed and true or false) then return not a.closed end
        return (a.ts or 0) > (b.ts or 0)
    end)
    return list
end

----------------------------------------------------------------------
-- Mutations
----------------------------------------------------------------------
function Polls:Create(question, options)
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    question = strtrim(question or "")
    if question == "" or type(options) ~= "table" or #options < 2 then
        GuildOS:Print(L["A poll needs a question and at least 2 options."])
        return
    end
    local p = {
        id = newId(), question = question, options = options, votes = {},
        author = GuildOS.Compat.PlayerName(), ts = GetServerTime(), closed = false,
    }
    self:GetList()[p.id] = p
    if GuildOS.SyncService then
        local rev = GuildOS.SyncService:NextRevision("poll", p.id)
        GuildOS.SyncService:Publish("poll", "create", { poll = {
            id = p.id, question = p.question, options = p.options, author = p.author, ts = p.ts,
        } }, { rev = rev })
    end
    self:Refresh()
end

function Polls:Vote(id, opt)
    local p = self:GetList()[id]
    if not p or p.closed then return end
    p.votes = p.votes or {}
    p.votes[keyOf(GuildOS.Compat.PlayerName())] = opt
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("poll", "vote", { id = id, opt = opt })
    end
    self:Refresh()
end

function Polls:Close(id)
    if not GuildOS:IsOfficer() then return end
    local p = self:GetList()[id]
    if not p then return end
    p.closed = true
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("poll", "close", { id = id })
    end
    self:Refresh()
end

----------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------
function Polls:OnSync(env, sender)
    local d = env.data
    if env.act == "create" and d and d.poll then
        local p = d.poll
        if GuildOS.SyncService:ShouldApply("poll", p.id, env.rev) then
            local existing = self:GetList()[p.id]
            p.votes = (existing and existing.votes) or {}
            self:GetList()[p.id] = p
            GuildOS.SyncService:SetRevision("poll", p.id, env.rev)
            self:Refresh()
        end
    elseif env.act == "close" and d and d.id then
        local p = self:GetList()[d.id]
        if p then p.closed = true; self:Refresh() end
    elseif env.act == "vote" and d and d.id and d.opt then
        local p = self:GetList()[d.id]
        if p and not p.closed then
            p.votes = p.votes or {}
            p.votes[keyOf(sender)] = d.opt
            self:Refresh()
        end
    end
end

function Polls:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
-- The notices and the polls are one board, the Salão's Notices (audit B24): no window of their own.
function Polls:Show()
    GuildOS.UI:OpenWindow("guild", "bulletin")
end
