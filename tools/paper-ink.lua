-- The paper's inks (#449), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/Data.lua,
-- Core/Style.lua, UI/Helpers.lua and UI/Kit.lua: every colour a screen draws on a parchment card goes through one
-- mapping (UI:InkFor, UI:Ink, UI.PaperRGB, UI:PaperText, UI:SetInk), and whatever it gives reads at 4.5:1 or
-- better against the paper (#f3e4c2): an item's quality, a class, a status, the wood's inks and golds, any
-- colour code in a string (an item link's). In the game a common item's white, a priest's white, a rogue's
-- yellow and the wood's light green vanished on the Ledger and the Cleanup.
--
--   luajit -e 'ADDON="."' tools/paper-ink.lua
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
  function f:GetParent() return self.parent end
  function f:SetText(t) self.text_ = t end
  function f:GetText() return self.text_ end
  function f:SetTextColor(r, g, b) self.color = { r = r, g = g, b = b } end
  function f:SetVertexColor(r, g, b) self.color = { r = r, g = g, b = b } end
  function f:CreateFontString() return frame(self) end
  function f:CreateTexture() return frame(self) end
  function f:GetWidth() return 100 end
  function f:GetHeight() return 20 end
  function f:GetFrameLevel() return 1 end
  function f:HookScript() end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
end
UIParent = frame()
function CreateFrame(_, _, parent) return frame(parent) end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.5", "70888", "", 20505 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
function GetTime() return 1 end
function UnitFullName() return "Lead", "" end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
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
dofile(ADDON .. "/UI/Spacing.lua")
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Kit.lua")
local UI, C, Kit = GuildOS.UI, GuildOS.Colors, GuildOS.Kit

local PAPER = C.paper
check(string.format("%02x%02x%02x", PAPER.r * 255 + 0.5, PAPER.g * 255 + 0.5, PAPER.b * 255 + 0.5) == "f3e4c2", "the paper is #f3e4c2")
-- reads(what, r, g, b) or reads(what, { r, g, b })
local function reads(what, r, g, b)
  if type(r) == "table" then r, g, b = r.r, r.g, r.b end
  local ratio = UI.Contrast({ r = r, g = g, b = b }, PAPER)
  check(ratio >= 4.5, ("%s reads at %.2f:1 on the paper, under 4.5:1"):format(what, ratio))
end

-- ── The paper's own inks ────────────────────────────────────────────────
for _, k in ipairs({ "paperInk", "paperSoft", "paperTitle", "paperLink", "quietInk" }) do reads("C." .. k, C[k]) end
for k, c in pairs(UI.STATUS_INK) do reads("the status ink " .. k, c) end
for k, c in pairs(UI.CLASS_INK) do reads("the class ink " .. k, c) end
for q, c in pairs(UI.QUALITY_INK) do reads("the quality ink " .. q, c) end
for _, k in ipairs({ "text", "textSoft", "silver", "label", "ok", "green", "warn", "danger", "red", "info", "epic",
  "offline", "disabled", "gold", "accent", "gold2" }) do
  if Kit.PAPER[k] then reads("Kit.PAPER." .. k, Kit.PAPER[k]) end
end

-- ── The mapping: quality, class, status ─────────────────────────────────
for q = 0, 8 do reads("an item of quality " .. q .. " on the paper", UI:InkFor("paper", "quality", q)) end
for file in pairs(GuildOS.ClassColors) do reads("a " .. file .. " on the paper", UI:InkFor("paper", "class", file)) end
reads("an unknown class on the paper", UI:InkFor("paper", "class", nil))
for _, s in ipairs({ "ok", "warn", "bad", "info", "mute", "epic", "nope" }) do reads("the status " .. s, UI:InkFor("paper", "status", s)) end
local r, g, b = UI:InkFor("paper", "quality", 1)
check(r == C.paperInk.r and g == C.paperInk.g, "a common item is the paper's ink, not white")
r, g, b = UI:InkFor("paper", "quality", 2)
check(g > r and g > b, "an uncommon item stays green on the paper")
r, g, b = UI:InkFor("wood", "quality", 2)
check(math.abs(g - 1) < 1e-6 and r < 0.2, "on the wood an uncommon item is the game's own green")
r = Kit:ClassInk("PRIEST")
check(r < 0.5, "a priest's white is dark grey on the paper")

-- ── Any colour meant for the wood (PaperRGB, UI:Ink) ─────────────────────
for _, k in ipairs({ "text", "textSoft", "silver", "label", "labelDim", "ok", "green", "online", "warn", "danger", "red",
  "info", "blue", "epic", "offline", "disabled", "gold", "gold2", "accent", "white", "orange", "yellow", "purple" }) do
  local c = C[k]
  if c and c.r then reads("C." .. k .. " as the paper prints it", UI.PaperRGB(c.r, c.g, c.b)) end
end
for q, c in pairs(GuildOS.QualityColors) do reads("quality " .. q .. "'s game colour as the paper prints it", UI.PaperRGB(c.r, c.g, c.b)) end
for file, c in pairs(GuildOS.ClassColors) do reads(file .. "'s game colour as the paper prints it", UI.PaperRGB(c.r, c.g, c.b)) end
for _, c in ipairs({ { r = 1, g = 0.8, b = 0.4 }, { r = 0.6, g = 1, b = 1 }, { r = 1, g = 1, b = 0 }, { r = 0.9, g = 0.6, b = 0.2 } }) do
  reads("a light colour of no palette, darkened", UI:Ink("paper", c))
end
local dark = { r = 0.2, g = 0.1, b = 0.05 }
check(UI:Ink("paper", dark).r == dark.r, "a colour that already reads is kept")
check(UI:Ink("wood", C.ok) == C.ok, "off the paper a colour is its own")
local ok = UI:Ink("paper", C.ok)
check(ok.r == UI.STATUS_INK.ok.r and ok.g == UI.STATUS_INK.ok.g, "the wood's ok is the paper's ok ink")

-- ── Colour codes in a string: an item link, a class-coloured name ───────
local link = "|cff1eff00|Hitem:2589::::::::70:::::|h[Linen Cloth]|h|r and |cffffffff|Hitem:1::::|h[Common]|h|r"
local out = UI:PaperText(link, "paper")
check(not out:find("1eff00", 1, true) and not out:lower():find("|cffffffff", 1, true), "an item link's light code is replaced on the paper")
for hx in out:gmatch("|cff(%x%x%x%x%x%x)") do
  reads("a code in a string on the paper (" .. hx .. ")", tonumber(hx:sub(1, 2), 16) / 255, tonumber(hx:sub(3, 4), 16) / 255, tonumber(hx:sub(5, 6), 16) / 255)
end
check(out:find("|Hitem:2589", 1, true) and out:find("[Linen Cloth]", 1, true), "the link itself is untouched")
local retail = UI:PaperText("|cnIQ4:|Hitem:19019::::|h[Thunderfury]|h|r", "paper")
check(retail:find("^|cff") and not retail:find("cnIQ", 1, true), "retail's quality code becomes the paper's epic ink")
check(UI:PaperText(link, "wood") == link, "on the wood a string is untouched")
local priest = GuildOS:ColorText("Velyra", GuildOS:GetClassColor("PRIEST"))
for hx in UI:PaperText(priest, "paper"):gmatch("|cff(%x%x%x%x%x%x)") do
  reads("a priest's name in a string on the paper", tonumber(hx:sub(1, 2), 16) / 255, tonumber(hx:sub(3, 4), 16) / 255, tonumber(hx:sub(5, 6), 16) / 255)
end

-- ── SetInk on a text: the paper's shade on a card, its own on the wood ──
local card = frame(UIParent); card.__paper = true
local fs = card:CreateFontString()
UI:SetInk(fs, 1, 1, 1)
reads("white set on a card's text", fs.color)
UI:SetInk(fs, GuildOS.ClassColors.ROGUE)
reads("a rogue's yellow set on a card's text", fs.color)
local woodFs = frame(UIParent):CreateFontString()
UI:SetInk(woodFs, 1, 1, 1)
check(woodFs.color.r == 1 and woodFs.color.g == 1, "on the wood a text keeps the colour given")
local inDark = frame(card); inDark.__dark = true
local badgeFs = inDark:CreateFontString()
UI:SetInk(badgeFs, 1, 1, 1)
check(badgeFs.color.r == 1, "a dark part on a card (a button, a badge) keeps its own colour")

-- ── No paper screen keeps its own copy of the class or status inks ───────
local function read(p) return assert(io.open(ADDON .. "/" .. p, "rb")):read("*a") end
for _, p in ipairs({ "UI/AuditPanel.lua", "UI/CalendarPanel.lua", "UI/CorePanel.lua", "UI/FeaturePanels.lua", "UI/PointsPanel.lua",
  "UI/RaiderPanel.lua", "UI/LootWindow.lua", "UI/ProfessionsPanel.lua", "UI/RecipesPanel.lua", "UI/GuildBankPanel.lua",
  "UI/CraftOrdersPanel.lua", "UI/Kit.lua" }) do
  local src = read(p)
  check(not src:find("local PAPER_CLASS", 1, true), p .. " has no class ink table of its own")
  check(not src:find("* 0.6, g * 0.6", 1, true) and not src:find("qc.r * 0.7", 1, true), p .. " does not darken a colour by a guess")
end
-- The Ledger and the Cleanup take the mapping for a member, a verb, a verdict and an item.
local bank = read("UI/GuildBankPanel.lua")
check(bank:find("classColor(e.n, row)", 1, true) and bank:find("qualityColor(info.quality, row)", 1, true), "the Ledger's who and item take the paper's inks")
check(select(2, bank:gsub("UI:Ink%(row, C%[v%[2%]%]", "")) == 2, "the Ledger's verb and the Cleanup's verdict take the paper's status inks")
check(bank:find("UI.QUALITY_INK[q or 1]", 1, true), "an item's quality on the paper is the shared quality ink")

print(("paper-ink: %d checks passed"):format(checks))
