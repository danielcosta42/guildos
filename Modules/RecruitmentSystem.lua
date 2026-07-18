----------------------------------------------------------------------
-- BRutus Guild Manager - Recruitment System
-- Automatic recruitment messages + right-click guild invite
-- Only officers (rank index <= 1) or configurable rank can use this
----------------------------------------------------------------------
local Recruitment = {}
BRutus.Recruitment = Recruitment
local L = BRutus.L

-- TBC class list (used by UI and broadcast)
Recruitment.CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

-- Defaults
Recruitment.DEFAULT_SETTINGS = {
    enabled = false,
    interval = 120,           -- seconds between messages
    message = "",             -- recruitment message text
    channels = {},            -- list of channel names to post to (e.g. {"LookingForGroup", "Trade"})
    minRankIndex = 2,         -- max rank index allowed (0 = GM, 1 = first officer, 2 = second officer, etc.)
    welcomeEnabled = true,
    welcomeMessage = "",      -- auto-filled on init
    discord = "",
}

Recruitment.ticker       = nil   -- officer auto-send ticker
Recruitment.memberTicker = nil   -- member opt-in auto-send ticker
Recruitment.lastSend     = 0

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
        local guildName = GetGuildInfo("player") or L["our guild"]
        r.message = guildName .. L[" is recruiting! All classes and roles welcome. Whisper me for info or invite!"]
    end

    -- Hook right-click menu for guild invite
    self:HookChatInvite()

    -- Set default welcome message if empty
    if r.welcomeMessage == "" then
        local guildName = GetGuildInfo("player") or L["our guild"]
        if r.discord ~= "" then
            r.welcomeMessage = L["Welcome to "] .. guildName .. L["! Join our Discord: "] .. r.discord .. L[" - Have fun!"]
        else
            r.welcomeMessage = L["Welcome to "] .. guildName .. L[" - Have fun!"]
        end
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
        BRutus:Print(L["|cffFF4444You don't have permission to use recruitment.|r"])
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

     BRutus:Print(string.format(L["Recruitment |cff4CFF4Cstarted|r - popup every %ds. Click to send!"], interval))
    -- Push the (now enabled) config to guild members so they can help spread it.
    self:BroadcastStatus(true)
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
    -- Push the disabled state so members stop spreading it (newest wins).
    if BRutus:IsOfficer() then self:BroadcastStatus(true) end
    BRutus:Print(L["Recruitment |cffFF4444stopped|r."])
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
-- Broadcast recruitment status (class needs, discord, message) to all
-- guild members who have Guild OS installed.
----------------------------------------------------------------------
function Recruitment:BroadcastStatus(quiet)
    if not BRutus.CommSystem or not IsInGuild() then return end
    if not (BRutus.IsOfficer and BRutus:IsOfficer()) then return end
    local r = BRutus.db.recruitment
    r.updatedAt = time()   -- version stamp: newest broadcast wins on receivers
    local payload = LibStub("LibSerialize"):Serialize({
        enabled    = r.enabled,
        discord    = r.discord or "",
        message    = r.message or "",
        channels   = r.channels or {},
        interval   = r.interval or 120,
        updatedBy  = UnitName("player"),
        updatedAt  = r.updatedAt,
    })
    BRutus.CommSystem:SendMessage("RI", payload)
    -- Mirror into the guild-synced slot so this account's own member-rank alts
    -- (they share the per-guild DB) get the ad immediately, with no round-trip.
    BRutus.db.guildRecruitment = {
        enabled = r.enabled, discord = r.discord or "", message = r.message or "",
        channels = r.channels or {}, interval = r.interval or 120,
        updatedAt = r.updatedAt, updatedBy = UnitName("player"),
    }
    if not quiet then BRutus:Print(L["Recruitment status broadcast to guild members."]) end
end

----------------------------------------------------------------------
-- Member auto-send: opt-in ticker using guild-broadcast config
----------------------------------------------------------------------
function Recruitment:StartMemberRecruit()
    local info = BRutus.db.guildRecruitment
    if not info or not info.message or info.message == "" then
        BRutus:Print(L["|cffFF4444No recruitment data received yet. Ask an officer to broadcast.|r"])
        return false
    end
    if self.memberTicker then self.memberTicker:Cancel() end
    local interval = math.max(info.interval or 120, 60)
    self.memberTicker = C_Timer.NewTicker(interval, function()
        Recruitment:ShowSendPopup()
    end)
    C_Timer.After(2, function() Recruitment:ShowSendPopup() end)
    BRutus:Print(string.format(L["Recruitment |cff4CFF4Cstarted|r - popup every %ds. Click to send!"], interval))
    return true
end

