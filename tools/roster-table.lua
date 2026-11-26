-- The member list's columns on the real table (issue #178, spec
-- docs/superpowers/specs/2026-10-18-roster-columns-design.md), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Data.lua, Core/Style.lua, Core/Utils.lua, UI/Helpers.lua, UI/Layout.lua,
-- Modules/RosterColumns.lua, Modules/GearAudit.lua and UI/RosterFrame.lua under a stub frame API.
-- tools/roster-columns.lua tests the stored choice on its own.
--
-- The default table is the one there always was. The Columns panel and a right click on the header
-- turn a column on, off and move it; the table follows at once and every column sorts, an empty
-- cell last. A column the reader may not see is not offered, and a narrow window drops the
-- rightmost first.
--
--   luajit -e 'ADDON="."' tools/roster-table.lua
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

function Frame:SetSize(w, h) self.w, self.h = w, h; fire(self, "OnSizeChanged", w, h) end
function Frame:SetWidth(w) self.w = w; fire(self, "OnSizeChanged", self.w, self.h) end
function Frame:SetHeight(h) self.h = h; fire(self, "OnSizeChanged", self.w, self.h) end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:SetChecked(v) self.checked = v and true or nil end
function Frame:GetChecked() return self.checked end
function Frame:SetEnabled(v) self.disabled = not v end
function Frame:IsEnabled() return not self.disabled end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints(other) self.points = { { "ALL", other } } end
function Frame:GetParent() return self.parent end
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
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
-- Kept, so the rows' fills and the selection's gold edge can be read (#377).
function Frame:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
function Frame:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function Frame:SetFocus() self.focused = true end
for _, name in ipairs({ "SetClampedToScreen", "RegisterForClicks", "SetBackdrop",
  "SetBackdropBorderColor", "SetTexture", "SetTexCoord", "SetBlendMode", "SetAlpha", "SetShadowOffset",
  "SetShadowColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetTextInsets", "SetAutoFocus", "SetMaxLetters", "SetNumeric",
  "ClearFocus", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDesaturated",
  "SetFrameStrata", "EnableMouse", "SetMovable", "RegisterForDrag", "SetColorTexture", "SetAtlas", "SetScale",
  "SetHorizTile", "SetVertTile", "SetResizeBounds", "SetClipsChildren", "SetScrollChild", "RegisterEvent",
  "SetDrawLayer", "SetFontObject", "SetSpacing", "SetNonSpaceWrap", "SetIndentedWordWrap", "SetMaxLines",
  "HasFocus" }) do   -- the shared field's placeholder asks whether it has the focus (#371)
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

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local function said(fragment)
  for _, m in ipairs(printed) do if m:find(fragment, 1, true) then return true end end
  return false
end
local NOW = 1757800000
function GetServerTime() return NOW end
time = function(t) if t then return os.time(t) end return NOW end
date = os.date
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
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
C_GuildInfo = { GuildRoster = function() end }

-- The guild. index, name, rank, rankIndex, level, class, zone, public note, officer note, online, classFile.
local ROSTER = {
  { "Ana-Firemaw",  "Officer", 1, 60, "Mage",    "Orgrimmar", "Anna Schmidt", "loot council", true,  "MAGE" },
  { "Beto-Firemaw", "Member",  3, 58, "Warrior", "",          "",             "",             false, "WARRIOR" },
  { "Caio-Firemaw", "Member",  3, 60, "Priest",  "Undercity", "Carl",         "",             true,  "PRIEST" },
  { "Dora-Firemaw", "Recruit", 4, 60, "Rogue",   "",          "Zed",          "",             false, "ROGUE" },
}
local myRank, viewOfficer = 0, true
function IsInGuild() return true end
function GetGuildInfo() return "Chama", "Rank", myRank end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  return r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], 0, r[10]
end
function CanViewOfficerNote() return viewOfficer end

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

local function key(n) return GuildOS:GetPlayerKey(n, "Firemaw") end
local ANA, BETO, CAIO, DORA = key("Ana"), key("Beto"), key("Caio"), key("Dora")

-- What the modules know, through the methods the columns read.
local lootSystem, attendanceTables = "dkp", {}
function GuildOS:GetLootSystem() return lootSystem end
GuildOS.Points = { Get = function(_, k) return k == ANA and 120 or 0 end }
GuildOS.LootTracker = {}
GuildOS.SpecChecker = { SpecName = function(_, spec) return spec.tree end }   -- a classic spec's name
GuildOS.RaiderRoster = { EffectiveRoles = function(_, k) return (k == CAIO and { HEALER = true, DPS = true }) or (k == DORA and { TANK = true }) or {} end }
GuildOS.AltRoster = {}
GuildOS.CoreManager = {
  GetSortedNames = function() return { "Main", "Ten" } end,
  GetMembers = function(_, n) return n == "Main" and { [ANA] = {}, [CAIO] = {} } or { [ANA] = {} } end,
}
GuildOS.RaidTracker = {
  GetAttendance25ManPercent = function(_, k, _, totals)
    attendanceTables[totals or "none"] = true
    return k == ANA and 80 or (k == CAIO and 40 or 0)
  end,
}
GuildOS.TrialTracker = { GetDaysRemaining = function(_, k) return k == DORA and 5 or nil end }
GuildOS.OfficerNotes = { GetNotes = function(_, k) return k == BETO and { { text = "newest" }, { text = "older" } } or {} end }
GuildOS.GuildManager = { GetDaysOffline = function(_, i) return ({ nil, 3, nil, 40 })[i] end }

