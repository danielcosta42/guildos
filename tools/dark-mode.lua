-- Dark mode (Settings > Interface, GuildOSDB.darkMode), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Core/Data.lua, Core/Style.lua, UI/Helpers.lua, UI/Kit.lua and the screens whose own paper shades
-- were literals: "nothing changes but the white". Checks that
--   * both papers read: the inks (paperInk, paperSoft, paperTitle, paperLink, quietInk) at 4.5:1 or better on the
--     paper and on its light field, the lines visible (1.5:1) on the dark one;
--   * the switch writes every paper token, in place, and nothing else (the wood, the gold, the legacy keys);
--   * the paper's inks (statuses, classes, qualities, PaperRGB) and every screen's own shade follow it, and come
--     back exactly on the way back;
--   * Style:Resolve reads GuildOSDB.darkMode before anything is drawn, and the screens no longer carry the light
--     literals that would have stayed cream.
--
--   luajit -e 'ADDON="."' tools/dark-mode.lua
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

-- The screens whose paper shades were literals (each registers its shades at load).
for _, f in ipairs({ "UI/Salao.lua", "UI/CalendarPanel.lua", "UI/CommunityPanel.lua", "UI/PointsPanel.lua",
  "UI/RaiderPanel.lua", "UI/CraftOrdersPanel.lua", "UI/RecipesPanel.lua", "UI/ModAlerts.lua" }) do
  local ok, err = pcall(dofile, ADDON .. "/" .. f)
  check(ok, f .. " loads: " .. tostring(err))
