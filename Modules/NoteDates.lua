----------------------------------------------------------------------
-- Guild OS - Join dates in the guild notes (issue #429, epic #423 group F)
-- Writes the date a member joined (the member history's, #425) into their public or officer note, in
-- the format the officer picks, for one member or the whole guild; and reads dates already written in
-- the notes (by hand, or by another addon) back into the history, after the officer has looked at them.
--
-- Writing never takes anything away without asking: an empty note gets the date, a note with room gets
-- it after a space, a note that already says it is left alone; a note with another date, or without
-- room for one, is only rewritten from a confirmation that shows the old and the new text. 31 bytes is
-- the game's cap and nothing longer is ever sent.
--
-- Where the client lets an addon write a note (TBC Anniversary, Compat.CanWriteNote), a run writes one
-- note every GAP seconds, doubled on "You are doing that too fast" (ERR_GENERIC_THROTTLE, #392/#393).
-- A write the game blocks (ADDON_ACTION_BLOCKED: it wants a click) turns the run into one note per click
-- of Next; one it forbids (ADDON_ACTION_FORBIDDEN, as WoW: Forever and retail do) turns it into "copy
-- the text": each click shows the note to paste into the game's roster. Session state only.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local NoteDates = {}
GuildOS.NoteDates = NoteDates
local L = GuildOS.L

NoteDates.NOTE_MAX = 31          -- the game's cap on a guild note, in bytes
NoteDates.FORMATS = { "dd/mm/yy", "mm/dd/yy", "dd.mm.yyyy", "yyyy-mm-dd" }
NoteDates.LABEL = "Joined: "     -- what the label option puts before the date (the import reads any "word:")
NoteDates.GAP = 2                -- seconds between two writes of a run
NoteDates.MAX_GAP = 32           -- what the doubling on the throttle stops at
NoteDates.CALM_WRITES = 5        -- writes in a row without the throttle before the gap halves back
NoteDates.MIN_YEAR = 2004        -- no guild is older than the game
local BLOCK_WINDOW = 2           -- seconds after a write within which a blocked-action event is about it
local DAY_END_HOUR, DAY_END_MIN = 23, 59   -- an imported day is filed at its last minute (see ImportTime)
local MONTH_FIRST = { enUS = true, koKR = true, zhCN = true, zhTW = true }   -- as GuildOS:DateText

local function state()
    GuildOS.State.noteDates = GuildOS.State.noteDates or {}
    return GuildOS.State.noteDates
end

function NoteDates:Initialize()
    state()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "UI_ERROR_MESSAGE")
    GuildOS.Compat.RegisterEvent(f, "ADDON_ACTION_BLOCKED")
    GuildOS.Compat.RegisterEvent(f, "ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "UI_ERROR_MESSAGE" then
            GuildOS:SafeCall(NoteDates.OnError, NoteDates, ...)
        else
            GuildOS:SafeCall(NoteDates.OnBlocked, NoteDates, event, ...)
        end
    end)
end

----------------------------------------------------------------------
-- Pure: dates (tools/note-dates.lua)
----------------------------------------------------------------------
local function leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end
local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

--- Whether y-m-d is a real day from MIN_YEAR up to `maxYear` (none: any year after it).
function NoteDates.ValidDay(y, m, d, maxYear)
    if not (y and m and d) or m < 1 or m > 12 or d < 1 then return false end
    if y < NoteDates.MIN_YEAR or (maxYear and y > maxYear) then return false end
    local last = MONTH_DAYS[m] + ((m == 2 and leap(y)) and 1 or 0)
    return d <= last
end

--- The order a slashed date with a two-part day and month is read in, by the client's language: "mdy" where the
--- language writes the month first, "dmy" elsewhere.
function NoteDates.DefaultOrder(locale)
    return MONTH_FIRST[locale or ""] and "mdy" or "dmy"
end

--- The format a date is written in by default, by the client's language.
function NoteDates.DefaultFormat(locale)
    return MONTH_FIRST[locale or ""] and "mm/dd/yy" or "dd/mm/yy"
end

--- The day { year, month, day } written in `fmt` (one of FORMATS), with LABEL before it when `label`.
function NoteDates.Format(day, fmt, label)
    local y, m, d = day.year, day.month, day.day
    local s
    if fmt == "mm/dd/yy" then s = string.format("%02d/%02d/%02d", m, d, y % 100)
    elseif fmt == "dd.mm.yyyy" then s = string.format("%02d.%02d.%04d", d, m, y)
    elseif fmt == "yyyy-mm-dd" then s = string.format("%04d-%02d-%02d", y, m, d)
    else s = string.format("%02d/%02d/%02d", d, m, y % 100) end
    return label and (NoteDates.LABEL .. s) or s
end

-- Day and month of a date written "a<sep>b<sep>year": the dot is day first everywhere; otherwise a number
-- above 12 decides, and `order` the rest.
local function dayMonth(a, b, sep, order)
    if sep == "." or a > 12 then return a, b end
    if b > 12 then return b, a end
    if order == "mdy" then return b, a end
    return a, b
end

-- The date patterns, each with how its captures read. %f keeps a number whole: "12025-01-02" is no date.
-- "yy2" is three two-digit numbers with dashes read yy-mm-dd ("24-01-29": 29 Jan 2024), and only where dd-mm-yy (or
-- mm-dd-yy, by `order`) is no real day of the game's era: "xy2" comes first and wins a tie, so "15-01-25" stays
-- 15 Jan 2025, as most of the guilds write it.
local PATTERNS = {
    { "%f[%d](%d%d%d%d)([-/.])(%d%d?)[-/.](%d%d?)%f[%D]", "ymd" },
    { "%f[%d](%d%d?)([-/.])(%d%d?)[-/.](%d%d%d%d)%f[%D]", "xy4" },
    { "%f[%d](%d%d?)([-/.])(%d%d?)[-/.](%d%d)%f[%D]", "xy2" },
    { "%f[%d](%d%d)(%-)(%d%d)%-(%d%d)%f[%D]", "yy2" },
}

----------------------------------------------------------------------
-- Months by name: "15 Jan 2025", "15 de janeiro de 2025", "Jan 15, 2025", "15. Januar 2025", "15 января 2025",
-- "2025年1月15日", "2025년 1월 15일". English always, and the client's language (its short and full names, the ones
-- GuildOS:LocalDate writes). Only read; a date is still written in FORMATS.
----------------------------------------------------------------------
local EN_MONTHS = {
    { "jan", "january" }, { "feb", "february" }, { "mar", "march" }, { "apr", "april" }, { "may", "may" },
    { "jun", "june" }, { "jul", "july" }, { "aug", "august" }, { "sep", "september", "sept" }, { "oct", "october" },
    { "nov", "november" }, { "dec", "december" },
}
local MONTH_KEYS = {
    { "Jan", "January" }, { "Feb", "February" }, { "Mar", "March" }, { "Apr", "April" }, { "May", "May" },
    { "Jun", "June" }, { "Jul", "July" }, { "Aug", "August" }, { "Sep", "September" }, { "Oct", "October" },
    { "Nov", "November" }, { "Dec", "December" },
}
-- Words that may stand between the day, the month and the year: "15 de jan", "the 15th of", "1er janvier".
local FILLER = { de = true, del = true, of = true, the = true, st = true, nd = true, rd = true, th = true, er = true,
                 ["\194\186"] = true, ["\194\170"] = true }   -- º ª
-- The CJK year, month and day marks (年 월 ...): a number then its mark.
local YEAR_MARK = { ["\229\185\180"] = true, ["\235\133\132"] = true }    -- 年 년
local MONTH_MARK = { ["\230\156\136"] = true, ["\236\155\148"] = true }   -- 月 월
local DAY_MARK = { ["\230\151\165"] = true, ["\236\157\188"] = true }     -- 日 일
local SHORT_MIN = 3   -- bytes a short name needs before a longer word starting with it reads as that month

--- `s` in lower case: ASCII, the accented Latin capitals (À-Þ) and Cyrillic (А-Я, Ё). A trailing dot goes.
function NoteDates.Fold(s)
    s = tostring(s or ""):lower()
    s = s:gsub("\195([\128-\158])", function(c) return "\195" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\144-\175])", function(c)
        local b = c:byte()
        if b < 160 then return "\208" .. string.char(b + 32) end
        return "\209" .. string.char(b - 32)
    end)
    s = s:gsub("\208\129", "\209\145")
    return (s:gsub("%.$", ""))
