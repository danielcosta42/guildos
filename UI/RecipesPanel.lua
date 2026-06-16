----------------------------------------------------------------------
-- BRutus Guild Manager - Recipes Panel
-- Searchable guild recipe browser, grouped by profession
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors

local ROW_HEIGHT = 24
local VISIBLE_ROWS = 20

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
    local title = UI:CreateTitle(topBar, "Guild Recipes", 14)
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
    searchPlaceholder:SetText("Search recipes...")

    -- Profession filter buttons row
    local filterRow = CreateFrame("Frame", nil, topBar)
    filterRow:SetPoint("TOPLEFT", 0, -26)
    filterRow:SetPoint("TOPRIGHT", 0, -26)
    filterRow:SetHeight(26)

    local filterButtons = {}

    local function RefreshResults()
        if not BRutus.RecipeTracker then
            state.results = {}
        else
            state.results = BRutus.RecipeTracker:Search(state.query, state.profFilter)
        end
        state.scrollOffset = 0
        countText:SetText(string.format("|cff888888%d results|r", #state.results))
    end

    local function CreateFilterButton(profName, anchorTo)
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
            label:SetText("All")
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

        if anchorTo then
            btn:SetPoint("LEFT", anchorTo, "RIGHT", 2, 0)
        else
            btn:SetPoint("LEFT", 0, 0)
        end

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

        local prev
        for _, profName in ipairs(allProfs) do
            prev = CreateFilterButton(profName, prev)
        end

        -- Mark active
        for _, fb in ipairs(filterButtons) do
            if fb.profName == state.profFilter then
                fb:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
            end
        end
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
    headerFrame:SetPoint("TOPLEFT", 10, -72)
    headerFrame:SetPoint("TOPRIGHT", -10, -72)
    headerFrame:SetHeight(24)

    local headerBg = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    headerBg:SetAllPoints()
    headerBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    local hStatus = UI:CreateHeaderText(headerFrame, "", 10)
    hStatus:SetPoint("LEFT", 8, 0)
    hStatus:SetWidth(20)

    local hRecipe = UI:CreateHeaderText(headerFrame, "RECIPE", 10)
    hRecipe:SetPoint("LEFT", 32, 0)

    local hProfession = UI:CreateHeaderText(headerFrame, "PROFESSION", 10)
    hProfession:SetPoint("LEFT", 400, 0)

    local hPlayer = UI:CreateHeaderText(headerFrame, "CRAFTERS", 10)
    hPlayer:SetPoint("LEFT", 560, 0)

    local hAction = UI:CreateHeaderText(headerFrame, "", 10)
    hAction:SetPoint("RIGHT", -8, 0)

    ----------------------------------------------------------------
    -- Scroll frame with rows
    ----------------------------------------------------------------
    local listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetPoint("TOPLEFT", 10, -96)
    listFrame:SetPoint("BOTTOMRIGHT", -10, 40)

    local scrollFrame = CreateFrame("ScrollFrame", "BRutusRecipeScroll", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetAllPoints()
    UI:SkinScrollBar(scrollFrame, "BRutusRecipeScroll")

    -- Create row frames
    local rows = {}

    local function CreateRow(index)
        local row = CreateFrame("Button", nil, listFrame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", -10, -((index - 1) * ROW_HEIGHT))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        -- Online dot
        local statusDot = row:CreateTexture(nil, "OVERLAY")
        statusDot:SetSize(8, 8)
        statusDot:SetPoint("LEFT", 10, 0)
        statusDot:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.statusDot = statusDot

        -- Recipe name
        local recipeName = row:CreateFontString(nil, "OVERLAY")
        recipeName:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        recipeName:SetPoint("LEFT", 32, 0)
        recipeName:SetWidth(360)
        recipeName:SetJustifyH("LEFT")
        recipeName:SetWordWrap(false)
        row.recipeName = recipeName

        -- Profession icon + name
        local profIcon = row:CreateTexture(nil, "ARTWORK")
        profIcon:SetSize(16, 16)
        profIcon:SetPoint("LEFT", 400, 0)
        row.profIcon = profIcon

        local profName = row:CreateFontString(nil, "OVERLAY")
        profName:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        profName:SetPoint("LEFT", profIcon, "RIGHT", 4, 0)
        profName:SetWidth(140)
        profName:SetJustifyH("LEFT")
        row.profName = profName

        -- Player name
        local playerName = row:CreateFontString(nil, "OVERLAY")
        playerName:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        playerName:SetPoint("LEFT", 560, 0)
        playerName:SetWidth(140)
        playerName:SetJustifyH("LEFT")
        playerName:SetWordWrap(false)
        row.playerName = playerName

        -- Whisper button
        local whisperBtn = UI:CreateButton(row, "Whisper", 60, 20)
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

    for i = 1, VISIBLE_ROWS do
        CreateRow(i)
    end

    ----------------------------------------------------------------
    -- Update visible rows from state.results
    ----------------------------------------------------------------
    function panel:UpdateRows()
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        local total = #state.results

        FauxScrollFrame_Update(scrollFrame, total, VISIBLE_ROWS, ROW_HEIGHT)

        for i = 1, VISIBLE_ROWS do
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
                            ChatFrame_OpenChat("/w " .. firstOnlineCrafter .. " Você consegue craftar " .. itemLink .. " ?")
                        else
                            ChatFrame_OpenChat("/w " .. firstOnlineCrafter .. " Você consegue craftar " .. (entry.name or "esse item") .. " ?")
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

    local scanHint = UI:CreateText(infoBar, "Open your tradeskill window to share your recipes", 9, C.accentDim.r, C.accentDim.g, C.accentDim.b)
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
        infoText:SetText(string.format("|cff888888%d crafters  |  %d total recipes indexed|r", totalPlayers, totalRecipes))
    end)
end
