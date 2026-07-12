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
    { key = "ready",   label = L["Readiness"] },
    { key = "attune",  label = L["Attunements"] },
    { key = "resist",  label = L["Resistances"] },
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
-- READINESS sub-panel — "is the raid ready?" one-screen rollup
-- Aggregates attunement + enchants + iLvl + (in-raid) consumables.
----------------------------------------------------------------------
local function BuildReadySub(panel)
    panel.targetIdx = 0   -- 0 = all raids; 1..N = a specific attunement raid

    local summary = UI:CreateText(panel, "", 10, C.gold.r, C.gold.g, C.gold.b)
    summary:SetPoint("TOPLEFT", 4, -4)

    local targetBtn = UI:CreateButton(panel, L["Target: All raids"], 220, 20)
    targetBtn:SetPoint("TOPRIGHT", -12, -2)

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 0, -26)
    header:SetPoint("TOPRIGHT", -10, -26)
    header:SetHeight(16)
    local function hcol(txt, x)
        local fs = UI:CreateHeaderText(header, txt, 9)
        fs:SetPoint("LEFT", x, 0)
    end
    hcol(L["MEMBER"], 8)
    hcol(L["STATUS"], 160)
    hcol(L["iLVL"], 250)
    hcol(L["ATTUNE"], 310)
    hcol(L["ENCHANTS"], 400)
    hcol(L["CONSUMES"], 510)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -46)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditReadyScroll")

    local function refresh()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local targets = BRutus.Readiness:GetTargets()
        local target = (panel.targetIdx > 0) and targets[panel.targetIdx] or nil
        local targetShort = target and target.short or nil
        targetBtn.label:SetText(target and (L["Target: "] .. target.short) or L["Target: All raids"])

        local rows = BRutus.Readiness:GetReport(targetShort)
        local c = BRutus.Readiness:Summarize(rows)
        summary:SetText(string.format(L["%d ready  |  %d need attention  |  %d not ready"],
            c.ready, c.warn, c.notready))

        local yOff = 0
        for idx, r in ipairs(rows) do
            local row = MakeRow(content, yOff, idx)
            local cr, cg, cb = BRutus:GetClassColor(r.class)
            local nameFS = UI:CreateText(row, r.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 8, 0)
            if r.status == "nodata" then nameFS:SetTextColor(0.45, 0.45, 0.5) end

            local stFS = UI:CreateText(row, "", 11, 1, 1, 1)
            stFS:SetPoint("LEFT", 160, 0)
            if r.status == "ready" then
                stFS:SetText(ICON_DONE .. " |cff4CFF4C" .. L["ready"] .. "|r")
            elseif r.status == "notready" then
                stFS:SetText(ICON_NONE .. " |cffFF5555" .. L["not attuned"] .. "|r")
            elseif r.status == "warn" then
                stFS:SetText("|cffEDCC7B! " .. L["check"] .. "|r")
            else
                stFS:SetText("|cff808080\226\128\147|r")
            end

            local ilvlFS = UI:CreateText(row, r.ilvl > 0 and tostring(r.ilvl) or "\226\128\148",
                10, C.silver.r, C.silver.g, C.silver.b)
            ilvlFS:SetPoint("LEFT", 250, 0)

            local attColor = (r.attTotal > 0 and r.attDone == r.attTotal) and C.green or C.gold
            if r.targetOk == false then attColor = C.red elseif r.targetOk == true then attColor = C.green end
            local attTxt = r.attTotal > 0 and (r.attDone .. "/" .. r.attTotal) or "\226\128\148"
            local attFS = UI:CreateText(row, attTxt, 10, attColor.r, attColor.g, attColor.b)
            attFS:SetPoint("LEFT", 310, 0)

            local enchTxt, ec
            if not r.hasGear then enchTxt, ec = "\226\128\148", C.textDim
            elseif r.missEnch > 0 then enchTxt, ec = string.format(L["%d missing"], r.missEnch), C.red
            else enchTxt, ec = "OK", C.green end
            local enchFS = UI:CreateText(row, enchTxt, 10, ec.r, ec.g, ec.b)
            enchFS:SetPoint("LEFT", 400, 0)

            local consTxt, cc
            if r.missCons == nil then consTxt, cc = "\226\128\148", C.textDim
            elseif r.missCons > 0 then consTxt, cc = string.format(L["%d missing"], r.missCons), C.red
            else consTxt, cc = "OK", C.green end
            local consFS = UI:CreateText(row, consTxt, 10, cc.r, cc.g, cc.b)
            consFS:SetPoint("LEFT", 510, 0)

            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = UI:CreateText(content, L["No roster data yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end

    targetBtn:SetScript("OnClick", function()
        local targets = BRutus.Readiness:GetTargets()
        panel.targetIdx = panel.targetIdx + 1
        if panel.targetIdx > #targets then panel.targetIdx = 0 end
        refresh()
    end)

    return refresh
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
-- RESISTANCES sub-panel — guild resistance-gear grid (member x school)
-- Shows the max resistance each member can field per school (from gear they
-- own, bags included), coloured against that school's headline fight.
----------------------------------------------------------------------
local function BuildResistSub(panel)
    local R = BRutus.Resistances

    local legend = UI:CreateText(panel,
        L["Max resistance each member can equip from owned gear (bags included). Green = a solid set for that fight."],
        9, C.silver.r, C.silver.g, C.silver.b)
    legend:SetPoint("TOPLEFT", 4, -2)

    -- Column header: MEMBER + one column per school (coloured), fight/target below.
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 0, -20)
    header:SetPoint("TOPRIGHT", -10, -20)
    header:SetHeight(30)
    local hName = UI:CreateHeaderText(header, L["MEMBER"], 10)
    hName:SetPoint("LEFT", 8, 6)
    for ci, sc in ipairs(R.SCHOOLS) do
        local x = NAME_W + (ci - 1) * COL_W
        local lbl = UI:CreateHeaderText(header, sc.label, 10)
        lbl:SetPoint("LEFT", x, 6)
        lbl:SetTextColor(sc.r, sc.g, sc.b)
        local sub = UI:CreateText(header, sc.fight .. " \226\137\165" .. sc.target, 8,
            C.textDim.r, C.textDim.g, C.textDim.b)
        sub:SetPoint("LEFT", x, -8)
    end

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -52)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditResistScroll")

    return function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local rows = R:GetRows()
        local yOff = 0
        for idx, r in ipairs(rows) do
            local row = MakeRow(content, yOff, idx)
            local cr, cg, cb = BRutus:GetClassColor(r.class)
            local nameFS = UI:CreateText(row, r.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 8, 0)

            for ci, sc in ipairs(R.SCHOOLS) do
                local x = NAME_W + (ci - 1) * COL_W
                local v = (r.res and r.res[sc.key]) or 0
                local tier = R:Tier(v, sc.target)
                local col = C.textDim
                if tier == "ready" then col = C.green
                elseif tier == "partial" then col = C.gold
                elseif tier == "low" then col = C.silver end
                local txt = v > 0 and tostring(v) or "|cff808080\226\128\148|r"
                local cell = UI:CreateText(row, txt, 11, col.r, col.g, col.b)
                cell:SetPoint("LEFT", x, 0)
            end
            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = UI:CreateText(content, L["No resistance data synced yet."], 11,
                C.silver.r, C.silver.g, C.silver.b)
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

    -- Chehul mesh observability: realm-wide, cross-addon presence beyond the
    -- guild-only sync above. Makes the otherwise-invisible mesh auditable.
    local meshLine = UI:CreateText(panel, "", 9, C.silver.r, C.silver.g, C.silver.b)
    meshLine:SetPoint("TOPLEFT", 4, -20)

    local refresh  -- forward declaration so the Sync button can refresh post-sync

    local exportBtn = UI:CreateButton(panel, L["Export Roster"], 110, 20)
    exportBtn:SetPoint("TOPRIGHT", -12, -2)
    exportBtn:SetScript("OnClick", function()
        BRutus:ShowExportPopup(L["Roster Export"], BRutus:ExportRoster())
    end)

    -- Manual sync: broadcast our data + re-request everyone's, then refresh the
    -- list once responses have had a moment to arrive.
    local syncBtn = UI:CreateButton(panel, L["Sync now"], 90, 20)
    syncBtn:SetPoint("TOPRIGHT", exportBtn, "TOPLEFT", -6, 0)
    syncBtn:SetScript("OnClick", function()
        if BRutus.CommSystem then BRutus.CommSystem:FullSync() end
        C_Timer.After(2.5, function() if refresh then refresh() end end)
    end)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -34)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditSyncScroll")

    refresh = function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local rows, withAddon, outdated = BRutus.CommSystem:GetSyncHealth()
        summary:SetText(string.format(L["%d/%d have Guild OS  |  %d outdated"], withAddon, #rows, outdated))

        if BRutus.Mesh then
            meshLine:SetText(string.format(
                L["Chehul mesh: %s  |  %d peers  |  %d on Guild OS"],
                BRutus.Mesh:HealthLine(), BRutus.Mesh:PeerCount(), BRutus.Mesh:PeerCount("gos")))
        end

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

    -- Live-update the mesh line as HELLOs arrive (throttled in GuildOS.Mesh),
    -- but only while this sub-panel is actually visible.
    if BRutus.Mesh then
        BRutus.Mesh:OnRefresh(function()
            if panel:IsShown() then refresh() end
        end)
    end

    return refresh
end

----------------------------------------------------------------------
-- Panel assembly (sub-tab bar + sub-panels)
----------------------------------------------------------------------
function BRutus:CreateAuditPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "ready"

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

    local builders = { ready = BuildReadySub, attune = BuildAttuneSub, resist = BuildResistSub,
        enchant = BuildEnchantSub, sync = BuildSyncSub }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "ready")
    end)
end
