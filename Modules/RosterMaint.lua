----------------------------------------------------------------------
-- Guild OS - Roster maintenance (specs/salao/manutencao-roster.md)
-- What the officers keep tidy in a big guild, computed from data the addon already has and syncs (the member
-- history, #425; the alt links, #424; the notes the game hands out; the nicknames, #429). Nothing new is
-- stored or sent: every answer here is read from those.
--
--   * Time in rank and in the guild: when the member's current rank started (their last rank change, else
--     their join), and the days since, for the Members column, the Bulk actions rules and the suggestions.
--   * The data audit (Officers' Room > Members > Data audit): who has no real join date, no alt link at all,
--     or a join date in a note that is not the history's; each with the existing flow that fixes it.
--   * Alt-aware inactivity: the most recently seen other character of a member's group, so "inactive" can
--     mean the player and not the character.
--   * The roster's search over the notes, the main's name and the nickname.
--
-- Big guilds (1000+): every pass here is one walk of the roster with table lookups (no GetLinkedChars per
-- member, which walks every link), and the audit is cached until the roster or an action changes it.
-- Business logic only, no frames.
----------------------------------------------------------------------
local RosterMaint = {}
GuildOS.RosterMaint = RosterMaint
local L = GuildOS.L

RosterMaint.KINDS = { "nodate", "noalt", "notediff" }
RosterMaint.CACHE_SECONDS = 20     -- an audit is computed again at most this often unless invalidated
RosterMaint.STUCK_DAYS = 90        -- the "long in rank" suggestion's default
RosterMaint.STUCK_MAX = 25         -- members that suggestion lists at most

local DAY = 86400

local function short(name) return name and (name:match("^([^-]+)") or name) or "?" end

-- A note as text this client may read, or "" (a Secret Value on WoW: Forever, or nil).
local function noteText(v)
    if v == nil or GuildOS.Compat.IsSecret(v) or type(v) ~= "string" then return "" end
    return v
end
RosterMaint.NoteText = noteText

----------------------------------------------------------------------
-- Pure: days, groups, the audit's rules (tools/roster-audit.lua)
----------------------------------------------------------------------
--- Whole days from `t` to `now` (never negative), or nil without `t`.
function RosterMaint.Days(t, now)
    if type(t) ~= "number" or type(now) ~= "number" then return nil end
    return math.max(0, math.floor((now - t) / DAY))
end

--- When the member's current rank started from their history: the last rank change when it is in the current
--- passage, else the passage's start. `ranks` and `stints` are MemberHistory's lists. Returns the time and whether it
--- is only when Guild OS saw it (est), or nil.
function RosterMaint.RankSinceOf(ranks, stints)
    local st = stints and stints[#stints]
    local open = st and st.leftAt == nil
    local join = open and st.joinAt or nil
    local last = ranks and ranks[#ranks]
    if last and last.at and (not join or last.at >= join) then return last.at, last.est == true end
    if join then return join, st.joinEst == true end
    return nil
end

--- The most recently seen OTHER character of each member's alt group. `rows`: { { key, name, days } } with days the
--- days offline (0 online, nil unknown); `links`: db.altLinks (alt -> main). Returns a map key -> { key, name, days,
--- main (it is the group's main) } for every member whose group has another character on the roster with a known
--- day, and a map key -> group main for every member in a group of two or more. One pass, two lowest per group.
function RosterMaint.GroupSeen(rows, links)
    links = links or {}
    local groups = {}
    for _, r in ipairs(rows or {}) do
        local main = links[r.key] or r.key
        local g = groups[main]
        if not g then g = { n = 0 }; groups[main] = g end
        g.n = g.n + 1
        if r.days ~= nil then
            if not g.a or r.days < g.a.days then g.b = g.a; g.a = r
            elseif not g.b or r.days < g.b.days then g.b = r end
        end
    end
    local seen, mainOf = {}, {}
    for _, r in ipairs(rows or {}) do
        local main = links[r.key] or r.key
        local g = groups[main]
        if g.n > 1 then
            mainOf[r.key] = main
            local best = (g.a == r) and g.b or g.a
            if best then
                seen[r.key] = { key = best.key, name = best.name, days = math.floor(best.days), main = best.key == main }
            end
        end
    end
    return seen, mainOf
end

--- The days the player behind a character was last seen: the least of its own and its group's other characters'.
function RosterMaint.PlayerDays(own, other)
    if own == nil then return nil end
    if other and other.days ~= nil and other.days < own then return other.days end
    return own
end

--- What a "seen" line says of another character of the group: "main Xyz seen 2d ago", "alt Xyz online now".
function RosterMaint.SeenText(other)
    if not other then return nil end
    local who = string.format(other.main and L["main %s"] or L["alt %s"], other.name or "?")
    if (other.days or 0) <= 0 then return string.format(L["%s seen today"], who) end
    return string.format(L["%s seen %dd ago"], who, other.days)
end

--- The audit's problems for one member. `m`: { joinAt, joinEst, joinFromNote, linked, public, officer (nil when this
--- rank cannot read them) }; `order`, `maxYear` as NoteDates.Parse; `dateFn` the clock's date (tests pass their own).
--- Returns the set { nodate, noalt, notediff } (each true or nil) and, for notediff, { which = "public" | "officer",
--- day = { year, month, day } }: the first readable note whose date is not the history's day.
function RosterMaint.Classify(m, order, maxYear, dateFn)
    local ND, MH = GuildOS.NoteDates, GuildOS.MemberHistory
    dateFn = dateFn or date
    local p, diff = {}, nil
    local real = m.joinAt ~= nil and (not m.joinEst or m.joinFromNote)
    if not real then p.nodate = true end
    if not m.linked then p.noalt = true end
    if real and ND and MH then
        local d = dateFn("*t", m.joinAt)
        local known = MH.DayNumber(d.year, d.month, d.day)
        for _, which in ipairs({ "public", "officer" }) do
            local text = m[which]
            local day = text and text ~= "" and ND.Parse(text, order, maxYear)
            if day and MH.DayNumber(day.year, day.month, day.day) ~= known then
                p.notediff, diff = true, { which = which, day = day }
                break
            end
        end
    end
    return p, diff
end

--- Whether a row has any problem.
function RosterMaint.HasProblem(p)
    return p ~= nil and (p.nodate or p.noalt or p.notediff) ~= nil
end

--- The rows of `rows` of problem `kind` ("all" or nil: any) whose name, rank or nickname holds `text`.
function RosterMaint.Filter(rows, kind, text)
    text = strlower(strtrim(text or ""))
    local out = {}
    for _, r in ipairs(rows or {}) do
        local okKind = (kind == nil or kind == "all") or r.problems[kind]
        local okText = text == "" or strlower(r.name or ""):find(text, 1, true)
            or strlower(r.rankName or ""):find(text, 1, true) or (r.nick and strlower(r.nick):find(text, 1, true))
        if okKind and okText then out[#out + 1] = r end
    end
    return out
end

--- How many rows have each problem: { all, nodate, noalt, notediff }.
function RosterMaint.Count(rows)
    local c = { all = #(rows or {}), nodate = 0, noalt = 0, notediff = 0 }
    for _, r in ipairs(rows or {}) do
        for _, k in ipairs(RosterMaint.KINDS) do if r.problems[k] then c[k] = c[k] + 1 end end
    end
    return c
end

-- What a column sorts by; a member with no value goes last whichever way.
local SORT = {
    name = function(r) return strlower(r.name or "") end,
    rank = function(r) return r.rankIndex end,
    rankDays = function(r) return r.rankDays end,
    joined = function(r) return r.joinAt end,
}
RosterMaint.SORTS = { "name", "rank", "rankDays", "joined" }

--- `rows` sorted in place by `by` (name, rank, rankDays, joined), ascending when `asc`; ties by name. Returns it.
function RosterMaint.Sort(rows, by, asc)
    local key = SORT[by] or SORT.name
    table.sort(rows, function(a, b)
        local va, vb = key(a), key(b)
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if asc then return va < vb end
            return va > vb
        end
        return strlower(a.name or "") < strlower(b.name or "")
    end)
    return rows
end

--- Whether a roster line matches the search `text` (lower case) by its note, officer note, main or nickname, and by
--- which: "note", "onote", "main" or "nick"; nil when none does. `d`: { note, officerNote (nil: unreadable), main,
--- nick }. The name, class, zone and rank are the caller's own.
function RosterMaint.MatchVia(d, text)
    if text == nil or text == "" then return nil end
    local function has(v) return v ~= nil and v ~= "" and strlower(v):find(text, 1, true) ~= nil end
    if has(d.note) then return "note" end
    if has(d.officerNote) then return "onote" end
    if has(d.main) then return "main" end
    if has(d.nick) then return "nick" end
    return nil
end

local VIA_TEXT = { note = L["note"], onote = L["officer note"], nick = L["nickname"] }
--- The small tag a row matched by MatchVia shows: "note", "officer note", "nickname", or "Alt of <main>" (`main`).
function RosterMaint.ViaText(via, main)
    if via == "main" then return string.format(L["Alt of %s"], main or "?") end
    return via and VIA_TEXT[via] or nil
end

----------------------------------------------------------------------
-- The live data
----------------------------------------------------------------------
--- When `key`'s current rank started (and est), from the member history; nil when it does not know.
function RosterMaint:RankSince(key)
    local MH = GuildOS.MemberHistory
    if not (MH and key) then return nil end
    return self.RankSinceOf(MH:Ranks(key), MH:Stints(key))
end

--- Days in the current rank (and est), or nil.
function RosterMaint:RankDays(key, now)
    local t, est = self:RankSince(key)
    return self.Days(t, now or GetServerTime()), est, t
end

--- Days in the guild over every passage, or nil (MemberHistory:TenureDays).
function RosterMaint:TenureDays(key, now)
    local MH = GuildOS.MemberHistory
    if not (MH and key) then return nil end
    return (MH:TenureDays(key, now or GetServerTime()))
end

--- The whole roster as { key, name, fullName, index, days } (days offline: 0 online, nil unknown). One pass.
function RosterMaint:RosterRows()
    local GM = GuildOS.GuildManager
    local out = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local full, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if full then
            local off = online and 0 or (GM and GM:GetDaysOffline(i)) or nil
            out[#out + 1] = { key = GuildOS:KeyOfRosterName(full), name = short(full), fullName = full, index = i,
                days = off and math.floor(off) or nil }
        end
    end
    return out
end

--- GroupSeen of the live roster and links: (seen, mainOf).
function RosterMaint:GroupSeenNow()
    return self.GroupSeen(self:RosterRows(), GuildOS.db and GuildOS.db.altLinks)
end

--- Whether the inactivity counts a player's other characters (the Inactivity screen's setting; on by default).
function RosterMaint:CountAlts()
    return GuildOS:GetSetting("inactiveCountAlts") ~= false
end

function RosterMaint:SetCountAlts(on)
    if not GuildOS:IsOfficer() then return false end
    GuildOS:SetSetting("inactiveCountAlts", on and true or false)
    self:Invalidate()
    return true
end

--- Whether a bulk removal by days takes a whole alt group, and only once every character in it is inactive (off).
function RosterMaint:WholeGroup()
    return GuildOS:GetSetting("bulkWholeGroup") == true
end

function RosterMaint:SetWholeGroup(on)
    if not GuildOS:IsOfficer() then return false end
    GuildOS:SetSetting("bulkWholeGroup", on and true or false)
    return true
end

----------------------------------------------------------------------
-- The data audit
----------------------------------------------------------------------
local cache = { at = nil, n = nil, data = nil }

--- Drop the audit's cache: the next Audit computes it again (an action changed what it reads).
function RosterMaint:Invalidate()
    cache.at, cache.data = nil, nil
end

--- The audit of the live roster: { rows, counts }. Each row { key, name, fullName, class, level, rankName, rankIndex,
--- online, nick, joinAt, joinEst, rankDays, rankSince, rankEst, problems, noteDiff }, only members with a problem.
--- Officers only (an empty audit otherwise). Cached for CACHE_SECONDS unless `force` or Invalidate, and while the
--- roster keeps its size.
function RosterMaint:Audit(force)
    if not GuildOS:IsOfficer() then return { rows = {}, counts = self.Count({}) } end
    local now = GetServerTime()
    local n = GetNumGuildMembers() or 0
    if not force and cache.data and cache.n == n and cache.at and now - cache.at < self.CACHE_SECONDS then
        return cache.data
    end
    local MH, ND, MM = GuildOS.MemberHistory, GuildOS.NoteDates, GuildOS.MemberMarks
    local links = (GuildOS.db and GuildOS.db.altLinks) or {}
    local hasAlts = {}
    for _, main in pairs(links) do hasAlts[main] = true end
    local onotes = GuildOS.Compat.CanViewOfficerNote()
    local order = ND and ND:Order() or "dmy"
    local maxYear = tonumber(date("%Y", now))
    local rows = {}
    for i = 1, n do
        local full, rankName, rankIndex, level, _, _, note, onote, online, _, classFile = GetGuildRosterInfo(i)
        if full then
            local key = GuildOS:KeyOfRosterName(full)
            local joinAt, joinEst
            if MH then joinAt, joinEst = MH:JoinedAt(key) end
            local m = { joinAt = joinAt, joinEst = joinEst, joinFromNote = MH and MH:JoinedFromNote(key) or false,
                linked = links[key] ~= nil or hasAlts[key] == true,
                public = noteText(note), officer = onotes and noteText(onote) or nil }
            local problems, diff = self.Classify(m, order, maxYear)
            if self.HasProblem(problems) then
                local since, est = self:RankSince(key)
                rows[#rows + 1] = {
                    key = key, name = short(full), fullName = full, class = classFile or "", level = level or 0,
                    rankName = rankName or "?", rankIndex = rankIndex, online = online and true or false,
                    nick = MM and MM:Nick(key) or nil, joinAt = joinAt, joinEst = joinEst,
                    rankSince = since, rankEst = est, rankDays = self.Days(since, now),
                    problems = problems, noteDiff = diff,
                }
            end
        end
    end
    local data = { rows = rows, counts = self.Count(rows), at = now }
    cache.at, cache.n, cache.data = now, n, data
    return data
end

-- The actions on an audit row: each opens the existing flow that fixes it (Rule 10: the screen calls these).
--- "Write date": the Notes and marks screen's join-date flow, its member box filled with this one.
function RosterMaint:WriteDate(row)
    if not (row and GuildOS.NoteDates) then return false end
    GuildOS.NoteDates:Prefill(row.fullName)
    if GuildOS.UI and GuildOS.UI.OpenWindow then GuildOS.UI:OpenWindow("management", "marks") end
    self:Invalidate()
    return true
end

--- "Fix note": the history's date into the note that differs (NoteDates:WriteOne, which asks before it replaces).
function RosterMaint:FixNote(row)
    if not (row and row.noteDiff and GuildOS.NoteDates) then return false end
    self:Invalidate()
    return GuildOS.NoteDates:WriteOne(row.fullName, nil, row.noteDiff.which)
end

--- The member's window (a row's click, "Open").
function RosterMaint:Open(row, focus)
    if not row then return false end
    local rec = GuildOS:GetMemberRecord(row.fullName or row.name)
    if not (rec and GuildOS.ShowMemberDetail) then return false end
    GuildOS:ShowMemberDetail(rec, focus)
    return true
end

--- "Link alt…": the member's window, on its Add alt box (the existing link flow).
function RosterMaint:LinkAlt(row)
    self:Invalidate()
    return self:Open(row, "alt")
end

----------------------------------------------------------------------
-- Suggestions: members long in their rank
----------------------------------------------------------------------
--- The days the "long in rank" suggestion asks for (the guild's setting "stuckRankDays", else STUCK_DAYS).
function RosterMaint:StuckDays()
    local v = tonumber(GuildOS:GetSetting("stuckRankDays"))
    return (v and v >= 1) and math.floor(v) or self.STUCK_DAYS
end

--- Members in their rank for StuckDays or more, the longest first, at most STUCK_MAX: never a trial, an officer, nor
--- one whose next step up is an officer's rank (that is the officers' own decision, not a suggestion);
--- { key, name, fullName, class, rankName, rankIndex, rankDays, est }. Only for a rank that may promote. `all`: every
--- one, not only the first STUCK_MAX (the login digest's count).
function RosterMaint:StuckInRank(now, all)
    local GM = GuildOS.GuildManager
    if not (GuildOS:IsOfficer() and GM and GM:CanPromote() and GuildOS.MemberHistory) then return {} end
    now = now or GetServerTime()
    local min = self:StuckDays()
    local officerMaxRank = GuildOS:GetSetting("officerMaxRank") or 1
    local TT = GuildOS.TrialTracker
    local out = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local full, rankName, rankIndex, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if full and rankIndex and rankIndex > officerMaxRank + 1 then
            local key = GuildOS:KeyOfRosterName(full)
            if not (TT and TT:IsTrial(key)) then
                local days, est = self:RankDays(key, now)
                if days and days >= min then
                    out[#out + 1] = { key = key, name = short(full), fullName = full, class = classFile or "",
                        rankName = rankName or "?", rankIndex = rankIndex, rankDays = days, est = est }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.rankDays ~= b.rankDays then return a.rankDays > b.rankDays end
        return a.name:lower() < b.name:lower()
    end)
    if not all then
        for i = #out, self.STUCK_MAX + 1, -1 do out[i] = nil end
    end
    return out
end
