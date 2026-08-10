----------------------------------------------------------------------
-- BRutus Guild Manager - Recipes Panel
-- Searchable guild recipe browser, grouped by profession
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L

local ROW_HEIGHT = 24

-- Resolved per resize by UI:ResolveColumns (UI/Layout.lua). The online
-- dot rides inside the recipe cell, so it cannot be lost to a narrow
-- window. PROFESSION is the one that goes: the icon in the row already
-- says which profession it is.
local COLUMNS = {
    { key = "recipe",     min = 200, weight = 3, priority = 100, required = true },
    { key = "profession", min = 130, weight = 0, priority = 40 },
    { key = "crafters",   min = 140, weight = 2, priority = 60,  required = true },
}

local COL_GAP    = 10
local ROW_INSET  = 10   -- x of the first cell inside a row
local SIDE_MARGIN = 10  -- panel edge to the list
local ROW_GUTTER = 10   -- rows stop short of the scrollbar
local TOP_PAD    = 8    -- panel top to the top bar
local TITLE_H    = 26   -- title + search row, above the profession filters
local HEADER_H   = 24   -- column header strip
local LIST_BOTTOM = 40  -- footer strip under the list

----------------------------------------------------------------------
-- Profession icons (TBC tradeskill textures)
----------------------------------------------------------------------
local PROF_ICONS = {
    ["Alchemy"]         = "Interface\\Icons\\Trade_Alchemy",
    ["Blacksmithing"]   = "Interface\\Icons\\Trade_BlackSmithing",
    ["Enchanting"]      = "Interface\\Icons\\Trade_Engraving",
    ["Engineering"]     = "Interface\\Icons\\Trade_Engineering",
    ["Herbalism"]       = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
    ["Jewelcrafting"]   = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Leatherworking"]  = "Interface\\Icons\\Trade_LeatherWorking",
    ["Skinning"]        = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Tailoring"]       = "Interface\\Icons\\Trade_Tailoring",
    ["Cooking"]         = "Interface\\Icons\\INV_Misc_Food_15",
    ["First Aid"]       = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    ["Fishing"]         = "Interface\\Icons\\Trade_Fishing",
}

local PROF_COLORS = {
    ["Alchemy"]         = { r = 0.90, g = 0.75, b = 0.20 },
    ["Blacksmithing"]   = { r = 0.70, g = 0.50, b = 0.30 },
    ["Enchanting"]      = { r = 0.80, g = 0.40, b = 0.80 },
    ["Engineering"]     = { r = 0.80, g = 0.65, b = 0.20 },
    ["Herbalism"]       = { r = 0.30, g = 0.85, b = 0.30 },
    ["Jewelcrafting"]   = { r = 0.85, g = 0.25, b = 0.35 },
    ["Leatherworking"]  = { r = 0.65, g = 0.50, b = 0.30 },
    ["Skinning"]        = { r = 0.65, g = 0.55, b = 0.35 },
    ["Tailoring"]       = { r = 0.60, g = 0.45, b = 0.80 },
    ["Cooking"]         = { r = 0.85, g = 0.55, b = 0.25 },
    ["First Aid"]       = { r = 0.90, g = 0.30, b = 0.30 },
    ["Fishing"]         = { r = 0.30, g = 0.60, b = 0.85 },
}