end
check(#GuildOS.PaperShades >= 15, ("the screens' paper shades are registered (%d)"):format(#GuildOS.PaperShades))

local function hx(c) return string.format("%02x%02x%02x", c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5) end
local function snap(c) return { r = c.r, g = c.g, b = c.b, a = c.a } end
local function same(a, b) return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a end

local PAPER = {}
for _, k in ipairs(GuildOS.PAPER_KEYS) do PAPER[k] = true; check(C[k] and C[k].r, "C." .. k .. " is a colour") end

-- ── Light mode is the parchment as it was ───────────────────────────────
check(not GuildOS:IsDarkPaper(), "the paper is light by default")
local LIGHT = { paper = "f3e4c2", paperInk = "3a2a17", paperSoft = "6f5a3c", paperLine = "dcc79c", paperRule = "c9b48a",
  paperTitle = "6b1d0e", paperEdge = "b49867", paperLight = "fffaf0", paperLink = "8a5a20", quiet = "fff6de",
  quietInk = "5a3b17", paperBox = "efe0bd", paperShade = "e0cc9f", paperOff = "d5c6a6", paperMark = "6f5a3c",
  paperMarkTitle = "6b1d0e" }
for k, h in pairs(LIGHT) do check(hx(C[k]) == h, ("light C.%s is #%s (%s)"):format(k, h, hx(C[k]))) end
check(C.paperOffInk.r == 0.45 and C.paperOffInk.g == 0.40 and C.paperOffInk.b == 0.33, "the light disabled ink is as it was")
check(UI.DISABLED_INK.paper == C.paperOffInk, "the disabled ink on the paper is the token")

-- WCAG contrast of the paper's inks and lines, for whichever paper is on.
local INKS = { "paperInk", "paperSoft", "paperTitle", "paperLink", "quietInk" }
local function readsOn(what, c, grounds)
  for _, g in ipairs(grounds) do
    local ratio = UI.Contrast(c, C[g])
    check(ratio >= 4.5, ("%s reads at %.2f:1 on C.%s, under 4.5:1"):format(what, ratio, g))
  end
end
local function palette(name, lines)
  for _, k in ipairs(INKS) do readsOn(name .. " C." .. k, C[k], { "paper", "paperLight", "paperBox" }) end
  readsOn(name .. " the quiet button's ink", C.quietInk, { "quiet" })
  -- A step's pill at rest: the light one read at 4.15:1, kept; the dark one does no worse than 4:1.
  check(UI.Contrast(C.paperSoft, C.paperShade) >= 4, name .. " the soft ink reads on a step's pill")
  readsOn(name .. " a selected chip's label", C.quiet, { "paperTitle" })
  for _, w in ipairs({ "paperMark", "paperMarkTitle" }) do readsOn(name .. " a glyph's white letter", C.white, { w }) end
  for k, c in pairs(UI.STATUS_INK) do readsOn(name .. " the status ink " .. k, c, { "paper", "paperLight" }) end
  for k, c in pairs(UI.CLASS_INK) do readsOn(name .. " the class ink " .. k, c, { "paper", "paperLight" }) end
  for q, c in pairs(UI.QUALITY_INK) do readsOn(name .. " the quality ink " .. q, c, { "paper", "paperLight" }) end
  for _, k in ipairs({ "text", "textSoft", "label", "labelDim", "ok", "warn", "danger", "info", "epic", "gold", "gold2", "white" }) do
    local r, g, b = UI.PaperRGB(C[k].r, C[k].g, C[k].b)
    readsOn(name .. " C." .. k .. " as the paper prints it", { r = r, g = g, b = b }, { "paper", "paperLight" })
  end
  for file, c in pairs(GuildOS.ClassColors) do
    local r, g, b = UI:InkFor("paper", "class", file)
    readsOn(name .. " a " .. file .. " on the paper", { r = r, g = g, b = b }, { "paper", "paperLight" })
  end
  if lines then
    for _, k in ipairs({ "paperLine", "paperRule" }) do
      local ratio = UI.Contrast(C[k], C.paper)
      check(ratio >= 1.5, ("%s C.%s shows at %.2f:1 on the paper, under 1.5:1"):format(name, k, ratio))
    end
    for _, g in ipairs({ "paperLight", "quiet" }) do
      local ratio = UI.Contrast(C.paperEdge, C[g])
      check(ratio >= 1.5, ("%s the field's and the quiet button's edge shows at %.2f:1 on C.%s"):format(name, ratio, g))
      ratio = UI.Contrast(C.paperRule, C[g])
      check(ratio >= 1.5, ("%s C.paperRule shows at %.2f:1 on C.%s"):format(name, ratio, g))
    end
    local ratio = UI.Contrast(C.paperOffInk, C.paperOff)
    check(ratio >= 3, ("%s a disabled label reads at %.2f:1 on its fill (about 60%% of the paper's)"):format(name, ratio))
  end
end
palette("light:", false)
-- The light paper's rule shows at 1.5:1 (its line, a fill more than a line, stays the 1.3:1 it was: nothing changes).
check(UI.Contrast(C.paperRule, C.paper) >= 1.5, "the light rule shows on the paper")

-- Every colour in the palette now, by key, and every table by identity.
local before, ids = {}, {}
for k, c in pairs(C) do if type(c) == "table" and c.r then before[k] = snap(c); ids[k] = c end end
local inkIds = { s = {}, k = {}, q = {} }
for k, c in pairs(UI.STATUS_INK) do inkIds.s[k] = c end
for k, c in pairs(UI.CLASS_INK) do inkIds.k[k] = c end
for k, c in pairs(UI.QUALITY_INK) do inkIds.q[k] = c end
local shadesBefore = {}
for i, s in ipairs(GuildOS.PaperShades) do shadesBefore[i] = snap(s.c) end
local inksBefore = {}
for k, c in pairs(UI.STATUS_INK) do inksBefore["s" .. k] = snap(c) end
for k, c in pairs(UI.CLASS_INK) do inksBefore["k" .. k] = snap(c) end
for k, c in pairs(UI.QUALITY_INK) do inksBefore["q" .. k] = snap(c) end
local swapBefore = { UI.PaperRGB(C.ok.r, C.ok.g, C.ok.b) }

-- ── Dark mode: through Style:Resolve, as at ADDON_LOADED ─────────────────
check(not GuildOS.Style:WantsDarkMode(), "dark mode is off by default")
GuildOS.Style:SetDarkMode(true)
check(GuildOSDB.darkMode == true and GuildOS.Style:WantsDarkMode(), "the choice is saved at the account's root")
check(not GuildOS:IsDarkPaper(), "saving the choice does not repaint: it waits for the reload")
GuildOS.Style:Resolve()
check(GuildOS:IsDarkPaper() and GuildOS.Style.darkMode == true, "Style:Resolve reads GuildOSDB.darkMode")

local DARK = GuildOS.PaperPalettes.dark
for k, c in pairs(C) do
  if type(c) == "table" and c.r then
    check(c == ids[k], "C." .. k .. " is the same table (switched in place)")
    if PAPER[k] then
      check(not same(c, before[k]), "dark mode changes C." .. k)
      check(hx(c) == hx(DARK[k]), ("dark C.%s is #%s"):format(k, hx(DARK[k])))
    elseif GuildOS.WoodPalettes.dark[k] then
      check(hx(c) == hx(GuildOS.WoodPalettes.dark[k]), ("dark C.%s is the ebony #%s"):format(k, hx(GuildOS.WoodPalettes.dark[k])))
    else
      check(same(c, before[k]), "dark mode leaves C." .. k .. " (the wood's, the gold's, a legacy key) alone")
    end
  end
end
for k, c in pairs(UI.STATUS_INK) do check(c == inkIds.s[k], "the status ink " .. k .. " is the same table") end
for k, c in pairs(UI.CLASS_INK) do check(c == inkIds.k[k], "the class ink " .. k .. " is the same table") end
for k, c in pairs(UI.QUALITY_INK) do check(c == inkIds.q[k], "the quality ink " .. k .. " is the same table") end
check(Kit.INK == UI.STATUS_INK and Kit.CLASS_INK == UI.CLASS_INK, "the kit holds the same ink tables")
check(hx(C.paper) == "3a2f22" and hx(C.paperInk) == "ecdcb8" and hx(C.paperTitle) == "f0b46a", "the dark paper is the suggested one")

palette("dark:", true)

-- The inks follow: the wood's statuses, the game's classes and qualities (lightened only where they would not read).
local function near(a, b) return math.abs(a.r - b.r) < 1e-9 and math.abs(a.g - b.g) < 1e-9 and math.abs(a.b - b.b) < 1e-9 end
check(near(UI.STATUS_INK.ok, C.ok), "on the dark paper ok is the wood's own green")
check(near(UI.STATUS_INK.warn, C.warn), "on the dark paper warn is the wood's own amber")
check(near(UI.CLASS_INK.MAGE, GuildOS.ClassColors.MAGE), "on the dark paper a mage reads in the game's own colour")
check(near(UI.CLASS_INK.ROGUE, GuildOS.ClassColors.ROGUE), "on the dark paper a rogue reads in the game's own yellow")
check(near(UI.QUALITY_INK[1], C.paperInk), "on the dark paper a common item is the paper's ink")
check(near(UI.QUALITY_INK[4], GuildOS.QualityColors[4]) or UI.QUALITY_INK[4].r > GuildOS.QualityColors[4].r,
  "on the dark paper an epic is the game's purple, lightened at most")
local r, g, b = UI.PaperRGB(C.ok.r, C.ok.g, C.ok.b)
check(r == UI.STATUS_INK.ok.r and g == UI.STATUS_INK.ok.g and b == UI.STATUS_INK.ok.b, "PaperRGB's table follows the paper")
check(r ~= swapBefore[1] or g ~= swapBefore[2], "PaperRGB gives the dark paper's ok, not the light one's")
r = UI.PaperSafe(0.1, 0.1, 0.1)
check(r > 0.1, "on the dark paper a dark colour is lightened until it reads")
local text = UI:PaperText("|cff1eff00[Linen]|r |cff2f6e33x|r", "paper")
for code in text:gmatch("|cff(%x%x%x%x%x%x)") do
  local c = { r = tonumber(code:sub(1, 2), 16) / 255, g = tonumber(code:sub(3, 4), 16) / 255, b = tonumber(code:sub(5, 6), 16) / 255 }
  readsOn("dark: a colour code in a string (" .. code .. ")", c, { "paper" })
end

-- Every screen's own shade: the dark one, or the wood's ink made to read.
for i, s in ipairs(GuildOS.PaperShades) do
  if s.wood then
    readsOn(("dark: screen ink #%d (light #%s)"):format(i, hx(s.light)), s.c, { "paper", "paperLight" })
    check(not same(s.c, shadesBefore[i]), ("dark: screen ink #%d changed"):format(i))
  else
    check(hx(s.c) == hx(s.dark), ("dark: screen shade #%d is #%s"):format(i, hx(s.dark)))
    -- (the kit's row wash under the cursor is the exception: a faint light on the dark paper)
    check(hx(s.light) == "9e7333" or UI.Luminance(s.c.r, s.c.g, s.c.b) < UI.Luminance(s.light.r, s.light.g, s.light.b),
      ("dark: screen shade #%d is darker than its light #%s"):format(i, hx(s.light)))
  end
end
-- A shade made after the switch (a screen built late) starts dark.
local late = GuildOS:PaperShade("efe0bd", "30261a")
check(hx(late) == "30261a", "a shade made in dark mode starts dark")
table.remove(GuildOS.PaperShades)

-- A metric chip on a parchment card: its box is the token, no cream left.
local card = CreateFrame("Frame"); card.__paper = true
local chip = UI:CreateMetricChip(card, "3", "x")
local filled = chip.fill and chip.fill.pieces and chip.fill.pieces.C
check(filled and filled.color and hx(filled.color) == hx(C.paperBox), "a metric chip's box on the paper is C.paperBox")
-- A glyph in the paper's inks keeps a deep fill under its white letter.
local gl = UI:CreateGlyph(card, 20)
gl:Set("A", C.paperTitle)
check(gl.orb.color and hx(gl.orb.color) == hx(C.paperMarkTitle), "a glyph in the title's colour fills with C.paperMarkTitle")
gl:Set("A", C.paperSoft)
check(hx(gl.orb.color) == hx(C.paperMark), "a glyph in the soft ink fills with C.paperMark")

-- ── And back: everything exactly as it was ───────────────────────────────
GuildOS:SetDarkPaper(false)
for k, c in pairs(C) do
  if type(c) == "table" and c.r then check(same(c, before[k]), "back to light, C." .. k .. " is as it was") end
end
for i, s in ipairs(GuildOS.PaperShades) do check(same(s.c, shadesBefore[i]), ("back to light, screen shade #%d is as it was"):format(i)) end
for k, c in pairs(UI.STATUS_INK) do check(same(c, inksBefore["s" .. k]), "back to light, the status ink " .. k) end
for k, c in pairs(UI.CLASS_INK) do check(same(c, inksBefore["k" .. k]), "back to light, the class ink " .. k) end
for k, c in pairs(UI.QUALITY_INK) do check(same(c, inksBefore["q" .. k]), "back to light, the quality ink " .. k) end
GuildOS.Style:SetDarkMode(false)
check(GuildOSDB.darkMode == nil, "off is not stored")
GuildOS.Style:Resolve()
check(not GuildOS:IsDarkPaper(), "Style:Resolve with the choice off keeps the light paper")

-- ── The screens carry no light literal that would stay cream ─────────────
local function read(f) local h = assert(io.open(ADDON .. "/" .. f, "rb")); local s = h:read("*a"); h:close(); return s end
local FORBIDDEN = {
  "0.937, 0.878, 0.741",                       -- the paper's box
  "0.878, 0.8, 0.624",                         -- a row's rule, a step's pill at rest
  "0.835, 0.776, 0.651",                       -- a disabled fill on the paper
  "r = 0.184, g = 0.431, b = 0.2 }",           -- the paper's ok ink (a badge's 0.200 fill stays)
  "0.184, 0.431, 0.2, 1.0",
  "r = 0.561, g = 0.106, b = 0.043", "r = 0.541, g = 0.353, b = 0", "r = 0.541, g = 0.416, b = 0.227",
  "|cff2f6e33", "|cff8f1b0b", "|cff6f5a3c", "|cff6b1d0e", "|cff2E7D32",
  'hex("efe0bd")', 'hex("d9c49a")', 'hex("f5e2b3")', 'hex("f6d6c9")', 'hex("ecd9a8")', 'hex("d6ecd0")',
  'hex("2f6e33")', 'hex("8f1b0b")', 'hex("a0560f")', 'hex("8a5a00")',
}
local SCREENS = { "UI/Helpers.lua", "UI/Kit.lua", "UI/Salao.lua", "UI/FeaturePanels.lua", "UI/AchievementsPanel.lua",
  "UI/JournalPanel.lua", "UI/CalendarPanel.lua", "UI/CommunityPanel.lua", "UI/RosterFrame.lua", "UI/RaidPlanPanel.lua",
  "UI/PointsPanel.lua", "UI/RaiderPanel.lua", "UI/GuildBankPanel.lua", "UI/CraftOrdersPanel.lua",
  "UI/ProfessionsPanel.lua", "UI/RecipesPanel.lua", "UI/ModAlerts.lua" }
-- A badge's deep fill under its white label is a fill, not an ink: it reads on either paper.
-- The Hall's urgent square and a "not going" note's outline are such fills too.
local ALLOW = { ["UI/Helpers.lua"] = { ["r = 0.561, g = 0.106, b = 0.043"] = true },
  ["UI/Salao.lua"] = { ['hex("8f1b0b")'] = true, ['hex("a0560f")'] = true } }
for _, f in ipairs(SCREENS) do
  local src = read(f)
  for _, lit in ipairs(FORBIDDEN) do
    check((ALLOW[f] and ALLOW[f][lit]) or not src:find(lit, 1, true), ("%s still draws the light literal %s"):format(f, lit))
  end
end
local ROUTED = {
  ["UI/Salao.lua"] = { "noticeBg:SetColor(C.paperBox)", "C.paperShade.r", 'GuildOS:PaperInk("8a6a3a", C.label)' },
  ["UI/Helpers.lua"] = { "fill:SetColor(C.paperBox)", "C.paperOff.r", "paper = C.paperOffInk" },
  ["UI/FeaturePanels.lua"] = { "C.paperBox.r" }, ["UI/AchievementsPanel.lua"] = { "fill:SetColor(C.paperBox)" },
  ["UI/JournalPanel.lua"] = { "card.fill:SetColor(C.paperBox)" }, ["UI/Kit.lua"] = { "color or C.paperShade" },
  ["UI/CalendarPanel.lua"] = { "ROLE_FILL   = C.paperBox" },
}
for f, needles in pairs(ROUTED) do
  local src = read(f)
  for _, n in ipairs(needles) do check(src:find(n, 1, true), ("%s draws through the token (%s)"):format(f, n)) end
end

-- ── The setting: Settings > Interface, found by the search ───────────────
local settings = read("UI/SettingsPanel.lua")
check(settings:find('F:Check(L["Dark mode"], L["Darker parchment cards, same wood and gold."]', 1, true), "Settings > Interface has Dark mode")
check(settings:find('markReload("dark"', 1, true), "switching dark mode asks for a reload")
local sp = settings:find('L["Dark mode"]', 1, true)
local ip = settings:find("PAGES.interface", 1, true) or settings:find("interface", 1, true)
check(sp and ip and sp > ip, "the check is on the Interface page")
local okS, errS = pcall(dofile, ADDON .. "/Modules/Search.lua")
check(okS, "Modules/Search.lua loads: " .. tostring(errS))
local found
for _, s in ipairs(GuildOS.Search.SETTINGS_SECTIONS) do
  if s.label == "Dark mode" then found = s end
end
check(found and found.sub == "interface", "the search finds Dark mode in Settings > Interface")
for _, w in ipairs({ "dark", "theme", "night" }) do
  check(found.words:find(w, 1, true), "the search finds dark mode by \"" .. w .. "\"")
end

-- Ebony: the boards and the title bar take GuildOS.EBONY in dark mode; other art keeps its colours.
do
  local f = { CreateTexture = function()
    local t = { vc = nil }
    function t:SetTexture() end
    function t:SetHorizTile() end
    function t:SetVertTile() end
    function t:SetVertexColor(r, g, b, a) self.vc = { r, g, b, a } end
    return t
  end }
  GuildOS:SetDarkPaper(true)
  local w = GuildOS.Style:Texture(f, "wood", "BACKGROUND", 0, true)
  local tb = GuildOS.Style:Texture(f, "titlebar", "BACKGROUND")
  local ring = GuildOS.Style:Texture(f, "ring", "ARTWORK")
  check(w.vc and math.abs(w.vc[1] - GuildOS.EBONY.r) < 1e-6, "dark mode: the wood is ebony")
  check(tb.vc ~= nil, "dark mode: the title bar is ebony")
  check(ring.vc == nil, "dark mode: other art keeps its colours")
  GuildOS:SetDarkPaper(false)
  local w2 = GuildOS.Style:Texture(f, "wood", "BACKGROUND", 0, true)
  check(w2.vc == nil, "light mode: the wood keeps its own colour")
  check(hx(C.bg) == hx(GuildOS.WoodPalettes.light.bg), "light mode: the wood's tokens come back")
end

print(("dark-mode: %d checks passed"):format(checks))
