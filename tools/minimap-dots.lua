-- Turning off the guildmates-in-your-zone dots on the minimap (issue #271), run against the real
-- Modules/GuildMap.lua. Until now they could not be turned off at all.
--
--   luajit -e 'ADDON="."' tools/minimap-dots.lua
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

LibStub = function() return {} end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), db = {} }
dofile(ADDON .. "/Modules/GuildMap.lua")
local GM = GuildOS.GuildMap

check(GM:IsMinimapDots() == true, "on by default, as it always was")
local redrawn = 0
GM.uiRefresh = function() redrawn = redrawn + 1 end
GM:SetMinimapDots(false)
check(GM:IsMinimapDots() == false and GuildOS.db.guildMapPrefs.minimapDots == false, "turned off and kept")
check(redrawn == 1, "and the minimap redraws at once, no /reload")
GM:SetMinimapDots(true)
check(GM:IsMinimapDots() == true and redrawn == 2, "and back on")
GuildOS.db = {}
check(GM:IsMinimapDots() == true, "a character that never chose sees them")

print("minimap-dots: " .. checks .. " checks passed")
