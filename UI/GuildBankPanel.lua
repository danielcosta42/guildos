----------------------------------------------------------------------
-- Guild OS - Guild bank window (issue #380)
-- The Bank tab: Inventory · Tabs · Ledger · Needs · Requests, and the bar the addon docks under the
-- game's own guild bank while it is open. Visual layer only: what the bank holds, its ledger, needs
-- and requests come from GuildOS.GuildBank, and every change goes through it.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local SUB_H     = 28    -- the sub-tab bar
local GAP       = tonumber(UI.GAP) or 8
local GUTTER    = tonumber(UI.SCROLL_GUTTER) or 12
local ROW_H     = 26    -- a list row
local HEAD_H    = 22    -- a list's column header
local CHIP_W    = 150   -- a metric chip's slot
local CHIP_H    = 52
local FIELD_H   = 22
local ICON      = 18    -- an item's icon in a list
local SLOT_MAX  = 40    -- a slot of the tab grid, at most
local SLOT_MIN  = 24
local SLOT_GAP  = 2
local GRID_COLS = 14    -- the game draws a tab 14 slots across (7 columns of two)
local GRID_ROWS = 7
local SIDE_W    = 280   -- the ledger's side column
local SIDE_MIN  = 760   -- under this width the ledger's side column goes
local WHERE_MIN = 640   -- under this width the inventory's "where" column goes
local CHART_H   = 60
local CHART_DAYS = 30
local TOP_N     = 8     -- contributors shown
local BAR_H     = 30    -- the bar under the game's bank
local ANNOUNCE_MAX = 240  -- characters of one guild chat line

local function Bank() return GuildOS.GuildBank end

----------------------------------------------------------------------
-- Small pieces
----------------------------------------------------------------------
local function money(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    if g > 0 then return string.format("%d|cffd9a94fg|r %d|cffa9a2b0s|r", g, s) end
    return string.format("%d|cffa9a2b0s|r", s)
end

local function qualityColor(q)
    local qc = GuildOS.QualityColors and GuildOS.QualityColors[q or 1]
    return qc or C.text
end

-- A name as the guild says it: the realm only when it is not mine.
local function shortName(name)
    if type(name) ~= "string" then return "?" end
    return (Ambiguate and Ambiguate(name, "guild")) or name
end

local function classColor(name)
    local class = Bank():ClassOf(name)
    return (class and GuildOS.ClassColors[class:upper()]) or C.text
end

-- The tooltip of an item, from its link string or id.
local function showItemTooltip(owner, id, l)
    if not (id or l) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(l or ("item:" .. id))
    GameTooltip:Show()
end

-- Shift-click puts the item's link in the chat box, as anywhere in the game.
local function linkToChat(id, l)
    local link = Bank():LinkOf(id, l)
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

-- The fields a shift-clicked item lands in while they have the focus.
local linkBoxes = {}
local linkHooked = false
local function acceptLinks(box)
    linkBoxes[box] = true
    if linkHooked then return end
    linkHooked = true
    local function insert(link)
        if type(link) ~= "string" then return end
        for b in pairs(linkBoxes) do
            if b:IsVisible() and b:HasFocus() then b:SetText(link); return true end
        end
    end
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link) if IsShiftKeyDown() then insert(link) end end)
    end
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insert) end
end

