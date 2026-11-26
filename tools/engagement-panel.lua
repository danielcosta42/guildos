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
    f.edit = setmetatable({ children = {} }, Frame)   -- a text area's field (UI:CreateTextArea)
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

dofile(ADDON .. "/UI/Spacing.lua"); rawset(GuildOS.UI, "SP", GuildOS.Spacing)   -- the spacing standard (#449)
dofile(ADDON .. "/UI/Forms.lua")
GuildOS.Forms = rawget(GuildOS, "Forms")
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

-- Leadership > Ranks (#371). Built row by row, a 943-member guild was a 26,000px scroll child the client
-- did not draw at all, and each roster update stacked another 943 frames on it (3,764 after four, seen in
-- game). Now only the rows that fit exist, refilled from the roster on every refresh and scroll.
local roster = {}
for i = 1, 943 do roster[i] = { "Member" .. i .. "-Realm", "Rank", 1, 60, nil, nil, nil, nil, true, nil, "MAGE" } end
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) return unpack(roster[i]) end
function GuildOS:GetClassColor() return 1, 1, 1 end
local fauxTotal, fauxShown
FauxScrollFrame_Update = function(_, total, shown) fauxTotal, fauxShown = total, shown end
FauxScrollFrame_GetOffset = function() return 0 end
FauxScrollFrame_OnVerticalScroll = function() end
function GuildOS:SafeCall(fn, ...) return true, fn(...) end   -- let a failing refresh raise here
local beforeRanks = created
parent.SelectSub("ranks")
local firstRanks = created
for _ = 1, 4 do parent.SelectSub("ranks") end
check(created == firstRanks, "four more roster updates make no new frames (" .. (created - firstRanks) .. " made)")
check(firstRanks - beforeRanks < 200, "a 943-member guild gets the rows that fit, not one per member ("
  .. (firstRanks - beforeRanks) .. " frames)")
local named, firstName = 0, nil
local function scanRanks(f)
  for _, c in ipairs(f.children) do
    local fs = rawget(c, "nameFS")
    if fs and rawget(c, "shown") and rawget(fs, "text") then
      named = named + 1
      firstName = firstName or fs.text
    end
    scanRanks(c)
  end
end
scanRanks(parent.subPanels.ranks.panel)
check(fauxTotal == 943 and fauxShown == 14 and named == 14,
  "the list knows all 943 and fills the 14 rows a 400px list holds (" .. named .. ")")
check(firstName == "Member1", "sorted by rank, then name")

-- Leadership > MOTD on WoW: Forever (#377): an addon's GuildSetMOTD is forbidden there, so the field only
-- shows the message and its button opens the game's guild panel, saying why.
function Frame:Disable() self.disabled = true end
function Frame:Enable() self.disabled = false end
local viaGame = true
GuildOS.GuildManager = {
  GetMOTD = function() return "Raid at 8" end, GetGuildInfo = function() return "" end,
  CanSetMOTD = function() return true end, CanSetGuildInfo = function() return true end,
  MOTDNeedsGamePanel = function() return viaGame end,
}
parent.SelectSub("motd")
local motdPanel = parent.subPanels.motd.panel
local motdArea, motdBtn, motdNote = motdPanel.motdArea, motdPanel.motdBtn, motdPanel.motdNote
check(motdArea.edit.disabled and motdBtn.label.text == "Edit in guild panel" and motdBtn.shown
  and motdNote.text == "On WoW: Forever only the game's guild panel can change the message of the day.",
  "on WoW: Forever the MOTD field only shows it, its button opens the game's panel and the note says why")
viaGame = false
parent.SelectSub("motd")
check(not motdArea.edit.disabled and motdBtn.label.text == "Save MOTD" and motdNote.text == "",
  "elsewhere the field is edited and saved from the addon")

-- Officers' Room > Ban list (audit M3): every keystroke in its filter and every ban that syncs in repaints it, and
-- each repaint made a new row of frames per ban. The rows are reused now. Lifting asks first, and Share is
-- offered only for a ban in force while the guild has an alliance on guildos.me (audit B6, B7).
local bans = {}
for i = 1, 30 do bans[i] = { key = "ban" .. i, name = "Banned" .. i, reason = "r", author = "Off", ts = 1 } end
bans[30].expiry = 1   -- a temporary ban that ran out
local lifted, asked = {}, {}
local siteAlliance = false
GuildOS.BanList = {
  List = function() return bans end,
  AllianceBans = function() return nil end,
  StillInGuild = function() return {} end,
  IsShared = function() return false end,
  CanShare = function(_, key) return siteAlliance and key ~= "ban30" end,
  HasSiteAlliance = function() return siteAlliance end,
  ConfirmRemoveKey = function(_, key) asked[#asked + 1] = key end,
  RemoveKey = function(_, key) lifted[#lifted + 1] = key end,
}
GuildOS.BulkActions = { Collect = function() return {} end, Context = function() return {} end }
-- The stub frames answer an unset text with a function: an empty filter.
strtrim = strtrim or function(x) return type(x) == "string" and (x:gsub("^%s+", ""):gsub("%s+$", "")) or "" end
parent.SelectSub("ban")
local banRefresh = parent.subPanels.ban.refresh   -- built with the panel
check(type(banRefresh) == "function", "the ban list registers its repaint")
banRefresh()
local afterBans = created
for _ = 1, 200 do banRefresh() end
check(created == afterBans, "200 repaints of the ban list reuse its rows (" .. (created - afterBans) .. " made)")
local banPanel = parent.subPanels.ban.panel
local function banRows()
  local out = {}
  local function walk(f)
    for _, c in ipairs(f.children) do
      if rawget(c, "cells") and rawget(c, "shown") then out[#out + 1] = c end
      walk(c)
    end
  end
  walk(banPanel)
  return out
end
local shown = banRows()
check(#shown == 30, "every ban has a row (" .. #shown .. ")")
local anyShare = false
for _, r in ipairs(shown) do if r.share.shown then anyShare = true end end
check(not anyShare, "with no alliance on guildos.me, no Share button")
siteAlliance = true
banRefresh()
shown = banRows()
local shareShown = 0
for _, r in ipairs(shown) do if r.share.shown then shareShown = shareShown + 1 end end
check(shareShown == 29, "with one, Share on each ban in force, not on the one that ran out (" .. shareShown .. ")")
for i = 11, 30 do bans[i] = nil end
banRefresh()
check(#banRows() == 10 and created == afterBans, "fewer bans: the extra rows hide, nothing new is made")
local ui = assert(io.open(ADDON .. "/UI/ManagementPanel.lua", "rb")):read("*a")
check(ui:find("GuildOS.BanList:ConfirmRemoveKey(key, who)", 1, true) and not ui:find("BanList:RemoveKey(key) end end)", 1, true),
  "the x asks before it lifts")

print("engagement-panel: " .. checks .. " checks passed")
