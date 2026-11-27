----------------------------------------------------------------------
-- Guild OS - Bulk actions panel (issue #420; Leadership > Bulk actions)
-- The rules, the preview of who they pick, and the Next button that acts
-- on one member per click. Visual layout only: what is picked, the queue
-- and the line each click runs are GuildOS.BulkActions' (Rule 10).
--
-- Next is a secure action button (ADR-0038): its PreClick asks the module
-- for this click's line and sets it, the game runs it, its PostClick clears
-- it. It is made at the first moment out of combat after load (a protected
-- frame's size and backdrop are refused in combat, as after a /reload in a
-- fight), so `/click GuildOSBulkNext` works before the tab is opened, and it
-- leaves the window when combat starts: the game would refuse to hide a
-- window holding a protected button in combat.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
-- Drawn on a parchment card in the Officers' Room and Settings (specs/salao/fase3.md): the text takes the
-- paper's inks and a class its colour on the paper (UI/Kit.lua); a floating window, the wood's (WOOD).
local Kit = rawget(GuildOS, "Kit")
local C = Kit and Kit.PAPER or GuildOS.Colors
local function classInk(class)
    if Kit then return Kit:ClassInk(class) end
    return GuildOS:GetClassColor(class)
end
local function rule(row) if Kit then Kit:Rule(row) end end
local L = GuildOS.L

local ROW_H = 24
local FIELD_W = 44         -- a numeric rule field
local NAMES_SHOWN = 10     -- names the removal's confirmation lists before "and N more"
local NEXT_W = 220         -- the Next button

GuildOS.Dialogs["GUILDOS_BULK_REMOVE"] = {
    text = "%s",
    button1 = L["Start"],
    button2 = L["Cancel"],
    -- Exactly the members the dialog listed, each still checked again before their click.
    OnAccept = function(_, data)
        if data and GuildOS.BulkActions then GuildOS:SafeCall(GuildOS.BulkActions.StartAndSay, GuildOS.BulkActions,
            data.rules, "remove", true, data.shown) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

----------------------------------------------------------------------
-- The Next button
----------------------------------------------------------------------
local nextBtn   -- made by ensure(), out of combat
local function ensure()
    if nextBtn or GuildOS.Compat.InCombat() then return nextBtn end
    nextBtn = UI:CreateButton(UIParent, L["Next"], NEXT_W, 24, "GuildOSBulkNext", "SecureActionButtonTemplate")
    UI:SetButtonVariant(nextBtn, "primary")
    nextBtn:Hide()
    GuildOS.Compat.SecureClicks(nextBtn)
    GuildOS.Compat.SetSecureMacro(nextBtn, "")
    nextBtn:SetScript("PreClick", function(self, _, down)
        GuildOS.Compat.SetSecureMacro(self, GuildOS.BulkActions and GuildOS.BulkActions:Arm(down) or "")
    end)
    nextBtn:SetScript("PostClick", function(self, _, down)
        if GuildOS.BulkActions then GuildOS:SafeCall(GuildOS.BulkActions.AfterClick, GuildOS.BulkActions, down) end
        GuildOS.Compat.SetSecureMacro(self, "")
    end)
    return nextBtn
end
ensure()

-- The button's label (a font string: free to change in combat too).
local function setNextLabel(text)
    if nextBtn then nextBtn.label:SetText(text) end
end

local slot   -- where the panel shows the button, once built
local function dock()
    if not (ensure() and slot) or GuildOS.Compat.InCombat() then return end
    nextBtn:SetParent(slot)
    nextBtn:ClearAllPoints()
    nextBtn:SetPoint("LEFT", slot, "LEFT", 0, 0)
    nextBtn:Show()
end
local function undock()
    if not nextBtn then return end
    nextBtn:SetParent(UIParent)
    nextBtn:ClearAllPoints()
    nextBtn:Hide()
end
local combat = CreateFrame("Frame")
GuildOS.Compat.RegisterEvent(combat, "PLAYER_REGEN_DISABLED")
GuildOS.Compat.RegisterEvent(combat, "PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then undock() else dock() end
end)

----------------------------------------------------------------------
-- The sub-panel
----------------------------------------------------------------------
local SKIP_TEXT = { left = L["left the guild"], rank = L["rank changed"], rules = L["no longer meets the rules"],
                    name = L["unknown name"], you = L["skipped"] }

-- The line a member's row says about them: offline days, attendance.
local function detailOf(m)
    local parts = {}
    if m.daysOffline then parts[#parts + 1] = m.daysOffline .. L["d offline"] end
    if m.attendance then parts[#parts + 1] = string.format(L["%d%% attendance"], m.attendance) end
    if m.hasAddon == false then parts[#parts + 1] = L["no GuildOS"] end
    if m.rankDays then parts[#parts + 1] = string.format(L["%d days in rank"], m.rankDays) end
    -- The group's most recently seen other character (specs/salao/manutencao-roster.md).
    local RM = GuildOS.RosterMaint
    local seen = RM and m.seen and RM.SeenText(m.seen)
    if seen then parts[#parts + 1] = seen end
    if m.viaGroup then parts[#parts + 1] = L["with its group"] end
    return table.concat(parts, "  ")
end

local function statusOf(item)
    if item.status == "done" then return L["done"], C.green end
    if item.status == "sent" then return L["sent"], C.warn end
    if item.status == "unconfirmed" then return L["not confirmed, check it"], C.red end
    if item.status == "skipped" then return SKIP_TEXT[item.why] or L["skipped"], C.textDim end
    return L["waiting"], C.silver
end

function GuildOS:BuildBulkSub(panel)
    local BA = GuildOS.BulkActions
    if not BA then return nil end
    local action = "promote"
    local preview, previewWhy = nil, nil
    local macroFS_text

    -- Under the card's title ("Bulk actions").
    local Forms = GuildOS.Forms
    local board = UI:CreateBoard(panel, { name = "GuildOSMgmtBulkBoard" })
    local refresh
    -- The rules (the mockup's "Bulk actions" card): the action as pills, the rules as fields above their
    -- boxes, Preview and Start at the card's bottom right.
    local card = board:Card(L["Bulk actions"], { col = 1 })
    card:Note(L["Pick members by rules, then act on one per click of Next: the game lets a rank change or a removal come only from your click."])
    local actBtns, actList = {}, {}
    for _, key in ipairs(BA.ACTIONS) do
        local b = Forms:Pill(card, BA:ActionText(key))
        b:SetScript("OnClick", function()
            action, preview = key, nil
            refresh()
        end)
        actBtns[key] = b
        actList[#actList + 1] = b
    end
    card:Note(L["Action"], { gap = 10 })
    card:Flow(actList, { gap = Forms.LABEL_GAP })

    local function field(parent)
        local box = UI:CreateInput(parent, FIELD_W, 24, { numeric = true, max = 4, justify = "CENTER" })
        box:SetScript("OnEnterPressed", function(s) s:ClearFocus(); preview = nil; refresh() end)
        return box
    end
    -- From one box to the other ("1 to 70"): two boxes and the word between them, as wide as the field.
    local function range(parent)
        local holder = CreateFrame("Frame", nil, parent)
        holder:SetSize(FIELD_W * 2 + 30, 24)
        local a, b = field(holder), field(holder)
        local to = UI:CreateText(holder, L["to"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        a:SetPoint("LEFT", holder, "LEFT", 0, 0)
        to:SetPoint("LEFT", a, "RIGHT", 6, 0)
        b:SetPoint("LEFT", to, "RIGHT", 6, 0)
        holder:SetScript("OnSizeChanged", function(_, w)
            w = tonumber(w) or 0
            local bw = math.max(30, math.floor((w - 12 - (to:GetStringWidth() or 12)) / 2))
            a:SetWidth(bw); b:SetWidth(bw)
        end)
        holder.min, holder.max, holder.to = a, b, to
        return holder
    end
    local daysBox = field(card)
    local rankDD = UI:CreateDropdown(card, 150, 24)
    rankDD.onSelect = function() preview = nil; refresh() end
    card:Pair(Forms:MakeField(card, L["Offline at least"] .. " (" .. L["days"] .. ")", daysBox, { w = 100 }),
              Forms:MakeField(card, L["Rank"], rankDD))
    local lvl, att = range(card), range(card)
    local lvlMin, lvlMax, attMin, attMax = lvl.min, lvl.max, att.min, att.max
    local attField = Forms:MakeField(card, L["Raid attendance"] .. " (%)", att, { w = 200 })
    card:Pair(Forms:MakeField(card, L["Level"], lvl, { w = 200 }), attField)
    local attParts = { attField }
    -- Time in the rank and in the guild (the member history's; specs/salao/manutencao-roster.md).
    local rankDaysBox, tenureBox = field(card), field(card)
    card:Pair(Forms:MakeField(card, L["In the rank at least"] .. " (" .. L["days"] .. ")", rankDaysBox, { w = 100 }),
              Forms:MakeField(card, L["In the guild at least"] .. " (" .. L["days"] .. ")", tenureBox, { w = 100 }))
    local noAddon = card:Check(L["Without GuildOS only"])
    noAddon.checkbox.onChanged = function() preview = nil; refresh() end
    -- A removal by days: the player's alts (the Inactivity screen's setting decides whether they count), and the
    -- whole group only once every character of it is inactive.
    local RM = GuildOS.RosterMaint
    local wholeCB = RM and card:Check(L["Remove the whole group only when every character is inactive"],
        L["Each alt group goes out together, and not while any of its characters was seen within the days."],
        { gap = 4, shown = function() return action == "remove" end })
    if wholeCB then
        wholeCB.checkbox.onChanged = function(_, on) RM:SetWholeGroup(on); preview = nil; refresh() end
    end
    local summary = card:Note("")

    local function rules()
        return {
            days = daysBox:GetText(), rank = rankDD:GetValue(),
            levelMin = lvlMin:GetText(), levelMax = lvlMax:GetText(),
            attMin = attMin:GetText(), attMax = attMax:GetText(),
            noAddon = noAddon.checkbox:GetChecked() and true or false,
            rankDaysMin = rankDaysBox:GetText(), tenureDaysMin = tenureBox:GetText(),
            countAlts = RM and RM:CountAlts() or nil,
            wholeGroup = (RM and action == "remove" and RM:WholeGroup()) or nil,
        }
    end

    local previewBtn = UI:CreateButton(card, L["Preview"], 90, 24)
    local startBtn = UI:CreateButton(card, L["Start"], 90, 24)
    UI:SetButtonVariant(startBtn, "primary")
    card:Actions({ previewBtn, startBtn })
    previewBtn:SetScript("OnClick", function()
        preview, previewWhy = BA:Preview(rules(), action)
        refresh()
    end)
    startBtn:SetScript("OnClick", function()
        if action ~= "remove" then return BA:StartAndSay(rules(), action) end
        -- A removal is final: the officer sees how many and who before the queue starts (#420 review).
        local live, why = BA:Preview(rules(), "remove")
        if why or #live == 0 then
            GuildOS:Print(BA:WhyText(why or "empty"))
            return
        end
        local names = {}
        for i = 1, math.min(NAMES_SHOWN, #live) do names[i] = live[i].name end
        local list = table.concat(names, ", ")
        if #live > NAMES_SHOWN then list = list .. " " .. string.format(L["and %d more"], #live - NAMES_SHOWN) end
        GuildOS:ShowDialog("GUILDOS_BULK_REMOVE", string.format(L["Remove %d member(s) from the guild:"], #live)
            .. " " .. list .. "\n\n" .. L["Each removal still takes one click of Next. Start?"], nil,
            { rules = rules(), shown = live })
    end)

    -- The queue (the mockup's message line): Next (the secure button, docked here), where it is, Retry, Skip
    -- and Stop, the macro's line, then the members: the preview's or the queue's.
    local qcard = board:Card(L["Members"], { col = 2, fill = true })
    local qrow = CreateFrame("Frame", nil, qcard)
    qrow:SetSize(1, 24)
    slot = CreateFrame("Frame", nil, qrow)
    slot:SetSize(NEXT_W, 24)
    slot:SetPoint("TOPLEFT", qrow, "TOPLEFT", 0, 0)
    local queueFS = UI:CreateText(qrow, "", 11, C.text.r, C.text.g, C.text.b)
    queueFS:SetJustifyH("LEFT")
    queueFS:SetWordWrap(true)
    qcard:Add(qrow, { place = function(_, w)
        local beside = w >= NEXT_W + 160
        queueFS:ClearAllPoints()
        if beside then
            queueFS:SetPoint("TOPLEFT", slot, "TOPRIGHT", 12, -5)
            queueFS:SetWidth(w - NEXT_W - 12)
        else
            queueFS:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -6)
            queueFS:SetWidth(w)
        end
        local th = math.ceil(queueFS:GetStringHeight() or 14)
        local h = beside and math.max(24, th + 5) or (24 + 6 + th)
        qrow:SetSize(math.max(1, w), h)
        return h
    end })
    local retryBtn = UI:CreateButton(qcard, L["Retry"], 110, 22)
    retryBtn:SetScript("OnClick", function() BA:RetryUnconfirmed() end)
    retryBtn:Hide()
    local skipBtn = UI:CreateButton(qcard, L["Skip"], 70, 22)
    skipBtn:SetScript("OnClick", function() BA:Skip() end)
    local stopBtn = UI:CreateButton(qcard, L["Stop"], 70, 22)
    stopBtn:SetScript("OnClick", function() BA:Stop() end)
    qcard:Flow({ retryBtn, skipBtn, stopBtn }, { shown = function() return stopBtn:IsShown() end })
    local macroFS = qcard:Note("", { size = UI.SP.META, shown = function() return (macroFS_text or "") ~= "" end })
    dock()

    local listHolder = qcard:Body(ROW_H * 4, { gap = 10 })
    local empty = UI:CreateText(listHolder, "", 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)
    local function createRow(parent)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        rule(row)
        row.nameFS = UI:CreateText(row, "", 11)
        row.nameFS:SetPoint("LEFT", 8, 0)
        row.rankFS = UI:CreateText(row, "", UI.SP.META, C.silver.r, C.silver.g, C.silver.b)
        row.rankFS:SetPoint("LEFT", 170, 0)
        row.lvlFS = UI:CreateText(row, "", UI.SP.META, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lvlFS:SetPoint("LEFT", 310, 0)
        row.detailFS = UI:CreateText(row, "", UI.SP.META, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.detailFS:SetPoint("LEFT", 370, 0)
        row.statusFS = UI:CreateText(row, "", UI.SP.META)
        row.statusFS:SetPoint("RIGHT", -8, 0)
        return row
    end
    local function fillRow(row, m, idx)
        local alt = (idx % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        local cr, cg, cb = classInk(m.class)
        row.nameFS:SetText(m.name)
        row.nameFS:SetTextColor(cr, cg, cb)
        row.rankFS:SetText(m.rankName or "?")
        row.lvlFS:SetText(L["Lv "] .. (m.level or 0))
        row.detailFS:SetText(detailOf(m))
        if m.status then
            local text, col = statusOf(m)
            row.statusFS:SetText(text)
            row.statusFS:SetTextColor(col.r, col.g, col.b)
        else
            row.statusFS:SetText("")
        end
    end
    local list = UI.MakeVirtualList(listHolder, "GuildOSMgmtBulkScroll", ROW_H + 2, createRow, fillRow)

    refresh = function()
        for key, b in pairs(actBtns) do Forms:SetOn(b, key == action) end
        -- The ranks, as the roster knows them now.
        local opts = { { value = -1, text = L["Any rank"] } }
        for _, r in ipairs(GuildOS.GuildManager and GuildOS.GuildManager:GetRanks() or {}) do
            opts[#opts + 1] = { value = r.index, text = r.name }
        end
        rankDD:SetOptions(opts)
        if rankDD:GetValue() == nil then rankDD:SetValue(-1) end
        if wholeCB then wholeCB.checkbox:SetChecked(RM:WholeGroup()) end
        local hasAtt = BA:HasAttendance()
        for _, part in ipairs(attParts) do part:SetShown(hasAtt) end
        if not hasAtt then attMin:SetText(""); attMax:SetText("") end

        local allowed = BA:Allowed(action)
        for _, b in ipairs({ startBtn, previewBtn }) do
            if allowed then b:Enable() else b:Disable() end
        end

        local q = BA:Queue()
        if q then
            local c = BA:Counts()
            local item = BA:Current()
            queueFS:SetText(item and string.format(L["Next: %s (%s), %d of %d"], item.name, item.rankName or "?",
                    c.done + c.sent + c.skipped + 1, c.total)
                or string.format(L["Bulk actions done: %d done, %d waiting for the roster, %d skipped."],
                    c.done, c.sent, c.skipped))
            setNextLabel(BA:NextLabel())
            macroFS_text = BA:Typed() and L["On this client the game takes the line only typed: each click of Next prints it for you."]
                or string.format(L["Or press a macro with %s, one member per press."], GuildOS.Compat.ClickMacro(BA.BUTTON))
            -- The officer action queue's key does the same step when nothing else waits in it (#449).
            local AQ = GuildOS.ActionQueue
            local key = AQ and not BA:Typed() and AQ:KeyText()
            if key then macroFS_text = macroFS_text .. " " .. string.format(L["Or press %s."], key) end
            macroFS:SetText(macroFS_text)
            skipBtn:SetShown(item ~= nil)
            retryBtn.label:SetText(string.format(L["Retry (%d)"], c.unconfirmed))
            retryBtn:SetShown(c.unconfirmed > 0)
            stopBtn:Show()
            summary:SetText("")
            empty:SetText("")
            list:SetData(q.items)
        else
            queueFS:SetText(L["Preview the rules, then Start."])
            setNextLabel(L["Next"])
            macroFS_text = ""
            macroFS:SetText("")
            skipBtn:Hide()
            retryBtn:Hide()
            stopBtn:Hide()
            if not allowed then
                summary:SetText(BA:WhyText("permission"))
            elseif preview then
                summary:SetText(previewWhy and BA:WhyText(previewWhy) or string.format(L["%d member(s)"], #preview))
            else
                summary:SetText("")
            end
            empty:SetText(preview and #preview == 0 and not previewWhy and BA:WhyText("empty") or "")
            list:SetData(preview or {})
        end
        board:Layout()
    end

    -- Only while it is on screen (memory audit): showing it refreshes it anyway.
    if BA then BA.uiRefresh = function() if panel:IsVisible() then refresh() end end end
    return refresh
end
