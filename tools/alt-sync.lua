-- Alt links synced per alt (issue #424), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/CommSystem.lua, Modules/SyncService.lua, Modules/AltSync.lua,
-- Modules/AltAutoDetect.lua and Modules/BulkActions.lua, with several clients on one guild channel.
--
-- The links travelled as one table ("AL") that replaced the receiver's whole table: an officer with an
-- old or empty one wiped everybody's on every sync request, and an unlink came back with an old table.
-- Now each alt is an entry with its own revision and a tombstone on unlink, and "AL" only merges.
--
--   luajit -e 'ADDON="."' tools/alt-sync.lua
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

local GAME = "anniversary"
local ROSTER = { { "OffA", 1 }, { "OffB", 1 }, { "Mem", 5 }, { "Main", 4 }, { "AltX", 6 }, { "AltY", 6 },
                 { "AltZ", 2 }, { "Other", 5 }, { "OffC", 1 }, { "Old", 1 } }
local me = "OffA"
local now = 1791000000
local afters = {}
local registry, store, n = {}, {}, 0

local function boot(game)
  GAME = game
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
    function UnitFullName() return me, "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return false end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  function GetRealmName() return "Realm" end
  function GetServerTime() return now end
  function GetTime() return now end
  time = os.time
  strtrim = strtrim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
  C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
              NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  function UnitName() return me end
  function UnitLevel() return 70 end
  function UnitClass() return "Warrior", "WARRIOR" end
  function IsInGuild() return true end
  function InCombatLockdown() return false end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i)
    local r = ROSTER[i]
    if r then return r[1] .. "-Realm", "Rank" .. r[2], r[2], 70, "Warrior", "", "", "", true, 0, "WARRIOR" end
  end
  function GetGuildInfo()
    for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
  end
  function GuildControlGetNumRanks() return 7 end
  function GuildControlGetRankName(i) return "Rank" .. (i - 1) end
  registry, store, n = {}, {}, 0
  LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
    GetLibrary = function(_, k) return registry[k] end },
    { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
  LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
  LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, store[s] end return false end
  LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
  LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/CommSystem.lua")
  dofile(ADDON .. "/Modules/SyncService.lua")
  dofile(ADDON .. "/Modules/AltSync.lua")
  dofile(ADDON .. "/Modules/AltAutoDetect.lua")
  dofile(ADDON .. "/Modules/BulkActions.lua")
  GuildOS.CommSystem.pendingMessages = {}
end

boot("anniversary")
local CS, SS, AS, AD = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.AltSync, GuildOS.AltAutoDetect

-- ── The clients ─────────────────────────────────────────────────────────
-- Each has its own guild db, account db and SyncService dedup set; `wire` is the guild channel.
local clients, wire, online = {}, {}, {}
local function newClient(name, links)
  clients[name] = { db = { settings = { officerMaxRank = 1 }, altLinks = links or {} }, acc = {}, seen = {}, count = 0 }
  online[name] = true
end
local function use(name)
  local c = clients[name]
  me = name
  GuildOS.db, GuildOSDB = c.db, c.acc
  SS.seenIds, SS.seenCount = c.seen, c.count
  AD._resentAt = c.resentAt
end
local function save()
  local c = clients[me]
  c.count, c.resentAt = SS.seenCount, AD._resentAt
end
CS.SendMessage = function(_, msgType, data, target)
  wire[#wire + 1] = { t = msgType, data = data, from = me, target = target }
end
-- Run the timers queued so far (a backfill's later batches), as `who`.
local function runAfters(who)
  use(who)
  while #afters > 0 do
    local fn = table.remove(afters, 1)
    now = now + 2
    fn()
  end
  save()
end
-- Deliver everything on the wire to every other online client, until nothing new is sent.
local function flush()
  local guard = 0
  while #wire > 0 do
    guard = guard + 1
    check(guard < 50, "the channel settles")
    local batch = wire
    wire = {}
    for _, msg in ipairs(batch) do
      for name in pairs(clients) do
        if online[name] and name ~= msg.from then
          use(name)
          CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, "GUILD", msg.from .. "-Realm")
          save()
        end
      end
    end
  end
end
local function as(name, fn) use(name); local r = fn(); save(); return r end
local function linksOf(name) return clients[name].db.altLinks end
local function sentOf(t)
  local c = 0
  for _, m in ipairs(wire) do if m.t == t then c = c + 1 end end
  return c
end
-- An officer on a client before #424: its whole table, as it sends it on every sync request.
local function oldClientSends(from, links)
  n = n + 1
  local token = "s" .. n
  store[token] = links
  wire[#wire + 1] = { t = "AL", data = token, from = from }
end

local K = function(name) return GuildOS:GetPlayerKey(name, "Realm") end
local MAIN, X, Y, Z, OTHER = K("Main"), K("AltX"), K("AltY"), K("AltZ"), K("Other")

-- ── 0. Pure helpers ─────────────────────────────────────────────────────
check(AS.Flatten({ a = "b", b = "c" }).a == "c" and AS.Flatten({ a = "b", b = "c" }).b == "c",
  "a chain is flattened onto its last main")
local loop = AS.Flatten({ a = "b", b = "a" })
check(loop.a == nil and loop.b == "a", "a loop two edits made at once settles on its lowest key as the main")
check(AS.Wins(5, { main = "m" }, 4, { main = "n", author = "x" }) and not AS.Wins(3, { main = "m" }, 4, nil),
  "the higher revision wins")
check(not AS.Wins(4, { main = "m", author = "a" }, 4, nil), "an entry seen and dropped (a pruned tombstone) never comes back")
check(AS.Wins(1, { main = "m", author = "a" }, 1, { main = "z" }), "this client's own migration yields to an officer's at the same revision")
local e1, e2 = { main = "m1", author = "a" }, { main = "m2", author = "b" }
check(AS.Wins(1, e2, 1, e1) ~= AS.Wins(1, e1, 1, e2), "two officers' entries at one revision settle the same way everywhere")
local over = AS.OverLimit({ a = "M", b = "M", c = "M", d = "N" }, 2)
check(#over == 1 and over[1].main == "M" and #over[1].alts == 3, "altlimit: only the groups above the limit")

-- ── 1. Migration: the table from before #424 becomes entries ────────────
newClient("OffA", { [X] = MAIN })
newClient("OffB", { [X] = MAIN })
newClient("Mem", { [X] = MAIN })
for _, name in ipairs({ "OffA", "OffB", "Mem" }) do as(name, function() AS:Initialize() end) end
check(linksOf("OffA")[X] == MAIN and clients.OffA.db.altSync.links[X].legacy and clients.OffA.db.altSync.rev[X] == AS.LEGACY_REV,
  "the old table becomes entries at the lowest revision, and the view is the same")

-- ── 2. An officer with an empty table answers a sync request ────────────
newClient("OffC")                                -- a new install: nothing linked at all
as("OffC", function() AS:Initialize() end)
as("OffC", function() CS:BroadcastAltLinks(); AS:Backfill() end)
check(#wire == 0, "an officer with no links sends no table and no entries")
oldClientSends("OffC", {})                       -- the same officer on a client before #424
flush()
check(linksOf("OffA")[X] == MAIN and linksOf("Mem")[X] == MAIN and linksOf("OffB")[X] == MAIN,
  "an empty table from an officer leaves everybody's links as they were")
oldClientSends("OffC", { [Y] = MAIN })           -- an old officer's stale, partial table
flush()
check(linksOf("OffA")[X] == MAIN and linksOf("Mem")[X] == MAIN, "an old client's partial table removes nothing")
check(linksOf("Mem")[Y] == MAIN and linksOf("OffA")[Y] == MAIN, "and what it has that nobody had is merged in")
oldClientSends("OffC", { [X] = OTHER })
flush()
check(linksOf("OffA")[X] == MAIN and linksOf("Mem")[X] == MAIN, "nor does it move an alt to another main")
clients.OffC = nil
online.OffC = nil

-- ── 3. An unlink while another officer is offline does not come back ────
online.OffB = false
as("OffA", function() GuildOS:UnlinkAlt(X) end)
check(sentOf("SV") >= 1, "the unlink is published as an entry")
flush()
check(linksOf("OffA")[X] == nil and linksOf("Mem")[X] == nil, "the unlink reaches whoever is online")
check(linksOf("OffB")[X] == MAIN, "OffB, offline, still has the old link")
online.OffB = true
as("OffB", function() CS:BroadcastAltLinks(); AS:Backfill() end)   -- OffB answers a sync request
runAfters("OffB")
flush()
check(linksOf("OffA")[X] == nil and linksOf("Mem")[X] == nil, "OffB comes back with its old list: the link does not return")
as("OffA", function() AS:Backfill() end)
runAfters("OffA")
flush()
check(linksOf("OffB")[X] == nil, "and OffA's backfill takes the tombstone to OffB")
check(clients.OffB.db.altSync.links[X].removed, "kept as a tombstone, not as a missing link")
-- Old clients never hear tombstones: one that still has the link sends it, and it stays gone.
oldClientSends("Old", { [X] = MAIN })
flush()
check(linksOf("OffA")[X] == nil and linksOf("Mem")[X] == nil and linksOf("OffB")[X] == nil,
  "an old client's table naming the unlinked alt does not bring it back")

-- ── 4. Two officers link at the same moment ─────────────────────────────
as("OffA", function() GuildOS:LinkAlt(X, MAIN) end)
as("OffB", function() GuildOS:LinkAlt(Z, MAIN) end)
flush()
for _, name in ipairs({ "OffA", "OffB", "Mem" }) do
  check(linksOf(name)[X] == MAIN and linksOf(name)[Z] == MAIN, name .. ": both links stand")
end
-- And the same alt, at the same second, to two mains: one answer everywhere.
as("OffA", function() GuildOS:LinkAlt(OTHER, MAIN) end)
as("OffB", function() GuildOS:LinkAlt(OTHER, Y) end)
flush()
check(linksOf("OffA")[OTHER] ~= nil and linksOf("OffA")[OTHER] == linksOf("OffB")[OTHER]
  and linksOf("OffB")[OTHER] == linksOf("Mem")[OTHER], "one alt linked twice at once: every client agrees")
as("OffA", function() GuildOS:UnlinkAlt(OTHER) end)
flush()

-- ── 5. A member's claim survives an officer who never heard it ──────────
local MEM = K("Mem")
as("Mem", function() AD:LinkOwnAlts(MEM, { MEM, OTHER }) end)   -- Mem says Other is its alt
local claim = wire[#wire]
check(claim and claim.t == "SA" and next(clients.Mem.acc.altPending or {}) ~= nil and linksOf("Mem")[OTHER] == MEM,
  "the member's claim goes out, waits, and shows on the member's view")
wire = {}                                        -- no officer heard it
as("OffB", function() CS:BroadcastAltLinks(); AS:Backfill() end)   -- an officer's links without it
runAfters("OffB")
local fromB = wire
wire = {}
for _, msg in ipairs(fromB) do                   -- to Mem only, for now
  use("Mem")
  CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, "GUILD", msg.from .. "-Realm")
  save()
end
check(next(clients.Mem.acc.altPending) ~= nil and linksOf("Mem")[OTHER] == MEM,
  "an officer's links lacking the claim are no answer: the claim waits, still on the view")
check(sentOf("SA") == 1, "and goes to the officers again, now that one is online")
flush()
check(linksOf("OffA")[OTHER] == MEM and linksOf("OffB")[OTHER] == MEM, "the officers apply the claim")
check(next(clients.Mem.acc.altPending) == nil and linksOf("Mem")[OTHER] == MEM, "and the member's claim is done")

-- ── 6. Volume: a big guild's backfill goes in spaced batches ────────────
use("OffA")
local big = {}
for i = 1, 300 do big[GuildOS:GetPlayerKey("Alt" .. i, "Realm")] = MAIN end
for k, v in pairs(linksOf("OffA")) do big[k] = v end
AS:Commit(big)
save()
wire = {}
afters = {}
local total = 0
for _ in pairs(clients.OffA.db.altSync.links) do total = total + 1 end
check(total > 300, "a guild with hundreds of alts")
as("OffA", function() AS:Backfill() end)
check(sentOf("SV") == 1 and #afters == 1, "a backfill sends one batch now, the next one later")
as("OffA", function() AS:Backfill() end)
check(sentOf("SV") == 1, "a second backfill while one runs does not stack")
runAfters("OffA")
check(sentOf("SV") == math.ceil(total / AS.BATCH) and not AS._backfilling,
  "and the rest one batch every few seconds, every entry once")
flush()
check(linksOf("Mem")[GuildOS:GetPlayerKey("Alt250", "Realm")] == MAIN, "every batch arrives")

-- ── 7. The group to the main's rank, through the bulk queue ─────────────
-- Main is rank 4; AltX and AltY rank 6, AltZ rank 2 (above the main). OffA is rank 1.
use("OffA")
GuildOS.Compat.CanGuildPromote = function() return true end
GuildOS.Compat.CanGuildDemote = function() return true end
GuildOS.Compat.MyGuildRankIndex = function() return 1 end
GuildOS.GuildManager = { GetRanks = function() local r = {} for i = 1, 7 do r[i] = { index = i - 1, name = "Rank" .. (i - 1) } end return r end,
                         GetRankName = function(_, i) return "Rank" .. i end, GetDaysOffline = function() return 0 end }
AS:Commit({ [X] = MAIN, [Y] = MAIN, [Z] = MAIN })
local ok = GuildOS.BulkActions:StartGroup(MAIN, "promote")
local q = GuildOS.BulkActions:Queue()
check(ok and q and #q.items == 2 and q.target == 4, "promote the group: the two alts below the main's rank, to it")
for _, it in ipairs(q.items) do check(it.key ~= MAIN and it.key ~= Z, "never the main, never an alt already at or above") end
ok = GuildOS.BulkActions:StartGroup(MAIN, "demote")
q = GuildOS.BulkActions:Queue()
check(ok and #q.items == 1 and q.items[1].key == Z, "demote the group: only the alt above the main's rank")
-- Eligible holds: an alt at the officer's own rank + 1 is never promoted into it.
ROSTER[4][2] = 0                                 -- the main is the guild master now
ok = GuildOS.BulkActions:StartGroup(MAIN, "promote")
q = GuildOS.BulkActions:Queue()
check(ok and #q.items == 2, "toward a rank above the officer's own, the alts still queue")
local item = GuildOS.BulkActions:Current()
check(item ~= nil, "and the first is next")
ROSTER[5][2], ROSTER[6][2] = 2, 2                 -- both one step below the officer
GuildOS.BulkActions:StartGroup(MAIN, "promote")
check(select(2, GuildOS.BulkActions:StartGroup(MAIN, "promote")) == "empty",
  "an alt whose promotion would reach the officer's rank is never queued (Eligible)")
ROSTER[4][2], ROSTER[5][2], ROSTER[6][2] = 4, 6, 6
-- One step per click, queued again until the target.
ok = GuildOS.BulkActions:StartGroup(MAIN, "promote")
q = GuildOS.BulkActions:Queue()
local first = q.items[1]
first.status, first.sentAt, first.sentClock = "sent", now, now
for _, r in ipairs(ROSTER) do if r[1] .. "-Realm" == first.fullName then r[2] = 5 end end
GuildOS.BulkActions:Confirm()
check(first.status == "done" and #q.items == 3 and q.items[3].key == first.key and q.items[3].rankIndex == 5,
  "an alt one step on and still short of the main's rank is queued again")
ROSTER[5][2], ROSTER[6][2] = 6, 6
GuildOS.BulkActions:Stop()
check(select(2, GuildOS.BulkActions:StartGroup(OTHER, "promote")) == "group", "a character with no alts: nothing to queue")
GuildOS.BulkActions:CommandGroup("promote Main")
q = GuildOS.BulkActions:Queue()
check(q and q.target == 4 and #q.items == 2, "/gos altgroup promote Main: to the main's rank")
GuildOS.BulkActions:CommandGroup("promote Main 6")          -- the game's 6th rank is index 5
q = GuildOS.BulkActions:Queue()
check(q and q.target == 5 and #q.items == 2, "/gos altgroup promote Main 6: to the rank given by its number")
GuildOS.BulkActions:Stop()
GuildOS.BulkActions:CommandGroup("promote Main Nope")
check(GuildOS.BulkActions:Queue() == nil, "an unknown rank starts nothing")
save()

-- ── 8. WoW: Forever keys with and without the realm are one member ──────
boot("forever")
CS, SS, AS, AD = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.AltSync, GuildOS.AltAutoDetect
CS.SendMessage = function() end
me = "OffA"
GuildOS.db = { settings = { officerMaxRank = 1 }, altLinks = { ["Bob-Old Realm"] = "Boss", ["Bob Two"] = "Boss-Old Realm" } }
GuildOSDB = {}
local function F(name) return GuildOS:LocalMemberKey(name) end
check(F("Bob") == F("Bob-Old Realm") and F("Bob") == F("Bob-Costa"), "forever: a key with and without a realm is one member")
AS:Initialize()
check(GuildOS.db.altLinks[F("Bob")] == F("Boss") and GuildOS.db.altLinks[F("Bob Two")] == F("Boss"),
  "forever: the old table's keys, with and without the realm, are migrated onto this client's keys")
AS:Apply({ { k = "Bob-Their Realm", x = true, a = "OffB", t = now + 10, r = now + 10 } }, "OffB")
AS:Rebuild()
check(GuildOS.db.altLinks[F("Bob")] == nil, "forever: an officer's unlink keyed with another realm lands on the same member")
AS:OnLegacyList({ ["Bob"] = "Boss" }, "Old")
AS:Rebuild()
check(GuildOS.db.altLinks[F("Bob")] == nil, "forever: an old table without the realm does not bring it back")
AS:Apply({ { k = "Cid", m = "Boss-Their Realm", a = "OffB", t = now + 11, r = now + 11 } }, "OffB")
AS:Rebuild()
check(GuildOS.db.altLinks[F("Cid")] == F("Boss"), "forever: a link with the realm on one side only is one link")
-- A store saved under another realm (the client's realm changed, #394) is rekeyed at start-up.
GuildOS.db.altSync.links["Dan-Old Realm"] = { main = "Boss-Old Realm", author = "OffB", ts = 1 }
GuildOS.db.altSync.rev["Dan-Old Realm"] = 7
AS:Normalize()
AS:Rebuild()
check(GuildOS.db.altSync.links[F("Dan")] and GuildOS.db.altSync.rev[F("Dan")] == 7 and GuildOS.db.altLinks[F("Dan")] == F("Boss"),
  "forever: entries and revisions stored under another realm move to this client's keys")

print(("alt-sync: %d checks passed"):format(checks))
