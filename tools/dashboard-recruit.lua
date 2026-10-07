-- The home dashboard's recruitment card with the module switched off (issue #84), run against
-- the real Core/Core.lua, Core/Compat.lua, Core/Data.lua and UI/Dashboard.lua on a stubbed UI.
--
-- With Recruitment off in Settings, the card still said "Guild is recruiting" and offered a
-- green "Helping" button (or the officer's "Broadcast now") for popups that would never come.
--
--   luajit -e 'ADDON="."' tools/dashboard-recruit.lua
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

-- Any frame, any method: numbers where the layout does arithmetic, itself everywhere else.
local NUM = { GetWidth = 300, GetHeight = 120, GetFrameLevel = 1, GetStringHeight = 12, GetStringWidth = 40 }
local stub
stub = setmetatable({}, { __index = function(_, k)
  if NUM[k] then return function() return NUM[k] end end
  if k == "GetChildren" or k == "GetRegions" then return function() end end
  return function() return stub end
end })
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame() return stub end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function GetNumGuildMembers() return 0, 0 end
function IsInGuild() return true end
local myRank = 5
function GetGuildInfo() return "Guild", "Rank", myRank end
function GetServerTime() return 1000 end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Utils.lua")
local texts, buttons = {}, {}
GuildOS.UI = setmetatable({
  GetFeature = function() return nil end,   -- no registry: IsFeatureEnabled reads the settings alone
  CreateText = function(_, _, t) texts[#texts + 1] = tostring(t); return stub end,
  CreateButton = function(_, _, t) buttons[#buttons + 1] = tostring(t); return stub end,
}, { __index = function() return function() return stub end end })
dofile(ADDON .. "/UI/Dashboard.lua")

local function show(modules, rank, ad)
  myRank = rank
  GuildOS.db = { settings = { modules = modules } }
  if ad ~= false then GuildOS.db.guildRecruitment = { enabled = true, message = "We recruit" } end
  texts, buttons = {}, {}
  local refresh = GuildOS:CreateDashboardPanel(stub)
  local ok, err = pcall(refresh)
  check(ok, "the dashboard draws (" .. tostring(err) .. ")")
end
local function shown(list, text)
  for _, t in ipairs(list) do
    if t:find(text, 1, true) then return true end
  end
  return false
end

-- ── 1. Module on: the card as it was ────────────────────────────────────
show({}, 5)
check(shown(texts, "Guild is recruiting") and shown(buttons, "Helping"), "module on: a member sees the ad and the Helping button")
show({}, 0)
check(shown(texts, "Guild is recruiting") and shown(buttons, "Broadcast now"), "module on: an officer sees the ad and Broadcast now")

-- ── 2. Module off: says so, offers nothing ──────────────────────────────
for _, who in ipairs({ { 5, "a member" }, { 0, "an officer" } }) do
  show({ recruitment = false }, who[1])
  check(shown(texts, "The Recruitment module is off. Turn it on in Settings > General > Modules."),
    "module off: " .. who[2] .. " is told the module is off and where to turn it on")
  check(not shown(texts, "Guild is recruiting") and not shown(buttons, "Helping")
    and not shown(buttons, "Help spread it") and not shown(buttons, "Broadcast now"),
    "module off: " .. who[2] .. " gets no ad and no button for popups that will not come")
end

-- Module off and no ad either: still the module, not the hidden tab, is named.
show({ recruitment = false }, 0, false)
check(shown(texts, "The Recruitment module is off") and not shown(texts, "Set it up in the Recruitment tab"),
  "module off with no ad: an officer is pointed at Settings, not at the tab the switch hid")

print(("dashboard-recruit: %d checks passed"):format(checks))