end
local fold = NoteDates.Fold

local monthNames, shortNames   -- built at the first read, once the Locales have filled L

--- The month names read: { [folded name] = month }, and the short ones ({ name, month }, longest first) a longer word
--- may start with ("января" reads as "янв", "sept." as "sep"). English, then `L`'s (the client's language).
function NoteDates.MonthNames(L2)
    if not L2 and monthNames then return monthNames, shortNames end
    local names, shorts = {}, {}
    local function add(word, m, short)
        word = fold(word)
        if word == "" or word:find("%d") then return end   -- "1月", "1월": the CJK marks read those
        names[word] = names[word] or m
        if short and #word >= SHORT_MIN then shorts[#shorts + 1] = { word, m } end
    end
    for m, list in ipairs(EN_MONTHS) do
        for i, w in ipairs(list) do add(w, m, i == 1 or i == 3) end
    end
    local tr = L2 or L
    for m, keys in ipairs(MONTH_KEYS) do
        local sh, full = rawget(tr, keys[1]) or tr[keys[1]], rawget(tr, keys[2]) or tr[keys[2]]
        if type(sh) == "string" then add(sh, m, true) end
        if type(full) == "string" then add(full, m, false) end
    end
    table.sort(shorts, function(a, b) return #a[1] > #b[1] end)
    if not L2 then monthNames, shortNames = names, shorts end
    return names, shorts
end

--- Forget the names built (a test that changes the language's).
function NoteDates.ForgetMonthNames()
    monthNames, shortNames = nil, nil
end

-- The month a word names, or nil.
local function monthOf(word, names, shorts)
    local w = fold(word)
    if names[w] then return names[w] end
    if #w < SHORT_MIN then return nil end
    for _, sh in ipairs(shorts) do
        if w:sub(1, #sh[1]) == sh[1] then return sh[2] end
    end
    return nil
end

-- The words and numbers of `text`, each { kind = "n" | "w", v, s, e, gap }: gap is true when what stands before it
-- is more than spaces and ". , - /" (the sequence breaks there).
local function tokens(text)
    local out, i, n = {}, 1, #text
    local lastEnd = 0
    while i <= n do
        local s, e = text:find("^%d+", i)
        local kind = "n"
        if not s then
            s, e = text:find("^[%a\128-\255]+", i)
            kind = "w"
        end
        if s then
            local between = text:sub(lastEnd + 1, s - 1)
            out[#out + 1] = { kind = kind, v = text:sub(s, e), s = s, e = e,
                gap = lastEnd > 0 and between:find("[^%s%.,%-/]") ~= nil }
            lastEnd, i = e, e + 1
        else
            i = i + 1
        end
    end
    return out
end

-- The tokens from `i` on with the fillers between them skipped: the next token's index, or nil (a gap breaks it).
local function nextTok(tk, i)
    while tk[i] and tk[i].kind == "w" and FILLER[fold(tk[i].v)] do
        i = i + 1
        if tk[i] and tk[i].gap then return nil end
    end
    if tk[i] and tk[i].gap then return nil end
    return tk[i] and i or nil
end

local function yearOf(v, two)
    if #v == 4 then return tonumber(v) end
    if two and #v == 2 then return 2000 + tonumber(v) end
    return nil
end

-- The first date written with a month name or the CJK marks: { year, month, day, s, e }, or nil.
local function namedDate(text, maxYear)
    if not text:find("[%a\128-\255]") then return nil end
    local tk = tokens(text)
    if #tk < 3 then return nil end
    local names, shorts = NoteDates.MonthNames()
    for i = 1, #tk do
        local a = tk[i]
        local y, m, d, last
        if a.kind == "n" and #a.v <= 2 then
            -- "15 Jan 2025", "15 de jan de 25", "15th of January 2025", "15. Januar 2025"
            local j = nextTok(tk, i + 1)
            local mm = j and tk[j].kind == "w" and monthOf(tk[j].v, names, shorts)
            local k = mm and nextTok(tk, j + 1)
            if k and tk[k].kind == "n" then
                y, m, d, last = yearOf(tk[k].v, true), mm, tonumber(a.v), k
            end
        elseif a.kind == "w" then
            -- "Jan 15, 2025", "January 15th 2025": a four-digit year only.
            local mm = monthOf(a.v, names, shorts)
            local j = mm and nextTok(tk, i + 1)
            if j and tk[j].kind == "n" and #tk[j].v <= 2 then
                local k = nextTok(tk, j + 1)
                if k and tk[k].kind == "n" then y, m, d, last = yearOf(tk[k].v, false), mm, tonumber(tk[j].v), k end
            end
        elseif a.kind == "n" and #a.v == 4 then
            -- "2025年1月15日", "2025년 1월 15일"
            local b, c, dd, e = tk[i + 1], tk[i + 2], tk[i + 3], tk[i + 4]
            if b and c and dd and e and YEAR_MARK[b.v] and c.kind == "n" and MONTH_MARK[dd.v] and e.kind == "n"
                and not (b.gap or c.gap or dd.gap or e.gap) then
                y, m, d, last = tonumber(a.v), tonumber(c.v), tonumber(e.v), i + 4
                if tk[i + 5] and DAY_MARK[tk[i + 5].v] and not tk[i + 5].gap then last = i + 5 end
            end
        end
        if y and NoteDates.ValidDay(y, m, d, maxYear) then
            return { year = y, month = m, day = d, s = a.s, e = tk[last].e }
        end
    end
    return nil
end

--- The first date written in `text`: { year, month, day }, and where it starts and ends, a "word:" just before it
--- included ("Joined: 03/02/25"), and where the date itself starts. Read: yyyy-mm-dd (or / and .), dd.mm.yyyy and dd.mm.yy,
--- yy-mm-dd (three two-digit numbers with dashes, only when dd-mm-yy is no real day of the era), with / or - the day and month in `order`
--- ("dmy" or "mdy") unless a number above 12 says which is which (so mm/dd/yyyy reads on a day-first client only when
--- the day is above 12), and a month by name (English and the client's language: "15 Jan 2025", "15 de jan 2025",
--- "Jan 15, 2025") or with the CJK marks ("2025年1月15日"). A two-digit year is 20yy.
--- `maxYear`: a later year is no date (a note's "12/31/99" is not this century's guild). Nil when there is none.
function NoteDates.Parse(text, order, maxYear)
    if type(text) ~= "string" or text == "" then return nil end
    local best
    for _, p in ipairs(PATTERNS) do
        local init = 1
        while true do
            local s, e, c1, sep, c2, c3 = text:find(p[1], init)
            if not s then break end
            local y, m, d
            if p[2] == "ymd" then
                y, m, d = tonumber(c1), tonumber(c2), tonumber(c3)
            elseif p[2] == "yy2" then
                y, m, d = 2000 + tonumber(c1), tonumber(c2), tonumber(c3)
                -- Only where dd-mm-yy / mm-dd-yy is no real day: the same text read that way is not this one.
                local dd, mm = dayMonth(tonumber(c1), tonumber(c2), sep, order)
                if NoteDates.ValidDay(2000 + tonumber(c3), mm, dd, maxYear) then y = nil end
            else
                y = tonumber(c3)
                if p[2] == "xy2" then y = 2000 + y end
                d, m = dayMonth(tonumber(c1), tonumber(c2), sep, order)
            end
            if y and NoteDates.ValidDay(y, m, d, maxYear) then
                if not best or s < best.s then best = { year = y, month = m, day = d, s = s, e = e } end
                break
            end
            init = s + 1
        end
    end
    local named = namedDate(text, maxYear)
    if named and (not best or named.s < best.s) then best = named end
    if not best then return nil end
    local from = best.s
    local ls = text:sub(1, best.s - 1):find("[%a][%a]*:%s*$")
    if ls then from = ls end
    return { year = best.year, month = best.month, day = best.day }, from, best.e, best.s
end

--- What the note should read with `piece` in it, and how: "same" (it says it already: nothing to write), "write"
--- (it was empty), "append" (after a space, the old text kept), "replace" (another date there, swapped for this one)
--- or "full" (no room: the old text cut to make some). The last two only from a confirmation. `order`, `maxYear`:
--- as Parse.
function NoteDates.Compose(current, piece, order, maxYear, max)
    max = max or NoteDates.NOTE_MAX
    current = strtrim(current or "")
    if current == "" then return piece, "write" end
    if current:find(piece, 1, true) then return current, "same" end
    local _, s, e, ds = NoteDates.Parse(current, order, maxYear)
    if s then
        -- A piece without a label keeps the note's own ("Entrou: 01/01/24" stays "Entrou: ...").
        if not piece:find("^[%a][%a]*:") then s = ds end
        local swapped = strtrim(current:sub(1, s - 1) .. piece .. current:sub(e + 1)):gsub("%s+", " ")
        if #swapped <= max then return swapped, "replace" end
        return piece, "replace"
    end
    if #current + 1 + #piece <= max then return current .. " " .. piece, "append" end
    local room = max - #piece - 1
    if room <= 0 then return piece, "full" end
    local kept = GuildOS:SanitizeUserText(current, room)
    return (kept ~= "" and (kept .. " ") or "") .. piece, "full"
end

--- Whether a Compose answer writes without asking.
function NoteDates.Silent(how)
    return how == "write" or how == "append"
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
--- Which note the dates go into: "officer" (the default: only officers read it) or "public".
function NoteDates:Target()
    return GuildOS:GetSetting("noteDateTarget") == "public" and "public" or "officer"
end

function NoteDates:SetTarget(which)
    if not GuildOS:IsOfficer() or (which ~= "public" and which ~= "officer") then return false end
    GuildOS:SetSetting("noteDateTarget", which)
    return true
end

--- The format dates are written in.
function NoteDates:FormatId()
    local f = GuildOS:GetSetting("noteDateFormat")
    for _, x in ipairs(self.FORMATS) do if x == f then return f end end
    return self.DefaultFormat(GetLocale and GetLocale())
end

function NoteDates:SetFormat(fmt)
    if not GuildOS:IsOfficer() then return false end
    for _, x in ipairs(self.FORMATS) do
        if x == fmt then GuildOS:SetSetting("noteDateFormat", fmt); return true end
    end
    return false
end

--- Whether LABEL goes before the date.
function NoteDates:UseLabel()
    return GuildOS:GetSetting("noteDateLabel") == true
end

function NoteDates:SetLabel(on)
    if not GuildOS:IsOfficer() then return false end
    GuildOS:SetSetting("noteDateLabel", on and true or false)
    return true
end

--- Whether dates GuildOS only saw (the first time it looked at the guild, say) are written too. Off by default: on
--- a guild GuildOS met today, every such date is today.
function NoteDates:WithSeen()
    return GuildOS:GetSetting("noteDateSeen") == true
end

function NoteDates:SetWithSeen(on)
    if not GuildOS:IsOfficer() then return false end
    GuildOS:SetSetting("noteDateSeen", on and true or false)
    return true
end

--- How a slashed date is read on import: "auto" (by the client's language), "dmy" or "mdy".
function NoteDates:OrderSetting()
    local o = GuildOS:GetSetting("noteDateOrder")
    return (o == "dmy" or o == "mdy") and o or "auto"
end

function NoteDates:Order()
    local o = self:OrderSetting()
    if o == "auto" then return self.DefaultOrder(GetLocale and GetLocale()) end
    return o
end

function NoteDates:SetOrder(o)
    if not GuildOS:IsOfficer() or (o ~= "auto" and o ~= "dmy" and o ~= "mdy") then return false end
    GuildOS:SetSetting("noteDateOrder", o)
    return true
end

local function thisYear() return tonumber(date("%Y", GetServerTime())) end

----------------------------------------------------------------------
-- Planning what to write
----------------------------------------------------------------------
local function short(name) return name and (name:match("^([^-]+)") or name) or "?" end

-- Roster line `i`: full name, key, public note, officer note (nil when this rank cannot read them).
local function rosterLine(i, onotes)
    local full, _, _, _, _, _, note, onote = GetGuildRosterInfo(i)
    if not full then return nil end
    return full, GuildOS:KeyOfRosterName(full), note or "", onotes and (onote or "") or nil
end

--- The item for one member: { fullName, name, key, which, current, piece, text, how } or nil and why: "date" (no
--- join date known), "seen" (only a date GuildOS saw, and those are off) or "hidden" (an officer note this rank
--- cannot read).
function NoteDates:ItemFor(fullName, key, note, onote, which)
    which = which or self:Target()
    local MH = GuildOS.MemberHistory
    local t, est = nil, nil
    if MH then t, est = MH:JoinedAt(key) end
    if not t then return nil, "date" end
    if est and not self:WithSeen() and not (MH and MH:JoinedFromNote(key)) then return nil, "seen" end
    local current = (which == "officer") and onote or note
    if current == nil then return nil, "hidden" end
    local dt = date("*t", t)
    local piece = self.Format(dt, self:FormatId(), self:UseLabel())
    local text, how = self.Compose(current, piece, self:Order(), thisYear())
    return { fullName = fullName, name = short(fullName), key = key, which = which, current = current,
             piece = piece, text = text, how = how }
end

--- What a run over the whole guild would write: the items, every member with a date whose note does not say it
--- already, silent writes first then the ones to confirm, by name; and how many were left out by why.
function NoteDates:Plan(which)
    which = which or self:Target()
    local onotes = GuildOS.Compat.CanViewOfficerNote()
    local out, left = {}, { date = 0, seen = 0, hidden = 0, same = 0 }
    for i = 1, GetNumGuildMembers() or 0 do
        local full, key, note, onote = rosterLine(i, onotes)
        if full then
            local item, why = self:ItemFor(full, key, note, onote, which)
            if not item then left[why] = (left[why] or 0) + 1
            elseif item.how == "same" then left.same = left.same + 1
            else out[#out + 1] = item end
        end
    end
    table.sort(out, function(a, b)
        local sa, sb = self.Silent(a.how), self.Silent(b.how)
        if sa ~= sb then return sa end
        return a.name:lower() < b.name:lower()
    end)
    return out, left
end

-- The member's roster line by name, read now.
local function lineOf(name)
    local idx = GuildOS.Compat.FindGuildRosterIndex(name)
    if not idx then return nil end
    return rosterLine(idx, GuildOS.Compat.CanViewOfficerNote())
end

----------------------------------------------------------------------
-- Writing
----------------------------------------------------------------------
--- How this client writes the note: "write" (the addon writes it), "click" (one per click: the game blocked a write
--- from a timer) or "copy" (the officer pastes it into the game's roster). Nil when this rank may not edit it at all.
function NoteDates:Mode(which)
    which = which or self:Target()
    if not GuildOS.Compat.RankEditsNote(which) and not GuildOS.Compat.CanWriteNote(which) then return nil end
    local s = state()
    if s.forbidden or not GuildOS.Compat.CanWriteNote(which) then return "copy" end
    if s.needsClick then return "click" end
    return "write"
end

-- Writes `item`'s text now, re-read first: what the note reads may have changed since the plan. Returns "done",
-- "same" (it already said it), "changed" (the note changed into one that needs a confirmation), "gone" (not on the
-- roster), "copy" (this client cannot write it: the officer is shown the text), "blocked" (the game refused it as it
-- ran: click or copy from now on) or "refused".
function NoteDates:_WriteNow(item, confirmed)
    local full, key, note, onote = lineOf(item.fullName)
    if not full then return "gone" end
    local fresh = self:ItemFor(full, key, note, onote, item.which)
    if not fresh then return "gone" end
    if fresh.how == "same" then return "same" end
    -- A confirmation was for the text it showed: a note that changed since is asked about again.
    if not self.Silent(fresh.how) and (not confirmed or fresh.text ~= item.text) then return "changed" end
    local mode = self:Mode(item.which)
    if mode == "copy" then
        self:ShowCopy(fresh)
        return "copy"
    end
    local s = state()
    s.writingAt, s.inWrite, s.blockedNow = GetTime(), true, nil
    local C = GuildOS.Compat
    local ok, why
    if item.which == "officer" then ok, why = C.SetGuildOfficerNote(full, fresh.text)
    else ok, why = C.SetGuildPublicNote(full, fresh.text) end
    s.inWrite = nil
    -- The game refused it while it ran (OnBlocked): not written, and the mode has changed.
    if s.blockedNow then s.blockedNow = nil return "blocked" end
    if not ok then
        GuildOS:Print(string.format(L["Could not write %s's note (%s)."], fresh.name, tostring(why)))
        return "refused"
    end
    -- The Roster Log gets the change from the member history's next look at the roster (#425).
    item.text = fresh.text
    return "done"
end

--- `/gos joindate <name>` and the panel's one-member write: the member's date into the chosen note (`which`, the
--- data audit's "Fix note": the note that differs; else the setting's). A note that would lose text asks first (the
--- confirmation calls back with `confirmed`). True when it reads as asked, or the copy box is open.
function NoteDates:WriteOne(name, confirmed, which)
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Only officers can do that."]) return false end
    which = (which == "public" or which == "officer") and which or self:Target()
    if not self:Mode(which) then GuildOS:Print(L["Your guild rank may not edit that note."]) return false end
    local full, key, note, onote = lineOf(name or "")
    if not full then GuildOS:Print(string.format(L["%s is not in the guild roster."], name or "?")) return false end
    local item, why = self:ItemFor(full, key, note, onote, which)
    if not item then
        GuildOS:Print(why == "hidden" and L["Your guild rank cannot read officer notes."]
            or why == "seen" and string.format(L["%s: GuildOS only knows when it first saw them. Turn on dates GuildOS only saw to write that one."], short(full))
            or string.format(L["%s: no join date known."], short(full)))
        return false
    end
    if item.how == "same" then GuildOS:Print(string.format(L["%s's note already says %s."], item.name, item.piece)) return true end
    if not self.Silent(item.how) and not confirmed then
        self:AskReplace(item)
        return false
    end
    return self:_SayAndOffer(item, self:_WriteNow(item, confirmed))
end

--- The confirmation's Start: exactly the text it showed, or nothing (the note changed: asked again).
function NoteDates:ConfirmWrite(item)
    if type(item) ~= "table" or not GuildOS:IsOfficer() then return false end
    return self:_SayAndOffer(item, self:_WriteNow(item, true))
end

-- _Say, then, when a main's date went into the note (or into the copy box), the offer for their alts.
function NoteDates:_SayAndOffer(item, res)
    local ok = self:_Say(item, res)
    if res == "done" or res == "copy" then self:OfferAlts({ item.key }) end
    return ok
end

-- A one-member write's answer, to chat.
function NoteDates:_Say(item, res)
    if res == "done" then
        GuildOS:Print(string.format(L["Set %s's note: |cffFFFFFF%s|r"], item.name, item.text))
    elseif res == "changed" then
        GuildOS:Print(string.format(L["%s's note changed meanwhile: try again."], item.name))
    elseif res == "blocked" and self:Mode(item.which) == "copy" then
        self:ShowCopy(item)
    end
    return res == "done" or res == "copy" or res == "same"
end

--- The confirmation before a note loses text: old and new side by side.
function NoteDates:AskReplace(item)
    if GuildOS.ShowDialog then
        GuildOS:ShowDialog("GUILDOS_NOTE_DATE_REPLACE",
            string.format(L["%s's note reads:\n|cffFFFFFF%s|r\n\nWrite instead:\n|cffFFFFFF%s|r"], item.name, item.current, item.text),
            nil, item)
    end
end

--- The note for the officer to copy and paste into the game's roster: where the client does not let an addon write.
function NoteDates:ShowCopy(item)
    if GuildOS.ShowDialog then
        GuildOS:ShowDialog("GUILDOS_NOTE_DATE_COPY", string.format(item.which == "officer"
            and L["Copy %s's officer note (Ctrl+C) and paste it into the game's guild roster:"]
            or L["Copy %s's public note (Ctrl+C) and paste it into the game's guild roster:"], item.name), nil, item)
    else
        GuildOS:Print(string.format(L["%s's note: %s"], item.name, item.text))
    end
end

----------------------------------------------------------------------
-- A run over many members
----------------------------------------------------------------------
--- The run going on, or nil: { which, items = { item + status }, pos, gap }. status: "pending", "done", "same",
--- "skipped" (changed into one to confirm, or gone) or "copied".
function NoteDates:Run()
    return state().run
end

--- Start a run over `items` (as Plan made them). Only the silent ones go unless `confirmed` (the screen asked for
--- the rest by showing each old and new note). Returns true, or false and why: "officer", "rank", "empty".
function NoteDates:Start(items, confirmed)
    if not GuildOS:IsOfficer() then return false, "officer" end
    -- The note the plan was made for (the setting may have moved since).
    local which = (type(items) == "table" and items[1] and items[1].which) or self:Target()
    if not self:Mode(which) then return false, "rank" end
    local list = {}
    for _, it in ipairs(items or {}) do
        if it.how ~= "same" and (confirmed or self.Silent(it.how)) then
            local copy = {}
            for k, v in pairs(it) do copy[k] = v end
            copy.status, copy.confirmed = "pending", (not self.Silent(it.how)) and true or nil
            list[#list + 1] = copy
        end
    end
    if #list == 0 then return false, "empty" end
    local s = state()
    s.run = { which = which, items = list, pos = 1, gap = self.GAP }
    GuildOS:Print(string.format(L["Join dates: %d note(s) to write."], #list))
    if self:Mode(which) == "write" then self:_Arm() else self:_SayNext() end
    self:Refresh()
    return true
end

local WHY = {
    officer = L["Only officers can do that."],
    rank = L["Your guild rank may not edit that note."],
    empty = L["Every note with a known date already says it."],
}

--- Start, and say why not when it does not.
function NoteDates:StartAndSay(items, confirmed)
    local ok, why = self:Start(items, confirmed)
    if not ok then GuildOS:Print(WHY[why] or WHY.empty) end
    return ok
end

--- Drop the run.
function NoteDates:Stop()
    local s = state()
    s.run, s.armed = nil, nil
    self:Refresh()
end

--- The item the next write or click is for, or nil when the run is through.
function NoteDates:Current()
    local r = self:Run()
    if not r then return nil end
    while r.items[r.pos] and r.items[r.pos].status ~= "pending" do r.pos = r.pos + 1 end
    return r.items[r.pos]
end

--- Counts by status: { pending, done, same, skipped, copied, total }.
function NoteDates:Counts()
    local c = { pending = 0, done = 0, same = 0, skipped = 0, copied = 0, total = 0 }
    local r = self:Run()
    for _, it in ipairs(r and r.items or {}) do
        c[it.status] = (c[it.status] or 0) + 1
        c.total = c.total + 1
    end
    return c
end

local function finish()
    local c = NoteDates:Counts()
    GuildOS:Print(string.format(L["Join dates done: %d written, %d copied, %d already there, %d skipped."],
        c.done, c.copied, c.same, c.skipped))
    -- The mains whose date went in: one offer for all their alts, once a run.
    local r = NoteDates:Run()
    if r and not r.altsOffered then
        r.altsOffered = true
        local keys = {}
        for _, it in ipairs(r.items) do
            if it.status == "done" or it.status == "copied" then keys[#keys + 1] = it.key end
        end
        NoteDates:OfferAlts(keys)
    end
end

-- One step of the run on `item`: the write's answer becomes its status.
function NoteDates:_Step(item)
    local res = self:_WriteNow(item, item.confirmed)
    if res == "done" then item.status = "done"
    elseif res == "same" then item.status = "same"
    elseif res == "copy" then item.status = "copied"
    elseif res == "blocked" then item.status = "pending"   -- next, by click or copy
    else item.status, item.why = "skipped", res end
    return res
end

-- The next timed write, GAP (or the doubled gap) from now.
function NoteDates:_Arm()
    local s = state()
    if s.armed or not s.run then return end
    s.armed = true
    GuildOS.Compat.After(s.run.gap, function()
        s.armed = nil
        GuildOS:SafeCall(NoteDates._Tick, NoteDates)
    end)
end

--- The timer's write: one member, then the next timer. Stops when the mode is no longer "write".
function NoteDates:_Tick()
    local r = self:Run()
    if not r then return end
    if self:Mode(r.which) ~= "write" then self:_SayNext() self:Refresh() return end
    local item = self:Current()
    if not item then finish() self:Refresh() return end
    -- Back toward GAP after a throttle: halved after CALM_WRITES writes in a row without one.
    if self:_Step(item) == "done" then
        r.calm = (r.calm or 0) + 1
        if r.calm >= self.CALM_WRITES and r.gap > self.GAP then r.gap, r.calm = math.max(self.GAP, r.gap / 2), 0 end
    end
    self:Refresh()
    if self:Current() then self:_Arm() else finish() end
end

-- In click or copy mode: who the next click is for.
function NoteDates:_SayNext()
    local item = self:Current()
    if item then
        GuildOS:Print(string.format(L["Join dates: click Next for %s."], item.name))
    else
        finish()
    end
end

--- The panel's Next: in click mode it writes the current member's note (a click is a hardware event); in copy mode
--- it shows the current member's note to copy. True when something was done.
function NoteDates:Next()
    local r = self:Run()
    if not r then return false end
    local item = self:Current()
    if not item then finish() self:Refresh() return false end
    local mode = self:Mode(r.which)
    if mode == "write" then
        if not state().armed then self:_Arm() end
        return false
    end
    self:_Step(item)
    self:Refresh()
    if not self:Current() then finish() end
    return true
end

--- What the panel's Next says.
function NoteDates:NextLabel()
    local r = self:Run()
    local item = r and self:Current()
    if not item then return L["Next"] end
    if self:Mode(r.which) == "copy" then return string.format(L["Copy %s"], item.name) end
    return string.format(L["Write %s"], item.name)
end

----------------------------------------------------------------------
-- What the game answers
----------------------------------------------------------------------
--- "You are doing that too fast" during a run: the gap doubles, and the member written last is tried again (their
--- note re-read first, so one that went in is not written twice).
function NoteDates:OnError(...)
    local r = self:Run()
    if not r then return end
    local WQ = GuildOS.WhisperQueue
    if not (WQ and WQ.IsThrottle(...)) then return end
    r.gap, r.calm = math.min(self.MAX_GAP, r.gap * 2), 0
    for i = r.pos, 1, -1 do
        local it = r.items[i]
        if it and it.status == "done" then it.status = "pending" r.pos = i break end
    end
    self:Refresh()
end

-- Whether a blocked function is a note write.
local function noteFunction(fn)
    return type(fn) == "string" and (fn:find("SetNote") or fn:find("SetPublicNote") or fn:find("SetOfficerNote")) ~= nil
end

--- A blocked or forbidden note write of ours, just after one: blocked asks for a click from now on, forbidden for
--- the copy box. The member it was for is tried again that way.
function NoteDates:OnBlocked(event, addon, fn)
    local s = state()
    if addon ~= "GuildOS" or not noteFunction(fn) or not s.writingAt or GetTime() - s.writingAt > BLOCK_WINDOW then return end
    if event == "ADDON_ACTION_FORBIDDEN" or s.needsClick then s.forbidden = true else s.needsClick = true end
    local r = self:Run()
    if s.inWrite then
        s.blockedNow = true   -- raised while the write ran: _WriteNow says so, the member stays next
    elseif r then
        for i = r.pos, 1, -1 do
            local it = r.items[i]
            if it and it.status == "done" then it.status = "pending" r.pos = i break end
        end
    end
    GuildOS:Print(s.forbidden and L["The game does not let an addon write notes here: each click of Next shows the note to copy."]
        or L["The game wants a click for each note: click Next for each one."])
    self:Refresh()
end

----------------------------------------------------------------------
-- Reading dates already in the notes
----------------------------------------------------------------------
--- The moment an imported day is filed at: its last minute on this client's clock, so an exact join seen that day
--- (the game's line, from any officer) is earlier and replaces it.
function NoteDates.ImportTime(day)
    return time({ year = day.year, month = day.month, day = day.day, hour = DAY_END_HOUR, min = DAY_END_MIN, sec = 0 })
end

-- A day's number, to compare dates without the hour.
local function dayNum(t)
    local d = date("*t", t)
    return GuildOS.MemberHistory.DayNumber(d.year, d.month, d.day)
end

--- What an import would do: one item per member with a date in a note ({ fullName, name, key, source = "public" |
--- "officer", note, day, t, known, knownEst, status, pick }). status: "new" (the history has no date), "earlier" (it
--- has one GuildOS only saw, later than the note's: the note's is better), "same" (the same day), "later" (the note
--- says later than GuildOS saw them: not taken) or "kept" (the history has the exact day). `pick` is true for new
--- and earlier, the ones Apply takes unless the officer unticks them.
function NoteDates:ImportPlan(order)
    order = order or self:Order()
    local MH = GuildOS.MemberHistory
    local out = {}
    local onotes = GuildOS.Compat.CanViewOfficerNote()
    local maxYear = thisYear()
    for i = 1, GetNumGuildMembers() or 0 do
        local full, key, note, onote = rosterLine(i, onotes)
        if full then
            local src, text, day = "public", note, self.Parse(note, order, maxYear)
            if not day and onote then src, text, day = "officer", onote, self.Parse(onote, order, maxYear) end
            if day then
                local t = self.ImportTime(day)
                local known, est = nil, nil
                if MH then known, est = MH:JoinedAt(key) end
                local status
                if not known then status = "new"
                elseif dayNum(known) == dayNum(t) then status = "same"
                elseif not est then status = "kept"
                elseif t < known then status = "earlier"
                else status = "later" end
                if t > GetServerTime() then status = "later" end
                out[#out + 1] = { fullName = full, name = short(full), key = key, source = src, note = text, day = day,
                    t = t, known = known, knownEst = est, status = status, pick = (status == "new" or status == "earlier") }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.pick ~= b.pick then return a.pick end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

--- Takes the picked items of an ImportPlan into the history. How many went in.
function NoteDates:ApplyImport(items)
    local MH = GuildOS.MemberHistory
    if not (MH and GuildOS:IsOfficer()) then return 0 end
    local n, keys = 0, {}
    for _, it in ipairs(items or {}) do
        if it.pick and (it.status == "new" or it.status == "earlier") and MH:ImportJoin(it.key, it.t) then
            n = n + 1
            keys[#keys + 1] = it.key
        end
    end
    GuildOS:Print(string.format(L["Join dates: %d taken from the notes into the history."], n))
    self:Refresh()
    if n > 0 then self:OfferAlts(keys) end
    return n
end

----------------------------------------------------------------------
-- The whole alt group: a main's date for their alts
----------------------------------------------------------------------
--- Whether an alt's open passage (`last`, MemberHistory's stint) would take the day filed at `t`: it has no real date
--- (no start, or one GuildOS only saw, not read from a note) and that one is later. Pure.
function NoteDates.AltTakes(last, t)
    if type(last) ~= "table" or last.leftAt ~= nil or type(t) ~= "number" then return false end
    if last.joinAt == nil then return true end
    return last.joinEst == true and last.joinSrc ~= "note" and t < last.joinAt
end

--- What the offer for `mainKeys` holds: one entry per main with a real join date (the game's, or a day read from a
--- note) and alts on the roster that would take it: { key, name, day, t, alts = { { key, fullName, name } } }, by
--- name. One pass over the roster and one over the links, whatever the guild's size.
function NoteDates:AltOffers(mainKeys)
    local MH = GuildOS.MemberHistory
    local links = GuildOS.db and GuildOS.db.altLinks
    if not (MH and type(links) == "table" and type(mainKeys) == "table") then return {} end
    local want, any = {}, false
    for _, key in ipairs(mainKeys) do
        local t, est = MH:JoinedAt(key)
        if t and not want[key] and (not est or MH:JoinedFromNote(key)) then
            local day = date("*t", t)
            day = { year = day.year, month = day.month, day = day.day }
            want[key] = { key = key, name = short(key), day = day, t = self.ImportTime(day), alts = {} }
            any = true
        end
    end
    if not any then return {} end
    local fullOf = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local full = GetGuildRosterInfo(i)
        if full then fullOf[GuildOS:KeyOfRosterName(full)] = full end
    end
    for alt, main in pairs(links) do
        local o = want[main]
        if o and alt ~= main and fullOf[alt] then
            local st = MH:Stints(alt)
            if self.AltTakes(st[#st], o.t) then
                o.alts[#o.alts + 1] = { key = alt, fullName = fullOf[alt], name = short(fullOf[alt]) }
            end
        end
    end
    local out = {}
    for _, o in pairs(want) do
        if #o.alts > 0 then
            table.sort(o.alts, function(a, b) return a.name:lower() < b.name:lower() end)
            out[#out + 1] = o
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

--- After a main's date was written or imported: one question for every alt of theirs with no real date ("apply the
--- same date to them?"). Officers only. Whether it was asked.
function NoteDates:OfferAlts(mainKeys)
    if not GuildOS:IsOfficer() or not GuildOS.ShowDialog then return false end
    local offers = self:AltOffers(mainKeys)
    if #offers == 0 then return false end
    local names, n = {}, 0
    for _, o in ipairs(offers) do
        for _, a in ipairs(o.alts) do
            n = n + 1
            if #names < 8 then names[#names + 1] = a.name end
        end
    end
    local list = table.concat(names, ", ") .. (n > #names and (" +" .. (n - #names)) or "")
    local text
    if #offers == 1 then
        text = string.format(L["%s's join date is %s. Apply it to their %d alt(s) with no real date (%s)?"],
            offers[1].name, self.Format(offers[1].day, self:FormatId()), n, list)
    else
        text = string.format(L["%d mains got a join date. Apply each one's to their %d alt(s) with no real date (%s)?"],
            #offers, n, list)
    end
    text = text .. "\n\n" .. L["Their notes get it where there is room; a note that would lose text is left for you to confirm (Whole guild)."]
    GuildOS:ShowDialog("GUILDOS_NOTE_DATE_ALTS", text, nil, offers)
    return true
end

--- The offer's Apply: each alt's history takes its main's day (as one read from a note: the game's exact line still
--- replaces it), then their notes are written through a run of the silent ones only (an empty note, or one with
--- room); a note that would lose text is left for the Whole guild list, which asks. How many alts took the date.
function NoteDates:ApplyToAlts(offers)
    local MH = GuildOS.MemberHistory
    if not (MH and GuildOS:IsOfficer() and type(offers) == "table") then return 0 end
    local which = self:Target()
    local onotes = GuildOS.Compat.CanViewOfficerNote()
    local n, items, asks = 0, {}, 0
    for _, o in ipairs(offers) do
        for _, a in ipairs(type(o) == "table" and type(o.alts) == "table" and o.alts or {}) do
            if type(a.key) == "string" and type(o.t) == "number" and MH:ImportJoin(a.key, o.t) then
                n = n + 1
                local idx = GuildOS.Compat.FindGuildRosterIndex(a.fullName or a.key)
                local full, key, note, onote = nil, nil, nil, nil
                if idx then full, key, note, onote = rosterLine(idx, onotes) end
                local item = full and self:ItemFor(full, key, note, onote, which)
                if item and self.Silent(item.how) then items[#items + 1] = item
                elseif item and item.how ~= "same" then asks = asks + 1 end
            end
        end
    end
    local busy = self:Current() ~= nil
    local started = #items > 0 and not busy and self:Mode(which) ~= nil and self:Start(items, false)
    GuildOS:Print(string.format(L["Join dates: %d alt(s) took their main's date; %d note(s) to write, %d to confirm."],
        n, started and #items or 0, asks))
    if busy and #items > 0 then GuildOS:Print(L["A run is still going: write the alts' notes from Whole guild once it ends."]) end
    if asks > 0 then GuildOS:Print(L["Whole guild lists the notes that would lose text, each old and new, to confirm."]) end
    if GuildOS.RosterMaint then GuildOS.RosterMaint:Invalidate() end
    self:Refresh()
    return n
end

----------------------------------------------------------------------
-- Commands and the screen
----------------------------------------------------------------------
--- `/gos joindate [<name> | all | import]`: no argument opens the panel; a name writes that member's date; `all`
--- plans the whole guild in the panel; `import` opens the import's review there.
function NoteDates:Command(rest)
    rest = strtrim(rest or "")
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Only officers can do that."]) return end
    local word = rest:lower()
    if rest == "" or word == "all" or word == "import" then
        state().open = (word == "import") and "import" or ((word == "all") and "plan" or nil)
        if GuildOS.UI and GuildOS.UI.OpenWindow then GuildOS.UI:OpenWindow("management", "marks") end
        self:Refresh()
        return
    end
    self:WriteOne(rest)
end

--- The member the panel's box should hold when it opens next (the data audit's "Write date"), and that name once.
function NoteDates:Prefill(name)
    state().prefill = type(name) == "string" and name or nil
end

function NoteDates:TakePrefill()
    local s = state()
    local v = s.prefill
    s.prefill = nil
    return v
end

--- What the panel should open on ("plan" or "import"), once.
function NoteDates:TakeOpen()
    local s = state()
    local v = s.open
    s.open = nil
    return v
end

function NoteDates:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end
