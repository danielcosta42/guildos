-- Somebody with alts removed or gone (issue #426), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/CommSystem.lua, Modules/SyncService.lua, Modules/AltSync.lua,
-- Modules/GuildManager.lua, Modules/RosterLog.lua, Modules/BanList.lua, Modules/BulkActions.lua and
-- Modules/AltDeparture.lua, with several clients on one guild channel.
--
-- Removing a main with two alts asks the officer who removed them (and only them) about the two, by name
-- in class colour; "Remove them too" queues the two in Bulk actions and never calls the protected API;
-- "Ban the group" bans the three with one term, synced, and the officer's note never leaves their client; a removal while a queue runs is
-- asked about once it is through; a main leaving asks each officer once, and "Set A as main" holds for
-- everybody; nothing during the login's settle, in a chat lockdown, for a member without alts or an alt.
--
--   luajit -e 'ADDON="."' tools/alt-departure.lua
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
  { "OffA", 1, "PALADIN" }, { "OffB", 1, "PRIEST" }, { "Mem", 5, "MAGE" },
  { "Main", 4, "WARRIOR" }, { "AltX", 6, "ROGUE" }, { "AltY", 6, "DRUID" },
  { "Solo", 5, "HUNTER" },
  { "Main2", 4, "WARLOCK" }, { "Alt2", 6, "SHAMAN" },
  { "Main3", 4, "MAGE" }, { "Alt3", 6, "PRIEST" },
  { "Main4", 3, "WARRIOR" }, { "AltA", 6, "MAGE" }, { "AltB", 6, "ROGUE" },
  { "Main5", 3, "DRUID" }, { "AltC", 6, "PALADIN" },
}
local me = "OffA"
local now = 1792000000
local afters = {}
local registry, store, n = {}, {}, 0
local handlers = {}   -- the CHAT_MSG_SYSTEM handler each module's frame set
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
time = os.time
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
function UnitName() return me end
function UnitLevel() return 70 end
function UnitClass() return "Warrior", "WARRIOR" end
function IsInGuild() return true end
function InCombatLockdown() return false end
function GuildRoster() end
function CanGuildPromote() return true end
function CanGuildDemote() return true end
function CanGuildRemove() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1] .. "-Realm", "Rank" .. r[2], r[2], 70, "Warrior", "", "", "", true, 0, r[3] end
end
function GetGuildRosterLastOnline() return nil end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
end
function GuildControlGetNumRanks() return 7 end
function GuildControlGetRankName(i) return "Rank" .. (i - 1) end
-- The protected calls: an addon that calls them is refused by the game. Here, they fail the test.
function GuildUninvite() error("GuildUninvite called") end
function GuildPromote() error("GuildPromote called") end
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."
local secret = {}
function issecretvalue(v) return secret[v] == true end

LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
-- Each receiver gets its own copy, as off a real wire.
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
dofile(ADDON .. "/Modules/BanList.lua")
dofile(ADDON .. "/Modules/BulkActions.lua")
dofile(ADDON .. "/Modules/AltDeparture.lua")
GuildOS.CommSystem.pendingMessages = {}
GuildOS.RecordError = function(_, e) errors[#errors + 1] = tostring(e) end
local CS, SS, AS, BL, BA, AD, RL = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.AltSync, GuildOS.BanList,
  GuildOS.BulkActions, GuildOS.AltDeparture, GuildOS.RosterLog

-- What the dialogs were asked to show, per client.
local shown = {}
function GuildOS:ShowAltRemovedDialog(groups) shown[me].removed[#shown[me].removed + 1] = groups end
function GuildOS:ShowMainLeftDialog(info) shown[me].left[#shown[me].left + 1] = info end

-- ── The clients ─────────────────────────────────────────────────────────
local clients, wire, online = {}, {}, {}
local function newClient(name)
  clients[name] = { db = { settings = { officerMaxRank = 1 }, altLinks = {}, banList = {}, members = {},
                           rosterLog = { events = {} } },
                    acc = {}, seen = {}, count = 0, state = {} }
  shown[name] = { removed = {}, left = {} }
  online[name] = true
end
local function use(name)
  local c = clients[name]
  me = name
  GuildOS.db, GuildOSDB = c.db, c.acc
  SS.seenIds, SS.seenCount = c.seen, c.count
  GuildOS.State.altDeparture, GuildOS.State.bulk = c.state.altDeparture, c.state.bulk
end
local function save()
  local c = clients[me]
  c.count = SS.seenCount
  c.state.altDeparture, c.state.bulk = GuildOS.State.altDeparture, GuildOS.State.bulk
end
CS.SendMessage = function(_, msgType, data, target)
  wire[#wire + 1] = { t = msgType, data = data, from = me, target = target }
end
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
local function runAfters(who)
  use(who)
  while #afters > 0 do
    local fn = table.remove(afters, 1)
    fn()
  end
  save()
end
local function dropAfters() afters = {} end

local K = function(name) return GuildOS:GetPlayerKey(name, "Realm") end
local MAIN, X, Y, SOLO = K("Main"), K("AltX"), K("AltY"), K("Solo")
local function gone(name)
  for i, r in ipairs(ROSTER) do if r[1] == name then table.remove(ROSTER, i) return end end
end

-- The game's guild line, as each client's Roster Log reads it.
local onSystem
local function system(name, msg)
  use(name)
  onSystem(nil, "CHAT_MSG_SYSTEM", msg)
  save()
end

for _, name in ipairs({ "OffA", "OffB", "Mem" }) do newClient(name) end
use("OffA")
SS:On("ban", function(env, sender) BL:OnSync(env, sender) end)
AS:Initialize()
RL:_SetupDetection()
onSystem = handlers[#handlers]
for _, name in ipairs({ "OffA", "OffB", "Mem" }) do as(name, function() AS:_Store(); AS:Rebuild() end) end

-- ── Pure ────────────────────────────────────────────────────────────────
local members = { { key = "a", name = "Bia" }, { key = "b", name = "ana" }, { key = "c", name = "Caio" } }
local others = AD.Others({ "a", "b", "z" }, members, { a = true })
check(#others == 1 and others[1].name == "ana", "the others: on the roster, in the group, not skipped")
local colored = AD.ColoredNames({ { name = "Ana", class = "MAGE" }, { name = "Bo" } })
check(colored:find("|cff", 1, true) and colored:find("Ana|r", 1, true) and colored:find("Bo", 1, true),
  "names in class colour, and plain without a class")

-- ── The group ───────────────────────────────────────────────────────────
as("OffA", function()
  GuildOS:LinkAlt(X, MAIN); GuildOS:LinkAlt(Y, MAIN)
  GuildOS:LinkAlt(K("Alt2"), K("Main2")); GuildOS:LinkAlt(K("Alt3"), K("Main3"))
  GuildOS:LinkAlt(K("AltA"), K("Main4")); GuildOS:LinkAlt(K("AltB"), K("Main4"))
  GuildOS:LinkAlt(K("AltC"), K("Main5"))
end)
flush()
check(clients.OffB.db.altLinks[X] == MAIN and clients.Mem.db.altLinks[Y] == MAIN, "the links reach everybody")

-- ── 1. Nothing while the login settles, nothing in a lockdown ───────────
check(RL._ready == false, "the Roster Log starts unsettled")
system("OffA", "Main-Realm has been kicked out of the guild by OffA.")
runAfters("OffA")   -- RosterLog's settle timer runs here too
check(#shown.OffA.removed == 0, "a removal seen while the login settles asks nothing")
check(RL._ready == true, "settled after the timer")
local locked = "Main-Realm has been kicked out of the guild by OffA. "
secret[locked] = true
system("OffA", locked)
runAfters("OffA")
check(#shown.OffA.removed == 0, "a line in chat lockdown asks nothing")
secret[locked] = nil

-- ── 2. Removed by somebody else, or without alts: nothing ──────────────
system("OffA", "Main-Realm has been kicked out of the guild by OffB.")
runAfters("OffA")
check(#shown.OffA.removed == 0, "only the client of whoever removed them asks")
system("OffA", "Solo-Realm has been kicked out of the guild by OffA.")
runAfters("OffA")
check(#shown.OffA.removed == 0, "a member without alts: no dialog")

-- ── 3. A main with two alts removed: asked, by name, in class colour ───
system("OffB", "Main-Realm has been kicked out of the guild by OffB.")
runAfters("OffB")
check(#shown.OffB.removed == 1, "the officer who removed the main is asked once")
check(#shown.OffA.removed == 0 and #shown.Mem.removed == 0, "nobody else is asked")
local groups = shown.OffB.removed[1]
check(#groups == 1 and groups[1].name == "Main" and #groups[1].others == 2
  and groups[1].others[1].key == X and groups[1].others[2].key == Y, "the two alts, by name")
check(#groups[1].keys == 3 and groups[1].keys[1] == MAIN, "the ban covers the whole group, the main first")
check(AD.ColoredNames(groups[1].others):find("|cff" .. GuildOS:GetClassColorHex("ROGUE") .. "AltX|r", 1, true),
  "each alt in its class colour")

-- "Remove them too": a queue of Bulk actions, nothing removed.
as("OffB", function() check(AD:RemoveOthers(groups), "the alts are queued") end)
use("OffB")
local q = BA:Queue()
check(q and q.action == "remove" and q.list and #q.items == 2 and q.items[1].fullName == "AltX-Realm"
  and q.items[2].fullName == "AltY-Realm", "the two alts, in a removal queue, one per click")
check(BA:Current() and BA:Current().fullName == "AltX-Realm", "the first click is for AltX")
save()

-- "Ban the group, 30 days, note": three bans, one term, one note, synced.
as("OffB", function()
  check(AD:BanGroups(groups, "Scam", 30, "nota x") == 3, "three bans")
end)
local banB = clients.OffB.db.banList
check(banB.main and banB.altx and banB.alty, "the main and both alts are banned")
check(banB.main.expiry == now + 30 * 86400 and banB.altx.expiry == banB.main.expiry and banB.alty.expiry == banB.main.expiry,
  "the same term for the three")
check(banB.altx.note == "nota x" and banB.alty.group == "Main" and banB.main.reason == "Scam", "the same note, the group's mark")
-- The note is the officer's words about a person: never on the guild channel, which every member's client reads.
local function noteOnWire()
  for _, msg in ipairs(wire) do
    local env = store[msg.data]
    local e = type(env) == "table" and env.dom == "ban" and type(env.data) == "table" and env.data.entry
    if type(e) == "table" and e.note ~= nil then return true end
  end
  return false
end
local banWire = 0
for _, msg in ipairs(wire) do
  local env = store[msg.data]
  if type(env) == "table" and env.dom == "ban" then banWire = banWire + 1 end
end
check(banWire == 3 and not noteOnWire(), "three bans on the wire, none with the note")
flush()
local banA, banM = clients.OffA.db.banList, clients.Mem.db.banList
check(banA.altx and banA.alty.group == "Main" and banA.main.expiry == banB.main.expiry,
  "the other officer has the three, the term and the group's mark")
check(banM.altx ~= nil and banM.altx.group == "Main", "the ban list reaches every client, as it always did")
for _, name in ipairs({ "OffA", "Mem" }) do
  for k, e in pairs(clients[name].db.banList) do check(e.note == nil, name .. " never receives the note (" .. k .. ")") end
end
-- A backfill from the officer who wrote it carries no note either.
as("OffB", function() BL:Backfill() end)
check(#wire > 0 and not noteOnWire(), "a backfill sends no note")
flush()
check(clients.Mem.db.banList.altx.note == nil, "still no note on a member's client after a backfill")
-- Another officer edits the ban (a share): the writer keeps their note, nobody else gets it.
as("OffA", function() check(BL:Share("altx", "scam", "alliance words"), "shared") end)
check(not noteOnWire(), "the share's envelope carries no officer note")
flush()
check(clients.OffB.db.banList.altx.note == "nota x" and clients.OffB.db.banList.altx.share ~= nil,
  "the writer's note stays on a ban another officer edited")
check(clients.Mem.db.banList.altx.note == nil, "and the member still has none")
-- `group` is a plain string, which a client before #426 stores unread.
check(type(banB.altx.group) == "string", "the group's mark is a plain string")
-- And its bans, without them, are taken without an error.
as("OffA", function()
  local rev = SS:NextRevision("ban", "solo")
  SS:Publish("ban", "set", { key = "solo", entry = { name = "Solo", reason = "old", author = "OffA", ts = now } }, { rev = rev })
end)
flush()
check(clients.OffB.db.banList.solo and clients.OffB.db.banList.solo.note == nil, "an old client's ban, without a note")
local listed
for _, e in ipairs(as("OffB", function() return BL:List() end)) do if e.key == "solo" then listed = e end end
check(listed and listed.reason == "old" and listed.group == nil, "listed as it came")
-- A permanent group ban, and the term not above 0 is permanent too.
as("OffA", function() check(BL:AddGroup({ K("Main5"), K("AltC") }, "", 0, "") == 2, "two bans") end)
check(clients.OffA.db.banList.main5.expiry == nil and clients.OffA.db.banList.altc.note == nil, "permanent, no note")
as("Mem", function() check(BL:AddGroup({ SOLO }, "x", 1, "y") == 0, "a member bans nobody") end)

-- ── 4. Asked once per group ─────────────────────────────────────────────
system("OffB", "AltX-Realm has been kicked out of the guild by OffB.")
runAfters("OffB")
check(#shown.OffB.removed == 1, "a group already asked about is not asked again")

-- ── 5. Banned and still in the guild ────────────────────────────────────
local still = as("OffA", function() return BL:StillInGuild(BA:Collect(false), BA:Context().meKey) end)
local names = {}
for _, m in ipairs(still) do names[#names + 1] = m.name end
table.sort(names)
check(table.concat(names, ",") == "AltC,AltX,AltY,Main,Main5", "the banned still on the roster: " .. table.concat(names, ","))
as("OffA", function()
  check(BA:StartList("remove", still), "Remove all: a queue")
  check(#BA:Queue().items == #still, "every one of them, one per click")
  local ok, why = BA:StartList("remove", still)
  check(not ok and why == "busy", "a queue still running is never replaced")
  BA:Stop()
end)

-- ── 6. Removed while a queue runs: asked once it is through ────────────
gone("Main"); gone("AltX")
as("OffA", function()
  local list = BA:ListFor({ K("Main2"), K("Main3") })
  check(BA:StartList("remove", list), "a removal queue of two mains")
  local first = BA:Current()
  BA:_Sent(first, "/gremove " .. first.name)
end)
dropAfters()
gone("Main2")
as("OffA", function() BA:Confirm() end)
check(#shown.OffA.removed == 0, "nothing asked while the queue still has a member to click")
as("OffA", function() BA:Skip() end)
check(#shown.OffA.removed == 1, "asked once the queue is through")
local g2 = shown.OffA.removed[1]
check(#g2 == 1 and g2[1].name == "Main2" and #g2[1].others == 1 and g2[1].others[1].key == K("Alt2"),
  "about Main2's alt, never Main3's (Main3 stays)")
dropAfters()

-- ── 7. A main leaves: each officer asked once; "Set A as main" for all ─
for _, name in ipairs({ "OffA", "OffB", "Mem" }) do system(name, "Main4-Realm has left the guild.") end
system("OffA", "Main4-Realm has left the guild.")   -- the same line twice
check(#shown.OffA.left == 1 and #shown.OffB.left == 1, "each officer online is asked once")
check(#shown.Mem.left == 0, "a member is never asked")
local info = shown.OffA.left[1]
check(info.name == "Main4" and #info.others == 2 and info.others[1].key == K("AltA"), "the alts that stay, by name")
check(clients.OffA.db.altLinks[K("AltA")] == K("Main4"), "nothing changed on its own")
as("OffA", function() check(AD:SetNewMain(K("Main4"), K("AltA")), "AltA is the main") end)
flush()
for _, name in ipairs({ "OffA", "OffB", "Mem" }) do
  local l = clients[name].db.altLinks
  check(l[K("AltA")] == nil and l[K("AltB")] == K("AltA") and l[K("Main4")] == K("AltA"),
    "AltA heads the group for " .. name)
end
as("OffB", function()
  local ok, why = AD:SetNewMain(K("Main4"), K("AltB"))
  check(not ok and why == "settled", "the second officer's answer comes too late and changes nothing")
end)
-- "Unlink": the group of a main who left stands alone.
system("OffB", "Main5-Realm has left the guild.")
check(#shown.OffB.left == 1 + 1, "OffB asked about Main5")
as("OffB", function() check(AD:Unlink(K("Main5")), "unlinked") end)
flush()
check(clients.OffA.db.altLinks[K("AltC")] == nil, "AltC stands alone for everybody")
as("OffA", function()
  local ok, why = AD:Unlink(K("Main5"))
  check(not ok and why == "settled", "nothing left to unlink")
end)
-- An alt leaving is only its line in the log.
local before = #shown.OffA.left
system("OffA", "AltB-Realm has left the guild.")
check(#shown.OffA.left == before, "an alt leaving asks nothing")
check(clients.OffA.db.rosterLog.events[#clients.OffA.db.rosterLog.events].target == "AltB", "only its line in the log")

check(#errors == 0, "no error: " .. table.concat(errors, " | "))
print(string.format("alt-departure: %d checks passed", checks))
