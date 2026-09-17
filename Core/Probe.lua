----------------------------------------------------------------------
-- Guild OS - Probe (/guildos probe; ADR-0015)
-- Records which client this is and which of the APIs and events GuildOS
-- uses exist, into GuildOSDB.probe, and prints a one-screen summary. Built
-- for the WoW: Forever beta: a tester sends back one SavedVariables file
-- instead of typing /dump for an hour. Every read is guarded: a missing or
-- raising API is recorded and the probe carries on (Rule 4).
----------------------------------------------------------------------
local Probe = {}
BRutus.Probe = Probe
local L = BRutus.L

local PREFIX = "GuildOSProbe"  -- its own prefix, so no other GuildOS client parses the test message
local LIST_MAX = 10            -- missing names printed before the list is cut

-- The WoW globals GuildOS and its bundled libraries read (the 0.53.0
-- inventory). GuildFrame, CommunitiesFrame and WorldMapFrame load on demand
-- and read as missing until they have been opened once.
Probe.APIS = {
    -- Global functions
    "Ambiguate", "CanEditGuildInfo", "CanEditMOTD", "CanEditPublicNote", "CanGuildDemote", "CanGuildInvite",
    "CanGuildPromote", "CanGuildRemove", "CanInspect", "ChannelBan", "ChannelKick", "ChannelModerator",
    "ChatFrame_AddMessageEventFilter", "ChatFrame_OpenChat", "ChatFrame_SendTell", "CloseDropDownMenus",
    "CombatLogGetCurrentEventInfo", "CreateColor", "CreateFrame", "FauxScrollFrame_GetOffset",
    "FauxScrollFrame_OnVerticalScroll", "FauxScrollFrame_Update", "GetBuildInfo", "GetChannelName",
    "GetChannelRosterInfo", "GetContainerItemInfo", "GetContainerItemLink", "GetContainerNumSlots",
    "GetCraftDisplaySkillLine", "GetCraftInfo", "GetCraftItemLink", "GetCraftSpellLink", "GetCursorPosition",
    "GetGuildInfo", "GetGuildInfoText", "GetGuildRosterInfo", "GetGuildRosterLastOnline", "GetGuildRosterMOTD",
    "GetInstanceInfo", "GetInventoryItemLink", "GetItemCount", "GetItemInfo", "GetItemQualityColor",
    "GetLocale", "GetLootMethod", "GetLootSlotInfo", "GetLootSlotLink", "GetMasterLootCandidate", "GetNumCrafts",
    "GetNumGroupMembers", "GetNumGuildMembers", "GetNumLootItems", "GetNumSkillLines", "GetNumTalentTabs",
    "GetNumTalents", "GetNumTradeSkills", "GetRaidRosterInfo", "GetRealmName", "GetServerTime",
    "GetSkillLineInfo", "GetSpellInfo", "GetSpellTexture", "GetTalentInfo", "GetTime", "GetTradeSkillInfo",
    "GetTradeSkillItemLink", "GetTradeSkillLine", "GetTradeSkillRecipeLink", "GetUnitName", "GiveMasterLoot",
    "GuildControlGetNumRanks", "GuildControlGetRankName", "GuildInvite", "GuildRoster", "GuildRosterSetPublicNote",
    "GuildSetMOTD", "HideUIPanel", "InCombatLockdown", "InspectUnit", "InviteByName", "InviteUnit",
    "IsAltKeyDown", "IsInGroup", "IsInGuild", "IsInInstance", "IsInRaid", "IsMasterLooter",
    "IsQuestFlaggedCompleted", "IsShiftKeyDown", "JoinChannelByName", "LeaveChannelByName", "NotifyInspect",
    "PlaySound", "RaidNotice_AddMessage", "RandomRoll", "ReloadUI", "SendChatMessage", "SendWho",
    "SetChannelOwner", "SetGuildInfoText", "SetGuildTabardTextures", "SetRaidSubgroup", "SetWhoToUI",
    "ShowUIPanel", "StaticPopup_Show", "TargetUnit", "ToggleDropDownMenu", "ToggleGuildFrame", "ToggleWorldMap",
    "UIDropDownMenu_AddButton", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize", "UIFrameFadeIn",
    "UnitBuff", "UnitClass", "UnitExists", "UnitFactionGroup", "UnitGUID", "UnitHealthMax", "UnitIsConnected",
    "UnitIsGroupAssistant", "UnitIsGroupLeader", "UnitIsPlayer", "UnitLevel", "UnitName", "UnitPlayerControlled",
    "UnitPowerMax", "UnitRace", "UnitSex", "UnitStat", "UseContainerItem", "debugstack", "geterrorhandler",
    "hooksecurefunc", "securecallfunction", "tContains",
    -- hooksecurefunc targets not listed above
    "SetItemRef", "ContainerFrameItemButton_OnModifiedClick", "HandleModifiedItemClick", "WorldMapFrame.OnMapChanged",
    -- C_ namespaces
    "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage", "C_Container.GetContainerItemInfo",
    "C_Container.GetContainerItemLink", "C_Container.GetContainerNumSlots", "C_Container.UseContainerItem",
    "C_FriendList.GetNumWhoResults", "C_FriendList.GetWhoInfo", "C_FriendList.SendWho", "C_FriendList.SetWhoToUI",
    "C_GuildInfo.GuildRoster", "C_GuildInfo.SetNote", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo",
    "C_Map.GetPlayerMapPosition", "C_PartyInfo.GetLootMethod", "C_PartyInfo.InviteUnit",
    "C_QuestLog.GetTitleForQuestID", "C_QuestLog.IsQuestFlaggedCompleted", "C_Timer.After", "C_Timer.NewTicker",
    "C_Timer.NewTimer",
    -- Read only by the bundled libraries
    "C_ChatInfo.SendChatMessage", "C_ChatInfo.SendAddonMessageLogged", "BNSendGameData",
    "Enum.SendAddonMessageResult", "UnitIsGhost", "RegisterAddonMessagePrefix",
    -- Frames, tables and constants
    "UIParent", "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "Minimap",
    "WorldMapFrame", "GuildFrame", "CommunitiesFrame", "DEFAULT_CHAT_FRAME", "RaidWarningFrame",
    "TradeFrameRecipientNameText", "UISpecialFrames", "StaticPopupDialogs", "SlashCmdList", "ChatTypeInfo",
    "GameFontNormalSmall", "STANDARD_TEXT_FONT", "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS",
    "LOCALIZED_CLASS_NAMES_MALE", "SOUNDKIT", "RANDOM_ROLL_RESULT", "RESISTANCE2_NAME", "RESISTANCE3_NAME",
    "RESISTANCE4_NAME", "RESISTANCE5_NAME", "RESISTANCE6_NAME",
}

