-- The Officers' Room's and Settings' kit (UI/Kit.lua, specs/salao/fase3.md), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Core/Style.lua, UI/Helpers.lua and UI/Kit.lua: a card's text
-- reads in the paper's inks, a class in its colour on the paper, a floating window has the mockup's .fw chrome
-- (header, title, round close, footer laid from the right), GuildOS's own dialog is dressed as a parchment card,
-- and the screens and popups that should wear them do.
--
--   luajit -e 'ADDON="."' tools/officer-kit.lua
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

local function frame(parent)
  local f = { shown = true, scripts = {}, parent = parent, points = {} }
  function f:Show() self.shown = true end
  function f:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  function f:SetShown(on) if on then self:Show() else self:Hide() end end
  function f:IsShown() return self.shown end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:HookScript(name, fn) local p = self.scripts[name]; self.scripts[name] = p and function(...) p(...); fn(...) end or fn end
  function f:GetParent() return self.parent end
  function f:SetText(t) self.text_ = t end
  function f:GetText() return self.text_ end
  function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function f:ClearAllPoints() self.points = {} end
  function f:GetStringHeight() return 20 end
  function f:GetStringWidth() return 10 end
  function f:GetWidth() return 100 end
  function f:GetFrameLevel() return 1 end
  function f:SetHeight(h) self.height = h end
  function f:IsEnabled() return true end
  function f:IsMovable() return self.movable end
  function f:SetMovable(v) self.movable = v end
  function f:SetVertexColor(r, g, b) self.color = { r, g, b } end
  function f:SetTextColor(r, g, b) self.color = { r, g, b } end
  function f:CreateFontString() return frame(self) end
  function f:CreateTexture() return frame(self) end
  function f:GetRegions() return end
  return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") and k ~= "GetEditBox" then return function() end end end })
end
UIParent = frame()
function CreateFrame(_, _, parent) return frame(parent) end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70888", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
function GetTime() return 1 end
function UnitFullName() return "Lead", "" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
CANCEL = "Cancel"
C_PlayerInfo = { ShouldDisplaySurname = function() return false end }
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
UISpecialFrames, SlashCmdList = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

GuildOSDB = {}
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
GuildOS.db = { settings = {} }
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Kit.lua")
local Kit, C, UI = GuildOS.Kit, GuildOS.Colors, GuildOS.UI

-- ── The paper's inks ───────────────────────────────────────────────────
local P = Kit.PAPER
check(P.text == C.paperInk and P.silver == C.paperSoft and P.textSoft == C.paperSoft, "a card's text is the paper's ink")
check(P.ok == Kit.INK.ok and P.red == Kit.INK.bad and P.warn == Kit.INK.warn, "its statuses are the paper's, not the wood's light ones")
check(P.lineHi == C.lineHi and P.crimson == C.crimson, "anything else is the shared colour")
check(P.row1.a == 0 and P.row2.a == 0, "no zebra on the paper: a row is ruled instead")
local r, g, b = Kit:ClassInk("PRIEST")
check(r < 0.5 and g < 0.5 and b < 0.5, "a priest's white is dark on the paper")
r = Kit:ClassInk("nope")
check(r == C.paperInk.r, "an unknown class is the paper's ink")

-- ── The floating window ─────────────────────────────────────────────────
local f = Kit:Float("Recruitment", { name = "GuildOSKitTest", foot = true, sub = "Guild OS" })
check(f.header and f.titleText and f.titleText:GetText() == "Recruitment" and f.subText:GetText() == "Guild OS",
  "a header with the title and what it is about")
check(f.body and f.foot and f.closeBtn, "a body, a footer and the round close")
local esc = false
for _, n in ipairs(UISpecialFrames) do if n == "GuildOSKitTest" then esc = true end end
check(esc, "Escape closes a named window")
f:Show()
f.closeBtn.scripts.OnClick()
check(not f:IsShown(), "the close hides it")
local a, bb = frame(f.foot), frame(f.foot)
f.foot:Lay(a, bb)
check(a.points[1][1] == "RIGHT" and a.points[1][2] == f.foot and bb.points[1][2] == a, "the footer lays its answers from the right, the first rightmost")
f:SetTitle("Warn", "Nyx")
check(f.titleText:GetText() == "Warn" and f.subText:GetText() == "Nyx", "the title changes with SetTitle")

-- ── The dialog as a parchment card ──────────────────────────────────────
GuildOS.Dialogs.KIT = { text = "Remove %s?", button1 = "Remove", button2 = "Cancel" }
local d = GuildOS:ShowDialog("KIT", "Nyx")
check(d and d.__paper and d.button1.variant == "primary" and d.button1.__onPaper and d.button2.__onPaper,
  "GuildOS's dialog is a parchment card: the answer crimson, the others the paper's quiet buttons")
check(d.text:GetText() == "Remove Nyx?", "and still says what it asks")

-- ── The screens and windows wear them ───────────────────────────────────
local function read(p) return assert(io.open(ADDON .. "/" .. p, "rb")):read("*a") end
check(read("GuildOS.toc"):find("UI\\Helpers.lua\r?\nUI\\Kit.lua"), "the kit loads right after the shared helpers")
for _, p in ipairs({ "UI/ManagementPanel.lua", "UI/RosterFrame.lua", "UI/AlliancePanel.lua", "UI/SettingsPanel.lua" }) do
  check(read(p):find("UI:CreateCard(", 1, true), p .. " draws its screens on parchment cards")
end
for _, p in ipairs({ "Modules/RecruitmentSystem.lua", "UI/WarnDialog.lua", "UI/Onboarding.lua", "Modules/Digest.lua",
  "Modules/LootMaster.lua", "UI/JoinRequests.lua", "UI/WebPanel.lua", "UI/ModAlerts.lua", "UI/ManagementPanel.lua" }) do
  check(read(p):find("Kit:Dress(", 1, true), p .. " opens its window with the floating window's chrome")
end
-- No section or card title in upper case on these screens (the mockup's titles are never).
for _, p in ipairs({ "UI/ManagementPanel.lua", "UI/BulkPanel.lua", "UI/RemindPanel.lua", "UI/MarksPanel.lua",
  "UI/ModAlerts.lua", "UI/SettingsPanel.lua", "UI/AlliancePanel.lua" }) do
  for line in read(p):gmatch("[^\n]+") do
    local t = line:match('[sS]ectionTitle%(%w+, L%["([^"]+)"%]') or line:match('CreateCard%(%w+, L%["([^"]+)"%]')
    if t then check(t ~= t:upper(), p .. ": " .. t .. " is not in upper case") end
  end
end

print(("officer-kit: %d checks passed"):format(checks))
