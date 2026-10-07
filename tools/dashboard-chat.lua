-- The Now cards' guild chat (issue #126), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Data.lua and UI/Dashboard.lua on a stubbed UI.
--
-- The big card under the others was "Guild activity", which repeated the Activity column beside
-- it and stood mostly empty. It is the guild's chat now: the feed Guild > Chat shows, /g alone,
-- with its box, and the arrow opens Guild > Chat.
--
--   luajit -e 'ADDON="."' tools/dashboard-chat.lua
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

-- Frames remember their parent and scripts; any other method answers a number where the layout
-- does arithmetic and a sink everywhere else.
local NUM = { GetWidth = 900, GetHeight = 600, GetFrameLevel = 1, GetStringHeight = 12, GetStringWidth = 40 }
local sink
sink = setmetatable({}, { __index = function(_, k)
  if NUM[k] then return function() return NUM[k] end end
  if k == "GetChildren" or k == "GetRegions" then return function() end end
  return function() return sink end
end })
local frames = {}
local function newFrame(parent)
  local f = { parent = parent, scripts = {} }
  frames[#frames + 1] = f
  return setmetatable(f, { __index = function(_, k)
    if NUM[k] then return function() return NUM[k] end end
    if k == "SetScript" or k == "HookScript" then return function(self, n, fn) self.scripts[n] = fn end end
    if k == "SetTextColor" then return function(self, r, g, b) self.color = { r, g, b } end end
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    return function() return sink end
  end })
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame(_, _, parent) return newFrame(parent) end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70245", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function GetNumGuildMembers() return 0, 0 end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Rank", 5 end
function GetServerTime() return 1000 end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Utils.lua")
local titles, opened = {}, nil
GuildOS.UI = setmetatable({
  GetFeature = function() return nil end,
  CreateDarkPanel = function(_, parent) return newFrame(parent) end,
  CreateHeaderText = function(_, card, title) card.title = title; titles[#titles + 1] = title; return sink end,
  CreateText = function(_, parent, t) local fs = newFrame(parent); fs.text = t; return fs end,
  CreateButton = function(_, parent, t) local b = newFrame(parent); b.text = t; return b end,
  OpenWindow = function(_, tab, sub) opened = { tab, sub } end,
}, { __index = function() return function() return sink end end })
dofile(ADDON .. "/UI/Dashboard.lua")

-- The feed itself is Guild > Chat's, tested in tools/window-shell.lua: here only how the card uses it.
local built, refreshed = {}, 0
function GuildOS:CreateGuildChatFeed(parent, opts)
  built[#built + 1] = { parent = parent, opts = opts }
  return function() refreshed = refreshed + 1 end
end

GuildOS.db = { settings = { modules = {} } }
local panel = newFrame()
local refresh = GuildOS:CreateDashboardPanel(panel)
check(pcall(refresh) and pcall(refresh), "the Now cards draw, twice")

local card
for _, f in ipairs(frames) do if f.title == "GUILD CHAT" then card = f end end
local has = {}
for _, t in ipairs(titles) do has[t] = true end
check(card ~= nil and not has["GUILD ACTIVITY"], "the big card is the guild's chat; the activity it repeated is gone")
check(#built == 1 and built[1].parent == card.body, "its body holds the chat feed, built once")
check(not (built[1].opts and built[1].opts.streams), "with /g alone: the channel tabs are Guild > Chat's")
check(refreshed == 2, "and drawn again with the rest of the cards")
check(card.scripts.OnMouseUp == nil, "a click in the chat (a link, the box) stays in it")
local arrow
for _, f in ipairs(frames) do
  if f.parent == card and f.scripts.OnClick then arrow = f end
end
check(arrow ~= nil, "the arrow is a button")
arrow.scripts.OnClick(arrow)
check(opened and opened[1] == "guild" and opened[2] == "chat", "that opens Guild > Chat")
local glyph
for _, f in ipairs(frames) do if f.parent == card and f.text == ">" then glyph = f end end
local C = GuildOS.Colors
arrow.scripts.OnEnter(arrow)
check(glyph and glyph.color[1] == C.gold.r and glyph.color[3] == C.gold.b, "and lights up under the mouse, as a card does")
arrow.scripts.OnLeave(arrow)
check(glyph.color[1] == C.silver.r, "and dims when it leaves")

print(string.format("dashboard-chat: %d checks passed", checks))