-- Templates the addon inherits, with the frame type each one needs.
Probe.TEMPLATES = {
    { "BackdropTemplate", "Frame" }, { "UIPanelScrollFrameTemplate", "ScrollFrame" },
    { "FauxScrollFrameTemplate", "ScrollFrame" }, { "InputBoxTemplate", "EditBox" },
    { "UICheckButtonTemplate", "CheckButton" }, { "UIPanelButtonTemplate", "Button" },
    { "UIDropDownMenuTemplate", "Frame" }, { "OptionsSliderTemplate", "Slider" },
    { "GameTooltipTemplate", "GameTooltip" },
}

-- Tooltip scripts the addon hooks.
Probe.SCRIPTS = { "OnTooltipSetItem", "OnTooltipSetSpell", "OnTooltipSetUnit", "OnTooltipCleared" }

-- Every event the addon's own files register. tools/probe.lua fails when the
-- source registers one that is not listed here.
Probe.EVENTS = {
    "ADDON_LOADED", "CHANNEL_UI_UPDATE", "CHARACTER_POINTS_CHANGED", "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_SKILL", "CHAT_MSG_SYSTEM", "CHAT_MSG_WHISPER",
    "COMBAT_LOG_EVENT_UNFILTERED", "CRAFT_SHOW", "ENCOUNTER_END", "ENCOUNTER_START", "GET_ITEM_INFO_RECEIVED",
    "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "INSPECT_READY", "LOOT_CLOSED", "LOOT_OPENED",
    "PARTY_LOOT_METHOD_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_GUILD_UPDATE",
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TALENT_UPDATE",
    "PLAYER_TARGET_CHANGED", "QUEST_TURNED_IN", "RAID_ROSTER_UPDATE", "SKILL_LINES_CHANGED",
    "TRADE_ACCEPT_UPDATE", "TRADE_SHOW", "TRADE_SKILL_SHOW", "UPDATE_MOUSEOVER_UNIT", "WHO_LIST_UPDATE",
    "ZONE_CHANGED_NEW_AREA",
}

-- Look up "Name", "C_Namespace.Function" or "Frame.Method" in _G.
local function resolve(name)
    local value = _G
    for part in name:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function present(name)
    local ok, value = pcall(resolve, name)
    return ok and value ~= nil
end

-- Call `fn` and keep every return. A missing function or an error is
-- recorded in the result, never raised.
local function capture(fn, ...)
    if type(fn) ~= "function" then return { missing = true } end
    local res = { pcall(fn, ...) }
    if not res[1] then return { error = tostring(res[2]) } end
    local out = {}
    for i = 2, table.maxn(res) do out[i - 1] = res[i] end
    return out
end

-- The first return of a capture, or what went wrong, as something printable.
local function first(res)
    if res.missing then return "missing" end
    if res.error then return "error: " .. res.error end
    return res[1]
end

-- A namespace function, or nil when the namespace itself is missing.
local function member(namespace, name)
    if type(namespace) ~= "table" then return nil end
    local ok, value = pcall(function() return namespace[name] end)
    return ok and value or nil
end

