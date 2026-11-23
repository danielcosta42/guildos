-- Without GuildOS: the officers' list and the reminder (issue #422), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/GuildManager.lua, Modules/Discipline.lua and
-- Modules/AddonReminder.lua under a stubbed client.
--
-- The list is who this client never heard GuildOS from (oneself aside), longest first, filtered by name,
-- rank, online and "reminded recently"; one click whispers one member the filled text, on the click;
-- the same member waits N days, whoever of the officers reminded them; two reminders keep a gap and the
-- game's "too fast" holds them and undoes the one that just left; the disciplinary record gets it only
-- when the officer asked; only an officer reminds, and only an officer's date is taken. With the site's
-- GOSGILD1.discordLinked (read by the real CompanionImport, whole or not at all) the list also holds who
-- has GuildOS but no Discord, filtered by what they lack, and the whisper says the matching text; without
-- it, the list is the GuildOS one, as before.
--
--   luajit -e 'ADDON="."' tools/addon-reminder.lua
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
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(_, fn) self.onEvent = fn end
  frames[#frames + 1] = f
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
function time() return NOW end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers()
  local list = timers
  timers = {}
  for _, fn in ipairs(list) do fn() end
end
function GuildRoster() end
function InCombatLockdown() return false end
Enum = { SendAddonMessageResult = {} }
ERR_GENERIC_THROTTLE = "You are doing that too fast"

local RANKS = { "Guild Master", "Officer", "Veteran", "Member", "Initiate" }
function GuildControlGetNumRanks() return #RANKS end
function GuildControlGetRankName(i) return RANKS[i] end
function IsInGuild() return true end
local myRank = 1
function GetGuildInfo() return "Os Guardioes", RANKS[myRank + 1], myRank end

-- { name, rankIndex, level, online, daysOffline }
local roster
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i)
  local m = roster[i]
  if not m then return nil end
  return m[1], RANKS[m[2] + 1], m[2], m[3], nil, nil, nil, nil, m[4], nil, "MAGE"
end
function GetGuildRosterLastOnline(i)
  local m = roster[i]
  if not m or m[4] then return nil end
  return 0, 0, m[5] or 0, 0
end