----------------------------------------------------------------------
-- Create the Recipes panel
----------------------------------------------------------------------
function BRutus:CreateRecipesPanel(parent, _mainFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- State
    local state = {
        query = "",
        profFilter = "All",
        results = {},
        scrollOffset = 0,
    }

    ----------------------------------------------------------------
    -- Top bar: search + profession filters
    ----------------------------------------------------------------
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)
    topBar:SetHeight(60)

    -- Title
    local title = UI:CreateTitle(topBar, L["Guild Recipes"], 14)
    title:SetPoint("TOPLEFT", 0, 0)

    -- Result count
    local countText = UI:CreateText(topBar, "", 10, C.silver.r, C.silver.g, C.silver.b)
    countText:SetPoint("LEFT", title, "RIGHT", 12, 0)

    -- Search box
    local searchBox = CreateFrame("EditBox", "BRutusRecipeSearch", topBar, "BackdropTemplate")
    searchBox:SetSize(220, 24)
    searchBox:SetPoint("TOPRIGHT", 0, 0)
    searchBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    searchBox:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    searchBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    searchBox:SetTextInsets(8, 8, 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY")
    searchPlaceholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchPlaceholder:SetPoint("LEFT", 8, 0)
    searchPlaceholder:SetTextColor(0.4, 0.4, 0.4)
    searchPlaceholder:SetText(L["Search recipes..."])

    -- Realm-wide crafter finder (guild + mesh) — opens the CraftFinder popup.
    local realmBtn = UI:CreateButton(topBar, L["Find a Crafter"], 120, 24)
    realmBtn:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    realmBtn:SetScript("OnClick", function() BRutus:ShowCraftFinder() end)

    -- Profession filter buttons row
    -- Anchored on the left only: UI:FlowBar reads GetWidth to decide where
    -- to wrap, and a frame pinned on both sides reports a stale width in
    -- the same frame the container was resized.
    local filterRow = CreateFrame("Frame", nil, topBar)
    filterRow:SetPoint("TOPLEFT", 0, -TITLE_H)
    filterRow:SetSize(400, 26)

    local filterButtons = {}

    local function RefreshResults()
        if not BRutus.RecipeTracker then
            state.results = {}
        else
            state.results = BRutus.RecipeTracker:Search(state.query, state.profFilter)
        end
        state.scrollOffset = 0
        countText:SetText(string.format(L["|cff888888%d results|r"], #state.results))
    end

    local function CreateFilterButton(profName)
        local btn = CreateFrame("Button", nil, filterRow, "BackdropTemplate")
        btn:SetHeight(22)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        btn:SetBackdropColor(0.100, 0.100, 0.130, 1.0)
        btn.profName = profName

        local icon
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")

        if profName == "All" then
            btn:SetWidth(40)
            label:SetPoint("CENTER")
            label:SetText(L["All"])
            label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        else
            local iconTex = PROF_ICONS[profName]
            if iconTex then
                icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetSize(16, 16)
                icon:SetPoint("CENTER")
                icon:SetTexture(iconTex)
            else
                label:SetPoint("CENTER")
                label:SetText(profName:sub(1, 3))
                local pc = PROF_COLORS[profName] or C.silver
                label:SetTextColor(pc.r, pc.g, pc.b)
            end
            btn:SetWidth(26)
        end

        btn.label = label
        btn.icon = icon
        -- Position comes from UI:FlowBar, which wraps the row when the
        -- window is too narrow to hold every profession on one line.

        btn:SetScript("OnClick", function()
            state.profFilter = profName
            -- Update active state visuals
            for _, fb in ipairs(filterButtons) do
                if fb.profName == state.profFilter then
                    fb:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
                else
                    fb:SetBackdropColor(0.100, 0.100, 0.130, 1.0)
                end
            end
            RefreshResults()
            panel:UpdateRows()
        end)
        btn:SetScript("OnEnter", function(self)
            if state.profFilter ~= self.profName then
                self:SetBackdropColor(0.160, 0.150, 0.210, 1.0)
            end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(profName, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            if state.profFilter ~= self.profName then
                self:SetBackdropColor(0.100, 0.100, 0.130, 1.0)
            end
            GameTooltip:Hide()
        end)

        table.insert(filterButtons, btn)
        return btn
    end

    -- Build profession filter buttons dynamically on show
    local function RebuildFilterButtons()
        -- Hide existing
        for _, btn in ipairs(filterButtons) do btn:Hide() end
        filterButtons = {}

        -- Get known professions
        local profs = BRutus.RecipeTracker and BRutus.RecipeTracker:GetAllProfessions() or {}
        local allProfs = { "All" }
        for _, p in ipairs(profs) do
            table.insert(allProfs, p)
        end

        for _, profName in ipairs(allProfs) do
            CreateFilterButton(profName)
        end

        -- Mark active
        for _, fb in ipairs(filterButtons) do
            if fb.profName == state.profFilter then
                fb:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
            end
        end

        -- New buttons need placing straight away; the layout pass only
        -- runs on resize.
        if panel.Relayout then panel:Relayout() end
    end

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            searchPlaceholder:Hide()
        else
            searchPlaceholder:Show()
        end
        state.query = text or ""
        RefreshResults()
        panel:UpdateRows()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    ----------------------------------------------------------------
    -- Column headers
    ----------------------------------------------------------------
    local headerFrame = CreateFrame("Frame", nil, panel)
    headerFrame:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
    headerFrame:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -4)
    headerFrame:SetHeight(HEADER_H)

    local headerBg = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    headerBg:SetAllPoints()
    headerBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    -- Header cells are positioned by the layout pass, keyed the same way
    -- the row cells are so the two can never drift apart.
    local headerByKey = {
        recipe     = UI:CreateHeaderText(headerFrame, L["RECIPE"], 10),
        profession = UI:CreateHeaderText(headerFrame, L["PROFESSION"], 10),
        crafters   = UI:CreateHeaderText(headerFrame, L["CRAFTERS"], 10),
    }
    for _, fs in pairs(headerByKey) do
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end

    ----------------------------------------------------------------
    -- Scroll frame with rows
    ----------------------------------------------------------------
    local listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    listFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE_MARGIN, LIST_BOTTOM)

    local scrollFrame = CreateFrame("ScrollFrame", "BRutusRecipeScroll", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetAllPoints()
    UI:SkinScrollBar(scrollFrame, "BRutusRecipeScroll")

    -- Create row frames
    local rows = {}

    local function CreateRow(index)
        local row = CreateFrame("Button", nil, listFrame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", -ROW_GUTTER, -((index - 1) * ROW_HEIGHT))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        -- Online dot: rides inside the recipe cell
        local statusDot = row:CreateTexture(nil, "OVERLAY")
        statusDot:SetSize(8, 8)
        statusDot:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.statusDot = statusDot

        -- Recipe name
        local recipeName = row:CreateFontString(nil, "OVERLAY")
        recipeName:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        recipeName:SetJustifyH("LEFT")
        recipeName:SetWordWrap(false)
        row.recipeName = recipeName

        -- Profession icon + name
        local profIcon = row:CreateTexture(nil, "ARTWORK")
        profIcon:SetSize(16, 16)
        row.profIcon = profIcon

        local profName = row:CreateFontString(nil, "OVERLAY")
        profName:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        profName:SetPoint("LEFT", profIcon, "RIGHT", 4, 0)
        profName:SetJustifyH("LEFT")
        profName:SetWordWrap(false)
        row.profName = profName

        -- Player name
        local playerName = row:CreateFontString(nil, "OVERLAY")
        playerName:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        playerName:SetJustifyH("LEFT")
        playerName:SetWordWrap(false)
        row.playerName = playerName

        -- Place every cell from a resolved layout.
        function row:ApplyColumns(layout)
            local byKey = layout.byKey

            local rec = byKey.recipe
            if rec and rec.shown then
                self.statusDot:ClearAllPoints()
                self.statusDot:SetPoint("LEFT", ROW_INSET + rec.x, 0)
                self.recipeName:ClearAllPoints()
                self.recipeName:SetPoint("LEFT", ROW_INSET + rec.x + 22, 0)
                self.recipeName:SetWidth(math.max(20, rec.w - 22))
            end

            local prof = byKey.profession
            self.profIcon:SetShown(prof and prof.shown)
            self.profName:SetShown(prof and prof.shown)
            if prof and prof.shown then
                self.profIcon:ClearAllPoints()
                self.profIcon:SetPoint("LEFT", ROW_INSET + prof.x, 0)
                self.profName:SetWidth(math.max(20, prof.w - 20))
            end

            local cr = byKey.crafters
            if cr and cr.shown then
                self.playerName:ClearAllPoints()
                self.playerName:SetPoint("LEFT", ROW_INSET + cr.x, 0)
                self.playerName:SetWidth(cr.w)
            end
        end

        -- Whisper button
        local whisperBtn = UI:CreateButton(row, L["Whisper"], 60, 20)
        whisperBtn:SetPoint("RIGHT", -4, 0)
        whisperBtn:SetFrameLevel(row:GetFrameLevel() + 2)
        whisperBtn:Hide()
        row.whisperBtn = whisperBtn

        -- Hover helpers (prevent flicker when mouse moves to whisper button)
        local function RowEnter(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            if self.data then
                if self.data.itemId then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.data.itemId)
                    GameTooltip:Show()
                elseif self.data.spellId then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("enchant:" .. self.data.spellId)
                    GameTooltip:Show()
                end
            end
            if self.firstOnlineCrafter then
                self.whisperBtn:Show()
            end
        end
        local function RowLeave(self)
            -- Don't hide if mouse moved onto the whisper button
            if self.whisperBtn:IsMouseOver() then return end
            local bg = (index % 2 == 0) and C.row2 or C.row1
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            GameTooltip:Hide()
            self.whisperBtn:Hide()
        end

        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)

        -- When mouse leaves the whisper button, check if still on the row
        whisperBtn:HookScript("OnLeave", function(self)
            local rowParent = self:GetParent()
            if not rowParent:IsMouseOver() then
                RowLeave(rowParent)
            end
        end)

        rows[index] = row
        return row
    end

    -- Rows are pooled and grown on demand: how many exist depends on how
    -- tall the window is right now.
    panel.visibleRows = 0
    local function AcquireRows(n)
        for i = #rows + 1, n do
            local row = CreateRow(i)
            if panel.colLayout then row:ApplyColumns(panel.colLayout) end
        end
        for i = 1, #rows do
            if i > n then rows[i]:Hide() end
        end
        panel.visibleRows = n
    end

    ----------------------------------------------------------------
    -- Update visible rows from state.results
    ----------------------------------------------------------------
    function panel:UpdateRows()
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        local total = #state.results
        local visible = self.visibleRows or 0
        if visible < 1 then return end

        FauxScrollFrame_Update(scrollFrame, total, visible, ROW_HEIGHT)

        for i = 1, visible do
            local row = rows[i]
            local dataIdx = offset + i
            if dataIdx <= total then
                local entry = state.results[dataIdx]
                row.data = entry
                row:Show()

                -- Alternate row colors
                local bg = (i % 2 == 0) and C.row2 or C.row1
                row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)

                -- Online status dot
                if entry.hasOnline then
                    row.statusDot:SetVertexColor(C.online.r, C.online.g, C.online.b, 1.0)
                else
                    row.statusDot:SetVertexColor(C.offline.r, C.offline.g, C.offline.b, 0.5)
                end

                -- Recipe name
                row.recipeName:SetText(entry.name or "?")
                row.recipeName:SetTextColor(C.white.r, C.white.g, C.white.b)

                -- Profession
                local iconPath = PROF_ICONS[entry.profName]
                if iconPath then
                    row.profIcon:SetTexture(iconPath)
                    row.profIcon:Show()
                else
                    row.profIcon:Hide()
                end
                local pc = PROF_COLORS[entry.profName] or C.silver
                row.profName:SetText(entry.profName or "")
                row.profName:SetTextColor(pc.r, pc.g, pc.b)

                -- Crafters list (grouped, class-colored)
                local crafterParts = {}
                local firstOnlineCrafter = nil
                for _, crafter in ipairs(entry.crafters or {}) do
                    local memberData = BRutus.db.members[crafter.playerKey]
                    local pClass = memberData and memberData.class
                    local cc = pClass and BRutus.ClassColors[pClass] or C.white
                    local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
                    local alpha = crafter.isOnline and "" or "|cff666666"
                    local resetAlpha = crafter.isOnline and "" or "|r"
                    table.insert(crafterParts, alpha .. "|cff" .. hex .. crafter.playerName .. "|r" .. resetAlpha)
                    if crafter.isOnline and not firstOnlineCrafter then
                        firstOnlineCrafter = crafter.playerName
                    end
                end
                row.playerName:SetText(table.concat(crafterParts, ", "))
                row.playerName:SetAlpha(1.0)

                -- Whisper button — whisper first online crafter with item link
                row.firstOnlineCrafter = firstOnlineCrafter
                row.whisperBtn:SetScript("OnClick", function()
                    if firstOnlineCrafter then
                        local itemLink
                        if entry.itemId then
                            itemLink = select(2, GetItemInfo(entry.itemId))
                        end
                        if itemLink then
                            ChatFrame_OpenChat("/w " .. firstOnlineCrafter .. L[" Can you craft "] .. itemLink .. L[" ?"])
                        else
                            ChatFrame_OpenChat("/w " .. firstOnlineCrafter .. L[" Can you craft "] .. (entry.name or L["this item"]) .. L[" ?"])
                        end
                    end
                end)
                row.whisperBtn:Hide()
            else
                row:Hide()
                row.data = nil
            end
        end
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            panel:UpdateRows()
        end)
    end)

    ----------------------------------------------------------------
    -- Info bar at bottom
    ----------------------------------------------------------------
    local infoBar = CreateFrame("Frame", nil, panel)
    infoBar:SetPoint("BOTTOMLEFT", 10, 8)
    infoBar:SetPoint("BOTTOMRIGHT", -10, 8)
    infoBar:SetHeight(24)

    local infoText = UI:CreateText(infoBar, "", 9, 0.5, 0.5, 0.6)
    infoText:SetPoint("LEFT", 0, 0)

    local scanHint = UI:CreateText(infoBar, L["Open your tradeskill window to share your recipes"], 9, C.accentDim.r, C.accentDim.g, C.accentDim.b)
    scanHint:SetPoint("RIGHT", 0, 0)

    ----------------------------------------------------------------
    -- Refresh on show
    ----------------------------------------------------------------
    parent:SetScript("OnShow", function()
        RebuildFilterButtons()
        RefreshResults()
        panel:UpdateRows()

        -- Update info bar
        local totalPlayers = 0
        local totalRecipes = 0
        for _, professions in pairs((BRutus.db and BRutus.db.recipes) or {}) do
            totalPlayers = totalPlayers + 1
            for _, recipes in pairs(professions) do
                totalRecipes = totalRecipes + #recipes
            end
        end
        infoText:SetText(string.format(L["|cff888888%d crafters  |  %d total recipes indexed|r"], totalPlayers, totalRecipes))
    end)

    ----------------------------------------------------------------
    -- Layout: profession filters wrap, columns drop, rows follow height.
    ----------------------------------------------------------------
    function panel:Relayout(w, h)
        w = w or parent:GetWidth()
        h = h or parent:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end

        local inner = w - SIDE_MARGIN * 2
        filterRow:SetWidth(inner)
        local filterH = UI:FlowBar(filterRow, filterButtons, { gap = 2, rowGap = 2, rowH = 22 })
        topBar:SetHeight(TITLE_H + filterH)

        local layout = UI:ResolveColumns(COLUMNS, inner - ROW_GUTTER - ROW_INSET, COL_GAP)
        self.colLayout = layout
        for _, col in ipairs(layout) do
            local fs = headerByKey[col.key]
            if fs then
                fs:SetShown(col.shown)
                if col.shown then
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", ROW_INSET + col.x, 0)
                    fs:SetWidth(col.w)
                end
            end
        end

        local listTop = TOP_PAD + TITLE_H + filterH + 4 + HEADER_H
        AcquireRows(UI:ResolveRows(h - listTop - LIST_BOTTOM, ROW_HEIGHT, 0))
        for i = 1, self.visibleRows do rows[i]:ApplyColumns(layout) end
        self:UpdateRows()
    end

    UI:MakeResponsive(parent, function(_, w, h) panel:Relayout(w, h) end)

    -- Returned so a caller (and the layout tests) can reach the panel
    -- rather than only its container.
    return panel
end
