-- The Recruitment hub's Recruiting sub-tab as #373 laid it out ("panel with preview"), built from the
-- real Core/Core.lua, Core/Compat.lua, Core/Data.lua, Core/Style.lua, Core/Utils.lua, UI/Helpers.lua,
-- UI/Layout.lua, Modules/RecruitmentSystem.lua and UI/RosterFrame.lua under a stub frame API.
--
-- A status strip (ON or OFF, its switch, the interval, Send now), the ad beside the chat line it makes
-- and its length, the channel chips, then Welcome, Auto-invite and Beacon as sections that open in
-- place, shut by default. Every control still writes the setting it always wrote. In both interface
-- styles.
--
--   luajit -e 'ADDON="."' tools/recruiting-layout.lua
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
local Frame = {}
Frame.__index = Frame

local function newFrame(kind, parent)
  local f = setmetatable({ kind = kind, parent = parent, children = {}, shown = true, points = {}, scripts = {},
                           w = 0, h = 0, level = parent and ((parent.level or 0) + 1) or 0 }, Frame)
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
local function plainText(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

function Frame:SetSize(w, h) self.w, self.h = w, h; fire(self, "OnSizeChanged", w, h) end
function Frame:SetWidth(w) self.w = w; fire(self, "OnSizeChanged", self.w, self.h) end
function Frame:SetHeight(h) self.h = h; fire(self, "OnSizeChanged", self.w, self.h) end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:SetChecked(v) self.checked = v and true or nil end
function Frame:GetChecked() return self.checked end
function Frame:SetEnabled(v) self.disabled = not v end
function Frame:Enable() self.disabled = nil end
function Frame:Disable() self.disabled = true end
function Frame:IsEnabled() return not self.disabled end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints(other) self.points = { { "ALL", other } } end
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
function Frame:GetObjectType() return self.kind end
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
function Frame:CreateTexture() return newFrame("Texture", self) end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetFont(file, size) self.font = { file = file, size = size }; return true end
-- An edit box says its text changed, as the game's does; `typed` is false for a SetText.
function Frame:SetText(t)
  self.text = t
  if self.kind == "EditBox" then fire(self, "OnTextChanged", false) end
end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #plainText(self.text) * 6 end
-- A text with a width wraps: a line of 14px for every width's worth of it.
function Frame:GetStringHeight()
  local w = self:GetStringWidth()
  if self.w and self.w > 0 and w > 0 then return math.ceil(w / self.w) * 14 end
  return 14
end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function Frame:SetCursorPosition(n) self.cursor = n end
function Frame:HasFocus() return self.focus == true end
function Frame:SetFocus() self.focus = true end
function Frame:ClearFocus() self.focus = nil end
function Frame:SetAtlas(name) self.atlas = name end
for _, name in ipairs({ "SetClampedToScreen", "RegisterForClicks", "SetBackdrop", "SetBackdropColor",
  "SetBackdropBorderColor", "SetTexture", "SetTexCoord", "SetBlendMode", "SetAlpha", "SetShadowOffset",
  "SetShadowColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetTextInsets", "SetAutoFocus", "SetMaxLetters",
  "SetNumeric", "SetMultiLine", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDesaturated",
  "SetFrameStrata", "EnableMouse", "SetMovable", "RegisterForDrag", "SetColorTexture", "SetScale",
  "SetHorizTile", "SetVertTile", "SetResizeBounds", "SetClipsChildren", "SetScrollChild", "RegisterEvent",
  "SetDrawLayer", "SetFontObject", "SetSpacing", "SetNonSpaceWrap", "SetIndentedWordWrap", "SetMaxLines",
  "Raise", "SetRotation" }) do
  Frame[name] = function() end
end

function CreateFrame(kind, name, parent)
  local f = newFrame(kind, parent)
  if name then f.name = name; _G[name] = f end
  return f
end
UIParent = newFrame("Frame")
UIParent.w, UIParent.h = 1600, 900
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
GuildOSDB = {}

local queue = {}
C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end, NewTicker = function() return { Cancel = function() end } end }
local function flush()
  for _ = 1, 20 do
    if #queue == 0 then return end
    local due = queue
    queue = {}
    for _, fn in ipairs(due) do fn() end
  end
