-- Public note writes (issue #5), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua and Modules/NoteCommand.lua under a
-- stubbed guild roster.
--
-- TBC Anniversary 2.5.6 documents C_GuildInfo.SetNote(guid, note, isPublic)
-- and not the old GuildRosterSetPublicNote global the addon called, so the
-- !note command failed without a word. This proves the write goes through
-- whichever API the client has, falls back when the row has no GUID, refuses
-- with a reason when it cannot write, keeps the name-resolution rule and the
-- sanitizer, and that the right person is told why: the member who typed a
-- !note their character cannot apply, or the officer whose client tried.
--
--   luajit -e 'ADDON="."' tools/public-note.lua
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
local printed, handlers, timers = {}, {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) handlers[#handlers + 1] = fn end
  return f
end
function GetServerTime() return 1757800000 end
function IsInGuild() return true end
function hooksecurefunc() end
function debugstack() return "" end
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
function UnitName(unit) if unit == "player" then return "Ana" end end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
-- Translations are marked, so a message that skips L[...] shows up.
GuildOS = { L = setmetatable({}, { __index = function(_, k) return "«" .. k .. "»" end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/NoteCommand.lua")
local Compat, NoteCommand = BRutus.Compat, BRutus.NoteCommand
local logged = {}
BRutus.GuildManager = { LogAction = function(_, action, who, what) logged[#logged + 1] = { action, who, what } end }

-- ── A roster, the note APIs and the permission, per case ────────────────
local ROSTER, writes, canEdit = {}, {}, true
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if not r then return nil end
  -- name, rank, rankIndex, level, class, zone, publicNote, officerNote, online,
  -- status, classFile, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid
  return r.name, "Raider", 4, 70, "Priest", "Shattrath", r.note or "", "", true,
    0, "PRIEST", 0, 0, false, false, 0, r.guid
end

local function client(state)
  ROSTER, writes, printed, timers = state.roster, {}, {}, {}
  if state.noNamespace then
    C_GuildInfo = nil
  else
    C_GuildInfo = state.setNote
      and { SetNote = function(guid, note, isPublic) writes[#writes + 1] = { "SetNote", guid, note, isPublic } end }
      or {}
  end
  GuildRosterSetPublicNote = state.global
    and function(idx, note) writes[#writes + 1] = { "global", idx, note } end
    or nil
  canEdit = state.canEdit ~= false
  CanEditPublicNote = (state.canEdit ~= "missing") and function() return canEdit end or nil
end

local function said(fragment)
  for _, line in ipairs(printed) do
    if tostring(line):find(fragment, 1, true) then return true end
  end
  return false
end

local ANA = { { name = "Ana-Firemaw", guid = "Player-4395-0A1B2C3D", note = "old" } }
local NO_GUID = { { name = "Ana-Firemaw", note = "old" } }
local TWO_BOBS = {
  { name = "Bob-RealmA", guid = "Player-1-000A", note = "a" },
  { name = "Bob-RealmB", guid = "Player-2-000B", note = "b" },
}

-- ── 1. The three API states ─────────────────────────────────────────────
client({ roster = ANA, setNote = true, global = true })
local ok, why = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == true and why == nil and #writes == 1, "with C_GuildInfo.SetNote the note is written once")
check(writes[1][1] == "SetNote" and writes[1][2] == "Player-4395-0A1B2C3D" and writes[1][3] == "LFG Kara" and writes[1][4] == true,
  "C_GuildInfo.SetNote gets the member's GUID, the note and isPublic = true")

client({ roster = ANA, setNote = false, global = true })
ok = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == true and #writes == 1 and writes[1][1] == "global" and writes[1][2] == 1 and writes[1][3] == "LFG Kara",
  "without C_GuildInfo.SetNote the old global gets the roster index")
client({ roster = ANA, noNamespace = true, global = true })
ok = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == true and #writes == 1 and writes[1][1] == "global", "a client without C_GuildInfo at all uses the old global")
client({ roster = ANA, noNamespace = true, global = false })
ok, why = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == false and why == "no-api", "a client with neither C_GuildInfo nor the old global: no-api, without raising")

client({ roster = ANA, setNote = false, global = false })
ok, why = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == false and why == "no-api" and #writes == 0, "with neither API nothing is written: no-api")

-- A row without a GUID: the old global when it exists, otherwise refuse.
client({ roster = NO_GUID, setNote = true, global = true })
ok = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == true and #writes == 1 and writes[1][1] == "global", "a row without a GUID falls back to the old global")
client({ roster = NO_GUID, setNote = true, global = false })
ok, why = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == false and why == "no-guid" and #writes == 0, "a row without a GUID and no old global: no-guid")
client({ roster = NO_GUID, setNote = false, global = false })
ok, why = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == false and why == "no-api", "no GUID and neither API: no-api, not no-guid")

-- ── 2. Permission, checked before the name ──────────────────────────────
client({ roster = ANA, setNote = true, global = true, canEdit = false })
ok, why = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == false and why == "no-permission" and #writes == 0, "without the permission nothing is written: no-permission")
client({ roster = ANA, setNote = true, global = true, canEdit = "missing" })
ok, why = Compat.SetGuildPublicNote("Ana", "LFG Kara", "Firemaw")
check(ok == false and why == "no-permission" and #writes == 0, "a client without CanEditPublicNote: no-permission")
client({ roster = TWO_BOBS, setNote = true, canEdit = false })
ok, why = Compat.SetGuildPublicNote("Bob", "x")
check(ok == false and why == "no-permission", "the permission is checked before the name: an ambiguous name still says no-permission")

-- ── 3. Name resolution (rule unchanged) ─────────────────────────────────
client({ roster = TWO_BOBS, setNote = true })
ok, why = Compat.SetGuildPublicNote("Bob", "x")
check(ok == false and why == "ambiguous" and #writes == 0, "a short name matching two members: ambiguous, nothing written")
ok = Compat.SetGuildPublicNote("Bob", "x", "RealmB")
check(ok == true and writes[1][2] == "Player-2-000B", "an exact Name-Realm picks that member")
client({ roster = TWO_BOBS, setNote = true })
ok, why = Compat.SetGuildPublicNote("Carl", "x")
check(ok == false and why == "absent" and #writes == 0, "a name nobody has: absent")
ok, why = Compat.SetGuildPublicNote("", "x")
check(ok == false and why == "absent", "an empty name: absent")

local idx, reason = Compat.FindGuildRosterIndex("Bob")
check(idx == nil and reason == "ambiguous", "FindGuildRosterIndex says ambiguous")
idx, reason = Compat.FindGuildRosterIndex("Carl")
check(idx == nil and reason == "absent", "FindGuildRosterIndex says absent")
idx, reason = Compat.FindGuildRosterIndex(nil)
check(idx == nil and reason == "absent", "FindGuildRosterIndex with no name says absent, without raising")
check(Compat.FindGuildRosterIndex("Bob", "RealmA") == 1, "FindGuildRosterIndex still returns the index alone on a match")
local note, noteWhy = Compat.GetGuildPublicNote("Bob")
check(note == nil and noteWhy == "ambiguous", "GetGuildPublicNote passes the reason on")
check(Compat.GetGuildPublicNote("Bob", "RealmB") == "b", "GetGuildPublicNote still returns the note")

-- ── 4. The note text ────────────────────────────────────────────────────
client({ roster = ANA, setNote = true })
Compat.SetGuildPublicNote("Ana", "|cffFF0000LFG|r Kara", "Firemaw")
check(writes[1][3] == "cffFF0000LFGr Kara", "UI escapes are stripped before the write")
client({ roster = ANA, setNote = true })
Compat.SetGuildPublicNote("Ana", string.rep("x", 30) .. "\195\167ao", "Firemaw")
check(writes[1][3] == string.rep("x", 30), "the 31-byte cap does not split a codepoint")
client({ roster = ANA, setNote = true })
Compat.SetGuildPublicNote("Ana", string.rep("y", 31), "Firemaw")
check(writes[1][3] == string.rep("y", 31), "a 31-byte note is written whole")
client({ roster = ANA, setNote = true })
Compat.SetGuildPublicNote("Ana", string.rep("z", 32), "Firemaw")
check(writes[1][3] == string.rep("z", 31), "a 32-byte note is cut to 31")

-- ── 5. !note tells the officer whose client tried ───────────────────────
client({ roster = ANA, setNote = true })
logged = {}
NoteCommand:_Apply("Ana", "Firemaw", "LFG Kara")
check(#writes == 1 and said("Set Ana's note"), "a successful !note writes and says so")
check(#logged == 1 and logged[1][1] == "note" and logged[1][2] == "Ana-Firemaw" and logged[1][3] == "LFG Kara",
  "a successful !note is logged for the officers, with the member's full name")

client({ roster = { { name = "Ana-Firemaw", guid = "Player-4395-0A1B2C3D", note = "LFG Kara" } }, setNote = true })
NoteCommand:_Apply("Ana", "Firemaw", "LFG Kara")
check(#writes == 0 and #printed == 0, "a note that already reads that way is left alone, silently")

client({ roster = TWO_BOBS, setNote = true })
NoteCommand:_Apply("Bob", nil, "x")
check(#writes == 0 and said("more than one guild member has that name"), "an ambiguous !note says so")
check(said("«Could not set Bob's note"), "the refusal goes through the translation table")

client({ roster = TWO_BOBS, setNote = true })
NoteCommand:_Apply("Carl", nil, "x")
check(#writes == 0 and said("not found in the guild roster"), "a !note for somebody not on the roster says so")

client({ roster = {}, setNote = true })
NoteCommand:_Apply("Ana", "Firemaw", "LFG Kara")
check(#writes == 0 and #printed == 0, "while the roster is still empty, not-found stays silent")

client({ roster = ANA, setNote = false, global = false })
NoteCommand:_Apply("Ana", "Firemaw", "LFG Kara")
check(#writes == 0 and said("no public note API"), "a client with no note API says so")

client({ roster = NO_GUID, setNote = true, global = false })
NoteCommand:_Apply("Ana", "Firemaw", "LFG Kara")
check(#writes == 0 and said("did not return the member's GUID"), "a row without a GUID says so")

-- Losing the permission between the chat line and the write (a rank change in the jitter window).
client({ roster = TWO_BOBS, setNote = true, canEdit = false })
NoteCommand:_Apply("Bob", nil, "x")
check(#writes == 0 and said("can no longer edit public notes") and not said("more than one"),
  "an officer who lost the permission is told that, before any name lookup")

-- ── 6. The chat hook: who is told when the client cannot write ──────────
BRutus.db = { noteCommand = { enabled = true } }
NoteCommand._cd = {}
NoteCommand:_SetupHook()
local onEvent = handlers[#handlers]
check(type(onEvent) == "function", "the hook listens to guild chat")

client({ roster = ANA, setNote = true, canEdit = false })
onEvent(nil, "CHAT_MSG_GUILD", "!note LFG Kara", "Bob-RealmA")
check(#printed == 0 and #timers == 0 and #writes == 0,
  "another member's !note on a client without the permission: silent, nothing scheduled")

client({ roster = ANA, setNote = true, canEdit = false })
onEvent(nil, "CHAT_MSG_GUILD", "!note LFG Kara", "Ana-Firemaw")
check(#printed == 1 and said("«You cannot edit public notes. Only an officer who is online now and running Guild OS can apply !note; if none is, type it again later.»")
  and #timers == 0 and #writes == 0,
  "the member who typed a !note their character cannot apply is told, once, on their own client, that only an officer online now can")

client({ roster = ANA, setNote = true })
onEvent(nil, "CHAT_MSG_GUILD", "!note LFG Kara", "Ana-Firemaw")
check(#printed == 0 and #timers == 2, "with the permission, the write is scheduled after the jitter (and the sender cooldown)")
for _, fn in ipairs(timers) do fn() end
check(#writes == 1 and writes[1][3] == "LFG Kara", "the scheduled write happens")

BRutus.db.noteCommand.enabled = false
client({ roster = ANA, setNote = true, canEdit = false })
onEvent(nil, "CHAT_MSG_GUILD", "!note LFG Kara", "Ana-Firemaw")
check(#printed == 0 and #timers == 0, "with !note turned off, even the member's own line prints and schedules nothing")
client({ roster = ANA, setNote = true })
onEvent(nil, "CHAT_MSG_GUILD", "!note LFG Kara", "Bob-RealmA")
check(#printed == 0 and #timers == 0 and #writes == 0, "with !note turned off, an officer's client schedules no write either")
BRutus.db.noteCommand.enabled = true

print(("public-note: %d checks passed"):format(checks))
