----------------------------------------------------------------------
-- Guild OS - Settings (issue #367)
-- Six sub-tabs, as the other hubs have them. Each page is built once and laid
-- out again on a resize; nothing is created when a sub-tab is switched or the
-- window changes size. Members read the guild's rules; officers change them.
-- A change that needs a reload lights one strip at the bottom of the panel.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
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

local SUBS = {
    { key = "profile",   label = L["Profile"] },
    { key = "interface", label = L["Interface"] },
    { key = "chat",      label = L["Chat and alerts"] },
    { key = "modules",   label = L["Modules"] },
    { key = "rules",     label = L["Guild rules"] },
    { key = "data",      label = L["Data and support"] },
    { key = "credits",   label = L["Credits"] },
}
-- The categories before #367, so an old deep link or command still lands on the right page.
local OLD_KEYS = { general = "profile", raid = "rules", officer = "rules", about = "data" }

local TWO_CARDS_W = 900   -- a page lays its cards in two columns from here (#449), one below
local GRID_TWO_W  = 560   -- a card's own grid (the module lists) splits in two from this inner width
local ROW_GAP     = 8
local SUB_INDENT  = 22    -- a sub-option sits under its parent's label
local NOTE_INDENT = 22    -- a checkbox's explanation starts where its label does
local LABEL_W     = 260   -- a field's label column, so the boxes line up; narrower on a narrow page
local TAB_H, TAB_MIN, TAB_PAD = 28, 60, 20
local STRIP_H     = 34
local CARD_PAD, CARD_TOP, CARD_GAP = 14, 36, 12   -- a section's card: its padding, its title's band, between two

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
    alliance     = L["The shared /g and the alliance room with allied guilds"],
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
        h = opts.h, wide = opts.wide, shown = opts.shown, place = opts.place, card = opts.card, span = opts.span }
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

-- The page (#449, the mockup's config screens): what comes before the first section sits on the wood across
-- the page; each section is a parchment card, its rows laid inside the card's own width (CARD_PAD in, under
-- its title) and anchored to the card, so a row never runs past it. From TWO_CARDS_W the cards go in two
-- columns, each to the shorter one (masonry, in order); a card made with `span` (a module grid) takes the
-- whole width under both. Below TWO_CARDS_W one column, the cards as wide as the page. Records each card's
-- place and each row's box in self.placed, for the tests.
function Form:Layout(width)
    width = num(width, 0)
    if width < 1 then width = num(UI.LaidWidth and UI:LaidWidth(self.content), 0) end
    if width < 1 then width = self.width or 640 end
    self.width = width
    local two = width >= TWO_CARDS_W
    local colW = two and math.floor((width - CARD_GAP) / 2) or width
    self.placed = {}

    -- Blocks: the rows on the wood before any section, then a section with its rows.
    local pre, blocks, cur = {}, {}, nil
    for _, r in ipairs(self.rows) do
        if r.card then cur = { card = r, rows = {} }; blocks[#blocks + 1] = cur
        elseif cur then cur.rows[#cur.rows + 1] = r
        else pre[#pre + 1] = r end
    end

    local y, first = 0, true
    for _, r in ipairs(pre) do
        local on = not r.shown or r.shown() and true or false
        r.obj:SetShown(on)
        if on then
            if not first then y = y + r.gap end
            first = false
            r.obj:ClearAllPoints()
            r.obj:SetPoint("TOPLEFT", self.content, "TOPLEFT", r.indent, -y)
            if r.wide then r.obj:SetWidth(math.max(1, width - r.indent)) end
            y = y + (r.place and r.place(r.obj, width - r.indent, width - r.indent) or r.h or textHeight(r.obj))
        end
    end
    if y > 0 then y = y + CARD_GAP end

    local colY = { y, y }
    for _, b in ipairs(blocks) do
        local card = b.card.obj
        local on = not b.card.shown or b.card.shown() and true or false
        card:SetShown(on)
        if not on then
            for _, r in ipairs(b.rows) do r.obj:SetShown(false) end
        else
            local span = b.card.span or not two
            local cw = span and width or colW
            local inner = cw - 2 * CARD_PAD
            card:SetWidth(math.max(1, cw))
            local yy, firstRow = CARD_TOP, true
            for _, r in ipairs(b.rows) do
                local ron = not r.shown or r.shown() and true or false
                r.obj:SetShown(ron)
                if ron then
                    if not firstRow then yy = yy + r.gap end
                    firstRow = false
                    local w = inner - r.indent
                    r.obj:ClearAllPoints()
                    r.obj:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + r.indent, -yy)
                    if r.wide then r.obj:SetWidth(math.max(1, w)) end
                    local h = r.place and r.place(r.obj, w, w) or r.h or textHeight(r.obj)
                    self.placed[#self.placed + 1] = { card = card, row = r.obj, x = CARD_PAD + r.indent, w = w, cardW = cw }
                    yy = yy + h
                end
            end
            local ch = yy + CARD_PAD
            card:SetHeight(math.max(1, ch))
            card:ClearAllPoints()
            local x, top
            if span then
                top = math.max(colY[1], colY[2])
                x = 0
                colY[1], colY[2] = top + ch + CARD_GAP, top + ch + CARD_GAP
            else
                local c = (colY[2] < colY[1]) and 2 or 1
                top, x = colY[c], (c - 1) * (colW + CARD_GAP)
                colY[c] = top + ch + CARD_GAP
            end
            card:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -top)
        end
    end
    local h = math.max(colY[1], colY[2])
    if #blocks > 0 then h = h - CARD_GAP end
    self.content:SetHeight(math.max(1, h))
    return h
end

-- A section: a parchment card titled `title` (Cinzel, the paper's dark red, never upper case), behind the rows
-- that follow it up to the next section. Under the page's other parts, so their text draws over it.
-- opts.span: the card takes the page's whole width (a grid of its own), under both columns.
function Form:Section(title, shown, opts)
    local card = UI:CreateCard(self.content, title)
    card:SetFrameLevel(math.max(0, (self.content:GetFrameLevel() or 1) - 1))
    card:SetHeight(CARD_TOP)
    self.hasCard = true
    return self:Row(card, { card = true, shown = shown, span = opts and opts.span })
end

-- A paragraph in Sans 11, textSoft, wrapped to the page.
function Form:Note(text, opts)
    opts = opts or {}
    -- Before the page's first card it is on the wood: the wood's soft ink there.
    local ink = self.hasCard and C.textSoft or WOOD.textSoft
    local fs = UI:CreateText(self.content, text, 11, ink.r, ink.g, ink.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return self:Row(fs, { gap = opts.gap or 2, indent = opts.indent, wide = true, shown = opts.shown })
end

-- A checkbox, its explanation under the label. `set` gets true or false; the page re-syncs after it,
-- so a sub-option greys out with its parent. opts: indent, enabled (a function), shown.
function Form:Check(label, desc, get, set, opts)
    opts = opts or {}
    local indent = opts.indent or 0
    local f = checkbox(self.content, label, 18)
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
    rule(box)
    -- The paper's light field and its tan line (the mockup's `.field input` on a card).
    box:SetBackdropColor(C.paperLight.r, C.paperLight.g, C.paperLight.b, 1)
    box:SetBackdropBorderColor(C.paperEdge.r, C.paperEdge.g, C.paperEdge.b, 1)
    box:SetTextInsets(6, 6, 0, 0)
    GuildOS:ApplyFont(box, 12, opts.numeric and "tableNum" or nil)
    box:SetTextColor(C.text.r, C.text.g, C.text.b)
    box:SetMaxLetters(opts.max or 64)
    if opts.numeric then box:SetNumeric(true) end
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(WOOD.paperTitle.r, WOOD.paperTitle.g, WOOD.paperTitle.b, 1) end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C.paperEdge.r, C.paperEdge.g, C.paperEdge.b, 1) end)
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
            cols = (full >= GRID_TWO_W and #cells > 1) and 2 or 1
            colW = cols == 2 and math.floor((full - 24) / 2) or w
        end
        for i, c in ipairs(cells) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (colW + 24), -row * (cellH + 8))
            c:SetWidth(colW)
            if c.Relayout then c:Relayout(colW) end
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

    -- WoW: Forever's guild feed on guildos.me (issue #205), and the live guild map (#449): the member's own choice.
    if GuildOS.Journal or GuildOS.GuildMap then F:Section(L["Privacy"]) end
    if GuildOS.Journal then
        F:Check(L["Don't name me in Discord posts"], L["The guild's Discord posts leave your name out."],
            function() return GuildOS.Journal:IsOptedOut() end,
            function(checked) GuildOS.Journal:SetOptedOut(checked) end)
    end
    if GuildOS.GuildMap then
        F:Check(L["Share my position with the guild"],
            L["Only while a guildmate has the guild map open; never coordinates in an instance, nothing in combat there."],
            function() return GuildOS.GuildMap:IsSharing() end,
            function(checked) GuildOS.GuildMap:SetSharing(checked) end)
    end
    -- The campfire beacon (ChehulNet v17, Modules/ChehulNetWire.lua): WoW: Forever only, where the camp kits are. On
    -- unless turned off ("default" counts as on); the realm bus carries an ownerless sighting, off by default on PvP.
    local CN = _G.ChehulNet
    if CN and CN.SetCampConsent and CN.CampState and CN.SetCampRealm and CN.CampRealmOn
        and not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail then
        local function camping() local st = CN:CampState(); return st == "on" or st == "default" end
        F:Check(L["Announce my campfires"], nil, camping, function(checked) CN:SetCampConsent(checked) end)
        F:Check(L["Also to the whole realm, without my name"],
            CN.IsPvPRealm and CN:IsPvPRealm() and L["Off by default on PvP realms, like this one."]
                or L["Off by default on PvP realms."],
            function() return CN:CampRealmOn() end,
            function(checked) CN:SetCampRealm(checked) end,
            { indent = SUB_INDENT, enabled = camping })
    end

    -- The member's own birthday (issue #428): the day and the month, for the guild's calendar.
    local BD = GuildOS.Birthdays
    if BD then
        F:Section(L["Birthday"])
        local box = F:Field(L["Your birthday"], { w = 80, max = 10, hint = BD:Hint(),
            get = function() return BD:Text(BD:Mine()) or "" end,
            save = function(b) GuildOS.Birthdays:SetMineText(b:GetText()); F:Refresh() end })
        F:Check(L["Show my birthday to the guild"],
            L["Only the day and the month, never the year. Untick it to remove it from everybody's Guild OS."],
            function() return BD:Mine() ~= nil end,
            function(checked)
                if checked then GuildOS.Birthdays:SetMineText(box:GetText()) else GuildOS.Birthdays:ClearMine() end
            end)
        F:Check(L["Announce birthdays in guild chat"],
            L["Officers: one line in /g on the day for each member, however many officers are online."],
            function() return BD:AnnounceOn() end,
            function(checked) BD:SetAnnounce(checked) end,
            { shown = function() return GuildOS:IsOfficer() end })
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

    -- The game's font is the only font since the Salão (#445): no switch for it any more.

    F:Section(L["In the game"])
    F:Check(L["Show minimap button"], nil,
        function() return GuildOS.IsMinimapShown and GuildOS:IsMinimapShown() end,
        function(checked) if GuildOS.SetMinimapShown then GuildOS:SetMinimapShown(checked) end end)
    -- The guildmates-in-your-zone dots on the minimap (#271, #449): where they really are.
    if GuildOS.GuildMap then
        F:Check(L["Show guildmates in your zone on the minimap"], nil,
            function() return GuildOS.GuildMap:IsMinimapDots() end,
            function(checked) GuildOS.GuildMap:SetMinimapDots(checked) end)
    end
    F:Check(L["Guild button opens Guild OS"], L["Off: the game's guild button opens the game's own guild window."],
        function() return GuildOS:IsGuildButtonHijacked() end,
        function(checked) GuildOS:SetSetting("hijackGuildButton", checked) end)
    -- Winter Veil's animations (guildos-web#662, #673): the snow over the window in December and the Winter Veil tab's
    -- embers and rays, one switch (saved as `snow`); and the tab's sounds. While it snows or the event is on.
    local veilOn = GuildOS.WinterVeil and GuildOS.WinterVeil:Event() ~= nil
    if GuildOS.Snow and (GuildOS.Snow:Phase() ~= "off" or veilOn) then
        F:Check(L["Winter Veil animations"], L["Off: no snow, embers or rays on the Guild OS window."],
            function() return GuildOS.Snow:Enabled() end,
            function(checked) GuildOS.Snow:SetEnabled(checked) end)
    end
    if veilOn then
        F:Check(L["Winter Veil sounds"], L["Off: the Winter Veil tab plays no sound."],
            function() return GuildOS:GetSetting("veilSounds") ~= false end,
            function(checked) GuildOS:SetSetting("veilSounds", checked and true or false) end)
    end
    -- Alt-click an item to open its recipe in the Crafts tab (#415).
    if GuildOS.CraftOrders then
        F:Check(L["Alt-click an item to open its recipe in Crafts"],
            L["Never while the auction house, mail, trade, a vendor or the guild bank is open."],
            function() return GuildOS:GetSetting("altClickCrafts") ~= false end,
            function(checked) GuildOS:SetSetting("altClickCrafts", checked) end)
    end

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
    -- The officers' nickname, and the same prefix in whispers, party and raid from guild members (#429).
    F:Check(L["Nickname (officers)"], nil, function() return ct().nick ~= false end, setCt("nick"),
        { indent = SUB_INDENT, enabled = annotating })
    F:Check(L["Also in whispers from guild members"], nil, function() return ct().whisper == true end, setCt("whisper"),
        { indent = SUB_INDENT, enabled = annotating })
    F:Check(L["Also in party and raid chat"], nil, function() return ct().group == true end, setCt("group"),
        { indent = SUB_INDENT, enabled = annotating })

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

    local f = checkbox(cell, label, 18)
    f:SetPoint("TOPLEFT", 0, 0)
    if f.label then
        f.label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.label:SetJustifyH("LEFT")
        f.label:SetWordWrap(false)
    end
    -- "reload" right after the label, inside the cell (#449): the switch is as wide as its label, the
    -- badge beside it; a label too long for the cell is cut before the badge.
    local badge = needsReload and UI:CreateBadge(cell, L["reload"]) or nil
    if badge then badge:SetPoint("LEFT", f, "RIGHT", 6, 0) end
    function cell:Relayout(w)
        local textW = math.ceil(num(f.label and f.label.GetStringWidth and f.label:GetStringWidth(), 0))
        local room = w - (badge and (num(badge:GetWidth(), 50) + 6) or 0)
        f:SetWidth(math.max(40, math.min(room, 22 + 6 + textW + 2)))
    end
    cell:Relayout(300)
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
    F:Section(L["Window tabs"], nil, { span = true })
    F:Note(L["Turning one off hides it; nothing is deleted."], { gap = 6 })
    F:Grid(cell, tabs, 40, { gap = 12 })
    if #background > 0 then
        F:Section(L["In the background"], nil, { span = true })
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
                local kb = checkbox(holder, Cal:KindLabel(k), 18)
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
    -- can edit notes applies it. TBC Anniversary only (audit B11).
    if isOfficer and GuildOS.Client.isAnniversary then
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
        { L["Export Data"], function() if GuildOS.ShowExportChooser then GuildOS:ShowExportChooser() end end, w = 140 },
    })
    -- A backup and its restore are the guild's whole database, not "your data" (audit D11); the restore asks first.
    F:Section(L["Whole guild database"])
    F:Buttons({
        { L["Backup"], function() if GuildOS.Backup then GuildOS.Backup:ShowExport() end end, w = 120 },
        { L["Restore"], function() if GuildOS.Backup then GuildOS.Backup:ShowRestore() end end, w = 120 },
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
        -- What needs a key press on this client (#449): no dialog, nobody is invited or whispered.
        { L["Probe invites"], function() if GuildOS.Probe then GuildOS.Probe:RunInvite() end end },
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
            -- A real roll in progress is never overwritten by a test (audit R20).
            local function rollOpen()
                if not LM:RollOpen() then return false end
                GuildOS:Print(L["|cffFFAA00A roll is open: the loot tests wait until it ends.|r"])
                return true
            end
            F:Action(L["Test Roll Popup"], L["Shows the raider roll popup with a sample item"], function()
                if rollOpen() then return end
                LM.testMode = true
                LM:ShowRollPopup("|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive of Azzinoth]|h|r", 15, 32837)
                GuildOS:Print(L["Test roll popup shown (15s timer). Try MS/OS/Pass buttons."])
            end)
            F:Action(L["Test Wishlist Council"], L["Shows the ML council result frame with sample data"], function()
                if rollOpen() then return end
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
                if rollOpen() then return end
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
                if rollOpen() then return end
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
    end, w = 120 },
        -- The game's own guild window, which the window's footer linked to before the Salão's phase 3 (#449).
        { L["Blizzard"], function() if GuildOS.OpenBlizzardGuildUI then GuildOS:OpenBlizzardGuildUI() end end, w = 120 } },
        { gap = 10 })
    F:Note(L["Project page, bug reports and updates"], { gap = 6 })

    -- /gos reset, behind a confirmation: it cannot be undone. Last, and red.
    F:Section(L["Danger zone"])
    F:Buttons({ { L["Erase guild data"], function() GuildOS:AskEraseGuildData() end, w = 170, variant = "danger" } })
    F:Note(L["Removes every Guild OS record of this guild on this PC, then reloads."], { gap = 6 })
end

----------------------------------------------------------------------
-- Credits (#449): what a player wants to know about the addon, on one page. On the wood, the crest: the
-- logo in its ring, the name in Cinzel gold, what it is, the version and the game as pills. Then the cards:
-- who made it, where to find the community (each link with a Copy that opens it in a box to select), the
-- thanks, the licence (its full text a click away), what it is built with, and this copy's details for a
-- bug report.
----------------------------------------------------------------------
local LINKS = {
    { key = "discord", glyph = "D", label = "Discord",    url = "https://discord.gg/8XA6gmNjja",                  note = "Help, bugs and ideas" },
    { key = "site",    glyph = "G", label = "guildos.me", url = "https://guildos.me",                             note = "The companion site of your guild" },
    { key = "github",  glyph = "</>", label = "GitHub",   url = "https://github.com/danielcosta42/GuildOS",       note = "Source code and bug reports" },
    { key = "curse",   glyph = "C", label = "CurseForge", url = "https://www.curseforge.com/projects/1549177",    note = "Downloads and updates" },
    { key = "wago",    glyph = "W", label = "Wago",       url = "https://addons.wago.io/addons/rNkyABKa",         note = "Downloads and updates" },
}
-- The rest of the Chehul family on WoW: Forever (they share ChehulNet, the hidden network): what each is for and
-- its CurseForge page. ProfessionHelper stays out until it runs on Forever.
local FAMILY = {
    { key = "lodestar", glyph = "L", label = "Lodestar",  url = "https://www.curseforge.com/wow/addons/lodestar",                               note = "Leveling guides with an arrow to the next quest" },
    { key = "party",    glyph = "P", label = "PartyLens", url = "https://www.curseforge.com/wow/addons/partylens-lfg-group-finder",             note = "Group radar: the LFG channel and listings in one panel" },
    { key = "warmth",   glyph = "W", label = "Warmth",    url = "https://www.curseforge.com/wow/addons/warmth-campfires-camps-for-wow-forever",  note = "Campfires on your map and who is around them" },
}
local MIT = "MIT License\n\nCopyright (c) 2026 danielcosta42\n\n"
    .. "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated "
    .. "documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation "
    .. "the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to "
    .. "permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\n"
    .. "The above copyright notice and this permission notice shall be included in all copies or substantial portions of "
    .. "the Software.\n\n"
    .. "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO "
    .. "THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE "
    .. "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, "
    .. "TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE "
    .. "SOFTWARE."
local BUILT_WITH = {
    { "Ace3: AceComm-3.0, CallbackHandler-1.0", "BSD" },
    { "LibStub", "Public domain" },
    { "ChatThrottleLib", "Public domain" },
    { "LibDeflate", "zlib" },
    { "Lib" .. "Serialize (its own copy)", "MIT" },
    { "Cinzel, Alegreya, Alegreya Sans", "SIL Open Font License" },
}

local function gameName()
    local c = GuildOS.Client or {}
    if c.isAnniversary then return L["TBC Anniversary"] end
    if c.isRetail then return L["Retail"] end
    return L["WoW: Forever"]
end

local function details()
    local c = GuildOS.Client or {}
    return table.concat({
        "Guild OS v" .. tostring(GuildOS.VERSION or "?"),
        L["Game"] .. ": " .. gameName() .. " " .. tostring(c.version or "") .. " (" .. tostring(c.build or "") .. ", " .. tostring(c.interface or "") .. ")",
        L["Language"] .. ": " .. tostring(GetLocale and GetLocale() or "?"),
    }, "\n")
end

-- A pill on the wood: a soft gold outline round a short text.
local function pill(parent, text)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(20)
    local fill = GuildOS.Style:Nine(p, "pill-line", 10, "BACKGROUND", 1)
    fill:SetColor(WOOD.gold2)
    p.text = UI:CreateText(p, text, 11, WOOD.gold2.r, WOOD.gold2.g, WOOD.gold2.b)
    p.text:SetPoint("CENTER", 0, 0)
    -- Measured again at each layout (a font not loaded yet measures short, #449 "WoW: Forever" spilled out);
    -- never under the label's length at the caption size, so a short measure cannot cut it.
    function p:Fit()
        local measured = math.ceil(tonumber(UI:TextWidth(self.text, 40)) or 40)
        local floor = math.ceil(#(self.text:GetText() or "") * 6.2)
        self:SetWidth(math.max(measured, floor) + 30)
    end
    p:Fit()
    return p
end

-- One line of the community card: a round glyph, the name and what it is for, the address, Copy.
local function linkRow(F, link)
    local row = CreateFrame("Frame", nil, F.content)
    row:SetSize(1, 40)
    local g = UI:CreateGlyph(row, 30)
    g:SetPoint("LEFT", 0, 0)
    g:Set(link.glyph, C.paperTitle)
    local name = UI:CreateText(row, link.label, 13, C.text.r, C.text.g, C.text.b)
    GuildOS:ApplyFont(name, 13, "button")
    name:SetPoint("TOPLEFT", g, "TOPRIGHT", 10, 1)
    local note = UI:CreateText(row, L[link.note], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    note:SetPoint("LEFT", name, "RIGHT", 8, 0)
    note:SetWordWrap(false)
    note:SetJustifyH("LEFT")
    local url = UI:CreateText(row, link.url, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    url:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    url:SetWordWrap(false)
    url:SetJustifyH("LEFT")
    local copy = UI:SetButtonVariant(UI:CreateButton(row, L["Copy"], 70, 24), "ghost")
    copy:SetPoint("RIGHT", 0, 0)
    copy:SetScript("OnClick", function() GuildOS:ShowExportPopup(link.label, link.url) end)
    UI:AddTooltip(copy, link.label, { link.url, L["Opens the address in a box: Ctrl+C copies it."] })
    row.copy, row.url, row.note = copy, url, note
    F:Row(row, { gap = 6, wide = true, place = function(r, w)
        r:SetWidth(math.max(1, w))
        local room = math.max(40, w - 30 - 10 - copy:GetWidth() - 8)
        url:SetWidth(room)
        note:SetWidth(math.max(1, room - UI:TextWidth(name, 60) - 8))
        return 40
    end })
    return row
end

PAGES.credits = function(F)
    -- The crest, on the wood.
    local hero = CreateFrame("Frame", nil, F.content)
    hero:SetSize(1, 96)
    local glow = hero:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(GuildOS.Style.ART and GuildOS.Style.ART.halo or "Interface\\AddOns\\GuildOS\\Media\\Salao\\halo")
    glow:SetSize(120, 120)
    glow:SetPoint("LEFT", -18, 0)
    glow:SetVertexColor(WOOD.gold2.r, WOOD.gold2.g, WOOD.gold2.b, 0.35)
    local logo = hero:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\GuildOS\\Media\\minimap-logo")
    logo:SetSize(72, 72)
    logo:SetPoint("LEFT", 6, 0)
    local ring = hero:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(GuildOS.Style.ART and GuildOS.Style.ART.ring or "Interface\\AddOns\\GuildOS\\Media\\Salao\\ring")
    ring:SetSize(84, 84)
    ring:SetPoint("CENTER", logo, "CENTER", 0, 0)
    ring:SetVertexColor(WOOD.gold2.r, WOOD.gold2.g, WOOD.gold2.b, 1)
    local title = UI:CreateText(hero, "Guild OS", 28, WOOD.gold.r, WOOD.gold.g, WOOD.gold.b)
    GuildOS:ApplyFont(title, 28, "windowTitle")
    title:SetTextColor(WOOD.gold.r, WOOD.gold.g, WOOD.gold.b)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 20, 2)
    local tag = UI:CreateText(hero, L["The guild manager for WoW: Forever, TBC Anniversary and Retail."], 12,
        WOOD.textSoft.r, WOOD.textSoft.g, WOOD.textSoft.b)
    tag:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
    tag:SetJustifyH("LEFT")
    local pills = { pill(hero, "v" .. tostring(GuildOS.VERSION or "?")), pill(hero, gameName()), pill(hero, "MIT") }
    local function placePills()
        local x = 0
        for _, p in ipairs(pills) do
            p:Fit()
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", tag, "BOTTOMLEFT", x, -8)
            x = x + p:GetWidth() + 6
        end
    end
    placePills()
    F:Row(hero, { gap = 4, wide = true, place = function(h, w)
        placePills()
        h:SetWidth(math.max(1, w))
        tag:SetWidth(math.max(1, w - 72 - 26))
        return math.max(96, 2 + 32 + 4 + math.ceil(tag:GetStringHeight() or 14) + 8 + 20 + 6)
    end })
    F.hero = hero

    -- Who made it.
    F:Section(L["Made by"])
    local who = CreateFrame("Frame", nil, F.content)
    who:SetSize(1, 52)
    local av = UI:CreateGlyph(who, 44)
    av:SetPoint("LEFT", 0, 0)
    av:Set("C", C.paperTitle)
    local nm = UI:CreateText(who, "Chehul", 16, C.text.r, C.text.g, C.text.b)
    GuildOS:ApplyFont(nm, 16, "sectionTitle")
    nm:SetPoint("TOPLEFT", av, "TOPRIGHT", 12, -4)
    local handle = UI:CreateText(who, "danielcosta42", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    handle:SetPoint("LEFT", nm, "RIGHT", 8, -1)
    local role = UI:CreateText(who, L["Creator and developer"], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    role:SetPoint("TOPLEFT", nm, "BOTTOMLEFT", 0, -4)
    F:Row(who, { gap = 4, wide = true, h = 52 })
    F:Note(L["Made with care for the guilds that play together, in every client the addon runs on."], { gap = 8 })

    -- Where to find the community.
    F:Section(L["Community and links"])
    for _, link in ipairs(LINKS) do linkRow(F, link) end

    -- The rest of the family.
    F:Section(L["The Chehul family"])
    F:Note(L["Guild OS has siblings, made by the same hands and talking over the same hidden network."], { gap = 2 })
    for _, link in ipairs(FAMILY) do linkRow(F, link) end

    -- The thanks.
    F:Section(L["Thanks"])
    F:Note(L["To the supporters on Discord, whose ideas and screenshots shaped this redesign, and to every guild that tested Guild OS in its raids and its chat."])
    F:Note(L["Found a bug or have an idea? The Discord is the quickest way to reach us."], { gap = 8 })
    F:Buttons({ { L["Join the Discord"], function() GuildOS:ShowExportPopup("Discord", LINKS[1].url) end, w = 160, variant = "primary" } },
        { gap = 10 })

    -- The licence.
    F:Section(L["License"])
    F:Value(L["License"], function() return "MIT" end)
    F:Value(L["Copyright"], function() return "2026 danielcosta42" end)
    F:Note(L["Free to use, change and share, with the copyright notice kept. It comes with no warranty."], { gap = 8 })
    F:Buttons({ { L["Read the license"], function() GuildOS:ShowExportPopup(L["License"], MIT) end, w = 160 } }, { gap = 10 })

    -- What it is built with.
    F:Section(L["Built with"])
    for _, lib in ipairs(BUILT_WITH) do F:Value(lib[1], function() return lib[2] end) end
    F:Note(L["Thanks to their authors: each keeps its own license."], { gap = 8 })

    -- This copy, for a bug report.
    F:Section(L["This copy"])
    F:Value(L["Version"], function() return "v" .. tostring(GuildOS.VERSION or "?") end)
    F:Value(L["Game"], gameName)
    F:Value(L["Language"], function() return GetLocale and GetLocale() or "?" end)
    F:Buttons({ { L["Copy for a bug report"], function() GuildOS:ShowExportPopup(L["This copy"], details()) end, w = 190 } },
        { gap = 10 })
    F:Note(L["Type /gos help to see every command."], { gap = 8 })
end

----------------------------------------------------------------------
-- Building a page into a frame. A page is rebuilt only when what it shows
-- changed shape (rank, the guild's ranks, a module's data appearing); the
-- values are re-read on every refresh.
----------------------------------------------------------------------
local builtPages = setmetatable({}, { __mode = "k" })   -- content -> { [shape] = { form, parts } }
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
        -- Each shape's page is built once and kept (memory audit): what a build made is set aside when the
        -- shape changes and shown again when it comes back, so an officer flag that flips at login, or two
        -- shapes taken in turn, no longer leave a whole page of frames behind on every change.
        local cache = builtPages[content]
        if not cache then cache = {}; builtPages[content] = cache end
        local old = content.__settingsShape and cache[content.__settingsShape]
        if old then
            for _, part in ipairs(old.parts) do part:Hide() end
        elseif F then
            for _, child in pairs({ content:GetChildren() }) do child:Hide() end
            for _, region in pairs({ content:GetRegions() }) do region:Hide() end
        end
        local kept = cache[shape]
        if kept then
            for _, part in ipairs(kept.parts) do part:Show() end
            F = kept.form
        else
            local before = {}
            for _, child in ipairs({ content:GetChildren() }) do before[child] = true end
            for _, region in ipairs({ content:GetRegions() }) do before[region] = true end
            F = newForm(content)
            PAGES[key](F, isOfficer)
            local parts = {}
            for _, child in ipairs({ content:GetChildren() }) do if not before[child] then parts[#parts + 1] = child end end
            for _, region in ipairs({ content:GetRegions() }) do if not before[region] then parts[#parts + 1] = region end end
            cache[shape] = { form = F, parts = parts }
        end
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
    rule(strip)
    strip:SetBackdropColor(WOOD.panel.r, WOOD.panel.g, WOOD.panel.b, 1)
    strip:SetBackdropBorderColor(WOOD.line.r, WOOD.line.g, WOOD.line.b, 1)
    strip.text = UI:CreateText(strip, "", 12, WOOD.text.r, WOOD.text.g, WOOD.text.b)
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
        if parent.PlaceUnderSubBar then
            parent.PlaceUnderSubBar(info.scroll)
        else
            info.scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -10)
        end
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
    -- The Settings button's entries open these pages themselves (#445).
    UI:CollapsibleSubBar(parent, bar, function()
        local t = {}
        for key, info in pairs(parent.subPanels) do t[key] = info.scroll end
        return t
    end, { 2, -10 })

    for _, s in ipairs(SUBS) do
        local t = UI:CreateTab(bar, s.label, TAB_MIN, true)
        t:SetWidth(math.max(TAB_MIN, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
        t:SetScript("OnClick", function() selectSub(s.key) end)
        tabs[s.key] = t
        tabList[#tabList + 1] = t
        local scroll, content = UI:CreateScrollFrame(parent, "GuildOSSettings_" .. s.key)
        -- Every part of a page sits on its sections' parchment cards: the controls take the paper's look.
        if Kit then content.__paper = true end
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
