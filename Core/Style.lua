----------------------------------------------------------------------
-- Guild OS - The look (issue #122; the Salão, specs/salao, #445; phase 3, specs/salao/fase3.md)
-- One look on every client: the Salão's dark wood and bronze around parchment cards, as the approved
-- mockup draws it. WoW draws no CSS, so the mockup's gradients, rounded corners, grain and glow are small
-- textures in Media/Salao (drawn by tools/salao_art.py), laid out here in nine pieces (a box), three (a
-- button, a pill) or one, and tinted with SetVertexColor where a colour varies. The same files on TBC
-- Anniversary, WoW: Forever and Retail: the look depends on no client's own atlases any more. The
-- Forever client's art (the "forever" painter, phases 1 and 2) made the window read as generic Forever and
-- is gone. Frames are built once, at load.
----------------------------------------------------------------------
local Style = {}
GuildOS.Style = Style
local L = GuildOS.L

Style.DEFAULT = "salao"
Style.ORDER = { "salao" }
Style.current = Style.DEFAULT

local INFO = {
    salao = { name = "Salão", desc = L["Flat and dark: the look Guild OS was made with."] },
}

-- Every texture the look draws, by name: Media/Salao/<name>.tga (tools/salao_art.py; tools/salao-art.lua
-- checks each one is on disk, a 32-bit TGA with power-of-two sides).
local DIR = "Interface\\AddOns\\GuildOS\\Media\\Salao\\"
Style.ART_DIR = DIR
Style.ART = {}
for _, name in ipairs({ "wood", "grain", "glow", "titlebar", "card", "card-line", "shadow", "button", "button-soft",
                        "button-line", "pill", "pill-line", "orb", "disc", "circle", "ring", "ring-dash", "halo", "fade",
                        "snow", "garland", "icon-search", "icon-gear", "mark-crest", "mark-warn", "mark-banner" }) do
    Style.ART[name] = DIR .. name .. ".tga"
end

-- Where the art keeps its corners, as a share of the file's side: a 9-slice box's corner (`card` is 32px
-- with 8px corners) and a 3-slice bar's cap (`button` is 64x32 with 8px caps, `pill` 64x32 with 16px caps).
local CORNER = { card = 0.25, ["card-line"] = 0.25, shadow = 0.375 }
local CAP = { button = 0.125, ["button-soft"] = 0.125, ["button-line"] = 0.125, pill = 0.25, ["pill-line"] = 0.25 }
-- A cap's width over the bar's height: the caps keep the art's proportions at any height.
local CAP_RATIO = { button = 0.25, ["button-soft"] = 0.25, ["button-line"] = 0.25, pill = 0.5, ["pill-line"] = 0.5 }

----------------------------------------------------------------------
-- The registry: one look, nothing to choose
----------------------------------------------------------------------
function Style:Has(id) return id == "salao" end
function Style:Available() return { "salao" } end
function Style:Name(id) return INFO[id] and INFO[id].name or tostring(id) end
function Style:Description(id) return INFO[id] and INFO[id].desc or "" end
function Style:Current() return self.current end

-- Nothing is saved (#445): there is one look. Kept for the callers that still ask.
-- The two names the look had before phase 3 are still known: asked for, they get the same answer.
local OLD = { guildos = true, forever = true }
function Style:Choose(id)
    if not (INFO[id] or OLD[id]) then return false, "unknown" end
    return false, "one"
end

-- At load, before any window is built. The palette is Core/Data.lua's and the fonts are the addon's own
-- unless the player ticked "Use the game's font" (GuildOSDB.gameFont, Settings > Interface): read here once, so
-- the whole interface draws in one font until the next reload. A saved GuildOSDB.style is ignored.
function Style:Resolve()
    self.current = "salao"
    self.gameFont = type(GuildOSDB) == "table" and GuildOSDB.gameFont == true
    -- Dark mode (GuildOSDB.darkMode, Settings > Interface): the parchment's tokens switch here, in place, so the
    -- whole interface draws on one paper until the next reload.
    self.darkMode = type(GuildOSDB) == "table" and GuildOSDB.darkMode == true
    if GuildOS.SetDarkPaper then GuildOS:SetDarkPaper(self.darkMode) end
    return self.current
end

-- The saved choice, as it will be after the next reload (Settings shows this, not the font in use).
function Style:WantsGameFont()
    return GuildOS.GameFontOnly or (type(GuildOSDB) == "table" and GuildOSDB.gameFont == true)
end

function Style:SetGameFont(on)
    if type(GuildOSDB) ~= "table" then return end
    GuildOSDB.gameFont = on and true or nil
end

-- Dark mode as it will be after the next reload (Settings shows this, not the paper in use).
function Style:WantsDarkMode()
    return type(GuildOSDB) == "table" and GuildOSDB.darkMode == true
end

function Style:SetDarkMode(on)
    if type(GuildOSDB) ~= "table" then return end
    GuildOSDB.darkMode = on and true or nil
end

GuildOS.Dialogs["GUILDOS_STYLE_RELOAD"] = {
    text = "%s", button1 = L["Reload"], button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- /gos style <id>: there is one look now (#445).
function Style:Apply(id)
    local _, why = self:Choose(id)
    if why == "unknown" then
        GuildOS:Print(string.format(L["Unknown style: %s. Styles: %s"], tostring(id), "salao"))
    else
        GuildOS:Print(L["Guild OS has one look now: the Salão."])
    end
    return false
end

function Style:PrintList()
    GuildOS:Print("  salao - Salão (" .. L["in use"] .. ")")
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

-- A texture of the art on `frame`. `tile`: repeat the file across the texture instead of stretching it
-- (the wood, the grain, the snow), where the client tiles; elsewhere the texture coordinates repeat it.
function Style:Texture(frame, name, layer, sub, tile)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    if tile then
        t:SetTexture(self.ART[name], "REPEAT", "REPEAT")
        if t.SetHorizTile then t:SetHorizTile(true) end
        if t.SetVertTile then t:SetVertTile(true) end
    else
        t:SetTexture(self.ART[name])
    end
    t.__art = name
    -- Dark mode: the boards and the title bar in ebony (GuildOS.EBONY); the rest of the art keeps its colours.
    if GuildOS.darkPaper and (name == "wood" or name == "titlebar") and GuildOS.EBONY then
        local e = GuildOS.EBONY
        t:SetVertexColor(e.r, e.g, e.b, 1)
    end
    return t
end

local function tint(t, c, a)
    if c then t:SetVertexColor(c.r, c.g, c.b, a or c.a or 1) end
end

local NINE = { "TL", "T", "TR", "L", "C", "R", "BL", "B", "BR" }

-- A box in nine pieces of `name` (card, card-line, shadow): corners of `size` px, edges stretched between
-- them. `inset` (l, t, r, b; negative hangs outside) places it inside `frame`. `open = "bottom"` drops the
-- bottom row: a door's top corners only. Returns the box: box:SetColor(c, a), box:SetShown(v), box.pieces.
function Style:Nine(frame, name, size, layer, sub, inset, open)
    local q = CORNER[name] or 0.25
    local l, tp, r, b = 0, 0, 0, 0
    if inset then l, tp, r, b = inset[1] or 0, inset[2] or 0, inset[3] or 0, inset[4] or 0 end
    local p = {}
    for _, k in ipairs(NINE) do p[k] = self:Texture(frame, name, layer, sub) end
    local function coords(t, x0, x1, y0, y1) t:SetTexCoord(x0, x1, y0, y1) end
    p.TL:SetSize(size, size); p.TL:SetPoint("TOPLEFT", frame, "TOPLEFT", l, -tp); coords(p.TL, 0, q, 0, q)
    p.TR:SetSize(size, size); p.TR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -r, -tp); coords(p.TR, 1 - q, 1, 0, q)
    p.T:SetPoint("TOPLEFT", p.TL, "TOPRIGHT"); p.T:SetPoint("BOTTOMRIGHT", p.TR, "BOTTOMLEFT"); coords(p.T, q, 1 - q, 0, q)
    if open == "bottom" then
        for _, k in ipairs({ "BL", "B", "BR" }) do p[k]:Hide(); p[k].__off = true end
        p.L:SetPoint("TOPLEFT", p.TL, "BOTTOMLEFT"); p.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", l, b); p.L:SetWidth(size)
        p.R:SetPoint("TOPRIGHT", p.TR, "BOTTOMRIGHT"); p.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, b); p.R:SetWidth(size)
        coords(p.L, 0, q, q, 1 - q); coords(p.R, 1 - q, 1, q, 1 - q)
        p.C:SetPoint("TOPLEFT", p.TL, "BOTTOMRIGHT"); p.C:SetPoint("BOTTOMRIGHT", p.R, "BOTTOMLEFT"); coords(p.C, q, 1 - q, q, 1 - q)
    else
        p.BL:SetSize(size, size); p.BL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", l, b); coords(p.BL, 0, q, 1 - q, 1)
        p.BR:SetSize(size, size); p.BR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, b); coords(p.BR, 1 - q, 1, 1 - q, 1)
        p.B:SetPoint("TOPLEFT", p.BL, "TOPRIGHT"); p.B:SetPoint("BOTTOMRIGHT", p.BR, "BOTTOMLEFT"); coords(p.B, q, 1 - q, 1 - q, 1)
        p.L:SetPoint("TOPLEFT", p.TL, "BOTTOMLEFT"); p.L:SetPoint("BOTTOMRIGHT", p.BL, "TOPRIGHT"); coords(p.L, 0, q, q, 1 - q)
        p.R:SetPoint("TOPLEFT", p.TR, "BOTTOMLEFT"); p.R:SetPoint("BOTTOMRIGHT", p.BR, "TOPRIGHT"); coords(p.R, 1 - q, 1, q, 1 - q)
        p.C:SetPoint("TOPLEFT", p.TL, "BOTTOMRIGHT"); p.C:SetPoint("BOTTOMRIGHT", p.BR, "TOPLEFT"); coords(p.C, q, 1 - q, q, 1 - q)
    end
    local box = { pieces = p, name = name, shown = true }
    function box:SetColor(c, a)
        self.color = c and { c.r, c.g, c.b, a or c.a or 1 } or nil
        for _, t in pairs(p) do tint(t, c, a) end
    end
    function box:SetRGBA(rr, gg, bb, aa)
        self.color = { rr, gg, bb, aa or 1 }
        for _, t in pairs(p) do t:SetVertexColor(rr, gg, bb, aa or 1) end
    end
    function box:SetShown(v)
        self.shown = v and true or false
        for _, t in pairs(p) do t:SetShown(self.shown and not t.__off) end
    end
    return box
end

-- A bar in three pieces of `name` (button, button-soft, button-line, pill, pill-line): caps that keep the
-- art's proportions at the frame's height, squeezed when the frame is narrower than both, and a middle
-- stretched between them. Returns the bar, with the box's SetColor, SetRGBA and SetShown.
function Style:Three(frame, name, layer, sub)
    local q, ratio = CAP[name] or 0.25, CAP_RATIO[name] or 0.5
    local p = { L = self:Texture(frame, name, layer, sub), M = self:Texture(frame, name, layer, sub),
                R = self:Texture(frame, name, layer, sub) }
    p.L:SetTexCoord(0, q, 0, 1); p.M:SetTexCoord(q, 1 - q, 0, 1); p.R:SetTexCoord(1 - q, 1, 0, 1)
    p.L:SetPoint("TOPLEFT"); p.L:SetPoint("BOTTOMLEFT")
    p.R:SetPoint("TOPRIGHT"); p.R:SetPoint("BOTTOMRIGHT")
    p.M:SetPoint("TOPLEFT", p.L, "TOPRIGHT"); p.M:SetPoint("BOTTOMRIGHT", p.R, "BOTTOMLEFT")
    local function layout()
        local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
        local cap = math.max(1, h * ratio)
        if w > 0 and 2 * cap > w then cap = math.max(1, w / 2) end
        p.L:SetWidth(cap); p.R:SetWidth(cap)
    end
    layout()
    frame:HookScript("OnSizeChanged", layout)
    local bar = { pieces = p, name = name, shown = true, Layout = layout }
    function bar:SetColor(c, a)
        self.color = c and { c.r, c.g, c.b, a or c.a or 1 } or nil
        for _, t in pairs(p) do tint(t, c, a) end
    end
    function bar:SetRGBA(rr, gg, bb, aa)
        self.color = { rr, gg, bb, aa or 1 }
        for _, t in pairs(p) do t:SetVertexColor(rr, gg, bb, aa or 1) end
    end
    function bar:SetShown(v)
        self.shown = v and true or false
        for _, t in pairs(p) do t:SetShown(self.shown) end
    end
    return bar
end

-- Give a painted frame the backdrop's two colour calls, onto its fill and its line: the screens that set a
-- panel's, a field's or a button's colour keep doing so, on the rounded art. Reads back as the backdrop did.
function Style:Hand(frame, fill, line)
    frame.__look = { fill = fill, line = line }
    function frame:SetBackdropColor(r, g, b, a)
        self.__bg = { r, g, b, a or 1 }
        if fill then fill:SetRGBA(r, g, b, a or 1) end
    end
    function frame:SetBackdropBorderColor(r, g, b, a)
        self.__edge = { r, g, b, a or 1 }
        if line then line:SetRGBA(r, g, b, a or 1) end
    end
    function frame:GetBackdropColor() if self.__bg then return unpack(self.__bg) end end
    function frame:GetBackdropBorderColor() if self.__edge then return unpack(self.__edge) end end
    return frame
end

----------------------------------------------------------------------
-- Painting by role
--   window   the frame: a 3px metal border with a bright metal line inside it, round 8px corners
--   panel    a dark card on the wood: the mockup's .dark (rgba(10,5,2,.55), a 1px metal line, 8px corners)
--   well     an inset on the wood: the field's colour, a 1px line, 6px corners
--   paper    a parchment card: the paper, its grain, a darker bottom edge and a soft shadow (.card)
--   popup    a popup's own backdrop, bordered in the bright metal (the caller paints its background)
--   titlebar the title bar's warm gradient
----------------------------------------------------------------------
function Style:Paint(frame, role)
    local C = GuildOS.Colors
    if role == "popup" then
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(C.metal2.r, C.metal2.g, C.metal2.b, 1) end
        return "art"
    end
    if role == "titlebar" then
        frame.__styleBg = frame.__styleBg or self:Texture(frame, "titlebar", "BACKGROUND")
        frame.__styleBg:SetAllPoints()
        return "art"
    end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    if role == "window" then
        local edge = self:Nine(frame, "card-line", 8, "BACKGROUND", -8, { -1, -1, -1, -1 })
        edge:SetRGBA(0, 0, 0, 1)
        local metal = self:Nine(frame, "card", 8, "BACKGROUND", -7)
        metal:SetColor(C.lineHi)
        local fill = self:Nine(frame, "card", 6, "BACKGROUND", -6, { 3, 3, 3, 3 })
        fill:SetColor(C.bg)
        local line = self:Nine(frame, "card-line", 6, "BACKGROUND", -5, { 3, 3, 3, 3 })
        line:SetColor(C.metal2)
        frame.__edge3 = 3
        return "art", self:Hand(frame, fill, metal)
    end
    if role == "paper" then
        local soft = self:Nine(frame, "shadow", 18, "BACKGROUND", -8, { -10, -6, -10, -16 })
        soft:SetRGBA(0, 0, 0, 0.35)
        local edge = self:Nine(frame, "card", 6, "BACKGROUND", -7, { 0, 3, 0, -3 })
        edge:SetColor(C.paperEdge)
        local fill = self:Nine(frame, "card", 6, "BACKGROUND", -6)
        fill:SetColor(C.paper)
        local grain = self:Texture(frame, "grain", "BACKGROUND", -5, true)
        grain:SetPoint("TOPLEFT", 2, -2)
        grain:SetPoint("BOTTOMRIGHT", -2, 2)
        frame.__paper, frame.__grain = true, grain
        return "art", self:Hand(frame, fill, nil)
    end
    if role == "well" then
        local fill = self:Nine(frame, "card", 5, "BACKGROUND", -6)
        fill:SetColor(C.well, 0.8)
        local line = self:Nine(frame, "card-line", 5, "BACKGROUND", -5)
        line:SetColor(C.line)
        return "art", self:Hand(frame, fill, line)
    end
    -- A panel, and any role this file does not know: the dark card.
    local fill = self:Nine(frame, "card", 8, "BACKGROUND", -6)
    fill:SetColor(C.darkCard)
    local line = self:Nine(frame, "card-line", 8, "BACKGROUND", -5)
    line:SetColor(C.lineHi)
    return "art", self:Hand(frame, fill, line)
end

-- The wood behind a room's screen: vertical boards, the fire's glow in the bottom-right corner and, while
-- Winter Veil is on (SetWinter), snow on the boards. Drawn on `frame` over `area` (the window's view), so the
-- screens' own frames, at the levels they always had, stay over it. Returns the layer: layer:SetWinter(on).
function Style:PaintWood(frame, area)
    area = area or frame
    local wood = self:Texture(frame, "wood", "BACKGROUND", 0, true)
    wood:SetAllPoints(area)
    local snow = self:Texture(frame, "snow", "BACKGROUND", 1, true)
    snow:SetAllPoints(area)
    snow:SetVertexColor(1, 1, 1, 0.7)
    snow:Hide()
    local glow = self:Texture(frame, "glow", "BACKGROUND", 2)
    glow:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
    local function size()
        local w, h = area:GetWidth() or 0, area:GetHeight() or 0
        glow:SetSize(math.max(1, math.min(w, 760) * 0.9), math.max(1, math.min(h, 560) * 0.9))
    end
    size()
    area:HookScript("OnSizeChanged", size)
    local layer = { wood = wood, glow = glow, snow = snow }
    function layer:SetWinter(on)
        snow:SetShown(on and true or false)
    end
    return layer
end
