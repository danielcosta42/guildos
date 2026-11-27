----------------------------------------------------------------------
-- Guild OS - Guild bank window (issue #380)
-- The Bank tab: Inventory · Tabs · Ledger · Needs · Requests · Cleanup, and the bar the addon docks over the
-- game's own guild bank while it is open. Visual layer only: what the bank holds, its ledger, needs
-- and requests come from GuildOS.GuildBank, and every change goes through it.
-- Each sub-screen is a board of parchment cards as the Salão's other screens (#449 phase 3, UI/Forms.lua): its
-- numbers, its form (labels above the fields), its table and the empty state, every width measured in the
-- client's language and laid again as the window narrows, so a long German or Russian label never runs into its
-- neighbour. An item is framed in its quality, its name in that quality deepened to read on the paper.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L
local SP = UI.SP
local Forms = GuildOS.Forms

local SUB_H     = 28    -- the sub-tab bar
local GUTTER    = tonumber(UI.SCROLL_GUTTER) or 12
local ROW_H     = SP.ROW
local ICON      = 18    -- an item's icon in a list
local ITEM_X    = ICON + 4 + 6   -- an item's name from its column's left: the framed icon, then a gap
local BTN_GAP   = 2 * SP.UNIT    -- two buttons of one group
local KPI_MIN   = 64    -- a KPI's text, at least
local BODY_MIN  = 160   -- a list's body, at least: room for its empty state
local ITEM_MAX  = 360   -- the item field asks for no more than this before the others
local SLOT_MAX  = 40    -- a slot of the tab grid, at most
local SLOT_MIN  = 24
local SLOT_GAP  = 2
local GRID_COLS = 14    -- the game draws a tab 14 slots across (7 columns of two)
local GRID_ROWS = 7
local TABS_W    = 232   -- the Tabs screen's list of tabs, beside the grid
local TAB_BTN_H = 30
local LEDGER_LEFT = 0.66   -- the Ledger's list, of two columns
local CHART_H   = 60
local CHART_DAYS = 30
local TOP_N     = 8     -- contributors shown
local TAX_N     = 4     -- members who owe the bank tax, shown (Ley)
local ANNOUNCE_MAX = 240  -- characters of one guild chat line
local LABEL_H   = 14 + SP.LABEL_GAP   -- a field's label over its box (Forms:MakeField)
local DROP_ARROW = 30   -- a select's text inset and its arrow (UI:CreateDropdown)

local function Bank() return GuildOS.GuildBank end

-- The Workshop's bank is drawn on parchment cards (#449 phase 3): a state's colour deepened to read on the
-- paper, as the mockup's.
local INK_OK     = { r = 0.184, g = 0.431, b = 0.2 }
local INK_DANGER = { r = 0.561, g = 0.106, b = 0.043 }
local INK_WARN   = { r = 0.541, g = 0.353, b = 0 }

----------------------------------------------------------------------
-- Small pieces
----------------------------------------------------------------------
-- A palette colour as a chat escape, for a colour inside one line of text.
local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function money(copper, paper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local gc, sc = paper and C.paperTitle or C.gold, paper and C.paperSoft or C.textSoft
    if g > 0 then return string.format("%d%sg|r %d%ss|r", g, hex(gc), s, hex(sc)) end
    -- Under a silver, its copper: a few greys read "0s" otherwise.
    if s == 0 and copper > 0 then return string.format("%d%sc|r", copper % 100, hex(sc)) end
    return string.format("%d%ss|r", s, hex(sc))
end
-- On a parchment card (the bank's sub-screens).
local function paperMoney(copper) return money(copper, true) end

-- An item's quality colour; on the paper (`paper` true, or a frame on a card) the paper's quality ink, the one
-- mapping every paper screen takes (UI:InkFor, #449): a common item in the paper's ink, an uncommon dark green.
local function qualityColor(q, paper)
    if paper and (paper == true or UI:OnPaper(paper)) then
        return UI.QUALITY_INK[q or 1] or C.paperInk
    end
    local qc = GuildOS.QualityColors and GuildOS.QualityColors[q or 1]
    return qc or C.text
end

-- A name as the guild says it: the realm only when it is not mine.
local function shortName(name)
    if type(name) ~= "string" then return "?" end
    return (Ambiguate and Ambiguate(name, "guild")) or name
end

-- A member's class colour; on the paper (`surface` a frame on a card) the paper's class ink (UI:InkFor).
local function classColor(name, surface)
    local class = Bank():ClassOf(name)
    if surface and UI:OnPaper(surface) then
        local r, g, b = UI:InkFor("paper", "class", class)
        return { r = r, g = g, b = b }
    end
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

-- A list with pooled rows over a FauxScrollFrame. `create(row)` builds a row once; `draw(row, item)`
-- paints it. list:SetData(items) redraws.
local listCount = 0
local function makeList(parent, rowH, create, draw)
    listCount = listCount + 1
    local name = "GuildOSBankList" .. listCount
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- On a parchment card the list is the paper itself, a line under each row (the mockup's table); on the wood
    -- (the drawer beside the game's bank) a dark well.
    local paper = UI:OnPaper(parent)
    list.paper = paper
    local rowLine = paper and C.paperLine or C.panel
    list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(list) })
    if paper then
        list:SetBackdropColor(0, 0, 0, 0)
        list:SetBackdropBorderColor(0, 0, 0, 0)
    else
        list:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
        list:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    end
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
            hl:SetColorTexture(rowLine.r, rowLine.g, rowLine.b, paper and 0.6 or 1)
            hl:Hide()
            row.hl = hl
            row:HookScript("OnEnter", function(self) self.hl:Show() end)
            row:HookScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
            local rule = row:CreateTexture(nil, "BORDER")
            rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
            UI:Hairline(rule)
            rule:SetColorTexture(rowLine.r, rowLine.g, rowLine.b, 1)
            row.paper = paper
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
    return list
end

----------------------------------------------------------------------
-- Laying a sub-screen out (#449 phase 3): every width measured in the client's language
----------------------------------------------------------------------
local function textW(fs) return math.ceil(tonumber(fs and fs:GetStringWidth()) or 0) end

-- A text's height as it wraps (14 for one line before the client measured it).
local function textH(fs)
    local h = tonumber(fs:GetStringHeight()) or 0
    return h > 0 and math.ceil(h) or 14
end

-- `text` in `fs`, cut with an ellipsis to `maxW` when it is wider (the client measures it: a German placeholder
-- is half as long again as the English one). Returns whether it was cut.
local ELLIPSIS = "\226\128\166"
local function fitText(fs, text, maxW)
    fs:SetText(text)
    if textW(fs) <= maxW then return false end
    local chars = {}
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    local lo, hi = 0, #chars
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        fs:SetText(table.concat(chars, "", 1, mid) .. ELLIPSIS)
        if textW(fs) <= maxW then lo = mid else hi = mid - 1 end
    end
    fs:SetText(table.concat(chars, "", 1, lo) .. ELLIPSIS)
    return true
end

-- A field's placeholder kept inside its box, `w` wide: as wide as the box less its insets, on one line, cut short
-- where the language makes it longer (it ran under the next field's label in German, #449).
local function fitPlaceholder(box, w)
    local ph = box.placeholder
    if type(ph) ~= "table" then return end   -- a select keeps its placeholder as a string
    box.phText = box.phText or ph:GetText() or ""
    local inner = math.max(8, w - 16)
    ph:ClearAllPoints()
    ph:SetPoint("LEFT", box, "LEFT", 8, 0)
    ph:SetWidth(inner)
    ph:SetJustifyH("LEFT")
    ph:SetWordWrap(false)
    fitText(ph, box.phText, inner)
end

-- A button whose label is one of `texts` (Decline or Cancel): as wide as the widest of them.
local function buttonFor(parent, texts, variant, h)
    local b = UI:CreateButton(parent, texts[1], 40, h or SP.FIELD)
    if variant then UI:SetButtonVariant(b, variant) end
    local w = 0
    for _, t in ipairs(texts) do
        b.label:SetText(t)
        w = math.max(w, textW(b.label))
    end
    b.label:SetText(texts[1])
    b:SetWidth(w + ((h or SP.FIELD) < SP.FIELD and 16 or 24))
    return b
end

-- A select as wide as its widest option, its text inset and arrow beside it.
local function fitDropdown(dd)
    local w, keep = 0, dd.label:GetText()
    for _, opt in ipairs(dd.options or {}) do
        dd.label:SetText(opt.text or tostring(opt.value))
        w = math.max(w, textW(dd.label))
    end
    dd.label:SetText(keep)
    dd:SetWidth(w + DROP_ARROW)
    return w + DROP_ARROW
end

-- A KPI (the mockup's .kpi) as wide as its number or its caption, whichever is wider. Returns whether it changed.
local function fitChip(chip)
    local w = math.max(KPI_MIN, textW(chip.value), textW(chip.label)) + 24
    if chip:GetWidth() ~= w then chip:SetWidth(w); return true end
    return false
end

-- Indices of `widths` in lines no wider than `w`, `gap` apart.
local function flowRows(widths, w, gap)
    local rows, cur, used = {}, {}, 0
    for i, iw in ipairs(widths) do
        local adv = (#cur > 0) and (gap + iw) or iw
        if #cur > 0 and used + adv > w then rows[#rows + 1] = cur; cur, used, adv = {}, 0, iw end
        cur[#cur + 1] = i
        used = used + adv
    end
    if #cur > 0 then rows[#rows + 1] = cur end
    return rows
end

-- The shown frames of `items` along lines inside `w` on `holder`, from `y0` down (align "RIGHT": from the right
-- edge), each line as tall as its tallest, the others centred on it. Returns the height used.
local function flowItems(holder, items, w, y0, gap, align)
    local shown, widths = {}, {}
    for _, it in ipairs(items) do
        if it:IsShown() then
            local iw = math.min(w, tonumber(it:GetWidth()) or 40)
            if iw < (tonumber(it:GetWidth()) or 0) then it:SetWidth(iw) end
            shown[#shown + 1], widths[#widths + 1] = it, iw
        end
    end
    if #shown == 0 then return 0 end
    local y = y0
    for _, row in ipairs(flowRows(widths, w, gap)) do
        local rowW, rowH = 0, 0
        for k, i in ipairs(row) do
            rowW = rowW + widths[i] + (k > 1 and gap or 0)
            rowH = math.max(rowH, tonumber(shown[i]:GetHeight()) or SP.FIELD)
        end
        local x = (align == "RIGHT") and (w - rowW) or 0
        for _, i in ipairs(row) do
            local it = shown[i]
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -(y + math.floor((rowH - (tonumber(it:GetHeight()) or rowH)) / 2)))
            x = x + widths[i] + gap
        end
        y = y + rowH + BTN_GAP
    end
    return y - BTN_GAP - y0
end

-- A frame on `card` laid as one of its rows by `place(holder, w)` (returns its height). opts: Card:Add's.
local function cardRow(card, place, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, card)
    holder:SetSize(1, 1)
    card:Add(holder, { gap = opts.gap, shown = opts.shown, place = function(_, w)
        local h = place(holder, w) or 0
        holder:SetSize(math.max(1, w), math.max(1, h))
        return h
    end })
    return holder
end

-- The screen's numbers (KPIs, holder.chips) at the left and its buttons (holder.buttons) at the right of one line;
-- where both do not fit, the buttons go on the next. Make both on the holder.
local function kpiRow(card, opts)
    local holder
    holder = cardRow(card, function(_, w)
        local chipsW, chipH = 0, 0
        for i, c in ipairs(holder.chips) do
            fitChip(c)
            chipsW = chipsW + c:GetWidth() + (i > 1 and SP.FIELD_GAP or 0)
            chipH = math.max(chipH, c:GetHeight())
        end
        local btnW, nb = 0, 0
        for _, b in ipairs(holder.buttons) do
            if b:IsShown() then
                btnW = btnW + b:GetWidth() + (nb > 0 and BTN_GAP or 0)
                nb = nb + 1
            end
        end
        local h = flowItems(holder, holder.chips, w, 0, SP.FIELD_GAP)
        if nb > 0 then
            if chipsW + SP.SECTION + btnW <= w then
                flowItems(holder, holder.buttons, w, math.max(0, math.floor((chipH - SP.FIELD) / 2)), BTN_GAP, "RIGHT")
                h = math.max(h, SP.FIELD)
            else
                local y = h > 0 and (h + SP.FIELD_GAP) or 0
                h = y + flowItems(holder, holder.buttons, w, y, BTN_GAP)
            end
        end
        return h
    end, opts)
    holder.chips, holder.buttons = {}, {}
    return holder
end

-- Fields and buttons of one form line (row:Field(label, control, spec), row.buttons): each label above its field
-- (Forms:MakeField), the buttons level with the boxes at the right. A field is at least spec.min and its label's
-- width; the growing ones (spec.grow, a weight) share the rest. Too narrow for one line: the first field takes a
-- line of its own and the others share the next; narrower still, one per line. A placeholder is kept in its box.
local function formRow(card, opts)
    local row
    local function need(s) return math.max(s.min or 60, textW(s.field.label)) end
    local function labelOf(list)
        for _, s in ipairs(list) do
            if (s.field.label:GetText() or "") ~= "" then return LABEL_H end
        end
        return 0
    end
    local function buttonsW()
        local w, n = 0, 0
        for _, b in ipairs(row.buttons) do
            if b:IsShown() then w = w + b:GetWidth() + (n > 0 and BTN_GAP or 0); n = n + 1 end
        end
        return w, n
    end
    -- The room a line takes beyond its fields' widths, or nil when it does not fit in `w`.
    local function free(list, withButtons, w)
        local total, weights = 0, 0
        for i, s in ipairs(list) do
            total = total + need(s) + (i > 1 and SP.FIELD_GAP or 0)
            weights = weights + (s.grow or 0)
        end
        local bw, nb = 0, 0
        if withButtons then bw, nb = buttonsW() end
        if nb > 0 then total = total + bw + (#list > 0 and SP.FIELD_GAP or 0) end
        if total > w then return nil end
        return w - total, weights, bw, nb
    end
    -- Lay `list` (and the buttons) on one line at `y`. Returns its height.
    local function line(list, y, withButtons, w)
        local extra, weights, _, nb = free(list, withButtons, w)
        if not extra then
            extra, weights = 0, 0
            nb = select(2, buttonsW())
        end
        local lh = labelOf(list)
        local lastGrow
        for i, s in ipairs(list) do if (s.grow or 0) > 0 then lastGrow = i end end
        local x, h, left = 0, 0, extra
        for i, s in ipairs(list) do
            local add = 0
            if weights > 0 and (s.grow or 0) > 0 then
                add = math.floor(extra * s.grow / weights)
                left = left - add
            end
            -- The rounding's last pixels go to the last growing field, so the line ends where the buttons start.
            if i == lastGrow then add = add + math.max(0, left) end
            local fw = need(s) + add
            if not withButtons and #list == 1 then fw = w end
            s.field:Place(fw)
            -- A field with no label sits level with its neighbours' boxes.
            local own = ((s.field.label:GetText() or "") ~= "") and LABEL_H or 0
            s.field:ClearAllPoints()
            s.field:SetPoint("TOPLEFT", row, "TOPLEFT", x, -(y + lh - own))
            fitPlaceholder(s.field.control, fw)
            s.laidW = fw
            x = x + fw + SP.FIELD_GAP
            h = math.max(h, lh + SP.FIELD)
        end
        if withButtons and nb > 0 then
            h = math.max(h, lh + flowItems(row, row.buttons, w, y + lh, BTN_GAP, "RIGHT"))
        end
        return h
    end
    row = cardRow(card, function(_, w)
        local all = row.specs
        if free(all, true, w) then return line(all, 0, true, w) end
        local rest = {}
        for i = 2, #all do rest[#rest + 1] = all[i] end
        if #all > 1 and free(rest, true, w) then
            local h1 = line({ all[1] }, 0, false, w)
            return h1 + SP.FIELD_GAP + line(rest, h1 + SP.FIELD_GAP, true, w)
        end
        local y = 0
        for _, s in ipairs(all) do y = y + line({ s }, y, false, w) + SP.FIELD_GAP end
        local bh = flowItems(row, row.buttons, w, y, BTN_GAP)
        return bh > 0 and (y + bh) or (y - SP.FIELD_GAP)
    end, opts)
    row.specs, row.buttons = {}, {}
    -- A field on the line: `control` made on the row, under `label` ("" for none). spec: min, grow.
    function row:Field(label, control, spec)
        spec = spec or {}
        spec.field = Forms:MakeField(self, label, control)
        self.specs[#self.specs + 1] = spec
        return control
    end
    return row
end

----------------------------------------------------------------------
-- A table on a card: its columns, laid in the client's language
----------------------------------------------------------------------
-- Lay `specs` across `w`: a fixed column as wide as it needs (spec.need: spec.w, its header, its widest sample),
-- the growing ones (spec.grow, a weight; never under spec.min) sharing what is left; while they would be under
-- their min, the optional columns go (spec.drop: the highest first). spec.when (a function) hides a column
-- outright. Sets spec.on, spec.x, spec.cw.
local function layColumns(specs, w)
    for _, s in ipairs(specs) do s.on = (not s.when) or (s.when() and true or false) end
    while true do
        local fixed, minGrow, weights, n = 0, 0, 0, 0
        for _, s in ipairs(specs) do
            if s.on then
                n = n + 1
                if s.grow then minGrow = minGrow + s.min; weights = weights + s.grow
                else fixed = fixed + s.need end
            end
        end
        local room = w - fixed - SP.CELL * math.max(0, n - 1)
        local worst
        if room < minGrow then
            for _, s in ipairs(specs) do
                if s.on and s.drop and (not worst or s.drop > worst.drop) then worst = s end
            end
        end
        if not worst then
            local x, left = 0, room
            local last
            for _, s in ipairs(specs) do if s.on and s.grow then last = s end end
            for _, s in ipairs(specs) do
                if s.on then
                    if s.grow then
                        s.cw = (s == last) and math.max(1, left) or math.max(1, math.floor(room * s.grow / weights))
                        left = left - s.cw
                    else
                        s.cw = s.need
                    end
                    s.x = x
                    x = x + s.cw + SP.CELL
                end
            end
            return
        end
        worst.on = false
    end
end

-- A table's header on `card` (the mockup's .t th) over columns `specs` ({ key, head, w, min, grow, drop, when,
-- justify, headX (the header's text that far in), samples (texts its cells may hold, measured at `size`) }).
-- Laid with the card at the rows' width (a list's rows stop GUTTER short of its right). Returns the header and
-- `cols`: cols.by[key] (the spec: on, x, cw), cols.v (bumped on every layout: a row re-lays its cells when it
-- differs from row.colsV).
local function tableHead(card, specs, opts)
    opts = opts or {}
    local head = UI:CreateTableHeader(card, SP.HIT)
    local probe = UI:CreateText(head, "", opts.size or SP.META)
    probe:Hide()
    local cols = { specs = specs, by = {}, v = 0 }
    for _, s in ipairs(specs) do
        cols.by[s.key] = s
        local hw = 0
        if s.head then
            s.fs = UI:CreateHeaderText(head, s.head, SP.META)
            s.fs:SetWordWrap(false)
            hw = textW(s.fs) + (s.headX or 0)
        end
        local sw = 0
        for _, t in ipairs(s.samples or {}) do probe:SetText(t); sw = math.max(sw, textW(probe)) end
        s.need = math.max(s.w or 0, hw, sw + (s.pad or 0))
        if s.grow then s.min = math.max(s.min or 80, hw) end
        s.on, s.x, s.cw = true, 0, s.need   -- until the card lays it out
    end
    card:Add(head, { h = SP.HIT, wide = true, gap = opts.gap, shown = opts.shown, place = function(f, w)
        f:SetSize(math.max(1, w), SP.HIT)
        layColumns(specs, w - 1 - GUTTER)
        cols.v = cols.v + 1
        for _, s in ipairs(specs) do
            if s.fs then s.fs:SetShown(s.on) end
            if s.fs and s.on then
                local hx = s.headX or 0
                s.fs:ClearAllPoints()
                s.fs:SetPoint("LEFT", f, "LEFT", 1 + s.x + hx, 0)
                s.fs:SetWidth(math.max(1, s.cw - hx))
                s.fs:SetJustifyH(s.justify or "LEFT")
            end
        end
        if cols.onLayout then cols.onLayout() end
        return SP.HIT
    end })
    return head, cols
end

-- A text of a row in column `s`: as wide as the column, cut short past it.
local function putCell(fs, row, s, y)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", s.x, y or 0)
    fs:SetWidth(math.max(1, s.cw))
    fs:SetJustifyH(s.justify or "LEFT")
    fs:SetWordWrap(false)
end

-- An item's icon and name in a row: row.icon, row.name; placed in a column by putItem.
local function itemCell(row)
    row.icon = UI:CreateIcon(row, ICON)
    row.name = UI:CreateText(row, "", 12)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
end

-- The icon at the column's left, the name after it to the column's right (raised `y` for a second line).
local function putItem(row, s, y)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", s.x, 0)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", s.x + ITEM_X, y or 0)
    row.name:SetWidth(math.max(1, s.cw - ITEM_X))
end

local function paintItem(row, id, l, suffix)
    local info = Bank():ItemInfo(id, l)
    row.icon.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    UI:SetIconQuality(row.icon, info.quality or 1)
    local qc = qualityColor(info.quality, row.paper or row)
    row.name:SetText((info.name or ("item:" .. tostring(id))) .. (suffix or ""))
    row.name:SetTextColor(qc.r, qc.g, qc.b)
    return info
end

-- The list of a card: a body that takes the card's room left (its fill row), the pooled rows on it and its empty
-- state (UI:CreateEmptyState) at its top. list:ShowEmpty(text) shows it with `text`, list:ShowEmpty() hides it.
local function listBody(card, rowH, create, draw, glyph)
    local body = card:Body(math.max(4 * rowH, BODY_MIN), { gap = 0 })
    local list = makeList(body, rowH, create, draw)
    list:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    local es = UI:CreateEmptyState(body, glyph or "?", 380)
    es:Hide()
    list.es = es
    function list:ShowEmpty(text)
        es:SetShown(text ~= nil)
        if not text then return end
        local w = UI:LaidWidth(body)
        es:SetWidth(math.max(200, math.min(420, (w > 0 and w or 420) - 4)))
        es:Set(text)
        es:ClearAllPoints()
        es:SetPoint("TOP", body, "TOP", 0, -SP.SECTION)
    end
    return list, body
end

-- A card's empty state on a row of its own (the screen has nothing to show at all), centred.
local function emptyRow(card, glyph, shown)
    local es
    local holder = cardRow(card, function(h, w)
        es:SetWidth(math.max(200, math.min(420, w)))
        es:Set(es.want or "")
        es:ClearAllPoints()
        es:SetPoint("TOP", h, "TOP", 0, -SP.SECTION)
        return SP.SECTION + (tonumber(es:GetHeight()) or 120)
    end, { shown = shown })
    es = UI:CreateEmptyState(holder, glyph, 380)
    holder.es = es
    return holder
end

-- A card's blurb (the mockup's .sm) wrapped at its width.
local function blurb(card, text, opts)
    local fs = card:Note(text, opts)
    fs:SetJustifyH("LEFT")
    return fs
end

local function emptyBankText()
    return L["Nobody with Guild OS has opened the guild bank yet. Open it once and every member sees it here."]
end

-- A sub-screen's board (UI:CreateBoard) on `p`, its cards' layout redone with board:Layout().
local function newBoard(p, key, opts)
    opts = opts or {}
    opts.name = "GuildOSBank" .. key .. "Board"
    return UI:CreateBoard(p, opts)
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
    local board = newBoard(p, "Inventory")
    local card = board:Card(L["Inventory"], { fill = true })

    -- The bank in four numbers.
    local top = kpiRow(card)
    for i, cap in ipairs({ L["Gold"], L["Items"], L["Free slots"], L["Last read"] }) do
        top.chips[i] = UI:CreateMetricChip(top, "—", cap)
    end
    local chips = top.chips

    -- Find, sort and filter: the search grows, each select as wide as its widest choice.
    local tools = formRow(card)
    local search = tools:Field("", UI:CreateInput(tools, 200, SP.FIELD, { placeholder = L["Search items…"], max = 60 }),
        { min = 180, grow = 1 })
    local sortDD = UI:CreateDropdown(tools, 150, SP.FIELD)
    sortDD:SetOptions({
        { value = "cat", text = L["By category"] }, { value = "name", text = L["By name"] },
        { value = "count", text = L["By quantity"] }, { value = "quality", text = L["By quality"] },
    })
    sortDD:SetValue("cat")
    tools:Field("", sortDD, { min = fitDropdown(sortDD) })
    local groupDD = UI:CreateDropdown(tools, 180, SP.FIELD)
    local gopts = { { value = "all", text = L["All categories"] } }
    for _, g in ipairs(GuildOS.GuildBankPlan.GROUPS) do gopts[#gopts + 1] = { value = g, text = L[GROUP_LABEL[g]] } end
    groupDD:SetOptions(gopts)
    groupDD:SetValue("all")
    tools:Field("", groupDD, { min = fitDropdown(groupDD) })

    -- The table: the item, how many, where (it goes first on a narrow window) and what a need still lacks.
    local NEED_BAR = 56
    local _, cols = tableHead(card, {
        { key = "item", head = L["Item"], grow = 1, min = 160, headX = ITEM_X },
        { key = "total", head = L["Total"], w = 40, justify = "RIGHT", samples = { "9999" } },
        { key = "where", head = L["Where"], w = 160, drop = 1 },
        { key = "need", head = L["Need"], w = 120, pad = NEED_BAR + 6,
          samples = { string.format(L["%d short"], 999), L["met"] } },
    }, { gap = SP.SECTION })
    local by = cols.by

    local list = listBody(card, ROW_H, function(row)
        itemCell(row)
        row.group = UI:CreateHeaderText(row, "", SP.META)
        row.group:SetPoint("LEFT", 0, 0)
        row.group:SetJustifyH("LEFT")
        row.group:SetWordWrap(false)
        row.total = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.total, 11, "tableNum")
        row.where = UI:CreateText(row, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        row.bar = UI:CreateProgressBar(row, NEED_BAR, 6)
        row.need = UI:CreateText(row, "", SP.META)
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
    end, function(row, it)
        if row.colsV ~= cols.v then
            row.colsV = cols.v
            putItem(row, by.item)
            row.group:SetWidth(math.max(1, by.item.cw + by.total.cw))
            putCell(row.total, row, by.total)
            if by.where.on then putCell(row.where, row, by.where) end
            row.bar:ClearAllPoints()
            row.bar:SetPoint("LEFT", row, "LEFT", by.need.x, 0)
            putCell(row.need, row, { x = by.need.x + NEED_BAR + 6, cw = by.need.cw - NEED_BAR - 6 })
        end
        local isHead = it.header and true or false
        row.group:SetShown(isHead)
        row.icon:SetShown(not isHead)
        row.name:SetShown(not isHead)
        row.total:SetShown(not isHead)
        row.where:SetShown(not isHead and by.where.on)
        if isHead then
            row.group:SetText(it.label)
            row.bar:Hide(); row.need:Hide()
            return
        end
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
            local col = have >= need and INK_OK or (have / need >= 0.6 and INK_WARN or INK_DANGER)
            row.need:SetText(have >= need and L["met"] or string.format(L["%d short"], need - have))
            row.need:SetTextColor(col.r, col.g, col.b)
        end
    end, "B")
    cols.onLayout = function() list:Update() end

    -- How to use the rows, and how many show.
    local hint = Forms:Soft(card, L["Shift-click: link in chat · Right-click: ask the officers · Alt-click (officer): set a need"], SP.META)
    hint:SetWordWrap(true)
    local countText = Forms:Soft(card, "", SP.META)
    countText:SetJustifyH("RIGHT")
    countText:SetWordWrap(false)
    cardRow(card, function(h, w)
        local cw = textW(countText)
        countText:ClearAllPoints()
        countText:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
        countText:SetWidth(math.max(1, cw))
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
        hint:SetWidth(math.max(1, w - cw - SP.SECTION))
        return math.max(textH(hint), 14)
    end, { gap = SP.FIELD_GAP })

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
                    out[#out + 1] = { header = true, label = string.format("%s · %d", L[GROUP_LABEL[it.group]], counts[it.group]) }
                end
                out[#out + 1] = it
            end
        end
        list:SetData(out)
        list:ShowEmpty(#index.list == 0 and emptyBankText() or nil)
        countText:SetText(string.format(L["%d of %d items"], #items, #index.list))

        local db = B:Store()
        chips[1]:SetValue(db.moneyNow and paperMoney(db.moneyNow) or "—")
        local total = 0
        for _, e in ipairs(index.list) do total = total + e.total end
        chips[2]:SetValue(tostring(total))
        local used, slots = B:Fill()
        chips[3]:SetValue(slots > 0 and string.format("%d / %d", slots - used, slots) or "—")
        local ts, by2 = B:Newest()
        chips[4]:SetValue(ts > 0 and GuildOS:TimeAgo(ts) or "—")
        chips[4].label:SetText(by2 and string.format(L["Read by %s"], by2) or L["Last read"])
        -- A number or a count wider than before lays the screen out again.
        local changed = math.ceil(textW(countText)) ~= (st.countW or -1)
        st.countW = math.ceil(textW(countText))
        for _, c in ipairs(chips) do if fitChip(c) then changed = true end end
        if changed then board:Layout() end
    end
    p.Draw = rebuild

    search:HookScript("OnTextChanged", function(self) st.query = self:GetText() or ""; rebuild() end)
    sortDD.onSelect = function(_, v) st.sort = v; rebuild() end
    groupDD.onSelect = function(_, v) st.group = v; rebuild() end
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
    local st = { tab = 1, organized = false, seen = true }
    local board = newBoard(p, "Tabs", { leftW = TABS_W })

    -- The bank's tabs, one button each (beside the grid; on a narrow window a line of them above it).
    local side = board:Card(L["Bank tabs"], { col = 1 })
    local tabButtons = {}
    for tab = 1, 8 do
        local b = UI:CreateButton(side, "", TABS_W - 2 * SP.PAD, TAB_BTN_H)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 34, 0)
        b.label:SetPoint("RIGHT", -48, 0)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(20, 20)
        b.icon:SetPoint("LEFT", 7, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.fill = UI:CreateText(b, "", SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(b.fill, SP.META, "tableNum")
        b.fill:SetPoint("RIGHT", -8, 0)
        b:SetScript("OnClick", function() st.tab = tab; p.Draw() end)
        tabButtons[tab] = b
    end
    side:Flow(tabButtons, { gapX = BTN_GAP })
    local perm = blurb(side, "")

    -- The tab: its slots as they are or organized, and the organizer under them.
    local main = board:Card(L["Bank"], { col = 2, fill = true })
    local title = main.title
    local fillText = Forms:Soft(main, "", SP.META)
    fillText:SetWordWrap(true)
    local asBtn = Forms:Pill(main, L["As it is"])
    local orgBtn = Forms:Pill(main, L["Organized"])
    asBtn:SetScript("OnClick", function() st.organized = false; p.Draw() end)
    orgBtn:SetScript("OnClick", function() st.organized = true; p.Draw() end)
    local function seen() return st.seen end
    cardRow(main, function(h, w)
        local pw = asBtn:GetWidth() + BTN_GAP + orgBtn:GetWidth()
        local textRoom = w - pw - SP.SECTION
        asBtn:ClearAllPoints(); orgBtn:ClearAllPoints()
        fillText:ClearAllPoints()
        fillText:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -4)
        if textRoom >= 160 then
            fillText:SetWidth(textRoom)
            orgBtn:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
            asBtn:SetPoint("RIGHT", orgBtn, "LEFT", -BTN_GAP, 0)
            return math.max(SP.HIT, textH(fillText) + 4)
        end
        fillText:SetWidth(w)
        local th = textH(fillText) + 4
        asBtn:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -(th + BTN_GAP))
        orgBtn:SetPoint("LEFT", asBtn, "RIGHT", BTN_GAP, 0)
        return th + BTN_GAP + SP.HIT
    end, { shown = seen })

    local grid = CreateFrame("Frame", nil, main)
    local cells = {}
    for i = 1, GRID_COLS * GRID_ROWS do
        local cell = CreateFrame("Button", nil, grid, "BackdropTemplate")
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(cell) })
        cell:SetBackdropColor(C.paperLight.r, C.paperLight.g, C.paperLight.b, 1)
        cell:SetBackdropBorderColor(C.paperRule.r, C.paperRule.g, C.paperRule.b, 1)
        cell.tex = cell:CreateTexture(nil, "ARTWORK")
        cell.tex:SetPoint("TOPLEFT", 2, -2)
        cell.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.count = UI:CreateText(cell, "", SP.META)
        GuildOS:ApplyFont(cell.count, SP.META, "tableNum")
        cell.count:SetPoint("BOTTOMRIGHT", -2, 2)
        cell:SetScript("OnEnter", function(self) if self.slot then showItemTooltip(self, self.slot.id, self.slot.l) end end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cell:SetScript("OnClick", function(self) if self.slot and IsShiftKeyDown() then linkToChat(self.slot.id, self.slot.l) end end)
        cells[i] = cell
    end
    local cellSize = 0
    main:Add(grid, { gap = SP.FIELD_GAP, shown = seen, place = function(_, w)
        local size = math.floor((w + SLOT_GAP) / GRID_COLS) - SLOT_GAP
        size = math.max(SLOT_MIN, math.min(SLOT_MAX, size))
        if size ~= cellSize then
            cellSize = size
            for i, cell in ipairs(cells) do
                local x, y = slotPosition(i)
                cell:SetSize(size, size)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", x * (size + SLOT_GAP), -y * (size + SLOT_GAP))
            end
        end
        local h = GRID_ROWS * (size + SLOT_GAP) - SLOT_GAP
        grid:SetSize(GRID_COLS * (size + SLOT_GAP) - SLOT_GAP, h)
        return h
    end })

    -- The organizer: what it would do, and the button that does it at the bank.
    local strip
    strip = cardRow(main, function(h, w)
        local chips, btns = strip.chips, strip.buttons
        local chipsW, chipH = 0, 0
        for i, c in ipairs(chips) do fitChip(c); chipsW = chipsW + c:GetWidth() + (i > 1 and SP.FIELD_GAP or 0); chipH = math.max(chipH, c:GetHeight()) end
        local btnW = 0
        for _, b in ipairs(btns) do if b:IsShown() then btnW = btnW + b:GetWidth() + (btnW > 0 and BTN_GAP or 0) end end
        local y = flowItems(h, chips, w, 0, SP.FIELD_GAP)
        if chipsW + SP.SECTION + btnW <= w then
            flowItems(h, btns, w, math.floor((chipH - SP.FIELD) / 2), BTN_GAP, "RIGHT")
        else
            y = y + SP.FIELD_GAP + flowItems(h, btns, w, y + SP.FIELD_GAP, BTN_GAP, "RIGHT")
        end
        strip.note:ClearAllPoints()
        strip.note:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -(y + SP.FIELD_GAP))
        strip.note:SetWidth(w)
        y = y + SP.FIELD_GAP + textH(strip.note)
        strip.progress:ClearAllPoints()
        if strip.progress:IsShown() then
            strip.progress:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -(y + BTN_GAP))
            strip.progress:SetWidth(w)
            y = y + BTN_GAP + 6
        end
        return y
    end, { gap = SP.SECTION, shown = seen })
    local movesChip = UI:CreateMetricChip(strip, "0", L["Moves"])
    local freedChip = UI:CreateMetricChip(strip, "0", L["Slots freed"])
    strip.chips = { movesChip, freedChip }
    local stop = Forms:Button(strip, L["Stop"])
    stop:SetScript("OnClick", function() B:StopSort("cancel") end)
    local organize = Forms:Button(strip, L["Organize at the bank"], "primary")
    organize:SetScript("OnClick", function() B:StartSort(st.tab) end)
    strip.buttons = { stop, organize }
    strip.note = Forms:Soft(strip, "", SP.META)
    strip.note:SetWordWrap(true)
    local note = strip.note
    local progress = UI:CreateProgressBar(strip, 100, 6)
    strip.progress = progress
    local empty = emptyRow(main, "T", function() return not st.seen end)

    p.Draw = function()
        local db = B:Store()
        local count = math.max(db.numTabs or 0, 0)
        for tab in pairs(db.tabs) do count = math.max(count, tab) end
        if not db.tabs[st.tab] then
            for tab = 1, count do if db.tabs[tab] then st.tab = tab; break end end
        end
        local layout = false
        for tab, b in ipairs(tabButtons) do
            local t = db.tabs[tab]
            if b:IsShown() ~= (tab <= count) then layout = true end
            b:SetShown(tab <= count)
            b.label:SetText(string.format("%d  %s", tab, (t and t.name) or L["Not seen yet"]))
            b.icon:SetTexture(t and t.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local used = 0
            if t then for _ in pairs(t.slots or {}) do used = used + 1 end end
            b.fill:SetText(t and string.format("%d/98", used) or "")
            UI:SetSelected(b, tab == st.tab)
        end
        Forms:SetOn(asBtn, not st.organized)
        Forms:SetOn(orgBtn, st.organized)

        local t = db.tabs[st.tab]
        if st.seen ~= (t ~= nil) then layout = true end
        st.seen = t ~= nil
        if B:IsOpen() then
            local _, _, _, canDeposit, _, remaining = GuildOS.Compat.GuildBankTabInfo(st.tab)
            perm:SetText(string.format(L["Your rank: %s · %s"], canDeposit and L["deposits"] or L["no deposits"],
                tonumber(remaining) == -1 and L["withdraws without limit"]
                    or string.format(L["%s withdrawals left today"], tostring(remaining or 0))))
        else
            perm:SetText(L["At the bank, this shows what your rank may do here."])
        end
        if not t then
            title:SetText(L["Bank"])
            fillText:SetText("")
            empty.es.want = emptyBankText()
            board:Layout()
            return
        end
        local preview, moves, full = B:Preview(st.tab)
        local shown = st.organized and preview or t.slots
        local used, after = 0, #preview
        for _ in pairs(t.slots) do used = used + 1 end
        GuildOS:SetTitleText(title, string.format("%d · %s", st.tab, t.name or ""))
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
                cell:SetBackdropBorderColor(C.paperRule.r, C.paperRule.g, C.paperRule.b, 1)
            end
        end
        movesChip:SetValue(tostring(moves))
        freedChip:SetValue("+" .. tostring(math.max(0, used - after)))

        local run = B:SortState()
        local can, why = B:CanOrganize(st.tab)
        local wasRun = stop:IsShown()
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
            if full and moves == 0 then note:SetText(L["This tab is full: free one slot and it can be put in order."])
            elseif moves == 0 then note:SetText(L["This tab is already in order."])
            elseif can then note:SetText(L["Merges stacks and sorts by category, quality and name, one move at a time."])
            else note:SetText(why or "") end
        end
        if wasRun ~= (run ~= nil) then layout = true end
        for _, c in ipairs(strip.chips) do if fitChip(c) then layout = true end end
        -- The lines above the grid and under it wrap as they change: laid out again whenever a text did.
        local key = (fillText:GetText() or "") .. "|" .. (note:GetText() or "") .. "|" .. (perm:GetText() or "")
        if key ~= st.texts then st.texts = key; layout = true end
        if layout then board:Layout() end
    end
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
    -- The ledger and, beside it (under it on a narrow window), the bank's gold and who gave most.
    local board = newBoard(p, "Ledger", { left = LEDGER_LEFT })
    local card = board:Card(L["Ledger"], { col = 1, fill = true })
    if UI.RegisterTourAnchor then UI:RegisterTourAnchor("bank.points", card) end   -- the tour (UI/Tour.lua)

    -- What to show: a pill per kind of line, and a member's name.
    local pills = {}
    for _, o in ipairs({ { "all", L["All"] }, { "d", L["Deposits"] }, { "w", L["Withdrawals"] }, { "m", L["Moves"] }, { "gold", L["Gold"] } }) do
        local b = Forms:Pill(card, o[2])
        b.key = o[1]
        b:SetScript("OnClick", function()
            st.kind = o[1]
            for _, x in ipairs(pills) do Forms:SetOn(x, x.key == st.kind) end
            p.Draw()
        end)
        pills[#pills + 1] = b
    end
    for _, x in ipairs(pills) do Forms:SetOn(x, x.key == st.kind) end
    local who = UI:CreateInput(card, 180, SP.FIELD, { placeholder = L["Member"], max = 40 })
    who:HookScript("OnTextChanged", function(self) st.who = (self:GetText() or ""):lower(); p.Draw() end)
    local filters = {}
    for _, b in ipairs(pills) do filters[#filters + 1] = b end
    filters[#filters + 1] = who
    card:Flow(filters, { gapX = BTN_GAP })
    fitPlaceholder(who, 180)

    local verbs = {}
    for _, v in pairs(VERB) do verbs[#verbs + 1] = L[v[1]] end
    local _, cols = tableHead(card, {
        { key = "when", head = L["When"], w = 64, samples = { GuildOS:TimeAgo(GetServerTime() - 50 * 60) } },
        { key = "who", head = L["Who"], grow = 1, min = 96 },
        { key = "verb", head = L["What"], w = 60, samples = verbs },
        { key = "item", head = L["Item"], grow = 3, min = 120 },
        -- The bank tax a withdrawal owes (Ley): only while the guild has one.
        { key = "tax", head = L["Tax"], w = 64, justify = "RIGHT", when = function() return st.taxOn end },
        { key = "qty", head = L["Qty"], w = 32, justify = "RIGHT", samples = { "999" } },
        { key = "tab", head = L["Tab"], w = 32, justify = "RIGHT", samples = { "8→8" } },
    }, { gap = SP.SECTION })
    local by = cols.by

    local list = listBody(card, ROW_H, function(row)
        row.when = UI:CreateText(row, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(row.when, 11, "tableNum")
        row.who = UI:CreateText(row, "", 12)
        row.verb = UI:CreateText(row, "", 11)
        row.itemText = UI:CreateText(row, "", 12)
        row.qty = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.qty, 11, "tableNum")
        row.tab = UI:CreateText(row, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(row.tab, 11, "tableNum")
        row.tax = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.tax, 11, "tableNum")
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.data and self.data.id then showItemTooltip(self, self.data.id) end
        end)
        row:SetScript("OnClick", function(self)
            if self.data and self.data.id and IsShiftKeyDown() then linkToChat(self.data.id) end
        end)
    end, function(row, e)
        if row.colsV ~= cols.v then
            row.colsV = cols.v
            putCell(row.when, row, by.when)
            putCell(row.who, row, by.who)
            putCell(row.verb, row, by.verb)
            putCell(row.itemText, row, by.item)
            putCell(row.qty, row, by.qty)
            putCell(row.tab, row, by.tab)
            if by.tax.on then putCell(row.tax, row, by.tax) end
            row.tax:SetShown(by.tax.on)
        end
        row.when:SetText(GuildOS:TimeAgo(e.t))
        local cc = classColor(e.n, row)
        row.who:SetText(shortName(e.n))
        row.who:SetTextColor(cc.r, cc.g, cc.b)
        local v = VERB[e.ty] or VERB.m
        local vc = UI:Ink(row, C[v[2]] or C.text)
        row.verb:SetText(L[v[1]])
        row.verb:SetTextColor(vc.r, vc.g, vc.b)
        if e.k == 0 then
            row.itemText:SetText(paperMoney(e.g))
            row.itemText:SetTextColor(C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
            row.qty:SetText("")
            row.tab:SetText("—")
        else
            local info = B:ItemInfo(e.id)
            local qc = qualityColor(info.quality, row)
            row.itemText:SetText(info.name or (e.id and ("item:" .. e.id)) or "?")
            row.itemText:SetTextColor(qc.r, qc.g, qc.b)
            row.qty:SetText(tostring(e.c or ""))
            row.tab:SetText(e.ty == "m" and e.t2 and string.format("%d→%d", e.k, e.t2) or tostring(e.k))
        end
        local tax = st.taxOn and B:LineTax(e) or nil
        row.tax:SetText(tax and (tax > 0 and paperMoney(tax) or "—") or "")
    end, "L")
    cols.onLayout = function() list:Update() end

    -- The side: the bank's gold and its last 30 days, who gave most, who owes the bank tax.
    local side = board:Card(L["Bank gold"], { col = 2 })
    local goldValue = UI:CreateText(side, "—", SP.KPI)
    GuildOS:ApplyFont(goldValue, SP.KPI, "metricValue")
    goldValue:SetTextColor(C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
    goldValue:SetWordWrap(false)
    local goldDelta = UI:CreateText(side, "", SP.META)
    goldDelta:SetWordWrap(false)
    side:Add(goldValue, { place = function(_, w)
        goldValue:SetWidth(math.max(1, math.min(w, textW(goldValue))))
        return SP.KPI + 4
    end })
    side:Add(goldDelta, { gap = 2, shown = function() return (goldDelta:GetText() or "") ~= "" end, place = function(_, w)
        goldDelta:SetWidth(math.max(1, w))
        return 14
    end })
    local chart = CreateFrame("Frame", nil, side)
    local base = chart:CreateTexture(nil, "BORDER")
    base:SetPoint("BOTTOMLEFT"); base:SetPoint("BOTTOMRIGHT")
    UI:Hairline(base)
    base:SetColorTexture(C.paperRule.r, C.paperRule.g, C.paperRule.b, 1)
    local bars = {}
    for i = 1, CHART_DAYS do
        local bar = chart:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(C.paperTitle.r, C.paperTitle.g, C.paperTitle.b, 0.85)
        bars[i] = bar
    end
    side:Add(chart, { gap = SP.FIELD_GAP, place = function(_, w)
        chart:SetSize(math.max(1, w), CHART_H)
        local barW = math.max(2, math.floor(w / CHART_DAYS))
        for i, bar in ipairs(bars) do
            bar:SetWidth(math.max(1, barW - 2))
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", (i - 1) * barW, 1)
        end
        return CHART_H
    end })
    blurb(side, L["Last 30 days, one bar a day"], { gap = 4 })

    local topTitle = UI:CreateSectionTitle(side, L["Top contributors · 30 days"], true)
    side:Add(topTitle, { gap = SP.SECTION })
    local tops = {}
    local topRows
    topRows = cardRow(side, function(h, w)
        local y = 0
        for _, r in ipairs(tops) do
            r:ClearAllPoints()
            if r:IsShown() then
                r:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -y)
                r:SetSize(math.max(1, w), 26)
                -- The figures at the right as wide as they are; the name takes the rest.
                local ww = math.min(math.floor(w * 0.6), textW(r.what))
                r.what:SetWidth(math.max(1, ww))
                r.name:SetWidth(math.max(1, w - ww - SP.CELL))
                y = y + 28
            end
        end
        return math.max(0, y - 2)
    end, { gap = SP.TITLE_GAP })
    for i = 1, TOP_N do
        local r = CreateFrame("Frame", nil, topRows)
        r:SetSize(200, 26)
        r.name = UI:CreateText(r, "", 12)
        r.name:SetPoint("TOPLEFT", 0, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.what = UI:CreateText(r, "", SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(r.what, SP.META, "tableNum")
        r.what:SetPoint("TOPRIGHT", 0, -1)
        r.what:SetJustifyH("RIGHT")
        r.what:SetWordWrap(false)
        r.bar = UI:CreateProgressBar(r, 200, 4)
        r.bar:SetPoint("BOTTOMLEFT", 0, 4)
        r.bar:SetPoint("BOTTOMRIGHT", 0, 4)
        r:Hide()
        tops[i] = r
    end
    -- Who owes the bank tax, most first (Ley): under the contributors, only while there is one.
    local taxTitle = UI:CreateSectionTitle(side, L["Bank tax owed"], true)
    side:Add(taxTitle, { gap = SP.SECTION, shown = function() return st.taxOn end })
    if UI.RegisterTourAnchor then UI:RegisterTourAnchor("bank.tax", taxTitle) end
    local taxRows = {}
    local taxHolder
    taxHolder = cardRow(side, function(h, w)
        local y = 0
        for _, r in ipairs(taxRows) do
            r:ClearAllPoints()
            if r:IsShown() then
                r:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -y)
                r:SetSize(math.max(1, w), 18)
                local ww = textW(r.what)
                r.what:SetWidth(math.max(1, ww))
                r.name:SetWidth(math.max(1, w - ww - SP.CELL))
                y = y + 18
            end
        end
        return y
    end, { gap = SP.TITLE_GAP, shown = function() return st.taxOn end })
    for i = 1, TAX_N do
        local r = CreateFrame("Frame", nil, taxHolder)
        r:SetSize(200, 18)
        r.name = UI:CreateText(r, "", 12)
        r.name:SetPoint("LEFT", 0, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.what = UI:CreateText(r, "", SP.META)
        GuildOS:ApplyFont(r.what, SP.META, "tableNum")
        r.what:SetPoint("RIGHT", 0, 0)
        r.what:SetJustifyH("RIGHT")
        r:Hide()
        taxRows[i] = r
    end
    local topNote = blurb(side, "", { gap = SP.SECTION })

    p.Draw = function()
        local taxOn = B.TaxOn and B:TaxOn() or false
        local layout = taxOn ~= st.taxOn
        st.taxOn = taxOn
        local rows = {}
        local ledger = B:Store().ledger
        for i = #ledger, 1, -1 do
            local e = ledger[i]
            local okKind = st.kind == "all" or (st.kind == "gold" and e.k == 0) or (st.kind ~= "gold" and e.k ~= 0 and e.ty == st.kind)
            if okKind and (st.who == "" or (e.n and e.n:lower():find(st.who, 1, true))) then rows[#rows + 1] = e end
        end
        -- Newest first by time; lines of one time keep the order they arrived in.
        local order = {}
        for i, e in ipairs(rows) do order[e] = i end
        table.sort(rows, function(a, b)
            if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
            return order[a] < order[b]
        end)
        list:SetData(rows)
        list:ShowEmpty(#rows == 0 and L["No ledger lines yet. They are read each time someone with Guild OS opens the bank."] or nil)

        local db = B:Store()
        goldValue:SetText(db.moneyNow and paperMoney(db.moneyNow) or "—")
        local readings, nowT = db.money, GetServerTime()
        local weekAgo
        for _, r in ipairs(readings) do if r.t <= nowT - 7 * 86400 then weekAgo = r.m end end
        local hadDelta = (goldDelta:GetText() or "") ~= ""
        if db.moneyNow and weekAgo then
            local d = db.moneyNow - weekAgo
            local col = d >= 0 and INK_OK or INK_DANGER
            goldDelta:SetText(string.format(L["%s%s in 7 days"], d >= 0 and "+" or "-", paperMoney(math.abs(d))))
            goldDelta:SetTextColor(col.r, col.g, col.b)
        else
            goldDelta:SetText("")
        end
        if hadDelta ~= ((goldDelta:GetText() or "") ~= "") then layout = true end
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
            if row:IsShown() ~= (x ~= nil) then layout = true end
            row:SetShown(x ~= nil)
            if x then
                local cc = classColor(x.name, row)
                row.name:SetText(string.format("%d  %s", i, shortName(x.name)))
                row.name:SetTextColor(cc.r, cc.g, cc.b)
                local what = string.format(L["%d items"], x.r.di)
                if x.r.dg > 0 then what = what .. " · " .. paperMoney(x.r.dg) end
                if officer and (x.r.wi > 0 or x.r.wg > 0) then
                    what = what .. " · " .. string.format(L["out %d"], x.r.wi)
                end
                row.what:SetText(what)
                row.bar:SetProgress(x.score / list2[1].score)
            end
        end
        topNote:SetText(officer and L["Items and gold deposited; withdrawals shown to officers only."]
            or L["Items and gold deposited."])

        -- The bank tax: who owes what, to officers; to a member, their own figure only.
        local owing = {}
        if st.taxOn then
            local _, taxList = B:TaxBalances()
            for _, r in ipairs(taxList) do
                if r.owed > 0 and (officer or B:IsMe(r.name)) then owing[#owing + 1] = r end
            end
            GuildOS:SetTitleText(taxTitle, string.format(L["Bank tax owed · %d%%"], B:TaxRate()))
        end
        for i, row in ipairs(taxRows) do
            local x = owing[i]
            if row:IsShown() ~= (x ~= nil) then layout = true end
            row:SetShown(x ~= nil)
            if x then
                local cc = classColor(x.name, row)
                row.name:SetText(shortName(x.name))
                row.name:SetTextColor(cc.r, cc.g, cc.b)
                row.what:SetText(paperMoney(x.owed))
            end
        end
        if layout or not st.laid then st.laid = true; board:Layout() end
    end
end

----------------------------------------------------------------------
-- Needs
----------------------------------------------------------------------
local function buildNeeds(p, panel)
    local B = Bank()
    local st = {}
    local board = newBoard(p, "Needs")
    local card = board:Card(L["Needs"], { fill = true })
    blurb(card, L["Officers say how many of each item the bank should hold. Every member sees what is short, here and on the item's tooltip."])

    -- How the needs stand, and what the officers do with the list.
    local top = kpiRow(card, { gap = SP.FIELD_GAP })
    local metChip = UI:CreateMetricChip(top, "—", L["Needs met"])
    local lowChip = UI:CreateMetricChip(top, "—", L["Under 60%"])
    top.chips = { metChip, lowChip }
    local announce = Forms:Button(top, L["Announce in guild chat"])
    announce:SetScript("OnClick", function()
        local lines = B:ShoppingList()
        if #lines == 0 then return end
        -- Whole lines only: a cut through an item link breaks the message.
        local text = L["Guild bank needs: "]
        for i, line in ipairs(lines) do
            local piece = (i > 1 and ", " or "") .. line
            if #text + #piece > ANNOUNCE_MAX then text = text .. " …"; break end
            text = text .. piece
        end
        SendChatMessage(text, "GUILD")
    end)
    local listBtn = Forms:Button(top, L["Shopping list"])
    listBtn:SetScript("OnClick", function()
        local lines = B:ShoppingList()
        if #lines == 0 then GuildOS:Print(L["The bank has everything it needs."]) end
        for _, line in ipairs(lines) do GuildOS:Print(line) end
    end)
    top.buttons = { announce, listBtn }

    -- An officer sets a need: the item (it grows), how many, a note, and the button.
    local function officer() return st.officer == true end
    local form = formRow(card, { gap = SP.SECTION, shown = officer })
    local item = form:Field(L["Item"], UI:CreateInput(form, 260, SP.FIELD, { placeholder = L["Shift-click an item, or type its name"], max = 255 }),
        { grow = 2 })
    acceptLinks(item)
    form.specs[1].min = math.min(ITEM_MAX, textW(item.placeholder) + 16)
    local qty = form:Field(L["Target"], UI:CreateInput(form, 72, SP.FIELD, { numeric = true, max = 6 }), { min = 72 })
    local noteBox = form:Field(L["Note"], UI:CreateInput(form, 140, SP.FIELD, { max = 80 }), { min = 140, grow = 1 })
    local add = Forms:Button(form, L["Set need"], "primary")
    form.buttons = { add }
    blurb(card, L["Only officers change the needs."], { gap = SP.SECTION, shown = function() return not officer() end })
    local function submit()
        local id = B:ParseItemInput(item:GetText())
        if not id then GuildOS:Print(L["That names no item. Shift-click one, or type a name the bank holds."]); return end
        if B:SetNeed(id, tonumber(qty:GetText()), noteBox:GetText()) then
            item:SetText(""); qty:SetText(""); noteBox:SetText("")
        end
    end
    add:SetScript("OnClick", submit)
    qty:HookScript("OnEnterPressed", submit)

    local _, cols = tableHead(card, {
        { key = "item", head = L["Item"], grow = 3, min = 160, headX = ITEM_X },
        { key = "have", head = L["HAVE / TARGET"], w = 56, justify = "RIGHT", samples = { "999 / 999" } },
        { key = "bar", head = L["Progress"], grow = 1, min = 80 },
        { key = "miss", head = L["Short"], w = 72, samples = { string.format(L["%d short"], 999), L["met"] } },
        { key = "remove", w = 20 },
    }, { gap = SP.SECTION })
    local by = cols.by

    local list = listBody(card, ROW_H + 8, function(row)
        itemCell(row)
        row.note = UI:CreateText(row, "", SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        row.have = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.have, 11, "tableNum")
        row.bar = UI:CreateProgressBar(row, 120, 8)
        row.miss = UI:CreateText(row, "", 11)
        GuildOS:ApplyFont(row.miss, 11, "tableNum")
        row.remove = UI:CreateCloseButton(row)
        row.remove:SetSize(20, 20)
        row.remove:SetScript("OnClick", function() if row.data then B:SetNeed(row.data.id, 0) end end)
        row:SetScript("OnEnter", function(self) self.hl:Show(); if self.data then showItemTooltip(self, self.data.id) end end)
        row:SetScript("OnClick", function(self, button)
            if not self.data then return end
            if IsShiftKeyDown() then linkToChat(self.data.id)
            elseif button == "RightButton" then panel.Prefill("requests", self.data.id) end
        end)
    end, function(row, r)
        if row.colsV ~= cols.v then
            row.colsV = cols.v
            putItem(row, by.item, 8)
            putCell(row.note, row, { x = by.item.x + ITEM_X, cw = by.item.cw - ITEM_X }, -8)
            putCell(row.have, row, by.have)
            row.bar:ClearAllPoints()
            row.bar:SetPoint("LEFT", row, "LEFT", by.bar.x, 0)
            row.bar:SetWidth(math.max(8, by.bar.cw))
            putCell(row.miss, row, by.miss)
            row.remove:ClearAllPoints()
            row.remove:SetPoint("LEFT", row, "LEFT", by.remove.x, 0)
        end
        paintItem(row, r.id)
        row.note:SetText(r.note or (r.by and string.format(L["by %s"], r.by)) or "")
        row.have:SetText(string.format("%d / %d", r.have, r.n))
        row.bar:SetProgress(r.have / r.n)
        local pct = r.have / r.n
        local col = pct >= 1 and INK_OK or (pct >= 0.6 and INK_WARN or INK_DANGER)
        row.miss:SetText(pct >= 1 and L["met"] or string.format(L["%d short"], r.n - r.have))
        row.miss:SetTextColor(col.r, col.g, col.b)
        row.remove:SetShown(GuildOS:IsOfficer())
    end, "N")
    cols.onLayout = function() list:Update() end

    p.Prefill = function(id)
        local link = B:LinkOf(id)
        item:SetText(link or tostring(id))
        qty:SetFocus()
    end
    p.Draw = function()
        local isOfficer = GuildOS:IsOfficer() and true or false
        local layout = isOfficer ~= st.officer
        st.officer = isOfficer
        announce:SetShown(isOfficer)
        local rows = B:NeedRows()
        local met, low = 0, 0
        for _, r in ipairs(rows) do
            if r.have >= r.n then met = met + 1 elseif r.have / r.n < 0.6 then low = low + 1 end
        end
        metChip:SetValue(#rows > 0 and string.format("%d / %d", met, #rows) or "—")
        lowChip:SetValue(tostring(low))
        list:SetData(rows)
        list:ShowEmpty(#rows == 0 and L["No needs yet. An officer sets one above, or Alt-clicks an item in the Inventory."] or nil)
        for _, c in ipairs(top.chips) do if fitChip(c) then layout = true end end
        if layout then board:Layout() end
    end
end

----------------------------------------------------------------------
-- Requests
----------------------------------------------------------------------
local REQ_TEXT = { open = "open", done = "filled", declined = "declined", cancelled = "cancelled" }

local function buildRequests(p)
    local B = Bank()
    local board = newBoard(p, "Requests")
    local card = board:Card(L["Requests"], { fill = true })

    -- Ask the officers for an item: the item (it grows), how many, why, and the button.
    local form = formRow(card)
    local item = form:Field(L["Item"], UI:CreateInput(form, 260, SP.FIELD, { placeholder = L["Shift-click an item, or type its name"], max = 255 }),
        { grow = 2 })
    acceptLinks(item)
    form.specs[1].min = math.min(ITEM_MAX, textW(item.placeholder) + 16)
    local qty = form:Field(L["Quantity"], UI:CreateInput(form, 72, SP.FIELD, { numeric = true, max = 4 }), { min = 72 })
    local noteBox = form:Field(L["Why"], UI:CreateInput(form, 140, SP.FIELD, { max = 80 }), { min = 140, grow = 1 })
    local ask = Forms:Button(form, L["Ask the officers"], "primary")
    form.buttons = { ask }
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

    -- A row's buttons, as wide as their widest label in this language.
    local probeFill = Forms:SmallButton(card, L["Filled"])
    local fillW = math.ceil(probeFill:GetWidth())
    probeFill:Hide()
    local probeNo = buttonFor(card, { L["Decline"], L["Cancel"] }, nil, SP.HIT)
    local noW = math.ceil(probeNo:GetWidth())
    probeNo:Hide()
    local _, cols = tableHead(card, {
        { key = "when", head = L["When"], w = 64, samples = { GuildOS:TimeAgo(GetServerTime() - 50 * 60) } },
        { key = "who", head = L["Who"], grow = 1, min = 104 },
        { key = "item", head = L["Item"], grow = 3, min = 150, headX = ITEM_X },
        { key = "state", head = L["State"], w = 132, drop = 1 },
        { key = "act", w = fillW + BTN_GAP + noW },
    }, { gap = SP.SECTION })
    local by = cols.by

    local list = listBody(card, ROW_H + 4, function(row)
        row.when = UI:CreateText(row, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(row.when, 11, "tableNum")
        row.who = UI:CreateText(row, "", 12)
        itemCell(row)
        row.state = UI:CreateText(row, "", 11)
        row.b1 = Forms:SmallButton(row, L["Filled"])
        row.b1:SetWidth(fillW)
        row.b2 = buttonFor(row, { L["Decline"], L["Cancel"] }, nil, SP.HIT)
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
        if row.colsV ~= cols.v then
            row.colsV = cols.v
            putCell(row.when, row, by.when)
            putCell(row.who, row, by.who)
            putItem(row, by.item)
            if by.state.on then putCell(row.state, row, by.state) end
            row.b2:ClearAllPoints()
            row.b2:SetPoint("RIGHT", row, "LEFT", by.act.x + by.act.cw, 0)
            row.b1:ClearAllPoints()
            row.b1:SetPoint("RIGHT", row.b2, "LEFT", -BTN_GAP, 0)
        end
        row.when:SetText(GuildOS:TimeAgo(r.ts))
        local cc = classColor(r.who, row)
        row.who:SetText(shortName(r.who))
        row.who:SetTextColor(cc.r, cc.g, cc.b)
        local have = B:CountOf(r.item)
        paintItem(row, r.item, nil, string.format(" × %d", r.n) .. (r.note and ("  " .. hex(C.paperSoft) .. r.note .. "|r") or ""))
        local col = (r.st == "open" and C.paperInk) or (r.st == "done" and INK_OK) or C.paperSoft
        local stateText = L[REQ_TEXT[r.st] or "open"]
        if r.st == "open" then stateText = stateText .. " · " .. string.format(L["bank has %d"], have)
        elseif r.by then stateText = stateText .. " · " .. r.by end
        row.state:SetText(stateText)
        row.state:SetTextColor(col.r, col.g, col.b)
        row.state:SetShown(by.state.on)
        local officer = GuildOS:IsOfficer()
        local mine = B:IsMe(r.who)
        row.b1:SetShown(r.st == "open" and officer)
        row.b2:SetShown(r.st == "open" and (officer or mine))
        row.b2.label:SetText((mine and not officer) and L["Cancel"] or L["Decline"])
    end, "R")
    cols.onLayout = function() list:Update() end

    p.Prefill = function(id)
        item:SetText(B:LinkOf(id) or tostring(id))
        qty:SetFocus()
    end
    p.Draw = function()
        local rows = B:RequestRows()
        list:SetData(rows)
        list:ShowEmpty(#rows == 0 and L["No requests. Ask for an item above, or right-click it in the Inventory."] or nil)
    end
end

----------------------------------------------------------------------
-- Cleanup (officers)
----------------------------------------------------------------------
local VERDICT = {
    sell = { "Sell", "warn" }, review = { "Review", "textSoft" }, keep = { "Keep", "ok" },
}

-- Why a cleanup row has its verdict, in one line.
local function whyText(r)
    local why = {}
    for _, k in ipairs(r.reasons) do why[#why + 1] = L[GuildOS.GuildBankCleanup.REASON[k]] end
    if r.level and r.level > 0 then why[#why + 1] = string.format(L["level %d"], r.level) end
    if r.days and r.days > 0 then why[#why + 1] = string.format(L["%d days in the bank"], r.days) end
    if r.taken > 0 then why[#why + 1] = string.format(L["taken %d times in 60 days"], r.taken) end
    return table.concat(why, " · ")
end

-- What a cleanup row is worth: where it sells for "sell", its vendor value otherwise.
local function valueText(r)
    if r.verdict == "sell" then
        if r.where == "ah" and r.ah then return L["AH"] .. " " .. paperMoney(r.ah) end
        if r.noValue then return L["no vendor value"] end
        return paperMoney(r.vendor)
    end
    if r.vendorEach and r.vendorEach > 0 then return paperMoney(r.vendorEach * r.have) end
    return ""
end

-- Mark or unmark a cleanup row, for the amount that may go.
local function toggleMark(r)
    if r then GuildOS.GuildBankCleanup:SetMark(r.key, not r.marked, r.out > 0 and r.out < r.have and r.out or nil) end
end

local function buildCleanup(p)
    local CL = GuildOS.GuildBankCleanup
    local st = { show = "sell" }
    local board = newBoard(p, "Cleanup")
    local card = board:Card(L["Cleanup"], { fill = true })
    if UI.RegisterTourAnchor then UI:RegisterTourAnchor("bank.cleanup", card) end
    local function officer() return st.officer == true end

    blurb(card, L["What the bank holds that nobody takes. Mark what goes; at the bank the bar takes it out, at a vendor it sells only that, and the gold goes back in."],
        { shown = officer })
    local top = kpiRow(card, { gap = SP.FIELD_GAP, shown = officer })
    for i, cap in ipairs({ L["To sell"], L["Gold back"], L["Slots freed"], L["Marked"] }) do
        top.chips[i] = UI:CreateMetricChip(top, "—", cap)
    end
    local chips = top.chips

    -- Which verdict to list, the level under which an item counts as low (the guild's setting), and the marks.
    local pills = {}
    for _, o in ipairs({ { "sell", L["Sell"] }, { "review", L["Review"] }, { "keep", L["Keep"] }, { "all", L["All"] } }) do
        local b = Forms:Pill(card, o[2])
        b.key = o[1]
        b:SetScript("OnClick", function()
            st.show = o[1]
            for _, x in ipairs(pills) do Forms:SetOn(x, x.key == st.show) end
            p.Draw()
        end)
        pills[#pills + 1] = b
    end
    for _, x in ipairs(pills) do Forms:SetOn(x, x.key == st.show) end
    card:Flow(pills, { gapX = BTN_GAP, gap = SP.SECTION, shown = officer })
    local tools = formRow(card, { shown = officer })
    local lowDD = UI:CreateDropdown(tools, 70, SP.FIELD)
    local opts = {}
    for lv = 10, GuildOS.Client.maxLevel - 10, 10 do opts[#opts + 1] = { value = lv, text = tostring(lv) } end
    lowDD:SetOptions(opts)
    lowDD.onSelect = function(_, v) GuildOS:SetSetting("gbankCleanLow", v); p.Draw() end
    tools:Field(L["Low level below"], lowDD, { min = math.max(72, fitDropdown(lowDD)) })
    local markAll = Forms:Button(tools, L["Mark all suggested"], "primary")
    markAll:SetScript("OnClick", function()
        local n = CL:MarkSuggested()
        GuildOS:Print(string.format(L["%d items marked to go."], n))
    end)
    local clear = Forms:Button(tools, L["Clear marks"])
    clear:SetScript("OnClick", function() CL:ClearMarks() end)
    tools.buttons = { clear, markAll }

    local verdicts = {}
    for _, v in pairs(VERDICT) do verdicts[#verdicts + 1] = L[v[1]] .. " 99" end
    local _, cols = tableHead(card, {
        { key = "item", head = L["Item"], grow = 2, min = 150, headX = ITEM_X },
        { key = "verdict", head = L["Verdict"], w = 56, samples = verdicts },
        { key = "why", head = L["Why"], grow = 3, min = 100, drop = 1 },
        { key = "value", head = L["Value"], w = 72, justify = "RIGHT" },
        { key = "mark", w = 18 },
    }, { gap = SP.SECTION, shown = officer })
    local by = cols.by

    local list, body = listBody(card, ROW_H + 4, function(row)
        row.mark = UI:CreateCheckbox(row, "", 14)
        row.mark:SetWidth(18)
        itemCell(row)
        row.verdict = UI:CreateText(row, "", 11)
        row.why = UI:CreateText(row, "", 11, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        row.value = UI:CreateText(row, "", 11)
        local function toggle() toggleMark(row.data) end
        row.mark.checkbox.onChanged = function() toggle() end
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.data then showItemTooltip(self, self.data.id, self.data.l) end
        end)
        row:SetScript("OnClick", function(self)
            if self.data and IsShiftKeyDown() then linkToChat(self.data.id, self.data.l) else toggle() end
        end)
    end, function(row, r)
        if row.colsV ~= cols.v then
            row.colsV = cols.v
            putItem(row, by.item)
            putCell(row.verdict, row, by.verdict)
            if by.why.on then putCell(row.why, row, by.why) end
            putCell(row.value, row, by.value)
            row.mark:ClearAllPoints()
            row.mark:SetPoint("LEFT", row, "LEFT", by.mark.x, 0)
        end
        paintItem(row, r.id, r.l, string.format(" × %d", r.have))
        local v = VERDICT[r.verdict]
        local vc = UI:Ink(row, C[v[2]] or C.text)
        local verdictText = L[v[1]]
        if r.verdict == "sell" and r.out < r.have then verdictText = verdictText .. " " .. r.out end
        row.verdict:SetText(verdictText)
        row.verdict:SetTextColor(vc.r, vc.g, vc.b)
        row.why:SetText(whyText(r))
        row.why:SetShown(by.why.on)
        row.value:SetText(valueText(r))
        row.mark.checkbox:SetChecked(r.marked)
    end, "C")
    cols.onLayout = function() list:Update() end
    -- A member: why the cleanup is not theirs, in place of all of it.
    local gate = emptyRow(card, "!", function() return not officer() end)
    gate.es.want = L["Only officers decide what leaves the bank. Ask an officer, or set your guild's officer ranks in Settings."]
    local parts = { top, tools, body }
    for _, b in ipairs(pills) do parts[#parts + 1] = b end

    p.Draw = function()
        local isOfficer = GuildOS:IsOfficer() and true or false
        local layout = isOfficer ~= st.officer
        st.officer = isOfficer
        for _, part in ipairs(parts) do part:SetShown(isOfficer) end
        gate:SetShown(not isOfficer)
        if not isOfficer then
            if layout then board:Layout() end
            return
        end
        lowDD:SetValue(CL:LowBelow())
        local rows = CL:Rows()
        local items, value, slots = CL:Summary(rows)
        chips[1]:SetValue(tostring(items))
        chips[2]:SetValue(value > 0 and paperMoney(value) or "—")
        chips[3]:SetValue("+" .. slots)
        local owed = CL:Owed()
        chips[4]:SetValue(tostring(CL:MarkedCount()))
        chips[4].label:SetText(owed > 0 and string.format(L["Marked · %s to deposit"], paperMoney(owed)) or L["Marked"])
        local shown = {}
        for _, r in ipairs(rows) do
            if st.show == "all" or r.verdict == st.show then shown[#shown + 1] = r end
        end
        list:SetData(shown)
        list:ShowEmpty(#shown == 0 and (#rows == 0 and emptyBankText() or L["Nothing here: try another verdict above."]) or nil)
        for _, c in ipairs(chips) do if fitChip(c) then layout = true end end
        if layout then board:Layout() end
    end
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
        -- Officers only: what to take out and sell.
        -- Always there (the officer check runs when it draws: the roster may not be in when the window
        -- is built); a member sees why it is empty.
        { key = "cleanup",   label = L["Cleanup"],   build = buildCleanup, absent = not GuildOS.GuildBankCleanup },
    }
    local panels, tabs, built = {}, {}, {}
    local active
    local api = {}

    local function select(key)
        local ok = false
        for _, s in ipairs(SUBS) do if s.key == key and not s.absent then ok = true end end
        if not ok then key = "inventory" end
        active = key
        for _, t in ipairs(tabs) do t:SetActive(t.key == key) end
        for k, p in pairs(panels) do if k ~= key then p:Hide() end end
        local p = panels[key]
        if not built[key] then
            built[key] = true
            -- The builder hangs its redraw and its prefill on the sub-panel, and lays its board of cards on it.
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
      if not s.absent then
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
    UI:CollapsibleSubBar(container, subBar, function() return panels end)   -- the Workshop's entries (#445)
    container.ActiveSub = function() return active end
    container.panels = panels
end

local bar   -- the bar over the game's guild bank, below

----------------------------------------------------------------------
-- What the bar and the drawer share: the Salão's look on the game's guild bank (#449 phase 3)
----------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"
local BTN_PAD = 12   -- a button's label to its edge, each side

-- A frame's explanation in its tooltip, where a line of text beside it had no room: `title` in the soft gold,
-- then `lines` (a list, or a function of the frame that returns one; an entry is a string, in white, or
-- { text, colour }). Hooked, so a button keeps its own hover. Returns the frame.
local function explain(frame, title, lines)
    frame.tipTitle, frame.tipLines = title, lines
    if frame.__explained then return frame end
    frame.__explained = true
    frame:EnableMouse(true)
    frame:HookScript("OnEnter", function(self)
        local list = self.tipLines
        if type(list) == "function" then list = list(self) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tipTitle or "", C.gold2.r, C.gold2.g, C.gold2.b)
        for _, line in ipairs(list or {}) do
            if type(line) == "table" then
                local c = line[2] or C.text
                GameTooltip:AddLine(line[1], c.r, c.g, c.b, true)
            else
                GameTooltip:AddLine(line, 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

-- A button as wide as its label in the client's language, BTN_PAD each side, never under `minW`.
local function fitButton(b, minW)
    local w = math.max(minW or 0, math.ceil(b.label:GetStringWidth() or 0) + 2 * BTN_PAD)
    b:SetWidth(w)
    return w
end

-- Two buttons of one pair (Organize tab and Organize all, Pause and Stop) as wide as the wider.
local function fitPair(a, b, minW)
    local w = math.max(fitButton(a, minW), fitButton(b, minW))
    a:SetWidth(w); b:SetWidth(w)
    return w
end

----------------------------------------------------------------------
-- The cleanup drawer beside the game's guild bank (officers, #384): mark what goes, take it out and
-- put the gold back without leaving the bank. The bar's Cleanup button opens and closes it.
-- A floating window of the kit (Kit:Dress): its summary, the verdicts as one segmented control with their
-- counts, "All suggested" over the rows' own boxes, the rows (the item framed in its quality, its name in that
-- quality, its value at the right, why on a second line, all of it in the tooltip), and a footer with the three
-- steps (the one to do now lit) and the one button that does it.
----------------------------------------------------------------------
local DRAWER_W     = 340
local DRAWER_ROW_H = 40    -- a row: the item and its value, why on a second line
local DRAWER_ICON  = 26
local DRAWER_CHECK = 16    -- a mark's box: the rows' and "All suggested"'s, one column
local TAB_CLEAR    = 44    -- how far the game's tab buttons stand out past the bank's right edge, where unmeasured
local STEP_DISC    = 18    -- a step's numbered disc
local STEP_GAP     = 6     -- a step to the line that joins it to the next
local STEP_LINE    = 10    -- that line, at least
local drawer, showDrawer

-- How far the game's own buttons down the bank's right edge (its tabs, the one that buys a tab) stand out past
-- it: the drawer docks beyond them, never under them.
local function sideClearance(host)
    local right = host.GetRight and host:GetRight()
    local clear = 0
    for _, b in ipairs(GuildOS.Compat.GuildBankSideButtons(host)) do
        if b:IsShown() then
            local r = b:GetRight()
            if right and r then clear = math.max(clear, r - right) else clear = math.max(clear, TAB_CLEAR) end
        end
    end
    return math.ceil(clear)
end

-- One choice of a few as a segmented control: the Salão's pills in a dark track, each segment its name and a
-- count, the chosen one the soft gold pill. items = { { key, label } }; onPick(key). seg.buttons (b.key, b.label,
-- b.count); seg:Select(key); seg:SetCount(key, n).
local function segmented(parent, items, width, onPick)
    local Style = GuildOS.Style
    local seg = CreateFrame("Frame", nil, parent)
    seg:SetSize(width, UI.SP.HIT + 4)
    local track = Style:Three(seg, "pill", "BACKGROUND", 0)
    track:SetColor(C.well)
    local edge = Style:Three(seg, "pill-line", "BACKGROUND", 1)
    edge:SetColor(C.lineHi)
    local n = #items
    local segW = math.floor((width - 4) / n)
    seg.buttons = {}
    local function center(b)
        local lw = math.ceil(b.label:GetStringWidth() or 0)
        local cw = math.ceil(b.count:GetStringWidth() or 0)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", b, "CENTER", -math.floor((lw + 5 + cw) / 2), 0)
        b.count:ClearAllPoints()
        b.count:SetPoint("LEFT", b.label, "RIGHT", 5, 0)
    end
    for i, it in ipairs(items) do
        local b = UI:CreateTab(seg, it[2], segW)
        b:SetWidth(segW)
        b:SetPoint("LEFT", seg, "LEFT", 2 + (i - 1) * segW, 0)
        b.key = it[1]
        b.count = UI:CreateText(b, "0", UI.SP.META)
        GuildOS:ApplyFont(b.count, UI.SP.META, "tableNum")
        b:SetScript("OnClick", function() seg:Select(it[1]); onPick(it[1]) end)
        b:HookScript("OnEnter", function(self) center(self) end)
        b:HookScript("OnLeave", function(self) center(self) end)
        seg.buttons[i] = b
        center(b)
    end
    function seg:Select(key)
        self.key = key
        for _, b in ipairs(self.buttons) do
            b:SetActive(b.key == key)
            local c = b.key == key and C.onGold or C.textSoft
            b.count:SetTextColor(c.r, c.g, c.b, b.key == key and 0.8 or 1)
            b:SetWidth(segW)
            center(b)
        end
    end
    function seg:SetCount(key, count)
        for _, b in ipairs(self.buttons) do
            if b.key == key then b.count:SetText(tostring(count or 0)); center(b) end
        end
    end
    seg.segW = segW
    return seg
end

-- The cleanup's three steps as small numbered discs joined by a line: the one to do now in the soft gold with its
-- name lit, those done in the metal's gold, those to come dim. labels = { text, ... }, tips = { text, ... } (each
-- step's tooltip). s.parts (p.disc, p.label, p.state); s:Set(current); s:Layout(width), which keeps the steps
-- inside `width` (only the lit step named when the three names do not fit) and sets s.laidW.
local function stepper(parent, labels, tips)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(STEP_DISC)
    s.parts = {}
    for i, text in ipairs(labels) do
        local p = CreateFrame("Frame", nil, s)
        p:SetHeight(STEP_DISC)
        p.disc = UI:CreateGlyph(p, STEP_DISC)
        p.disc:SetPoint("LEFT", 0, 0)
        p.label = UI:CreateText(p, text, UI.SP.META)
        p.label:SetPoint("LEFT", p.disc, "RIGHT", 5, 0)
        p.label:SetJustifyH("LEFT")
        p.label:SetWordWrap(false)
        if i > 1 then
            p.line = s:CreateTexture(nil, "ARTWORK")
            p.line:SetTexture(WHITE)
            UI:Hairline(p.line)
        end
        explain(p, string.format("%d · %s", i, text), { tips[i] })
        s.parts[i] = p
    end
    function s:Set(current)
        self.current = current
        for i, p in ipairs(self.parts) do
            p.state = (i == current and "now") or (i < current and "done") or "next"
            local disc = (p.state == "now" and C.gold2) or (p.state == "done" and C.metal2) or C.lineHi
            p.disc:Set(tostring(i), disc)
            p.disc.orb:SetVertexColor(disc.r, disc.g, disc.b, p.state == "done" and 0.6 or 1)
            local ink = p.state == "next" and C.textSoft or C.onGold
            p.disc.letter:SetTextColor(ink.r, ink.g, ink.b)
            GuildOS:ApplyFont(p.label, UI.SP.META, p.state == "now" and "button" or nil)
            local lc = p.state == "now" and C.gold or C.textSoft
            p.label:SetTextColor(lc.r, lc.g, lc.b)
            if p.line then
                local on = i <= current
                local c = on and C.metal2 or C.lineHi
                p.line:SetVertexColor(c.r, c.g, c.b, 1)
            end
        end
    end
    function s:Layout(width)
        local n = #self.parts
        local function natural(compact)
            local sum = 0
            for _, p in ipairs(self.parts) do
                local named = not compact or p.state == "now"
                p.w = STEP_DISC + (named and (5 + math.ceil(p.label:GetStringWidth() or 0)) or 0)
                sum = sum + p.w
            end
            return sum
        end
        local sum = natural(false)
        local joins = (n - 1) * (2 * STEP_GAP + STEP_LINE)
        self.compact = sum + joins > width
        if self.compact then sum = natural(true) end
        if sum + joins > width then
            -- Even the lit step's name alone is too long: it is cut to the room left.
            for _, p in ipairs(self.parts) do
                if p.state == "now" then
                    local lw = math.max(10, p.w - (sum + joins - width) - STEP_DISC - 5)
                    p.label:SetWidth(lw)
                    sum = sum - p.w + STEP_DISC + 5 + lw
                    p.w = STEP_DISC + 5 + lw
                end
            end
        end
        local line = n > 1 and math.floor((width - sum - (n - 1) * 2 * STEP_GAP) / (n - 1)) or 0
        local x = 0
        for _, p in ipairs(self.parts) do
            local named = not self.compact or p.state == "now"
            p.label:SetShown(named)
            if p.line then
                p.line:ClearAllPoints()
                p.line:SetPoint("LEFT", self, "LEFT", x + STEP_GAP, 0)
                p.line:SetWidth(math.max(1, line))
                x = x + 2 * STEP_GAP + line
            end
            p:ClearAllPoints()
            p:SetPoint("LEFT", self, "LEFT", x, 0)
            p:SetWidth(p.w)
            p.x = x
            x = x + p.w
        end
        self.laidW = x
        self:SetWidth(width)
    end
    return s
end

local function buildDrawer()
    local B, CL, Kit = Bank(), GuildOS.GuildBankCleanup, GuildOS.Kit
    local INNER = DRAWER_W - 2 * Kit.PAD
    local st = { show = "sell" }
    drawer = CreateFrame("Frame", "GuildOSGuildBankCleanup", UIParent, "BackdropTemplate")
    drawer:SetWidth(DRAWER_W)
    drawer:SetFrameStrata("MEDIUM")   -- the bank's own: open bags beside it stay clickable
    drawer:SetToplevel(true)
    drawer:SetClampedToScreen(true)
    drawer:EnableMouse(true)
    drawer:Hide()   -- frames are born shown; the bar's button shows it
    Kit:Dress(drawer, L["Cleanup"], { onClose = function() showDrawer(false) end })
    drawer.inner = INNER

    -- What selling would make, in one line (two where the language needs them).
    local summary = UI:CreateText(drawer, "", SP.BODY, C.text.r, C.text.g, C.text.b)
    summary:SetPoint("TOPLEFT", Kit.PAD, -(Kit.HEADER_H + 12))
    summary:SetWidth(INNER)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(true)
    drawer.summary = summary

    local seg = segmented(drawer, { { "sell", L["Sell"] }, { "review", L["Review"] }, { "keep", L["Keep"] } }, INNER,
        function(k) st.show = k; drawer:Draw() end)
    seg:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -SP.FIELD_GAP)
    seg:Select("sell")
    drawer.seg = seg

    local all = UI:CreateCheckbox(drawer, L["All suggested"], DRAWER_CHECK)
    all:SetPoint("TOPLEFT", seg, "BOTTOMLEFT", 0, -10)
    all:SetWidth(INNER)
    all.checkbox.onChanged = function(_, on) CL:MarkSuggested(not on) end
    explain(all.checkbox, L["All suggested"], { L["Marks every item the cleanup suggests selling; untick to unmark them."] })

    local list = makeList(drawer, DRAWER_ROW_H, function(row)
        row.mark = UI:CreateCheckbox(row, "", DRAWER_CHECK)
        row.mark:SetPoint("LEFT", 4, 0)
        row.mark:SetWidth(DRAWER_CHECK)
        row.mark.checkbox.onChanged = function() toggleMark(row.data) end
        row.icon = UI:CreateIcon(row, DRAWER_ICON)
        row.icon:SetPoint("LEFT", 4 + DRAWER_CHECK + 6, 0)
        row.value = UI:CreateText(row, "", SP.META)
        GuildOS:ApplyFont(row.value, SP.META, "tableNum")
        row.value:SetPoint("TOPRIGHT", -2, -7)
        row.value:SetJustifyH("RIGHT")
        row.name = UI:CreateText(row, "", SP.BODY)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.why = UI:CreateText(row, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.why:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
        row.why:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.why:SetJustifyH("LEFT")
        row.why:SetWordWrap(false)
        -- The item's own tooltip, then the verdict and the whole of why (the row cuts it to one line).
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            local r = self.data
            if not r then return end
            showItemTooltip(self, r.id, r.l)
            local v = VERDICT[r.verdict] or VERDICT.review
            local vc = C[v[2]] or C.text
            GameTooltip:AddLine(" ")
            local value = valueText(r)
            GameTooltip:AddLine(L[v[1]] .. (value ~= "" and ("  " .. value) or ""), vc.r, vc.g, vc.b)
            local why = whyText(r)
            if why ~= "" then GameTooltip:AddLine(why, 1, 1, 1, true) end
            GameTooltip:AddLine(L["Click: mark it to go · Shift-click: link in chat"], C.textSoft.r, C.textSoft.g, C.textSoft.b, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnClick", function(self)
            if self.data and IsShiftKeyDown() then linkToChat(self.data.id, self.data.l) else toggleMark(self.data) end
        end)
    end, function(row, r)
        local suffix = string.format(" × %d", r.have)
        if r.verdict == "sell" and r.out < r.have then suffix = suffix .. " · " .. L["Sell"] .. " " .. r.out end
        paintItem(row, r.id, r.l, suffix)
        row.value:SetText(valueText(r))
        row.why:SetText(whyText(r))
        row.mark.checkbox:SetChecked(r.marked)
    end)
    -- On the window's dark body the list is the body itself, a line under each row (no square well).
    list:SetBackdropColor(0, 0, 0, 0)
    list:SetBackdropBorderColor(0, 0, 0, 0)
    -- The rows' boxes under "All suggested"'s: a row starts 1 in from the list, its box 4 in from the row.
    list:SetPoint("TOPLEFT", all, "BOTTOMLEFT", -5, -6)
    local empty = UI:CreateEmptyState(list, "0", INNER - 24)
    empty:SetPoint("CENTER", list, "CENTER", -4, 0)
    empty:Hide()
    list.empty = empty
    drawer.list, drawer.emptyState = list, empty

    -- The footer: the steps across it, a line on what to do next when there is one, and the button that does it
    -- at the right (Stop beside it while stacks come out), what is marked at the left.
    local foot = Kit:Footer(drawer)
    list:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", -3, 4)
    local steps = stepper(foot, { L["Take out"], L["Sell"], L["Gold back"] }, {
        L["Takes the marked stacks out of the bank into your bags."],
        L["At any vendor, the Guild OS window there sells only what came out of the bank."],
        L["Back at the bank, deposit the gold the sale made."],
    })
    steps:SetPoint("TOPLEFT", foot, "TOPLEFT", Kit.PAD - 3, -10)
    steps:SetWidth(INNER)
    drawer.steps = steps
    local hint = UI:CreateText(foot, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    hint:SetPoint("TOPLEFT", steps, "BOTTOMLEFT", 0, -8)
    hint:SetWidth(INNER)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    local main = UI:SetButtonVariant(UI:CreateButton(foot, "", 120, SP.FIELD), "primary")
    main:SetPoint("BOTTOMRIGHT", foot, "BOTTOMRIGHT", -(Kit.PAD - 3), 9)
    main:SetScript("OnClick", function(self)
        if self.action == "take" then CL:WithdrawMarked() elseif self.action == "deposit" then CL:DepositOwed() end
    end)
    local stop = UI:SetButtonVariant(UI:CreateButton(foot, L["Stop"], 70, SP.FIELD), "danger")
    stop:SetPoint("RIGHT", main, "LEFT", -6, 0)
    stop:SetScript("OnClick", function() CL:StopWithdraw() end)
    local marked = UI:CreateText(foot, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    marked:SetPoint("LEFT", foot, "BOTTOMLEFT", Kit.PAD - 3, 9 + SP.FIELD / 2)
    marked:SetJustifyH("LEFT")
    marked:SetWordWrap(false)
    drawer.main, drawer.stop, drawer.hint, drawer.marked, drawer.foot = main, stop, hint, marked, foot

    -- Beside the bank: on its right past the game's tab buttons there, or on its left when the screen has no room.
    function drawer:Dock()
        self:ClearAllPoints()
        local host = GuildBankFrame
        if not (host and host:IsShown()) then
            self:SetPoint("CENTER")
            self:SetHeight(440)
            return
        end
        local right, screen = host:GetRight(), UIParent:GetWidth()
        local clear = sideClearance(host) + 4
        if right and screen and screen > 0 and screen - right < DRAWER_W + clear then
            self:SetPoint("TOPRIGHT", host, "TOPLEFT", -4, 0)
            self:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", -4, 0)
        else
            self:SetPoint("TOPLEFT", host, "TOPRIGHT", clear, 0)
            self:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", clear, 0)
        end
        self:Raise()   -- over the bank and its tab buttons, in the bank's strata
    end

    function drawer:Draw(rows)
        if not GuildOS:IsOfficer() then self:Hide(); return end
        rows = rows or CL:Rows()
        local items, value, slots = CL:Summary(rows)
        summary:SetText(items > 0 and string.format(L["%d to sell · %s · frees %d slots"], items, money(value), slots)
            or L["Nothing suggested to sell right now."])
        local counts, shown, allMarked = { sell = 0, review = 0, keep = 0 }, {}, items > 0
        for _, r in ipairs(rows) do
            counts[r.verdict] = (counts[r.verdict] or 0) + 1
            if r.verdict == st.show then shown[#shown + 1] = r end
            if r.verdict == "sell" and not r.marked then allMarked = false end
        end
        for key, n in pairs(counts) do seg:SetCount(key, n) end
        all.checkbox:SetChecked(allMarked)
        all.checkbox:SetEnabled(items > 0)
        if #rows == 0 then
            empty.glyph:Set("?", C.paperTitle)
            empty:Set(emptyBankText())
        else
            empty.glyph:Set("0", C.paperTitle)
            empty:Set(L["Nothing here: try another verdict above."])
        end
        list:SetData(shown)

        -- 1 take out (marked, or a run under way), 2 sell (stacks out, nothing more marked), 3 gold back.
        local done, total = CL:WithdrawProgress()
        -- What can come out now: a mark no withdrawal can fill (part of a stack, a tab this rank
        -- cannot take from, an item gone) does not hold the steps on 1.
        local owed, takeable, out = CL:Owed(), #CL:Queue(), #CL:Sellable()
        local step = (done and 1) or (owed > 0 and 3) or (out > 0 and takeable == 0 and 2) or 1
        steps:Set(step)
        steps:Layout(INNER)
        hint:SetText(out > 0 and string.format(L["%d stacks taken out. Sell them at any vendor with the Guild OS button."], out) or "")
        hint:SetShown(out > 0)

        stop:SetShown(done ~= nil)
        if done then
            main.label:SetText(string.format(L["Taking out %d of %d"], done, total))
            main.action = nil
        elseif owed > 0 then
            main.label:SetText(string.format(L["Deposit %s"], CL.MoneyText(owed)))
            main.action = "deposit"
        else
            main.label:SetText(takeable > 0 and string.format(L["Take out marked (%d)"], takeable) or L["Take out marked"])
            main.action = takeable > 0 and "take" or nil
        end
        main:SetEnabled(main.action ~= nil and not B:SortState())
        local stopW = done and (fitButton(stop, 64) + 6) or 0
        local mainW = math.min(fitButton(main, 120), INNER - stopW)
        main:SetWidth(mainW)
        local n = CL:MarkedCount()
        marked:SetText(n > 0 and string.format("%s · %d", L["Marked"], n) or "")
        local room = INNER - mainW - stopW - SP.CELL
        marked:SetShown(n > 0 and (marked:GetStringWidth() or 0) <= room)
        if marked:IsShown() then marked:SetWidth(room) end

        local hintH = out > 0 and (8 + math.ceil(hint:GetStringHeight() or 12)) or 0
        foot:SetHeight(10 + STEP_DISC + hintH + 10 + SP.FIELD + 9)
    end
    return drawer
end

-- Open or close the drawer; the bar redraws, and with it the drawer.
showDrawer = function(on)
    local d = drawer or buildDrawer()
    if on then d:Dock(); d:Show() else d:Hide() end
    if bar then bar:Draw() end
end

----------------------------------------------------------------------
-- The bar over the game's guild bank
----------------------------------------------------------------------
-- The kit's header strip as a bar (the title bar's warm gradient in the metal frame): the mark in Cinzel gold,
-- then [Organize tab][Organize all] (or [Pause][Stop] and how far a run got), a line, then [Cleanup (n)]
-- [Open in Guild OS]. As wide as what it holds in the client's language; what each button does is in its
-- tooltip. Dragged, it stays where it was put; right-click the mark to put it back over the bank.
local BAR_H     = 40               -- the bar, in its metal frame
local BAR_BTN_H = UI.SP.HIT        -- its buttons
local BAR_PAD   = 12               -- its content to the strip's edge
local BAR_GAP   = 6                -- two buttons of one group
local BAR_SEP   = 12               -- each side of the line between the groups, and after the mark
local BAR_STATUS_MAX = 280         -- a run's progress line, at most

local function buildBar()
    local B, CL, Kit = Bank(), GuildOS.GuildBankCleanup, GuildOS.Kit
    bar = CreateFrame("Frame", "GuildOSGuildBankBar", UIParent, "BackdropTemplate")
    bar:SetSize(480, BAR_H)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:SetMovable(true)
    local strip = Kit:Chrome(bar, BAR_H - 3)   -- the header strip fills the frame: the bar is all title bar
    bar.strip = strip

    local mark = strip:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(mark, 14, "windowTitle")
    mark:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    mark:SetText("Guild OS")
    mark:SetWordWrap(false)
    local function button(text, variant)
        local b = UI:CreateButton(strip, text, 60, BAR_BTN_H)
        if variant then UI:SetButtonVariant(b, variant) end
        return b
    end
    local one = button(L["Organize tab"], "primary")
    one:SetScript("OnClick", function() B:StartSort(GuildOS.Compat.GuildBankCurrentTab() or 1) end)
    local all = button(L["Organize all"])
    all:SetScript("OnClick", function() B:StartSort(B:OrganizableTabs()) end)
    local pause = button(L["Pause"])
    pause:SetScript("OnClick", function()
        local run = B:SortState()
        if run then B:PauseSort(not run.paused) end
    end)
    local stop = button(L["Stop"], "danger")
    stop:SetScript("OnClick", function() B:StopSort("cancel") end)
    -- The cleanup (officers): opens the drawer beside the bank, where all of it happens.
    local take = button(L["Cleanup"])
    take:SetScript("OnClick", function() showDrawer(not (drawer and drawer:IsShown())) end)
    local open = button(L["Open in Guild OS"])
    open:SetScript("OnClick", function() if UI.OpenWindow then UI:OpenWindow("bank", "tabs") end end)
    local sep = strip:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(WHITE)
    sep:SetSize(1, BAR_BTN_H - 4)
    sep:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    local status = UI:CreateText(strip, "", SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    local progress = UI:CreateProgressBar(strip, 100, 3)
    progress:SetPoint("BOTTOMLEFT", 2, 2)   -- as wide as the strip: Layout sets it
    bar.buttons = { one = one, all = all, pause = pause, stop = stop, take = take, open = open }
    bar.mark, bar.status, bar.sep = mark, status, sep

    -- What each button does, in its tooltip (the bar has no room for a line of it in every language).
    explain(one, L["Organize tab"], function()
        local can, why = B:CanOrganize(GuildOS.Compat.GuildBankCurrentTab() or 1)
        local lines = { L["Merges stacks and sorts by category, quality and name, one move at a time."] }
        if not can and why and why ~= "" then lines[#lines + 1] = { why, C.warn } end
        return lines
    end)
    explain(all, L["Organize all"], { L["Every tab your rank may organize, one after the other."] })
    explain(take, L["Cleanup"], { L["What the bank holds that nobody takes. Mark what goes; at the bank the bar takes it out, at a vendor it sells only that, and the gold goes back in."] })
    explain(open, L["Open in Guild OS"], { L["The bank's inventory, tabs, ledger, needs and requests in the Guild OS window."] })

    -- Where the bar sits: where the player dragged it, or over the top of the game's bank, outside
    -- it (under it, it covered the bank's own log tabs).
    function bar:Place()
        self:ClearAllPoints()
        local pos = GuildOS:GetSetting("gbankBarPos")
        local host = GuildBankFrame
        if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
            self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        elseif host and host:IsShown() then
            self:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 4)
        else
            self:SetPoint("TOP", UIParent, "TOP", 0, -120)
        end
    end

    -- Drag it anywhere (the strip, the frame or the mark); right-click the mark to put it back over the bank.
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        GuildOS:SetSetting("gbankBarPos", { x = math.floor(self:GetLeft() or 0), y = math.floor(self:GetBottom() or 0),
                                            w = math.floor(self:GetWidth() or 0) })
        self:Place()
    end)
    strip:SetScript("OnDragStart", function() bar:StartMoving() end)
    strip:SetScript("OnDragStop", function() bar:GetScript("OnDragStop")(bar) end)
    local grip = CreateFrame("Button", nil, strip)
    grip:SetAllPoints(mark)
    grip:RegisterForClicks("RightButtonUp")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() bar:StartMoving() end)
    grip:SetScript("OnDragStop", function() bar:GetScript("OnDragStop")(bar) end)
    grip:SetScript("OnClick", function()
        GuildOS:SetSetting("gbankBarPos", nil)
        bar:Place()
    end)
    explain(grip, "Guild OS", { L["Drag to move the bar. Right-click to put it back over the bank."] })

    -- Lay what shows from the left, each at its own width, and size the bar to it: bar.laid lists
    -- { frame, x, w } (x from the strip's left), bar.contentW the strip's width.
    function bar:Layout()
        local x, laid = BAR_PAD, {}
        local function put(f, w, gapBefore)
            if #laid > 0 then x = x + gapBefore end
            f:ClearAllPoints()
            f:SetPoint("LEFT", strip, "LEFT", x, 0)
            laid[#laid + 1] = { f = f, x = x, w = w }
            x = x + w
        end
        put(mark, math.ceil(mark:GetStringWidth() or 60), 0)
        local first = {}
        if one:IsShown() then fitPair(one, all, 72); first = { one, all } end
        if pause:IsShown() then fitPair(pause, stop, 64); first = { pause, stop } end
        for i, b in ipairs(first) do put(b, b:GetWidth(), i == 1 and BAR_SEP or BAR_GAP) end
        if status:IsShown() then
            local w = math.min(BAR_STATUS_MAX, math.ceil(status:GetStringWidth() or 0))
            status:SetWidth(w)
            put(status, w, BAR_SEP)
        end
        local second = {}
        for _, b in ipairs({ take, open }) do
            if b:IsShown() then fitButton(b, 72); second[#second + 1] = b end
        end
        sep:SetShown(#second > 0 and #laid > 1)
        if sep:IsShown() then put(sep, 1, BAR_SEP) end
        for i, b in ipairs(second) do put(b, b:GetWidth(), i == 1 and BAR_SEP or BAR_GAP) end
        self.laid, self.contentW = laid, x + BAR_PAD
        self:SetWidth(self.contentW + 6)   -- the strip sits 3 in from each side of the frame
        progress:SetWidth(self.contentW - 4)
        progress:SetProgress(self.done or 0)
    end

    function bar:Draw()
        local run = B:SortState()
        local tab = GuildOS.Compat.GuildBankCurrentTab() or 1
        local withdrawing = CL and CL:IsWithdrawing()
        one:SetShown(not run and not withdrawing)
        all:SetShown(not run and not withdrawing)
        pause:SetShown(run ~= nil)
        stop:SetShown(run ~= nil)
        progress:SetShown(run ~= nil)
        local officer = CL and GuildOS:IsOfficer() or false
        local drawerOpen = drawer and drawer:IsShown() or false
        take:SetShown(officer and not run)
        UI:SetSelected(take, drawerOpen)
        if officer and (not run or drawerOpen) then
            local rows = CL:Rows()
            take.label:SetText(string.format(L["Cleanup (%d)"], (CL:Summary(rows))))
            if drawerOpen then drawer:Draw(rows) end
        elseif drawerOpen then
            drawer:Hide()
        end
        if run then
            pause.label:SetText(run.paused and L["Resume"] or L["Pause"])
            local total = math.max(1, run.total or 1)
            self.done = (run.moves or 0) / total
            status:SetText(string.format(L["Tab %d: move %d of about %d"], run.tab or tab, run.moves or 0, total)
                .. (#run.queue > 0 and string.format(L[" · %d tabs to go"], #run.queue) or ""))
        else
            local can = B:CanOrganize(tab)
            one:SetEnabled(can)
            all:SetEnabled(#B:OrganizableTabs() > 0)
            status:SetText("")
        end
        status:SetShown(run ~= nil)
        self:Layout()
    end
    return bar
end

-- The bank opened and closed: dock the bar, take it away.
GuildOS.GuildBank.bankOpened = function()
    if GuildOS:GetSetting("gbankBar") == false then return end
    local b = bar or buildBar()
    -- The game builds its bank frame as it opens: place the bar a moment later.
    GuildOS.Compat.After(0.1, function()
        b:Place(); b:Draw(); b:Show()
        -- The cleanup's gold is owed: the drawer opens on that step.
        local CL = GuildOS.GuildBankCleanup
        if CL and GuildOS:IsOfficer() and CL:Owed() > 0 then showDrawer(true) end
    end)
end
GuildOS.GuildBank.bankClosed = function()
    if bar then bar:Hide() end
    if drawer then drawer:Hide() end
end
-- Coalesced like the window: every organize move and every stack taken out asks for a redraw, and
-- an open drawer reads the bank and the bags on each.
GuildOS.GuildBank.barRefresh = function()
    GuildOS:Coalesce("gbank.bar", 0.3, function() if bar and bar:IsShown() then bar:Draw() end end)
end

----------------------------------------------------------------------
-- The bar at a vendor: sell what the cleanup took out of the bank
----------------------------------------------------------------------
-- A small window in the Salão's look docked on the vendor's: its title, the items as icons (their count on
-- them, the item's tooltip on hover, "+n" past the room), what they are worth, and one Sell all. Its close
-- hides it until the next vendor. Nothing at a vendor with nothing from the bank.
local SELL_ICON, SELL_GAP, SELL_W = 32, 6, 340
local sellBar, sellDismissed
local function buildSellBar()
    local CL = GuildOS.GuildBankCleanup
    local Kit = GuildOS.Kit
    local f = CreateFrame("Frame", "GuildOSGuildBankSellBar", UIParent, "BackdropTemplate")
    f:SetSize(SELL_W, 120)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    Kit:Dress(f, L["Guild bank leftovers"], { onClose = function(fr) sellDismissed = true; fr:Hide() end })
    sellBar = f

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", Kit.PAD, -(Kit.HEADER_H + 10))
    body:SetPoint("TOPRIGHT", -Kit.PAD, -(Kit.HEADER_H + 10))
    body:SetHeight(1)

    local icons = {}
    local function iconAt(i)
        if icons[i] then return icons[i] end
        local b = CreateFrame("Button", nil, body)
        b:SetSize(SELL_ICON, SELL_ICON)
        b:SetPoint("TOPLEFT", (i - 1) * (SELL_ICON + SELL_GAP), 0)
        local edge = b:CreateTexture(nil, "BACKGROUND")
        edge:SetTexture("Interface\\Buttons\\WHITE8x8")
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetVertexColor(C.gold2.r, C.gold2.g, C.gold2.b, 0.7)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.count = UI:CreateText(b, "", 11, 1, 1, 1)
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b.more = UI:CreateText(b, "", 12, C.gold2.r, C.gold2.g, C.gold2.b)
        b.more:SetPoint("CENTER")
        b:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetHyperlink("item:" .. self.id)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icons[i] = b
        return b
    end

    local sum = UI:CreateText(f, "", SP.BODY, C.text.r, C.text.g, C.text.b)
    sum:SetJustifyH("LEFT")
    local sell = UI:SetButtonVariant(UI:CreateButton(f, L["Sell all"], 100, SP.FIELD), "primary")
    sell:SetScript("OnClick", function() CL:SellOut() end)
    UI:AddTooltip(sell, L["Sell all"], { L["Only what came out of the guild bank."],
        L["The gold is owed to the bank: deposit it the next time you open the guild bank."] })
    local note = UI:CreateText(f, L["Only what came out of the guild bank."], SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)

    function f:Draw()
        local list, value = CL:ToSell()
        local ids, total = {}, 0
        for id, c in pairs(list) do ids[#ids + 1] = id; total = total + c end
        table.sort(ids, function(a, b) return (list[a] or 0) * (GuildOS.Compat.ItemValue(a) or 0) > (list[b] or 0) * (GuildOS.Compat.ItemValue(b) or 0) end)
        local selling = CL.SellProgress and CL:SellProgress()
        local show = (#ids > 0 or selling) and CL:IsMerchantOpen() and not sellDismissed
        self:SetShown(show and true or false)
        if not show then return end
        local w = self:GetWidth()
        local inner = w - 2 * Kit.PAD
        local room = math.max(1, math.floor((inner + SELL_GAP) / (SELL_ICON + SELL_GAP)))
        local shown = (#ids > room) and (room - 1) or #ids
        for i = 1, math.max(#icons, room) do
            local b = (i <= room) and iconAt(i) or icons[i]
            if b then
                local id = ids[i]
                if i <= shown and id then
                    b.id = id
                    b.tex:SetTexture(GuildOS.Compat.ItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
                    b.tex:Show()
                    b.count:SetText((list[id] or 1) > 1 and tostring(list[id]) or "")
                    b.more:SetText("")
                    b:Show()
                elseif i == shown + 1 and #ids > shown then
                    b.id = nil
                    b.tex:Hide()
                    b.count:SetText("")
                    b.more:SetText("+" .. (#ids - shown))
                    b:Show()
                else
                    b:Hide()
                end
            end
        end
        local iconsH = (#ids > 0) and SELL_ICON or 0
        sell:ClearAllPoints()
        sell:SetPoint("TOPRIGHT", self, "TOPRIGHT", -Kit.PAD, -(Kit.HEADER_H + 10 + iconsH + SP.FIELD_GAP))
        if selling then
            sell.label:SetText(string.format(L["Selling... %d"], selling))
            sell:Disable()
        else
            sell.label:SetText(L["Sell all"])
            sell:Enable()
        end
        sell:SetWidth(math.ceil(sell.label:GetStringWidth() or 60) + 28)
        sum:ClearAllPoints()
        sum:SetPoint("LEFT", self, "TOPLEFT", Kit.PAD, -(Kit.HEADER_H + 10 + iconsH + SP.FIELD_GAP + SP.FIELD / 2))
        sum:SetPoint("RIGHT", sell, "LEFT", -SP.CELL, 0)
        sum:SetText(string.format(L["%d items · %s"], total, CL.MoneyText(value)))
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", self, "TOPLEFT", Kit.PAD, -(Kit.HEADER_H + 10 + iconsH + SP.FIELD_GAP + SP.FIELD + 6))
        note:SetWidth(inner)
        local noteH = math.ceil(note:GetStringHeight() or 12)
        self:SetHeight(Kit.HEADER_H + 10 + iconsH + SP.FIELD_GAP + SP.FIELD + 6 + noteH + Kit.PAD)
    end
    return f
end

if GuildOS.GuildBankCleanup then
    GuildOS.GuildBankCleanup.merchantOpened = function()
        sellDismissed = false
        local b = sellBar or buildSellBar()
        b:ClearAllPoints()
        local host = MerchantFrame
        local hw = host and host.GetWidth and tonumber(host:GetWidth()) or 0
        b:SetWidth(hw > 200 and hw or SELL_W)
        if host and host:IsShown() then b:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 6)
        else b:SetPoint("TOP", UIParent, "TOP", 0, -120) end
        b:Draw()
    end
    GuildOS.GuildBankCleanup.merchantClosed = function() if sellBar then sellBar:Hide() end end
    GuildOS.GuildBankCleanup.merchantRefresh = function() if sellBar then sellBar:Draw() end end
end
