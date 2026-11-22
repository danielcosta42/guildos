----------------------------------------------------------------------
-- Guild OS - The Warn window (issue #403)
--
-- One click to warn somebody: a reason, one of the guild's templates already filled in, an optional
-- officer note, and "only record it". Warn files the warning and the whisper leaves on that click (a
-- hardware event). When the new step's rung asks for something, a second step SUGGESTS it and does it only
-- on Confirm. The logic is Discipline's; this file only lays it out.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE8 = "Interface\\Buttons\\WHITE8x8"

local OUTCOME = {
    sent = L["Warning filed and whispered."],
    silent = L["Warning filed, without a whisper."],
    offline = L["Warning filed. %s is offline: no whisper went."],
    locked = L["Warning filed. The game is holding the chat: no whisper went."],
    failed = L["Warning filed, but the whisper did not go."],
}

local function text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    return fs
end

-- `opts.excerpt`: the chat line the warning is about (the alerts, issue #404), kept on the record.
function GuildOS:ShowWarnDialog(playerKey, name, opts)
    local D = GuildOS.Discipline
    if not D then return end
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    opts = opts or {}
    if self.warnDialog then self.warnDialog:Hide() end

    local f = CreateFrame("Frame", "GuildOSWarnDialog", UIParent, "BackdropTemplate")
    f:SetSize(440, 360)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    self.warnDialog = f

    local step = D:StepOf(playerKey)
    local title = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(title, nil, "sectionTitle")
    title:SetPoint("TOP", 0, -10)
    title:SetTextColor(C.text.r, C.text.g, C.text.b)
    title:SetText(string.format(L["Warn %s"], name))

    local sub = text(f, 10, C.silver)
    sub:SetPoint("TOPLEFT", 14, -32)
    sub:SetText(string.format(L["Now on step %d; this warning makes it %d."], step, math.min(10, step + 1)))

    local reasonDD = UI:CreateDropdown(f, 200, 22)
    reasonDD:SetPoint("TOPLEFT", 14, -54)
    local reasons = {}
    for _, r in ipairs(D.REASONS) do reasons[#reasons + 1] = { value = r, text = D.ReasonText(r) } end
    reasonDD:SetOptions(reasons)
    local start = "conduct"
    for _, r in ipairs(D.REASONS) do if r == opts.reason then start = r end end
    reasonDD:SetValue(start)

    local tplDD = UI:CreateDropdown(f, 196, 22)
    tplDD:SetPoint("LEFT", reasonDD, "RIGHT", 16, 0)
    tplDD:SetOptions({
        { value = "warning", text = L["Template: warning"] },
        { value = "final", text = L["Template: final warning"] },
        { value = "punish", text = L["Template: punishment"] },
    })
    tplDD:SetValue(D.TemplateFor(step + 1))

    -- The guild rule this warning is about (#407): {rule} in the template names it.
    local GR = GuildOS.GuildRules
    local ruleDD = UI:CreateDropdown(f, 412, 22)
    ruleDD:SetPoint("TOPLEFT", 14, -84)
    local ruleOpts = { { value = 0, text = L["Rule: none named"] } }
    for i, r in ipairs(GR and GR:Get() or {}) do ruleOpts[#ruleOpts + 1] = { value = i, text = GR.RefText(i, r) } end
    ruleDD:SetOptions(ruleOpts)
    ruleDD:SetValue(0)
    local function ruleText()
        local n = ruleDD:GetValue()
        local r = GR and n and n > 0 and GR:Rule(n)
        return r and GR.RefText(n, r) or nil
    end

    local msgLabel = text(f, 9, C.gold)
    msgLabel:SetPoint("TOPLEFT", 14, -116)
    msgLabel:SetText(L["The whisper (you can edit it before sending)"])
    local msg = UI:CreateInput(f, 412, 22, { max = D.WHISPER_MAX })
    msg:SetPoint("TOPLEFT", 14, -130)

    local edited = false
    local function refill()
        if edited then return end
        msg:SetText(D.Fill(D:GetTemplates()[tplDD:GetValue()], { name = name, reason = D.ReasonText(reasonDD:GetValue()), step = math.min(10, step + 1), rule = ruleText() }))
    end
    msg:HookScript("OnTextChanged", function(_, user) if user then edited = true end end)
    reasonDD.onSelect = function() refill() end
    ruleDD.onSelect = function() refill() end
    tplDD.onSelect = function() edited = false; refill() end
    refill()

    local saveTpl = UI:CreateButton(f, L["Save as the guild's template"], 200, 20)
    saveTpl:SetPoint("TOPLEFT", 14, -156)
    saveTpl:SetScript("OnClick", function()
        -- What was typed, with the name, the reason and the rule named put back as their placeholders.
        local typed = msg:GetText() or ""
        local reasonText = D.ReasonText(reasonDD:GetValue())
        typed = typed:gsub(name:gsub("%p", "%%%0"), "{name}"):gsub(reasonText:gsub("%p", "%%%0"), "{reason}")
        local named = ruleText()
        if named then typed = typed:gsub((named:gsub("%p", "%%%0")), "{rule}") end
        if D:SetTemplate(tplDD:GetValue(), typed) then GuildOS:Print(L["Template saved for the guild."]) end
    end)

    local noteLabel = text(f, 9, C.gold)
    noteLabel:SetPoint("TOPLEFT", 14, -184)
    noteLabel:SetText(L["Officer note (only officers see it)"])
    local note = UI:CreateInput(f, 412, 22, { max = D.NOTE_MAX })
    note:SetPoint("TOPLEFT", 14, -198)

    local silent = UI:CreateCheckbox(f, L["Only record it, without a whisper"])
    silent:SetPoint("TOPLEFT", 14, -228)

    local result = text(f, 10, C.text)
    result:SetPoint("TOPLEFT", 14, -256)
    result:SetWidth(412)
    result:SetWordWrap(true)

    local warnBtn = UI:CreateButton(f, L["Warn"], 100, 24)
    warnBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    local cancel = UI:CreateButton(f, L["Cancel"], 90, 24)
    cancel:SetPoint("RIGHT", warnBtn, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() f:Hide() end)
    local confirm = UI:CreateButton(f, L["Confirm"], 100, 24)
    confirm:SetPoint("BOTTOMRIGHT", -14, 12)
    confirm:Hide()

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    warnBtn:SetScript("OnClick", function()
        local reason = reasonDD:GetValue()
        local w, how = D:Warn(playerKey, name, reason, {
            text = msg:GetText(), note = note:GetText(), excerpt = opts.excerpt, rule = ruleText(),
            silent = silent.checkbox:GetChecked() and true or false,
        })
        if not w then
            result:SetText(L["Nothing was filed."])
            return
        end
        result:SetText(string.format(OUTCOME[how] or OUTCOME.failed, name))
        warnBtn:Hide()
        cancel.label:SetText(L["Close"])
        -- The step's rung, suggested: nothing happens without Confirm.
        local s = D.Suggestion(D:GetLadder(), w.level, D:GetPunishRank())
        if not s then return end
        local line
        if s.action == "rank" and not s.rank then
            line = L["The guild's ladder suggests the punishment rank, but none is set: set it on the member's record."]
        elseif s.action == "rank" then
            line = string.format(L["Suggested: move %s to the rank %s."], name, s.rank)
            confirm:Show()
        else
            line = string.format(L["Suggested: ban %s for %d days."], name, s.days)
            confirm:Show()
        end
        result:SetText(result:GetText() .. "\n" .. line)
        cancel.label:SetText(L["Not now"])
        cancel:ClearAllPoints()
        cancel:SetPoint("RIGHT", confirm, "LEFT", -8, 0)
        confirm:SetScript("OnClick", function()
            D:ApplySuggestion(name, s, reason)
            f:Hide()
        end)
    end)

    f:Show()
end
