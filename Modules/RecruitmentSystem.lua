----------------------------------------------------------------------
-- BRutus Guild Manager - Recruitment System
-- Automatic recruitment messages + right-click guild invite
-- Only officers (rank index <= 1) or configurable rank can use this
----------------------------------------------------------------------
local Recruitment = {}
BRutus.Recruitment = Recruitment

-- Defaults
Recruitment.DEFAULT_SETTINGS = {
    enabled = false,
    interval = 120,           -- seconds between messages
    message = "",             -- recruitment message text
    channels = {},            -- list of channel names to post to (e.g. {"LookingForGroup", "Trade"})
    minRankIndex = 2,         -- max rank index allowed (0 = GM, 1 = first officer, 2 = second officer, etc.)
    welcomeEnabled = true,
    welcomeMessage = "",      -- auto-filled on init
    discord = "https://discord.gg/6bcyPZ2UUC",
}

Recruitment.ticker = nil
Recruitment.lastSend = 0

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function Recruitment:Initialize()
    -- Ensure DB settings exist
    if not BRutus.db.recruitment then
        BRutus.db.recruitment = BRutus:DeepCopy(self.DEFAULT_SETTINGS)
    end
    local r = BRutus.db.recruitment
    -- Fill missing keys
    for k, v in pairs(self.DEFAULT_SETTINGS) do
        if r[k] == nil then
            if type(v) == "table" then
                r[k] = BRutus:DeepCopy(v)
            else
                r[k] = v
            end
        end
    end

    -- Set default channels if empty
    if #r.channels == 0 then
        r.channels = { "LookingForGroup" }
    end

    -- Set default message if empty
    if r.message == "" then
        local guildName = GetGuildInfo("player") or "our guild"
        r.message = guildName .. " is recruiting! All classes and roles welcome. Whisper me for info or invite!"
    end

    -- Hook right-click menu for guild invite
    self:HookChatInvite()

    -- Set default welcome message if empty
    if r.welcomeMessage == "" then
        local guildName = GetGuildInfo("player") or "our guild"
         r.welcomeMessage = "Welcome to " .. guildName .. "! Join our Discord: " .. r.discord .. " - Have fun!"
    end

    -- Listen for new guild members joining
    self:RegisterWelcomeEvent()

    -- Resume if was enabled
    if r.enabled and self:CanUseRecruitment() then
        self:StartAutoRecruit()
    end
end

----------------------------------------------------------------------
-- Permission check: is the player officer or above?
----------------------------------------------------------------------
function Recruitment:CanUseRecruitment()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if not rankIndex then return false end
    return rankIndex <= (BRutus.db.recruitment.minRankIndex or 2) or CanGuildInvite()
end

----------------------------------------------------------------------
-- Start automatic recruitment
----------------------------------------------------------------------
function Recruitment:StartAutoRecruit()
    if not self:CanUseRecruitment() then
        BRutus:Print("|cffFF4444You don't have permission to use recruitment.|r")
        return false
    end

    local settings = BRutus.db.recruitment
    settings.enabled = true

    -- Stop existing ticker
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    local interval = math.max(settings.interval, 60) -- minimum 60s safety

    -- NOTE: SendChatMessage("CHANNEL") requires a hardware event (Blizzard restriction).
    -- We show a clickable popup instead of sending automatically.
    self.ticker = C_Timer.NewTicker(interval, function()
        self:ShowSendPopup()
    end)

    -- Show first popup after a short delay
    C_Timer.After(2, function()
        self:ShowSendPopup()
    end)

     BRutus:Print("Recruitment |cff4CFF4Cstarted|r - popup every " .. interval .. "s. Click to send!")
    return true
end

----------------------------------------------------------------------
-- Stop automatic recruitment
----------------------------------------------------------------------
function Recruitment:StopAutoRecruit()
    BRutus.db.recruitment.enabled = false
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if self.popupFrame then
        self.popupFrame:Hide()
    end
    BRutus:Print("Recruitment |cffFF4444stopped|r.")
end

----------------------------------------------------------------------
-- Toggle recruitment
----------------------------------------------------------------------
function Recruitment:Toggle()
    if BRutus.db.recruitment.enabled then
        self:StopAutoRecruit()
    else
        self:StartAutoRecruit()
    end
    return BRutus.db.recruitment.enabled
end

