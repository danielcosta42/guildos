----------------------------------------------------------------------
-- Guild OS - Raid Tools Panel
-- "Raid Tools" tab with sub-tabs: Composition (class breakdown + buff
-- coverage) and Cooldowns (key raid CD coverage). Data comes from
-- BRutus.RaidTools (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local SUBTABS = {
    { key = "comp", label = L["Composition"] },
    { key = "cds",  label = L["Cooldowns"] },
}

local ROW_H = 24
local ICON_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t"
local ICON_NONE = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:14:14|t"

local function MakeScrollList(panel, name, topInset)
    local scroll = CreateFrame("ScrollFrame", name, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -(topInset or 0))
    scroll:SetPoint("BOTTOMRIGHT", -10, 0)
    UI:SkinScrollBar(scroll, name)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

local function MakeRow(content, yOff, index)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetSize(content:GetWidth() - 4, ROW_H)
    row:SetPoint("TOPLEFT", 0, -yOff)
    row:SetBackdrop({ bgFile = WHITE })
    local alt = (index % 2 == 0) and C.row1 or C.row2
    row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
    return row
end

local function SectionHeader(content, text, yOff)
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(content:GetWidth() - 4, 22)
    f:SetPoint("TOPLEFT", 0, -yOff)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(WHITE)
    bg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 0.7)
    local lbl = UI:CreateHeaderText(f, text, 10)
    lbl:SetPoint("LEFT", 8, 0)
    return f
end

local function ClearContent(content)
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
end

-- Localized class name from the WoW global (LOCALIZED_CLASS_NAMES_MALE),
-- falling back to the class token if unavailable.
local function ClassName(classFile)
    local t = LOCALIZED_CLASS_NAMES_MALE
    return (t and t[classFile]) or classFile
end

local function ProvidersText(providers)
    local parts = {}
    for _, cf in ipairs(providers) do
        local cc = BRutus.ClassColors[cf] or C.silver
        parts[#parts + 1] = BRutus:ColorText(ClassName(cf), cc.r, cc.g, cc.b)
    end
    return table.concat(parts, ", ")
end

----------------------------------------------------------------------
-- COMPOSITION sub-panel
----------------------------------------------------------------------
local function BuildCompSub(panel)
    local summary = UI:CreateText(panel, "", 11, C.gold.r, C.gold.g, C.gold.b)
    summary:SetPoint("TOPLEFT", 4, -4)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -24)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSRaidCompScroll")

    return function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local RT = BRutus.RaidTools
        local list, label = RT:GetSource()
        local counts = RT:GetClassCounts(list)
        summary:SetText(string.format(L["%s  \226\128\148  %d players"], label, #list))

        local yOff = 0
        SectionHeader(content, L["CLASS BREAKDOWN"], yOff)
        yOff = yOff + 24

        for _, classFile in ipairs(RT.CLASS_ORDER) do
            local c = counts[classFile] or 0
            if c > 0 then
                local row = MakeRow(content, yOff, yOff / (ROW_H + 2))
                local cc = BRutus.ClassColors[classFile] or C.silver
                local nameFS = UI:CreateText(row, ClassName(classFile), 11, cc.r, cc.g, cc.b)
                nameFS:SetPoint("LEFT", 8, 0)
                local cntFS = UI:CreateText(row, tostring(c), 11, C.white.r, C.white.g, C.white.b)
                cntFS:SetPoint("LEFT", 150, 0)
                yOff = yOff + ROW_H + 2
            end
        end

        yOff = yOff + 8
        SectionHeader(content, L["BUFF COVERAGE"], yOff)
        yOff = yOff + 24

        local cov = RT:ResolveCoverage(RT.BUFFS, counts)
        for idx, b in ipairs(cov) do
            local row = MakeRow(content, yOff, idx)
            local icon = UI:CreateText(row, b.covered and ICON_DONE or ICON_NONE, 11, 1, 1, 1)
            icon:SetPoint("LEFT", 8, 0)
            local nameFS = UI:CreateText(row, b.name, 11,
                b.covered and C.text.r or C.textDim.r, b.covered and C.text.g or C.textDim.g, b.covered and C.text.b or C.textDim.b)
            nameFS:SetPoint("LEFT", 34, 0)
            if b.covered then
                local prov = UI:CreateText(row, ProvidersText(b.providers), 10, C.silver.r, C.silver.g, C.silver.b)
                prov:SetPoint("LEFT", 220, 0)
            end
            yOff = yOff + ROW_H + 2
        end

        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- COOLDOWNS sub-panel
----------------------------------------------------------------------
local function BuildCdSub(panel)
    local summary = UI:CreateText(panel, "", 11, C.gold.r, C.gold.g, C.gold.b)
    summary:SetPoint("TOPLEFT", 4, -4)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -24)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSRaidCdScroll")

    return function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local RT = BRutus.RaidTools
        local list, label = RT:GetSource()
        local counts = RT:GetClassCounts(list)
        summary:SetText(string.format(L["%s  \226\128\148  %d players"], label, #list))

        local yOff = 0
        local cov = RT:ResolveCoverage(RT.COOLDOWNS, counts)
        for idx, cd in ipairs(cov) do
            local row = MakeRow(content, yOff, idx)
            local icon = UI:CreateText(row, cd.covered and ICON_DONE or ICON_NONE, 11, 1, 1, 1)
            icon:SetPoint("LEFT", 8, 0)
            local nameFS = UI:CreateText(row, cd.name, 11,
                cd.covered and C.text.r or C.textDim.r, cd.covered and C.text.g or C.textDim.g, cd.covered and C.text.b or C.textDim.b)
            nameFS:SetPoint("LEFT", 34, 0)
            if cd.covered then
                local prov = UI:CreateText(row, ProvidersText(cd.providers), 10, C.silver.r, C.silver.g, C.silver.b)
                prov:SetPoint("LEFT", 220, 0)
            else
                local miss = UI:CreateText(row, L["missing"], 10, C.red.r, C.red.g, C.red.b)
                miss:SetPoint("LEFT", 220, 0)
            end
            yOff = yOff + ROW_H + 2
        end

        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- Panel assembly
----------------------------------------------------------------------
function BRutus:CreateRaidToolsPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "comp"

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetPoint("TOPRIGHT", -10, -8)
    bar:SetHeight(26)

    local subTabBtns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then info.refresh() end
    end
    parent.RefreshActive = function()
        local info = parent.subPanels[parent.activeSub]
        if info and info.refresh then info.refresh() end
    end

    local x = 0
    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 130)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + 134
    end

    -- Manual refresh (group changes don't auto-refresh the panel)
    local refreshBtn = UI:CreateButton(bar, L["Refresh"], 90, 22)
    refreshBtn:SetPoint("RIGHT", 0, 0)
    refreshBtn:SetScript("OnClick", function() parent.RefreshActive() end)

    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", 12, -42)
        p:SetPoint("BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end

    local builders = { comp = BuildCompSub, cds = BuildCdSub }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "comp")
    end)
end
