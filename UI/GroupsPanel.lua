----------------------------------------------------------------------
-- Guild OS - The Groups tab (issue #341)
-- The guild's own group finder: what is being formed and who is looking (Active), and the game's
-- activities as tiles (Dungeons, Raids, Quests and more), each with how many groups and players it
-- has. Modules/Groups.lua and Modules/LFGBoard.lua answer; this draws and calls their methods.
--
-- One scroll area, repainted from pools: a repaint that created its rows would leak them, because
-- the client never frees a frame.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local TAB_H, TAB_MIN_W, TAB_PAD = 28, 70, 20   -- as the Guild hub's sub-tabs
local TILE_MIN_W, TILE_H, GAP = 150, 60, 6
local CARD_H, ROW_H, HEAD_H = 48, 24, 24
local CHIP = 22
local ART_ALPHA = 0.55          -- the game's art under a tile's text
local OFF_LEVEL_ALPHA = 0.5     -- a tile outside my level
local LEVEL_SLACK = 5           -- levels past an activity's range it still reads as mine
local REPAINT_EVERY = 30        -- seconds: the time left on a listing
local NAME_W, ROLES_W, TIME_W = 130, 96, 44

local LETTERS = { "T", "H", "D" }
local ROLE_OF = { T = "TANK", H = "HEALER", D = "DPS" }
local SUBS = {
    { key = "active",  label = L["Active now"] },
    { key = "dungeon", label = L["Dungeons"] },
    { key = "raid",    label = L["Raids"] },
    { key = "other",   label = L["Quests and more"] },
}

local function roleColor(letter)
    return (letter == "T" and C.info) or (letter == "H" and C.ok) or C.danger
end

local function roleNames(roles)
    local B, out = GuildOS.LFGBoard, {}
    for _, k in ipairs(LETTERS) do
        if roles:find(k, 1, true) then out[#out + 1] = B:RoleName(ROLE_OF[k]) end
    end
    return #out > 0 and table.concat(out, ", ") or B:RoleName("ANY")
end

local function coloured(name, classFile)
    if not classFile then return name end
    return "|cff" .. GuildOS:GetClassColorHex(classFile) .. name .. "|r"
end

local function whisper(name)
    local target = GuildOS:WhisperTarget(name)
    if ChatFrame_SendTell then ChatFrame_SendTell(target) else ChatFrame_OpenChat("/w " .. target .. " ") end
end

local function oneLine(fs, width)
    fs:SetWidth(math.max(10, width))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
end

-- A role's square: its letter, lit in the role's colour when on.
local function createRoleChip(parent, letter)
    local chip = CreateFrame("Button", nil, parent, "BackdropTemplate")
    chip:SetSize(CHIP, CHIP)
    chip:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    chip:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    chip.label = UI:CreateText(chip, letter, 11)
    chip.label:SetPoint("CENTER")
    chip.letter = letter
    function chip:SetOn(on)
        self.on = on and true or false
        local ink = self.on and roleColor(letter) or C.labelDim
        self.label:SetTextColor(ink.r, ink.g, ink.b)
        local edge = self.on and ink or C.line
        self:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
    end
    chip:SetOn(false)
    local B = GuildOS.LFGBoard
    UI:AddTooltip(chip, B:RoleName(ROLE_OF[letter]))
    return chip
end

----------------------------------------------------------------------
-- The composer: one popup, two modes (I am looking; I am forming a group)
----------------------------------------------------------------------
local composer

local function defaultNeed(act)
    local need = { T = 1, H = 1, D = 3 }
    local mine = GuildOS.LFGBoard:Pref("roles") or ""
    if #mine == 1 and need[mine] > 0 then need[mine] = need[mine] - 1 end
    local room = GuildOS.Groups:SizeOf(act) - 1
    return GuildOS.Groups:_SanitizeNeed(need, room)
end

local function buildComposer()
    local B, G = GuildOS.LFGBoard, GuildOS.Groups
    local f = CreateFrame("Frame", "GuildOSGroupComposer", UIParent, "BackdropTemplate")
    f:SetSize(380, 372)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    f:Hide()

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    local PAD, y = 16, -14
    local function label(text)
        local fs = UI:CreateHeaderText(f, text, 10)
        fs:SetPoint("TOPLEFT", PAD, y)
        y = y - 16
        return fs
    end

    -- Mode
    local tabs = {}
    local function modeTab(mode, text, x)
        local t = UI:CreateTab(f, text, TAB_MIN_W, true)
        t:SetWidth(math.max(TAB_MIN_W, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
        t:SetPoint("TOPLEFT", x, y)
        t:SetScript("OnClick", function() f:SetMode(mode) end)
        tabs[mode] = t
        return t
    end
    local seekTab = modeTab("seek", L["I am looking"], PAD)
    modeTab("group", L["Form a group"], PAD + seekTab:GetWidth() + 4)
    y = y - TAB_H - 10

    -- Activity
    label(L["ACTIVITY"])
    local actText = UI:CreateText(f, "", 12, C.gold.r, C.gold.g, C.gold.b)
    actText:SetPoint("TOPLEFT", PAD, y)
    actText:SetWidth(f:GetWidth() - PAD * 2)
    actText:SetJustifyH("LEFT")
    actText:SetWordWrap(true)
    actText:SetHeight(28)
    actText:SetJustifyV("TOP")
    local onlyBtn = UI:CreateButton(f, L["Only this one"], 110, 18)
    onlyBtn:SetPoint("TOPRIGHT", -PAD, y + 20)
    y = y - 34

    -- Roles (looking) or open spots (group): the same line, one of the two shown
    local rolesLabel = label("")
    local chips, steppers = {}, {}
    for i, letter in ipairs(LETTERS) do
        local chip = createRoleChip(f, letter)
        chip:SetPoint("TOPLEFT", PAD + (i - 1) * (CHIP + 4), y)
        chip:SetScript("OnClick", function(self)
            self:SetOn(not self.on)
        end)
        chips[letter] = chip

        local st = CreateFrame("Frame", nil, f)
        st:SetSize(104, CHIP)
        st:SetPoint("TOPLEFT", PAD + (i - 1) * 112, y)
        local mark = createRoleChip(st, letter)
        mark:SetPoint("LEFT")
        mark:SetOn(true)
        mark:EnableMouse(false)
        local minus = UI:CreateButton(st, "-", 20, CHIP)
        minus:SetPoint("LEFT", mark, "RIGHT", 4, 0)
        local value = UI:CreateText(st, "0", 12)
        value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
        value:SetWidth(24)
        value:SetJustifyH("CENTER")
        local plus = UI:CreateButton(st, "+", 20, CHIP)
        plus:SetPoint("LEFT", value, "RIGHT", 0, 0)
        st.value = value
        minus:SetScript("OnClick", function() f:Step(letter, -1) end)
        plus:SetScript("OnClick", function() f:Step(letter, 1) end)
        steppers[letter] = st
    end
    y = y - CHIP - 12

    -- Note
    label(L["NOTE"])
    local note = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    note:SetSize(f:GetWidth() - PAD * 2, 22)
    note:SetPoint("TOPLEFT", PAD, y)
    note:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    note:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    note:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    GuildOS:ApplyFont(note, 11)
    note:SetTextColor(C.text.r, C.text.g, C.text.b)
    note:SetTextInsets(6, 6, 0, 0)
    note:SetAutoFocus(false)
    note:SetMaxLetters(60)
    note:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    note:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    y = y - 22 - 12

    -- Duration
    label(L["LISTED FOR"])
    local durations = {}
    local x = PAD
    for _, seconds in ipairs(B.DURATIONS) do
        local b = UI:CreateButton(f, B:DurationName(seconds), 52, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function() f:SetDuration(seconds) end)
        durations[seconds] = b
        x = x + b:GetWidth() + 4
    end
    y = y - 22 - 12

    local chat = UI:CreateCheckbox(f, L["Also post in guild chat"], 18)
    chat:SetPoint("TOPLEFT", PAD - 2, y)
    chat.checkbox.onChanged = function(_, checked) B:SetPref("postToGuild", checked and true or false) end
    y = y - 26

    local hint = UI:CreateText(f, "", 11, C.danger.r, C.danger.g, C.danger.b)
    hint:SetPoint("TOPLEFT", PAD, y)
    hint:SetWidth(f:GetWidth() - PAD * 2)
    hint:SetJustifyH("LEFT")

    local publish = UI:SetButtonVariant(UI:CreateButton(f, L["Publish"], 110, 26), "primary")
    publish:SetPoint("BOTTOMRIGHT", -PAD, 14)
    local down = UI:SetButtonVariant(UI:CreateButton(f, L["Take down"], 100, 26), "danger")
    down:SetPoint("BOTTOMLEFT", PAD, 14)

    local function paint()
        local seek = f.mode == "seek"
        for mode, t in pairs(tabs) do t:SetActive(mode == f.mode) end
        rolesLabel:SetText(seek and L["MY ROLES (NONE IS ANY)"] or L["OPEN SPOTS"])
        local names = {}
        if seek then
            for _, id in ipairs(f.acts) do names[#names + 1] = B:ActivityName(id) end
            actText:SetText(#names > 0 and table.concat(names, ", ") or L["Anything"])
        else
            actText:SetText(f.act and B:ActivityName(f.act) or L["Pick what the group is for."])
        end
        onlyBtn:SetShown(seek and #f.acts > 1 and f.picked ~= nil)
        for _, letter in ipairs(LETTERS) do
            chips[letter]:SetShown(seek)
            steppers[letter]:SetShown(not seek)
            steppers[letter].value:SetText(tostring(f.need[letter] or 0))
        end
        for seconds, b in pairs(durations) do
            local on = seconds == f.ttl
            b.baseBorder = on and C.gold or C.line
            b.baseLabelColor = on and { C.gold.r, C.gold.g, C.gold.b } or { C.text.r, C.text.g, C.text.b }
            UI:_ButtonState(b, "rest")
        end
        local listed = (seek and B:Mine() ~= nil) or (not seek and G:Mine() ~= nil)
        publish.label:SetText(listed and L["Update"] or L["Publish"])
        down:SetShown(listed)
        if seek or f.act then publish:Enable() else publish:Disable() end
    end

    function f:SetMode(mode)
        self.mode = mode
        B:SetPref("lastMode", mode)
        hint:SetText("")
        paint()
    end
    function f:SetDuration(seconds)
        self.ttl = seconds
        paint()
    end
    -- One spot more or less, never past the room a group of this size has besides its leader.
    function f:Step(letter, by)
        local want = {}
        for _, k in ipairs(LETTERS) do want[k] = self.need[k] or 0 end
        want[letter] = math.max(0, want[letter] + by)
        if G:OpenSpots(want) > G:SizeOf(self.act) - 1 then return end
        self.need = want
        paint()
    end

    onlyBtn:SetScript("OnClick", function()
        f.acts = { f.picked }
        paint()
    end)
    down:SetScript("OnClick", function()
        if f.mode == "seek" then B:ClearAvailable() else G:Disband() end
        f:Hide()
    end)
    publish:SetScript("OnClick", function()
        local toGuild = B:Pref("postToGuild") and true or false
        if f.mode == "seek" then
            local roles = ""
            for _, letter in ipairs(LETTERS) do
                if chips[letter].on then roles = roles .. letter end
            end
            B:SetPref("roles", roles)
            B:SetAvailable(nil, note:GetText(), f.ttl, toGuild, roles, f.acts)
        else
            local ok, why = G:Create(f.act, f.need, note:GetText(), f.ttl, toGuild)
            if not ok then
                hint:SetText(why or "")
                return
            end
        end
        f:Hide()
    end)

    -- Open on `act` (a tile), or on what I already have listed. `mode` nil is the one used last,
    -- unless I am leading a group, which is then what there is to change.
    function f:Open(act, mode)
        local mine, group = B:Mine(), G:Mine()
        mode = mode or (group and "group") or (mine and "seek") or B:Pref("lastMode") or "seek"
        self.picked = act
        self.acts = {}
        for _, id in ipairs(mine and mine.acts or {}) do self.acts[#self.acts + 1] = id end
        if act then
            local have = false
            for _, id in ipairs(self.acts) do have = have or id == act end
            if not have then self.acts[#self.acts + 1] = act end
            self.acts = B:_SanitizeActs(self.acts)
        end
        self.act = act or (group and group.act) or nil
        self.need = (group and (not act or act == group.act)) and G:_SanitizeNeed(group.need) or defaultNeed(self.act)
        self.ttl = B:_ClampTtl(GuildOS.db.lfgPrefs.lastTtl)
        local roles = (mine and mine.roles) or B:Pref("roles") or ""
        for _, letter in ipairs(LETTERS) do chips[letter]:SetOn(roles:find(letter, 1, true) ~= nil) end
        local current = (mode == "group" and group) or (mode == "seek" and mine) or nil
        note:SetText(current and current.note or "")
        chat.checkbox:SetChecked(B:Pref("postToGuild") and true or false)
        hint:SetText("")
        self.mode = mode
        paint()
        self:Show()
        self:Raise()
    end

    f.Repaint = paint
    return f
end

local function openComposer(act, mode)
    composer = composer or buildComposer()
    composer:Open(act, mode)
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
function GuildOS:CreateGroupsPanel(parent)
    local B, G, Cat = GuildOS.LFGBoard, GuildOS.Groups, GuildOS.GroupActivities
    parent.activeSub = "active"

    -- Sub-tabs. Anchored on the left only: UI:FlowBar reads GetWidth to wrap (as the Guild hub).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)
    local subTabs, subList = {}, {}

    -- Actions: what I play, listing myself, forming a group.
    local actions = CreateFrame("Frame", nil, parent)
    actions:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -8)
    actions:SetSize(400, 26)   -- its width follows the panel's (MakeResponsive below)

    local rolesLabel = UI:CreateHeaderText(actions, L["I PLAY"], 10)
    rolesLabel:SetPoint("LEFT", 0, 0)
    local myChips = {}
    for i, letter in ipairs(LETTERS) do
        local chip = createRoleChip(actions, letter)
        if i == 1 then
            chip:SetPoint("LEFT", rolesLabel, "RIGHT", 8, 0)
        else
            chip:SetPoint("LEFT", myChips[LETTERS[i - 1]], "RIGHT", 4, 0)
        end
        myChips[letter] = chip
    end

    local groupBtn = UI:SetButtonVariant(UI:CreateButton(actions, L["+ Form a group"], 130, 26), "primary")
    groupBtn:SetPoint("RIGHT", 0, 0)
    local seekBtn = UI:CreateButton(actions, L["I am looking..."], 120, 26)
    seekBtn:SetPoint("RIGHT", groupBtn, "LEFT", -6, 0)

    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSGroupsScroll")
    scroll:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    ------------------------------------------------------------------
    -- Pools
    ------------------------------------------------------------------
    local pools = {}
    local function acquire(kind, make)
        local pool = pools[kind]
        if not pool then
            pool = { used = 0, items = {} }
            pools[kind] = pool
        end
        pool.used = pool.used + 1
        local item = pool.items[pool.used]
        if not item then
            item = make()
            pool.items[pool.used] = item
        end
        item:Show()
        return item
    end
    local function releaseAll()
        for _, pool in pairs(pools) do
            for _, item in ipairs(pool.items) do item:Hide() end
            pool.used = 0
        end
    end

    local y, width = 0, 400
    local paint   -- forward: the handlers below repaint

    local function head(text, extra)
        local fs = acquire("head", function()
            local t = UI:CreateText(content, "", 12, C.gold.r, C.gold.g, C.gold.b)
            t:SetJustifyH("LEFT")
            return t
        end)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 4, -(y + 6))
        fs:SetText(extra and (text .. "  |cff" .. string.format("%02x%02x%02x", C.label.r * 255, C.label.g * 255,
            C.label.b * 255) .. extra .. "|r") or text)
        y = y + HEAD_H
        return fs
    end

    local function line(text)
        local fs = acquire("line", function()
            local t = UI:CreateText(content, "", 11, C.label.r, C.label.g, C.label.b)
            t:SetJustifyH("LEFT")
            return t
        end)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 8, -(y + 2))
        fs:SetWidth(math.max(10, width - 16))
        fs:SetText(text)
        y = y + math.max(16, fs:GetStringHeight() or 16) + 6
    end

    local function smallButton(parentFrame, variant)
        local b = UI:CreateButton(parentFrame, "", 60, 20)
        if variant then UI:SetButtonVariant(b, variant) end
        return b
    end

    -- Lay buttons out from a frame's right edge inwards; returns the width they took.
    local function rightAlign(frame, buttons, top)
        local x = -6
        for _, b in ipairs(buttons) do
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, top)
            x = x - b:GetWidth() - 4
        end
        return -x
    end

    local function panelFrame()
        local f = CreateFrame("Frame", nil, content, "BackdropTemplate")
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
        f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
        return f
    end

    ------------------------------------------------------------------
    -- Active: my group and its queue, the groups being formed, who is looking
    ------------------------------------------------------------------
    local function metaOf(g, now, leader)
        local parts = {}
        if leader then parts[#parts + 1] = leader end
        parts[#parts + 1] = string.format("%d/%d", g.n or 1, g.max or 5)
        parts[#parts + 1] = string.format(L["open: %s"], G:NeedText(g.need))
        parts[#parts + 1] = string.format(L["%dm"], B:_Remaining(g, now))
        if (g.note or "") ~= "" then parts[#parts + 1] = g.note end
        return table.concat(parts, "  \194\183  ")
    end

    local function myGroupCard(g, now)
        local card = acquire("mine", function()
            local f = panelFrame()
            f.title = UI:CreateText(f, "", 13, C.gold.r, C.gold.g, C.gold.b)
            f.title:SetPoint("TOPLEFT", 10, -8)
            f.meta = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.meta:SetPoint("TOPLEFT", 10, -28)
            f.edit = smallButton(f)
            f.edit.label:SetText(L["Change"])
            f.edit:SetScript("OnClick", function() openComposer(nil, "group") end)
            f.down = smallButton(f, "danger")
            f.down.label:SetText(L["Take down"])
            f.down:SetScript("OnClick", function() G:Disband() end)
            return f
        end)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 4, -y)
        card:SetSize(width - 8, CARD_H)
        card:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1)
        local taken = rightAlign(card, { card.down, card.edit }, -6)
        card.title:SetText(string.format(L["Your group: %s"], B:ActivityName(g.act)))
        oneLine(card.title, width - 8 - 20 - taken)
        card.meta:SetText(metaOf(g, now))
        oneLine(card.meta, width - 8 - 20)
        y = y + CARD_H + GAP
    end

    local function requestRow(r, classByKey)
        local row = acquire("request", function()
            local f = CreateFrame("Frame", nil, content)
            f.name = UI:CreateText(f, "", 11)
            f.name:SetPoint("LEFT", 14, 0)
            f.state = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.invite = smallButton(f)
            f.invite.label:SetText(L["Invite"])
            f.decline = smallButton(f)
            f.decline.label:SetText(L["Decline"])
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, -y)
        row:SetSize(width - 8, ROW_H)
        local ink = roleColor(r.role)
        row.name:SetText(coloured(r.name, classByKey[r.key]) .. "  " ..
            GuildOS:ColorText(B:RoleName(ROLE_OF[r.role]), ink.r, ink.g, ink.b))
        local taken = rightAlign(row, { row.decline, row.invite }, -2)
        row.state:ClearAllPoints()
        row.state:SetPoint("RIGHT", row, "RIGHT", -(taken + 6), 0)
        row.state:SetText(r.state == "invited" and L["invited"] or "")
        oneLine(row.name, width - 8 - 14 - taken - 70)
        local key = r.key
        row.invite:SetScript("OnClick", function() G:Invite(key) end)
        row.decline:SetScript("OnClick", function() G:Decline(key) end)
        y = y + ROW_H
    end

    local function groupCard(g, now, classByKey)
        local card = acquire("group", function()
            local f = panelFrame()
            f.title = UI:CreateText(f, "", 13, C.gold.r, C.gold.g, C.gold.b)
            f.title:SetPoint("TOPLEFT", 10, -8)
            f.meta = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.meta:SetPoint("TOPLEFT", 10, -28)
            f.status = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.whisper = smallButton(f)
            f.whisper.label:SetText(L["Whisper"])
            f.cancel = smallButton(f)
            f.cancel.label:SetText(L["Take it back"])
            f.join = {}
            for _, letter in ipairs(LETTERS) do
                local b = smallButton(f)
                b.label:SetText(B:RoleName(ROLE_OF[letter]))
                local ink = roleColor(letter)
                b.baseLabelColor = { ink.r, ink.g, ink.b }
                UI:_ButtonState(b, "rest")
                f.join[letter] = b
            end
            return f
        end)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 4, -y)
        card:SetSize(width - 8, CARD_H)

        local key, name = g.key, g.name
        local asked = G:Asked(key)
        local buttons = { card.whisper }
        card.whisper:SetScript("OnClick", function() whisper(name) end)
        card.cancel:Hide()
        card.status:SetText("")
        for _, letter in ipairs(LETTERS) do card.join[letter]:Hide() end
        if asked and asked.state == "pending" then
            card.cancel:Show()
            card.cancel:SetScript("OnClick", function() G:CancelRequest(key) end)
            buttons[#buttons + 1] = card.cancel
            card.status:SetText(string.format(L["asked as %s"], B:RoleName(ROLE_OF[asked.role])))
        elseif asked then
            card.status:SetText(L["no spot for you"])
        else
            for i = #LETTERS, 1, -1 do
                local letter = LETTERS[i]
                if (g.need[letter] or 0) > 0 then
                    local b = card.join[letter]
                    b:Show()
                    b:SetScript("OnClick", function() G:RequestSpot(key, letter) end)
                    buttons[#buttons + 1] = b
                end
            end
            card.status:SetText(L["ask for a spot as"])
        end
        local taken = rightAlign(card, buttons, -6)
        card.status:ClearAllPoints()
        card.status:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(taken + 6), -11)
        local statusW = math.ceil(card.status:GetStringWidth() or 0)
        card.title:SetText(B:ActivityName(g.act))
        oneLine(card.title, width - 8 - 20 - taken - statusW - 12)
        card.meta:SetText(metaOf(g, now, coloured(name, classByKey[key])))
        oneLine(card.meta, width - 8 - 20)
        y = y + CARD_H + GAP
    end

    local function seekerRow(e, now, classByKey, mine)
        local row = acquire("seeker", function()
            local f = CreateFrame("Frame", nil, content)
            f.nameBtn = CreateFrame("Button", nil, f)
            f.nameBtn:SetPoint("LEFT", 10, 0)
            f.nameBtn:SetSize(NAME_W, ROW_H - 4)
            f.name = UI:CreateText(f.nameBtn, "", 11)
            f.name:SetPoint("LEFT")
            oneLine(f.name, NAME_W - 6)
            f.roles = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.roles:SetPoint("LEFT", 10 + NAME_W, 0)
            oneLine(f.roles, ROLES_W - 6)
            f.what = UI:CreateText(f, "", 11, C.label.r, C.label.g, C.label.b)
            f.what:SetPoint("LEFT", 10 + NAME_W + ROLES_W, 0)
            f.time = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.invite = smallButton(f)
            f.invite.label:SetText(L["Invite"])
            f.you = UI:CreateText(f, L["(you)"], 10, C.label.r, C.label.g, C.label.b)
            f.rule = UI:CreateSeparator(f)
            f.rule:SetPoint("BOTTOMLEFT", 6, 0)
            f.rule:SetPoint("BOTTOMRIGHT", -6, 0)
            f.rule:SetAlpha(0.4)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, -y)
        row:SetSize(width - 8, ROW_H)
        local isMe = e.key ~= nil and e.key == mine
        local name = e.name
        row.name:SetText(coloured(name, e.key and classByKey[e.key]))
        row.roles:SetText(roleNames(e.roles or ""))
        -- An allied listing carries no key: it is read, not acted on (as the board before #341).
        local allied = e.key == nil
        row.nameBtn:EnableMouse(not isMe and not allied)
        row.nameBtn:SetScript("OnClick", function() whisper(name) end)
        row.invite:SetShown(not isMe and not allied)
        row.you:SetShown(isMe)
        local taken = 6
        if not isMe and not allied then
            taken = rightAlign(row, { row.invite }, -2)
            row.invite:SetScript("OnClick", function() GuildOS.Compat.InviteUnit(name) end)
        elseif isMe then
            row.you:ClearAllPoints()
            row.you:SetPoint("RIGHT", -8, 0)
            taken = math.ceil(row.you:GetStringWidth() or 30) + 12
        end
        row.time:ClearAllPoints()
        row.time:SetPoint("RIGHT", row, "RIGHT", -(taken + 6), 0)
        row.time:SetText(string.format(L["%dm"], B:_Remaining(e, now)))
        local what = e.guild and e.note or B:Describe(e)
        row.what:SetText(what ~= "" and what or L["Anything"])
        oneLine(row.what, width - 8 - 10 - NAME_W - ROLES_W - taken - TIME_W - 10)
        y = y + ROW_H
    end

    local function scopeButton()
        local b = acquire("scope", function()
            local s = smallButton(content)
            s:SetScript("OnClick", function()
                B:SetPref("allianceScope", not B:Pref("allianceScope"))
                paint()
            end)
            return s
        end)
        b.label:SetText(B:Pref("allianceScope") and L["Scope: Alliance"] or L["Scope: Guild"])
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -(y + 2))
    end

    local function paintActive()
        local now = GetServerTime()
        local onlineSet, classByKey = B:_BuildOnlineRoster()
        local mine = B:MyKey()

        local myGroup = G:Mine()
        if myGroup then
            myGroupCard(myGroup, now)
            local requests = G:Requests()
            if #requests == 0 then
                line(L["Nobody asked for a spot yet. Guildmates see your group here and in the tiles."])
            else
                head(L["Asking for a spot"], tostring(#requests))
                for _, r in ipairs(requests) do requestRow(r, classByKey) end
                y = y + GAP
            end
        end

        local groups = {}
        for _, g in ipairs(G:ActiveList(GuildOS.db.lfgGroups, now, onlineSet)) do
            if g.key ~= mine then groups[#groups + 1] = g end
        end
        head(L["Groups being formed"], tostring(#groups))
        if #groups == 0 then
            line(L["No group is being formed right now. Pick an activity to start one."])
        end
        for _, g in ipairs(groups) do groupCard(g, now, classByKey) end

        local seekers = B:ActiveList(GuildOS.db.lfgBoard, now, onlineSet)
        local ally = GuildOS.Alliance
        local inAlliance = ally and ally:Get() ~= nil
        if inAlliance and B:Pref("allianceScope") then
            for _, row in ipairs(B:AllianceList(now)) do seekers[#seekers + 1] = row end
        end
        if inAlliance then scopeButton() end
        head(L["Looking for a group"], tostring(#seekers))
        if #seekers == 0 then
            line(L["Nobody is available right now. Be the first!"])
        end
        for _, e in ipairs(seekers) do seekerRow(e, now, classByKey, mine) end
    end

    ------------------------------------------------------------------
    -- Tiles
    ------------------------------------------------------------------
    local function makeTile()
        local t = CreateFrame("Button", nil, content, "BackdropTemplate")
        t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        t:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
        t.art = t:CreateTexture(nil, "ARTWORK")
        t.art:SetPoint("TOPLEFT", 1, -1)
        t.art:SetPoint("BOTTOMRIGHT", -1, 1)
        t.art:SetTexCoord(0, 1, 0.08, 0.72)
        t.art:SetAlpha(ART_ALPHA)
        t.name = UI:CreateText(t, "", 12, C.gold.r, C.gold.g, C.gold.b)
        t.name:SetPoint("BOTTOMLEFT", 8, 6)
        t.name:SetJustifyH("LEFT")
        t.name:SetJustifyV("BOTTOM")
        t.name:SetWordWrap(true)
        t.level = UI:CreateText(t, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        t.level:SetPoint("TOPRIGHT", -6, -5)
        t.groups = UI:CreateText(t, "", 10, C.ok.r, C.ok.g, C.ok.b)
        t.groups:SetPoint("TOPLEFT", 8, -5)
        t.seekers = UI:CreateText(t, "", 10, C.info.r, C.info.g, C.info.b)
        t:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.title, C.text.r, C.text.g, C.text.b)
            if self.detail then GameTooltip:AddLine(self.detail, 1, 1, 1) end
            GameTooltip:AddLine(L["Click to form a group or list yourself."], C.label.r, C.label.g, C.label.b, true)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
            GameTooltip:Hide()
        end)
        return t
    end

    local function tile(it, x, w, counts, myLevel)
        local t = acquire("tile", makeTile)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, -y)
        t:SetSize(w, TILE_H)
        t:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
        if it.artOk == nil then it.artOk = it.art ~= nil and GuildOS.Compat.TextureExists(it.art) end
        if it.artOk then
            t.art:SetTexture(it.art)
            t.art:Show()
        else
            t.art:Hide()
        end
        local name = B:ActivityName(it.id)
        t.title = name
        t.name:SetWidth(w - 16)
        t.name:SetText(name)
        local range = it.min and (it.min == it.max and tostring(it.min) or (it.min .. "\226\128\147" .. it.max)) or ""
        t.level:SetText(range)
        local details = {}
        if it.min then details[#details + 1] = string.format(L["Level %s"], range) end
        details[#details + 1] = string.format(L["%d players"], it.size)
        t.detail = table.concat(details, "  \194\183  ")
        local c = counts[it.id]
        t.groups:SetText(c and c.groups > 0 and string.format(L["%d forming"], c.groups) or "")
        t.seekers:ClearAllPoints()
        if c and c.groups > 0 then
            t.seekers:SetPoint("LEFT", t.groups, "RIGHT", 8, 0)
        else
            t.seekers:SetPoint("TOPLEFT", 8, -5)
        end
        t.seekers:SetText(c and c.seekers > 0 and string.format(L["%d looking"], c.seekers) or "")
        local mine = not it.min or (myLevel >= it.min and myLevel <= it.max + LEVEL_SLACK)
        t:SetAlpha(mine and 1 or OFF_LEVEL_ALPHA)
        local id = it.id
        t:SetScript("OnClick", function() openComposer(id) end)
    end

    local function paintTiles(cat)
        local now = GetServerTime()
        local onlineSet = B:_BuildOnlineRoster()
        local counts = G:Counts(now, onlineSet)
        local myLevel = UnitLevel("player") or 1
        local cols = math.max(1, math.floor((width - 8 + GAP) / (TILE_MIN_W + GAP)))
        local w = math.floor((width - 8 - GAP * (cols - 1)) / cols)
        for _, s in ipairs(Cat:Sections(cat)) do
            head(s.title)
            for i, it in ipairs(s.items) do
                local col = (i - 1) % cols
                if col == 0 and i > 1 then y = y + TILE_H + GAP end
                tile(it, 4 + col * (w + GAP), w, counts, myLevel)
            end
            y = y + TILE_H + GAP + 4
        end
    end

    ------------------------------------------------------------------
    -- Painting
    ------------------------------------------------------------------
    paint = function()
        if not parent:IsVisible() then return end
        B:Prune()
        G:Prune()
        releaseAll()
        local w = scroll:GetWidth() or 0
        width = w > 1 and w or 400
        content:SetWidth(width)
        y = 0
        if parent.activeSub == "active" then paintActive() else paintTiles(parent.activeSub) end
        content:SetHeight(math.max(1, y + 8))

        local roles = B:Pref("roles") or ""
        for _, letter in ipairs(LETTERS) do myChips[letter]:SetOn(roles:find(letter, 1, true) ~= nil) end
        seekBtn.label:SetText(B:Mine() and L["Stop looking"] or L["I am looking..."])
        groupBtn.label:SetText(G:Mine() and L["My group"] or L["+ Form a group"])
        if composer and composer:IsShown() then composer.Repaint() end
    end

    local function selectSub(key)
        local known = false
        for _, t in ipairs(SUBS) do known = known or t.key == key end
        parent.activeSub = known and key or "active"
        for k, btn in pairs(subTabs) do btn:SetActive(k == parent.activeSub) end
        scroll:SetVerticalScroll(0)
        GuildOS:SafeCall(paint)
    end
    parent.SelectSub = selectSub   -- deep links: /gos avail, Guild > Call to Arms

    for _, t in ipairs(SUBS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabs[t.key] = btn
        subList[#subList + 1] = btn
    end
    UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })

    for _, letter in ipairs(LETTERS) do
        myChips[letter]:SetScript("OnClick", function()
            local roles, out = B:Pref("roles") or "", ""
            for _, k in ipairs(LETTERS) do
                local on = roles:find(k, 1, true) ~= nil
                if k == letter then on = not on end
                if on then out = out .. k end
            end
            B:SetPref("roles", out)
            GuildOS:SafeCall(paint)
        end)
    end
    seekBtn:SetScript("OnClick", function()
        if B:Mine() then B:ClearAvailable() else openComposer(nil, "seek") end
    end)
    groupBtn:SetScript("OnClick", function()
        if G:Mine() then
            openComposer(nil, "group")
        elseif parent.activeSub == "active" then
            -- A group is for something: the tiles are where that is picked.
            selectSub("dungeon")
        else
            openComposer(nil, "group")
        end
    end)

    -- The board's refresh hook: every change the modules make lands here.
    B.uiRefresh = paint

    parent:SetScript("OnShow", function() selectSub(parent.activeSub or "active") end)
    local since = 0
    parent:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < REPAINT_EVERY then return end
        since = 0
        GuildOS:SafeCall(paint)
    end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        actions:SetWidth(math.max(TAB_MIN_W, w - 24))
        UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })
        GuildOS:SafeCall(paint)
    end)
end
