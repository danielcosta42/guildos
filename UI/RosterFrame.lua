----------------------------------------------------------------------
-- BRutus Guild Manager - Roster Frame
-- Premium guild roster UI with modern visual design
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors

-- Column definitions
local COLUMNS = {
    { key = "status",      label = "",            width = 20,  align = "CENTER" },
    { key = "name",        label = "MEMBER",      width = 140, align = "LEFT" },
    { key = "level",       label = "LVL",         width = 40,  align = "CENTER" },
    { key = "class",       label = "CLASS",       width = 80,  align = "LEFT" },
    { key = "race",        label = "RACE",        width = 80,  align = "LEFT" },
    { key = "avgIlvl",     label = "iLVL",        width = 50,  align = "CENTER" },
    { key = "professions", label = "PROFESSIONS", width = 160, align = "LEFT" },
    { key = "attunements", label = "ATTUNEMENTS",  width = 140, align = "LEFT" },
    { key = "attendance", label = "ATT%",         width = 50,  align = "CENTER" },
    { key = "zone",        label = "ZONE",         width = 120, align = "LEFT" },
    { key = "lastSeen",    label = "LAST SEEN",   width = 80,  align = "RIGHT" },
}

local ROW_HEIGHT = 32
local HEADER_HEIGHT = 36
local VISIBLE_ROWS = 18
local FRAME_WIDTH = 1080
local FRAME_HEIGHT = HEADER_HEIGHT + (ROW_HEIGHT * VISIBLE_ROWS) + 150  -- extra space for tab bar

local TAB_HEIGHT = 28

