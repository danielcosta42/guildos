----------------------------------------------------------------------
-- Guild OS - Recruitment Engagement
-- Officer-facing analytics data layer: who is actively recruiting, how
-- many invites they issued, and how many joins came from their OWN
-- invites, plus guild totals and a week-over-week trend.
--
-- Honesty: WoW exposes no who-invited-whom attribution. Everything here is
-- what a client observes about ITSELF and self-reports. A "join" is a name
-- THIS client invited (a GuildInvite it issued) that then appeared in a
-- "has joined the guild" system message within JOIN_WINDOW.
--
-- Security: the sync is self-reported vanity data (a member can inflate
-- their OWN numbers, and no permission ever rides on it). The one guarantee
-- is that identity is bound to the comm ENVELOPE sender, never the payload
-- body: db.recruitStats is keyed by the envelope sender, so nobody can file
-- a report under someone else's name. Accepted only over GUILD, and every
-- incoming number is clamped to a sane ceiling so a hostile or corrupt
-- packet cannot break the officer UI. Same rules as LFGBoard/RECRUIT_INFO.
----------------------------------------------------------------------
local RecruitEngagement = {}
BRutus.RecruitEngagement = RecruitEngagement
local LibSerialize = LibStub("LibSerialize")

local DAY         = 86400
local WEEK        = 7 * DAY          -- 604800: this-week window
local KEEP        = 14 * DAY         -- 1209600: prune posts/invites/joins and stats entries older than this
local JOIN_WINDOW = 1800             -- 30 min: pending-invite lifetime and the join-match window
local DAILY_MAX   = 500              -- per-day count ceiling on receipt
local PREV_MAX    = 5000             -- prev-week total ceiling on receipt
local STALE       = 86400            -- a row is "stale" when its report is older than this

----------------------------------------------------------------------
-- Pure helpers (unit tested; take an explicit `now`, touch no db/time/comm)
----------------------------------------------------------------------

-- Count timestamps whose AGE (now - ts) falls in the half-open window
-- [toSecAgo, fromSecAgo). fromSecAgo is the far (older) bound, toSecAgo the
-- near (newer) bound. This week = (list, now, WEEK, 0); prev week =
-- (list, now, KEEP, WEEK). The boundaries are chosen so a ts exactly 7 days
-- old lands in prev, never double-counted in this week.
function RecruitEngagement:_CountSince(list, now, fromSecAgo, toSecAgo)
    now = now or 0
    fromSecAgo = fromSecAgo or 0
    toSecAgo = toSecAgo or 0
    local n = 0
    for _, ts in ipairs(list or {}) do
        local age = now - ts
        if age >= toSecAgo and age < fromSecAgo then
            n = n + 1
        end
    end
    return n
end

-- Daily counts for the last 7 days as a 7-element array. Index 1 = today
-- (age 0..<1 day), index 7 = 6 days ago. A ts in the future (clock skew)
-- clamps into today so it can never produce a negative/zero index. sum of
-- the array equals _CountSince(list, now, WEEK, 0), by construction.
function RecruitEngagement:_Bucketize(list, now)
    now = now or 0
    local b = { 0, 0, 0, 0, 0, 0, 0 }
    for _, ts in ipairs(list or {}) do
        local age = now - ts
        if age < 0 then age = 0 end
        local idx = math.floor(age / DAY) + 1
        if idx >= 1 and idx <= 7 then
            b[idx] = b[idx] + 1
        end
    end
    return b
end

-- Was `short` invited by THIS client within `window` seconds of `now`?
-- Pins the join-credit rule: a join is only credited when a matching pending
-- invite exists and is still in window. Inclusive upper bound so an invite
-- exactly `window` old still matches (prune uses a strict >, so the two agree).
function RecruitEngagement:_MatchJoin(pending, short, now, window)
    if not pending or not short then return false end
    local ts = pending[short]
    if not ts then return false end
    return (now - ts) <= (window or 0)
end

