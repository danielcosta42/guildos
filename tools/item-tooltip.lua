-- The item-tooltip setting (issue #39), run against the real Core/Core.lua:
-- the guild's lines go on an item tooltip always, only with Shift held, or
-- never, and a link clicked in chat counts as asked for.
--
--   luajit -e 'ADDON="."' tools/item-tooltip.lua
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

-- ── The client Core.lua needs while it loads ────────────────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")

local shift = false
function IsShiftKeyDown() return shift end
GameTooltip, ItemRefTooltip = {}, {}

local function shows(mode, tooltip, held)
  BRutus.db = { settings = { itemTooltip = mode } }
  shift = held
  return BRutus:ShowsItemTooltipInfo(tooltip)
end

check(shows(nil, GameTooltip, false), "a saved setting from before #39 (no key) keeps the lines, as they always were")
check(shows("always", GameTooltip, false), "always shows without Shift")
check(not shows("shift", GameTooltip, false), "shift hides the lines while Shift is up")
check(shows("shift", GameTooltip, true), "shift shows the lines while Shift is held")
check(shows("shift", ItemRefTooltip, false), "a link clicked in chat shows the lines without Shift")
check(not shows("off", GameTooltip, true), "off hides the lines even with Shift held")
check(not shows("off", ItemRefTooltip, false), "off hides them on a clicked link too")

print(("item-tooltip: %d checks passed"):format(checks))
