----------------------------------------------------------------------
-- Guild OS - UI Helpers
-- Reusable factories for the GuildOS style (Swiss Modernism 2.0;
-- docs/superpowers/specs/2026-11-17-swiss-identity-design.md): flat opaque
-- surfaces told apart by a 1px line, no glow and no shadow, gold only for
-- the primary button, focus, selection, the active tab and the metric rule,
-- IBM Plex Sans for words and Plex Mono for numbers and labels, and state
-- changes that land in the same frame. Public names, signatures and fields
-- are unchanged from Obsidian, except CreateDropShadow, frame.dropShadow and
-- btn.glow, which went with the shadow and the glow (#361).
-- The interface style (Core/Style.lua, #122) paints each surface and control through them.
----------------------------------------------------------------------
local Helpers = {}
GuildOS.UI = Helpers

local C = GuildOS.Colors
local Style = GuildOS.Style
local WHITE = "Interface\\Buttons\\WHITE8x8"

local BUTTON_HEIGHT  = 26    -- default button height (handoff §8)
local DANGER_WASH    = 0.12  -- danger tint behind a hovered danger button
local DISABLED_GOLD  = 0.35  -- alpha of a disabled primary button or checkbox mark
local FADE_MAX       = 0.1   -- seconds; the only motion the skin allows
local SCROLL_WIDTH   = 8
-- The scroll bar sits inside its frame's right edge (2px in, SCROLL_WIDTH wide): content keeps this
-- much clear on the right, so nothing runs under it (#371). Layout's BindScrollChildWidth applies it.
Helpers.SCROLL_GUTTER = SCROLL_WIDTH + 4
local CHECK_BOX      = 14
local CHECK_MARK     = 8
local PROGRESS_OK    = 0.8   -- at or above: ok
local PROGRESS_WARN  = 0.6   -- at or above: warn; below: danger
local CHIP_MIN       = 34    -- px: a metric chip is never narrower than this
local CHIP_PAD       = 8     -- px between a metric chip's gold rule and its value

-- A FontString with the skin's text settings: font by size (GuildOS:ApplyFont),
-- no outline, no shadow.
local function newText(parent, size, role)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size, role)
    fs:SetShadowOffset(0, 0)
    return fs
end

-- Grow a button or tab whose label spills past it: the mono font and longer
-- translations run past the widths callers pass (issue #28). A label that fits,
-- even snugly, leaves the caller's width alone; one that spills grows it to the
-- label plus a pad. It never shrinks, so a width a layout sets later is kept, and
-- it follows every later label change, so a toggle that swaps its text still fits.
local LABEL_PAD = 16
local function fitToLabel(frame)
    local label, setText = frame.label, frame.label.SetText
    local function fit()
        local w = label:GetStringWidth()
        if w > frame:GetWidth() - 4 then frame:SetWidth(math.ceil(w) + LABEL_PAD) end
    end
    label.SetText = function(self, text)
        setText(self, text)
        fit()
    end
    fit()
end

----------------------------------------------------------------------
-- Pixels (issue #369)
----------------------------------------------------------------------

-- `n` interface units (1 by default) in `region`'s scale, rounded to whole screen pixels and never
-- under one. A 1-unit line is under a pixel when the interface is scaled down, and the game then rounds
-- both of its ends to the same pixel: the side of a box, or a rule, vanishes.
function Helpers:Px(region, n)
    n = n or 1
    if not (PixelUtil and PixelUtil.GetNearestPixelSize and region and region.GetEffectiveScale) then return n end
    return PixelUtil.GetNearestPixelSize(n, region:GetEffectiveScale(), 1)
end

-- What keeps a pixel when the scale changes: frame -> "edge" (its backdrop's edge), texture -> "Height"/"Width".
local hairlines = setmetatable({}, { __mode = "k" })

-- The backdrop edge size for `frame`: one screen pixel. Use it as `edgeSize = GuildOS.UI:Edge(f)`.
function Helpers:Edge(frame)
    hairlines[frame] = "edge"
    return self:Px(frame)
end

-- Make a texture a one-pixel rule across its other side: dim "Height" (default) or "Width".
function Helpers:Hairline(tex, dim)
    dim = dim or "Height"
    hairlines[tex] = dim
    tex["Set" .. dim](tex, self:Px(tex))
    return tex
end

-- Hang a texture one screen pixel outside its parent on every side: a border behind a fill. A 1-unit
-- offset rounds to nothing on the right and bottom when the interface is scaled down.
function Helpers:Outset(tex)
    hairlines[tex] = "outset"
    local px = self:Px(tex)
    tex:SetPoint("TOPLEFT", -px, px)
    tex:SetPoint("BOTTOMRIGHT", px, -px)
    return tex
end

-- Size every line again after the interface, the window or the screen changes scale (Core.lua's
-- event frame calls it on login, UI_SCALE_CHANGED and DISPLAY_SIZE_CHANGED; ApplyScale for the window).
function Helpers:RefreshHairlines()
    for region, kind in pairs(hairlines) do
        local px = self:Px(region)
        if kind == "outset" then
            region:SetPoint("TOPLEFT", -px, px)
            region:SetPoint("BOTTOMRIGHT", px, -px)
        elseif kind ~= "edge" then
            region["Set" .. kind](region, px)
        else
            local info = region.backdropInfo
            if info and info.edgeFile and info.edgeSize ~= px then
                local r, g, b, a = region:GetBackdropColor()
                local er, eg, eb, ea = region:GetBackdropBorderColor()
                local copy = {}
                for k, v in pairs(info) do copy[k] = v end
                copy.edgeSize = px
                region:SetBackdrop(copy)
                if r then region:SetBackdropColor(r, g, b, a) end
                if er then region:SetBackdropBorderColor(er, eg, eb, ea) end
            end
        end
    end
end

----------------------------------------------------------------------
-- Surfaces
----------------------------------------------------------------------

-- Create a window surface (elevation 2): `bg` with a 1px `line` border.
function Helpers:CreatePanel(parent, name, level)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    -- A window at the top level; a block inside a screen is a panel (#122).
    Style:Paint(f, (parent == nil or parent == UIParent) and "window" or "panel")
    return f
end

-- Create an inset surface (elevation 1: table body, field, scroll area).
function Helpers:CreateDarkPanel(parent, name, level)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    Style:Paint(f, "well")
    return f
end

-- Fade a frame in when shown. Capped at 0.1s: the skin allows no other motion.
function Helpers:EnableFadeIn(frame, duration)
    duration = math.min(duration or FADE_MAX, FADE_MAX)
    frame:HookScript("OnShow", function(self)
        if self.__fadingDisabled then return end
        UIFrameFadeIn(self, duration, 0, 1)
    end)
end

-- Give a popup its elevation: a `lineHi` border and the short fade-in. The
-- background stays the caller's. There is no shadow, so `opts.noShadow`,
-- `shadowSize`, `shadowAlpha` and `noSheen` are accepted and ignored.
function Helpers:StylePopup(frame, opts)
    opts = opts or {}
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    end
    if not opts.noFade then self:EnableFadeIn(frame, opts.fadeDuration) end
    Style:Paint(frame, "popup")
    return frame
end

-- Create a gold rule: 2px by default (under an active tab); pass 1 for a
-- metric chip or an active sub-tab.
function Helpers:CreateAccentLine(parent, thickness)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    if (thickness or 2) == 1 then Helpers:Hairline(line) else line:SetHeight(thickness or 2) end
    line:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    line.__solidColor = C.gold
    return line
end

-- Create a 1px separator in `line`.
function Helpers:CreateSeparator(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    Helpers:Hairline(line)
    line:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
    return line
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------

-- Create a window title: IBM Plex Sans SemiBold, paper.
function Helpers:CreateTitle(parent, text, size)
    local fs = newText(parent, size or 16, "windowTitle")
    fs:SetTextColor(C.text.r, C.text.g, C.text.b)
    fs:SetText(text or "")
    return fs
end

-- Create body or table text: IBM Plex Sans, paper unless a colour is given.
function Helpers:CreateText(parent, text, size, r, g, b)
    local fs = newText(parent, size or 12)
    fs:SetTextColor(r or C.text.r, g or C.text.g, b or C.text.b)
    fs:SetText(text or "")
    return fs
end

-- Create a column header: IBM Plex Mono Medium in `label`. A section of a screen takes
-- CreateSectionTitle instead.
function Helpers:CreateHeaderText(parent, text, size)
    local fs = newText(parent, size or 10, "colHeader")
    fs:SetTextColor(C.label.r, C.label.g, C.label.b)
    fs:SetText(text or "")
    return fs
end

----------------------------------------------------------------------
-- One of each screen part (#371): every screen takes these, none draws its own
----------------------------------------------------------------------

-- Space between blocks, and under a sub-tab bar before a screen's first line. A screen's content
-- starts flush with the sub-tab bar's left edge (x = 0) and ends GAP short of the right one.
Helpers.GAP = 8

-- A section title as Settings draws it: Sans SemiBold 14 in `text`. Any section but a screen's first
-- has a 1px `line` rule 12px above it, from the title's left to the parent's right edge, so leave
-- about 20px over a later one. Returns the title; title.rule is that rule.
function Helpers:CreateSectionTitle(parent, text, first)
    local fs = newText(parent, nil, "sectionTitle")
    fs:SetTextColor(C.text.r, C.text.g, C.text.b)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    if not first then
        local rule = self:CreateSeparator(parent)
        rule:SetPoint("BOTTOMLEFT", fs, "TOPLEFT", 0, 12)
        rule:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        fs.rule = rule
    end
    return fs
end

-- A text field: `well` fill, 1px `lineHi` border that turns gold while typing, Sans 12 (Plex Mono for
-- numbers) inset 6px, Escape lets go. opts: numeric, max, multiline, placeholder (a hint shown while
-- empty), justify. Hook its scripts with HookScript: SetScript on the focus ones would drop the border.
function Helpers:CreateInput(parent, width, height, opts)
    opts = opts or {}
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 160, height or 22)
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = self:Edge(box) })
    box:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    box:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    box:SetTextInsets(6, 6, opts.multiline and 4 or 0, opts.multiline and 4 or 0)
    GuildOS:ApplyFont(box, 12, opts.numeric and "tableNum" or nil)
    box:SetTextColor(C.text.r, C.text.g, C.text.b)
    if opts.justify then box:SetJustifyH(opts.justify) end
    box:SetAutoFocus(false)
    if opts.multiline then box:SetMultiLine(true) end
    if opts.numeric then box:SetNumeric(true) end
    if opts.max then box:SetMaxLetters(opts.max) end
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1) end)
    box:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1) end)
    if opts.placeholder then
        local ph = newText(box, 12)
        ph:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        ph:SetPoint(opts.multiline and "TOPLEFT" or "LEFT", 6, opts.multiline and -4 or 0)
        ph:SetText(opts.placeholder)
        local function sync() ph:SetShown((box:GetText() or "") == "" and not box:HasFocus()) end
        box:HookScript("OnTextChanged", sync)
        box:HookScript("OnEditFocusGained", sync)
        box:HookScript("OnEditFocusLost", sync)
        sync()
        box.placeholder = ph
    end
    return box
end

-- A table's header row: 22px, no fill, a 1px `line` rule along its bottom. Put the column labels on
-- it with CreateHeaderText and anchor it by its top corners; the first row sits right under it.
function Helpers:CreateTableHeader(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 22)
    local rule = self:CreateSeparator(f)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    f.rule = rule
    return f
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------

-- Paint one button state: "rest", "hover", "pressed" or "disabled". Internal.
-- Every colour lands in the same frame; there is no transition.
function Helpers:_ButtonState(btn, state)
    if btn.__forever then return Style:ButtonState(btn, state) end
    btn.__hovered = (state == "hover")
    local variant = btn.variant
    local base, text, border = btn.baseColor, btn.baseLabelColor, btn.baseBorder
    local r, g, b, a = base[1], base[2], base[3], base[4]
    local tr, tg, tb = text[1], text[2], text[3]

    if state == "disabled" then
        tr, tg, tb = C.disabled.r, C.disabled.g, C.disabled.b
        if variant == "primary" then a = DISABLED_GOLD end
    elseif state == "hover" then
        if variant == "primary" then
            r, g, b = C.goldHover.r, C.goldHover.g, C.goldHover.b
            border = C.goldHover
        elseif variant == "danger" then
            r, g, b, a = C.danger.r, C.danger.g, C.danger.b, DANGER_WASH
        else
            tr, tg, tb = C.text.r, C.text.g, C.text.b
            if variant == "secondary" then border = C.label end
        end
    elseif state == "pressed" then
        if variant == "primary" then
            r, g, b = C.goldActive.r, C.goldActive.g, C.goldActive.b
            border = C.goldActive
        elseif variant ~= "ghost" then
            r, g, b, a = C.popup.r, C.popup.g, C.popup.b, 1
        end
    end

    -- Selected (Helpers:SetSelected): gold border and gold label, through hover and press (#371).
    if btn.__selected and state ~= "disabled" and variant ~= "primary" then
        border = C.gold
        tr, tg, tb = C.gold.r, C.gold.g, C.gold.b
    end

    btn:SetBackdropColor(r, g, b, a)
    if border then
        btn:SetBackdropBorderColor(border.r, border.g, border.b, (variant == "primary" and a) or 1)
    else
        btn:SetBackdropBorderColor(0, 0, 0, 0)
    end
    btn.label:SetTextColor(tr, tg, tb)
    if btn.underline then btn.underline:SetVertexColor(tr, tg, tb, 1) end
end

-- Create a button. Secondary by default (1px `lineHi` border, paper text on no
-- fill); Helpers:SetButtonVariant switches it to primary, ghost or danger.
-- Toggle buttons keep calling btn:SetBaseColor so a resting colour survives
-- the hover; setting btn.baseLabelColor does the same for the label.
function Helpers:CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or BUTTON_HEIGHT)
    btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(btn) })

    local label = newText(btn, nil, "button")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    btn.label = label
    fitToLabel(btn)

    btn.variant = "secondary"
    btn.baseColor = { C.well.r, C.well.g, C.well.b, 0 }
    btn.baseLabelColor = { C.text.r, C.text.g, C.text.b }
    btn.baseBorder = C.lineHi

    function btn:SetBaseColor(r, g, b, a)
        self.baseColor = { r, g, b, a or 1 }
        if self.__forever then return Style:ButtonTint(self, r, g, b, a) end   -- the game's art (#122)
        if not self.__hovered then
            self:SetBackdropColor(r, g, b, a or 1)
        end
    end

    local function idle(self) return self:IsEnabled() and "rest" or "disabled" end
    btn:SetScript("OnEnter", function(self)
        Helpers:_ButtonState(self, self:IsEnabled() and "hover" or "disabled")
    end)
    btn:SetScript("OnLeave", function(self) Helpers:_ButtonState(self, idle(self)) end)
    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then Helpers:_ButtonState(self, "pressed") end
    end)
    btn:SetScript("OnMouseUp", function(self)
        Helpers:_ButtonState(self, self:IsEnabled() and (self:IsMouseOver() and "hover" or "rest") or "disabled")
    end)
    btn:HookScript("OnDisable", function(self) Helpers:_ButtonState(self, "disabled") end)
    btn:HookScript("OnEnable", function(self) Helpers:_ButtonState(self, "rest") end)

    -- Flat in every style; only a primary button takes the game's art (SetButtonVariant, #148).
    self:_ButtonState(btn, "rest")
    return btn
