----------------------------------------------------------------------
-- Guild OS - Core
-- Global namespace bootstrap, database lifecycle, event handling.
-- Constants are defined in Core/Config.lua (loaded first).
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Safety net: Config.lua should have run first, but guard defensively.
_G.GuildOS = _G.GuildOS or {}
_G.BRutus  = _G.GuildOS  -- legacy alias; see Config.lua

-- Attach the file-local namespace table (only accessible from this file)
GuildOS.ns = ns

local L = BRutus.L

----------------------------------------------------------------------
-- Session state (runtime-only, never persisted)
----------------------------------------------------------------------
BRutus.State = {
    comm        = { lastBroadcast = 0, pendingMessages = {} },
    lootMaster  = {},
    recruitment = {},
    raid        = {},
    consumables = {},
    raidCD      = { state = {}, members = {} },
    errors      = {},  -- session error ring (see BRutus:SafeCall / /guildos errors)
}

----------------------------------------------------------------------
-- Database defaults
----------------------------------------------------------------------
local DB_DEFAULTS = {
    version = 1,
    members = {},    -- [name-realm] = { gear, professions, attunements, ... }
    settings = {
        sortBy = "level",
        sortAsc = false,
        showOffline = true,
        minimap = { hide = false },
        officerMaxRank = 1,  -- rank indexes 0..officerMaxRank are officers (GM + rank 1 by default)
        modules = {
            raidTracker = true,
            lootTracker = true,
            lootMaster = true,
            consumableChecker = true,
            recruitment = true,
            trialTracker = true,
            officerNotes = true,
            commSystem = true,
            guildManager = true,
        },
    },
    myData = {},
    lastSync = 0,
    guildWishlists = {},  -- [lowerName] = { name, class, wishlist = {} }
    lootPrios = {},       -- [itemId(num)] = { {name, class, order}, ... } officer-set priorities
    raidTracker = {
        sessions = {},
        attendance = {},
        currentGroupTag = "",
        deletedSessions = {},  -- [sessionID] = true; permanent tombstone set
    },
    lootHistory = {},
    lootMaster = {
        rollDuration = 30,
        autoAnnounce = true,
        wishlistOnlyMode = false,
        awardHistory = {},
        disenchanter = "",
    },
    officerNotes = {},
    managementLog = {},  -- leadership action log (ring buffer; capped in GuildManager)
    firstSeen = {},      -- [playerKey] = timestamp first observed by GuildOS
    trials = {},
    altLinks = {},  -- [altKey] = mainKey  (officer-maintained, for account-wide attunement propagation)
    consumableChecks = { lastResults = {} },
    wishlists = {},   -- [charKey] = [{ itemId, itemLink, order, isOffspec }] — per-character wishlists
}

----------------------------------------------------------------------
-- Event frame
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == ADDON_NAME then
            BRutus:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        BRutus:OnLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        BRutus:OnEnterWorld(isInitialLogin, isReloadingUi)
    elseif event == "GUILD_ROSTER_UPDATE" then
        BRutus:OnGuildRosterUpdate()
    elseif event == "PLAYER_GUILD_UPDATE" then
        BRutus:OnGuildRosterUpdate()
    end
end)

----------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------
function BRutus:Initialize()
    -- Ensure both DB globals exist (WoW sets SavedVariables to nil if never written)
    if not GuildOSDB then GuildOSDB = {} end
    if not BRutusDB  then BRutusDB  = {} end

    -- One-time migration: copy legacy BRutusDB data into GuildOSDB when upgrading
    if not GuildOSDB._migrated then
        if next(BRutusDB) ~= nil then
            -- Shallow-copy every top-level key that GuildOSDB does not already own
            for k, v in pairs(BRutusDB) do
                if GuildOSDB[k] == nil then
                    GuildOSDB[k] = v
                end
            end
            GuildOSDB._migratedFrom      = "BRutus"
            GuildOSDB._legacyDbPreserved = true
            -- BRutusDB is intentionally preserved; never wiped automatically
        end
        GuildOSDB._migrated = true
    end

    -- Register both prefixes so we can receive messages from older BRutus clients
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
        C_ChatInfo.RegisterAddonMessagePrefix(self.LEGACY_PREFIX)
    end

    self:Print("v" .. self.VERSION .. " |cffFFD700by Chehul|r" .. L[" loaded. Type |cffFFD700/guildos|r to open."])
end

