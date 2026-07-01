----------------------------------------------------------------------
-- Guild OS - Points Window (DKP / EPGP / Loot Council)
-- Standalone window: standings table + transaction log, with officer
-- controls for award/charge/raid-award/decay/mode. Visual layer only —
-- all logic lives in BRutus.Points (Rule 3 / Rule 9).
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local MODE_LABEL = {
    dkp     = "DKP",
    epgp    = "EPGP",
    council = "Loot Council",
}
local MODE_CYCLE = { "dkp", "epgp", "council" }

local function makeInput(parent, w, numeric, placeholder)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.05, 0.05, 0.066, 1)
    b:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    b:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    b:SetTextColor(C.white.r, C.white.g, C.white.b)
    b:SetTextInsets(6, 6, 0, 0)
    b:SetAutoFocus(false)
    if numeric then b:SetNumeric(true); b:SetMaxLetters(6) end
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if placeholder then
        local ph = b:CreateFontString(nil, "OVERLAY")
        ph:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        ph:SetPoint("LEFT", 6, 0)
        ph:SetTextColor(0.4, 0.4, 0.4)
        ph:SetText(placeholder)
        b:SetScript("OnTextChanged", function(self)
            if self:GetText() ~= "" then ph:Hide() else ph:Show() end
        end)
    end
    return b
end

