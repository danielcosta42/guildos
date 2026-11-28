-- No screen makes frames again when it redraws (memory audit, specs/salao/memoria.md). The client never frees
-- a frame, a texture or a text: a screen that made its rows anew on every refresh and only hid the old ones grew
-- for the whole session (~150 MB reported). Run against the whole addon (every file the TOC loads) under the
-- room harness's stub frames (tools/room-cards.lua): every room's every entry is opened once, then each screen
-- below is refreshed many times, its data-change hooks fired on screen and off it, and no new frame, texture or
-- text may be made after its first drawing. Where a screen still makes some by design, the exception is listed
-- with its reason and its bound.
--
--   luajit -e 'ADDON="."' tools/frame-leaks.lua
--
-- Exits 1 on the first failed check (FRAME_LEAKS_ALL=1 lists them all).
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    if os.getenv("FRAME_LEAKS_ALL") ~= "1" then os.exit(1) end
  end
end

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
  return p[1] .. "-MundodeForever", p[5] or "Raider", p[6] or 2, p[7] or 70, p[2], p[3], "", "", p[4], nil, p[2], 0, 0, false, false, 0, "Player-1-" .. i end
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
  -- Former members (Officers' Room > Members > Former members): the history keeps them past the departure.
  local h = GuildOS.db.memberHistory
  if h then
    local T = GetServerTime()
    h["Grimlock-MundodeForever"] = { cls = "WARRIOR", stints = { { joinAt = T - 90 * 86400, leftAt = T - 30 * 86400, how = "kick", by = "Chehul" } }, ranks = {} }
    h["Aelwyn-MundodeForever"] = { cls = "MAGE", stints = { { joinAt = T - 400 * 86400, leftAt = T - 300 * 86400, how = "leave" },
      { joinAt = T - 200 * 86400, leftAt = T - 5 * 86400, how = "leave" } }, ranks = {},
      note = { text = "Voltou duas vezes; bom raider, sai em silencio.", author = "Chehul", ts = T, rev = T } }
    h["Borrin-MundodeForever"] = { cls = "PRIEST", stints = { { joinAt = T - 60 * 86400, leftAt = T - 2 * 86400, leftEst = true, how = "gone" } }, ranks = {} }
  end
  local _ = R
end

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
  -- Former members (Officers' Room > Members > Former members): the history keeps them past the departure.
  local h = GuildOS.db.memberHistory
  if h then
    local T = GetServerTime()
    h["Grimlock-MundodeForever"] = { cls = "WARRIOR", stints = { { joinAt = T - 90 * 86400, leftAt = T - 30 * 86400, how = "kick", by = "Chehul" } }, ranks = {} }
    h["Aelwyn-MundodeForever"] = { cls = "MAGE", stints = { { joinAt = T - 400 * 86400, leftAt = T - 300 * 86400, how = "leave" },
      { joinAt = T - 200 * 86400, leftAt = T - 5 * 86400, how = "leave" } }, ranks = {},
      note = { text = "Voltou duas vezes; bom raider, sai em silencio.", author = "Chehul", ts = T, rev = T } }
    h["Borrin-MundodeForever"] = { cls = "PRIEST", stints = { { joinAt = T - 60 * 86400, leftAt = T - 2 * 86400, leftEst = true, how = "gone" } }, ranks = {} }
  end
  local _ = R
end


-- ── Counting what is made ───────────────────────────────────────────────
-- Frames through the stub's CreateFrame (every GuildOS file reaches it through GuildOS.CountedCreateFrame),
-- textures and texts through the frame methods.
local made = { frames = 0, regions = 0 }
local countedAtStart = GuildOS.framesMade or 0
do
  local Frame = getmetatable(UIParent).__index
  local realCreate = CreateFrame
  CreateFrame = function(...) made.frames = made.frames + 1; return realCreate(...) end
  local tex, fs = Frame.CreateTexture, Frame.CreateFontString
  Frame.CreateTexture = function(...) made.regions = made.regions + 1; return tex(...) end
  Frame.CreateFontString = function(...) made.regions = made.regions + 1; return fs(...) end
end
local function total() return made.frames + made.regions end

local UI = GuildOS.UI
local N = 25   -- refreshes per screen

-- Opens the window on room `roomId`'s entry `entryId`; returns the window and the panel shown, or nil when this
-- client has no such entry.
local function open(roomId, entryId)
  SlashCmdList.GUILDOS("")
  pcall(FLUSH)
  local f = GuildOS.RosterFrame
  f:SetSize(1250, 720)
  local entry
  for _, en in ipairs(UI:RoomEntries(roomId)) do if en.id == entryId then entry = en end end
  if not entry then return nil end
  local ok, err = pcall(function() UI:OpenWindow(roomId); f:SelectEntry(roomId, entry, true) end)
  check(ok, roomId .. "/" .. entryId .. " opens: " .. tostring(err))
  pcall(FLUSH)
  return f, f.tabPanels[f.activeTab]
end
-- Whether a shown text under `root` reads `needle`, and the first shown frame `pred` picks.
local function shownUnder(fr, root)
  while fr and fr ~= root do if not fr.shown then return false end fr = fr.parent end
  return fr == root
end
local function shownText(root, needle)
  local found = false
  local function walk(fr)
    for _, c in ipairs(fr.children) do
      if not found and c.kind == "FontString" and type(c.text) == "string" and c.text:find(needle, 1, true) and shownUnder(c, root) then
        found = true
      end
      if not found then walk(c) end
    end
  end
  walk(root)
  return found
end
local function findShown(root, pred)
  local hit
  local function walk(fr)
    for _, c in ipairs(fr.children) do
      if not hit and pred(c) and shownUnder(c, root) then hit = c end
      if not hit then walk(c) end
    end
  end
  walk(root)
  return hit
end
local function closeWindow()
  if GuildOS.RosterFrame then GuildOS.RosterFrame:Hide() end
  pcall(FLUSH)
end

-- `what` run n times after a first run makes nothing (or at most `allow`, an exception named in `why`).
local function steady(name, what, allow, why)
  pcall(what); pcall(FLUSH)
  local before, f0 = total(), made.frames
  for _ = 1, N do
    local ok, err = pcall(what)
    if not ok then check(false, name .. ": refresh runs (" .. tostring(err) .. ")"); return end
    pcall(FLUSH)
  end
  local grew = total() - before
  check(grew <= (allow or 0), string.format("%s: %d refreshes make no new frame, texture or text (%d made, %d of them frames)%s",
    name, N, grew, made.frames - f0, why and (" — allowed " .. allow .. ": " .. why) or ""))
end

-- ── Data for the screens to list ─────────────────────────────────────────
local NOW = NOW_TS
local db = GuildOS.db
do
  -- Raids: three nights of a 25-man and their attendance, one expanded group.
  db.raidTracker = db.raidTracker or {}
  db.raidTracker.sessions = db.raidTracker.sessions or {}
  db.raidTracker.attendance = db.raidTracker.attendance or {}
  local players = {}
  for i = 1, #PEOPLE do players[PEOPLE[i][1] .. "-MundodeForever"] = { joined = NOW - 7200 } end
  for k = 1, 3 do
    db.raidTracker.sessions[NOW - k * 86400] = { name = "Karazhan", instanceID = 532, size = 25, startTime = NOW - k * 86400,
      endTime = NOW - k * 86400 + 7200, players = players, encounters = { { success = true }, { success = false } } }
  end
  db.raidTracker.attendance[""] = {}
  for key in pairs(players) do db.raidTracker.attendance[""][key] = { raids25 = 3, totalScore25 = 270, lastRaid = NOW - 86400 } end
  -- Trials, with comments.
  db.trials = db.trials or {}
  for i = 9, 13 do
    local key = PEOPLE[i][1] .. "-MundodeForever"
    db.trials[key] = { startDate = NOW - i * 86400, endDate = NOW + 86400, status = "trial", sponsor = "Chehul",
      notes = { { author = "Chehul", text = "ok", timestamp = NOW } } }
  end
  -- Cores to sign up to.
  if GuildOS.CoreManager then
    pcall(GuildOS.CoreManager.Create, GuildOS.CoreManager, "Alpha")
    pcall(GuildOS.CoreManager.Create, GuildOS.CoreManager, "Beta")
  end
end

-- ── Every room's every entry, once ──────────────────────────────────────
for _, room in ipairs(UI.ROOMS) do
  for _, e in ipairs(room.entries) do
    if not e.run then open(room.id, e.id) end
  end
end
-- GuildOS's own count (/gos debug mem) sees what the client made for it: every frame here is GuildOS's, but for
-- the few a library makes (AceComm's, ChatThrottleLib's).
local counted = (GuildOS.framesMade or 0) - countedAtStart
check(counted > 0 and counted <= made.frames and counted >= made.frames - 5,
  "GuildOS.framesMade counts the frames GuildOS made (" .. counted .. " of " .. made.frames .. ")")

-- Opening the rooms a second time makes nothing new: every screen keeps what it drew.
do
  local before = total()
  for _, room in ipairs(UI.ROOMS) do
    for _, e in ipairs(room.entries) do
      if not e.run then open(room.id, e.id) end
    end
  end
  -- Exception: the Loot room's Rule tab and the Cores' settings draw again when what they show changed; a
  -- second visit with nothing changed draws nothing (their signatures, UI/LootWindow.lua, UI/CorePanel.lua).
  check(total() - before == 0, "every room opened again makes nothing new (" .. (total() - before) .. " made)")
end

-- ── Each screen, refreshed ──────────────────────────────────────────────
-- Raids: every raid that syncs in redraws the tab (RaidTracker), here with a group expanded.
do
  open("raids", "sessions")
  local o = GuildOS.RaidsPanelOpen
  check(o ~= nil, "the raids tab is open")
  if o then
    GuildOS:RefreshRaidsPanel(o.sessionContent, o.attContent, o.statusText)
    local groupRow = findShown(o.sessionContent, function(c) return c.kind == "Button" and c.scripts.OnClick ~= nil end)
    check(groupRow ~= nil, "the raids tab lists a lockout")
    if groupRow then groupRow.scripts.OnClick(groupRow) end   -- open it: its nights listed too
    local nightRow = findShown(o.sessionContent, function(c) return c.kind == "Button" and c.scripts.OnClick ~= nil and c ~= groupRow
      and c.parent == o.sessionContent end)
    if nightRow then nightRow.scripts.OnClick(nightRow) end   -- and a night: its players listed
    check(shownText(o.attContent, "Thrandor") and shownText(o.sessionContent, "Karazhan"),
      "the raids tab draws its lockouts and attendance")
    steady("Raids attendance", function() GuildOS:RefreshRaidsPanel(o.sessionContent, o.attContent, o.statusText) end)
  end
end

-- The core sign-up window: a role click or a sign-up that syncs redraws it.
do
  GuildOS:ShowCoreSignupFrame()
  check(_G.GuildOSCoreSignupFrame and shownText(_G.GuildOSCoreSignupFrame, "Alpha"), "the sign-up window has a card a core")
  steady("Core sign-up", function() GuildOS:ShowCoreSignupFrame() end)
  if _G.GuildOSCoreSignupFrame then _G.GuildOSCoreSignupFrame:Hide() end
end

-- Trials: an officer's change or another officer's trials redraw it; off screen they draw nothing.
do
  local TT = GuildOS.TrialTracker
  if TT and TT.uiRefresh then
    local _, home = open("officers", "trials")
    TT.uiRefresh()
    check(home and shownText(home, "Brakk"), "the trials tab lists the trials")
    steady("Trials (on screen)", function() TT.uiRefresh() end)
    -- The panel on screen redrawn straight (its own buttons do so), whichever panel the hook holds.
    local panel = home and findShown(home, function(c) return rawget(c, "trialContent") ~= nil end)
    check(panel ~= nil, "the trials panel is on screen")
    if panel then steady("Trials (redrawn)", function() GuildOS:RefreshTrialsPanel(panel) end) end
    closeWindow()
    steady("Trials (off screen)", function() TT.uiRefresh() end)
  end
end

-- Moderation presets: a roster update repaints them; off screen only noted.
do
  local MP = GuildOS.ModPresets
  if MP and MP.uiRefresh then
    pcall(MP.AddPreset, MP, (MP.TYPE_ORDER or {})[1])
    local _, home = open("officers", "presets")
    local first = MP:GetPresets()[1]
    check(home and first and shownText(home, MP:Name(first)), "the presets tab lists the preset")
    steady("Moderation presets (on screen)", function() MP.uiRefresh() end)
    closeWindow()
    steady("Moderation presets (off screen)", function() MP.uiRefresh() end)
  end
end

-- The loot council: a tick a second while a vote is open.
do
  local LC = GuildOS.LootCouncil
  if LC then
    local cands = {}
    for i = 1, 10 do
      cands[i] = { place = i, name = PEOPLE[i][1], answer = "MS", bid = 0, roll = 50 + i, att = 90, recv = 1, points = 10,
        votes = i % 3, prio = 0, wish = 0, reserve = 0, accts = {}, voters = { "Chehul" } }
    end
    LC.View = function() return { link = "[Item]", candidates = cands, canVote = true, mine = 2, open = true, isML = true,
      proposed = "Thrandor", anon = false } end
    LC.StatusText = function() return "12s" end
    LC.WhyNot = function() return "" end
    GuildOS:ShowLootCouncil()
    check(_G.GuildOSLootCouncilFrame and shownText(_G.GuildOSLootCouncilFrame, "Thrandor"), "the council window lists the candidates")
    steady("Loot council (a tick a second)", function() GuildOS:RefreshLootCouncil() end)
    if _G.GuildOSLootCouncilFrame then _G.GuildOSLootCouncilFrame:Hide() end
  end
end

-- Loot › Rule: shown again and laid out again with nothing changed, it draws nothing.
do
  local _, home = open("loot", "rule")
  if home then
    steady("Loot rule tab (shown again)", function() home:Hide(); home:Show() end)
  end
end

-- Points: every points sync refreshes it; off screen nothing.
do
  local P = GuildOS.Points
  if P and P.uiRefresh then
    open("loot", "accounts")
    steady("Points (on screen)", function() P.uiRefresh() end)
    closeWindow()
    steady("Points (off screen)", function() P.uiRefresh() end)
  end
end

-- The calendar: every RSVP that syncs redraws the day.
do
  local CAL = GuildOS.Calendar
  if CAL and CAL.uiRefresh then
    open("raids", "calendar")
    steady("Calendar (on screen)", function() CAL.uiRefresh() end)
    closeWindow()
    steady("Calendar (off screen)", function() CAL.uiRefresh() end)
  end
end

-- Audit panels: the mesh's HELLOs and the sub-tabs refresh them.
do
  local _, home = open("raids", "audit")
  if home and home.RefreshActive then steady("Raid audit", function() home.RefreshActive() end) end
  _, home = open("officers", "audit")
  if home and home.RefreshActive then steady("Data audit", function() home.RefreshActive() end) end
  -- Former members: its list redrawn, a ban or a note that changes (the hooks it joins), and the member window for
  -- somebody no longer in the roster, opened again and again.
  local FM = GuildOS.FormerMembers
  _, home = open("officers", "former")
  check(home and shownText(home, "Aelwyn"), "the former members screen lists who left")
  if home and home.RefreshActive then steady("Former members", function() home.RefreshActive() end) end
  if FM and FM.uiRefresh then
    steady("Former members (a change on screen)", function() FM.uiRefresh() end)
    if GuildOS.BanList and GuildOS.BanList.uiRefresh then
      steady("Former members (a ban synced)", function() GuildOS.BanList.uiRefresh() end)
    end
    local rows = FM:Rows(true).rows
    if rows[1] then
      steady("Former member's card", function()
        for _, r in ipairs(rows) do FM:Open(r) end
      end)
      if GuildOS.DetailFrame then GuildOS.DetailFrame:Hide() end
    end
  end
end

-- Settings: each page refreshed in place; a page whose shape comes back is the one built before.
do
  local _, home = open("settings", "profile")
  if home and home.SelectSub then
    steady("Settings pages", function()
      for _, key in ipairs({ "profile", "rules", "modules", "chat" }) do home.SelectSub(key) end
    end)
  end
end

-- The member card: opened on member after member, and redrawn by a sheet or a warning.
do
  if GuildOS.Mesh then GuildOS.Mesh.PresenceSuffix = function() return "" end end   -- the stub has no mesh peers
  local list = {}
  for i = 1, #PEOPLE do list[i] = GuildOS.GetMemberRecord and GuildOS:GetMemberRecord(PEOPLE[i][1] .. "-MundodeForever") end
  if list[1] then
    steady("Member card", function()
      for i = 1, #list do if list[i] then GuildOS:ShowMemberDetail(list[i]) end end
    end)
    if GuildOS.DetailFrame then GuildOS.DetailFrame:Hide() end
  end
end

-- The login digest, shown again (/gos digest).
do
  local D = GuildOS.Digest
  if D and D.Show then
    steady("Digest", function() D:Show({ "one", "two", "three" }) end)
    if D.frame then D.frame:Hide() end
  end
end

-- Guild analytics: its tabs and switches repaint it.
do
  local A = GuildOS.GuildAnalytics
  if A and A.Show then
    pcall(A.Show, A)
    if A.uiRefresh then steady("Guild analytics", function() A.uiRefresh() end) end
    if A.frame then A.frame:Hide() end
  end
end

-- Raids › Cores: a sync redraws the list and the core's settings; off screen nothing.
do
  if GuildOS.coresPanelRefresh then
    local _, home = open("raids", "cores")
    local row = home and findShown(home, function(c) return rawget(c, "coreName") ~= nil and c.scripts.OnClick ~= nil end)
    check(row ~= nil, "the cores tab lists the cores")
    if row then row.scripts.OnClick(row) end   -- a core picked: its settings drawn
    pcall(FLUSH)
    steady("Cores (on screen)", function() GuildOS.coresPanelRefresh() end)
    closeWindow()
    steady("Cores (off screen)", function() GuildOS.coresPanelRefresh() end)
  end
end

-- Loot › Lists, the guild's wishlists: every keystroke in its search and every item the client loads fill it.
do
  db.guildWishlists = db.guildWishlists or {}
  for i = 1, 8 do
    db.guildWishlists[PEOPLE[i][1]:lower()] = { name = PEOPLE[i][1], class = PEOPLE[i][2],
      wishlist = { { itemId = 28000 + i, order = 1 }, { itemId = 29000 + i, order = 2, isOffspec = true } } }
  end
  local host = newFrame_("Frame", UIParent)
  host:SetSize(800, 500)
  local ok, err = pcall(GuildOS.CreateWishlistGuildPanel, GuildOS, host)
  check(ok, "the guild wishlist panel builds (" .. tostring(err) .. ")")
  local search = findShown(host, function(c) return c.kind == "EditBox" and c.scripts.OnTextChanged ~= nil end)
  check(search ~= nil, "the wishlist panel has its search")
  if search then
    search.scripts.OnTextChanged(search)
    local row = findShown(host, function(c) return c.kind == "Button" and c.scripts.OnClick ~= nil and shownText(c, "Thrandor") end)
    if row then row.scripts.OnClick(row) end   -- a member's list opened
    check(shownText(host, "Chehul"), "the wishlist panel lists the members")
    steady("Guild wishlists (typing)", function() search.scripts.OnTextChanged(search) end)
  end
  host:Hide()
end

-- The recruit scanner: every box ticked repaints its list.
do
  local RS = GuildOS.RecruitScanner
  if RS and RS.BuildInto then
    RS._results = {}
    for i = 1, 12 do RS._results[i] = { name = "Recruit" .. i, level = 70, class = "MAGE", zone = "Shattrath" } end
    local host = newFrame_("Frame", UIParent)
    host:SetSize(800, 500)
    local ok, refresh = pcall(RS.BuildInto, RS, host)
    check(ok and type(refresh) == "function", "the scanner builds (" .. tostring(refresh) .. ")")
    if ok and type(refresh) == "function" then
      refresh()
      check(shownText(host, "Recruit1"), "the scanner lists the candidates")
      steady("Recruit scanner", refresh)
    end
    host:Hide()
  end
end

-- Onboarding (specs/salao/onboarding.md): What's new paged through and shown again, a whole tour run (every
-- step, its callout and pictures), Show me, the help hub refreshed and a guide opened again, and the Hall's
-- Get started card redrawn: all made once.
do
  local O, Tour = GuildOS.Onboarding, UI.Tour
  if O and Tour then
    steady("What's new (paged, shown again)", function()
      GuildOSDB._onboard = nil
      local w = GuildOS:ShowWhatsNew(true)
      for _ = 1, #w.cards - 1 do w:Go(1) end
      w:Go(-1)
      w:Hide()
      GuildOS:ShowWhatsNew(true, "welcome"):Hide()
    end)
    open("salao", "home")
    steady("a whole member tour", function()
      O:Progress("member").done, O:Progress("member").step = nil, 1
      Tour:Start("member")
      for _ = 1, 25 do if Tour.state.mode == "tour" then Tour:Next() end end
      Tour:Stop()
    end)
    steady("the officers' tour at 452 px", function()
      GuildOS.RosterFrame:SetSize(452, 620)
      Tour:Start("officer", "recruit")
      for _ = 1, 25 do if Tour.state.mode == "tour" then Tour:Next() end end
      Tour:Stop()
      GuildOS.RosterFrame:SetSize(1250, 720)
    end)
    steady("Show me", function()
      local it = O:Checklist("officer")[1]
      Tour:ShowMe(it.go, it.title, it.desc)
      Tour:Stop()
    end)
    local _, help = open("settings", "help")
    steady("Settings › Help (refreshed, a guide opened)", function()
      if help and help.SelectSub then help.SelectSub("help") end
      UI.HelpPanel:OpenGuide("map"):Hide()
      UI.HelpPanel:OpenGuide("moderate"):Hide()
    end)
    local _, home = open("salao", "home")
    steady("the Hall's Get started card", function() if home and home.Refresh then home.Refresh() end end)
  end
end

-- The Hall's Groups now card (#449): groups opening and closing on the board repaint it (LFGBoard:Refresh, its
-- listener), and the Hall redraws; its lines are made once.
do
  local G, B = GuildOS.Groups, GuildOS.LFGBoard
  if G and B and db.lfgGroups then
    local _, home = open("salao", "home")
    local card = home and home.cards and home.cards.groups
    check(card ~= nil and card.shown, "the Hall shows Groups now")
    local keys = {}
    for i = 1, 4 do keys[i] = PEOPLE[i + 1][1] .. "-MundodeForever" end
    local flip = 0
    steady("the Hall's Groups now (the board changing)", function()
      flip = flip + 1
      for i, k in ipairs(keys) do
        db.lfgGroups[k] = (i <= (flip % 4) + 1) and G:_BuildGroup({ act = "elite-quests", need = { T = 1, D = i }, ttl = 3600 }, NOW - i) or nil
      end
      B:Refresh()
      if home and home.Refresh then home.Refresh() end
    end)
    for _, k in ipairs(keys) do db.lfgGroups[k] = nil end
    B:Refresh()
  end
end

-- Every other module hook, fired while the window is closed, makes nothing.
do
  closeWindow()
  local hooks = {}
  for name, m in pairs(GuildOS) do
    if type(m) == "table" and name ~= "UI" then
      for _, k in ipairs({ "uiRefresh", "rulesRefresh", "welcomeUiRefresh" }) do
        if type(rawget(m, k)) == "function" then hooks[#hooks + 1] = { name .. "." .. k, rawget(m, k) } end
      end
    end
  end
  table.sort(hooks, function(a, b) return a[1] < b[1] end)
  -- Exceptions, each with why it may make something off screen:
  local ALLOW = {
    -- Floating windows and bars that are their own screen: the hook paints a bar or badge outside the window.
    ["CraftOrders.uiRefresh"] = 0, ["GuildBank.uiRefresh"] = 0,
  }
  for _, h in ipairs(hooks) do
    steady("off screen: " .. h[1], h[2], ALLOW[h[1]])
  end
  check(#hooks >= 10, "the module hooks are found (" .. #hooks .. ")")
end

print(("frame-leaks: %d checks passed"):format(checks))
