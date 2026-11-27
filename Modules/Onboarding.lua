----------------------------------------------------------------------
-- Guild OS - Onboarding: what's new, the tours, getting started (specs/salao/onboarding.md)
--
-- Frame-free: the cards of the What's new / Welcome window, the three tours (member, officer, Guild
-- Master) with their chapters and steps, the client filters, the getting-started checklists and their
-- predicates, and the state that remembers what this account saw. UI/Onboarding.lua draws the window,
-- UI/Tour.lua runs a tour, UI/HelpPanel.lua lists them, UI/Salao.lua draws the officers' card. Tested by
-- tools/onboarding.lua.
--
-- Storage (nothing synced: tutorials are local):
--   GuildOSDB._onboard      the account's, every guild and character: feature (the big cards' id, 2.0, once
--                           closed), seen (the last release whose notes were closed), later (how many times
--                           "Later" was pressed for what is pending now, laterFor), dotSeen,
--                           tours = { [track] = { step, done, chapters = { [chapter] = true } } },
--                           chars = { ["Name-Realm"] = { gs = { hidden = ts } } } (the members' list, per character)
--   db.settings.gettingStarted   the officers' card, per guild: { hidden = ts, byHand = true, doneAt = ts, celebrated = true }
--   db.settings.onboarded   kept: true means this account used Guild OS before (What's new instead of Welcome)
-- A checklist tick is never stored: each is a test on data Guild OS already holds.
----------------------------------------------------------------------
local O = {}
GuildOS.Onboarding = O
local L = GuildOS.L

local DAY = 86400
O.WHATS_NEW_ID = "2.0"          -- the release whose big cards these are (2.0.0, the Salão)
O.FEATURE_VERSION = "2.0.0"     -- its own notes are what the big cards tell: no notes cards after them
O.NOTES_PER_CARD = 3            -- every release opens What's new with its notes (Data/ReleaseNotes.lua),
O.MAX_NOTE_CARDS = 4            -- this many lines a card, this many cards at most
O.MAX_LATER = 3                 -- "Later" shows it again at the next login, this many times; then only the dot
O.HIDE_S = 30 * DAY             -- "Hide for 30 days" (Activation's HIDE_S)
O.STAY_S = DAY                  -- an all-done card stays in the Hall this long after it was done
O.URLS = {
    site = "https://guildos.me",
    manual = "https://guildos.me/manual",
    discord = "https://discord.gg/8XA6gmNjja",
}

local function now() return (GetServerTime and GetServerTime()) or time() end

----------------------------------------------------------------------
-- The client and the player
----------------------------------------------------------------------
-- "forever", "anniversary" or "retail".
function O.ClientKey()
    local c = GuildOS.Client or {}
    if c.isRetail then return "retail" end
    if c.isAnniversary then return "anniversary" end
    return "forever"
end

function O.ClientName(key)
    key = key or O.ClientKey()
    if key == "retail" then return L["Retail"] end
    if key == "anniversary" then return L["TBC Anniversary"] end
    return L["WoW: Forever"]
end

-- "member", "officer" or "gm".
function O.Role()
    if GuildOS.Compat and GuildOS.Compat.IsGuildLeader and GuildOS.Compat.IsGuildLeader() then return "gm" end
    if GuildOS.IsOfficer and GuildOS:IsOfficer() then return "officer" end
    return "member"
end

-- A text that may differ by client: a string, or { forever =, anniversary =, retail =, default = }, or a
-- function of the client key.
function O.Text(v, client)
    client = client or O.ClientKey()
    if type(v) == "function" then return v(client) end
    if type(v) == "table" then
        local t = v[client]
        if t == nil then t = v.default end
        return t
    end
    return v
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
-- The account's onboarding record, made on first use.
function O:Store()
    if type(GuildOSDB) ~= "table" then GuildOSDB = {} end
    local s = GuildOSDB._onboard
    if type(s) ~= "table" then
        s = {}
        GuildOSDB._onboard = s
    end
    s.tours = type(s.tours) == "table" and s.tours or {}
    s.chars = type(s.chars) == "table" and s.chars or {}
    s.later = tonumber(s.later) or 0
    -- The 2.0 test builds kept the big cards' id in seen, and "Don't show again" in never.
    if s.seen == O.WHATS_NEW_ID or s.never then s.feature, s.never = O.WHATS_NEW_ID, nil end
    if s.seen == O.WHATS_NEW_ID then s.seen = nil end
    -- "Later" counts for what is pending now: a new release starts again from nothing.
    local key = O:PendingKey(s)
    if s.laterFor ~= key then s.later, s.laterFor = 0, key end
    return s
end

-- This build's release notes, when they are this version's: { version, lines }. The release workflow writes
-- Data/ReleaseNotes.lua with the version; a build from the source has none.
function O:Notes()
    local n = GuildOS.RELEASE_NOTES
    if type(n) ~= "table" or type(n.lines) ~= "table" or #n.lines == 0 then return nil end
    if n.version ~= GuildOS.VERSION then return nil end
    return n
end

-- Whether the big 2.0 cards are still to see.
function O:FeaturePending(s)
    s = s or GuildOSDB and GuildOSDB._onboard or {}
    return s.feature ~= self.WHATS_NEW_ID
end

-- Whether this release's notes are still to see (none when the big cards tell them).
function O:NotesPending(s)
    s = s or GuildOSDB and GuildOSDB._onboard or {}
    local n = self:Notes()
    if not n or n.version == self.FEATURE_VERSION then return false end
    return s.seen ~= n.version
end

-- What is pending, as one key: "Later" and the dot count for it.
function O:PendingKey(s)
    local n = self:Notes()
    return (self:FeaturePending(s) and self.WHATS_NEW_ID or "-") .. "/" .. (n and n.version or "-")
end

-- The version the window names: this release's, else the big cards'.
function O:Version()
    local n = self:Notes()
    return n and n.version or self.WHATS_NEW_ID
end

-- This login's own memory: at most one onboarding popup each login.
O.session = { shown = false }

-- "welcome" for an account that never used Guild OS, "whatsnew" for one that did.
function O:Arrival()
    local s = self:Store()
    if s.seen or s.feature or s.welcomed or GuildOS:GetSetting("onboarded") then return "whatsnew" end
    -- A record of an older version's use on any of the account's guilds counts too.
    for k, v in pairs(GuildOSDB or {}) do
        if GuildOS.IsGuildDBKey and GuildOS.IsGuildDBKey(k, v) and type(v.settings) == "table" and v.settings.onboarded then
            return "whatsnew"
        end
    end
    return "welcome"
end

-- Whether something is still to see: the big cards, or a new release's notes. Every release opens it again.
function O:Pending()
    local s = self:Store()
    return self:FeaturePending(s) or self:NotesPending(s)
end

-- What the login shows, if anything: "whatsnew", "welcome" or nil. After MAX_LATER "Later"s only the dot.
function O:LoginKind()
    if not self:Pending() then return nil end
    if self:Store().later >= self.MAX_LATER then return nil end
    return self:Arrival()
end

-- The red dot on "?": the cards still pending but no longer shown at login, until the help is opened.
function O:Dot()
    local s = self:Store()
    if not self:Pending() then return false end
    if s.later < self.MAX_LATER then return false end
    return s.dotSeen ~= s.laterFor
end

function O:HelpOpened()
    local s = self:Store()
    if s.later >= self.MAX_LATER and self:Pending() then s.dotSeen = s.laterFor end
end

-- "Later", the close and Escape: shown again at the next login, MAX_LATER times.
function O:Later()
    local s = self:Store()
    s.later = math.min(self.MAX_LATER, s.later + 1)
    return s.later
end

-- Closed until the next release: what is pending now is done ("Got it", or read to the end).
local function closeNow(self, s)
    s.feature = self.WHATS_NEW_ID
    local n = self:Notes()
    if n then s.seen = n.version end
    s.later = 0
    s.laterFor = self:PendingKey(s)
end

-- "Got it": closed until the next release opens it again.
function O:Never()
    closeNow(self, self:Store())
end

-- Read to the end ("Take the tour", "Done", or Finish on the welcome): closed until the next release.
function O:Seen()
    local s = self:Store()
    closeNow(self, s)
    if self:Arrival() == "welcome" or not GuildOS:GetSetting("onboarded") then s.welcomed = true end
    GuildOS:SetSetting("onboarded", true)
end

-- "Show tips again": the account's record forgotten (tours, what's new, the members' hides).
function O:Reset()
    if type(GuildOSDB) == "table" then GuildOSDB._onboard = nil end
    local gs = GuildOS.db and GuildOS.db.settings and GuildOS.db.settings.gettingStarted
    if type(gs) == "table" then gs.hidden = nil end
    self.session.shown = false
end

----------------------------------------------------------------------
-- The login guard: never in combat (ShowWhenClear's), never inside an instance or in a raid group, at most
-- one onboarding popup each login.
----------------------------------------------------------------------
function O:Clear()
    if GuildOS.InCombat and GuildOS:InCombat() then return false, "combat" end
    if IsInInstance then
        local inside = IsInInstance()
        if inside then return false, "instance" end
    end
    if IsInRaid and IsInRaid() then return false, "raid" end
    return true
end

----------------------------------------------------------------------
-- What's new / Welcome: the cards
-- { id, title, body, ill (UI/Onboarding.lua's picture), tag, extra ("guildbutton" | "roles") }
----------------------------------------------------------------------
function O:Cards(kind, role, client)
    kind = kind or self:Arrival()
    role = role or O.Role()
    client = client or O.ClientKey()
    local off, gm = role ~= "member", role == "gm"
    local forever, retail = client == "forever", client == "retail"
    if kind == "welcome" then
        return {
            { id = "welcome", ill = "salao", title = L["Welcome to Guild OS"],
              body = L["Your guild in one window: who is online, the raids and their sign-ups, loot, crafts and the guild's story, synced between everyone who runs it."] },
            O.LookCard(),
            { id = "open", ill = "compact", title = L["Open it anytime"], extra = "guildbutton",
              body = L["/guildos, the minimap button, or the guild button (J). The guild button can stay Blizzard's: untick below."] },
            { id = "roles", ill = "raids", title = L["Your raid roles"], extra = "roles",
              body = L["Which roles can you play? Raiders and Groups pick this up, so officers don't have to set it."] },
            { id = "privacy", ill = "shield", title = L["Data & privacy"],
              body = retail and L["Guild OS shares your gear, professions, spec and wishlist with guildmates who run it. Officer notes and trials stay officer-only."]
                  or L["Guild OS shares your gear, professions, spec, attunements and wishlist with guildmates who run it. Officer notes and trials stay officer-only."] },
        }
    end
    local c = {
        O.LookCard(),
        { id = "salao", ill = "salao", title = L["Welcome to the Salão"],
          body = L["Guild OS was redrawn from top to bottom: wood, parchment and rooms instead of tabs. The Hall is your home: notices, who is by the fire, the guild wall."] },
        { id = "search", ill = "search", title = L["Rooms, a search and a bar"],
          body = L["Rooms across the top. The search finds people, items, recipes and even settings by what they do (\"flood\", \"font\"). Fold the window to the compact bar when you play."] },
        off and { id = "officers", ill = "officers", title = L["The Officers' Room"], tag = L["Officers"],
              body = L["Recruitment that posts to every channel in one click, roster care (data audit, alt-aware inactivity, former members), moderation in plain language and an audit log filled from the game's own."] }
            or { id = "members", ill = "members", title = L["Members, redrawn"],
              body = L["Big numbers on top, filters on the side, class crests and marks for who runs Guild OS. Click anyone for their window: equipment, history and alts."] },
        { id = "raids", ill = "raids", title = L["Raids & Groups"],
          body = off and L["Sign up from the calendar, find a group on the cards (who fits shows in green), and Raid Tools for leaders: invite the site's list, announce, assignments, a small combat HUD."]
              or L["Sign up from the calendar, and find a group on the cards: who fits shows in green."] },
        forever and { id = "map", ill = "map", title = L["The guild map & campfires"], tag = L["WoW: Forever"],
              body = L["Guildmates live on the world map, alongside OpenMap, and the guild's campfires where people gather."] }
            or { id = "bank", ill = "bank", title = L["The guild bank"],
              body = off and L["A new bank bar and Cleanup drawer, and a vendor window that sells only what came out of the bank. The Guild Master can set a bank tax."]
                  or L["A new bank bar and Cleanup drawer, and a vendor window that sells only what came out of the bank."] },
        { id = "light", ill = "light", title = L["Lighter, and safe"],
          body = L["Less memory, no stutter, compact saved data. Your old data is kept for 7 days: /gos backup."] },
    }
    if gm then
        table.insert(c, 7, { id = "gm", ill = "gm", title = L["For the Guild Master"], tag = L["Guild Master"],
            body = L["Guild-wide settings in one place: the shared welcome, the bank tax and points for donations, and linking the guild to guildos.me."] })
    end
    -- Six at most: the Guild Master's card takes the place of the last one.
    -- The look card first, then six at most.
    for i = #c, 8, -1 do c[i] = nil end
    -- After the big cards were seen: this release's notes alone (the big cards again when there are none,
    -- as in a build from the source); with them: the notes of a release after 2.0.0 follow.
    if not self:FeaturePending() then
        local notes = self:NoteCards({})
        if #notes == 0 then return c end
        -- Whoever has not chosen a look yet (dark mode came in 2.1) is asked first.
        local s = GuildOSDB and GuildOSDB._onboard
        if not (s and s.lookSeen) then table.insert(notes, 1, O.LookCard()) end
        return notes
    end
    if self:NotesPending() then self:NoteCards(c) end
    return c
end

-- "Light or dark?": the dark mode switch, among the first cards of the welcome and of What's new (2.1).
function O.LookCard()
    return { id = "look", ill = "light", title = L["Light or dark?"], extra = "darkmode",
        body = L["Guild OS comes in wood and parchment, or in dark mode: ebony wood and dark parchment, easier on the eyes at night. Change it any time in Settings › Interface."] }
end

-- Whether a card list is a release's notes (the look card may lead it): "Done" ends it, no tour after.
function O:IsNotesOnly(cards)
    if type(cards) ~= "table" or cards[1] == nil then return false end
    local first = cards[1]
    if first.id == "look" then first = cards[2] end
    return first ~= nil and first.notes == true
end

-- The look was chosen (the card's switch touched, or read past): the notes stop asking.
function O:LookSeen()
    self:Store().lookSeen = true
end

-- This release's notes as cards, NOTES_PER_CARD lines each, appended to `c`. The lines are the release's
-- changelog, in English (the stores show the same).
function O:NoteCards(c)
    local n = self:Notes()
    if not n then return c end
    local lines, per, max = n.lines, self.NOTES_PER_CARD, self.MAX_NOTE_CARDS
    local cards = math.min(max, math.ceil(#lines / per))
    for k = 1, cards do
        local body = {}
        for i = (k - 1) * per + 1, math.min(#lines, k * per) do body[#body + 1] = "\194\183 " .. lines[i] end
        local rest = #lines - cards * per
        if k == cards and rest > 0 then body[#body + 1] = string.format(L["And %d more in the full changelog."], rest) end
        c[#c + 1] = { id = "notes" .. k, ill = "notes", notes = true,
            title = string.format(L["What's new in %s"], n.version), body = table.concat(body, "\n") }
    end
    return c
end

----------------------------------------------------------------------
-- The tours
-- A step: { id, ch (its chapter's id), room, entry, anchor (UI:TourAnchor keys, the first found), title, body,
-- note, ill (a picture in the callout, for a step that has no frame to point at: picture = true),
-- clients ({ forever = true, ... }: only there), cond (a test of its own), needs (a feature) }.
----------------------------------------------------------------------
O.TRACK_ORDER = { "member", "officer", "gm" }

local function step(t) return t end

O.TRACKS = {
    member = {
        label = L["Member tour"],
        chapters = {
            { id = "way",    label = L["Find your way"] },
            { id = "raids",  label = L["Raids & groups"] },
            { id = "people", label = L["People, loot & crafts"] },
            { id = "yours",  label = L["Make it yours"] },
        },
        steps = {
            step{ id = "hall", ch = "way", room = "salao", entry = "home", anchor = { "door.salao" },
                title = L["The Hall is home"],
                body = L["Each room is a door up here. The Hall gathers what's happening: things for you, the notice board, who is by the fire."] },
            step{ id = "fire", ch = "way", room = "salao", entry = "home", anchor = { "salao.fire" },
                title = L["By the fire"],
                body = L["Who is online right now, and where. Click a face for that member's menu; hover the title for what the card counts."] },
            step{ id = "board", ch = "way", room = "salao", entry = "home", anchor = { "salao.board" },
                title = L["The notice board"],
                body = L["The next events as pinned notes, and the newest notices. Your answer to an event goes round its note: green, amber or red."] },
            step{ id = "chat", ch = "way", room = "salao", entry = "chat", anchor = { "entry.salao.chat" },
                title = L["Guild chat, inside"],
                body = L["Read and write to the guild without the chat frame. Links work; officer chat shows for officers."] },
            step{ id = "search", ch = "way", room = "salao", entry = "home", anchor = { "tool.search" },
                title = L["Search everything"],
                body = L["People, items, recipes and settings by what they do: try \"font\", \"welcome\" or \"backup\"."] },
            step{ id = "fold", ch = "way", room = "salao", entry = "home", anchor = { "tool.fold" },
                title = L["The compact bar"],
                body = L["Fold the window into a slim bar while you play: online count and alerts stay in sight. Click it to open again."] },
            step{ id = "signup", ch = "raids", room = "raids", entry = "calendar", anchor = { "raids.signup", "entry.raids.calendar" },
                title = L["Sign up for raids"],
                body = L["Pick the night in the calendar, then your role. Officers see it at once, and so does guildos.me."] },
            step{ id = "groups", ch = "raids", room = "raids", entry = "groups", anchor = { "groups.cards", "entry.raids.groups" },
                title = L["Groups & LFG"],
                body = L["Cards of who is looking and for what. Green means you fit. \"+ Form a group\" to post your own."] },
            step{ id = "core", ch = "raids", room = "raids", entry = "calendar", anchor = { "entry.raids.signup" },
                needs = { room = "raids", entry = "signup" },
                title = L["Core sign-up"],
                body = L["Want a seat in a raid core? This opens the sign-up window with your roles and availability."] },
            step{ id = "people", ch = "people", room = "members", entry = "roster", anchor = { "roster.search", "door.members" },
                title = L["Find people"],
                body = L["Search by name, level (60-70, >=60), class or rank; the filters on the side combine."] },
            step{ id = "member", ch = "people", room = "members", entry = "roster", picture = true, ill = "members",
                anchor = { "door.members" },
                title = L["The member window"],
                body = L["Equipment, history and alts in one place. Your own alts are linked here too: \"Add alt\" lists your guild characters as you type."] },
            step{ id = "wish", ch = "people", room = "loot", entry = "lists", anchor = { "loot.wishlist", "entry.loot.lists" },
                title = L["Your wishlist"],
                body = { retail = L["Put the items you want first; the loot council reads it when they drop."],
                         default = L["Put the items you want first. When one drops, the loot window asks you, and the loot master sees your list."] } },
            step{ id = "crafts", ch = "people", room = "workshop", entry = "crafts", anchor = { "crafts.search", "entry.workshop.crafts" },
                title = L["Who crafts it"],
                body = L["Search an item or a recipe: the guild's crafters first, then the realm. \"Request\" sends them a craft order."] },
            step{ id = "chronicle", ch = "people", room = "chronicle", anchor = { "door.chronicle" },
                title = L["The Chronicle"],
                body = { forever = L["The guild's story: the journal of clears (every dungeon and boss), achievements and activity."],
                         default = L["The guild's story: what happened this week, clears and milestones."] } },
            step{ id = "settings", ch = "yours", room = "settings", entry = "interface", anchor = { "settings.font", "tool.gear" },
                title = L["Your settings"],
                body = L["The gear opens Settings. Prefer the game's own font? Tick it here. The minimap button can go too."] },
            step{ id = "map", ch = "yours", room = "salao", entry = "home", picture = true, ill = "map",
                cond = function() return GuildOS.GuildMap ~= nil end,
                title = L["The guild map"],
                body = { forever = L["Guildmates show live on the world map, alongside OpenMap, with the guild's campfires: where people gather."],
                         default = L["Guildmates show live on the world map, and it works alongside OpenMap."] } },
            step{ id = "site", ch = "yours", room = "settings", entry = "web", anchor = { "web.site", "entry.settings.web" },
                title = L["guildos.me & the Companion"],
                body = L["The guild's page holds the calendar, rosters and loot. The Companion app takes your data there after you log out."] },
            step{ id = "help", ch = "yours", room = "salao", entry = "home", anchor = { "tool.help" },
                title = L["Help, anytime"],
                body = L["The \"?\" replays any tour and has short guides. Or type /gos help."] },
        },
    },
    officer = {
        label = L["Officers' Room tour"],
        officer = true,
        chapters = {
            { id = "recruit", label = L["Recruitment"] },
            { id = "care",    label = L["Roster care"] },
            { id = "records", label = L["Records"] },
            { id = "mod",     label = L["Moderation"] },
            { id = "rlb",     label = L["Raids, loot & bank"] },
        },
        steps = {
            step{ id = "room", ch = "recruit", room = "officers", entry = "recruiting", anchor = { "door.officers" },
                title = L["The Officers' Room"],
                body = L["Your room, in groups down the side. The red count is the work waiting for you."] },
            step{ id = "post", ch = "recruit", room = "officers", entry = "recruiting", anchor = { "recruit.post", "side.recruiting" },
                title = L["One click, every channel"],
                body = L["Write the ad once; \"Post\" sends it to Trade, LFG and General in turn, without the server's \"too fast\"."] },
            step{ id = "welcome", ch = "recruit", room = "officers", entry = "recruiting", anchor = { "recruit.welcome", "side.recruiting" },
                title = L["Welcome messages"],
                body = L["Several messages, one drawn at random for each newcomer, shared with every officer so only one of you greets."] },
            step{ id = "invite", ch = "recruit", room = "officers", entry = "recruiting", anchor = { "recruit.invite", "side.recruiting" },
                title = { forever = L["Invites on WoW: Forever"], default = L["Auto-invite & the queue"] },
                body = { forever = L["The game does not let addons invite here. Requests wait in the queue: copy the /ginvite line and send it."],
                         default = L["Whispers \"inv\" join the queue. The game asks one key press or click per invite: the queue shows whose turn it is."] },
                note = { forever = L["WoW: Forever lets no addon invite."], default = L["One key press per invite."] } },
            step{ id = "scanner", ch = "recruit", room = "officers", entry = "scanner", anchor = { "side.scanner" },
                title = L["Scanner & trials"],
                body = L["Find unguilded players by level and class; Trials follows newcomers until they are promoted."] },
            step{ id = "suggest", ch = "care", room = "officers", entry = "suggest", anchor = { "side.suggest" },
                title = L["Suggestions"],
                body = L["Promotions due, inactive members, alts with no main: do or dismiss, one click each."] },
            step{ id = "ranks", ch = "care", room = "officers", entry = "ranks", anchor = { "side.ranks" },
                title = L["Ranks"],
                body = L["Promote or demote from the list; the game asks you to confirm. Time in rank comes from the game's guild event log."] },
            step{ id = "inactive", ch = "care", room = "officers", entry = "inactive", anchor = { "inactive.safe", "side.inactive" },
                title = L["Inactivity, alt-aware"],
                body = L["Someone is active when any alt played. The safe list keeps a member off it until a date you pick."] },
            step{ id = "bulk", ch = "care", room = "officers", entry = "bulk", anchor = { "side.bulk" },
                title = L["Bulk actions & presets"],
                body = L["Pick many, then promote, demote or remove. The game runs each one on your key press; presets save the filter."],
                note = L["Rank changes need one key press per member on every client."] },
            step{ id = "remind", ch = "care", room = "officers", entry = "remind", anchor = { "side.remind" },
                title = L["Without GuildOS"],
                body = L["Who doesn't run the addon (an alt counts when the main does), with a polite reminder."] },
            step{ id = "marks", ch = "records", room = "officers", entry = "marks", anchor = { "side.marks" },
                title = L["Notes and marks"],
                body = { anniversary = L["Write the game's public and officer notes from here, and add Guild OS marks."],
                         default = L["The game won't let addons write notes here: Guild OS keeps its own, shared with officers, and tells you what to type."] },
                note = function(c) if c == "anniversary" then return nil end
                    return string.format(L["No note writes from addons on %s."], O.ClientName(c)) end },
            step{ id = "audit", ch = "records", room = "officers", entry = "audit", anchor = { "side.audit" },
                title = L["Data audit"],
                body = L["Who lacks a join date or an alt link, or has a note that disagrees with the history."] },
            step{ id = "former", ch = "records", room = "officers", entry = "former", anchor = { "side.former" }, ill = "departure",
                title = L["Departures & returns"],
                body = L["When someone leaves or is removed, one popup gathers the note, the ban and their alts. A returning member gets \"welcome back\". Former members keeps the record."] },
            step{ id = "alerts", ch = "mod", room = "officers", entry = "alerts", anchor = { "side.alerts" },
                title = L["Chat alerts"],
                body = L["Lines that matched a rule, with who and the context around them."] },
            step{ id = "alertrules", ch = "mod", room = "officers", entry = "alertrules", anchor = { "side.alertrules" },
                title = L["Alert rules, in plain words"],
                body = L["Pick a sentence (\"anti-flood: 5 lines in 10 s\") and tune it. No patterns to learn."] },
            step{ id = "ban", ch = "mod", room = "officers", entry = "ban", anchor = { "side.ban" },
                title = L["Ban list & audit log"],
                body = L["Bans follow alts and warn you on whisper, group or invite. The audit log keeps every change, backfilled from the game."] },
            step{ id = "motd", ch = "mod", room = "officers", entry = "motd", anchor = { "side.motd" },
                title = L["The guild's word"],
                body = L["MOTD and info, and the Alliance with another guild: shared chat, bans and groups."] },
            step{ id = "raidtools", ch = "rlb", room = "raids", entry = "raidtools", anchor = { "entry.raids.raidtools" },
                title = L["Raid Tools"],
                body = L["For raid leaders: invite the site's list, announce in /raid, fight assignments, a small combat HUD you can hide."] },
            step{ id = "loot", ch = "rlb", room = "loot", entry = "rule", anchor = { "entry.loot.rule" },
                title = { retail = L["Loot council"], default = L["Loot master"] },
                body = { retail = L["Retail has no loot master: pick the rule (free roll, wishlist, council) and the council votes from the lists."],
                         default = L["Choose the rule (/roll, Wishlist, DKP, SR+). Closed the table by mistake? /gos lm reopens it."] } },
            step{ id = "cleanup", ch = "rlb", room = "workshop", entry = "cleanup", anchor = { "bank.cleanup", "entry.workshop.cleanup" },
                title = L["Bank cleanup"],
                body = L["Items nobody asked for, by tab; the vendor window sells only what came out of the bank."] },
            step{ id = "points", ch = "rlb", room = "loot", entry = "accounts", anchor = { "points.bank", "entry.loot.accounts" },
                cond = function() return GuildOS.Points ~= nil end,
                title = L["Points for donations"],
                body = L["Deposits can earn points under a named reason and a weekly cap, granted once by one officer."] },
        },
    },
    gm = {
        label = L["Guild Master extras"],
        gm = true,
        chapters = { { id = "gm", label = L["Guild Master"] } },
        steps = {
            step{ id = "officers", ch = "gm", room = "settings", entry = "rules", anchor = { "settings.officerRanks", "entry.settings.rules" },
                title = L["Who counts as an officer"],
                body = L["Pick the ranks that open the Officers' Room. Everything officer-only follows this."] },
            step{ id = "welcome", ch = "gm", room = "officers", entry = "recruiting", anchor = { "recruit.welcome", "side.recruiting" },
                title = L["The shared welcome"],
                body = L["Set the guild's own welcome messages: every officer's client uses them, one at random."] },
            step{ id = "tax", ch = "gm", room = "settings", entry = "rules", anchor = { "settings.bankTax", "entry.settings.rules" },
                title = L["Bank tax"],
                body = L["A share of each withdrawal the member owes until they deposit gold. Off by default; the member is told gently."] },
            step{ id = "site", ch = "gm", room = "settings", entry = "web", anchor = { "web.link", "entry.settings.web" },
                title = L["Link the guild to guildos.me"],
                body = { forever = L["The site holds the calendar, rosters and loot, and the Discord bot. On WoW: Forever the Get started card follows the five activation steps."],
                         default = L["The site holds the calendar, rosters and loot, and the Discord bot."] } },
        },
    },
}

-- Whether `track` is this player's: the member tour always, the officers' for an officer, the extras for the GM.
function O:TrackAllowed(track, role)
    local t = self.TRACKS[track]
    if not t then return false end
    role = role or O.Role()
    if t.gm then return role == "gm" end
    if t.officer then return role ~= "member" end
    return true
end

function O:TracksFor(role)
    local out = {}
    for _, id in ipairs(self.TRACK_ORDER) do
        if self:TrackAllowed(id, role) then out[#out + 1] = id end
    end
    return out
end

-- The entry a step opens may open now (UI:EntryAllowed: the module on, the rank, the client).
local function entryOpens(roomId, entryId)
    local UI = GuildOS.UI
    if not (UI and UI.RoomAllowed and UI.RoomEntries) then return true end
    if not UI:RoomAllowed(roomId) then return false end
    if not entryId then return true end
    for _, e in ipairs(UI:RoomEntries(roomId)) do if e.id == entryId then return true end end
    return false
end
O.EntryOpens = entryOpens

-- A track's steps for this client and player, as tables of their own with the texts resolved: a step whose
-- client is not this one, whose test fails, or whose screen may not open here (a module off, a client that
-- lacks it) is left out. ctx: { client, allowed = function(room, entry) } for the tests.
function O:Steps(track, ctx)
    ctx = ctx or {}
    local t = self.TRACKS[track]
    if not t then return {} end
    -- Not this player's tour (an officers' tour asked by a member): nothing. The tests pass `allowed`.
    if not ctx.allowed and not self:TrackAllowed(track) then return {} end
    local client = ctx.client or O.ClientKey()
    local allowed = ctx.allowed or entryOpens
    local out = {}
    for _, s in ipairs(t.steps) do
        local ok = not (s.clients and not s.clients[client])
        if ok and s.cond and not s.cond(client) then ok = false end
        if ok and not allowed(s.room, s.entry) then ok = false end
        if ok and s.needs and not allowed(s.needs.room, s.needs.entry) then ok = false end
        if ok then
            out[#out + 1] = {
                id = s.id, key = track .. "." .. s.id, track = track, ch = s.ch, room = s.room, entry = s.entry,
                anchor = s.anchor or {}, picture = s.picture, ill = s.ill,
                title = O.Text(s.title, client), body = O.Text(s.body, client), note = O.Text(s.note, client),
            }
        end
    end
    return out
end

-- The chapters a list of steps holds, in order: { { id, label, first (index), count } }.
function O:Chapters(track, steps)
    steps = steps or self:Steps(track)
    local t = self.TRACKS[track]
    local labels = {}
    for _, c in ipairs(t and t.chapters or {}) do labels[c.id] = c.label end
    local out, by = {}, {}
    for i, s in ipairs(steps) do
        local c = by[s.ch]
        if not c then
            c = { id = s.ch, label = labels[s.ch] or s.ch, first = i, count = 0 }
            by[s.ch] = c
            out[#out + 1] = c
        end
        c.count = c.count + 1
    end
    return out
end

-- A track's progress: { step (the next one to show, 1-based), done, chapters = { [id] = true } }.
function O:Progress(track)
    local s = self:Store()
    local p = s.tours[track]
    if type(p) ~= "table" then
        p = { step = 1, chapters = {} }
        s.tours[track] = p
    end
    p.step = tonumber(p.step) or 1
    p.chapters = type(p.chapters) == "table" and p.chapters or {}
    return p
end

-- How far along: 0..100 (100 once done).
function O:Percent(track, steps)
    local p = self:Progress(track)
    if p.done then return 100 end
    steps = steps or self:Steps(track)
    if #steps == 0 then return 0 end
    return math.floor(100 * math.max(0, math.min(#steps, p.step - 1)) / #steps)
end

-- Step `i` of `steps` reached: the next one to resume on, and the chapters left behind done.
function O:Reached(track, i, steps)
    local p = self:Progress(track)
    p.step = i
    steps = steps or self:Steps(track)
    local lastOf = {}
    for j, st in ipairs(steps) do lastOf[st.ch] = j end
    for ch, j in pairs(lastOf) do if j < i then p.chapters[ch] = true end end
end

function O:Finished(track)
    local p = self:Progress(track)
    p.done, p.step = true, 1
    for _, c in ipairs(self.TRACKS[track] and self.TRACKS[track].chapters or {}) do p.chapters[c.id] = true end
end

-- Where a track starts: its chapter `ch` when given, else where it was left (the start when done).
function O:StartIndex(track, steps, ch)
    steps = steps or self:Steps(track)
    if ch then
        for i, s in ipairs(steps) do if s.ch == ch then return i end end
    end
    local p = self:Progress(track)
    if p.done then return 1 end
    return math.max(1, math.min(#steps, p.step))
end

----------------------------------------------------------------------
-- The guides (Settings › Help): a picture, a few lines, where "Show me" goes.
-- { id, title, ill, body, officer, track, ch }
----------------------------------------------------------------------
O.GUIDES = {
    { id = "rooms",    ill = "salao",    title = L["Rooms & the Hall"], track = "member", ch = "way",
      body = L["Each room is a door; entries are the pills under the bar. The Hall gathers For you, notices, By the fire and the wall."] },
    { id = "search",   ill = "search",   title = L["Search"], track = "member", ch = "way",
      body = L["The magnifier finds people, items, recipes and settings by what they do. Enter opens the first hit."] },
    { id = "signup",   ill = "raids",    title = L["Raid sign-up"], track = "member", ch = "raids",
      body = L["Calendar, the night, your role. Tentative and Can't come count too. Core sign-up is for a seat in a core."] },
    { id = "groups",   ill = "raids",    title = L["Groups & LFG"], track = "member", ch = "raids",
      body = L["Post what you look for; cards show who fits. Whisper from the card."] },
    { id = "alts",     ill = "members",  title = L["Alts"], track = "member", ch = "people",
      body = L["Add alt in your member window lists your guild characters as you type. Alts share Guild OS status and inactivity."] },
    { id = "loot",     ill = "bank",     title = L["Loot & wishlist"], track = "member", ch = "people",
      body = { retail = L["Your wishlist tells the loot council what you want, in order."],
               default = L["Your wishlist tells the loot master what you want, in order."] } },
    { id = "crafts",   ill = "bank",     title = L["Crafts"], track = "member", ch = "people",
      body = L["Search who crafts; Request sends a craft order. Your recipes are shared automatically."] },
    { id = "map",      ill = "map",      title = L["Guild map"], track = "member", ch = "yours",
      body = { forever = L["Guildmates on the world map, alongside OpenMap, and the guild's campfires."],
               default = L["Guildmates on the world map, alongside OpenMap."] } },
    { id = "site",     ill = "shield",   title = L["The Companion & site"], track = "member", ch = "yours",
      body = L["guildos.me holds the calendar and rosters. The Companion app takes your data there after you log out."] },
    { id = "bar",      ill = "compact",  title = L["Compact bar"], track = "member", ch = "way",
      body = L["The fold button folds the window into a slim bar; click it to open it again."] },
    { id = "recruit",  ill = "officers", title = L["Recruiting"], officer = true, track = "officer", ch = "recruit",
      body = L["The ad, one-click posting, welcome messages, invites."] },
    { id = "moderate", ill = "officers", title = L["Moderation"], officer = true, track = "officer", ch = "mod",
      body = L["Chat alerts, the rule helper, bans that follow alts, the audit log."] },
}

function O:Guides(role, client)
    role = role or O.Role()
    client = client or O.ClientKey()
    local out = {}
    for _, g in ipairs(self.GUIDES) do
        if not g.officer or role ~= "member" then
            out[#out + 1] = { id = g.id, ill = g.ill, title = g.title, body = O.Text(g.body, client),
                              officer = g.officer, track = g.track, ch = g.ch }
        end
    end
    return out
end

function O:Guide(id)
    for _, g in ipairs(self:Guides()) do if g.id == id then return g end end
    return nil
end

-- Which tour chapter or guide fits the screen on show (Shift-click on "?"): { track, ch } or { guide }.
O.SCREEN_HELP = {
    ["salao"] = { track = "member", ch = "way" }, ["raids"] = { track = "member", ch = "raids" },
    ["members"] = { track = "member", ch = "people" }, ["loot"] = { guide = "loot" },
    ["workshop"] = { guide = "crafts" }, ["chronicle"] = { track = "member", ch = "people" },
    ["settings"] = { track = "member", ch = "yours" },
    ["raids/groups"] = { guide = "groups" }, ["raids/calendar"] = { guide = "signup" },
    ["raids/raidtools"] = { track = "officer", ch = "rlb" },
    ["workshop/cleanup"] = { track = "officer", ch = "rlb" }, ["workshop/ledger"] = { track = "officer", ch = "rlb" },
    ["officers"] = { track = "officer", ch = "recruit" },
}
local OFFICER_CH = { recruiting = "recruit", scanner = "recruit", trials = "recruit", engage = "recruit",
    suggest = "care", ranks = "care", inactive = "care", bulk = "care", presets = "care", remind = "care",
    marks = "records", audit = "records", former = "records",
    alerts = "mod", alertrules = "mod", ban = "mod", log = "mod", motd = "mod", alliance = "mod" }

function O:HelpFor(roomId, entryId, role)
    role = role or O.Role()
    local hit
    if roomId == "officers" and entryId and OFFICER_CH[entryId] then
        hit = { track = "officer", ch = OFFICER_CH[entryId] }
    else
        hit = self.SCREEN_HELP[tostring(roomId) .. "/" .. tostring(entryId)] or self.SCREEN_HELP[tostring(roomId)]
    end
    if hit and hit.track and not self:TrackAllowed(hit.track, role) then hit = { track = "member", ch = "way" } end
    return hit or { track = "member", ch = "way" }
end

----------------------------------------------------------------------
-- Getting started: the checklists. Every tick is a test on data Guild OS already has.
-- { id, title, desc, done, go = { room, entry, anchor, run }, sub = { { label, done } } }
----------------------------------------------------------------------
local function myKey()
    local name = GuildOS.Compat and GuildOS.Compat.PlayerName and GuildOS.Compat.PlayerName()
    if not name then return nil end
    return GuildOS:GetPlayerKey(name, GetRealmName and GetRealmName() or nil)
end
O.MyKey = myKey

local P = {}
O.PREDICATES = P

function P.roles()
    return next(GuildOS:GetMyRoles() or {}) ~= nil
end

-- Linked (as an alt, or as someone's main), or the account knows no other character in this guild.
function P.alts()
    local me = myKey()
    if not me then return false end
    local links = (GuildOS.db and GuildOS.db.altLinks) or {}
    if links[me] then return true end
    for _, main in pairs(links) do if main == me then return true end end
    local others = 0
    local guild = GetGuildInfo and GetGuildInfo("player")
    for key, info in pairs(type(GuildOSDB) == "table" and GuildOSDB.accountChars or {}) do
        if key ~= me and type(info) == "table" and (info.guild == nil or info.guild == guild) then others = others + 1 end
    end
    return others == 0
end

function P.signup()
    local Cal = GuildOS.Calendar
    if not (Cal and Cal.GetEvents and Cal.MyRsvp) then return false end
    for _, e in pairs(Cal:GetEvents() or {}) do
        if type(e) == "table" and Cal:MyRsvp(e) ~= nil then return true end
    end
    return false
end

function P.wish()
    local W = GuildOS.Wishlist
    local list = W and W.GetMyList and W:GetMyList()
    return type(list) == "table" and #list > 0
end

function P.comp()
    return type(GuildOSDB) == "table" and GuildOSDB.__companionAt ~= nil
end

function P.ad()
    local r = GuildOS.db and GuildOS.db.recruitment
    return type(r) == "table" and type(r.message) == "string" and r.message:gsub("%s", "") ~= ""
end

function P.welcome()
    local r = GuildOS.db and GuildOS.db.recruitment
    if type(r) ~= "table" then return false end
    for _, m in ipairs(type(r.welcomeMessages) == "table" and r.welcomeMessages or {}) do
        if type(m) == "string" and m:gsub("%s", "") ~= "" then return true end
    end
    return type(r.welcomeMessage) == "string" and r.welcomeMessage:gsub("%s", "") ~= ""
end

-- One saved filter for the rank changes, or "we promote by hand".
function P.ranks()
    local gs = GuildOS.db and GuildOS.db.settings and GuildOS.db.settings.gettingStarted
    if type(gs) == "table" and gs.byHand then return true end
    local MP = GuildOS.ModPresets
    local list = MP and MP.GetPresets and MP:GetPresets()
    return type(list) == "table" and #list > 0
end

function P.alerts()
    local MA = GuildOS.ModAlerts
    if not (MA and MA.IsCustomList and MA.GetRules) then return false end
    return MA:IsCustomList() and #(MA:GetRules() or {}) > 0
end

-- The site: WoW: Forever follows the activation (Modules/Activation.lua); elsewhere, the site answered.
function P.site()
    local act = GuildOS.Activation
    if act and act.Read then return act:Read(now()).activated and true or false end
    local CI = GuildOS.CompanionImport
    return (CI and CI.GuildBlock and CI:GuildBlock() ~= nil) and true or false
end

function P.offranks()
    local s = GuildOS.db and GuildOS.db.settings
    return type(s) == "table" and s.officerMaxRankAt ~= nil
end

function P.tax()
    local s = GuildOS.db and GuildOS.db.settings
    return type(s) == "table" and s.bankTaxAt ~= nil
end

local ACT_LABEL = {
    publish = L["Published"], bot = L["Discord bot"], account = L["Account"], members = L["5 members"], run = L["First run"],
}

local function siteSub()
    local act = GuildOS.Activation
    if not (act and act.Read and act.STEPS) then return nil end
    local r = act:Read(now())
    local sub = {}
    for _, id in ipairs(act.STEPS) do sub[#sub + 1] = { id = id, label = ACT_LABEL[id] or id, done = r.steps and r.steps[id] or false } end
    return sub, r
end

-- The list for `kind` ("member" or "officer"; the officer's grows the Guild Master's two when role is "gm").
function O:Checklist(kind, role)
    role = role or O.Role()
    local function item(id, title, desc, go, extra)
        local ok, done = pcall(P[id])
        local t = { id = id, title = title, desc = desc, done = ok and done and true or false, go = go }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    if kind == "member" then
        local out = {
            item("roles", L["Set your raid roles"], L["Done when you pick at least one role"],
                { room = "settings", entry = "profile", anchor = { "settings.roles", "entry.settings.profile" } }),
            item("alts", L["Link your alts"], L["Done when this account's characters are linked, or you have none in the guild"],
                { room = "members", entry = "roster", anchor = { "roster.search", "door.members" } }),
        }
        if GuildOS.Calendar then
            out[#out + 1] = item("signup", L["Sign up for the next raid"], L["Done on your first sign-up in the calendar"],
                { room = "raids", entry = "calendar", anchor = { "raids.signup", "entry.raids.calendar" } })
        end
        if GuildOS.Wishlist then
            out[#out + 1] = item("wish", L["Make your wishlist"], L["Done when the list has one item"],
                { room = "loot", entry = "lists", anchor = { "loot.wishlist", "entry.loot.lists" } })
        end
        out[#out + 1] = item("comp", L["Install the Companion"], L["Done when guildos.me has seen your data"],
            { room = "settings", entry = "web", anchor = { "web.site", "entry.settings.web" } })
        return out
    end
    local out = {}
    if role == "gm" then
        out[#out + 1] = item("offranks", L["Choose the officer ranks"], L["Guild Master: done once saved"],
            { room = "settings", entry = "rules", anchor = { "settings.officerRanks", "entry.settings.rules" } })
        if GuildOS.GuildBank and GuildOS.GuildBank.SetTax then
            out[#out + 1] = item("tax", L["Decide on the bank tax"], L["Guild Master: on, or deliberately off"],
                { room = "settings", entry = "rules", anchor = { "settings.bankTax", "entry.settings.rules" } })
        end
    end
    out[#out + 1] = item("ad", L["Write the recruitment ad"], L["Done when the ad has text"],
        { room = "officers", entry = "recruiting", anchor = { "recruit.ad", "recruit.post", "side.recruiting" } })
    out[#out + 1] = item("welcome", L["Add a welcome message"], L["Done with one message or more"],
        { room = "officers", entry = "recruiting", anchor = { "recruit.welcome", "side.recruiting" } })
    out[#out + 1] = item("ranks", L["Set the rank rules"], L["Done with one saved preset, or \"we promote by hand\""],
        { room = "officers", entry = "presets", anchor = { "side.presets", "side.ranks" } }, { byHand = true })
    out[#out + 1] = item("alerts", L["Set your alert rules"], L["Done when the officers saved a list with one rule"],
        { room = "officers", entry = "alertrules", anchor = { "side.alertrules" } })
    local sub = siteSub()
    out[#out + 1] = item("site", L["Link the guild to guildos.me"],
        sub and L["Follows the activation: published, bot, account, 5 members, first run"] or L["Done when the site answers"],
        { room = "settings", entry = "web", anchor = { "web.link", "entry.settings.web" } }, { sub = sub })
    return out
end

function O.DoneCount(list)
    local n = 0
    for _, it in ipairs(list) do if it.done then n = n + 1 end end
    return n
end

-- "We promote by hand": the ranks item counted done.
function O:PromoteByHand()
    local s = GuildOS.db and GuildOS.db.settings
    if not s then return end
    s.gettingStarted = type(s.gettingStarted) == "table" and s.gettingStarted or {}
    s.gettingStarted.byHand = true
end

----------------------------------------------------------------------
-- Getting started: where it shows.
-- Officers: a card at the top of the Hall, while not hidden and not done for a day; on WoW: Forever it is the
-- activation card's place too. Members: a line in For you, and the full list in Settings › Help.
----------------------------------------------------------------------
local function gsStore()
    local s = GuildOS.db and GuildOS.db.settings
    if not s then return nil end
    s.gettingStarted = type(s.gettingStarted) == "table" and s.gettingStarted or {}
    return s.gettingStarted
end
O.GuildStore = gsStore

local function charStore()
    local key = myKey()
    if not key then return nil end
    local s = O:Store()
    s.chars[key] = type(s.chars[key]) == "table" and s.chars[key] or {}
    s.chars[key].gs = type(s.chars[key].gs) == "table" and s.chars[key].gs or {}
    return s.chars[key].gs
end
O.CharStore = charStore

-- What the officers' card reads: { items, done, total, all } or nil while it does not show. Records the day it
-- was all done, and says once that the guild is set up (`celebrate`).
function O:OfficerCard(t)
    t = t or now()
    if O.Role() == "member" then return nil end
    local gs = gsStore()
    if not gs then return nil end
    if gs.hidden and t < gs.hidden + self.HIDE_S then return nil end
    local items = self:Checklist("officer")
    local done = O.DoneCount(items)
    local all = done == #items
    local celebrate = false
    if all then
        if not gs.doneAt then gs.doneAt = t end
        if not gs.celebrated then gs.celebrated, celebrate = true, true end
        if t >= gs.doneAt + self.STAY_S then return nil end
    else
        gs.doneAt = nil
    end
    return { items = items, done = done, total = #items, all = all, celebrate = celebrate }
end

function O:HideOfficerCard(t)
    local gs = gsStore()
    if gs then gs.hidden = t or now() end
    -- The activation's own reminder in the digest goes quiet for as long.
    local act = GuildOS.Activation
    if act and act.Hide and GuildOS.db and GuildOS.db.activation then act:Hide(t or now()) end
end

-- The members' line in For you: { done, total } while some are left and the character did not hide it.
function O:MemberLine(t)
    t = t or now()
    if O.Role() ~= "member" then return nil end
    local cs = charStore()
    if cs and cs.hidden and t < cs.hidden + self.HIDE_S then return nil end
    local items = self:Checklist("member")
    local done = O.DoneCount(items)
    if done >= #items then return nil end
    return { done = done, total = #items }
end

function O:HideMemberList(t)
    local cs = charStore()
    if cs then cs.hidden = t or now() end
end

----------------------------------------------------------------------
-- The search's index (Modules/Search.lua): the tours and the guides, by their names and these words.
----------------------------------------------------------------------
function O:SearchEntries(role)
    role = role or O.Role()
    local out = {}
    local words = L["tour, tutorial, help, guide, walkthrough, onboarding, tips, how to"]
    for _, id in ipairs(self:TracksFor(role)) do
        out[#out + 1] = { name = self.TRACKS[id].label, words = words, track = id }
    end
    out[#out + 1] = { name = string.format(L["What's new in %s"], self:Version()), words = L["what's new, news, changes, version, update"], whatsnew = true }
    for _, g in ipairs(self:Guides(role)) do
        out[#out + 1] = { name = g.title, words = L["guide, help"], guide = g.id }
    end
    return out
end

----------------------------------------------------------------------
-- /gos tour [member | officer | gm], /gos whatsnew
----------------------------------------------------------------------
function O:Command(verb, arg)
    if verb == "whatsnew" then
        if GuildOS.ShowWhatsNew then GuildOS:ShowWhatsNew(true) end
        return true
    end
    if verb == "tour" then
        local track = (arg and arg ~= "") and arg or "member"
        if track == "officers" then track = "officer" end
        if not self.TRACKS[track] then
            GuildOS:Print(L["Tours: member, officer, gm."])
            return false
        end
        if not self:TrackAllowed(track) then
            GuildOS:Print(L["That tour is not for your rank."])
            return false
        end
        local Tour = GuildOS.UI and GuildOS.UI.Tour
        if Tour then return Tour:Start(track) end
        return false
    end
    return false
end
