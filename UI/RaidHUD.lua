----------------------------------------------------------------------
-- UI/RaidHUD.lua
-- Floating Raid CD Tracker + Consumable Check popup
-- Auto-shows when in raid as leader or assist
----------------------------------------------------------------------
local BRutus = BRutus
local UI     = BRutus.UI
local C      = BRutus.Colors
local L      = BRutus.L

----------------------------------------------------------------------
-- TBC RAID CD DEFINITIONS
-- iconID   = spellID whose texture is used as the column icon
-- spellIDs = all spellIDs that count as this CD (all ranks)
-- cooldown = approx seconds (for timer display, not enforcement)
-- class    = UnitClassBase / GetRaidRosterInfo fileName
----------------------------------------------------------------------
local RAID_CDS = {
    {
        key      = "rebirth",
        label    = L["Battle Rez"],
        class    = "DRUID",
        iconID   = 20484,
        cooldown = 1800,
        spellIDs = { 20484, 20748, 20747, 20742, 20739, 20737 },
    },
    {
        key      = "bloodlust",
        label    = L["Bloodlust/Hero"],
        class    = "SHAMAN",
        iconID   = 2825,
        cooldown = 600,
        spellIDs = { 2825, 32182 },
    },
    {
        key      = "innervate",
        label    = L["Innervate"],
        class    = "DRUID",
        iconID   = 29166,
        cooldown = 360,
        spellIDs = { 29166 },
    },
    {
        key      = "pi",
        label    = L["Power Infusion"],
        class    = "PRIEST",
        iconID   = 10060,
        cooldown = 180,
        spellIDs = { 10060 },
    },
    {
        key      = "md",
        label    = L["Misdirection"],
        class    = "HUNTER",
        iconID   = 34477,
        cooldown = 30,
        spellIDs = { 34477 },
    },
    {
        key      = "loh",
        label    = L["Lay on Hands"],
        class    = "PALADIN",
        iconID   = 633,
        cooldown = 3600,
        spellIDs = { 633, 2800, 10310 },
    },
    {
        key      = "di",
        label    = L["Div. Intervention"],
        class    = "PALADIN",
        iconID   = 19752,
        cooldown = 3600,
        spellIDs = { 19752 },
    },
    {
        key      = "ps",
        label    = L["Pain Suppression"],
        class    = "PRIEST",
        iconID   = 33206,
        cooldown = 180,
        spellIDs = { 33206 },
    },
    {
        key      = "sf",
        label    = L["Shadowfiend"],
        class    = "PRIEST",
        iconID   = 34433,
        cooldown = 300,
        spellIDs = { 34433 },
    },
    {
        key      = "tranquility",
        label    = L["Tranquility"],
        class    = "DRUID",
        iconID   = 740,
        cooldown = 300,
        spellIDs = { 740, 8918, 9862, 9863 },
    },
    {
        key      = "shieldwall",
        label    = L["Shield Wall"],
        class    = "WARRIOR",
        iconID   = 871,
        cooldown = 1800,
        spellIDs = { 871 },
    },
    {
        key      = "laststand",
        label    = L["Last Stand"],
        class    = "WARRIOR",
        iconID   = 12975,
        cooldown = 480,
        spellIDs = { 12975 },
    },
}

-- Reverse lookup: spellID -> cd entry
local SPELL_TO_CD = {}
for _, cd in ipairs(RAID_CDS) do
    for _, sid in ipairs(cd.spellIDs) do
        SPELL_TO_CD[sid] = cd
    end
end

----------------------------------------------------------------------
-- MODULE STATE
----------------------------------------------------------------------
local _cdState           = {}   -- [playerName][cdKey] = { usedAt, duration }
local _raidMembers       = {}   -- [name] = classFile  (e.g. "WARRIOR")
local _hudFrame          = nil
local _consPopup         = nil
local _collapsed         = false
local _lastTick          = 0
local _hudManuallyClosed  = false

----------------------------------------------------------------------
-- LAYOUT CONSTANTS
----------------------------------------------------------------------
local HUD_W      = 420
local HEADER_H   = 22
local ROW_H      = 22
local ICON_W     = 18
local LABEL_W    = 90
local FOOT_H     = 36

