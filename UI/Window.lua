----------------------------------------------------------------------
-- Guild OS - Generic floating feature window
-- One draggable, resizable, position-remembering container. Content is
-- built lazily on first show by the feature's build(container, win), so
-- opening the addon constructs one window instead of thirteen panels.
--
-- A window duck-types the main frame's navigation interface
-- (SetActiveTab / tabPanels[key].SelectSub), which is why every existing
-- panel builder runs unchanged in either container.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local TITLE_H  = 26
local GRIP     = 14
local windows  = {}    -- id -> frame (created; shown or hidden)

----------------------------------------------------------------------
-- Geometry persistence (db.settings.windows[id])
----------------------------------------------------------------------
local function store()
    local w = BRutus:GetSetting("windows")
    if type(w) ~= "table" then
        w = {}
        BRutus:SetSetting("windows", w)
    end
    return w
end

function UI:SaveWindowGeometry(win)
    if not win.featureId then return end
    local point, _, relPoint, x, y = win:GetPoint()
    if not point then return end
    store()[win.featureId] = {
        point    = point,
        relPoint = relPoint or point,
        x        = math.floor((x or 0) + 0.5),
        y        = math.floor((y or 0) + 0.5),
        w        = math.floor(win:GetWidth() + 0.5),
        h        = math.floor(win:GetHeight() + 0.5),
    }
end

function UI:RestoreWindowGeometry(win, def)
    local g = win.featureId and store()[win.featureId]
    win:ClearAllPoints()
    if g and g.point then
        win:SetPoint(g.point, UIParent, g.relPoint or g.point, g.x or 0, g.y or 0)
        win:SetSize(g.w or def.w, g.h or def.h)
    else
        win:SetPoint("CENTER")
        win:SetSize(def.w, def.h)
    end
end

----------------------------------------------------------------------
-- UI scale: one global knob, applied to every live window and the hub.
----------------------------------------------------------------------
function UI:ApplyScale()
    local s = BRutus:GetSetting("uiScale") or 1
    for _, win in pairs(windows) do win:SetScale(s) end
    if self.Hub and self.Hub.frame then self.Hub.frame:SetScale(s) end
end

----------------------------------------------------------------------
-- Build the chrome. Content is NOT built here — see UI:OpenWindow.
----------------------------------------------------------------------
function UI:CreateWindow(id)
    local def = self:GetFeature(id)
    if not def or not def.hub then return nil end

    local name = "GuildOSWindow" .. id:gsub("^%l", string.upper)
    local win  = self:CreatePanel(UIParent, name)
    win.featureId = id
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:Hide()
    self:StylePopup(win)
    self:RestoreWindowGeometry(win, def)
    win:SetScale(BRutus:GetSetting("uiScale") or 1)

    -- Title bar doubles as the drag handle.
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        UI:SaveWindowGeometry(win)
    end)

    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local title = self:CreateHeaderText(bar, def.label, 11)
    title:SetPoint("LEFT", 10, 0)

    local line = self:CreateAccentLine(win, 1)
    line:SetPoint("TOPLEFT", 0, -TITLE_H)
    line:SetPoint("TOPRIGHT", 0, -TITLE_H)

    local close = self:CreateCloseButton(win)
    close:SetPoint("TOPRIGHT", -4, -3)
    close:SetScript("OnClick", function() UI:ToggleWindow(id) end)

    -- Resize grip (bottom-right), unless the feature opted out.
    if def.resizable ~= false then
        win:SetResizable(true)
        local minW, minH = def.minW or 380, def.minH or 260
        if win.SetResizeBounds then
            win:SetResizeBounds(minW, minH)
        elseif win.SetMinResize then
            win:SetMinResize(minW, minH)
        end

        local grip = CreateFrame("Button", nil, win)
        grip:SetSize(GRIP, GRIP)
        grip:SetPoint("BOTTOMRIGHT", -2, 2)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function()
            win:StopMovingOrSizing()
            UI:SaveWindowGeometry(win)
        end)
    end

    -- Content area: everything under the title bar.
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", 0, -(TITLE_H + 1))
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    win.content = content

    -- Navigation shim. Panels cross-navigate through the main frame's
    -- interface; in window mode "go to tab X" means "open window X".
    function win:SetActiveTab(key)
        UI:OpenWindow(key)
    end
    win.tabPanels = setmetatable({}, {
        __index = function(_, key)
            return { SelectSub = function(sub) UI:OpenWindow(key, sub) end }
        end,
    })

    table.insert(UISpecialFrames, name)   -- ESC closes the top window
    windows[id] = win
    return win
end

----------------------------------------------------------------------
-- Open (creating and building on demand). subKey deep-links a sub-tab.
----------------------------------------------------------------------
function UI:OpenWindow(id, subKey)
    local def = self:GetFeature(id)
    if not def or not def.hub then return end
    -- Durable gate: every future caller (the Task 5 hub included) routes
    -- through here, so this is the one place an officer-only feature needs
    -- to be checked rather than re-implemented at each call site. Mirrors
    -- the expanded-mode guard at Core/Core.lua:606-613.
    if def.officerOnly and not BRutus:IsOfficer() then
        BRutus:Print(string.format(L["%s is officer-only."], def.label))
        return
    end
    if not BRutus:IsFeatureEnabled(id) then
        BRutus:Print(string.format(L["%s is disabled in Settings."], def.label))
        return
    end

    local win = windows[id] or self:CreateWindow(id)
    if not win then return end
    if not win.built then
        win.built = true
        def.build(win.content, win)
    end
    win:Show()
    win:Raise()
    if subKey and win.content.SelectSub then win.content.SelectSub(subKey) end
    if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
end

function UI:ToggleWindow(id)
    local win = windows[id]
    if win and win:IsShown() then
        win:Hide()
        if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
        return
    end
    self:OpenWindow(id)
end

function UI:IsWindowOpen(id)
    local win = windows[id]
    return win ~= nil and win:IsShown()
end

-- The created window for a feature, or nil if it was never opened. Used by
-- refreshers that must find whichever container currently hosts a panel.
function UI:GetWindow(id)
    return windows[id]
end

function UI:CloseAllWindows()
    for _, win in pairs(windows) do win:Hide() end
    if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
end

----------------------------------------------------------------------
-- A feature turned off in Settings disappears everywhere, live: its
-- window closes, the hub row goes, the expanded-mode tab goes.
----------------------------------------------------------------------
function UI:OnFeatureToggled(id, enabled)
    if not enabled and windows[id] then windows[id]:Hide() end
    if self.Hub and self.Hub.Refresh then self.Hub:Refresh() end
    local rf = BRutus.RosterFrame
    if rf and rf.UpdateTabVisibility then rf:UpdateTabVisibility() end
end