end

-- Mark a button as the chosen one of a set (a filter, a mode, a model): gold border and gold label,
-- the identity's only selection mark (#371). No ">" prefix, no tinted fill.
function Helpers:SetSelected(btn, on)
    btn.__selected = on and true or nil
    if btn.label then
        self:_ButtonState(btn, not btn:IsEnabled() and "disabled" or (btn.__hovered and "hover") or "rest")
    end
    return btn
end

-- Switch a button to one of the variants: "primary" (flat gold fill; one per
-- screen), "secondary", "ghost" (mono label, underlined, no border) or
-- "danger". Returns the button.
function Helpers:SetButtonVariant(btn, variant)
    variant = variant or "secondary"
    btn.variant = variant
    local label = btn.label
    if variant == "primary" then
        Style:SkinButton(btn)
        btn.baseColor = { C.gold.r, C.gold.g, C.gold.b, 1 }
        btn.baseLabelColor = { C.onGold.r, C.onGold.g, C.onGold.b }
        btn.baseBorder = C.gold
        GuildOS:ApplyFont(label, nil, "button")  -- IBM Plex Sans Medium
    else
        Style:UnskinButton(btn)
        if variant == "ghost" then
            GuildOS:ApplyFont(label, 11, "caption")  -- IBM Plex Mono, a link
        else
            GuildOS:ApplyFont(label, nil, "button")
        end
        local ink = (variant == "ghost" and C.label) or (variant == "danger" and C.danger) or C.text
        btn.baseLabelColor = { ink.r, ink.g, ink.b }
        btn.baseColor = { C.well.r, C.well.g, C.well.b, 0 }
        btn.baseBorder = (variant == "danger" and C.danger) or (variant ~= "ghost" and C.lineHi) or nil
        if variant == "ghost" and not btn.underline then
            local u = btn:CreateTexture(nil, "ARTWORK")
            u:SetTexture(WHITE)
            Helpers:Hairline(u)
            u:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
            u:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -3)
            btn.underline = u
        end
        if btn.underline then btn.underline:SetShown(variant == "ghost") end
    end
    self:_ButtonState(btn, btn:IsEnabled() and "rest" or "disabled")
    return btn
