----------------------------------------------------------------------
-- Guild OS - Without GuildOS panel (issue #422; Leadership > Without GuildOS)
-- Who this client never heard GuildOS from, the filter, the officer's
-- reminder text and how often, and a Remind button per member that
-- whispers ONE member per click. Visual layout only: the list, the checks
-- and the whisper are GuildOS.AddonReminder's (Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local ROW_H = 24
local REMIND_W = 90

-- What a member's row says about them: how long without GuildOS, offline, last reminder.
local function detailOf(m, now)
    local R = GuildOS.AddonReminder
    local parts = {}
    if m.sinceDays then
        parts[#parts + 1] = string.format(L["no GuildOS for %d day(s)"], m.sinceDays)
    else
        parts[#parts + 1] = L["no GuildOS"]
    end
    parts[#parts + 1] = m.online and L["online"] or (m.daysOffline and (m.daysOffline .. L["d offline"]) or L["offline"])
    local d = m.remindedAt and R.DaysSince(m.remindedAt, now)
    if d then
        parts[#parts + 1] = d == 0 and L["reminded today"] or string.format(L["reminded %d day(s) ago"], d)
    end
    return table.concat(parts, "  ")
end

function GuildOS:BuildRemindSub(panel)
    local R = GuildOS.AddonReminder
    if not R then return nil end
    local refresh

    local title = UI:CreateSectionTitle(panel, L["WITHOUT GUILDOS"], true)
    title:SetPoint("TOPLEFT", 0, -2)
    local hint = UI:CreateText(panel,
        L["Members this client never heard GuildOS from. Remind whispers one of them per click, at most once every few days each; whether they linked Discord on guildos.me is not known in the game."],
        11, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 0, -24)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -24)
    hint:SetJustifyH("LEFT")

    -- The filter.
    local y = -56
    local search = UI:CreateInput(panel, 140, 22, { placeholder = L["Search"] })
    search:SetPoint("TOPLEFT", 0, y)
    search:HookScript("OnTextChanged", function() if refresh then refresh() end end)
    local rankDD = UI:CreateDropdown(panel, 140, 22)
    rankDD:SetPoint("LEFT", search, "RIGHT", 8, 0)
    rankDD.onSelect = function() refresh() end
    local onlineCB = UI:CreateCheckbox(panel, L["Online only"], 18)
    onlineCB:SetPoint("LEFT", rankDD, "RIGHT", 12, 0)
    onlineCB.checkbox.onChanged = function() refresh() end
    local recentCB = UI:CreateCheckbox(panel, L["Hide the ones reminded recently"], 18)
    recentCB:SetPoint("TOPLEFT", 0, y - 30)
    recentCB.checkbox.onChanged = function() refresh() end

    -- How often, and the record.
    y = y - 60
    local daysLbl = UI:CreateText(panel, L["Remind each member at most every"], 11, C.text.r, C.text.g, C.text.b)
    daysLbl:SetPoint("TOPLEFT", 0, y - 4)
    local daysBox = UI:CreateInput(panel, 44, 22, { numeric = true, max = 2, justify = "CENTER" })
    daysBox:SetPoint("LEFT", daysLbl, "RIGHT", 8, 0)
    local daysUnit = UI:CreateText(panel, L["days"], 11, C.text.r, C.text.g, C.text.b)
    daysUnit:SetPoint("LEFT", daysBox, "RIGHT", 6, 0)
    -- Taken on Enter and when the box lets go; a number out of range is said and the held one shown again.
    local function saveDays(box)
        if (box:GetText() or "") ~= tostring(R:GetDays()) and not R:SetDays(box:GetText()) then
            GuildOS:Print(string.format(L["Between %d and %d days."], R.MIN_DAYS, R.MAX_DAYS))
        end
        box:SetText(tostring(R:GetDays()))
    end
    daysBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    daysBox:HookScript("OnEditFocusLost", function(box) saveDays(box); refresh() end)
    local logCB = UI:CreateCheckbox(panel, L["Also file it on the disciplinary record (counts as a warning)"], 18)
    logCB:SetPoint("TOPLEFT", 0, y - 30)
    logCB.checkbox.onChanged = function(_, on) R:SetLogDiscipline(on) end

    -- The text.
    y = y - 60
    local textLbl = UI:CreateText(panel, L["Reminder ({name}, {guild})"], 11, C.text.r, C.text.g, C.text.b)
    textLbl:SetPoint("TOPLEFT", 0, y - 4)
    local textBox = UI:CreateInput(panel, 300, 22, { max = R.TEMPLATE_MAX })
    textBox:SetPoint("LEFT", textLbl, "RIGHT", 8, 0)
    textBox:SetPoint("RIGHT", panel, "RIGHT", -(60 + 6 + 70 + 6), 0)
    local saveBtn = UI:AttachSaveButton(textBox, function(box)
        R:SetTemplate(box:GetText())
        box:SetText(R:GetTemplate())
    end, { state = true })
    local defBtn = UI:CreateButton(panel, L["Default"], 70, 22)
    defBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    defBtn:SetScript("OnClick", function()
        R:SetTemplate(nil)
        textBox:SetText(R:GetTemplate())
        textBox:ClearFocus()
    end)

    -- What holds the next reminder back, and how many are listed.
    y = y - 32
    local status = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    status:SetPoint("TOPLEFT", 0, y)
    status:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
    status:SetJustifyH("LEFT")

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, y - 22)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local empty = UI:CreateText(listHolder, "", 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    local now = GetServerTime()
    local function createRow(parent)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row.nameFS = UI:CreateText(row, "", 11)
        row.nameFS:SetPoint("LEFT", 8, 0)
        row.rankFS = UI:CreateText(row, "", 10, C.silver.r, C.silver.g, C.silver.b)
        row.rankFS:SetPoint("LEFT", 170, 0)
        row.lvlFS = UI:CreateText(row, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lvlFS:SetPoint("LEFT", 300, 0)
        row.detailFS = UI:CreateText(row, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.detailFS:SetPoint("LEFT", 350, 0)
        row.remind = UI:CreateButton(row, L["Remind"], REMIND_W, 20)
        row.remind:SetPoint("RIGHT", -4, 0)
        row.detailFS:SetPoint("RIGHT", row.remind, "LEFT", -8, 0)
        row.detailFS:SetJustifyH("LEFT")
        -- The click itself sends the whisper: WoW: Forever drops one sent from a timer.
        row.remind:SetScript("OnClick", function(self)
            local m = self:GetParent().item
            if not m then return end
            local ok, why, left = R:Remind(m.key)
            if ok then
                GuildOS:Print(string.format(L["Reminder whispered to %s."], m.name))
            else
                GuildOS:Print(R.WhyText(why, left))
            end
            refresh()
        end)
        return row
    end
    local function fillRow(row, m, idx)
        row.item = m
        local alt = (idx % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        local cr, cg, cb = GuildOS:GetClassColor(m.class)
        row.nameFS:SetText(m.name)
        row.nameFS:SetTextColor(cr, cg, cb)
        row.rankFS:SetText(m.rankName or "?")
        row.lvlFS:SetText(L["Lv "] .. (m.level or 0))
        row.detailFS:SetText(detailOf(m, now))
        if R:CanRemind(m, now) then row.remind:Enable() else row.remind:Disable() end
    end
    local list = UI.MakeVirtualList(listHolder, "GuildOSMgmtRemindScroll", ROW_H + 2, createRow, fillRow)

    local rearm   -- a refresh waiting for the gap or the hold to pass
    refresh = function()
        now = GetServerTime()
        local opts = { { value = -1, text = L["Any rank"] } }
        for _, r in ipairs(GuildOS.GuildManager and GuildOS.GuildManager:GetRanks() or {}) do
            opts[#opts + 1] = { value = r.index, text = r.name }
        end
        rankDD:SetOptions(opts)
        if rankDD:GetValue() == nil then rankDD:SetValue(-1) end
        if not daysBox:HasFocus() then daysBox:SetText(tostring(R:GetDays())) end
        if not textBox:HasFocus() and (textBox:GetText() or "") == "" then textBox:SetText(R:GetTemplate()) end
        logCB.checkbox:SetChecked(R:GetLogDiscipline())

        local data = R:List({
            text = search:GetText(), rank = rankDD:GetValue(),
            online = onlineCB.checkbox:GetChecked() and true or false,
            hideRecent = recentCB.checkbox:GetChecked() and true or false,
        }, now)
        local t = R:Times(now)
        local held = (t.holdUntil and t.clock < t.holdUntil and { "throttle", t.holdUntil - t.clock })
            or (t.last and t.clock - t.last < R.GAP and { "wait", R.GAP - (t.clock - t.last) })
        local count = string.format(L["%d member(s)"], #data)
        status:SetText(held and (count .. "  " .. R.WhyText(held[1], held[2])) or count)
        empty:SetText(#data == 0 and L["Nobody here: everyone has GuildOS, or the filter hides them."] or "")
        list:SetData(data)
        -- Turn the buttons back on once the wait is over (the window may stay open).
        if held and not rearm then
            rearm = true
            GuildOS.Compat.After(math.ceil(held[2]) + 0.1, function()
                rearm = nil
                if panel:IsVisible() then GuildOS:SafeCall(refresh) end
            end)
        end
    end

    R.uiRefresh = function() if panel:IsVisible() then refresh() end end
    return refresh
end