local CP_W         = 320   -- compact consumables panel width
local CONS_ROW_H   = 18    -- compact "missing" row height
local CONS_MAX_ROWS = 12   -- cap visible rows before the list scrolls

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function FormatTime(s)
    s = floor(s)
    if s >= 60 then
        return format("%dm%ds", floor(s / 60), s % 60)
    end
    return format("%ds", s)
end

local function IsLeaderOrAssist()
    if not IsInRaid() then return false end
    local myName = UnitName("player")
    for i = 1, GetNumGroupMembers() do
        local rName, rank = GetRaidRosterInfo(i)
        if rName == myName then
            return rank >= 1
        end
    end
    return false
end

local function ScanRaidRoster()
    wipe(_raidMembers)
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
        if name then
            _raidMembers[name] = classFile
        end
    end
end

----------------------------------------------------------------------
-- COMBAT LOG — detect CD usage for all raid members
----------------------------------------------------------------------
local _clFrame = CreateFrame("Frame")
_clFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
_clFrame:SetScript("OnEvent", function()
    local _, event, _, _, srcName, _, _, _, _, _, _, spellID =
        CombatLogGetCurrentEventInfo()
    if event ~= "SPELL_CAST_SUCCESS" or not srcName then return end
    local cd = SPELL_TO_CD[spellID]
    if not cd then return end
    if not _cdState[srcName] then _cdState[srcName] = {} end
    _cdState[srcName][cd.key] = { usedAt = GetTime(), duration = cd.cooldown }
end)

