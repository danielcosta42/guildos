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
  SendMessage = function(_, kind, payload, target) wire[#wire + 1] = { kind = kind, p = payload, to = target } end,
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
check(#said == 1 and said[1].chan == "GUILD"
  and said[1].msg == "[Guild OS] Group for The Steamvault, looking for 1 Tank, 1 Healer, 2 DPS: ab",
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
