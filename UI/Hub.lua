----------------------------------------------------------------------
-- Guild OS - Hub
-- The minimal front door: a ~230px card with a live pulse band and one
-- clickable row per enabled feature. Rows toggle their feature's window,
-- so the hub is the only thing on screen until the user asks for more.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local Hub = {}
UI.Hub = Hub

local WIDTH   = 230
local TITLE_H = 24
local ROW_H   = 22
local PULSE_H = 34
local FOOT_H  = 22

local function cfg()
    local h = BRutus:GetSetting("hub")
    if type(h) ~= "table" then
        h = { collapsed = false, pulse = true }
        BRutus:SetSetting("hub", h)
    end
    return h
end

local function saveHubPos(f)
    local point, _, relPoint, x, y = f:GetPoint()
    local c = cfg()
    c.point, c.relPoint = point, relPoint or point
    c.x, c.y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end

function Hub:Create()
    if self.frame then return self.frame end
    local c = cfg()

    local f = UI:CreatePanel(UIParent, "GuildOSHub")
    f:SetWidth(WIDTH)
    f:SetHeight(TITLE_H + PULSE_H + FOOT_H)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    UI:StylePopup(f)
    f:ClearAllPoints()
    if c.point then
        f:SetPoint(c.point, UIParent, c.relPoint or c.point, c.x or 0, c.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -320, 120)
    end
    f:SetScale(BRutus:GetSetting("uiScale") or 1)
    self.frame = f

    -- Title bar: drag, and click to collapse to just this bar.
    local bar = CreateFrame("Button", nil, f)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLE_H)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); saveHubPos(f) end)
    bar:SetScript("OnClick", function()
        cfg().collapsed = not cfg().collapsed
        Hub:Refresh()
    end)

    local barBg = bar:CreateTexture(nil, "ARTWORK")
    barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    local title = UI:CreateHeaderText(bar, "GUILD OS", 11)
    title:SetPoint("LEFT", 8, 0)

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -3, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local gear = UI:CreateButton(f, "|TInterface\\Icons\\INV_Misc_Gear_01:12|t", 20, 18)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetScript("OnClick", function() UI:OpenWindow("settings") end)
    UI:AddTooltip(gear, L["Settings"])

    local expand = UI:CreateButton(f, "[ ]", 20, 18)
    expand:SetPoint("RIGHT", gear, "LEFT", -2, 0)
    expand:SetScript("OnClick", function()
        if BRutus.ToggleExpanded then BRutus:ToggleExpanded() end
    end)
    UI:AddTooltip(expand, L["Expanded mode"])

    -- Pulse band: two live lines, off when settings.hub.pulse is false.
    local pulse = CreateFrame("Frame", nil, f)
    pulse:SetPoint("TOPLEFT", 0, -TITLE_H)
    pulse:SetPoint("TOPRIGHT", 0, -TITLE_H)
    pulse:SetHeight(PULSE_H)
    f.pulse = pulse
    f.pulseOnline = UI:CreateText(pulse, "", 10, C.text.r, C.text.g, C.text.b)
    f.pulseOnline:SetPoint("TOPLEFT", 10, -4)
    f.pulseEvent = UI:CreateText(pulse, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.pulseEvent:SetPoint("TOPLEFT", 10, -18)

    -- Row pool: rows are reused across refreshes, never re-created.
    f.rows = {}
    f.footer = CreateFrame("Frame", nil, f)
    f.footer:SetHeight(FOOT_H)

    local more = UI:CreateButton(f.footer, L["... more"], 70, 18)
    more:SetPoint("LEFT", 8, 0)
    more:SetScript("OnClick", function() Hub:ToggleMorePage() end)

    local closeAll = UI:CreateButton(f.footer, L["Close all"], 70, 18)
    closeAll:SetPoint("RIGHT", -8, 0)
    closeAll:SetScript("OnClick", function() UI:CloseAllWindows() end)

    table.insert(UISpecialFrames, "GuildOSHub")
    return f
end

----------------------------------------------------------------------
-- One row: dot (window open) + icon + label + optional badge.
----------------------------------------------------------------------
local function acquireRow(f, index)
    local row = f.rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, f, "BackdropTemplate")
    row:SetSize(WIDTH - 12, ROW_H)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    row:SetBackdropColor(0, 0, 0, 0)

    row.dot = row:CreateTexture(nil, "OVERLAY")
    row.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.dot:SetSize(4, 4)
    row.dot:SetPoint("LEFT", 2, 0)
    row.dot:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 10, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
    row.label:SetPoint("LEFT", 30, 0)

    row.badge = UI:CreateText(row, "", 10, C.gold.r, C.gold.g, C.gold.b)
    row.badge:SetPoint("RIGHT", -8, 0)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
    end)

    f.rows[index] = row
    return row
