-- The resize ladder (issue #14), run against the real UI/Layout.lua.
--
-- One window reorganises its content by width through seven bands. A band
-- that flips back and forth while the edge is dragged across a threshold is
-- the failure this guards against, so every threshold is tested one pixel
-- inside and at the hysteresis, in both directions, plus the jumps a fast
-- drag makes across several bands at once.
--
--   luajit -e 'ADDON="."' tools/layout-ladder.lua
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
local L, H = UI.LADDER, UI.LADDER_HYSTERESIS

-- ── The table matches the handoff ───────────────────────────────────────
local NAMES = { "full", "wide", "medium", "compact", "narrow", "watch", "bar" }
local MINS  = { 880, 780, 700, 600, 520, 420, 0 }
check(#L == 7 and H == 16, "seven bands, 16px hysteresis")
for i = 1, 7 do
  check(L[i].name == NAMES[i] and L[i].min == MINS[i], "band " .. i .. " is " .. NAMES[i] .. " from " .. MINS[i] .. "px")
end

-- ── Plain thresholds when nothing is shown yet ──────────────────────────
check(UI:ResolveBand(1000) == "full" and UI:ResolveBand(320) == "bar", "the default and the smallest width")
for i = 1, 6 do
  check(UI:ResolveBand(MINS[i]) == NAMES[i], MINS[i] .. "px is " .. NAMES[i])
  check(UI:ResolveBand(MINS[i] - 1) == NAMES[i + 1], (MINS[i] - 1) .. "px is " .. NAMES[i + 1])
end
check(UI:ResolveBand(0) == "bar" and UI:ResolveBand(nil) == "bar", "no width reads as the bar")
check(UI:ResolveBand(700, "no-such-band") == "medium", "an unknown current band reads as none")

-- ── Hysteresis at every threshold, both ways ────────────────────────────
for i = 1, 6 do
  local t, above, below = MINS[i], NAMES[i], NAMES[i + 1]
  -- Growing from the band below.
  check(UI:ResolveBand(t, below) == below, below .. " stays " .. below .. " at the " .. t .. "px threshold")
  check(UI:ResolveBand(t + H - 1, below) == below, below .. " stays " .. below .. " at " .. (t + H - 1) .. "px")
  check(UI:ResolveBand(t + H, below) == above, below .. " becomes " .. above .. " at " .. (t + H) .. "px")
  -- Shrinking from the band above.
  if t - H >= 0 then
    check(UI:ResolveBand(t - 1, above) == above, above .. " stays " .. above .. " just under " .. t .. "px")
    check(UI:ResolveBand(t - H, above) == above, above .. " stays " .. above .. " at " .. (t - H) .. "px")
    check(UI:ResolveBand(t - H - 1, above) == below, above .. " becomes " .. below .. " at " .. (t - H - 1) .. "px")
  end
end
check(UI:ResolveBand(400, "bar") == "bar", "the bar stays the bar inside its band")
check(UI:ResolveBand(0, "bar") == "bar", "nothing is below the bar")

-- ── A fast drag across several bands ────────────────────────────────────
check(UI:ResolveBand(400, "full") == "bar", "full dragged to 400px lands on the bar")
check(UI:ResolveBand(1000, "bar") == "full", "the bar dragged to 1000px lands on full")
check(UI:ResolveBand(690, "full") == "medium", "full dragged to 690px stops at medium: 690 is not 16px below 700")
check(UI:ResolveBand(683, "full") == "compact", "full dragged to 683px reaches compact")
check(UI:ResolveBand(716, "bar") == "medium", "the bar dragged to 716px climbs to medium, the last band it clears by 16px")

-- ── Dragging back and forth never flickers ──────────────────────────────
local band, flips = "full", 0
for _, w in ipairs({ 881, 879, 870, 866, 865, 864, 863, 870, 880, 890, 895, 896, 890, 870 }) do
  local nextBand = UI:ResolveBand(w, band)
  if nextBand ~= band then flips = flips + 1 end
  band = nextBand
end
check(flips == 2 and band == "full", "wobbling around 880px changes the band once each way, not on every pixel")

print(("layout-ladder: %d checks passed"):format(checks))
