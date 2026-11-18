-- Forever skin components (issue #13), run against the real Core/Data.lua and
-- UI/Helpers.lua under a stub frame API that records what was painted.
--
-- The factories decide every state colour in code: rest, hover, pressed and
-- disabled, for the primary, secondary, ghost and danger buttons, the
-- checkbox, the tab, the close button, badges, the scrollbar, icons, the
-- popup, the fade and the progress bar. This proves each state lands on the
-- design handoff's token and size, that the
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
  return f
end

function CreateFrame()
  local fr = region()
  fr.scripts, fr.enabled, fr.level, fr.textures = {}, true, 1, {}
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
dofile(ADDON .. "/UI/Helpers.lua")
local UI, C, F = GuildOS.UI, GuildOS.Colors, GuildOS.Fonts

local EPS = 1e-6
local function near(a, b) return math.abs(a - b) < EPS end
local function same(rgb, token, alpha)
  return rgb and near(rgb[1], token.r) and near(rgb[2], token.g) and near(rgb[3], token.b)
    and (alpha == nil or near(rgb[4] or 1, alpha))
end

local parent = CreateFrame("Frame")

-- ── Secondary button, the default ───────────────────────────────────────
local b = UI:CreateButton(parent, "cancelar")
check(b.h == 26, "a button defaults to 26px")
check(UI:CreateButton(parent, "salvar", 80, 22).h == 22, "a caller's own button height is kept")
check(same(b.border, C.lineHi, 1) and b.bg[4] == 0, "secondary at rest: lineHi border, no fill")
check(same(b.label.color, C.text), "secondary label is paper")
check(b.label.font.file == F.sansMedium and b.label.font.size == 12 and b.label.font.flags == "",
  "a button label is Plex Sans Medium 12 and not outlined")
b:Fire("OnEnter")
check(same(b.border, C.label, 1), "secondary hover: label border")
b:Fire("OnMouseDown")
check(same(b.bg, C.popup, 1), "secondary pressed: popup fill")
b:Fire("OnLeave")
check(same(b.border, C.lineHi, 1) and b.bg[4] == 0, "leaving restores the resting state")

local up = UI:CreateButton(parent, "subir")
up:Fire("OnMouseDown")
up.mouseOver = false
up:Fire("OnMouseUp")
check(same(up.border, C.lineHi, 1) and up.bg[4] == 0, "releasing away from the button returns it to rest")
up:Fire("OnMouseDown")
up.mouseOver = true
up:Fire("OnMouseUp")
check(same(up.border, C.label, 1) and up.bg[4] == 0, "releasing over the button leaves it hovered, not pressed")

local toggle = UI:CreateButton(parent, "filtro")
toggle:Fire("OnEnter")
toggle:SetBaseColor(0.9, 0.9, 0.9, 1)
check(not near(toggle.bg[1], 0.9), "SetBaseColor does not paint over a hovered button")
toggle:Fire("OnLeave")
check(near(toggle.bg[1], 0.9) and near(toggle.bg[4], 1), "a toggle's resting colour appears once the hover ends")

b:Disable()
check(same(b.label.color, C.disabled), "disabled: the label turns disabled")
b:Fire("OnEnter")
check(same(b.label.color, C.disabled), "hovering a disabled button does not light it")
b:Enable()
check(same(b.label.color, C.text) and same(b.border, C.lineHi, 1), "enabling repaints the resting state")

-- ── Primary ─────────────────────────────────────────────────────────────
local p = UI:SetButtonVariant(UI:CreateButton(parent, "dar loot"), "primary")
check(same(p.bg, C.gold, 1) and same(p.label.color, C.onGold), "primary at rest: gold fill, onGold label")
check(same(p.border, C.gold, 1), "primary at rest: gold border")
check(p.glow == nil, "primary is flat: no glow")
check(p.label.font.file == F.sansMedium and p.label.font.size == 12, "primary label is Plex Sans Medium 12")
local restPts = p.label.points
p:Fire("OnEnter")
check(same(p.bg, C.goldHover, 1) and same(p.border, C.goldHover, 1), "primary hover: goldHover fill and border")
p:Fire("OnMouseDown")
check(same(p.bg, C.goldActive, 1) and same(p.border, C.goldActive, 1), "primary pressed: goldActive fill and border")
check(p.label.points == restPts and #restPts == 1 and restPts[1][1] == "CENTER" and restPts[1][3] == nil,
  "pressing a primary button leaves its label where it is")
p.mouseOver = true
p:Fire("OnMouseUp")
check(same(p.bg, C.goldHover, 1), "releasing a primary button over it: hover gold")
p:Fire("OnLeave")
check(same(p.bg, C.gold, 1) and same(p.border, C.gold, 1), "the cursor leaving a primary button: resting gold")
p:Disable()
check(near(p.bg[4], 0.35) and near(p.border[4], 0.35), "disabled primary: gold at 35%, its border too")

-- ── Ghost and danger ────────────────────────────────────────────────────
local g = UI:SetButtonVariant(UI:CreateButton(parent, "ver histórico"), "ghost")
check(g.border[4] == 0 and same(g.label.color, C.label) and g.underline and g.underline.shown,
  "ghost: no border, label text, underline")
check(g.label.font.file == F.mono and g.label.font.size == 11, "a ghost label is mono 11, a link")
g:Fire("OnEnter")
check(same(g.label.color, C.text) and same(g.underline.color, C.text, 1), "ghost hover: paper label and underline")
g:Fire("OnMouseDown")
check(g.bg[4] == 0, "ghost pressed: still no fill")
g:Disable()
check(same(g.label.color, C.disabled) and g.bg[4] == 0, "disabled ghost: disabled label, no fill")
g:Enable()
local d = UI:SetButtonVariant(UI:CreateButton(parent, "expulsar"), "danger")
check(same(d.border, C.danger, 1) and same(d.label.color, C.danger), "danger: danger border and label")
d:Fire("OnEnter")
check(same(d.bg, C.danger, 0.12), "danger hover: a faint danger wash, not gold")
check(same(d.border, C.danger, 1), "danger hover keeps its danger border")
d:Fire("OnMouseDown")
check(same(d.bg, C.popup, 1), "danger pressed: popup fill")
d:Disable()
check(same(d.label.color, C.disabled) and d.bg[4] == 0, "disabled danger: disabled label, no fill")
check(d.glow == nil, "no button glows")
UI:SetButtonVariant(g, "secondary")
check(not g.underline.shown and same(g.border, C.lineHi, 1) and g.label.font.file == F.sansMedium,
  "a ghost switched back to secondary loses its underline and its mono")

-- ── Checkbox ────────────────────────────────────────────────────────────
local cbf = UI:CreateCheckbox(parent, "anotar o chat", 18)
local cb = cbf.checkbox
local cbBorder = cb.textures[1]
check(cb.w == 14 and cb.h == 14, "the checkbox box is 14px")
check(not cb.checkMark.shown and same(cbBorder.color, C.lineHi, 1), "unchecked at rest: no mark, lineHi border")
local cbFill = cb.textures[2]
check(same(cbFill.color, C.well, 1), "the checkbox box is well")
cb:Fire("OnMouseDown")
check(same(cbFill.color, C.popup, 1), "checkbox pressed: popup fill")
cb:Fire("OnMouseUp")
check(same(cbFill.color, C.well, 1), "checkbox released: well again")
cb:Fire("OnEnter")
check(same(cbBorder.color, C.label, 1), "checkbox hover: label border")
cb:Fire("OnLeave")
check(same(cbBorder.color, C.lineHi, 1), "checkbox leave: lineHi border again")

local seen
cb.onChanged = function(_, checked) seen = checked end
cb.checked = true
cb:Fire("OnClick")
check(seen == true, "a click reaches onChanged with the checked state")
check(cb.checkMark.shown and cb.checkMark.w == 8 and same(cb.checkMark.color, C.gold, 1),
  "a click repaints: solid 8px gold mark")
cb:SetChecked(false)
check(not cb.checkMark.shown, "SetChecked(false) hides the mark")
cb:SetChecked(true)
check(cb.checkMark.shown, "SetChecked(true) shows the mark")
cb:Disable()
check(near(cb.checkMark.alpha, 0.35) and same(cbBorder.color, C.disabled, 1), "disabled: the mark at 35%, disabled border")
cb:Fire("OnEnter")
check(same(cbBorder.color, C.disabled, 1), "hovering a disabled checkbox does not light it")

-- ── Badges ──────────────────────────────────────────────────────────────
local officer = UI:CreateBadge(parent, "oficial", C.gold)
check(officer.bg[4] == 0 and same(officer.border, C.line, 1) and same(officer.label.color, C.label),
  "the officer badge is neutral: gold is not a badge colour")
local plain = UI:CreateBadge(parent, "raider")
check(plain.bg[4] == 0 and same(plain.border, C.line, 1) and same(plain.label.color, C.label),
  "a plain badge: label text in a line frame")
check(plain.label.font.file == F.mono and plain.label.font.size == 10, "badge text is mono 10")
local absent = UI:CreateBadge(parent, "falta", C.danger)
check(same(absent.border, C.danger, 1) and same(absent.label.color, C.danger), "a danger badge: danger frame and text")
local trial = UI:CreateBadge(parent, "trial 8/10", C.ok)
check(same(trial.border, C.line, 1) and same(trial.label.color, C.ok), "any other colour: coloured text in a line frame")
-- Legacy keys are copies of their token, so older screens passing them must still match.
local legacyGold = UI:CreateBadge(parent, "oficial", C.accent)
check(legacyGold.bg[4] == 0 and same(legacyGold.label.color, C.label), "a badge in the legacy accent is neutral too")
local legacyRed = UI:CreateBadge(parent, "falta", C.red)
check(same(legacyRed.border, C.danger, 1) and same(legacyRed.label.color, C.danger), "a badge in the legacy red gets the danger frame")
plain:SetText("falta", C.danger)
check(same(plain.border, C.danger, 1) and same(plain.label.color, C.danger) and plain.label.text == "falta",
  "SetText with a colour repaints the badge")
plain:SetText("raider")
check(same(plain.border, C.danger, 1) and plain.label.text == "raider", "SetText without a colour keeps the badge's paint")
for _, badge in ipairs({ officer, plain, absent, trial, legacyGold, legacyRed }) do
  check(badge.bg[4] == 0, "no badge is ever filled")
end

-- ── Progress bar ────────────────────────────────────────────────────────
local goal = UI:CreateProgressBar(parent, 100)
check(goal.h == 8, "the progress bar is 8px")
check(same(goal.bg, C.well, 1) and same(goal.border, C.line, 1), "the progress track is well in a line frame")
check(goal.bar.color ~= nil, "the bar is painted as soon as it exists")
goal:SetWidth(200)
goal:SetProgress(1)
check(goal.bar.w == 198, "the fill follows the bar's width after a resize (issue #33)")
goal:SetWidth(100)
goal:SetProgress(0.31)
check(same(goal.bar.color, C.textSoft, 1), "progress toward a goal is textSoft, never gold or danger")
goal:SetProgress(0.99)
check(same(goal.bar.color, C.textSoft, 1), "an unfinished goal stays textSoft")
goal:SetProgress(1)
check(same(goal.bar.color, C.ok, 1), "a completed goal is ok")

local score = UI:CreateProgressBar(parent, 100, 8, true)
for _, case in ipairs({
  { 0.85, C.ok, "85%" }, { 0.8, C.ok, "exactly 80%" }, { 0.7999, C.warn, "just under 80%" },
  { 0.6, C.warn, "exactly 60%" }, { 0.5999, C.danger, "just under 60%" }, { 0.31, C.danger, "31%" },
}) do
  score:SetProgress(case[1])
  check(same(score.bar.color, case[2], 1), "a score bar at " .. case[3])
end

-- ── Tab ─────────────────────────────────────────────────────────────────
local tab = UI:CreateTab(parent, "roster")
check(tab.h == 28 and not tab.underline.shown and same(tab.label.color, C.label), "tab at rest: label text, no rule")
check(tab.label.font.file == F.mono and tab.label.font.size == 11, "a tab label is mono 11")
tab:Fire("OnEnter")
check(same(tab.label.color, C.text) and not tab.underline.shown, "tab hover: paper, still no rule")
tab:Fire("OnLeave")
tab:SetActive(true)
check(tab.underline.shown and tab.underline.h == 2 and same(tab.underline.color, C.gold, 1) and same(tab.label.color, C.gold),
  "active tab: gold label and a 2px gold rule")
tab:Fire("OnMouseDown")
check(same(tab.bg, C.panel, 1), "tab pressed: panel fill")
tab.mouseOver = false
tab:Fire("OnMouseUp")
check(tab.bg[4] == 0 and tab.underline.shown, "tab released: no fill, the active rule stays")
tab:Fire("OnEnter")
check(tab.underline.shown and same(tab.label.color, C.gold), "an active tab keeps its rule and gold while hovered")
tab.mouseOver = true
tab:Fire("OnMouseDown")
tab:Fire("OnMouseUp")
check(tab.bg[4] == 0 and same(tab.label.color, C.gold), "a click released over the tab: no fill, still gold")

-- ── Scrollbar ───────────────────────────────────────────────────────────
local scrollFrame = CreateFrame("ScrollFrame")
local scrollBar = CreateFrame("Slider")
function scrollBar:GetMinMaxValues() return 0, 100 end
function scrollBar:GetValue() return 0 end
scrollBar.h = 200
scrollFrame.ScrollBar = scrollBar
UI:SkinScrollBar(scrollFrame)
check(scrollBar.w == 8, "the scrollbar is 8px")
check(same(scrollBar.textures[1].color, C.well, 1), "the scrollbar track is well")
check(scrollBar.customThumb.w == 6 and same(scrollBar.customThumb.color, C.lineHi, 1),
  "the thumb is lineHi with 1px of margin")
scrollBar:Fire("OnEnter")
check(same(scrollBar.customThumb.color, C.label, 1), "scrollbar hover: the thumb lights to label")
scrollBar:Fire("OnLeave")
check(same(scrollBar.customThumb.color, C.lineHi, 1), "scrollbar leave: the thumb is lineHi again")

-- ── Text ────────────────────────────────────────────────────────────────
local title = UI:CreateTitle(parent, "Roster da guilda")
check(title.font.file == F.sansStrong and title.font.size == 16 and same(title.color, C.text),
  "window title: Plex Sans SemiBold 16, paper")
local small = UI:CreateText(parent, "offline", 9)
check(small.font.file == F.sans and small.font.size == 11 and small.font.flags == "" and small.shadow[1] == 0,
  "small text: sans at 11px, no outline, no shadow")
local head = UI:CreateHeaderText(parent, "membro")
check(head.font.file == F.monoStrong and head.font.size == 10 and same(head.color, C.label),
  "a header: mono Medium 10 in label")

-- ── Surfaces and rules ──────────────────────────────────────────────────
local panel = UI:CreatePanel(parent)
check(same(panel.bg, C.bg, 1) and same(panel.border, C.line, 1), "a panel: bg with a line border")
check(same(UI:CreateDarkPanel(parent).bg, C.well, 1), "an inset panel: well")
local rule = UI:CreateAccentLine(parent)
check(rule.h == 2 and same(rule.color, C.gold, 1), "an accent line: solid 2px gold")
check(UI:CreateAccentLine(parent, 1).h == 1, "an accent line can be 1px")
local sep = UI:CreateSeparator(parent)
check(sep.h == 1 and same(sep.color, C.line, 1), "a separator: 1px line")
local icon = UI:CreateIcon(parent, 32)
check(icon.w == 36 and same(icon.bg, C.well, 1) and same(icon.border, C.line, 1), "an icon: well in a line frame")

-- ── Close button ────────────────────────────────────────────────────────
local close = UI:CreateCloseButton(parent)
check(close.bg[4] == 0 and close.border[4] == 0 and same(close.x.color, C.label),
  "close button at rest: a label ×, no square, no border")
close:Fire("OnEnter")
check(same(close.bg, C.popup, 1) and same(close.border, C.lineHi, 1) and same(close.x.color, C.text),
  "close hover: a paper × on a popup square")
close:Fire("OnLeave")
check(close.bg[4] == 0 and close.border[4] == 0 and same(close.x.color, C.label), "close leave: back to rest")

-- ── Popup: no shadow, a lineHi border ───────────────────────────────────
local pop = CreateFrame("Frame")
UI:StylePopup(pop, { noSheen = true, shadowSize = 16 })
check(pop.dropShadow == nil and UI.CreateDropShadow == nil, "a popup has no shadow, whatever the caller asks")
check(same(pop.border, C.lineHi, 1), "a popup: lineHi border")

-- ── Fade: the only motion, 0.1s at most ─────────────────────────────────
pop:Fire("OnShow")
check(fades[#fades] and fades[#fades].frame == pop and near(fades[#fades].duration, 0.1), "a popup fades in over 0.1s")
local slow = CreateFrame("Frame")
UI:EnableFadeIn(slow, 0.4)
slow:Fire("OnShow")
check(fades[#fades].frame == slow and near(fades[#fades].duration, 0.1), "no fade runs longer than 0.1s")

-- ── Metric chip ─────────────────────────────────────────────────────────
local chip = UI:CreateMetricChip(parent, "41", "membros")
check(chip.value.font.file == F.mono and chip.value.font.size == 24
  and chip.rule.h == 1 and same(chip.rule.color, C.gold, 1)
  and chip.label.font.file == F.mono and chip.label.font.size == 10 and same(chip.label.color, C.label),
  "a metric chip: mono 24 value, 1px gold rule, mono 10 label caption")
local r1, r2 = chip.rule.points[1], chip.rule.points[2]
check(r1 and r1[1] == "TOPLEFT" and r2 and r2[1] == "TOPRIGHT", "the rule runs across the top of the chip")
check(chip.value.points[1][1] == "TOPLEFT" and chip.value.points[1][3] == -9, "the value sits 8px under the rule")

-- ── Sub-tabs (issue #14) ────────────────────────────────────────────────
local subTab = UI:CreateTab(parent, "sessões", 110, true)
check(subTab.underline.h == 1, "a sub-tab's active rule is 1px")
check(UI:CreateTab(parent, "roster").underline.h == 2, "a tab's active rule stays 2px")
subTab:SetActive(true)
check(subTab.underline.shown and same(subTab.label.color, C.gold), "an active sub-tab: gold label over its rule")
local subBar = UI:StyleSubTabBar(CreateFrame("Frame"))
check(subBar.bg and subBar.bg.layer == "BACKGROUND" and same(subBar.bg.color, C.panel, 1), "a sub-tab bar sits on panel")

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
