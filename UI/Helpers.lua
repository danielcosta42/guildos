----------------------------------------------------------------------
-- Guild OS - UI Helpers
-- Reusable UI factory functions for the "Obsidian" premium style:
-- near-black neutral surfaces, subtle vertical gradients for depth, a
-- restrained desaturated-violet accent that only appears on interaction,
-- and softened champagne gold reserved for the brand / key emphasis.
----------------------------------------------------------------------
local Helpers = {}
BRutus.UI = Helpers

local C = BRutus.Colors
local FONT = (BRutus.Fonts and BRutus.Fonts.normal) or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Lighten/darken a colour table by a factor (>1 lightens, <1 darkens).
local function shade(col, f)
    return math.min(1, col.r * f), math.min(1, col.g * f), math.min(1, col.b * f)
end

----------------------------------------------------------------------
-- Internal: paint a subtle top-down gradient sheen onto a frame so flat
-- panels gain depth without looking colourful.
----------------------------------------------------------------------
local function applySheen(frame, topAlpha)
    topAlpha = topAlpha or 0.05
    local sheen = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetTexture(WHITE)
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("BOTTOMRIGHT", -1, 1)
    -- Lighter at the top, fading to nothing — pure white at very low alpha
    -- reads as a soft sheen on a dark surface.
    sheen:SetGradient("VERTICAL",
        CreateColor(1, 1, 1, 0),
        CreateColor(1, 1, 1, topAlpha))
    frame.sheen = sheen
    return sheen
end

----------------------------------------------------------------------
-- Create a premium background panel with subtle gradient + border
----------------------------------------------------------------------
function Helpers:CreatePanel(parent, name, level)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    f:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })
    f:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, C.panel.a)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    applySheen(f, 0.045)
    return f
end

----------------------------------------------------------------------
-- Create a dark sub-panel (for insets)
----------------------------------------------------------------------
function Helpers:CreateDarkPanel(parent, name, level)
    local f = self:CreatePanel(parent, name, level)
    f:SetBackdropColor(C.panelDark.r, C.panelDark.g, C.panelDark.b, C.panelDark.a)
    if f.sheen then f.sheen:SetGradient("VERTICAL", CreateColor(1,1,1,0), CreateColor(1,1,1,0.03)) end
    return f
end

----------------------------------------------------------------------
-- Create a soft drop shadow behind a frame (4 fading edge strips).
-- Portable: uses WHITE8x8 + gradients, no external textures required.
----------------------------------------------------------------------
function Helpers:CreateDropShadow(frame, spread, alpha)
    spread = spread or 14
    alpha  = alpha or C.shadow.a or 0.5
    -- Parent the shadow to the frame itself so it shows/hides and moves with
    -- it. The strips sit entirely OUTSIDE the frame's rectangle, so a lower
    -- frame level keeps them behind the window without being clipped.
    local s = CreateFrame("Frame", nil, frame)
    s:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    s:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    s:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local function strip(point1, rel1, point2, rel2, orient, nearTop)
        local t = s:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(WHITE)
        t:SetPoint(point1, frame, rel1, 0, 0)
        t:SetPoint(point2, frame, rel2, 0, 0)
        local near = CreateColor(0, 0, 0, alpha)
        local far  = CreateColor(0, 0, 0, 0)
        if nearTop then
            t:SetGradient(orient, far, near)   -- darkest toward the frame
        else
            t:SetGradient(orient, near, far)
        end
        return t
    end

    -- Top
    local top = strip("BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", "VERTICAL", false)
    top:ClearAllPoints()
    top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(spread)
    -- Bottom
    local bot = strip("TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", "VERTICAL", true)
    bot:ClearAllPoints()
    bot:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
    bot:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bot:SetHeight(spread)
    -- Left
    local left = s:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(WHITE)
    left:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(spread)
    left:SetGradient("HORIZONTAL", CreateColor(0,0,0,0), CreateColor(0,0,0,alpha))
    -- Right
    local right = s:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(WHITE)
    right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(spread)
    right:SetGradient("HORIZONTAL", CreateColor(0,0,0,alpha), CreateColor(0,0,0,0))

    frame.dropShadow = s
    return s
end

----------------------------------------------------------------------
-- Fade a frame in when shown (cheap, runs once per OnShow).
----------------------------------------------------------------------
function Helpers:EnableFadeIn(frame, duration)
    duration = duration or 0.18
    frame:HookScript("OnShow", function(self)
        if self.__fadingDisabled then return end
        UIFrameFadeIn(self, duration, 0, 1)
    end)
