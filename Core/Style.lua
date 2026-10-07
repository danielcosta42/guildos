----------------------------------------------------------------------
-- Guild OS - Interface styles (issue #122; spec docs/superpowers/specs/2026-10-07-ui-styles-design.md §4)
-- A style is how the addon is painted: its palette, its font, and the art behind each role
-- (window, title bar, panel, well, popup, input) and control (button, tab, checkbox, close
-- button, scroll bar). "guildos" is the flat look the addon was made with; it paints exactly as
-- the Helpers always did. "forever" paints with the WoW: Forever client's own -c60 atlases, and
-- is offered only where the client has them. The choice belongs to the account (GuildOSDB.style)
-- and takes effect at load: frames are built once, so a switch asks for a reload.
----------------------------------------------------------------------
local Style = {}
GuildOS.Style = Style
local L = GuildOS.L

Style.DEFAULT = "guildos"
Style.ORDER = { "guildos", "forever" }
Style.current = Style.DEFAULT

local INFO = {
    guildos = { name = "GuildOS", desc = L["Flat and dark: the look Guild OS was made with."] },
    forever = { name = "WoW: Forever",
                desc = L["The game's own bronze frames, tabs and buttons. A beta: tell us what looks off."] },
}

-- A frame's border in nine pieces, named as the client names them: four corners, and edges whose
-- names start with "_" (tiled across) or "!" (tiled down).
local function nine(prefix, suffix, scale, center)
    return { kind = "nine", scale = scale, center = center,
        TopLeftCorner = prefix .. "cornertopleft" .. suffix, TopRightCorner = prefix .. "cornertopright" .. suffix,
        BottomLeftCorner = prefix .. "cornerbottomleft" .. suffix,
        BottomRightCorner = prefix .. "cornerbottomright" .. suffix,
        TopEdge = "_" .. prefix .. "edgetop" .. suffix, BottomEdge = "_" .. prefix .. "edgebottom" .. suffix,
        LeftEdge = "!" .. prefix .. "edgeleft" .. suffix, RightEdge = "!" .. prefix .. "edgeright" .. suffix }
end
local function three(left, center, right)
    return { kind = "three", Left = left, Center = center, Right = right }
end
local function redButton(state)
    local s = (state == "rest") and "" or ("-" .. state)
    return three("128-redbutton-left" .. s .. "-c60", "_128-redbutton-center" .. s .. "-c60",
                 "128-redbutton-right" .. s .. "-c60")
end
local function iconButton(name)
    return { rest = "128-redbutton-" .. name .. "-c60", pressed = "128-redbutton-" .. name .. "-pressed-c60",
             disabled = "128-redbutton-" .. name .. "-disabled-c60" }
end

-- The Forever client's art (build 1.60.1.70235), by role. A nine-slice's pieces are the atlas size
-- times `scale`; a three-slice is as tall as its frame. Candidates until beta screenshots of
-- /gos style preview confirm them (spec §4.6).
Style.FOREVER = {
    window   = nine("ui-frame-metal-", "-c60-2x", 0.25),
    panel    = nine("optionsframe-nineslice-", "-c60", 0.5),
    well     = nine("optionsframe-nineslice-", "-c60", 0.5),
    popup    = nine("tooltip-nineslice-", "-c60", 1, "tooltip-nineslice-center-c60"),
    titlebar = three("ui-frame-diamondmetal-header-cornerleft-c60-2x", "_ui-frame-diamondmetal-header-tile-c60-2x",
                     "ui-frame-diamondmetal-header-cornerright-c60-2x"),
    input    = three("common-search-border-left-c60", "common-search-border-middle-c60",
                     "common-search-border-right-c60"),
    button   = { rest = redButton("rest"), pressed = redButton("pressed"), disabled = redButton("disabled") },
    tab      = { rest = "common-internaltab-c60", hover = "common-internaltab-hover-c60",
                 active = "common-internaltab-selected-c60" },
    checkbox = { box = "checkbox-minimal-c60", mark = "talents-checkmark-c60" },
    close    = iconButton("exit"),
    minimise = iconButton("minus"),
    scroll   = { track = "!minimal-scrollbar-track-middle-c60", thumb = "minimal-scrollbar-thumb-middle-c60" },
}
-- The pieces that say the client has the art at all.
local KEY_ATLASES = { "ui-frame-metal-cornertopleft-c60-2x", "_128-redbutton-center-c60", "common-internaltab-c60" }

-- Stone, bronze and parchment, with the game's yellow as the accent. Status colours keep theirs.
local function rgb(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
Style.FOREVER_PALETTE = {
    bg = rgb(0.078, 0.067, 0.055), panel = rgb(0.125, 0.106, 0.086), popup = rgb(0.157, 0.133, 0.106),
    well = rgb(0.051, 0.043, 0.035), line = rgb(0.361, 0.290, 0.180), lineHi = rgb(0.549, 0.443, 0.263),
    text = rgb(1.000, 0.957, 0.859), textSoft = rgb(0.824, 0.761, 0.624), label = rgb(0.722, 0.643, 0.482),
    labelDim = rgb(0.522, 0.459, 0.349), disabled = rgb(0.400, 0.361, 0.298),
    gold = rgb(1.000, 0.820, 0.000), onGold = rgb(0.149, 0.098, 0.020),
}

----------------------------------------------------------------------
-- Atlases
----------------------------------------------------------------------
local function atlasInfo(name)
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then return nil end
    local ok, info = pcall(get, name)
    return ok and info or nil
end

-- Every atlas a piece of art names, depth first.
function Style.AtlasNames(art, out)
    out = out or {}
    if type(art) == "string" then out[#out + 1] = art; return out end
    for k, v in pairs(art or {}) do
        if k ~= "kind" and (type(v) == "string" or type(v) == "table") then Style.AtlasNames(v, out) end
    end
    return out
end

-- True when the client has every atlas of `art`. Each missing one is recorded once per session.
local reported = {}
function Style:_HasArt(art)
    local all = true
    for _, n in ipairs(Style.AtlasNames(art)) do
        if not atlasInfo(n) then
            all = false
            if not reported[n] then
                reported[n] = true
                GuildOS:RecordError("style forever: the client has no atlas " .. n)
            end
        end
    end
    return all
end

----------------------------------------------------------------------
-- The registry
----------------------------------------------------------------------
function Style:Has(id)
    if id == "guildos" then return true end
    if id ~= "forever" then return false end
    for _, n in ipairs(KEY_ATLASES) do
        if not atlasInfo(n) then return false end
    end
    return true
end

function Style:Available()
    local out = {}
    for _, id in ipairs(self.ORDER) do
        if self:Has(id) then out[#out + 1] = id end
    end
    return out
end

function Style:Name(id) return INFO[id] and INFO[id].name or tostring(id) end
function Style:Description(id) return INFO[id] and INFO[id].desc or "" end
function Style:Current() return self.current end

-- Saves the account's choice; it is used from the next load on.
function Style:Choose(id)
    if not INFO[id] then return false, "unknown" end
    if not self:Has(id) then return false, "unavailable" end
    if type(GuildOSDB) ~= "table" then GuildOSDB = {} end
    GuildOSDB.style = id
    return true
end

-- At load, before any window is built: the saved style if this client draws it, else the default,
-- said once. The Forever style re-points the palette in place and takes the game's font.
function Style:Resolve()
    local want = type(GuildOSDB) == "table" and GuildOSDB.style or nil
    local id = (want and self:Has(want)) and want or self.DEFAULT
    self.current, self.gameFont = id, nil
    if want and want ~= id then
        GuildOS:Print(string.format(L["The %s style is not available on this client; using %s."],
            self:Name(want), self:Name(id)))
    end
    if id == "forever" then
        GuildOS:RepointColors(self.FOREVER_PALETTE)
        self.gameFont = true
    end
    return id
end

if StaticPopupDialogs then
    StaticPopupDialogs["GUILDOS_STYLE_RELOAD"] = {
        text = "%s", button1 = L["Reload"], button2 = L["Later"],
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

-- The picker's and /gos style's verb: save, then offer the reload.
function Style:Apply(id)
    local ok, why = self:Choose(id)
    if not ok then
        if why == "unknown" then
            GuildOS:Print(string.format(L["Unknown style: %s. Styles: %s"], tostring(id), table.concat(self.ORDER, ", ")))
        else
            GuildOS:Print(string.format(L["The %s style is not available on this client."], self:Name(id)))
        end
        return false
    end
    StaticPopup_Show("GUILDOS_STYLE_RELOAD", string.format(L["Reload the interface now to use the %s style?"], self:Name(id)))
    return true
end

function Style:PrintList()
    for _, id in ipairs(self.ORDER) do
        local tag = (id == self.current and L["in use"]) or ((not self:Has(id)) and L["not available here"]) or nil
        GuildOS:Print("  " .. id .. " - " .. self:Name(id) .. (tag and (" (" .. tag .. ")") or ""))
    end
end

----------------------------------------------------------------------
-- Painting by role
----------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function roleColor(role)
    local C = GuildOS.Colors
    if role == "well" or role == "input" then return C.well end
    if role == "titlebar" then return C.panel end
    return C.bg
end

-- Today's paint, unchanged: a WHITE8x8 backdrop with a 1px `line` border, or the title bar's band.
-- A popup's colours are its caller's (Helpers:StylePopup never set them), so flat leaves it alone.
function Style:_PaintFlat(frame, role)
    local C = GuildOS.Colors
    if role == "popup" then return "flat" end
    if role == "titlebar" then
        local bg = frame.__styleBg or frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(WHITE)
        bg:SetAllPoints()
        bg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
        frame.__styleBg = bg
        return "flat"
    end
    local c = roleColor(role)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(c.r, c.g, c.b, 1)
    frame:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    return "flat"
end

local function setAtlasSized(tex, name, scale)
    tex:SetAtlas(name)
    local info = atlasInfo(name)
    tex:SetSize((info and info.width or 0) * scale, (info and info.height or 0) * scale)
end

local NINE = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
               "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }

-- The border in nine pieces around the role's colour.
function Style:_PaintNine(frame, art, role)
    local c = roleColor(role)
    frame:SetBackdrop({ bgFile = WHITE })
    frame:SetBackdropColor(c.r, c.g, c.b, 1)
    local p = frame.__nine or {}
    frame.__nine = p
    for _, key in ipairs(NINE) do
        p[key] = p[key] or frame:CreateTexture(nil, "BORDER")
        setAtlasSized(p[key], art[key], art.scale)
        p[key]:ClearAllPoints()
    end
    p.TopLeftCorner:SetPoint("TOPLEFT")
    p.TopRightCorner:SetPoint("TOPRIGHT")
    p.BottomLeftCorner:SetPoint("BOTTOMLEFT")
    p.BottomRightCorner:SetPoint("BOTTOMRIGHT")
    p.TopEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "TOPRIGHT")
    p.TopEdge:SetPoint("TOPRIGHT", p.TopRightCorner, "TOPLEFT")
    p.BottomEdge:SetPoint("BOTTOMLEFT", p.BottomLeftCorner, "BOTTOMRIGHT")
    p.BottomEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "BOTTOMLEFT")
    p.LeftEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "BOTTOMLEFT")
    p.LeftEdge:SetPoint("BOTTOMLEFT", p.BottomLeftCorner, "TOPLEFT")
    p.RightEdge:SetPoint("TOPRIGHT", p.TopRightCorner, "BOTTOMRIGHT")
    p.RightEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "TOPRIGHT")
    if art.center then
        p.Center = p.Center or frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        p.Center:SetAtlas(art.center)
        p.Center:ClearAllPoints()
        p.Center:SetPoint("TOPLEFT", p.TopLeftCorner, "BOTTOMRIGHT")
        p.Center:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "TOPLEFT")
    end
    return "art"
