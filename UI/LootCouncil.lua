----------------------------------------------------------------------
-- Guild OS - Loot council vote window (issue #336)
-- The item a council is voting on, its candidates already in the rule's order with what the rule
-- knows of each (the answer, the roll or the bid, attendance, items received, points and accounts, the
-- note), the votes so far, and a button to vote for each. The master looter's own shows the same and
-- ends the vote. Visual layer only: what is shown is LootCouncil:View() and every click is a
-- LootCouncil method (Rule 10).
----------------------------------------------------------------------
-- Not on retail, which has no master looter and no such vote (the module is absent there).
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
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.95)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = UI:CreateText(f, L["Loot council"], 13, C.gold.r, C.gold.g, C.gold.b)
    title:SetPoint("TOP", 0, -8)
    f.itemText = UI:CreateText(f, "", 12, C.white.r, C.white.g, C.white.b)
    f.itemText:SetPoint("TOP", 0, -28)
    f.statusText = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.statusText:SetPoint("TOP", 0, -46)

    local headers = { { L["Player"], 28 }, { L["Type"], 170 }, { L["Roll"], 220 }, { L["ATT%"], 290 }, { L["RECV"], 340 },
        { L["Points"], 390 }, { L["Votes"], 450 } }
    for _, h in ipairs(headers) do
        local ht = UI:CreateHeaderText(f, h[1], 9)
        ht:SetPoint("TOPLEFT", h[2], -64)
    end

    local scroll, content = UI:CreateScrollFrame(f, "GuildOSLootCouncilScroll")
    scroll:SetPoint("TOPLEFT", 10, -80)
    scroll:SetPoint("BOTTOMRIGHT", -30, 44)   -- room for the scroll bar on its right
    content:SetSize(W - 60, 1)
    f.content = content

    f.hint = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
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

-- One candidate's row.
local function drawRow(content, y, c, view)
    local row = CreateFrame("Button", nil, content, "BackdropTemplate")
    row:SetSize(W - 60, ROW_H - 2)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    local proposed = view.proposed ~= nil and view.proposed == c.name
    if proposed then
        row:SetBackdropColor(C.accent.r * 0.34, C.accent.g * 0.34, C.accent.b * 0.34, 0.8)
    else
        row:SetBackdropColor(0.082, 0.082, 0.105, 0.6)
    end

    local place = UI:CreateText(row, c.place .. ".", 10, C.silver.r, C.silver.g, C.silver.b)
    place:SetPoint("LEFT", 4, 0)
    local name = UI:CreateText(row, c.name, 10, C.white.r, C.white.g, C.white.b)
    name:SetPoint("LEFT", 20, 0)
    local answer = UI:CreateText(row, c.answer, 10, C.gold.r, C.gold.g, C.gold.b)
    answer:SetPoint("LEFT", 162, 0)
    local figure = "-"
    if c.bid > 0 then figure = string.format(L["bid %d"], c.bid) elseif c.roll > 0 then figure = tostring(c.roll) end
    local roll = UI:CreateText(row, figure, 10, C.white.r, C.white.g, C.white.b)
    roll:SetPoint("LEFT", 212, 0)
    local att = UI:CreateText(row, c.att .. "%", 10, C.white.r, C.white.g, C.white.b)
    att:SetPoint("LEFT", 282, 0)
    local recv = UI:CreateText(row, tostring(c.recv), 10, C.white.r, C.white.g, C.white.b)
    recv:SetPoint("LEFT", 336, 0)
    local points = UI:CreateText(row, tostring(c.points), 10, C.white.r, C.white.g, C.white.b)
    points:SetPoint("LEFT", 382, 0)
    local votes = UI:CreateText(row, tostring(c.votes), 11, C.gold.r, C.gold.g, C.gold.b)
    votes:SetPoint("LEFT", 446, 0)

    local lines = tipLines(c, view.anon)
    if #lines > 0 then
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(lines[1], 1, 1, 1)
            for i = 2, #lines do GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", hideTip)
    end

    if view.canVote then
        local mine = view.mine == c.place
        local voteBtn = UI:CreateButton(row, mine and L["Voted"] or L["Vote"], 70, 18)
        voteBtn:SetPoint("RIGHT", -2, 0)
        if mine then voteBtn:SetBaseColor(C.accent.r * 0.34, C.accent.g * 0.34, C.accent.b * 0.34, 0.95) end
        local to = c.place
        voteBtn:SetScript("OnClick", function() LC():Vote(to) end)
    end
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
    for _, child in pairs({ frame.content:GetChildren() }) do child:Hide() end
    local y = 0
    for _, c in ipairs(view.candidates) do
        drawRow(frame.content, y, c, view)
        y = y + ROW_H
    end
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
