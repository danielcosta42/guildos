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
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 70    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab

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
    BRutus:ApplyFont(b, 11)
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
-- CALL TO ARMS sub-panel (issue #108): officers send, everyone sees the
-- recent calls, answers them and sets how they want to be told.
----------------------------------------------------------------------
local function BuildCallToArmsSub(panel)
    local CTA = BRutus.CallToArms
    local selected = "worldboss"
    -- { row frame, its widgets, line height }: wrapped again on every resize. A row grows to the
    -- lines it took, and what hangs below it moves down with it.
    local rows = {}
    local above             -- the last section placed; the next one hangs below it

    local function reflow()
        local w = (panel:GetWidth() or 0) - 8
        if w < 200 then w = 600 end   -- not laid out yet: OnSizeChanged wraps it again
        for _, r in ipairs(rows) do
            r[1]:SetWidth(w)
            UI:FlowBar(r[1], r[2], { gap = 4, rowGap = 4, rowH = r[3] })
        end
    end
    panel:SetScript("OnSizeChanged", reflow)

    if BRutus:IsOfficer() then
        local head = UI:CreateText(panel, L["Send a call"], 11, C.gold.r, C.gold.g, C.gold.b)
        head:SetPoint("TOPLEFT", 4, -2)
        local tplRow, cells = CreateFrame("Frame", nil, panel), {}
        tplRow:SetPoint("TOPLEFT", 4, -20)
        rows[#rows + 1] = { tplRow, cells, 22 }

        local msgBox = makeInput(panel, 0, false)
        msgBox:SetPoint("TOPLEFT", tplRow, "BOTTOMLEFT", 0, -2)
        msgBox:SetPoint("TOPRIGHT", tplRow, "BOTTOMRIGHT", -96, -2)   -- the row is as wide as the panel
        msgBox:SetMaxBytes(CTA.TEXT_MAX + 1)   -- the call is cut at bytes, not letters: Cyrillic is two each
        local function send()
            if CTA:Send(selected, msgBox:GetText()) then msgBox:ClearFocus() end
        end
        local sendBtn = UI:CreateButton(panel, L["Send"], 88, 24)
        sendBtn:SetPoint("LEFT", msgBox, "RIGHT", 8, 0)
        sendBtn:SetScript("OnClick", send)
        msgBox:SetScript("OnEnterPressed", send)   -- a key press is a hardware event, as a click is

        local function paintSelected()
            for _, cell in ipairs(cells) do
                cell.btn.label:SetText((cell.id == selected and "> " or "") .. cell.name)
                cell:SetWidth(cell.btn:GetWidth() + (cell.del and 19 or 0))
            end
            reflow()
        end
        -- Built again only when the list changes; picking one only relabels.
        local function buildTemplates()
            for i = #cells, 1, -1 do cells[i]:Hide(); cells[i] = nil end
            for _, t in ipairs(CTA:Templates()) do
                local cell = CreateFrame("Frame", nil, tplRow)
                cell:SetHeight(22)
                cell.id, cell.name = t.id, t.name
                cell.btn = UI:CreateButton(cell, t.name, 112, 22)
                cell.btn:SetPoint("TOPLEFT")
                local id, text = t.id, t.text
                cell.btn:SetScript("OnClick", function()
                    selected = id
                    msgBox:SetText(text)
                    paintSelected()
                end)
                if not t.builtin then
                    cell.del = UI:CreateButton(cell, "\195\151", 18, 22)
                    cell.del:SetPoint("LEFT", cell.btn, "RIGHT", 1, 0)
                    cell.del:SetScript("OnClick", function()
                        CTA:DeleteTemplate(id)
                        if selected == id then selected = "worldboss" end
                        buildTemplates()
                    end)
                end
                cells[#cells + 1] = cell
            end
            paintSelected()
        end

        local nameBox = makeInput(panel, 160, false)
        nameBox:SetPoint("TOPLEFT", msgBox, "BOTTOMLEFT", 0, -6)
        nameBox:SetMaxBytes(CTA.NAME_MAX + 1)
        local saveBtn = UI:CreateButton(panel, L["Save as template"], 130, 24)
        saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
        saveBtn:SetScript("OnClick", function()
            local tpl = CTA:Template(selected)
            local ok, why = CTA:SaveTemplate(nameBox:GetText(), msgBox:GetText(), tpl and tpl.kind)
            if not ok then BRutus:Print(why) return end
            nameBox:SetText("")
            buildTemplates()
        end)
        local chatCb = UI:CreateCheckbox(panel, L["Also post in guild chat"], 16)
        chatCb:SetPoint("LEFT", saveBtn, "RIGHT", 12, 0)
        chatCb.checkbox:SetChecked(CTA:ChatOn())
        chatCb.checkbox.onChanged = function(_, checked) BRutus:SetSetting("ctaChat", checked and true or false) end
        above = nameBox

        buildTemplates()
        msgBox:SetText(CTA:Template(selected).text)
    end

    -- Everyone: how a call reaches me. A row of what to do with a call, then the types to hear.
    local mine = UI:CreateText(panel, L["My alerts"], 11, C.gold.r, C.gold.g, C.gold.b)
    if above then mine:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -10) else mine:SetPoint("TOPLEFT", 4, -2) end
    local function checkRow(anchor, items)
        local row = CreateFrame("Frame", nil, panel)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        local boxes = {}
        for _, it in ipairs(items) do
            local cb = UI:CreateCheckbox(row, it[1], 16)
            cb:SetWidth(30 + (cb.label:GetStringWidth() or 100))
            cb.checkbox:SetChecked(it[2]())
            local set = it[3]
            cb.checkbox.onChanged = function(_, checked) set(checked and true or false) end
            boxes[#boxes + 1] = cb
        end
        rows[#rows + 1] = { row, boxes, 18 }
        return row
    end
    local function setting(key) return function(v) BRutus:SetSetting(key, v) end end
    local how = checkRow(mine, {
        { L["Show popups"], function() return CTA:PopupsOn() end, setting("ctaPopups") },
        { L["Play a sound"], function() return CTA:SoundOn() end, setting("ctaSound") },
        { L["Quiet in instances and combat"], function() return CTA:QuietOn() end, setting("ctaQuiet") },
    })
    local kinds = {}
    for _, k in ipairs(CTA.KINDS) do
        local id = k.id
        kinds[#kinds + 1] = { k.title, function() return not CTA:Muted(id) end,
                              function(v) BRutus:SetSetting("ctaMute_" .. id, not v) end }
    end
    local hear = checkRow(how, kinds)

    local recentHead = UI:CreateText(panel, L["Recent calls"], 11, C.gold.r, C.gold.g, C.gold.b)
    recentHead:SetPoint("TOPLEFT", hear, "BOTTOMLEFT", 0, -10)
    local holder, child = makeScroll(panel, "GuildOSHubCTAScroll", 0)
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", recentHead, "BOTTOMLEFT", -4, -6)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    reflow()

    -- The recent calls, one pooled line each (there are never more than CTA.KEEP): an answer
    -- arriving repaints them in place rather than drawing them all again.
    local lines = {}
    local empty = UI:CreateText(child, L["No calls yet."], 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 4, -4)
    local function lineAt(i)
        if lines[i] then return lines[i] end
        local ln = {}
        ln.text = UI:CreateText(child, "", 11, C.text.r, C.text.g, C.text.b)
        ln.text:SetJustifyH("LEFT")
        ln.meta = UI:CreateText(child, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        ln.go = UI:CreateButton(child, L["On my way"], 90, 18)
        ln.go:SetScript("OnClick", function() CTA:Answer(ln.id) end)
        lines[i] = ln
        return ln
    end

    local function refresh()
        reflow()
        child:SetWidth(holder:GetWidth() - 12)
        local now, y = GetServerTime(), 0
        for i, e in ipairs(CTA.recent) do
            local ln = lineAt(i)
            ln.id = e.id
            -- Anybody who has not answered can, from here too: with popups off, in quiet mode
            -- or after dismissing one, this is the only place to.
            local open = not e.mine and not e.answered and now - (tonumber(e.ts) or 0) <= CTA.MAX_AGE
            ln.go:SetShown(open)
            ln.go:SetPoint("TOPRIGHT", -4, -y)
            ln.text:SetText(string.format("|cffFF8800%s|r  %s", e.title or "", e.text or ""))
            ln.text:SetWidth(child:GetWidth() - (open and 104 or 10))
            ln.text:SetPoint("TOPLEFT", 4, -y)
            ln.text:Show()
            local th = ln.text:GetStringHeight() or 14
            local n = CTA:GoingCount(e)
            ln.meta:SetText(string.format("|cff888888%s · %s · %s|r", e.zone or "",
                (Ambiguate and Ambiguate(e.sender or "", "short")) or (e.sender or ""),
                n > 0 and string.format(L["%d on the way"], n) or date("%H:%M", e.at or 0)))
            ln.meta:SetPoint("TOPLEFT", 4, -(y + th + 2))
            ln.meta:Show()
            y = y + th + 22
        end
        for i = #CTA.recent + 1, #lines do
            lines[i].text:Hide(); lines[i].meta:Hide(); lines[i].go:Hide()
        end
        empty:SetShown(#CTA.recent == 0)
        child:SetHeight(math.max(1, y))
    end
    -- Answers arrive by the dozen while the tab is closed; it catches up when it opens.
    CTA.uiRefresh = function() if panel:IsVisible() then refresh() end end
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
        local myKey = keyOf(BRutus.Compat.PlayerName())
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
    { key = "calendar", label = L["Calendar"] },
    { key = "activity", label = L["Activity"] },
    { key = "bulletin", label = L["Bulletin"] },
    { key = "cta",      label = L["Call to Arms"] },
    { key = "polls",    label = L["Polls"] },
}

function BRutus:CreateGuildHub(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "calendar"

    -- Anchored on the left only: UI:FlowBar reads GetWidth to wrap, and a frame pinned on both
    -- sides reports a stale width in the frame its container was resized (as ManagementPanel).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)

    local subTabBtns = {}
    local function selectSub(key, filter)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
        -- A deep link's filter goes to the sub-panel that takes one (the calendar: a day).
        if filter ~= nil and info and info.panel.ApplyFilter then BRutus:SafeCall(info.panel.ApplyFilter, filter) end
    end
    parent.SelectSub = selectSub   -- deep links: /guildos calendar, the Now tab

    -- A tab is as wide as its label: five at a fixed 120px ran off a narrow window (issue #108).
    local subTabList = {}
    for _, t in ipairs(HUB_SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        subTabList[#subTabList + 1] = btn
    end
    UI:FlowBar(bar, subTabList, { gap = 4, rowGap = 4, rowH = TAB_H })

    -- Hung from the bar, so a bar wrapped onto two rows pushes the content down.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -6)
        p:SetPoint("BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end

    local builders = {
        calendar = function(p) return BRutus:CreateCalendarSub(p) end,
        activity = BuildActivitySub, bulletin = BuildBulletinSub, polls = BuildPollsSub, cta = BuildCallToArmsSub,
    }
    for _, t in ipairs(HUB_SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "calendar")
    end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        UI:FlowBar(bar, subTabList, { gap = 4, rowGap = 4, rowH = TAB_H })
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
