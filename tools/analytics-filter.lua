-- Guild Analytics' "Max level only" filter (issue #137), run against the real
-- Modules/GuildAnalytics.lua. The cap is the game's (GuildOS.Client.maxLevel).
--
--   luajit -e 'ADDON="."' tools/analytics-filter.lua
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

GuildOS = { Client = { maxLevel = 60 }, L = setmetatable({}, { __index = function(_, k) return k end }) }
dofile(ADDON .. "/Modules/GuildAnalytics.lua")
local A = GuildOS.GuildAnalytics

local roster = {
  { class = "MAGE", level = 60, online = true },
  { class = "MAGE", level = 60, online = false },
  { class = "MAGE", level = 42, online = true },
  { class = "ROGUE", level = 59, online = true },
  { class = "ROGUE" },   -- a roster row with no level is not at the cap
}

local out, total = A:Distribution("class", false, roster, true)
check(total == 2 and #out == 1 and out[1].label == "MAGE" and out[1].count == 2, "max level only counts the cap and nobody under it")
check(math.abs(out[1].pct - 100) < 0.01, "and the percentages are of who is left")
_, total = A:Distribution("class", true, roster, true)
check(total == 1, "with online only too: at the cap and online")
_, total = A:Distribution("class", false, roster)
check(total == 5, "without it, everybody, as before")
_, total = A:Distribution("class", true, roster)
check(total == 3, "and online only alone is unchanged")
GuildOS.Client.maxLevel = 70
_, total = A:Distribution("class", false, roster, true)
check(total == 0, "the cap is the game's: nobody at 70 here")

print(("analytics-filter: %d checks passed"):format(checks))
