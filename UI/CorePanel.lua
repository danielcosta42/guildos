----------------------------------------------------------------------
-- Guild OS - Core Panel
-- Officer UI for managing multiple raid cores, each with independent
-- loot rules, attendance penalties, and a DKP/points pool.
----------------------------------------------------------------------
local UI = BRutus.UI
local C = BRutus.Colors
local L = BRutus.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local PANEL_W = 1236  -- matches FRAME_WIDTH in RosterFrame
local LIST_W  = 220   -- left column: core list
local CFG_W   = PANEL_W - LIST_W - 20  -- right column: settings

local function TimeAgo(ts)
    if not ts or ts == 0 then return "" end
    local d = time() - ts
    if d < 60 then return "just now"
    elseif d < 3600 then return math.floor(d / 60) .. "m ago"
    elseif d < 86400 then return math.floor(d / 3600) .. "h ago"
    else return math.floor(d / 86400) .. "d ago"
    end
end

----------------------------------------------------------------------
-- Shared widget builders
----------------------------------------------------------------------
local function MakeInput(parent, w, numeric, placeholder)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.05, 0.05, 0.066, 1)
    b:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    b:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    b:SetTextColor(C.white.r, C.white.g, C.white.b)
    b:SetTextInsets(6, 6, 0, 0)
    b:SetAutoFocus(false)
    if numeric then b:SetNumeric(true); b:SetMaxLetters(5) end
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if placeholder then
        local ph = b:CreateFontString(nil, "OVERLAY")
        ph:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        ph:SetPoint("LEFT", 6, 0)
        ph:SetTextColor(0.4, 0.4, 0.4)
        ph:SetText(placeholder)
        b:SetScript("OnTextChanged", function(self)
            if self:GetText() ~= "" then ph:Hide() else ph:Show() end
        end)
    end
    return b
end

local function MakeCheck(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    if label then
        local lbl = cb:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        lbl:SetText(label)
        cb.label = lbl
    end
    return cb
end

local function MakeLabel(parent, text, size, r, g, b)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont("Fonts\\FRIZQT__.TTF", size or 10, "OUTLINE")
    f:SetTextColor(r or C.silver.r, g or C.silver.g, b or C.silver.b)
    f:SetText(text)
    return f
end

local function MakeSectionHeader(parent, text, y)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetPoint("TOPLEFT", 0, y)
    bg:SetSize(CFG_W - 10, 20)
    bg:SetVertexColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 0.8)

    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    lbl:SetPoint("TOPLEFT", 8, y - 3)
    lbl:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    lbl:SetText(text)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, y - 20)
    line:SetPoint("TOPRIGHT", -10, y - 20)
    line:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.4)

    return y - 26
end

