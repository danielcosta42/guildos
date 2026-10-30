-- The journal (issue #205), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/SyncService.lua, Modules/DataCollector.lua and Modules/Journal.lua.
--
-- Each client writes down what happened to its own character and the guild keeps it. What this
-- holds: an entry is only ever taken from its subject, over the guild channel; out-of-range
-- entries never land; each one is kept once; thirty days and a thousand entries are the limit;
-- the level milestones are the ones guildos.me reads; and the opt-out travels with the broadcast.
--
--   luajit -e 'ADDON="."' tools/journal.lua
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

local NOW = 1794139200
local REALM = "Normal"
local sent, store = {}, {}

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  elseif game == "retail" then
    function GetBuildInfo() return "12.1.5", "70575", "", 120105 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 1
    WOW_PROJECT_MAINLINE = 1
    function UnitName() return "Chehul" end
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Chehul" end
  end
  function UnitClass() return "Shaman", "SHAMAN" end
  function GetRealmName() return REALM end
  function GetNormalizedRealmName() return REALM end
  function GetServerTime() return NOW end
  function GetTime() return 1 end
  time = os.time
  function IsInGuild() return true end
  C_Timer = { After = function() end, NewTicker = function() end }
  Enum = { SendAddonMessageResult = {} }
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  LibStub("GuildOS-LibSerialize").Serialize = function(_, t) store[#store + 1] = t; return tostring(#store) end
  LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) return store[tonumber(s)] ~= nil, store[tonumber(s)] end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/SyncService.lua")
  dofile(ADDON .. "/Modules/DataCollector.lua")
  dofile(ADDON .. "/Modules/Journal.lua")
  GuildOS.CommSystem = { SendMessage = function(_, _, payload) sent[#sent + 1] = store[tonumber(payload)] end,
    BroadcastMyData = function() end }
  GuildOS.db = { members = {}, settings = {}, profile = {}, myData = { name = "Chehul Costa", level = 40 } }
  GuildOS.SyncService:Initialize()
  if GuildOS.Journal then GuildOS.Journal:Initialize() end
  return GuildOS
end

-- ── Only WoW: Forever has a journal ─────────────────────────────────────
check(load("anniversary").Journal == nil, "no journal on TBC Anniversary")
check(load("retail").Journal == nil, "no journal on retail")

local G = load("forever")
local J = G.Journal
check(J ~= nil, "the journal is on WoW: Forever")
local me = G:GetPlayerKey(G.Compat.PlayerName())
check(me == "Chehul Costa-" .. REALM, "my key has my surname: " .. tostring(me))

-- ── My own milestones ───────────────────────────────────────────────────
sent = {}
J:OnLevelUp(39)
check(#G.db.journal.entries == 0, "39 is no milestone")
J:OnLevelUp(40)
local e = G.db.journal.entries[1]
check(e and e.type == "member.level" and e.data.level == 40, "40 is written down")
check(e.subjectKey == me and e.at == NOW and e.id == me .. ":1", "about me, now, with my id")
check(e.data.name == nil and e.data.class == nil, "with no name in it: the roster names people")
check(#sent == 1 and sent[1].dom == "journal" and sent[1].act == "add", "and the guild is told")
J:OnLevelUp(60)
check(G.db.journal.entries[2].type == "member.level60", "the cap is its own entry")
check(G.db.journal.entries[2].data.level == nil, "with no level in it")

-- ── Entries from the guild ──────────────────────────────────────────────
local seq = 0
local function receive(sender, act, data, channel)
  seq = seq + 1
  local raw = LibStub("GuildOS-LibSerialize"):Serialize({ v = 2, id = "ID" .. seq, dom = "journal", act = act, data = data })
  G.SyncService:OnEnvelope(sender, raw, channel or "GUILD")
end
local function entry(subject, id, over)
  local x = { id = id, subjectKey = subject, at = NOW - 60, type = "member.level", data = { name = "Mira", level = 20 } }
  for k, v in pairs(over or {}) do x[k] = v end
  return x
end
local MIRA = "Mira Thornwood-" .. REALM
local count = function() return #G.db.journal.entries end
local base = count()

receive("Mira Thornwood", "add", { entry = entry(MIRA, MIRA .. ":1") })
check(count() == base + 1, "a member's own entry is kept")
receive("Mira Thornwood", "add", { entry = entry(MIRA, MIRA .. ":1") })
check(count() == base + 1, "the same entry again is not kept twice")
receive("Mira Thornwood", "add", { entry = entry(me, me .. ":99") })
check(count() == base + 1, "an entry about somebody else is dropped")
receive("Mira Thornwood", "add", { entry = entry(MIRA, MIRA .. ":2") }, "WHISPER")
check(count() == base + 1, "a whispered entry is dropped: the journal is the guild's")
receive("Mira Thornwood", "add", { entry = entry(MIRA, MIRA .. ":3", { data = { level = 61 } }) })
receive("Mira Thornwood", "add", { entry = entry(MIRA, MIRA .. ":4", { at = NOW + 86400 }) })
receive("Mira Thornwood", "add", { entry = entry(MIRA, MIRA .. ":5", { type = "member.died" }) })
receive("Mira Thornwood", "add", { entry = entry(MIRA, MIRA .. ":6",
  { type = "dungeon.clear", data = { dungeonId = "ruins", runId = "r1", bosses = 21, fullClear = true } }) })
check(count() == base + 1, "a level past the cap, a date ahead, an unknown type and 21 bosses never land")
receive("Mira Thornwood", "snap", { entries = { entry(MIRA, MIRA .. ":7"), entry(MIRA, MIRA .. ":8",
  { type = "dungeon.clear", data = { dungeonId = "ruins", runId = "r1", bosses = 7, fullClear = true } }) } })
check(count() == base + 3, "a snapshot brings what was missed")

-- On WoW: Forever each client answers its own realm name (#95): Mira's says another one.
local THEIRS = "Mira Thornwood-Classic Beta PvE"
receive("Mira Thornwood-Classic Beta PvE", "add", { entry = entry(THEIRS, THEIRS .. ":9",
  { data = { level = 30, name = "Chehul Costa", extra = string.rep("x", 5000) } }) })
check(count() == base + 4, "an entry whose key carries the sender's own realm answer is still the sender's")
local got
for _, x in ipairs(G.db.journal.entries) do if x.id == THEIRS .. ":9" then got = x end end
check(got.subjectKey == MIRA, "kept in this client's shape of the key: " .. tostring(got.subjectKey))
check(got.data.level == 30 and got.data.name == nil and got.data.extra == nil, "and only with the fields its type has")
check(got.id == THEIRS .. ":9", "the id stays as its author minted it")

-- ── Limits ──────────────────────────────────────────────────────────────
G.db.journal.entries[#G.db.journal.entries + 1] = entry(MIRA, "old", { at = NOW - 31 * 86400 })
J:Prune(NOW)
for _, x in ipairs(G.db.journal.entries) do check(x.id ~= "old", "thirty days and out") end
G.db.journal.entries = {}
for i = 1, 1005 do G.db.journal.entries[#G.db.journal.entries + 1] = entry(MIRA, "bulk" .. i, { at = NOW - 3600 + i }) end
J:Prune(NOW)
check(count() == 1000, "a thousand entries at most")
check(G.db.journal.entries[1000].id == "bulk1005", "the newest stay")

-- ── What goes out ───────────────────────────────────────────────────────
G.db.journal.entries = {}
J:OnLevelUp(50)
G.db.journal.entries[#G.db.journal.entries + 1] = entry(MIRA, MIRA .. ":20")
sent = {}
J:Snap()
check(#sent == 1 and sent[1].act == "snap" and #sent[1].data.entries == 1, "a snapshot carries only my own")
local out = J:ForExport()
check(#out == 2 and out[1].type and out[1].subjectKey and out[1].id and out[1].at and out[1].data, "the export carries the whole journal")

-- ── Not named on Discord ────────────────────────────────────────────────
check(G.DataCollector:GetBroadcastData().feedOptOut == false, "the broadcast always says, so turning it off clears it")
J:SetOptedOut(true)
check(J:IsOptedOut() and G.db.members[me].feedOptOut == true, "opting out marks my own row")
check(G.DataCollector:GetBroadcastData().feedOptOut == true, "and the broadcast says so")
J:SetOptedOut(false)
check(not J:IsOptedOut() and G.db.members[me].feedOptOut == false, "and back")

print(("journal: %d checks passed"):format(checks))
