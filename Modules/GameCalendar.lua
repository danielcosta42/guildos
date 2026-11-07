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