end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local NOW = 1757800000
function GetServerTime() return NOW end
function GetTime() return NOW end
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
function GetLocale() return "enUS" end
function hooksecurefunc() end
function debugstack() return "" end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strsplit = string.lower, function(sep, s)
  local out = {}
  for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end
  return unpack(out)
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
CLASS_ICON_TCOORDS = {}
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll() end
function UIDropDownMenu_Initialize() end
function UIFrameFadeIn() end
function GetRealmName() return "Firemaw" end
function UnitName() return "Ana" end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 60 end
function InCombatLockdown() return true end   -- the officer's popup never opens here
C_GuildInfo = { GuildRoster = function() end }
function IsInGuild() return true end
function GetGuildInfo() return "Chama", "Officer", 0 end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function CanViewOfficerNote() return true end
function CanGuildInvite() return true end
function GuildControlGetNumRanks() return 6 end
function GuildControlGetRankName(i) return ({ "GM", "Officer", "Veteran", "Member", "Alt", "Recruit" })[i] end
-- This character is in the Trade channel, as number 2.
local JOINED = { Trade = 2 }
function GetChannelName(name) return JOINED[name] or 0, name end
local sent = {}
function SendChatMessage(text, kind, _, num) sent[#sent + 1] = { text = text, kind = kind, num = num } end

-- ── Load ────────────────────────────────────────────────────────────────
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "0.83.0" }
dofile(ADDON .. "/Core/Core.lua")
GuildOS.SelfTest = { Register = function() end }
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
GuildOS.Style:Resolve()
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/UI/Spacing.lua")
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Forms.lua")
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/Modules/RosterColumns.lua")
dofile(ADDON .. "/Modules/GearAudit.lua")
dofile(ADDON .. "/UI/RosterFrame.lua")
dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Features.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
local UI, C, R = GuildOS.UI, GuildOS.Colors, GuildOS.Recruitment
function GuildOS:IsOfficer() return true end
function GuildOS:IsOnGuildDB() return true end
local said = {}
GuildOS.Print = function(_, m) said[#said + 1] = tostring(m) end
local beaconOn, beaconOpened, broadcasts = false, 0, 0
GuildOS.RecruitBeacon = { GetAd = function() return { enabled = beaconOn } end }
function GuildOS:ShowRecruitBeacon() beaconOpened = beaconOpened + 1 end
function GuildOS:CreateTrialsPanel() end
local broadcast0 = R.BroadcastStatus
R.BroadcastStatus = function(...) broadcasts = broadcasts + 1; return broadcast0(...) end

-- The ad every build starts from.
local AD = "<Chama> raids Kara and Gruul, Tue and Thu 20:00. Whisper ginv!"
local function freshDb()
  GuildOS.db = {
    settings = { officerMaxRank = 1, modules = {} },
    members = {},
    recruitment = { enabled = false, interval = 180, message = AD, discord = "discord.gg/chama",
                    welcomeEnabled = true, welcomeMessage = "Welcome!", channels = { "Trade" }, minRankIndex = 2,
                    autoInvite = { enabled = false, keyword = "ginv", minLevel = 0, classes = {}, cooldownSec = 300,
                                   whoFallback = "skip" } },
  }
end

-- ── Finding things ──────────────────────────────────────────────────────
local function walk(f, fn)
  fn(f)
  for _, c in ipairs(f.children) do walk(c, fn) end
end
local function findAll(root, pred)
  local out = {}
  walk(root, function(f) if pred(f) then out[#out + 1] = f end end)
  return out
end
local function button(root, text)
  return findAll(root, function(f) return f.kind == "Button" and f.label and f.label.text == text end)[1]
end
local function textOf(root, pattern)
  return findAll(root, function(f) return f.kind == "FontString" and plainText(f.text):find(pattern) end)[1]
end
local function click(btn)
  if not btn:IsEnabled() then return false end
  fire(btn, "OnClick")
  return true
end
local function typeInto(box, text)
  box.text = text
  fire(box, "OnTextChanged", true)
end
local function same(c, col) return c and math.abs(c[1] - col.r) < 1e-6 and math.abs(c[2] - col.g) < 1e-6 and math.abs(c[3] - col.b) < 1e-6 end
-- Where a frame was placed: the y of its TOPLEFT point.
local function topY(f)
  local p = f.points[1]
  return p and (p[5] or p[3])
end
local function topX(f)
  local p = f.points[1]
  return p and (type(p[2]) == "table" and p[4] or p[2])
end

-- Where a frame lies, from its points, in the panel's coordinates (y down): left, top, right, bottom. A text
-- with no width set is as wide as it reads. Enough of the client's anchoring for the cards' rows.
local function rectOf(f, memo)
  memo = memo or {}
  if memo[f] then return memo[f] end
  local w, h = f.w or 0, f.h or 0
  if f.kind == "FontString" then
    if w == 0 then w = f:GetStringWidth() end
    if h == 0 then h = f:GetStringHeight() end
  end
  if not f.parent or #f.points == 0 then
    local base = f.parent and rectOf(f.parent, memo) or { l = 0, t = 0, r = w, b = h }
    if f.scrollOwner then base = rectOf(f.scrollOwner, memo) end
    local r = { l = base.l, t = base.t, r = base.l + w, b = base.t + h }
    memo[f] = r
    return r
  end
  local L, R, T, B, CX, CY
  for _, p in ipairs(f.points) do
    if p[1] == "ALL" then
      local o = rectOf(p[2] or f.parent, memo)
      L, R, T, B = o.l, o.r, o.t, o.b
    else
      local point, rel, relPoint, x, y = p[1], nil, nil, 0, 0
      if type(p[2]) == "number" or p[2] == nil then x, y = p[2] or 0, p[3] or 0
      else rel, relPoint, x, y = p[2], p[3], p[4] or 0, p[5] or 0 end
      if type(relPoint) == "number" then relPoint, x, y = point, relPoint, x end
      rel = rel or f.parent
      relPoint = relPoint or point
      local o = rectOf(rel, memo)
      local ax = (relPoint:find("LEFT") and o.l) or (relPoint:find("RIGHT") and o.r) or (o.l + o.r) / 2
      local ay = (relPoint:find("TOP") and o.t) or (relPoint:find("BOTTOM") and o.b) or (o.t + o.b) / 2
      ax, ay = ax + x, ay - y
      if point:find("LEFT") then L = ax elseif point:find("RIGHT") then R = ax else CX = ax end
      if point:find("TOP") then T = ay elseif point:find("BOTTOM") then B = ay else CY = ay end
    end
  end
  if not L and not R then L = (CX or 0) - w / 2; R = L + w elseif not L then L = R - w elseif not R then R = L + w end
  if not T and not B then T = (CY or 0) - h / 2; B = T + h elseif not T then T = B - h elseif not B then B = T + h end
  memo[f] = { l = L, t = T, r = R, b = B }
  return memo[f]
end
-- Every shown descendant of each shown card lies inside the card (a pixel of slack for rounding).
local function cardsHoldTheirParts(board, what)
  local memo = {}
  for _, card in ipairs(board.cards) do
    if card.shown then
      local c = rectOf(card, memo)
      local function walk(f)
        for _, k in ipairs(f.children) do
          if k.shown and not k.__art then
            local r = rectOf(k, memo)
            local empty = (k.kind == "FontString" and plainText(k.text) == "") or (r.r - r.l < 1 and r.b - r.t < 1)
            if not empty then
              check(r.l >= c.l - 1 and r.r <= c.r + 1 and r.t >= c.t - 1 and r.b <= c.b + 1,
                what .. ": inside the card \"" .. tostring(card.title and card.title.text) .. "\" (" .. tostring(k.kind) .. " "
                .. tostring(k.text or (k.label and k.label.text) or "") .. " at " .. math.floor(r.l - c.l) .. "," .. math.floor(r.t - c.t)
                .. " " .. math.floor(r.r - r.l) .. "x" .. math.floor(r.b - r.t) .. " in " .. math.floor(c.r - c.l) .. "x" .. math.floor(c.b - c.t) .. ")")
            end
            walk(k)
          end
        end
      end
      walk(card)
    end
  end
end

-- Builds an officer's tab at `width` and opens the Recruiting sub-tab. Returns what the checks read.
local function build(width, anniversary)
  GuildOS.Client.isAnniversary = anniversary
  local panel = CreateFrame("Frame", nil, UIParent)
  panel:Hide()
  local ok, err = pcall(GuildOS.CreateRecruitmentPanel, GuildOS, panel, panel)
  check(ok, "the officer's recruitment tab builds: " .. tostring(err))
  panel:SetSize(width, 600)
  panel:Show()
  flush()
  -- The layout runs under SafeCall: an error in it would only be recorded.
  local errs = GuildOS.State.errors
  check(#errs == 0, "the tab lays itself out without an error: " .. tostring(errs[#errs] and errs[#errs].msg))
  local t = { panel = panel, sub = panel.subPanels.recruiting.panel, board = panel.recruitBoard, cards = panel.recruitCards }
  t.content = t.board.content
  t.content.scrollOwner = t.board.scroll
  local post = t.cards.post
  t.sendNow = button(post, "Send Now")
  t.toggle = button(post, "Enable") or button(post, "Disable")
  t.interval = findAll(post, function(f) return f.kind == "EditBox" end)[1]
  t.state = textOf(post, "^O")
  t.dot = findAll(post, function(f) return f.kind == "Texture" and f.vertex and not f.__art end)[1]
  t.area = findAll(t.cards.message, function(f) return f.edit ~= nil end)[1]
  t.msg = t.area.edit
  t.msgSave = button(t.cards.message, "Save")
  t.preview = textOf(t.sub, "Ana:") or textOf(t.sub, "Join a channel")
  t.count = textOf(t.sub, "^%d+/255$")
  return t
end
local function enter(box) fire(box, "OnEnterPressed") end
local function laid(card) return card.laid or {} end

-- ── 1. Posting: on or off, the interval, Send now ───────────────────────
freshDb()
local t = build(1000, true)
check(t.board.width == 1000 - 20 - UI.SCROLL_GUTTER, "the board is as wide as the area under the bar, less the scroll bar's gutter")
check(t.board.two, "from 900px the cards go in two columns")
check(laid(t.cards.post).x == 0 and laid(t.cards.post).y == 0, "Post in the channels leads, top left")
check(laid(t.cards.welcome).x > 0 and laid(t.cards.welcome).y == 0, "Welcome leads the right column")
for _, k in ipairs({ "message", "channels", "help" }) do
  check(laid(t.cards[k]).x == 0, k .. " is in the left column, under posting")
end
check(laid(t.cards.invite).x > 0, "auto-invite is in the right column")
check(t.state.text == "OFF" and same(t.state.color, C.danger) and same(t.dot.vertex, C.danger), "off: OFF and its dot in danger")
check(t.toggle.label.text == "Enable" and t.toggle.variant == "primary", "the switch is the card's primary action and says what a click does")
check(click(t.toggle) and GuildOS.db.recruitment.enabled == true, "Enable switches recruiting on (db.recruitment.enabled)")
check(t.state.text == "ON" and same(t.state.color, C.ok) and same(t.dot.vertex, C.ok) and t.toggle.label.text == "Disable",
  "on: ON and its dot in ok, and the switch offers Disable")
click(t.toggle)
check(GuildOS.db.recruitment.enabled == false and t.state.text == "OFF", "and Disable switches it off again")
check(t.interval.text == "180", "the interval field shows the saved interval")
check(textOf(t.cards.post, "^Interval %(sec%)$"), "its label is above it, without the colon")
typeInto(t.interval, "300")
enter(t.interval)
check(GuildOS.db.recruitment.interval == 300, "Enter writes db.recruitment.interval: the field saves on its own")
typeInto(t.interval, "240")
fire(t.interval, "OnEditFocusLost")
check(GuildOS.db.recruitment.interval == 240, "and so does leaving the field")
typeInto(t.interval, "30")
enter(t.interval)
check(GuildOS.db.recruitment.interval == 240 and t.interval.text == "240", "under 60 seconds is refused and the field put back")
check(not textOf(t.cards.post, "next post"), "no next-post countdown: the module keeps no next time")
sent = {}
click(t.sendNow)
check(#sent == 1 and sent[1].text == AD and sent[1].num == 2, "Send now posts the ad to the saved channel")
check(not button(t.cards.post, "Save"), "no Save beside the interval")

-- ── 2. The ad and how it appears ────────────────────────────────────────
check(t.msg.text == AD and t.area.h == 72, "the ad sits in a five-line field, so a full 255-byte ad fits, the saved message in it")
check(plainText(t.preview.text) == "[2. Trade] Ana: " .. AD, "the preview is the chat line: first channel, its number, this character")
check(t.count.text == #AD .. "/255" and same(t.count.color, C.textSoft), "the count is the ad's length against 255")
local memo = {}
check(rectOf(textOf(t.cards.message, "^Preview$"), memo).l > rectOf(t.area, memo).r, "wide, the preview is a column beside the ad")
typeInto(t.msg, AD .. " Extra")
check(plainText(t.preview.text) == "[2. Trade] Ana: " .. AD .. " Extra" and t.count.text == (#AD + 6) .. "/255",
  "typing changes the preview and the count at once")
check(GuildOS.db.recruitment.message == AD, "typing alone saves nothing")
typeInto(t.msg, "Line one\nline two")
check(t.msg.text == "Line one line two", "a line break becomes a space, as the send cleans it: a chat message has one line")
-- Enter typed in the middle of a word: one line break right before the cursor, which just goes.
t.msg.GetCursorPosition = function() return 3 end
typeInto(t.msg, "Ka" .. string.char(10) .. "ra")
check(t.msg.text == "Kara" and t.msg.cursor == 2, "Enter typed inside a word leaves it whole, the cursor where it was")
t.msg.GetCursorPosition = nil
typeInto(t.msg, string.rep("a", 240))
check(same(t.count.color, C.warn), "near the limit the count turns warn")
typeInto(t.msg, string.rep("\208\175", 130))
check(t.count.text == "260/255" and same(t.count.color, C.danger), "past 255 bytes it is danger")
click(t.msgSave)
check(GuildOS.db.recruitment.message == AD and said[#said] == "The game sends at most 255 characters.",
  "and the card's Save refuses it, saying why")
check(t.msgSave.variant == "primary", "the message card's one Save is its primary action")
typeInto(t.msg, "Raiding Tue/Thu, whisper ginv")
local chanTop = laid(t.cards.channels).y
typeInto(t.msg, string.rep("word ", 50))
flush()
check(laid(t.cards.channels).y > chanTop, "a full ad's chat line wraps past the field's height: the preview grows, the cards under it move")
typeInto(t.msg, "Raiding Tue/Thu, whisper ginv")
flush()
check(laid(t.cards.channels).y == chanTop, "and a short ad puts them back")
enter(t.msg)
check(GuildOS.db.recruitment.message == "Raiding Tue/Thu, whisper ginv", "Enter saves db.recruitment.message")
typeInto(t.msg, "Ana | Bob")
click(t.msgSave)
check(GuildOS.db.recruitment.message == "Raiding Tue/Thu, whisper ginv", "a | the game refuses is not kept")

-- ── 3. The channels, who helps, the broadcast ───────────────────────────
local chans = t.cards.channels
local trade, lfg, gr = button(chans, "Trade"), button(chans, "LookingForGroup"), button(chans, "GuildRecruitment")
check(trade and lfg and gr, "Anniversary offers its three channels as pills")
check(trade.variant == "chip" and trade.__selected and not lfg.__selected and not gr.__selected, "the channel it posts to is an on pill")
click(lfg)
check(R:HasChannel(GuildOS.db.recruitment.channels, "LookingForGroup") and lfg.__selected, "a pill adds its channel")
click(trade)
check(not R:HasChannel(GuildOS.db.recruitment.channels, "Trade") and not trade.__selected, "and takes it off")
check(plainText(t.preview.text) == "Join a channel to post the recruitment message.",
  "a saved channel this character is not in gets no preview: the send skips it")
click(trade)   -- back, after LookingForGroup
check(plainText(t.preview.text):find("^%[2%. Trade%] Ana: "),
  "the preview takes the first saved channel this character is in, as the send does")
click(trade); click(lfg)
check(plainText(t.preview.text) == "Join a channel to post the recruitment message.", "with no channel it says to pick one")
local chanBox = findAll(chans, function(f) return f.kind == "EditBox" end)[1]
local hint = textOf(chans, "^Click a channel below")
check(chanBox and chanBox.saveButton.label.text == "Add" and not hint.shown, "the other-channel field, its Add, and no hint while there is no channel of one's own")
JOINED.ChamaAds = 5   -- this character is in it, so the ad can go there
typeInto(chanBox, "ChamaAds")
click(chanBox.saveButton)
check(GuildOS.db.recruitment.channels[1] == "ChamaAds", "Add writes the channel into db.recruitment.channels")
local custom = findAll(chans, function(f) return f.kind == "Button" and f.shown and f._ch == "ChamaAds" end)[1]
flush()
check(custom and custom.__selected and custom.label.text:find("x$") and hint.shown, "its pill is on, keeps its x, under the hint")
check(plainText(t.preview.text):find("^%[5%. ChamaAds%] Ana: "), "and, being in it, it is now the preview's channel")
click(custom)
check(#GuildOS.db.recruitment.channels == 0 and not custom.shown and not hint.shown, "a click on its pill takes it off")
click(trade)
local rankDrop = findAll(t.cards.help, function(f) return f.options ~= nil and f.Select end)[1]
check(rankDrop and rankDrop.label.text == "Any rank", "who helps is a select, on every rank")
local values = {}
for _, o in ipairs(rankDrop.options) do values[#values + 1] = o.text end
check(table.concat(values, ",") == "Any rank,Up to Veteran,Up to Member,Up to Alt", "it lists every rank and the member ranks in turn")
rankDrop:Select(2)
check(GuildOS.db.recruitment.postMaxRank == 2 and rankDrop.label.text == "Up to Veteran", "a choice writes db.recruitment.postMaxRank")
rankDrop:Select(rankDrop.options[1].value)
check(GuildOS.db.recruitment.postMaxRank == nil, "and every rank clears it")
local before = broadcasts
check(click(button(t.cards.help, "Broadcast to Members")) and broadcasts == before + 1, "Broadcast to Members sends the settings")

-- ── 4. Welcome, auto-invite, the beacon ─────────────────────────────────
local welcome = t.cards.welcome
local wcb = findAll(welcome, function(f) return f.kind == "CheckButton" end)[1]
check(wcb.checked, "the welcome's switch reads on")
wcb:SetChecked(false)
fire(wcb, "OnClick")
check(GuildOS.db.recruitment.welcomeEnabled == false, "its checkbox writes welcomeEnabled at once")
local boxes = findAll(welcome, function(f) return f.kind == "EditBox" end)
check(boxes[1].text == "discord.gg/chama" and boxes[2].text == "Welcome!", "the Discord link and welcome are in their fields")
local wsave = button(welcome, "Save")
check(wsave and wsave.variant == "primary", "one Save for the card")
check(#findAll(welcome, function(f) return f.kind == "Button" and f.label and f.label.text == "Save" end) == 1, "and no other")
typeInto(boxes[1], "discord.gg/new")
typeInto(boxes[2], "Hi there!")
click(wsave)
check(GuildOS.db.recruitment.discord == "discord.gg/new" and GuildOS.db.recruitment.welcomeMessage == "Hi there!",
  "the card's Save writes discord and welcomeMessage")
-- Several welcomes (#419): Add opens a row under the first, the Save puts a second on the list.
local function shownRemoves()
  return findAll(welcome, function(f) return f.kind == "Button" and f.shown and f.label and f.label.text == "Remove" end)
end
check(boxes[2].shown and not boxes[3].shown and #shownRemoves() == 0, "one welcome: one row, which cannot be removed")
local hOne = laid(welcome).h
check(click(button(welcome, "Add message")) and boxes[3].shown and boxes[3].text == "", "Add opens an empty row")
flush()
check(laid(welcome).h == hOne + GuildOS.Forms.FIELD_H + GuildOS.Forms.ROW_GAP and #shownRemoves() == 1, "the card grows by a row; only the new row can go, its Remove at its right")
typeInto(boxes[3], "Glad to have you!")
enter(boxes[3])
local wl = GuildOS.db.recruitment.welcomeMessages
check(#wl == 2 and wl[1] == "Hi there!" and wl[2] == "Glad to have you!" and GuildOS.db.recruitment.welcomeMessage == "Hi there!",
  "Enter saves the second welcome; the first stays welcomeMessage")
check(#shownRemoves() == 2, "with two, either can go")
click(shownRemoves()[1])
flush()
wl = GuildOS.db.recruitment.welcomeMessages
check(#wl == 1 and GuildOS.db.recruitment.welcomeMessage == "Glad to have you!" and boxes[2].text == "Glad to have you!"
  and not boxes[3].shown and laid(welcome).h == hOne, "Remove on the first: the second moves up, the row goes")
local rules = findAll(welcome, function(f) return f.kind == "CheckButton" end)[2]
rules:SetChecked(true)
fire(rules, "OnClick")
check(GuildOS.db.recruitment.welcomeRules == true, "the rules' ending writes welcomeRules at once")

local invite = t.cards.invite
local cb = findAll(invite, function(f) return f.kind == "CheckButton" end)[1]
check(cb and cb:IsEnabled(), "auto-invite's controls are enabled on Anniversary")
cb:SetChecked(true)
fire(cb, "OnClick")
local ai = GuildOS.db.recruitment.autoInvite
check(ai.enabled == true, "its checkbox writes autoInvite.enabled")
local kw, lvl = unpack(findAll(invite, function(f) return f.kind == "EditBox" end))
typeInto(kw, "Join")
typeInto(lvl, "58")
click(button(invite, "Save"))
check(ai.keyword == "join" and ai.minLevel == 58, "the card's Save writes the keyword and the level")
check(click(button(invite, "MAGE")) and ai.classes.MAGE and button(invite, "MAGE").__selected, "a class pill writes autoInvite.classes")
local fb = findAll(invite, function(f) return f.options ~= nil and f.Select end)[1]
fb:Select("invite")
check(ai.whoFallback == "invite" and fb.label.text == "Invite them", "the fallback is a select and writes autoInvite.whoFallback")
check(textOf(t.cards.beacon, "^Off$") and click(button(t.cards.beacon, "Edit Beacon")) and beaconOpened == 1,
  "the beacon says it is off and opens its composer")
cardsHoldTheirParts(t.board, "wide")
check(t.content.h < 15000, "the board's content holds every card, well under 15000px")

-- ── 5. Not on this client ───────────────────────────────────────────────
freshDb()
local f = build(1000, false)
local fi = f.cards.invite
check(not button(f.cards.channels, "GuildRecruitment"), "the Anniversary-only channel is not offered")
check(textOf(fi, "^This game does not let an addon invite"), "where no addon may invite, the card says why first")
local fcb = findAll(fi, function(f2) return f2.kind == "CheckButton" end)[1]
check(not fcb:IsEnabled() and not button(fi, "Save"):IsEnabled() and not button(fi, "MAGE"):IsEnabled()
  and not findAll(fi, function(f2) return f2.options ~= nil and f2.Select end)[1]:IsEnabled(), "and its controls are kept, disabled")

-- Join requests, where its module runs (not Anniversary), is one more card.
GuildOS.JoinRequests = { OpenCount = function() return 2 end }
function GuildOS:JoinRequestsOpenText(k) return k .. " open" end
local jr = build(1000, false)
local jrCard
for _, c in ipairs(jr.board.cards) do if c.title and c.title.text == "Join requests" then jrCard = c end end
check(jrCard and textOf(jrCard, "^2 open$") and button(jrCard, "Open the list"), "join requests: its count and its button")
GuildOS.JoinRequests, GuildOS.JoinRequestsOpenText = nil, nil

-- ── 6. Narrow ───────────────────────────────────────────────────────────
freshDb()
local n = build(440, true)
check(not n.board.two, "narrow, one column")
local order, prevY = { "post", "message", "channels", "help", "welcome", "invite", "beacon" }, -1
for _, k in ipairs(order) do
  check(laid(n.cards[k]).x == 0 and laid(n.cards[k]).y > prevY, k .. " comes in order, as wide as the board")
  prevY = laid(n.cards[k]).y
end
local nm = {}
check(rectOf(textOf(n.cards.message, "^Preview$"), nm).l == rectOf(n.area, nm).l, "and the preview goes under the ad")
typeInto(n.msg, "Raiding Tue/Thu, whisper ginv")
flush()
local nChanTop = laid(n.cards.channels).y
typeInto(n.msg, string.rep("word ", 50))
flush()
check(laid(n.cards.channels).y > nChanTop, "a long line wraps past the field: the preview grows and the cards under it move down")
cardsHoldTheirParts(n.board, "narrow")
check(n.content.h < 15000, "the narrow board is well under 15000px")

-- ── 7. The WoW: Forever client, with its atlases: the same look (#449) ───
C_Texture = { GetAtlasInfo = function() return { width = 16, height = 16 } end }
GuildOSDB.style = "forever"
check(GuildOS.Style:Resolve() == "salao", "the stub client has the atlases, the look stays the Salão's")
freshDb()
local fv = build(1000, true)
check(fv.state.text == "OFF" and same(fv.state.color, GuildOS.Colors.danger), "Forever: the same status")
check(plainText(fv.preview.text) == "[2. Trade] Ana: " .. AD and fv.count.text == #AD .. "/255", "Forever: the same preview")
click(fv.toggle)
check(GuildOS.db.recruitment.enabled == true and fv.state.text == "ON", "Forever: the switch still writes enabled")
cardsHoldTheirParts(fv.board, "Forever")

flush()
check(#GuildOS.State.errors == 0, "no click or relayout recorded an error: "
  .. tostring(GuildOS.State.errors[1] and GuildOS.State.errors[1].msg))

print(("recruiting-layout: %d checks passed"):format(checks))
