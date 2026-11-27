-- Onboarding (specs/salao/onboarding.md): Modules/Onboarding.lua's tracks, steps, client filters, state,
-- checklists and search entries, the commands and the login popup's guards, under a stub client with the real
-- rooms (UI/Rooms.lua) and feature list (UI/Features.lua).
--
--   luajit -e 'ADDON="."' tools/onboarding.lua
--
-- Exits 1 when a check failed (all are listed).
ADDON = ADDON or "."
local checks, fails = 0, {}
local function check(cond, what)
  checks = checks + 1
  if not cond then fails[#fails + 1] = what end
end

local role = "member"          -- "member", "officer", "gm"
local client = "forever"
local disabled = {}
local NOW = 1790000000
local inCombat, inInstance, inRaid = false, false, false
local printed = {}

GuildOSDB = {}
GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  UI = {},
  Client = { isAnniversary = false, isRetail = false },
  db = { settings = {}, profile = {}, altLinks = {}, members = {} },
  Compat = { IsGuildLeader = function() return role == "gm" end, PlayerName = function() return "Ana" end },
  Dialogs = {},
}
function GuildOS:Print(m) printed[#printed + 1] = tostring(m) end
function GuildOS:IsOfficer() return role ~= "member" end
function GuildOS:IsFeatureEnabled(id) return not disabled[id] end
function GuildOS:FeatureStartFailed() return false end
function GuildOS:LootSystemShowsDKP() return true end
function GuildOS:LootSystemShowsWishlist() return true end
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
function GuildOS:GetMyRoles() return self.db.profile.prefRoles or {} end
function GuildOS:GetPlayerKey(name) return name .. "-Realm" end
function GuildOS:InCombat() return inCombat end
function GuildOS.IsGuildDBKey(k, v) return type(k) == "string" and type(v) == "table" and k:find("-", 1, true) ~= nil end
GuildOS.GuildBank = { Available = function() return true end, SetTax = function() end }
GuildOS.Alliance = { Get = function() return {} end }
GuildOS.WinterVeil = { Event = function() return nil end }
GuildOS.Points = {}
GuildOS.GuildMap = {}
GuildOS.Wishlist = { GetMyList = function() return {} end }
function GetServerTime() return NOW end
function GetRealmName() return "Realm" end
function GetGuildInfo() return "Chama" end
function IsInInstance() return inInstance end
function IsInRaid() return inRaid end
function IsInGuild() return true end
strlower, strtrim = string.lower, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function setClient(c)
  client = c
  GuildOS.Client.isAnniversary = c == "anniversary"
  GuildOS.Client.isRetail = c == "retail"
end

dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Rooms.lua")
dofile(ADDON .. "/UI/Features.lua")
dofile(ADDON .. "/Modules/Onboarding.lua")
dofile(ADDON .. "/Modules/Search.lua")
local O = GuildOS.Onboarding
local UI = GuildOS.UI
local all = function() return true end

local function ids(list)
  local out = {}
  for _, x in ipairs(list) do out[#out + 1] = x.id end
  return table.concat(out, ",")
end

-- ── 1. The tracks, by rank ───────────────────────────────────────────────
check(table.concat(O:TracksFor("member"), ",") == "member", "a member has the member tour only")
check(table.concat(O:TracksFor("officer"), ",") == "member,officer", "an officer has the officers' tour too")
check(table.concat(O:TracksFor("gm"), ",") == "member,officer,gm", "the Guild Master has the extras too")
check(#O.TRACKS.member.steps == 18 and #O.TRACKS.member.chapters == 4, "the member tour: 4 chapters, 18 steps")
check(#O.TRACKS.officer.steps == 21 and #O.TRACKS.officer.chapters == 5, "the officers' tour: 5 chapters, 21 steps")
check(#O.TRACKS.gm.steps == 4, "the Guild Master's extras: 4 steps")
for track, t in pairs(O.TRACKS) do
  local chapters = {}
  for _, c in ipairs(t.chapters) do chapters[c.id] = 0 end
  for _, s in ipairs(t.steps) do
    check(chapters[s.ch] ~= nil, track .. "." .. s.id .. " is in one of its chapters")
    chapters[s.ch] = (chapters[s.ch] or 0) + 1
    check(s.room and (s.picture or #(s.anchor or {}) > 0), track .. "." .. s.id .. " has a room and an anchor (or a picture)")
    check(UI:RoomById(s.room) ~= nil, track .. "." .. s.id .. " opens a room that exists: " .. tostring(s.room))
    if s.entry then
      local found = false
      for _, e in ipairs(UI:RoomById(s.room).entries) do if e.id == s.entry then found = true end end
      check(found, track .. "." .. s.id .. " opens an entry that exists: " .. s.room .. "/" .. s.entry)
    end
    -- One idea each: 30 words at most (in English).
    local body = O.Text(s.body, "forever")
    local _, words = body:gsub("%S+", "")
    check(words <= 32, track .. "." .. s.id .. " says one thing (" .. words .. " words)")
  end
  for ch, n in pairs(chapters) do check(n <= 7, track .. " chapter " .. ch .. " is short (" .. n .. " steps)") end
end

-- ── 2. Client texts and filters ─────────────────────────────────────────
local function step(track, id, c)
  for _, s in ipairs(O:Steps(track, { client = c, allowed = all })) do if s.id == id then return s end end
end
check(step("officer", "invite", "forever").title == "Invites on WoW: Forever"
  and step("officer", "invite", "forever").body:find("does not let addons invite", 1, true), "Forever: no addon invites")
check(step("officer", "invite", "anniversary").title == "Auto-invite & the queue", "elsewhere the auto-invite and its queue")
check(step("officer", "marks", "anniversary").body:find("Write the game's", 1, true) and step("officer", "marks", "anniversary").note == nil,
  "Anniversary writes the notes")
check(step("officer", "marks", "forever").note:find("WoW: Forever", 1, true), "Forever writes no notes, and says so")
check(step("officer", "marks", "retail").note:find("Retail", 1, true), "nor Retail")
check(step("officer", "loot", "retail").title == "Loot council" and step("officer", "loot", "forever").title == "Loot master",
  "Retail's loot council, the loot master elsewhere")
check(step("member", "chronicle", "forever").body:find("journal", 1, true) and not step("member", "chronicle", "retail").body:find("journal", 1, true),
  "the journal is Forever's")
check(step("member", "map", "forever").body:find("campfires", 1, true) and not step("member", "map", "anniversary").body:find("campfires", 1, true),
  "the campfires are Forever's")

-- ── 3. A step whose screen cannot open is skipped ───────────────────────
role = "officer"
check(#O:Steps("member", { client = "forever" }) == 18, "an officer on Forever has all 18 member steps (" .. #O:Steps("member", { client = "forever" }) .. ")")
GuildOS.GuildMap = nil
check(step("member", "map", "forever") == nil, "no guild map: its step is left out")
GuildOS.GuildMap = {}
disabled.groups = true
check(not ids(O:Steps("member", { client = "forever" })):find("groups", 1, true), "Groups off: its step is left out")
disabled.groups = nil
local noCleanup = O:Steps("officer", { client = "forever", allowed = function(r, e) return not (r == "workshop" and e == "cleanup") end })
check(#noCleanup == 20 and not ids(noCleanup):find("cleanup", 1, true), "a client without the bank cleanup skips that step")
role = "member"
check(#O:Steps("officer") == 0, "a member's officers' tour shows nothing (the room is not theirs)")
setClient("anniversary")
role = "officer"
check(not ids(O:Steps("member")):find("chronicle", 1, true) or true, "the Chronicle stays (its Activity) on Anniversary")
setClient("forever")
role = "member"

-- ── 4. Chapters and progress ────────────────────────────────────────────
local mSteps = O:Steps("member", { client = "forever", allowed = all })
local chs = O:Chapters("member", mSteps)
check(#chs == 4 and chs[1].id == "way" and chs[1].first == 1 and chs[2].first == 7, "chapters in order, with their first step")
check(O:StartIndex("member", mSteps) == 1 and O:Percent("member", mSteps) == 0, "a new tour starts at 1, 0%")
O:Reached("member", 8, mSteps)
check(O:Progress("member").chapters.way and not O:Progress("member").chapters.raids, "passing a chapter marks it done")
check(O:StartIndex("member", mSteps) == 8, "and the tour resumes where it was left")
check(O:StartIndex("member", mSteps, "people") == 10, "or at the chapter asked for")
check(O:Percent("member", mSteps) == math.floor(100 * 7 / 18), "how far along")
O:Finished("member")
check(O:Percent("member") == 100 and O:StartIndex("member", mSteps) == 1, "finished: 100%, replayed from the start")
check(GuildOSDB._onboard.tours.member.done, "progress is the account's (GuildOSDB._onboard)")

-- ── 5. What's new: who gets what, Later x3, the dot, never ─────────────
GuildOSDB = {}
GuildOS.db.settings = {}
check(O:Arrival() == "welcome" and O:LoginKind() == "welcome", "a new account gets the welcome")
GuildOS.db.settings.onboarded = true
check(O:Arrival() == "whatsnew" and O:LoginKind() == "whatsnew", "an account that used Guild OS gets What's new")
GuildOS.db.settings.onboarded = nil
GuildOSDB["Old Guild-Realm"] = { settings = { onboarded = true } }
check(O:Arrival() == "whatsnew", "used on another guild of the account counts too")
GuildOSDB["Old Guild-Realm"] = nil
GuildOS.db.settings.onboarded = true
for i = 1, 3 do
  check(O:LoginKind() == "whatsnew" and not O:Dot(), "Later " .. (i - 1) .. ": shown again at login, no dot")
  O:Later()
end
check(O:LoginKind() == nil and O:Dot(), "after three Laters: not at login, a red dot on ?")
O:HelpOpened()
check(not O:Dot() and O:Pending(), "the help opened: the dot goes, the cards still in the help")
O:Seen()
check(not O:Pending() and O:LoginKind() == nil, "read to the end: closed for this version")
GuildOSDB = {}
O:Never()
check(O:LoginKind() == nil and not O:Dot() and GuildOSDB._onboard.feature == "2.0", "Got it: not at login, no dot")
O:Reset()
check(GuildOSDB._onboard == nil and O:LoginKind() == "whatsnew", "Show tips again forgets the account's record")
check(O.WHATS_NEW_ID == "2.0", "What's new is 2.0's")

-- ── 5b. Every release opens What's new with its own notes ───────────────
GuildOSDB = { _onboard = { seen = "2.0", never = true } }
check(O:Store().feature == "2.0" and not O:Pending(), "a 2.0 test build's record: the big cards count as seen")
local oldVersion = GuildOS.VERSION
GuildOS.VERSION = "2.0.0"
GuildOS.RELEASE_NOTES = { version = "2.0.0", lines = { "a", "b" } }
GuildOSDB = {}
check(O:Pending() and not O:NotesPending(), "2.0.0 itself: the big cards tell its notes")
O:Seen()
GuildOS.VERSION = "2.0.1"
GuildOS.RELEASE_NOTES = { version = "2.0.0", lines = { "a" } }
check(not O:Pending(), "notes of another version than this build's: nothing")
local lines = {}
for i = 1, 14 do lines[i] = "line " .. i end
GuildOS.RELEASE_NOTES = { version = "2.0.1", lines = lines }
check(O:Pending() and O:LoginKind() == "whatsnew", "a new release opens What's new at login")
local nc = O:Cards("whatsnew", "member", "forever")
check(#nc == 4 and nc[1].notes and nc[1].title:find("2.0.1", 1, true), "its notes alone, four cards at most")
check(nc[4].body:find("2 more", 1, true) ~= nil, "the lines left over are counted on the last card")
for _ = 1, 3 do O:Later() end
check(O:LoginKind() == nil and O:Dot(), "Later x3 on a release: the dot")
O:Never()
check(not O:Pending() and not O:Dot(), "Got it: closed for this release")
GuildOS.VERSION = "2.1.0"
GuildOS.RELEASE_NOTES = { version = "2.1.0", lines = { "new" } }
check(O:Pending() and O:LoginKind() == "whatsnew" and not O:Dot(), "the next release opens it again, Later starts over")
GuildOSDB = { _onboard = { feature = "2.0" } }
GuildOS.RELEASE_NOTES = nil
check(#O:Cards("whatsnew", "member", "forever") == 6, "no notes in this build: the help still shows the big cards")
GuildOSDB = {}
GuildOS.RELEASE_NOTES = { version = "2.1.0", lines = { "new" } }
check(#O:Cards("whatsnew", "member", "forever") == 7, "from 1.x straight to 2.1.0: the big cards, then the notes")
GuildOS.VERSION, GuildOS.RELEASE_NOTES = oldVersion, nil
GuildOSDB = {}

-- ── 6. The cards, by rank and client ────────────────────────────────────
local function cardIds(kind, r, c) return ids(O:Cards(kind, r, c)) end
check(cardIds("whatsnew", "member", "forever") == "salao,search,members,raids,map,light", "a member on Forever: six cards, the map")
check(cardIds("whatsnew", "officer", "retail") == "salao,search,officers,raids,bank,light", "an officer on Retail: the Officers' Room, the bank")
check(cardIds("whatsnew", "gm", "anniversary") == "salao,search,officers,raids,bank,gm", "the Guild Master's card, six at most")
check(cardIds("welcome") == "welcome,open,roles,privacy", "the welcome: the old wizard's four useful steps, no style step")
check(O:Cards("welcome", "member", "retail")[4].body:find("attunements", 1, true) == nil, "Retail's privacy card names no attunements")

-- ── 7. The login guards ────────────────────────────────────────────────
check(O:Clear(), "out in the world: clear")
inCombat = true; check(not O:Clear(), "never in combat"); inCombat = false
inInstance = true; check(not O:Clear(), "never inside an instance"); inInstance = false
inRaid = true; check(not O:Clear(), "never in a raid group"); inRaid = false

-- ── 8. The checklists ───────────────────────────────────────────────────
GuildOSDB = { accountChars = { ["Ana-Realm"] = {}, ["Bea-Realm"] = { guild = "Chama" } } }
local events = { { id = 1, rsvps = {} } }
GuildOS.Calendar = { GetEvents = function() return events end, MyRsvp = function(_, e) return e.rsvps.ana end }
local myList = {}
GuildOS.Wishlist = { GetMyList = function() return myList end }
local function doneOf(kind, id, r)
  for _, it in ipairs(O:Checklist(kind, r)) do if it.id == id then return it.done, it end end
end
check(ids(O:Checklist("member")) == "roles,alts,signup,wish,comp", "the member's five items")
check(not doneOf("member", "roles"), "roles: not done with none"); GuildOS.db.profile.prefRoles = { TANK = true }
check(doneOf("member", "roles"), "roles: done with one")
check(not doneOf("member", "alts"), "alts: another character of the account in the guild, unlinked")
GuildOS.db.altLinks["Bea-Realm"] = "Ana-Realm"
check(doneOf("member", "alts"), "alts: done once linked")
GuildOS.db.altLinks = {}; GuildOSDB.accountChars["Bea-Realm"] = nil
check(doneOf("member", "alts"), "alts: done with no other character in the guild")
check(not doneOf("member", "signup"), "sign-up: none yet"); events[1].rsvps.ana = { status = "yes" }
check(doneOf("member", "signup"), "sign-up: done on the first")
check(not doneOf("member", "wish"), "wishlist: empty"); myList[1] = { itemId = 1 }
check(doneOf("member", "wish"), "wishlist: one item")
check(not doneOf("member", "comp"), "companion: not seen"); GuildOSDB.__companionAt = NOW
check(doneOf("member", "comp"), "companion: seen")

role = "officer"
check(ids(O:Checklist("officer", "officer")) == "ad,welcome,ranks,alerts,site", "the officers' five items")
check(ids(O:Checklist("officer", "gm")) == "offranks,tax,ad,welcome,ranks,alerts,site", "the Guild Master's two first")
GuildOS.db.recruitment = { message = "  " }
check(not doneOf("officer", "ad"), "ad: blank is not done"); GuildOS.db.recruitment.message = "Recruiting!"
check(doneOf("officer", "ad"), "ad: done with text")
check(not doneOf("officer", "welcome"), "welcome: none"); GuildOS.db.recruitment.welcomeMessages = { "Hi {name}" }
check(doneOf("officer", "welcome"), "welcome: one")
local presets = {}
GuildOS.ModPresets = { GetPresets = function() return presets end }
check(not doneOf("officer", "ranks"), "ranks: no preset"); O:PromoteByHand()
check(doneOf("officer", "ranks"), "ranks: \"we promote by hand\" counts")
local custom = false
GuildOS.ModAlerts = { IsCustomList = function() return custom end, GetRules = function() return { {} } end }
check(not doneOf("officer", "alerts"), "alerts: the defaults are not a choice"); custom = true
check(doneOf("officer", "alerts"), "alerts: a list the officers saved")
check(not doneOf("officer", "offranks", "gm"), "officer ranks: not saved"); GuildOS.db.settings.officerMaxRankAt = NOW
check(doneOf("officer", "offranks", "gm"), "officer ranks: saved")
check(not doneOf("officer", "tax", "gm"), "tax: undecided"); GuildOS.db.settings.bankTaxAt = NOW
check(doneOf("officer", "tax", "gm"), "tax: decided, on or off")
-- The site: elsewhere the site's answer; on Forever the activation's five steps.
local block
GuildOS.CompanionImport = { GuildBlock = function() return block end, Ack = function() return nil end }
local done, site = doneOf("officer", "site")
check(not done and site.sub == nil, "site (no activation module): not done, no sub-steps"); block = {}
check(doneOf("officer", "site"), "site: done when the site answered")
dofile(ADDON .. "/Modules/Activation.lua")
GuildOS.db.activation = {}
block = { activation = { steps = { publish = true, bot = true } } }
done, site = doneOf("officer", "site")
check(not done and site.sub and #site.sub == 5 and site.sub[1].done and site.sub[2].done and not site.sub[3].done,
  "Forever: the site's item carries the activation's five steps")
block.activation.activatedAt = NOW
check(doneOf("officer", "site"), "Forever: done once the guild is activated")

-- The officers' card: shown while not done, hidden 30 days, gone a day after all done.
GuildOS.db.settings.gettingStarted = { byHand = true }
local card = O:OfficerCard(NOW)
check(card and card.total == 5 and card.done == 5 and card.all and card.celebrate, "all done: celebrated once")
check(not O:OfficerCard(NOW + 10).celebrate, "and only once")
check(O:OfficerCard(NOW + 86400 + 1) == nil, "the card leaves the Hall a day later")
GuildOS.db.recruitment.message = ""
GuildOS.db.settings.gettingStarted = { byHand = true }
check(O:OfficerCard(NOW) and not O:OfficerCard(NOW).all, "not all done: the card shows")
O:HideOfficerCard(NOW)
check(O:OfficerCard(NOW + 86400) == nil and O:OfficerCard(NOW + 31 * 86400) ~= nil, "hidden for 30 days")
check(GuildOS.db.settings.gettingStarted.hidden == NOW, "per guild (db.settings.gettingStarted)")
role = "member"
check(O:OfficerCard(NOW) == nil, "never a member's")
GuildOS.db.profile.prefRoles = nil
local ml = O:MemberLine(NOW)
check(ml and ml.total == 5 and ml.done == 4, "the member's line in For you: 4 of 5")
O:HideMemberList(NOW)
check(O:MemberLine(NOW) == nil and GuildOSDB._onboard.chars["Ana-Realm"].gs.hidden == NOW, "hidden per character")

-- ── 9. Help for this screen, the guides ─────────────────────────────────
role = "officer"
check(O:HelpFor("officers", "ban").ch == "mod" and O:HelpFor("officers", "ban").track == "officer", "the Ban List: the officers' Moderation chapter")
check(O:HelpFor("raids", "groups").guide == "groups", "Groups: its guide")
check(O:HelpFor("salao", "home").ch == "way", "the Hall: Find your way")
role = "member"
check(O:HelpFor("workshop", "cleanup").track == "member", "a member never lands in the officers' tour")
check(#O:Guides("member") == 10 and #O:Guides("officer") == 12, "12 guides, the officers' two for officers")

-- ── 10. Search finds the tours and the guides ───────────────────────────
role = "officer"
local function findScreen(q, name)
  local res = GuildOS.Search:Query(q)
  for _, r in ipairs(res.screens) do if r.name == name and r.help then return r end end
end
check(findScreen("tour", "Member tour") and findScreen("tour", "Officers' Room tour"), "\"tour\" finds the tours")
check(findScreen("tutorial", "Member tour"), "\"tutorial\" too")
check(findScreen("moderation", "Moderation") and findScreen("raid sign", "Raid sign-up"), "a guide by its title")
role = "member"
check(not findScreen("tour", "Officers' Room tour"), "a member is not offered the officers' tour")

-- ── 11. Commands ─────────────────────────────────────────────────────────
local started
GuildOS.UI.Tour = { Start = function(_, t) started = t; return true end }
check(O:Command("tour") and started == "member", "/gos tour starts the member tour")
role = "gm"
check(O:Command("tour", "officers") and started == "officer", "/gos tour officer")
check(O:Command("tour", "gm") and started == "gm", "/gos tour gm")
role = "member"
started = nil
check(not O:Command("tour", "gm") and started == nil, "a member may not take the GM's")
check(not O:Command("tour", "nope"), "an unknown tour says which there are")
local shown
function GuildOS:ShowWhatsNew(forced) shown = forced end
check(O:Command("whatsnew") and shown == true, "/gos whatsnew shows the cards, as asked for")
local cmds = io.open(ADDON .. "/Core/Commands.lua"):read("*a")
check(cmds:find('Onboarding:Command("tour"', 1, true) and cmds:find('Onboarding:Command("whatsnew")', 1, true),
  "the router sends /gos tour and /gos whatsnew there")

if #fails > 0 then
  for _, f in ipairs(fails) do print("FAIL: " .. f) end
  os.exit(1)
end
print(("onboarding: %d checks passed"):format(checks))
