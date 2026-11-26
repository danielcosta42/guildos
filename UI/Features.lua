----------------------------------------------------------------------
-- Guild OS - Feature entries
-- The list every surface renders from: the window's tabs, the minimap
-- menu, the slash commands and the Settings toggles. Adding a feature
-- means adding one entry here.
--
--   tab = false  -> a background module with a Settings toggle only
--   tab = false, opens = { tab, sub } -> another tab's sub-tab, with its own Settings toggle
----------------------------------------------------------------------
local UI = GuildOS.UI
local L  = GuildOS.L

-- Tabs, in window order ----------------------------------------------
-- `retail = false`: not on retail (ADR-0026), which has no Master Loot: the loot master (issue #185).
UI:RegisterFeature({
    id = "home", label = L["Now"], order = 5, core = true,
    -- The Salão's Home (specs/salao, #445), in place of the Now column and its cards.
    build = function(c) GuildOS:CreateSalaoPanel(c) end,
})

UI:RegisterFeature({
    id = "roster", label = L["Roster"], order = 10, core = true,
    build = function(c, win) GuildOS:CreateRosterPanel(c, win) end,
})

UI:RegisterFeature({
    id = "raids", label = L["Raids"], order = 20,
    subs = { "sessions", "raiders", "cores", "audit", "raidtools" },
    build = function(c, win) GuildOS:CreateRaidHubPanel(c, win) end,
})

-- One Loot window for every member (issue #346): the rule, the accounts, the lists and the history.
-- On retail too since issue #183: the history and the equity of personal loot, no soft reserves.
UI:RegisterFeature({
    id = "loot", label = L["Loot"], order = 30,
    subs = { "rule", "accounts", "lists", "history" },
    build = function(c, win) GuildOS:CreateLootWindow(c, win) end,
})

-- The DKP and the guild's wishlists are the Loot window's Accounts and Lists (issue #346): their
-- switches stay in Settings, and /gos open dkp or wishlist opens the sub-tab.
UI:RegisterFeature({
    id = "dkp", label = L["DKP"], order = 35, tab = false, opens = { "loot", "accounts" },   -- retail too since #185
    condition = function() return GuildOS:LootSystemShowsDKP() end,
    restart = true,   -- the points module follows this switch, at login (audit B25)
})

UI:RegisterFeature({
    id = "wishlist", label = L["Wishlist"], order = 38, tab = false, opens = { "loot", "lists" },   -- retail too since #185
    condition = function() return GuildOS:IsOfficer() and GuildOS:LootSystemShowsWishlist() end,
})

-- The Crafts tab (issue #389): the guild's professions and its craft orders in one place. The
-- catalog is the Professions panel on WoW: Forever and retail (issue #33: the whole catalog, who
-- covers it and who does not) and the recipe search on Anniversary; the order queue sits beside it.
UI:RegisterFeature({
    id = "recipes", label = L["Crafts"], order = 40,
    -- The switch stops the crafts modules and their sync too (audit B25): they start at login only.
    restart = true,
    build = function(c, win) return GuildOS:CreateCraftsTab(c, win) end,
})

-- Journal and Achievements are its last two sub-tabs on WoW: Forever (issue #367), each where its
-- feature is present and switched on.
UI:RegisterFeature({
    id = "guild", label = L["Guild"], order = 50,
    subs = { "achievements", "calendar", "activity", "bulletin", "cta", "chat", "journal" },
    build = function(c, win) GuildOS:CreateGuildHub(c, win) end,
})

-- The guild bank (issue #380): what it holds, seen from anywhere, each tab, its ledger, what it
-- needs and what members asked for. Only where the client has a guild bank (WoW: Forever's servers may not).
UI:RegisterFeature({
    id = "bank", label = L["Bank"], order = 45,
    subs = { "inventory", "tabs", "ledger", "needs", "requests", "cleanup" },
    condition = function() return GuildOS.GuildBank ~= nil and GuildOS.GuildBank:Available() end,
    build = function(c, win) GuildOS:CreateGuildBankPanel(c, win) end,
})

-- Winter Veil's Secret Santa (issue #437, the site's specs/119): only while the site sends this year's event.
UI:RegisterFeature({
    id = "winterveil", label = L["Winter Veil"], order = 53,
    condition = function() return GuildOS.WinterVeil ~= nil and GuildOS.WinterVeil:Event() ~= nil end,
    build = function(c, win) GuildOS:CreateWinterVeilPanel(c, win) end,
})

-- The guild's own group finder (issue #341): what is being formed, who is looking, and the game's
-- activities as tiles. /gos avail opens it.
UI:RegisterFeature({
    id = "groups", label = L["Groups"], order = 52,
    subs = { "active", "dungeon", "raid", "other" },
    build = function(c, win) GuildOS:CreateGroupsPanel(c, win) end,
})

-- WoW: Forever only (issue #211): the guild's journal, where the module exists. The Guild tab's
-- Journal sub-tab since issue #367: its switch stays in Settings, and /gos open journal opens it.
UI:RegisterFeature({
    id = "journal", label = L["Journal"], order = 55, tab = false, opens = { "guild", "journal" },
    tbc = false, retail = false, restart = true,
})

-- WoW: Forever only (issue #216): what the guild earned, as guildos.me says it. The Guild tab's
-- Achievements sub-tab since issue #367.
UI:RegisterFeature({
    id = "achievements", label = L["Achievements"], order = 56, tab = false, opens = { "guild", "achievements" },
    tbc = false, retail = false,
})

UI:RegisterFeature({
    id = "alliance", label = L["Alliance"], order = 60,
    condition = function()
        return (GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil) or GuildOS:IsOfficer()
    end,
    build = function(c, win) GuildOS:CreateAlliancePanel(c, win) end,
})

-- An officer's view has sub-tabs; Trials only for officers, while its feature is on (issue #367).
UI:RegisterFeature({
    id = "recruitment", label = L["Recruitment"], order = 70,
    subs = { "recruiting", "scanner", "trials" },
    build = function(c, win) GuildOS:CreateRecruitmentPanel(c, win) end,
})

-- The Recruitment tab's Trials sub-tab since issue #367: its switch stays in Settings, and
-- /gos open trials opens it.
UI:RegisterFeature({
    id = "trials", label = L["Trials"], order = 80, tab = false, opens = { "recruitment", "trials" },
    officerOnly = true,
})

UI:RegisterFeature({
    id = "management", label = L["Leadership"], order = 90, officerOnly = true,
    build = function(c, win) GuildOS:CreateManagementPanel(c, win) end,
})

UI:RegisterFeature({
    id = "web", label = L["Web"], order = 95,   -- on retail too since issue #182
    -- Not officerOnly: publishing is each player's own choice, and the
    -- guild's picture on the site gets better the more members opt in. The
    -- raid actions gate themselves on raid leadership instead.
    build = function(c, win) GuildOS:CreateWebPanel(c, win) end,
})

UI:RegisterFeature({
    id = "settings", label = L["Settings"], order = 100, core = true,
    build = function(c, win) GuildOS:CreateSettingsPanel(c, win) end,
})

-- Background modules: a Settings toggle and nothing else ------------
-- `tbc`: TBC content, listed only on TBC Anniversary (ADR-0014). `retail`: false when not on retail.
-- `forever`: false when not on WoW: Forever (issue #187).
local function background(id, label, desc, officerOnly, tbc, retail, forever)
    UI:RegisterFeature({
        id = id, label = label, desc = desc,
        tab = false, officerOnly = officerOnly, tbc = tbc, retail = retail, forever = forever,
        module = id,
    })
end

background("raidTracker",       L["Raid Tracker"],       L["Track raid attendance, penalties, and sessions"], true)
-- Awards are always recorded (audit B17): the switch shows or hides the loot history.
background("lootTracker",       L["Loot Tracker"],       L["Show the loot history (awards are always recorded)"])  -- personal loot on retail (#183)
background("lootMaster",        L["Loot Master"],        L["Master Loot with wishlist auto-council"], nil, nil, false)
-- Anniversary's and retail's (Midnight's flask, food and rune; issue #187); WoW: Forever has none.
background("consumableChecker", L["Consumable Checker"], L["Scan raid for missing flasks/food/elixirs"], nil, nil, nil, false)
background("raidHUD",           L["Raid CD Tracker"],    L["Floating tracker for raid cooldowns and consumable check"], nil, true)
background("trialTracker",      L["Trial Tracker"],      L["Track trial member progress (officer)"], true)
background("officerNotes",      L["Officer Notes"],      L["Private notes on guild members (officer)"], true)
background("commSystem",        L["Comm System"],        L["Sync member data between addon users"])
-- WoW: Forever only: on by default since issue #289 (was off until tested, #232).
background("founding",          L["Founding"],           L["The guild's founding and its founding members"], nil, false, false)
