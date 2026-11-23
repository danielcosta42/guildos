-- Officers' tools on the notes (issue #429, epic #423 group F), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Core/WhisperQueue.lua, Modules/GuildManager.lua, Modules/RosterLog.lua,
-- Modules/MemberHistory.lua, Modules/MemberMarks.lua, Modules/NoteDates.lua, Modules/BulkActions.lua and
-- Modules/ChatTweaks.lua under a stubbed TBC Anniversary client.
--
--   * The date parser: dd/mm/yy, dd.mm.yyyy, yyyy-mm-dd, "Joined: ...", day and month by the language or
--     the officer's choice, a number above 12 deciding, impossible days refused.
--   * Writing: never past 31 bytes, nothing taken away without a confirmation, a note that says it left
--     alone, a run spaced and slowed down by the throttle, a forbidden write turned into "copy the text".
--   * The import: a review first; only new and earlier dates taken, as "seen", and the game's exact line
--     still wins.
--   * The safe list: marked or tagged members never in a removal or demotion preview, nor at their click.
--   * Back after N days offline: one line to the officer, once a return, with the threshold.
--   * Nicknames: synced between officers (later wins, officers only), in the chat prefix.
--
--   luajit -e 'ADDON="."' tools/note-dates.lua
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
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(ev) self.events[ev] = true end
  function f:SetScript(_, fn) self.onEvent = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
  end
end
function hooksecurefunc() end
function debugstack() return "" end
WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, 5
function GetBuildInfo() return "2.5.5", "65000", "", 20505 end
function GetRealmName() return "Dreamscythe" end
local locale = "ptBR"
function GetLocale() return locale end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
date, time = os.date, os.time
local NOW = os.time({ year = 2026, month = 11, day = 23, hour = 12 })
function GetServerTime() return NOW end
local CLOCK = 1000
function GetTime() return CLOCK end
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end,
            NewTicker = function() return { Cancel = function() end } end }
local function runTimers()
  local list = timers
  timers = {}
  for _, t in ipairs(list) do t.fn() end
  return list
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
function CanGuildPromote() return true end
function CanGuildDemote() return true end
function CanGuildRemove() return true end
local editPublic, editOfficer, viewOfficer = true, true, true
function CanEditPublicNote() return editPublic end
function CanEditOfficerNote() return editOfficer end
function CanViewOfficerNote() return viewOfficer end

