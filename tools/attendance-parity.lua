-- The attendance number, straight out of the addon, as a fixture the website
-- checks its own answer against.
--
-- The website recomputes attendance rather than echoing `att25`, because it holds
-- the union of every officer's nights while any one client holds only what that
-- client recorded. That means the rule exists twice, in two languages, and two
-- implementations of one rule drift unless something holds them together.
--
-- This is that something. It runs the REAL `RaidTracker:RebuildAttendanceFromSessions`
-- and `GetAttendance25ManPercent` over a set of nights, and prints both the nights
-- (in the shape the wire carries them) and the percentages the game would show. The
-- website's `test/parity.test.ts` reads the file, feeds the nights to `standings()`
-- and asserts the answers match to the digit.
--
--   luajit -e 'ADDON="."' tools/attendance-parity.lua > .../apps/web/test/fixtures/attendance-parity.json
--
-- Regenerate whenever either side's rule changes. A diff here is the two halves
-- disagreeing, which is exactly what it is for.
ADDON = ADDON or "."
package.path = ADDON .. "/?.lua;" .. package.path

BRutus = { L = setmetatable({}, { __index = function(_, k) return k end }) }
function BRutus:Print() end
function BRutus:IsOfficer() return true end

-- ── the WoW surface RaidTracker touches at load ───────────────────────
function GetServerTime() return 1754380000 end
function GetRealmName() return "Firemaw" end
function UnitName() return "Chehul" end
function IsInGuild() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function UnitClass() return "Hunter", "HUNTER" end
function UnitIsConnected() return true end
function GetInstanceInfo() return "Gruul's Lair", "raid", 0, "", 25, 0, false, 565 end
function C_Timer_After() end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
function CreateFrame()
  return setmetatable({}, { __index = function() return function() end end })
end
function LibStub() return nil end

dofile(ADDON .. "/Modules/RaidTracker.lua")
local RT = BRutus.RaidTracker

-- Two cores with different weights, because the whole reason the rules travel is
-- that an officer can change them and the website cannot assume 10/10/10.
local RULES = {
  [""]       = { LATE = 10, LEFT_EARLY = 10, NO_CONSUMES = 10 },
  ["Core 2"] = { LATE = 25, LEFT_EARLY = 5,  NO_CONSUMES = 0  },
}
BRutus.CoreManager = {
  GetPenalties = function(_, tag) return RULES[tag] or RULES[""] end,
}

----------------------------------------------------------------------
-- The nights
--
-- Every branch of the rule has to be exercised here or the parity test only
-- proves the two agree about the easy case:
--   * a perfect night, and a night with each penalty on its own
--   * two officers recording the same lockout, which is one chance to attend
--   * the same instance twice in one week, which is also one chance
--   * two instances the same evening, which is two
--   * a ten-man, which moves nobody's denominator but does decide their core
--   * a night marked not-a-guild-raid, which counts for nothing at all
--   * somebody who raids with two cores and belongs to the busier one
----------------------------------------------------------------------
local T = 1754380000        -- a Tuesday evening
local HOUR, DAY, WEEK = 3600, 86400, 604800

local function snap(at, members) return { time = at, reason = "tick", members = members } end
local function who(name, online, consumes)
  return { name = name, class = "HUNTER", online = online ~= false, hasConsumes = consumes == true }
end

local SESSIONS = {}
local function night(id, over)
  local s = {
    instanceID = 565, name = "Gruul's Lair", groupTag = "", startTime = id,
    endTime = id + 4 * HOUR, encounters = {}, players = {}, snapshots = {},
  }
  for k, v in pairs(over) do s[k] = v end
  for _, sn in ipairs(s.snapshots) do
    for key in pairs(sn.members) do s.players[key] = true end
  end
  SESSIONS[id] = s
end

-- Week 1, Gruul. Ana is perfect. Beto arrives after the first snapshot. Caio
-- leaves before the last. Dora is there throughout with nothing to drink.
night(T, { snapshots = {
  snap(T,          { ["Ana-Firemaw"] = who("Ana", true, true),
                     ["Caio-Firemaw"] = who("Caio", true, true),
                     ["Dora-Firemaw"] = who("Dora", true, false) }),
  snap(T + HOUR,   { ["Ana-Firemaw"] = who("Ana", true, true),
                     ["Beto-Firemaw"] = who("Beto", true, true),
                     ["Caio-Firemaw"] = who("Caio", true, true),
                     ["Dora-Firemaw"] = who("Dora", true, false) }),
  snap(T + 2*HOUR, { ["Ana-Firemaw"] = who("Ana", true, true),
                     ["Beto-Firemaw"] = who("Beto", true, true),
                     ["Dora-Firemaw"] = who("Dora", true, false) }),
} })

-- The same evening, Magtheridon. A different lockout, so a second chance.
night(T + 5 * HOUR, { instanceID = 544, name = "Magtheridon", snapshots = {
  snap(T + 5*HOUR, { ["Ana-Firemaw"] = who("Ana", true, true) }),
} })

-- Week 2, Gruul, recorded by two officers. One chance, and Beto appears only in
-- the second recording — which still has to count as the whole lockout.
night(T + WEEK, { startTime = T + WEEK, snapshots = {
  snap(T + WEEK,        { ["Ana-Firemaw"] = who("Ana", true, true) }),
  snap(T + WEEK + HOUR, { ["Ana-Firemaw"] = who("Ana", true, true) }),
} })
night(T + WEEK + 60, { startTime = T + WEEK + 60, snapshots = {
  snap(T + WEEK + 60,  { ["Beto-Firemaw"] = who("Beto", true, true) }),
} })

