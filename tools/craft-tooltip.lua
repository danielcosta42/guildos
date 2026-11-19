-- The short crafter list of an item tooltip (issue #389), run against the real
-- Modules/RecipeTracker.lua: with 900 members the list ran off the screen. At most three names:
-- the online crafters, or when nobody is online the offline ones seen most recently; the rest as
-- one count.
--
--   luajit -e 'ADDON="."' tools/craft-tooltip.lua
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

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
dofile(ADDON .. "/Modules/RecipeTracker.lua")
local RT = GuildOS.RecipeTracker

local function crafters(n)
  local out = {}
  for i = 1, n do out[i] = { playerName = string.format("M%03d", i), playerKey = "M" .. i } end
  return out
end
local function names(list)
  local out = {}
  for i, c in ipairs(list) do out[i] = c.playerName end
  return table.concat(out, ",")
end

-- 50 crafters, five online.
local list = crafters(50)
local presence = {}
for i = 1, 50 do presence[list[i].playerName] = { online = false, ago = 100 - i } end
for _, i in ipairs({ 40, 7, 22, 3, 31 }) do presence[list[i].playerName] = { online = true } end
local shown, rest, restOnline = RT.TooltipPick(list, presence)
check(#shown == 3, "at most three names, out of fifty")
check(names(shown) == "M003,M007,M022", "the online ones, by name: " .. names(shown))
check(rest == 47 and restOnline == 2, "the rest as a count, with how many of them are online")

-- Nobody online: the three seen most recently.
for i = 1, 50 do presence[list[i].playerName] = { online = false, ago = (i * 7) % 50 } end
presence["M010"] = { online = false }   -- never seen: last
shown, rest, restOnline = RT.TooltipPick(list, presence)
check(#shown == 3 and rest == 47 and restOnline == 0, "three offline names, the rest counted")
check(names(shown) == "M050,M043,M036", "the offline ones seen most recently first: " .. names(shown))

-- A short list shows whole, the order kept to the rule.
shown, rest = RT.TooltipPick(crafters(2), { M001 = { online = false, ago = 5 }, M002 = { online = true } })
check(#shown == 1 and shown[1].playerName == "M002" and rest == 1, "the online one shown, the offline one counted")
shown, rest = RT.TooltipPick(crafters(2), {})
check(#shown == 2 and rest == 0 and names(shown) == "M001,M002", "unknown presence: by name, nothing left out")
shown, rest = RT.TooltipPick({}, {})
check(#shown == 0 and rest == 0, "no crafters, nothing to show")
shown = RT.TooltipPick(crafters(10), {}, 5)
check(#shown == 5, "the limit can be asked for")

-- The roster is read at most every ten seconds, whichever tooltip asks.
local CLOCK, reads = 100, 0
function GetTime() return CLOCK end
function GetNumGuildMembers() reads = reads + 1; return 2 end
function GetGuildRosterInfo(i) return ({ "Ana-Realm", "Bea-Realm" })[i], nil, nil, nil, nil, nil, nil, nil, i == 1 end
function GetGuildRosterLastOnline() return 0, 0, 2, 3 end
local p = RT:GetPresence()
check(p.Ana.online and not p.Bea.online and p.Bea.ago == 51, "online, and the others' hours since seen")
RT:GetPresence(); CLOCK = 105; RT:GetPresence()
check(reads == 1, "read once within ten seconds")
CLOCK = 111; RT:GetPresence()
check(reads == 2, "and again after")

print(("craft-tooltip: %d checks passed"):format(checks))
