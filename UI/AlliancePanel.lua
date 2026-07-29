----------------------------------------------------------------------
-- Guild OS - Alliance panel
-- The Alliance tab: who is federated with us, how fresh their data is, and the
-- officer controls for the pact. Two sub-tabs: Overview and Manage.
--
-- Rule 10: no business logic here. Everything is rendered from
-- Alliance:Summary() / Alliance:CanAdminister(); actions call module methods.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local ROW_H = 22

local function ALLY() return BRutus.Alliance end

-- Explicit Show/Hide instead of SetShown: everywhere else in this codebase
-- SetShown is only ever called on Frames, and these groups mix in FontStrings
-- and Textures. Show/Hide is defined on every region, so this cannot surprise.
local function setShown(widget, cond)
    if cond then widget:Show() else widget:Hide() end
end

local function clear(child)
    for _, c in pairs({ child:GetChildren() }) do c:Hide() end
    for _, r in pairs({ child:GetRegions() }) do r:Hide() end
end

local function makeInput(parent, width)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(width, 24)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(C.bg1.r, C.bg1.g, C.bg1.b, 1)
    b:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.4)
    b:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    b:SetTextColor(C.text.r, C.text.g, C.text.b)
    b:SetTextInsets(6, 6, 0, 0)
    b:SetAutoFocus(false)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return b
end