function Probe:Run()
    if InCombatLockdown and InCombatLockdown() then
        BRutus:Print(L["The probe does not run in combat. Try again after the fight."])
        return nil
    end

    local clockOk, now = pcall(GetServerTime)
    local r = {
        at = (clockOk and now) or (time and time()) or 0,
        addonVersion = BRutus.VERSION,
        build = capture(GetBuildInfo),
        projectId = WOW_PROJECT_ID,
        client = BRutus.Client,
        gameMode = capture(member(C_GameRules, "GetActiveGameMode")),
        secrets = {
            issecretvalue = issecretvalue ~= nil,
            C_Secrets = C_Secrets ~= nil,
            C_RestrictedActions = C_RestrictedActions ~= nil,
            -- Present is not enforced: 2.5.6 already ships the API. This is the build's own answer.
            restricted = first(capture(member(C_Secrets, "HasSecretRestrictions"))),
        },
        chat = {
            lockdown = capture(member(C_ChatInfo, "InChatMessagingLockdown")),
            instance = capture(IsInInstance),
        },
    }

    if IsInGuild and IsInGuild() then
        r.roster = {
            -- The name only: the same row carries the member's public and officer notes.
            firstName = first(capture(GetGuildRosterInfo, 1)),
            realm = first(capture(GetNormalizedRealmName)),
            -- Member keys ask this one first (ADR-0018): both answers show which one a realm-less client gives.
            realmName = first(capture(GetRealmName)),
        }
        pcall(BRutus.Compat.RegisterAddonPrefix, PREFIX)
        r.guildMessage = capture(member(C_ChatInfo, "SendAddonMessage"), PREFIX, "probe", "GUILD")
    else
        r.roster, r.guildMessage = "not in guild", "not in guild"
    end

    r.apis, r.missingApis = {}, {}
    local function record(name, ok)
        r.apis[name] = ok
        if not ok then r.missingApis[#r.missingApis + 1] = name end
    end
    for _, name in ipairs(self.APIS) do record(name, present(name)) end

    -- Templates: ask the client when it can say, instead of building frames.
    local templateInfo = member(C_XMLUtil, "GetTemplateInfo")
    for _, t in ipairs(self.TEMPLATES) do
        if templateInfo then
            local ok, info = pcall(templateInfo, t[1])
            record(t[1], ok and info ~= nil)
        else
            -- A named frame: some templates build their children's names from it.
            local ok, frame = pcall(CreateFrame, t[2], "GuildOSProbe" .. t[1], nil, t[1])
            if ok and type(frame) == "table" and frame.Hide then pcall(frame.Hide, frame) end
            record(t[1], ok and frame ~= nil)
        end
    end
    for _, script in ipairs(self.SCRIPTS) do
        local ok, has = pcall(function() return GameTooltip:HasScript(script) end)
        record("GameTooltip:" .. script, (ok and has) and true or false)
    end

    -- One throwaway frame; each event it takes is released at once.
    r.events, r.missingEvents = {}, {}
    local frameOk, frame = pcall(CreateFrame, "Frame")
    frameOk = frameOk and type(frame) == "table"
    for _, event in ipairs(self.EVENTS) do
        local ok = frameOk and pcall(frame.RegisterEvent, frame, event) or false
        if ok then pcall(frame.UnregisterEvent, frame, event) end
        r.events[event] = ok
        if not ok then r.missingEvents[#r.missingEvents + 1] = event end
    end

    if not GuildOSDB then GuildOSDB = {} end
    GuildOSDB.probe = r
    self:PrintSummary(r)
    return r
end

-- true/false as yes/no; "missing" and errors as they are.
local function answer(v)
    if v == true then return L["yes"] end
    if v == false then return L["no"] end
    return tostring(v)
end

local function names(list)
    local shown = {}
    for i = 1, math.min(#list, LIST_MAX) do shown[i] = list[i] end
    return table.concat(shown, ", ") .. (#list > LIST_MAX and ", ..." or "")
end

function Probe:PrintSummary(r)
    local b = r.build
    BRutus:Print(string.format(L["Probe: build %s (%s), interface %s, project %s."],
        tostring(first(b)), tostring(b[2]), tostring(b[4]), tostring(r.projectId)))
    BRutus:Print(string.format(L["TBC Anniversary: %s. Secret Values restricted: %s. Chat lockdown here: %s (%s)."],
        answer(r.client and r.client.isAnniversary or false), answer(r.secrets.restricted),
        answer(first(r.chat.lockdown)), tostring(r.chat.instance[2] or first(r.chat.instance))))
    BRutus:Print(string.format(L["Missing: %d of %d APIs, %d of %d events."],
        #r.missingApis, #self.APIS + #self.TEMPLATES + #self.SCRIPTS, #r.missingEvents, #self.EVENTS))
    if #r.missingApis > 0 then BRutus:Print(names(r.missingApis)) end
    if #r.missingEvents > 0 then BRutus:Print(names(r.missingEvents)) end
    BRutus:Print(L["Saved in GuildOSDB.probe. Type /reload to write it to disk."])
end
