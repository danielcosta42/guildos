----------------------------------------------------------------------
-- Guild OS - Member History (issue #425)
-- Each member's passages through the guild (when they joined, when they left, how and by whom) and
-- their rank changes, kept apart from the Roster Log, which forgets after 90 days. An officer's
-- client feeds it from the Roster Log's live and synced events and from a diff of the whole roster
-- against the one it last saw ("since your last login"); the diff also writes level ups, note
-- changes and returns from inactivity to the log. Officers only: a member's client keeps nothing.
--
--   db.memberHistory[key] = {
--       stints = { { joinAt, joinEst, leftAt, leftEst, how = "leave"|"kick"|"gone", by, inv }, ... },   -- inv: who invited
--       ranks  = { { at, from, to, by, est }, ... },
--   }
--   db.memberHistoryBase = { at, m = { [key] = { r, rn, lv, n, o, off, c, g } } }   -- the roster last seen (c: class, g: GUID)
--   db.memberHistoryOut  = { rec, ... }   -- the last records this client sent, for the login backfill
--   db.memberHistory[key].note = { text, author, ts, rev }   -- the officers' permanent note (#449, saidas.md)
--   db.memberHistory[key].cls  = "WARRIOR"                    -- the class last seen, for a character gone since
--
-- The permanent note travels only over the game's OFFICER addon channel (SyncService domain "hnote", like the
-- officer sheet): a member's client never gets the bytes; without that channel it stays on this client. The newer
-- revision wins. A member with a note is never dropped by the ceiling below.
--
-- `joinEst` / `leftEst`: the time is when GuildOS saw it (a roster diff, or firstSeen before the
-- history existed), not the game's line: the true time is at or before it. A join nobody saw has no
-- joinAt at all. Nothing is ever read from another addon.
--
-- Ceiling (the criterion "teto documentado"): MAX_STINTS passages and MAX_RANKS rank changes per
-- member, the oldest dropped first, and MAX_KEYS members in all, the former members who left longest
-- ago dropped first; a present member is never dropped. A stint is ~80 bytes in the SavedVariables
-- and a rank change ~70: the hard bound is MAX_KEYS x (MAX_STINTS x 80 + MAX_RANKS x 70) ~ 7.6 MB,
-- and a 1000-member guild over three years (a few thousand keys, one or two stints and a couple of
-- rank changes each) stays near 1 MB.
--
-- Sync: append-only records with an id over the officers' existing `audit` domain, action "hist"
-- (a client before #425 reads only "add" there and ignores it). Applying a record twice, or two
-- officers' records of the same change, changes nothing: the rules below merge them.
----------------------------------------------------------------------
local MemberHistory = {}
GuildOS.MemberHistory = MemberHistory
local L = GuildOS.L

MemberHistory.MAX_STINTS = 10
MemberHistory.MAX_RANKS = 15
MemberHistory.MAX_KEYS = 4000
MemberHistory.OUTBOX = 25          -- records re-sent at login (like the Roster Log's backfill)
MemberHistory.SCAN_GAP = 60        -- seconds between two roster diffs (issue #324: a big guild's bursts)
MemberHistory.SETTLE_SECONDS = 45  -- after login: the other officers' audit backfill arrives first
local NEAR = 300                   -- seconds within which two exact records of one change are one
local FUTURE_SLACK = 300           -- a record's time may run this far past this client's clock
local STR_MAX = 48                 -- bytes of a name or rank off the network
local NAMES_SHOWN = 5              -- names in the login line before "+N"
MemberHistory.NOTE_MAX = 300       -- bytes of a permanent note
MemberHistory.NOTE_DOMAIN = "hnote"
MemberHistory.NOTE_BATCH = 4       -- notes per envelope of a backfill
MemberHistory.NOTE_BACKFILL = 40   -- the newest notes re-sent on a sync request

local function session()
    GuildOS.State.memberHistory = GuildOS.State.memberHistory or { seen = {} }
    return GuildOS.State.memberHistory
end

function MemberHistory:Initialize()
    local db = GuildOS.db
    db.memberHistory = type(db.memberHistory) == "table" and db.memberHistory or {}
    db.memberHistoryOut = type(db.memberHistoryOut) == "table" and db.memberHistoryOut or {}
    if GuildOS.SyncService then
        GuildOS.SyncService:On(self.NOTE_DOMAIN, function(env, sender) MemberHistory:OnNoteSync(env, sender) end)
    end
    local st = session()
    st.settled, st.diffed = nil, nil
    GuildOS.Compat.After(self.SETTLE_SECONDS, function()
        st.settled = true
        GuildOS:SafeCall(self.Scan, self)
    end)
end

----------------------------------------------------------------------
-- Pure: days, dates (unit-tested in tools/member-history.lua)
----------------------------------------------------------------------
-- The day number of a civil date (days since 1970-01-01), for any year: no table, no clock.
function MemberHistory.DayNumber(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- Calendar days from `a` to `b` (timestamps) on the dates the client's clock shows: joined on the
-- 31st at 23:30 and gone at 00:10 is one day, whatever the time zone, summer time or year. `dateFn`
-- is date (tests pass their own zone).
function MemberHistory.DaysBetween(a, b, dateFn)
    if not (a and b) then return nil end
    dateFn = dateFn or date
    local ta, tb = dateFn("*t", a), dateFn("*t", b)
    return MemberHistory.DayNumber(tb.year, tb.month, tb.day) - MemberHistory.DayNumber(ta.year, ta.month, ta.day)
end

----------------------------------------------------------------------
-- Pure: the merge rules, on a given store `h` (the db's, or a test's)
----------------------------------------------------------------------
local function recOf(h, key, create)
    local r = h[key]
    if type(r) ~= "table" then
        if not create then return nil end
        r = {}
        h[key] = r
    end
    r.stints = type(r.stints) == "table" and r.stints or {}
    r.ranks = type(r.ranks) == "table" and r.ranks or {}
    return r
end

local function trim(list, max)
    while #list > max do table.remove(list, 1) end
end

local HOW_RANK = { gone = 1, leave = 2, kick = 3 }

-- A join at `t`. `est`: seen by a roster diff, not the game's line. Returns "join" or "rejoin" when a
-- passage starts, "refined" when an open one got an earlier exact time, nil when nothing changed.
function MemberHistory.ApplyJoin(h, key, t, est)
    if type(key) ~= "string" or key == "" or type(t) ~= "number" then return nil end
    local r = recOf(h, key, true)
    local s = r.stints
    local last = s[#s]
    if last and last.leftAt == nil then
        -- Already a member: an exact time earlier than a seen one is the better one, and any exact time
        -- beats a day read from a note (#429).
        if not est and (last.joinAt == nil or (last.joinEst and (t <= last.joinAt or last.joinSrc == "note"))) then
            last.joinAt, last.joinEst, last.joinSrc = t, nil, nil
            return "refined"
        end
        return nil
    end
    if last and t < last.leftAt then
        if est then return nil end
        -- An old join off the network: it fills a closed passage's unknown or seen start.
        for i = #s, 1, -1 do
            local st, prev = s[i], s[i - 1]
            if st.leftAt and t <= st.leftAt and (not prev or (prev.leftAt and t >= prev.leftAt)) then
                if st.joinAt == nil or (st.joinEst and t <= st.joinAt) then
                    st.joinAt, st.joinEst = t, nil
                    return "refined"
                end
                return nil
            end
        end
        return nil
    end
    s[#s + 1] = { joinAt = t, joinEst = est or nil }
    trim(s, MemberHistory.MAX_STINTS)
    return #s > 1 and "rejoin" or "join"
end

-- A departure at `t`: `how` "leave", "kick" (by `by`) or "gone" (a diff: one or the other). True
-- when the history changed.
function MemberHistory.ApplyLeave(h, key, t, how, by, est)
    if type(key) ~= "string" or key == "" or type(t) ~= "number" then return false end
    local r = recOf(h, key, true)
    local s = r.stints
    local last = s[#s]
    if est then
        -- A diff reads the roster as it is: it closes an open passage, and that is all.
        if last and last.leftAt == nil and (last.joinAt == nil or t >= last.joinAt) then
            last.leftAt, last.leftEst, last.how, last.by = t, true, how or "gone", by
            return true
        end
        return false
    end
    -- The open passage ends, when the departure is after its start.
    if last and last.leftAt == nil and (last.joinAt == nil or t >= last.joinAt) then
        last.leftAt, last.how, last.by = t, how, by
        return true
    end
    -- The same departure already held: a seen one, or an exact one within NEAR seconds.
    for i = #s, 1, -1 do
        local st = s[i]
        if st.leftAt and ((st.leftEst and t <= st.leftAt and (st.joinAt == nil or t >= st.joinAt))
            or math.abs(st.leftAt - t) <= NEAR) then
            local changed = false
            if st.leftEst then st.leftAt, st.leftEst, changed = t, nil, true end
            if (HOW_RANK[how] or 0) > (HOW_RANK[st.how] or 0) then st.how, st.by, changed = how, by, true end
            return changed
        end
    end
    -- A departure nobody saw the join of: a passage with no start, in its place by time.
    local at = #s + 1
    for i = 1, #s do
        if (s[i].joinAt or s[i].leftAt or 0) > t then at = i; break end
    end
    table.insert(s, at, { leftAt = t, how = how, by = by })
    trim(s, MemberHistory.MAX_STINTS)
    return true
end

-- A rank change at `t` to rank `to` (a name; `from` when known). A diff's (`est`) is dropped when the
-- latest change already says `to`; an exact one merges with one of the same rank within NEAR seconds
-- or a seen one after it. True when added or refined.
function MemberHistory.ApplyRank(h, key, t, from, to, by, est)
    if type(key) ~= "string" or key == "" or type(t) ~= "number" or type(to) ~= "string" or to == "" then return false end
    local r = recOf(h, key, true)
    local list = r.ranks
    local last = list[#list]
    if est then
        if last and last.to == to then return false end
        list[#list + 1] = { at = t, from = from, to = to, est = true }
        trim(list, MemberHistory.MAX_RANKS)
        return true
    end
    for i = #list, 1, -1 do
        local e = list[i]
        if e.to == to and (math.abs(e.at - t) <= NEAR or (e.est and t <= e.at)) then
            local changed = false
            if e.est then e.at, e.est, changed = t, nil, true end
            if by and not e.by then e.by, changed = by, true end
            if from and not e.from then e.from, changed = from, true end
            return changed
        end
    end
    local at = #list + 1
    for i = 1, #list do
        if list[i].at > t then at = i; break end
    end
    table.insert(list, at, { at = t, from = from, to = to, by = by })
    trim(list, MemberHistory.MAX_RANKS)
    return true
end

-- A join day read from the member's note (#429), at `t`: it fills the open passage's start when there is none, or
-- replaces one GuildOS only saw that is later, never before the passage before it ended. It stays "seen" (est), so
-- the game's own line replaces it. True when the history changed.
function MemberHistory.ApplyNoteJoin(h, key, t)
    if type(key) ~= "string" or key == "" or type(t) ~= "number" then return false end
    local r = recOf(h, key, false)
    local s = r and r.stints
    local last = s and s[#s]
    if not last or last.leftAt ~= nil then return false end
    local prev = s[#s - 1]
    if prev and prev.leftAt and t < prev.leftAt then return false end
    if last.joinAt == nil or (last.joinEst and t < last.joinAt) then
        last.joinAt, last.joinEst, last.joinSrc = t, true, "note"
        return true
    end
    return false
end

-- A present member's open passage, made when none is: the first look at the guild, from what GuildOS
-- knew of them (`t`, firstSeen), never before their last departure. True when one was made.
function MemberHistory.EnsureOpen(h, key, t)
    local r = recOf(h, key, true)
    local s = r.stints
    local last = s[#s]
    if last and last.leftAt == nil then return false end
    if last and last.leftAt and t < last.leftAt then t = last.leftAt end
    s[#s + 1] = { joinAt = t, joinEst = true }
    trim(s, MemberHistory.MAX_STINTS)
    return true
end

-- Drops the former members who left longest ago until `h` holds at most `max` keys. Present members
-- (an open passage) stay, whatever the count. How many went.
function MemberHistory.Cap(h, max)
    local n, former = 0, {}
    for key, r in pairs(h) do
        n = n + 1
        local s = type(r) == "table" and r.stints
        local last = s and s[#s]
        local noted = type(r) == "table" and type(r.note) == "table"
        if (not last or last.leftAt) and not noted then former[#former + 1] = { key = key, at = last and last.leftAt or 0 } end
    end
    if n <= max then return 0 end
    table.sort(former, function(a, b) return a.at < b.at end)
    local removed = 0
    for _, f in ipairs(former) do
        if n <= max then break end
        h[f.key] = nil
        n, removed = n - 1, removed + 1
    end
    return removed
end

----------------------------------------------------------------------
-- Pure: the roster diff
----------------------------------------------------------------------
-- Whether a level up from `a` to `b` goes to the log: "all", "off", or "milestones" (the default):
-- a multiple of 10 reached, or the game's cap.
function MemberHistory.LevelWanted(mode, a, b, maxLevel)
    if not (a and b) or b <= a or mode == "off" then return false end
    if mode == "all" then return true end
    if maxLevel and b >= maxLevel then return true end
    return math.floor(b / 10) > math.floor(a / 10)
end

-- What changed between the roster last seen (`base`, key -> { r, rn, lv, n, o, off }) and this one
-- (`rows`, { key, r, rn, lv, n, o, off }). Returns the changes and whether the two share anybody
-- (a roster that shares nobody is keys that changed under it, not a guild of newcomers).
--   opts: levels (LevelWanted's mode), maxLevel, inactiveDays
function MemberHistory.Diff(base, rows, opts)
    opts = opts or {}
    local out, present, shared = {}, {}, false
    for _, row in ipairs(rows) do
        local key = row.key
        present[key] = true
        local b = base[key]
        if not b then
            out[#out + 1] = { kind = "join", key = key }
        else
            shared = true
            if b.r and row.r and b.r ~= row.r then
                out[#out + 1] = { kind = "rank", key = key, from = b.rn, to = row.rn, up = row.r < b.r }
            end
            if MemberHistory.LevelWanted(opts.levels or "milestones", b.lv, row.lv, opts.maxLevel) then
                out[#out + 1] = { kind = "level", key = key, from = b.lv, to = row.lv }
            end
            if b.n ~= nil and row.n ~= nil and b.n ~= row.n then
                out[#out + 1] = { kind = "note", key = key, from = b.n, to = row.n }
            end
            if b.o ~= nil and row.o ~= nil and b.o ~= row.o then
                out[#out + 1] = { kind = "onote", key = key, from = b.o, to = row.o }
            end
            local inactive = opts.inactiveDays or 30
            if b.off and b.off >= inactive and row.off and row.off < 1 then
                out[#out + 1] = { kind = "back", key = key, days = b.off }
            end
        end
    end
    for key in pairs(base) do
        if not present[key] then out[#out + 1] = { kind = "gone", key = key } end
    end
    return out, shared
end

----------------------------------------------------------------------
-- Reading (the API other features use; every call is safe with no history)
----------------------------------------------------------------------
local function store() return GuildOS.db and GuildOS.db.memberHistory end

-- The key a name is filed under, as the roster's: "Name" or "Name-Realm" as GetPlayerKey makes it.
function MemberHistory:KeyOf(name)
    if type(name) ~= "string" or name == "" then return nil end
    return GuildOS:KeyOfRosterName(name)
end

-- The member's passages, oldest first (the stored list: read it, never change it); {} when none.
function MemberHistory:Stints(key)
    local h = store()
    local r = h and key and h[key]
    return (type(r) == "table" and type(r.stints) == "table") and r.stints or {}
end

-- The member's rank changes, oldest first (the stored list); {} when none.
function MemberHistory:Ranks(key)
    local h = store()
    local r = h and key and h[key]
    return (type(r) == "table" and type(r.ranks) == "table") and r.ranks or {}
end

-- When the member's current passage started, and whether that is only when GuildOS saw them; nil when
-- they are not a member as far as the history knows (or it does not know when).
function MemberHistory:JoinedAt(key)
    local s = self:Stints(key)
    local last = s[#s]
    if last and last.leftAt == nil and last.joinAt then return last.joinAt, last.joinEst == true end
    return nil
end

-- Days in the guild over every passage (an open one counts to `now`), and how many passages; days nil
-- when no passage has a start.
function MemberHistory:TenureDays(key, now, dateFn)
    now = now or GetServerTime()
    local total, any = 0, false
    local s = self:Stints(key)
    for _, st in ipairs(s) do
        if st.joinAt then
            total, any = total + (MemberHistory.DaysBetween(st.joinAt, st.leftAt or now, dateFn) or 0), true
        end
    end
    return any and total or nil, #s
end

-- Whether the member's current passage starts on a day read from their note (#429).
function MemberHistory:JoinedFromNote(key)
    local s = self:Stints(key)
    local last = s[#s]
    return last ~= nil and last.leftAt == nil and last.joinSrc == "note"
end

-- The member's last passage when it is closed (they left), else nil.
function MemberHistory:LastLeft(key)
    local s = self:Stints(key)
    local last = s[#s]
    if last and last.leftAt then return last end
    return nil
end

-- Whether the history says this member left and has not come back.
function MemberHistory:IsFormer(key)
    return self:LastLeft(key) ~= nil
end

-- A date as the client's language writes it, with the year.
local function day(ts) return GuildOS:DateText(ts, "/%Y") end

local function howText(st)
    if st.how == "kick" then
        return st.by and string.format(L["removed by %s"], st.by) or L["removed"]
    elseif st.how == "leave" then
        return L["left"]
    end
    return L["left or was removed"]
end

-- One passage as a line: "03/02/2025 to 10/06/2025 (127 days), removed by Bob".
function MemberHistory:StintLine(st, now, dateFn)
    local from
    if not st.joinAt then from = L["before GuildOS saw them"]
    elseif st.joinSrc == "note" then from = string.format(L["%s (from a note)"], day(st.joinAt))
    elseif st.joinEst then from = string.format(L["%s (seen by GuildOS)"], day(st.joinAt))
    else from = day(st.joinAt) end
    local days = st.joinAt and MemberHistory.DaysBetween(st.joinAt, st.leftAt or now or GetServerTime(), dateFn)
    local daysText = days and tostring(days) or "?"
    if not st.leftAt then return string.format(L["since %s (%s days)"], from, daysText) end
    local to = day(st.leftAt) .. (st.leftEst and "*" or "")
    return string.format(L["%s to %s (%s days), %s"], from, to, daysText, howText(st))
end

-- "Ana was a member from ... to ... (127 days), removed by Bob." for a former member, with the count
-- and the days in all when they had several passages; nil when the history holds no departure.
function MemberHistory:Describe(name, key)
    key = key or self:KeyOf(name)
    local last = key and self:LastLeft(key)
    if not last then return nil end
    local who = name and (name:match("^([^-]+)") or name) or key
    local total, count = self:TenureDays(key)
    local line = self:StintLine(last)
    if count > 1 then
        return string.format(L["%s was a member %d times (%s days in all). Last: %s."], who, count,
            total and tostring(total) or "?", line)
    end
    return string.format(L["%s was a member: %s."], who, line)
end

-- A former member whispering (BanList's whisper check, issue #425): the officer is told, in chat, that they
-- were a member. True when a line was printed.
function MemberHistory:Warn(name, key)
    return self:Say(self:Describe(name, key))
end

-- A line Describe made, to an officer's chat: when somebody rejoins (the roster log here) or is about to be
-- invited (BanList's invite check). True when printed.
function MemberHistory:Say(text)
    if not text or not GuildOS:IsOfficer() then return false end
    GuildOS:Print("|cffFFAA33" .. text .. "|r")
    return true
end

-- Every former member, the latest departure first: key, first join, last departure and how, the
-- passages and the days in all. For the export and the panels.
function MemberHistory:Former()
    local out = {}
    for key, r in pairs(store() or {}) do
        local s = type(r) == "table" and r.stints
        local last = s and s[#s]
        if last and last.leftAt then
            local first
            for _, st in ipairs(s) do
                if st.joinAt then first = st; break end
            end
            local total = self:TenureDays(key)
            out[#out + 1] = { key = key, first = first, last = last, stints = #s, days = total }
        end
    end
    table.sort(out, function(a, b) return a.last.leftAt > b.last.leftAt end)
    return out
end

-- A former member coming back (#449, specs/salao/saidas.md): { leftAt, leftEst, how, by, away = days from the departure
-- to the return, past = days in the guild over the passages before, times = how many passages ended }. Asked before
-- the join opens a passage (the last one is closed: the return is `now`), or just after (the last one is open and the
-- one before it closed: the return is its start). Nil for somebody the history never saw leave.
function MemberHistory:ReturnInfo(key, now, dateFn)
    now = now or GetServerTime()
    local s = self:Stints(key)
    local last = s[#s]
    if not last then return nil end
    local gone, backAt, upto = last, now, #s
    if not last.leftAt then
        gone, backAt, upto = s[#s - 1], last.joinAt or now, #s - 1
        if not (gone and gone.leftAt) then return nil end
    end
    local past, any = 0, false
    for i = 1, upto do
        local st = s[i]
        if st.joinAt and st.leftAt then
            past, any = past + (MemberHistory.DaysBetween(st.joinAt, st.leftAt, dateFn) or 0), true
        end
    end
    return { leftAt = gone.leftAt, leftEst = gone.leftEst, how = gone.how, by = gone.by,
             away = math.max(0, MemberHistory.DaysBetween(gone.leftAt, backAt, dateFn) or 0),
             past = any and past or nil, times = upto }
end

-- The class last seen for `key` (kept past the member row, which goes with them, #203), or nil.
function MemberHistory:ClassOf(key)
    local h = store()
    local r = h and key and h[key]
    return type(r) == "table" and type(r.cls) == "string" and r.cls or nil
end

----------------------------------------------------------------------
-- The permanent note (#449): what the officers keep about a player, past any departure
----------------------------------------------------------------------
-- The note of `key` ({ text, author, ts, rev }), or nil. Officers only.
function MemberHistory:GetNote(key)
    if not GuildOS:IsOfficer() then return nil end
    local h = store()
    local r = h and key and h[key]
    local n = type(r) == "table" and r.note
    if type(n) ~= "table" or type(n.text) ~= "string" or n.text == "" then return nil end
    return n
end

-- The note of `key`, else the newest of its other characters' (the alt links): a note is about the player.
function MemberHistory:NoteFor(key)
    local own = self:GetNote(key)
    if own or not key then return own end
    local best
    for _, k in ipairs(GuildOS:GetLinkedChars(key)) do
        local n = k ~= key and self:GetNote(k)
        if n and (not best or (n.rev or 0) > (best.rev or 0)) then best = n end
    end
    return best
end

-- The text as it is kept: one line, no codes, NOTE_MAX bytes. "" empties the note.
function MemberHistory.CleanNote(text)
    if type(text) ~= "string" then return nil end
    return GuildOS:SanitizeUserText(text, MemberHistory.NOTE_MAX)
end

local function noteWire(k, n) return { k = k, x = n.text, a = n.author, t = n.ts, r = n.rev } end

local function publishNotes(items)
    local SS = GuildOS.SyncService
    if not SS or #items == 0 then return end
    for i = 1, #items, MemberHistory.NOTE_BATCH do
        local batch = {}
        for j = i, math.min(i + MemberHistory.NOTE_BATCH - 1, #items) do batch[#batch + 1] = items[j] end
        SS:Publish(MemberHistory.NOTE_DOMAIN, "set", { notes = batch }, { priority = "BULK" })
    end
end

-- Writes `key`'s note as this officer's and sends it to the officers. Whether it changed.
function MemberHistory:SetNote(key, text)
    if not GuildOS:IsOfficer() or type(key) ~= "string" or key == "" then return false end
    local h = store()
    if not h then return false end
    local clean = MemberHistory.CleanNote(text)
    if not clean then return false end
    local r = recOf(h, key, true)
    local held = type(r.note) == "table" and r.note or nil
    if (held and held.text or "") == clean then return false end
    local now = GetServerTime()
    r.note = { text = clean, author = GuildOS.Compat.PlayerName(), ts = now,
               rev = math.max(now, (held and tonumber(held.rev) or 0) + 1) }
    publishNotes({ noteWire(key, r.note) })
    if GuildOS.RosterLog then GuildOS.RosterLog:Refresh() end
    return true
end

-- Notes off the network ({ k, x, a, t, r } each), the newer revision winning. How many were taken.
function MemberHistory:ApplyNotes(list, sender)
    local h = store()
    if type(list) ~= "table" or not h then return 0 end
    local n = 0
    for i = 1, math.min(#list, MemberHistory.NOTE_BATCH * 2) do
        local it = list[i]
        local k = type(it) == "table" and type(it.k) == "string" and it.k ~= "" and #it.k <= 64
            and not it.k:find("|", 1, true) and GuildOS:LocalMemberKey(it.k)
        local rev = k and GuildOS.Finite(it.r)
        local text = k and type(it.x) == "string" and #it.x <= MemberHistory.NOTE_MAX * 2 and MemberHistory.CleanNote(it.x)
        if k and rev and rev >= 1 and text then
            local r = recOf(h, k, true)
            local held = type(r.note) == "table" and r.note or nil
            if not held or rev > (tonumber(held.rev) or 0) then
                local a = it.a
                if type(a) ~= "string" or a == "" or #a > STR_MAX or a:find("|", 1, true) then a = sender end
                r.note = { text = text, author = a, ts = GuildOS.Finite(it.t) or 0, rev = rev }
                n = n + 1
            end
        end
    end
    return n
end

-- From an officer over OFFICER (SyncService checked both). A member's client keeps nothing.
function MemberHistory:OnNoteSync(env, sender)
    if not GuildOS:IsOfficer() or type(env) ~= "table" or env.act ~= "set" or type(env.data) ~= "table" then return end
    if self:ApplyNotes(env.data.notes, sender and GuildOS:ShortName(sender)) > 0 and GuildOS.RosterLog then
        GuildOS.RosterLog:Refresh()
    end
end

-- The newest NOTE_BACKFILL notes again (a sync request's answer).
function MemberHistory:BackfillNotes()
    if not (GuildOS:IsOfficer() and GuildOS.SyncService) then return end
    if GuildOS.Compat.OfficerAddonChannel and not GuildOS.Compat.OfficerAddonChannel() then return end
    local items = {}
    for k, r in pairs(store() or {}) do
        local n = type(r) == "table" and r.note
        if type(n) == "table" and type(n.text) == "string" then items[#items + 1] = noteWire(k, n) end
    end
    table.sort(items, function(a, b) return (a.r or 0) > (b.r or 0) end)
    for i = #items, self.NOTE_BACKFILL + 1, -1 do items[i] = nil end
    publishNotes(items)
end

----------------------------------------------------------------------
-- Feeding: the Roster Log's events, the network, the roster diff
----------------------------------------------------------------------
local function mayRecord()
    return GuildOS.db and GuildOS.db.memberHistory and GuildOS:IsOfficer() and GuildOS:IsOnGuildDB()
end

-- An officer's import of a join day from the notes (NoteDates, #429): this client's history only.
function MemberHistory:ImportJoin(key, t)
    if not mayRecord() or not self:KeyOf(key) then return false end
    return MemberHistory.ApplyNoteJoin(GuildOS.db.memberHistory, key, t)
end

-- An event the Roster Log took (its own line or an officer's, synced): into the history, officers only.
function MemberHistory:FromAudit(evt)
    if type(evt) ~= "table" or not evt.target or not mayRecord() then return nil end
    local h, key, t = GuildOS.db.memberHistory, self:KeyOf(evt.target), tonumber(evt.timestamp)
    if not (key and t) then return nil end
    if evt.action == "join" then
        local res = MemberHistory.ApplyJoin(h, key, t, false)
        -- A join's officer is who invited them (the game's guild event log, Modules/GuildEventLog.lua).
        if evt.author then MemberHistory.SetInviter(h, key, t, evt.author, tonumber(evt.tol)) end
        return res
    elseif evt.action == "leave" or evt.action == "kick" then
        return MemberHistory.ApplyLeave(h, key, t, evt.action, evt.action == "kick" and evt.author or nil, false)
    elseif evt.action == "promote" or evt.action == "demote" then
        return MemberHistory.ApplyRank(h, key, t, nil, evt.detail, evt.author, false)
    end
    return nil
end

-- Who invited the passage that started at `t` (within `tol` seconds, or the open one when it started later than
-- `t`: a diff saw it after the fact). True when it was written; one already known stays.
function MemberHistory.SetInviter(h, key, t, by, tol)
    if type(by) ~= "string" or by == "" then return false end
    local r = recOf(h, key, false)
    local s = r and r.stints
    if not s then return false end
    tol = tol or 7200
    for i = #s, 1, -1 do
        local st = s[i]
        local at = st.joinAt
        if at and (math.abs(at - t) <= tol or (i == #s and st.joinEst and t <= at)) then
            if st.inv then return false end
            st.inv = by
            return true
        end
    end
    return false
end

-- Who invited the member's current passage, or nil.
function MemberHistory:InvitedBy(key)
    local s = self:Stints(key)
    local last = s[#s]
    return last and last.leftAt == nil and last.inv or nil
end

-- A line of the audit log the game's guild event log completed (GuildEventLog:Merge): the officer it lacked and
-- its time, into the history. Officers only.
function MemberHistory:FromLog(evt)
    return self:FromAudit(evt)
end

local function recId(rec)
    return string.format("%s|%s|%d", rec.k, rec.a, math.floor(rec.t / 60))
end

-- A record of this client's diff to the other officers, kept for the next login's backfill.
function MemberHistory:_Publish(rec)
    rec.id = recId(rec)
    session().seen[rec.id] = true
    local out = GuildOS.db.memberHistoryOut
    out[#out + 1] = rec
    trim(out, self.OUTBOX)
    if GuildOS.SyncService and GuildOS:IsOfficer() then
        GuildOS.SyncService:Publish("audit", "hist", { r = rec })
    end
end

-- At login (CommSystem's request answer, through RosterLog:Backfill): the last records again.
function MemberHistory:Backfill()
    if not (GuildOS.SyncService and GuildOS:IsOfficer() and GuildOS.db and GuildOS.db.memberHistoryOut) then return end
    for _, rec in ipairs(GuildOS.db.memberHistoryOut) do
        GuildOS.SyncService:Publish("audit", "hist", { r = rec })
    end
    self:BackfillNotes()
end

local function cleanStr(v)
    if v == nil then return nil end
    if type(v) ~= "string" or v == "" then return false end
    return GuildOS:SanitizeUserText(v, STR_MAX)
end

-- A record off the network, checked field by field, or nil.
function MemberHistory.ValidRecord(rec, now)
    if type(rec) ~= "table" or type(rec.k) ~= "string" or rec.k == "" or #rec.k > 64 then return nil end
    if rec.a ~= "j" and rec.a ~= "l" and rec.a ~= "r" then return nil end
    local t = GuildOS.Finite(rec.t)
    if not t or t <= 0 or t > now + FUTURE_SLACK then return nil end
    local by, from, to = cleanStr(rec.b), cleanStr(rec.f), cleanStr(rec.to)
    if by == false or from == false or to == false then return nil end
    if rec.a == "r" and not to then return nil end
    local how = rec.h
    if rec.a == "l" and how ~= "leave" and how ~= "kick" and how ~= "gone" then return nil end
    return { k = GuildOS:SanitizeUserText(rec.k, 64), a = rec.a, t = t, e = rec.e and true or nil,
        h = rec.a == "l" and how or nil, b = by, f = from, to = to }
end

-- From an officer (SyncService checked the officer and GUILD, RosterLog routed it): applied on an
-- officer's client only, once per id.
function MemberHistory:OnSync(data)
    if type(data) ~= "table" or not mayRecord() then return end
    local rec = MemberHistory.ValidRecord(data.r, GetServerTime())
    if not rec then return end
    local id = recId(rec)
    local seen = session().seen
    if seen[id] then return end
    seen[id] = true
    local h = GuildOS.db.memberHistory
    if rec.a == "j" then
        MemberHistory.ApplyJoin(h, rec.k, rec.t, rec.e)
    elseif rec.a == "l" then
        MemberHistory.ApplyLeave(h, rec.k, rec.t, rec.h, rec.b, rec.e)
    else
        MemberHistory.ApplyRank(h, rec.k, rec.t, rec.f, rec.to, rec.b, rec.e)
    end
end

-- The history from what this client already held, once: the Roster Log's events, oldest first, then
-- an open passage for every present member, from when GuildOS first saw them (firstSeen) or their
-- founding date (WoW: Forever), whichever is earlier. Before that, nothing is known.
function MemberHistory:Migrate(rows, now)
    local db = GuildOS.db
    if db.memberHistoryMigrated then return end
    db.memberHistoryMigrated = true
    local h = db.memberHistory
    local events = {}
    for _, e in ipairs(db.rosterLog and db.rosterLog.events or {}) do events[#events + 1] = e end
    table.sort(events, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
    for _, e in ipairs(events) do
        local key, t = e.target and self:KeyOf(e.target), tonumber(e.timestamp)
        if key and t then
            if e.action == "join" then MemberHistory.ApplyJoin(h, key, t, false)
            elseif e.action == "leave" or e.action == "kick" then
                MemberHistory.ApplyLeave(h, key, t, e.action, e.action == "kick" and e.author or nil, false)
            elseif e.action == "promote" or e.action == "demote" then
                MemberHistory.ApplyRank(h, key, t, nil, e.detail, e.author, false)
            end
        end
    end
    local seen, founding = db.firstSeen or {}, db.foundingJoins or {}
    for _, row in ipairs(rows) do
        local t = tonumber(seen[row.key]) or now
        local f = type(founding[row.key]) == "table" and tonumber(founding[row.key].joinedAt)
        if f and f > 0 and f < t then t = f end
        MemberHistory.EnsureOpen(h, row.key, t)
    end
    MemberHistory.Cap(h, self.MAX_KEYS)
end

-- The whole roster as rows, or nil while it is not whole (a row missing would read as gone).
-- The rows are the last read's, refilled (memory audit): a table a member every pass was the scan's garbage.
-- Nothing keeps a row past the scan that reads it (Diff, Migrate, Pairs and snapshot copy what they keep).
local scratchRows = {}
local function readRoster()
    local n = GetNumGuildMembers() or 0
    if n == 0 then return nil end
    local onotes = GuildOS.Compat.CanViewOfficerNote and GuildOS.Compat.CanViewOfficerNote()
    local rows = scratchRows
    for i = 1, n do
        local full, rankName, rankIndex, level, _, _, note, onote, online, _, classFile = GetGuildRosterInfo(i)
        if not full then return nil end
        local off = 0
        if not online and GetGuildRosterLastOnline then
            local y, mo, d = GetGuildRosterLastOnline(i)
            off = (y or 0) * 365 + (mo or 0) * 30 + (d or 0)
        end
        local row = rows[i]
        if not row then row = {}; rows[i] = row end
        row.key, row.r, row.rn = GuildOS:KeyOfRosterName(full), rankIndex, rankName
        row.lv, row.n, row.o, row.off = level, note or "", onotes and (onote or "") or nil, off
        row.cls = type(classFile) == "string" and classFile ~= "" and classFile or nil
        row.g = GuildOS.Compat.GuildRosterGUID(i)
    end
    for i = #rows, n + 1, -1 do rows[i] = nil end
    return rows
end

local function short(key) return key:match("^([^-]+)") or key end

local function snapshot(rows, into)
    into = into or {}
    for _, row in ipairs(rows) do
        local b = into[row.key]
        if not b then b = {}; into[row.key] = b end
        b.r, b.rn, b.lv, b.n, b.o, b.off, b.c, b.g = row.r, row.rn, row.lv, row.n, row.o, row.off, row.cls, row.g
    end
    return into
end

local function names(list)
    local shown = {}
    for i = 1, math.min(#list, NAMES_SHOWN) do shown[i] = list[i] end
    local text = table.concat(shown, ", ")
    if #list > NAMES_SHOWN then text = text .. " +" .. (#list - NAMES_SHOWN) end
    return text
end

-- A line of the Roster Log from this client's diff: kept here, never sent (`loc`: RosterLog's backfill
-- leaves it out), since every officer's client sees the same change.
local function logLocal(action, key, detail, author, rejoin)
    if not GuildOS.RosterLog then return end
    GuildOS.RosterLog:_Insert({ action = action, target = short(key), detail = detail, author = author,
        rejoin = rejoin or nil, timestamp = GetServerTime(), loc = true })
end

-- The roster against the one last seen, at most every SCAN_GAP seconds (Core's roster pass calls it).
function MemberHistory:Schedule()
    GuildOS:Coalesce("memberHistory", self.SCAN_GAP, function() GuildOS:SafeCall(self.Scan, self) end)
end

-- One diff, on an officer's client in the guild whose db is loaded, once the login has settled and
-- the client knows its rank, on the whole roster. A non-officer's look changes nothing: the next
-- officer's look covers the time since the last one (an alt shares the account's db). The first diff
-- of a session prints what changed "since your last login", once.
function MemberHistory:Scan()
    local st = session()
    if not st.settled then return end
    local db = GuildOS.db
    if not (db and db.memberHistory and IsInGuild() and GuildOS:IsOnGuildDB()) then return end
    if select(3, GetGuildInfo("player")) == nil or not GuildOS:IsOfficer() then return end
    local rows = readRoster()
    if not rows then return end
    local now, h = GetServerTime(), db.memberHistory
    self:Migrate(rows, now)
    -- The class each member has, for when they are gone (the departure popup's list of characters, #449).
    for _, row in ipairs(rows) do
        local r = row.cls and h[row.key]
        if type(r) == "table" and r.cls ~= row.cls then r.cls = row.cls end
    end
    local base = db.memberHistoryBase
    local changes, shared
    if type(base) == "table" and type(base.m) == "table" and next(base.m) then
        changes, shared = MemberHistory.Diff(base.m, rows, {
            levels = self:GetLevelMode(),
            maxLevel = GuildOS.Client and GuildOS.Client.maxLevel,
            inactiveDays = self:BackDays() > 0 and self:BackDays() or self.DefaultBackDays(),
        })
    end
    if not (changes and shared) then
        -- The first look, or keys that changed under it: only the roster is taken.
        for _, row in ipairs(rows) do MemberHistory.EnsureOpen(h, row.key, tonumber(db.firstSeen and db.firstSeen[row.key]) or now) end
        db.memberHistoryBase = { at = now, m = snapshot(rows) }
        st.diffed = true
        return
    end
    local first = not st.diffed
    st.diffed = true
    local sinceLogin = first and L["since your last login"] or nil
    local joined, gone, ranked, back, added = {}, {}, {}, {}, false
    -- A rename (Modules/MemberRename.lua): the same GUID under a new name moves at once; a likely one without a
    -- GUID is asked about, its two keys left out of this diff (and of the snapshot) until the officer answers.
    local MR, skip, held = GuildOS.MemberRename, nil, nil
    if MR then
        local pairs_ = MR.Pairs(changes, base.m, rows)
        for _, p in ipairs(pairs_) do
            if p.how == "guid" or MR:Accepted(p.old, p.new) then
                skip = skip or {}
                skip[p.old], skip[p.new] = true, true
                GuildOS:SafeCall(MR.Apply, MR, p.old, p.new, p.how)
                base.m[p.old] = nil
            elseif not MR:Declined(p.old, p.new) then
                skip = skip or {}
                skip[p.old], skip[p.new] = true, true
                held = held or {}
                held[#held + 1] = p
                MR:Propose(p.old, p.new)
            end
        end
    end
    if skip then
        local kept = {}
        for _, c in ipairs(changes) do
            if not skip[c.key] then kept[#kept + 1] = c end
        end
        changes = kept
    end
    for _, c in ipairs(changes) do
        local k = c.key
        if c.kind == "join" then
            local past = self:Describe(short(k), k)   -- before the join opens a passage
            local backInfo = self:ReturnInfo(k, now)
            local res = MemberHistory.ApplyJoin(h, k, now, true)
            joined[#joined + 1] = short(k)
            added = true
            if res == "join" or res == "rejoin" then
                logLocal("join", k, sinceLogin, nil, res == "rejoin")
                self:_Publish({ k = k, a = "j", t = now, e = true })
                if res == "rejoin" then
                    self:Say(past)
                    if backInfo and GuildOS.Departure then
                        GuildOS:SafeCall(GuildOS.Departure.OnReturn, GuildOS.Departure, k, short(k), backInfo)
                    end
                end
            end
        elseif c.kind == "gone" then
            local changed = MemberHistory.ApplyLeave(h, k, now, "gone", nil, true)
            local last = self:LastLeft(k)
            gone[#gone + 1] = short(k) .. (last and last.how == "kick" and last.by and (" (" .. string.format(L["removed by %s"], last.by) .. ")") or "")
            if changed then
                logLocal("gone", k, sinceLogin)
                self:_Publish({ k = k, a = "l", t = now, e = true, h = "gone" })
                -- Nobody saw the game's line here: the departure popup asks about it (deduped with the line, #449).
                if GuildOS.Departure then GuildOS:SafeCall(GuildOS.Departure.OnGone, GuildOS.Departure, k, now) end
            end
            base.m[k] = nil
        elseif c.kind == "rank" then
            ranked[#ranked + 1] = short(k)
            if MemberHistory.ApplyRank(h, k, now, c.from, c.to, nil, true) then
                logLocal(c.up and "promote" or "demote", k, c.to)
                self:_Publish({ k = k, a = "r", t = now, e = true, f = c.from, to = c.to })
            end
        elseif c.kind == "level" then
            logLocal("level", k, string.format("%d > %d", c.from, c.to))
        elseif c.kind == "note" then
            logLocal("note", k, GuildOS:SanitizeUserText(c.to, 31))
        elseif c.kind == "onote" then
            logLocal("onote", k, GuildOS:SanitizeUserText(c.to, 31))
        elseif c.kind == "back" then
            logLocal("back", k, string.format(L["after %d days offline"], c.days))
            back[#back + 1] = string.format("%s (%d)", short(k), c.days)
        end
    end
    snapshot(rows, base.m)
    for _, p in ipairs(held or {}) do base.m[p.new] = nil end   -- still asked about: the next diff sees it again
    base.at = now
    if added then MemberHistory.Cap(h, self.MAX_KEYS) end
    if #changes > 0 and GuildOS.RosterLog then GuildOS.RosterLog:Refresh() end
    if first and (#joined + #gone + #ranked) > 0 then
        local parts = {}
        if #joined > 0 then parts[#parts + 1] = string.format(L["%d joined (%s)"], #joined, names(joined)) end
        if #gone > 0 then parts[#parts + 1] = string.format(L["%d left or were removed (%s)"], #gone, names(gone)) end
        if #ranked > 0 then parts[#parts + 1] = string.format(L["%d changed rank (%s)"], #ranked, names(ranked)) end
        GuildOS:Print(L["Since your last login:"] .. " " .. table.concat(parts, "; "))
    end
    -- Back after a long time offline (#429): one line a look, a member in it once a return (the snapshot holds
    -- them online from now on, so the next look does not see the return again).
    if #back > 0 and self:BackDays() > 0 then
        self:Say(string.format(L["Back after a long time offline (days): %s"], names(back)))
    end
end

-- The days offline a member must have been away for their return to be told to the officer; the log's "Back" uses it
-- too. 0 turns the line off (the log keeps the default).
MemberHistory.BACK_MAX = 365
function MemberHistory.DefaultBackDays()
    return GuildOS.GuildManager and GuildOS.GuildManager.DEFAULT_INACTIVE_DAYS or 30
end

function MemberHistory:BackDays()
    local n = tonumber(GuildOS:GetSetting("backAfterDays"))
    if n == nil then return self.DefaultBackDays() end
    return n
end

-- Officers only; 0 (off) to BACK_MAX. Whether it changed.
function MemberHistory:SetBackDays(n)
    n = GuildOS.Finite(n)
    if not GuildOS:IsOfficer() or not n or n < 0 or n > self.BACK_MAX then return false end
    GuildOS:SetSetting("backAfterDays", math.floor(n))
    return true
end

-- The Roster Log's level filter: "milestones" (default), "all" or "off". Officers only.
MemberHistory.LEVEL_MODES = { "milestones", "all", "off" }
function MemberHistory:SetLevelMode(mode)
    if not GuildOS:IsOfficer() then return false end
    for _, m in ipairs(self.LEVEL_MODES) do
        if m == mode then GuildOS:SetSetting("historyLevels", mode); return true end
    end
    return false
end

function MemberHistory:GetLevelMode()
    return GuildOS:GetSetting("historyLevels") or "milestones"
end

-- The next mode after the current one (the log's button). Whether it changed.
function MemberHistory:CycleLevelMode()
    local cur, modes = self:GetLevelMode(), self.LEVEL_MODES
    for i, m in ipairs(modes) do
        if m == cur then return self:SetLevelMode(modes[i % #modes + 1]) end
    end
    return self:SetLevelMode(modes[1])
end
