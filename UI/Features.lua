----------------------------------------------------------------------
-- Guild OS - Feature entries
-- The list every surface renders from: the hub rows, the expanded-mode
-- tab bar, the minimap menu, the slash commands and the Settings
-- toggles. Adding a feature means adding one entry here.
--
--   hub = false  -> no floating window and no hub row
--   tab = false  -> no tab in expanded mode
--   both false   -> a background module with a Settings toggle only
----------------------------------------------------------------------
local UI = BRutus.UI
local L  = BRutus.L

local ICON = "Interface\\Icons\\"

-- Windowed features, in hub order -----------------------------------
UI:RegisterFeature({
    id = "home", label = L["Home"], order = 5,
    hub = false, tab = true, core = true,
    build = function(c, win) BRutus:CreateDashboardPanel(c, win) end,
})

UI:RegisterFeature({
    id = "roster", label = L["Roster"], order = 10, core = true,
    icon = ICON .. "INV_Misc_GroupLooking",
    -- minW 520 is the narrowest the table still reads at: the four-column
    -- state (MEMBER, LVL, CLASS, iLVL). See the design doc, section 5.3.
    w = 1000, h = 620, minW = 520, minH = 380,
    build = function(c, win) BRutus:CreateRosterPanel(c, win) end,
})

UI:RegisterFeature({
    id = "raids", label = L["Raids"], order = 20,
    icon = ICON .. "INV_Sword_04",
    w = 780, h = 540, minW = 620, minH = 400,
    subs = { "sessions", "raiders", "cores", "audit", "raidtools" },
    build = function(c, win) BRutus:CreateRaidHubPanel(c, win) end,
})

UI:RegisterFeature({
    id = "loot", label = L["Loot"], order = 30, officerOnly = true,
    icon = ICON .. "INV_Misc_Coin_01",
    w = 680, h = 470,
    build = function(c, win) BRutus:CreateLootPanel(c, win) end,
})

UI:RegisterFeature({
    id = "dkp", label = L["DKP"], order = 35,
    icon = ICON .. "INV_Misc_Coin_02",
    w = 620, h = 440,
    condition = function() return BRutus:LootSystemShowsDKP() end,
    build = function(c, win) BRutus:CreateDKPPanel(c, win) end,
})

UI:RegisterFeature({
    id = "wishlist", label = L["Wishlist"], order = 38,
    icon = ICON .. "INV_Scroll_03",
    w = 680, h = 470,
    condition = function() return BRutus:IsOfficer() and BRutus:LootSystemShowsWishlist() end,
    build = function(c, win) BRutus:CreateWishlistGuildPanel(c, win) end,
})

UI:RegisterFeature({
    id = "recipes", label = L["Recipes"], order = 40,
    icon = ICON .. "INV_Misc_Book_09",
    w = 700, h = 500,
    build = function(c, win) BRutus:CreateRecipesPanel(c, win) end,
})

UI:RegisterFeature({
    id = "guild", label = L["Guild"], order = 50,
    icon = ICON .. "INV_Shirt_GuildTabard_01",
    w = 720, h = 520,
    subs = { "calendar", "activity" },
    build = function(c, win) BRutus:CreateGuildHub(c, win) end,
})

UI:RegisterFeature({
    id = "alliance", label = L["Alliance"], order = 60,
    icon = ICON .. "INV_BannerPVP_02",
    w = 900, h = 600, minW = 700, minH = 460,
    condition = function()
        return (BRutus.Alliance and BRutus.Alliance:Get() ~= nil) or BRutus:IsOfficer()
    end,
    build = function(c, win) BRutus:CreateAlliancePanel(c, win) end,
})

UI:RegisterFeature({
    id = "recruitment", label = L["Recruitment"], order = 70,
    icon = ICON .. "INV_Misc_GroupNeedMore",
    w = 720, h = 500,
    build = function(c, win) BRutus:CreateRecruitmentPanel(c, win) end,
})

UI:RegisterFeature({
    id = "trials", label = L["Trials"], order = 80, officerOnly = true,
    icon = ICON .. "INV_Misc_Note_01",
    w = 620, h = 420,
    build = function(c, win) BRutus:CreateTrialsPanel(c, win) end,
})

UI:RegisterFeature({
    id = "management", label = L["Leadership"], order = 90, officerOnly = true,
    icon = ICON .. "INV_Crown_01",
    w = 760, h = 540, minW = 620, minH = 420,
    build = function(c, win) BRutus:CreateManagementPanel(c, win) end,
})

UI:RegisterFeature({
    id = "settings", label = L["Settings"], order = 100, core = true,
    icon = ICON .. "INV_Misc_Gear_01",
    w = 560, h = 520, resizable = false,
    build = function(c, win) BRutus:CreateSettingsPanel(c, win) end,
})

-- Background modules: a Settings toggle and nothing else ------------
local function background(id, label, desc, officerOnly)
    UI:RegisterFeature({
        id = id, label = label, desc = desc,
        hub = false, tab = false, officerOnly = officerOnly,
        module = id,
    })
end

background("raidTracker",       L["Raid Tracker"],       L["Track raid attendance, penalties, and sessions"], true)
background("lootTracker",       L["Loot Tracker"],       L["Record loot drops from boss kills"])
background("lootMaster",        L["Loot Master"],        L["Master Loot with wishlist auto-council"])
background("consumableChecker", L["Consumable Checker"], L["Scan raid for missing flasks/food/elixirs"])
background("raidHUD",           L["Raid CD Tracker"],    L["Floating tracker for raid cooldowns and consumable check"])
background("trialTracker",      L["Trial Tracker"],      L["Track trial member progress (officer)"], true)
background("officerNotes",      L["Officer Notes"],      L["Private notes on guild members (officer)"], true)
background("commSystem",        L["Comm System"],        L["Sync member data between addon users"])
