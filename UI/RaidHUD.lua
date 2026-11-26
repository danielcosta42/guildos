----------------------------------------------------------------------
-- UI/RaidHUD.lua
-- The consumables check popup (a click opens it: the HUD's, Readiness', Raid Tools'). The raid cooldown
-- HUD itself is Modules/RaidHUD.lua (#449), which reads Raid Tools' one list of cooldowns
-- (RT_TOOLS:TrackedCooldowns(), audit B19).
----------------------------------------------------------------------
local GuildOS = GuildOS
local UI     = GuildOS.UI
local C      = GuildOS.Colors
local L      = GuildOS.L

local _consPopup = nil
local HEADER_H     = 22
local CP_W         = 320   -- compact consumables panel width
local CONS_ROW_H   = 18    -- compact "missing" row height
local CONS_MAX_ROWS = 12   -- cap visible rows before the list scrolls

-- Closed with the HUD when the raid ends.
function GuildOS:HideConsumablePopup()
    if _consPopup then _consPopup:Hide() end
end

----------------------------------------------------------------------
-- CONSUMABLE PANEL — compact "problems only" floating frame
----------------------------------------------------------------------
local function BuildConsPopup(f)
    local CC = GuildOS.ConsumableChecker
    if not CC then return end

    local results = CC:GetLastResults()

    -- Status line
    if CC.lastCheck then
        local ago = floor(GetServerTime() - (CC.lastCheck.time or 0))
        f.statusText:SetText(L["Scanned "] .. ago .. L["s ago"])
    elseif results and next(results) then
        f.statusText:SetText(L["Previous session — rescan"])
    else
        f.statusText:SetText(L["No data"])
    end

    -- Only players missing something are listed; on retail one the client could not read is neither
    -- missing nor ready (issue #187).
    local problems, total, ready, unread = CC:Tally(results)
    table.sort(problems, function(a, b)
        local ca, cb = a.class or "ZZZ", b.class or "ZZZ"
        if ca == cb then return (a.name or "") < (b.name or "") end
        return ca < cb
    end)

    f.countText:SetText(total > 0 and (ready .. "/" .. total .. L[" ready"]) or "")

    for _, row in ipairs(f.rowPool) do row:Hide() end

    local content = f.content
    local yOff = 0

    if total == 0 then
        f.emptyText:SetText(L["Join a raid and scan."])
        f.emptyText:Show()
    elseif #problems == 0 and unread > 0 then
        f.emptyText:SetText(string.format(L["%d could not be read (out of range, or hidden by the game)."], unread))
        f.emptyText:Show()
    elseif #problems == 0 then
        f.emptyText:SetText("|cff4CFF4C" .. L["Everyone is prepared!"] .. "|r")
        f.emptyText:Show()
    else
        f.emptyText:Hide()
        for idx, p in ipairs(problems) do
            local row = f.rowPool[idx]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetHeight(CONS_ROW_H)
                row._name = UI:CreateText(row, "", 11, 1, 1, 1)
                row._name:SetPoint("LEFT", 4, 0)
                row._name:SetWidth(94)
                row._name:SetJustifyH("LEFT")
                row._name:SetWordWrap(false)
                row._miss = UI:CreateText(row, "", 10, C.red.r, C.red.g, C.red.b)
                row._miss:SetPoint("LEFT", 102, 0)
                row._miss:SetPoint("RIGHT", -4, 0)
                row._miss:SetJustifyH("LEFT")
                row._miss:SetWordWrap(false)
                f.rowPool[idx] = row
            end
            row:SetWidth(content:GetWidth())
            row:SetPoint("TOPLEFT", 0, -yOff)
            local cr, cg, cbv = GuildOS:GetClassColor(p.class)
            row._name:SetTextColor(cr, cg, cbv)
            row._name:SetText(p.name or "?")
            row._miss:SetText(table.concat(p.missing, ", "))
            row:Show()
            yOff = yOff + CONS_ROW_H
        end
    end

    content:SetHeight(math.max(1, yOff))

    -- Dynamic panel height: header + toolbar + body (capped) + padding
    local visibleRows = math.min(#problems, CONS_MAX_ROWS)
    local bodyH = (#problems > 0) and (visibleRows * CONS_ROW_H) or 30
    f:SetHeight(HEADER_H + 28 + bodyH + 10)
end

function GuildOS:ShowConsumablePopup()
    local CC = GuildOS.ConsumableChecker
    if CC then CC:CheckRaid() end

    if _consPopup then
        _consPopup:Show()
        BuildConsPopup(_consPopup)
        return
    end

    local WHITE = "Interface\\Buttons\\WHITE8x8"
    local f = CreateFrame("Frame", "GuildOSConsPopup", UIParent, "BackdropTemplate")
    f:SetSize(CP_W, 160)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 0.97)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(60)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Header
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(HEADER_H)
    hdr:SetPoint("TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", 0, 0)
    local hbg = hdr:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetTexture(WHITE)
    hbg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1)

    local hTitle = UI:CreateText(hdr, L["Consumables"], 12, C.gold.r, C.gold.g, C.gold.b)
    hTitle:SetPoint("LEFT", 10, 0)

    local hClose = UI:CreateCloseButton(hdr)
    hClose:SetPoint("RIGHT", -4, 0)
    hClose:SetScript("OnClick", function() f:Hide() end)

    f.countText = UI:CreateText(hdr, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.countText:SetPoint("RIGHT", hClose, "LEFT", -8, 0)

    -- Toolbar: status (left) + scan/announce (right)
    f.statusText = UI:CreateText(f, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    f.statusText:SetPoint("TOPLEFT", 10, -(HEADER_H + 8))

    local scanBtn = UI:CreateButton(f, L["Scan"], 78, 20)
    scanBtn:SetPoint("TOPRIGHT", -10, -(HEADER_H + 4))
    scanBtn:SetScript("OnClick", function()
        if GuildOS.ConsumableChecker then GuildOS.ConsumableChecker:CheckRaid() end
        BuildConsPopup(f)
    end)

    local repBtn = UI:CreateButton(f, L["Announce"], 78, 20)
    repBtn:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)
    repBtn:SetScript("OnClick", function()
        if GuildOS.ConsumableChecker then GuildOS.ConsumableChecker:ReportToChat("RAID") end
    end)

    -- Centered message for "all prepared" / "no data"
    f.emptyText = UI:CreateText(f, "", 12, C.silver.r, C.silver.g, C.silver.b)
    f.emptyText:SetPoint("TOP", 0, -(HEADER_H + 36))

    -- Scrollable problem list
    local scroll = CreateFrame("ScrollFrame", "GuildOSConsPopupScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -(HEADER_H + 28))
    scroll:SetPoint("BOTTOMRIGHT", -22, 8)
    UI:SkinScrollBar(scroll, "GuildOSConsPopupScroll")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CP_W - 30, 1)
    scroll:SetScrollChild(content)

    f.content = content
    f.rowPool = {}

    UI:StylePopup(f)
    _consPopup = f
    BuildConsPopup(f)
end