----------------------------------------------------------------------
-- Create the send popup (one-time)
----------------------------------------------------------------------
function Recruitment:CreatePopupFrame()
    if self.popupFrame then return end

    local C = BRutus.Colors
    local f = CreateFrame("Button", "BRutusRecruitPopup", UIParent, "BackdropTemplate")
    f:SetSize(300, 50)
    f:SetPoint("TOP", UIParent, "TOP", 0, -80)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.082, 0.082, 0.105, 0.95)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    f:SetFrameStrata("DIALOG")
    BRutus.UI:StylePopup(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()

    -- Glow pulse
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.15)

    local icon = f:CreateFontString(nil, "OVERLAY")
    icon:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    icon:SetPoint("LEFT", 10, 0)
    icon:SetText("|TInterface\\MINIMAP\\TRACKING\\Mailbox:16:16|t")

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    text:SetText("Click to send recruit msg!")
    f.label = text

    local dismiss = CreateFrame("Button", nil, f)
    dismiss:SetSize(20, 20)
    dismiss:SetPoint("TOPRIGHT", -4, -4)
    dismiss:SetNormalFontObject(GameFontNormalSmall)
    local dText = dismiss:CreateFontString(nil, "OVERLAY")
    dText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    dText:SetPoint("CENTER")
    dText:SetText("x")
    dText:SetTextColor(0.6, 0.6, 0.6)
    dismiss:SetScript("OnEnter", function() dText:SetTextColor(1, 0.3, 0.3) end)
    dismiss:SetScript("OnLeave", function() dText:SetTextColor(0.6, 0.6, 0.6) end)
    dismiss:SetScript("OnClick", function() f:Hide() end)

    -- The main click = hardware event -> sends the message
    f:SetScript("OnClick", function(self)
        Recruitment:DoSendRecruitmentMessage()
        self:Hide()
    end)

    f:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("BRutus Recruitment", C.gold.r, C.gold.g, C.gold.b)
        GameTooltip:AddLine("Left-click to post recruitment message.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Drag to move. x to dismiss.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.8)
        GameTooltip:Hide()
    end)

    self.popupFrame = f
end

----------------------------------------------------------------------
-- Show the popup notification
----------------------------------------------------------------------
function Recruitment:ShowSendPopup()
    if not BRutus.db.recruitment.enabled then return end
    if InCombatLockdown() then return end
    if not self:CanUseRecruitment() then return end

    self:CreatePopupFrame()

    -- Update channel list in label
    local channels = BRutus.db.recruitment.channels
    local chText = table.concat(channels, ", ")
    self.popupFrame.label:SetText("Click to recruit!  >>  " .. chText)
    self.popupFrame:Show()

    -- Auto-hide after 30s if not clicked
    C_Timer.After(30, function()
        if self.popupFrame and self.popupFrame:IsShown() then
            self.popupFrame:Hide()
        end
    end)
end

----------------------------------------------------------------------
-- Actually send the message (called from button click = hardware event)
----------------------------------------------------------------------
function Recruitment:DoSendRecruitmentMessage()
    if not IsInGuild() then return end

    local settings = BRutus.db.recruitment
    local msg = settings.message
    if not msg or msg == "" then
        BRutus:Print("|cffFF4444No recruitment message set.|r")
        return
    end

    local sent = false
    for _, channelName in ipairs(settings.channels) do
        local channelNum = GetChannelName(channelName)
        if channelNum and channelNum > 0 then
            SendChatMessage(msg, "CHANNEL", nil, channelNum)
            sent = true
        end
    end

    if sent then
        self.lastSend = GetTime()
        BRutus:Print("Recruitment message sent!")
    else
        BRutus:Print("|cffFF4444No valid channels found. Join a channel first.|r")
    end
end

----------------------------------------------------------------------
-- Right-click guild invite (slash command based - no dropdown hook to avoid taint)
-- Usage: /brutus invite PlayerName
----------------------------------------------------------------------
function Recruitment:HookChatInvite()
    -- No dropdown hooks - they cause taint errors.
    -- Guild invite is available via /brutus invite <name>
end

