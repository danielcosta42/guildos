-- The guild's trial (issue #249), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/CommSystem.lua, Modules/SyncService.lua, Modules/RosterLog.lua and Modules/TrialTracker.lua.
--
-- A trial lasted 30 days, hard-coded, was added by hand, and at its end was stamped "expired" on the
-- client that noticed. Now the length is the guild's (1 to 90 whole days, 30 until an officer chooses,
-- on guildcfg like the officer threshold), a trial's end is its start plus that length worked out every
-- time it is read, so a change moves every running trial and an older client's stored end or "expired"
-- cannot undo it, and with the guild's switch on an officer's client starts a trial for whoever joins,
-- from the roster against the one it last saw whole: the join line only asks for a fresh roster, so
-- every key is the roster's. Nobody already in the guild, nobody on an officer rank, nobody already
-- waiting, and one trial however many officers saw it, with the earlier start and every note. The roster
-- seen is an officer's client's alone (an alt shares the account's database), only grows (a leave or
-- kick line takes a key out), and waits a minute after login for the guild's settings; a trial whose
-- member left is marked and counted nowhere.
--
--   luajit -e 'ADDON="."' tools/trial-guild.lua
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
  frames[#frames + 1] = f
  return f
end
-- An event, to every frame that registered it, as the client hands it.
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
local T0 = 1794139200
local now = T0
function GetServerTime() return now end
function GetTime() return 1 end
local afters, tickers = {}, {}
local requests = 0                                -- roster requests the addon made (Compat.GuildRoster)
function GuildRoster() requests = requests + 1 end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function(every, fn) tickers[every] = fn; return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."

-- The guild. Who "I" am changes between the clients; ranks 0..1 are officers.
local ROSTER
local function roster(list)
  ROSTER = {}
  for _, r in ipairs(list) do ROSTER[#ROSTER + 1] = { r[1], r[2] } end
end
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 }, { "Old", 5 } })
local me, rankUnknown, holeAt = "Off", false, nil
function UnitName() return me end
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  if i == holeAt then return nil end      -- a row the client did not answer
  local r = ROSTER[i]
  if r then return r[1], "Rank", r[2] end
end
function GetGuildInfo()
  if rankUnknown then return "Guild", nil, nil end
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
  return "Guild", "Rank", 5
end

-- The wire: what is serialized is copied and kept by key, and the encoding hands strings back as is,
-- so two clients never share a table.
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
dofile(ADDON .. "/Modules/TrialTracker.lua")
function GuildOS:IsOnGuildDB() return true end   -- the loaded db is this guild's: Core resolves it at login
local CS, SS, RL, TT = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.RosterLog, GuildOS.TrialTracker
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end

local function key(name) return GuildOS:GetPlayerKey(name) end
local function freshDb()
  return { settings = { officerMaxRank = 1, modules = {} }, members = {}, trials = {}, rosterLog = { events = {} } }
end
-- Become `who`, on the database that client holds (a fresh one unless given), a client long past its
-- login's settle window.
local dbs = {}
local function use(who, fresh)
  me = who
  if fresh or not dbs[who] then dbs[who] = freshDb() end
  GuildOS.db = dbs[who]
  SS:Initialize()                -- per client: its own dedup of message ids
  TT:Initialize()
  GuildOS.State.trials = { settled = true }
  sent, printed = {}, {}
  return GuildOS.db
end
-- `who` logs in (or reloads) on the database given, or the one they hold: the settle window opens.
local function login(who, db)
  use(who)
  if db then dbs[who] = db; GuildOS.db = db end
  afters = {}
  TT:Arm()
  return GuildOS.db
end
-- The settle window's timer fires (and whatever else was waiting on a timer).
local function settle()
  local due = afters
  afters = {}
  for _, fn in ipairs(due) do fn() end
end
local function deliver(msg, sender, channel)
  CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, channel or "GUILD", sender)
end
local function lastOf(kind, act)
  for i = #sent, 1, -1 do
    local m = sent[i]
    if m.t == kind and (not act or (store[m.data] and store[m.data].act == act)) then return m end
  end
end
local function count(kind)
  local c = 0
  for _, m in ipairs(sent) do if m.t == kind then c = c + 1 end end
  return c