end

----------------------------------------------------------------------
-- Rebuild the card from the registry. Cheap enough to call on every
-- open/close: it repositions pooled rows, it does not create frames.
----------------------------------------------------------------------
function Hub:Refresh()
    local f = self.frame
    if not f then return end
    local c = cfg()

    if c.collapsed then
        for _, row in pairs(f.rows) do row:Hide() end
        f.pulse:Hide()
        f.footer:Hide()
        f:SetHeight(TITLE_H)
        return
    end

    local y = TITLE_H
    if c.pulse then
        f.pulse:Show()
        -- Counted live from the guild roster API, the same way
        -- frame:UpdateRail does it (UI/RosterFrame.lua:925-943). db.members
        -- has no online flag.
        local online, total = 0, 0
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if name then
                total = total + 1
                if isOnline then online = online + 1 end
            end
        end
        f.pulseOnline:SetText(string.format(L["%d online of %d"], online, total))

        -- The next event belongs to the Guild feature; if that is switched
        -- off, the line goes with it.
        if BRutus:IsFeatureEnabled("guild") then
            local e = BRutus.Calendar and BRutus.Calendar:NextEvent()
            f.pulseEvent:SetText(e and (e.title or "?") or L["No upcoming events scheduled."])
        else
            f.pulseEvent:SetText("")
        end
        y = y + PULSE_H
    else
        f.pulse:Hide()
    end

    local defs = self.morePage and self:MoreEntries() or UI:VisibleFeatures("hub")
    local shown = 0
    for i, def in ipairs(defs) do
        local row = acquireRow(f, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -y)
        row.label:SetText(def.label)
        if def.icon then row.icon:SetTexture(def.icon) else row.icon:SetTexture(nil) end
        row.dot:SetShown(UI:IsWindowOpen(def.id))
        local n = def.badge and def.badge() or 0
        row.badge:SetText((n and n > 0) and tostring(n) or "")
        row:SetScript("OnClick", function()
            if def.run then def.run()
            elseif def.sub then UI:OpenWindow(def.id, def.sub)
            else UI:ToggleWindow(def.id) end
        end)
        row:Show()
        y = y + ROW_H
        shown = i
    end
    for i = shown + 1, #f.rows do f.rows[i]:Hide() end

    if shown == 0 then
        local row = acquireRow(f, 1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -y)
        row.icon:SetTexture(nil)
        row.dot:Hide()
        row.badge:SetText("")
        row.label:SetText(L["Everything is disabled — open Settings"])
        row:SetScript("OnClick", function() UI:OpenWindow("settings") end)
        row:Show()
        y = y + ROW_H
    end

    f.footer:ClearAllPoints()
    f.footer:SetPoint("TOPLEFT", 0, -(y + 2))
    f.footer:SetPoint("TOPRIGHT", 0, -(y + 2))
    f.footer:Show()
    f:SetHeight(y + 2 + FOOT_H)
end

----------------------------------------------------------------------
-- Second page: loose tools and sub-tab deep links, shown in the same
-- card so "more" never costs another window.
----------------------------------------------------------------------
function Hub:MoreEntries()
    local out = {}
    local function add(id, label, sub, fn)
        out[#out + 1] = { id = id, label = label, sub = sub, badge = nil, run = fn }
    end
    add("roster", L["Search"], nil)
    out[#out].run = function() if BRutus.Search then BRutus.Search:Show() end end
    if BRutus:IsFeatureEnabled("raids") then
        add("raids", L["Raids"] .. " > " .. L["Audit"], "audit")
        add("raids", L["Raids"] .. " > " .. L["Raid Tools"], "raidtools")
    end
    if BRutus:IsFeatureEnabled("guild") then
        add("guild", L["Guild"] .. " > " .. L["Calendar"], "calendar")
    end
    return out
end

function Hub:ToggleMorePage()
    self.morePage = not self.morePage
    self:Refresh()
end

function Hub:Toggle()
    local f = self:Create()
    if f:IsShown() then
        f:Hide()
    else
        self.morePage = false
        self:Refresh()
        f:Show()
    end
end
