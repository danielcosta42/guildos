----------------------------------------------------------------------
-- Guild OS - The questions about a removed or departed member's alts (issue #426)
--
-- GuildOS's own windows (never a StaticPopup, #315). The removal one: remove the alts too (a queue of
-- Bulk actions), ban the whole group (a term or permanent, a note for the officers) or nothing. The
-- departure one: set an alt as the new main, unlink the group or keep it. The logic is AltDeparture's;
-- this file only lays it out and never removes, bans or relinks by itself. Also the one question about the
-- player's own characters (#449, AltAutoDetect's), at the end.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"
local WIDTH = 460

local function text(parent, size, color)
    local fs = UI:CreateText(parent, "", size, color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    return fs
end

local function frame(name, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, height)
    f:SetPoint("CENTER", 0, 80)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.title = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.title, nil, "sectionTitle")
    f.title:SetPoint("TOP", 0, -10)
    f.title:SetTextColor(C.text.r, C.text.g, C.text.b)
    f.body = text(f, 11, C.text)
    f.body:SetPoint("TOPLEFT", 14, -34)
    f.body:SetWidth(WIDTH - 28)
    f.body:SetWordWrap(true)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)
    table.insert(UISpecialFrames, name)   -- ESC closes it
    f:Hide()
    return f
end

----------------------------------------------------------------------
-- Removed: remove the alts too, ban the group, or nothing
----------------------------------------------------------------------
local removedDialog
function GuildOS:ShowAltRemovedDialog(groups)
    local AD = GuildOS.AltDeparture
    if not AD or type(groups) ~= "table" or #groups == 0 then return end
    local f = removedDialog
    if not f then
        f = frame("GuildOSAltRemovedDialog", 300)
        f.removeBtn = UI:CreateButton(f, L["Remove them too"], 150, 22)
        f.banTitle = text(f, UI.SP.META, C.gold)
        f.banTitle:SetText(L["Or ban the whole group"])
        f.reasonLbl = text(f, 11, C.text)
        f.reasonLbl:SetText(L["Reason"])
        f.reason = UI:CreateInput(f, 200, 22, { max = 80 })
        f.daysLbl = text(f, 11, C.text)
        f.daysLbl:SetText(L["days"])
        f.days = UI:CreateInput(f, 46, 22, { numeric = true, max = 4 })
        f.daysHint = text(f, UI.SP.META, C.silver)
        f.daysHint:SetText(L["(empty: permanent)"])
        f.noteLbl = text(f, UI.SP.META, C.gold)
        f.noteLbl:SetText(L["Note (kept only on your client, never sent)"])
        f.note = UI:CreateInput(f, WIDTH - 28, 22, { max = GuildOS.BanList and GuildOS.BanList.SHARE_NOTE_MAX or 200 })
        f.banBtn = UI:CreateButton(f, L["Ban the group"], 150, 22)
        f.result = text(f, UI.SP.META, C.text)
        f.result:SetWidth(WIDTH - 28)
        f.result:SetWordWrap(true)
        f.nothing = UI:CreateButton(f, L["Do nothing"], 110, 24)
        f.nothing:SetPoint("BOTTOMRIGHT", -14, 12)
        f.nothing:SetScript("OnClick", function() f:Hide() end)
        removedDialog = f
    end

    local lines, total = {}, 0
    for _, g in ipairs(groups) do
        total = total + #g.others
        lines[#lines + 1] = string.format(L["%s was removed. Still in the guild from the same player: %s"],
            g.name, AD.ColoredNames(g.others))
    end
    f.title:SetText(L["Alts still in the guild"])
    f.body:SetText(table.concat(lines, "\n"))
    local bodyH = math.ceil(f.body:GetStringHeight() or 14)
    local y = -34 - bodyH - 12
    f.removeBtn:ClearAllPoints(); f.removeBtn:SetPoint("TOPLEFT", 14, y)
    y = y - 34
    f.banTitle:ClearAllPoints(); f.banTitle:SetPoint("TOPLEFT", 14, y)
    y = y - 18
    f.reasonLbl:ClearAllPoints(); f.reasonLbl:SetPoint("TOPLEFT", 14, y - 4)
    f.reason:ClearAllPoints(); f.reason:SetPoint("LEFT", f.reasonLbl, "RIGHT", 8, 0)
    f.days:ClearAllPoints(); f.days:SetPoint("LEFT", f.reason, "RIGHT", 12, 0)
    f.daysLbl:ClearAllPoints(); f.daysLbl:SetPoint("LEFT", f.days, "RIGHT", 6, 0)
    f.daysHint:ClearAllPoints(); f.daysHint:SetPoint("TOPLEFT", f.days, "BOTTOMLEFT", 0, -2)
    y = y - 40
    f.noteLbl:ClearAllPoints(); f.noteLbl:SetPoint("TOPLEFT", 14, y)
    f.note:ClearAllPoints(); f.note:SetPoint("TOPLEFT", 14, y - 14)
    y = y - 44
    f.banBtn:ClearAllPoints(); f.banBtn:SetPoint("TOPLEFT", 14, y)
    y = y - 30
    f.result:ClearAllPoints(); f.result:SetPoint("TOPLEFT", 14, y)
    f:SetHeight(-y + 60)

    local officer = GuildOS:IsOfficer()
    for _, w in ipairs({ f.banTitle, f.reasonLbl, f.reason, f.daysLbl, f.days, f.daysHint, f.noteLbl, f.note, f.banBtn }) do
        w:SetShown(officer)
    end
    f.removeBtn.label:SetText(string.format(L["Remove them too (%d)"], total))
    f.removeBtn:Enable(); f.banBtn:Enable()
    f.reason:SetText(""); f.days:SetText(""); f.note:SetText(""); f.result:SetText("")
    f.nothing.label:SetText(L["Do nothing"])

    f.removeBtn:SetScript("OnClick", function()
        -- Only a queue: each of them is removed by a click of Next in Leadership > Bulk actions (ADR-0038).
        if AD:RemoveOthers(groups) then
            f.removeBtn:Disable()
            f.result:SetText(L["Queued in Leadership > Bulk actions: one per click of Next."])
            f.nothing.label:SetText(L["Close"])
        end
    end)
    f.banBtn:SetScript("OnClick", function()
        local days = tonumber(strtrim(f.days:GetText() or ""))
        if days and days <= 0 then days = nil end
        local n = AD:BanGroups(groups, f.reason:GetText(), days, f.note:GetText())
        if n > 0 then
            f.banBtn:Disable()
            f.result:SetText(days and string.format(L["%d banned for %d days."], n, days)
                or string.format(L["%d banned for good."], n))
            f.nothing.label:SetText(L["Close"])
        else
            f.result:SetText(L["Nobody was banned."])
        end
    end)
    f:Show()
    return f
