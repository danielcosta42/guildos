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
dofile(ADDON .. "/UI/Helpers.lua")
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
  local t = { panel = panel, sub = panel.subPanels.recruiting.panel }
  t.scroll = findAll(t.sub, function(f) return f.kind == "ScrollFrame" end)[1]
  t.content = t.scroll.children[1]
  t.sendNow = button(t.sub, "Send Now")
  t.strip = t.sendNow.parent
  t.toggle = button(t.strip, "Enable") or button(t.strip, "Disable")
  t.interval = findAll(t.strip, function(f) return f.kind == "EditBox" end)[1]
  t.state = textOf(t.strip, "^O")
  t.dot = findAll(t.strip, function(f) return f.kind == "Texture" and f.vertex and not f.__art end)[1]
  t.area = findAll(t.sub, function(f) return f.edit ~= nil end)[1]
  t.msg = t.area.edit
  t.preview = textOf(t.sub, "Ana:") or textOf(t.sub, "Join a channel")
  t.count = textOf(t.sub, "^%d+/255$")
  t.sections = {}
  for _, title in ipairs({ "Welcome Message (New Members)", "Auto-Invite (whisper keyword)", "Recruitment Beacon (mesh)" }) do
    local head = findAll(t.content, function(f)
      return f.kind == "Button" and f.parent == t.content and textOf(f, "^" .. title:gsub("%p", "%%%0") .. "$") ~= nil
    end)[1]
    check(head, "a section header for " .. title)
    local i
    for k, c in ipairs(t.content.children) do if c == head then i = k end end
    t.sections[#t.sections + 1] = { head = head, body = t.content.children[i + 1],
      status = findAll(head, function(f) return f.kind == "FontString" and f.points[1] and f.points[1][1] == "RIGHT" end)[1] }
  end
  return t
end

-- ── 1. The strip ────────────────────────────────────────────────────────
freshDb()
local t = build(1000, true)
check(topX(t.scroll) == 0 and topY(t.scroll) == -UI.GAP, "the form starts flush with the sub-tab bar, UI.GAP below it")
check(t.content.w == 1000 - 20 - 28 - UI.SCROLL_GUTTER, "the scroll child is as wide as the bar, less the card's padding and the scroll bar's gutter")
check(topX(t.strip) == 0 and topY(t.strip) == 0 and t.strip.points[1][2] == t.content, "the strip is the form's first line, at x = 0")
check(t.state.text == "OFF" and same(t.state.color, C.danger) and same(t.dot.vertex, C.danger), "off: OFF and its dot in danger")
check(t.toggle.label.text == "Enable", "the switch says what a click does")
check(click(t.toggle) and GuildOS.db.recruitment.enabled == true, "Enable switches recruiting on (db.recruitment.enabled)")
check(t.state.text == "ON" and same(t.state.color, C.ok) and same(t.dot.vertex, C.ok) and t.toggle.label.text == "Disable",
  "on: ON and its dot in ok, and the switch offers Disable")
