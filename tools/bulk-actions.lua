-- Bulk actions by rules, one member per click (issue #420), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/GuildManager.lua, Modules/RosterLog.lua and
-- Modules/BulkActions.lua under a stubbed client.
--
-- The rules pick who they say and never oneself, a higher rank, a promotion to one's own rank or a
-- demotion below the last; a removal starts only confirmed; a click arms one line, the game's own
-- /gpromote, /gdemote or /gremove, never the protected call; who left or changed rank is skipped; what
-- the roster then shows goes to the Roster Log once, beside the game's own message; WoW: Forever, or a
-- click the game blocked, prints the line to type.
--
--   luajit -e 'ADDON="."' tools/bulk-actions.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── The client the files need while they load ───────────────────────────
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
local function said(text)
  for _, line in ipairs(printed) do
    if tostring(line):find(text, 1, true) then return true end
  end
  return false
end
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) self.onEvent = fn end
  return f
end
function hooksecurefunc() end
WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
function GetBuildInfo() return "2.5.5", "65000", "", 20505 end
function GetRealmName() return "Dreamscythe" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local NOW, CLOCK = 1790000000, 1000
function GetServerTime() return NOW end
function GetTime() return CLOCK end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local rosterAsked = 0
function GuildRoster() rosterAsked = rosterAsked + 1 end
local combat = false
function InCombatLockdown() return combat end
Enum = { SendAddonMessageResult = {} }
-- The protected calls: an addon that calls them is refused by the game. Here, they fail the test.
function GuildPromote() error("GuildPromote called") end
function GuildDemote() error("GuildDemote called") end
function GuildUninvite() error("GuildUninvite called") end

-- The guild: ranks 0 (GM) .. 4, this character an officer at rank 1.
local RANKS = { "Guild Master", "Officer", "Veteran", "Member", "Initiate" }
function GuildControlGetNumRanks() return #RANKS end
function GuildControlGetRankName(i) return RANKS[i] end
function IsInGuild() return true end
local myRank = 1
function GetGuildInfo() return "Os Guardioes", RANKS[myRank + 1], myRank end
local can = { promote = true, demote = true, remove = true }
function CanGuildPromote() return can.promote end
function CanGuildDemote() return can.demote end
function CanGuildRemove() return can.remove end

-- { name, rankIndex, level, online, daysOffline }
local roster
local function setRoster(list) roster = list end
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i)
  local m = roster[i]
  if not m then return nil end
  return m[1], RANKS[m[2] + 1], m[2], m[3], nil, nil, nil, nil, m[4], nil, "WARRIOR"
end
function GetGuildRosterLastOnline(i)
  local m = roster[i]
  if not m or m[4] then return nil end
  return 0, 0, m[5] or 0, 0
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/GuildManager.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
dofile(ADDON .. "/Modules/BulkActions.lua")

GuildOS.Compat.PlayerName = function() return "Arthas" end
GuildOS.db = { settings = {}, members = {}, rosterLog = { events = {} } }
local BA, Compat = GuildOS.BulkActions, GuildOS.Compat
BA:Initialize()
local key = function(n) return GuildOS:GetPlayerKey(n) end

-- ── The line the game runs ──────────────────────────────────────────────
check(Compat.GuildRankCommand("promote", "Bob") == "/gpromote Bob", "a promotion is the game's /gpromote")
check(Compat.GuildRankCommand("remove", "Bob-Dreamscythe") == "/gremove Bob", "off retail the realm is left out")
SLASH_GUILD_DEMOTE1 = "/gdegradar"
check(Compat.GuildRankCommand("demote", "Bob") == "/gdegradar Bob", "the client's own spelling of the command")
check(Compat.GuildRankCommand("promote", "Bob\n/gquit") == nil and Compat.GuildRankCommand("promote", "a b") == nil,
      "a name that could carry a second command writes no line")
check(Compat.GuildRankCommand("invite", "Bob") == nil, "an unknown action writes no line")

