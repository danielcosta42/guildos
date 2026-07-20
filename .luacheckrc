-- Luacheck configuration for Guild OS WoW Addon

std = "lua51"
max_line_length = false

-- Globals that the addon WRITES to
globals = {
    -- Addon tables (GuildOS is the primary namespace; BRutus is a legacy alias)
    "GuildOS",
    "BRutus",
    "GuildOSDB",
    "BRutusDB",

    -- Slash commands
    "SlashCmdList",
    "SLASH_GUILDOS1",
    "SLASH_GUILDOS2",
    "SLASH_BRUTUS1",
    "SLASH_BRUTUS2",

    -- Hooked/overwritten globals
    "ToggleGuildFrame",
    "ToggleFriendsFrame",

    -- Implicit globals defined across files (functions shared between modules)
    "CreateRosterRow",
    "UpdateRosterRow",
    "ShowRowTooltip",
    "CreateDetailFrame",
    "PopulateDetail",
    "CreateSectionHeader",
    "CreateGearRow",
    "CreateProfessionRow",
    "CreateAttunementRow",

    -- Tables written to
    "UISpecialFrames",
    "StaticPopupDialogs",  -- GuildManager registers confirmation dialogs
}

-- Globals that the addon READS (WoW environment)
read_globals = {
    -- WoW API: Frames & UI
    "CreateFrame",
    "CreateColor",
    "UIParent",
    "GameTooltip",
    "GameFontNormal",
    "GameFontNormalSmall",
    "GameFontHighlight",
    "GameFontHighlightSmall",
    "GameFontNormalLarge",
    "ChatFontNormal",
    "BackdropTemplateMixin",
    "STANDARD_TEXT_FONT",
    "DEFAULT_CHAT_FRAME",
    "UIFrameFadeIn",
    "UIFrameFadeOut",

    -- WoW API: C_ namespaces
    "C_Timer",
    "C_ChatInfo",
    "C_GuildInfo",
    "C_Map",
    "C_QuestLog",

    -- WoW API: Unit functions
    "UnitName",
    "UnitClass",
    "UnitLevel",
    "UnitRace",
    "UnitFactionGroup",
    "UnitGUID",
    "UnitHealthMax",
    "UnitPowerMax",
    "UnitStat",
    "UnitExists",
    "UnitIsPlayer",
    "UnitPlayerControlled",
    "UnitIsConnected",
    "UnitBuff",

    -- WoW API: Guild functions
    "IsInGuild",
    "CanGuildInvite",
    "GuildInvite",
    "GetGuildInfo",
    "GetGuildRosterInfo",
    "GetNumGuildMembers",
    "GetGuildRosterMOTD",
    "GuildRoster",         -- nil in TBC Classic; guarded in Compat.lua
    "SetGuildTabardTextures",

    -- WoW API: Inventory & Items
    "GetInventoryItemLink",
    "GetInventoryItemTexture",
    "GetInventoryItemQuality",
    "GetItemInfo",
    "GetItemCount",
    "GetSpellInfo",
    "GetSpellTexture",
    "GetItemQualityColor",
    "GetAverageItemLevel",

    -- WoW API: Skills & Professions
    "GetNumSkillLines",
    "GetSkillLineInfo",

    -- WoW API: Quest & Reputation
    "GetQuestLogTitle",
    "GetNumQuestLogEntries",
    "GetQuestLogIndexByID",
    "IsQuestFlaggedCompleted",
    "GetFactionInfoByID",

    -- WoW API: Chat & Communication
    "SendChatMessage",
    "SendAddonMessage",
    "RegisterAddonMessagePrefix",
    "GetChannelName",
    "JoinChannelByName",
    "EnumerateServerChannels",
    "ChatFrame_AddMessageEventFilter",
    "ChatFrame_SendTell",

    -- WoW API: Social & Group
    "InviteUnit",
    "InviteByName",
    "TargetUnit",
    "InspectUnit",
    "NotifyInspect",
    "CanInspect",
    "GetNumTalentTabs",
    "GetTalentTabInfo",
    "GetNumTalents",
    "GetTalentInfo",
    "SendWho",

    -- /who lookups
    "SetWhoToUI",
    "C_FriendList",

    -- WoW API: Guild management
    "IsGuildLeader",
    "CanGuildRemove",
    "CanGuildPromote",
    "CanGuildDemote",
    "CanEditMOTD",
    "CanEditGuildInfo",
    "GuildPromote",
    "GuildDemote",
    "GuildUninvite",
    "GuildSetMOTD",
    "SetGuildInfoText",
    "GetGuildInfoText",
    "GetGuildRosterLastOnline",
    "GuildControlGetNumRanks",
    "GuildControlGetRankName",

    -- WoW API: Dropdown menus
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_Initialize",
    "ToggleDropDownMenu",
    "CloseDropDownMenus",

    -- WoW Global strings
    "WHISPER_MESSAGE",
    "PARTY_INVITE",
    "INSPECT",
    "GUILD_PROMOTE",
    "GUILD_DEMOTE",
    "GUILD_UNINVITE",
    "WHO",
    "CANCEL",
    "YES",
    "NO",

    -- WoW API: Miscellaneous
    "GetLocale",
    "GetRealmName",
    "Minimap",
    "GetCursorPosition",
    "GetTime",
    "GetServerTime",
    "ReloadUI",
    "InCombatLockdown",
    "PlaySound",
    "hooksecurefunc",
    "securecallfunction",
    "StaticPopup_Show",

    -- WoW API: Instance & Raid
    "GetInstanceInfo",
    "GetNumGroupMembers",
    "IsInGroup",
    "IsInRaid",
    "UnitIsGroupLeader",
    "GetRaidRosterInfo",
    "CombatLogGetCurrentEventInfo",

    -- WoW API: Loot
    "IsMasterLooter",
    "GetLootMethod",
    "GetNumLootItems",
    "GetLootSlotInfo",
    "GetLootSlotLink",
    "GiveMasterLoot",
    "GetMasterLootCandidate",
    "GetLootRollItemLink",  -- native group loot roll API
    "RandomRoll",           -- /roll command API
    "RANDOM_ROLL_RESULT",   -- localized roll result string (for pattern building)

    -- WoW API: Containers & Trade
    "C_Container",
    "GetContainerNumSlots",
    "GetContainerItemInfo",
    "GetContainerItemLink",                        -- legacy bag item link API
    "UseContainerItem",
    "ContainerFrameItemButton_OnModifiedClick",    -- bag button modifier-click handler
    "GetUnitName",
    "TradeFrameRecipientNameText",

    -- WoW API: Party
    "C_PartyInfo",

    -- WoW API: Tradeskills & Crafting
    "GetTradeSkillLine",
    "GetNumTradeSkills",
    "GetTradeSkillInfo",
    "GetTradeSkillItemLink",
    "GetTradeSkillRecipeLink",
    "GetCraftDisplaySkillLine",
    "GetNumCrafts",
    "GetCraftInfo",
    "GetCraftItemLink",
    "GetCraftSpellLink",

    -- WoW API: Scroll frames
    "FauxScrollFrame_Update",
    "FauxScrollFrame_GetOffset",
    "FauxScrollFrame_OnVerticalScroll",

    -- WoW API: Frame management
    "GuildFrame",
    "CommunitiesFrame",   -- modern (LoD) guild/communities UI; we attach a "Guild OS" button
    "FriendsFrame",
    "ShowUIPanel",
    "HideUIPanel",
    "InterfaceOptionsFrame_OpenToCategory",
    "ChatFrame_OpenChat",

    -- WoW Global constants & tables
    "SOUNDKIT",
    "CLASS_ICON_TCOORDS",
    "LOCALIZED_CLASS_NAMES_MALE",
    "FACTION_BAR_COLORS",
    "RAID_CLASS_COLORS",
    "ERR_GUILD_JOIN_S",
    "ERR_GUILD_INVITE_S",

    -- WoW Lua aliases (not in std lua51)
    "Ambiguate",
    "strsplit",
    "strtrim",
    "strlower",
    "strjoin",
    "tinsert",
    "tremove",
    "wipe",
    "date",
    "time",
    "format",
    "floor",
    "ceil",
    "min",
    "max",
    "abs",
    "random",
    "tContains",
    "CopyTable",

    -- WoW API: Key modifiers
    "IsAltKeyDown",
    "IsShiftKeyDown",
    "HandleModifiedItemClick",
    "SetItemRef",

    -- Tooltip frames
    "GameTooltipTemplate",
    "ItemRefTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",

    -- Libraries
    "LibStub",
    "ChatThrottleLib",

    -- UI / alerts
    "RaidNotice_AddMessage",
    "RaidWarningFrame",
    "ChatTypeInfo",
}

-- Third-party libraries — skip
exclude_files = {
    "Libs/**",
}

-- Ignore unused self and shadowing of self (common in WoW callbacks/event handlers)
ignore = {
    "212/self",  -- unused argument self
    "431/self",  -- shadowing upvalue self
    "432/self",  -- shadowing upvalue argument self
}
