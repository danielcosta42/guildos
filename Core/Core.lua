----------------------------------------------------------------------
-- Guild OS - Core
-- Global namespace bootstrap, database lifecycle, event handling.
-- Constants are defined in Core/Config.lua (loaded first).
----------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Safety net: Config.lua should have run first, but guard defensively.
_G.GuildOS = _G.GuildOS or {}

-- Attach the file-local namespace table (only accessible from this file)
GuildOS.ns = ns

local L = GuildOS.L

----------------------------------------------------------------------
-- Session state (runtime-only, never persisted)
----------------------------------------------------------------------
GuildOS.State = {
    comm        = { lastBroadcast = 0, pendingMessages = {} },
    lootMaster  = {},
    recruitment = {},
    raid        = {},
    consumables = {},
    raidCD      = { state = {}, members = {} },
    errors      = {},  -- session error ring (see GuildOS:RecordError / /guildos errors)
    -- What failed to start (GuildOS:RunStartup) and what this client lacks
    -- (GuildOS:RecordMissing). Feeds /guildos errors and the login line.
    startup     = { failed = {}, failedFeatures = {}, stacks = {} },
    missing     = {},
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
        hijackGuildButton = true,  -- guild micro button / "J" opens Guild OS (opt-out in General)
        itemTooltip = "always",    -- guild lines on item tooltips: "always", "shift" or "off"
        officerMaxRank = 1,  -- rank indexes 0..officerMaxRank are officers (GM + rank 1 by default)
        -- Web companion. Off until someone turns it on: the export carries the
        -- whole guild's gear, attunements and attendance, and a guild that does
        -- not use the site should not have that one mistyped command away.
        companion = false,
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
    cores = {},       -- [coreName] = { lootMaster, attendance, points, members }
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
            GuildOS:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        GuildOS:OnLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        GuildOS:OnEnterWorld(isInitialLogin, isReloadingUi)
    elseif event == "GUILD_ROSTER_UPDATE" then
        GuildOS:OnGuildRosterUpdate()
    elseif event == "PLAYER_GUILD_UPDATE" then
        GuildOS:OnGuildRosterUpdate()
    end
end)

----------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------
function GuildOS:Initialize()
    -- WoW leaves a SavedVariable nil until it is first written.
    if not GuildOSDB then GuildOSDB = {} end

    self.Compat.RegisterAddonPrefix(self.PREFIX)

    self:Print("v" .. self.VERSION .. " |cffFFD700by Chehul|r" .. L[" loaded. Type |cffFFD700/guildos|r to open."])
end

----------------------------------------------------------------------
-- Per-guild DB resolution
----------------------------------------------------------------------
function GuildOS:ResolveGuildDB()
    local realmName = GetRealmName() or "Unknown"
    local dbKey, guilded
    if IsInGuild() then
        local guildName = GetGuildInfo("player")
        if not guildName then return false end  -- in a guild but name not ready; caller retries
        dbKey = guildName .. "-" .. realmName
        guilded = true
    else
        -- Guildless: boot against a per-realm fallback DB so the mesh, recruitment
        -- finder, minimap and commands still work. Guild-scoped data just stays
        -- empty, and the player switches to the real guild DB once they join one.
        dbKey = "_noguild-" .. realmName
        guilded = false
    end

    -- Already resolved to this key
    if self.guildKey == dbKey and self.db then
        self.isGuilded = guilded
        return true
    end

    -- Migration from the pre-guild-keyed flat structure. Only meaningful when
    -- guilded, so legacy data lands under the real guild key (never _noguild);
    -- a guildless boot leaves _dbVersion untouched so a later guilded boot migrates.
    if guilded and not GuildOSDB._dbVersion then
        if GuildOSDB.version or GuildOSDB.members or GuildOSDB.settings then
            local oldData = {}
            for k, v in pairs(GuildOSDB) do
                oldData[k] = v
            end
            wipe(GuildOSDB)
            GuildOSDB[dbKey] = oldData
        end
        GuildOSDB._dbVersion = 2
    end

    if not GuildOSDB[dbKey] then
        GuildOSDB[dbKey] = {}
    end

    -- Apply defaults
    local guildDB = GuildOSDB[dbKey]
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
    self.guildKey = dbKey
    self.isGuilded = guilded
    return true
end

