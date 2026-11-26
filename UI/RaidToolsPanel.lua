----------------------------------------------------------------------
-- Guild OS - Raid Tools Panel
-- "Raid Tools" tab with sub-tabs: Composition (class breakdown + buff
-- coverage) and Cooldowns (key raid CD coverage). Data comes from
-- GuildOS.RaidTools (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local SUBTABS = {
    { key = "comp", label = L["Composition"] },
    { key = "cds",  label = L["Cooldowns"] },
}

local ROW_H = 28
local ICON_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t"
local ICON_NONE = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:14:14|t"
-- The screen's margins (#371): flush with the sub-tab bar's left edge, GAP under it, the content ending
-- GAP short of the right edge. A scroll child stops UI.SCROLL_GUTTER short of its frame, so a scroll
-- frame's right edge sits SCROLL_R from the panel's.
local GAP = UI.GAP
local SCROLL_R = UI.SCROLL_GUTTER - UI.GAP

-- The shared scroll frame (#371), anchored here: its child keeps the frame's width less the gutter.
local function MakeScrollList(panel, name, topInset)
    local scroll, content = UI:CreateScrollFrame(panel, name)
    scroll:SetPoint("TOPLEFT", 0, -(topInset or 0))
    scroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
    UI:BindScrollChildWidth(scroll, content)
    return scroll, content
end

-- A row of a table on the dark card (the mockup's raides-ferramentas), between `x0` and `x1` of the
-- content (x1 nil: its right edge), with the wood's 1px line under it.
local function MakeRow(content, yOff, x0, x1)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", x0 or 0, -yOff)
    if x1 then row:SetWidth(x1 - (x0 or 0)) else row:SetPoint("TOPRIGHT", 0, -yOff) end
    local rule = row:CreateTexture(nil, "BACKGROUND")
    rule:SetTexture(WHITE)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
    rule:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)
    return row
end

-- A table's heading: its name in the soft ink, bold, and under it the column titles on the shared header
-- (Cinzel in gold, the metal's rule). `cols` = { { text, x, right } }. Returns the y under it.
local function TableHead(content, title, cols, yOff, x0, x1)
    local t = UI:CreateText(content, title, 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    GuildOS:ApplyFont(t, 12, "button")
    t:SetPoint("TOPLEFT", x0 or 0, -yOff)
    local head = UI:CreateTableHeader(content, 20)
    head:SetPoint("TOPLEFT", x0 or 0, -yOff - 18)
    if x1 then head:SetWidth(x1 - (x0 or 0)) else head:SetPoint("TOPRIGHT", 0, -yOff - 18) end
    for _, c in ipairs(cols) do
        local h = UI:CreateHeaderText(head, c[1], 10)
        if c[3] then h:SetPoint("RIGHT", head, "LEFT", c[2], 0) else h:SetPoint("LEFT", c[2], 0) end
    end
    return yOff + 18 + 20
end

-- What a refresh drew goes before the next one: the rows, and the titles drawn straight on the content.
local function ClearContent(content)
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
    for _, region in pairs({ content:GetRegions() }) do region:Hide() end
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
        local cc = GuildOS.ClassColors[cf] or C.silver
        parts[#parts + 1] = GuildOS:ColorText(ClassName(cf), cc.r, cc.g, cc.b)
    end
    return table.concat(parts, ", ")
end

----------------------------------------------------------------------
-- COMPOSITION sub-panel
----------------------------------------------------------------------
local function BuildCompSub(panel)
    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, 0)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSRaidCompScroll")

    return function()
        ClearContent(content)

        local RT = GuildOS.RaidTools
        local list, label = RT:GetSource()
        local counts = RT:GetClassCounts(list)
        panel.summary = string.format(L["%s  \226\128\148  %d players"], label, #list)

        -- The classes on the left and the buffs they cover on the right; one under the other when narrow.
        local W = content:GetWidth()
        if not W or W < 100 then W = 600 end
        local twoCols = W >= 520
        local colW = twoCols and math.floor((W - 16) / 2) or W
        local x2 = twoCols and (colW + 16) or 0

        local yOff = TableHead(content, L["Classes"], { { L["Class"], 6 }, { L["Count"], colW - 6, true } }, 0, 0, colW)
        for _, classFile in ipairs(RT.CLASS_ORDER) do
            local c = counts[classFile] or 0
            if c > 0 then
                local row = MakeRow(content, yOff, 0, colW)
                local cc = GuildOS.ClassColors[classFile] or C.silver
                local nameFS = UI:CreateText(row, ClassName(classFile), 12, cc.r, cc.g, cc.b)
                nameFS:SetPoint("LEFT", 6, 0)
                local cntFS = UI:CreateText(row, tostring(c), 12, C.text.r, C.text.g, C.text.b)
                cntFS:SetPoint("RIGHT", -6, 0)
                yOff = yOff + ROW_H
            end
        end
        local leftH = yOff

        yOff = twoCols and 0 or (yOff + 16)
        yOff = TableHead(content, L["Buff coverage"], { { L["Buff"], 6 }, { L["Who"], math.floor((W - x2) * 0.45) } }, yOff, x2, nil)
        local cov = RT:ResolveCoverage(RT.BUFFS, counts)
        for _, b in ipairs(cov) do
            local row = MakeRow(content, yOff, x2, nil)
            local icon = UI:CreateText(row, b.covered and ICON_DONE or ICON_NONE, 11, C.text.r, C.text.g, C.text.b)
            icon:SetPoint("LEFT", 4, 0)
            local nameFS = UI:CreateText(row, b.name, 12,
                b.covered and C.text.r or C.label.r, b.covered and C.text.g or C.label.g, b.covered and C.text.b or C.label.b)
            nameFS:SetPoint("LEFT", 24, 0)
            if b.covered then
                local prov = UI:CreateText(row, ProvidersText(b.providers), 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                prov:SetPoint("LEFT", math.floor((W - x2) * 0.45), 0)
            end
            yOff = yOff + ROW_H
        end

        content:SetHeight(math.max(1, math.max(yOff, leftH)))
    end
end

----------------------------------------------------------------------
-- COOLDOWNS sub-panel
----------------------------------------------------------------------
local function BuildCdSub(panel)
    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, 0)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSRaidCdScroll")

    return function()
        ClearContent(content)

        local RT = GuildOS.RaidTools
        local list, label = RT:GetSource()
        local counts = RT:GetClassCounts(list)
        panel.summary = string.format(L["%s  \226\128\148  %d players"], label, #list)

        local yOff = TableHead(content, L["Cooldowns"], { { L["Cooldown"], 6 }, { L["Who"], 260 } }, 0)
        local cov = RT:ResolveCoverage(RT.COOLDOWNS, counts)
        for _, cd in ipairs(cov) do
            local row = MakeRow(content, yOff)
            local icon = UI:CreateText(row, cd.covered and ICON_DONE or ICON_NONE, 11, C.text.r, C.text.g, C.text.b)
            icon:SetPoint("LEFT", 4, 0)
            local nameFS = UI:CreateText(row, cd.name, 12,
                cd.covered and C.text.r or C.label.r, cd.covered and C.text.g or C.label.g, cd.covered and C.text.b or C.label.b)
            nameFS:SetPoint("LEFT", 24, 0)
            if cd.covered then
                local prov = UI:CreateText(row, ProvidersText(cd.providers), 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                prov:SetPoint("LEFT", 260, 0)
            else
                local miss = UI:CreateBadge(row, L["missing"], C.danger)
                miss:SetPoint("LEFT", 260, 0)
            end
            yOff = yOff + ROW_H
        end

        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- Panel assembly
----------------------------------------------------------------------
function GuildOS:CreateRaidToolsPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "comp"

    -- One dark card on the wood, GAP under the room's entries (the mockup's "Ferramentas de raide"): its
    -- title with whose raid it reads, the sub-tabs as pills, Refresh under them.
    local PAD = type(UI.CARD_PAD) == "number" and UI.CARD_PAD or 14
    local CARD_TOP = type(UI.CARD_TOP) == "number" and UI.CARD_TOP or 36
    local card = UI:CreateCard(parent, L["Raid Tools"], { dark = true })
    card:SetPoint("TOPLEFT", 0, -GAP)
    card:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    parent.card = card
    card.title:ClearAllPoints()
    card.title:SetPoint("TOPLEFT", PAD, -12)
    local summary = UI:CreateText(card, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    GuildOS:ApplyFont(summary, 12, "button")
    summary:SetPoint("LEFT", card.title, "RIGHT", 8, 0)
    parent.summary = summary
    local bar = CreateFrame("Frame", nil, card)
    bar:SetPoint("TOPLEFT", PAD, -CARD_TOP + 6)
    bar:SetPoint("TOPRIGHT", -PAD, -CARD_TOP + 6)
    bar:SetHeight(22)

    local subTabBtns = {}
    local function refreshSub(info)
        if info and info.refresh then
            GuildOS:SafeCall(info.refresh)
            summary:SetText(info.panel.summary and ("\194\183  " .. info.panel.summary) or "")
        end
    end
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do UI:SetSelected(btn, k == key) end
        refreshSub(parent.subPanels[key])
    end
    parent.SelectSub = selectSub
    parent.RefreshActive = function()
        refreshSub(parent.subPanels[parent.activeSub])
    end

    local x = 0
    for _, t in ipairs(SUBTABS) do
        local btn = UI:SetButtonVariant(UI:CreateButton(bar, t.label, 40, 22), "chip")
        btn:SetWidth(math.ceil(btn.label:GetStringWidth() or 40) + 22)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + btn:GetWidth() + 6  -- a pill its label grew pushes the next one (issue #28)
    end

    -- Manual refresh (group changes don't auto-refresh the panel)
    local refreshBtn = UI:CreateButton(card, L["Refresh"], 70, 22)
    refreshBtn:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    refreshBtn:SetScript("OnClick", function() parent.RefreshActive() end)

    -- A sub-tab's content: inside the card, under Refresh.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, card)
        p:SetPoint("TOPLEFT", PAD, -(CARD_TOP + 6 + 22 + 8 + 22 + 10))
        p:SetPoint("BOTTOMRIGHT", -PAD + GAP, 10)
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
