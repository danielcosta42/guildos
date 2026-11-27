----------------------------------------------------------------------
-- Guild OS - Audit Panel (guild readiness)
-- "Auditoria" tab with sub-tabs: Attunement progression grid and the
-- guild-wide enchant audit. Visual layout only — data comes from
-- GuildOS.AttunementTracker and GuildOS.GearAudit (Rule 3 / Rule 10).
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- The Raids room's Audit (the mockup's raides-prontidao): one parchment card, its sub-tabs as pills, the
-- tables on the paper. The paper's shades of a state, and a class's colour as the paper prints it.
local function paperClass(class)
    return GuildOS.UI:InkFor("paper", "class", class)   -- the paper's class inks (UI/Helpers.lua, #449)
end
-- The wood's colours as the paper prints them: the ink, the soft ink, a state's deeper shade; anything
-- else light (a school's colour) darkened to read on the parchment.
local function onPaper(r, g, b)
    return GuildOS.UI.PaperRGB(r, g, b)   -- the one mapping of the paper's inks (UI/Helpers.lua, #449)
end
-- The shared components, with every text drawn on the paper taking the paper's shade of its colour.
local UI = setmetatable({
    CreateText = function(self, parent, text, size, r, g, b)
        if r and GuildOS.UI.OnPaper and GuildOS.UI:OnPaper(parent) then r, g, b = onPaper(r, g, b) end
        return GuildOS.UI.CreateText(self, parent, text, size, r, g, b)
    end,
}, { __index = function(_, k) return GuildOS.UI[k] end })

local SUBTABS = {
    { key = "ready",   label = L["Readiness"] },
    { key = "attune",  label = L["Attunements"], tbc = true },  -- TBC content (ADR-0014)
    { key = "resist",  label = L["Resistances"], tbc = true },  -- targets are TBC fights
    { key = "enchant", label = L["Enchants"] },
    { key = "sync",    label = L["Sync"] },
}

local ROW_H = 24
local NAME_W = 170
local COL_W = 92
-- The screen's margins (#371): flush with the sub-tab bar's left edge, GAP under it, the content ending
-- GAP short of the right edge. A scroll child stops UI.SCROLL_GUTTER short of its frame, so a scroll
-- frame's right edge sits SCROLL_R from the panel's.
local GAP = UI.GAP
local SCROLL_R = UI.SCROLL_GUTTER - UI.GAP
local HEAD_ABOVE = 20   -- room over a later section title for its rule (UI:CreateSectionTitle)
local HEAD_H = 26       -- a section title's line and the space under it
local LINE_H = 16       -- a line of secondary text

-- A status word in its status colour, from the palette's tokens (#371: they were hex codes).
-- Every screen here is on the paper: the state's shade as the paper prints it.
local function tint(text, col)
    local r, g, b = onPaper(col.r, col.g, col.b)
    return GuildOS:ColorText(text, r, g, b)
end
local DASH = "\226\128\147"   -- en dash: no data

-- Ready-check icons render reliably inside FontStrings (no font-glyph risk).
local ICON_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t"
local ICON_NONE = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:14:14|t"

----------------------------------------------------------------------
-- Shared builders
----------------------------------------------------------------------
-- The shared scroll frame (#371), anchored here: its child keeps the frame's width less the gutter,
-- so it ends GAP short of the panel's right edge with the scroll bar past it.
local function MakeScrollList(panel, name, topInset)
    local scroll, content = UI:CreateScrollFrame(panel, name)
    scroll:SetPoint("TOPLEFT", 0, -(topInset or 0))
    scroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
    UI:BindScrollChildWidth(scroll, content)
    return scroll, content
end

-- A row hung by both top corners: a width read at refresh time is 0 on a hidden tab (#371).
-- A 1px line of the paper's under it, as the mockup's tables. Rows are kept on the content and handed out
-- again in order (#449): a refresh draws over the last one's frames instead of leaving them under it.
local function MakeRow(content, yOff)
    content.__rows = content.__rows or {}
    content.__nRows = (content.__nRows or 0) + 1
    local row = content.__rows[content.__nRows]
    if not row then
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)
        local rule = row:CreateTexture(nil, "BACKGROUND")
        rule:SetTexture(WHITE)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", 0, -ROW_H - 1)
        rule:SetPoint("TOPRIGHT", 0, -ROW_H - 1)
        rule:SetVertexColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 1)
        row.cells = {}
        content.__rows[content.__nRows] = row
    end
    for _, cell in pairs(row.cells) do cell:Hide() end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -yOff)
    row:SetPoint("TOPRIGHT", 0, -yOff)
    row:Show()
    return row
end

-- A row's (or a header's) text `key`: made the first time, set again on every refresh after. Unanchored.
local function Cell(owner, key, text, size, r, g, b)
    owner.cells = owner.cells or {}
    local fs = owner.cells[key]
    if not fs then
        fs = UI:CreateText(owner, "", size, r, g, b)
        owner.cells[key] = fs
    elseif r then
        if GuildOS.UI.OnPaper and GuildOS.UI:OnPaper(owner) then r, g, b = onPaper(r, g, b) end
        fs:SetTextColor(r, g, b)
    end
    fs:ClearAllPoints()
    fs:SetText(text or "")
    fs:Show()
    return fs
