-- The groups being formed (issue #341), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Data/GroupActivities.lua, Modules/LFGBoard.lua and Modules/Groups.lua.
--
-- A leader's listing is theirs alone and is sanitised on the way in; a request for a spot reaches
-- the leader alone, and only from a guildmate; the spot closes when the player joins, and with none
-- left the listing comes down; and each client's catalogue has ids that cross the wire.
--
--   luajit -e 'ADDON="."' tools/groups.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent = {}
RAID_CLASS_COLORS = {}

local function widget()
  local w = { scripts = {} }
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    return function() end
  end })
end
function CreateFrame() return widget() end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName(unit)
  if unit == "player" then return "Ana" end
  local i = tonumber(unit:match("^party(%d+)$"))
  return i and PARTY[i] or nil
end
function UnitClass() return "Warrior", "WARRIOR" end
local NOW, CLOCK = 1790000000, 1000
function GetServerTime() return NOW end
function GetTime() return CLOCK end
time = function() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
C_Timer = { After = function() end, NewTicker = function() end }
function GetNumGuildMembers() return 0 end
function IsInGuild() return true end
function IsInRaid() return false end
PARTY = {}
function GetNumGroupMembers() return #PARTY > 0 and #PARTY + 1 or 0 end
local said, invited = {}, {}
function SendChatMessage(msg, chan) said[#said + 1] = { msg = msg, chan = chan } end
function InviteUnit(name) invited[#invited + 1] = name end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Data/GroupActivities.lua")

local passThrough = { Serialize = function(_, t) return t end, Deserialize = function(_, d) return true, d end }
LibStub = function() return passThrough end
dofile(ADDON .. "/Modules/LFGBoard.lua")
dofile(ADDON .. "/Modules/Groups.lua")

local TYPES = { LFG = "LG", LFG_GROUP = "GF", LFG_JOIN = "GJ" }
local wire = {}
GuildOS.CommSystem = {
  MSG_TYPES = TYPES,
  SendMessage = function(_, kind, payload, target, priority)
    wire[#wire + 1] = { kind = kind, p = payload, to = target, priority = priority }
  end,
}
local printed = {}
GuildOS.Print = function(_, msg) printed[#printed + 1] = msg end
GuildOS.UI = { OpenWindow = function() return true end }

-- Timers are held and run by hand, so a cooldown ends when the test says so.
local timers = {}
GuildOS.Compat.After = function(_, fn) timers[#timers + 1] = fn end
local function runTimers()
  local due = timers
  timers = {}
  for _, fn in ipairs(due) do fn() end
end

-- The guild: who a whispered request may come from.
local guild = { Bea = true, Cid = true, Dan = true, Eva = true }
GuildOS.RosterKey = function(_, name)
  local short, realm = name:match("^([^-]+)"), name:match("-(.+)$")
  if guild[short] and (realm == nil or realm == "Realm") then return GuildOS:GetPlayerKey(short, "Realm") end
end
local leader = true
function UnitIsGroupLeader() return leader end
function UnitIsGroupAssistant() return false end

local Board, Groups = GuildOS.LFGBoard, GuildOS.Groups
local function key(name) return GuildOS:GetPlayerKey(name, "Realm") end
local function fresh()
  GuildOS.db = {}
  GuildOS.State.groups = nil
  Board._cd = nil
  Board:Initialize()
  Groups:Initialize()
  -- The tests of #341 answer each request by hand; #378's turn this back on where they test it.
  GuildOS.db.lfgPrefs.autoInvite = false
  said, wire, printed, invited, timers = {}, {}, {}, {}, {}
  PARTY = {}
  CLOCK = CLOCK + 1000   -- past every publish window
end
local function last(kind)
  for i = #wire, 1, -1 do
    if wire[i].kind == kind then return wire[i] end
  end
end
local function count(kind)
  local n = 0
  for _, m in ipairs(wire) do if m.kind == kind then n = n + 1 end end
  return n
end

-- ── Listing my group ────────────────────────────────────────────────────
fresh()
local g, why = Groups:Create("|cffEVIL", { T = 1 }, "", 3600, false)
check(g == nil and why ~= nil and why ~= "", "a group for nothing is refused, with a reason")
g, why = Groups:Create("karazhan", { T = 0, H = 0, D = 0 }, "", 3600, false)
check(g == nil and why ~= nil and why ~= "", "a group with no open spot is refused, with a reason")
check(#wire == 0 and Groups:Mine() == nil, "and nothing went out")

fresh()
Board:SetAvailable(nil, "x", 3600, false, "T", { "karazhan" })
g = Groups:Create("steamvault", { T = 1, H = 1, D = 9 }, "a|b", 1e12, true)
check(g ~= nil and Groups:Mine() == g, "a group is listed")
check(g.max == 5 and g.n == 1, "a dungeon is five, and I am one of them")
check(g.need.T == 1 and g.need.H == 1 and g.need.D == 2, "the spots never pass the room besides the leader")
check(g.ttl == 7200, "the duration is clamped to what the board offers")
check(not g.note:find("|", 1, true), "the note is sanitised")
check(not Board:AmAvailable(), "whoever forms a group is no longer listed as looking")
local out = last(TYPES.LFG_GROUP)
check(out and out.to == nil and out.p.act == "steamvault" and out.p.age == 0 and out.p.max == 5,
  "it goes to the guild, with its age and never a timestamp")
check(out.priority == "NORMAL", "ahead of the bulk sync, so two listings never leave back to back")
check(#said == 1 and said[1].chan == "GUILD"
  and said[1].msg == "[Guild OS] Group for The Steamvault (1/5), looking for 1 Tank, 1 Healer, 2 DPS: ab",
  "and one line in guild chat: " .. tostring(said[1] and said[1].msg))

fresh()
Groups:Create("steamvault", { D = 1 }, "", 3600, false)
check(#said == 0, "the box off says nothing in chat")

fresh()
Board:SetAvailable(nil, "x", 3600, true, "T", {})
Groups:Create("steamvault", { D = 1 }, "", 3600, true)
check(#said == 1, "a leader's line and their own listing share the five minutes")

fresh()
Groups:Create("karazhan", { T = 2, H = 3, D = 30 }, "", 3600, false)
check(Groups:Mine().max == 10 and Groups:OpenSpots(Groups:Mine().need) == 9, "a raid is as large as its catalogue entry")

-- A change inside the window waits, and goes out once with what is true by then
fresh()
Groups:Create("steamvault", { T = 1, D = 1 }, "", 3600, false)
check(count(TYPES.LFG_GROUP) == 1, "the listing goes out")
Groups:Create("steamvault", { T = 1, D = 2 }, "", 3600, false)
Groups:Create("steamvault", { T = 1, D = 3 }, "", 3600, false)
check(count(TYPES.LFG_GROUP) == 1, "two changes a moment later send nothing yet")
CLOCK = CLOCK + 10
runTimers()
check(count(TYPES.LFG_GROUP) == 2 and last(TYPES.LFG_GROUP).p.need.D == 3, "and then one message, with the last word")

fresh()
Groups:Create("steamvault", { T = 1 }, "", 3600, false)
NOW = NOW + 600
CLOCK = CLOCK + 600
check(Groups:Rebroadcast() and last(TYPES.LFG_GROUP).p.age == 600, "answering a login carries the listing's real age")
check(Groups:Disband() and Groups:Mine() == nil, "taking it down removes it")
CLOCK = CLOCK + 10
runTimers()
check(last(TYPES.LFG_GROUP).p.clear == true, "and says so")
check(not Groups:Rebroadcast(), "with no group there is nothing to answer a login with")

-- ── Somebody else's listing ─────────────────────────────────────────────
fresh()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 3600 }, "WHISPER")
check(next(GuildOS.db.lfgGroups) == nil, "a listing is only ever heard on the guild channel")
Groups:HandleGroup("Bea-Realm", { act = "karazhan", note = "|TInterface\\Icons\\X:64|t hi", ttl = 1e12,
  need = { T = "2", H = -4, D = 0 / 0, X = 9 }, n = 99, max = 4000, age = -50 }, "GUILD")
local bea = GuildOS.db.lfgGroups[key("Bea")]
check(bea ~= nil and bea.from == "Bea-Realm", "the key is the sender, and the whisper goes back to them")
check(bea.ts == NOW and bea.ttl == 7200, "a negative age cannot post date it, and a forged ttl still expires")
check(bea.max == 40 and bea.n == 40, "size and count are clamped")
check(bea.need.T == 2 and bea.need.H == 0 and bea.need.D == 0 and bea.need.X == nil, "the spots are whole numbers by role")
check(not bea.note:find("|", 1, true), "no escape reaches a row")
check(#printed == 1 and printed[1]:find("Bea", 1, true) and printed[1]:find("Karazhan", 1, true), "a new group is told")
Groups:HandleGroup("Bea-Realm", { act = "steamvault", need = { T = 1 }, ttl = 3600 }, "GUILD")
check(GuildOS.db.lfgGroups[key("Bea")].act == "karazhan", "a second listing inside five seconds is dropped")
Groups:HandleGroup("Bea-Realm", { clear = true }, "GUILD")
check(GuildOS.db.lfgGroups[key("Bea")] == nil, "but taking it down is heard whatever the cooldown says")
Groups:HandleGroup("Bea-Realm", { clear = true }, "GUILD")
runTimers()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 2 }, ttl = 3600, age = 1 }, "GUILD")
runTimers()
Groups:HandleGroup("Cid-Realm", { clear = true }, "GUILD")
check(GuildOS.db.lfgGroups[key("Bea")] ~= nil, "nobody takes down somebody else's group")
Groups:HandleGroup("Bea-Realm", { note = "no activity" }, "GUILD")
check(GuildOS.db.lfgGroups[key("Bea")].act == "karazhan", "a listing with no activity changes nothing")
runTimers()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 3600, age = 60 }, "GUILD")
check(#printed == 1, "a rebroadcast is not news")
runTimers()
Groups:HandleGroup("Bea-Realm", { clear = true }, "GUILD")
check(GuildOS.db.lfgGroups[key("Bea")] == nil, "the leader takes their own down")
runTimers()
GuildOS.db.lfgPrefs.notify = false
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 3600 }, "GUILD")
check(#printed == 1, "somebody who turned the notice off is not told")

-- The list and the tiles' counts
fresh()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 3600 }, "GUILD")
Groups:HandleGroup("Cid-Realm", { act = "karazhan", need = { H = 1 }, ttl = 3600, age = 100 }, "GUILD")
Groups:HandleGroup("Dan-Realm", { act = "steamvault", need = { D = 1 }, ttl = 1800, age = 1800 }, "GUILD")
Board:HandleEntry("Eva-Realm", { roles = "H", acts = { "karazhan", "steamvault" }, ttl = 3600 })
local list = Groups:ActiveList(GuildOS.db.lfgGroups, NOW)
check(#list == 2 and list[1].key == key("Bea") and list[2].key == key("Cid"), "newest first, and the expired one is gone")
check(#Groups:ActiveList(GuildOS.db.lfgGroups, NOW, { [key("Cid")] = true }) == 1, "a leader who logged off is not listed")
local counts = Groups:Counts(NOW)
check(counts.karazhan.groups == 2 and counts.karazhan.seekers == 1, "a tile counts its groups and who is looking for it")
check(counts.steamvault.groups == 0 and counts.steamvault.seekers == 1, "and an activity with only players looking")
check(Groups:Prune(NOW) == 1 and GuildOS.db.lfgGroups[key("Dan")] == nil, "an expired listing is pruned")

-- ── Asking for a spot ───────────────────────────────────────────────────
fresh()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1, H = 0 }, ttl = 3600 }, "GUILD")
check(not Groups:RequestSpot(key("Bea"), "H"), "no asking for a spot that is not open")
check(not Groups:RequestSpot(key("Bea"), "X") and not Groups:RequestSpot(key("Zed"), "T"), "nor in no role, nor of nobody")
check(#wire == 0, "and nothing was sent")
check(Groups:RequestSpot(key("Bea"), "T"), "asking for an open spot")
local ask = last(TYPES.LFG_JOIN)
check(ask and ask.to == "Bea-Realm" and ask.p.role == "T", "goes to the leader alone, with the role")
check(Groups:Asked(key("Bea")).state == "pending", "and is remembered as waiting")
Groups:HandleJoin("Cid-Realm", { decline = true }, "WHISPER")
check(Groups:Asked(key("Bea")).state == "pending", "somebody else's refusal is not the leader's")
Groups:HandleJoin("Bea-Realm", { decline = true }, "GUILD")
check(Groups:Asked(key("Bea")).state == "pending", "nor is one that did not come by whisper")
Groups:HandleJoin("Bea-Realm", { decline = true }, "WHISPER")
check(Groups:Asked(key("Bea")).state == "declined" and #printed == 2, "the leader's refusal is shown and told")

fresh()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 3600 }, "GUILD")
Groups:RequestSpot(key("Bea"), "T")
check(Groups:CancelRequest(key("Bea")) and last(TYPES.LFG_JOIN).p.cancel == true and Groups:Asked(key("Bea")) == nil,
  "taking a request back tells the leader")
