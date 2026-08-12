----------------------------------------------------------------------
-- Guild OS - Minimap button
-- A self-contained draggable minimap button (no LibDBIcon dependency).
-- Left-click opens the roster; drag to reposition around the minimap.
-- Position (angle) and visibility persist account-wide in GuildOSDB.minimap.
----------------------------------------------------------------------
local C = BRutus.Colors
local L = BRutus.L

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
        local old = BRutus:GetSetting("minimap")   -- one-time lift out of the guild DB
        GuildOSDB.minimap = (type(old) == "table") and old or { hide = false }
    end
    cachedCfg = GuildOSDB.minimap
    return cachedCfg
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
-- still opens the roster; the menu exposes the guild map and settings.
local menuFrame

local function MinimapMenu_Init(_, level)
    local info = UIDropDownMenu_CreateInfo()
    info.isTitle = true; info.notCheckable = true
    info.text = "|cffFFD700Guild|r |cffD4AC0DOS|r"
    UIDropDownMenu_AddButton(info, level)

    for _, def in ipairs(BRutus.UI:VisibleFeatures("hub")) do
        info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
        info.text = def.label
        info.func = function() BRutus.UI:OpenWindow(def.id); CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)
    end

    info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
    info.text = L["Guild Map"]
    info.func = function()
        if BRutus.ToggleGuildMap then BRutus:ToggleGuildMap() end
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
    info.text = L["Do I know this pug?"]
    info.func = function()
        if BRutus.TogglePugInspector then BRutus:TogglePugInspector() end
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
    info.text = L["Hide minimap button"]
    info.func = function() BRutus:SetMinimapShown(false); CloseDropDownMenus() end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo(); info.notCheckable = true
    info.text = CANCEL or L["Cancel"]
    UIDropDownMenu_AddButton(info, level)
end

local function ShowMinimapMenu()
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "GuildOSMinimapMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(menuFrame, MinimapMenu_Init, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 3, -3)
end

function BRutus:CreateMinimapButton()
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
            -- Right-click opens the menu (roster / guild map / settings).
            ShowMinimapMenu()
        else
            BRutus:ToggleRoster()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        ring:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffFFD700Guild|r |cffD4AC0DOS|r  |cff666666by Chehul|r")
        GameTooltip:AddLine(L["Left-click: open"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: menu"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Drag: move button"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        ring:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, RING_ALPHA)
        GameTooltip:Hide()
    end)

    UpdatePosition(btn)
    if GetMinimapCfg().hide then btn:Hide() end

    -- ponytail: one late repass instead of watching the minimap for resizes.
    -- Covers addons that resize it while loading; if someone starts resizing
    -- the minimap live, hooksecurefunc(Minimap, "SetWidth", ...) is the upgrade.
    BRutus.Compat.After(1, function() UpdatePosition(btn) end)

    self.minimapButton = btn

    -- Wire the live guild map presence layer (minimap zone dots + refresh hook)
    -- now that the minimap definitely exists. Safe to call once.
    if BRutus.SetupGuildMapPresence then BRutus:SetupGuildMapPresence() end

    return btn
end

-- Show/hide toggle (used by the slash command and settings).
function BRutus:ToggleMinimapButton()
    local cfg = GetMinimapCfg()
    cfg.hide = not cfg.hide
    if self.minimapButton then
        self.minimapButton:SetShown(not cfg.hide)
    end
    return not cfg.hide
end

-- Explicit show/hide (used by the Settings checkbox).
function BRutus:SetMinimapShown(shown)
    local cfg = GetMinimapCfg()
    cfg.hide = not shown
    if self.minimapButton then
        self.minimapButton:SetShown(shown and true or false)
    end
end

function BRutus:IsMinimapShown()
    return not GetMinimapCfg().hide
end

-- The button position used to be stored per guild, so a mid-session db swap
-- (guildless cold login resolving into the real guild) silently threw the
-- dragged angle away and snapped the button back to the default.
if BRutus.SelfTest then
    BRutus.SelfTest:Register("minimap.angle_survives_db_swap", function()
        local c = GetMinimapCfg()
        local prev = c.angle
        c.angle = 123

        local savedDb, savedKey = BRutus.db, BRutus.guildKey
        BRutus.db = { settings = { minimap = { hide = false } } }
        BRutus.guildKey = "__selftest-guild"
        local seen = GetMinimapCfg().angle
        BRutus.db, BRutus.guildKey = savedDb, savedKey

        c.angle = prev
        if seen ~= 123 then
            return false, "angle lost on db swap: got " .. tostring(seen)
        end
        return true
    end)
end
