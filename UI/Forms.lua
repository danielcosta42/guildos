----------------------------------------------------------------------
-- Guild OS - Forms: the Officers' Room's screens as the mockup lays them out (#449)
--
-- A screen is a board on the wood that scrolls, holding parchment cards (UI:CreateCard): two columns of
-- them from Forms.TWO_W, one below, each card as tall as what it holds. A list card may fill the room
-- left under it in its column (opts.fill), so a long list scrolls inside it and the board does not.
-- A card stacks rows top to bottom, each laid at the card's inner width, never past its edge:
--   card:Field(label, control)   the label above the field (the mockup's .field), the field as wide as the card
--   card:Pair(a, b)              two fields side by side (.row2), one under the other when the card is narrow
--   card:Flow(items)             buttons or pills along a line, wrapping (.btns, .chips)
--   card:Actions(buttons)        the card's buttons at its bottom right (the primary one last, at the right)
--   card:Check(label, hint)      a checkbox, its hint under the label
--   card:Note(text)              a paragraph in the soft ink, wrapped (.note, .sm)
--   card:Add(frame, opts)        anything else: a fixed height, or a place(frame, w, extra) that returns one
-- Forms:Pill(parent, text)      a toggle pill (on: the selection's fill; off: the outline), Forms:SetOn(pill, on)
-- Frame-free until called, so a file can read it lazily and still load where it is absent (a test).
----------------------------------------------------------------------
local UI = GuildOS.UI

local Forms = {}
GuildOS.Forms = Forms

local SP = UI.SP      -- the spacing standard (#449): every measure below comes from it
Forms.TWO_W     = SP.TWO_COLS    -- the board's width from which its cards go in two columns
Forms.GAP       = SP.GAP         -- between two cards
Forms.ROW_GAP   = SP.FIELD_GAP   -- between two rows of a card
Forms.LABEL_GAP = SP.LABEL_GAP   -- a field's label to its field (the mockup's .field gap)
Forms.FIELD_H   = SP.FIELD       -- a text field's, a select's and a button's height in a form
Forms.PILL_H    = SP.HIT
Forms.PAIR_MIN  = 300   -- under this inner width a pair stacks
Forms.TODO_H    = 40    -- a short list's two-line row (a title in BODY, a meta line under it)
Forms.FILL_MIN  = 220   -- a filling card is never shorter

local function num(v, fallback) return type(v) == "number" and v or fallback end
local function pad() return SP.PAD end
local function top() return SP.TOP end

local function laidHeight(f)
    local h = f and f.GetHeight and f:GetHeight()
    return num(h, 0)
end

-- Indices of `widths` in rows no wider than `available` (UI:FlowRows' rule, kept here: a layout calls nothing else).
local function flowRows(widths, available, gap)
    local rows, cur, used = {}, {}, 0
    for i, w in ipairs(widths) do
        local adv = (#cur > 0) and (gap + w) or w
        if #cur > 0 and used + adv > available then rows[#rows + 1] = cur; cur, used, adv = {}, 0, w end
        cur[#cur + 1] = i
        used = used + adv
    end
    if #cur > 0 then rows[#rows + 1] = cur end
    return rows
end

local function textHeight(fs)
    local h = num(fs.GetStringHeight and fs:GetStringHeight(), 0)
    return h > 0 and math.ceil(h) or 14
end

-- A text in the card's soft ink (the mockup's .sm and field labels), `size` (11) px, left-aligned.
function Forms:Soft(parent, text, size)
    local ink = (UI:OnPaper(parent) and GuildOS.Colors.paperSoft) or GuildOS.Colors.textSoft
    local fs = UI:CreateText(parent, text or "", size or SP.META, ink.r, ink.g, ink.b)
    fs:SetJustifyH("LEFT")
    return fs
end

-- A toggle pill (the mockup's .chip): the outline off, the selection's fill on. A Button: script its click.
function Forms:Pill(parent, text, on)
    local b = UI:CreateButton(parent, text or "", 40, Forms.PILL_H)
    UI:SetButtonVariant(b, "chip")
    b:SetWidth(math.ceil(num(b.label:GetStringWidth(), 30)) + 22)
    if on ~= nil then UI:SetSelected(b, on) end
    return b
end

function Forms:SetOn(pill, on) UI:SetSelected(pill, on and true or false) end

-- A pill's text changed: it takes the label's width again.
function Forms:FitPill(b, maxW)
    local w = math.ceil(num(b.label:GetStringWidth(), 30)) + 22
    if maxW and w > maxW then w = maxW end
    b:SetWidth(w)
end

-- A button sized to its label in a form's height (the quiet cream one on a card; variant: "primary").
function Forms:Button(parent, text, variant, h)
    local b = UI:CreateButton(parent, text or "", 40, h or Forms.FIELD_H)
    if variant then UI:SetButtonVariant(b, variant) end
    b:SetWidth(math.ceil(num(b.label:GetStringWidth(), 30)) + 24)
    return b
end

----------------------------------------------------------------------
-- A field: its label above it (soft, 11px), the field under it, as wide as the row unless opts.w says how
-- wide. opts.button: a button at the field's right (an Add), the field giving way to it. opts.hint: a note
-- under the field. Returns the holder; holder.label, holder.control, holder.hint. holder:Place(w) -> h.
----------------------------------------------------------------------
function Forms:MakeField(parent, label, control, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(1, 1)
    local lbl = Forms:Soft(holder, label or "", SP.META)
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetWordWrap(false)
    if control:GetParent() ~= holder and control.SetParent then control:SetParent(holder) end
    local hint = opts.hint and Forms:Soft(holder, opts.hint, SP.META) or nil
    if hint then hint:SetWordWrap(true) end
    holder.label, holder.control, holder.hint, holder.button = lbl, control, hint, opts.button
    if opts.button and opts.button.SetParent then opts.button:SetParent(holder) end
    local labelH = (label and label ~= "") and (14 + Forms.LABEL_GAP) or 0
    function holder:Place(w)
        lbl:SetWidth(math.max(1, w))
        lbl:SetShown(labelH > 0)
        local ch = num(control:GetHeight(), Forms.FIELD_H)
        local bw = opts.button and (num(opts.button:GetWidth(), 60) + 6) or 0
        local cw = math.max(30, w - bw)
        if opts.w then cw = math.min(cw, opts.w) end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -labelH)
        control:SetWidth(cw)
        if opts.button then
            opts.button:ClearAllPoints()
            opts.button:SetPoint("LEFT", control, "RIGHT", 6, 0)
            opts.button:SetHeight(math.min(ch, Forms.FIELD_H))
        end
        local h = labelH + ch
        if hint then
            hint:ClearAllPoints()
            hint:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(h + 3))
            hint:SetWidth(math.max(1, w))
            h = h + 3 + textHeight(hint)
        end
        holder:SetSize(math.max(1, w), h)
        return h
    end
    return holder
end

----------------------------------------------------------------------
-- The board
----------------------------------------------------------------------
local Board = {}
Board.__index = Board

-- A board filling `parent`: a scroll frame on the wood (opts.name names it), its child holding the cards.
-- opts.left: the first column's share of two (0.5); opts.leftW: the first column's width in px (the mockup's
-- .gl, a list beside its detail). Laid out on every size change, and by board:Layout().
function UI:CreateBoard(parent, opts)
    opts = opts or {}
    local scroll, content = UI:CreateScrollFrame(parent, opts.name)
    content = content or CreateFrame("Frame", nil, scroll)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    content:SetSize(1, 1)
    local board = setmetatable({ parent = parent, scroll = scroll, content = content, cards = {},
        left = opts.left, leftW = opts.leftW }, Board)
    parent.board = board
    local pending = false
    local function soon()
        if pending then return end
        pending = true
        C_Timer.After(0, function() pending = false; board:Layout() end)
    end
    -- The size the frame reports is the one to lay out at: GetWidth answers 0 until the game lays it out.
    scroll:SetScript("OnSizeChanged", function(_, w, h)
        w, h = num(w, 0), num(h, 0)
        if w > 1 then board:Layout(w - num(UI.SCROLL_GUTTER, 12), h) else board:Layout() end
    end)
    scroll:HookScript("OnShow", soon)
    board.Soon = soon
    return board
end

-- A card on the board. opts: col (1 or 2: its column when there are two), span (across both), fill (it
-- takes the room left under it, never under opts.minH; across both columns unless it has a col), shown (a function: laid out only while true),
-- link (UI:CreateCard's), dark. Returns the card, with the row builders below on it.
function Board:Card(title, opts)
    opts = opts or {}
    local card = UI:CreateCard(self.content, title, opts)
    card.rows, card.opts, card.board = {}, opts, self
    for k, fn in pairs(Forms.CardMethods) do card[k] = fn end
    self.cards[#self.cards + 1] = card
    return card
end

-- The width the board lays its cards in: the scroll frame's, less the scroll bar's gutter.
function Board:Width()
    local w = num(self.scroll.GetWidth and self.scroll:GetWidth(), 0)
    if w < 1 then w = num(UI.LaidWidth and UI:LaidWidth(self.scroll), 0) end
    if w < 1 then w = num(UI.LaidWidth and UI:LaidWidth(self.parent), 0) end
    if w < 1 then return 0 end
    return math.max(1, w - num(UI.SCROLL_GUTTER, 12))
end

-- Lay the cards out at `width` (the last one given or reported when nil, else the frame's) for a view `viewH`
-- tall (the scroll frame's). A
-- filling card takes the view's height left under it. board.onLayout(board) runs after. Returns the content's height.
function Board:Layout(width, viewH)
    width = num(width, 0)
    if width < 1 then width = self.width or 0 end
    if width < 1 then width = self:Width() end
    if width < 1 then return 0 end
    self.width = width
    viewH = num(viewH, 0)
    if viewH < 1 then viewH = laidHeight(self.scroll) end
    if viewH < 1 then viewH = laidHeight(self.parent) end
    if viewH < 1 then viewH = self.viewH or 0 end
    self.viewH = viewH
    local gap = Forms.GAP
    local two = width >= Forms.TWO_W
    local w1, w2 = width, width
    if two then
        if self.leftW then w1 = math.min(self.leftW, width - gap - 200)
        else w1 = math.floor((width - gap) * (self.left or 0.5)) end
        w2 = width - gap - w1
    end
    self.two = two
    self.content:SetWidth(width)
    local colY = { 0, 0 }
    for _, card in ipairs(self.cards) do
        local o = card.opts
        local on = not o.shown or (o.shown() and true or false)
        card:SetShown(on)
        if on then
            local col, x, cw
            -- A filling card with no column of its own takes both: a list is as wide as the screen.
            if two and not o.span and not (o.fill and not o.col) then
                col = o.col or ((colY[2] < colY[1]) and 2 or 1)
                x, cw = (col == 1) and 0 or (w1 + gap), (col == 1) and w1 or w2
            else
                col, x, cw = nil, 0, width
            end
            local y = col and colY[col] or math.max(colY[1], colY[2])
            local h = card:LayoutRows(cw, 0)
            if o.fill then
                local want = math.max(o.minH or Forms.FILL_MIN, viewH - y)
                if want > h then h = card:LayoutRows(cw, want - h) end
            end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
            card:SetSize(cw, h)
            card.laid = { x = x, y = y, w = cw, h = h }
            if col then colY[col] = y + h + gap
            else colY[1], colY[2] = y + h + gap, y + h + gap end
        end
    end
    local h = math.max(1, math.max(colY[1], colY[2]) - gap)
    self.content:SetHeight(h)
    self.height = h
    if self.onLayout then GuildOS:SafeCall(self.onLayout, self) end
    return h
end

----------------------------------------------------------------------
-- A card's rows
----------------------------------------------------------------------
local Card = {}
Forms.CardMethods = Card

-- A row: `obj` (a frame or a text on the card) and how tall it is: opts.h, or opts.place(obj, w, extra)
-- returning its height (`extra`: the room a filling card gives its fill row). opts: gap (above it), indent,
-- shown (a function), fill (this row takes the card's extra room), wide (its width set to the row's).
function Card:Add(obj, opts)
    opts = opts or {}
    self.rows[#self.rows + 1] = { obj = obj, h = opts.h, place = opts.place, gap = opts.gap,
        indent = opts.indent or 0, shown = opts.shown, fill = opts.fill, wide = opts.wide, right = opts.right }
    return obj
end

-- Lay the rows out at the card's width `cw`, `extra` px more to the fill row. Returns the card's height.
function Card:LayoutRows(cw, extra)
    local P = pad()
    local inner = math.max(1, cw - 2 * P)
    local y, first = top(), true
    for _, r in ipairs(self.rows) do
        local on = not r.shown or (r.shown() and true or false)
        if r.obj.SetShown then r.obj:SetShown(on) end
        if on then
            if not first then y = y + (r.gap or Forms.ROW_GAP) end
            first = false
            local w = inner - r.indent
            local add = r.fill and extra or 0
            r.obj:ClearAllPoints()
            local h
            if r.wide and r.obj.SetWidth then r.obj:SetWidth(math.max(1, w)) end
            if r.place then
                h = r.place(r.obj, w, add) or 0
            elseif r.h then
                h = r.h + add
                if r.fill and r.obj.SetHeight then r.obj:SetHeight(h) end
            else
                if r.obj.SetWidth then r.obj:SetWidth(math.max(1, w)) end
                h = textHeight(r.obj)
            end
            if r.right then
                r.obj:SetPoint("TOPRIGHT", self, "TOPRIGHT", -P, -y)
            else
                r.obj:SetPoint("TOPLEFT", self, "TOPLEFT", P + r.indent, -y)
            end
            r.laidY, r.laidH, r.laidW = y, h, w
            y = y + h
        end
    end
    return y + P
end

-- A field (Forms:MakeField) as a row. Returns the holder (holder.control is the field).
function Card:Field(label, control, opts)
    opts = opts or {}
    local holder = Forms:MakeField(self, label, control, opts)
    self:Add(holder, { gap = opts.gap, shown = opts.shown, indent = opts.indent,
        place = function(f, w) return f:Place(w) end })
    return holder
end

-- Two fields made with Forms:MakeField(card, ...) side by side, each half the row; one under the other under
-- Forms.PAIR_MIN. opts.split: the first one's share (0.5). Returns a holder.
function Card:Pair(a, b, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, self)
    holder:SetSize(1, 1)
    for _, f in ipairs({ a, b }) do if f.SetParent then f:SetParent(holder) end end
    self:Add(holder, { gap = opts.gap, shown = opts.shown, place = function(_, w)
        local h
        if w >= Forms.PAIR_MIN then
            local aw = math.floor((w - SP.FIELD_GAP) * (opts.split or 0.5))
            local ha, hb = a:Place(aw), b:Place(w - SP.FIELD_GAP - aw)
            a:ClearAllPoints(); a:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", holder, "TOPLEFT", aw + SP.FIELD_GAP, 0)
            h = math.max(ha, hb)
        else
            local ha = a:Place(w)
            local hb = b:Place(w)
            a:ClearAllPoints(); a:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(ha + Forms.ROW_GAP))
            h = ha + Forms.ROW_GAP + hb
        end
        holder:SetSize(math.max(1, w), h)
        return h
    end })
    return holder
end

-- Items along a line, wrapping as the card narrows (the mockup's .btns and .chips). `items` is a list, or
-- a function that returns the ones to lay (a list that changes: the channels). opts.align "RIGHT": from the
-- right edge (a card's actions). opts.gapX (8), opts.rowH (the tallest item). Each item keeps its width,
-- cut to the row's. Returns the holder; holder.items.
function Card:Flow(items, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, self)
    holder:SetSize(1, 1)
    holder.items = type(items) == "table" and items or {}
    for _, it in ipairs(holder.items) do if it.SetParent then it:SetParent(holder) end end
    local gx = opts.gapX or 2 * SP.UNIT
    self:Add(holder, { gap = opts.gap, shown = opts.shown, indent = opts.indent, place = function(_, w)
        local list = type(items) == "function" and items() or holder.items
        local shown, widths, rowH = {}, {}, 0
        for _, it in ipairs(list) do
            if it:IsShown() then
                shown[#shown + 1] = it
                local iw = math.min(w, num(it:GetWidth(), 40))
                if iw ~= it:GetWidth() then it:SetWidth(iw) end
                widths[#widths + 1] = iw
                rowH = math.max(rowH, num(it:GetHeight(), Forms.PILL_H))
            end
        end
        rowH = opts.rowH or rowH
        if #shown == 0 then holder:SetSize(math.max(1, w), 1); return 0 end
        local rows = flowRows(widths, w, gx)
        for ri, row in ipairs(rows) do
            local rowW = 0
            for k, i in ipairs(row) do rowW = rowW + widths[i] + (k > 1 and gx or 0) end
            local x = (opts.align == "RIGHT") and (w - rowW) or 0
            for _, i in ipairs(row) do
                local it = shown[i]
                it:ClearAllPoints()
                it:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -((ri - 1) * (rowH + 2 * SP.UNIT)))
                x = x + widths[i] + gx
            end
        end
        local h = #rows * rowH + (#rows - 1) * 2 * SP.UNIT
        holder:SetSize(math.max(1, w), h)
        return h
    end })
    return holder
end

-- The card's buttons at its bottom right, the primary one last (at the right): Flow aligned right, a
-- little more room above.
function Card:Actions(buttons, opts)
    opts = opts or {}
    opts.align = "RIGHT"
    opts.gap = opts.gap or SP.SECTION
    return self:Flow(buttons, opts)
end

-- A checkbox, `hint` under its label in the soft ink. opts.indent, opts.shown. Returns the checkbox frame
-- (frame.checkbox, frame.label, frame.hint).
function Card:Check(label, hint, opts)
    opts = opts or {}
    local f = UI:CreateCheckbox(self, label, 18)
    if f.label then
        f.label:ClearAllPoints()
        f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -2)
        f.label:SetJustifyH("LEFT")
        f.label:SetWordWrap(true)
    end
    if f.checkbox then
        f.checkbox:ClearAllPoints()
        f.checkbox:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    end
    local h2 = hint and Forms:Soft(f, hint, SP.META) or nil
    if h2 then h2:SetWordWrap(true) end
    f.hint = h2
    self:Add(f, { gap = opts.gap, indent = opts.indent, shown = opts.shown, place = function(_, w)
        local lw = math.max(1, w - 24)
        local h = 18
        if f.label then
            f.label:SetWidth(lw)
            h = math.max(18, textHeight(f.label) + 2)
        end
        if h2 then
            h2:ClearAllPoints()
            h2:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -(h + 1))
            h2:SetWidth(lw)
            h = h + 1 + textHeight(h2)
        end
        f:SetSize(math.max(1, w), h)
        return h
    end })
    return f
end

-- A paragraph in the soft ink (the mockup's .sm, .note), wrapped at the card's width. opts.size (SP.META),
-- opts.ink (a colour), opts.shown, opts.gap. Returns the text.
function Card:Note(text, opts)
    opts = opts or {}
    local fs = Forms:Soft(self, text, opts.size or SP.META)
    if opts.ink then fs:SetTextColor(opts.ink.r, opts.ink.g, opts.ink.b) end
    fs:SetWordWrap(true)
    self:Add(fs, { gap = opts.gap, shown = opts.shown, indent = opts.indent, place = function(_, w)
        fs:SetWidth(math.max(1, w))
        return textHeight(fs)
    end })
    return fs
end

-- A frame that fills its row's width, `h` tall (more when it is the card's fill row: opts.fill). The body
-- of a list: place a scroll frame or rows in it by its anchors. Returns the frame.
function Card:Body(h, opts)
    opts = opts or {}
    local body = CreateFrame("Frame", nil, self)
    body:SetSize(1, h)
    self:Add(body, { gap = opts.gap, shown = opts.shown, fill = opts.fill ~= false, place = function(_, w, extra)
        local bh = (type(h) == "function" and h(w) or h) + (extra or 0)
        body:SetSize(math.max(1, w), math.max(1, bh))
        return bh
    end })
    return body
end

-- A table's header row on the card (the mockup's .card .t th): Cinzel small caps in the card's red, a tan
-- rule under them. cols: { { text, x, justify }, ... } (x from the row's left; a negative x from its right).
-- Returns the header, with header.cols (the texts).
function Forms:TableHeader(parent, cols)
    local header = UI:CreateTableHeader(parent, SP.HIT)
    header.cols = {}
    for i, col in ipairs(cols or {}) do
        local fs = UI:CreateHeaderText(header, col[1], SP.META)
        local x = col[2] or 0
        if x < 0 then
            fs:SetPoint("RIGHT", header, "RIGHT", x, 0)
            fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("LEFT", header, "LEFT", x, 0)
        end
        header.cols[i] = fs
    end
    return header
end


-- A short list as rows (the mockup's .todo): `createRow(holder)` makes a row's parts once, `fillRow(row, item, i)`
-- writes an item into it; holder:SetData(list) shows them, rowH apart, and lays the board out again. With
-- none, opts.empty (a text) says so. Rows are kept and reused. opts.rowH (Forms.TODO_H), opts.shown, opts.gap.
-- Returns the holder (holder.rows, holder.empty).
function Card:Rows(createRow, fillRow, opts)
    opts = opts or {}
    local rowH = opts.rowH or Forms.TODO_H
    local holder = CreateFrame("Frame", nil, self)
    holder:SetSize(1, 1)
    holder.rows, holder.data = {}, {}
    local empty = Forms:Soft(holder, opts.empty or "", SP.META)
    empty:SetPoint("TOPLEFT", 0, -2)
    empty:SetWordWrap(true)
    holder.empty = empty
    local card = self
    function holder:SetData(list)
        self.data = list or {}
        for i, item in ipairs(self.data) do
            local row = self.rows[i]
            if not row then
                row = createRow(self)
                row:SetHeight(rowH)
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -((i - 1) * rowH))
            fillRow(row, item, i)
            row:Show()
        end
        for i = #self.data + 1, #self.rows do self.rows[i]:Hide() end
        empty:SetShown(#self.data == 0 and (opts.empty or "") ~= "")
        if card.board then card.board:Soon() end
    end
    self:Add(holder, { gap = opts.gap, shown = opts.shown, place = function(_, w)
        empty:SetWidth(math.max(1, w))
        local h = #holder.data * rowH
        if #holder.data == 0 then h = ((opts.empty or "") ~= "") and (textHeight(empty) + 4) or 0 end
        holder:SetSize(math.max(1, w), math.max(1, h))
        return h
    end })
    return holder
end

-- A row of a short list (the mockup's .todo): a round avatar (row.av, a class's) or a square glyph (row.glyph:
-- Set(letter, color)) at the left, the title and a soft line under it in the middle, and row.right, a frame at
-- the right where its buttons go (row:Right(buttons) lays them right to left). A tan rule under it. opts.glyph:
-- the square glyph instead of the avatar; opts.none: neither.
function Forms:TodoRow(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Forms.TODO_H)
    local Kit = rawget(GuildOS, "Kit")
    if Kit then Kit:Rule(row) end
    local x = 0
    if opts.glyph then
        local g = CreateFrame("Frame", nil, row, "BackdropTemplate")
        g:SetSize(24, 24)
        g:SetPoint("LEFT", 0, 0)
        local fill = g:CreateTexture(nil, "BACKGROUND")
        fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        fill:SetAllPoints()
        local letter = UI:CreateText(g, "", 12, 1, 1, 1)
        letter:SetPoint("CENTER", 0, 0)
        function g:Set(text, c)
            letter:SetText(text or "")
            c = c or GuildOS.Colors.paperSoft
            fill:SetVertexColor(c.r, c.g, c.b, 1)
        end
        row.glyph = g
        x = 32
    elseif not opts.none then
        row.av = UI:CreateAvatar(row, 24, false)
        row.av:SetPoint("LEFT", 0, 0)
        x = 32
    end
    row.right = CreateFrame("Frame", nil, row)
    row.right:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.right:SetSize(1, SP.HIT)
    local ink = GuildOS.Colors.paperInk
    row.title = UI:CreateText(row, "", SP.BODY, ink.r, ink.g, ink.b)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", x, -SP.UNIT)
    row.title:SetPoint("RIGHT", row.right, "LEFT", -SP.CELL, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.sub = Forms:Soft(row, "", SP.META)
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.right, "LEFT", -SP.CELL, 0)
    row.sub:SetWordWrap(false)
    row.buttons = {}
    -- Lay `buttons` (the shown ones) from the right edge leftwards; row.right takes their width.
    function row:Right(buttons)
        buttons = buttons or self.buttons
        self.buttons = buttons
        local xr = 0
        for _, b in ipairs(buttons) do
            if b:IsShown() then
                if b:GetParent() ~= self.right and b.SetParent then b:SetParent(self.right) end
                b:ClearAllPoints()
                b:SetPoint("RIGHT", self.right, "RIGHT", -xr, 0)
                xr = xr + num(b:GetWidth(), 40) + 2 * SP.UNIT
            end
        end
        self.right:SetWidth(math.max(1, xr - 2 * SP.UNIT))
    end
    return row
end

-- A small button for a row's action (the mockup's .btn.s): the smallest hit target (SP.HIT), sized to its label;
-- variant as Forms:Button.
function Forms:SmallButton(parent, text, variant)
    local b = UI:CreateButton(parent, text or "", 40, SP.HIT)
    if variant then UI:SetButtonVariant(b, variant) end
    b:SetWidth(math.ceil(num(b.label:GetStringWidth(), 30)) + 16)
    return b
end

-- Fields and buttons along one line (a filter bar: "Level from [68] to [70] Class [Any] [Search]"), wrapping
-- as the card narrows. `items`: field holders made with Forms:MakeField, each laid at its own `fw` (holder.fw,
-- default 120), and buttons, which sit level with the fields' boxes. Returns the holder.
function Card:Inline(items, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, self)
    holder:SetSize(1, 1)
    for _, it in ipairs(items) do if it.SetParent then it:SetParent(holder) end end
    local gx = opts.gapX or SP.CELL
    self:Add(holder, { gap = opts.gap, shown = opts.shown, place = function(_, w)
        local widths, heights, shown = {}, {}, {}
        for _, it in ipairs(items) do
            if it:IsShown() then
                shown[#shown + 1] = it
                local iw, ih
                if rawget(it, "Place") then
                    iw = math.min(w, num(rawget(it, "fw"), 120))
                    ih = it:Place(iw)
                else
                    iw, ih = math.min(w, num(it:GetWidth(), 60)), num(it:GetHeight(), Forms.FIELD_H)
                end
                widths[#widths + 1], heights[#heights + 1] = iw, ih
            end
        end
        local rows = flowRows(widths, w, gx)
        local y = 0
        for _, row in ipairs(rows) do
            local rowH = 0
            for _, i in ipairs(row) do rowH = math.max(rowH, heights[i]) end
            local x = 0
            for _, i in ipairs(row) do
                local it = shown[i]
                it:ClearAllPoints()
                -- A button or a text sits at the bottom of the row, level with the boxes.
                it:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -(y + rowH - heights[i]))
                x = x + widths[i] + gx
            end
            y = y + rowH + SP.FIELD_GAP
        end
        local h = math.max(0, y - SP.FIELD_GAP)
        holder:SetSize(math.max(1, w), math.max(1, h))
        return h
    end })
    return holder
end