----------------------------------------------------------------------
-- Create the main roster frame
----------------------------------------------------------------------
function BRutus.CreateRosterFrame()
    local frame = UI:CreatePanel(UIParent, "BRutusRosterFrame")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(10)
    frame:Hide()

    -- Double border effect for premium feel
    local outerBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    outerBorder:SetPoint("TOPLEFT", -2, 2)
    outerBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    outerBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    outerBorder:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.3)
    outerBorder:SetFrameLevel(9)

    -- Inner glow effect (subtle gradient overlay at top)
    local topGlow = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    topGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    topGlow:SetPoint("TOPLEFT", 1, -1)
    topGlow:SetPoint("TOPRIGHT", -1, -1)
    topGlow:SetHeight(60)
    topGlow:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(C.accent.r, C.accent.g, C.accent.b, 0.08))

    ----------------------------------------------------------------
    -- Title Bar
    ----------------------------------------------------------------
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(44)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- Title background accent
    local titleBg = titleBar:CreateTexture(nil, "ARTWORK")
    titleBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleBg:SetAllPoints()
    titleBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, C.headerBg.a)

    -- Guild emblem icon (3-layer tabard system)
    -- Textures MUST have global names — SetGuildTabardTextures in TBC Classic
    -- expects string names, not Lua object references.
    local guildIcon = CreateFrame("Frame", nil, titleBar)
    guildIcon:SetSize(28, 28)
    guildIcon:SetPoint("LEFT", 12, 0)
    local guildIconBg     = guildIcon:CreateTexture("GuildOSTabardBg",     "BACKGROUND")
    local guildIconBorder = guildIcon:CreateTexture("GuildOSTabardBorder", "BORDER")
    local guildIconEmblem = guildIcon:CreateTexture("GuildOSTabardEmblem", "ARTWORK")
    guildIconBg:SetAllPoints(guildIcon)
    guildIconBorder:SetAllPoints(guildIcon)
    guildIconEmblem:SetAllPoints(guildIcon)

    local function UpdateGuildIcon()
        if IsInGuild() then
            -- Pass global texture names — TBC Classic (bg, border, emblem) order.
            SetGuildTabardTextures("GuildOSTabardBg", "GuildOSTabardBorder", "GuildOSTabardEmblem")
            if guildIconEmblem:GetTexture() then
                guildIconEmblem:SetVertexColor(1, 1, 1)
                return
            end
        end
        -- No guild, or guild has no purchased tabard — show generic guild logo
        guildIconBg:SetTexture(nil)
        guildIconBorder:SetTexture(nil)
        guildIconEmblem:SetTexture("Interface\\GuildFrame\\GuildLogo-NoLogo")
        guildIconEmblem:SetVertexColor(C.gold.r, C.gold.g, C.gold.b)
    end
    frame.UpdateGuildIcon = UpdateGuildIcon
    frame:HookScript("OnShow", UpdateGuildIcon)

    -- Title text
    local title = UI:CreateTitle(titleBar, "|cffFFD700Guild|r |cffD4AC0DOS|r", 20)
    title:SetPoint("LEFT", guildIcon, "RIGHT", 8, 2)

    -- Subtitle (guild name)
    local subtitle = UI:CreateText(titleBar, "", 11, C.silver.r, C.silver.g, C.silver.b)
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
    frame.subtitle = subtitle

    -- Version tag
    local versionTag = UI:CreateText(titleBar, "v" .. BRutus.VERSION, 9, C.accentDim.r, C.accentDim.g, C.accentDim.b)
    versionTag:SetPoint("LEFT", title, "RIGHT", 10, -10)

    -- Close button
    local closeBtn = UI:CreateCloseButton(titleBar)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -10)
    closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Sync button
    local syncBtn = UI:CreateButton(titleBar, "Sync", 70, 24)
    syncBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    syncBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    syncBtn:SetScript("OnClick", function()
        if BRutus.CommSystem then
            BRutus.CommSystem:FullSync()
        end
    end)

    -- Title accent line
    local titleLine = UI:CreateAccentLine(frame, 2)
    titleLine:SetPoint("TOPLEFT", 0, -44)
    titleLine:SetPoint("TOPRIGHT", 0, -44)

    ----------------------------------------------------------------
    -- Tab Bar
    ----------------------------------------------------------------
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", 0, -(44 + 2))
    tabBar:SetPoint("TOPRIGHT", 0, -(44 + 2))
    tabBar:SetHeight(TAB_HEIGHT)

    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    tabBarBg:SetAllPoints()
    tabBarBg:SetVertexColor(0.06, 0.06, 0.10, 1.0)

    frame.tabs = {}
    frame.tabPanels = {}
    frame.activeTab = nil

    -- Content area starts below tab bar
    local contentTop = -(44 + 2 + TAB_HEIGHT)

    local function CreateTab(key, label, officerOnly, condition)
        local idx = #frame.tabs + 1
        local tab = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        tab:SetSize(100, TAB_HEIGHT)
        tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        tab:SetBackdropColor(0.10, 0.10, 0.16, 1.0)
        tab:SetFrameLevel(tabBar:GetFrameLevel() + 2)

        if idx == 1 then
            tab:SetPoint("LEFT", 4, 0)
        else
            tab:SetPoint("LEFT", frame.tabs[idx - 1], "RIGHT", 2, 0)
        end

        local tabLabel = tab:CreateFontString(nil, "OVERLAY")
        tabLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        tabLabel:SetPoint("CENTER")
        tabLabel:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        tabLabel:SetText(label)
        tab.label = tabLabel
        tab.key = key
        tab.officerOnly = officerOnly
        tab.condition   = condition  -- optional function() → bool; overrides officerOnly when present

        tab:SetScript("OnClick", function()
            frame:SetActiveTab(key)
        end)
        tab:SetScript("OnEnter", function(self)
            if frame.activeTab ~= self.key then
                self:SetBackdropColor(0.16, 0.14, 0.24, 1.0)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if frame.activeTab ~= self.key then
                self:SetBackdropColor(0.10, 0.10, 0.16, 1.0)
            end
        end)

        frame.tabs[idx] = tab
        return tab
    end

    function frame:SetActiveTab(key)
        self.activeTab = key
        for _, tab in ipairs(self.tabs) do
            if tab.key == key then
                tab:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)
                tab.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            else
                tab:SetBackdropColor(0.10, 0.10, 0.16, 1.0)
                tab.label:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            end
        end
        for k, panel in pairs(self.tabPanels) do
            if k == key then
                panel:Show()
            else
                panel:Hide()
            end
        end
    end

    function frame:UpdateTabVisibility()
        local prevTab = nil
        for _, tab in ipairs(self.tabs) do
            local visible = true
            if tab.condition then
                visible = tab.condition()
            elseif tab.officerOnly then
                visible = BRutus:IsOfficer()
            end
            if visible then
                tab:ClearAllPoints()
                if prevTab then
                    tab:SetPoint("LEFT", prevTab, "RIGHT", 2, 0)
                else
                    tab:SetPoint("LEFT", 4, 0)
                end
                tab:Show()
                prevTab = tab
            else
                -- If this was the active tab, clear active so we can fall back.
                if self.activeTab == tab.key then
                    self.activeTab = nil
                end
                tab:Hide()
            end
        end
        -- Fall back to roster if the previously active tab is now hidden.
        if not self.activeTab then
            self:SetActiveTab("roster")
        end
    end

    -- Create tabs
    CreateTab("roster", "Roster", false)
    CreateTab("recipes", "Recipes", false)
    if BRutus:IsOfficer() then
        CreateTab("wishlist", "Lista de Desejos", false)
    end
    CreateTab("raids", "Raids", false)
    CreateTab("loot", "Loot", true)  -- officers always see loot history; items recorded only via ML
    CreateTab("trials", "Trials", true)
    CreateTab("recruitment", "Recruitment", true)
    CreateTab("settings", "Settings", false)

    ----------------------------------------------------------------
    -- ROSTER PANEL
    ----------------------------------------------------------------
    local rosterPanel = CreateFrame("Frame", nil, frame)
    rosterPanel:SetPoint("TOPLEFT", 0, contentTop)
    rosterPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    frame.tabPanels["roster"] = rosterPanel

    -- Stats Bar
    local statsBar = CreateFrame("Frame", nil, rosterPanel)
    statsBar:SetPoint("TOPLEFT", 0, 0)
    statsBar:SetPoint("TOPRIGHT", 0, 0)
    statsBar:SetHeight(28)

    local statsBg = statsBar:CreateTexture(nil, "BACKGROUND")
    statsBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    statsBg:SetAllPoints()
    statsBg:SetVertexColor(0.06, 0.06, 0.10, 1.0)

    local totalText = UI:CreateText(statsBar, "", 10, C.silver.r, C.silver.g, C.silver.b)
    totalText:SetPoint("LEFT", 12, 0)
    frame.totalText = totalText

    local onlineText = UI:CreateText(statsBar, "", 10, C.online.r, C.online.g, C.online.b)
    onlineText:SetPoint("LEFT", totalText, "RIGHT", 20, 0)
    frame.onlineText = onlineText

    local addonText = UI:CreateText(statsBar, "", 10, C.accent.r, C.accent.g, C.accent.b)
    addonText:SetPoint("LEFT", onlineText, "RIGHT", 20, 0)
    frame.addonText = addonText

    -- Filter: Show offline toggle
    local offlineBtn = UI:CreateButton(statsBar, "Show Offline", 100, 22)
    offlineBtn:SetPoint("RIGHT", -12, 0)
    offlineBtn.isToggled = true
    offlineBtn:SetScript("OnClick", function(self)
        self.isToggled = not self.isToggled
        BRutus.db.settings.showOffline = self.isToggled
        if self.isToggled then
            self.label:SetText("Show Offline")
            self:SetBackdropColor(C.accentDim.r, C.accentDim.g, C.accentDim.b, 0.6)
        else
            self.label:SetText("Online Only")
            self:SetBackdropColor(C.online.r * 0.3, C.online.g * 0.3, C.online.b * 0.3, 0.6)
        end
        frame:RefreshRoster()
    end)
    frame.offlineBtn = offlineBtn

    -- Search box
    local searchBox = CreateFrame("EditBox", "BRutusSearchBox", statsBar, "BackdropTemplate")
    searchBox:SetSize(160, 22)
    searchBox:SetPoint("RIGHT", offlineBtn, "LEFT", -10, 0)
    searchBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    searchBox:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
    searchBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    searchBox:SetTextInsets(8, 8, 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(30)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY")
    searchPlaceholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchPlaceholder:SetPoint("LEFT", 8, 0)
    searchPlaceholder:SetTextColor(0.4, 0.4, 0.4)
    searchPlaceholder:SetText("Search...")

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            searchPlaceholder:Hide()
        else
            searchPlaceholder:Show()
        end
        frame.searchFilter = text
        frame:RefreshRoster()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.searchBox = searchBox

    -- Column Headers
    local headerFrame = CreateFrame("Frame", nil, rosterPanel)
    headerFrame:SetPoint("TOPLEFT", 0, -28)
    headerFrame:SetPoint("TOPRIGHT", 0, -28)
    headerFrame:SetHeight(HEADER_HEIGHT)

    local headerBg = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    headerBg:SetAllPoints()
    headerBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    local xOff = 10
    frame.headerButtons = {}
    for _, col in ipairs(COLUMNS) do
        if col.label ~= "" then
            local btn = CreateFrame("Button", nil, headerFrame)
            btn:SetSize(col.width, HEADER_HEIGHT)
            btn:SetPoint("LEFT", xOff, 0)

            local text = UI:CreateHeaderText(btn, col.label, 10)
            if col.align == "CENTER" then
                text:SetPoint("CENTER")
            elseif col.align == "RIGHT" then
                text:SetPoint("RIGHT")
            else
                text:SetPoint("LEFT")
            end
            btn.text = text

            -- Sort indicator
            local sortArrow = btn:CreateFontString(nil, "OVERLAY")
            sortArrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            sortArrow:SetPoint("LEFT", text, "RIGHT", 3, 0)
            sortArrow:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
            sortArrow:Hide()
            btn.sortArrow = sortArrow

            btn:SetScript("OnClick", function()
                local db = BRutus.db.settings
                if db.sortBy == col.key then
                    db.sortAsc = not db.sortAsc
                else
                    db.sortBy = col.key
                    db.sortAsc = (col.key == "name")
                end
                frame:RefreshRoster()
            end)

            btn:SetScript("OnEnter", function(self)
                self.text:SetTextColor(C.white.r, C.white.g, C.white.b)
            end)
            btn:SetScript("OnLeave", function(self)
                self.text:SetTextColor(C.gold.r, C.gold.g, C.gold.b, 0.9)
            end)

            frame.headerButtons[col.key] = btn
        end
        xOff = xOff + col.width
    end

    -- Header bottom line
    local headerLine = UI:CreateSeparator(rosterPanel)
    headerLine:SetPoint("TOPLEFT", 0, -(28 + HEADER_HEIGHT))
    headerLine:SetPoint("TOPRIGHT", 0, -(28 + HEADER_HEIGHT))

    -- Scroll Frame for roster rows
    local rosterContainer = CreateFrame("Frame", "BRutusRosterContainer", rosterPanel)
    rosterContainer:SetPoint("TOPLEFT", 1, -(28 + HEADER_HEIGHT + 1))
    rosterContainer:SetPoint("BOTTOMRIGHT", -1, 0)

    local scrollFrame = CreateFrame("ScrollFrame", "BRutusRosterScroll", rosterContainer, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(scrollFrame, "BRutusRosterScroll")

    frame.scrollFrame = scrollFrame
    frame.rows = {}

    for i = 1, VISIBLE_ROWS do
        frame.rows[i] = CreateRosterRow(rosterContainer, i)
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            frame:UpdateRows()
        end)
    end)

    ----------------------------------------------------------------
    -- RECIPES PANEL
    ----------------------------------------------------------------
    local recipesPanel = CreateFrame("Frame", nil, frame)
    recipesPanel:SetPoint("TOPLEFT", 0, contentTop)
    recipesPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    recipesPanel:Hide()
    frame.tabPanels["recipes"] = recipesPanel
    BRutus:CreateRecipesPanel(recipesPanel, frame)

    ----------------------------------------------------------------
    -- RECRUITMENT PANEL (officer only)
    ----------------------------------------------------------------
    local recruitPanel = CreateFrame("Frame", nil, frame)
    recruitPanel:SetPoint("TOPLEFT", 0, contentTop)
    recruitPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    recruitPanel:Hide()
    frame.tabPanels["recruitment"] = recruitPanel
    BRutus:CreateRecruitmentPanel(recruitPanel, frame)

    ----------------------------------------------------------------
    -- LISTA DE DESEJOS (WISHLIST) PANEL
    ----------------------------------------------------------------
    local wishlistPanel = CreateFrame("Frame", nil, frame)
    wishlistPanel:SetPoint("TOPLEFT", 0, contentTop)
    wishlistPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    wishlistPanel:Hide()
    frame.tabPanels["wishlist"] = wishlistPanel
    BRutus:CreateWishlistGuildPanel(wishlistPanel, frame)

    ----------------------------------------------------------------
    -- RAID ATTENDANCE PANEL
    ----------------------------------------------------------------
    local raidsPanel = CreateFrame("Frame", nil, frame)
    raidsPanel:SetPoint("TOPLEFT", 0, contentTop)
    raidsPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    raidsPanel:Hide()
    frame.tabPanels["raids"] = raidsPanel
    BRutus:CreateRaidsPanel(raidsPanel, frame)

    ----------------------------------------------------------------
    -- LOOT HISTORY PANEL
    ----------------------------------------------------------------
    local lootPanel = CreateFrame("Frame", nil, frame)
    lootPanel:SetPoint("TOPLEFT", 0, contentTop)
    lootPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    lootPanel:Hide()
    frame.tabPanels["loot"] = lootPanel
    BRutus:CreateLootPanel(lootPanel, frame)

    ----------------------------------------------------------------
    -- TRIAL TRACKER PANEL (officer only)
    ----------------------------------------------------------------
    local trialsPanel = CreateFrame("Frame", nil, frame)
    trialsPanel:SetPoint("TOPLEFT", 0, contentTop)
    trialsPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    trialsPanel:Hide()
    frame.tabPanels["trials"] = trialsPanel
    BRutus:CreateTrialsPanel(trialsPanel, frame)

    ----------------------------------------------------------------
    -- SETTINGS PANEL
    ----------------------------------------------------------------
    local settingsPanel = CreateFrame("Frame", nil, frame)
    settingsPanel:SetPoint("TOPLEFT", 0, contentTop)
    settingsPanel:SetPoint("BOTTOMRIGHT", 0, 30)
    settingsPanel:Hide()
    frame.tabPanels["settings"] = settingsPanel
    BRutus:CreateSettingsPanel(settingsPanel, frame)

    ----------------------------------------------------------------
    -- Bottom Bar
    ----------------------------------------------------------------
    local bottomBar = CreateFrame("Frame", nil, frame)
    bottomBar:SetPoint("BOTTOMLEFT", 0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", 0, 0)
    bottomBar:SetHeight(30)

    local bottomBg = bottomBar:CreateTexture(nil, "BACKGROUND")
    bottomBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bottomBg:SetAllPoints()
    bottomBg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 1.0)

    local bottomLine = UI:CreateAccentLine(frame, 1)
    bottomLine:SetPoint("BOTTOMLEFT", 0, 30)
    bottomLine:SetPoint("BOTTOMRIGHT", 0, 30)

    local helpText = UI:CreateText(bottomBar, "/guildos scan  |  /guildos sync  |  /guildos wish", 9, 0.4, 0.4, 0.5)
    helpText:SetPoint("LEFT", 12, 0)

    -- "Minha Wishlist" quick-access button (all members)
    local wishBtn = UI:CreateButton(bottomBar, "Minha Wishlist", 120, 22)
    wishBtn:SetPoint("LEFT", helpText, "RIGHT", 16, 0)
    wishBtn:SetScript("OnClick", function() BRutus:ShowWishlistFrame() end)

    -- Guild Invite (visible only if player can invite)
    local inviteBox = CreateFrame("EditBox", nil, bottomBar, "BackdropTemplate")
    inviteBox:SetSize(140, 22)
    inviteBox:SetPoint("RIGHT", -90, 0)
    inviteBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    inviteBox:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
    inviteBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    inviteBox:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    inviteBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    inviteBox:SetTextInsets(6, 6, 0, 0)
    inviteBox:SetAutoFocus(false)
    inviteBox:SetMaxLetters(50)

    local invitePlaceholder = inviteBox:CreateFontString(nil, "OVERLAY")
    invitePlaceholder:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    invitePlaceholder:SetPoint("LEFT", 6, 0)
    invitePlaceholder:SetTextColor(0.4, 0.4, 0.4)
    invitePlaceholder:SetText("Player name...")

    inviteBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            invitePlaceholder:Hide()
        else
            invitePlaceholder:Show()
        end
    end)

    local inviteBtn = UI:CreateButton(bottomBar, "Invite", 70, 22)
    inviteBtn:SetPoint("RIGHT", -12, 0)

    local function DoInvite()
        local target = strtrim(inviteBox:GetText() or "")
        if target == "" then
            BRutus:Print("Enter a player name to invite.")
            return
        end
        GuildInvite(target)
        BRutus:Print("Guild invite sent to " .. target .. ".")
        inviteBox:SetText("")
        inviteBox:ClearFocus()
    end

    inviteBtn:SetScript("OnClick", DoInvite)
    inviteBox:SetScript("OnEnterPressed", function(self)
        DoInvite()
        self:ClearFocus()
    end)
    inviteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    frame.inviteBox = inviteBox
    frame.inviteBtn = inviteBtn

    -- Show/hide invite based on permission
    local function UpdateInviteVisibility()
        if CanGuildInvite() then
            inviteBox:Show()
            inviteBtn:Show()
        else
            inviteBox:Hide()
            inviteBtn:Hide()
        end
    end

    frame:HookScript("OnShow", UpdateInviteVisibility)

    ----------------------------------------------------------------
    -- Data & Methods
    ----------------------------------------------------------------
    frame.sortedMembers = {}
    frame.searchFilter = ""

    function frame:RefreshRoster()
        self:BuildMemberList()
        self:UpdateSortIndicators()
        self:UpdateRows()
        self:UpdateStats()
    end

    function frame:BuildMemberList()
        -- Reuse the existing table to avoid allocating a new one on every refresh.
        wipe(self.sortedMembers)
        local members = self.sortedMembers
        local showOffline = BRutus.db.settings.showOffline
        local filter = self.searchFilter and strlower(strtrim(self.searchFilter)) or ""

        -- Get guild roster info
        local numMembers = GetNumGuildMembers()
        for i = 1, numMembers do
            local name, rankName, rankIndex, level, classLoc, zone, note,
                  officerNote, isOnline, status, classFile = GetGuildRosterInfo(i)

            if name then
                -- Strip realm from name for display
                local displayName = name:match("^([^-]+)") or name
                local realm = name:match("-(.+)$") or GetRealmName()
                local key = BRutus:GetPlayerKey(displayName, realm)

                -- Apply filters
                local passFilter = true
                if not showOffline and not isOnline then
                    passFilter = false
                end
                if filter ~= "" then
                    local searchTarget = strlower(displayName .. " " .. (classLoc or "") .. " " .. (zone or "") .. " " .. (rankName or ""))
                    if not searchTarget:find(filter, 1, true) then
                        passFilter = false
                    end
                end

                if passFilter then
                    -- Merge with stored addon data
                    local addonData = BRutus.db.members[key] or {}

                    table.insert(members, {
                        index = i,
                        key = key,
                        name = displayName,
                        fullName = name,
                        realm = realm,
                        rank = rankName,
                        rankIndex = rankIndex,
                        level = level or 0,
                        class = classFile or "",
                        classDisplay = classLoc or "",
                        zone = zone or "",
                        note = note or "",
                        officerNote = officerNote or "",
                        isOnline = isOnline,
                        status = status or "",
                        -- Addon data
                        avgIlvl = addonData.avgIlvl or 0,
                        gear = addonData.gear,
                        professions = addonData.professions,
                        attunements = addonData.attunements,
                        stats = addonData.stats,
                        race = addonData.race or "",
                        lastUpdate = addonData.lastUpdate or 0,
                        lastSync = addonData.lastSync or 0,
                        addonVersion = addonData.addonVersion,
                        hasAddonData = (addonData.lastUpdate ~= nil and addonData.lastUpdate ~= 0),
                    })
                end
            end
        end

        -- Sort
        local sortBy = BRutus.db.settings.sortBy or "level"
        local sortAsc = BRutus.db.settings.sortAsc

        table.sort(members, function(a, b)
            -- Online always first
            if a.isOnline ~= b.isOnline then
                return a.isOnline
            end

            local va, vb
            if sortBy == "name" then
                va, vb = a.name:lower(), b.name:lower()
            elseif sortBy == "level" then
                va, vb = a.level, b.level
            elseif sortBy == "class" then
                va, vb = a.classDisplay:lower(), b.classDisplay:lower()
            elseif sortBy == "race" then
                va, vb = a.race:lower(), b.race:lower()
            elseif sortBy == "avgIlvl" then
                va, vb = a.avgIlvl, b.avgIlvl
            elseif sortBy == "lastSeen" then
                va, vb = a.lastUpdate, b.lastUpdate
            elseif sortBy == "attendance" then
                local pa = BRutus.RaidTracker and BRutus.RaidTracker:GetAttendance25ManPercent(a.key) or 0
                local pb = BRutus.RaidTracker and BRutus.RaidTracker:GetAttendance25ManPercent(b.key) or 0
                va, vb = pa, pb
            else
                va, vb = a.level, b.level
            end

            if va == vb then
                return a.name:lower() < b.name:lower()
            end

            if sortAsc then
                return va < vb
            else
                return va > vb
            end
        end)
    end

    function frame:UpdateSortIndicators()
        local sortBy = BRutus.db.settings.sortBy
        local sortAsc = BRutus.db.settings.sortAsc

        for key, btn in pairs(self.headerButtons) do
            if key == sortBy then
                btn.sortArrow:SetText(sortAsc and "|TInterface\\BUTTONS\\Arrow-Up-Up:12:12|t" or "|TInterface\\BUTTONS\\Arrow-Down-Up:12:12|t")
                btn.sortArrow:Show()
            else
                btn.sortArrow:Hide()
            end
        end
    end

    function frame:UpdateRows()
        local members = self.sortedMembers
        local numMembers = #members
        local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

        FauxScrollFrame_Update(self.scrollFrame, numMembers, VISIBLE_ROWS, ROW_HEIGHT)

        for i = 1, VISIBLE_ROWS do
            local row = self.rows[i]
            local dataIndex = offset + i

            if dataIndex <= numMembers then
                local data = members[dataIndex]
                UpdateRosterRow(row, data, i)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    function frame:UpdateStats()
        local numTotal = GetNumGuildMembers()
        local numOnline = 0
        local numWithAddon = 0

        for i = 1, numTotal do
            local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if isOnline then numOnline = numOnline + 1 end
        end

        -- Count members with addon data
        for _, data in pairs(BRutus.db.members) do
            if data.lastUpdate and data.lastUpdate > 0 then
                numWithAddon = numWithAddon + 1
            end
        end

        -- Update guild name in subtitle
        local guildName = GetGuildInfo("player")
        if guildName then
            self.subtitle:SetText("< " .. guildName .. " >")
        end

        -- Refresh guild emblem
        if self.UpdateGuildIcon then self.UpdateGuildIcon() end

        self.totalText:SetText("Members: |cffFFFFFF" .. numTotal .. "|r")
        self.onlineText:SetText("Online: |cff4CFF4C" .. numOnline .. "|r")
        self.addonText:SetText("Guild OS: |cff8060FF" .. numWithAddon .. "|r")
    end

    -- ESC to close
    table.insert(UISpecialFrames, "BRutusRosterFrame")

    -- Re-evaluate conditional tabs when group or loot method changes.
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
    -- Refresh guild emblem when tabard/guild data becomes available
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function(self, event)
        if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
            if self.UpdateGuildIcon then self.UpdateGuildIcon() end
        else
            self:UpdateTabVisibility()
        end
    end)

    -- Initialize tab system
    frame:UpdateTabVisibility()
    frame:SetActiveTab("roster")

    return frame
