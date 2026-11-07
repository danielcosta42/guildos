-- A raid planned on the site, in the game's own calendar (guildos-web specs/075, guildos#263), run
-- against the real Modules/GameCalendar.lua.
--
-- What decides it: the event the addon makes from a raid (a title the game takes, at most 31 letters
-- and never cut through an accented one; a description that keeps the raid's mark whole), which game
-- event is the raid's (two raids of the same name on the same day are two events), and the state the
-- addon's calendar shows. "No longer on the website" is inferred from the companion's inbox, which also
-- drops raids past its cap of ten and its four weeks: neither may read as cancelled.
--
--   luajit -e 'ADDON="."' tools/game-calendar.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

local NOW = 1793998800   -- 2026-11-06 21:00 UTC
function GetServerTime() return NOW end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
dofile(ADDON .. "/Modules/GameCalendar.lua")
local G = GuildOS.GameCalendar

local function utf8len(s) local _, n = s:gsub("[^\128-\191]", ""); return n end

-- ── 1. The mark ───────────────────────────────────────────────────────
check(G.Marker("clx9a_b-1") == "guildos:clx9a_b-1", "the mark names the site's raid")
check(G.RaidIdIn("Sign up here.\nguildos:clx9a_b-1") == "clx9a_b-1", "and reads back out of a description")
check(G.RaidIdIn("no mark at all") == nil, "a description without one names nothing")
check(G.RaidIdIn(nil) == nil, "nor does none")

-- ── 2. The event a raid becomes ───────────────────────────────────────
local function raid(id, title, when) return { id = "web:" .. id, title = title, when = when } end
local long = raid("r1", string.rep("K", 40), NOW + 86400)
local spec = G.SpecFor(long)
check(#spec.title == G.TITLE_MAX and G.TITLE_MAX == 31, "a long title is cut to the 31 letters the game takes")
check(spec.startsAt == NOW + 86400, "at the raid's time")
check(spec.description:sub(-#"guildos:r1") == "guildos:r1", "the mark closes the description")
check(utf8len(spec.description) <= G.DESC_MAX and G.DESC_MAX == 255, "within the 255 letters the game takes")
local accented = G.SpecFor(raid("r2", "Ataque à Fortaleza da Tempestade Ígnea, de novo", NOW))
check(utf8len(accented.title) == 31, "letters, not bytes: an accented title keeps 31 letters")
check(accented.title:find("[\194-\244]$") == nil, "and never ends in half a letter")
check(G.SpecFor(raid("r3", "Karazhan", NOW)).title == "Karazhan", "a short title stays as it is")

-- ── 3. Which game event is the raid's ─────────────────────────────────
local early, late = raid("ra", "Karazhan", NOW + 3600), raid("rb", "Karazhan", NOW + 7200)
local native = {
  { title = "Karazhan", startsAt = NOW + 3600, offset = 0, day = 6, index = 1 },
  { title = "Karazhan", startsAt = NOW + 7200, offset = 0, day = 6, index = 2 },
  { title = "Quest da Sleeping Bag", startsAt = NOW, offset = 0, day = 6, index = 3 },
}
check(G.Match(early, native).index == 1 and G.Match(late, native).index == 2,
  "two raids of the same name on the same day are two events")
check(G.Match(raid("rc", "Gruul", NOW), native) == nil, "a raid not in the game matches nothing")
-- Put in the game as it was; the site moved it since: still found, by what was put there.
local moved = raid("ra", "Karazhan", NOW + 5400)
moved.game = { title = "Karazhan", at = NOW + 3600 }
check(G.Match(moved, native).index == 1, "an event put in the game is found by what it was put there as")
-- What this client knows it was put there as is out of date (another officer updated it while this one
-- was away): the event as the site has it now is still the raid's (final review I3).
local outdated = raid("rb", "Karazhan", NOW + 7200)
outdated.game = { title = "Karazhan", at = NOW + 9000 }
check(G.Match(outdated, native) and G.Match(outdated, native).index == 2, "an out-of-date identity falls back to the site's")
-- The realm's clock moved an hour (summer time) since it was put there: still found, so it reads out of
-- date and an update fixes it, rather than reading absent and inviting a second event (I4).
local shifted = raid("rs", "Gruul", NOW + 86400)
shifted.game = { title = "Gruul", at = NOW + 86400 }
local shiftedNative = { { title = "Gruul", startsAt = NOW + 86400 + 3600, offset = 0, day = 7, index = 1 } }
check(G.Match(shifted, shiftedNative) ~= nil, "an hour off what it was put there as is still the same event")
check(G.StateOf(shifted, shiftedNative, nil) == "stale", "and reads out of date")
local twoHoursOff = { { title = "Gruul", startsAt = NOW + 86400 + 7200, offset = 0, day = 7, index = 1 } }
check(G.Match(shifted, twoHoursOff) == nil, "two hours off is not")
local exactFirst = raid("ra", "Karazhan", NOW + 3600)
exactFirst.game = { title = "Karazhan", at = NOW + 7200 }
check(G.Match(exactFirst, native).index == 2, "the exact hour wins over an hour's tolerance")

-- ── 4. The state the addon's calendar shows ───────────────────────────
local inbox = { ids = { ra = true, rb = true, rc = true }, count = 3, at = NOW - 600 }
check(G.StateOf(early, native, inbox) == "present", "in the game, as the site has it")
check(G.StateOf(moved, native, inbox) == "stale", "in the game, but the site moved it")
check(G.StateOf(raid("rc", "Gruul", NOW + 86400), native, inbox) == "absent", "not in the game yet")
local gone = raid("rz", "Karazhan", NOW + 3600)
gone.game = { title = "Karazhan", at = NOW + 3600 }
gone.signupsAt = NOW - 3600   -- what we know of it came from an inbox older than the one read now
local INBOX = function(count) return { ids = {}, count = count, at = NOW - 600 } end
check(G.StateOf(gone, native, INBOX(9)) == "gone", "out of an inbox under its cap: no longer on the website")
check(G.StateOf(gone, native, INBOX(10)) ~= "gone", "out of a full inbox it may just be past the cap")
check(G.StateOf(raid("rz", "Far", NOW + 40 * 86400), native, INBOX(2)) ~= "gone",
  "beyond the four weeks the inbox covers, missing proves nothing")
check(G.StateOf(raid("rz", "Started", NOW - 4 * 3600), native, INBOX(2)) ~= "gone",
  "nor once the three hours after its start are over")
check(G.StateOf(gone, native, nil) ~= "gone", "with no inbox read, nothing is gone")
-- Final review C1: a raid another officer's newer inbox brought in, after the one this client read.
local synced = raid("rn", "Karazhan", NOW + 3600)
synced.signupsAt = NOW - 60
check(G.StateOf(synced, native, INBOX(2)) ~= "gone", "a raid newer than the inbox read is not gone")
local unknown = raid("ru", "Karazhan", NOW + 3600)
check(G.StateOf(unknown, native, INBOX(2)) ~= "gone", "nor one with no date of its own")
check(G.StateOf(gone, native, { ids = {}, count = 2 }) ~= "gone", "nor against an inbox with no date")

-- ── 5. The clicks: put, update, remove ────────────────────────────────
-- The game answers later (a new event, a refreshed list, or CALENDAR_UPDATE_ERROR), so each action
-- reports through `done` once, and what was put there is kept only once the game took it.
local frames, timers = {}, {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(_, fn) self.fn = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(ev, ...) for _, f in ipairs(frames) do if f.events[ev] and f.fn then f.fn(f, ev, ...) end end end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function timeout() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
local officer = true
function GuildOS:IsOfficer() return officer end
CALENDAR_ERROR_PERMISSIONS = "You do not have permission to do that."   -- the game's own sentence

local inGame, created, edited, removed = {}, {}, {}, {}
local loaded, openedNow = true, nil   -- whether the game has read its calendar yet; the event it has open
GuildOS.Compat = {
  After = function(_, fn) timers[#timers + 1] = fn end,
  CalendarAvailable = function() return true end,
  CalendarGuildEvents = function() if loaded then return inGame end end,
  CalendarCreateGuildEvent = function(spec) created[#created + 1] = spec; return true end,
  CalendarOpenEvent = function(where) openedNow = where; return true end,
  CalendarOpenedEvent = function() return openedNow and { title = openedNow.title, startsAt = openedNow.startsAt } end,
  -- A realm six hours behind UTC: what the game will hold for a date and time on its calendar.
  EpochOfRealm = function(t) return 1793750400 + ((t.day - 1) * 24 + t.hour + 6) * 3600 + t.minute * 60 end,
  CalendarApplyEdit = function(spec) edited[#edited + 1] = spec; return true end,
  CalendarRemove = function(where) removed[#removed + 1] = where; return true end,
}
local events, stored = {}, {}
GuildOS.Calendar = {
  GetEvents = function() return events end,
  SetGameEvent = function(_, id, g) stored[id] = g; events[id].game = g or nil end,
}
local function answer() local out = {}; return out, function(ok, msg) out.ok, out.msg, out.n = ok, msg, (out.n or 0) + 1 end end

events["web:rp"] = raid("rp", "Karazhan", NOW + 86400)
local put, putDone = answer()
check(G:Put("web:rp", putDone) == true, "an officer's click starts it")
check(#created == 1 and created[1].title == "Karazhan" and created[1].startsAt == NOW + 86400
  and created[1].description:find("guildos:rp", 1, true), "the event the raid becomes")
check(put.n == nil and stored["web:rp"] == nil, "nothing is kept before the game answers")
inGame[#inGame + 1] = { title = "Karazhan", startsAt = NOW + 86400, offset = 0, day = 7, index = 1 }
fire("CALENDAR_NEW_EVENT")
check(put.ok == true and put.n == 1, "the game took it, said once")
check(stored["web:rp"] and stored["web:rp"].title == "Karazhan" and stored["web:rp"].at == NOW + 86400,
  "what was put there is kept")
fire("CALENDAR_UPDATE_EVENT_LIST")
check(put.n == 1, "and never said twice")
local again = select(2, G:Put("web:rp", function() end))
check(#created == 1 and type(again) == "string", "a raid already in the game is not put there twice")

officer = false
events["web:rm"] = raid("rm", "Gruul", NOW + 86400)
check(G:Put("web:rm", function() end) == false and #created == 1, "a member's click does nothing")
officer = true

-- Final review I1: a second click before the game answers is not a second event.
events["web:rd"] = raid("rd", "Gruul", NOW + 3 * 86400)
check(G:Put("web:rd", function() end) == true, "the first click starts it")
local second, secondWhy = G:Put("web:rd", function() end)
check(second == false and secondWhy == "Waiting for the game's answer." and #created == 2, "a second click while it waits does nothing")
timeout()   -- the game never answered: free to try again
-- I3: a guild event of that name near that hour that is no raid's (moved or retitled by hand in the game)
-- makes Put refuse, rather than make a second one.
inGame[#inGame + 1] = { title = "Gruul", startsAt = NOW + 3 * 86400 + 7200, offset = 0, day = 9, index = 2 }
local doubled, doubledWhy = G:Put("web:rd", function() end)
check(doubled == false and #created == 2 and doubledWhy ==
  "The game's calendar already has a guild event with this name around that time. Update or remove it there first.",
  "a same-named event near that hour is never doubled")
table.remove(inGame)
-- I5: the calendar not read yet is unknown, never empty: no Put.
loaded = false
local notYet, notYetWhy = G:Put("web:rd", function() end)
check(notYet == false and notYetWhy == "The game's calendar is still loading. Try again in a moment." and #created == 2,
  "no Put before the game has read its calendar")
loaded = true

local refused, refusedDone = answer()
G:Put("web:rm", refusedDone)
fire("CALENDAR_UPDATE_ERROR", "CALENDAR_ERROR_PERMISSIONS")
check(refused.ok == false and refused.msg:find("permission", 1, true), "the game's refusal, in its own words")
check(stored["web:rm"] == nil, "and nothing kept")

local silent, silentDone = answer()
G:Put("web:rm", silentDone)
timeout()
check(silent.ok == false and silent.msg == "The game did not answer. Check its calendar.", "no answer is said too")

-- The site moved the raid: open it with one click, save it with the next.
events["web:rp"].when = NOW + 86400 + 1800
local upd, updDone = answer()
check(G:Refresh("web:rp", updDone) == "opened" and G:IsOpenFor("web:rp"), "the first click opens it")
check(#edited == 0, "and saves nothing")
check(G:Refresh("web:rp", updDone) == true and #edited == 1 and edited[1].startsAt == NOW + 86400 + 1800,
  "the second saves the site's hour")
inGame[1].startsAt = NOW + 86400 + 1800
fire("CALENDAR_UPDATE_EVENT_LIST")
check(upd.ok == true and stored["web:rp"].at == NOW + 86400 + 1800 and not G:IsOpenFor("web:rp"),
  "what is in the game now is kept")
check(edited[1].description == nil, "an update leaves the description people may have edited in the game alone (I6)")
-- I2: the second click checks that the event still open is this raid's.
events["web:rp"].when = NOW + 86400 + 3600
check(G:Refresh("web:rp", function() end) == "opened", "open it again")
openedNow = { title = "Quest da Sleeping Bag", startsAt = NOW }   -- the officer opened another event meanwhile
check(G:Refresh("web:rp", function() end) == "opened" and #edited == 1, "another event open: nothing saved, the raid's opened again")
check(G:Refresh("web:rp", function() end) == true and #edited == 2, "the raid's open: saved")
timeout()
events["web:rp"].when = NOW + 86400 + 1800   -- back to what the game has
check(G:Refresh("web:rp", function() end) == "opened", "opened")
G:Put("web:rm", function() end)
check(not G:IsOpenFor("web:rp"), "another action forgets what was open")
timeout()

-- Removing: the server may refuse it, as it refused a guild event to a timer.
local take, takeDone = answer()
check(G:Take("web:rp", takeDone) == true and removed[1].index == 1, "removed where it sits")
fire("CALENDAR_UPDATE_ERROR", "CALENDAR_ERROR_PERMISSIONS")
check(take.ok == false and take.msg == "The game refused to remove it. Delete it by hand in the game's calendar.",
  "a refusal says to delete it by hand")
check(stored["web:rp"] and stored["web:rp"].at == NOW + 86400 + 1800, "and keeps what is still there")
local take2, take2Done = answer()
G:Take("web:rp", take2Done)
loaded = false
fire("CALENDAR_UPDATE_EVENT_LIST")
check(take2.n == nil, "a calendar not read yet is never taken for the event being gone (I5)")
loaded = true
table.remove(inGame, 1)
fire("CALENDAR_UPDATE_EVENT_LIST")
check(take2.ok == true and stored["web:rp"] == false, "gone from the game: nothing kept")

-- #411: the raid's clock as it was created goes to the game exactly.
local typed = raid("rt", "teste", NOW + 86400)
typed.clock = { year = 2026, month = 11, day = 8, hour = 1, minute = 4 }
local tspec = G.SpecFor(typed)
check(tspec.clock == typed.clock and tspec.startsAt == GuildOS.Compat.EpochOfRealm(typed.clock),
  "with a clock, the event is those numbers on the game's calendar, and its instant is what the game holds for them")
events["web:rt"] = typed
G:Put("web:rt", function() end)
check(created[#created].clock == typed.clock, "and Put hands the clock to the game")
inGame[#inGame + 1] = { title = "teste", startsAt = tspec.startsAt, offset = 0, day = 8, index = 9 }
fire("CALENDAR_NEW_EVENT")
check(G.StateOf(typed, inGame, nil) == "present", "and then reads as in the game, as the site has it")
table.remove(inGame)

-- ── 6. What the addon's calendar shows, and what a click there does ───
local v = G.ViewOf("absent", false, true, false)
check(v.text == "Not in the game's calendar yet." and v.action == "put" and v.label == "Put in the game's calendar",
  "not in the game: an officer gets the button that puts it there")
check(G.ViewOf("absent", false, false, false).action == nil, "a member reads the state and gets no button")
local waiting = G.ViewOf("absent", false, true, false, true)
check(waiting.text == "Waiting for the game's answer..." and waiting.action == nil, "while the game answers: no button (I1)")
local reading = G:ViewFor(raid("rv", "Hyjal", NOW + 86400), nil, nil)
check(reading.text == "Reading the game's calendar..." and reading.action == nil, "the calendar not read yet: no button (I5)")
check(G.ViewOf("present", true, true, false).text == "In the game's calendar." and G.ViewOf("present", true, true, false).action == nil,
  "in the game as the site has it: nothing to do")
local st = G.ViewOf("stale", true, true, false)
check(st.text == "In the game's calendar, out of date." and st.action == "refresh" and st.label == "Update in the game's calendar",
  "out of date: the button that updates it")
check(G.ViewOf("stale", true, true, true).label == "Confirm", "once opened, the second click confirms")
local gv = G.ViewOf("gone", true, true, false)
check(gv.text == "No longer on the website." and gv.action == "take" and gv.label == "Remove from the game's calendar",
  "no longer on the site, still in the game: the button that takes it out")
check(G.ViewOf("gone", false, true, false).action == nil, "no longer on the site and not in the game: nothing to take out")

local printed, redrawn = {}, 0
function GuildOS:Print(m) printed[#printed + 1] = m end
GuildOS.Calendar.Refresh = function() redrawn = redrawn + 1 end
events["web:rq"] = raid("rq", "Magtheridon", NOW + 2 * 86400)
G:Act("web:rq", "put")
inGame[#inGame + 1] = { title = "Magtheridon", startsAt = NOW + 2 * 86400, offset = 0, day = 8, index = 1 }
fire("CALENDAR_NEW_EVENT")
check(printed[#printed] == "It is in the game's calendar now." and redrawn >= 1, "a click says what happened and redraws")
G:Act("web:rq", "put")
check(printed[#printed] == "It is already in the game's calendar.", "and says why when it could not start")

io.write(string.format("game-calendar: %d checks passed\n", checks))
