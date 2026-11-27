-- The Salão's components (issue #13; phase 3, #449), run against the real Core/Data.lua, Core/Style.lua and
-- UI/Helpers.lua under a stub frame API that records what was painted.
--
-- The factories decide every state colour in code: rest, hover, pressed and
-- disabled, for the primary (crimson), secondary (dark, or quiet on the paper),
-- ghost, danger and chip buttons, the cards, the fields, the avatar, the
-- checkbox, the tab (a pill), the close button and the round tool, badges, the
-- scrollbar, the popup, the fade and the progress bar. This proves each state
-- lands on the mockup's token and size, that the
-- contracts older screens rely on still hold (a caller's button height, a
-- toggle's resting colour, a checkbox's onChanged), that no
-- button glows and that text is never outlined.
--
--   luajit -e 'ADDON="."' tools/forever-components.lua
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

-- ── Stub frame API that remembers what was painted ─────────────────────
local function region()
  local r = { shown = true, points = {} }
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:SetAllPoints() end
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:GetHeight() return self.h or 0 end
  function r:GetWidth() return self.w or 0 end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:SetShown(v) self.shown = v and true or false end
  function r:SetAlpha(a) self.alpha = a end
  return r
end

local function texture()
  local t = region()
  function t:SetTexture(path) self.file = path end
  function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
  function t:SetTexCoord(...) self.coords = { ... } end
  function t:SetBlendMode(mode) self.blend = mode end
  return t
end

local function fontString()
  local f = region()
  function f:SetFont(file, size, flags) self.font = { file = file, size = size, flags = flags }; return true end
  function f:SetShadowOffset(x, y) self.shadow = { x, y } end
  function f:SetTextColor(r, g, b) self.color = { r, g, b } end
  function f:SetText(t) self.text = t end
  function f:GetStringWidth() return #(self.text or "") * 6 end
  function f:SetJustifyH(j) self.justify = j end
  function f:SetWordWrap(v) self.wrap = v end
  return f
end

