-- Somebody left or was removed, and who comes back (#449, specs/salao/saidas.md), run against the real Core,
-- Compat, Utils, CommSystem, SyncService, AltSync, GuildManager, RosterLog, MemberHistory, BanList, BulkActions,
-- AltDeparture, Departure and RecruitmentSystem, with several clients on one guild channel (two officers, a member,
-- and an officer who logs in later).
--
-- One popup per happening (the game's line twice, the roster diff, a removal's line after a diff); the player's
-- characters listed in the guild / already gone, the ones in the guild ticked; "Remove selected" queued one per click
-- (never the protected call), the /gremove lines to copy where the game takes no removal, the reason without the
-- rank; the permanent note saved, sent over OFFICER only and shown to officers only; the ban and the suspension
-- through BanList for the whole group; "Handled by" closing the other officer's window; the backfill keeping a
-- late officer from being asked; the switch off; the welcome back (the notice, the warning for a suspended player,
-- the placeholders, the fallback); the history surviving the log's prune and the members' drop.
--
--   luajit -e 'ADDON="."' tools/departure.lua
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

-- name, rank (officers up to 1), class
local ROSTER = {
  { "OffA", 1, "PALADIN" }, { "OffB", 1, "PRIEST" }, { "OffC", 1, "SHAMAN" }, { "Mem", 5, "MAGE" },
  { "Main", 4, "WARRIOR" }, { "AltX", 6, "ROGUE" }, { "AltY", 6, "DRUID" },
  { "Solo", 5, "HUNTER" },
}
local me = "OffA"
local now = 1792000000
local afters = {}
local registry, store, n = {}, {}, 0
local handlers = {}
local errors = {}

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) handlers[#handlers + 1] = fn; self.fn = fn end
  function f:Hide() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function GetServerTime() return now end
function GetTime() return now end
function GetLocale() return "enUS" end
time = os.time
date = os.date
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
function UnitName() return me end
function UnitFullName() return me, nil end
function UnitLevel() return 70 end
function UnitClass() return "Warrior", "WARRIOR" end
function IsInGuild() return true end
function InCombatLockdown() return false end
function GuildRoster() end
function CanGuildPromote() return true end
function CanGuildDemote() return true end
local canRemove = true
function CanGuildRemove() return canRemove end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1] .. "-Realm", "Rank" .. r[2], r[2], 70, "Warrior", "", "", "", true, 0, r[3] end
end
function GetGuildRosterLastOnline() return nil end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
  return "Guild", "Rank", 1
