-- A member's rename (specs/salao/log-e-renomes.md), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/CommSystem.lua, Modules/SyncService.lua, Modules/RosterLog.lua, Modules/MemberHistory.lua,
-- Modules/MemberRename.lua, Modules/AltSync.lua, Modules/AltAutoDetect.lua, Modules/BanList.lua,
-- Modules/MemberMarks.lua, Modules/OfficerNotes.lua, Modules/TrialTracker.lua and Modules/Birthdays.lua under a
-- stubbed client.
--
-- The same GUID under a new name moves everything kept by the old key at once (the history, the alt links through
-- AltSync, the ban, the safe mark and nickname, the officer notes and sheet, the trial, the birthday, the raid
-- attendance, first seen) and writes a "rename" line; nobody is asked and the diff records no departure and no
-- join. Without a GUID, one departure and one join that look alike (class, rank, level within one, the same note)
-- are asked about once, through the popup queue; yes moves everything, no is remembered and the next diff records
-- the departure and the join as usual. The player's own rename (AltAutoDetect.PlanRename) is the same plan.
--
--   luajit -e 'ADDON="."' tools/member-rename.lua
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

local DAY = 86400
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local frames = {}
function CreateFrame()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(ev) self.events[ev] = true end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:UnregisterEvent(ev) self.events[ev] = nil end
  frames[#frames + 1] = f
  return f
end
function hooksecurefunc() end
function debugstack() return "" end
function GetBuildInfo() return "1.60.1", "70450", "", 16001 end   -- WoW: Forever: keys are the name alone
WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 1, 5, 99
function GetRealmName() return "Realm" end
local now = 1794139200
function GetServerTime() return now end
local clock = 1
function GetTime() return clock end
local afters = {}
function GuildRoster() end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end }
local function runAfters()
  local list = afters
  afters = {}
  for _, fn in ipairs(list) do fn() end
end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
GameTooltip = { HasScript = function() return true end, HookScript = function() end }
date = os.date
time = os.time
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetLocale() return "enUS" end
function InCombatLockdown() return false end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 60 end

-- The guild: { name, rankName, rankIndex, level, note, officerNote, online, daysOffline, class, guid }.
local ROSTER = {}
local function roster(list) ROSTER = list end
local me = "Off"
function UnitName() return me end
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then
    return r[1], r[2], r[3], r[4], "Class", "", r[5], r[6], r[7], nil, r[9] or "WARRIOR",
      nil, nil, nil, nil, nil, r[10]
  end
end
function GetGuildRosterLastOnline(i)
  local r = ROSTER[i]
  if r and not r[7] then return 0, 0, r[8] or 0, 0 end