----------------------------------------------------------------------
-- Per-guild DB resolution
----------------------------------------------------------------------
function BRutus:ResolveGuildDB()
    if not IsInGuild() then
        self.db = nil
        self.guildKey = nil
        return false
    end

    local guildName = GetGuildInfo("player")
    if not guildName then return false end

    local realmName = GetRealmName() or "Unknown"
    local guildKey = guildName .. "-" .. realmName

    -- Already resolved to this guild
    if self.guildKey == guildKey and self.db then return true end

    -- Migration from flat structure (pre-guild-keyed DB)
    if not GuildOSDB._dbVersion then
        if GuildOSDB.version or GuildOSDB.members or GuildOSDB.settings then
            local oldData = {}
            for k, v in pairs(GuildOSDB) do
                oldData[k] = v
            end
            wipe(GuildOSDB)
            GuildOSDB[guildKey] = oldData
        end
        GuildOSDB._dbVersion = 2
    end

    if not GuildOSDB[guildKey] then
        GuildOSDB[guildKey] = {}
    end

    -- Apply defaults
    local guildDB = GuildOSDB[guildKey]
    for k, v in pairs(DB_DEFAULTS) do
        if guildDB[k] == nil then
            if type(v) == "table" then
                guildDB[k] = self:DeepCopy(v)
            else
                guildDB[k] = v
            end
        end
    end

    self.db = guildDB
    self.guildKey = guildKey
    return true
end

function BRutus:OnLogin()
    if not IsInGuild() then
        self:Print(L["|cff888888Not in a guild - addon inactive.|r"])
        return
    end

    -- Guild info may not be available immediately; retry a few times
    if not self:ResolveGuildDB() then
        local attempts = 0
        local function tryResolve()
            attempts = attempts + 1
            if BRutus:ResolveGuildDB() then
                BRutus:InitModules()
                return
            end
            if attempts < 5 then
                C_Timer.After(2, tryResolve)
            else
                BRutus:Print(L["|cffFF4444Could not load guild info. Try /reload.|r"])
            end
        end
        C_Timer.After(2, tryResolve)
        return
    end

    self:InitModules()
end

function BRutus:InitModules()
    -- Module enabled helper
    local function modEnabled(key)
        if not self.db or not self.db.settings or not self.db.settings.modules then return true end
        return self.db.settings.modules[key] ~= false
    end

    -- Initialize subsystems (always-on)
    if BRutus.DataCollector then
        BRutus.DataCollector:Initialize()
    end
    if BRutus.AttunementTracker then
        BRutus.AttunementTracker:Initialize()
    end
    if BRutus.SyncService then
        BRutus.SyncService:Initialize()
    end
    if BRutus.CommSystem and modEnabled("commSystem") then
        BRutus.CommSystem:Initialize()
    end
    if BRutus.Wishlist then
        BRutus.Wishlist:Initialize()
    end
    if BRutus.RaidTracker and modEnabled("raidTracker") then
        BRutus.RaidTracker:Initialize()
    end
    if BRutus.LootTracker and modEnabled("lootTracker") then
        BRutus.LootTracker:Initialize()
    end
    if BRutus.LootMaster and modEnabled("lootMaster") then
        BRutus.LootMaster:Initialize()
    end
    if BRutus.Points and modEnabled("points") then
        BRutus.Points:Initialize()
    end
    if BRutus.Digest then
        BRutus.Digest:Initialize()
    end
    if BRutus.Bulletin then
        BRutus.Bulletin:Initialize()
    end
    if BRutus.ConsumableChecker and modEnabled("consumableChecker") then
        BRutus.ConsumableChecker:Initialize()
    end
    if BRutus.SpecChecker then
        BRutus.SpecChecker:Initialize()
    end
    if BRutus.RecipeTracker then
        BRutus.RecipeTracker:Initialize()
    end
    if BRutus.GuildManager and modEnabled("guildManager") then
        BRutus.GuildManager:Initialize()
    end
    if BRutus.CreateMinimapButton then
        BRutus:CreateMinimapButton()
    end
    -- First-run welcome (once); delayed so guild info + frames are ready.
    if BRutus.MaybeShowOnboarding then
        BRutus.Compat.After(6, function() BRutus:MaybeShowOnboarding() end)
    end
    -- Login digest: shown a bit later so guild/roster data is ready and it
    -- doesn't collide with the first-run onboarding wizard.
    if BRutus.Digest then
        BRutus.Compat.After(9, function() BRutus.Digest:ShowOnLogin() end)
    end

    -- Officer-only modules: defer init until guild info is available
    C_Timer.After(5, function()
        if not BRutus:IsOfficer() then return end

        if BRutus.Recruitment and modEnabled("recruitment") then
            BRutus.Recruitment:Initialize()
        end
        if BRutus.OfficerNotes and modEnabled("officerNotes") then
            BRutus.OfficerNotes:Initialize()
        end
        if BRutus.TrialTracker and modEnabled("trialTracker") then
            BRutus.TrialTracker:Initialize()
            BRutus.TrialTracker:CheckExpired()
        end
    end)

    -- Hook chat player links for guild invite
    BRutus:HookChatInvite()

    -- Request guild roster
    if IsInGuild() then
        C_GuildInfo.GuildRoster()
    end

    -- Hook into default guild frame so Guild OS opens instead
    BRutus:HookGuildFrame()
