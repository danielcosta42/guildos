----------------------------------------------------------------------
-- Guild OS - Loot council vote window (issue #336)
-- The item a council is voting on, its candidates already in the rule's order with what the rule
-- knows of each (the answer, the roll or the bid, attendance, items received, points and accounts, the
-- note), the votes so far, and a button to vote for each. The master looter's own shows the same and
-- ends the vote. Visual layer only: what is shown is LootCouncil:View() and every click is a
-- LootCouncil method (Rule 10).
----------------------------------------------------------------------
-- Not on retail, which has no master looter and no such vote (the module is absent there).
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
if not GuildOS.LootCouncil then return end

local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local W, H = 640, 360
local ROW_H = 24
local frame, ticker

local function LC() return GuildOS.LootCouncil end

local function hideTip() GameTooltip:Hide() end

-- The lines of a candidate's tooltip: the note, the lists, the accounts, and who voted for them.
local function tipLines(c, anon)
    local lines = {}
    if c.note then lines[#lines + 1] = c.note end
    if c.prio > 0 then lines[#lines + 1] = string.format(L["Officer priority #%d"], c.prio) end
    if c.wish > 0 then lines[#lines + 1] = string.format(L["Wishlist #%d"], c.wish) end
    if c.reserve == 2 then
        lines[#lines + 1] = L["Hard reserve"]
    elseif c.reserve == 1 then
        lines[#lines + 1] = L["Soft reserve"]
    end
    for _, a in ipairs(c.accts) do lines[#lines + 1] = string.format("%s: %d", a.key:upper(), a.value) end
    if not anon and #c.voters > 0 then
        lines[#lines + 1] = string.format(L["Voted by: %s"], table.concat(c.voters, ", "))
    end
    return lines
end

local function build()
    local f = CreateFrame("Frame", "GuildOSLootCouncilFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.95)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- The window's title and its lines in the text colours: gold is the selection's (#371).
    local title = UI:CreateTitle(f, L["Loot council"], 13)
    title:SetPoint("TOP", 0, -8)
    f.itemText = UI:CreateText(f, "", 12, C.text.r, C.text.g, C.text.b)
    f.itemText:SetPoint("TOP", 0, -28)
    f.statusText = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.statusText:SetPoint("TOP", 0, -46)

    -- The candidates' header row: the shared one, no fill and a 1px rule under it, ending where the
    -- rows end, short of the scroll bar (#371).
    local gutter = tonumber(UI.SCROLL_GUTTER) or 12
    local head = UI:CreateTableHeader(f)
    head:SetPoint("TOPLEFT", 10, -58)
    head:SetPoint("TOPRIGHT", -(10 + gutter), -58)
    local headers = { { L["Player"], 18 }, { L["Type"], 160 }, { L["Roll"], 210 }, { L["ATT%"], 280 }, { L["RECV"], 330 },
        { L["Points"], 380 }, { L["Votes"], 440 } }
    for _, h in ipairs(headers) do
        local ht = UI:CreateHeaderText(head, h[1], UI.SP.META)
        ht:SetPoint("LEFT", h[2], 0)
    end

    local scroll, content = UI:CreateScrollFrame(f, "GuildOSLootCouncilScroll")
    scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -10, 44)
    UI:BindScrollChildWidth(scroll, content)   -- the rows stop short of the scroll bar
    f.content = content

    f.hint = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.hint:SetPoint("BOTTOMLEFT", 12, 16)

    -- Take my vote back.
    f.abstainBtn = UI:CreateButton(f, L["Abstain"], 90, 22)
    f.abstainBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    f.abstainBtn:SetScript("OnClick", function() LC():Vote(0) end)

    -- The master looter ends the vote: whoever has the most votes is proposed.
    f.endBtn = UI:CreateButton(f, L["End vote"], 90, 22)
    f.endBtn:SetPoint("RIGHT", f.abstainBtn, "LEFT", -6, 0)
    f.endBtn:SetScript("OnClick", function() LC():EndVote() end)

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
    end)
    return f
end

-- One candidate's row, made once and refilled on every refresh: the window repaints each second while a
-- vote is open, and a frame the client makes is never freed, so a new row per tick only grew (memory audit).
local function tipOnEnter(self)
    local lines = self.tipLines
    if not lines or #lines == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(lines[1], 1, 1, 1)
    for i = 2, #lines do GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8) end
    GameTooltip:Show()
end

local function makeRow(content)
    -- Hung by both top corners (#371).
    local row = CreateFrame("Button", nil, content, "BackdropTemplate")
    row:SetHeight(ROW_H - 2)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    local function text(x, size, col)
        local fs = UI:CreateText(row, "", size, col.r, col.g, col.b)
        fs:SetPoint("LEFT", x, 0)
        return fs
    end
    row.place = text(4, 11, C.label)
    row.name = text(20, 11, C.text)
    row.answer = text(162, 11, C.text)
    row.roll = text(212, 11, C.textSoft)
    row.att = text(282, 11, C.textSoft)
    row.recv = text(336, 11, C.textSoft)
    row.pointsFS = text(382, 11, C.textSoft)
    row.votes = text(442, 12, C.text)
    row:SetScript("OnEnter", tipOnEnter)
    row:SetScript("OnLeave", hideTip)
    row.voteBtn = UI:CreateButton(row, L["Vote"], 70, 18)
    row.voteBtn:SetPoint("RIGHT", -2, 0)
    row.voteBtn:SetScript("OnClick", function(self) if self.to then LC():Vote(self.to) end end)
    return row
end

local function fillRow(row, y, c, view)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", 0, -y)
    -- The one the council proposes on the selected-row surface, not a gold tint (#371).
    local proposed = view.proposed ~= nil and view.proposed == c.name
    if proposed then
        row:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    else
        row:SetBackdropColor(C.well.r, C.well.g, C.well.b, 0.6)
    end
    row.place:SetText(c.place .. ".")
    row.name:SetText(c.name)
    row.answer:SetText(c.answer)
    local figure = "-"
    if c.bid > 0 then figure = string.format(L["bid %d"], c.bid) elseif c.roll > 0 then figure = tostring(c.roll) end
    row.roll:SetText(figure)
    row.att:SetText(c.att .. "%")
    row.recv:SetText(tostring(c.recv))
    row.pointsFS:SetText(tostring(c.points))
    row.votes:SetText(tostring(c.votes))
    row.tipLines = tipLines(c, view.anon)
    local btn = row.voteBtn
    if view.canVote then
        local mine = view.mine == c.place
        btn.label:SetText(mine and L["Voted"] or L["Vote"])
        UI:SetSelected(btn, mine)   -- my vote: the shared selection mark (#371)
        btn.to = c.place
        btn:Show()
    else
        btn.to = nil
        btn:Hide()
    end
    row:Show()
end

local function refresh()
    if not (frame and frame:IsShown()) then return end
    local view = LC():View()
    if not view then
        frame:Hide()
        return
    end
    frame.itemText:SetText(view.link or "")
    frame.statusText:SetText(LC():StatusText(view))
    local rows = frame.rows
    if not rows then rows = {}; frame.rows = rows end
    local y = 0
    for i, c in ipairs(view.candidates) do
        local row = rows[i]
        if not row then row = makeRow(frame.content); rows[i] = row end
        fillRow(row, y, c, view)
        y = y + ROW_H
    end
    for i = #view.candidates + 1, #rows do rows[i]:Hide() end
    frame.content:SetHeight(math.max(1, y))
    -- Why this player has no vote, when they have none.
    if view.canVote or not view.open then
        frame.hint:SetText(view.anon and L["Anonymous: only the totals are shown."] or "")
    else
        frame.hint:SetText(LC():WhyNot(view.whyNot))
    end
    if view.canVote and view.mine then frame.abstainBtn:Show() else frame.abstainBtn:Hide() end
    if view.isML and view.open then frame.endBtn:Show() else frame.endBtn:Hide() end
end

function GuildOS:ShowLootCouncil()
    if not LC():View() then return end
    frame = frame or build()
    frame:Show()
    -- The seconds left, while the window is open.
    if not ticker then ticker = C_Timer.NewTicker(1, refresh) end
    refresh()
end

function GuildOS:RefreshLootCouncil()
    refresh()
end