end

----------------------------------------------------------------------
-- Attach an inline "Save" button to an EditBox whose value is otherwise
-- committed only by pressing Enter. The button and the Enter key share
-- the same commit callback, so the action is no longer hidden behind an
-- implicit keypress.
--   onSave(editBox)  -- runs the commit; receives the edit box
-- opts (all optional):
--   text    button label            (default: localized "Save")
--   width   button width            (default: 60)
--   height  button height           (default: edit box height, min 22)
--   gap     space box -> button     (default: 6)
--   point   { ... } SetPoint args to override the default anchoring
--           (default: anchored to the immediate right of the edit box)
-- This also rewires the box's OnEnterPressed to the same callback so the
-- two stay in sync. Returns the button.
----------------------------------------------------------------------
-- Pure: where the controls of a labelled form start (#265). Past the widest label (its left inset
-- plus `gap`), never before `floor`, the column the form always had. A form with fixed x's put a
-- long translation ("Membres qui aident :") over its own control.
function Helpers.LabelColumn(widths, left, gap, floor)
    local widest = 0
    for _, w in ipairs(widths) do
        if w > widest then widest = w end
    end
    return math.max(floor, math.ceil(left + widest + gap))
end

-- The room a box keeps on its right for the Save button attached to it (#265): the button's own
-- width, which follows its label ("Enregistrer" is wider than "Save"), plus `gap`.
function Helpers.ReserveFor(button, gap)
    return (button and button:GetWidth() or 0) + gap
end

-- The height a run of chips takes (#265): as many rows as are shown and the 4 px under them, none
-- for none, so a form with no chips keeps no gap where they would be.
function Helpers.ChipRowsHeight(shown, perRow, rowH)
    local rows = math.ceil((shown or 0) / perRow)
    return rows * rowH + (rows > 0 and 4 or 0)
end

function Helpers:AttachSaveButton(editBox, onSave, opts)
    opts = opts or {}
    local parent = opts.parent or editBox:GetParent()
    local label  = opts.text or (GuildOS.L and GuildOS.L["Save"]) or "Save"
    local h = opts.height or editBox:GetHeight()
    if not h or h < 22 then h = 22 end

    local btn = self:CreateButton(parent, label, opts.width or 60, h)
    if opts.point then
        btn:SetPoint(unpack(opts.point))
    else
        btn:SetPoint("LEFT", editBox, "RIGHT", opts.gap or 6, 0)
    end

    -- `opts.state` (issue #346): the button says whether the box holds what was saved. "Saved",
    -- and unclickable, until the text changes; "Save" from then until the commit.
    local savedText = opts.state and ((GuildOS.L and GuildOS.L["Saved"]) or "Saved")
    local function showSaved(saved)
        if not savedText then return end
        btn.label:SetText(saved and savedText or label)
        if saved then btn:Disable() else btn:Enable() end
    end
    local function commit()
        onSave(editBox)
        editBox:ClearFocus()
        showSaved(true)
    end
    btn:SetScript("OnClick", commit)
    editBox:SetScript("OnEnterPressed", commit)
    if savedText then
        editBox:HookScript("OnTextChanged", function(_, typed)
            if typed ~= false then showSaved(false) end
        end)
        showSaved(true)
    end

    editBox.saveButton = btn
    return btn
end

----------------------------------------------------------------------
-- A removable chip's text (issue #59): GuildOS:ChipLabel, shortened until it fits `width`
-- in the font that draws it (GuildOS's own or the game's, #57), so the chip never grows
-- over its neighbour and a click lands on the entry it shows.
----------------------------------------------------------------------
function Helpers:SetChipText(btn, text, width)
    width = width or btn:GetWidth()
    btn:SetWidth(width)
    local maxBytes = 14
    btn.label:SetText(GuildOS:ChipLabel(text, maxBytes))
    while btn.label:GetStringWidth() > width - 8 and maxBytes > 3 do
        maxBytes = maxBytes - 1
        btn.label:SetText(GuildOS:ChipLabel(text, maxBytes))
    end
    btn:SetWidth(width)
end

----------------------------------------------------------------------
-- Checkbox
----------------------------------------------------------------------

-- Create a checkbox with a label: a 14px box in `well` with a 1px border
-- and, when checked, a solid 8px gold mark (a texture, not a glyph).
-- `frame.checkbox.onChanged(cb, checked)` fires on click; SetChecked repaints.
function Helpers:CreateCheckbox(parent, labelText, size)
    size = size or 20
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size + 200, size)

    local cb = CreateFrame("CheckButton", nil, frame)
    cb:SetSize(CHECK_BOX, CHECK_BOX)
    cb:SetPoint("LEFT", math.floor((size - CHECK_BOX) / 2), 0)

    -- A texture one screen pixel larger on every side, under the fill, is the border (#369).
    local border = cb:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetTexture(WHITE)
    Helpers:Outset(border)
    local fill = cb:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetTexture(WHITE)
    fill:SetAllPoints()
    fill:SetVertexColor(C.well.r, C.well.g, C.well.b, 1)

    local mark = cb:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(WHITE)
    mark:SetSize(CHECK_MARK, CHECK_MARK)
    mark:SetPoint("CENTER")
    mark:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    mark:Hide()
    cb.checkMark = mark
    local skinned = Style:SkinCheckbox(cb, border, fill, mark)

    local function paint()
        local enabled = cb:IsEnabled()
        -- GetChecked() returns true or nil (never false) in TBC.
        mark:SetShown(cb:GetChecked() and true or false)
        mark:SetAlpha(enabled and 1 or DISABLED_GOLD)
        local edge = (not enabled and C.disabled) or (cb.__hovered and C.label) or C.lineHi
        border:SetVertexColor(edge.r, edge.g, edge.b, 1)
    end

    cb:SetScript("OnClick", function(self)
        paint()
        if self.onChanged then self:onChanged(self:GetChecked()) end
    end)
    local origSetChecked = cb.SetChecked
    cb.SetChecked = function(self, val)
        origSetChecked(self, val)
        paint()
    end
    cb:SetScript("OnEnter", function(self) self.__hovered = true; paint() end)
    cb:SetScript("OnLeave", function(self) self.__hovered = false; paint() end)
    -- The flat box darkens while pressed; the Forever art keeps its own colour (#122).
    cb:SetScript("OnMouseDown", function()
        if not skinned then fill:SetVertexColor(C.popup.r, C.popup.g, C.popup.b, 1) end
    end)
    cb:SetScript("OnMouseUp", function()
        if not skinned then fill:SetVertexColor(C.well.r, C.well.g, C.well.b, 1) end
    end)
    cb:HookScript("OnDisable", paint)
    cb:HookScript("OnEnable", paint)
    paint()

    local label = newText(frame, nil, "body")
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    label:SetTextColor(C.text.r, C.text.g, C.text.b)
    label:SetText(labelText or "")
    frame.label = label

    frame.checkbox = cb
    return frame
end

----------------------------------------------------------------------
-- Dropdown (issue #346)
-- A button that shows the value chosen and, clicked, opens the list of the others under it: one
-- popup the whole addon shares, built on first use, scrolled by the wheel past DROPDOWN_ROWS
-- rows, closed by a click outside it, by Escape and by a choice. No typing: a choice is a click.
-- Where a control picks one of more than two values it is this, never a button that cycles.
--   dd = UI:CreateDropdown(parent, width, height)
--   dd:SetOptions({ { value = v, text = "label", color = {r,g,b}? }, ... })
--   dd:SetValue(v)      show v, without telling anyone
--   dd:GetValue()
--   dd:Select(v)        show v and call dd.onSelect(dd, v), as a click on it does
--   dd.onSelect = function(dd, value) ... end
--   dd:SetPlaceholder(text)   what it says while no option is chosen
-- The button is a CreateButton, so it paints like every other one in either style; the list is a
-- popup surface (StylePopup) whose rows are borderless buttons.
----------------------------------------------------------------------
local DROPDOWN_ROWS  = 10     -- rows the list shows before it scrolls
local DROPDOWN_ROW_H = 20
local DROPDOWN_PAD   = 2      -- px between the list's edge and its rows
local ARROW_W        = 14     -- room the button keeps on its right for the arrow
local dropdownList            -- the shared list, built on first open

-- A small arrow pointing down, drawn as three rows of solid pixels (no glyph a font may lack).
local function dropdownArrow(btn)
    local rows = {}
    for i, w in ipairs({ 7, 5, 3, 1 }) do
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        t:SetWidth(w)
        Helpers:Hairline(t)
        t:SetPoint("RIGHT", btn, "RIGHT", -(6 + (7 - w) / 2), 2 - i)
        rows[i] = t
    end
    function btn:PaintArrow(col)
        for _, t in ipairs(rows) do t:SetVertexColor(col.r, col.g, col.b, 1) end
    end
    btn:PaintArrow(C.label)
end

local function closeDropdown()
    if dropdownList then
        dropdownList.owner = nil
        dropdownList:Hide()
        dropdownList.catcher:Hide()
    end
end

local function buildDropdownList()
    local f = CreateFrame("Frame", "GuildOSDropdownList", UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(20)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    Helpers:StylePopup(f, { noFade = true })
    f:Hide()
    table.insert(UISpecialFrames, "GuildOSDropdownList")   -- Escape closes it

    -- A click anywhere else closes the list: a transparent sheet over the screen, under the list.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(10)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", closeDropdown)
    catcher:Hide()
    f.catcher = catcher
    f:SetScript("OnHide", function(self)
        self.catcher:Hide()
        self.owner = nil
    end)

    f.scroll, f.child = Helpers:CreateScrollFrame(f, "GuildOSDropdownListScroll")
    f.scroll:SetPoint("TOPLEFT", DROPDOWN_PAD, -DROPDOWN_PAD)
    f.scroll:SetPoint("BOTTOMRIGHT", -DROPDOWN_PAD, DROPDOWN_PAD)
    f.rows = {}
    return f
end

-- One row of the list, made once and reused by every dropdown.
local function dropdownRow(f, i)
    local row = f.rows[i]
    if row then return row end
    row = Helpers:CreateButton(f.child, "", 10, DROPDOWN_ROW_H)
    row.baseBorder = nil
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetJustifyH("LEFT")
    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(WHITE)
    mark:SetSize(2, DROPDOWN_ROW_H - 6)
    mark:SetPoint("LEFT", 2, 0)
    mark:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    row.mark = mark
    row:SetScript("OnClick", function(self)
        local owner = f.owner
        closeDropdown()
        if owner then owner:Select(self.value) end
    end)
    Helpers:_ButtonState(row, "rest")
    f.rows[i] = row
    return row
end

local function openDropdown(dd)
    dropdownList = dropdownList or buildDropdownList()
    local f = dropdownList
    local options = dd.options or {}
    local width = math.max(dd:GetWidth() or 0, dd.listWidth or 0)
    local shown = math.max(1, math.min(#options, DROPDOWN_ROWS))
    f:SetSize(width, shown * DROPDOWN_ROW_H + DROPDOWN_PAD * 2)
    f.child:SetWidth(width - DROPDOWN_PAD * 2 - (#options > DROPDOWN_ROWS and 10 or 0))
    for i, opt in ipairs(options) do
        local row = dropdownRow(f, i)
        row.value = opt.value
        row:SetWidth(f.child:GetWidth())
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * DROPDOWN_ROW_H)
        row.label:SetText(opt.text or tostring(opt.value))
        local chosen = opt.value == dd.value
        local ink = opt.color or (chosen and C.gold) or C.text
        row.baseLabelColor = { ink.r, ink.g, ink.b }
        row.mark:SetShown(chosen)
        if opt.disabled then row:Disable() else row:Enable() end
        Helpers:_ButtonState(row, opt.disabled and "disabled" or "rest")
        row:Show()
    end
    for i = #options + 1, #f.rows do f.rows[i]:Hide() end
    f.child:SetHeight(math.max(1, #options * DROPDOWN_ROW_H))
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    f.owner = dd
    f.catcher:Show()
    f:Show()
end

-- Whether the shared list is open, and for which dropdown (the tests read it).
function Helpers:DropdownOpenFor()
    return dropdownList and dropdownList:IsShown() and dropdownList.owner or nil
end

function Helpers:CloseDropdown() closeDropdown() end

function Helpers:CreateDropdown(parent, width, height)
    local dd = self:CreateButton(parent, "", width or 140, height or 22)
    dd.label:ClearAllPoints()
    dd.label:SetPoint("LEFT", 8, 0)
    dd.label:SetPoint("RIGHT", -ARROW_W, 0)
    dd.label:SetJustifyH("LEFT")
    if dd.label.SetWordWrap then dd.label:SetWordWrap(false) end
    dropdownArrow(dd)
    dd.options, dd.placeholder = {}, ""

    local function textOf(value)
        for _, opt in ipairs(dd.options) do
            if opt.value == value then return opt.text or tostring(value), opt.color end
        end
        return nil
    end
    function dd:SetOptions(list)
        self.options = list or {}
        self:SetValue(self.value)
    end
    function dd:SetPlaceholder(text)
        self.placeholder = text or ""
        if textOf(self.value) == nil then self.label:SetText(self.placeholder) end
    end
    function dd:SetValue(value)
        self.value = value
        local text, color = textOf(value)
        self.label:SetText(text or self.placeholder)
        -- A value with a colour of its own (an item quality) keeps it at rest.
        local ink = color or (text and C.text) or C.label
        self.baseLabelColor = { ink.r, ink.g, ink.b }
        Helpers:_ButtonState(self, self:IsEnabled() and "rest" or "disabled")
    end
    function dd:GetValue() return self.value end
    function dd:Select(value)
        self:SetValue(value)
        if self.onSelect then self:onSelect(value) end
    end
    function dd:Open() openDropdown(self) end
    function dd:Close() if dropdownList and dropdownList.owner == self then closeDropdown() end end
    dd:SetScript("OnClick", function(self)
        if dropdownList and dropdownList:IsShown() and dropdownList.owner == self then
            closeDropdown()
        else
            openDropdown(self)
        end
    end)
    dd:HookScript("OnHide", function(self) self:Close() end)
    return dd
end

-- Create a close button (×): `label` at rest, paper on a `popup` square when hovered.
function Helpers:CreateCloseButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(20, 20)
    btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(btn) })
    btn:SetBackdropColor(0, 0, 0, 0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    local x = newText(btn, 14)
    x:SetPoint("CENTER", 0, 0)
    x:SetTextColor(C.label.r, C.label.g, C.label.b)
    x:SetText("\195\151")  -- multiplication sign (×) reads cleaner than letter X
    btn.x = x

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
        self:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        self.x:SetTextColor(C.text.r, C.text.g, C.text.b)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        self.x:SetTextColor(C.label.r, C.label.g, C.label.b)
    end)

    Style:SkinClose(btn, "close")
    return btn
end

----------------------------------------------------------------------
-- A button that lives on a title bar.
--
-- A title bar is mouse-enabled and drag-registered across its full
-- width. A button placed on it as a SIBLING, at the same frame level,
-- never receives the click: the bar swallows it. Parenting to the bar
-- and bumping the level is the fix. It used to be written inline at one
-- of the three title bars and forgotten at the other two, which is how
-- every close button in the addon ended up dead, so it lives here now.
--   kind == "close" -> CreateCloseButton(bar)
--   kind == "text"  -> CreateButton(bar, text, width, height)
----------------------------------------------------------------------
function Helpers:TitleBarButton(bar, kind, ...)
    local btn
    if kind == "close" then
        btn = self:CreateCloseButton(bar)
    else
        btn = self:CreateButton(bar, ...)
    end
    btn:SetFrameLevel(bar:GetFrameLevel() + 5)
    return btn
end

----------------------------------------------------------------------
-- Scrolling
----------------------------------------------------------------------

-- Skin a default WoW scrollbar: 8px, no arrows, a `well` track and a
-- `lineHi` thumb with 1px of margin. Works with UIPanelScrollFrameTemplate
-- and FauxScrollFrameTemplate.
function Helpers:SkinScrollBar(scrollFrame, scrollName)
    local scrollBar = scrollFrame.ScrollBar
        or (scrollName and _G[scrollName .. "ScrollBar"])
        or nil
    if not scrollBar then return end

    -- Hide the default Blizzard up/down buttons and thumb texture
    local upBtn = scrollBar.ScrollUpButton
        or _G[scrollName and (scrollName .. "ScrollBarScrollUpButton")]
    local downBtn = scrollBar.ScrollDownButton
        or _G[scrollName and (scrollName .. "ScrollBarScrollDownButton")]
    local thumbTex = scrollBar.ThumbTexture
        or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture())
        or _G[scrollName and (scrollName .. "ScrollBarThumbTexture")]

    if upBtn then upBtn:SetAlpha(0); upBtn:SetSize(1, 1); upBtn:EnableMouse(false) end
    if downBtn then downBtn:SetAlpha(0); downBtn:SetSize(1, 1); downBtn:EnableMouse(false) end
    if thumbTex then thumbTex:SetAlpha(0) end

    scrollBar:SetWidth(SCROLL_WIDTH)
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 2)

    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture(WHITE)
    track:SetVertexColor(C.well.r, C.well.g, C.well.b, 1)

    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    thumb:SetSize(SCROLL_WIDTH - 2, 40)
    scrollBar.customThumb = thumb
    Style:SkinScrollBar(track, thumb)

    local function UpdateThumb()
        local min, max = scrollBar:GetMinMaxValues()
        local val = scrollBar:GetValue()
        local trackHeight = scrollBar:GetHeight() or 100
        local thumbHeight = math.max(20, trackHeight * (trackHeight / (trackHeight + max - min + 1)))
        thumb:SetHeight(thumbHeight)

        -- Nothing to scroll: no thumb and no empty track either (#371).
        if max <= min then
            thumb:Hide()
            track:Hide()
            return
        end
        thumb:Show()
        track:Show()
        local ratio = (val - min) / (max - min)
        local travel = trackHeight - thumbHeight
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", -1, -(ratio * travel))
    end

    scrollBar:HookScript("OnValueChanged", function() UpdateThumb() end)
    scrollBar:HookScript("OnMinMaxChanged", function() UpdateThumb() end)
    scrollBar:HookScript("OnEnter", function() thumb:SetVertexColor(C.label.r, C.label.g, C.label.b, 1) end)
    scrollBar:HookScript("OnLeave", function() thumb:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1) end)
    GuildOS.Compat.After(0.05, UpdateThumb)

    return scrollBar
end

-- Create a scroll frame with the skinned scrollbar.
function Helpers:CreateScrollFrame(parent, name)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local scrollChild = CreateFrame("Frame", name and (name .. "Child") or nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)

    self:SkinScrollBar(scrollFrame, name)

    return scrollFrame, scrollChild
end

----------------------------------------------------------------------
-- Icons, badges, progress, metrics
----------------------------------------------------------------------

-- Create an icon with a 1px `line` frame over `well`. The game art is
-- cropped 8% per side to drop its own border; SetIconQuality recolours the frame.
function Helpers:CreateIcon(parent, size, iconPath)
    size = size or 32
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(size + 4, size + 4)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(frame) })
    frame:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    frame:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    if iconPath then
        icon:SetTexture(iconPath)
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = icon

    return frame
end

-- Frame an icon in its item-quality colour (never a palette colour).
function Helpers:SetIconQuality(iconFrame, quality)
    quality = quality or 1
    local color = GuildOS.QualityColors[quality] or GuildOS.QualityColors[1]
    iconFrame:SetBackdropBorderColor(color.r, color.g, color.b, 1)
end

-- Create a badge: mono 10 in a 1px frame, never filled. A danger badge takes
-- a danger frame; any other colour is text on a `line` frame. Gold is not a
-- badge colour (the officer mark included), so gold reads as `label`, the default.
function Helpers:CreateBadge(parent, text, color)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(b) })
    local fs = newText(b, nil, "badge")
    fs:SetPoint("CENTER", 0, 0)
    b.label = fs

    local function paint(col)
        if not col or col == C.gold or col == C.accent then col = C.label end
        local edge = (col == C.danger or col == C.red) and col or C.line
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
        fs:SetTextColor(col.r, col.g, col.b)
    end

    paint(color)
    fs:SetText(text or "")
    b:SetSize((fs:GetStringWidth() or 10) + 14, 16)
    function b:SetText(t, col)
        self.label:SetText(t or "")
        if col then paint(col) end
        self:SetWidth((self.label:GetStringWidth() or 10) + 14)
    end
    return b
end

-- Create an 8px progress bar: `well` track, 1px `line` frame, solid fill.
-- By default the fill is `textSoft` while in progress and ok when complete:
-- progress toward a goal (a profession rank, an attunement) is not a
-- failure, and gold is not a status. Pass `ramp = true` for a score that can
-- be bad (attendance): ok at 80% and up, warn from 60%, danger below.
function Helpers:CreateProgressBar(parent, width, height, ramp)
    width = width or 100
    height = height or 8

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(frame) })
    frame:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    frame:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)

    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetHeight(math.max(1, height - 2))
    bar:SetWidth(1)
    frame.bar = bar

    function frame:SetProgress(value)
        value = math.max(0, math.min(1, value or 0))
        -- The frame's current width: a caller may resize the bar after creating it (a table
        -- column); the width it was created with is the fallback before it is laid out.
        local w = self:GetWidth()
        if not w or w < 3 then w = width end
        self.bar:SetWidth(math.max(1, (w - 2) * value))
        local col
        if ramp then
            col = (value >= PROGRESS_OK and C.ok) or (value >= PROGRESS_WARN and C.warn) or C.danger
        else
            col = (value >= 1 and C.ok) or C.textSoft
        end
        self.bar:SetVertexColor(col.r, col.g, col.b, 1)
    end
    frame:SetProgress(0)

    return frame