end

function BRutus:OnEnterWorld(isInitialLogin, isReloadingUi)
    if not self.db or not self.guildKey then return end

    -- Only run the full startup sequence on the initial login or UI reload.
    -- PLAYER_ENTERING_WORLD also fires on every zone/instance transition —
    -- we don't want to re-collect, re-broadcast, or re-check professions then.
    if not isInitialLogin and not isReloadingUi then return end

    -- Collect own data after a short delay
    C_Timer.After(3, function()
        if BRutus.DataCollector then
            BRutus.DataCollector:CollectMyData()
        end
        if BRutus.AttunementTracker then
            BRutus.AttunementTracker:ScanAttunements()
        end
        -- Broadcast our data to guildies
        C_Timer.After(2, function()
            if BRutus.CommSystem then
                BRutus.CommSystem:BroadcastMyData()
            end
        end)
        -- Broadcast our wishlist so guildies can see our priorities (officer-only while in testing)
        if BRutus:IsOfficer() then
            C_Timer.After(5, function()
                if BRutus.Wishlist then
                    BRutus.Wishlist:BroadcastMyWishlist()
                end
            end)
        end
        -- Check profession freshness after data is collected
        C_Timer.After(4, function()
            BRutus:CheckProfessionFreshness()
        end)
    end)
end

function BRutus:OnGuildRosterUpdate()
    if BRutus.RecordFirstSeen then BRutus:RecordFirstSeen() end
    if BRutus.RosterFrame and BRutus.RosterFrame:IsShown() then
        BRutus.RosterFrame:RefreshRoster()
    end
end

----------------------------------------------------------------------
-- Hook into the default Blizzard guild frame
----------------------------------------------------------------------
function BRutus:HookGuildFrame()
    -- Replace ToggleGuildFrame (called by J keybind and guild micro button)
    if ToggleGuildFrame then
        local originalToggleGuildFrame = ToggleGuildFrame
        -- Keep a handle to the native toggle so GuildManager can hand the
        -- leader off to Blizzard's secure guild panel for protected actions
        -- (promote/demote/kick can only be performed there).
        BRutus._origToggleGuildFrame = originalToggleGuildFrame
        ToggleGuildFrame = function()
            if IsInGuild() then
                BRutus:ToggleRoster()
            else
                originalToggleGuildFrame()
            end
        end
    end

    -- Also hook ToggleFriendsFrame for guild tab (tab 3)
    if ToggleFriendsFrame then
        local originalToggleFriendsFrame = ToggleFriendsFrame
        ToggleFriendsFrame = function(tabNumber, ...)
            if tabNumber == 3 and IsInGuild() then
                BRutus:ToggleRoster()
                return
            end
            return originalToggleFriendsFrame(tabNumber, ...)
        end
    end
end

----------------------------------------------------------------------
-- Toggle main roster window
----------------------------------------------------------------------
function BRutus:ToggleRoster()
    if not IsInGuild() or not self.db then
        self:Print(L["|cff888888Not in a guild \226\128\148 addon inactive.|r"])
        return
    end
    if not self.RosterFrame then
        self.RosterFrame = BRutus.CreateRosterFrame()
    end
    if self.RosterFrame:IsShown() then
        self.RosterFrame:Hide()
    else
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
        end
        self.RosterFrame:UpdateTabVisibility()
        -- Reset to roster if current tab is officer-only and player isn't officer
        local currentTab = self.RosterFrame.activeTab or "roster"
        for _, tab in ipairs(self.RosterFrame.tabs) do
            if tab.key == currentTab and tab.officerOnly and not self:IsOfficer() then
                currentTab = "roster"
                break
            end
        end
        self.RosterFrame:SetActiveTab(currentTab)
        self.RosterFrame:Show()
        self.RosterFrame:RefreshRoster()
    end
