----------------------------------------------------------------------
-- Guild OS - The Crafts tab and craft orders (issue #389)
-- One tab for the guild's professions and its craft orders: the catalog on the left (the
-- Professions panel, or Anniversary's recipe list), the order queue on the right, and a recipe
-- opened in place with what it takes, who makes it and the order. Also the order dialog, Alt-click
-- on an item, and the bars on the game's trade and mail windows that hand the materials or the
-- item over in one click. Visual layer only: every change goes through GuildOS.CraftOrders.
-- The queue is the Workshop's "Pedidos de craft" (#449 phase 3): a parchment card, its views as pills, each
-- order a paper line with its item framed in its quality, the steps under it and its buttons.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local GAP     = tonumber(UI.GAP) or 8
local GUTTER  = tonumber(UI.SCROLL_GUTTER) or 12
local ICON    = 18
local FIELD_H = 22
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Orders() return GuildOS.CraftOrders end

local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function money(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    if g > 0 then return string.format("%d%sg|r", g, hex(C.gold)) .. (s > 0 and string.format(" %d%ss|r", s, hex(C.textSoft)) or "") end
    return string.format("%d%ss|r", s, hex(C.textSoft))
end

local function nameOf(key) return Orders().NameOf(key) end

local function classColor(key)
    local short = type(key) == "string" and (key:match("^([^-]+)") or key)
    local rec = short and GuildOS.GetMemberRecord and GuildOS:GetMemberRecord(short, key:match("-(.+)$"))
    local class = rec and rec.class
    return (class and GuildOS.ClassColors[class:upper()]) or C.text
end

local function itemInfo(id)
    local name, link, quality, _, _, _, _, _, _, tex = GuildOS.Compat.GetItemInfo(id)
    return name, link, quality, tex
end

local function whisper(key)
    if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. nameOf(key) .. " ") end
end

local STATE_TEXT = {
    open = L["Open"], accepted = L["Accepted"], mats = L["Materials delivered"], done = L["Done"],
    cancelled = L["Cancelled"], expired = L["Expired"],
}

-- One line on what an order asks for: whose materials, and the tip. `mine`: I placed it.
local function termsText(o, mine)
    local t = (o.mode == "own" and L["Crafter's materials"]) or (mine and L["Your materials"]) or L["Their materials"]
    if (o.tip or 0) > 0 then t = t .. " · " .. money(o.tip) end
    return t
end

-- The item's tooltip with what the order takes and its note.
local function orderTooltip(owner, o)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. o.item)
    local needs = Orders():Needs(o)
    if #needs > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Materials for %d:"], o.n), C.accent.r, C.accent.g, C.accent.b)
        for _, r in ipairs(needs) do
            local nm = itemInfo(r.itemID) or ("item:" .. r.itemID)
            local ok = r.have >= r.need
            GameTooltip:AddDoubleLine("  " .. nm, string.format("%d / %d", r.have, r.need), 0.9, 0.9, 0.9,
                ok and C.ok.r or C.red.r, ok and C.ok.g or C.red.g, ok and C.ok.b or C.red.b)
        end
    end
    if o.note then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(o.note, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- The order queue: the right column of the Crafts tab (issue #389)
-- For me · Mine · Open, one card per order with its four steps and the next thing to do.
----------------------------------------------------------------------
local CARD_H   = 100
local CARD_GAP = 8
local STEP_LABELS = { L["Open"], L["Accepted"], L["Materials"], L["Ready"] }

local function trade(key)
    if not GuildOS.Compat.InitiateTrade(nameOf(key)) then whisper(key) end
end

-- What a card offers, by view and state: the primary action (the next step) and a second one.
-- { label, fn } each, either may be nil.
local function cardActions(view, o)
    local O, me = Orders(), Orders():MyKey()
    local st = O.StateOf(o)
    local id = o.id
    local function act(what) return function() O:Act(id, what) end end
    if view == "mine" then
        if st == "open" then return nil, { L["Cancel"], act("cancel") } end
        if st == "accepted" and o.mode == "mats" then
            return { L["Trade"], function() trade(o.cr) end }, { L["Cancel"], act("cancel") }
        end
        if st == "accepted" or st == "mats" then
            return { L["Whisper"], function() whisper(o.cr) end }, { L["Received"], act("done") }
        end
        if st == "done" then
            return { L["Order again"], function() GuildOS:ShowCraftFor(o.item) end }, nil
        end
        return nil, nil
    elseif view == "forme" then
        if st == "open" and o.to == me then
            return { L["Accept"], act("accept") }, { L["Decline"], act("decline") }
        end
        if o.cr == me and st == "accepted" and o.mode == "mats" then
            return { L["Whisper"], function() whisper(o.who) end }, { L["Give back"], act("release") }
        end
        if o.cr == me and (st == "accepted" or st == "mats") then
            return { L["Trade"], function() trade(o.who) end }, { L["Done"], act("done") }
        end
        return nil, nil
    elseif view == "open" and st == "open" then
        return { L["Accept"], act("accept") }, { L["Whisper"], function() whisper(o.who) end }
    end
    return nil, nil
end

-- Who the card is with, as its view says it.
local function cardWho(view, o)
    local me = Orders():MyKey()
    if view == "mine" then
        if o.cr then return string.format(L["accepted by %s"], nameOf(o.cr)) end
        if o.to then return string.format(L["Sent to %s"], nameOf(o.to)) end
        return L["To every crafter who knows it"]
    end
    if o.to == me and not o.cr then return string.format(L["from %s · sent to you"], nameOf(o.who)) end
    if o.cr == me then return string.format(L["from %s · you accepted"], nameOf(o.who)) end
    return string.format(L["from %s"], nameOf(o.who))
end

local QUEUE_TABS = { { "forme", L["For me"] }, { "mine", L["Mine"] }, { "open", L["Open"] } }

-- The paper's colours for the queue: on a parchment card (the Workshop's), else the wood's.
local function inks(paper)
    if paper then
        return { ink = C.paperInk, soft = C.paperSoft, line = C.paperRule, done = { r = 0.184, g = 0.431, b = 0.2 },
                 now = C.paperTitle, todo = C.paperLine, fill = C.paperLight, act = C.paperTitle }
    end
    return { ink = C.text, soft = C.label, line = C.line, done = C.ok, now = C.gold, todo = C.line, fill = C.bg, act = C.gold }
end

function GuildOS:CreateOrderQueue(parent)
    local q = CreateFrame("Frame", nil, parent)
    q:SetAllPoints()
    -- In a card, the card's title is the queue's: the views start under it.
    local paper = UI:OnPaper(parent)
    local P = inks(paper)
    local top = paper and 34 or 36

    local title = UI:CreateTitle(q, L["Orders"], 13)
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetShown(not paper and not parent.title)
    local hint = UI:CreateText(q, L["trade and mail in one click"], 11, P.soft.r, P.soft.g, P.soft.b)
    hint:SetPoint("TOPRIGHT", -14, -14)

    -- The three views, as pills (the mockup's Para mim / Meus / Abertos).
    local seg = CreateFrame("Frame", nil, q)
    seg:SetPoint("TOPLEFT", 14, -top)
    seg:SetPoint("TOPRIGHT", -14, -top)
    seg:SetHeight(FIELD_H)
    q.tabs = {}
    for i, t in ipairs(QUEUE_TABS) do
        local b = UI:SetButtonVariant(UI:CreateButton(seg, t[2], 80, FIELD_H), "chip")
        b.key, b.base = t[1], t[2]
        b:SetScript("OnClick", function() q:Select(t[1]) end)
        q.tabs[i] = b
    end
    function q:LayoutTabs()
        local x = 0
        for _, b in ipairs(self.tabs) do
            b:SetWidth(math.ceil(b.label:GetStringWidth() or 40) + 24)
            b:ClearAllPoints()
            b:SetPoint("LEFT", x, 0)
            x = x + b:GetWidth() + 6
        end
    end

    local footer = UI:CreateText(q, L["Closed orders are kept 14 days."], 11, P.soft.r, P.soft.g, P.soft.b)
    footer:SetPoint("BOTTOMLEFT", 14, 10)

    -- The cards: pooled, over a FauxScrollFrame, as tall as the column allows.
    local area = CreateFrame("Frame", nil, q)
    area:SetPoint("TOPLEFT", 14, -top - FIELD_H - GAP)
    area:SetPoint("BOTTOMRIGHT", -6, 28)
    local scroll = CreateFrame("ScrollFrame", "GuildOSOrderQueueScroll", area, "FauxScrollFrameTemplate")
    scroll:SetAllPoints()
    UI:SkinScrollBar(scroll, "GuildOSOrderQueueScroll")
    local empty = UI:CreateText(area, "", 12, P.soft.r, P.soft.g, P.soft.b)
    empty:SetPoint("TOPLEFT", 4, -8)
    empty:SetPoint("RIGHT", -GUTTER, 0)
    empty:SetJustifyH("LEFT")

    local cards, visible = {}, 0
    local function buildCard(i)
        local c = CreateFrame("Button", nil, area, "BackdropTemplate")
        c:SetHeight(CARD_H)
        c:SetPoint("TOPLEFT", 0, -((i - 1) * (CARD_H + CARD_GAP)))
        c:SetPoint("TOPRIGHT", -GUTTER, -((i - 1) * (CARD_H + CARD_GAP)))
        c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(c) })
        c.icon = UI:CreateIcon(c, ICON)
        c.icon:SetPoint("TOPLEFT", 8, -8)
        c.name = UI:CreateText(c, "", 12)
        c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 0)
        c.name:SetPoint("RIGHT", c, "RIGHT", -54, 0)
        c.name:SetJustifyH("LEFT"); c.name:SetWordWrap(false)
        c.who = UI:CreateText(c, "", 11, P.soft.r, P.soft.g, P.soft.b)
        c.who:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
        c.who:SetPoint("RIGHT", c, "RIGHT", -8, 0)
        c.who:SetJustifyH("LEFT"); c.who:SetWordWrap(false)
        c.when = UI:CreateText(c, "", 10, P.soft.r, P.soft.g, P.soft.b)
        GuildOS:ApplyFont(c.when, 10, "tableNum")
        c.when:SetPoint("TOPRIGHT", -8, -8)
        c.steps = {}
        for s = 1, 4 do
            local bar = c:CreateTexture(nil, "ARTWORK")
            bar:SetTexture("Interface\\Buttons\\WHITE8x8")
            bar:SetHeight(3)
            local lab = UI:CreateText(c, STEP_LABELS[s], 10)
            GuildOS:ApplyFont(lab, 10, "caption")
            lab:SetJustifyH("LEFT"); lab:SetWordWrap(false)
            c.steps[s] = { bar = bar, label = lab }
        end
        c.terms = UI:CreateText(c, "", 10, P.soft.r, P.soft.g, P.soft.b)
        c.terms:SetPoint("BOTTOMLEFT", 8, 10)
        c.terms:SetJustifyH("LEFT"); c.terms:SetWordWrap(false)
        c.b1 = UI:CreateButton(c, "", 84, 20)
        UI:SetButtonVariant(c.b1, "primary")
        c.b1:SetPoint("BOTTOMRIGHT", -8, 8)
        c.b2 = UI:CreateButton(c, "", 76, 20)
        c.b2:SetPoint("RIGHT", c.b1, "LEFT", -4, 0)
        c.b1:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
        c.b2:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
        c.terms:SetPoint("RIGHT", c.b2, "LEFT", -6, 0)
        c:SetScript("OnEnter", function(self) if self.data then orderTooltip(self, self.data) end end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        c:SetScript("OnClick", function(self)
            if self.data and IsShiftKeyDown() and HandleModifiedItemClick then
                local _, link = itemInfo(self.data.item)
                if link then HandleModifiedItemClick(link) end
            elseif self.data then
                GuildOS:ShowCraftFor(self.data.item)
            end
        end)
        cards[i] = c
        return c
    end

    local function paintSteps(c, o)
        local at = Orders().Step(o)
        local w = math.max(20, ((c:GetWidth() or 260) - 16 - 12) / 4)
        for s, x in ipairs(c.steps) do
            x.bar:ClearAllPoints()
            x.bar:SetPoint("TOPLEFT", 8 + (s - 1) * (w + 4), -46)
            x.bar:SetWidth(w)
            x.label:ClearAllPoints()
            x.label:SetPoint("TOPLEFT", x.bar, "BOTTOMLEFT", 0, -4)
            x.label:SetWidth(w)
            local col = (s < at and P.done) or (s == at and P.now) or P.todo
            if at == 4 and s == 4 then col = P.done end
            x.bar:SetVertexColor(col.r, col.g, col.b, 1)
            local ink = (s == at and P.now) or (s < at and P.ink) or P.soft
            x.label:SetTextColor(ink.r, ink.g, ink.b)
        end
    end

    local function paintCard(c, o)
        c.data = o
        local name, _, quality, tex = itemInfo(o.item)
        c.icon.icon:SetTexture(tex or QUESTION)
        UI:SetIconQuality(c.icon, quality or 1)
        local qc = (GuildOS.QualityColors and GuildOS.QualityColors[quality or 1]) or P.ink
        -- On the paper the common and the uncommon read in its ink, the rarer deepened (as the catalog's).
        if paper then
            if (quality or 1) <= 1 then qc = P.ink
            else qc = { r = qc.r * 0.7, g = qc.g * 0.7, b = qc.b * 0.7 } end
        end
        c.name:SetText((name or ("item:" .. o.item)) .. (o.n > 1 and (" × " .. o.n) or ""))
        c.name:SetTextColor(qc.r, qc.g, qc.b)
        c.who:SetText(cardWho(q.view, o))
        c.when:SetText(GuildOS:TimeAgo(o.ts))
        paintSteps(c, o)
        local st = Orders().StateOf(o)
        if st == "cancelled" or st == "expired" then
            c.terms:SetText(STATE_TEXT[st])
        else
            c.terms:SetText(termsText(o, o.who == Orders():MyKey()))
        end
        local a1, a2 = cardActions(q.view, o)
        c.b1:SetShown(a1 ~= nil)
        c.b2:SetShown(a2 ~= nil)
        if a1 then c.b1.label:SetText(a1[1]); c.b1.fn = a1[2] end
        if a2 then c.b2.label:SetText(a2[1]); c.b2.fn = a2[2] end
        -- The one waiting for me has the gold edge: the next step is mine.
        local mineToAct = a1 ~= nil and Orders().IsActive(o) and (q.view ~= "open")
            and not (q.view == "mine" and st == "open")
        local edge = mineToAct and P.act or P.line
        c:SetBackdropColor(P.fill.r, P.fill.g, P.fill.b, paper and 0.7 or 1)
        c:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
    end

    local data = {}
    local function update()
        local offset = FauxScrollFrame_GetOffset(scroll)
        FauxScrollFrame_Update(scroll, #data, visible, CARD_H + CARD_GAP)
        for i = 1, visible do
            local c, o = cards[i], data[offset + i]
            if o then GuildOS:SafeCall(paintCard, c, o); c:Show() else c.data = nil; c:Hide() end
        end
        empty:SetShown(#data == 0)
    end
    local function size()
        local h = area:GetHeight() or 0
        local n = math.max(1, math.floor((h + CARD_GAP) / (CARD_H + CARD_GAP)))
        for i = #cards + 1, n do buildCard(i) end
        for i = n + 1, #cards do cards[i]:Hide() end
        visible = n
        q:LayoutTabs()
        update()
    end
    area:SetScript("OnSizeChanged", size)
    area:HookScript("OnShow", size)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, CARD_H + CARD_GAP, update)
    end)

    local EMPTY = {
        forme = L["Nothing for you: orders sent to you and the ones you accept show here."],
        mine  = L["You have no craft orders. Open a recipe on the left and order it."],
        open  = L["No open orders for a recipe you know."],
    }

    -- How many in each view still need someone: the counts on the segments.
    function q:Draw()
        local O = Orders()
        for _, b in ipairs(self.tabs) do
            local n = 0
            for _, o in ipairs(O:Rows(b.key)) do if O.IsActive(o) then n = n + 1 end end
            b.label:SetText(n > 0 and string.format("%s %d", b.base, n) or b.base)
            UI:SetSelected(b, b.key == self.view)
        end
        data = O:Rows(self.view)
        empty:SetText(EMPTY[self.view] or "")
        update()
    end
    function q:Select(view)
        self.view = (view == "mine" or view == "open") and view or "forme"
        scroll:SetVerticalScroll(0)
        self:Draw()
    end
    -- Opens on For me when something waits there, else on Mine.
    q.view = (#Orders():Rows("forme") > 0) and "forme" or "mine"
    q.cards, q.area = cards, area
    return q
end

----------------------------------------------------------------------
-- The recipe opened in the catalog: what it takes, who makes it, and the order, in one block
----------------------------------------------------------------------
local DETAIL_H   = 152
local COMPOSER_W = 248
local COMPOSER_H = DETAIL_H - 16
local MAT_LINES  = 5
local WHO_LINES  = 3
local COL_MIN    = 120
-- Materials and crafters side by side, the order on their right, takes this much width. A
-- narrower block puts the order under them, taller, instead of drawing the crafters' "Ask them"
-- over it (#415).
local WIDE_MIN   = 34 + 2 * COL_MIN + 18 + COMPOSER_W + 16
local STACKED_H  = DETAIL_H + COMPOSER_H + 8

function GuildOS:CreateCraftDetail(parent)
    local d = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    d:SetHeight(DETAIL_H)
    d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    d:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
    d:EnableMouse(true)
    local mark = d:CreateTexture(nil, "ARTWORK")
    mark:SetTexture("Interface\\Buttons\\WHITE8x8")
    mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT")
    mark:SetWidth(2)
    mark:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)
    d:Hide()

    -- Materials
    local matHead = UI:CreateHeaderText(d, "", 10)
    matHead:SetPoint("TOPLEFT", 34, -8)
    d.mats = {}
    for i = 1, MAT_LINES do
        local name = UI:CreateText(d, "", 11)
        name:SetPoint("TOPLEFT", 34, -8 - i * 18)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        local have = UI:CreateText(d, "", 11)
        GuildOS:ApplyFont(have, 11, "tableNum")
        have:SetJustifyH("RIGHT")
        d.mats[i] = { name = name, have = have }
    end
    local matNote = UI:CreateText(d, "", 10, C.label.r, C.label.g, C.label.b)
    matNote:SetJustifyH("LEFT")

    -- Crafters
    local whoHead = UI:CreateHeaderText(d, "", 10)
    d.who = {}
    for i = 1, WHO_LINES do
        local name = UI:CreateText(d, "", 11)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        local ask = UI:SetButtonVariant(UI:CreateButton(d, L["Ask them"], 70, 18), "ghost")
        -- Online: a drawn dot, not a bullet character (the addon's fonts have no such glyph: it draws a box).
        local dot = d:CreateTexture(nil, "ARTWORK")
        dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        dot:SetSize(6, 6)
        d.who[i] = { name = name, ask = ask, dot = dot }
    end
    local whoMore = UI:CreateText(d, "", 10, C.label.r, C.label.g, C.label.b)
    whoMore:SetJustifyH("LEFT")

    -- The order: on the right, or under the columns in a narrow list (Paint places it)
    local box = CreateFrame("Frame", nil, d, "BackdropTemplate")
    box:SetSize(COMPOSER_W, COMPOSER_H)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(box) })
    box:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 1)
    box:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    local qtyLabel = UI:CreateText(box, L["Quantity"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    qtyLabel:SetPoint("TOPLEFT", 10, -12)
    local plus = UI:CreateButton(box, "+", 22, 20)
    plus:SetPoint("TOPRIGHT", -10, -8)
    local qtyText = UI:CreateText(box, "1", 12)
    GuildOS:ApplyFont(qtyText, 12, "tableNum")
    qtyText:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    qtyText:SetWidth(26); qtyText:SetJustifyH("CENTER")
    local minus = UI:CreateButton(box, "-", 22, 20)
    minus:SetPoint("RIGHT", qtyText, "LEFT", -4, 0)
    local modeMats = UI:CreateButton(box, L["I bring them"], 112, 20)
    modeMats:SetPoint("TOPLEFT", 10, -36)
    local modeOwn = UI:CreateButton(box, L["Crafter's own"], 112, 20)
    modeOwn:SetPoint("LEFT", modeMats, "RIGHT", 4, 0)
    local tipLabel = UI:CreateText(box, L["Tip (gold)"], 10, C.label.r, C.label.g, C.label.b)
    tipLabel:SetPoint("TOPLEFT", 10, -64)
    local tip = UI:CreateInput(box, 70, 20, { numeric = true, max = 6 })
    tip:SetPoint("TOPLEFT", 10, -78)
    local toText = UI:CreateText(box, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    toText:SetPoint("TOPLEFT", tip, "TOPRIGHT", 10, 12)
    toText:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    toText:SetJustifyH("LEFT"); toText:SetWordWrap(false)
    local toClear = UI:SetButtonVariant(UI:CreateButton(box, L["Send to anyone"], 120, 18), "ghost")
    toClear:SetPoint("TOPLEFT", tip, "TOPRIGHT", 10, -1)
    local send = UI:CreateButton(box, L["Send order"], COMPOSER_W - 20, 24)
    UI:SetButtonVariant(send, "primary")
    send:SetPoint("BOTTOMLEFT", 10, 8)

    d.qty, d.mode = 1, "mats"

    -- The height the block takes at width `w`: the order beside the columns, or under them.
    function d:HeightFor(w)
        return (w and w > 0 and w < WIDE_MIN) and STACKED_H or DETAIL_H
    end
    -- The layout follows the height the list gave the block; when the width asks for the other
    -- one, `onReflow` (the list's) gives it the rows it needs.
    function d:IsStacked()
        return (self:GetHeight() or 0) >= STACKED_H - 0.5
    end

    function d:Paint()
        local O, r = Orders(), self.recipe
        if not r then return end
        local w = self:GetWidth() or 600
        local stacked = self:IsStacked()
        box:ClearAllPoints()
        local colW
        if stacked then
            box:SetPoint("TOPLEFT", 34, -DETAIL_H)
            colW = math.max(60, math.floor((w - 34 - 8 - 18) / 2))
        else
            box:SetPoint("TOPRIGHT", -8, -8)
            colW = math.max(COL_MIN, math.floor((w - 34 - COMPOSER_W - 16 - 18) / 2))
        end
        -- The recipe of the row clicked, when the catalog says which (issue #396).
        local crafts = math.ceil(self.qty / O:Yield(r.item, nil, r.recipeId))
        -- Materials
        local rg = r.item and O:Reagents(r.item, nil, r.recipeId) or {}
        matHead:SetText(string.format(L["MATERIALS × %d"], self.qty))
        for i, m in ipairs(self.mats) do
            local x = rg[i]
            m.name:SetShown(x ~= nil); m.have:SetShown(x ~= nil)
            if x then
                local need = x.count * crafts
                local have = GuildOS.Compat.GetItemCount(x.itemID) or 0
                m.name:SetText(itemInfo(x.itemID) or ("item:" .. x.itemID))
                m.name:SetWidth(math.max(20, colW - 60))
                m.have:ClearAllPoints()
                m.have:SetPoint("TOPLEFT", 34 + colW - 56, -8 - i * 18)
                m.have:SetWidth(56)
                m.have:SetText(string.format("%d / %d", have, need))
                local col = (self.mode == "own" and C.labelDim) or (have >= need and C.ok) or C.danger
                m.have:SetTextColor(col.r, col.g, col.b)
            end
        end
        matNote:ClearAllPoints()
        matNote:SetPoint("TOPLEFT", 34, -8 - (math.min(#rg, MAT_LINES) + 1) * 18 - 4)
        matNote:SetWidth(colW)
        -- Under the materials: how many one craft makes (or that the crafter will say what it takes),
        -- then where the recipe is learned, its skill and station.
        local note = (#rg == 0 and L["The materials show once a crafter accepts: they tell what it takes."])
            or string.format(L["Makes %d per craft"], O:Yield(r.item, nil, r.recipeId))
        if r.meta and r.meta ~= "" then note = note .. " · " .. r.meta end
        matNote:SetText(note)
        -- Crafters
        local x2 = 34 + colW + 18
        whoHead:ClearAllPoints()
        whoHead:SetPoint("TOPLEFT", x2, -8)
        whoHead:SetText(string.format(L["CRAFTERS · %d"], #r.crafters))
        local me = O:MyKey()
        for i, slot in ipairs(self.who) do
            local c = r.crafters[i]
            slot.name:SetShown(c ~= nil)
            slot.dot:SetShown(c ~= nil and c.online)
            slot.ask:SetShown(c ~= nil and c.key ~= me and c.key ~= self.toKey)
            if c then
                slot.name:ClearAllPoints()
                slot.name:SetPoint("TOPLEFT", x2 + 12, -8 - i * 20)
                slot.name:SetWidth(math.max(20, colW - 88))
                slot.dot:ClearAllPoints()
                slot.dot:SetPoint("RIGHT", slot.name, "LEFT", -6, 0)
                slot.dot:SetVertexColor(C.ok.r, C.ok.g, C.ok.b, 1)
                local cc = c.online and classColor(c.key) or C.labelDim
                slot.name:SetText(c.name or nameOf(c.key))
                slot.name:SetTextColor(cc.r, cc.g, cc.b)
                slot.ask:ClearAllPoints()
                slot.ask:SetPoint("TOPLEFT", x2 + colW - 72, -8 - i * 20 + 2)
                local key = c.key
                slot.ask:SetScript("OnClick", function() self.toKey = key; self:Paint() end)
            end
        end
        local extra, extraOnline = #r.crafters - WHO_LINES, 0
        for i = WHO_LINES + 1, #r.crafters do if r.crafters[i].online then extraOnline = extraOnline + 1 end end
        whoMore:ClearAllPoints()
        whoMore:SetPoint("TOPLEFT", x2, -8 - (WHO_LINES + 1) * 20)
        whoMore:SetWidth(colW)
        if #r.crafters == 0 then
            whoMore:SetText(L["Nobody in the guild crafts this"])
        elseif extra > 0 then
            whoMore:SetText(string.format(L["+%d more (%d online)"], extra, extraOnline))
        else
            whoMore:SetText("")
        end
        -- The order
        qtyText:SetText(tostring(self.qty))
        UI:SetSelected(modeMats, self.mode == "mats")
        UI:SetSelected(modeOwn, self.mode == "own")
        toText:SetShown(self.toKey ~= nil)
        toClear:SetShown(self.toKey ~= nil)
        if self.toKey then
            toText:SetText(string.format(L["To %s only"], nameOf(self.toKey)))
        end
        local orderable = r.item ~= nil and (#r.crafters > 0 or self.toKey ~= nil)
        send:SetEnabled(orderable)
        box:SetShown(r.item ~= nil)
    end

    plus:SetScript("OnClick", function() d.qty = math.min(Orders().MAX_N, d.qty + 1); d:Paint() end)
    minus:SetScript("OnClick", function() d.qty = math.max(1, d.qty - 1); d:Paint() end)
    modeMats:SetScript("OnClick", function() d.mode = "mats"; d:Paint() end)
    modeOwn:SetScript("OnClick", function() d.mode = "own"; d:Paint() end)
    toClear:SetScript("OnClick", function() d.toKey = nil; d:Paint() end)
    send:SetScript("OnClick", function()
        local r = d.recipe
        if not (r and r.item) then return end
        local o, why = Orders():Place(r.item, {
            n = d.qty, mode = d.mode, tip = (tonumber(tip:GetText()) or 0) * 10000, to = d.toKey,
            recipe = r.recipeId,
        })
        if not o then GuildOS:Print(why or L["The order could not be placed."]); return end
        GuildOS:Print(string.format(L["Order sent: %s. You will hear when a crafter accepts."], Orders().ItemText(o.item)))
        tip:SetText("")
        d.qty, d.toKey = 1, nil
        d:Paint()
        if d.onSent then d.onSent(o) end
    end)

    -- recipe = { id (what identifies the row), item, crafters = { { key, name, class, online } } },
    -- the crafters online first. `toKey`: one crafter to send the order to.
    -- A repaint of the same recipe keeps what the player chose in the block (quantity, materials,
    -- tip, the crafter it goes to); a new recipe, or `fresh` (opened on an item from elsewhere),
    -- starts over with `toKey`.
    function d:SetRecipe(recipe, toKey, fresh)
        if fresh or not (self.recipe and recipe and self.recipe.id == recipe.id) then
            self.qty, self.mode = 1, "mats"
            tip:SetText("")
            self.toKey = toKey
        end
        self.recipe = recipe
        self:Paint()
    end
    d:SetScript("OnSizeChanged", function(self, w)
        if not self:IsShown() then return end
        if self.onReflow and (self:HeightFor(w) == STACKED_H) ~= self:IsStacked() then
            self.onReflow()
            return
        end
        self:Paint()
    end)
    return d
end

-- The catalog lists keep fixed-height rows. An open recipe takes DETAIL_ROWS of them: the list
-- gets that many empty entries after it, and the detail is laid over their place (the list clips
-- what scrolls out). `detail` (optional) says how tall it is at the list's width. Returns the
-- list with the entries, and where the first one is.
function UI.WithDetail(results, isOpen, rowH, detail)
    local h = DETAIL_H
    if detail and detail.HeightFor then
        local w = detail:GetWidth()
        if not w or w <= 0 then w = detail:GetParent() and detail:GetParent():GetWidth() end
        h = detail:HeightFor(w)
    end
    local n = math.ceil(h / rowH)
    for i, e in ipairs(results) do
        if isOpen(e) then
            for k = 1, n do table.insert(results, i + k, { __detail = k }) end
            return results, i + 1, n
        end
    end
    return results, nil, n
end

-- Lay the detail over its rows, or hide it when none of them is in view.
function UI.PlaceDetail(detail, list, first, n, offset, visible, rowH, gutter)
    if not first then detail:Hide(); return end
    local top = first - offset - 1
    if top + n <= 0 or top >= visible then detail:Hide(); return end
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -top * rowH)
    detail:SetPoint("RIGHT", list, "RIGHT", -(gutter or 0), 0)
    detail:SetHeight(n * rowH)
    detail:Show()
    detail:Paint()
end

----------------------------------------------------------------------
-- The Crafts tab: the catalog and the order queue, side by side (issue #389)
----------------------------------------------------------------------
local QUEUE_W   = 300
local QUEUE_MIN = 940    -- under this width the queue becomes a drawer

function GuildOS:CreateCraftsTab(container, win)
    local host = CreateFrame("Frame", nil, container)
    -- The queue in a parchment card of its own beside the catalog (the mockup's "Pedidos de craft").
    local dock = UI:CreateCard(container, L["Orders"])
    dock:SetFrameLevel(container:GetFrameLevel() + 20)
    local queue = GuildOS.CraftOrders and GuildOS:CreateOrderQueue(dock)

    -- In a narrow window the queue opens over the catalog from this button.
    local toggle = UI:CreateButton(container, L["Orders"], 110, 22)
    toggle:SetPoint("BOTTOMRIGHT", -10, 6)
    toggle:SetFrameLevel(container:GetFrameLevel() + 21)
    local drawerOpen = false

    local panel
    if GuildOS.CreateProfessionsPanel then
        panel = GuildOS:CreateProfessionsPanel(host, win)
    else
        panel = GuildOS:CreateRecipesPanel(host, win)
    end

    local lastW
    local function layout(w)
        w = w or lastW or container:GetWidth() or 0
        lastW = w
        local wide = w >= QUEUE_MIN
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT")
        host:SetPoint("BOTTOMRIGHT", wide and -(QUEUE_W + 12) or 0, 0)
        dock:ClearAllPoints()
        dock:SetPoint("TOPRIGHT", -10, -8)
        dock:SetPoint("BOTTOMRIGHT", -10, wide and 10 or 34)
        dock:SetWidth(QUEUE_W)
        dock:SetShown(queue ~= nil and (wide or drawerOpen))
        toggle:SetShown(queue ~= nil and not wide)
    end
    toggle:SetScript("OnClick", function()
        drawerOpen = not drawerOpen
        layout()
        if drawerOpen and queue then GuildOS:SafeCall(queue.Draw, queue) end
    end)
    UI:MakeResponsive(container, function(_, w) layout(w) end)
    layout()

    local function paintToggle()
        if not queue then return end
        local n = GuildOS.CraftOrders:InboxCount()
        toggle.label:SetText(n > 0 and string.format("%s (%d)", L["Orders"], n) or L["Orders"])
    end

    if GuildOS.CraftOrders then
        GuildOS.CraftOrders.uiRefresh = function()
            GuildOS:RefreshCraftOrderBars()
            GuildOS:PaintCraftsBadge()
            if not container:IsVisible() then return end
            GuildOS:Coalesce("craftorders.ui", 0.3, function()
                paintToggle()
                if queue and dock:IsVisible() then GuildOS:SafeCall(queue.Draw, queue) end
                if panel and panel.Refresh then GuildOS:SafeCall(panel.Refresh, panel) end
                if panel and panel.UpdateRows and not panel.Refresh then GuildOS:SafeCall(panel.UpdateRows, panel) end
            end)
        end
    end
    container:HookScript("OnShow", function()
        paintToggle()
        if queue then GuildOS:SafeCall(queue.Draw, queue) end
    end)

    -- /gos open recipes forme · the minimap's inbox: the queue on that view.
    container.SelectSub = function(sub)
        if not queue then return end
        if not dock:IsShown() then drawerOpen = true; layout() end
        queue:Select(sub)
    end
    container.panel, container.queue, container.dock, container.toggle = panel, queue, dock, toggle
    container.LayoutCrafts = layout
    GuildOS.craftsTab = container
    return panel
end

-- The window's Crafts tab says how many orders wait for me.
function GuildOS:PaintCraftsBadge()
    local f = GuildOS.RosterFrame        -- the window, only once it exists: this never builds it
    if not (f and f.tabs and GuildOS.CraftOrders) then return end
    local n = GuildOS.CraftOrders:InboxCount()
    for _, tab in ipairs(f.tabs) do
        if tab.key == "recipes" then
            tab.base = tab.base or tab.label:GetText()
            local text = n > 0 and string.format("%s (%d)", tab.base, n) or tab.base
            if tab.label:GetText() ~= text then
                tab.label:SetText(text)
                if f.LayoutTabs then f:LayoutTabs() end
            end
        end
    end
end

-- Open the Crafts tab on an item: the recipe that makes it, opened, ready to order.
function GuildOS:ShowCraftFor(itemId, toKey)
    itemId = tonumber(itemId)
    if not itemId then return false end
    if not UI:OpenWindow("recipes") then return false end
    local tab = GuildOS.craftsTab
    local panel = tab and tab.panel
    if panel and panel.FocusItem and panel:FocusItem(itemId, toKey) then return true end
    -- An item the catalog does not list (nobody scanned it yet): the dialog still orders it.
    GuildOS:ShowCraftOrderDialog(itemId, toKey)
    return true
end

----------------------------------------------------------------------
-- The order dialog
----------------------------------------------------------------------
local dialog
local DIALOG_W = 380
local REAGENT_LINES = 8

local function buildDialog()
    local f = UI:CreatePanel(UIParent, "GuildOSCraftOrderDialog")
    f:SetSize(DIALOG_W, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI:StylePopup(f)
    table.insert(UISpecialFrames, "GuildOSCraftOrderDialog")

    local title = UI:CreateTitle(f, L["Craft order"], 13)
    title:SetPoint("TOPLEFT", 14, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    -- The item: shift-click one into the field, or it comes filled.
    local input = UI:CreateInput(f, DIALOG_W - 28, FIELD_H, { placeholder = L["Shift-click an item or type its id"], max = 255 })
    input:SetPoint("TOPLEFT", 14, -40)
    f.input = input
    f.icon = UI:CreateIcon(f, 28)
    f.icon:SetPoint("TOPLEFT", 14, -70)
    f.itemName = UI:CreateText(f, "", 13)
    f.itemName:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -1)
    f.itemName:SetWidth(DIALOG_W - 80); f.itemName:SetJustifyH("LEFT"); f.itemName:SetWordWrap(false)
    f.to = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.to:SetPoint("TOPLEFT", f.itemName, "BOTTOMLEFT", 0, -3)
    f.toClear = UI:SetButtonVariant(UI:CreateButton(f, L["Send to anyone"], 110, 18), "ghost")
    f.toClear:SetPoint("TOPRIGHT", -14, -84)
    f.toClear:SetScript("OnClick", function() f.toKey = nil; f.Paint() end)

    local function label(text, x, y)
        local fs = UI:CreateText(f, text, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        fs:SetPoint("TOPLEFT", x, y)
        return fs
    end
    label(L["Quantity"], 14, -112)
    f.qty = UI:CreateInput(f, 50, FIELD_H, { numeric = true, max = 2 })
    f.qty:SetPoint("TOPLEFT", 90, -108)
    f.qty:HookScript("OnTextChanged", function() if f.Paint then f.Paint() end end)
    label(L["Tip (gold)"], 160, -112)
    f.tip = UI:CreateInput(f, 70, FIELD_H, { numeric = true, max = 6 })
    f.tip:SetPoint("TOPLEFT", 240, -108)

    label(L["Materials"], 14, -140)
    f.modeBtns = {}
    local modes = { { "mats", L["I bring them"] }, { "own", L["Crafter's own"] } }
    local prevBtn
    for _, m in ipairs(modes) do
        local b = UI:CreateButton(f, m[2], 120, FIELD_H)
        if prevBtn then b:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 90, -136) end
        b.key = m[1]
        b:SetScript("OnClick", function() f.mode = m[1]; f.Paint() end)
        f.modeBtns[#f.modeBtns + 1] = b
        prevBtn = b
    end

    label(L["Note"], 14, -168)
    f.note = UI:CreateInput(f, DIALOG_W - 104, FIELD_H, { max = 80 })
    f.note:SetPoint("TOPLEFT", 90, -164)

    f.rgHeader = UI:CreateHeaderText(f, L["MATERIALS"], 10)
    f.rgHeader:SetPoint("TOPLEFT", 14, -198)
    f.rg = {}
    for i = 1, REAGENT_LINES do
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("TOPLEFT", 14, -214 - (i - 1) * 18)
        local text = UI:CreateText(f, "", 11)
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        text:SetWidth(DIALOG_W - 120); text:SetJustifyH("LEFT"); text:SetWordWrap(false)
        local have = UI:CreateText(f, "", 11)
        have:SetPoint("TOPRIGHT", -14, -214 - (i - 1) * 18)
        GuildOS:ApplyFont(have, 11, "tableNum")
        f.rg[i] = { icon = icon, text = text, have = have }
    end
    f.rgNone = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.rgNone:SetWidth(DIALOG_W - 28); f.rgNone:SetJustifyH("LEFT")

    f.send = UI:CreateButton(f, L["Send order"], 130, 24)
    UI:SetButtonVariant(f.send, "primary")
    f.send:SetPoint("BOTTOMRIGHT", -14, 12)
    f.crafters = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.crafters:SetPoint("BOTTOMLEFT", 14, 18)
    f.crafters:SetPoint("RIGHT", f.send, "LEFT", -8, 0)
    f.crafters:SetJustifyH("LEFT")

    function f.Paint()
        local O = Orders()
        local id = f.itemId
        local name, quality, tex, _
        if id then name, _, quality, tex = itemInfo(id) end
        f.icon.icon:SetTexture(tex or QUESTION)
        UI:SetIconQuality(f.icon, quality or 1)
        local qc = (GuildOS.QualityColors and GuildOS.QualityColors[quality or 1]) or C.text
        f.itemName:SetText(id and (name or ("item:" .. id)) or L["No item yet"])
        f.itemName:SetTextColor(qc.r, qc.g, qc.b)
        f.to:SetText(f.toKey and string.format(L["To %s only"], nameOf(f.toKey)) or L["To every crafter who knows it"])
        f.toClear:SetShown(f.toKey ~= nil)
        for _, b in ipairs(f.modeBtns) do UI:SetSelected(b, b.key == f.mode) end

        local n = math.max(1, math.min(O.MAX_N, tonumber(f.qty:GetText()) or 1))
        -- The recipe of the crafter it goes to, or the one the guild knows most (issue #396).
        local rg = id and O:Reagents(id, nil, nil, f.toKey) or {}
        local crafts = id and math.ceil(n / O:Yield(id, nil, nil, f.toKey)) or n
        local y = -214
        for i, slot in ipairs(f.rg) do
            local r = rg[i]
            slot.icon:SetShown(r ~= nil); slot.text:SetShown(r ~= nil); slot.have:SetShown(r ~= nil)
            if r then
                local rname, _, _, rtex = itemInfo(r.itemID)
                slot.icon:SetTexture(rtex or QUESTION)
                slot.text:SetText(string.format("%s  %s×%d|r", rname or ("item:" .. r.itemID), hex(C.label), r.count * crafts))
                local have, need = GuildOS.Compat.GetItemCount(r.itemID) or 0, r.count * crafts
                local col = (f.mode == "own" and C.textSoft) or (have >= need and C.ok) or C.red
                slot.have:SetText(string.format(L["you have %d"], have))
                slot.have:SetTextColor(col.r, col.g, col.b)
                y = -214 - i * 18
            end
        end
        f.rgHeader:SetShown(id ~= nil)
        f.rgNone:SetShown(id ~= nil and #rg == 0)
        if id and #rg == 0 then
            f.rgNone:ClearAllPoints()
            f.rgNone:SetPoint("TOPLEFT", 14, -214)
            f.rgNone:SetText(L["The materials show once a crafter accepts: they tell what it takes."])
            y = -244
        end
        local crafters = id and O:CraftersOf(id) or {}
        f.crafters:SetText(id and string.format(L["%d guild crafters know it"], #crafters) or "")
        f.send:SetEnabled(id ~= nil and (#crafters > 0 or f.toKey ~= nil))
        f:SetHeight(-y + 56)
    end

    local function setItem(text)
        local id = tonumber((text or ""):match("item:(%d+)")) or tonumber((text or ""):match("^%s*(%d+)%s*$"))
        if id then f.itemId = id end
        f.Paint()
    end
    input:SetScript("OnEnterPressed", function(self) setItem(self:GetText()); self:SetText(""); self:ClearFocus() end)
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if f:IsShown() and IsShiftKeyDown() and type(link) == "string" and link:match("item:%d+") then setItem(link) end
        end)
    end

    f.send:SetScript("OnClick", function()
        local O = Orders()
        local o, why = O:Place(f.itemId, {
            n = tonumber(f.qty:GetText()) or 1, mode = f.mode,
            tip = (tonumber(f.tip:GetText()) or 0) * 10000, note = f.note:GetText(), to = f.toKey,
        })
        if not o then GuildOS:Print(why or L["The order could not be placed."]); return end
        GuildOS:Print(string.format(L["Order sent: %s. You will hear when a crafter accepts."], O.ItemText(o.item)))
        f:Hide()
    end)
    return f
end

-- Open the order dialog for an item (optional) and, optionally, one crafter (a member key).
function GuildOS:ShowCraftOrderDialog(itemId, toKey)
    if not GuildOS.CraftOrders then return end
    dialog = dialog or buildDialog()
    dialog.itemId = tonumber(itemId)
    dialog.toKey = toKey ~= Orders():MyKey() and toKey or nil
    dialog.mode = "mats"
    dialog.qty:SetText("1")
    dialog.tip:SetText("")
    dialog.note:SetText("")
    dialog.Paint()
    dialog:Show()
    dialog:Raise()
    -- Item info may not be cached yet: paint again once it is.
    GuildOS.Compat.After(0.5, function() if dialog:IsShown() then dialog.Paint() end end)
end

----------------------------------------------------------------------
-- The bar on the game's trade window
----------------------------------------------------------------------
local tradeBar

local function reportMissing(missing, full)
    for id, n in pairs(missing or {}) do
        GuildOS:Print(string.format(L["Missing %d of %s in your bags."], n, Orders().ItemText(id)))
    end
    if full then GuildOS:Print(L["The window is full: hand over the rest in another trade or mail."]) end
end

local function paintTradeBar()
    local O = Orders()
    local t = O.trade
    local o, role = O:OrderWith(t and t.partner)
    if not (o and TradeFrame and TradeFrame:IsShown()) then
        if tradeBar then tradeBar:Hide() end
        return
    end
    if not tradeBar then
        tradeBar = UI:CreatePanel(TradeFrame, "GuildOSCraftTradeBar")
        tradeBar:SetSize(TradeFrame:GetWidth(), 34)
        tradeBar:SetPoint("TOPLEFT", TradeFrame, "BOTTOMLEFT", 0, -2)
        UI:StylePopup(tradeBar)
        tradeBar.text = UI:CreateText(tradeBar, "", 11)
        tradeBar.text:SetPoint("LEFT", 10, 0)
        tradeBar.text:SetJustifyH("LEFT"); tradeBar.text:SetWordWrap(false)
        tradeBar.btn = UI:CreateButton(tradeBar, "", 130, 22)
        UI:SetButtonVariant(tradeBar.btn, "primary")
        tradeBar.btn:SetPoint("RIGHT", -6, 0)
        -- Several orders with the same player: this picks which one the trade is about.
        tradeBar.next = UI:CreateButton(tradeBar, "", 54, 22)
        tradeBar.next:SetPoint("RIGHT", tradeBar.btn, "LEFT", -4, 0)
        tradeBar.text:SetPoint("RIGHT", tradeBar.next, "LEFT", -6, 0)
    end
    local list = O:OrdersWith(t.partner)
    local at = 1
    for i, x in ipairs(list) do if x.o.id == o.id then at = i end end
    tradeBar.next:SetShown(#list > 1)
    tradeBar.next.label:SetText(string.format("%d/%d >", at, #list))
    tradeBar.next:SetScript("OnClick", function()
        local nxt = list[at % #list + 1]
        if O.trade and nxt then O.trade.pick = nxt.o.id end
        paintTradeBar()
    end)
    local wants, tip = O:ToHand(o, role)
    local label
    if #wants > 0 then
        label = role == "author" and L["Put materials"] or L["Put the item"]
        if tip > 0 then label = label .. " + " .. L["tip"] end
    elseif tip > 0 then
        label = L["Put the tip"]
    end
    tradeBar.text:SetText(string.format(L["Order: %s"], O.ItemText(o.item) .. (o.n > 1 and (" x" .. o.n) or "")))
    tradeBar.btn:SetShown(label ~= nil)
    if label then
        tradeBar.btn.label:SetText(label)
        tradeBar.btn:SetScript("OnClick", function()
            if GuildOS.Compat.InCombat() then return end
            local missing, full = O:PutItems(wants, GuildOS.Compat.TradeFreeSlots(), GuildOS.Compat.ClickTradeButton)
            if tip > 0 then
                GuildOS.Compat.SetTradeMoney(tip)
                if O.trade then O.trade.tipPut = true end
            end
            reportMissing(missing, full)
        end)
    end
    tradeBar:Show()
end

----------------------------------------------------------------------
-- The bar on the game's mail window: one line per order I can mail now
----------------------------------------------------------------------
local mailBar
local MAIL_LINES = 5

local function paintMailBar()
    local O = Orders()
    if not (MailFrame and MailFrame:IsShown()) then
        if mailBar then mailBar:Hide() end
        return
    end
    local rows = O:MailRows()
    if #rows == 0 then
        if mailBar then mailBar:Hide() end
        return
    end
    if not mailBar then
        mailBar = UI:CreatePanel(MailFrame, "GuildOSCraftMailBar")
        mailBar:SetWidth(260)
        mailBar:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
        UI:StylePopup(mailBar)
        local title = UI:CreateHeaderText(mailBar, L["CRAFT ORDERS"], 10)
        title:SetPoint("TOPLEFT", 10, -10)
        mailBar.lines = {}
        for i = 1, MAIL_LINES do
            local b = UI:CreateButton(mailBar, "", 240, 22)
            b:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 26)
            b.label:SetWidth(228); b.label:SetWordWrap(false)
            mailBar.lines[i] = b
        end
    end
    local shown = math.min(#rows, MAIL_LINES)
    for i, b in ipairs(mailBar.lines) do
        local r = rows[i]
        b:SetShown(r ~= nil)
        if r then
            local who = nameOf(r.role == "author" and r.o.cr or r.o.who)
            local what = (r.act == "mats" and L["Mail materials to %s"]) or (r.act == "tip" and L["Mail the tip to %s"])
                or L["Mail the item to %s"]
            local name = itemInfo(r.o.item) or ("item:" .. r.o.item)
            b.label:SetText(string.format(what, who) .. "  ·  " .. name)
            b:SetScript("OnClick", function()
                if GuildOS.Compat.InCombat() then return end
                local missing, full = O:FillMail(r)
                reportMissing(missing, full)
                GuildOS:Print(L["Check the mail and click Send: the order moves on once it goes."])
            end)
        end
    end
    mailBar:SetHeight(36 + shown * 26)
    mailBar:Show()
end

function GuildOS:RefreshCraftOrderBars()
    GuildOS:SafeCall(paintTradeBar)
    GuildOS:SafeCall(paintMailBar)
end

if GuildOS.CraftOrders then
    -- Until the tab is built, a change still repaints the trade and mail bars.
    GuildOS.CraftOrders.uiRefresh = GuildOS.CraftOrders.uiRefresh or function()
        GuildOS:RefreshCraftOrderBars()
        GuildOS:PaintCraftsBadge()
    end
    -- Painted a frame later: the game shows its own window on the same event, maybe after us.
    GuildOS.CraftOrders.uiTrade = function(open)
        if open then GuildOS.Compat.After(0, function() GuildOS:SafeCall(paintTradeBar) end)
        elseif tradeBar then tradeBar:Hide() end
    end
    GuildOS.CraftOrders.uiMail = function(open)
        if open then GuildOS.Compat.After(0, function() GuildOS:SafeCall(paintMailBar) end)
        elseif mailBar then mailBar:Hide() end
    end
end

----------------------------------------------------------------------
-- Alt-click an item (bags, chat, the bank): its recipe opens in the Crafts tab, ready to order.
-- Not for a master looter, whose Alt-click on a bag item starts a roll (Modules/LootMaster.lua),
-- nor while a window that has its own use for the click is open: Auctionator and others sell
-- or post the item on an Alt-click (#415). Settings turns the shortcut off ("altClickCrafts").
----------------------------------------------------------------------
local BUSY_FRAMES = { "AuctionHouseFrame", "AuctionFrame", "MailFrame", "TradeFrame", "MerchantFrame", "GuildBankFrame" }

local function busyFrameOpen()
    for _, name in ipairs(BUSY_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then return true end
    end
    return false
end

local function itemHasCrafters(id)
    local rt = GuildOS.RecipeTracker
    if rt and rt:GetCraftersForItem(id) then return true end
    local D = GuildOS.ProfDirectory
    return D ~= nil and #D.ItemRecipes(id) > 0
end

if HandleModifiedItemClick and GuildOS.CraftOrders then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not (IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()) then return end
        if type(link) ~= "string" or GuildOS.Compat.InCombat() then return end
        if GuildOS:GetSetting("altClickCrafts") == false or busyFrameOpen() then return end
        local lm = GuildOS.LootMaster
        if lm and lm.IsMasterLooter then
            local ok, isML = pcall(lm.IsMasterLooter, lm)
            if ok and isML then return end
        end
        if LootFrame and LootFrame:IsShown() then return end
        local id = tonumber(link:match("item:(%d+)"))
        if id and itemHasCrafters(id) then GuildOS:ShowCraftFor(id) end
    end)
end
