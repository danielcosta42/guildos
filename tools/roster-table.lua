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
for _, name in ipairs({ "SetClampedToScreen", "RegisterForClicks", "SetBackdrop", "SetBackdropColor",
  "SetBackdropBorderColor", "SetTexture", "SetTexCoord", "SetBlendMode", "SetAlpha", "SetShadowOffset",
  "SetShadowColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetTextInsets", "SetAutoFocus", "SetMaxLetters",
  "ClearFocus", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetVertexColor", "SetDesaturated",
  "SetFrameStrata", "EnableMouse", "SetMovable", "RegisterForDrag", "SetColorTexture", "SetAtlas", "SetScale",
  "SetHorizTile", "SetVertTile", "SetResizeBounds", "SetClipsChildren", "SetScrollChild", "RegisterEvent",
  "SetDrawLayer", "SetFontObject", "SetSpacing", "SetNonSpaceWrap", "SetIndentedWordWrap", "SetMaxLines" }) do
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
GuildOS.SpecChecker = {}
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
GuildOS.db.settings.modules.trialTracker = false
GuildOS:RefreshRosterUI()
flush()
check(not parent.headerButtons.trial:IsShown(), "trial days go with the trial tracker turned off")
GuildOS.db.settings.modules.trialTracker = nil

-- ── A narrow window drops the rightmost first ───────────────────────────
GuildOS.RosterColumns:Reset()
tick("note", true)
parent.w = 156 + 10 + 18 + 150 + 10 + 34 + 10 + 74 + 10 + 46 + 10 + 70 + 10 + 78 + 10 + 160 + 10 + 120
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

print(("roster-table: %d checks passed"):format(checks))