-- Week 2 again, Gruul again, two days later. Same lockout as above: a mop-up is
-- not another chance to have turned up.
night(T + WEEK + 2 * DAY, { startTime = T + WEEK + 2 * DAY, snapshots = {
  snap(T + WEEK + 2*DAY, { ["Caio-Firemaw"] = who("Caio", true, true) }),
} })

-- A ten-man. Nobody's denominator moves, but it is what makes Elis belong to
-- Core 2 rather than to the main core.
night(T + WEEK + 3 * DAY, { instanceID = 532, name = "Karazhan", groupTag = "Core 2",
  startTime = T + WEEK + 3 * DAY, snapshots = {
  snap(T + WEEK + 3*DAY, { ["Elis-Firemaw"] = who("Elis", true, true) }),
} })

-- Core 2's own 25, with its own weights: leaving early costs 5 there, not 10.
night(T + 2 * WEEK, { groupTag = "Core 2", startTime = T + 2 * WEEK, snapshots = {
  snap(T + 2*WEEK,        { ["Elis-Firemaw"] = who("Elis", true, false),
                            ["Ana-Firemaw"] = who("Ana", true, true) }),
  snap(T + 2*WEEK + HOUR, { ["Elis-Firemaw"] = who("Elis", true, false) }),
} })

-- An alt run somebody marked as not a guild raid. It counts for nothing.
night(T + 3 * WEEK, { isGuildRaid = false, startTime = T + 3 * WEEK, snapshots = {
  snap(T + 3*WEEK, { ["Fantasma-Firemaw"] = who("Fantasma", true, true) }),
} })

-- A night that arrived from another officer. The broadcast carries `players` and
-- leaves the frames behind, so this is what an exporter holds for every night they
-- did not personally record — and it is most of them. The addon scores it whole
-- because its late and left-early guards have no frame to check against.
SESSIONS[T + 4 * WEEK] = {
  instanceID = 565, name = "Gruul's Lair", groupTag = "", startTime = T + 4 * WEEK,
  endTime = T + 4 * WEEK + 4 * HOUR, encounters = {}, snapshots = {},
  players = { ["Ana-Firemaw"] = true, ["Ouvida-Firemaw"] = true },
}

-- And the mixed case: one officer's frames merged with both officers' people. Whoever
-- only the peer knew about is in `players` and in no frame, which the game reads as
-- absent from the first and from the last.
night(T + 5 * WEEK, { startTime = T + 5 * WEEK, snapshots = {
  snap(T + 5*WEEK,        { ["Ana-Firemaw"] = who("Ana", true, true) }),
  snap(T + 5*WEEK + HOUR, { ["Ana-Firemaw"] = who("Ana", true, true) }),
} })
SESSIONS[T + 5 * WEEK].players["Mesclada-Firemaw"] = true

BRutus.db = { raidTracker = { sessions = SESSIONS, attendance = {}, deletedSessions = {} } }
RT:RebuildAttendanceFromSessions()

----------------------------------------------------------------------
-- Out, as JSON the website can read without a parser of its own
----------------------------------------------------------------------
local function q(s) return '"' .. tostring(s):gsub('"', '\\"') .. '"' end

local keys = {}
for _, s in pairs(SESSIONS) do
  for key in pairs(s.players) do keys[key] = true end
end
local names = {}
for key in pairs(keys) do names[#names + 1] = key end
table.sort(names)

local out = { "{" }

-- The nights, in the shape CompanionExport puts on the wire.
out[#out + 1] = '"sessions":['
local ids = {}
for id in pairs(SESSIONS) do ids[#ids + 1] = id end
table.sort(ids)
for i, id in ipairs(ids) do
  local s = SESSIONS[id]
  local players = {}
  local pkeys = {}
  for key in pairs(s.players) do pkeys[#pkeys + 1] = key end
  table.sort(pkeys)
  for _, key in ipairs(pkeys) do
    local n, first, last, hits = 0, nil, nil, 0
    for _, sn in ipairs(s.snapshots) do
      local m = sn.members[key]
      if m then
        n = n + 1
        first = first or sn.time
        last = sn.time
        if m.hasConsumes then hits = hits + 1 end
      end
    end
    -- Same rule CompanionExport uses: somebody in `players` and in no frame travels
    -- with a count of zero, stamped at the session's start. The zero is the signal.
    players[#players + 1] = string.format(
      '{"key":%s,"snapshots":%d,"first":%d,"last":%d,"chits":%d}',
      q(key), n, first or s.startTime, last or s.startTime, hits)
  end
  out[#out + 1] = string.format(
    '{"instanceID":%d,"groupTag":%s,"guildRaid":%s,"startTime":%d,"players":[%s]}%s',
    s.instanceID, q(s.groupTag), (s.isGuildRaid == false) and "false" or "true",
    s.startTime, table.concat(players, ","), (i < #ids) and "," or "")
end
out[#out + 1] = "],"

-- The weights, as the payload carries them.
out[#out + 1] = '"rules":{'
local tags = {}
for tag in pairs(RULES) do tags[#tags + 1] = tag end
table.sort(tags)
for i, tag in ipairs(tags) do
  local p = RULES[tag]
  out[#out + 1] = string.format('%s:{"late":%d,"early":%d,"dry":%d}%s',
    q(tag), p.LATE, p.LEFT_EARLY, p.NO_CONSUMES, (i < #tags) and "," or "")
end
out[#out + 1] = "},"

-- And what the game shows for each of them.
out[#out + 1] = '"expected":{'
for i, key in ipairs(names) do
  out[#out + 1] = string.format("%s:%d%s", q(key),
    RT:GetAttendance25ManPercent(key), (i < #names) and "," or "")
end
out[#out + 1] = "}}"

io.write(table.concat(out))
