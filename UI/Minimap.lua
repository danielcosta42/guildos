----------------------------------------------------------------------
-- Guild OS - Minimap button
-- A self-contained draggable minimap button (no LibDBIcon dependency).
-- Left-click opens the roster; drag to reposition around the minimap.
-- Position (angle) and visibility persist in settings.minimap.
----------------------------------------------------------------------
local C = BRutus.Colors
local L = BRutus.L

local RADIUS = 80          -- distance from minimap center
local DEFAULT_ANGLE = 215  -- degrees; lower-left by default

local function GetMinimapCfg()
    local m = BRutus:GetSetting("minimap")
    if type(m) ~= "table" then
        m = { hide = false }
        BRutus:SetSetting("minimap", m)
    end
    return m
end

local function UpdatePosition(btn)
    local a = math.rad((GetMinimapCfg().angle) or DEFAULT_ANGLE)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * RADIUS, math.sin(a) * RADIUS)
end

local function OnDragUpdate(btn)
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    GetMinimapCfg().angle = angle
    UpdatePosition(btn)
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

    -- Icon + standard minimap-button border
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\GuildFrame\\GuildLogo-NoLogo")
    icon:SetVertexColor(C.gold.r, C.gold.g, C.gold.b)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

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
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffFFD700Guild|r |cffD4AC0DOS|r  |cff666666by Chehul|r")
        GameTooltip:AddLine(L["Left-click: open"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: menu"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Drag: move button"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition(btn)
    if GetMinimapCfg().hide then btn:Hide() end

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