-- Every whisper the client would send: { text, target }.
local whispers = {}
function SendChatMessage(text, chatType, _, target)
  if chatType == "WHISPER" then whispers[#whispers + 1] = { text = text, target = target } end
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/GuildManager.lua")
dofile(ADDON .. "/Modules/Discipline.lua")
dofile(ADDON .. "/Modules/AddonReminder.lua")

-- The officers' channel: what this client publishes, and what reaches it.
local published = {}
local handlers = {}
GuildOS.SyncService = {
  On = function(_, dom, fn) handlers[dom] = fn end,
  Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end,
}
local function publishedOf(dom)
  local out = {}
  for _, p in ipairs(published) do if p.dom == dom then out[#out + 1] = p end end
  return out
end

GuildOS.Compat.PlayerName = function() return "Arthas" end
-- The site's block, as the companion import hands it over (nil: an older site, or no block).
local BLOCK
local Import = GuildOS.CompanionImport
function Import:GuildBlock() return BLOCK end
GuildOS.db = { settings = {}, members = {}, firstSeen = {} }
local R = GuildOS.AddonReminder
local key = function(n) return GuildOS:GetPlayerKey(n) end
local day = 86400
R:Initialize()
GuildOS.Discipline:Initialize()
check(handlers.reminder ~= nil, "the officers' reminder dates are listened to")

roster = {
  { "Arthas", 1, 60, true },
  { "Bob", 4, 60, true },
  { "Cid", 3, 60, false, 12 },
  { "Dan", 4, 30, true },
  { "Eve", 2, 60, true },
}
GuildOS.db.members[key("Dan")] = { lastUpdate = NOW - 5 }   -- Dan's GuildOS was heard
GuildOS.db.firstSeen[key("Bob")] = NOW - 10 * day
GuildOS.db.firstSeen[key("Cid")] = NOW - 40 * day
GuildOS.db.firstSeen[key("Eve")] = NOW - 2 * day

-- ── The list ────────────────────────────────────────────────────────────
local list = R:List({})
check(#list == 3 and list[1].name == "Cid" and list[2].name == "Bob" and list[3].name == "Eve",
      "who has no GuildOS, longest first; oneself and Dan (heard) are not listed")
check(list[1].sinceDays == 40 and list[1].daysOffline == 12 and not list[1].online, "how long, and how long offline")
check(#R:List({ online = true }) == 2, "online only")
check(#R:List({ rank = 4 }) == 1 and R:List({ rank = 4 })[1].name == "Bob", "by rank")
check(#R:List({ text = "  ci " }) == 1, "by part of the name, any case")
check(#R:List({ rank = -1 }) == 3, "any rank")

-- ── The settings ────────────────────────────────────────────────────────
check(R:GetDays() == 7, "every 7 days by default")
check(not R:SetDays("0") and not R:SetDays("91") and not R:SetDays("2.5") and R:GetDays() == 7, "out of range is refused")
check(R:SetDays("3") and R:GetDays() == 3, "an officer's own number of days")
R:SetDays(7)
check(R:GetTemplate() == R.DefaultTemplate(), "the default text until one is written")
R:SetTemplate("Hey {name}, {guild} uses |cffff0000GuildOS|r!\nPlease get it.")
check(R:GetTemplate() == "Hey {name}, {guild} uses cffff0000GuildOSr! Please get it.", "the text is one line with no game codes")
check(R.Fill("{name} {who} 100%", { name = "Bob" }) == "Bob {who} 100%", "a known field filled, an unknown left as typed")
check(#R.Fill(string.rep("a", 300), {}) == 255, "a whisper is cut at 255 bytes")
R:SetTemplate("")
check(GuildOS:GetSetting("reminderTemplate") == nil, "blank goes back to the default")
R:SetTemplate("Hi {name}, {guild} uses GuildOS.")

-- ── One click, one member ───────────────────────────────────────────────
local ok, why = R:Remind(key("Cid"))
check(not ok and why == "offline" and #whispers == 0, "an offline member is not whispered")
ok = R:Remind(key("Bob"))
check(ok and #whispers == 1 and whispers[1].target == "Bob" and whispers[1].text == "Hi Bob, Os Guardioes uses GuildOS.",
      "the click whispers the filled text to that member only")
check(GuildOS.db.reminders[key("Bob")] == NOW, "the date is kept at once: no second click for Bob")
ok, why = R:Remind(key("Eve"))
check(not ok and why == "wait" and #whispers == 1, "a second reminder within the gap waits")
check(#publishedOf("reminder") == 0 and #timers == 1, "nothing goes to the officers until the game had its moment")
runTimers()
local pub = publishedOf("reminder")
check(#pub == 1 and pub[1].act == "sent" and pub[1].data.key == key("Bob") and pub[1].data.at == NOW,
      "the date then goes to the other officers")
check(next(GuildOS.db.discipline.warnings) == nil, "nothing is filed on the record unless asked")

CLOCK = CLOCK + R.GAP
NOW = NOW + R.GAP
ok, why = R:Remind(key("Bob"))
check(not ok and why == "recent", "the same member waits the days")
local listed = R:List({ hideRecent = true })
check(#listed == 2 and listed[1].name == "Cid", "the reminded can be hidden")
NOW = NOW + 7 * day
check(R:CanRemind(R:Member(key("Bob"))), "after 7 days Bob can be reminded again")

-- ── The game's "too fast" ───────────────────────────────────────────────
CLOCK = CLOCK + R.GAP
R:SetLogDiscipline(true)
ok = R:Remind(key("Eve"))
check(ok and #whispers == 2, "Eve whispered")
local f
for _, fr in ipairs(frames) do if fr.events.UI_ERROR_MESSAGE then f = fr end end
check(f ~= nil, "the game's error lines are listened to")
f.onEvent(f, "UI_ERROR_MESSAGE", 3, "Something else")
check(GuildOS.State.reminder.holdUntil == nil, "another error line holds nothing")
CLOCK = CLOCK + 1
f.onEvent(f, "UI_ERROR_MESSAGE", 3, ERR_GENERIC_THROTTLE)
check(GuildOS.db.reminders[key("Eve")] == nil, "the reminder throttled right after it left does not count")
check(said("went too fast"), "and the officer is told")
runTimers()
check(#publishedOf("reminder") == 1 and next(GuildOS.db.discipline.warnings) == nil,
      "a throttled reminder is neither sent to the officers nor filed")
CLOCK = CLOCK + R.GAP
ok, why = R:Remind(key("Eve"))
check(not ok and why == "throttle", "after the game's too fast, the reminders hold")
CLOCK = CLOCK + R.HOLD

-- ── On the record, when asked ───────────────────────────────────────────
ok = R:Remind(key("Eve"))
check(ok and #whispers == 3, "after the hold, Eve is whispered")
CLOCK = CLOCK + R.WATCH + 1
f.onEvent(f, "UI_ERROR_MESSAGE", 3, ERR_GENERIC_THROTTLE)   -- late: holds the next, does not undo this one
check(GuildOS.db.reminders[key("Eve")] == NOW, "a too fast after the moment does not undo the reminder")
runTimers()
local filed
for _, w in pairs(GuildOS.db.discipline.warnings) do filed = w end
check(filed and filed.subject == key("Eve") and filed.reason == "other" and filed.note == "Reminded to install GuildOS (whisper).",
      "with the box ticked the reminder is filed on Eve's record")
R:SetLogDiscipline(false)

-- ── Among officers ──────────────────────────────────────────────────────
handlers.reminder({ act = "sent", data = { key = key("Cid"), at = NOW - day } })
check(GuildOS.db.reminders[key("Cid")] == NOW - day, "another officer's reminder counts here")
handlers.reminder({ act = "sent", data = { key = key("Cid"), at = NOW - 5 * day } })
check(GuildOS.db.reminders[key("Cid")] == NOW - day, "an older date never replaces a newer one")
handlers.reminder({ act = "sent", data = { key = key("Zed"), at = NOW + 10 * day } })
handlers.reminder({ act = "sent", data = { key = "a|b", at = NOW } })
handlers.reminder({ act = "sent", data = { key = key("Zed"), at = 0 / 0 } })
check(GuildOS.db.reminders[key("Zed")] == nil and GuildOS.db.reminders["a|b"] == nil, "a date from the future, a bad key or NaN is refused")

-- ── Only an officer ─────────────────────────────────────────────────────
myRank = 3
CLOCK = CLOCK + R.HOLD
NOW = NOW + 30 * day
local before = #whispers
ok, why = R:Remind(key("Bob"))
check(not ok and why == "officer" and #whispers == before, "a member cannot remind")
handlers.reminder({ act = "sent", data = { key = key("Bob"), at = NOW } })
check(GuildOS.db.reminders[key("Bob")] ~= NOW, "a member's client keeps no date")
myRank = 1

-- Bob installs GuildOS: off the list, and never whispered.
GuildOS.db.members[key("Bob")] = { lastUpdate = NOW }
ok, why = R:Remind(key("Bob"))
check(not ok and why == "addon", "who has GuildOS now is not reminded")
table.remove(roster, 2)
ok, why = R:Remind(key("Bob"))
check(not ok and why == "gone", "who left is not reminded")

-- The dates are forgotten past keeping.
GuildOS.db.reminders.old = NOW - 100 * day
check(R:Prune(NOW) >= 1 and GuildOS.db.reminders.old == nil, "an old date goes")

-- ── Without Discord (the site's discordLinked) ──────────────────────────
check(Import:DiscordLinked() == nil and R:Linked() == nil, "no block: the game does not know who linked Discord")
BLOCK = { guild = "Os Guardioes" }
check(Import:DiscordLinked() == nil, "a block without the field (an older site): not known")
BLOCK = { discordLinked = "Bob-Dreamscythe" }
check(Import:DiscordLinked() == nil, "not a list: refused")
BLOCK = { discordLinked = { "Eve-Dreamscythe", 42 } }
check(Import:DiscordLinked() == nil, "an entry that is not a key refuses the whole list")
BLOCK = { discordLinked = { "Eve-Dreamscythe", "Bad|cffff0000-Dreamscythe" } }
check(Import:DiscordLinked() == nil, "a key with a bar refuses the whole list")
BLOCK = { discordLinked = { "Eve-Dreamscythe", string.rep("x", 65) } }
check(Import:DiscordLinked() == nil, "a key past 64 bytes refuses the whole list, never cut")
BLOCK = { discordLinked = { "Eve-Dreamscythe", extra = "x" } }
check(Import:DiscordLinked() == nil, "a table with more than a list in it: refused")
local big = {}
for i = 1, Import.DISCORD_LINKED_MAX + 1 do big[i] = "M" .. i .. "-Dreamscythe" end
BLOCK = { discordLinked = big }
check(Import:DiscordLinked() == nil, "over the limit: refused, never a cut list")
BLOCK = { discordLinked = {} }
local none = Import:DiscordLinked()
check(none ~= nil and next(none) == nil, "an empty list says nobody linked")

roster = {
  { "Arthas", 1, 60, true },
  { "Fay", 4, 60, true },    -- GuildOS, Discord linked: not listed
  { "Gus", 4, 60, true },    -- GuildOS, no Discord
  { "Hal", 3, 60, true },    -- no GuildOS, Discord linked
  { "Ivy", 3, 60, true },    -- neither
}
for _, n in ipairs({ "Fay", "Gus" }) do GuildOS.db.members[key(n)] = { lastUpdate = NOW } end
GuildOS.db.reminders = {}
BLOCK = { discordLinked = { "fay-dreamscythe", "Hal-Dreamscythe", "Arthas-Dreamscythe" } }
check(Import:DiscordLinked()[key("Fay"):lower()] and Import:DiscordLinked() == Import:DiscordLinked(),
      "kept in memory, once per block, by this client's key in any case")
local names = function(l) local o = {} for _, m in ipairs(l) do o[#o + 1] = m.name end table.sort(o) return table.concat(o, ",") end
check(names(R:List({})) == "Gus,Hal,Ivy", "without GuildOS, without Discord, or both; who has both is not listed, nor oneself")
check(names(R:List({ lacks = "addon" })) == "Hal,Ivy", "only without GuildOS")
check(names(R:List({ lacks = "discord" })) == "Gus,Ivy", "only without Discord")
check(names(R:List({ lacks = "both" })) == "Ivy", "only without either")
local gus = R:Member(key("Gus"))
check(gus.noDiscord == true and gus.hasAddon and R.KindOf(gus) == "discord", "Gus lacks Discord only")
check(R.KindOf(R:Member(key("Hal"))) == "addon" and R.KindOf(R:Member(key("Ivy"))) == "both" and R.KindOf(R:Member(key("Fay"))) == nil,
      "what each one lacks")

check(R:GetTemplate("discord") == R.DefaultDiscordTemplate(), "the Discord text has its own default")
R:SetTemplate("Link it, {name}! {discord}", "discord")
check(R:GetTemplate("discord") == "Link it, {name}! {discord}" and R:GetTemplate() == "Hi {name}, {guild} uses GuildOS.",
      "an officer's own Discord text, apart from the GuildOS one")
CLOCK = CLOCK + R.HOLD
R:SetLogDiscipline(true)
local n0 = #whispers
ok = R:Remind(key("Gus"))
check(ok and whispers[#whispers].text == "Link it, Gus!", "who has GuildOS gets the Discord text")
CLOCK = CLOCK + R.GAP
ok = R:Remind(key("Ivy"))
check(ok and whispers[#whispers].text == "Hi Ivy, Os Guardioes uses GuildOS. " .. R.DiscordHint(),
      "who lacks both gets the GuildOS text with the Discord hint after it")
CLOCK = CLOCK + R.GAP
R:SetTemplate("Hi {name}!{discord} Bye.")
ok = R:Remind(key("Hal"))
check(ok and whispers[#whispers].text == "Hi Hal! Bye." and #whispers == n0 + 3, "who has Discord: {discord} stays empty")
runTimers()
local notes = {}
for _, w in pairs(GuildOS.db.discipline.warnings) do notes[w.subject] = w.note end
check(notes[key("Gus")] == "Reminded to link Discord on guildos.me (whisper)."
      and notes[key("Ivy")] == "Reminded to install GuildOS and link Discord (whisper)."
      and notes[key("Hal")] == "Reminded to install GuildOS (whisper).", "the record says what the reminder was for")
R:SetLogDiscipline(false)
R:SetTemplate(nil, "discord")
check(GuildOS:GetSetting("reminderDiscordTemplate") == nil, "Default puts the Discord text back")

-- The site stops saying it: the list is the GuildOS one again.
BLOCK = nil
check(names(R:List({})) == "Hal,Ivy" and R:Member(key("Gus")).noDiscord == nil,
      "without the field, nobody is called without Discord")

print(string.format("addon-reminder: %d checks passed", checks))