end

-- Three pieces side by side, as tall as the frame. The caps keep their atlas proportions at that
-- height and are squeezed together when the frame is narrower than both.
function Style:_PaintThree(frame, art, layer)
    local p = frame.__three or {}
    frame.__three = p
    for _, k in ipairs({ "Left", "Center", "Right" }) do
        p[k] = p[k] or frame:CreateTexture(nil, layer or "BACKGROUND")
        p[k]:SetAtlas(art[k])
    end
    local function layout()
        local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
        local li, ri = atlasInfo(art.Left), atlasInfo(art.Right)
        local k = (li and li.height and li.height > 0) and (h / li.height) or 1
        local lw, rw = (li and li.width or 0) * k, (ri and ri.width or 0) * k
        if w > 0 and lw + rw > w then
            local f = w / (lw + rw)
            lw, rw = lw * f, rw * f
        end
        p.Left:ClearAllPoints(); p.Left:SetPoint("TOPLEFT"); p.Left:SetPoint("BOTTOMLEFT"); p.Left:SetWidth(lw)
        p.Right:ClearAllPoints(); p.Right:SetPoint("TOPRIGHT"); p.Right:SetPoint("BOTTOMRIGHT"); p.Right:SetWidth(rw)
        p.Center:ClearAllPoints()
        p.Center:SetPoint("TOPLEFT", p.Left, "TOPRIGHT")
        p.Center:SetPoint("BOTTOMRIGHT", p.Right, "BOTTOMLEFT")
    end
    layout()
    if not frame.__threeHooked then
        frame.__threeHooked = true
        frame:HookScript("OnSizeChanged", layout)
    end
    return p
end

-- Paint `frame` as `role`. In the Forever style with the client's art, the role's art; otherwise,
-- and for any piece the client lacks, today's flat paint.
function Style:Paint(frame, role)
    local art = (self.current == "forever") and self.FOREVER[role] or nil
    if art and self:_HasArt(art) then
        if art.kind == "nine" then return self:_PaintNine(frame, art, role) end
        if role == "titlebar" then self:_PaintFlat(frame, role) end   -- the band behind the art
        if role == "input" then
            local c = roleColor(role)
            frame:SetBackdrop({ bgFile = WHITE })
            frame:SetBackdropColor(c.r, c.g, c.b, 1)
        end
        self:_PaintThree(frame, art, role == "titlebar" and "ARTWORK" or "BORDER")
        return "art"
    end
    return self:_PaintFlat(frame, role)
end
