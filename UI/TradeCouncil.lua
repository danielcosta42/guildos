----------------------------------------------------------------------
-- Guild OS - Loot council window (retail, issue #185)
-- The offers open in the raid, the items in my bags I can still trade, and the answers to the offer
-- picked: who wants it, what they wear in that slot, their roll, wishlist place, points and
-- attendance. Visual layer only: every action is a TradeCouncil method (Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local W, H = 760, 450
local PAD = 16
local LEFT_W = 236
local ROW_H = 20
local OFFER_ROWS = 6
local ITEM_ROWS = 6
local ANSWER_ROWS = 9
local REFRESH_EVERY = 5     -- seconds: the time left on the offers

local frame, ticker
local selected              -- the id of the offer shown on the right

local function TC() return GuildOS.TradeCouncil end

-- "1:52" for what is left of a trade window, or "?" when the client could not read it.
local function clock(seconds)
    if not seconds then return "?" end
    seconds = math.max(0, seconds)
    return string.format("%d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function itemName(link)
    return (type(link) == "string" and link:match("|h%[(.-)%]|h")) or link or "?"
end

local function short(key)
    return (key or "?"):match("^([^-]+)") or key
end

local function showLink(owner, link)
    if not link then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

local function hideTip() GameTooltip:Hide() end

-- A plain row: a backdrop frame that can be hovered.
local function row(parent, width)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetSize(width, ROW_H)
    r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    return r
end

local function text(parent, size, width)
    local fs = UI:CreateText(parent, "", size or 10)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    if width then fs:SetWidth(width) end
    return fs
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------
local function build()
    local f = UI:CreatePanel(UIParent, "GuildOSTradeCouncil")
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    UI:StylePopup(f)
    tinsert(UISpecialFrames, "GuildOSTradeCouncil")

    local title = UI:CreateTitle(f, L["Loot Council"], 16)
    title:SetPoint("TOPLEFT", PAD, -12)
    local sub = UI:CreateText(f, L["Offer an item you can still trade: the raid answers, and it is awarded."], 9,
        C.silver.r, C.silver.g, C.silver.b)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Left: the offers in the raid, then my tradeable items.
    local y = -56
    local oh = UI:CreateHeaderText(f, L["OFFERS IN THE RAID"], 10)
    oh:SetPoint("TOPLEFT", PAD, y)
    y = y - 16
    f.offerRows = {}
    for i = 1, OFFER_ROWS do
        local r = row(f, LEFT_W)
        r:SetPoint("TOPLEFT", PAD, y - (i - 1) * (ROW_H + 2))
        r.label = text(r, 10, LEFT_W - 46)
        r.label:SetPoint("LEFT", 4, 0)
        r.time = text(r, 9, 40)
        r.time:SetPoint("RIGHT", -4, 0)
        r.time:SetJustifyH("RIGHT")
        r:SetScript("OnClick", function(self) selected = self.id; GuildOS:RefreshTradeCouncil() end)
        r:SetScript("OnEnter", function(self) showLink(self, self.link) end)
        r:SetScript("OnLeave", hideTip)
        f.offerRows[i] = r
    end
    f.noOffers = UI:CreateText(f, L["Nobody is offering anything."], 10, C.silver.r, C.silver.g, C.silver.b)
    f.noOffers:SetPoint("TOPLEFT", PAD + 4, y - 4)

    y = y - OFFER_ROWS * (ROW_H + 2) - 14
    local ih = UI:CreateHeaderText(f, L["YOUR TRADEABLE ITEMS"], 10)
    ih:SetPoint("TOPLEFT", PAD, y)
    y = y - 16
    f.itemRows = {}
    for i = 1, ITEM_ROWS do
        local r = row(f, LEFT_W)
        r:SetPoint("TOPLEFT", PAD, y - (i - 1) * (ROW_H + 2))
        r.label = text(r, 10, LEFT_W - 104)
        r.label:SetPoint("LEFT", 4, 0)
        r.time = text(r, 9, 36)
        r.time:SetPoint("LEFT", LEFT_W - 98, 0)
        r.offer = UI:CreateButton(r, L["Offer"], 56, 18)
        r.offer:SetPoint("RIGHT", -1, 0)
        r.offer:SetScript("OnClick", function(self) GuildOS.TradeCouncil:Offer(self:GetParent().link) end)
        r:SetScript("OnEnter", function(self) showLink(self, self.link) end)
        r:SetScript("OnLeave", hideTip)
        f.itemRows[i] = r
    end
    f.noItems = UI:CreateText(f, L["Nothing in your bags can still be traded."], 10, C.silver.r, C.silver.g, C.silver.b)
    f.noItems:SetPoint("TOPLEFT", PAD + 4, y - 4)

    -- Right: the offer picked.
    local x = PAD + LEFT_W + 20
    local rw = W - x - PAD
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", x, -56)
    d:SetSize(rw, H - 56 - PAD)
    f.detail = d

    local item = row(d, rw)
    item:SetBackdropColor(0, 0, 0, 0)
    item:SetPoint("TOPLEFT", 0, 0)
    item.label = text(item, 13, rw)
    item.label:SetPoint("LEFT", 0, 0)
    item:SetScript("OnEnter", function(self) showLink(self, self.link) end)
    item:SetScript("OnLeave", hideTip)
    d.item = item
    d.info = text(d, 10, rw)
    d.info:SetPoint("TOPLEFT", 0, -24)
    d.status = text(d, 10, rw)
    d.status:SetPoint("TOPLEFT", 0, -40)
    d.wish = text(d, 10, rw)
    d.wish:SetPoint("TOPLEFT", 0, -56)

    d.choiceButtons = {}
    local bx = 0
    for _, choice in ipairs({ "N", "G", "P" }) do
        local b = UI:CreateButton(d, GuildOS.TradeCouncil.CHOICE_LABEL[choice], 80, 22)
        b:SetPoint("TOPLEFT", bx, -76)
        b.choice = choice
        b:SetScript("OnClick", function(self) GuildOS.TradeCouncil:Answer(selected, self.choice) end)
        d.choiceButtons[#d.choiceButtons + 1] = b
        bx = bx + b:GetWidth() + 6
    end

    local COLS = { { L["PLAYER"], 0 }, { L["ANSWER"], 130 }, { L["ROLL"], 180 }, { L["EQUIPPED"], 212 },
                   { L["WISH"], 334 }, { L["PTS"], 364 }, { L["ATT%"], 402 } }
    for _, col in ipairs(COLS) do
        local h = UI:CreateHeaderText(d, col[1], 9)
        h:SetPoint("TOPLEFT", col[2], -108)
    end
    d.rows = {}
    for i = 1, ANSWER_ROWS do
        local r = row(d, rw)
        r:SetPoint("TOPLEFT", 0, -122 - (i - 1) * (ROW_H + 2))
        r.name = text(r, 10, 126)
        r.name:SetPoint("LEFT", 2, 0)
        r.answer = text(r, 10, 48)
        r.answer:SetPoint("LEFT", 130, 0)
        r.roll = text(r, 10, 30)
        r.roll:SetPoint("LEFT", 180, 0)
        r.worn = CreateFrame("Button", nil, r)
        r.worn:SetSize(118, ROW_H)
        r.worn:SetPoint("LEFT", 212, 0)
        r.worn.label = text(r.worn, 9, 118)
        r.worn.label:SetPoint("LEFT", 0, 0)
        r.worn:SetScript("OnEnter", function(self) showLink(self, self.link) end)
        r.worn:SetScript("OnLeave", hideTip)
        r.wish = text(r, 10, 28)
        r.wish:SetPoint("LEFT", 334, 0)
        r.pts = text(r, 10, 36)
        r.pts:SetPoint("LEFT", 364, 0)
        r.att = text(r, 10, 30)
        r.att:SetPoint("LEFT", 402, 0)
        r.award = UI:CreateButton(r, L["Award"], 50, 18)
        r.award:SetPoint("RIGHT", -1, 0)
        r.award:SetScript("OnClick", function(self) GuildOS.TradeCouncil:Award(selected, self:GetParent().key) end)
        d.rows[i] = r
    end
    d.noAnswers = UI:CreateText(d, L["No answers yet."], 10, C.silver.r, C.silver.g, C.silver.b)
    d.noAnswers:SetPoint("TOPLEFT", 2, -126)

    d.withdraw = UI:CreateButton(d, L["Withdraw offer"], 120, 22)
    d.withdraw:SetPoint("BOTTOMRIGHT", 0, 0)
    d.withdraw:SetScript("OnClick", function() GuildOS.TradeCouncil:Withdraw(selected) end)
    d.empty = UI:CreateText(d, L["Pick an offer, or offer one of your items."], 11, C.silver.r, C.silver.g, C.silver.b)
    d.empty:SetPoint("TOPLEFT", 0, -4)

    f:SetScript("OnShow", function()
        if ticker then ticker:Cancel() end
        ticker = GuildOS.Compat.NewTicker(REFRESH_EVERY, function() GuildOS:RefreshTradeCouncil() end)
    end)
    f:SetScript("OnHide", function()
        if ticker then ticker:Cancel() end
        ticker = nil
    end)
    f:Hide()   -- a new frame is shown: hidden here, its first Show runs OnShow and starts the ticker
    return f
end

----------------------------------------------------------------------
-- Filling
----------------------------------------------------------------------
local function paint(r, i, active)
    local bg = active and C.accent or ((i % 2 == 0) and C.row2 or C.row1)
    r:SetBackdropColor(bg.r, bg.g, bg.b, active and 0.35 or (bg.a or 0.6))
end

local function fillOffers(offers)
    local now = GetServerTime()
    for i, r in ipairs(frame.offerRows) do
        local o = offers[i]
        r.id, r.link = o and o.id, o and o.link
        if o then
            paint(r, i, o.id == selected)
            r.label:SetText(itemName(o.link) .. " |cff999999" .. short(o.holder) .. "|r")
            r.time:SetText(o.award and "|cff33ff33" .. L["awarded"] .. "|r" or clock(o.timeKnown and (o.expires - now) or nil))
            r:Show()
        else
            r:Hide()
        end
    end
    frame.noOffers:SetShown(#offers == 0)
end

local function fillItems(items)
    for i, r in ipairs(frame.itemRows) do
        local it = items[i]
        r.link = it and it.link
        if it then
            paint(r, i, false)
            r.label:SetText(it.link)
            r.time:SetText(clock(it.seconds))
            r:Show()
        else
            r:Hide()
        end
    end
    frame.noItems:SetShown(#items == 0)
end

local function fillDetail(o)
    local d = frame.detail
    local T = TC()
    local shown = o ~= nil
    for _, k in ipairs({ "item", "info", "status", "wish", "withdraw" }) do d[k]:SetShown(shown) end
    d.empty:SetShown(not shown)
    for _, b in ipairs(d.choiceButtons) do b:Hide() end
    for _, r in ipairs(d.rows) do r:Hide() end
    d.noAnswers:Hide()
    if not o then return end

    d.item.link = o.link
    d.item.label:SetText(o.link)
    local left = o.timeKnown and clock(o.expires - GetServerTime()) or L["unknown"]
    d.info:SetText(string.format(L["Offered by %s, tradeable for %s."], o.holder, left))
    local status
    if o.done then
        status = "|cff33ff33" .. string.format(L["Traded to %s: the award is recorded."], o.award.winner) .. "|r"
    elseif o.closed then
        status = "|cff999999" .. L["Withdrawn."] .. "|r"
    elseif o.award then
        status = "|cffffd100" .. string.format(L["Awarded to %s: waiting for the trade."], o.award.winner) .. "|r"
    else
        status = o.free and L["Free roll: the holder or an officer awards it."] or L["An officer awards it."]
    end
    d.status:SetText(status)
    local wishers = {}
    for _, w in ipairs(T:Wishers(o)) do wishers[#wishers + 1] = string.format("%s #%d", short(w.key), w.order) end
    d.wish:SetText(#wishers > 0 and (L["On the wishlist of:"] .. " " .. table.concat(wishers, ", ")) or "")
    d.withdraw:SetShown(T:MayIWithdraw(o))

    local mine = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
    if not o.closed and not T:IsMine(o) then
        local current = o.answers[mine] and o.answers[mine].choice
        for _, b in ipairs(d.choiceButtons) do
            b:SetBaseColor(C.well.r, C.well.g, C.well.b, 0)
            if b.choice == current then b:SetBaseColor(C.accent.r * 0.34, C.accent.g * 0.34, C.accent.b * 0.34, 0.95) end
            b:Show()
        end
    end

    local rows = T:Ranked(o)
    local canAward = T:MayIAward(o)
    local showPoints = GuildOS:GetLootSystem() == "dkp"
    for i, r in ipairs(d.rows) do
        local a = rows[i]
        r.key = a and a.key
        if a then
            paint(r, i, o.award and o.award.winner == a.key)
            local cr, cg, cb = GuildOS:GetClassColor(GuildOS.db.members[a.key] and GuildOS.db.members[a.key].class or "")
            r.name:SetText(a.key)
            r.name:SetTextColor(cr, cg, cb)
            local col = a.choice == "N" and C.green or (a.choice == "G" and C.gold or C.silver)
            r.answer:SetText(T.CHOICE_LABEL[a.choice] or "?")
            r.answer:SetTextColor(col.r, col.g, col.b)
            r.roll:SetText(tostring(a.roll))
            r.worn.link = a.equipped
            r.worn.label:SetText(a.equipped or "-")
            r.wish:SetText(a.wish and ("#" .. a.wish) or "-")
            r.pts:SetText(showPoints and a.points and tostring(a.points) or "-")
            r.att:SetText(T:Context(a.key).att .. "%")
            r.award:SetShown(canAward and a.choice ~= "P")
            r:Show()
        end
    end
    d.noAnswers:SetShown(#rows == 0)
end

local function refresh()
    local T = TC()
    if not (frame and T) then return end
    local offers = T:OpenOffers()
    if selected and not T:Get(selected) then selected = nil end
    if not selected and offers[1] then selected = offers[1].id end
    fillOffers(offers)
    fillItems(T:MyTradeableItems())
    fillDetail(selected and T:Get(selected))
end

----------------------------------------------------------------------
-- Entry points
----------------------------------------------------------------------

-- Open the loot council, on an offer when one is given (/gos offer with no item, the Settings quick
-- button, a new offer from the raid).
function GuildOS:ShowTradeCouncil(offerId)
    if not TC() then
        GuildOS:Print(L["Not available on this client."])
        return
    end
    if not frame then frame = build() end
    if offerId then selected = offerId end
    frame:Show()
    refresh()
end

-- Redraw the loot council when it is open (the module calls it on every change).
function GuildOS:RefreshTradeCouncil()
    if frame and frame:IsShown() then refresh() end
end
