----------------------------------------------------------------------
-- Guild OS - Web panel
-- The web companion's four slash commands, as buttons that explain
-- themselves. A disabled button prints its reason underneath rather
-- than making you click and then read the refusal in chat.
--
-- What this panel may claim is bounded by what the addon can know: it
-- writes GuildOSDB.__companion at logout and the Go companion forwards
-- it without ever reporting back. So this says "written", never "sent".
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local SITE    = "guildos.ferion.com.br"
local PAD     = 14   -- panel edge to content
local GAP     = 8    -- between stacked lines
local SECTION = 14   -- extra space above a section caption
local BTN_H   = 22
local ROW_H   = 16

-- Same shape as UI/Dashboard.lua's countdown, kept local so this panel
-- does not depend on the dashboard having been built.
local function fmtCountdown(dt)
    if dt <= 0 then return L["now"] end
    local d = math.floor(dt / 86400)
    local h = math.floor((dt % 86400) / 3600)
    local m = math.floor((dt % 3600) / 60)
    if d > 0 then return string.format(L["in %dd %dh"], d, h) end
    if h > 0 then return string.format(L["in %dh %dm"], h, m) end
    return string.format(L["in %dm"], math.max(1, m))
end

local function writtenAgo()
    local at = GuildOSDB and GuildOSDB.__companionAt
    if not at or at <= 0 then return L["never"] end
    local dt = (GetServerTime() or time()) - at
    if dt < 120 then return L["just now"] end
    return date("%d/%m %H:%M", at)
end

----------------------------------------------------------------------
-- Can the reload-to-publish button run? Same shape as the import
-- predicates in Modules/CompanionImport.lua, and for the same reason:
-- the button and the action must not disagree about the rule.
----------------------------------------------------------------------
local function canPublishNow()
    local co = BRutus.Companion
    if not (co and co:IsEnabled()) then return false, L["Turn publishing on first."] end
    if InCombatLockdown() then return false, L["Can't reload during combat."] end
    return true
end