end

-- Create a metric chip: a 1px gold rule across the top, a mono value under it
-- and a `label` caption under that. Never a box. chip:SetValue(text) updates the number.
function Helpers:CreateMetricChip(parent, value, caption, size)
    local chip = CreateFrame("Frame", nil, parent)
    local rule = self:CreateAccentLine(chip, 1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")

    local px = size or GuildOS.Fonts.metricValue.size
    local v = newText(chip, px, "metricValue")
    v:SetPoint("TOPLEFT", 0, -(1 + CHIP_PAD))
    v:SetTextColor(C.text.r, C.text.g, C.text.b)
    v:SetText(value or "")

    local l = newText(chip, nil, "caption")
    l:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -2)
    l:SetTextColor(C.label.r, C.label.g, C.label.b)
    l:SetText(caption or "")

    chip.value, chip.rule, chip.label = v, rule, l
    function chip:SetValue(t) self.value:SetText(t or "") end
    chip:SetSize(math.max(CHIP_MIN, v:GetStringWidth() or 0, l:GetStringWidth() or 0), px + CHIP_PAD + 20)
    return chip
end

-- Tooltip on hover: a paper title and white lines.
function Helpers:AddTooltip(frame, title, lines)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then
            GameTooltip:AddLine(title, C.text.r, C.text.g, C.text.b)
        end
        if lines then
            for _, line in ipairs(lines) do
                if type(line) == "table" then
                    GameTooltip:AddLine(line.text, line.r or 1, line.g or 1, line.b or 1, line.wrap)
                else
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------

