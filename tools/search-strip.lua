-- The search inside the window (#449, specs/salao/fase3.md), run against the whole addon (every file the TOC
-- loads) under a stub frame API. The maintainer, in game: "the search button still opens a popup". Now the
-- title bar's Search tool opens a strip under the pills (the mockup's .search) and what it finds replaces the
-- screen in the window's view:
--   * the tool opens the strip, focused, under the pills, and closes it; the content moves down under it;
--   * under Search.MIN characters the screen stays; from there the results stand in its place, as parchment
--     cards in order (Members, Items, Recipes, Screens), each with its top rows and "N more";
--   * Up and Down choose a row, Enter opens it: a member's card, the loot history, the recipe in the Workshop
--     (by its item, else by its name), the screen (a room's entry, a Settings section's page);
--   * Escape, the tool again, a door or hiding the window close it, and the screen that was open is back;
--   * /gos find <text> and /gos search open the window with the strip filled;
--   * two columns of cards from UI.SP.TWO_COLS of width, one below, the same strip in every band but the bar;
--   * nothing found is the standard's empty state; no floating search window is left.
--
--   luajit -e 'ADDON="."' tools/search-strip.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
LOCALE = "enUS"   -- the texts below are the keys

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── Stub frame API, the whole addon loaded, a guild of fourteen (tools/room-cards.lua's) ────────────────
-- ── Stub frame API (the screen renderer's) ──────────────────────────────
do
ADDON = ADDON or "."
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
-- Moved under another frame, as the client moves it: out of its old parent's children, into the new one's.
function Frame:SetParent(p)
  if p == self.parent then return end
  if self.parent then
    for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i); break end end
  end
  self.parent = p
  if p then p.children[#p.children + 1] = self; self.level = (p.level or 0) + 1 end
end
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
  self.focused = nil   -- a box hidden lets go of the keyboard, as in the game
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

function CreateFrame(kind, name, parent, template)
  local f = newFrame(kind, parent)
  if kind == "ScrollFrame" and template and tostring(template):find("Scroll") then f.ScrollBar = newFrame("Slider", f) end
  if template and tostring(template):find("CheckButton") then f.Text = newFrame("FontString", f) end
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
    -- One callback's error never drops the others queued with it, as in the game.
    for _, fn in ipairs(due) do
      local ok, err = pcall(fn)
      if not ok and os.getenv("ROOM_CARDS_ALL") == "1" then io.stderr:write("TIMER: " .. tostring(err) .. "\n") end
    end
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

-- ── permissive fallbacks for the full load ──
local noop = function() end
local NOTMETHOD = { ScrollBar = 1, ScrollUpButton = 1, ScrollDownButton = 1, ThumbTexture = 1, Text = 1, Left = 1, Right = 1, Middle = 1, Icon = 1, NineSlice = 1, Background = 1, Border = 1, TitleText = 1, CloseButton = 1, EditBox = 1 }
setmetatable(Frame, { __index = function(_, k) if type(k) == "string" and k:match("^[A-Z]") and not NOTMETHOD[k] then return noop end end })
local known = { Frame = true }
local function anything()
  local t
  t = setmetatable({}, { __index = function(_, k) return anything() end, __call = function() return nil end })
  return t
end
NOW_TS = NOW
FLUSH = flush
newFrame_ = newFrame

end

-- ── Load every file in TOC order ─────────────────────────────────────────
do
-- loads stub + whole addon in toc order
-- render-recording overrides (from the shell render tail)
local order = 0
local Frame = getmetatable(UIParent).__index
local function stamp(f) order = order + 1; f.order = order end
function Frame:CreateTexture(_, layer, _, sub) local t = newFrame_("Texture", self); t.layer = layer or "ARTWORK"; t.sub = sub or 0; stamp(t); return t end
function Frame:CreateFontString(_, layer) local t = newFrame_("FontString", self); t.layer = layer or "OVERLAY"; t.sub = 0; stamp(t); return t end
function Frame:SetTexCoord(a, b, c, d) self.tc = { a, b, c, d } end
function Frame:SetHorizTile(v) self.htile = v end
function Frame:SetVertTile(v) self.vtile = v end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:SetJustifyH(j) self.justify = j end
function Frame:SetJustifyV(j) self.justifyV = j end
function Frame:SetWordWrap(v) self.wrap = v end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetFont(file, size) self.font = { file = file, size = size }; return true end
function Frame:GetFont() if self.font then return self.font.file, self.font.size end return "x", 12 end
function Frame:SetFontObject() end
function Frame:GetStringWidth() local s = tostring(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "   "); local _, n = s:gsub("[^\128-\191]", ""); return n * ((self.font and self.font.size or 12) * 0.5) end
function Frame:GetUnboundedStringWidth() return self:GetStringWidth() end
function Frame:GetStringHeight()
  local sz = (self.font and self.font.size or 12)
  local w = self.w or 0
  if w > 0 and self.wrap ~= false then
    local lines = math.max(1, math.ceil(self:GetStringWidth() / w))
    return lines * (sz + 3)
  end
  return sz + 2
end
function Frame:GetNumPoints() return #self.points end
function Frame:GetName() return self.name end
function Frame:GetObjectType() return self.kind end
function Frame:IsObjectType(k) return self.kind == k end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:GetCenter() return 0, 0 end
function Frame:GetRight() return 0 end
function Frame:GetBottom() return 0 end
function Frame:GetNumChildren() return select("#", self:GetChildren()) end
function Frame:SetChecked(v) self.checked = v and true or nil end
function Frame:GetChecked() return self.checked end
function Frame:GetNumLetters() return #(self.text or "") end
function Frame:GetCursorPosition() return 0 end
function Frame:GetMaxLetters() return 255 end
function Frame:GetTextColor() local c = self.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end
function Frame:GetVertexColor() local c = self.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end
function Frame:GetTexture() return self.texture end
function Frame:IsMultiLine() return false end
function Frame:GetMinMaxValues() return 0, 0 end
function Frame:GetValue() return self.value or 0 end
function Frame:SetValue(v) self.value = v end
function Frame:SetMinMaxValues() end
function Frame:IsProtected() return false end
function Frame:GetAttribute(k) return self.attrs and self.attrs[k] end
function Frame:SetAttribute(k, v) self.attrs = self.attrs or {}; self.attrs[k] = v end
function Frame:IsForbidden() return false end
function Frame:IsMouseEnabled() return self.mouse end
function Frame:GetHitRectInsets() return 0,0,0,0 end
function Frame:GetTextInsets() return 0,0,0,0 end

local function anything()
  return setmetatable({}, { __index = function() return anything() end, __call = function() return nil end })
end
setmetatable(_G, { __index = function(_, k)
  if type(k) == "string" and k:match("^[A-Z]") then return anything() end
  return nil
end })
PixelUtil = false; NUM_CHAT_WINDOWS = 10; CHAT_FRAMES = {}
GetLocale = function() return rawget(_G,'LOCALE') or "ptBR" end
GetAddOnMetadata = function() return "test" end
C_AddOns = { GetAddOnMetadata = function() return "test" end, IsAddOnLoaded = function() return false end }
IsAddOnLoaded = function() return false end
UnitName = function() return "Chehul" end
UnitGUID = function() return "Player-1-0001" end
UnitClass = function() return "Paladino", "PALADIN", 2 end
UnitLevel = function() return 70 end
UnitFactionGroup = function() return "Alliance" end
UnitIsGroupLeader = function() return false end
IsInRaid = function() return false end
IsInGroup = function() return false end
GetNumGroupMembers = function() return 0 end
GetRealmName = function() return "Mundo de Forever" end
GetNormalizedRealmName = function() return "MundodeForever" end
GetCVar = function() return nil end
GetGuildRosterMOTD = function() return "Kael amanhã às 20h. Frasco obrigatório." end
GetGuildInfoText = function() return "Raides seg e qua, 20h. Discord: discord.gg/curva" end
GetNumGuildMembers = function() return #(PEOPLE or {}) end
GetGuildRosterInfo = function(i) local p = PEOPLE[i]; if not p then return end
  return p[1] .. "-MundodeForever", p[5] or "Raider", p[6] or 2, p[7] or 70, p[2], p[3], p[9] or "", p[10] or "", p[4], nil, p[2], 0, 0, false, false, 0, "Player-1-" .. i end
GetGuildRosterLastOnline = function(i) local p = PEOPLE[i]; return 0, 0, (p and p[8]) or 0, 0 end
GuildControlGetNumRanks = function() return 5 end
GuildControlGetRankName = function(i) return ({ "Mestre", "Oficial", "Raider", "Trial", "Social" })[i] end
CanEditMOTD = function() return true end
CanEditGuildInfo = function() return true end
CanEditOfficerNote = function() return true end
CanEditPublicNote = function() return true end
CanGuildPromote = function() return true end
CanGuildDemote = function() return true end
CanGuildRemove = function() return true end
CanViewOfficerNote = function() return true end
IsGuildLeader = function() return true end
C_GuildInfo = { GuildRoster = function() end, CanEditOfficerNote = function() return true end }
GetChannelList = function() return 1, "General", false, 2, "Trade", false end
GetChannelName = function(n) return 0, nil end
RAID_CLASS_COLORS = setmetatable({}, { __index = function(_, k) return { r = 0.8, g = 0.8, b = 0.8, colorStr = "ffcccccc" } end })
local cc = { PALADIN = {0.96,0.55,0.73}, HUNTER = {0.67,0.83,0.45}, DRUID = {1,0.49,0.04}, MAGE = {0.25,0.78,0.92},
  PRIEST = {1,1,1}, SHAMAN = {0,0.44,0.87}, WARLOCK = {0.53,0.53,0.93}, ROGUE = {1,0.96,0.41}, WARRIOR = {0.78,0.61,0.43} }
for k, v in pairs(cc) do rawset(RAID_CLASS_COLORS, k, { r = v[1], g = v[2], b = v[3], colorStr = string.format("ff%02x%02x%02x", v[1]*255, v[2]*255, v[3]*255) }) end
LOCALIZED_CLASS_NAMES_MALE = setmetatable({ PALADIN = "Paladino", HUNTER = "Caçador", DRUID = "Druida", MAGE = "Mago", PRIEST = "Sacerdote",
  SHAMAN = "Xamã", WARLOCK = "Bruxo", ROGUE = "Ladino", WARRIOR = "Guerreiro" }, { __index = function(_, k) return k end })
LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_MALE
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
CANCEL, OKAY, ACCEPT, YES, NO, CLOSE = "Cancelar", "OK", "Aceitar", "Sim", "Não", "Fechar"
GameTooltip = newFrame_("GameTooltip", UIParent)
GameFontNormal, GameFontHighlight, GameFontHighlightSmall, GameFontNormalSmall = {}, {}, {}, {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
math.huge = math.huge
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove, tContains = table.insert, table.remove, function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
strsplit = function(sep, s, n) local out = {}; for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end return unpack(out) end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
format = string.format
strlower, strupper, strsub, strlen, strfind, gsub = string.lower, string.upper, string.sub, string.len, string.find, string.gsub
strmatch = string.match
floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
date = os.date
GetTimePreference = nil
GetCursorPosition = function() return 0, 0 end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
PlaySound = function() end
PlaySoundFile = function() end
SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
ChatFrame_AddMessageEventFilter = function() end
GetGuildFactionInfo = function() return end
C_Timer.NewTimer = function(_, fn) local t = {}; function t:Cancel() end; return t end
GetFramerate = function() return 60 end
debugprofilestop = function() return 0 end
BNGetInfo = function() return end
GetPlayerInfoByGUID = function() return end
GetItemInfo = function(i) return "Item", "|cffa335ee|Hitem:1|h[Item]|h|r", 4, 141, 70, "Weapon", "", 1, "", 134400 end

-- Load in toc order
LOADERR = {}
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
for line in io.lines(ADDON .. "/GuildOS.toc") do
  local p = line:match("^([%w\\_%-]+%.lua)%s*$")
  if p and not p:find("^Libs") and p ~= "Inbox.lua" then
    local path = ADDON .. "/" .. p:gsub("\\", "/")
    local chunk, err = loadfile(path)
    if not chunk then LOADERR[#LOADERR + 1] = err else
      local ok, e = pcall(chunk, "GuildOS", {})
      if not ok then LOADERR[#LOADERR + 1] = p .. ": " .. tostring(e) end
    end
  end
end
if #LOADERR > 0 and rawget(_G,'VERBOSE') then for _, e in ipairs(LOADERR) do io.stderr:write("LOAD: " .. e .. "\n") end end
local function obj() return setmetatable({}, { __index = function(t, k) if type(k) == "string" and k:match("^[A-Z]") then return function() return obj() end end end }) end
local FrameM = getmetatable(UIParent).__index
function FrameM:CreateAnimationGroup() return obj() end
function FrameM:SetMultiLine(v) self.multiline = v end

end

-- The faux scroll frames' offsets (the client's FauxScrollFrame helpers).
FauxScrollFrame_GetOffset = function() return 0 end
FauxScrollFrame_Update = function() end
FauxScrollFrame_OnVerticalScroll = function() end

-- ── Boot, with a guild of fourteen and some of everything to list ─────────
PEOPLE = {
  { "Chehul", "PALADIN", "Shattrath", true, "Mestre", 0 }, { "Thrandor", "HUNTER", "Shattrath", true }, { "Lunara", "DRUID", "Karazhan", true, "Oficial", 1 },
  { "Kaelis", "MAGE", "Quel'Danas", true }, { "Velyra", "PRIEST", "Shattrath", true }, { "Oruk", "SHAMAN", "Nagrand", true },
  { "Morvane", "WARLOCK", "Shattrath", true }, { "Sombra", "ROGUE", "Arena", true }, { "Brakk", "WARRIOR", "", false, "Social", 4, 70, 4 },
  { "Ysolde", "PALADIN", "", false, "Raider", 2, 70, 2 }, { "Garruk", "WARRIOR", "", false, "Raider", 2, 70, 1 }, { "Nyx", "ROGUE", "", false, "Social", 4, 68, 41 },
  { "Fenwick", "WARRIOR", "Shattrath", true, "Trial", 3, 70 }, { "Tessa", "DRUID", "Nagrand", true, "Social", 4, 66 },
}
local okBoot, errBoot = pcall(function() GuildOS:Initialize(); GuildOS:ResolveGuildDB(); GuildOS:InitModules() end)
check(okBoot, "the addon boots under the stub: " .. tostring(errBoot))
for _ = 1, 3 do pcall(FLUSH) end
do
  local R = GuildOS.Recruitment
  -- The officers' modules start a moment after login in the game: here their settings are made at once.
  if R and not GuildOS.db.recruitment then
    GuildOS.db.recruitment = GuildOS:DeepCopy(R.DEFAULT_SETTINGS)
    if R.Initialize then pcall(R.Initialize, R) end
  end
  local r = GuildOS.db.recruitment
  if r then
    r.message = "Abaixo da Curva recruta tanque e cura para TK/SSC. Seg e qua 20h. Fale com Chehul!"
    r.channels = { "Trade", "CurvaAds" }
    r.discord = "discord.gg/curva"
  end
  if GuildOS.BanList then pcall(GuildOS.BanList.Add, GuildOS.BanList, "Grimlock", "Ninja de loot em Karazhan") end
  if GuildOS.GuildManager and GuildOS.GuildManager.Log then pcall(GuildOS.GuildManager.Log, GuildOS.GuildManager, "promote", "Kaelis", "Raider") end
  local _ = R
end


-- The game fires OnTextChanged when a field's text is set, and lets go of the focus on ClearFocus.
do
  local FM = getmetatable(UIParent).__index
  local setText = FM.SetText
  function FM:SetText(t)
    local was = self.text
    setText(self, t)
    if self.kind == "EditBox" and was ~= t and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
  end
  function FM:ClearFocus() self.focused = nil end
end
local function fire(fr, script, ...)
  local fn = fr.scripts[script]
  if fn then return fn(fr, ...) end
end
local function type_(f, text)
  -- Typed: the text, then the game's OnTextChanged (userInput).
  f.searchBox.text = text
  fire(f.searchBox, "OnTextChanged", true)
end

-- Items and recipes to find: the item cache answers by id.
local NAMES = { [28830] = "Dragonspine Trophy", [28434] = "Lionheart Executioner", [29096] = "Cobrahide Leg Armor",
  [32067] = "Elixir of Draenic Wisdom" }
local function itemInfo(i)
  local id = tonumber(tostring(i):match("item:(%d+)") or i)
  local n = NAMES[id]
  if not n then return nil end
  return n, "|cffa335ee|Hitem:" .. id .. "|h[" .. n .. "]|h|r", 4, 141, 70, "", "", 1, "", 134400
end
GetItemInfo = itemInfo
rawset(_G, "C_Item", { GetItemInfo = itemInfo })
local now = os.time()
GuildOS.db.lootHistory = {
  { itemLink = select(2, itemInfo(28434)), player = "Garruk", timestamp = now - 9 * 86400 },
  { itemLink = select(2, itemInfo(28830)), player = "Kaelis", timestamp = now - 2 * 86400 },
}
-- Lists in the recipe tracker's store (memoria.md: compact, a name only where no spell ID gives it).
GuildOS.db.recipeIds = {
  ["Velyra-MundodeForever"] = { Alchemy = GuildOS.RecipeTracker.Pack({ { itemId = 32067, name = "Elixir of Draenic Wisdom" },
                                            { spellId = 28568, name = "Transmute: Primal Might" } }) },
  ["Sombra-MundodeForever"] = { Leatherworking = GuildOS.RecipeTracker.Pack({ { itemId = 29096, name = "Cobrahide Leg Armor" } }) },
}
if GuildOS.RecipeTracker then GuildOS.RecipeTracker.cachedIndex = nil end
-- The Workshop's catalog (Modules/ProfDirectory.lua): Velyra knows recipe 9950, named by the spell.
-- The client names a spell by its ID (a stored list keeps no name a spell ID gives back, memoria.md).
rawset(_G, "C_Spell", { GetSpellInfo = function(id)
  if id == 9950 then return { name = "Ornate Mithril Gloves" } end
  if id == 28568 then return { name = "Transmute: Primal Might" } end
end })
GuildOS.db.professions[GuildOS:GetPlayerKey("Velyra")] = { src = "addon", ts = now, profs = { [164] = { recipes = { 9950 } } } }
GuildOS.Professions.index = nil

local S, UI, SV = GuildOS.Search, GuildOS.UI, GuildOS.UI.SearchView
check(S and SV and UI.OpenSearch, "the search, its results view and the window's way in are loaded")

-- ── The window, on the Workshop ───────────────────────────────────────────
SlashCmdList.GUILDOS("")
pcall(FLUSH)
local f = GuildOS.RosterFrame
check(f and f.shown, "the window opens")
f:SetSize(1000, 620)
f:Layout(1000)
pcall(FLUSH)
check(f:OpenRoom("workshop", true) and f.activeTab == "recipes", "the Workshop's Crafts is open")
local before = { tab = f.activeTab, room = f.activeRoom, entry = f.activeEntry }
local panel = f.tabPanels.recipes

local function y(fr, i) local p = fr.points[i or 1]; return type(p[2]) == "number" and p[3] or p[5] end

-- ── The tool opens the strip, under the pills ─────────────────────────────
local contentTop = y(f.content)
fire(f.searchButton, "OnClick")
check(f.searchOpen and f.searchRow.shown and f.searchBox:HasFocus(), "the Search tool opens the strip, the field focused")
check(f.searchButton.__pressed, "the tool shows it is open")
check(f.entryRow.shown and y(f.searchRow) == y(f.entryRow) - 40, "the strip sits right under the pills: " .. tostring(y(f.searchRow)))
check(y(f.content) == contentTop - 44, "the screen moves down under the strip (" .. tostring(contentTop) .. " -> " .. tostring(y(f.content)) .. ")")
check(f.searchBox.placeholder and f.searchBox.placeholder.text == "Search member, item, recipe or screen…",
  "its hint names what it finds")
local sp = f.searchBox.points
check(sp[1][1] == "LEFT" and sp[2][1] == "RIGHT" and sp[1][4] == 12 and sp[2][4] == -12,
  "the field runs across the window, the window's padding at either end")
check(not rawget(_G, "GuildOSSearchFrame") and not S.frame, "no floating Search window")
check(not f.searchResults.shown and f.content.shown and panel:IsVisible(), "nothing typed: the screen stays")

-- ── Typing filters ────────────────────────────────────────────────────────
type_(f, "r")
check(not f.searching and f.content.shown and not f.searchResults.shown, "one character: still the screen")
type_(f, "ra")
check(f.searching and f.searchResults.shown and not f.content.shown, "two characters: the results in the screen's place")
local host = f.searchResults
local function shownCards()
  local out = {}
  for _, g in ipairs(SV.GROUPS) do
    local c = host.cards[g.key]
    if c.shown then out[#out + 1] = g.key end
  end
  return table.concat(out, ",")
end
check(shownCards() == "members,loot,recipes,screens", "grouped in cards, in order: " .. shownCards())
for _, g in ipairs(SV.GROUPS) do
  local c = host.cards[g.key]
  check(c.isCard and c.title.text == g.label, "each group a parchment card titled " .. tostring(g.label))
end
local res = host.result
check(res.members[1].name == "Lunára" or res.members[1].online, "members: online first")
local names = {}
for _, m in ipairs(res.members) do names[#names + 1] = m.name end
check(table.concat(names, ","):find("Thrandor", 1, true) and table.concat(names, ","):find("Brakk", 1, true),
  "members whose name holds the text: " .. table.concat(names, ","))
check(res.loot[1].name == "Dragonspine Trophy" and res.loot[1].sub:find("Kaelis", 1, true), "items in the loot history, who got them")
check(#res.recipes == 3 and res.recipes[1].name == "Cobrahide Leg Armor" and res.recipes[1].sub:find("Sombra", 1, true),
  "recipes the guild crafts, who crafts them")
local scr = {}
for _, r in ipairs(res.screens) do scr[r.name] = r end
check(scr["Ranks"] and scr["Ranks"].roomId == "officers" and scr["Raiders"] and scr["Raiders"].sub == "Raids",
  "screens: a room's entries by their name or the room's, with the room as context")
local screens = host.cards.screens
local nRows = 0
for _, row in ipairs(screens.rows) do if row.shown then nRows = nRows + 1 end end
check(nRows == 6 and screens.more.shown and screens.more.text == string.format("%d more", #res.screens - 6),
  "a group shows its top six and says how many more: " .. tostring(screens.more.text))
local first = host.flat[1]
check(first.result.kind == "member" and first.avatar.shown and not first.icon.shown, "a member's row has the avatar")
check(first.action.text == "View card" and first.sub.text:find("Level 70", 1, true), "its context line and its action: " .. tostring(first.sub.text))
check(host.flat[1].sel.shown and not host.flat[2].sel.shown, "the first result is the chosen one")
check(f.searchBox:HasFocus(), "the field keeps the focus while typing")

-- Settings' sections, by name.
type_(f, "appearance")
check(host.result.screens[1] and host.result.screens[1].roomId == "settings" and host.result.screens[1].entry.sub == "interface"
  and host.result.screens[1].sub:find("Settings", 1, true), "a Settings section is found, on its page")

-- ── Keyboard: Up and Down move, Enter opens ───────────────────────────────
type_(f, "ra")
fire(f.searchBox, "OnArrowPressed", "DOWN")
check(host.sel == 2 and host.flat[2].sel.shown and not host.flat[1].sel.shown, "Down chooses the next row")
fire(f.searchBox, "OnArrowPressed", "UP")
fire(f.searchBox, "OnArrowPressed", "UP")
check(host.sel == 1, "Up goes back, and stops at the first")
for _ = 1, 40 do fire(f.searchBox, "OnArrowPressed", "DOWN") end
check(host.sel == #host.flat, "Down stops at the last")

-- A member: the card.
local shown
local realShow = GuildOS.ShowMemberDetail
GuildOS.ShowMemberDetail = function(_, data) shown = data end
type_(f, "thran")
fire(f.searchBox, "OnEnterPressed")
GuildOS.ShowMemberDetail = realShow
check(shown and shown.name == "Thrandor" and shown.rank, "Enter on a member opens the member's card")
check(not f.searchOpen and not f.searchRow.shown and f.content.shown and not f.searchResults.shown,
  "and the search closes, the screen back")
check(f.activeTab == before.tab and f.activeEntry == before.entry and panel:IsVisible(), "the screen that was open")

-- An item: the loot history.
fire(f.searchButton, "OnClick")
type_(f, "dragonspine")
check(host.flat[1].result.kind == "loot" and host.flat[1].icon.shown and host.flat[1].action.text == "View history",
  "an item's row: its icon and the history")
fire(f.searchBox, "OnEnterPressed")
check(f.activeRoom == "loot" and f.activeEntry.id == "history" and not f.searchOpen, "Enter on an item opens the loot history")

-- A recipe with its item: the Workshop's card for that item.
local craft
local realCraft = GuildOS.ShowCraftFor
GuildOS.ShowCraftFor = function(_, id) craft = id; return true end
fire(f.searchButton, "OnClick")
type_(f, "draenic")
check(host.flat[1].result.kind == "recipe" and host.flat[1].action.text == "View recipe", "a recipe's row")
fire(f.searchBox, "OnEnterPressed")
GuildOS.ShowCraftFor = realCraft
check(craft == 32067 and not f.searchOpen, "Enter on a recipe the catalog lacks opens the recipe that makes its item")

-- A recipe of the Workshop's catalog: its card there, the list on its name.
fire(f.searchButton, "OnClick")
type_(f, "ornate")
local hit = host.flat[1] and host.flat[1].result
check(hit and hit.kind == "recipe" and hit.recipeId == 9950 and hit.sub:find("Velyra", 1, true),
  "a recipe of the Workshop's catalog, who knows it: " .. tostring(hit and hit.sub))
local tab = GuildOS.craftsTab
local focused
local realFocus = tab.panel.FocusRecipe
check(type(realFocus) == "function", "the Workshop's catalog opens a recipe by id")
tab.panel.FocusRecipe = function(p, id, name) focused = { id, name, realFocus(p, id, name) } end
fire(f.searchBox, "OnEnterPressed")
tab.panel.FocusRecipe = realFocus
check(f.activeTab == "recipes" and focused and focused[1] == 9950 and focused[3] == true and not f.searchOpen,
  "Enter on it opens its card in the Workshop")

-- A recipe only the older scans know, without an item: the Workshop still opens.
f:OpenRoom("salao", true)
fire(f.searchButton, "OnClick")
type_(f, "primal")
hit = host.flat[1] and host.flat[1].result
check(hit and hit.kind == "recipe" and hit.itemId == nil and hit.recipeId == nil, "a recipe without an item is found too")
fire(f.searchBox, "OnEnterPressed")
check(f.activeTab == "recipes" and not f.searchOpen, "and Enter opens the Workshop")

-- A screen: the room's entry.
fire(f.searchButton, "OnClick")
type_(f, "ranks")
local idx
for i, row in ipairs(host.flat) do if row.result.kind == "screen" and row.result.name == "Ranks" then idx = i end end
check(idx and host.flat[idx].glyph.shown and host.flat[idx].action.text == "Go to", "a screen's row: its glyph and Go to")
SV:Select(host, idx)
fire(f.searchBox, "OnEnterPressed")
check(f.activeRoom == "officers" and f.activeEntry.id == "ranks" and not f.searchOpen, "Enter on a screen opens it")

-- A click on a row opens it too.
fire(f.searchButton, "OnClick")
type_(f, "appearance")
fire(host.flat[1], "OnClick")
check(f.activeRoom == "settings" and f.activeTab == "settings" and f.tabPanels.settings.activeSub == "interface"
  and not f.searchOpen, "a click on a Settings section opens its page")

-- ── Closing restores the screen ───────────────────────────────────────────
f:OpenRoom("workshop", true)
before = { tab = f.activeTab, entry = f.activeEntry }
fire(f.searchButton, "OnClick")
type_(f, "ra")
check(f.searching and not panel:IsVisible(), "the results cover the screen")
fire(f.searchBox, "OnEscapePressed")
check(not f.searchOpen and not f.searchRow.shown and not f.searchResults.shown and f.content.shown and panel:IsVisible()
  and f.activeTab == before.tab and f.activeEntry == before.entry, "Escape closes the search and the screen is back")
check(y(f.content) == contentTop and f.searchBox.text == "", "the screen back where it was, the field emptied")
fire(f.searchButton, "OnClick")
type_(f, "ra")
fire(f.searchButton, "OnClick")
check(not f.searchOpen and f.content.shown and panel:IsVisible(), "the tool again closes it too")
fire(f.searchButton, "OnClick")
type_(f, "ra")
local door
for _, d in ipairs(f.tabs) do if d.key == "raids" then door = d end end
fire(door, "OnClick")
check(f.activeRoom == "raids" and not f.searchOpen and f.content.shown, "a door leaves the results for its room")
fire(f.searchButton, "OnClick")
type_(f, "ra")
f:Hide()
check(not f.searchOpen, "hiding the window closes the search")
f:Show()
check(not f.searchRow.shown and f.content.shown, "opened again, the window shows its screen")

-- ── /gos find and /gos search ─────────────────────────────────────────────
f:Hide()
SlashCmdList.GUILDOS("find kael")
check(f.shown and f.searchOpen and f.searchBox.text == "kael" and f.searching, "/gos find <text> opens the window with the strip filled")
check(host.flat[1].result.name == "Kaelis", "and its results: " .. tostring(host.flat[1] and host.flat[1].result.name))
f:Hide()
SlashCmdList.GUILDOS("search")
check(f.shown and f.searchOpen and f.searchBox.text == "" and not f.searching and f.searchBox:HasFocus(),
  "/gos search opens it empty, focused")
S:Show("velyra")
check(f.searchBox.text == "velyra" and host.flat[1].result.name == "Velyra", "Search:Show fills an open strip")

-- ── Widths: two columns from UI.SP.TWO_COLS, one below; the same strip ─────
type_(f, "ra")
f:SetSize(1000, 620); f:Layout(1000); pcall(FLUSH)
check(host.cols == 2 and f.searchW == 1000 - 6 - 24, "a wide window: two columns (" .. tostring(f.searchW) .. ")")
local m, l = host.cards.members, host.cards.loot
check(m.points[1][4] == 0 and l.points[1][4] > 0 and m.w == l.w, "the cards side by side, as wide as each other")
f:SetSize(800, 620); f:Layout(800); pcall(FLUSH)
local inner = f.searchW - UI.SCROLL_GUTTER
check(host.cols == 1 and m.w == inner and l.points[1][4] == 0, "a narrow window: one column, the cards its width")
check(host.flat[1].w == inner - 2 * UI.SP.PAD, "a row is the card's width less its padding")
f:SetSize(470, 620); f:Layout(470); pcall(FLUSH)
check(f.band == "watch" and f.searchRow.shown and f.searching and host.cols == 1, "the narrowest band keeps the strip and one column")
f:ToggleCollapsed()
check(f.band == "bar" and not f.searchRow.shown and not f.searchResults.shown, "folded to the bar, no strip")
f:ToggleCollapsed()
f:SetSize(1000, 620); f:Layout(1000); pcall(FLUSH)
check(f.searchRow.shown and f.searching, "unfolded, the strip and its results come back")

-- The Officers' Room's side bar steps aside for the results.
f:CloseSearch()
f:OpenRoom("officers", true)
check(f.sideNav.shown, "the Officers' Room has its side bar")
fire(f.searchButton, "OnClick")
type_(f, "ra")
check(not f.sideNav.shown and f.searchResults.points[1][2] == 3 + 12, "the results take the whole view")
fire(f.searchBox, "OnEscapePressed")
check(f.sideNav.shown, "and the side bar is back after")

-- ── By the notes (specs/salao/manutencao-roster.md) ───────────────────────
PEOPLE[4][9] = "healer principal"      -- Kaelis's public note
PEOPLE[6][10] = "atrasa no pagamento"   -- Oruk's officer note
fire(f.searchButton, "OnClick")
type_(f, "healer")
check(#host.result.members == 1 and host.result.members[1].name == "Kaelis" and host.result.members[1].via == "note",
  "a member found by the public note")
check(host.flat[1].sub.text:find("note", 1, true), "its line says why: " .. tostring(host.flat[1].sub.text))
type_(f, "pagamento")
check(#host.result.members == 1 and host.result.members[1].via == "onote", "and by the officer note, for a rank that reads it")
CanViewOfficerNote = function() return false end
type_(f, "pagament")
check(#host.result.members == 0, "never for one that cannot")
CanViewOfficerNote = function() return true end
PEOPLE[4][9], PEOPLE[6][10] = nil, nil
f:CloseSearch()

-- ── Nothing found ─────────────────────────────────────────────────────────
fire(f.searchButton, "OnClick")
type_(f, "zzqx")
check(f.searching and #host.flat == 0 and shownCards() == "" and host.empty.shown, "nothing found: the empty state")
check(host.empty.text.text == 'Nothing found for "zzqx".', "saying what was searched: " .. tostring(host.empty.text.text))
fire(f.searchBox, "OnEnterPressed")
check(f.searchOpen, "Enter with nothing found does nothing")
f:CloseSearch()

-- ── The source ────────────────────────────────────────────────────────────
local function read(p) local h = io.open(ADDON .. "/" .. p); local s = h:read("*a"); h:close(); return s end
for _, p in ipairs({ "UI/SearchView.lua", "Modules/Search.lua" }) do
  local s = read(p)
  check(not s:find("GetWidth%(%)%s*%-"), p .. " never sizes from GetWidth() - n")
  check(not s:find("GuildOSSearchFrame", 1, true) and not s:find("UIParent", 1, true), p .. " makes no window of its own")
end

io.write(string.format("search-strip: %d checks passed\n", checks))
