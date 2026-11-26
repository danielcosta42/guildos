----------------------------------------------------------------------
-- Guild OS - Notes and marks panel (issue #429; Leadership > Notes and marks)
-- Join dates written into the guild notes and read back from them, the safe list, nicknames and the
-- "back after N days offline" line. Visual layout only: the plans, the writes, the marks and the
-- settings are GuildOS.NoteDates', GuildOS.MemberMarks' and GuildOS.MemberHistory's (Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local ROW_H = 22
local NAMES_SHOWN = 8      -- names a confirmation lists before "and N more"

GuildOS.Dialogs["GUILDOS_NOTE_DATE_REPLACE"] = {
    text = "%s",
    button1 = L["Write"], button2 = L["Cancel"],
    OnAccept = function(_, data)
        if GuildOS.NoteDates then GuildOS.NoteDates:ConfirmWrite(data) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

GuildOS.Dialogs["GUILDOS_NOTE_DATE_RUN"] = {
    text = "%s",
    button1 = L["Start"], button2 = L["Cancel"],
    OnAccept = function(_, data)
        if GuildOS.NoteDates then GuildOS.NoteDates:StartAndSay(data, true) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

-- The note to copy where the game does not let an addon write it: the box holds it, selected.
GuildOS.Dialogs["GUILDOS_NOTE_DATE_COPY"] = {
    text = "%s",
    button1 = L["Done"], button2 = L["Close"],
    hasEditBox = true, maxLetters = 0,
    OnShow = function(self, data)
        local box = GuildOS.Compat.PopupEditBox(self)
        if box and data then
            box:SetText(data.text or "")
            box:HighlightText()
            box:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(editBox) editBox:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local HOW_TEXT = { write = L["empty note"], append = L["added after the note"], replace = L["replaces a date: asks"],
                   full = L["no room: cuts the note, asks"] }
local IMPORT_TEXT = { new = L["new"], earlier = L["earlier than GuildOS saw"], same = L["same day"],
                      later = L["later than GuildOS saw: not taken"], kept = L["history has the exact day"] }
local RUN_TEXT = { pending = L["waiting"], done = L["done"], same = L["already there"], copied = L["copied"],
                   skipped = L["skipped"] }

local function hex(c) return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end

local function listNames(items)
    local names = {}
    for i = 1, math.min(NAMES_SHOWN, #items) do names[i] = items[i].name end
    local s = table.concat(names, ", ")
    if #items > NAMES_SHOWN then s = s .. " " .. string.format(L["and %d more"], #items - NAMES_SHOWN) end
    return s
end

function GuildOS:BuildMarksSub(panel)
    local ND, MM, MH = GuildOS.NoteDates, GuildOS.MemberMarks, GuildOS.MemberHistory
    if not (ND and MM and MH) then return nil end
    local mode, plan, planLeft, imports = nil, nil, nil, nil   -- what the list shows: "plan", "import", "safe"
    local refresh

    local function text(parent, s, size, col)
        col = col or C.text
        return UI:CreateText(parent, s, size or 11, col.r, col.g, col.b)
    end

    -- ── Join dates in the notes ───────────────────────────────────────
    local title = UI:CreateSectionTitle(panel, L["JOIN DATES IN NOTES"], true)
    title:SetPoint("TOPLEFT", 0, -2)

    local y = -28
    local noteLbl = text(panel, L["Note"])
    noteLbl:SetPoint("TOPLEFT", 0, y - 4)
    local offBtn = UI:CreateButton(panel, L["Officer"], 70, 22)
    offBtn:SetPoint("LEFT", noteLbl, "RIGHT", 8, 0)
    offBtn:SetScript("OnClick", function() ND:SetTarget("officer"); plan = nil; refresh() end)
    local pubBtn = UI:CreateButton(panel, L["Public"], 70, 22)
    pubBtn:SetPoint("LEFT", offBtn, "RIGHT", 4, 0)
    pubBtn:SetScript("OnClick", function() ND:SetTarget("public"); plan = nil; refresh() end)
    local fmtDD = UI:CreateDropdown(panel, 110, 22)
    fmtDD:SetPoint("LEFT", pubBtn, "RIGHT", 12, 0)
    local fmts = {}
    for _, f in ipairs(ND.FORMATS) do fmts[#fmts + 1] = { value = f, text = f } end
    fmtDD:SetOptions(fmts)
    fmtDD.onSelect = function(_, v) ND:SetFormat(v); plan = nil; refresh() end
    local labelCB = UI:CreateCheckbox(panel, ND.LABEL .. "...", 18)
    labelCB:SetPoint("LEFT", fmtDD, "RIGHT", 12, 0)
    labelCB.checkbox.onChanged = function(_, checked) ND:SetLabel(checked); plan = nil; refresh() end
    local seenCB = UI:CreateCheckbox(panel, L["Also dates GuildOS only saw"], 18)
    seenCB:SetPoint("LEFT", labelCB, "LEFT", 110, 0)
    seenCB.checkbox.onChanged = function(_, checked) ND:SetWithSeen(checked); plan = nil; refresh() end

    y = y - 30
    local nameBox = UI:CreateInput(panel, 150, 22, { max = 60 })
    nameBox:SetPoint("TOPLEFT", 0, y)
    local writeBtn = UI:CreateButton(panel, L["Write date"], 90, 22)
    writeBtn:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    writeBtn:SetScript("OnClick", function() ND:WriteOne(strtrim(nameBox:GetText() or "")); refresh() end)
    nameBox:SetScript("OnEnterPressed", function(s) s:ClearFocus(); ND:WriteOne(strtrim(s:GetText() or "")); refresh() end)
    local planBtn = UI:CreateButton(panel, L["Whole guild"], 100, 22)
    planBtn:SetPoint("LEFT", writeBtn, "RIGHT", 12, 0)
    planBtn:SetScript("OnClick", function() plan, planLeft = ND:Plan(); mode = "plan"; refresh() end)
    local importBtn = UI:CreateButton(panel, L["Read dates from notes"], 150, 22)
    importBtn:SetPoint("LEFT", planBtn, "RIGHT", 12, 0)
    importBtn:SetScript("OnClick", function() imports = ND:ImportPlan(); mode = "import"; refresh() end)
    local orderDD = UI:CreateDropdown(panel, 120, 22)
    orderDD:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)
    orderDD:SetOptions({ { value = "auto", text = L["By language"] }, { value = "dmy", text = L["Day first"] },
                         { value = "mdy", text = L["Month first"] } })
    orderDD.onSelect = function(_, v) ND:SetOrder(v); if mode == "import" then imports = ND:ImportPlan() end; refresh() end

    y = y - 30
    local runFS = text(panel, "", 11, C.textSoft)
    runFS:SetPoint("TOPLEFT", 0, y - 4)
    local stopBtn = UI:CreateButton(panel, L["Stop"], 70, 22)
    stopBtn:SetPoint("TOPRIGHT", 0, y)
    stopBtn:SetScript("OnClick", function() ND:Stop() end)
    local nextBtn = UI:CreateButton(panel, L["Next"], 150, 22)
    nextBtn:SetPoint("RIGHT", stopBtn, "LEFT", -6, 0)
    nextBtn:SetScript("OnClick", function() ND:Next() end)
    local askBtn = UI:CreateButton(panel, L["Rewrite those too"], 140, 22)
    askBtn:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
    local goBtn = UI:CreateButton(panel, L["Start"], 90, 22)
    goBtn:SetPoint("RIGHT", askBtn, "LEFT", -6, 0)
    UI:SetButtonVariant(goBtn, "primary")

    -- ── Safe list, nicknames, returns ─────────────────────────────────
    y = y - 50
    local title2 = UI:CreateSectionTitle(panel, L["SAFE LIST AND NICKNAMES"])
    title2:SetPoint("TOPLEFT", 0, y)
    -- WoW: Forever: the marks stay on this client (audit B11).
    local localOnly = GuildOS:LocalOnlyText()
    if localOnly then
        local lo = text(panel, localOnly, 10, C.silver)
        lo:SetPoint("TOPLEFT", 0, y - 16)
        y = y - 14
    end
    y = y - 26
    local tagLbl = text(panel, L["Safe tag in notes"])
    tagLbl:SetPoint("TOPLEFT", 0, y - 4)
    local tagBox = UI:CreateInput(panel, 80, 22, { max = MM.TAG_MAX })
    tagBox:SetPoint("LEFT", tagLbl, "RIGHT", 8, 0)
    local function saveTag() MM:SetSafeTag(tagBox:GetText() or ""); tagBox:ClearFocus(); refresh() end
    tagBox:SetScript("OnEnterPressed", saveTag)
    local tagSave = UI:CreateButton(panel, L["Save"], 60, 22)
    tagSave:SetPoint("LEFT", tagBox, "RIGHT", 4, 0)
    tagSave:SetScript("OnClick", saveTag)
    local backLbl = text(panel, L["Tell me who comes back after"])
    backLbl:SetPoint("LEFT", tagSave, "RIGHT", 20, 0)
    local backBox = UI:CreateInput(panel, 44, 22, { numeric = true, max = 3, justify = "CENTER" })
    backBox:SetPoint("LEFT", backLbl, "RIGHT", 8, 0)
    local function saveBack() MH:SetBackDays(tonumber(backBox:GetText() or "") or 0); backBox:ClearFocus(); refresh() end
    backBox:SetScript("OnEnterPressed", saveBack)
    local backDays = text(panel, L["days offline (0: never)"])
    backDays:SetPoint("LEFT", backBox, "RIGHT", 6, 0)
    local backSave = UI:CreateButton(panel, L["Save"], 60, 22)
    backSave:SetPoint("LEFT", backDays, "RIGHT", 6, 0)
    backSave:SetScript("OnClick", saveBack)

    y = y - 30
    local memberBox = UI:CreateInput(panel, 150, 22, { max = 60 })
    memberBox:SetPoint("TOPLEFT", 0, y)
    local safeBtn = UI:CreateButton(panel, L["Safe on / off"], 100, 22)
    safeBtn:SetPoint("LEFT", memberBox, "RIGHT", 6, 0)
    safeBtn:SetScript("OnClick", function() MM:CommandSafe(memberBox:GetText() or ""); mode = "safe"; refresh() end)
    local nickBox = UI:CreateInput(panel, 120, 22, { max = MM.NICK_MAX })
    nickBox:SetPoint("LEFT", safeBtn, "RIGHT", 12, 0)
    local nickBtn = UI:CreateButton(panel, L["Set nickname"], 100, 22)
    nickBtn:SetPoint("LEFT", nickBox, "RIGHT", 6, 0)
    nickBtn:SetScript("OnClick", function()
        MM:CommandNick(strtrim(memberBox:GetText() or "") .. " " .. strtrim(nickBox:GetText() or ""))
        refresh()
    end)
    local safeListBtn = UI:CreateButton(panel, L["Safe list"], 90, 22)
    safeListBtn:SetPoint("LEFT", nickBtn, "RIGHT", 12, 0)
    safeListBtn:SetScript("OnClick", function() mode = "safe"; refresh() end)

    -- ── The list: the plan, the import's review or the safe list ──────
    y = y - 32
    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, y)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local empty = text(listHolder, "", 11, C.silver)
    empty:SetPoint("TOPLEFT", 0, -4)
    local function createRow(parent)
        local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row.a = text(row, "", 11)
        row.a:SetPoint("LEFT", 8, 0)
        row.b = text(row, "", 10, C.silver)
        row.b:SetPoint("LEFT", 170, 0)
        row.c = text(row, "", 10, C.text)
        row.c:SetPoint("LEFT", 390, 0)
        row.d = text(row, "", 10, C.textSoft)
        row.d:SetPoint("RIGHT", -8, 0)
        row:SetScript("OnClick", function(self)
            -- In the import's review a click takes a member in or out (only those it would take).
            local it = self.item
            if mode == "import" and it and (it.status == "new" or it.status == "earlier") then
                it.pick = not it.pick
                refresh()
            end
        end)
        return row
    end
    local function fillRow(row, it, idx)
        local alt = (idx % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        row.item = it
        row.a:SetTextColor(C.text.r, C.text.g, C.text.b)
        if mode == "import" then
            row.a:SetText((it.pick and "|cff" .. hex(C.green) .. "[x]|r " or "[ ] ") .. it.name)
            row.b:SetText(it.note or "")
            row.c:SetText(string.format("%04d-%02d-%02d", it.day.year, it.day.month, it.day.day)
                .. (it.known and ("  /  " .. date("%Y-%m-%d", it.known) .. (it.knownEst and "*" or "")) or ""))
            row.d:SetText(IMPORT_TEXT[it.status] or "")
        elseif mode == "safe" then
            row.a:SetText(it.name)
            row.b:SetText(it.why or "")
            row.c:SetText(it.nick or "")
            row.d:SetText("")
        else
            row.a:SetText(it.name)
            row.b:SetText(it.current ~= "" and it.current or L["(empty)"])
            row.c:SetText("> " .. it.text)
            local col = ND.Silent(it.how) and C.textSoft or C.warn
            row.d:SetTextColor(col.r, col.g, col.b)
            row.d:SetText(it.status and (RUN_TEXT[it.status] or it.status) or (HOW_TEXT[it.how] or ""))
            return
        end
        row.d:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
    end
    local list = UI.MakeVirtualList(listHolder, "GuildOSMgmtMarksScroll", ROW_H + 2, createRow, fillRow)

    -- The safe list as rows: marked by hand, and who has the tag in a note now.
    local function safeRows()
        local out, seen = {}, {}
        for _, k in ipairs(MM:SafeKeys()) do
            seen[k] = true
            out[#out + 1] = { name = k:match("^([^-]+)") or k, why = L["marked by hand"], nick = MM:Nick(k) }
        end
        local tag = MM:SafeTag()
        local onotes = GuildOS.Compat.CanViewOfficerNote()
        for i = 1, GetNumGuildMembers() or 0 do
            local full, _, _, _, _, _, note, onote = GetGuildRosterInfo(i)
            local key = full and GuildOS:KeyOfRosterName(full)
            if key and not seen[key] and MM.NoteHasTag(note, onotes and onote or nil, tag) then
                out[#out + 1] = { name = full:match("^([^-]+)") or full, why = string.format(L["%s in a note"], tag), nick = MM:Nick(key) }
            end
        end
        table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
        return out
    end

    local function silentOf(items)
        local n = 0
        for _, it in ipairs(items or {}) do if ND.Silent(it.how) then n = n + 1 end end
        return n
    end

    goBtn:SetScript("OnClick", function()
        if mode == "import" then
            ND:ApplyImport(imports)
            imports = ND:ImportPlan()
        elseif plan then
            ND:StartAndSay(plan, false)
        end
        refresh()
    end)
    askBtn:SetScript("OnClick", function()
        if not plan then return end
        local asks = {}
        for _, it in ipairs(plan) do if not ND.Silent(it.how) then asks[#asks + 1] = it end end
        if #asks == 0 then return end
        GuildOS:ShowDialog("GUILDOS_NOTE_DATE_RUN", string.format(
            L["%d note(s) lose text or a date they had: %s.\n\nThe list shows each old and new note. Write all of them?"],
            #asks, listNames(asks)), nil, plan)
    end)

    refresh = function()
        local which = ND:Target()
        UI:SetSelected(offBtn, which == "officer")
        UI:SetSelected(pubBtn, which == "public")
        fmtDD:SetValue(ND:FormatId())
        labelCB.checkbox:SetChecked(ND:UseLabel())
        seenCB.checkbox:SetChecked(ND:WithSeen())
        orderDD:SetValue(ND:OrderSetting())
        if not tagBox:HasFocus() then tagBox:SetText(MM:SafeTag()) end
        if not backBox:HasFocus() then backBox:SetText(tostring(MH:BackDays())) end

        local open = ND:TakeOpen()
        if open == "plan" then plan, planLeft = ND:Plan(); mode = "plan"
        elseif open == "import" then imports = ND:ImportPlan(); mode = "import" end

        local run = ND:Run()
        local m = ND:Mode(which)
        nextBtn:SetShown(run ~= nil and m ~= "write" and ND:Current() ~= nil)
        nextBtn.label:SetText(ND:NextLabel())
        stopBtn:SetShown(run ~= nil)
        askBtn:Hide()
        goBtn:Hide()
        if run then
            local c = ND:Counts()
            runFS:SetText(string.format(L["Join dates: %d written, %d copied, %d already there, %d skipped, %d waiting."],
                c.done, c.copied, c.same, c.skipped, c.pending))
            empty:SetText("")
            list:SetData(run.items)
            mode = "plan"
            return
        end
        if mode == "import" then
            local n = 0
            for _, it in ipairs(imports or {}) do if it.pick then n = n + 1 end end
            runFS:SetText(string.format(L["%d date(s) found in notes; %d ticked to take into the history. Click a row to change it."],
                #(imports or {}), n))
            goBtn.label:SetText(L["Take ticked"])
            goBtn:SetShown(n > 0)
            empty:SetText((imports and #imports == 0) and L["No note holds a date."] or "")
            list:SetData(imports or {})
        elseif mode == "safe" then
            local rows = safeRows()
            runFS:SetText(L["Never in a bulk removal or demotion; a promotion still may."])
            empty:SetText(#rows == 0 and L["Nobody is on the safe list."] or "")
            list:SetData(rows)
        elseif mode == "plan" and plan then
            local silent = silentOf(plan)
            local left = planLeft or {}
            local why = m == nil and L["Your guild rank may not edit that note."]
                or (m == "copy" and L["This client does not let an addon write notes: you copy each one."]) or ""
            runFS:SetText(string.format(L["%d to write, %d to confirm; %d already there, %d without a known date, %d only seen by GuildOS."],
                silent, #plan - silent, left.same or 0, left.date or 0, left.seen or 0) .. (why ~= "" and ("  " .. why) or ""))
            goBtn.label:SetText(L["Start"])
            goBtn:SetShown(silent > 0 and m ~= nil)
            askBtn:SetShown(#plan - silent > 0 and m ~= nil)
            empty:SetText(#plan == 0 and L["Every note with a known date already says it."] or "")
            list:SetData(plan)
        else
            runFS:SetText(L["Write a member's date, plan the whole guild, or read dates already in the notes."])
            empty:SetText("")
            list:SetData({})
        end
    end

    ND.uiRefresh, MM.uiRefresh = refresh, refresh
    return refresh
end
