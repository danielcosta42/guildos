-- Where the controls of a labelled form start (issue #265), against the real UI/Helpers.lua.
--
-- The recruiting screen put every control at x = 140 whatever its label said, so "Membres qui
-- aident :" in French ran over its button. The column now starts after the widest label, and never
-- before where it always was.
--
--   luajit -e 'ADDON="."' tools/label-column.lua
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

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), Colors = setmetatable({}, {
  __index = function() return { r = 0, g = 0, b = 0, a = 1 } end }) }
dofile(ADDON .. "/UI/Helpers.lua")
local UI = GuildOS.UI

check(UI.LabelColumn({ 40, 72, 55 }, 30, 12, 140) == 140, "short labels keep the column where it was")
check(UI.LabelColumn({ 40, 131.6, 55 }, 30, 12, 140) == 174, "a long label pushes it past itself, rounded up")
check(UI.LabelColumn({}, 30, 12, 140) == 140, "no labels: the floor")
check(UI.ReserveFor({ GetWidth = function() return 84 end }, 6) == 90, "a box leaves room for its own Save button")
check(UI.ReserveFor(nil, 6) == 6, "and only the gap when there is none")

-- The gap under "Autre canal" in the same screenshot: two rows of chips were always reserved, shown or
-- not. The rows below now sit under the chips actually shown.
check(UI.ChipRowsHeight(0, 3, 26) == 0, "no chip: no room kept")
check(UI.ChipRowsHeight(2, 3, 26) == 30, "one row of chips")
check(UI.ChipRowsHeight(4, 3, 26) == 56, "two rows, as the screen always kept before")
local stack = io.open(ADDON .. "/UI/RosterFrame.lua", "rb"):read("*a")
check(not stack:find("math.ceil(CUSTOM_MAX / CUSTOM_PER_ROW) * 26", 1, true), "the recruiting screen no longer keeps the most chips possible")
check(stack:find("chanHint:SetShown(shown > 0)", 1, true), "\"click a channel below\" shows only with a channel below")

print("label-column: " .. checks .. " checks passed")
