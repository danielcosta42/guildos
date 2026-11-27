----------------------------------------------------------------------
-- Guild OS - Global Search
-- One box to find anything the guild knows: members by name, items in the loot history, who can craft a
-- recipe, and the window's own screens (every room's entries and Settings' sections, by name). Read-only.
--
-- Since #449 the search is a strip inside the window (UI/Window.lua, the mockup's .search), its results drawn
-- in the window's view in place of the screen (UI/SearchView.lua); there is no floating window any more.
-- Search:Show(text) is the way in for /gos find and /gos search.
----------------------------------------------------------------------
local Search = {}
GuildOS.Search = Search
local L = GuildOS.L

local CAP = 20   -- max results per category
local DOT = " \194\183 "

-- The fewest characters a query takes before anything is searched (a whole UTF-8 character counts once).
Search.MIN = 2

-- The groups, in the order the results show them.
Search.GROUPS = { "members", "loot", "recipes", "screens" }

-- Settings' sections by name (UI/SettingsPanel.lua's F:Section titles), each with the page that holds it and,
-- where the page draws it only sometimes, the same test.
local function officer() return GuildOS:IsOfficer() and true or false end
-- `words`: what a player may type for it that its title does not say (Discord 1574577794908954674: "flood" found
-- nothing), one translated, comma-separated list; a translator puts their language's words (and the English ones
-- players use anyway) in it.
Search.SETTINGS_SECTIONS = {
    { sub = "profile",   label = L["Your raid roles"], words = L["role, tank, healer, dps, spec"] },
    { sub = "profile",   label = L["Notices"], words = L["login, digest, popup, notification, version"] },
    { sub = "profile",   label = L["Privacy"], cond = function() return GuildOS.Journal ~= nil or GuildOS.GuildMap ~= nil end,
      words = L["share, location, map, journal, hide"] },
    { sub = "profile",   label = L["Birthday"], cond = function() return GuildOS.Birthdays ~= nil end },
    { sub = "profile",   label = L["Getting started"], words = L["intro, tutorial, onboarding, help"] },
    { sub = "interface", label = L["Appearance"], words = L["font, game font, scale, size, look"] },
    { sub = "interface", label = L["In the game"], words = L["minimap, button, tooltip, alt-click, snow"] },
    { sub = "chat",      label = L["Guild chat"], words = L["whisper, timestamp, class colours, alt tag, chat tweaks"] },
    { sub = "chat",      label = L["Mentions"], cond = function() return GuildOS.db and GuildOS.db.mentions ~= nil end,
      words = L["mention, my name, ping, sound, watch word"] },
    { sub = "chat",      label = L["Groups"], cond = function() return GuildOS.db and GuildOS.db.lfgPrefs ~= nil end,
      words = L["lfg, looking for group, dungeon"] },
    { sub = "modules",   label = L["Window tabs"], words = L["module, tab, turn off, disable, enable"] },
    { sub = "rules",     label = L["Who is an officer in Guild OS"], words = L["rank, officer, permission"] },
    { sub = "rules",     label = L["Calendar events"], words = L["event, raid, signup, invite"] },
    { sub = "rules",     label = L["Attendance"], cond = function() return GuildOS.RaidTracker ~= nil end,
      words = L["late, left early, penalty"] },
    { sub = "rules",     label = L["The !note command"], cond = function() return officer() and GuildOS.Client.isAnniversary end },
    { sub = "data",      label = L["Your data"], words = L["backup, export, import, saved variables"] },
    { sub = "data",      label = L["Whole guild database"], words = L["delete, old guild, clean, size"] },
    { sub = "data",      label = L["Diagnostics"], words = L["debug, error, bug, report"] },
    { sub = "data",      label = L["Test functions"], cond = officer },
    { sub = "data",      label = L["About"], words = L["version, discord, support"] },
    { sub = "data",      label = L["Danger zone"], words = L["erase, wipe, reset"] },
}

-- The cards inside a room's screen that players look for by what they do, not by the screen's name: each found
-- under its own name, its room and screen as the context. `room`/`entry`: UI/Rooms.lua's ids.
Search.SCREEN_WORDS = {
    { room = "officers", entry = "alertrules", name = L["Anti-flood"],
      words = L["flood, anti-flood, spam, repeated messages, too many messages, mute"] },
    { room = "officers", entry = "alertrules", words = L["alert, rule, swear, insult, gold seller, link, keyword"] },
    { room = "officers", entry = "recruiting", name = L["Welcome Message (New Members)"],
      words = L["welcome, greeting, greet, new member, newcomer"] },
    { room = "officers", entry = "recruiting", name = L["Auto-Invite (whisper keyword)"],
      words = L["invite, auto-invite, inv, whisper, keyword"] },
    { room = "officers", entry = "remind", words = L["reminder, install, no addon, without addon"] },
    { room = "officers", entry = "ban", words = L["ban, blacklist, block"] },
    { room = "officers", entry = "former", words = L["left, kicked, departure, ex-member, rejoin"] },
    { room = "officers", entry = "motd", words = L["message of the day, guild info"] },
}

