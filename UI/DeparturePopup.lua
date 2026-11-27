----------------------------------------------------------------------
-- Guild OS - The departure popup and the welcome-back notice (#449, specs/salao/saidas.md)
--
-- Floating windows of the kit (Kit:Float: the metal frame, the header, a footer of buttons), opened only through
-- GuildOS:ShowWhenClear (never in combat, one popup at a time). The departure one sits at the top centre, moves by
-- its header and keeps its place. The logic is Modules/Departure.lua's; this file only lays it out, and never
-- removes, bans or writes anything by itself.
-- Also the Recruiting › Welcome card's second list ("For members who return"), built here for UI/RosterFrame.lua.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local WIDTH = 420
local NOTICE_W = 380
local ROWS = 10
local ROW_H = 22

local function setting(name, default)
    local s = GuildOS:GetSetting(name)
    if type(s) ~= "table" then
        s = default or {}
        GuildOS:SetSetting(name, s)
    end
    return s
end

local function keepPlace(f, name)
    f.header:HookScript("OnDragStop", function()
        local point, _, _, x, y = f:GetPoint()
        local s = setting(name)
        s.point, s.x, s.y = point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
    end)
end

local function text(parent, size, color)
    local fs = UI:CreateText(parent, "", size or UI.SP.BODY, color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function height(fs)
    local h = fs:IsShown() and fs:GetText() ~= "" and fs:GetStringHeight() or 0
    return math.ceil(h or 0)
end

----------------------------------------------------------------------
-- The departure popup
----------------------------------------------------------------------
local popup

local function build()
    if popup then return popup end
    local Kit = GuildOS.Kit
    local saved = setting("departurePopupPos")
    local f = Kit:Float(L["Left the guild"], {
        name = "GuildOSDeparturePopup", width = WIDTH, height = 420, strata = "DIALOG", foot = true,
        point = { saved.point or "TOP", saved.x or 0, saved.y or -120 },
        onClose = function(fr) fr:Hide() end,
    })
    f:ClearAllPoints()
    f:SetPoint(saved.point or "TOP", UIParent, saved.point or "TOP", saved.x or 0, saved.y or -120)
    keepPlace(f, "departurePopupPos")
    local inner = WIDTH - 2 * Kit.PAD
    local b = f.body

    f.headline = text(b, 14, C.text)
    f.headline:SetWidth(inner - 60)
    f.count = text(b, UI.SP.META, C.textSoft)
    f.count:SetJustifyH("RIGHT")
    f.count:SetWidth(58)
    f.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -2)
    f.handled = text(b, UI.SP.BODY, C.ok or C.gold)
    f.handled:SetWidth(inner)
    f.charsLbl = text(b, UI.SP.META, C.textSoft)
    f.charsLbl:SetText(L["Their characters"])
    f.rows = {}
    for i = 1, ROWS do
        local cb = UI:CreateCheckbox(b, "", ROW_H)
        cb:SetWidth(inner - 110)
        local st = text(b, UI.SP.META, C.textSoft)
        st:SetJustifyH("RIGHT")
        st:SetWidth(108)
        f.rows[i] = { cb = cb, status = st }
    end
    f.removeBtn = UI:CreateButton(b, L["Remove selected"], 150, UI.SP.FIELD)
    f.removeNote = text(b, UI.SP.META, C.textSoft)
    f.removeNote:SetWidth(inner)
    f.lineBox = UI:CreateInput(b, inner - 96, UI.SP.FIELD)
    f.lineBox:HookScript("OnTextChanged", function(self, userInput)
        if userInput and f.lineText and self:GetText() ~= f.lineText then self:SetText(f.lineText); self:HighlightText() end
    end)
    f.lineBox:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.lineNext = UI:CreateButton(b, L["Next line"], 90, UI.SP.FIELD)
    f.noteLbl = text(b, UI.SP.META, C.textSoft)
    f.noteLbl:SetText(L["Permanent officer note (officers only)"])
    f.noteBox = UI:CreateInput(b, inner, UI.SP.FIELD, { max = (GuildOS.MemberHistory and GuildOS.MemberHistory.NOTE_MAX) or 300 })
    f.flagLbl = text(b, UI.SP.META, C.textSoft)
    f.flagLbl:SetText(L["Flag"])
    local Forms = GuildOS.Forms
    f.pills = {
        none = Forms:Pill(b, L["No flag"]),
        ban = Forms:Pill(b, L["Ban permanently"]),
        suspend = Forms:Pill(b, L["Suspend for"]),
    }
    f.daysBox = UI:CreateInput(b, 46, UI.SP.FIELD, { numeric = true, max = 3, justify = "CENTER" })
    f.daysLbl = text(b, UI.SP.BODY, C.text)
    f.daysLbl:SetText(L["days"])
    f.result = text(b, UI.SP.META, C.text)
    f.result:SetWidth(inner)

    f.saveBtn = UI:CreateButton(f.foot, L["Save"], 110, UI.SP.FIELD)
    UI:SetButtonVariant(f.saveBtn, "primary")
    f.dismissBtn = UI:CreateButton(f.foot, L["Dismiss"], 100, UI.SP.FIELD)
    f.nextBtn = UI:CreateButton(f.foot, L["Next"], 80, UI.SP.FIELD)
    f.nextBtn:SetPoint("LEFT", f.foot, "LEFT", Kit.PAD - 3, -1)
    f.foot:Lay(f.saveBtn, f.dismissBtn)

    for flag, pill in pairs(f.pills) do
        pill:SetScript("OnClick", function()
            f.flag = flag ~= "none" and flag or nil
            for k, p in pairs(f.pills) do Forms:SetOn(p, k == flag) end
            if flag == "suspend" and (f.daysBox:GetText() or "") == "" then f.daysBox:SetText("7") end
        end)
    end
    popup = f
    return f
end

-- Lays the parts out under one another; returns the body's height.
local function layout(f)
    local Kit = GuildOS.Kit
    local y = 0
    local function at(w, x, h, gap)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", f.body, "TOPLEFT", x or 0, -y)
        y = y + (h or w:GetHeight()) + (gap or UI.SP.FIELD_GAP)
    end
    at(f.headline, 0, height(f.headline), 6)
    if f.handled:IsShown() then at(f.handled, 0, height(f.handled), 6) end
    at(f.charsLbl, 0, 14, 2)
    for _, r in ipairs(f.rows) do
        if r.cb:IsShown() then
            r.cb:ClearAllPoints(); r.cb:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y)
            r.status:ClearAllPoints(); r.status:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -(y + 5))
            y = y + ROW_H
        end
    end
    y = y + 4
    at(f.removeBtn, 0, UI.SP.FIELD, 4)
    if f.removeNote:GetText() ~= "" then at(f.removeNote, 0, height(f.removeNote), 4) end
    if f.lineBox:IsShown() then
        f.lineBox:ClearAllPoints(); f.lineBox:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y)
        f.lineNext:ClearAllPoints(); f.lineNext:SetPoint("LEFT", f.lineBox, "RIGHT", 6, 0)
        y = y + UI.SP.FIELD + 6
    end
    y = y + 6
    at(f.noteLbl, 0, 14, 2)
    at(f.noteBox, 0, UI.SP.FIELD, 10)
    at(f.flagLbl, 0, 14, 2)
    local x = 0
    for _, k in ipairs({ "none", "ban", "suspend" }) do
        local p = f.pills[k]
        p:ClearAllPoints(); p:SetPoint("TOPLEFT", f.body, "TOPLEFT", x, -y)
        x = x + p:GetWidth() + 6
    end
    f.daysBox:ClearAllPoints(); f.daysBox:SetPoint("LEFT", f.pills.suspend, "RIGHT", 6, 0)
    f.daysLbl:ClearAllPoints(); f.daysLbl:SetPoint("LEFT", f.daysBox, "RIGHT", 6, 0)
    y = y + UI.SP.FIELD + 6
    if f.result:GetText() ~= "" then at(f.result, 0, height(f.result), 0) end
    f:SetHeight(Kit.HEADER_H + 8 + y + 10 + Kit.FOOT_H + 4)
    return y
