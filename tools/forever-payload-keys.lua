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
  BRutus.db = { settings = {}, members = {}, altLinks = {}, officerNotes = {}, trials = {}, raiders = {}, cores = {},
                raidTracker = { sessions = {}, attendance = {}, deletedSessions = {} } }
  handlers = {}
  BRutus.SyncService = { On = function(_, dom, fn) handlers[dom] = fn end, Publish = function() end,
                         ShouldApply = function() return true end, SetRevision = function() end }
  BRutus.CommSystem.pendingMessages = {}
  BRutus.CommSystem.SendMessage = function() end       -- what a change re-broadcasts is not the question here
  BRutus.db.points = { mode = "dkp", config = {}, standings = {}, log = {}, appliedOps = {}, appliedCount = 0 }
end
local function ser(t) return LibStub("GuildOS-LibSerialize"):Serialize(t) end

-- ── 0. The helper ───────────────────────────────────────────────────────
load("forever")
check(BRutus:LocalMemberKey(theirs("Cherry Arrow")) == mine("Cherry Arrow"), "forever: another client's key becomes this client's")
check(BRutus:LocalMemberKey(mine("Cherry Arrow")) == mine("Cherry Arrow"), "forever: this client's own key stays")
check(BRutus:LocalMemberKey("Cherry Arrow") == mine("Cherry Arrow"), "forever: a bare name gets this client's realm")
check(BRutus:LocalMemberKey(nil) == nil and BRutus:LocalMemberKey("") == "" and BRutus:LocalMemberKey(5) == 5,
  "forever: nothing that is not a key is touched")
check(BRutus:LocalMemberKey("ally:Chehul Costa") == "ally:Chehul Costa", "forever: an allied guild's realm-free key is left alone")

-- ── 1. Raid attendance and sessions ─────────────────────────────────────
BRutus.RaidTracker:HandleIncoming(ser({
  attendance = { [""] = { [theirs("Cherry Arrow")] = { raids = 3, lastRaid = 100 } } },
  sessions = { s1 = { players = { [theirs("Cherry Arrow")] = true }, startTime = 1, instanceID = 409 } },
}))
local rt = BRutus.db.raidTracker
check(rt.attendance[""][mine("Cherry Arrow")] and rt.attendance[""][theirs("Cherry Arrow")] == nil,
  "forever: an officer's attendance lands on the member's own key")
check(rt.sessions.s1 and rt.sessions.s1.players[mine("Cherry Arrow")] and not rt.sessions.s1.players[theirs("Cherry Arrow")],
  "forever: a received session lists its players under this client's keys")
BRutus.RaidTracker:HandleIncoming(ser({
  attendance = { [theirs("Old Flat")] = { raids = 1, lastRaid = 50 },
                 ["Team-A"] = { [theirs("Cherry Arrow")] = { raids = 1, lastRaid = 60 } } },
}))
check(rt.attendance[""][mine("Old Flat")] and rt.attendance[""][theirs("Old Flat")] == nil,
  "forever: the old flat attendance format is localized too")
check(rt.attendance["Team-A"] and rt.attendance["Team-A"][mine("Cherry Arrow")] and rt.attendance["Team-A-" .. MY] == nil,
  "forever: a group tag is a group, never rewritten as a member key")

-- ── 2. Points ───────────────────────────────────────────────────────────
local P = BRutus.Points
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
BRutus.CommSystem:OnMessageReceived("S:AL:" .. ser({ [theirs("Cherry Alt")] = theirs("Cherry Arrow") }), "GUILD", "Off Icer")
check(BRutus.db.altLinks[mine("Cherry Alt")] == mine("Cherry Arrow") and BRutus.db.altLinks[theirs("Cherry Alt")] == nil,
  "forever: an officer's alt links key both sides this client's way")
BRutus.CommSystem:OnMessageReceived("S:AL:" .. ser({ [theirs("Bob Bee")] = "Bob Bee-Third Realm" }), "GUILD", "Off Icer")
check(BRutus.db.altLinks[mine("Bob Bee")] == nil, "forever: one split person is never linked as their own alt")

-- ── 4. A member's own alt claim (SELF_ALT) ──────────────────────────────
BRutus.db.altLinks = {}
BRutus.AltAutoDetect:HandleSelfClaim("Cherry Arrow", ser({ main = theirs("Cherry Arrow"), alts = { theirs("Cherry Two") } }))
check(BRutus.db.altLinks[mine("Cherry Two")] == mine("Cherry Arrow"),
  "forever: a member's own claim from another realm is recognised as theirs and applied")