-- Create a tab: mono `label` text at rest, paper when hovered, and the active
-- one gold with a 2px gold rule under it; `sub` makes it a sub-tab, with a
-- 1px rule. No box around it.
function Helpers:CreateTab(parent, text, width, sub)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(width or 100, 28)
    tab:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(tab) })
    tab:SetBackdropBorderColor(0, 0, 0, 0)

    local label = newText(tab, 11, "caption")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    tab.label = label
    fitToLabel(tab)

    local underline = tab:CreateTexture(nil, "OVERLAY")
    underline:SetTexture(WHITE)
    if sub then Helpers:Hairline(underline) else underline:SetHeight(2) end
    underline:SetPoint("BOTTOMLEFT", 2, 0)
    underline:SetPoint("BOTTOMRIGHT", -2, 0)
    underline:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    underline:Hide()
    tab.underline = underline
    Style:SkinTab(tab)

    local function paint(self, hovered)
        -- The Forever tab art marks the open tab itself; the gold label and rule are the flat style's mark.
        local flatActive = self.isActive and not self.__styleTab
        local ink = (flatActive and C.gold) or ((self.isActive or hovered) and C.text) or C.label
        self:SetBackdropColor(0, 0, 0, 0)
        self.label:SetTextColor(ink.r, ink.g, ink.b)
        self.underline:SetShown(flatActive and true or false)
        if self.__styleTab then Style:TabState(self) end
    end

    function tab:SetActive(active)
        tab.isActive = active
        paint(tab, false)
    end

    tab:SetActive(false)

    tab:SetScript("OnEnter", function(self) paint(self, true) end)
    tab:SetScript("OnLeave", function(self) paint(self, false) end)
    tab:SetScript("OnMouseDown", function(self) self:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1) end)
    tab:SetScript("OnMouseUp", function(self) paint(self, self:IsMouseOver()) end)

    return tab
