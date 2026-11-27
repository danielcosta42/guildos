----------------------------------------------------------------------
-- Guild OS - The window (issue #14, ADR-0016)
-- The only container. Every feature is a panel in one resizable window, and
-- every entry point opens it: the slash commands, the minimap button, the
-- guild-frame takeover and the key binding, all through
-- UI:OpenWindow(id, sub) or UI:ToggleMain().
--
-- Since the Salão (specs/salao, #445; phase 3, #449) the title bar holds the
-- guild's crest and name, the rooms (UI/Rooms.lua) as doors, and round tools
-- (Search, Settings, fold, close); a strip under it the open room's entries as
-- pills, or for a side room (the Officers' Room) a side bar. The Search tool
-- opens a strip under those (the mockup's .search): what it finds replaces the
-- screen in the view while there is a query (UI/SearchView.lua). Each entry opens
-- a feature's panel, on its sub-tab when it names one. Settings and Web are
-- behind the gear. The screens sit on the wood; the footer says welcome and
-- when the last sync ran.
--
-- It reorganises by width through the resize ladder (UI/Layout.lua). Doors
-- and pills that do not fit fold into "»n"; under 520px the doors become a
-- one-line selector and the content switches to Home; under 420px only the
-- 28px bar stays, with three numbers. Nothing animates.
-- Position, size and the active tab persist in settings.window.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local NAME         = "GuildOSWindow"
local DEFAULT_W    = 1000
local DEFAULT_H    = 620
local MIN_W        = 320
-- The narrowest a drag of the grip leaves an open window: its content still in the watch band. Only the
-- minimise button folds it to the bar; a window made small by hand used to fold and read as closed.
local DRAG_MIN_W   = 420 + 16 + 2 * 8   -- past the watch band by the ladder's hysteresis
local BAR_H        = 28      -- the whole window in the bar band
local TITLE_H      = 50      -- the title bar: crest, guild, rooms and tools (the mockup's .bar)
local EDGE         = 3       -- the metal frame's width, inside the window's edge
local NARROW       = 620     -- under this: 8px padding
local PAD          = 12
local PAD_NARROW   = 8
local CREST        = 34
local NAME_MAX     = 220     -- the guild's name and its line under it never take more than this
local NAME_MIN     = 70
local DOOR_H       = 32      -- a room's door, standing on the title bar's bottom line
local DOOR_PAD     = 20
local DOOR_GAP     = 1
local SP           = UI.SP   -- the spacing standard (#449)
local ENTRY_H      = 40      -- the open room's entries, as pills on the strip under the bar (#445, #449)
local PILL_H       = SP.HIT
local PILL_PAD     = 24
local PILL_GAP     = 6
local SEARCH_H     = 44      -- the search strip under the pills (the mockup's .search): 8 above and below its field
local SEARCH_FIELD = 28      -- its field, rounded to a pill
local SIDE_W       = 190     -- a side room's bar of entries (the Officers' Room, #447): the mockup's .side-nav
local SIDE_ROW     = 22      -- the side bar fits the default 620px window with every entry
local SIDE_HEAD    = 20
local TAB_MIN_W    = 40
local MORE_W       = 36
local FOOT_H       = 24
local FOOT_PAD     = 12
local TOOL         = 28
local CLOSE_SIZE   = 24
local TOOL_GAP     = 6
local GRIP         = 16
local HOME         = "home"  -- the Now tab
local DASH         = "\226\128\148"
local DOT          = " \194\183 "
local RAQUO        = "\194\187"

BINDING_HEADER_GUILDOS = "Guild OS"
BINDING_NAME_GUILDOS_TOGGLE = L["Open or close Guild OS"]

local function round(n) return math.floor(n + 0.5) end

----------------------------------------------------------------------
-- The guild's tabard in a round crest (#449): background, emblem and border, inside the crest's ring. The layers
-- sit between the crest's sphere (ARTWORK 0) and its ring (ARTWORK 4). The data is Compat's (GuildTabardInfo:
-- the colours and the emblem's file), else the game draws its own (SetLargeGuildTabardTextures). Round by a mask
-- where the client has them (the art's own disc), else the background is the disc itself and the game's square
-- background is drawn inside the circle. Nothing to draw: the layers hide and the guild's initial stays.
--
-- How Blizzard draws the emblem (wow-ui-source, the same on live, classic and classic_era):
--  * The emblem's file (C_GuildInfo.GetGuildTabardInfo().emblemFileID, GetGuildLogoInfo()'s 10th value; it is
--    Textures\GuildEmblems\Emblem_NN, 512x1024 on retail) holds HALF the emblem: its right half, the emblem's
--    middle on the file's left edge. Blizzard draws it twice, side by side, the left one mirrored, cropped to
--    u 0..0.7, v 0.15..0.85, each half twice as tall as wide (94x188), so the whole emblem is a square:
--    https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.xml
--    ($parentGuildEmblemLeft TexCoords 0.7,0,0.15,0.85 / Right 0,0.7,0.15,0.85; SetTexture(emblemFilename) in
--    Blizzard_AchievementUI.lua), and InspectGuildFrame.xml (TabardLeftIcon mirrored, TabardRightIcon plain,
--    SetDoubleGuildTabardTextures). Drawn whole in a square, as before, it showed half an emblem, small and
--    off-centre (WoW: Forever, #449). The crop does not change between clients, so no Compat branch.
--  * SetLargeGuildTabardTextures draws instead from a sheet of whole emblems, Interface\GuildFrame\GuildEmblemsLG_01
--    (1024x1024, 16 columns of 64x64 cells), the cell picked by SetTexCoord from the emblem's style, and squeezes
--    the texture to 7/8 of its height in width:
--    https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_FrameXML/GuildUtil.lua
--    (classic_era: Blizzard_UIParent/TBC/UIParent.lua, the style read from the emblem file's number). On a
--    banner its emblem is 42 high on a 51 high background (Blizzard_Communities/CommunitiesList.xml, 36x42 on 52x51).
----------------------------------------------------------------------
local TABARD_INSET = 3     -- inside the metal ring
local SQUARE_INSET = 8     -- a square inside the circle, where there are no masks
local EMBLEM_HALF = { 0, 0.7, 0.15, 0.85 }   -- Blizzard's crop of the emblem file's half (u0, u1, v0, v1)
local SHEET_HEIGHT = 42 / 51                  -- the sheet's emblem on its background (CommunitiesList.xml)
local SHEET_WIDTH = 7 / 8                     -- SetLargeGuildTabardTextures' width for that height

function UI:TabardLayers(crest)
    local function layer(sub, inset)
        local t = crest:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetPoint("TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", -inset, inset)
        t:Hide()
        return t
    end
    crest.tabBg = layer(1, TABARD_INSET)
    crest.tabEmblem = layer(2, TABARD_INSET)    -- the emblem's left half (mirrored), or the sheet's whole emblem
    crest.tabEmblemR = layer(2, TABARD_INSET)   -- its right half
    crest.tabBorder = layer(3, TABARD_INSET)
    -- One round mask over the disc for both halves (a mask set on a half would be stretched to the half).
    crest.tabMask = GuildOS.Compat.NewMask(crest, GuildOS.Style.ART.circle, TABARD_INSET)
    return crest
end

-- Draws the tabard on a crest made with UI:TabardLayers. Returns how ("info", "game") or nil (the initial stays).
function UI:DrawTabard(crest)
    if not (crest and crest.tabBg) then return nil end
    local Compat, Style = GuildOS.Compat, GuildOS.Style
    local bg, em, emR, bd = crest.tabBg, crest.tabEmblem, crest.tabEmblemR, crest.tabBorder
    local disc = Style.ART.circle
    local size = crest.GetWidth and crest:GetWidth()
    if type(size) ~= "number" or size <= 0 then size = CREST end
    local d = size - 2 * TABARD_INSET          -- the disc's diameter
    local how
    -- The guild's colours and emblem first (C_GuildInfo.GetGuildTabardInfo / GetGuildLogoInfo): a disc in the
    -- background colour, the emblem's two halves (Blizzard's crop, above) filling it in the emblem's colour, the
    -- ring in the border colour.
    local info = Compat.GuildTabardInfo()
    if info then
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", TABARD_INSET, -TABARD_INSET)
        bg:SetPoint("BOTTOMRIGHT", -TABARD_INSET, TABARD_INSET)
        bg:SetTexture(disc)
        bg:SetTexCoord(0, 1, 0, 1)
        bg:SetVertexColor(info.background.r, info.background.g, info.background.b, 1)
        local u0, u1, v0, v1 = EMBLEM_HALF[1], EMBLEM_HALF[2], EMBLEM_HALF[3], EMBLEM_HALF[4]
        for _, half in ipairs({ { em, "RIGHT", u1, u0 }, { emR, "LEFT", u0, u1 } }) do
            local t = half[1]
            t:ClearAllPoints()
            t:SetPoint(half[2], crest, "CENTER", 0, 0)
            t:SetSize(d / 2, d)
            t:SetTexture(info.emblemFile)
            t:SetTexCoord(half[3], half[4], v0, v1)
            t:SetVertexColor(info.emblem.r, info.emblem.g, info.emblem.b, 1)
            Compat.AddMask(t, crest.tabMask)
        end
        bd:SetTexture(Style.ART.ring)
        bd:SetTexCoord(0, 1, 0, 1)
        bd:SetVertexColor(info.border.r, info.border.g, info.border.b, 1)
        bd:Show()
        how = "info"
    elseif Compat.SetGuildTabardTextures(em, bg, bd) then
        -- The sheet's cell, centred at Blizzard's banner proportion (above); its coordinates are the game's.
        em:ClearAllPoints()
        em:SetPoint("CENTER", crest, "CENTER", 0, 0)
        em:SetSize(d * SHEET_HEIGHT * SHEET_WIDTH, d * SHEET_HEIGHT)
        if bg.SetMask ~= nil then
            Compat.SetMask(bg, disc)
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", TABARD_INSET, -TABARD_INSET)
            bg:SetPoint("BOTTOMRIGHT", -TABARD_INSET, TABARD_INSET)
        else
            -- No masks: the game's square background inside the circle.
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", SQUARE_INSET, -SQUARE_INSET)
            bg:SetPoint("BOTTOMRIGHT", -SQUARE_INSET, SQUARE_INSET)
        end
        bd:Hide()   -- its square frame: the crest's own ring is the border
        how = "game"
    end
    bg:SetShown(how ~= nil)
    em:SetShown(how ~= nil)
    emR:SetShown(how == "info")
    if not how then bd:Hide() end
    if crest.letter then crest.letter:SetShown(how == nil) end
    crest.tabard = how
    return how
end

local function store()
    local g = GuildOS:GetSetting("window")
    if type(g) ~= "table" then
        g = {}
        GuildOS:SetSetting("window", g)
    end
    return g
end

local function allowed(key)
    return UI:IsFeatureAllowed(UI:GetFeature(key))
end

local function bandMin(name)
    for _, band in ipairs(UI.LADDER) do
        if band.name == name then return band.min end
    end
    return 0
end

-- The ladder measures the panel hosting the tables, the content area inside
-- the padding, not the window (handoff §6).
local function contentWidth(w)
    return w - 2 * ((w < NARROW) and PAD_NARROW or PAD)
end

local function tabFeatures()
    local out = {}
    for _, id in ipairs(UI.featureOrder) do
        local def = UI.features[id]
        if def.tab then out[#out + 1] = def end
    end
    return out
end

----------------------------------------------------------------------
-- Geometry (settings.window: left, top, w, h, tab, collapsed, restoreW, restoreH)
----------------------------------------------------------------------

-- A saved rectangle kept on a screen of sw × sh: no larger than the screen,
-- no smaller than the bar, and moved back inside when it hangs off an edge.
-- Frame coordinates, origin at the bottom left.
function UI:ClampWindowRect(left, top, w, h, sw, sh)
    w = math.max(MIN_W, math.min(w, sw))
    h = math.max(BAR_H, math.min(h, sh))
    left = math.max(0, math.min(left, sw - w))
    top = math.max(h, math.min(top, sh))
    return left, top, w, h
end

function UI:SaveWindowGeometry(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    local g = store()
    g.left, g.top = round(left), round(top)
    g.w, g.h = round(f:GetWidth()), round(f:GetHeight())
end

-- Absent: 1000×620, centred. Present: where it was, clamped onto the screen.
function UI:RestoreWindowGeometry(f)
    local g = store()
    local scale = f:GetScale()
    if not scale or scale <= 0 then scale = 1 end
    local sw, sh = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
    f:ClearAllPoints()
    if g.left and g.top and g.w and g.h then
        local left, top, w, h = self:ClampWindowRect(g.left, g.top, g.w, g.h, sw, sh)
        f:SetSize(w, h)
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        f:SetSize(math.min(DEFAULT_W, sw), math.min(DEFAULT_H, sh))
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- Anchor by the top-left corner where the window is now, so a size change
-- moves the bottom-right edge instead of both edges around the centre.
local function pinTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

----------------------------------------------------------------------
-- The tab menu: the "»n" overflow, and the one-line selector under 520px.
----------------------------------------------------------------------
-- Drawn as every menu of the addon (UI:PaintMenu, UI:MenuRow; #449): the dark rounded panel under the
-- button, a row per item, the current one marked, a click elsewhere or Escape closes it. The game's
-- UIDropDownMenu drew a square grey list over the window, its highlight off the rows.
local MENU_ROW, MENU_PAD, MENU_MIN = 24, 4, 140
local menu
local function closeMenu()
    if menu then menu:Hide(); menu.catcher:Hide() end
end
local function buildMenu()
    menu = CreateFrame("Frame", "GuildOSTabMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(20)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    UI:PaintMenu(menu)
    menu:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "GuildOSTabMenu") end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(10)
    catcher:EnableMouse(true)
    if catcher.RegisterForClicks then catcher:RegisterForClicks("AnyUp") end
    catcher:SetScript("OnClick", closeMenu)
    catcher:Hide()
    menu.catcher = catcher
    menu:SetScript("OnHide", function() catcher:Hide() end)
    menu.rows = {}
    return menu
end
-- items: { text, checked, func }. The list is kept on UI.lastMenuItems (what the tests read).
local function showListMenu(anchor, items)
    if #items == 0 then return end
    local m = menu or buildMenu()
    if m:IsShown() and m.anchor == anchor then closeMenu(); return end
    m.anchor = anchor
    UI.lastMenuItems = items
    local w = MENU_MIN
    for i, item in ipairs(items) do
        local row = m.rows[i]
        if not row then
            row = UI:MenuRow(m, MENU_ROW)
            m.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", m, "TOPLEFT", MENU_PAD, -(MENU_PAD + (i - 1) * MENU_ROW))
        row:SetPoint("TOPRIGHT", m, "TOPRIGHT", -MENU_PAD, -(MENU_PAD + (i - 1) * MENU_ROW))
        row.label:SetText(item.text or "")
        row:SetChosen(item.checked)
        row:SetScript("OnClick", function()
            closeMenu()
            if item.func then item.func() end
        end)
        row:Show()
        w = math.max(w, math.ceil(tonumber(row.label:GetStringWidth()) or 0) + 30)
    end
    for i = #items + 1, #m.rows do m.rows[i]:Hide() end
    m:SetSize(w + 2 * MENU_PAD, #items * MENU_ROW + 2 * MENU_PAD)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    m.catcher:Show()
    m:Show()
end

-- The rooms: the "»n" overflow, and the one-line selector under 520px.
local function showTabMenu(f, anchor, keys)
    local items = {}
    for _, key in ipairs(keys) do
        local room = UI:RoomById(key)
        items[#items + 1] = { text = room and room.label or key, checked = (key == f.activeRoom),
            func = function() f:OpenRoom(key, true) end }
    end
    showListMenu(anchor, items)
end

-- The entries that did not fit on the row, under its "»n".
local function showEntryMenu(f, anchor, entries)
    local items = {}
    for _, e in ipairs(entries) do
        items[#items + 1] = { text = e.label, checked = (f.activeEntry and f.activeEntry.id == e.id) or false,
            func = function() f:SelectEntry(f.activeRoom, e, true) end }
    end
    showListMenu(anchor, items)
end

----------------------------------------------------------------------
-- Build the window. Tab content is NOT built here: each panel builds the
-- first time its tab is opened.
----------------------------------------------------------------------
local function createWindow()
    local f = UI:CreatePanel(UIParent, NAME)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, BAR_H)
    elseif f.SetMinResize then
        f:SetMinResize(MIN_W, BAR_H)
    end
    f:Hide()
    f:SetScale(GuildOS:GetSetting("uiScale") or 1)
    UI:RefreshHairlines()   -- its lines were sized before the scale (#369)
    UI:RestoreWindowGeometry(f)
    f.tabs, f.tabPanels, f.overflow = {}, {}, {}

    ------------------------------------------------------------------
    -- Title bar (the mockup's .bar): the drag handle. The crest and the guild's name on the left, the rooms
    -- as doors standing on its bottom line, round tools on the right: Search, Settings, fold, close.
    ------------------------------------------------------------------
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", EDGE, -EDGE)
    bar:SetPoint("TOPRIGHT", -EDGE, -EDGE)
    bar:SetHeight(TITLE_H)
    bar:SetFrameLevel(f:GetFrameLevel() + 4)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        pinTopLeft(f)
        UI:SaveWindowGeometry(f)
    end)
    GuildOS.Style:Paint(bar, "titlebar")
    -- Its 2px metal line along the bottom; the open door stands over it.
    local barLine = bar:CreateTexture(nil, "BORDER")
    barLine:SetTexture("Interface\\Buttons\\WHITE8x8")
    barLine:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    barLine:SetHeight(2)
    barLine:SetPoint("BOTTOMLEFT", 0, 0)
    barLine:SetPoint("BOTTOMRIGHT", 0, 0)
    f.titleBar, f.barLine = bar, barLine
    -- Winter Veil's garland hangs under the bar (the mockup's .winter .bar::after), over the strip.
    local garland = GuildOS.Style:Texture(bar, "garland", "OVERLAY", 0, true)
    garland:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 3)
    garland:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 3)
    garland:SetHeight(12)
    garland:Hide()
    f.garland = garland

    local function text(parent, size, role, color)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(fs, size, role)
        fs:SetShadowOffset(0, 0)
        fs:SetTextColor(color.r, color.g, color.b)
        fs:SetWordWrap(false)
        fs:SetJustifyH("LEFT")
        return fs
    end

    -- The crest: the guild's tabard (UI:DrawTabard) or, where the client gives none, its initial, on a dark red
    -- sphere in the bright metal's ring.
    local crest = CreateFrame("Frame", nil, bar)
    crest:SetSize(CREST, CREST)
    crest:SetPoint("LEFT", 10, 0)
    crest.orb = GuildOS.Style:Texture(crest, "orb", "ARTWORK", 0)
    crest.orb:SetAllPoints()
    crest.orb:SetVertexColor(0.42, 0.11, 0.07, 1)
    UI:TabardLayers(crest)
    crest.ring = GuildOS.Style:Texture(crest, "ring", "ARTWORK", 4)
    crest.ring:SetAllPoints()
    crest.ring:SetVertexColor(C.metal2.r, C.metal2.g, C.metal2.b, 1)
    crest.letter = text(crest, nil, "windowTitle", { r = 1, g = 0.824, b = 0.29 })
    crest.letter:SetJustifyH("CENTER")
    crest.letter:SetPoint("CENTER", 0, 0)
    f.crest = crest

    -- The guild's name in the title serif and gold, "N online · realm" under it.
    local guildName = text(bar, nil, "windowTitle", C.gold)
    guildName:SetPoint("TOPLEFT", crest, "TOPRIGHT", 8, -1)
    f.nameText = guildName
    local meta = text(bar, 11, nil, C.textSoft)
    meta:SetPoint("TOPLEFT", guildName, "BOTTOMLEFT", 0, -2)
    f.metaText = meta

    local close = UI:TitleBarButton(bar, "close")
    close:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton = close

    -- Fold to the bar and back: a round tool with a dash (a plus while folded).
    local minimise = UI:TitleBarButton(bar, "tool", DASH, TOOL)
    minimise.x = minimise.glyph
    minimise:SetScript("OnClick", function() f:ToggleCollapsed() end)
    f.minimise = minimise

    -- Search and Settings, round tools left of the fold. Children of the bar through UI:TitleBarButton: as
    -- siblings its drag would take every click. Settings and Web live behind the gear since the rooms (#445);
    -- the site and /gos help are in its tooltip and on Settings' Data page (the footer's links went, #449).
    local function tool(icon, tip, lines, run)
        local b = UI:TitleBarButton(bar, "tool", icon, TOOL)
        b:SetScript("OnClick", run)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(tip, C.text.r, C.text.g, C.text.b)
            for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, C.textSoft.r, C.textSoft.g, C.textSoft.b) end
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    -- Search opens and closes the strip under the pills (#449): no window of its own.
    local searchBtn = tool("icon-search", L["Search"], nil, function() f:ToggleSearch() end)
    local gearBtn = tool("icon-gear", L["Settings"],
        { "Guild OS v" .. tostring(GuildOS.VERSION or ""), "guildos.me", "/gos help" },
        function() f:OpenRoom("settings", true) end)
    f.searchButton, f.settingsButton = searchBtn, gearBtn

    local summary = text(bar, 11, nil, C.text)
    summary:SetPoint("LEFT", 10, 0)
    summary:SetPoint("RIGHT", minimise, "LEFT", -6, 0)
    summary:Hide()
    f.summaryText = summary
    -- The folded bar's three numbers, unlabelled to fit: the pointer on them says what they are, and a
    -- click opens the window back up.
    local summaryHit = CreateFrame("Button", nil, bar)
    summaryHit:SetPoint("TOPLEFT", summary, "TOPLEFT", 0, 4)
    summaryHit:SetPoint("BOTTOMRIGHT", summary, "BOTTOMRIGHT", 0, -4)
    summaryHit:Hide()
    summaryHit:SetScript("OnClick", function() f:ToggleCollapsed() end)
    summaryHit:SetScript("OnEnter", function(self)
        local A = GuildOS.Agora
        if not (A and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Guild OS")
        GameTooltip:AddLine(string.format(L["%d online"], tonumber(A:OnlineCount()) or 0), 1, 1, 1)
        local raid = A:NextRaid()
        GameTooltip:AddLine(L["Next raid"] .. ": " .. (raid and A.Short(raid.when - GetServerTime()) or "\226\128\148"), 1, 1, 1)
        GameTooltip:AddLine(string.format(L["Waiting on you: %d"], #A:NeedsMe()), 1, 1, 1)
        GameTooltip:AddLine(L["Click to open the window."], C.textSoft.r, C.textSoft.g, C.textSoft.b)
        GameTooltip:Show()
    end)
    summaryHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.summaryHit = summaryHit

    ------------------------------------------------------------------
    -- The rooms: doors in the title bar (the mockup's .door), "»n" and the one-line selector
    ------------------------------------------------------------------
    local rule = CreateFrame("Frame", nil, bar)
    rule:SetHeight(DOOR_H)
    f.rule = rule

    -- A door: the room's name; the open one raised in the wood with the metal's line round its top, its name gold
    -- and bold, standing on the bar's bottom line (the mockup's .door[aria-current]). The Officers' Room's name is the soft gold, with its count.
    local function door(room)
        local d = CreateFrame("Button", nil, rule)
        d:SetHeight(DOOR_H)
        d.key = room.id
        d.fill = GuildOS.Style:Nine(d, "card", 6, "BACKGROUND", 1, nil, "bottom")
        d.fill:SetColor(C.wood)
        d.edge = GuildOS.Style:Nine(d, "card-line", 6, "BACKGROUND", 2, nil, "bottom")
        d.edge:SetColor(C.lineHi)
        d.label = text(d, 13, nil, C.door)
        d.label:SetPoint("CENTER", 0, -1)
        d.label:SetText(room.label)
        if room.officer then
            d.count = UI:CreateCount(d)
            d.count:SetPoint("LEFT", d.label, "RIGHT", 5, 0)
        end
        -- The name moves left by half the count, so the two sit centred in the door together.
        local function centre(self)
            local shift = (self.count and self.count:IsShown()) and (self.count:GetWidth() + 5) / 2 or 0
            self.label:ClearAllPoints()
            self.label:SetPoint("CENTER", -shift, -1)
        end
        local function paint(self, hovered)
            local active = self.isActive and true or false
            self.fill:SetShown(active)
            self.edge:SetShown(active)
            if active ~= self.__bold then
                self.__bold = active
                GuildOS:ApplyFont(self.label, 13, active and "button" or nil)
            end
            local ink = (active and C.gold) or (hovered and C.text) or (room.officer and C.gold2) or C.door
            self.label:SetTextColor(ink.r, ink.g, ink.b)
        end
        function d:SetActive(v) self.isActive = v; paint(self, false) end
        function d:Width()
            centre(self)
            local w = math.ceil(self.label:GetStringWidth()) + DOOR_PAD
            if self.count and self.count:IsShown() then w = w + self.count:GetWidth() + 5 end
            return math.max(TAB_MIN_W, w)
        end
        d:SetScript("OnEnter", function(self) paint(self, true) end)
        d:SetScript("OnLeave", function(self) paint(self, false) end)
        d:SetScript("OnClick", function() f:OpenRoom(room.id, true) end)
        d:SetActive(false)
        d:Hide()
        return d
    end
    for _, room in ipairs(UI.ROOMS) do
        if not room.gear then f.tabs[#f.tabs + 1] = door(room) end
    end

    local more = UI:SetButtonVariant(UI:CreateButton(rule, "", MORE_W, 22), "ghost")
    more:SetScript("OnClick", function(self) showTabMenu(f, self, f.overflow) end)
    more:Hide()
    f.more = more

    local selector = UI:SetButtonVariant(UI:CreateButton(rule, "", 120, 22), "ghost")
    selector:SetPoint("BOTTOMLEFT", rule, "BOTTOMLEFT", 4, 6)
    selector:SetScript("OnClick", function(self)
        local keys = {}
        for _, room in ipairs(UI:VisibleRooms()) do keys[#keys + 1] = room.id end
        showTabMenu(f, self, keys)
    end)
    selector:Hide()
    f.selector = selector

    ------------------------------------------------------------------
    -- The open room's entries, as pills on a strip under the bar (the mockup's .subs); drawn only when the
    -- room has more than one.
    ------------------------------------------------------------------
    local entryRow = CreateFrame("Frame", nil, f)
    entryRow:SetHeight(ENTRY_H)
    entryRow:SetFrameLevel(f:GetFrameLevel() + 3)
    local stripBg = entryRow:CreateTexture(nil, "BACKGROUND")
    stripBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    stripBg:SetAllPoints()
    stripBg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
    local entryLine = UI:CreateSeparator(entryRow)
    entryLine:SetVertexColor(0.29, 0.208, 0.098, 1)   -- #4a3519, the strip's own line
    entryLine:SetPoint("BOTTOMLEFT", 0, 0)
    entryLine:SetPoint("BOTTOMRIGHT", 0, 0)
    entryRow:Hide()
    f.entryRow, f.entryTabs, f.entryOverflow = entryRow, {}, {}
    local entryMore = UI:SetButtonVariant(UI:CreateButton(entryRow, "", MORE_W, 20), "ghost")
    entryMore:SetPoint("RIGHT", entryRow, "RIGHT", -10, 0)
    entryMore:SetScript("OnClick", function(self) showEntryMenu(f, self, f.entryOverflow) end)
    entryMore:Hide()
    f.entryMore = entryMore

    -- A side room's entries (#447): the mockup's .side-nav, a dark card left of the content, its groups headed
    -- in the title serif and the soft gold, the open entry a gold pill, a red count where work waits.
    local sideNav = UI:CreatePanel(f)
    sideNav:SetFrameLevel(f:GetFrameLevel() + 3)
    sideNav:SetWidth(SIDE_W)
    sideNav:Hide()
    f.sideNav, f.sideBtns, f.sideHeads = sideNav, {}, {}

    ------------------------------------------------------------------
    -- The search (#449, the mockup's .search): a strip under the pills with one rounded dark field across the
    -- window, opened and closed by the Search tool, focused at once; Escape closes it too. While it holds a
    -- query (Search.MIN characters) what it finds is drawn in the content's place (UI/SearchView.lua): Up and
    -- Down choose a result, Enter opens it. Closing it shows the screen that was open again.
    ------------------------------------------------------------------
    local searchRow = CreateFrame("Frame", nil, f)
    searchRow:SetHeight(SEARCH_H)
    searchRow:SetFrameLevel(f:GetFrameLevel() + 3)
    local searchBg = searchRow:CreateTexture(nil, "BACKGROUND")
    searchBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    searchBg:SetAllPoints()
    searchBg:SetVertexColor(C.popup.r, C.popup.g, C.popup.b, 1)
    local searchLine = UI:CreateSeparator(searchRow)
    searchLine:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    searchLine:SetPoint("BOTTOMLEFT", 0, 0)
    searchLine:SetPoint("BOTTOMRIGHT", 0, 0)
    searchRow:Hide()
    local searchBox = UI:CreateInput(searchRow, 200, SEARCH_FIELD,
        { max = 60, placeholder = L["Search member, item, recipe or screen…"], corner = SEARCH_FIELD / 2 })
    searchBox:SetTextInsets(14, 14, 0, 0)
    if searchBox.placeholder then
        searchBox.placeholder:ClearAllPoints()
        searchBox.placeholder:SetPoint("LEFT", 14, 0)
    end
    searchBox:SetPoint("LEFT", searchRow, "LEFT", PAD, 0)
    searchBox:SetPoint("RIGHT", searchRow, "RIGHT", -PAD, 0)
    f.searchRow, f.searchBox = searchRow, searchBox

    -- The results: in the content's rectangle, shown in its place.
    local results = CreateFrame("Frame", nil, f)
    results:SetFrameLevel(f:GetFrameLevel() + 2)
    results:Hide()
    f.searchResults = results

    ------------------------------------------------------------------
    -- The view: the wood behind the screens (the mockup's .view), painted on the window itself so every
    -- panel that drew over the window's background still draws over it. `view` only holds the rectangle.
    ------------------------------------------------------------------
    local view = CreateFrame("Frame", nil, f)
    f.view = view
    f.wood = UI:PaintWood(f, view)

    ------------------------------------------------------------------
    -- Content: one empty panel per tab
    ------------------------------------------------------------------
    local content = CreateFrame("Frame", nil, f)
    content:SetFrameLevel(f:GetFrameLevel() + 2)
    -- Clipping is the net under the ladder: a panel that has not learnt the
    -- narrow bands yet is cut at the window's edge instead of painting past it.
    if content.SetClipsChildren then content:SetClipsChildren(true) end
    f.content = content
    for _, def in ipairs(tabFeatures()) do
        local panel = CreateFrame("Frame", nil, content)
        panel:SetAllPoints(content)
        panel:Hide()
        panel.featureId = def.id
        f.tabPanels[def.id] = panel
    end

    ------------------------------------------------------------------
    -- Footer (the mockup's .foot): "Welcome back, <name>." on the left, "● Updated: <when>" on the right, a
    -- click on which syncs. Its links (#377) went: the site and /gos help are in the gear's tooltip and on
    -- Settings' Data page, the Blizzard guild window a button there.
    ------------------------------------------------------------------
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", EDGE, EDGE)
    foot:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    foot:SetHeight(FOOT_H)
    foot:SetFrameLevel(f:GetFrameLevel() + 3)
    local footBg = foot:CreateTexture(nil, "BACKGROUND")
    footBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    footBg:SetAllPoints()
    footBg:SetVertexColor(C.popup.r, C.popup.g, C.popup.b, 1)
    local footLine = UI:CreateSeparator(foot)
    footLine:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    footLine:SetPoint("TOPLEFT", 0, 0)
    footLine:SetPoint("TOPRIGHT", 0, 0)
    f.footer = foot

    local welcome = text(foot, 11, nil, C.label)
    welcome:SetPoint("LEFT", foot, "LEFT", FOOT_PAD, 0)
    f.welcomeText = welcome

    local sync = text(foot, 11, nil, C.label)
    sync:SetJustifyH("RIGHT")
    sync:SetPoint("RIGHT", foot, "RIGHT", -(FOOT_PAD + GRIP), 0)
    f.syncText, f.footRight = sync, sync
    local dot = GuildOS.Style:Texture(foot, "circle", "ARTWORK", 0)
    dot:SetSize(7, 7)
    dot:SetPoint("RIGHT", sync, "LEFT", -6, 0)
    f.syncDot = dot
    -- The sync, from the line that says when it last ran.
    local syncBtn = CreateFrame("Button", nil, foot)
    syncBtn:SetPoint("TOPLEFT", dot, "TOPLEFT", -2, 6)
    syncBtn:SetPoint("BOTTOMRIGHT", sync, "BOTTOMRIGHT", 2, -6)
    syncBtn:SetScript("OnClick", function() if GuildOS.CommSystem then GuildOS.CommSystem:FullSync() end end)
    syncBtn:SetScript("OnEnter", function(self)
        sync:SetTextColor(C.text.r, C.text.g, C.text.b)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Sync"], C.text.r, C.text.g, C.text.b)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function()
        sync:SetTextColor(C.label.r, C.label.g, C.label.b)
        GameTooltip:Hide()
    end)
    f.syncButton = syncBtn

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    local function bounds(w, h)
        if f.SetResizeBounds then f:SetResizeBounds(w, h)
        elseif f.SetMinResize then f:SetMinResize(w, h) end
    end
    grip:SetScript("OnMouseDown", function()
        pinTopLeft(f)
        f.sizingFrom = { f:GetWidth(), f:GetHeight() }
        f.sizingFolded = store().collapsed and true or false
        -- Open, it stops at the watch band; folded, it stays the bar it is.
        if not f.sizingFolded then bounds(DRAG_MIN_W, 240) end
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        bounds(MIN_W, BAR_H)
        f:Settle()
    end)
    f.grip = grip

    ------------------------------------------------------------------
    -- Tabs
    ------------------------------------------------------------------

    -- Open a tab, building its panel the first time. `byUser` remembers it
    -- across /reload; the switch to Now under 520px is not remembered.
    function f:SetActiveTab(key, byUser)
        local def = UI:GetFeature(key)
        local panel = self.tabPanels[key]
        if not (panel and allowed(key)) then return false end
        -- A panel that raised while building is half-built, so it stays
        -- refused until /reload instead of opening empty.
        if not panel.built then
            panel.built = true
            panel.buildFailed = not GuildOS:RunStartup("Tab:" .. key, nil, def.build, panel, self)
            panel.OnSubChanged = function(sub) self:FollowSub(key, sub) end
        end
        if panel.buildFailed then
            GuildOS:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
            return false
        end
        self.activeTab = key
        if byUser then
            store().tab = key
            self.beforeWatch = nil
        end
        -- Opened by its feature (the narrow band's switch to Home, a saved tab): the room that holds it.
        if not (self.activeEntry and self.activeEntry.feature == key) then
            local room, entry = UI:RoomOf(key)
            self.activeRoom, self.activeEntry = room and room.id, entry
        end
        -- Showing a hub fires OnShow on the sub-tab it was left on, not the entry's: that is no choice of the
        -- player, so FollowSub ignores it while the panels switch.
        self.switching = true
        for k, p in pairs(self.tabPanels) do p:SetShown(k == key) end
        self.switching = nil
        if panel.SetSubBarShown then panel.SetSubBarShown(not (self.activeEntry and self.activeEntry.sub)) end
        self:LayoutTabs()
        return true
    end

    -- Open a room's entry: its feature's panel, on the entry's sub-tab (or `sub`, a deep link's), with
    -- `filter` for the sub-tab that takes one. Remembered per room, so a room opens where it was left.
    function f:SelectEntry(roomId, entry, byUser, sub, filter)
        if not (entry and UI:EntryAllowed(entry)) then return false end
        -- An action, not a screen (Core Sign-up): it runs, and the screen on show stays.
        if entry.run then
            GuildOS:SafeCall(entry.run)
            return true
        end
        -- A screen asked for by the player (a door, a pill, a command) leaves the search's results.
        if byUser and self.searching then self:CloseSearch() end
        local prevRoom, prevEntry = self.activeRoom, self.activeEntry
        self.activeRoom, self.activeEntry = roomId, entry
        if not self:SetActiveTab(entry.feature, byUser) then
            self.activeRoom, self.activeEntry = prevRoom, prevEntry
            self:LayoutTabs()
            return false
        end
        if byUser then
            local g = store()
            g.room = roomId
            g.entries = type(g.entries) == "table" and g.entries or {}
            g.entries[roomId] = entry.id
        end
        local panel = self.tabPanels[entry.feature]
        local want = sub or entry.sub
        if want and panel and panel.SelectSub then panel.SelectSub(want, filter) end
        -- The panel may land elsewhere (a sub-tab that failed to build falls back to the calendar): the
        -- marked entry follows the screen actually drawn.
        if entry.sub and panel and panel.activeSub and panel.activeSub ~= entry.sub then
            local r2, e2 = UI:RoomOf(entry.feature, panel.activeSub)
            if e2 and e2.sub == panel.activeSub then
                self.activeRoom, self.activeEntry = r2.id, e2
                self:LayoutTabs()
            end
        end
        return true
    end

    -- The panel showed sub-tab `sub` itself (a button inside it, the hub's own fallback): the room marks and
    -- remembers the entry that names it, when there is one. Nothing changes while another screen is open.
    function f:FollowSub(feature, sub)
        local e = self.activeEntry
        if self.switching then return end
        if self.activeTab ~= feature or not (e and e.feature == feature and e.sub) or e.sub == sub then return end
        local r2, e2 = UI:RoomOf(feature, sub)
        if not (e2 and e2.sub == sub) then return end
        self.activeRoom, self.activeEntry = r2.id, e2
        local g = store()
        g.room = r2.id
        g.entries = type(g.entries) == "table" and g.entries or {}
        g.entries[r2.id] = e2.id
        self:LayoutTabs()
    end

    -- A room from its tab: the entry it was left on, else its first.
    function f:OpenRoom(roomId, byUser)
        if not UI:RoomAllowed(roomId) then return false end
        local saved = type(store().entries) == "table" and store().entries[roomId] or nil
        return self:SelectEntry(roomId, UI:RoomDefault(roomId, saved), byUser)
    end

    ------------------------------------------------------------------
    -- The search strip (#449)
    ------------------------------------------------------------------
    local function queryOf() return strtrim(searchBox:GetText() or "") end

    -- Whether the results stand in the content's place: the strip open, not folded to the bar, with a query of
    -- Search.MIN characters or more.
    function f:SearchShowing()
        local S = GuildOS.Search
        if not (self.searchOpen and self.band ~= "bar" and S and S.Chars) then return false end
        return S.Chars(queryOf()) >= (S.MIN or 2)
    end

    -- The results again, at the size the layout gave their frame.
    function f:RenderSearch()
        if self.searching and UI.SearchView then
            GuildOS:SafeCall(UI.SearchView.Render, UI.SearchView, results, queryOf(), self.searchW or 1, self.searchH or 1)
        end
    end

    -- The query changed: the content and the results swap when it crosses Search.MIN (a layout, which draws
    -- the results), else the results follow it.
    function f:RunSearch()
        if self:SearchShowing() ~= (self.searching or false) then self:LayoutTabs() else self:RenderSearch() end
    end

    -- Open the strip, with `text` in it (/gos find), the field focused.
    function f:OpenSearch(initial)
        searchBox:SetText(initial or "")
        self.searchOpen = true
        searchBtn:SetPressed(true)
        searchBox:SetFocus()
        self:LayoutTabs()
    end

    -- Close it: the field emptied, the screen it covered shown again.
    function f:CloseSearch()
        if not self.searchOpen then return end
        self.searchOpen = nil
        searchBtn:SetPressed(false)
        searchBox:SetText("")
        searchBox:ClearFocus()
        self:LayoutTabs()
    end

    function f:ToggleSearch()
        if self.searchOpen then self:CloseSearch() else self:OpenSearch() end
    end

    -- The hint stays while the field is empty, focused or not (the mockup's placeholder): the strip opens
    -- focused, and an empty strip has to say what it finds.
    local function hint()
        if searchBox.placeholder then searchBox.placeholder:SetShown((searchBox:GetText() or "") == "") end
    end
    searchBox:HookScript("OnEditFocusGained", hint)
    searchBox:HookScript("OnTextChanged", hint)
    searchBox:HookScript("OnTextChanged", function() if f.searchOpen then f:RunSearch() end end)
    searchBox:HookScript("OnEscapePressed", function() f:CloseSearch() end)
    searchBox:SetScript("OnEnterPressed", function()
        if f.searching and UI.SearchView then UI.SearchView:Activate(results) end
    end)
    searchBox:SetScript("OnArrowPressed", function(_, key)
        if not (f.searching and UI.SearchView) then return end
        if key == "UP" then UI.SearchView:Move(results, -1) elseif key == "DOWN" then UI.SearchView:Move(results, 1) end
    end)
    if searchBox.SetAltArrowKeyMode then searchBox:SetAltArrowKeyMode(false) end

    -- Re-check which tabs may show (rank, loot system, alliance, Settings
    -- toggles and start-up failures all change it without a reload) and fall
    -- back to Now when the open tab is no longer allowed.
    function f:UpdateTabVisibility()
        self:InvalidateOfficerCounts()
        -- An entry that may no longer open (a rank change, the Winter Veil event over) counts as closed.
        if self.activeEntry and not UI:EntryAllowed(self.activeEntry) then self.activeEntry = nil end
        -- A room that may no longer show (an officer demoted with the Officers' Room open) closes too.
        if self.activeRoom and not UI:RoomAllowed(self.activeRoom) then self.activeEntry = nil end
        if not (self.activeTab and allowed(self.activeTab) and self.activeEntry) then
            local panel = self.activeTab and self.tabPanels[self.activeTab]
            if panel then panel:Hide() end
            self.activeTab = nil
            -- Not to a Now tab that failed to build: this runs on every group
            -- change, and the refusal would print each time.
            local home = self.tabPanels[HOME]
            if not (home and home.buildFailed) then self:SetActiveTab(HOME) end
        end
        self:LayoutTabs()
    end

    -- The officers' work waiting (UI.Agora:OfficerCounts): the door's total and each entry's own. That walks
    -- the whole roster (Agora:NeedsMe), so it is kept on the window and counted again only after the 10s tick, a
    -- roster update or a re-check of the tabs drops it (UpdateTabVisibility); a layout or a resize reads it.
    function f:RefreshOfficerCounts()
        local A = UI.Agora
        local total, by = 0, {}
        if A and A.OfficerCounts then
            GuildOS:SafeCall(function() total, by = A:OfficerCounts() end)
        end
        self.officerTotal, self.officerBy = total or 0, by or {}
        return self.officerTotal, self.officerBy
    end
    -- Counted again at the next layout (a change the tick has not seen yet: a trial added, a rank changed).
    function f:InvalidateOfficerCounts() self.officerTotal, self.officerBy = nil, nil end
    local function officerCounts()
        if f.officerTotal == nil then return f:RefreshOfficerCounts() end
        return f.officerTotal, f.officerBy
    end

    -- Where the doors go: from past the guild's name to short of the tools.
    function f:DoorSpan(w)
        w = w or self:GetWidth() or 0
        local x0 = self.doorsX or (10 + CREST + 8 + NAME_MIN + 10)
        local tools = 10 + CLOSE_SIZE + 3 * (TOOL + TOOL_GAP) + 8
        return x0, math.max(0, (w - 2 * EDGE) - tools - x0)
    end

    function f:LayoutTabs(w)
        w = w or self:GetWidth() or 0
        local visible = {}
        for _, room in ipairs(UI:VisibleRooms()) do visible[room.id] = true end
        local total = officerCounts()
        local shown = {}
        for _, tab in ipairs(self.tabs) do
            tab:Hide()
            tab:SetActive(tab.key == self.activeRoom)
            if tab.count then tab.count:SetCount(total) end
            if visible[tab.key] then shown[#shown + 1] = tab end
        end
        self.overflow = {}
        more:Hide()
        selector:SetShown(self.band == "watch")
        local x0, span = self:DoorSpan(w)
        rule:ClearAllPoints()
        rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x0, 0)
        rule:SetWidth(math.max(1, span))
        self:LayoutEntries(w)
        if self.band == "watch" then
            local room = UI:RoomById(self.activeRoom)
            selector.label:SetText((room and room.label or "") .. " " .. RAQUO)
            selector:SetWidth(math.ceil(selector.label:GetStringWidth()) + 16)
            return
        end
        if self.band == "bar" then return end

        local widths, active = {}, nil
        for i, tab in ipairs(shown) do
            widths[i] = tab:Width()
            if tab.key == self.activeRoom then active = i end
        end
        local fit, hidden = UI:FitTabs(widths, span, DOOR_GAP, MORE_W, active)
        local x, placed = 0, {}
        for _, i in ipairs(fit) do
            local tab = shown[i]
            tab:ClearAllPoints()
            -- On the bar's 2px line.
            tab:SetPoint("BOTTOMLEFT", rule, "BOTTOMLEFT", x, 2)
            tab:SetWidth(widths[i])
            tab:Show()
            x = x + widths[i] + DOOR_GAP
            placed[i] = true
        end
        for i, tab in ipairs(shown) do
            if not placed[i] then self.overflow[#self.overflow + 1] = tab.key end
        end
        if hidden > 0 then
            more.label:SetText(RAQUO .. hidden)
            more:ClearAllPoints()
            more:SetPoint("BOTTOMLEFT", rule, "BOTTOMLEFT", x + 2, 8)
            more:Show()
        end
    end

    -- The open room's entries on the strip under the bar, and the content below whatever is drawn. A room with
    -- a single entry draws no strip: its one screen starts right under the bar.
    function f:LayoutEntries(w)
        w = w or self:GetWidth() or 0
        -- Only entries whose feature has a panel: a tab another addon registers after the window was built
        -- has none, and would be a button that does nothing.
        local list = {}
        for _, e in ipairs(self.activeRoom and UI:RoomEntries(self.activeRoom) or {}) do
            if self.tabPanels[e.feature] then list[#list + 1] = e end
        end
        local room = self.activeRoom and UI:RoomById(self.activeRoom)
        local top, pad = self.layoutTop or 0, self.layoutPad or PAD
        local _, counts = officerCounts()
        local function countOf(e)
            return (e.sub and counts[e.feature .. ":" .. e.sub]) or (not e.sub and counts[e.feature])
                or (e.needs and counts[e.needs]) or 0
        end
        -- The side bar only while it fits: the content keeps a table's width beside it (medium and up), and the
        -- window is tall enough for every row; otherwise the room folds into the strip like any other.
        local side = false
        if room and room.side and #list > 0 and (self.band == "full" or self.band == "wide" or self.band == "medium") then
            local need, groups, seen = 16, 0, {}
            for _, e in ipairs(list) do
                if e.group and not seen[e.group] then seen[e.group] = true; groups = groups + 1 end
                need = need + SIDE_ROW
            end
            need = need + groups * SIDE_HEAD + math.max(0, groups - 1) * 6
            local room_h = (self:GetHeight() or 0) - (top + 2 * pad + EDGE + FOOT_H)
            side = need <= room_h
        end
        -- The search's results take the whole view: the side bar steps aside while they show.
        local searching = self:SearchShowing()
        self.searching = searching
        sideNav:SetShown(side and not searching)
        for _, b in ipairs(self.sideBtns) do b:Hide() end
        for _, h in ipairs(self.sideHeads) do h:Hide() end
        local rowShown = not side and #list > 1 and self.band ~= "bar"
        entryRow:SetShown(rowShown)
        for _, btn in ipairs(self.entryTabs) do btn:Hide() end
        entryMore:Hide()
        self.entryOverflow = {}
        if rowShown then
            entryRow:ClearAllPoints()
            entryRow:SetPoint("TOPLEFT", EDGE, -top)
            entryRow:SetPoint("TOPRIGHT", -EDGE, -top)
            local widths, active = {}, nil
            for i, entry in ipairs(list) do
                local btn = self.entryTabs[i]
                if not btn then
                    btn = UI:CreateTab(entryRow, "", TAB_MIN_W, true)
                    btn:SetHeight(PILL_H)
                    btn.count = UI:CreateCount(btn)
                    btn.count:SetPoint("LEFT", btn.label, "RIGHT", 4, 0)
                    btn:SetScript("OnClick", function(b) f:SelectEntry(f.activeRoom, b.entry, true) end)
                    self.entryTabs[i] = btn
                end
                btn.entry = entry
                btn.label:SetText(entry.label)
                btn.count:SetCount(countOf(entry))
                widths[i] = math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + PILL_PAD
                    + (btn.count:IsShown() and (btn.count:GetWidth() + 4) or 0))
                if self.activeEntry and self.activeEntry.id == entry.id then active = i end
            end
            -- Entries that do not fit fold into "»n", as the rooms do.
            local fit, hidden = UI:FitTabs(widths, w - 2 * EDGE - 2 * PAD, PILL_GAP, MORE_W, active)
            local x, placed = PAD, {}
            for _, i in ipairs(fit) do
                local btn = self.entryTabs[i]
                btn:SetWidth(widths[i])
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", entryRow, "LEFT", x, 0)
                btn:SetActive(i == active)
                -- The label sits left of the count when there is one.
                btn.label:ClearAllPoints()
                btn.label:SetPoint("CENTER", btn, "CENTER", btn.count:IsShown() and -(btn.count:GetWidth() + 4) / 2 or 0, 0)
                btn:Show()
                x = x + widths[i] + PILL_GAP
                placed[i] = true
            end
            for i, entry in ipairs(list) do
                if not placed[i] then self.entryOverflow[#self.entryOverflow + 1] = entry end
            end
            if hidden > 0 then
                entryMore.label:SetText(RAQUO .. hidden)
                entryMore:Show()
            end
        end
        local below = top + (rowShown and ENTRY_H or 0)
        -- The search strip, under the pills (or the bar when there are none).
        local stripShown = self.searchOpen and self.band ~= "bar" or false
        searchRow:SetShown(stripShown)
        if stripShown then
            searchRow:ClearAllPoints()
            searchRow:SetPoint("TOPLEFT", EDGE, -below)
            searchRow:SetPoint("TOPRIGHT", -EDGE, -below)
            below = below + SEARCH_H
        end
        view:ClearAllPoints()
        view:SetPoint("TOPLEFT", EDGE, -below)
        view:SetPoint("BOTTOMRIGHT", -EDGE, EDGE + FOOT_H)
        local left = pad
        if side and not searching then
            local y0 = below + pad
            sideNav:ClearAllPoints()
            sideNav:SetPoint("TOPLEFT", EDGE + pad, -y0)
            sideNav:SetHeight(1)
            local y, group, nb, nh = 8, nil, 0, 0
            for _, entry in ipairs(list) do
                if entry.group and entry.group ~= group then
                    group = entry.group
                    nh = nh + 1
                    local h = self.sideHeads[nh]
                    if not h then
                        h = sideNav:CreateFontString(nil, "OVERLAY")
                        GuildOS:ApplyFont(h, 11, "sectionTitle")
                        h:SetShadowOffset(0, 0)
                        h:SetJustifyH("LEFT")
                        self.sideHeads[nh] = h
                    end
                    h:SetTextColor(C.gold2.r, C.gold2.g, C.gold2.b)
                    h:SetText(group)
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", 14, -(y + (nh > 1 and 6 or 0) + 4))
                    h:Show()
                    y = y + SIDE_HEAD + (nh > 1 and 6 or 0)
                end
                nb = nb + 1
                local b = self.sideBtns[nb]
                if not b then
                    b = UI:CreateTab(sideNav, "", SIDE_W - 16, true)
                    b:SetHeight(SIDE_ROW - 2)
                    b.label:ClearAllPoints()
                    b.label:SetPoint("LEFT", 10, 0)
                    b.label:SetJustifyH("LEFT")
                    b.count = UI:CreateCount(b)
                    b.count:SetPoint("RIGHT", -8, 0)
                    b:SetScript("OnClick", function(btn) f:SelectEntry(f.activeRoom, btn.entry, true) end)
                    self.sideBtns[nb] = b
                end
                b.entry = entry
                b.label:SetText(entry.label)
                b.count:SetCount(countOf(entry))
                b:SetWidth(SIDE_W - 16)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 8, -y)
                b:SetActive(self.activeEntry and self.activeEntry.id == entry.id or false)
                b:Show()
                y = y + SIDE_ROW
            end
            sideNav:SetHeight(y + 8)
            left = pad + SIDE_W + UI.GAP
        end
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", EDGE + left, -(below + pad))
        content:SetPoint("BOTTOMRIGHT", -(EDGE + pad), EDGE + FOOT_H + pad)
        -- The results in the content's place, at the size worked out here (never read back from a frame).
        results:ClearAllPoints()
        results:SetPoint("TOPLEFT", EDGE + pad, -(below + pad))
        results:SetPoint("BOTTOMRIGHT", -(EDGE + pad), EDGE + FOOT_H + pad)
        self.searchW = math.max(1, w - 2 * EDGE - 2 * pad)
        self.searchH = math.max(1, (self:GetHeight() or 0) - (below + pad) - (EDGE + FOOT_H + pad))
        if self.band ~= "bar" then content:SetShown(not searching) end
        results:SetShown(searching)
        if searching then self:RenderSearch() end
    end

    -- "Welcome back" keeps the left, shortened to what is left beside the sync line (and the snow's parcel,
    -- `footReserve`, UI/Snow.lua).
    function f:LayoutFooter(w)
        w = w or self:GetWidth() or 0
        local room = w - 2 * EDGE - 2 * FOOT_PAD - GRIP - math.ceil(sync:GetStringWidth()) - 13 - 12 - (self.footReserve or 0)
        welcome:SetWidth(math.max(0, room))
        welcome:SetShown(room > 40)
    end

    -- The crest, the guild's name and its line, the doors and the tools. The name block keeps what it needs up
    -- to NAME_MAX, never under NAME_MIN; the doors take the rest up to the tools, folding into "»n". Folded to
    -- the bar only the three numbers stay, as before.
    function f:LayoutTitle(w)
        w = w or self:GetWidth() or 0
        local isBar = self.band == "bar"
        summary:SetShown(isBar)
        summaryHit:SetShown(isBar)
        crest:SetShown(not isBar)
        guildName:SetShown(not isBar)
        meta:SetShown(not isBar)
        searchBtn:SetShown(not isBar)
        gearBtn:SetShown(not isBar)
        rule:SetShown(not isBar)
        close:ClearAllPoints()
        close:SetPoint("RIGHT", bar, "RIGHT", isBar and -(GRIP + 2) or -10, 0)
        minimise:ClearAllPoints()
        minimise:SetPoint("RIGHT", close, "LEFT", -TOOL_GAP, 0)
        gearBtn:ClearAllPoints()
        gearBtn:SetPoint("RIGHT", minimise, "LEFT", -TOOL_GAP, 0)
        searchBtn:ClearAllPoints()
        searchBtn:SetPoint("RIGHT", gearBtn, "LEFT", -TOOL_GAP, 0)
        if isBar then
            minimise:SetSize(20, 20)
            return
        end
        minimise:SetSize(TOOL, TOOL)
        local want = math.max(math.ceil(guildName:GetStringWidth() or 0), math.ceil(meta:GetStringWidth() or 0))
        local cap = math.max(NAME_MIN, math.min(NAME_MAX, math.floor((w - 2 * EDGE) * 0.3)))
        local nameW = math.max(NAME_MIN, math.min(want, cap))
        guildName:SetWidth(nameW)
        meta:SetWidth(nameW)
        self.doorsX = 10 + CREST + 8 + nameW + 10
    end

    -- Guarded: it runs on every show and roster update, and reads modules
    -- that may not have started.
    function f:RefreshTitle()
        GuildOS:SafeCall(function()
            local A = UI.Agora
            local online = A:RosterLoading() and DASH or string.format(L["%d online"], A:OnlineCount())
            local level = GuildOS.Achievements and GuildOS.Achievements:Renown()
            local badge = level and GuildOS.Achievements:Insignia()
            -- The insignia at the line's own height (0: the font's), not a 14px icon on an 11px line (#449).
            local renown = level and (DOT .. (badge and ("|T" .. badge .. ":0:0:0:-1|t ") or "")
                .. string.format(L["renown %d"], level)) or ""
            local guild = GetGuildInfo("player") or "Guild OS"
            GuildOS:SetTitleText(guildName, guild)
            GuildOS:SetTitleText(crest.letter, UI.Initial(guild))
            UI:DrawTabard(crest)
            local realm = GetRealmName and GetRealmName() or nil
            meta:SetText(online .. ((realm and realm ~= "") and (DOT .. realm) or "") .. renown)
            local last = A:LastSync()
            sync:SetText(last and string.format(L["Updated: %s"], GuildOS:TimeAgo(last)) or L["not synced yet"])
            local fresh = last and (time() - last) < 3600
            local dc = fresh and C.ok or (last and C.warn) or C.disabled
            dot:SetVertexColor(dc.r, dc.g, dc.b, 1)
            local me = GuildOS.Compat.PlayerName()
            welcome:SetText(string.format(L["Welcome back, %s."], me or "?"))
            -- Winter Veil: snow on the wood and the garland under the bar, while the event's snow falls.
            local winter = UI.Snow and UI.Snow.Mode and UI.Snow:Mode() == "season" or false
            garland:SetShown(winter)
            if f.wood then f.wood:SetWinter(winter) end
            -- The three numbers walk the officer work, so only while they show.
            if self.band == "bar" then summary:SetText(A:BarText()) end
            self:LayoutTitle()
            -- The officers' counts and the name's width move the doors and the pills: laid out again only when
            -- one changed, as this runs on the 10s tick and a door hidden mid-press loses its click (#377).
            local total, by = officerCounts()
            local parts = { tostring(total), tostring(self.doorsX) }
            for k, n in pairs(by) do parts[#parts + 1] = k .. "=" .. n end
            table.sort(parts)
            local key = table.concat(parts, ",")
            if key ~= self.__tabsKey then
                self.__tabsKey = key
                self:LayoutTabs()
            end
            self:LayoutFooter()
        end)
    end

    ------------------------------------------------------------------
    -- The ladder
    ------------------------------------------------------------------

    -- The minimise button, and the way back out of the bar: folded (or in the
    -- bar band) it restores the size the window had, otherwise it folds to the
    -- bar. The saved fold decides, since the band is unknown until the first
    -- layout after /reload.
    function f:ToggleCollapsed()
        local g = store()
        pinTopLeft(self)
        if g.collapsed or self.band == "bar" then
            g.collapsed = nil
            -- Wide enough that the content area clears the bar band.
            self:SetSize(math.max(g.restoreW or DEFAULT_W,
                bandMin("watch") + UI.LADDER_HYSTERESIS + 2 * PAD_NARROW), g.restoreH or DEFAULT_H)
        else
            g.collapsed = true
            g.restoreW, g.restoreH = round(self:GetWidth()), round(self:GetHeight())
            self:SetSize(MIN_W, BAR_H)
        end
        UI:SaveWindowGeometry(self)
        -- Laid out now: a hidden frame is not sure to get OnSizeChanged.
        self:Layout(self:GetWidth())
    end

    -- After the grip lets go. The bar band is one 28px line, so a window
    -- dragged into it folds to that line, and one dragged back out gets the
    -- height it had before.
    function f:Settle()
        local g = store()
        pinTopLeft(self)
        local band = UI:ResolveBand(contentWidth(self:GetWidth()), self.band)
        -- An open window dragged narrow (a client that let the grip past its bounds) stays open, at the
        -- narrowest open width: folding is the minimise button's.
        if band == "bar" and not g.collapsed and self.sizingFrom and not self.sizingFolded then
            self:SetWidth(DRAG_MIN_W)
            if (tonumber(self:GetHeight()) or 0) < 240 then self:SetHeight(240) end
            self.sizingFrom, self.sizingFolded = nil, nil
            UI:SaveWindowGeometry(self)
            self:Layout(self:GetWidth())
            return
        end
        if band == "bar" then
            if not g.collapsed then
                local from = self.sizingFrom
                g.collapsed = true
                g.restoreW = from and round(from[1]) or DEFAULT_W
                g.restoreH = from and round(from[2]) or DEFAULT_H
            end
            self:SetHeight(BAR_H)
        elseif g.collapsed then
            g.collapsed = nil
            self:SetHeight(g.restoreH or DEFAULT_H)
        end
        self.sizingFrom, self.sizingFolded = nil, nil
        UI:SaveWindowGeometry(self)
    end

    function f:Layout(w)
        local band = UI:ResolveBand(contentWidth(w), self.band)
        local changed = band ~= self.band
        self.band = band
        local isBar, isWatch = band == "bar", band == "watch"
        local narrow = w < NARROW
        local titleH = isBar and BAR_H or TITLE_H
        local pad = narrow and PAD_NARROW or PAD

        bar:SetHeight(titleH)
        -- Folded to the bar, the window is the bar: edge to edge, no frame around it.
        local inset = isBar and 0 or EDGE
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", -inset, -inset)
        barLine:SetShown(not isBar)
        minimise.x:SetText(isBar and "+" or DASH)
        self:LayoutTitle(w)

        content:SetShown(not isBar and not self:SearchShowing())
        if isBar then entryRow:Hide(); sideNav:Hide(); searchRow:Hide(); results:Hide() end
        foot:SetShown(not isBar)
        for _, t in pairs(f.wood) do if type(t) == "table" and t.SetShown then t:SetShown(not isBar) end end
        if not isBar and f.wood.SetWinter then f.wood:SetWinter(garland:IsShown()) end
        self.layoutTop, self.layoutPad = EDGE + titleH, pad

        local home = self.tabPanels[HOME]
        if changed and isWatch and self.activeTab ~= HOME and not (home and home.buildFailed) then
            -- The room and entry that were open come back once the window is wide again.
            self.beforeWatch = { room = self.activeRoom, entry = self.activeEntry, tab = self.activeTab }
            self:SetActiveTab(HOME)
        elseif changed and not isWatch and not isBar and self.beforeWatch then
            local back = self.beforeWatch
            self.beforeWatch = nil
            if self.activeTab == HOME then
                if not (back.entry and self:SelectEntry(back.room, back.entry)) then self:SetActiveTab(back.tab) end
            end
        end

        self:LayoutTabs(w)
        self:LayoutFooter(w)
        if changed then self:RefreshTitle() end
    end

    ------------------------------------------------------------------
    -- Show, hide, events
    ------------------------------------------------------------------
    f:SetScript("OnShow", function(self)
        self:UpdateTabVisibility()
        self:RefreshTitle()
        if not self.ticker then
            self.ticker = C_Timer.NewTicker(10, function() self:InvalidateOfficerCounts(); self:RefreshTitle() end)
        end
    end)
    f:SetScript("OnHide", function(self)
        -- Opened again, the window shows its screen, not an old search.
        self:CloseSearch()
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
    end)
    -- After OnShow is set: MakeResponsive hooks it.
    UI:MakeResponsive(f, function(_, w) f:Layout(w) end)

    -- One literal call per event: tools/probe.lua reads them to keep the
    -- probe's event list honest.
    GuildOS.Compat.RegisterEvent(f, "GROUP_ROSTER_UPDATE")
    GuildOS.Compat.RegisterEvent(f, "RAID_ROSTER_UPDATE")
    GuildOS.Compat.RegisterEvent(f, "PARTY_LOOT_METHOD_CHANGED")
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    -- The crest's tabard: the guild changed, or its data arrived (#449).
    GuildOS.Compat.RegisterEvent(f, "PLAYER_GUILD_UPDATE")
    -- The title counts who is online over the whole roster: at most once every ROSTER_GAP (issue #324).
    local function shownTitle()
        if f:IsShown() then f:InvalidateOfficerCounts(); f:RefreshTitle() end
    end
    f:SetScript("OnEvent", function(self, event)
        if event == "GUILD_ROSTER_UPDATE" then
            GuildOS:Coalesce("windowTitle", GuildOS.ROSTER_GAP, shownTitle)
        elseif event == "PLAYER_GUILD_UPDATE" then
            if self:IsShown() then GuildOS:SafeCall(UI.DrawTabard, UI, crest) end
        else
            self:UpdateTabVisibility()
        end
    end)

    table.insert(UISpecialFrames, NAME)   -- ESC closes it

    -- Where it was left: the saved room's entry, else the saved feature (before the rooms), else Home.
    local g = store()
    if not (g.room and f:OpenRoom(g.room)) and not (g.tab and f:SetActiveTab(g.tab)) then
        f:UpdateTabVisibility()
    end
    if UI.Snow then UI.Snow:Attach(f) end   -- Winter Veil's snow (guildos-web#662)
    return f
end

----------------------------------------------------------------------
-- The ways in
----------------------------------------------------------------------

-- Whether the window can open feature `id`: true before it is built (every tab feature will get a panel then),
-- and afterwards only for the features it built a panel for (UI/Rooms.lua asks, #445).
function UI:HasPanel(id)
    local f = GuildOS.RosterFrame
    return not f or (f.tabPanels and f.tabPanels[id] ~= nil) or false
end

-- The window, created on first use. Nil until the saved data is loaded.
function UI:GetMainWindow()
    if not GuildOS.db then return nil end
    if not GuildOS.RosterFrame then GuildOS.RosterFrame = createWindow() end
    return GuildOS.RosterFrame
end

-- Show the window on tab `id`, then on sub-tab `sub`, with `filter` applied
-- where that sub-tab takes one (Guild › Calendar takes a day). The one opener
-- every entry point uses. Returns true when the tab opened.
function UI:OpenWindow(id, sub, filter)
    local def = self:GetFeature(id)
    -- A feature that lives in another tab's sub-tab (issue #346: DKP, the wishlists) opens it.
    if def and not def.tab and def.opens then
        if self:IsFeatureAbsent(def) then
            GuildOS:Print(L["Not available on this client."])
            return false
        end
        -- Said as a tab says it (issue #367: Trials, the Journal and Achievements became sub-tabs).
        if not GuildOS:IsFeatureEnabled(id) then
            GuildOS:Print(string.format(L["%s is disabled in Settings."], def.label))
            return false
        end
        if GuildOS:FeatureStartFailed(id) then
            GuildOS:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
            return false
        end
        if def.officerOnly and not GuildOS:IsOfficer() then
            GuildOS:Print(string.format(L["%s is officer-only."], def.label))
            return false
        end
        return self:OpenWindow(def.opens[1], sub or def.opens[2], filter)
    end
    if not (def and def.tab) then return false end
    -- Checked here with their own messages, before the tab gate that covers
    -- all four: an absent feature, a disabled one, a failed one and a rank
    -- refusal read differently to the player.
    if self:IsFeatureAbsent(def) then
        GuildOS:Print(L["Not available on this client."])
        return false
    end
    if not GuildOS:IsFeatureEnabled(id) then
        GuildOS:Print(string.format(L["%s is disabled in Settings."], def.label))
        return false
    end
    if GuildOS:FeatureStartFailed(id) then
        GuildOS:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
        return false
    end
    if not self:IsFeatureAllowed(def) then
        GuildOS:Print(string.format(L["%s is officer-only."], def.label))
        return false
    end
    local f = self:GetMainWindow()
    if not f then return false end
    f:Show()
    -- A tab asked for by name has to be seen, so the bar opens back up.
    if store().collapsed or f.band == "bar" then f:ToggleCollapsed() end
    -- Through the room that holds it (#445): its entry, on the sub-tab asked for.
    local room, entry = self:RoomOf(id, sub)
    if room then return f:SelectEntry(room.id, entry, true, sub, filter) end
    if not f:SetActiveTab(id, true) then return false end
    local panel = f.tabPanels[id]
    if sub and panel.SelectSub then panel.SelectSub(sub, filter) end
    return true
end

-- The window with its search strip open, `text` in it (/gos find, /gos search; Search:Show).
function UI:OpenSearch(text)
    local f = self:GetMainWindow()
    if not f then return false end
    f:Show()
    if store().collapsed or f.band == "bar" then f:ToggleCollapsed() end
    f:OpenSearch(text)
    return true
end

function UI:ToggleMain()
    local f = self:GetMainWindow()
    if f then f:SetShown(not f:IsShown()) end
end

function UI:ApplyScale()
    local f = GuildOS.RosterFrame
    if f then f:SetScale(GuildOS:GetSetting("uiScale") or 1) end
    self:RefreshHairlines()
end

-- A feature turned off in Settings loses its tab at once.
function UI:OnFeatureToggled()
    local f = GuildOS.RosterFrame
    if f then f:UpdateTabVisibility() end
end
