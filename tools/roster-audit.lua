-- The roster maintenance (specs/salao/manutencao-roster.md), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/GuildManager.lua, Modules/RosterLog.lua, Modules/MemberHistory.lua, Modules/MemberMarks.lua,
-- Modules/NoteDates.lua, Modules/BulkActions.lua, Modules/ModPresets.lua, Modules/RosterMaint.lua, Modules/Search.lua
-- and Modules/ExportImport.lua under a stubbed TBC Anniversary client.
--
--   * The data audit: who has no real join date, no alt link, a note's date that is not the history's; the counts,
--     the filter, the sort by every column; the officer note read only by a rank that may; cached, and invalidated.
--   * Its actions call the existing flows: Notes and marks' Write date (prefilled), the member window on Add alt,
--     NoteDates' write into the note that differs.
--   * Time in rank and in the guild: the Bulk actions rules, the "promote after days in rank" preset, the "long in
--     rank" suggestion (only for a rank that may promote).
--   * Inactivity per player: a character whose main or alt was seen within the days is not inactive (the setting,
--     on by default); the list says which was seen; a removal by days can take a whole group, only when all are out.
--   * The global search over the notes (the officer note by permission), the main's name and the nickname.
--   * The roster export's Main, JoinDate, DaysInRank, PublicNote and (by permission) OfficerNote.
--
--   luajit -e 'ADDON="."' tools/roster-audit.lua
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

-- ── The client ──────────────────────────────────────────────────────────
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
local function said(text)
  for _, line in ipairs(printed) do
    if tostring(line):find(text, 1, true) then return true end
  end
  return false
end
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(ev) self.events[ev] = true end
  function f:SetScript(_, fn) self.onEvent = fn end
  return f
end
function hooksecurefunc() end
function debugstack() return "" end
WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
function GetBuildInfo() return "2.5.5", "65000", "", 20505 end
function GetRealmName() return "Dreamscythe" end
function GetLocale() return "ptBR" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower = string.lower
format = string.format
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
date, time = os.date, os.time
local DAY = 86400
local NOW = os.time({ year = 2026, month = 11, day = 23, hour = 12 })
function GetServerTime() return NOW end
function GetTime() return 1000 end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
function GuildRoster() end
function InCombatLockdown() return false end
Enum = { SendAddonMessageResult = {} }

local RANKS = { "Guild Master", "Officer", "Veteran", "Member", "Initiate" }
function GuildControlGetNumRanks() return #RANKS end
function GuildControlGetRankName(i) return RANKS[i] end
function IsInGuild() return true end
local myRank = 1
function GetGuildInfo() return "Os Guardioes", RANKS[myRank + 1], myRank end
local canPromote = true
function CanGuildPromote() return canPromote end
function CanGuildDemote() return true end
function CanGuildRemove() return true end
local viewOfficer = true
function CanEditPublicNote() return true end
function CanEditOfficerNote() return true end
function CanViewOfficerNote() return viewOfficer end

-- { name, rankIndex, level, online, daysOffline, note, onote }
local roster = {}
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i)
  local m = roster[i]
  if not m then return nil end
  return m[1], RANKS[m[2] + 1], m[2], m[3], "Warrior", "", m[6] or "", m[7] or "", m[4], 0, "WARRIOR"
end
function GetGuildRosterLastOnline(i)
  local m = roster[i]
  if not m or m[4] then return nil end
  return 0, 0, m[5] or 0, 0
