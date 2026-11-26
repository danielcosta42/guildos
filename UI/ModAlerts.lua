----------------------------------------------------------------------
-- Guild OS - The officers' chat alerts on screen (issues #404, #405)
--
-- The alert itself (a small window: who, the two lines before, the line, the category; Warn, Ignore,
-- Mute this pattern for 1h) and the Leadership screen's two sub-tabs: the alerts heard this session and
-- the guild's rules. The logic is ModAlerts' (and ModFlood's); this file only lays it out.
----------------------------------------------------------------------
local UI = GuildOS.UI
-- Drawn on a parchment card in the Officers' Room and Settings (specs/salao/fase3.md): the text takes the
-- paper's inks and a class its colour on the paper (UI/Kit.lua); a floating window, the wood's (WOOD).
local Kit = rawget(GuildOS, "Kit")
local C = Kit and Kit.PAPER or GuildOS.Colors
local WOOD = GuildOS.Colors
local function rule(row) if Kit then Kit:Rule(row) end end
local function checkbox(parent, text, size)
    if Kit then return Kit:Checkbox(parent, text, size) end
    return GuildOS.UI:CreateCheckbox(parent, text, size)
end
local L = GuildOS.L
local WHITE8 = "Interface\\Buttons\\WHITE8x8"

local ROW_H = 44
local RULE_ROW = UI.SP.ROW   -- a rule's row in the Alert rules list

local function text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    return fs
end

local function clock(t)
    return date("%H:%M", t or GetServerTime())
end

-- An alert's lines as the window and the list show them: the screen's text, without colours or links.
local function plain(s) return GuildOS.ModAlerts.Plain(s or "") end

-- What an alert is about: its category, and for a surge (#405) the signals it fired.
local function aboutText(a)
    local t = GuildOS.ModAlerts.CategoryText(a.cat)
    local F = GuildOS.ModFlood
    if a.signals and F then
        local parts = {}
        for i, sig in ipairs(a.signals) do parts[i] = F.SignalText(sig) end
        t = t .. " (" .. table.concat(parts, ", ") .. ")"
    end
    -- A newcomer's (#406): the badge, on the officers' screens only.
    local badge = GuildOS.Newcomer and GuildOS.Newcomer.BadgeText(a.newcomer)
    if badge then t = t .. " - " .. badge end
    return t
end

----------------------------------------------------------------------
-- The alert window
----------------------------------------------------------------------
-- A severity's short word (the badge's): what SeverityText says before its colon ("Low: log only" -> "Low").
local function sevWord(sev)
    local t = GuildOS.ModAlerts.SeverityText(sev)
    return (tostring(t):gsub("%s*[:：].*$", ""))
end
local SEV_COLOR = { low = "textSoft", med = "warn", high = "danger" }
local function sevColor(sev) return WOOD[SEV_COLOR[sev] or "warn"] or WOOD.warn end

-- A speaker's class, from the roster (nil when the roster does not know them).
local function classOf(name)
    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" or not name then return nil end
    for i = 1, GetNumGuildMembers() or 0 do
        local full, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if full and (full == name or full:match("^([^-]+)") == name) then return classFile end
    end
end
local function speaker(name)
    local cls = classOf(name)
    local hexc = cls and GuildOS:GetClassColorHex(cls)
    return (type(hexc) == "string" and hexc ~= "") and ("|c" .. (#hexc == 6 and "ff" or "") .. hexc .. tostring(name) .. "|r") or tostring(name)
end

-- Why it fired: the rule (its category and pattern) and how often this session's feed has it.
local function whyText(a)
    local M = GuildOS.ModAlerts
    local why = aboutText(a)
    local pattern = type(a.rule) == "string" and a.rule:match("^[WL]:(.*)$")
    if pattern and pattern ~= "" then why = why .. " «" .. pattern .. "»" end
    local n = 0
    for _, other in ipairs(M:Feed()) do if a.rule and other.rule == a.rule then n = n + 1 end end
    if n > 1 then why = why .. " · " .. string.format(L["%d times in the last two hours"], n) end
    return string.format("%s: %s", L["Why"], why)
end

local POP_W, POP_PAD = 420, 14
function GuildOS:ShowModAlert(a)
    local M = GuildOS.ModAlerts
    if not M or not GuildOS:IsOfficer() then return end
    local f = self.modAlertFrame
    if not f then
        -- A floating window (the mockup's .fw "chatAlert"): the header says it is an alert, how grave (a badge)
        -- and where and when; the chat around the line in the soft ink, the line as a framed quote with a bar
        -- in the severity's colour, why it fired; the answers at the bottom right, Warn the main one.
        f = CreateFrame("Frame", "GuildOSModAlert", UIParent, "BackdropTemplate")
        f:SetSize(POP_W, 220)
        f:SetPoint("TOP", 0, -140)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        if Kit then Kit:Dress(f, L["Chat alert"]) end
        local hdr = rawget(f, "header") or f
        f.badge = UI:CreateBadge(hdr, "", WOOD.warn)
        if rawget(f, "titleText") then
            f.badge:SetPoint("LEFT", f.titleText, "RIGHT", 8, 0)
            if rawget(f, "subText") then
                f.subText:ClearAllPoints()
                f.subText:SetPoint("LEFT", f.badge, "RIGHT", 8, 0)
            end
        end
        local top = Kit and (Kit.HEADER_H + 10) or 12
        local inner = POP_W - 2 * POP_PAD

        f.context = text(f, 11, WOOD.textSoft)
        f.context:SetPoint("TOPLEFT", POP_PAD, -top)
        f.context:SetWidth(inner)
        f.context:SetWordWrap(true)

        -- The flagged line: a framed quote, a bar at its left in the severity's colour.
        f.quote = CreateFrame("Frame", nil, f)
        f.quote:SetPoint("TOPLEFT", f.context, "BOTTOMLEFT", 0, -8)
        f.quote:SetSize(inner, 24)
        local qbg = f.quote:CreateTexture(nil, "BACKGROUND")
        qbg:SetTexture(WHITE8)
        qbg:SetAllPoints()
        qbg:SetVertexColor(1, 1, 1, 0.06)
        f.bar = f.quote:CreateTexture(nil, "BORDER")
        f.bar:SetTexture(WHITE8)
        f.bar:SetPoint("TOPLEFT", 0, 0)
        f.bar:SetPoint("BOTTOMLEFT", 0, 0)
        f.bar:SetWidth(3)
        f.line = text(f.quote, 12, WOOD.text)
        f.line:SetPoint("TOPLEFT", 12, -6)
        f.line:SetWidth(inner - 20)
        f.line:SetWordWrap(true)

        -- Why it fired (the rule, how often), under the quote.
        f.title = text(f, 11, WOOD.textSoft)
        f.title:SetPoint("TOPLEFT", f.quote, "BOTTOMLEFT", 0, -8)
        f.title:SetWidth(inner)
        f.title:SetWordWrap(true)

        -- The footer: what else waits (left, or over the buttons when they leave it no room), the answers at the
        -- right, on two rows when one does not hold them.
        f.foot = CreateFrame("Frame", nil, f)
        f.foot:SetPoint("BOTTOMLEFT", 0, 0)
        f.foot:SetPoint("BOTTOMRIGHT", 0, 0)
        f.foot:SetHeight(40)
        local frule = f.foot:CreateTexture(nil, "BORDER")
        frule:SetTexture(WHITE8)
        frule:SetPoint("TOPLEFT", 3, 0)
        frule:SetPoint("TOPRIGHT", -3, 0)
        UI:Hairline(frule)
        frule:SetVertexColor(0.227, 0.165, 0.09, 1)
        f.more = text(f.foot, UI.SP.META, WOOD.textSoft)
        f.more:SetWordWrap(true)
        f.ignore = UI:CreateButton(f.foot, L["Ignore"], 90, 24)
        f.mute = UI:CreateButton(f.foot, L["Mute this pattern for 1h"], 180, 24)
        f.warn = UI:CreateButton(f.foot, L["Warn"], 90, 24)
        UI:SetButtonVariant(f.warn, "primary")
        for _, btn in ipairs({ f.ignore, f.mute, f.warn }) do
            btn:SetWidth(math.ceil(tonumber(btn.label:GetStringWidth()) or 60) + 24)
        end
        if not Kit then
            local closeBtn = UI:CreateCloseButton(f)
            closeBtn:SetPoint("TOPRIGHT", -4, -4)
            closeBtn:SetScript("OnClick", function() f:Hide() end)
        end
        self.modAlertFrame = f

        -- An alert acted on from the list closes the window showing it; one that grew redraws it.
        M.popupRefresh = function()
            if f:IsShown() and f.alert and f.alert.state ~= "new" then f:Hide() end
        end
        M.popupUpdate = function(grown)
            if f:IsShown() and f.alert == grown then GuildOS:ShowModAlert(grown) end
        end
    end
    f.alert = a
    local inner = POP_W - 2 * POP_PAD
    f.badge:SetText(sevWord(a.sev), sevColor(a.sev))
    if rawget(f, "subText") then f.subText:SetText(L["Guild chat"] .. " · " .. clock(a.said or a.at)) end
    f.title:SetText(whyText(a))
    local ctx = {}
    if a.lines then
        -- A surge (#405): its lines, the newest last.
        for i = math.max(1, #a.lines - 3), #a.lines - 1 do ctx[#ctx + 1] = speaker(a.who) .. ": " .. plain(a.lines[i]) end
    else
        for _, e in ipairs(a.context or {}) do ctx[#ctx + 1] = speaker(tostring(e.n or "?")) .. ": " .. plain(e.m) end
    end
    f.context:SetText(#ctx > 0 and table.concat(ctx, "\n") or L["(nothing said before it)"])
    local shown = a.lines and a.lines[#a.lines] or a.line
    local head = a.count and string.format(L["%s (%d lines)"], a.who, a.count) or a.who
    f.line:SetText(speaker(head) .. ": " .. plain(shown))
    local sc = sevColor(a.sev)
    f.bar:SetVertexColor(sc.r, sc.g, sc.b, 1)
    local waiting = 0
    for _, other in ipairs(M:Feed()) do
        if other ~= a and other.state == "new" and other.sev ~= "low" and not other.by then waiting = waiting + 1 end
    end
    f.more:SetText(waiting > 0 and string.format(L["%d more on Leadership > Chat alerts."], waiting) or "")
    f.mute:SetShown(a.rule ~= nil)

    -- The footer: buttons from the right, wrapping to a second row when they do not fit; the meta left of them
    -- when it fits there, else over them.
    local function num(v, d) return tonumber(v) or d end
    local btns = { f.warn, f.mute, f.ignore }
    local rows, row, used = {}, {}, 0
    for _, b in ipairs(btns) do
        if b:IsShown() then
            local bw = num(b:GetWidth(), 90)
            if #row > 0 and used + 6 + bw > inner then rows[#rows + 1] = row; row, used = {}, 0 end
            row[#row + 1] = b
            used = used + (#row > 1 and 6 or 0) + bw
        end
    end
    if #row > 0 then rows[#rows + 1] = row end
    local firstW = 0
    for i, b in ipairs(rows[#rows] or {}) do firstW = firstW + num(b:GetWidth(), 90) + (i > 1 and 6 or 0) end
    local metaW = num(f.more:GetStringWidth(), 0)
    local metaBeside = #rows == 1 and (metaW == 0 or metaW + 12 <= inner - firstW)
    local y = 8
    for r = #rows, 1, -1 do
        local x = POP_PAD
        for _, b in ipairs(rows[r]) do
            b:ClearAllPoints()
            b:SetPoint("BOTTOMRIGHT", f.foot, "BOTTOMRIGHT", -x, y)
            x = x + num(b:GetWidth(), 90) + 6
        end
        y = y + 24 + 6
    end
    local footH = y + 2
    f.more:ClearAllPoints()
    if metaBeside then
        f.more:SetPoint("LEFT", f.foot, "BOTTOMLEFT", POP_PAD, 8 + 12)
        f.more:SetWidth(math.max(1, inner - firstW - 12))
    else
        f.more:SetPoint("BOTTOMLEFT", f.foot, "BOTTOMLEFT", POP_PAD, y)
        f.more:SetWidth(inner)
        if metaW > 0 then footH = y + num(f.more:GetStringHeight(), 12) + 6 end
    end
    f.foot:SetHeight(footH)

    -- Tall enough for the chat around the line, the quote and why.
    local top = Kit and (Kit.HEADER_H + 10) or 12
    local function h(fs, d) return num(fs:GetStringHeight(), d) end
    local qh = h(f.line, 14) + 12
    f.quote:SetHeight(qh)
    f:SetHeight(math.max(160, top + h(f.context, 14) + 8 + qh + 8 + h(f.title, 12) + 10 + footH))
    local id = a.id
    f.warn:SetScript("OnClick", function() M:Warn(id); f:Hide() end)
    f.ignore:SetScript("OnClick", function() M:Ignore(id); f:Hide() end)
    f.mute:SetScript("OnClick", function() M:MuteRule(id); f:Hide() end)
    f:Show()
end

----------------------------------------------------------------------
-- Leadership > Chat alerts: what was flagged this session
----------------------------------------------------------------------
local STATE_TEXT = { warned = L["warned"], ignored = L["ignored"] }

function GuildOS:BuildModAlertsSub(panel)
    local M = GuildOS.ModAlerts
    local board = UI:CreateBoard(panel, { name = "GuildOSModAlertsBoard" })
    local card = board:Card(L["Chat alerts"], { fill = true })
    card:Note(L["Lines of guild chat that match the guild's rules, for the officers only. Kept in memory for two hours; a line is stored only when you warn."])
    -- This officer's own switches, side by side as the card's width allows.
    local prefs = M and M:Prefs() or {}
    local boxes = {
        { "enabled", L["Alerts on"] }, { "officers", L["Also officers' lines"] },
        { "own", L["Also my own lines"] }, { "sound", L["Sound on high"] },
    }
    local checks = {}
    for _, b in ipairs(boxes) do
        local cb = checkbox(card, b[2], 18)
        cb:SetWidth(math.ceil(tonumber(cb.label and cb.label:GetStringWidth()) or 100) + 30)
        cb.checkbox:SetChecked(prefs[b[1]] and true or false)
        cb.checkbox.onChanged = function(_, checked) prefs[b[1]] = checked and true or false end
        checks[#checks + 1] = cb
    end
    card:Flow(checks, { gapX = 16, rowH = 18 })
    local paused = card:Note(L["Alerts paused: the game hides the chat in instances and combat."],
        { ink = C.red, shown = function() return M and M:Paused() or false end })

    local holder = card:Body(ROW_H * 3, { gap = 10 })
    local scroll = CreateFrame("ScrollFrame", "GuildOSModAlertsScroll", holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(scroll, "GuildOSModAlertsScroll")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    UI:BindScrollChildWidth(scroll, content)

    -- One frame per row, made once and refilled: a busy evening must not stack frames.
    local rows = {}
    local function rowAt(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + 2)))
        row:SetPoint("TOPRIGHT", 0, -((i - 1) * (ROW_H + 2)))
        rule(row)
        -- The mockup's .todo: a red "!" glyph, who and why over the line, the answers at the right.
        row.ic = CreateFrame("Frame", nil, row)
        row.ic:SetSize(24, 24)
        row.ic:SetPoint("LEFT", 0, 0)
        row.icFill = row.ic:CreateTexture(nil, "BACKGROUND")
        row.icFill:SetTexture(WHITE8)
        row.icFill:SetAllPoints()
        local bang = text(row.ic, 13, WOOD.text)
        bang:SetText("!")
        bang:SetPoint("CENTER", 0, 0)
        bang:SetTextColor(1, 1, 1)
        row.top = text(row, 11, C.label)
        row.top:SetPoint("TOPLEFT", 32, -5)
        row.top:SetWordWrap(false)
        row.line = text(row, 11, C.text)
        GuildOS:ApplyFont(row.line, 12, "reading")
        row.line:SetPoint("TOPLEFT", 32, -22)
        row.line:SetWordWrap(false)
        -- The answers at the row's right, each as wide as its word, side by side (the mockup's small buttons).
        row.mute = UI:CreateButton(row, L["Mute 1h"], 70, 20)
        row.mute:SetPoint("RIGHT", -2, 0)
        row.ignore = UI:CreateButton(row, L["Ignore"], 70, 20)
        row.ignore:SetPoint("RIGHT", row.mute, "LEFT", -6, 0)
        row.warn = UI:CreateButton(row, L["Warn"], 70, 20)
        UI:SetButtonVariant(row.warn, "primary")
        row.warn:SetPoint("RIGHT", row.ignore, "LEFT", -6, 0)
        for _, b in ipairs({ row.mute, row.ignore, row.warn }) do
            b:SetWidth(math.max(56, math.ceil(tonumber(b.label and b.label:GetStringWidth()) or 50) + 16))
        end
        row.top:SetPoint("RIGHT", row.warn, "LEFT", -10, 0)
        row.line:SetPoint("RIGHT", row.warn, "LEFT", -10, 0)
        row.mute:SetScript("OnClick", function() M:MuteRule(row.id) end)
        row.ignore:SetScript("OnClick", function() M:Ignore(row.id) end)
        row.warn:SetScript("OnClick", function() M:Warn(row.id) end)
        rows[i] = row
        return row
    end
    local empty = UI:CreateText(content, "", 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    local function refresh()
        -- Off screen nothing is drawn: showing the tab draws it (as Engagement, #371).
        if not M or not panel:IsVisible() then return end
        local feed = M:Feed()
        for i, a in ipairs(feed) do
            local row = rowAt(i)
            row.id = a.id
            local status = STATE_TEXT[a.state] or ""
            if a.by then status = string.format(L["alerted on %s's screen"], a.by) .. (status ~= "" and (", " .. status) or "") end
            if a.sev == "low" and status == "" then status = L["logged"] end
            -- Heard in combat or an instance (audit B4): no window was opened for it.
            if a.held then status = L["in combat: panel only"] .. (status ~= "" and (", " .. status) or "") end
            -- Said while this officer was away (#411): when it was said, and so marked.
            if a.away then status = L["while you were away"] .. (status ~= "" and (", " .. status) or "") end
            local who = a.count and string.format(L["%s (%d lines)"], a.who, a.count) or a.who
            row.top:SetText(string.format("%s  %s  -  %s  %s", clock(a.said or a.at), who, aboutText(a),
                status ~= "" and ("(" .. status .. ")") or ""))
            local ink = a.state == "new" and C.text or C.textDim
            row.line:SetTextColor(ink.r, ink.g, ink.b)
            row.line:SetText(plain(a.lines and a.lines[#a.lines] or a.line))
            local sc = WOOD[(a.sev == "high" and "danger") or (a.sev == "low" and "textSoft") or "warn"] or WOOD.warn
            row.icFill:SetVertexColor(sc.r, sc.g, sc.b, 1)
            row.mute:SetShown(a.rule ~= nil and a.state == "new")
            row.ignore:SetShown(a.state == "new")
            row:Show()
        end
        for i = #feed + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#feed == 0)
        empty:SetText(#M:GetRules() == 0
            and L["The guild's list is empty: nothing will alert. Add words on the Alert rules tab."]
            or L["No alerts this session."])
        content:SetHeight(math.max(1, #feed * (ROW_H + 2)))
        board:Layout()
    end

    -- The lockdown starts and ends without a line: while the tab shows, look every two seconds.
    local acc, wasPaused = 0, nil
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 2 then return end
        acc = 0
        local now = M and M:Paused() or false
        if now ~= wasPaused then wasPaused = now; board:Layout() end
    end)
    local _ = paused
    if M then M.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- Leadership > Alert rules: the guild's list (and the anti-flood's limits, #405)
----------------------------------------------------------------------
local RULE_WHY = {
    empty = L["Type a word or a pattern."],
    long = L["At most 60 characters."],
    invalid = L["That Lua pattern is not valid."],
    broad = L["That pattern matches every line."],
    slow = L["Use at most one repetition (*, + or -) in a pattern: more would freeze the game."],
    case = L["Write the pattern in lower case: lines are compared that way."],
    dupe = L["That rule is already on the list."],
    full = L["The list is full."],
    officer = L["|cffFF4444Officers only.|r"],
}

function GuildOS:BuildModRulesSub(panel)
    local M = GuildOS.ModAlerts
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSModRulesBoard" })
    -- The words and patterns (the mockup's first card): a new one's form, then the list.
    local card = board:Card(L["Alert rules"], { col = 1, fill = true, minH = 360 })
    local hint = card:Note(L["The guild's words and patterns, shared by the officers. A word matches whole, without case or accents."])
    local input = UI:CreateInput(card, 170, 24, { max = M and M.PATTERN_MAX or 60, placeholder = L["word or phrase"] })
    card:Field("", input, { gap = 10 })
    local catDD = UI:CreateDropdown(card, 150, 24)
    local cats = {}
    for _, c in ipairs(M and M.CATEGORIES or {}) do cats[#cats + 1] = { value = c, text = M.CategoryText(c) } end
    catDD:SetOptions(cats)
    catDD:SetValue("custom")
    local sevDD = UI:CreateDropdown(card, 160, 24)
    local sevs = {}
    for _, sv in ipairs(M and M.SEVERITIES or {}) do sevs[#sevs + 1] = { value = sv, text = M.SeverityText(sv) } end
    sevDD:SetOptions(sevs)
    sevDD:SetValue("med")
    card:Pair(Forms:MakeField(card, L["Category"], catDD), Forms:MakeField(card, L["Severity"], sevDD))
    local luaChk = card:Check(L["Lua pattern"])
    local result = card:Note("", { ink = C.red })
    local restore = UI:CreateButton(card, L["Restore the default list"], 170, 24)
    restore:SetWidth(math.ceil(tonumber(restore.label:GetStringWidth()) or 150) + 24)
    local addBtn = UI:CreateButton(card, L["Add"], 70, 24)
    UI:SetButtonVariant(addBtn, "primary")
    card:Actions({ restore, addBtn })

    local function add()
        if not M then return end
        local ok, why = M:AddRule(input:GetText(), catDD:GetValue(), sevDD:GetValue(), luaChk.checkbox:GetChecked() and true or false)
        if ok then
            input:SetText("")
            input:ClearFocus()
            result:SetText("")
        else
            result:SetText(RULE_WHY[why] or RULE_WHY.empty)
        end
        board:Layout()
    end
    addBtn:SetScript("OnClick", add)
    input:HookScript("OnEnterPressed", add)
    restore:SetScript("OnClick", function() if M then M:RestoreDefaults() end end)

    -- The anti-flood's limits (#405) and the newcomer's quarantine (#406), each a card beside the rules.
    if GuildOS.BuildModFloodSection then GuildOS:BuildModFloodSection(panel, board) end
    if GuildOS.BuildNewcomerSection then GuildOS:BuildNewcomerSection(panel, board) end

    local header = Forms:TableHeader(card, { { L["Word or pattern"], 0 }, { L["Category"], 210 }, { L["Severity"], 360 } })
    card:Add(header, { h = 20, wide = true, gap = 12 })
    local holder = card:Body(24 * 4, { gap = 2 })
    local scroll = CreateFrame("ScrollFrame", "GuildOSModRulesScroll", holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(scroll, "GuildOSModRulesScroll")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    UI:BindScrollChildWidth(scroll, content)

    local rows = {}
    local function rowAt(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(RULE_ROW)
        rule(row)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * RULE_ROW))
        row:SetPoint("TOPRIGHT", 0, -((i - 1) * RULE_ROW))
        row.p = text(row, UI.SP.BODY, C.text)
        row.p:SetPoint("LEFT", 0, 0)
        row.p:SetWidth(200)
        row.p:SetJustifyH("LEFT")
        row.p:SetWordWrap(false)
        row.cat = text(row, UI.SP.BODY, C.textDim)
        row.cat:SetPoint("LEFT", 210, 0)
        row.cat:SetWidth(140)
        row.cat:SetWordWrap(false)
        -- A click moves the severity on: low, medium, high (audit B5).
        row.sev = UI:CreateButton(row, "", 150, RULE_ROW - 6)
        row.sev:SetPoint("LEFT", 360, 0)
        row.sev:SetScript("OnClick", function()
            local r = M:GetRules()[row.index]
            if r then M:SetRuleSeverity(row.index, M.NextSeverity(r.sev)) end
        end)
        UI:AddTooltip(row.sev, L["Severity"], { L["Click to change: low only logs, medium alerts, high alerts with a sound."] })
        row.del = UI:CreateButton(row, "\195\151", UI.SP.HIT, RULE_ROW - 6)  -- ×
        row.del:SetPoint("RIGHT", 0, 0)
        row.del:SetScript("OnClick", function() M:RemoveRule(row.index) end)
        rows[i] = row
        return row
    end
    local empty = UI:CreateText(content,
        L["The list is empty: nothing will alert. Add a word above, or restore the default list."],
        UI.SP.BODY, C.silver.r, C.silver.g, C.silver.b)
    -- An empty list is a centred line across it, never a grey line in its corner (#449).
    empty:SetPoint("TOPLEFT", 0, -UI.SP.FIELD_GAP)
    empty:SetPoint("TOPRIGHT", 0, -UI.SP.FIELD_GAP)
    empty:SetJustifyH("CENTER")
    empty:SetWordWrap(true)

    local function refresh()
        if not M or not panel:IsVisible() then return end
        if panel.floodRefresh then GuildOS:SafeCall(panel.floodRefresh) end
        if panel.newcomerRefresh then GuildOS:SafeCall(panel.newcomerRefresh) end
        local rules = M:GetRules()
        -- The columns share the list's width: the pattern, its category, its severity, the remove at the right.
        local W = math.max(300, tonumber(content:GetWidth()) or 400)
        local catX, sevX = math.floor(W * 0.4), math.floor(W * 0.64)
        local sevW = math.max(90, W - sevX - 30)
        header.cols[2]:ClearAllPoints(); header.cols[2]:SetPoint("LEFT", header, "LEFT", catX, 0)
        header.cols[3]:ClearAllPoints(); header.cols[3]:SetPoint("LEFT", header, "LEFT", sevX, 0)
        for i, r in ipairs(rules) do
            local row = rowAt(i)
            row.index = i
            row.p:SetWidth(catX - 8)
            row.cat:ClearAllPoints(); row.cat:SetPoint("LEFT", catX, 0); row.cat:SetWidth(sevX - catX - 8)
            row.sev:ClearAllPoints(); row.sev:SetPoint("LEFT", sevX, 0); row.sev:SetWidth(sevW)
            row.p:SetText(r.lua and (r.p .. "  |cff888888(" .. L["Lua pattern"] .. ")|r") or r.p)
            row.cat:SetText(M.CategoryText(r.cat))
            row.sev.label:SetText(M.SeverityText(r.sev))
            row:Show()
        end
        for i = #rules + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#rules == 0)
        -- Until an officer saves, these are the defaults of this client's language (audit B5).
        hint:SetText(M:IsCustomList() and L["The guild's words and patterns, shared by the officers. A word matches whole, without case or accents."]
            or L["The default list in your language. Your first change makes it the one list every officer matches."])
        content:SetHeight(#rules == 0 and 2 * UI.SP.FIELD_GAP + math.ceil(empty:GetStringHeight() or 14) or #rules * RULE_ROW)
        board:Layout()
    end
    if M then M.rulesRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- The anti-flood's limits (#405), on the Alert rules tab under the rules' form
----------------------------------------------------------------------
-- Builds the anti-flood's card on `board` (the Alert rules screen's); panel.floodRefresh fills it.
function GuildOS:BuildModFloodSection(panel, board)
    local F = GuildOS.ModFlood
    if not F or type(board) ~= "table" or not board.Card then return 0 end
    local card = board:Card(L["Anti-flood"], { col = 2 })
    card:Note(L["Each signal flags one alert per person while the surge lasts. The game's item and spell links never count."])

    -- One row per signal: its switch, then its two limits with their words between, wrapping on a narrow card.
    local ROWS = {
        { sig = "burst", label = L["Too many lines"], a = "n", mid = L["lines in"], b = "secs", tail = L["seconds"] },
        { sig = "repeat", label = L["The same line repeated"], a = "n", mid = L["times in"], b = "secs", tail = L["seconds"] },
        { sig = "caps", label = L["Capitals"], a = "pct", mid = L["percent of the letters, in lines of at least"], b = "min", tail = L["letters"] },
        { sig = "links", label = L["Links"], a = "n", mid = L["links in"], b = "secs", tail = L["seconds"] },
    }
    local fields = {}
    for _, row in ipairs(ROWS) do
        local cb = card:Check(row.label, nil, { gap = 10 })
        local line = CreateFrame("Frame", nil, card)
        line:SetSize(1, 22)
        local boxA = UI:CreateInput(line, 44, 22, { numeric = true, max = 3, justify = "CENTER" })
        local mid = UI:CreateText(line, row.mid, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        local boxB = UI:CreateInput(line, 44, 22, { numeric = true, max = 3, justify = "CENTER" })
        local tail = UI:CreateText(line, row.tail, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        for _, fs in ipairs({ mid, tail }) do fs:SetJustifyH("LEFT"); fs:SetWordWrap(false) end
        card:Add(line, { gap = 4, indent = 24, place = function(_, w)
            local midW = math.ceil(tonumber(mid:GetStringWidth()) or 60)
            local tailW = math.ceil(tonumber(tail:GetStringWidth()) or 40)
            boxA:ClearAllPoints(); boxA:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
            mid:ClearAllPoints(); mid:SetPoint("LEFT", boxA, "RIGHT", 6, 0)
            local oneLine = 44 + 6 + midW + 6 + 44 + 6 + tailW <= w
            mid:SetWidth(math.max(1, math.min(midW, w - 50)))
            boxB:ClearAllPoints()
            if oneLine then
                boxB:SetPoint("LEFT", mid, "RIGHT", 6, 0)
            else
                boxB:SetPoint("TOPLEFT", line, "TOPLEFT", 0, -28)
            end
            tail:ClearAllPoints(); tail:SetPoint("LEFT", boxB, "RIGHT", 6, 0)
            tail:SetWidth(math.max(1, math.min(tailW, w - 50)))
            local h = oneLine and 22 or 50
            line:SetSize(math.max(1, w), h)
            return h
        end })
        fields[row.sig] = { cb = cb, a = boxA, b = boxB, row = row }
    end
    local result = card:Note("")
    local save = UI:CreateButton(card, L["Save limits"], 110, 24)
    UI:SetButtonVariant(save, "primary")
    save:SetWidth(math.ceil(tonumber(save.label:GetStringWidth()) or 80) + 24)
    card:Actions({ save })

    save:SetScript("OnClick", function()
        local cfg = {}
        for sig, f in pairs(fields) do
            local a, b = F.ValidLimit(f.row.a, f.a:GetText()), F.ValidLimit(f.row.b, f.b:GetText())
            if not a or not b then
                result:SetText(L["Out of range: lines 2-50, seconds 5-600, percent 50-100, letters 5-100."])
                return
            end
            cfg[sig] = { on = f.cb.checkbox:GetChecked() and true or false, [f.row.a] = a, [f.row.b] = b }
        end
        local ok = F:SetConfig(cfg)
        result:SetText(ok and L["Limits saved for the guild."] or L["|cffFF4444Officers only.|r"])
        board:Layout()
    end)

    panel.floodRefresh = function()
        local cfg = F:GetConfig()
        for sig, f in pairs(fields) do
            local c = cfg[sig]
            f.cb.checkbox:SetChecked(c.on and true or false)
            if not f.a:HasFocus() then f.a:SetText(tostring(c[f.row.a])) end
            if not f.b:HasFocus() then f.b:SetText(tostring(c[f.row.b])) end
        end
    end
    return card
end

----------------------------------------------------------------------
-- The newcomer's quarantine (#406), on the Alert rules tab under the anti-flood
----------------------------------------------------------------------
-- Builds the newcomers' card on `board` (the Alert rules screen's); panel.newcomerRefresh fills it.
function GuildOS:BuildNewcomerSection(panel, board)
    local N = GuildOS.Newcomer
    if not N or type(board) ~= "table" or not board.Card then return 0 end
    local card = board:Card(L["Newcomers"], { col = 2 })
    card:Note(L["In a member's first days any link alerts and the anti-flood's limits are stricter. The join comes from the roster log: a member who joined before the addon is not a newcomer. Only officers see it."])
    local box = UI:CreateInput(card, 50, 24, { numeric = true, max = 2, justify = "CENTER" })
    card:Field(L["Newcomer for the first"], box, { w = 70, hint = L["days (0 turns it off)"], gap = 10 })
    local trial = card:Check(L["A trial counts as a newcomer"])
    local result = card:Note("")
    local save = UI:CreateButton(card, L["Save for the guild"], 140, 24)
    UI:SetButtonVariant(save, "primary")
    save:SetWidth(math.ceil(tonumber(save.label:GetStringWidth()) or 100) + 24)
    card:Actions({ save })
    save:SetScript("OnClick", function()
        local ok, why = N:SetConfig(box:GetText(), trial.checkbox:GetChecked() and true or false)
        if ok then
            result:SetText(L["Saved. The guild gets it now."])
        elseif why == "range" then
            result:SetText(L["From 0 to 30 days."])
        else
            result:SetText(L["|cffFF4444Officers only.|r"])
        end
        board:Layout()
    end)
    panel.newcomerRefresh = function()
        if not box:HasFocus() then box:SetText(tostring(N:GetDays())) end
        trial.checkbox:SetChecked(N:TrialCounts())
    end
    return card
end
