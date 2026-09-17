----------------------------------------------------------------------
-- Guild OS - UI Helpers
-- Reusable factories for the "Forever" skin (design handoff §3-5 and §8;
-- docs/superpowers/specs/2026-09-14-forever-skin-design.md): opaque
-- surfaces told apart by a 1px line, gold as the only accent, IBM Plex
-- Mono for labels and numbers, and state changes that land in the same
-- frame. Public names, signatures and fields are unchanged from Obsidian.
----------------------------------------------------------------------
local Helpers = {}
BRutus.UI = Helpers

local C = BRutus.Colors
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA = "Interface\\AddOns\\GuildOS\\Media\\"

local BUTTON_HEIGHT  = 26    -- default button height (handoff §8)
local GLOW_BLEED     = 20    -- px the primary button's glow reaches past its edges
local GLOW_ALPHA     = 0.5   -- strength of that glow
local HOVER_LIFT     = 0.08  -- white added over gold while a primary button is hovered
local PRESSED_DARKEN = 0.85  -- gold under the cursor while a primary button is held
local DANGER_WASH    = 0.12  -- danger tint behind a hovered danger button
local DISABLED_GOLD  = 0.35  -- alpha of a disabled primary button or checkbox mark
local SHADOW_SIZE    = 12    -- px a popup's shadow reaches past its edges
local SHADOW_ALPHA   = C.shadow.a  -- darkest point of that shadow: the texture's own peak
local FADE_MAX       = 0.1   -- seconds; the only motion the skin allows
local SCROLL_WIDTH   = 8
local CHECK_BOX      = 14
local CHECK_MARK     = 8
local PROGRESS_OK    = 0.8   -- at or above: ok
local PROGRESS_WARN  = 0.6   -- at or above: gold; below: danger
local CHIP_RULE      = 34    -- px width of the gold rule under a metric value

-- A FontString with the skin's text settings: font by size (BRutus:ApplyFont),
-- no outline, no shadow.
local function newText(parent, size, role)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(fs, size, role)
    fs:SetShadowOffset(0, 0)
    return fs
end

----------------------------------------------------------------------
-- Surfaces
----------------------------------------------------------------------

-- Create a window surface (elevation 2): `bg` with a 1px `line` border.
function Helpers:CreatePanel(parent, name, level)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 1)
    f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    return f
end

-- Create an inset surface (elevation 1: table body, field, scroll area).
function Helpers:CreateDarkPanel(parent, name, level)
    local f = self:CreatePanel(parent, name, level)
    f:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    return f
end

-- Soft shadow behind a popup (elevation 4). Eight pieces of
-- Media/drop-shadow.tga around the frame and none under it, so it holds at
-- any size. `spread` is the reach in px; `alpha` scales the texture's peak.
function Helpers:CreateDropShadow(frame, spread, alpha)
    spread = spread or SHADOW_SIZE
    local strength = math.min(1, (alpha or SHADOW_ALPHA) / SHADOW_ALPHA)
    -- Parented to the frame so it shows, hides and moves with it; the lower
    -- level keeps it behind, and it sits entirely outside the frame's rectangle.
    local s = CreateFrame("Frame", nil, frame)
    s:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    s:SetAllPoints(frame)

    local function piece(left, right, top, bottom)
        local tex = s:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(MEDIA .. "drop-shadow.tga")
        tex:SetTexCoord(left, right, top, bottom)
        tex:SetAlpha(strength)
        return tex
    end

    -- Corners: one quadrant of the radial each, its centre on the frame's corner.
    local tl = piece(0, 0.5, 0, 0.5)
    tl:SetSize(spread, spread)
    tl:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT")
    local tr = piece(0.5, 1, 0, 0.5)
    tr:SetSize(spread, spread)
    tr:SetPoint("BOTTOMLEFT", frame, "TOPRIGHT")
    local bl = piece(0, 0.5, 0.5, 1)
    bl:SetSize(spread, spread)
    bl:SetPoint("TOPRIGHT", frame, "BOTTOMLEFT")
    local br = piece(0.5, 1, 0.5, 1)
    br:SetSize(spread, spread)
    br:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT")

    -- Edges: a thin slice through the middle of the radial, stretched along the side.
    local MID_A, MID_B = 0.49, 0.51
    local top = piece(MID_A, MID_B, 0, 0.5)
    top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT")
    top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT")
    top:SetHeight(spread)
    local bottom = piece(MID_A, MID_B, 0.5, 1)
    bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT")
    bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT")
    bottom:SetHeight(spread)
    local left = piece(0, 0.5, MID_A, MID_B)
    left:SetPoint("TOPRIGHT", frame, "TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT")
    left:SetWidth(spread)
    local right = piece(0.5, 1, MID_A, MID_B)
    right:SetPoint("TOPLEFT", frame, "TOPRIGHT")
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT")
    right:SetWidth(spread)

    frame.dropShadow = s
    return s
