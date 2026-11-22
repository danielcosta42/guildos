----------------------------------------------------------------------
-- Guild OS - Professions panel (WoW: Forever, issue #33)
--
-- Who in the guild makes what. A rail of professions with their coverage; a Recipes view of
-- every recipe the game has for the profession (who knows it, what it needs, what nobody
-- covers) and a Crafters view of the members with it. A recipe clicked opens in place with its
-- reagents, source and crafters, and the craft order (issue #389). Everything comes from GuildOS.ProfDirectory; this file only draws.
-- Replaces the Recipes panel on Forever (UI/Features.lua).
----------------------------------------------------------------------
if GuildOS.Client.isAnniversary then return end

local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local RAIL_W     = 176
local RAIL_ROW   = 36
local SIDE       = 10
local TOP        = 8
local TITLE_H    = 30
local TOOLS_H    = 30
local HEADER_H   = 24
local ROW_H      = 24
local FOOTER_H   = 24
local COL_GAP    = 10
local ROW_INSET  = 8
local ROW_GUTTER = 12
local WHITE8     = "Interface\\Buttons\\WHITE8x8"
local QUESTION   = "Interface\\Icons\\INV_Misc_QuestionMark"

local PROF_ICONS = {
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [333] = "Interface\\Icons\\Trade_Engraving",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [182] = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
    [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [186] = "Interface\\Icons\\Trade_Mining",
    [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    [197] = "Interface\\Icons\\Trade_Tailoring",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [356] = "Interface\\Icons\\Trade_Fishing",
    -- Retail's (issue #167).
    [755] = "Interface\\Icons\\INV_Misc_Gem_01",
    [773] = "Interface\\Icons\\INV_Inscription_Tradeskill01",
}
local ALL_ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- Resolved per resize by UI:ResolveColumns. The same four cell keys serve both views.
local COLUMNS = {
    recipes = {
        { key = "name",  min = 200, weight = 3, priority = 100, required = true },
        { key = "skill", min = 64,  weight = 0, priority = 70 },
        { key = "who",   min = 150, weight = 2, priority = 90,  required = true },
        { key = "req",   min = 140, weight = 1, priority = 40 },
    },
    crafters = {
        { key = "name",  min = 160, weight = 2, priority = 100, required = true },
        { key = "skill", min = 150, weight = 1, priority = 90,  required = true },
        { key = "req",   min = 120, weight = 1, priority = 50 },
        { key = "who",   min = 70,  weight = 0, priority = 60 },
    },
}
local HEADERS = {
    recipes  = { name = L["RECIPE"], skill = L["SKILL"], who = L["CRAFTERS"], req = L["REQUIRES"] },
    crafters = { name = L["MEMBER"], skill = L["LEVEL"], who = L["RECIPES"], req = L["SPECIALIZATION"] },
}

local function hex(c) return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
local function classHex(class)
    local r, g, b = GuildOS:GetClassColor(class)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function itemIcon(id)
    return id and id > 0 and select(10, GuildOS.Compat.GetItemInfo(id)) or nil
end

local function recipeIcon(e)
    return itemIcon(e.out) or select(3, GuildOS.Compat.GetSpellInfo(e.id)) or QUESTION
end

local function sourceText(e)
    if e.src == 3 then return L["Automatic"] end
    if e.src == 2 then
        local link = e.recipeItem and e.recipeItem > 0 and select(2, GuildOS.Compat.GetItemInfo(e.recipeItem))
        return link or L["Recipe item"]
    end
    return L["Trainer"]
end

local function specName(id)
    return id and id > 0 and (GuildOS.Compat.GetSpellInfo(id) or ("#" .. id)) or nil
end

local function stationName(focus)
    local name = focus and focus > 0 and GuildOS.ProfCatalog.stations[focus]
    return name and name ~= "" and L[name] or nil
end

local function requiresText(e)
    local parts = {}
    parts[#parts + 1] = specName(e.spec)
    parts[#parts + 1] = stationName(e.focus)
    return table.concat(parts, " · ")
end

-- The crafters of a recipe, online first, as { name, class, online } from the roster map.
local function crafterList(keys, who)
    local list = {}
    for _, key in ipairs(keys) do
        local w = who[key] or {}
        list[#list + 1] = { key = key, name = w.name or key:match("^([^-]+)") or key, class = w.class,
                            online = w.online == true }
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return list
end

local function whoText(keys, who)
    if #keys == 0 then return "|cff" .. hex(C.red) .. L["nobody"] .. "|r" end
    local list = crafterList(keys, who)
    local parts = {}
    for i = 1, math.min(3, #list) do
        local e = list[i]
        parts[i] = e.online and ("|cff" .. classHex(e.class) .. e.name .. "|r") or ("|cff" .. hex(C.labelDim) .. e.name .. "|r")
    end
    local text = table.concat(parts, ", ")
    if #list > 3 then text = text .. string.format(" |cff%s+%d|r", hex(C.labelDim), #list - 3) end
    return text
end

-- What the opened recipe says besides its materials: where it is learned, the skill, the station.
local function metaText(e)
    local parts = { sourceText(e) }
    if e.reqSkill and e.reqSkill > 0 then parts[#parts + 1] = string.format(L["skill %d"], e.reqSkill) end
    parts[#parts + 1] = specName(e.spec)
    parts[#parts + 1] = stationName(e.focus)
    return table.concat(parts, " · ")
end

----------------------------------------------------------------------
-- The panel
----------------------------------------------------------------------
function GuildOS:CreateProfessionsPanel(parent, _win)
    local D = GuildOS.ProfDirectory
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local state = { line = nil, mode = "recipes", filter = "all", query = "", results = {}, who = {},
                    open = nil, item = nil }

    ----------------------------------------------------------------
    -- Rail: every profession with its coverage
    ----------------------------------------------------------------
    local rail = CreateFrame("Frame", nil, panel)
    rail:SetPoint("TOPLEFT", SIDE, -TOP)
    rail:SetPoint("BOTTOMLEFT", SIDE, SIDE)
    rail:SetWidth(RAIL_W)
    local railButtons = {}

    local function RailButton(index, line)
        local b = CreateFrame("Button", nil, rail, "BackdropTemplate")
        b:SetSize(RAIL_W, RAIL_ROW - 2)
        b:SetPoint("TOPLEFT", 0, -((index - 1) * RAIL_ROW))
        b:SetBackdrop({ bgFile = WHITE8 })
        b.line = line
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexture(line and PROF_ICONS[line] or ALL_ICON)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = UI:CreateText(b, line and D.DisplayName(line) or L["All professions"], 11,
            C.text.r, C.text.g, C.text.b)
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
        name:SetWidth(RAIL_W - 42)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        b.icon, b.name = icon, name
        b.sub = UI:CreateText(b, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        b.sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, -2)
        b.sub:SetWidth(RAIL_W - 42)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetWordWrap(false)
        b:SetScript("OnClick", function()
            state.line, state.item = line, nil
            panel:Refresh(true)
        end)
        b:SetScript("OnEnter", function(self)
            if state.line ~= self.line then
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            end
        end)
        b:SetScript("OnLeave", function() panel:PaintRail() end)
        railButtons[#railButtons + 1] = b
    end

    RailButton(1, nil)
    for i, line in ipairs(D.Lines()) do RailButton(i + 1, line) end

    function panel:PaintRail()
        for _, b in ipairs(railButtons) do
            if b.line then
                local cov = D.Coverage(b.line)
                local pct = cov.total > 0 and math.floor(cov.covered * 100 / cov.total + 0.5) or 0
                b.sub:SetText(string.format(L["%d crafters · %d%%"], cov.crafters, pct))
            end
            if state.line == b.line then
                b:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1)
            else
                b:SetBackdropColor(0, 0, 0, 0)
            end
        end
        -- Every recipe once: one two professions learn is not counted twice.
        local all = D.CoverageAll()
        railButtons[1].sub:SetText(string.format(L["%d / %d recipes"], all.covered, all.total))
        return all.covered, all.total
    end

    ----------------------------------------------------------------
    -- Main area: title, view tabs, search and filters
    ----------------------------------------------------------------
    local main = CreateFrame("Frame", nil, panel)
    main:SetPoint("TOPLEFT", rail, "TOPRIGHT", 12, 0)
    main:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE, SIDE)

    local title = UI:CreateTitle(main, "", 14)
    title:SetPoint("TOPLEFT", 0, -2)

    local tabCrafters = UI:CreateTab(main, L["Crafters"], 90, true)
    tabCrafters:SetPoint("TOPRIGHT", 0, 0)
    local tabRecipes = UI:CreateTab(main, L["Recipes"], 90, true)
    tabRecipes:SetPoint("RIGHT", tabCrafters, "LEFT", -4, 0)
    tabRecipes:SetScript("OnClick", function() state.mode = "recipes"; panel:Refresh(true) end)
    -- /gos craft: who can craft an item, guild, alliance and realm, as the Recipes tab offers it (#142).
    local finderBtn = UI:CreateButton(main, L["Find a Crafter"], 120, 22)
    finderBtn:SetPoint("RIGHT", tabRecipes, "LEFT", -12, 0)
    finderBtn:SetScript("OnClick", function() if GuildOS.ShowCraftFinder then GuildOS:ShowCraftFinder() end end)
    -- A narrow window cuts the title short rather than lay the button over it.
    title:SetPoint("TOPRIGHT", finderBtn, "TOPLEFT", -8, 1)   -- the tabs are 28 tall, the button 22
    title:SetWordWrap(false)
    title:SetJustifyH("LEFT")
    tabCrafters:SetScript("OnClick", function() state.mode = "crafters"; panel:Refresh(true) end)

    local tools = CreateFrame("Frame", nil, main)
    tools:SetPoint("TOPLEFT", 0, -TITLE_H)
    tools:SetPoint("TOPRIGHT", 0, -TITLE_H)
    tools:SetHeight(TOOLS_H)

    -- The shared field (#371). Its hint is drawn here, as the field's own is (Sans 12 in `textSoft`,
    -- 6px in), because this one also goes when the box is too narrow to hold it.
    local search = UI:CreateInput(tools, 220, 24, { max = 50 })
    search:SetPoint("LEFT", 0, 0)
    local placeholder = UI:CreateText(search, L["Search recipes..."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    placeholder:SetPoint("LEFT", 6, 0)
    -- The placeholder only while the box is empty and wide enough to hold it.
    local function paintPlaceholder()
        placeholder:SetShown((search:GetText() or "") == "" and (search:GetWidth() or 0) >= 130)
    end
    -- Hooked, not set: the field keeps its own Escape, focus and text handlers.
    search:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        paintPlaceholder()
        state.query = text
        if text ~= "" then state.item = nil end
        panel:Refresh(true)
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local filterTabs = {}
    local FILTERS = { { "all", L["All"] }, { "guild", L["In the guild"] }, { "gaps", L["Nobody crafts"] } }
    -- Craft orders (issue #389): the recipes I make, and the ones someone ordered.
    if GuildOS.CraftOrders then
        FILTERS[#FILTERS + 1] = { "mine", L["I craft"] }
        FILTERS[#FILTERS + 1] = { "orders", L["With orders"] }
    end
    local previous
    for i = #FILTERS, 1, -1 do
        local key, label = FILTERS[i][1], FILTERS[i][2]
        local t = UI:CreateTab(tools, label, 60, true)
        if previous then t:SetPoint("RIGHT", previous, "LEFT", -4, 0) else t:SetPoint("RIGHT", 0, 0) end
        t.key = key
        t:SetScript("OnClick", function() state.filter = key; panel:Refresh(true) end)
        filterTabs[#filterTabs + 1] = t
        previous = t
    end

    ----------------------------------------------------------------
    -- Header strip and the list
    ----------------------------------------------------------------
    -- The shared table header (#371): no fill, a 1px rule under the column labels.
    local header = UI:CreateTableHeader(main, HEADER_H)
    header:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -4)
    header:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", 0, -4)
    local headerCells = {}
    for _, key in ipairs({ "name", "skill", "who", "req" }) do
        local fs = UI:CreateHeaderText(header, "", 10)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        headerCells[key] = fs
    end

    local list = CreateFrame("Frame", nil, main)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, FOOTER_H)
    local scroll = CreateFrame("ScrollFrame", "GuildOSProfessionsScroll", list, "FauxScrollFrameTemplate")
    scroll:SetAllPoints()
    UI:SkinScrollBar(scroll, "GuildOSProfessionsScroll")
    -- The opened recipe sits over the rows it takes; what scrolls past the list's edge is cut.
    if list.SetClipsChildren then list:SetClipsChildren(true) end
    local detail = GuildOS.CreateCraftDetail and GuildOS:CreateCraftDetail(list)
    if detail then detail:SetFrameLevel(list:GetFrameLevel() + 5) end

    local empty = UI:CreateText(list, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("CENTER", 0, 20)

    local footer = UI:CreateText(main, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
    footer:SetPoint("BOTTOMLEFT", 0, 4)

    local rows = {}
    local function CreateRow(index)
        local row = CreateFrame("Button", nil, list, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -ROW_GUTTER, -((index - 1) * ROW_H))
        row:SetBackdrop({ bgFile = WHITE8 })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetSize(8, 8)
        row.dot:SetTexture(WHITE8)
        row.bar = UI:CreateProgressBar(row, 100, 8)
        for _, k in ipairs({ "t1", "t2", "t3", "t4" }) do
            local fs = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(fs, k == "t1" and 11 or 10)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row[k] = fs
        end

        function row:ApplyColumns(layout, mode)
            local by = layout.byKey
            local c = by.name or { shown = false, x = 0, w = 0 }
            self.icon:ClearAllPoints()
            self.icon:SetPoint("LEFT", ROW_INSET + c.x, 0)
            self.dot:ClearAllPoints()
            self.dot:SetPoint("LEFT", ROW_INSET + c.x + 5, 0)
            self.t1:ClearAllPoints()
            self.t1:SetPoint("LEFT", ROW_INSET + c.x + 24, 0)
            self.t1:SetWidth(math.max(20, c.w - 24))
            local s = by.skill or { shown = false, x = 0, w = 0 }
            self.t2:SetShown(s.shown)
            if s.shown then
                self.t2:ClearAllPoints()
                if mode == "crafters" then
                    self.bar:ClearAllPoints()
                    self.bar:SetPoint("LEFT", ROW_INSET + s.x, 0)
                    self.bar:SetWidth(math.max(20, s.w - 70))
                    self.t2:SetPoint("LEFT", ROW_INSET + s.x + s.w - 64, 0)
                    self.t2:SetWidth(64)
                else
                    self.t2:SetPoint("LEFT", ROW_INSET + s.x, 0)
                    self.t2:SetWidth(s.w)
                end
            end
            self.barAllowed = mode == "crafters" and s.shown
            for key, fs in pairs({ who = self.t3, req = self.t4 }) do
                local col = by[key] or { shown = false, x = 0, w = 0 }
                fs:SetShown(col.shown)
                if col.shown then
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", ROW_INSET + col.x, 0)
                    fs:SetWidth(col.w)
                end
            end
        end

        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            local e = self.data
            if e and state.mode == "recipes" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if e.out and e.out > 0 then
                    GameTooltip:SetItemByID(e.out)
                else
                    GameTooltip:SetHyperlink("enchant:" .. e.id)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            local bg = (index % 2 == 0) and C.row2 or C.row1
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            local e = self.data
            if not (e and state.mode == "recipes" and detail) then return end
            if IsShiftKeyDown() and e.out and e.out > 0 and HandleModifiedItemClick then
                local _, link = GuildOS.Compat.GetItemInfo(e.out)
                if link then HandleModifiedItemClick(link) end
                return
            end
            if state.open == e.id then state.open = nil else state.open = e.id end
            state.openTo = nil
            panel:Refresh()
        end)
        rows[index] = row
        return row
    end

    panel.visibleRows = 0
    local function AcquireRows(n)
        for i = #rows + 1, n do CreateRow(i) end
        for i = n + 1, #rows do rows[i]:Hide() end
        panel.visibleRows = n
    end

    function panel:UpdateRows()
        local offset = FauxScrollFrame_GetOffset(scroll)
        local total = #state.results
        local visible = self.visibleRows or 0
        FauxScrollFrame_Update(scroll, total, visible, ROW_H)
        for i = 1, visible do
            local row, e = rows[i], state.results[offset + i]
            row.data = e
            if not e or e.__detail then
                row.data = nil
                row:Hide()
            else
                row:Show()
                local bg = (i % 2 == 0) and C.row2 or C.row1
                row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
                if state.mode == "recipes" then
                    row.icon:Show()
                    row.dot:Hide()
                    row.bar:Hide()
                    row.icon:SetTexture(recipeIcon(e))
                    row.t1:SetText(e.name .. panel:Badges(e))
                    row.t1:SetTextColor(C.text.r, C.text.g, C.text.b)
                    if e.id == state.open then
                        row:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
                    end
                    -- A few recipes give no skill: the client's table says 0 for both. The range in
                    -- `text` to `label`, not gold (#371).
                    row.t2:SetText(e.grey > 0 and string.format("|cff%s%d|r–|cff%s%d|r", hex(C.text), e.yellow,
                        hex(C.label), e.grey) or "")
                    row.t3:SetText(whoText(e.crafters, state.who))
                    row.t4:SetText(requiresText(e))
                    row.t4:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
                else
                    row.icon:Hide()
                    row.dot:Show()
                    local dc = e.online and C.online or C.offline
                    row.dot:SetVertexColor(dc.r, dc.g, dc.b, e.online and 1 or 0.5)
                    row.t1:SetText("|cff" .. classHex(e.class) .. e.name .. "|r")
                    if e.native then
                        row.bar:Hide()
                        row.t2:SetText("|cff" .. hex(C.labelDim) .. L["no addon"] .. "|r")
                    else
                        row.bar:SetShown(row.barAllowed)
                        row.bar:SetProgress((e.max or 0) > 0 and (e.rank or 0) / e.max or 0)
                        row.t2:SetText(string.format("%d / %d", e.rank or 0, e.max or 0))
                    end
                    row.t3:SetText(e.native and "" or tostring(e.count))
                    row.t4:SetText(specName(e.spec) or "")
                    row.t4:SetTextColor(C.text.r, C.text.g, C.text.b)
                end
            end
        end
        local message
        if total == 0 then
            if state.mode == "crafters" and not state.line then
                message = L["Pick a profession on the left."]
            elseif state.mode == "crafters" then
                message = L["Nobody in the guild has this profession yet."]
            else
                message = L["No recipes match."]
            end
        end
        empty:SetText(message or "")
        empty:SetShown(message ~= nil)
        if detail then
            UI.PlaceDetail(detail, list, state.detailAt, state.detailRows or 0, offset, visible, ROW_H, ROW_GUTTER)
        end
    end

    -- The marks after a recipe's name: I make it, and how many orders ask for it.
    function panel:Badges(e)
        local O = GuildOS.CraftOrders
        if not O then return "" end
        local out = ""
        if state.mine and state.mine[e.id] then out = out .. "  " .. "|cff" .. hex(C.ok) .. L["you craft"] .. "|r" end
        local n = e.out and state.byItem and state.byItem[e.out]
        if n and n > 0 then out = out .. "  " .. "|cff" .. hex(C.gold) .. string.format(L["%d orders"], n) .. "|r" end
        return out
    end

    -- The opened recipe's block: its item, its crafters online first, what it takes.
    function panel:PaintDetail(fresh)
        if not detail then return end
        if state.mode ~= "recipes" or not state.open then detail:Hide(); return end
        local e
        for _, x in ipairs(state.results) do if not x.__detail and x.id == state.open then e = x end end
        if not e then detail:Hide(); return end
        local list2 = crafterList(e.crafters, state.who)
        detail:SetRecipe({ id = e.id, recipeId = e.id, item = (e.out and e.out > 0) and e.out or nil, crafters = list2,
                           meta = metaText(e) }, state.openTo, fresh)
    end

    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function() panel:UpdateRows() end)
    end)

    ----------------------------------------------------------------
    -- State to screen
    ----------------------------------------------------------------
    function panel:Refresh(resetScroll)
        state.who = D.Roster()
        if state.mode == "recipes" then
            local O = GuildOS.CraftOrders
            local base = (state.filter == "mine" or state.filter == "orders") and "guild" or state.filter
            local rows0 = D.RecipeRows(state.line, base, state.item and "" or state.query)
            state.byItem = O and O:OrdersByItem() or {}
            local me = O and O:MyKey()
            state.mine = {}
            for _, e in ipairs(rows0) do
                for _, k in ipairs(e.crafters) do if k == me then state.mine[e.id] = true end end
            end
            local out = {}
            for _, e in ipairs(rows0) do
                local keep = (state.filter ~= "mine" or state.mine[e.id])
                    and (state.filter ~= "orders" or (e.out and (state.byItem[e.out] or 0) > 0))
                    and (not state.item or e.out == state.item)
                if keep then out[#out + 1] = e end
            end
            local at, n
            if UI.WithDetail then
                out, at, n = UI.WithDetail(out, function(e) return e.id == state.open end, ROW_H)
            end
            state.results, state.detailAt, state.detailRows = out, at, n
            if not at then state.open = nil end
        else
            state.results = state.line and D.MemberRows(state.line) or {}
            state.detailAt, state.detailRows = nil, nil
        end
        if resetScroll then
            scroll:SetVerticalScroll(0)
            if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(scroll, 0) end
        end
        local itemName = state.item and (GuildOS.Compat.GetItemInfo(state.item) or ("item:" .. state.item))
        title:SetText(itemName and string.format(L["Recipes for %s"], itemName)
            or (state.line and D.DisplayName(state.line)) or L["All professions"])
        tabRecipes:SetActive(state.mode == "recipes")
        tabCrafters:SetActive(state.mode == "crafters")
        tools:SetShown(state.mode == "recipes")
        for _, t in ipairs(filterTabs) do t:SetActive(state.filter == t.key) end
        local known, total = self:PaintRail()
        if state.line then
            local cov = D.Coverage(state.line)
            footer:SetText(string.format(L["The guild knows %d of %d recipes · %d crafters"],
                cov.covered, cov.total, cov.crafters))
        else
            footer:SetText(string.format(L["The guild knows %d of %d recipes"], known, total))
        end
        self:Relayout()
        self:PaintDetail()
    end

    -- Open the recipe that makes `itemId` (the Crafts tab's Alt-click, an order's card). False when
    -- the catalog has none.
    function panel:FocusItem(itemId, toKey)
        if #D.ItemRecipes(itemId) == 0 then return false end
        state.mode, state.line, state.filter, state.query, state.item = "recipes", nil, "all", "", itemId
        search:SetText("")
        state.item = itemId          -- the search box's handler cleared it
        -- The recipe the crafter it goes to knows, else the one the guild knows most (issue #396).
        local O = GuildOS.CraftOrders
        state.open = (O and O:RecipeFor(itemId, toKey)) or D.ItemRecipes(itemId)[1]
        self:Refresh(true)
        state.openTo = toKey
        self:PaintDetail(true)
        return true
    end

    function panel:Relayout(w, h)
        w = w or parent:GetWidth()
        h = h or parent:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end
        local inner = w - SIDE * 2 - RAIL_W - 12

        -- The rail shrinks its rows to the height it has; the second line goes when they get short.
        local railRow = math.max(20, math.min(RAIL_ROW, math.floor((h - TOP - SIDE) / #railButtons)))
        for i, b in ipairs(railButtons) do
            b:SetHeight(railRow - 2)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -((i - 1) * railRow))
            local tall = railRow >= 30
            b.sub:SetShown(tall)
            b.icon:SetSize(tall and 22 or 16, tall and 22 or 16)
            b.name:ClearAllPoints()
            if tall then
                b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 2)
            else
                b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
            end
        end
        panel.railRow = railRow

        -- The search box gives way to the filter tabs in a narrow window; where even that is not
        -- enough, the order filters (issue #389) go first, the chosen one staying.
        local function width(keepAll)
            local sum = 0
            for _, t in ipairs(filterTabs) do
                local extra = t.key == "mine" or t.key == "orders"
                t.fits = keepAll or not extra or state.filter == t.key
                if t.fits then sum = sum + (t:GetWidth() or 0) + 4 end
            end
            return sum
        end
        local filtersW = width(true)
        if inner - filtersW - 12 < 60 then filtersW = width(false) end
        local previousTab
        for _, t in ipairs(filterTabs) do          -- built right to left
            t:SetShown(t.fits)
            if t.fits then
                t:ClearAllPoints()
                if previousTab then t:SetPoint("RIGHT", previousTab, "LEFT", -4, 0) else t:SetPoint("RIGHT", 0, 0) end
                previousTab = t
            end
        end
        search:SetWidth(math.max(60, math.min(220, inner - filtersW - 12)))
        paintPlaceholder()

        local layout = UI:ResolveColumns(COLUMNS[state.mode], inner - ROW_GUTTER - ROW_INSET, COL_GAP)
        for _, col in ipairs(layout) do
            local fs = headerCells[col.key]
            fs:SetShown(col.shown)
            if col.shown then
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", ROW_INSET + col.x, 0)
                fs:SetWidth(col.w)
                fs:SetText(HEADERS[state.mode][col.key])
            end
        end
        local listTop = TOP + TITLE_H + TOOLS_H + 4 + HEADER_H
        AcquireRows(UI:ResolveRows(h - listTop - FOOTER_H - SIDE, ROW_H, 0))
        for i = 1, self.visibleRows do rows[i]:ApplyColumns(layout, state.mode) end
        self:UpdateRows()
    end

    parent:SetScript("OnShow", function() panel:Refresh() end)
    UI:MakeResponsive(parent, function(_, w, h) panel:Relayout(w, h) end)

    -- Items the client had not cached arrive later: repaint names, icons and links once they do.
    local itemEvents = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(itemEvents, "GET_ITEM_INFO_RECEIVED")
    itemEvents:SetScript("OnEvent", function()
        if panel.itemsPending or not parent:IsVisible() then return end
        panel.itemsPending = true
        GuildOS.Compat.After(0.3, function()
            panel.itemsPending = false
            panel:UpdateRows()
            panel:PaintDetail()
        end)
    end)
    panel.itemEvents = itemEvents

    -- Reachable by the caller and by tools/professions-panel.lua, which drives the panel like a user.
    panel.state, panel.railButtons, panel.rows, panel.detail = state, railButtons, rows, detail
    panel.tabRecipes, panel.tabCrafters, panel.search, panel.filterTabs = tabRecipes, tabCrafters, search, filterTabs
    return panel
end
