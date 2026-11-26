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
-- A check button, as the Guild tab's Call to Arms settings draw (issue #108).
function Frame:SetChecked(v) self.checked = v and true or nil end
function Frame:GetChecked() return self.checked end
function Frame:SetMaxBytes(n) self.maxBytes = n end
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
function Frame:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:SetBackdrop(b) self.backdrop, self.backdropInfo = b, b end
function Frame:GetBackdropColor() if self.bg then return unpack(self.bg) end end
function Frame:GetBackdropBorderColor() end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:SetAtlas(name) self.atlas = name end
function Frame:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
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
function Frame:SetVerticalScroll(v) self.vscroll = v end
function Frame:GetVerticalScroll() return self.vscroll or 0 end
function Frame:GetVerticalScrollRange()
  local c = self.scrollChild
  return c and math.max(0, (c.h or 0) - (self.h or 0)) or 0
end
function Frame:SetHyperlinksEnabled(v) self.hyperlinks = v end
function Frame:EnableMouse(v) self.mouse = v end
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
function Frame:IsEnabled() return self.disabled ~= true end
function Frame:Enable() self.disabled = nil end
function Frame:Disable() self.disabled = true end
function Frame:SetFocus() self.focused = true end
function Frame:HasFocus() return self.focused == true end
function Frame:IsMouseOver() return false end
for _, name in ipairs({ "SetClampedToScreen", "RegisterForClicks", "Raise",
  "SetBackdropBorderColor", "SetTexture", "SetTexCoord", "SetBlendMode", "SetAlpha", "SetShadowOffset",
  "SetShadowColor", "SetJustifyH", "SetWordWrap", "SetTextInsets", "SetAutoFocus", "SetMaxLetters", "ClearFocus",
  "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetMultiLine", "SetHorizTile", "SetVertTile",
  "HighlightText" }) do
  Frame[name] = function() end