-- Clamp one self-reported count to a non-negative integer in [0, ceiling].
-- nil / NaN / non-number / negative all collapse to 0; anything over the
-- ceiling is capped. This is the whole defence against a hostile packet
-- driving the officer UI with absurd numbers.
function RecruitEngagement:_ClampCount(n, ceiling)
    n = tonumber(n)
    if not n or n ~= n then return 0 end   -- nil / not a number / NaN
    if n < 0 then return 0 end
    ceiling = ceiling or 0
    if n > ceiling then return ceiling end
    return math.floor(n)
end

-- Sanitize a claimed daily array into exactly 7 clamped counts. A non-array
-- (or a forged 10000-entry array) becomes seven zeros / is read only at
-- 1..7, so the stored shape is always fixed-size regardless of the payload.
function RecruitEngagement:_SanitizeDaily(arr, ceiling)
    if type(arr) ~= "table" then arr = {} end
    local out = {}
    for i = 1, 7 do
        out[i] = self:_ClampCount(arr[i], ceiling)
    end
    return out
end

-- Turn a received packet into the entry we store. Pure (explicit `now`), so
-- a self test pins the clamp without comm/db. Every count is clamped; `last`
-- is a timestamp clamped to [0, now] (a forged far-future stamp cannot make
-- a member look permanently active); `part` defaults to participating unless
-- an explicit false was sent (opt-out semantics). receivedAt = now.
function RecruitEngagement:_SanitizeStats(p, now)
    now = now or 0
    if type(p) ~= "table" then p = {} end
    local d  = type(p.daily) == "table" and p.daily or {}
    local pv = type(p.prev) == "table" and p.prev or {}
    local last = tonumber(p.last)
    if not last or last ~= last or last < 0 then
        last = 0
    elseif last > now then
        last = now
    end
    return {
        daily = {
            posts   = self:_SanitizeDaily(d.posts, DAILY_MAX),
            invites = self:_SanitizeDaily(d.invites, DAILY_MAX),
            joins   = self:_SanitizeDaily(d.joins, DAILY_MAX),
        },
        prev = {
            posts   = self:_ClampCount(pv.posts, PREV_MAX),
            invites = self:_ClampCount(pv.invites, PREV_MAX),
            joins   = self:_ClampCount(pv.joins, PREV_MAX),
        },
        part = p.part ~= false,
        last = last,
        receivedAt = now,
    }
end