end
function CanViewOfficerNote() return true end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", r[2], r[3] end end
  return "Guild", "Member", 5
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local registry, store, n = {}, {}, 0
LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = copy(t); return "s" .. n end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, copy(store[s]) end return false end
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
dofile(ADDON .. "/Modules/MemberHistory.lua")
dofile(ADDON .. "/Modules/MemberRename.lua")
dofile(ADDON .. "/Modules/AltSync.lua")
dofile(ADDON .. "/Modules/AltAutoDetect.lua")
dofile(ADDON .. "/Modules/BanList.lua")
dofile(ADDON .. "/Modules/MemberMarks.lua")
dofile(ADDON .. "/Modules/OfficerNotes.lua")
dofile(ADDON .. "/Modules/TrialTracker.lua")
dofile(ADDON .. "/Modules/Birthdays.lua")
function GuildOS:IsOnGuildDB() return true end
GuildOS.isGuilded = true
GuildOS.Compat.OfficerAddonChannel = function() return true end
local CS, SS, RL, MH, MR = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.RosterLog, GuildOS.MemberHistory, GuildOS.MemberRename
local AS, BL, MM, ON, TT, BD = GuildOS.AltSync, GuildOS.BanList, GuildOS.MemberMarks, GuildOS.OfficerNotes,
  GuildOS.TrialTracker, GuildOS.Birthdays
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end
CS.SendToOfficers = function(_, msgType, data) sent[#sent + 1] = { t = msgType, data = data, target = "OFFICER" } end
CS.OfficerChannel = function() return "OFFICER" end
local function K(name) return GuildOS:GetPlayerKey(name) end
local function domains()
  local out = {}
  for _, m in ipairs(sent) do
    local env = store[m.data]
    if env and env.dom then out[env.dom] = (out[env.dom] or 0) + 1 end
  end
  return out
end
local function find(action, target)
  for _, e in ipairs(GuildOS.db.rosterLog.events) do
    if e.action == action and e.target == target then return e end
  end
end

-- The popup queue's window: the dialog asked for, kept to be answered by the test.
local dialogs = {}
function GuildOS:ShowDialog(which, text, _, data)
  dialogs[#dialogs + 1] = { which = which, text = text, data = data }
  return nil
end
local function answer(yes)
  local d = table.remove(dialogs, 1)
  local def = GuildOS.Dialogs[d.which]
  if yes then def.OnAccept(nil, d.data) else def.OnCancel(nil, d.data) end
end

-- ── 1. Pure: which departures and joins are one character ─────────────────
local P = MR.Pairs
local res = P({ { kind = "gone", key = "Abc" }, { kind = "join", key = "Xyz" }, { kind = "join", key = "Q" } },
  { Abc = { g = "G1" } }, { { key = "Xyz", g = "G1" }, { key = "Q", g = "G2" } })
check(#res == 1 and res[1].old == "Abc" and res[1].new == "Xyz" and res[1].how == "guid", "the same GUID is a rename")
check(#P({ { kind = "gone", key = "Abc" }, { kind = "join", key = "Xyz" } }, { Abc = { g = "G1" } },
  { { key = "Xyz", g = "G9" } }) == 0, "another GUID is somebody else")
local b = { Def = { c = "MAGE", r = 3, lv = 59, n = "tank main", o = "" } }
local function guess(row) return P({ { kind = "gone", key = "Def" }, { kind = "join", key = row.key } }, b, { row }) end
res = guess({ key = "Ghi", cls = "MAGE", r = 3, lv = 60, n = "tank main", o = "" })
check(#res == 1 and res[1].how == "guess", "no GUID: same class, rank, level within one and note: a likely rename")
check(#guess({ key = "Ghi", cls = "MAGE", r = 3, lv = 60, n = "", o = "" }) == 0, "not without a note in common")
check(#guess({ key = "Ghi", cls = "PRIEST", r = 3, lv = 60, n = "tank main" }) == 0, "not another class")
check(#guess({ key = "Ghi", cls = "MAGE", r = 2, lv = 60, n = "tank main" }) == 0, "not another rank")
check(#guess({ key = "Ghi", cls = "MAGE", r = 3, lv = 61, n = "tank main" }) == 0, "not two levels apart")
check(#P({ { kind = "gone", key = "Def" }, { kind = "gone", key = "Z" }, { kind = "join", key = "Ghi" } },
  { Def = b.Def, Z = b.Def }, { { key = "Ghi", cls = "MAGE", r = 3, lv = 59, n = "tank main" } }) == 0,
  "two departures: no guess")
check(#P({ { kind = "rank", key = "A" } }, {}, {}) == 0, "no departure: nothing")
-- The player's own rename is the same plan for the links.
local plan = GuildOS.AltAutoDetect.PlanRename({ Abc = "Main", Alt2 = "Abc" }, "Abc", "Xyz")
check(plan.Xyz == "Main" and plan.Alt2 == "Xyz" and plan.Abc == nil, "PlanRename: the links follow the new name")

-- ── 2. An officer's client, the first look ───────────────────────────────
local db = { settings = { officerMaxRank = 1, modules = {} }, members = {}, rosterLog = { events = {} }, firstSeen = {},
  banList = {}, altLinks = {}, officerNotes = {}, trials = {}, birthdays = {},
  raidTracker = { sessions = { { players = { [K("Abc")] = true, [K("Off")] = true } } },
                  attendance = { [""] = { [K("Abc")] = { raids = 3 } } } } }
GuildOS.db = db
SS:Initialize()
RL:Initialize()
RL._ready = true
AS:Initialize()
BL:Initialize()
MM:Initialize()
ON:Initialize()
TT:Initialize()
BD:Initialize()
MR:Initialize()
roster({
  { "Off", "Officer", 1, 60, "", "", true, 0, "WARRIOR", "G-off" },
  { "Main", "Member", 3, 60, "", "", true, 0, "PRIEST", "G-main" },
  { "Abc", "Raider", 2, 60, "dps", "core", false, 1, "ROGUE", "G-abc" },
  { "Def", "Member", 3, 59, "tank main", "", false, 1, "MAGE" },          -- no GUID: an older client
  { "Jkl", "Member", 3, 40, "", "healer", false, 1, "DRUID" },
  { "Alt2", "Member", 3, 30, "", "", false, 1, "PRIEST", "G-alt2" },
})
db.firstSeen[K("Abc")] = now - 100 * DAY
local function scan()
  GuildOS.State.coalesce = nil
  MH:Scan()
end
afters = {}
MH:Initialize()
runAfters()
check(db.memberHistoryBase and db.memberHistoryBase.m[K("Abc")].g == "G-abc", "the roster last seen keeps each GUID")
check(db.memberHistoryBase.m[K("Def")].c == "MAGE" and db.memberHistoryBase.m[K("Def")].g == nil, "and the class")

-- Everything an officer keeps about Abc.
GuildOS:LinkAlt(K("Abc"), K("Main"))
GuildOS:LinkAlt(K("Alt2"), K("Main"))
check(db.altLinks[K("Abc")] == K("Main"), "Abc is Main's alt")
BL:Add("Abc", "ninja", nil, "kept on watch")
MM:SetSafe(K("Abc"), true)
MM:SetNick(K("Abc"), "Shadow")
ON:AddNote(K("Abc"), "good raider")
ON:SetSheet(K("Abc"), "Long sheet about Abc")
db.trials[K("Abc")] = { startDate = now - 5 * DAY, status = "trial", notes = {}, snapshots = {} }
BD:SetFor(K("Abc"), 14, 3)
MH:SetNote(K("Abc"), "permanent note")
check(BL:IsBanned("Abc") and MM:IsMarkedSafe(K("Abc")) and BD:For(K("Abc")), "set up: ban, mark, birthday")

-- ── 3. The same GUID under a new name: moved at once ─────────────────────
now = now + DAY
roster({
  { "Off", "Officer", 1, 60, "", "", true, 0, "WARRIOR", "G-off" },
  { "Main", "Member", 3, 60, "", "", true, 0, "PRIEST", "G-main" },
  { "Xyz", "Raider", 2, 60, "dps", "core", false, 0, "ROGUE", "G-abc" },
  { "Def", "Member", 3, 59, "tank main", "", false, 1, "MAGE" },
  { "Jkl", "Member", 3, 40, "", "healer", false, 1, "DRUID" },
  { "Alt2", "Member", 3, 30, "", "", false, 1, "PRIEST", "G-alt2" },
})
sent, dialogs = {}, {}
scan()
local A, X = K("Abc"), K("Xyz")
check(#dialogs == 0, "a GUID match asks nobody")
check(not find("gone", "Abc") and not find("join", "Xyz"), "and the diff records no departure and no join")
local rn = find("rename", "Xyz")
check(rn and rn.detail == "renamed from Abc" and rn.loc, "the log: Xyz renamed from Abc")
check(MH:JoinedAt(X) and db.memberHistory[A] == nil and not MH:IsFormer(X), "the history: the passage is Xyz's, still open")
check(db.memberHistory[X].note and db.memberHistory[X].note.text == "permanent note", "with the permanent note")
check(db.altLinks[X] == K("Main") and db.altLinks[A] == nil and db.altLinks[K("Alt2")] == K("Main"),
  "the alt links: Xyz is Main's alt, Abc is gone")
local altEntry = AS:_Store().links[A]
check(altEntry and altEntry.removed, "Abc's link is an AltSync tombstone")
check(BL:IsBanned("Xyz") and not BL:IsBanned("Abc"), "the ban moved")
check(db.banList[BL:_NormalizeKey("Xyz")].note == "kept on watch" and db.banList[BL:_NormalizeKey("Abc")].removed,
  "with the officer's note, the old one lifted by tombstone")
check(MM:IsMarkedSafe(X) and not MM:IsMarkedSafe(A) and MM:Nick(X) == "Shadow" and MM:Nick(A) == nil, "the safe mark and nickname")
check(ON:GetNotes(X)[1] and ON:GetNotes(X)[1].text == "good raider", "the officer notes")
check(ON:GetSheet(X) and ON:GetSheet(X).text == "Long sheet about Abc" and ON:GetSheet(A) == nil, "the sheet")
check(db.trials[X] and db.trials[A] == nil and db.trialTombs[A], "the trial, the old one a tombstone")
local bx = BD:For(X)
check(bx and bx.day == 14 and bx.month == 3 and db.birthdays[A].off, "the birthday, the old one a tombstone")
check(db.raidTracker.sessions[1].players[X] and not db.raidTracker.sessions[1].players[A]
  and db.raidTracker.attendance[""][X].raids == 3, "the raid attendance")
check(db.firstSeen[X] == now - 101 * DAY and db.firstSeen[A] == nil, "first seen")
local d = domains()
check((d.alt or 0) > 0 and (d.ban or 0) >= 2 and (d.marks or 0) > 0 and (d.osheet or 0) > 0 and (d.birthday or 0) > 0,
  "each synced store sent through its own domain")
check(db.memberHistoryBase.m[X] and db.memberHistoryBase.m[A] == nil, "the roster last seen follows")
sent = {}
scan()
check(#dialogs == 0 and not find("join", "Xyz"), "the next diff: nothing")

-- ── 4. No GUID, a likely rename: asked once, declined ────────────────────
now = now + DAY
roster({
  { "Off", "Officer", 1, 60, "", "", true, 0, "WARRIOR", "G-off" },
  { "Main", "Member", 3, 60, "", "", true, 0, "PRIEST", "G-main" },
  { "Xyz", "Raider", 2, 60, "dps", "core", false, 0, "ROGUE", "G-abc" },
  { "Ghi", "Member", 3, 60, "tank main", "", false, 0, "MAGE" },
  { "Jkl", "Member", 3, 40, "", "healer", false, 1, "DRUID" },
  { "Alt2", "Member", 3, 30, "", "", false, 1, "PRIEST", "G-alt2" },
})
db.officerNotes[K("Def")] = { notes = { { text = "def note", author = "Off", timestamp = now } }, tags = {} }
scan()
check(#dialogs == 1 and dialogs[1].which == "GUILDOS_MEMBER_RENAME"
  and dialogs[1].text == "Ghi looks like Def renamed. Move Def's history, alt links, ban and marks to the new name?",
  "one question: " .. tostring(dialogs[1] and dialogs[1].text))
check(not find("gone", "Def") and not find("join", "Ghi"), "while it waits, the two stay out of the diff")
check(db.memberHistoryBase.m[K("Def")] and db.memberHistoryBase.m[K("Ghi")] == nil, "and out of the snapshot")
scan()
check(#dialogs == 1, "the next diff does not ask again")
answer(false)
check(MR:Declined(K("Def"), K("Ghi")), "no: remembered")
scan()
check(find("gone", "Def") and find("join", "Ghi"), "the next diff: a departure and a join, as usual")
check(db.officerNotes[K("Def")] and not db.officerNotes[K("Ghi")] and not find("rename", "Ghi"), "nothing moved")

-- ── 5. Another one, accepted ─────────────────────────────────────────────
now = now + DAY
roster({
  { "Off", "Officer", 1, 60, "", "", true, 0, "WARRIOR", "G-off" },
  { "Main", "Member", 3, 60, "", "", true, 0, "PRIEST", "G-main" },
  { "Xyz", "Raider", 2, 60, "dps", "core", false, 0, "ROGUE", "G-abc" },
  { "Ghi", "Member", 3, 60, "tank main", "", false, 0, "MAGE" },
  { "Mno", "Member", 3, 41, "", "healer", false, 0, "DRUID" },
  { "Alt2", "Member", 3, 30, "", "", false, 1, "PRIEST", "G-alt2" },
})
MM:SetNick(K("Jkl"), "Leafy")
scan()
check(#dialogs == 1 and dialogs[1].text:find("Mno looks like Jkl", 1, true), "asked about Jkl and Mno")
answer(true)
check(find("rename", "Mno") and MM:Nick(K("Mno")) == "Leafy" and MH:JoinedAt(K("Mno")) and db.memberHistory[K("Jkl")] == nil,
  "yes: the nickname and the history moved, the log says so")
scan()
check(not find("gone", "Jkl") and not find("join", "Mno") and #dialogs == 0, "and the next diff records neither")

-- ── 6. A member's client: nothing ────────────────────────────────────────
me = "Main"
check(#MR:Apply(K("Ghi"), K("Zzz"), "guid") >= 0 and db.altLinks[K("Zzz")] == nil, "a member writes no synced store")
me = "Off"

print(string.format("member-rename: %d checks passed", checks))
