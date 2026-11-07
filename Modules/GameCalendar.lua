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
    -- The raid's clock as it was created goes in as its numbers (guildos-web #411); its instant is then
    -- what the game holds for those numbers on the realm's calendar, which is what matching compares.
    local clock = type(webEvent.clock) == "table" and webEvent.clock or nil
    local startsAt = clock and GuildOS.Compat.EpochOfRealm(clock) or tonumber(webEvent.when) or 0
    return { title = title, description = text .. "\n" .. mark, startsAt = startsAt, clock = clock }
end

-- An hour either way of what an event was put there as is still that event: the realm's clock moving
-- for summer time puts it an hour off, and then it reads out of date and an update fixes it, rather
-- than reading absent and inviting a second one. The hour put on a date past such a change follows
-- today's offset (known limit: the realm's summer-time rule is not modelled).
local SAME_EVENT_TOLERANCE = 3600

--- The game event that is this raid's, among `nativeEvents` ({ title, startsAt, ... }), or nil. First
--- what it was put there as (`webEvent.game`), exactly, then within an hour; then the event the raid
--- would become now, so an identity this client has out of date still finds the event another officer
--- updated. Title and hour together: two raids of one name on one day are two events.
function GameCalendar.Match(webEvent, nativeEvents)
    local list = nativeEvents or {}
    local game = type(webEvent.game) == "table" and webEvent.game or nil
    local gameAt = game and tonumber(game.at)
    if game and type(game.title) == "string" and gameAt then
        for _, e in ipairs(list) do
            if e.title == game.title and e.startsAt == gameAt then return e end
        end
        for _, e in ipairs(list) do
            if e.title == game.title and math.abs(e.startsAt - gameAt) <= SAME_EVENT_TOLERANCE then return e end
        end
    end
    local spec = GameCalendar.SpecFor(webEvent)
    for _, e in ipairs(list) do
        if e.title == spec.title and e.startsAt == spec.startsAt then return e end
    end
    return nil
end