Groups:RequestSpot(key("Bea"), "T")
Groups:HandleJoin("Bea-Realm", { decline = true, closed = true }, "WHISPER")
check(Groups:Asked(key("Bea")) == nil, "a group that closed is not a refusal")
Groups:RequestSpot(key("Bea"), "T")
runTimers()
Groups:HandleGroup("Bea-Realm", { clear = true }, "GUILD")
check(Groups:Asked(key("Bea")) == nil, "and a listing that came down takes the request with it")

-- What I asked, I asked of the group that was listed
fresh()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 1800 }, "GUILD")
Groups:RequestSpot(key("Bea"), "T")
Groups:HandleJoin("Bea-Realm", { decline = true }, "WHISPER")
runTimers()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 1800, age = 30 }, "GUILD")
check(Groups:Asked(key("Bea")).state == "declined", "the same group said again keeps its answer")
runTimers()
Groups:HandleGroup("Bea-Realm", { act = "steamvault", need = { T = 1 }, ttl = 1800 }, "GUILD")
check(Groups:Asked(key("Bea")) == nil, "another activity is another group: its roles are offered again")
Groups:RequestSpot(key("Bea"), "T")
NOW = NOW + 1801
Groups:Prune()
check(Groups:Asked(key("Bea")) == nil, "and a request does not outlive a listing that expired")

-- An asker never sends two requests inside the leader's cooldown
fresh()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1, H = 1 }, ttl = 3600 }, "GUILD")
Groups:RequestSpot(key("Bea"), "T")
Groups:CancelRequest(key("Bea"))
Groups:RequestSpot(key("Bea"), "H")
check(count(TYPES.LFG_JOIN) == 2 and wire[2].p.cancel == true, "asking again a moment later waits")
check(Groups:Asked(key("Bea")).role == "H", "while the card already says what I ask")
CLOCK = CLOCK + 5
runTimers()
check(count(TYPES.LFG_JOIN) == 3 and last(TYPES.LFG_JOIN).p.role == "H", "and goes out once the leader would hear it")
Groups:RequestSpot(key("Bea"), "T")
Groups:CancelRequest(key("Bea"))
CLOCK = CLOCK + 5
runTimers()
check(last(TYPES.LFG_JOIN).p.cancel == true, "a request taken back while it waited is never sent")