function GuildOS:OnLogin()
    -- Boots whether or not we're in a guild: ResolveGuildDB falls back to a
    -- guildless DB so the mesh + recruitment finder + minimap still work.
    -- A false return only means "in a guild but the name isn't ready yet".
    if not self:ResolveGuildDB() then
        local attempts = 0
        local function tryResolve()
            attempts = attempts + 1
            if GuildOS:ResolveGuildDB() then
                GuildOS:InitModules()
                return
            end
            if attempts < 5 then
                C_Timer.After(2, tryResolve)
            else
                GuildOS:Print(L["|cffFF4444Could not load guild info. Try /reload.|r"])
            end
        end
        C_Timer.After(2, tryResolve)
        return
    end

    self:InitModules()
end

----------------------------------------------------------------------
-- Module start-up list. Order matters (DataCollector before the sync that
-- reads it), so this is a list, not a set. Per entry:
--   [1]      module name under GuildOS
--   feature  Settings toggle that can switch the module off
--   ui       window the module backs: if the module fails to start, the
--            window refuses to open instead of erroring while it builds
--   method   start function, when it is not Initialize
--   after    second function, run only when the first one succeeded
----------------------------------------------------------------------
local MODULE_START = {
    { "DataCollector" },
    { "AttunementTracker" },
    { "SyncService" },
    { "Alliance", ui = "alliance" },
    { "AllianceSync" },
    { "AllianceChat" },
    { "RosterLog" },
    { "BanList" },
    { "CommSystem", feature = "commSystem" },
    { "Wishlist", ui = "wishlist" },
    { "SoftRes" },
    { "CoreManager" },
    { "RaidTracker", feature = "raidTracker", ui = "raids" },
    { "LootTracker", feature = "lootTracker" },
    { "LootMaster", feature = "lootMaster", ui = "loot" },
    { "Points", feature = "points", ui = "dkp" },
    { "Digest" },
    { "Bulletin" },
    { "CallToArms" },
    { "Polls" },
    { "Calendar" },
    { "Milestones" },
    { "ConsumableChecker", feature = "consumableChecker" },
    { "SpecChecker" },
    { "GuildAnalytics" },
    { "Mentions" },
    { "NoteCommand" },
    { "LevelQuery" },
    { "LFGBoard" },
    { "GuildMap" },
    { "PugInspector" },
    { "RecipeTracker", ui = "recipes" },
    { "CraftNet" },
    -- WoW: Forever only (issue #31); on Anniversary the module does not exist and is skipped.
    { "Professions" },
    { "ProfSync" },
    -- WoW: Forever only (issue #37): the look, read in the barber's chair.
    { "Look" },
    { "RecruitBeacon" },
    { "RecruitScanner" },
    -- Recruitment participation runs for EVERY player (the officer-only
    -- Initialize in OFFICER_START handles just the auto-post/welcome flow).
    { "Recruitment", feature = "recruitment", method = "InitParticipation" },
    -- Recruitment engagement stats: every client tracks its own activity and
    -- self-reports; officers aggregate for the Leadership dashboard.
    { "RecruitEngagement" },
    -- Raider roster (officer-curated, everyone stores/views it).
    { "RaiderRoster" },
    { "AltRoster" },
    { "AltAutoDetect" },
    { "ChatTweaks" },
    { "GuildManager", feature = "guildManager", ui = "management" },
    { "ModPresets" },
}

-- Officer-only modules, started once guild info is available.
local OFFICER_START = {
    { "Recruitment", feature = "recruitment" },
    { "OfficerNotes", feature = "officerNotes" },
    { "TrialTracker", feature = "trialTracker", ui = "trials", after = "CheckExpired" },
}

local OFFICER_START_DELAY = 5  -- seconds; the guild rank is not known at PLAYER_LOGIN
local OFFICER_START_TRIES = 12 -- asks, OFFICER_START_DELAY apart, before giving up on the rank

-- The rank IsOfficer reads, or no guild at all: either way there is an answer to act on.
local function rankKnown()
    if not IsInGuild() then return true end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil
end

-- Asked once at five seconds, a rank the client had not loaded yet read as "not an officer",
-- and the officer's welcome, notes and trials stayed off all session, silently (issue #79).
-- It asks again until the rank is known; the start-up report waits for the answer.
local function startOfficerModules(try)
    if not rankKnown() and try < OFFICER_START_TRIES then
        GuildOS.Compat.After(OFFICER_START_DELAY, function() startOfficerModules(try + 1) end)
        return
    end
    if not rankKnown() then
        GuildOS.State.startup.failed.OfficerModules = "not started, the guild rank was still unknown after "
            .. (OFFICER_START_DELAY * OFFICER_START_TRIES) .. "s"
    elseif GuildOS:IsOfficer() then
        for _, entry in ipairs(OFFICER_START) do
            GuildOS:StartModule(entry)
        end
    end
    GuildOS:ReportStartup()
end

function GuildOS:InitModules()
    -- Core helper tests (Utils loads before SelfTest, so it cannot self-register).
    self:RunStartup("UtilTests", nil, self.RegisterUtilTests, self)

    for _, entry in ipairs(MODULE_START) do
        self:StartModule(entry)
    end
    if GuildOS.CreateMinimapButton then
        self:RunStartup("MinimapButton", nil, self.CreateMinimapButton, self)
    end
    -- First-run welcome (once); delayed so guild info + frames are ready.
    if GuildOS.MaybeShowOnboarding then
        GuildOS.Compat.After(6, function() GuildOS:MaybeShowOnboarding() end)
    end
    -- Login digest: shown a bit later so guild/roster data is ready and it
    -- doesn't collide with the first-run onboarding wizard.
    if GuildOS.Digest then
        GuildOS.Compat.After(9, function() GuildOS.Digest:ShowOnLogin() end)
    end

    -- Officer-only modules: defer init until guild info is available. The
    -- start-up report waits for them, so it counts every problem exactly once.
    GuildOS.Compat.After(OFFICER_START_DELAY, function() startOfficerModules(1) end)

    -- Hook chat player links for guild invite
    self:RunStartup("ChatInviteHook", nil, self.HookChatInvite, self)

    -- Request guild roster
    if IsInGuild() then
        GuildOS.Compat.GuildRoster()
    end

    -- Hook into default guild frame so Guild OS opens instead
    self:RunStartup("GuildFrameHook", nil, self.HookGuildFrame, self)
end

----------------------------------------------------------------------
-- Start-up isolation. One API missing on a new client (WoW: Forever) is
-- enough to make a module raise while it starts, and every module after
-- it in the list used to stay unstarted: the addon was dead.
----------------------------------------------------------------------

-- xpcall handler: keeps the stack a bare pcall would throw away, so a real
-- bug in a module's start-up is still traceable.
local function withStack(err)
    return { msg = tostring(err), stack = debugstack and debugstack(2) or nil }
end

-- Run one start-up step. A failure is recorded against `name`, and against
-- the features `entry` names (their windows then refuse to open); the
-- caller carries on with the next step. Returns true when the step ran.
function GuildOS:RunStartup(name, entry, fn, ...)
    local ok, res
    if type(fn) == "function" then
        local args, n = { ... }, select("#", ...)
        ok, res = xpcall(function() return fn(unpack(args, 1, n)) end, withStack)
        -- When the handler itself fails (out of memory, an error object whose
        -- __tostring raises), xpcall returns a plain value, not our table.
        if not ok and type(res) ~= "table" then
            local printable, text = pcall(tostring, res)
            res = { msg = printable and text or "start-up error" }
        end
    else
        ok, res = false, { msg = "no start-up function" }
    end
    if not ok then
        local startup = self.State.startup
        startup.failed[name] = res.msg
        startup.stacks[name] = res.stack
        if entry and entry.feature then startup.failedFeatures[entry.feature] = name end
        if entry and entry.ui then startup.failedFeatures[entry.ui] = name end
        self:RecordError(name .. ": " .. res.msg)
        -- Debug mode hands the whole error to the client's handler (BugSack,
        -- scriptErrors), the way an unguarded start-up always did.
        if self.Logger.debug and geterrorhandler then
            geterrorhandler()(name .. ": " .. res.msg .. (res.stack and ("\n" .. res.stack) or ""))
        end
    end
    return ok
end

-- Start one module from a start-list entry. A module that is not loaded or
-- is switched off in Settings is skipped, which is not a failure.
function GuildOS:StartModule(entry)
    local name = entry[1]
    local mod = self[name]
    if not mod then return false end
    if entry.feature and not self:IsFeatureEnabled(entry.feature) then return false end
    local method = entry.method or "Initialize"
    -- "Module:Method" for anything but Initialize, so two stages of one
    -- module (Recruitment, TrialTracker) never overwrite each other's record.
    local label = method == "Initialize" and name or (name .. ":" .. method)
    local ok = self:RunStartup(label, entry, mod[method], mod)
    if ok and entry.after then
        ok = self:RunStartup(name .. ":" .. entry.after, entry, mod[entry.after], mod)
    end
    return ok
end

-- Name of the module whose failed start-up took feature `id` down, or nil.
function GuildOS:FeatureStartFailed(id)
    return self.State.startup.failedFeatures[id]
end

-- Record something this client does not have (an event, a tooltip script),
-- once per session, so /guildos errors lists it without repeating it.
--
-- `expected` marks one only some clients ever had — the old craft window's
-- event on a client that never had a craft window. It is still remembered, so
-- the second caller is not recorded either, and left out of the start-up list:
-- a client being itself is not a problem with the addon. What exists on this
-- client is the probe's inventory to answer (Core/Probe.lua), not this one's.
function GuildOS:RecordMissing(what, expected)
    local seen = self.State.missing[what]
    if seen == true or (seen and expected) then return end  -- a real miss still wins over an expected one
    self.State.missing[what] = expected and "expected" or true
    if expected then return end
    self:RecordError(what .. " is not available on this client")
end

-- Every start-up failure and every missing capability, one line each,
-- sorted. /guildos errors prints these before the error ring, which is
-- capped and shared with runtime errors and can already have lost them.
function GuildOS:ListStartupProblems()
    local lines = {}
    for name, err in pairs(self.State.startup.failed) do
        lines[#lines + 1] = name .. ": " .. err
    end
    for what, how in pairs(self.State.missing) do
        if how == true then lines[#lines + 1] = what .. " is not available on this client" end
    end
    table.sort(lines)
    return lines
end

-- One chat line when start-up hit problems; silent when everything started.
function GuildOS:ReportStartup()
    local n = #self:ListStartupProblems()
    if n > 0 then
        self:Print(string.format(L["%d start-up problem(s) on this client. Type /guildos errors for details."], n))
    end
end

function GuildOS:OnEnterWorld(isInitialLogin, isReloadingUi)
    if not self.db or not self.guildKey then return end

    -- Only run the full startup sequence on the initial login or UI reload.
    -- PLAYER_ENTERING_WORLD also fires on every zone/instance transition —
    -- we don't want to re-collect, re-broadcast, or re-check professions then.
    if not isInitialLogin and not isReloadingUi then return end

    -- Collect own data after a short delay. This feeds the profession-freshness
    -- check and the officer wishlist broadcast. The member-data NETWORK broadcast
    -- is owned by CommSystem:Initialize (which runs after the guild DB resolves,
    -- so it fires reliably even on a cold login) — do NOT broadcast here too, or
    -- a /reload would double-send.
    C_Timer.After(3, function()
        if GuildOS.DataCollector then
            GuildOS.DataCollector:CollectMyData()
        end
        -- Broadcast our wishlist so guildies can see our priorities (officer-only while in testing)
        if GuildOS:IsOfficer() then
            C_Timer.After(5, function()
                if GuildOS.Wishlist then
                    GuildOS.Wishlist:BroadcastMyWishlist()
                end
            end)
        end
        -- Check profession freshness after data is collected
        C_Timer.After(4, function()
            GuildOS:CheckProfessionFreshness()
        end)
    end)
end

function GuildOS:OnGuildRosterUpdate()
    if GuildOS.RecordFirstSeen then GuildOS:RecordFirstSeen() end
    GuildOS:RefreshRosterUI()
end

----------------------------------------------------------------------
-- Hook into the default Blizzard guild frame
----------------------------------------------------------------------
function GuildOS:HookGuildFrame()
    -- CRITICAL: never overwrite ToggleGuildFrame / ToggleFriendsFrame with our own
    -- closures. Replacing those Blizzard globals TAINTS the shared social-frame
    -- code, and the Raid window is a FriendsFrame tab, so a raid leader could not
    -- open the raid frame or move a unit between subgroups DURING COMBAT (the
    -- protected action fails with "Interface action failed because of an addon").
    -- The taint is installed at load, which is why toggling the guild-button
    -- option off never cleared it. hooksecurefunc keeps Blizzard's functions
    -- secure; we only react AFTER they run, mirroring the native guild frame's
    -- open/close onto Guild OS. We deliberately do NOT touch ToggleFriendsFrame at
    -- all, so the Raid tab (and every other tab) stays completely untainted.
    if ToggleGuildFrame and not self._guildHookInstalled then
        self._guildHookInstalled = true
        hooksecurefunc("ToggleGuildFrame", function()
            if self._suppressGuildHijack then return end
            if not (IsInGuild() and self:IsGuildButtonHijacked()) then return end
            local blizShown = (GuildFrame and GuildFrame:IsShown())
                or (CommunitiesFrame and CommunitiesFrame:IsShown())
            if blizShown then
                -- Swap to Guild OS. The hide runs in the same frame as the native
                -- Show (hooksecurefunc is synchronous), so nothing actually renders.
                --
                -- CRITICAL: use HideUIPanel, never frame:Hide(). Both of these are
                -- UIPanels (registered in UIPanelWindows), and a bare :Hide() skips
                -- the panel manager, so the slot they occupy is never released. The
                -- panel stays "open" as far as GetUIPanel is concerned while being
                -- invisible, and HideUIPanel later early-returns on a frame that is
                -- already hidden, so the slot leaks for the rest of the session.
                -- CloseAllWindows() then reports "I closed something" on every call,
                -- and ToggleGameMenu never reaches ShowUIPanel(GameMenuFrame): ESC
                -- still closes windows but stops opening the game menu, with no Lua
                -- error, until /reload.
                if GuildFrame then HideUIPanel(GuildFrame) end
                if CommunitiesFrame then HideUIPanel(CommunitiesFrame) end
                -- With Guild OS already up this press is a close: we hid Blizzard's frame on
                -- the press that opened us, so its toggle shows it again instead of hiding
                -- it, and the key never closed anything (issue #66).
                if self:IsFrontDoorShown() then
                    self:HideFrontDoor()
                else
                    self:ToggleRoster()
                end
            elseif self:IsFrontDoorShown() then
                -- The toggle just closed the native frame: close ours to match.
                self:HideFrontDoor()
            end
        end)
    end

    -- Add a "Guild OS" button to Blizzard's own guild frames so you can jump from
    -- the native UI to Guild OS (and back via the "Blizzard" button in our header),
    -- rather than the addon fully replacing the guild pane.
    GuildOS:SetupNativeGuildButtons()
end

----------------------------------------------------------------------
-- Guild-button takeover (opt-out) + native <-> Guild OS toggle buttons
----------------------------------------------------------------------

-- Does the guild micro button / "J" open Guild OS? Default yes; opt-out in Settings
-- (General) or via /guildos guildbutton, so players can keep the modern Blizzard
-- guild UI (chat history, news) as the guild button's target and use both.
function GuildOS:IsGuildButtonHijacked()
    return self:GetSetting("hijackGuildButton") ~= false
end

-- Open Blizzard's own guild UI (classic GuildFrame or the modern Communities frame,
-- whichever the client is set to) — the "Blizzard" button in our header calls this so
-- a Guild OS user can still reach guild chat history / the news feed.
function GuildOS:OpenBlizzardGuildUI()
    -- Open the native guild UI without our hijack redirect swapping it back to
    -- Guild OS. We call the real (unreplaced) ToggleGuildFrame with a guard flag
    -- our hooksecurefunc handler checks.
    if not ToggleGuildFrame then return end
    self._suppressGuildHijack = true
    ToggleGuildFrame()
    self._suppressGuildHijack = false
end

-- Attach a "Guild OS" button to a Blizzard guild frame ONCE (guarded — a shape change
-- in a future client never errors us). Attached state is tracked in a local table, NOT
-- as a field on the Blizzard global frame (which would trip luacheck's undefined-field).
local nativeGuildOSButtons = {}
local function AttachGuildOSButton(parent, point, xOff, yOff)
    if not parent or nativeGuildOSButtons[parent] then
        return
    end
    nativeGuildOSButtons[parent] = true
    local ok, btn = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not ok or not btn then
        return
    end
    btn:SetSize(84, 22)
    btn:SetText("Guild OS")
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    -- Anchor is per-frame: the classic GuildFrame and the modern CommunitiesFrame have
    -- different top-bar layouts (the classic "Show Offline Members" checkbox and the
    -- Communities online counter each sit where a shared corner offset would overlap),
    -- so each caller picks its own corner + offset.
    point = point or "TOPRIGHT"
    btn:SetPoint(point, parent, point, xOff or -56, yOff or -32)
    btn:SetScript("OnClick", function() GuildOS:ToggleRoster() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cffFFD700Guild|r |cffD4AC0DOS|r")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Put the "Guild OS" button on BOTH the classic GuildFrame and the modern
-- CommunitiesFrame. Both are load-on-demand, so attach now if already present and again
-- when their addon loads. Runs once.
function GuildOS:SetupNativeGuildButtons()
    if self._nativeButtonsSetup then
        return
    end
    self._nativeButtonsSetup = true
    local function tryAttach()
        -- Classic GuildFrame: top-LEFT — the top-right there holds the "Show Offline
        -- Members" checkbox, so we sit on the empty left side under the title.
        if GuildFrame then AttachGuildOSButton(GuildFrame, "TOPLEFT", 16, -28) end
        -- Modern CommunitiesFrame: top-right, pushed in so it clears the "x/y Online"
        -- member counter in the top bar.
        if CommunitiesFrame then AttachGuildOSButton(CommunitiesFrame, "TOPRIGHT", -12, -32) end
    end
    tryAttach()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_GuildUI" or name == "Blizzard_Communities" then
            tryAttach()
        end
    end)
end

----------------------------------------------------------------------
-- Toggle the Guild OS window
----------------------------------------------------------------------
function GuildOS:ToggleRoster()
    if not self.db then
        self:Print(L["|cff888888Not in a guild \226\128\148 addon inactive.|r"])
        return
    end
    if not IsInGuild() then
        -- Guildless: the roster is guild data — open the recruitment finder,
        -- which is exactly what a guildless player is here for.
        if self.ShowRecruitInbox then self:ShowRecruitInbox() end
        return
    end
    self.Compat.GuildRoster()
    if GuildOS.UI and GuildOS.UI.ToggleMain then
        GuildOS.UI:ToggleMain()
    end
end

----------------------------------------------------------------------
-- Is the Guild OS window on screen? The guild-frame hook mirrors
-- Blizzard's open and close onto it.
----------------------------------------------------------------------
function GuildOS:IsFrontDoorShown()
    return (self.RosterFrame and self.RosterFrame:IsShown()) and true or false
end

function GuildOS:HideFrontDoor()
    if self.RosterFrame then self.RosterFrame:Hide() end
end

-- Refresh the roster when the window is up and the roster tab has been built.
function GuildOS:RefreshRosterUI()
    local f = self.RosterFrame
    if f and f:IsShown() and f.RefreshRoster then f:RefreshRoster() end
end

----------------------------------------------------------------------
-- Utility — print
----------------------------------------------------------------------
function GuildOS:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffFFD700[Guild OS]|r " .. tostring(msg))
end

----------------------------------------------------------------------
-- Structured logger + error resilience
-- Logger.debug gates verbose output (toggle via /guildos debug).
-- SafeCall pcall-wraps risky callbacks so a single failure never breaks
-- the rest of the UI or spams the default error frame; failures land in a
-- session ring buffer viewable via /guildos errors.
----------------------------------------------------------------------
GuildOS.Logger = { debug = false }

function GuildOS.Logger.Debug(msg)
    if GuildOS.Logger.debug then
        GuildOS:Print("|cff888888[debug]|r " .. tostring(msg))
    end
end

function GuildOS.Logger.Info(msg)
    GuildOS:Print(tostring(msg))
end

function GuildOS.Logger.Warn(msg)
    GuildOS:Print("|cffFF8800[warn]|r " .. tostring(msg))
end

local ERROR_RING_MAX = 50

-- Push one message into the session error ring shown by /guildos errors.
function GuildOS:RecordError(msg)
    local ring = GuildOS.State.errors
    ring[#ring + 1] = { msg = tostring(msg), when = (GetServerTime and GetServerTime()) or 0 }
    while #ring > ERROR_RING_MAX do table.remove(ring, 1) end
    if GuildOS.Logger.debug then
        GuildOS:Print("|cffFF4444[error]|r " .. tostring(msg))
    end
end

-- pcall a function, capturing any error into GuildOS.State.errors.
-- Returns (ok, errOrResult). Use for event handlers and panel refreshes.
function GuildOS:SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then GuildOS:RecordError(err) end
    return ok, err
end

----------------------------------------------------------------------
-- Permission checks
----------------------------------------------------------------------
function GuildOS:IsOfficer()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    if not rankIndex then return false end
    local maxRank = (self.db and self.db.settings and self.db.settings.officerMaxRank) or 1
    return rankIndex <= maxRank
end

-- The officer threshold is the guild's, not each account's (issue #81). Stored per account, it
-- let an officer tick an "Officer Alt" rank that no other client knew of, and since #78 every
-- officer message from that alt was dropped everywhere else. An officer's change is stamped and
-- published; every client keeps the newest stamp an officer sent over GUILD (SyncService's
-- officer-domain check). Until somebody changes it, each client keeps the value it had.
local RANK_FUTURE_SLACK = 300   -- seconds a stamp may run ahead of this client's clock, as RI's
local MAX_RANK_INDEX = 9        -- guild ranks are 0..9

-- The stamp only moves forward, past the one this client holds: a clock a second behind, or
-- two clicks in one second, would otherwise stamp a change the rest of the guild rejects as
-- old, and the guild would stay split. Only an officer changes it, and the change goes out
-- even when it demotes that officer: the receivers judge the sender by their own threshold,
-- which still counts them.
function GuildOS:SetOfficerMaxRank(maxRank)
    if not self:IsOfficer() then return false end
    local s = self.db.settings
    s.officerMaxRank = maxRank
    s.officerMaxRankAt = math.max(GetServerTime(), (s.officerMaxRankAt or 0) + 1)
    self:PublishOfficerMaxRank(true)
    return true
end

-- Officers re-send it on the 5-minute sync and when asked, so a client that missed the change
-- still gets it. `justChanged` skips the officer check for the change SetOfficerMaxRank has
-- just made, which may have demoted the sender.
function GuildOS:PublishOfficerMaxRank(justChanged)
    local s = self.db and self.db.settings
    if not (s and s.officerMaxRankAt and self.SyncService and (justChanged or self:IsOfficer())) then return end
    self.SyncService:Publish("guildcfg", "officers", { max = s.officerMaxRank }, { rev = s.officerMaxRankAt })
end

function GuildOS:OnOfficerMaxRankSync(env)
    local data = env and env.data
    local at = env and tonumber(env.rev)
    local max = type(data) == "table" and type(data.max) == "number" and data.max
    -- `at > 0` also turns away NaN, which compares false to everything and would switch
    -- newest-wins off for good on the client that stored it.
    if not (at and at > 0 and at < math.huge and max) then return end
    if max < 0 or max > MAX_RANK_INDEX or max ~= math.floor(max) then return end
    at = math.min(at, GetServerTime() + RANK_FUTURE_SLACK)
    local s = self.db.settings
    -- Newest wins; two changes stamped in the same second settle on the lower threshold, the
    -- same answer on every client whatever order they arrive in.
    local held = s.officerMaxRankAt
    if held and (at < held or (at == held and max >= (s.officerMaxRank or 1))) then return end
    s.officerMaxRank, s.officerMaxRankAt = max, at
end

-- Check whether a named player (may include realm, e.g. "Name-Realm") is an officer
-- by scanning the guild roster. Used to validate incoming officer-only messages.
function GuildOS:IsOfficerByName(fullName)
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
function GuildOS:GetSetting(key)
    return self.db and self.db.settings and self.db.settings[key]
end

function GuildOS:SetSetting(key, value)
    if self.db and self.db.settings then
        self.db.settings[key] = value
    end
end

-- Do the guild's lines (crafters, wishlist, soft reserves) go on this item tooltip?
-- "always", "shift" or "off" (issue #39). A link clicked in chat counts as asked for:
-- shift-clicking it pastes it into the chat box instead.
-- ponytail: pressing Shift mid-hover only shows up where the owner refreshes its
-- tooltip (bags, character, action bars, every 0.2s); elsewhere hover again.
function GuildOS:ShowsItemTooltipInfo(tooltip)
    local mode = self:GetSetting("itemTooltip")
    if mode == "off" then return false end
    return mode ~= "shift" or tooltip == ItemRefTooltip or IsShiftKeyDown()
end

----------------------------------------------------------------------
-- Feature toggles (Rule 8 — never read db.settings.modules directly).
-- Keys are the feature ids from UI/FeatureRegistry.lua. Default is ON:
-- an absent key means "never touched", not "off". `core` features can
-- never be turned off — that is how a user would lock themselves out of
-- the Settings window that would turn them back on.
----------------------------------------------------------------------
function GuildOS:IsFeatureEnabled(id)
    if type(id) ~= "string" then return false end
    -- UI loads after Core, so the registry is resolved per call, not per load.
    local def = self.UI and self.UI.GetFeature and self.UI:GetFeature(id)
    if def and def.core then return true end
    local mods = self.db and self.db.settings and self.db.settings.modules
    if not mods then return true end
    return mods[id] ~= false
end

function GuildOS:SetFeatureEnabled(id, enabled)
    if type(id) ~= "string" then return end
    local def = self.UI and self.UI.GetFeature and self.UI:GetFeature(id)
    if def and def.core then return end
    if not (self.db and self.db.settings) then return end
    self.db.settings.modules = self.db.settings.modules or {}
    -- GetChecked() returns true or nil (never false) in TBC, so store an
    -- explicit boolean — IsFeatureEnabled compares against false.
    enabled = enabled and true or false
    self.db.settings.modules[id] = enabled
    if self.UI and self.UI.OnFeatureToggled then self.UI:OnFeatureToggled(id, enabled) end
end

----------------------------------------------------------------------
-- Loot distribution system chosen by the guild (Settings, officer).
-- Drives the default Loot Master flow; read by features that present
-- loot UI. "rolls" = /roll MS/OS (default), "tmb"/"wishlist" = interest
-- lists, "dkp" = the Points economy.
----------------------------------------------------------------------
GuildOS.LOOT_SYSTEMS = {
    { key = "rolls",    label = "/roll (MS/OS)" },
    { key = "tmb",      label = "TMB" },
    { key = "wishlist", label = "Wishlist" },
    { key = "dkp",      label = "DKP / Points" },
    { key = "external", label = "External / Off" },
}

function GuildOS:GetLootSystem()
    return self:GetSetting("lootSystem") or "rolls"
end

-- True unless the guild has opted out of GuildOS loot handling entirely
-- ("external": loot is run by Gargul/RCLootCouncil/etc.).
function GuildOS:LootSystemActive()
    return self:GetLootSystem() ~= "external"
end

function GuildOS:SetLootSystem(sys)
    self:SetSetting("lootSystem", sys)
    -- Loot Master follows the system: "external" silences it entirely (no
    -- roll popups, ML window, council, or /roll capture — and with no awards
    -- the loot history stops growing too). SetEnabled hides any open frames
    -- immediately; the runtime gate keeps new ones from opening.
    if self.LootMaster and self.LootMaster.SetEnabled then
        self.LootMaster:SetEnabled(self.LootMaster:IsModuleEnabled())
    end
    -- Re-surface only the access points the new system needs (no reload).
    if self.UpdateLootSystemUI then self:UpdateLootSystemUI() end
end

-- Each loot system exposes only its own UI so players never see screens
-- that don't apply: wishlist/TMB -> wishlist access; DKP -> DKP access;
-- plain /roll -> neither.
function GuildOS:LootSystemShowsWishlist()
    local s = self:GetLootSystem()
    return s == "wishlist" or s == "tmb"
end

function GuildOS:LootSystemShowsDKP()
    return self:GetLootSystem() == "dkp"
end

----------------------------------------------------------------------
-- Player self-service profile: the roles this character is willing to
-- play. Stored locally, mirrored into our own member row, and broadcast
-- so the Raider Roster + guildmates pick it up with no officer input.
----------------------------------------------------------------------
function GuildOS:GetMyRoles()
    return (self.db and self.db.profile and self.db.profile.prefRoles) or {}
end

function GuildOS:SetMyRoles(roles)
    self.db.profile = self.db.profile or {}
    self.db.profile.prefRoles = roles or {}
    local key = self:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
    self.db.members = self.db.members or {}
    self.db.members[key] = self.db.members[key] or {}
    self.db.members[key].prefRoles = self.db.profile.prefRoles
    if self.CommSystem and self.CommSystem.BroadcastMyData then
        self.CommSystem:BroadcastMyData(true)
    end
    if self.RaiderRoster then self.RaiderRoster:Refresh() end
end