----------------------------------------------------------------------
-- Slash command handler
----------------------------------------------------------------------
function Recruitment:HandleCommand(args)
    local cmd = args[1]

    if cmd == "on" or cmd == "start" then
        self:StartAutoRecruit()
    elseif cmd == "off" or cmd == "stop" then
        self:StopAutoRecruit()
    elseif cmd == "msg" or cmd == "message" then
        table.remove(args, 1)
        local newMsg = table.concat(args, " ")
        if newMsg and newMsg ~= "" then
            BRutus.db.recruitment.message = newMsg
            BRutus:Print("Recruitment message set to: |cffFFFFFF" .. newMsg .. "|r")
        else
            BRutus:Print("Current message: |cffFFFFFF" .. (BRutus.db.recruitment.message or "(empty)") .. "|r")
        end
    elseif cmd == "interval" then
        local secs = tonumber(args[2])
        if secs and secs >= 60 then
            BRutus.db.recruitment.interval = secs
            BRutus:Print("Recruitment interval set to |cffFFFFFF" .. secs .. "s|r.")
            -- Restart if active
            if BRutus.db.recruitment.enabled then
                self:StopAutoRecruit()
                self:StartAutoRecruit()
            end
        else
            BRutus:Print("Usage: /brutus recruit interval <seconds> (min 60)")
        end
    elseif cmd == "channel" then
        local action = args[2]
        local chName = args[3]
        if action == "add" and chName then
            table.insert(BRutus.db.recruitment.channels, chName)
            BRutus:Print("Added channel: |cffFFFFFF" .. chName .. "|r")
        elseif action == "remove" and chName then
            local channels = BRutus.db.recruitment.channels
            for i = #channels, 1, -1 do
                if channels[i]:lower() == chName:lower() then
                    table.remove(channels, i)
                    BRutus:Print("Removed channel: |cffFFFFFF" .. chName .. "|r")
                    return
                end
            end
            BRutus:Print("Channel not found: " .. chName)
        elseif action == "list" then
            local list = table.concat(BRutus.db.recruitment.channels, ", ")
            BRutus:Print("Channels: |cffFFFFFF" .. (list ~= "" and list or "(none)") .. "|r")
        else
            BRutus:Print("Usage: /brutus recruit channel <add|remove|list> [name]")
        end
    elseif cmd == "status" then
        local s = BRutus.db.recruitment
        local status = s.enabled and "|cff4CFF4CON|r" or "|cffFF4444OFF|r"
        local wStatus = s.welcomeEnabled and "|cff4CFF4CON|r" or "|cffFF4444OFF|r"
        BRutus:Print("--- Recruitment Status ---")
        BRutus:Print("Active: " .. status)
        BRutus:Print("Interval: |cffFFFFFF" .. s.interval .. "s|r")
        BRutus:Print("Channels: |cffFFFFFF" .. table.concat(s.channels, ", ") .. "|r")
        BRutus:Print("Message: |cffFFFFFF" .. s.message .. "|r")
        BRutus:Print("Welcome: " .. wStatus)
        BRutus:Print("Welcome msg: |cffFFFFFF" .. s.welcomeMessage .. "|r")
        BRutus:Print("Discord: |cffFFFFFF" .. s.discord .. "|r")
    elseif cmd == "welcome" then
        local sub = args[2]
        if sub == "on" then
            BRutus.db.recruitment.welcomeEnabled = true
            BRutus:Print("Welcome message |cff4CFF4Cenabled|r.")
        elseif sub == "off" then
            BRutus.db.recruitment.welcomeEnabled = false
            BRutus:Print("Welcome message |cffFF4444disabled|r.")
        elseif sub == "msg" then
            table.remove(args, 1)
            table.remove(args, 1)
            local newMsg = table.concat(args, " ")
            if newMsg and newMsg ~= "" then
                BRutus.db.recruitment.welcomeMessage = newMsg
                BRutus:Print("Welcome message set to: |cffFFFFFF" .. newMsg .. "|r")
            else
                BRutus:Print("Current: |cffFFFFFF" .. BRutus.db.recruitment.welcomeMessage .. "|r")
            end
        else
            BRutus:Print("Usage: /brutus recruit welcome <on|off|msg> [text]")
        end
    elseif cmd == "discord" then
        local link = args[2]
        if link and link ~= "" then
            BRutus.db.recruitment.discord = link
            BRutus:Print("Discord link set to: |cffFFFFFF" .. link .. "|r")
        else
            BRutus:Print("Discord: |cffFFFFFF" .. BRutus.db.recruitment.discord .. "|r")
        end
    elseif cmd == "invite" then
        local target = args[2]
        if target and target ~= "" then
            if not CanGuildInvite() then
                BRutus:Print("|cffFF4444You don't have permission to invite.|r")
                return
            end
            GuildInvite(target)
            BRutus:Print("Guild invite sent to |cffFFFFFF" .. target .. "|r.")
        else
            BRutus:Print("Usage: /brutus recruit invite <PlayerName>")
        end
    else
        BRutus:Print("|cffFFD700Recruitment commands:|r")
        BRutus:Print("  /brutus recruit on/off")
        BRutus:Print("  /brutus recruit status")
        BRutus:Print("  /brutus recruit msg <text>")
        BRutus:Print("  /brutus recruit interval <seconds>")
        BRutus:Print("  /brutus recruit channel add/remove/list <name>")
        BRutus:Print("  /brutus recruit welcome on/off/msg <text>")
        BRutus:Print("  /brutus recruit discord <link>")
        BRutus:Print("  /brutus recruit invite <PlayerName>")
    end
