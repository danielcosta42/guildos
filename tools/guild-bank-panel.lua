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
    -- GBP_ALL=1 lists every failure instead of stopping at the first.
    if os.getenv("GBP_ALL") ~= "1" then os.exit(1) end
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
dofile(ADDON .. "/UI/Spacing.lua")
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/UI/Kit.lua")
dofile(ADDON .. "/UI/Forms.lua")
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
-- The stub has no layout engine: give every list and every board (its scroll frame) a size and run what a
-- resize runs.
local function lay(root)
  walk(root, function(f)
    if f.scripts.OnSizeChanged and (f.kind == "Frame" or f.kind == "ScrollFrame") then
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
check(not led:find("Bank tax owed", 1, true) and not led:find("\nTax\n", 1, true), "no bank tax: no Tax column and nobody owes")
-- The bank tax (Ley): 10% from before Cid's withdrawal; the flask is worth 50s at the auction house.
GuildOS.db.settings.bankTaxPct, GuildOS.db.settings.bankTaxSince, GuildOS.db.settings.bankTaxAt = 10, NOW - 7000, NOW - 7000
GuildOS.Compat.AuctionPrice = function(id) return id == 22854 and 5000 or nil end
panel.SelectSub("needs")
panel.SelectSub("ledger")
lay(panel)
led = texts(panel)
check(led:find("Tax", 1, true) and led:find("Bank tax owed", 1, true) and led:find("Cid", 1, true),
  "with the tax on: the Tax column and who owes it")
GuildOS.db.settings.bankTaxPct, GuildOS.db.settings.bankTaxSince, GuildOS.db.settings.bankTaxAt = nil, nil, nil
GuildOS.Compat.AuctionPrice = function() return nil end

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
check(shows(drawer, " to sell · ") and shows(drawer, "Take out") and shows(drawer, "Gold back"),
  "with what selling would make and the steps")
local function segment(key)
  for _, b in ipairs(drawer.seg.buttons) do if b.key == key then return b end end
end
check(shows(drawer, "Rabbit's Foot × 4") and segment("sell").label.text == "Sell" and segment("sell").count.text == "1"
  and segment("sell").isActive, "and lists what may go, on the Sell segment, with its count")
check(drawer.steps.current == 1 and drawer.steps.parts[1].state == "now" and drawer.steps.parts[2].state == "next",
  "the first step is lit while something is marked or can be")
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

-- ── The Salão's look on the game's bank (#449): sizes, tooltips, docking, steps ──
do
  local CL = GuildOS.GuildBankCleanup
  local B = barFrame.buttons
  -- Text widths as the client draws them, near enough: a Latin or Cyrillic letter 6.5 px, a Hangul or Han one 12.
  local realWidth = Frame.GetStringWidth
  function Frame:GetStringWidth()
    local s = tostring(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local w = 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do w = w + (ch:byte() >= 0xE0 and 12 or 6.5) end
    return w
  end
  local function localeTable(code)
    local saveL, saveGL = GuildOS.L, GetLocale
    local T = setmetatable({}, { __index = function(_, k) return k end })
    GuildOS.L, GetLocale = T, function() return code end
    dofile(ADDON .. "/Locales/" .. code .. ".lua")
    GuildOS.L, GetLocale = saveL, saveGL
    return T
  end
  -- Everything the bar shows sits inside it, one after the other, each button wider than its label.
  local function barFits(what)
    local laid, inner = barFrame.laid, barFrame.contentW
    check(barFrame.w == inner + 6, what .. ": the bar is as wide as what it holds")
    for i, e in ipairs(laid) do
      check(e.x >= 12 and e.x + e.w <= inner - 12, what .. ": nothing past the bar's edges (" .. i .. ")")
      if i > 1 then check(e.x >= laid[i - 1].x + laid[i - 1].w + 6, what .. ": nothing over its neighbour (" .. i .. ")") end
      if e.f.label then
        check(e.w >= e.f.label:GetStringWidth() + 24, what .. ": a button fits its label: " .. tostring(e.f.label.text))
        check(e.f.h == 24, what .. ": every button one height")
      end
    end
  end
  barFrame:Draw()
  barFits("enUS")
  check(B.one.w == B.all.w, "the two organize buttons are one width")
  local codes = { "enUS", "ptBR", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW", "itIT" }
  for _, code in ipairs(codes) do
    local T = localeTable(code)
    B.one.label:SetText(T["Organize tab"]); B.all.label:SetText(T["Organize all"])
    B.take.label:SetText(string.format(T["Cleanup (%d)"], 128)); B.open.label:SetText(T["Open in Guild OS"])
    barFrame:Layout()
    barFits(code)
    -- A run: Pause and Stop, and how far it got.
    B.one:Hide(); B.all:Hide(); B.take:Hide(); B.pause:Show(); B.stop:Show()
    B.pause.label:SetText(T["Resume"]); B.stop.label:SetText(T["Stop"])
    barFrame.status:SetText(string.format(T["Tab %d: move %d of about %d"], 3, 120, 240) .. string.format(T[" · %d tabs to go"], 4))
    barFrame.status:Show()
    barFrame:Layout()
    barFits(code .. " running")
    check(barFrame.status.w <= 280, code .. ": a run's line has a cap")
    B.one:Show(); B.all:Show(); B.take:Show(); B.pause:Hide(); B.stop:Hide(); barFrame.status:Hide()
    -- The drawer: its segments, its steps and its button inside its width.
    local inner = drawer.inner
    for _, b in ipairs(drawer.seg.buttons) do
      b.label:SetText(T[({ sell = "Sell", review = "Review", keep = "Keep" })[b.key]]); b.count:SetText("128")
      check(b.label:GetStringWidth() + 5 + b.count:GetStringWidth() + 8 <= drawer.seg.segW,
        code .. ": a segment fits its name and count: " .. b.label.text)
    end
    check(3 * drawer.seg.segW + 4 <= inner, code .. ": the segments inside the drawer")
    for i, k in ipairs({ "Take out", "Sell", "Gold back" }) do drawer.steps.parts[i].label:SetText(T[k]) end
    for cur = 1, 3 do
      drawer.steps:Set(cur)
      drawer.steps:Layout(inner)
      check(drawer.steps.laidW <= inner, code .. ": the steps inside the drawer (step " .. cur .. ")")
      check(drawer.steps.parts[cur].label.shown, code .. ": the lit step is named")
    end
    for _, k in ipairs({ "Take out marked (%d)", "Taking out %d of %d", "Deposit %s" }) do
      drawer.main.label:SetText(string.format(T[k], 128, 256))
      check(drawer.main.label:GetStringWidth() + 24 + 76 <= inner, code .. ": the drawer's button and Stop fit: " .. drawer.main.label.text)
    end
  end
  barFrame:Draw()
  check(drawer.summary.w == drawer.inner, "the summary wraps inside the drawer")

  -- What each button does is in its tooltip, not in a line cut short on the bar.
  local tip = {}
  local realSet, realAdd = GameTooltip.SetText, GameTooltip.AddLine
  GameTooltip.SetText = function(_, t) tip = { t } end
  GameTooltip.AddLine = function(_, t) tip[#tip + 1] = t end
  local function tipOf(f) tip = {}; f.scripts.OnEnter(f); return table.concat(tip, "\n"), #tip end
  check(tipOf(B.one):find("Merges stacks and sorts by category", 1, true), "Organize tab explains itself")
  local _, nOne = tipOf(B.one)
  check(not B.one.enabled and nOne >= 3, "and, disabled, says why")
  check(tipOf(B.all):find("Every tab your rank may organize", 1, true), "Organize all explains itself")
  check(tipOf(B.take):find("What the bank holds that nobody takes", 1, true), "the cleanup explains itself")
  check(tipOf(B.open):find("ledger, needs and requests", 1, true), "Open in Guild OS says what it opens")
  check(not shows(barFrame, "Merges stacks"), "and the bar draws no explanation of its own")
  check(tipOf(drawer.steps.parts[2]):find("vendor", 1, true), "a step says what it is")
  drawer:Show(); drawer:Draw()
  lay(drawer)
  local row
  walk(drawer.list, function(f) if f.data and f.why then row = row or f end end)
  check(row and row.why.text ~= "" and tipOf(row):find(row.why.text, 1, true), "a row's tooltip holds the whole of why")
  GameTooltip.SetText, GameTooltip.AddLine = realSet, realAdd

  -- The steps: the one to do now lit, those done behind it.
  local realSellable, realQueue = CL.Sellable, CL.Queue
  CL.Sellable = function() return { {} } end
  CL.Queue = function() return {} end
  drawer:Draw()
  check(drawer.steps.current == 2 and drawer.steps.parts[1].state == "done" and drawer.steps.parts[2].state == "now"
    and drawer.steps.parts[3].state == "next", "stacks out and nothing more to take: Sell is lit")
  CL.Sellable, CL.Queue = realSellable, realQueue
  CL:Mine().toDeposit = 500
  drawer:Draw()
  check(drawer.steps.current == 3 and drawer.steps.parts[3].state == "now" and drawer.steps.parts[2].state == "done",
    "gold owed: Gold back is lit")
  CL:Mine().toDeposit = 0
  drawer:Draw()
  check(drawer.steps.current == 1, "and back to the first")

  -- Docked on the bank's right, past the game's tab buttons there (they drew over the drawer's corner).
  GuildBankFrame.GetRight = function() return 800 end
  UIParent:SetWidth(1920)
  for i = 1, 6 do
    local t = newFrame("Frame", GuildBankFrame)
    t.GetRight = function() return 838 end
    _G["GuildBankTab" .. i] = t
  end
  drawer:Dock()
  local dp = drawer.points[1]
  check(dp[1] == "TOPLEFT" and dp[2] == GuildBankFrame and dp[3] == "TOPRIGHT" and dp[4] >= 38 + 4,
    "the drawer docks clear of the bank's tab buttons (" .. tostring(dp[4]) .. ")")
  check(drawer.points[2][4] == dp[4], "top and bottom alike")
  for i = 1, 6 do _G["GuildBankTab" .. i].GetRight = function() return nil end end
  drawer:Dock()
  check(drawer.points[1][4] >= 44, "unmeasured, it keeps the room they take")
  for i = 1, 6 do _G["GuildBankTab" .. i]:Hide() end
  drawer:Dock()
  check(drawer.points[1][4] == 4, "with no tab buttons shown, it sits by the bank")
  for i = 1, 6 do _G["GuildBankTab" .. i]:Show(); _G["GuildBankTab" .. i].GetRight = function() return GuildBankFrame:GetRight() + 38 end end
  GuildBankFrame.GetRight = function() return 1560 end
  drawer:Dock()
  check(drawer.points[1][1] == "TOPRIGHT" and drawer.points[1][3] == "TOPLEFT", "no room past the tabs: on the bank's left")
  for i = 1, 6 do _G["GuildBankTab" .. i] = nil end
  GuildBankFrame.GetRight, UIParent.w = nil, 0
  drawer:Hide()
  Frame.GetStringWidth = realWidth
end
Bank:OnEvent("GUILDBANKFRAME_CLOSED")

-- At a vendor: the leftovers window, docked on the vendor's, its items as icons, one Sell all (#449).
do
  local CL = GuildOS.GuildBankCleanup
  local realToSell, realOpen, realSell = CL.ToSell, CL.IsMerchantOpen, CL.SellOut
  local items = {}
  for i = 1, 12 do items[1000 + i] = i end
  CL.ToSell = function() return items, 11744 end
  CL.IsMerchantOpen = function() return true end
  local sold = 0
  CL.SellOut = function() sold = sold + 1 end
  MerchantFrame = newFrame("Frame"); MerchantFrame.w = 336
  CL.merchantOpened()
  local w = _G.GuildOSGuildBankSellBar or nil
  local bar
  for _, c in ipairs(UIParent.children) do if c.titleText and c.titleText.text == "Guild bank leftovers" then bar = c end end
  check(bar and bar.shown, "a vendor with leftovers opens the window")
  check(bar.w == 336 and bar.points[1][1] == "BOTTOMLEFT" and bar.points[1][2] == MerchantFrame, "as wide as the vendor's, on top of it")
  local icons, more, sum, sellBtn = 0, nil, nil, nil
  local function walk(f)
    for _, c in ipairs(f.children or {}) do
      if c.kind == "Button" and c.tex and c.shown then
        if c.id then icons = icons + 1 elseif c.more and c.more.text ~= "" then more = c.more.text end
      end
      if c.kind == "FontString" and type(c.text) == "string" and c.text:find("items") then sum = c.text end
      if c.label and c.label.text == "Sell all" then sellBtn = c end
      walk(c)
    end
  end
  walk(bar)
  check(icons >= 1 and more and more:find("^%+%d+$"), "the items as icons, the rest as +n (" .. icons .. ", " .. tostring(more) .. ")")
  check(sum and sum:find("78 items", 1, true), "how many and what they are worth: " .. tostring(sum))
  check(sellBtn and sellBtn.enabled, "one Sell all")
  sellBtn.scripts.OnClick(sellBtn)
  check(sold == 1, "which sells")
  local h = bar.h
  check(h > 60 and h < 200, "the window as tall as what it holds (" .. h .. ")")
  bar.closeBtn.scripts.OnClick(bar.closeBtn)
  CL.merchantRefresh()
  check(not bar.shown, "closed, it stays closed at this vendor")
  CL.merchantOpened()
  check(bar.shown, "and comes back at the next")
  items = {}
  CL.merchantRefresh()
  check(not bar.shown, "nothing left to sell: no window")
  CL.ToSell, CL.IsMerchantOpen, CL.SellOut = realToSell, realOpen, realSell
  MerchantFrame = nil
end


-- ── Every sub-screen in every language (#449): nothing runs past its box, nothing over its neighbour ──
-- The report: in German the Needs form's placeholder ran under the next field's label, the labels into the boxes,
-- and the header's text into the numbers and the buttons. Each sub-screen is built anew with each locale's
-- strings (as the client would load them) and laid out at 1000 and 800 px; then, from the anchors as the client
-- would resolve them, every text, field, button and number must fit its box and the card, and no two of them may
-- cross; in a list's rows, no two cells may cross either.
do
  local realW, realH, realFont, realAll, realWrap = Frame.GetStringWidth, Frame.GetStringHeight, Frame.SetFont,
    Frame.SetAllPoints, Frame.SetWordWrap
  local function plain(t) return tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "") end
  -- Text widths as the client draws them, near enough: a Latin or Cyrillic letter 6.5 px at 12 px, a Hangul or
  -- Han one 12, both scaled with the font's size; a wrapped text as many lines as its width makes.
  function Frame:SetFont(_, px) self.px = px; return true end
  function Frame:GetStringWidth()
    local w = 0
    for ch in plain(self.text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do w = w + (ch:byte() >= 0xE0 and 12 or 6.5) end
    return w * (self.px or 12) / 12
  end
  function Frame:GetStringHeight()
    local line = math.ceil((self.px or 12) * 1.25)
    if self.wrap ~= false and (self.w or 0) > 0 then return math.max(1, math.ceil(self:GetStringWidth() / self.w)) * line end
    return line
  end
  function Frame:SetWordWrap(v) self.wrap = v and true or false end
  function Frame:SetAllPoints(other) self.points = { { "ALL", other } } end

  -- Where a frame lies, from its anchors, in the panel's coordinates (y down): the client's layout, as
  -- tools/room-cards.lua resolves it.
  local function resolver(root, W, H)
    local rects, owner = {}, {}
    local function scan(fr) if fr.scrollChild then owner[fr.scrollChild] = fr end for _, c in ipairs(fr.children) do scan(c) end end
    scan(root)
    local resolve
    resolve = function(fr, depth)
      if rects[fr] then return rects[fr] end
      depth = (depth or 0) + 1
      if fr == root or depth > 60 then rects[fr] = { l = 0, t = 0, r = W, b = H }; return rects[fr] end
      local w, h = fr.w or 0, fr.h or 0
      if fr.kind == "FontString" then
        if w == 0 then w = fr:GetStringWidth() end
        if h == 0 then h = fr:GetStringHeight() end
      end
      local pts = fr.points or {}
      if #pts == 0 then
        local base = owner[fr] and resolve(owner[fr], depth) or (fr.parent and resolve(fr.parent, depth)) or { l = 0, t = 0 }
        rects[fr] = { l = base.l, t = base.t, r = base.l + w, b = base.t + h }
        return rects[fr]
      end
      local Lx, Rx, T, B, CX, CY
      for _, p in ipairs(pts) do
        if p[1] == "ALL" then
          local o = resolve(p[2] or fr.parent, depth)
          Lx, Rx, T, B = o.l, o.r, o.t, o.b
        else
          local point, rel, relPoint, x, y = p[1], nil, nil, 0, 0
          if type(p[2]) == "number" or p[2] == nil then x, y = p[2] or 0, p[3] or 0
          else rel, relPoint, x, y = p[2], p[3], p[4] or 0, p[5] or 0 end
          if type(relPoint) == "number" then relPoint, x, y = point, relPoint, x end
          rel = rel or fr.parent
          relPoint = relPoint or point
          local o = rel and resolve(rel, depth) or { l = 0, t = 0, r = W, b = H }
          local ax = (relPoint:find("LEFT") and o.l) or (relPoint:find("RIGHT") and o.r) or (o.l + o.r) / 2
          local ay = (relPoint:find("TOP") and o.t) or (relPoint:find("BOTTOM") and o.b) or (o.t + o.b) / 2
          ax, ay = ax + x, ay - y
          if point:find("LEFT") then Lx = ax elseif point:find("RIGHT") then Rx = ax else CX = ax end
          if point:find("TOP") then T = ay elseif point:find("BOTTOM") then B = ay else CY = ay end
        end
      end
      if not Lx and not Rx then Lx = (CX or 0) - w / 2; Rx = Lx + w elseif not Lx then Lx = Rx - w elseif not Rx then Rx = Lx + w end
      if not T and not B then T = (CY or 0) - h / 2; B = T + h elseif not T then T = B - h elseif not B then B = T + h end
      rects[fr] = { l = Lx, t = T, r = Rx, b = B }
      return rects[fr]
    end
    return resolve
  end
  -- The client sizes a frame from its anchors a frame later, and tells it: here, from the resolved anchors.
  local function settle(root, W, H)
    for _ = 1, 4 do
      local resolve = resolver(root, W, H)
      local function visit(fr)
        if fr.shown and fr.kind ~= "Texture" and fr.kind ~= "FontString" and #(fr.points or {}) >= 2 then
          local r = resolve(fr)
          local w, h = math.floor(r.r - r.l + 0.5), math.floor(r.b - r.t + 0.5)
          if w > 0 and h > 0 and (w ~= fr.w or h ~= fr.h) then
            fr.w, fr.h = w, h
            if fr.scripts.OnSizeChanged then fr.scripts.OnSizeChanged(fr, w, h) end
          end
        end
        for _, c in ipairs(fr.children) do visit(c) end
      end
      visit(root)
    end
  end

  local function visible(f, top)
    local x = f
    while x and x ~= top do if not x.shown then return false end x = x.parent end
    return true
  end
  local function isRow(f) return f.kind == "Button" and rawget(f, "hl") ~= nil end
  -- A piece the screen shows: a text, a field, a button, a number (KPI), a progress bar, an icon, a box, an empty state.
  local function isControl(f)
    if f.kind == "FontString" then return plain(f.text) ~= "" end
    if f.kind == "Button" or f.kind == "EditBox" or f.kind == "CheckButton" then return true end
    if rawget(f, "isCard") and rawget(f, "glyph") then return true end   -- an empty state
    if f.kind == "Frame" and rawget(f, "value") and rawget(f, "label") then return true end   -- a KPI
    if rawget(f, "bar") and rawget(f, "SetProgress") then return true end
    if rawget(f, "checkbox") then return true end
    if rawget(f, "icon") and f.kind == "Frame" and (f.w or 0) <= 40 then return true end
    return false
  end
  -- The screen's pieces outside the lists, and each shown row's cells.
  local function collect(root)
    local out, rows = {}, {}
    local function walk(f, into)
      for _, c in ipairs(f.children) do
        if c.shown and c.kind ~= "Texture" then
          if isRow(c) then
            local cells = {}
            rows[#rows + 1] = { row = c, cells = cells }
            walk(c, cells)
          elseif isControl(c) then
            into[#into + 1] = c
          else
            walk(c, into)
          end
        end
      end
    end
    walk(root, out)
    return out, rows
  end
  local function cardOf(f)
    local x = f.parent
    while x do
      if rawget(x, "isCard") and not rawget(x, "glyph") then return x end
      x = x.parent
    end
  end
  local function name(f)
    local t = f.kind == "FontString" and f.text or (rawget(f, "label") and f.label.text) or (rawget(f, "value") and f.value.text)
      or (rawget(f, "placeholder") and type(f.placeholder) == "table" and f.placeholder.text) or ""
    return f.kind .. " \"" .. plain(t) .. "\""
  end
  local function crosses(a, b)
    local ix = math.min(a.r, b.r) - math.max(a.l, b.l)
    local iy = math.min(a.b, b.b) - math.max(a.t, b.t)
    return ix > 0.5 and iy > 0.5, ix, iy
  end

  local function screenFits(root, W, H, what)
    local resolve = resolver(root, W, H)
    local controls, rows = collect(root)
    check(#controls >= 2, what .. ": the screen shows its pieces (" .. #controls .. ")")
    for _, f in ipairs(controls) do
      local r = resolve(f)
      local card = cardOf(f)
      if card then
        local c = resolve(card)
        check(r.l >= c.l - 1 and r.r <= c.r + 1, string.format("%s: %s inside its card across (%d..%d in %d..%d)", what, name(f), r.l, r.r, c.l, c.r))
      end
      -- A text on one line fits its own box (a wrapped one is as tall as its lines); a button's label, a field's
      -- placeholder and a number fit theirs.
      if f.kind == "FontString" and f.wrap == false then
        check(f:GetStringWidth() <= (r.r - r.l) + 1, string.format("%s: %s fits its box (%d > %d)", what, name(f), f:GetStringWidth(), r.r - r.l))
      end
      local label = rawget(f, "label")
      if f.kind == "Button" and label and plain(label.text) ~= "" then
        local lr = resolve(label)
        local room = math.min(r.r - r.l - 8, (#(label.points or {}) >= 2) and (lr.r - lr.l) or math.huge)
        check(label:GetStringWidth() <= room + 1, string.format("%s: %s fits its button (%d > %d)", what, name(f), label:GetStringWidth(), room))
      end
      local ph = rawget(f, "placeholder")
      if f.kind == "EditBox" and type(ph) == "table" and ph.shown then
        check(ph:GetStringWidth() <= (r.r - r.l) - 16 + 1, string.format("%s: %s placeholder inside its box (%d > %d)", what, name(f), ph:GetStringWidth(), r.r - r.l - 16))
      end
      if f.kind == "Frame" and rawget(f, "value") and label then
        for _, t in ipairs({ f.value, label }) do
          check(t:GetStringWidth() <= (r.r - r.l) - 24 + 1, string.format("%s: KPI text \"%s\" inside it", what, plain(t.text)))
        end
      end
    end
    for i = 1, #controls do
      local a = resolve(controls[i])
      if (a.r - a.l) >= 1 and (a.b - a.t) >= 1 then
        for j = i + 1, #controls do
          local b = resolve(controls[j])
          local hit, ix, iy = crosses(a, b)
          check(not hit, string.format("%s: %s and %s do not cross (%dx%d)", what, name(controls[i]), name(controls[j]), ix, iy))
        end
      end
    end
    for _, rw in ipairs(rows) do
      local cells = rw.cells
      for i = 1, #cells do
        local a = resolve(cells[i])
        for j = i + 1, #cells do
          local hit, ix, iy = crosses(a, resolve(cells[j]))
          check(not hit, string.format("%s: in a row, %s and %s do not cross (%dx%d)", what, name(cells[i]), name(cells[j]), ix, iy))
        end
        local rr = resolve(rw.row)
        check(a.l >= rr.l - 1 and a.r <= rr.r + 1, string.format("%s: in a row, %s inside it across", what, name(cells[i])))
      end
    end
    return #controls, #rows
  end

  local codes = { "enUS", "ptBR", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW", "itIT" }
  local saveL, saveGL, saveOfficer = GuildOS.L, GetLocale, officer
  local SUBS = { "inventory", "tabs", "ledger", "needs", "requests", "cleanup" }
  local laidRows = 0
  for _, code in ipairs(codes) do
    local T = setmetatable({}, { __index = function(_, k) return k end })
    GuildOS.L, GetLocale = T, function() return code end
    dofile(ADDON .. "/Locales/" .. code .. ".lua")
    dofile(ADDON .. "/UI/GuildBankPanel.lua")
    for _, W in ipairs({ 1000, 800 }) do
      local H = 640
      local host = newFrame("Frame", UIParent)
      host:SetSize(W, H)
      GuildOS:CreateGuildBankPanel(host)
      for _, sub in ipairs(SUBS) do
        for _, asOfficer in ipairs({ true, false }) do
          if asOfficer or sub == "needs" or sub == "cleanup" or sub == "requests" then
            officer = asOfficer
            host.SelectSub(sub)
            local p = host.panels[sub]
            settle(p, W, H - 28)
            p.Draw()
            settle(p, W, H - 28)
            local _, nr = screenFits(p, W, H - 28, string.format("%s %s at %d%s", code, sub, W, asOfficer and "" or " (member)"))
            laidRows = laidRows + nr
          end
        end
      end
      officer = true
    end
  end
  check(laidRows > 100, "the lists' rows were laid and checked (" .. laidRows .. ")")
  GuildOS.L, GetLocale, officer = saveL, saveGL, saveOfficer
  Frame.GetStringWidth, Frame.GetStringHeight, Frame.SetFont, Frame.SetAllPoints, Frame.SetWordWrap = realW, realH, realFont, realAll, realWrap
end

print(string.format("guild-bank-panel: %d checks passed", checks))
