-- Member keys carried inside synced payloads, on WoW: Forever (issue #97), run against the real
-- Core, Compat, Utils and the modules that receive them.
--
-- Issue #95 made a member key agree within a client: on Forever it is always the name plus this
-- client's realm. But a guild's clients answer different realms, so a key BUILT ON THE SENDER
-- and carried inside a payload ("Cherry Arrow-Classic Beta PvE") still split the person here
-- ("Cherry Arrow-Classic Beta PvE 2"): attendance, DKP, alt links, officer notes, trials,
-- raiders and core rosters. Every receive path now localizes such keys. Anniversary keys, where
-- a realm is part of who somebody is, pass through untouched.
--
--   luajit -e 'ADDON="."' tools/forever-payload-keys.lua
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

local MY = "Classic Beta PvE 2"
local THEIRS = "Classic Beta PvE"
local function mine(name) return name .. "-" .. MY end
local function theirs(name) return name .. "-" .. THEIRS end

local store, handlers = {}, {}
local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    function f:Hide() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Chehul" end
  end
  function GetRealmName() return MY end
  function GetServerTime() return 1791000000 end
  function GetTime() return 1 end
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1 end
  local ROSTER = { { "Off Icer", 1 }, { "Cherry Arrow", 5 }, { "Chehul Costa", 1 } }
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2] end end
  C_Timer = { After = function() end, NewTicker = function() end,
              NewTimer = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  LibStub("GuildOS-LibSerialize").Serialize = function(_, t) store[#store + 1] = t; return "#" .. #store end
  LibStub("GuildOS-LibSerialize").Deserialize = function(_, s)
    local t = store[tonumber((s or ""):match("^#(%d+)$") or "")]
    return t ~= nil, t
  end
  LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
  LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  for _, m in ipairs({ "CommSystem", "RaidTracker", "Points", "AltAutoDetect", "OfficerNotes", "TrialTracker",
                       "RaiderRoster", "CoreManager", "Alliance" }) do
    dofile(ADDON .. "/Modules/" .. m .. ".lua")
  end
  GuildOS.db = { settings = {}, members = {}, altLinks = {}, officerNotes = {}, trials = {}, raiders = {}, cores = {},
                raidTracker = { sessions = {}, attendance = {}, deletedSessions = {} } }
  handlers = {}
  GuildOS.SyncService = { On = function(_, dom, fn) handlers[dom] = fn end, Publish = function() end,
                         ShouldApply = function() return true end, SetRevision = function() end }
  GuildOS.CommSystem.pendingMessages = {}
  GuildOS.CommSystem.SendMessage = function() end       -- what a change re-broadcasts is not the question here
  GuildOS.db.points = { mode = "dkp", config = {}, standings = {}, log = {}, appliedOps = {}, appliedCount = 0 }
end
local function ser(t) return LibStub("GuildOS-LibSerialize"):Serialize(t) end

-- ── 0. The helper ───────────────────────────────────────────────────────
load("forever")
check(GuildOS:LocalMemberKey(theirs("Cherry Arrow")) == mine("Cherry Arrow"), "forever: another client's key becomes this client's")
check(GuildOS:LocalMemberKey(mine("Cherry Arrow")) == mine("Cherry Arrow"), "forever: this client's own key stays")
check(GuildOS:LocalMemberKey("Cherry Arrow") == mine("Cherry Arrow"), "forever: a bare name gets this client's realm")
check(GuildOS:LocalMemberKey(nil) == nil and GuildOS:LocalMemberKey("") == "" and GuildOS:LocalMemberKey(5) == 5,
  "forever: nothing that is not a key is touched")
check(GuildOS:LocalMemberKey("ally:Chehul Costa") == "ally:Chehul Costa", "forever: an allied guild's realm-free key is left alone")

-- ── 1. Raid attendance and sessions ─────────────────────────────────────
GuildOS.RaidTracker:HandleIncoming(ser({
  attendance = { [""] = { [theirs("Cherry Arrow")] = { raids = 3, lastRaid = 100 } } },
  sessions = { s1 = { players = { [theirs("Cherry Arrow")] = true }, startTime = 1, instanceID = 409 } },
}))
local rt = GuildOS.db.raidTracker
check(rt.attendance[""][mine("Cherry Arrow")] and rt.attendance[""][theirs("Cherry Arrow")] == nil,
  "forever: an officer's attendance lands on the member's own key")
check(rt.sessions.s1 and rt.sessions.s1.players[mine("Cherry Arrow")] and not rt.sessions.s1.players[theirs("Cherry Arrow")],
  "forever: a received session lists its players under this client's keys")
GuildOS.RaidTracker:HandleIncoming(ser({
  attendance = { [theirs("Old Flat")] = { raids = 1, lastRaid = 50 },
                 ["Team-A"] = { [theirs("Cherry Arrow")] = { raids = 1, lastRaid = 60 } } },
}))
check(rt.attendance[""][mine("Old Flat")] and rt.attendance[""][theirs("Old Flat")] == nil,
  "forever: the old flat attendance format is localized too")
check(rt.attendance["Team-A"] and rt.attendance["Team-A"][mine("Cherry Arrow")] and rt.attendance["Team-A-" .. MY] == nil,
  "forever: a group tag is a group, never rewritten as a member key")

-- ── 2. Points ───────────────────────────────────────────────────────────
local P = GuildOS.Points
P:OnSync({ act = "delta", data = { entries = { { op = "o1", key = theirs("Cherry Arrow"), delta = 10, name = "Cherry Arrow" } } } })
local pool = P:GetDBForCore(nil)
check(pool.standings[mine("Cherry Arrow")] and pool.standings[mine("Cherry Arrow")].current == 10
  and pool.standings[theirs("Cherry Arrow")] == nil, "forever: a DKP delta lands on the member's own key")
P:OnSync({ act = "snapshot", rev = 2, data = { standings = { [theirs("Cherry Arrow")] = { current = 40, earned = 40, spent = 0 } } } })
pool = P:GetDBForCore(nil)
check(pool.standings[mine("Cherry Arrow")] and pool.standings[mine("Cherry Arrow")].current == 40
  and pool.standings[theirs("Cherry Arrow")] == nil, "forever: a DKP snapshot keys its standings this client's way")
P:OnSync({ act = "snapshot", rev = 3, data = { config = { startingPoints = 100 }, standings = {
  [theirs("Split Man")] = { current = 110, earned = 10, spent = 0 },
  ["Split Man-Third Realm"] = { current = 95, earned = 0, spent = 5 } } } })
pool = P:GetDBForCore(nil)
local sm = pool.standings[mine("Split Man")]
check(sm and sm.current == 105 and sm.earned == 10 and sm.spent == 5,
  "forever: one member under two of the sender's keys adds up, the starting points counted once")

-- ── 3. Alt links (AL) ───────────────────────────────────────────────────
GuildOS.CommSystem:OnMessageReceived("S:AL:" .. ser({ [theirs("Cherry Alt")] = theirs("Cherry Arrow") }), "GUILD", "Off Icer")
check(GuildOS.db.altLinks[mine("Cherry Alt")] == mine("Cherry Arrow") and GuildOS.db.altLinks[theirs("Cherry Alt")] == nil,
  "forever: an officer's alt links key both sides this client's way")
GuildOS.CommSystem:OnMessageReceived("S:AL:" .. ser({ [theirs("Bob Bee")] = "Bob Bee-Third Realm" }), "GUILD", "Off Icer")
check(GuildOS.db.altLinks[mine("Bob Bee")] == nil, "forever: one split person is never linked as their own alt")

-- ── 4. A member's own alt claim (SELF_ALT) ──────────────────────────────
GuildOS.db.altLinks = {}
GuildOS.AltAutoDetect:HandleSelfClaim("Cherry Arrow", ser({ main = theirs("Cherry Arrow"), alts = { theirs("Cherry Two") } }))
check(GuildOS.db.altLinks[mine("Cherry Two")] == mine("Cherry Arrow"),
  "forever: a member's own claim from another realm is recognised as theirs and applied")
GuildOS.AltAutoDetect:HandleSelfClaim("Cherry Arrow", ser({ unlink = { theirs("Cherry Two") } }))
check(GuildOS.db.altLinks[mine("Cherry Two")] == nil, "forever: and so is a member's own unlink, sent with no alts")
local found = GuildOS.AltAutoDetect:DetectOwnAlts({ [theirs("Chehul Costa")] = { level = 60 }, [theirs("Chehul Two")] = { level = 20 } },
  { [mine("Chehul Costa")] = true, [mine("Chehul Two")] = true }, {})
check(found and found.main == mine("Chehul Costa") and #found.group == 2,
  "forever: this account's characters recorded on another realm are still found in the guild")
local tests = {}
GuildOS.SelfTest = { Register = function(_, name, fn) tests[name] = fn end }
GuildOS.AltAutoDetect:_RegisterTests()
for name, fn in pairs(tests) do
  local ok, why = fn()
  check(ok, "forever: /gos selftest " .. name .. " passes (" .. tostring(why) .. ")")
end
GuildOS.SelfTest = nil

-- ── 5. Officer notes ────────────────────────────────────────────────────
GuildOS.OfficerNotes:HandleIncoming(ser({ target = theirs("Cherry Arrow"), note = { author = "Off Icer", timestamp = 5, text = "hi" } }))
check(GuildOS.db.officerNotes[mine("Cherry Arrow")] and GuildOS.db.officerNotes[theirs("Cherry Arrow")] == nil,
  "forever: an officer note lands on the sheet the member's line reads")
GuildOS.OfficerNotes:HandleAllIncoming(ser({ [theirs("Cherry Arrow")] = { notes = { { author = "B", timestamp = 6, text = "x" } }, tags = {} } }))
check(#GuildOS.db.officerNotes[mine("Cherry Arrow")].notes == 2 and GuildOS.db.officerNotes[theirs("Cherry Arrow")] == nil,
  "forever: a bulk sync merges into the same sheet")

-- ── 6. Trials ───────────────────────────────────────────────────────────
GuildOS.TrialTracker:HandleIncoming(ser({ [theirs("Cherry Arrow")] = { startDate = 1, status = "active" } }))
check(GuildOS.db.trials[mine("Cherry Arrow")] and GuildOS.db.trials[theirs("Cherry Arrow")] == nil,
  "forever: a trial is kept under the member's own key")
GuildOS.TrialTracker:HandleIncoming(ser({ [theirs("Cherry Arrow")] = { startDate = 0, status = "stale" } }))
check(GuildOS.db.trials[mine("Cherry Arrow")].status == "active", "forever: an older copy of a held trial does not replace it")

-- ── 7. Raiders ──────────────────────────────────────────────────────────
GuildOS.RaiderRoster:HandleIncoming("Off Icer", ser({ [theirs("Cherry Arrow")] = { updatedAt = 1, roles = {} } }))
check(GuildOS.db.raiders[mine("Cherry Arrow")] and GuildOS.db.raiders[theirs("Cherry Arrow")] == nil,
  "forever: a raider record is kept under the member's own key")

-- ── 8. Core sign-ups and rosters ────────────────────────────────────────
GuildOS.CoreManager:InitSync()
local CM = GuildOS.CoreManager
CM:Create("Main")
handlers["core.signup"]({ data = { coreName = "Main", playerKey = theirs("Somebody Else"), info = { role = "rdps" } } }, "Cherry Arrow")
local signups = GuildOS.db.cores.Main.signups or {}
check(signups[mine("Cherry Arrow")] and not signups[theirs("Somebody Else")] and not signups[mine("Somebody Else")],
  "forever: a sign-up is filed under who sent it, never under a key the payload claims")
handlers["core.signup"]({ data = { coreName = "Main", info = { name = "Not Me", role = "rdps" } } }, "Cherry Arrow")
check(GuildOS.db.cores.Main.signups[mine("Cherry Arrow")].name == "Cherry Arrow", "forever: and named as who sent it")
handlers["core.roster"]({ data = { coreName = "Main", members = { [theirs("Cherry Arrow")] = { role = "mdps" } } } }, "Off Icer")
check(GuildOS.db.cores.Main.members[mine("Cherry Arrow")] and GuildOS.db.cores.Main.members[theirs("Cherry Arrow")] == nil,
  "forever: a core roster from another officer keys its members this client's way")

-- ── 9. The alliance bridge: every client elects the same one ────────────
local A = GuildOS.Alliance or GuildOS.Alliance
local here = A.ElectBridge({ mine("Ann Lee"), mine("Bob Ray"), mine("Cid Moe"), mine("Dee Fox") })
GetRealmName = function() return THEIRS end
local there = A.ElectBridge({ theirs("Ann Lee"), theirs("Bob Ray"), theirs("Cid Moe"), theirs("Dee Fox") })
GetRealmName = function() return MY end
check(here:match("^([^-]+)") == there:match("^([^-]+)"), "forever: clients on different realms elect the same bridge")

-- ── 9b. What an earlier version stored with another client's keys ───────
load("forever")
GuildOS.db.raidTracker = {
  attendance = { [""] = { [theirs("Cherry Arrow")] = { raids = 4, lastRaid = 9 }, [mine("Cherry Arrow")] = { raids = 2, lastRaid = 20 },
                          [theirs("Tie Guy")] = { raids = 2, lastRaid = 30 }, [mine("Tie Guy")] = { raids = 2, lastRaid = 10 } },
                 ["Team-A"] = { [theirs("Cherry Arrow")] = { raids = 1 } } },
  sessions = { s9 = { players = { [theirs("Cherry Arrow")] = true, [mine("Chehul Costa")] = true },
                      snapshots = { { members = { [theirs("Cherry Arrow")] = { name = "Cherry Arrow" } } } } } },
}
GuildOS.db.officerNotes = { [theirs("Cherry Arrow")] = { notes = { { author = "A", timestamp = 1 } }, tags = { t = "x" } },
                           [mine("Cherry Arrow")] = { notes = { { author = "B", timestamp = 2 }, { author = "A", timestamp = 1 } }, tags = {} } }
GuildOS.db.trials = { [theirs("Cherry Arrow")] = { startDate = 50 },
                     [mine("Cherry Arrow")] = { startDate = 10, resolvedDate = 90, notes = { { author = "A", timestamp = 60 } } } }
GuildOS.db.raiders = { [theirs("Cherry Arrow")] = { updatedAt = 5 } }
GuildOS.db.altLinks = { [theirs("Cherry Alt")] = theirs("Cherry Arrow"), [theirs("Bob Bee")] = mine("Bob Bee") }
GuildOS.db.points = { config = { startingPoints = 100 }, standings = {
  [theirs("Cherry Arrow")] = { current = 110, earned = 10, spent = 0 }, [mine("Cherry Arrow")] = { current = 95, earned = 0, spent = 5 },
  [theirs("Junk Side")] = 5, [mine("Junk Side")] = { current = 100 },
  [theirs("Junk Two")] = { current = 100 }, [mine("Junk Two")] = 5 } }
GuildOS.db.cores = { Main = { members = { [theirs("Cherry Arrow")] = { role = "rdps" } }, signups = { [theirs("Cherry Arrow")] = {} },
                             points = { standings = { [theirs("Cherry Arrow")] = { current = 3, earned = 3, spent = 0 } } } } }
GuildOS.DataCollector = nil
dofile(ADDON .. "/Modules/DataCollector.lua")
GuildOS.DataCollector:Initialize()
local db = GuildOS.db
check(db.raidTracker.attendance[""][mine("Cherry Arrow")].raids == 4 and db.raidTracker.attendance[""][theirs("Cherry Arrow")] == nil,
  "forever: stored attendance moves to the member's key, the record with more raids kept")
check(db.raidTracker.attendance[""][mine("Tie Guy")].lastRaid == 30, "forever: on equal raids the later attendance record is kept")
check(db.raidTracker.attendance["Team-A"] and db.raidTracker.attendance["Team-A"][mine("Cherry Arrow")]
  and db.raidTracker.attendance["Team-A-" .. MY] == nil, "forever: a stored group tag stays a group")
check(db.raidTracker.sessions.s9.players[mine("Cherry Arrow")] and not db.raidTracker.sessions.s9.players[theirs("Cherry Arrow")],
  "forever: a stored session's players are localized, so the site gets no ghost")
local snap = db.raidTracker.sessions.s9.snapshots[1].members
check(snap[mine("Cherry Arrow")] and snap[theirs("Cherry Arrow")] == nil,
  "forever: and so are its snapshots, or attendance rebuilt from them counts the player late and gone early")
check(#db.officerNotes[mine("Cherry Arrow")].notes == 2 and db.officerNotes[mine("Cherry Arrow")].tags.t == "x"
  and db.officerNotes[theirs("Cherry Arrow")] == nil, "forever: stored officer notes merge onto one sheet, each note once")
check(db.trials[mine("Cherry Arrow")].resolvedDate == 90 and db.trials[theirs("Cherry Arrow")] == nil,
  "forever: the trial with the latest activity is kept, a resolution counting, not just the start")
check(db.raiders[mine("Cherry Arrow")] and db.raiders[theirs("Cherry Arrow")] == nil, "forever: a stored raider moves")
check(db.altLinks[mine("Cherry Alt")] == mine("Cherry Arrow") and db.altLinks[mine("Bob Bee")] == nil,
  "forever: stored alt links are localized and a self-link dropped")
local ca = db.points.standings[mine("Cherry Arrow")]
check(ca.current == 105 and ca.earned == 10 and ca.spent == 5 and db.points.standings[theirs("Cherry Arrow")] == nil,
  "forever: stored DKP under two keys adds up, the starting points counted once")
check(db.points.standings[mine("Junk Side")].current == 100 and db.points.standings[mine("Junk Two")].current == 100,
  "forever: a value that is not a record never replaces one, whichever comes first")
check(db.cores.Main.points.standings[mine("Cherry Arrow")].current == 3, "forever: stored DKP moves in each core's pool too")
check(db.cores.Main.members[mine("Cherry Arrow")] and db.cores.Main.signups[mine("Cherry Arrow")], "forever: stored core rosters and sign-ups move")
local before = db.trials
GuildOS.DataCollector:Initialize()
check(db.trials[mine("Cherry Arrow")].resolvedDate == 90 and before ~= nil, "forever: running it again changes nothing")
GuildOS.db.officerNotes = { [theirs("Bad Data")] = { notes = "junk", tags = 3 }, [mine("Bad Data")] = { notes = { 5, { author = "A", timestamp = 1 } } } }
GuildOS.db.raidTracker.attendance = { [""] = { [theirs("Bad Data")] = { raids = "x" }, [mine("Bad Data")] = { raids = 1 } } }
GuildOS.db.trials = { [theirs("Bad Data")] = { startDate = 5, notes = { 7 } }, [mine("Bad Data")] = { startDate = 5 } }
GuildOS.db.raiders = { [theirs("Bad Data")] = { updatedAt = 1 } }
GuildOS.db.points = { config = { startingPoints = "lots" }, standings = { [theirs("Bad Data")] = { current = 1 }, [mine("Bad Data")] = { current = 2 } } }
check(db.storedKeysLocalized == MY, "forever: the migration marks the database as done")
GuildOS.db.storedKeysLocalized = nil
check(pcall(GuildOS.LocalizeStoredMemberTables, GuildOS), "forever: stored junk does not break the migration")
check(#GuildOS.db.officerNotes[mine("Bad Data")].notes == 1, "forever: and the notes that are notes survive it")
check(GuildOS.db.raidTracker.attendance[""][mine("Bad Data")] and GuildOS.db.raidTracker.attendance[""][theirs("Bad Data")] == nil,
  "forever: attendance with a junk raid count still moves")
check(GuildOS.db.trials[mine("Bad Data")] and GuildOS.db.raiders[mine("Bad Data")] and GuildOS.db.points.standings[mine("Bad Data")].current == 3,
  "forever: a malformed trial note leaves the trial and every later table moved")
GuildOS.db.raiders = { [theirs("Later On")] = {} }
GuildOS:LocalizeStoredMemberTables()
check(GuildOS.db.raiders[theirs("Later On")], "forever: once done, it is not redone on every login")
local registered = 0
CreateFrame = function() return { RegisterEvent = function() registered = registered + 1 end, SetScript = function() end } end
GuildOS.LocalizeStoredMemberTables = function() error("boom") end
check(pcall(GuildOS.DataCollector.Initialize, GuildOS.DataCollector) and registered > 0,
  "forever: a migration that throws still lets the data collector start")

-- ── 9c. Each merge decides, whichever of the two keys comes first ───────
-- `win` is stored under one of a member's two keys and `lose` under the other, both ways round.
-- The keys go in in the same order each time, so pairs() meets them in the same order and only
-- the values swap: one of the two runs always hands the merge the loser first.
local function both(what, name, put, win, lose, ok)
  for _, flip in ipairs({ false, true }) do
    load("forever")
    local v = flip and { [mine(name)] = win(), [theirs(name)] = lose() } or { [theirs(name)] = win(), [mine(name)] = lose() }
    put(GuildOS.db, theirs(name), v[theirs(name)])
    put(GuildOS.db, mine(name), v[mine(name)])
    GuildOS:LocalizeStoredMemberTables()
    check(ok(GuildOS.db, mine(name)), what .. (flip and " (the winner under this client's key)" or " (the winner under the other's key)"))
  end
end
local function att(db, k, v) db.raidTracker.attendance[""] = db.raidTracker.attendance[""] or {}; db.raidTracker.attendance[""][k] = v end
both("forever: more raids win", "Ann Lee", att, function() return { raids = 5, lastRaid = 1 } end,
  function() return { raids = 2, lastRaid = 99 } end, function(db, k) return db.raidTracker.attendance[""][k].raids == 5 end)
both("forever: on equal raids the later one wins", "Ann Lee", att, function() return { raids = 2, lastRaid = 30 } end,
  function() return { raids = 2, lastRaid = 10 } end, function(db, k) return db.raidTracker.attendance[""][k].lastRaid == 30 end)
both("forever: both sheets' tags are kept", "Ann Lee", function(db, k, v) db.officerNotes[k] = v end,
  function() return { notes = {}, tags = { a = "1" } } end, function() return { notes = {}, tags = { b = "2" } } end,
  function(db, k) return db.officerNotes[k].tags.a == "1" and db.officerNotes[k].tags.b == "2" end)
both("forever: the trial with the later activity wins", "Ann Lee", function(db, k, v) db.trials[k] = v end,
  function() return { startDate = 50 } end, function() return { startDate = 10 } end,
  function(db, k) return db.trials[k].startDate == 50 end)
both("forever: the raider updated later wins", "Ann Lee", function(db, k, v) db.raiders[k] = v end,
  function() return { updatedAt = 9 } end, function() return { updatedAt = 1 } end,
  function(db, k) return db.raiders[k].updatedAt == 9 end)
both("forever: a value that is not a record never replaces one", "Ann Lee", function(db, k, v) db.points.standings[k] = v end,
  function() return { current = 100 } end, function() return 5 end,
  function(db, k) return type(db.points.standings[k]) == "table" and db.points.standings[k].current == 100 end)
load("forever")
GuildOS.db.raidTracker.attendance = { [theirs("Flat Guy")] = { raids = 1, lastRaid = 5 } }
GuildOS:LocalizeStoredMemberTables()
check(GuildOS.db.raidTracker.attendance[theirs("Flat Guy")].raids == 1,
  "forever: the old flat attendance format is left for the raid tracker to spot and rebuild")
load("forever")
GuildOS.db.trials = { [theirs("Ann Lee")] = { startDate = 1 }, [mine("Ann Lee")] = { startDate = 2 } }
GuildOS.db.raiders = { [theirs("Ann Lee")] = { updatedAt = 1 } }
GuildOS.db.cores = { Main = { members = { [theirs("Ann Lee")] = {} } } }
local realMerge = GuildOS.TrialTracker.Merge
GuildOS.TrialTracker.Merge = function() error("boom") end
check(pcall(GuildOS.LocalizeStoredMemberTables, GuildOS) and GuildOS.db.raiders[mine("Ann Lee")] and GuildOS.db.cores.Main.members[mine("Ann Lee")],
  "forever: one table's step failing leaves every other table moved")
check(GuildOS.db.storedKeysLocalized == nil and GuildOS.db.trials[theirs("Ann Lee")], "forever: and the database is not marked done")
GuildOS.TrialTracker.Merge = realMerge
GuildOS:LocalizeStoredMemberTables()
check(GuildOS.db.trials[mine("Ann Lee")] and GuildOS.db.trials[theirs("Ann Lee")] == nil and GuildOS.db.storedKeysLocalized == MY,
  "forever: so the next login moves what failed, and only then marks it done")
load("forever")
GuildOS.db.cores = { Main = { points = { standings = { [theirs("Ann Lee")] = { current = "x" }, [mine("Ann Lee")] = { current = 1 } } },
                             members = { [theirs("Ann Lee")] = {} }, signups = { [theirs("Ann Lee")] = {} } } }
GuildOS:LocalizeStoredMemberTables()
check(GuildOS.db.cores.Main.members[mine("Ann Lee")] and GuildOS.db.cores.Main.signups[mine("Ann Lee")] and GuildOS.db.storedKeysLocalized == nil,
  "forever: a core whose points fail still has its roster and sign-ups moved, and is retried")
load("forever")

local TT = GuildOS.TrialTracker
local ta, tb = { startDate = 5, notes = { { author = "A", timestamp = 3 } } }, { startDate = 5, notes = { { author = "B", timestamp = 4 } } }
check(TT:Merge(ta, tb) == ta and #ta.notes == 2, "trials: a tie keeps the held copy and merges the notes")
check(TT:Merge({ startDate = 10 }, { startDate = 5, resolvedDate = 20 }).resolvedDate == 20, "trials: a later resolution is later activity")
check(TT:Merge({ startDate = 10 }, { startDate = 5, notes = { { timestamp = 30 } } }).startDate == 5, "trials: so is a later note")
check(TT:Merge({ startDate = 10 }, { startDate = 5 }).startDate == 10, "trials: an older copy never replaces a newer one")
check(pcall(TT.Merge, TT, { startDate = 5, notes = { 7 } }, { startDate = 5, notes = { 8, { author = "A", timestamp = 1 } } }),
  "trials: a note that is not a note breaks no merge")
check(pcall(TT.Merge, TT, { startDate = 5, notes = 3 }, { startDate = 5, notes = { { author = "A", timestamp = 1 } } })
  and pcall(TT.Merge, TT, { startDate = 5, notes = {} }, { startDate = 5, notes = "x" }), "trials: nor do notes that are not a list")

local sheet = GuildOS.OfficerNotes:MergeSheet(
  { notes = { { author = "A", timestamp = 1, text = "x" }, { author = "A", timestamp = 1, text = "y" } }, tags = { t = "old" } },
  { notes = { { author = "A", timestamp = 1, text = "x" }, { author = "B", timestamp = 9 } }, tags = { t = "new" } })
check(#sheet.notes == 3 and sheet.notes[1].timestamp == 9,
  "officer notes: every held note stays, an arriving duplicate is dropped, newest first")
check(sheet.tags.t == "new", "officer notes: an arriving tag wins")
local okHeld, held = pcall(GuildOS.OfficerNotes.MergeSheet, GuildOS.OfficerNotes, { notes = { 5, { author = "A", timestamp = 1 } } }, { notes = { 6 } })
check(okHeld and #held.notes == 1, "officer notes: a note that is not a note, held or arriving, is dropped and breaks nothing")

-- ── 10. Anniversary: a realm is part of who somebody is ─────────────────
load("anniversary")
check(GuildOS:LocalMemberKey("Bob-Spineshatter") == "Bob-Spineshatter", "anniversary: another realm's key passes through")
GuildOS.OfficerNotes:HandleIncoming(ser({ target = "Bob-Spineshatter", note = { author = "A", timestamp = 1 } }))
check(GuildOS.db.officerNotes["Bob-Spineshatter"], "anniversary: a note for another realm's player stays theirs")
A = GuildOS.Alliance or GuildOS.Alliance
check(A.ElectBridge({ "Cid-R", "Ann-R", "Bob-R" }) == A.ElectBridge({ "Ann-R", "Bob-R", "Cid-R" }),
  "anniversary: the bridge election is as it was")
local loser, winner = "Ann-R1", "Ann-R2"
if A.Hash(loser) < A.Hash(winner) then loser, winner = winner, loser end
check(A.Hash(loser) ~= A.Hash(winner) and A.ElectBridge({ loser, winner }) == winner,
  "anniversary: the election still hashes the whole key, realm included")
GuildOS.CoreManager:InitSync()
GuildOS.CoreManager:Create("Main")
handlers["core.signup"]({ data = { coreName = "Main", info = {} } }, "Bob-Spineshatter")
handlers["core.signup"]({ data = { coreName = "Main", info = {} } }, "Ann")
check(GuildOS.db.cores.Main.signups["Bob-Spineshatter"] and GuildOS.db.cores.Main.signups["Ann-" .. MY],
  "anniversary: a sign-up is filed under the sender's own realm")
GuildOS.db.trials = { ["Bob-Spineshatter"] = { startDate = 1 } }
GuildOS:LocalizeStoredMemberTables()
check(GuildOS.db.trials["Bob-Spineshatter"], "anniversary: the stored-table migration leaves another realm's player alone")

print(("forever-payload-keys: %d checks passed"):format(checks))