end

----------------------------------------------------------------------
-- Welcome message for new guild members
----------------------------------------------------------------------
function Recruitment:RegisterWelcomeEvent()
    -- Track guild roster to detect new joins
    self._knownMembers = {}
    self._rosterReady = false
    self._welcomedRecently = {}

    -- Build initial roster snapshot
    local function SnapshotRoster()
        local members = {}
        local numMembers = GetNumGuildMembers() or 0
        for i = 1, numMembers do
            local fullName = GetGuildRosterInfo(i)
            if fullName then
                local shortName = fullName:match("^([^-]+)") or fullName
                members[shortName] = true
            end
        end
        return members
    end

    -- Initialize roster snapshot after a delay (guild data needs to load)
    C_Timer.After(8, function()
        Recruitment._knownMembers = SnapshotRoster()
        Recruitment._rosterReady = true
    end)

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    frame:SetScript("OnEvent", function(_, event, msg)
        if event ~= "CHAT_MSG_SYSTEM" then return end
        if not IsInGuild() then return end
        if not BRutus.db.recruitment.welcomeEnabled then return end
        if not Recruitment._rosterReady then return end

        -- Detect "%s has joined the guild."
        local joinPattern = ERR_GUILD_JOIN_S and ERR_GUILD_JOIN_S:gsub("%%s", "(.+)") or nil
        local newMember

        if joinPattern then
            newMember = msg:match(joinPattern)
        end

        -- Fallback patterns for PT/EN clients
        if not newMember then
            newMember = msg:match("(.+) entrou na guilda%.")
                     or msg:match("(.+) has joined the guild%.")
        end

        if not newMember then return end

        -- Don't welcome ourselves
        local myName = UnitName("player")
        if newMember == myName then return end

        -- Avoid duplicate welcomes (e.g. multiple officers running BRutus)
        if Recruitment._welcomedRecently[newMember] then return end
        Recruitment._welcomedRecently[newMember] = true
        C_Timer.After(60, function()
            Recruitment._welcomedRecently[newMember] = nil
        end)

        -- Add to known members
        Recruitment._knownMembers[newMember] = true

        -- Random delay 3-7s so only the first officer to fire actually sends.
        -- Before sending, re-check the claim flag (another officer may have
        -- already claimed via CommSystem WC message and set it back to true).
        local delay = 3 + math.random() * 4
        C_Timer.After(delay, function()
            -- Re-check: another BRutus client may have claimed in the meantime
            if Recruitment._welcomedRecently[newMember .. "_sent"] then return end
            Recruitment._welcomedRecently[newMember .. "_sent"] = true

            -- Broadcast claim with NORMAL priority so other clients suppress before their timer fires
            if BRutus.CommSystem then
                BRutus.CommSystem:SendMessage(
                    BRutus.CommSystem.MSG_TYPES.WELCOME_CLAIM, newMember, nil, "NORMAL")
            end

            local settings = BRutus.db.recruitment
            local welcomeMsg = settings.welcomeMessage
            if welcomeMsg and welcomeMsg ~= "" then
                SendChatMessage(welcomeMsg, "GUILD")
                BRutus:Print("Welcome message sent for |cffFFFFFF" .. newMember .. "|r in guild chat.")
            end
        end)
    end)
end