BRutus.AltAutoDetect:HandleSelfClaim("Cherry Arrow", ser({ unlink = { theirs("Cherry Two") } }))
check(BRutus.db.altLinks[mine("Cherry Two")] == nil, "forever: and so is a member's own unlink, sent with no alts")
local found = BRutus.AltAutoDetect:DetectOwnAlts({ [theirs("Chehul Costa")] = { level = 60 }, [theirs("Chehul Two")] = { level = 20 } },
  { [mine("Chehul Costa")] = true, [mine("Chehul Two")] = true }, {})
check(found and found.main == mine("Chehul Costa") and #found.group == 2,
  "forever: this account's characters recorded on another realm are still found in the guild")
local tests = {}
BRutus.SelfTest = { Register = function(_, name, fn) tests[name] = fn end }
BRutus.AltAutoDetect:_RegisterTests()
for name, fn in pairs(tests) do
  local ok, why = fn()
  check(ok, "forever: /gos selftest " .. name .. " passes (" .. tostring(why) .. ")")
end
BRutus.SelfTest = nil

-- ── 5. Officer notes ────────────────────────────────────────────────────
BRutus.OfficerNotes:HandleIncoming(ser({ target = theirs("Cherry Arrow"), note = { author = "Off Icer", timestamp = 5, text = "hi" } }))
check(BRutus.db.officerNotes[mine("Cherry Arrow")] and BRutus.db.officerNotes[theirs("Cherry Arrow")] == nil,
  "forever: an officer note lands on the sheet the member's line reads")
BRutus.OfficerNotes:HandleAllIncoming(ser({ [theirs("Cherry Arrow")] = { notes = { { author = "B", timestamp = 6, text = "x" } }, tags = {} } }))
check(#BRutus.db.officerNotes[mine("Cherry Arrow")].notes == 2 and BRutus.db.officerNotes[theirs("Cherry Arrow")] == nil,
  "forever: a bulk sync merges into the same sheet")

-- ── 6. Trials ───────────────────────────────────────────────────────────
BRutus.TrialTracker:HandleIncoming(ser({ [theirs("Cherry Arrow")] = { startDate = 1, status = "active" } }))
check(BRutus.db.trials[mine("Cherry Arrow")] and BRutus.db.trials[theirs("Cherry Arrow")] == nil,
  "forever: a trial is kept under the member's own key")
BRutus.TrialTracker:HandleIncoming(ser({ [theirs("Cherry Arrow")] = { startDate = 0, status = "stale" } }))
check(BRutus.db.trials[mine("Cherry Arrow")].status == "active", "forever: an older copy of a held trial does not replace it")

-- ── 7. Raiders ──────────────────────────────────────────────────────────
BRutus.RaiderRoster:HandleIncoming("Off Icer", ser({ [theirs("Cherry Arrow")] = { updatedAt = 1, roles = {} } }))
check(BRutus.db.raiders[mine("Cherry Arrow")] and BRutus.db.raiders[theirs("Cherry Arrow")] == nil,
  "forever: a raider record is kept under the member's own key")

-- ── 8. Core sign-ups and rosters ────────────────────────────────────────
BRutus.CoreManager:InitSync()
local CM = BRutus.CoreManager
CM:Create("Main")
handlers["core.signup"]({ data = { coreName = "Main", playerKey = theirs("Somebody Else"), info = { role = "rdps" } } }, "Cherry Arrow")
local signups = BRutus.db.cores.Main.signups or {}
check(signups[mine("Cherry Arrow")] and not signups[theirs("Somebody Else")] and not signups[mine("Somebody Else")],
  "forever: a sign-up is filed under who sent it, never under a key the payload claims")
handlers["core.signup"]({ data = { coreName = "Main", info = { name = "Not Me", role = "rdps" } } }, "Cherry Arrow")
check(BRutus.db.cores.Main.signups[mine("Cherry Arrow")].name == "Cherry Arrow", "forever: and named as who sent it")
handlers["core.roster"]({ data = { coreName = "Main", members = { [theirs("Cherry Arrow")] = { role = "mdps" } } } }, "Off Icer")
check(BRutus.db.cores.Main.members[mine("Cherry Arrow")] and BRutus.db.cores.Main.members[theirs("Cherry Arrow")] == nil,
  "forever: a core roster from another officer keys its members this client's way")