end

-- Fade a frame in when shown. Capped at 0.1s: the skin allows no other motion.
function Helpers:EnableFadeIn(frame, duration)
    duration = math.min(duration or FADE_MAX, FADE_MAX)
    frame:HookScript("OnShow", function(self)
        if self.__fadingDisabled then return end
        UIFrameFadeIn(self, duration, 0, 1)
    end)
end

-- Give a popup its elevation: the drop shadow and the short fade-in. Does NOT
-- touch backdrop colours; callers set those from the palette. `opts.noSheen`
-- is accepted and ignored (the skin has no sheen).
function Helpers:StylePopup(frame, opts)
    opts = opts or {}
    if not opts.noShadow then self:CreateDropShadow(frame, opts.shadowSize, opts.shadowAlpha) end
    if not opts.noFade then self:EnableFadeIn(frame, opts.fadeDuration) end
    return frame
end

-- Create a gold rule: 2px by default (under an active tab); pass 1 for a
-- metric chip or an active sub-tab.
function Helpers:CreateAccentLine(parent, thickness)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(thickness or 2)
    line:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    line.__solidColor = C.gold
    return line
end

-- Create a 1px separator in `line`.
function Helpers:CreateSeparator(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
    return line
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------

-- Create a window title: Spectral from 14px, paper.
function Helpers:CreateTitle(parent, text, size)
    local fs = newText(parent, size or 16)
    fs:SetTextColor(C.text.r, C.text.g, C.text.b)
    fs:SetText(text or "")
    return fs
end

-- Create body or table text: IBM Plex Mono below 14px, paper unless a colour is given.
function Helpers:CreateText(parent, text, size, r, g, b)
    local fs = newText(parent, size or 12)
    fs:SetTextColor(r or C.text.r, g or C.text.g, b or C.text.b)
    fs:SetText(text or "")
    return fs
end

-- Create a column or section header: IBM Plex Mono Medium in `label`.
function Helpers:CreateHeaderText(parent, text, size)
    local fs = newText(parent, size or 10, "colHeader")
    fs:SetTextColor(C.label.r, C.label.g, C.label.b)
    fs:SetText(text or "")
    return fs
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------

-- Paint one button state: "rest", "hover", "pressed" or "disabled". Internal.
-- Every colour lands in the same frame; there is no transition.
function Helpers:_ButtonState(btn, state)
    btn.__hovered = (state == "hover")
    local variant = btn.variant
    local base, text, border = btn.baseColor, btn.baseLabelColor, btn.baseBorder
    local r, g, b, a = base[1], base[2], base[3], base[4]
    local tr, tg, tb = text[1], text[2], text[3]
    local dy = 0

    if state == "disabled" then
        tr, tg, tb = C.disabled.r, C.disabled.g, C.disabled.b
        if variant == "primary" then a = DISABLED_GOLD end
    elseif state == "hover" then
        if variant == "primary" then
            r, g, b = math.min(1, r + HOVER_LIFT), math.min(1, g + HOVER_LIFT), math.min(1, b + HOVER_LIFT)
        elseif variant == "danger" then
            r, g, b, a = C.danger.r, C.danger.g, C.danger.b, DANGER_WASH
        else
            tr, tg, tb = C.text.r, C.text.g, C.text.b
            if variant == "secondary" then border = C.lineHi end
        end
    elseif state == "pressed" then
        if variant == "primary" then
            r, g, b = r * PRESSED_DARKEN, g * PRESSED_DARKEN, b * PRESSED_DARKEN
            dy = -1
        elseif variant ~= "ghost" then
            r, g, b, a = C.popup.r, C.popup.g, C.popup.b, 1
        end
    end

    btn:SetBackdropColor(r, g, b, a)
    if border then
        btn:SetBackdropBorderColor(border.r, border.g, border.b, 1)
    else
        btn:SetBackdropBorderColor(0, 0, 0, 0)
    end
    btn.label:SetTextColor(tr, tg, tb)
    -- Only a primary button moves its label, and only by the press: other
    -- buttons may have had their label re-anchored by the screen that owns them.
    if variant == "primary" then
        btn.label:ClearAllPoints()
        btn.label:SetPoint("CENTER", 0, dy)
    end
    if btn.underline then btn.underline:SetVertexColor(tr, tg, tb, 1) end
    if btn.glow then btn.glow:SetShown(variant == "primary" and state ~= "disabled") end
end

-- Create a button. Secondary by default (1px `line` border, paper text on no
-- fill); Helpers:SetButtonVariant switches it to primary, ghost or danger.
-- Toggle buttons keep calling btn:SetBaseColor so a resting colour survives
-- the hover; setting btn.baseLabelColor does the same for the label.
function Helpers:CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or BUTTON_HEIGHT)
    btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })

    local label = newText(btn, 11)
    label:SetPoint("CENTER")
    label:SetText(text or "")
    btn.label = label

    btn.variant = "secondary"
    btn.baseColor = { C.well.r, C.well.g, C.well.b, 0 }
    btn.baseLabelColor = { C.text.r, C.text.g, C.text.b }
    btn.baseBorder = C.line

    function btn:SetBaseColor(r, g, b, a)
        self.baseColor = { r, g, b, a or 1 }
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

    self:_ButtonState(btn, "rest")
    return btn