end

----------------------------------------------------------------------
-- Utility — print
----------------------------------------------------------------------
function BRutus:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffFFD700[Guild OS]|r " .. tostring(msg))
end

----------------------------------------------------------------------
-- Structured logger + error resilience
-- Logger.debug gates verbose output (toggle via /guildos debug).
-- SafeCall pcall-wraps risky callbacks so a single failure never breaks
-- the rest of the UI or spams the default error frame; failures land in a
-- session ring buffer viewable via /guildos errors.
----------------------------------------------------------------------
BRutus.Logger = { debug = false }

function BRutus.Logger.Debug(msg)
    if BRutus.Logger.debug then
        BRutus:Print("|cff888888[debug]|r " .. tostring(msg))
    end
end

function BRutus.Logger.Info(msg)
    BRutus:Print(tostring(msg))
end

function BRutus.Logger.Warn(msg)
    BRutus:Print("|cffFF8800[warn]|r " .. tostring(msg))
end

local ERROR_RING_MAX = 50

-- pcall a function, capturing any error into BRutus.State.errors.
-- Returns (ok, errOrResult). Use for event handlers and panel refreshes.
function BRutus:SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then
        local ring = BRutus.State.errors
        ring[#ring + 1] = { msg = tostring(err), when = (GetServerTime and GetServerTime()) or 0 }
        while #ring > ERROR_RING_MAX do table.remove(ring, 1) end
        if BRutus.Logger.debug then
            BRutus:Print("|cffFF4444[error]|r " .. tostring(err))
        end
    end
    return ok, err
end

----------------------------------------------------------------------
-- Permission checks
----------------------------------------------------------------------
function BRutus:IsOfficer()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if not rankIndex then return false end
    local maxRank = (self.db and self.db.settings and self.db.settings.officerMaxRank) or 1
    return rankIndex <= maxRank
end

-- Check whether a named player (may include realm, e.g. "Name-Realm") is an officer
-- by scanning the guild roster. Used to validate incoming officer-only messages.
function BRutus:IsOfficerByName(fullName)
    if not IsInGuild() or not fullName then return false end
    local maxRank = (self.db and self.db.settings and self.db.settings.officerMaxRank) or 1
    -- Normalise: strip realm if present
    local shortName = fullName:match("^([^-]+)") or fullName
    local numMembers = GetNumGuildMembers() or 0
    for i = 1, numMembers do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name then
            local memberShort = name:match("^([^-]+)") or name
            if memberShort == shortName and rankIndex and rankIndex <= maxRank then
                return true
            end
        end
    end
    return false
end

----------------------------------------------------------------------
-- Config accessors (Rule 8 — never read db.settings.* directly from UI)
----------------------------------------------------------------------
function BRutus:GetSetting(key)
    return self.db and self.db.settings and self.db.settings[key]
end

function BRutus:SetSetting(key, value)
    if self.db and self.db.settings then
        self.db.settings[key] = value
    end
end

----------------------------------------------------------------------
-- Loot distribution system chosen by the guild (Settings, officer).
-- Drives the default Loot Master flow; read by features that present
-- loot UI. "rolls" = /roll MS/OS (default), "tmb"/"wishlist" = interest
-- lists, "dkp" = the Points economy.
----------------------------------------------------------------------
BRutus.LOOT_SYSTEMS = {
    { key = "rolls",    label = "/roll (MS/OS)" },
    { key = "tmb",      label = "TMB" },
    { key = "wishlist", label = "Wishlist" },
    { key = "dkp",      label = "DKP / Points" },
}

function BRutus:GetLootSystem()
    return self:GetSetting("lootSystem") or "rolls"
end

function BRutus:SetLootSystem(sys)
    self:SetSetting("lootSystem", sys)
    -- Re-surface only the access points the new system needs (no reload).
    if self.UpdateLootSystemUI then self:UpdateLootSystemUI() end
end

-- Each loot system exposes only its own UI so players never see screens
-- that don't apply: wishlist/TMB -> wishlist access; DKP -> DKP access;
-- plain /roll -> neither.
function BRutus:LootSystemShowsWishlist()
    local s = self:GetLootSystem()
    return s == "wishlist" or s == "tmb"
end

function BRutus:LootSystemShowsDKP()
    return self:GetLootSystem() == "dkp"
end
