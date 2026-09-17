-- One window (issue #14), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Data.lua, Core/Commands.lua, UI/Helpers.lua, UI/Layout.lua,
-- UI/FeatureRegistry.lua, UI/Window.lua, UI/Agora.lua, UI/CalendarPanel.lua,
-- UI/Minimap.lua and UI/Features.lua under a stub frame API.
--
-- The slash commands, the minimap button and menu, the guild-frame hook and its
-- button open one window on the tab they name. A feature that is disabled,
-- failed to start, is officer-only or is not on this client gets no tab.
-- Position, size, the fold and the open tab come back after /reload, pulled
-- onto the screen. The ladder, measured on the content area, switches the tab
-- rule, "»n", the selector, the Now tab and the 28px bar at the right widths.
-- The Now column reads the right data, keeps its limits, shows its empty and
-- loading states, refreshes on its ticker and on roster events, and every row
-- opens its screen with its filter.
--
--   luajit -e 'ADDON="."' tools/window-shell.lua
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

-- ── Stub frame API ─────────────────────────────────────────────────────
local SCREEN_W, SCREEN_H = 1600, 900
local Frame = {}
Frame.__index = Frame

local function newFrame(kind, parent)
  local f = setmetatable({
    kind = kind, parent = parent, children = {}, shown = true, points = {}, scripts = {},
    w = 0, h = 0, scale = 1, level = parent and ((parent.level or 0) + 1) or 0, events = {},
  }, Frame)
  if parent then parent.children[#parent.children + 1] = f end
  return f
end

local function fire(f, script, ...)
  local fn = f.scripts[script]
  if fn then return fn(f, ...) end
end

local function cascade(f, script)
  if not f.shown then return end
  fire(f, script)
  for _, c in ipairs(f.children) do cascade(c, script) end
end

function Frame:SetSize(w, h) self.w, self.h = w, h; fire(self, "OnSizeChanged", w, h) end
function Frame:SetWidth(w) self.w = w; fire(self, "OnSizeChanged", self.w, self.h) end
function Frame:SetHeight(h) self.h = h; fire(self, "OnSizeChanged", self.w, self.h) end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints(other) self.points = { { "ALL", other } } end
function Frame:GetPoint(i)
  local p = self.points[i or 1]
  if p then return p[1], p[2], p[3], p[4], p[5] end
end
-- The two ways the window is ever anchored: by its top-left corner to the
-- screen's bottom-left, or centred.
function Frame:GetLeft()
  local p = self.points[1]
  if not p then return nil end
  if p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT" then return p[4] end
  if p[1] == "CENTER" then return (SCREEN_W / self.scale - self.w) / 2 + (p[4] or 0) end
end
function Frame:GetTop()
  local p = self.points[1]
  if not p then return nil end
  if p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT" then return p[5] end
  if p[1] == "CENTER" then return (SCREEN_H / self.scale + self.h) / 2 + (p[5] or 0) end
end
function Frame:GetParent() return self.parent end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
  local f = self
  while f do
    if not f.shown then return false end
    f = f.parent
  end
  return true
end
function Frame:Show()
  if self.shown then return end
  local parentVisible = not self.parent or self.parent:IsVisible()
  self.shown = true
  if parentVisible then cascade(self, "OnShow") end
end
function Frame:Hide()
  if not self.shown then return end
  if self:IsVisible() then cascade(self, "OnHide") end
  self.shown = false
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel() return self.level end
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:CreateTexture(_, layer) local t = newFrame("Texture", self); t.layer = layer; return t end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetFont(file, size) self.font = { file = file, size = size }; return true end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function Frame:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
function Frame:SetResizeBounds(w, h) self.resizeBounds = { w, h } end
function Frame:SetClipsChildren(v) self.clips = v end
function Frame:SetMovable(v) self.movable = v end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:SetResizable(v) self.resizable = v end
function Frame:RegisterForDrag(button) self.dragButton = button end
function Frame:StartMoving() if self.movable then self.moving = true end end
function Frame:StartSizing(corner) if self.resizable then self.sizing = corner end end
function Frame:StopMovingOrSizing() self.moving, self.sizing = nil, nil end
function Frame:SetScrollChild(child) self.scrollChild = child end
function Frame:GetStringHeight() return 12 end
local function isRegion(c) return c.kind == "Texture" or c.kind == "FontString" end
function Frame:GetChildren()
  local out = {}
  for _, c in ipairs(self.children) do if not isRegion(c) then out[#out + 1] = c end end
  return unpack(out)
end
function Frame:GetRegions()
  local out = {}
  for _, c in ipairs(self.children) do if isRegion(c) then out[#out + 1] = c end end
  return unpack(out)
end
function Frame:IsEnabled() return true end
function Frame:IsMouseOver() return false end
for _, name in ipairs({ "EnableMouse", "SetClampedToScreen", "RegisterForClicks", "SetBackdrop",
  "SetBackdropBorderColor", "SetTexture", "SetTexCoord", "SetBlendMode", "SetAlpha", "SetShadowOffset",
  "SetShadowColor", "SetJustifyH", "SetWordWrap", "SetTextInsets", "SetAutoFocus", "SetMaxLetters", "ClearFocus",
  "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetMultiLine" }) do
  Frame[name] = function() end
end

function CreateFrame(kind, name, parent)
  local f = newFrame(kind, parent)
  if name then f.name = name; _G[name] = f end
  return f
end
UIParent = newFrame("Frame")
UIParent.w, UIParent.h = SCREEN_W, SCREEN_H
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
GuildOSDB = {}

-- ── The rest of the client ─────────────────────────────────────────────
local queue, tickers = {}, {}
C_Timer = {
  After = function(_, fn) queue[#queue + 1] = fn end,
  NewTicker = function(interval, fn)
    local t = { interval = interval, fn = fn }
    function t:Cancel() self.cancelled = true end
    tickers[#tickers + 1] = t
    return t
  end,
}
local function flush()
  for _ = 1, 20 do
    if #queue == 0 then return end
    local due = queue
    queue = {}
    for _, fn in ipairs(due) do fn() end
  end
end
local function liveTicker(interval)
  for i = #tickers, 1, -1 do
    local tk = tickers[i]
    if tk.interval == interval and not tk.cancelled then return tk end
  end
end

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local function said(fragment)
  for _, m in ipairs(printed) do
    if m:find(fragment, 1, true) then return true end
  end
  return false
end

local NOW = 1757800000
function GetServerTime() return NOW end
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
local hooks = {}
function hooksecurefunc(name, fn) hooks[name] = fn end
function debugstack() return "" end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_GuildInfo = { GuildRoster = function() end }
function UnitName() return "Ana" end
local canInvite = true
function CanGuildInvite() return canInvite end
function GuildInvite() end
GuildFrame = newFrame("Frame", UIParent)
GuildFrame:Hide()
function ToggleGuildFrame() end
function HideUIPanel(frame) frame:Hide() end
Minimap = newFrame("Frame", UIParent)
Minimap.w, Minimap.h = 140, 140

local inGuild, officer = true, true
local roster = { { "Ana-Firemaw", true }, { "Beto-Firemaw", false }, { "Caio-Firemaw", true } }
local fullRoster = roster
function IsInGuild() return inGuild end
function GetGuildInfo() if inGuild then return "Chama", "Rank", officer and 0 or 5 end end
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) local r = roster[i]; return r[1], "Rank", 0, 70, "Mage", "", "", "", r[2] end

local menuItems, menuAnchor = {}, nil
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuItems[#menuItems + 1] = info end
function UIDropDownMenu_Initialize(frame, init) menuItems = {}; init(frame, 1) end
function ToggleDropDownMenu(_, _, _, anchor) menuAnchor = anchor end
function CloseDropDownMenus() menuAnchor = nil end

-- ── Load ────────────────────────────────────────────────────────────────
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
local selftests = {}
BRutus.SelfTest = { Register = function(_, name, fn) selftests[name] = fn end }
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Commands.lua")
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/UI/FeatureRegistry.lua")
local UI, C = BRutus.UI, BRutus.Colors
-- A tab this client does not support, and one whose panel raises while building.
UI:RegisterFeature({ id = "tbcOnly", label = "TBC only", order = 200, tbc = true, build = function() end })
UI:RegisterFeature({ id = "boom", label = "Boom", order = 210, build = function() error("boom") end })
dofile(ADDON .. "/UI/Window.lua")
dofile(ADDON .. "/UI/Agora.lua")
dofile(ADDON .. "/UI/CalendarPanel.lua")
dofile(ADDON .. "/UI/Minimap.lua")
dofile(ADDON .. "/UI/Features.lua")
local A = UI.Agora
check(not BRutus.Client.isAnniversary, "the stub client is not TBC Anniversary")

function BRutus:TimeAgo(ts) return "T" .. (NOW - ts) end
local events = {}
BRutus.Calendar = {
  GetUpcoming = function() return events end,
  GetComposition = function(_, e) return { yes = e.yes or 0 } end,
  MyRsvp = function(_, e) return e.mine end,
  GetEvents = function() return {} end,
}

-- Panel builders record what they built and, where the real one does, expose
-- SelectSub and record the sub-tab and filter it was given.
local built, selected = {}, {}
local function builder(name, withSub)
  BRutus[name] = function(_, c)
    built[name] = (built[name] or 0) + 1
    if withSub then
      c.SelectSub = function(sub, filter)
        selected[#selected + 1] = name .. ":" .. sub .. (filter ~= nil and (":" .. tostring(filter)) or "")
      end
    end
  end
end
for _, n in ipairs({ "CreateRosterPanel", "CreateLootPanel", "CreateDKPPanel", "CreateWishlistGuildPanel",
  "CreateRecipesPanel", "CreateTrialsPanel", "CreateWebPanel", "CreateSettingsPanel", "CreateDashboardPanel" }) do
  builder(n)
end
for _, n in ipairs({ "CreateRaidHubPanel", "CreateGuildHub", "CreateAlliancePanel", "CreateRecruitmentPanel",
  "CreateManagementPanel" }) do
  builder(n, true)
end

local function tabOf(f, key)
  for _, t in ipairs(f.tabs) do if t.key == key then return t end end
end
local function listed(f, key)
  if tabOf(f, key).shown then return true end
  for _, k in ipairs(f.overflow) do if k == key then return true end end
  return false
end
local function allowedCount(f)
  local n = 0
  for _, t in ipairs(f.tabs) do if UI:IsFeatureAllowed(UI:GetFeature(t.key)) then n = n + 1 end end
  return n
end
local function shownTabs(f)
  local n = 0
  for _, t in ipairs(f.tabs) do if t.shown then n = n + 1 end end
  return n
end
local function resize(f, w, h) f:SetSize(w, h or f.h); flush() end
-- "POINT,x,y" of a frame's i-th anchor, in either SetPoint form.
local function point(frame, i)
  local p = frame.points[i or 1]
  if not p then return nil end
  if type(p[2]) == "number" then return table.concat({ p[1], p[2], p[3] }, ",") end
  return table.concat({ tostring(p[1]), tostring(p[4]), tostring(p[5]) }, ",")
end
local function read(p)
  local fh = assert(io.open(ADDON .. "/" .. p, "rb"))
  local s = fh:read("*a")
  fh:close()
  return s
end
local function same(color, token)
  return color ~= nil and math.abs(color[1] - token.r) < 1e-6 and math.abs(color[2] - token.g) < 1e-6
    and math.abs(color[3] - token.b) < 1e-6
end
local function visible(list)
  local n = 0
  for _, r in ipairs(list.rows) do if r.shown then n = n + 1 end end
  return n
end

-- ── Entry points ────────────────────────────────────────────────────────
check(UI:GetMainWindow() == nil, "no window before the saved data loads")
BRutus.db = { settings = { modules = {} }, members = {}, calendar = { events = {} } }
local slash = SlashCmdList.GUILDOS
check(slash and SlashCmdList.BRUTUS == slash, "/guildos, /gos and the legacy /brutus share one handler")

local finder = false
function BRutus:ShowRecruitInbox() finder = true end
inGuild = false
slash("")
check(finder and BRutus.RosterFrame == nil, "guildless: /gos opens the recruitment finder, not the window")
inGuild = true

slash("")
local f = BRutus.RosterFrame
flush()
check(f and f:IsShown() and f.name == "GuildOSWindow", "/gos opens the one window")
check(f.w == 1000 and f.h == 620 and f.points[1][1] == "CENTER", "no saved geometry: 1000×620, centred")
check(f.resizeBounds and f.resizeBounds[1] == 320 and f.resizeBounds[2] == 28, "resizable down to 320×28")
check(f.grip.w == 16 and f.grip.h == 16 and point(f.grip) == "BOTTOMRIGHT,-1,1", "from a 16×16 grip in the corner")
check(f.content.clips, "the content is clipped at the window's edge")
check(f.strata == "HIGH", "on the HIGH strata")
check(f.titleBar.dragButton == "LeftButton", "the title bar takes a left-button drag")
fire(f.titleBar, "OnDragStart")
check(f.moving, "and dragging it moves the window")
fire(f.titleBar, "OnDragStop")
check(not f.moving, "until it is let go")
fire(f.grip, "OnMouseDown")
check(f.sizing == "BOTTOMRIGHT", "the grip resizes the window from its bottom-right corner")
fire(f.grip, "OnMouseUp")
check(not f.sizing, "until it is let go")
check(f.activeTab == "home" and tabOf(f, "home").label.text == "Now", "it opens on Now, the first tab")
check(f.tabs[1].key == "home" and UI:GetFeature("home").core,
  "Now is the first tab, and core: it cannot be switched off, so the fall-back always exists")
check(BRutus:IsFrontDoorShown(), "the guild-frame hook sees the window open")
local esc = false
for _, n in ipairs(UISpecialFrames) do if n == "GuildOSWindow" then esc = true end end
check(esc, "Escape closes the window")
slash("")
check(not f:IsShown() and not BRutus:IsFrontDoorShown(), "/gos again closes it")

BRutus:CreateMinimapButton()
local mm = GuildOSMinimapButton
fire(mm, "OnClick", "LeftButton")
check(f:IsShown(), "a left click on the minimap button opens the window")
fire(mm, "OnClick", "LeftButton")
check(not f:IsShown(), "and closes it")
fire(mm, "OnClick", "RightButton")
local raidsItem
for _, item in ipairs(menuItems) do if item.text == "Raids" then raidsItem = item end end
check(raidsItem ~= nil, "the minimap menu lists the window's tabs")
raidsItem.func()
check(f:IsShown() and f.activeTab == "raids", "a tab picked there opens in the window")

f:Hide()
BRutus:HookGuildFrame()
check(type(hooks.ToggleGuildFrame) == "function", "the guild key is hooked after Blizzard's toggle, not replaced")
GuildFrame:Show()
hooks.ToggleGuildFrame()
check(not GuildFrame:IsShown() and f:IsShown(), "the guild key opens Guild OS in place of Blizzard's frame")
hooks.ToggleGuildFrame()
check(not f:IsShown(), "and closes it again")
local native
for _, c in ipairs(GuildFrame.children) do if c.kind == "Button" and c.text == "Guild OS" then native = c end end
check(native ~= nil, "Blizzard's guild frame carries a Guild OS button")
fire(native, "OnClick")
check(f:IsShown(), "which opens the window")

check(BINDING_HEADER_GUILDOS == "Guild OS" and BINDING_NAME_GUILDOS_TOGGLE == "Open or close Guild OS",
  "the key binding is labelled")
local bindings = read("Bindings.xml")
check(bindings:find('name="GUILDOS_TOGGLE"', 1, true) and bindings:find('category="ADDONS"', 1, true)
  and bindings:find("BRutus:ToggleRoster()", 1, true), "the key binding, in the AddOns category, opens the window")
check(read("Modules/Digest.lua"):find("BRutus:ToggleRoster()", 1, true)
  and read("UI/Onboarding.lua"):find('OpenWindow("settings")', 1, true),
  "the digest and onboarding open the window through the same calls")

do
  local refreshed = 0
  f.RefreshRoster = function() refreshed = refreshed + 1 end
  BRutus:RefreshRosterUI()
  check(refreshed == 1, "the roster refreshes while the window is up")
  f:Hide()
  BRutus:RefreshRosterUI()
  check(refreshed == 1, "and not while it is closed")
  f.RefreshRoster = nil
end

slash("open management inactive")
check(f:IsShown() and f.activeTab == "management" and selected[#selected] == "CreateManagementPanel:inactive",
  "/gos open reaches the tab and its sub-tab (the hub's link was ignored)")
check(BRutus.db.settings.window.tab == "management", "an opened tab is remembered")
slash("banlist")
check(selected[#selected] == "CreateManagementPanel:ban", "/gos banlist lands on the ban list")
slash("calendar")
check(f.activeTab == "guild" and selected[#selected] == "CreateGuildHub:calendar", "/gos calendar lands on the calendar")
check(built.CreateManagementPanel == 1 and built.CreateGuildHub == 1, "each panel builds once, the first time it opens")
printed = {}
slash("open nope")
check(said("Usage: /gos open <feature>"), "/gos open with an unknown tab shows its usage")
printed = {}
slash("open raidTracker")
check(said("Usage: /gos open <feature>"), "and so does a background module, which has no tab")
check(not UI:OpenWindow("nope") and not UI:OpenWindow("raidTracker"), "OpenWindow opens nothing for either")

-- ── Which features get a tab ────────────────────────────────────────────
resize(f, 1000, 620)
check(listed(f, "recipes") and listed(f, "loot") and listed(f, "alliance"), "available features have tabs")
check(not listed(f, "tbcOnly"), "a feature this client does not support gets no tab")

BRutus:SetFeatureEnabled("recipes", false)
printed = {}
check(not UI:OpenWindow("recipes") and said("Recipes is disabled in Settings."), "a disabled feature refuses, saying why")
check(not listed(f, "recipes"), "a disabled feature has no tab")
BRutus:SetFeatureEnabled("recipes", true)
check(listed(f, "recipes"), "switching it back on brings the tab back")

BRutus.State.startup.failedFeatures.alliance = "Alliance"
f:UpdateTabVisibility()
printed = {}
check(not UI:OpenWindow("alliance") and said("Alliance could not start on this client."), "a failed feature refuses, saying why")
check(not listed(f, "alliance"), "a feature whose module failed to start has no tab")
BRutus.State.startup.failedFeatures.alliance = nil

officer = false
f:UpdateTabVisibility()
printed = {}
check(not UI:OpenWindow("loot") and said("Loot is officer-only."), "an officer-only tab refuses a member")
check(not listed(f, "loot") and not listed(f, "management"), "a member sees no officer tabs")
officer = true
f:UpdateTabVisibility()

do
  local before = f.activeTab
  printed = {}
  check(not UI:OpenWindow("boom") and said("Boom could not start on this client."), "a tab that raises while building refuses")
  check(f.activeTab == before, "and leaves the open tab alone")
  check(BRutus.State.startup.failed["Tab:boom"], "and /guildos errors lists it as Tab:boom")
end

UI:OpenWindow("trials")
BRutus:SetFeatureEnabled("trials", false)
check(f.activeTab == "home" and not f.tabPanels.trials.shown and f.tabPanels.home.shown,
  "switching off the open tab's feature falls back to Now")
BRutus:SetFeatureEnabled("trials", true)

-- ── Geometry and persistence ────────────────────────────────────────────
do
  check(select(1, UI:ClampWindowRect(100, 700, 1000, 620, 1600, 900)) == 100, "a rectangle on screen is left alone")
  local l, t, w, h = UI:ClampWindowRect(1200, 1000, 1000, 620, 1600, 900)
  check(l == 600 and t == 900 and w == 1000 and h == 620, "one hanging off the top right is pulled back on")
  l, t, w, h = UI:ClampWindowRect(-50, 10, 2000, 1200, 1600, 900)
  check(l == 0 and t == 900 and w == 1600 and h == 900, "one larger than the screen shrinks to it")
  l, t, w, h = UI:ClampWindowRect(0, 0, 100, 10, 1600, 900)
  check(w == 320 and h == 28 and t == 28, "none is smaller than the bar")
end

f.points = { { "TOPLEFT", UIParent, "BOTTOMLEFT", 300, 700 } }
fire(f.titleBar, "OnDragStop")
local g = BRutus.db.settings.window
check(g.left == 300 and g.top == 700 and g.w == 1000 and g.h == 620, "dragging the title bar saves where the window is")

UI:OpenWindow("raids")
f:Hide()
BRutus.RosterFrame = nil   -- /reload
f = UI:GetMainWindow()
check(point(f) == "TOPLEFT,300,700" and f.w == 1000 and f.h == 620, "after /reload the window is where it was, at its size")
check(f.activeTab == "raids", "and on the tab it was left on")

BRutus.db.settings.window = { left = 1200, top = 1000, w = 1000, h = 620 }
BRutus.RosterFrame = nil
f = UI:GetMainWindow()
check(point(f) == "TOPLEFT,600,900", "a saved spot hanging off the screen is pulled back on")

BRutus.db.settings.window, BRutus.db.settings.uiScale = nil, 2
BRutus.RosterFrame = nil
f = UI:GetMainWindow()
check(f.scale == 2 and f.w == 800 and f.h == 450, "the UI scale applies, and the default size fits the scaled screen")
BRutus.db.settings.uiScale = 1.1
UI:ApplyScale()
check(f.scale == 1.1, "changing the UI scale rescales the window")
BRutus.db.settings.uiScale = nil
BRutus.db.settings.window = nil
BRutus.RosterFrame = nil
f = UI:GetMainWindow()
f:Show()
resize(f, 1000, 620)
g = BRutus.db.settings.window

-- ── Title bar, footer, refresh ──────────────────────────────────────────
check(f.band == "full" and f.titleBar.h == 30, "at 1000px the title bar is 30px")
do
  local F = BRutus.Fonts
  local wordmark, barBg
  for _, c in ipairs(f.titleBar.children) do
    if c.kind == "FontString" and c.text == "GuildOS" then wordmark = c end
    if c.kind == "Texture" and c.layer == "BACKGROUND" then barBg = c end
  end
  check(wordmark and wordmark.font.file == F.wordmark.file and wordmark.font.size == 18 and same(wordmark.color, C.gold),
    "left: the gold wordmark, GuildOS, in its Spectral face")
  check(barBg and same(barBg.color, C.panel), "the title bar sits on panel")
  check(same(f.metaText.color, C.labelDim) and same(f.syncText.color, C.label) and f.metaText.font.file == F.mono
    and f.syncText.font.size == 10, "the meta line in labelDim and the sync time in label, both mono 10")
  local label = tabOf(f, "roster").label
  check(label.font.file == F.mono and label.font.size == 11, "tab labels are mono 11")
  local ruleLine
  for _, c in ipairs(f.rule.children) do if c.kind == "Texture" and c.h == 1 then ruleLine = c end end
  check(ruleLine and same(ruleLine.color, C.line), "with a 1px line under the tab rule")
  local barLine, footLine
  for _, c in ipairs(f.titleBar.children) do if c.kind == "Texture" and c.h == 1 then barLine = c end end
  for _, c in ipairs(f.footer.children) do if c.kind == "Texture" and c.h == 1 then footLine = c end end
  check(barLine and same(barLine.color, C.line) and footLine and same(footLine.color, C.line),
    "a 1px line under the title bar and above the footer")
end
fire(f.closeButton, "OnClick")
check(not f:IsShown(), "× closes the window")
f:Show()
flush()
check(f.metaText.shown and f.metaText.text == "Chama · 2 online", "left: the guild and who is online")
BRutus.db.members = { a = { lastSync = NOW - 300 }, b = { lastSync = NOW - 60 }, c = "junk" }
f:RefreshTitle()
check(f.syncText.shown and f.syncText.text == "sync T60", "right: the newest sync time")
BRutus.db.members = {}
f:RefreshTitle()
check(f.syncText.text == "not synced yet", "before any sync it says so")
check(f.minimise.x.text == "\226\128\148" and f.closeButton.shown and point(f.closeButton) == "RIGHT,-6,0",
  "then minimise and close at the right edge")
check(point(f.content, 1) == "TOPLEFT,12,-70" and point(f.content, 2) == "BOTTOMRIGHT,-12,34",
  "content padding 12px under the 30px title bar and the tab rule, and above the 22px footer")

check(f.events.GROUP_ROSTER_UPDATE and f.events.RAID_ROSTER_UPDATE and f.events.PARTY_LOOT_METHOD_CHANGED
  and f.events.GUILD_ROSTER_UPDATE, "the window listens for group, raid, loot-method and roster changes")
do
  local titleTicker = liveTicker(10)
  check(titleTicker ~= nil, "while shown, the title refreshes every 10s")
  roster[2][2] = true
  titleTicker.fn()
  check(f.metaText.text == "Chama · 3 online", "and the tick picks up who came online")
  roster[2][2] = false
  fire(f, "OnEvent", "GUILD_ROSTER_UPDATE")
  check(f.metaText.text == "Chama · 2 online", "so does a roster update")
  f:Hide()
  roster[2][2] = true
  fire(f, "OnEvent", "GUILD_ROSTER_UPDATE")
  check(f.metaText.text == "Chama · 2 online", "closed, the window does not refresh on a roster update")
  roster[2][2] = false
  f:Show()
  flush()
  officer = false
  fire(f, "OnEvent", "GROUP_ROSTER_UPDATE")
  check(not listed(f, "loot"), "a group change re-checks the tabs")
  officer = true
  fire(f, "OnEvent", "PARTY_LOOT_METHOD_CHANGED")
  check(listed(f, "loot"), "so does a loot-method change")
  roster = {}
  f:RefreshTitle()
  check(f.metaText.text == "Chama · \226\128\148", "while the roster loads, a dash instead of 0 online")
  roster = fullRoster
  f:RefreshTitle()
end

do
  local function footShown(key) return f.footItems[key].shown end
  check(footShown("search") and footShown("sync") and footShown("invite") and footShown("cores") and footShown("blizzard"),
    "at 1000px the footer holds every action and the invite field")
  check(point(f.footItems.search) == "LEFT,10,0", "starting 10px in")
  check(f.footItems.search.variant == "ghost" and f.footItems.sync.variant == "ghost"
    and f.footItems.cores.variant == "ghost" and f.footItems.blizzard.variant == "ghost", "as ghost buttons")
  local ran = {}
  local real = { BRutus.Search, BRutus.CommSystem, BRutus.ShowCoreSignupFrame, BRutus.OpenBlizzardGuildUI }
  BRutus.Search = { Show = function() ran.search = true end }
  BRutus.CommSystem = { FullSync = function() ran.sync = true end }
  BRutus.ShowCoreSignupFrame = function() ran.cores = true end
  BRutus.OpenBlizzardGuildUI = function() ran.blizzard = true end
  for _, key in ipairs({ "search", "sync", "cores", "blizzard" }) do fire(f.footItems[key], "OnClick") end
  check(ran.search and ran.sync and ran.cores and ran.blizzard, "each footer action runs what it names")
  BRutus.Search, BRutus.CommSystem, BRutus.ShowCoreSignupFrame, BRutus.OpenBlizzardGuildUI = real[1], real[2], real[3], real[4]
  local invitedName
  local realInvite = GuildInvite
  GuildInvite = function(name) invitedName = name end
  local holder, inviteBtn = f.footItems.invite, nil
  for _, c in ipairs(holder.children) do
    if c.kind == "Button" and c.label and c.label.text == "Invite" then inviteBtn = c end
  end
  printed = {}
  holder.box:SetText("")
  fire(inviteBtn, "OnClick")
  check(invitedName == nil and said("Enter a player name to invite."), "an empty invite asks for a name")
  holder.box:SetText("  Nova  ")
  fire(inviteBtn, "OnClick")
  check(invitedName == "Nova" and said("Guild invite sent to Nova.") and holder.box.text == "",
    "the invite field invites the name typed, then clears")
  GuildInvite = realInvite
  canInvite = false
  f:LayoutFooter(1000)
  check(not footShown("invite") and footShown("blizzard"), "no invite field for who cannot invite")
  canInvite = true
  f:LayoutFooter(490)
  check(not footShown("blizzard") and footShown("cores") and footShown("invite"), "narrower: Blizzard goes first")
  f:LayoutFooter(420)
  check(not footShown("cores") and footShown("search") and footShown("sync") and footShown("invite"),
    "then Core Sign-up; search, sync and invite stay longest")
  f:LayoutFooter(1000)
end

-- ── Tab rule and »n ─────────────────────────────────────────────────────
check(shownTabs(f) == allowedCount(f) and not f.more.shown and #f.overflow == 0, "at 1000px every tab fits")
do
  local x = 6
  for _, tab in ipairs(f.tabs) do
    if tab.shown then
      check(point(tab) == "LEFT," .. x .. ",0", tab.key .. " sits after the one before it")
      check(tab.label.text == UI:GetFeature(tab.key).label and tab.w >= 48, tab.key .. " shows its name, never an icon")
      x = x + tab.w + 2
    end
  end
end
check(tabOf(f, f.activeTab).isActive, "the open tab carries the rule")
fire(tabOf(f, "loot"), "OnClick")
check(f.activeTab == "loot" and g.tab == "loot" and tabOf(f, "loot").isActive,
  "clicking a tab on the rule opens it, marks it and remembers it")

resize(f, 890)
check(f.band == "full", "890px (content 866) is still full: 16px past the line before the band changes")
resize(f, 887)
check(f.band == "wide", "887px (content 863) is wide: the band is measured on the content, not the window")

resize(f, 600)
check(f.band == "compact" and f.titleBar.h == 28, "under 620px the title bar is 28px")
check(point(f.content, 1) == "TOPLEFT,8,-64" and point(f.content, 2) == "BOTTOMRIGHT,-8,30", "and the padding 8px")
check(f.more.shown and #f.overflow > 0 and f.more.label.text == "\194\187" .. #f.overflow,
  "tabs that do not fit fold into »n, which counts them")
check(shownTabs(f) + #f.overflow == allowedCount(f), "every allowed tab is on the rule or behind »n")
check(point(f.more) == "RIGHT,-6,0", "»n sits at the rule's right edge")
check(f.more.variant == "ghost", "»n is a ghost button")
do
  local widths, active = {}, nil
  for _, tab in ipairs(f.tabs) do
    if UI:IsFeatureAllowed(UI:GetFeature(tab.key)) then
      widths[#widths + 1] = math.max(48, #tab.label.text * 6 + 20)
      if tab.key == f.activeTab then active = #widths end
    end
  end
  local _, hidden = UI:FitTabs(widths, 600 - 12, 2, 36, active)
  check(#f.overflow == hidden, "the fold is UI:FitTabs' answer")
  fire(f.more, "OnClick")
  check(menuAnchor == f.more and #menuItems == #f.overflow, "»n opens a menu of the tabs it holds")
  for i, item in ipairs(menuItems) do
    check(item.text == UI:GetFeature(f.overflow[i]).label, "menu entry " .. i .. " names its tab")
  end
  -- The last folded tab that builds: "boom" is made to raise.
  local pick = #f.overflow
  while f.overflow[pick] == "boom" do pick = pick - 1 end
  local picked = f.overflow[pick]
  menuItems[pick].func()
  check(f.activeTab == picked and tabOf(f, picked).shown, "a tab picked from »n opens and joins the rule")
  check(g.tab == picked, "and is remembered")
end

-- ── Watch: the selector and Now ─────────────────────────────────────────
UI:OpenWindow("raids")
resize(f, 500)
check(f.band == "watch" and f.activeTab == "home", "under 520px the content switches to Now")
check(f.selector.shown and shownTabs(f) == 0 and not f.more.shown, "and the tab rule becomes a one-line selector")
check(f.selector.label.text == "Now \194\187", "the selector names the open tab")
check(f.selector.variant == "ghost", "the selector is a ghost button")
check(g.tab == "raids", "the switch to Now is not remembered as a choice")
fire(f.selector, "OnClick")
check(#menuItems == allowedCount(f), "the selector lists every tab")
do
  local nowItem
  for _, item in ipairs(menuItems) do if item.text == "Now" then nowItem = item end end
  check(nowItem and nowItem.checked, "with the open one checked")
end
resize(f, 700)
check(f.band == "compact" and f.activeTab == "raids", "wide again, the tab that was open comes back")
check(not f.selector.shown and shownTabs(f) > 0, "and the tab rule replaces the selector")
resize(f, 500)
fire(f.selector, "OnClick")
for _, item in ipairs(menuItems) do if item.text == "Roster" then item.func() end end
check(f.activeTab == "roster" and g.tab == "roster", "a tab picked from the selector opens and is remembered")
resize(f, 900)
check(f.band == "wide" and f.activeTab == "roster", "and stays open when the window widens")

-- ── Bar ─────────────────────────────────────────────────────────────────
resize(f, 1000, 620)
fire(f.grip, "OnMouseDown")
resize(f, 400, 620)
check(f.band == "bar" and not f.rule.shown and not f.content.shown and not f.footer.shown,
  "under 420px only the title bar stays")
check(f.summaryText.shown and not f.metaText.shown and f.summaryText.text == A:BarText(),
  "with the three numbers in place of the meta line")
check(f.minimise.x.text == "+" and point(f.closeButton) == "RIGHT,-20,0",
  "the dash becomes the way back out, and close clears the grip")
fire(f.grip, "OnMouseUp")
flush()
check(f.h == 28 and g.collapsed and g.restoreW == 1000 and g.restoreH == 620, "let go in the bar: 28px tall, the old size kept")
check(g.w == 400 and g.h == 28 and g.left and g.top, "and the fold is saved")
check(f.points[1][1] == "TOPLEFT", "it folds from its top-left corner")
fire(f.minimise, "OnClick")
check(f.w == 1000 and f.h == 620 and not g.collapsed and f.band == "full", "the bar opens back to that size, laid out at once")
check(g.w == 1000 and g.h == 620, "and that size is saved")
fire(f.minimise, "OnClick")
check(f.w == 320 and f.h == 28 and g.collapsed and f.band == "bar", "minimise folds the window to the bar")
check(g.w == 320 and g.h == 28 and g.restoreW == 1000 and g.restoreH == 620, "and saves the fold")
roster[2][2] = true
fire(f.minimise, "OnClick")
check(f.metaText.text == "Chama · 3 online", "unfolding refreshes the title at once, not on the next tick")
roster[2][2] = false
fire(f.minimise, "OnClick")
f:Hide()
BRutus.RosterFrame = nil   -- /reload
f = UI:GetMainWindow()
check(f.w == 320 and f.h == 28 and f.band == nil, "folded, it comes back folded after /reload")
check(UI:OpenWindow("roster") and f.w == 1000 and f.h == 620 and f.band == "full" and f.content.shown,
  "a deep link right after /reload opens it back up, laid out before the next frame")
flush()
fire(f.minimise, "OnClick")
fire(f.grip, "OnMouseDown")
resize(f, 800, 28)
fire(f.grip, "OnMouseUp")
flush()
check(f.w == 800 and f.h == 620 and not g.collapsed and f.band == "medium", "dragged out of the bar, the height comes back")
check(g.w == 800 and g.h == 620, "and the new size is saved")
resize(f, 430, 500)
fire(f.grip, "OnMouseDown")
resize(f, 350)
fire(f.grip, "OnMouseUp")
flush()
check(g.restoreW == 430 and g.restoreH == 500, "the size kept is the one the drag started from")
fire(f.minimise, "OnClick")
check(f.w == 452 and f.h == 500 and f.band == "watch", "the way back out always lands past the bar band")
resize(f, 1000, 620)
fire(f.minimise, "OnClick")
fire(f.grip, "OnMouseDown")
resize(f, 440, 28)
fire(f.grip, "OnMouseUp")
flush()
check(f.h == 28 and g.collapsed and f.band == "bar",
  "dragged folded to 440px, whose 424px content is still in the bar band, it stays folded")
fire(f.minimise, "OnClick")
check(f.w == 1000 and f.h == 620, "and it still opens back to the size it had before it was folded")
resize(f, 1000, 620)

-- ── Now: data ───────────────────────────────────────────────────────────
local KARAZHAN = NOW + 4 * 3600 + 12 * 60 + 38
events = {
  { title = "Past", kind = "RAID", when = NOW - 60 },
  { title = "Dungeon", kind = "DUNGEON", when = NOW + 600 },
  { title = "Karazhan", when = KARAZHAN, yes = 9 },
}
check(A:NextRaid() == events[3], "the next raid skips past events and other kinds; kindless events are raids")
BRutus.db.calendar = nil
check(A:NextRaid() == nil, "before Calendar has started there is no raid, and no error")
BRutus.db.calendar = { events = {} }
check(A.Clock(4 * 3600 + 12 * 60 + 38) == "4:12:38" and A.Clock(2 * 86400 + 4 * 3600 + 5) == "2d 4h"
  and A.Clock(0) == "now", "the countdown reads h:mm:ss under a day, days and hours past it")
check(A.Short(4 * 3600 + 12 * 60) == "4h12" and A.Short(2 * 86400 + 3600) == "2d1h" and A.Short(59) == "1m"
  and A.Short(-5) == "now", "the bar's short form")
check(A:OnlineCount() == 2 and not A:RosterLoading(), "online counts the roster")
check(A:LastSync() == nil, "no sync, no time")

BRutus.TrialTracker = {
  GetActiveTrials = function() return { { key = "t1" }, { key = "t2" }, { key = "t3" } } end,
  -- Whole days, rounded down, like TrialTracker:GetDaysRemaining.
  GetDaysRemaining = function(_, k) return ({ t1 = 0, t2 = 1, t3 = 5 })[k] end,
}
BRutus.GuildManager = {
  DEFAULT_INACTIVE_DAYS = 30,
  GetInactiveMembers = function() return { 1, 2, 3, 4 } end,
  GetSuggestions = function() return { trialsReady = { 1 }, promoteCandidates = { 1, 2 } } end,
}
BRutus.RecruitScanner = { GetInbox = function() return { a = 1, b = 2 } end }
do
  local needs = A:NeedsMe()
  check(#needs == 5, "an officer's five kinds of work")
  check(needs[1].text == "1 trials expiring" and needs[1].urgent and needs[1].id == "trials",
    "urgent first: a trial with under a day left, not one with a whole day")
  check(needs[2].text == "You have not answered: Karazhan" and not needs[2].urgent and needs[2].id == "guild"
    and needs[2].sub == "calendar" and needs[2].filter == KARAZHAN, "an unanswered raid this week opens the calendar on its day")
  check(needs[3].text == "4 inactive over 30d" and needs[3].id == "management" and needs[3].sub == "inactive",
    "inactivity opens Leadership on inactivity")
  check(needs[4].text == "2 promotions to review" and needs[4].sub == "suggest",
    "suggestions open on suggestions and count promotions: a ready trial is already the trials row")
  check(needs[5].text == "2 applicants waiting" and needs[5].id == "recruitment" and needs[5].sub == "scanner",
    "applicants open the scanner")
end
events[3].mine = { status = "yes" }
check(#A:NeedsMe() == 4, "an answered raid needs nothing")
events[3].mine, events[3].when = nil, NOW + 7 * 86400 - 1
check(#A:NeedsMe() == 5, "a raid just inside a week asks")
events[3].when = NOW + 7 * 86400 + 1
check(#A:NeedsMe() == 4, "just past a week it does not yet")
events[3].when = KARAZHAN
BRutus:SetFeatureEnabled("trials", false)
check(A:NeedsMe()[1].id == "guild", "work for a screen that is switched off is left out")
BRutus:SetFeatureEnabled("guild", false)
check(A:NeedsMe()[1].id == "management", "and an unanswered raid needs the Guild tab")
BRutus:SetFeatureEnabled("guild", true)
BRutus:SetFeatureEnabled("trials", true)
officer = false
check(#A:NeedsMe() == 1 and A:NeedsMe()[1].id == "guild", "a member only sees their own answer")
officer = true

BRutus.db.members = { ["Ana-Firemaw"] = {}, ["Dora-Firemaw"] = {}, ["Bob-RealmA"] = {}, ["Bob-RealmB"] = {} }
BRutus.db.rosterLog = { events = {
  { action = "join", target = "Dora", timestamp = NOW - 100 },
  { action = "promote", target = "Ana", detail = "Officer", timestamp = NOW - 50 },
  { action = "leave", target = "Eva", timestamp = NOW - 110 },
  { action = "kick", target = "Bob", timestamp = NOW - 120 },
  { action = "demote", target = "Caio", detail = "Member", timestamp = NOW - 130 },
  { action = "join", target = "Edge", timestamp = NOW - 47 * 3600 },
  { action = "join", target = "Old", timestamp = NOW - 49 * 3600 },
  { action = "note", target = "X", timestamp = NOW - 10 },
} }
BRutus.db.lootHistory = {
  { player = "Beto", playerKey = "Beto-Firemaw", itemLink = "[Staff]", timestamp = NOW - 200 },
  { player = "Ancient", playerKey = "Ancient-Firemaw", itemLink = "[Relic]", timestamp = NOW - 50 * 3600 },
}
BRutus.db.milestones = { events = {
  { type = "ding", key = "Caio-Firemaw", name = "Caio", detail = "70", ts = NOW - 300 },
  { type = "attune", key = "Ana-Firemaw", name = "Ana", ts = NOW - 310 },
} }
BRutus.db.raidTracker = { sessions = { s1 = { name = "Karazhan", startTime = NOW - 3 * 3600, endTime = NOW - 400 } } }
do
  local feed = A:Activity()
  check(#feed == 10, "48 hours of roster changes, loot, milestones and tracked raids; older and unknown entries left out")
  check(feed[1].text == "Ana was promoted to Officer" and feed[1].id == "management" and feed[1].sub == "log"
    and feed[1].key == "Ana-Firemaw", "newest first; a promotion opens the audit log and that member")
  check(feed[2].text == "Dora joined the guild" and feed[2].key == "Dora-Firemaw", "a join")
  check(feed[3].text == "Eva left the guild" and feed[3].key == nil, "a leave, for someone no longer saved")
  check(feed[4].text == "Bob was removed from the guild" and feed[4].key == nil,
    "a removal: two members are called Bob, so no member is guessed")
  check(feed[5].text == "Caio was demoted to Member", "a demotion")
  check(feed[6].text == "Beto received [Staff]" and feed[6].id == "loot" and feed[6].key == "Beto-Firemaw",
    "loot opens the loot screen and the member who got it")
  check(feed[7].text == "Caio reached level 70!" and feed[7].id == "roster" and feed[7].key == "Caio-Firemaw",
    "a level milestone opens the member")
  check(feed[8].text == "Ana completed a new attunement" and feed[8].key == "Ana-Firemaw", "and an attunement one")
  check(feed[9].text == "Raid tracked: Karazhan" and feed[9].ts == NOW - 400 and feed[9].sub == "sessions",
    "a tracked raid, at the time it ended, opens the sessions")
  check(feed[10].text == "Edge joined the guild", "47 hours ago is still in; 49 is not")
  check(#A:Activity(2) == 2 and A:Activity(2)[1].ts == feed[1].ts, "the limit keeps the newest")
  officer = false
  local mine = A:Activity()
  check(mine[1].id == "roster" and mine[1].sub == nil and mine[6].id == "roster",
    "a member's rows open the roster where the owner is officer-only")
  officer = true

  local saved = { BRutus.db.rosterLog, BRutus.db.lootHistory, BRutus.db.milestones, BRutus.db.raidTracker }
  local many = {}
  for i = 1, 14 do many[i] = { action = "join", target = "N" .. i, timestamp = NOW - i } end
  BRutus.db.rosterLog, BRutus.db.lootHistory, BRutus.db.milestones, BRutus.db.raidTracker = { events = many }, nil, nil, nil
  check(#A:Activity() == 12, "at most 12 rows of activity")
  BRutus.db.rosterLog, BRutus.db.lootHistory, BRutus.db.milestones, BRutus.db.raidTracker = saved[1], saved[2], saved[3], saved[4]
end

local gold = string.format("%02x%02x%02x", math.floor(C.gold.r * 255 + 0.5), math.floor(C.gold.g * 255 + 0.5),
  math.floor(C.gold.b * 255 + 0.5))
check(A:BarText() == "2 · 4h12 · |cff" .. gold .. "5|r", "the bar: online · time to raid · pending, in that order")
roster = {}
check(A:RosterLoading() and A:BarText() == "\226\128\148 · 4h12 · \226\128\148", "while the roster loads: dashes, and the raid still counts down")
roster = fullRoster
do
  local saved = events
  events = {}
  officer = false
  check(A:BarText() == "2 · \226\128\148 · 0", "a dash with no raid; a plain zero with nothing pending")
  events, officer = saved, true
end

-- ── Now: the column ─────────────────────────────────────────────────────
UI:OpenWindow("home")
local now = f.tabPanels.home
now.Refresh()
check(now.column and now.needsList and now.feedList, "Now builds its live column")
local nowTicker = liveTicker(1)
check(nowTicker ~= nil, "its clock ticks every second while on screen")
now:SetSize(976, 520)
flush()
check(built.CreateDashboardPanel == 1 and now.home.shown and now.column.w == 296, "wide: the home cards beside the 296px column")
now:SetSize(700, 520)
flush()
check(not now.home.shown and now.column.w == 700, "under 780px: the column alone")
now:SetSize(976, 520)
flush()
check(built.CreateDashboardPanel == 1, "the home cards build once")
do
  local p = now.home.points[1]
  check(p and p[1] == "TOPLEFT" and p[2] == now.column and p[3] == "TOPRIGHT" and p[4] == 8 and p[5] == 0,
    "the home cards sit 8px beside the column, not over it")
  local raidCard, needsCard, feedCard = now.clock.parent, now.needsList.parent, now.feedList.parent
  local n1, f1 = needsCard.points[1], feedCard.points[1]
  local toBottom = false
  for _, q in ipairs(feedCard.points) do
    if q[1] == "BOTTOM" and q[2] == now.column and q[3] == "BOTTOM" then toBottom = true end
  end
  check(n1 and n1[2] == raidCard and n1[3] == "BOTTOMLEFT" and n1[5] == -8
    and f1 and f1[2] == needsCard and f1[3] == "BOTTOMLEFT" and f1[5] == -8 and toBottom,
    "the cards stack 8px apart, and activity runs to the bottom of the column")
  now:SetSize(780, 520)
  flush()
  check(now.home.shown and now.column.w == 296, "from 780px the home cards are beside the column")
  now:SetSize(779, 520)
  flush()
  check(not now.home.shown and now.column.w == 779, "at 779px the column is alone")
  now:SetSize(976, 520)
  flush()
end

check(now.clock.text == "4:12:38", "the countdown to the next raid")
check(same(now.clock.color, C.gold) and now.clock.font.file == BRutus.Fonts.countdown.file and now.clock.font.size == 19,
  "in gold, in the countdown's mono face at 19px")
check(now.raidMeta.text == "Karazhan · " .. os.date("%a %H:%M", KARAZHAN) .. " · 9 going", "its title, time and who is going")
check(now.openCalendar.shown and now.openCalendar.variant == "primary", "and a primary button to the calendar")

local needRows, feedRows = now.needsList.rows, now.feedList.rows
check(visible(now.needsList) == 5 and now.needsList.h == 2 + 5 * 26 and needRows[1].h == 26, "five 26px rows of what needs me")
check(needRows[1].mark.shown and needRows[1].mark.w == 6 and needRows[1].mark.h == 6
  and needRows[1].mark.color[1] == C.danger.r and needRows[1].text.text == "1 trials expiring",
  "urgent rows carry the 6px danger mark")
check(needRows[2].mark.color[1] == C.gold.r and needRows[2].mark.color[2] == C.gold.g, "the others the gold one")
check(point(needRows[1]) == "TOPLEFT,1,-1" and point(needRows[2]) == "TOPLEFT,1,-27",
  "rows stack 26px apart inside the list's 1px frame")
check(point(needRows[1].text, 2) == "LEFT,22,0", "a need's text starts after its mark")
fire(needRows[1], "OnEnter")
check(needRows[1].hover.shown, "a row lights up under the cursor")
fire(needRows[1], "OnLeave")
check(visible(now.feedList) == 7 and feedRows[1].time.shown and feedRows[1].time.w == 44
  and feedRows[1].time.text == os.date("%H:%M", NOW - 50), "activity fills the column's height, each row led by a 44px time")
check(point(feedRows[1].text, 2) == "LEFT,56,0", "the text starts after the time column")
now:SetSize(976, 1000)
flush()
check(visible(now.feedList) == 10, "a taller column shows more of it")
check(feedRows[10].time.text == os.date("%a", NOW - 47 * 3600), "a row older than a day shows its weekday, not a time")
do
  local savedLog, many = BRutus.db.rosterLog, {}
  for i = 1, 14 do many[i] = { action = "join", target = "N" .. i, timestamp = NOW - i } end
  BRutus.db.rosterLog = { events = many }
  now.Refresh()
  check(visible(now.feedList) == 12, "however tall the column, at most 12 rows")
  BRutus.db.rosterLog = savedLog
  now.Refresh()
end
do
  local saved = { BRutus.db.rosterLog, BRutus.db.lootHistory, BRutus.db.milestones, BRutus.db.raidTracker }
  BRutus.db.rosterLog = { events = { { action = "join", target = "Late", timestamp = NOW - 23 * 3600 } } }
  BRutus.db.lootHistory, BRutus.db.milestones, BRutus.db.raidTracker = nil, nil, nil
  now.Refresh()
  check(feedRows[1].time.text == os.date("%H:%M", NOW - 23 * 3600), "23 hours ago still shows the time")
  BRutus.db.rosterLog, BRutus.db.lootHistory, BRutus.db.milestones, BRutus.db.raidTracker = saved[1], saved[2], saved[3], saved[4]
  now.Refresh()
end
now:SetSize(976, 520)
flush()

do
  local calls, real = 0, A.NeedsMe
  A.NeedsMe = function(self) calls = calls + 1; return real(self) end
  now:SetSize(900, 520)
  flush()
  now:SetSize(976, 520)
  flush()
  f:RefreshTitle()
  A.NeedsMe = real
  check(calls == 0, "resizing Now, and the title outside the bar, do not walk the officer work again")
end

do
  BRutus.RecruitScanner = { GetInbox = function() return { a = 1, b = 2, c = 3 } end }
  for _ = 1, 9 do nowTicker.fn() end
  check(needRows[5].text.text == "2 applicants waiting", "between refreshes the lists stay as they were")
  nowTicker.fn()
  check(needRows[5].text.text == "3 applicants waiting", "the tenth tick refreshes them")
  NOW = NOW + 60
  nowTicker.fn()
  check(now.clock.text == "4:11:38", "every tick moves the clock")
  NOW = NOW - 60
  check(now.events.GUILD_ROSTER_UPDATE, "Now listens for roster updates")
  BRutus.RecruitScanner = { GetInbox = function() return { a = 1, b = 2 } end }
  fire(now, "OnEvent", "GUILD_ROSTER_UPDATE")
  check(needRows[5].text.text == "2 applicants waiting", "and refreshes on one")
end

fire(needRows[3], "OnClick")
check(f.activeTab == "management" and selected[#selected] == "CreateManagementPanel:inactive",
  "a row opens its screen on its sub-tab")
check(nowTicker.cancelled, "leaving Now stops its clock")
BRutus.RecruitScanner = { GetInbox = function() return { a = 1, b = 2, c = 3, d = 4 } end }
fire(now, "OnEvent", "GUILD_ROSTER_UPDATE")
check(needRows[5].text.text == "2 applicants waiting", "off screen, a roster update does not refresh Now")
BRutus.RecruitScanner = { GetInbox = function() return { a = 1, b = 2 } end }
UI:OpenWindow("home")
fire(needRows[2], "OnClick")
check(f.activeTab == "guild" and selected[#selected] == "CreateGuildHub:calendar:" .. KARAZHAN,
  "the unanswered raid opens the calendar on the raid's day")
UI:OpenWindow("home")
fire(now.openCalendar, "OnClick")
check(f.activeTab == "guild" and selected[#selected] == "CreateGuildHub:calendar:" .. KARAZHAN,
  "so does the next raid's calendar button")
do
  local member
  function BRutus:ShowMemberDetail(d) member = d end
  BRutus.db.members["Caio-Firemaw"] = { name = "Caio" }
  UI:OpenWindow("home")
  fire(feedRows[7], "OnClick")
  check(f.activeTab == "roster" and member and member.name == "Caio", "a milestone row opens the roster and the member")
  UI:OpenWindow("home")
  fire(feedRows[1], "OnClick")
  check(f.activeTab == "management" and selected[#selected] == "CreateManagementPanel:log"
    and member == BRutus.db.members["Ana-Firemaw"], "a roster change opens the audit log and the member")
end

UI:OpenWindow("home")
officer = false
events[3].mine = { status = "yes" }
now.Refresh()
check(visible(now.needsList) == 1 and needRows[1].text.text == "All caught up" and not needRows[1].mark.shown
  and needRows[1].go == nil, "nothing to do: one empty line, not a button")
fire(needRows[1], "OnEnter")
check(not needRows[1].hover.shown, "and it does not light up under the cursor")
BRutus.db.rosterLog, BRutus.db.lootHistory, BRutus.db.milestones, BRutus.db.raidTracker = nil, nil, nil, nil
now.Refresh()
check(visible(now.feedList) == 1 and feedRows[1].text.text == "Nothing in the last 48 hours." and feedRows[1].go == nil,
  "no activity: one empty line")
roster = {}
now.Refresh()
check(visible(now.needsList) == 3 and needRows[1].bar.shown and not needRows[1].text.shown
  and needRows[1].bar.w == 180 and needRows[2].bar.w == 130 and needRows[3].bar.w == 160,
  "while the roster loads: static bars, not zeros")
roster = fullRoster
BRutus:SetFeatureEnabled("guild", false)
now.Refresh()
check(not now.openCalendar.shown, "no calendar button when the Guild tab is off")
BRutus:SetFeatureEnabled("guild", true)
events = {}
now.Refresh()
check(now.clock.text == "\226\128\148" and now.raidMeta.text == "No raid scheduled.", "no raid: a dash and one line")
officer = true

do
  local sync, activity = A.LastSync, A.Activity
  A.LastSync = function() error("sync exploded") end
  A.Activity = function() error("activity exploded") end
  check(pcall(f.RefreshTitle, f) and pcall(now.Refresh), "a module that raises does not break the title or Now")
  A.LastSync, A.Activity = sync, activity
end

f:Hide()
do
  local running = 0
  for _, tk in ipairs(tickers) do if not tk.cancelled then running = running + 1 end end
  check(running == 0, "a hidden window runs no timers")
end

-- A Now tab that failed to build is not retried each time the window narrows.
do
  local real = UI.features.home.build
  UI.features.home.build = function() error("no now") end
  BRutus.RosterFrame, BRutus.db.settings.window = nil, nil
  local broken = UI:GetMainWindow()
  broken:Show()
  resize(broken, 1000, 620)
  printed = {}
  resize(broken, 500)
  resize(broken, 1000)
  resize(broken, 500)
  check(broken.band == "watch" and not said("could not start"), "a Now tab that failed to build is refused once, not on every narrowing")
  UI.features.home.build = real
  broken:Hide()
end

-- The calendar filter, through the real Guild tab and the real calendar.
do
  dofile(ADDON .. "/UI/CommunityPanel.lua")
  BRutus.RosterFrame, BRutus.db.settings.window = nil, nil
  local win = UI:GetMainWindow()
  local when = os.time({ year = 2026, month = 1, day = 15, hour = 21 })
  check(UI:OpenWindow("guild", "calendar", when), "a deep link with a day opens the real Guild tab")
  local guild = win.tabPanels.guild
  local calPanel = guild.subPanels and guild.subPanels.calendar and guild.subPanels.calendar.panel
  local cal
  for _, c in ipairs(calPanel and calPanel.children or {}) do if c.Render then cal = c end end
  check(guild.activeSub == "calendar" and calPanel.shown and cal ~= nil, "on its calendar")
  local bar
  for _, c in ipairs(guild.children) do if c.bg then bar = c end end
  local subTabs, open = 0, nil
  for _, c in ipairs(bar and bar.children or {}) do
    if c.underline then
      subTabs = subTabs + ((c.underline.h == 1) and 1 or -100)
      if c.isActive then open = c end
    end
  end
  check(bar and bar.h == 28 and same(bar.bg.color, C.panel), "the Guild tab's sub-tab bar is 28px on panel")
  check(subTabs == 4 and open and open.label.text == "Calendar" and open.underline.shown,
    "its four sub-tabs carry a 1px gold rule, shown under the open one")
  check(cal.viewYear == 2026 and cal.viewMonth == 1 and cal.selectedKey == 20260115,
    "showing the raid's month, with its day selected")
  local function drawn(text)
    for _, c in ipairs(cal.children) do
      if c.kind == "FontString" and c.text == text then return true end
    end
    return false
  end
  check(drawn(os.date("%b %Y", os.time({ year = 2026, month = 1, day = 1, hour = 12 })))
    and drawn(os.date("%A, %d %b %Y", os.time({ year = 2026, month = 1, day = 15, hour = 12 }))),
    "and drawn: that month's name and the day's heading")
  UI:OpenWindow("guild", "calendar")
  check(cal.selectedKey == 20260115, "opening the calendar without a day leaves the selection alone")
  win:Hide()
end

do
  BRutus.RosterFrame, BRutus.db.settings.window = nil, nil
  local edge = UI:GetMainWindow()
  edge:Show()
  resize(edge, 620, 620)
  check(edge.titleBar.h == 30 and point(edge.content, 1) == "TOPLEFT,12,-70" and edge.band == "narrow",
    "at exactly 620px: the 30px title bar, 12px padding, and 596px of content, so narrow")
  edge:Hide()
end

-- ── What is gone, and who opens what ────────────────────────────────────
do
  local toc = read("GuildOS.toc")
  check(not toc:find("Hub.lua", 1, true) and toc:find("UI\\Agora.lua", 1, true), "the hub is out of the TOC and Now is in it")
  local sources = {}
  for line in toc:gmatch("[^\r\n]+") do
    if line:match("%.lua$") and not line:match("^Libs") and not line:match("^#") then
      sources[#sources + 1] = read((line:gsub("\\", "/")))
    end
  end
  local all = table.concat(sources, "\n")
  for _, stale in ipairs({ "UI.Hub", "ToggleExpanded", "BRutusRosterFrame", '"GuildOSHub"', "UI:CreateWindow(",
    "UI:ToggleWindow(", "UI:CloseAllWindows(", "UI:IsWindowOpen(", "UI:RaiseWindow(", 'VisibleFeatures("hub")', "def.hub" }) do
    check(not all:find(stale, 1, true), "nothing refers to " .. stale)
  end
  for _, p in ipairs({ "UI/ManagementPanel.lua", "UI/AuditPanel.lua", "UI/RaidToolsPanel.lua", "UI/CommunityPanel.lua",
    "UI/AlliancePanel.lua" }) do
    check(read(p):find("parent.SelectSub = selectSub", 1, true), p .. " exposes its sub-tabs")
  end
  local rf = read("UI/RosterFrame.lua")
  check(rf:find("root.SelectSub = selectSub", 1, true) and rf:find("container.SelectSub = SetSubTab", 1, true),
    "recruitment and raids expose their sub-tabs")
  check(rf:find("local SUB_H = 28", 1, true), "the Raids sub-tab bar is 28px like the others")
  -- Building these panels would pull in most of the addon; their bars are checked where they are made.
  for _, bars in ipairs({
    { "UI/ManagementPanel.lua", "local TAB_H = 28", "    bar:SetSize(400, TAB_H)\n    UI:StyleSubTabBar(bar)\n", "UI:CreateTab(bar, t.label, TAB_MIN_W, true)" },
    { "UI/AuditPanel.lua", "    bar:SetHeight(28)\n    UI:StyleSubTabBar(bar)\n", "UI:CreateTab(bar, t.label, 130, true)" },
    { "UI/RaidToolsPanel.lua", "    bar:SetHeight(28)\n    UI:StyleSubTabBar(bar)\n", "UI:CreateTab(bar, t.label, 130, true)" },
    { "UI/AlliancePanel.lua", "    bar:SetSize(400, 28)\n    UI:StyleSubTabBar(bar)\n", "UI:CreateTab(bar, t.label, TAB_MIN_W, true)" },
    { "UI/RosterFrame.lua", "    bar:SetSize(300, 28)\n    UI:StyleSubTabBar(bar)\n", "UI:CreateTab(bar, t.label, 90, true)" },
    { "UI/RosterFrame.lua", "subBar:SetHeight(SUB_H)", "    UI:StyleSubTabBar(subBar)\n", "UI:CreateTab(subBar, st.label, 110, true)" },
  }) do
    local src = read(bars[1]):gsub("\r\n", "\n")
    local ok = true
    for i = 2, #bars do if not src:find(bars[i], 1, true) then ok = false end end
    check(ok, bars[1] .. ": a 28px sub-tab bar on panel, its tabs with the 1px rule (" .. bars[#bars] .. ")")
  end
  check(read("UI/CommunityPanel.lua"):find("info.panel.ApplyFilter", 1, true)
    and read("UI/CalendarPanel.lua"):find("panel.ApplyFilter = function(when)", 1, true),
    "the Guild tab hands a deep link's day to the calendar")
  check(read("UI/Dashboard.lua"):find("UI:OpenWindow(tabKey, subKey)", 1, true), "the home cards open tabs through OpenWindow")
end

-- ── In-game self-tests that need no live client ─────────────────────────
UI:RegisterFeature({ id = "nobuild", label = "No build", order = 999 })
check(not selftests["features.invariants"](), "the registry refuses a tab with nothing to build")
UI.features.nobuild = nil
table.remove(UI.featureOrder)
for _, name in ipairs({ "features.invariants", "features.unique_ids", "features.core_cannot_be_disabled",
  "window.geometry_roundtrip", "ui.titlebar_button_outranks_bar" }) do
  local ok, why = selftests[name]()
  check(ok, "selftest " .. name .. ": " .. tostring(why))
end

print(("window-shell: %d checks passed"):format(checks))
