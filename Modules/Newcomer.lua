----------------------------------------------------------------------
-- Guild OS - The newcomer's quarantine (issue #406, epic guildos-web#609)
--
-- Most of the spam and the gold selling in /g comes from somebody who just joined. For the guild's first
-- N days of a member (default 7, 0 to 30; 0 turns it off) the officers' alerts are stricter on them:
--   * any link outside the game is an alert (the anti-flood's links signal at one link, on even when the
--     guild switched it off);
--   * the anti-flood's other limits are stricter (lines at two thirds, 4 in 10 s by default; repeats at
--     half; never under two; capitals on lines of 70% the letters, 14 by default; audit B3);
--   * the alert carries the badge "newcomer (day X of N)".
-- A trial (TrialTracker) still running counts as a newcomer too, when the guild says so.
--
-- Where the join comes from: RosterLog, the game's "has joined the guild" line. A member whose join no
-- officer's client ever read (they were in the guild before the addon) is NOT a newcomer. The end of the
-- quarantine is the join plus N days, worked out every time and never stored, so a change of N moves
-- everybody's at once.
--
-- Assisted, never automatic, and never seen by the member: all of it runs on the officers' clients, inside
-- the alerts (ModAlerts, ModFlood), which a member's client never runs. Nothing new about anybody is kept:
-- it reads what RosterLog and TrialTracker already hold.
--
-- The guild's setting is the officers' (guildcfg "newcomer", newest stamp wins, as ModFlood's limits).
----------------------------------------------------------------------
local Newcomer = {}
GuildOS.Newcomer = Newcomer
local L = GuildOS.L

local DAY = 86400
Newcomer.DEFAULT_DAYS = 7
Newcomer.MIN_DAYS = 0
Newcomer.MAX_DAYS = 30
local STAMP_FUTURE_SLACK = 300

local function settings() return GuildOS.db and GuildOS.db.settings end

----------------------------------------------------------------------
-- Pure helpers (unit-tested via /gos selftest and tools/newcomer.lua)
----------------------------------------------------------------------
-- A length in whole days, 0 to 30, a number or digits typed in a box; nil otherwise (never clamped).
function Newcomer.ValidDays(v)
    if type(v) == "string" then
        if not v:match("^%s*%d+%s*$") then return nil end
        v = tonumber(v)
    end
    if type(v) ~= "number" or v ~= v or v ~= math.floor(v) then return nil end
    if v < Newcomer.MIN_DAYS or v > Newcomer.MAX_DAYS then return nil end
    return v
end

-- Which day of the quarantine `now` is for somebody who joined at `joinAt`: 1 on the day they joined, up to
-- `days` on the last one; nil once join + days has passed, when the join is unknown or when days is 0.
-- A join a little ahead of this clock (another officer's) reads as day 1.
function Newcomer.DayOf(joinAt, now, days)
    joinAt, now = GuildOS.Finite(joinAt), GuildOS.Finite(now)
    if not (joinAt and now and days and days > 0) then return nil end
    -- A join more than a few minutes past this clock is no join anybody saw: unknown, never a quarantine forever.
    if joinAt > now + 300 then return nil end
    if now >= joinAt + days * DAY then return nil end
    return math.floor(math.max(0, now - joinAt) / DAY) + 1
end

-- The anti-flood's limits for a newcomer (pure on `cfg`, a ModFlood.ValidConfig): links on at one link,
-- lines at two thirds and repeats at half (rounded up, at least two), capitals on lines of 70% of the letters
-- (rounded up, at least 5): 4 lines in 10 s and 14 letters on the guild's defaults (audit B3).
-- The percentages, the windows and the guild's switches of the other signals stay as they are.
function Newcomer.Strict(cfg)
    local out = {}
    for sig, c in pairs(cfg) do
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        out[sig] = copy
    end
    if out.burst then out.burst.n = math.max(2, math.ceil(out.burst.n * 2 / 3)) end
    if out["repeat"] then out["repeat"].n = math.max(2, math.ceil(out["repeat"].n / 2)) end
    if out.caps then out.caps.min = math.max(5, math.ceil(out.caps.min * 7 / 10)) end
    if out.links then out.links.on, out.links.n = true, 1 end
    return out
end

-- The badge an officer reads on the alert: "newcomer (day X of N)", or "newcomer (trial)".
function Newcomer.BadgeText(nc)
    if type(nc) ~= "table" then return nil end
    if nc.day then return string.format(L["newcomer (day %d of %d)"], nc.day, nc.of or nc.day) end
    if nc.trial then return L["newcomer (trial)"] end
    return nil
end

----------------------------------------------------------------------
-- The guild's setting
----------------------------------------------------------------------
-- The guild's length in days: the officers' choice, 7 until one is made.
function Newcomer:GetDays()
    local s = settings()
    local d = s and self.ValidDays(s.newcomerDays)
    if d == nil then return self.DEFAULT_DAYS end
    return d
end

-- Whether a running trial counts as a newcomer. Off until an officer turns it on.
function Newcomer:TrialCounts()
    local s = settings()
    return s ~= nil and s.newcomerTrial == true
end

-- An officer saves both. True, or false and "officer" or "range".
function Newcomer:SetConfig(days, trial)
    if not GuildOS:IsOfficer() then return false, "officer" end
    -- The first save on the rules tab makes this officer's list the guild's one list (audit B5).
    if GuildOS.ModAlerts and GuildOS.ModAlerts.SeedShared then GuildOS.ModAlerts:SeedShared() end
    local d = self.ValidDays(days)
    if d == nil then return false, "range" end
    local s = settings()
    s.newcomerDays, s.newcomerTrial = d, trial and true or false
    s.newcomerAt = math.max(GetServerTime(), (s.newcomerAt or 0) + 1)
    self:PublishConfig()
    if GuildOS.ModAlerts then GuildOS.ModAlerts:Refresh() end
    return true
end

-- Only a setting somebody made: a guild that never chose sends nothing. It carries no `max`.
function Newcomer:PublishConfig()
    local s = settings()
    if not (s and s.newcomerAt and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    GuildOS.SyncService:Publish("guildcfg", "newcomer", { days = self:GetDays(), trial = self:TrialCounts() },
        { rev = s.newcomerAt })
end

-- From an officer over GUILD (SyncService checked it): newest stamp wins, a tie keeps what is held. Only an
-- officer's client keeps it: the alerts are theirs.
function Newcomer:OnConfigSync(env)
    local data = type(env) == "table" and env.data
    local s = settings()
    if type(data) ~= "table" or not s or not GuildOS:IsOfficer() or env.act ~= "newcomer" then return end
    local at = GuildOS.Finite(env.rev)
    if not (at and at > 0) then return end
    at = math.min(at, GetServerTime() + STAMP_FUTURE_SLACK)
    local d = self.ValidDays(data.days)
    if d == nil or type(data.trial) ~= "boolean" then return end
    if s.newcomerAt and at <= s.newcomerAt then return end
    s.newcomerDays, s.newcomerTrial, s.newcomerAt = d, data.trial, at
    if GuildOS.ModAlerts then GuildOS.ModAlerts:Refresh() end
end

----------------------------------------------------------------------
-- Who is a newcomer
----------------------------------------------------------------------
-- The latest join RosterLog holds of each name, rebuilt only when its list changed (a new event, or a new
-- list after a Clear): one pass over at most 1000 events, never per line.
function Newcomer:_JoinIndex()
    local db = GuildOS.db
    local store = db and db.rosterLog and db.rosterLog.events
    if type(store) ~= "table" then return {} end
    local last = store[#store]
    local c = self._index
    if c and c.store == store and c.n == #store and c.last == last then return c.joins end
    local joins = {}
    for _, e in ipairs(store) do
        if type(e) == "table" and e.action == "join" and type(e.target) == "string" then
            local t = tonumber(e.timestamp)
            if t and (joins[e.target] == nil or t > joins[e.target]) then joins[e.target] = t end
        end
    end
    self._index = { store = store, n = #store, last = last, joins = joins }
    return joins
end

-- When `author` (a name as chat gives it) last joined, as RosterLog files it; nil when no officer's client
-- read their join.
function Newcomer:JoinAt(author)
    if type(author) ~= "string" or author == "" then return nil end
    local R = GuildOS.RosterLog
    local name = R and R._NormShort and R:_NormShort(author) or (author:match("^([^-]+)") or author)
    return self:_JoinIndex()[name]
end

-- Whether `author` is a newcomer now, and the badge's facts: { day = X, of = N }, { trial = true, of = N },
-- or nil. 0 days: nobody is.
function Newcomer:Of(author, now)
    local days = self:GetDays()
    if days <= 0 or type(author) ~= "string" then return nil end
    now = now or GetServerTime()
    local day = self.DayOf(self:JoinAt(author), now, days)
    if day then return { day = day, of = days } end
    local T = GuildOS.TrialTracker
    if self:TrialCounts() and T and T.GetState and GuildOS.db and type(GuildOS.db.trials) == "table" then
        local key = GuildOS:KeyOfRosterName(author)
        if key and T:GetState(key) == "trial" then return { trial = true, of = days } end
    end
    return nil
end

----------------------------------------------------------------------
-- Lifecycle and self-tests
----------------------------------------------------------------------
function Newcomer:Initialize()
    self:_RegisterTests()
end

function Newcomer:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    local N = Newcomer

    S:Register("newcomer.is_newcomer_at_the_edges", function()
        local join = 1000000
        if N.DayOf(join, join, 7) ~= 1 then return false, "the day they joined is day 1" end
        if N.DayOf(join, join + DAY - 1, 7) ~= 1 then return false, "still day 1" end
        if N.DayOf(join, join + DAY, 7) ~= 2 then return false, "day 2" end
        if N.DayOf(join, join + 7 * DAY - 1, 7) ~= 7 then return false, "the last second is day 7" end
        if N.DayOf(join, join + 7 * DAY, 7) ~= nil then return false, "join + N is over" end
        if N.DayOf(nil, join, 7) ~= nil then return false, "no known join: not a newcomer" end
        if N.DayOf(join, join, 0) ~= nil then return false, "0 days: nobody" end
        return true
    end)

    S:Register("newcomer.strict_limits", function()
        local cfg = {
            burst = { on = true, n = 5, secs = 10 }, ["repeat"] = { on = false, n = 3, secs = 60 },
            caps = { on = true, pct = 70, min = 12 }, links = { on = false, n = 2, secs = 60 },
        }
        local st = N.Strict(cfg)
        if st.burst.n ~= 4 or st["repeat"].n ~= 2 or st["repeat"].on then return false, "stricter, switches kept" end
        if st.caps.min ~= 9 or st.caps.pct ~= 70 then return false, "capitals on 70% of the letters" end
        if not st.links.on or st.links.n ~= 1 then return false, "any link" end
        if cfg.burst.n ~= 5 or cfg.links.on then return false, "the guild's limits untouched" end
        return true
    end)

    S:Register("newcomer.days_range", function()
        if N.ValidDays(0) ~= 0 or N.ValidDays("30") ~= 30 then return false, "0 and 30" end
        if N.ValidDays(31) or N.ValidDays(-1) or N.ValidDays(2.5) or N.ValidDays("x") then return false, "out of range" end
        return true
    end)
end