end

----------------------------------------------------------------------
-- Create a single roster row
----------------------------------------------------------------------
function CreateRosterRow(parent, rowIndex)
    local row = CreateFrame("Button", "BRutusRow" .. rowIndex, parent, "BackdropTemplate")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((rowIndex - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })

    -- Alternating row colors
    local bgColor = (rowIndex % 2 == 0) and C.row2 or C.row1
    row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    row.defaultBg = bgColor

    -- Row elements
    local xOff = 10

    -- Status indicator (online dot)
    local statusDot = row:CreateTexture(nil, "OVERLAY")
    statusDot:SetSize(8, 8)
    statusDot:SetPoint("LEFT", xOff + 6, 0)
    statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
    row.statusDot = statusDot
    xOff = xOff + COLUMNS[1].width

    -- Class icon + Name
    local classIcon = row:CreateTexture(nil, "OVERLAY")
    classIcon:SetSize(20, 20)
    classIcon:SetPoint("LEFT", xOff, 0)
    classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.classIcon = classIcon

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    nameText:SetPoint("LEFT", classIcon, "RIGHT", 5, 0)
    nameText:SetWidth(COLUMNS[2].width - 28)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    -- Addon indicator (tiny dot)
    local addonDot = row:CreateTexture(nil, "OVERLAY")
    addonDot:SetSize(6, 6)
    addonDot:SetPoint("LEFT", nameText, "RIGHT", 2, 0)
    addonDot:SetTexture("Interface\\Buttons\\WHITE8x8")
    addonDot:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.8)
    addonDot:Hide()
    row.addonDot = addonDot
    xOff = xOff + COLUMNS[2].width

    -- Level
    local levelText = row:CreateFontString(nil, "OVERLAY")
    levelText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    levelText:SetPoint("LEFT", xOff, 0)
    levelText:SetWidth(COLUMNS[3].width)
    levelText:SetJustifyH("CENTER")
    row.levelText = levelText
    xOff = xOff + COLUMNS[3].width

    -- Class name
    local classText = row:CreateFontString(nil, "OVERLAY")
    classText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    classText:SetPoint("LEFT", xOff, 0)
    classText:SetWidth(COLUMNS[4].width)
    classText:SetJustifyH("LEFT")
    row.classText = classText
    xOff = xOff + COLUMNS[4].width

    -- Race
    local raceText = row:CreateFontString(nil, "OVERLAY")
    raceText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    raceText:SetPoint("LEFT", xOff, 0)
    raceText:SetWidth(COLUMNS[5].width)
    raceText:SetJustifyH("LEFT")
    raceText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    row.raceText = raceText
    xOff = xOff + COLUMNS[5].width

    -- Average iLvl
    local ilvlText = row:CreateFontString(nil, "OVERLAY")
    ilvlText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    ilvlText:SetPoint("LEFT", xOff, 0)
    ilvlText:SetWidth(COLUMNS[6].width)
    ilvlText:SetJustifyH("CENTER")
    row.ilvlText = ilvlText
    xOff = xOff + COLUMNS[6].width

    -- Professions
    local profText = row:CreateFontString(nil, "OVERLAY")
    profText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    profText:SetPoint("LEFT", xOff, 0)
    profText:SetWidth(COLUMNS[7].width)
    profText:SetJustifyH("LEFT")
    profText:SetWordWrap(false)
    row.profText = profText
    xOff = xOff + COLUMNS[7].width

    -- Attunements
    local attText = row:CreateFontString(nil, "OVERLAY")
    attText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    attText:SetPoint("LEFT", xOff, 0)
    attText:SetWidth(COLUMNS[8].width)
    attText:SetJustifyH("LEFT")
    attText:SetWordWrap(false)
    row.attText = attText
    xOff = xOff + COLUMNS[8].width

    -- Attendance %
    local attPctText = row:CreateFontString(nil, "OVERLAY")
    attPctText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    attPctText:SetPoint("LEFT", xOff, 0)
    attPctText:SetWidth(COLUMNS[9].width)
    attPctText:SetJustifyH("CENTER")
    row.attPctText = attPctText
    xOff = xOff + COLUMNS[9].width

    -- Zone
    local zoneText = row:CreateFontString(nil, "OVERLAY")
    zoneText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    zoneText:SetPoint("LEFT", xOff, 0)
    zoneText:SetWidth(COLUMNS[10].width)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetWordWrap(false)
    row.zoneText = zoneText
    xOff = xOff + COLUMNS[10].width

    -- Last Seen
    local lastSeenText = row:CreateFontString(nil, "OVERLAY")
    lastSeenText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    lastSeenText:SetPoint("LEFT", xOff, 0)
    lastSeenText:SetWidth(COLUMNS[11].width)
    lastSeenText:SetJustifyH("RIGHT")
    lastSeenText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    row.lastSeenText = lastSeenText

    -- Hover effects
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
        if self.memberData then
            ShowRowTooltip(self)
        end
    end)
    row:SetScript("OnLeave", function(self)
        local bg = self.defaultBg
        self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        GameTooltip:Hide()
    end)

    -- Click: left = detail, right = context menu
    row:SetScript("OnClick", function(self, button)
        if not self.memberData then return end
        if button == "RightButton" then
            BRutus:ShowMemberContextMenu(self, self.memberData)
        else
            BRutus:ShowMemberDetail(self.memberData)
        end
    end)

    return row
