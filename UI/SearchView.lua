----------------------------------------------------------------------
-- Guild OS - The search's results (#449)
-- What the window's search strip (UI/Window.lua, the mockup's .search) finds, drawn in the window's view in
-- place of the screen while there is a query: a parchment card per group (Members, Items, Recipes, Screens),
-- each with its top results as rows (the avatar or the icon, the name, a context line and what a click does),
-- "N more" under a group that has more. Two columns from UI.SP.TWO_COLS of width, one below. One row is the
-- chosen one (the gold wash): Up and Down move it, Enter opens it, the cursor chooses too, a click opens.
-- Nothing found: the standard's empty state.
--
-- SearchView:Attach(host) builds it on a frame of the window; SearchView:Render(host, text, w, h) fills it,
-- `w` and `h` the size the window lays the host out at (never read back from the frame); Move and Activate
-- are the strip's keys. Search (Modules/Search.lua) finds and opens.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L
local SP = UI.SP

local SearchView = {}
UI.SearchView = SearchView

local ROWS  = 6            -- the top results a group shows
local ROW_H = SP.ROW_AV    -- a row with an avatar
local AV    = 24           -- the avatar, the icon or the glyph
local MORE_H = 20          -- the "N more" line under a group's rows

local GROUPS = {
    { key = "members", label = L["Members"], action = L["View card"] },
    { key = "loot",    label = L["Items"],   action = L["View history"] },
    { key = "recipes", label = L["Recipes"], action = L["View recipe"] },
    { key = "screens", label = L["Screens"], action = L["Go to"] },
}
SearchView.GROUPS = GROUPS

