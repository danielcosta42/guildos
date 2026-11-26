----------------------------------------------------------------------
-- Guild OS - The rooms (the Salão, specs/salao, #445)
-- The window's top bar holds a few rooms named from the game instead of one tab per feature: the
-- Salão, Raids, Members, Loot, Workshop, Chronicle and, for officers, the Officers' Room. Settings
-- and Web are reached from the title bar's gear. A room is only a list of entries; an entry opens a
-- feature's panel as today, on one of its sub-tabs when it names one. The feature registry
-- (UI/Features.lua) is untouched: /gos open, the minimap menu and Settings keep reading it.
--
-- Frame-free, so tools/rooms.lua tests every lookup.
----------------------------------------------------------------------
local UI = GuildOS.UI
local L  = GuildOS.L

-- `officer`: an officers' entry in a room everybody has (Raids' Cores). `cond`: a test of its own (a sub-tab
-- whose module is absent). `run`: an action instead of a screen (Core Sign-up). `group`: its heading in a
-- side bar (`side` rooms).
-- `feature`: the feature whose panel the entry opens. `sub`: the panel's sub-tab, opened with its own
-- sub-tab bar hidden where the panel allows it (a hub split over rooms). `needs`: another feature the
-- entry also needs (the Guild hub's Achievements and Journal are WoW: Forever's). `members`: shown only
-- to non-officers (the read-only recruitment view, which helps spread the ad).
UI.ROOMS = {
    { id = "salao", label = L["Salão"], entries = {
        { id = "home",     label = L["Home"],         feature = "home" },
        { id = "bulletin", label = L["Notices"],      feature = "guild", sub = "bulletin" },
        { id = "rules",    label = L["Rules"],        feature = "guild", sub = "rules" },
        { id = "cta",      label = L["Call to Arms"], feature = "guild", sub = "cta" },
        { id = "chat",     label = L["Chat"],         feature = "guild", sub = "chat" },
        { id = "alliance", label = L["Alliance"],     feature = "alliance", sub = "hall" },
        { id = "veil",     label = L["Secret Santa"], feature = "winterveil" },
        { id = "recruit",  label = L["Recruitment"],  feature = "recruitment", members = true },
    } },
    { id = "raids", label = L["Raids"], entries = {
        { id = "calendar",  label = L["Calendar"],    feature = "guild", sub = "calendar" },
        { id = "sessions",  label = L["Sessions"],    feature = "raids", sub = "sessions" },
        { id = "raiders",   label = L["Raiders"],     feature = "raids", sub = "raiders" },
        { id = "cores",     label = L["Cores"],       feature = "raids", sub = "cores", officer = true },
        { id = "audit",     label = L["Audit"],       feature = "raids", sub = "audit" },
        { id = "raidtools", label = L["Raid Tools"],  feature = "raids", sub = "raidtools" },
        { id = "groups",    label = L["Groups"],      feature = "groups" },
        -- Not a screen: the sign-up window, which the Raids bar's button opened before the rooms.
        { id = "signup",    label = L["Core Sign-up"], feature = "raids",
          run = function() if GuildOS.ShowCoreSignupFrame then GuildOS:ShowCoreSignupFrame() end end },
    } },
    { id = "members", label = L["Members"], entries = {
        { id = "roster", label = L["Members"], feature = "roster" },
    } },
    { id = "loot", label = L["Loot"], entries = {
        { id = "rule",     label = L["Rule"],     feature = "loot", sub = "rule" },
        { id = "accounts", label = L["Accounts"], feature = "loot", sub = "accounts",
          cond = function() return GuildOS.Points ~= nil end },
        { id = "lists",    label = L["Lists"],    feature = "loot", sub = "lists",
          cond = function() return GuildOS.Wishlist ~= nil or GuildOS.SoftRes ~= nil end },
        { id = "history",  label = L["History"],  feature = "loot", sub = "history" },
    } },
    { id = "workshop", label = L["Workshop"], entries = {
        { id = "crafts",   label = L["Crafts"],   feature = "recipes" },
        -- Who crafts an item on the whole realm, the guild's crafters first (audit B27): a screen of the Crafts tab
        -- (#449), GuildOS:ShowCraftFinder's and /gos craft's.
        { id = "realm",    label = L["Search the realm"], feature = "recipes", sub = "realm" },
        { id = "bank",     label = L["Bank"],     feature = "bank", sub = "inventory" },
        { id = "tabs",     label = L["Tabs"],     feature = "bank", sub = "tabs" },
        { id = "ledger",   label = L["Ledger"],   feature = "bank", sub = "ledger" },
        { id = "needs",    label = L["Needs"],    feature = "bank", sub = "needs" },
        { id = "requests", label = L["Requests"], feature = "bank", sub = "requests" },
        { id = "cleanup",  label = L["Cleanup"],  feature = "bank", sub = "cleanup",
          cond = function() return GuildOS.GuildBankCleanup ~= nil end },
    } },
    { id = "chronicle", label = L["Chronicle"], entries = {
        { id = "achievements", label = L["Achievements"], feature = "guild", sub = "achievements", needs = "achievements" },
        { id = "journal",      label = L["Journal"],      feature = "guild", sub = "journal", needs = "journal" },
        { id = "activity",     label = L["Activity"],     feature = "guild", sub = "activity" },
    } },
    -- Seventeen entries: a side bar in groups instead of the row (`side`, UI/Window.lua).
    { id = "officers", label = L["Officers' Room"], officer = true, side = true, entries = {
        { id = "recruiting", label = L["Recruiting"],       feature = "recruitment", sub = "recruiting", group = L["Recruitment"] },
        { id = "scanner",    label = L["Scanner"],          feature = "recruitment", sub = "scanner",    group = L["Recruitment"] },
        { id = "trials",     label = L["Trials"],           feature = "recruitment", sub = "trials",     group = L["Recruitment"],
          needs = "trials" },
        { id = "engage",     label = L["Engagement"],       feature = "management",  sub = "engage",     group = L["Recruitment"] },
        { id = "suggest",    label = L["Suggestions"],      feature = "management",  sub = "suggest",    group = L["Members"] },
        { id = "ranks",      label = L["Ranks"],            feature = "management",  sub = "ranks",      group = L["Members"] },
        { id = "inactive",   label = L["Inactivity"],       feature = "management",  sub = "inactive",   group = L["Members"] },
        { id = "bulk",       label = L["Bulk actions"],     feature = "management",  sub = "bulk",       group = L["Members"] },
        { id = "presets",    label = L["Presets"],          feature = "management",  sub = "presets",    group = L["Members"] },
        { id = "remind",     label = L["Without GuildOS"],  feature = "management",  sub = "remind",     group = L["Members"] },
        { id = "marks",      label = L["Notes and marks"],  feature = "management",  sub = "marks",      group = L["Members"] },
        { id = "alerts",     label = L["Chat alerts"],      feature = "management",  sub = "alerts",     group = L["Moderation"] },
        { id = "alertrules", label = L["Alert rules"],      feature = "management",  sub = "alertrules", group = L["Moderation"] },
        { id = "ban",        label = L["Ban List"],         feature = "management",  sub = "ban",        group = L["Moderation"] },
        { id = "log",        label = L["Audit Log"],        feature = "management",  sub = "log",        group = L["Moderation"] },
        { id = "motd",       label = L["MOTD / Info"],      feature = "management",  sub = "motd",       group = L["Guild"] },
        -- The alliance code pasted by hand (chat only) and the alliance's bans (specs/salao/alianca.md §3.3, §3.5).
        { id = "alliance",   label = L["Alliance"],         feature = "alliance",    sub = "setup",      group = L["Guild"] },
    } },
    -- The Settings button in the title bar: never drawn among the rooms.
    { id = "settings", label = L["Settings"], gear = true, entries = {
        { id = "profile",   label = L["Profile"],          feature = "settings", sub = "profile" },
        { id = "interface", label = L["Interface"],        feature = "settings", sub = "interface" },
        { id = "chat",      label = L["Chat and alerts"],  feature = "settings", sub = "chat" },
        { id = "modules",   label = L["Modules"],          feature = "settings", sub = "modules" },
        { id = "rules",     label = L["Guild rules"],      feature = "settings", sub = "rules" },
        { id = "data",      label = L["Data and support"], feature = "settings", sub = "data" },
        { id = "web",       label = L["Web"],              feature = "web" },
    } },
}

-- A split hub opened by its name alone (/gos open guild): the sub-tabs it opened on before the rooms, in
-- order, the first that may open (Achievements on WoW: Forever, else the calendar; #373).
UI.ROOM_PREFERRED = {
    guild = { "achievements", "calendar" }, raids = { "sessions" }, loot = { "rule" }, bank = { "inventory" },
    management = { "ranks" }, recruitment = { "recruiting" }, settings = { "profile" },
}

-- Where a tab another addon registers lands when no room names it: the Salão, so it stays reachable.
UI.ROOM_FALLBACK = "salao"

local function officer() return GuildOS:IsOfficer() and true or false end

local function room(id)
    for _, r in ipairs(UI.ROOMS) do if r.id == id then return r end end
    return nil
end
UI.RoomById = function(_, id) return room(id) end

-- Every feature some room names.
local function named()
    local out = {}
    for _, r in ipairs(UI.ROOMS) do
        for _, e in ipairs(r.entries) do out[e.feature] = true end
    end
    return out
end

-- The tab features no room names, as entries of the fallback room (a third-party tab).
local function strays()
    local seen, out = named(), {}
    for _, id in ipairs(UI.featureOrder or {}) do
        local def = UI.features[id]
        if def and def.tab and not seen[id] then
            out[#out + 1] = { id = "x:" .. id, label = def.label, feature = id }
        end
    end
    return out
end

-- May this entry open now? Its feature may (UI:IsFeatureAllowed: present, switched on, started, the
-- rank), so may the feature it needs, and a members-only entry is not an officer's.
function UI:EntryAllowed(e)
    if not e then return false end
    -- The window answers whether it built a panel for the feature (a tab another addon registered after it
    -- was built has none): an entry with no panel would be a button that does nothing.
    if self.HasPanel and not self:HasPanel(e.feature) then return false end
    if e.members and officer() then return false end
    if e.officer and not officer() then return false end
    if e.cond and not e.cond() then return false end
    if e.needs and not self:IsFeatureAllowed(self:GetFeature(e.needs)) then return false end
    return self:IsFeatureAllowed(self:GetFeature(e.feature))
end

-- A room's entries in order, the strays after the fallback room's own; `all` keeps the ones that may
-- not open now.
function UI:RoomEntries(id, all)
    local r = room(id)
    if not r then return {} end
    local list = {}
    for _, e in ipairs(r.entries) do list[#list + 1] = e end
    if id == self.ROOM_FALLBACK then
        for _, e in ipairs(strays()) do list[#list + 1] = e end
    end
    if all then return list end
    local out = {}
    for _, e in ipairs(list) do
        if self:EntryAllowed(e) then out[#out + 1] = e end
    end
    return out
end

-- May this room show? An officers' room only to an officer, and any room only while one of its
-- entries may open.
function UI:RoomAllowed(id)
    local r = room(id)
    if not r then return false end
    if r.officer and not officer() then return false end
    return #self:RoomEntries(id) > 0
end

-- The rooms the top bar draws, in order (never the gear's).
function UI:VisibleRooms()
    local out = {}
    for _, r in ipairs(self.ROOMS) do
        if not r.gear and self:RoomAllowed(r.id) then out[#out + 1] = r end
    end
    return out
end

-- The room and entry that open feature `id` (on sub-tab `sub`): the entry naming that sub-tab first,
-- then the one naming the feature with no sub-tab, then any entry of the feature. An officers' room is
-- skipped for a non-officer, so a deep link never lands there. Nil when no room holds it.
function UI:RoomOf(id, sub)
    if type(id) ~= "string" then return nil end
    local found = {}
    for _, r in ipairs(self.ROOMS) do
        if not (r.officer and not officer()) then
            for _, e in ipairs(self:RoomEntries(r.id, true)) do
                -- An action (Core Sign-up) is never where a screen opens.
                if e.feature == id and not e.run and not (e.members and officer()) then
                    found[#found + 1] = { r, e }
                end
            end
        end
    end
    local function first(test)
        for _, hit in ipairs(found) do if test(hit[2]) then return hit end end
    end
    -- A sub-tab this player may not open (a member's Cores, an absent module) falls through to the default.
    local hit = (sub and first(function(e) return e.sub == sub and self:EntryAllowed(e) end))
        or first(function(e) return not e.sub end)
    -- A hub split over rooms, opened by name alone, lands where the hub itself opened before the rooms.
    if not hit and self.ROOM_PREFERRED[id] then
        for _, want in ipairs(self.ROOM_PREFERRED[id]) do
            hit = first(function(e) return e.sub == want and self:EntryAllowed(e) end)
            if hit then break end
        end
    end
    hit = hit or found[1]
    if not hit then return nil end
    return hit[1], hit[2]
end

-- The entry a room opens on: the one saved for it when it may still open, else its first.
function UI:RoomDefault(id, saved)
    local list = self:RoomEntries(id)
    if saved then
        for _, e in ipairs(list) do if e.id == saved then return e end end
    end
    return list[1]
end
