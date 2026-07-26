----------------------------------------------------------------------
-- Guild OS - Management Panel (Leadership Suite UI)
-- The "Lideran\195\167a" tab: rank management, inactivity report, promotion /
-- trial suggestions, MOTD / Guild Info editing, and the action log.
-- Visual layout only — all data and actions go through BRutus.GuildManager
-- (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Sub-tabs shown across the top of the panel.
local SUBTABS = {
    { key = "ranks",    label = L["Ranks"] },
    { key = "inactive", label = L["Inactivity"] },
    { key = "suggest",  label = L["Suggestions"] },
    { key = "motd",     label = L["MOTD / Info"] },
    { key = "log",      label = L["Audit Log"] },
    { key = "ban",      label = L["Ban List"] },
    { key = "engage",   label = L["Engagement"] },
    { key = "presets",  label = L["Presets"] },
}

local ROW_H = 26

-- Confirmation dialog for a bulk Apply. The full, already-formatted message
-- is passed as text arg1 ("%s"); OnAccept runs the officer-gated ApplyPreset
-- on exactly the members captured when Apply was clicked. Rank/kick handoffs
-- inside ApplyPreset open Blizzard's native panel (ADR-0010) — no protected
-- call is made from this insecure OnAccept.
StaticPopupDialogs["GUILDOS_MODPRESET_APPLY"] = {
    text = "%s",
    button1 = L["Apply"],
    button2 = L["Cancel"],
    OnAccept = function(_, data)
        if data and data.preset and BRutus.ModPresets then
            BRutus.ModPresets:ApplyPreset(data.preset, data.matches)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

----------------------------------------------------------------------
-- Small builders shared by the sub-panels
----------------------------------------------------------------------
-- A scroll frame + content child that fills its parent panel.
local function MakeScrollList(panel, name)
    local scroll = CreateFrame("ScrollFrame", name, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -10, 0)
    UI:SkinScrollBar(scroll, name)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

-- A striped row frame parented to `content`. All text/widgets must be created
-- on the returned frame so a single Hide() clears the row on refresh.
local function MakeRow(content, yOff, index, height)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetSize(content:GetWidth() - 4, height or ROW_H)
    row:SetPoint("TOPLEFT", 0, -yOff)
    row:SetBackdrop({ bgFile = WHITE })
    local alt = (index % 2 == 0) and C.row1 or C.row2
    row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
    return row
end

-- A section header frame parented to `content`.
local function MakeSectionHeader(content, text, yOff)
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(content:GetWidth() - 4, 22)
    f:SetPoint("TOPLEFT", 0, -yOff)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(WHITE)
    bg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 0.7)
    local lbl = UI:CreateHeaderText(f, text, 10)
    lbl:SetPoint("LEFT", 8, 0)
    return f
end

-- Clear all (frame) children of a content holder before a rebuild.
local function ClearContent(content)
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
end

----------------------------------------------------------------------
-- RANKS sub-panel — promote / demote roster members
----------------------------------------------------------------------
local function BuildRanksSub(panel)
    local note = UI:CreateText(panel,
        L["Rank changes are Blizzard-protected: the arrow buttons open the official guild panel for you to confirm."],
        9, C.silver.r, C.silver.g, C.silver.b)
    note:SetPoint("TOPLEFT", 2, -2)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -22)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtRanksScroll")

    return function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local GM = BRutus.GuildManager
        local canPromote = GM:CanPromote()
        local canDemote = GM:CanDemote()

        -- Collect roster, sort by rank then name.
        local members = {}
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name, rankName, rankIndex, level, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
            if name then
                members[#members + 1] = {
                    name = name:match("^([^-]+)") or name,
                    fullName = name,
                    rankName = rankName or "?",
                    rankIndex = rankIndex or 0,
                    level = level or 0,
                    class = classFile or "",
                    online = isOnline,
                }
            end
        end
        table.sort(members, function(a, b)
            if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
            return a.name:lower() < b.name:lower()
        end)

        local yOff = 0
        for idx, m in ipairs(members) do
            local row = MakeRow(content, yOff, idx)
            local cr, cg, cb = BRutus:GetClassColor(m.class)

            local nameFS = UI:CreateText(row, m.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 8, 0)
            if not m.online then nameFS:SetTextColor(cr * 0.55, cg * 0.55, cb * 0.55) end

            local rankFS = UI:CreateText(row, m.rankName, 10, C.silver.r, C.silver.g, C.silver.b)
            rankFS:SetPoint("LEFT", 180, 0)

            local lvlFS = UI:CreateText(row, L["Lv "] .. m.level, 9, C.textDim.r, C.textDim.g, C.textDim.b)
            lvlFS:SetPoint("LEFT", 340, 0)

            -- Demote one step (higher rankIndex). Hidden if no permission.
            if canDemote then
                local downBtn = UI:CreateButton(row, "|TInterface\\BUTTONS\\Arrow-Down-Up:14:14|t", 26, 18)
                downBtn:SetPoint("RIGHT", -8, 0)
                downBtn:SetScript("OnClick", function()
                    BRutus.GuildManager:Demote(m.fullName)
                    BRutus.GuildManager:RefreshUI()
                end)
            end
            -- Promote one step (lower rankIndex).
            if canPromote then
                local upBtn = UI:CreateButton(row, "|TInterface\\BUTTONS\\Arrow-Up-Up:14:14|t", 26, 18)
                upBtn:SetPoint("RIGHT", -38, 0)
                upBtn:SetScript("OnClick", function()
                    BRutus.GuildManager:Promote(m.fullName)
                    BRutus.GuildManager:RefreshUI()
                end)
            end

            yOff = yOff + ROW_H + 2
        end

        if #members == 0 then
            local empty = UI:CreateText(content, L["Roster empty or unavailable."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- INACTIVITY sub-panel — purge candidates
----------------------------------------------------------------------
local function BuildInactiveSub(panel)
    panel.threshold = BRutus.GuildManager.DEFAULT_INACTIVE_DAYS

    local lbl = UI:CreateText(panel, L["Inactive for more than"], 11, C.text.r, C.text.g, C.text.b)
    lbl:SetPoint("TOPLEFT", 2, -4)

    local daysBox = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    daysBox:SetSize(44, 22)
    daysBox:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    daysBox:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    daysBox:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 1)
    daysBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    daysBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    daysBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    daysBox:SetJustifyH("CENTER")
    daysBox:SetAutoFocus(false)
    daysBox:SetNumeric(true)
    daysBox:SetMaxLetters(4)
    daysBox:SetText(tostring(panel.threshold))

    local daysLbl = UI:CreateText(panel, L["days"], 11, C.text.r, C.text.g, C.text.b)
    daysLbl:SetPoint("LEFT", daysBox, "RIGHT", 6, 0)

    local summary = UI:CreateText(panel, "", 10, C.gold.r, C.gold.g, C.gold.b)
    summary:SetPoint("LEFT", daysLbl, "RIGHT", 16, 0)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -32)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtInactiveScroll")

    local refresh
    refresh = function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local GM = BRutus.GuildManager
        local canKick = GM:CanKick()
        local list = GM:GetInactiveMembers(panel.threshold)
        summary:SetText(format(L["%d member(s)"], #list))

        local yOff = 0
        for idx, m in ipairs(list) do
            local row = MakeRow(content, yOff, idx)
            local cr, cg, cb = BRutus:GetClassColor(m.class)

            local nameFS = UI:CreateText(row, m.name, 11, cr, cg, cb)
            nameFS:SetPoint("LEFT", 8, 0)

            local rankFS = UI:CreateText(row, m.rankName or "?", 10, C.silver.r, C.silver.g, C.silver.b)
            rankFS:SetPoint("LEFT", 180, 0)

            local lvlFS = UI:CreateText(row, L["Lv "] .. m.level, 9, C.textDim.r, C.textDim.g, C.textDim.b)
            lvlFS:SetPoint("LEFT", 320, 0)

            local daysColor = m.daysOffline >= 60 and C.red or C.gold
            local daysFS = UI:CreateText(row, m.daysOffline .. L["d offline"], 10, daysColor.r, daysColor.g, daysColor.b)
            daysFS:SetPoint("LEFT", 390, 0)

            if canKick then
                local kickBtn = UI:CreateButton(row, L["Remove"], 70, 18)
                kickBtn:SetPoint("RIGHT", -8, 0)
                kickBtn:SetScript("OnClick", function()
                    BRutus.GuildManager:ConfirmKick(m.fullName)
                end)
            end

            yOff = yOff + ROW_H + 2
        end

        if #list == 0 then
            local empty = UI:CreateText(content, L["No inactive members in this period."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end

    local function apply()
        local v = tonumber(daysBox:GetText()) or BRutus.GuildManager.DEFAULT_INACTIVE_DAYS
        if v < 1 then v = 1 end
        panel.threshold = v
        daysBox:ClearFocus()
        refresh()
    end
    daysBox:SetScript("OnEnterPressed", apply)
    daysBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local applyBtn = UI:CreateButton(panel, L["Apply"], 70, 22)
    applyBtn:SetPoint("LEFT", summary, "RIGHT", 16, 0)
    applyBtn:SetScript("OnClick", apply)

    return refresh
end

----------------------------------------------------------------------
-- SUGGESTIONS sub-panel — trial approvals + promotion candidates
----------------------------------------------------------------------
local function BuildSuggestSub(panel)
    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, 0)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtSuggestScroll")

    local refresh
    refresh = function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local data = BRutus.GuildManager:GetSuggestions()
        local yOff = 0

        -- Trials ready for a decision
        MakeSectionHeader(content, format(L["TRIALS READY FOR DECISION  (%d)"], #data.trialsReady), yOff)
        yOff = yOff + 24
        if #data.trialsReady == 0 then
            local none = MakeRow(content, yOff, 1)
            local fs = UI:CreateText(none, L["No trials due."], 10, C.silver.r, C.silver.g, C.silver.b)
            fs:SetPoint("LEFT", 8, 0)
            yOff = yOff + ROW_H + 2
        else
            for idx, t in ipairs(data.trialsReady) do
                local row = MakeRow(content, yOff, idx)
                local nameFS = UI:CreateText(row, t.name, 11, C.gold.r, C.gold.g, C.gold.b)
                nameFS:SetPoint("LEFT", 8, 0)

                local infoFS = UI:CreateText(row,
                    format(L["Day %d  |  %d%% attendance  |  iLvl %s%d"], t.daysSince, t.attendance,
                        t.ilvlDelta >= 0 and "+" or "", t.ilvlDelta),
                    10, C.silver.r, C.silver.g, C.silver.b)
                infoFS:SetPoint("LEFT", 150, 0)

                local key = t.key
                local denyBtn = UI:CreateButton(row, L["Deny"], 56, 18)
                denyBtn:SetPoint("RIGHT", -8, 0)
                denyBtn:SetScript("OnClick", function()
                    BRutus.TrialTracker:UpdateStatus(key, BRutus.TrialTracker.STATUS.DENIED)
                    refresh()
                end)

                local okBtn = UI:CreateButton(row, L["Approve"], 64, 18)
                okBtn:SetPoint("RIGHT", denyBtn, "LEFT", -4, 0)
                okBtn:SetScript("OnClick", function()
                    BRutus.TrialTracker:UpdateStatus(key, BRutus.TrialTracker.STATUS.APPROVED)
                    refresh()
                end)

                yOff = yOff + ROW_H + 2
            end
        end

        yOff = yOff + 8

        -- Promotion candidates
        MakeSectionHeader(content, format(L["PROMOTION CANDIDATES  (%d)"], #data.promoteCandidates), yOff)
        yOff = yOff + 24
        if #data.promoteCandidates == 0 then
            local none = MakeRow(content, yOff, 1)
            local fs = UI:CreateText(none, L["No candidates (high attendance) right now."], 10, C.silver.r, C.silver.g, C.silver.b)
            fs:SetPoint("LEFT", 8, 0)
            yOff = yOff + ROW_H + 2
        else
            local canPromote = BRutus.GuildManager:CanPromote()
            for idx, m in ipairs(data.promoteCandidates) do
                local row = MakeRow(content, yOff, idx)
                local cr, cg, cb = BRutus:GetClassColor(m.class)
                local nameFS = UI:CreateText(row, m.name, 11, cr, cg, cb)
                nameFS:SetPoint("LEFT", 8, 0)

                local rankFS = UI:CreateText(row, m.rankName or "?", 10, C.silver.r, C.silver.g, C.silver.b)
                rankFS:SetPoint("LEFT", 150, 0)

                local attFS = UI:CreateText(row, format(L["%d%% attendance"], m.attendance), 10, C.green.r, C.green.g, C.green.b)
                attFS:SetPoint("LEFT", 300, 0)

                if canPromote then
                    local fullName = m.fullName
                    local promoBtn = UI:CreateButton(row, L["Promote"], 76, 18)
                    promoBtn:SetPoint("RIGHT", -8, 0)
                    promoBtn:SetScript("OnClick", function()
                        BRutus.GuildManager:Promote(fullName)
                        BRutus.GuildManager:RefreshUI()
                    end)
                end

                yOff = yOff + ROW_H + 2
            end
        end

        content:SetHeight(math.max(1, yOff))
    end

    return refresh
end

----------------------------------------------------------------------
-- MOTD / GUILD INFO sub-panel
----------------------------------------------------------------------
local function MakeTextArea(parent, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 1)
    box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    box:SetMultiLine(true)
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(C.white.r, C.white.g, C.white.b)
    box:SetTextInsets(6, 6, 4, 4)
    box:SetAutoFocus(false)
    box:SetHeight(height)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function BuildMotdSub(panel)
    -- MOTD
    local motdLabel = UI:CreateHeaderText(panel, L["MESSAGE OF THE DAY"], 11)
    motdLabel:SetPoint("TOPLEFT", 2, -4)

    local motdBox = MakeTextArea(panel, 50)
    motdBox:SetPoint("TOPLEFT", 2, -24)
    motdBox:SetPoint("TOPRIGHT", -12, -24)
    motdBox:SetMaxLetters(128)

    local motdBtn = UI:CreateButton(panel, L["Save MOTD"], 110, 24)
    motdBtn:SetPoint("TOPLEFT", 2, -82)
    motdBtn:SetScript("OnClick", function()
        BRutus.GuildManager:SetMOTD(motdBox:GetText())
        motdBox:ClearFocus()
    end)

    local motdNote = UI:CreateText(panel, "", 9, C.silver.r, C.silver.g, C.silver.b)
    motdNote:SetPoint("LEFT", motdBtn, "RIGHT", 10, 0)

    -- Guild Info
    local infoLabel = UI:CreateHeaderText(panel, L["GUILD INFORMATION"], 11)
    infoLabel:SetPoint("TOPLEFT", 2, -122)

    local infoBox = MakeTextArea(panel, 120)
    infoBox:SetPoint("TOPLEFT", 2, -142)
    infoBox:SetPoint("TOPRIGHT", -12, -142)
    infoBox:SetMaxLetters(500)

    local infoBtn = UI:CreateButton(panel, L["Save Info"], 110, 24)
    infoBtn:SetPoint("TOPLEFT", 2, -270)
    infoBtn:SetScript("OnClick", function()
        BRutus.GuildManager:SetGuildInfo(infoBox:GetText())
        infoBox:ClearFocus()
    end)

    local infoNote = UI:CreateText(panel, "", 9, C.silver.r, C.silver.g, C.silver.b)
    infoNote:SetPoint("LEFT", infoBtn, "RIGHT", 10, 0)

    return function()
        local GM = BRutus.GuildManager
        if not motdBox:HasFocus() then motdBox:SetText(GM:GetMOTD()) end
        if not infoBox:HasFocus() then infoBox:SetText(GM:GetGuildInfo()) end

        local canMotd = GM:CanSetMOTD()
        if canMotd then motdBox:Enable() else motdBox:Disable() end
        motdBtn:SetShown(canMotd)
        motdNote:SetText(canMotd and "" or L["|cff888888No permission to edit the MOTD.|r"])

        local canInfo = GM:CanSetGuildInfo()
        if canInfo then infoBox:Enable() else infoBox:Disable() end
        infoBtn:SetShown(canInfo)
        infoNote:SetText(canInfo and "" or L["|cff888888No permission to edit the info.|r"])
    end
end

----------------------------------------------------------------------
-- ACTION LOG sub-panel
----------------------------------------------------------------------
local ACTION_LABELS = {
    promote = { txt = L["Promoted"], color = "green" },
    demote  = { txt = L["Demoted"],  color = "gold" },
    kick    = { txt = L["Removed"],  color = "red" },
    motd    = { txt = L["MOTD"],     color = "accent" },
    info    = { txt = L["Info"],     color = "accent" },
    join    = { txt = L["Joined"], color = "online" },
    leave   = { txt = L["Left"],   color = "offline" },
}

local function BuildLogSub(panel)
    local clearBtn = UI:CreateButton(panel, L["Clear"], 80, 22)
    clearBtn:SetPoint("TOPLEFT", 2, -2)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -30)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtLogScroll")

    local refresh
    refresh = function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local entries = BRutus.GuildManager:GetLog()
        local yOff = 0
        for idx, e in ipairs(entries) do
            local row = MakeRow(content, yOff, idx)

            local whenFS = UI:CreateText(row, date("%m/%d %H:%M", e.timestamp or 0), 9, C.textDim.r, C.textDim.g, C.textDim.b)
            whenFS:SetPoint("LEFT", 8, 0)

            local meta = ACTION_LABELS[e.action] or { txt = e.action or "?", color = "silver" }
            local col = C[meta.color] or C.silver
            local actFS = UI:CreateText(row, meta.txt, 10, col.r, col.g, col.b)
            actFS:SetPoint("LEFT", 90, 0)

            local tgt = e.target and ("|cffFFD700" .. e.target .. "|r ") or ""
            local detail = e.detail and tostring(e.detail) or ""
            local descFS = UI:CreateText(row, tgt .. detail, 10, C.silver.r, C.silver.g, C.silver.b)
            descFS:SetPoint("LEFT", 170, 0)
            descFS:SetWidth(content:GetWidth() - 320)
            descFS:SetJustifyH("LEFT")
            descFS:SetWordWrap(false)

            local byFS = UI:CreateText(row, L["by "] .. (e.author or "?"), 9, C.textDim.r, C.textDim.g, C.textDim.b)
            byFS:SetPoint("RIGHT", -10, 0)

            yOff = yOff + ROW_H + 2
        end

        if #entries == 0 then
            local empty = UI:CreateText(content, L["No actions logged yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end

    clearBtn:SetScript("OnClick", function()
        BRutus.GuildManager:ClearLog()
        refresh()
    end)

    if BRutus.RosterLog then BRutus.RosterLog.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- BAN LIST sub-panel — officer blacklist (add / search / remove)
----------------------------------------------------------------------
local function BuildBanSub(panel)
    -- Header + one-line context
    local header = UI:CreateHeaderText(panel, L["BANNED PLAYERS"], 11)
    header:SetPoint("TOPLEFT", 2, -4)
    local hint = UI:CreateText(panel,
        L["Blocked from auto-invite. You're alerted when a banned player rejoins the guild or whispers you."],
        9, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 2, -22)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -22)
    hint:SetJustifyH("LEFT")

    -- Add form, row 1: player + reason
    local playerLbl = UI:CreateText(panel, L["Player"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
    playerLbl:SetPoint("TOPLEFT", 4, -52)
    local nameBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    nameBox:SetSize(140, 22); nameBox:SetPoint("LEFT", playerLbl, "RIGHT", 8, 0)
    nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    local reasonLbl = UI:CreateText(panel, L["Reason"], 11, C.textDim.r, C.textDim.g, C.textDim.b)
    reasonLbl:SetPoint("LEFT", nameBox, "RIGHT", 16, 0)
    local reasonBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    reasonBox:SetSize(210, 22); reasonBox:SetPoint("LEFT", reasonLbl, "RIGHT", 8, 0)
    reasonBox:SetAutoFocus(false); reasonBox:SetMaxLetters(80)
    reasonBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    -- Add form, row 2: temporary toggle (+days) and the Ban button
    local tempChk = UI:CreateCheckbox(panel, L["Temporary"], 18)
    tempChk:SetPoint("TOPLEFT", 4, -84)
    local daysBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    daysBox:SetSize(42, 20); daysBox:SetPoint("LEFT", tempChk, "LEFT", 104, 0)
    daysBox:SetAutoFocus(false); daysBox:SetNumeric(true); daysBox:SetMaxLetters(4)
    daysBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    local daysLbl = UI:CreateText(panel, L["days"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
    daysLbl:SetPoint("LEFT", daysBox, "RIGHT", 6, 0)
    daysBox:Hide(); daysLbl:Hide()
    tempChk.checkbox.onChanged = function(_, checked)
        daysBox:SetShown(checked); daysLbl:SetShown(checked)
        if not checked then daysBox:SetText("") end
    end

    local banBtn = UI:CreateButton(panel, L["Ban player"], 110, 24)
    banBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -82)

    local function doAdd()
        local n = strtrim(nameBox:GetText())
        if n == "" or not BRutus.BanList then return end
        if tempChk.checkbox:GetChecked() then
            local d = tonumber(strtrim(daysBox:GetText() or ""))
            if not d or d <= 0 then
                BRutus:Print(L["Enter a positive number of days for a temporary ban."])
                return
            end
            BRutus.BanList:Add(n, reasonBox:GetText(), d * 86400)
        else
            BRutus.BanList:Add(n, reasonBox:GetText())
        end
        nameBox:SetText(""); reasonBox:SetText(""); daysBox:SetText("")
        nameBox:ClearFocus(); reasonBox:ClearFocus(); daysBox:ClearFocus()
    end
    banBtn:SetScript("OnClick", doAdd)
    nameBox:SetScript("OnEnterPressed", doAdd)
    reasonBox:SetScript("OnEnterPressed", doAdd)
    daysBox:SetScript("OnEnterPressed", doAdd)

    -- Divider between the form and the list
    local sep = UI:CreateSeparator(panel)
    sep:SetPoint("TOPLEFT", 2, -114)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -114)

    -- Filter + column headers
    local filterLbl = UI:CreateText(panel, L["Filter"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
    filterLbl:SetPoint("TOPLEFT", 4, -128)
    local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetSize(180, 20); searchBox:SetPoint("LEFT", filterLbl, "RIGHT", 8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    local function colHeader(text, x)
        local fs = UI:CreateText(panel, text, 9, C.textDim.r, C.textDim.g, C.textDim.b)
        fs:SetPoint("TOPLEFT", x, -152)
    end
    colHeader(L["PLAYER"], 8)
    colHeader(L["REASON"], 160)
    colHeader(L["BY"], 340)
    colHeader(L["EXPIRES"], 430)

    -- List
    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 4, -168)
    listHolder:SetPoint("BOTTOMRIGHT", -4, 4)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtBanScroll")

    local function cell(text, x, w, y, r, g, b)
        local fs = UI:CreateText(content, text, 11, r, g, b)
        fs:SetPoint("TOPLEFT", x, -y)
        fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    end

    local function refresh()
        for _, c in pairs({ content:GetChildren() }) do c:Hide() end
        for _, r in pairs({ content:GetRegions() }) do r:Hide() end
        content:SetWidth(listHolder:GetWidth() - 4)
        local filter = strtrim(searchBox:GetText() or ""):lower()
        local now = GetServerTime()
        local list = BRutus.BanList and BRutus.BanList:List() or {}
        local y = 0
        for _, e in ipairs(list) do
            if filter == "" or (e.name or ""):lower():find(filter, 1, true) then
                local expired = e.expiry and e.expiry <= now
                local nr, ng, nb = C.red.r, C.red.g, C.red.b
                local expTxt
                if not e.expiry then
                    expTxt = L["permanent"]
                elseif expired then
                    expTxt = L["(expired)"]
                    nr, ng, nb = C.silver.r, C.silver.g, C.silver.b
                else
                    expTxt = date("%m/%d/%y", e.expiry)
                end
                cell(e.name or "?", 4, 148, y, nr, ng, nb)
                cell(e.reason or "", 156, 176, y, C.text.r, C.text.g, C.text.b)
                cell(e.author or "?", 336, 86, y, C.textDim.r, C.textDim.g, C.textDim.b)
                cell(expTxt, 426, 82, y, C.textDim.r, C.textDim.g, C.textDim.b)
                local del = UI:CreateButton(content, "\195\151", 22, 18)  -- ×
                del:SetPoint("TOPRIGHT", -4, -y)
                local nm = e.name
                del:SetScript("OnClick", function() if BRutus.BanList then BRutus.BanList:Remove(nm) end end)
                y = y + ROW_H
            end
        end
        if y == 0 then
            local empty = UI:CreateText(content,
                L["No banned players yet. Add one above to block them."],
                11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, y))
    end

    searchBox:SetScript("OnTextChanged", refresh)
    -- let sync / mutations repaint this tab
    if BRutus.BanList then BRutus.BanList.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- ENGAGEMENT sub-panel — recruitment activity per member (officer analytics).
-- Thin renderer over RecruitEngagement:GetAggregate; no logic of consequence
-- lives here (Rule 10). "Joined" is confirmed direct-invite credit only, so a
-- member who merely posts in a channel shows effort (Posts) without joins.
----------------------------------------------------------------------
-- Signed count for a trend delta ("+12" / "-3" / "0").
local function signedDelta(n)
    return (n > 0 and "+" .. n) or tostring(n)
end

local SPARK_BARS   = 7    -- one bar per day
local SPARK_BAR_W  = 7
local SPARK_STEP   = 9    -- bar width + gap
local SPARK_H      = 12   -- max bar height in px

-- Present a member's status from the two fields the data carries.
local function statusOf(r, now)
    if not r.part then return L["Off"], C.textDim end
    if r.last == 0 or (now - r.last) > 48 * 3600 then return L["Paused"], C.silver end
    return L["Active"], C.green
end

local function BuildEngageSub(panel)
    local totalsFS = UI:CreateText(panel, "", 11, C.gold.r, C.gold.g, C.gold.b)
    totalsFS:SetPoint("TOPLEFT", 2, -4)

    local trendFS = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    trendFS:SetPoint("TOPLEFT", 2, -22)

    -- Invite sparkline as texture bars (glyph blocks do not render in FRIZQT).
    -- One bar per day, oldest on the left, newest on the right; heights scaled
    -- to the busiest day. Anchored just right of the trend text.
    local sparkFrame = CreateFrame("Frame", nil, panel)
    sparkFrame:SetSize(SPARK_BARS * SPARK_STEP, SPARK_H)
    sparkFrame:SetPoint("LEFT", trendFS, "RIGHT", 10, 0)
    local sparkBars = {}
    for i = 1, SPARK_BARS do
        local tex = sparkFrame:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(WHITE)
        tex:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.9)
        tex:SetPoint("BOTTOMLEFT", (i - 1) * SPARK_STEP, 0)
        tex:SetSize(SPARK_BAR_W, 1)
        sparkBars[i] = tex
    end

    -- Fixed column header (aligns with the row x-offsets below).
    local COLS = { name = 8, status = 150, posts = 280, invites = 350, joined = 430, last = 510 }
    local function headerAt(text, x)
        local fs = UI:CreateText(panel, text, 9, C.silver.r, C.silver.g, C.silver.b)
        fs:SetPoint("TOPLEFT", x, -42)
        return fs
    end
    headerAt(L["MEMBER"], COLS.name)
    headerAt(L["STATUS"], COLS.status)
    headerAt(L["POSTS"], COLS.posts)
    headerAt(L["INVITES"], COLS.invites)
    headerAt(L["JOINED"], COLS.joined)
    headerAt(L["LAST"], COLS.last)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -58)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtEngageScroll")

    local refresh
    refresh = function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)

        local agg = (BRutus.RecruitEngagement and BRutus.RecruitEngagement:GetAggregate())
            or { rows = {}, totals = { posts7 = 0, invites7 = 0, joins7 = 0, conv = 0,
                                       postsPrev = 0, invitesPrev = 0, joinsPrev = 0 } }
        local t = agg.totals
        local now = time()

        totalsFS:SetText(format(L["Guild: Posts %d  Invites %d  Joined %d  Conv %d%%"],
            t.posts7, t.invites7, t.joins7, math.floor((t.conv or 0) * 100 + 0.5)))

        trendFS:SetText(format(L["vs last week: invites %s, joins %s"],
            signedDelta(t.invites7 - t.invitesPrev), signedDelta(t.joins7 - t.joinsPrev)))

        -- Guild daily invites summed across members, drive the sparkline bars.
        local gd = { 0, 0, 0, 0, 0, 0, 0 }
        for _, r in ipairs(agg.rows) do
            local di = r.dailyInvites or {}
            for i = 1, 7 do gd[i] = gd[i] + (di[i] or 0) end
        end
        local maxv = 0
        for i = 1, 7 do if gd[i] > maxv then maxv = gd[i] end end
        for i = 1, SPARK_BARS do
            local v = gd[8 - i] or 0   -- bar 1 = 6 days ago (gd[7]); bar 7 = today (gd[1])
            local h = (maxv > 0) and math.max(1, math.floor((v / maxv) * SPARK_H + 0.5)) or 1
            sparkBars[i]:SetHeight(h)
        end

        local yOff = 0
        for idx, r in ipairs(agg.rows) do
            local row = MakeRow(content, yOff, idx)
            local nameColor = r.stale and C.textDim or C.text

            local nameFS = UI:CreateText(row, r.name, 11, nameColor.r, nameColor.g, nameColor.b)
            nameFS:SetPoint("LEFT", COLS.name, 0)

            local sText, sColor = statusOf(r, now)
            local statusFS = UI:CreateText(row, sText, 10, sColor.r, sColor.g, sColor.b)
            statusFS:SetPoint("LEFT", COLS.status, 0)

            local function numFS(val, x, color)
                local fs = UI:CreateText(row, tostring(val), 10, color.r, color.g, color.b)
                fs:SetPoint("LEFT", x, 0)
            end
            numFS(r.posts7, COLS.posts, C.text)
            numFS(r.invites7, COLS.invites, C.text)
            numFS(r.joins7, COLS.joined, r.joins7 > 0 and C.green or C.textDim)

            local lastFS = UI:CreateText(row, BRutus:TimeAgo(r.last), 10, C.textDim.r, C.textDim.g, C.textDim.b)
            lastFS:SetPoint("LEFT", COLS.last, 0)

            yOff = yOff + ROW_H + 2
        end

        if #agg.rows == 0 then
            local empty = UI:CreateText(content, L["No recruitment activity yet."],
                11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end

    -- Repaint when a fresh self-report arrives (RecruitEngagement:HandleStats).
    BRutus.recruitEngagementRefresh = refresh
    return refresh
end

----------------------------------------------------------------------
-- PRESETS sub-panel — built-in bulk-moderation presets (officer-only).
-- Thin renderer over BRutus.ModPresets: each preset shows its criteria, a
-- live match count, threshold editors, Preview (inline member list) and
-- Apply. No matching / apply logic lives here (Rule 10). Apply confirms
-- first, then routes each rank/kick through ModPresets:ApplyPreset, whose
-- protected handoffs open Blizzard's native panel (ADR-0010).
----------------------------------------------------------------------
-- Per-type threshold editor fields { key, label, rank? } for the UI.
local PRESET_FIELDS = {
    purge_inactive   = { { key = "days",         label = L["inactive days"] },
                         { key = "minRankIndex", label = L["min rank"], rank = true } },
    promote_regulars = { { key = "minAttendance", label = L["min attendance %"] } },
    trial_cleanup    = { { key = "minDays",       label = L["trial days"] },
                         { key = "maxAttendance", label = L["max attendance %"] } },
}

-- Apply confirmation text: heading + affected members (capped) + the
-- Blizzard-protected note. Presentation only.
local function presetApplyText(preset, matches)
    local MP = BRutus.ModPresets
    local action = MP:GetAction(preset)
    local CAP = 10
    local names = {}
    for i, m in ipairs(matches) do
        if i > CAP then break end
        names[#names + 1] = m.name
    end
    local list = table.concat(names, ", ")
    if #matches > CAP then
        list = list .. " " .. format(L["and %d more"], #matches - CAP)
    end
    local line = (action == "promote")
        and format(L["Promote %d member(s):"], #matches)
        or  format(L["Remove %d member(s) from the guild:"], #matches)
    return format(L["Apply preset \"%s\"?"], preset.name or "?") .. "\n"
        .. line .. " " .. list .. "\n\n"
        .. L["Rank and removal actions are Blizzard-protected: the guild panel opens to confirm each."]
end

local function BuildPresetsSub(panel)
    panel.expanded = {}
    panel.showChooser = false

    local title = UI:CreateHeaderText(panel, L["MODERATION PRESETS"], 11)
    title:SetPoint("TOPLEFT", 2, -4)

    local newBtn = UI:CreateButton(panel, L["+ New"], 80, 22)
    newBtn:SetPoint("TOPRIGHT", -12, -2)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -30)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtPresetsScroll")

    -- Small numeric threshold editor; commits to ModPresets then repaints.
    local function makeNumBox(parent, value, onCommit)
        local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        box:SetSize(40, 20)
        box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        box:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 1)
        box:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
        box:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        box:SetTextColor(C.white.r, C.white.g, C.white.b)
        box:SetJustifyH("CENTER")
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(4)
        box:SetText(tostring(value or 0))
        box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(s)
            onCommit(tonumber(s:GetText()))
            s:ClearFocus()
        end)
        return box
    end

    local refresh
    refresh = function()
        content:SetWidth(listHolder:GetWidth() - 12)
        ClearContent(content)
        for _, r in pairs({ content:GetRegions() }) do r:Hide() end

        local MP = BRutus.ModPresets
        local presets = (MP and MP:GetPresets()) or {}
        local yOff = 0

        -- "+ New" chooser: a labelled row of the built-in type buttons.
        if panel.showChooser and MP then
            local chooser = CreateFrame("Frame", nil, content)
            chooser:SetSize(content:GetWidth() - 4, ROW_H)
            chooser:SetPoint("TOPLEFT", 0, -yOff)
            local lbl = UI:CreateText(chooser, L["Add preset:"], 10, C.gold.r, C.gold.g, C.gold.b)
            lbl:SetPoint("LEFT", 8, 0)
            local bx = 96
            for _, key in ipairs(MP.TYPE_ORDER) do
                local info = MP.TYPES[key]
                local b = UI:CreateButton(chooser, info.name, 130, 20)
                b:SetPoint("LEFT", bx, 0)
                b:SetScript("OnClick", function()
                    if MP:AddPreset(key) then
                        panel.showChooser = false
                        refresh()
                    end
                end)
                bx = bx + 136
            end
            yOff = yOff + ROW_H + 4
        end

        if #presets == 0 and not panel.showChooser then
            local empty = UI:CreateText(content, L["No presets yet. Use [+ New] to add one."],
                11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -(yOff + 4))
            content:SetHeight(math.max(1, yOff + ROW_H))
            return
        end

        for idx, preset in ipairs(presets) do
            local matches = (MP and MP:GetMatches(preset)) or {}
            local expanded = panel.expanded[idx]

            -- Height: header line + controls line (+ preview rows when open).
            local blockH = ROW_H + 24
            if expanded then blockH = blockH + math.max(1, #matches) * 18 + 4 end
            local block = CreateFrame("Frame", nil, content, "BackdropTemplate")
            block:SetSize(content:GetWidth() - 4, blockH)
            block:SetPoint("TOPLEFT", 0, -yOff)
            block:SetBackdrop({ bgFile = WHITE })
            local alt = (idx % 2 == 0) and C.row1 or C.row2
            block:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)

            -- Header line: name + criteria summary + remove.
            local nameFS = UI:CreateText(block, preset.name or "?", 12, C.gold.r, C.gold.g, C.gold.b)
            nameFS:SetPoint("TOPLEFT", 8, -5)
            local sumFS = UI:CreateText(block, MP:Summarize(preset), 10, C.silver.r, C.silver.g, C.silver.b)
            sumFS:SetPoint("TOPLEFT", 168, -6)

            local delBtn = UI:CreateButton(block, "\195\151", 22, 18)  -- ×
            delBtn:SetPoint("TOPRIGHT", -8, -4)
            delBtn:SetScript("OnClick", function()
                if MP:RemovePreset(idx) then
                    panel.expanded[idx] = nil
                    refresh()
                end
            end)

            -- Controls line: threshold editors, match count, Preview, Apply.
            local cy = -(ROW_H + 2)
            local x = 8
            for _, field in ipairs(PRESET_FIELDS[preset.type] or {}) do
                local flbl = UI:CreateText(block, field.label, 9, C.textDim.r, C.textDim.g, C.textDim.b)
                flbl:SetPoint("TOPLEFT", x, cy - 2)
                x = x + flbl:GetStringWidth() + 6
                local fieldKey = field.key
                local box = makeNumBox(block, preset.thresholds and preset.thresholds[fieldKey], function(v)
                    if MP:SetThreshold(idx, fieldKey, v) then refresh() end
                end)
                box:SetPoint("TOPLEFT", x, cy)
                x = x + 46
                if field.rank then
                    local rn = (BRutus.GuildManager and BRutus.GuildManager:GetRankName(
                        preset.thresholds and preset.thresholds[fieldKey] or 0)) or "?"
                    local rnFS = UI:CreateText(block, "(" .. rn .. ")", 9, C.silver.r, C.silver.g, C.silver.b)
                    rnFS:SetPoint("TOPLEFT", x, cy - 2)
                    x = x + rnFS:GetStringWidth() + 10
                end
            end

            local countFS = UI:CreateText(block, format(L["%d match"], #matches), 10, C.gold.r, C.gold.g, C.gold.b)
            countFS:SetPoint("TOPLEFT", math.max(x + 8, 320), cy - 2)

            local applyBtn = UI:CreateButton(block, L["Apply"], 70, 20)
            applyBtn:SetPoint("TOPRIGHT", -8, cy)
            applyBtn:SetScript("OnClick", function()
                if not BRutus:IsOfficer() then BRutus:Print(L["Officers only."]) return end
                local live = MP:GetMatches(preset)
                if #live == 0 then BRutus:Print(L["No members match this preset."]) return end
                StaticPopup_Show("GUILDOS_MODPRESET_APPLY", presetApplyText(preset, live), nil,
                    { preset = preset, matches = live })
            end)

            local prevBtn = UI:CreateButton(block, L["Preview"], 70, 20)
            prevBtn:SetPoint("TOPRIGHT", applyBtn, "TOPLEFT", -6, 0)
            prevBtn:SetScript("OnClick", function()
                panel.expanded[idx] = not panel.expanded[idx]
                refresh()
            end)

            -- Inline preview list.
            if expanded then
                local py = ROW_H + 24
                if #matches == 0 then
                    local none = UI:CreateText(block, L["No members match this preset."],
                        9, C.silver.r, C.silver.g, C.silver.b)
                    none:SetPoint("TOPLEFT", 16, -py)
                else
                    for _, m in ipairs(matches) do
                        local mFS = UI:CreateText(block,
                            "\226\128\162 " .. m.name .. "  |cff888888" .. (m.detail or "") .. "|r",
                            9, C.text.r, C.text.g, C.text.b)
                        mFS:SetPoint("TOPLEFT", 16, -py)
                        py = py + 18
                    end
                end
            end

            yOff = yOff + blockH + 4
        end

        content:SetHeight(math.max(1, yOff))
    end

    newBtn:SetScript("OnClick", function()
        panel.showChooser = not panel.showChooser
        refresh()
    end)

    if BRutus.ModPresets then BRutus.ModPresets.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- Panel assembly
----------------------------------------------------------------------
function BRutus:CreateManagementPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "ranks"

    -- Sub-tab bar
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetPoint("TOPRIGHT", -10, -8)
    bar:SetHeight(26)

    local subTabBtns = {}

    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do
            info.panel:SetShown(k == key)
        end
        for k, btn in pairs(subTabBtns) do
            btn:SetActive(k == key)
        end
        local info = parent.subPanels[key]
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
    end

    -- Refresh whatever sub-panel is currently visible (used by GuildManager).
    parent.RefreshActive = function()
        local info = parent.subPanels[parent.activeSub]
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
    end

    local x = 0
    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 116)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + 120
    end

    -- One content panel per sub-tab, all sharing the area below the bar.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", 12, -42)
        p:SetPoint("BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end

    local builders = {
        ranks    = BuildRanksSub,
        inactive = BuildInactiveSub,
        suggest  = BuildSuggestSub,
        motd     = BuildMotdSub,
        log      = BuildLogSub,
        ban      = BuildBanSub,
        engage   = BuildEngageSub,
        presets  = BuildPresetsSub,
    }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        local refresh = builders[t.key](p)
        parent.subPanels[t.key] = { panel = p, refresh = refresh }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "ranks")
    end)
end
