-- The tab rule's overflow (issue #14), run against the real UI/Layout.lua.
--
-- Tabs that do not fit collapse into one "»n" control, never into icons, and
-- the active tab never disappears into the menu. This pins the arithmetic at
-- its edges: the exact fit, one pixel over, the gaps, the room "»n" takes, and
-- an active tab that has to push others out to stay visible.
--
--   luajit -e 'ADDON="."' tools/layout-tabs.lua
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

BRutus = { UI = {} }
dofile(ADDON .. "/UI/Layout.lua")
local UI = BRutus.UI

local function same(list, expect)
  if #list ~= #expect then return false end
  for i = 1, #list do if list[i] ~= expect[i] then return false end end
  return true
end
local function fit(...)
  local v, hidden = UI:FitTabs(...)
  return v, hidden
end

-- Five tabs of 60px, gaps of 2px: 5*60 + 4*2 = 308px in all. "»n" is 30px.
local W = { 60, 60, 60, 60, 60 }

-- ── Everything fits ─────────────────────────────────────────────────────
local v, hidden = fit(W, 308, 2, 30)
check(same(v, { 1, 2, 3, 4, 5 }) and hidden == 0, "at exactly 308px all five tabs show and nothing overflows")
v, hidden = fit(W, 500, 2, 30)
check(same(v, { 1, 2, 3, 4, 5 }) and hidden == 0, "with room to spare all five show")
v, hidden = fit({}, 100, 2, 30)
check(#v == 0 and hidden == 0, "no tabs, nothing to fit")

-- ── One pixel short: "»n" takes its room ────────────────────────────────
-- 307px: budget = 307 - 30 - 2 = 275; tabs 60, +62, +62, +62 = 246 fits four? 246 <= 275, fifth would be 308.
v, hidden = fit(W, 307, 2, 30)
check(same(v, { 1, 2, 3, 4 }) and hidden == 1, "one pixel short of everything: four tabs and »1")
-- budget exactly 246 -> four tabs; 245 -> three.
v, hidden = fit(W, 246 + 30 + 2, 2, 30)
check(same(v, { 1, 2, 3, 4 }) and hidden == 1, "a budget of exactly four tabs keeps four")
v, hidden = fit(W, 245 + 30 + 2, 2, 30)
check(same(v, { 1, 2, 3 }) and hidden == 2, "one pixel less and the fourth goes into »2")
v, hidden = fit(W, 60 + 30 + 2, 2, 30)
check(same(v, { 1 }) and hidden == 4, "room for one tab and »4")
v, hidden = fit(W, 59 + 30 + 2, 2, 30)
check(#v == 0 and hidden == 5, "no room for a whole tab: everything in »5, nothing squeezed")

-- The gap counts: without gaps five 60px tabs fit in 300px.
v, hidden = fit(W, 300, 0, 30)
check(same(v, { 1, 2, 3, 4, 5 }) and hidden == 0, "with no gap 300px holds all five")
v, hidden = fit(W, 300, 2, 30)
check(hidden > 0, "with 2px gaps 300px does not")

-- ── The active tab stays visible ────────────────────────────────────────
v, hidden = fit(W, 245 + 30 + 2, 2, 30, 2)
check(same(v, { 1, 2, 3 }) and hidden == 2, "an active tab that already shows changes nothing")
v, hidden = fit(W, 245 + 30 + 2, 2, 30, 5)
check(same(v, { 1, 2, 5 }) and hidden == 2, "an overflowing active tab takes the last visible slot")
local NARROW_LAST = { 60, 60, 60, 100, 20 }
v, hidden = fit(NARROW_LAST, 206 + 30 + 2, 2, 30, 5)
check(same(v, { 1, 2, 3, 5 }) and hidden == 1, "a narrow active tab that fits after the visible ones pushes nothing out")
local WIDE = { 60, 60, 60, 60, 150 }
v, hidden = fit(WIDE, 245 + 30 + 2, 2, 30, 5)
check(same(v, { 1, 5 }) and hidden == 3, "a wide active tab pushes out as many tabs as it needs")
v, hidden = fit({ 60, 60, 300 }, 150, 2, 30, 3)
check(same(v, { 1 }) and hidden == 2, "an active tab wider than the whole rule cannot show; the tab that fit stays")
v, hidden = fit(W, 60 + 30 + 2, 2, 30, 4)
check(same(v, { 4 }) and hidden == 4, "with room for one tab, that one is the active tab")
v, hidden = fit(W, 307, 2, 30, 9)
check(same(v, { 1, 2, 3, 4 }) and hidden == 1, "an active index outside the list is ignored")

print(("layout-tabs: %d checks passed"):format(checks))
