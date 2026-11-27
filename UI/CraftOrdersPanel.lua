----------------------------------------------------------------------
-- Guild OS - The Crafts tab and craft orders (issue #389)
-- One tab for the guild's professions and its craft orders: the catalog on the left (the
-- Professions panel, or Anniversary's recipe list), the order queue on the right, and the recipe chosen
-- on a card of its own in the queue's place (#449) with what it takes, who makes it and the order; the
-- Workshop's Search the realm is a screen of the tab (UI/CraftFinder.lua). Also the order dialog, Alt-click
-- on an item, and the bars on the game's trade and mail windows that hand the materials or the
-- item over in one click. Visual layer only: every change goes through GuildOS.CraftOrders.
-- The queue is the Workshop's "Pedidos de craft" (#449 phase 3): a parchment card, its views as pills, each
-- order a paper line with its item framed in its quality, the steps under it and its buttons.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local GAP     = tonumber(UI.GAP) or 8
local GUTTER  = tonumber(UI.SCROLL_GUTTER) or 12
local ICON    = 18
local FIELD_H = 22
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local WHITE8   = "Interface\\Buttons\\WHITE8x8"

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
local CARD_GAP = UI.SP.GAP
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

local DONE_INK = GuildOS:PaperInk("2f6e33", C.ok)   -- a done step on the paper

local QUEUE_TABS = { { "forme", L["For me"] }, { "mine", L["Mine"] }, { "open", L["Open"] } }

-- The paper's colours for the queue: on a parchment card (the Workshop's), else the wood's.
local function inks(paper)
    if paper then
        return { ink = C.paperInk, soft = C.paperSoft, line = C.paperRule, done = DONE_INK,
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
        c.when = UI:CreateText(c, "", UI.SP.META, P.soft.r, P.soft.g, P.soft.b)
        GuildOS:ApplyFont(c.when, UI.SP.META, "tableNum")
        c.when:SetPoint("TOPRIGHT", -8, -8)
        c.steps = {}
        for s = 1, 4 do
            local bar = c:CreateTexture(nil, "ARTWORK")
            bar:SetTexture("Interface\\Buttons\\WHITE8x8")
            bar:SetHeight(3)
            local lab = UI:CreateText(c, STEP_LABELS[s], UI.SP.META)
            GuildOS:ApplyFont(lab, UI.SP.META, "caption")
            lab:SetJustifyH("LEFT"); lab:SetWordWrap(false)
            c.steps[s] = { bar = bar, label = lab }
        end
        c.terms = UI:CreateText(c, "", UI.SP.META, P.soft.r, P.soft.g, P.soft.b)
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
        -- On the paper the paper's quality ink (UI:InkFor, #449): the common in its ink, the uncommon dark green.
        if paper then qc = UI.QUALITY_INK[quality or 1] or P.ink end
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
-- The recipe card (#449): the recipe chosen in the catalog, on a parchment card of its own in the right
-- column where the Orders card was (over the table's right part in a narrow window). Its item framed in its
-- quality, what it takes for the quantity chosen, who crafts it (the guild, then the alliance) and the order.
-- "‹ Orders", Escape or the row clicked again close it.
----------------------------------------------------------------------
local CARD_PAD   = UI.SP.PAD
local HEAD_TOP   = UI.SP.PAD   -- the header (the item's icon, its name, "‹ Orders" at the right) on the card's first line
local ICON_SIZE  = 36
local MAT_H      = 24
local MAT_BANK_H = 38       -- a material the guild bank also holds: a second line under its name
local MAT_MAX    = 5        -- material rows shown before the materials scroll on their own
local WHO_H      = UI.SP.ROW_AV
local WHO_MAX    = 40       -- crafter rows drawn at most; the rest counted
local ORDER_H    = 200      -- the order block, pinned to the card's foot (its Send and the line under it)
local SCROLL_GUT = 14

-- The paper's inks, read where the card is drawn.
local function ink(key)
    local S = UI.STATUS_INK or {}
    local P = { soft = C.paperSoft, dim = S.mute or C.paperSoft, ok = S.ok or C.ok, bad = S.bad or C.danger }
    return P[key]
end

-- A material's count in the guild bank, by the bank's last picture (nil where nobody read it).
local function bankCount(id)
    local B = GuildOS.GuildBank
    if not (B and B.CountOf and B.Available and B:Available()) then return nil end
    local ok, n = pcall(B.CountOf, B, id)
    return ok and tonumber(n) or nil
end

-- The item's link (or the enchant's), for a shift-click into chat.
local function recipeLink(r)
    if r.item then
        local _, link = itemInfo(r.item)
        return link
    end
    if r.spell and GuildOS.Compat.GetSpellLink then return GuildOS.Compat.GetSpellLink(r.spell) end
end

local function whisperTo(name, r)
    if not ChatFrame_OpenChat then return end
    local link = recipeLink(r)
    ChatFrame_OpenChat("/w " .. GuildOS:WhisperTarget(name) .. " "
        .. string.format(L["Can you craft %s?"], link or r.name or L["this item"]))
end

function GuildOS:CreateRecipeCard(parent)
    local d = UI:CreateCard(parent, "")
    d.title:Hide()
    d:EnableMouse(true)
    d:Hide()
    d.qty, d.mode = 1, "mats"

    -- Back to the Orders card (the column's own), at the header's right.
    local back = UI:SetButtonVariant(UI:CreateButton(d, L["‹ Orders"], 80, UI.SP.HIT), "chip")
    back:SetWidth(math.ceil(back.label:GetStringWidth() or 50) + 22)
    back:SetPoint("TOPRIGHT", -CARD_PAD, -HEAD_TOP)
    d.back = back

    -- The header (#449): the item's icon in its quality's frame beside its name, in the serif in the paper's
    -- quality ink. The icon and its frame are drawn on the card itself, so nothing laid over the card hides them;
    -- a frame over them takes the mouse (the tooltip, a shift-click).
    local iconEdge = d:CreateTexture(nil, "ARTWORK", nil, 1)
    iconEdge:SetTexture(WHITE8)
    iconEdge:SetSize(ICON_SIZE + 4, ICON_SIZE + 4)
    iconEdge:SetPoint("TOPLEFT", CARD_PAD, -HEAD_TOP)
    local iconTex = d:CreateTexture(nil, "ARTWORK", nil, 2)
    iconTex:SetPoint("TOPLEFT", iconEdge, "TOPLEFT", 2, -2)
    iconTex:SetPoint("BOTTOMRIGHT", iconEdge, "BOTTOMRIGHT", -2, 2)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local icon = CreateFrame("Frame", nil, d)
    icon:SetAllPoints(iconEdge)
    icon:EnableMouse(true)
    icon.icon, icon.edge = iconTex, iconEdge
    d.icon = icon
    local name = UI:CreateTitle(d, "", UI.SP.TITLE)
    name:SetPoint("TOPLEFT", iconEdge, "TOPRIGHT", UI.SP.CELL, -2)
    name:SetPoint("RIGHT", back, "LEFT", -UI.SP.CELL, 0)
    name:SetJustifyH("LEFT")
    if name.SetWordWrap then name:SetWordWrap(true) end
    if name.SetMaxLines then name:SetMaxLines(2) end
    d.name = name
    local meta = UI:CreateText(d, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    meta:SetJustifyH("LEFT")
    meta:SetWordWrap(true)
    d.meta = meta
    local makes = UI:CreateText(d, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    makes:SetJustifyH("LEFT")
    d.makes = makes

    -- Hovered: the item's tooltip. Shift-clicked: its link into chat.
    local function showTip(self)
        local r = d.recipe
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if r.item then GameTooltip:SetHyperlink("item:" .. r.item)
        elseif r.spell then GameTooltip:SetHyperlink("enchant:" .. r.spell) end
        GameTooltip:Show()
    end
    icon:SetScript("OnEnter", showTip)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:SetScript("OnMouseUp", function()
        local r = d.recipe
        local link = r and recipeLink(r)
        if link and IsShiftKeyDown() and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)

    -- The middle: the materials (scrolling on their own past MAT_MAX rows), then who crafts it in a list of its
    -- own that scrolls and stops a section's gap above the order (#449: it ran into the Order block).
    local matHead = UI:CreateHeaderText(d, L["Materials"], UI.SP.META)
    local scroll, body = UI:CreateScrollFrame(d, nil)
    d.scroll, d.body = scroll, body
    body.__paper = true
    local matNote = UI:CreateText(body, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    matNote:SetJustifyH("LEFT")
    matNote:SetWordWrap(true)
    d.mats = {}
    local function matRow(i)
        local m = d.mats[i]
        if m then return m end
        m = CreateFrame("Button", nil, body)
        m:SetHeight(MAT_H)
        m.icon = m:CreateTexture(nil, "ARTWORK")
        m.icon:SetSize(16, 16)
        m.icon:SetPoint("TOPLEFT", 0, -3)
        m.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        m.name = UI:CreateText(m, "", 12)
        m.name:SetPoint("TOPLEFT", 22, -5)
        m.name:SetJustifyH("LEFT"); m.name:SetWordWrap(false)
        m.have = UI:CreateText(m, "", 12)
        GuildOS:ApplyFont(m.have, 12, "tableNum")
        m.have:SetPoint("TOPRIGHT", 0, -5)
        m.have:SetJustifyH("RIGHT")
        m.bank = UI:CreateText(m, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        m.bank:SetPoint("TOPLEFT", 22, -21)
        m.bank:SetJustifyH("LEFT"); m.bank:SetWordWrap(false)
        m:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:Show()
        end)
        m:SetScript("OnLeave", function() GameTooltip:Hide() end)
        m:SetScript("OnClick", function(self)
            local _, link = itemInfo(self.itemID)
            if link and IsShiftKeyDown() and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
        d.mats[i] = m
        return m
    end

    local whoHead = UI:CreateHeaderText(d, "", UI.SP.META)
    local whoScroll, whoBody = UI:CreateScrollFrame(d, nil)
    whoBody.__paper = true
    d.whoScroll, d.whoBody = whoScroll, whoBody
    d.who = {}
    local function whoRow(i)
        local w = d.who[i]
        if w then return w end
        w = CreateFrame("Frame", nil, whoBody)
        w:SetHeight(WHO_H)
        w.avatar = UI:CreateAvatar(w, 24, false)
        w.avatar:SetPoint("LEFT", 0, 0)
        w.avatar:EnableMouse(false)
        -- Online: a drawn dot, not a bullet character (the addon's fonts have no such glyph: it draws a box).
        w.dot = w:CreateTexture(nil, "OVERLAY")
        w.dot:SetTexture(WHITE8)
        w.dot:SetSize(6, 6)
        w.dot:SetPoint("BOTTOMRIGHT", w.avatar, "BOTTOMRIGHT", 1, -1)
        w.name = UI:CreateText(w, "", 12)
        w.name:SetPoint("LEFT", 32, 0)
        w.name:SetJustifyH("LEFT"); w.name:SetWordWrap(false)
        w.skill = UI:CreateText(w, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
        GuildOS:ApplyFont(w.skill, UI.SP.META, "tableNum")
        w.skill:SetJustifyH("RIGHT")
        w.whisper = UI:SetButtonVariant(UI:CreateButton(w, L["Whisper"], 50, UI.SP.HIT), "ghost")
        w.whisper:SetWidth(math.ceil(w.whisper.label:GetStringWidth() or 40) + 4)
        w.whisper:SetPoint("RIGHT", 0, 0)
        w.ask = UI:SetButtonVariant(UI:CreateButton(w, L["Order"], 40, UI.SP.HIT), "ghost")
        w.ask:SetWidth(math.ceil(w.ask.label:GetStringWidth() or 30) + 4)
        w.ask:SetPoint("RIGHT", w.whisper, "LEFT", -8, 0)
        w.skill:SetPoint("RIGHT", w.ask, "LEFT", -8, 0)
        w.skill:SetWidth(40)
        w.name:SetPoint("RIGHT", w.skill, "LEFT", -6, 0)
        d.who[i] = w
        return w
    end
    local whoMore = UI:CreateText(whoBody, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    whoMore:SetJustifyH("LEFT")
    whoMore:SetWordWrap(true)
    -- Nobody in the guild: the realm's search, opened on the item.
    local realm = UI:SetButtonVariant(UI:CreateButton(whoBody, L["Search the realm"], 100, UI.SP.HIT), "ghost")
    realm:SetWidth(math.ceil(realm.label:GetStringWidth() or 80) + 4)
    realm:SetScript("OnClick", function()
        local r = d.recipe
        if GuildOS.ShowCraftFinder then GuildOS:ShowCraftFinder(r and r.item) end
    end)
    d.realm = realm

    -- The order, pinned to the card's foot under a rule.
    local box = CreateFrame("Frame", nil, d)
    box:SetPoint("BOTTOMLEFT", CARD_PAD, CARD_PAD)
    box:SetPoint("BOTTOMRIGHT", -CARD_PAD, CARD_PAD)
    box:SetHeight(ORDER_H)
    d.box = box
    local rule = UI:CreateSeparator(box)
    rule:SetVertexColor(C.paperRule.r, C.paperRule.g, C.paperRule.b, 1)
    rule:SetPoint("TOPLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", 0, 0)
    local orderHead = UI:CreateHeaderText(box, L["Order"], UI.SP.META)
    orderHead:SetPoint("TOPLEFT", 0, -UI.SP.FIELD_GAP)
    -- The quantity and the tip on one line, the materials' two ways under them, who it goes to, Send.
    local qtyLabel = UI:CreateText(box, L["Quantity"], 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    qtyLabel:SetPoint("TOPLEFT", 0, -40)
    local minus = UI:CreateButton(box, "-", UI.SP.HIT, UI.SP.HIT)
    minus:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
    local qtyText = UI:CreateText(box, "1", 13)
    GuildOS:ApplyFont(qtyText, 13, "tableNum")
    qtyText:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    qtyText:SetWidth(28); qtyText:SetJustifyH("CENTER")
    local plus = UI:CreateButton(box, "+", UI.SP.HIT, UI.SP.HIT)
    plus:SetPoint("LEFT", qtyText, "RIGHT", 2, 0)
    local tip = UI:CreateInput(box, 64, UI.SP.FIELD, { numeric = true, max = 6 })
    tip:SetPoint("TOPRIGHT", 0, -34)
    local tipLabel = UI:CreateText(box, L["Tip (gold)"], 12, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    tipLabel:SetPoint("RIGHT", tip, "LEFT", -8, 0)
    local modeMats = UI:SetButtonVariant(UI:CreateButton(box, L["I bring the materials"], 120, UI.SP.HIT), "chip")
    modeMats:SetWidth(math.ceil(modeMats.label:GetStringWidth() or 100) + 22)
    modeMats:SetPoint("TOPLEFT", 0, -72)
    local modeOwn = UI:SetButtonVariant(UI:CreateButton(box, L["Crafter's own"], 100, UI.SP.HIT), "chip")
    modeOwn:SetWidth(math.ceil(modeOwn.label:GetStringWidth() or 80) + 22)
    modeOwn:SetPoint("LEFT", modeMats, "RIGHT", 8, 0)
    local toText = UI:CreateText(box, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    toText:SetPoint("TOPLEFT", 0, -108)
    toText:SetJustifyH("LEFT"); toText:SetWordWrap(false)
    local toClear = UI:SetButtonVariant(UI:CreateButton(box, L["Send to anyone"], 100, UI.SP.HIT), "ghost")
    toClear:SetWidth(math.ceil(toClear.label:GetStringWidth() or 80) + 4)
    toClear:SetPoint("TOPRIGHT", 0, -103)
    toText:SetPoint("RIGHT", toClear, "LEFT", -6, 0)
    local send = UI:SetButtonVariant(UI:CreateButton(box, L["Send order"], 140, UI.SP.FIELD), "primary")
    send:SetPoint("TOPLEFT", 0, -134)
    send:SetPoint("TOPRIGHT", 0, -134)
    local what = UI:CreateText(box, "", UI.SP.META, C.paperSoft.r, C.paperSoft.g, C.paperSoft.b)
    what:SetPoint("TOPLEFT", send, "BOTTOMLEFT", 0, -6)
    what:SetPoint("TOPRIGHT", send, "BOTTOMRIGHT", 0, -6)
    what:SetJustifyH("LEFT")
    what:SetWordWrap(true)
    d.send, d.what, d.tip, d.modeMats, d.modeOwn, d.toText, d.toClear = send, what, tip, modeMats, modeOwn, toText, toClear
    d.plus, d.minus = plus, minus

    -- Lays the body out at the card's width and paints it. Every width is read from the card (UI:LaidWidth),
    -- never from a GetWidth that answers 0 before the game lays the card out.
    function d:Paint()
        local O, r = Orders(), self.recipe
        if not r then return end
        local W = math.max(220, UI:LaidWidth(self))
        local inner = W - 2 * CARD_PAD

        -- The header
        local q = r.quality or (r.item and select(3, itemInfo(r.item))) or 1
        icon.icon:SetTexture(r.icon or (r.item and select(4, itemInfo(r.item))) or QUESTION)
        do
            local qc = GuildOS.QualityColors and GuildOS.QualityColors[q]
            local er, eg, eb = C.paperRule.r, C.paperRule.g, C.paperRule.b
            if qc and q >= 2 then er, eg, eb = qc.r, qc.g, qc.b end
            icon.edge:SetVertexColor(er, eg, eb, 1)
        end
        name:SetWidth(math.max(60, inner - ICON_SIZE - 4 - 2 * UI.SP.CELL - (back:GetWidth() or 60)))
        name:SetText(r.name or (r.item and itemInfo(r.item)) or (r.item and ("item:" .. r.item)) or "?")
        name:SetTextColor(UI:InkFor("paper", "quality", q))
        local parts = {}
        if r.prof and r.prof ~= "" then parts[#parts + 1] = r.prof end
        if r.yellow and r.grey and r.grey > 0 then
            parts[#parts + 1] = string.format(L["skill %d–%d"], r.yellow, r.grey)
        end
        if r.requires and r.requires ~= "" then parts[#parts + 1] = string.format(L["Requires %s"], r.requires) end
        if r.source and r.source ~= "" then parts[#parts + 1] = r.source end
        meta:SetText(table.concat(parts, " · "))
        meta:SetWidth(inner)
        meta:ClearAllPoints()
        meta:SetPoint("TOPLEFT", CARD_PAD, -(HEAD_TOP + ICON_SIZE + 4 + UI.SP.FIELD_GAP))
        local metaH = (meta:GetText() ~= "" and math.max(14, math.ceil(meta:GetStringHeight() or 14))) or 0
        local yield = r.item and O:Yield(r.item, nil, r.recipeId, self.toKey) or 1
        makes:SetText(string.format(L["Makes %d per craft"], yield))
        makes:ClearAllPoints()
        local headTop = HEAD_TOP + ICON_SIZE + 4 + UI.SP.FIELD_GAP
        makes:SetPoint("TOPLEFT", CARD_PAD, -(headTop + metaH + (metaH > 0 and 3 or 0)))
        local headBottom = headTop + metaH + (metaH > 0 and 3 or 0) + 16 + UI.SP.SECTION

        matHead:ClearAllPoints()
        matHead:SetPoint("TOPLEFT", CARD_PAD, -headBottom)
        local bw = math.max(120, inner - SCROLL_GUT)
        body:SetWidth(bw)
        whoBody:SetWidth(bw)

        -- Materials, for the quantity chosen
        local crafts = math.ceil(self.qty / math.max(1, yield))
        local rg = r.item and O:Reagents(r.item, nil, r.recipeId, self.toKey) or {}
        matHead:SetText(self.qty > 1 and string.format(L["Materials × %d"], self.qty) or L["Materials"])
        local y = 0
        for _, m in ipairs(self.mats) do m:Hide() end
        for i, x in ipairs(rg) do
            local m = matRow(i)
            local need = x.count * crafts
            local have = GuildOS.Compat.GetItemCount(x.itemID) or 0
            local mname, _, mq, mtex = itemInfo(x.itemID)
            m.itemID = x.itemID
            m.icon:SetTexture(mtex or QUESTION)
            m.name:SetText(mname or ("item:" .. x.itemID))
            m.name:SetTextColor(UI:InkFor("paper", "quality", mq or 1))
            m.have:SetText(string.format("%d / %d", have, need))
            local col = (self.mode == "own" and ink("dim")) or (have >= need and ink("ok")) or ink("bad")
            m.have:SetTextColor(col.r, col.g, col.b)
            m.name:SetWidth(math.max(40, bw - 22 - 70))
            local inBank = bankCount(x.itemID)
            m.bank:SetShown(inBank ~= nil and inBank > 0)
            if inBank and inBank > 0 then m.bank:SetText(string.format(L["+%d in the guild bank"], inBank)) end
            local h = (inBank and inBank > 0) and MAT_BANK_H or MAT_H
            m:SetHeight(h)
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", 0, -y)
            m:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            m:Show()
            y = y + h
        end
        matNote:SetShown(#rg == 0)
        if #rg == 0 then
            matNote:SetText(L["The materials show once a crafter accepts: they tell what it takes."])
            matNote:SetWidth(bw)
            matNote:ClearAllPoints()
            matNote:SetPoint("TOPLEFT", 0, -y)
            y = y + math.max(16, math.ceil(matNote:GetStringHeight() or 16)) + 2
        end
        -- The materials' own area: as tall as they are, up to MAT_MAX rows, scrolling past that.
        body:SetHeight(math.max(1, y))
        local matTop = headBottom + 20
        local matH = math.max(1, math.min(y, MAT_MAX * MAT_H + 4))
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", CARD_PAD, -matTop)
        scroll:SetPoint("TOPRIGHT", -(CARD_PAD - 4), -matTop)
        scroll:SetHeight(matH)
        local whoTop = matTop + matH + UI.SP.SECTION

        -- Who crafts it: the guild's, online first, then the alliance's (marked with their guild).
        local list = {}
        for _, c in ipairs(r.crafters or {}) do list[#list + 1] = c end
        local allies = 0
        local A = GuildOS.Alliance
        if r.item and A and A.Get and A:Get() and A.FindCrafters then
            local ok, found = pcall(A.FindCrafters, A, r.item)
            for _, c in ipairs(ok and found or {}) do
                list[#list + 1] = { name = c.name, class = c.class, online = c.online, guild = c.guild, whisper = c.whisper,
                                    ally = true }
                allies = allies + 1
            end
        end
        local guildN = #list - allies
        whoHead:ClearAllPoints()
        whoHead:SetPoint("TOPLEFT", CARD_PAD, -whoTop)
        whoHead:SetText(string.format(L["Who crafts it · %d"], #list))
        -- The list fills the room down to a section's gap above the order block, and scrolls in it.
        whoScroll:ClearAllPoints()
        whoScroll:SetPoint("TOPLEFT", CARD_PAD, -(whoTop + 20))
        whoScroll:SetPoint("BOTTOMRIGHT", -(CARD_PAD - 4), CARD_PAD + ORDER_H + UI.SP.SECTION)
        y = 0
        local me = O:MyKey()
        for _, w in ipairs(self.who) do w:Hide() end
        for i = 1, math.min(#list, WHO_MAX) do
            local c, w = list[i], whoRow(i)
            w.data = c
            w.avatar:SetMember(c.name or nameOf(c.key), c.class, not c.online)
            w.dot:SetShown(c.online and true or false)
            local okc = ink("ok")
            w.dot:SetVertexColor(okc.r, okc.g, okc.b, 1)
            local cname = c.name or nameOf(c.key)
            if c.ally then cname = cname .. "  |cff" .. string.format("%02x%02x%02x", C.paperSoft.r * 255, C.paperSoft.g * 255,
                C.paperSoft.b * 255) .. "[" .. tostring(c.guild or "?") .. "]|r" end
            w.name:SetText(cname)
            local cr, cg, cb = UI:InkFor("paper", "class", c.class)
            if not c.online then local s = ink("dim"); cr, cg, cb = s.r, s.g, s.b end
            w.name:SetTextColor(cr, cg, cb)
            w.skill:SetText(c.skill and tostring(c.skill) or "")
            local mine = c.key ~= nil and c.key == me
            w.whisper:SetShown(not mine)
            w.whisper:SetScript("OnClick", function() whisperTo(c.whisper or cname:match("^(%S+)") or cname, r) end)
            -- A guild crafter takes an order sent to them alone.
            w.ask:SetShown(c.key ~= nil and not mine and c.key ~= self.toKey)
            w.ask:SetScript("OnClick", function() self.toKey = c.key; self:Paint() end)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", 0, -y)
            w:SetPoint("RIGHT", whoBody, "RIGHT", 0, 0)
            w:Show()
            y = y + WHO_H
        end
        realm:Hide()
        whoMore:ClearAllPoints()
        whoMore:SetPoint("TOPLEFT", 0, -(y + 2))
        whoMore:SetWidth(bw)
        if #list > WHO_MAX then
            whoMore:SetText(string.format(L["+%d more"], #list - WHO_MAX))
            whoMore:Show()
            y = y + 20
        elseif guildN == 0 then
            whoMore:SetText(L["Nobody in the guild crafts this."])
            whoMore:Show()
            realm:ClearAllPoints()
            realm:SetPoint("TOPLEFT", whoMore, "BOTTOMLEFT", 0, -4)
            realm:SetShown(GuildOS.ShowCraftFinder ~= nil and r.item ~= nil)
            y = y + 20 + (realm:IsShown() and (UI.SP.HIT + 4) or 0)
        else
            whoMore:Hide()
        end
        whoBody:SetHeight(math.max(1, y + 4))

        -- The order
        qtyText:SetText(tostring(self.qty))
        UI:SetSelected(modeMats, self.mode == "mats")
        UI:SetSelected(modeOwn, self.mode == "own")
        toText:SetText(self.toKey and string.format(L["To %s only"], nameOf(self.toKey)) or L["To every crafter who knows it"])
        toClear:SetShown(self.toKey ~= nil)
        local orderable = Orders ~= nil and r.item ~= nil and (guildN > 0 or self.toKey ~= nil)
        send:SetEnabled(orderable)
        local why
        if not r.item then why = L["An enchant is not an item: whisper a crafter instead."]
        elseif not orderable then why = L["Nobody in the guild crafts this"] end
        UI:SetDisabledReason(send, why)
        if not orderable then
            what:SetText(why or "")
        elseif self.toKey then
            what:SetText(string.format(L["%s sees it and can accept it. You hear when they do."], nameOf(self.toKey)))
        else
            what:SetText(string.format(L["The %d guild crafters who know it see it; the first to accept takes it."], guildN))
        end
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

    -- recipe = { id (the row's), recipeId, item, spell, name, icon, quality, prof, yellow, grey, requires, source,
    -- crafters = { { key, name, class, online, skill } } }, the crafters online first. `toKey`: one crafter to
    -- send the order to. A repaint of the same recipe keeps what the player chose (quantity, materials, tip, the
    -- crafter); a new recipe, or `fresh` (opened on an item from elsewhere), starts over with `toKey`.
    function d:SetRecipe(recipe, toKey, fresh)
        if fresh or not (self.recipe and recipe and self.recipe.id == recipe.id) then
            self.qty, self.mode = 1, "mats"
            tip:SetText("")
            self.toKey = toKey
            scroll:SetVerticalScroll(0)
            whoScroll:SetVerticalScroll(0)
        end
        self.recipe = recipe
        local was = self:IsShown()
        self:Show()
        self:Paint()
        if not was and self.onChange then self.onChange(true) end
    end

    -- Closed: by "‹ Orders" (`toOrders`), Escape or its row clicked again. The catalog lets go of the recipe.
    function d:Close(toOrders)
        local was = self:IsShown()
        self.recipe = nil
        self:Hide()
        if self.onClose then self.onClose() end
        if was and self.onChange then self.onChange(false, toOrders) end
    end
    back:SetScript("OnClick", function() d:Close(true) end)

    -- Escape closes the card first, the window after. Keys go on to the game otherwise (never touched in combat,
    -- where a frame may not change that).
    d:EnableKeyboard(true)
    d:SetScript("OnKeyDown", function(self, key)
        local fight = GuildOS.Compat.InCombat and GuildOS.Compat.InCombat()
        if key == "ESCAPE" then
            if not fight and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            self:Close()
        elseif not fight and self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    d:SetScript("OnSizeChanged", function(self)
        if self:IsShown() and self.recipe then self:Paint() end
    end)
    return d
end

-- Where the card sits when no Crafts tab places it (a catalog on its own): over the right part of `host`.
function UI.PlaceRecipeCard(card, host, w)
    if not card or card.hosted then return end
    w = w or UI:LaidWidth(host)
    card:ClearAllPoints()
    card:SetPoint("TOPRIGHT", host, "TOPRIGHT", -10, -8)
    card:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -10, 10)
    card:SetWidth(math.max(260, math.min(360, (w or 0) - 220)))
    card:SetFrameLevel((host:GetFrameLevel() or 1) + 30)
end


----------------------------------------------------------------------
-- The Crafts tab: the catalog and the order queue, side by side (issue #389)
----------------------------------------------------------------------
local QUEUE_W   = 300
local CARD_W    = 340    -- the recipe card in the right column
local QUEUE_MIN = 1000   -- under this width the queue becomes a drawer and the recipe card lies over the table

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
    -- The recipe chosen in the catalog: its card takes the right column (the Orders card's place), or lies over
    -- the table's right part in a narrow window.
    local card = panel and panel.detail
    if card then
        card.hosted = true
        if card.SetParent then card:SetParent(container) end
    end

    -- Search the realm (the Workshop's second entry): a screen of this tab, in place of the catalog and the queue.
    local realm = CreateFrame("Frame", nil, container)
    realm:SetAllPoints()
    realm:Hide()
    local finder = GuildOS.CreateRealmSearch and GuildOS:CreateRealmSearch(realm)
    local view = "catalog"

    local lastW
    local function layout(w)
        w = w or lastW or UI:LaidWidth(container) or 0
        lastW = w
        if view == "realm" then
            host:Hide(); dock:Hide(); toggle:Hide()
            if card then card:Hide() end
            return
        end
        host:Show()
        local wide = w >= QUEUE_MIN
        local open = card ~= nil and card:IsShown()
        local colW = (wide and open) and CARD_W or QUEUE_W
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT")
        host:SetPoint("BOTTOMRIGHT", wide and -(colW + 12) or 0, 0)
        dock:ClearAllPoints()
        dock:SetPoint("TOPRIGHT", -10, -8)
        dock:SetPoint("BOTTOMRIGHT", -10, wide and 10 or 34)
        dock:SetWidth(QUEUE_W)
        -- The card takes the column while it is open; the drawer closes under it.
        dock:SetShown(queue ~= nil and not open and (wide or drawerOpen))
        toggle:SetShown(queue ~= nil and not wide and not open)
        if card then
            card:ClearAllPoints()
            card:SetPoint("TOPRIGHT", container, "TOPRIGHT", -10, -8)
            card:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -10, 10)
            card:SetWidth(wide and CARD_W or math.max(280, math.min(CARD_W, w - 240)))
            card:SetFrameLevel(container:GetFrameLevel() + 22)
        end
    end
    toggle:SetScript("OnClick", function()
        drawerOpen = not drawerOpen
        layout()
        if drawerOpen and queue then GuildOS:SafeCall(queue.Draw, queue) end
    end)
    if card then
        -- Opened or closed: the column follows. "‹ Orders" in a narrow window opens the drawer it covered.
        card.onChange = function(_, toOrders)
            if toOrders and not (lastW and lastW >= QUEUE_MIN) then drawerOpen = true end
            layout()
            if panel.Relayout then GuildOS:SafeCall(panel.Relayout, panel) end
            if queue and dock:IsShown() then GuildOS:SafeCall(queue.Draw, queue) end
        end
    end
    UI:MakeResponsive(container, function(_, w) layout(w) end)
    layout()

    -- The catalog, or Search the realm. The recipe open on the catalog is let go when the realm's screen opens.
    local function showView(v)
        v = (v == "realm" and finder) and "realm" or "catalog"
        if v == "realm" and card and card:IsShown() then card:Close() end
        view = v
        container.activeSub = v == "realm" and "realm" or nil
        realm:SetShown(v == "realm")
        layout()
        if v == "realm" then GuildOS:SafeCall(finder.Relayout, finder) end
    end
    -- The window opened one of the tab's entries: the Crafts entry (no sub-tab) is the catalog.
    container.SetSubBarShown = function()
        local e = win and win.activeEntry
        if not (e and e.sub == "realm") then showView("catalog") end
    end

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
    container.SelectSub = function(sub, filter)
        if sub == "realm" then
            showView("realm")
            if finder and tonumber(filter) then finder.RunQuery(filter) end
            return
        end
        showView("catalog")
        if not queue then return end
        if card and card:IsShown() then card:Close() end
        if not dock:IsShown() then drawerOpen = true; layout() end
        queue:Select(sub)
    end
    container.panel, container.queue, container.dock, container.toggle, container.card = panel, queue, dock, toggle, card
    container.finder, container.ShowView = finder, showView
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
    f.to = UI:CreateText(f, "", UI.SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
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

    f.rgHeader = UI:CreateHeaderText(f, L["Materials"], UI.SP.META)
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
    f.rgNone = UI:CreateText(f, "", UI.SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.rgNone:SetWidth(DIALOG_W - 28); f.rgNone:SetJustifyH("LEFT")

    f.send = UI:CreateButton(f, L["Send order"], 130, 24)
    UI:SetButtonVariant(f.send, "primary")
    f.send:SetPoint("BOTTOMRIGHT", -14, 12)
    f.crafters = UI:CreateText(f, "", UI.SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
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
        UI:SetInk(f.itemName, qc)
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
        local title = UI:CreateHeaderText(mailBar, L["Craft orders"], UI.SP.META)
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
