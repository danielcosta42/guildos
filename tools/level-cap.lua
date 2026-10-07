-- The level cap (issue #53), run against the real Core/Core.lua, Core/Compat.lua and the
-- modules that read it, once as TBC Anniversary and once as WoW: Forever.
--
-- Forever stops at 60. Every "top level" check said 70, so a Forever guild of 60s had no
-- raid-ready members on the dashboard, no ding, and a top level bracket nobody reached.
--
--   luajit -e 'ADDON="."' tools/level-cap.lua
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

-- ── The client the files need while they load ───────────────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}

local function load(game)
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70124", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Modules/GuildAnalytics.lua")
  dofile(ADDON .. "/Modules/Milestones.lua")
  dofile(ADDON .. "/Modules/RecruitScanner.lua")
  GuildOS.db = { milestones = { events = {} } }
  return GuildOS
end

for game, cap in pairs({ anniversary = 70, forever = 60 }) do
  local B = load(game)
  check(B.Client.maxLevel == cap, game .. ": the cap is " .. cap)

  -- The top bracket is the cap; one below it is the decade it sits in.
  check(B.GuildAnalytics:_LevelBracket(cap) == tostring(cap), game .. ": the cap is its own bracket")
  local below = cap - 5
  local lo = math.floor(below / 10) * 10
  check(B.GuildAnalytics:_LevelBracket(below) == lo .. "-" .. (lo + 9), game .. ": below the cap is a decade")

  -- A ding at the cap is a milestone; a level under it is not.
  B.Milestones:Check("A-Realm", { name = "A", level = cap }, cap - 1, nil, true)
  local ev = B.db.milestones.events[1]
  check(ev and ev.type == "ding" and ev.detail == tostring(cap), game .. ": reaching the cap is a ding")
  B.Milestones:Check("B-Realm", { name = "B", level = cap - 1 }, cap - 2, nil, true)
  check(#B.db.milestones.events == 1, game .. ": a level under the cap is not")

  -- The recruit scan stops at the cap.
  check(B.RecruitScanner.DEFAULTS.maxLevel == cap, game .. ": the scan's default top level is the cap")
end

print(("level-cap: %d checks passed"):format(checks))
