-- The officers' Engagement tab, run against the real UI/ManagementPanel.lua with generic frame stubs.
--
-- "1426x stack overflow" in ManagementPanel.lua:96 (7/11): every member's self-report repaints the tab,
-- and each repaint made a new frame per member and only hid the old ones. In a big guild the content
-- grew to thousands of frames, until `{ content:GetChildren() }` blew the Lua stack on every report.
-- The rows are reused now, and nothing is drawn while the tab is off screen.
--
--   luajit -e 'ADDON="."' tools/engagement-panel.lua
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

-- A frame that takes any call. Children are kept per parent, the way GetChildren reads them.
local created, visible = 0, true
local Frame = {}
Frame.__index = function(_, k)
  return Frame[k] or function(self) return self end
end
function Frame.new(parent)
  created = created + 1
  local f = setmetatable({ children = {}, shown = true, label = nil }, Frame)
  if parent and parent.children then parent.children[#parent.children + 1] = f end
  return f
end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetWidth() return 600 end
function Frame:GetHeight() return 400 end
function Frame:GetStringWidth() return 40 end
function Frame:IsVisible() return visible end
function Frame:IsShown() return self.shown end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:CreateTexture() return setmetatable({ children = {} }, Frame) end
function Frame:CreateFontString() return setmetatable({ children = {} }, Frame) end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function CreateFrame(_, _, parent) return Frame.new(parent) end
function time() return 1794000000 end
format = string.format
StaticPopupDialogs = {}
function StaticPopup_Show() end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function GuildControlGetNumRanks() return 5 end
function GuildControlGetRankName(i) return "Rank" .. i end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetServerTime() return 1794000000 end
function date(...) return os.date(...) end

GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end }),
}
-- Every UI helper hands back a frame (a button carries a label); the panel only draws through them.
GuildOS.UI = setmetatable({}, { __index = function()
  return function(_, parent)
    local f = Frame.new(type(parent) == "table" and parent or nil)
    f.label = setmetatable({ children = {} }, Frame)
    f.checkbox = setmetatable({ children = {} }, Frame)
    f.text = nil
    return f
  end
end })
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
function GuildOS:TimeAgo() return "now" end
function GuildOS:IsOfficer() return true end
-- Any other module the other tabs read while they are built: a table whose every method answers nothing.
local anything = setmetatable({}, { __index = function() return function() return nil end end, __call = function() return nil end })
setmetatable(GuildOS, { __index = function() return anything end })
GuildOS.db = { settings = {} }

local rows = {}
for i = 1, 40 do rows[i] = { name = "Member" .. i, posts7 = i, invites7 = 1, joins7 = 0, last = 1794000000 } end
GuildOS.RecruitEngagement = { GetAggregate = function()
  return { rows = rows, totals = { posts7 = 1, invites7 = 1, joins7 = 0, conv = 0, postsPrev = 0, invitesPrev = 0, joinsPrev = 0 } }
end }

dofile(ADDON .. "/UI/ManagementPanel.lua")
local parent = Frame.new(nil)
GuildOS:CreateManagementPanel(parent, nil)
local refresh = GuildOS.recruitEngagementRefresh
check(type(refresh) == "function", "the Engagement tab registers its repaint")

refresh()
local afterFirst = created
for _ = 1, 300 do refresh() end
check(created == afterFirst, "300 more reports reuse the rows: no new frames (" .. (created - afterFirst) .. " made)")

local engage = parent.subPanels.engage.panel
local function shownRows()
  local n = 0
  local function walk(f)
    for _, c in ipairs(f.children) do
      if rawget(c, "shown") and rawget(c, "nameFS") then n = n + 1 end
      walk(c)
    end
  end
  walk(engage)
  return n
end
check(shownRows() == 40, "every member has a row (" .. shownRows() .. ")")
for i = 31, 40 do rows[i] = nil end
refresh()
check(shownRows() == 30 and created == afterFirst, "fewer members: the extra rows hide, nothing new is made")

-- Off screen, a report draws nothing; showing the tab draws it.
visible = false
rows[1].name = "Renamed"
refresh()
local nameOf1
local function find(f)
  for _, c in ipairs(f.children) do
    local fs = rawget(c, "nameFS"); if fs and rawget(fs, "text") then nameOf1 = nameOf1 or fs.text end
    find(c)
  end
end
find(engage)
check(nameOf1 == "Member1", "a report while the tab is hidden draws nothing")
visible = true
parent.SelectSub("engage")
nameOf1 = nil
find(engage)
check(nameOf1 == "Renamed", "opening the tab draws what came in meanwhile")

print("engagement-panel: " .. checks .. " checks passed")