----------------------------------------------------------------------
-- HUD ROW UPDATE (called from ticker)
----------------------------------------------------------------------
local function UpdateRow(row)
    if not row or not row:IsShown() then return end
    local parts = {}
    local now = GetTime()
    for _, p in ipairs(row.players) do
        local st = _cdState[p.name] and _cdState[p.name][row.cdKey]
        local remaining = st and (st.duration - (now - st.usedAt)) or 0
        if remaining > 0 then
            parts[#parts + 1] = "|cff999999" .. p.shortName
                              .. " " .. FormatTime(remaining) .. "|r"
        else
            parts[#parts + 1] = "|cff" .. p.colorHex .. p.shortName .. "|r"
        end
    end
    row.playerText:SetText(table.concat(parts, "  "))
end

----------------------------------------------------------------------
-- BUILD / REBUILD HUD ROWS
----------------------------------------------------------------------
local function BuildHUDRows(f)
    for _, r in ipairs(f.rows or {}) do r:Hide() end
    f.rows = {}

    ScanRaidRoster()

    local yOff = 2
    for _, cd in ipairs(RAID_CDS) do
        local players = {}
        for name, classFile in pairs(_raidMembers) do
            if classFile == cd.class then
                local shortName = name:sub(1, 12)
                local hex = BRutus:GetClassColorHex(classFile)
                table.insert(players, { name = name, shortName = shortName, colorHex = hex })
            end
        end

        if #players > 0 then
            table.sort(players, function(a, b) return a.name < b.name end)

            local row = CreateFrame("Frame", nil, f.bodyFrame)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT",  4, -yOff)
            row:SetPoint("TOPRIGHT", -4, -yOff)
            row.cdKey   = cd.key
            row.players = players

            -- Alternating background
            local bgCol = (#f.rows % 2 == 0) and C.row1 or C.row2
            local bgTex = row:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            bgTex:SetTexture("Interface\\Buttons\\WHITE8x8")
            bgTex:SetVertexColor(bgCol.r, bgCol.g, bgCol.b, bgCol.a)

            -- Spell icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_W, ICON_W)
            icon:SetPoint("LEFT", 2, 0)
            local spellTex = GetSpellTexture(cd.iconID)
            icon:SetTexture(spellTex or "Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- CD label
            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            lbl:SetPoint("LEFT", ICON_W + 4, 0)
            lbl:SetWidth(LABEL_W)
            lbl:SetJustifyH("LEFT")
            lbl:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            lbl:SetText(cd.label)

            -- Player name list (colored, updated by ticker)
            local pText = row:CreateFontString(nil, "OVERLAY")
            pText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            pText:SetPoint("LEFT", ICON_W + LABEL_W + 6, 0)
            pText:SetPoint("RIGHT", -2, 0)
            pText:SetJustifyH("LEFT")
            row.playerText = pText

            -- Tooltip: show full names + CD status
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(cd.label, C.gold.r, C.gold.g, C.gold.b)
                local now2 = GetTime()
                for _, p in ipairs(self.players) do
                    local st = _cdState[p.name] and _cdState[p.name][self.cdKey]
                    local rem = st and (st.duration - (now2 - st.usedAt)) or 0
                    local status
                    if rem > 0 then
                        status = "|cffff5555" .. FormatTime(rem) .. "|r"
                    else
                        status = "|cff55ff55" .. L["Ready"] .. "|r"
                    end
                    GameTooltip:AddLine(p.name .. ": " .. status, 1, 1, 1, false)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            UpdateRow(row)
            row:Show()
            table.insert(f.rows, row)
            yOff = yOff + ROW_H
        end
    end

    -- Resize body + main frame
    f.bodyFrame:SetHeight(math.max(1, yOff + 2))
    local totalH = HEADER_H + yOff + 2 + FOOT_H
    f:SetHeight(totalH)
end

----------------------------------------------------------------------
-- CREATE RAID HUD
----------------------------------------------------------------------
function BRutus:CreateRaidHUD()
    if _hudFrame then return end

    local f = CreateFrame("Frame", "BRutusRaidHUD", UIParent, "BackdropTemplate")
    f:SetWidth(HUD_W)
    f:SetHeight(200)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 0.92)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(50)
    f:SetClampedToScreen(true)

    -- Restore saved position
    local pos = BRutus.db.raidHUDPos
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -250, -180)
    end

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        BRutus.db.raidHUDPos = {
            point = point, relPoint = relPoint,
            x = floor(x), y = floor(y),
        }
    end)

    ----------------------------------------------------------------
    -- Header bar (draggable)
    ----------------------------------------------------------------
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1)

    local titleText = header:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    titleText:SetPoint("LEFT", 8, 0)
    titleText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleText:SetText(L["Guild OS — Raid CDs"])

    ----------------------------------------------------------------
    -- Collapse button  (— / +)
    ----------------------------------------------------------------
    local colBtn = CreateFrame("Button", nil, header)
    colBtn:SetSize(18, 18)
    colBtn:SetPoint("RIGHT", -22, 0)

    local colBtnText = colBtn:CreateFontString(nil, "OVERLAY")
    colBtnText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    colBtnText:SetAllPoints()
    colBtnText:SetJustifyH("CENTER")
    colBtnText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    colBtnText:SetText("—")

    colBtn:SetScript("OnClick", function()
        _collapsed = not _collapsed
        f.bodyFrame:SetShown(not _collapsed)
        f.consBtn:SetShown(not _collapsed)
        colBtnText:SetText(_collapsed and "+" or "—")
        if _collapsed then
            f:SetHeight(HEADER_H + 2)
        else
            BuildHUDRows(f)
        end
    end)

    ----------------------------------------------------------------
    -- Close button
    ----------------------------------------------------------------
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -2, 0)

    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTxt:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    closeTxt:SetAllPoints()
    closeTxt:SetJustifyH("CENTER")
    closeTxt:SetTextColor(0.85, 0.20, 0.20)
    closeTxt:SetText("×")

    closeBtn:SetScript("OnClick", function()
        -- Persist the dismissal so it survives zoning/reload within the raid
        -- session (it is cleared again when the player leaves the raid).
        _hudManuallyClosed = true
        if BRutus.db and BRutus.db.settings then
            BRutus.db.settings.raidHUDDismissed = true
        end
        f:Hide()
    end)

    ----------------------------------------------------------------
    -- Body frame (holds CD rows)
    ----------------------------------------------------------------
    f.bodyFrame = CreateFrame("Frame", nil, f)
    f.bodyFrame:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  0, 0)
    f.bodyFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)

    ----------------------------------------------------------------
    -- Check Consumables button
    ----------------------------------------------------------------
    f.consBtn = UI:CreateButton(f, L["Check Consumables"], 200, 24)
    f.consBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
    f.consBtn:SetScript("OnClick", function()
        BRutus:ShowConsumablePopup()
    end)

    ----------------------------------------------------------------
    -- Per-0.5s ticker: update cooldown countdown text
    ----------------------------------------------------------------
    f.rows = {}
    f:SetScript("OnUpdate", function(self, elapsed)
        _lastTick = _lastTick + elapsed
        if _lastTick < 0.5 then return end
        _lastTick = 0
        for _, row in ipairs(self.rows) do
            UpdateRow(row)
        end
    end)

    _hudFrame = f
    f:Hide()

    BuildHUDRows(f)
