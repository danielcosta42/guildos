-- The Bank tab (issue #380): the real UI/GuildBankPanel.lua built on the real helpers, under a stubbed
-- client, with a guild bank picture, a ledger, needs and requests in it.
--
-- Every sub-tab paints empty and full; the inventory finds, groups and sorts; the tab grid draws a
-- tab as it is and organized; needs and requests take a typed item; the bar under the game's bank
-- docks and offers organizing only where the rank may.
--
--   luajit -e 'ADDON="."' tools/guild-bank-panel.lua
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

-- ── A frame that keeps what the panel reads back, and takes anything else ──
local created = 0
local Frame = {}
local VERBS = { "Set", "Get", "Is", "Clear", "Enable", "Register", "Unregister", "Raise", "Lower", "Start", "Stop", "Add" }
local function newFrame(kind, parent)
  created = created + 1
  local f = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, shown = true, w = 0, h = 0,
                           enabled = true, alpha = 1 }, { __index = function(_, k)
    -- A method the stub does not keep does nothing; a field nobody set is nil, as on a real frame.
    if Frame[k] then return Frame[k] end
    if type(k) ~= "string" then return nil end
    for _, verb in ipairs(VERBS) do
      if k:find("^" .. verb) then return function() end end
    end
    return nil
  end })
  if parent and parent.children then parent.children[#parent.children + 1] = f end
  return f
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
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
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
end
function Frame:CreateTexture() return newFrame("Texture", self) end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text or "" end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetFont() return true end
function Frame:GetFrameLevel() return 1 end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:SetEnabled(v) self.enabled = v and true or false end
function Frame:IsEnabled() return self.enabled end
function Frame:IsMouseOver() return false end
function Frame:SetChecked(v) self.checked = v and true or false end
function Frame:GetChecked() return self.checked end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetScrollChild(c) self.scrollChild = c end
function Frame:SetBackdropBorderColor(r, g, b) self.border = { r, g, b } end
-- What the activity cards (#373) are read back by: where a frame is, which art a texture holds.
function Frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAtlas(name) self.atlas, self.texture = name, nil end
function Frame:SetTexCoord(...) self.coords = { ... } end
function Frame:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
function Frame:SetDesaturated(v) self.desaturated = v and true or false end

UIParent = newFrame("Frame")
function CreateFrame(kind, _, parent) return newFrame(kind, parent) end
GameTooltip = newFrame("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function UnitName(unit) if unit == "player" then return "Ana" end end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 70 end
local NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return 5000 end
time = function() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
C_Timer = { After = function() end, NewTicker = function() end }
function IsInGuild() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function SendChatMessage() end
local invited, tells = {}, {}
function InviteUnit(name) invited[#invited + 1] = name end
function ChatFrame_SendTell(name) tells[#tells + 1] = name end
-- The guild: everybody online, so every listing shows. The third field is the level (#373).
local ROSTER = { { "Bea-Realm", "PRIEST" }, { "Cid-Realm", "PRIEST" }, { "Dan-Realm", "PRIEST", 68 },
                 { "Ana-Realm", "PRIEST" }, { "Eve-Realm", "MAGE", 69 }, { "Fay-Realm", "PRIEST", 62 } }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local m = ROSTER[i]
  if m then return m[1], "Rank", 1, m[3] or 70, "Priest", "Zone", "", "", true, 0, m[2] end
end


function Frame:HasFocus() return false end
function Frame:SetFocus() end
function Frame:Insert() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll() end
function IsShiftKeyDown() return false end
function IsAltKeyDown() return false end
local linked = {}
function HandleModifiedItemClick(link) linked[#linked + 1] = link end

local ITEMS = {
  [22854] = { "Flask of Relentless Assault", 1, 0, 3, 20 },
  [22832] = { "Super Mana Potion", 1, 0, 1, 20 },
  [23445] = { "Fel Iron Bar", 1, 7, 7, 20 },
  [28555] = { "Seamaiden's Pendant", 4, 4, 0, 1 },
  [3300] = { "Rabbit's Foot", 0, 15, 0, 20 },   -- grey: the cleanup sells it
}
local function idOf(item)
  if type(item) == "number" then return item end
  if type(item) == "string" then return tonumber(item:match("item:(%d+)")) or tonumber(item) end
end
local function linkOf(id) return "|cffffffff|Hitem:" .. id .. "::::|h[" .. ITEMS[id][1] .. "]|h|r" end
function GetItemInfoInstant(item)
  local id = idOf(item); local it = id and ITEMS[id]
  if it then return id, "", "", "", "icon" .. id, it[3], it[4] end
end
function GetItemInfo(item)
  local id = idOf(item); local it = id and ITEMS[id]
  if it then return it[1], linkOf(id), it[2], 100, 1, "", "", it[5] end
end
local TABS = { { "Raid", -1 }, { "Mats", 5 } }
function GetNumGuildBankTabs() return #TABS end
function GetGuildBankTabInfo(tab) local t = TABS[tab]; if t then return t[1], "i", true, true, t[2], t[2] end end
function GetGuildBankItemInfo() return nil, 0 end
function QueryGuildBankTab() end
function QueryGuildBankLog() end
function IsGuildLeader() return false end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
dofile(ADDON .. "/Core/Utils.lua")
GuildOS.Style:Resolve()
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
local wire = {}
GuildOS.SyncService = {
  On = function() end,
  Publish = function(_, d, act, data) wire[#wire + 1] = { d = d, act = act, data = data } end,
  GetRevision = function() return 0 end, NextRevision = function() return 1 end,
  ShouldApply = function() return true end, SetRevision = function() end,
}
GuildOS.Print = function() end
GuildOS.Compat.After = function(_, fn) fn() end
GuildOS.Compat.HookTooltip = function() return true end
GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end   -- an error in a paint fails the test, loudly
GuildOS.Coalesce = function(_, _, _, fn) fn() end
local officer = true
GuildOS.IsOfficer = function() return officer end
GuildOS.IsOfficerByName = function() return officer end
GuildOS.db = { settings = {}, members = {} }
dofile(ADDON .. "/Modules/GuildBankPlan.lua")
dofile(ADDON .. "/Modules/GuildBank.lua")
dofile(ADDON .. "/Modules/GuildBankCleanup.lua")
dofile(ADDON .. "/UI/GuildBankPanel.lua")
local Bank = GuildOS.GuildBank
GuildOS.State.gbank = nil
Bank:Store()

local function walk(f, visit)
  visit(f)
  for _, c in ipairs(f.children) do walk(c, visit) end
end
local function texts(root)
  local out = {}
  walk(root, function(f)
    if f.kind == "FontString" and f:IsVisible() and f.text and f.text ~= "" then out[#out + 1] = f.text end
  end)
  return table.concat(out, "\n")
end
local function shows(root, text) return texts(root):find(text, 1, true) ~= nil end
local function buttons(root, label)
  local out = {}
  walk(root, function(f)
    if f.kind == "Button" and f:IsVisible() and f.label and f.label.text == label then out[#out + 1] = f end
  end)
  return out
end
-- The stub has no layout engine: give every list a size and run what a resize runs.
local function lay(root)
  walk(root, function(f)
    if f.scripts.OnSizeChanged and f.kind == "Frame" then
      if (f.w or 0) == 0 then f:SetSize(700, 400) end
      f.scripts.OnSizeChanged(f)
    end
  end)
end

local panel = newFrame("Frame", UIParent)
panel:SetSize(980, 620)
GuildOS:CreateGuildBankPanel(panel)
check(type(panel.SelectSub) == "function", "the tab takes a deep link")
for _, sub in ipairs({ "inventory", "tabs", "ledger", "needs", "requests", "cleanup" }) do
  panel.SelectSub(sub)
  lay(panel)
  check(panel.ActiveSub() == sub, sub .. " opens")
end
panel.SelectSub("inventory")
lay(panel)
check(shows(panel, "Nobody with Guild OS has opened the guild bank yet."), "an empty bank says how to fill it")
panel.SelectSub("tabs")
check(shows(panel, "Nobody with Guild OS has opened the guild bank yet."), "and so does the tab grid")

-- ── With a bank ─────────────────────────────────────────────────────────
Bank:ApplySnapshot({ tabs = {
  [1] = { n = "Raid", ts = NOW - 3600, by = "Bea", s = "1,23445,7;9,22854,5;30,22854,20;31,28555,1;40,22832,20" },
  [2] = { n = "Mats", ts = NOW - 7200, by = "Cid", s = "1,23445,20" },
}, m = 12345678, mt = NOW - 3600, nt = 2 }, "Bea")
Bank:MergeStream(1, { { t = NOW - 7200, ty = "d", n = "Bea", id = 23445, c = 20 }, { t = NOW - 3600, ty = "w", n = "Cid", id = 22854, c = 2 } })
Bank:MergeStream(0, { { t = NOW - 600, ty = "d", n = "Dan", g = 1000000 } })
Bank:SetNeed(22854, 60, "raid")
Bank:Request(22832, 5, "heals")

panel.SelectSub("inventory")
lay(panel)
local inv = texts(panel)
check(inv:find("Fel Iron Bar", 1, true) and inv:find("Flask of Relentless Assault", 1, true), "the inventory lists the items")
check(inv:find("Consumables", 1, true) and inv:find("Trade goods", 1, true) and not inv:find("CONSUMABLES", 1, true),
  "grouped by category, never in capitals (#449)")
check(inv:find("27", 1, true) and inv:find("Tab 1: 7  Tab 2: 20", 1, true), "with totals and where they are")
check(inv:find("35 short", 1, true), "and what is short of a need")
check(inv:find("1234", 1, true) ~= nil, "the bank's gold shows")

panel.SelectSub("tabs")
lay(panel)
check(shows(panel, "1 · Raid") and shows(panel, "5 of 98 slots"), "the tab grid shows the first tab")
local org = buttons(panel, "Organized")[1]
check(org ~= nil, "there is an Organized view")
org.scripts.OnClick(org)
local cells = {}
walk(panel, function(f) if f.kind == "Button" and f.tex and f.count then cells[#cells + 1] = f end end)
check(#cells == 98 and cells[1].slot and cells[1].slot.id == 22832 and cells[2].slot.id == 22854 and cells[2].slot.c == 20,
  "organized, the potion comes first, then the full stack of flasks")
check(cells[98].slot == nil, "and the end of the tab is empty")
check(shows(panel, "Open the guild bank first."), "away from the bank, organizing says why it cannot")

panel.SelectSub("ledger")
lay(panel)
local led = texts(panel)
check(led:find("deposited", 1, true) and led:find("withdrew", 1, true) and led:find("Bea", 1, true), "the ledger lists its lines")
check(led:find("Top contributors", 1, true) and led:find("Dan", 1, true), "and who gave most")

panel.SelectSub("needs")
lay(panel)
check(shows(panel, "Flask of Relentless Assault") and shows(panel, "35 short") and shows(panel, "raid"), "needs list what is short")
panel.SelectSub("requests")
lay(panel)
check(shows(panel, "Super Mana Potion") and shows(panel, "open"), "requests list what was asked")

officer = false
panel.SelectSub("cleanup")
lay(panel)
check(shows(panel, "Only officers decide what leaves the bank.") and not shows(panel, "To sell"), "a member sees why the cleanup is not theirs")
officer = true
panel.SelectSub("inventory")
panel.SelectSub("cleanup")
lay(panel)
check(shows(panel, "To sell") and shows(panel, "Gold back"), "the cleanup shows what selling would make")
local allBtn
walk(panel, function(f) if f.kind == "Button" and f:IsVisible() and f.label and f.label.text == "All" then allBtn = f end end)
if allBtn then allBtn.scripts.OnClick(allBtn) end
check(shows(panel, "Fel Iron Bar"), "and, with every verdict shown, lists the items")

-- Prefill from the inventory: a typed name reaches the form.
check(Bank:ParseItemInput("fel iron") == 23445, "a typed name names an item")

-- ── The bar under the game's bank ───────────────────────────────────────
GuildBankFrame = newFrame("Frame", UIParent)
Bank:OnEvent("GUILDBANKFRAME_OPENED")
local bar = _G.GuildOSGuildBankBar
check(bar == nil or bar.shown ~= false, "the bar docks when the bank opens")
local docked
walk(UIParent, function(f) if f.label and f.label.text == "Organize tab" then docked = f end end)
check(docked ~= nil, "the bar offers to organize the tab")
local cleanBtn
walk(UIParent, function(f) if f.label and type(f.label.text) == "string" and f.label.text:find("^Cleanup %(") and f.shown then cleanBtn = f end end)
check(cleanBtn ~= nil, "an officer's bar offers the cleanup, with how many items it would sell")

-- The cleanup happens beside the bank (#384): the bar's button opens a drawer, no trip to the window.
local CL = GuildOS.GuildBankCleanup
Bank:ApplySnapshot({ tabs = { [2] = { n = "Mats", ts = NOW, by = "Bea", s = "1,3300,4" } } }, "Bea")
-- The bank as the game shows it now: the grey stack in tab 2, the rank may take from it.
GetGuildBankItemInfo = function(tab, slot) if tab == 2 and slot == 1 then return "icon3300", 4, false end return nil, 0 end
GetGuildBankItemLink = function(tab, slot) if tab == 2 and slot == 1 then return linkOf(3300) end end
cleanBtn.scripts.OnClick(cleanBtn)
local drawer
walk(UIParent, function(f) if f.Dock and f.Draw then drawer = f end end)
check(drawer ~= nil and drawer:IsShown(), "the bar's Cleanup button opens the drawer")
local dp = drawer.points[1]
check(dp[1] == "TOPLEFT" and dp[2] == GuildBankFrame and dp[3] == "TOPRIGHT", "on the bank's right")
lay(drawer)
check(shows(drawer, " to sell · ") and shows(drawer, "1 Take out"), "with what selling would make and the steps")
check(shows(drawer, "Rabbit's Foot × 4") and shows(drawer, "Sell 1"), "and lists what may go, on the Sell filter")
local allBox
walk(drawer, function(f) if f.checkbox and f.label and f.label.text == "All suggested" then allBox = f.checkbox end end)
check(allBox ~= nil, "it offers to mark every suggestion")
allBox:SetChecked(true)
allBox.scripts.OnClick(allBox)
local marked = CL:MarkedCount()
check(marked > 0 and allBox:GetChecked(), "All suggested marks them")
local takeBtn = buttons(drawer, "Take out marked (1)")[1]
check(takeBtn ~= nil and takeBtn.enabled, "and the drawer's button offers the one stack that can come out")
local withdraw, took = CL.WithdrawMarked, false
CL.WithdrawMarked = function() took = true end
takeBtn.scripts.OnClick(takeBtn)
CL.WithdrawMarked = withdraw
check(took, "and takes it out")
allBox:SetChecked(false)
allBox.scripts.OnClick(allBox)
check(CL:MarkedCount() == 0 and #buttons(drawer, "Take out marked") == 1, "unticked, it unmarks them, and there is nothing to take")
-- A run under way shows how far it got, with Stop.
GuildOS.State.gbankClean.withdraw = { queue = {}, done = 2, total = 5 }
Bank:Refresh()
check(#buttons(drawer, "Taking out 2 of 5") == 1 and #buttons(drawer, "Stop") == 1, "a run shows its progress and can stop")
GuildOS.State.gbankClean.withdraw = nil
-- Gold the cleanup made is owed: the bank opens with the drawer on that step.
CL:Mine().toDeposit = 12345
Bank:OnEvent("GUILDBANKFRAME_CLOSED")
check(not drawer:IsShown(), "closing the bank closes the drawer")
Bank:OnEvent("GUILDBANKFRAME_OPENED")
check(drawer:IsShown() and #buttons(drawer, "Deposit 1g 23s 45c") == 1, "and the next visit opens it to put the gold back")
CL:Mine().toDeposit = 0
-- On a screen with no room on the bank's right, it docks on the left.
GuildBankFrame.GetRight = function() return 1800 end
UIParent:SetWidth(1920)
drawer:Dock()
dp = drawer.points[1]
check(dp[1] == "TOPRIGHT" and dp[3] == "TOPLEFT", "with no room on the right, it docks on the left")
GuildBankFrame.GetRight, UIParent.w = nil, 0
-- A member never sees it.
officer = false
Bank:Refresh()
check(not drawer:IsShown() and not cleanBtn.shown, "a member sees neither the button nor the drawer")
officer = true
Bank:Refresh()
cleanBtn.scripts.OnClick(cleanBtn)
check(drawer:IsShown(), "the button opens it again")
cleanBtn.scripts.OnClick(cleanBtn)
check(not drawer:IsShown(), "and closes it")
check(docked.enabled == true, "on a tab whose rank withdraws without limit")
TABS[1][2] = 5
Bank:Refresh()
check(docked.enabled == false, "and not on one with a limit")
-- The bar sits over the game's bank, never over its bottom (the bank's own log tabs are there).
local barFrame
walk(UIParent, function(f) if f.Place and f.Draw then barFrame = f end end)
check(barFrame ~= nil, "the bar exists")
barFrame:Place()
local p1 = barFrame.points and barFrame.points[1]
check(p1 and p1[1] == "BOTTOMLEFT" and p1[2] == GuildBankFrame and p1[3] == "TOPLEFT", "the bar sits on top of the bank, outside it")
-- Dragged, it stays where it was put; right-clicking its name puts it back.
function Frame:GetLeft() return 100 end
function Frame:GetBottom() return 200 end
barFrame.scripts.OnDragStop(barFrame)
local saved = GuildOS:GetSetting("gbankBarPos")
check(saved and saved.x == 100 and saved.y == 200, "a dragged bar keeps its place")
p1 = barFrame.points[1]
check(p1[1] == "BOTTOMLEFT" and p1[2] == UIParent and p1[4] == 100, "and is placed there next time")
GuildOS:SetSetting("gbankBarPos", nil)
Bank:OnEvent("GUILDBANKFRAME_CLOSED")

print(string.format("guild-bank-panel: %d checks passed", checks))