end

----------------------------------------------------------------------
-- A main who left: set another main, unlink, or keep
----------------------------------------------------------------------
local leftDialog
function GuildOS:ShowMainLeftDialog(info)
    local AD = GuildOS.AltDeparture
    if not AD or type(info) ~= "table" or type(info.others) ~= "table" or #info.others == 0 then return end
    local f = leftDialog
    if not f then
        f = frame("GuildOSMainLeftDialog", 190)
        f.pick = UI:CreateDropdown(f, 200, 22)
        f.setBtn = UI:CreateButton(f, "", 200, 22)
        f.unlinkBtn = UI:CreateButton(f, L["Unlink"], 100, 24)
        f.keepBtn = UI:CreateButton(f, L["Keep"], 100, 24)
        f.keepBtn:SetPoint("BOTTOMRIGHT", -14, 12)
        f.keepBtn:SetScript("OnClick", function() f:Hide() end)
        f.unlinkBtn:SetPoint("RIGHT", f.keepBtn, "LEFT", -8, 0)
        f.result = text(f, UI.SP.META, C.text)
        f.result:SetWidth(WIDTH - 28)
        leftDialog = f
    end
    local others = info.others
    f.title:SetText(L["A main left the guild"])
    -- A main found gone at login (#449), not seen leaving: Keep is for good on this client.
    f.body:SetText(string.format(info.orphan
        and L["%s is not in the guild any more and still has %d alt(s) in it: %s. Did the main change?"]
        or L["%s left and still has %d alt(s) in the guild: %s. Did the main change?"],
        info.name, #others, AD.ColoredNames(others)))
    f.keepBtn:SetScript("OnClick", function()
        if info.orphan and AD.KeepOrphan then AD:KeepOrphan(info.key) end
        f:Hide()
    end)
    local bodyH = math.ceil(f.body:GetStringHeight() or 14)
    f.pick:ClearAllPoints(); f.pick:SetPoint("TOPLEFT", 14, -34 - bodyH - 12)
    f.setBtn:ClearAllPoints(); f.setBtn:SetPoint("LEFT", f.pick, "RIGHT", 10, 0)
    f.result:ClearAllPoints(); f.result:SetPoint("TOPLEFT", f.pick, "BOTTOMLEFT", 0, -10)
    f:SetHeight(34 + bodyH + 12 + 22 + 10 + 16 + 48)

    local opts = {}
    for i, m in ipairs(others) do opts[i] = { value = m.key, text = m.name } end
    f.pick:SetOptions(opts)
    local function label()
        local key = f.pick:GetValue()
        local name = key and (key:match("^([^-]+)") or key) or "?"
        f.setBtn.label:SetText(string.format(L["Set %s as main"], name))
    end
    f.pick.onSelect = function() label() end
    f.pick:SetValue(others[1].key)
    label()
    f.result:SetText("")
    f.keepBtn.label:SetText(L["Keep"])
    for _, b in ipairs({ f.setBtn, f.unlinkBtn }) do b:Enable() end

    local function done(ok, why, line)
        if ok then
            f.result:SetText(line)
            f.setBtn:Disable(); f.unlinkBtn:Disable()
            f.keepBtn.label:SetText(L["Close"])
        else
            f.result:SetText(AD.WhyText(why))
        end
    end
    f.setBtn:SetScript("OnClick", function()
        local key = f.pick:GetValue()
        local ok, why = AD:SetNewMain(info.key, key)
        done(ok, why, string.format(L["%s is the main now, for every officer."], key and (key:match("^([^-]+)") or key) or "?"))
    end)
    f.unlinkBtn:SetScript("OnClick", function()
        local ok, why = AD:Unlink(info.key)
        done(ok, why, L["The alts are unlinked."])
    end)
    f:Show()
    return f
end

----------------------------------------------------------------------
-- Your own characters (#449): the one question AltAutoDetect asks for every undecided character of the account,
--   "These characters are on your account: A, B, C." / "Link them as alts of [main]"
--   Link all · Choose... (a tick per character, then Link selected) · Not now · Don't ask again
-- The close and Escape are a Not now. The logic (what to ask, what an answer keeps) is AltAutoDetect's.
----------------------------------------------------------------------
local promptDialog
local PROMPT_W = 540
local CHECK_H = 22

-- The account's record of a key (class, name), read the way the plan keys it (WoW: Forever, #97).
local function accountInfo(key)
    for k, info in pairs(type(GuildOSDB) == "table" and GuildOSDB.accountChars or {}) do
        if type(info) == "table" and GuildOS:LocalMemberKey(k) == key then return info end
    end
    return nil
end

local function charLine(key)
    local info = accountInfo(key)
    local name = (info and info.name) or (key:match("^([^-]+)") or key)
    return { key = key, name = name, class = info and info.class }
end

function GuildOS:ShowAltPrompt(plan, manual)
    local AAD = GuildOS.AltAutoDetect
    if not AAD or type(plan) ~= "table" or type(plan.list) ~= "table" or #plan.list == 0 then return nil end
    local Kit = GuildOS.Kit
    local f = promptDialog
    if not f then
        f = Kit:Float(L["Your characters"], {
            name = "GuildOSAltPrompt", width = PROMPT_W, height = 200, foot = true,
            onClose = function(fr) fr:Hide() end,
        })
        f.text = text(f.body, UI.SP.BODY, C.text)
        f.text:SetPoint("TOPLEFT", 0, -2)
        f.text:SetWidth(PROMPT_W - 2 * Kit.PAD)
        f.text:SetWordWrap(true)
        f.checks = {}
        f.asLbl = text(f.body, UI.SP.BODY, C.text)
        f.asLbl:SetText(L["Link them as alts of"])
        f.pick = UI:CreateDropdown(f.body, 180, 22)
        f.linkBtn = UI:SetButtonVariant(UI:CreateButton(f.foot, L["Link all"], 110, UI.SP.FIELD), "primary")
        f.chooseBtn = UI:CreateButton(f.foot, L["Choose..."], 90, UI.SP.FIELD)
        f.laterBtn = UI:CreateButton(f.foot, L["Not now"], 80, UI.SP.FIELD)
        f.neverBtn = UI:CreateButton(f.foot, L["Don't ask again"], 120, UI.SP.FIELD)
        f.laterBtn:SetScript("OnClick", function() f:Hide() end)
        promptDialog = f
    end
    f.plan, f.choosing = plan, false

    -- The characters linked under the main picked (AltAutoDetect.Candidates): picking another main lists the one
    -- suggested instead. One tick each, shown under Choose...; a tick taken off stays off while the window is up.
    local lines = {}
    f.unticked = {}
    local function fill()
        lines = {}
        for i, k in ipairs(AAD.Candidates(plan, f.pick:GetValue() or plan.main)) do lines[i] = charLine(k) end
        f.text:SetText(string.format(L["These characters are on your account: %s."], GuildOS.AltDeparture
            and GuildOS.AltDeparture.ColoredNames(lines) or ""))
        for _, cb in ipairs(f.checks) do cb:Hide() end
        for i, m in ipairs(lines) do
            local cb = f.checks[i]
            if not cb then
                cb = UI:CreateCheckbox(f.body, "", CHECK_H)
                f.checks[i] = cb
                cb.checkbox.onChanged = function(box, on) if box.key then f.unticked[box.key] = not on or nil end end
            end
            cb.checkbox.key = m.key
            cb.label:SetText(m.name)
            cb.checkbox:SetChecked(not f.unticked[m.key])
        end
    end

    local opts = {}
    for i, k in ipairs(plan.choices) do opts[i] = { value = k, text = charLine(k).name } end
    f.pick:SetOptions(opts)
    f.pick:SetValue(plan.main)
    fill()

    local function layout()
        local y = -2 - math.ceil(f.text:GetStringHeight() or 14) - 10
        for i, cb in ipairs(f.checks) do
            cb:ClearAllPoints()
            if f.choosing and lines[i] then
                cb:SetPoint("TOPLEFT", 0, y)
                cb:Show()
                y = y - CHECK_H
            else
                cb:Hide()
            end
        end
        if f.choosing then y = y - 6 end
        f.asLbl:ClearAllPoints(); f.asLbl:SetPoint("TOPLEFT", 0, y - 4)
        f.pick:ClearAllPoints(); f.pick:SetPoint("LEFT", f.asLbl, "RIGHT", 8, 0)
        y = y - 22 - 10
        f:SetHeight(Kit.HEADER_H + 8 - y + Kit.FOOT_H + 4)
        f.linkBtn.label:SetText(f.choosing and L["Link selected"] or L["Link all"])
        f.chooseBtn:SetShown(not f.choosing and #lines > 1)
        for _, b in ipairs({ f.linkBtn, f.chooseBtn, f.laterBtn, f.neverBtn }) do
            b:SetWidth(math.ceil(b.label:GetStringWidth() or 60) + 24)   -- to its label, in every language
        end
        f.foot:Lay(f.linkBtn, f.chooseBtn, f.laterBtn, f.neverBtn)
    end

    f.chooseBtn:SetScript("OnClick", function() f.choosing = true; layout() end)
    f.pick.onSelect = function() fill(); layout() end
    f.linkBtn:SetScript("OnClick", function()
        local picked
        if f.choosing then
            picked = {}
            for i, cb in ipairs(f.checks) do
                if lines[i] and cb.checkbox:GetChecked() then picked[cb.checkbox.key] = true end
            end
        end
        f:Hide()
        AAD:Accept(plan, f.pick:GetValue() or plan.main, picked)
    end)
    f.neverBtn:SetScript("OnClick", function()
        f:Hide()
        AAD:Decline(plan)
    end)
    -- Asked for (Detect my alts, /gos myalts): nothing counts as asked, so it closes rather than waits.
    f.laterBtn.label:SetText(manual and L["Close"] or L["Not now"])
    layout()
    f:Show()
    return f
end