end

-- Paint a sub-tab bar: sub-tabs sit on the `panel` surface.
function Helpers:StyleSubTabBar(bar)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints()
    bg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
    bar.bg = bg
    return bar
end

----------------------------------------------------------------------
-- Dialogs (#315)
-- GuildOS's own confirmation box, read from GuildOS.Dialogs. Never Blizzard's StaticPopup: its
-- frames are a pool the game's own dialogs share, and one opened from addon code leaves them
-- tainted. WoW: Forever's gamepad UI reads a field written there (`gamepadShown`) and has its
-- protected calls blocked from then on. A definition keeps StaticPopup's names: text, button1,
-- button2, OnAccept, OnCancel, OnShow, OnHide, hasEditBox, maxLetters, EditBoxOnEnterPressed,
-- EditBoxOnEscapePressed, timeout. Closing any way but button1 is a cancel.
----------------------------------------------------------------------
local DIALOG_WIDTH = 360
local dialogFrames = {}

local function acceptDialog(f)
    local def = f.def
    if not def then return end
    f.answered = true
    if def.OnAccept then GuildOS:SafeCall(def.OnAccept, f, f.data, f.data2) end
    f:Hide()
end

local function newDialog(i)
    local name = "GuildOSDialog" .. i
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetWidth(DIALOG_WIDTH)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120 - (i - 1) * 150)
    -- Above the windows that ask: the event editor, the ally card and the member detail are DIALOG.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    Helpers:StylePopup(f)
    f:Hide()

    f.text = Helpers:CreateText(f, "", 12)
    f.text:SetPoint("TOP", 0, -18)
    f.text:SetWidth(DIALOG_WIDTH - 40)

    -- `editBox` is where Compat.PopupEditBox looks, and its parent is the dialog, as the
    -- definitions' EditBox handlers expect.
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(240, 22)
    box:SetPoint("BOTTOM", 0, 48)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", function(self)
        local def = f.def
        if def and def.EditBoxOnEnterPressed then
            GuildOS:SafeCall(def.EditBoxOnEnterPressed, self, f.data)
        else
            acceptDialog(f)
        end
    end)
    box:SetScript("OnEscapePressed", function(self)
        local def = f.def
        if def and def.EditBoxOnEscapePressed then
            GuildOS:SafeCall(def.EditBoxOnEscapePressed, self, f.data)
        else
            f:Hide()
        end
    end)
    f.editBox = box

    f.button1 = Helpers:CreateButton(f, "", 130, 24)
    f.button1:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
    f.button1:SetScript("OnClick", function() acceptDialog(f) end)
    f.button2 = Helpers:CreateButton(f, "", 130, 24)
    f.button2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
    f.button2:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnHide", function(self)
        -- Still shown: it went with the whole interface (Alt-Z), and comes back with it.
        if self:IsShown() then return end
        local def, data = self.def, self.data
        self.def, self.data, self.data2 = nil, nil, nil
        if not def then return end
        if not self.answered and def.OnCancel then GuildOS:SafeCall(def.OnCancel, self, data, "clicked") end
        if def.OnHide then GuildOS:SafeCall(def.OnHide, self, data) end
    end)

    table.insert(UISpecialFrames, name)   -- ESC closes it
    dialogFrames[i] = f
    return f
