----------------------------------------------------------------------
-- Guild OS - Without GuildOS panel (issue #422; Leadership > Without GuildOS)
-- Who this client never heard GuildOS from and, when the site says it
-- (GOSGILD1.discordLinked), who has no Discord linked; the filter, the
-- officer's two reminder texts and how often, and a Remind button per member that
-- whispers ONE member per click. Visual layout only: the list, the checks
-- and the whisper are GuildOS.AddonReminder's (Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
-- Drawn on a parchment card in the Officers' Room and Settings (specs/salao/fase3.md): the text takes the
-- paper's inks and a class its colour on the paper (UI/Kit.lua); a floating window, the wood's (WOOD).
local Kit = rawget(GuildOS, "Kit")
local C = Kit and Kit.PAPER or GuildOS.Colors
local function classInk(class)
    if Kit then return Kit:ClassInk(class) end
    return GuildOS:GetClassColor(class)
end
local L = GuildOS.L

local ROW_H = 24

-- What a member's row says about them: how long without GuildOS, without Discord, offline, last reminder.
local function detailOf(m, now)
    local R = GuildOS.AddonReminder
    local parts = {}
    -- Who has GuildOS is listed only for Discord.
    if not m.hasAddon then
        parts[#parts + 1] = m.sinceDays and string.format(L["no GuildOS for %d day(s)"], m.sinceDays) or L["no GuildOS"]
    end
    if m.addonOn then parts[#parts + 1] = string.format(L["GuildOS on %s"], (m.addonOn:match("^([^-]+)") or m.addonOn)) end
    if m.noDiscord then parts[#parts + 1] = L["no Discord"] end
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

    -- Under the card's title ("Without GuildOS").
    -- Without the site's list (an older site), the old hint: the game does not know who linked Discord.
    local HINT_NO_SITE = L["Members this client never heard GuildOS from. Remind whispers one of them per click, at most once every few days each; whether they linked Discord on guildos.me is not known in the game."]
    local HINT_SITE = L["Members this client never heard GuildOS from, and the ones guildos.me says have no Discord linked. Remind whispers one of them per click, at most once every few days each."]
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtRemindBoard" })
    -- The members (the mockup's "Without GuildOS or Discord"): the filter above the list, a member a row,
    -- Remind at its right. Beside it, how often and what the whisper says.
    local siteOn = false   -- the site's list is here: the "which lack" choice and the Discord text show
    local card = board:Card(L["Without GuildOS"], { col = 1, fill = true, minH = 320 })
    local hint = card:Note(HINT_NO_SITE)
    local search = UI:CreateInput(card, 140, 24, { placeholder = L["Search"] })
    search:HookScript("OnTextChanged", function() if refresh then refresh() end end)
    local rankDD = UI:CreateDropdown(card, 140, 24)
    rankDD.onSelect = function() refresh() end
    card:Pair(Forms:MakeField(card, "", search), Forms:MakeField(card, "", rankDD))
    -- Which lack: shown only when the site says who linked Discord.
    local lacksDD = UI:CreateDropdown(card, 200, 24)
    lacksDD:SetOptions({
        { value = "any", text = L["Without GuildOS or Discord"] },
        { value = "addon", text = L["Without GuildOS"] },
        { value = "discord", text = L["Without Discord"] },
        { value = "both", text = L["Without GuildOS and Discord"] },
    })
    lacksDD:SetValue("any")
    lacksDD.onSelect = function() refresh() end
    card:Add(lacksDD, { h = 24, shown = function() return siteOn end,
        place = function(_, w) lacksDD:SetWidth(math.min(w, 260)); return 24 end })
    local onlineCB = card:Check(L["Online only"])
    onlineCB.checkbox.onChanged = function() refresh() end
    local recentCB = card:Check(L["Hide the ones reminded recently"], nil, { gap = 4 })
    recentCB.checkbox.onChanged = function() refresh() end
    -- What holds the next reminder back, and how many are listed.
    local status = card:Note("")

    local settings = board:Card(L["Settings"], { col = 2 })
    -- How often, and the record. Taken on Enter and when the box lets go; a number out of range is said and
    -- the held one shown again.
    local daysBox = UI:CreateInput(settings, 60, 24, { numeric = true, max = 2, justify = "CENTER" })
    settings:Field(L["Remind each member at most every"] .. " (" .. L["days"] .. ")", daysBox, { w = 80 })
    local function saveDays(box)
        if (box:GetText() or "") ~= tostring(R:GetDays()) and not R:SetDays(box:GetText()) then
            GuildOS:Print(string.format(L["Between %d and %d days."], R.MIN_DAYS, R.MAX_DAYS))
        end
        box:SetText(tostring(R:GetDays()))
    end
    daysBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    daysBox:HookScript("OnEditFocusLost", function(box) saveDays(box); refresh() end)
    local logCB = settings:Check(L["Also file it on the disciplinary record (counts as a warning)"])
    logCB.checkbox.onChanged = function(_, on) R:SetLogDiscipline(on) end
    -- An alt of somebody who runs GuildOS on another character is not "without GuildOS" (Discord #general).
    local altsCB = settings:Check(L["Count GuildOS on any of a member's linked characters"],
        L["Off: each character is listed until it runs GuildOS itself."], { gap = 4 })
    altsCB.checkbox.onChanged = function(_, on) R:SetCountsAlts(on); refresh() end

    -- The texts: GuildOS's, and (for who has GuildOS but no Discord) Discord's, each with its Default at its
    -- right; the card's Save keeps both.
    local function templateRow(label, kind, shown)
        local box = UI:CreateInput(settings, 300, 24, { max = R.TEMPLATE_MAX })
        local def = Forms:Button(settings, L["Default"])
        def:SetScript("OnClick", function()
            R:SetTemplate(nil, kind)
            box:SetText(R:GetTemplate(kind))
            box:ClearFocus()
        end)
        local holder = settings:Field(label, box, { button = def, gap = 10, shown = shown })
        return box, holder
    end
    local textBox = templateRow(L["Reminder ({name}, {guild})"], nil)
    local discordBox = templateRow(L["Without Discord ({name}, {guild})"], "discord", function() return siteOn end)
    local function saveTexts()
        R:SetTemplate(textBox:GetText(), nil)
        textBox:SetText(R:GetTemplate())
        if siteOn then
            R:SetTemplate(discordBox:GetText(), "discord")
            discordBox:SetText(R:GetTemplate("discord"))
        end
        textBox:ClearFocus(); discordBox:ClearFocus()
    end
    textBox:SetScript("OnEnterPressed", saveTexts)
    discordBox:SetScript("OnEnterPressed", saveTexts)
    local saveBtn = Forms:Button(settings, L["Save"], "primary")
    saveBtn:SetScript("OnClick", saveTexts)
    settings:Actions({ saveBtn })
    textBox.saveButton, discordBox.saveButton = saveBtn, saveBtn

    local listHolder = card:Body(ROW_H * 4, { gap = 10 })
    local empty = UI:CreateText(listHolder, "", 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    local now = GetServerTime()
    local function createRow(parent)
        local row = Forms:TodoRow(parent)
        row.remind = Forms:SmallButton(row.right, L["Remind"], "primary")
        row:Right({ row.remind })
        -- The click itself sends the whisper: WoW: Forever drops one sent from a timer.
        row.remind:SetScript("OnClick", function()
            local m = row.item
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
    local function fillRow(row, m)
        row.item = m
        local cr, cg, cb = classInk(m.class)
        row.av:SetMember(m.name, m.class, not m.online)
        row.title:SetText(m.name .. "  |cff" .. string.format("%02x%02x%02x", C.textSoft.r * 255, C.textSoft.g * 255, C.textSoft.b * 255)
            .. (m.rankName or "?") .. " · " .. L["Lv "] .. (m.level or 0) .. "|r")
        row.title:SetTextColor(cr, cg, cb)
        row.sub:SetText(detailOf(m, now))
        if R:CanRemind(m, now) then row.remind:Enable() else row.remind:Disable() end
    end
    local list = UI.MakeVirtualList(listHolder, "GuildOSMgmtRemindScroll", 36, createRow, fillRow)

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
        if not discordBox:HasFocus() and (discordBox:GetText() or "") == "" then discordBox:SetText(R:GetTemplate("discord")) end
        logCB.checkbox:SetChecked(R:GetLogDiscipline())
        altsCB.checkbox:SetChecked(R:CountsAlts())

        -- The site's list or not: the hint, the "which lack" choice and the Discord text follow it.
        local site = R:Linked() ~= nil
        hint:SetText(site and HINT_SITE or HINT_NO_SITE)
        siteOn = site
        board:Layout()

        local data = R:List({
            text = search:GetText(), rank = rankDD:GetValue(),
            online = onlineCB.checkbox:GetChecked() and true or false,
            hideRecent = recentCB.checkbox:GetChecked() and true or false,
            lacks = site and lacksDD:GetValue() or nil,
        }, now)
        local t = R:Times(now)
        local held = (t.holdUntil and t.clock < t.holdUntil and { "throttle", t.holdUntil - t.clock })
            or (t.last and t.clock - t.last < R.GAP and { "wait", R.GAP - (t.clock - t.last) })
        local count = string.format(L["%d member(s)"], #data)
        status:SetText(held and (count .. "  " .. R.WhyText(held[1], held[2])) or count)
        empty:SetText(#data == 0 and (site and L["Nobody here: everyone has GuildOS and Discord, or the filter hides them."]
            or L["Nobody here: everyone has GuildOS, or the filter hides them."]) or "")
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
