----------------------------------------------------------------------
-- Guild OS - Guild Hub + DKP panels
-- Brings the community/loot features into the main window as real tabs
-- instead of slash-only popups:
--   * Guild hub: Activity feed, Bulletin board, Polls (sub-tabs)
--   * DKP: standings + officer controls
-- Renders from the module data APIs (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

----------------------------------------------------------------------
-- Shared builders
----------------------------------------------------------------------
local function makeScroll(panel, name, top)
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(top or 0))
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, child = UI:CreateScrollFrame(holder, name)
    scroll:SetAllPoints()
    return holder, child
end

local function clear(child)
    for _, c in pairs({ child:GetChildren() }) do c:Hide() end
    for _, r in pairs({ child:GetRegions() }) do r:Hide() end
end

local function makeInput(parent, w, multiline)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(w, multiline and 50 or 24)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.05, 0.05, 0.066, 1)
    b:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    b:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    b:SetTextColor(C.white.r, C.white.g, C.white.b)
    b:SetTextInsets(6, 6, multiline and 4 or 0, 0)
    b:SetAutoFocus(false)
    if multiline then b:SetMultiLine(true) end
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return b
end

----------------------------------------------------------------------
-- ACTIVITY sub-panel — recent guild activity (last 7 days)
----------------------------------------------------------------------
local function BuildActivitySub(panel)
    local hint = UI:CreateText(panel, L["What's happened in the guild lately."], 9, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 4, -2)
    local holder, child = makeScroll(panel, "GuildOSHubActivityScroll", 20)

    return function()
        clear(child)
        child:SetWidth(holder:GetWidth() - 12)
        local lines = {}
        if BRutus.Digest then
            local since = GetServerTime() - 7 * 86400
            lines = BRutus.Digest:Build(since)
        end
        local y = 0
        for _, line in ipairs(lines) do
            local dot = UI:CreateText(child, "|cffEDCC7B*|r", 12, C.gold.r, C.gold.g, C.gold.b)
            dot:SetPoint("TOPLEFT", 2, -y)
            local fs = UI:CreateText(child, line, 11, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 18, -y)
            fs:SetWidth(child:GetWidth() - 22)
            fs:SetJustifyH("LEFT")
            y = y + math.max(20, (fs:GetStringHeight() or 14) + 8)
        end
        if #lines == 0 then
            local empty = UI:CreateText(child, L["Nothing new in the last 7 days."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, y))
    end
end