end

local function showLine(f)
    local line = f.typedLines and f.typedLines[f.typedPos or 1]
    f.lineBox:SetShown(line ~= nil)
    f.lineNext:SetShown(line ~= nil and #f.typedLines > (f.typedPos or 1))
    if line then
        f.lineText = line
        f.lineBox:SetText(line)
    end
end

-- Fills the window with happening `h` (index `i` of `n`).
local function fill(f, h, i, n)
    local DP = GuildOS.Departure
    local fresh = f.h ~= h
    f.h = h
    f:SetTitle(h.how == "kick" and L["Removed from the guild"] or L["Left the guild"])
    f.count:SetText(n > 1 and string.format(L["%d of %d"], i, n) or "")
    f.headline:SetText(DP.Header(h))
    f.handled:SetShown(h.handledBy ~= nil)
    f.handled:SetText(h.handledBy and string.format(L["Handled by %s"], h.handledBy) or "")
    local linked = DP:Linked(h)
    for j, r in ipairs(f.rows) do
        local c = linked[j]
        r.cb:SetShown(c ~= nil)
        r.status:SetShown(c ~= nil)
        if c then
            r.key = c.key
            local name = DP.Colored(c) .. (c.main and (" |cff888888(" .. L["main"] .. ")|r") or "")
            r.cb.label:SetText(name)
            r.status:SetText(c.me and L["you"] or (c.inGuild and L["in the guild"] or L["already gone"]))
            local ink = c.inGuild and (C.ok or C.text) or C.textSoft
            r.status:SetTextColor(ink.r, ink.g, ink.b)
            if fresh then r.cb.checkbox:SetChecked(c.checked) end
            local can = c.inGuild and not c.me and not h.handledBy
            if can then r.cb.checkbox:Enable() else r.cb.checkbox:Disable(); r.cb.checkbox:SetChecked(false) end
        end
    end
    local anyIn = false
    for _, c in ipairs(linked) do if c.inGuild and not c.me then anyIn = true end end
    if fresh then
        f.removeNote:SetText(anyIn and "" or L["Nobody else of theirs is in the guild."])
        f.typedLines, f.typedPos = nil, nil
        local MH = GuildOS.MemberHistory
        local note = MH and MH.NoteFor and MH:NoteFor(h.key)
        f.noteBox:SetText(note and note.text or "")
        f.flag = nil
        for k, p in pairs(f.pills) do GuildOS.Forms:SetOn(p, k == "none") end
        f.daysBox:SetText("")
        f.result:SetText("")
    end
    if anyIn and not h.handledBy then f.removeBtn:Enable() else f.removeBtn:Disable() end
    if h.handledBy then f.saveBtn:Disable() else f.saveBtn:Enable() end
    f.dismissBtn.label:SetText(h.handledBy and L["Close"] or L["Dismiss"])
    f.nextBtn:SetShown(n > 1)
    showLine(f)
    layout(f)
end

local function current(f, list)
    for i, h in ipairs(list) do
        if h == f.h then return h, i end
    end
    return list[1], 1
end

--- Shows the departure popup on the happening it shows, or the first one waiting; hidden with none. Returns the
--- window, or nil.
function GuildOS:ShowDeparturePopup()
    local DP = GuildOS.Departure
    if not DP then return nil end
    local list = DP:Shown()
    if #list == 0 then
        if popup then popup:Hide() end
        return nil
    end
    local f = build()
    local h, i = current(f, list)
    fill(f, h, i, #list)

    f.nextBtn:SetScript("OnClick", function()
        local l = DP:Shown()
        local _, at = current(f, l)
        local nh = l[at % #l + 1]
        if nh then fill(f, nh, at % #l + 1, #l) end
    end)
    f.dismissBtn:SetScript("OnClick", function()
        DP:Dismiss(f.h)
    end)
    f.removeBtn:SetScript("OnClick", function()
        local keys = {}
        for _, r in ipairs(f.rows) do
            if r.cb:IsShown() and r.cb.checkbox:GetChecked() then keys[#keys + 1] = r.key end
        end
        local res, extra = DP:Remove(f.h, keys)
        if res == "queued" then
            f.removeNote:SetText(L["Queued in Leadership > Bulk actions: one per click of Next."])
            f.removeBtn:Disable()
        elseif res == "typed" then
            f.typedLines, f.typedPos = extra, 1
            f.removeNote:SetText(L["This game lets no addon remove a member: copy each line and send it (Ctrl+C, Enter, Ctrl+V, Enter)."])
            showLine(f)
            f.lineBox:SetFocus()
        else
            f.removeNote:SetText(GuildOS.BulkActions and GuildOS.BulkActions:WhyText(extra) or "")
        end
        layout(f)
    end)
    f.lineNext:SetScript("OnClick", function()
        f.typedPos = math.min(#(f.typedLines or {}), (f.typedPos or 1) + 1)
        showLine(f)
        f.lineBox:SetFocus()
    end)
    f.saveBtn:SetScript("OnClick", function()
        local h0 = f.h
        local ok, did = DP:Save(h0, { note = f.noteBox:GetText(), flag = f.flag, days = tonumber(f.daysBox:GetText() or "") })
        if not ok then
            f.result:SetText(did == "days" and string.format(L["Write the days of the suspension (1-%d)."], DP.SUSPEND_MAX)
                or L["|cffFF4444Officers only.|r"])
            layout(f)
            return
        end
        local parts = {}
        if did.note then parts[#parts + 1] = L["note saved"] end
        if did.banned and did.banned > 0 then parts[#parts + 1] = string.format(L["%d banned"], did.banned) end
        GuildOS:Print(string.format(L["%s: handled (%s)."], h0.name, #parts > 0 and table.concat(parts, ", ") or L["nothing to write"]))
    end)
    f:Show()
    return f
end

if GuildOS.Departure then
    GuildOS.Departure.uiRefresh = function()
        if popup and popup:IsShown() then GuildOS:ShowDeparturePopup() end
    end
end

----------------------------------------------------------------------
-- The welcome-back notice
----------------------------------------------------------------------
local notice
local NOTICE_LINES = 6
function GuildOS:ShowWelcomeBackNotice(r)
    if type(r) ~= "table" then return nil end
    local Kit = GuildOS.Kit
    if not notice then
        local saved = setting("welcomeBackPos")
        local f = Kit:Float(L["Welcome back"], {
            name = "GuildOSWelcomeBack", width = NOTICE_W, height = 160, foot = true,
            point = { saved.point or "TOP", saved.x or 0, saved.y or -160 },
            onClose = function(fr) fr:Hide() end,
        })
        f:ClearAllPoints()
        f:SetPoint(saved.point or "TOP", UIParent, saved.point or "TOP", saved.x or 0, saved.y or -160)
        keepPlace(f, "welcomeBackPos")
        f.warnLine = text(f.body, 14, C.danger or C.red)
        f.warnLine:SetWidth(NOTICE_W - 2 * Kit.PAD)
        f.lines = {}
        for i = 1, NOTICE_LINES do
            f.lines[i] = text(f.body, UI.SP.BODY, C.text)
            f.lines[i]:SetWidth(NOTICE_W - 2 * Kit.PAD)
        end
        f.okBtn = UI:CreateButton(f.foot, L["Close"], 100, UI.SP.FIELD)
        UI:SetButtonVariant(f.okBtn, "primary")
        f.okBtn:SetScript("OnClick", function() f:Hide() end)
        f.foot:Lay(f.okBtn)
        notice = f
    end
    local f = notice
    local danger = C.danger or C.red
    local ink = r.warn and danger or C.gold
    f:SetTitle(r.warn and L["A banned player is back"] or r.title or L["Welcome back"])
    f.titleText:SetTextColor(ink.r, ink.g, ink.b)
    -- A ban or a suspension first, in red; then the welcome back, the last removal and the note, one line each.
    local y = 0
    f.warnLine:SetShown(r.warn == true)
    f.warnLine:SetText(r.warn and r.title or "")
    if r.warn then
        f.warnLine:ClearAllPoints(); f.warnLine:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
        y = height(f.warnLine) + 8
    end
    for i, fs in ipairs(f.lines) do
        local line = r.lines and r.lines[i]
        fs:SetShown(line ~= nil)
        fs:SetText(line or "")
        if line then
            local c = (r.warn and i == 1) and C.textSoft or C.text   -- the ban's reason, under its title
            fs:SetTextColor(c.r, c.g, c.b)
            fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y)
            y = y + height(fs) + 6
        end
    end
    f:SetHeight(Kit.HEADER_H + 8 + y + 8 + Kit.FOOT_H + 4)
    f:Show()
    return f
end

----------------------------------------------------------------------
-- Recruiting › Welcome: the second list, "For members who return" (#449). Built on the welcome card: returns
-- { commit = function() (the card's Save), refresh = function() }.
----------------------------------------------------------------------
function UI:WelcomeBackList(card, relayout)
    local R, Forms = GuildOS.Recruitment, GuildOS.Forms
    if not (R and Forms and card) then return nil end
    local MAX = R.WELCOME_MAX
    local rows, shown = {}, 1
    local api = {}
    local holder = CreateFrame("Frame", nil, card)
    holder:SetSize(1, 1)
    local cap = Forms:Soft(holder, L["For members who return"], UI.SP.META)
    cap:SetPoint("TOPLEFT", 0, 0)
    cap:SetWordWrap(false)
    for i = 1, MAX do
        local box = UI:CreateInput(holder, 200, Forms.FIELD_H, { max = 255 })
        local remove = UI:SetButtonVariant(UI:CreateButton(holder, L["Remove"], 40, UI.SP.HIT), "ghost")
        remove:SetWidth(math.ceil(remove.label:GetStringWidth() or 30) + 6)
        remove:SetScript("OnClick", function()
            for _, row in ipairs(rows) do row.box:ClearFocus() end
            if i <= #R.WelcomeBackList(GuildOS.db.recruitment) then R:RemoveWelcomeBack(i) end
            for j = i, MAX - 1 do rows[j].box:SetText(rows[j + 1].box:GetText() or "") end
            rows[MAX].box:SetText("")
            shown = math.max(1, shown - 1)
            api.refresh()
        end)
        rows[i] = { box = box, remove = remove }
    end
    card:Add(holder, { place = function(_, w)
        cap:SetWidth(math.max(1, w))
        local y = 14 + Forms.LABEL_GAP
        local rw = 0
        for _, row in ipairs(rows) do rw = math.max(rw, row.remove:GetWidth()) end
        for i = 1, MAX do
            local row = rows[i]
            local on = i <= shown
            row.box:SetShown(on)
            row.remove:SetShown(on and (row.box:GetText() or "") ~= "")
            if on then
                row.box:ClearAllPoints()
                row.box:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
                row.box:SetWidth(math.max(40, w - rw - UI.SP.CELL))
                row.remove:ClearAllPoints()
                row.remove:SetPoint("RIGHT", holder, "TOPRIGHT", 0, -(y + Forms.FIELD_H / 2))
                y = y + Forms.FIELD_H + Forms.ROW_GAP
            end
        end
        local h = y - Forms.ROW_GAP
        holder:SetSize(math.max(1, w), h)
        return h
    end })
    local add = Forms:Button(card, L["Add message"])
    card:Flow({ add }, { shown = function() return shown < MAX end })
    card:Note(L["Empty: a member who returns gets the welcome above. {days} is how many days they were away, {since} the date they left."])
    add:SetScript("OnClick", function()
        if not api.commit() then return end   -- what was typed is kept, then a new row opens
        shown = math.min(MAX, #R.WelcomeBackList(GuildOS.db.recruitment) + 1)
        api.refresh()
        rows[shown].box:SetFocus()
    end)
    function api.commit()
        local list = R.WelcomeBackList(GuildOS.db.recruitment)
        for i = 1, shown do
            local txt = rows[i].box:GetText()
            if txt and txt ~= "" and list[i] ~= txt then
                local ok, problem = R:SetWelcomeBack(i, txt)
                if problem then GuildOS:Print(problem); return false end
                if ok then GuildOS:Print(L["Welcome message updated."]) end
            end
            rows[i].box:ClearFocus()
        end
        return true
    end
    function api.refresh()
        local list = R.WelcomeBackList(GuildOS.db.recruitment)
        shown = math.max(1, #list, math.min(shown, #list + 1))
        for i = 1, MAX do
            local box = rows[i].box
            if i > shown then box:SetText("")
            elseif list[i] and not box:HasFocus() then box:SetText(list[i]) end
        end
        if relayout then relayout() end
    end
    api.rows = rows
    return api
end
