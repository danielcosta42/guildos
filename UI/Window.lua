----------------------------------------------------------------------
-- Guild OS - The window (issue #14, ADR-0016)
-- The only container. Every feature is a tab in one resizable window, and
-- every entry point opens it: the slash commands, the minimap button, the
-- guild-frame takeover and the key binding, all through
-- UI:OpenWindow(id, sub) or UI:ToggleMain().
--
-- It reorganises by width through the resize ladder (UI/Layout.lua). Tabs
-- that do not fit fold into "»n"; under 520px the tab rule becomes a
-- one-line selector and the content switches to the Now tab; under 420px
-- only the 28px title bar stays, with three numbers. Nothing animates.
-- Position, size and the active tab persist in settings.window.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local WHITE        = "Interface\\Buttons\\WHITE8x8"
local NAME         = "GuildOSWindow"
local DEFAULT_W    = 1000
local DEFAULT_H    = 620
local MIN_W        = 320
local BAR_H        = 28      -- the title bar under 620px, and the whole window in the bar band
local TITLE_H      = 30
local NARROW       = 620     -- under this: the 28px title bar and 8px padding
local PAD          = 12
local PAD_NARROW   = 8
local RULE_H       = 28
local RULE_PAD     = 6
local TAB_GAP      = 2
local TAB_MIN_W    = 48
local TAB_TEXT_PAD = 20
local MORE_W       = 36
local FOOT_H       = 22
local FOOT_PAD     = 10
local FOOT_GAP     = 8
local GRIP         = 16
local HOME         = "home"  -- the Now tab
local DASH         = "\226\128\148"
local DOT          = " \194\183 "
local RAQUO        = "\194\187"

BINDING_HEADER_GUILDOS = "Guild OS"
BINDING_NAME_GUILDOS_TOGGLE = L["Open or close Guild OS"]

local function round(n) return math.floor(n + 0.5) end

local function store()
    local g = BRutus:GetSetting("window")
    if type(g) ~= "table" then
        g = {}
        BRutus:SetSetting("window", g)
    end
    return g
end

local function allowed(key)
    return UI:IsFeatureAllowed(UI:GetFeature(key))
end

local function bandMin(name)
    for _, band in ipairs(UI.LADDER) do
        if band.name == name then return band.min end
    end
    return 0
end

-- The ladder measures the panel hosting the tables, the content area inside
-- the padding, not the window (handoff §6).
local function contentWidth(w)
    return w - 2 * ((w < NARROW) and PAD_NARROW or PAD)
end

local function tabFeatures()
    local out = {}
    for _, id in ipairs(UI.featureOrder) do
        local def = UI.features[id]
        if def.tab then out[#out + 1] = def end
    end
    return out
end

----------------------------------------------------------------------
-- Geometry (settings.window: left, top, w, h, tab, collapsed, restoreW, restoreH)
----------------------------------------------------------------------

-- A saved rectangle kept on a screen of sw × sh: no larger than the screen,
-- no smaller than the bar, and moved back inside when it hangs off an edge.
-- Frame coordinates, origin at the bottom left.
function UI:ClampWindowRect(left, top, w, h, sw, sh)
    w = math.max(MIN_W, math.min(w, sw))
    h = math.max(BAR_H, math.min(h, sh))
    left = math.max(0, math.min(left, sw - w))
    top = math.max(h, math.min(top, sh))
    return left, top, w, h
end

function UI:SaveWindowGeometry(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    local g = store()
    g.left, g.top = round(left), round(top)
    g.w, g.h = round(f:GetWidth()), round(f:GetHeight())
end

-- Absent: 1000×620, centred. Present: where it was, clamped onto the screen.
function UI:RestoreWindowGeometry(f)
    local g = store()
    local scale = f:GetScale()
    if not scale or scale <= 0 then scale = 1 end
    local sw, sh = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
    f:ClearAllPoints()
    if g.left and g.top and g.w and g.h then
        local left, top, w, h = self:ClampWindowRect(g.left, g.top, g.w, g.h, sw, sh)
        f:SetSize(w, h)
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        f:SetSize(math.min(DEFAULT_W, sw), math.min(DEFAULT_H, sh))
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- Anchor by the top-left corner where the window is now, so a size change
-- moves the bottom-right edge instead of both edges around the centre.
local function pinTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

----------------------------------------------------------------------
-- The tab menu: the "»n" overflow, and the one-line selector under 520px.
----------------------------------------------------------------------
local menu
local function showTabMenu(f, anchor, keys)
    if #keys == 0 then return end
    menu = menu or CreateFrame("Frame", "GuildOSTabMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menu, function(_, level)
        for _, key in ipairs(keys) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = UI:GetFeature(key).label
            info.checked = (key == f.activeTab)
            info.func = function()
                f:SetActiveTab(key, true)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
end

----------------------------------------------------------------------
-- Footer: quick actions, dropped lowest priority first as the window
-- narrows, and the invite field for whoever can invite.
----------------------------------------------------------------------
local FOOTER = {
    { key = "search", label = L["Search"], priority = 100,
      run = function() if BRutus.Search then BRutus.Search:Show() end end },
    { key = "sync", label = L["Sync"], priority = 90,
      run = function() if BRutus.CommSystem then BRutus.CommSystem:FullSync() end end },
    { key = "invite", priority = 80 },
    { key = "cores", label = L["Core Sign-up"], priority = 60,
      run = function() if BRutus.ShowCoreSignupFrame then BRutus:ShowCoreSignupFrame() end end },
    { key = "blizzard", label = L["Blizzard"], priority = 50,
      run = function() if BRutus.OpenBlizzardGuildUI then BRutus:OpenBlizzardGuildUI() end end },
}

local function inviteField(parent)
    local holder = CreateFrame("Frame", nil, parent)
    local box = CreateFrame("EditBox", nil, holder, "BackdropTemplate")
    box:SetSize(130, 18)
    box:SetPoint("LEFT", 0, 0)
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
    box:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    BRutus:ApplyFont(box, 10)
    box:SetTextColor(C.text.r, C.text.g, C.text.b)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(50)

    local hint = box:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(hint, 10)
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(C.labelDim.r, C.labelDim.g, C.labelDim.b)
    hint:SetText(L["Player name..."])
    box:SetScript("OnTextChanged", function(self) hint:SetShown((self:GetText() or "") == "") end)

    local btn = UI:CreateButton(holder, L["Invite"], 64, 18)
    btn:SetPoint("LEFT", box, "RIGHT", 4, 0)

    local function invite()
        local target = strtrim(box:GetText() or "")
        if target == "" then
            BRutus:Print(L["Enter a player name to invite."])
            return
        end
        GuildInvite(target)
        BRutus:Print(string.format(L["Guild invite sent to %s."], target))
        box:SetText("")
    end
    btn:SetScript("OnClick", function() invite(); box:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) invite(); self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    holder:SetSize(130 + 4 + 64, 18)
    holder.box = box
    return holder
end

----------------------------------------------------------------------
-- Build the window. Tab content is NOT built here: each panel builds the
-- first time its tab is opened.
----------------------------------------------------------------------
local function createWindow()
    local f = UI:CreatePanel(UIParent, NAME)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, BAR_H)
    elseif f.SetMinResize then
        f:SetMinResize(MIN_W, BAR_H)
    end
    f:Hide()
    f:SetScale(BRutus:GetSetting("uiScale") or 1)
    UI:RestoreWindowGeometry(f)
    f.tabs, f.tabPanels, f.overflow, f.footItems = {}, {}, {}, {}

    ------------------------------------------------------------------
    -- Title bar: the drag handle
    ------------------------------------------------------------------
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        pinTopLeft(f)
        UI:SaveWindowGeometry(f)
    end)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(WHITE)
    barBg:SetAllPoints()
    barBg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
    local barLine = UI:CreateSeparator(bar)
    barLine:SetPoint("BOTTOMLEFT", 0, 0)
    barLine:SetPoint("BOTTOMRIGHT", 0, 0)
    f.titleBar = bar

    local function text(size, role, color)
        local fs = bar:CreateFontString(nil, "OVERLAY")
        BRutus:ApplyFont(fs, size, role)
        fs:SetShadowOffset(0, 0)
        fs:SetTextColor(color.r, color.g, color.b)
        fs:SetWordWrap(false)
        return fs
    end

    local wordmark = text(18, "wordmark", C.gold)
    wordmark:SetPoint("LEFT", 10, 0)
    wordmark:SetText("GuildOS")

    local close = UI:TitleBarButton(bar, "close")
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton = close

    -- The close button with its glyph swapped: same size, same hover.
    local minimise = UI:TitleBarButton(bar, "close")
    minimise.x:SetText(DASH)
    minimise:SetPoint("RIGHT", close, "LEFT", -2, 0)
    minimise:SetScript("OnClick", function() f:ToggleCollapsed() end)
    f.minimise = minimise

    local sync = text(10, "caption", C.label)
    sync:SetPoint("RIGHT", minimise, "LEFT", -8, 0)
    sync:SetJustifyH("RIGHT")
    f.syncText = sync

    local meta = text(10, "caption", C.labelDim)
    meta:SetPoint("LEFT", wordmark, "RIGHT", 10, 0)
    meta:SetPoint("RIGHT", sync, "LEFT", -10, 0)
    meta:SetJustifyH("LEFT")
    f.metaText = meta

    local summary = text(11, nil, C.text)
    summary:SetPoint("LEFT", wordmark, "RIGHT", 10, 0)
    summary:SetPoint("RIGHT", minimise, "LEFT", -6, 0)
    summary:SetJustifyH("LEFT")
    summary:Hide()
    f.summaryText = summary

    ------------------------------------------------------------------
    -- Tab rule, "»n" and the selector
    ------------------------------------------------------------------
    local rule = CreateFrame("Frame", nil, f)
    rule:SetHeight(RULE_H)
    local ruleLine = UI:CreateSeparator(rule)
    ruleLine:SetPoint("BOTTOMLEFT", 0, 0)
    ruleLine:SetPoint("BOTTOMRIGHT", 0, 0)
    f.rule = rule

    for _, def in ipairs(tabFeatures()) do
        local tab = UI:CreateTab(rule, def.label, TAB_MIN_W)
        tab.key = def.id
        tab:SetScript("OnClick", function() f:SetActiveTab(def.id, true) end)
        tab:Hide()
        f.tabs[#f.tabs + 1] = tab
    end

    local more = UI:SetButtonVariant(UI:CreateButton(rule, "", MORE_W, 22), "ghost")
    more:SetPoint("RIGHT", rule, "RIGHT", -RULE_PAD, 0)
    more:SetScript("OnClick", function(self) showTabMenu(f, self, f.overflow) end)
    more:Hide()
    f.more = more

    local selector = UI:SetButtonVariant(UI:CreateButton(rule, "", 120, 22), "ghost")
    selector:SetPoint("LEFT", rule, "LEFT", RULE_PAD, 0)
    selector:SetScript("OnClick", function(self)
        local keys = {}
        for _, tab in ipairs(f.tabs) do
            if allowed(tab.key) then keys[#keys + 1] = tab.key end
        end
        showTabMenu(f, self, keys)
    end)
    selector:Hide()
    f.selector = selector

    ------------------------------------------------------------------
    -- Content: one empty panel per tab
    ------------------------------------------------------------------
    local content = CreateFrame("Frame", nil, f)
    -- Clipping is the net under the ladder: a panel that has not learnt the
    -- narrow bands yet is cut at the window's edge instead of painting past it.
    if content.SetClipsChildren then content:SetClipsChildren(true) end
    f.content = content
    for _, def in ipairs(tabFeatures()) do
        local panel = CreateFrame("Frame", nil, content)
        panel:SetAllPoints(content)
        panel:Hide()
        panel.featureId = def.id
        f.tabPanels[def.id] = panel
    end

    ------------------------------------------------------------------
    -- Footer and grip
    ------------------------------------------------------------------
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(FOOT_H)
    local footLine = UI:CreateSeparator(foot)
    footLine:SetPoint("TOPLEFT", 0, 0)
    footLine:SetPoint("TOPRIGHT", 0, 0)
    f.footer = foot

    for _, item in ipairs(FOOTER) do
        local frame
        if item.key == "invite" then
            frame = inviteField(foot)
        else
            frame = UI:SetButtonVariant(UI:CreateButton(foot, item.label, 40, 18), "ghost")
            frame:SetWidth(math.max(40, math.ceil(frame.label:GetStringWidth()) + 12))
            frame:SetScript("OnClick", item.run)
        end
        frame:Hide()
        f.footItems[item.key] = frame
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        pinTopLeft(f)
        f.sizingFrom = { f:GetWidth(), f:GetHeight() }
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f:Settle()
    end)
    f.grip = grip

    ------------------------------------------------------------------
    -- Tabs
    ------------------------------------------------------------------

    -- Open a tab, building its panel the first time. `byUser` remembers it
    -- across /reload; the switch to Now under 520px is not remembered.
    function f:SetActiveTab(key, byUser)
        local def = UI:GetFeature(key)
        local panel = self.tabPanels[key]
        if not (panel and allowed(key)) then return false end
        -- A panel that raised while building is half-built, so it stays
        -- refused until /reload instead of opening empty.
        if not panel.built then
            panel.built = true
            panel.buildFailed = not BRutus:RunStartup("Tab:" .. key, nil, def.build, panel, self)
        end
        if panel.buildFailed then
            BRutus:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
            return false
        end
        self.activeTab = key
        if byUser then
            store().tab = key
            self.beforeWatch = nil
        end
        for _, tab in ipairs(self.tabs) do tab:SetActive(tab.key == key) end
        for k, p in pairs(self.tabPanels) do p:SetShown(k == key) end
        self:LayoutTabs()
        return true
    end

    -- Re-check which tabs may show (rank, loot system, alliance, Settings
    -- toggles and start-up failures all change it without a reload) and fall
    -- back to Now when the open tab is no longer allowed.
    function f:UpdateTabVisibility()
        if not (self.activeTab and allowed(self.activeTab)) then
            local panel = self.activeTab and self.tabPanels[self.activeTab]
            if panel then panel:Hide() end
            self.activeTab = nil
            -- Not to a Now tab that failed to build: this runs on every group
            -- change, and the refusal would print each time.
            local home = self.tabPanels[HOME]
            if not (home and home.buildFailed) then self:SetActiveTab(HOME) end
        end
        self:LayoutTabs()
    end

    function f:LayoutTabs(w)
        w = w or self:GetWidth() or 0
        local shown = {}
        for _, tab in ipairs(self.tabs) do
            tab:Hide()
            if allowed(tab.key) then shown[#shown + 1] = tab end
        end
        self.overflow = {}
        more:Hide()
        selector:SetShown(self.band == "watch")
        if self.band == "watch" then
            local def = UI:GetFeature(self.activeTab)
            selector.label:SetText((def and def.label or "") .. " " .. RAQUO)
            selector:SetWidth(math.ceil(selector.label:GetStringWidth()) + 16)
            return
        end
        if self.band == "bar" then return end

        local widths, active = {}, nil
        for i, tab in ipairs(shown) do
            widths[i] = math.max(TAB_MIN_W, math.ceil(tab.label:GetStringWidth()) + TAB_TEXT_PAD)
            if tab.key == self.activeTab then active = i end
        end
        local visible, hidden = UI:FitTabs(widths, w - 2 * RULE_PAD, TAB_GAP, MORE_W, active)
        local x, placed = RULE_PAD, {}
        for _, i in ipairs(visible) do
            local tab = shown[i]
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", rule, "LEFT", x, 0)
            tab:SetWidth(widths[i])
            tab:Show()
            x = x + widths[i] + TAB_GAP
            placed[i] = true
        end
        for i, tab in ipairs(shown) do
            if not placed[i] then self.overflow[#self.overflow + 1] = tab.key end
        end
        if hidden > 0 then
            more.label:SetText(RAQUO .. hidden)
            more:Show()
        end
    end

    function f:LayoutFooter(w)
        w = w or self:GetWidth() or 0
        local spec = {}
        for _, item in ipairs(FOOTER) do
            local frame = self.footItems[item.key]
            frame:Hide()
            if item.key ~= "invite" or CanGuildInvite() then
                spec[#spec + 1] = { key = item.key, min = frame:GetWidth(), weight = 0, priority = item.priority }
            end
        end
        -- The grip keeps the right-hand corner.
        for _, col in ipairs(UI:ResolveColumns(spec, w - 2 * FOOT_PAD - GRIP, FOOT_GAP)) do
            if col.shown then
                local frame = self.footItems[col.key]
                frame:ClearAllPoints()
                frame:SetPoint("LEFT", foot, "LEFT", FOOT_PAD + col.x, 0)
                frame:Show()
            end
        end
    end

    -- Guarded: it runs on every show and roster update, and reads modules
    -- that may not have started.
    function f:RefreshTitle()
        BRutus:SafeCall(function()
            local A = UI.Agora
            local online = A:RosterLoading() and DASH or string.format(L["%d online"], A:OnlineCount())
            meta:SetText((GetGuildInfo("player") or "Guild OS") .. DOT .. online)
            local last = A:LastSync()
            sync:SetText(last and string.format(L["sync %s"], BRutus:TimeAgo(last)) or L["not synced yet"])
            -- The three numbers walk the officer work, so only while they show.
            if self.band == "bar" then summary:SetText(A:BarText()) end
        end)
    end

    ------------------------------------------------------------------
    -- The ladder
    ------------------------------------------------------------------

    -- The minimise button, and the way back out of the bar: folded (or in the
    -- bar band) it restores the size the window had, otherwise it folds to the
    -- bar. The saved fold decides, since the band is unknown until the first
    -- layout after /reload.
    function f:ToggleCollapsed()
        local g = store()
        pinTopLeft(self)
        if g.collapsed or self.band == "bar" then
            g.collapsed = nil
            -- Wide enough that the content area clears the bar band.
            self:SetSize(math.max(g.restoreW or DEFAULT_W,
                bandMin("watch") + UI.LADDER_HYSTERESIS + 2 * PAD_NARROW), g.restoreH or DEFAULT_H)
        else
            g.collapsed = true
            g.restoreW, g.restoreH = round(self:GetWidth()), round(self:GetHeight())
            self:SetSize(MIN_W, BAR_H)
        end
        UI:SaveWindowGeometry(self)
        -- Laid out now: a hidden frame is not sure to get OnSizeChanged.
        self:Layout(self:GetWidth())
    end

    -- After the grip lets go. The bar band is one 28px line, so a window
    -- dragged into it folds to that line, and one dragged back out gets the
    -- height it had before.
    function f:Settle()
        local g = store()
        pinTopLeft(self)
        local band = UI:ResolveBand(contentWidth(self:GetWidth()), self.band)
        if band == "bar" then
            if not g.collapsed then
                local from = self.sizingFrom
                g.collapsed = true
                g.restoreW = from and round(from[1]) or DEFAULT_W
                g.restoreH = from and round(from[2]) or DEFAULT_H
            end
            self:SetHeight(BAR_H)
        elseif g.collapsed then
            g.collapsed = nil
            self:SetHeight(g.restoreH or DEFAULT_H)
        end
        self.sizingFrom = nil
        UI:SaveWindowGeometry(self)
    end

    function f:Layout(w)
        local band = UI:ResolveBand(contentWidth(w), self.band)
        local changed = band ~= self.band
        self.band = band
        local isBar, isWatch = band == "bar", band == "watch"
        local narrow = w < NARROW
        local titleH = (narrow or isBar) and BAR_H or TITLE_H
        local pad = narrow and PAD_NARROW or PAD

        bar:SetHeight(titleH)
        meta:SetShown(not isBar)
        sync:SetShown(not isBar)
        summary:SetShown(isBar)
        minimise.x:SetText(isBar and "+" or DASH)
        close:ClearAllPoints()
        close:SetPoint("RIGHT", bar, "RIGHT", isBar and -(GRIP + 4) or -6, 0)

        rule:SetShown(not isBar)
        content:SetShown(not isBar)
        foot:SetShown(not isBar)
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", 0, -titleH)
        rule:SetPoint("TOPRIGHT", 0, -titleH)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", pad, -(titleH + RULE_H + pad))
        content:SetPoint("BOTTOMRIGHT", -pad, FOOT_H + pad)

        local home = self.tabPanels[HOME]
        if changed and isWatch and self.activeTab ~= HOME and not (home and home.buildFailed) then
            -- The tab that was open comes back once the window is wide again.
            self.beforeWatch = self.activeTab
            self:SetActiveTab(HOME)
        elseif changed and not isWatch and not isBar and self.beforeWatch then
            local back = self.beforeWatch
            self.beforeWatch = nil
            if self.activeTab == HOME then self:SetActiveTab(back) end
        end

        self:LayoutTabs(w)
        self:LayoutFooter(w)
        if changed then self:RefreshTitle() end
    end

    ------------------------------------------------------------------
    -- Show, hide, events
    ------------------------------------------------------------------
    f:SetScript("OnShow", function(self)
        self:UpdateTabVisibility()
        self:RefreshTitle()
        if not self.ticker then
            self.ticker = C_Timer.NewTicker(10, function() self:RefreshTitle() end)
        end
    end)
    f:SetScript("OnHide", function(self)
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
    end)
    -- After OnShow is set: MakeResponsive hooks it.
    UI:MakeResponsive(f, function(_, w) f:Layout(w) end)

    -- One literal call per event: tools/probe.lua reads them to keep the
    -- probe's event list honest.
    BRutus.Compat.RegisterEvent(f, "GROUP_ROSTER_UPDATE")
    BRutus.Compat.RegisterEvent(f, "RAID_ROSTER_UPDATE")
    BRutus.Compat.RegisterEvent(f, "PARTY_LOOT_METHOD_CHANGED")
    BRutus.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(self, event)
        if event == "GUILD_ROSTER_UPDATE" then
            if self:IsShown() then self:RefreshTitle() end
        else
            self:UpdateTabVisibility()
        end
    end)

    table.insert(UISpecialFrames, NAME)   -- ESC closes it

    local saved = store().tab
    if not (saved and f:SetActiveTab(saved)) then f:UpdateTabVisibility() end
    return f
end

----------------------------------------------------------------------
-- The ways in
----------------------------------------------------------------------

-- The window, created on first use. Nil until the saved data is loaded.
function UI:GetMainWindow()
    if not BRutus.db then return nil end
    if not BRutus.RosterFrame then BRutus.RosterFrame = createWindow() end
    return BRutus.RosterFrame
end

-- Show the window on tab `id`, then on sub-tab `sub`, with `filter` applied
-- where that sub-tab takes one (Guild › Calendar takes a day). The one opener
-- every entry point uses. Returns true when the tab opened.
function UI:OpenWindow(id, sub, filter)
    local def = self:GetFeature(id)
    if not (def and def.tab) then return false end
    -- Checked here with their own messages, before the tab gate that covers
    -- all three: a disabled feature, a failed one and a rank refusal read
    -- differently to the player.
    if not BRutus:IsFeatureEnabled(id) then
        BRutus:Print(string.format(L["%s is disabled in Settings."], def.label))
        return false
    end
    if BRutus:FeatureStartFailed(id) then
        BRutus:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
        return false
    end
    if not self:IsFeatureAllowed(def) then
        BRutus:Print(string.format(L["%s is officer-only."], def.label))
        return false
    end
    local f = self:GetMainWindow()
    if not f then return false end
    f:Show()
    -- A tab asked for by name has to be seen, so the bar opens back up.
    if store().collapsed or f.band == "bar" then f:ToggleCollapsed() end
    if not f:SetActiveTab(id, true) then return false end
    local panel = f.tabPanels[id]
    if sub and panel.SelectSub then panel.SelectSub(sub, filter) end
    return true
end

function UI:ToggleMain()
    local f = self:GetMainWindow()
    if f then f:SetShown(not f:IsShown()) end
end

function UI:ApplyScale()
    local f = BRutus.RosterFrame
    if f then f:SetScale(BRutus:GetSetting("uiScale") or 1) end
end

-- A feature turned off in Settings loses its tab at once.
function UI:OnFeatureToggled()
    local f = BRutus.RosterFrame
    if f then f:UpdateTabVisibility() end
end
