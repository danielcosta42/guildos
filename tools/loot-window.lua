-- The Loot window and its dropdown (issue #346), the real UI files on the real modules under a stubbed
-- client, in both interface styles (the flat "guildos" one and "forever"):
--   * the dropdown: a button that shows the value chosen, a list under it that a click opens, a click
--     on a row chooses, a click outside or Escape closes, and a long list scrolls;
--
--   luajit -e 'ADDON="."' tools/loot-window.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local STYLE = "guildos"
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL (" .. STYLE .. "): " .. tostring(what) .. "\n")
    os.exit(1)
  end
end

-- ── A frame that keeps what the screens read back, and takes anything else ──
local Frame = {}
local VERBS = { "Set", "Get", "Is", "Clear", "Enable", "Register", "Unregister", "Raise", "Lower", "Start", "Stop", "Add" }
local allFrames
local function newFrame(kind, parent, name)
  local f = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, shown = true, w = 0, h = 0,
                           enabled = true, alpha = 1, name = name, points = {} }, { __index = function(_, k)
    if Frame[k] then return Frame[k] end
    if type(k) ~= "string" then return nil end
    for _, verb in ipairs(VERBS) do
      if k:find("^" .. verb) then return function() end end
    end
    return nil
  end })
  if parent and parent.children then parent.children[#parent.children + 1] = f end
  allFrames[#allFrames + 1] = f
  if name then _G[name] = f end
  return f
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:GetParent() return self.parent end
function Frame:GetName() return self.name end
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
  local was = self.shown
  self.shown = true
  if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
  local was = self.shown
  self.shown = false
  if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:CreateTexture() return newFrame("Texture", self) end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetText(t) self.text = t; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end end
function Frame:GetText() return self.text or "" end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetFont() return true end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:Enable() self.enabled = true; if self.scripts.OnEnable then self.scripts.OnEnable(self) end end
function Frame:Disable() self.enabled = false; if self.scripts.OnDisable then self.scripts.OnDisable(self) end end
function Frame:SetEnabled(v) if v then self:Enable() else self:Disable() end end
function Frame:IsEnabled() return self.enabled end
function Frame:IsMouseOver() return false end
function Frame:SetChecked(v) self.checked = v and true or nil end
function Frame:GetChecked() return self.checked end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetScrollChild(c) self.scrollChild = c end
function Frame:SetBackdropBorderColor(r, g, b) self.border = { r, g, b } end
function Frame:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:SetVerticalScroll(v) self.vscroll = v end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetRegions()
  local out = {}
  for _, c in ipairs(self.children) do
    if c.kind == "FontString" or c.kind == "Texture" then out[#out + 1] = c end
  end
  return unpack(out)
end

-- Every visible button with this label under `root`, or every one anywhere.
local function walk(f, visit)
  visit(f)
  for _, c in ipairs(f.children) do walk(c, visit) end
end
local function buttons(root, label)
  local out = {}
  walk(root, function(f)
    if f.kind == "Button" and f:IsVisible() and f.label and f.label.text == label then out[#out + 1] = f end
  end)
  return out
end
local function click(root, label, nth)
  local b = buttons(root, label)[nth or 1]
  check(b ~= nil and b.scripts.OnClick ~= nil, "there is a button \"" .. label .. "\" to click")
  b.scripts.OnClick(b)
  return b
end
local function texts(root)
  local out = {}
  walk(root, function(f)
    if f.kind == "FontString" and f:IsVisible() and f.text and f.text ~= "" then out[#out + 1] = f.text end
  end)
  return table.concat(out, "\n")
end
local function shows(root, text) return texts(root):find(text, 1, true) ~= nil end

-- ── The client ──────────────────────────────────────────────────────────
local function load(style)
  allFrames = {}
  STYLE = style
  UIParent = newFrame("Frame")
  UIParent:SetSize(1920, 1080)
  function CreateFrame(kind, name, parent) return newFrame(kind, parent, name) end
  GameTooltip = newFrame("GameTooltip")
  UISpecialFrames = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 1 } }
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  function hooksecurefunc() end
  function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  function GetLocale() return "enUS" end
  function GetRealmName() return "Realm" end
  function UnitName(unit) if unit == "player" then return "Lead" end end
  function UnitClass() return "Mage", "MAGE" end
  function GetServerTime() return 1791000000 end
  function GetTime() return 100 end
  time, date = os.time, os.date
  function strtrim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
  format, strlower = string.format, string.lower
  function wipe(t) for k in pairs(t) do t[k] = nil end return t end
  function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
  C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  function UIFrameFadeIn() end
  function IsInGuild() return true end
  function IsInRaid() return false end
  function GetNumGroupMembers() return 0 end
  function GetNumGuildMembers() return 0 end
  function SendChatMessage() end
  GuildOSDB = {}
  C_Texture = nil
  if style == "forever" then
    local atlases = {}
    for line in io.lines(ADDON .. "/tools/data/forever-atlas-elements.txt") do
      if not line:find("^#") then atlases[(line:gsub(" %*$", "")):lower()] = true end
    end
    C_Texture = { GetAtlasInfo = function(n) return atlases[tostring(n):lower()] and { width = 32, height = 32 } or nil end }
    GuildOSDB.style = "forever"
  end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Style.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.Style:Resolve()
  dofile(ADDON .. "/UI/Helpers.lua")
  dofile(ADDON .. "/UI/Layout.lua")
  GuildOS.Print = function() end
  GuildOS.SafeCall = function(_, fn, ...) return fn(...) end   -- an error in a paint fails the test, loudly
  check(GuildOS.Style.current == style, "the " .. style .. " style is the one in force")
  return GuildOS.UI
end

-- ── 1. The dropdown ─────────────────────────────────────────────────────
local function dropdown(UI)
  local parent = newFrame("Frame", UIParent)
  local dd = UI:CreateDropdown(parent, 160, 22)
  check(dd.kind == "Button" and dd.label and dd.w >= 160, "a dropdown is a button of the width asked")
  local picked = {}
  dd.onSelect = function(_, v) picked[#picked + 1] = v end
  dd:SetPlaceholder("Pick one")
  check(dd.label.text == "Pick one", "with nothing chosen it says so")
  dd:SetOptions({ { value = "near", text = "Nearest" }, { value = "up", text = "Up" }, { value = "down", text = "Down" } })
  dd:SetValue("up")
  check(dd.label.text == "Up" and dd:GetValue() == "up" and #picked == 0, "SetValue shows the value and tells nobody")
  check(UI:DropdownOpenFor() == nil, "the list is closed until a click")

  dd.scripts.OnClick(dd)
  local list = _G.GuildOSDropdownList
  check(list and list:IsShown() and UI:DropdownOpenFor() == dd, "a click opens the shared list, for this dropdown")
  check(list.strata == "FULLSCREEN_DIALOG", "the list is a popup over the window")
  local anchored = list.points[1]
  check(anchored and anchored[1] == "TOPLEFT" and anchored[2] == dd and anchored[3] == "BOTTOMLEFT", "anchored under its button")
  check(tContains(UISpecialFrames, "GuildOSDropdownList"), "Escape closes it, as every window of the addon")
  local rows = {}
  for _, r in ipairs(list.rows) do if r:IsShown() then rows[#rows + 1] = r end end
  check(#rows == 3 and rows[1].label.text == "Nearest" and rows[2].label.text == "Up" and rows[3].label.text == "Down",
    "one row an option, in their order")
  check(rows[2].mark:IsShown() and not rows[1].mark:IsShown(), "the value chosen is marked")
  check(list.h == 3 * 20 + 4, "the list is as tall as its rows")
  rows[3].scripts.OnClick(rows[3])
  check(dd:GetValue() == "down" and dd.label.text == "Down" and picked[1] == "down", "a click on a row chooses it and says so")
  check(not list:IsShown() and not list.catcher:IsShown() and UI:DropdownOpenFor() == nil, "and closes the list")

  dd.scripts.OnClick(dd)
  check(list:IsShown() and list.catcher:IsShown(), "open again, a sheet catches the clicks outside it")
  list.catcher.scripts.OnClick(list.catcher)
  check(not list:IsShown() and #picked == 1, "a click outside closes it and chooses nothing")
  dd.scripts.OnClick(dd)
  dd.scripts.OnClick(dd)
  check(not list:IsShown(), "a second click on the button closes it")
  dd.scripts.OnClick(dd)
  list:Hide()   -- what Escape does to a frame of UISpecialFrames
  check(not list.catcher:IsShown() and UI:DropdownOpenFor() == nil, "Escape closes it whole")
  dd.scripts.OnClick(dd)
  parent:Hide()
  dd.scripts.OnHide(dd)
  check(not list:IsShown(), "and so does the button going away with its window")
  parent:Show()

  -- A long list scrolls, and a second dropdown reuses the list.
  local many = UI:CreateDropdown(parent, 120, 22)
  local opts = {}
  for i = 1, 25 do opts[i] = { value = i, text = "Option " .. i } end
  many:SetOptions(opts)
  many:SetValue(7)
  many.scripts.OnClick(many)
  check(UI:DropdownOpenFor() == many and list.h == 10 * 20 + 4, "past ten rows the list keeps ten rows tall")
  check(list.scroll.scrollChild == list.child and list.child.h == 25 * 20, "and scrolls the rest")
  local shown = 0
  for _, r in ipairs(list.rows) do if r:IsShown() then shown = shown + 1 end end
  check(shown == 25, "every option has its row")
  list.rows[7].scripts.OnClick(list.rows[7])
  check(many:GetValue() == 7 and dd:GetValue() == "down", "a choice is the owner's, not the other dropdown's")
  dd.scripts.OnClick(dd)
  shown = 0
  for _, r in ipairs(list.rows) do if r:IsShown() then shown = shown + 1 end end
  check(shown == 3, "the rows a shorter list does not need are hidden")
  dd:Close()
  check(not list:IsShown(), "Close closes it from code")

  -- A value with a colour of its own (an item quality) keeps it on the button.
  local q = UI:CreateDropdown(parent, 120, 22)
  q:SetOptions({ { value = 4, text = "Epic", color = { r = 0.64, g = 0.21, b = 0.93 } } })
  q:Select(4)
  check(q.label.color and math.abs(q.label.color[1] - 0.64) < 1e-6, "a coloured option paints the button's label")
  -- A disabled option cannot be chosen.
  q:SetOptions({ { value = 1, text = "One" }, { value = 2, text = "Two", disabled = true } })
  q.scripts.OnClick(q)
  check(not list.rows[2]:IsEnabled() and list.rows[1]:IsEnabled(), "a disabled option's row cannot be clicked")
  q:Close()

  -- The Save button that says whether the box holds what was saved.
  local box = newFrame("EditBox", parent)
  box:SetText("30")
  local saved = 0
  local btn = UI:AttachSaveButton(box, function() saved = saved + 1 end, { state = true })
  check(btn.label.text == "Saved" and not btn:IsEnabled(), "a box with nothing typed reads Saved")
  box.text = "45"
  box.scripts.OnTextChanged(box, true)
  check(btn.label.text == "Save" and btn:IsEnabled(), "typing turns it back into Save")
  btn.scripts.OnClick(btn)
  check(saved == 1 and btn.label.text == "Saved" and not btn:IsEnabled(), "and saving says so")
end

for _, style in ipairs({ "guildos", "forever" }) do
  local UI = load(style)
  dropdown(UI)
end

print(("loot-window: %d checks passed"):format(checks))
