----------------------------------------------------------------------
-- Guild OS - Live Guild Map (UI layer)
--
-- Draws guildmates on Blizzard's world map (our OWN pin textures parented
-- to the map canvas), a draggable roster-style list overlay with a
-- "share my live position" checkbox, and an ambient minimap indicator that
-- counts guildmates in the player's current zone.
--
-- TAINT SAFETY: we NEVER overwrite a Blizzard global function. Our pins are
-- our own frames parented to the world map canvas; we react to the map
-- opening / the displayed map changing ONLY through hooksecurefunc and
-- HookScript, and we never call a protected function from an insecure
-- handler. Every world map / C_Map read goes through BRutus.Compat (Rule 4).
-- The UI holds no domain logic (Rule 10): it renders GuildMap:GetPeers and
-- flips the shareExact pref through GuildMap methods.
--
-- v1 SCOPE: pins are drawn only for peers whose mapID equals the map the
-- user is currently viewing. Peers on other maps appear in the LIST with
-- click-to-navigate (cross-map coordinate translation is unreliable in BCC),
-- never as pins. Zone-only peers (no exact x/y) are placed at the map centre
-- and dimmed.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT  = (BRutus.Fonts and BRutus.Fonts.normal) or "Fonts\\FRIZQT__.TTF"

local PIN_SIZE          = 12
local LIST_ROW_H        = 20
local POS_THROTTLE      = 0.1   -- seconds between pin reposition passes (zoom/pan)
local DOT_SIZE          = 8
local DOT_GAP           = 4
local MINIMAP_DOTS_MAX  = 5

local function ModGM() return BRutus.GuildMap end

-- Localized zone name for a mapID, with a safe fallback.
local function zoneName(mapID)
    return (mapID and BRutus.Compat.GetMapName(mapID)) or L["Unknown zone"]
end

----------------------------------------------------------------------
-- Shared state + forward declarations
----------------------------------------------------------------------
local cachedPeers = {}          -- last GuildMap:GetPeers() snapshot
local pins        = {}          -- world-map pin frame pool
local pinContainer              -- our frame covering the map canvas
local activePins  = 0
local hooked      = false
local listFrame, listContent    -- the draggable list overlay
local listRows    = {}
local dotsFrame                 -- minimap "guildmates in your zone" indicator

local PositionPins, LayoutPins, RefreshData, RefreshList, RefreshMinimapDots

----------------------------------------------------------------------
-- World map pins
----------------------------------------------------------------------

-- Acquire (or reuse) pin frame i.
local function AcquirePin(i)
    local pin = pins[i]
    if pin then return pin end
    pin = CreateFrame("Frame", nil, pinContainer)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:EnableMouse(true)

    local border = pin:CreateTexture(nil, "BACKGROUND")
    border:SetTexture(WHITE)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetVertexColor(0, 0, 0, 0.85)

    local dot = pin:CreateTexture(nil, "ARTWORK")
    dot:SetTexture(WHITE)
    dot:SetAllPoints()
    pin.dot = dot

    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.pinName or "?", self.cr or 1, self.cg or 1, self.cb or 1)
        if self.zoneText then GameTooltip:AddLine(self.zoneText, C.silver.r, C.silver.g, C.silver.b) end
        if self.subText then GameTooltip:AddLine(self.subText, C.textDim.r, C.textDim.g, C.textDim.b) end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pins[i] = pin
    return pin
end

-- Reposition the currently active pins to the current canvas size. Cheap:
-- only reads the container size and moves our own frames (no roster scan, no
-- protected call), so it is safe to run on a throttled OnUpdate to follow
-- zoom/pan. Blizzard's own pins use the same normalized -> canvas formula.
PositionPins = function()
    if not pinContainer then return end
    local w, h = pinContainer:GetWidth(), pinContainer:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then return end
    for i = 1, activePins do
        local pin = pins[i]
        if pin and pin.nx then
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", pinContainer, "TOPLEFT", pin.nx * w, -pin.ny * h)
        end
    end
end