-- ── The rules (pure) ────────────────────────────────────────────────────
local r = BA.Rules({ days = "30", rank = -1, levelMin = "", attMax = "150", noAddon = false })
check(r.days == 30 and r.rank == nil and r.levelMin == nil and r.attMax == nil and r.noAddon == nil,
      "empty, out of range and 'any' rules are no rules")
check(not BA.HasRule(BA.Rules({})) and BA.HasRule(BA.Rules({ rank = 3 })), "a rank alone is a rule; nothing is none")

local ctx = { myRank = 1, lowestRank = 4, meKey = "me" }
check(not BA.Eligible({ key = "me", rankIndex = 3 }, "remove", ctx), "never oneself")
check(not BA.Eligible({ key = "x", rankIndex = 1 }, "remove", ctx) and not BA.Eligible({ key = "x", rankIndex = 0 }, "demote", ctx),
      "never someone at or above one's own rank")
check(not BA.Eligible({ key = "x", rankIndex = 2 }, "promote", ctx) and BA.Eligible({ key = "x", rankIndex = 3 }, "promote", ctx),
      "a promotion never up to one's own rank")
check(not BA.Eligible({ key = "x", rankIndex = 4 }, "demote", ctx) and BA.Eligible({ key = "x", rankIndex = 3 }, "demote", ctx),
      "a demotion never below the lowest rank")

