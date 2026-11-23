----------------------------------------------------------------------
-- Guild OS - The officers' chat alerts on screen (issues #404, #405)
--
-- The alert itself (a small window: who, the two lines before, the line, the category; Warn, Ignore,
-- Mute this pattern for 1h) and the Leadership screen's two sub-tabs: the alerts heard this session and
-- the guild's rules. The logic is ModAlerts' (and ModFlood's); this file only lays it out.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE8 = "Interface\\Buttons\\WHITE8x8"

local ROW_H = 44
local GUTTER = tonumber(UI.SCROLL_GUTTER) or 12

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
function GuildOS:ShowModAlert(a)
    local M = GuildOS.ModAlerts
    if not M or not GuildOS:IsOfficer() then return end
    local f = self.modAlertFrame
    if not f then
        f = CreateFrame("Frame", "GuildOSModAlert", UIParent, "BackdropTemplate")
        f:SetSize(420, 210)
        f:SetPoint("TOP", 0, -140)
        f:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = UI:Edge(f) })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

        f.title = f:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(f.title, nil, "sectionTitle")
        f.title:SetPoint("TOPLEFT", 14, -10)
        f.title:SetTextColor(C.text.r, C.text.g, C.text.b)

        f.context = text(f, 10, C.silver)
        f.context:SetPoint("TOPLEFT", 14, -36)
        f.context:SetWidth(392)
        f.context:SetWordWrap(true)

        f.line = text(f, 12, C.text)
        f.line:SetPoint("TOPLEFT", f.context, "BOTTOMLEFT", 0, -6)
        f.line:SetWidth(392)
        f.line:SetWordWrap(true)

        f.more = text(f, 9, C.silver)
        f.more:SetPoint("BOTTOMLEFT", 14, 44)

        f.warn = UI:CreateButton(f, L["Warn"], 90, 24)
        f.warn:SetPoint("BOTTOMLEFT", 14, 12)
        f.ignore = UI:CreateButton(f, L["Ignore"], 90, 24)
        f.ignore:SetPoint("LEFT", f.warn, "RIGHT", 8, 0)
        f.mute = UI:CreateButton(f, L["Mute this pattern for 1h"], 180, 24)
        f.mute:SetPoint("LEFT", f.ignore, "RIGHT", 8, 0)

        local closeBtn = UI:CreateCloseButton(f)
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function() f:Hide() end)
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
    f.title:SetText(string.format(L["Chat alert: %s"], aboutText(a)))
    local ctx = {}
    if a.lines then
        -- A surge (#405): its lines, the newest last.
        for i = math.max(1, #a.lines - 3), #a.lines - 1 do ctx[#ctx + 1] = a.who .. ": " .. plain(a.lines[i]) end
    else
        for _, e in ipairs(a.context or {}) do ctx[#ctx + 1] = tostring(e.n or "?") .. ": " .. plain(e.m) end
    end
    f.context:SetText(#ctx > 0 and table.concat(ctx, "\n") or L["(nothing said before it)"])
    local shown = a.lines and a.lines[#a.lines] or a.line
    local head = a.count and string.format(L["%s (%d lines)"], a.who, a.count) or a.who
    f.line:SetText(head .. ": " .. plain(shown))
    local waiting = 0
    for _, other in ipairs(M:Feed()) do
        if other ~= a and other.state == "new" and other.sev ~= "low" and not other.by then waiting = waiting + 1 end
    end
    f.more:SetText(waiting > 0 and string.format(L["%d more on Leadership > Chat alerts."], waiting) or "")
    f.mute:SetShown(a.rule ~= nil)
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
    local header = UI:CreateSectionTitle(panel, L["CHAT ALERTS"], true)
    header:SetPoint("TOPLEFT", 0, 0)
    local hint = UI:CreateText(panel,
        L["Lines of guild chat that match the guild's rules, for the officers only. Kept in memory for two hours; a line is stored only when you warn."],
        11, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 0, -24)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -24)
    hint:SetJustifyH("LEFT")

    local paused = UI:CreateText(panel, L["Alerts paused: the game hides the chat in instances and combat."],
        11, C.red.r, C.red.g, C.red.b)
    paused:SetPoint("TOPLEFT", 0, -56)
    paused:Hide()

    -- This officer's own switches.
    local prefs = M and M:Prefs() or {}
    local boxes = {
        { "enabled", L["Alerts on"] }, { "officers", L["Also officers' lines"] },
        { "own", L["Also my own lines"] }, { "sound", L["Sound on high"] },
    }
    local x = 0
    for _, b in ipairs(boxes) do
        local cb = UI:CreateCheckbox(panel, b[2], 18)
        cb:SetPoint("TOPLEFT", x, -74)
        cb.checkbox:SetChecked(prefs[b[1]] and true or false)
        cb.checkbox.onChanged = function(_, checked) prefs[b[1]] = checked and true or false end
        x = x + 150
    end

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -102)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll = CreateFrame("ScrollFrame", "GuildOSModAlertsScroll", holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", GUTTER, 0)
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
        row:SetBackdrop({ bgFile = WHITE8 })
        local alt = (i % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        row.top = text(row, 11, C.label)
        row.top:SetPoint("TOPLEFT", 6, -4)
        row.top:SetPoint("RIGHT", row, "RIGHT", -230, 0)
        row.top:SetWordWrap(false)
        row.line = text(row, 11, C.text)
        row.line:SetPoint("TOPLEFT", 6, -22)
        row.line:SetPoint("RIGHT", row, "RIGHT", -230, 0)
        row.line:SetWordWrap(false)
        row.mute = UI:CreateButton(row, L["Mute 1h"], 70, 20)
        row.mute:SetPoint("RIGHT", -6, 0)
        row.ignore = UI:CreateButton(row, L["Ignore"], 70, 20)
        row.ignore:SetPoint("RIGHT", -82, 0)
        row.warn = UI:CreateButton(row, L["Warn"], 70, 20)
        row.warn:SetPoint("RIGHT", -158, 0)
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
        paused:SetShown(M:Paused())
        local feed = M:Feed()
        for i, a in ipairs(feed) do
            local row = rowAt(i)
            row.id = a.id
            local status = STATE_TEXT[a.state] or ""
            if a.by then status = string.format(L["alerted on %s's screen"], a.by) .. (status ~= "" and (", " .. status) or "") end
            if a.sev == "low" and status == "" then status = L["logged"] end
            -- Said while this officer was away (#411): when it was said, and so marked.
            if a.away then status = L["while you were away"] .. (status ~= "" and (", " .. status) or "") end
            local who = a.count and string.format(L["%s (%d lines)"], a.who, a.count) or a.who
            row.top:SetText(string.format("%s  %s  -  %s  %s", clock(a.said or a.at), who, aboutText(a),
                status ~= "" and ("(" .. status .. ")") or ""))
            local ink = a.state == "new" and C.text or C.textDim
            row.line:SetTextColor(ink.r, ink.g, ink.b)
            row.line:SetText(plain(a.lines and a.lines[#a.lines] or a.line))
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
    end

    -- The lockdown starts and ends without a line: while the tab shows, look every two seconds.
    local acc = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 2 then return end
        acc = 0
        if M then paused:SetShown(M:Paused()) end
    end)
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
    local header = UI:CreateSectionTitle(panel, L["ALERT RULES"], true)
    header:SetPoint("TOPLEFT", 0, 0)
    local hint = UI:CreateText(panel,
        L["The guild's words and patterns, shared by the officers. A word matches whole, without case or accents."],
        11, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 0, -24)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -24)
    hint:SetJustifyH("LEFT")

    local input = UI:CreateInput(panel, 170, 22, { max = M and M.PATTERN_MAX or 60, placeholder = L["word or phrase"] })
    input:SetPoint("TOPLEFT", 0, -50)
    local catDD = UI:CreateDropdown(panel, 150, 22)
    catDD:SetPoint("LEFT", input, "RIGHT", 8, 0)
    local cats = {}
    for _, c in ipairs(M and M.CATEGORIES or {}) do cats[#cats + 1] = { value = c, text = M.CategoryText(c) } end
    catDD:SetOptions(cats)
    catDD:SetValue("custom")
    local sevDD = UI:CreateDropdown(panel, 160, 22)
    sevDD:SetPoint("LEFT", catDD, "RIGHT", 8, 0)
    local sevs = {}
    for _, s in ipairs(M and M.SEVERITIES or {}) do sevs[#sevs + 1] = { value = s, text = M.SeverityText(s) } end
    sevDD:SetOptions(sevs)
    sevDD:SetValue("med")
    local luaChk = UI:CreateCheckbox(panel, L["Lua pattern"], 18)
    luaChk:SetPoint("TOPLEFT", 0, -80)
    local addBtn = UI:CreateButton(panel, L["Add"], 70, 22)
    addBtn:SetPoint("LEFT", sevDD, "RIGHT", 8, 0)
    local result = UI:CreateText(panel, "", 11, C.silver.r, C.silver.g, C.silver.b)
    result:SetPoint("TOPLEFT", 160, -82)
    local restore = UI:CreateButton(panel, L["Restore the default list"], 170, 22)
    restore:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -78)

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
    end
    addBtn:SetScript("OnClick", add)
    input:HookScript("OnEnterPressed", add)
    restore:SetScript("OnClick", function() if M then M:RestoreDefaults() end end)

    -- The anti-flood's limits (#405) sit under the rules when that module is there.
    local floodH = 0
    if GuildOS.BuildModFloodSection then floodH = GuildOS:BuildModFloodSection(panel, 110) or 0 end
    -- And the newcomer's quarantine (#406) under them.
    if GuildOS.BuildNewcomerSection then floodH = floodH + (GuildOS:BuildNewcomerSection(panel, 110 + floodH) or 0) end

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(110 + floodH))
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll = CreateFrame("ScrollFrame", "GuildOSModRulesScroll", holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", GUTTER, 0)
    UI:SkinScrollBar(scroll, "GuildOSModRulesScroll")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    UI:BindScrollChildWidth(scroll, content)

    local rows = {}
    local function rowAt(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * 24))
        row:SetPoint("TOPRIGHT", 0, -((i - 1) * 24))
        row.p = text(row, 11, C.text)
        row.p:SetPoint("LEFT", 0, 0)
        row.p:SetWidth(200)
        row.p:SetWordWrap(false)
        row.cat = text(row, 11, C.textDim)
        row.cat:SetPoint("LEFT", 210, 0)
        row.sev = text(row, 11, C.textDim)
        row.sev:SetPoint("LEFT", 380, 0)
        row.del = UI:CreateButton(row, "\195\151", 22, 18)  -- ×
        row.del:SetPoint("RIGHT", 0, 0)
        row.del:SetScript("OnClick", function() M:RemoveRule(row.index) end)
        rows[i] = row
        return row
    end
    local empty = UI:CreateText(content,
        L["The list is empty: nothing will alert. Add a word above, or restore the default list."],
        11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    local function refresh()
        if not M or not panel:IsVisible() then return end
        if panel.floodRefresh then GuildOS:SafeCall(panel.floodRefresh) end
        if panel.newcomerRefresh then GuildOS:SafeCall(panel.newcomerRefresh) end
        local rules = M:GetRules()
        for i, r in ipairs(rules) do
            local row = rowAt(i)
            row.index = i
            row.p:SetText(r.lua and (r.p .. "  |cff888888(" .. L["Lua pattern"] .. ")|r") or r.p)
            row.cat:SetText(M.CategoryText(r.cat))
            local ink = r.sev == "high" and C.red or C.textDim
            row.sev:SetTextColor(ink.r, ink.g, ink.b)
            row.sev:SetText(M.SeverityText(r.sev))
            row:Show()
        end
        for i = #rules + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#rules == 0)
        content:SetHeight(math.max(1, #rules * 24))
    end
    if M then M.rulesRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- The anti-flood's limits (#405), on the Alert rules tab under the rules' form
----------------------------------------------------------------------
-- Builds the section at `top` px down `panel`; returns the height it takes. panel.floodRefresh fills it.
function GuildOS:BuildModFloodSection(panel, top)
    local F = GuildOS.ModFlood
    if not F then return 0 end
    local title = UI:CreateSectionTitle(panel, L["ANTI-FLOOD"], false)
    title:SetPoint("TOPLEFT", 0, -(top + 20))
    local hint = UI:CreateText(panel, L["Each signal flags one alert per person while the surge lasts. The game's item and spell links never count."],
        11, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 0, -(top + 44))
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(top + 44))
    hint:SetJustifyH("LEFT")

    -- One row per signal: its switch, then its two limits with their words between.
    local ROWS = {
        { sig = "burst", label = L["Too many lines"], a = "n", mid = L["lines in"], b = "secs", tail = L["seconds"] },
        { sig = "repeat", label = L["The same line repeated"], a = "n", mid = L["times in"], b = "secs", tail = L["seconds"] },
        { sig = "caps", label = L["Capitals"], a = "pct", mid = L["percent of the letters, in lines of at least"], b = "min", tail = L["letters"] },
        { sig = "links", label = L["Links"], a = "n", mid = L["links in"], b = "secs", tail = L["seconds"] },
    }
    local fields = {}
    for i, row in ipairs(ROWS) do
        local y = -(top + 66 + (i - 1) * 26)
        local cb = UI:CreateCheckbox(panel, row.label, 18)
        cb:SetPoint("TOPLEFT", 0, y)
        local boxA = UI:CreateInput(panel, 40, 20, { numeric = true, max = 3 })
        boxA:SetPoint("TOPLEFT", 200, y + 1)
        local mid = UI:CreateText(panel, row.mid, 11, C.text.r, C.text.g, C.text.b)
        mid:SetPoint("LEFT", boxA, "RIGHT", 6, 0)
        local boxB = UI:CreateInput(panel, 40, 20, { numeric = true, max = 3 })
        boxB:SetPoint("LEFT", mid, "RIGHT", 6, 0)
        local tail = UI:CreateText(panel, row.tail, 11, C.text.r, C.text.g, C.text.b)
        tail:SetPoint("LEFT", boxB, "RIGHT", 6, 0)
        fields[row.sig] = { cb = cb, a = boxA, b = boxB, row = row }
    end
    local y = -(top + 66 + #ROWS * 26 + 4)
    local save = UI:CreateButton(panel, L["Save limits"], 110, 22)
    save:SetPoint("TOPLEFT", 0, y)
    local result = UI:CreateText(panel, "", 11, C.silver.r, C.silver.g, C.silver.b)
    result:SetPoint("LEFT", save, "RIGHT", 10, 0)

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
    return 66 + #ROWS * 26 + 32
end

----------------------------------------------------------------------
-- The newcomer's quarantine (#406), on the Alert rules tab under the anti-flood
----------------------------------------------------------------------
-- Builds the section at `top` px down `panel`; returns the height it takes. panel.newcomerRefresh fills it.
function GuildOS:BuildNewcomerSection(panel, top)
    local N = GuildOS.Newcomer
    if not N then return 0 end
    local title = UI:CreateSectionTitle(panel, L["NEWCOMERS"], false)
    title:SetPoint("TOPLEFT", 0, -(top + 8))
    local hint = UI:CreateText(panel,
        L["In a member's first days any link alerts and the anti-flood's limits are halved. The join comes from the roster log: a member who joined before the addon is not a newcomer. Only officers see it."],
        11, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 0, -(top + 32))
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(top + 32))
    hint:SetJustifyH("LEFT")
    local y = -(top + 62)
    local lead = UI:CreateText(panel, L["Newcomer for the first"], 11, C.text.r, C.text.g, C.text.b)
    lead:SetPoint("TOPLEFT", 0, y - 3)
    local box = UI:CreateInput(panel, 40, 20, { numeric = true, max = 2 })
    box:SetPoint("LEFT", lead, "RIGHT", 6, 0)
    local tail = UI:CreateText(panel, L["days (0 turns it off)"], 11, C.text.r, C.text.g, C.text.b)
    tail:SetPoint("LEFT", box, "RIGHT", 6, 0)
    local trial = UI:CreateCheckbox(panel, L["A trial counts as a newcomer"], 18)
    trial:SetPoint("LEFT", tail, "RIGHT", 16, 0)
    local save = UI:CreateButton(panel, L["Save for the guild"], 140, 22)
    save:SetPoint("TOPLEFT", 0, y - 28)
    local result = UI:CreateText(panel, "", 11, C.silver.r, C.silver.g, C.silver.b)
    result:SetPoint("LEFT", save, "RIGHT", 10, 0)
    save:SetScript("OnClick", function()
        local ok, why = N:SetConfig(box:GetText(), trial.checkbox:GetChecked() and true or false)
        if ok then
            result:SetText(L["Saved. The guild gets it now."])
        elseif why == "range" then
            result:SetText(L["From 0 to 30 days."])
        else
            result:SetText(L["|cffFF4444Officers only.|r"])
        end
    end)
    panel.newcomerRefresh = function()
        if not box:HasFocus() then box:SetText(tostring(N:GetDays())) end
        trial.checkbox:SetChecked(N:TrialCounts())
    end
    return 62 + 56
end