-- Decide which cached peers belong on the displayed map, bind them to pins,
-- then position. Called on data refresh and whenever the displayed map
-- changes (OnMapChanged hook).
LayoutPins = function()
    if not pinContainer then return end
    local shownMap = BRutus.Compat.GetShownMapID()
    local used = 0
    if shownMap then
        for _, p in ipairs(cachedPeers) do
            if p.mapID == shownMap then
                used = used + 1
                local pin = AcquirePin(used)
                local cr, cg, cb = BRutus:GetClassColor(p.class)
                pin.dot:SetVertexColor(cr, cg, cb, 1)
                pin.cr, pin.cg, pin.cb = cr, cg, cb
                pin.pinName  = p.name
                pin.zoneText = zoneName(p.mapID)
                if p.exact and p.x and p.y then
                    pin.nx, pin.ny = p.x, p.y
                    pin.subText = p.level and (L["Lv "] .. p.level) or nil
                    pin:SetAlpha(1)
                else
                    pin.nx, pin.ny = 0.5, 0.5   -- zone-only -> map centre
                    pin.subText = L["Somewhere in this zone"]
                    pin:SetAlpha(0.65)
                end
                pin:Show()
            end
        end
    end
    for i = used + 1, #pins do pins[i]:Hide() end
    activePins = used
    PositionPins()
end

-- React to the world map opening / changing maps with taint-safe hooks only.
local function InstallMapHooks()
    if hooked then return end
    local wmf = BRutus.Compat.GetWorldMapFrame()
    if not wmf then return end
    hooked = true
    -- Displayed map changed -> re-pick which peers are pinned. hooksecurefunc
    -- POST-hooks the Blizzard method without replacing it (no taint).
    if wmf.OnMapChanged then
        hooksecurefunc(wmf, "OnMapChanged", function() BRutus:SafeCall(LayoutPins) end)
    end
    -- Map opened -> repaint from the latest data.
    wmf:HookScript("OnShow", function() BRutus:SafeCall(RefreshData) end)
end

-- Lazily build our pin container over the map canvas. Returns nil until the
-- world map (and its canvas) exists.
local function EnsurePinLayer()
    if pinContainer then return pinContainer end
    local canvas = BRutus.Compat.GetWorldMapCanvas()
    if not canvas then return nil end
    pinContainer = CreateFrame("Frame", nil, canvas)
    pinContainer:SetAllPoints(canvas)   -- track the canvas rect through zoom/pan
    pinContainer:SetFrameStrata("HIGH")
    pinContainer._elapsed = 0
    pinContainer:SetScript("OnUpdate", function(self, dt)
        self._elapsed = self._elapsed + dt
        if self._elapsed < POS_THROTTLE then return end
        self._elapsed = 0
        PositionPins()
    end)
    InstallMapHooks()
    return pinContainer
end

----------------------------------------------------------------------
-- List overlay
----------------------------------------------------------------------

local function GetListRow(i)
    local row = listRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, listContent, "BackdropTemplate")
    row:SetHeight(LIST_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * LIST_ROW_H)
    row:SetBackdrop({ bgFile = WHITE })
    row:SetBackdropColor(0, 0, 0, 0)

    local dot = row:CreateTexture(nil, "ARTWORK")
    dot:SetTexture(WHITE)
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", 4, 0)
    row.dot = dot

    local nameFS = UI:CreateText(row, "", 11)
    nameFS:SetPoint("LEFT", 16, 0)
    nameFS:SetJustifyH("LEFT")
    row.nameFS = nameFS

    local zoneFS = UI:CreateText(row, "", 9, C.silver.r, C.silver.g, C.silver.b)
    zoneFS:SetPoint("LEFT", 92, 0)
    zoneFS:SetPoint("RIGHT", -6, 0)
    zoneFS:SetJustifyH("RIGHT")
    zoneFS:SetWordWrap(false)
    row.zoneFS = zoneFS

    row:SetScript("OnEnter", function(self) self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 0.5) end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)

    listRows[i] = row
    return row
end

