----------------------------------------------------------------------
-- Guild OS - Guild Hub + DKP panels
-- Brings the community/loot features into the main window as real tabs
-- instead of slash-only popups:
--   * Guild hub: Activity feed, Bulletin board, Polls (sub-tabs)
--   * DKP: standings + officer controls
-- Renders from the module data APIs (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 70    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab
-- Every sub-tab lays out on the same grid (#371): content flush with the sub-tab bar's left edge,
-- its first line GAP under the sub-panel's top, blocks GAP apart, and a later section title with
-- room over it for its rule.
local GAP = UI.GAP
local SECTION_SPACE = 20   -- over a later UI:CreateSectionTitle: its rule sits 12px above it
local FIELD_H = 24         -- a one-line field, and the button beside it

----------------------------------------------------------------------
-- Shared builders
----------------------------------------------------------------------
-- A scroll list filling the panel under `top`: a region it hangs GAP below, or an offset from the
-- panel's top (GAP by default). Its child keeps the list's width, less the scroll bar's gutter, and
-- every row hangs from both top corners, so a tab built hidden (0 wide) still lays out (#371).
local function makeScroll(panel, name, top)
    local holder = CreateFrame("Frame", nil, panel)
    if type(top) == "table" then
        holder:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -GAP)
    else
        holder:SetPoint("TOPLEFT", 0, -(top or GAP))
    end
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, child = UI:CreateScrollFrame(holder, name)
    scroll:SetAllPoints()
    UI:BindScrollChildWidth(scroll, child)
    return holder, child
end

local function clear(child)
    for _, c in pairs({ child:GetChildren() }) do c:Hide() end
    for _, r in pairs({ child:GetRegions() }) do r:Hide() end
end

----------------------------------------------------------------------
-- ACTIVITY sub-panel: recent guild activity (last 7 days)
----------------------------------------------------------------------
local function BuildActivitySub(panel)
    local hint = UI:CreateText(panel, L["What's happened in the guild lately."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    hint:SetPoint("TOPLEFT", 0, -GAP)
    local _, child = makeScroll(panel, "GuildOSHubActivityScroll", hint)

    return function()
        clear(child)
        local lines = {}
        if GuildOS.Digest then
            local since = GetServerTime() - 7 * 86400
            lines = GuildOS.Digest:Build(since)
        end
        local y = 0
        -- One line per thing that happened, as a plain list: no gold bullet before it (#371).
        for _, line in ipairs(lines) do
            local fs = UI:CreateText(child, line, 12, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 0, -y)
            fs:SetPoint("TOPRIGHT", 0, -y)
            fs:SetJustifyH("LEFT")
            y = y + math.max(20, (fs:GetStringHeight() or 14) + GAP)
        end
        if #lines == 0 then
            local empty = UI:CreateText(child, L["Nothing new in the last 7 days."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end
end

----------------------------------------------------------------------
-- BULLETIN sub-panel
----------------------------------------------------------------------
-- The polls, drawn on the board under the notices (audit B24): what a poll is, a kind of notice.
local function pollKey(name)
    local short = (name or ""):match("^([^-]+)") or name
    return GuildOS:GetPlayerKey(short, GetRealmName())
end

local function drawPolls(child, y)
    local polls = (GuildOS.Polls and GuildOS.Polls:GetSorted()) or {}
    local isOfficer = GuildOS:IsOfficer()
    local myKey = pollKey(GuildOS.Compat.PlayerName())
    for _, p in ipairs(polls) do
        -- The question in the text colour, a closed one in the soft one (#371).
        local qc = p.closed and C.textSoft or C.text
        local q = UI:CreateText(child, (p.closed and "[" .. L["closed"] .. "] " or "") .. p.question, 12, qc.r, qc.g, qc.b)
        local closable = isOfficer and not p.closed
        q:SetPoint("TOPLEFT", 0, -y)
        q:SetPoint("TOPRIGHT", closable and -(56 + GAP) or 0, -y)
        q:SetJustifyH("LEFT")
        if closable then
            local closeBtn = UI:CreateButton(child, L["Close"], 56, 18)
            closeBtn:SetPoint("TOPRIGHT", 0, -y)
            local id = p.id
            closeBtn:SetScript("OnClick", function() if GuildOS.Polls then GuildOS.Polls:Close(id) end end)
        end
        y = y + math.max(18, (q:GetStringHeight() or 14) + 4)

        local total, counts = 0, {}
        for _, opt in pairs(p.votes or {}) do counts[opt] = (counts[opt] or 0) + 1; total = total + 1 end
        local myVote = p.votes and p.votes[myKey]
        for idx, optText in ipairs(p.options or {}) do
            local n = counts[idx] or 0
            local pct = total > 0 and math.floor(n / total * 100 + 0.5) or 0
            local btn = UI:CreateButton(child, string.format("%s  (%d · %d%%)", optText, n, pct), 1, 20)
            btn:SetPoint("TOPLEFT", 0, -y)
            btn:SetPoint("TOPRIGHT", 0, -y)
            -- My vote is the selected option, as every selection is marked (#371).
            UI:SetSelected(btn, myVote == idx)
            btn.label:ClearAllPoints()
            btn.label:SetPoint("LEFT", 8, 0)
            if not p.closed then
                local id, oi = p.id, idx
                btn:SetScript("OnClick", function() if GuildOS.Polls then GuildOS.Polls:Vote(id, oi) end end)
            end
            y = y + 22
        end
        local meta = UI:CreateText(child, string.format(L["%d vote(s) · by %s"], total, p.author or "?"),
            11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        meta:SetPoint("TOPLEFT", 0, -y)
        y = y + 22
    end
    return y, #polls
end

local function BuildBulletinSub(panel)
    local listTop = GAP
    local box, pollForm
    if GuildOS:IsOfficer() then
        -- One field, so one label beside it, then its buttons (#371). A poll is the other kind of post.
        local label = UI:CreateText(panel, L["Notice:"], 12)
        local postBtn = UI:CreateButton(panel, L["Post"], 84, FIELD_H)
        local pollBtn = UI:CreateButton(panel, L["New poll"], 96, FIELD_H)
        -- How long the notice lasts (issue #418): some days, or until an officer removes it.
        local lasts = UI:CreateDropdown(panel, 120, FIELD_H)
        lasts:SetOptions(GuildOS.Bulletin and GuildOS.Bulletin:DurationOptions() or {})
        lasts:SetValue(0)
        panel.lasts = lasts
        box = UI:CreateInput(panel, 0, FIELD_H, { max = 200 })
        box:SetPoint("TOPLEFT", math.ceil(label:GetStringWidth() or 0) + GAP, -GAP)
        box:SetPoint("TOPRIGHT", -(GAP + UI.ReserveFor(postBtn, GAP) + UI.ReserveFor(lasts, GAP)
            + UI.ReserveFor(pollBtn, GAP)), -GAP)
        label:SetPoint("RIGHT", box, "LEFT", -GAP, 0)
        lasts:SetPoint("LEFT", box, "RIGHT", GAP, 0)
        postBtn:SetPoint("LEFT", lasts, "RIGHT", GAP, 0)
        pollBtn:SetPoint("LEFT", postBtn, "RIGHT", GAP, 0)
        local function doPost()
            if GuildOS.Bulletin then GuildOS.Bulletin:Post(box:GetText(), lasts:GetValue()) end
            box:SetText(""); box:ClearFocus()
        end
        box:SetScript("OnEnterPressed", doPost)
        postBtn:SetScript("OnClick", doPost)
        listTop = GAP + FIELD_H + GAP

        -- The poll's fields, under the notice's while "New poll" holds them open. The question says
        -- what it is while empty; the options box is three lines tall with its hint right under it (#371).
        pollForm = CreateFrame("Frame", nil, panel)
        pollForm:SetPoint("TOPLEFT", 0, -listTop)
        pollForm:SetPoint("TOPRIGHT", 0, -listTop)
        pollForm:SetHeight(FIELD_H + GAP + 56 + 4 + 14)
        pollForm:Hide()
        local createBtn = UI:CreateButton(pollForm, L["Create Poll"], 110, FIELD_H)
        local qBox = UI:CreateInput(pollForm, 0, FIELD_H, { max = 150, placeholder = L["Question..."] })
        qBox:SetPoint("TOPLEFT", 0, 0)
        qBox:SetPoint("TOPRIGHT", -(GAP + UI.ReserveFor(createBtn, GAP)), 0)
        createBtn:SetPoint("LEFT", qBox, "RIGHT", GAP, 0)
        local oArea = UI:CreateTextArea(pollForm, 0, 56)   -- a multi-line EditBox alone shrinks to one line
        oArea:SetPoint("TOPLEFT", qBox, "BOTTOMLEFT", 0, -GAP)
        oArea:SetPoint("TOPRIGHT", createBtn, "BOTTOMRIGHT", 0, -GAP)
        local oBox = oArea.edit
        local hint = UI:CreateText(pollForm, L["One option per line (2-6)"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        hint:SetPoint("TOPLEFT", oArea, "BOTTOMLEFT", 0, -4)
        pollForm.create = function()
            local opts = {}
            for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                local t = strtrim(line)
                if t ~= "" and #opts < 6 then opts[#opts + 1] = t end
            end
            if GuildOS.Polls then GuildOS.Polls:Create(qBox:GetText(), opts) end
            qBox:SetText(""); oBox:SetText(""); qBox:ClearFocus(); oBox:ClearFocus()
        end
        pollForm.button, pollForm.createBtn = pollBtn, createBtn
    end
    local holder, child = makeScroll(panel, "GuildOSHubBulletinScroll", listTop)
    local function place()
        local open = pollForm and pollForm:IsShown()
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", 0, -(listTop + (open and (pollForm:GetHeight() + GAP) or 0)))
        holder:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    if pollForm then
        pollForm.button:SetScript("OnClick", function()
            if pollForm:IsShown() then pollForm:Hide() else pollForm:Show() end
            place()
        end)
        pollForm.createBtn:SetScript("OnClick", function() pollForm.create(); pollForm:Hide(); place() end)
    end

    local function refresh()
        clear(child)
        local msgs = (GuildOS.Bulletin and GuildOS.Bulletin:Listed()) or {}
        local isOfficer = GuildOS:IsOfficer()
        local y = 0
        for _, m in ipairs(msgs) do
            local textFS = UI:CreateText(child, m.text, 12, C.text.r, C.text.g, C.text.b)
            textFS:SetPoint("TOPLEFT", 0, -y)
            textFS:SetPoint("TOPRIGHT", isOfficer and -(22 + GAP) or 0, -y)
            textFS:SetJustifyH("LEFT")
            local th = textFS:GetStringHeight() or 14
            local meta = UI:CreateText(child, GuildOS.Bulletin.MetaText(m),
                11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            meta:SetPoint("TOPLEFT", 0, -(y + th + 2))
            if isOfficer then
                local del = UI:CreateButton(child, "\195\151", 22, 18)
                del:SetPoint("TOPRIGHT", 0, -y)
                local id = m.id
                del:SetScript("OnClick", function() if GuildOS.Bulletin then GuildOS.Bulletin:Remove(id) end end)
            end
            y = y + th + 22
        end
        local polls
        y, polls = drawPolls(child, y)
        if #msgs == 0 and polls == 0 then
            local empty = UI:CreateText(child, L["No notices yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end
    if GuildOS.Bulletin then GuildOS.Bulletin.uiRefresh = refresh end
    if GuildOS.Polls then GuildOS.Polls.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- RULES sub-panel (issue #407): the guild's rules for everybody to read; the officers write them here.
----------------------------------------------------------------------
local RULE_WHY = {
    officer = L["|cffFF4444Officers only.|r"],
    empty = L["A rule needs a title."],
    full = L["The list is full."],
    missing = L["That rule is gone."],
}

local function BuildGuildRulesSub(panel)
    local GR = GuildOS.GuildRules
    local listTop = GAP
    local editing   -- the number of the rule the form rewrites, nil while it adds one
    local titleBox, textBox, saveBtn, cancelBtn, result
    if GuildOS:IsOfficer() and GR then
        -- Two fields, title then text, each with its label beside it (#371), then the buttons.
        local tLabel = UI:CreateText(panel, L["Title:"], 12)
        titleBox = UI:CreateInput(panel, 0, FIELD_H, { max = GR.TITLE_MAX })
        local xLabel = UI:CreateText(panel, L["Text:"], 12)
        textBox = UI:CreateInput(panel, 0, FIELD_H, { max = GR.TEXT_MAX })
        local labelW = math.ceil(math.max(tLabel:GetStringWidth() or 0, xLabel:GetStringWidth() or 0)) + GAP
        titleBox:SetPoint("TOPLEFT", labelW, -GAP)
        titleBox:SetPoint("TOPRIGHT", 0, -GAP)
        tLabel:SetPoint("RIGHT", titleBox, "LEFT", -GAP, 0)
        textBox:SetPoint("TOPLEFT", labelW, -(2 * GAP + FIELD_H))
        textBox:SetPoint("TOPRIGHT", 0, -(2 * GAP + FIELD_H))
        xLabel:SetPoint("RIGHT", textBox, "LEFT", -GAP, 0)
        saveBtn = UI:CreateButton(panel, L["Add rule"], 120, FIELD_H)
        saveBtn:SetPoint("TOPLEFT", labelW, -(3 * GAP + 2 * FIELD_H))
        cancelBtn = UI:CreateButton(panel, L["Cancel"], 90, FIELD_H)
        cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", GAP, 0)
        cancelBtn:Hide()
        result = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        result:SetPoint("LEFT", cancelBtn, "RIGHT", GAP, 0)
        local function stopEditing()
            editing = nil
            titleBox:SetText(""); textBox:SetText("")
            titleBox:ClearFocus(); textBox:ClearFocus()
            saveBtn.label:SetText(L["Add rule"])
            cancelBtn:Hide()
        end
        panel.stopEditing = stopEditing
        local function doSave()
            local ok, why
            if editing then
                ok, why = GR:Update(editing, titleBox:GetText(), textBox:GetText())
            else
                ok, why = GR:Add(titleBox:GetText(), textBox:GetText())
            end
            if ok then
                stopEditing()
                result:SetText(L["Saved. The guild gets it now."])
            else
                result:SetText(RULE_WHY[why] or RULE_WHY.empty)
            end
        end
        saveBtn:SetScript("OnClick", doSave)
        textBox:SetScript("OnEnterPressed", doSave)
        cancelBtn:SetScript("OnClick", stopEditing)
        panel.editRule = function(n)
            local r = GR:Rule(n)
            if not r then return end
            editing = n
            titleBox:SetText(r.title); textBox:SetText(r.text or "")
            saveBtn.label:SetText(L["Save rule"])
            cancelBtn:Show()
        end
        listTop = 4 * GAP + 3 * FIELD_H
    end
    local _, child = makeScroll(panel, "GuildOSHubRulesScroll", listTop)

    -- One frame per rule, made once and refilled (at most GR.RULES_MAX).
    local rows = {}
    local function rowAt(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, child)
        row.title = UI:CreateText(row, "", 13, C.text.r, C.text.g, C.text.b)
        row.title:SetPoint("TOPLEFT", 0, 0)
        row.title:SetJustifyH("LEFT")
        row.text = UI:CreateText(row, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.text:SetJustifyH("LEFT")
        if panel.editRule then
            row.del = UI:CreateButton(row, "\195\151", 22, 18)   -- ×
            row.del:SetPoint("TOPRIGHT", 0, 0)
            row.del:SetScript("OnClick", function() GR:Remove(row.n); if panel.stopEditing then panel.stopEditing() end end)
            row.up = UI:CreateButton(row, "\226\134\145", 22, 18)   -- ↑
            row.up:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
            row.up:SetScript("OnClick", function() GR:MoveUp(row.n); if panel.stopEditing then panel.stopEditing() end end)
            row.edit = UI:CreateButton(row, L["Edit"], 60, 18)
            row.edit:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
            row.edit:SetScript("OnClick", function() panel.editRule(row.n) end)
            row.title:SetPoint("TOPRIGHT", -(22 + 4 + 22 + 4 + 60 + GAP), 0)
        else
            row.title:SetPoint("TOPRIGHT", 0, 0)
        end
        row.text:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -2)
        rows[i] = row
        return row
    end
    local empty = UI:CreateText(child, L["The guild has not written its rules yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, 0)

    local function refresh()
        local rules = GR and GR:Get() or {}
        local y = 0
        for i, r in ipairs(rules) do
            local row = rowAt(i)
            row.n = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row.title:SetText(string.format("%d. %s", i, r.title))
            row.text:SetText(r.text or "")
            if row.up then row.up:SetShown(i > 1) end
            local h = (row.title:GetStringHeight() or 14) + 2 + ((r.text ~= "" and row.text:GetStringHeight()) or 0)
            row:SetHeight(math.max(18, h))
            row:Show()
            y = y + math.max(18, h) + GAP
        end
        for i = #rules + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#rules == 0)
        child:SetHeight(math.max(1, y))
    end
    if GR then GR.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- CALL TO ARMS sub-panel (issue #108): officers send, everyone sees the
-- recent calls, answers them and sets how they want to be told.
----------------------------------------------------------------------
local function BuildCallToArmsSub(panel)
    local CTA = GuildOS.CallToArms
    local selected = "worldboss"
    -- { row frame, its widgets, line height }: wrapped again on every resize. A row grows to the
    -- lines it took, and what hangs below it moves down with it.
    local rows = {}
    local above             -- the last section placed; the next one hangs below it

    local function reflow()
        -- As wide as the content: flush left, GAP short of the right edge (#371).
        local w = (panel:GetWidth() or 0) - GAP
        if w < 200 then w = 600 end   -- not laid out yet: OnSizeChanged wraps it again
        for _, r in ipairs(rows) do
            r[1]:SetWidth(w)
            UI:FlowBar(r[1], r[2], { gap = 4, rowGap = 4, rowH = r[3] })
        end
    end
    panel:SetScript("OnSizeChanged", reflow)

    if GuildOS:IsOfficer() then
        local head = UI:CreateSectionTitle(panel, L["Send a call"], true)
        head:SetPoint("TOPLEFT", 0, -GAP)
        local tplRow, cells = CreateFrame("Frame", nil, panel), {}
        tplRow:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -GAP)
        rows[#rows + 1] = { tplRow, cells, 22 }

        local sendBtn = UI:CreateButton(panel, L["Send"], 88, FIELD_H)
        -- Left empty, the call carries the template's own message: the hint says so (#371).
        local msgBox = UI:CreateInput(panel, 0, FIELD_H, { placeholder = L["Message (optional)"] })
        msgBox:SetPoint("TOPLEFT", tplRow, "BOTTOMLEFT", 0, -GAP)
        -- The row is as wide as the content; the box leaves the button its room.
        msgBox:SetPoint("TOPRIGHT", tplRow, "BOTTOMRIGHT", -UI.ReserveFor(sendBtn, GAP), -GAP)
        msgBox:SetMaxBytes(CTA.TEXT_MAX + 1)   -- the call is cut at bytes, not letters: Cyrillic is two each
        local function send()
            if CTA:Send(selected, msgBox:GetText()) then msgBox:ClearFocus() end
        end
        sendBtn:SetPoint("LEFT", msgBox, "RIGHT", GAP, 0)
        sendBtn:SetScript("OnClick", send)
        msgBox:SetScript("OnEnterPressed", send)   -- a key press is a hardware event, as a click is

        -- The chosen template is marked as every selection is, gold border and label, not with a
        -- ">" before its name (#371).
        local function paintSelected()
            for _, cell in ipairs(cells) do
                UI:SetSelected(cell.btn, cell.id == selected)
                cell:SetWidth(cell.btn:GetWidth() + (cell.del and 19 or 0))
            end
            reflow()
        end
        -- Built again only when the list changes; picking one only marks it.
        local function buildTemplates()
            for i = #cells, 1, -1 do cells[i]:Hide(); cells[i] = nil end
            for _, t in ipairs(CTA:Templates()) do
                local cell = CreateFrame("Frame", nil, tplRow)
                cell:SetHeight(22)
                cell.id = t.id
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

        -- A template's name is the title its calls go out under.
        local nameBox = UI:CreateInput(panel, 160, FIELD_H, { placeholder = L["Title"] })
        nameBox:SetPoint("TOPLEFT", msgBox, "BOTTOMLEFT", 0, -GAP)
        nameBox:SetMaxBytes(CTA.NAME_MAX + 1)
        local saveBtn = UI:CreateButton(panel, L["Save as template"], 130, FIELD_H)
        saveBtn:SetPoint("LEFT", nameBox, "RIGHT", GAP, 0)
        saveBtn:SetScript("OnClick", function()
            local tpl = CTA:Template(selected)
            local ok, why = CTA:SaveTemplate(nameBox:GetText(), msgBox:GetText(), tpl and tpl.kind)
            if not ok then GuildOS:Print(why) return end
            nameBox:SetText("")
            buildTemplates()
        end)
        local chatCb = UI:CreateCheckbox(panel, L["Also post in guild chat"], 16)
        chatCb:SetPoint("LEFT", saveBtn, "RIGHT", 12, 0)
        chatCb.checkbox:SetChecked(CTA:ChatOn())
        chatCb.checkbox.onChanged = function(_, checked) GuildOS:SetSetting("ctaChat", checked and true or false) end
        above = nameBox

        buildTemplates()
        msgBox:SetText(CTA:Template(selected).text)
    end

    -- Everyone: how a call reaches me. A row of what to do with a call, then the types to hear.
    local mine = UI:CreateSectionTitle(panel, L["My alerts"], above == nil)
    if above then mine:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_SPACE) else mine:SetPoint("TOPLEFT", 0, -GAP) end
    local function checkRow(anchor, items)
        local row = CreateFrame("Frame", nil, panel)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -GAP)
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
    local function setting(key) return function(v) GuildOS:SetSetting(key, v) end end
    local how = checkRow(mine, {
        { L["Show popups"], function() return CTA:PopupsOn() end, setting("ctaPopups") },
        { L["Play a sound"], function() return CTA:SoundOn() end, setting("ctaSound") },
        { L["Quiet in instances and combat"], function() return CTA:QuietOn() end, setting("ctaQuiet") },
    })
    local kinds = {}
    for _, k in ipairs(CTA.KINDS) do
        local id = k.id
        kinds[#kinds + 1] = { k.title, function() return not CTA:Muted(id) end,
                              function(v) GuildOS:SetSetting("ctaMute_" .. id, not v) end }
    end
    local hear = checkRow(how, kinds)

    local recentHead = UI:CreateSectionTitle(panel, L["Recent calls"])
    recentHead:SetPoint("TOPLEFT", hear, "BOTTOMLEFT", 0, -SECTION_SPACE)
    -- /gos avail: who in the guild is free for a group, and listing yourself (#142).
    if GuildOS.LFGBoard then
        local boardBtn = UI:CreateButton(panel, L["Groups"], 180, 18)
        boardBtn:SetPoint("LEFT", recentHead, "RIGHT", 12, 0)
        boardBtn:SetScript("OnClick", function() GuildOS.LFGBoard:Show() end)
    end
    local _, child = makeScroll(panel, "GuildOSHubCTAScroll", recentHead)
    reflow()

    -- The recent calls, one pooled line each (there are never more than CTA.KEEP): an answer
    -- arriving repaints them in place rather than drawing them all again.
    local lines = {}
    local empty = UI:CreateText(child, L["No calls yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, 0)
    local function lineAt(i)
        if lines[i] then return lines[i] end
        local ln = {}
        ln.text = UI:CreateText(child, "", 12, C.text.r, C.text.g, C.text.b)
        ln.text:SetJustifyH("LEFT")
        ln.meta = UI:CreateText(child, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        ln.go = UI:CreateButton(child, L["On my way"], 90, 18)
        ln.go:SetScript("OnClick", function() CTA:Answer(ln.id) end)
        lines[i] = ln
        return ln
    end

    local function refresh()
        reflow()
        local now, y = GetServerTime(), 0
        for i, e in ipairs(CTA.recent) do
            local ln = lineAt(i)
            ln.id = e.id
            -- Anybody who has not answered can, from here too: with popups off, in quiet mode
            -- or after dismissing one, this is the only place to.
            local open = not e.mine and not e.answered and now - (tonumber(e.ts) or 0) <= CTA.MAX_AGE
            ln.go:SetShown(open)
            ln.go:ClearAllPoints()
            ln.go:SetPoint("TOPRIGHT", 0, -y)
            -- The call's title is a name, in the text colour as every name (#371); the line wraps
            -- short of the button when there is one.
            ln.text:SetText(string.format("%s  %s", e.title or "", e.text or ""))
            ln.text:ClearAllPoints()
            ln.text:SetPoint("TOPLEFT", 0, -y)
            if open then
                ln.text:SetPoint("TOPRIGHT", ln.go, "TOPLEFT", -GAP, 0)
            else
                ln.text:SetPoint("TOPRIGHT", 0, -y)
            end
            ln.text:Show()
            local th = ln.text:GetStringHeight() or 14
            local n = CTA:GoingCount(e)
            ln.meta:SetText(string.format("%s · %s · %s", e.zone or "",
                (Ambiguate and Ambiguate(e.sender or "", "short")) or (e.sender or ""),
                n > 0 and string.format(L["%d on the way"], n) or date("%H:%M", e.at or 0)))
            ln.meta:ClearAllPoints()
            ln.meta:SetPoint("TOPLEFT", 0, -(y + th + 2))
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
-- Guild chat feed (issues #124, #126), kept by Modules/GuildChat.lua. Laid out
-- like the alliance feed: one card per run of lines from one speaker, newest at
-- the bottom, a box underneath, and a tab per channel of the guild. Guild > Chat
-- and the Now cards both build it.
----------------------------------------------------------------------
local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
local feeds = 0   -- each feed's scroll frame needs its own global name

-- A channel is { id, name, kind }; nil, and the Guild tab, mean /g.
local function idOf(stream)
    return (stream and stream.kind ~= "guild") and stream.id or nil
end

local function streamLabel(stream)
    if stream.kind == "guild" then return L["Guild"] end
    if stream.kind == "officer" then return L["Officers"] end
    return stream.name or "?"
end

-- `top`: room over the feed. The Guild tab leaves GAP under its sub-tab bar, as on every sub-tab
-- (#371); a Now card gives none.
function GuildOS:CreateGuildChatFeed(panel, top)
    local GC = GuildOS.GuildChat
    local current   -- the channel open; nil is /g
    top = top or 0
    feeds = feeds + 1

    -- The channel tabs, shown only when there is more than /g to choose from.
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 0, -top)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)
    bar:Hide()
    local tabs = {}

    local holder = CreateFrame("Frame", nil, panel)
    local function anchorHolder(belowTabs)
        holder:ClearAllPoints()
        if belowTabs then
            holder:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
        else
            holder:SetPoint("TOPLEFT", 0, -top)
        end
        holder:SetPoint("BOTTOMRIGHT", 0, 32)
    end
    anchorHolder(false)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSGuildChatScroll" .. feeds)
    scroll:SetAllPoints()

    local input = UI:CreateInput(panel, 100, FIELD_H)
    input:SetPoint("BOTTOMLEFT", 0, 4)
    input:SetPoint("BOTTOMRIGHT", -70, 4)
    input:SetMaxBytes(241)   -- what Send keeps (240 bytes), plus the terminator
    local sendBtn = UI:CreateButton(panel, L["Send"], 62, FIELD_H)
    sendBtn:SetPoint("BOTTOMRIGHT", 0, 4)

    local empty = UI:CreateText(content, L["No guild chat yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    local refresh   -- declared for the tab clicks
    -- The newest line is shown on opening and on changing channel; after that the feed follows
    -- new lines only for a reader already at the bottom, never pulling one who scrolled up.
    local pinBottom = true
    local scrolling = false   -- a move to the bottom is queued for the next frame
    local waiting = false     -- a look after a chat lockdown is queued

    -- Another channel: the server stops being told about the old one, and is told about this one.
    local function open(stream)
        -- In a chat lockdown the feed cannot be redrawn: a channel changed then would send Enter
        -- somewhere other than what is on screen, an officer's line to the whole guild.
        if GC:Locked() or idOf(stream) == idOf(current) then return end
        GC:Watch(false, current)
        current = idOf(stream) and stream or nil
        GC:Watch(true, current)
        pinBottom = true
        refresh()
    end

    local function layoutTabs()
        local streams = GC:Streams()
        local list = (streams and #streams > 1) and streams or nil
        -- The channel open is gone (removed, or no longer listed to this player): back to /g.
        if current then
            local still
            for _, s in ipairs(list or {}) do
                if s.id == current.id then still = s end
            end
            if not still then
                -- Hidden, the feed already stopped watching it.
                local watched = panel:IsVisible()
                if watched then GC:Watch(false, current) end
                current = nil
                if watched then GC:Watch(true, nil) end
            end
        end
        bar:SetShown(list ~= nil)
        anchorHolder(list ~= nil)
        if not list then return end
        local shown = {}
        for i, s in ipairs(list) do
            local t = tabs[i]
            if not t then
                t = UI:CreateTab(bar, "", TAB_MIN_W, true)
                t:SetScript("OnClick", function(self) open(self.stream) end)
                tabs[i] = t
            end
            t.stream = s
            t.label:SetText(streamLabel(s))
            t:SetWidth(math.max(TAB_MIN_W, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
            t:SetActive(idOf(s) == idOf(current))
            t:Show()
            shown[#shown + 1] = t
        end
        for i = #list + 1, #tabs do tabs[i]:Hide() end
        bar:SetWidth(math.max(TAB_MIN_W, panel:GetWidth() or 0))
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = TAB_H })
    end

    -- Pooled: refresh runs on every line of chat, and WoW never frees a frame.
    local blocks = {}
    local function getBlock(i)
        if blocks[i] then return blocks[i] end
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(card) })
        -- A link in the line opens as it does in the chat frame.
        card:EnableMouse(true)
        card:SetHyperlinksEnabled(true)
        card:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 8, -6)
        icon:SetTexture(CLASS_TEX)
        local nameFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        nameFS:SetPoint("TOPLEFT", 36, -7)
        local timeFS = UI:CreateText(card, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        timeFS:SetPoint("TOPRIGHT", -8, -8)
        local bodyFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        bodyFS:SetPoint("TOPLEFT", 36, -22)
        bodyFS:SetJustifyH("LEFT")
        bodyFS:SetWordWrap(true)
        blocks[i] = { card = card, icon = icon, nameFS = nameFS, timeFS = timeFS, bodyFS = bodyFS }
        return blocks[i]
    end

    refresh = function()
        -- In a chat lockdown the server's lines and channels arrive secret: keep what is drawn,
        -- and look again every 2 seconds while on screen, since no event says the lockdown lifted.
        if GC:Locked() then
            if not waiting then
                waiting = true
                GuildOS.Compat.After(2, function()
                    waiting = false
                    if panel:IsVisible() then refresh() end
                end)
            end
            return
        end
        local follow = pinBottom or scrolling or scroll:GetVerticalScroll() >= scroll:GetVerticalScrollRange() - 4
        pinBottom = false
        layoutTabs()
        -- Born 0 wide (CreateScrollFrame sizes it before layout), so re-set on every draw.
        content:SetWidth(math.max(holder:GetWidth() - 12, 1))
        local log = GC:Entries(current)
        local classOf = {}
        for _, e in ipairs(log) do classOf[e.n] = e.c or classOf[e.n] end
        local groups = GuildOS.AllianceChat.GroupLog(log, GuildOS.AllianceChat.GROUP_WINDOW)
        local today = date("%Y%m%d", GetServerTime())
        local width = math.max(content:GetWidth() - 12, 200)
        local y = 0
        for i, g in ipairs(groups) do
            local b = getBlock(i)
            local class = classOf[g.name]
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
            if coords then
                b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                b.icon:Show()
            else
                b.icon:Hide()
            end
            -- A line from an allied guild (issue #344) says which one, in its colour.
            local who = g.name or "?"
            if g.guild and GuildOS.Alliance then
                who = "|cff" .. GuildOS.Alliance.GuildColorHex(g.guild) .. "[" .. g.guild .. "]|r " .. who
            end
            b.nameFS:SetText(who)
            b.nameFS:SetTextColor(GuildOS:GetClassColor(class))
            -- The log outlives the session: a line from another day says which day.
            local t = tonumber(g.t)
            b.timeFS:SetText(t and GuildOS:LocalDate(date("%Y%m%d", t) == today and "%H:%M" or "%a %H:%M", t) or "")
            b.bodyFS:SetWidth(width - 44)
            b.bodyFS:SetText(table.concat(g.lines, "\n"))
            local h = math.max(34, (b.bodyFS:GetStringHeight() or 12) + 28)
            b.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.55)
            b.card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.35)
            b.card:SetPoint("TOPLEFT", 0, -y)
            b.card:SetSize(width, h)
            b.card:Show()
            y = y + h + 3
        end
        for i = #groups + 1, #blocks do blocks[i].card:Hide() end
        empty:SetShown(#groups == 0)
        if #groups == 0 then y = 20 end
        content:SetHeight(math.max(y, 1))
        -- A frame later: the scroll range follows the new height only after it lands.
        if not follow then return end
        local target = math.max(0, y - holder:GetHeight())
        scrolling = true
        GuildOS.Compat.After(0, function()
            scrolling = false
            if panel:IsVisible() then scroll:SetVerticalScroll(target) end
        end)
    end

    -- Enter and the click are the player's own key press, which chat needs on Forever.
    local function doSend()
        local ok, why = GC:Send(input:GetText(), current)
        if ok then
            input:SetText("")
        elseif why == "locked" then
            GuildOS:Print(L["Chat is locked right now: your message is still in the box."])
        end
    end
    sendBtn:SetScript("OnClick", doSend)
    input:SetScript("OnEnterPressed", doSend)

    GC:OnRefresh(function()
        if panel:IsVisible() then refresh() end
    end)
    -- The server is told a channel is being read only while the feed is on screen.
    panel:HookScript("OnShow", function() pinBottom = true; GC:Watch(true, current) end)
    panel:HookScript("OnHide", function() GC:Watch(false, current) end)
    -- The cards are as wide as the view: a resized window lays them out again, once a frame.
    UI:MakeResponsive(holder, function()
        if panel:IsVisible() then refresh() end
    end)
    return refresh
end

----------------------------------------------------------------------
-- Guild Hub assembly (sub-tab bar mirrors the Audit panel)
----------------------------------------------------------------------
-- `feature`: offered only while that feature may open here (UI:IsFeatureAllowed: present on this
-- client, switched on, started), and built the first time it opens. The Journal and Achievements
-- tabs became the last two (issue #367); both are WoW: Forever's. Achievements leads the bar and is
-- where Guild opens wherever it is offered (#373); elsewhere Guild opens on Calendar.
local HUB_SUBTABS = {
    { key = "achievements", label = L["Achievements"], feature = "achievements" },
    { key = "calendar", label = L["Calendar"] },
    { key = "activity", label = L["Activity"] },
    { key = "bulletin", label = L["Bulletin"] },
    { key = "rules",    label = L["Rules"] },
    { key = "cta",      label = L["Call to Arms"] },
    { key = "chat",     label = L["Chat"] },
    { key = "journal",      label = L["Journal"],      feature = "journal" },
}

-- `failed`: this hub's lazy sub-tabs whose builder errored (issue #367), refused for the session.
local function hubOffers(key, failed)
    if failed and failed[key] then return false end
    for _, t in ipairs(HUB_SUBTABS) do
        if t.key == key then return not t.feature or UI:IsFeatureAllowed(UI:GetFeature(t.feature)) end
    end
    return false
end

-- Where Guild opens: Achievements where this client has it and it started, else Calendar (#373).
local function hubDefault(failed)
    return hubOffers("achievements", failed) and "achievements" or "calendar"
end

function GuildOS:CreateGuildHub(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = hubDefault()

    -- Anchored on the left only: UI:FlowBar reads GetWidth to wrap, and a frame pinned on both
    -- sides reports a stale width in the frame its container was resized (as ManagementPanel).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)

    local builders = {
        calendar = function(p) return GuildOS:CreateCalendarSub(p) end,
        activity = BuildActivitySub, bulletin = BuildBulletinSub, cta = BuildCallToArmsSub,
        rules = BuildGuildRulesSub,
        chat = function(p) return GuildOS:CreateGuildChatFeed(p, GAP) end,
        journal = function(p) return GuildOS:CreateJournalPanel(p) end,
        achievements = function(p) return GuildOS:CreateAchievementsPanel(p) end,
    }
    local failed = {}
    -- The six built with the tab raise as they did, into the tab's own start-up guard. Journal and
    -- Achievements are built the first time they open: one that errors is recorded, with its stack, and
    -- refused for the session rather than left half built (issue #367).
    local function build(key)
        local info = parent.subPanels[key]
        if not info or info.built then return end
        info.built = true
        local def
        for _, t in ipairs(HUB_SUBTABS) do if t.key == key then def = t end end
        if not (def and def.feature) then
            info.refresh = builders[key](info.panel)
            return
        end
        local ok, res = xpcall(function() return builders[key](info.panel) end, function(e)
            return tostring(e) .. (debugstack and ("\n" .. debugstack(2)) or "")
        end)
        if ok then
            info.refresh = res
        else
            failed[key] = true
            GuildOS:RecordError("Guild hub " .. key .. ": " .. tostring(res))
            GuildOS:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
        end
    end

    local subTabBtns = {}
    -- A sub-tab not offered (switched off, or not on this client) falls back to the calendar, deep
    -- links included.
    local function selectSub(key, filter)
        if not hubOffers(key, failed) then key = hubDefault(failed) end
        build(key)
        if failed[key] then key = hubDefault(failed); build(key) end   -- its builder just errored
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
        -- A deep link's filter goes to the sub-panel that takes one (the calendar: a day).
        if filter ~= nil and info and info.panel.ApplyFilter then GuildOS:SafeCall(info.panel.ApplyFilter, filter) end
    end
    parent.SelectSub = selectSub   -- deep links: /guildos calendar, /gos open journal, the Now tab

    -- A tab is as wide as its label: five at a fixed 120px ran off a narrow window (issue #108).
    for _, t in ipairs(HUB_SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
    end

    -- Flow the offered tabs only, so a sub-tab switched off leaves no gap in the bar (as the
    -- Alliance panel).
    local function layoutTabs()
        local shown = {}
        for _, t in ipairs(HUB_SUBTABS) do
            local btn = subTabBtns[t.key]
            local offered = hubOffers(t.key, failed)
            btn:SetShown(offered)
            if offered then shown[#shown + 1] = btn end
        end
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = TAB_H })
    end
    layoutTabs()

    -- Hung from the bar, so a bar wrapped onto two rows pushes the content down. Flush with the bar on
    -- both sides and right under it: each sub-tab starts its content at x = 0, GAP down (#371), so
    -- every one of them starts at the same place.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        p:SetPoint("BOTTOMRIGHT", -10, 10)
        p:Hide()
        return p
    end

    for _, t in ipairs(HUB_SUBTABS) do
        parent.subPanels[t.key] = { panel = makeSubPanel() }
        if not t.feature then build(t.key) end
    end

    -- A room that opens one of these sub-tabs as its own entry (the Salão's Notices, Raids' Calendar,
    -- specs/salao #445) hides this bar, so the screen never shows two rows of the same tabs: the
    -- sub-panels then start where the bar was.
    for key, info in pairs(parent.subPanels) do
        info.panel:HookScript("OnShow", function() if parent.OnSubChanged then parent.OnSubChanged(key) end end)
    end
    local barShown = true
    function parent.SetSubBarShown(shown)
        shown = shown and true or false
        if shown == barShown then return end
        barShown = shown
        bar:SetShown(shown)
        for _, info in pairs(parent.subPanels) do
            info.panel:ClearAllPoints()
            if shown then
                info.panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
            else
                info.panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -8)
            end
            info.panel:SetPoint("BOTTOMRIGHT", -10, 10)
        end
    end

    parent:SetScript("OnShow", function()
        layoutTabs()
        selectSub(parent.activeSub or hubDefault(failed))
    end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        layoutTabs()
    end)
end

