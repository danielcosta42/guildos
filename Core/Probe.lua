----------------------------------------------------------------------
-- Guild OS - Probe (/guildos probe; ADR-0015)
-- Records which client this is and which of the APIs and events GuildOS
-- uses exist, into GuildOSDB.probe, and prints a one-screen summary. Built
-- for the WoW: Forever beta: a tester sends back one SavedVariables file
-- instead of typing /dump for an hour. Every read is guarded: a missing or
-- raising API is recorded and the probe carries on (Rule 4).
----------------------------------------------------------------------
local Probe = {}
GuildOS.Probe = Probe
local L = GuildOS.L

local PREFIX = "GuildOSProbe"  -- its own prefix, so no other GuildOS client parses the test message
local LIST_MAX = 10            -- missing names printed before the list is cut

-- The WoW globals GuildOS and its bundled libraries read (the 0.53.0
-- inventory). GuildFrame, CommunitiesFrame and WorldMapFrame load on demand
-- and read as missing until they have been opened once.
Probe.APIS = {
    -- Global functions
    "Ambiguate", "CanEditGuildInfo", "CanEditMOTD", "CanEditPublicNote", "CanGuildDemote", "CanGuildInvite",
    "CanGuildPromote", "CanGuildRemove", "CanInspect", "CanViewOfficerNote", "ChannelBan", "ChannelKick", "ChannelModerator",
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
    "UnitBuff", "UnitClass", "UnitExists", "UnitFactionGroup", "UnitFullName", "UnitGUID", "UnitHealthMax", "UnitIsConnected",
    "UnitIsGroupAssistant", "UnitIsGroupLeader", "UnitIsPlayer", "UnitIsUnit", "UnitLevel", "UnitName", "UnitPlayerControlled",
    "UnitPowerMax", "UnitRace", "UnitSex", "UnitStat", "UseContainerItem", "debugstack", "geterrorhandler",
    "hooksecurefunc", "securecallfunction", "tContains",
    -- hooksecurefunc targets not listed above
    "SetItemRef", "ContainerFrameItemButton_OnModifiedClick", "HandleModifiedItemClick", "WorldMapFrame.OnMapChanged",
    -- C_ namespaces
    "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage", "C_Container.GetContainerItemInfo",
    "C_Container.GetContainerItemLink", "C_Container.GetContainerNumSlots", "C_Container.UseContainerItem",
    "C_FriendList.GetNumWhoResults", "C_FriendList.GetWhoInfo", "C_FriendList.SendWho", "C_FriendList.SetWhoToUi",
    "C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator",
    "C_GuildInfo.CanViewOfficerNote", "C_GuildInfo.GuildRoster", "C_GuildInfo.SetNote", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo",
    "C_Map.GetPlayerMapPosition", "C_PartyInfo.GetLootMethod", "C_PartyInfo.InviteUnit", "C_PlayerInfo.ShouldDisplaySurname",
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
    -- What the Forever port reads or will read (docs/forever/README.md): the Secret Values checks,
    -- the retail talents and professions that replace talent tabs and the trade-skill window, and
    -- the chat filter's retail home.
    "issecretvalue", "canaccessvalue", "C_Secrets.ShouldUnitIdentityBeSecret", "C_ClassTalents.GetActiveConfigID",
    "C_Traits.GetConfigInfo", "C_TradeSkillUI.GetAllProfessionTradeSkillLines", "C_TradeSkillUI.GetBaseProfessionInfo",
    -- WoW: Forever professions (issue #31).
    "GetProfessions", "GetProfessionInfo", "IsPlayerSpell", "C_TradeSkillUI.GetAllRecipeIDs",
    "C_InstanceEncounter.IsEncounterInProgress", "IsEncounterInProgress",
    "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.IsDataSourceChanging", "C_Club.GetGuildClubId", "C_Club.GetMemberInfo",
    -- The guild's chat as the server keeps it (issue #126).
    "C_Club.GetStreams", "C_Club.GetMessageRanges", "C_Club.GetMessagesBefore", "C_Club.FocusStream",
    "C_Club.UnfocusStream", "C_Club.RequestMoreMessagesBefore", "C_Club.SendMessage", "GetClassInfo",
    "ChatFrameUtil.AddMessageEventFilter",
    -- The retail tooltip (issue #19): where the OnTooltipSet* scripts below are absent, the hook
    -- and the reading happen through these instead. A client with the processor and no TooltipUtil
    -- can hook and not read, so both are asked for.
    "TooltipDataProcessor.AddTooltipPostCall", "TooltipUtil.GetDisplayedItem",
    "TooltipUtil.GetDisplayedSpell", "TooltipUtil.GetDisplayedUnit",
    -- Retail (ADR-0026): the spec the client names, the item level as worn and the game's own
    -- average, a weapon told from a shield by id, and the realm keys are spelt with (issue #177).
    "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo",
    "C_SpecializationInfo.GetInspectSpecialization", "GetSpecializationInfoForSpecID",
    "C_Item.GetDetailedItemLevelInfo", "GetAverageItemLevel", "C_Item.GetItemInfoInstant", "GetNormalizedRealmName",
    -- Retail (issue #184): an inspected guildmate's average item level, and the character sheet's ratings.
    "C_PaperDollInfo.GetInspectItemLevel", "GetCritChance", "GetRangedCritChance", "GetSpellCritChance", "GetHaste",
    "GetMasteryEffect", "GetCombatRatingBonus", "GetVersatilityBonus",
    -- The lockout week (guildos-web#199): the region whose reset counts it, and the client's own count of
    -- the seconds to that reset, which the self-test compares with the table.
    "GetCurrentRegion", "C_DateAndTime.GetSecondsUntilWeeklyReset",
    -- Retail (issue #187): the raid's consumables read from its auras, whether the client keeps them
    -- secret, my weapon's oil.
    "C_UnitAuras.GetBuffDataByIndex", "C_Secrets.ShouldAurasBeSecret", "GetWeaponEnchantInfo",
    -- Retail (issue #187): my keystone and rating, a dungeon named, the Great Vault and the week.
    "C_MythicPlus.RequestMapInfo", "C_MythicPlus.GetOwnedKeystoneChallengeMapID", "C_MythicPlus.GetOwnedKeystoneLevel",
    "C_ChallengeMode.GetOverallDungeonScore", "C_ChallengeMode.GetMapUIInfo", "C_ChallengeMode.GetDungeonScoreRarityColor",
    "C_WeeklyRewards.GetActivities", "Enum.WeeklyRewardChestThresholdType", "C_DateAndTime.GetWeeklyResetStartTime",
    -- Retail (issue #185): the wishlist's items from the Encounter Journal.
    "EJ_SelectInstance", "EJ_SelectEncounter", "EJ_GetNumLoot", "EJ_GetLootFilter", "EJ_SetLootFilter",
    "EJ_GetEncounterInfo", "EJ_GetInstanceInfo", "C_EncounterJournal.GetLootInfoByIndex",
    "C_EncounterJournal.GetSlotFilter", "C_EncounterJournal.ResetSlotFilter", "C_EncounterJournal.SetSlotFilter",
    -- Retail (issue #185): the loot council by trade, a personal item's trade window on its tooltip.
    "C_TooltipInfo.GetBagItem", "GetTradePlayerItemLink", "Enum.TooltipDataLineType", "ERR_TRADE_COMPLETE",
    "INT_SPELL_DURATION_HOURS", "INT_SPELL_DURATION_MIN",
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
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "ADDON_LOADED",
    "CALENDAR_CLOSE_EVENT", "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_ERROR", "CALENDAR_UPDATE_EVENT_LIST",   -- the game's calendar (#263)
    "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE",
    "CHANNEL_UI_UPDATE", "CHARACTER_POINTS_CHANGED", "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_SKILL", "CHAT_MSG_SYSTEM", "CHAT_MSG_WHISPER", "CLUB_MESSAGE_ADDED",
    "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_STREAM_ADDED", "CLUB_STREAM_REMOVED", "CLUB_STREAMS_LOADED",
    "COMBAT_LOG_EVENT_UNFILTERED", "CRAFT_SHOW", "EJ_LOOT_DATA_RECIEVED", "ENCOUNTER_END", "ENCOUNTER_LOOT_RECEIVED", "ENCOUNTER_START", "GET_ITEM_INFO_RECEIVED",
    "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "INSPECT_READY", "LOOT_CLOSED", "LOOT_OPENED",
    "MACRO_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN", "PARTY_LOOT_METHOD_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_GUILD_UPDATE", "PLAYER_LEVEL_UP",
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE",
    "PLAYER_TARGET_CHANGED", "QUEST_TURNED_IN", "RAID_ROSTER_UPDATE", "READY_CHECK", "READY_CHECK_FINISHED",
    "SKILL_LINES_CHANGED",
    "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_SHOW", "TRADE_SKILL_SHOW", "UI_INFO_MESSAGE",
    "UPDATE_MOUSEOVER_UNIT", "WEEKLY_REWARDS_UPDATE", "WHO_LIST_UPDATE",
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
        GuildOS:Print(L["The probe does not run in combat. Try again after the fight."])
        return nil
    end

    local clockOk, now = pcall(GetServerTime)
    local r = {
        at = (clockOk and now) or (time and time()) or 0,
        addonVersion = GuildOS.VERSION,
        build = capture(GetBuildInfo),
        projectId = WOW_PROJECT_ID,
        client = GuildOS.Client,
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
        pcall(GuildOS.Compat.RegisterAddonPrefix, PREFIX)
        r.guildMessage = capture(member(C_ChatInfo, "SendAddonMessage"), PREFIX, "probe", "GUILD")
    else
        r.roster, r.guildMessage = "not in guild", "not in guild"
    end

    -- WoW: Forever professions (issue #31): which catalog build the client carries, and how many
    -- learned recipes it found that the catalog does not have (a sign to regenerate it).
    if GuildOS.Professions and GuildOS.ProfCatalog then
        local own = GuildOS.db and GuildOS.db.professions and GuildOS.db.professions[GuildOS.Professions.OwnKey()]
        local lines, extra = 0, 0
        for _, e in pairs((own and own.profs) or {}) do
            lines = lines + 1
            extra = extra + #(e.extra or {})
        end
        r.professions = { catalog = GuildOS.ProfCatalog.build, lines = lines, extra = extra }
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

-- The game this client was taken for, by name (issue #177): the probe on retail said only
-- "TBC Anniversary: no".
local GAME_NAMES = { ANNIVERSARY = "TBC Anniversary", FOREVER = "WoW: Forever", RETAIL = "Retail" }
local function gameName(c)
    c = c or {}
    local game = c.game or (c.isAnniversary and "ANNIVERSARY") or (c.isRetail and "RETAIL") or "FOREVER"
    return GAME_NAMES[game] or tostring(game)
end

function Probe:PrintSummary(r)
    local b = r.build
    GuildOS:Print(string.format(L["Probe: build %s (%s), interface %s, project %s."],
        tostring(first(b)), tostring(b[2]), tostring(b[4]), tostring(r.projectId)))
    GuildOS:Print(string.format(L["Client: %s. Secret Values restricted: %s. Chat lockdown here: %s (%s)."],
        gameName(r.client), answer(r.secrets.restricted),
        answer(first(r.chat.lockdown)), tostring(r.chat.instance[2] or first(r.chat.instance))))
    GuildOS:Print(string.format(L["Missing: %d of %d APIs, %d of %d events."],
        #r.missingApis, #self.APIS + #self.TEMPLATES + #self.SCRIPTS, #r.missingEvents, #self.EVENTS))
    if #r.missingApis > 0 then GuildOS:Print(names(r.missingApis)) end
    if #r.missingEvents > 0 then GuildOS:Print(names(r.missingEvents)) end
    GuildOS:Print(L["Saved in GuildOSDB.probe. Type /reload to write it to disk."])
end

----------------------------------------------------------------------
-- Blocked actions (issue #75)
-- When the game blocks a protected call, chat gets "Interface action failed because of an
-- AddOn", once a session: no Lua error and no function named. These events carry the addon
-- (a macro's carry only the function) and the function, so /guildos errors can say who it
-- was. Each pair is recorded once a session: a noisy addon blocks thousands of times and the
-- ring holds 50. A chat probe that is running keeps every one.
----------------------------------------------------------------------
local BLOCKS_SHOWN = 5  -- blocks the chat probe's verdict prints; GuildOSDB.probeChat keeps all
local seenBlocks = {}

local blockedFrame = CreateFrame("Frame")
GuildOS.Compat.RegisterEvent(blockedFrame, "ADDON_ACTION_BLOCKED")
GuildOS.Compat.RegisterEvent(blockedFrame, "ADDON_ACTION_FORBIDDEN")
GuildOS.Compat.RegisterEvent(blockedFrame, "MACRO_ACTION_BLOCKED")
GuildOS.Compat.RegisterEvent(blockedFrame, "MACRO_ACTION_FORBIDDEN")
blockedFrame:SetScript("OnEvent", function(_, event, addon, func)
    if event:find("^MACRO_") then addon, func = "macro", addon end
    if GuildOS.Compat.IsSecret(addon, func) then addon, func = "?", "?" end
    addon, func = tostring(addon), tostring(func)
    local key = event .. "\0" .. addon .. "\0" .. func
    if not seenBlocks[key] then
        seenBlocks[key] = true
        GuildOS:RecordError(string.format("%s: %s tried %s", event, addon, func))
    end
    local run = Probe._chat
    if run then
        run.blocked[#run.blocked + 1] = { event = event, addon = addon, func = func, after = GetTime() - run.started }
    end
end)

----------------------------------------------------------------------
-- /guildos probe chat (issue #75)
-- Whether this client lets an addon post to guild chat from a key press and from a timer,
-- measured instead of assumed. Two lines go to guild chat: one straight from the command (the
-- Enter that sent it is the key press) and one from a one-second timer, the way the welcome
-- used to go. A line counts as sent when the game echoes it back in CHAT_MSG_GUILD. The verdict
-- comes CHAT_WAIT seconds later, set against Compat.NeedsClick(), and goes to
-- GuildOSDB.probeChat.
----------------------------------------------------------------------
local CHAT_WAIT = 6  -- seconds: the timer's line goes at 1, and echoes come back well inside this

-- The retail client's own answer to "is something restricting addons right now": one of
-- Combat, Encounter, ChallengeMode, PvPMatch, Map or Chat. The names that are active, sorted,
-- or "missing" on a client without the API.
local function activeRestrictions()
    local types = Enum and Enum.AddOnRestrictionType
    local isActive = member(C_RestrictedActions, "IsAddOnRestrictionActive")
    if type(types) ~= "table" or not isActive then return "missing" end
    local out = {}
    for name, value in pairs(types) do
        local ok, on = pcall(isActive, value)
        if ok and on == true then out[#out + 1] = tostring(name) end
    end
    table.sort(out)
    return out
end

function Probe:RunChat()
    if InCombatLockdown and InCombatLockdown() then
        GuildOS:Print(L["The probe does not run in combat. Try again after the fight."])
        return nil
    end
    if not (IsInGuild and IsInGuild()) then
        GuildOS:Print(L["The chat probe posts in guild chat. Join a guild first."])
        return nil
    end
    if self._chat then
        GuildOS:Print(L["The chat probe is already running."])
        return nil
    end

    -- English on purpose: it is matched against its own echo, and the guild reads it as a test.
    local tag = "[Guild OS probe " .. math.random(1000, 9999) .. "]"
    local clockOk, now = pcall(GetServerTime)
    local b = capture(GetBuildInfo)
    local run = {
        at = (clockOk and now) or 0,
        started = GetTime(),
        -- Version and build: every Forever beta build is version 1.60.1.
        build = b[2] and (tostring(first(b)) .. "." .. tostring(b[2])) or tostring(first(b)),
        lockdown = first(capture(member(C_ChatInfo, "InChatMessagingLockdown"))),
        restrictions = activeRestrictions(),
        assumesClick = GuildOS.Compat.NeedsClick(),
        steps = {
            { how = "command", text = tag .. " 1/2 sent from a command" },
            { how = "timer", text = tag .. " 2/2 sent from a timer" },
        },
        blocked = {},
    }
    self._chat = run

    self._chatFrame = self._chatFrame or CreateFrame("Frame")
    self._chatFrame:SetScript("OnEvent", function(_, _, msg)
        if GuildOS.Compat.IsSecret(msg) then
            run.unreadable = true
            return
        end
        for _, step in ipairs(run.steps) do
            if msg == step.text then step.echoed = true end
        end
    end)
    GuildOS.Compat.RegisterEvent(self._chatFrame, "CHAT_MSG_GUILD")

    -- The same global the welcome calls, so this tests what the welcome does.
    local function send(step)
        step.echoed = false
        step.sentAfter = GetTime() - run.started
        step.restrictions = activeRestrictions()   -- what was restricting addons as this line went
        local ok, err = pcall(SendChatMessage, step.text, "GUILD")
        if not ok then step.error = tostring(err) end
    end
    GuildOS:Print(L["Chat probe: one test line goes to guild chat now and one in a second. The verdict follows in a few seconds."])
    send(run.steps[1])
    GuildOS.Compat.After(1, function()
        if Probe._chat == run then send(run.steps[2]) end  -- never after the verdict
    end)
    GuildOS.Compat.After(CHAT_WAIT, function() Probe:FinishChat() end)
    return run
end

function Probe:FinishChat()
    local run = self._chat
    if not run then return end
    self._chat = nil
    pcall(self._chatFrame.UnregisterEvent, self._chatFrame, "CHAT_MSG_GUILD")

    local fromCommand, fromTimer = run.steps[1], run.steps[2]
    if not fromCommand.echoed or fromTimer.sentAfter == nil then
        run.needsClick = "unknown"   -- not even the key press got through, or the timer's never went
    elseif run.unreadable and not fromTimer.echoed then
        run.needsClick = "unknown"   -- the timer's echo may have come back unreadable
    else
        run.needsClick = not fromTimer.echoed
    end
    run.started = nil
    if not GuildOSDB then GuildOSDB = {} end
    GuildOSDB.probeChat = run

    GuildOS:Print(string.format(L["Chat probe, build %s, chat lockdown %s:"], run.build, answer(run.lockdown)))
    local r = run.restrictions
    GuildOS:Print("  " .. string.format(L["Addon restrictions: %s."],
        r == "missing" and L["not on this client"] or (#r == 0 and L["none active"] or table.concat(r, ", "))))
    local labels = { command = L["the line sent from the command"], timer = L["the line sent from a timer"] }
    for _, step in ipairs(run.steps) do
        local outcome = step.sentAfter == nil and L["not sent"]
            or step.echoed and L["came back in guild chat"] or L["did not come back"]
        if step.error then outcome = outcome .. " (" .. step.error .. ")" end
        GuildOS:Print(string.format("  %s (%.1fs): %s", labels[step.how], step.sentAfter or 0, outcome))
    end
    if #run.blocked == 0 then
        GuildOS:Print("  " .. L["The game reported no blocked action."])
    end
    for i = 1, math.min(#run.blocked, BLOCKS_SHOWN) do
        local blk = run.blocked[i]
        GuildOS:Print(string.format("  " .. L["Blocked by the game (%.1fs): %s tried %s."], blk.after, blk.addon, blk.func))
    end
    if #run.blocked > BLOCKS_SHOWN then
        GuildOS:Print("  " .. string.format(L["... and %d more."], #run.blocked - BLOCKS_SHOWN))
    end
    if run.needsClick == "unknown" then
        GuildOS:Print(run.unreadable and L["Could not tell: this client keeps guild chat unreadable here."]
            or not fromCommand.echoed and L["Could not tell: not even the line from the command came back."]
            or L["Could not tell: the verdict came before the line from the timer went out."])
    else
        GuildOS:Print(string.format(L["Chat needs a click: %s. Guild OS assumes: %s."],
            answer(run.needsClick), answer(run.assumesClick)))
    end
    GuildOS:Print(L["Saved in GuildOSDB.probeChat. Type /reload to write it to disk."])
end

----------------------------------------------------------------------
-- /gos probe channel (specs/071-o-recrutamento in guildos-web)
-- Whether an addon message may go through a created channel, measured: the one thing the recruitment's
-- beacon would use to reach past the zone and the layer that YELL stops at. The probe joins a temporary
-- channel of its own, sends one message from the command (the Enter behind it is the key press) and one
-- from a timer, listens for its own text coming back, leaves, and keeps the result in
-- GuildOSDB.probeChannel = { timer, click, timerSkipped, clickSkipped, heard = { timer, click }, joined, left, at }:
-- timer and click are true (the game took the message), false (it was tried and the game did not) or nil
-- (never tried, and <how>Skipped says why: the channel had no number yet), and heard says it came back through
-- the channel. The channel always ends, whatever went wrong, and nothing is said in any chat but the player's
-- own window. GuildOSDB.probeChannelOpen holds the running channel's name, so that one a /reload cut short goes.
----------------------------------------------------------------------
local CHANNEL_WAIT = 15        -- seconds until the verdict: long enough to press the command a second time
Probe.CHANNEL_WAIT = CHANNEL_WAIT   -- the Audit panel reads the result one second after it
local CHANNEL_TIMER_AT = 2
local STALE_WAIT = 15          -- seconds after login before a channel a /reload left behind can be left
local STALE_AGAIN = 10         -- seconds until a leave is looked at, and tried again if the channel is still there
local STALE_TRIES = 5          -- leaves at most, per login or run

-- The join and leave lines of the probe's channel are the player's own business, and none needs reading.
-- The client hands the channel as "5. GOSProbe1234" and its base name ninth, so either one names it.
local function hideChannelNotice(_, _, _, _, _, channel, _, _, _, _, base)
    local name = Probe._channelName
    if not name or GuildOS.Compat.IsSecret(channel, base) then return false end
    if type(base) == "string" and base == name then return true end
    return type(channel) == "string" and channel:find(name, 1, true) ~= nil
end

-- A run that a /reload cut short leaves its channel joined: the name was kept in GuildOSDB, and it goes now.
-- The name of the probe that is running is no leftover: the wait below can come due in the middle of a run.
-- The game may drop a leave that comes from a timer, and says nothing, so the name is cleared only once the
-- channel is seen gone, on a later try. STALE_TRIES leaves at most: what is still there then keeps its name
-- for the next login or the next key press. `stale` and `try` are for the tries after the first.
function Probe:LeaveStaleChannel(stale, try)
    stale = stale or (GuildOSDB and GuildOSDB.probeChannelOpen)
    try = try or 1
    if type(stale) ~= "string" or (self._channel and self._channel.name == stale) then return end
    local Compat = GuildOS.Compat
    if try > 1 and Compat.ChannelId(stale) <= 0 then
        if GuildOSDB and GuildOSDB.probeChannelOpen == stale then GuildOSDB.probeChannelOpen = nil end
        return
    end
    if try > STALE_TRIES then return end
    Compat.LeaveChannel(stale)
    Compat.After(STALE_AGAIN, function() GuildOS:SafeCall(Probe.LeaveStaleChannel, Probe, stale, try + 1) end)
end

-- Started with the modules. At PLAYER_LOGIN the game has not joined the character's channels yet, and
-- leaving one then would do nothing: the wait is for the game.
function Probe:Initialize()
    GuildOS.Compat.After(STALE_WAIT, function() GuildOS:SafeCall(Probe.LeaveStaleChannel, Probe) end)
end

-- One attempt to send `how` ("click" or "timer"). A channel with no number yet is not a refusal by the
-- game: it is an attempt that did not happen, recorded as its own state (`<how>Skipped`) and never as false.
function Probe:ChannelAttempt(run, how)
    local Compat = GuildOS.Compat
    pcall(function()
        local id = Compat.ChannelId(run.name)
        if id <= 0 then
            if not run[how] then run[how .. "Skipped"] = "no channel number" end
            return
        end
        run.joined = true
        run[how .. "Skipped"] = nil
        run.sentTry[how] = true
        Compat.SendAddonMessageNow(PREFIX, run.texts[how], "CHANNEL", id, function() run[how] = true end)
    end)
end

function Probe:RunChannel()
    if InCombatLockdown and InCombatLockdown() then
        GuildOS:Print(L["The probe does not run in combat. Try again after the fight."])
        return nil
    end
    local running = self._channel
    if running then
        -- A second press, from a new key press: the click that was skipped for want of a number gets its
        -- attempt now, and this is the one that counts.
        if running.click or not running.clickSkipped then
            GuildOS:Print(L["The channel probe is already running."])
            return nil
        end
        self:ChannelAttempt(running, "click")
        return running
    end

    local Compat = GuildOS.Compat
    local name = "GOSProbe" .. math.random(1000, 9999)
    local run = {
        name = name, heard = { timer = false, click = false }, joined = false, sentTry = {},
        texts = { click = name .. " click", timer = name .. " timer" },
    }
    self._channel, self._channelName = run, name
    -- The verdict first of all: whatever raises below, the channel still ends.
    Compat.After(CHANNEL_WAIT, function() Probe:FinishChannel(run) end)

    pcall(function()
        if not self._noticeFilter then self._noticeFilter = Compat.AddChatFilter("CHAT_MSG_CHANNEL_NOTICE", hideChannelNotice) end
        self._channelFrame = self._channelFrame or CreateFrame("Frame")
        self._channelFrame:SetScript("OnEvent", function(_, _, prefix, text, dist)
            if Compat.IsSecret(prefix, text, dist) then return end
            for how, own in pairs(run.texts) do
                if prefix == PREFIX and text == own and dist == "CHANNEL" then run.heard[how] = true end
            end
        end)
        Compat.RegisterEvent(self._channelFrame, "CHAT_MSG_ADDON")
        pcall(Compat.RegisterAddonPrefix, PREFIX)
        -- The name kept here is all that is left of a run a /reload cut short: it goes before this one replaces it.
        self:LeaveStaleChannel()
        if type(GuildOSDB) == "table" then GuildOSDB.probeChannelOpen = name end
        Compat.JoinChannel(name)
    end)

    GuildOS:Print(L["Channel probe: a temporary channel is joined and one message goes through it from the command and one from a timer. The verdict follows in a few seconds."])
    self:ChannelAttempt(run, "click")
    if run.clickSkipped then
        GuildOS:Print(L["The channel has no number yet: press the command or the button again within a few seconds. The second press is the one that counts."])
    end
    Compat.After(CHANNEL_TIMER_AT, function()
        if Probe._channel == run then self:ChannelAttempt(run, "timer") end   -- never after the verdict
    end)
    return run
end

function Probe:FinishChannel(run)
    if self._channel ~= run then return end
    self._channel = nil
    local Compat = GuildOS.Compat
    pcall(function() self._channelFrame:UnregisterEvent("CHAT_MSG_ADDON") end)
    if Compat.ChannelId(run.name) > 0 then run.joined = true end
    local left = Compat.LeaveChannel(run.name)
    -- This leave comes from a timer too: its name goes only once the channel has, and this is its second try.
    self:LeaveStaleChannel(run.name, 2)
    local clockOk, now = pcall(GetServerTime)
    -- timer and click are true (the game took it), false (it was tried and the game did not) or nil
    -- (never tried: <how>Skipped says why).
    local function outcomeOf(how)
        if run[how] then return true end
        if run.sentTry[how] then return false end
        return nil
    end
    local result = { timer = outcomeOf("timer"), click = outcomeOf("click"),
                     timerSkipped = run.timerSkipped, clickSkipped = run.clickSkipped,
                     heard = run.heard, joined = run.joined, left = left, at = (clockOk and now) or 0 }
    if not GuildOSDB then GuildOSDB = {} end
    GuildOSDB.probeChannel = result

    if not result.joined then
        GuildOS:Print(L["The channel could not be joined."])
    end
    local labels = { click = L["the message sent from the command"], timer = L["the message sent from a timer"] }
    for _, how in ipairs({ "click", "timer" }) do
        local outcome
        if result[how] == nil then
            outcome = L["not tried: the channel had no number yet"]
        else
            outcome = not result[how] and L["not sent"] or result.heard[how] and L["came back"] or L["did not come back"]
        end
        GuildOS:Print(string.format("  %s: %s", labels[how], outcome))
    end
    GuildOS:Print(L["Saved in GuildOSDB.probeChannel. Type /reload to write it to disk."])
end

----------------------------------------------------------------------
-- /gos probe mem (issue #285)
-- Where the memory goes while the addon runs. On 2026-11-08 it held 16 MB after a collection and
-- allocated 77 MB a minute standing still. For MEM_SECONDS every function of every GuildOS module, of
-- GuildOS itself and of the shared ChehulMesh is wrapped to count what it allocates and how long it
-- takes. Every call adds to "incl"; only a call with no wrapped call around it adds to "top", so the top
-- list adds up to what the addon allocated through anything wrapped, nested calls counted once. The
-- collector is asked to stop meanwhile: then the counts are exact; where the client refuses, a
-- collection step inside a call hides part of it, and they are lower bounds.
-- GuildOSDB.probeMem = { at, seconds, gcStopped, version, wrapped, addonKb, luaKb, top, incl, slow }.
----------------------------------------------------------------------
Probe.MEM_SECONDS = 120
local MEM_KEEP = 25    -- rows of each list kept
local MEM_SHOWN = 8    -- rows of the top list printed
-- Data, not code: nothing in them is wrapped, and the probe does not wrap itself.
local MEM_SKIP = { db = true, State = true, L = true, Client = true, Probe = true }
local mem              -- the run in progress

-- What the game counts for this addon, in KB; nil where it will not say.
local function addonKb()
    local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if not (update and get) or not pcall(update) then return nil end
    local ok, kb = pcall(get, "GuildOS")
    return ok and tonumber(kb) or nil
end

-- Every function to watch: GuildOS's own, each plain module table's, and the mesh's. A table with a
-- metatable is data or somebody else's class, and is left alone.
local function memTargets()
    local out, seen = {}, { [Probe] = true }
    local function add(owner, label)
        if seen[owner] then return end
        seen[owner] = true
        for key, fn in pairs(owner) do
            if type(fn) == "function" then out[#out + 1] = { owner = owner, key = key, name = label .. tostring(key), fn = fn } end
        end
    end
    for name, value in pairs(GuildOS) do
        if type(value) == "table" and not MEM_SKIP[name] and getmetatable(value) == nil then add(value, name .. ":") end
    end
    add(GuildOS, "GuildOS:")
    if type(_G.ChehulMesh) == "table" then add(_G.ChehulMesh, "ChehulMesh:") end
    return out
end

-- The wrapper changes nothing it measures: same arguments, all the returns, the same error.
local function memWrap(t, run)
    local stat = { name = t.name, kb = 0, calls = 0, ms = 0, topKb = 0, topCalls = 0, topMs = 0 }
    local fn = t.fn
    local function done(top, m0, t0, ok, ...)
        local kb = collectgarbage("count") - m0
        if kb < 0 then kb = 0 end
        local ms = debugprofilestop() - t0
        stat.kb, stat.calls, stat.ms = stat.kb + kb, stat.calls + 1, stat.ms + ms
        if top then stat.topKb, stat.topCalls, stat.topMs = stat.topKb + kb, stat.topCalls + 1, stat.topMs + ms end
        run.depth = run.depth - 1
        if not ok then error((...), 0) end
        return ...
    end
    t.stat = stat
    t.wrapper = function(...)
        -- A wrapper somebody kept (a timer made during the run) passes straight through afterwards.
        if mem ~= run then return fn(...) end
        local top = run.depth == 0
        run.depth = run.depth + 1
        return done(top, collectgarbage("count"), debugprofilestop(), pcall(fn, ...))
    end
    t.owner[t.key] = t.wrapper
end

function Probe:RunMem()
    if mem then
        GuildOS:Print(L["The memory probe is already running."])
        return nil
    end
    local run = { depth = 0, targets = memTargets(), started = debugprofilestop() }
    run.gcStopped = pcall(collectgarbage, "stop")
    run.lua0, run.addon0 = collectgarbage("count"), addonKb()
    for _, t in ipairs(run.targets) do memWrap(t, run) end
    mem = run
    C_Timer.After(self.MEM_SECONDS, function() Probe:FinishMem() end)
    GuildOS:Print(string.format(L["Measuring memory for %d seconds. Keep playing; the result comes in chat."], self.MEM_SECONDS))
    return run
end

local function memList(run, kb, calls, ms, by)
    local rows = {}
    for _, t in ipairs(run.targets) do
        local s = t.stat
        if s and s[calls] > 0 then
            rows[#rows + 1] = { name = s.name, kb = math.floor(s[kb] * 10 + 0.5) / 10, calls = s[calls],
                                ms = math.floor(s[ms] * 10 + 0.5) / 10 }
        end
    end
    table.sort(rows, function(a, b) return a[by] > b[by] end)
    for i = #rows, MEM_KEEP + 1, -1 do rows[i] = nil end
    return rows
end

function Probe:FinishMem()
    local run = mem
    if not run then return end
    mem = nil
    -- Back as it was first, and the collector running again, before anything here can fail.
    for _, t in ipairs(run.targets) do
        if t.owner[t.key] == t.wrapper then t.owner[t.key] = t.fn end
    end
    local luaKb, addon1 = collectgarbage("count") - run.lua0, addonKb()
    if run.gcStopped then pcall(collectgarbage, "restart") end

    local seconds = (debugprofilestop() - run.started) / 1000
    local result = {
        at = time(), seconds = math.floor(seconds + 0.5), gcStopped = run.gcStopped, version = GuildOS.VERSION,
        wrapped = #run.targets, luaKb = math.floor(luaKb + 0.5),
        addonKb = (addon1 and run.addon0) and math.floor(addon1 - run.addon0 + 0.5) or nil,
        top = memList(run, "topKb", "topCalls", "topMs", "kb"),
        incl = memList(run, "kb", "calls", "ms", "kb"),
        slow = memList(run, "topKb", "topCalls", "topMs", "ms"),
    }
    if not GuildOSDB then GuildOSDB = {} end
    GuildOSDB.probeMem = result

    local total = (result.addonKb or result.luaKb) / 1024
    GuildOS:Print(string.format(L["Memory probe, %d s: the addon allocated %.1f MB (%.1f MB a minute)."],
        result.seconds, total, seconds > 0 and total * 60 / seconds or 0))
    if not run.gcStopped then GuildOS:Print(L["The game kept collecting while it measured: the numbers are lower bounds."]) end
    for i = 1, math.min(MEM_SHOWN, #result.top) do
        local x = result.top[i]
        GuildOS:Print(string.format("  %s: %.1f MB, %d calls, %.0f ms", x.name, x.kb / 1024, x.calls, x.ms))
    end
    GuildOS:Print(L["Saved in GuildOSDB.probeMem. Type /reload to write it to disk."])
end