-- ── The leader's queue ──────────────────────────────────────────────────
fresh()
Groups:HandleJoin("Bea-Realm", { role = "T" }, "WHISPER")
check(#Groups:Requests() == 0 and #wire == 0, "with no group of mine a request is nothing")
Groups:Create("steamvault", { T = 1, H = 1, D = 0 }, "", 3600, false)
wire, printed = {}, {}
runTimers()
Groups:HandleJoin("Bea-Realm", { role = "T" }, "GUILD")
check(#Groups:Requests() == 0, "a request is only ever heard by whisper")
Groups:HandleJoin("Zed-Realm", { role = "T" }, "WHISPER")
check(#Groups:Requests() == 0 and #wire == 0, "and only from somebody on the guild roster")
Groups:HandleJoin("Bea-Otherrealm", { role = "T" }, "WHISPER")
check(#Groups:Requests() == 0 and #wire == 0, "a namesake on another realm is not the guildmate")
Groups:HandleJoin("Bea-Realm", { role = "T" }, "WHISPER")
local queue = Groups:Requests()
check(#queue == 1 and queue[1].key == key("Bea") and queue[1].role == "T" and queue[1].state == "pending", "a guildmate's request is queued")
check(#printed == 1 and printed[1]:find("Bea", 1, true), "and told")
runTimers()
Groups:HandleJoin("Bea-Realm", { role = "H" }, "WHISPER")
check(#Groups:Requests() == 1 and Groups:Requests()[1].role == "H" and #printed == 1, "asking again changes the role, not the queue")
Groups:HandleJoin("Cid-Realm", { role = "D" }, "WHISPER")
check(#Groups:Requests() == 1 and last(TYPES.LFG_JOIN).to == "Cid-Realm" and last(TYPES.LFG_JOIN).p.decline == true,
  "a role with no spot is declined at once")
Groups:HandleJoin("Dan-Realm", { role = "|cffT" }, "WHISPER")
check(#Groups:Requests() == 1, "and so is a role that is none")
Groups:HandleJoin("Eva-Realm", { role = "T" }, "WHISPER")
check(#Groups:Requests() == 2 and Groups:Requests()[1].key == key("Bea"), "the queue is oldest first")
Groups:HandleJoin("Eva-Realm", { cancel = true }, "WHISPER")
check(#Groups:Requests() == 1, "a request taken back leaves the queue, inside the cooldown too")
runTimers()

check(Groups:Invite(key("Bea")) and invited[1] == "Bea-Realm" and Groups:Requests()[1].state == "invited",
  "inviting calls the game's invite and marks the row")
check(not Groups:Invite(key("Zed")) and #invited == 1, "nobody is invited who did not ask")
runTimers()
Groups:HandleJoin("Eva-Realm", { role = "T" }, "WHISPER")
wire = {}
check(Groups:Decline(key("Eva")) and wire[1].to == "Eva-Realm" and wire[1].p.decline == true and #Groups:Requests() == 1,
  "declining tells the asker and clears the row")

-- The queue is the listed group's
fresh()
Groups:Create("steamvault", { T = 1, D = 1 }, "", 1800, false)
Groups:HandleJoin("Bea-Realm", { role = "T" }, "WHISPER")
CLOCK = CLOCK + 10
Groups:Create("steamvault", { T = 1, D = 2 }, "", 1800, false)
check(#Groups:Requests() == 1, "changing the spots keeps who asked")
wire = {}
Groups:Create("karazhan", { T = 1 }, "", 1800, false)
check(#Groups:Requests() == 0 and wire[1].to == "Bea-Realm" and wire[1].p.closed == true,
  "another activity is another group: who asked hears the first one closed")
runTimers()
Groups:HandleJoin("Bea-Realm", { role = "T" }, "WHISPER")
NOW = NOW + 1801
Groups:Prune()
check(Groups:Mine() == nil and #Groups:Requests() == 0, "and a queue does not outlive a listing that expired")

-- Only whoever can invite lists the group
fresh()
PARTY = { "Bea" }
leader = false
g, why = Groups:Create("steamvault", { D = 1 }, "", 3600, false)
check(g == nil and why == "Only the group's leader can list it." and #wire == 0, "a member of somebody else's party lists nothing")
leader = true
check(Groups:Create("steamvault", { D = 1 }, "", 3600, false) ~= nil, "its leader does")
leader = false
Groups:OnGroupRoster()
check(Groups:Mine() == nil and printed[#printed] == "Only the group's leader can list it.",
  "and a leader who passed the lead no longer lists it")
leader = true

-- A full queue
fresh()
Groups:Create("karazhan", { D = 9 }, "", 3600, false)
for i = 1, Groups.REQUESTS_MAX + 1 do
  guild["M" .. i] = true
  Groups:HandleJoin("M" .. i .. "-Realm", { role = "D" }, "WHISPER")
end
check(#Groups:Requests() == Groups.REQUESTS_MAX, "the queue holds no more than its cap")
check(last(TYPES.LFG_JOIN).to == "M" .. (Groups.REQUESTS_MAX + 1) .. "-Realm" and last(TYPES.LFG_JOIN).p.decline == true,
  "and whoever comes after is declined")

-- ── The party changed ───────────────────────────────────────────────────
fresh()
Groups:Create("steamvault", { T = 1, H = 1 }, "", 3600, false)
runTimers()
Groups:HandleJoin("Bea-Realm", { role = "H" }, "WHISPER")
Groups:HandleJoin("Cid-Realm", { role = "T" }, "WHISPER")
Groups:Invite(key("Bea"))
CLOCK = CLOCK + 10
wire, printed = {}, {}
PARTY = { "Bea" }
Groups:OnGroupRoster()
local mine = Groups:Mine()
check(mine and mine.need.H == 0 and mine.need.T == 1 and mine.n == 2, "the player who joined closes the spot they asked in")
check(#Groups:Requests() == 1 and Groups:Requests()[1].key == key("Cid"), "and leaves the queue")
check(last(TYPES.LFG_GROUP).p.need.H == 0 and last(TYPES.LFG_GROUP).p.n == 2, "the guild hears the group as it is now")
Groups:OnGroupRoster()
check(count(TYPES.LFG_GROUP) == 1, "a roster event that changes nothing sends nothing")

PARTY = { "Bea", "Stranger" }
Groups:OnGroupRoster()
check(Groups:Mine().n == 3 and Groups:Mine().need.T == 1, "somebody invited by hand counts as a member and closes no spot")
check(last(TYPES.LFG_GROUP).p.n == 2, "(said once the publish window allows)")

-- The spots never pass the seats left
do
  local saved = { wire = wire, printed = printed }
  fresh()
  Groups:Create("steamvault", { T = 1, H = 1, D = 2 }, "", 3600, false)
  PARTY = { "W", "X", "Y" }
  Groups:OnGroupRoster()
  local left = Groups:Mine()
  check(left and left.n == 4 and Groups:OpenSpots(left.need) == 1 and left.need.T == 1,
    "three joined by hand: one seat left is one spot open, the first role's")
  fresh()
  Groups:Create("steamvault", { T = 1, H = 1 }, "", 3600, false)
  runTimers()
  Groups:HandleJoin("Bea-Realm", { role = "H" }, "WHISPER")
  Groups:HandleJoin("Cid-Realm", { role = "T" }, "WHISPER")
  Groups:Invite(key("Bea"))
  CLOCK = CLOCK + 10
  wire, printed = saved.wire, saved.printed
  PARTY = { "Bea", "Stranger" }
  Groups:OnGroupRoster()
end

PARTY = { "Bea", "Stranger", "Cid" }
Groups:OnGroupRoster()
check(Groups:Mine() == nil, "with no spot left the listing comes down")
check(printed[#printed] == "Your group is complete: the listing came down.", "and the leader is told")
CLOCK = CLOCK + 10
runTimers()
check(last(TYPES.LFG_GROUP).p.clear == true, "and so is the guild")

-- A full group with spots still open, and the queue it leaves
fresh()
Groups:Create("steamvault", { D = 4 }, "", 3600, false)
runTimers()
Groups:HandleJoin("Dan-Realm", { role = "D" }, "WHISPER")
wire = {}
PARTY = { "W", "X", "Y", "Z" }
Groups:OnGroupRoster()
check(Groups:Mine() == nil, "a group that filled by hand comes down too")
check(wire[1].kind == TYPES.LFG_JOIN and wire[1].to == "Dan-Realm" and wire[1].p.closed == true,
  "and whoever was waiting hears it closed")

-- The asker's side
fresh()
Groups:HandleGroup("Bea-Realm", { act = "karazhan", need = { T = 1 }, ttl = 3600 }, "GUILD")
Groups:HandleGroup("Cid-Realm", { act = "karazhan", need = { T = 1 }, ttl = 3600 }, "GUILD")
Board:SetAvailable(nil, "", 3600, false, "T", { "karazhan" })
Groups:RequestSpot(key("Bea"), "T")
Groups:RequestSpot(key("Cid"), "T")
wire = {}
PARTY = { "Dan" }
Groups:OnGroupRoster()
check(Groups:Asked(key("Bea")) ~= nil and Board:AmAvailable(), "joining somebody I asked nothing of changes nothing")
PARTY = { "Bea", "Dan" }
Groups:OnGroupRoster()
check(Groups:Asked(key("Bea")) == nil and Groups:Asked(key("Cid")) == nil, "in the group of a leader I asked, I ask nobody else")
check(last(TYPES.LFG_JOIN).to == "Cid-Realm" and last(TYPES.LFG_JOIN).p.cancel == true, "the other leader hears I took it back")
check(not Board:AmAvailable(), "and I am no longer listed as looking")

-- Who is looking is heard on the guild channel alone
fresh()
Board:HandleEntry("Zed-Realm", { role = "TANK", note = "x", ttl = 3600 }, "WHISPER")
check(next(GuildOS.db.lfgBoard) == nil and #printed == 0, "a whispered listing is nobody's")
Board:HandleEntry("Bea-Realm", { role = "TANK", note = "x", ttl = 3600 }, "GUILD")
check(GuildOS.db.lfgBoard[key("Bea")] ~= nil, "the guild channel's is a guildmate's")

-- The codes on the wire are nobody else's
do
  local fh = assert(io.open(ADDON .. "/Modules/CommSystem.lua", "rb"))
  local src = fh:read("*a")
  fh:close()
  local seen = {}
  for name, code in src:gmatch('\n%s+([%u_]+)%s*=%s*"(%w%w)",') do
    check(not seen[code], "message code " .. code .. " is " .. name .. "'s alone (also " .. tostring(seen[code]) .. ")")
    seen[code] = name
  end
  check(seen.GF == "LFG_GROUP" and seen.GJ == "LFG_JOIN", "the two new messages are in the table")
  for code in src:gmatch('msgType == "(%w%w)"') do
    check(code ~= "GF" and code ~= "GJ", "no older branch already takes " .. code)
  end
  local other = assert(io.open(ADDON .. "/Modules/WishlistSystem.lua", "rb")):read("*a")
  check(other:find('SendMessage("LP"', 1, true) and not seen.LP, "LP stays the wishlist's loot prio")
end

-- WoW: Forever: a unit may give the first name alone, or the surname in the realm's slot
do
  local has = GuildOS.Client.has
  local was = has.surnames
  has.surnames = true
  local members = { [key("Bea")] = true, ["~Lethaniel"] = true }
  check(GuildOS.Compat.InGroup(members, key("Bea")), "a whole name that matches is there")
  check(GuildOS.Compat.InGroup(members, GuildOS:GetPlayerKey("Lethaniel Blightwood", "Realm")), "a first name decides when the whole one does not")
  check(not GuildOS.Compat.InGroup(members, key("Cid")), "and somebody else is not there")
  has.surnames = false
  check(not GuildOS.Compat.InGroup(members, GuildOS:GetPlayerKey("Lethaniel Blightwood", "Realm")), "elsewhere only the whole name counts")
  has.surnames = was
end

-- ── The party forms itself (#378) ───────────────────────────────────────
local toasts = {}
GuildOS.GroupsToast = function(_, n) toasts[#toasts + 1] = n end
local converted = 0
function ConvertToRaid() converted = converted + 1 end

-- Invite whoever asks
fresh()
GuildOS.db.lfgPrefs.autoInvite = true
Groups:Create("steamvault", { T = 1, D = 1 }, "", 3600, false)
Groups:HandleJoin("Bea-Realm", { role = "T" }, "WHISPER")
check(invited[1] == "Bea-Realm" and Groups:Requests()[1].state == "invited", "a request is an invite at once")
check(#toasts == 0, "and the leader gets no notice to answer")
runTimers()
Groups:HandleJoin("Bea-Realm", { role = "T" }, "WHISPER")
check(#invited == 1, "asking again is not a second invite")

-- Without it, the leader answers from a notice
fresh()
toasts = {}
Groups:Create("steamvault", { T = 1, D = 1 }, "", 3600, false)
Groups:HandleJoin("Bea-Realm", { role = "D" }, "WHISPER")
check(#invited == 0 and #toasts == 1 and toasts[1].kind == "request" and toasts[1].key == key("Bea")
  and toasts[1].role == "D", "with invites by hand the request is a notice for the leader")

-- "inv" by whisper, for a guildmate with no addon
check(Groups:_IsInviteWord("inv") and Groups:_IsInviteWord("  INV ") and Groups:_IsInviteWord("+1")
  and Groups:_IsInviteWord("invite"), "inv, invite, + and +1 are asking for an invite")
check(not Groups:_IsInviteWord("inv pls") and not Groups:_IsInviteWord("invalid") and not Groups:_IsInviteWord(nil),
  "a sentence, another word or nothing is not")
fresh()
check(not Groups:OnWhisper("inv", "Bea-Realm"), "with no group listed a whisper is just a whisper")
Groups:Create("steamvault", { T = 1, D = 1 }, "", 3600, false)
check(not Groups:OnWhisper("inv", "Bea-Realm") and #invited == 0, "and with invites by hand, too")
GuildOS.db.lfgPrefs.autoInvite = true
check(not Groups:OnWhisper("inv", "Zed-Realm") and #invited == 0, "nobody outside the guild is invited")
check(not Groups:OnWhisper("hello", "Bea-Realm") and #invited == 0, "a whisper that asks nothing invites nobody")
check(Groups:OnWhisper("inv", "Bea-Realm") and invited[1] == "Bea-Realm", "a guildmate who whispers inv is invited")
check(printed[#printed] and printed[#printed]:find("Bea", 1, true) ~= nil, "and the leader is told who: " .. tostring(printed[#printed]))
check(not Groups:OnWhisper("inv", "Bea-Realm") and #invited == 1, "whispering it again inside the cooldown does nothing")
runTimers()
PARTY = { "Bea" }
check(not Groups:OnWhisper("inv", "Bea-Realm") and #invited == 1, "nor once already in the group")
PARTY = {}
Groups:Disband()
check(not Groups:OnWhisper("inv", "Cid-Realm"), "a group taken down invites nobody")

-- Where the game drops an invite sent from the whisper's event (#449, Compat.NeedsHardware), it waits in the officer
-- action queue, and the key press (ActionQueue:Next) sends it; one that no longer applies is passed over.
fresh()
dofile(ADDON .. "/Modules/ActionQueue.lua")
local needs = GuildOS.Compat.NeedsHardware
GuildOS.Compat.NeedsHardware = function(kind) return kind == "groupInvite" end
Groups:Create("steamvault", { T = 1, D = 1 }, "", 3600, false)
GuildOS.db.lfgPrefs.autoInvite = true
invited = {}
check(Groups:OnWhisper("inv", "Dan-Realm") and #invited == 0 and GuildOS.ActionQueue:Pending() == 1,
  "queued: the whisper's event invites nobody, the queue holds it")
check(GuildOS.ActionQueue:Next() and invited[1] == "Dan-Realm" and GuildOS.ActionQueue:Pending() == 0,
  "the key press invites them")
GuildOS.Compat.NeedsHardware = needs
GuildOS.ActionQueue = nil
Groups:Disband()

-- A raid-sized group turns the party into a raid
fresh()
converted = 0
Groups:Create("karazhan", { T = 2, H = 2, D = 5 }, "", 3600, false)
Groups:OnGroupRoster()
check(converted == 0, "alone there is no party to convert")
PARTY = { "Bea" }
Groups:OnGroupRoster()
check(converted == 1, "a raid's group becomes a raid as soon as somebody joins")
leader = false
PARTY = { "Bea", "Cid" }
Groups:OnGroupRoster()
check(converted == 1, "only the leader converts")
leader = true
fresh()
converted = 0
Groups:Create("steamvault", { T = 1, D = 2 }, "", 3600, false)
PARTY = { "Bea" }
Groups:OnGroupRoster()
check(converted == 0, "a dungeon's party stays a party")

-- The line in guild chat, again every ten minutes
fresh()
GuildOS.db.lfgPrefs.autoInvite = true
Groups:Create("steamvault", { T = 1, D = 2 }, "SP", 3600, true)
check(#said == 1 and said[1].msg:find('Whisper me "inv"', 1, true), "inviting whoever asks, the line says how")
NOW = NOW + 300
check(not Groups:Tick() and #said == 1, "five minutes on it says nothing again")
NOW = NOW + 300
check(Groups:Tick() and #said == 2 and said[2].msg:find("(1/5)", 1, true), "ten minutes on it does")
NOW = NOW + 100
check(not Groups:Tick() and #said == 2, "and then waits ten more")
PARTY = { "Bea" }
Groups:OnGroupRoster()
NOW = NOW + 500
check(Groups:Tick() and said[3].msg:find("(2/5)", 1, true), "with how full the group is by then")
fresh()
Groups:Create("steamvault", { T = 1 }, "", 3600, false)
check(not Groups:Tick(NOW + 600) and #said == 0, "a group listed without the box is never said in chat")
fresh()
Board:SetAvailable(nil, "x", 3600, true, "T", {})
Groups:Create("steamvault", { T = 1 }, "", 3600, true)
check(#said == 1, "the five-minute cooldown holds the group's first line back")
NOW = NOW + 60
check(Groups:Tick() == false, "the next tick still waits on it")
NOW = NOW + 240
check(Groups:Tick() and #said == 2, "and the line goes out once the cooldown is over")
fresh()
Groups:Create("steamvault", { T = 1 }, "", 3600, true)
Groups:Disband()
NOW = NOW + 600
check(not Groups:Tick(), "a group taken down stops saying it")

-- A guildmate's new group: a notice where it fits me, the chat line otherwise
fresh()
toasts = {}
local function listing(act, need) return Groups:_BuildGroup({ act = act, need = need, ttl = 3600 }, NOW) end
check(Groups:FitsLevel("steamvault", 70) and Groups:FitsLevel("steamvault", 63) and not Groups:FitsLevel("steamvault", 62),
  "an activity fits a level inside its range, give or take five")
check(not Groups:FitsLevel("not-an-activity", 70), "an unknown activity fits nobody")
check(Groups:BestRole({ T = 0, H = 1, D = 2 }, "D") == "D" and Groups:BestRole({ T = 1, D = 2 }, "") == "T"
  and Groups:BestRole({ T = 1 }, "H") == nil, "the role asked is the first of mine with a spot")
local dm = listing("steamvault", { T = 1, D = 1 })
check(Groups:_ShouldToast(dm, 70, false), "a group for my level, free, gets a notice")
check(not Groups:_ShouldToast(dm, 50, false), "not one for another level")
check(not Groups:_ShouldToast(dm, 70, true), "not in a group")
Board:SetPref("roles", "H")
check(not Groups:_ShouldToast(dm, 70, false), "not with no spot for any role of mine")
Board:SetPref("roles", "")
GuildOS.db.lfgPrefs.toast = false
check(not Groups:_ShouldToast(dm, 70, false), "and not with the notices off")
GuildOS.db.lfgPrefs.toast = true
Groups:Create("steamvault", { T = 1 }, "", 3600, false)
check(not Groups:_ShouldToast(dm, 70, false), "nor while I lead a group of my own")
Groups:Disband()
check(Groups:_Announce(key("Bea"), "Bea", Groups:_BuildGroup({ act = "karazhan", need = { T = 1 }, ttl = 3600 }, NOW)) == "toast"
  and toasts[1].kind == "group" and toasts[1].act == "karazhan" and #printed == 0,
  "a new group that fits a level-less client is a notice, not a chat line")
-- In combat the notice is still asked for (#449): GuildOS:ShowWhenClear holds it until combat ends,
-- where before it was dropped for good.
function InCombatLockdown() return true end
toasts = {}
check(Groups:_Announce(key("Cid"), "Cid", Groups:_BuildGroup({ act = "karazhan", need = { T = 1 }, ttl = 3600 }, NOW)) == "toast"
  and #toasts == 1, "in combat a group that fits is still a notice, held for after it")
InCombatLockdown = nil
local panelSrc = assert(io.open(ADDON .. "/UI/GroupsPanel.lua", "rb")):read("*a")
check(panelSrc:find("self:ShowWhenClear(\"groups:\"", 1, true) ~= nil, "and the notice opens through ShowWhenClear, never in combat")
check(panelSrc:find("G:StillTrue(n)", 1, true) ~= nil, "and checks, when it shows, that it is still true")
GuildOS.db.lfgPrefs.toast = false
check(Groups:_Announce(key("Bea"), "Bea", dm) == "chat" and #printed == 1, "with the notices off it is the chat line")
GuildOS.GroupsToast = nil

-- A notice that waited behind combat says only what is still true (#449)
fresh()
GuildOS.db.lfgGroups[key("Bea")] = Groups:_BuildGroup({ act = "steamvault", need = { T = 1 }, ttl = 3600 }, NOW)
GuildOS.db.lfgGroups[key("Bea")].from = "Bea-Realm"
local note = { kind = "group", key = key("Bea") }
check(Groups:StillTrue(note), "a group still up with a spot for me is still news")
Board:SetPref("roles", "H")
check(not Groups:StillTrue(note), "not once it has no spot in a role of mine")
Board:SetPref("roles", "")
Groups:RequestSpot(key("Bea"), "T")
check(not Groups:StillTrue(note), "nor once I asked it already")
Groups:CancelRequest(key("Bea"))
NOW = NOW + 3600
check(not Groups:StillTrue(note), "nor once it ended")
NOW = NOW - 3600
check(not Groups:StillTrue({ kind = "request", key = key("Cid") }), "a request nobody is waiting on is not")
check(not Groups:StillTrue({ kind = "expiring", what = "group" }) and not Groups:StillTrue({ kind = "nonsense" }),
  "nor a warning about a listing I no longer have, nor anything else")

-- ── The leader's tools (#378) ───────────────────────────────────────────
-- A start later on crosses the wire as seconds from now, and never past the listing's end
fresh()
g = Groups:Create("karazhan", { T = 1, D = 3 }, "", 3600, false, 1800)
check(g.start == NOW + 1800 and Groups:StartsIn(g, NOW) == 1800, "a group can start later")
check(last(TYPES.LFG_GROUP).p.startIn == 1800, "and says so as seconds from now")
check(Groups:Create("karazhan", { T = 1 }, "", 1800, false, 99999).start == NOW + 1740,
  "a start never passes the listing's end")
check(Groups:Create("karazhan", { T = 1 }, "", 3600, false).start == nil, "and with none it starts now")
local heard = Groups:_BuildGroup({ act = "karazhan", need = { T = 1 }, ttl = 3600, age = 600, startIn = 1e9 }, NOW)
check(heard.start == NOW + 3000, "a start heard is clamped to what is left of the listing")
heard = Groups:_BuildGroup({ act = "karazhan", need = { T = 1 }, ttl = 3600, startIn = -5 }, NOW)
check(heard.start == nil and Groups:StartsIn(heard, NOW) == nil, "and one in the past is now")
fresh()
Groups:Create("steamvault", { T = 1 }, "", 1800, true, 900)
check(said[1].msg:find("(starts in 15m)", 1, true), "the guild line says when it starts: " .. said[1].msg)

-- +30 minutes
fresh()
Groups:Create("steamvault", { T = 1 }, "", 1800, false)
NOW = NOW + 1500
CLOCK = CLOCK + 10
check(Groups:Extend() and Groups:Mine().ts == NOW and Groups:Mine().ttl == 2100, "+30 min adds to what is left")
runTimers()
check(last(TYPES.LFG_GROUP).p.ttl == 2100 and last(TYPES.LFG_GROUP).p.age == 0, "and says the new end")
Groups:Extend(1e6)
check(Groups:Mine().ttl == 7200, "never past the longest duration")
Groups:Disband()
check(not Groups:Extend(), "with no group there is nothing to extend")
fresh()
Board:SetAvailable(nil, "x", 1800, false, "T", {})
NOW = NOW + 1700
check(Board:Extend() and Board:Mine().ttl == 1900 and wire[#wire].p.ttl == 1900, "my own listing takes 30 minutes more too")

-- Post in chat now, outside the ten minutes
fresh()
Groups:Create("steamvault", { T = 1 }, "", 3600, true)
local ok, wait = Groups:PostNow()
check(not ok and wait == 300 and #said == 1, "the five-minute cooldown holds it, and says how long")
NOW = NOW + 300
check(Groups:PostNow() and #said == 2 and Board:GuildLineWait() == 300, "and then it goes out")

-- A ready check
fresh()
local checksRun = 0
function DoReadyCheck() checksRun = checksRun + 1 end
Groups:Create("steamvault", { T = 1, D = 2 }, "", 3600, false)
check(not Groups:CanReadyCheck() and not Groups:ReadyCheck(), "alone there is nobody to check")
PARTY = { "Bea" }
check(Groups:CanReadyCheck() and Groups:ReadyCheck() and checksRun == 1, "with somebody in it the leader checks")
leader = false
check(not Groups:CanReadyCheck(), "a member does not")
leader = true
DoReadyCheck = nil

-- Who is looking and fits my group
fresh()
Groups:Create("steamvault", { T = 1, D = 1 }, "", 3600, false)
local store = GuildOS.db.lfgBoard
store[key("Bea")] = { role = "TANK", roles = "T", acts = { "steamvault" }, note = "", ts = NOW, ttl = 3600 }
store[key("Cid")] = { role = "HEALER", roles = "H", acts = {}, note = "", ts = NOW, ttl = 3600 }
store[key("Dan")] = { role = "ANY", roles = "", acts = {}, note = "", ts = NOW - 1, ttl = 3600 }
store[key("Eva")] = { role = "DPS", roles = "D", acts = { "karazhan" }, note = "", ts = NOW, ttl = 3600 }
local matches = Groups:Matches(NOW)
local byKey = {}
for _, m in ipairs(matches) do byKey[m.key] = m.role end
check(byKey[key("Bea")] == "T", "a tank for my activity fits, as a tank")
check(byKey[key("Dan")] == "T", "somebody who plays anything, for anything, fits in my first open spot")
check(byKey[key("Cid")] == nil, "a healer does not, with no healer's spot")
check(byKey[key("Eva")] == nil, "nor somebody who wants another activity")
check(Groups:InviteSeeker(key("Bea"), "Bea", "T") and invited[#invited] == "Bea", "inviting one calls the game's invite")
check(Groups:Requests()[1].key == key("Bea") and Groups:Requests()[1].state == "invited", "and they wait in the queue as invited")
check(#Groups:Matches(NOW) == 1, "so they no longer show as a match")
check(not Groups:InviteSeeker(key("Cid"), "Cid", "H"), "nobody is invited into a role with no spot")
PARTY = { "Bea" }
Groups:OnGroupRoster()
check(Groups:Mine().need.T == 0 and Groups:Mine().need.D == 1, "the tank's spot closes when they join, not another")

-- About to end
fresh()
toasts = {}
GuildOS.GroupsToast = function(_, n) toasts[#toasts + 1] = n end
Groups:Create("steamvault", { T = 1 }, "", 1800, false)
check(Groups:_WarnExpiring(NOW + 1400) == nil, "with ten minutes left nothing is said")
check(Groups:_WarnExpiring(NOW + 1520) == "group" and toasts[1].kind == "expiring" and toasts[1].what == "group",
  "five minutes before the end the leader is told, with +30 min a click away")
check(Groups:_WarnExpiring(NOW + 1560) == nil, "and only once")
Groups:Extend()
check(Groups:_WarnExpiring(NOW + 1520) == nil and not Groups:Mine().warned, "a listing extended warns again later")
fresh()
Board:SetAvailable(nil, "x", 1800, false, "T", {})
check(Groups:_WarnExpiring(NOW + 1600) == "seek", "my own listing as well")
GuildOS.GroupsToast = nil

-- A group for me
fresh()
local fit70 = Groups:_BuildGroup({ act = "steamvault", need = { T = 1 }, ttl = 3600 }, NOW)
fit70.key = key("Bea")
check(Groups:FitsMe(fit70, 70, "T") and not Groups:FitsMe(fit70, 70, "H") and not Groups:FitsMe(fit70, 50, "T"),
  "a group is for me at my level with a spot in my role")
fit70.key = Board:MyKey()
check(not Groups:FitsMe(fit70, 70, "T"), "and never my own")

-- ── The board keeps itself clean (#449) ─────────────────────────────────
-- A listing heard with no spot left is a group that filled: it closes, and nothing lists it
fresh()
Groups:HandleGroup("Bea-Realm", { act = "steamvault", need = { T = 1 }, ttl = 3600 }, "GUILD")
Groups:RequestSpot(key("Bea"), "T")
runTimers()
Groups:HandleGroup("Bea-Realm", { act = "steamvault", need = { T = 0, H = 0, D = 0 }, n = 5, ttl = 3600 }, "GUILD")
check(GuildOS.db.lfgGroups[key("Bea")] == nil and Groups:Asked(key("Bea")) == nil, "a full group heard closes, and so does what I asked of it")
GuildOS.db.lfgGroups[key("Cid")] = { act = "steamvault", need = { T = 0, H = 0, D = 0 }, n = 5, max = 5, ts = NOW, ttl = 3600 }
check(#Groups:ActiveList(GuildOS.db.lfgGroups, NOW) == 0, "and a full one stored from before is not listed")

-- Expired listings leave on the minute's tick, with the tab closed too
fresh()
local refreshed = 0
Board.uiRefresh = function() refreshed = refreshed + 1 end
GuildOS.db.lfgGroups[key("Bea")] = Groups:_BuildGroup({ act = "steamvault", need = { T = 1 }, ttl = 1800 }, NOW)
GuildOS.db.lfgBoard[key("Cid")] = Board:_BuildEntry({ roles = "H", ttl = 1800 }, NOW)
Groups:Tick(NOW + 60)
check(GuildOS.db.lfgGroups[key("Bea")] and GuildOS.db.lfgBoard[key("Cid")] and refreshed == 0, "a live listing stays, and nothing repaints")
Groups:Tick(NOW + 1801)
check(GuildOS.db.lfgGroups[key("Bea")] == nil and GuildOS.db.lfgBoard[key("Cid")] == nil and refreshed == 1,
  "an expired group and an expired player leave the saved board, and the tab repaints once")

-- Whoever logs off or leaves the guild leaves the board, and what was asked of them
fresh()
Groups:HandleGroup("Bea-Realm", { act = "steamvault", need = { T = 1 }, ttl = 3600 }, "GUILD")
Groups:RequestSpot(key("Bea"), "T")
GuildOS.db.lfgBoard[key("Cid")] = Board:_BuildEntry({ roles = "H", ttl = 3600 }, NOW)
GuildOS.db.lfgBoard[key("Dan")] = Board:_BuildEntry({ roles = "D", ttl = 3600 }, NOW)
check(Groups:SweepOffline({}) == 0 and GuildOS.db.lfgGroups[key("Bea")], "a roster without me in it (not loaded yet) drops nothing")
local online = { [Board:MyKey()] = true, [key("Dan")] = true }
-- Bea's listing was heard at NOW: a roster read before it has not seen her online yet, and keeps her (#449 review).
check(Groups:SweepOffline(online, NOW - 30) == 1 and GuildOS.db.lfgGroups[key("Bea")] ~= nil and Groups:Asked(key("Bea")) ~= nil,
  "a listing heard after the roster was read stays, and what I asked of it: she logged in after it")
check(Groups:SweepOffline(online, NOW + 1) == 2, "with a roster read since, the offline leader and my request go too")
check(GuildOS.db.lfgGroups[key("Bea")] == nil and Groups:Asked(key("Bea")) == nil and GuildOS.db.lfgBoard[key("Cid")] == nil
  and GuildOS.db.lfgBoard[key("Dan")] ~= nil, "and whoever is online stays")
-- The minute's tick asks the game for a fresh roster and sweeps when it lands, never on the cached one.
fresh()
local asked = 0
local oldRoster = GuildOS.Compat.GuildRoster
GuildOS.Compat.GuildRoster = function() asked = asked + 1 end
Groups:HandleGroup("Eve-Realm", { act = "steamvault", need = { T = 1 }, ttl = 3600 }, "GUILD")
Groups:Tick(NOW + 60)
check(asked == 1 and GuildOS.db.lfgGroups[key("Eve")] ~= nil, "the tick asks for the roster and drops nobody yet")
local oldBuild = Board._BuildOnlineRoster
Board._BuildOnlineRoster = function() return { [Board:MyKey()] = true } end
check(Groups:OnGuildRoster(NOW + 61) == 1 and GuildOS.db.lfgGroups[key("Eve")] == nil,
  "the roster that lands after it, without her, takes her listing down")
check(Groups:OnGuildRoster(NOW + 62) == 0, "and a roster update nobody asked for sweeps nothing")
Board._BuildOnlineRoster, GuildOS.Compat.GuildRoster = oldBuild, oldRoster
fresh()
Groups:Create("steamvault", { T = 1, D = 1 }, "", 3600, false)
Groups:HandleJoin("Bea-Realm", { role = "T" }, "WHISPER")
Groups:SweepOffline({ [Board:MyKey()] = true }, NOW + 1)
check(#Groups:Requests() == 0 and Groups:Mine() ~= nil, "a leader's queue drops who logged off, and keeps the group")

-- Joining a guildmate's listed group, by their invite, takes my own listing down
fresh()
Board:SetAvailable(nil, "x", 3600, false, "T", { "steamvault" })
Groups:HandleGroup("Bea-Realm", { act = "steamvault", need = { T = 1 }, ttl = 3600 }, "GUILD")
PARTY = { "Cid" }
Groups:OnGroupRoster()
check(Board:AmAvailable(), "a party with somebody else in it leaves me listed")
PARTY = { "Bea" }
Groups:OnGroupRoster()
check(not Board:AmAvailable() and last(TYPES.LFG).p.clear == true, "in the party of a listed group I am no longer looking, and the guild hears it")

-- A take-down is heard inside the cooldown of the listing before it
fresh()
Board:HandleEntry("Bea-Realm", { roles = "T", ttl = 3600 }, "GUILD")
check(GuildOS.db.lfgBoard[key("Bea")] ~= nil, "a guildmate lists")
Board:HandleEntry("Bea-Realm", { clear = true }, "GUILD")
check(GuildOS.db.lfgBoard[key("Bea")] == nil, "and taking it down a moment later is heard, cooldown or not")
Board:HandleEntry("Bea-Realm", { roles = "H", ttl = 3600 }, "GUILD")
check(GuildOS.db.lfgBoard[key("Bea")] == nil, "while a new listing still waits out the cooldown")
Board.uiRefresh = nil

-- ── My quests in the guild LFG (#450) ───────────────────────────────────
do
  dofile(ADDON .. "/Modules/GroupQuests.lua")
  local Q = GuildOS.GroupQuests
  local Compat = GuildOS.Compat
  local SECRET = {}
  issecretvalue = function(v) return v == SECRET end

  -- The modern shape: C_QuestLog's GetInfo tables, tags as tables, the suggested size asked apart.
  local LOG = {
    { title = "Westfall", isHeader = true },
    { title = "The Defias Brotherhood", questID = 155, level = 22, suggestedGroup = 5 },
    { title = "Red Leather Bandanas", questID = 153, level = 15 },
    { title = "Hidden thing", questID = 999, level = 20, isHidden = true },
    { title = "Hellfire Peninsula", isHeader = true },
    { title = "Wanted: Worg Master Kruush", questID = 10809, level = 62 },
    { title = SECRET, questID = 4242, level = 62 },
    { title = "Bad id", questID = 1.5, level = 1 },
  }
  local TAGS = { [10809] = { tagID = 1, tagName = "Group", isElite = true } }
  local SIZES = { [10809] = 3 }
  C_QuestLog = {
    GetNumQuestLogEntries = function() return #LOG end,
    GetInfo = function(i) return LOG[i] end,
    GetQuestTagInfo = function(id) return TAGS[id] end,
    GetSuggestedGroupSize = function(id) return SIZES[id] or 0 end,
  }
  local out, n = Compat.QuestLog({})
  check(n == 3 and #out == 3, "modern log: three quests read, the header, the hidden, the secret and the bad id left out (" .. n .. ")")
  check(out[1].id == 155 and out[1].zone == "Westfall" and out[1].level == 22 and out[1].size == 5 and out[1].group,
    "a quest has its zone (its header), level and suggested players, and a size over one is a group quest")
  check(out[2].id == 153 and not out[2].group and out[2].size == 0, "a solo quest is no group quest")
  check(out[3].zone == "Hellfire Peninsula" and out[3].tag == "Group" and out[3].elite and out[3].size == 3 and out[3].group,
    "the client's tag, elite and GetSuggestedGroupSize are read")
  local kept = out[1]
  Compat.QuestLog(out)
  check(out[1] == kept, "a second read refills the same tables")

  -- The Classic-era shape: the globals, the tag by quest id.
  C_QuestLog = nil
  local CLASSIC = {
    { "Elwynn Forest", 0, 0, true },
    { "Kobold Camp Cleanup", 7, 0, false, false, false, 0, 7 },
    { "The Stockade Riots", 26, 0, false, false, false, 0, 391 },
    { SECRET, 5, 0, false, false, false, 0, 11 },
  }
  GetNumQuestLogEntries = function() return #CLASSIC, 3 end
  GetQuestLogTitle = function(i) return unpack(CLASSIC[i]) end
  GetQuestTagInfo = function(id) if id == 391 then return 81, "Dungeon" end end
  out, n = Compat.QuestLog({})
  check(n == 2 and out[1].id == 7 and out[1].zone == "Elwynn Forest" and not out[1].group,
    "Classic log: the quests under their zone header, the secret one left out")
  check(out[2].id == 391 and out[2].tag == "Dungeon" and out[2].tagID == 81 and out[2].group, "a dungeon tag is a group quest")
  GetNumQuestLogEntries, GetQuestLogTitle, GetQuestTagInfo = nil, nil, nil
  C_QuestLog = { GetNumQuestLogEntries = function() return #LOG end, GetInfo = function(i) return LOG[i] end,
    GetQuestTagInfo = function(id) return TAGS[id] end, GetSuggestedGroupSize = function(id) return SIZES[id] or 0 end }

  -- The cache: group quests first, one read for a burst of events, a repaint only when it changed.
  fresh()
  local repaints = 0
  Board.uiRefresh = function() repaints = repaints + 1 end
  Q:Refresh()
  local list = Q:List()
  check(list[1].id == 155 and list[2].id == 10809 and list[3].id == 153, "group quests come first, the log's order kept")
  check(Q:Has(10809) and not Q:Has(999) and Q:Title(153) == "Red Leather Bandanas", "what is in my log, by id")
  check(Q:Title(424242, "Their title") == "Their title", "a quest not in my log keeps the listing's title")
  for _ = 1, 10 do Q._OnEvent() end
  check(#timers == 1, "ten QUEST_LOG_UPDATEs make one read (" .. #timers .. " timers)")
  runTimers()
  check(repaints == 0, "a read that changed nothing repaints nothing")
  LOG[#LOG + 1] = { title = "Fel Orc Scavengers", questID = 10482, level = 61 }
  Q._OnEvent()
  runTimers()
  check(repaints == 1 and Q:Has(10482), "a quest picked up repaints once")
  Board.uiRefresh = nil

  -- Off the wire: whole ids, plain capped titles, each once, never more than the cap.
  check(Q:_SanitizeId(12) == 12 and not Q:_SanitizeId(0) and not Q:_SanitizeId(-3) and not Q:_SanitizeId(1.5)
    and not Q:_SanitizeId(2 ^ 30) and not Q:_SanitizeId("12") and not Q:_SanitizeId(0 / 0), "an id is a whole number in range")
  local q = Q:_SanitizeQuest({ id = 5, t = "|cffff0000Evil|r |TInterface\\X:64|t" .. string.rep("x", 200) })
  check(q and not q.t:find("|", 1, true) and #q.t <= Q.TITLE_MAX, "a title loses its escapes and is capped: " .. tostring(q and #q.t))
  check(Q:_SanitizeQuest({ id = 5, t = {} }).t == "" and Q:_SanitizeQuest("x") == nil, "a title that is no string is none")
  local qs = Q:_SanitizeQuests({ { id = 1, t = "a" }, { id = 1, t = "dup" }, "junk", { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 } })
  check(#qs == Q.PICK_MAX and qs[1].t == "a" and qs[2].id == 2, "quests: each once, at most PICK_MAX (" .. #qs .. ")")
  check(#Q:_SanitizeQuests("nope") == 0 and #Q:_SanitizeIds(7) == 0, "a list that is no table is empty")
  local many = {}
  for i = 1, 40 do many[i] = i end
  check(#Q:_SanitizeIds(many) == Q.SHARE_MAX, "shared ids are capped at SHARE_MAX")

  -- Looking: only the quests picked go out, with Elite quests for a client before #450; nothing shared by default.
  check(GuildOS.db.lfgPrefs.shareQuests == false and Board:Pref("shareQuests") == false, "sharing my log is off by default")
  Board:SetAvailable(nil, "", 3600, false, "D", { "karazhan" }, { { id = 155, t = "The Defias Brotherhood" } })
  local p = last("LG").p
  check(p.quests and #p.quests == 1 and p.quests[1].id == 155 and p.quests[1].t == "The Defias Brotherhood",
    "the listing carries the quest picked, id and title")
  check(p.shared == nil, "and none of the rest of my log")
  check(tContains(p.acts, "karazhan") and tContains(p.acts, "elite-quests") and #p.acts == 2,
    "Elite quests goes out with them, which an old client knows")
  check(Board:Mine().questAct == true, "remembered as added for the quests, not picked")
  local keys = 0
  for _ in pairs(p) do keys = keys + 1 end
  check(keys == 6, "the payload is the old one plus quests (" .. keys .. " fields)")
  Board:SetAvailable(nil, "", 3600, false, "D", { "karazhan" })
  p = last("LG").p
  check(p.quests == nil and p.shared == nil and #p.acts == 1, "with no quest picked the payload is the one before #450")
  Board:SetPref("shareQuests", true)
  Board:SetAvailable(nil, "", 3600, false, "D", {}, { { id = 155, t = "The Defias Brotherhood" } })
  p = last("LG").p
  check(p.shared and #p.shared == 1 and p.shared[1] == 10809, "opted in, the group quests of my log go as ids, the picked ones not twice")
  check(type(p.shared[1]) == "number", "ids only, never titles")
  Board:SetPref("shareQuests", false)
  Board._cd = {}
  Board:Rebroadcast()
  check(last("LG").p.shared[1] == 10809 and last("LG").p.quests[1].id == 155, "a rebroadcast says the same quests")

  -- Hearing them: checked on the way in; an old listing has none.
  Board:HandleEntry("Bea-Realm", { roles = "T", acts = { "elite-quests" }, ttl = 3600,
    quests = { { id = 10809, t = "Their| title" }, { id = "x" } }, shared = { 155, -1, "z", 155 } }, "GUILD")
  local bea = Board:ActiveList(GuildOS.db.lfgBoard, NOW)
  for _, e in ipairs(bea) do if e.key == key("Bea") then bea = e end end
  check(#bea.quests == 1 and bea.quests[1].t == "Their title" and #bea.shared == 1 and bea.shared[1] == 155,
    "a listing's quests and shared ids are sanitised")
  check(Q:InMyLog(bea) == 10809 and Q:Lists(bea, 155) and not Q:Lists(bea, 153), "and compared with my own log, here")
  check(Board:Describe(bea) == "Wanted: Worg Master Kruush", "a listing is described by my log's title, Elite quests not said twice")
  Board:HandleEntry("Cid-Realm", { roles = "H", acts = { "karazhan" }, ttl = 3600 }, "GUILD")
  local cid = GuildOS.db.lfgBoard[key("Cid")]
  check(#cid.quests == 0 and #cid.shared == 0, "a listing from before #450 has no quest")

  -- A group for a quest: under Elite quests, its quest checked, matched by whoever names it.
  fresh()
  Q:Refresh()
  local g = Groups:Create("karazhan", { T = 1, D = 2 }, "", 3600, false, 0, { id = 10809, t = "Wanted: Worg Master Kruush" })
  check(g and g.act == "elite-quests" and g.quest.id == 10809, "a group for a quest is listed under Elite quests")
  p = last("GF").p
  check(p.act == "elite-quests" and p.quest.id == 10809 and p.quest.t == "Wanted: Worg Master Kruush", "its quest goes out with it")
  check(Groups:Title(g) == "Wanted: Worg Master Kruush", "and names it")
  Board:HandleEntry("Dan-Realm", { roles = "D", acts = { "deadmines" }, ttl = 3600, shared = { 10809 } }, "GUILD")
  Board:HandleEntry("Eva-Realm", { roles = "D", acts = { "elite-quests" }, ttl = 3600 }, "GUILD")
  local m = Groups:Matches(NOW)
  check(#m == 2 and m[1].key == key("Dan") and m[1].quest and not m[2].quest,
    "who has the group's quest fits it and comes first, marked; who wants elite quests fits too")
  local counts = Groups:Counts(NOW)
  check(counts[10809] and counts[10809].groups == 1 and counts[10809].seekers == 1, "a quest is counted by its id")
  Groups:Disband()

  local old = GuildOS.GroupQuests
  GuildOS.GroupQuests = nil   -- a client before #450 reading the same listing
  local og = Groups:_BuildGroup(p, NOW)
  check(og and og.act == "elite-quests" and og.quest == nil, "an old client lists the group as Elite quests and ignores the quest")
  local oe = Board:_BuildEntry({ roles = "D", acts = { "elite-quests" }, quests = { { id = 1, t = "x" } } }, NOW)
  check(oe and #oe.acts == 1 and #oe.quests == 0, "and a listing as looking for elite quests")
  GuildOS.GroupQuests = old
  local bad = Groups:_BuildGroup({ act = "elite-quests", quest = { id = -5, t = "x" }, need = { D = 1 } }, NOW)
  check(bad and bad.quest == nil, "a group's forged quest is dropped, the group kept")
  Groups:HandleGroup("Bea-Realm", { act = "elite-quests", need = { D = 1 }, ttl = 3600, quest = { id = 155, t = "Theirs" } }, "GUILD")
  check(GuildOS.db.lfgGroups[key("Bea")].quest.id == 155 and Groups:Title(GuildOS.db.lfgGroups[key("Bea")]) == "The Defias Brotherhood",
    "a group heard is named by my log's title for its quest")
  issecretvalue = nil
end

-- ── The catalogue of each client ────────────────────────────────────────
local function catalogue(client)
  local real = GuildOS
  GuildOS = { L = real.L, Client = client }
  dofile(ADDON .. "/Data/GroupActivities.lua")
  local cat = GuildOS.GroupActivities
  GuildOS = real
  return cat
end
for name, client in pairs({ anniversary = { isAnniversary = true }, retail = { isRetail = true }, forever = {} }) do
  local cat = catalogue(client)
  local seen, n = {}, 0
  for _, s in ipairs(cat.sections) do
    check(type(s.title) == "string" and s.title ~= "" and #s.items > 0, name .. ": a section has a title and something in it")
    for _, it in ipairs(s.items) do
      n = n + 1
      check(not seen[it.id], name .. ": " .. it.id .. " is listed once")
      seen[it.id] = true
      check(Board:_SanitizeAct(it.id) == it.id, name .. ": " .. it.id .. " crosses the wire as it is")
      check(type(it.name) == "string" and it.name ~= "", name .. ": " .. it.id .. " has a name")
      check(it.size >= 2 and it.size <= 40, name .. ": " .. it.id .. " has a group's size")
      check((it.min == nil) == (it.max == nil) and (it.min == nil or it.min <= it.max), name .. ": " .. it.id .. " has a level range or none")
      check(cat.byId[it.id] == it and it.cat == s.cat, name .. ": " .. it.id .. " is found by its id")
    end
  end
  for _, c in ipairs(cat.CATS) do
    check(#cat:Sections(c) > 0, name .. ": the " .. c .. " tab has something to show")
  end
  check(n >= 10, name .. ": a catalogue worth a tab (" .. n .. ")")
end
do
  local forever = catalogue({})
  local real = GuildOS
  GuildOS = { L = real.L, Client = {} }
  dofile(ADDON .. "/Data/ForeverDungeons.lua")
  local journal = GuildOS.ForeverDungeons
  GuildOS = real
  for map, d in pairs(journal.byInstance) do
    if #d.bosses > 0 then
      check(forever.byId[d.id] and forever.byId[d.id].map == map, "Forever's " .. d.id .. " is the journal's, by the same id and map")
    end
  end
end

print(checks .. " checks ok")
