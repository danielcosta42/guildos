-- The loot council window (issue #185), run against the real Core, Compat, Data, Style, Utils,
-- UI/Helpers.lua, TradeCouncil and UI/TradeCouncil.lua under a stub frame API and a stubbed retail
-- client on Tol Barad.
--
-- The window lists the raid's offers and my tradeable items, and for the offer picked: the item, who
-- offered it and for how long it can be traded, who wished for it, my Need / Greed / Pass (never on my
-- own offer), and every answer ranked with its roll, what the player wears in that slot, wishlist
-- place and attendance, with an Award button only for who may award. Every button calls the module,
-- and a new offer from the raid opens the window on it.
--
--   luajit -e 'ADDON="."' tools/trade-council-ui.lua
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
    w = 0, h = 0, level = parent and ((parent.level or 0) + 1) or 0, events = {} }, Frame)
  if parent then parent.children[#parent.children + 1] = f end
  return f
end
local function run(f, script, ...)
  local fn = f.scripts[script]
  if fn then return fn(f, ...) end
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints() end
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
function Frame:Show() if not self.shown then self.shown = true; run(self, "OnShow") end end
function Frame:Hide() if self.shown then self.shown = false; run(self, "OnHide") end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
  local old = self.scripts[name]
  self.scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel() return self.level end
function Frame:CreateTexture() return newFrame("Texture", self) end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetFont() return true end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #(self.text or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
function Frame:IsEnabled() return true end
function Frame:IsMouseOver() return false end
function Frame:GetObjectType() return self.kind end
function Frame:IsObjectType(t) return self.kind == t end
for _, name in ipairs({ "SetClampedToScreen", "RegisterForClicks", "SetBackdrop", "SetBackdropBorderColor",
  "SetTexture", "SetTexCoord", "SetBlendMode", "SetAlpha", "SetShadowOffset", "SetShadowColor", "SetJustifyH",
  "SetJustifyV", "SetWordWrap", "SetVertexColor", "SetColorTexture", "SetAtlas", "SetFrameStrata", "EnableMouse",
  "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetNormalTexture", "SetHighlightTexture",
  "SetPushedTexture", "SetDrawLayer", "SetNonSpaceWrap", "SetMaxLines", "SetIgnoreParentAlpha", "SetEnabled",
  "Enable", "Disable", "RegisterEvent", "UnregisterEvent", "SetHitRectInsets", "SetMotionScriptsWhileDisabled" }) do
  Frame[name] = Frame[name] or function() end
end
function CreateFrame(kind, name, parent)
  local f = newFrame(kind, parent)
  if name then _G[name] = f end
  return f
end
UIParent = newFrame("Frame")
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function UIFrameFadeIn() end
local tip = {}
GameTooltip = { SetOwner = function() end, SetHyperlink = function(_, l) tip.link = l end, Show = function() end,
  Hide = function() end }

-- ── The rest of a retail client ────────────────────────────────────────
local NOW = 1791000000
local printed, addon = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
function issecretvalue() return false end
function hooksecurefunc() end
function debugstack() return "" end
function GetServerTime() return NOW end
time = function() return NOW end
date = os.date
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert, strlower, format = table.insert, string.lower, string.format
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local ROSTER = { { "Chehul-TolBarad", 1 }, { "Ana-Gallywix", 4 }, { "Bob-TolBarad", 4 } }
function IsInGuild() return true end
function GetGuildInfo() return "Jardim Escola", "Officer", 1, "Azralon" end
function GetRealmName() return "Tol Barad" end
function GetNormalizedRealmName() return "TolBarad" end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2] end end
function IsInRaid() return true end
function UnitName() return "Chehul" end
function UnitClass() return "Druid", "DRUID", 11 end
function GetInventoryItemLink() return nil end
local rolls = 0
function RandomRoll() rolls = rolls + 1 end
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
local function link(id, name) return ("|cnIQ4:|Hitem:%d::::::::90:::::|h[%s]|h|r"):format(id, name) end
local HELM, CAPE, RING = link(250001, "Voidforged Helm"), link(250003, "Gloomweave Cloak"), link(240011, "Old Band")
local BAGS = { [0] = { { itemID = 250001, hyperlink = HELM, quality = 4, isBound = true } } }
C_Container = {
  GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}
C_TooltipInfo = { GetBagItem = function() return { lines = { { type = 36, leftText = "for the next 1 hour 30 min." } } } end }
INT_SPELL_DURATION_HOURS, INT_SPELL_DURATION_MIN = "%d |4hour:hours;", "%d min"
Enum = { TooltipDataLineType = { TradeTimeRemaining = 36 } }
C_Item = { GetItemInfo = function() return nil end, GetItemInfoInstant = function() return nil end }
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, text) addon[#addon + 1] = text end,
  InChatMessagingLockdown = function() return false end,
  SendChatMessage = function() end,
}
local tickers = {}
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
  NewTicker = function(interval, fn)
    local t = { interval = interval, fn = fn }
    function t:Cancel() self.cancelled = true end
    tickers[#tickers + 1] = t
    return t
  end }
LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
  { __call = function() return {} end })