end

----------------------------------------------------------------------
-- Update a roster row with member data
----------------------------------------------------------------------
function UpdateRosterRow(row, data, rowIndex)
    row.memberData = data

    -- Alternating backgrounds
    local bgColor = (rowIndex % 2 == 0) and C.row2 or C.row1
    row.defaultBg = bgColor
    row:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

    -- Grayscale helper for offline members
    local function textColor(r, g, b)
        if data.isOnline then
            return r, g, b
        else
            local gray = r * 0.299 + g * 0.587 + b * 0.114
            return gray, gray, gray
        end
    end

    -- Online status
    if data.isOnline then
        row.statusDot:SetTexture("Interface\\COMMON\\Indicator-Green")
        row.statusDot:SetVertexColor(C.online.r, C.online.g, C.online.b)
    else
        row.statusDot:SetTexture("Interface\\COMMON\\Indicator-Gray")
        row.statusDot:SetVertexColor(C.offline.r, C.offline.g, C.offline.b)
    end

    -- Class icon
    local classCoords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class]
    if classCoords then
        row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        row.classIcon:SetTexCoord(unpack(classCoords))
        row.classIcon:SetDesaturated(not data.isOnline)
    else
        row.classIcon:SetTexture("")
    end

    -- Name (class-colored, grayscale if offline)
    local cr, cg, cb = BRutus:GetClassColor(data.class)
    local nr, ng, nb = textColor(cr, cg, cb)
    row.nameText:SetText(data.name)
    row.nameText:SetTextColor(nr, ng, nb)

    -- Addon data indicator
    if data.hasAddonData then
        row.addonDot:Show()
        if data.addonVersion and data.addonVersion ~= BRutus.VERSION then
            row.addonDot:SetVertexColor(C.red.r, C.red.g, C.red.b, 0.9)
        else
            row.addonDot:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.8)
        end
    else
        row.addonDot:Hide()
    end

    -- Level with color coding
    local level = data.level
    local lr, lg, lb
    if level >= 70 then
        lr, lg, lb = C.gold.r, C.gold.g, C.gold.b
    elseif level >= 60 then
        lr, lg, lb = C.green.r, C.green.g, C.green.b
    else
        lr, lg, lb = C.white.r, C.white.g, C.white.b
    end
    row.levelText:SetTextColor(textColor(lr, lg, lb))
    row.levelText:SetText(level)

    -- Class display
    row.classText:SetText(data.classDisplay)
    row.classText:SetTextColor(textColor(cr, cg, cb))

    -- Race
    row.raceText:SetText(data.race ~= "" and data.race or "-")
    row.raceText:SetTextColor(textColor(C.silver.r, C.silver.g, C.silver.b))

    -- Average iLvl
    if data.avgIlvl and data.avgIlvl > 0 then
        row.ilvlText:SetText(BRutus:FormatItemLevel(data.avgIlvl))
    else
        row.ilvlText:SetText("|cff666666-|r")
    end

    -- Professions
    if data.professions and #data.professions > 0 then
        local parts = {}
        for _, prof in ipairs(data.professions) do
            if prof.isPrimary then
                local pr, pg, pb = textColor(C.gold.r, C.gold.g, C.gold.b)
                table.insert(parts, BRutus:ColorText(prof.name:sub(1, 5) .. " " .. prof.rank, pr, pg, pb))
            end
        end
        row.profText:SetText(table.concat(parts, " / "))
    else
        row.profText:SetText("|cff666666No data|r")
    end

    -- Attunements
    if data.attunements and #data.attunements > 0 then
        row.attText:SetText(BRutus.AttunementTracker:GetAttunementSummary(data.key))
    else
        row.attText:SetText("|cff666666No data|r")
    end

    -- Attendance %
    if BRutus.RaidTracker then
        local pct = BRutus.RaidTracker:GetAttendance25ManPercent(data.key)
        if pct > 0 then
            local ar, ag, ab
            if pct >= 75 then
                ar, ag, ab = textColor(C.green.r, C.green.g, C.green.b)
            elseif pct >= 50 then
                ar, ag, ab = textColor(C.gold.r, C.gold.g, C.gold.b)
            else
                ar, ag, ab = textColor(C.red.r, C.red.g, C.red.b)
            end
            row.attPctText:SetTextColor(ar, ag, ab)
            row.attPctText:SetText(pct .. "%")
        else
            row.attPctText:SetText("|cff666666-|r")
        end
    else
        row.attPctText:SetText("")
    end

    -- Zone (only shown for online members)
    if data.isOnline and data.zone and data.zone ~= "" then
        row.zoneText:SetTextColor(textColor(C.silver.r, C.silver.g, C.silver.b))
        row.zoneText:SetText(data.zone)
    else
        row.zoneText:SetText("|cff666666-|r")
    end

    -- Last seen
    if data.isOnline then
        row.lastSeenText:SetText("|cff4CFF4CNow|r")
    elseif data.lastUpdate > 0 then
        row.lastSeenText:SetText(BRutus:TimeAgo(data.lastUpdate))
    else
        row.lastSeenText:SetText("-")
    end
