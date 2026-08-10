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
-- Window stacking
--
-- Every window is built by UI:CreatePanel, which pins the frame to level
-- 1, and its children then take parent + 1 from there. Panels nest to
-- different depths, so two open windows occupied overlapping level ranges
-- and a deep child of the window BEHIND could outrank a shallow frame of
-- the window in FRONT: the two drew interleaved rather than one over the
-- other.
--
-- The fix is to hand each window its own band and write it across the
-- whole subtree, rather than calling Raise() on the root and trusting the
-- client to carry the children with it. Doing it explicitly makes the
-- stacking the addon's own invariant, verifiable without the game running
-- (see window.raise_gives_each_window_its_own_band).
----------------------------------------------------------------------
local STACK_BASE    = 10
local STACK_CEILING = 4000   -- well under the client's 10000 level cap
local nextLevel     = STACK_BASE

-- Level the subtree from `level` down, and report the deepest level used.
local function applyLevels(frame, level)
    frame:SetFrameLevel(level)
    local deepest = level
    for _, child in ipairs({ frame:GetChildren() }) do
        local d = applyLevels(child, level + 1)
        if d > deepest then deepest = d end
    end
    return deepest
end

-- Re-stack every other open window from the base, preserving the order
-- they are in now. Without this the counter climbs all session and would
-- eventually run into the client's cap, where every window clamps to the
-- same level and the interleaving comes straight back.
local function renormalise(exclude)
    local open = {}
    for _, w in pairs(windows) do
        if w ~= exclude and w:IsShown() then open[#open + 1] = w end
    end
    table.sort(open, function(a, b) return (a.__stackBase or 0) < (b.__stackBase or 0) end)
    nextLevel = STACK_BASE
    for _, w in ipairs(open) do
        w.__stackBase = nextLevel
        nextLevel = applyLevels(w, nextLevel) + 1
    end
end

function UI:RaiseWindow(win)
    if not win then return end
    if nextLevel > STACK_CEILING then renormalise(win) end
    win.__stackBase = nextLevel
    nextLevel = applyLevels(win, nextLevel) + 1
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
    bar:SetScript("OnMouseDown", function() UI:RaiseWindow(win) end)
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        UI:SaveWindowGeometry(win)
    end)

    -- Clicking the window brings it forward. A mouse-enabled child consumes
    -- its own clicks, so this covers the chrome and any empty area; the
    -- title bar above is the reliable "bring to front" gesture.
    win:SetScript("OnMouseDown", function() UI:RaiseWindow(win) end)

    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local title = self:CreateHeaderText(bar, def.label, 11)
    title:SetPoint("LEFT", 10, 0)

    local line = self:CreateAccentLine(win, 1)
    line:SetPoint("TOPLEFT", 0, -TITLE_H)
    line:SetPoint("TOPRIGHT", 0, -TITLE_H)

    -- Parented to the bar, not the window: a sibling at the same frame
    -- level loses every click to the bar's drag handler.
    local close = self:TitleBarButton(bar, "close")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -3)
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

    -- Content area: everything under the title bar. Clipping is the net
    -- under the responsive layout: a panel that still miscalculates gets
    -- truncated inside its own window instead of painting over the rest
    -- of the screen, which is what every unconverted panel used to do.
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", 0, -(TITLE_H + 1))
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    if content.SetClipsChildren then content:SetClipsChildren(true) end
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
    -- the expanded-mode guard at Core/Core.lua:606-613. IsFeatureEnabled is
    -- tested first so a disabled feature and a rank refusal print different
    -- messages; IsFeatureAllowed is the single gate (also covers `condition`,
    -- which some officer-only features — wishlist — express instead of
    -- `officerOnly`).
    if not BRutus:IsFeatureEnabled(id) then
        BRutus:Print(string.format(L["%s is disabled in Settings."], def.label))
        return
    end
    if not self:IsFeatureAllowed(def) then
        BRutus:Print(string.format(L["%s is officer-only."], def.label))
        return
    end

    local win = windows[id] or self:CreateWindow(id)
    if not win then return end
    if not win.built then
        win.built = true
        def.build(win.content, win)
    end
    win:Show()
    -- After build(): the panel's frames have to exist before they can be
    -- levelled, or the subtree walk misses everything inside the window.
    self:RaiseWindow(win)
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
