----------------------------------------------------------------------
-- Guild OS - Minimap button
-- A self-contained draggable minimap button (no LibDBIcon dependency).
-- Left-click opens the roster; drag to reposition around the minimap.
-- Position (angle) and visibility persist account-wide in GuildOSDB.minimap.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local C = GuildOS.Colors
local L = GuildOS.L

local MEDIA = "Interface\\AddOns\\GuildOS\\Media\\"

local RADIUS_PAD = 5       -- how far outside the minimap edge the button sits
local DEFAULT_ANGLE = 215  -- degrees; lower-left by default
local RING_ALPHA = 0.8     -- anel parado; vai a 1 no hover

-- Where you parked the button is a UI preference, not guild data. It used to
-- live in db.settings.minimap, which is GuildOSDB[<guild>-<realm>]: every alt
-- in another guild, and every cold login that fell back to the guildless DB,
-- got a fresh table and the button jumped back to the default angle. Resolved
-- once and cached, so a mid-session db swap can no longer split the write from
-- the read either.
local cachedCfg

local function GetMinimapCfg()
    if cachedCfg then return cachedCfg end
    if type(GuildOSDB) ~= "table" then return { hide = false } end  -- pre-login
    if type(GuildOSDB.minimap) ~= "table" then
        local old = GuildOS:GetSetting("minimap")   -- one-time lift out of the guild DB
        GuildOSDB.minimap = (type(old) == "table") and old or { hide = false }
    end
    cachedCfg = GuildOSDB.minimap
    return cachedCfg
end

-- The ring's colour: gold, brighter under the cursor; green while a guild is waiting to be looked at.
local function RingColor(hover)
    if GuildOS.minimapAlert then return C.ok.r, C.ok.g, C.ok.b, 1 end
    return C.gold.r, C.gold.g, C.gold.b, hover and 1 or RING_ALPHA
end

local function UpdatePosition(btn, angle)
    angle = angle or GetMinimapCfg().angle or DEFAULT_ANGLE
    local a = math.rad(angle)
    -- Radius from the live minimap size, not a hardcoded 80: any addon that
    -- resizes the minimap used to leave the button floating off the ring.
    local r = (Minimap:GetWidth() / 2) + RADIUS_PAD
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function OnDragUpdate(btn)
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    GetMinimapCfg().angle = angle
    -- Pass the angle through rather than re-reading it: the drag must never
    -- depend on the write having landed somewhere the read can see.
    UpdatePosition(btn, angle)
end

-- Right-click context menu for the minimap button (built lazily). Left-click
-- still opens the roster; the menu exposes the tabs and settings.
-- The mockup's .mmenu: GuildOS's own small popup (the dark of a popup, the bright metal's line, rows that
-- light gold under the cursor, a dark rule between groups), not the game's dropdown.
local menuFrame, menuCatcher