end

----------------------------------------------------------------------
-- Right-click context menu (mimics default guild roster menu)
----------------------------------------------------------------------
local memberDropdown = CreateFrame("Frame", "BRutusMemberDropdown", UIParent, "UIDropDownMenuTemplate")

local function MemberDropdown_Initialize(self, level)
    local data = self.memberData
    if not data then return end

    local info = UIDropDownMenu_CreateInfo()
    local myName = UnitName("player")
    local isMe = (data.name == myName)

    -- Header: player name
    info.text = data.name
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true

    -- Whisper
    if not isMe and data.isOnline then
        info.text = WHISPER_MESSAGE or "Whisper"
        info.func = function()
            ChatFrame_SendTell(data.name)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Invite to group
    if not isMe and data.isOnline then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = PARTY_INVITE or "Invite"
        info.func = function()
            -- Classic/TBC uses InviteByName for name-based invites
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(data.name)
            elseif InviteByName then
                InviteByName(data.name)
            else
                -- Fallback: target player first, then invite
                TargetUnit(data.name)
                InviteUnit("target")
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Inspect (target must be nearby)
    if not isMe and data.isOnline then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = INSPECT or "Inspect"
        info.func = function()
            InspectUnit(data.name)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Guild promote (if we can)
    if not isMe and IsGuildLeader and IsGuildLeader() then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = GUILD_PROMOTE or "Promote"
        info.func = function()
            GuildPromote(data.name)
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = GUILD_DEMOTE or "Demote"
        info.func = function()
            GuildDemote(data.name)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Guild remove (if we can)
    if not isMe and CanGuildRemove and CanGuildRemove() then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = GUILD_UNINVITE or "Remove from guild"
        info.func = function()
            GuildUninvite(data.name)
        end
        UIDropDownMenu_AddButton(info, level)
    end

    -- Who
    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = WHO or "Who"
    info.func = function()
        SendWho("n-" .. data.name)
    end
    UIDropDownMenu_AddButton(info, level)

    -- View detail
    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = "Guild OS Detail"
    info.func = function()
        BRutus:ShowMemberDetail(data)
    end
    UIDropDownMenu_AddButton(info, level)

    -- Officer actions
    if not isMe and BRutus:IsOfficer() then
        -- Mark as trial
        if BRutus.TrialTracker then
            local key = data.key or BRutus:GetPlayerKey(data.name, data.realm or GetRealmName())
            if not BRutus.TrialTracker:IsTrial(key) then
                info = UIDropDownMenu_CreateInfo()
                info.notCheckable = true
                info.text = "|cffFFAA00Mark as Trial|r"
                info.func = function()
                    BRutus.TrialTracker:AddTrial(key)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- Add officer note
        if BRutus.OfficerNotes then
            info = UIDropDownMenu_CreateInfo()
            info.notCheckable = true
            info.text = "|cff8888FFAdd Note|r"
            info.func = function()
                -- Simple note via chat input
                BRutus:Print("Use: /guildos note " .. data.name .. " <your note>")
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    -- Cancel
    info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = CANCEL or "Cancel"
    UIDropDownMenu_AddButton(info, level)
end

function BRutus:ShowMemberContextMenu(_anchor, memberData)
    memberDropdown.memberData = memberData
    UIDropDownMenu_Initialize(memberDropdown, MemberDropdown_Initialize, "MENU")
    ToggleDropDownMenu(1, nil, memberDropdown, "cursor", 3, -3)
end