SlashCmdList, GuildOSDB = {}, {}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
GuildOS.Style:Resolve()
dofile(ADDON .. "/Core/Utils.lua")
GuildOS.db = { settings = { modules = {} }, members = { ["Ana-Gallywix"] = { class = "MAGE" } }, lootHistory = {} }
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/Modules/TradeCouncil.lua")
dofile(ADDON .. "/UI/TradeCouncil.lua")
local TC = GuildOS.TradeCouncil
TC:Initialize()

local function find(f, pred)
  if pred(f) then return f end
  for _, c in ipairs(f.children) do
    local hit = find(c, pred)
    if hit then return hit end
  end
end
local function label(f) return f.label and f.label.text end
local function shownText(root, text)
  return find(root, function(x) return x.kind == "FontString" and x.text == text and x:IsVisible() end) ~= nil
end

-- ── 1. A guildmate's offer opens the window on it ─────────────────────
local id = "65A1B2C30001"
TC:OnAddonMessage("GuildOSTC", ("O|%s|0|5400|%d|%s"):format(id, NOW - 60, CAPE), "RAID", "Ana-Gallywix")
local f = _G.GuildOSTradeCouncil
check(f and f:IsShown(), "a new offer opens the loot council")
local d = f.detail
check(d.item.label.text == CAPE and d.info.text == "Offered by Ana-Gallywix, tradeable for 1:31.", "the offer picked: its item and who offered it")
check(f.offerRows[1]:IsShown() and f.offerRows[1].label.text:find("Gloomweave Cloak", 1, true)
  and f.offerRows[1].label.text:find("Ana", 1, true) and f.offerRows[1].time.text == "1:31",
  "the raid's offers: item, holder and the time left (a minute's slack)")
check(not f.offerRows[2]:IsShown() and not f.noOffers:IsShown(), "one offer, one row")
check(f.itemRows[1]:IsShown() and f.itemRows[1].label.text == HELM and f.itemRows[1].time.text == "1:30",
  "my tradeable items, with their time left")
check(d.status.text == "An officer awards it.", "who awards it")
for _, b in ipairs(d.choiceButtons) do check(b:IsShown(), "I can answer " .. label(b)) end

-- ── 2. Answers, ranked, with Award for an officer ─────────────────────
TC:OnAddonMessage("GuildOSTC", ("A|%s|G|%s"):format(id, RING), "RAID", "Bob-TolBarad")
run(d.choiceButtons[1], "OnClick")
check(addon[#addon] == ("A|%s|N|"):format(id), "my Need goes to the raid")
local r1, r2 = d.rows[1], d.rows[2]
check(r1:IsShown() and r1.name.text == "Chehul" and r1.answer.text == "Need", "my Need ranks first, named without my own realm")
check(r2.name.text == "Bob" and r2.answer.text == "Greed" and r2.worn.label.text == RING, "Bob's Greed, with what he wears")
check(rolls == 1 and r1.roll.text == "-", "my Need rolls the server's /roll; until its line is seen there is no roll")
TC:OnSystemMessage("Chehul rolls 63 (1-100)")
check(d.rows[1].roll.text == "63", "and when it is seen, the row shows it")
check(not d.rows[3]:IsShown() and not d.noAnswers:IsShown(), "two answers, two rows")
check(r1.award:IsShown() and r2.award:IsShown(), "an officer sees Award by each answer")
run(r2.award, "OnClick")
check(TC:Get(id).award.winner == "Bob-TolBarad" and addon[#addon] == ("W|%s|Bob-TolBarad"):format(id), "Award awards")
check(d.status.text == "|cffffd100Awarded to Bob-TolBarad: waiting for the trade.|r", "and the window says it waits for the trade")
check(d.withdraw:IsShown(), "an officer may withdraw it")

-- ── 3. My own offer: no answer buttons for me ─────────────────────────
run(f.itemRows[1].offer, "OnClick")
local mine
for oid, o in pairs(GuildOS.State.tradeCouncil.offers) do if o.holder == "Chehul-TolBarad" then mine = oid end end
check(mine and addon[#addon]:find("^O|" .. mine), "Offer offers my item to the raid")
GuildOS:ShowTradeCouncil(mine)
for _, b in ipairs(d.choiceButtons) do check(not b:IsShown(), "no " .. label(b) .. " on my own offer") end
check(d.status.text == "Free roll: the holder or an officer awards it.", "a free roll, as the guild rolls")
check(f.offerRows[2]:IsShown(), "both offers listed")
run(f.offerRows[1], "OnClick")
check(d.item.label.text == CAPE, "clicking an offer shows it")

-- ── 4. Withdrawn, and the ticker ──────────────────────────────────────
GuildOS:ShowTradeCouncil(mine)
run(d.withdraw, "OnClick")
check(addon[#addon] == "X|" .. mine, "Withdraw withdraws")
local live
for _, t in ipairs(tickers) do if not t.cancelled then live = t end end
check(live ~= nil, "the window ticks while it is open")
f:Hide()
check(live.cancelled, "and stops when it is closed")

print(("trade-council-ui: %d checks passed"):format(checks))