----------------------------------------------------------------------
-- Overview: the header band, the allied guild table, the blocked list.
----------------------------------------------------------------------
local function BuildOverview(panel)
    local empty = UI:CreateText(panel, "", 12, C.textDim.r, C.textDim.g, C.textDim.b)
    empty:SetPoint("TOPLEFT", 4, -6)
    empty:SetPoint("RIGHT", -4, 0)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)

    local title = UI:CreateText(panel, "", 13, C.gold.r, C.gold.g, C.gold.b)
    title:SetPoint("TOPLEFT", 4, -6)

    local status = UI:CreateText(panel, "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
    status:SetPoint("TOPLEFT", 4, -26)

    local line = UI:CreateAccentLine(panel, 1)
    line:SetPoint("TOPLEFT", 0, -44)
    line:SetPoint("TOPRIGHT", 0, -44)

    -- Column headers, matching the approved mockup.
    local head = {}
    local COLS = {
        { key = "guild", label = L["GUILD"],       x = 6,   w = 190 },
        { key = "seen",  label = L["SEEN"],        x = 200, w = 70 },
        { key = "amb",   label = L["AMBASSADORS"], x = 274, w = 200 },
        { key = "sync",  label = L["LAST SYNC"],   x = 478, w = 110 },
    }
    for _, col in ipairs(COLS) do
        local fs = UI:CreateHeaderText(panel, col.label, 10)
        fs:SetPoint("TOPLEFT", col.x, -50)
        fs:SetWidth(col.w)
        fs:SetJustifyH("LEFT")
        head[col.key] = fs
    end

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -68)
    holder:SetPoint("BOTTOMRIGHT", 0, 4)
    -- CreateScrollFrame does NOT anchor the scroll frame; without this the
    -- content is clipped to 0x0 and renders as nothing, with no error.
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceOverviewScroll")
    scroll:SetAllPoints()

    local function refresh()
        local ally = ALLY()
        local summary = ally and ally:Summary()

        clear(content)

        if not summary then
            title:Hide()
            status:Hide()
            line:Hide()
            for _, fs in pairs(head) do fs:Hide() end
            empty:Show()
            empty:SetText(BRutus:IsOfficer()
                and L["This guild is not in an alliance yet. Use the Manage tab to found one."]
                or L["This guild is not in an alliance yet."])
            return
        end

        empty:Hide()
        title:Show()
        status:Show()
        line:Show()
        for _, fs in pairs(head) do fs:Show() end

        title:SetText(string.format("%s  |cff888888[%s]|r  %s",
            summary.name, summary.tag,
            string.format(L["%d guilds, %d members"], #summary.guilds, summary.members)))

        local bridgeText = summary.bridge or L["nobody online"]
        if summary.amBridge then
            bridgeText = bridgeText .. " " .. L["(you)"]
        end
        local chanText = summary.connected and L["connected"] or L["not connected"]
        status:SetText(string.format("%s  |cff555555.|r  %s %s",
            string.format(L["Bridge: %s"], bridgeText),
            summary.channel or "?", chanText))

        local y = 0
        for i, g in ipairs(summary.guilds) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(content:GetWidth() > 0 and content:GetWidth() or 600, ROW_H)
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local rc = (i % 2 == 0) and C.row2 or C.row1
            bg:SetColorTexture(rc.r, rc.g, rc.b, rc.a or 1)

            -- Filled marker when the mesh can see somebody from that guild,
            -- hollow when it cannot. Data never vanishes; it just ages.
            local live = g.seen > 0
            local mark = UI:CreateText(row, live and "*" or "o", 12,
                live and C.online.r or C.offline.r,
                live and C.online.g or C.offline.g,
                live and C.online.b or C.offline.b)
            mark:SetPoint("LEFT", 6, 0)

            local label = g.name
            if g.isOwner then label = label .. " " .. L["(owner)"] end
            if g.isMine then label = label .. " " .. L["(you)"] end
            local nameFs = UI:CreateText(row, label, 11, C.text.r, C.text.g, C.text.b)
            nameFs:SetPoint("LEFT", 18, 0)
            nameFs:SetWidth(178)
            nameFs:SetJustifyH("LEFT")

            local seenFs = UI:CreateText(row, string.format("%d/%d", g.seen, g.members), 11,
                C.textDim.r, C.textDim.g, C.textDim.b)
            seenFs:SetPoint("LEFT", 200, 0)

            local amb = table.concat(g.ambassadors, ", ")
            local ambFs = UI:CreateText(row, amb, 11, C.textDim.r, C.textDim.g, C.textDim.b)
            ambFs:SetPoint("LEFT", 274, 0)
            ambFs:SetWidth(200)
            ambFs:SetJustifyH("LEFT")
            ambFs:SetWordWrap(false)

            local age = g.ts and BRutus:TimeAgo(g.ts) or L["never"]
            local ageFs = UI:CreateText(row, age, 11, C.textDim.r, C.textDim.g, C.textDim.b)
            ageFs:SetPoint("LEFT", 478, 0)

            row:EnableMouse(true)
            row:SetScript("OnEnter", function()
                bg:SetColorTexture(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(g.name)
                GameTooltip:AddLine(string.format(
                    L["Seen: %d of %d known members are visible on the presence mesh."],
                    g.seen, g.members), 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(L["Only players running Guild OS are counted, so this is a floor, not the real online count."],
                    0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                bg:SetColorTexture(rc.r, rc.g, rc.b, rc.a or 1)
                GameTooltip:Hide()
            end)

            y = y + ROW_H
        end

        -- Upcoming events published by allied guilds, with a slot request.
        local cal = BRutus.Calendar
        local events = (cal and cal.AllianceEvents and cal:AllianceEvents()) or {}
        if #events > 0 then
            y = y + 10
            local hdr = UI:CreateText(content, L["UPCOMING ALLIANCE EVENTS"], 10,
                C.gold.r, C.gold.g, C.gold.b)
            hdr:SetPoint("TOPLEFT", 6, -y)
            y = y + 18

            for i = 1, math.min(#events, 8) do
                local ev = events[i]
                local full = (ev.yes or 0) >= (ev.size or 25)
                local when = date("%a %H:%M", ev.when)
                local fs = UI:CreateText(content, string.format("%s  %s  |cff888888%s  %d/%d|r",
                    when, ev.title or "?", ev.guild or "?", ev.yes or 0, ev.size or 25),
                    11, C.text.r, C.text.g, C.text.b)
                fs:SetPoint("TOPLEFT", 10, -y)
                fs:SetWidth(math.max(content:GetWidth() - 200, 200))
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(false)

                if full then
                    local fullFs = UI:CreateText(content, L["full"], 10,
                        C.textDim.r, C.textDim.g, C.textDim.b)
                    fullFs:SetPoint("TOPRIGHT", -6, -y)
                else
                    local roleBtn = UI:CreateButton(content, L["DPS"], 56, 18)
                    roleBtn.role = "DPS"
                    local askBtn = UI:CreateButton(content, L["Request slot"], 100, 18)
                    askBtn:SetPoint("TOPRIGHT", -6, -y + 2)
                    roleBtn:SetPoint("RIGHT", askBtn, "LEFT", -6, 0)
                    roleBtn:SetScript("OnClick", function()
                        local order = { TANK = "HEALER", HEALER = "DPS", DPS = "TANK" }
                        roleBtn.role = order[roleBtn.role] or "DPS"
                        roleBtn.label:SetText(L[roleBtn.role])
                    end)
                    askBtn:SetScript("OnClick", function()
                        local ok, err = BRutus.Calendar:RequestAllianceSlot(
                            ev.id, ev.guild, roleBtn.role, "")
                        if ok then
                            BRutus:Print(string.format(L["Slot requested from %s."], ev.guild))
                        elseif err then
                            BRutus:Print(err)
                        end
                    end)
                end
                y = y + ROW_H
            end
        end

        if #summary.blocked > 0 then
            y = y + 8
            local fs = UI:CreateText(content,
                string.format(L["Blocked: %s"], table.concat(summary.blocked, ", ")),
                11, C.red.r, C.red.g, C.red.b)
            fs:SetPoint("TOPLEFT", 6, -y)
            y = y + ROW_H
        end

        content:SetHeight(math.max(y, 1))
    end

    return refresh
end

----------------------------------------------------------------------
-- Manage: found, invite, block, remove, leave, and the channel toggle.
----------------------------------------------------------------------
local function BuildManage(panel)
    local notOfficer = UI:CreateText(panel, L["Only officers can manage the alliance."],
        12, C.textDim.r, C.textDim.g, C.textDim.b)
    notOfficer:SetPoint("TOPLEFT", 6, -8)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Found a new alliance (only shown when there is no pact).
    local foundHdr = UI:CreateHeaderText(body, L["Found an alliance"], 11)
    foundHdr:SetPoint("TOPLEFT", 6, -10)
    local tagBox = makeInput(body, 110)
    tagBox:SetPoint("TOPLEFT", 6, -30)
    local nameBox = makeInput(body, 240)
    nameBox:SetPoint("LEFT", tagBox, "RIGHT", 8, 0)
    local foundBtn = UI:CreateButton(body, L["Create"], 90, 24)
    foundBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    local foundHint = UI:CreateText(body, L["Tag (letters and numbers) and a display name."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    foundHint:SetPoint("TOPLEFT", 6, -58)

    -- Invite / block, shown once a pact exists.
    local inviteHdr = UI:CreateHeaderText(body, L["Invite a guild"], 11)
    inviteHdr:SetPoint("TOPLEFT", 6, -10)
    local inviteBox = makeInput(body, 200)
    inviteBox:SetPoint("TOPLEFT", 6, -30)
    local inviteBtn = UI:CreateButton(body, L["Invite"], 90, 24)
    inviteBtn:SetPoint("LEFT", inviteBox, "RIGHT", 8, 0)
    local inviteHint = UI:CreateText(body,
        L["Name any officer of that guild. They get a prompt and must accept."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    inviteHint:SetPoint("TOPLEFT", 6, -58)

    local blockHdr = UI:CreateHeaderText(body, L["Ignore a guild locally"], 11)
    blockHdr:SetPoint("TOPLEFT", 6, -86)
    local blockBox = makeInput(body, 200)
    blockBox:SetPoint("TOPLEFT", 6, -106)
    local blockBtn = UI:CreateButton(body, L["Block"], 90, 24)
    blockBtn:SetPoint("LEFT", blockBox, "RIGHT", 8, 0)
    local unblockBtn = UI:CreateButton(body, L["Unblock"], 90, 24)
    unblockBtn:SetPoint("LEFT", blockBtn, "RIGHT", 6, 0)
    local blockHint = UI:CreateText(body,
        L["Only affects you. The pact is untouched and nobody is told."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    blockHint:SetPoint("TOPLEFT", 6, -134)

    local removeHdr = UI:CreateHeaderText(body, L["Remove a guild from the pact"], 11)
    removeHdr:SetPoint("TOPLEFT", 6, -162)
    local removeBox = makeInput(body, 200)
    removeBox:SetPoint("TOPLEFT", 6, -182)
    local removeBtn = UI:CreateButton(body, L["Remove"], 90, 24)
    removeBtn:SetPoint("LEFT", removeBox, "RIGHT", 8, 0)
    local removeHint = UI:CreateText(body, L["Only the founding guild can do this."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    removeHint:SetPoint("TOPLEFT", 6, -210)

    local chatBtn = UI:CreateButton(body, L["Alliance chat"], 150, 24)
    chatBtn:SetPoint("TOPLEFT", 6, -240)
    local chatHint = UI:CreateText(body,
        L["A custom channel is public: anyone who guesses the name can join. Keep secrets out of it."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    chatHint:SetPoint("TOPLEFT", 6, -268)
    chatHint:SetPoint("RIGHT", body, "RIGHT", -6, 0)
    chatHint:SetJustifyH("LEFT")
    chatHint:SetWordWrap(true)

    local leaveBtn = UI:CreateButton(body, L["Leave the alliance"], 170, 24)
    leaveBtn:SetPoint("TOPLEFT", 6, -300)

    local foundGroup  = { foundHdr, tagBox, nameBox, foundBtn, foundHint }
    local memberGroup = { inviteHdr, inviteBox, inviteBtn, inviteHint,
                          blockHdr, blockBox, blockBtn, unblockBtn, blockHint,
                          removeHdr, removeBox, removeBtn, removeHint,
                          chatBtn, chatHint, leaveBtn }

    local function say(ok, err)
        if not ok and err then BRutus:Print(err) end
    end

    local refresh   -- forward declaration so handlers can re-render

    foundBtn:SetScript("OnClick", function()
        local ok, err = ALLY():Create(tagBox:GetText(), nameBox:GetText())
        say(ok, err)
        if ok then
            tagBox:SetText("")
            nameBox:SetText("")
            if BRutus.AllianceChat then BRutus.AllianceChat:Join() end
        end
        refresh()
    end)

    inviteBtn:SetScript("OnClick", function()
        local target = inviteBox:GetText()
        local ok, err = ALLY():Invite(target)
        say(ok, err)
        if ok then
            BRutus:Print(string.format(L["Invite sent to %s."], target))
            inviteBox:SetText("")
        end
        refresh()
    end)

    blockBtn:SetScript("OnClick", function()
        say(ALLY():Block(blockBox:GetText()))
        blockBox:SetText("")
        refresh()
    end)

    unblockBtn:SetScript("OnClick", function()
        say(ALLY():Unblock(blockBox:GetText()))
        blockBox:SetText("")
        refresh()
    end)

    removeBtn:SetScript("OnClick", function()
        local guild = removeBox:GetText()
        StaticPopup_Show("GUILDOS_ALLY_REMOVE",
            string.format(L["Remove %s from the alliance?"], guild), nil,
            { guild = guild, after = function() removeBox:SetText(""); refresh() end })
    end)

    chatBtn:SetScript("OnClick", function()
        local chat = BRutus.AllianceChat
        if not chat then return end
        chat:SetEnabled(not chat:Prefs().chat)
        refresh()
    end)

    leaveBtn:SetScript("OnClick", function()
        StaticPopup_Show("GUILDOS_ALLY_LEAVE",
            L["Leave the alliance? Your guild stops sharing and stops receiving."], nil,
            { after = function() refresh() end })
    end)

    refresh = function()
        local ally = ALLY()
        local isOfficer = BRutus:IsOfficer()
        setShown(notOfficer, not isOfficer)
        setShown(body, isOfficer)
        if not isOfficer then return end

        local hasPact = ally and ally:Get() ~= nil
        for _, w in ipairs(foundGroup) do setShown(w, not hasPact) end
        for _, w in ipairs(memberGroup) do setShown(w, hasPact) end
        if not hasPact then return end

        -- Enable/Disable rather than SetEnabled: both exist on Button and
        -- EditBox in this client, these two are the ones guaranteed to.
        local isOwner = ally:Get().owner == ally:MyGuildName()
        if isOwner then
            removeBtn:Enable()
            removeBox:Enable()
        else
            removeBtn:Disable()
            removeBox:Disable()
        end

        local chat = BRutus.AllianceChat
        local on = chat and chat:Prefs().chat
        -- UI:CreateButton has no SetText; the label is a child FontString.
        chatBtn.label:SetText(on and L["Alliance chat: on"] or L["Alliance chat: off"])
    end

    return refresh
end

----------------------------------------------------------------------
-- Confirmations
----------------------------------------------------------------------
local function registerPopups()
    if StaticPopupDialogs["GUILDOS_ALLY_REMOVE"] then return end

    StaticPopupDialogs["GUILDOS_ALLY_REMOVE"] = {
        text = "%s", button1 = L["Remove"], button2 = L["Cancel"],
        OnAccept = function(self)
            local d = self and self.data
            if not d then return end
            local ok, err = BRutus.Alliance:RemoveGuild(d.guild)
            if not ok and err then BRutus:Print(err) end
            if d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    StaticPopupDialogs["GUILDOS_ALLY_LEAVE"] = {
        text = "%s", button1 = L["Leave"], button2 = L["Cancel"],
        OnAccept = function(self)
            local ok, err = BRutus.Alliance:Leave()
            if not ok and err then BRutus:Print(err) end
            local d = self and self.data
            if d and d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

----------------------------------------------------------------------
-- Entry point, called from UI/RosterFrame.lua
----------------------------------------------------------------------
local SUBTABS = {
    { key = "overview", label = L["Overview"] },
    { key = "manage",   label = L["Manage"] },
}

function BRutus:CreateAlliancePanel(parent, _mainFrame)
    registerPopups()
    parent.subPanels = {}
    parent.activeSub = "overview"

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetPoint("TOPRIGHT", -10, -8)
    bar:SetHeight(26)

    local btns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(btns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then BRutus:SafeCall(info.refresh) end
    end
    parent.SelectSub = selectSub

    local x = 0
    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 120)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        btns[t.key] = btn
        x = x + 124
    end

    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", 12, -42)
        p:SetPoint("BOTTOMRIGHT", -12, 10)
        p:Hide()
        return p
    end

    local builders = { overview = BuildOverview, manage = BuildManage }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "overview")
    end)
end
