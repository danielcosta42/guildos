----------------------------------------------------------------------
-- Guild OS - the game's own calendar (guildos-web specs/075, guildos#263)
-- A raid planned on the site, put in WoW: Forever's calendar by an officer's click, and the state the
-- addon's calendar shows for it. This half is the reasoning, with no state and no game calls: the
-- event a raid becomes, which game event is the raid's, and whether the site still has the raid.
-- The calls themselves are in Core/Compat.lua; the clicks, further down.
----------------------------------------------------------------------
local GameCalendar = {}
GuildOS.GameCalendar = GameCalendar
local L = GuildOS.L

GameCalendar.TITLE_MAX = 31          -- letters the game's title box takes (Blizzard_Calendar.xml)
GameCalendar.DESC_MAX = 255          -- letters its description takes
-- What the companion's inbox holds, from apps/web/app/api/roster/route.ts in guildos-web: at most ten
-- raids, four weeks ahead, kept three hours after their start. A raid missing from it is only known
-- to be gone inside all three.
GameCalendar.INBOX_CAP = 10
GameCalendar.WINDOW_DAYS = 28
GameCalendar.GRACE = 3 * 3600

local MARK = "guildos:"
local WEB_PREFIX = "web:"
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- The first `n` letters of `s`, never cutting through a multi-byte one.
local function firstLetters(s, n)
    local out, count = {}, 0
    for ch in s:gmatch(UTF8_CHAR) do
        if count >= n then break end
        out[#out + 1] = ch
        count = count + 1
    end
    return table.concat(out), count
end

local function letters(s)
    local _, n = s:gsub(UTF8_CHAR, "")
    return n
end

--- The mark a game event carries in its description to say which site raid it is.
function GameCalendar.Marker(raidId) return MARK .. raidId end

--- The site raid a description names, or nil.
function GameCalendar.RaidIdIn(description)
    if type(description) ~= "string" then return nil end
    return description:match(MARK .. "([%w_%-]+)")
end

--- The site's id of a raid in the addon's calendar (`web:<id>`), or nil for any other event.
function GameCalendar.RaidIdOf(webEvent)
    local id = type(webEvent) == "table" and webEvent.id
    if type(id) ~= "string" or id:sub(1, #WEB_PREFIX) ~= WEB_PREFIX then return nil end
    return id:sub(#WEB_PREFIX + 1)
end

--- The game event a site raid becomes: { title, description, startsAt }.
function GameCalendar.SpecFor(webEvent)
    local title = firstLetters(tostring(webEvent.title or ""), GameCalendar.TITLE_MAX)
    local mark = GameCalendar.Marker(GameCalendar.RaidIdOf(webEvent) or "")
    -- The line people read may be cut; the mark at the end never is.
    local room = GameCalendar.DESC_MAX - letters(mark) - 1
    local text = firstLetters(L["Sign up here, in Discord or on guildos.me."], math.max(room, 0))
    return { title = title, description = text .. "\n" .. mark, startsAt = tonumber(webEvent.when) or 0 }
end

--- The game event that is this raid's, among `nativeEvents` ({ title, startsAt, ... }), or nil. One put
--- there by the addon is found by what it was put there as (`webEvent.game`), so a raid the site moved
--- since is still found; otherwise by the event the raid would become. Title and hour together: two
--- raids of one name on one day are two events.
function GameCalendar.Match(webEvent, nativeEvents)
    local game = type(webEvent.game) == "table" and webEvent.game or nil
    local spec = GameCalendar.SpecFor(webEvent)
    local title = game and game.title or spec.title
    local at = game and tonumber(game.at) or spec.startsAt
    for _, e in ipairs(nativeEvents or {}) do
        if e.title == title and e.startsAt == at then return e end
    end
    return nil
end

--- What the addon's calendar says about a site raid and the game's calendar:
---   "gone"    the site no longer sends it (inferred, and only where the inbox can tell);
---   "absent"  not in the game's calendar;
---   "stale"   in it, but the site has since changed its title or hour;
---   "present" in it, as the site has it.
--- `inbox` is { ids = { [raidId] = true }, count = n }, or nil when no inbox was read.
function GameCalendar.StateOf(webEvent, nativeEvents, inbox)
    if type(inbox) == "table" and type(inbox.ids) == "table" then
        local raidId = GameCalendar.RaidIdOf(webEvent)
        local when, now = tonumber(webEvent.when) or 0, GetServerTime()
        local inWindow = when >= now - GameCalendar.GRACE and when <= now + GameCalendar.WINDOW_DAYS * 86400
        if raidId and not inbox.ids[raidId] and (tonumber(inbox.count) or 0) < GameCalendar.INBOX_CAP and inWindow then
            return "gone"
        end
    end
    local native = GameCalendar.Match(webEvent, nativeEvents)
    if not native then return "absent" end
    local spec = GameCalendar.SpecFor(webEvent)
    if native.title ~= spec.title or native.startsAt ~= spec.startsAt then return "stale" end
    return "present"
end

----------------------------------------------------------------------
-- The clicks. Only an officer's, only on WoW: Forever, and only from a button: the game refuses
-- creating and editing to anything else. The game answers later (a new event or a refreshed list, or
-- CALENDAR_UPDATE_ERROR), so each action reports through `done(ok, message)` once; its own return says
-- only whether the click could start it. What the raid was put there as is kept, and shared with the
-- other officers, only once the game shows it.
----------------------------------------------------------------------
local ANSWER_WAIT = 6            -- seconds the game has to answer before the officer is told it did not
local AROUND = 86400             -- the game's events read around a raid, either side of it
local ANSWER_EVENTS = { "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_ERROR" }

local function eventOf(eventId)
    local e = GuildOS.Calendar and GuildOS.Calendar:GetEvents()[eventId]
    return GameCalendar.RaidIdOf(e) and e or nil
end

-- The game's events around a raid: its hour on the site and, if it was put there, the hour it was put at.
local function nativeAround(e)
    local when = tonumber(e.when) or 0
    local put = type(e.game) == "table" and tonumber(e.game.at) or when
    return GuildOS.Compat.CalendarGuildEvents(math.min(when, put) - AROUND, math.max(when, put) + AROUND)
end

local function has(list, title, at)
    for _, n in ipairs(list) do
        if n.title == title and n.startsAt == at then return true end
    end
    return false
end

--- Whether this client may act on the game's calendar at all.
function GameCalendar:CanAct()
    return GuildOS:IsOfficer() and GuildOS.Compat.CalendarAvailable()
end

-- Waits for the game's answer: `shows()` is true once the game shows what was asked. A refusal ends it
-- with `refusal`, or the game's own sentence for its reason; silence, with a sentence of ours.
function GameCalendar:_Await(shows, onTaken, done, refusal)
    self._waits = self._waits or {}
    local wait = {}
    local function finish(ok, msg)
        if wait.over then return end
        wait.over = true
        for i, w in ipairs(self._waits) do if w == wait then table.remove(self._waits, i) break end end
        if ok and onTaken then onTaken() end
        if done then done(ok, msg) end
    end
    wait.shows, wait.finish, wait.refusal = shows, finish, refusal
    self._waits[#self._waits + 1] = wait
    if not self._frame then
        self._frame = CreateFrame("Frame")
        for _, ev in ipairs(ANSWER_EVENTS) do self._frame:RegisterEvent(ev) end
        self._frame:SetScript("OnEvent", function(_, event, reason) GameCalendar:_OnAnswer(event, reason) end)
    end
    GuildOS.Compat.After(ANSWER_WAIT, function() finish(false, L["The game did not answer. Check its calendar."]) end)
end

function GameCalendar:_OnAnswer(event, reason)
    for _, w in ipairs({ unpack(self._waits or {}) }) do
        if event == "CALENDAR_UPDATE_ERROR" then
            local said = type(reason) == "string" and type(_G[reason]) == "string" and _G[reason] or tostring(reason)
            w.finish(false, w.refusal or said)
        elseif w.shows() then
            w.finish(true)
        end
    end
end

--- Puts a site raid in the game's calendar, as a guild event with sign-up.
function GameCalendar:Put(eventId, done)
    if not self:CanAct() then return false, L["Only an officer can do this, on WoW: Forever."] end
    local e = eventOf(eventId)
    if not e then return false end
    if GameCalendar.Match(e, nativeAround(e)) then return false, L["It is already in the game's calendar."] end
    local spec = GameCalendar.SpecFor(e)
    local ok, err = GuildOS.Compat.CalendarCreateGuildEvent(spec)
    if not ok then return false, err end
    self:_Await(function() return has(nativeAround(e), spec.title, spec.startsAt) end,
        function() GuildOS.Calendar:SetGameEvent(eventId, { title = spec.title, at = spec.startsAt }) end, done)
    return true
end

--- Whether the last click opened this raid's game event, waiting for the click that saves it.
function GameCalendar:IsOpenFor(eventId) return self._open ~= nil and self._open == eventId end

--- Brings the game's event in line with the site, in two clicks: the first opens it (returns "opened"),
--- the second saves the site's title and hour onto it.
function GameCalendar:Refresh(eventId, done)
    if not self:CanAct() then return false, L["Only an officer can do this, on WoW: Forever."] end
    local e = eventOf(eventId)
    if not e then return false end
    if self._open ~= eventId then
        local native = GameCalendar.Match(e, nativeAround(e))
        if not native then return false, L["It is not in the game's calendar."] end
        local ok, err = GuildOS.Compat.CalendarOpenEvent(native)
        if not ok then return false, err end
        self._open = eventId
        return "opened"
    end
    self._open = nil
    local spec = GameCalendar.SpecFor(e)
    local ok, err = GuildOS.Compat.CalendarApplyEdit(spec)
    if not ok then return false, err end
    self:_Await(function() return has(nativeAround(e), spec.title, spec.startsAt) end,
        function() GuildOS.Calendar:SetGameEvent(eventId, { title = spec.title, at = spec.startsAt }) end, done)
    return true
end

--- Takes a raid's event out of the game's calendar. The server may refuse it (it refused a guild event
--- to a timer, measured): the officer is then told to delete it by hand, and what is there stays known.
function GameCalendar:Take(eventId, done)
    if not self:CanAct() then return false, L["Only an officer can do this, on WoW: Forever."] end
    local e = eventOf(eventId)
    local native = e and GameCalendar.Match(e, nativeAround(e))
    if not native then return false, L["It is not in the game's calendar."] end
    local ok, err = GuildOS.Compat.CalendarRemove(native)
    if not ok then return false, err end
    local title, at = native.title, native.startsAt
    self:_Await(function() return not has(nativeAround(e), title, at) end,
        function() GuildOS.Calendar:SetGameEvent(eventId, false) end, done,
        L["The game refused to remove it. Delete it by hand in the game's calendar."])
    return true
end
