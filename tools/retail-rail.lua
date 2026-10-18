-- The roster rail's class chips on retail (issue #166), run against the real UI/Layout.lua.
--
-- The rail is 156 wide and the chips grow upward from its bottom under the rank list, five rows tall.
-- Nine classes fit two to a row; retail's thirteen would need seven rows of two, and the last three
-- chips were drawn below the rail. The grid takes a third column instead, so it stays five rows tall
-- and every chip stays on the rail.
--
--   luajit -e 'ADDON="."' tools/retail-rail.lua
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

GuildOS = { UI = {}, SelfTest = { Register = function() end } }
dofile(ADDON .. "/UI/Layout.lua")
local UI = GuildOS.UI

local RAIL_BTN_W, GAP, MAX_ROWS = 138, 6, 5
local g = UI:ChipGrid(9, RAIL_BTN_W, GAP, MAX_ROWS)
check(g.cols == 2 and g.rows == 5 and g.w == 66, "nine classes keep two to a row, five rows, as before")
g = UI:ChipGrid(13, RAIL_BTN_W, GAP, MAX_ROWS)
check(g.rows <= MAX_ROWS, "thirteen classes stay within five rows (" .. g.rows .. ")")
check(g.cols == 3 and g.w * g.cols + GAP * (g.cols - 1) <= RAIL_BTN_W, "in three columns that fit the rail")
check(g.w >= 40, "each chip still holds its icon and a count (" .. g.w .. ")")
for idx = 1, 13 do
  local col, row = g:Cell(idx)
  check(col >= 0 and col < g.cols and row >= 0 and row < g.rows, "chip " .. idx .. " is inside the grid")
end
check(select(2, g:Cell(13)) == 4 and select(2, g:Cell(1)) == 0, "the first chip is on the top row, the last on the bottom")

local roster = io.open(ADDON .. "/UI/RosterFrame.lua", "rb"):read("*a")
check(roster:find("UI:ChipGrid(#CLASS_ORDER", 1, true) ~= nil, "the roster rail lays its chips out with the grid")

print(("retail-rail: %d checks passed"):format(checks))
