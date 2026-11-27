----------------------------------------------------------------------
-- Guild OS - UI Helpers
-- Reusable factories for the Salão's look (specs/salao/fase3.md): dark cards
-- and fields on the wood, parchment cards with their own ink, a crimson
-- primary button, dark and cream (quiet) buttons, pills for tabs and filters,
-- round class avatars, Cinzel for titles and Alegreya Sans for the rest, and
-- state changes that land in the same frame. Every screen is built through
-- them, so every screen takes the look. Public names, signatures and fields
-- are kept; a frame's backdrop colour calls land on its rounded art.
-- The art and its layout live in Core/Style.lua.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Helpers = {}
GuildOS.UI = Helpers

local C = GuildOS.Colors
local Style = GuildOS.Style
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- The spacing standard (#449): UI/Spacing.lua, the one scale every screen and every primitive below reads.
local SP = GuildOS.Spacing
Helpers.SP = SP

local BUTTON_HEIGHT  = SP.FIELD    -- default button height
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

-- Create a surface: a window at the top level (the metal frame), a dark card inside a screen (#122).
function Helpers:CreatePanel(parent, name, level)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    local top = parent == nil or parent == UIParent
    Style:Paint(f, top and "window" or "panel")
    if top then f.__popupTop = true end   -- a floating window: its title and close go in the header (#449)
    return f
end

-- An older floating window (UI:StylePopup or UI:CreatePanel on UIParent) wears the mockup's .fw chrome the
-- moment it makes its title or its close (#449): Kit:Chrome's metal frame, dark body and brown header, the
-- title (the first UI:CreateTitle on the frame) in Cinzel gold on the header's left and the close (the first
-- UI:CreateCloseButton) round and red at its right, wherever the window asked to put them. Returns the
-- header, or nil for anything else (a card, a dropdown, a frame Kit:Dress dressed itself).
local function popupHeader(frame, what)
    if not frame or not rawget(frame, "__popupTop") or rawget(frame, what) then return nil end
    local Kit = rawget(GuildOS, "Kit")
    if not Kit or not Kit.Chrome then return nil end
    if frame.header and not rawget(frame, "__chromed") then return nil end   -- Kit:Dress's own header
    frame.__chromed = true
    frame[what] = true
    return Kit:Chrome(frame)
end
-- `region` placed at the header's `point` (LEFT or RIGHT) whatever the window asks: its x kept, its y the
-- header's middle. The window's own SetPoint calls land here.
local function pinToHeader(region, header, point, pad)
    local setPoint = region.SetPoint
    region.SetPoint = function(self, _, rel, _, x)
        if type(rel) == "number" then x = rel end
        x = math.abs(tonumber(x) or pad)
        x = math.max(pad, math.min(x, 24))
        self:ClearAllPoints()
        setPoint(self, point, header, point, point == "LEFT" and x or -x, 0)
    end
    region:SetPoint(point, pad)
end

-- Create an inset surface on the wood (a table body, a scroll area, a side bar's well).
function Helpers:CreateDarkPanel(parent, name, level)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetFrameLevel(level or 1)
    Style:Paint(f, "well")
    return f
end

-- Whether `frame` sits on a parchment card (a card made by CreateCard, or anything inside one): controls
-- there take the paper's colours (a quiet button, a light field, a dark red title).
function Helpers:OnPaper(frame)
    local f, depth = frame, 0
    while f and depth < 12 do
        if rawget(f, "__paper") then return true end
        if rawget(f, "__dark") then return false end
        f = f.GetParent and f:GetParent() or nil
        depth = depth + 1
    end
    return false
end

-- A frame's width as its anchors will make it, where GetWidth cannot say yet. The game lays a frame placed by
-- its anchors out on the next drawn frame: until then (a window built and filled in the same call, a frame
-- never shown) GetWidth answers 0. A text given `GetWidth() - x` then got a negative width and drew nothing at
-- all (the login digest's lines, #449). This reads the anchors instead: a frame on both a left and a right
-- point of the same frame is that frame's width less the offsets, SetAllPoints its whole width; its own set
-- width wins. Returns 0 when nothing says (a caller keeps its own floor).
function Helpers:LaidWidth(frame, depth)
    if not frame then return 0 end
    local w = frame.GetWidth and frame:GetWidth() or 0
    if type(w) == "number" and w > 0 then return w end
    depth = (depth or 0) + 1
    if depth > 12 then return 0 end
    local okN, n = pcall(function() return frame:GetNumPoints() end)
    if not okN or type(n) ~= "number" then return 0 end
    local left, right
    for i = 1, n do
        local point, rel, relPoint, x = frame:GetPoint(i)
        if type(rel) == "number" then rel, relPoint, x = nil, point, rel end   -- SetPoint("TOPLEFT", x, y), as given
        if type(relPoint) == "number" then relPoint, x = point, relPoint end   -- SetPoint("TOPLEFT", other, x, y)
        if type(rel) == "string" then rel = _G[rel] end
        rel = rel or frame:GetParent()
        relPoint = relPoint or point
        x = tonumber(x) or 0
        if point and point:find("LEFT") and relPoint:find("LEFT") then left = left or { rel, x }
        elseif point and point:find("RIGHT") and relPoint:find("RIGHT") then right = right or { rel, x } end
    end
    if left and right and left[1] == right[1] then
        local pw = self:LaidWidth(left[1], depth)
        if pw > 0 then return math.max(0, pw - left[2] + right[2]) end
    end
    return 0
end

-- The width a text laid `inset` px inside `frame` may take: LaidWidth less the inset, never under `floor`
-- (default 40). A negative or zero width is never handed to a FontString this way.
function Helpers:TextWidth(frame, inset, floor)
    return math.max(floor or 40, self:LaidWidth(frame) - (inset or 0))
end

----------------------------------------------------------------------
-- Inks on the paper (#449): one mapping for every colour a screen draws on a parchment card
--
-- The game's colours are made for a dark ground: a common item's white, a priest's white, a rogue's yellow,
-- an uncommon item's light green and the wood's status colours vanish on the paper. On the paper every such
-- colour goes through here: an item's quality and a class take the paper's own inks, a status the kit's,
-- and any other colour (one in a string's |cff… code, an item link's) is darkened, keeping its hue, until it
-- reads at 4.5:1 or better against the paper. Off the paper they are the game's.
----------------------------------------------------------------------
local function lin(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
-- WCAG relative luminance of r, g, b (0..1).
function Helpers.Luminance(r, g, b) return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) end
-- The contrast ratio between two colours ({ r, g, b }).
function Helpers.Contrast(a, b)
    local la, lb = Helpers.Luminance(a.r, a.g, a.b), Helpers.Luminance(b.r, b.g, b.b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end
Helpers.PAPER_CONTRAST = 4.6   -- the least a text on the paper reads at (WCAG AA is 4.5)

-- r, g, b made to read at PAPER_CONTRAST against the paper (and its light field), hue kept: darkened on the
-- parchment, lightened on the dark mode's paper (GuildOS.PaperReadable, Core/Data.lua); unchanged when it does.
function Helpers.PaperSafe(r, g, b)
    return GuildOS.PaperReadable(r or 0, g or 0, b or 0)
end

local function hexRGB(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end
-- Write an ink into t[key] (the table is kept: the screens hold it): on the parchment `light` (hex) made safe; on
-- the dark paper `wood` ({ r, g, b }, the colour the game or the wood draws it in) made safe, `light` without one.
local function putInk(t, key, light, wood)
    local r, g, b
    if GuildOS:IsDarkPaper() and wood and wood.r then r, g, b = wood.r, wood.g, wood.b else r, g, b = hexRGB(light) end
    r, g, b = Helpers.PaperSafe(r, g, b)
    local c = t[key] or {}
    c.r, c.g, c.b, c.a = r, g, b, 1
    t[key] = c
end

-- An item's quality on the paper: poor dark grey, common the paper's ink, uncommon dark green, rare blue,
-- epic purple, legendary dark orange, artifact dark gold, heirloom dark cyan. On the dark paper, the game's own
-- colours (a common item the paper's ink), lightened where they would not read.
Helpers.QUALITY_INK = {}
local QUALITY_LIGHT = { [0] = "5f5a52", [1] = "3a2a17", [2] = "1a6e00", [3] = "0b4fa0", [4] = "6c2fb0",
    [5] = "a34a00", [6] = "7a6326", [7] = "0a6e8a", [8] = "0a6e8a" }
-- The game's quality colours as their codes read (lower case), to know a quality from a link's colour.
local QUALITY_HEX = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["0070de"] = 3, ["a335ee"] = 4,
    ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}
Helpers.QUALITY_HEX = QUALITY_HEX
-- The statuses on the paper (the kit's badges' inks); on the dark paper, the wood's own.
Helpers.STATUS_INK = {}
local STATUS_LIGHT = { ok = "2f6e33", warn = "8f4a0c", bad = "8f1b0b", info = "1d4f99", mute = "6f6450", epic = "6c2fb0" }
local STATUS_WOOD = { ok = "ok", warn = "warn", bad = "danger", info = "info", mute = "labelDim", epic = "epic" }
-- A class on the paper (the mockup's `.card .c-*`): each made safe on the paper, a priest's white dark grey,
-- a rogue's yellow dark gold. On the dark paper the game's class colours, lightened where they would not read.
Helpers.CLASS_INK = {}
local CLASS_LIGHT = { PRIEST = "666666", ROGUE = "857612", HUNTER = "4f7319", MAGE = "16758d", PALADIN = "a8457a",
    DRUID = "b35400", SHAMAN = "0b4fa0", WARRIOR = "7e5a33", WARLOCK = "4b4cb0", DEATHKNIGHT = "a3202f",
    MONK = "00995a", DEMONHUNTER = "7a2a9a", EVOKER = "23705f" }

local paperSwap   -- PaperRGB's table: made the first time it is asked, and again after the paper changes
local function buildInks()
    for q, h in pairs(QUALITY_LIGHT) do
        local wood = GuildOS.QualityColors and GuildOS.QualityColors[q]
        if q == 1 then wood = C.paperInk end
        putInk(Helpers.QUALITY_INK, q, h, wood)
    end
    for k, h in pairs(STATUS_LIGHT) do putInk(Helpers.STATUS_INK, k, h, C[STATUS_WOOD[k]]) end
    for k, h in pairs(CLASS_LIGHT) do putInk(Helpers.CLASS_INK, k, h, GuildOS.ClassColors and GuildOS.ClassColors[k]) end
    paperSwap = nil
end
buildInks()
GuildOS:OnPaperChange(buildInks)

local function onPaperSurface(surface)
    if surface == "paper" or surface == true then return true end
    if surface == "wood" or not surface then return false end
    return Helpers:OnPaper(surface)
end

-- r, g, b of a colour as `surface` (a frame, "paper" or "wood") reads it. kind:
--   "quality"  value: an item's quality (0..8)
--   "class"    value: a class file (PRIEST)
--   "status"   value: ok, warn, bad, info, mute or epic
--   "rgb"      value: { r, g, b } (any colour meant for the wood)
function Helpers:InkFor(surface, kind, value)
    local paper = onPaperSurface(surface)
    if kind == "quality" then
        local q = tonumber(value) or 1
        if paper then local c = Helpers.QUALITY_INK[q] or C.paperInk; return c.r, c.g, c.b end
        local c = GuildOS.QualityColors and GuildOS.QualityColors[q]
        if c then return c.r, c.g, c.b end
        local Compat = GuildOS.Compat
        if Compat and Compat.GetItemQualityColor then
            local r, g, b = Compat.GetItemQualityColor(q)
            if r then return r, g, b end
        end
        return 1, 1, 1
    elseif kind == "class" then
        local file = value and tostring(value):upper()
        if paper then local c = file and Helpers.CLASS_INK[file] or C.paperInk; return c.r, c.g, c.b end
        return GuildOS:GetClassColor(value)
    elseif kind == "status" then
        if paper then local c = Helpers.STATUS_INK[value] or C.paperSoft; return c.r, c.g, c.b end
        local wood = { ok = C.ok, warn = C.warn, bad = C.danger, info = C.info, mute = C.disabled, epic = C.epic }
        local c = wood[value] or C.textSoft
        return c.r, c.g, c.b
    end
    local c = type(value) == "table" and value or C.text
    if paper then return Helpers.PaperRGB(c.r, c.g, c.b) end
    return c.r, c.g, c.b
end

-- `text` with every colour code in it made safe for the paper: a quality's colour (an item link's) becomes the
-- paper's quality ink, retail's |cnIQn: too, and any other colour is darkened until it reads. On the wood (a
-- frame that is not on the paper, or "wood") it is returned unchanged.
function Helpers:PaperText(text, surface)
    if text == nil then return text end
    text = tostring(text)
    if surface ~= nil and not onPaperSurface(surface) then return text end
    local function code(r, g, b) return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end
    text = text:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(_, hex)
        hex = hex:lower()
        local q = QUALITY_HEX[hex]
        if q then local c = Helpers.QUALITY_INK[q]; return code(c.r, c.g, c.b) end
        local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
        return code(Helpers.PaperRGB(r, g, b))
    end)
    text = text:gsub("|cnIQ(%d+):", function(n)
        local c = Helpers.QUALITY_INK[tonumber(n)] or C.paperInk
        return code(c.r, c.g, c.b)
    end)
    return text
end

-- A colour's six hex digits (lower case).
local function hexOf(r, g, b)
    return string.format("%02x%02x%02x", math.floor((r or 0) * 255 + 0.5), math.floor((g or 0) * 255 + 0.5), math.floor((b or 0) * 255 + 0.5))
end
-- The wood's colours by their value, and what the paper prints for each.
local function swapTable()
    if paperSwap then return paperSwap end
    local S = Helpers.STATUS_INK
    paperSwap = {}
    local function put(c, to) if c and c.r then paperSwap[hexOf(c.r, c.g, c.b)] = paperSwap[hexOf(c.r, c.g, c.b)] or to end end
    -- The inks first: a status sharing a value with one keeps the ink's meaning.
    put(C.text, C.paperInk); put(C.textSoft, C.paperSoft); put(C.silver, C.paperSoft); put(C.label, C.paperSoft)
    put(C.ok, S.ok); put(C.green, S.ok); put(C.online, S.ok)
    put(C.danger, S.bad); put(C.red, S.bad); put(C.warn, S.warn); put(C.info, S.info); put(C.blue, S.info)
    put(C.epic, S.epic); put(C.offline, S.mute); put(C.disabled, S.mute); put(C.labelDim, S.mute); put(C.textDim, S.mute)
    put(C.gold, C.paperTitle); put(C.gold2, C.paperTitle); put(C.accent, C.paperTitle)
    -- The game's quality colours (a common item's white is the paper's ink).
    for hx, q in pairs(QUALITY_HEX) do paperSwap[hx] = paperSwap[hx] or Helpers.QUALITY_INK[q] end
    for file, ink in pairs(Helpers.CLASS_INK) do
        local c = GuildOS.ClassColors and GuildOS.ClassColors[file]
        if c and not paperSwap[hexOf(c.r, c.g, c.b)] then paperSwap[hexOf(c.r, c.g, c.b)] = ink end
    end
    return paperSwap
end

-- r, g, b of a colour meant for the wood as the paper prints it: the wood's statuses become the paper's (ok,
-- warn, bad, info), its inks the paper's ink and soft ink, its golds the paper's title red, the game's quality
-- and class colours the paper's quality and class inks, and anything else is darkened until it reads
-- (PaperSafe). Every paper screen's local "on the paper" shade calls this.
function Helpers.PaperRGB(r, g, b)
    local to = swapTable()[hexOf(r, g, b)]
    if to then return to.r, to.g, to.b end
    return Helpers.PaperSafe(r or 0, g or 0, b or 0)
end

-- A palette colour `c` (one of GuildOS.Colors, a quality's, a class's, any { r, g, b }) as `surface` reads it,
-- as a table: on the paper PaperRGB's colour; off it, `c` itself.
function Helpers:Ink(surface, c)
    c = c or C.text
    if not onPaperSurface(surface) then return c end
    local r, g, b = Helpers.PaperRGB(c.r, c.g, c.b)
    return { r = r, g = g, b = b, a = c.a or 1 }
end

-- fs:SetTextColor of a colour meant for the wood (a class's, a quality's, a status's: r, g, b or a table),
-- taking the paper's shade of it where `fs` is drawn on the paper (PaperRGB). Off the paper, the colour as given.
function Helpers:SetInk(fs, r, g, b)
    if type(r) == "table" then r, g, b = r.r, r.g, r.b end
    r, g, b = r or 1, g or 1, b or 1
    if Helpers:OnPaper(fs) then r, g, b = Helpers.PaperRGB(r, g, b) end
    fs:SetTextColor(r, g, b)
end

-- SetText on `fs` with its colour codes made safe where it is drawn on the paper (PaperText).
function Helpers:SetInkText(fs, text)
    fs:SetText(Helpers:OnPaper(fs) and Helpers:PaperText(text) or text)
end

-- A card, as the mockup's .card and .dark: a parchment card (its paper, grain, darker bottom edge and soft
-- shadow, a dark red title in Cinzel) or, with opts.dark, a dark card on the wood with a soft gold title.
-- opts.link: a link at the title's right (an underlined word that opens something), card.link; set its click
-- with card.link:SetScript("OnClick", ...). card.ink and card.soft are the colours its text takes. The title is
-- never upper case. Size and place it as any frame; its content starts CARD_TOP down, CARD_PAD in.
Helpers.CARD_PAD, Helpers.CARD_TOP = SP.PAD, SP.TOP
function Helpers:CreateCard(parent, title, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local dark = opts.dark and true or false
    Style:Paint(f, dark and "panel" or "paper")
    f.__dark = dark or nil
    f.ink = dark and C.text or C.paperInk
    f.soft = dark and C.textSoft or C.paperSoft
    f.lineColor = dark and C.line or C.paperLine
    f.isCard = true   -- the room harness (tools/room-cards.lua) holds everything drawn on it inside it
    local t = newText(f, nil, "sectionTitle")
    local tc = dark and C.gold2 or C.paperTitle
    t:SetTextColor(tc.r, tc.g, tc.b)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    GuildOS:ApplyFont(t, SP.TITLE, "sectionTitle")
    t:SetPoint("TOPLEFT", Helpers.CARD_PAD, -Helpers.CARD_PAD)
    GuildOS:SetTitleText(t, title or "")
    f.title = t
    if opts.link then
        local link = self:SetButtonVariant(self:CreateButton(f, opts.link, 40, 18), "ghost")
        link:SetWidth(math.ceil(link.label:GetStringWidth()) + 4)
        link:SetPoint("TOPRIGHT", -Helpers.CARD_PAD + 2, -(Helpers.CARD_PAD - 1))
        t:SetPoint("RIGHT", link, "LEFT", -8, 0)
        f.link = link
    else
        t:SetPoint("RIGHT", f, "RIGHT", -Helpers.CARD_PAD, 0)
    end
    return f
end

-- The wood behind a screen (the window's view): boards, the fire's glow, snow in Winter Veil; drawn on
-- `frame` over `area`.
function Helpers:PaintWood(frame, area) return Style:PaintWood(frame, area) end

-- The first character of `name` (a whole UTF-8 sequence), for an avatar's or the crest's initial.
local function initial(name)
    return tostring(name or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
end
Helpers.Initial = initial

-- A round class avatar (the mockup's .av): a disc in the class's colour, lit from the top left, a soft gold
-- ring, a warm glow from 32px up, and the name's initial. avatar:SetMember(name, classFile, away) paints it;
-- away greys it out. avatar:SetCount(n) makes it the dashed "+n" disc. A Button: script its click.
function Helpers:CreateAvatar(parent, size, glow)
    size = size or 40
    local a = CreateFrame("Button", nil, parent)
    a:SetSize(size, size)
    if glow == nil then glow = size >= 32 end
    if glow then
        local halo = Style:Texture(a, "halo", "BACKGROUND", 0)
        halo:SetPoint("CENTER")
        halo:SetSize(size * 1.5, size * 1.5)
        a.halo = halo
    end
    a.disc = Style:Texture(a, "disc", "ARTWORK", 0)
    a.disc:SetAllPoints()
    a.ring = Style:Texture(a, "ring", "ARTWORK", 1)
    a.ring:SetAllPoints()
    a.dash = Style:Texture(a, "ring-dash", "ARTWORK", 2)
    a.dash:SetAllPoints()
    a.dash:Hide()
    a.letter = newText(a, math.max(SP.META, math.floor(size * 0.42)), "button")
    a.letter:SetPoint("CENTER", 0, 0)
    -- The class's own crest from the game, cut round inside the disc (the disc's colour shows as a thin
    -- band around it, the gold ring over both). Where a client has no mask it stays square, trimmed of the
    -- crest's own frame. No class known: the initial, as before.
    local inset = math.max(2, math.floor(size * 0.1 + 0.5))
    a.icon = a:CreateTexture(nil, "ARTWORK", nil, 0)
    a.icon:SetPoint("TOPLEFT", inset, -inset)
    a.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    a.icon:Hide()
    local Compat = GuildOS.Compat
    a.iconMask = Compat and Compat.NewMask and Compat.NewMask(a, Style.ART and Style.ART.circle, inset)
    if a.iconMask then Compat.AddMask(a.icon, a.iconMask) end
    function a:SetClassIcon(classFile)
        local tc = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if type(tc) ~= "table" or not tc[4] then self.icon:Hide(); return false end
        -- Trimmed a little: the crest's painted edge would read as a second ring.
        local l, r, t, b = tc[1], tc[2], tc[3], tc[4]
        local dx, dy = (r - l) * 0.08, (b - t) * 0.08
        self.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        self.icon:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
        self.icon:Show()
        return true
    end
    function a:SetMember(name, classFile, away)
        local cc = (classFile and GuildOS.ClassColors[classFile]) or C.textSoft
        -- The disc runs from a lighter cut of the class's colour to a darker one, as the mockup's gradient.
        local r, g, b = cc.r + (1 - cc.r) * 0.3, cc.g + (1 - cc.g) * 0.3, cc.b + (1 - cc.b) * 0.3
        if away then
            local grey = (r + g + b) / 3 * 0.55
            r, g, b = grey, grey, grey
        end
        self.disc:SetVertexColor(r, g, b, 1)
        self.disc:Show()
        local ring = away and C.lineHi or C.gold2
        self.ring:SetVertexColor(ring.r, ring.g, ring.b, 1)
        self.ring:Show()
        self.dash:Hide()
        if self.halo then self.halo:SetShown(not away) end
        -- Dark classes (the shaman's blue) take a light initial.
        local lum = 0.3 * cc.r + 0.59 * cc.g + 0.11 * cc.b
        if lum < 0.45 then self.letter:SetTextColor(1, 1, 1) else self.letter:SetTextColor(0.14, 0.08, 0.04) end
        if self:SetClassIcon(classFile) then
            self.letter:SetText("")
            if self.icon.SetDesaturated then self.icon:SetDesaturated(away and true or false) end
            self.icon:SetVertexColor(away and 0.6 or 1, away and 0.6 or 1, away and 0.6 or 1, 1)
        else
            self.letter:SetText(initial(name))
        end
    end
    function a:SetCount(n)
        self.icon:Hide()
        self.disc:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
        self.ring:Hide()
        self.dash:SetVertexColor(C.gold2.r, C.gold2.g, C.gold2.b, 1)
        self.dash:Show()
        if self.halo then self.halo:Hide() end
        self.letter:SetTextColor(C.gold2.r, C.gold2.g, C.gold2.b)
        self.letter:SetText("+" .. tostring(n or 0))
    end
    return a
end

-- A round glyph (the mockup's .glyph on the Guild wall): a lit sphere in one colour and a letter on it.
-- glyph:Set(letter, color).
function Helpers:CreateGlyph(parent, size)
    size = size or 26
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(size, size)
    g.orb = Style:Texture(g, "orb", "ARTWORK", 0)
    g.orb:SetAllPoints()
    g.letter = newText(g, math.max(SP.META, math.floor(size * 0.42)), "button")
    g.letter:SetPoint("CENTER", 0, 0)
    g.letter:SetTextColor(1, 1, 1)
    function g:Set(letter, color)
        local c = color or C.paperMark
        -- The paper's inks as a fill under the white letter: their marks (the same on the parchment; on the dark
        -- paper the inks are light, the marks stay deep).
        if c == C.paperSoft then c = C.paperMark elseif c == C.paperTitle then c = C.paperMarkTitle end
        self.orb:SetVertexColor(c.r, c.g, c.b, 1)
        self.letter:SetText(letter or "")
    end
    return g
end

-- An empty state as the standard draws it (#449, specs/salao/fase3.md "Espaçamento"): a centred block on a parchment
-- card, never a grey line in a corner. A round glyph (`glyph`, a letter or a symbol), one line (wrapped) and the
-- main action when there is one. Centre it where the screen's list would be: es:SetPoint("CENTER", host). es:Set(text,
-- actionText, onClick) fills it (no actionText: no button) and sizes the card; es.text, es.glyph, es.action.
function Helpers:CreateEmptyState(parent, glyph, width)
    local es = self:CreateCard(parent, "")
    es.title:Hide()
    es:SetWidth(width or 380)
    es.glyph = self:CreateGlyph(es, 40)
    es.glyph:SetPoint("TOP", 0, -SP.PAD - 4)
    es.glyph:Set(glyph or "?", C.paperTitle)
    es.text = self:CreateText(es, "", SP.BODY, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    es.text:SetPoint("TOP", es.glyph, "BOTTOM", 0, -SP.FIELD_GAP)
    es.text:SetJustifyH("CENTER")
    es.text:SetWordWrap(true)
    es.action = self:SetButtonVariant(self:CreateButton(es, "", 120, SP.FIELD), "primary")
    es.action:Hide()
    function es:Set(text, actionText, onClick)
        local w = self:GetWidth() or 380
        self.text:SetWidth(math.max(60, w - 2 * SP.PAD))
        self.text:SetText(text or "")
        local h = SP.PAD + 4 + 40 + SP.FIELD_GAP + math.ceil(self.text:GetStringHeight() or 14)
        if actionText then
            self.action.label:SetText(actionText)
            self.action:SetWidth(math.ceil(self.action.label:GetStringWidth() or 80) + 32)
            self.action:ClearAllPoints()
            self.action:SetPoint("TOP", self.text, "BOTTOM", 0, -SP.SECTION)
            self.action:SetScript("OnClick", onClick)
            self.action:Show()
            h = h + SP.SECTION + SP.FIELD
        else
            self.action:Hide()
        end
        self:SetHeight(h + SP.PAD)
    end
    return es
end

-- A red count (the Officers' Room's, an entry's): a small pill, hidden at zero. count:SetCount(n).
function Helpers:CreateCount(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(18, 15)
    local fill = Style:Three(f, "pill", "ARTWORK", 0)
    fill:SetColor(C.count)
    f.fill = fill
    f.text = newText(f, SP.META, "badge")
    f.text:SetPoint("CENTER", 0, 0)
    f.text:SetTextColor(1, 1, 1)
    function f:SetCount(n)
        n = tonumber(n) or 0
        self.text:SetText(n > 99 and "99+" or tostring(n))
        self:SetWidth(math.max(16, math.ceil(self.text:GetStringWidth() or 0) + 10))
        self:SetShown(n > 0)
    end
    f:SetCount(0)
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
    -- A floating window on the screen takes the .fw chrome with its title (popupHeader).
    if frame.GetParent and frame:GetParent() == UIParent and not opts.noChrome then frame.__popupTop = true end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(C.metal2.r, C.metal2.g, C.metal2.b, 1)
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

-- Create a 1px separator in `line` (the paper's tan on a parchment card).
function Helpers:CreateSeparator(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    Helpers:Hairline(line)
    local c = Helpers:OnPaper(parent) and C.paperLine or C.line
    line:SetVertexColor(c.r, c.g, c.b, 1)
    return line
end

----------------------------------------------------------------------
-- Text
----------------------------------------------------------------------

-- Create a window title: Cinzel, gold (dark red on a parchment card).
function Helpers:CreateTitle(parent, text, size)
    local header = popupHeader(parent, "__fwTitled")
    if header then
        local fs = newText(header, math.min(size or 15, 15), "windowTitle")
        fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        pinToHeader(fs, header, "LEFT", 10)
        GuildOS:SetTitleText(fs, text or "")
        return fs
    end
    local fs = newText(parent, size or 15, "windowTitle")
    local c = Helpers:OnPaper(parent) and C.paperTitle or C.gold
    fs:SetTextColor(c.r, c.g, c.b)
    GuildOS:SetTitleText(fs, text or "")
    return fs
end

-- Create body or table text: Alegreya Sans, the wood's ink (the paper's on a card) unless a colour is given.
function Helpers:CreateText(parent, text, size, r, g, b)
    local fs = newText(parent, size or SP.BODY)
    local ink = (r == nil and Helpers:OnPaper(parent)) and C.paperInk or C.text
    fs:SetTextColor(r or ink.r, g or ink.g, b or ink.b)
    fs:SetText(text or "")
    return fs
end

-- Create a column header: Cinzel, small, gold on the wood and dark red on the paper (the mockup's .t th).
-- A section of a screen takes CreateSectionTitle instead.
function Helpers:CreateHeaderText(parent, text, size)
    local fs = newText(parent, size or SP.META, "colHeader")
    local c = Helpers:OnPaper(parent) and C.paperTitle or C.gold
    fs:SetTextColor(c.r, c.g, c.b)
    fs:SetText(text or "")
    return fs
end

----------------------------------------------------------------------
-- One of each screen part (#371): every screen takes these, none draws its own
----------------------------------------------------------------------

-- Space between blocks, and under a sub-tab bar before a screen's first line. A screen's content
-- starts flush with the sub-tab bar's left edge (x = 0) and ends GAP short of the right one.
Helpers.GAP = SP.MARGIN

-- A section title as Settings draws it: Cinzel 15 (UI.SP.TITLE), the soft gold on the wood and dark red on the paper,
-- never upper case. Any section but a screen's first has a 1px `line` rule 12px above it, from the title's
-- left to the parent's right edge, so leave about 20px over a later one. Returns the title; title.rule is that rule.
function Helpers:CreateSectionTitle(parent, text, first)
    local fs = newText(parent, nil, "sectionTitle")
    local c = Helpers:OnPaper(parent) and C.paperTitle or C.gold2
    fs:SetTextColor(c.r, c.g, c.b)
    fs:SetJustifyH("LEFT")
    GuildOS:SetTitleText(fs, text or "")
    if not first then
        local rule = self:CreateSeparator(parent)
        rule:SetPoint("BOTTOMLEFT", fs, "TOPLEFT", 0, 12)
        rule:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        fs.rule = rule
    end
    return fs
end

-- A field's rounded box (the mockup's .field input): on the wood the field's dark with the metal line, on
-- the paper the light paper with a tan line; the line turns the soft gold while typing. Returns the field's
-- resting line colour and its ink. Internal.
local function fieldLook(frame, corner)
    local paper = Helpers:OnPaper(frame)
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    local fill = Style:Nine(frame, "card", corner or 5, "BACKGROUND", -6)
    local line = Style:Nine(frame, "card-line", corner or 5, "BACKGROUND", -5)
    Style:Hand(frame, fill, line)
    local bg, edge = paper and C.paperLight or C.well, paper and C.paperEdge or C.lineHi
    frame:SetBackdropColor(bg.r, bg.g, bg.b, 1)
    frame:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
    return edge, paper and C.paperInk or C.text, paper
end

-- A text field: rounded, on the wood's dark or the paper's light, its line the soft gold while typing,
-- Alegreya Sans 12 inset 8px, Escape lets go. opts: numeric, max, multiline, placeholder (a hint shown while
-- empty), justify, corner (the box's corner radius, 5 by default; half its height makes a pill). Hook its scripts
-- with HookScript: SetScript on the focus ones would drop the line.
function Helpers:CreateInput(parent, width, height, opts)
    opts = opts or {}
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 160, height or SP.FIELD)
    local edge, ink, paper = fieldLook(box, opts.corner)
    box:SetTextInsets(8, 8, opts.multiline and 4 or 0, opts.multiline and 4 or 0)
    GuildOS:ApplyFont(box, 12, opts.numeric and "tableNum" or nil)
    box:SetTextColor(ink.r, ink.g, ink.b)
    if opts.justify then box:SetJustifyH(opts.justify) end
    box:SetAutoFocus(false)
    if opts.multiline then box:SetMultiLine(true) end
    if opts.numeric then box:SetNumeric(true) end
    if opts.max then box:SetMaxLetters(opts.max) end
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local focus = paper and C.paperTitle or C.gold2
    box:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(focus.r, focus.g, focus.b, 1) end)
    box:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1) end)
    if opts.placeholder then
        local ph = newText(box, 12)
        local soft = paper and C.paperSoft or C.labelDim
        ph:SetTextColor(soft.r, soft.g, soft.b)
        ph:SetPoint(opts.multiline and "TOPLEFT" or "LEFT", 8, opts.multiline and -4 or 0)
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

-- A multi-line field. A multi-line EditBox takes the height of its text, so given 56px and left empty
-- it shrinks to one line (the poll's options box and the MOTD did, #371). The field is a frame of the
-- asked size, flat in every style, with the EditBox inside; a click anywhere on it starts typing, and
-- text past its bottom is clipped. Place and size the area; read, write and script `area.edit`.
-- opts: max, placeholder.
function Helpers:CreateTextArea(parent, width, height, opts)
    opts = opts or {}
    local area = CreateFrame("Button", nil, parent, "BackdropTemplate")
    area:SetSize(width or 160, height or 56)
    local edge, ink, paper = fieldLook(area)
    if area.SetClipsChildren then area:SetClipsChildren(true) end
    local edit = CreateFrame("EditBox", nil, area)
    edit:SetPoint("TOPLEFT", 8, -5)
    edit:SetPoint("TOPRIGHT", -8, -5)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    -- A text to be read (a note, a message) is in the reading face.
    GuildOS:ApplyFont(edit, 12, "reading")
    edit:SetTextColor(ink.r, ink.g, ink.b)
    if opts.max then edit:SetMaxLetters(opts.max) end
    edit:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local focus = paper and C.paperTitle or C.gold2
    edit:HookScript("OnEditFocusGained", function() area:SetBackdropBorderColor(focus.r, focus.g, focus.b, 1) end)
    edit:HookScript("OnEditFocusLost", function() area:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1) end)
    area:SetScript("OnClick", function() if edit:IsEnabled() then edit:SetFocus() end end)
    if opts.placeholder then
        local ph = newText(area, 12)
        local soft = paper and C.paperSoft or C.labelDim
        ph:SetTextColor(soft.r, soft.g, soft.b)
        ph:SetPoint("TOPLEFT", 8, -5)
        ph:SetText(opts.placeholder)
        local function sync() ph:SetShown((edit:GetText() or "") == "" and not edit:HasFocus()) end
        edit:HookScript("OnTextChanged", sync)
        edit:HookScript("OnEditFocusGained", sync)
        edit:HookScript("OnEditFocusLost", sync)
        sync()
        area.placeholder = ph
    end
    area.edit = edit
    return area
end

-- A table's header row (the mockup's .t th): UI.SP.HIT (24px) tall unless told, no fill, a 1px rule along its bottom, the metal on the
-- wood and tan on the paper. Put the column labels on it with CreateHeaderText and anchor it by its top
-- corners; the first row sits right under it.
function Helpers:CreateTableHeader(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or SP.HIT)
    local rule = self:CreateSeparator(f)
    local c = Helpers:OnPaper(parent) and C.paperRule or C.lineHi
    rule:SetVertexColor(c.r, c.g, c.b, 1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    f.rule = rule
    return f
end

-- A selected row's mark (the mockup's .t tr.sel): a gold wash that fades to the right. A texture on `row`,
-- hidden; show it while the row is selected. It is exactly the row's box, its top and bottom on the row's own
-- edges, where the lines between rows are drawn (#449: the wash sat above its row in the Cores list). Pinned by
-- two corners to the row itself, never left to SetAllPoints' parent; and only the art's middle rows are read, so
-- the texture's filtering never bleeds its edge rows in (an 8px art stretched over a 46px row). Under the row's
-- lines (sub-level -1), so a rule drawn on the row still shows on a selected one.
function Helpers:CreateRowSelection(row)
    local t = Style:Texture(row, "fade", "BACKGROUND", -1)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    t:SetTexCoord(0, 1, 0.25, 0.75)
    t:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 0.2)
    t.row = row
    t:Hide()
    return t
end

----------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------

-- The variants' colours: the fill's art and colour, the line's colour and the ink, at rest. A secondary
-- button is the dark one on the wood and the quiet (cream) one on a parchment card; a chip is a pill.
local LOOKS
local function looks()
    LOOKS = LOOKS or {
        primary   = { art = "button",      line = "button-line", fill = C.crimson,    edge = C.crimsonLine, ink = C.crimsonInk },
        secondary = { art = "button",      line = "button-line", fill = C.darkButton, edge = C.lineHi,      ink = C.darkInk },
        quiet     = { art = "button-soft", line = "button-line", fill = C.quiet,      edge = C.paperEdge,   ink = C.quietInk },
        danger    = { art = "button",      line = "button-line", fill = C.darkButton, edge = C.danger,      ink = C.danger },
        chip      = { art = "pill",        line = "pill-line",   fill = C.popup,      edge = C.lineHi,      ink = C.door },
        paperChip = { art = "pill",        line = "pill-line",   fill = C.quiet,      edge = C.paperEdge,   ink = C.quietInk },
        ghost     = { ink = C.textSoft },
        paperGhost = { ink = C.paperLink },
        -- A select's closed field (#449): the text input's own box, the dark well on the wood, the light paper
        -- with its tan line on a card, 5px corners.
        field      = { art = "nine:card", line = "nine:card-line", fill = C.well,       edge = C.lineHi,    ink = C.text },
        paperField = { art = "nine:card", line = "nine:card-line", fill = C.paperLight, edge = C.paperEdge, ink = C.paperInk },
    }
    return LOOKS
end

local function lookKey(btn)
    local v = btn.variant
    if btn.__onPaper then
        if v == "secondary" then return "quiet" end
        if v == "chip" then return "paperChip" end
        if v == "ghost" then return "paperGhost" end
        if v == "field" then return "paperField" end
    end
    return v
end

-- The art a button wears (made the first time a variant needs it; one fill and one line shown).
local function wear(btn, look)
    btn.__arts = btn.__arts or {}
    for name, art in pairs(btn.__arts) do art:SetShown(name == look.art or name == look.line) end
    for _, name in ipairs({ look.art, look.line }) do
        if name and not btn.__arts[name] then
            local nine = name:match("^nine:(.+)$")
            local art = nine and Style:Nine(btn, nine, 5, "BACKGROUND", nine:find("line") and 2 or 1)
                or Style:Three(btn, name, "BACKGROUND", name:find("line") and 2 or 1)
            btn.__arts[name] = art
        end
    end
    return look.art and btn.__arts[look.art], look.line and btn.__arts[look.line]
end

-- A disabled button's label: about 60% of the contrast its ground allows, on the wood and on the paper.
Helpers.DISABLED_INK = { wood = { r = 0.62, g = 0.57, b = 0.49 }, paper = C.paperOffInk }

-- Paint one button state: "rest", "hover", "pressed" or "disabled". Internal.
-- Every colour lands in the same frame; there is no transition.
function Helpers:_ButtonState(btn, state)
    btn.__hovered = (state == "hover")
    local key = lookKey(btn)
    local look = looks()[key] or looks().secondary
    local fillArt, lineArt = wear(btn, look)
    local base, text, border = btn.baseColor, btn.baseLabelColor, btn.baseBorder
    local r, g, b, a = base[1], base[2], base[3], base[4]
    local tr, tg, tb = text[1], text[2], text[3]
    local paper = btn.__onPaper
    local k = 1   -- the fill's light: up under the cursor, down while held

    if state == "disabled" then
        -- Disabled reads as disabled on both grounds (#449), not as a dim copy of itself: a flat desaturated
        -- fill, a quiet line and a label at about 60% contrast. A crimson "Raid ready" went a dim red bar with
        -- an unreadable label, a dark button on the wood all but vanished.
        if key ~= "ghost" and key ~= "paperGhost" then
            local fill = paper and { C.paperOff.r, C.paperOff.g, C.paperOff.b } or { 0.20, 0.165, 0.125 }
            r, g, b, a = fill[1], fill[2], fill[3], 1
            border = paper and C.paperRule or C.lineHi
        end
        local d = paper and Helpers.DISABLED_INK.paper or Helpers.DISABLED_INK.wood
        tr, tg, tb = d.r, d.g, d.b
    elseif state == "hover" then
        k = 1.14
        if key == "ghost" or key == "paperGhost" then
            local h = paper and C.paperInk or C.text
            tr, tg, tb = h.r, h.g, h.b
        elseif key == "field" or key == "paperField" then
            border = paper and C.paperTitle or C.metal2
        elseif key == "secondary" or key == "chip" or key == "danger" then
            border = (key == "danger") and C.danger or C.metal2
            if key ~= "danger" then tr, tg, tb = C.text.r, C.text.g, C.text.b end
        end
    elseif state == "pressed" then
        k = 0.82
    end

    -- Selected (Helpers:SetSelected): the soft gold, the identity's selection, through hover and press (#371).
    -- A chip fills with it (the mockup's chosen filter); any other button takes its line and ink. Disabled, it
    -- keeps the mark: an event's kind the rank may no longer pick still shows as its kind.
    if btn.__selected and key ~= "primary" then
        local sel = paper and C.paperTitle or C.gold2
        if key == "chip" or key == "paperChip" then
            r, g, b, a = sel.r, sel.g, sel.b, (state == "disabled") and 0.5 or 1
            border = sel
            local on = paper and C.quiet or C.onGold
            tr, tg, tb = on.r, on.g, on.b
        else
            border = sel
            if state ~= "disabled" then tr, tg, tb = sel.r, sel.g, sel.b end
        end
    end

    if fillArt then
        fillArt:SetRGBA(math.min(1, r * k), math.min(1, g * k), math.min(1, b * k), a or 1)
    end
    if lineArt then
        if border then
            lineArt:SetRGBA(border.r, border.g, border.b, 1)
        else
            lineArt:SetRGBA(0, 0, 0, 0)
        end
    end
    btn.__bg = { r, g, b, a or 1 }
    btn.label:SetTextColor(tr, tg, tb)
    if btn.underline then btn.underline:SetVertexColor(tr, tg, tb, 1) end
end

-- Say why `btn` is disabled: shown in a tooltip while it is (nil: none).
function Helpers:SetDisabledReason(btn, text)
    btn.disabledReason = text
end

-- Create a button. Secondary by default: the dark button on the wood, the quiet cream one on a parchment
-- card; Helpers:SetButtonVariant switches it to primary (crimson), ghost (an underlined link), danger or chip
-- (a pill). Toggle buttons keep calling btn:SetBaseColor so a resting colour survives the hover; setting
-- btn.baseLabelColor does the same for the label. btn:SetBackdropColor and SetBackdropBorderColor tint its
-- rounded art. `name` and `template`, optional: a global name and a template added to BackdropTemplate (a
-- secure action button, issue #420; never SetScript("OnClick") on one, which would replace its secure handler).
function Helpers:CreateButton(parent, text, width, height, name, template)
    local btn = CreateFrame("Button", name, parent, template and ("BackdropTemplate," .. template) or "BackdropTemplate")
    btn:SetSize(width or 120, height or BUTTON_HEIGHT)
    btn.__onPaper = Helpers:OnPaper(parent)

    local label = newText(btn, nil, "button")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    btn.label = label
    fitToLabel(btn)

    btn.variant = "secondary"
    local look = looks()[lookKey(btn)]
    btn.baseColor = { look.fill.r, look.fill.g, look.fill.b, 1 }
    btn.baseLabelColor = { look.ink.r, look.ink.g, look.ink.b }
    btn.baseBorder = look.edge

    -- The backdrop's colour calls land on the art: the fill's and the line's, now.
    local function fillOf() return btn.__arts and btn.__arts[(looks()[lookKey(btn)] or {}).art or ""] end
    local function lineOf() return btn.__arts and btn.__arts[(looks()[lookKey(btn)] or {}).line or ""] end
    Style:Hand(btn, { SetRGBA = function(_, ...) local f = fillOf(); if f then f:SetRGBA(...) end end },
                    { SetRGBA = function(_, ...) local l = lineOf(); if l then l:SetRGBA(...) end end })

    function btn:SetBaseColor(r, g, b, a)
        self.baseColor = { r, g, b, a or 1 }
        if not self.__hovered then Helpers:_ButtonState(self, self:IsEnabled() and "rest" or "disabled") end
    end

    local function idle(self) return self:IsEnabled() and "rest" or "disabled" end
    btn:SetScript("OnEnter", function(self)
        Helpers:_ButtonState(self, self:IsEnabled() and "hover" or "disabled")
        -- Why it is disabled, where the code knows (Helpers:SetDisabledReason).
        if not self:IsEnabled() and self.disabledReason and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.disabledReason, 1, 0.82, 0.5, 1, true)
            GameTooltip:Show()
            self.__reasonShown = true
        end
    end)
    btn:SetScript("OnLeave", function(self)
        Helpers:_ButtonState(self, idle(self))
        if self.__reasonShown and GameTooltip then GameTooltip:Hide(); self.__reasonShown = nil end
    end)
    -- A disabled button still answers the cursor, for its reason's tooltip.
    pcall(function() btn:SetMotionScriptsWhileDisabled(true) end)
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

-- Mark a button as the chosen one of a set (a filter, a mode, a model): a chip fills with the soft gold,
-- any other button takes its line and ink (#371). No ">" prefix.
function Helpers:SetSelected(btn, on)
    btn.__selected = on and true or nil
    if btn.label then
        self:_ButtonState(btn, not btn:IsEnabled() and "disabled" or (btn.__hovered and "hover") or "rest")
    end
    return btn
end

-- Switch a button to one of the variants: "primary" (the crimson button; one per screen), "secondary",
-- "ghost" (an underlined link, no box), "danger" or "chip" (a pill: a filter). Returns the button.
function Helpers:SetButtonVariant(btn, variant)
    variant = variant or "secondary"
    btn.variant = variant
    local label = btn.label
    local look = looks()[lookKey(btn)] or looks().secondary
    if variant == "ghost" then
        GuildOS:ApplyFont(label, 11, "caption")
    elseif variant == "chip" then
        GuildOS:ApplyFont(label, 11, nil)
    else
        GuildOS:ApplyFont(label, nil, "button")
    end
    btn.baseLabelColor = { look.ink.r, look.ink.g, look.ink.b }
    if look.fill then
        btn.baseColor = { look.fill.r, look.fill.g, look.fill.b, 1 }
    else
        btn.baseColor = { 0, 0, 0, 0 }
    end
    btn.baseBorder = look.edge
    if variant == "ghost" and not btn.underline then
        local u = btn:CreateTexture(nil, "ARTWORK")
        u:SetTexture(WHITE)
        Helpers:Hairline(u)
        u:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        u:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -2)
        btn.underline = u
    end
    if btn.underline then btn.underline:SetShown(variant == "ghost") end
    if not look.art and btn.__arts then
        for _, art in pairs(btn.__arts) do art:SetShown(false) end
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
-- On a parchment card the box is the paper's light field with its tan line, the mark the card's dark red and
-- the label the paper's ink. cb.border and cb.fill are the box's two textures.
-- `frame.checkbox.onChanged(cb, checked)` fires on click; SetChecked repaints.
function Helpers:CreateCheckbox(parent, labelText, size)
    size = size or SP.HIT
    local paper = Helpers:OnPaper(parent)
    local well, pressed = paper and C.paperLight or C.well, paper and C.paperLine or C.popup
    local rest = paper and C.paperEdge or C.lineHi
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
    fill:SetVertexColor(well.r, well.g, well.b, 1)
    cb.border, cb.fill = border, fill

    local mark = cb:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(WHITE)
    mark:SetSize(CHECK_MARK, CHECK_MARK)
    mark:SetPoint("CENTER")
    local ink = paper and C.paperTitle or C.gold2
    mark:SetVertexColor(ink.r, ink.g, ink.b, 1)
    mark:Hide()
    cb.checkMark = mark
    local skinned = false

    local function paint()
        local enabled = cb:IsEnabled()
        -- GetChecked() returns true or nil (never false) in TBC.
        mark:SetShown(cb:GetChecked() and true or false)
        mark:SetAlpha(enabled and 1 or DISABLED_GOLD)
        local edge = (not enabled and C.disabled) or (cb.__hovered and C.label) or rest
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
        if not skinned then fill:SetVertexColor(pressed.r, pressed.g, pressed.b, 1) end
    end)
    cb:SetScript("OnMouseUp", function()
        if not skinned then fill:SetVertexColor(well.r, well.g, well.b, 1) end
    end)
    cb:HookScript("OnDisable", paint)
    cb:HookScript("OnEnable", paint)
    paint()

    local label = newText(frame, nil, "body")
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    local text = paper and C.paperInk or C.text
    label:SetTextColor(text.r, text.g, text.b)
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
local DROPDOWN_ROW_H = 22     -- the mockup's menu rows (.ctx button)
local DROPDOWN_PAD   = 4      -- px between the list's edge and its rows
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
    btn:PaintArrow(btn.__onPaper and C.paperSoft or C.textSoft)
end

local function closeDropdown()
    if dropdownList then
        dropdownList.owner = nil
        dropdownList:Hide()
        dropdownList.catcher:Hide()
    end
end

-- The mockup's menu surface on `f`: a soft shadow, the #1a1009 panel with 6px corners and the metal2 line.
-- Shared by the dropdown's list, the minimap menu and the right-click menus.
Helpers.MENU_BG = { r = 0x1a / 255, g = 0x10 / 255, b = 0x09 / 255 }
function Helpers:PaintMenu(f)
    if f.__menuPainted then return f end
    f.__menuPainted = true
    if f.SetBackdrop then f:SetBackdrop(nil) end
    local shadow = Style:Nine(f, "shadow", 14, "BACKGROUND", -8, { -8, -4, -8, -10 })
    shadow:SetRGBA(0, 0, 0, 0.5)
    local fill = Style:Nine(f, "card", 6, "BACKGROUND", -7)
    fill:SetColor(Helpers.MENU_BG)
    local line = Style:Nine(f, "card-line", 6, "BACKGROUND", -6)
    line:SetColor(C.metal2)
    Style:Hand(f, fill, line)
    return f
end

-- A menu row (the mockup's .ctx button): its label 10px in, a warm gold wash with 4px corners under the
-- cursor; `row:SetChosen(on)` marks the current value: the soft gold label on a fainter wash.
function Helpers:MenuRow(parent, h)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(h or DROPDOWN_ROW_H)
    row.wash = Style:Nine(row, "card", 4, "BACKGROUND", 1)
    row.wash:SetRGBA(C.gold2.r, C.gold2.g, C.gold2.b, 0)
    row.label = newText(row, 12)
    row.label:SetPoint("LEFT", 10, 0)
    row.label:SetPoint("RIGHT", -8, 0)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    row.ink = C.text
    local function paint(self)
        local over = self.__over and self:IsEnabled()
        local a = over and 0.22 or (self.chosen and 0.1 or 0)
        self.wash:SetRGBA(C.gold2.r, C.gold2.g, C.gold2.b, a)
        local c = (not self:IsEnabled() and Helpers.DISABLED_INK.wood) or (self.chosen and C.gold2) or (over and C.text) or self.ink
        self.label:SetTextColor(c.r, c.g, c.b)
    end
    row.Paint = paint
    function row:SetChosen(on) self.chosen = on and true or false; paint(self) end
    function row:SetInk(c) self.ink = c or C.text; paint(self) end
    row:SetScript("OnEnter", function(self) self.__over = true; paint(self) end)
    row:SetScript("OnLeave", function(self) self.__over = false; paint(self) end)
    row:HookScript("OnEnable", paint)
    row:HookScript("OnDisable", paint)
    paint(row)
    return row
end

local function buildDropdownList()
    local f = CreateFrame("Frame", "GuildOSDropdownList", UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(20)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    -- Its own surface, the mockup's menus (.ctx, .mmenu; #449): a rounded dark panel (#1a1009) in the bright
    -- metal's line over a soft shadow, the rows 4px in. Every popup menu of the addon draws as this.
    Helpers:PaintMenu(f)
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
    row = Helpers:MenuRow(f.child, DROPDOWN_ROW_H)
    -- The chosen value's mark: a short soft gold bar at the row's left, inside its wash.
    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(WHITE)
    mark:SetSize(2, DROPDOWN_ROW_H - 10)
    mark:SetPoint("LEFT", 4, 0)
    mark:SetVertexColor(C.gold2.r, C.gold2.g, C.gold2.b, 1)
    row.mark = mark
    row:SetScript("OnClick", function(self)
        local owner = f.owner
        closeDropdown()
        if owner then owner:Select(self.value) end
    end)
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
        -- The field's size: the list's text in the UI face at the field's own size.
        GuildOS:ApplyFont(row.label, dd.fontSize or 12)
        row.ink = opt.color or C.text
        row.mark:SetShown(chosen)
        if opt.disabled then row:Disable() else row:Enable() end
        row:SetChosen(chosen)
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
    local dd = self:CreateButton(parent, "", width or 140, height or SP.FIELD)
    -- The closed field looks like the text input beside it (#449): the select of the mockup, not a button.
    self:SetButtonVariant(dd, "field")
    GuildOS:ApplyFont(dd.label, 12)
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
        local ink = color or (text and (self.__onPaper and C.paperInk or C.darkInk)) or (self.__onPaper and C.paperSoft or C.label)
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

-- Create a close button (the mockup's .xbtn): a round crimson button with a gold ring and a light ×,
-- brighter under the cursor. btn.x is the glyph.
local CLOSE_RED = { r = 0.765, g = 0.153, b = 0.114 }
function Helpers:CreateCloseButton(parent)
    local header = popupHeader(parent, "__fwClosed")
    local btn = CreateFrame("Button", nil, header or parent, "BackdropTemplate")
    btn:SetSize(20, 20)
    local orb = Style:Texture(btn, "orb", "BACKGROUND", 1)
    orb:SetAllPoints()
    orb:SetVertexColor(CLOSE_RED.r, CLOSE_RED.g, CLOSE_RED.b, 1)
    local ring = Style:Texture(btn, "ring", "BORDER", 0)
    ring:SetAllPoints()
    ring:SetVertexColor(C.crimsonLine.r, C.crimsonLine.g, C.crimsonLine.b, 1)
    btn.orb, btn.ring = orb, ring

    local x = newText(btn, 12, "button")
    x:SetPoint("CENTER", 0, 0)
    x:SetTextColor(1, 0.85, 0.69)
    x:SetText("\195\151")  -- multiplication sign (×) reads cleaner than letter X
    btn.x = x

    btn:SetScript("OnEnter", function(self)
        self.orb:SetVertexColor(math.min(1, CLOSE_RED.r * 1.2), CLOSE_RED.g * 1.2, CLOSE_RED.b * 1.2, 1)
        self.x:SetTextColor(1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.orb:SetVertexColor(CLOSE_RED.r, CLOSE_RED.g, CLOSE_RED.b, 1)
        self.x:SetTextColor(1, 0.85, 0.69)
    end)
    if header then pinToHeader(btn, header, "RIGHT", 6) end
    return btn
end

-- A round tool (the mockup's .tool): a dark disc with the metal ring and an icon (Media/Salao's "icon-search"
-- or "icon-gear") or a glyph in its middle; the ring and the icon take the soft gold under the cursor and
-- while btn:SetPressed(true).
function Helpers:CreateToolButton(parent, icon, size)
    size = size or 28
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    local disc = Style:Texture(btn, "circle", "BACKGROUND", 1)
    disc:SetAllPoints()
    disc:SetVertexColor(C.popup.r, C.popup.g, C.popup.b, 1)
    local ring = Style:Texture(btn, "ring", "BORDER", 0)
    ring:SetAllPoints()
    btn.disc, btn.ring = disc, ring
    if icon and Style.ART[icon] then
        local t = Style:Texture(btn, icon, "ARTWORK", 0)
        t:SetSize(math.floor(size * 0.5), math.floor(size * 0.5))
        t:SetPoint("CENTER", 0, 0)
        btn.icon = t
    elseif type(icon) == "string" and icon:find("\\", 1, true) then
        -- A game icon (a path): drawn in its own colours, the edges trimmed, a little dim until hovered.
        local t = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        t:SetTexture(icon)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t:SetSize(math.floor(size * 0.58), math.floor(size * 0.58))
        t:SetPoint("CENTER", 0, 0)
        btn.icon, btn.gameIcon = t, true
    else
        local fs = newText(btn, 13, "button")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(icon or "")
        btn.icon, btn.glyph = fs, fs
    end
    local function paint(self)
        local on = self.__pressed or self.__hovered
        local ringC, ink = on and C.gold2 or C.lineHi, on and C.gold2 or C.door
        self.ring:SetVertexColor(ringC.r, ringC.g, ringC.b, 1)
        if self.glyph then self.glyph:SetTextColor(ink.r, ink.g, ink.b)
        elseif self.gameIcon then self.icon:SetAlpha(on and 1 or 0.8)
        else self.icon:SetVertexColor(ink.r, ink.g, ink.b, 1) end
    end
    function btn:SetPressed(on) self.__pressed = on and true or nil; paint(self) end
    btn:SetScript("OnEnter", function(self) self.__hovered = true; paint(self) end)
    btn:SetScript("OnLeave", function(self) self.__hovered = nil; paint(self) end)
    paint(btn)
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
--   kind == "tool"  -> CreateToolButton(bar, icon, size)
--   kind == "text"  -> CreateButton(bar, text, width, height)
----------------------------------------------------------------------
function Helpers:TitleBarButton(bar, kind, ...)
    local btn
    if kind == "close" then
        btn = self:CreateCloseButton(bar)
    elseif kind == "tool" then
        btn = self:CreateToolButton(bar, ...)
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
    track:SetVertexColor(C.well.r, C.well.g, C.well.b, 0.6)

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

-- Create a badge (the mockup's .badge): a small filled pill, bold white text on the colour's own deep
-- shade (danger a deep red, ok a deep green, warn amber, info blue, epic violet, the ink an earned tier's gold
-- brown, anything else the paper's brown). b:SetText(text, color) updates it.
local function badgeFill(col)
    if col == C.danger or col == C.red then return { r = 0.561, g = 0.106, b = 0.043 } end
    if col == C.ok or col == C.green or col == C.online then return { r = 0.184, g = 0.431, b = 0.200 } end
    if col == C.warn then return { r = 0.627, g = 0.337, b = 0.059 } end
    if col == C.info or col == C.blue then return { r = 0.114, g = 0.310, b = 0.600 } end
    if col == C.epic then return { r = 0.424, g = 0.184, b = 0.690 } end
    -- The ink (an earned tier, the mockup's .tier): the gold's brown.
    if col == C.text then return { r = 0.604, g = 0.416, b = 0.071 } end
    if not col or col == C.gold or col == C.accent or col == C.label or col == C.textSoft then return C.paperSoft end
    return { r = col.r * 0.55, g = col.g * 0.55, b = col.b * 0.55 }
end

function Helpers:CreateBadge(parent, text, color)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(20, 16)
    local fill = Style:Three(b, "pill", "BACKGROUND", 1)
    Style:Hand(b, fill, nil)
    local fs = newText(b, nil, "badge")
    fs:SetPoint("CENTER", 0, 0)
    b.label = fs

    local function paint(col)
        local f = badgeFill(col)
        fill:SetRGBA(f.r, f.g, f.b, 1)
        fs:SetTextColor(1, 1, 1)
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

    -- On a parchment card: the paper's tan track and line, the progress in the paper's soft ink.
    local paper = Helpers:OnPaper(parent)
    local track, edge = paper and C.paperLine or C.well, paper and C.paperEdge or C.line
    local going = paper and C.paperSoft or C.textSoft
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(frame) })
    frame:SetBackdropColor(track.r, track.g, track.b, 1)
    frame:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)

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
            col = (value >= 1 and C.ok) or going
        end
        self.bar:SetVertexColor(col.r, col.g, col.b, 1)
    end
    frame:SetProgress(0)

    return frame
end

-- Create a metric chip (the mockup's .kpi): a small dark tile with the metal line, the number in Cinzel and
-- the soft gold, its caption under it in the soft ink; on a parchment card, a darker paper with dark red.
-- chip:SetValue(text) updates the number. chip.rule is kept (hidden) for the screens that read it.
local KPI_PAD_X, KPI_PAD_Y = 12, 8
function Helpers:CreateMetricChip(parent, value, caption, size)
    local chip = CreateFrame("Frame", nil, parent)
    local paper = Helpers:OnPaper(parent)
    local fill = Style:Nine(chip, "card", 6, "BACKGROUND", -6)
    local line = Style:Nine(chip, "card-line", 6, "BACKGROUND", -5)
    if paper then
        fill:SetColor(C.paperBox)
        line:SetColor(C.paperRule)
    else
        fill:SetRGBA(10 / 255, 5 / 255, 2 / 255, 0.5)
        line:SetColor(C.lineHi)
    end
    chip.fill, chip.line = fill, line
    local rule = self:CreateAccentLine(chip, 1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    rule:Hide()

    local px = size or SP.KPI
    local v = newText(chip, px, "metricValue")
    v:SetPoint("TOPLEFT", KPI_PAD_X, -KPI_PAD_Y)
    local vc = paper and C.paperTitle or C.gold2
    v:SetTextColor(vc.r, vc.g, vc.b)
    v:SetText(value or "")

    local l = newText(chip, nil, "caption")
    l:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -2)
    local lc = paper and C.paperSoft or C.textSoft
    l:SetTextColor(lc.r, lc.g, lc.b)
    l:SetText(caption or "")

    chip.value, chip.rule, chip.label = v, rule, l
    function chip:SetValue(t) self.value:SetText(t or "") end
    chip:SetSize(math.max(CHIP_MIN, v:GetStringWidth() or 0, l:GetStringWidth() or 0) + 2 * KPI_PAD_X,
        px + CHIP_PAD + 20)
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
-- A screen's own sub-tab bar that a room may hide (specs/salao, #445): opened from a room entry that names one of
-- its sub-tabs, the room's row is the only row of tabs. `frames()` returns the sub-panels (frames, or records
-- with a `panel`), keyed by sub-tab; `under` is where each starts under the bar, { x, y } from its bottom-left.
-- Hidden, they start where the bar's top-left is (the same x). host.PlaceUnderSubBar(frame) anchors one by the
-- same rule. A sub-panel shown by the screen itself (a button that opens another sub-tab) reports its key to
-- host.OnSubChanged, so the room marks the entry actually on screen.
function Helpers:CollapsibleSubBar(host, bar, frames, under)
    local shown = true
    local ux, uy = under and under[1] or 0, under and under[2] or 0
    local function frameOf(p) return (type(p) == "table" and rawget(p, "panel")) or p end
    local function place(f)
        if shown then
            f:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", ux, uy)
        else
            f:SetPoint("TOPLEFT", bar, "TOPLEFT", ux, 0)
        end
    end
    host.PlaceUnderSubBar = place
    function host.SetSubBarShown(v)
        v = v and true or false
        if v == shown then return end
        shown = v
        bar:SetShown(v)
        for _, p in pairs(frames()) do
            local f = frameOf(p)
            if f then place(f) end
        end
    end
    for key, p in pairs(frames()) do
        local f = frameOf(p)
        if f and f.HookScript and type(key) == "string" then
            f:HookScript("OnShow", function() if host.OnSubChanged then host.OnSubChanged(key) end end)
        end
    end
end

-- Create a tab (the mockup's .sub, an entry pill): the door's ink at rest, the metal's line under the cursor,
-- and the open one a soft gold pill with dark bold text. `_sub` is kept for the callers that pass it; every tab, at least SP.HIT tall,
-- is a pill now. tab.underline is kept, hidden.
function Helpers:CreateTab(parent, text, width, _sub)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(width or 100, SP.HIT)
    local fill = Style:Three(tab, "pill", "BACKGROUND", 1)
    local line = Style:Three(tab, "pill-line", "BACKGROUND", 2)
    fill:SetColor(C.gold2)
    line:SetColor(C.lineHi)
    tab.fill, tab.line = fill, line

    local label = newText(tab, 12, nil)
    label:SetPoint("CENTER")
    label:SetText(text or "")
    tab.label = label
    fitToLabel(tab)

    local underline = tab:CreateTexture(nil, "OVERLAY")
    underline:SetTexture(WHITE)
    Helpers:Hairline(underline)
    underline:SetPoint("BOTTOMLEFT", 2, 0)
    underline:SetPoint("BOTTOMRIGHT", -2, 0)
    underline:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    underline:Hide()
    tab.underline = underline

    local function paint(self, hovered)
        local active = self.isActive and true or false
        fill:SetShown(active)
        line:SetShown(hovered and not active or false)
        if active ~= self.__bold then
            self.__bold = active
            GuildOS:ApplyFont(self.label, 12, active and "button" or nil)
        end
        -- On a parchment card the door's cream is invisible: at rest, and under the cursor, the quiet button's ink.
        local ink = (active and C.onGold) or (self.__paperInk and C.quietInk) or (hovered and C.text) or C.door
        self.label:SetTextColor(ink.r, ink.g, ink.b)
    end

    function tab:SetActive(active)
        tab.isActive = active
        paint(tab, false)
    end
    tab.__paperInk = Helpers:OnPaper(parent) or nil

    tab:SetActive(false)

    tab:SetScript("OnEnter", function(self) paint(self, true) end)
    tab:SetScript("OnLeave", function(self) paint(self, false) end)
    tab:SetScript("OnMouseDown", function() end)
    tab:SetScript("OnMouseUp", function(self) paint(self, self:IsMouseOver()) end)

    return tab
end

-- Paint a sub-tab bar: a screen's own row of pills, on a dark strip with a line under it.
function Helpers:StyleSubTabBar(bar)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints()
    bg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 0.7)
    bar.bg = bg
    local rule = self:CreateSeparator(bar)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    bar.rule = rule
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
    -- A third answer (def.button3, def.OnAlt), under the other two: "Don't ask again" (audit B12).
    f.button3 = Helpers:CreateButton(f, "", 272, 22)
    f.button3:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    f.button3:SetScript("OnClick", function()
        local def = f.def
        if not def then return end
        f.answered = true
        if def.OnAlt then GuildOS:SafeCall(def.OnAlt, f, f.data, f.data2) end
        f:Hide()
    end)
    f.button3:Hide()

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
    -- Dressed as the mockup's modal (UI/Kit.lua) before anything is laid out: the reading face changes the
    -- text's height the box is sized from.
    if GuildOS.Kit and GuildOS.Kit.DressDialog then GuildOS.Kit:DressDialog(f) end

    f.which, f.def, f.data, f.data2, f.answered = which, def, data, nil, false
    f.showing = (f.showing or 0) + 1
    local showing = f.showing
    f.text:SetText(string.format(def.text or "%s", textArg1 or "", textArg2 or ""))
    f.button1.label:SetText(def.button1)
    f.button2.label:SetText(def.button2 or CANCEL)
    f.button3:SetShown(def.button3 ~= nil)
    if def.button3 then f.button3.label:SetText(def.button3) end
    local rowY = def.button3 and 42 or 14   -- the two answers sit above the third one
    f.button1:ClearAllPoints()
    f.button1:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, rowY)
    f.button2:ClearAllPoints()
    f.button2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, rowY)
    f.editBox:SetShown(def.hasEditBox and true or false)
    f.editBox:SetMaxLetters(def.maxLetters or 0)
    f.editBox:SetText("")
    f:SetHeight(f.text:GetStringHeight() + (def.hasEditBox and 104 or 72) + (def.button3 and 28 or 0))
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