-- How many characters `s` holds (UTF-8).
local function chars(s)
    local _, n = tostring(s or ""):gsub("[^\128-\191]", "")
    return n
end
Search.Chars = chars

local function has(hay, text) return hay ~= nil and strlower(tostring(hay)):find(text, 1, true) ~= nil end

-- A name that starts with the query sorts before one that only holds it.
local function starts(hay, text) return strlower(tostring(hay or "")):sub(1, #text) == text end

----------------------------------------------------------------------
-- Members on the guild roster whose name holds the query; online first.
----------------------------------------------------------------------
-- Also by the public note, the officer note (only where this rank reads them), the main's name and the nickname
-- (specs/salao/manutencao-roster.md): such a result says which matched (`via`, and a tag on its line).
local function members(text)
    local out = {}
    local n = GetNumGuildMembers() or 0
    local RM, MM = GuildOS.RosterMaint, GuildOS.MemberMarks
    local canOfficer = GuildOS.Compat.CanViewOfficerNote()
    local links = (GuildOS.db and GuildOS.db.altLinks) or {}
    for i = 1, n do
        local name, rank, _, level, _, zone, note, onote, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local via, mainName
            if not has(short, text) and RM then
                local key = GuildOS:KeyOfRosterName(name)
                local main = links[key]
                mainName = main and (main:match("^([^-]+)") or main) or nil
                via = RM.MatchVia({ note = RM.NoteText(note), officerNote = canOfficer and RM.NoteText(onote) or nil,
                    main = mainName, nick = MM and MM:Nick(key) or nil }, text)
            end
            if has(short, text) or via then
                local parts = { string.format(L["Level %d"], level or 0) }
                if rank and rank ~= "" then parts[#parts + 1] = rank end
                parts[#parts + 1] = online and (zone ~= "" and zone or nil) or L["offline"]
                if via then parts[#parts + 1] = RM.ViaText(via, mainName) end
                out[#out + 1] = { kind = "member", name = short, class = classFile or "", level = level or 0,
                    online = online and true or false, sub = table.concat(parts, DOT), via = via }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        -- A name that holds the query before a note that does.
        if (a.via == nil) ~= (b.via == nil) then return a.via == nil end
        local sa, sb = starts(a.name, text), starts(b.name, text)
        if sa ~= sb then return sa end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

----------------------------------------------------------------------
-- Items in the loot history, the latest first.
----------------------------------------------------------------------
local function loot(text)
    local out = {}
    local list = GuildOS:IsFeatureEnabled("lootTracker") and GuildOS.db.lootHistory or {}
    for i = #list, 1, -1 do
        local e = list[i]
        local iname, quality, icon
        if e.itemLink then
            local info = { GuildOS.Compat.GetItemInfo(e.itemLink) }
            iname, quality, icon = info[1], info[3], info[10]
        end
        iname = iname or e.itemName or (e.itemLink and e.itemLink:match("%[(.-)%]")) or ""
        if iname ~= "" and has(iname, text) then
            out[#out + 1] = { kind = "loot", name = iname, link = e.itemLink, icon = icon, quality = quality,
                sub = (e.player or "?") .. DOT .. GuildOS:DateText(e.timestamp or 0) }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Recipes someone in the guild crafts: the Workshop's index (RecipeTracker), else the raw scans.
----------------------------------------------------------------------
local function crafterLine(names)
    local shown = {}
    for i = 1, math.min(3, #names) do shown[i] = names[i] end
    local line = table.concat(shown, ", ")
    if #names > 3 then line = line .. " " .. string.format(L["%d more"], #names - 3) end
    return line
end

local function recipes(text)
    local out, seen = {}, {}
    -- The Workshop's catalog: the recipes someone in the guild knows (Modules/ProfDirectory.lua).
    local D = GuildOS.ProfDirectory
    local okD, rows = false, nil
    if D and D.RecipeRows then okD, rows = pcall(D.RecipeRows, nil, "guild", text) end
    if okD and type(rows) == "table" then
        for _, e in ipairs(rows) do
            local names = {}
            for _, k in ipairs(e.crafters or {}) do names[#names + 1] = k:match("^([^-]+)") or k end
            table.sort(names)
            local parts = { D.DisplayName(e.line) }
            if #names > 0 then parts[#parts + 1] = crafterLine(names) end
            seen[strlower(e.name or "")] = true
            out[#out + 1] = { kind = "recipe", name = e.name or "?", recipeId = e.id, itemId = e.out,
                icon = e.out and select(10, GuildOS.Compat.GetItemInfo(e.out)) or nil,
                sub = table.concat(parts, DOT) }
        end
    end
    local RT = GuildOS.RecipeTracker
    local ok, list = false, nil
    if RT and RT.Search then ok, list = pcall(RT.Search, RT, text, "All") end
    if ok and type(list) == "table" then
        -- The older scans (RecipeTracker), for a recipe the catalog did not already give.
        for _, e in ipairs(list) do
            local names, parts = {}, {}
            for _, c in ipairs(e.crafters or {}) do names[#names + 1] = c.playerName end
            if e.profName then parts[#parts + 1] = L[e.profName] end
            if #names > 0 then parts[#parts + 1] = crafterLine(names) end
            if not seen[strlower(e.name or "")] then
                out[#out + 1] = { kind = "recipe", name = e.name or "?", itemId = e.itemId, profName = e.profName,
                    icon = e.itemId and select(10, GuildOS.Compat.GetItemInfo(e.itemId)) or nil,
                    sub = table.concat(parts, DOT) }
            end
        end
        return out
    end
    -- No index (the module is off): who scanned a recipe of that name.
    local hits = {}
    -- The lists as stored: RecipeTracker's compact shape (db.recipeIds: a name kept, else the game's), or the
    -- old one (db.recipes) a version before memoria.md left while the module stayed off.
    local function hit(rname, crafter)
        if rname and has(rname, text) then
            hits[rname] = hits[rname] or {}
            hits[rname][crafter] = true
        end
    end
    for _, store in ipairs({ GuildOS.db.recipeIds or {}, GuildOS.db.recipes or {} }) do
        for key, profs in pairs(store) do
            local crafter = key:match("^([^-]+)") or key
            for _, rs in pairs(type(profs) == "table" and profs or {}) do
                if type(rs) == "table" and type(rs[1]) == "table" then
                    for _, r in pairs(rs) do
                        hit((type(r) == "table" and (r.name or r.itemName)) or (type(r) == "string" and r) or nil, crafter)
                    end
                elseif type(rs) == "table" then
                    local nm = type(rs.nm) == "table" and rs.nm or {}
                    for i = 1, math.floor(#rs / 2) do
                        local sid = rs[2 * i - 1]
                        hit(nm[i] or (type(sid) == "number" and sid > 0 and GuildOS.Compat.GetSpellInfo(sid)) or nil, crafter)
                    end
                end
            end
        end
    end
    for rname, set in pairs(hits) do
        if not seen[strlower(rname)] then
            local names = {}
            for c in pairs(set) do names[#names + 1] = c end
            table.sort(names)
            out[#out + 1] = { kind = "recipe", name = rname, sub = crafterLine(names) }
        end
    end
    return out
end

----------------------------------------------------------------------
-- The window's screens: every entry of a room this player may open (Settings' included), by its name or its
-- room's, Settings' sections by their titles or their words, and the cards of SCREEN_WORDS by what they do.
----------------------------------------------------------------------
local function screens(text)
    local out, UI = {}, GuildOS.UI
    if not (UI and UI.ROOMS and UI.RoomEntries) then return out end
    local settingsEntry = {}
    for _, room in ipairs(UI.ROOMS) do
        if UI:RoomAllowed(room.id) then
            for _, e in ipairs(UI:RoomEntries(room.id)) do
                if room.gear and e.sub then settingsEntry[e.sub] = e end
                if has(e.label, text) or has(room.label, text) then
                    out[#out + 1] = { kind = "screen", name = e.label, roomId = room.id, entry = e,
                        sub = room.label }
                end
            end
        end
    end
    local pages = {}
    for _, e in ipairs(UI:RoomEntries("settings")) do if e.sub then pages[e.sub] = e.label end end
    for _, s in ipairs(Search.SETTINGS_SECTIONS) do
        local e = settingsEntry[s.sub]
        if e and (has(s.label, text) or has(s.words, text)) and not (s.cond and not s.cond()) then
            out[#out + 1] = { kind = "screen", name = s.label, roomId = "settings", entry = e,
                sub = L["Settings"] .. DOT .. (pages[s.sub] or s.sub) }
        end
    end
    -- A card found by what it does: once, under its own name (or its screen's), unless its screen already is.
    local listed = {}
    for _, r in ipairs(out) do listed[tostring(r.roomId) .. "/" .. tostring(r.entry and r.entry.id) .. "/" .. tostring(r.name)] = true end
    for _, w in ipairs(Search.SCREEN_WORDS) do
        if has(w.words, text) or (w.name and has(w.name, text)) then
            local room = UI.RoomEntries and UI:RoomAllowed(w.room) and UI:RoomEntries(w.room) or {}
            for _, e in ipairs(room) do
                local name = w.name or e.label
                local key = w.room .. "/" .. e.id .. "/" .. tostring(name)
                if e.id == w.entry and not listed[key] then
                    listed[key] = true
                    local roomLabel
                    for _, r in ipairs(UI.ROOMS) do if r.id == w.room then roomLabel = r.label end end
                    out[#out + 1] = { kind = "screen", name = name, roomId = w.room, entry = e,
                        sub = w.name and ((roomLabel or w.room) .. DOT .. e.label) or roomLabel }
                end
            end
        end
    end
    -- Whose name starts with the query first, the room's order kept otherwise.
    for i, r in ipairs(out) do r.order = i end
    table.sort(out, function(a, b)
        local sa, sb = starts(a.name, text), starts(b.name, text)
        if sa ~= sb then return sa end
        return a.order < b.order
    end)
    return out
end

----------------------------------------------------------------------
-- Query everything. Returns { members = {...}, loot = {...}, recipes = {...}, screens = {...}, total = n }:
-- each result a { kind, name, sub (its context line), ... } the results view draws and Search:Open opens.
-- Under Search.MIN characters, nothing.
----------------------------------------------------------------------
function Search:Query(text)
    text = strlower(strtrim(text or ""))
    local res = { members = {}, loot = {}, recipes = {}, screens = {}, total = 0 }
    if chars(text) < self.MIN then return res end
    local db = GuildOS.db or {}
    local function run(key, fn)
        local ok, list = pcall(fn, text)
        if not ok then return end
        local t = {}
        for i = 1, math.min(CAP, #list) do t[i] = list[i] end
        res[key], res.total = t, res.total + #t
        res[key].more = math.max(0, #list - #t)
    end
    run("members", members)
    if db.lootHistory then run("loot", loot) end
    run("recipes", recipes)
    run("screens", screens)
    return res
end

----------------------------------------------------------------------
-- Open a result: a member's card, the loot history, the recipe's card in the Workshop, the screen.
----------------------------------------------------------------------
function Search:Open(r)
    if type(r) ~= "table" then return false end
    local UI = GuildOS.UI
    local f = GuildOS.RosterFrame
    -- Opening a result leaves the search: the window shows what was opened (or, for a member's card, the
    -- screen the search covered, the card over it).
    if f and f.CloseSearch then f:CloseSearch() end
    if r.kind == "member" then
        local rec = GuildOS:GetMemberRecord(r.name)
        if rec and GuildOS.ShowMemberDetail then GuildOS:ShowMemberDetail(rec); return true end
        return UI:OpenWindow("roster")
    elseif r.kind == "loot" then
        return UI:OpenWindow("loot", "history")
    elseif r.kind == "recipe" then
        -- The Workshop's catalog, on the recipe (by its id, else its name); else the recipe that makes its item.
        if not UI:OpenWindow("recipes") then return false end
        local tab = GuildOS.craftsTab
        if tab and tab.ShowView then tab.ShowView("catalog") end
        local panel = tab and tab.panel
        if panel and panel.FocusRecipe and panel:FocusRecipe(r.recipeId, r.name, r.profName) then return true end
        if r.itemId and GuildOS.ShowCraftFor then return GuildOS:ShowCraftFor(r.itemId) end
        return true
    elseif r.kind == "screen" then
        f = f or UI:GetMainWindow()
        if not f then return false end
        f:Show()
        return f:SelectEntry(r.roomId, r.entry, true)
    end
    return false
end

----------------------------------------------------------------------
-- /gos find <text>, /gos search: the window, its search strip open and filled.
----------------------------------------------------------------------
function Search:Show(initial)
    local UI = GuildOS.UI
    if UI and UI.OpenSearch then return UI:OpenSearch(initial) end
end
