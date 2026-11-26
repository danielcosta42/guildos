----------------------------------------------------------------------
-- Guild OS - Live Guild Map (UI layer; issue #449, specs/salao/mapa.md)
--
-- Guildmates drawn where they are, as they move:
--   * On the world map: a round class avatar with the gold ring (UI:CreateAvatar) per guildmate on the shown
--     map, a zone's or a continent's (points converted between maps by GuildMap:_PlaceOn); it glides between
--     updates, fades after GuildMap.STALE_FADE and goes after STALE_GONE, and grows a little with the zoom.
--     Hover: name, level, class, zone, how long ago. A small list on the map ("Guildmates on this map"); a
--     click flashes the pin, or opens the guildmate's map.
--   * On the minimap: a dot per guildmate in the zone, at their bearing and distance (held at the edge when
--     out of range), turning with a rotating minimap; none in an instance.
-- While the world map is open this client watches the shown map (GuildMap:SetWatch), and that is what makes
-- guildmates send.
--
-- TAINT SAFETY: no Blizzard function is replaced. Our own frames sit on the map's canvas and on the minimap;
-- the map is followed with hooksecurefunc and HookScript only. Every map read goes through GuildOS.Compat.
-- The UI holds no protocol: it draws GuildMap:GetPeers() and tells GuildMap what it shows.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L
local SP = GuildOS.Spacing
local Compat = GuildOS.Compat

local PIN_SIZE      = 20     -- a pin at the map's widest; up to PIN_ZOOM times that zoomed in
local PIN_ZOOM      = 1.5
local DOT_SIZE      = 12
local FRAME_GAP     = 1 / 30 -- seconds between two pin moves (the glide)
local LIST_GAP      = 0.5    -- seconds between two rebuilds of who is drawn
local LIST_W        = 240
local LIST_ROWS     = 10
local ROW_H         = SP.HIT
local FLASH_TIME    = 3

local function GM() return GuildOS.GuildMap end

local function className(class)
    return (class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or ""
end

-- The tooltip of a guildmate: name, level and class, zone, and how fresh it is.
local function ShowPeerTooltip(owner, p, extra)
    if not p then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local cc = GuildOS.ClassColors[p.class or ""] or C.text
    GameTooltip:AddLine(p.name or "?", cc.r, cc.g, cc.b)
    if p.level then
        GameTooltip:AddLine(string.format(L["Level %d %s"], p.level, className(p.class)), C.text.r, C.text.g, C.text.b)
    end
    if p.inInstance then
        GameTooltip:AddLine(string.format(L["In an instance: %s"], p.inst or L["Unknown zone"]), C.gold2.r, C.gold2.g, C.gold2.b)
    else
        GameTooltip:AddLine(p.zone or L["Unknown zone"], C.textSoft.r, C.textSoft.g, C.textSoft.b)
    end
    if p.combat then GameTooltip:AddLine(L["In combat"], C.danger.r, C.danger.g, C.danger.b) end
    if extra then GameTooltip:AddLine(extra, C.textSoft.r, C.textSoft.g, C.textSoft.b) end
    if p.onOpenMap then
        GameTooltip:AddLine(L["Drawn by OpenMap"], C.textSoft.r, C.textSoft.g, C.textSoft.b)
    elseif p.via == "openmap" then
        GameTooltip:AddLine(L["Shared through OpenMap"], C.textSoft.r, C.textSoft.g, C.textSoft.b)
    end
    if p.isGroup then
        GameTooltip:AddLine(L["In your group"], C.textSoft.r, C.textSoft.g, C.textSoft.b)
    else
        GameTooltip:AddLine(string.format(L["Updated %d s ago"], math.floor((p.age or 0) + 0.5)),
            C.textSoft.r, C.textSoft.g, C.textSoft.b)
    end
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local peers = {}           -- the last GuildMap:GetPeers()
local byKey = {}           -- key -> its row in peers
local pinOf = {}           -- key -> its pin
local layer                -- our frame over the world map's canvas
local pins, nPins = {}, 0
local list                 -- the list on the world map
local dots, dotsDriver = {}, nil
local hooked = false
local dirty = true
local flashKey, flashUntil

----------------------------------------------------------------------
-- World map pins
----------------------------------------------------------------------
local function AcquirePin(i)
    local pin = pins[i]
    if pin then return pin end
    pin = UI:CreateAvatar(layer, PIN_SIZE, false)
    pin:EnableMouse(true)
    local halo = GuildOS.Style:Texture(pin, "halo", "BACKGROUND", 0)
    halo:SetPoint("CENTER")
    halo:SetSize(PIN_SIZE * 2.2, PIN_SIZE * 2.2)
    halo:SetVertexColor(C.gold2.r, C.gold2.g, C.gold2.b, 1)
    halo:Hide()
    pin.flash = halo
    pin:SetScript("OnEnter", function(self) ShowPeerTooltip(self, byKey[self.key]) end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pins[i] = pin
    return pin
end

-- Moves every drawn pin to where its guildmate is now (the glide), at the zoom's size. Cheap: affine maths on
-- cached transforms, our own frames only.
local function MovePins()
    if not layer or nPins == 0 then return end
    local w, h = layer:GetWidth(), layer:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then return end
    local shown = Compat.GetShownMapID()
    local canvasScale, pct = Compat.WorldMapZoom()
    local scale = (1 + (PIN_ZOOM - 1) * pct) / canvasScale
    local t = GetTime()
    local G = GM()
    for i = 1, nPins do pins[i].seen = false end
    G:ForEachLive(t, function(p, x, y, alpha)
        local pin = pinOf[p.key]
        if not pin then return end
        local sx, sy
        if x then sx, sy = G:_PlaceOn(shown, p.mapID, x, y) end
        if not sx then return end
        pin.seen = true
        pin:SetScale(scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", layer, "TOPLEFT", sx * w / scale, -sy * h / scale)
        pin:SetAlpha(alpha)
        local flashing = flashKey == p.key and flashUntil and t < flashUntil
        pin.flash:SetShown(flashing and true or false)
        if flashing then pin.flash:SetAlpha(0.5 + 0.5 * math.abs(math.sin(t * 6))) end
        pin:Show()
    end)
    for i = 1, nPins do if not pins[i].seen then pins[i]:Hide() end end
end

-- Who is drawn on the shown map: everybody whose point lands on it, but those OpenMap draws itself (listed only).
local function LayoutPins()
    if not layer then return end
    local shown = Compat.GetShownMapID()
    peers = GM():GetPeers()
    byKey, pinOf = {}, {}
    local used = 0
    for _, p in ipairs(peers) do
        byKey[p.key] = p
        if shown and p.x and not p.onOpenMap and GM():_PlaceOn(shown, p.mapID, p.x, p.y) then
            used = used + 1
            local pin = AcquirePin(used)
            pin.key = p.key
            pinOf[p.key] = pin
            pin:SetMember(p.name, p.class, false)
        end
    end
    for i = used + 1, #pins do pins[i]:Hide(); pins[i].key = nil end
    nPins = used
    MovePins()
end

----------------------------------------------------------------------
-- The list on the world map
----------------------------------------------------------------------
local RefreshList

local function ListRow(i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", SP.PAD - 4, -(list.top + (i - 1) * ROW_H))
    row:SetPoint("TOPRIGHT", -(SP.PAD - 4), -(list.top + (i - 1) * ROW_H))
    UI:CreateRowSelection(row)
    row.av = UI:CreateAvatar(row, 18, false)
    row.av:SetPoint("LEFT", 0, 0)
    row.av:EnableMouse(false)
    row.name = UI:CreateText(row, "", SP.BODY)
    row.name:SetPoint("LEFT", row.av, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.meta = UI:CreateText(row, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    row.meta:SetPoint("RIGHT", 0, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetWordWrap(false)
    row.name:SetPoint("RIGHT", row.meta, "LEFT", -6, 0)
    row:SetScript("OnEnter", function(self) ShowPeerTooltip(self, byKey[self.key]) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local p = byKey[self.key]
        if not p then return end
        local shown = Compat.GetShownMapID()
        if not (shown and p.x and GM():_PlaceOn(shown, p.mapID, p.x, p.y)) and p.mapID and p.mapID > 0 then
            Compat.SetShownMapID(p.mapID)
        end
        flashKey, flashUntil = p.key, GetTime() + FLASH_TIME
        dirty = true
    end)
    list.rows[i] = row
    return row
end

local function BuildList()
    local wmf = Compat.GetWorldMapFrame()
    local host = wmf and (wmf.ScrollContainer or wmf)
    if not host then return nil end
    local f = UI:CreateCard(host, L["Guild Map"], { dark = true })
    f:SetWidth(LIST_W)
    f:SetPoint("TOPRIGHT", host, "TOPRIGHT", -SP.MARGIN, -SP.MARGIN)
    f:SetFrameLevel((host:GetFrameLevel() or 1) + 600)
    f:EnableMouse(true)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -SP.PAD + 6, -SP.PAD + 6)
    close:SetScript("OnClick", function() GM():SetListShown(false); f:Hide() end)
    f.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
    f.head = UI:CreateText(f, "", SP.META, C.gold2.r, C.gold2.g, C.gold2.b)
    f.head:SetPoint("TOPLEFT", SP.PAD, -SP.TOP)
    f.head:SetPoint("RIGHT", f, "RIGHT", -SP.PAD, 0)
    f.head:SetJustifyH("LEFT")
    f.top = SP.TOP + 18
    f.rows = {}
    f.foot = UI:CreateText(f, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.foot:SetPoint("LEFT", f, "LEFT", SP.PAD, 0)
    f.foot:SetPoint("RIGHT", f, "RIGHT", -SP.PAD, 0)
    f.foot:SetJustifyH("LEFT")
    f.foot:SetWordWrap(true)
    f:Hide()
    return f
end

RefreshList = function()
    if not list or not list:IsShown() then return end
    local shown = Compat.GetShownMapID()
    local here, elsewhere = {}, 0
    for _, p in ipairs(peers) do
        if shown and p.x and GM():_PlaceOn(shown, p.mapID, p.x, p.y) then here[#here + 1] = p
        else elsewhere = elsewhere + 1 end
    end
    list.head:SetText(string.format(L["Guildmates on this map (%d)"], #here))
    local n = math.min(#here, LIST_ROWS)
    for i = 1, n do
        local p, row = here[i], ListRow(i)
        row.key = p.key
        row.av:SetMember(p.name, p.class, p.alpha < 1)
        row.name:SetText(p.name or "?")
        row.meta:SetText(p.onOpenMap and ((p.zone and p.zone .. " · " or "") .. L["on OpenMap"]) or p.zone or "")
        row:SetAlpha(math.max(0.5, p.alpha))
        row:Show()
    end
    for i = n + 1, #list.rows do list.rows[i]:Hide() end
    -- Under the rows: who is elsewhere, why this client may not draw or send, and who can show at all.
    local notes = {}
    if #here == 0 then notes[#notes + 1] = L["No guildmate on this map."] end
    if elsewhere > 0 then
        local names = {}
        for _, p in ipairs(peers) do
            if not (shown and p.x and GM():_PlaceOn(shown, p.mapID, p.x, p.y)) and #names < 6 then
                local where = p.inInstance and string.format(L["In an instance: %s"], p.inst or "?") or p.zone or "?"
                names[#names + 1] = (p.name or "?") .. " (" .. where .. ")"
            end
        end
        notes[#notes + 1] = string.format(L["Elsewhere (%d)"], elsewhere) .. ": " .. table.concat(names, ", ")
    end
    -- Online by the roster in the shown zone, with no place known here (OpenMap's zone badge, as a line).
    local rosterOnly = GM():RosterOnlyHere(shown, byKey)
    if #rosterOnly > 0 then
        local names = {}
        for i = 1, math.min(6, #rosterOnly) do names[i] = rosterOnly[i] end
        notes[#notes + 1] = string.format(L["In this zone by the roster, no position (%d)"], #rosterOnly) .. ": "
            .. table.concat(names, ", ") .. (#rosterOnly > 6 and ", ..." or "")
    end
    if not Compat.MapAbilities().position then
        notes[#notes + 1] = L["This client's map gives no positions: guildmates are listed, not drawn."]
    end
    if not GM():IsSharing() then notes[#notes + 1] = L["You are not sharing your position (Settings > Privacy)."] end
    notes[#notes + 1] = L["Only guildmates who share their position (with Guild OS, or OpenMap's sharing), and your group, show here."]
    list.foot:SetText(table.concat(notes, "\n"))
    local rowsH = n * ROW_H
    list.foot:ClearAllPoints()
    list.foot:SetPoint("TOPLEFT", list, "TOPLEFT", SP.PAD, -(list.top + rowsH + 6))
    list.foot:SetPoint("RIGHT", list, "RIGHT", -SP.PAD, 0)
    list:SetHeight(list.top + rowsH + 6 + math.ceil(list.foot:GetStringHeight() or 0) + SP.PAD)
end

----------------------------------------------------------------------
-- The world map: layer, hooks, watch
----------------------------------------------------------------------
local function WatchShownMap()
    local wmf = Compat.GetWorldMapFrame()
    if wmf and wmf:IsShown() then
        GM():SetWatch("worldmap", Compat.GetShownMapID())
    else
        GM():SetWatch("worldmap", nil)
    end
end

local function OnMapChanged()
    dirty = true
    GM():RefreshOpenMap()   -- OpenMap's settings, read again as the map opens or moves (cheap: a table read)
    WatchShownMap()
end

local function InstallMapHooks()
    if hooked then return end
    local wmf = Compat.GetWorldMapFrame()
    if not wmf then return end
    hooked = true
    if wmf.OnMapChanged then
        hooksecurefunc(wmf, "OnMapChanged", function() GuildOS:SafeCall(OnMapChanged) end)
    end
    wmf:HookScript("OnShow", function()
        if list and GM():IsListShown() then list:Show() end
        GuildOS:SafeCall(OnMapChanged)
    end)
    wmf:HookScript("OnHide", function()
        GM():SetWatch("worldmap", nil)
        if list then list:Hide() end
    end)
end

local function EnsureLayer()
    if layer then return layer end
    local canvas = Compat.GetWorldMapCanvas()
    if not canvas then return nil end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:SetFrameLevel((canvas:GetFrameLevel() or 1) + 50)
    local acc, accList = 0, 0
    layer:SetScript("OnUpdate", function(_, dt)
        acc, accList = acc + dt, accList + dt
        if dirty or accList >= LIST_GAP then
            accList, dirty = 0, false
            GuildOS:SafeCall(LayoutPins)
            GuildOS:SafeCall(RefreshList)
        elseif acc >= FRAME_GAP then
            acc = 0
            GuildOS:SafeCall(MovePins)
        end
    end)
    list = list or BuildList()
    InstallMapHooks()
    return layer
end

----------------------------------------------------------------------
-- Minimap dots
----------------------------------------------------------------------
local function AcquireDot(i)
    local d = dots[i]
    if d then return d end
    d = CreateFrame("Frame", nil, Minimap)
    d:SetSize(DOT_SIZE, DOT_SIZE)
    d:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 6)
    d.disc = GuildOS.Style:Texture(d, "disc", "ARTWORK", 0)
    d.disc:SetAllPoints()
    d.ring = GuildOS.Style:Texture(d, "ring", "ARTWORK", 1)
    d.ring:SetAllPoints()
    d.ring:SetVertexColor(C.gold2.r, C.gold2.g, C.gold2.b, 1)
    d:EnableMouse(true)
    d:SetScript("OnEnter", function(self)
        local p
        for _, row in ipairs(GM():GetPeers()) do if row.key == self.key then p = row end end
        ShowPeerTooltip(self, p, self.yards and string.format(L["%d yd"], math.floor(self.yards + 0.5)))
    end)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dots[i] = d
    return d
end

-- Every guildmate on the player's map, at their bearing and distance.
local function RefreshDots()
    local used = 0
    local G = GM()
    local show = G:IsMinimapDots() and not Compat.InstanceState()
    local myMap = show and Compat.GetBestMapForUnit("player")
    local mx, my
    if myMap then mx, my = Compat.GetPlayerMapPosition(myMap, "player") end
    local yw, yh
    if mx then yw, yh = G:_MapYards(myMap, Compat) end
    local zoom, indoors, rotate = Compat.MinimapView()
    if yw and zoom then
        local rYd = G:_MinimapRadius(zoom, indoors)
        local rPx = (Minimap:GetWidth() or 140) / 2 - DOT_SIZE / 2
        local facing = rotate and Compat.PlayerFacing() or nil
        local t = GetTime()
        G:ForEachLive(t, function(p, x, y, alpha)
            local px, py
            if x then px, py = G:_PlaceOn(myMap, p.mapID, x, y) end
            if not px then return end
            local ox, oy, edge, yards = G:_MinimapOffset((px - mx) * yw, (py - my) * yh, rYd, rPx, facing)
            used = used + 1
            local d = AcquireDot(used)
            local cc = GuildOS.ClassColors[p.class or ""] or C.textSoft
            d.disc:SetVertexColor(cc.r, cc.g, cc.b, 1)
            d.key, d.yards, d.peer = p.key, yards, nil
            d:ClearAllPoints()
            d:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
            d:SetAlpha(alpha * (edge and 0.6 or 1))
            d:Show()
        end)
    end
    for i = used + 1, #dots do dots[i]:Hide() end
end

----------------------------------------------------------------------
-- Entry points
----------------------------------------------------------------------

-- /gos map and the minimap menu: opens the world map with the guild list on it; again, closes the list.
function GuildOS:ToggleGuildMap()
    local wmf = Compat.GetWorldMapFrame()
    if wmf and wmf:IsShown() and list and list:IsShown() then
        GM():SetListShown(false)
        list:Hide()
        return
    end
    GM():SetListShown(true)
    Compat.OpenWorldMap()
    local function show()
        if not EnsureLayer() then return end
        if list and Compat.GetWorldMapFrame() and Compat.GetWorldMapFrame():IsShown() then list:Show() end
        dirty = true
        WatchShownMap()
    end
    show()
    -- The map may have loaded on demand this frame.
    Compat.After(0, show)
end

-- One-time wiring, from CreateMinimapButton: the minimap dots and the world map layer (as soon as the map
-- exists; it may load on demand).
function GuildOS:SetupGuildMapPresence()
    if GuildOS._guildMapPresence or not GM() then return end
    GuildOS._guildMapPresence = true
    GM().uiRefresh = function() dirty = true end
    if Minimap then
        dotsDriver = CreateFrame("Frame", nil, Minimap)
        local acc = 0
        dotsDriver:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.1 then return end
            acc = 0
            GuildOS:SafeCall(RefreshDots)
        end)
    end
    if not EnsureLayer() then
        -- Blizzard_WorldMap loads on demand on some clients: try again when it does.
        local ev = CreateFrame("Frame")
        Compat.RegisterEvent(ev, "ADDON_LOADED")
        ev:SetScript("OnEvent", function(self)
            if EnsureLayer() then self:UnregisterAllEvents() end
        end)
    end
end
