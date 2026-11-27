----------------------------------------------------------------------
-- Guild OS - The game's guild event log, read once a login (specs/salao/log-e-renomes.md)
--
-- The Roster Log hears the game's system lines only while this officer is online; the roster diff
-- (MemberHistory) sees who joined, left or changed rank since the last login, but not who did it. The
-- game keeps its own short log of the guild (the "Guild Log": invite, join, promote, demote, remove,
-- quit, each with how long ago in years, months, days and hours). Once a login, after the roster has
-- settled and the first diff ran, out of combat, on an officer's client in its own guild, this asks for
-- it once (Compat.QueryGuildEventLog) and merges what comes back:
--   * a line already in the audit log (the same action and member within the entry's tolerance: two
--     hours for "hours ago", three days for "months ago"; a diff's line, seen after the fact, anywhere
--     before the time it was seen) gets the officer it lacked: who invited a join, who removed a "gone"
--     (it becomes a removal), who changed a rank; and the member's history follows (MemberHistory);
--   * one the log does not hold is added as an approximate event (`approx`, its time the middle of the
--     game's hour) and sent to the officers like any event this client adds (domain "audit", "add");
--     a copy another officer sends of the same game line folds into it (RosterLog:_Insert's approx rule);
--   * an entry older than the log's 90 days is left alone, so a quiet guild's old log never comes back.
-- A client without the log (Compat.HasGuildEventLog false) does nothing and says nothing. Another
-- addon or the game's own window asking for the log is not this one's answer: only the answer to its
-- own question is read.
----------------------------------------------------------------------
local GuildEventLog = {}
GuildOS.GuildEventLog = GuildEventLog

GuildEventLog.DELAY = 15          -- seconds after MemberHistory's settle: its first diff runs before this
GuildEventLog.RETRY = 30          -- seconds between two tries while the diff has not run yet
GuildEventLog.TRIES = 6
GuildEventLog.MAX_AGE = 90 * 86400
GuildEventLog.SEEN_WINDOW = 30 * 86400   -- how long before a diff saw a change the change may have been

-- The game's word -> the audit log's action, and which of the two names is the member and which the officer.
local KIND = {
    join    = { action = "join",    target = 1 },
    quit    = { action = "leave",   target = 1 },
    remove  = { action = "kick",    target = 2, author = 1 },
    promote = { action = "promote", target = 2, author = 1, rank = true },
    demote  = { action = "demote",  target = 2, author = 1, rank = true },
}
GuildEventLog.KIND = KIND

-- Which lines already in the log can be the same change: a "gone" of the diff is a removal or a departure.
local SAME = {
    join = { join = true }, leave = { leave = true, gone = true }, kick = { kick = true, gone = true },
    promote = { promote = true }, demote = { demote = true },
}

local function session()
    GuildOS.State.guildEventLog = GuildOS.State.guildEventLog or {}
    return GuildOS.State.guildEventLog
end

function GuildEventLog:Initialize()
    local st = session()
    st.done, st.pending, st.tries, st.combat = nil, nil, 0, nil
    local f = CreateFrame("Frame")
    -- Expected missing on a client without the log: a fact about the client, not a start-up problem.
    GuildOS.Compat.RegisterEvent(f, "GUILD_EVENT_LOG_UPDATE", true)
    GuildOS.Compat.RegisterEvent(f, "PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "GUILD_EVENT_LOG_UPDATE" then
            GuildOS:SafeCall(GuildEventLog.OnUpdate, GuildEventLog)
        elseif st.combat then
            st.combat = nil
            GuildOS:SafeCall(GuildEventLog.Resume, GuildEventLog)
        end
    end)
    local settle = GuildOS.MemberHistory and GuildOS.MemberHistory.SETTLE_SECONDS or 45
    GuildOS.Compat.After(settle + self.DELAY, function() GuildOS:SafeCall(GuildEventLog.Request, GuildEventLog) end)
end

local function mayRead()
    return GuildOS.db and GuildOS.db.rosterLog and IsInGuild() and GuildOS:IsOnGuildDB() and GuildOS:IsOfficer()
end

-- The one question of a login. True when it was asked.
function GuildEventLog:Request()
    local st = session()
    if st.done or st.pending then return false end
    if not GuildOS.Compat.HasGuildEventLog() then st.done = true; return false end
    if not mayRead() then return false end
    if GuildOS:InCombat() then st.combat = "ask"; return false end
    -- After the first roster diff, so its lines are there to be completed.
    local MH = GuildOS.State.memberHistory
    if GuildOS.MemberHistory and not (MH and MH.diffed) and (st.tries or 0) < self.TRIES then
        st.tries = (st.tries or 0) + 1
        GuildOS.Compat.After(self.RETRY, function() GuildOS:SafeCall(GuildEventLog.Request, GuildEventLog) end)
        return false
    end
    if not GuildOS.Compat.QueryGuildEventLog() then st.done = true; return false end
    st.pending = true
    return true
end

-- After a fight: the question, or the answer that came during it.
function GuildEventLog:Resume()
    local st = session()
    if st.held then
        local list = st.held
        st.held = nil
        return self:Merge(list)
    end
    return self:Request()
end

function GuildEventLog:OnUpdate()
    local st = session()
    if not st.pending then return end   -- the game's window, or another addon: not our question
    st.pending, st.done = nil, true
    local list = GuildOS.Compat.GuildEventLog()
    if not list then return end
    if GuildOS:InCombat() then st.held, st.combat = list, "merge"; return end
    return self:Merge(list)
end

----------------------------------------------------------------------
-- Pure: the game's entries as the audit log's events
----------------------------------------------------------------------
-- `list` (Compat.GuildEventLog's) at `now`: { action, target, author, detail, timestamp, tol } oldest first,
-- invites folded into the join they led to (its author), and the inviter of each join on `inviter`.
function GuildEventLog.Events(list, now, norm)
    norm = norm or function(n) return n end
    local out, invites = {}, {}
    for _, it in ipairs(list or {}) do
        local t = now - (tonumber(it.ago) or 0) - 1800   -- the middle of the game's hour
        if it.type == "invite" and it.p2 then
            invites[#invites + 1] = { by = norm(it.p1), target = norm(it.p2), t = t, tol = it.tol or 7200 }
        else
            local k = KIND[it.type]
            local target = k and (k.target == 1 and it.p1 or it.p2)
            if target then
                out[#out + 1] = { action = k.action, target = norm(target),
                    author = k.author and norm(k.author == 1 and it.p1 or it.p2) or nil,
                    detail = k.rank and it.rank or nil, timestamp = t, tol = it.tol or 7200 }
            end
        end
    end
    table.sort(out, function(a, b) return a.timestamp < b.timestamp end)
    -- An invite comes just before its join: the closest earlier one for that member, within the tolerance.
    for _, e in ipairs(out) do
        if e.action == "join" then
            local best
            for _, inv in ipairs(invites) do
                if inv.target == e.target and inv.t <= e.timestamp + e.tol
                    and (not best or math.abs(inv.t - e.timestamp) < math.abs(best.t - e.timestamp)) then best = inv end
            end
            if best then e.author = best.by end
        end
    end
    return out
end

-- Pure: the line of `store` that is `evt`'s change, or nil. A line the game's own message or an officer's sync
-- wrote: the same action and member within `evt.tol`. A line of the diff (`loc`, seen after the fact): any time
-- from SEEN_WINDOW before it was seen up to the tolerance after. The closest in time wins.
function GuildEventLog.Find(store, evt)
    local same = SAME[evt.action]
    if not same then return nil end
    local best, bestD
    for i = #store, 1, -1 do
        local e = store[i]
        if e.target == evt.target and same[e.action] and (not evt.detail or not e.detail or e.detail == evt.detail) then
            local ts = e.timestamp or 0
            local ok
            if e.loc then
                ok = evt.timestamp <= ts + evt.tol and evt.timestamp >= ts - GuildEventLog.SEEN_WINDOW
            else
                ok = math.abs(ts - evt.timestamp) <= math.max(evt.tol, tonumber(e.tol) or 0)
            end
            local d = math.abs(ts - evt.timestamp)
            if ok and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end

-- Pure: `line` completed from `evt`. True when it changed.
function GuildEventLog.Fill(line, evt)
    local changed = false
    if line.action == "gone" and (evt.action == "kick" or evt.action == "leave") then
        line.action, changed = evt.action, true
    end
    if evt.author and not line.author then line.author, changed = evt.author, true end
    if evt.detail and not line.detail then line.detail, changed = evt.detail, true end
    return changed
end

----------------------------------------------------------------------
-- The merge
----------------------------------------------------------------------
-- The log's entries into the audit log and the members' history. Returns how many lines were completed and
-- how many added.
function GuildEventLog:Merge(list, now)
    if not mayRead() then return 0, 0 end
    local RL = GuildOS.RosterLog
    if not RL then return 0, 0 end
    now = now or GetServerTime()
    local store = GuildOS.db.rosterLog.events
    local events = GuildEventLog.Events(list, now, function(n) return RL:_NormShort(n) end)
    local filled, added = 0, 0
    local MH = GuildOS.MemberHistory
    for _, evt in ipairs(events) do
        if now - evt.timestamp <= self.MAX_AGE then
            local line = GuildEventLog.Find(store, evt)
            if line then
                if GuildEventLog.Fill(line, evt) then
                    filled = filled + 1
                    if MH and MH.FromLog then GuildOS:SafeCall(MH.FromLog, MH, evt) end
                end
            else
                local new = { action = evt.action, target = evt.target, author = evt.author, detail = evt.detail,
                    timestamp = math.floor(evt.timestamp), approx = true, tol = evt.tol }
                -- One an officer deleted here stays deleted (RosterLog:IsHidden, inside _Insert).
                if RL:Add(new) then
                    added = added + 1
                end
            end
        end
    end
    if filled > 0 then RL:Refresh() end
    return filled, added
end