function Recruitment:StopMemberRecruit()
    if self.memberTicker then
        self.memberTicker:Cancel()
        self.memberTicker = nil
    end
    if self.popupFrame then self.popupFrame:Hide() end
    BRutus:Print(L["Recruitment |cffFF4444stopped|r."])
end

function Recruitment:IsMemberRecruitActive()
    return self.memberTicker ~= nil
end

----------------------------------------------------------------------
-- Guild-wide sharing + opt-out participation
--
-- The officer's config is relayed member-to-member (not just pushed once by
-- the officer), so alts and late-loggers reliably end up with it. Each member
-- decides once whether to help spread it — db.recruitParticipate is tri-state
-- (nil = undecided → prompt; true = participating; false = declined) and the
-- choice is remembered across sessions.
----------------------------------------------------------------------

-- Re-share the guild's recruitment config in response to a sync REQUEST.
-- Officers send their own authoritative copy; members relay the cached one so
-- the ad reaches newcomers even when no officer is online.
function Recruitment:RespondToSync()
    if not BRutus.CommSystem or not IsInGuild() then return end
    if BRutus:IsOfficer() then
        local r = BRutus.db.recruitment
        if r and r.enabled then self:BroadcastStatus(true) end
        return
    end
    local info = BRutus.db.guildRecruitment
    if info and info.enabled and info.message and info.message ~= "" then
        local payload = LibStub("LibSerialize"):Serialize({
            enabled = info.enabled, discord = info.discord or "", message = info.message or "",
            channels = info.channels or {}, interval = info.interval or 120,
            updatedBy = info.updatedBy, updatedAt = info.updatedAt,
        })
        BRutus.CommSystem:SendMessage("RI", payload)
    end
end

-- Apply an incoming config (direct officer broadcast OR a member relay).
-- Trusted only if the AUTHOR is a verified guild officer, and only if it is
-- newer than what we hold (newest updatedAt wins) so relays can't roll it back.
function Recruitment:ApplyIncoming(info, sender)
    if type(info) ~= "table" then return end
    local author = (info.updatedBy and info.updatedBy ~= "" and info.updatedBy) or sender
    if not (BRutus.IsOfficerByName and BRutus:IsOfficerByName(author)) then return end
    local incomingAt = tonumber(info.updatedAt) or 0
    local cur = BRutus.db.guildRecruitment
    if cur and cur.updatedAt and incomingAt < cur.updatedAt then return end
    BRutus.db.guildRecruitment = {
        enabled   = info.enabled,
        discord   = info.discord or "",
        message   = info.message or "",
        channels  = info.channels or {},
        interval  = info.interval or 120,
        updatedAt = incomingAt > 0 and incomingAt or time(),
        updatedBy = author,
    }
    if BRutus.recruitmentPanelRefresh then BRutus.recruitmentPanelRefresh() end
    self:SyncMemberParticipation()
end

-- Member opt-out choice (persisted, tri-state).
function Recruitment:SetParticipation(v)
    BRutus.db.recruitParticipate = v
    self:SyncMemberParticipation()
end

-- Reconcile the member popup ticker and the one-time prompt with the current
-- guild config and the stored choice. Safe to call repeatedly.
function Recruitment:SyncMemberParticipation()
    if BRutus:IsOfficer() then return end   -- officers use their own flow
    local info = BRutus.db.guildRecruitment
    local active = info and info.enabled and info.message and info.message ~= ""
    if not active then
        if self:IsMemberRecruitActive() then self:StopMemberRecruit() end
        return
    end
    local choice = BRutus.db.recruitParticipate
    if choice == true then
        if not self:IsMemberRecruitActive() then self:StartMemberRecruit() end
    elseif choice == false then
        if self:IsMemberRecruitActive() then self:StopMemberRecruit() end
    else
        self:PromptParticipation()
    end
end

-- One-time "help recruit?" prompt (deduped per session; decision persists).
function Recruitment:PromptParticipation()
    if self._promptShown then return end
    if BRutus.db.recruitParticipate ~= nil then return end
    if InCombatLockdown and InCombatLockdown() then return end
    self._promptShown = true
    StaticPopup_Show("GUILDOS_RECRUIT_JOIN")
end

