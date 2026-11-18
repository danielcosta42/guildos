----------------------------------------------------------------------
-- Guild OS - Settings (issue #367)
-- Six sub-tabs, as the other hubs have them. Each page is built once and laid
-- out again on a resize; nothing is created when a sub-tab is switched or the
-- window changes size. Members read the guild's rules; officers change them.
-- A change that needs a reload lights one strip at the bottom of the panel.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE8 = "Interface\\Buttons\\WHITE8x8"

local SUBS = {
    { key = "profile",   label = L["Profile"] },
    { key = "interface", label = L["Interface"] },
    { key = "chat",      label = L["Chat and alerts"] },
    { key = "modules",   label = L["Modules"] },
    { key = "rules",     label = L["Guild rules"] },
    { key = "data",      label = L["Data and support"] },
}
-- The categories before #367, so an old deep link or command still lands on the right page.
local OLD_KEYS = { general = "profile", raid = "rules", officer = "rules", about = "data" }

local MAX_W       = 640   -- one column of settings reads best at this width
local TWO_COL_W   = 830   -- the module lists split in two from here (a 900px window: 900 - 2x12 - 24 - 20)
local ROW_GAP     = 8
local SUB_INDENT  = 22    -- a sub-option sits under its parent's label
local NOTE_INDENT = 22    -- a checkbox's explanation starts where its label does
local LABEL_W     = 260   -- a field's label column, so the boxes line up; narrower on a narrow page
local TAB_H, TAB_MIN, TAB_PAD = 28, 60, 20
local STRIP_H     = 34

-- Tabs have no description of their own in the registry; the Modules page says what each holds.
local TAB_DESC = {
    raids        = L["Sessions, raiders, cores and audit"],
    loot         = L["The loot rule, accounts, lists and history"],
    dkp          = L["Points accounts, in Loot"],
    wishlist     = L["The guild's wishlists, in Loot"],
    recipes      = L["Who in the guild crafts what"],
    guild        = L["Calendar, activity, bulletin and polls"],
    groups       = L["Groups being formed and who is looking"],
    journal      = L["The guild's journal"],
    achievements = L["What the guild has earned"],
    alliance     = L["Pacts with other guilds"],
    recruitment  = L["Recruiting, the scanner and auto-invite"],
    trials       = L["Trial members and their progress"],
    management   = L["Ranks, inactivity, bans and the audit log"],
    web          = L["Publishing to guildos.me"],
}

----------------------------------------------------------------------
-- What waits for a reload. A setting switched back to how it loaded is no
-- longer waiting, so the strip counts real changes only.
----------------------------------------------------------------------
local boot            -- the font and module states at the first build
local pending = {}
local strip           -- the panel's reload strip, once built

local function updateStrip()
    if not strip then return end
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    strip.text:SetText(n == 1 and L["1 change applies after you reload the interface."]
        or string.format(L["%d changes apply after you reload the interface."], n))
    strip:SetShown(n > 0)
    if strip.onToggle then strip.onToggle(n > 0) end
end

local function markReload(key, waiting)
    pending[key] = waiting and true or nil
    updateStrip()
end

----------------------------------------------------------------------
-- A page: rows top to bottom, re-anchored by Layout. A row is an object and
-- how to size it: a fixed height, a measured FontString, or a place function
-- that arranges what it holds for the width and returns its height.
----------------------------------------------------------------------
local Form = {}
Form.__index = Form

local function newForm(content)
    return setmetatable({ content = content, rows = {}, syncs = {} }, Form)
end

local function num(v, fallback)
    return type(v) == "number" and v or fallback
end

-- The label column on a page `w` wide: LABEL_W, or 40% of a narrow page, so the control still fits.
local function labelColumn(w, want)
    return math.min(want or LABEL_W, math.floor(w * 0.4))
end

local function textHeight(fs)
    local h = num(fs.GetStringHeight and fs:GetStringHeight(), 0)
    return h > 0 and math.ceil(h) or 14
end

function Form:Row(obj, opts)
    opts = opts or {}
    self.rows[#self.rows + 1] = { obj = obj, gap = opts.gap or ROW_GAP, indent = opts.indent or 0,
        h = opts.h, wide = opts.wide, shown = opts.shown, place = opts.place }
    return obj
end

-- `fn` re-reads one control's value; Refresh runs them all, then lays the page out again.
function Form:Sync(fn)
    self.syncs[#self.syncs + 1] = fn
end

function Form:Refresh()
    for _, fn in ipairs(self.syncs) do GuildOS:SafeCall(fn) end
    return self:Layout()
end

function Form:Layout(width)
    width = num(width, 0)
    if width < 1 then width = num(self.content:GetWidth(), 0) end
    if width < 1 then width = self.width or MAX_W end
    self.width = width
    local page = math.min(width, MAX_W)
    local y, first = 0, true
    for _, r in ipairs(self.rows) do
        local on = not r.shown or r.shown() and true or false
        r.obj:SetShown(on)
        if on then
            if not first then y = y + r.gap end
            first = false
            r.obj:ClearAllPoints()
            r.obj:SetPoint("TOPLEFT", self.content, "TOPLEFT", r.indent, -y)
            if r.wide then r.obj:SetWidth(math.max(1, page - r.indent)) end
            y = y + (r.place and r.place(r.obj, page - r.indent, width - r.indent) or r.h or textHeight(r.obj))
        end
    end
    self.content:SetHeight(math.max(1, y))
    return y
end

-- A section: a 1px rule (none above the first) and its title in Sans SemiBold 14.
function Form:Section(title, shown)
    if #self.rows > 0 then
        self:Row(UI:CreateSeparator(self.content), { gap = 20, wide = true, h = 1, shown = shown })
    end
    local fs = self.content:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, nil, "sectionTitle")
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(C.text.r, C.text.g, C.text.b)
    fs:SetJustifyH("LEFT")
    fs:SetText(title)
    return self:Row(fs, { gap = 12, wide = true, shown = shown })
end

-- A paragraph in Sans 11, textSoft, wrapped to the page.
function Form:Note(text, opts)
    opts = opts or {}
    local fs = UI:CreateText(self.content, text, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return self:Row(fs, { gap = opts.gap or 2, indent = opts.indent, wide = true, shown = opts.shown })
end

-- A checkbox, its explanation under the label. `set` gets true or false; the page re-syncs after it,
-- so a sub-option greys out with its parent. opts: indent, enabled (a function), shown.
function Form:Check(label, desc, get, set, opts)
    opts = opts or {}
    local indent = opts.indent or 0
    local f = UI:CreateCheckbox(self.content, label, 18)
    if f.label then   -- the label ends at the page's edge rather than running past it
        f.label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.label:SetJustifyH("LEFT")
        f.label:SetWordWrap(false)
    end
    local cb = f.checkbox
    cb.onChanged = function(_, checked)
        set(checked and true or false)
        self:Refresh()
    end
    self:Sync(function()
        cb:SetChecked(get() and true or false)
        if opts.enabled then
            if opts.enabled() then cb:Enable() else cb:Disable() end
        end
    end)
    self:Row(f, { gap = opts.gap, indent = indent, h = 18, wide = true, shown = opts.shown })
    if desc then self:Note(desc, { indent = indent + NOTE_INDENT, shown = opts.shown }) end
    return f
end

-- Buttons side by side, wrapping when the page is narrow. Each spec is { label, onClick, w = width,
-- variant = "danger" }. Returns the buttons.
function Form:Buttons(list, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetSize(1, 26)
    local btns = {}
    for _, spec in ipairs(list) do
        local b = UI:CreateButton(holder, spec[1], spec.w or 150, 26)
        if spec.variant then UI:SetButtonVariant(b, spec.variant) end
        b:SetScript("OnClick", spec[2])
        btns[#btns + 1] = b
    end
    holder.buttons = btns
    self:Row(holder, { gap = opts.gap, indent = opts.indent, wide = true, shown = opts.shown,
        place = function(_, w)
            local x, y = 0, 0
            for _, b in ipairs(btns) do
                local bw = num(b:GetWidth(), 150)
                if x > 0 and x + bw > w then x, y = 0, y + 32 end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
                x = x + bw + 8
            end
            holder:SetHeight(y + 26)
            return y + 26
        end })
    return btns
end

-- One test or tool: its button, and what it does beside it on one line.
function Form:Action(label, desc, onClick)
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetSize(1, 26)
    local b = UI:CreateButton(holder, label, 200, 26)
    b:SetPoint("LEFT", 0, 0)
    b:SetScript("OnClick", onClick)
    local d = UI:CreateText(holder, desc, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    d:SetPoint("LEFT", b, "RIGHT", 10, 0)
    d:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    d:SetJustifyH("LEFT")
    d:SetWordWrap(false)
    self:Row(holder, { h = 26, wide = true })
    return b
end

-- A box with a label before it and a Save button after it (UI:AttachSaveButton). The border turns gold
-- while it has the keyboard. opts: w, max, numeric, get (fills it), save(box), saveText, hint, indent.
function Form:Field(label, opts)
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetSize(1, 24)
    local lbl = UI:CreateText(holder, label, 12, C.text.r, C.text.g, C.text.b)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    local box = CreateFrame("EditBox", nil, holder, "BackdropTemplate")
    box:SetSize(opts.w or 160, 22)
    box:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = GuildOS.UI:Edge(box) })
    box:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    box:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    box:SetTextInsets(6, 6, 0, 0)
    GuildOS:ApplyFont(box, 12, opts.numeric and "tableNum" or nil)
    box:SetTextColor(C.text.r, C.text.g, C.text.b)
    box:SetMaxLetters(opts.max or 64)
    if opts.numeric then box:SetNumeric(true) end
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1) end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1) end)
    UI:AttachSaveButton(box, opts.save, { text = opts.saveText, parent = holder })
    if opts.hint then
        local hint = UI:CreateText(holder, opts.hint, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        hint:SetPoint("LEFT", box.saveButton, "RIGHT", 8, 0)
        hint:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(false)
    end
    if opts.get then
        self:Sync(function()
            if not box:HasFocus() then box:SetText(tostring(opts.get() or "")) end
        end)
    end
    self:Row(holder, { wide = true, gap = opts.gap, indent = opts.indent, shown = opts.shown,
        place = function(_, w)
            local lw = labelColumn(w, opts.labelW)
            lbl:SetWidth(lw)
            box:ClearAllPoints()
            box:SetPoint("LEFT", holder, "LEFT", lw + 8, 0)
            -- The box gives way before its Save button does.
            local saveW = num(box.saveButton and box.saveButton:GetWidth(), 60)
            box:SetWidth(math.max(40, math.min(opts.w or 160, w - lw - 8 - 6 - saveW)))
            return 24
        end })
    return box
end

-- A rule a member reads: its label, then its value, on one line.
function Form:Value(label, value, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetSize(1, 18)
    local lbl = UI:CreateText(holder, label, 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    local v = UI:CreateText(holder, "", 12, C.text.r, C.text.g, C.text.b)
    if opts.numeric then GuildOS:ApplyFont(v, nil, "tableNum") end
    v:SetJustifyH("LEFT")
    v:SetWordWrap(false)
    self:Sync(function() v:SetText(tostring(value() or "")) end)
    self:Row(holder, { wide = true, gap = opts.gap, indent = opts.indent, shown = opts.shown,
        place = function(_, w)
            local lw = labelColumn(w)
            lbl:SetWidth(lw)
            v:ClearAllPoints()
            v:SetPoint("LEFT", holder, "LEFT", lw + 8, 0)
            v:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
            return 18
        end })
    return v
end

-- Cells in one column, or two from TWO_COL_W; with opts.colW, as many of that width as fit the page.
-- Each cell is a frame made by `make(holder, item)`.
function Form:Grid(make, list, cellH, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetSize(1, cellH)
    local cells = {}
    for _, item in ipairs(list) do cells[#cells + 1] = make(holder, item) end
    self:Row(holder, { gap = opts.gap, shown = opts.shown, place = function(_, w, full)
        local cols, colW
        if opts.colW then
            colW = opts.colW
            cols = math.max(1, math.floor((w + 24) / (colW + 24)))
        else
            cols = (full >= TWO_COL_W and #cells > 1) and 2 or 1
            colW = cols == 2 and math.floor((full - 24) / 2) or w
        end
        for i, c in ipairs(cells) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (colW + 24), -row * (cellH + 8))
            c:SetWidth(colW)
        end
        local h = math.max(1, math.ceil(#cells / cols) * (cellH + 8) - 8)
        holder:SetSize(cols == 2 and full or w, h)
        return h
    end })
    return cells
end

----------------------------------------------------------------------
-- The pages
----------------------------------------------------------------------
local PAGES = {}

PAGES.profile = function(F)
    F:Section(L["Your raid roles"])
    local picker = GuildOS:CreateRolePicker(F.content)
    F:Sync(function() if picker.refresh then picker.refresh() end end)   -- onboarding has a picker too
    F:Row(picker, { h = 24, gap = 10 })
    F:Note(L["Roles you're willing to play. Your guild's Raiders list picks this up automatically, so no officer has to set it."], { gap = 6 })

    F:Section(L["Notices"])
    F:Check(L["Show login digest"], L["What changed in the guild since your last login."],
        function() return not (GuildOS.db.digest and GuildOS.db.digest.enabled == false) end,
        function(checked)
            GuildOS.db.digest = GuildOS.db.digest or {}
            GuildOS.db.digest.enabled = checked
        end)
    F:Buttons({ { L["Show the digest now"], function() if GuildOS.Digest then GuildOS.Digest:Show() end end, w = 170 } },
        { indent = NOTE_INDENT })

    -- WoW: Forever's guild feed on guildos.me (issue #205): the member's own choice.
    if GuildOS.Journal then
        F:Section(L["Privacy"])
        F:Check(L["Don't name me in Discord posts"], L["The guild's Discord posts leave your name out."],
            function() return GuildOS.Journal:IsOptedOut() end,
            function(checked) GuildOS.Journal:SetOptedOut(checked) end)
    end

    F:Section(L["Getting started"])
    F:Buttons({ { L["Show welcome again"], function() if GuildOS.ShowOnboarding then GuildOS:ShowOnboarding() end end, w = 170 } })
    F:Note(L["Replay the first-run intro"], { gap = 6 })
end

PAGES.interface = function(F)
    F:Section(L["Appearance"])
    local scaleRow = CreateFrame("Frame", nil, F.content)
    scaleRow:SetSize(1, 34)
    local scaleLabel = UI:CreateText(scaleRow, L["UI scale"], 12, C.text.r, C.text.g, C.text.b)
    scaleLabel:SetPoint("LEFT", 0, 2)
    local scale = CreateFrame("Slider", "GuildOSScaleSlider", scaleRow, "OptionsSliderTemplate")
    scale:SetMinMaxValues(0.8, 1.2)
    scale:SetValueStep(0.05)
    scale:SetObeyStepOnDrag(true)
    -- The template's three texts, by the names it gives them.
    local function say(suffix, text)
        local fs = _G[(scale:GetName() or "") .. suffix]
        if fs then fs:SetText(text) end
    end
    say("Low", "80%")
    say("High", "120%")
    scale:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value * 20 + 0.5) / 20   -- snap to the 0.05 step
        GuildOS:SetSetting("uiScale", value)
        say("Text", string.format("%d%%", value * 100))
        UI:ApplyScale()
    end)
    F:Sync(function()
        local v = GuildOS:GetSetting("uiScale") or 1
        scale:SetValue(v)
        say("Text", string.format("%d%%", v * 100))
    end)
    F:Row(scaleRow, { wide = true, place = function(_, w)
        local lw = labelColumn(w)
        scale:ClearAllPoints()
        scale:SetPoint("LEFT", scaleRow, "LEFT", lw + 8, 2)
        scale:SetWidth(math.max(100, math.min(200, w - lw - 8 - 40)))
        return 34
    end })

    -- The interface style (issue #122), where the client draws more than one.
    local styleRow = CreateFrame("Frame", nil, F.content)
    local styleH = GuildOS.Style.BuildPicker and GuildOS.Style:BuildPicker(styleRow, 0) or 0
    if styleH > 0 then
        styleRow:SetSize(1, styleH)
        F:Row(styleRow, { h = styleH, gap = 12 })
    else
        styleRow:Hide()
    end

    -- The game's own font instead of GuildOS's (issue #57), for the whole account. A Korean or Chinese
    -- client, and the Forever style, always use it (#103).
    local forced = GuildOS.GameFontOnly or GuildOS.Style.gameFont
    F:Check(L["Use the game's font"],
        forced and L["This client always uses the game's font."]
            or L["Swaps IBM Plex Sans and Mono for the client's own font. Applies after a reload."],
        function() return GuildOSDB.font == "game" or forced end,
        function(checked)
            GuildOSDB.font = checked and "game" or nil
            markReload("font", checked ~= boot.font)
        end,
        { enabled = function() return not forced end, gap = 12 })

    F:Section(L["In the game"])
    F:Check(L["Show minimap button"], nil,
        function() return GuildOS.IsMinimapShown and GuildOS:IsMinimapShown() end,
        function(checked) if GuildOS.SetMinimapShown then GuildOS:SetMinimapShown(checked) end end)
    -- The guildmates-in-your-zone dots under the minimap (#271).
    if GuildOS.GuildMap then
        F:Check(L["Show guildmates in your zone on the minimap"], nil,
            function() return GuildOS.GuildMap:IsMinimapDots() end,
            function(checked) GuildOS.GuildMap:SetMinimapDots(checked) end)
    end
    F:Check(L["Guild button opens Guild OS"], L["Off: the game's guild button opens the game's own guild window."],
        function() return GuildOS:IsGuildButtonHijacked() end,
        function(checked) GuildOS:SetSetting("hijackGuildButton", checked) end)

    -- Guild lines on item tooltips (crafters, wishlist, soft reserves), issue #39. Shift is
    -- remembered while the lines are off, so turning them back on keeps it.
    local shiftPref = GuildOS:GetSetting("itemTooltip") == "shift"
    local function tooltipsOn() return GuildOS:GetSetting("itemTooltip") ~= "off" end
    F:Check(L["Guild info on item tooltips"], L["Who crafts it, who wishes for it and who reserved it."],
        tooltipsOn,
        function(checked)
            GuildOS:SetSetting("itemTooltip", not checked and "off" or (shiftPref and "shift" or "always"))
        end)
    F:Check(L["Only while holding Shift"], nil,
        function() return shiftPref end,
        function(checked)
            shiftPref = checked
            if tooltipsOn() then GuildOS:SetSetting("itemTooltip", checked and "shift" or "always") end
        end,
        { indent = SUB_INDENT, enabled = tooltipsOn })
    -- The guild bank (issue #380): how many the bank holds, on the item's tooltip, and the bar under
    -- the game's bank. Where the client has a guild bank.
    if GuildOS.GuildBank and GuildOS.GuildBank:Available() then
        F:Check(L["Guild bank count on item tooltips"], L["How many the guild bank holds, and what it still needs."],
            function() return GuildOS:GetSetting("gbankTooltip") ~= false end,
            function(checked) GuildOS:SetSetting("gbankTooltip", checked) end,
            { indent = SUB_INDENT, enabled = tooltipsOn })
        F:Check(L["Guild OS bar under the guild bank"], L["Organize the tab you are on, or every tab your rank may, from the bank itself."],
            function() return GuildOS:GetSetting("gbankBar") ~= false end,
            function(checked) GuildOS:SetSetting("gbankBar", checked) end)
    end
end

PAGES.chat = function(F, isOfficer)
    -- Guild and officer chat annotations: a personal display preference (Modules/ChatTweaks.lua).
    local function ct() return GuildOS.db.chatTweaks or {} end
    local function setCt(key)
        return function(checked) if GuildOS.db.chatTweaks then GuildOS.db.chatTweaks[key] = checked end end
    end
    local function annotating() return ct().enabled and true or false end
    F:Section(L["Guild chat"])
    F:Check(L["Annotate guild chat (class icon, level, alt tag)"], nil, annotating, setCt("enabled"))
    F:Check(L["Class icon"], nil, function() return ct().classIcon ~= false end, setCt("classIcon"),
        { indent = SUB_INDENT, enabled = annotating })
    F:Check(L["Level"], nil, function() return ct().level ~= false end, setCt("level"),
        { indent = SUB_INDENT, enabled = annotating })
    F:Check(L["Alt tag"], nil, function() return ct().altTag ~= false end, setCt("altTag"),
        { indent = SUB_INDENT, enabled = annotating })
    -- Guild Roster Manager's tag (#269).
    F:Check(L["Short tag: [M] on a main, [Main] on an alt"], nil, function() return ct().altShort end, setCt("altShort"),
        { indent = 2 * SUB_INDENT, enabled = function() return annotating() and ct().altTag ~= false end })

    -- Mentions (issue #59): what /gos mentions sets. Personal, never synced.
    local mcfg = GuildOS.db.mentions
    if mcfg then
        F:Section(L["Mentions"])
        local function alerting() return mcfg.enabled and true or false end
        local function mention(label, key, officerOnly)
            if officerOnly and not isOfficer then return end
            F:Check(label, nil, function() return mcfg[key] end, function(checked) mcfg[key] = checked end,
                key ~= "enabled" and { indent = SUB_INDENT, enabled = alerting } or nil)
        end
        mention(L["Alert me when my name or a watch-word comes up in chat"], "enabled")
        mention(L["My own name"], "ownName")
        mention(L["Guild chat"], "guild")
        mention(L["Officer chat"], "officer", true)
        mention(L["When somebody calls the officers in guild chat (officers only)"], "officerCall", true)
        mention(L["Play a sound"], "sound")

        F:Field(L["Watch-words:"], { w = 160, max = 40, saveText = L["Add"], hint = L["Click a word to remove it."],
            indent = SUB_INDENT, labelW = 120,
            save = function(box)
                mcfg.watchWords = mcfg.watchWords or {}
                local status = GuildOS.Mentions:_AddWatchWord(mcfg.watchWords, box:GetText())
                if status == "ok" then
                    box:SetText("")
                    F:Refresh()
                elseif status == "short" then
                    GuildOS:Print(L["Watch-words must be at least 3 characters."])
                else
                    GuildOS:Print(L["Already watching: |cffFFFFFF"] .. strtrim(box:GetText()):lower() .. "|r")
                end
            end })

        -- One chip per watch-word, up to WORD_MAX; clicking one removes it.
        local WORD_MAX = 9
        local function words() return mcfg.watchWords or {} end
        local chipRow = CreateFrame("Frame", nil, F.content)
        chipRow:SetSize(1, 20)
        local chips = {}
        for i = 1, WORD_MAX do
            local b = UI:CreateButton(chipRow, "", 130, 20)
            b:SetScript("OnClick", function(self)
                GuildOS.Mentions:_RemoveWatchWord(mcfg.watchWords, self._word)
                F:Refresh()
            end)
            chips[i] = b
        end
        F:Sync(function()
            local list = words()
            for i, b in ipairs(chips) do
                b._word = list[i]
                if list[i] then UI:SetChipText(b, list[i], 130) end
                b:SetShown(list[i] ~= nil)
            end
        end)
        F:Row(chipRow, { indent = SUB_INDENT, gap = 6, shown = function() return #words() > 0 end,
            place = function(_, w)
                local x, y = 0, 0
                for _, b in ipairs(chips) do
                    if b:IsShown() then
                        if x > 0 and x + 130 > w then x, y = 0, y + 24 end
                        b:ClearAllPoints()
                        b:SetPoint("TOPLEFT", chipRow, "TOPLEFT", x, -y)
                        x = x + 136
                    end
                end
                chipRow:SetHeight(y + 20)
                return y + 20
            end })
        local more = F:Note("", { indent = SUB_INDENT, shown = function() return #words() > WORD_MAX end })
        F:Sync(function()
            local n = #words()
            more:SetText(n > WORD_MAX and string.format(L["+%d more (/gos mentions list)"], n - WORD_MAX) or "")
        end)
        F:Buttons({
            { L["Recent mentions"], function() GuildOS.Mentions:PrintLog() end },
            { L["Clear watch-words"], function()
                GuildOS.Dialogs["GUILDOS_CLEAR_WORDS"] = GuildOS.Dialogs["GUILDOS_CLEAR_WORDS"] or {
                    text = L["Clear every watch-word?"], button1 = L["Clear watch-words"], button2 = L["Cancel"],
                    OnAccept = function(self)
                        GuildOS.Mentions:HandleCommand({ "clearwords" })
                        if self and self.data and self.data.after then self.data.after() end
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
                }
                GuildOS:ShowDialog("GUILDOS_CLEAR_WORDS", nil, nil, { after = function() F:Refresh() end })
            end },
        }, { indent = SUB_INDENT })
    end

    if GuildOS.db.lfgPrefs then
        F:Section(L["Groups"])
        F:Check(L["Tell me when a guildmate posts on the LFG board"], nil,
            function() return GuildOS.db.lfgPrefs.notify end,
            function(checked) GuildOS.db.lfgPrefs.notify = checked end)
        F:Check(L["Show a small notice when a guildmate forms a group for my level"], nil,
            function() return GuildOS.db.lfgPrefs.toast ~= false end,
            function(checked) GuildOS.db.lfgPrefs.toast = checked and true or false end)
    end
end

-- One module's cell: its switch, where it lives, what it does, and "reload" when it needs one.
local function moduleCell(F, holder, def)
    local cell = CreateFrame("Frame", nil, holder)
    cell:SetSize(300, 40)
    local label = def.label
    local host = def.opens and UI:GetFeature(def.opens[1])
    if host then label = string.format(L["%s (in %s)"], def.label, host.label) end
    local needsReload = def.restart or (def.module and not def.tab)

    local f = UI:CreateCheckbox(cell, label, 18)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("RIGHT", cell, "RIGHT", needsReload and -76 or 0, 0)
    if f.label then
        f.label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.label:SetJustifyH("LEFT")
        f.label:SetWordWrap(false)
    end
    if needsReload then
        local badge = UI:CreateBadge(cell, L["reload"])
        badge:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, -1)
    end
    local desc = UI:CreateText(cell, TAB_DESC[def.id] or def.desc or "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    desc:SetPoint("TOPLEFT", cell, "TOPLEFT", NOTE_INDENT, -21)
    desc:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)

    if boot.modules[def.id] == nil then boot.modules[def.id] = GuildOS:IsFeatureEnabled(def.id) and true or false end
    f.checkbox.onChanged = function(_, checked)
        checked = checked and true or false
        GuildOS:SetFeatureEnabled(def.id, checked)
        GuildOS:Print(def.label .. (checked and L[" |cff00ff00enabled|r."] or L[" |cffFF4444disabled|r."]))
        if def.id == "lootMaster" and GuildOS.LootMaster and GuildOS.LootMaster.SetEnabled then
            GuildOS.LootMaster:SetEnabled(checked)
        end
        -- Tabs build lazily and toggle live; a background module registers its events at load.
        if needsReload then markReload("module:" .. def.id, checked ~= boot.modules[def.id]) end
    end
    F:Sync(function() f.checkbox:SetChecked(GuildOS:IsFeatureEnabled(def.id)) end)
    return cell
end

PAGES.modules = function(F)
    -- AllFeatures, not VisibleFeatures: a disabled feature keeps its switch, or nothing turns it back
    -- on. `core` ones have none: turning Settings or Roster off would lock the player out.
    local tabs, background = {}, {}
    for _, def in ipairs(UI:AllFeatures(nil)) do
        if not def.core then
            if def.tab or def.opens then tabs[#tabs + 1] = def else background[#background + 1] = def end
        end
    end
    local function cell(holder, def) return moduleCell(F, holder, def) end
    F:Section(L["Window tabs"])
    F:Note(L["Turning one off hides it; nothing is deleted."], { gap = 6 })
    F:Grid(cell, tabs, 40, { gap = 12 })
    if #background > 0 then
        F:Section(L["In the background"])
        F:Note(L["These run without a tab of their own."], { gap = 6 })
        F:Grid(cell, background, 40, { gap = 12 })
    end
end

-- Officers change these for the whole guild; members read what applies.
PAGES.rules = function(F, isOfficer)
    local S = GuildOS.db.settings
    F:Note(isOfficer and L["These apply to the whole guild: a change goes to every member running Guild OS."]
        or L["Only officers change these. This is what applies in your guild now."], { gap = 0 })

    local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    local function rankName(idx)   -- 0-based, as GuildOS stores ranks
        local n = GuildControlGetRankName and GuildControlGetRankName(idx + 1)
        return (n and n ~= "") and n or (L["Rank "] .. idx)
    end

    -- Who is an officer (issue #81): the guild's threshold, rank 0 (the guild master) always in.
    F:Section(L["Who is an officer in Guild OS"])
    if numRanks == 0 then
        F:Note(L["Guild rank info not available. Open the Guild panel first."])
    elseif isOfficer then
        -- Set before the threshold was the guild's, a choice was never stamped, so nobody sends it:
        -- one click shares it as it is. Only a choice, not the default: an officer who never ticked
        -- anything and has not heard the guild's yet would otherwise overwrite it.
        if not S.officerMaxRankAt and (S.officerMaxRank or 1) ~= 1 then
            local share
            share = F:Buttons({ { L["Share these ranks with the guild"], function(self)
                GuildOS:SetOfficerMaxRank(S.officerMaxRank or 1)
                self:Hide()
                F:Refresh()
            end, w = 220 } }, { shown = function() return not S.officerMaxRankAt and share[1]:IsShown() end })
        end
        for i = 0, numRanks - 1 do
            local isGM = i == 0
            F:Check(rankName(i), isGM and L["Always an officer."] or nil,
                function() return i <= (S.officerMaxRank or 1) end,
                function(checked)
                    -- Ticking a rank takes every rank above it; unticking one drops every rank below it.
                    local newMax = checked and math.max(i, S.officerMaxRank or 0) or math.max(0, i - 1)
                    local wasOfficer = GuildOS:IsOfficer()
                    -- No longer an officer (a change from elsewhere, the panel still open): nothing changed.
                    if not GuildOS:SetOfficerMaxRank(newMax) then return end
                    -- Ticking one's own rank off ends one's officer modules, at the next reload.
                    if GuildOS:IsOfficer() ~= wasOfficer then markReload("officer", true) end
                    GuildOS:Print(L["Officer threshold: ranks 0-"] .. newMax .. " (" .. rankName(newMax) .. L[" and above are officers)."])
                end,
                { enabled = function() return not isGM end, gap = 6 })
        end
        F:Note(L["Change takes effect immediately. Reload UI required to reload officer modules."], { gap = 8 })
    else
        F:Value(L["Officers"], function()
            local names = {}
            for i = 0, math.min(S.officerMaxRank or 1, numRanks - 1) do names[#names + 1] = rankName(i) end
            return table.concat(names, ", ")
        end)
    end

    -- Who creates calendar events (issue #283) and of which kinds (#308).
    F:Section(L["Calendar events"])
    local function whoCreates()
        local max = GuildOS:EventMaxRank()
        if max <= (S.officerMaxRank or 1) then return L["Officers"] end
        return string.format(L["Up to %s"], rankName(max))
    end
    if isOfficer then
        local whoRow = CreateFrame("Frame", nil, F.content)
        whoRow:SetSize(1, 24)
        local whoLabel = UI:CreateText(whoRow, L["Who creates events:"], 12, C.text.r, C.text.g, C.text.b)
        whoLabel:SetPoint("LEFT", 0, 0)
        local whoBtn = UI:CreateButton(whoRow, "", 180, 24)
        -- Each click moves one rank further, then back to the officers.
        whoBtn:SetScript("OnClick", function()
            local officers = S.officerMaxRank or 1
            local last = (GuildControlGetNumRanks and GuildControlGetNumRanks() or 10) - 1
            local nextMax = GuildOS:EventMaxRank() + 1
            if nextMax > last then nextMax = officers end
            if GuildOS:SetEventMaxRank(nextMax) then F:Refresh() end
        end)
        F:Sync(function() whoBtn.label:SetText(whoCreates()) end)
        F:Row(whoRow, { wide = true, place = function(_, w)
            local lw = labelColumn(w)
            whoLabel:SetWidth(lw)
            whoBtn:ClearAllPoints()
            whoBtn:SetPoint("LEFT", whoRow, "LEFT", lw + 8, 0)
            return 24
        end })
    else
        F:Value(L["Who creates events:"], whoCreates)
    end
    local Cal = GuildOS.Calendar
    if Cal and Cal.KINDS then
        local function isOpen(k)
            local open = Cal:MemberKinds()
            return open == nil or open[k] == true
        end
        if isOfficer then
            F:Note(L["Event types non-officers may create:"], { gap = 10 })
            local boxes = {}
            local function ticked()
                local list = {}
                for _, b in ipairs(boxes) do
                    if b.checkbox:GetChecked() then list[#list + 1] = b.kind end
                end
                return list
            end
            F:Grid(function(holder, k)
                local kb = UI:CreateCheckbox(holder, Cal:KindLabel(k), 18)
                kb.kind = k
                kb.checkbox.onChanged = function(box)
                    -- No longer an officer (a change from elsewhere, the panel still open): the tick goes back.
                    if not Cal:SetMemberKinds(ticked()) then box:SetChecked(not box:GetChecked()) end
                end
                F:Sync(function() kb.checkbox:SetChecked(isOpen(k)) end)
                boxes[#boxes + 1] = kb
                return kb
            end, Cal.KINDS, 18, { gap = 6, colW = 130 })
            F:Note(L["Officers can always create every type."], { gap = 6 })
        else
            F:Value(L["Event types non-officers may create:"], function()
                local names = {}
                for _, k in ipairs(Cal.KINDS) do
                    if isOpen(k) then names[#names + 1] = Cal:KindLabel(k) end
                end
                return #names > 0 and table.concat(names, ", ") or L["None"]
            end)
        end
    end

    -- The guild's attendance weights (issue #55): what a raid outside any core scores with, and what a
    -- core takes when it set none of its own (Raids > Cores). 0 turns one off.
    local RT = GuildOS.RaidTracker
    if RT then
        F:Section(L["Attendance"])
        F:Note(L["Attendance penalties (base score = 100, 0 turns one off):"], { gap = 0 })
        F:Note(L["For raids outside a core, and for every core that set none of its own."])
        local penalties = {
            { key = "LATE",       label = L["Late (missed first snapshot)"] },
            { key = "LEFT_EARLY", label = L["Left Early (missed last snapshot)"] },
        }
        -- Consumables are checked only where the checker exists (TBC, ADR-0014; issue #184).
        if GuildOS.ConsumableChecker then
            penalties[#penalties + 1] = { key = "NO_CONSUMES", label = L["No Consumables (<50% snapshots)"] }
        end
        local function penalty(key) return RT:GetPenalties("")[key] end
        if isOfficer and GuildOS.CoreManager then
            for i, p in ipairs(penalties) do
                F:Field(p.label, { w = 44, max = 3, numeric = true, gap = i == 1 and 10 or nil,
                    get = function() return penalty(p.key) end,
                    save = function(box)
                        local val = tonumber(box:GetText())
                        if not val then   -- an empty box is a slip, not "off": 0 is typed
                            box:SetText(tostring(penalty(p.key)))
                            return
                        end
                        GuildOS.CoreManager:SetPenalty(p.key, val, "")
                        RT:RebuildAttendanceFromSessions()
                        box:SetText(tostring(penalty(p.key)))
                        GuildOS:Print(L["Attendance penalty saved."])
                    end })
            end
            F:Buttons({ { L["Turn penalties off"], function()
                for _, p in ipairs(penalties) do GuildOS.CoreManager:SetPenalty(p.key, 0, "") end
                RT:RebuildAttendanceFromSessions()
                GuildOS:Print(L["Attendance penalties are off."])
                F:Refresh()
            end, w = 170 } })
            -- The raid group the next session is tagged with; Raids > Cores sets it too.
            F:Field(L["Raid Group:"], { w = 160, max = 64, hint = L["Ex: Core 1, Core 2"], gap = 14,
                get = function() return GuildOS.db.raidTracker and GuildOS.db.raidTracker.currentGroupTag or "" end,
                save = function(box)
                    local name = strtrim(box:GetText())
                    RT:SetGroupTag(name)
                    if name ~= "" then
                        GuildOS:Print(L["Raid group set: "] .. "|cff9966FF" .. name .. "|r")
                    else
                        GuildOS:Print(L["Raid group removed."])
                    end
                end })
        else
            for i, p in ipairs(penalties) do
                F:Value(p.label, function()
                    local v = penalty(p.key)
                    return v > 0 and ("-" .. v) or "0"
                end, { numeric = true, gap = i == 1 and 10 or nil })
            end
        end
    end

    -- WoW: Forever: the item level a 60 needs to be ready without a warning (issue #206).
    if not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail and GuildOS.Readiness then
        F:Section(L["Readiness"])
        if isOfficer then
            F:Field(L["Minimum item level for a level 60:"], { w = 50, max = 3, numeric = true,
                get = function() return GuildOS.Readiness:GetMinIlvl() end,
                save = function(box)
                    GuildOS.Readiness:SetMinIlvl(tonumber(box:GetText()))
                    box:SetText(tostring(GuildOS.Readiness:GetMinIlvl() or ""))
                end })
            F:Note(L["Empty: no minimum. Below it, a 60 still counts, with a warning."])
            -- The founding letter, for after the prompt was put away (issue #208): the GM records, an
            -- officer suggests.
            if GuildOS.Founding and GuildOS:IsFeatureEnabled("founding") then
                F:Buttons({ { GuildOS.Founding:IsGM() and L["Record founding"] or L["Suggest founding date to your GM"],
                    function() GuildOS:ShowFoundingLetter(false) end, w = 240 } }, { gap = 12 })
            end
        else
            F:Value(L["Minimum item level for a level 60:"], function()
                return GuildOS.Readiness:GetMinIlvl() or L["None"]
            end, { numeric = true })
        end
    end

    -- !note (issue #59): members set their public note by typing !note in guild chat, and a client that
    -- can edit notes applies it.
    if isOfficer then
        F:Section(L["The !note command"])
        F:Check(L["Apply !note requests from guild chat on this client"],
            L["Members set their public note by typing !note in guild chat."],
            function() return GuildOS.db.noteCommand and GuildOS.db.noteCommand.enabled end,
            function(checked)
                if GuildOS.db.noteCommand then GuildOS.db.noteCommand.enabled = checked end
            end)
    end
end

PAGES.data = function(F, isOfficer)
    F:Section(L["Your data"])
    F:Buttons({
        { L["Backup"], function() if GuildOS.Backup then GuildOS.Backup:ShowExport() end end, w = 120 },
        { L["Restore"], function() if GuildOS.Backup then GuildOS.Backup:ShowRestore() end end, w = 120 },
        { L["Export Data"], function() if GuildOS.ShowExportChooser then GuildOS:ShowExportChooser() end end, w = 140 },
    })
    F:Note(L["Export/import all Guild OS data for this guild"], { gap = 6 })

    -- What /gos scan, errors, selftest, probe, probe chat and style preview do (#142).
    F:Section(L["Diagnostics"])
    F:Buttons({
        { L["Collect my data"], function() GuildOS:CollectMyDataNow() end },
        { L["View Errors"], function() GuildOS:ShowErrors() end },
        { L["Self-test"], function() if GuildOS.SelfTest then GuildOS.SelfTest:Run() end end },
        { L["Probe the client"], function() if GuildOS.Probe then GuildOS.Probe:Run() end end },
        { L["Probe chat"], function()
            -- It posts two lines in guild chat: asked first.
            GuildOS.Dialogs["GUILDOS_PROBE_CHAT"] = GuildOS.Dialogs["GUILDOS_PROBE_CHAT"] or {
                text = L["Post two test lines in guild chat?"],
                button1 = L["Probe chat"], button2 = L["Cancel"],
                OnAccept = function() if GuildOS.Probe then GuildOS.Probe:RunChat() end end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
            GuildOS:ShowDialog("GUILDOS_PROBE_CHAT")
        end },
        { L["Style preview"], function() if GuildOS.Style then GuildOS.Style:ShowPreview() end end },
    })
    F:Note(L["The results go to the chat window."], { gap = 6 })
    F:Check(L["Debug logging"], L["Until the next reload."],
        function() return GuildOS.Logger and GuildOS.Logger.debug end,
        function(checked)
            if GuildOS.Logger then GuildOS.Logger.debug = checked end
        end, { gap = 12 })

    if isOfficer then
        F:Section(L["Test functions"])
        F:Note(L["Simulate features to preview how they work. No data is sent to raid or guild chat."], { gap = 6 })
        -- Consumable Check: TBC content, only where the checker exists (ADR-0014).
        if GuildOS.ConsumableChecker then
            F:Action(L["Test Consumable Check"], L["Scans your current raid for missing consumables"], function()
                local results = GuildOS.ConsumableChecker:CheckRaid()
                if results then
                    local missing = GuildOS.ConsumableChecker:GetMissingCount(results)
                    GuildOS:Print(L["Consumable Check Test: "] .. missing .. L[" players missing buffs."])
                    GuildOS:Print(L["Use |cffFFD700/guildos consreport|r to see details in raid chat."])
                else
                    GuildOS:Print(L["Consumable check returned no results (not in a raid?)."])
                end
            end)
        end
        -- The Loot Master's tests: only where it exists, never on retail (ADR-0026).
        local LM = GuildOS.LootMaster
        if LM then
            F:Action(L["Test Roll Popup"], L["Shows the raider roll popup with a sample item"], function()
                LM.testMode = true
                LM:ShowRollPopup("|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r", 15, 32837)
                GuildOS:Print(L["Test roll popup shown (15s timer). Try MS/OS/Pass buttons."])
            end)
            F:Action(L["Test Wishlist Council"], L["Shows the ML council result frame with sample data"], function()
                LM.testMode = true
                local link = "|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r"
                local fakeWinner = { name = GuildOS.Compat.PlayerName(), class = select(2, UnitClass("player")), wishlistType = "wishlist", order = 1 }
                local fakeCandidates = {
                    fakeWinner,
                    { name = "TestPlayer", class = "WARRIOR", wishlistType = "wishlist", order = 2 },
                    { name = "AnotherOne", class = "MAGE", wishlistType = "wishlist", order = 3 },
                }
                LM.activeLoot = { link = link, slot = nil, itemId = 32837 }
                LM:ShowCouncilResultFrame(fakeWinner, link, nil, fakeCandidates)
                GuildOS:Print(L["Test council frame shown. Award button won't work (no loot slot)."])
            end)
            F:Action(L["Test Roll Tracker"], L["Shows the ML roll tracker with sample roll data"], function()
                LM.testMode = true
                LM.activeLoot = {
                    link = "|cffa335ee|Hitem:30110::::::::70:::::|h[Tsunami Talisman]|h|r",
                    slot = nil, itemId = 30110, startTime = GetServerTime(), endTime = GetServerTime() + 30,
                }
                LM.rolls = {
                    ["TestWarrior-Realm"] = { name = "TestWarrior", class = "WARRIOR", rollType = "MS", roll = 87, prioOrder = 1 },
                    ["TestMage-Realm"] = { name = "TestMage", class = "MAGE", rollType = "MS", roll = 54, wishlist = { order = 2 } },
                    ["TestPriest-Realm"] = { name = "TestPriest", class = "PRIEST", rollType = "OS", roll = 92 },
                    ["TestRogue-Realm"] = { name = "TestRogue", class = "ROGUE", rollType = "PASS", roll = 0 },
                }
                LM:ShowRollFrame()
                GuildOS:Print(L["Test roll tracker shown with sample rolls."])
            end)
            F:Action(L["Test Loot Frame"], L["Opens the ML loot frame with sample items"], function()
                LM.testMode = true
                LM:ShowLootFrame({
                    { slot = 1, link = "|cffa335ee|Hitem:30110::::::::70:::::|h[Tsunami Talisman]|h|r",   name = "Tsunami Talisman",    quality = 4 },
                    { slot = 2, link = "|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r", name = "Warglaive of Azzinoth", quality = 5 },
                    { slot = 3, link = "|cffa335ee|Hitem:30019::::::::70:::::|h[Ring of Endless Coils]|h|r", name = "Ring of Endless Coils", quality = 4 },
                })
                GuildOS:Print(L["Test loot frame shown with 3 sample items."])
            end)
        end
        F:Action(L["Test Raid Status"], L["Shows current raid tracking status and session count"], function()
            local RT = GuildOS.RaidTracker
            if not RT then return GuildOS:Print(L["|cffFF4444Raid Tracker module is disabled.|r"]) end
            GuildOS:Print(string.format(L["Raid Tracker: %d sessions recorded. Currently %s."], RT:GetTotalSessions(),
                RT.trackingActive and "|cff00ff00" .. L["tracking"] .. "|r" or "|cffFF4444" .. L["not tracking"] .. "|r"))
            if RT.currentRaid then GuildOS:Print(L["Active raid: "] .. (RT.currentRaid.name or L["Unknown"])) end
        end)
        F:Action(L["Test Attendance Export"], L["Opens the attendance export window"], function()
            local RT = GuildOS.RaidTracker
            if not RT then return GuildOS:Print(L["|cffFF4444Raid Tracker module is disabled.|r"]) end
            local json, err = RT:ExportForTMB()
            if json then
                GuildOS:ShowExportPopup(L["Attendance Export"], json)
            else
                GuildOS:Print(L["|cffFF4444Export failed:|r "] .. (err or L["No attendance data"]))
            end
        end)
    end

    F:Section(L["About"])
    local ver = UI:CreateText(F.content, "Guild OS v" .. (GuildOS.VERSION or "?"), 12, C.text.r, C.text.g, C.text.b)
    F:Row(ver, { h = 16 })
    F:Note(L["Made with care by "] .. "Chehul")
    -- Retail has no attunements (ADR-0026, issue #177); its wishlist came with issue #185.
    F:Note(GuildOS.Client.isRetail
        and L["Guild OS syncs your gear, professions, spec and wishlist with guildmates running the addon. Officer notes and trials stay officer-only."]
        or L["Guild OS syncs your gear, professions, attunements, spec and wishlist with guildmates running the addon. Officer notes and trials stay officer-only."],
        { gap = 8 })
    F:Note(L["Type /gos help to see every command."], { gap = 8 })
    F:Buttons({ { L["Links"], function()
        GuildOS:ShowExportPopup(L["Guild OS Links"],
            -- The site first: it is the one link here that does something for the person reading it.
            "App:  https://guildos.me\n"
            .. "GitHub:  https://github.com/danielcosta42/GuildOS\n"
            .. "CurseForge:  https://www.curseforge.com/projects/1549177\n"
            .. "Wago:  https://addons.wago.io/addons/rNkyABKa")
    end, w = 120 } }, { gap = 10 })
    F:Note(L["Project page, bug reports and updates"], { gap = 6 })

    -- /gos reset, behind a confirmation: it cannot be undone. Last, and red.
    F:Section(L["Danger zone"])
    F:Buttons({ { L["Erase guild data"], function()
        GuildOS.Dialogs["GUILDOS_ERASE_GUILD"] = GuildOS.Dialogs["GUILDOS_ERASE_GUILD"] or {
            text = L["Erase all Guild OS data for this guild and reload the interface? This cannot be undone."],
            button1 = L["Erase guild data"], button2 = L["Cancel"],
            OnAccept = function() GuildOS:EraseGuildData() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        GuildOS:ShowDialog("GUILDOS_ERASE_GUILD")
    end, w = 170, variant = "danger" } })
    F:Note(L["Removes every Guild OS record of this guild on this PC, then reloads."], { gap = 6 })
end

----------------------------------------------------------------------
-- Building a page into a frame. A page is rebuilt only when what it shows
-- changed shape (rank, the guild's ranks, a module's data appearing); the
-- values are re-read on every refresh.
----------------------------------------------------------------------
local function shapeOf(key, isOfficer)
    local parts = { key, isOfficer and "officer" or "member" }
    if key == "rules" and GuildControlGetNumRanks then
        for i = 1, GuildControlGetNumRanks() or 0 do   -- a rank renamed is a new shape too
            parts[#parts + 1] = tostring(GuildControlGetRankName and GuildControlGetRankName(i) or i)
        end
    elseif key == "modules" then
        for _, def in ipairs(UI:AllFeatures(nil)) do parts[#parts + 1] = def.id end
    elseif key == "chat" then
        parts[#parts + 1] = (GuildOS.db.mentions and "mentions" or "") .. (GuildOS.db.lfgPrefs and "lfg" or "")
    end
    return table.concat(parts, ":")
end

function GuildOS:RefreshSettingsPanel(content, key)
    key = OLD_KEYS[key] or key
    if not PAGES[key] then key = "profile" end
    boot = boot or { font = GuildOSDB and GuildOSDB.font == "game", modules = {} }
    local isOfficer = GuildOS:IsOfficer()
    local shape = shapeOf(key, isOfficer)
    local F = content.__settingsForm
    if not F or content.__settingsShape ~= shape then
        if F then
            for _, child in pairs({ content:GetChildren() }) do child:Hide() end
            for _, region in pairs({ content:GetRegions() }) do region:Hide() end
        end
        F = newForm(content)
        PAGES[key](F, isOfficer)
        content.__settingsForm, content.__settingsShape = F, shape
    end
    F:Refresh()
    return F
end

function GuildOS:CreateSettingsPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = parent.activeSub or "profile"

    -- Anchored on the left only: UI:FlowBar reads GetWidth to wrap (as the Guild hub).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)

    strip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    strip:SetPoint("BOTTOMLEFT", 10, 8)
    strip:SetPoint("BOTTOMRIGHT", -12, 8)
    strip:SetHeight(STRIP_H)
    strip:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = GuildOS.UI:Edge(strip) })
    strip:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
    strip:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    strip.text = UI:CreateText(strip, "", 12, C.text.r, C.text.g, C.text.b)
    strip.text:SetPoint("LEFT", 12, 0)
    local reload = UI:SetButtonVariant(UI:CreateButton(strip, L["Reload"], 120, 24), "primary")
    reload:SetPoint("RIGHT", -5, 0)
    reload:SetScript("OnClick", function() ReloadUI() end)
    strip.text:SetPoint("RIGHT", reload, "LEFT", -12, 0)
    strip.text:SetJustifyH("LEFT")
    strip:Hide()

    local tabs, tabList = {}, {}
    local function anchorScroll(info, stripShown)
        info.scroll:ClearAllPoints()
        info.scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -10)
        info.scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, stripShown and (STRIP_H + 16) or 10)
    end
    strip.onToggle = function(shown)
        for _, info in pairs(parent.subPanels) do anchorScroll(info, shown) end
    end

    local function selectSub(key)
        key = OLD_KEYS[key] or key
        if not parent.subPanels[key] then key = "profile" end
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.scroll:SetShown(k == key) end
        for k, t in pairs(tabs) do t:SetActive(k == key) end
        local info = parent.subPanels[key]
        GuildOS:SafeCall(function()
            info.form = GuildOS:RefreshSettingsPanel(info.content, key)
        end)
    end
    parent.SelectSub = selectSub   -- deep links: /gos open settings <page>

    for _, s in ipairs(SUBS) do
        local t = UI:CreateTab(bar, s.label, TAB_MIN, true)
        t:SetWidth(math.max(TAB_MIN, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
        t:SetScript("OnClick", function() selectSub(s.key) end)
        tabs[s.key] = t
        tabList[#tabList + 1] = t
        local scroll, content = UI:CreateScrollFrame(parent, "GuildOSSettings_" .. s.key)
        local info = { scroll = scroll, content = content }
        anchorScroll(info, false)
        UI:BindScrollChildWidth(scroll, content, 20)
        scroll:Hide()
        parent.subPanels[s.key] = info
    end
    UI:FlowBar(bar, tabList, { gap = 4, rowGap = 4, rowH = TAB_H })

    parent:SetScript("OnShow", function() selectSub(parent.activeSub) end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN, w - 20))
        UI:FlowBar(bar, tabList, { gap = 4, rowGap = 4, rowH = TAB_H })
        local info = parent.subPanels[parent.activeSub]
        if info and info.form then info.form:Layout(info.content:GetWidth()) end
    end)
    updateStrip()
end