end

----------------------------------------------------------------------
-- VISIBILITY: show when in raid as leader/assist, hide otherwise
----------------------------------------------------------------------
function BRutus:UpdateRaidHUDVisibility()
    if not _hudFrame then return end
    local moduleEnabled = not BRutus.db or not BRutus.db.settings
        or not BRutus.db.settings.modules
        or BRutus.db.settings.modules.raidHUD ~= false
    local shouldShow = moduleEnabled and IsInRaid() and IsLeaderOrAssist()
    if shouldShow then
        if not _hudFrame:IsShown() and not _hudManuallyClosed then
            _hudFrame:Show()
        end
        if not _collapsed then
            BuildHUDRows(_hudFrame)
        end
    else
        -- Left the raid: clear the dismissal so the HUD reappears next raid.
        _hudManuallyClosed = false
        if BRutus.db and BRutus.db.settings then
            BRutus.db.settings.raidHUDDismissed = false
        end
        _hudFrame:Hide()
        if _consPopup then _consPopup:Hide() end
    end
end

----------------------------------------------------------------------
-- EVENT HANDLING — auto show/hide on roster changes
----------------------------------------------------------------------
local _evtFrame = CreateFrame("Frame")
_evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_evtFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
_evtFrame:RegisterEvent("RAID_ROSTER_UPDATE")

_evtFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Do NOT reset the dismissal here: zoning inside a raid (wipes,
        -- instance transitions) fires PEW and was re-opening a window the
        -- user had closed. Restore the persisted state once db is ready.
        C_Timer.After(2, function()
            if BRutus.db then
                if BRutus.db.settings then
                    _hudManuallyClosed = BRutus.db.settings.raidHUDDismissed and true or false
                end
                BRutus:CreateRaidHUD()
                BRutus:UpdateRaidHUDVisibility()
            end
        end)
    else
        BRutus:UpdateRaidHUDVisibility()
    end
end)

----------------------------------------------------------------------
-- CONSUMABLE PANEL — compact "problems only" floating frame
----------------------------------------------------------------------
local function BuildConsPopup(f)
    local CC = BRutus.ConsumableChecker
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

    -- Collect only players missing something; tally ready vs total
    local problems, total, ready = {}, 0, 0
    if results then
        for _, p in pairs(results) do
            total = total + 1
            if p.missing and #p.missing > 0 then
                table.insert(problems, p)
            else
                ready = ready + 1
            end
        end
    end
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
            local cr, cg, cbv = BRutus:GetClassColor(p.class)
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

function BRutus:ShowConsumablePopup()
    local CC = BRutus.ConsumableChecker
    if CC then CC:CheckRaid() end

    if _consPopup then
        _consPopup:Show()
        BuildConsPopup(_consPopup)
        return
    end

    local WHITE = "Interface\\Buttons\\WHITE8x8"
    local f = CreateFrame("Frame", "BRutusConsPopup", UIParent, "BackdropTemplate")
    f:SetSize(CP_W, 160)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 0.97)
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
        if BRutus.ConsumableChecker then BRutus.ConsumableChecker:CheckRaid() end
        BuildConsPopup(f)
    end)

    local repBtn = UI:CreateButton(f, L["Announce"], 78, 20)
    repBtn:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)
    repBtn:SetScript("OnClick", function()
        if BRutus.ConsumableChecker then BRutus.ConsumableChecker:ReportToChat("RAID") end
    end)

    -- Centered message for "all prepared" / "no data"
    f.emptyText = UI:CreateText(f, "", 12, C.silver.r, C.silver.g, C.silver.b)
    f.emptyText:SetPoint("TOP", 0, -(HEADER_H + 36))

    -- Scrollable problem list
    local scroll = CreateFrame("ScrollFrame", "BRutusConsPopupScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -(HEADER_H + 28))
    scroll:SetPoint("BOTTOMRIGHT", -22, 8)
    UI:SkinScrollBar(scroll, "BRutusConsPopupScroll")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CP_W - 30, 1)
    scroll:SetScrollChild(content)

    f.content = content
    f.rowPool = {}

    UI:StylePopup(f)
    _consPopup = f
    BuildConsPopup(f)
end