end

----------------------------------------------------------------------
-- Give any pop-up frame the same premium depth as the main window:
-- a soft top sheen, an outer drop shadow, and a fade-in on show.
-- Does NOT touch the backdrop colours — callers set those from the
-- palette themselves. Call once, after the frame's level/strata is set.
----------------------------------------------------------------------
function Helpers:StylePopup(frame, opts)
    opts = opts or {}
    if not opts.noSheen  then applySheen(frame, opts.sheen or 0.04) end
    if not opts.noShadow then self:CreateDropShadow(frame, opts.shadowSize or 14, opts.shadowAlpha or 0.5) end
    if not opts.noFade   then self:EnableFadeIn(frame, opts.fadeDuration or 0.15) end
    return frame
end

----------------------------------------------------------------------
-- Create a glowing accent line (horizontal separator)
----------------------------------------------------------------------
function Helpers:CreateAccentLine(parent, thickness)
    thickness = thickness or 2
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(thickness)
    -- Horizontal fade so the accent reads as a soft highlight, not a hard bar.
    line:SetGradient("HORIZONTAL",
        CreateColor(C.accent.r, C.accent.g, C.accent.b, 0.0),
        CreateColor(C.accent.r, C.accent.g, C.accent.b, 0.55))
    line.__solidColor = C.accent
    return line
end

----------------------------------------------------------------------
-- Create a separator line (dimmer)
----------------------------------------------------------------------
function Helpers:CreateSeparator(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetVertexColor(C.separator.r, C.separator.g, C.separator.b, C.separator.a)
    return line
end

----------------------------------------------------------------------
-- Create premium gold title text
----------------------------------------------------------------------
function Helpers:CreateTitle(parent, text, size)
    size = size or 18
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    fs:SetText(text or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    return fs
end

----------------------------------------------------------------------
-- Create standard text (off-white body text with a soft shadow)
----------------------------------------------------------------------
function Helpers:CreateText(parent, text, size, r, g, b)
    size = size or 12
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetTextColor(r or C.text.r, g or C.text.g, b or C.text.b)
    fs:SetText(text or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    return fs
end

----------------------------------------------------------------------
-- Create header text (for column headers) — muted, letter-spaced feel
----------------------------------------------------------------------
function Helpers:CreateHeaderText(parent, text, size)
    size = size or 11
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b, 0.85)
    fs:SetText(text or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.7)
    return fs
end

----------------------------------------------------------------------
-- Create a premium styled button (subtle gradient, accent on hover)
----------------------------------------------------------------------
function Helpers:CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 28)
    btn:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })
    btn:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.92)
    btn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)

    -- Subtle top sheen for a raised feel
    applySheen(btn, 0.05)

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 11, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetTextColor(C.text.r, C.text.g, C.text.b)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 0.7)
    label:SetText(text or "")
    btn.label = label

    -- Default visual state. Toggle buttons should call SetBaseColor so the
    -- resting colour persists after the cursor leaves (the hover effect is
    -- only temporary).
    btn.baseColor = { C.bg2.r, C.bg2.g, C.bg2.b, 0.92 }
    btn.baseLabelColor = { C.text.r, C.text.g, C.text.b }

    function btn:SetBaseColor(r, g, b, a)
        self.baseColor = { r, g, b, a or 1 }
        if not self.__hovered then
            self:SetBackdropColor(r, g, b, a or 1)
        end
    end

    btn:SetScript("OnEnter", function(self)
        self.__hovered = true
        self:SetBackdropColor(C.accent.r * 0.32, C.accent.g * 0.32, C.accent.b * 0.32, 0.95)
        self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.85)
        self.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    end)
    btn:SetScript("OnLeave", function(self)
        self.__hovered = false
        local b = self.baseColor
        self:SetBackdropColor(b[1], b[2], b[3], b[4])
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        local l = self.baseLabelColor
        self.label:SetTextColor(l[1], l[2], l[3])
    end)

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
-- Create a styled checkbox with label (real checkmark glyph)
----------------------------------------------------------------------
function Helpers:CreateCheckbox(parent, labelText, size)
    size = size or 20
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size + 200, size)

    local cb = CreateFrame("CheckButton", nil, frame)
    cb:SetSize(size, size)
    cb:SetPoint("LEFT", 0, 0)

    -- Box background
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints()
    bg:SetVertexColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.95)

    local border = cb:CreateTexture(nil, "BORDER")
    border:SetTexture(WHITE)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetVertexColor(C.border.r, C.border.g, C.border.b, 0.7)

    -- Real checkmark texture (tinted gold), shown when checked
    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetPoint("CENTER", 0, 0)
    check:SetSize(size + 4, size + 4)
    check:SetVertexColor(C.gold.r, C.gold.g, C.gold.b)
    check:Hide()
    cb.checkMark = check

    local function refresh(checked)
        if checked then
            check:Show()
            border:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.9)
        else
            check:Hide()
            border:SetVertexColor(C.border.r, C.border.g, C.border.b, 0.7)
        end
    end

    cb:SetScript("OnClick", function(self)
        refresh(self:GetChecked())
        if self.onChanged then self:onChanged(self:GetChecked()) end
    end)

    local origSetChecked = cb.SetChecked
    cb.SetChecked = function(self, val)
        origSetChecked(self, val)
        refresh(val)
    end

    cb:SetScript("OnEnter", function()
        bg:SetVertexColor(shade(C.bg2, 1.6))
    end)
    cb:SetScript("OnLeave", function()
        bg:SetVertexColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.95)
    end)

    -- Reflect disabled state visually
    cb:HookScript("OnDisable", function()
        bg:SetVertexColor(C.bg0.r, C.bg0.g, C.bg0.b, 0.9)
        check:SetVertexColor(C.offline.r, C.offline.g, C.offline.b)
    end)
    cb:HookScript("OnEnable", function()
        check:SetVertexColor(C.gold.r, C.gold.g, C.gold.b)
    end)

    -- Label
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 11, "OUTLINE")
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    label:SetTextColor(C.text.r, C.text.g, C.text.b)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 0.6)
    label:SetText(labelText or "")
    frame.label = label

    frame.checkbox = cb
    return frame