GuildOS.db = {
  settings = { sortBy = "level", sortAsc = false, showOffline = true, officerMaxRank = 1, modules = {} },
  members = {
    [ANA] = { lastUpdate = NOW - 60, avgIlvl = 70, addonVersion = "0.83.0", race = "Orc", spec = { tree = "Frost", points = { 0, 0, 51 } },
              gear = { [1] = { name = "Helm", enchantId = 0 }, [5] = { name = "Chest", enchantId = 9 } } },
    [CAIO] = { lastUpdate = NOW - 120, addonVersion = "0.9.0" },
  },
  altLinks = { [DORA] = BETO },
  lootHistory = { { playerKey = ANA }, { playerKey = ANA }, { playerKey = CAIO } },
}

-- ── The window ──────────────────────────────────────────────────────────
local parent = CreateFrame("Frame", nil, UIParent)
parent.w, parent.h = 1600, 600
GuildOS:CreateRosterPanel(parent, parent)
GuildOS.RosterFrame = parent
flush()

local function headers()
  local shown = {}
  for k, btn in pairs(parent.headerButtons) do
    if btn:IsShown() then shown[#shown + 1] = { k = k, x = btn.points[1] and btn.points[1][2] or -1 } end
  end
  table.sort(shown, function(a, b) return a.x < b.x end)
  local out = {}
  for i, s in ipairs(shown) do out[i] = s.k end
  return table.concat(out, ",")
end
local function rowOf(name)
  for _, row in ipairs(parent.rows) do
    if row.memberData and row.memberData.name == name then return row end
  end
end
local function order()
  local out = {}
  for i, m in ipairs(parent.sortedMembers) do out[i] = m.name end
  return table.concat(out, ",")
end
local function panelRow(k)
  for _, child in ipairs(GuildOSColumnsPanel.children) do
    if child.key == k and child:IsShown() then return child end
  end
end
local function tick(k, on)
  local cb = panelRow(k).box.checkbox
  cb:SetChecked(on)
  cb:onChanged(on)
  flush()
end

-- ── The default is the table there always was ───────────────────────────
local DEFAULT = "name,level,class,avgIlvl,race,lastSeen,professions,zone"
check(headers() == DEFAULT, "the default header is the old eight: " .. headers())
check(not rowOf("Ana").textCells.note:IsShown(), "and no note cell is drawn")
check(GuildOSDB.rosterColumns == nil, "and nothing is stored")

-- ── The rows: the sketch's measurements (#377) ──────────────────────────
local C = GuildOS.Colors
local function same(color, token)
  return color ~= nil and math.abs(color[1] - token.r) < 1e-6 and math.abs(color[2] - token.g) < 1e-6
    and math.abs(color[3] - token.b) < 1e-6
end
do
  local rows = parent.rows
  -- The Salão's list (#449): the tiles (70), the card's title (34), the toolbar (28 and 6), the pills and 6, the
  -- header (24 and its rule), the card's bottom (10).
  local reserved = 70 + 34 + 28 + 6 + parent.filterH + 6 + 24 + 1 + 10
  check(parent.filterH >= 22 and #rows == math.floor((600 - reserved) / 26), "rows are 26px tall: as many as fit under the header")
  local stacked, flat, ruled = true, true, true
  for i, row in ipairs(rows) do
    local p = row.points[1]
    if row.h ~= 26 or p[1] ~= "TOPLEFT" or p[3] ~= -((i - 1) * 26) then stacked = false end
    if i <= 4 and not (row.bg and row.bg[4] == 0) then flat = false end
    local r = row.rule
    if not (r and r.h == 1 and same(r.color, C.line) and r.points[1][1] == "BOTTOMLEFT"
      and r.points[2][1] == "BOTTOMRIGHT") then ruled = false end
  end
  check(stacked, "each one 26px under the one before")
  check(flat, "no zebra: nothing behind a row at rest, the card shows through")
  check(ruled, "and a 1px line under each")
  check(rowOf("Ana").avatar.w == 20 and rowOf("Ana").avatar.letter.text == "A"
    and rowOf("Ana").nameText.font.file == GuildOS.Fonts.uiMedium,
    "a 20px round class avatar with the initial, the name in Alegreya Sans Medium (#449)")
  local marked = false
  for _, row in ipairs(rows) do if row.selMark.shown then marked = true end end
  check(not marked, "before any click no row is selected")

  -- A left click opens the member's sheet and selects the row.
  local sheets = {}
  function GuildOS:ShowMemberDetail(d)
    self.DetailFrame = self.DetailFrame or CreateFrame("Frame", nil, UIParent)
    self.DetailFrame:Show()
    sheets[#sheets + 1] = d.name
  end
  local ana = rowOf("Ana")
  fire(ana, "OnClick", "LeftButton")
  local m = ana.selMark
  check(sheets[1] == "Ana" and m.shown and m.w == 2 and same(m.color, C.gold) and m.points[1][1] == "TOPLEFT"
    and m.points[1][2] == 0 and m.points[2][1] == "BOTTOMLEFT", "the selected row: a 2px gold edge down its left side")
  check(ana.selFade and ana.selFade.shown, "and the gold wash that fades to the right")
  local others = true
  for _, row in ipairs(parent.rows) do
    if row ~= ana and row.shown and (row.selMark.shown or row.selFade.shown) then others = false end
  end
  check(others, "and only that one")
  -- The hover's tooltip reads half the addon; only the fill is under test here.
  GameTooltip = setmetatable({}, { __index = function() return function() end end })
  local tooltip = ShowRowTooltip
  ShowRowTooltip = function() end
  fire(ana, "OnEnter")
  check(ana.selFade.shown and ana.bg[4] == 0, "a selected row keeps its gold wash under the cursor")
  fire(ana, "OnLeave")
  local beto = rowOf("Beto")
  fire(beto, "OnEnter")
  check(beto.bg and beto.bg[4] > 0 and beto.bg[4] < 0.1 and not beto.selMark.shown, "another row takes a faint gold under the cursor")
  fire(beto, "OnLeave")
  check(beto.bg[4] == 0, "and nothing when it leaves")
  ShowRowTooltip = tooltip

  -- The list is virtual: the mark follows the member, not the row it was drawn on.
  local firstRow = parent.rows[1]
  check(firstRow.memberData.name == "Ana", "Ana is drawn on the first row")
  fire(parent.headerButtons.name, "OnClick", "LeftButton")
  fire(parent.headerButtons.name, "OnClick", "LeftButton")
  check(firstRow.memberData.name ~= "Ana" and not firstRow.selMark.shown and rowOf("Ana").selMark.shown,
    "sorted the other way, the first row shows someone else unmarked, and Ana's new row has the mark")
  fire(rowOf("Caio"), "OnClick", "LeftButton")
  check(rowOf("Caio").selMark.shown and not rowOf("Ana").selMark.shown, "clicking another member moves the selection")
  local menu = GuildOS.ShowMemberContextMenu
  GuildOS.ShowMemberContextMenu = function() end
  fire(rowOf("Dora"), "OnClick", "RightButton")
  GuildOS.ShowMemberContextMenu = menu
  check(rowOf("Caio").selMark.shown and not rowOf("Dora").selMark.shown, "a right click opens the menu, not a selection")
  GuildOS.DetailFrame:Hide()
  local none = true
  for _, row in ipairs(parent.rows) do if row.selMark.shown then none = false end end
  check(none and parent.selectedKey == nil, "closing the sheet clears the selection")
  GuildOS.db.settings.sortBy, GuildOS.db.settings.sortAsc = "level", false
  GuildOS:RefreshRosterUI()
end

-- ── The Members bar: the invite field moved here from the footer (#377) ─
do
  local UI = GuildOS.UI
  local field = parent.inviteField
  local bar = parent.searchBox.parent
  check(field.parent == bar, "the invite field is the Members bar's")
  check(not field.shown, "off Anniversary nobody is offered it (#256)")
  local canInvite = true
  CanGuildInvite = function() return canInvite end
  local invited
  GuildInvite = function(n) invited = n end
  GuildOS.Client.isAnniversary = true
  GuildOS:RefreshRosterUI()
  check(field.shown, "on Anniversary, for a rank that invites, it shows")
  local function x(fr) return fr.points[1][4] end
  check(x(field) > x(parent.offlineBtn) and x(parent.offlineBtn) > x(parent.searchBox) and x(parent.resultText) > x(field),
    "past the search and Show Offline, before the summary")
  check(field.button.variant == "primary" and field.button.label.text == "Invite" and field.box.h == 22
    and field.box.placeholder.text == "Player name...", "a 22px name box and the screen's one primary button, Invite")
  printed = {}
  field.box:SetText("")
  fire(field.button, "OnClick")
  check(invited == nil and said("Enter a player name to invite."), "an empty invite asks for a name")
  field.box:SetText("  Nova  ")
  fire(field.button, "OnClick")
  check(invited == "Nova" and said("Guild invite sent to Nova.") and field.box:GetText() == "",
    "it invites the name typed, then clears")
  canInvite = false
  GuildOS:RefreshRosterUI()
  check(not field.shown, "a rank that cannot invite does not see it, without a reload")
  canInvite = true

  -- A narrow bar drops in a set order and nothing overlaps; Show Offline always stays.
  local function relayout(room)
    parent.w = room + 2 * 12
    UI:Relayout(parent)
    flush()
  end
  local function parts()
    local out = {}
    for _, c in ipairs(bar.children) do
      if c.kind ~= "Texture" and c.shown then out[#out + 1] = c end
    end
    table.sort(out, function(a, b) return x(a) < x(b) end)
    return out
  end
  -- From the narrowest table the window draws: the watch band's 404px of content less the card's padding.
  local misfit
  for room = 404 - 24, 1300, 7 do
    relayout(room)
    local edge = 0
    for _, c in ipairs(parts()) do
      if x(c) < edge or x(c) + c.w > room then misfit = misfit or room end
      edge = x(c) + c.w
    end
    if not parent.offlineBtn.shown then misfit = misfit or room end
  end
  check(misfit == nil, "at every width the bar's parts stay inside it, apart, and Show Offline stays: " .. tostring(misfit))
  relayout(900)
  check(#parts() == 8 and field.shown, "900px holds all eight: the search, All, Online, Show Offline, Columns, Analytics, the invite field, the summary")
  -- Narrowing, what goes and in what order: the summary first, then Columns (a right click on the header
  -- opens it too), Analytics (the one way in to /gos analytics, #137), the invite field, and at the
  -- narrowest the search box; Show Offline stays.
  local named = { [parent.resultText] = "summary", [field] = "invite", [parent.searchBox] = "search",
                  [parent.offlineBtn] = "offline", [parent.segBtns.all] = "all", [parent.segBtns.online] = "online" }
  for _, c in ipairs(parts()) do
    if not named[c] then named[c] = c.label and c.label.text == "Analytics" and "analytics" or "columns" end
  end
  local gone, order = {}, {}
  for room = 900, 404 - 24, -2 do
    relayout(room)
    for fr, name in pairs(named) do
      if not fr.shown and not gone[name] then gone[name] = room; order[#order + 1] = name end
    end
  end
  table.sort(order, function(p, q) return gone[p] > gone[q] end)
  check(table.concat(order, ",") == "summary,columns,analytics,invite,search",
    "narrowing drops the summary, Columns, Analytics, the invite field, then the search: " .. table.concat(order, ","))
  check(not gone.offline and not gone.all and not gone.online, "Show Offline, All and Online stay at every width")

  -- A field kept is never hidden and shown again: the search filters on every keystroke and the roster
  -- updates while someone types a name, and a hidden EditBox loses the keyboard (B would open the bags).
  relayout(738)
  local hides = 0
  local hide = Frame.Hide
  local function watch(fr) fr.Hide = function(self) hides = hides + 1; return hide(self) end end
  watch(parent.searchBox); watch(field)
  parent.searchBox:SetText("Ab")
  if parent.searchBox.scripts.OnTextChanged then fire(parent.searchBox, "OnTextChanged") end
  GuildOS:RefreshRosterUI()
  flush()
  parent.searchBox.Hide, field.Hide = nil, nil
  parent.searchBox:SetText("")
  if parent.searchBox.scripts.OnTextChanged then fire(parent.searchBox, "OnTextChanged") end
  check(hides == 0 and parent.searchBox.shown and field.shown,
    "typing in the search and a roster update hide neither the search box nor the invite field (" .. hides .. ")")
  GuildOS.Client.isAnniversary = false
  parent.w = 1600
  UI:Relayout(parent)
  flush()
  check(not field.shown, "back off Anniversary, gone again")
  GuildInvite, CanGuildInvite = nil, nil
end

-- ── The panel offers what this reader may see ───────────────────────────
GuildOS:ToggleColumnsPanel(parent.headerButtons.level)
check(GuildOSColumnsPanel:IsShown(), "a right click on the header opens the panel")
check(panelRow("name") and not panelRow("name").box.checkbox:IsEnabled(), "Member is listed and cannot be turned off")
for _, k in ipairs({ "note", "officerNote", "rank", "offline", "spec", "roles", "main", "version", "enchants",
                     "attendance", "core", "dkp", "loot", "trial", "gosNote" }) do
  check(panelRow(k) ~= nil, "an officer is offered " .. k)
end
check(not panelRow("level").up:IsShown() and panelRow("level").down:IsShown(), "the first column has nowhere up to go")
check(panelRow("zone").up:IsShown() and not panelRow("zone").down:IsShown(), "the last has nowhere down to go")
check(not panelRow("note").up:IsShown() and not panelRow("note").down:IsShown(), "a hidden column has no arrows")

-- ── Turning a column on draws it at once, at the end ────────────────────
tick("note", true)
check(headers() == DEFAULT .. ",note", "the note goes to the end: " .. headers())
check(rowOf("Ana").textCells.note:IsShown() and rowOf("Ana").textCells.note:GetText() == "Anna Schmidt", "with the public note in it")
check(rowOf("Beto").textCells.note:GetText():find("-", 1, true), "an empty note reads as a dash")
check(GuildOSDB.rosterColumns ~= nil, "and the account keeps the choice")
check(panelRow("note").up:IsShown(), "a shown column gets its arrows")

-- ── Every column sorts, an empty cell last ──────────────────────────────
fire(parent.headerButtons.note, "OnClick", "LeftButton")
check(GuildOS.db.settings.sortBy == "note" and GuildOS.db.settings.sortAsc, "a text column sorts A to Z first")
check(order() == "Ana,Caio,Dora,Beto", "online first, then by note, the empty one last: " .. order())
fire(parent.headerButtons.note, "OnClick", "LeftButton")
check(order() == "Caio,Ana,Dora,Beto", "Z to A keeps the empty one last: " .. order())
fire(parent.headerButtons.zone, "OnClick", "LeftButton")
check(order() == "Ana,Caio,Beto,Dora", "zone sorts too: " .. order())
-- A Guild OS note that arrived over sync as a number sorts with the text ones instead of raising.
local notesOf = GuildOS.OfficerNotes.GetNotes
GuildOS.OfficerNotes.GetNotes = function(_, k)
  if k == ANA then return { { text = 42 } } end
  if k == CAIO then return { { text = "alpha" } } end
  return notesOf(_, k)
end
tick("gosNote", true)
fire(parent.headerButtons.gosNote, "OnClick", "LeftButton")
check(order() == "Ana,Caio,Beto,Dora", "a number among the texts sorts as text: " .. order())
GuildOS.OfficerNotes.GetNotes = notesOf
tick("gosNote", false)
fire(parent.headerButtons.zone, "OnClick", "LeftButton")
fire(parent.headerButtons.zone, "OnClick", "RightButton")
check(GuildOS.db.settings.sortBy == "zone" and GuildOSColumnsPanel:IsShown(), "a right click on a label opens the panel, not a sort")

-- ── Moving ──────────────────────────────────────────────────────────────
fire(panelRow("note").up, "OnClick")
flush()
check(headers() == "name,level,class,avgIlvl,race,lastSeen,professions,note,zone", "up one: " .. headers())

-- ── Every new column reads its value ────────────────────────────────────
for _, k in ipairs({ "officerNote", "rank", "offline", "spec", "roles", "main", "version", "enchants",
                     "attendance", "core", "dkp", "loot", "trial", "gosNote" }) do
  tick(k, true)
end
parent.w = 4000
UI = GuildOS.UI
UI:Relayout(parent)
flush()
local function cell(name, k) return rowOf(name).textCells[k]:GetText() end
check(cell("Ana", "officerNote") == "loot council", "the officer note")
check(cell("Ana", "rank") == "Officer", "the rank's name")
check(cell("Beto", "offline") == "3d ago", "days offline, from the game: " .. tostring(cell("Beto", "offline")))
check(cell("Ana", "offline"):find("Now", 1, true), "online reads Now")
check(cell("Ana", "spec") == "Frost 0/0/51", "the spec, its tree first: " .. tostring(cell("Ana", "spec")))
check(cell("Dora", "roles") == "T", "an offline row's letters are plain, greyed like the rest of it")
-- A sync takes the spec away while the window is closed; a scroll redraws before any refresh.
local spec = GuildOS.db.members[ANA].spec
GuildOS.db.members[ANA].spec = nil
parent:UpdateRows()
check(cell("Ana", "spec") == "Frost 0/0/51", "a redraw after the spec went away still draws what was read")
GuildOS.db.members[ANA].spec = { tree = "Fire", points = {} }
GuildOS:RefreshRosterUI()
check(cell("Ana", "spec") == "Fire", "no points, no trailing space: " .. tostring(cell("Ana", "spec")))
GuildOS.db.members[ANA].spec = spec
check(cell("Caio", "roles"):find("H", 1, true) and cell("Caio", "roles"):find("D", 1, true)
      and not cell("Caio", "roles"):find("T", 1, true), "the roles' letters")
check(cell("Dora", "main") == "Beto" and cell("Beto", "main") == "Main", "an alt names its main, a main says so")
check(cell("Caio", "version") == "0.9.0", "the addon version")
check(cell("Ana", "enchants") == 1, "one worn item without an enchant")
check(cell("Ana", "attendance") == "80%" and cell("Beto", "attendance"):find("-", 1, true), "attendance, none as a dash")
check(cell("Ana", "core") == "Main / Ten" and cell("Caio", "core") == "Main", "every core someone is on")
check(cell("Ana", "dkp") == 120, "DKP")
check(cell("Ana", "loot") == 2 and cell("Caio", "loot") == 1, "loot counted in one pass")
check(cell("Dora", "trial") == "5d", "trial days left")
check(cell("Beto", "gosNote") == "newest", "the newest Guild OS note")
local memos = 0
for t in pairs(attendanceTables) do if t ~= "none" then memos = memos + 1 end end
check(memos >= 1, "the column asks for attendance with the per-refresh memo")
fire(parent.headerButtons.offline, "OnClick", "LeftButton")
check(order() == "Ana,Caio,Dora,Beto", "offline sorts longest away first: " .. order())
fire(parent.headerButtons.avgIlvl, "OnClick", "LeftButton")
fire(parent.headerButtons.avgIlvl, "OnClick", "LeftButton")
check(GuildOS.db.settings.sortAsc, "the second click sorts lowest first")
check(order() == "Ana,Caio,Beto,Dora", "a member with no item level goes last that way too: " .. order())

-- ── A column this reader may not see is not offered ─────────────────────
viewOfficer, myRank, lootSystem = false, 5, "council"
GuildOS:ToggleColumnsPanel(parent.headerButtons.level)   -- close
GuildOS:ToggleColumnsPanel(parent.headerButtons.name)    -- and open again elsewhere
for _, k in ipairs({ "officerNote", "trial", "gosNote", "dkp" }) do
  check(panelRow(k) == nil, k .. " is not offered to a member here")
end
GuildOS:RefreshRosterUI()   -- an ordinary refresh, not a resize
flush()
for _, k in ipairs({ "officerNote", "trial", "gosNote", "dkp" }) do
  check(not parent.headerButtons[k]:IsShown(), k .. " leaves the table on the next refresh")
end
viewOfficer, myRank, lootSystem = true, 0, "dkp"
GuildOS:RefreshRosterUI()
flush()
check(parent.headerButtons.gosNote:IsShown(), "and comes back where it was once offered again")
check(panelRow("gosNote") ~= nil and panelRow("dkp") ~= nil, "the open panel follows without being reopened")
GuildOS.db.settings.modules.trialTracker = false
GuildOS:RefreshRosterUI()
flush()
check(not parent.headerButtons.trial:IsShown(), "trial days go with the trial tracker turned off")
GuildOS.db.settings.modules.trialTracker = nil

-- ── A narrow window drops the rightmost first ───────────────────────────
GuildOS.RosterColumns:Reset()
tick("note", true)
parent.w = 2 * 12 + 10 + 18 + 150 + 10 + 34 + 10 + 74 + 10 + 46 + 10 + 70 + 10 + 78 + 10 + 160 + 10 + 120
UI:Relayout(parent)
flush()
check(headers() == DEFAULT, "the note, last, is the first to go: " .. headers())

-- ── Restore defaults ────────────────────────────────────────────────────
tick("race", false)
for _, c in ipairs(GuildOSColumnsPanel.children) do
  if c.label and c.label:GetText() == "Restore defaults" then fire(c, "OnClick") end
end
flush()
check(GuildOSDB.rosterColumns == nil and headers() == DEFAULT, "Restore defaults brings the old table back")

-- ── The panel goes with the window ──────────────────────────────────────
parent:Hide()
check(not GuildOSColumnsPanel:IsShown(), "closing the roster closes the panel")

-- ── Recruitment: an officer whose recruitment never started (#255) ──────
-- Joined, founded or promoted after login: the officer modules ran before, so no db.recruitment
-- until a /reload. The member's view, saying so; never the officer's panel over a missing table.
do
  local isOfficer = GuildOS.IsOfficer
  function GuildOS:IsOfficer() return true end
  GuildOS.db.recruitment = nil
  local panel = CreateFrame("Frame", nil, UIParent)
  local ok, err = pcall(GuildOS.CreateRecruitmentPanel, GuildOS, panel, panel)
  check(ok, "a late officer's recruitment tab builds: " .. tostring(err))
  fire(panel, "OnShow")
  local function says(f, s)
    if type(f.text) == "string" and f.text:find(s, 1, true) then return true end
    for _, c in ipairs(f.children) do if says(c, s) then return true end end
    return false
  end
  check(says(panel, "/reload"), "and tells them to /reload")
  GuildOS.IsOfficer = isOfficer
end

-- ── Recruitment: the Trials sub-tab, an officer's (#367) ────────────────
-- The Trials tab became the officers' third sub-tab, offered while the registry allows the trials
-- feature (switched on, started, officerOnly), built the first time it opens, and a deep link to it
-- that is not offered lands on Recruiting.
do
  dofile(ADDON .. "/UI/FeatureRegistry.lua")
  dofile(ADDON .. "/UI/Features.lua")
  dofile(ADDON .. "/Modules/RecruitmentSystem.lua")   -- the officers' view reads its channels and checks
  -- What the officers' form calls on its boxes and nothing above did.
  for _, name in ipairs({ "SetMultiLine" }) do Frame[name] = Frame[name] or function() end end
  local UI = GuildOS.UI
  local isOfficer, officer = GuildOS.IsOfficer, true
  function GuildOS:IsOfficer() return officer end
  GuildOS.db.settings = GuildOS.db.settings or {}
  GuildOS.db.settings.modules = {}
  GuildOS.db.recruitment = { interval = 120, message = "", discord = "", welcomeMessage = "", channels = {} }
  local trialsBuilt, trialsDrawn = 0, 0
  local createTrials = GuildOS.CreateTrialsPanel
  function GuildOS:CreateTrialsPanel(p)
    trialsBuilt = trialsBuilt + 1
    p:SetScript("OnShow", function() trialsDrawn = trialsDrawn + 1 end)
  end

  local panel = CreateFrame("Frame", nil, UIParent)
  panel:Hide()
  local ok, err = pcall(GuildOS.CreateRecruitmentPanel, GuildOS, panel, panel)
  check(ok, "an officer's recruitment tab builds: " .. tostring(err))
  local tabs = {}
  local function collect(f)
    for _, c in ipairs(f.children) do
      if c.underline and c.label then tabs[c.label.text] = c end
      collect(c)
    end
  end
  collect(panel)
  check(tabs.Recruiting and tabs.Scanner and tabs.Trials, "Recruiting, Scanner and Trials are its sub-tabs")
  panel:SetSize(900, 500)
  panel:Show()
  flush()
  local trials = panel.subPanels.trials
  check(tabs.Trials.shown and panel.activeSub == "recruiting" and trialsBuilt == 0,
    "an officer is offered Trials, and it is not built before it opens")
  panel.SelectSub("trials")
  check(panel.activeSub == "trials" and trials.panel.shown and not panel.subPanels.recruiting.panel.shown
    and trialsBuilt == 1 and trialsDrawn == 1 and tabs.Trials.isActive,
    "a deep link opens Trials: built once, its own OnShow draws it, shown alone, its tab marked")
  panel.SelectSub("scanner")
  panel.SelectSub("trials")
  check(trialsBuilt == 1 and trialsDrawn == 2, "opened again it is not built again, and its OnShow redraws it")

  -- Switched off in Settings: no tab, and the deep link lands on Recruiting.
  GuildOS:SetFeatureEnabled("trials", false)
  panel:Hide()
  panel:Show()
  check(not tabs.Trials.shown and panel.activeSub == "recruiting" and not trials.panel.shown,
    "Trials switched off has no sub-tab, and the open one falls back to Recruiting")
  panel.SelectSub("trials")
  check(panel.activeSub == "recruiting", "and its deep link lands on Recruiting")
  GuildOS:SetFeatureEnabled("trials", true)
  -- A trial tracker that failed to start takes the sub-tab down with it, as it did the tab.
  GuildOS.State.startup.failedFeatures.trials = "TrialTracker"
  panel.SelectSub("trials")
  check(panel.activeSub == "recruiting", "a trial tracker that failed to start offers no Trials")
  GuildOS.State.startup.failedFeatures.trials = nil

  -- A rank that is no longer an officer's: not offered, even on the officers' view built earlier.
  officer = false
  panel:Hide()
  panel:Show()
  panel.SelectSub("trials")
  check(not tabs.Trials.shown and panel.activeSub == "recruiting", "Trials is for officers only")
  check(not UI:IsFeatureAllowed(UI:GetFeature("trials")), "as the registry says")
  -- A member's view has no sub-tabs at all: the deep link opens the tab as it is.
  local member = CreateFrame("Frame", nil, UIParent)
  check(pcall(GuildOS.CreateRecruitmentPanel, GuildOS, member, member) and member.SelectSub == nil,
    "a member's recruitment tab has no Trials to open")
  officer = true
  panel.SelectSub("trials")
  check(panel.activeSub == "trials" and tabs.Trials and trialsBuilt == 1, "an officer again: Trials is back")

  -- Promoted after logging in: the officers' view waits for a /reload, and a link to Trials says so.
  local said, print0 = {}, GuildOS.Print
  GuildOS.Print = function(_, m) said[#said + 1] = tostring(m) end
  local recruitment = GuildOS.db.recruitment
  GuildOS.db.recruitment = nil
  local late = CreateFrame("Frame", nil, UIParent)
  check(pcall(GuildOS.CreateRecruitmentPanel, GuildOS, late, late) and late.SelectSub, "a late officer's tab takes a deep link")
  late.SelectSub("trials")
  check(said[#said] == "You became an officer after logging in. Type /reload to manage recruiting.",
    "and a link to Trials says what to do")
  GuildOS.db.recruitment = recruitment

  -- A Trials builder that errors is recorded and refused, and the tab stays on Recruiting (issue #367).
  function GuildOS:CreateTrialsPanel() error("boom") end
  local broken = CreateFrame("Frame", nil, UIParent)
  check(pcall(GuildOS.CreateRecruitmentPanel, GuildOS, broken, broken), "an officer's tab builds with a broken Trials")
  broken:SetSize(900, 500)
  broken.SelectSub("trials")
  check(broken.activeSub == "recruiting" and broken.subPanels.recruiting.panel.shown and broken.subPanels.trials.failed,
    "a Trials that errors leaves the tab on Recruiting")
  check(said[#said] == "Trials could not start on this client. Type /guildos errors for details.", "saying so")
  broken.SelectSub("trials")
  check(broken.activeSub == "recruiting", "and is refused from then on")
  GuildOS.Print = print0

  GuildOS.CreateTrialsPanel, GuildOS.IsOfficer = createTrials, isOfficer
end

-- ── The Raids screen: Core Sign-up moved here from the footer (#377) ────
do
  for _, n in ipairs({ "CreateRaidsPanel", "CreateRaiderPanel", "CreateCoresPanel", "CreateAuditPanel", "CreateRaidToolsPanel" }) do
    GuildOS[n] = GuildOS[n] or function() end
  end
  local isOfficer, officer = GuildOS.IsOfficer, true
  function GuildOS:IsOfficer() return officer end
  local ran, show = 0, GuildOS.ShowCoreSignupFrame
  function GuildOS:ShowCoreSignupFrame() ran = ran + 1 end
  for _, who in ipairs({ "an officer", "a member" }) do
    local hub = CreateFrame("Frame", nil, UIParent)
    GuildOS:CreateRaidHubPanel(hub, hub)
    local btn = hub.signupButton
    local subBar = btn and btn.parent
    check(btn and btn.label.text == "Core Sign-up" and subBar.h == 28, who .. ": the Raids sub-tab bar has a Core Sign-up button")
    check(btn.points[1][1] == "RIGHT" and btn.points[1][3] == "RIGHT" and btn.points[1][4] == -8, "at its right end, 8px in")
    subBar:SetSize(900, 28)
    flush()
    check(btn.shown, who .. ": shown beside the tabs at 900px")
    local before = ran
    fire(btn, "OnClick")
    check(ran == before + 1, "and it opens the core sign-up")
    local tabs = 0
    for _, c in ipairs(subBar.children) do if c.kind == "Button" and c ~= btn then tabs = tabs + 1 end end
    check(tabs == (officer and 5 or 4), who .. " sees " .. tabs .. " sub-tabs, and the button either way")
    subBar:SetSize(4 + tabs * 112 + 8 + btn.w + 8, 28)
    flush()
    check(btn.shown, who .. ": still shown while it fits past the last tab")
    subBar:SetSize(4 + tabs * 112 + 8 + btn.w + 7, 28)
    flush()
    check(not btn.shown, who .. ": and stands down a pixel narrower, never over a tab")
    officer = false
  end
  GuildOS.IsOfficer, GuildOS.ShowCoreSignupFrame = isOfficer, show
end

-- ── Members › From the alliance (alianca.md §3.2): guildos.me's directory, read-only ──
do
  local keepAlly, keepTell, keepDetail, keepMenu = GuildOS.Alliance, ChatFrame_SendTell, GuildOS.ShowMemberDetail, GuildOS.ShowMemberContextMenu
  local dir = {}
  GuildOS.Alliance = {
    Directory = function() return dir end,
    OnlineNow = function() return { { name = "Zeca", guild = "Iron Pact" } } end,
    AsOf = function() return 1790000000 end,
  }
  local wasShown = parent.shown
  parent.shown = true
  GuildOS:RefreshRosterUI()
  check(not parent.segBtns.allied.shown, "no directory from the site: no From the alliance")
  dir = { { guild = "Iron Pact", members = {
    { key = "Zeca-Other", name = "Zeca", class = "MAGE", level = 70, role = "DPS", profs = { "Tailoring" }, recipes = {} },
    { key = "Yuri-Other", name = "Yuri", class = "PRIEST", level = 68, main = "Zeca-Other", recipes = {} } } },
          { guild = "Silver Hand", members = { { key = "Xan", name = "Xan", class = "MAGE", level = 60, recipes = {} } } } }
  GuildOS:RefreshRosterUI()
  check(parent.segBtns.allied.shown and parent.segBtns.allied.label.text == "From the alliance"
    and parent.segBtns.allied.count.text == "3", "with one, the rail offers From the alliance, with how many it lists")
  fire(parent.segBtns.allied, "OnClick")
  check(order():find("Zeca", 1, true) and order():find("Xan", 1, true) and not order():find("Ana", 1, true),
    "the table lists the allied members, none of the guild's")
  local zeca = rowOf("Zeca")
  check(zeca.memberData.allied and zeca.memberData.rank == "Iron Pact" and zeca.memberData.isOnline,
    "each with their guild in the rank's place, and on now as the channel tells")
  local opened, told = 0, nil
  function GuildOS:ShowMemberDetail() opened = opened + 1 end
  GuildOS.ShowMemberContextMenu = function() opened = opened + 1 end
  ChatFrame_SendTell = function(n) told = n end
  fire(zeca, "OnClick", "RightButton")
  fire(zeca, "OnClick", "LeftButton")
  check(opened == 0 and told == "Zeca-Other", "read-only: no sheet, no menu, no rank action; a click whispers them")
  parent.classFilter = "PRIEST"
  GuildOS:RefreshRosterUI()
  check(order() == "Yuri", "the class chips filter them as the guild's")
  parent.classFilter = nil
  dir = {}
  GuildOS:RefreshRosterUI()
  GuildOS:RefreshRosterUI()
  check(parent.segment == "all" and not parent.segBtns.allied.shown, "the directory gone, the view goes back to All")
  GuildOS.Alliance, ChatFrame_SendTell, GuildOS.ShowMemberDetail, GuildOS.ShowMemberContextMenu = keepAlly, keepTell, keepDetail, keepMenu
  GuildOS:RefreshRosterUI()
  parent.shown = wasShown
end

print(("roster-table: %d checks passed"):format(checks))
