----------------------------------------------------------------------
-- Guild OS - Feature entries
-- The list every surface renders from: the window's tabs, the minimap
-- menu, the slash commands and the Settings toggles. Adding a feature
-- means adding one entry here.
--
--   tab = false  -> a background module with a Settings toggle only
----------------------------------------------------------------------
local UI = BRutus.UI
local L  = BRutus.L

-- Tabs, in window order ----------------------------------------------
UI:RegisterFeature({
    id = "home", label = L["Now"], order = 5, core = true,
    build = function(c, win) BRutus:CreateNowPanel(c, win) end,
})

UI:RegisterFeature({
    id = "roster", label = L["Roster"], order = 10, core = true,
    build = function(c, win) BRutus:CreateRosterPanel(c, win) end,
})

UI:RegisterFeature({
    id = "raids", label = L["Raids"], order = 20,
    subs = { "sessions", "raiders", "cores", "audit", "raidtools" },
    build = function(c, win) BRutus:CreateRaidHubPanel(c, win) end,
})

UI:RegisterFeature({
    id = "loot", label = L["Loot"], order = 30, officerOnly = true,
    build = function(c, win) BRutus:CreateLootPanel(c, win) end,
})

UI:RegisterFeature({
    id = "dkp", label = L["DKP"], order = 35,
    condition = function() return BRutus:LootSystemShowsDKP() end,
    build = function(c, win) BRutus:CreateDKPPanel(c, win) end,
})

UI:RegisterFeature({
    id = "wishlist", label = L["Wishlist"], order = 38,
    condition = function() return BRutus:IsOfficer() and BRutus:LootSystemShowsWishlist() end,
    build = function(c, win) BRutus:CreateWishlistGuildPanel(c, win) end,
})

UI:RegisterFeature({
    id = "recipes", label = L["Recipes"], order = 40,
    build = function(c, win) BRutus:CreateRecipesPanel(c, win) end,
})

UI:RegisterFeature({
    id = "guild", label = L["Guild"], order = 50,
    subs = { "calendar", "activity" },
    build = function(c, win) BRutus:CreateGuildHub(c, win) end,
})

UI:RegisterFeature({
    id = "alliance", label = L["Alliance"], order = 60,
    condition = function()
        return (BRutus.Alliance and BRutus.Alliance:Get() ~= nil) or BRutus:IsOfficer()
    end,
    build = function(c, win) BRutus:CreateAlliancePanel(c, win) end,
})

UI:RegisterFeature({
    id = "recruitment", label = L["Recruitment"], order = 70,
    build = function(c, win) BRutus:CreateRecruitmentPanel(c, win) end,
})

UI:RegisterFeature({
    id = "trials", label = L["Trials"], order = 80, officerOnly = true,
    build = function(c, win) BRutus:CreateTrialsPanel(c, win) end,
})

UI:RegisterFeature({
    id = "management", label = L["Leadership"], order = 90, officerOnly = true,
    build = function(c, win) BRutus:CreateManagementPanel(c, win) end,
})

UI:RegisterFeature({
    id = "web", label = L["Web"], order = 95,
    -- Not officerOnly: publishing is each player's own choice, and the
    -- guild's picture on the site gets better the more members opt in. The
    -- raid actions gate themselves on raid leadership instead.
    build = function(c, win) BRutus:CreateWebPanel(c, win) end,
})

UI:RegisterFeature({
    id = "settings", label = L["Settings"], order = 100, core = true,
    build = function(c, win) BRutus:CreateSettingsPanel(c, win) end,
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
