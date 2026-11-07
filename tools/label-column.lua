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

print("label-column: " .. checks .. " checks passed")
