----------------------------------------------------------------------
-- Guild OS - Founding (issue #208, guildos.me #240)
--
-- On WoW: Forever every guild is born from nothing, on or after the launch (4 Nov 2026). The GM
-- records the day the guild was founded; everyone who joined within the 14 days after it is a
-- founding member, and the GM always is. guildos.me keeps it in the guild's book (payload v12).
--
--   `founding` (officer domain): the founding itself, highest revision wins; and an officer's
--     suggested date for the GM.
--   `foundingSelf` (member domain, guild channel only): each client says when its own character
--     joined, and nobody else's — the founders are worked out from those claims, never sent.
--
-- WoW: Forever only.
----------------------------------------------------------------------
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

local Founding = {}
GuildOS.Founding = Founding

local Compat = GuildOS.Compat

local DAY = 86400
Founding.FIRST_DAY = 1793750400   -- 2026-11-04 00:00 UTC: launch day, the earliest a guild was founded
Founding.WINDOW_DAYS = 14
local SKEW = 600                   -- a client's clock a little ahead is a clock
local PUBLISH_DELAY = 20           -- seconds after login: the guild channel is up by then
local LATER_S = DAY                -- "Later" puts the letter away for a day
local LATER_MAX = 3                -- and after three, it waits in Settings

local function dayOf(t) return t - t % DAY end

local function myKey() return GuildOS:GetPlayerKey(Compat.PlayerName()) end

local function senderKey(sender)
    local short = sender:match("^([^-]+)") or sender
    return GuildOS:GetPlayerKey(short, sender:match("-(.+)$"))
end

local function isInt(v) return type(v) == "number" and v == math.floor(v) end

-- A founding day: 00:00 UTC, not before the launch, not after today.
function Founding.ValidDay(t, now)
    return isInt(t) and t == dayOf(t) and t >= Founding.FIRST_DAY and t <= dayOf(now)
end

-- The last second a founding member may join: the end of the 14th day after the founding day.
function Founding.WindowEnd(foundedAt)
    return foundedAt + (Founding.WINDOW_DAYS + 1) * DAY - 1
end

function Founding:Initialize()
    GuildOS.db.foundingJoins = GuildOS.db.foundingJoins or {}
    GuildOS.db.foundingPrompt = GuildOS.db.foundingPrompt or { later = 0, untilAt = 0 }
    if GuildOS.SyncService then
        GuildOS.SyncService:On("founding", function(env, sender) Founding:OnSync(env, sender) end)
        GuildOS.SyncService:On("foundingSelf", function(env, sender) Founding:OnSelf(env, sender) end)
    end
    Compat.After(PUBLISH_DELAY, function() Founding:PublishSelf() end)
end

function Founding:Get() return GuildOS.db and GuildOS.db.founding end

function Founding:IsGM()
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

----------------------------------------------------------------------
-- The date the letter offers: the earliest the GuildOS saw anybody of today's roster (the game
-- says nothing of when somebody joined, guildos.me #240), never before the launch; else today.
----------------------------------------------------------------------
function Founding:SuggestedDay(now)
    local s = GuildOS.db.foundingSuggested
    if s and Founding.ValidDay(s.foundedAt, now) then return s.foundedAt, "declared" end
    -- `firstSeen` holds today's roster: whoever left had theirs dropped (1.0.2, DropDeparted).
    local earliest
    for _, t in pairs(GuildOS.db.firstSeen or {}) do
        if type(t) == "number" and (not earliest or t < earliest) then earliest = t end
    end
    if earliest then return math.max(Founding.FIRST_DAY, math.min(dayOf(earliest), dayOf(now))), "firstSeen" end
    return dayOf(now), "declared"
end

-- The GM records it (or corrects it). Returns whether it was taken.
function Founding:Record(foundedAt, source)
    local now = GetServerTime()
    if not self:IsGM() or not Founding.ValidDay(foundedAt, now) then return false end
    local old = self:Get()
    GuildOS.db.founding = {
        foundedAt = foundedAt,
        source = source or "declared",
        declaredBy = myKey(),
        recordedAt = now,
        windowDays = Founding.WINDOW_DAYS,
        manual = old and old.manual or {},
        revision = (old and old.revision or 0) + 1,
    }
    GuildOS.db.foundingSuggested = nil
    self:Publish()
    return true
end

-- An officer who is not the GM suggests a day; the GM's letter offers it.
function Founding:Suggest(foundedAt)
    if self:IsGM() or not GuildOS:IsOfficer() or not Founding.ValidDay(foundedAt, GetServerTime()) then return false end
    if GuildOS.SyncService then GuildOS.SyncService:Publish("founding", "suggest", { foundedAt = foundedAt }) end
    return true
end

function Founding:Publish()
    local f = self:Get()
    if f and GuildOS.SyncService then GuildOS.SyncService:Publish("founding", "set", { founding = f }, { rev = f.revision }) end
end

-- From an officer (SyncService checked the officer and the guild channel).
function Founding:OnSync(env, sender)
    local d = type(env.data) == "table" and env.data or nil
    if not d then return end
    local now = GetServerTime()
    if env.act == "suggest" then
        if Founding.ValidDay(d.foundedAt, now) then
            GuildOS.db.foundingSuggested = { foundedAt = d.foundedAt, by = senderKey(sender) }
        end
        return
    end
    if env.act ~= "set" then return end
    local f = type(d.founding) == "table" and d.founding or nil
    if not f or not Founding.ValidDay(f.foundedAt, now + SKEW) or not isInt(f.revision) or f.revision < 1 then return end
    local held = self:Get()
    if held and f.revision <= (held.revision or 0) then return end
    GuildOS.db.founding = {
        foundedAt = f.foundedAt,
        source = type(f.source) == "string" and f.source or "declared",
        declaredBy = type(f.declaredBy) == "string" and GuildOS:LocalMemberKey(f.declaredBy) or nil,
        recordedAt = isInt(f.recordedAt) and f.recordedAt or now,
        windowDays = Founding.WINDOW_DAYS,
        manual = type(f.manual) == "table" and f.manual or {},
        revision = f.revision,
    }
end

----------------------------------------------------------------------
-- When my own character joined: the only claim a client makes (guildos.me #240). The game does not
-- say, so it is when the GuildOS first saw me in this guild, until a probe finds better (#214).
----------------------------------------------------------------------
function Founding:MyJoinedAt()
    local t = GuildOS:GetFirstSeen(myKey())
    return isInt(t) and t > 0 and t or nil, "firstSeen"
end

function Founding:PublishSelf()
    local t, src = self:MyJoinedAt()
    if not t then return end
    GuildOS.db.foundingJoins[myKey()] = { joinedAt = t, src = src }
    if GuildOS.SyncService then GuildOS.SyncService:Publish("foundingSelf", "join", { joinedAt = t, src = src }) end
end

-- A member's claim about themselves: filed under who sent it, never a key the payload names.
function Founding:OnSelf(env, sender)
    local d = type(env.data) == "table" and env.data or nil
    if not d or type(sender) ~= "string" or sender == "" then return end
    if not isInt(d.joinedAt) or d.joinedAt <= 0 or d.joinedAt > GetServerTime() + SKEW then return end
    GuildOS.db.foundingJoins[senderKey(sender)] = { joinedAt = d.joinedAt, src = d.src == "club" and "club" or "firstSeen" }
end

----------------------------------------------------------------------
-- The founding members, worked out the same way on every client: the GM, everyone the guild roster
-- holds whose join date (their own claim, else when this client first saw them) is within the
-- window, and the GM's manual additions. Key -> { joinedAt, src }.
----------------------------------------------------------------------
function Founding:Founders()
    local f = self:Get()
    if not f then return {} end
    local out, last = {}, Founding.WindowEnd(f.foundedAt)
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name then
            local key = GuildOS:GetPlayerKey(name:match("^([^-]+)") or name, name:match("-(.+)$"))
            local claim = GuildOS.db.foundingJoins[key]
            local joinedAt, src = claim and claim.joinedAt, claim and claim.src
            if not joinedAt then joinedAt, src = GuildOS:GetFirstSeen(key), "firstSeen" end
            if rankIndex == 0 or (joinedAt and joinedAt <= last) or (f.manual and f.manual[key]) then
                out[key] = { joinedAt = joinedAt or f.foundedAt, src = src or "firstSeen" }
            end
        end
    end
    return out
end

function Founding:IsFounder(key)
    return self:Founders()[key] ~= nil
end

-- What the companion export carries (payload v12): the founding, with founders as a list.
function Founding:ForExport()
    local f = self:Get()
    if not f then return nil end
    local founders, manual = {}, {}
    for key, v in pairs(self:Founders()) do founders[#founders + 1] = { key = key, joinedAt = v.joinedAt, src = v.src } end
    table.sort(founders, function(a, b) return a.key < b.key end)
    for key, m in pairs(f.manual or {}) do
        if type(m) == "table" then manual[#manual + 1] = { key = key, by = m.by, reason = m.reason, at = m.at } end
    end
    return {
        foundedAt = f.foundedAt, source = f.source, declaredBy = f.declaredBy, recordedAt = f.recordedAt,
        windowDays = f.windowDays, founders = founders, manual = manual, revision = f.revision,
    }
end

-- My own claim for the export's member row; nobody else's.
function Founding:JoinedAtOf(key)
    local c = GuildOS.db.foundingJoins and GuildOS.db.foundingJoins[key]
    return c and c.joinedAt or nil
end

----------------------------------------------------------------------
-- The letter (UI/Founding.lua): to the GM, while nothing is recorded, at most three times a day apart.
----------------------------------------------------------------------
function Founding:ShouldPrompt(now)
    if not IsInGuild() or self:Get() or not self:IsGM() then return false end
    local p = GuildOS.db.foundingPrompt
    return (p.later or 0) < LATER_MAX and now >= (p.untilAt or 0)
end

function Founding:Later(now)
    local p = GuildOS.db.foundingPrompt
    p.later = (p.later or 0) + 1
    p.untilAt = now + LATER_S
end
