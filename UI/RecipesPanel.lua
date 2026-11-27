----------------------------------------------------------------------
-- Guild OS - Recipes Panel
-- Searchable guild recipe browser, grouped by profession
-- Drawn as the Workshop's catalog (#449 phase 3): one parchment card, the profession filters as quiet buttons,
-- the table in the paper's ink, the crafters in their class's colour deepened to read on the paper.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

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
local ROW_GUTTER = UI.SCROLL_GUTTER   -- rows stop clear of the scrollbar (#371)
local TOP_PAD    = 8    -- panel top to the top bar
local TITLE_H    = 26   -- title + search row, above the profession filters
local HEADER_H   = 24   -- column header strip
local LIST_BOTTOM = 40  -- footer strip under the list
local CARD_PAD   = UI.SP.PAD   -- the parchment card's padding
local CARD_TOP   = UI.SP.TOP   -- under the card's title

-- A colour deepened to read on the paper: the bright ones (a priest's white, a rogue's yellow) vanish on it.
local function deep(c)
    return GuildOS.UI:Ink("paper", c)   -- the one mapping of the paper's inks (UI/Helpers.lua, #449)
end
local function hexOf(c) return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end

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
function GuildOS:CreateRecipesPanel(parent, _mainFrame)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- State
    local state = {
        query = "",
        profFilter = "All",
        results = {},
        scrollOffset = 0,
        open = nil,      -- the recipe whose card is open (issue #389, #449), by its key
    }

    -- A recipe's identity in the list: its item, else its name and profession.
    local function keyOf(e) return e.itemId and ("i" .. e.itemId) or ((e.name or "?") .. "|" .. (e.profName or "")) end

    ----------------------------------------------------------------
    -- Top bar: search + profession filters
    ----------------------------------------------------------------
    -- The catalog's parchment card; its title says what it lists.
    local sheet = UI:CreateCard(panel, L["Guild Recipes"])
    sheet:SetPoint("TOPLEFT", SIDE_MARGIN, -TOP_PAD)
    sheet:SetPoint("BOTTOMRIGHT", -SIDE_MARGIN, SIDE_MARGIN)
    local title = sheet.title

    local topBar = CreateFrame("Frame", nil, sheet)
    topBar:SetPoint("TOPLEFT", CARD_PAD, -CARD_TOP)
    topBar:SetPoint("TOPRIGHT", -CARD_PAD, -CARD_TOP)
    topBar:SetHeight(60)

    -- Search box: the shared field, with its own hint while empty (#371).
    local searchBox = UI:CreateInput(topBar, 220, 24, { max = 50, placeholder = L["Search recipes..."] })
    searchBox:SetPoint("TOPLEFT", 0, 0)

    -- Result count
    local countText = UI:CreateText(topBar, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    countText:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)

    -- Profession filter buttons row
    -- Anchored on the left only: UI:FlowBar reads GetWidth to decide where
    -- to wrap, and a frame pinned on both sides reports a stale width in
    -- the same frame the container was resized.
    local filterRow = CreateFrame("Frame", nil, topBar)
    filterRow:SetPoint("TOPLEFT", 0, -TITLE_H)
    filterRow:SetSize(400, 26)

    local filterButtons = {}
    local detail   -- the opened recipe's block, made with the list below

    local function RefreshResults()
        if not GuildOS.RecipeTracker then
            state.results = {}
        else
            state.results = GuildOS.RecipeTracker:Search(state.query, state.profFilter)
        end
        -- Opened on an item (Alt-click, an order's card): only the recipes that make it, and the
        -- title says so until a filter or the search lets go of it.
        local itemName = state.item and (GuildOS.Compat.GetItemInfo(state.item) or ("item:" .. state.item))
        GuildOS:SetTitleText(title, itemName and string.format(L["Recipes for %s"], itemName) or L["Guild Recipes"])
        if state.item then
            local only = {}
            for _, e in ipairs(state.results) do if e.itemId == state.item then only[#only + 1] = e end end
            state.results = only
        end
        state.scrollOffset = 0
        countText:SetText((string.format(L["|cff888888%d results|r"], #state.results):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        -- The marks after a name: the recipes I make, and how many orders ask for each item.
        local O = GuildOS.CraftOrders
        state.byItem = O and O:OrdersByItem() or {}
        state.me = O and O:MyKey()
    end

    -- The chosen filter carries the shared selection mark (#371), not a tinted fill.
    local function PaintFilters()
        for _, fb in ipairs(filterButtons) do UI:SetSelected(fb, fb.profName == state.profFilter) end
    end

    -- A filter is a shared button: "All" by name, a profession by its icon, or by its first letters
    -- in its colour where the client has no icon for it.
    local function CreateFilterButton(profName)
        local isAll = profName == "All"
        local iconTex = not isAll and PROF_ICONS[profName] or nil
        local text = (isAll and L["All"]) or (iconTex and "") or GuildOS:Utf8Head(L[profName], 3)
        local btn = UI:CreateButton(filterRow, text, isAll and 40 or 26, 22)
        btn.profName = profName

        local icon
        if iconTex then
            icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("CENTER")
            icon:SetTexture(iconTex)
        elseif not isAll then
            local pc = deep(PROF_COLORS[profName] or C.silver)
            btn.baseLabelColor = { pc.r, pc.g, pc.b }
        end
        btn.icon = icon
        -- Position comes from UI:FlowBar, which wraps the row when the
        -- window is too narrow to hold every profession on one line.

        btn:SetScript("OnClick", function()
            state.profFilter, state.item = profName, nil
            PaintFilters()
            RefreshResults()
            panel:UpdateRows()
        end)
        -- Hooked, not set: the button's own hover state lives on OnEnter and OnLeave.
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L[profName], 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(filterButtons, btn)
        return btn
    end

    -- Build profession filter buttons dynamically on show
    local function RebuildFilterButtons()
        -- Hide existing
        for _, btn in ipairs(filterButtons) do btn:Hide() end
        filterButtons = {}

        -- Get known professions
        local profs = GuildOS.RecipeTracker and GuildOS.RecipeTracker:GetAllProfessions() or {}
        local allProfs = { "All" }
        for _, p in ipairs(profs) do
            table.insert(allProfs, p)
        end

        for _, profName in ipairs(allProfs) do
            CreateFilterButton(profName)
        end

        -- Mark active
        PaintFilters()

        -- New buttons need placing straight away; the layout pass only
        -- runs on resize.
        if panel.Relayout then panel:Relayout() end
    end

    -- Hooked, not set: the field keeps its own Escape, focus and hint handlers.
    searchBox:HookScript("OnTextChanged", function(self)
        local text = self:GetText()
        state.query, state.item = text or "", nil
        RefreshResults()
        panel:UpdateRows()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    ----------------------------------------------------------------
    -- Column headers
    ----------------------------------------------------------------
    -- The shared table header (#371): no fill, a 1px rule under the column labels.
    local headerFrame = UI:CreateTableHeader(sheet, HEADER_H)
    headerFrame:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
    headerFrame:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -4)

    -- Header cells are positioned by the layout pass, keyed the same way
    -- the row cells are so the two can never drift apart.
    local headerByKey = {
        recipe     = UI:CreateHeaderText(headerFrame, L["Recipe"], UI.SP.META),
        profession = UI:CreateHeaderText(headerFrame, L["Profession"], UI.SP.META),
        crafters   = UI:CreateHeaderText(headerFrame, L["Crafters"], UI.SP.META),
    }
    for _, fs in pairs(headerByKey) do
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end

    ----------------------------------------------------------------
    -- Scroll frame with rows
    ----------------------------------------------------------------
    local listFrame = CreateFrame("Frame", nil, sheet)
    listFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    listFrame:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -CARD_PAD, LIST_BOTTOM - SIDE_MARGIN)

    local scrollFrame = CreateFrame("ScrollFrame", "GuildOSRecipeScroll", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetAllPoints()
    UI:SkinScrollBar(scrollFrame, "GuildOSRecipeScroll")
    -- The chosen recipe's card (#449): the Crafts tab puts it in its right column; on its own it lies over the
    -- panel's right part. Closed (its "‹ Orders", Escape), the list lets go of the recipe.
    detail = GuildOS.CreateRecipeCard and GuildOS:CreateRecipeCard(panel)
    if detail then
        detail.onClose = function()
            state.open, state.openTo = nil, nil
            panel:UpdateRows()
        end
    end

    -- Create row frames
    local rows = {}

    local function CreateRow(index)
        local row = CreateFrame("Button", nil, listFrame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", -ROW_GUTTER, -((index - 1) * ROW_HEIGHT))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        -- Online dot: rides inside the recipe cell
        -- The chosen recipe's mark on its left, in the paper's title red.
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.mark:SetVertexColor(C.paperTitle.r, C.paperTitle.g, C.paperTitle.b, 1)
        row.mark:SetPoint("TOPLEFT", 0, 0)
        row.mark:SetPoint("BOTTOMLEFT", 0, 0)
        row.mark:SetWidth(2)
        row.mark:Hide()

        local statusDot = row:CreateTexture(nil, "OVERLAY")
        statusDot:SetSize(8, 8)
        statusDot:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.statusDot = statusDot

        -- Recipe name
        local recipeName = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(recipeName, 11)
        recipeName:SetJustifyH("LEFT")
        recipeName:SetWordWrap(false)
        row.recipeName = recipeName

        -- Profession icon + name
        local profIcon = row:CreateTexture(nil, "ARTWORK")
        profIcon:SetSize(16, 16)
        row.profIcon = profIcon

        local profName = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(profName, UI.SP.META)
        profName:SetPoint("LEFT", profIcon, "RIGHT", 4, 0)
        profName:SetJustifyH("LEFT")
        profName:SetWordWrap(false)
        row.profName = profName

        -- Player name
        local playerName = row:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(playerName, 11)
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
        whisperBtn:SetPoint("RIGHT", 0, 0)
        whisperBtn:SetFrameLevel(row:GetFrameLevel() + 2)
        whisperBtn:Hide()
        row.whisperBtn = whisperBtn

        -- Hover helpers (prevent flicker when mouse moves to whisper button)
        local function RowEnter(self)
            self:SetBackdropColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 0.6)
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
            self:SetBackdropColor(0, 0, 0, 0)
            GameTooltip:Hide()
            self.whisperBtn:Hide()
        end

        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        -- A click opens the recipe's card (issue #389, #449), a second one closes it; Shift-click links its item.
        row:SetScript("OnClick", function(self)
            local e = self.data
            if not e then return end
            if IsShiftKeyDown() and e.itemId and HandleModifiedItemClick then
                local _, link = GuildOS.Compat.GetItemInfo(e.itemId)
                if link then HandleModifiedItemClick(link) end
                return
            end
            if not detail then return end
            local k = keyOf(e)
            state.openTo = nil
            if state.open == k then
                detail:Close()
            else
                state.open = k
                panel:UpdateRows()
                panel:PaintDetail(true)
            end
        end)

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
            local entry = state.results[dataIdx]
            if entry then
                row.data = entry
                row:Show()

                -- On the paper: no stripes, the opened recipe washed below.
                row:SetBackdropColor(0, 0, 0, 0)

                -- Online status dot
                if entry.hasOnline then
                    row.statusDot:SetVertexColor(0.184, 0.431, 0.2, 1.0)
                else
                    row.statusDot:SetVertexColor(C.paperRule.r, C.paperRule.g, C.paperRule.b, 1)
                end

                -- Recipe name, and its marks
                local marks = ""
                for _, c in ipairs(entry.crafters or {}) do
                    if state.me and c.playerKey == state.me then
                        marks = string.format("  |cff2f6e33%s|r", L["you craft"])
                    end
                end
                local orders = entry.itemId and state.byItem and state.byItem[entry.itemId]
                if orders and orders > 0 then
                    marks = marks .. string.format("  |cff%s%s|r", hexOf(C.paperTitle), string.format(L["%d orders"], orders))
                end
                row.recipeName:SetText((entry.name or "?") .. marks)
                row.recipeName:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
                local chosen = keyOf(entry) == state.open
                if chosen then row:SetBackdropColor(C.paperLine.r, C.paperLine.g, C.paperLine.b, 0.8) end
                row.mark:SetShown(chosen)

                -- Profession
                local iconPath = PROF_ICONS[entry.profName]
                if iconPath then
                    row.profIcon:SetTexture(iconPath)
                    row.profIcon:Show()
                else
                    row.profIcon:Hide()
                end
                local pc = deep(PROF_COLORS[entry.profName] or C.silver)
                row.profName:SetText(entry.profName and L[entry.profName] or "")
                row.profName:SetTextColor(pc.r, pc.g, pc.b)

                -- Crafters list (grouped, class-colored)
                local crafterParts = {}
                local firstOnlineCrafter = nil
                for _, crafter in ipairs(entry.crafters or {}) do
                    local memberData = GuildOS.db.members[crafter.playerKey]
                    local pClass = memberData and memberData.class
                    local cc = pClass and GuildOS.ClassColors[pClass] and deep(GuildOS.ClassColors[pClass]) or C.paperInk
                    -- The shared paper inks (UI/Kit.lua's mockup class colours) where they are loaded.
                    local Kit = rawget(GuildOS, "Kit")
                    if Kit and Kit.ClassInk and pClass then
                        local r, g, b = Kit:ClassInk(pClass)
                        cc = { r = r, g = g, b = b }
                    end
                    -- Offline, the paper's softer ink: who can make it now reads first.
                    local hex = crafter.isOnline and hexOf(cc) or hexOf(C.paperSoft)
                    table.insert(crafterParts, "|cff" .. hex .. crafter.playerName .. "|r")
                    if crafter.isOnline and not firstOnlineCrafter then
                        firstOnlineCrafter = crafter.playerName
                    end
                end
                row.playerName:SetText(table.concat(crafterParts, ", "))
                row.playerName:SetTextColor(C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
                row.playerName:SetAlpha(1.0)

                -- Whisper button — whisper first online crafter with item link
                row.firstOnlineCrafter = firstOnlineCrafter
                row.whisperBtn:SetScript("OnClick", function()
                    if firstOnlineCrafter then
                        local itemLink
                        if entry.itemId then
                            itemLink = select(2, GuildOS.Compat.GetItemInfo(entry.itemId))
                        end
                        if itemLink then
                            ChatFrame_OpenChat("/w " .. firstOnlineCrafter .. " " .. string.format(L["Can you craft %s?"], itemLink))
                        else
                            ChatFrame_OpenChat("/w " .. firstOnlineCrafter .. " " .. string.format(L["Can you craft %s?"], entry.name or L["this item"]))
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

    -- The chosen recipe's card: its item, what it takes, its crafters online first, the order.
    function panel:PaintDetail(fresh)
        if not detail then return end
        if not state.open then
            if detail:IsShown() then detail:Close() end
            return
        end
        local e = state.openRow
        for _, x in ipairs(state.results) do if keyOf(x) == state.open then e = x end end
        if not e or keyOf(e) ~= state.open then detail:Close(); return end
        state.openRow = e
        local crafters = {}
        for _, c in ipairs(e.crafters or {}) do
            local m = GuildOS.db.members and GuildOS.db.members[c.playerKey]
            crafters[#crafters + 1] = { key = c.playerKey, name = c.playerName, class = m and m.class, online = c.isOnline == true }
        end
        table.sort(crafters, function(a, b)
            if a.online ~= b.online then return a.online end
            return (a.name or "") < (b.name or "")
        end)
        local name, quality, tex, _
        if e.itemId then name, _, quality, _, _, _, _, _, _, tex = GuildOS.Compat.GetItemInfo(e.itemId) end
        detail:SetRecipe({ id = keyOf(e), item = e.itemId, spell = e.spellId, name = name or e.name, quality = quality,
            icon = tex or PROF_ICONS[e.profName], prof = e.profName and L[e.profName] or nil, crafters = crafters },
            state.openTo, fresh)
        UI.PlaceRecipeCard(detail, panel)
    end

    -- Search again, keeping the scroll, and paint the rows and the opened recipe.
    function panel:Reload()
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        RefreshResults()
        if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(scrollFrame, offset) end
        self:UpdateRows()
        self:PaintDetail()
    end
    panel.Refresh = panel.Reload

    -- Open the recipe that makes `itemId`: the Crafts tab's Alt-click, an order's card.
    function panel:FocusItem(itemId, toKey)
        state.profFilter, state.query = "All", ""
        searchBox:SetText("")
        state.item, state.open = itemId, "i" .. itemId     -- after SetText: its handler clears the item
        RefreshResults()
        local found = false
        for _, x in ipairs(state.results) do if keyOf(x) == state.open then found = true end end
        if not found then state.item, state.open = nil, nil; RefreshResults(); return false end
        PaintFilters()
        state.openTo = toKey
        if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(scrollFrame, 0) end
        self:UpdateRows()
        self:PaintDetail(true)
        return true
    end

    -- Open a recipe from the window's search (#449), by its name (and profession): this list has no ids of the
    -- Workshop's catalog, so `_id` is not read. The list is searched for the name, and the recipe of that name (else
    -- the first found) opened.
    function panel:FocusRecipe(_id, name, profName)
        if type(name) ~= "string" or name == "" then return false end
        state.profFilter = "All"
        searchBox:SetText(name)
        state.query, state.item = name, nil   -- after SetText: its handler runs the search where the game fires it
        RefreshResults()
        local hit
        for _, x in ipairs(state.results) do
            if x.name == name and (not profName or x.profName == profName) then hit = x; break end
        end
        hit = hit or state.results[1]
        if not hit then return false end
        state.open = keyOf(hit)
        PaintFilters()
        if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(scrollFrame, 0) end
        self:UpdateRows()
        self:PaintDetail(true)
        return true
    end

    ----------------------------------------------------------------
    -- Info bar at bottom
    ----------------------------------------------------------------
    local infoBar = CreateFrame("Frame", nil, sheet)
    infoBar:SetPoint("BOTTOMLEFT", CARD_PAD, 6)
    infoBar:SetPoint("BOTTOMRIGHT", -CARD_PAD, 6)
    infoBar:SetHeight(24)

    local infoText = UI:CreateText(infoBar, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    infoText:SetPoint("LEFT", 0, 0)

    -- A hint, in `textSoft`: not the dimmed gold it used to be (#371). Anniversary has no other way to
    -- read a profession than its open window (audit B28).
    local scanHint = UI:CreateText(infoBar, L["Open each profession once to share it."], 11,
        C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
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
        local RT, seen = GuildOS.RecipeTracker, {}
        if RT and GuildOS.db then
            for key, prof in RT:EachList() do
                if not seen[key] then
                    seen[key] = true
                    totalPlayers = totalPlayers + 1
                end
                totalRecipes = totalRecipes + RT:CountOf(key, prof)
            end
        end
        infoText:SetText((string.format(L["|cff888888%d crafters  |  %d total recipes indexed|r"], totalPlayers, totalRecipes)
            :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end)

    ----------------------------------------------------------------
    -- Layout: profession filters wrap, columns drop, rows follow height.
    ----------------------------------------------------------------
    function panel:Relayout(w, h)
        w = w or parent:GetWidth()
        h = h or parent:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end

        local inner = w - SIDE_MARGIN * 2 - CARD_PAD * 2
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

        local listTop = TOP_PAD + CARD_TOP + TITLE_H + filterH + 4 + HEADER_H
        AcquireRows(UI:ResolveRows(h - listTop - LIST_BOTTOM, ROW_HEIGHT, 0))
        for i = 1, self.visibleRows do rows[i]:ApplyColumns(layout) end
        self:UpdateRows()
        if detail and detail:IsShown() then UI.PlaceRecipeCard(detail, panel, w) end
    end

    UI:MakeResponsive(parent, function(_, w, h) panel:Relayout(w, h) end)

    -- Returned so a caller (and the layout tests) can reach the panel
    -- rather than only its container.
    return panel
end
