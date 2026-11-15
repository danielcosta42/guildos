-- The Loot window and its dropdown (issue #346), the real UI files on the real modules under a stubbed
-- client, in both interface styles (the flat "guildos" one and "forever"):
--   * the dropdown: a button that shows the value chosen, a list under it that a click opens, a click
--     on a row chooses, a click outside or Escape closes, and a long list scrolls;
--   * the Loot window: an officer edits the rule (the model, its settings, the answers) and the accounts
--     (the award row, the points' settings) of the guild or of a core; a member reads the rule as
--     players will read it and the standings, and edits nothing;
--   * no loot setting is reachable from two places: Settings > Loot and the core's Config tab only
--     point to the window, and the code that writes each setting is in one UI file;
--   * the master looter's table: the boss's items with where each stands, the candidates in the rule's
--     order with why each is there, the decision in a sentence that follows that order, an Award
--     button whose label says who (the relabel that never showed), End now, Disenchant, Cancel, the
--     night's awards and Undo; every way in (the loot window, a roll announced, a bag click);
--   * the raider's popup: the item and what it is, what the player wears there, where they stand in
--     the rule (reserve, lists, counters, points and what entering costs), the rule's buttons and the
--     line that names the rule;
--   * Raids › Cores: the list with size, fill and origin, the header with origin and the raid's mark,
--     the sub-tabs, the role meters, the role as a dropdown, the guests of the night, the Discord's
--     notes, the format and the penalties that say when they are saved, the columns that drop;
--   * the core sign-up: one card a core with where the player stands always in sight (Cancel request
--     shown with no hover), when it raids and who leads it, its loot rule in one line;
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
-- Only the ones shown: a screen hides what it drew before, and what is hidden needs nothing more.
function Frame:GetChildren()
  local out = {}
  for _, c in ipairs(self.children) do
    if c.shown and c.kind ~= "FontString" and c.kind ~= "Texture" then out[#out + 1] = c end
  end
  return unpack(out)
end
function Frame:GetRegions()
  local out = {}
  for _, c in ipairs(self.children) do
    if c.shown and (c.kind == "FontString" or c.kind == "Texture") then out[#out + 1] = c end
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


-- ── 2. The Loot window ──────────────────────────────────────────────────
local officer = true
local function loadModules()
  dofile(ADDON .. "/Modules/CoreManager.lua")
  dofile(ADDON .. "/Modules/Points.lua")
  dofile(ADDON .. "/Modules/LootRule.lua")
  dofile(ADDON .. "/Modules/LootMaster.lua")
  GuildOS.db = { settings = { lootSystem = "rolls", modules = {} }, members = {}, altLinks = {}, cores = {},
    lootHistory = {}, lootMaster = { awardHistory = {} }, points = {},
    raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
  GuildOS.IsOfficer = function() return officer end
  GuildOS.IsOfficerByName = function() return officer end
  GuildOS.Points:Initialize()
  GuildOS.LootMaster:LoadCfg()
  GuildOS.Wishlist = { GetItemInterest = function() return nil end }   -- what the Lists tab and the popup read
  GuildOS.LootMasterStatus = function() return "Master Loot: Lead" end   -- Core/Commands.lua's
  dofile(ADDON .. "/UI/FeaturePanels.lua")
  dofile(ADDON .. "/UI/LootWindow.lua")
  dofile(ADDON .. "/UI/PointsPanel.lua")
  dofile(ADDON .. "/UI/CorePanel.lua")
  GuildOS.CreateRolePicker = function(_, parent) return newFrame("Frame", parent) end
  UI_OPENED = nil
  GuildOS.UI.OpenWindow = function(_, id, sub, filter) UI_OPENED = { id, sub, filter } return true end
end

-- Lay the scroll children out as the client would: the stub has no layout engine.
local function sized(root, w)
  walk(root, function(f)
    if f.kind == "ScrollFrame" then f:SetSize(w, 400) end
    if f.scrollChild then f.scrollChild:SetWidth(w - 12) end
  end)
end

local function lootWindow(width)
  local box = newFrame("Frame", UIParent)
  box:SetSize(width or 680, 470)
  GuildOS:CreateLootWindow(box)
  sized(box, (width or 680) - 40)
  return box
end

-- The frames of `root` that carry `field` (a setting's key, a dropdown's role), visible ones only.
local function tagged(root, field, value)
  local out = {}
  walk(root, function(f)
    if f:IsVisible() and f[field] ~= nil and (value == nil or f[field] == value) then out[#out + 1] = f end
  end)
  return out
end
local function typeAndSave(box, text)
  box.text = text
  box.scripts.OnTextChanged(box, true)
  box.saveButton.scripts.OnClick(box.saveButton)
end

local function lootTab(UI)
  loadModules()
  local LM, LR, CM, P = GuildOS.LootMaster, GuildOS.LootRule, GuildOS.CoreManager, GuildOS.Points

  -- The officer's Rule tab, on the guild.
  local win = lootWindow()
  check(type(win.SelectSub) == "function" and win.ActiveSub() == "rule", "the tab opens on Rule, and takes a deep link")
  local rule = win.panels.rule
  rule.Draw("")
  check(#buttons(rule, "MS > OS +1") == 1 and #buttons(rule, "DKP / Points") == 1 and #buttons(rule, "Add answer") == 1,
    "an officer sees the models as a list and the answers' editor")
  check(#tagged(rule, "isScope") == 1, "and a selector: the guild or a core")
  check(shows(rule, "Who may ask.") and shows(rule, "Who takes it.") and shows(rule, "The higher roll"),
    "and the rule as players will read it, in the rule's order")
  local wl = tagged(rule, "lootKey", "wishlistOnlyMode")
  check(#wl == 1, "the wishlist-only switch is here, once")
  wl[1].onChanged(wl[1], true)
  check(GuildOS.db.lootMaster.wishlistOnlyMode == true and LM.WISHLIST_ONLY_MODE == true, "and writes the key it always did")
  local thr = tagged(rule, "lootKey", "lootThreshold")[1]
  check(thr and thr.options and #thr.options == 4, "the loot threshold is a dropdown of the four qualities")
  thr:Select(4)
  check(GuildOS.db.lootMaster.lootThreshold == 4 and LM:GetLootThreshold() == 4, "a choice saves it")
  local dur = tagged(rule, "lootKey", "rollDuration")[1]
  check(dur and dur.saveButton.label.text == "Saved", "the roll duration's box shows it is saved")
  typeAndSave(dur, "45")
  check(GuildOS.db.lootMaster.rollDuration == 45 and LM.ROLL_DURATION == 45, "a typed duration is saved")
  typeAndSave(dur, "500")
  check(GuildOS.db.lootMaster.rollDuration == 45 and dur.text == "45", "one out of bounds is refused, and the box says what holds")
  click(rule, "MS > OS +1")
  check(GuildOS:GetLootSystem("") == "plus1", "a model is a click")
  rule.Draw("")
  check(shows(rule, "The answer: MS > OS") and shows(rule, "Who holds less +1"), "and what players read follows it")

  -- A core's rule: Follow the guild, its own model, and the way to its accounts.
  check(CM:Create("Alpha"), "a core")
  local scope = tagged(rule, "isScope")[1]
  scope:Select("Alpha")
  check(#buttons(rule, "Follow the guild") == 1, "a core offers to follow the guild: " .. #buttons(rule, "Follow the guild"))
  check(shows(rule, "Following the guild"), "a core follows the guild until it picks: " .. texts(rule):sub(1, 300))
  click(rule, "DKP / Points")
  check(CM:GetLootSystem("Alpha") == "dkp" and GuildOS:GetLootSystem("") == "plus1", "its pick is its own")
  check(#buttons(rule, "Open Accounts") == 1, "a model on points says its settings are in Accounts")
  click(rule, "Open Accounts")
  check(win.ActiveSub() == "accounts" and win.panels.accounts.Scope() == "Alpha", "and opens them, on that core")

  -- The officer's Accounts: the award row, on the core picked.
  local acc = win.panels.accounts
  sized(acc, 640)
  acc.Refresh()
  local who
  walk(acc, function(f) if f.kind == "EditBox" and f:IsVisible() and not who then who = f end end)
  local reason = tagged(acc, "isReason")[1]
  check(who and reason and #buttons(acc, "Award") == 1 and #buttons(acc, "Charge") == 1, "who, a reason, Award and Charge")
  check(reason.options[#reason.options].text == "Other (type it)", "the reason is a named one, or typed")
  who.text = "Ana"
  local amount
  walk(acc, function(f) if f.kind == "EditBox" and f:IsVisible() and f ~= who and not amount then amount = f end end)
  amount.text = "10"
  click(acc, "Award")
  check(P:InCore("Alpha", P.Get, P, P:KeyOf("Ana")) == 10 and P:Get(P:KeyOf("Ana")) ~= 10, "an award lands in the core's pool")
  amount.text = "3"
  click(acc, "Charge")
  check(P:InCore("Alpha", P.Get, P, P:KeyOf("Ana")) == 7, "and a charge too")
  check(shows(acc, "Ana") and shows(acc, "7"), "the standings show it")
  P:InCore("Alpha", P.SetReason, P, "don", "Donation", 5, 2)
  acc.Refresh()
  check(reason.options[1].text == "Donation: 5 points, up to 2 a week", "a named reason is offered with its points and its cap")
  reason:Select("don")
  who.text, amount.text = "Bo", "3"
  click(acc, "Award")
  check(P:InCore("Alpha", P.Get, P, P:KeyOf("Bo")) == 2, "given three times, held to its cap of two a week")
  click(acc, "Account settings")
  local boss = tagged(acc, "pointsKey", "bossAward")[1]
  check(boss and #buttons(acc, "Back to the standings") == 1, "the points' settings are behind one button")
  typeAndSave(boss, "15")
  check(P:GetDBForCore("Alpha").config.bossAward == 15 and P:GetDBForCore("").config.bossAward ~= 15, "and save on the core's pool")
  local mode = tagged(acc, "isMode")[1]
  check(mode and #mode.options == 2, "the mode is a dropdown: DKP or a council")
  mode:Select("council")
  check(P:GetMode("Alpha") == "council", "and a choice changes it")
  click(acc, "Back to the standings")

  -- Settings > Loot and the core's Config tab only point here.
  local settings = newFrame("Frame", UIParent)
  settings:SetSize(560, 900)
  GuildOS:RefreshSettingsPanel(settings, "loot")
  check(#buttons(settings, "Open Loot") == 1, "Settings > Loot says where the loot settings are")
  local LOOT_CONTROLS = { "Wishlist Auto-Council", "Roll Duration", "Rarity threshold", "Disenchanter", "Bank character",
    "Points per boss", "Min. Attendance", "Auto-announce", "LOOT SYSTEM", "LOOT MASTER", "Wishlist-only mode",
    "Roll duration", "Loot threshold", "Mode:" }
  for _, label in ipairs(LOOT_CONTROLS) do
    check(not shows(settings, label), "Settings has no \"" .. label .. "\" left")
  end
  click(settings, "Open Loot")
  check(UI_OPENED[1] == "loot" and UI_OPENED[2] == "rule" and UI_OPENED[3] == "", "its button opens the Rule tab on the guild")

  local cores = newFrame("Frame", UIParent)
  cores:SetSize(780, 540)
  GuildOS:CreateCoresPanel(cores)
  sized(cores, 540)
  cores.scripts.OnShow(cores)
  local alphaRow
  walk(cores, function(f) if f.coreName == "Alpha" and f.scripts.OnClick and f:IsVisible() then alphaRow = alphaRow or f end end)
  check(alphaRow, "the core is listed")
  alphaRow.scripts.OnClick(alphaRow)
  click(cores, "Config")
  for _, label in ipairs(LOOT_CONTROLS) do
    check(not shows(cores, label), "the core's Config tab has no \"" .. label .. "\" left")
  end
  check(#buttons(cores, "Open Loot") == 0, "nor the way to the Loot window: its Rule tab has that")
  click(cores, "Rule")
  check(#buttons(cores, "Open Loot") == 1 and shows(cores, "Loot: DKP (fixed price)"), "the core's Rule tab says what the core plays")
  for _, label in ipairs(LOOT_CONTROLS) do
    check(not shows(cores, label), "and edits none of it: no \"" .. label .. "\"")
  end
  click(cores, "Open Loot")
  check(UI_OPENED[3] == "Alpha", "and its button opens the Loot window's Rule tab on that core")

  -- Each loot setting is written from one UI file.
  local function read(path)
    local f = assert(io.open(ADDON .. "/" .. path, "rb"))
    local src = f:read("*a")
    f:close()
    return src
  end
  local WRITES = {
    { "SetLootSetting(", "UI/LootWindow.lua" }, { "SetLootSystem(", "UI/LootWindow.lua" },
    { "SetConfigKey(", "UI/PointsPanel.lua" }, { "Points:SetMode(", "UI/PointsPanel.lua" },
    { "P:SetMode(", "UI/PointsPanel.lua" }, { "wishlistOnlyMode", "UI/LootWindow.lua" },
  }
  local uiFiles = {}
  for line in io.popen('ls "' .. ADDON .. '/UI"'):lines() do uiFiles[#uiFiles + 1] = "UI/" .. line end
  for _, w in ipairs(WRITES) do
    for _, path in ipairs(uiFiles) do
      if path ~= w[2] then
        check(not read(path):find(w[1], 1, true), w[1] .. " is written from " .. w[2] .. " alone, not " .. path)
      end
    end
  end
  for _, path in ipairs(uiFiles) do
    check(not read(path):find("SaveCfgKey(", 1, true) and not read(path):find("SetLootConfigKey(", 1, true),
      path .. " writes no loot setting behind the Loot window's back")
  end

  -- What players read, from the rule's own blocks.
  local d = LR:Describe({ v = 1, model = "custom", time = 25,
    responses = { { key = "MS", label = "Main", ask = "roll", cost = 1 }, { key = "OS", label = "Off", ask = "roll", cost = 0 } },
    filters = { { k = "attendance", min = 50, act = "downgrade", from = "MS", to = "OS" }, { k = "points", min = 4, act = "block" } },
    order = { { k = "softres" }, { k = "response" }, { k = "roll" } },
    exceptions = { { on = { cat = "recipe" }, to = "bank" } } })
  check(d.who == "Everyone in the raid. With attendance below 50%, Main counts as Off. Whoever holds fewer than 4 points may not ask.",
    "who may ask, filter by filter: " .. d.who)
  check(d.how == "Main, Off, pass, within 25 seconds.", "how to ask, with the rule's own time: " .. d.how)
  check(d.order[1] == "Who reserved the item" and d.order[2] == "The answer: Main > Off" and d.order[3] == "The higher roll",
    "who takes it, in the order")
  check(d.exceptions == "recipes: the guild bank.", "and what goes elsewhere: " .. tostring(d.exceptions))
  check(select(2, LM:SetLootSetting("colour", 1, "")) == "key" and select(2, LM:SetLootSetting("lootThreshold", 9, "")) == "range",
    "a setting that is none, or a threshold that is no quality, is refused")
  check(LM:SetLootSetting("minAttendancePct", 140, "") == 100 and LM:SetLootSetting("bank", "  Vault ", "Alpha") == "Vault"
    and CM:GetLootConfig("Alpha").bank == "Vault" and CM:GetLootConfig("").bank ~= "Vault", "and the others are held to their bounds, on their core")
  check(select(2, P:AwardRow({ name = "" })) == "name" and select(2, P:AwardRow({ name = "Ana" })) == "amount"
    and select(2, P:AwardRow({ name = "Ana", reason = "nope" })) == "reason", "the award row needs who, and points or a reason")
  check(P:SetConfigKey("decayPct", 250, "") == 100 and P:SetConfigKey("decayRound", "sideways", "") == nil
    and P:SetConfigKey("autoAward", 1, "") == true and P:SetConfigKey("nonsense", 1, "") == nil, "the points' settings are held to theirs")

  -- A member reads, and edits nothing.
  officer = false
  local mine = lootWindow()
  local r2 = mine.panels.rule
  r2.Draw("")
  check(#buttons(r2, "MS > OS +1") == 0 and #buttons(r2, "Add answer") == 0 and #tagged(r2, "lootKey") == 0,
    "a member sees no model to pick, no editor and no setting")
  check(shows(r2, "Model: MS > OS +1") and shows(r2, "Who may ask.") and shows(r2, "Who takes it."),
    "but reads the model and the rule as players will read it")
  check(#tagged(r2, "isScope") == 1, "of the guild or of any core")
  mine.SelectSub("accounts", "Alpha")
  local a2 = mine.panels.accounts
  sized(a2, 640)
  a2.Refresh()
  check(#buttons(a2, "Award") == 0 and #buttons(a2, "Charge") == 0 and #buttons(a2, "Account settings") == 0,
    "nor the award row, nor the points' settings")
  check(shows(a2, "Ana") and shows(a2, "Bo"), "and reads the standings of the core")
  mine.SelectSub("lists")
  check(shows(mine.panels.lists, "Your wishlist is yours to keep"), "the lists say where their own wishlist is")
  mine.SelectSub("history")
  check(mine.ActiveSub() == "history", "and the history opens")
  officer = true
end

-- ── 3. The master looter's table ───────────────────────────────────────
local LINK1 = "|cffa335ee|Hitem:28770::::::::70:::::|h[Crown of the Abyssal Wind]|h|r"
local LINK2 = "|cffa335ee|Hitem:30627::::::::70:::::|h[Ring of the Oath]|h|r"
local LINK3 = "|cffa335ee|Hitem:30628::::::::70:::::|h[Shard of the Bond]|h|r"
local function lootTable()
  loadModules()
  local LM, LR = GuildOS.LootMaster, GuildOS.LootRule
  local said = {}
  LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
  LM.SafeSendChatAuto = LM.SafeSendChat
  LM.SafeSendAddon = function() end
  LM.SendEcho = function() end
  LM.IsMasterLooter = function() return true end
  LM.GetPlayerContext = function() return { att25 = 90, recvThisLockout = 0 } end
  function GetInstanceInfo() return "Karazhan", "raid", 9, "", 10, 0, false, 532 end
  function IsInRaid() return true end
  function GetItemInfo(link)
    local name = tostring(link):match("%[(.-)%]")
    return name, link, 4, 70, 70, "Armor", "Cloth", 1, "INVTYPE_HEAD", 133000, 0, 4, 1, 1
  end
  -- The rule of the table's sentence: the reserve first, then the answer, then the roll.
  check(LR:Set({ v = 1, model = "custom", order = { { k = "softres" }, { k = "response" }, { k = "roll" } } }) == true,
    "a rule that orders by the reserve, the answer and the roll")

  LM:ShowLootFrame({ { slot = 1, link = LINK1, name = "Crown of the Abyssal Wind", quality = 4 },
                     { slot = 2, link = LINK2, name = "Ring of the Oath", quality = 4 } })
  local f = _G.GuildOSLootTable
  check(f and f:IsShown() and LM.lootFrame == f and LM.rollFrame == f, "the loot window and the roll tracker are one table")
  f:SetSize(1000, 480)
  LM:RefreshRollFrame()
  check(f.itemRows[1]:IsShown() and f.itemRows[2]:IsShown() and f.itemRows[1].stateKey == "queued", "the boss's items, each with its state")
  check(f.selected and f.selected.link == LINK1, "the first is picked")
  check(f.openBtn:IsShown() and f.openBtn:IsEnabled() and not f.endBtn:IsShown(), "before its roll: Open roll")
  check(not f.awardBtn:IsEnabled() and f.awardBtn.label.text == "Award", "and no one to award yet")
  check(shows(f, "Nobody has it on a list: open a roll."), "the decision says what to do")
  -- No setting lives in the table any more: the wishlist council and the disenchanter are the Rule tab's.
  check(not shows(f, "Wishlist Council") and #buttons(f, ">") == 0, "no wishlist-council box and no disenchanter picker")
  local src = assert(io.open(ADDON .. "/Modules/LootMaster.lua", "rb")):read("*a")
  check(not src:find('SaveCfgKey("wishlistOnlyMode"', 1, true), "nothing in the loot master writes the wishlist-only switch any more")

  -- A roll: the candidates in the rule's order, and why.
  click(f, "Open Roll")
  check(LM.activeLoot and LM.activeLoot.link == LINK1 and f.itemRows[1].stateKey == "rolling", "Open roll announces the item")
  check(f.endBtn:IsShown() and f.endBtn:IsEnabled() and not f.openBtn:IsShown(), "and End now takes its place")
  local function K(n) return GuildOS:GetPlayerKey(n) end
  LM.rolls[K("Kawa")] = { name = "Kawa", class = "MAGE", rollType = "MS", roll = 93 }
  LM.rolls[K("Rias")] = { name = "Rias", class = "MAGE", rollType = "MS", roll = 17, softRes = { hard = false } }
  LM.rolls[K("Chehul")] = { name = "Chehul", class = "MAGE", rollType = "MS", roll = 41, softRes = { hard = false } }
  LM.rolls[K("Dean")] = { name = "Dean", class = "MAGE", rollType = "PASS", roll = 0 }
  LM:RefreshRollFrame()
  local order = {}
  for i = 1, 4 do order[i] = f.rows[i].cells.name.text end
  check(table.concat(order, ",") == "Chehul,Rias,Kawa,Dean", "the candidates in the rule's order, a pass last: " .. table.concat(order, ","))
  check(f.rows[1].cells.why.text == "reserved" and f.rows[3].cells.why.text == "", "why each is there: the reserve the rule compares")
  check(f.rows[4].cells.answer.text == "Passed", "a pass says so")
  local sentence = f.decision.text
  check(sentence == "Chehul leads: both reserved the item (Rias too), and their roll 41 beats Rias's 17.",
    "the decision in a sentence, in the rule's order: " .. tostring(sentence))
  check(not f.awardBtn:IsEnabled(), "Award waits for the answers to close")
  click(f, "End now")
  check(LM.activeLoot.ended and f.decision.text:find("^Chehul wins: both reserved the item"), "End now closes it: " .. f.decision.text)
  check(f.awardBtn:IsEnabled() and f.awardBtn.label.text == "Award to Chehul",
    "and the Award button says who, on the label the player sees: " .. tostring(f.awardBtn.label.text))
  -- The rule's order changes, and so do the sentence and the button.
  check(LR:Set({ v = 1, model = "custom", order = { { k = "response" }, { k = "roll" } } }) == true, "a rule that reads only the roll")
  LM.activeLoot.rule = LR:Active()
  LM:RefreshRollFrame()
  check(f.rows[1].cells.name.text == "Kawa" and f.decision.text == "Kawa wins: their roll 93 beats Chehul's 41.",
    "the sentence follows the order: " .. f.decision.text)
  -- The master looter picks someone else.
  f.rows[2].scripts.OnClick(f.rows[2])
  check(f.awardBtn.label.text == "Award to Chehul" and f.decision.text:find("You picked Chehul instead.", 1, true), "a click on a row picks them")
  f.rows[4].scripts.OnClick(f.rows[4])
  check(f.awardBtn.label.text == "Award to Chehul", "a pass cannot be picked")
  click(f, "Award to Chehul")
  check(LM.activeLoot == nil and said[#said]:find("delivered to Chehul", 1, true), "Award gives it: " .. tostring(said[#said]))
  check(f.itemRows[1].stateKey == "awarded" and f.itemRows[1].state.text == "to Chehul", "the item says who got it")
  check(shows(f, "Crown of the Abyssal Wind \226\134\146 Chehul"), "and the night's awards list it")
  check(f.undoBtn:IsEnabled(), "which Undo can take back")
  click(f, "Undo last award")
  check(f.itemRows[1].stateKey == "queued" and not shows(f, "\226\134\146 Chehul"), "Undo takes it back")

  -- Disenchant and Cancel.
  f.itemRows[2].scripts.OnClick(f.itemRows[2])
  check(f.selected.link == LINK2 and f.deBtn:IsEnabled() and not f.cancelBtn:IsEnabled(), "another item: Disenchant, nothing to cancel")
  GuildOS.LootMaster:SetLootSetting("disenchanter", "Dis", "")
  click(f, "Disenchant")
  check(said[#said]:find("delivered to Disenchant (Dis)", 1, true), "Disenchant sends it to the disenchanter: " .. tostring(said[#said]))
  click(f, "Open Roll")
  check(f.cancelBtn:IsEnabled(), "a roll can be cancelled")
  click(f, "Cancel")
  check(LM.activeLoot == nil and f.openBtn:IsShown(), "and Cancel cancels it")

  -- The answer for someone: a dropdown of the rule's answers.
  check(f.forAnswer.options[1].value == "MS" and f.forAnswer.options[2].value == "OS", "the answer for someone is the rule's answers")

  -- A narrow table drops columns by priority; a wide one shows them all.
  f:SetSize(600, 360)
  LM:RefreshRollFrame()
  local L1 = f.layout.byKey
  check(L1.name.shown and L1.answer.shown and L1.roll.shown and not L1.rank.shown and not L1.att.shown, "at 600px the rank and the attendance go first")
  f:SetSize(1100, 480)
  LM:RefreshRollFrame()
  check(f.layout.byKey.att.shown and f.layout.byKey.rank.shown and f.layout.byKey.why.shown, "and come back with room")

  -- A roll announced from a bag: its item joins the list and is picked.
  LM:SetActiveLoot(LINK3, nil, 30628)
  LM:ShowRollFrame()
  check(f.selected.link == LINK3 and #LM.lootItems == 3, "a roll from a bag adds its item to the table")
  LM:CancelRolling()
  f:Hide()
  LR:Set(nil)
end

-- ── 4. The raider's popup ──────────────────────────────────────────────
local function popup()
  loadModules()
  local LM, P = GuildOS.LootMaster, GuildOS.Points
  local sent = {}
  LM.SendAnswer = function(_, key, bid, note) sent[#sent + 1] = { key = key, bid = bid, note = note } end
  INVTYPE_HEAD = "Head"
  function GetItemInfo(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    local name = tostring(link):match("%[(.-)%]")
    return name, link, 4, id == 99999 and 66 or 76, 70, "Armor", "Cloth", 1, "INVTYPE_HEAD", 133000
  end
  local WORN = "|cff0070dd|Hitem:99999::::::::70:::::|h[Arcanist Cowl]|h|r"
  function GetInventoryItemLink(unit, slot) if unit == "player" and slot == 1 then return WORN end end
  GuildOS.SoftRes = { GetReserves = function() return { { name = "Lead" } } end }
  GuildOS.Wishlist = { GetItemInterest = function() return { { name = "Lead", order = 2, type = "wishlist" } } end }
  GuildOS:SetLootSystem("plus1")
  local ask = { responses = { { key = "MS", label = "Main spec", ask = "roll" }, { key = "OS", label = "Off spec", ask = "roll" },
    { key = "TMOG", label = "Transmog", ask = "roll" } }, bids = false }
  LM:ShowRollPopup(LINK1, 30, 28770, ask)
  local f = LM.rollPopup
  check(f and f:IsShown() and f.w == 380, "the popup opens")
  check(shows(f, "Crown of the Abyssal Wind") and shows(f, "Head \194\183 Cloth \194\183 item level 76"), "with the item and what it is")
  check(shows(f, "YOU WEAR") and shows(f, "Arcanist Cowl") and f.diffText.text == "+10 item level", "what the player wears there, and the gain")
  check(f.standing[1] == "Reserved the item" and f.standing[2] == "Wishlist #2" and f.standing[3] == "+1 tonight: 0",
    "where they stand: the reserve, the wishlist place, the counter: " .. table.concat(f.standing, ", "))
  check(#buttons(f, "Main spec") == 1 and #buttons(f, "Off spec") == 1 and #buttons(f, "Transmog") == 1 and #buttons(f, "Pass") == 1,
    "the rule's buttons, and Pass")
  check(f.ruleText.text == "Rule of the guild: MS > OS +1. The roll is drawn by the master looter's addon and shows here.",
    "and the line that names the rule: " .. tostring(f.ruleText.text))
  check(f.clock.text == "0:30", "the clock counts what is left")
  click(f, "Off spec")
  check(sent[1] and sent[1].key == "OS" and not f:IsShown(), "an answer is sent and the popup closes")

  -- On points: the balance and what entering costs.
  GuildOS:SetLootSystem("dkp")
  P:SetConfigKey("entryCost", 4, "")
  P:SetConfigKey("refundPct", 50, "")
  P:Adjust(P:KeyOf("Lead"), 18, "start", "award")
  GuildOS.SoftRes, GuildOS.Wishlist = nil, nil
  function GetInventoryItemLink() return nil end
  LM:ShowRollPopup(LINK1, 30, 28770, ask)
  f = LM.rollPopup
  check(f.pointsText and f.pointsText.text == "Points: 18. Entering this roll costs 4; whoever loses gets 2 back.",
    "the balance and the price of entering: " .. tostring(f.pointsText and f.pointsText.text))
  check(f.standing[1] == "Not on your lists" and not shows(f, "YOU WEAR"), "nothing worn or listed: it says so, and no empty block")
  -- A loot master from before: MS, OS and Pass by /roll.
  local rolled
  function RandomRoll(a, b) rolled = a .. "-" .. b end
  LM:ShowRollPopup(LINK1, 30, 28770, nil)
  f = LM.rollPopup
  check(#buttons(f, "MS") == 1 and #buttons(f, "OS") == 1 and #buttons(f, "Pass") == 1, "a loot master from before: MS, OS, Pass")
  check(f.ruleText.text:find("/roll", 1, true), "and the line says they are /roll")
  click(f, "OS")
  check(rolled == "1-99", "OS is /roll 1-99")
end

-- ── 5. Raids › Cores ───────────────────────────────────────────────────
local function cores()
  loadModules()
  local CM = GuildOS.CoreManager
  function GetGuildRosterInfo(i)
    local roster = { { "Pug-Realm", "PRIEST", true }, { "Bea-Realm", "MAGE", false } }
    local m = roster[i]
    if m then return m[1], "Raider", 2, 70, "Priest", "Zone", "", "", m[3], 0, m[2] end
  end
  function GetNumGuildMembers() return 2 end
  GuildOS.KeyOfRosterName = function(_, full) return full end
  -- A linked guild: one core of the Discord, one only in this game from before the link.
  check(CM:Create("Bravo"), "a core of this game")
  CM:Create("Alfa")
  GuildOS.db.cores.Alfa.discordTag = "alfa"
  GuildOS.db.cores.Alfa.raidSize = 10
  GuildOS.db.cores.Alfa.discordWaiting = { "Dean_Ales" }
  local K = function(n) return n .. "-Realm" end
  CM:AddMember(K("Chehul"), { name = "Chehul", class = "PRIEST", role = "healer", src = "discord" }, "Alfa")
  CM:AddMember(K("Kawa"), { name = "Kawa", class = "WARRIOR", role = "tank", src = "discord" }, "Alfa")
  GuildOS.db.coreLink = { since = GetServerTime() - 7200, seenAt = GetServerTime() - 7200 }
  CM:AddGuest(K("Xablau"), { name = "Xablau", class = "MAGE", role = "rdps" }, "Alfa", true)

  local panel = newFrame("Frame", UIParent)
  panel:SetSize(780, 540)
  GuildOS:CreateCoresPanel(panel)
  sized(panel, 520)
  panel.scripts.OnShow(panel)
  local rows = {}
  walk(panel, function(f) if f.coreName and f:IsVisible() then rows[f.coreName] = f end end)
  check(rows.Alfa and rows.Bravo, "the guild's cores are listed")
  check(rows.Alfa.sub.text == "10 \194\183 2 of 10 \194\183 from Discord", "with size, fill and origin: " .. rows.Alfa.sub.text)
  check(rows.Bravo.sub.text:find("only in this game", 1, true), "and a core only this game has says so")
  check(shows(panel, "New cores are born on Discord") and shows(panel, "Received from the site"), "a linked guild is told where cores are born")
  rows.Alfa.scripts.OnClick(rows.Alfa)
  check(shows(panel, "Alfa") and shows(panel, "from Discord") and #buttons(panel, "Rename") == 0,
    "the header says the origin, and a Discord core is not renamed here")
  check(#buttons(panel, "Roster") == 1 and #buttons(panel, "Requests") == 1 and #buttons(panel, "Rule") == 1 and #buttons(panel, "Config") == 1,
    "sub-tabs Roster, Requests, Rule, Config")
  check(shows(panel, "Tanks") and shows(panel, "Healers") and shows(panel, "1 of "), "the role meters")
  local roleDD
  walk(panel, function(f) if f:IsVisible() and f.memberKey == K("Kawa") then roleDD = f end end)
  check(roleDD and #roleDD.options == 4 and roleDD:GetValue() == "tank", "each member's role is a dropdown of the four")
  roleDD:Select("mdps")
  check(GuildOS.db.cores.Alfa.members[K("Kawa")].role == "mdps", "and a choice changes it, through CoreManager")
  check(shows(panel, "Guests of the night (1)") and shows(panel, "Xablau"), "the guests of the night")
  check(shows(panel, "Dean_Ales") and shows(panel, "waiting for a character"), "who the Discord has with no character")
  check(shows(panel, "Who joins and leaves the core is decided on Discord"), "and what is the Discord's to decide")
  check(#buttons(panel, "Remove") == 1, "a Discord member is not removed here; a guest is")
  local picker
  walk(panel, function(f) if f:IsVisible() and f.isMemberPicker then picker = f end end)
  check(picker and #picker.options == 2, "the guild's people to invite, in a dropdown")
  picker:Select("Pug-Realm")
  click(panel, "Invite")
  check(GuildOS.db.cores.Alfa.guests["Pug-Realm"] and GuildOS.db.cores.Alfa.guests["Pug-Realm"].role == "healer",
    "invited as a guest, in their class's role")
  -- The columns drop by priority at a narrow width.
  sized(panel, 320)
  panel.scripts.OnSizeChanged(panel)
  rows.Alfa.scripts.OnClick(rows.Alfa)
  local layout = panel.memberLayout
  check(layout.byKey.name.shown and layout.byKey.role.shown and not layout.byKey.origin.shown, "narrow: the origin goes first, the member and the role stay")
  sized(panel, 520)
  rows.Alfa.scripts.OnClick(rows.Alfa)
  -- A core of this game: its format and its penalties.
  walk(panel, function(f) if f.coreName and f:IsVisible() then rows[f.coreName] = f end end)
  rows.Bravo.scripts.OnClick(rows.Bravo)
  click(panel, "Config")
  check(#buttons(panel, "10-man") == 1 and #buttons(panel, "25-man") == 1, "TBC's two formats are two buttons")
  click(panel, "10-man")
  check(CM:GetRaidSize("Bravo") == 10, "and a click is the format")
  local late
  walk(panel, function(f) if f:IsVisible() and f.penaltyKey == "LATE" then late = f end end)
  check(late and late.saveButton.label.text == "Saved", "a penalty's box says it is saved")
  late.text = "20"
  late.scripts.OnTextChanged(late, true)
  check(late.saveButton.label.text == "Save", "typing says it is not, yet")
  late.saveButton.scripts.OnClick(late.saveButton)
  check(CM:GetPenalties("Bravo").LATE == 20 and late.saveButton.label.text == "Saved", "and saving does")
  click(panel, "Requests")
  check(shows(panel, "Pending Sign-ups (0)"), "the requests")
end

-- ── 6. The core sign-up ────────────────────────────────────────────────
local function signup()
  loadModules()
  local CM = GuildOS.CoreManager
  local sent
  CM.BroadcastSignup = function(_, core, note, role) sent = { core = core, note = note, role = role } end
  local me = GuildOS:GetPlayerKey("Lead", "Realm")
  CM:Create("Alfa"); CM:Create("Bravo"); CM:Create("Sat")
  CM:AddMember(me, { name = "Lead", class = "MAGE", role = "rdps" }, "Alfa")
  GuildOS.db.cores.Alfa.schedule, GuildOS.db.cores.Alfa.leader = "Wed and Sun, 21h", "Chehul"
  GuildOS.db.cores.Bravo.signups = { [me] = { name = "Lead", class = "MAGE", role = "rdps", ts = GetServerTime() - 3 * 3600 } }
  GuildOS:ShowCoreSignupFrame()
  local f = _G.GuildOSCoreSignupFrame
  check(f and f:IsShown(), "the sign-up window opens")
  f.content:SetWidth(430)
  GuildOS:ShowCoreSignupFrame()   -- a second call closes it
  check(not f:IsShown(), "and the same call closes it")
  GuildOS:ShowCoreSignupFrame()
  check(f.states.Alfa == "you are a starter" and f.states.Bravo:find("^request sent ") and f.states.Sat:find("^missing "),
    "each card says where the player stands: " .. tostring(f.states.Bravo) .. " / " .. tostring(f.states.Sat))
  check(shows(f, "Wed and Sun, 21h") and shows(f, "leader Chehul") and shows(f, "no leader set"), "when it raids and who leads it")
  check(shows(f, "Loot: Rolls (MS > OS)"), "the core's loot rule in one line")
  local cancel = buttons(f, "Cancel request")
  check(#cancel == 1 and cancel[1]:IsVisible() and cancel[1].variant == "danger", "Cancel request is in sight, with no hover to find it")
  check(not shows(f, "Pending"), "and nothing says Pending in English")
  local src = assert(io.open(ADDON .. "/UI/FeaturePanels.lua", "rb")):read("*a")
  check(not src:find('"Pending "', 1, true), "the untranslated Pending is gone from the code")
  cancel[1].scripts.OnClick(cancel[1])
  check(not GuildOS.db.cores.Bravo.signups[me], "Cancel takes the request back")
  click(f, "Ask for a place")
  check(sent and sent.core == "Bravo", "Ask for a place asks, on its own core")
  click(f, "See the rule", 3)
  check(UI_OPENED and UI_OPENED[1] == "loot" and UI_OPENED[3] == "Sat", "See the rule opens the core's rule in the Loot window")
  f:Hide()
end

for _, style in ipairs({ "guildos", "forever" }) do
  local UI = load(style)
  dropdown(UI)
  lootTab(UI)
  lootTable()
  popup()
  cores()
  signup()
end

print(("loot-window: %d checks passed"):format(checks))
