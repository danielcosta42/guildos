-- Settings in six sub-tabs (issue #367), the real UI/SettingsPanel.lua on the real core under a stubbed
-- client:
--   * the six pages in their order, an old category name still landing on its page, and an unknown one
--     on the first;
--   * a page built once: switching sub-tabs and re-laying it out at another width create no frame;
--   * the module lists in one column, or two from a 900px window;
--   * the reload strip: lit by a change that needs a reload, out again when the change is undone;
--   * a sub-option greyed out with its parent;
--   * Guild rules read by a member, changed by an officer;
--   * every setting the old panel had is on a page, and what moved out of Settings is gone from it.
--
--   luajit -e 'ADDON="."' tools/settings-panel.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
STYLE = STYLE or "guildos"

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. tostring(what) .. "\n")
    os.exit(1)
  end
end

-- ── A frame that keeps what the pages read back, and takes anything else ──
local Frame = {}
local VERBS = { "Set", "Get", "Is", "Clear", "Enable", "Register", "Unregister", "Raise", "Lower", "Start", "Stop", "Add" }
local allFrames = {}
local function newFrame(kind, parent, name)
  local f = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, shown = true, w = 0, h = 0,
                           enabled = true, name = name, points = {} }, { __index = function(_, k)
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
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:CreateTexture() return newFrame("Texture", self) end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text or "" end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetFont() return true end
function Frame:GetFrameLevel() return 1 end
function Frame:Enable() self.enabled = true; if self.scripts.OnEnable then self.scripts.OnEnable(self) end end
function Frame:Disable() self.enabled = false; if self.scripts.OnDisable then self.scripts.OnDisable(self) end end
function Frame:IsEnabled() return self.enabled end
function Frame:IsMouseOver() return false end
function Frame:HasFocus() return false end
function Frame:SetChecked(v) self.checked = v and true or nil end
function Frame:GetChecked() return self.checked end
function Frame:SetScrollChild(c) self.scrollChild = c end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:GetChildren()
  local out = {}
  for _, c in ipairs(self.children) do
    if c.kind ~= "FontString" and c.kind ~= "Texture" then out[#out + 1] = c end
  end
  return unpack(out)
end
function Frame:GetRegions()
  local out = {}
  for _, c in ipairs(self.children) do
    if c.kind == "FontString" or c.kind == "Texture" then out[#out + 1] = c end
  end
  return unpack(out)
end

local function walk(f, visit)
  visit(f)
  for _, c in ipairs(f.children) do walk(c, visit) end
end
-- The visible checkbox (its frame, from UI:CreateCheckbox) or button with this label under `root`.
local function find(root, kind, label)
  local hit
  walk(root, function(f)
    if hit or not f:IsVisible() then return end
    if kind == "check" and f.checkbox and f.label and f.label.text == label then hit = f end
    if kind == "button" and f.kind == "Button" and f.label and f.label.text == label then hit = f end
  end)
  return hit
end
local function shows(root, text)
  local seen = false
  walk(root, function(f)
    if f.kind == "FontString" and f:IsVisible() and f.text and f.text:find(text, 1, true) then seen = true end
  end)
  return seen
end

-- ── The client ──────────────────────────────────────────────────────────
UIParent = newFrame("Frame")
UIParent:SetSize(1920, 1080)
function CreateFrame(kind, name, parent) return newFrame(kind, parent, name) end
GameTooltip = newFrame("GameTooltip")
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
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
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
function UIFrameFadeIn() end
function IsInGuild() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function GetNumGuildMembers() return 0 end
local RANKS = { "Guild Master", "Officer", "Veteran", "Member" }
function GuildControlGetNumRanks() return #RANKS end
function GuildControlGetRankName(i) return RANKS[i] end
GuildOSDB = {}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
dofile(ADDON .. "/Core/Utils.lua")
-- tools/settings-panel-forever.lua runs this whole harness again under the Forever style, with the
-- client's atlases: its tabs, checkboxes and primary button wear the game's art.
if STYLE == "forever" then
  local atlases = {}
  for line in io.lines(ADDON .. "/tools/data/forever-atlas-elements.txt") do
    if not line:find("^#") then atlases[(line:gsub(" %*$", "")):lower()] = true end
  end
  C_Texture = { GetAtlasInfo = function(n) return atlases[tostring(n):lower()] and { width = 32, height = 32 } or nil end }
  GuildOSDB.style = "forever"
end
GuildOS.Style:Resolve()
dofile(ADDON .. "/UI/StylePreview.lua")
dofile(ADDON .. "/UI/Spacing.lua")
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Features.lua")
dofile(ADDON .. "/UI/SettingsPanel.lua")
-- The help hub's page (specs/salao/onboarding.md) and what it reads.
dofile(ADDON .. "/Modules/Onboarding.lua")
dofile(ADDON .. "/UI/Tour.lua")
dofile(ADDON .. "/UI/Onboarding.lua")
dofile(ADDON .. "/UI/HelpPanel.lua")
local UI = GuildOS.UI
check(GuildOS.Style.current == "salao", "the Salão's one look on the " .. STYLE .. " client")

local printed = {}
GuildOS.Print = function(_, msg) printed[#printed + 1] = tostring(msg) end
GuildOS.SafeCall = function(_, fn, ...) return fn(...) end   -- an error in a page fails the test, loudly
local officer = true
GuildOS.IsOfficer = function() return officer end
GuildOS.CreateRolePicker = function(_, parent) return newFrame("Frame", parent) end
GuildOS.IsMinimapShown = function() return true end
GuildOS.Mentions = { PrintLog = function() end, HandleCommand = function() end,
                     _AddWatchWord = function(_, list, w) list[#list + 1] = w; return "ok" end,
                     _RemoveWatchWord = function() end }
UI.ApplyScale = function() end
GuildOS.RaidTracker = { GetPenalties = function() return { LATE = 2, LEFT_EARLY = 2 } end, SetGroupTag = function() end,
                        RebuildAttendanceFromSessions = function() end }
GuildOS.CoreManager = { SetPenalty = function() end }
GuildOS.db = { settings = { modules = {}, officerMaxRank = 1, officerMaxRankAt = 900 }, profile = {},
  chatTweaks = { enabled = true }, mentions = { enabled = true, watchWords = {} }, lfgPrefs = { notify = false } }

-- ── 1. Six pages, in their order; old names land on their page ──────────
local parent = newFrame("Frame", UIParent)
parent:SetSize(960, 560)
GuildOS:CreateSettingsPanel(parent)
local labels = {}
walk(parent, function(f)
  if f.kind == "Button" and f.underline and f.label then labels[#labels + 1] = f.label.text end
end)
check(table.concat(labels, "|") == "Profile|Interface|Chat and alerts|Modules|Guild rules|Data and support|Credits|Help",
  "eight sub-tabs, in order (" .. table.concat(labels, "|") .. ")")
parent.SelectSub("profile")
local profileTab
walk(parent, function(f) if f.kind == "Button" and f.underline and f.label and f.label.text == "Profile" then profileTab = f end end)
-- One look on every client (#449): the open sub-tab is the soft gold pill, on Forever too.
check(profileTab.isActive and profileTab.fill and profileTab.fill.shown and not profileTab.underline.shown,
  "the open sub-tab is a soft gold pill, no rule, on every client")
for old, page in pairs({ about = "data", officer = "rules", raid = "rules", general = "profile", loot = "profile",
                         nonsense = "profile" }) do
  parent.SelectSub(old)
  check(parent.activeSub == page, "\"" .. old .. "\" opens " .. page)
end
check(UI:GetFeature("settings") and UI:GetFeature("settings").core, "Settings itself has no switch")

-- ── 2. Built once: switching and resizing create nothing ────────────────
local PAGES = { "profile", "interface", "chat", "modules", "rules", "data", "help", "credits" }
for _, p in ipairs(PAGES) do parent.SelectSub(p) end   -- every page built
local frames = #allFrames
for _ = 1, 3 do
  for _, p in ipairs(PAGES) do parent.SelectSub(p) end
end
check(#allFrames == frames, "switching sub-tabs builds nothing new (" .. (#allFrames - frames) .. " frames)")
for _, w in ipairs({ 360, 600, 900, 1200 }) do
  for _, p in ipairs(PAGES) do parent.subPanels[p].form:Layout(w) end
end
check(#allFrames == frames, "laying the pages out at four widths builds nothing new")
for _, p in ipairs(PAGES) do
  local info = parent.subPanels[p]
  check(info.scroll:IsShown() == (p == "credits"), p .. " is shown only while its sub-tab is open")
  check(info.content.h > 0, p .. " has a height for its scroll frame")
end

-- ── 2b. Every part of a page lies inside its card (#449) ────────────────
-- In the game the module lists were laid out by the window's width while their card had a fixed one: the right
-- column, its descriptions and "reload" badges sat on the wood. Now a card is its column's width and lays its
-- rows in its own: every row (and every cell of a row's grid) ends inside the card, at a 1250px and an 800px
-- window (about 1200px and 750px of page), and two cards never overlap.
for _, pageW in ipairs({ 1200, 750 }) do
  for _, p in ipairs(PAGES) do
    local form = parent.subPanels[p].form
    form:Layout(pageW)
    check(form.placed and #form.placed > 0, p .. " lays rows in cards at " .. pageW)
    for _, pl in ipairs(form.placed) do
      local ow = pl.row.w or 0
      check(pl.x + math.min(ow, pl.w) <= pl.cardW - 14 + 0.5 and pl.w <= pl.cardW - 28 + 0.5,
        ("%s at %d: a row ends inside its card (x %d + %d of %d)"):format(p, pageW, pl.x, ow, pl.cardW))
      for _, c in ipairs(pl.row.children or {}) do
        local pt = c.points and c.points[1]
        if c.shown and pt and pt[1] == "TOPLEFT" and pt[2] == pl.row and type(pt[4]) == "number" and (c.w or 0) > 0 then
          check(pt[4] + c.w <= pl.w + 0.5, ("%s at %d: a cell (%d + %d) ends inside its row of %d"):format(p, pageW, pt[4], c.w, pl.w))
        end
      end
    end
    -- The cards themselves: inside the page, side by side or one under the other, never over each other.
    local boxes = {}
    for _, c in ipairs(parent.subPanels[p].content.children) do
      local pt = c.points and c.points[1]
      if c.shown and c.__paper and pt and pt[2] == parent.subPanels[p].content then
        boxes[#boxes + 1] = { x = pt[4], y = -pt[5], w = c.w, h = c.h }
        check(pt[4] >= 0 and pt[4] + c.w <= pageW + 0.5, ("%s at %d: a card inside the page"):format(p, pageW))
      end
    end
    for i = 1, #boxes do for j = i + 1, #boxes do
      local a2, b2 = boxes[i], boxes[j]
      local apart = a2.x + a2.w <= b2.x or b2.x + b2.w <= a2.x or a2.y + a2.h <= b2.y or b2.y + b2.h <= a2.y
      check(apart, ("%s at %d: two cards do not overlap"):format(p, pageW))
    end end
    if pageW >= 900 and #boxes >= 2 and p ~= "modules" then
      local xs = {}
      for _, bx in ipairs(boxes) do xs[bx.x] = true end
      local n = 0
      for _ in pairs(xs) do n = n + 1 end
      check(n == 2, p .. " lays its cards in two columns on a wide page")
    end
  end
end

-- ── 3. Module lists: one column, two from a 900px window ────────────────
parent.SelectSub("modules")
local mods = parent.subPanels.modules
local function cellXs(width)
  mods.form:Layout(width)
  local xs = {}
  walk(mods.content, function(f)
    if f.checkbox and f.parent and f.parent.parent and f.parent.parent.parent == mods.content and f:IsVisible() then
      local p = f.parent.points[1]
      xs[#xs + 1] = p and p[4] or 0
    end
  end)
  return xs
end
local wide, narrow = cellXs(900), cellXs(500)
local function anyRight(xs) for _, x in ipairs(xs) do if x > 0 then return true end end return false end
check(#wide > 4 and anyRight(wide), "at 900px the modules sit in two columns")
check(#narrow == #wide and not anyRight(narrow), "at 500px in one")
local comm = find(mods.content, "check", "Comm System")
check(comm and shows(mods.content, "Sync member data between addon users"), "a module says what it does")
check(find(mods.content, "check", "Loot") and shows(mods.content, "The loot rule, accounts, lists and history"),
  "a tab says what it holds")

-- ── 4. The reload strip ─────────────────────────────────────────────────
local strip
walk(parent, function(f) if f.text and f.text.kind == "FontString" and f.kind == "Frame" and f.parent == parent then strip = f end end)
check(strip and not strip:IsShown(), "nothing waits for a reload at first")
comm.checkbox.checked = not comm.checkbox.checked
comm.checkbox.onChanged(comm.checkbox, comm.checkbox.checked)
check(strip:IsShown() and strip.text.text == "1 change applies after you reload the interface.",
  "switching a background module lights the strip")
local reload = find(strip, "button", "Reload")
check(reload and reload.variant == "primary", "with one Reload button, the primary one")
check(reload.__arts and reload.__arts.button and reload.__arts.button.shown,
  "the crimson button of the Salão's art on every client, no game atlas")
comm.checkbox.checked = not comm.checkbox.checked
comm.checkbox.onChanged(comm.checkbox, comm.checkbox.checked)
check(not strip:IsShown(), "switching it back puts the strip out")
local groups = find(mods.content, "check", "Groups")
groups.checkbox.onChanged(groups.checkbox, false)
check(not strip:IsShown() and not GuildOS:IsFeatureEnabled("groups"), "a tab switches live, with no reload")
groups.checkbox.onChanged(groups.checkbox, true)
parent.SelectSub("interface")
local interface = parent.subPanels.interface.content
-- One look since the Salão (#445): no style picker. The game's font is a choice again (Discord 1556991354478010459):
-- saved at the account root as GuildOSDB.gameFont, applied after a reload (the strip lights), undone by unticking.
check(not find(interface, "button", "Apply"), "no style picker, on any client")
local gameFont = find(interface, "check", "Use the game's font")
check(gameFont and not gameFont.checkbox.checked and shows(interface, "Applies after you reload the interface"),
  "Interface has \"Use the game's font\", off by default, saying it needs a reload")
GuildOSDB = GuildOSDB or {}
gameFont.checkbox.onChanged(gameFont.checkbox, true)
check(GuildOSDB.gameFont == true and strip:IsShown(), "ticked: saved for the account and the reload strip lit")
check(GuildOS:FontFace(GuildOS.Fonts.ui) == GuildOS.Fonts.ui, "the font in use changes only after the reload")
gameFont.checkbox.onChanged(gameFont.checkbox, false)
check(GuildOSDB.gameFont == nil and not strip:IsShown(), "unticked: nothing saved, nothing waits for a reload")

-- ── 5. A sub-option greys out with its parent ───────────────────────────
parent.SelectSub("chat")
local chat = parent.subPanels.chat.content
local annotate = find(chat, "check", "Annotate guild chat (class icon, level, alt tag)")
check(find(chat, "check", "Class icon").checkbox:IsEnabled(), "with the chat annotated, its parts can be chosen")
annotate.checkbox.onChanged(annotate.checkbox, false)
check(GuildOS.db.chatTweaks.enabled == false and not find(chat, "check", "Class icon").checkbox:IsEnabled()
  and not find(chat, "check", "Short tag: [M] on a main, [Main] on an alt").checkbox:IsEnabled(),
  "turned off, every part greys out")
check(find(chat, "check", "Officer chat"), "an officer is offered officer chat")

-- ── 6. Guild rules: an officer changes them, a member reads them ────────
parent.SelectSub("rules")
local rules = parent.subPanels.rules.content
check(find(rules, "check", "Officer") and find(rules, "check", "Veteran"), "an officer has a box per rank")
check(not find(rules, "check", "Guild Master").checkbox:IsEnabled(), "the guild master is always an officer")
check(find(rules, "button", "Officers"), "and the button that says who creates events")
officer = false
parent.SelectSub("rules")
check(not find(rules, "check", "Officer") and shows(rules, "Guild Master, Officer"),
  "a member reads who the officers are")
check(shows(rules, "Only officers change these."), "and is told why it cannot change them")
check(not find(rules, "button", "Officers") and shows(rules, "Who creates events:"), "reads who creates events")
parent.SelectSub("chat")
check(not find(parent.subPanels.chat.content, "check", "Officer chat"), "a member is not offered officer chat")
parent.SelectSub("data")
check(not find(parent.subPanels.data.content, "button", "Test Raid Status"), "nor the test functions")
officer = true

-- A rank renamed is a new page: the new name shows. And on a narrow page every box keeps its Save.
RANKS[3] = "Elder"
parent.SelectSub("rules")
check(find(rules, "check", "Elder") and not find(rules, "check", "Veteran"), "a rank renamed shows its new name")
parent.subPanels.rules.form:Layout(380)
local boxes, fits = 0, true
walk(rules, function(f)
  if f.kind == "EditBox" and f:IsVisible() then
    boxes = boxes + 1
    local p = f.points[1]
    if (p and p[4] or 0) + f.w + 6 + 60 > 380 then fits = false end
  end
end)
check(boxes >= 3 and fits, "at 380px every box and its Save button fit the page (" .. boxes .. " boxes)")
parent.subPanels.rules.form:Layout(900)
RANKS[3] = "Veteran"

-- A sub-tab goes with its host (issue #367): Trials is nowhere while Recruitment is off.
GuildOS:SetFeatureEnabled("recruitment", false)
check(not UI:IsFeatureAllowed(UI:GetFeature("trials")), "with Recruitment off, Trials is not offered either")
GuildOS:SetFeatureEnabled("recruitment", true)
check(UI:IsFeatureAllowed(UI:GetFeature("trials")), "and it comes back with Recruitment")

-- ── 7. Every setting is on a page; what moved out is gone ───────────────
local everything = newFrame("Frame", UIParent)
for _, p in ipairs(PAGES) do
  local content = newFrame("Frame", everything)
  content:SetSize(900, 1)
  GuildOS:RefreshSettingsPanel(content, p)
end
for _, label in ipairs({ "Show minimap button", "Guild button opens Guild OS", "Guild info on item tooltips",
  "Only while holding Shift", "Show login digest",
  "Annotate guild chat (class icon, level, alt tag)", "Class icon", "Level", "Alt tag",
  "Short tag: [M] on a main, [Main] on an alt", "Alert me when my name or a watch-word comes up in chat",
  "My own name", "Guild chat", "Officer chat", "When somebody calls the officers in guild chat (officers only)",
  "Play a sound", "Tell me when a guildmate posts on the LFG board", "Debug logging",
  "Apply !note requests from guild chat on this client" }) do
  check(find(everything, "check", label), "Settings still has \"" .. label .. "\"")
end
for _, label in ipairs({ "Show tips again", "Show the digest now", "Recent mentions", "Clear watch-words",
  "Backup", "Restore", "Export Data", "Collect my data", "View Errors", "Self-test", "Probe the client", "Probe chat",
  "Style preview", "Links", "Erase guild data", "Test Raid Status", "Test Attendance Export" }) do
  check(find(everything, "button", label), "Settings still has the \"" .. label .. "\" button")
end
check(shows(everything, "UI scale") and shows(everything, "Watch-words:"), "and the scale and the watch-words")
-- Credits: who made it, the links each with Copy, the licence, what it is built with, this copy's details.
do
  local credits = newFrame("Frame", UIParent)
  credits:SetSize(900, 1)
  GuildOS:RefreshSettingsPanel(credits, "credits")
  for _, t in ipairs({ "Guild OS", "Chehul", "Made by", "Community and links", "Thanks", "License", "Built with", "This copy",
    "https://discord.gg/8XA6gmNjja", "https://guildos.me", "MIT" }) do
    check(shows(credits, t), "Credits shows \"" .. t .. "\"")
  end
  local copies = 0
  walk(credits, function(f) if f.kind == "Button" and f.label and f.label.text == "Copy" then copies = copies + 1 end end)
  check(copies == 8, "each link, and each of the family's addons, has its Copy (" .. copies .. ")")
  check(not shows(credits, "ProfessionHelper"), "ProfessionHelper stays out until it runs on Forever")
  check(shows(credits, "https://www.curseforge.com/wow/addons/lodestar"), "the family links go to CurseForge")
  for _, t in ipairs({ "The Chehul family", "Lodestar", "PartyLens", "Warmth" }) do
    check(shows(credits, t), "Credits shows \"" .. t .. "\"")
  end
  for _, label in ipairs({ "Read the license", "Copy for a bug report", "Join the Discord" }) do
    check(find(credits, "button", label), "Credits has the \"" .. label .. "\" button")
  end
  local narrow = newFrame("Frame", UIParent)
  narrow:SetSize(380, 1)
  local F = GuildOS:RefreshSettingsPanel(narrow, "credits")
  F:Layout(380)
  local inside = true
  for _, pl in ipairs(F.placed or {}) do if pl.x + pl.w > pl.cardW + 1 then inside = false end end
  check(inside, "at 380px every row stays inside its card")
end
local errorsButtons = 0
walk(everything, function(f)
  if f.kind == "Button" and f.label and f.label.text == "View Errors" then errorsButtons = errorsButtons + 1 end
end)
check(errorsButtons == 1, "View Errors is there once")
check(not shows(everything, "QUICK ACCESS") and not shows(everything, "AUTO-INVITE"), "the quick access and auto-invite sections left")
for _, gone in ipairs({ "Loot & DKP", "My Wishlist", "Loot Council", "Loot Equity", "Bulletin", "Polls",
  "Search", "Login Digest", "Open Loot", "Open in Recruitment", "Reload UI" }) do
  check(not find(everything, "button", gone), "the \"" .. gone .. "\" button left Settings")
end
local danger = find(everything, "button", "Erase guild data")
check(danger.variant == "danger", "erasing is the danger button")

io.write(string.format("settings-panel: %d checks passed\n", checks))
