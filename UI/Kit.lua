----------------------------------------------------------------------
-- Guild OS - The Officers' Room's and Settings' kit (specs/salao/fase3.md, second pass)
--
-- What the officers' screens, Settings and the floating windows draw with, on top of UI/Helpers.lua:
--   * the paper's inks: Kit.PAPER reads as GuildOS.Colors with the wood's text and status colours swapped
--     for the ones that read on a parchment card (the mockup's .card colours); a screen drawn on a card
--     takes it as its `C`, so `C.text` is the paper's ink there;
--   * a class's colour on the paper (the mockup's `.card .c-*`): the game's class colours are made for a
--     dark ground, a priest's white is invisible on the paper;
--   * a screen as a parchment card with its title (Kit:Screen), a row's tan rule (Kit:Rule), a status
--     badge (Kit:Badge);
--   * the floating window (the mockup's .fw): a metal frame, a brown gradient header with the title in
--     Cinzel gold, a round red close, a dark body and a footer of buttons on the right (Kit:Float), or the
--     same chrome put on a frame that already exists (Kit:Dress).
-- Frame-free until called, so a file can read Kit lazily and still load where it is absent (a test).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local Style = GuildOS.Style

local Kit = {}
GuildOS.Kit = Kit

local function hex(s)
    return { r = tonumber(s:sub(1, 2), 16) / 255, g = tonumber(s:sub(3, 4), 16) / 255,
             b = tonumber(s:sub(5, 6), 16) / 255, a = 1 }
end

-- The statuses on the paper: the mockup's #2f6e33 (ok), the badges' deep amber, red and blue.
Kit.INK = {
    ok   = hex("2f6e33"),
    warn = hex("a0560f"),
    bad  = hex("8f1b0b"),
    info = hex("1d4f99"),
    mute = hex("8a7a5e"),
    epic = hex("6c2fb0"),
}

-- GuildOS.Colors as a card's text reads it: the ink, the softer ink and the statuses of the paper; every
-- other key (a line, a fill, the gold of a selection) is the shared one.
local SWAP = {
    text = C.paperInk, textSoft = C.paperSoft, silver = C.paperSoft, label = C.paperSoft,
    textDim = C.paperSoft, labelDim = C.paperSoft,
    ok = Kit.INK.ok, green = Kit.INK.ok, online = Kit.INK.ok,
    warn = Kit.INK.warn, danger = Kit.INK.bad, red = Kit.INK.bad,
    info = Kit.INK.info, blue = Kit.INK.info, epic = Kit.INK.epic,
    offline = Kit.INK.mute, disabled = Kit.INK.mute,
    gold = C.paperTitle, accent = C.paperTitle, gold2 = C.paperTitle,
    row1 = { r = 0, g = 0, b = 0, a = 0 }, row2 = { r = 0, g = 0, b = 0, a = 0 },
    rowHover = { r = 0.62, g = 0.45, b = 0.2, a = 0.12 },
    border = C.paperLine, separator = C.paperLine, line = C.paperLine,
}
Kit.PAPER = setmetatable({}, { __index = function(_, k)
    local v = SWAP[k]
    if v ~= nil then return v end
    return C[k]
end })

-- A screen file's colours: the paper's while the kit is loaded, the shared ones where it is not.
function Kit.Colors()
    return Kit.PAPER
end

-- The class colours on the paper (the mockup's `.card .c-*`), darker so they read on it.
Kit.CLASS_INK = {
    PRIEST = hex("666666"), ROGUE = hex("857612"), HUNTER = hex("4f7319"), MAGE = hex("16758d"),
    PALADIN = hex("a8457a"), DRUID = hex("b35400"), SHAMAN = hex("0b4fa0"), WARRIOR = hex("7e5a33"),
    WARLOCK = hex("4b4cb0"), DEATHKNIGHT = hex("a3202f"), MONK = hex("00995a"), DEMONHUNTER = hex("7a2a9a"),
    EVOKER = hex("23705f"),
}

-- r, g, b of `classFile` on the paper; the paper's ink for an unknown class.
function Kit:ClassInk(classFile)
    local c = classFile and self.CLASS_INK[tostring(classFile):upper()]
    if c then return c.r, c.g, c.b end
    return C.paperInk.r, C.paperInk.g, C.paperInk.b
end

-- A row's tan line along its bottom (the mockup's `.card .t td` border), in place of the wood's stripes.
function Kit:Rule(row, color)
    local t = row.__kitRule
    if not t then
        t = row:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetPoint("BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", 0, 0)
        UI:Hairline(t)
        row.__kitRule = t
    end
    local c = color or { r = 0.878, g = 0.8, b = 0.624 }   -- #e0cc9f
    t:SetVertexColor(c.r, c.g, c.b, 1)
    return t
end

-- A status badge (the mockup's .badge): kind "ok", "warn", "bad", "info", "mute" or "epic".
local BADGE = { ok = "ok", warn = "warn", bad = "danger", info = "info", epic = "epic" }
function Kit:Badge(parent, text, kind)
    local col = BADGE[kind] and C[BADGE[kind]] or C.paperSoft
    return UI:CreateBadge(parent, text, col)
end

-- A screen on a parchment card: the card (titled, never upper case) and the body inside it, where the
-- screen's parts go. Place the card; the body follows it, CARD_PAD in and CARD_TOP down.
function Kit:Screen(parent, title, opts)
    local card = UI:CreateCard(parent, title, opts)
    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", UI.CARD_PAD, -UI.CARD_TOP)
    body:SetPoint("BOTTOMRIGHT", -UI.CARD_PAD, UI.CARD_PAD - 4)
    card.body = body
    return card, body
end

----------------------------------------------------------------------
-- Floating windows (the mockup's .fw)
----------------------------------------------------------------------
Kit.HEADER_H = 32   -- the header's height; a dressed frame's content starts under it
Kit.FOOT_H = 40     -- a footer's height (a 24px button row with its padding)
Kit.PAD = 12        -- the body's side padding

local FW_BODY = hex("1d130a")
local FW_RULE = hex("3a2a17")

-- Give `f` the floating window's chrome: the metal frame over a dark body, a header bar (the title bar's
-- warm gradient, a metal line under it) with `title` in Cinzel gold and `sub` beside it in the soft ink, a
-- round red close at its right (opts.noClose: none; opts.onClose: what it runs, else f:Hide()), dragging
-- by the header when f is movable. Returns f, with f.header, f.titleText, f.subText and f.closeBtn, and
-- f:SetTitle(title, sub). The frame's own content must start Kit.HEADER_H down.
function Kit:Dress(f, title, opts)
    opts = opts or {}
    if f.SetBackdrop then f:SetBackdrop(nil) end
    Style:Paint(f, "window")
    if f.SetBackdropColor then f:SetBackdropColor(FW_BODY.r, FW_BODY.g, FW_BODY.b, 0.98) end
    f.__dark = true   -- the controls on it take the wood's colours (UI:OnPaper)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 3, -3)
    header:SetPoint("TOPRIGHT", -3, -3)
    header:SetHeight(self.HEADER_H - 3)
    header:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
    Style:Paint(header, "titlebar")
    local line = header:CreateTexture(nil, "BORDER")
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:Hairline(line)
    line:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    f.header = header

    local t = header:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(t, 14, "windowTitle")
    t:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    t:SetPoint("LEFT", header, "LEFT", 10, 0)
    f.titleText = t

    local sub = header:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(sub, 11, "caption")
    sub:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    sub:SetPoint("LEFT", t, "RIGHT", 8, 0)
    f.subText = sub

    if not opts.noClose then
        local close = UI:TitleBarButton(header, "close")
        close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
        close:SetScript("OnClick", function()
            if opts.onClose then opts.onClose(f) else f:Hide() end
        end)
        sub:SetPoint("RIGHT", close, "LEFT", -8, 0)
        f.closeBtn = close
    else
        sub:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    end

    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing(); f.moved = true end)

    function f:SetTitle(text, subText)
        GuildOS:SetTitleText(self.titleText, text or "")
        self.subText:SetText(subText or "")
    end
    f:SetTitle(title, opts.sub)
    UI:EnableFadeIn(f)
    return f
end

-- A footer (the mockup's .ff): a strip along the bottom, a dark line over it, its buttons laid from the
-- right. Returns the strip; strip:Lay(buttons...) places them right to left in the order given (the first
-- given is the rightmost, the window's main answer).
function Kit:Footer(f)
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", 3, 3)
    foot:SetPoint("BOTTOMRIGHT", -3, 3)
    foot:SetHeight(self.FOOT_H - 3)
    local rule = foot:CreateTexture(nil, "BORDER")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetPoint("TOPLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", 0, 0)
    UI:Hairline(rule)
    rule:SetVertexColor(FW_RULE.r, FW_RULE.g, FW_RULE.b, 1)
    function foot:Lay(...)
        local prev
        for i = 1, select("#", ...) do
            local b = select(i, ...)
            if b and b:IsShown() then
                b:ClearAllPoints()
                if prev then b:SetPoint("RIGHT", prev, "LEFT", -6, 0)
                else b:SetPoint("RIGHT", foot, "RIGHT", -Kit.PAD + 3, -1) end
                prev = b
            end
        end
    end
    f.foot = foot
    return foot
end

-- A new floating window: Kit:Dress on a fresh frame on UIParent. opts: name (a global name; Escape closes
-- it), width, height, strata (default "DIALOG"), sub, noClose, onClose, foot (a footer, Kit:Footer), point
-- ({ "CENTER", 0, 60 } by default), movable (default true). f.body is the area under the header (and over
-- the footer), Kit.PAD in at the sides.
function Kit:Float(title, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    f:SetSize(opts.width or 360, opts.height or 160)
    local p = opts.point or { "CENTER", 0, 60 }
    f:SetPoint(p[1], UIParent, p[1], p[2] or 0, p[3] or 0)
    f:SetFrameStrata(opts.strata or "DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if opts.movable ~= false then f:SetMovable(true) end
    f:Hide()
    self:Dress(f, title, opts)
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", self.PAD, -(self.HEADER_H + 8))
    if opts.foot then
        self:Footer(f)
        body:SetPoint("BOTTOMRIGHT", -self.PAD, self.FOOT_H + 4)
    else
        body:SetPoint("BOTTOMRIGHT", -self.PAD, 10)
    end
    f.body = body
    if opts.name and UISpecialFrames then table.insert(UISpecialFrames, opts.name) end
    return f
end

----------------------------------------------------------------------
-- Parts on the paper: UI/Helpers.lua draws them for the paper itself now (#449); these stay for their callers.
----------------------------------------------------------------------
-- UI:CreateCheckbox, which on a card is the paper's light field with its tan line, the card's dark red mark and
-- the paper's ink. Returns the checkbox frame.
function Kit:Checkbox(parent, labelText, size)
    return UI:CreateCheckbox(parent, labelText, size)
end

-- UI:CreateSeparator, in the paper's tan on a card (the wood's line elsewhere).
function Kit:Separator(parent)
    return UI:CreateSeparator(parent)
end

-- UI:CreateSectionTitle, whose rule takes the paper's tan on a card.
function Kit:SectionTitle(parent, text, first)
    return UI:CreateSectionTitle(parent, text, first)
end

-- UI:CreateTab's pill on a card: its label at rest takes the quiet button's ink, the door's cream being
-- invisible on the paper; the open one keeps the soft gold pill. CreateTab does this for a tab made on the
-- paper; this is for one moved there after. Returns the tab.
function Kit:PaperTab(tab)
    if not UI:OnPaper(tab) or tab.__paperInk then return tab end
    tab.__paperInk = true
    tab:SetActive(tab.isActive)
    return tab
end

----------------------------------------------------------------------
-- GuildOS's own confirmation box (GuildOS:ShowDialog, UI/Helpers.lua) as the mockup's modal: a parchment card
-- (the mockup's `.modal .card`), its question in the paper's ink, the answer in the crimson primary button and
-- the others in the paper's quiet ones. Helpers builds the frame; GuildOS:ShowDialog has the kit dress it the
-- first time, before it lays the text and sizes the box (a dressing after the sizing overlapped on the first show).
----------------------------------------------------------------------
function Kit:DressDialog(f)
    if not f or f.__kitDressed then return f end
    f.__kitDressed = true
    Style:Paint(f, "paper")
    if f.text then
        GuildOS:ApplyFont(f.text, 13, "reading")
        f.text:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
    end
    for i, b in ipairs({ f.button1, f.button2, f.button3 }) do
        b.__onPaper = true
        UI:SetButtonVariant(b, i == 1 and "primary" or "secondary")
    end
    return f
end