local function fieldLabel(parent, text)
    local fs = UI:CreateText(parent, text, 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    return fs
end

-- A list with pooled rows over a FauxScrollFrame. `create(row)` builds a row once; `draw(row, item)`
-- paints it. list:SetData(items) redraws.
local listCount = 0
local function makeList(parent, rowH, create, draw)
    listCount = listCount + 1
    local name = "GuildOSBankList" .. listCount
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(list) })
    list:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    list:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    local scroll = CreateFrame("ScrollFrame", name, list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -1)
    scroll:SetPoint("BOTTOMRIGHT", -2, 1)
    UI:SkinScrollBar(scroll, name)
    local rows, visible = {}, 0
    list.data = {}

    local function update()
        local offset = FauxScrollFrame_GetOffset(scroll)
        FauxScrollFrame_Update(scroll, #list.data, visible, rowH)
        for i = 1, visible do
            local row, item = rows[i], list.data[offset + i]
            if item then
                row.data = item
                GuildOS:SafeCall(draw, row, item, offset + i)
                row:Show()
            else
                row.data = nil
                row:Hide()
            end
        end
        if list.empty then list.empty:SetShown(#list.data == 0) end
    end
    list.Update = update

    local function size()
        local h = list:GetHeight() or 0
        local n = math.max(1, math.floor((h - 2) / rowH))
        for i = #rows + 1, n do
            local row = CreateFrame("Button", nil, list)
            row:SetHeight(rowH)
            row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * rowH)
            row:SetPoint("TOPRIGHT", -GUTTER, -1 - (i - 1) * rowH)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local hl = row:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetColorTexture(C.panel.r, C.panel.g, C.panel.b, 1)
            hl:Hide()
            row.hl = hl
            row:HookScript("OnEnter", function(self) self.hl:Show() end)
            row:HookScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
            local rule = row:CreateTexture(nil, "BORDER")
            rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
            UI:Hairline(rule)
            rule:SetColorTexture(C.panel.r, C.panel.g, C.panel.b, 1)
            create(row)
            rows[i] = row
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        visible = n
        update()
    end
    list:SetScript("OnSizeChanged", size)
    list:HookScript("OnShow", size)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, rowH, update)
    end)
    function list:SetData(items)
        self.data = items or {}
        update()
    end
    function list:SetEmptyText(text)
        if not self.empty then
            self.empty = UI:CreateText(self, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            self.empty:SetPoint("TOPLEFT", 12, -14)
            self.empty:SetPoint("RIGHT", -12, 0)
            self.empty:SetJustifyH("LEFT")
        end
        self.empty:SetText(text)
    end
    return list
end

-- An item's icon and name in a row: row.icon, row.name.
local function itemCell(row, x)
    row.icon = UI:CreateIcon(row, ICON)
    row.icon:SetPoint("LEFT", x or 6, 0)
    row.name = UI:CreateText(row, "", 12)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
end

local function paintItem(row, id, l, suffix)
    local info = Bank():ItemInfo(id, l)
    row.icon.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    UI:SetIconQuality(row.icon, info.quality or 1)
    local qc = qualityColor(info.quality)
    row.name:SetText((info.name or ("item:" .. tostring(id))) .. (suffix or ""))
    row.name:SetTextColor(qc.r, qc.g, qc.b)
    return info
end

local function headerText(parent, text, x, justify)
    local fs = UI:CreateHeaderText(parent, text, 10)
    fs:SetPoint("LEFT", x, 0)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- A row of chip buttons, one chosen: opts = { { key, label } }, onPick(key). Returns the bar and its
-- Select(key).
local function chipBar(parent, opts, onPick)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(FIELD_H)
    local buttons, prev = {}, nil
    for _, o in ipairs(opts) do
        local b = UI:CreateButton(bar, o[2], 60, FIELD_H)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", 0, 0) end
        b.key = o[1]
        b:SetScript("OnClick", function() bar.Select(o[1]); onPick(o[1]) end)
        buttons[#buttons + 1] = b
        prev = b
    end
    function bar.Select(key)
        for _, b in ipairs(buttons) do UI:SetSelected(b, b.key == key) end
    end
    bar.buttons = buttons
    bar.last = prev
    return bar
end

local function emptyBankText()
    return L["Nobody with Guild OS has opened the guild bank yet. Open it once and every member sees it here."]
end

----------------------------------------------------------------------
-- Inventory
----------------------------------------------------------------------
local GROUP_LABEL = {
    consumable = "Consumables", trade = "Trade goods", enhance = "Gems and enhancements",
    recipe = "Recipes", gear = "Equipment", bags = "Bags and ammo", other = "Other",
}

local function buildInventory(p, panel)
    local B = Bank()
    local st = { query = "", sort = "cat", group = "all" }

    local chips = {}
    local captions = { L["Gold"], L["Items"], L["Free slots"], L["Last read"] }
    for i, cap in ipairs(captions) do
        local chip = UI:CreateMetricChip(p, "—", cap)
        chip:SetPoint("TOPLEFT", (i - 1) * (CHIP_W + 16), -GAP)
        chip:SetWidth(CHIP_W)
        chips[i] = chip
    end

    local search = UI:CreateInput(p, 200, FIELD_H, { placeholder = L["Search items…"], max = 60 })
    search:SetPoint("TOPLEFT", 0, -(GAP + CHIP_H + GAP))
    local sortDD = UI:CreateDropdown(p, 150, FIELD_H)
    sortDD:SetPoint("LEFT", search, "RIGHT", 8, 0)
    sortDD:SetOptions({
        { value = "cat", text = L["By category"] }, { value = "name", text = L["By name"] },
        { value = "count", text = L["By quantity"] }, { value = "quality", text = L["By quality"] },
    })
    sortDD:SetValue("cat")
    local groupDD = UI:CreateDropdown(p, 180, FIELD_H)
    groupDD:SetPoint("LEFT", sortDD, "RIGHT", 8, 0)
    local gopts = { { value = "all", text = L["All categories"] } }
    for _, g in ipairs(GuildOS.GuildBankPlan.GROUPS) do gopts[#gopts + 1] = { value = g, text = L[GROUP_LABEL[g]] } end
    groupDD:SetOptions(gopts)
    groupDD:SetValue("all")

    local head = UI:CreateTableHeader(p, HEAD_H)
    head:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -GAP)
    head:SetPoint("RIGHT", p, "RIGHT", -GAP, 0)
    headerText(head, L["ITEM"], 32)
    local hTotal = UI:CreateHeaderText(head, L["TOTAL"], 10)
    local hWhere = UI:CreateHeaderText(head, L["WHERE"], 10)
    local hNeed = UI:CreateHeaderText(head, L["NEED"], 10)

    local hint = UI:CreateText(p, L["Shift-click: link in chat · Right-click: ask the officers · Alt-click (officer): set a need"], 11,
        C.label.r, C.label.g, C.label.b)
    hint:SetPoint("BOTTOMLEFT", 0, 4)
    local countText = UI:CreateText(p, "", 11, C.label.r, C.label.g, C.label.b)
    countText:SetPoint("BOTTOMRIGHT", -GAP, 4)

    local NEED_W, WHERE_W, TOTAL_W = 150, 230, 60
    local showWhere = true
    local list = makeList(p, ROW_H, function(row)
        itemCell(row, 8)
        row.group = UI:CreateHeaderText(row, "", 10)
        row.group:SetPoint("BOTTOMLEFT", 8, 4)
        row.total = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.total, 11, "tableNum")
        row.total:SetJustifyH("RIGHT")
        row.total:SetWidth(TOTAL_W)
        row.where = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.where:SetJustifyH("LEFT")
        row.where:SetWordWrap(false)
        row.where:SetWidth(WHERE_W)
        row.bar = UI:CreateProgressBar(row, 60, 6)
        row.need = UI:CreateText(row, "", 10)
        row.need:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.data and not self.data.header then showItemTooltip(self, self.data.id, self.data.l) end
        end)
        row:SetScript("OnClick", function(self, button)
            local it = self.data
            if not it or it.header then return end
            if IsShiftKeyDown() then linkToChat(it.id, it.l)
            elseif IsAltKeyDown() and GuildOS:IsOfficer() then panel.Prefill("needs", it.id)
            elseif button == "RightButton" then panel.Prefill("requests", it.id) end
        end)
        row.Layout = function(self)
            self.need:ClearAllPoints()
            self.bar:ClearAllPoints()
            self.bar:SetPoint("RIGHT", -(NEED_W - 60), 0)
            self.need:SetPoint("LEFT", self.bar, "RIGHT", 6, 0)
            self.where:ClearAllPoints()
            self.where:SetPoint("RIGHT", -(NEED_W + 10), 0)
            self.where:SetShown(showWhere)
            self.total:ClearAllPoints()
            self.total:SetPoint("RIGHT", -(NEED_W + 10 + (showWhere and (WHERE_W + 10) or 0)), 0)
            self.name:SetPoint("RIGHT", self.total, "LEFT", -10, 0)
        end
        row:Layout()
    end, function(row, it)
        local isHead = it.header and true or false
        row.group:SetShown(isHead)
        row.icon:SetShown(not isHead)
        row.name:SetShown(not isHead)
        row.total:SetShown(not isHead)
        row.where:SetShown(not isHead and showWhere)
        if isHead then
            row.group:SetText(it.label)
            row.bar:Hide(); row.need:Hide()
            return
        end
        if row.layoutWhere ~= showWhere then row.layoutWhere = showWhere; row:Layout() end
        paintItem(row, it.id, it.l)
        row.total:SetText(tostring(it.total))
        local parts, tabs = {}, {}
        for tab in pairs(it.tabs) do tabs[#tabs + 1] = tab end
        table.sort(tabs)
        for _, tab in ipairs(tabs) do parts[#parts + 1] = string.format(L["Tab %d: %d"], tab, it.tabs[tab]) end
        row.where:SetText(table.concat(parts, "  "))
        local need = B:NeedOf(it.id)
        row.bar:SetShown(need ~= nil)
        row.need:SetShown(need ~= nil)
        if need then
            local have = B:CountOf(it.id)
            row.bar:SetProgress(have / need)
            local col = have >= need and C.ok or (have / need >= 0.6 and C.warn or C.danger)
            row.need:SetText(have >= need and L["met"] or string.format(L["%d short"], need - have))
            row.need:SetTextColor(col.r, col.g, col.b)
        end
    end)
    list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -GAP, 22)
    list:SetEmptyText(emptyBankText())

    local function rebuild()
        local index = B:Index()
        local q = st.query:lower()
        local items = {}
        for _, e in ipairs(index.list) do
            local info = B:ItemInfo(e.id, e.l)
            local group = GuildOS.GuildBankPlan.GroupOf(info.classID)
            if (st.group == "all" or st.group == group) and (q == "" or (info.name and info.name:lower():find(q, 1, true))) then
                items[#items + 1] = { id = e.id, l = e.l, total = e.total, tabs = e.tabs, info = info, group = group,
                    rank = (B:RankOf(e.id, e.l)) }
            end
        end
        local sorters = {
            cat = function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.total > b.total end,
            name = function(a, b) return (a.info.name or "~") < (b.info.name or "~") end,
            count = function(a, b) if a.total ~= b.total then return a.total > b.total end return a.rank < b.rank end,
            quality = function(a, b)
                local qa, qb = a.info.quality or 0, b.info.quality or 0
                if qa ~= qb then return qa > qb end
                return a.rank < b.rank
            end,
        }
        table.sort(items, sorters[st.sort])
        local out = items
        if st.sort == "cat" and #items > 0 then
            out = {}
            local counts = {}
            for _, it in ipairs(items) do counts[it.group] = (counts[it.group] or 0) + 1 end
            local last
            for _, it in ipairs(items) do
                if it.group ~= last then
                    last = it.group
                    out[#out + 1] = { header = true, label = string.format("%s · %d", L[GROUP_LABEL[it.group]]:upper(), counts[it.group]) }
                end
                out[#out + 1] = it
            end
        end
        list:SetData(out)
        countText:SetText(string.format(L["%d of %d items"], #items, #index.list))

        local db = B:Store()
        chips[1]:SetValue(db.moneyNow and money(db.moneyNow) or "—")
        local total = 0
        for _, e in ipairs(index.list) do total = total + e.total end
        chips[2]:SetValue(tostring(total))
        local used, slots = B:Fill()
        chips[3]:SetValue(slots > 0 and string.format("%d / %d", slots - used, slots) or "—")
        local ts, by = B:Newest()
        chips[4]:SetValue(ts > 0 and GuildOS:TimeAgo(ts) or "—")
        chips[4].label:SetText(by and string.format(L["Read by %s"], by) or L["Last read"])
    end
    p.Draw = rebuild

    search:HookScript("OnTextChanged", function(self) st.query = self:GetText() or ""; rebuild() end)
    sortDD.onSelect = function(_, v) st.sort = v; rebuild() end
    groupDD.onSelect = function(_, v) st.group = v; rebuild() end

    UI:MakeResponsive(p, function(_, w)
        showWhere = w >= WHERE_MIN
        hWhere:SetShown(showWhere)
        hNeed:ClearAllPoints(); hNeed:SetPoint("LEFT", head, "RIGHT", -(NEED_W + GUTTER), 0)
        hWhere:ClearAllPoints(); hWhere:SetPoint("LEFT", head, "RIGHT", -(NEED_W + 10 + WHERE_W + GUTTER), 0)
        hTotal:ClearAllPoints()
        hTotal:SetPoint("RIGHT", head, "RIGHT", -(NEED_W + 10 + (showWhere and (WHERE_W + 10) or 0) + GUTTER), 0)
        list:Update()
    end)
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local function slotPosition(i)
    local col = math.floor((i - 1) / GuildOS.Compat.GUILD_BANK_PER_COLUMN)
    local b = (i - 1) % GuildOS.Compat.GUILD_BANK_PER_COLUMN
    return col * 2 + (b >= GRID_ROWS and 1 or 0), b % GRID_ROWS
end

local function buildTabs(p)
    local B = Bank()
    local st = { tab = 1, organized = false }

    local side = CreateFrame("Frame", nil, p)
    side:SetPoint("TOPLEFT", 0, -GAP)
    side:SetPoint("BOTTOMLEFT", 0, GAP)
    side:SetWidth(190)
    local sideTitle = UI:CreateHeaderText(side, L["BANK TABS"], 10)
    sideTitle:SetPoint("TOPLEFT", 0, 0)
    local tabButtons = {}
    for tab = 1, 8 do
        local b = UI:CreateButton(side, "", 190, 30)
        b:SetPoint("TOPLEFT", 0, -16 - (tab - 1) * 34)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 34, 0)
        b.label:SetPoint("RIGHT", -44, 0)
        b.label:SetJustifyH("LEFT")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(20, 20)
        b.icon:SetPoint("LEFT", 7, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.fill = UI:CreateText(b, "", 10, C.label.r, C.label.g, C.label.b)
        GuildOS:ApplyFont(b.fill, 10, "tableNum")
        b.fill:SetPoint("RIGHT", -8, 0)
        b:SetScript("OnClick", function() st.tab = tab; p.Draw() end)
        tabButtons[tab] = b
    end
    local perm = UI:CreateText(side, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    perm:SetPoint("BOTTOMLEFT", 0, 0)
    perm:SetPoint("RIGHT", side, "RIGHT", 0, 0)
    perm:SetJustifyH("LEFT")

    local main = CreateFrame("Frame", nil, p)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 16, 0)
    main:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    local title = UI:CreateSectionTitle(main, "", true)
    title:SetPoint("TOPLEFT", 0, 0)
    local fillText = UI:CreateText(main, "", 11, C.label.r, C.label.g, C.label.b)
    fillText:SetPoint("LEFT", title, "RIGHT", 10, 0)
    local orgBtn = UI:CreateButton(main, L["Organized"], 96, FIELD_H)
    orgBtn:SetPoint("TOPRIGHT", 0, 2)
    local asBtn = UI:CreateButton(main, L["As it is"], 96, FIELD_H)
    asBtn:SetPoint("RIGHT", orgBtn, "LEFT", -4, 0)
    asBtn:SetScript("OnClick", function() st.organized = false; p.Draw() end)
    orgBtn:SetScript("OnClick", function() st.organized = true; p.Draw() end)

    local grid = CreateFrame("Frame", nil, main)
    grid:SetPoint("TOPLEFT", 0, -32)
    local cells = {}
    for i = 1, GRID_COLS * GRID_ROWS do
        local cell = CreateFrame("Button", nil, grid, "BackdropTemplate")
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(cell) })
        cell:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
        cell:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
        cell.tex = cell:CreateTexture(nil, "ARTWORK")
        cell.tex:SetPoint("TOPLEFT", 2, -2)
        cell.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.count = UI:CreateText(cell, "", 10)
        GuildOS:ApplyFont(cell.count, 10, "tableNum")
        cell.count:SetPoint("BOTTOMRIGHT", -2, 2)
        cell:SetScript("OnEnter", function(self) if self.slot then showItemTooltip(self, self.slot.id, self.slot.l) end end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cell:SetScript("OnClick", function(self) if self.slot and IsShiftKeyDown() then linkToChat(self.slot.id, self.slot.l) end end)
        cells[i] = cell
    end

    local strip = CreateFrame("Frame", nil, main, "BackdropTemplate")
    strip:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(strip) })
    strip:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
    strip:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    strip:SetHeight(64)
    strip:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -GAP * 2)
    strip:SetPoint("RIGHT", main, "RIGHT", 0, 0)
    local movesChip = UI:CreateMetricChip(strip, "0", L["Moves"])
    movesChip:SetPoint("TOPLEFT", 12, -8)
    movesChip:SetWidth(80)
    local freedChip = UI:CreateMetricChip(strip, "0", L["Slots freed"])
    freedChip:SetPoint("TOPLEFT", 108, -8)
    freedChip:SetWidth(90)
    local organize = UI:CreateButton(strip, L["Organize at the bank"], 170, 28)
    UI:SetButtonVariant(organize, "primary")
    organize:SetPoint("RIGHT", -12, 0)
    organize:SetScript("OnClick", function() B:StartSort(st.tab) end)
    local stop = UI:CreateButton(strip, L["Stop"], 70, 28)
    stop:SetPoint("RIGHT", organize, "LEFT", -6, 0)
    stop:SetScript("OnClick", function() B:StopSort("cancel") end)
    local note = UI:CreateText(strip, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    note:SetPoint("LEFT", 216, 0)
    note:SetPoint("RIGHT", stop, "LEFT", -12, 0)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    local progress = UI:CreateProgressBar(strip, 100, 6)
    progress:SetPoint("BOTTOMLEFT", 216, 8)
    progress:SetPoint("RIGHT", stop, "LEFT", -12, 0)
    local empty = UI:CreateText(main, emptyBankText(), 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, -36)
    empty:SetPoint("RIGHT", main, "RIGHT", 0, 0)
    empty:SetJustifyH("LEFT")

    local cellSize = SLOT_MAX
    local function layoutGrid()
        grid:SetSize(GRID_COLS * (cellSize + SLOT_GAP), GRID_ROWS * (cellSize + SLOT_GAP))
        for i, cell in ipairs(cells) do
            local x, y = slotPosition(i)
            cell:SetSize(cellSize, cellSize)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", x * (cellSize + SLOT_GAP), -y * (cellSize + SLOT_GAP))
        end
    end
    layoutGrid()

    p.Draw = function()
        local db = B:Store()
        local count = math.max(db.numTabs or 0, 0)
        for tab in pairs(db.tabs) do count = math.max(count, tab) end
        if not db.tabs[st.tab] then
            for tab = 1, count do if db.tabs[tab] then st.tab = tab; break end end
        end
        for tab, b in ipairs(tabButtons) do
            local t = db.tabs[tab]
            b:SetShown(tab <= count)
            b.label:SetText(string.format("%d  %s", tab, (t and t.name) or L["Not seen yet"]))
            b.icon:SetTexture(t and t.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local used = 0
            if t then for _ in pairs(t.slots or {}) do used = used + 1 end end
            b.fill:SetText(t and string.format("%d/98", used) or "")
            UI:SetSelected(b, tab == st.tab)
        end
        UI:SetSelected(asBtn, not st.organized)
        UI:SetSelected(orgBtn, st.organized)

        local t = db.tabs[st.tab]
        empty:SetShown(t == nil)
        grid:SetShown(t ~= nil)
        strip:SetShown(t ~= nil)
        if not t then title:SetText(L["Bank"]); fillText:SetText(""); perm:SetText(""); return end
        local preview, moves = B:Preview(st.tab)
        local shown = st.organized and preview or t.slots
        local used, after = 0, #preview
        for _ in pairs(t.slots) do used = used + 1 end
        title:SetText(string.format("%d · %s", st.tab, t.name or ""))
        fillText:SetText(string.format(L["%d of 98 slots · read by %s %s"], st.organized and after or used, t.by or "?", GuildOS:TimeAgo(t.ts)))
        for i, cell in ipairs(cells) do
            local s = shown[i]
            cell.slot = s
            if s then
                local info = B:ItemInfo(s.id, s.l)
                cell.tex:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                cell.tex:Show()
                local qc = qualityColor(info.quality)
                cell:SetBackdropBorderColor(qc.r, qc.g, qc.b, (info.quality or 1) > 1 and 1 or 0.35)
                cell.count:SetText(s.c > 1 and tostring(s.c) or "")
            else
                cell.tex:Hide()
                cell.count:SetText("")
                cell:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
            end
        end
        movesChip:SetValue(tostring(moves))
        freedChip:SetValue("+" .. tostring(math.max(0, used - after)))

        local run = B:SortState()
        local can, why = B:CanOrganize(st.tab)
        if run then
            organize:Disable()
            stop:Show()
            progress:Show()
            local total = math.max(1, run.total or 1)
            progress:SetProgress((run.moves or 0) / total)
            note:SetText(string.format(L["Organizing tab %d: %d of about %d moves."], run.tab or st.tab, run.moves or 0, total))
        else
            stop:Hide()
            progress:Hide()
            organize:SetEnabled(can and moves > 0)
            if moves == 0 then note:SetText(L["This tab is already in order."])
            elseif can then note:SetText(L["Merges stacks and sorts by category, quality and name, one move at a time."])
            else note:SetText(why or "") end
        end
        if B:IsOpen() then
            local _, _, _, canDeposit, _, remaining = GuildOS.Compat.GuildBankTabInfo(st.tab)
            perm:SetText(string.format(L["Your rank: %s · %s"], canDeposit and L["deposits"] or L["no deposits"],
                tonumber(remaining) == -1 and L["withdraws without limit"]
                    or string.format(L["%s withdrawals left today"], tostring(remaining or 0))))
        else
            perm:SetText(L["At the bank, this shows what your rank may do here."])
        end
    end

    UI:MakeResponsive(p, function(_, w, h)
        local availW = w - 190 - 16 - GAP
        local availH = h - GAP * 2 - 32 - 64 - GAP * 2
        local size = math.floor(math.min((availW + SLOT_GAP) / GRID_COLS, (availH + SLOT_GAP) / GRID_ROWS)) - SLOT_GAP
        size = math.max(SLOT_MIN, math.min(SLOT_MAX, size))
        if size ~= cellSize then cellSize = size; layoutGrid() end
    end)
end

----------------------------------------------------------------------
-- Ledger
----------------------------------------------------------------------
local VERB = {
    d = { "deposited", "ok" }, w = { "withdrew", "danger" }, m = { "moved", "textSoft" },
    r = { "repairs", "warn" }, b = { "bought a tab", "warn" }, s = { "earned", "ok" },
}

local function buildLedger(p)
    local B = Bank()
    local st = { kind = "all", who = "" }

    local filters = chipBar(p, {
        { "all", L["All"] }, { "d", L["Deposits"] }, { "w", L["Withdrawals"] }, { "m", L["Moves"] }, { "gold", L["Gold"] },
    }, function(k) st.kind = k; p.Draw() end)
    filters:SetPoint("TOPLEFT", 0, -GAP)
    filters:SetWidth(400)
    filters.Select("all")
    local who = UI:CreateInput(p, 150, FIELD_H, { placeholder = L["Member"], max = 40 })
    who:SetPoint("LEFT", filters.last, "RIGHT", 12, 0)
    who:HookScript("OnTextChanged", function(self) st.who = (self:GetText() or ""):lower(); p.Draw() end)

    local side = CreateFrame("Frame", nil, p)
    side:SetPoint("TOPRIGHT", -GAP, -GAP)
    side:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    side:SetWidth(SIDE_W)

    local head = UI:CreateTableHeader(p, HEAD_H)
    head:SetPoint("TOPLEFT", 0, -(GAP + FIELD_H + GAP))
    head:SetPoint("RIGHT", side, "LEFT", -16, 0)
    local X = { when = 8, who = 76, verb = 190, item = 276 }
    headerText(head, L["WHEN"], X.when)
    headerText(head, L["WHO"], X.who)
    headerText(head, L["WHAT"], X.verb)
    headerText(head, L["ITEM"], X.item)
    local hQty = UI:CreateHeaderText(head, L["QTY"], 10)
    hQty:SetPoint("RIGHT", -(GUTTER + 52), 0)
    local hTab = UI:CreateHeaderText(head, L["TAB"], 10)
    hTab:SetPoint("RIGHT", -(GUTTER + 6), 0)

    local list = makeList(p, ROW_H, function(row)
        row.when = UI:CreateText(row, "", 11, C.label.r, C.label.g, C.label.b)
        GuildOS:ApplyFont(row.when, 11, "tableNum")
        row.when:SetPoint("LEFT", X.when, 0)
        row.who = UI:CreateText(row, "", 12)
        row.who:SetPoint("LEFT", X.who, 0)
        row.who:SetWidth(X.verb - X.who - 6)
        row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)
        row.verb = UI:CreateText(row, "", 11)
        row.verb:SetPoint("LEFT", X.verb, 0)
        row.itemText = UI:CreateText(row, "", 12)
        row.itemText:SetPoint("LEFT", X.item, 0)
        row.itemText:SetPoint("RIGHT", -96, 0)
        row.itemText:SetJustifyH("LEFT"); row.itemText:SetWordWrap(false)
        row.qty = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.qty, 11, "tableNum")
        row.qty:SetPoint("RIGHT", -52, 0)
        row.tab = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        GuildOS:ApplyFont(row.tab, 11, "tableNum")
        row.tab:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.data and self.data.id then showItemTooltip(self, self.data.id) end
        end)
        row:SetScript("OnClick", function(self)
            if self.data and self.data.id and IsShiftKeyDown() then linkToChat(self.data.id) end
        end)
    end, function(row, e)
        row.when:SetText(GuildOS:TimeAgo(e.t))
        local cc = classColor(e.n)
        row.who:SetText(shortName(e.n))
        row.who:SetTextColor(cc.r, cc.g, cc.b)
        local v = VERB[e.ty] or VERB.m
        local vc = C[v[2]] or C.text
        row.verb:SetText(L[v[1]])
        row.verb:SetTextColor(vc.r, vc.g, vc.b)
        if e.k == 0 then
            row.itemText:SetText(money(e.g))
            row.itemText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            row.qty:SetText("")
            row.tab:SetText("—")
        else
            local info = B:ItemInfo(e.id)
            local qc = qualityColor(info.quality)
            row.itemText:SetText(info.name or (e.id and ("item:" .. e.id)) or "?")
            row.itemText:SetTextColor(qc.r, qc.g, qc.b)
            row.qty:SetText(tostring(e.c or ""))
            row.tab:SetText(e.ty == "m" and e.t2 and string.format("%d→%d", e.k, e.t2) or tostring(e.k))
        end
    end)
    list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -16, 0)
    list:SetEmptyText(L["No ledger lines yet. They are read each time someone with Guild OS opens the bank."])

    -- Side: the bank's gold and who gave most.
    local goldTitle = UI:CreateSectionTitle(side, L["Bank gold"], true)
    goldTitle:SetPoint("TOPLEFT", 0, 0)
    local goldValue = UI:CreateText(side, "—", 20)
    GuildOS:ApplyFont(goldValue, 20, "metricValue")
    goldValue:SetPoint("TOPLEFT", goldTitle, "BOTTOMLEFT", 0, -8)
    local goldDelta = UI:CreateText(side, "", 11)
    goldDelta:SetPoint("LEFT", goldValue, "RIGHT", 10, 0)
    local chart = CreateFrame("Frame", nil, side)
    chart:SetPoint("TOPLEFT", goldValue, "BOTTOMLEFT", 0, -10)
    chart:SetSize(SIDE_W, CHART_H)
    local base = chart:CreateTexture(nil, "BORDER")
    base:SetPoint("BOTTOMLEFT"); base:SetPoint("BOTTOMRIGHT")
    UI:Hairline(base)
    base:SetColorTexture(C.line.r, C.line.g, C.line.b, 1)
    local bars = {}
    local barW = math.floor(SIDE_W / CHART_DAYS)
    for i = 1, CHART_DAYS do
        local bar = chart:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 0.85)
        bar:SetWidth(math.max(1, barW - 2))
        bar:SetPoint("BOTTOMLEFT", (i - 1) * barW, 1)
        bars[i] = bar
    end
    local chartCap = UI:CreateText(side, L["Last 30 days, one bar a day"], 10, C.label.r, C.label.g, C.label.b)
    chartCap:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -4)

    local topTitle = UI:CreateSectionTitle(side, L["Top contributors · 30 days"])
    topTitle:SetPoint("TOPLEFT", chartCap, "BOTTOMLEFT", 0, -28)
    local tops = {}
    for i = 1, TOP_N do
        local r = CreateFrame("Frame", nil, side)
        r:SetSize(SIDE_W, 26)
        r:SetPoint("TOPLEFT", topTitle, "BOTTOMLEFT", 0, -8 - (i - 1) * 28)
        r.name = UI:CreateText(r, "", 12)
        r.name:SetPoint("TOPLEFT", 0, 0)
        r.what = UI:CreateText(r, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        GuildOS:ApplyFont(r.what, 10, "tableNum")
        r.what:SetPoint("TOPRIGHT", 0, -1)
        r.bar = UI:CreateProgressBar(r, SIDE_W, 4)
        r.bar:SetPoint("BOTTOMLEFT", 0, 4)
        r.bar:SetPoint("BOTTOMRIGHT", 0, 4)
        tops[i] = r
    end
    local topNote = UI:CreateText(side, "", 10, C.label.r, C.label.g, C.label.b)
    topNote:SetPoint("BOTTOMLEFT", 0, 0)
    topNote:SetPoint("RIGHT", side, "RIGHT", 0, 0)
    topNote:SetJustifyH("LEFT")

    p.Draw = function()
        local rows = {}
        local ledger = B:Store().ledger
        for i = #ledger, 1, -1 do
            local e = ledger[i]
            local okKind = st.kind == "all" or (st.kind == "gold" and e.k == 0) or (st.kind ~= "gold" and e.k ~= 0 and e.ty == st.kind)
            if okKind and (st.who == "" or (e.n and e.n:lower():find(st.who, 1, true))) then rows[#rows + 1] = e end
        end
        list:SetData(rows)

        local db = B:Store()
        goldValue:SetText(db.moneyNow and money(db.moneyNow) or "—")
        local readings, nowT = db.money, GetServerTime()
        local weekAgo
        for _, r in ipairs(readings) do if r.t <= nowT - 7 * 86400 then weekAgo = r.m end end
        if db.moneyNow and weekAgo then
            local d = db.moneyNow - weekAgo
            local col = d >= 0 and C.ok or C.danger
            goldDelta:SetText(string.format(L["%s%s in 7 days"], d >= 0 and "+" or "-", money(math.abs(d))))
            goldDelta:SetTextColor(col.r, col.g, col.b)
        else
            goldDelta:SetText("")
        end
        local perDay, maxM = {}, 0
        for _, r in ipairs(readings) do
            local day = math.floor((nowT - r.t) / 86400)
            if day >= 0 and day < CHART_DAYS then perDay[CHART_DAYS - day] = r.m end
        end
        local last
        for i = 1, CHART_DAYS do
            if perDay[i] then last = perDay[i] elseif last then perDay[i] = last end
            if perDay[i] and perDay[i] > maxM then maxM = perDay[i] end
        end
        for i, bar in ipairs(bars) do
            local v = perDay[i]
            bar:SetShown(v ~= nil and maxM > 0)
            if v and maxM > 0 then bar:SetHeight(math.max(1, (CHART_H - 2) * v / maxM)) end
        end

        local list2 = {}
        for name, r in pairs(B:Contributions(30)) do
            local score = r.di + r.dg / 10000
            if score > 0 then list2[#list2 + 1] = { name = name, r = r, score = score } end
        end
        table.sort(list2, function(a, b) return a.score > b.score end)
        local officer = GuildOS:IsOfficer()
        for i, row in ipairs(tops) do
            local x = list2[i]
            row:SetShown(x ~= nil)
            if x then
                local cc = classColor(x.name)
                row.name:SetText(string.format("%d  %s", i, shortName(x.name)))
                row.name:SetTextColor(cc.r, cc.g, cc.b)
                local what = string.format(L["%d items"], x.r.di)
                if x.r.dg > 0 then what = what .. " · " .. money(x.r.dg) end
                if officer and (x.r.wi > 0 or x.r.wg > 0) then
                    what = what .. " · " .. string.format(L["out %d"], x.r.wi)
                end
                row.what:SetText(what)
                row.bar:SetProgress(x.score / list2[1].score)
            end
        end
        topNote:SetText(officer and L["Items and gold deposited; withdrawals shown to officers only."]
            or L["Items and gold deposited."])
    end

    UI:MakeResponsive(p, function(_, w)
        local wide = w >= SIDE_MIN
        side:SetShown(wide)
        head:SetPoint("RIGHT", wide and side or p, wide and "LEFT" or "RIGHT", wide and -16 or -GAP, 0)
        list:SetPoint("BOTTOMRIGHT", wide and side or p, wide and "BOTTOMLEFT" or "BOTTOMRIGHT", wide and -16 or -GAP, wide and 0 or GAP)
        list:Update()
    end)
end

----------------------------------------------------------------------
-- Needs
----------------------------------------------------------------------
local function buildNeeds(p, panel)
    local B = Bank()
    local metChip = UI:CreateMetricChip(p, "—", L["Needs met"])
    metChip:SetPoint("TOPLEFT", 0, -GAP)
    metChip:SetWidth(CHIP_W)
    local lowChip = UI:CreateMetricChip(p, "—", L["Under 60%"])
    lowChip:SetPoint("TOPLEFT", CHIP_W + 16, -GAP)
    lowChip:SetWidth(CHIP_W)
    local blurb = UI:CreateText(p, L["Officers say how many of each item the bank should hold. Every member sees what is short, here and on the item's tooltip."],
        12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    blurb:SetPoint("TOPLEFT", (CHIP_W + 16) * 2, -GAP - 4)
    blurb:SetPoint("RIGHT", p, "RIGHT", -(GAP + 330), 0)
    blurb:SetJustifyH("LEFT")
    local listBtn = UI:CreateButton(p, L["Shopping list"], 120, FIELD_H)
    listBtn:SetPoint("TOPRIGHT", -GAP, -GAP)
    listBtn:SetScript("OnClick", function()
        local lines = B:ShoppingList()
        if #lines == 0 then GuildOS:Print(L["The bank has everything it needs."]) end
        for _, line in ipairs(lines) do GuildOS:Print(line) end
    end)
    local announce = UI:CreateButton(p, L["Announce in guild chat"], 190, FIELD_H)
    announce:SetPoint("RIGHT", listBtn, "LEFT", -6, 0)
    announce:SetScript("OnClick", function()
        local lines = B:ShoppingList()
        if #lines == 0 then return end
        local text = L["Guild bank needs: "] .. table.concat(lines, ", ")
        if #text > ANNOUNCE_MAX then text = text:sub(1, ANNOUNCE_MAX - 3) .. "..." end
        SendChatMessage(text, "GUILD")
    end)

    local form = CreateFrame("Frame", nil, p)
    form:SetPoint("TOPLEFT", 0, -(GAP + CHIP_H + GAP))
    form:SetPoint("RIGHT", p, "RIGHT", -GAP, 0)
    form:SetHeight(FIELD_H)
    local itemLabel = fieldLabel(form, L["Item"])
    itemLabel:SetPoint("LEFT", 0, 0)
    local item = UI:CreateInput(form, 260, FIELD_H, { placeholder = L["Shift-click an item, or type its name"], max = 255 })
    item:SetPoint("LEFT", itemLabel, "RIGHT", 8, 0)
    acceptLinks(item)
    local qtyLabel = fieldLabel(form, L["Target"])
    qtyLabel:SetPoint("LEFT", item, "RIGHT", 12, 0)
    local qty = UI:CreateInput(form, 60, FIELD_H, { numeric = true, max = 6 })
    qty:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
    local noteLabel = fieldLabel(form, L["Note"])
    noteLabel:SetPoint("LEFT", qty, "RIGHT", 12, 0)
    local add = UI:CreateButton(form, L["Set need"], 100, FIELD_H)
    UI:SetButtonVariant(add, "primary")
    add:SetPoint("RIGHT", 0, 0)
    local noteBox = UI:CreateInput(form, 120, FIELD_H, { max = 80 })
    noteBox:SetPoint("LEFT", noteLabel, "RIGHT", 8, 0)
    noteBox:SetPoint("RIGHT", add, "LEFT", -8, 0)
    local readOnly = UI:CreateText(p, L["Only officers change the needs."], 11, C.label.r, C.label.g, C.label.b)
    readOnly:SetPoint("TOPLEFT", 0, -(GAP + CHIP_H + GAP + 4))
    local function submit()
        local id = B:ParseItemInput(item:GetText())
        if not id then GuildOS:Print(L["That names no item. Shift-click one, or type a name the bank holds."]); return end
        if B:SetNeed(id, tonumber(qty:GetText()), noteBox:GetText()) then
            item:SetText(""); qty:SetText(""); noteBox:SetText("")
        end
    end
    add:SetScript("OnClick", submit)
    qty:HookScript("OnEnterPressed", submit)

    local head = UI:CreateTableHeader(p, HEAD_H)
    head:SetPoint("TOPLEFT", form, "BOTTOMLEFT", 0, -GAP)
    head:SetPoint("RIGHT", p, "RIGHT", -GAP, 0)
    headerText(head, L["ITEM"], 32)
    local hHave = UI:CreateHeaderText(head, L["HAVE / TARGET"], 10)
    hHave:SetPoint("RIGHT", -(GUTTER + 380), 0)
    local hProg = UI:CreateHeaderText(head, L["PROGRESS"], 10)
    hProg:SetPoint("LEFT", head, "RIGHT", -(GUTTER + 360), 0)
    local hMiss = UI:CreateHeaderText(head, L["SHORT"], 10)
    hMiss:SetPoint("LEFT", head, "RIGHT", -(GUTTER + 140), 0)

    local list = makeList(p, ROW_H + 8, function(row)
        itemCell(row, 8)
        row.note = UI:CreateText(row, "", 10, C.label.r, C.label.g, C.label.b)
        row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 6)
        row.name:SetPoint("RIGHT", -400, 0)
        row.have = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.have, 11, "tableNum")
        row.have:SetPoint("RIGHT", -380, 0)
        row.bar = UI:CreateProgressBar(row, 200, 8)
        row.bar:SetPoint("LEFT", row, "RIGHT", -360, 0)
        row.miss = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.miss, 11, "tableNum")
        row.miss:SetPoint("LEFT", row, "RIGHT", -140, 0)
        row.remove = UI:CreateCloseButton(row)
        row.remove:SetSize(20, 20)
        row.remove:SetPoint("RIGHT", -4, 0)
        row.remove:SetScript("OnClick", function() if row.data then B:SetNeed(row.data.id, 0) end end)
        row:SetScript("OnEnter", function(self) self.hl:Show(); if self.data then showItemTooltip(self, self.data.id) end end)
        row:SetScript("OnClick", function(self, button)
            if not self.data then return end
            if IsShiftKeyDown() then linkToChat(self.data.id)
            elseif button == "RightButton" then panel.Prefill("requests", self.data.id) end
        end)
    end, function(row, r)
        paintItem(row, r.id)
        row.note:SetText(r.note or (r.by and string.format(L["by %s"], r.by)) or "")
        row.have:SetText(string.format("%d / %d", r.have, r.n))
        row.bar:SetProgress(r.have / r.n)
        local pct = r.have / r.n
        local col = pct >= 1 and C.ok or (pct >= 0.6 and C.warn or C.danger)
        row.miss:SetText(pct >= 1 and L["met"] or string.format(L["%d short"], r.n - r.have))
        row.miss:SetTextColor(col.r, col.g, col.b)
        row.remove:SetShown(GuildOS:IsOfficer())
    end)
    list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -GAP, GAP)
    list:SetEmptyText(L["No needs yet. An officer sets one above, or Alt-clicks an item in the Inventory."])

    p.Prefill = function(id)
        local link = B:LinkOf(id)
        item:SetText(link or tostring(id))
        qty:SetFocus()
    end
    p.Draw = function()
        local officer = GuildOS:IsOfficer()
        form:SetShown(officer)
        readOnly:SetShown(not officer)
        announce:SetShown(officer)
        local rows = B:NeedRows()
        local met, low = 0, 0
        for _, r in ipairs(rows) do
            if r.have >= r.n then met = met + 1 elseif r.have / r.n < 0.6 then low = low + 1 end
        end
        metChip:SetValue(#rows > 0 and string.format("%d / %d", met, #rows) or "—")
        lowChip:SetValue(tostring(low))
        list:SetData(rows)
    end
end

----------------------------------------------------------------------
-- Requests
----------------------------------------------------------------------
local REQ_TEXT = { open = "open", done = "filled", declined = "declined", cancelled = "cancelled" }

local function buildRequests(p)
    local B = Bank()
    local form = CreateFrame("Frame", nil, p)
    form:SetPoint("TOPLEFT", 0, -GAP)
    form:SetPoint("RIGHT", p, "RIGHT", -GAP, 0)
    form:SetHeight(FIELD_H)
    local itemLabel = fieldLabel(form, L["Item"])
    itemLabel:SetPoint("LEFT", 0, 0)
    local item = UI:CreateInput(form, 260, FIELD_H, { placeholder = L["Shift-click an item, or type its name"], max = 255 })
    item:SetPoint("LEFT", itemLabel, "RIGHT", 8, 0)
    acceptLinks(item)
    local qtyLabel = fieldLabel(form, L["Quantity"])
    qtyLabel:SetPoint("LEFT", item, "RIGHT", 12, 0)
    local qty = UI:CreateInput(form, 60, FIELD_H, { numeric = true, max = 4 })
    qty:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
    local noteLabel = fieldLabel(form, L["Why"])
    noteLabel:SetPoint("LEFT", qty, "RIGHT", 12, 0)
    local ask = UI:CreateButton(form, L["Ask the officers"], 140, FIELD_H)
    UI:SetButtonVariant(ask, "primary")
    ask:SetPoint("RIGHT", 0, 0)
    local noteBox = UI:CreateInput(form, 120, FIELD_H, { max = 80 })
    noteBox:SetPoint("LEFT", noteLabel, "RIGHT", 8, 0)
    noteBox:SetPoint("RIGHT", ask, "LEFT", -8, 0)
    local function submit()
        local id = B:ParseItemInput(item:GetText())
        if not id then GuildOS:Print(L["That names no item. Shift-click one, or type a name the bank holds."]); return end
        local n = tonumber(qty:GetText()) or 1
        if B:Request(id, n, noteBox:GetText()) then
            item:SetText(""); qty:SetText(""); noteBox:SetText("")
            GuildOS:Print(L["Request sent to the officers."])
        end
    end
    ask:SetScript("OnClick", submit)
    qty:HookScript("OnEnterPressed", submit)

    local head = UI:CreateTableHeader(p, HEAD_H)
    head:SetPoint("TOPLEFT", form, "BOTTOMLEFT", 0, -GAP)
    head:SetPoint("RIGHT", p, "RIGHT", -GAP, 0)
    headerText(head, L["WHEN"], 8)
    headerText(head, L["WHO"], 76)
    headerText(head, L["ITEM"], 196)
    local hState = UI:CreateHeaderText(head, L["STATE"], 10)
    hState:SetPoint("RIGHT", -(GUTTER + 170), 0)

    local list = makeList(p, ROW_H + 4, function(row)
        row.when = UI:CreateText(row, "", 11, C.label.r, C.label.g, C.label.b)
        GuildOS:ApplyFont(row.when, 11, "tableNum")
        row.when:SetPoint("LEFT", 8, 0)
        row.who = UI:CreateText(row, "", 12)
        row.who:SetPoint("LEFT", 76, 0)
        row.who:SetWidth(112)
        row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)
        itemCell(row, 196)
        row.name:SetPoint("RIGHT", -260, 0)
        row.state = UI:CreateText(row, "", 11)
        row.state:SetPoint("RIGHT", -170, 0)
        row.b1 = UI:CreateButton(row, L["Filled"], 76, 20)
        row.b1:SetPoint("RIGHT", -84, 0)
        row.b2 = UI:CreateButton(row, L["Decline"], 76, 20)
        row.b2:SetPoint("RIGHT", -4, 0)
        row.b1:SetScript("OnClick", function() if row.data then B:SetRequestState(row.data.id, "done") end end)
        row.b2:SetScript("OnClick", function()
            if not row.data then return end
            B:SetRequestState(row.data.id, B:IsMe(row.data.who) and not GuildOS:IsOfficer() and "cancelled" or "declined")
        end)
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.data then
                showItemTooltip(self, self.data.item)
                if self.data.note then GameTooltip:AddLine(self.data.note, 1, 1, 1, true); GameTooltip:Show() end
            end
        end)
        row:SetScript("OnClick", function(self) if self.data and IsShiftKeyDown() then linkToChat(self.data.item) end end)
    end, function(row, r)
        row.when:SetText(GuildOS:TimeAgo(r.ts))
        local cc = classColor(r.who)
        row.who:SetText(shortName(r.who))
        row.who:SetTextColor(cc.r, cc.g, cc.b)
        local have = B:CountOf(r.item)
        paintItem(row, r.item, nil, string.format(" × %d", r.n) .. (r.note and ("  |cff97909f" .. r.note .. "|r") or ""))
        local col = (r.st == "open" and C.text) or (r.st == "done" and C.ok) or C.label
        local stateText = L[REQ_TEXT[r.st] or "open"]
        if r.st == "open" then stateText = stateText .. " · " .. string.format(L["bank has %d"], have)
        elseif r.by then stateText = stateText .. " · " .. r.by end
        row.state:SetText(stateText)
        row.state:SetTextColor(col.r, col.g, col.b)
        local officer = GuildOS:IsOfficer()
        local mine = B:IsMe(r.who)
        row.b1:SetShown(r.st == "open" and officer)
        row.b2:SetShown(r.st == "open" and (officer or mine))
        row.b2.label:SetText((mine and not officer) and L["Cancel"] or L["Decline"])
    end)
    list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -GAP, GAP)
    list:SetEmptyText(L["No requests. Ask for an item above, or right-click it in the Inventory."])

    p.Prefill = function(id)
        item:SetText(B:LinkOf(id) or tostring(id))
        qty:SetFocus()
    end
    p.Draw = function() list:SetData(B:RequestRows()) end
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
function GuildOS:CreateGuildBankPanel(container, _mainFrame)
    local subBar = CreateFrame("Frame", nil, container)
    subBar:SetPoint("TOPLEFT", 0, 0)
    subBar:SetPoint("TOPRIGHT", 0, 0)
    subBar:SetHeight(SUB_H)
    UI:StyleSubTabBar(subBar)

    local SUBS = {
        { key = "inventory", label = L["Inventory"], build = buildInventory },
        { key = "tabs",      label = L["Tabs"],      build = buildTabs },
        { key = "ledger",    label = L["Ledger"],    build = buildLedger },
        { key = "needs",     label = L["Needs"],     build = buildNeeds },
        { key = "requests",  label = L["Requests"],  build = buildRequests },
    }
    local panels, tabs, built = {}, {}, {}
    local active
    local api = {}

    local function select(key)
        local ok = false
        for _, s in ipairs(SUBS) do if s.key == key then ok = true end end
        if not ok then key = "inventory" end
        active = key
        for _, t in ipairs(tabs) do t:SetActive(t.key == key) end
        for k, p in pairs(panels) do if k ~= key then p:Hide() end end
        local p = panels[key]
        if not built[key] then
            built[key] = true
            for _, s in ipairs(SUBS) do if s.key == key then s.build(p, api) end end
        end
        p:Show()
        if p.Draw then GuildOS:SafeCall(p.Draw) end
    end
    api.Prefill = function(key, id)
        select(key)
        if panels[key].Prefill then panels[key].Prefill(id) end
    end

    local prev
    for _, s in ipairs(SUBS) do
        local p = CreateFrame("Frame", nil, container)
        p:SetPoint("TOPLEFT", 0, -SUB_H)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        p:Hide()
        p:SetScript("OnShow", function(self) if self.Draw then GuildOS:SafeCall(self.Draw) end end)
        panels[s.key] = p
        local tab = UI:CreateTab(subBar, s.label, 100, true)
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 2, 0) else tab:SetPoint("LEFT", 4, 0) end
        tab.key = s.key
        tab:SetScript("OnClick", function() select(s.key) end)
        tabs[#tabs + 1] = tab
        prev = tab
    end

    -- Redraw what shows, at most a few times a second while the bank is busy.
    GuildOS.GuildBank.uiRefresh = function()
        if not container:IsVisible() then return end
        GuildOS:Coalesce("gbank.ui", 0.3, function()
            local p = active and panels[active]
            if p and p:IsVisible() and p.Draw then GuildOS:SafeCall(p.Draw) end
        end)
    end

    container:SetScript("OnShow", function() if not active then select("inventory") end end)
    select("inventory")
    container.SelectSub = select
    container.ActiveSub = function() return active end
    container.panels = panels
end

----------------------------------------------------------------------
-- The bar under the game's guild bank
----------------------------------------------------------------------
local bar
local function buildBar()
    local B = Bank()
    bar = CreateFrame("Frame", "GuildOSGuildBankBar", UIParent, "BackdropTemplate")
    bar:SetHeight(BAR_H + 8)
    bar:SetFrameStrata("HIGH")
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(bar) })
    bar:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 0.97)
    bar:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    local mark = UI:CreateText(bar, "GUILD OS", 12)
    GuildOS:ApplyFont(mark, 12, "sectionTitle")
    mark:SetPoint("LEFT", 10, 0)
    local one = UI:CreateButton(bar, L["Organize tab"], 120, BAR_H - 4)
    UI:SetButtonVariant(one, "primary")
    one:SetPoint("LEFT", mark, "RIGHT", 12, 0)
    one:SetScript("OnClick", function() B:StartSort(GuildOS.Compat.GuildBankCurrentTab() or 1) end)
    local all = UI:CreateButton(bar, L["Organize all"], 110, BAR_H - 4)
    all:SetPoint("LEFT", one, "RIGHT", 6, 0)
    all:SetScript("OnClick", function() B:StartSort(B:OrganizableTabs()) end)
    local pause = UI:CreateButton(bar, L["Pause"], 70, BAR_H - 4)
    pause:SetPoint("LEFT", one, "RIGHT", 6, 0)
    pause:SetScript("OnClick", function()
        local run = B:SortState()
        if run then B:PauseSort(not run.paused) end
    end)
    local stop = UI:CreateButton(bar, L["Stop"], 70, BAR_H - 4)
    UI:SetButtonVariant(stop, "danger")
    stop:SetPoint("LEFT", pause, "RIGHT", 6, 0)
    stop:SetScript("OnClick", function() B:StopSort("cancel") end)
    local open = UI:CreateButton(bar, L["Open in Guild OS"], 130, BAR_H - 4)
    open:SetPoint("RIGHT", -6, 0)
    open:SetScript("OnClick", function() if UI.OpenWindow then UI:OpenWindow("bank", "tabs") end end)
    local status = UI:CreateText(bar, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    status:SetPoint("LEFT", all, "RIGHT", 12, 0)
    status:SetPoint("RIGHT", open, "LEFT", -12, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    local progress = UI:CreateProgressBar(bar, 100, 4)
    progress:SetPoint("BOTTOMLEFT", 1, 1)
    progress:SetPoint("BOTTOMRIGHT", -1, 1)

    function bar:Place()
        self:ClearAllPoints()
        local host = GuildBankFrame
        if host and host:IsShown() then
            self:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -4)
            self:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, -4)
        else
            self:SetPoint("TOP", UIParent, "TOP", 0, -120)
            self:SetWidth(640)
        end
    end

    function bar:Draw()
        local run = B:SortState()
        local tab = GuildOS.Compat.GuildBankCurrentTab() or 1
        one:SetShown(not run)
        all:SetShown(not run)
        pause:SetShown(run ~= nil)
        stop:SetShown(run ~= nil)
        progress:SetShown(run ~= nil)
        status:ClearAllPoints()
        status:SetPoint("LEFT", run and stop or all, "RIGHT", 12, 0)
        status:SetPoint("RIGHT", open, "LEFT", -12, 0)
        if run then
            pause.label:SetText(run.paused and L["Resume"] or L["Pause"])
            local total = math.max(1, run.total or 1)
            progress:SetProgress((run.moves or 0) / total)
            status:SetText(string.format(L["Tab %d: move %d of about %d"], run.tab or tab, run.moves or 0, total)
                .. (#run.queue > 0 and string.format(L[" · %d tabs to go"], #run.queue) or ""))
        else
            local can, why = B:CanOrganize(tab)
            one:SetEnabled(can)
            all:SetEnabled(#B:OrganizableTabs() > 0)
            status:SetText(can and L["Merges stacks and sorts this tab."] or (why or ""))
        end
    end
    return bar
end

-- The bank opened and closed: dock the bar, take it away.
GuildOS.GuildBank.bankOpened = function()
    if GuildOS:GetSetting("gbankBar") == false then return end
    local b = bar or buildBar()
    -- The game builds its bank frame as it opens: place the bar a moment later.
    GuildOS.Compat.After(0.1, function() b:Place(); b:Draw(); b:Show() end)
end
GuildOS.GuildBank.bankClosed = function() if bar then bar:Hide() end end
GuildOS.GuildBank.barRefresh = function() if bar and bar:IsShown() then bar:Draw() end end
