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
}

local ROW_H = 26

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