-- What the menu lists, in order: { text, func, title = true, rule = true (a rule above it) }.
function GuildOS:MinimapMenuItems()
    local items = { { text = "Guild OS", title = true } }
    local function close() if menuFrame then menuFrame:Hide() end end

    -- An officer with people waiting: the list is one click away (the mock's tab 3).
    local requests = GuildOS.JoinRequests
    local waiting = 0
    if requests and GuildOS.ShowJoinRequests and IsInGuild() and GuildOS:IsOfficer() then
        local ok, n = pcall(requests.OpenCount, requests)
        waiting = ok and n or 0
    end
    if waiting > 0 then
        items[#items + 1] = { text = string.format(L["Join requests (%d)"], waiting),
            func = function() close(); GuildOS:ShowJoinRequests() end }
    end

    -- Craft orders waiting for me (issue #389): the inbox, one click away.
    local orders = GuildOS.CraftOrders
    local pending = 0
    if orders and IsInGuild() then
        local ok, n = pcall(orders.InboxCount, orders)
        pending = ok and n or 0
    end
    if pending > 0 then
        items[#items + 1] = { text = string.format(L["Craft orders (%d)"], pending),
            func = function() close(); GuildOS.UI:OpenWindow("recipes", "forme") end }
    end

    -- The window's rooms, as its top bar draws them (#449), then the gear's Settings (never in VisibleRooms).
    local UI = GuildOS.UI
    local function openRoom(id)
        local f = UI:GetMainWindow()
        if not f then return end
        f:Show()
        -- A room asked for by name has to be seen, so the bar opens back up.
        local g = GuildOS:GetSetting("window")
        if (type(g) == "table" and g.collapsed) or f.band == "bar" then f:ToggleCollapsed() end
        f:OpenRoom(id, true)
    end
    -- Groups, near the top (#449): Raids › Groups in one click, with how many are open when any is.
    if UI.GetFeature and UI:GetFeature("groups") and GuildOS:IsFeatureEnabled("groups") then
        local S = UI.Salao
        local st = S and S.GroupsNow and S:GroupsNow()
        local text = (st and st.open > 0) and string.format(L["Groups (%d open)"], st.open) or L["Groups"]
        items[#items + 1] = { text = text, groups = true, func = function() close(); UI:OpenWindow("groups") end }
    end
    local first = true
    for _, room in ipairs(UI.VisibleRooms and UI:VisibleRooms() or {}) do
        local id = room.id
        items[#items + 1] = { text = room.label, rule = first and #items > 1,
            func = function() close(); openRoom(id) end }
        first = false
    end
    if UI.RoomAllowed and UI:RoomAllowed("settings") then
        items[#items + 1] = { text = L["Settings"], rule = first and #items > 1,
            func = function() close(); openRoom("settings") end }
    end

    items[#items + 1] = { text = L["Guild Map"], rule = true, func = function()
        close()
        if GuildOS.ToggleGuildMap then GuildOS:ToggleGuildMap() end
    end }
    items[#items + 1] = { text = L["Do I know this pug?"], func = function()
        close()
        if GuildOS.TogglePugInspector then GuildOS:TogglePugInspector() end
    end }
    items[#items + 1] = { text = L["Hide minimap button"], func = function() close(); GuildOS:SetMinimapShown(false) end }
    items[#items + 1] = { text = CANCEL or L["Cancel"], rule = true, func = close }
    return items
end

local MENU_W, MENU_ROW, MENU_PAD = 220, 22, 4

local function menuRow(i)
    local rows = menuFrame.rows
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, menuFrame)
    row:SetHeight(MENU_ROW)
    -- The menu row's warm gold wash, 4px corners (UI:MenuRow's).
    local wash = GuildOS.Style and GuildOS.Style.Nine and GuildOS.Style:Nine(row, "card", 4, "BACKGROUND", 1)
    if wash then
        wash:SetRGBA(1, 0.843, 0.478, 0.22)
        wash.Show, wash.Hide = function(w) w:SetShown(true) end, function(w) w:SetShown(false) end
    else
        wash = row:CreateTexture(nil, "BACKGROUND")
        wash:SetTexture("Interface\\Buttons\\WHITE8x8")
        wash:SetAllPoints()
        wash:SetVertexColor(1, 0.843, 0.471, 0.1)
    end
    wash:Hide()
    row.wash = wash
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetPoint("LEFT", 10, 0)
    row.text:SetPoint("RIGHT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.rule = menuFrame:CreateTexture(nil, "ARTWORK")
    row.rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.rule:SetVertexColor(0.227, 0.165, 0.09, 1)   -- the menus' separator, #3a2a17
    row.rule:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 4, 3)
    row.rule:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", -4, 3)
    GuildOS.UI:Hairline(row.rule)
    row:SetScript("OnEnter", function(self) if self.func then self.wash:Show() end end)
    row:SetScript("OnLeave", function(self) self.wash:Hide() end)
    row:SetScript("OnClick", function(self) if self.func then self.func() end end)
    rows[i] = row
    return row
end

local function buildMenu()
    menuFrame = CreateFrame("Frame", "GuildOSMinimapMenu", UIParent, "BackdropTemplate")
    menuFrame:SetWidth(MENU_W)
    menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    menuFrame:SetFrameLevel(20)
    menuFrame:SetClampedToScreen(true)
    menuFrame:EnableMouse(true)
    -- The addon's one menu look (UI:PaintMenu, the mockup's .mmenu; #449), as the dropdowns' lists.
    if GuildOS.UI and GuildOS.UI.PaintMenu then
        GuildOS.UI:PaintMenu(menuFrame)
    elseif GuildOS.Style and GuildOS.Style.Paint then
        GuildOS.Style:Paint(menuFrame, "panel")
        menuFrame:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 0.98)
        menuFrame:SetBackdropBorderColor(C.metal2.r, C.metal2.g, C.metal2.b, 1)
    end
    menuFrame.rows = {}
    menuFrame:Hide()
    table.insert(UISpecialFrames, "GuildOSMinimapMenu")   -- Escape closes it
    -- A click anywhere else closes it. Where the client has GLOBAL_MOUSE_DOWN it is heard, and nothing
    -- covers the screen; a press on the menu or on the button (whose own click toggles it) is not "else".
    if GuildOS.Compat.RegisterEvent(menuFrame, "GLOBAL_MOUSE_DOWN", true) then
        menuFrame:SetScript("OnEvent", function(self, event)
            if event ~= "GLOBAL_MOUSE_DOWN" or not self:IsShown() or self:IsMouseOver() then return end
            local btn = GuildOS.minimapButton
            if btn and btn:IsMouseOver() then return end
            self:Hide()
        end)
        return
    end
    -- Otherwise a see-through catcher, shown while it is: on DIALOG, under the menu's FULLSCREEN_DIALOG,
    -- so the game's own full-screen dialogs stay above it.
    menuCatcher = CreateFrame("Button", nil, UIParent)
    menuCatcher:SetAllPoints(UIParent)
    menuCatcher:SetFrameStrata("DIALOG")
    menuCatcher:RegisterForClicks("AnyUp")
    menuCatcher:SetScript("OnClick", function() menuFrame:Hide() end)
    menuCatcher:Hide()
    menuFrame:SetScript("OnShow", function() menuCatcher:Show() end)
    menuFrame:SetScript("OnHide", function() menuCatcher:Hide() end)
end

local function ShowMinimapMenu()
    if menuFrame and menuFrame:IsShown() then menuFrame:Hide(); return end
    if not menuFrame then buildMenu() end
    local items = GuildOS:MinimapMenuItems()
    local y = MENU_PAD
    for i, item in ipairs(items) do
        local row = menuRow(i)
        if item.rule then y = y + 7 end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", MENU_PAD, -y)
        row:SetPoint("TOPRIGHT", -MENU_PAD, -y)
        row.func = item.func
        row.rule:SetShown(item.rule and true or false)
        if item.title then
            GuildOS:ApplyFont(row.text, 13, "sectionTitle")
            row.text:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        else
            GuildOS:ApplyFont(row.text, 12)
            row.text:SetTextColor(C.text.r, C.text.g, C.text.b)
        end
        row.text:SetText(item.text)
        row:Show()
        y = y + MENU_ROW
    end
    for i = #items + 1, #menuFrame.rows do menuFrame.rows[i]:Hide(); menuFrame.rows[i].rule:Hide() end
    menuFrame:SetHeight(y + MENU_PAD)
    -- At the cursor, as the game's menu opened.
    local x, cy = 0, 0
    if GetCursorPosition then x, cy = GetCursorPosition() end
    local scale = UIParent:GetEffectiveScale() or 1
    menuFrame:ClearAllPoints()
    menuFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (x or 0) / scale - 3, (cy or 0) / scale - 3)
    menuFrame:Show()
end

function GuildOS:CreateMinimapButton()
    if self.minimapButton then return self.minimapButton end
    if not Minimap then return nil end

    local btn = CreateFrame("Button", "GuildOSMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    -- O escudo do logo do addon, recortado em círculo, dentro de um anel
    -- dourado. O logo já vem colorido; só o anel é branco e tingido daqui,
    -- para acender no hover e acompanhar o tema.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER")
    icon:SetTexture(MEDIA .. "minimap-logo")

    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetSize(30, 30)
    ring:SetPoint("CENTER")
    ring:SetTexture(MEDIA .. "minimap-ring")
    ring:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, RING_ALPHA)
    btn.ring = ring

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            -- Right-click opens the menu (roster / tabs / settings).
            ShowMinimapMenu()
        else
            GuildOS:ToggleRoster()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        ring:SetVertexColor(RingColor(true))
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffFFD700Guild|r |cffD4AC0DOS|r  |cff666666by Chehul|r")
        GameTooltip:AddLine(L["Left-click: open"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: menu"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Drag: move button"], 0.5, 0.5, 0.5)
        local orders = GuildOS.CraftOrders
        local ok, pending = false, 0
        if orders and IsInGuild() then ok, pending = pcall(orders.InboxCount, orders) end
        if ok and (pending or 0) > 0 then
            GameTooltip:AddLine(string.format(L["Craft orders waiting for you: %d (right-click)"], pending), C.ok.r, C.ok.g, C.ok.b)
        end
        if GuildOS.minimapAlert and IsInGuild() then
            GameTooltip:AddLine(L["Somebody asked to join the guild: right-click for the list"], C.ok.r, C.ok.g, C.ok.b)
        elseif GuildOS.minimapAlert then
            GameTooltip:AddLine(L["A guild is recruiting nearby: left-click to look"], C.ok.r, C.ok.g, C.ok.b)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        ring:SetVertexColor(RingColor(false))
        GameTooltip:Hide()
    end)

    UpdatePosition(btn)
    if GetMinimapCfg().hide then btn:Hide() end

    -- ponytail: one late repass instead of watching the minimap for resizes.
    -- Covers addons that resize it while loading; if someone starts resizing
    -- the minimap live, hooksecurefunc(Minimap, "SetWidth", ...) is the upgrade.
    GuildOS.Compat.After(1, function() UpdatePosition(btn) end)

    self.minimapButton = btn

    -- The live guild map's minimap dots and world map pins (issue #449), now that the minimap exists.
    if GuildOS.SetupGuildMapPresence then GuildOS:SafeCall(GuildOS.SetupGuildMapPresence, GuildOS) end

    return btn
end

-- Light the ring (or put it out): the guild finder uses it to say a guild was heard (specs/071).
function GuildOS:SetMinimapAlert(on)
    self.minimapAlert = on and true or false
    local btn = self.minimapButton
    if btn and btn.ring then btn.ring:SetVertexColor(RingColor(false)) end
end

-- Show/hide toggle (used by the slash command and settings).
function GuildOS:ToggleMinimapButton()
    local cfg = GetMinimapCfg()
    cfg.hide = not cfg.hide
    if self.minimapButton then
        self.minimapButton:SetShown(not cfg.hide)
    end
    return not cfg.hide
end

-- Explicit show/hide (used by the Settings checkbox).
function GuildOS:SetMinimapShown(shown)
    local cfg = GetMinimapCfg()
    cfg.hide = not shown
    if self.minimapButton then
        self.minimapButton:SetShown(shown and true or false)
    end
end

function GuildOS:IsMinimapShown()
    return not GetMinimapCfg().hide
end

-- The button position used to be stored per guild, so a mid-session db swap
-- (guildless cold login resolving into the real guild) silently threw the
-- dragged angle away and snapped the button back to the default.
if GuildOS.SelfTest then
    GuildOS.SelfTest:Register("minimap.angle_survives_db_swap", function()
        local c = GetMinimapCfg()
        local prev = c.angle
        c.angle = 123

        local savedDb, savedKey = GuildOS.db, GuildOS.guildKey
        GuildOS.db = { settings = { minimap = { hide = false } } }
        GuildOS.guildKey = "__selftest-guild"
        local seen = GetMinimapCfg().angle
        GuildOS.db, GuildOS.guildKey = savedDb, savedKey

        c.angle = prev
        if seen ~= 123 then
            return false, "angle lost on db swap: got " .. tostring(seen)
        end
        return true
    end)
end