function CreateFrame(_, _, parent)
  local fr = region()
  fr.scripts, fr.enabled, fr.level, fr.textures, fr.parent = {}, true, 1, {}, parent
  function fr:GetParent() return self.parent end
  function fr:SetBackdrop(b) self.backdrop = b end
  function fr:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
  function fr:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
  function fr:CreateTexture(_, layer, _, sublevel)
    local t = texture()
    t.layer, t.sublevel = layer, sublevel
    self.textures[#self.textures + 1] = t
    return t
  end
  function fr:CreateFontString() return fontString() end
  function fr:SetScript(name, fn) self.scripts[name] = fn end
  function fr:HookScript(name, fn)
    local prev = self.scripts[name]
    self.scripts[name] = function(...) if prev then prev(...) end fn(...) end
  end
  function fr:Fire(name, ...) if self.scripts[name] then self.scripts[name](self, ...) end end
  function fr:IsEnabled() return self.enabled end
  function fr:Enable() self.enabled = true; self:Fire("OnEnable") end
  function fr:Disable() self.enabled = false; self:Fire("OnDisable") end
  function fr:IsMouseOver() return self.mouseOver end
  function fr:SetFrameLevel(l) self.level = l end
  function fr:GetFrameLevel() return self.level end
  function fr:EnableMouse() end
  function fr:SetChecked(v) self.checked = v end
  for _, name in ipairs({ "SetTextInsets", "SetTextColor", "SetJustifyH", "SetAutoFocus", "SetMultiLine", "SetNumeric",
                          "SetMaxLetters", "SetFont", "RegisterForClicks" }) do
    fr[name] = fr[name] or function() end
  end
  function fr:GetText() return self.text or "" end
  function fr:HasFocus() return false end
  function fr:GetChecked() return self.checked end
  return fr
end

local fades = {}
UIFrameFadeIn = function(frame, duration) fades[#fades + 1] = { frame = frame, duration = duration } end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GuildOS = {
  Dialogs = {},   -- Core/Core.lua's, which Core/Style.lua writes its reload question into (#315)
  Compat = { After = function() end },
  L = setmetatable({}, { __index = function(_, k) return k end }),
}
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
dofile(ADDON .. "/UI/Spacing.lua")
dofile(ADDON .. "/UI/Helpers.lua")
local UI, C, F = GuildOS.UI, GuildOS.Colors, GuildOS.Fonts

local EPS = 1e-6
local function near(a, b) return math.abs(a - b) < EPS end
local function same(rgb, token, alpha)
  return rgb and near(rgb[1], token.r) and near(rgb[2], token.g) and near(rgb[3], token.b)
    and (alpha == nil or near(rgb[4] or 1, alpha))
end

local parent = CreateFrame("Frame")

-- The art a button wears, by name, and its last tint: { r, g, b, a }.
local function art(btn, name) return btn.__arts and btn.__arts[name] end
local function tint(btn, name) local a = art(btn, name); return a and a.shown and a.color end
local function lit(rgb, token, k)
  return rgb and near(rgb[1], math.min(1, token.r * k)) and near(rgb[2], math.min(1, token.g * k))
    and near(rgb[3], math.min(1, token.b * k))
end

-- ── Secondary button, the default: the dark button on the wood ─────────
local b = UI:CreateButton(parent, "cancelar")
check(b.h == 26, "a button defaults to 26px")
check(UI:CreateButton(parent, "salvar", 80, 22).h == 22, "a caller's own button height is kept")
check(same(tint(b, "button"), C.darkButton, 1) and same(tint(b, "button-line"), C.lineHi, 1),
  "secondary at rest: the dark button, the metal's line")
check(art(b, "button").pieces.L.file:find("Media\\Salao\\button.tga", 1, true), "drawn from Media/Salao's button art")
check(same(b.label.color, C.darkInk), "secondary label is the dark button's ink")
check(b.label.font.file == F.uiBold and b.label.font.size == 12 and b.label.font.flags == "",
  "a button label is Alegreya Sans Bold 12 and not outlined")
b:Fire("OnEnter")
check(lit(tint(b, "button"), C.darkButton, 1.14) and same(tint(b, "button-line"), C.metal2, 1) and same(b.label.color, C.text),
  "secondary hover: lighter, the bright metal's line, the wood's ink")
b:Fire("OnMouseDown")
check(lit(tint(b, "button"), C.darkButton, 0.82), "secondary pressed: darker")
b:Fire("OnLeave")
check(same(tint(b, "button"), C.darkButton, 1) and same(tint(b, "button-line"), C.lineHi, 1), "leaving restores the resting state")

local up = UI:CreateButton(parent, "subir")
up:Fire("OnMouseDown")
up.mouseOver = false
up:Fire("OnMouseUp")
check(same(tint(up, "button"), C.darkButton, 1), "releasing away from the button returns it to rest")
up:Fire("OnMouseDown")
up.mouseOver = true
up:Fire("OnMouseUp")
check(same(tint(up, "button-line"), C.metal2, 1), "releasing over the button leaves it hovered, not pressed")

local toggle = UI:CreateButton(parent, "filtro")
toggle:Fire("OnEnter")
toggle:SetBaseColor(0.5, 0.5, 0.5, 1)
check(not near(tint(toggle, "button")[1], 0.5), "SetBaseColor does not paint over a hovered button")
toggle:Fire("OnLeave")
check(near(tint(toggle, "button")[1], 0.5) and near(tint(toggle, "button")[4], 1), "a toggle's resting colour appears once the hover ends")
toggle:SetBackdropColor(0.2, 0.3, 0.4, 1)
check(near(tint(toggle, "button")[2], 0.3), "the backdrop's colour call lands on the button's art")

b:Disable()
check(same(b.label.color, UI.DISABLED_INK.wood) and near(tint(b, "button")[4], 1), "disabled: a flat desaturated button with a readable label (#449)")
b:Fire("OnEnter")
check(same(b.label.color, UI.DISABLED_INK.wood), "hovering a disabled button does not light it")
b:Enable()
check(same(b.label.color, C.darkInk) and same(tint(b, "button-line"), C.lineHi, 1), "enabling repaints the resting state")

-- ── Primary: the crimson button ─────────────────────────────────────────
local p = UI:SetButtonVariant(UI:CreateButton(parent, "dar loot"), "primary")
check(same(tint(p, "button"), C.crimson, 1) and same(tint(p, "button-line"), C.crimsonLine, 1) and same(p.label.color, C.crimsonInk),
  "primary at rest: crimson, a gold line, yellow ink")
check(p.glow == nil, "primary has no glow")
check(p.label.font.file == F.uiBold and p.label.font.size == 12, "primary label is Alegreya Sans Bold 12")
local restPts = p.label.points
p:Fire("OnEnter")
check(lit(tint(p, "button"), C.crimson, 1.14), "primary hover: brighter")
p:Fire("OnMouseDown")
check(lit(tint(p, "button"), C.crimson, 0.82), "primary pressed: darker")
check(p.label.points == restPts and #restPts == 1 and restPts[1][1] == "CENTER" and restPts[1][3] == nil,
  "pressing a primary button leaves its label where it is")
p.mouseOver = true
p:Fire("OnMouseUp")
check(lit(tint(p, "button"), C.crimson, 1.14), "releasing a primary button over it: hover")
p:Fire("OnLeave")
check(same(tint(p, "button"), C.crimson, 1), "the cursor leaving a primary button: resting crimson")
p:Disable()
check(near(tint(p, "button")[4], 1) and not same(tint(p, "button"), C.crimson, 1) and same(p.label.color, UI.DISABLED_INK.wood),
  "disabled primary: no dim red bar, a flat desaturated button with a readable label (#449)")

-- ── Ghost, danger and chip ──────────────────────────────────────────────
local g = UI:SetButtonVariant(UI:CreateButton(parent, "ver histórico"), "ghost")
check(not tint(g, "button") and same(g.label.color, C.textSoft) and g.underline and g.underline.shown,
  "ghost: no box, the soft ink, underlined")
check(g.label.font.file == F.ui and g.label.font.size == 12, "a ghost label is a link, Alegreya Sans 12")
g:Fire("OnEnter")
check(same(g.label.color, C.text) and same(g.underline.color, C.text, 1), "ghost hover: the ink and its underline")
g:Disable()
check(same(g.label.color, UI.DISABLED_INK.wood) and not tint(g, "button"), "disabled ghost: disabled label, no box")
g:Enable()
local d = UI:SetButtonVariant(UI:CreateButton(parent, "expulsar"), "danger")
check(same(tint(d, "button-line"), C.danger, 1) and same(d.label.color, C.danger), "danger: a danger line and label")
d:Fire("OnEnter")
check(same(tint(d, "button-line"), C.danger, 1), "danger hover keeps its danger line")
d:Disable()
check(same(d.label.color, UI.DISABLED_INK.wood), "disabled danger: disabled label")
check(d.glow == nil, "no button glows")
UI:SetButtonVariant(g, "secondary")
check(not g.underline.shown and same(tint(g, "button-line"), C.lineHi, 1) and g.label.font.file == F.uiBold,
  "a ghost switched back to secondary loses its underline and takes the button's bold")
local chipB = UI:SetButtonVariant(UI:CreateButton(parent, "Todos", 60, 22), "chip")
check(same(tint(chipB, "pill"), C.popup, 1) and same(tint(chipB, "pill-line"), C.lineHi, 1) and same(chipB.label.color, C.door),
  "a chip: a dark pill with the metal's line")
UI:SetSelected(chipB, true)
check(same(tint(chipB, "pill"), C.gold2, 1) and same(chipB.label.color, C.onGold), "a chosen chip fills with the soft gold")
local sel = UI:SetSelected(UI:CreateButton(parent, "modo"), true)
check(same(tint(sel, "button-line"), C.gold2, 1) and same(sel.label.color, C.gold2), "a chosen button: the soft gold's line and ink")

-- ── On parchment: the quiet button, the light field, the dark red title ─
local paperCard = UI:CreateCard(parent, "Para você")
check(paperCard.__paper and UI:OnPaper(paperCard) and same(paperCard.title.color, C.paperTitle)
  and paperCard.title.font.file == F.title, "a card is parchment, its title Cinzel in the dark red")
check(same(paperCard.__look.fill.color, C.paper, 1), "the paper's colour")
local q = UI:CreateButton(paperCard, "Decidir")
check(same(tint(q, "button-soft"), C.quiet, 1) and same(tint(q, "button-line"), C.paperEdge, 1) and same(q.label.color, C.quietInk),
  "on the paper a button is the quiet cream one")
local field = UI:CreateInput(paperCard, 120, 22)
check(same(field.__look.fill.color, C.paperLight, 1) and same(field.__look.line.color, C.paperEdge, 1),
  "on the paper a field is light with a tan line")
field:Fire("OnEditFocusGained")
check(same(field.__look.line.color, C.paperTitle, 1), "typing on the paper, its line is the dark red")
local darkCard = UI:CreateCard(parent, "Perto da lareira", { dark = true, link = "Todos" })
check(not UI:OnPaper(darkCard) and same(darkCard.title.color, C.gold2) and darkCard.link and darkCard.link.underline.shown,
  "a dark card: the soft gold title, a link at its right")
local woodField = UI:CreateInput(parent, 120, 22)
check(same(woodField.__look.fill.color, C.well, 1) and same(woodField.__look.line.color, C.lineHi, 1),
  "on the wood a field is dark with the metal's line")
woodField:Fire("OnEditFocusGained")
check(same(woodField.__look.line.color, C.gold2, 1), "typing, its line is the soft gold")

-- ── Avatar, glyph, count ────────────────────────────────────────────────
local av = UI:CreateAvatar(parent, 40)
av:SetMember("Thrandor", "HUNTER")
local hc = GuildOS.ClassColors.HUNTER
check(av.letter.text == "T" and near(av.disc.color[1], hc.r + (1 - hc.r) * 0.3) and same(av.ring.color, C.gold2, 1)
  and av.halo and av.halo.shown, "an avatar: the class's disc, the initial, a soft gold ring, a glow")
av:SetMember("Brakk", "WARRIOR", true)
check(not av.halo.shown and same(av.ring.color, C.lineHi, 1), "away: grey, no glow, the metal's ring")
av:SetMember("\195\137lise", "MAGE")
check(av.letter.text == "\195\137", "the initial is a whole character")
av:SetCount(10)
check(av.letter.text == "+10" and av.dash.shown and not av.ring.shown, "the +n disc is dashed")
local count = UI:CreateCount(parent)
check(not count.shown, "a count of nothing is not drawn")
count:SetCount(4)
check(count.shown and count.text.text == "4" and same(count.fill.color, C.count, 1), "a red count")

-- ── Checkbox ────────────────────────────────────────────────────────────
local cbf = UI:CreateCheckbox(parent, "anotar o chat", 18)
local cb = cbf.checkbox
local cbBorder = cb.textures[1]
check(cb.w == 14 and cb.h == 14, "the checkbox box is 14px")
check(not cb.checkMark.shown and same(cbBorder.color, C.lineHi, 1), "unchecked at rest: no mark, the metal's border")
local cbFill = cb.textures[2]
check(same(cbFill.color, C.well, 1), "the checkbox box is well")
cb:Fire("OnMouseDown")
check(same(cbFill.color, C.popup, 1), "checkbox pressed: popup fill")
cb:Fire("OnMouseUp")
check(same(cbFill.color, C.well, 1), "checkbox released: well again")
cb:Fire("OnEnter")
check(same(cbBorder.color, C.label, 1), "checkbox hover: label border")
cb:Fire("OnLeave")
local seen
cb.onChanged = function(_, checked) seen = checked end
cb.checked = true
cb:Fire("OnClick")
check(seen == true, "a click reaches onChanged with the checked state")
check(cb.checkMark.shown and cb.checkMark.w == 8 and same(cb.checkMark.color, C.gold2, 1),
  "a click repaints: an 8px soft gold mark")
cb:SetChecked(false)
check(not cb.checkMark.shown, "SetChecked(false) hides the mark")
cb:Disable()
check(same(cbBorder.color, C.disabled, 1), "disabled: disabled border")

-- ── Badges: small filled pills ──────────────────────────────────────────
local function fill(badge) return badge.__look.fill.color end
local officer = UI:CreateBadge(parent, "oficial", C.gold)
check(same(fill(officer), C.paperSoft, 1) and near(officer.label.color[1], 1), "the officer badge is the plain brown: gold is not a badge colour")
local absent = UI:CreateBadge(parent, "falta", C.danger)
check(near(fill(absent)[1], 0.561) and near(fill(absent)[2], 0.106), "a danger badge: the deep red")
local trial = UI:CreateBadge(parent, "trial 8/10", C.ok)
check(near(fill(trial)[2], 0.431), "an ok badge: the deep green")
check(trial.label.font.file == F.uiBold and trial.label.font.size == 11, "badge text is Alegreya Sans Bold 11")
local legacyRed = UI:CreateBadge(parent, "falta", C.red)
check(near(fill(legacyRed)[1], 0.561), "a badge in the legacy red gets the deep red too")
officer:SetText("falta", C.danger)
check(near(fill(officer)[1], 0.561) and officer.label.text == "falta", "SetText with a colour repaints the badge")

-- ── Progress bar ────────────────────────────────────────────────────────
local goal = UI:CreateProgressBar(parent, 100)
check(goal.h == 8, "the progress bar is 8px")
check(same(goal.bg, C.well, 1) and same(goal.border, C.line, 1), "the progress track is well in a line frame")
goal:SetWidth(200)
goal:SetProgress(1)
check(goal.bar.w == 198, "the fill follows the bar's width after a resize (issue #33)")
goal:SetWidth(100)
goal:SetProgress(0.31)
check(same(goal.bar.color, C.textSoft, 1), "progress toward a goal is textSoft, never gold or danger")
goal:SetProgress(1)
check(same(goal.bar.color, C.ok, 1), "a completed goal is ok")
local score = UI:CreateProgressBar(parent, 100, 8, true)
for _, case in ipairs({
  { 0.85, C.ok, "85%" }, { 0.8, C.ok, "exactly 80%" }, { 0.7999, C.warn, "just under 80%" },
  { 0.6, C.warn, "exactly 60%" }, { 0.5999, C.danger, "just under 60%" },
}) do
  score:SetProgress(case[1])
  check(same(score.bar.color, case[2], 1), "a score bar at " .. case[3])
end

-- ── Tab: a pill ─────────────────────────────────────────────────────────
local tab = UI:CreateTab(parent, "roster")
check(not tab.fill.shown and not tab.line.shown and same(tab.label.color, C.door), "tab at rest: the door's ink, no pill")
check(tab.label.font.file == F.ui and tab.label.font.size == 13, "a tab label is Alegreya Sans")
tab:Fire("OnEnter")
check(same(tab.label.color, C.text) and tab.line.shown and same(tab.line.color, C.lineHi, 1), "tab hover: the metal's line round it")
tab:Fire("OnLeave")
tab:SetActive(true)
check(tab.fill.shown and same(tab.fill.color, C.gold2, 1) and same(tab.label.color, C.onGold) and tab.label.font.file == F.uiBold,
  "active tab: a soft gold pill, dark bold text")
check(not tab.underline.shown, "no rule under a tab any more")
tab:Fire("OnEnter")
check(tab.fill.shown and same(tab.label.color, C.onGold), "an active tab keeps its pill while hovered")
local subBar = UI:StyleSubTabBar(CreateFrame("Frame"))
check(subBar.bg and subBar.bg.layer == "BACKGROUND" and same(subBar.bg.color, C.panel, 0.7) and subBar.rule,
  "a sub-tab bar: a dark strip with a line under it")

-- ── Scrollbar ───────────────────────────────────────────────────────────
local scrollFrame = CreateFrame("ScrollFrame")
local scrollBar = CreateFrame("Slider")
function scrollBar:GetMinMaxValues() return 0, 100 end
function scrollBar:GetValue() return 0 end
scrollBar.h = 200
scrollFrame.ScrollBar = scrollBar
UI:SkinScrollBar(scrollFrame)
check(scrollBar.w == 8, "the scrollbar is 8px")
check(same(scrollBar.textures[1].color, C.well, 0.6), "the scrollbar track is well, see-through")
check(scrollBar.customThumb.w == 6 and same(scrollBar.customThumb.color, C.lineHi, 1), "the thumb is the metal")
scrollBar:Fire("OnEnter")
check(same(scrollBar.customThumb.color, C.label, 1), "scrollbar hover: the thumb lights")

-- ── Text ────────────────────────────────────────────────────────────────
local title = UI:CreateTitle(parent, "Roster da guilda")
check(title.font.file == F.title and title.font.size == 15 and same(title.color, C.gold),
  "window title: Cinzel 15, gold")
local small = UI:CreateText(parent, "offline", 9)
check(small.font.file == F.ui and small.font.size == 11 and small.font.flags == "" and small.shadow[1] == 0,
  "small text: Alegreya Sans at 11px, no outline, no shadow")
local head = UI:CreateHeaderText(parent, "membro")
check(head.font.file == F.title and head.font.size == 11 and same(head.color, C.gold),
  "a header: Cinzel 11 (UI.SP.META) in gold")
check(same(UI:CreateHeaderText(paperCard, "membro").color, C.paperTitle), "a header on the paper: dark red")

-- ── Surfaces and rules ──────────────────────────────────────────────────
local panel = UI:CreatePanel(parent)
check(same(panel.__look.fill.color, C.darkCard, C.darkCard.a) and same(panel.__look.line.color, C.lineHi, 1),
  "a panel: the dark card, see-through, with the metal's line")
check(panel.__look.fill.pieces.TL.file:find("card.tga", 1, true), "rounded: drawn from Media/Salao's card")
local well = UI:CreateDarkPanel(parent)
check(same(well.__look.fill.color, C.well, 0.8), "an inset panel: well")
panel:SetBackdropColor(0.1, 0.2, 0.3, 1)
check(near(panel.__look.fill.color[2], 0.2), "a panel's backdrop colour call lands on its art")
local rule = UI:CreateAccentLine(parent)
check(rule.h == 2 and same(rule.color, C.gold, 1), "an accent line: solid 2px gold")
local sep = UI:CreateSeparator(parent)
check(sep.h == 1 and same(sep.color, C.line, 1), "a separator: 1px line")

-- ── Close button and round tool ─────────────────────────────────────────
local close = UI:CreateCloseButton(parent)
check(close.orb.file:find("orb.tga", 1, true) and same(close.ring.color, C.crimsonLine, 1) and close.x.text == "\195\151",
  "close button: a round crimson button, a gold ring, a ×")
close:Fire("OnEnter")
check(close.orb.color[1] > 0.765, "close hover: brighter")
local tool = UI:CreateToolButton(parent, "icon-gear", 28)
check(tool.w == 28 and same(tool.ring.color, C.lineHi, 1) and tool.icon.file:find("icon-gear.tga", 1, true),
  "a round tool: the metal's ring, its icon")
tool:SetPressed(true)
check(same(tool.ring.color, C.gold2, 1), "a pressed tool: the soft gold ring")

-- ── Popup: no shadow, the bright metal's border ─────────────────────────
local pop = CreateFrame("Frame")
UI:StylePopup(pop, { noSheen = true, shadowSize = 16 })
check(pop.dropShadow == nil and UI.CreateDropShadow == nil, "a popup has no shadow, whatever the caller asks")
check(same(pop.border, C.metal2, 1), "a popup: the bright metal's border")
pop:Fire("OnShow")
check(fades[#fades] and fades[#fades].frame == pop and near(fades[#fades].duration, 0.1), "a popup fades in over 0.1s")
local slow = CreateFrame("Frame")
UI:EnableFadeIn(slow, 0.4)
slow:Fire("OnShow")
check(fades[#fades].frame == slow and near(fades[#fades].duration, 0.1), "no fade runs longer than 0.1s")

-- ── Metric chip: a small dark tile ──────────────────────────────────────
local chip = UI:CreateMetricChip(parent, "41", "membros")
check(chip.value.font.file == F.title and chip.value.font.size == UI.SP.KPI and same(chip.value.color, C.gold2)
  and chip.label.font.file == F.ui and same(chip.label.color, C.textSoft) and not chip.rule.shown,
  "a metric chip: Cinzel 22 (UI.SP.KPI) in the soft gold, a soft caption, no rule")
check(chip.value.points[1][1] == "TOPLEFT" and chip.value.points[1][2] == 12 and chip.value.points[1][3] == -8,
  "the value sits inside the tile")
local paperChip = UI:CreateMetricChip(paperCard, "76%", "presença")
check(same(paperChip.value.color, C.paperTitle), "on the paper a tile's number is dark red")

-- ── A label always fits its button or tab (issue #28) ─────────────────
-- The stub measures 6px a glyph; the pad is 16px.
check(UI:CreateButton(parent, "ok", 80, 22).w == 80, "a label that fits keeps the caller's width")
check(UI:CreateButton(parent, "Tentative", 58, 18).w == 58, "a label that fits snugly (inside its 2px margins) keeps it too")
local long = UI:CreateButton(parent, "Definir como main", 90, 18)
check(long.w == 17 * 6 + 16, "a label wider than the button grows it to the label and its pad")
long.label:SetText("Desvincular personagem")
check(long.w == 22 * 6 + 16, "a later, longer label grows it again")
long.label:SetText("ok")
check(long.w == 22 * 6 + 16, "a shorter label never shrinks it, so a layout's own width survives")
check(long.label.text == "ok", "the label still takes its text")
check(UI:CreateTab(parent, "Caixa de entrada", 90).w == 16 * 6 + 16, "a tab grows to its label too")
check(UI:CreateButton(parent, "", 22, 22).w == 22, "an empty label leaves an icon button alone")

io.write(string.format("forever-components: %d checks passed\n", checks))