--- What the addon's calendar says about a site raid and the game's calendar:
---   "gone"    the site no longer sends it (inferred, and only where the inbox can tell);
---   "absent"  not in the game's calendar;
---   "stale"   in it, but the site has since changed its title or hour;
---   "present" in it, as the site has it.
--- `inbox` is { ids, count, at }, or nil. Gone needs an inbox at least as new as what this client
--- knows of the raid (`signupsAt`, the site's answer it came with): a raid another officer's newer
--- inbox brought in is not gone from this one's older one. The window is the inbox's, from when it
--- was written, and a raid three hours past its start is past, never gone.
function GameCalendar.StateOf(webEvent, nativeEvents, inbox)
    local at = type(inbox) == "table" and type(inbox.ids) == "table" and tonumber(inbox.at)
    if at then
        local raidId = GameCalendar.RaidIdOf(webEvent)
        local known = tonumber(webEvent.signupsAt) or 0
        local when, now = tonumber(webEvent.when) or 0, GetServerTime()
        local inWindow = when >= at - GameCalendar.GRACE and when <= at + GameCalendar.WINDOW_DAYS * 86400
            and when >= now - GameCalendar.GRACE
        if raidId and not inbox.ids[raidId] and (tonumber(inbox.count) or 0) < GameCalendar.INBOX_CAP
            and known > 0 and known <= at and inWindow then
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
local NEAR = 12 * 3600           -- a same-named guild event this close to a raid's hour may be that raid's

local function eventOf(eventId)
    local e = GuildOS.Calendar and GuildOS.Calendar:GetEvents()[eventId]
    return GameCalendar.RaidIdOf(e) and e or nil
end

-- The game's events around a raid: its hour on the site and, if it was put there, the hour it was put
-- at. Nil while the game has not read its calendar: unknown, never empty.
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

-- A guild event of the raid's name near its hour that no other site raid holds: an event moved or
-- retitled by hand in the game, or one whose answer the addon missed. Putting another would double it.
local function sameNameNearby(e, list, spec)
    local held = {}
    for id, other in pairs(GuildOS.Calendar:GetEvents()) do
        if id ~= e.id and GameCalendar.RaidIdOf(other) then
            local m = GameCalendar.Match(other, list)
            if m then held[m] = true end
        end
    end
    for _, n in ipairs(list) do
        if not held[n] and n.title == spec.title and math.abs(n.startsAt - spec.startsAt) <= NEAR then return true end
    end
    return false
end

--- Whether this client may act on the game's calendar at all.
function GameCalendar:CanAct()
    return GuildOS:IsOfficer() and GuildOS.Compat.CalendarAvailable()
end

--- Whether an action on this raid is waiting for the game's answer.
function GameCalendar:IsWaiting(eventId) return self._pending ~= nil and self._pending[eventId] == true end

-- The one frame this module listens with, made on first use: the game's answers, and the open event
-- closing (which ends a half-done update).
function GameCalendar:_Listen()
    if self._frame then return end
    self._frame = CreateFrame("Frame")
    self._frame:RegisterEvent("CALENDAR_NEW_EVENT")
    self._frame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
    self._frame:RegisterEvent("CALENDAR_UPDATE_ERROR")
    self._frame:RegisterEvent("CALENDAR_CLOSE_EVENT")
    self._frame:SetScript("OnEvent", function(_, event, reason) GameCalendar:_OnAnswer(event, reason) end)
end

-- Waits for the game's answer about `eventId`: `shows()` is true once the game shows what was asked. A
-- refusal ends it with `refusal`, or the game's own sentence for its reason; silence, with ours. While
-- it waits, nothing else is started on that raid.
function GameCalendar:_Await(eventId, shows, onTaken, done, refusal)
    self._waits, self._pending = self._waits or {}, self._pending or {}
    self._pending[eventId] = true
    local wait = {}
    local function finish(ok, msg)
        if wait.over then return end
        wait.over = true
        self._pending[eventId] = nil
        for i, w in ipairs(self._waits) do if w == wait then table.remove(self._waits, i) break end end
        if ok and onTaken then onTaken() end
        if done then done(ok, msg) end
    end
    wait.shows, wait.finish, wait.refusal = shows, finish, refusal
    self._waits[#self._waits + 1] = wait
    self:_Listen()
    GuildOS.Compat.After(ANSWER_WAIT, function() finish(false, L["The game did not answer. Check its calendar."]) end)
end

function GameCalendar:_OnAnswer(event, reason)
    if event == "CALENDAR_CLOSE_EVENT" then
        self._open = nil
        return
    end
    for _, w in ipairs({ unpack(self._waits or {}) }) do
        if event == "CALENDAR_UPDATE_ERROR" then
            local said = type(reason) == "string" and type(_G[reason]) == "string" and _G[reason] or tostring(reason)
            w.finish(false, w.refusal or said)
        elseif w.shows() then
            w.finish(true)
        end
    end
end

-- The checks every click makes first; nil when it may go on, else false and why.
function GameCalendar:_Refuse(eventId)
    if not self:CanAct() then return false, L["Only an officer can do this, on WoW: Forever."] end
    if self:IsWaiting(eventId) then return false, L["Waiting for the game's answer."] end
    return nil
end


--- Puts a site raid in the game's calendar, as a guild event with sign-up.
function GameCalendar:Put(eventId, done)
    local refused, why = self:_Refuse(eventId)
    if refused == false then return refused, why end
    local e = eventOf(eventId)
    if not e then return false end
    local list = nativeAround(e)
    if not list then return false, L["The game's calendar is still loading. Try again in a moment."] end
    if GameCalendar.Match(e, list) then return false, L["It is already in the game's calendar."] end
    local spec = GameCalendar.SpecFor(e)
    if sameNameNearby(e, list, spec) then
        return false, L["The game's calendar already has a guild event with this name around that time. Update or remove it there first."]
    end
    self._open = nil
    local ok, err = GuildOS.Compat.CalendarCreateGuildEvent(spec)
    if not ok then return false, err end
    self:_Await(eventId, function()
        local now = nativeAround(e)
        return now ~= nil and has(now, spec.title, spec.startsAt)
    end, function() GuildOS.Calendar:SetGameEvent(eventId, { title = spec.title, at = spec.startsAt }) end, done)
    return true
end

--- Whether the last click opened this raid's game event, waiting for the click that saves it.
function GameCalendar:IsOpenFor(eventId) return self._open ~= nil and self._open.id == eventId end

-- Opens the raid's game event for the click that saves it, and remembers which event that was.
function GameCalendar:_Open(eventId, e)
    local list = nativeAround(e)
    if not list then return false, L["The game's calendar is still loading. Try again in a moment."] end
    local native = GameCalendar.Match(e, list)
    if not native then return false, L["It is not in the game's calendar."] end
    local ok, err = GuildOS.Compat.CalendarOpenEvent(native)
    if not ok then return false, err end
    self:_Listen()
    self._open = { id = eventId, title = native.title, at = native.startsAt }
    return "opened"
end

--- Brings the game's event in line with the site, in two clicks: the first opens it (returns "opened"),
--- the second saves the site's title and hour onto it, after checking the event still open is this
--- raid's (another may have been opened meanwhile: then it is opened again and nothing is saved). The
--- description is left as it is in the game, where people may have written in it.
function GameCalendar:Refresh(eventId, done)
    local refused, why = self:_Refuse(eventId)
    if refused == false then return refused, why end
    local e = eventOf(eventId)
    if not e then return false end
    if not self:IsOpenFor(eventId) then return self:_Open(eventId, e) end
    local open = GuildOS.Compat.CalendarOpenedEvent()
    if not open or open.title ~= self._open.title or open.startsAt ~= self._open.at then
        return self:_Open(eventId, e)
    end
    self._open = nil
    local spec = GameCalendar.SpecFor(e)
    local ok, err = GuildOS.Compat.CalendarApplyEdit({ title = spec.title, startsAt = spec.startsAt, clock = spec.clock })
    if not ok then return false, err end
    self:_Await(eventId, function()
        local now = nativeAround(e)
        return now ~= nil and has(now, spec.title, spec.startsAt)
    end, function() GuildOS.Calendar:SetGameEvent(eventId, { title = spec.title, at = spec.startsAt }) end, done)
    return true
end

--- Takes a raid's event out of the game's calendar. The server may refuse it (it refused a guild event
--- to a timer, measured): the officer is then told to delete it by hand, and what is there stays known.
function GameCalendar:Take(eventId, done)
    local refused, why = self:_Refuse(eventId)
    if refused == false then return refused, why end
    local e = eventOf(eventId)
    if not e then return false end
    local list = nativeAround(e)
    if not list then return false, L["The game's calendar is still loading. Try again in a moment."] end
    local native = GameCalendar.Match(e, list)
    if not native then return false, L["It is not in the game's calendar."] end
    self._open = nil
    local ok, err = GuildOS.Compat.CalendarRemove(native)
    if not ok then return false, err end
    local title, at = native.title, native.startsAt
    self:_Await(eventId, function()
        local now = nativeAround(e)
        return now ~= nil and not has(now, title, at)
    end, function() GuildOS.Calendar:SetGameEvent(eventId, false) end, done,
        L["The game refused to remove it. Delete it by hand in the game's calendar."])
    return true
end

----------------------------------------------------------------------
-- What the addon's calendar shows for a site raid, and what its button does. Decided here, so the
-- panel only draws (Rule 10).
----------------------------------------------------------------------
local STATE_TEXT = {
    present = L["In the game's calendar."],
    stale = L["In the game's calendar, out of date."],
    absent = L["Not in the game's calendar yet."],
    gone = L["No longer on the website."],
}
local DONE_TEXT = {
    put = L["It is in the game's calendar now."],
    refresh = L["The game's calendar is up to date."],
    take = L["Taken out of the game's calendar."],
}

--- { text, action, label }: the state line, and for whoever may act the button's action
--- ("put", "refresh", "take") and label. Nothing to do, or an answer from the game still awaited
--- (`waiting`): no action.
function GameCalendar.ViewOf(state, hasNative, canAct, isOpen, waiting)
    if waiting then return { text = L["Waiting for the game's answer..."] } end
    local view = { text = STATE_TEXT[state] }
    if not canAct then return view end
    if state == "absent" then
        view.action, view.label = "put", L["Put in the game's calendar"]
    elseif state == "stale" then
        view.action, view.label = "refresh", isOpen and L["Confirm"] or L["Update in the game's calendar"]
    elseif state == "gone" and hasNative then
        view.action, view.label = "take", L["Remove from the game's calendar"]
    end
    return view
end

--- The view of one raid, from the game's events and the inbox read once for the whole panel. Events
--- not read yet (nil) say so and offer nothing.
function GameCalendar:ViewFor(webEvent, nativeEvents, inbox)
    if nativeEvents == nil then return { text = L["Reading the game's calendar..."] } end
    local state = GameCalendar.StateOf(webEvent, nativeEvents, inbox)
    local native = GameCalendar.Match(webEvent, nativeEvents)
    return GameCalendar.ViewOf(state, native ~= nil, self:CanAct(), self:IsOpenFor(webEvent.id), self:IsWaiting(webEvent.id))
end

local function redraw()
    if GuildOS.Calendar and GuildOS.Calendar.Refresh then GuildOS.Calendar:Refresh() end
end

-- Drawn again when the game hands its calendar over, so "reading" turns into the state (I5).
if GuildOS.Compat and GuildOS.Compat.OnCalendarUpdate then GuildOS.Compat.OnCalendarUpdate(redraw) end

--- The panel's button: runs the action and says, in the chat window, what came of it.
function GameCalendar:Act(eventId, action)
    local run = ({ put = self.Put, refresh = self.Refresh, take = self.Take })[action]
    if not run then return end
    local started, why = run(self, eventId, function(ok, msg)
        if ok then GuildOS:Print(DONE_TEXT[action]) elseif msg then GuildOS:Print(msg) end
        redraw()
    end)
    if started == "opened" then
        GuildOS:Print(L["Opened in the game's calendar: click Confirm to save it."])
    elseif not started and why then
        GuildOS:Print(why)
    end
    redraw()
end