function BRutus:ShowPointsFrame()
    if self.pointsFrame then
        self.pointsFrame:Show()
        if BRutus.Points then BRutus.Points:Refresh() end
        return
    end

    local f = CreateFrame("Frame", "GuildOSPointsFrame", UIParent, "BackdropTemplate")
    f:SetSize(760, 540)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    self.pointsFrame = f

    local title = UI:CreateTitle(f, L["Guild Points"], 18)
    title:SetPoint("TOPLEFT", 16, -12)

    local modeText = UI:CreateText(f, "", 12, C.accent.r, C.accent.g, C.accent.b)
    modeText:SetPoint("LEFT", title, "RIGHT", 12, 0)

    local summary = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
    summary:SetPoint("TOPLEFT", 16, -34)

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    local isOfficer = BRutus:IsOfficer()
    local listTop = -52

    if isOfficer then
        local nameInput = makeInput(f, 150, false, L["Player"])
        nameInput:SetPoint("TOPLEFT", 16, -50)
        local amtInput = makeInput(f, 60, true, "0")
        amtInput:SetPoint("LEFT", nameInput, "RIGHT", 6, 0)
        local reasonInput = makeInput(f, 200, false, L["Reason"])
        reasonInput:SetPoint("LEFT", amtInput, "RIGHT", 6, 0)

        local awardBtn = UI:CreateButton(f, L["Award"], 64, 22)
        awardBtn:SetPoint("LEFT", reasonInput, "RIGHT", 8, 0)
        awardBtn:SetBaseColor(C.online.r * 0.30, C.online.g * 0.30, C.online.b * 0.30, 0.9)
        local chargeBtn = UI:CreateButton(f, L["Charge"], 64, 22)
        chargeBtn:SetPoint("LEFT", awardBtn, "RIGHT", 6, 0)
        chargeBtn:SetBaseColor(C.red.r * 0.30, C.red.g * 0.30, C.red.b * 0.30, 0.9)

        local function doAdjust(sign)
            local nm = strtrim(nameInput:GetText() or "")
            local amt = tonumber(amtInput:GetText())
            if nm == "" or not amt or amt == 0 then return end
            local key = BRutus:GetPlayerKey(nm, GetRealmName())
            BRutus.Points:Adjust(key, sign * math.abs(amt), strtrim(reasonInput:GetText() or ""),
                sign > 0 and "award" or "spend")
            amtInput:SetText(""); reasonInput:SetText(""); nameInput:ClearFocus()
        end
        awardBtn:SetScript("OnClick", function() doAdjust(1) end)
        chargeBtn:SetScript("OnClick", function() doAdjust(-1) end)

        -- Second control row
        local raidBtn = UI:CreateButton(f, L["Award Raid"], 100, 20)
        raidBtn:SetPoint("TOPLEFT", 16, -78)
        raidBtn:SetScript("OnClick", function()
            local amt = BRutus.Points:GetDB().config.bossAward or 0
            local n = BRutus.Points:AwardRaidGroup(amt, L["Manual raid award"])
            if n and n > 0 then
                BRutus:Print(string.format(L["Awarded %d points to %d raiders."], amt, n))
            end
        end)

        local decayBtn = UI:CreateButton(f, L["Apply Decay"], 100, 20)
        decayBtn:SetPoint("LEFT", raidBtn, "RIGHT", 6, 0)
        decayBtn:SetScript("OnClick", function()
            local n = BRutus.Points:ApplyDecay()
            BRutus:Print(string.format(L["Decay applied to %d player(s)."], n or 0))
        end)

        local modeBtn = UI:CreateButton(f, L["Mode"], 110, 20)
        modeBtn:SetPoint("LEFT", decayBtn, "RIGHT", 6, 0)
        modeBtn:SetScript("OnClick", function()
            local cur = BRutus.Points:GetMode()
            local idx = 1
            for i, m in ipairs(MODE_CYCLE) do if m == cur then idx = i end end
            local nxt = MODE_CYCLE[(idx % #MODE_CYCLE) + 1]
            BRutus.Points:SetMode(nxt)
        end)

        local syncBtn = UI:CreateButton(f, L["Sync"], 70, 20)
        syncBtn:SetPoint("LEFT", modeBtn, "RIGHT", 6, 0)
        syncBtn:SetScript("OnClick", function()
            BRutus.Points:BroadcastSnapshot()
            BRutus:Print(L["Points snapshot sent to guild."])
        end)

        listTop = -106
    end

    -- Column headers
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 16, listTop)
    header:SetPoint("TOPRIGHT", -16, listTop)
    header:SetHeight(16)
    local function hcol(txt, x, parentFrame)
        local fs = UI:CreateHeaderText(parentFrame or header, txt, 9)
        fs:SetPoint("LEFT", x, 0)
        return fs
    end
    hcol(L["MEMBER"], 4)
    hcol(L["CURRENT"], 250)
    hcol(L["EARNED"], 330)
    hcol(L["SPENT"], 410)
    local logHdr = UI:CreateHeaderText(f, L["HISTORY"], 9)
    logHdr:SetPoint("TOPLEFT", 500, listTop)

    -- Standings list (left) and history list (right)
    local standHolder = CreateFrame("Frame", nil, f)
    standHolder:SetPoint("TOPLEFT", 12, listTop - 18)
    standHolder:SetPoint("BOTTOMLEFT", 12, 14)
    standHolder:SetWidth(478)
    local standScroll, standChild = UI:CreateScrollFrame(standHolder, "GuildOSPointsStandScroll")
    standScroll:SetAllPoints()

    local logHolder = CreateFrame("Frame", nil, f)
    logHolder:SetPoint("TOPLEFT", 498, listTop - 18)
    logHolder:SetPoint("BOTTOMRIGHT", -12, 14)
    local logScroll, logChild = UI:CreateScrollFrame(logHolder, "GuildOSPointsLogScroll")
    logScroll:SetAllPoints()

    local function clear(child)
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
    end

    local function refresh()
        if not f:IsShown() then return end
        local mode = BRutus.Points:GetMode()
        modeText:SetText(MODE_LABEL[mode] or mode)
        local cfg = BRutus.Points:GetDB().config
        summary:SetText(string.format(L["Boss award: %d  |  Decay: %d%%  |  Auto-award: %s"],
            cfg.bossAward or 0, cfg.decayPct or 0, cfg.autoAward and L["on"] or L["off"]))

        -- Standings
        standChild:SetWidth(standHolder:GetWidth() - 12)
        clear(standChild)
        local list = BRutus.Points:GetStandings()
        local y = 0
        for idx, s in ipairs(list) do
            local row = CreateFrame("Frame", nil, standChild)
            row:SetSize(standChild:GetWidth(), 22)
            row:SetPoint("TOPLEFT", 0, -y)
            local cr, cg, cb = BRutus:GetClassColor(s.class)
            local nameFS = UI:CreateText(row, idx .. ". " .. s.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 4, 0)
            local curFS = UI:CreateText(row, tostring(s.current), 11, C.gold.r, C.gold.g, C.gold.b)
            curFS:SetPoint("LEFT", 250, 0)
            local earnFS = UI:CreateText(row, tostring(s.earned), 10, C.green.r, C.green.g, C.green.b)
            earnFS:SetPoint("LEFT", 330, 0)
            local spentFS = UI:CreateText(row, tostring(s.spent), 10, C.silver.r, C.silver.g, C.silver.b)
            spentFS:SetPoint("LEFT", 410, 0)
            y = y + 23
        end
        if #list == 0 then
            local empty = UI:CreateText(standChild, L["No points recorded yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        standChild:SetHeight(math.max(1, y))

        -- History
        logChild:SetWidth(logHolder:GetWidth() - 12)
        clear(logChild)
        local log = BRutus.Points:GetLog(60)
        local ly = 0
        for _, e in ipairs(log) do
            local sign = (e.delta or 0) >= 0
            local col = sign and C.green or C.red
            local prefix = sign and "+" or ""
            local amtStr = BRutus:ColorText(prefix .. (e.delta or 0), col.r, col.g, col.b)
            local txt = amtStr .. " " .. (e.name or "?")
            local line = UI:CreateText(logChild, txt, 10, C.text.r, C.text.g, C.text.b)
            line:SetPoint("TOPLEFT", 4, -ly)
            line:SetWidth(logChild:GetWidth() - 8)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(false)
            if e.reason and e.reason ~= "" then
                ly = ly + 14
                local sub = UI:CreateText(logChild, e.reason, 8, C.textDim.r, C.textDim.g, C.textDim.b)
                sub:SetPoint("TOPLEFT", 12, -ly)
                sub:SetWidth(logChild:GetWidth() - 16)
                sub:SetJustifyH("LEFT")
                sub:SetWordWrap(false)
            end
            ly = ly + 16
        end
        if #log == 0 then
            local empty = UI:CreateText(logChild, L["No history."], 10, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        logChild:SetHeight(math.max(1, ly))
    end

    BRutus.Points.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    refresh()
end
