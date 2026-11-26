----------------------------------------------------------------------
-- Guild OS - Management Panel (Leadership Suite UI)
-- The "Lideran\195\167a" tab: rank management, inactivity report, promotion /
-- trial suggestions, MOTD / Guild Info editing, and the action log.
-- Visual layout only — all data and actions go through GuildOS.GuildManager
-- (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
-- The Officers' Room draws each screen on a parchment card (specs/salao/fase3.md): its text takes the paper's
-- inks (UI/Kit.lua), and a floating window over it the wood's (WOOD).
local Kit = rawget(GuildOS, "Kit")
local C = Kit and Kit.PAPER or GuildOS.Colors
local WOOD = GuildOS.Colors
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
    -- Promote, demote or remove by rules, one member a click (issue #420): UI/BulkPanel.lua builds it.
    { key = "bulk",     label = L["Bulk actions"] },
    -- Who has no GuildOS, and a reminder one member a click (issue #422): UI/RemindPanel.lua builds it.
    { key = "remind",   label = L["Without GuildOS"] },
    -- Join dates in the notes, the safe list, nicknames (issue #429): UI/MarksPanel.lua builds it.
    { key = "marks",    label = L["Notes and marks"] },
    -- The officers' chat alerts and their rules (issues #404, #405): UI/ModAlerts.lua builds both.
    { key = "alerts",   label = L["Chat alerts"] },
    { key = "alertrules", label = L["Alert rules"] },
}

local ROW_H = 26
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 70    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab

-- The shared spacing (#371), read as numbers: a test that stubs GuildOS.UI hands back functions.
local GAP = tonumber(UI.GAP) or 8
local GUTTER = tonumber(UI.SCROLL_GUTTER) or 12

-- A colour token as the hex an inline |c code takes (#371).
local function hex(c)
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- A member's class colour on the paper (Kit:ClassInk): the game's own read only on the wood.
local function classInk(class)
    if Kit then return Kit:ClassInk(class) end
    return GuildOS:GetClassColor(class)
end

-- A row's tan rule along its bottom, the paper's table line, in place of the wood's stripes.
local function rule(row)
    if Kit then Kit:Rule(row) end
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
    rule(row)
    return row
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
UI.MakeVirtualList = MakeVirtualList   -- the bulk actions' list draws the same way (UI/BulkPanel.lua)

-- A table's columns on a list card: avatar, name, rank and level, then the row's actions at its right.
local COL_NAME, COL_RANK, COL_LVL = 30, 180, 300

-- A member's cells on a table row: a small class avatar, the name in the class's ink, the rank and the level.
local function MemberCells(row)
    row.av = UI:CreateAvatar(row, 20, false)
    row.av:SetPoint("LEFT", 2, 0)
    row.nameFS = UI:CreateText(row, "", 12)
    row.nameFS:SetPoint("LEFT", COL_NAME, 0)
    row.nameFS:SetWidth(COL_RANK - COL_NAME - 8)
    row.nameFS:SetJustifyH("LEFT")
    row.nameFS:SetWordWrap(false)
    row.rankFS = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    row.rankFS:SetPoint("LEFT", COL_RANK, 0)
    row.rankFS:SetWidth(COL_LVL - COL_RANK - 8)
    row.rankFS:SetJustifyH("LEFT")
    row.rankFS:SetWordWrap(false)
    row.lvlFS = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    GuildOS:ApplyFont(row.lvlFS, 11, "tableNum")
    row.lvlFS:SetPoint("LEFT", COL_LVL, 0)
end
local function FillMember(row, m)
    local cr, cg, cb = classInk(m.class)
    if row.av and row.av.SetMember then row.av:SetMember(m.name, m.class, m.online == false) end
    row.nameFS:SetText(m.name)
    row.nameFS:SetTextColor(cr, cg, cb)
    row.rankFS:SetText(m.rankName or "?")
    row.lvlFS:SetText(tostring(m.level or ""))
end

-- A list card: `card` fills the room left in its column; its header (Forms:TableHeader) then a body the list
-- draws in. Returns the body.
local function ListBody(card, cols)
    local header = GuildOS.Forms:TableHeader(card, cols)
    card:Add(header, { h = 20, wide = true })
    return card:Body(ROW_H * 4, { gap = 2 })
end

local function BuildRanksSub(panel)
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtRanksBoard" })
    local card = board:Card(L["Ranks"], { fill = true })
    card:Note(L["Rank changes are Blizzard-protected: the arrow buttons open the official guild panel for you to confirm."])
    local listHolder = ListBody(card, { { L["Member"], COL_NAME }, { L["Rank"], COL_RANK }, { L["Level"], COL_LVL } })

    local empty = UI:CreateText(listHolder, L["Roster empty or unavailable."], 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)
    empty:Hide()

    local function createRow(parent)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = WHITE })
        rule(row)
        MemberCells(row)
        -- Demote one step (higher rankIndex), promote one (lower). Shown where the rank may: small quiet
        -- buttons at the row's right (the mockup's ▲ ▼).
        row.downBtn = UI:CreateButton(row, "|TInterface\\BUTTONS\\Arrow-Down-Up:14:14|t", 26, 20)
        row.downBtn:SetPoint("RIGHT", -2, 0)
        row.downBtn:SetScript("OnClick", function()
            GuildOS.GuildManager:Demote(row.member.fullName)
            GuildOS.GuildManager:RefreshUI()
        end)
        row.upBtn = UI:CreateButton(row, "|TInterface\\BUTTONS\\Arrow-Up-Up:14:14|t", 26, 20)
        row.upBtn:SetPoint("RIGHT", -32, 0)
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
        FillMember(row, m)
        row.nameFS:SetAlpha(m.online and 1 or 0.7)
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

    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtInactiveBoard" })
    local card = board:Card(L["Inactive members"], { fill = true })
    -- The threshold above the list, its Apply beside it (the mockup's "Inactive for more than [30] days").
    local daysBox = UI:CreateInput(card, 60, 24, { numeric = true, max = 4, justify = "CENTER" })   -- #371
    daysBox:SetText(tostring(panel.threshold))
    local applyBtn = UI:CreateButton(card, L["Apply"], 70, 24)
    card:Field(L["Inactive for more than"] .. " (" .. L["days"] .. ")", daysBox, { w = 80, button = applyBtn })
    -- How many matched: secondary text, not gold (#371).
    local summary = card:Note("")

    local COL_DAYS = COL_LVL + 44
    local listHolder = ListBody(card, { { L["Member"], COL_NAME }, { L["Rank"], COL_RANK }, { L["Level"], COL_LVL },
        { L["Offline"], COL_DAYS } })
    -- Drawn as Ranks is (MakeVirtualList): only the rows that fit, refilled on scroll (#371).
    local empty = UI:CreateText(listHolder, L["No inactive members in this period."], 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)
    empty:Hide()

    local canKick = false
    local function createRow(parent)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = WHITE })
        rule(row)
        MemberCells(row)
        row.daysFS = UI:CreateText(row, "", 11)
        row.daysFS:SetPoint("LEFT", COL_DAYS, 0)
        row.kickBtn = UI:CreateButton(row, L["Remove"], 70, 20)
        row.kickBtn:SetWidth(math.ceil(row.kickBtn.label:GetStringWidth() or 40) + 16)
        row.kickBtn:SetPoint("RIGHT", -2, 0)
        row.kickBtn:SetScript("OnClick", function()
            GuildOS.GuildManager:ConfirmKick(row.member.fullName)
        end)
        return row
    end
    local function fillRow(row, m, idx)
        row.member = m
        local alt = (idx % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        m.online = false
        FillMember(row, m)
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
    applyBtn:SetScript("OnClick", apply)

    return refresh
end

----------------------------------------------------------------------
-- SUGGESTIONS sub-panel — trial approvals + promotion candidates
----------------------------------------------------------------------
-- Two cards (the mockup's): the trials ready for a decision and the members to promote, a row each with
-- the member, why, and the decision at the row's right.
local function BuildSuggestSub(panel)
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtSuggestBoard" })
    local refresh

    local trialsCard = board:Card("", { col = 1 })
    local trials = trialsCard:Rows(function(holder)
        local row = Forms:TodoRow(holder, { glyph = true })
        row.ok = Forms:SmallButton(row.right, L["Approve"], "primary")
        row.deny = Forms:SmallButton(row.right, L["Deny"])
        row:Right({ row.deny, row.ok })
        return row
    end, function(row, t)
        row.glyph:Set("T", C.epic)
        row.title:SetText(t.name)
        row.sub:SetText(format(L["Day %d  |  %d%% attendance  |  iLvl %s%d"], t.daysSince, t.attendance,
            t.ilvlDelta >= 0 and "+" or "", t.ilvlDelta))
        local key = t.key
        row.ok:SetScript("OnClick", function()
            GuildOS.TrialTracker:UpdateStatus(key, GuildOS.TrialTracker.STATUS.APPROVED)
            refresh()
        end)
        row.deny:SetScript("OnClick", function()
            GuildOS.TrialTracker:UpdateStatus(key, GuildOS.TrialTracker.STATUS.DENIED)
            refresh()
        end)
        row:Right()
    end, { empty = L["No trials due."] })

    local promoCard = board:Card("", { col = 2 })
    local canPromote = false
    local promos = promoCard:Rows(function(holder)
        local row = Forms:TodoRow(holder)
        row.promo = Forms:SmallButton(row.right, L["Promote"], "primary")
        row:Right({ row.promo })
        return row
    end, function(row, m)
        row.av:SetMember(m.name, m.class)
        local cr, cg, cb = classInk(m.class)
        row.title:SetText(m.name)
        row.title:SetTextColor(cr, cg, cb)
        row.sub:SetText((m.rankName or "?") .. "  ·  " .. format(L["%d%% attendance"], m.attendance))
        local fullName = m.fullName
        row.promo:SetShown(canPromote)
        row.promo:SetScript("OnClick", function()
            GuildOS.GuildManager:Promote(fullName)
            GuildOS.GuildManager:RefreshUI()
        end)
        row:Right()
    end, { empty = L["No candidates (high attendance) right now."] })

    refresh = function()
        local data = GuildOS.GuildManager:GetSuggestions()
        canPromote = GuildOS.GuildManager:CanPromote() and true or false
        GuildOS:SetTitleText(trialsCard.title, format(L["Trials ready for a decision (%d)"], #data.trialsReady))
        GuildOS:SetTitleText(promoCard.title, format(L["Promotion candidates (%d)"], #data.promoteCandidates))
        trials:SetData(data.trialsReady)
        promos:SetData(data.promoteCandidates)
        board:Layout()
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
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtMotdBoard" })
    -- Two cards (the mockup's): the message of the day and the guild's information, each its field, why it
    -- may not change, and its Save at the card's bottom right.
    local motdCard = board:Card(L["Message of the day"], { col = 1 })
    local motdArea = MakeTextArea(motdCard, 56)
    motdCard:Add(motdArea, { h = 56, wide = true })
    local motdBox = motdArea.edit
    motdBox:SetMaxLetters(128)
    local motdNote = motdCard:Note("", { shown = function() return (panel.motdNoteText or "") ~= "" end })
    local motdBtn = UI:CreateButton(motdCard, L["Save MOTD"], 110, 24)
    UI:SetButtonVariant(motdBtn, "primary")
    motdBtn:SetScript("OnClick", function()
        GuildOS.GuildManager:SetMOTD(motdBox:GetText())
        motdBox:ClearFocus()
    end)
    motdCard:Actions({ motdBtn })

    local infoCard = board:Card(L["Guild information"], { col = 2 })
    local infoArea = MakeTextArea(infoCard, 120)
    infoCard:Add(infoArea, { h = 120, wide = true })
    local infoBox = infoArea.edit
    infoBox:SetMaxLetters(500)
    local infoNote = infoCard:Note("", { shown = function() return (panel.infoNoteText or "") ~= "" end })
    local infoBtn = UI:CreateButton(infoCard, L["Save Info"], 110, 24)
    UI:SetButtonVariant(infoBtn, "primary")
    infoBtn:SetScript("OnClick", function()
        GuildOS.GuildManager:SetGuildInfo(infoBox:GetText())
        infoBox:ClearFocus()
    end)
    infoCard:Actions({ infoBtn })
    -- What the tests read.
    panel.motdArea, panel.motdBtn, panel.motdNote = motdArea, motdBtn, motdNote
    panel.infoArea, panel.infoBtn, panel.infoNote = infoArea, infoBtn, infoNote

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
        panel.motdNoteText = not canMotd and L["|cff888888No permission to edit the MOTD.|r"]
            or viaGame and L["On WoW: Forever only the game's guild panel can change the message of the day."] or ""
        motdNote:SetText((panel.motdNoteText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))

        local canInfo = GM:CanSetGuildInfo()
        if canInfo then infoBox:Enable() else infoBox:Disable() end
        infoBtn:SetShown(canInfo)
        panel.infoNoteText = canInfo and "" or L["|cff888888No permission to edit the info.|r"]
        infoNote:SetText((panel.infoNoteText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        if board.Layout then board:Layout() end
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
    warn    = { txt = L["Warned"], color = "warn" },
    -- From the member history and the roster diff (issue #425).
    rejoin  = { txt = L["Rejoined"], color = "online" },
    gone    = { txt = L["Gone"],     color = "offline" },
    level   = { txt = L["Level"],    color = "info" },
    note    = { txt = L["Note changed"], color = "info" },
    onote   = { txt = L["Officer note changed"], color = "info" },
    back    = { txt = L["Back from inactivity"], color = "online" },   -- not L["Back"], the navigation's (#429)
}

-- The badge each action's status colour takes (Kit:Badge's kinds).
local BADGE_OF = { green = "ok", online = "ok", warn = "warn", red = "bad", info = "info", offline = "mute", silver = "mute" }

-- What the level filter's select says for each mode (MemberHistory.LEVEL_MODES).
local LEVEL_MODE_TEXT = {
    milestones = L["Levels: milestones"],
    all        = L["Levels: all"],
    off        = L["Levels: off"],
}

-- Whether a log line holds `filter` (lower case): its member, officer, detail or the word for it.
local function logMatches(e, meta, filter)
    if filter == "" then return true end
    for _, v in ipairs({ e.target, e.author, e.detail ~= nil and tostring(e.detail) or nil, meta.txt }) do
        if v and v:lower():find(filter, 1, true) then return true end
    end
    return false
end

local function BuildLogSub(panel)
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtLogBoard" })
    local card = board:Card(L["Action log"], { fill = true })

    -- Search (issue #425): the member, the officer, the detail or the action's word; which level ups the
    -- roster diff writes here (milestones: every 10 and the cap, all, none), a select; Clear at the right.
    local searchBox = UI:CreateInput(card, 160, 24, { placeholder = L["Search"] })
    local levelDD = UI:CreateDropdown(card, 170, 24)
    local MH0 = GuildOS.MemberHistory
    local modes = {}
    local known = MH0 and MH0.LEVEL_MODES
    for _, m in ipairs(type(known) == "table" and known or { "milestones", "all", "off" }) do
        modes[#modes + 1] = { value = m, text = LEVEL_MODE_TEXT[m] or m }
    end
    levelDD:SetOptions(modes)
    local clearBtn = UI:CreateButton(card, L["Clear"], 80, 24)
    local tools = CreateFrame("Frame", nil, card)
    tools:SetSize(1, 24)
    for _, f in ipairs({ searchBox, levelDD, clearBtn }) do f:SetParent(tools) end
    card:Add(tools, { place = function(_, w)
        local cw = clearBtn:GetWidth() or 80
        local lw = levelDD:IsShown() and math.min(180, math.floor(w * 0.35)) or 0
        clearBtn:ClearAllPoints(); clearBtn:SetPoint("TOPRIGHT", tools, "TOPRIGHT", 0, 0)
        levelDD:ClearAllPoints(); levelDD:SetPoint("TOPRIGHT", clearBtn, "TOPLEFT", -8, 0); levelDD:SetWidth(math.max(1, lw))
        searchBox:ClearAllPoints(); searchBox:SetPoint("TOPLEFT", tools, "TOPLEFT", 0, 0)
        searchBox:SetWidth(math.max(60, w - cw - 8 - (lw > 0 and (lw + 8) or 0)))
        tools:SetSize(math.max(1, w), 24)
        return 24
    end })

    local COL_WHEN, COL_ACT, COL_WHAT = 0, 92, 196
    local header = Forms:TableHeader(card, { { L["When"], COL_WHEN }, { L["Action"], COL_ACT }, { L["What"], COL_WHAT },
        { L["By"], -4 } })
    card:Add(header, { h = 20, wide = true, gap = 10 })
    local listHolder = card:Body(ROW_H * 4, { gap = 2 })
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtLogScroll")

    local refresh
    refresh = function()
        ClearContent(content)

        local MH = GuildOS.MemberHistory
        levelDD:SetShown(MH ~= nil and GuildOS:IsOfficer())
        if MH then levelDD:SetValue(MH:GetLevelMode()) end
        local filter = strtrim(searchBox:GetText() or ""):lower()
        local entries = {}
        for _, e in ipairs(GuildOS.GuildManager:GetLog()) do
            local meta = ACTION_LABELS[(e.action == "join" and e.rejoin) and "rejoin" or e.action]
                or { txt = e.action or "?", color = "silver" }
            if logMatches(e, meta, filter) then entries[#entries + 1] = { e = e, meta = meta } end
        end
        local yOff = 0
        for idx, item in ipairs(entries) do
            local e, meta = item.e, item.meta
            local row = MakeRow(content, yOff, idx)

            local whenFS = UI:CreateText(row, GuildOS:DateText(e.timestamp or 0, " %H:%M"), 10, C.textDim.r, C.textDim.g, C.textDim.b)
            GuildOS:ApplyFont(whenFS, 10, "tableNum")
            whenFS:SetPoint("LEFT", COL_WHEN + 2, 0)

            -- The action as a badge in its status (the mockup's), not a coloured word.
            local badge = Kit and Kit:Badge(row, meta.txt, BADGE_OF[meta.color] or "mute")
                or UI:CreateBadge(row, meta.txt, C[meta.color] or C.silver)
            badge:SetPoint("LEFT", COL_ACT, 0)

            -- Who it was done to, in `text` against the detail's softer one: not gold (#371).
            local tgt = e.target and ("|cff" .. hex(C.text) .. e.target .. "|r ") or ""
            local detail = e.detail and tostring(e.detail) or ""
            local descFS = UI:CreateText(row, tgt .. detail, 11, C.silver.r, C.silver.g, C.silver.b)
            descFS:SetPoint("LEFT", COL_WHAT, 0)
            descFS:SetPoint("RIGHT", -110, 0)
            descFS:SetJustifyH("LEFT")
            descFS:SetWordWrap(false)

            -- A line of this client's roster diff has no officer: the roster only shows what changed.
            local byFS = UI:CreateText(row, e.author or "—", 10, C.textDim.r, C.textDim.g, C.textDim.b)
            byFS:SetPoint("RIGHT", -4, 0)
            byFS:SetWidth(100)
            byFS:SetJustifyH("RIGHT")
            byFS:SetWordWrap(false)

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
    searchBox:HookScript("OnTextChanged", function() refresh() end)
    levelDD.onSelect = function(_, mode)
        local MH = GuildOS.MemberHistory
        if MH then MH:SetLevelMode(mode) end
        refresh()
    end

    if GuildOS.RosterLog then GuildOS.RosterLog.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- Share a ban with the alliance (#408): a reason from the contract's list, required, and an optional
-- note. The logic is BanList:Share's; this only asks.
----------------------------------------------------------------------
local shareDialog
local function ShowShareDialog(key, name)
    local BL = GuildOS.BanList
    if not BL then return end
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    local f = shareDialog
    if not f then
        f = CreateFrame("Frame", "GuildOSBanShareDialog", UIParent, "BackdropTemplate")
        f:SetSize(380, 176)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        -- A floating window (the mockup's .fw): the question in its header, the form on its dark body.
        local DY = 0
        if Kit then
            Kit:Dress(f, L["Share"])
            DY = Kit.HEADER_H - 4
            f:SetHeight(176 + DY)
            f.title = UI:CreateText(f, "", 12, WOOD.text.r, WOOD.text.g, WOOD.text.b)
            f.title:SetPoint("TOPLEFT", 14, -(Kit.HEADER_H + 8))
            f.title:SetPoint("TOPRIGHT", -14, -(Kit.HEADER_H + 8))
            f.title:SetJustifyH("LEFT")
        else
            f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(f) })
            f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
            UI:StylePopup(f)
            f.title = UI:CreateText(f, "", 13, WOOD.text.r, WOOD.text.g, WOOD.text.b)
            f.title:SetPoint("TOP", 0, -12)
        end
        local hint = UI:CreateText(f, L["The alliance's officers are alerted about them; nobody is banned for it."],
            10, WOOD.silver.r, WOOD.silver.g, WOOD.silver.b)
        hint:SetPoint("TOPLEFT", 14, -(34 + DY))
        hint:SetPoint("TOPRIGHT", -14, -(34 + DY))
        hint:SetJustifyH("LEFT")
        local reasonLbl = UI:CreateText(f, L["Reason"], 11, WOOD.text.r, WOOD.text.g, WOOD.text.b)
        reasonLbl:SetPoint("TOPLEFT", 14, -(66 + DY))
        f.reason = UI:CreateDropdown(f, 220, 22)
        f.reason:SetPoint("LEFT", reasonLbl, "RIGHT", 8, 0)
        local opts = {}
        for _, r in ipairs(BL.SHARE_REASONS) do opts[#opts + 1] = { value = r, text = BL.ReasonText(r) } end
        f.reason:SetOptions(opts)
        f.reason:SetPlaceholder(L["Choose a reason"])
        local noteLbl = UI:CreateText(f, L["Note (optional)"], 11, WOOD.text.r, WOOD.text.g, WOOD.text.b)
        noteLbl:SetPoint("TOPLEFT", 14, -(98 + DY))
        f.note = UI:CreateInput(f, 250, 22, { max = BL.SHARE_NOTE_MAX })
        f.note:SetPoint("LEFT", noteLbl, "RIGHT", 8, 0)
        f.result = UI:CreateText(f, "", 10, WOOD.red.r, WOOD.red.g, WOOD.red.b)
        f.result:SetPoint("BOTTOMLEFT", 14, 18)
        f.ok = UI:CreateButton(f, L["Share"], 90, 24)
        UI:SetButtonVariant(f.ok, "primary")
        f.ok:SetPoint("BOTTOMRIGHT", -14, 12)
        local cancel = UI:CreateButton(f, L["Cancel"], 90, 24)
        cancel:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
        cancel:SetScript("OnClick", function() f:Hide() end)
        table.insert(UISpecialFrames, "GuildOSBanShareDialog")   -- ESC closes it
        shareDialog = f
    end
    f.title:SetText(string.format(L["Share the ban on %s with your guildos.me alliance"], name or "?"))
    f.reason:SetValue(nil)
    f.note:SetText("")
    f.result:SetText("")
    f.ok:SetScript("OnClick", function()
        local ok, why = BL:Share(key, f.reason:GetValue(), f.note:GetText())
        if ok then f:Hide(); return end
        f.result:SetText(why == "reason" and L["Choose a reason first."]
            or why == "expired" and L["This ban has run out: there is nothing to share."] or L["Nothing was shared."])
    end)
    f:Show()
end

----------------------------------------------------------------------
-- BAN LIST sub-panel — officer blacklist (add / search / remove)
----------------------------------------------------------------------
local function BuildBanSub(panel)
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtBanBoard" })
    -- Two cards (the mockup's "Banned players"): banning someone, then the list.
    local formCard = board:Card(L["Banned players"], { span = true })
    -- One line of context under the card's title.
    formCard:Note(L["Blocked from auto-invite. You're alerted when a banned player rejoins the guild or whispers you."])
    local nameBox = UI:CreateInput(formCard, 140, 24, { max = 40 })
    local reasonBox = UI:CreateInput(formCard, 210, 24, { max = 80 })
    formCard:Pair(Forms:MakeField(formCard, L["Player"], nameBox), Forms:MakeField(formCard, L["Reason"], reasonBox))
    -- Temporary: a number of days; left empty (or 0) the ban is for good.
    local daysBox = UI:CreateInput(formCard, 120, 24, { numeric = true, max = 4, placeholder = "0 = " .. L["permanent"] })
    local banBtn = UI:CreateButton(formCard, L["Ban player"], 110, 24)
    UI:SetButtonVariant(banBtn, "primary")
    banBtn:SetWidth(math.ceil(banBtn.label:GetStringWidth() or 60) + 24)
    formCard:Field(L["Temporary"] .. " (" .. L["days"] .. ")", daysBox, { w = 160, button = banBtn })

    local function doAdd()
        local n = strtrim(nameBox:GetText())
        if n == "" or not GuildOS.BanList then return end
        local raw = strtrim(daysBox:GetText() or "")
        local d = tonumber(raw)
        if raw ~= "" and (not d or d < 0) then
            GuildOS:Print(L["Enter a positive number of days for a temporary ban."])
            return
        end
        if d and d > 0 then
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

    -- The list: ours or, while the guild has an alliance on guildos.me, the alliance's (#408), as two pills;
    -- a filter; the table.
    local listCard = board:Card(L["Ban List"], { span = true, fill = true })
    local showAlliance = false
    local pillsFor
    local refresh
    local ourPill = Forms:Pill(listCard, L["Our bans"], true)
    local allyBtn = Forms:Pill(listCard, string.format(L["Alliance bans (%d)"], 0), false)
    ourPill:SetScript("OnClick", function() showAlliance = false; refresh() end)
    allyBtn:SetScript("OnClick", function() showAlliance = true; refresh() end)
    listCard:Flow({ ourPill, allyBtn }, { shown = function() return allyBtn:IsShown() end })
    local searchBox = UI:CreateInput(listCard, 180, 24, { placeholder = L["Filter"] })
    listCard:Add(searchBox, { h = 24, place = function(_, w) searchBox:SetWidth(math.min(w, 260)); return 24 end })

    local CELL_X = { 0, 124, 280, 354 }
    local localHeader = MakeTableHeader(listCard, { { L["Player"], CELL_X[1] }, { L["Reason"], CELL_X[2] },
        { L["By"], CELL_X[3] }, { L["Expires"], CELL_X[4] } }, 0)
    -- The alliance's bans this client holds (#408): read-only, in memory, the guild that banned and when.
    local allyHeader = MakeTableHeader(listCard, { { L["Player"], CELL_X[1] }, { L["Reason"], CELL_X[2] },
        { L["Guild"], CELL_X[3] }, { L["Date"], CELL_X[4] } }, 0)
    allyHeader:Hide()
    local heads = CreateFrame("Frame", nil, listCard)
    heads:SetSize(1, 22)
    for _, h in ipairs({ localHeader, allyHeader }) do
        h:SetParent(heads); h:ClearAllPoints()
        h:SetPoint("TOPLEFT", heads, "TOPLEFT", 0, 0); h:SetPoint("TOPRIGHT", heads, "TOPRIGHT", 0, 0)
    end
    listCard:Add(heads, { h = 22, wide = true, gap = 10 })

    -- List
    local listHolder = listCard:Body(ROW_H * 4, { gap = 2 })
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtBanScroll")

    -- Every widget of the list is made once and reused (audit M3): a refresh, which every keystroke in the filter
    -- and every ban that syncs in runs, used to make a new row of frames for each ban and only hide the old ones.
    local CELL_W = { 118, 150, 70, 70 }
    local rowPool, used = {}, 0
    local function rowAt(idx)
        local row = rowPool[idx]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)
        rule(row)
        row.cells = {}
        for c = 1, 4 do
            local fs = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("LEFT", CELL_X[c] + 2, 0)
            fs:SetWidth(CELL_W[c]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
            row.cells[c] = fs
        end
        row.del = UI:CreateButton(row, "\195\151", 22, 20)  -- ×
        row.del:SetPoint("RIGHT", 0, 0)
        row.share = UI:CreateButton(row, L["Share"], 70, 20)
        row.share:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
        rowPool[idx] = row
        return row
    end
    -- The next pooled row, placed at `y`, its four cells' text and colour set: { text, color } each.
    local function placeRow(y, cells)
        used = used + 1
        local row = rowAt(used)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        for c = 1, 4 do
            local fs, col = row.cells[c], cells[c][2]
            fs:SetText(cells[c][1])
            fs:SetTextColor(col.r, col.g, col.b)
        end
        row.del:Hide(); row.share:Hide()
        row:Show()
        return row
    end
    local stillTitle = UI:CreateText(content, "", 11, C.red.r, C.red.g, C.red.b)
    local stillAll = UI:CreateButton(content, L["Remove all"], 110, 18)
    local stillNames = UI:CreateText(content, "", 11, C.text.r, C.text.g, C.text.b)
    stillNames:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    stillNames:SetJustifyH("LEFT"); stillNames:SetWordWrap(true)
    local emptyFS = UI:CreateText(content, "", 11, C.silver.r, C.silver.g, C.silver.b)
    emptyFS:SetPoint("TOPLEFT", 0, -4)
    local function clearList()
        for idx = 1, #rowPool do rowPool[idx]:Hide() end
        used = 0
        stillTitle:Hide(); stillAll:Hide(); stillNames:Hide(); emptyFS:Hide()
    end
    local function showEmpty(text)
        emptyFS:SetText(text)
        emptyFS:Show()
    end

    -- The alliance's bans, read-only: an alert for the officers, never a ban here (#408).
    local function refreshAlliance(filter)
        local BL = GuildOS.BanList
        local list = BL and GuildOS:IsOfficer() and BL:AllianceBans() or nil
        local y = 0
        for _, b in ipairs(list or {}) do
            if filter == "" or (b.name or ""):lower():find(filter, 1, true) then
                local why = BL.ReasonText(b.reason) .. (b.appeal and (" " .. L["(under appeal)"]) or "")
                if b.note then why = why .. " — " .. b.note end
                placeRow(y, { { b.name or "?", C.red }, { why, C.text }, { b.guild or "?", C.textDim },
                    { GuildOS:DateText(b.at, "/%y"), C.textDim } })
                y = y + ROW_H
            end
        end
        if y == 0 then
            showEmpty(L["No bans from the alliance. The site sends them with the companion when other guilds share theirs."])
        end
        content:SetHeight(math.max(1, y))
    end

    refresh = function()
        clearList()
        local filter = strtrim(searchBox:GetText() or ""):lower()
        local held = GuildOS.BanList and GuildOS:IsOfficer() and GuildOS.BanList:AllianceBans() or nil
        -- With no alliance on guildos.me there are no alliance's bans to show (audit B7).
        local hasAlliance = (held and #held > 0) or (GuildOS.BanList and GuildOS.BanList:HasSiteAlliance())
        if not hasAlliance then showAlliance = false end
        allyBtn:SetShown(hasAlliance and true or false)
        ourPill:SetShown(hasAlliance and true or false)
        allyBtn.label:SetText(string.format(L["Alliance bans (%d)"], held and #held or 0))
        GuildOS.Forms:FitPill(allyBtn)
        if pillsFor ~= showAlliance then   -- repainted only when the choice changes: every keystroke refreshes
            pillsFor = showAlliance
            GuildOS.Forms:SetOn(ourPill, not showAlliance)
            GuildOS.Forms:SetOn(allyBtn, showAlliance)
        end
        board:Layout()
        localHeader:SetShown(not showAlliance); allyHeader:SetShown(showAlliance)
        if showAlliance then return refreshAlliance(filter) end
        local now = GetServerTime()
        local list = GuildOS.BanList and GuildOS.BanList:List() or {}
        local y = 0
        -- Banned and still in the guild (#426): "Remove all" only queues them in Bulk actions, one per click.
        local BA = GuildOS.BulkActions
        local inGuild = (BA and GuildOS.BanList and filter == "")
            and GuildOS.BanList:StillInGuild(BA:Collect(false), BA:Context().meKey, now) or {}
        if #inGuild > 0 then
            stillTitle:SetText(string.format(L["Banned and still in the guild (%d)"], #inGuild))
            stillTitle:ClearAllPoints(); stillTitle:SetPoint("TOPLEFT", 0, -y); stillTitle:Show()
            stillAll:ClearAllPoints(); stillAll:SetPoint("TOPRIGHT", 0, -y); stillAll:Show()
            stillAll:SetScript("OnClick", function() BA:StartListAndSay("remove", inGuild) end)
            y = y + ROW_H
            stillNames:SetText(GuildOS.AltDeparture and GuildOS.AltDeparture.ColoredNames(inGuild) or "")
            stillNames:SetPoint("TOPLEFT", 0, -y); stillNames:Show()
            y = y + math.max(ROW_H, math.ceil(stillNames:GetStringHeight() or 0) + 4) + 6
        end
        local officer = GuildOS:IsOfficer()
        for _, e in ipairs(list) do
            if filter == "" or (e.name or ""):lower():find(filter, 1, true) then
                local expired = e.expiry and e.expiry <= now
                local nameColor = C.red
                local expTxt
                if not e.expiry then
                    expTxt = L["permanent"]
                elseif expired then
                    expTxt = L["(expired)"]
                    nameColor = C.silver
                else
                    expTxt = GuildOS:DateText(e.expiry, "/%y")
                end
                -- Banned with an alt group (#426): "(group of X)"; the officers' note after the reason.
                local shownName = e.name or "?"
                if e.group then shownName = shownName .. " " .. string.format(L["(group of %s)"], e.group) end
                local why = e.reason or ""
                if officer and e.note then why = why .. " — " .. e.note end
                local row = placeRow(y, { { shownName, nameColor }, { why, C.text }, { e.author or "?", C.textDim },
                    { expTxt, C.textDim } })
                -- By the row's own key: on retail a name alone is a different ban from Name-Realm (#184). Lifting
                -- asks first (audit B6).
                local key, who = e.key, e.name
                row.del:SetScript("OnClick", function() if GuildOS.BanList then GuildOS.BanList:ConfirmRemoveKey(key, who) end end)
                row.del:Show()
                -- Share with the guild's alliance on guildos.me, or stop sharing (#408): offered only while the guild
                -- has one, and never for a temporary ban that ran out (audit B6, B7). A share stays withdrawable.
                local BL = GuildOS.BanList
                local shared = BL and BL:IsShared(key)
                if shared or (BL and BL:CanShare(key, nil, now)) then
                    row.share.label:SetText(shared and L["Unshare"] or L["Share"])
                    row.share:SetScript("OnClick", function()
                        if not GuildOS.BanList then return end
                        if shared then GuildOS.BanList:Unshare(key) else ShowShareDialog(key, who) end
                    end)
                    row.share:Show()
                end
                y = y + ROW_H
            end
        end
        if y == 0 then showEmpty(L["No banned players yet. Add one above to block them."]) end
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
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtEngageBoard" })
    local card = board:Card(L["Recruitment engagement"], { fill = true })
    -- The guild's totals lead the card in `text`, the trend under them softer with the week's invites as
    -- bars beside it (#371).
    local totalsFS = card:Note("", { ink = C.text, size = 12 })
    local trendRow = CreateFrame("Frame", nil, card)
    trendRow:SetSize(1, 14)
    card:Add(trendRow, { h = 14, wide = true, gap = 4 })
    local trendFS = UI:CreateText(trendRow, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    trendFS:SetPoint("LEFT", 0, 0)

    -- Invite sparkline as texture bars (glyph blocks do not render in the skin fonts).
    -- One bar per day, oldest on the left, newest on the right; heights scaled
    -- to the busiest day. Anchored just right of the trend text.
    local sparkFrame = CreateFrame("Frame", nil, trendRow)
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

    -- The table: the member with their avatar, their status as a badge, the counts, the last report.
    local COLS = { name = 30, status = 150, posts = 250, invites = 310, joined = 375, last = 440 }
    local header = Forms:TableHeader(card, {
        { L["Member"], COLS.name }, { L["Status"], COLS.status }, { L["Posts"], COLS.posts },
        { L["Invites"], COLS.invites }, { L["Joined"], COLS.joined }, { L["Last"], COLS.last },
    })
    card:Add(header, { h = 20, wide = true, gap = 10 })

    local listHolder = card:Body(ROW_H * 4, { gap = 2 })
    local _, content = MakeScrollList(listHolder, "GuildOSMgmtEngageScroll")

    -- One row per member, made once and reused. Every member's self-report repaints this tab, and a
    -- repaint used to make a new row per member and only hide the old ones: a big guild grew the list
    -- to thousands of frames, until `{ content:GetChildren() }` blew the stack (1426x, 7/11).
    local rowPool, emptyFS = {}, nil
    local function rowAt(idx)
        local row = rowPool[idx]
        if row then return row end
        row = MakeRow(content, 0, idx)
        row.av = UI:CreateAvatar(row, 20, false)
        row.av:SetPoint("LEFT", 2, 0)
        row.nameFS = UI:CreateText(row, "", 12, C.text.r, C.text.g, C.text.b)
        row.nameFS:SetPoint("LEFT", COLS.name, 0)
        row.nameFS:SetWidth(COLS.status - COLS.name - 8)
        row.nameFS:SetJustifyH("LEFT")
        row.nameFS:SetWordWrap(false)
        row.statusFS = Kit and Kit:Badge(row, "", "mute") or UI:CreateBadge(row, "", C.silver)
        row.statusFS:SetPoint("LEFT", COLS.status, 0)
        row.postsFS = UI:CreateText(row, "", 10, C.text.r, C.text.g, C.text.b)
        row.postsFS:SetPoint("LEFT", COLS.posts, 0)
        row.invitesFS = UI:CreateText(row, "", 10, C.text.r, C.text.g, C.text.b)
        row.invitesFS:SetPoint("LEFT", COLS.invites, 0)
        row.joinsFS = UI:CreateText(row, "", 10, C.text.r, C.text.g, C.text.b)
        row.joinsFS:SetPoint("LEFT", COLS.joined, 0)
        row.lastFS = UI:CreateText(row, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lastFS:SetPoint("LEFT", COLS.last, 0)
        for _, fs in ipairs({ row.postsFS, row.invitesFS, row.joinsFS }) do GuildOS:ApplyFont(fs, 11, "tableNum") end
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
            row.statusFS:SetText(sText, (sColor == C.green and WOOD.ok) or (sColor == C.silver and WOOD.warn) or WOOD.paperSoft)
            if row.av.SetMember then row.av:SetMember(r.name, r.class, r.stale) end

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
        .. L["They go to the Bulk actions queue: one click of Next each, the safe list and your rank's limits kept."]
end

local function BuildPresetsSub(panel)
    panel.expanded = {}
    panel.showChooser = false

    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtPresetsBoard" })
    local card = board:Card(L["Moderation presets"], { fill = true })
    -- A preset a row (the mockup's): its name and criteria, how many match, its thresholds, Preview and
    -- Apply at its right; "+ New" adds one.
    local newBtn = UI:CreateButton(card, L["+ New"], 80, 24)
    newBtn:SetWidth(math.ceil(newBtn.label:GetStringWidth() or 40) + 24)
    card:Flow({ newBtn })
    local listHolder = card:Body(ROW_H * 4, { gap = 10 })
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
            rule(block)

            -- Header line: name + criteria summary + remove. The name in `text`, not gold (#371).
            local nameFS = UI:CreateText(block, MP:Name(preset), 13, C.paperTitle.r, C.paperTitle.g, C.paperTitle.b)
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

            local countFS = Kit and Kit:Badge(block, format(L["%d match"], #matches), #matches > 0 and "warn" or "mute")
                or UI:CreateText(block, format(L["%d match"], #matches), 11, C.text.r, C.text.g, C.text.b)
            countFS:SetPoint("TOPLEFT", math.max(x + 8, 300), cy - 2)

            local applyBtn = UI:CreateButton(block, L["Apply"], 70, 20)
            applyBtn:SetWidth(math.ceil(applyBtn.label:GetStringWidth() or 40) + 16)
            UI:SetButtonVariant(applyBtn, "primary")
            applyBtn:SetPoint("TOPRIGHT", -8, cy)
            applyBtn:SetScript("OnClick", function()
                if not GuildOS:IsOfficer() then GuildOS:Print(L["Officers only."]) return end
                local live = MP:GetMatches(preset)
                if #live == 0 then GuildOS:Print(L["No members match this preset."]) return end
                GuildOS:ShowDialog("GUILDOS_MODPRESET_APPLY", presetApplyText(preset, live), nil,
                    { preset = preset, matches = live })
            end)

            local prevBtn = UI:CreateButton(block, L["Preview"], 70, 20)
            prevBtn:SetWidth(math.ceil(prevBtn.label:GetStringWidth() or 40) + 16)
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
    -- The cards move up when the room hides the bar (#445).
    UI:CollapsibleSubBar(parent, bar, function()
        local cards = {}
        for k, info in pairs(parent.subPanels) do cards[k] = info.panel end
        return cards
    end, { 0, -GAP })   -- the Officers' Room (#445)

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

    -- One area per sub-tab, all sharing the room below the bar: on the wood, where each screen lays its
    -- parchment cards (UI/Forms.lua, the mockup's). Flush with the bar's left edge, GAP under it, ending GAP short
    -- of its right edge (the bar spans the parent less 10px a side), as every screen's content does (#371).
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
        bulk     = function(p) return GuildOS.BuildBulkSub and GuildOS:BuildBulkSub(p) end,
        remind   = function(p) return GuildOS.BuildRemindSub and GuildOS:BuildRemindSub(p) end,
        marks    = function(p) return GuildOS.BuildMarksSub and GuildOS:BuildMarksSub(p) end,
        alerts   = function(p) return GuildOS.BuildModAlertsSub and GuildOS:BuildModAlertsSub(p) end,
        alertrules = function(p) return GuildOS.BuildModRulesSub and GuildOS:BuildModRulesSub(p) end,
    }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel(t.key)
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
    UI:MakeResponsive(parent, function(_, w, h)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        UI:FlowBar(bar, subTabList, { gap = 4, rowGap = 4, rowH = TAB_H })
        -- Each screen's cards at the area's width and height (its anchors say so; the game says so a frame later).
        local areaW = w - 20 - GAP
        local areaH = h - 8 - 10 - (bar:IsShown() and ((tonumber(bar:GetHeight()) or TAB_H) + GAP) or 0)
        for _, info in pairs(parent.subPanels) do
            local b = rawget(info.panel, "board")
            if type(b) == "table" and b.Layout then b:Layout(areaW - GUTTER, areaH) end
        end
        parent.RefreshActive()
    end)
end
