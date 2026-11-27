-- Interface styles (issue #122, spec docs/superpowers/specs/2026-10-07-ui-styles-design.md §4), run
-- against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Core/Style.lua,
-- UI/Helpers.lua and Core/Commands.lua under a stubbed client.
--
-- One look since the Salão (#445), and since its phase 3 (#449) drawn from the addon's own art
-- (Media/Salao) on every client: no atlas of the WoW: Forever client paints it any more. Nothing to
-- choose, a saved style from before ignored; the palette, the fonts, every role and every control the
-- same with the client's atlases or without them.
--
--   luajit -e 'ADDON="."' tools/style.lua
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

-- The atlas elements the Forever client draws with its -c60 art (build 1.60.1.70245); " *" marks the
-- ones TBC Anniversary does not have.
local ATLAS, ONLY = {}, {}
for line in io.lines(ADDON .. "/tools/data/forever-atlas-elements.txt") do
  if line ~= "" and not line:find("^#") then
    local name, mark = line:match("^(.-)( %*)$")
    name = (name or line):lower()
    ATLAS[name], ONLY[name] = true, mark ~= nil
  end
end
local SIZES = {}   -- the sizes the tests rely on, from the same table
SIZES["ui-frame-metal-cornertopleft"] = { 190, 190 }
SIZES["128-redbutton-left"], SIZES["128-redbutton-right"] = { 114, 128 }, { 292, 128 }

-- ── A client: frames and textures that remember what was done to them ────
local function newRegion(kind, parent)
  local r = { kind = kind, parent = parent, children = {}, points = {}, scripts = {}, w = 0, h = 0, shown = true }
  if parent then parent.children[#parent.children + 1] = r end
  return setmetatable(r, { __index = function(_, k)
    if k:match("^[a-z_]") then return nil end   -- a field nobody set is nil; only methods answer
    return function(self, ...)
      local a = { ... }
      if k == "SetAtlas" then self.atlas = a[1]
      elseif k == "SetHorizTile" then self.horizTile = a[1]
      elseif k == "SetVertTile" then self.vertTile = a[1]
      elseif k == "SetTexture" then self.texture = a[1]
      elseif k == "SetVertexColor" or k == "SetTextColor" or k == "SetColorTexture" then self.color = a
      elseif k == "SetBackdrop" then   -- the client's ApplyBackdrop paints the pieces white again
        self.backdrop, self.backdropInfo, self.bg, self.border = a[1], a[1], { 1, 1, 1, 1 }, { 1, 1, 1, 1 }
      elseif k == "SetBackdropColor" then self.bg = a
      elseif k == "SetBackdropBorderColor" then self.border = a
      elseif k == "GetBackdropColor" then if self.bg then return unpack(self.bg) end
      elseif k == "GetBackdropBorderColor" then if self.border then return unpack(self.border) end
      elseif k == "GetEffectiveScale" then
        return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
      elseif k == "SetSize" then self.w, self.h = a[1], a[2]
      elseif k == "SetWidth" then self.w = a[1]
      elseif k == "SetHeight" then self.h = a[1]
      elseif k == "GetWidth" then return self.w
      elseif k == "GetHeight" then return self.h
      elseif k == "SetPoint" then self.points[#self.points + 1] = a
      elseif k == "ClearAllPoints" then self.points = {}
      elseif k == "Show" then self.shown = true
      elseif k == "Hide" then self.shown = false
      elseif k == "SetShown" then self.shown = a[1] and true or false
      elseif k == "IsShown" then return self.shown
      elseif k == "SetText" then self.text = a[1]
      elseif k == "GetText" then return self.text
      elseif k == "SetFont" then self.font = a[1]; return true
      elseif k == "GetStringWidth" then return #(self.text or "") * 6
      elseif k == "SetScript" then self.scripts[a[1]] = a[2]
      elseif k == "HookScript" then
        local prev = self.scripts[a[1]]
        self.scripts[a[1]] = prev and function(...) prev(...); a[2](...) end or a[2]
      elseif k == "GetScript" then return self.scripts[a[1]]
      elseif k == "CreateTexture" or k == "CreateFontString" then
        local t = newRegion(k, self); t.layer = a[2]; return t
      elseif k == "IsEnabled" then return self.enabled ~= false
      elseif k == "Enable" then self.enabled = true
      elseif k == "Disable" then self.enabled = false
      elseif k == "IsMouseOver" then return false
      elseif k == "GetFrameLevel" then return 1
      elseif k == "GetChecked" then return self.checked
      elseif k == "SetChecked" then self.checked = a[1]
      end
    end
  end })
end

local printed, errors, popups = {}, {}, {}
local function load(opts)
  opts = opts or {}
  printed, errors, popups = {}, {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  function CreateFrame(kind, _, parent)
    local f = newRegion(kind, parent)
    if kind == "ScrollFrame" then   -- UIPanelScrollFrameTemplate's scroll bar and its children
      local bar = newRegion("Slider", f)
      bar.ScrollUpButton, bar.ScrollDownButton = newRegion("Button", bar), newRegion("Button", bar)
      bar.ThumbTexture = newRegion("Texture", bar)
      bar.GetMinMaxValues = function() return 0, 0 end
      bar.GetValue = function() return 0 end
      f.ScrollBar = bar
    end
    return f
  end
  UIParent = newRegion("Frame")
  function hooksecurefunc() end
  function GetBuildInfo() return "1.60.1", "70235", "", 16001 end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  function GetLocale() return "enUS" end
  function GetRealmName() return "Realm" end
  function UnitName() return "Ana" end
  function GetServerTime() return 1790000000 end
  function GetTime() return 1 end
  function IsInGuild() return true end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  UISpecialFrames, SlashCmdList = {}, {}
  function ReloadUI()
    popups.reloaded = true
    popups.wizardUp = GuildOS.onboardingFrame and GuildOS.onboardingFrame.shown
  end
  local without = opts.without or {}
  C_Texture = opts.noArt and {} or { GetAtlasInfo = function(name)
    name = tostring(name):lower()
    if not ATLAS[name] or without[name] then return nil end
    local s = SIZES[name] or { 32, 32 }
    -- "_" pieces tile across and "!" pieces tile down, as the client's atlas flags say.
    return { width = s[1], height = s[2], tilesHorizontally = name:sub(1, 1) == "_",
             tilesVertically = name:sub(1, 1) == "!" }
  end }
  GuildOSDB = opts.db or {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Style.lua")
  GuildOS.RecordError = function(_, msg) errors[#errors + 1] = msg end
  GuildOS.db = { settings = {} }
  dofile(ADDON .. "/UI/Spacing.lua")
  dofile(ADDON .. "/UI/Helpers.lua")
  function GuildOS:ShowDialog(which, text) popups[#popups + 1] = { which = which, text = text } end
  dofile(ADDON .. "/UI/StylePreview.lua")
  return GuildOS.Style
end
local function said(fragment)
  for _, m in ipairs(printed) do if m:find(fragment, 1, true) then return true end end
end

-- ── 1. The art is the addon's own, on every client (#449) ──────────────
local S = load()
local names = {}
for name, path in pairs(S.ART) do
  names[#names + 1] = name
  check(path == "Interface\\AddOns\\GuildOS\\Media\\Salao\\" .. name .. ".tga", name .. " is a file of Media/Salao")
end
check(#names >= 20, "the look names its textures (" .. #names .. ")")
for _, k in ipairs({ "FOREVER", "KEY_ATLASES", "_PaintNine", "_PaintThree", "SkinButton", "SkinTab", "SkinClose" }) do
  check(S[k] == nil, "the Forever atlas painter is gone: no " .. k)
end

-- ── 2. One look, whatever the client has (#445, #449) ──────────────────
for _, opts in ipairs({ { noArt = true }, {} }) do
  S = load(opts)
  local where = opts.noArt and " (Anniversary, no atlases)" or " (Forever, its atlases)"
  check(S:Has("salao") and not S:Has("forever") and not S:Has("guildos"), "one look" .. where)
  check(#S:Available() == 1 and S:Available()[1] == "salao", "and nothing to choose" .. where)
end

-- ── 3. Nothing to choose ───────────────────────────────────────────────
S = load()
local ok, why = S:Choose("neon")
check(not ok and why == "unknown" and GuildOSDB.style == nil, "an unknown style is refused, and nothing is saved")
ok, why = S:Choose("salao")
check(not ok and why == "one" and GuildOSDB.style == nil, "the one look is refused too: there is nothing to pick")
S:Apply("salao")
check(said("one look"), "/gos style says so")

-- ── 4. Resolving at load ───────────────────────────────────────────────
for _, saved in ipairs({ "guildos", "forever" }) do
  S = load({ db = { style = saved } })
  check(S:Resolve() == "salao" and S:Current() == "salao" and #printed == 0,
    "a saved " .. saved .. " style from before is ignored, silently")
end

-- ── 5. The palette and the fonts, on every client ──────────────────────
for _, opts in ipairs({ { db = {}, noArt = true }, { db = {} } }) do
  S = load(opts)
  local C = GuildOS.Colors
  local GOLD = C.gold
  S:Resolve()
  local where = opts.noArt and " (no atlases)" or " (atlases)"
  check(GOLD.r == 1 and math.abs(GOLD.g - 0xd1 / 255) < 1e-9 and C.gold == GOLD, "the game's yellow" .. where)
  check(math.abs(C.paper.r - 0xf3 / 255) < 1e-9 and math.abs(C.lineHi.r - 0x6b / 255) < 1e-9, "the paper and the metal" .. where)
  local fs = newRegion("FontString")
  GuildOS:ApplyFont(fs, 12)
  check(not S.gameFont and fs.font == GuildOS.Fonts.ui, "every text takes the addon's own font, not the game's" .. where)
end

-- ── 6. Painting by role ────────────────────────────────────────────────
local function pieces(box) local n = 0; for _ in pairs(box.pieces) do n = n + 1 end; return n end
local function art(t) return t and tostring(t.texture or ""):match("Salao\\(.-)%.tga$") end
for _, opts in ipairs({ { db = {}, noArt = true }, { db = { style = "forever" } } }) do
  S = load(opts); S:Resolve()
  local C = GuildOS.Colors
  local where = opts.noArt and " (no atlases)" or " (atlases)"
  local f = newRegion("Frame")
  check(S:Paint(f, "window") == "art" and f.__look and f.__look.fill and art(f.__look.fill.pieces.TL) == "card"
    and f.__look.fill.color[1] == C.bg.r and f.__look.line.color[1] == C.lineHi.r and f.__edge3 == 3,
    "a window: the metal frame, 3px, around the window's colour" .. where)
  for _, c in ipairs(f.children) do check(c.atlas == nil, "the window uses no atlas" .. where) end
  f = newRegion("Frame")
  S:Paint(f, "panel")
  check(pieces(f.__look.fill) == 9 and math.abs(f.__look.fill.color[4] - 0.55) < 1e-9 and f.__look.line.color[1] == C.lineHi.r,
    "a panel: the dark card in nine pieces, see-through, the metal's line" .. where)
  f = newRegion("Frame")
  S:Paint(f, "paper")
  check(f.__paper and f.__look.fill.color[1] == C.paper.r and f.__grain and art(f.__grain) == "grain" and f.__grain.horizTile,
    "parchment: the paper and its grain, tiled" .. where)
  f = newRegion("Frame")
  S:Paint(f, "well")
  check(f.__look.fill.color[1] == C.well.r, "a well: the field's colour" .. where)
  f = newRegion("Frame")
  check(S:Paint(f, "popup") == "art" and f.border and f.border[1] == C.metal2.r, "a popup: the bright metal's border on its own colour" .. where)
  f = newRegion("Frame")
  S:Paint(f, "titlebar")
  check(f.__styleBg and art(f.__styleBg) == "titlebar", "a title bar: its warm gradient" .. where)
  f = newRegion("Frame")
  local wood = S:PaintWood(f)
  check(art(wood.wood) == "wood" and wood.wood.horizTile and wood.wood.vertTile and art(wood.glow) == "glow"
    and not wood.snow.shown, "the wood: tiled boards and the fire's glow" .. where)
  wood:SetWinter(true)
  check(wood.snow.shown, "with snow in Winter Veil" .. where)
end

-- A nine-piece box: corners of its size, the middle stretched between them; the door's open at the bottom.
S = load(); S:Resolve()
local f = newRegion("Frame")
local box = S:Nine(f, "card", 6, "BACKGROUND", 1)
check(box.pieces.TL.w == 6 and box.pieces.TL.h == 6 and box.pieces.BR.points[1][1] == "BOTTOMRIGHT"
  and box.pieces.C.points[1][2] == box.pieces.TL, "a box: 6px corners, the middle between them")
local door = S:Nine(f, "card", 6, "BACKGROUND", 1, nil, "bottom")
check(not door.pieces.BL.shown and not door.pieces.B.shown and door.pieces.L.points[2][1] == "BOTTOMLEFT",
  "a door's box is open at the bottom")
door:SetShown(true)
check(not door.pieces.BL.shown, "and stays open when shown again")
local bar = newRegion("Frame"); bar.w, bar.h = 40, 24
local three = S:Three(bar, "pill", "BACKGROUND", 1)
check(three.pieces.L.w == 12 and three.pieces.R.w == 12, "a pill's caps are half its height")
bar.w = 16; bar.scripts.OnSizeChanged(bar)
check(three.pieces.L.w == 8, "squeezed when the pill is narrower than both caps")

-- ── 7. The controls, through the real Helpers ──────────────────────────
for _, opts in ipairs({ { db = {}, noArt = true }, { db = { style = "forever" } } }) do
  S = load(opts); S:Resolve()
  local UI, C = GuildOS.UI, GuildOS.Colors
  local where = opts.noArt and " (no atlases)" or " (atlases)"
  local b = UI:SetButtonVariant(UI:CreateButton(UIParent, "Go", 120, 26), "primary")
  check(b.__arts.button and b.__arts.button.shown and art(b.__arts.button.pieces.L) == "button"
    and b.__arts.button.color[1] == C.crimson.r, "the primary button is the crimson one of the Salão's art" .. where)
  UI:SetButtonVariant(b, "ghost")
  check(not b.__arts.button.shown and b.underline.shown, "switched to ghost it leaves the art for an underline" .. where)
  UI:SetButtonVariant(b, "primary")
  check(b.__arts.button.shown, "and takes it back as primary" .. where)
  local tab = UI:CreateTab(UIParent, "Roster", 100)
  tab:SetActive(true)
  check(tab.fill.shown and art(tab.fill.pieces.L) == "pill" and not tab.underline.shown, "an open tab is a pill" .. where)
  local close = UI:CreateCloseButton(UIParent)
  check(art(close.orb) == "orb" and close.x.shown, "the close button is the round crimson one" .. where)
  for _, c in ipairs(close.children) do check(c.atlas == nil, "no atlas on it" .. where) end
end

-- ── 7b. Initialize settles the look; no Settings picker (#445) ───────
S = load({ db = { style = "guildos" } })
GuildOS:Initialize()
check(S:Current() == "salao" and GuildOS.Colors.gold.r == 1, "Initialize settles the one look before anything is drawn")
local host = newRegion("Frame")
check(S:BuildPicker(host, 100) == 100 and #(host.children or {}) == 0, "and Settings draws no style picker")

-- ── 8. /gos style ──────────────────────────────────────────────────────
S = load({ db = {}, noArt = true }); S:Resolve()
dofile(ADDON .. "/Core/Commands.lua")
SlashCmdList.GUILDOS("style")
check(said("salao - Salão (in use)"), "/gos style lists the one look")
SlashCmdList.GUILDOS("style forever")
check(GuildOSDB.style == nil and not popups[1] and said("one look"), "/gos style forever saves nothing and says there is one look")
SlashCmdList.GUILDOS("style neon")
check(said("Unknown style: neon"), "an unknown style says which exists")

-- ── 9. /gos style preview ──────────────────────────────────────────────
S = load({ db = {}, noArt = true }); S:Resolve()
local rows = S:PreviewRows()
local seen = {}
for _, r in ipairs(rows) do seen[r.role] = r.file end
check(seen.wood and seen.card and seen.pill and seen.orb and #rows == #names, "the preview lists every texture of the look")
S:ShowPreview()
check(S.previewFrame and S.previewFrame.shown, "/gos style preview opens it")

-- ── 10. A line is never under a screen pixel (issue #369) ──────────────
-- The client's rounding, as SharedXML/PixelUtil.lua does it: whole pixels, never under `min`.
local physH = 1080
PixelUtil = { GetNearestPixelSize = function(units, scale, min)
  local factor = 768 / physH
  local n = math.floor(units * scale / factor + 0.5)
  if min and n < min then n = min end
  return n * factor / scale
end }
local function pixels(units, region) return units * region:GetEffectiveScale() * physH / 768 end
local function near(a, b) return math.abs(a - b) < 1e-9 end

S = load({ db = {}, noArt = true }); S:Resolve()
local UI = GuildOS.UI
UIParent.scale = 0.64                    -- 1080p at the smallest UI scale: 1 unit is 0.91 px
local win = UI:CreatePanel(UIParent)
win.scale = 0.9                          -- the window's own scale slider
local box = UI:CreatePanel(win)
local rule = UI:CreateSeparator(box)
check(near(pixels(rule.h, box), 1), "a separator is one screen pixel, not 0.82 of one")
-- A checkbox's border is a texture hung outside the box: one screen pixel out on every side.
local cbBorder = UI:CreateCheckbox(box, "Don't name me").checkbox.children[1]
local function outset(t)
  local tl, br
  for _, p in ipairs(t.points) do
    if p[1] == "TOPLEFT" then tl = p elseif p[1] == "BOTTOMRIGHT" then br = p end
  end
  return tl and br and -tl[2], br and br[2]
end
local l, r = outset(cbBorder)
check(l and near(pixels(l, box), 1) and near(pixels(r, box), 1),
  "a checkbox's border sticks out one screen pixel on the right and bottom too, not 0.82")

physH, UIParent.scale = 2160, 1          -- moved to a 4K screen: 1 unit is now 2.5 px
UI:RefreshHairlines()
check(near(pixels(rule.h, box), 3), "after a scale change every line is resized to whole pixels")
l, r = outset(cbBorder)
check(near(pixels(l, box), 3) and near(pixels(r, box), 3), "and the checkbox's border moves with them")
PixelUtil = nil
check(UI:Px(box) == 1, "a client without PixelUtil keeps 1 unit")

local files, literal = {}, {}
local p = io.popen('git -C "' .. ADDON .. '" ls-files "*.lua"')
for line in p:lines() do if not line:find("^tools/") then files[#files + 1] = line end end
p:close()
for _, rel in ipairs(files) do
  local fh = io.open(ADDON .. "/" .. rel, "rb")
  local n = 0
  for line in fh:lines() do
    n = n + 1
    if line:find("edgeSize%s*=%s*1[^%d.]") or line:find("edgeSize%s*=%s*1$") then literal[#literal + 1] = rel .. ":" .. n end
  end
  fh:close()
end
check(#files > 100 and #literal == 0,
  "no border is a literal 1 unit (use GuildOS.UI:Edge): " .. table.concat(literal, ", "))

-- ── 11. One of each screen part (issue #371) ───────────────────────────
S = load({ db = {}, noArt = true }); S:Resolve()
UI = GuildOS.UI
local C = GuildOS.Colors
local function same(col, c) return col and math.abs(col[1] - c.r) < 1e-6 and math.abs(col[2] - c.g) < 1e-6 end
local host = UI:CreatePanel(UIParent)

-- A field: the metal's line, the soft gold while typing, a hint while empty.
local function line(f) return f.__look and f.__look.line and f.__look.line.color end
local field = UI:CreateInput(host, 120, 22, { placeholder = "Search" })
check(field.kind == "EditBox" and same(line(field), C.lineHi), "a field is an edit box with the metal's line")
check(field.placeholder and field.placeholder.shown and field.placeholder.text == "Search", "an empty field shows its hint")
field.scripts.OnEditFocusGained(field)
check(same(line(field), C.gold2), "it turns the soft gold while typing")
field.scripts.OnEditFocusLost(field)
check(same(line(field), C.lineHi), "and back when it lets go")
field:SetText("ana"); field.scripts.OnTextChanged(field)
check(not field.placeholder.shown, "the hint goes once there is text")

-- A multi-line field keeps the height it was given: a multi-line EditBox alone takes its text's height,
-- one line when empty, so the box is a frame of that size with the EditBox inside it.
local area = UI:CreateTextArea(host, 300, 56, { placeholder = "Options" })
check(area.h == 56 and area.edit and area.edit.kind == "EditBox" and area.edit.parent == area
  and same(line(area), C.lineHi), "a text area is a 56px framed box with its EditBox inside")
area.edit.scripts.OnEditFocusGained(area.edit)
check(same(line(area), C.gold2), "and its frame turns the soft gold while typing")

-- A dropdown's list has its own surface: popup fill under a lineHi border, not options over whatever is
-- behind them (#371, seen in Loot > Rule).
local dd = UI:CreateDropdown(host, 150, 22)
dd:SetOptions({ { value = 1, text = "Rare" }, { value = 2, text = "Epic" } })
dd:Open()
local list
for _, c in ipairs(UIParent.children) do if rawget(c, "catcher") then list = c end end
check(list and list.__menuPainted and list.__look and list.__look.fill and list.__look.line,
  "an open dropdown's list is the mockup's menu: a rounded dark panel with the bright metal's line (#449)")
check(dd.variant == "field", "the closed select is drawn as a field, like the text input beside it")

-- Selection: the soft gold's line and ink, kept under the cursor, gone when unselected.
local function edge(b) return b.__arts["button-line"].color end
local opt = UI:CreateButton(host, "All", 60, 22)
UI:SetSelected(opt, true)
check(same(edge(opt), C.gold2) and same(opt.label.color, C.gold2), "a selected button has the soft gold's line and label")
opt.scripts.OnEnter(opt)
check(same(edge(opt), C.gold2), "and keeps it under the cursor")
opt.scripts.OnLeave(opt)
UI:SetSelected(opt, false)
check(same(edge(opt), C.lineHi) and same(opt.label.color, C.darkInk), "unselected, it is the dark button again")
UI:SetSelected(opt, true); opt:Disable(); opt.scripts.OnLeave(opt)
UI:_ButtonState(opt, "disabled")
check(same(edge(opt), C.gold2) and same(opt.label.color, GuildOS.UI.DISABLED_INK.wood),
  "a selected button that cannot be clicked keeps the gold line, so the choice still shows")

-- Section titles: a rule above every one but the first; table headers: a rule under, no fill.
local t1 = UI:CreateSectionTitle(host, "Your raid roles", true)
local t2 = UI:CreateSectionTitle(host, "Notices")
check(t1.rule == nil and t2.rule ~= nil and t2.rule.h ~= nil, "a later section title has a rule above it, the first none")
check(same(t2.color, C.gold2) and t2.font == GuildOS.Fonts.title, "a section title is Cinzel in the soft gold")
local th = UI:CreateTableHeader(host)
check(th.h == UI.SP.HIT and th.rule and th.backdrop == nil and same(th.rule.color, C.lineHi),
  "a table header is UI.SP.HIT (24px) tall with the metal's rule and no fill")

-- Scrolling: no empty track when nothing scrolls.
local scroll = UI:CreateScrollFrame(host, "TestScroll")
local bar = scroll.ScrollBar
local track
for _, c in ipairs(bar.children) do if c.kind == "CreateTexture" and c.layer == "BACKGROUND" then track = c end end
bar.GetMinMaxValues = function() return 0, 0 end
bar.scripts.OnMinMaxChanged(bar)
check(track and not track.shown, "a scroll bar with nothing to scroll shows no track")
bar.GetMinMaxValues = function() return 0, 300 end
bar.scripts.OnMinMaxChanged(bar)
check(track.shown, "and shows it once there is something to scroll")
check(UI.SCROLL_GUTTER == 12, "content keeps 12px clear of the scroll bar")

-- On WoW: Forever a field is the same rounded field: no game art, a multi-line box too (#449).
S = load({ db = { style = "forever" } }); S:Resolve()
local fhost = GuildOS.UI:CreatePanel(UIParent)
local ffield = GuildOS.UI:CreateInput(fhost, 120, 22)
local atlases = 0
for _, c in ipairs(ffield.children) do if c.atlas then atlases = atlases + 1 end end
check(atlases == 0 and ffield.__look.fill and ffield.backdrop == nil, "a Forever field is the Salão's rounded field, no atlas")
local fbox = GuildOS.UI:CreateInput(fhost, 460, 250, { multiline = true })
check(fbox.__look.fill and fbox.backdrop == nil, "a multi-line box too")

-- ── 12. The onboarding has no style step (#445, specs/salao/onboarding.md) ──
-- One look: the welcome and What's new (UI/Onboarding.lua) never ask for a style, and never reload.
do
  local fh = assert(io.open(ADDON .. "/UI/Onboarding.lua", "rb"))
  local src = fh:read("*a")
  fh:close()
  check(not src:find("styleStep", 1, true) and not src:find("Style:Choose", 1, true) and not src:find("ReloadUI", 1, true),
    "the welcome has no style step and no reload")
end

print(("style: %d checks passed"):format(checks))