end

----------------------------------------------------------------------
-- Create close button (X) — subtle, reveals red tint on hover
----------------------------------------------------------------------
function Helpers:CreateCloseButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(20, 20)
    btn:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })
    btn:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.0)
    btn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.0)

    local x = btn:CreateFontString(nil, "OVERLAY")
    x:SetFont(FONT, 14, "OUTLINE")
    x:SetPoint("CENTER", 0, 0)
    x:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    x:SetText("\195\151")  -- multiplication sign (×) reads cleaner than letter X
    btn.x = x

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.70, 0.18, 0.20, 0.85)
        self:SetBackdropBorderColor(0.90, 0.30, 0.32, 0.9)
        self.x:SetTextColor(1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.0)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.0)
        self.x:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    end)

    return btn
end

----------------------------------------------------------------------
-- Skin a default WoW scrollbar into a thin, subtle track+thumb
-- Works with both UIPanelScrollFrameTemplate and FauxScrollFrameTemplate
----------------------------------------------------------------------
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

    -- Make the scrollbar thin and positioned inside the frame
    scrollBar:SetWidth(5)
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 2)

    -- Track background
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture(WHITE)
    track:SetVertexColor(C.bg0.r, C.bg0.g, C.bg0.b, 0.5)

    -- Custom thumb overlay
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.45)
    thumb:SetSize(5, 40)
    scrollBar.customThumb = thumb

    -- Update thumb position on scroll
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
        local yOff = -(ratio * travel)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, yOff)
    end

    scrollBar:HookScript("OnValueChanged", function() UpdateThumb() end)
    scrollBar:HookScript("OnMinMaxChanged", function() UpdateThumb() end)
    -- Brighten thumb on hover for feedback
    scrollBar:HookScript("OnEnter", function() thumb:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.75) end)
    scrollBar:HookScript("OnLeave", function() thumb:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.45) end)
    -- Initial
    C_Timer.After(0.05, UpdateThumb)

    return scrollBar
end

----------------------------------------------------------------------
-- Create a scroll frame with custom scrollbar
----------------------------------------------------------------------
function Helpers:CreateScrollFrame(parent, name)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local scrollChild = CreateFrame("Frame", name and (name .. "Child") or nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)

    -- Apply thin scrollbar skin
    self:SkinScrollBar(scrollFrame, name)

    return scrollFrame, scrollChild