end
local writes = {}
function GuildRosterSetPublicNote(i, note) writes[#writes + 1] = { i = i, note = note, public = true }; roster[i][6] = note end
function GuildRosterSetOfficerNote(i, note) writes[#writes + 1] = { i = i, note = note, public = false }; roster[i][7] = note end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/GuildManager.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
dofile(ADDON .. "/Modules/MemberHistory.lua")
dofile(ADDON .. "/Modules/MemberMarks.lua")
dofile(ADDON .. "/Modules/NoteDates.lua")
dofile(ADDON .. "/Modules/BulkActions.lua")
dofile(ADDON .. "/Modules/ModPresets.lua")
dofile(ADDON .. "/Modules/RosterMaint.lua")
dofile(ADDON .. "/Modules/Search.lua")
dofile(ADDON .. "/Modules/ExportImport.lua")
function GuildOS:IsOnGuildDB() return true end
GuildOS.Compat.PlayerName = function() return "Arthas" end
GuildOS.SyncService = { Publish = function() end, On = function() end }
GuildOS.db = { settings = {}, members = {}, rosterLog = { events = {} }, memberHistory = {}, memberHistoryOut = {},
               altLinks = {} }
local ND, MM, MH, BA, MP, RM, GM = GuildOS.NoteDates, GuildOS.MemberMarks, GuildOS.MemberHistory, GuildOS.BulkActions,
  GuildOS.ModPresets, GuildOS.RosterMaint, GuildOS.GuildManager
ND:Initialize()
MM:Initialize()
BA:Initialize()
local K = function(n) return GuildOS:GetPlayerKey(n) end
local function ago(d) return NOW - d * DAY end

-- What the screens open: recorded, never drawn.
local opened, shown = {}, {}
GuildOS.UI = { OpenWindow = function(_, a, b) opened[#opened + 1] = a .. "/" .. tostring(b) return true end }
function GuildOS:ShowMemberDetail(rec, focus) shown[#shown + 1] = { name = rec.name, focus = focus } end

-- ── 1. The pure parts ───────────────────────────────────────────────────
check(RM.Days(ago(3) - 100, NOW) == 3 and RM.Days(NOW + 50, NOW) == 0 and RM.Days(nil, NOW) == nil, "whole days, never negative")
local t, est = RM.RankSinceOf({ { at = ago(40), to = "Member" } }, { { joinAt = ago(400) } })
check(t == ago(40) and not est, "in the rank since the last change")
t, est = RM.RankSinceOf({}, { { joinAt = ago(10), joinEst = true } })
check(t == ago(10) and est, "no change: since the join, est when only seen")
t = RM.RankSinceOf({ { at = ago(500), to = "Member" } }, { { joinAt = ago(600), leftAt = ago(550) }, { joinAt = ago(20) } })
check(t == ago(20), "a change from an earlier passage does not count: since this passage")
check(RM.RankSinceOf({}, { { joinAt = ago(9), leftAt = ago(1) } }) == nil, "a former member has no rank")

local seen, mainOf = RM.GroupSeen({
  { key = "M", name = "Main", days = 40 }, { key = "A1", name = "Alt1", days = 2 }, { key = "A2", name = "Alt2", days = 90 },
  { key = "S", name = "Solo", days = 50 },
}, { A1 = "M", A2 = "M" })
check(seen.M.name == "Alt1" and seen.M.days == 2 and not seen.M.main, "the main's most recent alt")
check(seen.A1.name == "Main" and seen.A1.main and seen.A2.name == "Alt1", "an alt sees the group's most recent other")
check(seen.S == nil and mainOf.S == nil and mainOf.A2 == "M", "a lone character has no group")
check(RM.PlayerDays(40, seen.M) == 2 and RM.PlayerDays(2, seen.A1) == 2 and RM.PlayerDays(nil, seen.M) == nil, "the player's days")
check(RM.SeenText({ name = "Xyz", days = 2, main = true }) == "main Xyz seen 2d ago"
  and RM.SeenText({ name = "Q", days = 0 }) == "alt Q seen today", "which one was seen, said")

ND.Order = function() return "dmy" end
local p, diff = RM.Classify({ joinAt = nil, linked = true }, "dmy", 2026)
check(p.nodate and not p.noalt and not p.notediff, "no history: no join date")
p = RM.Classify({ joinAt = ago(30), joinEst = true, linked = false }, "dmy", 2026)
check(p.nodate and p.noalt, "only seen by Guild OS is no real date; no link is no alt")
p = RM.Classify({ joinAt = ago(30), joinEst = true, joinFromNote = true, linked = true }, "dmy", 2026)
check(not RM.HasProblem(p), "a date read from a note is real")
local exact = os.time({ year = 2024, month = 3, day = 2, hour = 10 })
p, diff = RM.Classify({ joinAt = exact, linked = true, public = "Entrou 05/03/24", officer = "02/03/2024" }, "dmy", 2026)
check(p.notediff and diff.which == "public" and diff.day.day == 5, "the public note says another day")
p, diff = RM.Classify({ joinAt = exact, linked = true, public = "raider", officer = "01/03/24" }, "dmy", 2026)
check(p.notediff and diff.which == "officer", "the officer note says another day")
p = RM.Classify({ joinAt = exact, linked = true, public = "02/03/24", officer = nil }, "dmy", 2026)
check(not p.notediff, "the same day is no difference; an unreadable officer note is not compared")

local rows = {
  { name = "Bia", rankName = "Member", rankIndex = 3, rankDays = 10, joinAt = ago(100), problems = { nodate = true } },
  { name = "ana", rankName = "Veteran", rankIndex = 2, rankDays = nil, joinAt = nil, problems = { noalt = true, nodate = true } },
  { name = "Caio", rankName = "Initiate", rankIndex = 4, rankDays = 300, joinAt = ago(400), nick = "Padre", problems = { notediff = true } },
}
local c = RM.Count(rows)
check(c.all == 3 and c.nodate == 2 and c.noalt == 1 and c.notediff == 1, "the chips' counts")
check(#RM.Filter(rows, "nodate") == 2 and #RM.Filter(rows, "notediff") == 1 and #RM.Filter(rows, "all") == 3, "the chips filter")
check(#RM.Filter(rows, nil, "padre") == 1 and #RM.Filter(rows, "all", "veter") == 1 and #RM.Filter(rows, "noalt", "bia") == 0,
  "the search by name, rank and nickname, with the chip")
local function names(list) local o = {} for i, r in ipairs(list) do o[i] = r.name end return table.concat(o, ",") end
check(names(RM.Sort(rows, "name", true)) == "ana,Bia,Caio", "by name A to Z, case aside")
check(names(RM.Sort(rows, "name", false)) == "Caio,Bia,ana", "and Z to A")
check(names(RM.Sort(rows, "rankDays", false)) == "Caio,Bia,ana", "days in rank, longest first, unknown last")
check(names(RM.Sort(rows, "rankDays", true)) == "Bia,Caio,ana", "shortest first, unknown still last")
check(names(RM.Sort(rows, "joined", true)) == "Caio,Bia,ana", "joined, oldest first, unknown last")
check(names(RM.Sort(rows, "rank", true)) == "ana,Bia,Caio", "by rank")

check(RM.MatchVia({ note = "Healer main" }, "healer") == "note" and RM.MatchVia({ officerNote = "loot ban" }, "ban") == "onote"
  and RM.MatchVia({ main = "Thrandor" }, "thran") == "main" and RM.MatchVia({ nick = "Padre" }, "padre") == "nick"
  and RM.MatchVia({ note = "x" }, "y") == nil and RM.MatchVia({ note = "x" }, "") == nil, "what a search matched by")
check(RM.ViaText("main", "Bob") == "Alt of Bob" and RM.ViaText("onote") == "officer note", "and the tag that says so")

-- ── 2. The audit on the live roster ─────────────────────────────────────
local function setRoster(list) roster = list; RM:Invalidate() end
setRoster({
  { "Arthas",  1, 70, true },                                   -- me: exact date, a main with an alt
  { "Bob",     3, 70, false, 40 },                              -- alt of Arthas, only seen by Guild OS
  { "Cara",    3, 70, true,  nil, "Entrou 05/03/24", "" },      -- exact 02/03/24, public note says 05
  { "Dino",    4, 68, false, 10, "", "01/03/24 trial" },        -- exact 02/03/24, officer note says 01
  { "Eva",     2, 70, false, 5 },                               -- no history at all
})
local h = GuildOS.db.memberHistory
h[K("Arthas")] = { stints = { { joinAt = ago(700) } }, ranks = { { at = ago(300), to = "Officer" } } }
h[K("Bob")] = { stints = { { joinAt = ago(30), joinEst = true } } }
h[K("Cara")] = { stints = { { joinAt = exact } }, ranks = { { at = ago(200), to = "Member" } } }
h[K("Dino")] = { stints = { { joinAt = exact } } }
GuildOS.db.altLinks = { [K("Bob")] = K("Arthas") }
MM:SetNick(K("Eva"), "Evinha")

local a = RM:Audit()
local by = {}
for _, r in ipairs(a.rows) do by[r.name] = r end
check(by.Arthas == nil, "a member with nothing to fix is not listed")
check(by.Bob and by.Bob.problems.nodate and not by.Bob.problems.noalt, "an alt only seen by Guild OS: no real date, linked")
check(by.Cara.problems.notediff and by.Cara.noteDiff.which == "public" and by.Cara.problems.noalt, "Cara's public note differs")
check(by.Dino.problems.notediff and by.Dino.noteDiff.which == "officer", "Dino's officer note differs")
check(by.Eva.problems.nodate and by.Eva.problems.noalt and by.Eva.nick == "Evinha", "Eva: nothing known, and her nickname")
check(a.counts.all == 4 and a.counts.nodate == 2 and a.counts.noalt == 3 and a.counts.notediff == 2, "the counts")
check(by.Cara.rankDays == 200 and by.Dino.rankDays == RM.Days(exact, NOW) and by.Eva.rankDays == nil, "days in the current rank")
check(RM:Audit() == a, "a second look within the cache is the same audit")
roster[3][6] = "02/03/24"
check(RM:Audit() == a, "the cache holds until invalidated")
RM:Invalidate()
a = RM:Audit()
by = {}
for _, r in ipairs(a.rows) do by[r.name] = r end
check(not by.Cara.problems.notediff and a.counts.notediff == 1, "invalidated, the fixed note is no difference")
viewOfficer = false
a = RM:Audit(true)
check(a.counts.notediff == 0, "a rank that cannot read officer notes compares only the public one")
viewOfficer = true
myRank = 3
check(#RM:Audit(true).rows == 0, "not an officer: no audit")
myRank = 1
roster[3][6] = "Entrou 05/03/24"
a = RM:Audit(true)
by = {}
for _, r in ipairs(a.rows) do by[r.name] = r end

-- ── 3. The actions call the existing flows ──────────────────────────────
check(RM:WriteDate(by.Bob) and opened[#opened] == "management/marks", "Write date opens Notes and marks")
check(ND:TakePrefill() == "Bob" and ND:TakePrefill() == nil, "with the member in its box, once")
check(RM:LinkAlt(by.Eva) and shown[#shown].name == "Eva" and shown[#shown].focus == "alt", "Link alt opens the member on Add alt")
check(RM:Open(by.Dino) and shown[#shown].name == "Dino" and shown[#shown].focus == nil, "a row's click opens the member")
ND:SetFormat("dd/mm/yy")
writes = {}
local asked
function GuildOS:ShowDialog(name, _, _, data) asked = { name = name, data = data } end
RM:FixNote(by.Dino)
check(#writes == 0 and asked and asked.name == "GUILDOS_NOTE_DATE_REPLACE" and asked.data.which == "officer"
  and asked.data.text == "02/03/24 trial", "Fix note asks before it replaces the officer note's date: " .. tostring(asked and asked.data.text))
ND:ConfirmWrite(asked.data)
check(#writes == 1 and writes[1].public == false and roster[4][7] == "02/03/24 trial", "and, confirmed, writes the history's day")
-- The public note that differs is the one written, whatever the setting says.
ND:SetTarget("officer")
writes = {}
check(ND:WriteOne("Cara", true, "public") and writes[1] and writes[1].public, "WriteOne takes the note to write")

-- ── 4. Time in rank and in the guild: rules, preset, suggestion ─────────
local r = BA.Rules({ rankDaysMin = "30", tenureDaysMin = "0" })
check(r.rankDaysMin == 30 and r.tenureDaysMin == nil and BA.HasRule(r), "days in rank is a rule; 0 days in the guild is none")
check(not BA.HasRule(BA.Rules({ countAlts = true, wholeGroup = true })), "the alts' options are no rule of their own")
check(BA.Meets({ rankDays = 40 }, r) and not BA.Meets({ rankDays = 20 }, r) and not BA.Meets({}, r), "an unknown time meets no rule")
r = BA.Rules({ tenureDaysMin = 365 })
check(BA.Meets({ tenureDays = 700 }, r) and not BA.Meets({ tenureDays = 100 }, r), "days in the guild")
local members = BA:Collect(false)
local col = {}
for _, m in ipairs(members) do col[m.name] = m end
check(col.Cara.rankDays == 200 and col.Arthas.tenureDays == 700 and col.Eva.rankDays == nil, "the roster's lines carry them")
local list = BA.Match(members, BA.Rules({ rankDaysMin = 100 }), "promote", BA:Context())
check(#list == 2 and list[1].name ~= "Arthas", "promote who has been 100+ days in the rank (never oneself)")

check(MP.TYPES.promote_rank_time and MP.TYPE_ORDER[4] == "promote_rank_time", "the ready preset")
local preset = { type = "promote_rank_time", thresholds = { days = 100, rankIndex = 3, tenureDays = 0 } }
local br = MP.BulkRules(preset)
check(br.rank == 3 and br.rankDaysMin == 100 and br.tenureDaysMin == nil, "its rules: the rank and the days")
local m2 = MP.Match(preset, members, BA:Context(), 1)
check(#m2 == 1 and m2[1].name == "Cara", "Cara, a Member for 200 days")
preset.thresholds.tenureDays = 1000
check(#MP.Match(preset, members, BA:Context(), 1) == 0, "and the days in the guild too")
check(MP:Summarize(preset):find("Member for 100+ days", 1, true), "its summary names the rank")
GuildOS.db.modPresets = nil
MP:Initialize()
local seeded = 0
for _, x in ipairs(GuildOS.db.modPresets) do if x.type == "promote_rank_time" then seeded = seeded + 1 end end
check(seeded == 1, "seeded in a new guild")
GuildOS.db.modPresets, GuildOS.db.modPresetsRankTime = { { type = "purge_inactive", thresholds = { days = 30 } } }, nil
MP:Initialize()
MP:Initialize()
check(#GuildOS.db.modPresets == 2 and GuildOS.db.modPresets[2].type == "promote_rank_time", "and added once to an older guild")

GuildOS.db.settings.stuckRankDays = 150
local stuck = RM:StuckInRank()
-- Dino (Initiate) has been one since 2024 too: both, the longest first; Eva (Veteran) is a step from officer: never.
check(#stuck == 2 and stuck[1].name == "Dino" and stuck[2].name == "Cara" and stuck[2].rankDays == 200, "long in rank, the longest first")
check(GM:GetSuggestions().stuckInRank[2].name == "Cara", "in the suggestions")
canPromote = false
check(#RM:StuckInRank() == 0 and #GM:GetSuggestions().stuckInRank == 0, "only for a rank that may promote")
canPromote = true
GuildOS.TrialTracker = { IsTrial = function(_, k) return k == K("Cara") end }
check(#RM:StuckInRank() == 1 and RM:StuckInRank()[1].name == "Dino", "never a trial")
GuildOS.TrialTracker = nil
GuildOS.db.settings.stuckRankDays = nil

-- ── 5. Inactivity per player ────────────────────────────────────────────
setRoster({
  { "Arthas", 1, 70, true },
  { "Main",   3, 70, false, 3 },     -- seen 3 days ago
  { "Alt",    3, 70, false, 60 },    -- its alt, 60 days away
  { "Gone",   3, 70, false, 90 },    -- main of Gone2, both away
  { "Gone2",  4, 70, false, 45 },
  { "Solo",   3, 70, false, 40 },
})
GuildOS.db.altLinks = { [K("Alt")] = K("Main"), [K("Gone2")] = K("Gone") }
local function inactive(...)
  local o = {}
  for _, m in ipairs(GM:GetInactiveMembers(...)) do o[#o + 1] = m.name end
  return table.concat(o, ",")
end
check(RM:CountAlts(), "counting the player's alts is on by default")
check(inactive(30) == "Gone,Gone2,Solo", "an alt whose main was seen is not inactive: " .. inactive(30))
check(inactive(30, false) == "Gone,Alt,Gone2,Solo", "off: every character on its own: " .. inactive(30, false))
local gone
for _, m in ipairs(GM:GetInactiveMembers(30, false)) do if m.name == "Alt" then gone = m end end
check(gone.seen and gone.seen.name == "Main" and gone.seen.main and RM.SeenText(gone.seen) == "main Main seen 3d ago",
  "the list says which was seen")
RM:SetCountAlts(false)
check(inactive(30) == "Gone,Alt,Gone2,Solo" and GuildOS.db.settings.inactiveCountAlts == false, "the screen's setting")
RM:SetCountAlts(true)

members = BA:Collect(false)
local function pick(raw, action)
  local o = {}
  for _, m in ipairs((BA.Match(members, BA.Rules(raw), action or "remove", BA:Context()))) do o[#o + 1] = m.name end
  table.sort(o)
  return table.concat(o, ",")
end
check(pick({ days = 30 }) == "Alt,Gone,Gone2,Solo", "without the option the rule reads the character")
check(pick({ days = 30, countAlts = true }) == "Gone,Gone2,Solo", "with it, the player")
check(pick({ days = 50 }) == "Alt,Gone" and pick({ days = 50, countAlts = true }) == "",
  "Gone, 90 days away, stays while its alt Gone2 was seen 45 days ago")
check(pick({ days = 50, wholeGroup = true }) == "", "whole group: Alt stays while Main was seen, Gone waits for Gone2")
check(pick({ days = 40, wholeGroup = true }) == "Gone,Gone2,Solo", "every character out: the whole group goes")
local whole = BA.Match(members, BA.Rules({ days = 40, rank = 3, wholeGroup = true }), "remove", BA:Context())
local via = {}
for _, m in ipairs(whole) do via[m.name] = m.viaGroup or false end
check(via.Gone == false and via.Gone2 == true and via.Solo == false, "the rank rule picks Gone; Gone2 comes with its group")
check(pick({ days = 50, wholeGroup = true }, "promote") == "Alt,Gone", "only a removal takes groups")

-- The queue checks again at each click: Gone2 seen since, Gone stays.
GuildOS.Compat.SecureGuildMacro = function() return true end
check(BA:Start({ days = 40, wholeGroup = true }, "remove", true), "a removal by days with the whole group")
roster[5][4] = true    -- Gone2 logs in
local cur = BA:Current()
check(cur and cur.name == "Solo", "Gone and Gone2 are skipped: the group is no longer all out (" .. tostring(cur and cur.name) .. ")")
BA:Stop()
roster[5][4] = false
check(BA:Start({ days = 30, countAlts = true }, "remove", true), "a removal counting the alts")
roster[4][4] = true   -- Gone logs in: Gone2 is no longer inactive as a player
local seenNames = {}
while BA:Current() do
  local it = BA:Current()
  seenNames[#seenNames + 1] = it.name
  it.status = "done"
end
check(table.concat(seenNames, ",") == "Solo", "an alt whose main logged in since is skipped at its click: " .. table.concat(seenNames, ","))
BA:Stop()
roster[4][4] = false
GuildOS.db.settings.bulkWholeGroup = nil
check(not RM:WholeGroup() and RM:SetWholeGroup(true) and RM:WholeGroup(), "the whole-group option: off by default")

-- ── 6. The global search ────────────────────────────────────────────────
setRoster({
  { "Arthas", 1, 70, true, nil, "", "" },
  { "Healz",  3, 70, true, nil, "melhor healer", "" },
  { "Bob",    3, 70, false, 3, "", "cuidado loot" },
  { "Bobalt", 4, 70, false, 3, "", "" },
  { "Padrin", 3, 70, false, 3, "", "" },
})
GuildOS.db.altLinks = { [K("Bobalt")] = K("Arthas") }
MM:SetNick(K("Padrin"), "Padre")
GuildOS.RaidTracker = nil
local function found(q)
  local o = {}
  for _, m in ipairs(Search:Query(q).members) do o[#o + 1] = m.name .. (m.via and (":" .. m.via) or "") end
  return table.concat(o, ",")
end
Search = GuildOS.Search
check(found("healer") == "Healz:note", "the public note: " .. found("healer"))
check(found("cuidado") == "Bob:onote", "the officer note, for a rank that reads it")
viewOfficer = false
check(found("cuidado") == "", "never for one that cannot")
viewOfficer = true
check(found("arth") == "Arthas,Bobalt:main", "the main's name finds the alt, after the name match: " .. found("arth"))
check(found("padre") == "Padrin:nick", "the nickname")
check(Search:Query("healer").members[1].sub:find("note", 1, true), "the line says why")

-- ── 7. The roster export ────────────────────────────────────────────────
GuildOS.db.memberHistory[K("Healz")] = { stints = { { joinAt = ago(50), joinEst = true } }, ranks = { { at = ago(20), to = "Member" } } }
roster[2][6] = "melhor\thealer"
local headers, out = GuildOS.Exporter:RosterData()
local hi = {}
for i, hname in ipairs(headers) do hi[hname] = i end
check(hi.Main and hi.JoinDate and hi.DaysInRank and hi.PublicNote and hi.OfficerNote == #headers, "the new columns, the officer note last")
local rowOf = {}
for _, row in ipairs(out) do rowOf[row[1]] = row end
check(rowOf.Bobalt[hi.Main] == "Arthas" and rowOf.Arthas[hi.Main] == "", "the main, for an alt")
check(rowOf.Healz[hi.JoinDate] == "~" .. date("%Y-%m-%d", ago(50)) and rowOf.Healz[hi.DaysInRank] == 20, "the join date (~ seen) and days in rank")
check(rowOf.Healz[hi.PublicNote] == "melhor healer" and rowOf.Bob[hi.OfficerNote] == "cuidado loot", "the notes, a tab made a space")
for _, row in ipairs(out) do check(#row == #headers, "every row lines up with the header") end
viewOfficer = false
headers, out = GuildOS.Exporter:RosterData()
check(headers[#headers] == "PublicNote" and #out[1] == #headers, "no officer note for a rank that cannot read it")
viewOfficer = true
check(GuildOS.Exporter:Build("roster", "tsv"):find("melhor healer", 1, true), "and the TSV keeps one cell per note")

print("roster-audit: " .. checks .. " checks passed")
