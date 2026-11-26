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
local UI = GuildOS.UI
local C = GuildOS.Colors
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

    local title = UI:CreateSectionTitle(panel, L["BULK ACTIONS"], true)
    title:SetPoint("TOPLEFT", 0, -2)
    local hint = UI:CreateText(panel,
        L["Pick members by rules, then act on one per click of Next: the game lets a rank change or a removal come only from your click."],
        11, C.silver.r, C.silver.g, C.silver.b)
    hint:SetPoint("TOPLEFT", 0, -24)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -24)
    hint:SetJustifyH("LEFT")

    -- What to do.
    local y = -52
    local actLbl = UI:CreateText(panel, L["Action"], 11, C.text.r, C.text.g, C.text.b)
    actLbl:SetPoint("TOPLEFT", 0, y - 4)
    local actBtns, prev = {}, actLbl
    local refresh
    for _, key in ipairs(BA.ACTIONS) do
        local b = UI:CreateButton(panel, BA:ActionText(key), 90, 22)
        b:SetPoint("LEFT", prev, "RIGHT", prev == actLbl and 12 or 6, 0)
        b:SetScript("OnClick", function()
            action, preview = key, nil
            refresh()
        end)
        actBtns[key], prev = b, b
    end

    -- The rules.
    local function label(text, anchor, dx)
        local fs = UI:CreateText(panel, text, 11, C.text.r, C.text.g, C.text.b)
        fs:SetPoint("LEFT", anchor, "RIGHT", dx or 6, 0)
        return fs
    end
    local function field(anchor, dx)
        local box = UI:CreateInput(panel, FIELD_W, 22, { numeric = true, max = 4, justify = "CENTER" })
        box:SetPoint("LEFT", anchor, "RIGHT", dx or 6, 0)
        box:SetScript("OnEnterPressed", function(s) s:ClearFocus(); preview = nil; refresh() end)
        return box
    end
    y = y - 32
    local offLbl = UI:CreateText(panel, L["Offline at least"], 11, C.text.r, C.text.g, C.text.b)
    offLbl:SetPoint("TOPLEFT", 0, y - 4)
    local daysBox = field(offLbl, 8)
    local daysLbl = label(L["days"], daysBox)
    local rankLbl = label(L["Rank"], daysLbl, 20)
    local rankDD = UI:CreateDropdown(panel, 150, 22)
    rankDD:SetPoint("LEFT", rankLbl, "RIGHT", 8, 0)
    rankDD.onSelect = function() preview = nil; refresh() end
    local noAddon = UI:CreateCheckbox(panel, L["Without GuildOS only"], 18)
    noAddon:SetPoint("LEFT", rankDD, "RIGHT", 16, 0)
    noAddon.checkbox.onChanged = function() preview = nil; refresh() end

    y = y - 32
    local lvlLbl = UI:CreateText(panel, L["Level"], 11, C.text.r, C.text.g, C.text.b)
    lvlLbl:SetPoint("TOPLEFT", 0, y - 4)
    local lvlMin = field(lvlLbl, 8)
    local lvlTo = label(L["to"], lvlMin)
    local lvlMax = field(lvlTo)
    local attLbl = label(L["Raid attendance"], lvlMax, 20)
    local attMin = field(attLbl, 8)
    local attTo = label(L["to"], attMin)
    local attMax = field(attTo)
    local attPct = label("%", attMax, 4)
    local attParts = { attLbl, attMin, attTo, attMax, attPct }

    local function rules()
        return {
            days = daysBox:GetText(), rank = rankDD:GetValue(),
            levelMin = lvlMin:GetText(), levelMax = lvlMax:GetText(),
            attMin = attMin:GetText(), attMax = attMax:GetText(),
            noAddon = noAddon.checkbox:GetChecked() and true or false,
        }
    end

    -- Preview and start.
    y = y - 34
    local previewBtn = UI:CreateButton(panel, L["Preview"], 90, 22)
    previewBtn:SetPoint("TOPLEFT", 0, y)
    local summary = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    summary:SetPoint("LEFT", previewBtn, "RIGHT", 12, 0)
    local startBtn = UI:CreateButton(panel, L["Start"], 90, 22)
    startBtn:SetPoint("TOPRIGHT", 0, y)
    previewBtn:SetScript("OnClick", function()
        preview, previewWhy = BA:Preview(rules(), action)
        refresh()
    end)
    startBtn:SetScript("OnClick", function()
        if action ~= "remove" then return BA:StartAndSay(rules(), action) end
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

    -- The queue: Next, the member it is for, skip and stop.
    y = y - 34
    slot = CreateFrame("Frame", nil, panel)
    slot:SetSize(NEXT_W, 24)
    slot:SetPoint("TOPLEFT", 0, y)
    local queueFS = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    queueFS:SetPoint("LEFT", slot, "RIGHT", 12, 0)
    local stopBtn = UI:CreateButton(panel, L["Stop"], 70, 22)
    stopBtn:SetPoint("TOPRIGHT", 0, y - 1)
    stopBtn:SetScript("OnClick", function() BA:Stop() end)
    local skipBtn = UI:CreateButton(panel, L["Skip"], 70, 22)
    skipBtn:SetPoint("RIGHT", stopBtn, "LEFT", -6, 0)
    skipBtn:SetScript("OnClick", function() BA:Skip() end)
    -- The members the roster never showed changed go back in the queue (audit M13).
    local retryBtn = UI:CreateButton(panel, L["Retry"], 110, 22)
    retryBtn:SetPoint("RIGHT", skipBtn, "LEFT", -6, 0)
    retryBtn:SetScript("OnClick", function() BA:RetryUnconfirmed() end)
    retryBtn:Hide()
    local macroFS = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    macroFS:SetPoint("TOPLEFT", 0, y - 30)
    macroFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y - 30)
    macroFS:SetJustifyH("LEFT")
    dock()

    -- The members: the queue while one runs, the preview otherwise.
    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, y - 50)
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local empty = UI:CreateText(listHolder, "", 11, C.silver.r, C.silver.g, C.silver.b)
    empty:SetPoint("TOPLEFT", 0, -4)
    local function createRow(parent)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(ROW_H)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row.nameFS = UI:CreateText(row, "", 11)
        row.nameFS:SetPoint("LEFT", 8, 0)
        row.rankFS = UI:CreateText(row, "", 10, C.silver.r, C.silver.g, C.silver.b)
        row.rankFS:SetPoint("LEFT", 170, 0)
        row.lvlFS = UI:CreateText(row, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lvlFS:SetPoint("LEFT", 310, 0)
        row.detailFS = UI:CreateText(row, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.detailFS:SetPoint("LEFT", 370, 0)
        row.statusFS = UI:CreateText(row, "", 10)
        row.statusFS:SetPoint("RIGHT", -8, 0)
        return row
    end
    local function fillRow(row, m, idx)
        local alt = (idx % 2 == 0) and C.row1 or C.row2
        row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
        local cr, cg, cb = GuildOS:GetClassColor(m.class)
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
        for key, b in pairs(actBtns) do UI:SetSelected(b, key == action) end
        -- The ranks, as the roster knows them now.
        local opts = { { value = -1, text = L["Any rank"] } }
        for _, r in ipairs(GuildOS.GuildManager and GuildOS.GuildManager:GetRanks() or {}) do
            opts[#opts + 1] = { value = r.index, text = r.name }
        end
        rankDD:SetOptions(opts)
        if rankDD:GetValue() == nil then rankDD:SetValue(-1) end
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
            macroFS:SetText(BA:Typed() and L["On this client the game takes the line only typed: each click of Next prints it for you."]
                or string.format(L["Or press a macro with %s, one member per press."], GuildOS.Compat.ClickMacro(BA.BUTTON)))
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
    end

    if BA then BA.uiRefresh = refresh end
    return refresh
end