local function text(parent, size, color)
    local fs = UI:CreateText(parent, "", size, color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A result's row: the selection's wash, the avatar (a member), the icon (an item, a recipe) or the glyph (a
-- screen), the name and its context line, and the action on the right.
local function newRow(card, host)
    local row = CreateFrame("Button", nil, card)
    row:SetHeight(ROW_H)
    row.sel = UI:CreateRowSelection(row)
    row.line = UI:CreateSeparator(row)
    row.line:SetVertexColor(card.lineColor.r, card.lineColor.g, card.lineColor.b, 1)
    row.line:SetPoint("TOPLEFT", 0, 0)
    row.line:SetPoint("TOPRIGHT", 0, 0)
    row.avatar = UI:CreateAvatar(row, AV, false)
    row.avatar:SetPoint("LEFT", 0, 0)
    row.avatar:EnableMouse(false)
    row.icon = UI:CreateIcon(row, AV - 4)
    row.icon:SetPoint("LEFT", 0, 0)
    row.glyph = UI:CreateGlyph(row, AV)
    row.glyph:SetPoint("LEFT", 0, 0)
    row.name = text(row, SP.BODY, card.ink)
    row.name:SetPoint("TOPLEFT", AV + SP.CELL, -1)
    row.sub = text(row, SP.META, card.soft)
    row.sub:SetPoint("TOPLEFT", AV + SP.CELL, -17)
    row.action = text(row, SP.META, C.paperLink)
    row.action:SetJustifyH("RIGHT")
    row.action:SetPoint("RIGHT", 0, 0)
    row:SetScript("OnEnter", function(self)
        SearchView:Select(host, self.index)
        if self.result and self.result.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.result.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        SearchView:Select(host, self.index)
        SearchView:Activate(host)
    end)
    return row
end

-- Paint row `row` with result `r` at width `w`, its action named `action`.
local function paintRow(row, r, w, action)
    row:SetWidth(w)
    row.result = r
    row.avatar:SetShown(r.kind == "member")
    row.icon:SetShown(r.kind == "loot" or r.kind == "recipe")
    row.glyph:SetShown(r.kind == "screen")
    if r.kind == "member" then
        row.avatar:SetMember(r.name, r.class, not r.online)
    elseif r.kind == "screen" then
        row.glyph:Set(UI.Initial(r.name), C.paperTitle)
    else
        row.icon.icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        if r.quality then UI:SetIconQuality(row.icon, r.quality) end
    end
    row.action:SetText(action)
    local actionW = math.ceil(row.action:GetStringWidth() or 0)
    local textW = math.max(40, w - AV - SP.CELL - actionW - SP.CELL)
    row.name:SetWidth(textW)
    row.sub:SetWidth(textW)
    row.name:SetText(r.name or "")
    if r.kind == "member" then
        UI:SetInk(row.name, GuildOS:GetClassColor(r.class))
    else
        row.name:SetTextColor(C.paperInk.r, C.paperInk.g, C.paperInk.b)
    end
    row.sub:SetText(r.sub or "")
    row:Show()
end

----------------------------------------------------------------------
-- Build the results on `host`: a scroll frame over it, a card per group, the empty state.
----------------------------------------------------------------------
function SearchView:Attach(host)
    local scroll, child = UI:CreateScrollFrame(host, nil)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    host.scroll, host.child = scroll, child
    host.cards, host.flat, host.sel = {}, {}, 1
    for _, g in ipairs(GROUPS) do
        local card = UI:CreateCard(child, g.label)
        card.rows = {}
        card.more = text(card, SP.META, card.soft)
        card:Hide()
        host.cards[g.key] = card
    end
    host.empty = UI:CreateEmptyState(child, "?")
    host.empty:Hide()
    return host
end

----------------------------------------------------------------------
-- Fill `host` with what `query` finds, laid out at `w` x `h`.
----------------------------------------------------------------------
function SearchView:Render(host, query, w, h)
    if not host.cards then self:Attach(host) end
    w, h = math.max(1, w or 1), math.max(1, h or 1)
    local res = GuildOS.Search and GuildOS.Search:Query(query) or { total = 0 }
    host.result, host.query = res, query
    local child = host.child
    local inner = math.max(1, w - (UI.SCROLL_GUTTER or 12))
    child:SetWidth(inner)
    local cols = (w >= SP.TWO_COLS) and 2 or 1
    local cw = math.floor((inner - (cols - 1) * SP.GAP) / cols)
    local colY = {}
    for i = 1, cols do colY[i] = 0 end
    host.flat, host.cols = {}, cols
    for _, g in ipairs(GROUPS) do
        local card, list = host.cards[g.key], res[g.key] or {}
        for _, row in ipairs(card.rows) do row:Hide() end
        card.more:Hide()
        if #list == 0 then
            card:Hide()
        else
            -- The shorter column takes the next card.
            local col = 1
            for i = 2, cols do if colY[i] < colY[col] then col = i end end
            local n = math.min(ROWS, #list)
            local rowW = cw - 2 * SP.PAD
            local y = SP.TOP
            for i = 1, n do
                local row = card.rows[i]
                if not row then
                    row = newRow(card, host)
                    card.rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", SP.PAD, -y)
                paintRow(row, list[i], rowW, g.action)
                row.line:SetShown(i > 1)
                host.flat[#host.flat + 1] = row
                row.index = #host.flat
                y = y + ROW_H
            end
            local hidden = #list - n + (list.more or 0)
            if hidden > 0 then
                card.more:ClearAllPoints()
                card.more:SetPoint("TOPLEFT", SP.PAD + AV + SP.CELL, -(y + 4))
                card.more:SetWidth(rowW - AV - SP.CELL)
                card.more:SetText(string.format(L["%d more"], hidden))
                card.more:Show()
                y = y + MORE_H
            end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", child, "TOPLEFT", (col - 1) * (cw + SP.GAP), -colY[col])
            card:SetSize(cw, y + SP.PAD)
            card:Show()
            colY[col] = colY[col] + y + SP.PAD + SP.GAP
        end
    end
    local tall = 0
    for i = 1, cols do tall = math.max(tall, colY[i]) end
    local es = host.empty
    if #host.flat == 0 then
        local ew = math.min(380, inner)
        es:SetWidth(ew)
        es:Set(string.format(L["Nothing found for \"%s\"."], strtrim(query or "")))
        es:ClearAllPoints()
        es:SetPoint("TOP", child, "TOP", 0, -math.max(0, math.floor((h - (es:GetHeight() or 0)) / 3)))
        es:Show()
        tall = h
    else
        es:Hide()
    end
    child:SetHeight(math.max(1, tall))
    if host.scroll.SetVerticalScroll then host.scroll:SetVerticalScroll(0) end
    self:Select(host, 1)
    return res
end

----------------------------------------------------------------------
-- The chosen row
----------------------------------------------------------------------
function SearchView:Select(host, i)
    local flat = host.flat or {}
    if #flat == 0 then host.sel = nil; return end
    i = math.max(1, math.min(#flat, i or 1))
    host.sel = i
    for k, row in ipairs(flat) do row.sel:SetShown(k == i) end
    -- Kept in sight: the scroll follows a row moved past its edge.
    local scroll, row = host.scroll, flat[i]
    if scroll.GetVerticalScroll and scroll.SetVerticalScroll and row.GetTop and scroll.GetTop then
        local top, bottom, sTop, sBottom = row:GetTop(), row:GetBottom(), scroll:GetTop(), scroll:GetBottom()
        if top and bottom and sTop and sBottom then
            local cur = scroll:GetVerticalScroll() or 0
            if top > sTop then scroll:SetVerticalScroll(math.max(0, cur - (top - sTop)))
            elseif bottom < sBottom then scroll:SetVerticalScroll(cur + (sBottom - bottom)) end
        end
    end
end

function SearchView:Move(host, delta)
    if host.sel then self:Select(host, host.sel + delta) end
end

-- The chosen result, opened (Search:Open closes the search first).
function SearchView:Selected(host)
    local row = host.sel and host.flat and host.flat[host.sel]
    return row and row.result or nil
end

function SearchView:Activate(host)
    local r = self:Selected(host)
    if r and GuildOS.Search then return GuildOS.Search:Open(r) end
    return false
end
