-- Every room's screen against the spacing standard (#449, specs/salao/fase3.md "Espaçamento"), run against the
-- whole addon (every file the TOC loads) under a stub frame API. Each entry of every room (UI/Rooms.lua: the
-- Salão, Raids, Members, Loot, Workshop, Chronicle, the Officers' Room and Settings) is opened at a wide window
-- (1250px) and a narrow one (800px), and on every parchment or dark card shown (UI:CreateCard marks it isCard):
--   * every shown part of the card (texts, fields, buttons, lists) lies inside it; a list's rows inside its
--     scroll frame are held to the card's width (the frame clips them in height);
--   * no two cards overlap (a card inside another one is part of it);
--   * no text on it asks for less than UI.SP.META, nor draws under 11px;
--   * its title sits UI.SP.PAD down from its top, at least UI.SP.PAD in: the card's padding is the shared scale's.
-- Also: no screen file keeps a card padding of its own (a local CARD_PAD or CARD_TOP set to a number).
--
--   luajit -e 'ADDON="."' tools/room-cards.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    -- ROOM_CARDS_ALL=1 lists every failure instead of stopping at the first.
    if os.getenv("ROOM_CARDS_ALL") ~= "1" then os.exit(1) end
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
  local _ = R
end

-- Where a frame lies, from its points, in the window's coordinates (y down).
local function resolver(root, W, H)
  local rects, owner = {}, {}
  local function scan(fr) if fr.scrollChild then owner[fr.scrollChild] = fr end for _, c in ipairs(fr.children) do scan(c) end end
  scan(root)
  local function sizeOf(fr)
    local w, h = fr.w or 0, fr.h or 0
    if fr.kind == "FontString" then
      if w == 0 then w = fr:GetStringWidth() end
      if h == 0 then h = fr:GetStringHeight() end
    end
    return w, h
  end
  local resolve
  resolve = function(fr, depth)
    if rects[fr] then return rects[fr] end
    depth = (depth or 0) + 1
    if depth > 80 then return { l = 0, t = 0, r = 0, b = 0 } end
    if fr == root then rects[fr] = { l = 0, t = 0, r = W, b = H }; return rects[fr] end
    local w, h = sizeOf(fr)
    if #fr.points == 0 then
      local base = owner[fr] and resolve(owner[fr], depth) or (fr.parent and resolve(fr.parent, depth)) or { l = 0, t = 0, r = W, b = H }
      rects[fr] = { l = base.l, t = base.t, r = base.l + w, b = base.t + h }
      return rects[fr]
    end
    local L, R, T, B, CX, CY
    for _, p in ipairs(fr.points) do
      if p[1] == "ALL" then
        local o = resolve(p[2] or fr.parent, depth)
        L, R, T, B = o.l, o.r, o.t, o.b
      else
        local point, rel, relPoint, x, y = p[1], nil, nil, 0, 0
        if type(p[2]) == "number" or p[2] == nil then x, y = p[2] or 0, p[3] or 0
        else rel, relPoint, x, y = p[2], p[3], p[4] or 0, p[5] or 0 end
        if type(relPoint) == "number" then relPoint, x, y = point, relPoint, x end
        if type(rel) == "string" then rel = _G[rel] end
        rel = rel or fr.parent
        relPoint = relPoint or point
        local o = rel and resolve(rel, depth) or { l = 0, t = 0, r = W, b = H }
        local ax = (relPoint:find("LEFT") and o.l) or (relPoint:find("RIGHT") and o.r) or (o.l + o.r) / 2
        local ay = (relPoint:find("TOP") and o.t) or (relPoint:find("BOTTOM") and o.b) or (o.t + o.b) / 2
        ax, ay = ax + x, ay - y
        if point:find("LEFT") then L = ax elseif point:find("RIGHT") then R = ax else CX = ax end
        if point:find("TOP") then T = ay elseif point:find("BOTTOM") then B = ay else CY = ay end
      end
    end
    if not L and not R then L = (CX or 0) - w / 2; R = L + w elseif not L then L = R - w elseif not R then R = L + w end
    if not T and not B then T = (CY or 0) - h / 2; B = T + h elseif not T then T = B - h elseif not B then B = T + h end
    rects[fr] = { l = L, t = T, r = R, b = B }
    return rects[fr]
  end
  return resolve, owner
end

local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
local function visibleUnder(fr, top)
  local x = fr
  while x and x ~= top do if not x.shown then return false end x = x.parent end
  return x == top
end


local function visibleUnder(fr, top)
  local x = fr
  while x and x ~= top do if not x.shown then return false end x = x.parent end
  return x == top
end

-- ── No screen keeps a card padding of its own ───────────────────────────
do
  local p = io.popen('ls "' .. ADDON .. '"/UI/*.lua')
  for path in p:lines() do
    local fh = io.open(path, "rb")
    local text = fh:read("*a")
    fh:close()
    for line in text:gmatch("[^\n]+") do
      local name = line:match("^%s*local%s+(CARD_PAD)%s*=%s*%d") or line:match("^%s*local%s+(CARD_TOP)%s*=%s*%d")
        or line:match("^%s*local%s+(CARD_GAP)%s*=%s*%d")
      check(not name, path .. " takes its card spacing from UI.SP, not a " .. tostring(name) .. " of its own: " .. line)
    end
  end
  p:close()
end

local UI = GuildOS.UI
local SP = UI.SP
check(type(SP) == "table" and SP.PAD == 16 and SP.GAP == 14 and SP.BODY == 13 and SP.META == 11 and SP.TITLE == 15,
  "the spacing standard is one table, UI.SP")
check(UI.CARD_PAD == SP.PAD and UI.CARD_TOP == SP.TOP and GuildOS.Forms.GAP == SP.GAP and GuildOS.Forms.FIELD_H == SP.FIELD,
  "a card's padding, its content's top, the gap between cards and a field's height come from UI.SP")
check(GuildOS.Kit.PAD == SP.PAD, "a floating window's body padding is a card's")

-- Opens the window at W x H on room `roomId`'s entry `entryId`; returns the window and the shown panel, or nil
-- when this client or player has no such entry.
local function open(roomId, entryId, W, H)
  SlashCmdList.GUILDOS("")
  pcall(FLUSH)
  local f = GuildOS.RosterFrame
  f:SetSize(W, H)
  pcall(FLUSH)
  local entry
  for _, en in ipairs(UI:RoomEntries(roomId)) do if en.id == entryId then entry = en end end
  if not entry then return nil end
  local ok, err = pcall(function() UI:OpenWindow(roomId); f:SelectEntry(roomId, entry, true) end)
  check(ok, roomId .. "/" .. entryId .. " opens: " .. tostring(err))
  pcall(FLUSH)
  local home = f.tabPanels[f.activeTab]
  if not home then return nil end
  local stripH = (f.entryRow and f.entryRow.shown) and (f.entryRow.h or 0) or 0
  local cw, ch = W - 30, H - (3 + 50 + 12) - stripH - (3 + 24 + 12)
  if f.sideNav and f.sideNav.shown then cw = cw - 198 end
  f.content:SetSize(cw, ch)
  home:SetSize(cw, ch)
  local function prop(fr, w, h)
    for _, c in ipairs(fr.children) do
      if c.kind ~= "Texture" and c.kind ~= "FontString" then
        local p = c.points[1]
        if (p and p[1] == "ALL") or (#c.points >= 2 and (c.w or 0) == 0 and (c.h or 0) == 0) then
          c:SetSize(w, h); prop(c, w, h)
        end
      end
    end
  end
  prop(home, cw, ch)
  pcall(FLUSH)
  -- The game sizes a frame from its anchors a frame later: here from the resolved anchors, twice.
  for _ = 1, 2 do
    local resolve = resolver(f, W, H)
    local function settle(fr)
      -- A scroll frame, and any frame its anchors size (two corners): as the client lays it out.
      if fr.shown and (fr.kind == "ScrollFrame" or (fr.kind ~= "Texture" and fr.kind ~= "FontString" and #fr.points >= 2)) then
        local r = resolve(fr)
        local w, h = math.floor(r.r - r.l + 0.5), math.floor(r.b - r.t + 0.5)
        if w > 0 and (w ~= fr.w or h ~= fr.h) then fr:SetSize(w, h) end
      end
      for _, c in ipairs(fr.children) do settle(c) end
    end
    settle(home)
    pcall(FLUSH)
  end
  -- The game lays a screen out a frame after every frame took its new size: here, once more, after the scroll
  -- frames (a size that changes, so a screen that only listens to a change hears it).
  prop(home, cw - 1, ch)
  prop(home, cw, ch)
  -- And shown again at its new size, as a screen opened on a window already that size is (its OnShow lays it out).
  home:Hide(); home:Show()
  pcall(FLUSH)
  if home.RefreshActive then pcall(home.RefreshActive) end
  if home.Refresh then pcall(home.Refresh) end
  pcall(FLUSH)
  return f, home
end

-- Every card shown under `home`, with whether it lies in a scroll frame's child.
local function cardsUnder(home, owner)
  local out = {}
  local function walk(fr, scrolled, inCard)
    for _, c in ipairs(fr.children) do
      if c.shown then
        local s = scrolled or (owner[c] ~= nil and c) or nil
        if rawget(c, "isCard") and not inCard then out[#out + 1] = { card = c, scroll = s } end
        walk(c, s, inCard or rawget(c, "isCard"))
      end
    end
  end
  walk(home, nil, false)
  return out
end

local SLACK = 2
local opened = 0
for _, room in ipairs(UI.ROOMS) do
  for _, e in ipairs(room.entries) do
    if not e.run then
      for _, W in ipairs({ 1250, 800 }) do
        local f, home = open(room.id, e.id, W, 720)
        if f then
          opened = opened + 1
          local id = room.id .. "/" .. e.id
          local resolve, owner = resolver(f, W, 720)
          local list = cardsUnder(home, owner)
          for _, it in ipairs(list) do
            local card = it.card
            local c = resolve(card)
            local cname = plain(card.title and card.title.text)
            if card.title and plain(card.title.text) ~= "" then
              local t = resolve(card.title)
              -- A title between a card's own arrows (the calendar's month) sits on the same line, further in.
              check((t.l - c.l) >= SP.PAD - 1 and math.abs((t.t - c.t) - SP.PAD) <= 2,
                string.format("%s at %d: \"%s\" has its title UI.SP.PAD in (%d,%d)", id, W, cname, t.l - c.l, t.t - c.t))
            end
            local function walk(fr, clipped)
              for _, k in ipairs(fr.children) do
                if k.shown then
                  local inScroll = clipped or owner[k] ~= nil
                  local art = k.kind == "Texture" and fr == card
                  local empty = (k.kind == "FontString" and plain(k.text) == "")
                  if not art and not empty then
                    local r = resolve(k)
                    local sized = (r.r - r.l) >= 1 or (r.b - r.t) >= 1
                    local name = tostring(k.kind) .. " \"" .. plain(k.text or (rawget(k, "label") and k.label.text) or "") .. "\""
                    local where = string.format("%s at %d: \"%s\" holds its %s (%d,%d %dx%d in %dx%d)", id, W,
                      cname, name, r.l - c.l, r.t - c.t, r.r - r.l, r.b - r.t, c.r - c.l, c.b - c.t)
                    if sized then
                      check(r.l >= c.l - SLACK and r.r <= c.r + SLACK, where .. ": across")
                      if not inScroll then check(r.t >= c.t - SLACK and r.b <= c.b + SLACK, where .. ": down") end
                    end
                    if k.kind == "FontString" then
                      local font = rawget(k, "__gosFont")
                      if font then
                        local title = font.file == GuildOS.Fonts.title
                        check(font.px >= 11 and (title or font.asked >= SP.META),
                          string.format("%s (asked %s, drawn %s): no text on a card under UI.SP.META", where, tostring(font.asked), tostring(font.px)))
                      end
                    end
                  end
                  walk(k, inScroll)
                end
              end
            end
            walk(card, false)
          end
          -- No two cards overlap (cards in different scroll frames are clipped apart; the same frame's are not).
          for a = 1, #list do
            for b = a + 1, #list do
              local A, B = list[a], list[b]
              if A.scroll == B.scroll then
                local ra, rb = resolve(A.card), resolve(B.card)
                local ix = math.min(ra.r, rb.r) - math.max(ra.l, rb.l)
                local iy = math.min(ra.b, rb.b) - math.max(ra.t, rb.t)
                check(ix <= SLACK or iy <= SLACK, string.format("%s at %d: the cards \"%s\" and \"%s\" do not overlap (%dx%d)",
                  id, W, plain(A.card.title and A.card.title.text), plain(B.card.title and B.card.title.text), ix, iy))
              end
            end
          end
          local _ = visibleUnder
        end
      end
    end
  end
end
-- Raid Tools (#449 review): a roster change redraws the screen, never taking the box the raid leader types in.
do
  local RTm = GuildOS.RaidTools
  local defs = {}
  for _, d in ipairs(RTm:InstanceList() or {}) do defs[#defs + 1] = d end
  check(defs[1] ~= nil, "this client knows a raid to plan")
  RTm:PickInstance(defs[1].key)
  local f, home = open("raids", "raidtools", 1250, 720)
  check(f ~= nil, "Raid Tools opens")
  local rt
  local function find(fr)
    for _, c in ipairs(fr.children) do
      if not rt and type(rawget(c, "subPanels")) == "table" and c.subPanels.fight then rt = c end
      find(c)
    end
  end
  find(home)
  check(rt ~= nil, "Raid Tools has its Fight part")
  rt.SelectSub("fight")
  pcall(FLUSH)
  local box, ev
  local function walk(fr)
    for _, c in ipairs(fr.children) do
      if c.kind == "EditBox" and c.shown and visibleUnder(c, home) and not box then box = c end
      if rawget(c, "events") and c.events.GROUP_ROSTER_UPDATE and c.scripts.OnEvent then ev = c end
      walk(c)
    end
  end
  walk(home)
  check(box ~= nil and ev ~= nil, "the fight's task boxes and the screen's roster listener (" .. tostring(box) .. tostring(ev) .. ")")
  box:SetFocus()
  ev.scripts.OnEvent(ev, "GROUP_ROSTER_UPDATE")
  pcall(FLUSH)
  check(box.shown and box:HasFocus(), "the box being typed in stays, focused, through a roster change")
  box.focused = false
  ev.scripts.OnEvent(ev, "GROUP_ROSTER_UPDATE")
  pcall(FLUSH)
  check(box.shown, "and the screen redraws once it lets go")
end

-- Raids › Cores (#449 review): picking a core again and again makes no new frames (its rows and cards are kept).
do
  pcall(GuildOS.CoreManager.Create, GuildOS.CoreManager, "Alpha")
  pcall(GuildOS.CoreManager.Create, GuildOS.CoreManager, "Beta")
  local f, home = open("raids", "cores", 1250, 720)
  check(f ~= nil, "Cores opens")
  local function count(fr) local n = rawget(fr, "isCard") and 1 or 0 for _, c in ipairs(fr.children) do n = n + count(c) end return n end
  local rows = {}
  local function walk(fr)
    for _, c in ipairs(fr.children) do
      if rawget(c, "coreName") and c.scripts.OnClick and c.shown then rows[#rows + 1] = c end
      walk(c)
    end
  end
  walk(home)
  check(#rows >= 1, "the cores list its rows")
  rows[1].scripts.OnClick(rows[1]); pcall(FLUSH)
  local before = count(home)
  for _ = 1, 3 do rows[1].scripts.OnClick(rows[1]); pcall(FLUSH) end
  local after = count(home)
  check(after == before, "three rebuilds make no new cards (" .. before .. " -> " .. after .. ")")
  local again = {}
  for _, c in ipairs(rows) do again[c] = true end
  rows = {}
  walk(home)
  local same = true
  for _, c in ipairs(rows) do if not again[c] then same = false end end
  check(same, "the list's rows are the same frames after a rebuild")
end

-- Workshop › the recipe card (#449): the item's icon beside its name on the header's line, and who crafts it in a
-- list of its own that stops a section's gap above the order block.
for _, W in ipairs({ 1250, 800 }) do
  local f, home = open("workshop", "crafts", W, 720)
  local hit
  local function walk(fr)
    for _, c in ipairs(fr.children) do
      if not hit and c.shown and type(rawget(c, "data")) == "table" and c.data.id and c.scripts.OnClick then hit = c end
      walk(c)
    end
  end
  walk(home)
  check(hit ~= nil, "the catalog lists a recipe to open")
  local d
  local function find(fr)
    for _, c in ipairs(fr.children) do
      if not d and rawget(c, "whoScroll") then d = c end
      find(c)
    end
  end
  find(f)
  -- A second click on the open recipe closes it: open it only when it is not.
  if not (d and d.shown) then hit.scripts.OnClick(hit, "LeftButton"); pcall(FLUSH) end
  d = d and d.shown and d or nil
  check(d ~= nil, "the recipe card opens at " .. W)
  local resolve = resolver(f, W, 720)
  local card, edge, name, box, who = resolve(d), resolve(d.icon.edge), resolve(d.name), resolve(d.box), resolve(d.whoScroll)
  check(math.abs(edge.t - card.t - SP.PAD) <= 1 and math.abs(edge.l - card.l - SP.PAD) <= 1, "the icon opens the header, PAD in")
  check(name.l >= edge.r and name.t < edge.b and name.b > edge.t, "the name beside the icon, on its line")
  check(d.icon.icon.texture ~= nil and d.icon.icon.shown ~= false, "the icon holds the item's art")
  check(who.b <= box.t - SP.SECTION + 1 and who.b > who.t, string.format("the crafters' list ends a section above the order (%d, %d)", who.b, box.t))
  check(box.b <= card.b - SP.PAD + 1, "the order block sits PAD above the card's foot")
end

-- Members (#449, membros-mockup): the six tiles span the screen's width (two rows of three at 800), the filter rail
-- and the list are cards inside the screen, side by side at 1250 and the rail above the list at 800, and every
-- line of the rail and every part of the list lies inside its card (the loop above holds them in; this names them).
for _, W in ipairs({ 1250, 800 }) do
  local f, home = open("members", "roster", W, 720)
  check(f ~= nil, "Members opens at " .. W)
  local host = GuildOS.RosterFrame
  local resolve = resolver(f, W, 720)
  local screen = resolve(home)
  local band = resolve(host.kpiBand)
  local first, last = resolve(host.kpiCards.members), resolve(host.kpiCards[W >= 1000 and "addon" or "online"])
  check(math.abs(first.l - screen.l) <= 1 and math.abs(last.r - screen.r) <= 1 and math.abs(band.r - screen.r) <= 1,
    string.format("Members at %d: the tiles span the screen (%d..%d of %d..%d)", W, first.l, last.r, screen.l, screen.r))
  local rail, list = resolve(host.railCard), resolve(host.listCard)
  for name, r in pairs({ rail = rail, list = list }) do
    check(r.l >= screen.l - 1 and r.r <= screen.r + 1 and r.t >= band.b and r.b <= screen.b + 1,
      string.format("Members at %d: the %s card is inside the screen, under the tiles", W, name))
  end
  if W == 1250 then
    check(rail.r <= list.l - SP.GAP + 1 and math.abs(rail.t - list.t) <= 1, "Members at 1250: the rail on the left, the list beside it")
  else
    check(rail.b <= list.t - SP.GAP + 1 and math.abs(rail.l - list.l) <= 1, "Members at 800: the rail above the list")
  end
  local inside = true
  local function walk(fr, card, c)
    for _, k in ipairs(fr.children) do
      if k.shown and k.kind ~= "Texture" then
        local r = resolve(k)
        if (r.r - r.l) >= 1 and (r.l < c.l - SLACK or r.r > c.r + SLACK) then inside = false end
        walk(k, card, c)
      end
    end
  end
  walk(host.railCard, host.railCard, rail)
  walk(host.listCard, host.listCard, list)
  check(inside, "Members at " .. W .. ": every line of the rail and every part of the list inside its card")
end

check(opened >= 80, "every room's screens were opened at both widths (" .. opened .. ")")

print(("room-cards: %d checks passed"):format(checks))