end

-- Switch a button to one of the handoff's variants: "primary" (gold fill
-- with a glow; one per screen), "secondary", "ghost" (underlined label, no
-- border) or "danger". Returns the button.
function Helpers:SetButtonVariant(btn, variant)
    variant = variant or "secondary"
    btn.variant = variant
    local label = btn.label
    if variant == "primary" then
        btn.baseColor = { C.gold.r, C.gold.g, C.gold.b, 1 }
        btn.baseLabelColor = { C.onGold.r, C.onGold.g, C.onGold.b }
        btn.baseBorder = C.gold
        BRutus:ApplyFont(label, 11, "colHeader")  -- IBM Plex Mono Medium
        if not btn.glow then
            local glow = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
            glow:SetTexture(MEDIA .. "glow-gold.tga")
            glow:SetBlendMode("ADD")
            glow:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, GLOW_ALPHA)
            glow:SetPoint("TOPLEFT", -GLOW_BLEED, GLOW_BLEED)
            glow:SetPoint("BOTTOMRIGHT", GLOW_BLEED, -GLOW_BLEED)
            btn.glow = glow
        end
    else
        BRutus:ApplyFont(label, 11)
        local ink = (variant == "ghost" and C.label) or (variant == "danger" and C.danger) or C.text
        btn.baseLabelColor = { ink.r, ink.g, ink.b }
        btn.baseColor = { C.well.r, C.well.g, C.well.b, 0 }
        btn.baseBorder = (variant == "danger" and C.danger) or (variant ~= "ghost" and C.line) or nil
        if variant == "ghost" and not btn.underline then
            local u = btn:CreateTexture(nil, "ARTWORK")
            u:SetTexture(WHITE)
            u:SetHeight(1)
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
function Helpers:AttachSaveButton(editBox, onSave, opts)
    opts = opts or {}
    local parent = opts.parent or editBox:GetParent()
    local label  = opts.text or (BRutus.L and BRutus.L["Save"]) or "Save"
    local h = opts.height or editBox:GetHeight()
    if not h or h < 22 then h = 22 end

    local btn = self:CreateButton(parent, label, opts.width or 60, h)
    if opts.point then
        btn:SetPoint(unpack(opts.point))
    else
        btn:SetPoint("LEFT", editBox, "RIGHT", opts.gap or 6, 0)
    end

    local function commit()
        onSave(editBox)
        editBox:ClearFocus()
    end
    btn:SetScript("OnClick", commit)
    editBox:SetScript("OnEnterPressed", commit)

    editBox.saveButton = btn
    return btn
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

    -- A texture one pixel larger on every side, under the fill, is the border.
    local border = cb:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetTexture(WHITE)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
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

    local function paint()
        local enabled = cb:IsEnabled()
        -- GetChecked() returns true or nil (never false) in TBC.
        mark:SetShown(cb:GetChecked() and true or false)
        mark:SetAlpha(enabled and 1 or DISABLED_GOLD)
        local edge = (not enabled and C.disabled) or (cb.__hovered and C.lineHi) or C.line
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
    cb:SetScript("OnMouseDown", function() fill:SetVertexColor(C.popup.r, C.popup.g, C.popup.b, 1) end)
    cb:SetScript("OnMouseUp", function() fill:SetVertexColor(C.well.r, C.well.g, C.well.b, 1) end)
    cb:HookScript("OnDisable", paint)
    cb:HookScript("OnEnable", paint)
    paint()

    local label = newText(frame, 11)
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    label:SetTextColor(C.text.r, C.text.g, C.text.b)
    label:SetText(labelText or "")
    frame.label = label

    frame.checkbox = cb
    return frame
end