----------------------------------------------------------------------
-- Row tooltip (rich info on hover)
----------------------------------------------------------------------
function ShowRowTooltip(row)
    local data = row.memberData
    if not data then return end

    GameTooltip:SetOwner(row, "ANCHOR_BOTTOM", 0, -5)

    -- Header: Name colored by class
    local cr, cg, cb = BRutus:GetClassColor(data.class)
    GameTooltip:AddLine(data.name, cr, cg, cb)
    GameTooltip:AddLine(string.format("Level %d %s %s", data.level, data.race, data.classDisplay), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(data.rank, C.gold.r, C.gold.g, C.gold.b)

    -- Talent spec
    if BRutus.SpecChecker then
        local memberKey = BRutus:GetPlayerKey(data.name, data.realm or GetRealmName())
        local specLabel = BRutus.SpecChecker:GetSpecLabel(memberKey)
        if specLabel then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Spec: " .. specLabel, cr, cg, cb)
        end
    end

    if data.zone and data.zone ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Zone: " .. data.zone, C.silver.r, C.silver.g, C.silver.b)
    end

    if data.note and data.note ~= "" then
        GameTooltip:AddLine("Note: " .. data.note, 0.6, 0.6, 0.6, true)
    end

    -- Gear summary
    if data.avgIlvl and data.avgIlvl > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Average Item Level: " .. data.avgIlvl, C.accent.r, C.accent.g, C.accent.b)
    end

    -- Professions detail
    if data.professions and #data.professions > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Professions:", C.gold.r, C.gold.g, C.gold.b)
        for _, prof in ipairs(data.professions) do
            local profColor = prof.isPrimary and C.gold or C.silver
            GameTooltip:AddLine(string.format("  %s  %d / %d", prof.name, prof.rank, prof.maxRank),
                profColor.r, profColor.g, profColor.b)
        end
    end

    -- Attunement detail
    -- Uses GetEffectiveAttunements so only game-API-verified data is shown
    -- (no alt-propagation that could produce false "Done" for cross-account alts).
    local effAtts = BRutus.AttunementTracker:GetEffectiveAttunements(data.key)
    if effAtts and #effAtts > 0 then
        local done, inProg, pending = {}, {}, {}
        for _, att in ipairs(effAtts) do
            if att.complete then
                tinsert(done, att)
            elseif att.progress and att.progress > 0 then
                tinsert(inProg, att)
            else
                tinsert(pending, att)
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            string.format("Attunements: (%d/%d)", #done, #effAtts),
            C.gold.r, C.gold.g, C.gold.b)

        for _, att in ipairs(done) do
            GameTooltip:AddLine(
                string.format("  [%s] %s", att.tier, att.name) .. "  Done",
                C.green.r, C.green.g, C.green.b)
        end
        for _, att in ipairs(inProg) do
            GameTooltip:AddLine(
                string.format("  [%s] %s  %d%%", att.tier, att.name,
                    math.floor((att.progress or 0) * 100)),
                C.gold.r, C.gold.g, C.gold.b)
        end
        for _, att in ipairs(pending) do
            GameTooltip:AddLine(
                string.format("  [%s] %s  Not started", att.tier, att.name),
                C.red.r, C.red.g, C.red.b)
        end
    end

    if not data.hasAddonData then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Player does not have Guild OS installed", C.red.r, C.red.g, C.red.b)
    elseif data.addonVersion and data.addonVersion ~= BRutus.VERSION then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Guild OS v" .. data.addonVersion .. " (outdated)", C.red.r, C.red.g, C.red.b)
    end

    -- Wishlist info (native)
    if BRutus.db.guildWishlists then
        local gKey = strlower(data.name or "")
        local wData = BRutus.db.guildWishlists[gKey]
        if wData and wData.wishlist and #wData.wishlist > 0 then
            local wColor = BRutus.Wishlist and BRutus.Wishlist.TypeColors.wishlist or { r=0.3, g=0.7, b=1.0 }
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Wishlist:", C.gold.r, C.gold.g, C.gold.b)
            local shown = math.min(#wData.wishlist, 5)
            for j = 1, shown do
                local item = wData.wishlist[j]
                local iName = BRutus.Wishlist and BRutus.Wishlist:GetItemName(item.itemId) or ("Item #" .. (item.itemId or "?"))
                local os = item.isOffspec and " (OS)" or ""
                GameTooltip:AddLine("  #" .. (item.order or j) .. ": " .. iName .. os,
                    wColor.r, wColor.g, wColor.b)
            end
            if #wData.wishlist > 5 then
                GameTooltip:AddLine("  +" .. (#wData.wishlist - 5) .. " mais...", 0.5, 0.5, 0.5)
            end
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: detailed view", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Right-click: whisper, invite, etc.", 0.5, 0.5, 0.5)

    GameTooltip:Show()
end

----------------------------------------------------------------------
-- Lista de Desejos (Wishlist) Guild Panel UI
----------------------------------------------------------------------
function BRutus:CreateWishlistGuildPanel(parent, _mainFrame)
    local expandedChar = nil  -- key of currently expanded character

    ----------------------------------------------------------------
    -- Top bar: status text
    ----------------------------------------------------------------
    local topBar = CreateFrame("Frame", nil, parent)
    topBar:SetPoint("TOPLEFT", 15, -10)
    topBar:SetPoint("TOPRIGHT", -15, -10)
    topBar:SetHeight(30)

    local statusText = UI:CreateText(topBar, "", 11, C.white.r, C.white.g, C.white.b)
    statusText:SetPoint("LEFT", 5, 0)
    statusText:SetWidth(280)
    statusText:SetJustifyH("LEFT")

    -- "Minha Wishlist" button — open personal wishlist manager
    local myWishBtn = UI:CreateButton(topBar, "Minha Wishlist", 120, 24)
    myWishBtn:SetPoint("RIGHT", -140, 0)
    myWishBtn:SetScript("OnClick", function() BRutus:ShowWishlistFrame() end)

    -- "Gerenciar Prios" button — officer only, opens prio modal
    local managePrioBtn = UI:CreateButton(topBar, "Gerenciar Prios", 120, 24)
    managePrioBtn:SetPoint("RIGHT", -6, 0)
    managePrioBtn:SetScript("OnClick", function() BRutus:ShowPrioModal() end)

    -- Hide officer button for non-officers; refresh on show
    parent:HookScript("OnShow", function()
        if BRutus:IsOfficer() then
            managePrioBtn:Show()
        else
            managePrioBtn:Hide()
        end
    end)

    ----------------------------------------------------------------
    -- Search bar
    ----------------------------------------------------------------
    local searchBar = CreateFrame("Frame", nil, parent)
    searchBar:SetPoint("TOPLEFT", 15, -44)
    searchBar:SetPoint("TOPRIGHT", -15, -44)
    searchBar:SetHeight(26)

    local searchIcon = searchBar:CreateFontString(nil, "OVERLAY")
    searchIcon:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    searchIcon:SetPoint("LEFT", 8, 0)
    searchIcon:SetTextColor(C.silver.r, C.silver.g, C.silver.b, 0.5)
    searchIcon:SetText("Buscar:")

    local wishSearch = CreateFrame("EditBox", nil, searchBar, "BackdropTemplate")
    wishSearch:SetSize(200, 22)
    wishSearch:SetPoint("LEFT", searchIcon, "RIGHT", 8, 0)
    wishSearch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    wishSearch:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
    wishSearch:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    wishSearch:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    wishSearch:SetTextColor(C.white.r, C.white.g, C.white.b)
    wishSearch:SetTextInsets(6, 6, 0, 0)
    wishSearch:SetAutoFocus(false)
    wishSearch:SetMaxLetters(30)
    wishSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local wishSearchPlaceholder = wishSearch:CreateFontString(nil, "OVERLAY")
    wishSearchPlaceholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    wishSearchPlaceholder:SetPoint("LEFT", 6, 0)
    wishSearchPlaceholder:SetTextColor(0.4, 0.4, 0.4)
    wishSearchPlaceholder:SetText("Nome do jogador...")

    local charCountText = UI:CreateText(searchBar, "", 10, C.silver.r, C.silver.g, C.silver.b)
    charCountText:SetPoint("RIGHT", -5, 0)

    ----------------------------------------------------------------
    -- Column header
    ----------------------------------------------------------------
    local colHeader = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    colHeader:SetPoint("TOPLEFT", 15, -74)
    colHeader:SetPoint("TOPRIGHT", -15, -74)
    colHeader:SetHeight(20)
    colHeader:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    colHeader:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 0.8)

    local hName = UI:CreateHeaderText(colHeader, "Personagem", 10)
    hName:SetPoint("LEFT", 28, 0)
    local hClass = UI:CreateHeaderText(colHeader, "Classe", 10)
    hClass:SetPoint("LEFT", 180, 0)
    local hWish = UI:CreateHeaderText(colHeader, "Wishlist", 10)
    hWish:SetPoint("LEFT", 310, 0)
    local hAtt = UI:CreateHeaderText(colHeader, "Pres%", 10)
    hAtt:SetPoint("LEFT", 400, 0)

    ----------------------------------------------------------------
    -- Scrollable character list
    ----------------------------------------------------------------
    local listContainer = CreateFrame("Frame", nil, parent)
    listContainer:SetPoint("TOPLEFT", 15, -94)
    listContainer:SetPoint("BOTTOMRIGHT", -15, 5)

    local listScroll = CreateFrame("ScrollFrame", "BRutusWishlistGuildScroll", listContainer, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, 0)
    listScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(listScroll, "BRutusWishlistGuildScroll")

    local listChild = CreateFrame("Frame", "BRutusWishlistGuildChild", listScroll)
    listChild:SetWidth(listContainer:GetWidth() or 720)
    listChild:SetHeight(1)
    listScroll:SetScrollChild(listChild)

    listContainer:SetScript("OnSizeChanged", function(self)
        listChild:SetWidth(self:GetWidth() - 24)
    end)

    ----------------------------------------------------------------
    -- Populate character list
    ----------------------------------------------------------------
    local function PopulateWishlistPanel(filter)
        -- Clear previous
        local children = { listChild:GetChildren() }
        for _, ch in ipairs(children) do ch:Hide() end
        local regions = { listChild:GetRegions() }
        for _, rg in ipairs(regions) do rg:Hide() end

        local guildWl = BRutus.db.guildWishlists
        local childWidth = listChild:GetWidth()
        if childWidth < 100 then childWidth = 720 end
        local ly = -2
        local count = 0
        local totalCount = 0

        local sorted = {}
        if guildWl then
            for key, charData in pairs(guildWl) do
                totalCount = totalCount + 1
                if not filter or filter == "" or strlower(charData.name or key):find(strlower(filter), 1, true) then
                    table.insert(sorted, { key = key, data = charData })
                end
            end
        end
        table.sort(sorted, function(a, b)
            return (a.data.name or a.key) < (b.data.name or b.key)
        end)

        local wColor = BRutus.Wishlist and BRutus.Wishlist.TypeColors.wishlist or { r=0.3, g=0.7, b=1.0 }

        for _, entry in ipairs(sorted) do
            local charData = entry.data
            local charKey = entry.key
            local isExpanded = expandedChar == charKey
            count = count + 1

            local rowBg = (count % 2 == 0) and C.row2 or C.row1

            -- Character row (clickable)
            local charRow = CreateFrame("Button", nil, listChild, "BackdropTemplate")
            charRow:SetPoint("TOPLEFT", 0, ly)
            charRow:SetSize(childWidth, 24)
            charRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            charRow:SetBackdropColor(rowBg.r, rowBg.g, rowBg.b, rowBg.a)
            charRow:Show()

            -- Expand indicator
            local arrow = charRow:CreateFontString(nil, "OVERLAY")
            arrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            arrow:SetPoint("LEFT", 8, 0)
            arrow:SetTextColor(C.silver.r, C.silver.g, C.silver.b, 0.6)
            arrow:SetText(isExpanded and "v" or ">")

            -- Character name
            local cc = BRutus.ClassColors and BRutus.ClassColors[(charData.class or ""):upper()] or C.white
            local nameStr = charRow:CreateFontString(nil, "OVERLAY")
            nameStr:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            nameStr:SetPoint("LEFT", 24, 0)
            nameStr:SetTextColor(cc.r, cc.g, cc.b)
            nameStr:SetText(charData.name or charKey)

            -- Class
            local classStr = charRow:CreateFontString(nil, "OVERLAY")
            classStr:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            classStr:SetPoint("LEFT", 180, 0)
            classStr:SetTextColor(cc.r, cc.g, cc.b, 0.7)
            classStr:SetText(charData.class or "")

            -- Wishlist count
            local wishItems = charData.wishlist or {}
            local wishCount = charRow:CreateFontString(nil, "OVERLAY")
            wishCount:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            wishCount:SetPoint("LEFT", 310, 0)
            wishCount:SetWidth(60)
            if #wishItems > 0 then
                wishCount:SetTextColor(wColor.r, wColor.g, wColor.b)
                wishCount:SetText(tostring(#wishItems) .. " itens")
            else
                wishCount:SetTextColor(0.3, 0.3, 0.3)
                wishCount:SetText("-")
            end

            -- ATT%
            local attStr = "-"
            local attR, attG, attB = 0.35, 0.35, 0.35
            if BRutus.RaidTracker then
                local pKey = BRutus:GetPlayerKey(charData.name or charKey, GetRealmName())
                local attVal = BRutus.RaidTracker:GetAttendance25ManPercent(pKey) or 0
                if attVal > 0 then
                    attStr = attVal .. "%"
                    if attVal >= 60 then
                        attR, attG, attB = 0.3, 1.0, 0.3
                    elseif attVal >= 40 then
                        attR, attG, attB = 1.0, 1.0, 0.3
                    else
                        attR, attG, attB = 1.0, 0.3, 0.3
                    end
                end
            end
            local attPct = charRow:CreateFontString(nil, "OVERLAY")
            attPct:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            attPct:SetPoint("LEFT", 400, 0)
            attPct:SetWidth(50)
            attPct:SetTextColor(attR, attG, attB)
            attPct:SetText(attStr)

            -- Officer prio indicator: gold star if this character has any prios
            local hasPrio = false
            if BRutus.db.lootPrios then
                for _, prioList in pairs(BRutus.db.lootPrios) do
                    for _, prioEntry in ipairs(prioList) do
                        if strlower(prioEntry.name or "") == charKey then
                            hasPrio = true
                            break
                        end
                    end
                    if hasPrio then break end
                end
            end
            if hasPrio then
                local prioStar = charRow:CreateFontString(nil, "OVERLAY")
                prioStar:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                prioStar:SetPoint("LEFT", 460, 0)
                prioStar:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
                prioStar:SetText("|cffFFD700*|r")
            end

            -- Hover
            charRow:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            end)
            charRow:SetScript("OnLeave", function(self)
                self:SetBackdropColor(rowBg.r, rowBg.g, rowBg.b, rowBg.a)
            end)

            -- Click to expand/collapse
            charRow:SetScript("OnClick", function()
                if expandedChar == charKey then
                    expandedChar = nil
                else
                    expandedChar = charKey
                end
                PopulateWishlistPanel(wishSearch:GetText())
            end)

            ly = ly - 26

            ----------------------------------------------------
            -- Expanded: wishlist items
            ----------------------------------------------------
            if isExpanded and (#wishItems > 0 or hasPrio) then
                local detailBg = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
                detailBg:SetPoint("TOPLEFT", 0, ly)
                detailBg:SetSize(childWidth, 1)
                detailBg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                detailBg:SetBackdropColor(0.07, 0.06, 0.11, 0.9)
                detailBg:Show()

                local detailLy = -4

                -- Section label
                local secLabel = listChild:CreateFontString(nil, "OVERLAY")
                secLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                secLabel:SetPoint("TOPLEFT", 10, ly + detailLy)
                secLabel:SetTextColor(wColor.r, wColor.g, wColor.b)
                secLabel:SetText("WISHLIST  (" .. #wishItems .. ")")
                secLabel:Show()
                detailLy = detailLy - 16

                for _, item in ipairs(wishItems) do
                    local iRow = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
                    iRow:SetPoint("TOPLEFT", 20, ly + detailLy)
                    iRow:SetSize(childWidth - 30, 18)
                    iRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                    iRow:SetBackdropColor(0.06, 0.06, 0.10, 0.6)
                    iRow:Show()

                    -- Color bar
                    local colorBar = iRow:CreateTexture(nil, "ARTWORK")
                    colorBar:SetPoint("TOPLEFT", 0, 0)
                    colorBar:SetPoint("BOTTOMLEFT", 0, 0)
                    colorBar:SetWidth(3)
                    colorBar:SetTexture("Interface\\Buttons\\WHITE8x8")
                    colorBar:SetVertexColor(wColor.r, wColor.g, wColor.b, 0.9)

                    -- Order
                    local orderStr = iRow:CreateFontString(nil, "OVERLAY")
                    orderStr:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                    orderStr:SetPoint("LEFT", 8, 0)
                    orderStr:SetWidth(22)
                    orderStr:SetJustifyH("RIGHT")
                    orderStr:SetTextColor(wColor.r, wColor.g, wColor.b, 0.7)
                    orderStr:SetText("#" .. (item.order or "?"))

                    -- Item name
                    local qColor = C.white
                    if BRutus.Wishlist and BRutus.QualityColors then
                        local q = BRutus.Wishlist:GetItemQuality(item.itemId)
                        qColor = BRutus.QualityColors[q] or C.white
                    end
                    local itemName = BRutus.Wishlist and BRutus.Wishlist:GetItemName(item.itemId) or ("Item #" .. (item.itemId or "?"))
                    local itemStr = iRow:CreateFontString(nil, "OVERLAY")
                    itemStr:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
                    itemStr:SetPoint("LEFT", 34, 0)
                    itemStr:SetWidth(childWidth - 140)
                    itemStr:SetJustifyH("LEFT")
                    itemStr:SetWordWrap(false)
                    itemStr:SetTextColor(qColor.r, qColor.g, qColor.b)
                    itemStr:SetText(itemName)

                    -- OS badge
                    if item.isOffspec then
                        local osBadge = iRow:CreateFontString(nil, "OVERLAY")
                        osBadge:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
                        osBadge:SetPoint("RIGHT", -8, 0)
                        osBadge:SetTextColor(0.7, 0.7, 0.7, 0.7)
                        osBadge:SetText("OS")
                    end

                    -- Officer prio badge for this item + this character
                    if BRutus.db.lootPrios and BRutus.db.lootPrios[item.itemId] then
                        for prioIdx, prioEntry in ipairs(BRutus.db.lootPrios[item.itemId]) do
                            if strlower(prioEntry.name or "") == charKey then
                                local prioBadge = iRow:CreateFontString(nil, "OVERLAY")
                                prioBadge:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                                local rightOff = item.isOffspec and -28 or -8
                                prioBadge:SetPoint("RIGHT", rightOff, 0)
                                prioBadge:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
                                prioBadge:SetText("|cffFFD700* #" .. prioIdx .. "|r")
                                break
                            end
                        end
                    end

                    -- Tooltip
                    iRow:EnableMouse(true)
                    iRow:SetScript("OnEnter", function(self)
                        self:SetBackdropColor(0.12, 0.10, 0.18, 0.8)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink("item:" .. (item.itemId or 0))
                        GameTooltip:Show()
                    end)
                    iRow:SetScript("OnLeave", function(self)
                        self:SetBackdropColor(0.06, 0.06, 0.10, 0.6)
                        GameTooltip:Hide()
                    end)

                    detailLy = detailLy - 20
                end

                -- Officer prio section: items where this character has prio but may not be on wishlist
                local prioBadges = {}
                if BRutus.db.lootPrios then
                    for itemId, prioList in pairs(BRutus.db.lootPrios) do
                        for prioIdx, prioEntry in ipairs(prioList) do
                            if strlower(prioEntry.name or "") == charKey then
                                table.insert(prioBadges, { itemId = itemId, order = prioIdx })
                                break
                            end
                        end
                    end
                end
                if #prioBadges > 0 then
                    table.sort(prioBadges, function(a, b) return a.order < b.order end)

                    -- Section separator
                    detailLy = detailLy - 4
                    local prioSep = listChild:CreateTexture(nil, "ARTWORK")
                    prioSep:SetTexture("Interface\\Buttons\\WHITE8x8")
                    prioSep:SetPoint("TOPLEFT", 20, ly + detailLy)
                    prioSep:SetPoint("TOPRIGHT", -20, ly + detailLy)
                    prioSep:SetHeight(1)
                    prioSep:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 0.3)
                    prioSep:Show()
                    detailLy = detailLy - 5

                    local prioLabel = listChild:CreateFontString(nil, "OVERLAY")
                    prioLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                    prioLabel:SetPoint("TOPLEFT", 10, ly + detailLy)
                    prioLabel:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
                    prioLabel:SetText("PRIORIDADE OFICIAL  (" .. #prioBadges .. ")")
                    prioLabel:Show()
                    detailLy = detailLy - 16

                    for _, badge in ipairs(prioBadges) do
                        local pRow = CreateFrame("Frame", nil, listChild, "BackdropTemplate")
                        pRow:SetPoint("TOPLEFT", 20, ly + detailLy)
                        pRow:SetSize(childWidth - 30, 18)
                        pRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                        pRow:SetBackdropColor(0.10, 0.08, 0.03, 0.6)
                        pRow:Show()

                        local goldBar = pRow:CreateTexture(nil, "ARTWORK")
                        goldBar:SetPoint("TOPLEFT", 0, 0)
                        goldBar:SetPoint("BOTTOMLEFT", 0, 0)
                        goldBar:SetWidth(3)
                        goldBar:SetTexture("Interface\\Buttons\\WHITE8x8")
                        goldBar:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 0.9)

                        local starStr = pRow:CreateFontString(nil, "OVERLAY")
                        starStr:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                        starStr:SetPoint("LEFT", 8, 0)
                        starStr:SetWidth(28)
                        starStr:SetJustifyH("RIGHT")
                        starStr:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
                        starStr:SetText("|cffFFD700*|r #" .. badge.order)

                        local pName = BRutus.Wishlist and BRutus.Wishlist:GetItemName(badge.itemId) or ("Item #" .. badge.itemId)
                        local pqColor = C.white
                        if BRutus.QualityColors and BRutus.Wishlist then
                            local q = BRutus.Wishlist:GetItemQuality(badge.itemId)
                            pqColor = BRutus.QualityColors[q] or C.white
                        end
                        local pItemStr = pRow:CreateFontString(nil, "OVERLAY")
                        pItemStr:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
                        pItemStr:SetPoint("LEFT", 40, 0)
                        pItemStr:SetWidth(childWidth - 150)
                        pItemStr:SetJustifyH("LEFT")
                        pItemStr:SetWordWrap(false)
                        pItemStr:SetTextColor(pqColor.r, pqColor.g, pqColor.b)
                        pItemStr:SetText(pName)

                        pRow:EnableMouse(true)
                        pRow:SetScript("OnEnter", function(self)
                            self:SetBackdropColor(0.18, 0.14, 0.04, 0.8)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetHyperlink("item:" .. (badge.itemId or 0))
                            GameTooltip:Show()
                        end)
                        pRow:SetScript("OnLeave", function(self)
                            self:SetBackdropColor(0.10, 0.08, 0.03, 0.6)
                            GameTooltip:Hide()
                        end)

                        detailLy = detailLy - 20
                    end
                end

                local detailHeight = math.abs(detailLy) + 4
                detailBg:SetHeight(detailHeight)                ly = ly - detailHeight - 2
            end
        end

        if count == 0 and totalCount == 0 then
            local noData = listChild:CreateFontString(nil, "OVERLAY")
            noData:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
            noData:SetPoint("TOP", listChild, "TOP", 0, ly - 30)
            noData:SetTextColor(C.silver.r, C.silver.g, C.silver.b, 0.5)
            noData:SetText("Nenhum membro sincronizou a wishlist ainda.\nUse o botao Sync na janela Minha Wishlist para enviar seus dados.")
            noData:SetJustifyH("CENTER")
            noData:Show()
            ly = ly - 60
        elseif count == 0 then
            local noMatch = listChild:CreateFontString(nil, "OVERLAY")
            noMatch:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
            noMatch:SetPoint("TOP", listChild, "TOP", 0, ly - 20)
            noMatch:SetTextColor(C.silver.r, C.silver.g, C.silver.b, 0.5)
            noMatch:SetText("Nenhum personagem encontrado.")
            noMatch:SetJustifyH("CENTER")
            noMatch:Show()
            ly = ly - 40
        end

        local total = 0
        if BRutus.db.guildWishlists then
            for _ in pairs(BRutus.db.guildWishlists) do total = total + 1 end
        end
        charCountText:SetText(count .. " / " .. total .. " membros")
        listChild:SetHeight(math.abs(ly) + 20)

        -- Update status text
        if total > 0 then
            statusText:SetText(string.format("|cff4CFF4C%d|r membros sincronizaram a wishlist", total))
        else
            statusText:SetText("|cffAAAAAASem dados de wishlist recebidos|r")
        end
    end

    wishSearch:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= "" then wishSearchPlaceholder:Hide() else wishSearchPlaceholder:Show() end
        PopulateWishlistPanel(self:GetText())
    end)

    -- Re-render when the client finishes loading a queued item (async cache population).
    -- Debounce: batch rapid arrivals into a single repopulate 0.3 s later.
    parent:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    parent:SetScript("OnEvent", function(self, event)
        if event == "GET_ITEM_INFO_RECEIVED" and self:IsVisible() then
            if not self._itemInfoTimer then
                self._itemInfoTimer = true
                C_Timer.After(0.3, function()
                    self._itemInfoTimer = nil
                    if parent:IsVisible() then
                        PopulateWishlistPanel(wishSearch:GetText())
                    end
                end)
            end
        end
    end)

    parent:SetScript("OnShow", function()
        PopulateWishlistPanel(wishSearch:GetText())
    end)
end

----------------------------------------------------------------------
-- Recruitment Panel UI
----------------------------------------------------------------------
function BRutus:CreateRecruitmentPanel(parent, _mainFrame)
    local yOff = -15

    -- Helper to create a labeled section
    local function SectionHeader(text, y)
        local header = UI:CreateText(parent, text, 13, C.gold.r, C.gold.g, C.gold.b)
        header:SetPoint("TOPLEFT", 20, y)
        local line = UI:CreateSeparator(parent)
        line:SetPoint("TOPLEFT", 20, y - 16)
        line:SetPoint("TOPRIGHT", -20, y - 16)
        return y - 26
    end

    -- Helper to create a row label
    local function RowLabel(text, y)
        local label = UI:CreateText(parent, text, 11, C.silver.r, C.silver.g, C.silver.b)
        label:SetPoint("TOPLEFT", 30, y)
        return label
    end

    ----------------------------------------------------------------
    -- Auto-Recruit Section
    ----------------------------------------------------------------
    yOff = SectionHeader("Auto-Recruit Messages", yOff)

    -- Info note about Blizzard restriction
    local infoNote = UI:CreateText(parent, "Note: Blizzard requires a click to send channel messages. A popup will appear on interval.", 10, 0.7, 0.55, 0.2)
    infoNote:SetPoint("TOPLEFT", 30, yOff)
    infoNote:SetWidth(700)
    yOff = yOff - 18

    -- Status + toggle
    RowLabel("Status:", yOff)
    local statusText = UI:CreateText(parent, "", 11, C.white.r, C.white.g, C.white.b)
    statusText:SetPoint("TOPLEFT", 140, yOff)

    local toggleBtn = UI:CreateButton(parent, "Enable", 80, 22)
    toggleBtn:SetPoint("TOPLEFT", 300, yOff + 3)

    -- Manual send button
    local sendNowBtn = UI:CreateButton(parent, "Send Now", 100, 22)
    sendNowBtn:SetPoint("TOPLEFT", 390, yOff + 3)
    sendNowBtn:SetScript("OnClick", function()
        if BRutus.Recruitment then
            BRutus.Recruitment:DoSendRecruitmentMessage()
        end
    end)

    local function UpdateRecruitStatus()
        local s = BRutus.db.recruitment
        if s.enabled then
            statusText:SetText("|cff4CFF4CACTIVE|r")
            toggleBtn.label:SetText("Disable")
            toggleBtn:SetBackdropColor(C.red.r * 0.3, C.red.g * 0.3, C.red.b * 0.3, 0.6)
        else
            statusText:SetText("|cffFF4444INACTIVE|r")
            toggleBtn.label:SetText("Enable")
            toggleBtn:SetBackdropColor(C.online.r * 0.3, C.online.g * 0.3, C.online.b * 0.3, 0.6)
        end
    end

    toggleBtn:SetScript("OnClick", function()
        if BRutus.Recruitment then
            BRutus.Recruitment:Toggle()
            UpdateRecruitStatus()
        end
    end)
    yOff = yOff - 28

    -- Interval
    RowLabel("Interval (sec):", yOff)
    local intervalBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    intervalBox:SetSize(80, 22)
    intervalBox:SetPoint("TOPLEFT", 140, yOff)
    intervalBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    intervalBox:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
    intervalBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    intervalBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    intervalBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    intervalBox:SetTextInsets(6, 6, 0, 0)
    intervalBox:SetAutoFocus(false)
    intervalBox:SetNumeric(true)
    intervalBox:SetMaxLetters(5)
    intervalBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val >= 60 then
            BRutus.db.recruitment.interval = val
            BRutus:Print("Interval set to " .. val .. "s.")
        else
            self:SetText(tostring(BRutus.db.recruitment.interval))
        end
        self:ClearFocus()
    end)
    intervalBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yOff = yOff - 28

    -- Channels
    RowLabel("Channels:", yOff)
    local channelsText = UI:CreateText(parent, "", 11, C.white.r, C.white.g, C.white.b)
    channelsText:SetPoint("TOPLEFT", 140, yOff)
    channelsText:SetWidth(500)
    yOff = yOff - 28

    -- Message
    RowLabel("Message:", yOff)
    local msgBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    msgBox:SetSize(680, 40)
    msgBox:SetPoint("TOPLEFT", 30, yOff - 18)
    msgBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    msgBox:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
    msgBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    msgBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    msgBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    msgBox:SetTextInsets(8, 8, 6, 6)
    msgBox:SetAutoFocus(false)
    msgBox:SetMaxLetters(255)
    msgBox:SetMultiLine(false)
    msgBox:SetScript("OnEnterPressed", function(self)
        local txt = self:GetText()
        if txt and txt ~= "" then
            BRutus.db.recruitment.message = txt
            BRutus:Print("Recruitment message updated.")
        end
        self:ClearFocus()
    end)
    msgBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yOff = yOff - 68

    ----------------------------------------------------------------
    -- Welcome Message Section
    ----------------------------------------------------------------
    yOff = SectionHeader("Welcome Message (New Members)", yOff)

    -- Welcome status + toggle
    RowLabel("Auto-Welcome:", yOff)
    local welcomeStatusText = UI:CreateText(parent, "", 11, C.white.r, C.white.g, C.white.b)
    welcomeStatusText:SetPoint("TOPLEFT", 140, yOff)

    local welcomeToggle = UI:CreateButton(parent, "Enable", 80, 22)
    welcomeToggle:SetPoint("TOPLEFT", 300, yOff + 3)

    local function UpdateWelcomeStatus()
        local s = BRutus.db.recruitment
        if s.welcomeEnabled then
            welcomeStatusText:SetText("|cff4CFF4CON|r")
            welcomeToggle.label:SetText("Disable")
            welcomeToggle:SetBackdropColor(C.red.r * 0.3, C.red.g * 0.3, C.red.b * 0.3, 0.6)
        else
            welcomeStatusText:SetText("|cffFF4444OFF|r")
            welcomeToggle.label:SetText("Enable")
            welcomeToggle:SetBackdropColor(C.online.r * 0.3, C.online.g * 0.3, C.online.b * 0.3, 0.6)
        end
    end

    welcomeToggle:SetScript("OnClick", function()
        BRutus.db.recruitment.welcomeEnabled = not BRutus.db.recruitment.welcomeEnabled
        UpdateWelcomeStatus()
        local state = BRutus.db.recruitment.welcomeEnabled and "enabled" or "disabled"
        BRutus:Print("Welcome message " .. state .. ".")
    end)
    yOff = yOff - 28

    -- Discord link
    RowLabel("Discord:", yOff)
    local discordBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    discordBox:SetSize(400, 22)
    discordBox:SetPoint("TOPLEFT", 140, yOff)
    discordBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    discordBox:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
    discordBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    discordBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    discordBox:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
    discordBox:SetTextInsets(6, 6, 0, 0)
    discordBox:SetAutoFocus(false)
    discordBox:SetMaxLetters(100)
    discordBox:SetScript("OnEnterPressed", function(self)
        local txt = self:GetText()
        if txt and txt ~= "" then
            BRutus.db.recruitment.discord = txt
            BRutus:Print("Discord link updated.")
        end
        self:ClearFocus()
    end)
    discordBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    yOff = yOff - 28

    -- Welcome message
    RowLabel("Welcome Msg:", yOff)
    local welcomeBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    welcomeBox:SetSize(680, 40)
    welcomeBox:SetPoint("TOPLEFT", 30, yOff - 18)
    welcomeBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    welcomeBox:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
    welcomeBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    welcomeBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    welcomeBox:SetTextColor(C.white.r, C.white.g, C.white.b)
    welcomeBox:SetTextInsets(8, 8, 6, 6)
    welcomeBox:SetAutoFocus(false)
    welcomeBox:SetMaxLetters(255)
    welcomeBox:SetMultiLine(false)
    welcomeBox:SetScript("OnEnterPressed", function(self)
        local txt = self:GetText()
        if txt and txt ~= "" then
            BRutus.db.recruitment.welcomeMessage = txt
            BRutus:Print("Welcome message updated.")
        end
        self:ClearFocus()
    end)
    welcomeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    ----------------------------------------------------------------
    -- Refresh function for when panel is shown
    ----------------------------------------------------------------
    parent:SetScript("OnShow", function()
        local s = BRutus.db.recruitment
        intervalBox:SetText(tostring(s.interval or 120))
        channelsText:SetText(table.concat(s.channels or {}, ", "))
        msgBox:SetText(s.message or "")
        discordBox:SetText(s.discord or "")
        welcomeBox:SetText(s.welcomeMessage or "")
        UpdateRecruitStatus()
        UpdateWelcomeStatus()
    end)
end
