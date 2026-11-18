----------------------------------------------------------------------
-- Guild OS - Management Panel (Leadership Suite UI)
-- The "Lideran\195\167a" tab: rank management, inactivity report, promotion /
-- trial suggestions, MOTD / Guild Info editing, and the action log.
-- Visual layout only — all data and actions go through GuildOS.GuildManager
-- (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
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
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 70    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab

-- The shared spacing (#371), read as numbers: a test that stubs GuildOS.UI hands back functions.
local GAP = tonumber(UI.GAP) or 8
local GUTTER = tonumber(UI.SCROLL_GUTTER) or 12
local SECTION_ABOVE = 20   -- room over a later section title for the rule drawn 12px above it
local TITLE_H = 24         -- a section title and the gap under it

-- A colour token as the hex an inline |c code takes (#371).
local function hex(c)
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- Confirmation dialog for a bulk Apply. The full, already-formatted message
-- is passed as text arg1 ("%s"); OnAccept runs the officer-gated ApplyPreset
-- on exactly the members captured when Apply was clicked. Rank/kick handoffs
-- inside ApplyPreset open Blizzard's native panel (ADR-0010) — no protected
-- call is made from this insecure OnAccept.
GuildOS.Dialogs["GUILDOS_MODPRESET_APPLY"] = {
    text = "%s",
    button1 = L["Apply"],
    button2 = L["Cancel"],
    OnAccept = function(_, data)
        if data and data.preset and GuildOS.ModPresets then
            GuildOS.ModPresets:ApplyPreset(data.preset, data.matches)
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
-- A scroll frame + content child that fills its parent panel. It reaches the scroll gutter past the
-- panel's right edge: the child stops that gutter short (BindScrollChildWidth), so the rows end where
-- the screen's other lines do and the bar sits in the margin, never over a row's buttons (#371).
local function MakeScrollList(panel, name)
    local scroll = CreateFrame("ScrollFrame", name, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", GUTTER, 0)
    UI:SkinScrollBar(scroll, name)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    UI:BindScrollChildWidth(scroll, content)
    return scroll, content
end

-- A striped row frame parented to `content`. All text/widgets must be created
-- on the returned frame so a single Hide() clears the row on refresh.
-- Held by both sides, not sized from content:GetWidth(): a list built while its tab is hidden reads a
-- width of 0, and rows sized from it came out negative and invisible (Ranks showed nothing, #371).
local function MakeRow(content, yOff, index, height)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetHeight(height or ROW_H)
    row:SetPoint("TOPLEFT", 0, -yOff)
    row:SetPoint("TOPRIGHT", 0, -yOff)
    row:SetBackdrop({ bgFile = WHITE })
    local alt = (index % 2 == 0) and C.row1 or C.row2
    row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
    return row
end

-- A group of rows' title, parented to `content`: the shared section title, not a filled band (#371).
-- Held by a strip across the list, so its rule reaches the right edge and a ClearContent hides both.
-- `first`: the list's first title, with no rule; a later one wants SECTION_ABOVE over it.
local function MakeSectionHeader(content, text, yOff, first)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(18)
    f:SetPoint("TOPLEFT", 0, -yOff)
    f:SetPoint("TOPRIGHT", 0, -yOff)
    local lbl = UI:CreateSectionTitle(f, text, first)
    lbl:SetPoint("TOPLEFT", 0, 0)
    return f
end

-- A table's column labels on the shared header row (#371): mono labels, no fill, a rule under them.
-- cols: { { text, x }, ... }. Anchored by its top corners at `y` on `parent`.
local function MakeTableHeader(parent, cols, y)
    local header = UI:CreateTableHeader(parent)
    header:SetPoint("TOPLEFT", 0, -y)
    header:SetPoint("TOPRIGHT", 0, -y)
    for _, col in ipairs(cols) do
        local fs = UI:CreateHeaderText(header, col[1], 10)
        fs:SetPoint("LEFT", col[2], 0)
    end
    return header
end

-- Clear all (frame) children of a content holder before a rebuild.
local function ClearContent(content)
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
end

----------------------------------------------------------------------
-- RANKS sub-panel — promote / demote roster members
----------------------------------------------------------------------
-- A list that draws only the rows that fit, as Members and Professions do (FauxScrollFrame): one frame per
-- visible line, refilled from `data` on every scroll and refresh. Ranks built the whole guild row by row:
-- a 26,000px scroll child the client did not draw at all, and each roster update stacked another 943
-- frames on it (3,764 after four, #371). createRow(parent) makes a row's parts once; fillRow(row, item, i)
-- writes an item into it.
local function MakeVirtualList(holder, name, rowStep, createRow, fillRow)
    local scroll = CreateFrame("ScrollFrame", name, holder, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", GUTTER, 0)   -- the bar in the margin, past the rows' right edge
    UI:SkinScrollBar(scroll, name)
    local list = { data = {}, rows = {} }
    function list:Update()
        local shown = math.max(0, math.floor((holder:GetHeight() or 0) / rowStep))
        for i = #self.rows + 1, shown do
            local row = createRow(holder)
            row:SetPoint("TOPLEFT", 0, -((i - 1) * rowStep))
            row:SetPoint("TOPRIGHT", 0, -((i - 1) * rowStep))
            self.rows[i] = row
        end
        FauxScrollFrame_Update(scroll, #self.data, shown, rowStep)
        local offset = FauxScrollFrame_GetOffset(scroll) or 0
        for i, row in ipairs(self.rows) do
            local item = i <= shown and self.data[offset + i]
            if item then
                fillRow(row, item, offset + i)
                row:Show()
            else
                row:Hide()
            end
        end
    end
    function list:SetData(data)
        self.data = data or {}
        self:Update()
    end
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, rowStep, function() list:Update() end)
    end)
    holder:HookScript("OnSizeChanged", function() list:Update() end)
    return list
end

local function BuildRanksSub(panel)
    local note = UI:CreateText(panel,
        L["Rank changes are Blizzard-protected: the arrow buttons open the official guild panel for you to confirm."],
        11, C.silver.r, C.silver.g, C.silver.b)
    note:SetPoint("TOPLEFT", 0, 0)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(14 + GAP))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)

    local empty = UI:CreateText(listHolder, L["Roster empty or unavailable."], 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)
    empty:Hide()

    local function createRow(parent)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = WHITE })
        row.nameFS = UI:CreateText(row, "", 11)
        row.nameFS:SetPoint("LEFT", 8, 0)
        row.rankFS = UI:CreateText(row, "", 10, C.silver.r, C.silver.g, C.silver.b)
        row.rankFS:SetPoint("LEFT", 180, 0)
        row.lvlFS = UI:CreateText(row, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lvlFS:SetPoint("LEFT", 340, 0)
        -- Demote one step (higher rankIndex), promote one (lower). Shown where the rank may.
        row.downBtn = UI:CreateButton(row, "|TInterface\\BUTTONS\\Arrow-Down-Up:14:14|t", 26, 18)
        row.downBtn:SetPoint("RIGHT", -8, 0)
        row.downBtn:SetScript("OnClick", function()
            GuildOS.GuildManager:Demote(row.member.fullName)
            GuildOS.GuildManager:RefreshUI()
        end)
        row.upBtn = UI:CreateButton(row, "|TInterface\\BUTTONS\\Arrow-Up-Up:14:14|t", 26, 18)
        row.upBtn:SetPoint("RIGHT", -38, 0)
        row.upBtn:SetScript("OnClick", function()
            GuildOS.GuildManager:Promote(row.member.fullName)
            GuildOS.GuildManager:RefreshUI()
        end)
        return row
    end

    local canPromote, canDemote = false, false
    local function fillRow(row, m, idx)
        row.member = m
        local alt = (idx % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        local cr, cg, cb = GuildOS:GetClassColor(m.class)
        local dim = m.online and 1 or 0.55
        row.nameFS:SetText(m.name)
        row.nameFS:SetTextColor(cr * dim, cg * dim, cb * dim)
        row.rankFS:SetText(m.rankName)
        row.lvlFS:SetText(L["Lv "] .. m.level)
        row.downBtn:SetShown(canDemote)
        row.upBtn:SetShown(canPromote)
    end

    local list = MakeVirtualList(listHolder, "GuildOSMgmtRanksScroll", ROW_H + 2, createRow, fillRow)

    return function()
        local GM = GuildOS.GuildManager
        canPromote = GM:CanPromote() and true or false
        canDemote = GM:CanDemote() and true or false

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

        empty:SetShown(#members == 0)
        list:SetData(members)
    end
end

----------------------------------------------------------------------
-- INACTIVITY sub-panel — purge candidates
----------------------------------------------------------------------
local function BuildInactiveSub(panel)
    panel.threshold = GuildOS.GuildManager.DEFAULT_INACTIVE_DAYS

    local lbl = UI:CreateText(panel, L["Inactive for more than"], 11, C.text.r, C.text.g, C.text.b)
    lbl:SetPoint("TOPLEFT", 0, -4)

    local daysBox = UI:CreateInput(panel, 44, 22, { numeric = true, max = 4, justify = "CENTER" })   -- #371
    daysBox:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    daysBox:SetText(tostring(panel.threshold))

    local daysLbl = UI:CreateText(panel, L["days"], 11, C.text.r, C.text.g, C.text.b)
    daysLbl:SetPoint("LEFT", daysBox, "RIGHT", 6, 0)

    -- How many matched: secondary text, not gold (#371).
    local summary = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    summary:SetPoint("LEFT", daysLbl, "RIGHT", 16, 0)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(22 + GAP + 2))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    -- Drawn as Ranks is (MakeVirtualList): only the rows that fit, refilled on scroll (#371).
    local empty = UI:CreateText(listHolder, L["No inactive members in this period."], 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)
    empty:Hide()

    local canKick = false
    local function createRow(parent)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = WHITE })
        row.nameFS = UI:CreateText(row, "", 11)
        row.nameFS:SetPoint("LEFT", 8, 0)
        row.rankFS = UI:CreateText(row, "", 10, C.silver.r, C.silver.g, C.silver.b)
        row.rankFS:SetPoint("LEFT", 180, 0)
        row.lvlFS = UI:CreateText(row, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lvlFS:SetPoint("LEFT", 320, 0)
        row.daysFS = UI:CreateText(row, "", 10)
        row.daysFS:SetPoint("LEFT", 390, 0)
        row.kickBtn = UI:CreateButton(row, L["Remove"], 70, 18)
        row.kickBtn:SetPoint("RIGHT", -8, 0)
        row.kickBtn:SetScript("OnClick", function()
            GuildOS.GuildManager:ConfirmKick(row.member.fullName)
        end)
        return row
    end
    local function fillRow(row, m, idx)
        row.member = m
        local alt = (idx % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        local cr, cg, cb = GuildOS:GetClassColor(m.class)
        row.nameFS:SetText(m.name)
        row.nameFS:SetTextColor(cr, cg, cb)
        row.rankFS:SetText(m.rankName or "?")
        row.lvlFS:SetText(L["Lv "] .. m.level)
        -- Status: long gone is `danger`, gone a while `warn` (gold is no status colour, #371).
        local daysColor = m.daysOffline >= 60 and C.red or C.warn
        row.daysFS:SetText(m.daysOffline .. L["d offline"])
        row.daysFS:SetTextColor(daysColor.r, daysColor.g, daysColor.b)
        row.kickBtn:SetShown(canKick)
    end
    local rows = MakeVirtualList(listHolder, "GuildOSMgmtInactiveScroll", ROW_H + 2, createRow, fillRow)

    local refresh
    refresh = function()
        local GM = GuildOS.GuildManager
        canKick = GM:CanKick() and true or false
        local list = GM:GetInactiveMembers(panel.threshold)
        summary:SetText(format(L["%d member(s)"], #list))
        empty:SetShown(#list == 0)
        rows:SetData(list)
    end

    local function apply()
        local v = tonumber(daysBox:GetText()) or GuildOS.GuildManager.DEFAULT_INACTIVE_DAYS
        if v < 1 then v = 1 end
        panel.threshold = v
        daysBox:ClearFocus()
        refresh()
    end
    daysBox:SetScript("OnEnterPressed", apply)   -- Escape is the field's own (UI:CreateInput)

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
        ClearContent(content)

        local data = GuildOS.GuildManager:GetSuggestions()
        local yOff = 0

        -- Trials ready for a decision
        MakeSectionHeader(content, format(L["TRIALS READY FOR DECISION  (%d)"], #data.trialsReady), yOff, true)
        yOff = yOff + TITLE_H
        if #data.trialsReady == 0 then
            local none = MakeRow(content, yOff, 1)
            local fs = UI:CreateText(none, L["No trials due."], 10, C.silver.r, C.silver.g, C.silver.b)
            fs:SetPoint("LEFT", 8, 0)
            yOff = yOff + ROW_H + 2
        else
            for idx, t in ipairs(data.trialsReady) do
                local row = MakeRow(content, yOff, idx)
                local nameFS = UI:CreateText(row, t.name, 11, C.text.r, C.text.g, C.text.b)
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
                    GuildOS.TrialTracker:UpdateStatus(key, GuildOS.TrialTracker.STATUS.DENIED)
                    refresh()
                end)

                local okBtn = UI:CreateButton(row, L["Approve"], 64, 18)
                okBtn:SetPoint("RIGHT", denyBtn, "LEFT", -4, 0)
                okBtn:SetScript("OnClick", function()
                    GuildOS.TrialTracker:UpdateStatus(key, GuildOS.TrialTracker.STATUS.APPROVED)
                    refresh()
                end)

                yOff = yOff + ROW_H + 2
            end
        end

        yOff = yOff + SECTION_ABOVE

        -- Promotion candidates
        MakeSectionHeader(content, format(L["PROMOTION CANDIDATES  (%d)"], #data.promoteCandidates), yOff)
        yOff = yOff + TITLE_H
        if #data.promoteCandidates == 0 then
            local none = MakeRow(content, yOff, 1)
            local fs = UI:CreateText(none, L["No candidates (high attendance) right now."], 10, C.silver.r, C.silver.g, C.silver.b)
            fs:SetPoint("LEFT", 8, 0)
            yOff = yOff + ROW_H + 2
        else
            local canPromote = GuildOS.GuildManager:CanPromote()
            for idx, m in ipairs(data.promoteCandidates) do
                local row = MakeRow(content, yOff, idx)
                local cr, cg, cb = GuildOS:GetClassColor(m.class)
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
                        GuildOS.GuildManager:Promote(fullName)
                        GuildOS.GuildManager:RefreshUI()
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
-- The shared multi-line field (#371); its width comes from its anchors.
-- The MOTD and guild info boxes: a field of fixed height (UI:CreateTextArea), the text in `.edit`.
local function MakeTextArea(parent, height)
    return UI:CreateTextArea(parent, nil, height)
end

local function BuildMotdSub(panel)
    -- MOTD: the screen's first section title (#371), its field under it, both flush with the edges.
    local motdLabel = UI:CreateSectionTitle(panel, L["MESSAGE OF THE DAY"], true)
    motdLabel:SetPoint("TOPLEFT", 0, 0)

    local motdArea = MakeTextArea(panel, 50)
    motdArea:SetPoint("TOPLEFT", 0, -TITLE_H)
    motdArea:SetPoint("TOPRIGHT", 0, -TITLE_H)
    local motdBox = motdArea.edit
    motdBox:SetMaxLetters(128)

    local motdBtn = UI:CreateButton(panel, L["Save MOTD"], 110, 24)
    motdBtn:SetPoint("TOPLEFT", 0, -(TITLE_H + 50 + GAP))
    motdBtn:SetScript("OnClick", function()
        GuildOS.GuildManager:SetMOTD(motdBox:GetText())
        motdBox:ClearFocus()
    end)

    local motdNote = UI:CreateText(panel, "", 11, C.silver.r, C.silver.g, C.silver.b)
    motdNote:SetPoint("LEFT", motdBtn, "RIGHT", 10, 0)

    -- Guild Info: a later section, its rule SECTION_ABOVE under the MOTD's button.
    local infoTop = TITLE_H + 50 + GAP + 24 + SECTION_ABOVE
    local infoLabel = UI:CreateSectionTitle(panel, L["GUILD INFORMATION"])
    infoLabel:SetPoint("TOPLEFT", 0, -infoTop)

    local infoArea = MakeTextArea(panel, 120)
    infoArea:SetPoint("TOPLEFT", 0, -(infoTop + TITLE_H))
    infoArea:SetPoint("TOPRIGHT", 0, -(infoTop + TITLE_H))
    local infoBox = infoArea.edit
    infoBox:SetMaxLetters(500)

    local infoBtn = UI:CreateButton(panel, L["Save Info"], 110, 24)
    infoBtn:SetPoint("TOPLEFT", 0, -(infoTop + TITLE_H + 120 + GAP))
    infoBtn:SetScript("OnClick", function()
        GuildOS.GuildManager:SetGuildInfo(infoBox:GetText())
        infoBox:ClearFocus()
    end)

    local infoNote = UI:CreateText(panel, "", 11, C.silver.r, C.silver.g, C.silver.b)
    infoNote:SetPoint("LEFT", infoBtn, "RIGHT", 10, 0)

    return function()
        local GM = GuildOS.GuildManager
        if not motdBox:HasFocus() then motdBox:SetText(GM:GetMOTD()) end
        if not infoBox:HasFocus() then infoBox:SetText(GM:GetGuildInfo()) end

        -- On WoW: Forever the game's own panel changes it (#377): the field only shows it, and the
        -- button opens that panel.
        local canMotd, viaGame = GM:CanSetMOTD(), GM:MOTDNeedsGamePanel()
        if canMotd and not viaGame then motdBox:Enable() else motdBox:Disable() end
        motdBtn:SetShown(canMotd)
        motdBtn.label:SetText(viaGame and L["Edit in guild panel"] or L["Save MOTD"])
        motdNote:SetText(not canMotd and L["|cff888888No permission to edit the MOTD.|r"]
            or viaGame and L["On WoW: Forever only the game's guild panel can change the message of the day."] or "")

        local canInfo = GM:CanSetGuildInfo()
        if canInfo then infoBox:Enable() else infoBox:Disable() end
        infoBtn:SetShown(canInfo)
        infoNote:SetText(canInfo and "" or L["|cff888888No permission to edit the info.|r"])
    end
end

----------------------------------------------------------------------
-- ACTION LOG sub-panel
----------------------------------------------------------------------
-- Status colours only (#371): a demotion is a `warn`, the guild's texts `info`; gold is no status.
local ACTION_LABELS = {
    promote = { txt = L["Promoted"], color = "green" },
    demote  = { txt = L["Demoted"],  color = "warn" },
    kick    = { txt = L["Removed"],  color = "red" },
    motd    = { txt = L["MOTD"],     color = "info" },
    info    = { txt = L["Info"],     color = "info" },
    join    = { txt = L["Joined"], color = "online" },
    leave   = { txt = L["Left"],   color = "offline" },
}

local function BuildLogSub(panel)
    local clearBtn = UI:CreateButton(panel, L["Clear"], 80, 22)
    clearBtn:SetPoint("TOPLEFT", 0, 0)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(22 + GAP))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtLogScroll")

    local refresh
    refresh = function()
        ClearContent(content)

        local entries = GuildOS.GuildManager:GetLog()
        local yOff = 0
        for idx, e in ipairs(entries) do
            local row = MakeRow(content, yOff, idx)

            local whenFS = UI:CreateText(row, GuildOS:DateText(e.timestamp or 0, " %H:%M"), 9, C.textDim.r, C.textDim.g, C.textDim.b)
            whenFS:SetPoint("LEFT", 8, 0)

            local meta = ACTION_LABELS[e.action] or { txt = e.action or "?", color = "silver" }
            local col = C[meta.color] or C.silver
            local actFS = UI:CreateText(row, meta.txt, 10, col.r, col.g, col.b)
            actFS:SetPoint("LEFT", 90, 0)

            -- Who it was done to, in `text` against the detail's softer one: not gold (#371).
            local tgt = e.target and ("|cff" .. hex(C.text) .. e.target .. "|r ") or ""
            local detail = e.detail and tostring(e.detail) or ""
            local descFS = UI:CreateText(row, tgt .. detail, 10, C.silver.r, C.silver.g, C.silver.b)
            descFS:SetPoint("LEFT", 170, 0)
            descFS:SetPoint("RIGHT", -150, 0)
            descFS:SetJustifyH("LEFT")
            descFS:SetWordWrap(false)

            local byFS = UI:CreateText(row, L["by "] .. (e.author or "?"), 9, C.textDim.r, C.textDim.g, C.textDim.b)
            byFS:SetPoint("RIGHT", -10, 0)

            yOff = yOff + ROW_H + 2
        end

        if #entries == 0 then
            local empty = UI:CreateText(content, L["No actions logged yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 0, -4)
        end
        content:SetHeight(math.max(1, yOff))
    end

    clearBtn:SetScript("OnClick", function()
        GuildOS.GuildManager:ClearLog()
        refresh()
    end)

    if GuildOS.RosterLog then GuildOS.RosterLog.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- BAN LIST sub-panel — officer blacklist (add / search / remove)
----------------------------------------------------------------------
local function BuildBanSub(panel)
    -- Header + one-line context: the screen's first section title (#371).
    local header = UI:CreateSectionTitle(panel, L["BANNED PLAYERS"], true)
    header:SetPoint("TOPLEFT", 0, 0)
    local hint = UI:CreateText(panel,
        L["Blocked from auto-invite. You're alerted when a banned player rejoins the guild or whispers you."],
        11, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 0, -TITLE_H)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -TITLE_H)
    hint:SetJustifyH("LEFT")

    -- Add form, row 1: player + reason. Form labels in `text`, the shared fields (#371).
    local playerLbl = UI:CreateText(panel, L["Player"], 11, C.text.r, C.text.g, C.text.b)
    playerLbl:SetPoint("TOPLEFT", 0, -52)
    local nameBox = UI:CreateInput(panel, 140, 22, { max = 40 })
    nameBox:SetPoint("LEFT", playerLbl, "RIGHT", 8, 0)

    local reasonLbl = UI:CreateText(panel, L["Reason"], 11, C.text.r, C.text.g, C.text.b)
    reasonLbl:SetPoint("LEFT", nameBox, "RIGHT", 16, 0)
    local reasonBox = UI:CreateInput(panel, 210, 22, { max = 80 })
    reasonBox:SetPoint("LEFT", reasonLbl, "RIGHT", 8, 0)

    -- Add form, row 2: temporary toggle (+days) and the Ban button
    local tempChk = UI:CreateCheckbox(panel, L["Temporary"], 18)
    tempChk:SetPoint("TOPLEFT", 0, -84)
    local daysBox = UI:CreateInput(panel, 42, 20, { numeric = true, max = 4 })
    daysBox:SetPoint("LEFT", tempChk, "LEFT", 104, 0)
    local daysLbl = UI:CreateText(panel, L["days"], 11, C.text.r, C.text.g, C.text.b)
    daysLbl:SetPoint("LEFT", daysBox, "RIGHT", 6, 0)
    daysBox:Hide(); daysLbl:Hide()
    tempChk.checkbox.onChanged = function(_, checked)
        daysBox:SetShown(checked); daysLbl:SetShown(checked)
        if not checked then daysBox:SetText("") end
    end

    local banBtn = UI:CreateButton(panel, L["Ban player"], 110, 24)
    banBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -82)

    local function doAdd()
        local n = strtrim(nameBox:GetText())
        if n == "" or not GuildOS.BanList then return end
        if tempChk.checkbox:GetChecked() then
            local d = tonumber(strtrim(daysBox:GetText() or ""))
            if not d or d <= 0 then
                GuildOS:Print(L["Enter a positive number of days for a temporary ban."])
                return
            end
            GuildOS.BanList:Add(n, reasonBox:GetText(), d * 86400)
        else
            GuildOS.BanList:Add(n, reasonBox:GetText())
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
    sep:SetPoint("TOPLEFT", 0, -114)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -114)

    -- Filter + column headers: the shared table header, its labels over the cells below (#371).
    local filterLbl = UI:CreateText(panel, L["Filter"], 11, C.text.r, C.text.g, C.text.b)
    filterLbl:SetPoint("TOPLEFT", 0, -128)
    local searchBox = UI:CreateInput(panel, 180, 20)
    searchBox:SetPoint("LEFT", filterLbl, "RIGHT", 8, 0)

    local CELL_X = { 0, 152, 332, 422 }
    MakeTableHeader(panel, { { L["PLAYER"], CELL_X[1] }, { L["REASON"], CELL_X[2] },
        { L["BY"], CELL_X[3] }, { L["EXPIRES"], CELL_X[4] } }, 146)

    -- List
    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(146 + 22 + 4))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtBanScroll")

    local function cell(text, x, w, y, r, g, b)
        local fs = UI:CreateText(content, text, 11, r, g, b)
        fs:SetPoint("TOPLEFT", x, -y)
        fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    end

    local function refresh()
        for _, c in pairs({ content:GetChildren() }) do c:Hide() end
        for _, r in pairs({ content:GetRegions() }) do r:Hide() end
        local filter = strtrim(searchBox:GetText() or ""):lower()
        local now = GetServerTime()
        local list = GuildOS.BanList and GuildOS.BanList:List() or {}
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
                    expTxt = GuildOS:DateText(e.expiry, "/%y")
                end
                cell(e.name or "?", CELL_X[1], 148, y, nr, ng, nb)
                cell(e.reason or "", CELL_X[2], 176, y, C.text.r, C.text.g, C.text.b)
                cell(e.author or "?", CELL_X[3], 86, y, C.textDim.r, C.textDim.g, C.textDim.b)
                cell(expTxt, CELL_X[4], 82, y, C.textDim.r, C.textDim.g, C.textDim.b)
                local del = UI:CreateButton(content, "\195\151", 22, 18)  -- ×
                del:SetPoint("TOPRIGHT", 0, -y)
                -- By the row's own key: on retail a name alone is a different ban from Name-Realm (#184).
                local key = e.key
                del:SetScript("OnClick", function() if GuildOS.BanList then GuildOS.BanList:RemoveKey(key) end end)
                y = y + ROW_H
            end
        end
        if y == 0 then
            local empty = UI:CreateText(content,
                L["No banned players yet. Add one above to block them."],
                11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 0, -4)
        end
        content:SetHeight(math.max(1, y))
    end

    -- Hooked: the field keeps its own text handlers (#371).
    searchBox:HookScript("OnTextChanged", function() refresh() end)
    -- let sync / mutations repaint this tab
    if GuildOS.BanList then GuildOS.BanList.uiRefresh = refresh end
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
    if not r.part then return L["Opted out"], C.textDim end
    if r.last == 0 or (now - r.last) > 48 * 3600 then return L["Paused"], C.silver end
    return L["Active"], C.green
end

local function BuildEngageSub(panel)
    -- The guild's totals lead the screen in `text`, the trend under them softer (#371).
    local totalsFS = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    totalsFS:SetPoint("TOPLEFT", 0, 0)

    local trendFS = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    trendFS:SetPoint("TOPLEFT", 0, -18)

    -- Invite sparkline as texture bars (glyph blocks do not render in the skin fonts).
    -- One bar per day, oldest on the left, newest on the right; heights scaled
    -- to the busiest day. Anchored just right of the trend text.
    local sparkFrame = CreateFrame("Frame", nil, panel)
    sparkFrame:SetSize(SPARK_BARS * SPARK_STEP, SPARK_H)
    sparkFrame:SetPoint("LEFT", trendFS, "RIGHT", 10, 0)
    local sparkBars = {}
    for i = 1, SPARK_BARS do
        local tex = sparkFrame:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(WHITE)
        tex:SetVertexColor(C.label.r, C.label.g, C.label.b, 0.9)   -- data in `label`, not gold (#371)
        tex:SetPoint("BOTTOMLEFT", (i - 1) * SPARK_STEP, 0)
        tex:SetSize(SPARK_BAR_W, 1)
        sparkBars[i] = tex
    end

    -- Fixed column header (aligns with the row x-offsets below): the shared header row (#371).
    local COLS = { name = 8, status = 150, posts = 280, invites = 350, joined = 430, last = 510 }
    local headTop = 18 + 14 + GAP
    MakeTableHeader(panel, {
        { L["MEMBER"], COLS.name }, { L["STATUS"], COLS.status }, { L["POSTS"], COLS.posts },
        { L["INVITES"], COLS.invites }, { L["JOINED"], COLS.joined }, { L["LAST"], COLS.last },
    }, headTop)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(headTop + 22))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtEngageScroll")

    -- One row per member, made once and reused. Every member's self-report repaints this tab, and a
    -- repaint used to make a new row per member and only hide the old ones: a big guild grew the list
    -- to thousands of frames, until `{ content:GetChildren() }` blew the stack (1426x, 7/11).
    local rowPool, emptyFS = {}, nil
    local function rowAt(idx)
        local row = rowPool[idx]
        if row then return row end
        row = MakeRow(content, 0, idx)
        row.nameFS = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
        row.nameFS:SetPoint("LEFT", COLS.name, 0)
        row.statusFS = UI:CreateText(row, "", 10, C.text.r, C.text.g, C.text.b)
        row.statusFS:SetPoint("LEFT", COLS.status, 0)
        row.postsFS = UI:CreateText(row, "", 10, C.text.r, C.text.g, C.text.b)
        row.postsFS:SetPoint("LEFT", COLS.posts, 0)
        row.invitesFS = UI:CreateText(row, "", 10, C.text.r, C.text.g, C.text.b)
        row.invitesFS:SetPoint("LEFT", COLS.invites, 0)
        row.joinsFS = UI:CreateText(row, "", 10, C.text.r, C.text.g, C.text.b)
        row.joinsFS:SetPoint("LEFT", COLS.joined, 0)
        row.lastFS = UI:CreateText(row, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lastFS:SetPoint("LEFT", COLS.last, 0)
        rowPool[idx] = row
        return row
    end

    local refresh
    refresh = function()
        -- Off screen nothing is drawn: showing the tab repaints it (selectSub), with what came meanwhile.
        if not panel:IsVisible() then return end

        local agg = (GuildOS.RecruitEngagement and GuildOS.RecruitEngagement:GetAggregate())
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
            local row = rowAt(idx)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -yOff)
            row:SetPoint("TOPRIGHT", 0, -yOff)

            local nameColor = r.stale and C.textDim or C.text
            row.nameFS:SetText(r.name)
            row.nameFS:SetTextColor(nameColor.r, nameColor.g, nameColor.b)

            local sText, sColor = statusOf(r, now)
            row.statusFS:SetText(sText)
            row.statusFS:SetTextColor(sColor.r, sColor.g, sColor.b)

            row.postsFS:SetText(tostring(r.posts7))
            row.invitesFS:SetText(tostring(r.invites7))
            local jc = r.joins7 > 0 and C.green or C.textDim
            row.joinsFS:SetText(tostring(r.joins7))
            row.joinsFS:SetTextColor(jc.r, jc.g, jc.b)
            row.lastFS:SetText(GuildOS:TimeAgo(r.last))

            row:Show()
            yOff = yOff + ROW_H + 2
        end
        for idx = #agg.rows + 1, #rowPool do rowPool[idx]:Hide() end

        if not emptyFS then
            emptyFS = UI:CreateText(content, L["No recruitment activity yet."], 11, C.silver.r, C.silver.g, C.silver.b)
            emptyFS:SetPoint("TOPLEFT", 0, -4)
        end
        emptyFS:SetShown(#agg.rows == 0)
        content:SetHeight(math.max(1, yOff))
    end

    -- Repaint when a fresh self-report arrives (RecruitEngagement:HandleStats).
    GuildOS.recruitEngagementRefresh = refresh
    return refresh
end

----------------------------------------------------------------------
-- PRESETS sub-panel — built-in bulk-moderation presets (officer-only).
-- Thin renderer over GuildOS.ModPresets: each preset shows its criteria, a
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
    local MP = GuildOS.ModPresets
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
    return format(L["Apply preset \"%s\"?"], MP:Name(preset)) .. "\n"
        .. line .. " " .. list .. "\n\n"
        .. L["Rank and removal are Blizzard-protected: the guild panel opens, do them there."]
end

local function BuildPresetsSub(panel)
    panel.expanded = {}
    panel.showChooser = false

    -- The screen's first section title, on the line of its one action (#371).
    local title = UI:CreateSectionTitle(panel, L["MODERATION PRESETS"], true)
    title:SetPoint("TOPLEFT", 0, -2)

    local newBtn = UI:CreateButton(panel, L["+ New"], 80, 22)
    newBtn:SetPoint("TOPRIGHT", 0, 0)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(22 + GAP))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtPresetsScroll")

    -- Small numeric threshold editor, the shared field (#371); commits to ModPresets then repaints.
    local function makeNumBox(parent, value, onCommit)
        local box = UI:CreateInput(parent, 40, 20, { numeric = true, max = 4, justify = "CENTER" })
        box:SetText(tostring(value or 0))
        box:SetScript("OnEnterPressed", function(s)
            onCommit(tonumber(s:GetText()))
            s:ClearFocus()
        end)
        return box
    end

    local refresh
    refresh = function()
        ClearContent(content)
        for _, r in pairs({ content:GetRegions() }) do r:Hide() end

        local MP = GuildOS.ModPresets
        local presets = (MP and MP:GetPresets()) or {}
        local yOff = 0

        -- "+ New" chooser: a labelled row of the built-in type buttons.
        if panel.showChooser and MP then
            local chooser = CreateFrame("Frame", nil, content)
            chooser:SetHeight(ROW_H)
            chooser:SetPoint("TOPLEFT", 0, -yOff)
            chooser:SetPoint("TOPRIGHT", 0, -yOff)
            local lbl = UI:CreateText(chooser, L["Add preset:"], 11, C.text.r, C.text.g, C.text.b)   -- a form label (#371)
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
                bx = bx + b:GetWidth() + 6  -- a button its label grew pushes the next one (issue #28)
            end
            yOff = yOff + ROW_H + 4
        end

        if #presets == 0 and not panel.showChooser then
            local empty = UI:CreateText(content, L["No presets yet. Use [+ New] to add one."],
                11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 0, -(yOff + 4))
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
            block:SetHeight(blockH)
            block:SetPoint("TOPLEFT", 0, -yOff)
            block:SetPoint("TOPRIGHT", 0, -yOff)
            block:SetBackdrop({ bgFile = WHITE })
            local alt = (idx % 2 == 0) and C.row1 or C.row2
            block:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)

            -- Header line: name + criteria summary + remove. The name in `text`, not gold (#371).
            local nameFS = UI:CreateText(block, MP:Name(preset), 12, C.text.r, C.text.g, C.text.b)
            nameFS:SetPoint("TOPLEFT", 8, -5)
            local sumFS = UI:CreateText(block, MP:Summarize(preset), 10, C.silver.r, C.silver.g, C.silver.b)
            -- After the name when the name runs past the column: French ones do (#114).
            sumFS:SetPoint("TOPLEFT", math.max(168, 8 + math.ceil(nameFS:GetStringWidth() or 0) + 16), -6)

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
                    local rn = (GuildOS.GuildManager and GuildOS.GuildManager:GetRankName(
                        preset.thresholds and preset.thresholds[fieldKey] or 0)) or "?"
                    local rnFS = UI:CreateText(block, "(" .. rn .. ")", 9, C.silver.r, C.silver.g, C.silver.b)
                    rnFS:SetPoint("TOPLEFT", x, cy - 2)
                    x = x + rnFS:GetStringWidth() + 10
                end
            end

            local countFS = UI:CreateText(block, format(L["%d match"], #matches), 11, C.text.r, C.text.g, C.text.b)
            countFS:SetPoint("TOPLEFT", math.max(x + 8, 320), cy - 2)

            local applyBtn = UI:CreateButton(block, L["Apply"], 70, 20)
            applyBtn:SetPoint("TOPRIGHT", -8, cy)
            applyBtn:SetScript("OnClick", function()
                if not GuildOS:IsOfficer() then GuildOS:Print(L["Officers only."]) return end
                local live = MP:GetMatches(preset)
                if #live == 0 then GuildOS:Print(L["No members match this preset."]) return end
                GuildOS:ShowDialog("GUILDOS_MODPRESET_APPLY", presetApplyText(preset, live), nil,
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
                    -- No bullet in front (#371); the detail in `label`.
                    for _, m in ipairs(matches) do
                        local mFS = UI:CreateText(block,
                            m.name .. "  |cff" .. hex(C.label) .. (m.detail or "") .. "|r",
                            11, C.text.r, C.text.g, C.text.b)
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

    if GuildOS.ModPresets then GuildOS.ModPresets.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- Panel assembly
----------------------------------------------------------------------
function GuildOS:CreateManagementPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "ranks"

    -- Sub-tab bar. Anchored on the left only: UI:FlowBar reads GetWidth to
    -- decide where to wrap, and a frame pinned on both sides reports a
    -- stale width in the same frame its container was resized.
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)

    local subTabBtns = {}
    local subTabList = {}

    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do
            info.panel:SetShown(k == key)
        end
        for k, btn in pairs(subTabBtns) do
            btn:SetActive(k == key)
        end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end
    parent.SelectSub = selectSub   -- deep links: /gos banlist, the Now tab

    -- Refresh whatever sub-panel is currently visible (used by GuildManager).
    parent.RefreshActive = function()
        local info = parent.subPanels[parent.activeSub]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end

    -- Tab width comes from the label, not a constant: eight tabs at a
    -- fixed 120px needed 960px inside a 760px window, which is how the
    -- bar ended up running off the right edge.
    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        subTabList[#subTabList + 1] = btn
    end

    -- One content panel per sub-tab, all sharing the area below the bar.
    -- Anchored to the bar rather than a fixed offset, so a wrapped
    -- two-row tab bar pushes the content down instead of overlapping it.
    -- Flush with the bar's left edge, GAP under it, ending GAP short of its right edge (the bar spans
    -- the parent less 10px a side), as every screen's content does (#371).
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -GAP)
        p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(10 + GAP), 10)
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

    -- Exposed so the layout can be inspected from outside the builder.
    parent.subTabBar = bar
    parent.subTabList = subTabList

    ----------------------------------------------------------------
    -- Layout: the tab bar wraps, and the visible sub-panel rebuilds so
    -- its scroll content picks up the new width.
    ----------------------------------------------------------------
    UI:MakeResponsive(parent, function(_, w, _)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        UI:FlowBar(bar, subTabList, { gap = 4, rowGap = 4, rowH = TAB_H })
        parent.RefreshActive()
    end)
end
