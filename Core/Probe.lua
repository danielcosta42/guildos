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
    "C_GuildInfo.GuildRoster", "C_GuildInfo.SetNote", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo",
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
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "ADDON_LOADED", "CHANNEL_UI_UPDATE", "CHARACTER_POINTS_CHANGED", "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_SKILL", "CHAT_MSG_SYSTEM", "CHAT_MSG_WHISPER", "CLUB_MESSAGE_ADDED",
    "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_STREAM_ADDED", "CLUB_STREAM_REMOVED", "CLUB_STREAMS_LOADED",
    "COMBAT_LOG_EVENT_UNFILTERED", "CRAFT_SHOW", "ENCOUNTER_END", "ENCOUNTER_START", "GET_ITEM_INFO_RECEIVED",
    "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "INSPECT_READY", "LOOT_CLOSED", "LOOT_OPENED",
    "MACRO_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN", "PARTY_LOOT_METHOD_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_GUILD_UPDATE",
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

function Probe:PrintSummary(r)
    local b = r.build
    GuildOS:Print(string.format(L["Probe: build %s (%s), interface %s, project %s."],
        tostring(first(b)), tostring(b[2]), tostring(b[4]), tostring(r.projectId)))
    GuildOS:Print(string.format(L["TBC Anniversary: %s. Secret Values restricted: %s. Chat lockdown here: %s (%s)."],
        answer(r.client and r.client.isAnniversary or false), answer(r.secrets.restricted),
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
