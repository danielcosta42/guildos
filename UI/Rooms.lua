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
        { id = "polls",    label = L["Polls"],        feature = "guild", sub = "polls" },
        { id = "chat",     label = L["Chat"],         feature = "guild", sub = "chat" },
        { id = "alliance", label = L["Alliance"],     feature = "alliance" },
        { id = "veil",     label = L["Secret Santa"], feature = "winterveil" },
        { id = "recruit",  label = L["Recruitment"],  feature = "recruitment", members = true },
    } },
    { id = "raids", label = L["Raids"], entries = {
        { id = "calendar", label = L["Calendar"], feature = "guild", sub = "calendar" },
        { id = "raids",    label = L["Raids"],    feature = "raids" },
        { id = "groups",   label = L["Groups"],   feature = "groups" },
    } },
    { id = "members", label = L["Members"], entries = {
        { id = "roster", label = L["Members"], feature = "roster" },
    } },
    { id = "loot", label = L["Loot"], entries = {
        { id = "loot", label = L["Loot"], feature = "loot" },
    } },
    { id = "workshop", label = L["Workshop"], entries = {
        { id = "crafts", label = L["Crafts"],     feature = "recipes" },
        { id = "bank",   label = L["Guild bank"], feature = "bank" },
    } },
    { id = "chronicle", label = L["Chronicle"], entries = {
        { id = "achievements", label = L["Achievements"], feature = "guild", sub = "achievements", needs = "achievements" },
        { id = "journal",      label = L["Journal"],      feature = "guild", sub = "journal", needs = "journal" },
        { id = "activity",     label = L["Activity"],     feature = "guild", sub = "activity" },
    } },
    { id = "officers", label = L["Officers' Room"], officer = true, entries = {
        { id = "leadership",  label = L["Leadership"],  feature = "management" },
        { id = "recruitment", label = L["Recruitment"], feature = "recruitment" },
    } },
    -- The gear in the title bar: never drawn among the rooms.
    { id = "settings", label = L["Settings"], gear = true, entries = {
        { id = "settings", label = L["Settings"], feature = "settings" },
        { id = "web",      label = L["Web"],      feature = "web" },
    } },
}

-- A split hub opened by its name alone (/gos open guild): the sub-tabs it opened on before the rooms, in
-- order, the first that may open (Achievements on WoW: Forever, else the calendar; #373).
UI.ROOM_PREFERRED = { guild = { "achievements", "calendar" } }

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
    if e.members and officer() then return false end
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
    local exact, plain, any
    for _, r in ipairs(self.ROOMS) do
        if not (r.officer and not officer()) then
            for _, e in ipairs(self:RoomEntries(r.id, true)) do
                if e.feature == id and not (e.members and officer()) then
                    if sub and e.sub == sub then exact = exact or { r, e } end
                    if not e.sub then plain = plain or { r, e } end
                    any = any or { r, e }
                end
            end
        end
    end
    -- A hub split over rooms, opened by name alone, lands where the hub itself opened before the rooms.
    if not (exact or plain) and self.ROOM_PREFERRED[id] then
        for _, want in ipairs(self.ROOM_PREFERRED[id]) do
            local r, e = self:RoomOf(id, want)
            if e and e.sub == want and self:EntryAllowed(e) then return r, e end
        end
    end
    local hit = exact or plain or any
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