-- ── 9. The alliance bridge: every client elects the same one ────────────
local A = GuildOS.Alliance or BRutus.Alliance
local here = A.ElectBridge({ mine("Ann Lee"), mine("Bob Ray"), mine("Cid Moe"), mine("Dee Fox") })
GetRealmName = function() return THEIRS end
local there = A.ElectBridge({ theirs("Ann Lee"), theirs("Bob Ray"), theirs("Cid Moe"), theirs("Dee Fox") })
GetRealmName = function() return MY end
check(here:match("^([^-]+)") == there:match("^([^-]+)"), "forever: clients on different realms elect the same bridge")

-- ── 9b. What an earlier version stored with another client's keys ───────
load("forever")
BRutus.db.raidTracker = {
  attendance = { [""] = { [theirs("Cherry Arrow")] = { raids = 4, lastRaid = 9 }, [mine("Cherry Arrow")] = { raids = 2, lastRaid = 20 },
                          [theirs("Tie Guy")] = { raids = 2, lastRaid = 30 }, [mine("Tie Guy")] = { raids = 2, lastRaid = 10 } },
                 ["Team-A"] = { [theirs("Cherry Arrow")] = { raids = 1 } } },
  sessions = { s9 = { players = { [theirs("Cherry Arrow")] = true, [mine("Chehul Costa")] = true },
                      snapshots = { { members = { [theirs("Cherry Arrow")] = { name = "Cherry Arrow" } } } } } },
}
BRutus.db.officerNotes = { [theirs("Cherry Arrow")] = { notes = { { author = "A", timestamp = 1 } }, tags = { t = "x" } },
                           [mine("Cherry Arrow")] = { notes = { { author = "B", timestamp = 2 }, { author = "A", timestamp = 1 } }, tags = {} } }
BRutus.db.trials = { [theirs("Cherry Arrow")] = { startDate = 50 },
                     [mine("Cherry Arrow")] = { startDate = 10, resolvedDate = 90, notes = { { author = "A", timestamp = 60 } } } }
BRutus.db.raiders = { [theirs("Cherry Arrow")] = { updatedAt = 5 } }
BRutus.db.altLinks = { [theirs("Cherry Alt")] = theirs("Cherry Arrow"), [theirs("Bob Bee")] = mine("Bob Bee") }
BRutus.db.points = { config = { startingPoints = 100 }, standings = {
  [theirs("Cherry Arrow")] = { current = 110, earned = 10, spent = 0 }, [mine("Cherry Arrow")] = { current = 95, earned = 0, spent = 5 },
  [theirs("Junk Side")] = 5, [mine("Junk Side")] = { current = 100 },
  [theirs("Junk Two")] = { current = 100 }, [mine("Junk Two")] = 5 } }
BRutus.db.cores = { Main = { members = { [theirs("Cherry Arrow")] = { role = "rdps" } }, signups = { [theirs("Cherry Arrow")] = {} },
                             points = { standings = { [theirs("Cherry Arrow")] = { current = 3, earned = 3, spent = 0 } } } } }