----------------------------------------------------------------------
-- Member-side setup — runs for EVERY player (unlike the officer-only
-- Initialize). Registers the opt-in prompt and reconciles participation
-- against the persisted/synced config on login, so members auto-fire the
-- recruit popup without any officer action on their client.
----------------------------------------------------------------------
function Recruitment:InitParticipation()
    StaticPopupDialogs["GUILDOS_RECRUIT_JOIN"] = {
        text = L["Your guild is recruiting! Show a periodic reminder so you can help post it in chat? (change anytime in the Recruitment tab)"],
        button1 = L["I'll help"],
        button2 = L["No thanks"],
        OnAccept = function() if BRutus.Recruitment then BRutus.Recruitment:SetParticipation(true) end end,
        OnCancel = function() if BRutus.Recruitment then BRutus.Recruitment:SetParticipation(false) end end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    C_Timer.After(15, function()
        if BRutus.Recruitment then BRutus.Recruitment:SyncMemberParticipation() end
    end)
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
    text:SetText(L["Click to send recruit msg!"])
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
        GameTooltip:AddLine(L["Guild OS Recruitment"], C.gold.r, C.gold.g, C.gold.b)
        GameTooltip:AddLine(L["Left-click to post recruitment message."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Drag to move. x to dismiss."], 0.5, 0.5, 0.5, true)
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
    if InCombatLockdown() then return end

    -- Officers use their own config; members use the guild-broadcast config
    local isOfficer = BRutus:IsOfficer()
    if isOfficer then
        if not BRutus.db.recruitment.enabled then return end
    else
        local info = BRutus.db.guildRecruitment
        if not info or not info.enabled or not info.message or info.message == "" then return end
    end

    self:CreatePopupFrame()

    self.popupFrame.label:SetText(L["Click to recruit!"])
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

    -- Officers use their own config; members use guild-broadcast config
    local settings = BRutus:IsOfficer()
        and BRutus.db.recruitment
        or  BRutus.db.guildRecruitment
    if not settings then
        BRutus:Print(L["|cffFF4444No recruitment data. Ask an officer to broadcast.|r"])
        return
    end
    local msg = settings.message
    if not msg or msg == "" then
        BRutus:Print(L["|cffFF4444No recruitment message set.|r"])
        return
    end

    local sent = false
    for _, channelName in ipairs(settings.channels or {}) do
        local channelNum = GetChannelName(channelName)
        if channelNum and channelNum > 0 then
            SendChatMessage(msg, "CHANNEL", nil, channelNum)
            sent = true
        end
    end

    if sent then
        self.lastSend = GetTime()
        BRutus:Print(L["Recruitment message sent!"])
    else
        BRutus:Print(L["|cffFF4444No valid channels found. Join a channel first.|r"])
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
            BRutus:Print(L["Recruitment message set to: |cffFFFFFF"] .. newMsg .. "|r")
        else
            BRutus:Print(L["Current message: |cffFFFFFF"] .. (BRutus.db.recruitment.message or L["(empty)"]) .. "|r")
        end
    elseif cmd == "interval" then
        local secs = tonumber(args[2])
        if secs and secs >= 60 then
            BRutus.db.recruitment.interval = secs
            BRutus:Print(string.format(L["Recruitment interval set to |cffFFFFFF%ds|r."], secs))
            -- Restart if active
            if BRutus.db.recruitment.enabled then
                self:StopAutoRecruit()
                self:StartAutoRecruit()
            end
        else
            BRutus:Print(L["Usage: /guildos recruit interval <seconds> (min 60)"])
        end
    elseif cmd == "channel" then
        local action = args[2]
        local chName = args[3]
        if action == "add" and chName then
            table.insert(BRutus.db.recruitment.channels, chName)
            BRutus:Print(L["Added channel: |cffFFFFFF"] .. chName .. "|r")
        elseif action == "remove" and chName then
            local channels = BRutus.db.recruitment.channels
            for i = #channels, 1, -1 do
                if channels[i]:lower() == chName:lower() then
                    table.remove(channels, i)
                    BRutus:Print(L["Removed channel: |cffFFFFFF"] .. chName .. "|r")
                    return
                end
            end
            BRutus:Print(L["Channel not found: "] .. chName)
        elseif action == "list" then
            local list = table.concat(BRutus.db.recruitment.channels, ", ")
            BRutus:Print(L["Channels: |cffFFFFFF"] .. (list ~= "" and list or L["(none)"]) .. "|r")
        else
            BRutus:Print(L["Usage: /guildos recruit channel <add|remove|list> [name]"])
        end
    elseif cmd == "status" then
        local s = BRutus.db.recruitment
        local status = s.enabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        local wStatus = s.welcomeEnabled and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]
        BRutus:Print(L["--- Recruitment Status ---"])
        BRutus:Print(L["Active: "] .. status)
        BRutus:Print(string.format(L["Interval: |cffFFFFFF%ds|r"], s.interval))
        BRutus:Print(L["Channels: |cffFFFFFF"] .. table.concat(s.channels, ", ") .. "|r")
        BRutus:Print(L["Message: |cffFFFFFF"] .. s.message .. "|r")
        BRutus:Print(L["Welcome: "] .. wStatus)
        BRutus:Print(L["Welcome msg: |cffFFFFFF"] .. s.welcomeMessage .. "|r")
        BRutus:Print(L["Discord: |cffFFFFFF"] .. s.discord .. "|r")
    elseif cmd == "welcome" then
        local sub = args[2]
        if sub == "on" then
            BRutus.db.recruitment.welcomeEnabled = true
            BRutus:Print(L["Welcome message |cff4CFF4Cenabled|r."])
        elseif sub == "off" then
            BRutus.db.recruitment.welcomeEnabled = false
            BRutus:Print(L["Welcome message |cffFF4444disabled|r."])
        elseif sub == "msg" then
            table.remove(args, 1)
            table.remove(args, 1)
            local newMsg = table.concat(args, " ")
            if newMsg and newMsg ~= "" then
                BRutus.db.recruitment.welcomeMessage = newMsg
                BRutus:Print(L["Welcome message set to: |cffFFFFFF"] .. newMsg .. "|r")
            else
                BRutus:Print(L["Current: |cffFFFFFF"] .. BRutus.db.recruitment.welcomeMessage .. "|r")
            end
        else
            BRutus:Print(L["Usage: /guildos recruit welcome <on|off|msg> [text]"])
        end
    elseif cmd == "discord" then
        local link = args[2]
        if link and link ~= "" then
            BRutus.db.recruitment.discord = link
            BRutus:Print(L["Discord link set to: |cffFFFFFF"] .. link .. "|r")
        else
            BRutus:Print(L["Discord: |cffFFFFFF"] .. BRutus.db.recruitment.discord .. "|r")
        end
    elseif cmd == "invite" then
        local target = args[2]
        if target and target ~= "" then
            if not CanGuildInvite() then
                BRutus:Print(L["|cffFF4444You don't have permission to invite.|r"])
                return
            end
            GuildInvite(target)
            BRutus:Print(L["Guild invite sent to |cffFFFFFF"] .. target .. "|r.")
        else
            BRutus:Print(L["Usage: /guildos recruit invite <PlayerName>"])
        end
    else
        BRutus:Print(L["|cffFFD700Recruitment commands:|r"])
        BRutus:Print("  /guildos recruit on/off")
        BRutus:Print("  /guildos recruit status")
        BRutus:Print("  /guildos recruit msg <text>")
        BRutus:Print("  /guildos recruit interval <seconds>")
        BRutus:Print("  /guildos recruit channel add/remove/list <name>")
        BRutus:Print("  /guildos recruit welcome on/off/msg <text>")
        BRutus:Print("  /guildos recruit discord <link>")
        BRutus:Print("  /guildos recruit invite <PlayerName>")
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
    self._welcomeIntents   = {}  -- [memberName] = { [officerName] = true, ... }

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

        -- Dedup: if already handled on this client, skip
        if Recruitment._welcomedRecently[newMember] then return end
        Recruitment._welcomedRecently[newMember] = true
        C_Timer.After(90, function()
            Recruitment._welcomedRecently[newMember] = nil
            Recruitment._welcomeIntents[newMember]  = nil
        end)

        -- Add to known members
        Recruitment._knownMembers[newMember] = true

        -- Phase 1: broadcast intent immediately so all online officers can collect intents.
        -- After 2 seconds the officer with the lexicographically lowest name wins and sends.
        -- This is deterministic across all clients — no race condition.
        Recruitment._welcomeIntents[newMember] = Recruitment._welcomeIntents[newMember] or {}
        Recruitment._welcomeIntents[newMember][myName] = true

        if BRutus.CommSystem then
            BRutus.CommSystem:SendMessage(
                BRutus.CommSystem.MSG_TYPES.WELCOME_INTENT, newMember, nil, "NORMAL")
        end

        C_Timer.After(2, function()
            -- Already suppressed by a WC claim from another officer?
            if Recruitment._welcomedRecently[newMember .. "_sent"] then return end

            -- Tiebreak: lowest name alphabetically among intents wins
            local intents = Recruitment._welcomeIntents[newMember] or {}
            local winner = myName
            for name in pairs(intents) do
                if name < winner then winner = name end
            end
            if winner ~= myName then return end  -- someone else wins

            Recruitment._welcomedRecently[newMember .. "_sent"] = true

            if BRutus.CommSystem then
                BRutus.CommSystem:SendMessage(
                    BRutus.CommSystem.MSG_TYPES.WELCOME_CLAIM, newMember, nil, "NORMAL")
            end

            local settings = BRutus.db.recruitment
            local welcomeMsg = settings.welcomeMessage
            if welcomeMsg and welcomeMsg ~= "" then
                SendChatMessage(welcomeMsg, "GUILD")
                BRutus:Print(L["Welcome message sent for |cffFFFFFF"] .. newMember .. L["|r in guild chat."])
            end
        end)
    end)
end