end

-- Shows GuildOS.Dialogs[which], its text formatted with the two arguments, and returns the
-- frame (`data`, `data2` and `editBox` on it, as on a StaticPopup). Nil for an unknown name.
function GuildOS:ShowDialog(which, textArg1, textArg2, data)
    local def = self.Dialogs[which]
    if not def then return nil end

    -- The same question asked again takes its frame over; otherwise the first one free.
    local f
    for _, frame in ipairs(dialogFrames) do
        if frame:IsShown() and frame.which == which then f = frame; break end
    end
    if f then
        f.def = nil   -- replaced, not cancelled
        f:Hide()
    else
        for _, frame in ipairs(dialogFrames) do
            if not frame:IsShown() then f = frame; break end
        end
    end
    f = f or newDialog(#dialogFrames + 1)

    f.which, f.def, f.data, f.data2, f.answered = which, def, data, nil, false
    f.showing = (f.showing or 0) + 1
    local showing = f.showing
    f.text:SetText(string.format(def.text or "%s", textArg1 or "", textArg2 or ""))
    f.button1.label:SetText(def.button1)
    f.button2.label:SetText(def.button2 or CANCEL)
    f.editBox:SetShown(def.hasEditBox and true or false)
    f.editBox:SetMaxLetters(def.maxLetters or 0)
    f.editBox:SetText("")
    f:SetHeight(f.text:GetStringHeight() + (def.hasEditBox and 104 or 72))
    f:Show()
    if def.hasEditBox then f.editBox:SetFocus() end
    if def.OnShow then self:SafeCall(def.OnShow, f, data) end

    if (def.timeout or 0) > 0 then
        C_Timer.After(def.timeout, function()
            if f.showing == showing and f:IsShown() then f:Hide() end
        end)
    end
    return f
end