end
function GuildControlGetNumRanks() return 7 end
function GuildControlGetRankName(i) return "Rank" .. (i - 1) end
function GuildControlGetRankFlags() return true, true, true, true end
function GuildUninvite() error("GuildUninvite called") end
function GuildPromote() error("GuildPromote called") end
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."
function issecretvalue() return false end
local chat = {}
function SendChatMessage(msg, chan) chat[#chat + 1] = { msg = msg, chan = chan, from = me } end

LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, copy(store[s]) end return false end
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/AltSync.lua")
dofile(ADDON .. "/Modules/GuildManager.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
dofile(ADDON .. "/Modules/MemberHistory.lua")
dofile(ADDON .. "/Modules/BanList.lua")
dofile(ADDON .. "/Modules/BulkActions.lua")
dofile(ADDON .. "/Modules/AltDeparture.lua")
dofile(ADDON .. "/Modules/Departure.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
GuildOS.CommSystem.pendingMessages = {}
GuildOS.RecordError = function(_, e) errors[#errors + 1] = tostring(e) end
GuildOS.IsOnGuildDB = function() return true end
local CS, SS, AS, BL, BA, RL, MH, DP, R = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.AltSync, GuildOS.BanList,
  GuildOS.BulkActions, GuildOS.RosterLog, GuildOS.MemberHistory, GuildOS.Departure, GuildOS.Recruitment

-- The windows, per client: what was queued and drawn.
local popups, notices, redraws = {}, {}, {}
function GuildOS:ShowDeparturePopup() popups[me] = (popups[me] or 0) + 1; return nil end
function GuildOS:ShowWelcomeBackNotice(r) notices[me] = notices[me] or {}; table.insert(notices[me], r); return nil end
function GuildOS:ShowAltRemovedDialog() error("the alt dialog is the departure popup's now") end
function GuildOS:ShowMainLeftDialog() end
local queued = {}
function GuildOS:ShowWhenClear(key, fn) queued[#queued + 1] = key; fn() end
DP.uiRefresh = function() redraws[me] = (redraws[me] or 0) + 1 end

-- ── The clients ─────────────────────────────────────────────────────────
local clients, wire, online = {}, {}, {}
local OFFICERS = { OffA = true, OffB = true, OffC = true }
local function newClient(name)
  clients[name] = { db = { settings = { officerMaxRank = 1 }, altLinks = {}, banList = {}, members = {},
                           rosterLog = { events = {} }, memberHistory = {}, memberHistoryOut = {},
                           recruitment = { welcomeEnabled = true, welcomeMessage = "Welcome {name}!", discord = "" } },
                    acc = {}, seen = {}, count = 0, state = {} }
  online[name] = true
end
local function use(name)
  local c = clients[name]
  me = name
  GuildOS.db, GuildOSDB = c.db, c.acc
  SS.seenIds, SS.seenCount = c.seen, c.count
  for _, k in ipairs({ "altDeparture", "bulk", "departure", "memberHistory" }) do GuildOS.State[k] = c.state[k] end
end
local function save()
  local c = clients[me]
  c.count = SS.seenCount
  for _, k in ipairs({ "altDeparture", "bulk", "departure", "memberHistory" }) do c.state[k] = GuildOS.State[k] end
end
CS.SendMessage = function(_, msgType, data, target, _, _, channel)
  wire[#wire + 1] = { t = msgType, data = data, from = me, target = target, channel = channel or "GUILD" }
end
local delivered = {}   -- [client] = { { channel, env } }
local function flush()
  local guard = 0
  while #wire > 0 do
    guard = guard + 1
    check(guard < 50, "the channel settles")
    local batch = wire
    wire = {}
    for _, msg in ipairs(batch) do
      for name in pairs(clients) do
        -- The game's OFFICER addon channel reaches only those who may read officer chat.
        if online[name] and name ~= msg.from and (msg.channel ~= "OFFICER" or OFFICERS[name]) then
          use(name)
          delivered[name] = delivered[name] or {}
          table.insert(delivered[name], { channel = msg.channel, env = store[msg.data] })
          CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, msg.channel, msg.from .. "-Realm")
          save()
        end
      end
    end
  end
end
local function as(name, fn) use(name); local r = { fn() }; save(); return unpack(r, 1, 3) end
local function runAfters(who)
  use(who)
  local guard = 0
  while #afters > 0 do
    guard = guard + 1
    check(guard < 500, "the timers settle")
    table.remove(afters, 1)()
  end
  save()
end

local K = function(name) return GuildOS:GetPlayerKey(name, "Realm") end
local MAIN, X, Y, OLD, SOLO = K("Main"), K("AltX"), K("AltY"), K("OldAlt"), K("Solo")
local function gone(name)
  for i, r in ipairs(ROSTER) do if r[1] == name then table.remove(ROSTER, i) return end end
end
local onSystem
local function system(name, msg) use(name); onSystem(nil, "CHAT_MSG_SYSTEM", msg); save() end
local function pendingOf(name) return as(name, function() return DP:Pending() end) end

for name in pairs({ OffA = 1, OffB = 1, Mem = 1 }) do newClient(name) end
online.OffC = nil
use("OffA")
SS:On("ban", function(env, sender) BL:OnSync(env, sender) end)
SS:On("audit", function(env, sender) RL:OnSync(env, sender) end)
SS:On(MH.NOTE_DOMAIN, function(env, sender) MH:OnNoteSync(env, sender) end)
AS:Initialize()
RL:_SetupDetection()
onSystem = handlers[#handlers]
runAfters("OffA")   -- the Roster Log's settle
for _, name in ipairs({ "OffA", "OffB", "Mem" }) do as(name, function() AS:_Store(); AS:Rebuild(); DP:Initialize() end) end

-- ── The links, and a history: Main in the guild for 100 days ────────────
as("OffA", function()
  GuildOS:LinkAlt(X, MAIN); GuildOS:LinkAlt(Y, MAIN); GuildOS:LinkAlt(OLD, MAIN)
end)
flush()
for _, name in ipairs({ "OffA", "OffB" }) do
  as(name, function() MH.ApplyJoin(GuildOS.db.memberHistory, MAIN, now - 100 * 86400, false) end)
end

-- OffA's roster diff has seen the guild once (its baseline).
as("OffA", function() GuildOS.State.memberHistory = { seen = {}, settled = true }; MH:Scan() end)
check(clients.OffA.db.memberHistoryBase and clients.OffA.db.memberHistoryBase.m[MAIN], "the diff's baseline")
check(as("OffA", function() return MH:ClassOf(MAIN) end) == "WARRIOR", "the class kept with the history")

-- ── 1. One popup per happening ──────────────────────────────────────────
gone("Main")
for _, name in ipairs({ "OffA", "OffB", "Mem" }) do system(name, "Main-Realm has left the guild.") end
check(#pendingOf("OffA") == 1 and #pendingOf("OffB") == 1, "every officer online is asked")
check(#pendingOf("Mem") == 0 and not popups.Mem, "a member is never asked")
system("OffA", "Main-Realm has left the guild.")
check(#pendingOf("OffA") == 1, "the same line twice is one happening")
local h, fresh = as("OffA", function() return DP:OnGone(MAIN, now + 120) end)
check(h and fresh == false and #pendingOf("OffA") == 1, "the roster diff of the same departure is the same happening")
as("OffA", function() MH:Scan() end)
check(#pendingOf("OffA") == 1, "a diff after the game's line asks nothing more")
local h2 = as("OffB", function() return DP:Take(MAIN, "kick", "OffC", now + 60) end)
check(h2.how == "kick" and h2.by == "OffC" and #pendingOf("OffB") == 1, "a removal's line names the officer, still one happening")
check(as("OffB", function() return DP.Header(h2) end) == "Main was removed by OffC", "the header of a removal")
local hdr = as("OffA", function() return DP.Header(DP:Pending()[1]) end)
check(hdr == "Main left the guild", "the header of a leave")
local later = as("OffA", function() return DP:Take(MAIN, "leave", nil, now + DP.SAME + 60) end)
check(later ~= nil and #pendingOf("OffA") == 2, "the same member past SAME seconds is another happening")
as("OffA", function() DP:Dismiss(later) end)
check(#pendingOf("OffA") == 1, "dismissed")
local qd = 0
for _, k in ipairs(queued) do if k == "departure" then qd = qd + 1 end end
check(qd >= 2, "the popup went through the popup queue")

-- ── 2. The player's characters ──────────────────────────────────────────
local hA = pendingOf("OffA")[1]
local linked = as("OffA", function() return DP:Linked(hA) end)
check(#linked == 4 and linked[1].key == MAIN and linked[1].main, "the main first, then the alts")
local by = {}
for _, c in ipairs(linked) do by[c.key] = c end
check(not by[MAIN].inGuild and not by[MAIN].checked, "the one who left: already gone")
check(by[X].inGuild and by[X].checked and by[Y].inGuild and by[Y].checked, "the alts still in the guild, ticked")
check(not by[OLD].inGuild and not by[OLD].checked, "an alt that left long ago: already gone")
check(DP.Colored(by[X]):find("|cff" .. GuildOS:GetClassColorHex("ROGUE") .. "AltX|r", 1, true), "in class colour")

-- ── 3. Remove selected: one per click; the copy lines; the reason ───────
local res = as("OffA", function() return DP:Remove(hA, { X, Y, MAIN, OLD }) end)
check(res == "queued", "queued in Bulk actions")
use("OffA")
local q = BA:Queue()
check(q and q.action == "remove" and #q.items == 2 and q.items[1].fullName == "AltX-Realm" and q.items[2].fullName == "AltY-Realm",
  "the two in the guild, one per click of Next")
check(BA:Current().fullName == "AltX-Realm", "the first click is for AltX")
BA:Stop()
save()
local secure = GuildOS.Compat.SecureGuildMacro
GuildOS.Compat.SecureGuildMacro = function() return false end
local typed, lines = as("OffA", function() return DP:Remove(hA, { X, Y }) end)
GuildOS.Compat.SecureGuildMacro = secure
check(typed == "typed" and lines[1] == "/gremove AltX" and lines[2] == "/gremove AltY", "WoW: Forever: the lines to copy")
check(as("OffA", function() return BA:Queue() end) == nil, "and no queue there")
canRemove = false
local no, why = as("OffA", function() return DP:Remove(hA, { X }) end)
canRemove = true
check(no == false and why == "permission", "a rank that may not remove: the reason")

-- ── 4. Save: the note, the suspension, "Handled by" ─────────────────────
redraws.OffB = 0
local ok, did = as("OffA", function() return DP:Save(hA, { note = "Left after the drama |cffff0000x", flag = "suspend", days = 14 }) end)
check(ok and did.note and did.banned == 4, "the note, and the four characters suspended")
local bad = { as("OffA", function() return DP:Save(DP:Take(SOLO, "leave", nil, now) or hA, { flag = "suspend", days = 0 }) end) }
check(bad[1] == false and bad[2] == "days", "a suspension needs its days")
as("OffA", function() DP:Dismiss(DP:Pending()[1]) end)
local noteA = as("OffA", function() return MH:GetNote(MAIN) end)
check(noteA and noteA.text == "Left after the drama cffff0000x" and noteA.author == "OffA", "the note, cleaned, in the history")
local banA = clients.OffA.db.banList
check(banA.main and banA.main.expiry == now + 14 * 86400 and banA.altx and banA.oldalt, "suspended for 14 days through BanList")
-- What went on the wire: the note only over OFFICER, the claim over GUILD without it.
local noteOverGuild, noteOverOfficer, claim = false, false, nil
for _, msg in ipairs(wire) do
  local env = store[msg.data]
  if type(env) == "table" and env.dom == MH.NOTE_DOMAIN then
    if msg.channel == "OFFICER" then noteOverOfficer = true else noteOverGuild = true end
  end
  if type(env) == "table" and env.dom == "audit" and env.act == "dh" then claim = { env = env, channel = msg.channel } end
end
check(noteOverOfficer and not noteOverGuild, "the note goes to the officers' channel only")
check(claim and claim.channel == "GUILD" and claim.env.data.k == MAIN and claim.env.data.f == "suspend" and claim.env.data.x == nil,
  "the claim goes over GUILD, with no text")
flush()
local noteB = as("OffB", function() return MH:GetNote(MAIN) end)
check(noteB and noteB.text == noteA.text and noteB.author == "OffA", "the other officer has the note")
check(clients.Mem.db.memberHistory[MAIN] == nil or clients.Mem.db.memberHistory[MAIN].note == nil, "a member keeps no note")
for _, d in ipairs(delivered.Mem or {}) do
  check(not (type(d.env) == "table" and d.env.dom == MH.NOTE_DOMAIN), "a member's client never gets the note's bytes")
end
check(as("Mem", function() return MH:GetNote(MAIN) end) == nil, "and reads none")
check(clients.OffB.db.banList.main and clients.OffB.db.banList.main.expiry == banA.main.expiry, "the suspension reached the other officer")
check(as("OffB", function() return BL:IsBanned("Main") end), "and warns there as any ban")
-- "Handled by OffA": OffB's window says it, then moves on.
local hB = as("OffB", function() return DP:Shown()[1] end)
check(hB and hB.handledBy == "OffA" and #pendingOf("OffB") == 0, "Handled by OffA, off the list")
check((redraws.OffB or 0) > 0, "the other officer's window redrew")
runAfters("OffB")
check(#as("OffB", function() return DP:Shown() end) == 0, "and closes after a moment")
check(as("OffA", function() return DP:Take(MAIN, "gone", nil, now + 30) end) == nil, "handled here: a late diff asks nothing")

-- The member window and the officer sheet read it through NoteFor, for any of the player's characters.
check(as("OffB", function() return MH:NoteFor(X) end).text == noteA.text, "the note shows on an alt's card too")

-- ── 5. An officer who logs in later: the backfill ───────────────────────
newClient("OffC")
as("OffC", function() DP:Initialize() end)
as("OffA", function() RL:Backfill() end)
flush()
check(as("OffC", function() return MH:GetNote(MAIN) end) ~= nil, "the late officer has the note")
check(as("OffC", function() return DP:OnGone(MAIN, now + 200) end) == nil, "and is not asked about what was handled")

-- ── 6. The switch off ───────────────────────────────────────────────────
as("OffB", function() DP:SetEnabled(false) end)
gone("Solo")
for _, name in ipairs({ "OffA", "OffB" }) do system(name, "Solo-Realm has been kicked out of the guild by OffA.") end
check(#pendingOf("OffB") == 0, "switched off: no popup")
check(#pendingOf("OffA") == 1 and pendingOf("OffA")[1].how == "kick" and pendingOf("OffA")[1].by == "OffA", "on: asked, removed by OffA")
as("OffB", function() DP:SetEnabled(true) end)

-- ── 7. Welcome back ─────────────────────────────────────────────────────
local leftAt = clients.OffA.db.memberHistory[MAIN].stints[1].leftAt
now = now + 5 * 86400
table.insert(ROSTER, { "Main", 4, "WARRIOR" })
notices.OffA = nil
system("OffA", "Main-Realm has joined the guild.")
local r = notices.OffA and notices.OffA[1]
check(r and r.warn and r.title:find("^Main is suspended until "), "suspended and back: the warning in the welcome's place")
local joined = table.concat(r.lines, "\n")
check(joined:find("returned after 5 days", 1, true) and joined:find("member for 100 days", 1, true), "the welcome back's line under it")
check(joined:find(noteA.text, 1, true), "with the permanent note")
local info = as("OffA", function() return MH:ReturnInfo(MAIN) end)
check(info and info.away == 5 and info.past == 100 and info.leftAt == leftAt and info.times == 1,
  "after the join: left 5 days ago, a member for 100 days before")
local pure = DP.ReturnLines("Main", { leftAt = leftAt, away = 5, past = 100 }, nil, nil, now)
check(not pure.warn and pure.title == "Welcome back: Main" and #pure.lines == 1, "no ban: the welcome back")
-- The guild's welcome: the list for those who return, its placeholders, the fallback.
use("OffA")
local back = R:BackInfo("Main")
check(back and back.days == 5 and back.since == GuildOS:DateText(leftAt, "/%Y"), "{days} and {since} for Main")
check(R:BackInfo("Newbie") == nil and R:BackInfo({ "Main", "Other" }) == nil, "a newcomer, or several at once: the normal welcome")
check(R:WelcomeMessage(back) == "Welcome {name}!", "no list for those who return: the normal welcome")
check(R:SetWelcomeBack(1, "Welcome back {name}! {days} days away, since {since}.") and #R.WelcomeBackList(GuildOS.db.recruitment) == 1,
  "a welcome back written")
local msg = R:WelcomeMessage(back)
check(msg == "Welcome back {name}! {days} days away, since {since}.", "the returning member's list is drawn")
check(R.FillWelcome(msg, "Main-Realm", back) == "Welcome back Main! 5 days away, since " .. back.since .. ".", "filled in")
check(R:WelcomeMessage(nil) == "Welcome {name}!", "and a newcomer keeps the normal one")
check(R.FillWelcome("Hi {name} {days}", "Ana") == "Hi Ana {days}", "{days} stays as written without a return")
check(R:RemoveWelcomeBack(1) and R:WelcomeMessage(back) == "Welcome {name}!", "emptied: back to the normal welcome")
save()

-- ── 8. The history lasts ────────────────────────────────────────────────
now = now + 120 * 86400
as("OffA", function()
  RL:Prune()
  GuildOS.db.members[MAIN] = nil
  GuildOS.db.rosterLog.events = {}
end)
check(#as("OffA", function() return MH:Stints(MAIN) end) == 2, "the passages outlive the log's prune and the member row")
check(as("OffA", function() return MH:GetNote(MAIN) end) ~= nil, "and the note")
local hist = {}
for i = 1, 5 do hist["gone" .. i] = { stints = { { joinAt = 1, leftAt = 2 } } } end
hist.noted = { stints = { { joinAt = 1, leftAt = 1 } }, ranks = {}, note = { text = "x", rev = 1 } }
MH.Cap(hist, 2)
check(hist.noted ~= nil, "the ceiling never drops a member with a note")
-- WoW: Forever's surnames: the whole "First Surname" is the key and the name.
local cf = GuildOS.Client.has.surnames
GuildOS.Client.has.surnames = true
local hs = as("OffA", function() return DP:OnRosterEvent({ action = "leave", target = "Ana Lima", timestamp = now }) end)
GuildOS.Client.has.surnames = cf
check(hs and hs.name == "Ana Lima" and hs.key == GuildOS:GetPlayerKey("Ana Lima"), "a surname is part of the key")

-- Seen only by the roster diff (nobody's chat had the line), then the removal's line: one happening.
table.insert(ROSTER, { "Drift", 5, "MAGE" })
as("OffA", function() MH:Scan() end)
gone("Drift")
local before = #pendingOf("OffA")
as("OffA", function() MH:Scan() end)
local hd = pendingOf("OffA")[#pendingOf("OffA")]
check(#pendingOf("OffA") == before + 1 and hd.key == K("Drift") and hd.how == "gone", "the diff alone asks")
as("OffA", function() return DP:OnRosterEvent({ action = "kick", target = "Drift", author = "OffB", timestamp = now - 60 }) end)
check(#pendingOf("OffA") == before + 1 and hd.how == "kick" and hd.by == "OffB", "and the game's line after it is the same one")
check(as("OffA", function() return DP.Header(hd) end) == "Drift was removed by OffB", "removed by OffB")

check(#errors == 0, "no error: " .. table.concat(errors, " | "))
print(string.format("departure: %d checks passed", checks))