-- Create a close button (×): `label` at rest, paper on a `popup` square when hovered.
function Helpers:CreateCloseButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(20, 20)
    btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
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

    local function UpdateThumb()
        local min, max = scrollBar:GetMinMaxValues()
        local val = scrollBar:GetValue()
        local trackHeight = scrollBar:GetHeight() or 100
        local thumbHeight = math.max(20, trackHeight * (trackHeight / (trackHeight + max - min + 1)))
        thumb:SetHeight(thumbHeight)

        if max <= min then
            thumb:Hide()
            return
        end
        thumb:Show()
        local ratio = (val - min) / (max - min)
        local travel = trackHeight - thumbHeight
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", -1, -(ratio * travel))
    end

    scrollBar:HookScript("OnValueChanged", function() UpdateThumb() end)
    scrollBar:HookScript("OnMinMaxChanged", function() UpdateThumb() end)
    scrollBar:HookScript("OnEnter", function() thumb:SetVertexColor(C.label.r, C.label.g, C.label.b, 1) end)
    scrollBar:HookScript("OnLeave", function() thumb:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1) end)
    BRutus.Compat.After(0.05, UpdateThumb)

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
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
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
    local color = BRutus.QualityColors[quality] or BRutus.QualityColors[1]
    iconFrame:SetBackdropBorderColor(color.r, color.g, color.b, 1)
end

-- Create a badge: mono 10 in a 1px frame. A gold badge (the officer mark) is
-- the only filled one, gold with `onGold` text; a danger badge takes a danger
-- frame; any other colour is text on a `line` frame. Defaults to `label`.
function Helpers:CreateBadge(parent, text, color)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local fs = newText(b, 10)
    fs:SetPoint("CENTER", 0, 0)
    b.label = fs

    local function paint(col)
        col = col or C.label
        if col == C.gold or col == C.accent then
            b:SetBackdropColor(C.gold.r, C.gold.g, C.gold.b, 1)
            b:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1)
            fs:SetTextColor(C.onGold.r, C.onGold.g, C.onGold.b)
        else
            local edge = (col == C.danger or col == C.red) and col or C.line
            b:SetBackdropColor(0, 0, 0, 0)
            b:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
            fs:SetTextColor(col.r, col.g, col.b)
        end
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
-- By default the fill is gold while in progress and ok when complete:
-- progress toward a goal (a profession rank, an attunement) is not a
-- failure. Pass `ramp = true` for a score that can be bad (attendance):
-- ok at 80% and up, gold from 60%, danger below.
function Helpers:CreateProgressBar(parent, width, height, ramp)
    width = width or 100
    height = height or 8

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
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
        self.bar:SetWidth(math.max(1, (width - 2) * value))
        local col
        if ramp then
            col = (value >= PROGRESS_OK and C.ok) or (value >= PROGRESS_WARN and C.gold) or C.danger
        else
            col = (value >= 1 and C.ok) or C.gold
        end
        self.bar:SetVertexColor(col.r, col.g, col.b, 1)
    end
    frame:SetProgress(0)

    return frame
end

-- Create a metric chip: a mono value, a 1px gold rule and a `labelDim`
-- caption under it. Never a box. chip:SetValue(text) updates the number.
function Helpers:CreateMetricChip(parent, value, caption, size)
    local chip = CreateFrame("Frame", nil, parent)
    local v = newText(chip, size, "metricValue")
    v:SetPoint("TOPLEFT")
    v:SetTextColor(C.text.r, C.text.g, C.text.b)
    v:SetText(value or "")

    local rule = self:CreateAccentLine(chip, 1)
    rule:SetWidth(CHIP_RULE)
    rule:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -3)

    local l = newText(chip, 10, "caption")
    l:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -3)
    l:SetTextColor(C.labelDim.r, C.labelDim.g, C.labelDim.b)
    l:SetText(caption or "")

    chip.value, chip.rule, chip.label = v, rule, l
    function chip:SetValue(t) self.value:SetText(t or "") end
    chip:SetSize(math.max(CHIP_RULE, v:GetStringWidth() or 0, l:GetStringWidth() or 0), (size or 22) + 20)
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

-- Create a tab: `label` text at rest, paper when hovered or active, and a 2px
-- gold rule under the active one; `sub` makes it a sub-tab, with a 1px rule.
-- No box around it.
function Helpers:CreateTab(parent, text, width, sub)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(width or 100, 28)
    tab:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    tab:SetBackdropBorderColor(0, 0, 0, 0)

    local label = newText(tab, 11)
    label:SetPoint("CENTER")
    label:SetText(text or "")
    tab.label = label

    local underline = tab:CreateTexture(nil, "OVERLAY")
    underline:SetTexture(WHITE)
    underline:SetHeight(sub and 1 or 2)
    underline:SetPoint("BOTTOMLEFT", 2, 0)
    underline:SetPoint("BOTTOMRIGHT", -2, 0)
    underline:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    underline:Hide()
    tab.underline = underline

    local function paint(self, hovered)
        local ink = (self.isActive or hovered) and C.text or C.label
        self:SetBackdropColor(0, 0, 0, 0)
        self.label:SetTextColor(ink.r, ink.g, ink.b)
        self.underline:SetShown(self.isActive and true or false)
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
