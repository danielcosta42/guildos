----------------------------------------------------------------------
-- Guild OS - Audit Panel (guild readiness)
-- "Auditoria" tab with sub-tabs: Attunement progression grid and the
-- guild-wide enchant audit. Visual layout only — data comes from
-- BRutus.AttunementTracker and BRutus.GearAudit (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local SUBTABS = {
    { key = "attune",  label = L["Attunements"] },
    { key = "enchant", label = L["Enchants"] },
    { key = "sync",    label = L["Sync"] },
}

local ROW_H = 24
local NAME_W = 170
local COL_W = 92

-- Ready-check icons render reliably inside FontStrings (no font-glyph risk).
local ICON_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t"
local ICON_NONE = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:14:14|t"

----------------------------------------------------------------------
-- Shared builders
----------------------------------------------------------------------
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

local function ClearContent(content)
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
end

----------------------------------------------------------------------
-- ATTUNEMENTS sub-panel — guild progression grid
----------------------------------------------------------------------
local function BuildAttuneSub(panel)
    local legend = UI:CreateText(panel,
        ICON_DONE .. " " .. L["attuned"] .. "    " .. ICON_NONE .. " " .. L["not started"]
        .. "    |cffEDCC7Bx/y|r " .. L["in progress"] .. "    |cff808080\226\128\147|r " .. L["no data"],
        9, C.silver.r, C.silver.g, C.silver.b)
    legend:SetPoint("TOPLEFT", 4, -2)

    -- Column header (fixed, above the scroll)
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 0, -20)
    header:SetPoint("TOPRIGHT", -10, -20)
    header:SetHeight(30)
    panel.headerCells = {}
    local hName = UI:CreateHeaderText(header, L["MEMBER"], 10)
    hName:SetPoint("LEFT", 8, 6)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -52)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditAttuneScroll")

    return function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)
        for _, fs in ipairs(panel.headerCells) do fs:Hide() end

        local cols, rows = BRutus.AttunementTracker:GetGuildMatrix()

        -- Header column labels + per-column attuned counts
        local totalsWithData = 0
        for _, r in ipairs(rows) do if r.hasData then totalsWithData = totalsWithData + 1 end end
        for ci, col in ipairs(cols) do
            local x = NAME_W + (ci - 1) * COL_W
            local lbl = UI:CreateHeaderText(header, col.short, 10)
            lbl:SetPoint("LEFT", x, 6)
            panel.headerCells[#panel.headerCells + 1] = lbl
            local doneN = 0
            for _, r in ipairs(rows) do
                local c = r.cells[col.short]
                if c and c.complete then doneN = doneN + 1 end
            end
            local cnt = UI:CreateText(header, doneN .. "/" .. totalsWithData, 8, C.textDim.r, C.textDim.g, C.textDim.b)
            cnt:SetPoint("LEFT", x, -8)
            panel.headerCells[#panel.headerCells + 1] = cnt
        end

        local yOff = 0
        for idx, r in ipairs(rows) do
            local row = MakeRow(content, yOff, idx)
            local cr, cg, cb = BRutus:GetClassColor(r.class)
            local nameFS = UI:CreateText(row, r.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 8, 0)
            if not r.hasData then nameFS:SetTextColor(0.45, 0.45, 0.5) end

            for ci, col in ipairs(cols) do
                local x = NAME_W + (ci - 1) * COL_W
                local cell = UI:CreateText(row, "", 11, 1, 1, 1)
                cell:SetPoint("LEFT", x, 0)
                local c = r.cells[col.short]
                if not r.hasData or not c then
                    cell:SetText("|cff808080\226\128\147|r")  -- en dash, gray
                elseif c.complete then
                    cell:SetText(ICON_DONE)
                elseif (c.progress or 0) > 0 then
                    cell:SetText(string.format("|cffEDCC7B%d/%d|r", c.questsDone or 0, c.questsTotal or 0))
                else
                    cell:SetText(ICON_NONE)
                end
            end
            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = UI:CreateText(content, L["No roster data yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- ENCHANTS sub-panel — guild enchant audit
----------------------------------------------------------------------
local function BuildEnchantSub(panel)
    local summary = UI:CreateText(panel, "", 10, C.gold.r, C.gold.g, C.gold.b)
    summary:SetPoint("TOPLEFT", 4, -4)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -24)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditEnchantScroll")

    return function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local all = BRutus.GearAudit:GetGuildEnchantAudit()
        local problems = {}
        for _, r in ipairs(all) do
            if r.missingCount > 0 then problems[#problems + 1] = r end
        end
        summary:SetText(string.format(L["%d with missing enchants  |  %d scanned"], #problems, #all))

        local yOff = 0
        for idx, r in ipairs(problems) do
            local row = MakeRow(content, yOff, idx)
            local cr, cg, cb = BRutus:GetClassColor(r.class)
            local nameFS = UI:CreateText(row, r.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 8, 0)

            local cntFS = UI:CreateText(row, string.format(L["%d missing"], r.missingCount), 10, C.red.r, C.red.g, C.red.b)
            cntFS:SetPoint("LEFT", 150, 0)

            local slots = table.concat(r.missing, ", ")
            local slotsFS = UI:CreateText(row, slots, 10, C.silver.r, C.silver.g, C.silver.b)
            slotsFS:SetPoint("LEFT", 250, 0)
            slotsFS:SetWidth(content:GetWidth() - 270)
            slotsFS:SetJustifyH("LEFT")
            slotsFS:SetWordWrap(false)

            yOff = yOff + ROW_H + 2
        end

        if #problems == 0 then
            local msg = #all == 0 and L["No gear data synced yet."] or L["Everyone is fully enchanted!"]
            local empty = UI:CreateText(content, msg, 11, C.green.r, C.green.g, C.green.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- SYNC sub-panel — addon adoption / version / last sync
----------------------------------------------------------------------
local function BuildSyncSub(panel)
    local summary = UI:CreateText(panel, "", 10, C.gold.r, C.gold.g, C.gold.b)
    summary:SetPoint("TOPLEFT", 4, -6)

    local exportBtn = UI:CreateButton(panel, L["Export Roster"], 110, 20)
    exportBtn:SetPoint("TOPRIGHT", -12, -2)
    exportBtn:SetScript("OnClick", function()
        BRutus:ShowExportPopup(L["Roster Export"], BRutus:ExportRoster())
    end)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -24)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditSyncScroll")

    return function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local rows, withAddon, outdated = BRutus.CommSystem:GetSyncHealth()
        summary:SetText(string.format(L["%d/%d have Guild OS  |  %d outdated"], withAddon, #rows, outdated))

        local yOff = 0
        for idx, r in ipairs(rows) do
            local row = MakeRow(content, yOff, idx)
            local cr, cg, cb = BRutus:GetClassColor(r.class)
            local nameFS = UI:CreateText(row, r.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 8, 0)

            if not r.hasAddon then
                local st = UI:CreateText(row, L["no addon"], 10, C.red.r, C.red.g, C.red.b)
                st:SetPoint("LEFT", 180, 0)
            else
                local st = UI:CreateText(row, ICON_DONE, 11, 1, 1, 1)
                st:SetPoint("LEFT", 180, 0)
                local verColor = r.outdated and C.gold or C.silver
                local verStr = r.version and ("v" .. r.version) or "?"
                if r.outdated then verStr = verStr .. L[" (outdated)"] end
                local ver = UI:CreateText(row, verStr, 10, verColor.r, verColor.g, verColor.b)
                ver:SetPoint("LEFT", 220, 0)

                local last = UI:CreateText(row, BRutus:TimeAgo(r.lastUpdate), 9, C.textDim.r, C.textDim.g, C.textDim.b)
                last:SetPoint("LEFT", 420, 0)
            end

            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = UI:CreateText(content, L["No roster data yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- Panel assembly (sub-tab bar + sub-panels)
----------------------------------------------------------------------
function BRutus:CreateAuditPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "attune"

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
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
    end

    parent.RefreshActive = function()
        local info = parent.subPanels[parent.activeSub]
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
    end

    local x = 0
    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 130)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + 134
    end

    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", 12, -42)
        p:SetPoint("BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end

    local builders = { attune = BuildAttuneSub, enchant = BuildEnchantSub, sync = BuildSyncSub }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "attune")
    end)
end