end

-- A row's status badge `key`, kept like its texts.
local function Badge(row, key, text, color)
    local b = row.cells[key]
    if b then b:SetText(text, color) else b = UI:CreateBadge(row, text, color); row.cells[key] = b end
    b:ClearAllPoints()
    b:Show()
    return b
end

-- A line drawn straight on the content (an empty list's message, the sync's lines): the content's next one.
local function Line(content, text, size, r, g, b)
    content.__nLines = (content.__nLines or 0) + 1
    return Cell(content, "line" .. content.__nLines, text, size, r, g, b)
end

-- What a refresh drew goes before the next one: the rows, and the lines and titles drawn straight on
-- the content; the next refresh takes them again from the first.
local function ClearContent(content)
    content.__nRows, content.__nLines, content.__nTitles = 0, 0, 0
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
    for _, region in pairs({ content:GetRegions() }) do region:Hide() end
end

-- A table's header row: the shared one, no fill and a 1px rule under it (#371).
local function MakeHeader(panel, top, height)
    local header = UI:CreateTableHeader(panel, height)
    header:SetPoint("TOPLEFT", 0, -top)
    header:SetPoint("TOPRIGHT", -GAP, -top)
    return header
end

-- A section title on a list (#371): the list's first has no rule; a later one leaves HEAD_ABOVE over
-- itself for it. Returns the y under it.
local function SectionTitle(content, text, yOff)
    local first = yOff == 0
    if not first then yOff = yOff + HEAD_ABOVE end
    content.__titles = content.__titles or {}
    content.__nTitles = (content.__nTitles or 0) + 1
    local t = content.__titles[content.__nTitles]
    if not t then
        t = UI:CreateSectionTitle(content, "", false)
        content.__titles[content.__nTitles] = t
    end
    GuildOS:SetTitleText(t, text)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", 0, -yOff)
    t:Show()
    if t.rule then t.rule:SetShown(not first) end
    return yOff + HEAD_H
end

----------------------------------------------------------------------
-- READINESS sub-panel — "is the raid ready?" one-screen rollup
-- Aggregates attunement + enchants + iLvl + (in-raid) consumables.
----------------------------------------------------------------------
local function BuildReadySub(panel)
    panel.targetIdx = 0   -- 0 = all raids; 1..N = a specific attunement raid
    -- The attunement target is TBC's (ADR-0014) and the consumables column the checker's, on
    -- Anniversary and retail (issue #187): where the game has neither, there is nothing to cycle
    -- through or to count (issue #184).
    local hasAttune, hasCons = GuildOS.AttunementTracker ~= nil, GuildOS.ConsumableChecker ~= nil
    -- WoW: Forever has no attunements: its column is the level, the door to a raid (issue #207).
    local forever = not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail
    panel.statusIdx = 0   -- 0 = every status; 1..N = one of them (issue #220)
    local STATUSES = { { "ready", L["ready"] }, { "warn", L["check"] }, { "notready", L["not ready"] } }

    -- The counts on a line of the soft ink; under it the actions and the filters, small buttons in a row.
    local summary = UI:CreateText(panel, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    summary:SetPoint("TOPLEFT", 0, 0)
    summary:SetPoint("TOPRIGHT", 0, 0)

    -- /gos specs: the group's talent specs, read now (#142).
    local specsBtn = UI:CreateButton(panel, L["Scan group talents"], 150, 20)
    specsBtn:SetPoint("TOPLEFT", 0, -20)
    local targetBtn
    if hasAttune then
        targetBtn = UI:CreateButton(panel, L["Target: All raids"], 160, 20)
    end
    specsBtn:SetScript("OnClick", function()
        if GuildOS.SpecChecker then GuildOS.SpecChecker:ScanGroup() end
    end)
    -- /gos cons: the raid's consumables, read now, with the announce (on retail the Raid HUD that
    -- holds the other way in does not exist; issue #187).
    local last = specsBtn
    if hasCons then
        local consBtn = UI:CreateButton(panel, L["Check Consumables"], 150, 20)
        consBtn:SetPoint("LEFT", last, "RIGHT", 6, 0)
        consBtn:SetScript("OnClick", function() GuildOS:ShowConsumablePopup() end)
        last = consBtn
    end
    if targetBtn then
        targetBtn:SetPoint("LEFT", last, "RIGHT", 6, 0)
        last = targetBtn
    end
    -- Forever's filters: a core and a status, each cycled like the target above (issue #220).
    local coreBtn, statusBtn
    if forever then
        coreBtn = UI:CreateButton(panel, L["Core: All"], 110, 20)
        coreBtn:SetPoint("LEFT", last, "RIGHT", 6, 0)
        statusBtn = UI:CreateButton(panel, L["Status: All"], 110, 20)
        statusBtn:SetPoint("LEFT", coreBtn, "RIGHT", 6, 0)
    end
    summary:SetWordWrap(false)
    summary:SetJustifyH("LEFT")

    local header = MakeHeader(panel, 48)
    local function hcol(txt, x)
        local fs = UI:CreateHeaderText(header, txt, 11)
        fs:SetPoint("LEFT", x, 0)
    end
    hcol(L["Member"], 8)
    hcol(L["Status"], 160)
    hcol(L["iLvl"], 250)
    if hasAttune then hcol(L["Attune"], 310) end
    if forever then hcol(L["Level"], 310) end
    hcol(L["Enchants"], 400)
    if hasCons then hcol(L["Consumables"], 510) end
    if forever then
        hcol(L["Core"], 470)
        hcol(L["Role"], 580)
    end

    local foot = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    foot:SetPoint("BOTTOMLEFT", 0, 2)
    foot:SetJustifyH("LEFT")

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -70)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditReadyScroll")

    local function refresh()
        ClearContent(content)

        local targets = GuildOS.Readiness:GetTargets()
        local target = (panel.targetIdx > 0) and targets[panel.targetIdx] or nil
        local targetShort = target and target.short or nil
        if targetBtn then targetBtn.label:SetText(target and (L["Target: "] .. target.short) or L["Target: All raids"]) end

        local rows = GuildOS.Readiness:GetReport(targetShort)
        local c = GuildOS.Readiness:Summarize(rows)
        summary:SetText(string.format(L["%d ready · %d need attention · %d not ready"],
            c.ready, c.warn, c.notready))

        if forever then
            local names = GuildOS.CoreManager and GuildOS.CoreManager:GetSortedNames() or {}
            if panel.coreIdx > #names then panel.coreIdx = 0 end
            panel.coreName = names[panel.coreIdx]
            local status = STATUSES[panel.statusIdx]
            coreBtn.label:SetText(panel.coreName and (L["Core: "] .. panel.coreName) or L["Core: All"])
            statusBtn.label:SetText(status and (L["Status: "] .. status[2]) or L["Status: All"])

            GuildOS.Readiness:WithSeats(rows)
            -- The footer reads the whole guild: a status filter hides rows, not what a core has.
            local lines = {}
            for _, x in ipairs(GuildOS.Readiness:Compositions(rows, panel.coreName)) do
                lines[#lines + 1] = string.format(L["%s: tanks %d/%d  |  healers %d/%d  |  dps %d/%d"],
                    x.core, x.tanks, x.wantTanks, x.healers, x.wantHealers, x.dps, x.wantDps)
            end
            foot:SetText(table.concat(lines, "\n"))
            listHolder:SetPoint("BOTTOMRIGHT", 0, #lines > 0 and #lines * 14 + 6 or 0)
            rows = GuildOS.Readiness.Filtered(rows, panel.coreName, status and status[1] or nil)
        end

        local yOff = 0
        for _, r in ipairs(rows) do
            local row = MakeRow(content, yOff)
            local cr, cg, cb = paperClass(r.class)
            local nameFS = Cell(row, "nameFS", r.name, 12, cr, cg, cb)
            GuildOS:ApplyFont(nameFS, 12, "button")
            nameFS:SetPoint("LEFT", 8, 0)
            if r.status == "nodata" then nameFS:SetTextColor(C.labelDim.r, C.labelDim.g, C.labelDim.b) end

            -- The status as the mockup's badge: green ready, amber to check, red not ready.
            local badge
            if r.status == "ready" then
                badge = Badge(row, "badge", L["ready"], C.ok)
            elseif r.status == "notready" and r.reason == "level" then
                badge = Badge(row, "badge", L["Level"] .. " " .. (r.level or 0), C.danger)
            elseif r.status == "notready" then
                badge = Badge(row, "badge", L["not attuned"], C.danger)
            elseif r.status == "warn" then
                badge = Badge(row, "badge", L["check"], C.warn)
            end
            if badge then
                badge:SetPoint("LEFT", 160, 0)
            else
                Cell(row, "dash", tint(DASH, C.labelDim), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b):SetPoint("LEFT", 160, 0)
            end

            -- A 60 with no addon data is ready by level only, said where its item level would be (#207).
            local ilvlFS = Cell(row, "ilvlFS", r.levelOnly and L["level only"] or r.ilvl > 0 and tostring(r.ilvl) or "\226\128\148",
                11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            ilvlFS:SetPoint("LEFT", 250, 0)
            ilvlFS:SetWidth(56); ilvlFS:SetWordWrap(false); ilvlFS:SetJustifyH("LEFT")

            if forever then
                local lvlFS = Cell(row, "lvlFS", tostring(r.level or 0), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                lvlFS:SetPoint("LEFT", 310, 0)
            end
            if hasAttune then
                -- In progress reads as warn: gold is not a status (#371).
                local attColor = (r.attTotal > 0 and r.attDone == r.attTotal) and C.ok or C.warn
                if r.targetOk == false then attColor = C.danger elseif r.targetOk == true then attColor = C.ok end
                local attTxt = r.attTotal > 0 and (r.attDone .. "/" .. r.attTotal) or "\226\128\148"
                local attFS = Cell(row, "attFS", attTxt, 11, attColor.r, attColor.g, attColor.b)
                attFS:SetPoint("LEFT", 310, 0)
            end

            local enchTxt, ec
            if not r.hasGear then enchTxt, ec = "\226\128\148", C.label
            elseif r.missEnch > 0 then enchTxt, ec = string.format(L["%d missing"], r.missEnch), C.danger
            else enchTxt, ec = "OK", C.ok end
            local enchFS = Cell(row, "enchFS", enchTxt, 11, ec.r, ec.g, ec.b)
            enchFS:SetPoint("LEFT", 400, 0)

            if forever then
                -- The seat in the chosen core, or the first, with how many more.
                local seat = r.seats[1]
                for _, s in ipairs(r.seats) do
                    if s.core == panel.coreName then seat = s end
                end
                local more = (#r.seats > 1 and not panel.coreName) and (" +" .. (#r.seats - 1)) or ""
                local coreFS = Cell(row, "coreFS", seat and (seat.core .. more) or "\226\128\148", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                coreFS:SetPoint("LEFT", 470, 0)
                coreFS:SetWidth(104); coreFS:SetWordWrap(false); coreFS:SetJustifyH("LEFT")
                local rc = (seat and seat.main) and C.textSoft or C.label
                local roleName = seat and GuildOS.CoreManager.ROLE_LABELS[seat.role]
                local roleFS = Cell(row, "roleFS", roleName or "\226\128\148", 11, rc.r, rc.g, rc.b)
                roleFS:SetPoint("LEFT", 580, 0)
            end

            if hasCons then
                local consTxt, cc
                if r.missCons == nil then consTxt, cc = "\226\128\148", C.label
                elseif r.missCons > 0 then consTxt, cc = string.format(L["%d missing"], r.missCons), C.danger
                else consTxt, cc = "OK", C.ok end
                local consFS = Cell(row, "consFS", consTxt, 11, cc.r, cc.g, cc.b)
                consFS:SetPoint("LEFT", 510, 0)
            end

            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = Line(content, L["No roster data yet."], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 8, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end

    if forever then
        panel.coreIdx = 0
        coreBtn:SetScript("OnClick", function()
            panel.coreIdx = panel.coreIdx + 1
            refresh()
        end)
        statusBtn:SetScript("OnClick", function()
            panel.statusIdx = (panel.statusIdx + 1) % (#STATUSES + 1)
            refresh()
        end)
    end

    if targetBtn then
        targetBtn:SetScript("OnClick", function()
            local targets = GuildOS.Readiness:GetTargets()
            panel.targetIdx = panel.targetIdx + 1
            if panel.targetIdx > #targets then panel.targetIdx = 0 end
            refresh()
        end)
    end

    return refresh
end

----------------------------------------------------------------------
-- ATTUNEMENTS sub-panel — guild progression grid
----------------------------------------------------------------------
local function BuildAttuneSub(panel)
    local legend = UI:CreateText(panel,
        ICON_DONE .. " " .. L["attuned"] .. "    " .. ICON_NONE .. " " .. L["not started"]
        .. "    " .. tint("x/y", C.warn) .. " " .. L["in progress"] .. "    " .. tint(DASH, C.labelDim) .. " " .. L["no data"],
        11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    legend:SetPoint("TOPLEFT", 0, -2)

    -- Column header (fixed, above the scroll): two lines, the raid and how many have it.
    local header = MakeHeader(panel, 22, 30)
    panel.headerCells = {}
    local hName = UI:CreateHeaderText(header, L["Member"], 11)
    hName:SetPoint("LEFT", 8, 6)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -52)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditAttuneScroll")

    return function()
        ClearContent(content)
        for _, fs in pairs(panel.headerCells) do fs:Hide() end

        local cols, rows = GuildOS.AttunementTracker:GetGuildMatrix()

        -- Header column labels + per-column attuned counts
        local totalsWithData = 0
        for _, r in ipairs(rows) do if r.hasData then totalsWithData = totalsWithData + 1 end end
        for ci, col in ipairs(cols) do
            local x = NAME_W + (ci - 1) * COL_W
            -- Kept by column: a refresh sets them again (#449).
            local lbl = panel.headerCells["lbl" .. ci]
            if not lbl then
                lbl = UI:CreateHeaderText(header, "", 11)
                panel.headerCells["lbl" .. ci] = lbl
            end
            lbl:SetText(col.short)
            lbl:ClearAllPoints()
            lbl:SetPoint("LEFT", x, 6)
            lbl:Show()
            local doneN = 0
            for _, r in ipairs(rows) do
                local c = r.cells[col.short]
                if c and c.complete then doneN = doneN + 1 end
            end
            local cnt = Cell(header, "cnt" .. ci, doneN .. "/" .. totalsWithData, 10, C.label.r, C.label.g, C.label.b)
            cnt:SetPoint("LEFT", x, -8)
            panel.headerCells["cnt" .. ci] = cnt
        end

        local yOff = 0
        for _, r in ipairs(rows) do
            local row = MakeRow(content, yOff)
            local cr, cg, cb = paperClass(r.class)
            local nameFS = Cell(row, "nameFS", r.name, 12, cr, cg, cb)
            GuildOS:ApplyFont(nameFS, 12, "button")
            nameFS:SetPoint("LEFT", 8, 0)
            if not r.hasData then nameFS:SetTextColor(C.labelDim.r, C.labelDim.g, C.labelDim.b) end

            for ci, col in ipairs(cols) do
                local x = NAME_W + (ci - 1) * COL_W
                local cell = Cell(row, "cell" .. ci, "", 11, C.text.r, C.text.g, C.text.b)
                cell:SetPoint("LEFT", x, 0)
                local c = r.cells[col.short]
                if not r.hasData or not c then
                    cell:SetText(tint(DASH, C.labelDim))
                elseif c.complete then
                    cell:SetText(ICON_DONE)
                elseif (c.progress or 0) > 0 then
                    cell:SetText(tint(string.format("%d/%d", c.questsDone or 0, c.questsTotal or 0), C.warn))
                else
                    cell:SetText(ICON_NONE)
                end
            end
            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = Line(content, L["No roster data yet."], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 8, -4)
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
    local R = GuildOS.Resistances

    local legend = UI:CreateText(panel,
        L["Max resistance each member can equip from owned gear (bags included). Green = a solid set for that fight."],
        11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    legend:SetPoint("TOPLEFT", 0, -2)

    -- Column header: MEMBER + one column per school (coloured), fight/target below.
    local header = MakeHeader(panel, 22, 30)
    local hName = UI:CreateHeaderText(header, L["Member"], 11)
    hName:SetPoint("LEFT", 8, 6)
    for ci, sc in ipairs(R.SCHOOLS) do
        local x = NAME_W + (ci - 1) * COL_W
        local lbl = UI:CreateHeaderText(header, sc.label, 11)
        lbl:SetPoint("LEFT", x, 6)
        lbl:SetTextColor(sc.r, sc.g, sc.b)
        local sub = UI:CreateText(header, sc.fight .. " \226\137\165" .. sc.target, 11,
            C.label.r, C.label.g, C.label.b)
        sub:SetPoint("LEFT", x, -8)
    end

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -52)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditResistScroll")

    return function()
        ClearContent(content)

        local rows = R:GetRows()
        local yOff = 0
        for _, r in ipairs(rows) do
            local row = MakeRow(content, yOff)
            local cr, cg, cb = paperClass(r.class)
            local nameFS = Cell(row, "nameFS", r.name, 12, cr, cg, cb)
            GuildOS:ApplyFont(nameFS, 12, "button")
            nameFS:SetPoint("LEFT", 8, 0)

            for ci, sc in ipairs(R.SCHOOLS) do
                local x = NAME_W + (ci - 1) * COL_W
                local v = (r.res and r.res[sc.key]) or 0
                local tier = R:Tier(v, sc.target)
                -- A partial set reads as warn: gold is not a status (#371).
                local col = C.label
                if tier == "ready" then col = C.ok
                elseif tier == "partial" then col = C.warn
                elseif tier == "low" then col = C.textSoft end
                local txt = v > 0 and tostring(v) or tint("\226\128\148", C.labelDim)
                local cell = Cell(row, "cell" .. ci, txt, 11, col.r, col.g, col.b)
                cell:SetPoint("LEFT", x, 0)
            end
            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = Line(content, L["No resistance data synced yet."], 11,
                C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 8, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- ENCHANTS sub-panel — guild enchant audit
----------------------------------------------------------------------
local function BuildEnchantSub(panel)
    local summary = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    summary:SetPoint("TOPLEFT", 0, -4)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -26)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditEnchantScroll")

    return function()
        ClearContent(content)

        local all = GuildOS.GearAudit:GetGuildEnchantAudit()
        local problems = {}
        for _, r in ipairs(all) do
            if r.missingCount > 0 then problems[#problems + 1] = r end
        end
        summary:SetText(string.format(L["%d with missing enchants  |  %d scanned"], #problems, #all))

        local yOff = 0
        for _, r in ipairs(problems) do
            local row = MakeRow(content, yOff)
            local cr, cg, cb = paperClass(r.class)
            local nameFS = Cell(row, "nameFS", r.name, 12, cr, cg, cb)
            GuildOS:ApplyFont(nameFS, 12, "button")
            nameFS:SetPoint("LEFT", 8, 0)

            local cntFS = Cell(row, "cntFS", string.format(L["%d missing"], r.missingCount), 11, C.danger.r, C.danger.g, C.danger.b)
            cntFS:SetPoint("LEFT", 150, 0)

            -- Up to the row's right edge by anchors: a width read at refresh time is 0 on a hidden tab.
            local slots = table.concat(r.missing, ", ")
            local slotsFS = Cell(row, "slotsFS", slots, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            slotsFS:SetPoint("LEFT", 250, 0)
            slotsFS:SetPoint("RIGHT", -8, 0)
            slotsFS:SetJustifyH("LEFT")
            slotsFS:SetWordWrap(false)

            yOff = yOff + ROW_H + 2
        end

        if #problems == 0 then
            -- Everyone enchanted is good news, in ok; no data yet is a plain line.
            local msg = #all == 0 and L["No gear data synced yet."] or L["Everyone is fully enchanted!"]
            local col = #all == 0 and C.textSoft or C.ok
            local empty = Line(content, msg, 11, col.r, col.g, col.b)
            empty:SetPoint("TOPLEFT", 8, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- SYNC sub-panel — addon adoption / version / last sync
----------------------------------------------------------------------

-- The recruitment's numbers as lines of text: ChehulGossip:Audit() has them and keeps a copy in
-- GuildOSDB. Whatever it lacks reads as zero, and one that raises shows nothing: the panel never falls
-- over a counter.
local function RecruitLines()
    local gossip = GuildOS.ChehulGossip
    if GuildOS.Client.isAnniversary or not (gossip and gossip.Audit) then return nil end
    local ok, a = pcall(gossip.Audit, gossip)
    if not ok or type(a) ~= "table" then return nil end
    -- A value an old or damaged save holds wrong costs the tab its line, never the tab.
    local built, lines = pcall(function()
        local g, r, ch = a.gossip or {}, a.requests or {}, a.channel
        local d = type(r.dropped) == "table" and r.dropped or {}
        -- Tried and refused, tried and taken, or never tried (the channel had no number yet): three things.
        local function sent(v, skipped)
            if v == nil then return skipped and L["not tried"] or L["no"] end
            return v and L["yes"] or L["no"]
        end
        local function yn(v) return v and L["yes"] or L["no"] end
        local out = {
            string.format(L["rounds %d  -  ads in %d, out %d  -  peers %d  -  dropped %d"],
                g.rounds or 0, g.adsIn or 0, g.adsOut or 0, g.peers or 0, g.dropped or 0),
            string.format(L["Whisper test: %s"], g.whisper or L["no spelling came back: gossip and requests do not whisper"]),
            string.format(L["requests: %d open  -  asked %d, delivered %d  -  invites %d, confirmed by the game %d  -  dropped: name %d, guild %d"],
                r.open or 0, r.asked or 0, r.delivered or 0, r.invites or 0, r.confirmed or 0, d.name or 0, d.guild or 0),
            string.format(L["Senders refused as officers: %d"], g.officerRefused or 0),
        }
        if type(ch) == "table" then
            local h = type(ch.heard) == "table" and ch.heard or {}
            out[#out + 1] = string.format(L["Channel probe: command sent %s, timer sent %s  -  heard back: command %s, timer %s"],
                sent(ch.click, ch.clickSkipped), sent(ch.timer, ch.timerSkipped), yn(h.click), yn(h.timer))
        else
            out[#out + 1] = L["Channel probe: not run"]
        end
        return out
    end)
    if not built then return nil end
    return lines
end

local function BuildSyncSub(panel)
    local summary = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    summary:SetPoint("TOPLEFT", 0, -4)

    -- Chehul mesh observability: realm-wide, cross-addon presence beyond the
    -- guild-only sync above. Makes the otherwise-invisible mesh auditable.
    local meshLine = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    meshLine:SetPoint("TOPLEFT", 0, -22)

    local refresh  -- forward declaration so the Sync button can refresh post-sync

    local exportBtn = UI:CreateButton(panel, L["Export Roster"], 110, 20)
    exportBtn:SetPoint("TOPRIGHT", -GAP, -2)
    exportBtn:SetScript("OnClick", function()
        GuildOS:ShowExportPopup(L["Roster Export"], GuildOS:ExportRoster())
    end)

    -- Manual sync: broadcast our data + re-request everyone's, then refresh the
    -- list once responses have had a moment to arrive.
    local syncBtn = UI:CreateButton(panel, L["Sync now"], 90, 20)
    syncBtn:SetPoint("TOPRIGHT", exportBtn, "TOPLEFT", -6, 0)
    syncBtn:SetScript("OnClick", function()
        if GuildOS.CommSystem then GuildOS.CommSystem:FullSync() end
        C_Timer.After(2.5, function() if refresh then refresh() end end)
    end)

    -- /gos mergeraids: the same night recorded twice becomes one (#142).
    local mergeBtn = UI:CreateButton(panel, L["Merge duplicate sessions"], 170, 20)
    mergeBtn:SetPoint("TOPRIGHT", syncBtn, "TOPLEFT", -6, 0)
    mergeBtn:SetScript("OnClick", function() GuildOS:MergeRaidSessions() end)
    summary:SetPoint("TOPRIGHT", mergeBtn, "TOPLEFT", -8, -4)
    summary:SetWordWrap(false)
    summary:SetJustifyH("LEFT")

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(38 + GAP))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSAuditSyncScroll")

    -- /gos probe channel (specs/071-o-recrutamento). Made once; the list clears its children and the
    -- refresh puts it back under the recruitment lines.
    local probeBtn = UI:CreateButton(content, L["Probe channel"], 140, 20)
    probeBtn:SetScript("OnClick", function()
        if not GuildOS.Probe then return end
        GuildOS.Probe:RunChannel()
        -- The verdict comes CHANNEL_WAIT seconds in; a second later the counters take it up here.
        C_Timer.After(GuildOS.Probe.CHANNEL_WAIT + 1, function() if refresh and panel:IsShown() then refresh() end end)
    end)

    -- /gos perf and /gos perf reset (issue #324), made once like the probe's button.
    local perfPrintBtn = UI:CreateButton(content, L["Print to chat"], 110, 20)
    perfPrintBtn:SetScript("OnClick", function() GuildOS.Perf:Print() end)
    local perfResetBtn = UI:CreateButton(content, L["Zero the counters"], 130, 20)
    perfResetBtn:SetScript("OnClick", function()
        GuildOS.Perf:Reset()
        if refresh then refresh() end
    end)

    refresh = function()
        ClearContent(content)

        local rows, withAddon, outdated = GuildOS.CommSystem:GetSyncHealth()
        summary:SetText(string.format(L["%d/%d have Guild OS  |  %d outdated"], withAddon, #rows, outdated))

        if GuildOS.Mesh then
            meshLine:SetText(string.format(
                L["Chehul mesh: %s  |  %d peers  |  %d on Guild OS"],
                GuildOS.Mesh:HealthLine(), GuildOS.Mesh:PeerCount(), GuildOS.Mesh:PeerCount("gos")))
        end

        local yOff = 0

        ------------------------------------------------------------------
        -- Guild OS messages this session (issue #312): what the guildmates' broadcasts became, so a
        -- sync that stores nothing shows where it was lost.
        ------------------------------------------------------------------
        local cs = GuildOS.CommSystem
        if cs.SyncCounters then
            local n = cs:SyncCounters()
            local line = string.format(L["Guild OS messages this session: received %d  -  stored %d  -  dropped %d"],
                n.received, n.stored, n.dropped)
            if n.topReason then
                line = line .. "  -  " .. string.format(L["top drop reason: %s"],
                    (cs.DROP_REASON_TEXT or {})[n.topReason] or n.topReason)
            end
            local fs = Line(content, line, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            fs:SetPoint("TOPLEFT", 0, -yOff)
            yOff = yOff + LINE_H + 2
        end

        ------------------------------------------------------------------
        -- Where the time goes (issue #324): what /gos perf prints. A section, under the shared title.
        ------------------------------------------------------------------
        yOff = SectionTitle(content, L["Performance"], yOff)
        for _, line in ipairs(GuildOS.Perf:Lines()) do
            local fs = Line(content, line, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            fs:SetPoint("TOPLEFT", 0, -yOff)
            yOff = yOff + LINE_H
        end
        perfPrintBtn:ClearAllPoints()
        perfPrintBtn:SetPoint("TOPLEFT", 0, -(yOff + 2))
        perfPrintBtn:Show()
        perfResetBtn:ClearAllPoints()
        perfResetBtn:SetPoint("LEFT", perfPrintBtn, "RIGHT", 6, 0)
        perfResetBtn:Show()
        yOff = yOff + 32

        ------------------------------------------------------------------
        -- The recruitment: the gossip's rounds, the requests, the whisper test and the channel probe.
        ------------------------------------------------------------------
        local lines = RecruitLines()
        probeBtn:Hide()
        if lines then
            yOff = SectionTitle(content, L["Recruitment"], yOff)
            for _, line in ipairs(lines) do
                local fs = Line(content, line, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                fs:SetPoint("TOPLEFT", 0, -yOff)
                yOff = yOff + LINE_H
            end
            probeBtn:ClearAllPoints()
            probeBtn:SetPoint("TOPLEFT", 0, -(yOff + 2))
            probeBtn:Show()
            yOff = yOff + 32
        end

        ------------------------------------------------------------------
        -- Alliance diagnostics: the alliance code's hidden channel, its lines sent, heard, shown and
        -- dropped (Modules/AllianceLink.lua), next to the mesh health line.
        ------------------------------------------------------------------
        local link = GuildOS.AllianceLink
        if link and link:Active() then
            yOff = SectionTitle(content, L["Alliance code"], yOff)
            local stats = Line(content, link:StatusLine(), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            stats:SetPoint("TOPLEFT", 0, -yOff)
            yOff = yOff + LINE_H + GAP
        end

        for _, r in ipairs(rows) do
            local row = MakeRow(content, yOff)
            local cr, cg, cb = paperClass(r.class)
            local nameFS = Cell(row, "nameFS", r.name, 12, cr, cg, cb)
            GuildOS:ApplyFont(nameFS, 12, "button")
            nameFS:SetPoint("LEFT", 8, 0)

            if not r.hasAddon then
                local st = Cell(row, "st", L["no addon"], 11, C.danger.r, C.danger.g, C.danger.b)
                st:SetPoint("LEFT", 180, 0)
            else
                local st = Cell(row, "st", ICON_DONE, 11, C.text.r, C.text.g, C.text.b)
                st:SetPoint("LEFT", 180, 0)
                -- An outdated version is a warning: gold is not a status (#371).
                local verColor = r.outdated and C.warn or C.textSoft
                local verStr = r.version and ("v" .. r.version) or "?"
                if r.outdated then verStr = verStr .. L[" (outdated)"] end
                local ver = Cell(row, "ver", verStr, 11, verColor.r, verColor.g, verColor.b)
                ver:SetPoint("LEFT", 220, 0)

                local last = Cell(row, "last", GuildOS:TimeAgo(r.lastUpdate), 11, C.label.r, C.label.g, C.label.b)
                last:SetPoint("LEFT", 420, 0)
            end

            yOff = yOff + ROW_H + 2
        end

        if #rows == 0 then
            local empty = Line(content, L["No roster data yet."], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 8, -(yOff + 4))
        end
        content:SetHeight(math.max(1, yOff))
    end

    -- Live-update the mesh line as HELLOs arrive (throttled in GuildOS.Mesh),
    -- but only while this sub-panel is actually visible.
    if GuildOS.Mesh then
        GuildOS.Mesh:OnRefresh(function()
            if panel:IsVisible() then refresh() end
        end)
    end

    return refresh
end

----------------------------------------------------------------------
-- Panel assembly (sub-tab bar + sub-panels)
----------------------------------------------------------------------
function GuildOS:CreateAuditPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "ready"

    local subtabs = {}
    for _, t in ipairs(SUBTABS) do
        -- Attunements wherever the tracker is (TBC; Forever's Onyxia, Ricki); resistances are TBC fights only.
        if not t.tbc or GuildOS.Client.isAnniversary or (t.key == "attune" and GuildOS.AttunementTracker) then
            subtabs[#subtabs + 1] = t
        end
    end

    -- One parchment card, GAP under the room's entries (the mockup's "Prontidão da guilda"); its sub-tabs
    -- are pills under its title, the chosen one in the title's red.
    local PAD = type(UI.CARD_PAD) == "number" and UI.CARD_PAD or 14
    local CARD_TOP = type(UI.CARD_TOP) == "number" and UI.CARD_TOP or 36
    local card = UI:CreateCard(parent, L["Guild readiness"])
    card:SetPoint("TOPLEFT", 0, -GAP)
    card:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    parent.card = card
    local bar = CreateFrame("Frame", nil, card)
    bar:SetPoint("TOPLEFT", PAD, -CARD_TOP + 6)
    bar:SetPoint("TOPRIGHT", -PAD, -CARD_TOP + 6)
    bar:SetHeight(22)

    local subTabBtns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do UI:SetSelected(btn, k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end
    parent.SelectSub = selectSub

    parent.RefreshActive = function()
        local info = parent.subPanels[parent.activeSub]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end

    local x = 0
    for _, t in ipairs(subtabs) do
        local btn = UI:SetButtonVariant(UI:CreateButton(bar, t.label, 40, 22), "chip")
        btn:SetWidth(math.ceil(btn.label:GetStringWidth() or 40) + 22)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + btn:GetWidth() + 6  -- a pill its label grew pushes the next one (issue #28)
    end

    -- A sub-tab's content: inside the card, under the pills.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, card)
        p:SetPoint("TOPLEFT", PAD, -(CARD_TOP + 26))
        p:SetPoint("BOTTOMRIGHT", -PAD + GAP, 10)
        p:Hide()
        return p
    end

    local builders = { ready = BuildReadySub, attune = BuildAttuneSub, resist = BuildResistSub,
        enchant = BuildEnchantSub, sync = BuildSyncSub }
    for _, t in ipairs(subtabs) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "ready")
    end)
end
