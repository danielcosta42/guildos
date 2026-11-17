-- "merged 1 duplicate raid session(s)" every five minutes, on every officer (issue #197), run against
-- the real Core, Compat, Utils, CoreManager and RaidTracker under a stubbed client.
--
-- A merge deleted the folded half and kept no trace of it. A peer whose copy of the kept session is
-- older does not fold the same pair, and its broadcast carries the other half every five minutes:
-- taken back, merged again, announced again.
--
--   luajit -e 'ADDON="."' tools/raid-merge-loop.lua
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

local printed, store, sent = {}, {}, nil
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function UnitName() return "Leader" end
function GetRealmName() return "Realm" end
function GetServerTime() return 1791000000 end
function GetTime() return 1 end
time = os.time
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
-- The debounced merge after a broadcast runs at once.
C_Timer = { After = function(_, f) f() end, NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function(_, f) f(); return { Cancel = function() end } end }
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
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CoreManager.lua")
dofile(ADDON .. "/Modules/RaidTracker.lua")
GuildOS.IsOfficer = function() return true end
GuildOS.CommSystem = { MSG_TYPES = { RAID_DATA = "RD" }, SendMessage = function(_, _, data) sent = data end }
-- A SavedVariables from before the fix: no mergedSessions.
GuildOS.db = { settings = {}, members = {}, altLinks = {}, cores = {},
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local RT, raidDB = GuildOS.RaidTracker, GuildOS.db.raidTracker

local T = 1791000000
local function session(start, stop, who)
  return { instanceID = 544, name = "Magtheridon's Lair", groupTag = "", startTime = start, endTime = stop,
           isGuildRaid = true, players = { [who] = true }, encounters = {}, snapshots = {} }
end
local function merges()
  local n = 0
  for _, m in ipairs(printed) do if m:find("merged", 1, true) then n = n + 1 end end
  printed = {}
  return n
end

-- Here: 20:00–21:40 (already the fold of a 20:50 session this peer never saw) and 22:00–22:30.
raidDB.sessions[T] = session(T, T + 6000, "Aaa-Realm")
raidDB.sessions[T + 7200] = session(T + 7200, T + 9000, "Bbb-Realm")
check(RT:MergeDuplicateSessions() == 1 and merges() == 1, "the pair 20 minutes apart is folded, and said once")
check(raidDB.sessions[T + 7200] == nil and raidDB.sessions[T].players["Bbb-Realm"],
  "the 22:00 half is gone, its player kept in 20:00")
check(raidDB.mergedSessions and raidDB.mergedSessions[T + 7200] == T, "the folded id is remembered, with where it went")

-- The peer's 20:00 stopped at 20:40, so 22:00 is 80 minutes after it there and stays apart.
local peer = { attendance = {}, deletedSessions = {}, sessions = {
  [T] = session(T, T + 2400, "Aaa-Realm"), [T + 7200] = session(T + 7200, T + 9000, "Bbb-Realm") } }
for i = 1, 3 do
  RT:HandleIncoming(LibStub("GuildOS-LibSerialize"):Serialize(peer))
  check(merges() == 0, "the peer's five-minute broadcast " .. i .. " announces no merge")
  check(raidDB.sessions[T + 7200] == nil, "the folded half is not taken back from broadcast " .. i)
end

-- A session this client never folded still comes in.
peer.sessions[T + 86400] = session(T + 86400, T + 90000, "Ccc-Realm")
RT:HandleIncoming(LibStub("GuildOS-LibSerialize"):Serialize(peer))
check(raidDB.sessions[T + 86400] ~= nil, "a new night from the peer is still taken")

-- What was folded here stays here: a tombstone would make the peer drop a half its copy cannot replace.
RT:BroadcastRaidData()
local out = store[tonumber(sent:match("^#(%d+)$"))]
check(out.mergedSessions == nil and not (out.deletedSessions or {})[T + 7200],
  "the broadcast carries no record of the fold")

-- A peer deletes the night the half went into: the half comes back, or the night is gone here.
peer.deletedSessions[T] = true
peer.sessions[T] = nil
RT:HandleIncoming(LibStub("GuildOS-LibSerialize"):Serialize(peer))
check(raidDB.sessions[T] == nil and raidDB.sessions[T + 7200] ~= nil,
  "with 20:00 deleted by a peer, its 22:00 half is taken back")

print(("raid-merge-loop: %d checks passed"):format(checks))
