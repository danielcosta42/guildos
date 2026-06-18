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
            -- Right-click jumps straight to the roster's Settings tab.
            BRutus:ToggleRoster()
            if BRutus.RosterFrame and BRutus.RosterFrame:IsShown() then
                BRutus.RosterFrame:SetActiveTab("settings")
            end
        else
            BRutus:ToggleRoster()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffFFD700Guild|r |cffD4AC0DOS|r")
        GameTooltip:AddLine(L["Left-click: open"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: settings"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Drag: move button"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition(btn)
    if GetMinimapCfg().hide then btn:Hide() end

    self.minimapButton = btn
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