local members = {
  { key = "a", name = "Ana", rankIndex = 4, level = 60, daysOffline = 40, hasAddon = false },
  { key = "b", name = "Bia", rankIndex = 4, level = 20, daysOffline = 90, hasAddon = true, attendance = 10 },
  { key = "c", name = "Caio", rankIndex = 3, level = 60, daysOffline = nil, hasAddon = false, attendance = 95 },
  { key = "d", name = "Duda", rankIndex = 4, level = 60, daysOffline = 31, hasAddon = false },
}
local out, why = BA.Match(members, BA.Rules({}), "remove", ctx)
check(#out == 0 and why == "rule", "no rule picks nobody")
out = BA.Match(members, BA.Rules({ days = 30 }), "remove", ctx)
check(#out == 3 and out[1].name == "Bia" and out[2].name == "Ana" and out[3].name == "Duda",
      "offline 30+ days, longest offline first; an online member is never offline")
out = BA.Match(members, BA.Rules({ days = 30, levelMin = 50, noAddon = true }), "remove", ctx)
check(#out == 2 and out[1].name == "Ana", "the level and the GuildOS rules narrow it")
out = BA.Match(members, BA.Rules({ attMax = 50 }), "remove", ctx)
check(#out == 1 and out[1].name == "Bia", "an unknown attendance meets no attendance rule")
out = BA.Match(members, BA.Rules({ rank = 3, attMin = 90 }), "promote", ctx)
check(#out == 1 and out[1].name == "Caio", "the current rank and attendance pick the promotion")

-- ── The live roster ─────────────────────────────────────────────────────
setRoster({
  { "Arthas", 1, 60, true },
  { "Bob", 4, 60, false, 60 },
  { "Cid", 3, 60, false, 45 },
  { "Dan", 4, 30, true },
  { "Eve", 2, 60, false, 100 },
})
GuildOS.db.members[key("Cid")] = { lastUpdate = 5 }
local list = BA:Preview({ days = 30 }, "demote")
check(#list == 2 and list[1].name == "Eve" and list[2].name == "Cid", "demote: rank 4 is the lowest, Bob is passed over")
can.demote = false
local _, w = BA:Preview({ days = 30 }, "demote")
check(w == "permission", "without the rank's right nothing is previewed")
can.demote = true
list = BA:Preview({ days = 30, noAddon = true }, "remove")
check(#list == 2 and list[1].name == "Eve" and list[2].name == "Bob", "without GuildOS: Cid's client was heard")

local ok, sw = BA:Start({ days = 30 }, "remove")
check(not ok and sw == "confirm" and BA:Queue() == nil, "a removal starts only confirmed")
ok, sw = BA:Start({}, "promote")
check(not ok and sw == "rule", "no rule starts nothing")
combat = true
ok, sw = BA:Start({ days = 30 }, "promote", true)
check(not ok and sw == "combat", "nothing starts in combat")
combat = false

-- ── One click, one member ───────────────────────────────────────────────
ok = BA:Start({ days = 30 }, "promote")
local q = BA:Queue()
check(ok and q and #q.items == 2 and q.items[1].name == "Bob" and q.items[2].name == "Cid",
      "promote: Bob (rank 4) and Cid (rank 3); Eve at rank 2 would reach the officer's own rank")
check(BA:NextLabel() == "Promote Bob", "the button names the action and the member")
check(BA:Arm(true) == nil and BA:Queue().items[1].status == "pending", "the press does nothing on this client: the release acts")
local line = BA:Arm(false)
check(line == "/gpromote Bob", "the click arms the game's line for Bob only")
BA:AfterClick(false)
check(q.items[1].status == "sent" and q.pos == 2, "the click sent it and goes on to Cid")
check(said("Sent /gpromote Bob. Next: Cid."), "the chat says what was sent and who is next")
check(#timers == 2, "the timers only ask for the roster and look at it, never another action")
for _, fn in ipairs(timers) do fn() end
timers = {}
check(rosterAsked == 1 and q.items[1].status == "sent", "the roster is asked for; too soon to call it unconfirmed")

-- The roster shows Bob promoted; the game's own guild message logged it a second before.
GuildOS.RosterLog._ready = true
GuildOS.RosterLog:Add({ action = "promote", target = "Bob", author = "Arthas", detail = "Member", timestamp = NOW })
roster[2][2] = 3
NOW = NOW + 3
BA:Confirm()
local events = GuildOS.db.rosterLog.events
check(q.items[1].status == "done" and #events == 1, "Bob is done, and logged once beside the game's message")

-- Cid changed rank meanwhile: skipped.
roster[3][2] = 2
check(BA:Arm(false) == nil and q.items[2].status == "skipped" and q.items[2].why == "rank",
      "a member whose rank moved since the list is skipped")
check(said("Bulk actions done: 1 done, 0 waiting for the roster, 1 skipped."), "the end says what was done")
check(BA:NextLabel() == "Done", "and the button says so")
roster[3][2] = 3

-- A demotion, logged by the click alone when no guild message comes.
ok = BA:Start({ days = 30, rank = 3 }, "demote")
q = BA:Queue()
check(ok and #q.items == 2 and q.items[1].name == "Bob", "a new queue replaces the finished one")
check(BA:Arm(false) == "/gdegradar Bob", "demote arms the client's demote")
BA:AfterClick(false)
roster[2][2] = 4
NOW = NOW + 60
BA:Confirm()
local last = events[#events]
check(q.items[1].status == "done" and last.action == "demote" and last.author == "Arthas" and last.detail == "Initiate",
      "a change the roster shows goes to the Roster Log with the new rank")
local n = #events
GuildOS.RosterLog:Add({ action = "demote", target = "Bob", author = "Arthas", detail = "Initiate", timestamp = NOW + 4 })
check(#events == n, "the game's own message a few seconds later is the same event, not a second one")
GuildOS.RosterLog:Add({ action = "join", target = "Zed", timestamp = NOW + 10 })
GuildOS.RosterLog:Add({ action = "leave", target = "Zed", timestamp = NOW + 20 })
GuildOS.RosterLog:Add({ action = "join", target = "Zed", timestamp = NOW + 30 })
check(#events == n + 3, "a join, a leave and a join again are three events, whatever their seconds")

-- A removal: the one who left meanwhile is skipped; the removed one is done when gone.
setRoster({
  { "Arthas", 1, 60, true },
  { "Bob", 4, 60, false, 45 },
  { "Gil", 4, 60, false, 50 },
})
ok = BA:Start({ days = 30 }, "remove", true)
q = BA:Queue()
check(ok and #q.items == 2 and q.items[1].name == "Gil", "a confirmed removal starts")
table.remove(roster, 3)   -- Gil left on his own
line = BA:Arm(false)
check(line == "/gremove Bob" and q.items[1].status == "skipped" and q.items[1].why == "left",
      "who left the guild is skipped, the click goes to the next")
BA:AfterClick(false)
table.remove(roster, 2)
NOW = NOW + 60
BA:Confirm()
check(q.items[2].status == "done" and events[#events].action == "kick", "a removal is logged as the game logs one")

-- Combat and the rank's right are checked at every click.
setRoster({ { "Arthas", 1, 60, true }, { "Bob", 4, 60, false, 45 } })
BA:Start({ days = 30 }, "promote")
combat = true
check(BA:Arm(false) == nil and BA:Queue().items[1].status == "pending", "no line in combat")
combat = false
can.promote = false
check(BA:Arm(false) == nil and said("Your guild rank may not do this."), "no line without the rank's right")
can.promote = true

-- A block the game raises while this click runs its line: the member is never marked sent, and from then on the
-- click prints the line to type. Another addon's block, or one for another function, is not ours.
check(BA:Arm(false) == "/gpromote Bob", "armed")
BA:OnBlocked("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "GuildPromote")
BA:OnBlocked("MACRO_ACTION_BLOCKED", "CastSpellByName")
check(not BA:Typed(), "another addon's block, or another function's, changes nothing")
BA:OnBlocked("MACRO_ACTION_BLOCKED", "GuildPromote")
BA:AfterClick(false)
check(BA:Queue().items[1].status == "pending" and BA:Typed(), "blocked during the click: Bob was never sent, typed mode on")
check(said("The game blocked the click. Click Next again: it shows the line to type."), "and the officer is told")
printed = {}
check(BA:Arm(false) == nil and BA:Queue().items[1].status == "sent", "typed: the click arms nothing and goes on")
check(said("Type /gpromote Bob in chat, then click Next for the one after."), "it prints the line to type")
-- A block after the click is over (nothing armed) never puts a sent member back.
BA:OnBlocked("MACRO_ACTION_BLOCKED", "GuildPromote")
check(BA:Queue().items[1].status == "sent", "a member already sent is never put back")
-- No change in the roster for a while: "not confirmed", never sent again.
CLOCK = CLOCK + 20
for _, fn in ipairs(timers) do fn() end
timers = {}
check(BA:Queue().items[1].status == "unconfirmed", "no change seen in the roster: not confirmed, check it")
check(BA:Arm(false) == nil and BA:Counts().sent == 0, "and nobody is sent twice")
roster[2][2] = 3
BA:Confirm()
check(BA:Queue().items[1].status == "done", "a later roster update still confirms it")
GuildOS.State.bulk.typed = nil

-- The rules are checked again before each click: who logged in since is no longer 30 days offline.
setRoster({ { "Arthas", 1, 60, true }, { "Bob", 4, 60, false, 45 }, { "Cid", 4, 60, false, 50 } })
BA:Start({ days = 30 }, "remove", true)
roster[3][4] = true   -- Cid logs in
check(BA:Arm(false) == "/gremove Bob" and BA:Queue().items[1].status == "skipped" and BA:Queue().items[1].why == "rules",
      "who no longer meets the rules is skipped, the click goes to the next")
BA:AfterClick(false)

-- The removal's confirmation queues exactly the list it showed.
local shown = BA:Preview({ days = 30 }, "remove")
roster[#roster + 1] = { "Dan", 4, 60, false, 90 }
check(BA:Start({ days = 30 }, "remove", true, shown) and #BA:Queue().items == #shown,
      "the queue is the list the dialog showed, not one made again")
BA:Stop()

-- WoW: Forever prints the line from the first click; `/gos bulk next` does the same there. A surname goes as /w
-- takes it, the hyphen for the space.
GuildOS.Client.game, GuildOS.Client.isAnniversary, GuildOS.Client.has.surnames = "FOREVER", false, true
check(Compat.GuildRankCommand("promote", "Chehul Druida") == "/gpromote Chehul-Druida", "a Forever surname")
check(Compat.GuildRankCommand("promote", "Chehul;Druida") == nil and Compat.GuildRankCommand("promote", "a/b") == nil,
      "a ; or a / never reaches the line")
setRoster({ { "Arthas", 1, 60, true }, { "Bob", 4, 60, false, 45 } })
BA:Start({ days = 30 }, "promote")
printed = {}
BA:Command("next")
check(BA:Queue().items[1].status == "sent" and said("Type /gpromote Bob in chat"), "Forever: /gos bulk next prints the line")
-- Never typed: the roster shows no change, the member reads "not confirmed", and Retry puts them back next (audit M13).
CLOCK = CLOCK + 16
BA:Confirm()
check(BA:Queue().items[1].status == "unconfirmed" and BA:Current() == nil, "unconfirmed after the wait, and no longer next")
check(BA:RetryUnconfirmed() == 1 and BA:Queue().items[1].status == "pending" and BA:Current() == BA:Queue().items[1],
      "Retry puts the member back in the queue, next")
printed = {}
BA:Command("next")
check(BA:Queue().items[1].status == "sent" and said("Type /gpromote Bob in chat"), "and the next click prints their line again")
check(BA:RetryUnconfirmed() == 0, "a member just sent is not retried")
CLOCK = CLOCK + 16
BA:Confirm()
BA:Command("retry")
check(BA:Queue().items[1].status == "pending", "/gos bulk retry does the same")
BA:Stop()
GuildOS.Client.game, GuildOS.Client.isAnniversary, GuildOS.Client.has.surnames = "ANNIVERSARY", true, false
roster[2][2] = 4

-- Elsewhere a typed command only says who is next: it may not run the game's command.
BA:Start({ days = 30 }, "promote")
printed = {}
BA:Command("next")
check(BA:Queue().items[1].status == "pending" and said("/click GuildOSBulkNext"), "/gos bulk next names the macro and acts on nobody")
check(BA:Skip() and BA:Queue().items[1].why == "you", "skip passes over the member")
BA:Command("stop")
check(BA:Queue() == nil, "stop drops the queue")

-- The key-down option: with it, the button listens to press and release and exactly one arms the line; the macro
-- says it is a press when the option is on. Without it, the release acts.
local keyDown = "1"
function GetCVar(name) return name == "ActionButtonUseKeyDown" and keyDown or nil end
local registered
local fakeButton = { RegisterForClicks = function(_, ...) registered = { ... } end }
Compat.SecureClicks(fakeButton)
check(#registered == 2, "with the option, press and release are both registered")
check(Compat.SecureClickActs(true) and not Compat.SecureClickActs(false), "key-down on: the press arms, the release does not")
check(Compat.ClickMacro("GuildOSBulkNext") == "/click GuildOSBulkNext LeftButton 1", "and the macro presses")
keyDown = "0"
check(Compat.SecureClickActs(false) and not Compat.SecureClickActs(true), "key-down off: the release arms, the press does not")
check(Compat.ClickMacro("GuildOSBulkNext") == "/click GuildOSBulkNext", "and the macro is a plain /click")
GetCVar = nil
Compat.SecureClicks(fakeButton)
check(#registered == 1 and Compat.SecureClickActs(false) and not Compat.SecureClickActs(true), "without the option: the release")

-- Retail keeps the realm, and a member is found by the whole name: Bob-A gone while Bob-B stays is gone.
GuildOS.Client.isRetail = true
check(Compat.GuildRankCommand("promote", "Bob-Azralon") == "/gpromote Bob-Azralon", "retail keeps the realm")
setRoster({ { "Arthas", 1, 60, true }, { "Bob-Azralon", 4, 60, false, 45 }, { "Bob-Gallywix", 3, 60, false, 45 } })
BA:Start({ days = 30, rank = 4 }, "promote")
check(#BA:Queue().items == 1 and BA:Queue().items[1].fullName == "Bob-Azralon", "the queue holds Bob-Azralon")
table.remove(roster, 2)
check(BA:Arm(false) == nil and BA:Queue().items[1].why == "left", "Bob-Azralon left: Bob-Gallywix does not stand in for him")
GuildOS.Client.isRetail = false

-- One member from the roster's menu, Ranks, Inactivity, Suggestions or Discipline (audit M11): a queue of one, run by
-- one click of Next, never the protected call and never the game's panel.
local GM = GuildOS.GuildManager
setRoster({ { "Arthas", 1, 60, true }, { "Bob", 4, 60, false, 45 }, { "Cid", 3, 60, false, 2 }, { "Dee", 2, 60, true } })
printed = {}
check(GM:Promote("Bob") and BA:Queue() and #BA:Queue().items == 1 and BA:Queue().items[1].fullName == "Bob"
  and BA:Queue().action == "promote", "Promote queues that one member")
check(BA:Arm(false) == "/gpromote Bob", "and the click runs the game's /gpromote for them")
BA:AfterClick(false)
check(not GM:Demote("Cid") and said("still running"), "a queue still waiting for the roster is never replaced")
roster[2][2] = 3
BA:Confirm()
check(BA:Queue().items[1].status == "done", "the roster shows it: done")
check(GM:Kick("Cid") and BA:Queue().action == "remove" and BA:Arm(false) == "/gremove Cid", "Remove queues the removal")
BA:AfterClick(false)
BA:Stop()
printed = {}
check(not GM:Promote("Nobody") and said("Nobody is not in the guild roster."), "somebody not on the roster: said so")
check(not GM:Promote("Dee") and said("Your guild rank may not do this to Dee."), "a promotion up to one's own rank is refused")
-- Toward a rank, one step per click (Discipline's rank step).
check(GM:QueueRankAction("demote", "Cid", nil, 4) and BA:Queue().target == 4 and BA:Arm(false) == Compat.GuildRankCommand("demote", "Cid"),
  "toward a rank: a demotion step")
BA:AfterClick(false)
BA:Stop()
check(not GM:QueueRankAction("demote", "Bob", nil, 3) and said("Bob is already at that rank."), "already there: said so")
local menuSrc = assert(io.open(ADDON .. "/UI/RosterFrame.lua", "rb")):read("*a")
check(not menuSrc:find("SETRANK", 1, true) and not menuSrc:find("ConfirmSetRank", 1, true), "the Set Rank submenu is gone")
local gmSrc = assert(io.open(ADDON .. "/Modules/GuildManager.lua", "rb")):read("*a")
check(not gmSrc:find("function GuildManager:SetRank", 1, true), "and so is SetRank, whose rank choice was thrown away")

-- ── Time in rank and in the guild, the player's alts (specs/salao/manutencao-roster.md) ──
local rr = BA.Rules({ rankDaysMin = "60", tenureDaysMin = "365", countAlts = true })
check(rr.rankDaysMin == 60 and rr.tenureDaysMin == 365 and rr.countAlts and BA.HasRule(rr), "days in rank and in the guild are rules")
check(BA.Rules({ rankDaysMin = "0", tenureDaysMin = "abc" }).rankDaysMin == nil and not BA.HasRule(BA.Rules({ countAlts = true })),
  "nothing set is none; counting alts alone picks nobody")
check(BA.Meets({ rankDays = 60, tenureDays = 400 }, rr) and not BA.Meets({ rankDays = 59, tenureDays = 400 }, rr)
  and not BA.Meets({ rankDays = 60 }, rr), "both must hold; an unknown time meets neither")
local byDays = BA.Rules({ days = 30, countAlts = true })
check(not BA.Meets({ daysOffline = 45, playerDays = 3 }, byDays) and BA.Meets({ daysOffline = 45, playerDays = 31 }, byDays)
  and BA.Meets({ daysOffline = 45 }, byDays) and BA.Meets({ daysOffline = 45, playerDays = 3 }, BA.Rules({ days = 30 })),
  "counting the alts, a character whose alt was seen within the days is kept; without, it is not")

print("bulk-actions: " .. checks .. " checks passed")
