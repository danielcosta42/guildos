----------------------------------------------------------------------
-- Guild OS - Professions panel (WoW: Forever, issue #33)
--
-- Who in the guild makes what. A rail of professions with their coverage; a Recipes view of
-- every recipe the game has for the profession (who knows it, what it needs, what nobody
-- covers) and a Crafters view of the members with it; a card per recipe with its reagents,
-- source and crafters. Everything comes from BRutus.ProfDirectory; this file only draws.
-- Replaces the Recipes panel on Forever (UI/Features.lua).
----------------------------------------------------------------------
if BRutus.Client.isAnniversary then return end

local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L

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
local CARD_LINES = 8
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
    local r, g, b = BRutus:GetClassColor(class)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function itemIcon(id)
    return id and id > 0 and select(10, BRutus.Compat.GetItemInfo(id)) or nil
end

local function recipeIcon(e)
    return itemIcon(e.out) or select(3, BRutus.Compat.GetSpellInfo(e.id)) or QUESTION
end

-- A whisper to a guildmate through the client's tell box. A name with a surname ("First Last") is
-- resolved by the chat parser's completion of online guildmates, which is why only online
-- crafters get the button.
local function whisper(name)
    if ChatFrame_SendTell then ChatFrame_SendTell(name) else ChatFrame_OpenChat("/w " .. name .. " ") end
end

local function sourceText(e)
    if e.src == 3 then return L["Automatic"] end
    if e.src == 2 then
        local link = e.recipeItem and e.recipeItem > 0 and select(2, BRutus.Compat.GetItemInfo(e.recipeItem))
        return link or L["Recipe item"]
    end
    return L["Trainer"]
end

local function specName(id)
    return id and id > 0 and (BRutus.Compat.GetSpellInfo(id) or ("#" .. id)) or nil
end

local function stationName(focus)
    local name = focus and focus > 0 and BRutus.ProfCatalog.stations[focus]
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
        parts[i] = e.online and ("|cff" .. classHex(e.class) .. e.name .. "|r") or ("|cff777777" .. e.name .. "|r")
    end
    local text = table.concat(parts, ", ")
    if #list > 3 then text = text .. string.format(" |cff777777+%d|r", #list - 3) end
    return text
end

----------------------------------------------------------------------
-- The recipe card: a popup beside the window, as tall as what it shows
----------------------------------------------------------------------
local card

local function BuildCard()
    card = UI:CreatePanel(UIParent, "BRutusRecipeCard")
    card:SetSize(320, 200)
    card:SetFrameStrata("DIALOG")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", card.StartMoving)
    card:SetScript("OnDragStop", card.StopMovingOrSizing)
    UI:StylePopup(card)
    table.insert(UISpecialFrames, "BRutusRecipeCard")

    local close = UI:CreateCloseButton(card)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() card:Hide() end)

    card.icon = UI:CreateIcon(card, 32)
    card.icon:SetPoint("TOPLEFT", 14, -14)
    card.title = UI:CreateText(card, "", 13, C.white.r, C.white.g, C.white.b)
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
    card.title:SetWidth(230)
    card.title:SetJustifyH("LEFT")
    card.subtitle = UI:CreateText(card, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)

    local function detail(label)
        local l = UI:CreateText(card, label, 10, C.textDim.r, C.textDim.g, C.textDim.b)
        local v = UI:CreateText(card, "", 10, C.text.r, C.text.g, C.text.b)
        v:SetWidth(196)
        v:SetJustifyH("LEFT")
        return { label = l, value = v }
    end
    card.details = {
        makes = detail(L["Makes"]), source = detail(L["Source"]), skill = detail(L["Skill"]),
        spec = detail(L["Specialization"]), station = detail(L["Station"]),
    }

    card.reagentsHeader = UI:CreateHeaderText(card, L["REAGENTS"], 10)
    card.reagents = {}
    for i = 1, CARD_LINES do
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local text = UI:CreateText(card, "", 10, C.text.r, C.text.g, C.text.b)
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        text:SetWidth(260)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        card.reagents[i] = { icon = icon, text = text }
    end

    card.craftersHeader = UI:CreateHeaderText(card, L["CRAFTERS"], 10)
    card.crafters = {}
    for i = 1, CARD_LINES do
        local text = UI:CreateText(card, "", 10, C.text.r, C.text.g, C.text.b)
        text:SetWidth(200)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        local btn = UI:CreateButton(card, L["Whisper"], 60, 18)
        card.crafters[i] = { text = text, btn = btn }
    end
    card.more = UI:CreateText(card, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    card.none = UI:CreateText(card, "", 10, C.red.r, C.red.g, C.red.b)
end

-- Anchor a region at x, y from the card's top-left.
local function at(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", x, y)
end

-- `repaint` keeps the card where it is (the user may have dragged it); a click places it beside
-- the window.
local function ShowCard(e, anchor, who, repaint)
    if not card then BuildCard() end
    local D = BRutus.ProfDirectory
    card.last = { e = e, anchor = anchor, who = who }   -- repainted when an item's data arrives
    if not repaint then
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    end

    card.icon.icon:SetTexture(recipeIcon(e))
    card.title:SetText(e.name)
    card.subtitle:SetText(string.format("%s  ·  %d–%d", D.DisplayName(e.line), e.yellow, e.grey))

    local outLink = e.out and e.out > 0 and select(2, BRutus.Compat.GetItemInfo(e.out))
    local values = {
        { card.details.makes, outLink or (e.out and e.out > 0 and ("#" .. e.out)) or L["Enchantment"] },
        { card.details.source, sourceText(e) },
        { card.details.skill, e.reqSkill and e.reqSkill > 0 and tostring(e.reqSkill) or nil },
        { card.details.spec, specName(e.spec) },
        { card.details.station, stationName(e.focus) },
    }
    local y = -64
    for _, v in ipairs(values) do
        local d, text = v[1], v[2]
        d.label:SetShown(text ~= nil)
        d.value:SetShown(text ~= nil)
        if text then
            at(d.label, 14, y)
            at(d.value, 110, y)
            d.value:SetText(text)
            y = y - 18
        end
    end

    local reagents = D.Reagents(e.id)
    card.reagentsHeader:SetShown(#reagents > 0)
    if #reagents > 0 then
        y = y - 8
        at(card.reagentsHeader, 14, y)
        y = y - 18
    end
    for i, slot in ipairs(card.reagents) do
        local rg = reagents[i]
        slot.icon:SetShown(rg ~= nil)
        slot.text:SetShown(rg ~= nil)
        if rg then
            at(slot.icon, 14, y)
            slot.icon:SetTexture(itemIcon(rg.itemID) or QUESTION)
            local name = BRutus.Compat.GetItemInfo(rg.itemID) or ("#" .. rg.itemID)
            slot.text:SetText(string.format("%s  |cff%sx%d|r", name, hex(C.gold), rg.count))
            y = y - 20
        end
    end

    y = y - 8
    at(card.craftersHeader, 14, y)
    y = y - 20
    local list = crafterList(e.crafters, who)
    for i, slot in ipairs(card.crafters) do
        local c = list[i]
        slot.text:SetShown(c ~= nil)
        slot.btn:SetShown(c ~= nil and c.online)
        if c then
            at(slot.text, 14, y)
            slot.text:SetText(c.online and ("|cff" .. classHex(c.class) .. c.name .. "|r")
                or ("|cff777777" .. c.name .. "  " .. L["(offline)"] .. "|r"))
            slot.btn:ClearAllPoints()
            slot.btn:SetPoint("RIGHT", card, "TOPRIGHT", -14, y - 6)
            local name = c.name
            slot.btn:SetScript("OnClick", function() whisper(name) end)
            y = y - 22
        end
    end
    card.more:SetShown(#list > CARD_LINES)
    if #list > CARD_LINES then
        at(card.more, 14, y)
        card.more:SetText(string.format(L["+%d more crafters"], #list - CARD_LINES))
        y = y - 18
    end
    card.none:SetShown(#list == 0)
    if #list == 0 then
        at(card.none, 14, y)
        card.none:SetText(L["Nobody in the guild crafts this"])
        y = y - 18
    end
    card:SetHeight(-y + 14)
    card:Show()
end

----------------------------------------------------------------------
-- The panel
----------------------------------------------------------------------
function BRutus:CreateProfessionsPanel(parent, _win)
    local D = BRutus.ProfDirectory
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local state = { line = nil, mode = "recipes", filter = "all", query = "", results = {}, who = {} }

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
            state.line = line
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
    tabCrafters:SetScript("OnClick", function() state.mode = "crafters"; panel:Refresh(true) end)

    local tools = CreateFrame("Frame", nil, main)
    tools:SetPoint("TOPLEFT", 0, -TITLE_H)
    tools:SetPoint("TOPRIGHT", 0, -TITLE_H)
    tools:SetHeight(TOOLS_H)

    local search = CreateFrame("EditBox", nil, tools, "BackdropTemplate")
    search:SetSize(220, 24)
    search:SetPoint("LEFT", 0, 0)
    search:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    search:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    search:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    BRutus:ApplyFont(search, 11)
    search:SetTextColor(C.white.r, C.white.g, C.white.b)
    search:SetTextInsets(8, 8, 0, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(50)
    local placeholder = search:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(placeholder, 11)
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    placeholder:SetText(L["Search recipes..."])
    -- The placeholder only while the box is empty and wide enough to hold it.
    local function paintPlaceholder()
        placeholder:SetShown((search:GetText() or "") == "" and (search:GetWidth() or 0) >= 130)
    end
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        paintPlaceholder()
        state.query = text
        panel:Refresh(true)
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local filterTabs = {}
    local FILTERS = { { "all", L["All"] }, { "guild", L["In the guild"] }, { "gaps", L["Nobody crafts"] } }
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
    local header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -4)
    header:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", 0, -4)
    header:SetHeight(HEADER_H)
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetTexture(WHITE8)
    headerBg:SetAllPoints()
    headerBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
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
    local scroll = CreateFrame("ScrollFrame", "BRutusProfessionsScroll", list, "FauxScrollFrameTemplate")
    scroll:SetAllPoints()
    UI:SkinScrollBar(scroll, "BRutusProfessionsScroll")

    local empty = UI:CreateText(list, "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
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
            BRutus:ApplyFont(fs, k == "t1" and 11 or 10)
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
            if self.data and state.mode == "recipes" then ShowCard(self.data, panel, state.who) end
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
            if not e then
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
                    row.t1:SetText(e.name)
                    row.t1:SetTextColor(C.white.r, C.white.g, C.white.b)
                    row.t2:SetText(string.format("|cff%s%d|r–|cff888888%d|r", hex(C.gold), e.yellow, e.grey))
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
                        row.t2:SetText("|cff777777" .. L["no addon"] .. "|r")
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
            state.results = D.RecipeRows(state.line, state.filter, state.query)
        else
            state.results = state.line and D.MemberRows(state.line) or {}
        end
        if resetScroll then
            scroll:SetVerticalScroll(0)
            if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(scroll, 0) end
        end
        title:SetText(state.line and D.DisplayName(state.line) or L["All professions"])
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

        -- The search box gives way to the filter tabs in a narrow window.
        local filtersW = 0
        for _, t in ipairs(filterTabs) do filtersW = filtersW + (t:GetWidth() or 0) + 4 end
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
    parent:HookScript("OnHide", function() if card then card:Hide() end end)
    UI:MakeResponsive(parent, function(_, w, h) panel:Relayout(w, h) end)

    -- Items the client had not cached arrive later: repaint names, icons and links once they do.
    local itemEvents = CreateFrame("Frame")
    BRutus.Compat.RegisterEvent(itemEvents, "GET_ITEM_INFO_RECEIVED")
    itemEvents:SetScript("OnEvent", function()
        if panel.itemsPending or not parent:IsVisible() then return end
        panel.itemsPending = true
        BRutus.Compat.After(0.3, function()
            panel.itemsPending = false
            panel:UpdateRows()
            if card and card:IsShown() and card.last then
                ShowCard(card.last.e, card.last.anchor, card.last.who, true)
            end
        end)
    end)
    panel.itemEvents = itemEvents

    -- Reachable by the caller and by tools/professions-panel.lua, which drives the panel like a user.
    panel.state, panel.railButtons, panel.rows = state, railButtons, rows
    panel.tabRecipes, panel.tabCrafters, panel.search, panel.filterTabs = tabRecipes, tabCrafters, search, filterTabs
    return panel
end