end
function Frame:SetTexture(t) self.texture = t end

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
-- Each read is a minute after the last, so no roster update here is held as part of a burst
-- (GuildOS:Coalesce, issue #324; tools/coalesce.lua tests the holding).
local clock = 0
function GetTime() clock = clock + 60; return clock end
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
local hooks = {}
function hooksecurefunc(name, fn) hooks[name] = fn end
function debugstack() return "" end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
-- The face a text should have: the Forever style draws every text in the game's font (#122).
local function face() return STANDARD_TEXT_FONT end   -- the game's font on every client since #445
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_GuildInfo = { GuildRoster = function() end }
function UnitName() return "Ana" end
local canInvite = true
function CanGuildInvite() return canInvite end
function GuildInvite() end
GuildFrame = newFrame("Frame", UIParent)
GuildFrame:Hide()
function ToggleGuildFrame() end
function InCombatLockdown() return false end
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
GuildOS.SelfTest = { Register = function(_, name, fn) selftests[name] = fn end }
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
-- tools/window-shell-forever.lua runs this whole harness again under the Forever style (#122).
if STYLE == "forever" then
  local atlases = {}
  for line in io.lines(ADDON .. "/tools/data/forever-atlas-elements.txt") do
    if not line:find("^#") then atlases[(line:gsub(" %*$", "")):lower()] = true end
  end
  C_Texture = { GetAtlasInfo = function(n) return atlases[tostring(n):lower()] and { width = 32, height = 32 } or nil end }
  GuildOSDB.style = "forever"
end
GuildOS.Style:Resolve()
dofile(ADDON .. "/Core/Commands.lua")
dofile(ADDON .. "/UI/Helpers.lua")
-- Core/Utils.lua's UTF-8 head; this harness loads Utils further down. The calendar editor's kind
-- buttons shorten a long label with it (#371).
function GuildOS:Utf8Head(s, n) return tostring(s):sub(1, n) end
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Rooms.lua")
local UI, C = GuildOS.UI, GuildOS.Colors
-- A tab this client does not support, and one whose panel raises while building.
UI:RegisterFeature({ id = "tbcOnly", label = "TBC only", order = 200, tbc = true, build = function() end })
UI:RegisterFeature({ id = "boom", label = "Boom", order = 210, build = function() error("boom") end })
dofile(ADDON .. "/UI/Window.lua")
dofile(ADDON .. "/UI/Agora.lua")
dofile(ADDON .. "/UI/Salao.lua")
dofile(ADDON .. "/UI/CalendarPanel.lua")
dofile(ADDON .. "/UI/Minimap.lua")
dofile(ADDON .. "/UI/Features.lua")
local A = UI.Agora
check(not GuildOS.Client.isAnniversary, "the stub client is not TBC Anniversary")

function GuildOS:TimeAgo(ts) return "T" .. (NOW - ts) end
local events = {}
GuildOS.Calendar = {
  GetUpcoming = function() return events end,
  GetComposition = function(_, e) return { yes = e.yes or 0 } end,
  MyRsvp = function(_, e) return e.mine end,
  GetEvents = function() return {} end,
  CreatableKinds = function() return { "RAID" } end,   -- the kinds this rank creates (#308)
}

-- Panel builders record what they built and, where the real one does, expose
-- SelectSub and record the sub-tab and filter it was given.
local built, selected = {}, {}
local function builder(name, withSub)
  GuildOS[name] = function(_, c)
    built[name] = (built[name] or 0) + 1
    if withSub then
      c.SelectSub = function(sub, filter)
        selected[#selected + 1] = name .. ":" .. sub .. (filter ~= nil and (":" .. tostring(filter)) or "")
      end
    end
  end
end
-- The Loot window took the Loot, DKP and Wishlist tabs' panels (issue #346), with sub-tabs. The
-- Recruitment tab took Trials, the Guild tab Journal and Achievements (issue #367).
for _, n in ipairs({ "CreateRosterPanel",
  "CreateRecipesPanel", "CreateWebPanel", "CreateSettingsPanel" }) do
  builder(n)
end
for _, n in ipairs({ "CreateRaidHubPanel", "CreateGuildHub", "CreateAlliancePanel", "CreateRecruitmentPanel",
  "CreateManagementPanel", "CreateLootWindow" }) do
  builder(n, true)
end

local function tabOf(f, key)
  for _, t in ipairs(f.tabs) do if t.key == key then return t end end
end
-- A feature is reachable when some room the bar shows opens it (the rooms, #445).
local function listed(_, key)
  for _, room in ipairs(UI:VisibleRooms()) do
    for _, e in ipairs(UI:RoomEntries(room.id)) do if e.feature == key then return true end end
  end
  for _, e in ipairs(UI:RoomEntries("settings")) do if e.feature == key then return true end end
  return false
end
local function allowedCount()
  return #UI:VisibleRooms()
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
GuildOS.db = { settings = { modules = {} }, members = {}, calendar = { events = {} } }
local slash = SlashCmdList.GUILDOS
local aliases = {}
for key, fn in pairs(SlashCmdList) do if fn == slash then aliases[#aliases + 1] = key end end
check(slash and #aliases == 1 and aliases[1] == "GUILDOS" and SLASH_GUILDOS1 == "/guildos" and SLASH_GUILDOS2 == "/gos",
  "/guildos and /gos open the window, and no other command does (#120)")

local finder = false
function GuildOS:ShowRecruitInbox() finder = true end
inGuild = false
slash("")
check(finder and GuildOS.RosterFrame == nil, "guildless: /gos opens the recruitment finder, not the window")
inGuild = true

slash("")
local f = GuildOS.RosterFrame
flush()
check(f and f:IsShown() and f.name == "GuildOSWindow", "/gos opens the one window")
check(f.w == 1000 and f.h == 620 and f.points[1][1] == "CENTER", "no saved geometry: 1000×620, centred")
check(f.resizeBounds and f.resizeBounds[1] == 320 and f.resizeBounds[2] == 28, "resizable down to 320×28")
check(f.grip.w == 16 and f.grip.h == 16 and point(f.grip) == "BOTTOMRIGHT,-3,3", "from a 16×16 grip in the corner, inside the 3px metal frame")
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
check(f.activeTab == "home" and f.activeRoom == "salao" and tabOf(f, "salao").label.text == "Salão",
  "it opens on the Salão's Home (#445)")
check(f.tabs[1].key == "salao" and UI:GetFeature("home").core,
  "the Salão is the first room, and Home is core: it cannot be switched off, so the fall-back always exists")
check(GuildOS:IsFrontDoorShown(), "the guild-frame hook sees the window open")
local esc = false
for _, n in ipairs(UISpecialFrames) do if n == "GuildOSWindow" then esc = true end end
check(esc, "Escape closes the window")
slash("")
check(not f:IsShown() and not GuildOS:IsFrontDoorShown(), "/gos again closes it")

GuildOS:CreateMinimapButton()
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
GuildOS:HookGuildFrame()
check(type(hooks.ToggleGuildFrame) == "function", "the guild key is hooked after Blizzard's toggle, not replaced")
-- The guild key as the game runs it: Blizzard's toggle shows its frame when hidden and hides it
-- when shown, and the hook runs after. Guild OS hid that frame, so the next press shows it again.
local function pressJ()
  if GuildFrame:IsShown() then GuildFrame:Hide() else GuildFrame:Show() end
  hooks.ToggleGuildFrame()
end
pressJ()
check(not GuildFrame:IsShown() and f:IsShown(), "the guild key opens Guild OS in place of Blizzard's frame")
pressJ()
check(not f:IsShown() and not GuildFrame:IsShown(), "and the next press closes it, Blizzard's frame too (issue #66)")
pressJ()
check(f:IsShown(), "and the one after opens it again")
pressJ()
check(not f:IsShown(), "and closes it again")
-- In combat the game will not let an addon hide Blizzard's frame: the key opens that one alone (#261).
local inCombat = InCombatLockdown
InCombatLockdown = function() return true end
pressJ()
check(GuildFrame:IsShown() and not f:IsShown(), "in combat the guild key opens Blizzard's frame alone, never both")
pressJ()
check(not GuildFrame:IsShown() and not f:IsShown(), "and the next press closes it")
InCombatLockdown = inCombat
local native
for _, c in ipairs(GuildFrame.children) do if c.kind == "Button" and c.text == "Guild OS" then native = c end end
check(native ~= nil, "Blizzard's guild frame carries a Guild OS button")
fire(native, "OnClick")
check(f:IsShown(), "which opens the window")

check(BINDING_HEADER_GUILDOS == "Guild OS" and BINDING_NAME_GUILDOS_TOGGLE == "Open or close Guild OS",
  "the key binding is labelled")
local bindings = read("Bindings.xml")
check(bindings:find('name="GUILDOS_TOGGLE"', 1, true) and bindings:find('category="ADDONS"', 1, true)
  and bindings:find("GuildOS:ToggleRoster()", 1, true), "the key binding, in the AddOns category, opens the window")
check(read("Modules/Digest.lua"):find("GuildOS:ToggleRoster()", 1, true)
  and read("UI/Onboarding.lua"):find('OpenWindow("settings")', 1, true),
  "the digest and onboarding open the window through the same calls")

do
  local refreshed = 0
  f.RefreshRoster = function() refreshed = refreshed + 1 end
  GuildOS:RefreshRosterUI()
  check(refreshed == 1, "the roster refreshes while the window is up")
  f:Hide()
  GuildOS:RefreshRosterUI()
  check(refreshed == 1, "and not while it is closed")
  f.RefreshRoster = nil
end

slash("open management inactive")
check(f:IsShown() and f.activeTab == "management" and selected[#selected] == "CreateManagementPanel:inactive",
  "/gos open reaches the tab and its sub-tab (the hub's link was ignored)")
check(GuildOS.db.settings.window.tab == "management", "an opened tab is remembered")
slash("banlist")
check(selected[#selected] == "CreateManagementPanel:ban", "/gos banlist lands on the ban list")
slash("calendar")
check(f.activeTab == "guild" and selected[#selected] == "CreateGuildHub:calendar", "/gos calendar lands on the calendar")
check(built.CreateManagementPanel == 1 and built.CreateGuildHub == 1, "each panel builds once, the first time it opens")
-- Trials, Journal and Achievements are sub-tabs since issue #367: their names open the tab that hosts
-- them, on their sub-tab.
slash("open trials")
check(f.activeTab == "recruitment" and selected[#selected] == "CreateRecruitmentPanel:trials",
  "/gos open trials opens Recruitment on its Trials sub-tab")
slash("open journal")
check(f.activeTab == "guild" and selected[#selected] == "CreateGuildHub:journal",
  "/gos open journal opens Guild on its Journal sub-tab")
check(UI:OpenWindow("achievements") and f.activeTab == "guild" and selected[#selected] == "CreateGuildHub:achievements",
  "and Achievements on its own")
check(built.CreateGuildHub == 1 and built.CreateRecruitmentPanel == 1, "through the one panel each tab builds")
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
for _, id in ipairs({ "trials", "journal", "achievements" }) do
  check(tabOf(f, id) == nil and not UI:GetFeature(id).tab and UI:GetFeature(id).opens,
    id .. " has no tab of its own: it is a sub-tab (#367)")
end
check(UI:GetFeature("trials").opens[1] == "recruitment" and UI:GetFeature("trials").opens[2] == "trials"
  and UI:GetFeature("trials").officerOnly, "Trials is Recruitment's, for officers")
for _, id in ipairs({ "journal", "achievements" }) do
  local d = UI:GetFeature(id)
  check(d.opens[1] == "guild" and d.opens[2] == id and d.tbc == false and d.retail == false,
    id .. " is Guild's, on WoW: Forever only")
end
check(UI:GetFeature("journal").restart, "the journal still asks for a reload when switched")

GuildOS:SetFeatureEnabled("recipes", false)
printed = {}
check(not UI:OpenWindow("recipes") and said("Crafts is disabled in Settings."), "a disabled feature refuses, saying why")
check(not listed(f, "recipes"), "a disabled feature has no tab")
GuildOS:SetFeatureEnabled("recipes", true)
check(listed(f, "recipes"), "switching it back on brings the tab back")

GuildOS.State.startup.failedFeatures.alliance = "Alliance"
f:UpdateTabVisibility()
printed = {}
check(not UI:OpenWindow("alliance") and said("Alliance could not start on this client."), "a failed feature refuses, saying why")
check(not listed(f, "alliance"), "a feature whose module failed to start has no tab")
GuildOS.State.startup.failedFeatures.alliance = nil

officer = false
f:UpdateTabVisibility()
printed = {}
check(not UI:OpenWindow("management") and said("Leadership is officer-only."), "an officer-only tab refuses a member")
check(not listed(f, "management"), "a member sees no officer tabs")
check(not UI:IsFeatureAllowed(UI:GetFeature("trials")), "nor the officers' Trials sub-tab")
printed = {}
check(not UI:OpenWindow("trials") and said("Trials is officer-only."), "and /gos open trials tells a member why")
-- The Loot window is every member's since issue #346 (it was officer-only): a raider reads the rule.
check(listed(f, "loot") and UI:IsFeatureAllowed(UI:GetFeature("loot")), "a member has the Loot tab")
officer = true
f:UpdateTabVisibility()

-- A tab this client does not have says so, not that it is officer-only (issue #177).
-- Every tab is retail's since issue #185, so one is marked `retail = false` for the check.
GuildOS.Client.isRetail = true
UI:GetFeature("dkp").retail = false
printed = {}
check(not UI:OpenWindow("dkp") and said("Not available on this client."), "a tab retail does not have says it is not on this client")
UI:GetFeature("dkp").retail = nil
-- The loot tab is retail's since issue #183, the DKP and wishlist tabs since issue #185.
for _, id in ipairs({ "loot", "dkp", "wishlist" }) do
  check(not UI:IsFeatureAbsent(UI:GetFeature(id)), "the " .. id .. " tab is on retail")
end
GuildOS.Client.isRetail = nil

do
  local before = f.activeTab
  printed = {}
  check(not UI:OpenWindow("boom") and said("Boom could not start on this client."), "a tab that raises while building refuses")
  check(f.activeTab == before, "and leaves the open tab alone")
  check(GuildOS.State.startup.failed["Tab:boom"], "and /guildos errors lists it as Tab:boom")
end

UI:OpenWindow("management")
GuildOS:SetFeatureEnabled("management", false)
check(f.activeTab == "home" and not f.tabPanels.management.shown and f.tabPanels.home.shown,
  "switching off the open tab's feature falls back to Now")
GuildOS:SetFeatureEnabled("management", true)

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
local g = GuildOS.db.settings.window
check(g.left == 300 and g.top == 700 and g.w == 1000 and g.h == 620, "dragging the title bar saves where the window is")

UI:OpenWindow("raids")
f:Hide()
GuildOS.RosterFrame = nil   -- /reload
f = UI:GetMainWindow()
check(point(f) == "TOPLEFT,300,700" and f.w == 1000 and f.h == 620, "after /reload the window is where it was, at its size")
check(f.activeTab == "raids", "and on the tab it was left on")

GuildOS.db.settings.window = { left = 1200, top = 1000, w = 1000, h = 620 }
GuildOS.RosterFrame = nil
f = UI:GetMainWindow()
check(point(f) == "TOPLEFT,600,900", "a saved spot hanging off the screen is pulled back on")

GuildOS.db.settings.window, GuildOS.db.settings.uiScale = nil, 2
GuildOS.RosterFrame = nil
f = UI:GetMainWindow()
check(f.scale == 2 and f.w == 800 and f.h == 450, "the UI scale applies, and the default size fits the scaled screen")
-- Its border is sized after the scale, not before (#369): 0.5 makes 1 unit 0.7 of a 1080p pixel.
PixelUtil = { GetNearestPixelSize = function(units, scale, min)
  local factor = 768 / 1080
  return math.max(min or 0, math.floor(units * scale / factor + 0.5)) * factor / scale
end }
GuildOS.db.settings.uiScale = 0.5
GuildOS.RosterFrame = nil
f = UI:GetMainWindow()
check(f.__look and f.__look.fill and f.__edge3 == 3, "the window is the Salão's metal frame, 3px, drawn from its art (#449)")
PixelUtil = nil
GuildOS.db.settings.uiScale = 1.1
UI:ApplyScale()
check(f.scale == 1.1, "changing the UI scale rescales the window")
GuildOS.db.settings.uiScale = nil
GuildOS.db.settings.window = nil
GuildOS.RosterFrame = nil
f = UI:GetMainWindow()
f:Show()
resize(f, 1000, 620)
g = GuildOS.db.settings.window

-- ── Title bar, footer, refresh (the mockup's .bar and .foot, #449) ─────
check(f.band == "full" and f.titleBar.h == 50, "at 1000px the title bar is 50px")
do
  local F = GuildOS.Fonts
  check(f.crest.shown and f.crest.letter.text == "C" and f.crest.orb.texture:find("Salao\\orb.tga", 1, true),
    "left: the round crest with the guild's initial")
  check(f.nameText.text == "Chama" and f.nameText.font.file == F.title and same(f.nameText.color, C.gold),
    "the guild's name in Cinzel and gold")
  check(f.titleBar.__styleBg and f.titleBar.__styleBg.texture:find("titlebar.tga", 1, true), "the bar's warm gradient")
  check(same(f.metaText.color, C.textSoft) and f.metaText.font.file == F.ui and same(f.syncText.color, C.label),
    "the line under the name in the soft ink, the sync line in the footer's")
  local label = tabOf(f, "members").label
  check(label.font.file == F.ui and label.font.size >= 13, "a door's name is Alegreya Sans")
  check(tabOf(f, "members").parent == f.rule and f.rule.parent == f.titleBar, "the rooms are doors in the title bar")
  check(f.barLine.h == 2 and same(f.barLine.color, C.lineHi), "a 2px metal line under the title bar")
  local footLine
  for _, c in ipairs(f.footer.children) do if c.kind == "Texture" and c.h == 1 then footLine = c end end
  check(footLine and same(footLine.color, C.lineHi), "and a 1px metal line above the footer")
end
fire(f.closeButton, "OnClick")
check(not f:IsShown(), "× closes the window")
f:Show()
flush()
check(f.metaText.shown and f.metaText.text == "2 online", "under the name: who is online")
check(f.welcomeText.text == "Welcome back, Ana.", "the footer welcomes the player")
GuildOS.db.members = { a = { lastSync = NOW - 300 }, b = { lastSync = NOW - 60 }, c = "junk" }
f:RefreshTitle()
check(f.syncText.shown and f.syncText.text == "Updated: T60" and f.syncDot.shown, "right: the newest sync time, by its dot")
GuildOS.db.members = {}
f:RefreshTitle()
check(f.syncText.text == "not synced yet", "before any sync it says so")
check(f.minimise.x.text == "\226\128\148" and f.closeButton.shown and point(f.closeButton) == "RIGHT,-10,0"
  and f.closeButton.orb, "then the fold and the round close button at the right edge")
check(point(f.settingsButton) == "RIGHT,-6,0" and f.settingsButton.points[1][2] == f.minimise, "Settings left of the fold")
check(point(f.content, 1) == "TOPLEFT,15,-99" and point(f.content, 2) == "BOTTOMRIGHT,-15,39",
  "content padding 12px inside the frame, under the 50px bar and the Salão's 34px strip, above the 24px footer")
check(point(f.footer, 1) == "BOTTOMLEFT,3,3" and point(f.titleBar, 1) == "TOPLEFT,3,-3",
  "the footer and the title bar inside the 3px metal frame")

check(f.events.GROUP_ROSTER_UPDATE and f.events.RAID_ROSTER_UPDATE and f.events.PARTY_LOOT_METHOD_CHANGED
  and f.events.GUILD_ROSTER_UPDATE, "the window listens for group, raid, loot-method and roster changes")
do
  local titleTicker = liveTicker(10)
  check(titleTicker ~= nil, "while shown, the title refreshes every 10s")
  roster[2][2] = true
  titleTicker.fn()
  check(f.metaText.text == "3 online", "and the tick picks up who came online")
  roster[2][2] = false
  fire(f, "OnEvent", "GUILD_ROSTER_UPDATE")
  check(f.metaText.text == "2 online", "so does a roster update")
  f:Hide()
  roster[2][2] = true
  fire(f, "OnEvent", "GUILD_ROSTER_UPDATE")
  check(f.metaText.text == "2 online", "closed, the window does not refresh on a roster update")
  roster[2][2] = false
  f:Show()
  flush()
  officer = false
  fire(f, "OnEvent", "GROUP_ROSTER_UPDATE")
  check(not listed(f, "management"), "a group change re-checks the tabs")
  officer = true
  fire(f, "OnEvent", "PARTY_LOOT_METHOD_CHANGED")
  check(listed(f, "management"), "so does a loot-method change")
  roster = {}
  f:RefreshTitle()
  check(f.metaText.text == "\226\128\148", "while the roster loads, a dash instead of 0 online")
  roster = fullRoster
  f:RefreshTitle()
end

-- The title bar's tools (#449): round Search and Settings beside the fold, children of the bar so its drag
-- does not eat their clicks. The sync moved to the footer's "Updated" line; the footer's links went: the site
-- and /gos help are in the gear's tooltip and on Settings' Data page, the Blizzard window a button there.
local tip = {}
GameTooltip = { SetOwner = function() tip = {} end, AddLine = function(_, t) tip[#tip + 1] = t end,
                Show = function() end, Hide = function() end, SetText = function(_, t) tip[#tip + 1] = t end }
do
  local search, gear = f.searchButton, f.settingsButton
  check(search.parent == f.titleBar and gear.parent == f.titleBar and search.level > f.titleBar.level
    and gear.level > f.titleBar.level, "Search and Settings are the title bar's children, above it, so a click is theirs")
  check(search.w == 28 and gear.w == 28 and search.icon.texture:find("icon-search", 1, true)
    and gear.icon.texture:find("icon-gear", 1, true), "as round 28px tools with their icons")
  check(point(search) == "RIGHT,-6,0" and search.points[1][2] == gear, "Search left of Settings")
  fire(gear, "OnEnter")
  local said2 = table.concat(tip, "|")
  check(said2:find("Settings", 1, true) and said2:find("guildos.me", 1, true) and said2:find("/gos help", 1, true),
    "the gear's tooltip names the site and /gos help: " .. said2)
  fire(gear, "OnLeave")
  fire(f.settingsButton, "OnClick")
  check(f.activeTab == "settings" and f.activeRoom == "settings", "Settings opens Settings, which is no room on the bar")
  fire(tabOf(f, "salao"), "OnClick")
  check(f.activeRoom == "salao", "and the Salão's door brings the window back")
  local ran, real = {}, { GuildOS.Search, GuildOS.CommSystem }
  GuildOS.Search = { Show = function() ran.search = true end }
  GuildOS.CommSystem = { FullSync = function() ran.sync = true end }
  fire(search, "OnClick")
  fire(f.syncButton, "OnClick")
  check(ran.search and ran.sync and f.syncButton.parent == f.footer, "Search opens the search; the footer's Updated line syncs")
  GuildOS.Search, GuildOS.CommSystem = real[1], real[2]
  -- The 10s tick and every roster update lay the bar out again: a tool is never hidden and shown again.
  local hides, hide = 0, search.Hide
  search.Hide = function(self) hides = hides + 1; return hide(self) end
  gear.Hide = search.Hide
  for _ = 1, 3 do f:RefreshTitle() end
  search.Hide, gear.Hide = nil, nil
  check(hides == 0 and search.shown and gear.shown, "refreshing the title hides neither tool (" .. hides .. ")")
end

-- The footer (#449): the welcome on the left, the sync line on the right, nothing else.
do
  local buttons, boxes = 0, 0
  for _, c in ipairs(f.footer.children) do
    if c.kind == "Button" then buttons = buttons + 1 end
    if c.kind == "EditBox" then boxes = boxes + 1 end
  end
  check(buttons == 1 and boxes == 0 and f.footItems == nil and f.versionText == nil,
    "no links, no copy box, no version: only the sync line is a button")
  check(point(f.welcomeText) == "LEFT,12,0" and point(f.syncText) == "RIGHT,-28,0", "welcome on the left, the sync line on the right")
  f:LayoutFooter(1000)
  local wide = f.welcomeText.w
  f.footReserve = 26
  f:LayoutFooter(1000)
  check(f.welcomeText.w == wide - 26, "the snow's parcel keeps its width free of the welcome")
  f.footReserve = nil
  f:LayoutFooter(150)
  check(not f.welcomeText.shown and f.syncText.shown, "too narrow, the welcome goes and the sync line stays")
  f:LayoutFooter(1000)
  check(f.welcomeText.shown, "and comes back")
end

-- ── The rooms on the rule (#445) ────────────────────────────────────────
check(shownTabs(f) == allowedCount(f) and not f.more.shown and #f.overflow == 0, "at 1000px every room fits")
do
  local x = 0
  for _, tab in ipairs(f.tabs) do
    if tab.shown then
      check(point(tab) == "BOTTOMLEFT," .. x .. ",2", tab.key .. " stands after the one before it, on the bar's line")
      check(tab.label.text == UI:RoomById(tab.key).label and tab.w >= 40, tab.key .. " shows its name, never an icon")
      x = x + tab.w + 1
    end
  end
  local open = tabOf(f, f.activeRoom)
  check(open.fill.shown and open.edge.shown and same(open.label.color, C.gold) and same(open.fill.color, C.wood),
    "the open door is raised in the wood, the metal round it, its name gold")
  local officers = tabOf(f, "officers")
  check(officers.count and same(officers.label.color, C.gold2), "the Officers' Room's name is the soft gold, with its count")
end
check(tabOf(f, f.activeRoom).isActive, "the open room carries the rule")
fire(tabOf(f, "members"), "OnClick")
check(f.activeTab == "roster" and f.activeRoom == "members" and g.tab == "roster" and g.room == "members" and tabOf(f, "members").isActive,
  "clicking a room opens its entry, marks it and remembers it")
check(not f.entryRow.shown, "a room with one entry draws no entries row")
fire(tabOf(f, "raids"), "OnClick")
check(f.entryRow.shown and f.activeRoom == "raids" and f.activeTab == "guild" and selected[#selected] == "CreateGuildHub:calendar",
  "Raids opens on its first entry, the calendar, with the row of its entries")
local raidsEntry
for _, b in ipairs(f.entryTabs) do if b.shown and b.entry.id == "sessions" then raidsEntry = b end end
fire(raidsEntry, "OnClick")
check(f.activeTab == "raids" and raidsEntry.isActive and g.entries.raids == "sessions" and selected[#selected] == "CreateRaidHubPanel:sessions",
  "an entry opens its panel on its sub-tab and is remembered")
fire(tabOf(f, "members"), "OnClick")
fire(tabOf(f, "raids"), "OnClick")
check(f.activeTab == "raids", "and the room opens again where it was left")
fire(tabOf(f, "members"), "OnClick")

resize(f, 890)
check(f.band == "full", "890px (content 866) is still full: 16px past the line before the band changes")
resize(f, 887)
check(f.band == "wide", "887px (content 863) is wide: the band is measured on the content, not the window")

resize(f, 600)
check(f.band == "compact" and f.titleBar.h == 50, "under 620px the title bar keeps its 50px")
check(point(f.content, 1) == "TOPLEFT,11,-61" and point(f.content, 2) == "BOTTOMRIGHT,-11,35", "and the padding 8px")
check(shownTabs(f) + #f.overflow == allowedCount(f), "every room is a door or behind »n")
check(f.more.shown and f.more.points[1][2] == f.rule, "»n stands after the last door")
check(f.more.variant == "ghost", "»n is a ghost button")
do
  local widths, active = {}, nil
  for _, tab in ipairs(f.tabs) do
    if UI:RoomAllowed(tab.key) then
      widths[#widths + 1] = tab:Width()
      if tab.key == f.activeRoom then active = #widths end
    end
  end
  local _, span = f:DoorSpan(600)
  local _, hidden = UI:FitTabs(widths, span, 1, 36, active)
  check(#f.overflow == hidden, "the fold is UI:FitTabs' answer")
end

-- ── Watch: the selector and the Salão ──────────────────────────────────
UI:OpenWindow("raids")
resize(f, 500)
check(f.band == "watch" and f.activeTab == "home" and f.activeRoom == "salao", "under 520px the content switches to the Salão's Home")
check(f.selector.shown and shownTabs(f) == 0 and not f.more.shown, "and the rooms become a one-line selector")
check(f.selector.label.text == "Salão \194\187", "the selector names the open room")
check(f.selector.variant == "ghost", "the selector is a ghost button")
check(g.tab == "raids", "the switch to Home is not remembered as a choice")
fire(f.selector, "OnClick")
check(#menuItems == allowedCount(f), "the selector lists every room")
do
  local salao
  for _, item in ipairs(menuItems) do if item.text == "Salão" then salao = item end end
  check(salao and salao.checked, "with the open one checked")
end
resize(f, 700)
check(f.band == "compact" and f.activeTab == "raids", "wide again, the screen that was open comes back")
check(not f.selector.shown and shownTabs(f) > 0, "and the rooms replace the selector")
-- Back from the narrow band: the room and the entry that were open, not just the feature (#445).
UI:OpenWindow("guild", "bulletin")
resize(f, 500)
check(f.activeTab == "home", "narrow, the Salão's Home again")
resize(f, 700)
check(f.activeRoom == "salao" and f.activeEntry.id == "bulletin" and selected[#selected] == "CreateGuildHub:bulletin",
  "wide again: the same room, entry and sub-tab, not the calendar")
-- The entries row folds into »n when it does not fit, as the rooms do.
fire(tabOf(f, "salao"), "OnClick")
resize(f, 430)
local entryShown = 0
for _, b in ipairs(f.entryTabs) do if b.shown then entryShown = entryShown + 1 end end
check(f.entryMore.shown and #f.entryOverflow > 0 and entryShown + #f.entryOverflow == #UI:RoomEntries("salao"),
  "a narrow window folds the Salão's entries into »n, none lost")
fire(f.entryMore, "OnClick")
check(#menuItems == #f.entryOverflow and menuItems[1].text == f.entryOverflow[1].label, "»n lists the folded entries")
resize(f, 700)
-- An officer demoted with the Officers' Room open leaves it.
UI:OpenWindow("recruitment")
check(f.activeRoom == "officers", "an officer's Recruitment is in the Officers' Room")
officer = false
f:UpdateTabVisibility()
check(f.activeRoom ~= "officers", "demoted, the window leaves the Officers' Room")
officer = true
f:UpdateTabVisibility()
-- One row only (#447): each screen's sub-tabs are its room's entries.
check(UI:OpenWindow("raids") and f.activeRoom == "raids" and f.activeEntry.id == "sessions"
  and selected[#selected] == "CreateRaidHubPanel:sessions", "Raids by name opens on its first sub-tab, Sessions")
local signupRan = false
local realSignup = GuildOS.ShowCoreSignupFrame
GuildOS.ShowCoreSignupFrame = function() signupRan = true end
local signupBtn
for _, b in ipairs(f.entryTabs) do if b.shown and b.entry.id == "signup" then signupBtn = b end end
if not signupBtn then
  fire(f.entryMore, "OnClick")
  for _, item in ipairs(menuItems) do if item.text == "Core Sign-up" then item.func() end end
else
  fire(signupBtn, "OnClick")
end
check(signupRan and f.activeTab == "raids" and f.activeEntry.id == "sessions",
  "Core Sign-up is an entry that opens the sign-up window and leaves the screen as it was")
GuildOS.ShowCoreSignupFrame = realSignup
officer = false
f:UpdateTabVisibility()
local coresListed = false
for _, e in ipairs(UI:RoomEntries("raids")) do if e.id == "cores" then coresListed = true end end
check(not coresListed, "a member's Raids has no Cores entry")
officer = true
f:UpdateTabVisibility()
resize(f, 1000, 620)
slash("open management inactive")
local sideActive
for _, b in ipairs(f.sideBtns) do if b.shown and b.isActive then sideActive = b end end
check(f.sideNav.shown and not f.entryRow.shown and sideActive and sideActive.entry.id == "inactive",
  "the Officers' Room lists its entries in a side bar, the open one marked")
check(f.content.points[#f.content.points - 1][2] > 12 or f.content.points[1][2] > 12, "and the content starts right of it")
-- The officers' work waiting (#449): a red count on the room's door and on the entry it opens.
do
  local realTT = GuildOS.TrialTracker
  GuildOS.TrialTracker = { CountReady = function() return 2 end }
  f:RefreshTitle()
  local door = tabOf(f, "officers")
  local trials
  for _, b in ipairs(f.sideBtns) do if b.shown and b.entry.id == "trials" then trials = b end end
  check(door.count.shown and door.count.text.text == "2" and trials and trials.count.shown and trials.count.text.text == "2",
    "two trials to review: a red 2 on the Officers' Room's door and on its Trials entry")
  GuildOS.TrialTracker = realTT
  f:RefreshTitle()
  check(not door.count.shown, "and none once there is nothing")
end
resize(f, 700, 620)
check(not f.sideNav.shown and f.entryRow.shown, "narrow, the side bar folds into the row: the content keeps its width")
resize(f, 1000, 380)
check(not f.sideNav.shown and f.entryRow.shown, "and so it does in a window too short for every row")
resize(f, 1000, 620)
check(f.sideNav.shown, "with room again, the side bar comes back")
-- A sub-tab the screen opens itself (a button inside it) is the entry the room marks and remembers.
f.tabPanels.management.OnSubChanged("ban")
check(f.activeEntry.id == "ban" and g.entries.officers == "ban", "a sub-tab opened from inside the screen moves the mark")
-- Switching screens is no choice of a sub-tab: the hub's old sub-tab showing on the way must not overwrite
-- another room's memory (the Guild hub lives in the Salão, Raids and the Chronicle).
do
  local guild = f.tabPanels.guild
  local realShown = guild.SetShown
  -- The stub fires no OnShow for children: the hub's left-over sub-tab reports itself as the client would.
  guild.SetShown = function(self, v)
    realShown(self, v)
    if v and f.switching ~= nil and guild.OnSubChanged then guild.OnSubChanged("bulletin") end
  end
  UI:OpenWindow("guild", "bulletin")
  fire(tabOf(f, "salao"), "OnClick")
  for _, b in ipairs(f.entryTabs) do if b.shown and b.entry.id == "home" then fire(b, "OnClick") end end
  check(g.entries.salao == "home", "the Salão remembers Home")
  UI:OpenWindow("guild", "calendar")
  check(g.entries.salao == "home" and f.activeEntry.id == "calendar",
    "opening Raids' Calendar leaves the Salão's memory alone")
  guild.SetShown = realShown
end
-- A deep link to a sub-tab this player may not open falls back to the screen's default.
officer = false
f:UpdateTabVisibility()
check(UI:OpenWindow("raids", "cores") and f.activeEntry.id == "sessions", "a member's link to Cores opens Sessions")
officer = true
f:UpdateTabVisibility()
resize(f, 700, 620)
resize(f, 500)
fire(f.selector, "OnClick")
for _, item in ipairs(menuItems) do if item.text == "Members" then item.func() end end
check(f.activeTab == "roster" and g.tab == "roster" and g.room == "members", "a room picked from the selector opens and is remembered")
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
check(f.minimise.x.text == "+" and point(f.closeButton) == "RIGHT,-18,0",
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
check(f.metaText.text == "3 online", "unfolding refreshes the title at once, not on the next tick")
roster[2][2] = false
fire(f.minimise, "OnClick")
f:Hide()
GuildOS.RosterFrame = nil   -- /reload
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
GuildOS.db.calendar = nil
check(A:NextRaid() == nil, "before Calendar has started there is no raid, and no error")
GuildOS.db.calendar = { events = {} }
check(A.Clock(4 * 3600 + 12 * 60 + 38) == "4:12:38" and A.Clock(2 * 86400 + 4 * 3600 + 5) == "2d 4h"
  and A.Clock(0) == "now", "the countdown reads h:mm:ss under a day, days and hours past it")
check(A.Short(4 * 3600 + 12 * 60) == "4h12" and A.Short(2 * 86400 + 3600) == "2d1h" and A.Short(59) == "1m"
  and A.Short(-5) == "now", "the bar's short form")
check(A:OnlineCount() == 2 and not A:RosterLoading(), "online counts the roster")
check(A:LastSync() == nil, "no sync, no time")

GuildOS.TrialTracker = {
  -- The trials ready to review, as TrialTracker:CountReady counts them (#249).
  CountReady = function() return 1 end,
}
GuildOS.GuildManager = {
  DEFAULT_INACTIVE_DAYS = 30,
  GetInactiveMembers = function() return { 1, 2, 3, 4 } end,
  GetSuggestions = function() return { trialsReady = { 1 }, promoteCandidates = { 1, 2 } } end,
}
-- The scanner's reply inbox: n replies that arrived at NOW (issue #311).
local function replies(n)
  local list = {}
  for i = 1, n do list[i] = { name = "R" .. i, msg = "hi", ts = NOW } end
  return { GetInbox = function() return list end }
end
GuildOS.RecruitScanner = replies(2)
do
  local needs = A:NeedsMe()
  check(#needs == 5, "an officer's five kinds of work")
  check(needs[1].text == "1 trial(s) ready to review" and needs[1].urgent and needs[1].id == "trials",
    "urgent first: the trials ready to review")
  check(needs[2].text == "You have not answered: Karazhan" and not needs[2].urgent and needs[2].id == "guild"
    and needs[2].sub == "calendar" and needs[2].filter == KARAZHAN, "an unanswered raid this week opens the calendar on its day")
  check(needs[3].text == "4 inactive over 30d" and needs[3].id == "management" and needs[3].sub == "inactive",
    "inactivity opens Leadership on inactivity")
  check(needs[4].text == "2 promotions to review" and needs[4].sub == "suggest",
    "suggestions open on suggestions and count promotions: a ready trial is already the trials row")
  check(needs[5].text == "2 applicants waiting" and needs[5].id == "recruitment" and needs[5].sub == "scanner",
    "applicants open the scanner")
end
-- Opening the inbox reads it: what was there stops waiting, a reply after it waits (issue #311).
do
  GuildOS.db.recruitScanner = { inboxReadAt = NOW }
  check(#A:NeedsMe() == 4, "replies the officer has seen are not applicants waiting")
  local seen = replies(2)
  local list = seen.GetInbox()
  list[#list + 1] = { name = "Late", msg = "still recruiting?", ts = NOW + 5 }
  GuildOS.RecruitScanner = seen
  local needs = A:NeedsMe()
  check(needs[5] and needs[5].text == "1 applicants waiting", "only a reply after the last look is waiting")
  GuildOS.RecruitScanner = { GetInbox = function() return { a = 1, b = 2 } end }
  GuildOS.db.recruitScanner = nil
  check(#A:NeedsMe() == 4, "an entry with no time is not an applicant")
  GuildOS.RecruitScanner = replies(2)
end
events[3].mine = { status = "yes" }
check(#A:NeedsMe() == 4, "an answered raid needs nothing")
events[3].mine, events[3].when = nil, NOW + 7 * 86400 - 1
check(#A:NeedsMe() == 5, "a raid just inside a week asks")
events[3].when = NOW + 7 * 86400 + 1
check(#A:NeedsMe() == 4, "just past a week it does not yet")
events[3].when = KARAZHAN
GuildOS:SetFeatureEnabled("trials", false)
check(A:NeedsMe()[1].id == "guild", "work for a screen that is switched off is left out")
GuildOS:SetFeatureEnabled("guild", false)
check(A:NeedsMe()[1].id == "management", "and an unanswered raid needs the Guild tab")
GuildOS:SetFeatureEnabled("guild", true)
GuildOS:SetFeatureEnabled("trials", true)
officer = false
check(#A:NeedsMe() == 1 and A:NeedsMe()[1].id == "guild", "a member only sees their own answer")
officer = true

GuildOS.db.members = { ["Ana-Firemaw"] = {}, ["Dora-Firemaw"] = {}, ["Bob-RealmA"] = {}, ["Bob-RealmB"] = {} }
GuildOS.db.rosterLog = { events = {
  { action = "join", target = "Dora", timestamp = NOW - 100 },
  { action = "promote", target = "Ana", detail = "Officer", timestamp = NOW - 50 },
  { action = "leave", target = "Eva", timestamp = NOW - 110 },
  { action = "kick", target = "Bob", timestamp = NOW - 120 },
  { action = "demote", target = "Caio", detail = "Member", timestamp = NOW - 130 },
  { action = "join", target = "Edge", timestamp = NOW - 47 * 3600 },
  { action = "join", target = "Old", timestamp = NOW - 49 * 3600 },
  { action = "note", target = "X", timestamp = NOW - 10 },
} }
GuildOS.db.lootHistory = {
  { player = "Beto", playerKey = "Beto-Firemaw", itemLink = "[Staff]", timestamp = NOW - 200 },
  { player = "Ancient", playerKey = "Ancient-Firemaw", itemLink = "[Relic]", timestamp = NOW - 50 * 3600 },
}
GuildOS.db.milestones = { events = {
  { type = "ding", key = "Caio-Firemaw", name = "Caio", detail = "70", ts = NOW - 300 },
  { type = "attune", key = "Ana-Firemaw", name = "Ana", ts = NOW - 310 },
} }
GuildOS.db.raidTracker = { sessions = { s1 = { name = "Karazhan", startTime = NOW - 3 * 3600, endTime = NOW - 400 } } }
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
  check(mine[1].id == "roster" and mine[1].sub == nil and mine[6].id == "loot",
    "a member's rows open the roster where the owner is officer-only, and loot the Loot window, every member's since #346")
  officer = true

  local saved = { GuildOS.db.rosterLog, GuildOS.db.lootHistory, GuildOS.db.milestones, GuildOS.db.raidTracker }
  local many = {}
  for i = 1, 14 do many[i] = { action = "join", target = "N" .. i, timestamp = NOW - i } end
  GuildOS.db.rosterLog, GuildOS.db.lootHistory, GuildOS.db.milestones, GuildOS.db.raidTracker = { events = many }, nil, nil, nil
  check(#A:Activity() == 12, "at most 12 rows of activity")
  GuildOS.db.rosterLog, GuildOS.db.lootHistory, GuildOS.db.milestones, GuildOS.db.raidTracker = saved[1], saved[2], saved[3], saved[4]
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

-- ── The Salão's Home (#445) ─────────────────────────────────────────────
UI:OpenWindow("home")
local home = f.tabPanels.home
home:SetSize(976, 520)
flush()
home.Refresh()
local cards = home.cards
check(cards and cards.forYou and cards.board and cards.fire and cards.wall, "Home builds its four cards")
local function shownRows(c)
  local out = {}
  for _, r in ipairs(c.rows) do if r.shown then out[#out + 1] = r end end
  return out
end
local you = shownRows(cards.forYou)
check(#you == 3, "For you holds three lines at most, of five things that need this officer")
check(you[1].main.text == "1 trial(s) ready to review" and you[1].btn.shown and you[1].btn.label.text == "Open",
  "the urgent one first, each with one action")
fire(you[1].btn, "OnClick")
check(f.activeTab == "recruitment" and selected[#selected] == "CreateRecruitmentPanel:trials" and f.activeRoom == "officers",
  "which opens the screen that owns it, in its room")
UI:OpenWindow("home")
local karaRow
for _, r in ipairs(cards.board.notes) do if r.shown and r.main.text == "Karazhan" then karaRow = r end end
check(karaRow and karaRow.side.shown and karaRow.side.text ~= "", "the notice board: the next events pinned, each with its time")
fire(karaRow, "OnClick")
check(f.activeTab == "guild" and f.activeRoom == "raids" and selected[#selected] == "CreateGuildHub:calendar:" .. KARAZHAN,
  "a click opens Raids › Calendar on that day")
UI:OpenWindow("home")
local faces = {}
for _, b in ipairs(cards.fire.faces) do if b.shown then faces[#faces + 1] = b end end
check(#faces == 1 and faces[1].name.text == "Caio", "by the fire: who is online, this player left out")
fire(faces[1], "OnClick")
check(menuItems[1] ~= nil, "a name opens the member's menu")
check(#shownRows(cards.wall) >= 1, "the guild wall shows what just happened")
check(not cards.chimney.shown, "no Winter Veil event, no Chimney")
check(cards.board.points[1][2] == 0 and cards.fire.points[1][2] > 0, "wide: two columns")
home:SetSize(600, 520)
flush()
home.Refresh()
check(cards.fire.points[1][2] == 0, "narrow: the cards stack in one column")
home:SetSize(976, 520)
flush()
officer = false
home.Refresh()
officer = true
home.Refresh()

-- The calendar filter, through the real Guild tab and the real calendar.
do
  dofile(ADDON .. "/Modules/CallToArms.lua")   -- the TOC loads it before the panel
  dofile(ADDON .. "/Modules/AllianceChat.lua")
  dofile(ADDON .. "/Modules/GuildChat.lua")
  GuildOS.CallToArms:Initialize()
  dofile(ADDON .. "/UI/CommunityPanel.lua")
  -- The Guild tab's Journal and Achievements sub-tabs draw with the real panels (#367).
  dofile(ADDON .. "/UI/JournalPanel.lua")
  dofile(ADDON .. "/UI/AchievementsPanel.lua")
  GuildOS.RosterFrame, GuildOS.db.settings.window = nil, nil
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
  guild:SetSize(800, 500)   -- a window of ordinary width: six tabs wrap only below it (#124)
  flush()
  local subTabs, visibleSubs, open = 0, {}, nil
  for _, c in ipairs(bar and bar.children or {}) do
    if c.underline then
      subTabs = subTabs + ((c.underline.h == 1) and 1 or -100)
      if c.shown then visibleSubs[#visibleSubs + 1] = c.label.text end
      if c.isActive then open = c end
    end
  end
  check(bar and bar.h == 28 and same(bar.bg.color, C.panel), "the Guild tab's sub-tab bar is 28px on the dark strip")
  check(subTabs == 8 and #visibleSubs == 8 and visibleSubs[1] == "Achievements" and visibleSubs[5] == "Rules"
    and visibleSubs[7] == "Chat" and visibleSubs[8] == "Journal" and open and open.label.text == "Calendar"
    and open.fill.shown and not open.underline.shown,
    "its eight sub-tabs on WoW: Forever (Achievements first, #373; Rules after the Bulletin, #407; the polls on the Bulletin, #448 B24; Journal last) "
      .. "are pills, the open one the soft gold pill (#449)")
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

  -- An allied guild's raid open to the alliance (guildos.me's GOSALLY1): on the day, read-only, never stored.
  local keepAlly = GuildOS.Alliance
  local gruul = os.time({ year = 2026, month = 1, day = 15, hour = 21, min = 0 })
  GuildOS.Alliance = {
    OpenRaids = function() return { { guild = "Iron Pact", title = "Gruul", when = gruul, where = "Gruul's Lair",
                                      leader = "Mira", going = 11, size = 25 } } end,
    AsOf = function() return gruul - 86400 end,
  }
  cal.Render()
  local found = {}
  local function walk(f)
    for _, c in ipairs(f.children or {}) do
      if c.shown ~= false and type(c.text) == "string" then found[#found + 1] = c.text end
      walk(c)
    end
  end
  walk(cal.child)
  local said = table.concat(found, "\n")
  check(said:find("[Iron Pact] Gruul", 1, true) and said:find("11/25", 1, true) and said:find("Gruul's Lair", 1, true)
    and said:find("led by Mira", 1, true) and said:find("Sign up in Discord or on the website.", 1, true)
    and said:find("(as of ", 1, true), "Raids › Calendar shows the alliance's open raid on its day, read-only, signed up to elsewhere")
  local cell
  for _, c in ipairs(cal.cells) do if c.dkey == 20260115 then cell = c end end
  check(cell and cell.evtFS.text:find("Iron Pact", 1, true), "and the day's cell names it")
  check(#GuildOS.Calendar.GetEvents() == 0, "the calendar stores nothing of it")
  GuildOS.Alliance = keepAlly
  cal.Render()

  -- The event editor (#308): only the kinds this rank creates, and a dungeon from the game's list.
  -- Calendar's own rules are tools/event-kinds.lua's.
  local Cal = GuildOS.Calendar
  Cal.KINDS, Cal.REPEATS = { "RAID", "DUNGEON", "PVP", "FARM", "SOCIAL", "OTHER" }, { "none" }
  Cal.SizesFor = function(k, sizes) return k == "DUNGEON" and { 5 } or sizes end
  Cal.KindLabel = function(_, k) return k end
  Cal.MayCreateKind = function(_, k) return k == "DUNGEON" or k == "SOCIAL" end
  Cal.CreatableKinds = function() return { "DUNGEON", "SOCIAL" } end
  Cal.DungeonChoices = function() return { "Ruins of Lordaeron", "Scholomance" } end
  tinsert = tinsert or table.insert
  fire(cal.newBtn, "OnClick")
  local ed = _G.GuildOSEventEditor
  check(ed and ed.shown, "New Event opens the editor")
  local pills, picker, titleBox = {}, nil, nil
  local isKind = {}
  for _, k in ipairs(Cal.KINDS) do isKind[k] = true end
  for _, c in ipairs(ed.children) do
    if c.fs and isKind[c.kind] then pills[c.kind] = c end   -- a pill keeps its kind where the stub keeps its type
    if c.label and c.label.text == "Pick a dungeon" then picker = c end
    if c.kind == "EditBox" and (c.w == 332 or c.w == 222) then titleBox = titleBox or c end   -- the title, first
  end
  check(pills.RAID and pills.RAID.disabled and pills.DUNGEON and not pills.DUNGEON.disabled,
    "a kind this rank does not create is there, and cannot be picked")
  -- Six fixed 52px places inside the 360px editor, labels never marked as removable chips (#371).
  local placed, chipX = 0, false
  for i, k in ipairs(Cal.KINDS) do
    local p = pills[k]
    local pt = p and p.points[1]
    if p and p.w == 52 and pt and pt[2] == 14 + (i - 1) * 55 then placed = placed + 1 end
    if p and p.label.text:find("x$") then chipX = true end
  end
  check(placed == #Cal.KINDS and not chipX, "the kinds sit in six 52px places, no chip's x on any")
  check(picker and picker.shown and titleBox and titleBox.w == 222,
    "it starts on the first kind it creates, a dungeon, with the list beside the title")
  fire(picker, "OnClick")
  local list
  for _, c in ipairs(ed.children) do
    if c ~= picker and c.children and #c.children == 3 and c.strata == "DIALOG" then list = c end
  end
  check(list and list.shown, "the list opens beside the editor")
  local rows = {}
  for _, b in ipairs(list.children) do if b.label then rows[#rows + 1] = b end end
  check(#rows == 3 and rows[1].label.text == "Ruins of Lordaeron" and rows[3].label.text == "Other (type a name)",
    "the game's dungeons, then Other")
  fire(rows[2], "OnClick")
  check(titleBox.text == "Scholomance" and not list.shown, "a pick is the title")
  fire(picker, "OnClick")
  fire(rows[3], "OnClick")
  check(titleBox.text == "" and titleBox.focused, "Other clears a picked name and asks for one")
  fire(pills.SOCIAL, "OnClick")
  check(not picker.shown and titleBox.w == 332, "another kind has no list")
  ed:Hide()
  win:Hide()
end

-- The Journal and the Achievements, the Guild tab's last two sub-tabs on WoW: Forever (#367): each
-- offered while its feature is here and on, built the first time it opens, redrawn on its own OnShow,
-- and a deep link to one that is not offered lands on the calendar.
do
  local reads = { journal = 0, achievements = 0 }
  GuildOS.Journal = {
    ThisWeek = function() reads.journal = reads.journal + 1; return { milestones = 2, members = 1, clears = 3 } end,
    GuildFirsts = function() return {} end,
    Mine = function() return {} end,
  }
  GuildOS.Achievements = { Renown = function() reads.achievements = reads.achievements + 1 end }
  GuildOS.RosterFrame, GuildOS.db.settings.window = nil, nil
  local win = UI:GetMainWindow()
  check(UI:OpenWindow("guild"), "the real Guild tab opens")
  local guild = win.tabPanels.guild
  local bar
  for _, c in ipairs(guild.children) do if c.bg then bar = c end end
  local function subTab(label)
    for _, c in ipairs(bar.children) do
      if c.underline and c.label.text == label then return c end
    end
  end
  local journal, achievements = guild.subPanels.journal, guild.subPanels.achievements
  check(subTab("Journal").shown and subTab("Achievements").shown, "Journal and Achievements are offered on WoW: Forever")
  check(guild.activeSub == "achievements" and achievements.built and achievements.panel.shown
    and subTab("Achievements").isActive, "Guild opens on Achievements, its first sub-tab on WoW: Forever (#373)")
  check(not journal.built and not journal.panel.shown, "and the Journal is not built before it opens")

  check(UI:OpenWindow("journal") and win.activeTab == "guild" and guild.activeSub == "journal",
    "/gos open journal lands on the Guild tab's Journal")
  check(journal.built and journal.panel.shown and not guild.subPanels.calendar.panel.shown
    and subTab("Journal").isActive and reads.journal > 0, "built there, shown alone, its tab marked, drawn")
  local before = reads.journal
  journal.panel:Hide()
  journal.panel:Show()
  check(reads.journal > before, "the Journal's own OnShow redraws it as a sub-panel")
  before = reads.journal
  win:Hide()
  win:Show()
  check(reads.journal > before and guild.activeSub == "journal", "and so does the window opening again on it")

  check(UI:OpenWindow("achievements") and guild.activeSub == "achievements" and achievements.built
    and achievements.panel.shown and not journal.panel.shown, "/gos open achievements lands on its sub-tab")
  before = reads.achievements
  achievements.panel:Hide()
  achievements.panel:Show()
  check(reads.achievements > before, "and its own OnShow redraws it too")

  -- Switched off in Settings: no tab, and the deep link says so as a tab's does.
  GuildOS:SetFeatureEnabled("journal", false)
  win:Hide()
  win:Show()
  check(not subTab("Journal").shown and subTab("Achievements").shown, "a journal switched off has no sub-tab")
  printed = {}
  check(not UI:OpenWindow("journal") and said("Journal is disabled in Settings.") and not journal.panel.shown,
    "and its deep link refuses, saying why")
  -- A sub-tab that went stale on screen still falls back: a click asks again.
  guild.SelectSub("journal")
  check(guild.activeSub == "achievements" and achievements.panel.shown and not journal.panel.shown,
    "selecting it anyway lands where Guild opens, Achievements")
  guild.SelectSub("achievements")
  GuildOS:SetFeatureEnabled("achievements", false)
  win:Hide()
  win:Show()
  check(win.activeTab == "home" and win.activeRoom == "salao",
    "the open entry switched off falls back to the Salão's Home the next time the window shows (#445)")
  check(UI:OpenWindow("guild") and guild.activeSub == "calendar" and not subTab("Achievements").shown,
    "and the Guild hub by name opens on the calendar, without the Achievements sub-tab")
  GuildOS:SetFeatureEnabled("journal", true)
  GuildOS:SetFeatureEnabled("achievements", true)

  -- A module that failed to start: its deep link says so, as its tab did (issue #367).
  local startFailed = GuildOS.FeatureStartFailed
  GuildOS.FeatureStartFailed = function(_, id) return id == "journal" end
  printed = {}
  check(not UI:OpenWindow("journal") and said("Journal could not start on this client."),
    "a journal that failed to start says so")
  GuildOS.FeatureStartFailed = startFailed

  -- A lazy sub-tab whose builder errors is recorded and refused for the session, and the hub falls
  -- back to the calendar, in a hub of its own so the one above keeps its Achievements.
  local realAchievements = GuildOS.CreateAchievementsPanel
  GuildOS.CreateAchievementsPanel = function() error("boom") end
  local hub = newFrame("Frame", UIParent)
  hub:SetSize(800, 500)
  GuildOS:CreateGuildHub(hub)
  local errors = #(GuildOS.State.errors or {})
  printed = {}
  hub.SelectSub("achievements")
  check(hub.activeSub == "calendar" and hub.subPanels.calendar.panel.shown and not hub.subPanels.achievements.panel.shown,
    "an Achievements builder that errors lands on the calendar")
  check(said("Achievements could not start on this client.") and #(GuildOS.State.errors or {}) > errors,
    "saying so, and recording the error")
  printed = {}
  hub.SelectSub("achievements")
  check(hub.activeSub == "calendar" and #printed == 0, "and is refused, quietly, for the rest of the session")
  GuildOS.CreateAchievementsPanel = realAchievements
  guild.SelectSub("nope")
  check(guild.activeSub == "achievements", "a sub-tab the hub does not have lands where Guild opens, Achievements (#373)")

  -- Not on TBC Anniversary nor retail: the tabs are not there, and the deep links say so.
  for _, other in ipairs({ "isAnniversary", "isRetail" }) do
    GuildOS.Client[other] = true
    win:Hide()
    win:Show()
    check(not subTab("Journal").shown and not subTab("Achievements").shown,
      "no Journal nor Achievements sub-tab where " .. other)
    printed = {}
    check(not UI:OpenWindow("journal") and not UI:OpenWindow("achievements") and said("Not available on this client."),
      "and their deep links say they are not on this client (" .. other .. ")")
    guild.SelectSub("journal")
    check(guild.activeSub == "calendar", "nor does the hub open one there (" .. other .. ")")
    GuildOS.Client[other] = nil
  end
  win:Hide()
  GuildOS.Journal, GuildOS.Achievements = nil, nil
end

-- The Call to Arms tab (issue #108), through the real Helpers.
do
  local CTA = GuildOS.CallToArms
  local function find(root, text)
    for _, c in ipairs(root.children) do
      if c.text == text or (c.label and c.label.text == text) then return c end
      local hit = find(c, text)
      if hit then return hit end
    end
  end
  local function tick(cb, v) cb.checkbox:SetChecked(v); cb.checkbox.scripts.OnClick(cb.checkbox) end
  local function open()
    GuildOS.RosterFrame, GuildOS.db.settings.window = nil, nil
    local win = UI:GetMainWindow()
    UI:OpenWindow("guild", "cta")
    return win, win.tabPanels.guild.subPanels.cta.panel
  end

  officer = false
  local win, p = open()
  check(p.shown and find(p, "My alerts") and not find(p, "Send") and not find(p, "Save as template"),
    "a member gets the tab and their own settings, not the controls to send")
  tick(find(p, "Show popups"), false)
  tick(find(p, "World Boss"), false)
  check(GuildOS.db.settings.ctaPopups == false and CTA:SoundOn() and CTA:Muted("worldboss") and not CTA:Muted("pvp"),
    "unticking 'Show popups' turns popups off, and unticking a type mutes that type alone")
  tick(find(p, "Show popups"), true)
  tick(find(p, "World Boss"), true)
  check(CTA:PopupsOn() and not CTA:Muted("worldboss"), "and ticking them again undoes it")

  -- A call the player has not answered can be answered from the list, then not again.
  CTA.recent = { { id = "R1", kind = "pvp", title = "World PvP", text = "Go", zone = "Ashenvale", sender = "Ann-Realm",
                   ts = NOW, at = NOW, going = {} } }
  win.tabPanels.guild.subPanels.cta.refresh()
  local go = find(p, "On my way")
  check(go and go.shown, "a call nobody here answered has 'On my way' in the list")
  go.scripts.OnClick(go)
  check(CTA.recent[1].answered and CTA:GoingCount(CTA.recent[1]) == 1 and not go.shown,
    "answering it counts, and the list repaints without the button")
  win:Hide()
  CTA.recent[1].title = "Later"
  CTA.uiRefresh()
  check(not find(p, "Later  Go"), "with the window closed, an answer arriving repaints nothing")
  UI:OpenWindow("guild", "cta")
  check(find(p, "Later  Go"), "it catches up when the tab opens")
  win:Hide()
  CTA.recent = {}

  officer = true
  local chatCb
  win, p = open()
  chatCb = find(p, "Also post in guild chat")
  check(find(p, "Send") and chatCb and chatCb.checkbox:GetChecked(), "an officer sends, with the guild line on")
  tick(chatCb, false)
  check(GuildOS.db.settings.ctaChat == false and not CTA:ChatOn(), "and can switch the guild line off")
  win:Hide()

  -- However many templates, of whatever length, none sits on another or on the message box.
  local saved = GuildOS.db.cta.templates
  saved[1] = { id = "c1", name = "A very long template nam", text = "x", kind = "pvp" }
  for i = 2, CTA.TEMPLATES_MAX do saved[i] = { id = "c" .. i, name = "t" .. i, text = "x", kind = "rally" } end
  win, p = open()
  local wb = find(p, "World Boss")   -- the chosen template is marked by UI:SetSelected, not "> " (#371)
  local row = wb.parent.parent
  local function laid()
    local cells, lines = {}, {}
    for _, c in ipairs(row.children) do
      if c.shown then
        local _, _, _, x, y = c:GetPoint(1)
        cells[#cells + 1] = { x = x, y = -y, w = c.w }
        lines[-y] = true
      end
    end
    local clash = false
    for i, a in ipairs(cells) do
      if a.x + a.w > row.w then clash = true end
      for j, b in ipairs(cells) do
        if i ~= j and a.y == b.y and a.x < b.x + b.w and b.x < a.x + a.w then clash = true end
      end
    end
    local n = 0
    for _ in pairs(lines) do n = n + 1 end
    return #cells, clash, n
  end
  local nCells, clash, nRows = laid()
  check(nCells == 5 + CTA.TEMPLATES_MAX and not clash and nRows > 2, "seventeen templates flow over rows, none overlapping")
  check(row.h == nRows * 22 + (nRows - 1) * 4, "and the row is as tall as the lines it took")
  p:SetSize(408, 500)
  local _, clash2, nRows2 = laid()
  check(row.w == 400 and not clash2 and nRows2 > nRows, "a narrower tab wraps them again, at its own width")
  local guild = win.tabPanels.guild
  local bar
  for _, c in ipairs(guild.children) do if c.bg then bar = c end end
  guild:SetSize(300, 500)
  flush()
  local fits = true
  for _, c in ipairs(bar.children) do
    if c.underline then
      local _, _, _, x = c:GetPoint(1)
      if x + c.w > bar.w then fits = false end
    end
  end
  check(bar.w == 280 and fits and bar.h > 28, "and the Guild tab's six sub-tabs wrap rather than run off a narrow window")
  local msg
  for _, c in ipairs(p.children) do
    if c.kind == "EditBox" and c.points[1] and c.points[1][2] == row then msg = c end
  end
  check(msg ~= nil, "the message box hangs below the templates, so it moves down with them")
  check(msg.maxBytes == CTA.TEXT_MAX + 1, "and holds what a call carries in bytes, not letters: Cyrillic is two each")
  win:Hide()
  GuildOS.db.cta.templates = {}
end

-- The Chat sub-tab (issue #124): guild chat in the window, through the real GuildChat and Helpers.
do
  local timeAgo = GuildOS.TimeAgo
  dofile(ADDON .. "/Core/Utils.lua")   -- class colours, and the clean-up a sent line gets
  GuildOS.TimeAgo = timeAgo
  local GC = GuildOS.GuildChat
  local function find(root, text)
    for _, c in ipairs(root.children) do
      if c.text == text or (c.label and c.label.text == text) then return c end
      local hit = find(c, text)
      if hit then return hit end
    end
  end
  local sentChat, refs = {}, {}
  function SendChatMessage(msg, chan) sentChat[#sentChat + 1] = { msg = msg, chan = chan } end
  function SetItemRef(link, text, button) refs[#refs + 1] = { link, text, button } end
  function GetPlayerInfoByGUID(g) if g == "g-b" then return "Mage", "MAGE" end end
  GuildOS.db.guildChatLog, GuildOS.isGuilded = nil, true

  GuildOS.RosterFrame, GuildOS.db.settings.window = nil, nil
  local win = UI:GetMainWindow()
  UI:OpenWindow("guild", "chat")
  local sub = win.tabPanels.guild.subPanels.chat
  local p = sub and sub.panel
  local empty = p and find(p, "No guild chat yet.")
  check(p and p.shown and empty and empty.shown, "the Chat sub-tab opens, and says so while nobody has spoken")

  GC:_OnMessage("boa noite", "Bruna", "g-b")
  GC:_OnMessage("bora raid", "Bruna", "g-b")
  local link = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
  GC:_OnMessage("olha " .. link, "Ana", nil)
  local bruna, ana = find(p, "Bruna"), find(p, "Ana")
  check(bruna and bruna.shown and ana and ana.shown and not empty.shown,
    "a line of /g is drawn the moment it arrives, while the tab is open")
  local pr, pg, pb = GuildOS:GetClassColor("MAGE")
  check(same(bruna.color, { r = pr, g = pg, b = pb }), "the speaker in their class colour")
  check(find(p, "boa noite\nbora raid") ~= nil, "two lines in a row from one speaker read as one block")
  local line = find(p, "olha " .. link)
  check(line ~= nil, "a link is drawn as the game sent it")
  local card = line.parent
  check(card.hyperlinks == true and card.mouse == true and card.scripts.OnHyperlinkClick ~= nil, "and can be clicked")
  card.scripts.OnHyperlinkClick(card, "item:19019", "[Thunderfury]", "LeftButton")
  check(refs[1] and refs[1][1] == "item:19019" and refs[1][2] == "[Thunderfury]" and refs[1][3] == "LeftButton",
    "a click on a link opens it as the chat frame would")
  flush()
  local content = card.parent
  local scroll = content.parent
  check(content.h > 0 and scroll.vscroll == math.max(0, content.h - scroll.parent.h), "scrolled to the newest line")

  UI:OpenWindow("guild", "calendar")
  GC:_OnMessage("alguem?", "Caio", nil)
  check(not find(p, "Caio"), "a line that arrives while the tab is closed is not drawn then")
  UI:OpenWindow("guild", "chat")
  check(find(p, "Caio") and find(p, "Caio").shown, "and is there when the tab opens again")

  local old = NOW - 2 * 86400
  table.insert(GC:Log(), 1, { t = old, n = "Duda", m = "ontem" })
  sub.refresh()
  check(find(p, os.date("%a %H:%M", old)) and find(p, os.date("%H:%M", NOW)),
    "a line from another day says which day; today's only the time")

  local holder = scroll.parent
  holder:SetSize(400, 300)
  holder:SetSize(500, 300)
  flush()
  check(card.w == 500 - 12 - 12, "a resized window lays the feed out again, at its new width")

  -- At the cap the oldest line can be a block of its own while the newest joins the last one:
  -- one block fewer, and the card left over must not stay on screen.
  local caio = find(p, "Caio").parent
  GuildOS.db.guildChatLog = { { t = NOW, n = "Bruna", c = "MAGE", m = "so eu" } }
  sub.refresh()
  check(not caio.shown and find(p, "so eu").parent.shown, "a card the log no longer needs is hidden")

  local box
  for _, c in ipairs(p.children) do if c.kind == "EditBox" then box = c end end
  check(box and box.maxBytes == 241, "the box holds what /g will carry: 240 bytes")
  box:SetText("vamos")
  box.scripts.OnEnterPressed(box)
  check(#sentChat == 1 and sentChat[1].msg == "vamos" and sentChat[1].chan == "GUILD" and box.text == "",
    "Enter sends it to /g and empties the box")
  box:SetText("   ")
  box.scripts.OnEnterPressed(box)
  check(#sentChat == 1, "an empty box sends nothing")
  local send = find(p, "Send")
  box:SetText("de novo")
  send.scripts.OnClick(send)
  check(#sentChat == 2 and sentChat[2].msg == "de novo", "and the Send button sends too")
  C_ChatInfo = { InChatMessagingLockdown = function() return true end }
  printed = {}
  box:SetText("agora")
  box.scripts.OnEnterPressed(box)
  check(#sentChat == 2 and box.text == "agora" and said("still in the box"),
    "in a chat lockdown nothing goes, the text stays in the box, and the player is told")
  C_ChatInfo = nil

  -- Where the server keeps the guild's chat (WoW: Forever, #126), the tab reads it.
  local focused
  local held = { { messageId = { epoch = (NOW - 3600) * 1e6, position = 0 },
                  author = { name = "Elyndora Saurfang", classID = 8 }, content = "proc a skill" } }
  local focusedSet = {}
  local function focusCount() local n = 0; for _ in pairs(focusedSet) do n = n + 1 end; return n end
  local byStream, streams, clubSaid = { ["1"] = held }, { { streamId = "1", streamType = 1, name = "Guild" } }, {}
  -- In a chat lockdown the club's lists and messages arrive secret: every read then is counted.
  local locked, lockedReads = false, 0
  local function read(v) if locked then lockedReads = lockedReads + 1 end; return v end
  C_ChatInfo = { InChatMessagingLockdown = function() return locked end }
  C_Club = {
    GetGuildClubId = function() return "C1" end,
    GetStreams = function() return read(streams) end,
    GetMessageRanges = function(_, s)
      local h = byStream[s]
      if not h then return read({}) end
      return read({ { oldestMessageId = h[1].messageId, newestMessageId = h[#h].messageId } })
    end,
    GetMessagesBefore = function(_, s) return read(byStream[s] or {}) end,
    FocusStream = function(c, s) focusedSet[s] = true; focused = c .. "/" .. s end,
    UnfocusStream = function(c, s) focusedSet[s] = nil; if focused == c .. "/" .. s then focused = nil end end,
    RequestMoreMessagesBefore = function() end,
    SendMessage = function(_, s, text) clubSaid[#clubSaid + 1] = { s = s, text = text } end,
  }
  function GetClassInfo(id) if id == 8 then return "Mage", "MAGE", 8 end end
  UI:OpenWindow("guild", "calendar")
  UI:OpenWindow("guild", "chat")
  local ely = find(p, "Elyndora Saurfang")
  local mr, mg, mb = GuildOS:GetClassColor("MAGE")
  check(ely and ely.shown and same(ely.color, { r = mr, g = mg, b = mb }) and find(p, "proc a skill")
    and not find(p, "so eu"), "the tab shows the server's lines, and only those")
  check(focused == "C1/1", "opening it tells the server the guild stream is being read")
  local only = find(p, "Guild")
  check(not (only and only:IsVisible()) and holder.points[1][1] == "TOPLEFT" and holder.points[1][2] == 0,
    "with /g the only channel, there is no row of channel tabs, and the feed starts at the top")
  UI:OpenWindow("guild", "calendar")
  check(focused == nil, "and leaving it says so")

  -- Every channel of the guild gets a tab: Officer to who may read it, and the ones the guild made.
  streams[2] = { streamId = "2", streamType = 2, name = "Officer" }
  streams[3] = { streamId = "3", streamType = 4, name = "Raid Team" }
  byStream["2"] = { { messageId = { epoch = (NOW - 60) * 1e6, position = 0 },
                     author = { name = "Chefe Lima", classID = 8 }, content = "pauta da reuniao" } }
  UI:OpenWindow("guild", "chat")
  local tabG, tabO, tabR = find(p, "Guild"), find(p, "Officers"), find(p, "Raid Team")
  check(tabG and tabO and tabR and tabG:IsVisible() and tabO:IsVisible() and tabR:IsVisible() and tabG.isActive,
    "with more channels, a tab for each above the feed: Guild open, then Officers and the guild's own")
  check(holder.points[1][2] == tabG.parent, "and the feed hangs below the tabs")
  tabO.scripts.OnClick(tabO)
  check(tabO.isActive and not tabG.isActive and find(p, "pauta da reuniao") and not find(p, "proc a skill"),
    "Officers shows the officers' lines alone")
  check(focused == "C1/2" and focusCount() == 1, "and the server is told that is the channel being read, and only that")
  box:SetText("oi chefes")
  box.scripts.OnEnterPressed(box)
  check(sentChat[#sentChat].chan == "OFFICER" and sentChat[#sentChat].msg == "oi chefes", "Enter there goes to /o")
  locked = true
  GuildOS.GuildChat:_Notify()
  check(lockedReads == 0 and tabO.isActive and find(p, "pauta da reuniao") and focused == "C1/2",
    "in a chat lockdown nothing is read, and the open channel stays as it was drawn")
  tabG.scripts.OnClick(tabG)
  check(tabO.isActive and focused == "C1/2",
    "a tab clicked in a lockdown does nothing: what is drawn stays where Enter sends")
  byStream["2"][2] = { messageId = { epoch = (NOW - 30) * 1e6, position = 0 },
                       author = { name = "Chefe Lima", classID = 8 }, content = "depois do boss" }
  GuildOS.GuildChat:_Notify()
  check(not find(p, "pauta da reuniao\ndepois do boss"), "a line that arrives then waits")
  locked = false
  flush()
  check(lockedReads == 0 and find(p, "pauta da reuniao\ndepois do boss"), "and the feed catches up by itself once it lifts")
  box:SetText("segredo dos oficiais")
  box.scripts.OnEnterPressed(box)
  check(sentChat[#sentChat].chan == "OFFICER" and sentChat[#sentChat].msg == "segredo dos oficiais",
    "and Enter still goes to /o")
  tabR.scripts.OnClick(tabR)
  box:SetText("bora")
  box.scripts.OnEnterPressed(box)
  check(focused == "C1/3" and clubSaid[1] and clubSaid[1].s == "3" and clubSaid[1].text == "bora" and box.text == "",
    "and in a channel the guild made, to that channel")
  streams[3] = nil
  GuildOS.GuildChat:_Notify()
  check(tabG.isActive and not tabR:IsVisible() and find(p, "proc a skill") and focused == "C1/1" and focusCount() == 1,
    "a channel removed while open falls back to Guild, which is then the only one being read")

  -- A reader scrolled up stays where they are when a line arrives; one at the bottom follows it.
  scroll:SetSize(500, 300)
  local lots = {}
  local function line(i)
    return { messageId = { epoch = (NOW - 3000 + i) * 1e6, position = 0 },
             author = { name = (i % 2 == 0) and "Ana Silva" or "Bia Costa", classID = 8 }, content = "linha " .. i }
  end
  for i = 1, 30 do lots[i] = line(i) end
  byStream["1"] = lots
  GuildOS.GuildChat:_Notify()
  flush()
  check(scroll:GetVerticalScrollRange() > 0 and scroll.vscroll == scroll:GetVerticalScrollRange(),
    "a long feed sits at its newest line")
  scroll.vscroll = 0
  lots[31] = line(31)
  GuildOS.GuildChat:_Notify()
  flush()
  check(scroll.vscroll == 0 and find(p, "linha 31"), "a reader scrolled up stays there when a line arrives")
  scroll.vscroll = scroll:GetVerticalScrollRange()
  lots[32] = line(32)
  GuildOS.GuildChat:_Notify()
  flush()
  check(scroll.vscroll == scroll:GetVerticalScrollRange(), "and one at the bottom follows the new one")
  scroll.vscroll = 0
  UI:OpenWindow("guild", "calendar")
  UI:OpenWindow("guild", "chat")
  flush()
  check(scroll.vscroll == scroll:GetVerticalScrollRange(), "reopening the tab shows the newest line again")
  local officerLots = {}
  for i = 1, 30 do officerLots[i] = line(i) end
  byStream["2"] = officerLots
  scroll.vscroll = 0
  tabO.scripts.OnClick(tabO)
  flush()
  check(scroll:GetVerticalScrollRange() > 0 and scroll.vscroll == scroll:GetVerticalScrollRange(),
    "and so does changing channel")
  UI:OpenWindow("guild", "calendar")
  check(focused == nil, "and leaving the tab stops reading it")
  C_Club, GetClassInfo, C_ChatInfo = nil, nil, nil
  win:Hide()
  GuildOS.db.guildChatLog = nil
  SendChatMessage, SetItemRef, GetPlayerInfoByGUID = nil, nil, nil
end

do
  GuildOS.RosterFrame, GuildOS.db.settings.window = nil, nil
  local edge = UI:GetMainWindow()
  edge:Show()
  resize(edge, 620, 620)
  check(edge.titleBar.h == 50 and point(edge.content, 1) == "TOPLEFT,15,-99" and edge.band == "narrow",
    "at exactly 620px: the 50px title bar, the strip, 12px padding, and 596px of content, so narrow")
  edge:Hide()
end

-- ── The title bar at every width (#377, #449) ───────────────────────────
-- With a guild name as long as they come, the crest and the name keep the left, the doors take what is left
-- short of the tools and fold into »n, and nothing runs into the tools, down to MIN_W, where only the three
-- numbers stay.
do
  GuildOS.RosterFrame, GuildOS.db.settings.window = nil, nil
  local realInfo = GetGuildInfo
  GetGuildInfo = function() return "Os Cavaleiros da Távola Redonda", "Rank", 0 end
  local win = UI:GetMainWindow()
  win:Show()
  local misfit
  for w = 320, 1000 do
    resize(win, w, 620)
    if win.band ~= "bar" and win.band ~= "watch" then
      local x0, span = win:DoorSpan(w)
      local toolsLeft = (w - 6) - (10 + 24 + 3 * 34)
      if x0 + span > toolsLeft then misfit = misfit or (w .. "px: the doors reach the tools") end
      if x0 < 10 + 34 + 8 + win.nameText.w then misfit = misfit or (w .. "px: the doors over the name") end
      for _, d in ipairs(win.tabs) do
        if d.shown and d.points[1][4] + d.w > span then misfit = misfit or (w .. "px: " .. d.key .. " past the span") end
      end
      if win.more.shown and win.more.points[1][4] + win.more.w > span + 40 then misfit = misfit or (w .. "px: »n") end
      if not (win.searchButton.shown and win.settingsButton.shown and win.minimise.shown) then
        misfit = misfit or (w .. "px: a tool went")
      end
    end
  end
  check(misfit == nil, "from 320px to 1000px nothing on the title bar runs into the next part: " .. tostring(misfit))
  resize(win, 1000, 620)
  check(win.nameText.w <= 220 and win.nameText.w >= 70, "a long name keeps at most 220px (" .. win.nameText.w .. ")")
  resize(win, 320, 620)
  check(win.band == "bar" and win.summaryText.shown and point(win.summaryText, 2) == "RIGHT,-6,0"
    and not (win.metaText.shown or win.nameText.shown or win.crest.shown or win.searchButton.shown or win.settingsButton.shown),
    "at MIN_W, folded to the bar, the three numbers end short of the fold and the tools wait")
  win:Hide()
  GetGuildInfo = realInfo
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
  for _, stale in ipairs({ "UI.Hub", "ToggleExpanded", "GuildOSRosterFrame", '"GuildOSHub"', "UI:CreateWindow(",
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
  check(read("UI/Salao.lua"):find("UI:OpenWindow(item.id, item.sub, item.filter)", 1, true), "the Salão opens screens through OpenWindow")
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