----------------------------------------------------------------------
-- BULLETIN sub-panel
----------------------------------------------------------------------
local function BuildBulletinSub(panel)
    local listTop = 6
    local box
    if BRutus:IsOfficer() then
        box = makeInput(panel, 0, false)
        box:SetPoint("TOPLEFT", 4, -4)
        box:SetPoint("TOPRIGHT", -96, -4)
        box:SetMaxLetters(200)
        local function doPost()
            if BRutus.Bulletin then BRutus.Bulletin:Post(box:GetText()) end
            box:SetText(""); box:ClearFocus()
        end
        box:SetScript("OnEnterPressed", doPost)
        local postBtn = UI:CreateButton(panel, L["Post"], 84, 24)
        postBtn:SetPoint("TOPRIGHT", -4, -4)
        postBtn:SetScript("OnClick", doPost)
        listTop = 36
    end
    local holder, child = makeScroll(panel, "GuildOSHubBulletinScroll", listTop)

    local function refresh()
        clear(child)
        child:SetWidth(holder:GetWidth() - 12)
        local msgs = (BRutus.Bulletin and BRutus.Bulletin:GetMessages()) or {}
        local isOfficer = BRutus:IsOfficer()
        local y = 0
        for _, m in ipairs(msgs) do
            local textFS = UI:CreateText(child, m.text, 11, C.text.r, C.text.g, C.text.b)
            textFS:SetPoint("TOPLEFT", 4, -y)
            textFS:SetWidth(child:GetWidth() - (isOfficer and 30 or 10))
            textFS:SetJustifyH("LEFT")
            local th = textFS:GetStringHeight() or 14
            local meta = UI:CreateText(child,
                "|cff888888" .. (m.author or "?") .. " · " .. date("%m/%d %H:%M", m.ts or 0) .. "|r",
                9, C.textDim.r, C.textDim.g, C.textDim.b)
            meta:SetPoint("TOPLEFT", 4, -(y + th + 2))
            if isOfficer then
                local del = UI:CreateButton(child, "\195\151", 22, 18)
                del:SetPoint("TOPRIGHT", -2, -y)
                local id = m.id
                del:SetScript("OnClick", function() if BRutus.Bulletin then BRutus.Bulletin:Remove(id) end end)
            end
            y = y + th + 22
        end
        if #msgs == 0 then
            local empty = UI:CreateText(child, L["No notices yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, y))
    end
    if BRutus.Bulletin then BRutus.Bulletin.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- POLLS sub-panel
----------------------------------------------------------------------
local function BuildPollsSub(panel)
    local listTop = 6
    if BRutus:IsOfficer() then
        local qBox = makeInput(panel, 0, false)
        qBox:SetPoint("TOPLEFT", 4, -4)
        qBox:SetPoint("TOPRIGHT", -120, -4)
        qBox:SetMaxLetters(150)
        local oBox = makeInput(panel, 0, true)
        oBox:SetPoint("TOPLEFT", 4, -32)
        oBox:SetPoint("TOPRIGHT", -4, -32)
        local createBtn = UI:CreateButton(panel, L["Create Poll"], 110, 24)
        createBtn:SetPoint("TOPRIGHT", -4, -4)
        createBtn:SetScript("OnClick", function()
            local opts = {}
            for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                local t = strtrim(line)
                if t ~= "" and #opts < 6 then opts[#opts + 1] = t end
            end
            if BRutus.Polls then BRutus.Polls:Create(qBox:GetText(), opts) end
            qBox:SetText(""); oBox:SetText(""); qBox:ClearFocus(); oBox:ClearFocus()
        end)
        local hint = UI:CreateText(panel, L["One option per line (2-6)"], 8, C.textDim.r, C.textDim.g, C.textDim.b)
        hint:SetPoint("TOPLEFT", 6, -84)
        listTop = 96
    end
    local holder, child = makeScroll(panel, "GuildOSHubPollsScroll", listTop)

    local function keyOf(name)
        local short = (name or ""):match("^([^-]+)") or name
        return BRutus:GetPlayerKey(short, GetRealmName())
    end

    local function refresh()
        clear(child)
        child:SetWidth(holder:GetWidth() - 12)
        local polls = (BRutus.Polls and BRutus.Polls:GetSorted()) or {}
        local isOfficer = BRutus:IsOfficer()
        local myKey = keyOf(UnitName("player"))
        local y = 0
        for _, p in ipairs(polls) do
            local q = UI:CreateText(child, (p.closed and "|cff888888[" .. L["closed"] .. "]|r " or "") .. p.question,
                12, C.gold.r, C.gold.g, C.gold.b)
            q:SetPoint("TOPLEFT", 4, -y)
            q:SetWidth(child:GetWidth() - (isOfficer and 70 or 10))
            q:SetJustifyH("LEFT")
            if isOfficer and not p.closed then
                local closeBtn = UI:CreateButton(child, L["Close"], 56, 18)
                closeBtn:SetPoint("TOPRIGHT", -2, -y)
                local id = p.id
                closeBtn:SetScript("OnClick", function() if BRutus.Polls then BRutus.Polls:Close(id) end end)
            end
            y = y + math.max(18, (q:GetStringHeight() or 14) + 4)

            local total, counts = 0, {}
            for _, opt in pairs(p.votes or {}) do counts[opt] = (counts[opt] or 0) + 1; total = total + 1 end
            local myVote = p.votes and p.votes[myKey]
            for idx, optText in ipairs(p.options or {}) do
                local n = counts[idx] or 0
                local pct = total > 0 and math.floor(n / total * 100 + 0.5) or 0
                local btn = UI:CreateButton(child, string.format("%s  (%d · %d%%)", optText, n, pct), child:GetWidth() - 8, 20)
                btn:SetPoint("TOPLEFT", 4, -y)
                if myVote == idx then
                    btn:SetBaseColor(C.accent.r * 0.34, C.accent.g * 0.34, C.accent.b * 0.34, 0.95)
                    btn.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
                end
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", 8, 0)
                if not p.closed then
                    local id, oi = p.id, idx
                    btn:SetScript("OnClick", function() if BRutus.Polls then BRutus.Polls:Vote(id, oi) end end)
                end
                y = y + 22
            end
            local meta = UI:CreateText(child,
                "|cff888888" .. string.format(L["%d vote(s) · by %s"], total, p.author or "?") .. "|r",
                8, C.textDim.r, C.textDim.g, C.textDim.b)
            meta:SetPoint("TOPLEFT", 4, -y)
            y = y + 22
        end
        if #polls == 0 then
            local empty = UI:CreateText(child, L["No polls yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, y))
    end
    if BRutus.Polls then BRutus.Polls.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- Guild Hub assembly (sub-tab bar mirrors the Audit panel)
----------------------------------------------------------------------
local HUB_SUBTABS = {
    { key = "activity", label = L["Activity"] },
    { key = "bulletin", label = L["Bulletin"] },
    { key = "polls",    label = L["Polls"] },
}

function BRutus:CreateGuildHub(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "activity"

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetPoint("TOPRIGHT", -10, -8)
    bar:SetHeight(26)

    local subTabBtns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
    end

    local x = 0
    for _, t in ipairs(HUB_SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 120)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + 124
    end

    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", 12, -42)
        p:SetPoint("BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end

    local builders = { activity = BuildActivitySub, bulletin = BuildBulletinSub, polls = BuildPollsSub }
    for _, t in ipairs(HUB_SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "activity")
    end)
end

----------------------------------------------------------------------
-- DKP panel (standings + officer controls), embedded as a main tab.
----------------------------------------------------------------------
function BRutus:CreateDKPPanel(parent, _mainFrame)
    local summary = UI:CreateText(parent, "", 11, C.gold.r, C.gold.g, C.gold.b)
    summary:SetPoint("TOPLEFT", 12, -10)

    local openBtn = UI:CreateButton(parent, L["More..."], 90, 22)
    openBtn:SetPoint("TOPRIGHT", -12, -8)
    openBtn:SetScript("OnClick", function() if BRutus.ShowPointsFrame then BRutus:ShowPointsFrame() end end)

    local controlsTop = -34
    if BRutus:IsOfficer() then
        local nameInput = makeInput(parent, 150, false)
        nameInput:SetPoint("TOPLEFT", 12, -32)
        local amtInput = makeInput(parent, 60, false)
        amtInput:SetPoint("LEFT", nameInput, "RIGHT", 6, 0)
        amtInput:SetNumeric(true); amtInput:SetMaxLetters(6)
        local reasonInput = makeInput(parent, 180, false)
        reasonInput:SetPoint("LEFT", amtInput, "RIGHT", 6, 0)
        local function doAdjust(sign)
            local nm = strtrim(nameInput:GetText() or "")
            local amt = tonumber(amtInput:GetText())
            if nm == "" or not amt or amt == 0 or not BRutus.Points then return end
            BRutus.Points:Adjust(BRutus:GetPlayerKey(nm, GetRealmName()), sign * math.abs(amt),
                strtrim(reasonInput:GetText() or ""), sign > 0 and "award" or "spend")
            amtInput:SetText(""); reasonInput:SetText(""); nameInput:ClearFocus()
        end
        local awardBtn = UI:CreateButton(parent, L["Award"], 64, 24)
        awardBtn:SetPoint("LEFT", reasonInput, "RIGHT", 8, 0)
        awardBtn:SetScript("OnClick", function() doAdjust(1) end)
        local chargeBtn = UI:CreateButton(parent, L["Charge"], 64, 24)
        chargeBtn:SetPoint("LEFT", awardBtn, "RIGHT", 6, 0)
        chargeBtn:SetScript("OnClick", function() doAdjust(-1) end)
        controlsTop = -64
    end

    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 12, controlsTop)
    header:SetPoint("TOPRIGHT", -12, controlsTop)
    header:SetHeight(16)
    local function hcol(txt, px)
        local fs = UI:CreateHeaderText(header, txt, 9)
        fs:SetPoint("LEFT", px, 0)
    end
    hcol(L["MEMBER"], 4)
    hcol(L["CURRENT"], 250)
    hcol(L["EARNED"], 330)
    hcol(L["SPENT"], 410)

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", 12, controlsTop - 18)
    holder:SetPoint("BOTTOMRIGHT", -12, 10)
    local scroll, child = UI:CreateScrollFrame(holder, "GuildOSDKPTabScroll")
    scroll:SetAllPoints()

    local function refresh()
        clear(child)
        child:SetWidth(holder:GetWidth() - 12)
        if BRutus.Points then
            local mode = BRutus.Points:GetMode()
            summary:SetText(string.format(L["Mode: %s  ·  click More for decay / raid award / history"], mode))
        end
        local list = (BRutus.Points and BRutus.Points:GetStandings()) or {}
        local y = 0
        for idx, s in ipairs(list) do
            local row = CreateFrame("Frame", nil, child)
            row:SetSize(child:GetWidth(), 22)
            row:SetPoint("TOPLEFT", 0, -y)
            local cr, cg, cb = BRutus:GetClassColor(s.class)
            local nameFS = UI:CreateText(row, idx .. ". " .. s.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 4, 0)
            local cur = UI:CreateText(row, tostring(s.current), 11, C.gold.r, C.gold.g, C.gold.b)
            cur:SetPoint("LEFT", 250, 0)
            local earn = UI:CreateText(row, tostring(s.earned), 10, C.green.r, C.green.g, C.green.b)
            earn:SetPoint("LEFT", 330, 0)
            local spent = UI:CreateText(row, tostring(s.spent), 10, C.silver.r, C.silver.g, C.silver.b)
            spent:SetPoint("LEFT", 410, 0)
            y = y + 23
        end
        if #list == 0 then
            local empty = UI:CreateText(child, L["No points recorded yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        child:SetHeight(math.max(1, y))
    end

    parent.RefreshActive = refresh
    parent:SetScript("OnShow", refresh)
end
