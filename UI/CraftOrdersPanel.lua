----------------------------------------------------------------------
-- Guild OS - Craft orders window (issue #389)
-- The Orders tab (My orders · For me · Open that I can craft), the dialog that places an order, and
-- the bars on the game's trade and mail windows that hand the materials or the item over in one
-- click. Visual layer only: every change goes through GuildOS.CraftOrders.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local SUB_H   = 28
local GAP     = tonumber(UI.GAP) or 8
local GUTTER  = tonumber(UI.SCROLL_GUTTER) or 12
local ROW_H   = 30
local HEAD_H  = 22
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

-- One line on what an order asks for: whose materials, and the tip.
local function termsText(o)
    local t = o.mode == "own" and L["Crafter's materials"] or L["My materials"]
    if (o.tip or 0) > 0 then t = t .. " · " .. money(o.tip) end
    return t
end

-- The order's state, with who it is with.
local function stateText(o)
    local st = Orders().StateOf(o)
    local t = STATE_TEXT[st] or STATE_TEXT.open
    if st == "open" and o.to then t = string.format(L["Sent to %s"], nameOf(o.to))
    elseif (st == "accepted" or st == "mats") and o.cr then t = t .. " · " .. nameOf(o.cr) end
    local col = (st == "done" and C.ok) or ((st == "cancelled" or st == "expired") and C.label) or C.text
    return t, col
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
-- A list with pooled rows over a FauxScrollFrame (the bank's, kept local)
----------------------------------------------------------------------
local listCount = 0
local function makeList(parent, rowH, create, draw)
    listCount = listCount + 1
    local name = "GuildOSOrderList" .. listCount
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(list) })
    list:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    list:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
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
                GuildOS:SafeCall(draw, row, item)
                row:Show()
            else
                row.data = nil
                row:Hide()
            end
        end
        if list.empty then list.empty:SetShown(#list.data == 0) end
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
            local hl = row:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetColorTexture(C.panel.r, C.panel.g, C.panel.b, 1)
            hl:Hide()
            row.hl = hl
            row:SetScript("OnEnter", function(self)
                self.hl:Show()
                if self.data then orderTooltip(self, self.data) end
            end)
            row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
            row:SetScript("OnClick", function(self)
                if self.data and IsShiftKeyDown() and HandleModifiedItemClick then
                    local _, link = itemInfo(self.data.item)
                    if link then HandleModifiedItemClick(link) end
                end
            end)
            local rule = row:CreateTexture(nil, "BORDER")
            rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
            UI:Hairline(rule)
            rule:SetColorTexture(C.panel.r, C.panel.g, C.panel.b, 1)
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
    function list:SetEmptyText(text)
        if not self.empty then
            self.empty = UI:CreateText(self, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            self.empty:SetPoint("TOPLEFT", 12, -14)
            self.empty:SetPoint("RIGHT", -12, 0)
            self.empty:SetJustifyH("LEFT")
        end
        self.empty:SetText(text)
    end
    return list
end

local function headerText(parent, text, x)
    local fs = UI:CreateHeaderText(parent, text, 10)
    fs:SetPoint("LEFT", x, 0)
    return fs
end

----------------------------------------------------------------------
-- One view of the tab
----------------------------------------------------------------------
-- The buttons a row offers, by view and state: { { label, fn, primary } }, at most three.
local function actionsFor(view, o)
    local O, me = Orders(), Orders():MyKey()
    local st = O.StateOf(o)
    local out = {}
    local function add(label, fn, primary) out[#out + 1] = { label, fn, primary } end
    local id = o.id
    if view == "mine" then
        if (st == "accepted" or st == "mats") and o.cr then add(L["Whisper"], function() whisper(o.cr) end) end
        if st == "accepted" or st == "mats" then add(L["Received"], function() O:Act(id, "done") end) end
        if O.ACTIVE[st] then add(L["Cancel"], function() O:Act(id, "cancel") end) end
    elseif view == "forme" then
        if st == "open" and o.to == me then
            add(L["Accept"], function() O:Act(id, "accept") end, true)
            add(L["Decline"], function() O:Act(id, "decline") end)
            add(L["Whisper"], function() whisper(o.who) end)
        elseif (st == "accepted" or st == "mats") and o.cr == me then
            add(L["Done"], function() O:Act(id, "done") end, true)
            add(L["Give back"], function() O:Act(id, "release") end)
            add(L["Whisper"], function() whisper(o.who) end)
        end
    elseif view == "open" and st == "open" then
        add(L["Accept"], function() O:Act(id, "accept") end, true)
        add(L["Whisper"], function() whisper(o.who) end)
    end
    return out
end

local EMPTY = {
    mine  = L["You have no craft orders. Find an item in Find a Crafter or on the Professions tab, or type /gos order and an item."],
    forme = L["Nothing for you: orders sent to you and the ones you accept show here."],
    open  = L["No open orders for a recipe you know."],
}

local function buildView(p, view)
    local head = UI:CreateTableHeader(p, HEAD_H)
    head:SetPoint("TOPLEFT", 0, -GAP)
    head:SetPoint("RIGHT", p, "RIGHT", -GAP, 0)
    headerText(head, L["WHEN"], 8)
    headerText(head, L["ITEM"], 76)
    headerText(head, view == "mine" and L["CRAFTER"] or L["FOR"], 300)
    headerText(head, L["STATE"], 420)

    local list = makeList(p, ROW_H, function(row)
        row.when = UI:CreateText(row, "", 11, C.label.r, C.label.g, C.label.b)
        GuildOS:ApplyFont(row.when, 11, "tableNum")
        row.when:SetPoint("LEFT", 8, 0)
        row.when:SetWidth(64); row.when:SetJustifyH("LEFT")
        row.icon = UI:CreateIcon(row, ICON)
        row.icon:SetPoint("LEFT", 76, 0)
        row.name = UI:CreateText(row, "", 12)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 2)
        row.name:SetWidth(196); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.terms = UI:CreateText(row, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.terms:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.terms:SetWidth(196); row.terms:SetJustifyH("LEFT"); row.terms:SetWordWrap(false)
        row.who = UI:CreateText(row, "", 12)
        row.who:SetPoint("LEFT", 300, 0)
        row.who:SetWidth(112); row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)
        row.state = UI:CreateText(row, "", 11)
        row.state:SetPoint("LEFT", 420, 0)
        row.state:SetPoint("RIGHT", row, "RIGHT", -262, 0)
        row.state:SetJustifyH("LEFT"); row.state:SetWordWrap(false)
        row.btns = {}
        for i = 1, 3 do
            local b = UI:CreateButton(row, "", 80, 20)
            b:SetPoint("RIGHT", -4 - (3 - i) * 84, 0)
            b:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
            row.btns[i] = b
        end
    end, function(row, o)
        row.when:SetText(GuildOS:TimeAgo(o.ts))
        local name, _, quality, tex = itemInfo(o.item)
        row.icon.icon:SetTexture(tex or QUESTION)
        UI:SetIconQuality(row.icon, quality or 1)
        local qc = (GuildOS.QualityColors and GuildOS.QualityColors[quality or 1]) or C.text
        row.name:SetText((name or ("item:" .. o.item)) .. (o.n > 1 and (" × " .. o.n) or ""))
        row.name:SetTextColor(qc.r, qc.g, qc.b)
        row.terms:SetText(termsText(o) .. (o.note and ("  ·  " .. o.note) or ""))
        local whoKey = view == "mine" and (o.cr or o.to) or o.who
        if whoKey then
            local cc = classColor(whoKey)
            row.who:SetText(nameOf(whoKey))
            row.who:SetTextColor(cc.r, cc.g, cc.b)
        else
            row.who:SetText(L["Any crafter"])
            row.who:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        end
        local st, col = stateText(o)
        row.state:SetText(st)
        row.state:SetTextColor(col.r, col.g, col.b)
        local acts = actionsFor(view, o)
        -- Right-aligned: the last action sits at the edge.
        for i = 1, 3 do
            local a = acts[#acts - 3 + i]
            local b = row.btns[i]
            b:SetShown(a ~= nil)
            if a then
                b.label:SetText(a[1])
                b.fn = a[2]
                UI:SetButtonVariant(b, a[3] and "primary" or "secondary")
            end
        end
    end)
    list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -GAP, GAP)
    list:SetEmptyText(EMPTY[view])
    p.Draw = function() list:SetData(Orders():Rows(view)) end
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
function GuildOS:CreateCraftOrdersPanel(container, _mainFrame)
    local subBar = CreateFrame("Frame", nil, container)
    subBar:SetPoint("TOPLEFT", 0, 0)
    subBar:SetPoint("TOPRIGHT", 0, 0)
    subBar:SetHeight(SUB_H)
    UI:StyleSubTabBar(subBar)

    local SUBS = {
        { key = "mine",  label = L["My orders"] },
        { key = "forme", label = L["For me"] },
        { key = "open",  label = L["Open that I can craft"] },
    }
    local panels, tabs = {}, {}
    local active

    local newBtn = UI:CreateButton(subBar, L["New order"], 110, 22)
    UI:SetButtonVariant(newBtn, "primary")
    newBtn:SetPoint("RIGHT", -GAP, 0)
    newBtn:SetScript("OnClick", function() GuildOS:ShowCraftOrderDialog() end)

    -- The sub-tabs say how many wait in each.
    local function labels()
        local O = Orders()
        for _, t in ipairs(tabs) do
            local n = 0
            for _, o in ipairs(O:Rows(t.key)) do if O.IsActive(o) then n = n + 1 end end
            t.label:SetText(n > 0 and string.format("%s (%d)", t.base, n) or t.base)
        end
    end

    local function select(key)
        if not panels[key] then key = "mine" end
        active = key
        for _, t in ipairs(tabs) do t:SetActive(t.key == key) end
        for k, p in pairs(panels) do if k ~= key then p:Hide() end end
        panels[key]:Show()
        labels()
        GuildOS:SafeCall(panels[key].Draw)
    end

    local prev
    for _, s in ipairs(SUBS) do
        local p = CreateFrame("Frame", nil, container)
        p:SetPoint("TOPLEFT", 0, -SUB_H)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        p:Hide()
        buildView(p, s.key)
        p:SetScript("OnShow", function(self) GuildOS:SafeCall(self.Draw) end)
        panels[s.key] = p
        local tab = UI:CreateTab(subBar, s.label, 150, true)
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 2, 0) else tab:SetPoint("LEFT", 4, 0) end
        tab.key, tab.base = s.key, s.label
        tab:SetScript("OnClick", function() select(s.key) end)
        tabs[#tabs + 1] = tab
        prev = tab
    end

    Orders().uiRefresh = function()
        if GuildOS.RefreshCraftOrderBars then GuildOS:RefreshCraftOrderBars() end
        if not container:IsVisible() then return end
        GuildOS:Coalesce("craftorders.ui", 0.3, function()
            labels()
            local p = active and panels[active]
            if p and p:IsVisible() then GuildOS:SafeCall(p.Draw) end
        end)
    end

    -- Opened with something new for me, the tab shows it; otherwise it stays where it was left.
    local seenForMe = 0
    local function openOn()
        local n = 0
        for _, o in ipairs(Orders():Rows("forme")) do if Orders().IsActive(o) then n = n + 1 end end
        local key = (n > seenForMe and "forme") or active or "mine"
        seenForMe = n
        select(key)
    end
    container:SetScript("OnShow", openOn)
    openOn()
    container.SelectSub = select
    container.ActiveSub = function() return active end
    container.panels = panels
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
        local rg = id and O:Reagents(id) or {}
        local crafts = id and math.ceil(n / O:Yield(id)) or n
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
        tradeBar.text:SetPoint("RIGHT", tradeBar.btn, "LEFT", -6, 0)
    end
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
    GuildOS.CraftOrders.uiRefresh = GuildOS.CraftOrders.uiRefresh or function() GuildOS:RefreshCraftOrderBars() end
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