function BRutus:CreateWebPanel(parent, _win)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    ----------------------------------------------------------------
    -- PUBLISHING
    ----------------------------------------------------------------
    local pubHead = UI:CreateHeaderText(panel, L["PUBLISHING"], 10)

    local stateDot = panel:CreateTexture(nil, "OVERLAY")
    stateDot:SetTexture("Interface\\Buttons\\WHITE8x8")
    stateDot:SetSize(6, 6)

    local stateText = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    local toggleBtn = UI:CreateButton(panel, L["Turn on"], 90, BTN_H)

    local countText   = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    local writtenText = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(true)

    local publishBtn  = UI:CreateButton(panel, L["Publish now"], 120, BTN_H)
    local publishWhy  = UI:CreateText(panel, "", 9, C.gold.r, C.gold.g, C.gold.b)
    local publishNote = UI:CreateText(panel, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
    publishNote:SetWordWrap(true)
    publishNote:SetJustifyH("LEFT")
    publishWhy:SetJustifyH("LEFT")

    ----------------------------------------------------------------
    -- PLANNED RAID
    ----------------------------------------------------------------
    local raidHead  = UI:CreateHeaderText(panel, L["PLANNED RAID"], 10)
    local raidCount = UI:CreateText(panel, "", 10, C.gold.r, C.gold.g, C.gold.b)
    local raidTitle = UI:CreateText(panel, "", 12, C.text.r, C.text.g, C.text.b)
    local raidWhen  = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    raidTitle:SetJustifyH("LEFT")
    raidTitle:SetWordWrap(false)
    raidWhen:SetJustifyH("LEFT")

    local bringBtn  = UI:CreateButton(panel, L["Bring roster"], 110, BTN_H)
    local inviteBtn = UI:CreateButton(panel, L["Invite"], 90, BTN_H)
    local groupsBtn = UI:CreateButton(panel, L["Groups"], 90, BTN_H)
    local raidWhy   = UI:CreateText(panel, "", 9, C.gold.r, C.gold.g, C.gold.b)
    raidWhy:SetJustifyH("LEFT")
    raidWhy:SetWordWrap(true)

    ----------------------------------------------------------------
    -- FIRST TIME?
    ----------------------------------------------------------------
    local firstHead = UI:CreateHeaderText(panel, L["FIRST TIME?"], 10)
    local step1 = UI:CreateText(panel, string.format(L["1. Open %s"], SITE),
        10, C.text.r, C.text.g, C.text.b)
    local step2 = UI:CreateText(panel, L["2. Download the companion and paste the token"],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    local step3 = UI:CreateText(panel, L["3. Log out of the game once"],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    for _, fs in ipairs({ step1, step2, step3 }) do
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end
    local copyBtn = UI:CreateButton(panel, L["Copy"], 70, 18)

    -- WoW cannot open a browser, so the address goes into a pre-selected
    -- read-only box for Ctrl+C. Same idiom as BRutus:ShowExportPopup.
    local copyBox = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    copyBox:SetHeight(20)
    copyBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    copyBox:SetBackdropColor(0.050, 0.050, 0.066, 1.0)
    copyBox:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    copyBox:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    copyBox:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
    copyBox:SetTextInsets(6, 6, 0, 0)
    copyBox:SetAutoFocus(false)
    copyBox:SetText(SITE)
    copyBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    copyBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    -- Read-only: any edit snaps back to the full address, still selected.
    copyBox:SetScript("OnTextChanged", function(s)
        if s:GetText() ~= SITE then
            s:SetText(SITE)
            s:HighlightText()
        end
    end)
    copyBox:Hide()

    copyBtn:SetScript("OnClick", function()
        copyBox:Show()
        copyBox:SetText(SITE)
        copyBox:HighlightText()
        copyBox:SetFocus()
        BRutus:Print(L["Address selected — press Ctrl+C"])
        panel:Relayout()
    end)

    ----------------------------------------------------------------
    -- Wiring
    ----------------------------------------------------------------
    toggleBtn:SetScript("OnClick", function()
        local co = BRutus.Companion
        if not co then return end
        co:SetEnabled(not co:IsEnabled())
        panel:Refresh()
    end)

    publishBtn:SetScript("OnClick", function()
        -- Re-checked here rather than trusting the greyed state: combat can
        -- start between the last refresh and the click.
        if not canPublishNow() then return end
        ReloadUI()
    end)

    bringBtn:SetScript("OnClick", function()
        BRutus:ShowImportPopup()
    end)

    inviteBtn:SetScript("OnClick", function()
        local I = BRutus.CompanionImport
        if not I then return end
        local n, skipped, err = I:InviteAll()
        if err then
            BRutus:Print(err)
        else
            BRutus:Print(string.format(L["Invited %d, already here %d."], n, skipped))
        end
        panel:Refresh()
    end)

    groupsBtn:SetScript("OnClick", function()
        local I = BRutus.CompanionImport
        if not I then return end
        local moved, err = I:OrganizeGroups()
        if err then
            BRutus:Print(err)
        else
            BRutus:Print(string.format(L["Moved %d into their groups."], moved))
        end
        panel:Refresh()
    end)

    ----------------------------------------------------------------
    -- Refresh: recompute every state, then lay out what is visible.
    ----------------------------------------------------------------
    local function setEnabled(btn, ok)
        if ok then
            btn:Enable()
            btn:SetAlpha(1)
        else
            btn:Disable()
            btn:SetAlpha(0.4)
        end
    end

    function panel:Refresh()
        local co = BRutus.Companion
        local on = (co and co:IsEnabled()) and true or false
        self.publishing = on

        local dot = on and C.online or C.textDim
        stateDot:SetVertexColor(dot.r, dot.g, dot.b, 1)
        stateText:SetText(on and L["On"] or L["Off"])
        toggleBtn.label:SetText(on and L["Turn off"] or L["Turn on"])

        if on then
            -- Build walks the whole guild, so it runs here and nowhere else.
            local _, count = co:Build()
            countText:SetText(type(count) == "number"
                and string.format(L["%d members go out next time"], count) or "")
            writtenText:SetText(string.format(L["Last written: %s"], writtenAgo()))
            publishNote:SetText(L["Writes and reloads the interface. The companion sends it on from your PC."])
        else
            countText:SetText(L["Nothing leaves the game while this is off."])
            writtenText:SetText("")
            publishNote:SetText("")
        end

        local pubOk, pubWhy = canPublishNow()
        setEnabled(publishBtn, pubOk)
        publishWhy:SetText(pubOk and "" or (pubWhy or ""))

        local I = BRutus.CompanionImport
        local roster = I and I:Current()
        if roster then
            local title = roster.title
            if not title or title == "" then title = roster.instance or "?" end
            raidTitle:SetText(title)
            local when = tonumber(roster.startsAt) or 0
            if when > 0 then
                raidWhen:SetText(string.format("%s · %s", date("%a %H:%M", when),
                    fmtCountdown(when - (GetServerTime() or time()))))
            else
                raidWhen:SetText("")
            end
            raidCount:SetText(string.format(L["%d signed up"], #roster.members))
        else
            raidTitle:SetText(L["Nothing loaded."])
            raidWhen:SetText("")
            raidCount:SetText("")
        end

        -- Default to refused, with a reason. If the import module is missing
        -- the actions cannot run, and an enabled button that does nothing
        -- when clicked is the exact failure this panel exists to remove.
        local invOk, invWhy = false, L["Import a roster first."]
        local grpOk, grpWhy = false, L["Import a roster first."]
        if I then
            invOk, invWhy = I:CanInvite()
            grpOk, grpWhy = I:CanOrganize()
        end
        setEnabled(bringBtn, on)
        setEnabled(inviteBtn, invOk and true or false)
        setEnabled(groupsBtn, grpOk and true or false)

        -- One reason line, not three: show the first thing standing in the
        -- way, so the officer gets one instruction instead of a wall.
        local why = ""
        if not on then
            why = L["Turn publishing on first."]
        elseif not invOk then
            why = invWhy or ""
        elseif not grpOk then
            why = grpWhy or ""
        end
        raidWhy:SetText(why)

        -- Exposed so the layout tests can assert the contract this panel
        -- exists for: a button that is off has to say why, and one that is
        -- on must not be nagging about nothing.
        self.state = {
            publishing = on,
            reason     = why,
            publishWhy = pubOk and "" or (pubWhy or ""),
            enabled    = {
                publish = pubOk and true or false,
                bring   = on,
                invite  = invOk and true or false,
                groups  = grpOk and true or false,
            },
        }

        -- The toggle already answers "has this person set it up", so the
        -- first-run block needs no state of its own.
        self.showFirstRun = not on
        for _, r in ipairs({ firstHead, step1, step2, step3, copyBtn }) do
            r:SetShown(self.showFirstRun)
        end
        if not self.showFirstRun then copyBox:Hide() end

        self:Relayout()
    end

    ----------------------------------------------------------------
    -- Layout: one vertical stack; a hidden section costs no height.
    ----------------------------------------------------------------
    function panel:Relayout(w, _h)
        w = w or parent:GetWidth()
        if not w or w < 1 then return end
        local inner = math.max(120, w - PAD * 2)
        local y = PAD

        local function place(region, dx, dy)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + (dx or 0), -(y + (dy or 0)))
        end

        place(pubHead)
        y = y + ROW_H + 2

        place(stateDot, 2, 5)
        place(stateText, 14)
        toggleBtn:ClearAllPoints()
        toggleBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -y)
        y = y + BTN_H + 2

        place(countText); countText:SetWidth(inner)
        y = y + ROW_H
        place(writtenText); writtenText:SetWidth(inner)
        y = y + ROW_H + GAP

        local on = self.publishing
        publishBtn:SetShown(on)
        publishWhy:SetShown(on)
        publishNote:SetShown(on)
        if on then
            publishBtn:ClearAllPoints()
            publishBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
            place(publishWhy, 128, 6)
            publishWhy:SetWidth(math.max(60, inner - 128))
            y = y + BTN_H + 2
            place(publishNote); publishNote:SetWidth(inner)
            y = y + ROW_H * 2 + GAP
        end

        y = y + SECTION
        place(raidHead)
        raidCount:ClearAllPoints()
        raidCount:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -y)
        y = y + ROW_H + 2
        place(raidTitle); raidTitle:SetWidth(inner)
        y = y + ROW_H + 2
        place(raidWhen); raidWhen:SetWidth(inner)
        y = y + ROW_H + GAP

        bringBtn:ClearAllPoints()
        bringBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
        inviteBtn:ClearAllPoints()
        inviteBtn:SetPoint("LEFT", bringBtn, "RIGHT", 6, 0)
        groupsBtn:ClearAllPoints()
        groupsBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 6, 0)
        y = y + BTN_H + 2
        place(raidWhy); raidWhy:SetWidth(inner)
        y = y + ROW_H

        if self.showFirstRun then
            y = y + SECTION
            place(firstHead)
            y = y + ROW_H + 2
            place(step1); step1:SetWidth(math.max(60, inner - 80))
            copyBtn:ClearAllPoints()
            copyBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -y)
            y = y + ROW_H
            place(step2); step2:SetWidth(inner)
            y = y + ROW_H
            place(step3); step3:SetWidth(inner)
            y = y + ROW_H + 4
            if copyBox:IsShown() then
                place(copyBox); copyBox:SetWidth(inner)
                y = y + 20
            end
        end

        self.contentHeight = y + PAD
    end

    ----------------------------------------------------------------
    -- Live while shown: combat gates the publish button, group changes
    -- gate the raid buttons, and the countdown moves on its own.
    ----------------------------------------------------------------
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:RegisterEvent("GROUP_ROSTER_UPDATE")
    panel:SetScript("OnEvent", function(self)
        if self:IsShown() then self:Refresh() end
    end)
    panel:SetScript("OnShow", function(self)
        self:Refresh()
        if self.__ticker then return end
        self.__ticker = C_Timer.NewTicker(10, function()
            if self:IsShown() then self:Refresh() end
        end)
    end)
    panel:SetScript("OnHide", function(self)
        if self.__ticker then self.__ticker:Cancel(); self.__ticker = nil end
    end)

    UI:MakeResponsive(parent, function(_, w, h) panel:Relayout(w, h) end)

    return panel
end
