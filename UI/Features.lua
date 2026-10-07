----------------------------------------------------------------------
-- Guild OS - Feature entries
-- The list every surface renders from: the window's tabs, the minimap
-- menu, the slash commands and the Settings toggles. Adding a feature
-- means adding one entry here.
--
--   tab = false  -> a background module with a Settings toggle only
----------------------------------------------------------------------
local UI = GuildOS.UI
local L  = GuildOS.L

-- Tabs, in window order ----------------------------------------------
UI:RegisterFeature({
    id = "home", label = L["Now"], order = 5, core = true,
    build = function(c, win) GuildOS:CreateNowPanel(c, win) end,
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

UI:RegisterFeature({
    id = "loot", label = L["Loot"], order = 30, officerOnly = true,
    build = function(c, win) GuildOS:CreateLootPanel(c, win) end,
})

UI:RegisterFeature({
    id = "dkp", label = L["DKP"], order = 35,
    condition = function() return GuildOS:LootSystemShowsDKP() end,
    build = function(c, win) GuildOS:CreateDKPPanel(c, win) end,
})

UI:RegisterFeature({
    id = "wishlist", label = L["Wishlist"], order = 38,
    condition = function() return GuildOS:IsOfficer() and GuildOS:LootSystemShowsWishlist() end,
    build = function(c, win) GuildOS:CreateWishlistGuildPanel(c, win) end,
})

-- On WoW: Forever the Professions panel (issue #33) takes the Recipes tab: the whole catalog,
-- who covers it and who does not. Anniversary keeps the recipe search.
UI:RegisterFeature({
    id = "recipes", label = GuildOS.CreateProfessionsPanel and L["Professions"] or L["Recipes"], order = 40,
    build = function(c, win)
        if GuildOS.CreateProfessionsPanel then return GuildOS:CreateProfessionsPanel(c, win) end
        return GuildOS:CreateRecipesPanel(c, win)
    end,
})

UI:RegisterFeature({
    id = "guild", label = L["Guild"], order = 50,
    subs = { "calendar", "activity", "cta" },
    build = function(c, win) GuildOS:CreateGuildHub(c, win) end,
})

UI:RegisterFeature({
    id = "alliance", label = L["Alliance"], order = 60,
    condition = function()
        return (GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil) or GuildOS:IsOfficer()
    end,
    build = function(c, win) GuildOS:CreateAlliancePanel(c, win) end,
})

UI:RegisterFeature({
    id = "recruitment", label = L["Recruitment"], order = 70,
    build = function(c, win) GuildOS:CreateRecruitmentPanel(c, win) end,
})

UI:RegisterFeature({
    id = "trials", label = L["Trials"], order = 80, officerOnly = true,
    build = function(c, win) GuildOS:CreateTrialsPanel(c, win) end,
})

UI:RegisterFeature({
    id = "management", label = L["Leadership"], order = 90, officerOnly = true,
    build = function(c, win) GuildOS:CreateManagementPanel(c, win) end,
})

UI:RegisterFeature({
    id = "web", label = L["Web"], order = 95,
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
-- `tbc`: TBC content, listed only on TBC Anniversary (ADR-0014).
local function background(id, label, desc, officerOnly, tbc)
    UI:RegisterFeature({
        id = id, label = label, desc = desc,
        tab = false, officerOnly = officerOnly, tbc = tbc,
        module = id,
    })
end

background("raidTracker",       L["Raid Tracker"],       L["Track raid attendance, penalties, and sessions"], true)
background("lootTracker",       L["Loot Tracker"],       L["Record loot drops from boss kills"])
background("lootMaster",        L["Loot Master"],        L["Master Loot with wishlist auto-council"])
background("consumableChecker", L["Consumable Checker"], L["Scan raid for missing flasks/food/elixirs"], nil, true)
background("raidHUD",           L["Raid CD Tracker"],    L["Floating tracker for raid cooldowns and consumable check"], nil, true)
background("trialTracker",      L["Trial Tracker"],      L["Track trial member progress (officer)"], true)
background("officerNotes",      L["Officer Notes"],      L["Private notes on guild members (officer)"], true)
background("commSystem",        L["Comm System"],        L["Sync member data between addon users"])