end
local function join(name) fire("CHAT_MSG_SYSTEM", name .. " has joined the guild.") end
local function left(name) fire("CHAT_MSG_SYSTEM", name .. " has left the guild.") end
local function kicked(name, by) fire("CHAT_MSG_SYSTEM", name .. " has been kicked out of the guild by " .. by .. ".") end
-- Each roster here is its own burst: the clock stands still, and GuildOS:Coalesce would hold every
-- update after the first (issue #324; tools/coalesce.lua tests the holding).
local function rosterUpdate()
  GuildOS.State.coalesce.at.roster = nil
  fire("GUILD_ROSTER_UPDATE")
end
local function trials(db)
  local c = 0
  for _ in pairs(db.trials) do c = c + 1 end
  return c
end

-- RosterLog's join line, ready: it waits eight seconds at login for the client's replay to pass.
use("Off")
RL:Initialize()
RL._ready = true

-- ── 1. The length: 30 until an officer chooses, 1 to 90 whole days ─────
local db = use("Off", true)
check(TT:GetDays() == 30 and not TT:IsAutoOn(), "a guild that never chose: 30 days, and the switch off")
for _, bad in ipairs({ 0, 91, -5, 2.5, 0 / 0, math.huge, -math.huge, "abc", "", " ", "3e1", "12a", "7.0", "-3", "0x10",
                       true, {} }) do
  local ok, why = TT:SetDays(bad)
  check(not ok and why == "range" and TT:GetDays() == 30 and db.settings.trialDaysAt == nil,
    "a length of " .. tostring(bad) .. " is refused, not clamped")
end
check(#sent == 0, "and nothing refused goes to the guild")
check(TT.ValidDays(" 45 ") == 45 and TT.ValidDays(1) == 1 and TT.ValidDays(90) == 90, "1 and 90 are lengths, and so are typed digits")
check(TT:SetDays("45") and TT:GetDays() == 45 and db.settings.trialDaysAt == now, "an officer sets it, stamped")
local m = lastOf("SV", "trialdays")
check(m and store[m.data].dom == "guildcfg" and store[m.data].data.days == 45 and store[m.data].rev == now,
  "and the guild is told on guildcfg")
check(store[m.data].data.max == nil, "with no `max`, so a client before #249 does not read it as the officer threshold")
GuildOS:OnOfficerMaxRankSync(store[m.data])
check(db.settings.officerMaxRank == 1, "as that client does: its threshold is left alone")
db.settings.trialDays = "lots"                                   -- a saved file somebody edited
check(TT:GetDays() == 30, "a stored length that is no length reads as the default")
use("Mem", true)
local ok, why = TT:SetDays(10)
check(not ok and why == "officer" and TT:GetDays() == 30, "a member's client cannot set it")
check(not TT:SetAuto(true) and not TT:IsAutoOn() and #sent == 0, "nor turn the switch on")

-- ── 2. The end is the start plus the guild's length, up and down ───────
db = use("Off", true)
local ann = key("Ann")
TT:AddTrial(ann)
local t = db.trials[ann]
check(t.startDate == T0 and t.endDate == T0 + 30 * DAY and t.status == "trial",
  "a new trial still carries the end a client before #249 reads")
now = T0 + 20 * DAY
check(TT:GetState(ann) == "trial" and TT:GetDaysRemaining(ann) == 10 and TT:CountReady() == 0, "day 20 of 30: running, 10 left")
TT:SetDays(14)
check(TT:GetState(ann) == "review" and TT:GetDaysRemaining(ann) == 0 and TT:CountReady() == 1,
  "shortened to 14: ready to review at once")
check(t.endDate == T0 + 30 * DAY and t.status == "trial", "and the record is not rewritten")
check(TT:IsTrial(ann) and #TT:GetActiveTrials() == 1, "ready to review is still a trial nobody decided")
TT:SetDays(60)
check(TT:GetState(ann) == "trial" and TT:GetDaysRemaining(ann) == 40, "lengthened to 60: running again, 40 left")
now = T0 + 60 * DAY
check(TT:GetState(ann) == "review" and TT:IsReady(t), "its end, from the start: ready on day 60")
TT:UpdateStatus(ann, TT.STATUS.APPROVED)
check(TT:GetState(ann) == "approved" and not TT:IsTrial(ann) and TT:GetDaysRemaining(ann) == nil and #TT:GetActiveTrials() == 0,
  "approved is a decision: no days, no trial")
TT:SetDays(90)
check(TT:GetState(ann) == "approved", "and a new length does not reopen it")

-- ── 3. What a client before #249 wrote ─────────────────────────────────
db = use("Off", true)
now = T0 + 20 * DAY
TT:SetDays(60)
local bea, cid = key("Bea"), key("Cid")
db.trials[bea] = { startDate = T0, endDate = T0 + 5 * DAY, status = "expired", notes = {}, snapshots = {} }
check(TT:GetState(bea) == "trial" and TT:IsTrial(bea) and TT:GetDaysRemaining(bea) == 40,
  "stored \"expired\" with its old end, and the guild lengthened its trials: running again")
TT:SetDays(14)
check(TT:GetState(bea) == "review" and TT:CountReady() == 1, "shortened, it is ready to review, not \"expired\"")
TT:SetDays(60)
db.trials[cid] = { startDate = T0 + DAY, endDate = T0 + 61 * DAY, status = "trial", notes = {}, snapshots = {} }
-- An officer on the old version sends the whole table: its copy of Cid started earlier (so it is the one
-- kept), with a note, its own stored end, long past, and the "expired" its client wrote.
use("Off2", true)
local oldCopy = { [cid] = { startDate = T0, endDate = T0 + DAY, status = "expired", sponsor = "Off2", snapshots = {},
  notes = { { author = "Off2", timestamp = T0 + 19 * DAY, text = "quiet so far" } } } }
local tr = { t = "TR", data = LibStub("GuildOS-LibSerialize"):Serialize(oldCopy) }
use("Off")
deliver(tr, "Off2")
check(db.trials[cid].status == "expired" and db.trials[cid].endDate == T0 + DAY and db.trials[cid].startDate == T0
  and #db.trials[cid].notes == 1, "the old officer's copy is kept (two undecided copies keep the earlier start), its note too")
check(TT:GetState(cid) == "trial" and TT:GetDaysRemaining(cid) == 40, "and its end and its \"expired\" change nothing: 40 days left")
-- The login line says it, and writes nothing.
TT:SetDays(14)
printed = {}
TT:CheckReady()
local said = table.concat(printed, "\n")
check(said:find("2 trial(s) ready to review.", 1, true) and not said:find("expired", 1, true),
  "the login line: ready to review, never \"expired\"")
check(db.trials[cid].status == "expired" and db.trials[bea].status == "expired" and TT:GetState(cid) == "review",
  "and it writes no status: the state stays worked out")
local order = TT:GetAllTrials()
check(order[1].group == 1 and order[2].group == 1, "the Trials panel lists the ready ones first")
use("Mem")
printed = {}
TT:CheckReady()
check(#printed == 0, "a member's client says nothing at login")

-- ── 4. The settings across the guild: newest wins, from an officer over GUILD ──
db = use("Off", true)
now = T0
TT:SetDays(20); local days20 = lastOf("SV", "trialdays")
TT:SetAuto(true); local autoOn = lastOf("SV", "trialauto")
check(store[autoOn.data].data.on == true and store[autoOn.data].data.max == nil, "the switch goes out too, with no `max`")
db = use("Mem", true)
deliver(days20, "Off"); deliver(autoOn, "Off")
check(TT:GetDays() == 20 and TT:IsAutoOn(), "a member's client takes both from an officer")
use("Off")
now = T0 + 100
TT:SetDays(25); local days25 = lastOf("SV", "trialdays")
TT:SetAuto(false); local autoOff = lastOf("SV", "trialauto")
use("Mem")
deliver(days25, "Off"); deliver(days20, "Off"); deliver(autoOff, "Off"); deliver(autoOn, "Off")
check(TT:GetDays() == 25 and not TT:IsAutoOn(), "an older change arriving late does not undo a newer one")
-- A member, dressed as an officer, from the future.
use("Mem")
SS:Publish("guildcfg", "trialdays", { days = 5 }, { rev = now + 1000 }); local forgedDays = sent[#sent]
SS:Publish("guildcfg", "trialauto", { on = true }, { rev = now + 1000 }); local forgedAuto = sent[#sent]
use("Off2", true)
deliver(forgedDays, "Mem"); deliver(forgedAuto, "Mem")
check(TT:GetDays() == 30 and not TT:IsAutoOn(), "from a member, neither is taken")
deliver(days25, "Off", "WHISPER"); deliver(autoOn, "Off", "WHISPER")
check(TT:GetDays() == 30 and not TT:IsAutoOn(), "nor from an officer's name over a whisper")
deliver(days25, "Off")
check(TT:GetDays() == 25, "over GUILD from the officer it is")
-- What a change may say, and stamps that are no time.
for _, bad in ipairs({ 0, 91, 2.5, "20", 0 / 0 }) do
  use("Off")
  SS:Publish("guildcfg", "trialdays", { days = bad }, { rev = now + 50 }); local msg = sent[#sent]
  use("Mem", true)
  deliver(msg, "Off")
  check(TT:GetDays() == 30 and GuildOS.db.settings.trialDaysAt == nil, "a length of " .. tostring(bad) .. " from the network is not taken")
end
for _, bad in ipairs({ "yes", 1 }) do
  use("Off")
  SS:Publish("guildcfg", "trialauto", { on = bad }, { rev = now + 50 }); local msg = sent[#sent]
  use("Mem", true)
  deliver(msg, "Off")
  check(not TT:IsAutoOn() and GuildOS.db.settings.trialAutoAt == nil, "a switch of " .. tostring(bad) .. " is not taken")
end
for _, bad in ipairs({ 0 / 0, math.huge, 0, -5 }) do
  use("Off")
  SS:Publish("guildcfg", "trialdays", { days = 40 }, { rev = bad }); local msg = sent[#sent]
  use("Mem", true)
  deliver(msg, "Off")
  check(TT:GetDays() == 30, "a stamp of " .. tostring(bad) .. " is not taken")
end
use("Off")
SS:Publish("guildcfg", "trialdays", { days = 40 }, { rev = now + 999999 }); local future = sent[#sent]
use("Mem", true)
deliver(future, "Off")
check(GuildOS.db.settings.trialDaysAt == now + 300, "a stamp from the future is held to five minutes ahead")
-- Two officers in the same second: every client settles on the shorter length and the switch off.
use("Off", true); TT:SetDays(40); local a = lastOf("SV", "trialdays"); TT:SetAuto(true); local aOn = lastOf("SV", "trialauto")
use("Off2", true); TT:SetDays(35); local b = lastOf("SV", "trialdays"); TT:SetAuto(false); local bOff = lastOf("SV", "trialauto")
check(store[a.data].rev == store[b.data].rev and store[aOn.data].rev == store[bOff.data].rev, "(stamped in the same second)")
use("Mem", true); deliver(a, "Off"); deliver(b, "Off2"); deliver(aOn, "Off"); deliver(bOff, "Off2")
local first = { TT:GetDays(), TT:IsAutoOn() }
use("Mem", true); deliver(b, "Off2"); deliver(a, "Off"); deliver(bOff, "Off2"); deliver(aOn, "Off")
check(first[1] == 35 and TT:GetDays() == 35 and first[2] == false and not TT:IsAutoOn(),
  "two changes in one second settle the same everywhere, whatever the order")
-- Re-sent by officers, only once somebody chose.
use("Off", true)
TT:PublishConfig()
check(#sent == 0, "an officer whose guild never chose sends nothing")
use("Mem")
GuildOS.db.settings.trialDaysAt = now
TT:PublishConfig()
check(#sent == 0, "a member's client does not re-send it")
use("Off")
TT:SetDays(21)
local function runAfters()
  for _ = 1, 5 do
    local due = afters
    afters = {}
    for _, fn in ipairs(due) do fn() end
  end
end
CS.BroadcastMyData = function() end
CS:Initialize()
sent, afters = {}, {}
tickers[300]()
runAfters()
check(lastOf("SV", "trialdays"), "the 5-minute sync re-sends the length")
sent, afters = {}, {}
CS:HandleRequest("Mem", "")
runAfters()
check(lastOf("SV", "trialdays"), "and so does an officer's answer to a request")

-- ── 5. The join line asks for the roster; the roster starts the trial ───
-- The line's name is never a key: on WoW: Forever it need not be the roster's spelling, and two
-- strings for one person would be two trials. Only ScanRoster starts one.
local function leaves(name)
  for i, r in ipairs(ROSTER) do if r[1] == name then table.remove(ROSTER, i) return end end
end
now = T0 + 200 * DAY
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 }, { "Old", 5 } })
db = use("Off", true)
rosterUpdate()
local newbie = key("Newbie")
requests = 0
join("Newbie")
check(requests == 0 and trials(db) == 0, "switch off: a join is only a join, and no roster is asked for")
TT:SetDays(21)
TT:SetAuto(true)
sent, requests = {}, 0
join("Newbie")
check(requests == 1 and trials(db) == 0 and count("TR") == 0,
  "switch on: the join line asks the game for a fresh roster, and starts nothing itself")
join("Chehul-Costa")                              -- a spelling the roster may not use
check(trials(db) == 0 and db.trials[GuildOS:KeyOfRosterName("Chehul-Costa")] == nil and db.trials[key("Chehul")] == nil,
  "no name off the line becomes a key")
table.insert(ROSTER, { "Newbie", 6 })
rosterUpdate()
local nt = db.trials[newbie]
check(nt and trials(db) == 1 and nt.status == "trial" and nt.startDate == now and nt.endDate == now + 21 * DAY
  and nt.sponsor == "Guild OS", "the roster that follows starts the trial, of the guild's length, sponsored by Guild OS")
check(count("TR") == 1, "and the other officers are told")
now = now + 60
sent = {}
join("Newbie")
rosterUpdate()
check(db.trials[newbie].startDate == now - 60 and count("TR") == 0, "a second join line for somebody already waiting starts nothing")
TT:AddTrialNote(newbie, "slow start")
TT:SetDays(1); now = now + 2 * DAY
check(TT:GetState(newbie) == "review", "(their trial is now ready to review)")
leaves("Newbie"); left("Newbie"); rosterUpdate()
check(db.trialBaseline[newbie] == nil and TT:GetState(newbie) == "left", "the leave line takes them out of the roster seen")
table.insert(ROSTER, { "Newbie", 6 }); join("Newbie"); rosterUpdate()
check(db.trials[newbie].startDate < now and db.trials[newbie].leftAt == nil and TT:GetState(newbie) == "review",
  "back while still waiting: the same trial, no longer marked as left, no new one over it")
TT:UpdateStatus(newbie, TT.STATUS.DENIED)
leaves("Newbie"); kicked("Newbie", "Off"); rosterUpdate()
check(db.trialBaseline[newbie] == nil and db.trials[newbie].leftAt == nil,
  "a kick line takes them out too, and a decided trial is never marked as left")
table.insert(ROSTER, { "Newbie", 6 }); join("Newbie"); rosterUpdate()
check(db.trials[newbie].status == "denied", "denied, removed and back: no trial starts by itself over a decision")
TT:AddTrial(newbie)                                -- an officer's Mark as Trial
local again = db.trials[newbie]
check(again.status == "trial" and again.startDate == now and #again.notes == 1 and again.notes[1].text == "slow start",
  "the officer puts them on trial again by hand, and what officers wrote stays")
table.insert(ROSTER, { "Veteran", 1 }); join("Veteran"); rosterUpdate()
check(db.trials[key("Veteran")] == nil, "somebody the roster has on an officer rank is never a trial")
GuildOS.db.settings.modules.trialTracker = false
requests = 0
table.insert(ROSTER, { "Dora", 6 }); join("Dora"); rosterUpdate()
check(requests == 0 and db.trials[key("Dora")] == nil, "the trial tracker turned off asks for nothing and starts nothing")
GuildOS.db.settings.modules.trialTracker = nil
use("Mem", true)
rosterUpdate()
GuildOS.db.settings.trialAuto, GuildOS.db.settings.trialAutoAt = true, now
requests = 0
table.insert(ROSTER, { "Eve", 6 }); join("Eve"); rosterUpdate()
check(requests == 0 and GuildOS.db.trials[key("Eve")] == nil, "a member's client asks for nothing and starts nothing")
check(GuildOS.db.trialBaseline == nil, "and neither reads nor writes the roster seen")

-- ── 6. The roster seen: the first look, then whoever is new to it ───────
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 }, { "Old", 5 } })
db = use("Off", true)
rosterUpdate()
check(type(db.trialBaseline) == "table" and db.trialBaseline[key("Mem")] and db.trialBaseline[key("Old")] and trials(db) == 0,
  "the first look, switch off: the roster is taken, nobody is a trial")
-- Quiet joins while the switch is off: taken in, no trial. Then the switch is turned on.
table.insert(ROSTER, { "Quiet", 6 })
rosterUpdate()
check(db.trialBaseline[key("Quiet")] and trials(db) == 0, "switch off: a newcomer is taken into the roster seen, no trial")
table.insert(ROSTER, { "Quieter", 6 })          -- joined a moment ago: no roster update has come yet
TT:SetAuto(true)
rosterUpdate()
check(trials(db) == 0 and db.trialBaseline[key("Quieter")],
  "turning the switch on takes the roster as it is: nobody already there is a trial, not even a moment's newcomer")
-- The first run after installing, with the switch already on (heard from the guild): only the roster.
db = use("Off", true)
GuildOS.db.settings.trialAuto, GuildOS.db.settings.trialAutoAt = true, now
rosterUpdate()
check(trials(db) == 0 and db.trialBaseline[key("Quiet")], "the first run after installing, switch on: only the roster seen")
-- The officer logs out. While away, Late and Later join, LateOfficer comes in on an officer rank, and
-- Old and Quieter leave with no officer's addon there to read the line. At the next login:
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 }, { "Quiet", 6 }, { "Late", 5 }, { "LateOfficer", 1 }, { "Later", 6 } })
now = now + 3 * DAY
login("Off")
rosterUpdate()
check(trials(db) == 0 and db.trialBaseline[key("Late")] == nil,
  "inside the login's settle window the roster is neither compared nor taken in")
rankUnknown = true
settle()
check(trials(db) == 0 and db.trialBaseline[key("Late")] == nil, "the window's own look, rank still unknown: nothing moves")
rankUnknown = false
holeAt = 2
rosterUpdate()
check(trials(db) == 0 and db.trialBaseline[key("Late")] == nil, "nor while the roster is not whole")
holeAt = nil
local catchUp = now
sent = {}
rosterUpdate()
check(db.trials[key("Late")] and db.trials[key("Late")].startDate == catchUp and db.trials[key("Later")]
  and db.trials[key("Later")].startDate == catchUp, "the catch-up: whoever joined while I was away is a trial, starting now")
check(db.trials[key("LateOfficer")] == nil, "but nobody on an officer rank")
check(db.trials[key("Mem")] == nil and db.trials[key("Quiet")] == nil and db.trials[key("Off2")] == nil,
  "and nobody who was already there")
check(db.trialBaseline[key("Old")], "Old left with no leave line read: still in the roster seen")
check(count("TR") == 1, "told to the other officers in one message")
rosterUpdate()
check(trials(db) == 2 and count("TR") == 1, "the next roster update starts nothing more")
table.insert(ROSTER, { "Old", 5 })
rosterUpdate()
check(db.trials[key("Old")] == nil, "so Old coming back is no newcomer: the consequence the roster seen accepts")
-- The window's look needs no roster event of its own.
table.insert(ROSTER, { "Solo", 6 })
login("Off")
settle()
check(db.trials[key("Solo")] and db.trials[key("Solo")].startDate == now, "once the window is over, the catch-up runs by itself")
-- A short roster, then the whole one: the roster seen only grows, so nobody is new.
local whole = {}
for i, r in ipairs(ROSTER) do whole[i] = { r[1], r[2] } end
local before = trials(db)
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
rosterUpdate()
check(trials(db) == before and db.trialBaseline[key("Quiet")] and db.trialBaseline[key("Late")],
  "a roster that comes short takes nobody out of the roster seen")
roster(whole)
rosterUpdate()
check(trials(db) == before, "and the whole roster after it puts nobody on trial")
check(db.trials[key("Late")].leftAt == nil and db.trials[key("Solo")].leftAt == nil,
  "the short roster's left marks are gone once the whole one is read")
-- A roster that shares nobody with the one seen: the keys changed under it, nobody is new.
db.trialBaseline = { [key("Somebody Else")] = true }
rosterUpdate()
check(trials(db) == before and db.trialBaseline[key("Mem")], "a roster with nobody in common is taken, not read as newcomers")
-- One account, one database for the guild: the officer and a non-officer alt.
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 }, { "OffAlt", 6 } })
local account = use("Off", true)
TT:SetAuto(true)
rosterUpdate()
table.insert(ROSTER, { "Newcomer", 6 })        -- joins while only the alt is online
login("OffAlt", account)
settle()
rosterUpdate()
check(account.trialBaseline[key("Newcomer")] == nil and account.trials[key("Newcomer")] == nil,
  "a non-officer alt on the officer's account neither reads nor takes in the roster seen")
login("Off", account)
settle()
check(account.trials[key("Newcomer")] and account.trials[key("Newcomer")].startDate == now,
  "the officer, back on the account, catches the newcomer up")
-- A newly promoted officer, with no roster seen yet: the first look only takes the roster.
local promoted = use("Mem", true)
promoted.settings.trialAuto, promoted.settings.trialAutoAt = true, now
ROSTER[3][2] = 1
login("Mem")
settle()
check(type(promoted.trialBaseline) == "table" and trials(promoted) == 0, "promoted, nobody already in the guild is a trial")
ROSTER[3][2] = 5
-- The switch turned on by another officer, on a client that has not seen the roster since Quiet2
-- joined (while the switch was off): it only takes the roster.
db = use("Off2", true)
rosterUpdate()
table.insert(ROSTER, { "Quiet2", 6 })
use("Off", true)
TT:SetAuto(true); local onAgain = lastOf("SV", "trialauto")
use("Off2")
deliver(onAgain, "Off")
check(TT:IsAutoOn() and db.trialBaseline[key("Quiet2")] and trials(db) == 0,
  "the switch heard on from another officer only takes the roster: Quiet2 joined before it, and is no trial")
table.insert(ROSTER, { "Fresh", 6 })
rosterUpdate()
check(db.trials[key("Fresh")] and trials(db) == 1, "whoever joins after it is")

-- ── 7. The login's window: the guild's switch arrives before the catch-up ──
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
now = T0 + 600 * DAY
local stale = use("Off", true)
TT:SetAuto(true)
rosterUpdate()
use("Off2", true)
TT:SetAuto(true)
now = now + 60
TT:SetAuto(false); local offMsg = lastOf("SV", "trialauto")
for _, j in ipairs({ "J1", "J2", "J3" }) do table.insert(ROSTER, { j, 6 }) end   -- join while Off is away
now = now + DAY
login("Off")
sent = {}
rosterUpdate()                                     -- the login roster, before any answer
check(trials(stale) == 0 and count("TR") == 0, "the login roster comes inside the window: nothing is compared")
deliver(offMsg, "Off2")                            -- the guild's switch, a few seconds later
settle()
check(not TT:IsAutoOn() and trials(stale) == 0 and stale.trialBaseline[key("J1")] and count("TR") == 0,
  "the switch the guild turned off meanwhile arrives first: the three are taken in, nobody is a trial")

-- ── 8. Two officers' copies of one trial: the earlier start and every note ──
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
now = T0 + 800 * DAY
use("Off", true); TT:SetAuto(true); rosterUpdate()
use("Off2", true); TT:SetAuto(true); rosterUpdate()
local rookie = key("Rookie")
use("Off")                                         -- Off2 is logged out
local t1 = now
table.insert(ROSTER, { "Rookie", 6 }); rosterUpdate()
now = now + 3600
TT:AddTrialNote(rookie, "great first raid"); local fromOff = lastOf("TR")
now = t1 + DAY                                     -- Off2 logs in a day later; Off is offline
login("Off2")
sent = {}
settle()
local fromOff2 = lastOf("TR")
check(fromOff2 and dbs.Off2.trials[rookie].startDate == now, "(with nobody to tell it, Off2's catch-up starts its own copy)")
deliver(fromOff, "Off")                            -- Off's copy reaches Off2 later
use("Off"); deliver(fromOff2, "Off2")              -- and Off2's reaches Off
local a, b = dbs.Off.trials[rookie], dbs.Off2.trials[rookie]
check(a.startDate == t1 and b.startDate == t1, "both keep the earlier start: the later catch-up restarts nothing")
check(#a.notes == 1 and #b.notes == 1 and b.notes[1].text == "great first raid", "and neither loses the note")
-- With Off online when Off2 logs in, its trials arrive inside the window: Off2 starts no copy at all.
local rookie2 = key("Rookie Two")
table.insert(ROSTER, { "Rookie Two", 6 }); rosterUpdate(); local fromOn = lastOf("TR")
now = now + DAY
login("Off2")
sent = {}
deliver(fromOn, "Off")
settle()
check(dbs.Off2.trials[rookie2].startDate == now - DAY and count("TR") == 0,
  "another officer's trials arrive inside the window: no copy of its own, and nothing to send")
-- A decided copy on either side: the latest activity wins, as before.
check(TT:Merge({ status = "approved", startDate = 10, resolvedDate = 50 }, { status = "trial", startDate = 20 }).status == "approved",
  "an approval after the other copy's start is kept")
check(TT:Merge({ status = "trial", startDate = 5 }, { status = "denied", startDate = 5, resolvedDate = 9 }).status == "denied",
  "and so is a denial")
check(TT:Merge({ status = "denied", startDate = 5, resolvedDate = 9 }, { status = "trial", startDate = 30 }).startDate == 30,
  "a trial started after a decision (back in the guild) wins over it")
local snaps = TT:Merge({ status = "trial", startDate = 20, snapshots = { 1, 2, 3 } }, { status = "expired", startDate = 10, snapshots = {} })
check(snaps.startDate == 10 and #snaps.snapshots == 3, "two undecided copies: the earlier start, with the longer snapshots")

-- ── 9. Somebody who left the guild ──────────────────────────────────────
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
now = T0 + 700 * DAY
local gone = use("Off", true)
TT:SetAuto(true); TT:SetDays(7)
rosterUpdate()
local spam = key("Spam")
table.insert(ROSTER, { "Spam", 6 }); rosterUpdate()
check(gone.trials[spam] and gone.trials[spam].leftAt == nil, "(Spam is a trial)")
leaves("Spam")
sent = {}
rosterUpdate()
check(gone.trials[spam].leftAt == now and count("TR") == 1,
  "an officer's whole roster without them marks the trial left, and the officers are told")
now = now + 8 * DAY
check(TT:CountReady() == 0 and TT:GetState(spam) == "left" and #TT:GetActiveTrials() == 0 and TT:GetDaysRemaining(spam) == nil,
  "past its end, it is not ready to review, not counted, not active")
check(TT:IsTrial(spam) and TT:GetAllTrials()[1].group == 3, "still undecided, listed with the decided")
printed = {}
TT:CheckReady()
check(#printed == 0, "and the login line does not count it")
local marked = lastOf("TR")
use("Off2", true)
deliver(marked, "Off")
check(dbs.Off2.trials[spam] and dbs.Off2.trials[spam].leftAt ~= nil, "the mark travels with the trial")
use("Off")
table.insert(ROSTER, { "Spam", 6 }); rosterUpdate()
check(gone.trials[spam].leftAt == nil and TT:GetState(spam) == "review" and TT:CountReady() == 1,
  "back in the guild: the mark goes, and the trial waits for a decision again")

-- ── 10. An officer who missed the join never reopens a decision ────────
local function decidedAnn(offOnline)
  roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
  now = now + 100 * DAY
  use("Off", true); TT:SetAuto(true); TT:SetDays(7); rosterUpdate()
  use("Off2", true); TT:SetAuto(true); TT:SetDays(7); rosterUpdate()
  use("Off")                                         -- Off2 is away when Ann joins and is approved
  table.insert(ROSTER, { "Ann", 6 }); rosterUpdate()
  now = now + 8 * DAY
  TT:AddTrialNote(key("Ann"), "solid")
  TT:UpdateStatus(key("Ann"), TT.STATUS.APPROVED); local approved = lastOf("TR")
  now = now + DAY
  login("Off2")
  sent = {}
  if offOnline then deliver(approved, "Off") end     -- Off's answer, inside the settle window
  rosterUpdate(); settle()
  local fromOff2 = lastOf("TR")
  if not offOnline then
    check(fromOff2 and dbs.Off2.trials[key("Ann")].sponsor == "Guild OS", "(alone, Off2's catch-up starts its own copy)")
    deliver(approved, "Off")                         -- Off's decision reaches Off2 later
  end
  use("Off")
  if fromOff2 then deliver(fromOff2, "Off2") end
  return dbs.Off.trials[key("Ann")], dbs.Off2.trials[key("Ann")], fromOff2
end
local annOff, annOff2, reopened = decidedAnn(true)
check(annOff2.status == "approved" and reopened == nil,
  "Off online: Off2 reads Ann's approval in the window and starts nothing over it")
check(annOff.status == "approved", "and Ann stays approved for Off")
annOff, annOff2 = decidedAnn(false)
check(annOff.status == "approved" and annOff2.status == "approved",
  "Off offline: Off2's automatic copy gives way to the approval on both, whatever its later start")
check(#annOff.notes == 1 and #annOff2.notes == 1 and annOff2.notes[1].text == "solid", "with the notes kept")
local auto = TT:Merge({ status = "denied", startDate = 5, resolvedDate = 9, notes = { { author = "Off", timestamp = 7 } } },
  { status = "trial", startDate = 30, sponsor = "Guild OS", notes = { { author = "Off2", timestamp = 31 } } })
check(auto.status == "denied" and #auto.notes == 2, "an automatic trial never wins over a decision, and its notes are kept")
check(TT:Merge({ status = "trial", startDate = 30, sponsor = "Off" }, { status = "denied", startDate = 5, resolvedDate = 9 }).status == "trial",
  "an officer's own trial after a decision still wins over it")

-- ── 11. A character that was no officer for a while: the first look again ─
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
now = now + 100 * DAY
use("Off", true); rosterUpdate()
local demoted = use("Off2", true)
rosterUpdate()
ROSTER[2][2] = 5                                     -- Off2 demoted
table.insert(ROSTER, { "Quiet3", 6 })                -- joins, the switch off
use("Off"); rosterUpdate()
now = now + DAY
TT:SetAuto(true); local switchOn = lastOf("SV", "trialauto")
use("Off2"); deliver(switchOn, "Off"); rosterUpdate()
check(TT:IsAutoOn() and demoted.trialBaseline[key("Quiet3")] == nil, "demoted, Off2 hears the switch and takes nobody in")
now = now + 30 * DAY
ROSTER[2][2] = 1                                     -- promoted again a month later
rosterUpdate()
check(trials(demoted) == 0 and demoted.trialBaseline[key("Quiet3")],
  "promoted again: the first look only takes the roster, nobody who has been here a month is a trial")
table.insert(ROSTER, { "After", 6 }); rosterUpdate()
check(demoted.trials[key("After")] and trials(demoted) == 1, "and whoever joins after that is")
-- The same when the guild narrows its officer ranks and widens them again.
ROSTER[2][2] = 2
demoted.settings.officerMaxRank = 2
rosterUpdate()
demoted.settings.officerMaxRank = 1                  -- narrowed: Off2's rank 2 is no officer
table.insert(ROSTER, { "Narrow", 6 }); rosterUpdate()
now = now + 10 * DAY
demoted.settings.officerMaxRank = 2                  -- widened again
rosterUpdate()
check(demoted.trials[key("Narrow")] == nil and demoted.trialBaseline[key("Narrow")],
  "a threshold narrowed, then widened: the first look again only takes the roster")
check(demoted.trialScannedAsOfficer[key("Off2")] == true, "(each character's last look is kept by its own key)")
-- The switch turned on while only a non-officer alt of the officer's account was online to hear it.
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 }, { "OffAlt", 6 } })
now = now + 100 * DAY
local acct = use("Off", true)
rosterUpdate()                                       -- the officer's roster seen; the switch off; logs out
table.insert(ROSTER, { "N1", 6 })                    -- joins before the switch is on
use("Off2", true); TT:SetAuto(true); local heard = lastOf("SV", "trialauto")
login("OffAlt", acct)
deliver(heard, "Off2")
settle()
check(TT:IsAutoOn() and acct.trialBaselinePending == true and acct.trialBaseline[key("N1")] == nil,
  "the alt stores the switch and leaves a mark, and takes nobody in")
login("Off", acct)
settle()
check(acct.trials[key("N1")] == nil and acct.trialBaselinePending == nil and acct.trialBaseline[key("N1")],
  "the officer's next look honours it: only the roster is taken, N1 joined before the switch and is no trial")
table.insert(ROSTER, { "N3", 6 }); rosterUpdate()
check(acct.trials[key("N3")] and trials(acct) == 1, "whoever joins after that look is")

-- ── 12. Several officers online at once: one trial ────────────────────
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
local twin = key("Twin")
now = T0 + 400 * DAY
for _, who in ipairs({ "Off", "Off2" }) do
  use(who, true)
  TT:SetAuto(true)
end
-- Both see the join line (each asks for the roster), and each one's roster update starts the trial.
local function seen(who)
  use(who); sent, requests = {}, 0
  join("Twin")
  check(requests == 1 and trials(GuildOS.db) == 0, who .. ": the join line only asks for the roster")
  rosterUpdate()
  return lastOf("TR")
end
table.insert(ROSTER, { "Twin", 6 })
local fromA, fromB = seen("Off"), seen("Off2")
use("Off"); deliver(fromB, "Off2")
use("Off2"); deliver(fromA, "Off")
local A, B = dbs.Off.trials[twin], dbs.Off2.trials[twin]
check(fromA and fromB and trials(dbs.Off) == 1 and trials(dbs.Off2) == 1,
  "two officers saw the same join in the same second: one trial each")
check(A.startDate == B.startDate and A.sponsor == B.sponsor and A.status == B.status, "and the same trial on both")
-- The second officer's roster a second behind: both keep the earlier copy.
now = now + DAY
roster({ { "Off", 1 }, { "Off2", 1 }, { "Mem", 5 } })
use("Off", true); TT:SetAuto(true)
use("Off2", true); TT:SetAuto(true)
table.insert(ROSTER, { "Twin", 6 })
fromA = seen("Off")
now = now + 1
fromB = seen("Off2")
use("Off"); deliver(fromB, "Off2")
use("Off2"); deliver(fromA, "Off")
check(dbs.Off.trials[twin].startDate == now - 1 and dbs.Off2.trials[twin].startDate == now - 1 and trials(dbs.Off) == 1,
  "a second apart, both keep the earlier one: still one trial")
-- And the roster updates that follow add nothing on either.
for _, who in ipairs({ "Off", "Off2" }) do
  use(who)
  rosterUpdate()
  check(trials(GuildOS.db) == 1, who .. ": the next roster update starts no second trial")
end

print(("trial-guild: %d checks passed"):format(checks))