-- Drop timestamps older than maxAge, preserving order. Returns a new list.
function RecruitEngagement:_PruneList(list, now, maxAge)
    now = now or 0
    local out = {}
    for _, ts in ipairs(list or {}) do
        if (now - ts) <= maxAge then out[#out + 1] = ts end
    end
    return out
end

-- Drop pending invites older than `window` (they can no longer match a join).
-- Returns a new map.
function RecruitEngagement:_PrunePending(pending, now, window)
    now = now or 0
    local out = {}
    for short, ts in pairs(pending or {}) do
        if (now - ts) <= window then out[short] = ts end
    end
    return out
end

-- Drop stored member reports whose receivedAt is older than KEEP (the member
-- went quiet or left). Mutates store in place; returns how many were removed.
function RecruitEngagement:_PruneStore(store, now)
    if not store then return 0 end
    now = now or 0
    local removed = 0
    for k, e in pairs(store) do
        local recv = (type(e) == "table" and tonumber(e.receivedAt)) or 0
        if (now - recv) > KEEP then
            store[k] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Aggregate a fake-able store into the shape the officer UI renders. Pure
-- (explicit store + now) so a self test pins the sums/sort/conversion.
--   rows: one per member { key, name, part, posts7, invites7, joins7,
--         dailyInvites (7-array), last, stale }, sorted posts7 desc, then
--         joins7 desc, then key asc (a total order so rows never swap places
--         between repaints).
--   totals: { posts7, invites7, joins7, conv = joins7/invites7 (0 when no
--         invites), postsPrev, invitesPrev, joinsPrev }.
function RecruitEngagement:_Aggregate(store, now)
    now = now or 0
    local function sumArr(a)
        local s = 0
        for i = 1, 7 do s = s + (tonumber(a and a[i]) or 0) end
        return s
    end
    local rows = {}
    local totals = {
        posts7 = 0, invites7 = 0, joins7 = 0,
        postsPrev = 0, invitesPrev = 0, joinsPrev = 0, conv = 0,
    }
    for key, e in pairs(store or {}) do
        if type(e) == "table" then
            local d = e.daily or {}
            local posts7   = sumArr(d.posts)
            local invites7 = sumArr(d.invites)
            local joins7   = sumArr(d.joins)
            local prev = e.prev or {}
            local recv = tonumber(e.receivedAt) or 0
            rows[#rows + 1] = {
                key          = key,
                name         = key:match("^([^-]+)") or key,
                part         = e.part ~= false,
                posts7       = posts7,
                invites7     = invites7,
                joins7       = joins7,
                dailyInvites = d.invites or { 0, 0, 0, 0, 0, 0, 0 },
                last         = tonumber(e.last) or 0,
                stale        = (now - recv) > STALE,
            }
            totals.posts7      = totals.posts7 + posts7
            totals.invites7    = totals.invites7 + invites7
            totals.joins7      = totals.joins7 + joins7
            totals.postsPrev   = totals.postsPrev + (tonumber(prev.posts) or 0)
            totals.invitesPrev = totals.invitesPrev + (tonumber(prev.invites) or 0)
            totals.joinsPrev   = totals.joinsPrev + (tonumber(prev.joins) or 0)
        end
    end
    if totals.invites7 > 0 then
        totals.conv = totals.joins7 / totals.invites7
    end
    table.sort(rows, function(a, b)
        if a.posts7 ~= b.posts7 then return a.posts7 > b.posts7 end
        if a.joins7 ~= b.joins7 then return a.joins7 > b.joins7 end
        return a.key < b.key
    end)
    return { rows = rows, totals = totals }
end

----------------------------------------------------------------------
-- Layer 1: local self-tracking (db.myRecruitStats, this client only)
----------------------------------------------------------------------
function RecruitEngagement:_Stats()
    BRutus.db.myRecruitStats = BRutus.db.myRecruitStats or {}
    local s = BRutus.db.myRecruitStats
    s.posts   = s.posts   or {}
    s.invites = s.invites or {}
    s.joins   = s.joins   or {}
    s.pending = s.pending or {}
    return s
end

function RecruitEngagement:_PruneLocal(now)
    now = now or time()
    local s = self:_Stats()
    s.posts   = self:_PruneList(s.posts, now, KEEP)
    s.invites = self:_PruneList(s.invites, now, KEEP)
    s.joins   = self:_PruneList(s.joins, now, KEEP)
    s.pending = self:_PrunePending(s.pending, now, JOIN_WINDOW)
end

-- One successful recruitment send (called from DoSendRecruitmentMessage).
function RecruitEngagement:RecordPost()
    local s = self:_Stats()
    local now = time()
    s.posts[#s.posts + 1] = now
    self:_PruneLocal(now)
end

-- One GuildInvite THIS client issued. Records the invite and opens a pending
-- match keyed by the short name, so a later join can be credited.
function RecruitEngagement:RecordInvite(name)
    local s = self:_Stats()
    local now = time()
    s.invites[#s.invites + 1] = now
    local short = (type(name) == "string") and (name:match("^([^-]+)") or name) or nil
    if short and short ~= "" then s.pending[short] = now end
    self:_PruneLocal(now)
end

-- A detected guild join. Credits a join ONLY when this client has an in-window
-- pending invite for that name (no pending -> no credit, per the honesty rule).
-- Clears the pending on a match so a duplicate system message cannot double-count.
function RecruitEngagement:RecordJoin(name)
    local s = self:_Stats()
    local now = time()
    local short = (type(name) == "string") and (name:match("^([^-]+)") or name) or nil
    local matched = false
    if short and self:_MatchJoin(s.pending, short, now, JOIN_WINDOW) then
        s.joins[#s.joins + 1] = now
        s.pending[short] = nil
        matched = true
    end
    self:_PruneLocal(now)
    return matched
end

----------------------------------------------------------------------
-- Layer 2: sync (CommSystem RECRUIT_STATS)
----------------------------------------------------------------------

-- Derive and broadcast this client's compact self-report over GUILD.
-- Answered from CommSystem:HandleRequest (login + periodic pull), so an
-- officer logging in converges on a fresh picture. Small; no throttle need.
function RecruitEngagement:BroadcastStats()
    if not BRutus.CommSystem or not IsInGuild() then return end
    local now = time()
    self:_PruneLocal(now)
    local s = self:_Stats()
    local function lastOf(list) return (#list > 0) and list[#list] or 0 end
    local last = math.max(lastOf(s.posts), lastOf(s.invites), lastOf(s.joins))
    local part = true
    if BRutus.Recruitment and BRutus.Recruitment.IsParticipating then
        part = BRutus.Recruitment:IsParticipating()
    end
    local packet = {
        daily = {
            posts   = self:_Bucketize(s.posts, now),
            invites = self:_Bucketize(s.invites, now),
            joins   = self:_Bucketize(s.joins, now),
        },
        prev = {
            posts   = self:_CountSince(s.posts, now, KEEP, WEEK),
            invites = self:_CountSince(s.invites, now, KEEP, WEEK),
            joins   = self:_CountSince(s.joins, now, KEEP, WEEK),
        },
        part = part,
        last = last,
    }
    BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.RECRUIT_STATS,
        LibSerialize:Serialize(packet))
end

-- Incoming self-report. Identity is the ENVELOPE sender (never the payload):
-- the entry is keyed by the sender's short-Realm key, so a member can only
-- ever file under their own name. Accepted only over GUILD. Only officers
-- store (members drop it). Every number is clamped in _SanitizeStats.
function RecruitEngagement:HandleStats(sender, data, channel)
    if channel ~= "GUILD" then return end
    if not sender then return end
    if not (BRutus.IsOfficer and BRutus:IsOfficer()) then return end
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end
    local now = time()
    local entry = self:_SanitizeStats(p, now)
    local short = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = BRutus:GetPlayerKey(short, realm)
    BRutus.db.recruitStats = BRutus.db.recruitStats or {}
    BRutus.db.recruitStats[key] = entry
    self:_PruneStore(BRutus.db.recruitStats, now)
    if BRutus.recruitEngagementRefresh then BRutus.recruitEngagementRefresh() end
end

----------------------------------------------------------------------
-- Layer 3: aggregate for the UI (thin wrapper over the pure _Aggregate)
----------------------------------------------------------------------
function RecruitEngagement:GetAggregate(now)
    local store = (BRutus.db and BRutus.db.recruitStats) or {}
    return self:_Aggregate(store, now or time())
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function RecruitEngagement:Initialize()
    BRutus.db.recruitStats = BRutus.db.recruitStats or {}
    self:_Stats()
    local now = time()
    self:_PruneLocal(now)
    self:_PruneStore(BRutus.db.recruitStats, now)
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Self tests (pure helpers only; no db/time/comm touched)
----------------------------------------------------------------------
function RecruitEngagement:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    S:Register("recruiteng.count_since", function()
        local now = 2000000
        -- fresh, 3d, 8d, 20d, exactly-7d
        local list = { now, now - 3 * DAY, now - 8 * DAY, now - 20 * DAY, now - 7 * DAY }
        -- this week [0, 7d): fresh + 3d
        if RecruitEngagement:_CountSince(list, now, WEEK, 0) ~= 2 then return false, "this-week window" end
        -- prev week [7d, 14d): 8d + exactly-7d (7d lands in prev, not this week)
        if RecruitEngagement:_CountSince(list, now, KEEP, WEEK) ~= 2 then return false, "prev window" end
        if RecruitEngagement:_CountSince({}, now, WEEK, 0) ~= 0 then return false, "empty list" end
        return true
    end)

    S:Register("recruiteng.bucketize", function()
        local now = 2000000
        local list = { now, now - 100, now - DAY - 5, now - 6 * DAY, now - 7 * DAY, now - 20 * DAY }
        local b = RecruitEngagement:_Bucketize(list, now)
        if #b ~= 7 then return false, "seven buckets" end
        if b[1] ~= 2 then return false, "today holds fresh + 100s" end
        if b[2] ~= 1 then return false, "yesterday bucket" end
        if b[7] ~= 1 then return false, "sixth-day bucket" end
        if b[3] ~= 0 or b[4] ~= 0 or b[5] ~= 0 or b[6] ~= 0 then return false, "empty middle buckets" end
        local s = 0
        for i = 1, 7 do s = s + b[i] end
        if s ~= 4 then return false, "7d/20d fall outside the window" end
        local fb = RecruitEngagement:_Bucketize({ now + 500 }, now)
        if fb[1] ~= 1 then return false, "future ts clamps into today" end
        return true
    end)

    S:Register("recruiteng.match_join", function()
        local pending = { Ann = 1000, Bob = 500 }
        if not RecruitEngagement:_MatchJoin(pending, "Ann", 1000 + JOIN_WINDOW, JOIN_WINDOW) then
            return false, "exactly in-window matches"
        end
        if RecruitEngagement:_MatchJoin(pending, "Ann", 1000 + JOIN_WINDOW + 1, JOIN_WINDOW) then
            return false, "one second past misses"
        end
        if not RecruitEngagement:_MatchJoin(pending, "Bob", 600, JOIN_WINDOW) then
            return false, "well inside matches"
        end
        if RecruitEngagement:_MatchJoin(pending, "Cara", 600, JOIN_WINDOW) then
            return false, "never-invited name misses"
        end
        if RecruitEngagement:_MatchJoin(nil, "Ann", 600, JOIN_WINDOW) then return false, "nil pending" end
        if RecruitEngagement:_MatchJoin(pending, nil, 600, JOIN_WINDOW) then return false, "nil short" end
        return true
    end)

    S:Register("recruiteng.prune", function()
        local now = 2000000
        local kept = RecruitEngagement:_PruneList({ now, now - 10 * DAY, now - 15 * DAY }, now, KEEP)
        if #kept ~= 2 then return false, "list prune count" end
        if kept[1] ~= now or kept[2] ~= now - 10 * DAY then return false, "order kept, 15d dropped" end
        local pk = RecruitEngagement:_PrunePending(
            { Ann = now - 100, Bob = now - (JOIN_WINDOW + 10) }, now, JOIN_WINDOW)
        if pk.Ann ~= now - 100 then return false, "fresh pending kept" end
        if pk.Bob ~= nil then return false, "stale pending dropped" end
        local store = { ["A-R"] = { receivedAt = now - 5 * DAY }, ["B-R"] = { receivedAt = now - 15 * DAY } }
        local removed = RecruitEngagement:_PruneStore(store, now)
        if removed ~= 1 or store["A-R"] == nil or store["B-R"] ~= nil then return false, "store prune" end
        return true
    end)

    S:Register("recruiteng.clamp", function()
        if RecruitEngagement:_ClampCount(5, 500) ~= 5 then return false, "in range kept" end
        if RecruitEngagement:_ClampCount(-3, 500) ~= 0 then return false, "negative -> 0" end
        if RecruitEngagement:_ClampCount(9999, 500) ~= 500 then return false, "over ceiling clamped" end
        if RecruitEngagement:_ClampCount(3.9, 500) ~= 3 then return false, "floored to int" end
        if RecruitEngagement:_ClampCount("nope", 500) ~= 0 then return false, "garbage -> 0" end
        if RecruitEngagement:_ClampCount(nil, 500) ~= 0 then return false, "nil -> 0" end
        local nan = math.huge - math.huge
        if RecruitEngagement:_ClampCount(nan, 500) ~= 0 then return false, "NaN -> 0" end
        return true
    end)

    S:Register("recruiteng.sanitize", function()
        local now = 2000000
        local hostile = {
            daily = {
                posts   = { 9999, -5, 3, 0, 0, 0, 0 },
                invites = { 1, 2, 3, 4, 5, 6, 7 },
                joins   = "not a table",
            },
            prev = { posts = 999999, invites = -10, joins = 4 },
            part = false,
            last = now + 999999,
        }
        local e = RecruitEngagement:_SanitizeStats(hostile, now)
        if e.daily.posts[1] ~= 500 or e.daily.posts[2] ~= 0 or e.daily.posts[3] ~= 3 then
            return false, "daily clamp"
        end
        if #e.daily.joins ~= 7 or e.daily.joins[1] ~= 0 then return false, "bad daily -> seven zeros" end
        if e.prev.posts ~= 5000 or e.prev.invites ~= 0 or e.prev.joins ~= 4 then return false, "prev clamp" end
        if e.part ~= false then return false, "explicit false opts out" end
        if e.last ~= now then return false, "far-future last clamped to now" end
        if e.receivedAt ~= now then return false, "receivedAt stamped" end
        local g = RecruitEngagement:_SanitizeStats("garbage", now)
        if g.prev.posts ~= 0 or #g.daily.invites ~= 7 or g.part ~= true then return false, "garbage defaults" end
        return true
    end)

    S:Register("recruiteng.aggregate", function()
        local now = 2000000
        local store = {
            ["Ann-R"] = {
                daily = { posts = { 1, 1, 0, 0, 0, 0, 0 }, invites = { 2, 0, 0, 0, 0, 0, 0 }, joins = { 1, 0, 0, 0, 0, 0, 0 } },
                prev = { posts = 3, invites = 4, joins = 1 },
                part = true, last = now - 100, receivedAt = now - 10,
            },
            ["Bob-R"] = {
                daily = { posts = { 5, 0, 0, 0, 0, 0, 0 }, invites = { 1, 1, 0, 0, 0, 0, 0 }, joins = { 0, 0, 0, 0, 0, 0, 0 } },
                prev = { posts = 0, invites = 2, joins = 0 },
                part = false, last = now - 5000, receivedAt = now - 2 * DAY,
            },
        }
        local agg = RecruitEngagement:_Aggregate(store, now)
        local t = agg.totals
        if t.posts7 ~= 7 then return false, "posts7 total" end
        if t.invites7 ~= 4 then return false, "invites7 total" end
        if t.joins7 ~= 1 then return false, "joins7 total" end
        if t.postsPrev ~= 3 then return false, "postsPrev total" end
        if t.invitesPrev ~= 6 then return false, "invitesPrev total" end
        if t.joinsPrev ~= 1 then return false, "joinsPrev total" end
        if math.abs(t.conv - 0.25) > 1e-9 then return false, "conversion joins7/invites7" end
        if #agg.rows ~= 2 then return false, "row count" end
        if agg.rows[1].name ~= "Bob" or agg.rows[2].name ~= "Ann" then return false, "sorted posts7 desc" end
        if agg.rows[1].part ~= false then return false, "participation carried" end
        if agg.rows[1].stale ~= true then return false, "Bob report stale" end
        if agg.rows[2].stale ~= false then return false, "Ann report fresh" end
        if agg.rows[2].dailyInvites[1] ~= 2 then return false, "dailyInvites passthrough" end
        local empty = RecruitEngagement:_Aggregate({}, now)
        if empty.totals.conv ~= 0 or #empty.rows ~= 0 then return false, "empty aggregate is safe" end
        return true
    end)
end
