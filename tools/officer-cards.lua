-- The Officers' Room's screens as cards (#449, UI/Forms.lua), run against the whole addon (every file the TOC
-- loads) under a stub frame API: each screen of the room, opened at a wide window (1250px, two columns of
-- cards) and a narrow one (800px, one column), lays parchment cards on the wood, and every shown part of a card
-- (its fields, labels, pills, buttons, lists) lies inside the card. A list's rows inside its scroll frame are
-- held to the card's width (the frame clips them in height). Also: the wide window puts the cards in two
-- columns wherever a screen has more than one, the narrow one in one.
--
--   luajit -e 'ADDON="."' tools/officer-cards.lua
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

local function resolverFor(root, W, H) local r = resolver(root, W, H); return r end

-- Opens the window at W x H on an Officers' Room entry; returns the window and the shown area's board.
local function open(entryId, W, H)
  SlashCmdList.GUILDOS("")
  pcall(FLUSH)
  local f = GuildOS.RosterFrame
  f:SetSize(W, H)
  pcall(FLUSH)
  local UI = GuildOS.UI
  local entry
  for _, en in ipairs(UI:RoomEntries("officers")) do if en.id == entryId then entry = en end end
  check(entry, "the Officers' Room lists " .. entryId)
  local ok, err = pcall(function() UI:OpenWindow("officers"); f:SelectEntry("officers", entry, true) end)
  check(ok, entryId .. " opens: " .. tostring(err))
  pcall(FLUSH)
  local home = f.tabPanels[f.activeTab]
  local cw, ch = W - 30, H - (3 + 50 + 34 + 12) - (3 + 24 + 12)
  if f.sideNav and f.sideNav.shown then cw = cw - 198 end
  if f.entryRow and not f.entryRow.shown then ch = ch + 34 end
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
  -- The game sizes a scroll frame from its anchors a frame later: here from the resolved anchors, twice (a
  -- list inside a card is sized once the card is).
  for _ = 1, 2 do
    local resolve = resolverFor(f, W, H)
    local function settle(fr)
      if fr.kind == "ScrollFrame" and fr.shown then
        local r = resolve(fr)
        local w, h = math.floor(r.r - r.l + 0.5), math.floor(r.b - r.t + 0.5)
        if w > 0 and (w ~= fr.w or h ~= fr.h) then fr:SetSize(w, h) end
      end
      for _, c in ipairs(fr.children) do settle(c) end
    end
    settle(home)
    pcall(FLUSH)
  end
  if home.RefreshActive then pcall(home.RefreshActive) end
  pcall(FLUSH)
  return f, home
end

-- Every board shown under `home`.
local function boards(home)
  local out = {}
  local function walk(fr)
    local b = rawget(fr, "board")
    if type(b) == "table" and b.cards and visibleUnder(fr, home) then out[#out + 1] = b end
    for _, c in ipairs(fr.children) do walk(c) end
  end
  walk(home)
  return out
end

local ENTRIES = { "recruiting", "scanner", "trials", "engage", "suggest", "ranks", "inactive", "bulk", "presets", "remind",
  "marks", "audit", "alerts", "alertrules", "ban", "log", "motd", "alliance" }
local SLACK = 2
for _, W in ipairs({ 1250, 800 }) do
  for _, id in ipairs(ENTRIES) do
    local f, home = open(id, W, 720)
    local bs = boards(home)
    check(#bs >= 1, id .. " at " .. W .. ": the screen lays its cards on a board")
    local resolve, owner = resolver(f, W, 720)
    for _, b in ipairs(bs) do
      local shownCards, xs = 0, {}
      for _, card in ipairs(b.cards) do
        if card.shown then
          shownCards = shownCards + 1
          xs[(card.laid and card.laid.x or 0) > 0 and 2 or 1] = true
          local c = resolve(card)
          local function walk(fr, clipped)
            for _, k in ipairs(fr.children) do
              if k.shown then
                local inScroll = clipped or owner[k] ~= nil
                local art = k.kind == "Texture" and fr == card
                local empty = (k.kind == "FontString" and plain(k.text) == "")
                if not art and not empty then
                  local r = resolve(k)
                  local sized = (r.r - r.l) >= 1 or (r.b - r.t) >= 1
                  if sized then
                    local name = tostring(k.kind) .. " \"" .. plain(k.text or (rawget(k, "label") and k.label.text) or "") .. "\""
                    local where = string.format("%s at %d: \"%s\" holds its %s (%d,%d %dx%d in %dx%d)", id, W,
                      plain(card.title and card.title.text), name, r.l - c.l, r.t - c.t, r.r - r.l, r.b - r.t, c.r - c.l, c.b - c.t)
                    check(r.l >= c.l - SLACK and r.r <= c.r + SLACK, where .. ": across")
                    if not inScroll then check(r.t >= c.t - SLACK and r.b <= c.b + SLACK, where .. ": down") end
                  end
                end
                walk(k, inScroll)
              end
            end
          end
          walk(card, false)
        end
      end
      if W == 1250 and shownCards > 1 and not b.allSpan then
        check(b.two, id .. " at 1250: two columns of cards")
      end
      if W == 800 then check(not b.two and not xs[2], id .. " at 800: one column of cards") end
    end
  end
end

print(("officer-cards: %d checks passed"):format(checks))
