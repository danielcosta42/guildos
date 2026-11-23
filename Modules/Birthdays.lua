----------------------------------------------------------------------
-- Guild OS - Birthdays (issue #428, epic #423 group E). ADR-0043, specs/birthdays/spec.md
--
-- Two dates a year for each person in the guild:
--   * the birthday the member gives themselves: a day and a month, never a year (privacy: nothing
--     tells an age). `/gos birthday 14/03` or Settings > Profile. One per person: set on any
--     character, it shows on every character of the alt group (db.altLinks). Officers correct it.
--   * the anniversary of joining: the CURRENT passage's start (MemberHistory, officers' clients),
--     else when GuildOS first saw them. A first look at the guild is not a join, so a date from it
--     makes no anniversary (otherwise everybody would share the install day).
--
-- Neither is a calendar event: the calendar draws both as VIRTUAL yearly dates, worked out when it is
-- drawn with Calendar._Occurrences "yearly" (#358, 29 February on the 28th when the year has none),
-- and nothing is ever written to db.events or synced as one.
--
-- The store: db.birthdays[key] = { d, m, at, by } or { off = true, at, by } (a tombstone: the member
-- unticked "Show my birthday", or an officer removed it). Synced over the member domain "birthday"
-- (GUILD channel only), newest `at` (server time) wins, a tie to the tombstone. A member writes only
-- for their own characters (their own key or their alt group); an officer for anybody. Each client
-- re-sends its own entry at login, officers re-send all of them on a sync request (Backfill: at most
-- one every BACKFILL_GAP, and one every BACKFILL_IDLE when nothing changed since the last), and an
-- officer who hears an older entry than the one it holds answers with its own, once a session.
--
-- On the day, by the realm's calendar (GetServerTime + Compat.RealmClock): a digest line at the first
-- login of the day, and, if an officer turned it on (off by default), one line in /g a day for each
-- person and kind, however many officers are online: a claim, a short wait, the lower name wins a tie.
-- Only an officer's claim or "said" counts. "Said" is remembered, answered to a late officer's claim by
-- every officer who knows it, and sent with an officer's backfill (the late officer's own login sync
-- request). The limit left: an officer who logs in when no officer who heard the "said" is online says
-- it again (a member's word is not taken: anybody could silence the line with it).
----------------------------------------------------------------------
local Birthdays = {}
GuildOS.Birthdays = Birthdays

local L = GuildOS.L
local Compat = GuildOS.Compat

Birthdays.DOMAIN = "birthday"
Birthdays.BATCH = 40          -- entries per envelope in a backfill, as AltSync's
Birthdays.BATCH_GAP = 2       -- seconds between two of its envelopes (#324)
Birthdays.CLAIM_WAIT = 5      -- seconds a claim to announce waits for another officer's
Birthdays.CLAIM_JITTER = 3    -- and up to this much more, so two officers rarely claim at once
Birthdays.BACKFILL_GAP = 600  -- seconds between two backfills of this client
Birthdays.BACKFILL_IDLE = 3600 -- and between two with nothing changed in between
Birthdays.GAME_HOUR = 12      -- the hour of the day a birthday goes in the game's calendar
Birthdays.GAME_MARGIN = 10    -- minutes before it: today's is too late after that
local PUBLISH_DELAY = 20      -- seconds after login: the guild channel is up by then
local ANNOUNCE_DELAY = 90     -- after login: the roster and the other officers' "said" are in
local ANNOUNCE_EVERY = 3600   -- an hourly look catches the day turning over
local SKEW = 600              -- a sender's clock a little ahead is a clock
local CACHE_S = 5             -- the roster's people are kept this long (the roster asks per row)
local JOIN_SLACK = 3600       -- the first look at the guild takes a moment
local MAX_ITEMS = 200         -- entries read from one envelope
local DIGEST_MAX = 5          -- lines of today's dates in the digest
local KEY_MAX = 64            -- bytes of a key read off the network

----------------------------------------------------------------------
-- Pure (tools/birthdays.lua)
----------------------------------------------------------------------
local function isInt(v) return type(v) == "number" and v == math.floor(v) end
local function isLeap(y) return y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0) end
local MONTH_DAYS = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

--- Whether a day and a month are a date some year has (29/02 is).
function Birthdays.Valid(d, m)
    return isInt(d) and isInt(m) and m >= 1 and m <= 12 and d >= 1 and d <= MONTH_DAYS[m]
end

--- "14/03" (also 14.03, 14-03, and a year after it, which is dropped) in the order the client's language
--- writes dates; a date only valid the other way round (14/03 where the month comes first) is read so.
--- Returns day, month, or nil.
function Birthdays.Parse(text, monthFirst)
    local a, b, rest = tostring(text or ""):match("^%s*(%d%d?)%s*[/%.%-]%s*(%d%d?)(.-)%s*$")
    if not a or not (rest == "" or rest:match("^[/%.%-]%d%d%d?%d?$")) then return nil end
    a, b = tonumber(a), tonumber(b)
    local d, m = a, b
    if monthFirst then d, m = b, a end
    if Birthdays.Valid(d, m) then return d, m end
    if Birthdays.Valid(m, d) then return m, d end
    return nil
end

--- Whether a birthday (d, m) falls on the date y-cm-cd: 29 February is the 28th in a year with none,
--- the rule Calendar._Occurrences "yearly" draws it by.
function Birthdays.OnDay(d, m, y, cm, cd)
    if m == 2 and d == 29 and not isLeap(y) then return cm == 2 and cd == 28 end
    return cm == m and cd == d
end

--- Whether entry `a` beats `b`: the newer `at`; a tie goes to the tombstone (the privacy side), then to
--- the later date, so every client settles it the same way.
function Birthdays.Newer(a, b)
    if not a then return false end
    if not b then return true end
    if a.at ~= b.at then return (a.at or 0) > (b.at or 0) end
    if (a.off == true) ~= (b.off == true) then return a.off == true end
    return (a.m or 0) * 100 + (a.d or 0) > (b.m or 0) * 100 + (b.d or 0)
end

--- The date a join anniversary counts from (the rule, spec §3): the CURRENT passage's start when the
--- history has one (a member who left and came back counts from the return; earlier passages count for
--- the time in the guild, not for the date); else when GuildOS first saw them. A date only "seen" at
--- the first look at the guild (`floor`) is no join. Returns the time and whether it is estimated, or nil.
function Birthdays.JoinAnchor(stints, firstSeen, floor)
    floor = (floor or 0) + JOIN_SLACK
    local last = type(stints) == "table" and stints[#stints] or nil
    if last and last.leftAt == nil and isInt(last.joinAt) then
        if last.joinEst and last.joinAt <= floor then return nil end
        return last.joinAt, last.joinEst == true
    end
    if isInt(firstSeen) and firstSeen > floor then return firstSeen, true end
    return nil
end

-- An entry off the network, checked; nil when it is not one.
local function clean(it, now)
    if type(it) ~= "table" or not isInt(it.at) or it.at <= 0 or it.at > now + SKEW then return nil end
    local by = type(it.by) == "string" and #it.by <= KEY_MAX and GuildOS:LocalMemberKey(it.by) or nil
    if it.off == true then return { off = true, at = it.at, by = by } end
    if not Birthdays.Valid(it.d, it.m) then return nil end
    return { d = it.d, m = it.m, at = it.at, by = by }
end

local function wire(key, e) return { k = key, d = e.d, m = e.m, off = e.off, at = e.at, by = e.by } end

----------------------------------------------------------------------
-- Keys, the store, the alt group
----------------------------------------------------------------------
local function myKey() return GuildOS:GetPlayerKey(Compat.PlayerName()) end

local function senderKey(sender)
    local short = sender:match("^([^-]+)") or sender
    return GuildOS:GetPlayerKey(short, sender:match("-(.+)$"))
end

local function onGuild() return GuildOS:IsOnGuildDB() end

local function store()
    GuildOS.db.birthdays = GuildOS.db.birthdays or {}
    return GuildOS.db.birthdays
end

-- A count bumped on every change to the store: a backfill with nothing new waits longer.
local revision = 0
local function bump() revision = revision + 1 end

local function session()
    GuildOS.State.birthdays = GuildOS.State.birthdays or { pending = {}, answered = {} }
    return GuildOS.State.birthdays
end

-- The alt groups, read from db.altLinks (flat: an alt points at its main) and kept a few seconds.
local groupsAt, groups
function Birthdays:Forget() groupsAt, groups = nil, nil; self._people = nil end

local function groupIndex()
    local t = GetTime()
    if groups and groupsAt and t - groupsAt < CACHE_S then return groups end
    local members = {}
    for alt, main in pairs(GuildOS.db.altLinks or {}) do
        if type(main) == "string" and alt ~= main then
            members[main] = members[main] or { main }
            local list = members[main]
            list[#list + 1] = alt
        end
    end
    groups, groupsAt = members, t
    return groups
end

--- The keys of a character's alt group, its main first (the character alone when it has no alts).
function Birthdays:Group(key)
    local main = (GuildOS.db.altLinks or {})[key] or key
    return groupIndex()[main] or { main }, main
end

local function sameGroup(a, b)
    local links = GuildOS.db.altLinks or {}
    return (links[a] or a) == (links[b] or b)
end

-- The newest entry of a character's group, tombstones included.
function Birthdays:_Entry(key)
    local s = GuildOS.db and GuildOS.db.birthdays
    if not s or type(key) ~= "string" then return nil end
    local best
    for _, k in ipairs((self:Group(key))) do
        local e = s[k]
        if e and Birthdays.Newer(e, best) then best = e end
    end
    return best
end

--- A character's birthday, the same on every character of the group: { day, month }, or nil.
function Birthdays:For(key)
    local e = self:_Entry(key)
    if not e or e.off then return nil end
    return { day = e.d, month = e.m }
end

--- My own birthday, or nil.
function Birthdays:Mine() return self:For(myKey()) end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------
local MONTH_FIRST = { enUS = true, koKR = true, zhCN = true, zhTW = true }   -- as GuildOS:DateText
local function monthFirst() return MONTH_FIRST[GetLocale and GetLocale() or "enUS"] == true end

--- A birthday as the client's language writes a day and a month ("14/03", "03/14"); nil for none.
function Birthdays:Text(b)
    if type(b) ~= "table" then return nil end
    return GuildOS:DateText(time({ year = 2000, month = b.month, day = b.day, hour = 12 }))
end

--- The roster card's line (#427): "Birthday: 14/03", or nil when the member shares none (never given,
--- or "Show my birthday" unticked: a tombstone reads as none). Day and month only, for any reader.
function Birthdays:TooltipLine(key)
    local b = self:For(key)
    return b and string.format(L["Birthday: %s"], self:Text(b)) or nil
end

--- How a date is typed here: "DD/MM" or "MM/DD".
function Birthdays:Hint() return monthFirst() and L["MM/DD"] or L["DD/MM"] end

local function shortName(key) return (key:match("^([^-]+)") or key) end

----------------------------------------------------------------------
-- Writing
----------------------------------------------------------------------
local function redraw()
    if GuildOS.Calendar and GuildOS.Calendar.Refresh then GuildOS.Calendar:Refresh() end
end

-- A time newer than anything the group holds, so the write wins on every client.
local function nextAt(key)
    local held = Birthdays:_Entry(key)
    return math.max(GetServerTime(), (held and held.at or 0) + 1)
end

function Birthdays:_Write(writes)
    local s, list = store(), {}
    for _, w in ipairs(writes) do
        s[w.key] = w.e
        list[#list + 1] = wire(w.key, w.e)
    end
    bump()
    self:Forget()
    if #list > 0 and GuildOS.SyncService then GuildOS.SyncService:Publish(self.DOMAIN, "set", { list = list }) end
    redraw()
end

--- Sets my birthday (day, month) and tells the guild. True when taken.
function Birthdays:SetMine(d, m)
    if not onGuild() or not Birthdays.Valid(d, m) then return false end
    local me = myKey()
    self:_Write({ { key = me, e = { d = d, m = m, at = nextAt(me), by = me } } })
    return true
end

--- The settings box and the command: my birthday from what was typed; says why when it is not one.
function Birthdays:SetMineText(text)
    local d, m = Birthdays.Parse(text, monthFirst())
    if not d then
        GuildOS:Print(string.format(L["Type the day and the month, like %s."], self:Hint()))
        return false
    end
    if not self:SetMine(d, m) then return false end
    GuildOS:Print(string.format(L["Your birthday is now %s. Only the day and the month are shared."], self:Text({ day = d, month = m })))
    return true
end

-- Tombstones over every character of `key`'s group that holds a birthday, and over `own` itself.
local function clearGroup(key, own, by)
    local s, at, writes = store(), nextAt(key), {}
    for _, k in ipairs((Birthdays:Group(key))) do
        local e = s[k]
        if k == own or (e and not e.off) then writes[#writes + 1] = { key = k, e = { off = true, at = at, by = by } } end
    end
    Birthdays:_Write(writes)
end

--- "Show my birthday" off: removed here and, by tombstone, from every other client. True when done.
function Birthdays:ClearMine()
    if not onGuild() then return false end
    local me = myKey()
    clearGroup(me, me, me)
    return true
end

--- An officer's correction of somebody's birthday. True when taken.
function Birthdays:SetFor(key, d, m)
    if not onGuild() or not GuildOS:IsOfficer() or type(key) ~= "string" or not Birthdays.Valid(d, m) then return false end
    self:_Write({ { key = key, e = { d = d, m = m, at = nextAt(key), by = myKey() } } })
    return true
end

--- An officer removing somebody's birthday (every character of their group). True when done.
function Birthdays:ClearFor(key)
    if not onGuild() or not GuildOS:IsOfficer() or type(key) ~= "string" then return false end
    clearGroup(key, nil, myKey())
    return true
end

--- /gos birthday [DD/MM | off] — and for an officer /gos birthday <name> <DD/MM | off>.
function Birthdays:Command(rest)
    rest = strtrim(rest or "")
    if rest == "" then
        local mine = self:Mine()
        GuildOS:Print(mine and string.format(L["Your birthday: %s."], self:Text(mine)) or L["You have not given your birthday."])
        GuildOS:Print(string.format(L["Usage: /gos birthday <%s | off>"], self:Hint()))
        return
    end
    local name, last = rest:match("^(.-)%s+(%S+)$")
    if not name then
        if rest:lower() == "off" then
            if self:ClearMine() then GuildOS:Print(L["Your birthday is no longer shared."]) end
            return
        end
        self:SetMineText(rest)
        return
    end
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["Only an officer can change another member's birthday."])
        return
    end
    local key = GuildOS:RosterKey(name)
    if not key then
        GuildOS:Print(string.format(L["%s is not on the guild roster."], name))
        return
    end
    if last:lower() == "off" then
        if self:ClearFor(key) then GuildOS:Print(string.format(L["%s's birthday was removed."], shortName(key))) end
        return
    end
    local d, m = Birthdays.Parse(last, monthFirst())
    if not d then
        GuildOS:Print(string.format(L["Type the day and the month, like %s."], self:Hint()))
    elseif self:SetFor(key, d, m) then
        GuildOS:Print(string.format(L["%s's birthday is now %s."], shortName(key), self:Text({ day = d, month = m })))
    end
end

----------------------------------------------------------------------
-- Receiving and the cold sync
----------------------------------------------------------------------
-- The roster's keys, or nil while it is not the whole guild (GuildOS:WholeRoster). Worked out once per
-- roster update (RosterChanged), not per envelope: a backfill is many envelopes, each read by everybody.
local presentCache
function Birthdays:RosterChanged() presentCache = nil end

local function presentKeys()
    if presentCache then return presentCache end
    local roster = GuildOS:WholeRoster()
    if not roster then return nil end
    local keys = { [myKey()] = true }
    for _, full in ipairs(roster) do keys[GuildOS:KeyOfRosterName(full)] = true end
    presentCache = keys
    return keys
end

function Birthdays:OnSync(env, sender)
    local d = type(env.data) == "table" and env.data or nil
    if not d or type(sender) ~= "string" or sender == "" or not onGuild() then return end
    if env.act == "set" then return self:_Apply(d.list, sender) end
    if env.act == "claim" then return self:_OnClaim(d, sender) end
    if env.act == "said" then return self:_OnSaid(d, sender) end
end

-- Entries from `sender`: a member's for their own characters only, an officer's for anybody, and
-- nobody the whole roster says is gone. An older one than this officer holds is answered, once.
function Birthdays:_Apply(list, sender)
    if type(list) ~= "table" then return end
    local from, officer = senderKey(sender), GuildOS:IsOfficerByName(sender)
    local present, now, s = presentKeys(), GetServerTime(), store()
    local changed, answer = false, {}
    for i = 1, math.min(#list, MAX_ITEMS) do
        local it = list[i]
        local e = clean(it, now)
        local key = e and type(it.k) == "string" and #it.k <= KEY_MAX and GuildOS:LocalMemberKey(it.k) or nil
        if key and (officer or key == from or sameGroup(key, from)) and (not present or present[key]) then
            local held = s[key]
            if Birthdays.Newer(e, held) then
                s[key], changed = e, true
            elseif held and Birthdays.Newer(held, e) and GuildOS:IsOfficer() and not session().answered[key] then
                session().answered[key] = true
                answer[#answer + 1] = wire(key, held)
            end
        end
    end
    if changed then bump(); self:Forget(); redraw() end
    if #answer > 0 and GuildOS.SyncService then GuildOS.SyncService:Publish(self.DOMAIN, "set", { list = answer }, { priority = "BULK" }) end
end

--- My own entry to the guild, at login: a client that missed it (offline, a new install) gets it.
function Birthdays:PublishSelf()
    if not onGuild() or not GuildOS.SyncService then return end
    local me = myKey()
    local e = store()[me]
    if e then GuildOS.SyncService:Publish(self.DOMAIN, "set", { list = { wire(me, e) } }, { priority = "BULK" }) end
end

--- Every entry, tombstones included, BATCH an envelope BATCH_GAP seconds apart: an officer's answer to a
--- sync request and /gos sync. One backfill at a time, at most one every BACKFILL_GAP seconds, and one
--- every BACKFILL_IDLE when the store has not changed since the last. Today's "said" go with it.
function Birthdays:Backfill()
    if not GuildOS:IsOfficer() or not GuildOS.SyncService or not onGuild() or self._backfilling then return end
    local t, last = GetTime(), self._backfill
    if last and t - last.at < (last.rev == revision and self.BACKFILL_IDLE or self.BACKFILL_GAP) then return end
    self._backfill = { at = t, rev = revision }
    self:_SendSaid()
    local keys = {}
    for k in pairs(store()) do keys[#keys + 1] = k end
    if #keys == 0 then return end
    table.sort(keys)
    local s = store()
    self._backfilling = true
    local function send(i)
        local list = {}
        for j = i, math.min(i + self.BATCH - 1, #keys) do list[#list + 1] = wire(keys[j], s[keys[j]]) end
        GuildOS.SyncService:Publish(self.DOMAIN, "set", { list = list }, { priority = "BULK" })
        if keys[i + self.BATCH] then
            Compat.After(self.BATCH_GAP, function() send(i + self.BATCH) end)
        else
            self._backfilling = nil
        end
    end
    send(1)
end

--- Whoever left the guild (GuildOS:DropDeparted, the whole roster only): their birthday goes with them.
function Birthdays:Departed(present)
    local s = GuildOS.db and GuildOS.db.birthdays
    if not s then return end
    for key in pairs(s) do
        if not present[key] then s[key] = nil; bump() end
    end
    self:Forget()
end

----------------------------------------------------------------------
-- The people of today's roster: one birthday per alt group, one join anniversary per character that is
-- nobody's alt. Kept for CACHE_S seconds.
----------------------------------------------------------------------
local function firstLook()
    if GuildOS.db.firstSeenSince then return GuildOS.db.firstSeenSince end
    -- A db from before #170: the first look is the earliest sighting.
    local earliest
    for _, t in pairs(GuildOS.db.firstSeen or {}) do
        if type(t) == "number" and (not earliest or t < earliest) then earliest = t end
    end
    return earliest or 0
end

--- When a character's join anniversary counts from (JoinAnchor), and whether it is estimated; nil when unknown.
function Birthdays:JoinedAt(key, floor)
    local stints = GuildOS.MemberHistory and GuildOS.MemberHistory:Stints(key) or {}
    return Birthdays.JoinAnchor(stints, GuildOS:GetFirstSeen(key), floor or firstLook())
end

function Birthdays:People()
    local t = GetTime()
    local p = self._people
    if p and t - p.at < CACHE_S then return p end
    p = { at = t, birthdays = {}, joins = {} }
    local links, seen, floor = GuildOS.db.altLinks or {}, {}, firstLook()
    local inRoster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then inRoster[GuildOS:KeyOfRosterName(name)] = name end
    end
    for key in pairs(inRoster) do
        local main = links[key] or key
        if not seen[main] then
            seen[main] = true
            local b = self:For(key)
            if b then
                p.birthdays[#p.birthdays + 1] = { id = main, name = shortName(inRoster[main] and main or key), d = b.day, m = b.month }
            end
        end
        if not links[key] then
            local at = self:JoinedAt(key, floor)
            if at then p.joins[#p.joins + 1] = { id = key, name = shortName(key), at = at } end
        end
    end
    table.sort(p.birthdays, function(a, b) return a.id < b.id end)
    table.sort(p.joins, function(a, b) return a.id < b.id end)
    self._people = p
    return p
end

local function stampOf(c) return c.year * 10000 + c.month * 100 + c.day end

--- Today's dates on the realm's calendar: { id, name, kind = "birthday" | "join", years }, birthdays first.
function Birthdays:Today(now)
    local c = Compat.RealmClock(now or GetServerTime())
    local out = {}
    local p = self:People()
    for _, b in ipairs(p.birthdays) do
        if Birthdays.OnDay(b.d, b.m, c.year, c.month, c.day) then out[#out + 1] = { id = b.id, name = b.name, kind = "birthday" } end
    end
    for _, j in ipairs(p.joins) do
        local jc = Compat.RealmClock(j.at)
        local years = c.year - jc.year
        if years >= 1 and Birthdays.OnDay(jc.day, jc.month, c.year, c.month, c.day) then
            out[#out + 1] = { id = j.id, name = j.name, kind = "join", years = years }
        end
    end
    return out, stampOf(c)
end

local function lineOf(item)
    if item.kind == "birthday" then return string.format(L["Today is %s's birthday!"], item.name) end
    return string.format(L["%s joined the guild %d year(s) ago today."], item.name, item.years)
end

----------------------------------------------------------------------
-- The digest and the login
----------------------------------------------------------------------
--- Whether today's dates were already told at a login today.
function Birthdays:ToldToday(now)
    local _, stamp = self:Today(now)
    return GuildOS.db.birthdayTold == stamp
end

function Birthdays:MarkTold(now)
    local _, stamp = self:Today(now)
    GuildOS.db.birthdayTold = stamp
end

--- The digest's lines for today, DIGEST_MAX at most and how many more.
function Birthdays:GetDigestLines(now)
    local out, today = {}, self:Today(now)
    for i, item in ipairs(today) do
        if i > DIGEST_MAX then
            out[#out + 1] = string.format(L["And %d more today."], #today - DIGEST_MAX)
            break
        end
        out[#out + 1] = lineOf(item)
    end
    return out
end

--- With the digest switched off: today's lines in the chat, once a day.
function Birthdays:TellInChat(now)
    if self:ToldToday(now) then return end
    for _, line in ipairs(self:GetDigestLines(now)) do GuildOS:Print(line) end
    self:MarkTold(now)
end

----------------------------------------------------------------------
-- The calendar's virtual dates
----------------------------------------------------------------------
local SHOW_SETTING = { birthday = "calBirthdays", join = "calJoinDays" }

--- Whether the calendar draws birthdays ("birthday") or join anniversaries ("join"): on by default.
function Birthdays:Shows(kind) return GuildOS:GetSetting(SHOW_SETTING[kind]) ~= false end

function Birthdays:SetShows(kind, on)
    if SHOW_SETTING[kind] then GuildOS:SetSetting(SHOW_SETTING[kind], on and true or false) end
    redraw()
end

local YEARLY = { rep = "yearly", hour = 12, min = 0 }

--- The virtual dates between two local times: { id, when, title, kind = "BIRTHDAY" | "JOINDAY", virtual }.
--- Worked out now, never stored.
function Birthdays:VirtualEvents(fromT, toT)
    local Cal = GuildOS.Calendar
    local out = {}
    if not Cal or not Cal._Occurrences then return out end
    local p = self:People()
    if self:Shows("birthday") then
        -- From a leap year at or before the window, so 29 February is a date the series starts on.
        local y = tonumber(date("%Y", fromT))
        local base = y - y % 4
        for _, b in ipairs(p.birthdays) do
            local first = time({ year = base, month = b.m, day = b.d, hour = 12 })
            for _, ts in ipairs(Cal._Occurrences(YEARLY, first, fromT, toT, 2)) do
                out[#out + 1] = { id = "bday:" .. b.id .. ":" .. date("%Y", ts), when = ts, kind = "BIRTHDAY", virtual = true,
                                  title = string.format(L["%s's birthday"], b.name) }
            end
        end
    end
    if self:Shows("join") then
        for _, j in ipairs(p.joins) do
            local jt = date("*t", j.at)
            local first = time({ year = jt.year, month = jt.month, day = jt.day, hour = 12 })
            for _, ts in ipairs(Cal._Occurrences(YEARLY, first, math.max(fromT, first + 1), toT, 2)) do
                local years = tonumber(date("%Y", ts)) - jt.year
                out[#out + 1] = { id = "join:" .. j.id .. ":" .. years, when = ts, kind = "JOINDAY", virtual = true,
                                  title = string.format(L["%s: %d year(s) in the guild"], j.name, years) }
            end
        end
    end
    return out
end

--- This realm month's birthdays still ahead, for the game's calendar (WoW: Forever): { name, day, month, year }.
--- Today's only before GAME_HOUR (less GAME_MARGIN minutes): the game refuses an event in the past.
function Birthdays:RestOfMonth(now)
    local c = Compat.RealmClock(now or GetServerTime())
    local from = c.day
    if c.hour * 60 + c.minute >= self.GAME_HOUR * 60 - self.GAME_MARGIN then from = c.day + 1 end
    local out = {}
    for _, b in ipairs(self:People().birthdays) do
        for day = from, 31 do
            if Birthdays.OnDay(b.d, b.m, c.year, c.month, day) then
                out[#out + 1] = { name = b.name, day = day, month = c.month, year = c.year }
                break
            end
        end
    end
    table.sort(out, function(a, b) return a.day < b.day or (a.day == b.day and a.name < b.name) end)
    return out
end

----------------------------------------------------------------------
-- The /g announcement: off by default, an officer's own choice
----------------------------------------------------------------------
function Birthdays:AnnounceOn() return GuildOS:GetSetting("birthdayAnnounce") == true end
function Birthdays:SetAnnounce(on) GuildOS:SetSetting("birthdayAnnounce", on and true or false) end

local function said() GuildOS.db.birthdaySaid = GuildOS.db.birthdaySaid or {}; return GuildOS.db.birthdaySaid end

-- A line's slot, its id in claims, "said" and the pending list: a birthday and a join anniversary of
-- the same person on the same day are two lines. On the wire: the member key and `kind` "b" or "j".
local WIRE_KIND = { birthday = "b", join = "j" }
local function slotOf(kind, key) return kind .. ":" .. key end

--- Claims today's lines this officer may say; each is said CLAIM_WAIT (+ jitter) seconds later unless
--- another officer said it, or claimed it with a lower name, meanwhile.
function Birthdays:CheckAnnounce(now)
    if not onGuild() or not GuildOS:IsOfficer() or not self:AnnounceOn() or not GuildOS.SyncService then return end
    local today, stamp = self:Today(now)
    local s, pending = said(), session().pending
    for id, day in pairs(s) do
        if day ~= stamp then s[id] = nil end
    end
    for _, item in ipairs(today) do
        local kind = WIRE_KIND[item.kind]
        local slot = slotOf(kind, item.id)
        if s[slot] ~= stamp and not pending[slot] then
            local claim = { day = stamp, line = lineOf(item), id = item.id, kind = kind }
            pending[slot] = claim
            GuildOS.SyncService:Publish(self.DOMAIN, "claim", { id = item.id, kind = kind, day = stamp })
            Compat.After(self.CLAIM_WAIT + math.random() * self.CLAIM_JITTER, function() self:_Say(slot, claim) end)
        end
    end
end

function Birthdays:_Say(slot, claim)
    local pending = session().pending
    if pending[slot] ~= claim then return end
    pending[slot] = nil
    if claim.cancelled or said()[slot] == claim.day then return end
    if not Compat.SendChatMessage(claim.line, "GUILD") then return end
    said()[slot] = claim.day
    GuildOS.SyncService:Publish(self.DOMAIN, "said", { id = claim.id, kind = claim.kind, day = claim.day })
end

-- A line off the network: its slot, key and wire kind, or nil. No kind is a birthday.
local function wireSlot(it, day)
    if type(it) ~= "table" or type(it.id) ~= "string" or #it.id > KEY_MAX or not isInt(day) then return nil end
    local kind = it.kind == nil and "b" or it.kind
    if kind ~= "b" and kind ~= "j" then return nil end
    local key = GuildOS:LocalMemberKey(it.id)
    if not key then return nil end
    return slotOf(kind, key), key, kind
end

-- Another officer's claim: answered "said" by an officer who knows it was; my own claim for the same
-- line gives way to a lower name.
function Birthdays:_OnClaim(d, sender)
    local slot, key, kind = wireSlot(d, d.day)
    if not slot or not GuildOS:IsOfficerByName(sender) then return end
    if said()[slot] == d.day then
        if GuildOS:IsOfficer() then GuildOS.SyncService:Publish(self.DOMAIN, "said", { id = key, kind = kind, day = d.day }) end
        return
    end
    local mine = session().pending[slot]
    if mine and mine.day == d.day and senderKey(sender) < myKey() then mine.cancelled = true end
end

-- An officer's "said": one line ({ id, kind, day }), or today's from a backfill ({ day, list }). A
-- member's is dropped: it would silence the line for everybody.
function Birthdays:_OnSaid(d, sender)
    if not GuildOS:IsOfficerByName(sender) then return end
    local list = type(d.list) == "table" and d.list or { d }
    local s, pending = said(), session().pending
    for i = 1, math.min(#list, MAX_ITEMS) do
        local slot = wireSlot(list[i], d.day)
        if slot then
            s[slot] = d.day
            local mine = pending[slot]
            if mine and mine.day == d.day then mine.cancelled = true end
        end
    end
end

-- Today's "said", one envelope with the backfill: an officer who logs in later knows before it claims.
function Birthdays:_SendSaid()
    local stamp = stampOf(Compat.RealmClock(GetServerTime()))
    local list = {}
    for slot, day in pairs(GuildOS.db.birthdaySaid or {}) do
        local kind, key
        if type(slot) == "string" then kind, key = slot:match("^([bj]):(.+)$") end
        if day == stamp and kind and #list < MAX_ITEMS then list[#list + 1] = { id = key, kind = kind } end
    end
    if #list > 0 then GuildOS.SyncService:Publish(self.DOMAIN, "said", { day = stamp, list = list }, { priority = "BULK" }) end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function Birthdays:Initialize()
    store()
    local f = CreateFrame("Frame")
    Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() Birthdays:RosterChanged() end)
    if GuildOS.SyncService then
        GuildOS.SyncService:On(self.DOMAIN, function(env, sender) Birthdays:OnSync(env, sender) end)
    end
    Compat.After(PUBLISH_DELAY, function() Birthdays:PublishSelf() end)
    Compat.After(ANNOUNCE_DELAY, function()
        Birthdays:CheckAnnounce(GetServerTime())
        Compat.NewTicker(ANNOUNCE_EVERY, function() Birthdays:CheckAnnounce(GetServerTime()) end)
    end)
end
