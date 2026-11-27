----------------------------------------------------------------------
-- Guild OS - The officer action queue on screen (#449; Modules/ActionQueue.lua)
--   * GuildOSQueueNext: the button the "Guild OS: next in the queue" binding clicks (Bindings.xml, a CLICK
--     binding). A secure action button, made out of combat at load like the bulk actions' Next, so the same key
--     press can run the bulk actions' line; for anything else its PreClick runs the queue's next action, inside
--     the key press, and the macro stays empty.
--   * The toast: a small floating window (Kit:Float) "Press [key] (or click) to invite Fulano · N more", with the
--     action's button. Movable (its place is kept), hideable (it comes back with the next action), opened through
--     GuildOS:ShowWhenClear, so never in combat, and hidden when a fight starts.
--   * WoW: Forever: the "/ginvite Name" line, selected in an edit box to copy (Ctrl+C, Enter, Ctrl+V, Enter).
--     Never written into the chat box: that taints it (#256).
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local UI = GuildOS.UI
local L = GuildOS.L
local AQ = GuildOS.ActionQueue

-- The binding's name in Key Bindings, AddOns, Guild OS (the header is UI/Window.lua's).
_G["BINDING_NAME_CLICK GuildOSQueueNext:LeftButton"] = L["Guild OS: next in the queue"]

local TOAST_W = 360
local TYPED_W = 380

----------------------------------------------------------------------
-- The binding's button
----------------------------------------------------------------------
local nextBtn
local function ensure()
    if nextBtn or GuildOS.Compat.InCombat() or not AQ then return nextBtn end
    nextBtn = CreateFrame("Button", AQ.BUTTON, UIParent, "SecureActionButtonTemplate")
    nextBtn:SetSize(1, 1)
    nextBtn:Hide()
    GuildOS.Compat.SecureClicks(nextBtn)
    GuildOS.Compat.SetSecureMacro(nextBtn, "")
    nextBtn:SetScript("PreClick", function(self, _, down)
        local line = ""
        local ok, got = pcall(AQ.Arm, AQ, down)
        if ok then line = got or "" end
        GuildOS.Compat.SetSecureMacro(self, line)
    end)
    nextBtn:SetScript("PostClick", function(self, _, down)
        GuildOS:SafeCall(AQ.AfterClick, AQ, down)
        GuildOS.Compat.SetSecureMacro(self, "")
    end)
    return nextBtn
end
ensure()

----------------------------------------------------------------------
-- The toast
----------------------------------------------------------------------
local toast
local hiddenByHand = false   -- the close hid it: back with the next action

local function store()
    local s = GuildOS:GetSetting("actionToast")
    if type(s) ~= "table" then
        s = {}
        GuildOS:SetSetting("actionToast", s)
    end
    return s
end

local function buildToast()
    if toast then return toast end
    local Kit = GuildOS.Kit
    local saved = store()
    local f = Kit:Float(L["Officer queue"], {
        name = "GuildOSActionToast", width = TOAST_W, height = Kit.HEADER_H + 2 * UI.SP.PAD + UI.SP.FIELD + 20,
        strata = "MEDIUM", foot = false,
        point = { saved.point or "TOP", saved.x or 0, saved.y or -140 },
        onClose = function(fr) hiddenByHand = true; fr:Hide() end,
    })
    f:ClearAllPoints()
    f:SetPoint(saved.point or "TOP", UIParent, saved.point or "TOP", saved.x or 0, saved.y or -140)
    f.header:HookScript("OnDragStop", function()
        local point, _, _, x, y = f:GetPoint()
        local s = store()
        s.point, s.x, s.y = point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
    end)
    local line = UI:CreateText(f.body, "", UI.SP.BODY)
    line:SetPoint("TOPLEFT", 0, -2)
    line:SetWidth(TOAST_W - 2 * Kit.PAD)
    line:SetJustifyH("LEFT")
    f.line = line
    local go = UI:CreateButton(f.body, L["Do it"], 140, UI.SP.FIELD)
    UI:SetButtonVariant(go, "primary")
    go:SetPoint("BOTTOMLEFT", 0, 0)
    -- A click is a hardware event: it runs the next action here, as the key press does.
    go:SetScript("OnClick", function() GuildOS:SafeCall(AQ.Next, AQ, true) end)
    f.go = go
    local skip = UI:CreateButton(f.body, L["Skip"], 90, UI.SP.FIELD)
    skip:SetPoint("LEFT", go, "RIGHT", UI.SP.UNIT * 2, 0)
    skip:SetScript("OnClick", function()
        local item = AQ:Peek(true)
        if item then AQ:Remove(item.key) end
    end)
    f.skip = skip
    toast = f
    return f
end

-- Fills the toast from the queue: hidden with nothing to show.
function AQ:RefreshToast()
    local item = self:Peek(true)
    if not item then
        if toast then toast:Hide() end
        return nil
    end
    local f = buildToast()
    f.line:SetText(self:PromptText(item) or "")
    -- Grown to the line: under the header, the line, a gap, the buttons and the body's bottom margin.
    local Kit = GuildOS.Kit
    f:SetHeight(Kit.HEADER_H + 8 + 2 + math.ceil(f.line:GetStringHeight() or 14) + UI.SP.FIELD_GAP + UI.SP.FIELD + 10)
    local verb = item.kind == "guildInvite" and L["Invite"] or item.kind == "who" and L["Check"]
        or item.kind == "channel" and L["Post"] or L["Do it"]
    f.go.label:SetText(verb)
    f:SetTitle(L["Officer queue"], tostring(self:Pending(true)))
    f:Show()
    return f
end

AQ.onChange = function()
    if not AQ:Peek(true) then
        if toast then toast:Hide() end
        GuildOS:CancelWhenClear("actionqueue")
        return
    end
    if toast and toast:IsShown() then AQ:RefreshToast() return end
    if hiddenByHand and not AQ._fresh then return end
    hiddenByHand = false
    GuildOS:ShowWhenClear("actionqueue", function() return AQ:RefreshToast() end)
end

-- A new action brings a hidden toast back.
local add = AQ.Add
function AQ:Add(item, fromClick)
    self._fresh = true
    local r = add(self, item, fromClick)
    self._fresh = nil
    return r
end

----------------------------------------------------------------------
-- WoW: Forever: the /ginvite line to copy
----------------------------------------------------------------------
local typed
local function buildTyped()
    if typed then return typed end
    local Kit = GuildOS.Kit
    local f = Kit:Float(L["Invite to the guild"], {
        name = "GuildOSInviteLine", width = TYPED_W,
        height = Kit.HEADER_H + 8 + 2 * UI.SP.PAD + 34 + UI.SP.FIELD + 10,
        point = { "TOP", 0, -200 },
        onClose = function(fr) fr:Hide() end,
    })
    local note = UI:CreateText(f.body, "", UI.SP.BODY)
    note:SetPoint("TOPLEFT", 0, -2)
    note:SetWidth(TYPED_W - 2 * Kit.PAD)
    note:SetJustifyH("LEFT")
    f.note = note
    local box = UI:CreateInput(f.body, TYPED_W - 2 * Kit.PAD, UI.SP.FIELD)
    box:SetPoint("BOTTOMLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    -- Read-only: whatever is typed, the line stays the one to copy.
    box:HookScript("OnTextChanged", function(self, userInput)
        if userInput and f.lineText and self:GetText() ~= f.lineText then
            self:SetText(f.lineText)
            self:HighlightText()
        end
    end)
    -- Enter after Ctrl+C: this window goes, so the next Enter opens the chat box for Ctrl+V.
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    box:HookScript("OnEscapePressed", function() f:Hide() end)
    box:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.box = box
    -- However it went (Enter, Escape, the close), the line shown is done; the next one comes once this one is
    -- gone, never over a fight (ShowWhenClear).
    f:HookScript("OnHide", function()
        if f.shownName and AQ:NextTyped() == f.shownName then AQ:DoneTyped() end
        f.shownName = nil
        if AQ:NextTyped() then GuildOS:ShowWhenClear("inviteline", function() return AQ:ShowTyped() end) end
    end)
    typed = f
    return f
end

--- Shows the next /ginvite line to copy; the window, or nil with none waiting.
function AQ:ShowTyped()
    local name, n = self:NextTyped()
    if not name then
        if typed then typed:Hide() end
        return nil
    end
    local f = buildTyped()
    f.lineText, f.shownName = AQ.TypedLine(name), name
    local more = n > 1 and (" \194\183 " .. string.format(L["%d more"], n - 1)) or ""
    f.note:SetText(string.format(L["%s whispered the keyword. The game lets no addon invite here: copy the line and send it (Ctrl+C, Enter, Ctrl+V, Enter)."], name) .. more)
    -- WoW: Forever's own right-click menu has no guild invite either: the typed line is the only way.
    f.box:SetText(f.lineText)
    local Kit = GuildOS.Kit
    f:SetHeight(Kit.HEADER_H + 8 + 2 + math.ceil(f.note:GetStringHeight() or 14) + UI.SP.FIELD_GAP + UI.SP.FIELD + 10)
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
    return f
end

AQ.onTyped = function()
    if typed and typed:IsShown() then return end
    GuildOS:ShowWhenClear("inviteline", function() return AQ:ShowTyped() end)
end

----------------------------------------------------------------------
-- Combat: the button is made at the first moment out of it, the windows go when it starts and the toast comes back
-- after it (the queue keeps waiting).
----------------------------------------------------------------------
local combat = CreateFrame("Frame")
GuildOS.Compat.RegisterEvent(combat, "PLAYER_REGEN_DISABLED")
GuildOS.Compat.RegisterEvent(combat, "PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if toast and toast:IsShown() then toast:Hide() end
    else
        ensure()
        if AQ:Peek(true) and not hiddenByHand then
            GuildOS:ShowWhenClear("actionqueue", function() return AQ:RefreshToast() end)
        end
    end
end)