BRutus.DataCollector = nil
dofile(ADDON .. "/Modules/DataCollector.lua")
BRutus.DataCollector:Initialize()
local db = BRutus.db
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
BRutus.DataCollector:Initialize()
check(db.trials[mine("Cherry Arrow")].resolvedDate == 90 and before ~= nil, "forever: running it again changes nothing")
BRutus.db.officerNotes = { [theirs("Bad Data")] = { notes = "junk", tags = 3 }, [mine("Bad Data")] = { notes = { 5, { author = "A", timestamp = 1 } } } }
BRutus.db.raidTracker.attendance = { [""] = { [theirs("Bad Data")] = { raids = "x" }, [mine("Bad Data")] = { raids = 1 } } }
BRutus.db.trials = { [theirs("Bad Data")] = { startDate = 5, notes = { 7 } }, [mine("Bad Data")] = { startDate = 5 } }
BRutus.db.raiders = { [theirs("Bad Data")] = { updatedAt = 1 } }
BRutus.db.points = { config = { startingPoints = "lots" }, standings = { [theirs("Bad Data")] = { current = 1 }, [mine("Bad Data")] = { current = 2 } } }
check(db.storedKeysLocalized == MY, "forever: the migration marks the database as done")
BRutus.db.storedKeysLocalized = nil
check(pcall(BRutus.LocalizeStoredMemberTables, BRutus), "forever: stored junk does not break the migration")
check(#BRutus.db.officerNotes[mine("Bad Data")].notes == 1, "forever: and the notes that are notes survive it")
check(BRutus.db.raidTracker.attendance[""][mine("Bad Data")] and BRutus.db.raidTracker.attendance[""][theirs("Bad Data")] == nil,
  "forever: attendance with a junk raid count still moves")
check(BRutus.db.trials[mine("Bad Data")] and BRutus.db.raiders[mine("Bad Data")] and BRutus.db.points.standings[mine("Bad Data")].current == 3,
  "forever: a malformed trial note leaves the trial and every later table moved")
BRutus.db.raiders = { [theirs("Later On")] = {} }
BRutus:LocalizeStoredMemberTables()
check(BRutus.db.raiders[theirs("Later On")], "forever: once done, it is not redone on every login")
local registered = 0
CreateFrame = function() return { RegisterEvent = function() registered = registered + 1 end, SetScript = function() end } end
BRutus.LocalizeStoredMemberTables = function() error("boom") end
check(pcall(BRutus.DataCollector.Initialize, BRutus.DataCollector) and registered > 0,
  "forever: a migration that throws still lets the data collector start")

-- ── 9c. Each merge decides, whichever of the two keys comes first ───────
-- `win` is stored under one of a member's two keys and `lose` under the other, both ways round.
-- The keys go in in the same order each time, so pairs() meets them in the same order and only
-- the values swap: one of the two runs always hands the merge the loser first.
local function both(what, name, put, win, lose, ok)
  for _, flip in ipairs({ false, true }) do
    load("forever")
    local v = flip and { [mine(name)] = win(), [theirs(name)] = lose() } or { [theirs(name)] = win(), [mine(name)] = lose() }
    put(BRutus.db, theirs(name), v[theirs(name)])
    put(BRutus.db, mine(name), v[mine(name)])
    BRutus:LocalizeStoredMemberTables()
    check(ok(BRutus.db, mine(name)), what .. (flip and " (the winner under this client's key)" or " (the winner under the other's key)"))
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
BRutus.db.raidTracker.attendance = { [theirs("Flat Guy")] = { raids = 1, lastRaid = 5 } }
BRutus:LocalizeStoredMemberTables()
check(BRutus.db.raidTracker.attendance[theirs("Flat Guy")].raids == 1,
  "forever: the old flat attendance format is left for the raid tracker to spot and rebuild")
load("forever")
BRutus.db.trials = { [theirs("Ann Lee")] = { startDate = 1 }, [mine("Ann Lee")] = { startDate = 2 } }
BRutus.db.raiders = { [theirs("Ann Lee")] = { updatedAt = 1 } }
BRutus.db.cores = { Main = { members = { [theirs("Ann Lee")] = {} } } }
local realMerge = BRutus.TrialTracker.Merge
BRutus.TrialTracker.Merge = function() error("boom") end
check(pcall(BRutus.LocalizeStoredMemberTables, BRutus) and BRutus.db.raiders[mine("Ann Lee")] and BRutus.db.cores.Main.members[mine("Ann Lee")],
  "forever: one table's step failing leaves every other table moved")
check(BRutus.db.storedKeysLocalized == nil and BRutus.db.trials[theirs("Ann Lee")], "forever: and the database is not marked done")
BRutus.TrialTracker.Merge = realMerge
BRutus:LocalizeStoredMemberTables()
check(BRutus.db.trials[mine("Ann Lee")] and BRutus.db.trials[theirs("Ann Lee")] == nil and BRutus.db.storedKeysLocalized == MY,
  "forever: so the next login moves what failed, and only then marks it done")
load("forever")
BRutus.db.cores = { Main = { points = { standings = { [theirs("Ann Lee")] = { current = "x" }, [mine("Ann Lee")] = { current = 1 } } },
                             members = { [theirs("Ann Lee")] = {} }, signups = { [theirs("Ann Lee")] = {} } } }
BRutus:LocalizeStoredMemberTables()
check(BRutus.db.cores.Main.members[mine("Ann Lee")] and BRutus.db.cores.Main.signups[mine("Ann Lee")] and BRutus.db.storedKeysLocalized == nil,
  "forever: a core whose points fail still has its roster and sign-ups moved, and is retried")
load("forever")

local TT = BRutus.TrialTracker
local ta, tb = { startDate = 5, notes = { { author = "A", timestamp = 3 } } }, { startDate = 5, notes = { { author = "B", timestamp = 4 } } }
check(TT:Merge(ta, tb) == ta and #ta.notes == 2, "trials: a tie keeps the held copy and merges the notes")
check(TT:Merge({ startDate = 10 }, { startDate = 5, resolvedDate = 20 }).resolvedDate == 20, "trials: a later resolution is later activity")
check(TT:Merge({ startDate = 10 }, { startDate = 5, notes = { { timestamp = 30 } } }).startDate == 5, "trials: so is a later note")
check(TT:Merge({ startDate = 10 }, { startDate = 5 }).startDate == 10, "trials: an older copy never replaces a newer one")
check(pcall(TT.Merge, TT, { startDate = 5, notes = { 7 } }, { startDate = 5, notes = { 8, { author = "A", timestamp = 1 } } }),
  "trials: a note that is not a note breaks no merge")
check(pcall(TT.Merge, TT, { startDate = 5, notes = 3 }, { startDate = 5, notes = { { author = "A", timestamp = 1 } } })
  and pcall(TT.Merge, TT, { startDate = 5, notes = {} }, { startDate = 5, notes = "x" }), "trials: nor do notes that are not a list")

local sheet = BRutus.OfficerNotes:MergeSheet(
  { notes = { { author = "A", timestamp = 1, text = "x" }, { author = "A", timestamp = 1, text = "y" } }, tags = { t = "old" } },
  { notes = { { author = "A", timestamp = 1, text = "x" }, { author = "B", timestamp = 9 } }, tags = { t = "new" } })
check(#sheet.notes == 3 and sheet.notes[1].timestamp == 9,
  "officer notes: every held note stays, an arriving duplicate is dropped, newest first")
check(sheet.tags.t == "new", "officer notes: an arriving tag wins")
local okHeld, held = pcall(BRutus.OfficerNotes.MergeSheet, BRutus.OfficerNotes, { notes = { 5, { author = "A", timestamp = 1 } } }, { notes = { 6 } })
check(okHeld and #held.notes == 1, "officer notes: a note that is not a note, held or arriving, is dropped and breaks nothing")

-- ── 10. Anniversary: a realm is part of who somebody is ─────────────────
load("anniversary")
check(BRutus:LocalMemberKey("Bob-Spineshatter") == "Bob-Spineshatter", "anniversary: another realm's key passes through")
BRutus.OfficerNotes:HandleIncoming(ser({ target = "Bob-Spineshatter", note = { author = "A", timestamp = 1 } }))
check(BRutus.db.officerNotes["Bob-Spineshatter"], "anniversary: a note for another realm's player stays theirs")
A = GuildOS.Alliance or BRutus.Alliance
check(A.ElectBridge({ "Cid-R", "Ann-R", "Bob-R" }) == A.ElectBridge({ "Ann-R", "Bob-R", "Cid-R" }),
  "anniversary: the bridge election is as it was")
local loser, winner = "Ann-R1", "Ann-R2"
if A.Hash(loser) < A.Hash(winner) then loser, winner = winner, loser end
check(A.Hash(loser) ~= A.Hash(winner) and A.ElectBridge({ loser, winner }) == winner,
  "anniversary: the election still hashes the whole key, realm included")
BRutus.CoreManager:InitSync()
BRutus.CoreManager:Create("Main")
handlers["core.signup"]({ data = { coreName = "Main", info = {} } }, "Bob-Spineshatter")
handlers["core.signup"]({ data = { coreName = "Main", info = {} } }, "Ann")
check(BRutus.db.cores.Main.signups["Bob-Spineshatter"] and BRutus.db.cores.Main.signups["Ann-" .. MY],
  "anniversary: a sign-up is filed under the sender's own realm")
BRutus.db.trials = { ["Bob-Spineshatter"] = { startDate = 1 } }
BRutus:LocalizeStoredMemberTables()
check(BRutus.db.trials["Bob-Spineshatter"], "anniversary: the stored-table migration leaves another realm's player alone")

print(("forever-payload-keys: %d checks passed"):format(checks))