click(t.toggle)
check(GuildOS.db.recruitment.enabled == false and t.state.text == "OFF", "and Disable switches it off again")
check(t.interval.text == "180", "the interval field shows the saved interval")
typeInto(t.interval, "300")
click(t.interval.saveButton)
check(GuildOS.db.recruitment.interval == 300, "its Save writes db.recruitment.interval")
typeInto(t.interval, "30")
click(t.interval.saveButton)
check(GuildOS.db.recruitment.interval == 300 and t.interval.text == "300", "under 60 seconds is refused and the field put back")
check(not textOf(t.strip, "next post"), "no next-post countdown: the module keeps no next time")
sent = {}
click(t.sendNow)
check(#sent == 1 and sent[1].text == AD and sent[1].num == 2, "Send now posts the ad to the saved channel")
local stripH = t.strip.h
check(stripH == 2 * UI.GAP + 22, "wide, the strip is one row")

-- ── 2. The ad and how it appears ────────────────────────────────────────
check(t.msg.text == AD and t.area.h == 72, "the ad sits in a five-line field, so a full 255-byte ad fits, the saved message in it")
check(plainText(t.preview.text) == "[2. Trade] Ana: " .. AD, "the preview is the chat line: first channel, its number, this character")
check(t.count.text == #AD .. "/255" and same(t.count.color, C.textSoft), "the count is the ad's length against 255")
local twoColX = topX(textOf(t.sub, "^Preview$"))
check(twoColX and twoColX > 0, "wide, the preview is a column beside the ad")
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
click(t.msg.saveButton)
check(GuildOS.db.recruitment.message == AD and said[#said] == "The game sends at most 255 characters.",
  "and Save refuses it, saying why")
typeInto(t.msg, "Raiding Tue/Thu, whisper ginv")
local chanBlock = t.content.children[5]
check(button(chanBlock, "Trade"), "the channels come under the ad")
local chanTop = topY(chanBlock)
typeInto(t.msg, string.rep("word ", 50))
-- Wide, a full ad wraps to four lines: inside the five-line field, nothing below moves.
check(topY(chanBlock) == chanTop, "a full ad fits beside the field: what is under it stays")
typeInto(t.msg, "Raiding Tue/Thu, whisper ginv")
click(t.msg.saveButton)
check(GuildOS.db.recruitment.message == "Raiding Tue/Thu, whisper ginv", "Save writes db.recruitment.message")
check(topY(chanBlock) == chanTop, "and a short ad puts the rows back")
typeInto(t.msg, "Ana | Bob")
click(t.msg.saveButton)
check(GuildOS.db.recruitment.message == "Raiding Tue/Thu, whisper ginv", "a | the game refuses is not kept")

-- ── 3. The channels, who helps, the broadcast ───────────────────────────
local trade, lfg, gr = button(t.sub, "Trade"), button(t.sub, "LookingForGroup"), button(t.sub, "GuildRecruitment")
check(trade and lfg and gr, "Anniversary offers its three channels as chips")
check(trade.__selected and not lfg.__selected and not gr.__selected, "the channel it posts to is the selected chip")
click(lfg)
check(R:HasChannel(GuildOS.db.recruitment.channels, "LookingForGroup") and lfg.__selected, "a chip adds its channel")
click(trade)
check(not R:HasChannel(GuildOS.db.recruitment.channels, "Trade") and not trade.__selected, "and takes it off")
check(plainText(t.preview.text) == "Join a channel to post the recruitment message.",
  "a saved channel this character is not in gets no preview: the send skips it")
click(trade)   -- back, after LookingForGroup
check(plainText(t.preview.text):find("^%[2%. Trade%] Ana: "),
  "the preview takes the first saved channel this character is in, as the send does")
click(trade); click(lfg)
check(plainText(t.preview.text) == "Join a channel to post the recruitment message.", "with no channel it says to pick one")
local chanBox = findAll(t.sub, function(f) return f.kind == "EditBox" and f.saveButton and f.saveButton.label.text == "Add" end)[1]
local hint = textOf(t.sub, "^Click a channel below")
check(chanBox and not hint.shown, "the other-channel field, and no hint while there is no channel of one's own")
JOINED.ChamaAds = 5   -- this character is in it, so the ad can go there
typeInto(chanBox, "ChamaAds")
click(chanBox.saveButton)
check(GuildOS.db.recruitment.channels[1] == "ChamaAds", "Add writes the channel into db.recruitment.channels")
local custom = findAll(t.sub, function(f) return f.kind == "Button" and f.shown and f._ch == "ChamaAds" end)[1]
check(custom and custom.__selected and custom.label.text:find("x$") and hint.shown, "its chip is selected, keeps its x, under the hint")
check(plainText(t.preview.text):find("^%[5%. ChamaAds%] Ana: "), "and, being in it, it is now the preview's channel")
click(custom)
check(#GuildOS.db.recruitment.channels == 0 and not custom.shown and not hint.shown, "a click on its chip takes it off")
click(trade)
local rankBtn = button(t.sub, "Any rank")
check(rankBtn and click(rankBtn) and GuildOS.db.recruitment.postMaxRank == 2 and rankBtn.label.text == "Up to Veteran",
  "who helps cycles db.recruitment.postMaxRank")
local before = broadcasts
check(click(button(t.sub, "Broadcast to Members")) and broadcasts == before + 1, "Broadcast to Members sends the settings")

-- ── 4. The sections ─────────────────────────────────────────────────────
local welcome, invite, beacon = t.sections[1], t.sections[2], t.sections[3]
check(not welcome.body.shown and not invite.body.shown and not beacon.body.shown, "the three sections start shut")
check(welcome.status.text == "ON" and same(welcome.status.color, C.ok), "Welcome's header says ON")
check(invite.status.text == "OFF", "Auto-invite's header says OFF where the game lets an addon invite")
check(beacon.status.text == "Off", "the beacon's header says it is off")
local h0, inviteY = t.content.h, topY(invite.head)
check(t.content.h < 15000 and t.content.h > -topY(beacon.head) + 28, "the scroll child holds every row, well under 15000px")
click(welcome.head)
check(welcome.body.shown and button(welcome.body, "Disable"), "opening Welcome shows its controls")
check(topY(invite.head) == inviteY - 4 - welcome.body.h - UI.GAP, "and moves what is under it down by its height")
check(t.content.h == h0 + 4 + welcome.body.h + UI.GAP, "and the scroll child grows by as much")
check(click(button(welcome.body, "Disable")) and GuildOS.db.recruitment.welcomeEnabled == false
  and welcome.status.text == "OFF" and same(welcome.status.color, C.danger), "its switch writes welcomeEnabled, the header follows")
local boxes = findAll(welcome.body, function(f) return f.kind == "EditBox" end)
check(boxes[1].text == "discord.gg/chama" and boxes[2].text == "Welcome!", "the Discord link and welcome are in their fields")
typeInto(boxes[1], "discord.gg/new")
click(boxes[1].saveButton)
typeInto(boxes[2], "Hi there!")
click(boxes[2].saveButton)
check(GuildOS.db.recruitment.discord == "discord.gg/new" and GuildOS.db.recruitment.welcomeMessage == "Hi there!",
  "their Saves write discord and welcomeMessage")
-- Several welcomes (#419): Add opens a row under the first, its Save puts a second on the list.
local function shownRemoves()
  return findAll(welcome.body, function(f) return f.kind == "Button" and f.shown and f.label and f.label.text == "Remove" end)
end
check(boxes[2].shown and not boxes[3].shown and #shownRemoves() == 0, "one welcome: one row, which cannot be removed")
local hOne = welcome.body.h
check(click(button(welcome.body, "Add message")) and boxes[3].shown and boxes[3].text == "", "Add opens an empty row")
check(welcome.body.h == hOne + 28 and #shownRemoves() == 1, "the section grows by a row; only the new row can go")
typeInto(boxes[3], "Glad to have you!")
click(boxes[3].saveButton)
local wl = GuildOS.db.recruitment.welcomeMessages
check(#wl == 2 and wl[1] == "Hi there!" and wl[2] == "Glad to have you!" and GuildOS.db.recruitment.welcomeMessage == "Hi there!",
  "its Save adds the second welcome; the first stays welcomeMessage")
check(#shownRemoves() == 2, "with two, either can go")
click(shownRemoves()[1])
wl = GuildOS.db.recruitment.welcomeMessages
check(#wl == 1 and GuildOS.db.recruitment.welcomeMessage == "Glad to have you!" and boxes[2].text == "Glad to have you!"
  and not boxes[3].shown and welcome.body.h == hOne, "Remove on the first: the second moves up, the row goes")
click(welcome.head)
check(not welcome.body.shown and topY(invite.head) == inviteY and t.content.h == h0, "shut again, it gives the room back")

click(invite.head)
local cb = findAll(invite.body, function(f) return f.kind == "CheckButton" end)[1]
check(invite.body.shown and cb and cb:IsEnabled(), "opening Auto-invite shows its controls, enabled on Anniversary")
cb:SetChecked(true)
fire(cb, "OnClick")
local ai = GuildOS.db.recruitment.autoInvite
check(ai.enabled == true and invite.status.text == "ON", "its checkbox writes autoInvite.enabled, the header follows")
local kw, lvl = unpack(findAll(invite.body, function(f) return f.kind == "EditBox" end))
typeInto(kw, "Join")
click(kw.saveButton)
typeInto(lvl, "58")
click(lvl.saveButton)
check(ai.keyword == "join" and ai.minLevel == 58, "the keyword and level Saves write autoInvite")
check(click(button(invite.body, "MAGE")) and ai.classes.MAGE and button(invite.body, "MAGE").__selected, "a class chip writes autoInvite.classes")
check(click(button(invite.body, "Skip them")) and ai.whoFallback == "invite", "the fallback writes autoInvite.whoFallback")
local beaconY = topY(beacon.head)
check(beaconY < topY(invite.head) - 28, "the beacon's header sits under the open section")
click(beacon.head)
check(beacon.body.shown and click(button(beacon.body, "Edit Beacon")) and beaconOpened == 1, "the beacon opens its composer")

-- Open for the session: a tab built again keeps them open; the narrow tab below reads them shut.
local again = build(1000, true)
check(again.sections[2].body.shown and again.sections[3].body.shown and not again.sections[1].body.shown,
  "built again in the same session, the sections open stay open")
click(again.sections[2].head)
click(again.sections[3].head)

-- ── 5. Not on this client ───────────────────────────────────────────────
freshDb()
local f = build(1000, false)
local fi = f.sections[2]
check(fi.status.text == "not on this client" and same(fi.status.color, C.textSoft), "where no addon may invite, the header says so")
check(not button(f.sub, "GuildRecruitment"), "and the Anniversary-only channel is not offered")
click(fi.head)
check(textOf(fi.body, "^This game does not let an addon invite"), "opened, it says why first")
local fcb = findAll(fi.body, function(f2) return f2.kind == "CheckButton" end)[1]
local fkw = findAll(fi.body, function(f2) return f2.kind == "EditBox" end)[1]
check(not fcb:IsEnabled() and not fkw.saveButton:IsEnabled() and not button(fi.body, "MAGE"):IsEnabled()
  and not button(fi.body, "Skip them"):IsEnabled(), "and its controls are kept, disabled")
click(fi.head)

-- Join requests, where its module runs (not Anniversary), is one more section of the same kind.
GuildOS.JoinRequests = { OpenCount = function() return 2 end }
function GuildOS:JoinRequestsOpenText(k) return k .. " open" end
local jr = build(1000, false)
local jrHead = findAll(jr.content, function(f2) return f2.kind == "Button" and textOf(f2, "^Join requests$") end)[1]
local jrBody
for k, c in ipairs(jr.content.children) do if c == jrHead then jrBody = jr.content.children[k + 1] end end
check(jrHead and textOf(jrHead, "^2 open$") and not jrBody.shown, "join requests: shut, its count on the header")
click(jrHead)
check(jrBody.shown and button(jrBody, "Open the list"), "and opened, its button")
click(jrHead)
GuildOS.JoinRequests, GuildOS.JoinRequestsOpenText = nil, nil

-- ── 6. Narrow ───────────────────────────────────────────────────────────
local n = build(400, true)
check(n.content.w == 400 - 20 - 28 - UI.SCROLL_GUTTER, "narrow, the scroll child still stops short of the scroll bar")
check(n.strip.h > stripH, "the strip wraps onto another row")
check(topX(textOf(n.sub, "^Preview$")) == 0, "and the preview goes under the ad")
typeInto(n.msg, "Raiding Tue/Thu, whisper ginv")
local nChan = n.content.children[5]
local nChanTop = topY(nChan)
typeInto(n.msg, string.rep("word ", 50))
check(topY(nChan) < nChanTop, "narrow, a long line wraps past the field: the preview grows and what is under it moves down")
for _, b in ipairs(findAll(n.sub, function(f2) return f2.kind == "Button" and f2._ch and f2.shown end)) do
  check(topX(b) + b.w <= n.content.w, "chip " .. b._ch .. " stays inside the width")
end
check(n.content.h < 15000, "the narrow scroll child is well under 15000px")

-- ── 7. The WoW: Forever client, with its atlases: the same look (#449) ───
C_Texture = { GetAtlasInfo = function() return { width = 16, height = 16 } end }
GuildOSDB.style = "forever"
check(GuildOS.Style:Resolve() == "salao", "the stub client has the atlases, the look stays the Salão's")
freshDb()
local fv = build(1000, true)
check(fv.state.text == "OFF" and same(fv.state.color, GuildOS.Colors.danger) and fv.strip.h == stripH,
  "Forever: the same strip")
check(plainText(fv.preview.text) == "[2. Trade] Ana: " .. AD and fv.count.text == #AD .. "/255", "Forever: the same preview")
check(not fv.sections[1].body.shown and not fv.sections[2].body.shown and not fv.sections[3].body.shown,
  "Forever: the sections start shut")
click(fv.sections[2].head)
check(fv.sections[2].body.shown and topY(fv.sections[3].head) < topY(fv.sections[2].head) - 28, "Forever: a section opens in place")
click(fv.toggle)
check(GuildOS.db.recruitment.enabled == true and fv.state.text == "ON", "Forever: the switch still writes enabled")

flush()
check(#GuildOS.State.errors == 0, "no click or relayout recorded an error: "
  .. tostring(GuildOS.State.errors[1] and GuildOS.State.errors[1].msg))

print(("recruiting-layout: %d checks passed"):format(checks))
