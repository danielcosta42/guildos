----------------------------------------------------------------------
-- Guild OS - Notes and marks panel (issue #429; Leadership > Notes and marks)
-- Join dates written into the guild notes and read back from them, the safe list, nicknames and the
-- "back after N days offline" line. Visual layout only: the plans, the writes, the marks and the
-- settings are GuildOS.NoteDates', GuildOS.MemberMarks' and GuildOS.MemberHistory's (Rule 10).
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
-- Drawn on a parchment card in the Officers' Room and Settings (specs/salao/fase3.md): the text takes the
-- paper's inks and a class its colour on the paper (UI/Kit.lua); a floating window, the wood's (WOOD).
local Kit = rawget(GuildOS, "Kit")
local C = Kit and Kit.PAPER or GuildOS.Colors
local function rule(row) if Kit then Kit:Rule(row) end end
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

-- A main's join date for their alts with no real date (NoteDates:OfferAlts): one question for the whole group.
GuildOS.Dialogs["GUILDOS_NOTE_DATE_ALTS"] = {
    text = "%s",
    button1 = L["Apply"], button2 = L["Cancel"],
    OnAccept = function(_, data)
        if GuildOS.NoteDates then GuildOS.NoteDates:ApplyToAlts(data) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
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
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtMarksBoard" })

    -- ── Join dates in the notes (the mockup's first card) ─────────────
    local dates = board:Card(L["Join dates in the notes"], { col = 1 })
    local offBtn = Forms:Pill(dates, L["Officer"])
    offBtn:SetScript("OnClick", function() ND:SetTarget("officer"); plan = nil; refresh() end)
    local pubBtn = Forms:Pill(dates, L["Public"])
    pubBtn:SetScript("OnClick", function() ND:SetTarget("public"); plan = nil; refresh() end)
    dates:Note(L["Note"])
    dates:Flow({ offBtn, pubBtn }, { gap = Forms.LABEL_GAP })
    local fmtDD = UI:CreateDropdown(dates, 110, 24)
    local fmts = {}
    for _, f in ipairs(ND.FORMATS) do fmts[#fmts + 1] = { value = f, text = f } end
    fmtDD:SetOptions(fmts)
    fmtDD.onSelect = function(_, v) ND:SetFormat(v); plan = nil; refresh() end
    local orderDD = UI:CreateDropdown(dates, 120, 24)
    orderDD:SetOptions({ { value = "auto", text = L["By language"] }, { value = "dmy", text = L["Day first"] },
                         { value = "mdy", text = L["Month first"] } })
    orderDD.onSelect = function(_, v) ND:SetOrder(v); if mode == "import" then imports = ND:ImportPlan() end; refresh() end
    dates:Pair(Forms:MakeField(dates, L["Date format"], fmtDD), Forms:MakeField(dates, L["Order"], orderDD))
    local labelCB = dates:Check(ND.LABEL .. "...")
    labelCB.checkbox.onChanged = function(_, checked) ND:SetLabel(checked); plan = nil; refresh() end
    local seenCB = dates:Check(L["Also dates GuildOS only saw"], nil, { gap = 4 })
    seenCB.checkbox.onChanged = function(_, checked) ND:SetWithSeen(checked); plan = nil; refresh() end

    local nameBox = UI:CreateInput(dates, 150, 24, { max = 60 })
    local writeBtn = Forms:Button(dates, L["Write date"])
    writeBtn:SetScript("OnClick", function() ND:WriteOne(strtrim(nameBox:GetText() or "")); refresh() end)
    nameBox:SetScript("OnEnterPressed", function(s) s:ClearFocus(); ND:WriteOne(strtrim(s:GetText() or "")); refresh() end)
    dates:Field(L["Member"], nameBox, { button = writeBtn, gap = 10 })
    local planBtn = Forms:Button(dates, L["Whole guild"])
    planBtn:SetScript("OnClick", function() plan, planLeft = ND:Plan(); mode = "plan"; refresh() end)
    local importBtn = Forms:Button(dates, L["Read dates from notes"])
    importBtn:SetScript("OnClick", function() imports = ND:ImportPlan(); mode = "import"; refresh() end)
    dates:Flow({ planBtn, importBtn })

    -- ── Safe list, nicknames, returns ─────────────────────────────────
    local safe = board:Card(L["Safe list and nicknames"], { col = 2 })
    -- WoW: Forever: the marks stay on this client (audit B11).
    local localOnly = GuildOS:LocalOnlyText()
    if localOnly then safe:Note(localOnly, { size = UI.SP.META }) end
    local tagBox = UI:CreateInput(safe, 80, 24, { max = MM.TAG_MAX })
    local backBox = UI:CreateInput(safe, 60, 24, { numeric = true, max = 3, justify = "CENTER" })
    safe:Pair(Forms:MakeField(safe, L["Safe tag in notes"], tagBox, { w = 140 }),
              Forms:MakeField(safe, L["Tell me who comes back after"], backBox, { w = 80, hint = L["days offline (0: never)"] }))
    -- One Save for both: Enter in either does the same.
    local function saveTag() MM:SetSafeTag(tagBox:GetText() or ""); tagBox:ClearFocus() end
    local function saveBack() MH:SetBackDays(tonumber(backBox:GetText() or "") or 0); backBox:ClearFocus() end
    local function saveBoth() saveTag(); saveBack(); refresh() end
    tagBox:SetScript("OnEnterPressed", function() saveTag(); refresh() end)
    backBox:SetScript("OnEnterPressed", function() saveBack(); refresh() end)
    local saveBtn = Forms:Button(safe, L["Save"], "primary")
    saveBtn:SetScript("OnClick", saveBoth)
    safe:Actions({ saveBtn })
    tagBox.saveButton, backBox.saveButton = saveBtn, saveBtn
    -- Who leaves or is removed: the officers' popup (#449, specs/salao/saidas.md), on this client.
    local DP = GuildOS.Departure
    local departCB = DP and safe:Check(L["Ask me when somebody leaves or is removed"],
        L["A small window: their other characters, a permanent note, a ban or a suspension."], { gap = 4 })
    if departCB then
        departCB.checkbox.onChanged = function(_, checked) DP:SetEnabled(checked) end
    end

    local memberBox = UI:CreateInput(safe, 150, 24, { max = 60 })
    local nickBox = UI:CreateInput(safe, 120, 24, { max = MM.NICK_MAX })
    safe:Pair(Forms:MakeField(safe, L["Member"], memberBox), Forms:MakeField(safe, L["Nickname"], nickBox), { gap = 14 })
    -- How long a new safe mark lasts: for good, 7, 14 or 30 days, or until a date (MemberMarks.UntilOf reads it).
    local forDD = UI:CreateDropdown(safe, 120, 24)
    local forOpts = { { value = "forever", text = L["Forever"] } }
    for _, d in ipairs(MM.DURATIONS) do forOpts[#forOpts + 1] = { value = tostring(d), text = string.format(L["%d days"], d) } end
    forOpts[#forOpts + 1] = { value = "date", text = L["Until a date"] }
    forDD:SetOptions(forOpts)
    forDD:SetValue("forever")
    local untilBox = UI:CreateInput(safe, 100, 24, { max = 24 })
    forDD.onSelect = function(_, v) if v == "date" then untilBox:SetFocus() end end
    safe:Pair(Forms:MakeField(safe, L["Safe for"], forDD),
              Forms:MakeField(safe, L["Until"], untilBox, { w = 110, hint = L["a date, as 15/01/2027"] }), { gap = 14 })
    local safeBtn = Forms:Button(safe, L["Safe on / off"])
    safeBtn:SetScript("OnClick", function()
        local u, why = MM.UntilOf(forDD:GetValue(), strtrim(untilBox:GetText() or ""))
        if why == "bad" then GuildOS:Print(L["Write a date after today, as 15/01/2027."]) return end
        MM:CommandSafe(memberBox:GetText() or "", u)
        mode = "safe"
        refresh()
    end)
    local nickBtn = Forms:Button(safe, L["Set nickname"])
    nickBtn:SetScript("OnClick", function()
        MM:CommandNick(strtrim(memberBox:GetText() or "") .. " " .. strtrim(nickBox:GetText() or ""))
        refresh()
    end)
    local safeListBtn = Forms:Button(safe, L["Safe list"])
    safeListBtn:SetScript("OnClick", function() mode = "safe"; refresh() end)
    safe:Flow({ safeBtn, nickBtn, safeListBtn })

    -- ── The list: the plan, the import's review or the safe list ──────
    local listCard = board:Card(L["Members"], { fill = true, minH = 260 })
    local runFS = listCard:Note("")
    local goBtn = Forms:Button(listCard, L["Start"], "primary")
    local askBtn = Forms:Button(listCard, L["Rewrite those too"])
    local nextBtn = Forms:Button(listCard, L["Next"])
    nextBtn:SetWidth(150)
    nextBtn:SetScript("OnClick", function() ND:Next() end)
    local stopBtn = Forms:Button(listCard, L["Stop"])
    stopBtn:SetScript("OnClick", function() ND:Stop() end)
    listCard:Flow({ stopBtn, nextBtn, askBtn, goBtn }, { align = "RIGHT", gap = 6,
        shown = function() return goBtn:IsShown() or askBtn:IsShown() or nextBtn:IsShown() or stopBtn:IsShown() end })
    local listHolder = listCard:Body(ROW_H * 4, { gap = 10 })
    local empty = text(listHolder, "", 11, C.silver)
    empty:SetPoint("TOPLEFT", 0, -4)
    local function createRow(parent)
        local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        rule(row)
        row.a = text(row, "", 11)
        row.a:SetPoint("LEFT", 8, 0)
        row.b = text(row, "", 10, C.silver)
        row.b:SetPoint("LEFT", 170, 0)
        row.c = text(row, "", 10, C.text)
        row.c:SetPoint("LEFT", 390, 0)
        row.d = text(row, "", 10, C.textSoft)
        row.d:SetPoint("RIGHT", -8, 0)
        -- The safe list: the mark's tooltip (its end, as the roster's says it).
        row:SetScript("OnEnter", function(self)
            local it = self.item
            if mode ~= "safe" or not (it and it.key and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.name, 1, 1, 1)
            MM:TooltipLines(GameTooltip, it.key)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
            local u = MM:SafeUntil(k)
            out[#out + 1] = { name = k:match("^([^-]+)") or k, nick = MM:Nick(k), key = k,
                why = u and (L["marked by hand"] .. ", " .. MM:UntilText(u)) or L["marked by hand"] }
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
        Forms:SetOn(offBtn, which == "officer")
        Forms:SetOn(pubBtn, which == "public")
        fmtDD:SetValue(ND:FormatId())
        labelCB.checkbox:SetChecked(ND:UseLabel())
        seenCB.checkbox:SetChecked(ND:WithSeen())
        orderDD:SetValue(ND:OrderSetting())
        if not tagBox:HasFocus() then tagBox:SetText(MM:SafeTag()) end
        if not backBox:HasFocus() then backBox:SetText(tostring(MH:BackDays())) end
        if departCB then departCB.checkbox:SetChecked(DP:Enabled()) end

        local open = ND:TakeOpen()
        -- From the data audit's "Write date": its member in the box, ready for Write date.
        local pre = ND.TakePrefill and ND:TakePrefill()
        if pre then nameBox:SetText(pre); nameBox:SetFocus() end
        if open == "plan" then plan, planLeft = ND:Plan(); mode = "plan"
        elseif open == "import" then imports = ND:ImportPlan(); mode = "import" end

        local run = ND:Run()
        local m = ND:Mode(which)
        nextBtn:SetShown(run ~= nil and m ~= "write" and ND:Current() ~= nil)
        nextBtn.label:SetText(ND:NextLabel())
        Forms:FitPill(nextBtn)
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
            Forms:FitPill(goBtn)
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
            Forms:FitPill(goBtn)
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

    local fill = refresh
    refresh = function()
        fill()
        board:Layout()
    end
    -- Only while it is on screen (memory audit): showing it refreshes it anyway.
    local function onChange() if panel:IsVisible() then refresh() end end
    ND.uiRefresh, MM.uiRefresh = onChange, onChange
    return refresh
end