----------------------------------------------------------------------
-- Main builder
----------------------------------------------------------------------
function BRutus:CreateCoresPanel(panel)
    ----------------------------------------------------------------
    -- Status label (shown at the top)
    ----------------------------------------------------------------
    local statusLbl = MakeLabel(panel, "", 10, C.silver.r, C.silver.g, C.silver.b)
    statusLbl:SetPoint("TOPLEFT", LIST_W + 14, -6)
    local function SetStatus(msg, color)
        statusLbl:SetText(msg or "")
        if color then
            statusLbl:SetTextColor(color.r, color.g, color.b)
        else
            statusLbl:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        end
    end

    ----------------------------------------------------------------
    -- Left column: core list
    ----------------------------------------------------------------
    local leftCol = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    leftCol:SetPoint("TOPLEFT", 0, 0)
    leftCol:SetPoint("BOTTOMLEFT", 0, 0)
    leftCol:SetWidth(LIST_W)
    leftCol:SetBackdrop({ bgFile = WHITE })
    leftCol:SetBackdropColor(C.bg0.r, C.bg0.g, C.bg0.b, 0.45)

    local listTitle = MakeLabel(leftCol, L["Cores"], 12, C.gold.r, C.gold.g, C.gold.b)
    listTitle:SetPoint("TOPLEFT", 8, -8)

    local listDiv = leftCol:CreateTexture(nil, "ARTWORK")
    listDiv:SetTexture(WHITE)
    listDiv:SetWidth(1)
    listDiv:SetPoint("TOPRIGHT", 0, 0)
    listDiv:SetPoint("BOTTOMRIGHT", 0, 0)
    listDiv:SetVertexColor(C.separator.r, C.separator.g, C.separator.b, C.separator.a)

    -- Scrollable list of core rows
    local listScroll = CreateFrame("ScrollFrame", "GuildOSCoreListScroll", leftCol, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, -28)
    listScroll:SetPoint("BOTTOMRIGHT", -12, 60)
    UI:SkinScrollBar(listScroll, "GuildOSCoreListScroll")

    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(LIST_W - 14, 1)
    listScroll:SetScrollChild(listContent)

    -- "New core" input + button at the bottom of the list column
    local newInput = MakeInput(leftCol, LIST_W - 80, false, L["Core name"])
    newInput:SetPoint("BOTTOMLEFT", 4, 6)
    local createBtn = UI:CreateButton(leftCol, L["Create"], 60, 22)
    createBtn:SetPoint("LEFT", newInput, "RIGHT", 4, 0)

    ----------------------------------------------------------------
    -- Right column: settings for the selected core
    ----------------------------------------------------------------
    local rightScroll = CreateFrame("ScrollFrame", "GuildOSCoreSettingsScroll", panel, "UIPanelScrollFrameTemplate")
    rightScroll:SetPoint("TOPLEFT", LIST_W + 6, -26)
    rightScroll:SetPoint("BOTTOMRIGHT", -6, 10)
    UI:SkinScrollBar(rightScroll, "GuildOSCoreSettingsScroll")

    local rightContent = CreateFrame("Frame", nil, rightScroll)
    rightContent:SetSize(CFG_W - 20, 1)
    rightScroll:SetScrollChild(rightContent)

    -- Placeholder shown when no core is selected
    local noCoreLbl = MakeLabel(rightContent, L["Select or create a core on the left."],
        12, C.textDim.r, C.textDim.g, C.textDim.b)
    noCoreLbl:SetPoint("TOPLEFT", 12, -20)

    ----------------------------------------------------------------
    -- State
    ----------------------------------------------------------------
    local selectedCore   = nil
    local activeRightTab = "roster"   -- "roster" | "signups" | "config"
    local coreRows       = {}
    local cfgWidgets     = {}   -- holds all setting widgets; rebuilt per selection

    -- Add-member form state (persists across BuildSettings rebuilds)
    local addGMName     = nil   -- selected guild member name
    local addGMClass    = nil   -- classFile e.g. "HUNTER"
    local addGMRole     = nil   -- nil = auto-inferred from class
    local gmDropdown    = nil   -- floating dropdown frame, created once on first open
    local lastCoreBuilt = nil   -- detect core switch so we reset the selection

    local function InferRole(class)
        return BRutus.CoreManager and BRutus.CoreManager:GetRoleForClass(class) or "rdps"
    end

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function GetActiveName()
        return BRutus.CoreManager and BRutus.CoreManager:GetActiveName() or ""
    end

    local function RowLabel(name)
        local active = GetActiveName()
        if active ~= "" and name == active then
            return "|cffFFD700" .. name .. "|r |cff888888(" .. L["active"] .. ")|r"
        end
        return name
    end

    ----------------------------------------------------------------
    -- Settings panel builder (right side)
    ----------------------------------------------------------------
    local function ClearSettings()
        for _, w in ipairs(cfgWidgets) do
            if w.Hide then w:Hide() end
        end
        cfgWidgets = {}
        -- MakeSectionHeader creates raw textures/fontstrings directly on rightContent;
        -- they're not in cfgWidgets, so hide them here to prevent stacking across rebuilds.
        for _, region in pairs({ rightContent:GetRegions() }) do
            region:Hide()
        end
        noCoreLbl:Hide()
        if gmDropdown then gmDropdown:Hide() end
    end

    local function BuildSettings(coreName)
        ClearSettings()
        -- Reset add-member selection when switching to a different core
        if coreName ~= lastCoreBuilt then
            addGMName = nil; addGMClass = nil; addGMRole = nil
        end
        lastCoreBuilt = coreName
        if not coreName or coreName == "" then
            noCoreLbl:Show()
            return
        end
        local CM = BRutus.CoreManager
        if not CM then noCoreLbl:Show(); return end

        local function track(w) cfgWidgets[#cfgWidgets + 1] = w; return w end

        -- Core name header
        local coreTitle = track(MakeLabel(rightContent,
            "|cffFFD700" .. coreName .. "|r", 14))
        coreTitle:SetPoint("TOPLEFT", 4, -4)

        -- "Set as active" button
        local setActiveBtn = track(UI:CreateButton(rightContent, L["Set Active"], 90, 20))
        setActiveBtn:SetPoint("LEFT", coreTitle, "RIGHT", 12, 0)
        setActiveBtn:SetScript("OnClick", function()
            if BRutus.RaidTracker then
                BRutus.RaidTracker:SetGroupTag(coreName)
                SetStatus(string.format(L["Active core set to: %s"], coreName), C.online)
                -- Refresh row labels
                for _, row in pairs(coreRows) do
                    if row.label then row.label:SetText(RowLabel(row.coreName)) end
                end
            end
        end)

        -- Rename + Delete buttons
        local renameBtn = track(UI:CreateButton(rightContent, L["Rename"], 70, 20))
        renameBtn:SetPoint("LEFT", setActiveBtn, "RIGHT", 8, 0)

        local deleteBtn = track(UI:CreateButton(rightContent, L["Delete"], 70, 20))
        deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 6, 0)
        deleteBtn:SetBaseColor(C.red.r * 0.25, C.red.g * 0.25, C.red.b * 0.25, 0.9)

        local renameInput = track(MakeInput(rightContent, 130, false, L["New name"]))
        renameInput:SetPoint("LEFT", deleteBtn, "RIGHT", 10, 0)
        renameBtn:SetScript("OnClick", function()
            local newName = strtrim(renameInput:GetText() or "")
            if newName == "" then
                SetStatus(L["Enter a new name first."], C.red)
                return
            end
            local ok, err = CM:Rename(coreName, newName)
            if not ok then
                SetStatus(err, C.red)
            else
                SetStatus(string.format(L["Renamed to: %s"], newName), C.online)
                renameInput:SetText("")
            end
        end)
        deleteBtn:SetScript("OnClick", function()
            CM:Delete(coreName)
            selectedCore = nil
            SetStatus(string.format(L["Core \"%s\" deleted."], coreName), C.red)
        end)

        -- Right-column sub-tab bar: Roster | Sign-ups | Config (officers only)
        local isOfficer = BRutus:IsOfficer()
        -- Force off config tab for non-officers
        if activeRightTab == "config" and not isOfficer then activeRightTab = "roster" end

        local RTABS    = { "roster", "signups" }
        if isOfficer then RTABS[#RTABS + 1] = "config" end
        local RTAB_LBL = { config = L["Config"], roster = L["Roster"], signups = L["Sign-ups"] }
        local rtabX = 4
        for _, tk in ipairs(RTABS) do
            local tb = track(UI:CreateButton(rightContent, RTAB_LBL[tk], 92, 22))
            tb:SetPoint("TOPLEFT", rtabX, -30)
            if tk == activeRightTab then
                tb:SetBaseColor(C.accent.r * 0.35, C.accent.g * 0.35, C.accent.b * 0.35, 0.9)
            end
            local captureTab = tk
            tb:SetScript("OnClick", function()
                activeRightTab = captureTab
                BuildSettings(coreName)
            end)
            rtabX = rtabX + 98
        end

        local y = -56

        if activeRightTab == "config" then
        ------------------------------------------------------------
        -- Section: General
        ------------------------------------------------------------
        y = MakeSectionHeader(rightContent, L["General"], y)
        y = y - 6

        local curSize = CM:GetRaidSize(coreName)
        local szLbl = track(MakeLabel(rightContent, L["Raid format:"], 10))
        szLbl:SetPoint("TOPLEFT", 4, y)
        local SZ_LABELS = { [10] = "10-man", [25] = "25-man" }
        local szBtn = track(UI:CreateButton(rightContent, SZ_LABELS[curSize], 80, 20))
        szBtn:SetPoint("LEFT", szLbl, "RIGHT", 6, 1)
        szBtn:SetScript("OnClick", function(self)
            curSize = (curSize == 25) and 10 or 25
            self.label:SetText(SZ_LABELS[curSize])
            CM:SetRaidSize(coreName, curSize)
        end)
        local szHint = track(MakeLabel(rightContent,
            L["Sets composition targets for roster analysis."],
            9, C.textDim.r, C.textDim.g, C.textDim.b))
        szHint:SetPoint("LEFT", szBtn, "RIGHT", 10, 0)
        y = y - 30

        ------------------------------------------------------------
        -- Section: Loot Rules
        ------------------------------------------------------------
        y = MakeSectionHeader(rightContent, L["Loot Rules"], y)
        y = y - 6

        local lootCfg = CM:GetLootConfig(coreName)
        local curMethod = lootCfg.lootMethod or "roll"
        local METHOD_LABELS = { roll = L["Roll"], dkp = "DKP", tmb = "TMB" }
        local METHOD_CYCLE  = { "roll", "dkp", "tmb" }

        local function lmSave(key, val)
            CM:SetLootConfigKey(key, val, coreName)
        end

        -- Method selector
        local mthLbl = track(MakeLabel(rightContent, L["Loot method:"], 10))
        mthLbl:SetPoint("TOPLEFT", 4, y)
        local mthBtn = track(UI:CreateButton(rightContent, METHOD_LABELS[curMethod] or "Roll", 70, 20))
        mthBtn:SetPoint("LEFT", mthLbl, "RIGHT", 6, 1)
        mthBtn:SetScript("OnClick", function()
            for i, v in ipairs(METHOD_CYCLE) do
                if v == curMethod then
                    curMethod = METHOD_CYCLE[(i % #METHOD_CYCLE) + 1]
                    break
                end
            end
            lmSave("lootMethod", curMethod)
            BuildSettings(coreName)
        end)
        y = y - 30

        if curMethod == "roll" then
            --------------------------------------------------------
            -- Roll settings
            --------------------------------------------------------
            local rdLabel = track(MakeLabel(rightContent, L["Roll duration (sec):"], 10))
            rdLabel:SetPoint("TOPLEFT", 4, y)
            local rdInput = track(MakeInput(rightContent, 44, true))
            rdInput:SetPoint("LEFT", rdLabel, "RIGHT", 6, 1)
            rdInput:SetText(tostring(lootCfg.rollDuration or 30))
            rdInput:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText()) or 30
                if v < 5 then v = 5 end
                self:SetText(tostring(v))
                lmSave("rollDuration", v)
                self:ClearFocus()
            end)

            local aaCheck = track(MakeCheck(rightContent, L["Auto-announce"]))
            aaCheck:SetPoint("LEFT", rdInput, "RIGHT", 16, 0)
            aaCheck:SetChecked(lootCfg.autoAnnounce ~= false)
            -- Store an explicit boolean (GetChecked yields true/nil in TBC) so the
            -- per-core cascade doesn't fall back to default-true when unchecked.
            aaCheck:SetScript("OnClick", function(self) lmSave("autoAnnounce", self:GetChecked() and true or false) end)
            y = y - 28

            local wmCheck = track(MakeCheck(rightContent, L["Wishlist-only mode"]))
            wmCheck:SetPoint("TOPLEFT", 4, y)
            wmCheck:SetChecked(lootCfg.wishlistOnlyMode or false)
            wmCheck:SetScript("OnClick", function(self) lmSave("wishlistOnlyMode", self:GetChecked()) end)

            local maLabel = track(MakeLabel(rightContent, L["Min attendance % for MS:"], 10))
            maLabel:SetPoint("LEFT", wmCheck, "RIGHT", 24, 0)
            local maInput = track(MakeInput(rightContent, 40, true))
            maInput:SetPoint("LEFT", maLabel, "RIGHT", 6, 1)
            maInput:SetText(tostring(lootCfg.minAttendancePct or 0))
            maInput:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText()) or 0
                if v < 0 then v = 0 elseif v > 100 then v = 100 end
                self:SetText(tostring(v))
                lmSave("minAttendancePct", v)
                self:ClearFocus()
            end)
            y = y - 28

            local atCheck = track(MakeCheck(rightContent, L["Attendance tiebreaker"]))
            atCheck:SetPoint("TOPLEFT", 4, y)
            atCheck:SetChecked(lootCfg.attTiebreaker ~= false)
            atCheck:SetScript("OnClick", function(self) lmSave("attTiebreaker", self:GetChecked()) end)

            local rpCheck = track(MakeCheck(rightContent, L["Recent loot penalty"]))
            rpCheck:SetPoint("LEFT", atCheck, "RIGHT", 24, 0)
            rpCheck:SetChecked(lootCfg.recvPenalty ~= false)
            rpCheck:SetScript("OnClick", function(self) lmSave("recvPenalty", self:GetChecked()) end)
            y = y - 28

            local thLbl = track(MakeLabel(rightContent, L["Loot threshold:"], 10))
            thLbl:SetPoint("TOPLEFT", 4, y)
            local THRESH_NAMES = { [2]=L["Uncommon"], [3]=L["Rare"], [4]=L["Epic"], [5]=L["Legendary"] }
            local THRESH_CYCLE = { 2, 3, 4, 5 }
            local curThresh = lootCfg.lootThreshold or 3
            local thBtn = track(UI:CreateButton(rightContent, THRESH_NAMES[curThresh] or "Rare", 90, 20))
            thBtn:SetPoint("LEFT", thLbl, "RIGHT", 6, 1)
            thBtn:SetScript("OnClick", function(self)
                for i, v in ipairs(THRESH_CYCLE) do
                    if v == curThresh then curThresh = THRESH_CYCLE[(i % #THRESH_CYCLE) + 1]; break end
                end
                self.label:SetText(THRESH_NAMES[curThresh] or "?")
                lmSave("lootThreshold", curThresh)
            end)

            local deLbl = track(MakeLabel(rightContent, L["Disenchanter:"], 10))
            deLbl:SetPoint("LEFT", thBtn, "RIGHT", 18, -1)
            local deInp = track(MakeInput(rightContent, 110, false, L["Player name"]))
            deInp:SetPoint("LEFT", deLbl, "RIGHT", 6, 1)
            deInp:SetText(lootCfg.disenchanter or "")
            deInp:SetScript("OnEnterPressed", function(self)
                lmSave("disenchanter", strtrim(self:GetText() or ""))
                self:ClearFocus()
            end)
            y = y - 30

        elseif curMethod == "dkp" then
            --------------------------------------------------------
            -- DKP bidding settings
            --------------------------------------------------------
            local noteL = track(MakeLabel(rightContent,
                L["Items are bid on using this core's DKP pool. Highest bidder wins."],
                10, C.textDim.r, C.textDim.g, C.textDim.b))
            noteL:SetPoint("TOPLEFT", 4, y)
            noteL:SetWidth(CFG_W - 32)
            noteL:SetWordWrap(true)
            y = y - 24

            local mbLbl = track(MakeLabel(rightContent, L["Min bid (DKP):"], 10))
            mbLbl:SetPoint("TOPLEFT", 4, y)
            local mbInp = track(MakeInput(rightContent, 60, true))
            mbInp:SetPoint("LEFT", mbLbl, "RIGHT", 6, 1)
            mbInp:SetText(tostring(lootCfg.dkpMinBid or 0))
            mbInp:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText()) or 0
                if v < 0 then v = 0 end
                self:SetText(tostring(v))
                lmSave("dkpMinBid", v)
                self:ClearFocus()
            end)

            local btLbl = track(MakeLabel(rightContent, L["Bid duration (sec):"], 10))
            btLbl:SetPoint("LEFT", mbInp, "RIGHT", 20, 0)
            local btInp = track(MakeInput(rightContent, 44, true))
            btInp:SetPoint("LEFT", btLbl, "RIGHT", 6, 1)
            btInp:SetText(tostring(lootCfg.dkpBidTime or 30))
            btInp:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText()) or 30
                if v < 5 then v = 5 end
                self:SetText(tostring(v))
                lmSave("dkpBidTime", v)
                self:ClearFocus()
            end)
            y = y - 28

            local aaCheck2 = track(MakeCheck(rightContent, L["Auto-announce bids"]))
            aaCheck2:SetPoint("TOPLEFT", 4, y)
            aaCheck2:SetChecked(lootCfg.autoAnnounce ~= false)
            aaCheck2:SetScript("OnClick", function(self) lmSave("autoAnnounce", self:GetChecked() and true or false) end)
            y = y - 28

            local thLbl2 = track(MakeLabel(rightContent, L["Loot threshold:"], 10))
            thLbl2:SetPoint("TOPLEFT", 4, y)
            local THRESH_NAMES2 = { [2]=L["Uncommon"], [3]=L["Rare"], [4]=L["Epic"], [5]=L["Legendary"] }
            local THRESH_CYCLE2 = { 2, 3, 4, 5 }
            local curThresh2 = lootCfg.lootThreshold or 3
            local thBtn2 = track(UI:CreateButton(rightContent, THRESH_NAMES2[curThresh2] or "Rare", 90, 20))
            thBtn2:SetPoint("LEFT", thLbl2, "RIGHT", 6, 1)
            thBtn2:SetScript("OnClick", function(self)
                for i, v in ipairs(THRESH_CYCLE2) do
                    if v == curThresh2 then curThresh2 = THRESH_CYCLE2[(i % #THRESH_CYCLE2) + 1]; break end
                end
                self.label:SetText(THRESH_NAMES2[curThresh2] or "?")
                lmSave("lootThreshold", curThresh2)
            end)

            local deLbl2 = track(MakeLabel(rightContent, L["Disenchanter:"], 10))
            deLbl2:SetPoint("LEFT", thBtn2, "RIGHT", 18, -1)
            local deInp2 = track(MakeInput(rightContent, 110, false, L["Player name"]))
            deInp2:SetPoint("LEFT", deLbl2, "RIGHT", 6, 1)
            deInp2:SetText(lootCfg.disenchanter or "")
            deInp2:SetScript("OnEnterPressed", function(self)
                lmSave("disenchanter", strtrim(self:GetText() or ""))
                self:ClearFocus()
            end)
            y = y - 30

        elseif curMethod == "tmb" then
            --------------------------------------------------------
            -- TMB (That's My BiS) import & priority list
            --------------------------------------------------------
            local tmbList    = CM:GetTMBList(coreName)
            local entryCount = #tmbList

            local countLbl = track(MakeLabel(rightContent,
                string.format(L["%d priority entries imported."], entryCount),
                10, C.textDim.r, C.textDim.g, C.textDim.b))
            countLbl:SetPoint("TOPLEFT", 4, y)
            y = y - 20

            local instrLbl = track(MakeLabel(rightContent,
                L["Paste TMB export below (CSV: player,item,priority):"],
                10, C.silver.r, C.silver.g, C.silver.b))
            instrLbl:SetPoint("TOPLEFT", 4, y)
            y = y - 18

            -- Multiline paste area
            local importBg = track(CreateFrame("Frame", nil, rightContent, "BackdropTemplate"))
            importBg:SetSize(CFG_W - 24, 80)
            importBg:SetPoint("TOPLEFT", 4, y)
            importBg:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            importBg:SetBackdropColor(0.04, 0.04, 0.055, 1)
            importBg:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)

            local importScroll = CreateFrame("ScrollFrame", nil, importBg, "UIPanelScrollFrameTemplate")
            importScroll:SetPoint("TOPLEFT", 4, -4)
            importScroll:SetPoint("BOTTOMRIGHT", -22, 4)

            local importBox = track(CreateFrame("EditBox", nil, importScroll))
            importBox:SetSize(CFG_W - 54, 70)
            importBox:SetMultiLine(true)
            importBox:SetMaxLetters(50000)
            importBox:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            importBox:SetTextColor(C.text.r, C.text.g, C.text.b)
            importBox:SetAutoFocus(false)
            importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            importScroll:SetScrollChild(importBox)
            y = y - 88

            local importBtn = track(UI:CreateButton(rightContent, L["Import"], 80, 22))
            importBtn:SetPoint("TOPLEFT", 4, y)
            importBtn:SetScript("OnClick", function()
                local text = importBox:GetText() or ""
                if text == "" then return end
                local list = CM:ParseTMBImport(text)
                CM:SetTMBList(list, coreName)
                BuildSettings(coreName)
            end)

            local clearBtn = track(UI:CreateButton(rightContent, L["Clear List"], 80, 22))
            clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
            clearBtn:SetBaseColor(C.red.r * 0.25, C.red.g * 0.25, C.red.b * 0.25, 0.9)
            clearBtn:SetScript("OnClick", function()
                CM:SetTMBList({}, coreName)
                BuildSettings(coreName)
            end)
            y = y - 30

            local thLbl3 = track(MakeLabel(rightContent, L["Loot threshold:"], 10))
            thLbl3:SetPoint("TOPLEFT", 4, y)
            local THRESH_NAMES3 = { [2]=L["Uncommon"], [3]=L["Rare"], [4]=L["Epic"], [5]=L["Legendary"] }
            local THRESH_CYCLE3 = { 2, 3, 4, 5 }
            local curThresh3 = lootCfg.lootThreshold or 3
            local thBtn3 = track(UI:CreateButton(rightContent, THRESH_NAMES3[curThresh3] or "Rare", 90, 20))
            thBtn3:SetPoint("LEFT", thLbl3, "RIGHT", 6, 1)
            thBtn3:SetScript("OnClick", function(self)
                for i, v in ipairs(THRESH_CYCLE3) do
                    if v == curThresh3 then curThresh3 = THRESH_CYCLE3[(i % #THRESH_CYCLE3) + 1]; break end
                end
                self.label:SetText(THRESH_NAMES3[curThresh3] or "?")
                lmSave("lootThreshold", curThresh3)
            end)

            local deLbl3 = track(MakeLabel(rightContent, L["Disenchanter:"], 10))
            deLbl3:SetPoint("LEFT", thBtn3, "RIGHT", 18, -1)
            local deInp3 = track(MakeInput(rightContent, 110, false, L["Player name"]))
            deInp3:SetPoint("LEFT", deLbl3, "RIGHT", 6, 1)
            deInp3:SetText(lootCfg.disenchanter or "")
            deInp3:SetScript("OnEnterPressed", function(self)
                lmSave("disenchanter", strtrim(self:GetText() or ""))
                self:ClearFocus()
            end)
            y = y - 30

            if entryCount > 0 then
                local listHdr = track(MakeLabel(rightContent, L["Priority list:"], 10,
                    C.gold.r, C.gold.g, C.gold.b))
                listHdr:SetPoint("TOPLEFT", 4, y)
                y = y - 18

                local MAX_SHOW = math.min(entryCount, 30)
                for i = 1, MAX_SHOW do
                    local e = tmbList[i]
                    local row = track(MakeLabel(rightContent,
                        string.format("|cffFFD700%s|r  %s  |cff888888#%d|r",
                            e.player or "?", e.item or "?", e.priority or 1),
                        9))
                    row:SetPoint("TOPLEFT", 8, y)
                    row:SetWidth(CFG_W - 32)
                    y = y - 14
                end
                if entryCount > MAX_SHOW then
                    local moreL = track(MakeLabel(rightContent,
                        string.format(L["...and %d more"], entryCount - MAX_SHOW),
                        9, C.textDim.r, C.textDim.g, C.textDim.b))
                    moreL:SetPoint("TOPLEFT", 8, y)
                    y = y - 14
                end
                y = y - 6
            end
        end

        ------------------------------------------------------------
        -- Section: Attendance Penalties
        ------------------------------------------------------------
        y = MakeSectionHeader(rightContent, L["Attendance Penalties"], y)
        y = y - 6

        local pen = CM:GetPenalties(coreName)
        local function penSave(key, val)
            CM:SetPenalty(key, val, coreName)
            -- Rebuild from sessions so the new weights apply immediately
            if BRutus.RaidTracker then
                BRutus.RaidTracker:RebuildAttendanceFromSessions()
            end
        end

        local penFields = {
            { key = "LATE",        label = L["Late (pts):"]         },
            { key = "LEFT_EARLY",  label = L["Left early (pts):"]   },
            { key = "NO_CONSUMES", label = L["No consumables (pts):"] },
        }
        for _, pf in ipairs(penFields) do
            local lbl = track(MakeLabel(rightContent, pf.label, 10))
            lbl:SetPoint("TOPLEFT", 4, y)
            local inp = track(MakeInput(rightContent, 44, true))
            inp:SetPoint("LEFT", lbl, "RIGHT", 6, 1)
            inp:SetText(tostring(pen[pf.key] or 10))
            local captureKey = pf.key
            inp:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText()) or 10
                if v < 0 then v = 0 elseif v > 100 then v = 100 end
                self:SetText(tostring(v))
                penSave(captureKey, v)
                self:ClearFocus()
            end)
            y = y - 28
        end

        local penNote = track(MakeLabel(rightContent,
            L["Penalty values take effect on the next attendance rebuild."],
            9, C.textDim.r, C.textDim.g, C.textDim.b))
        penNote:SetPoint("TOPLEFT", 4, y)
        y = y - 24

        ------------------------------------------------------------
        -- Section: Points / DKP (only when loot method is DKP)
        ------------------------------------------------------------
        if curMethod == "dkp" then
        y = MakeSectionHeader(rightContent, L["Points / DKP"], y)
        y = y - 6

        local pDB = CM:GetPointsDB(coreName)
        local pCfg = pDB.config or {}

        -- Mode cycle
        local MODE_LABEL = { dkp = "DKP", epgp = "EPGP", council = L["Council"] }
        local MODE_CYCLE = { "dkp", "epgp", "council" }
        local curMode = pDB.mode or "dkp"

        local modeLabel = track(MakeLabel(rightContent, L["Mode:"], 10))
        modeLabel:SetPoint("TOPLEFT", 4, y)
        local modeBtn = track(UI:CreateButton(rightContent, MODE_LABEL[curMode] or "DKP", 80, 20))
        modeBtn:SetPoint("LEFT", modeLabel, "RIGHT", 6, 1)
        modeBtn:SetScript("OnClick", function(self)
            for i, v in ipairs(MODE_CYCLE) do
                if v == curMode then
                    curMode = MODE_CYCLE[(i % #MODE_CYCLE) + 1]
                    break
                end
            end
            pDB.mode = curMode
            self.label:SetText(MODE_LABEL[curMode] or curMode)
            if BRutus.Points then BRutus.Points:Refresh() end
        end)

        y = y - 28

        local ptFields = {
            { key = "bossAward",      label = L["Boss award:"]       },
            { key = "onTimeAward",    label = L["On-time award:"]    },
            { key = "startingPoints", label = L["Starting points:"]  },
            { key = "decayPct",       label = L["Decay %:"]          },
            { key = "itemCost",       label = L["Default item cost:"] },
        }
        local col = 0
        for _, pf in ipairs(ptFields) do
            local xOff = col * 200 + 4
            local lbl = track(MakeLabel(rightContent, pf.label, 10))
            lbl:SetPoint("TOPLEFT", xOff, y)
            local inp = track(MakeInput(rightContent, 52, true))
            inp:SetPoint("LEFT", lbl, "RIGHT", 4, 1)
            inp:SetText(tostring(pCfg[pf.key] or 0))
            local captureKey = pf.key
            inp:SetScript("OnEnterPressed", function(self)
                local v = tonumber(self:GetText()) or 0
                if v < 0 then v = 0 end
                self:SetText(tostring(v))
                pCfg[captureKey] = v
                self:ClearFocus()
            end)
            col = col + 1
            if col >= 3 then col = 0; y = y - 28 end
        end
        if col > 0 then y = y - 28 end

        local autoAwardCheck = track(MakeCheck(rightContent, L["Auto-award on boss kill"]))
        autoAwardCheck:SetPoint("TOPLEFT", 4, y)
        autoAwardCheck:SetChecked(pCfg.autoAward or false)
        autoAwardCheck:SetScript("OnClick", function(self)
            pCfg.autoAward = self:GetChecked()
        end)
        y = y - 32
        end -- if curMethod == "dkp"

        ------------------------------------------------------------
        -- Raid Leader Ranks (who can manage core rosters)
        ------------------------------------------------------------
        y = MakeSectionHeader(rightContent, L["Raid Leader Ranks"], y)
        y = y - 6
        local rlNote = track(MakeLabel(rightContent,
            L["Guild ranks below can add/remove members and accept sign-ups (officers always can)."],
            9, C.textDim.r, C.textDim.g, C.textDim.b))
        rlNote:SetPoint("TOPLEFT", 4, y)
        rlNote:SetWidth(CFG_W - 32)
        rlNote:SetWordWrap(true)
        y = y - 28

        local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        for ri = 1, numRanks do
            local rn = GuildControlGetRankName and GuildControlGetRankName(ri) or ("Rank " .. ri)
            if rn and rn ~= "" then
                local rlCk = track(MakeCheck(rightContent, rn))
                rlCk:SetPoint("TOPLEFT", 4, y)
                rlCk:SetChecked(CM:GetRaidLeaderRanks()[rn] == true)
                local captureRank = rn
                rlCk:SetScript("OnClick", function(self)
                    CM:SetRaidLeaderRank(captureRank, self:GetChecked())
                end)
                y = y - 22
            end
        end

        elseif activeRightTab == "roster" then
        ------------------------------------------------------------
        -- Roster tab: composition + member management
        ------------------------------------------------------------
        local isRL   = CM:IsRaidLeader()
        local comp   = CM:GetComposition(coreName)
        local members = CM:GetMembers(coreName)

        -- Composition summary
        y = MakeSectionHeader(rightContent, L["Composition"], y)
        y = y - 6

        local roles = comp.roleCounts
        local raidSize = CM:GetRaidSize(coreName)
        local T = CM.RAID_TARGETS[raidSize] or CM.RAID_TARGETS[25]
        local function roleColor(role, cnt)
            local t = T[role] or 0
            if cnt >= t then return "|cff44FF44"
            elseif cnt > 0 then return "|cffFFD700"
            else return "|cffFF4444" end
        end
        local compStr = string.format(
            "%d/%d members  %sT:%d/%d|r  %sH:%d/%d|r  %sM:%d/%d|r  %sR:%d/%d|r",
            comp.total, raidSize,
            roleColor("tank",   roles.tank),   roles.tank,   T.tank,
            roleColor("healer", roles.healer), roles.healer, T.healer,
            roleColor("mdps",   roles.mdps),   roles.mdps,   T.mdps,
            roleColor("rdps",   roles.rdps),   roles.rdps,   T.rdps)
        local compLbl = track(MakeLabel(rightContent, compStr, 10, C.silver.r, C.silver.g, C.silver.b))
        compLbl:SetPoint("TOPLEFT", 4, y)
        compLbl:SetWidth(CFG_W - 20)
        y = y - 18

        -- Class breakdown
        local CLASS_ORDER = { "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN","MAGE","WARLOCK","DRUID" }
        local clsCol = 0
        for _, cls in ipairs(CLASS_ORDER) do
            local cnt = comp.classCount[cls]
            if cnt and cnt > 0 then
                local cr, cg, cb = BRutus:GetClassColor(cls)
                local clsLbl = track(MakeLabel(rightContent,
                    cls:sub(1,1) .. cls:sub(2):lower() .. " ×" .. cnt, 10, cr, cg, cb))
                clsLbl:SetPoint("TOPLEFT", clsCol * 155 + 4, y)
                clsCol = clsCol + 1
                if clsCol >= 3 then clsCol = 0; y = y - 16 end
            end
        end
        if clsCol > 0 then y = y - 16 end
        y = y - 6

        -- Raid buff coverage
        y = MakeSectionHeader(rightContent, L["Raid Buffs"], y)
        y = y - 6
        local bfCol = 0
        for _, bs in ipairs(comp.buffStatus) do
            local col_c = bs.covered and C.online or C.red
            local icon  = bs.covered and "|cff00CC00+|r " or "|cffFF4444-|r "
            local bfLbl = track(MakeLabel(rightContent, icon .. bs.name, 9, col_c.r, col_c.g, col_c.b))
            bfLbl:SetPoint("TOPLEFT", bfCol * 200 + 4, y)
            bfCol = bfCol + 1
            if bfCol >= 3 then bfCol = 0; y = y - 15 end
        end
        if bfCol > 0 then y = y - 15 end
        y = y - 6

        -- Member list (with inline role editing for RLs)
        local sortedMbrs = {}
        for k, m in pairs(members) do sortedMbrs[#sortedMbrs + 1] = { key=k, m=m } end
        table.sort(sortedMbrs, function(a, b)
            if (a.m.role or "") ~= (b.m.role or "") then return (a.m.role or "") < (b.m.role or "") end
            return (a.m.name or "") < (b.m.name or "")
        end)

        y = MakeSectionHeader(rightContent,
            string.format(L["Roster (%d)"], #sortedMbrs), y)
        y = y - 6

        local ROLE_C     = { tank=C.accent, healer=C.online, mdps={r=1,g=0.5,b=0.1}, rdps=C.gold }
        local ROLE_LBL   = { tank="TANK", healer="HEAL", mdps="MDPS", rdps="RDPS" }
        local ROLE_CYCLE = { "tank", "healer", "mdps", "rdps" }
        local ROLE_SHORT = { tank="T", healer="H", mdps="M", rdps="R" }

        if #sortedMbrs == 0 then
            local emL = track(MakeLabel(rightContent, L["No members yet."], 10, C.textDim.r, C.textDim.g, C.textDim.b))
            emL:SetPoint("TOPLEFT", 4, y)
            y = y - 20
        end

        for _, entry in ipairs(sortedMbrs) do
            local m  = entry.m
            local mk = entry.key
            local cr, cg, cb = BRutus:GetClassColor(m.class or "WARRIOR")
            local rc = ROLE_C[m.role or "rdps"] or C.silver
            local rowLbl = track(MakeLabel(rightContent,
                string.format("|cff%02X%02X%02X[%s]|r %s",
                    math.floor(rc.r * 255), math.floor(rc.g * 255), math.floor(rc.b * 255),
                    ROLE_LBL[m.role] or "?", m.name or mk),
                10, cr, cg, cb))
            rowLbl:SetPoint("TOPLEFT", 4, y)
            if isRL then
                -- Cycle role without removing the member
                local roleBtn = track(UI:CreateButton(rightContent, ROLE_SHORT[m.role] or "?", 20, 16))
                roleBtn:SetPoint("LEFT", rowLbl, "RIGHT", 6, 0)
                local capKey = mk
                roleBtn:SetScript("OnClick", function()
                    local mem = CM:GetMembers(coreName)[capKey]
                    if not mem then return end
                    local cur = mem.role or "rdps"
                    for i, v in ipairs(ROLE_CYCLE) do
                        if v == cur then mem.role = ROLE_CYCLE[(i % #ROLE_CYCLE) + 1]; break end
                    end
                    CM:BroadcastRoster(coreName)
                    BuildSettings(coreName)
                end)

                local remBtn = track(UI:CreateButton(rightContent, "x", 18, 16))
                remBtn:SetPoint("LEFT", roleBtn, "RIGHT", 3, 0)
                remBtn:SetBaseColor(C.red.r * 0.25, C.red.g * 0.25, C.red.b * 0.25, 0.9)
                local capKey2 = mk
                remBtn:SetScript("OnClick", function()
                    CM:RemoveMember(capKey2, coreName)
                    CM:BroadcastRoster(coreName)
                    BuildSettings(coreName)
                end)
            end
            y = y - 18
        end
        y = y - 8

        -- Add from guild roster: dropdown selectbox (RL only)
        if isRL then
            y = MakeSectionHeader(rightContent, L["Add from Guild"], y)
            y = y - 6

            local ADD_ROLES    = { "tank", "healer", "mdps", "rdps" }
            local ADD_ROLE_LBL = { tank="Tank", healer="Healer", mdps="Melee", rdps="Ranged" }

            -- Derive label and role from current selection state
            local selBtnLbl  = L["Select player..."]
            local currentRole = "rdps"
            if addGMName then
                local cls = addGMClass or "WARRIOR"
                selBtnLbl   = addGMName .. " |cffAAAAAA(" .. cls:sub(1,1) .. cls:sub(2):lower() .. ")|r"
                currentRole = addGMRole or InferRole(cls)
            end

            -- Forward-declare roleBtn so the dropdown row callbacks can update it in-place
            local roleBtn

            -- Dropdown trigger button
            local selBtn = track(UI:CreateButton(rightContent, selBtnLbl, 200, 22))
            selBtn:SetPoint("TOPLEFT", 4, y)
            selBtn:SetScript("OnClick", function(self)
                -- Toggle
                if gmDropdown and gmDropdown:IsShown() then
                    gmDropdown:Hide()
                    return
                end

                -- Create the floating frame once
                if not gmDropdown then
                    local DD_W, DD_H = 220, 224  -- 20px search box + 200px list + 4px padding
                    gmDropdown = CreateFrame("Frame", "GuildOSCoreGMDropdown", UIParent, "BackdropTemplate")
                    gmDropdown:SetSize(DD_W, DD_H)
                    gmDropdown:SetFrameStrata("DIALOG")
                    gmDropdown:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
                    gmDropdown:SetBackdropColor(0.06, 0.06, 0.09, 0.98)
                    gmDropdown:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.9)
                    table.insert(UISpecialFrames, "GuildOSCoreGMDropdown")

                    -- Search box at the top of the dropdown
                    local sb = CreateFrame("EditBox", nil, gmDropdown, "BackdropTemplate")
                    sb:SetSize(DD_W - 4, 20)
                    sb:SetPoint("TOPLEFT", 2, -2)
                    sb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
                    sb:SetBackdropColor(0.08, 0.08, 0.12, 1)
                    sb:SetBackdropBorderColor(C.accent.r * 0.5, C.accent.g * 0.5, C.accent.b * 0.5, 0.8)
                    sb:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                    sb:SetTextColor(C.white.r, C.white.g, C.white.b)
                    sb:SetTextInsets(6, 6, 0, 0)
                    sb:SetAutoFocus(false)
                    sb:SetScript("OnEscapePressed", function() gmDropdown:Hide() end)
                    local sbph = sb:CreateFontString(nil, "OVERLAY")
                    sbph:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
                    sbph:SetPoint("LEFT", 6, 0)
                    sbph:SetTextColor(0.35, 0.35, 0.35)
                    sbph:SetText(L["Search..."])
                    sb:SetScript("OnTextChanged", function(s)
                        local txt = s:GetText()
                        if txt ~= "" then sbph:Hide() else sbph:Show() end
                        if gmDropdown.doFilter then gmDropdown.doFilter(txt) end
                        gmDropdown.scrollOff = 0
                        if gmDropdown.child then gmDropdown.child:SetPoint("TOPLEFT", 0, 0) end
                    end)
                    gmDropdown.searchBox = sb

                    -- Clip frame: masks overflow
                    local clip = CreateFrame("Frame", nil, gmDropdown)
                    clip:SetPoint("TOPLEFT", 2, -26)
                    clip:SetPoint("BOTTOMRIGHT", -2, 2)
                    clip:SetClipsChildren(true)
                    clip:EnableMouseWheel(true)
                    clip:SetScript("OnMouseWheel", function(_, delta)
                        local ch   = gmDropdown.child
                        local off  = gmDropdown.scrollOff or 0
                        local maxV = math.max(0, ch:GetHeight() - (DD_H - 30))
                        gmDropdown.scrollOff = math.min(maxV, math.max(0, off - delta * 20))
                        ch:SetPoint("TOPLEFT", 0, gmDropdown.scrollOff)
                    end)

                    -- Content frame: explicit width so child buttons render at full width
                    local ch = CreateFrame("Frame", nil, clip)
                    ch:SetWidth(DD_W - 4)   -- 216px
                    ch:SetHeight(1)
                    ch:SetPoint("TOPLEFT", 0, 0)

                    gmDropdown.clip      = clip
                    gmDropdown.child     = ch
                    gmDropdown.scrollOff = 0
                end

                -- Build guild member list fresh on each open
                local guildMembers = {}
                local numGM = GetNumGuildMembers and GetNumGuildMembers() or 0
                for gi = 1, numGM do
                    local gname, _, _, _, _, _, _, _, gonline, _, gclass = GetGuildRosterInfo(gi)
                    if gname then
                        guildMembers[#guildMembers + 1] = {
                            name   = gname:match("^([^%-]+)") or gname,
                            class  = gclass or "WARRIOR",
                            online = gonline,
                        }
                    end
                end
                table.sort(guildMembers, function(a, b)
                    if a.online ~= b.online then return a.online and not b.online end
                    return a.name < b.name
                end)

                local inCoreKeys = {}
                for k in pairs(members) do inCoreKeys[k] = true end

                local DD_ROW_W = 216
                local ROW_H    = 20
                local capSelf  = self  -- capture current selBtn for in-place label update

                -- Row builder: called on open and on each keystroke in the search box
                local function buildRows(filter)
                    for _, c in ipairs({ gmDropdown.child:GetChildren() }) do c:Hide() end
                    local lf = (filter and filter ~= "") and filter:lower() or nil
                    local gy = 0
                    for _, gm in ipairs(guildMembers) do
                        if not lf or gm.name:lower():find(lf, 1, true) then
                            local key = BRutus:GetPlayerKey(gm.name, GetRealmName())
                            local alreadyIn = inCoreKeys[key]
                            local cr, cg, cb = BRutus:GetClassColor(gm.class)
                            local dot = gm.online and "|cff00FF00●|r " or "|cff555555●|r "

                            local row = CreateFrame("Button", nil, gmDropdown.child, "BackdropTemplate")
                            row:SetSize(DD_ROW_W, ROW_H)
                            row:SetPoint("TOPLEFT", 0, -gy)
                            row:SetBackdrop({ bgFile = WHITE })

                            local isSelected = (addGMName == gm.name)
                            if alreadyIn then
                                row:SetBackdropColor(0.05, 0.18, 0.05, 0.7)
                            elseif isSelected then
                                row:SetBackdropColor(C.accent.r*0.25, C.accent.g*0.25, C.accent.b*0.25, 0.9)
                            else
                                row:SetBackdropColor(0, 0, 0, 0)
                            end

                            local txt = row:CreateFontString(nil, "OVERLAY")
                            txt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                            txt:SetPoint("LEFT", 4, 0)
                            txt:SetTextColor(alreadyIn and 0.35 or cr, alreadyIn and 0.35 or cg, alreadyIn and 0.35 or cb)
                            txt:SetText(dot .. gm.name)

                            if not alreadyIn then
                                local captureGM = gm
                                row:SetScript("OnClick", function()
                                    addGMName  = captureGM.name
                                    addGMClass = captureGM.class
                                    addGMRole  = InferRole(captureGM.class)
                                    gmDropdown:Hide()
                                    local lbl2 = captureGM.name .. " |cffAAAAAA(" ..
                                        captureGM.class:sub(1,1) .. captureGM.class:sub(2):lower() .. ")|r"
                                    capSelf.label:SetText(lbl2)
                                    if roleBtn then roleBtn.label:SetText(ADD_ROLE_LBL[addGMRole] or "?") end
                                end)
                                row:SetScript("OnEnter", function(s)
                                    if addGMName ~= gm.name then s:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 1) end
                                end)
                                row:SetScript("OnLeave", function(s)
                                    if addGMName == gm.name then
                                        s:SetBackdropColor(C.accent.r*0.25, C.accent.g*0.25, C.accent.b*0.25, 0.9)
                                    else
                                        s:SetBackdropColor(0, 0, 0, 0)
                                    end
                                end)
                            end
                            gy = gy + ROW_H
                        end
                    end
                    gmDropdown.child:SetHeight(math.max(1, gy))
                end

                -- Register filter function so the search box OnTextChanged can call it
                gmDropdown.doFilter = buildRows

                -- Reset state for this open
                gmDropdown.scrollOff = 0
                gmDropdown.child:SetPoint("TOPLEFT", 0, 0)
                if gmDropdown.searchBox then gmDropdown.searchBox:SetText("") end

                -- Build initial full list
                buildRows("")

                -- Position dropdown flush below the select button
                gmDropdown:ClearAllPoints()
                local bx = self:GetLeft()   or 0
                local by = self:GetBottom() or 0
                gmDropdown:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bx, by)

                gmDropdown:Show()
                if gmDropdown.searchBox then gmDropdown.searchBox:SetFocus() end
            end)

            -- Role cycle button — auto-inferred from class, manually overridable
            roleBtn = track(UI:CreateButton(rightContent, ADD_ROLE_LBL[currentRole], 80, 22))
            roleBtn:SetPoint("LEFT", selBtn, "RIGHT", 6, 0)
            roleBtn:SetScript("OnClick", function(self)
                local cur = addGMRole or "rdps"
                for i, v in ipairs(ADD_ROLES) do
                    if v == cur then addGMRole = ADD_ROLES[(i % #ADD_ROLES) + 1]; break end
                end
                self.label:SetText(ADD_ROLE_LBL[addGMRole] or "?")
            end)

            -- Confirm add
            local addBtn = track(UI:CreateButton(rightContent, L["Add"], 50, 22))
            addBtn:SetPoint("LEFT", roleBtn, "RIGHT", 6, 0)
            addBtn:SetScript("OnClick", function()
                if not addGMName then SetStatus(L["Select a player first."], C.red); return end
                local k = BRutus:GetPlayerKey(addGMName, GetRealmName())
                CM:AddMember(k, {
                    name  = addGMName,
                    class = addGMClass,
                    role  = addGMRole or InferRole(addGMClass or "WARRIOR"),
                }, coreName)
                CM:BroadcastRoster(coreName)
                addGMName = nil; addGMClass = nil; addGMRole = nil
                BuildSettings(coreName)
            end)
            y = y - 30
        end

        elseif activeRightTab == "signups" then
        ------------------------------------------------------------
        -- Sign-ups tab: application queue
        ------------------------------------------------------------
        local isRL   = CM:IsRaidLeader()
        local signups = CM:GetSignups(coreName)
        local suList = {}
        for k, su in pairs(signups) do suList[#suList + 1] = { key=k, su=su } end
        -- Newest applications first; fall back to alphabetical for entries without a timestamp
        table.sort(suList, function(a, b)
            local ta, tb = a.su.ts or 0, b.su.ts or 0
            if ta ~= tb then return ta > tb end
            return (a.su.name or "") < (b.su.name or "")
        end)

        y = MakeSectionHeader(rightContent,
            string.format(L["Pending Sign-ups (%d)"], #suList), y)
        y = y - 6

        local tipLbl = track(MakeLabel(rightContent,
            L["Players apply with: /gos signup <core> [note]"],
            9, C.textDim.r, C.textDim.g, C.textDim.b))
        tipLbl:SetPoint("TOPLEFT", 4, y)
        y = y - 18

        if #suList == 0 then
            local emL = track(MakeLabel(rightContent, L["No pending sign-ups."], 10, C.silver.r, C.silver.g, C.silver.b))
            emL:SetPoint("TOPLEFT", 4, y)
            y = y - 20
        end

        local RL = CM.ROLE_LABELS
        for _, entry in ipairs(suList) do
            local su = entry.su
            local sk = entry.key
            local cr, cg, cb = BRutus:GetClassColor(su.class or "WARRIOR")
            local tsStr = su.ts and TimeAgo(su.ts) or ""
            local nameLbl = track(MakeLabel(rightContent,
                string.format("%s |cff888888(%s)|r", su.name or sk, (RL and RL[su.role]) or su.role or "?"),
                11, cr, cg, cb))
            nameLbl:SetPoint("TOPLEFT", 4, y)

            if isRL then
                local accBtn = track(UI:CreateButton(rightContent, L["Accept"], 70, 20))
                accBtn:SetPoint("TOPRIGHT", rightContent, "TOPRIGHT", -4, y + 1)
                accBtn:SetBaseColor(C.online.r * 0.25, C.online.g * 0.25, C.online.b * 0.25, 0.9)
                local decBtn = track(UI:CreateButton(rightContent, L["Decline"], 70, 20))
                decBtn:SetPoint("RIGHT", accBtn, "LEFT", -4, 0)
                decBtn:SetBaseColor(C.red.r * 0.25, C.red.g * 0.25, C.red.b * 0.25, 0.9)
                local capKey = sk
                accBtn:SetScript("OnClick", function()
                    CM:AcceptSignup(capKey, coreName)
                    CM:BroadcastRoster(coreName)
                    activeRightTab = "roster"
                    BuildSettings(coreName)
                end)
                decBtn:SetScript("OnClick", function()
                    CM:DeclineSignup(capKey, coreName)
                    BuildSettings(coreName)
                end)
            end
            y = y - 22

            -- Note and/or timestamp on the same sub-line
            local noteStr = (su.note and su.note ~= "") and su.note or ""
            local subLine = tsStr ~= "" and (noteStr ~= "" and (noteStr .. "  •  " .. tsStr) or tsStr) or noteStr
            if subLine ~= "" then
                local noteLbl = track(MakeLabel(rightContent, subLine, 9, C.textDim.r, C.textDim.g, C.textDim.b))
                noteLbl:SetPoint("TOPLEFT", 12, y)
                y = y - 16
            end
        end

        end -- activeRightTab branches

        -- Resize content frame so scroll bar knows the full height
        rightContent:SetHeight(math.abs(y) + 20)
    end

    ----------------------------------------------------------------
    -- Core list rebuild
    ----------------------------------------------------------------
    local function RebuildList()
        -- Clear existing rows
        for _, row in pairs(coreRows) do row:Hide() end
        coreRows = {}

        if not BRutus.CoreManager then return end

        local names = BRutus.CoreManager:GetSortedNames()
        local ROW_H = 28
        for idx, name in ipairs(names) do
            local row = CreateFrame("Button", nil, listContent, "BackdropTemplate")
            row:SetSize(LIST_W - 14, ROW_H)
            row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
            row:SetBackdrop({ bgFile = WHITE })
            local isEven = idx % 2 == 0
            row:SetBackdropColor(
                isEven and C.row2.r or C.row1.r,
                isEven and C.row2.g or C.row1.g,
                isEven and C.row2.b or C.row1.b,
                isEven and C.row2.a or C.row1.a)

            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            lbl:SetPoint("LEFT", 8, 0)
            lbl:SetTextColor(C.text.r, C.text.g, C.text.b)
            lbl:SetText(RowLabel(name))
            row.label    = lbl
            row.coreName = name

            -- Highlight selected
            if name == selectedCore then
                row:SetBackdropColor(C.headerBg.r, C.headerBg.g, C.headerBg.b, 0.9)
                lbl:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
            end

            row:SetScript("OnClick", function()
                selectedCore = name
                BuildSettings(name)
                RebuildList()
            end)
            row:SetScript("OnEnter", function(self)
                if name ~= selectedCore then
                    self:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 1)
                end
            end)
            row:SetScript("OnLeave", function(self)
                if name ~= selectedCore then
                    self:SetBackdropColor(
                        isEven and C.row2.r or C.row1.r,
                        isEven and C.row2.g or C.row1.g,
                        isEven and C.row2.b or C.row1.b,
                        isEven and C.row2.a or C.row1.a)
                end
            end)

            coreRows[#coreRows + 1] = row
        end

        listContent:SetHeight(math.max(1, #names * ROW_H))
    end

    ----------------------------------------------------------------
    -- Create button handler
    ----------------------------------------------------------------
    createBtn:SetScript("OnClick", function()
        local name = strtrim(newInput:GetText() or "")
        if name == "" then
            SetStatus(L["Enter a name for the new core."], C.red)
            return
        end
        local ok, err = BRutus.CoreManager:Create(name)
        if not ok then
            SetStatus(err, C.red)
        else
            newInput:SetText("")
            selectedCore = name
            SetStatus(string.format(L["Core \"%s\" created."], name), C.online)
            RebuildList()
            BuildSettings(name)
        end
    end)

    ----------------------------------------------------------------
    -- Refresh hook — called when the panel becomes visible or from sync
    ----------------------------------------------------------------
    BRutus.coresPanelRefresh = function()
        RebuildList()
        if selectedCore then BuildSettings(selectedCore) end
    end

    panel:SetScript("OnShow", function()
        RebuildList()
        if selectedCore then
            BuildSettings(selectedCore)
        else
            noCoreLbl:Show()
        end
    end)

    -- Initial build
    noCoreLbl:Show()
end
