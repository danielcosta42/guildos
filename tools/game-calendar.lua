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

-- ── 4. The state the addon's calendar shows ───────────────────────────
local inbox = { ids = { ra = true, rb = true, rc = true }, count = 3 }
check(G.StateOf(early, native, inbox) == "present", "in the game, as the site has it")
check(G.StateOf(moved, native, inbox) == "stale", "in the game, but the site moved it")
check(G.StateOf(raid("rc", "Gruul", NOW + 86400), native, inbox) == "absent", "not in the game yet")
local gone = raid("rz", "Karazhan", NOW + 3600)
gone.game = { title = "Karazhan", at = NOW + 3600 }
check(G.StateOf(gone, native, { ids = {}, count = 9 }) == "gone", "out of an inbox under its cap: no longer on the website")
check(G.StateOf(gone, native, { ids = {}, count = 10 }) ~= "gone", "out of a full inbox it may just be past the cap")
check(G.StateOf(raid("rz", "Far", NOW + 40 * 86400), native, { ids = {}, count = 2 }) ~= "gone",
  "beyond the four weeks the inbox covers, missing proves nothing")
check(G.StateOf(raid("rz", "Started", NOW - 4 * 3600), native, { ids = {}, count = 2 }) ~= "gone",
  "nor once the three hours after its start are over")
check(G.StateOf(gone, native, nil) ~= "gone", "with no inbox read, nothing is gone")

io.write(string.format("game-calendar: %d checks passed\n", checks))