-- { name, rankIndex, level, online, daysOffline, note, onote }
local roster = {}
local writes = {}
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
local forbid = false
function GuildRosterSetPublicNote(i, note)
  writes[#writes + 1] = { i = i, note = note, public = true }
  if forbid then fire("ADDON_ACTION_FORBIDDEN", "GuildOS", "GuildRosterSetPublicNote()") return end
  roster[i][6] = note
end
function GuildRosterSetOfficerNote(i, note)
  writes[#writes + 1] = { i = i, note = note, public = false }
  if forbid then fire("ADDON_ACTION_FORBIDDEN", "GuildOS", "GuildRosterSetOfficerNote()") return end
  roster[i][7] = note
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/WhisperQueue.lua")
dofile(ADDON .. "/Modules/GuildManager.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
dofile(ADDON .. "/Modules/MemberHistory.lua")
dofile(ADDON .. "/Modules/MemberMarks.lua")
dofile(ADDON .. "/Modules/NoteDates.lua")
dofile(ADDON .. "/Modules/BulkActions.lua")
dofile(ADDON .. "/Modules/ChatTweaks.lua")
function GuildOS:IsOnGuildDB() return true end
GuildOS.isGuilded = true
GuildOS.Compat.PlayerName = function() return "Arthas" end
local published = {}
GuildOS.SyncService = { Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end,
                        On = function() end }
GuildOS.db = { settings = {}, members = {}, rosterLog = { events = {} }, memberHistory = {}, memberHistoryOut = {} }
local ND, MM, MH, BA, CT = GuildOS.NoteDates, GuildOS.MemberMarks, GuildOS.MemberHistory, GuildOS.BulkActions, GuildOS.ChatTweaks
ND:Initialize()
MM:Initialize()
BA:Initialize()
local K = function(n) return GuildOS:GetPlayerKey(n) end

-- ── 1. The parser ───────────────────────────────────────────────────────
local function ymd(text, order)
  local d = ND.Parse(text, order, 2026)
  return d and string.format("%04d-%02d-%02d", d.year, d.month, d.day) or nil
end
check(ymd("03/02/25", "dmy") == "2025-02-03", "dd/mm/yy, day first")
check(ymd("03/02/25", "mdy") == "2025-03-02", "the same date month first")
check(ymd("13/02/25", "mdy") == "2025-02-13", "a number above 12 is the day, whatever the order")
check(ymd("02/13/25", "dmy") == "2025-02-13", "and the other way round")
check(ymd("03.02.2025", "mdy") == "2025-02-03", "dd.mm.yyyy is day first everywhere")
check(ymd("03.02.25", "mdy") == "2025-02-03", "and dd.mm.yy")
check(ymd("2025-02-03", "mdy") == "2025-02-03", "yyyy-mm-dd")
check(ymd("2025/2/3", "dmy") == "2025-02-03", "yyyy/m/d")
check(ymd("Joined: 03/02/2025", "dmy") == "2025-02-03", "\"Joined: ...\" with a four-digit year")
check(ymd("tank main - Joined: 5/6/24", "mdy") == "2024-05-06", "a date after other text")
local _, s, e = ND.Parse("tank Joined: 03/02/25 ok", "dmy", 2026)
check(s == 6 and e == 21, "the span takes in the \"word:\" before the date")
check(ymd("31/02/25", "dmy") == nil and ymd("29/02/25", "dmy") == nil and ymd("29/02/24", "dmy") == "2024-02-29",
  "an impossible day is no date; a leap day is one")
check(ymd("12/31/99", "mdy") == nil, "a year after maxYear is no date (20yy)")
check(ymd("01/02/2003", "dmy") == nil, "before the game, no guild")
check(ymd("12025-01-02", "dmy") == nil and ymd("ilvl 115/120", "dmy") == nil and ymd("", "dmy") == nil,
  "a number cut in two, a fraction or nothing are no date")
check(ymd("1/2/25 and 2025-06-07", "dmy") == "2025-02-01", "the first date written wins")
check(ND.DefaultOrder("enUS") == "mdy" and ND.DefaultOrder("ptBR") == "dmy" and ND.DefaultOrder("deDE") == "dmy",
  "the order by the client's language")

-- ── 2. Writing a date into a note: 31 bytes, nothing taken without asking ─
local day = { year = 2025, month = 2, day = 3 }
check(ND.Format(day, "dd/mm/yy") == "03/02/25" and ND.Format(day, "mm/dd/yy") == "02/03/25"
  and ND.Format(day, "dd.mm.yyyy") == "03.02.2025" and ND.Format(day, "yyyy-mm-dd") == "2025-02-03",
  "every format")
check(ND.Format(day, "dd/mm/yy", true) == "Joined: 03/02/25", "with the label")
local piece = "03/02/25"
local t, how = ND.Compose("", piece, "dmy", 2026)
check(t == piece and how == "write", "an empty note gets the date")
t, how = ND.Compose("tank", piece, "dmy", 2026)
check(t == "tank 03/02/25" and how == "append", "a note with room keeps its text, the date after it")
t, how = ND.Compose("tank 03/02/25", piece, "dmy", 2026)
check(how == "same", "a note that already says it is left alone")
t, how = ND.Compose("tank Joined: 01/01/24", "Joined: 03/02/25", "dmy", 2026)
check(t == "tank Joined: 03/02/25" and how == "replace" and not ND.Silent(how), "another date is swapped only from a confirmation")
local long = string.rep("x", 28)
t, how = ND.Compose(long, piece, "dmy", 2026)
check(#t <= 31 and how == "full" and not ND.Silent(how) and t:sub(-8) == piece, "no room: the cut is asked about, and fits")
t = ND.Compose("caf\195\169 " .. string.rep("y", 20), "Joined: 03/02/25", "dmy", 2026)
check(#t <= 31, "never past 31 bytes")
for _, cur in ipairs({ "", "a", string.rep("z", 31), "1/1/24 " .. string.rep("w", 24) }) do
  for _, fmt in ipairs(ND.FORMATS) do
    local out = ND.Compose(cur, ND.Format(day, fmt, true), "dmy", 2026)
    check(#out <= 31, "31 bytes, note '" .. cur .. "', " .. fmt)
  end
end

-- ── 3. One member, then the whole guild ─────────────────────────────────
roster = {
  { "Arthas", 1, 70, true, 0, "", "" },
  { "Ana", 3, 70, true, 0, "", "" },
  { "Bob", 3, 70, true, 0, "tank", "main tank" },
  { "Cid", 3, 70, true, 0, "", "Joined: 01/01/24" },
  { "Dan", 4, 60, false, 40, "", string.rep("q", 28) },
  { "Eva", 4, 60, false, 5, "", "" },
}
local h = GuildOS.db.memberHistory
local joinT = os.time({ year = 2025, month = 2, day = 3, hour = 20 })
for _, n in ipairs({ "Ana", "Bob", "Cid", "Dan" }) do MH.ApplyJoin(h, K(n), joinT, false) end
MH.EnsureOpen(h, K("Eva"), NOW - 86400)   -- only seen by GuildOS
check(ND:Target() == "officer", "the officer note by default")
ND:WriteOne("Ana")
check(roster[2][7] == "03/02/25" and said("Set Ana's note"), "Ana's officer note gets the date, in the language's format")
writes = {}
ND:WriteOne("Ana")
check(#writes == 0 and said("already says"), "written again: nothing sent")
ND:WriteOne("Eva")
check(roster[6][7] == "" and said("only knows when it first saw"), "a date GuildOS only saw is not written by default")
local shown
GuildOS.ShowDialog = function(_, which, text, _, data) shown = { which = which, text = text, data = data } end
ND:WriteOne("Cid")
check(roster[4][7] == "Joined: 01/01/24" and shown and shown.which == "GUILDOS_NOTE_DATE_REPLACE",
  "another date in the note: asked first, nothing written")
roster[4][7] = "Joined: 01/01/24 x"
ND:ConfirmWrite(shown.data)
check(roster[4][7] == "Joined: 01/01/24 x" and said("changed meanwhile"), "a note that changed since the question is asked again")
roster[4][7] = "Joined: 01/01/24"
ND:ConfirmWrite(shown.data)
check(roster[4][7] == "Joined: 03/02/25", "confirmed: exactly what the question showed")

ND:SetTarget("public")
ND:SetLabel(true)
local plan, left = ND:Plan()
local names = {}
for _, it in ipairs(plan) do names[#names + 1] = it.name .. ":" .. it.how end
check(table.concat(names, ",") == "Ana:write,Bob:append,Cid:write,Dan:write", "the whole guild: " .. table.concat(names, ","))
check(left.seen == 1 and left.date == 1, "one only seen, one with no date (this character)")
writes = {}
check(ND:Start(plan), "a run starts")
check(#writes == 0 and #timers == 1 and timers[1].d == ND.GAP, "nothing at once: one write every GAP seconds")
runTimers()
check(#writes == 1 and roster[2][6] == "Joined: 03/02/25", "the first write")
fire("UI_ERROR_MESSAGE", 1, ERR_GENERIC_THROTTLE)
check(ND:Run().gap == ND.GAP * 2, "too fast: the gap doubles")
runTimers()
check(#writes == 1 and timers[1].d == ND.GAP * 2, "the write the throttle hit is re-read, already in: not sent again")
runTimers()
check(roster[3][6] == "tank Joined: 03/02/25", "Bob's text is kept")
runTimers() runTimers()
check(roster[4][6] == "Joined: 03/02/25" and roster[5][6] == "Joined: 03/02/25" and said("Join dates done"), "the run ends")
for _, w in ipairs(writes) do check(#w.note <= 31, "every write within 31 bytes") end

-- A forbidden write: copy the text from then on, one per click.
for _, m in ipairs(roster) do m[6] = "" end
forbid = true
plan = ND:Plan()
ND:Start(plan)
shown = nil
runTimers()
check(ND:Mode() == "copy" and said("does not let an addon write notes"), "forbidden: the run turns into copy the text")
check(ND:Current() and ND:Current().name == "Ana", "the member it was for is next again")
ND:Next()
check(shown and shown.which == "GUILDOS_NOTE_DATE_COPY" and shown.data.text == "Joined: 03/02/25", "a click shows the note to copy")
check(ND:Current().name == "Bob", "and moves on")
ND:Stop()
forbid = false
GuildOS.State.noteDates.forbidden = nil

-- Where the client does not let an addon write (WoW: Forever, retail): copy straight away.
GuildOS.Client.isAnniversary = false
check(ND:Mode() == "copy", "WoW: Forever: copy the text")
shown = nil
ND:WriteOne("Ana")
check(shown and shown.which == "GUILDOS_NOTE_DATE_COPY", "a one-member write shows the text to copy")
editPublic = false
check(ND:Mode() == nil, "a rank that may not edit the note gets nothing to copy")
editPublic = true
GuildOS.Client.isAnniversary = true

-- ── 4. Reading the dates already in the notes ───────────────────────────
GuildOS.db.memberHistory = {}
h = GuildOS.db.memberHistory
roster = {
  { "Arthas", 1, 70, true, 0, "", "" },
  { "Ana", 3, 70, true, 0, "Joined: 05/06/24", "" },       -- seen later by GuildOS: earlier, taken
  { "Bob", 3, 70, true, 0, "", "2024-01-10" },             -- officer note; exact join known: kept
  { "Cid", 3, 70, true, 0, "13/12/25", "" },               -- seen earlier: later, not taken
  { "Dan", 4, 60, true, 0, "02.03.2025", "" },             -- nothing known: new
}
MH.EnsureOpen(h, K("Ana"), NOW - 10 * 86400)
MH.ApplyJoin(h, K("Bob"), os.time({ year = 2024, month = 3, day = 1, hour = 9 }), false)
MH.EnsureOpen(h, K("Cid"), os.time({ year = 2025, month = 1, day = 1, hour = 9 }))
h[K("Dan")] = { stints = { { } }, ranks = {} }   -- a passage with no start
local imp = ND:ImportPlan("dmy")
local st = {}
for _, it in ipairs(imp) do st[it.name] = it end
check(st.Ana.status == "earlier" and st.Ana.pick, "an earlier date than GuildOS saw is ticked")
check(st.Bob.status == "kept" and not st.Bob.pick and st.Bob.source == "officer", "an exact day is kept; the officer note read too")
check(st.Cid.status == "later" and not st.Cid.pick, "a later date than GuildOS saw is not taken")
check(st.Dan.status == "new" and st.Dan.pick, "an unknown start is new")
st.Dan.pick = false
check(ND:ApplyImport(imp) == 1, "only what stayed ticked goes in")
local ja, est = MH:JoinedAt(K("Ana"))
check(os.date("%Y-%m-%d", ja) == "2024-06-05" and est and MH:JoinedFromNote(K("Ana")), "Ana's day, as seen, from the note")
check(MH:JoinedAt(K("Dan")) == nil, "Dan unticked: unchanged")
check(MH:StintLine(MH:Stints(K("Ana"))[1]):find("from a note", 1, true), "the history says where the day came from")
local exact = os.time({ year = 2024, month = 6, day = 5, hour = 14 })
check(MH.ApplyJoin(h, K("Ana"), exact + 30 * 86400, false) == "refined" and MH:JoinedAt(K("Ana")) == exact + 30 * 86400,
  "the game's exact line still replaces a day read from a note")
check(not MH.ApplyNoteJoin(h, K("Bob"), exact), "a note never replaces an exact join")
-- And the plan writes a date read from a note, though it is "seen".
check(ND:ItemFor("Dan", K("Dan"), "", "", "officer") == nil, "no date, nothing to write")

-- ── 5. The safe list in the bulk actions ────────────────────────────────
roster = {
  { "Arthas", 1, 70, true, 0, "", "" },
  { "Ana", 3, 70, false, 60, "", "" },
  { "Bob", 3, 70, false, 60, "alt [SAFE]", "" },
  { "Cid", 3, 70, false, 60, "", "long leave [safe]" },
  { "Dan", 3, 70, false, 60, "", "" },
}
MM:SetSafe(K("Dan"), true)
local function preview(action)
  local list = BA:Preview({ days = 30 }, action)
  local out = {}
  for _, m in ipairs(list) do out[#out + 1] = m.name end
  table.sort(out)
  return table.concat(out, ",")
end
check(preview("remove") == "Ana", "[safe] in either note, any case, or marked by hand: never in a removal preview")
check(preview("demote") == "Ana", "nor a demotion")
check(preview("promote") == "Ana,Bob,Cid,Dan", "a promotion still may")
MM:SetSafeTag("[keep]")
check(preview("remove") == "Ana,Bob,Cid", "the tag is the officers' choice; the hand mark stays")
MM:SetSafeTag("[safe]")
-- Marked between the preview and the click: skipped at the click.
check(BA:Start({ days = 30 }, "remove", true, { { fullName = "Ana", name = "Ana", key = K("Ana"), rankIndex = 3 } }), "a removal queue")
roster[2][6] = "[safe]"
check(BA:Current() == nil and BA:Queue().items[1].why == "rules", "tagged since: skipped when their click comes")
BA:Stop()

-- ── 6. Back after a long time offline ───────────────────────────────────
GuildOS.db.memberHistory, GuildOS.db.memberHistoryBase, GuildOS.db.memberHistoryMigrated = {}, nil, true
GuildOS.State.memberHistory = { seen = {}, settled = true }
roster = {
  { "Arthas", 1, 70, true, 0, "", "" },
  { "Ana", 3, 70, false, 45, "", "" },
  { "Bob", 3, 70, false, 10, "", "" },
}
MH:Scan()   -- the first look: only the roster is taken
printed = {}
roster[2][4], roster[3][4] = true, true
MH:Scan()
check(said("Back after a long time offline") and said("Ana (45)") and not said("Bob ("), "Ana back after 45 days: one line; Bob's 10 days are not")
printed = {}
MH:Scan()
check(not said("Back after"), "once a return: the next look says nothing")
roster[2][4], roster[2][5] = false, 12
MH:Scan()
roster[2][4] = true
MH:SetBackDays(10)
MH:Scan()
check(said("Ana (12)"), "the threshold is the officers' (10 days)")
MH:SetBackDays(0)
printed = {}
roster[2][4], roster[2][5] = false, 50
MH:Scan()
roster[2][4] = true
MH:Scan()
check(not said("Back after"), "0 turns the line off")
myRank = 3
MH:SetBackDays(5)
check(MH:BackDays() == 0, "a member cannot change it")
myRank = 1

-- ── 7. Nicknames and the marks' sync ────────────────────────────────────
published = {}
check(MM:SetNick(K("Bob"), "Big |cffff0000Bob|r") and MM:Nick(K("Bob")) == "Big cffff0000Bobr", "a nickname, UI escapes out")
check(#published == 1 and published[1].dom == "marks" and published[1].data.items[1].s == "nick", "sent to the officers")
local item = published[1].data.items[1]
check(MM:Apply({ { s = "nick", k = item.k, v = "Old", t = item.t - 10, b = "Jaina" } }, "Jaina") == 0, "an older entry loses")
check(MM:Apply({ { s = "nick", k = item.k, v = "Bobby", t = item.t + 10, b = "Jaina" } }, "Jaina") == 1 and MM:Nick(K("Bob")) == "Bobby",
  "a later one wins")
check(MM:Apply({ { s = "safe", k = K("Ana"), v = "yes", t = NOW }, { s = "x", k = "a", v = true, t = NOW },
  { s = "safe", k = "a|b", v = true, t = NOW }, { s = "safe", k = K("Ana"), v = true, t = NOW + 3600 } }, "Jaina") == 0,
  "bad entries and the future are refused")
check(MM:Apply({ { s = "safe", k = K("Ana"), v = true, t = NOW } }, "Jaina") == 1 and MM:IsMarkedSafe(K("Ana")), "a mark off the network")
check(MM:SetSafe(K("Ana"), false) and not MM:IsMarkedSafe(K("Ana")), "unmarked: a tombstone")
check(MM:Apply({ { s = "safe", k = K("Ana"), v = true, t = NOW - 5 } }, "Jaina") == 0, "an old copy does not bring it back")
myRank = 3
check(MM:Apply({ { s = "nick", k = K("Cid"), v = "C", t = NOW } }, "Jaina") == 0 and not MM:SetNick(K("Cid"), "C"),
  "a member's client keeps none, and writes none")
myRank = 1
published = {}
MM:Backfill()
check(#published == 1 and #published[1].data.items >= 3, "the backfill sends every entry, tombstones included")
-- The chat prefix.
GuildOS.db.chatTweaks = { enabled = true, nick = true, classIcon = false, level = false, altTag = false, whisper = false, group = true }
CT._cache = { Bob = { level = 70, classFile = "WARRIOR", fullKey = K("Bob") } }
local filter = CT:_MakeFilter()
local _, msg = filter(nil, "CHAT_MSG_GUILD", "hi", "Bob")
check(msg and msg:find("Bobby", 1, true) and msg:find("hi$"), "the nickname before a guild line")
local keep = filter(nil, "CHAT_MSG_WHISPER", "hi", "Bob")
check(keep == false and select(2, filter(nil, "CHAT_MSG_WHISPER", "hi", "Bob")) == nil, "whispers off by default")
_, msg = filter(nil, "CHAT_MSG_RAID", "pull", "Bob")
check(msg and msg:find("Bobby", 1, true), "in raid chat when asked")
check(select(2, filter(nil, "CHAT_MSG_PARTY", "x", "Stranger")) == nil, "nobody outside the guild gets a prefix")
local tips = {}
MM:TooltipLines({ AddLine = function(_, l) tips[#tips + 1] = l end }, K("Bob"), "alt [safe]", "")
check(tips[1] == "Nickname: Bobby" and tips[2] == "On the safe list (tag in the note)", "the tooltip's lines")

print(("note-dates: %d checks passed"):format(checks))