local function BuildListFrame()
    local f = CreateFrame("Frame", "GuildOSGuildMapList", UIParent, "BackdropTemplate")
    f:SetSize(240, 360)
    f:SetPoint("TOPLEFT", 40, -200)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the world map window
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSGuildMapList")

    local title = UI:CreateTitle(f, L["Guild Map"], 13)
    title:SetPoint("TOPLEFT", 12, -10)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    local chk = UI:CreateCheckbox(f, L["Share my live position"], 16)
    chk:SetPoint("TOPLEFT", 10, -34)
    chk.checkbox.onChanged = function(_, checked)
        ModGM():SetShareExact(checked and true or false)
    end
    f.shareChk = chk

    local hint = UI:CreateText(f, L["Click a name to jump to their zone."], 9,
        C.accentDim.r, C.accentDim.g, C.accentDim.b)
    hint:SetPoint("TOPLEFT", 12, -56)

    local status = UI:CreateText(f, "", 9, C.silver.r, C.silver.g, C.silver.b)
    status:SetPoint("TOPLEFT", 12, -70)
    f.statusFS = status

    local scroll = CreateFrame("ScrollFrame", "GuildOSGuildMapListScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -88)
    scroll:SetPoint("BOTTOMRIGHT", -10, 10)
    UI:SkinScrollBar(scroll, "GuildOSGuildMapListScroll")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    f.scroll = scroll
    listContent = content

    -- Frames are shown on creation; hide it so ToggleGuildMap's first call
    -- opens it instead of seeing IsShown()==true and immediately hiding it.
    f:Hide()
    return f
end

RefreshList = function()
    if not listFrame then return end
    listFrame.shareChk.checkbox:SetChecked(ModGM():IsShareExact())
    listContent:SetWidth(listFrame.scroll:GetWidth())

    local shownMap = BRutus.Compat.GetShownMapID()
    for i, p in ipairs(cachedPeers) do
        local row = GetListRow(i)
        local cr, cg, cb = BRutus:GetClassColor(p.class)
        row.dot:SetVertexColor(cr, cg, cb, 1)
        row.nameFS:SetText(p.name)
        row.nameFS:SetTextColor(cr, cg, cb)
        row.zoneFS:SetText(zoneName(p.mapID))
        if shownMap and p.mapID == shownMap then
            row.zoneFS:SetTextColor(C.gold.r, C.gold.g, C.gold.b)   -- on the map you're viewing
        else
            row.zoneFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        end
        local mid = p.mapID
        row:SetScript("OnClick", function() BRutus:GuildMapFocus(mid) end)
        row:Show()
    end
    for i = #cachedPeers + 1, #listRows do listRows[i]:Hide() end
    listContent:SetHeight(math.max(1, #cachedPeers * LIST_ROW_H))
    listFrame.statusFS:SetText(string.format(L["%d guildmate(s) on the map"], #cachedPeers))
end

----------------------------------------------------------------------
-- Minimap indicator: class-coloured dots for guildmates in your zone.
-- BCC has no reliable insecure math to place them geographically (minimap
-- yards-per-pixel + rotation are not exposed), so this is an honest count
-- indicator: one dot per same-zone guildmate (capped, with a "+N" overflow)
-- and a tooltip listing their names.
----------------------------------------------------------------------
local function BuildDotsFrame()
    local f = CreateFrame("Frame", nil, Minimap)
    f:SetSize(MINIMAP_DOTS_MAX * (DOT_SIZE + DOT_GAP) + 22, DOT_SIZE + 6)
    f:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 6)
    f.dots = {}
    for i = 1, MINIMAP_DOTS_MAX do
        local d = CreateFrame("Frame", nil, f)
        d:SetSize(DOT_SIZE, DOT_SIZE)
        d:SetPoint("LEFT", (i - 1) * (DOT_SIZE + DOT_GAP), 0)
        local border = d:CreateTexture(nil, "BACKGROUND")
        border:SetTexture(WHITE)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetVertexColor(0, 0, 0, 0.85)
        local tex = d:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(WHITE)
        tex:SetAllPoints()
        d.tex = tex
        d:Hide()
        f.dots[i] = d
    end
    local more = f:CreateFontString(nil, "OVERLAY")
    more:SetFont(FONT, 9, "OUTLINE")
    more:SetPoint("LEFT", f.dots[MINIMAP_DOTS_MAX], "RIGHT", 3, 0)
    more:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    f.more = more

    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.here or #self.here == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Guildmates in your zone"], C.gold.r, C.gold.g, C.gold.b)
        for _, p in ipairs(self.here) do
            local cr, cg, cb = BRutus:GetClassColor(p.class)
            GameTooltip:AddLine(p.name, cr, cg, cb)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

RefreshMinimapDots = function()
    if not dotsFrame then return end
    local myMap = tonumber(BRutus.Compat.GetBestMapForUnit("player"))
    local here = {}
    if myMap and myMap > 0 then
        for _, p in ipairs(cachedPeers) do
            if p.mapID == myMap then here[#here + 1] = p end
        end
    end
    local n = #here
    local shown = math.min(n, MINIMAP_DOTS_MAX)
    for i = 1, shown do
        local cr, cg, cb = BRutus:GetClassColor(here[i].class)
        dotsFrame.dots[i].tex:SetVertexColor(cr, cg, cb, 1)
        dotsFrame.dots[i]:Show()
    end
    for i = shown + 1, MINIMAP_DOTS_MAX do dotsFrame.dots[i]:Hide() end
    if n > MINIMAP_DOTS_MAX then
        dotsFrame.more:SetText("+" .. (n - MINIMAP_DOTS_MAX))
        dotsFrame.more:Show()
    else
        dotsFrame.more:Hide()
    end
    dotsFrame.here = here
    dotsFrame:SetShown(n > 0)
end

----------------------------------------------------------------------
-- Refresh orchestration
----------------------------------------------------------------------

-- Recompute the peer snapshot (the only place that scans the roster) and
-- repaint every surface that is currently live.
RefreshData = function()
    cachedPeers = (BRutus.GuildMap and BRutus.GuildMap:GetPeers()) or {}
    if listFrame and listFrame:IsShown() then RefreshList() end
    LayoutPins()
    RefreshMinimapDots()
end

----------------------------------------------------------------------
-- Public entry points
----------------------------------------------------------------------

-- Open the world map on a peer's zone (used by list-row clicks). OnMapChanged
-- will relayout the pins; LayoutPins() is a belt-and-suspenders for clients
-- whose map lacks that method.
function BRutus:GuildMapFocus(mapID)
    BRutus.Compat.OpenWorldMap()
    EnsurePinLayer()
    BRutus.Compat.SetShownMapID(mapID)
    BRutus:SafeCall(LayoutPins)
end

-- /gos map and the minimap menu entry. Toggles the list overlay; opening it
-- also opens the world map and builds the pin layer.
function BRutus:ToggleGuildMap()
    local f = listFrame or BuildListFrame()
    listFrame = f
    if f:IsShown() then
        f:Hide()
        return
    end
    BRutus.Compat.OpenWorldMap()
    EnsurePinLayer()
    f:Show(); f:Raise()
    RefreshData()
    -- The map addon may have loaded on demand this frame; retry the layer +
    -- repaint once the canvas certainly exists.
    BRutus.Compat.After(0, function()
        EnsurePinLayer()
        RefreshData()
    end)
end

-- One-time wiring: bind the data-layer refresh hook, build the minimap
-- indicator, and watch our own zone changes. Called from CreateMinimapButton
-- so no Core file needs editing and Minimap is guaranteed to exist.
function BRutus:SetupGuildMapPresence()
    if BRutus._guildMapPresence then return end
    BRutus._guildMapPresence = true

    if Minimap then dotsFrame = BuildDotsFrame() end

    -- Incoming positions (GuildMap:HandlePosition) repaint everything live.
    if BRutus.GuildMap then
        BRutus.GuildMap.uiRefresh = function() BRutus:SafeCall(RefreshData) end
    end

    -- Our own zone change alters who counts as "in your zone".
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() BRutus:SafeCall(RefreshData) end)
    BRutus._guildMapPresenceFrame = ev

    RefreshData()
end
