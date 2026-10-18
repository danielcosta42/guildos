-- The member list's columns, each reader's own (issue #178, spec
-- docs/superpowers/specs/2026-10-18-roster-columns-design.md), run against the real
-- Modules/RosterColumns.lua.
--
-- The default is the list as it always was; a column turned on goes to the end; Member is never in
-- the list; a column this reader cannot use is skipped but kept; and anything stored that is not a
-- list of keys reads as the default.
--
--   luajit -e 'ADDON="."' tools/roster-columns.lua
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

GuildOS, GuildOSDB = {}, {}
dofile(ADDON .. "/Modules/RosterColumns.lua")
local RC = GuildOS.RosterColumns

local OFFERED = { level = true, class = true, avgIlvl = true, race = true, lastSeen = true,
                  professions = true, zone = true, note = true, rank = true, dkp = true }
local function all(k) return OFFERED[k] == true end
local function joined(offered) return table.concat(RC:Visible(offered or all), ",") end

-- ── The default is the list as it always was ────────────────────────────
local DEFAULT = "level,class,avgIlvl,race,lastSeen,professions,zone"
check(joined() == DEFAULT, "nothing stored reads as the old eight, Member aside")
check(GuildOSDB.rosterColumns == nil, "reading writes nothing")

-- ── On goes to the end, off comes out ───────────────────────────────────
RC:SetShown("note", true)
check(joined() == DEFAULT .. ",note", "a column turned on is appended")
RC:SetShown("note", true)
check(joined() == DEFAULT .. ",note", "turning on a shown column changes nothing")
RC:SetShown("race", false)
check(joined() == "level,class,avgIlvl,lastSeen,professions,zone,note", "a column turned off is removed")
RC:SetShown("race", false)
check(joined() == "level,class,avgIlvl,lastSeen,professions,zone,note", "turning off a hidden one changes nothing")

-- ── Member is not the reader's to move or hide ──────────────────────────
RC:SetShown("name", true)
check(not joined():find("name"), "Member is never stored")

-- ── Moving ──────────────────────────────────────────────────────────────
RC:Move("note", -1, all)
check(joined() == "level,class,avgIlvl,lastSeen,professions,note,zone", "up one swaps with the one before")
RC:Move("level", -1, all)
check(joined() == "level,class,avgIlvl,lastSeen,professions,note,zone", "the first one does not go further up")
RC:Move("zone", 1, all)
check(joined() == "level,class,avgIlvl,lastSeen,professions,note,zone", "the last one does not go further down")
RC:Move("rank", -1, all)
check(joined() == "level,class,avgIlvl,lastSeen,professions,note,zone", "a hidden column has nowhere to move")

-- ── A column this reader cannot use is skipped, never forgotten ─────────
RC:SetShown("dkp", true)   -- level,class,avgIlvl,lastSeen,professions,note,zone,dkp
local noDkp = function(k) return k ~= "dkp" and all(k) end
check(joined(noDkp) == "level,class,avgIlvl,lastSeen,professions,note,zone", "a stored column not offered is skipped")
RC:Move("zone", 1, noDkp)
check(joined(noDkp) == "level,class,avgIlvl,lastSeen,professions,note,zone", "it is not a place to move to")
check(joined() == "level,class,avgIlvl,lastSeen,professions,note,zone,dkp", "and it is still there once offered")
RC:Move("note", 1, function(k) return k ~= "zone" and all(k) end)
check(joined() == "level,class,avgIlvl,lastSeen,professions,dkp,zone,note", "a move jumps over a column not offered")

-- ── Back to the default ─────────────────────────────────────────────────
RC:Reset()
check(GuildOSDB.rosterColumns == nil and joined() == DEFAULT, "Restore defaults forgets the choice")

-- ── What is stored is not trusted ───────────────────────────────────────
for what, v in pairs({ string = "level", number = 3, ["a list with a number"] = { "level", 7 } }) do
  GuildOSDB.rosterColumns = v
  check(joined() == DEFAULT, what .. " reads as the default")
end
GuildOSDB.rosterColumns = { "zone", "zone", "nope", "name", "level" }
check(joined() == "zone,level", "repeats, Member and unknown keys are dropped on the way out")
GuildOSDB.rosterColumns = {}
check(joined() == "", "an empty list is a choice: only Member")

print(("roster-columns: %d checks passed"):format(checks))