end

----------------------------------------------------------------------
-- Create an icon frame with border
----------------------------------------------------------------------
function Helpers:CreateIcon(parent, size, iconPath)
    size = size or 32
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(size + 4, size + 4)
    frame:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    if iconPath then
        icon:SetTexture(iconPath)
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Trim default icon borders
    frame.icon = icon

    return frame
end

----------------------------------------------------------------------
-- Create a quality-colored icon border
----------------------------------------------------------------------
function Helpers:SetIconQuality(iconFrame, quality)
    quality = quality or 1
    local color = BRutus.QualityColors[quality] or BRutus.QualityColors[1]
    iconFrame:SetBackdropBorderColor(color.r, color.g, color.b, 0.9)
end

----------------------------------------------------------------------
-- Create a small rounded "badge"/pill for counts or status labels.
----------------------------------------------------------------------
function Helpers:CreateBadge(parent, text, color)
    color = color or C.accent
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(color.r * 0.22, color.g * 0.22, color.b * 0.22, 0.9)
    b:SetBackdropBorderColor(color.r, color.g, color.b, 0.55)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 10, "OUTLINE")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetText(text or "")
    b.label = fs
    b:SetSize((fs:GetStringWidth() or 10) + 14, 16)
    function b:SetText(t, col)
        self.label:SetText(t or "")
        if col then
            self:SetBackdropColor(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.9)
            self:SetBackdropBorderColor(col.r, col.g, col.b, 0.55)
            self.label:SetTextColor(col.r, col.g, col.b)
        end
        self:SetWidth((self.label:GetStringWidth() or 10) + 14)
    end
    return b
end

----------------------------------------------------------------------
-- Create a progress bar
----------------------------------------------------------------------
function Helpers:CreateProgressBar(parent, width, height)
    width = width or 100
    height = height or 8

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })
    frame:SetBackdropColor(C.bg0.r, C.bg0.g, C.bg0.b, 0.85)
    frame:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)

    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetHeight(height - 2)
    bar:SetWidth(1)
    bar:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.85)
    frame.bar = bar

    -- Soft top highlight on the fill for a glassy look
    local gloss = frame:CreateTexture(nil, "OVERLAY")
    gloss:SetTexture(WHITE)
    gloss:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    gloss:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, -math.max(1, (height - 2) / 2))
    gloss:SetGradient("VERTICAL", CreateColor(1,1,1,0), CreateColor(1,1,1,0.18))
    frame.gloss = gloss

    function frame:SetProgress(value)
        value = math.max(0, math.min(1, value or 0))
        local barWidth = math.max(1, (width - 2) * value)
        self.bar:SetWidth(barWidth)

        if value >= 1 then
            self.bar:SetVertexColor(C.green.r, C.green.g, C.green.b, 0.9)
        elseif value > 0 then
            self.bar:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.85)
        else
            self.bar:SetVertexColor(C.red.r, C.red.g, C.red.b, 0.5)
        end
    end

    return frame
end

----------------------------------------------------------------------
-- Create a tooltip-enhanced frame
----------------------------------------------------------------------
function Helpers:AddTooltip(frame, title, lines)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then
            GameTooltip:AddLine(title, C.gold.r, C.gold.g, C.gold.b)
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
-- Create a tab button with an active underline indicator
----------------------------------------------------------------------
function Helpers:CreateTab(parent, text, width)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(width or 100, 28)
    tab:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })

    local label = tab:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 11, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 0.6)
    label:SetText(text or "")
    tab.label = label

    -- Active underline indicator
    local underline = tab:CreateTexture(nil, "OVERLAY")
    underline:SetTexture(WHITE)
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", 2, 0)
    underline:SetPoint("BOTTOMRIGHT", -2, 0)
    underline:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 1)
    underline:Hide()
    tab.underline = underline

    function tab:SetActive(active)
        tab.isActive = active
        if active then
            tab:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
            tab:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
            tab.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            tab.underline:Show()
        else
            tab:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.9)
            tab:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.25)
            tab.label:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            tab.underline:Hide()
        end
    end

    tab:SetActive(false)

    tab:SetScript("OnEnter", function(self)
        if not self.isActive then
            self:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 1.0)
            self.label:SetTextColor(C.text.r, C.text.g, C.text.b)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.isActive then
            self:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 0.9)
            self.label:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        end
    end)

    return tab
end
