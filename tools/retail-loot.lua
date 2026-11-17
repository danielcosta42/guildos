-- Personal loot on retail (issue #183), run against the real Core, Compat, Utils, RaidTracker,
-- LootTracker, LootEquity, ExportImport, Digest and the slash router, under a stubbed retail client
-- on Tol Barad and a stubbed WoW: Forever one.
--
-- Retail has no loot to hand out: each player gets their own item. What comes back is the history.
-- LootTracker records ENCOUNTER_LOOT_RECEIVED, every guildmate's item and not only mine, inside a
-- tracked raid session and only there (never elsewhere in its grace, never on another difficulty), into the
-- same history a master-loot award goes to: the player named and keyed by their own realm, a stranger
-- from a pickup raid left out, a field the client keeps secret skipping the whole record, a re-fire of
-- the same drop recorded once, and nothing under the loot master's default threshold (Rare). During
-- the grace, Raid Finder of the same raid adds no snapshot and no boss to the guild's session, and a
-- grace that runs out there, or in another raid, ends the session without a snapshot of that group. The
-- readers come back with it: equity, the loot and equity exports, `/gos equity`, the digest. Forever
-- records nothing from that event, and its master-loot path and its grace are what they were.
--
--   luajit -e 'ADDON="."' tools/retail-loot.lua
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

-- ── A client the files load on, with frames that keep their events ────
local NOW = 1791000000
local printed, frames = {}, {}
local SECRET = setmetatable({}, { __tostring = function() error("a secret value was read") end,
  __concat = function() error("a secret value was joined") end, __eq = function() error("a secret value was compared") end })
-- Items the client has cached, by id: name, quality.
local ITEMS = {
  [250001] = { "Voidforged Helm", 4 },
  [250002] = { "Dreamrift Band", 3 },
  [250003] = { "Shimmering Scale", 2 },
}
local INSTANCE = { "The Voidspire", "raid", 15, "Heroic", 30, 0, true, 2912 }
-- The guild, across connected realms, as retail's roster writes it. Ana is three people.
local ROSTER = { "Chehul-TolBarad", "Ana-TolBarad", "Ana-Gallywix", "Ana-Azralon", "Bob-TolBarad", "Fulano-Azralon" }
-- Who is in my group: me, and a stranger from Raid Finder.
local GROUP = { { "Chehul" }, { "Stranger", "Nemesis" } }
local realSnapshot
local function link(id, name, q)
  return ("|cnIQ%d:|Hitem:%d::::::::90:::::|h[%s]|h|r"):format(q, id, name)
end

local function load(retail)
  printed, frames = {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  function issecretvalue(v) return rawequal(v, SECRET) end
  function CreateFrame()
    local f = { events = {}, scripts = {} }
    function f.RegisterEvent(self, e) self.events[e] = true end
    function f.UnregisterEvent(self, e) self.events[e] = nil end
    function f.SetScript(self, what, fn) self.scripts[what] = fn end
    frames[#frames + 1] = f
    return setmetatable(f, { __index = function() return function() end end })
  end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return NOW end
  time = function() return NOW end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  function GetGuildInfo() return "Jardim Escola", "Officer", 1, "Azralon" end
  function GetRealmName() return "Tol Barad" end
  function GetNormalizedRealmName() return "TolBarad" end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i) return ROSTER[i] end
  function IsInRaid() return true end
  function GetNumGroupMembers() return #GROUP end
  function UnitExists(unit) return GROUP[tonumber(unit:match("%d+") or "")] ~= nil end
  function UnitIsUnit(a, b) return a == b or (b == "player" and a == "raid1") end
  function UnitName(unit)
    local g = unit == "player" and GROUP[1] or GROUP[tonumber(unit:match("%d+") or "")]
    if g then return g[1], g[2] end
  end
  function UnitClass() return "Mage", "MAGE" end
  function UnitIsConnected() return true end
  function GetInstanceInfo() return unpack(INSTANCE) end
  C_Item = { GetItemInfo = function(item)
    local id = tonumber(tostring(item):match("item:(%d+)") or item)
    local it = ITEMS[id]
    if it then return it[1], link(id, it[1], it[2]), it[2] end
  end }
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return true end
  GuildOS.db = { settings = { modules = {} }, members = {},
                 raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  dofile(ADDON .. "/Modules/LootTracker.lua")
  dofile(ADDON .. "/Modules/LootEquity.lua")
  realSnapshot = GuildOS.RaidTracker.TakeSnapshot
  GuildOS.RaidTracker.TakeSnapshot = function() end
end

local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function listens(event)
  for _, f in ipairs(frames) do
    if f.events[event] then return true end
  end
  return false
end
local function said(text)
  return table.concat(printed, "\n"):find(text, 1, true) ~= nil
end

local HELM, BAND, SCALE = link(250001, "Voidforged Helm", 4), link(250002, "Dreamrift Band", 3),
  link(250003, "Shimmering Scale", 2)
local BOSS = 3176

-- ── 1. Retail: the tracker is here and listens ────────────────────────
load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
local LT, RT = GuildOS.LootTracker, GuildOS.RaidTracker
check(LT ~= nil and GuildOS.LootEquity ~= nil, "LootTracker and LootEquity are on retail (issue #183)")
check(GuildOS:StartModule({ "LootTracker", feature = "lootTracker" }), "the tracker starts on retail")
check(listens("ENCOUNTER_LOOT_RECEIVED"), "it listens for the loot of a boss")
local history = GuildOS.db.lootHistory
check(type(history) == "table" and #history == 0, "the history starts empty")

-- ── 2. Only inside a tracked raid session ─────────────────────────────
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 0, "no session, nothing recorded")
INSTANCE[3] = 17   -- Raid Finder is not tracked
RT:CheckZone()
check(not RT.trackingActive, "Raid Finder opens no session")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 0, "Raid Finder loot is not recorded")
INSTANCE[3] = 15
RT:CheckZone()
check(RT.trackingActive and RT.currentRaid.instanceID == 2912, "a Heroic night opens a session")

-- ── 3. Every player's item, keyed by their own realm ──────────────────
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 1, "my item is recorded")
local e = history[1]
check(e.playerKey == "Chehul-TolBarad" and e.player == "Chehul-TolBarad",
  "a name with no realm is on this character's realm, and is named with it")
check(e.itemLink == HELM and e.itemId == 250001 and e.itemName == "Voidforged Helm" and e.quality == 4,
  "the item: link, id, name and quality")
check(e.timestamp == NOW and e.raid == "The Voidspire" and e.instanceID == 2912 and e.encounterID == BOSS and e.count == 1,
  "when, which raid and which boss")
check(e.fromML == nil, "a personal item is not a master-loot award")

fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Ana-Gallywix", "MAGE")
check(#history == 2 and history[1].playerKey == "Ana-Gallywix" and history[1].player == "Ana-Gallywix",
  "another player's item, keyed by their own realm")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250002, BAND, 1, "Ana-Azralon", "PRIEST")
check(#history == 3 and history[1].playerKey == "Ana-Azralon", "a namesake on another connected realm is someone else")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250002, BAND, 1, "Bob-Tol Barad", "WARRIOR")
check(#history == 4 and history[1].playerKey == "Bob-TolBarad" and history[1].player == "Bob-TolBarad",
  "a realm with a space is normalized, as the roster writes it")

-- ── 3b. Only the guild: a pickup raid's strangers stay out ────────────
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Stranger-Nemesis", "MAGE")
check(#history == 4, "a stranger's item is not the guild's")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Ana-Nemesis", "MAGE")
check(#history == 4, "nor a namesake of three guildmates from a realm the guild is not on")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Fulano", "WARRIOR")
check(#history == 4, "nor a name with no realm that nobody on this realm carries")

-- ── 4. A re-fire of the same drop is one record ───────────────────────
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Ana-Gallywix", "MAGE")
check(#history == 4, "the same boss, item and player again is a re-fire")
NOW = NOW + 30
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Ana-Gallywix", "MAGE")
check(#history == 4, "still a re-fire half a minute later")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 1, 250001, HELM, 1, "Ana-Gallywix", "MAGE")
check(#history == 5 and history[1].encounterID == BOSS + 1, "the same item from the next boss is another drop")
NOW = NOW + 600
fire("ENCOUNTER_LOOT_RECEIVED", BOSS, 250001, HELM, 1, "Ana-Gallywix", "MAGE")
check(#history == 6, "long after, it is another drop")

-- ── 5. A secret field skips the whole record ──────────────────────────
local ARGS = { BOSS + 2, 250001, HELM, 1, "Fulano-Azralon", "WARRIOR" }
for i = 1, #ARGS do
  local args = { unpack(ARGS) }
  args[i] = SECRET
  local ok, err = pcall(fire, "ENCOUNTER_LOOT_RECEIVED", unpack(args, 1, #ARGS))
  check(ok, "a secret in field " .. i .. " does not raise: " .. tostring(err))
  check(#history == 6, "a secret in field " .. i .. " stores nothing, not half a record")
end
fire("ENCOUNTER_LOOT_RECEIVED", unpack(ARGS))
check(#history == 7 and history[1].playerKey == "Fulano-Azralon", "the same item with nothing secret is recorded")

-- ── 6. Only what is worth recording: Rare and up ──────────────────────
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 2, 250003, SCALE, 5, "Fulano-Azralon", "WARRIOR")
check(#history == 7, "an Uncommon item is not recorded")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 2, 250002, BAND, 1, "Fulano-Azralon", "WARRIOR")
check(#history == 8 and history[1].quality == 3, "a Rare one is")
-- Not cached yet: the quality the link carries.
local UNCACHED_EPIC, UNCACHED_GREEN = link(260001, "Crown of the Void", 4), link(260002, "Void Dust", 2)
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 2, 260001, UNCACHED_EPIC, 1, "Chehul", "DRUID")
check(#history == 9 and history[1].quality == 4 and history[1].itemName == "Crown of the Void",
  "an item not cached yet is read from its link: quality and name")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 2, 260002, UNCACHED_GREEN, 3, "Chehul", "DRUID")
check(#history == 9, "and an Uncommon one in the link is still not recorded")
local PLAIN = "|cffa335ee|Hitem:270001::::::::90:::::|h[Sigil of the Void]|h|r"   -- the older colour, no quality tag
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 2, 270001, PLAIN, 1, "Chehul", "DRUID")
check(#history == 10 and history[1].quality == 4 and history[1].itemName == "Sigil of the Void",
  "an item neither cached nor tagged is a boss's epic, as an ML award assumes")

-- ── 7. Outside the raid, in its grace or on another difficulty, nothing ─
local function inside(kind, difficulty, id) INSTANCE[2], INSTANCE[3], INSTANCE[8] = kind, difficulty, id end
local function snapshots() return #RT.currentRaid.snapshots end
local function encounters() return #RT.currentRaid.encounters end
local heroic = RT.currentRaid
-- A pull the Heroic left open (a disconnect mid-fight): no kill in another instance may close it.
RT:OnEncounterStart(BOSS + 5, "Imperator")
local openPull = heroic.encounters[#heroic.encounters]
inside("party", 1, 2830)
RT:CheckZone()
check(RT.trackingActive and RT.endTimer ~= nil, "left the raid: the session waits out its grace")
fire("ENCOUNTER_LOOT_RECEIVED", 2950, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 10, "a dungeon boss during the raid's grace is not the raid's loot")
-- The review's night: out of the guild's Heroic, then Raid Finder of the same raid in its grace.
inside("raid", 17, 2912)
RT:CheckZone()
check(RT.currentRaid == heroic and RT.endTimer ~= nil, "Raid Finder of the same raid leaves the Heroic session in its grace")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 3, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 10, "Raid Finder's loot is not the Heroic session's")
local before, bosses = snapshots(), encounters()
realSnapshot(RT, "roster_change")
RT:OnEncounterStart(BOSS + 3, "Imperator")
RT:OnEncounterEnd(BOSS + 3, "Imperator", 1)
RT:OnEncounterEnd(BOSS + 5, "Imperator", 1)
check(snapshots() == before and encounters() == bosses and not heroic.players["Stranger-Nemesis"],
  "nor its group, nor its bosses")
check(openPull.id == BOSS + 5 and openPull.success == nil and openPull.endTime == nil,
  "and a Raid Finder kill does not close the Heroic's open pull")
-- In the grace but standing in the session's raid on its difficulty (the zone change missed): the
-- session's, as its snapshots and bosses are.
inside("raid", 15, 2912)
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 6, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 11 and history[1].encounterID == BOSS + 6, "in its grace, the session's own raid still records")
-- The open world is the run-back: the group is still the raid's.
inside("none", 0, 0)
before = snapshots()
realSnapshot(RT, "roster_change")
check(snapshots() == before + 1, "a snapshot on the run-back is kept, as before")
-- Back in, then on another difficulty with no grace pending:
inside("raid", 15, 2912)
RT:CheckZone()
check(RT.currentRaid == heroic and RT.endTimer == nil, "back in: the Heroic session resumes")
INSTANCE[3] = 17
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 3, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 11, "another difficulty of the same raid is not the session's, grace or no grace")
INSTANCE[3] = 15
GuildOS.db.settings.modules.lootTracker = false
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 3, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 11, "the Loot Tracker switched off in Settings records nothing")
GuildOS.db.settings.modules.lootTracker = nil
before = snapshots()
realSnapshot(RT, "roster_change")
check(snapshots() == before + 1 and heroic.players["Stranger-Nemesis"], "in the raid, the group is the session's")

-- ── 8. The readers ────────────────────────────────────────────────────
check(LT:GetLootCount("Ana-Gallywix") == 3 and #LT:GetPlayerLoot("Chehul-TolBarad") == 4,
  "a member's loot, by key")
local report, total = GuildOS.LootEquity:GetReport()
local rows = {}
for _, r in ipairs(report) do rows[r.name] = r end
check(total == 11 and rows["Ana-Gallywix"].total == 3 and rows["Ana-Azralon"].total == 1
  and rows["Chehul-TolBarad"].total == 4, "equity counts each player, two namesakes apart")
check(rows["Ana-Gallywix"].epics == 3 and rows["Ana-Azralon"].epics == 0, "and their epics")

dofile(ADDON .. "/Modules/ExportImport.lua")
local Ex = GuildOS.Exporter
check(Ex:Has("loot") and Ex:Has("equity"), "the loot and equity exports are on retail")
local csv = Ex:Build("loot", "csv")
check(csv:find("Voidforged Helm", 1, true) and csv:find("Ana-Gallywix", 1, true) and csv:find("The Voidspire", 1, true),
  "the loot export lists the personal items")
check(Ex:Build("equity", "csv"):find("Ana-Gallywix", 1, true), "and the equity export")

dofile(ADDON .. "/Modules/Digest.lua")
GuildOS.Digest:Initialize()
local digest = table.concat(GuildOS.Digest:Build(NOW - 3600), "\n")
check(digest:find("11 item(s) looted", 1, true), "the digest says how many items were looted: " .. digest)

-- The verbs: equity answers; the loot master and soft reserves still say they are not here (points and
-- the wishlist are retail's since issue #185: tools/retail-points.lua, tools/retail-wishlist.lua).
dofile(ADDON .. "/Core/Commands.lua")
GuildOS.ShowExportPopup = function() end
local NOT_HERE = "Not available on this client."
for _, verb in ipairs({ "equity", "lootequity" }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, verb), "/gos " .. verb .. " does not raise on retail")
  check(not said(NOT_HERE) and said("Loot equity"), "/gos " .. verb .. " prints the equity on retail")
end
for _, verb in ipairs({ "export loot", "export equity" }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, verb) and not said(NOT_HERE), "/gos " .. verb .. " exports on retail")
end
for _, verb in ipairs({ "lm", "lootmaster", "softres" }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, verb) and said(NOT_HERE), "/gos " .. verb .. " is still not on retail")
end
printed = {}
SlashCmdList.GUILDOS("help")
check(said("Export roster, attendance or loot"), "the help names the loot export on retail")

-- ── 8b. Another character on a connected realm names "Ana" another Ana ─
-- An alt on Gallywix in the same guild: its "Ana" is Ana-Gallywix, where Chehul's was Ana-TolBarad.
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 4, 250001, HELM, 1, "Ana", "MAGE")
function GetRealmName() return "Gallywix" end
function GetNormalizedRealmName() return "Gallywix" end
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 4, 250002, BAND, 1, "Ana", "PRIEST")
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 4, 250001, HELM, 1, "Bob-TolBarad", "WARRIOR")
check(history[3].player == "Ana-TolBarad" and history[2].player == "Ana-Gallywix" and history[1].player == "Bob-TolBarad",
  "every item is named with its player's realm, whichever character recorded it")
report = GuildOS.LootEquity:GetReport()
rows = {}
for _, r in ipairs(report) do rows[r.name] = r end
check(rows["Ana-TolBarad"].total == 1 and rows["Ana-Gallywix"].total == 4 and rows["Bob-TolBarad"].total == 2
  and rows.Ana == nil and rows.Bob == nil, "so /gos equity neither merges namesakes nor splits a person")
function GetRealmName() return "Tol Barad" end
function GetNormalizedRealmName() return "TolBarad" end

-- ── 8c. A grace that runs out where the session is not ───────────────
RT.TakeSnapshot = realSnapshot
local fireTimer
C_Timer.NewTimer = function(_, fn) fireTimer = fn; return { Cancel = function() end } end
local GUILD = { { "Chehul" }, { "Ana", "Gallywix" }, { "Fulano", "Azralon" } }
local PUG = { { "Chehul" }, { "Stranger", "Nemesis" }, { "Other", "Nemesis" } }
local function setGroup(g) for i = 1, math.max(#GROUP, #g) do GROUP[i] = g[i] end end
local function lastSnap(session) return session.snapshots[#session.snapshots] end
local function guildNight()
  setGroup(GUILD)
  inside("raid", 15, 2912)
  RT:CheckZone()
  local night = RT.currentRaid
  NOW = NOW + 3600
  inside("none", 0, 0)
  RT:CheckZone()
  return night
end
-- The night in progress ends on the run-back, in the open world: its last snapshot is taken, as before.
local night = RT.currentRaid
inside("none", 0, 0)
RT:CheckZone()
NOW = NOW + 1200
fireTimer()
check(not RT.trackingActive and lastSnap(night).reason == "session_end", "a grace ending in the open world snapshots the group")
-- Out of the guild's Heroic into Raid Finder of the same raid, and the twenty minutes run out there.
night = guildNight()
inside("raid", 17, 2912)
RT:CheckZone()
setGroup(PUG)
NOW = NOW + 1200
fireTimer()
check(not RT.trackingActive and lastSnap(night).reason ~= "session_end" and not night.players["Stranger-Nemesis"],
  "a grace running out in Raid Finder takes no snapshot of Raid Finder's group")
-- Out of the guild's Heroic into another raid with a pickup group, inside the grace.
night = guildNight()
setGroup(PUG)
INSTANCE[1] = "The Dreamrift"
inside("raid", 14, 2939)
RT:CheckZone()
check(RT.currentRaid ~= night and RT.currentRaid.instanceID == 2939, "another raid ends the old session and starts its own")
check(lastSnap(night).reason ~= "session_end" and not night.players["Stranger-Nemesis"],
  "and the old session's last snapshot is not the pickup group")
INSTANCE[1] = "The Voidspire"
setGroup(GUILD)

-- ── 9. Forever: the event records nothing, the master-loot path is unchanged ─
NOW = 1791000000
load(false)
check(not GuildOS.Client.isRetail and not GuildOS.Client.isAnniversary, "the stub is Forever")
LT, RT = GuildOS.LootTracker, GuildOS.RaidTracker
check(GuildOS:StartModule({ "LootTracker", feature = "lootTracker" }), "the tracker starts on Forever")
check(not listens("ENCOUNTER_LOOT_RECEIVED"), "Forever does not listen for personal loot")
RT:CheckZone()
check(RT.trackingActive, "a Forever raid is tracked")
inside("party", 1, 2830)
RT:CheckZone()
local fsnaps = #RT.currentRaid.snapshots
realSnapshot(RT, "roster_change")
check(RT.endTimer ~= nil and #RT.currentRaid.snapshots == fsnaps + 1, "Forever still snapshots a group in the grace, anywhere")
do
  local fire2
  local realTimer = C_Timer.NewTimer
  C_Timer.NewTimer = function(_, fn) fire2 = fn; return { Cancel = function() end } end
  RT.endTimer = nil
  RT:CheckZone()
  local fnight = RT.currentRaid
  RT.TakeSnapshot = realSnapshot
  NOW = NOW + 1800
  fire2()
  check(not RT.trackingActive and fnight.snapshots[#fnight.snapshots].reason == "session_end",
    "and a Forever grace running out in another instance ends with its snapshot, as before")
  RT.TakeSnapshot = function() end
  C_Timer.NewTimer = realTimer
end
inside("raid", 15, 2912)
RT:CheckZone()
LT:OnEncounterLoot(BOSS, 250001, HELM, 1, "Chehul", "DRUID")
check(#GuildOS.db.lootHistory == 0, "and personal loot is never recorded there, even called by hand")
local award = { itemLink = HELM, itemName = "Voidforged Helm", quality = 4, player = "Ana", playerKey = "Ana",
  count = 1, timestamp = NOW, raid = "The Voidspire", instanceID = 2912, fromML = true }
LT:RecordMLAward(award)
check(GuildOS.db.lootHistory[1] == award, "a master-loot award is stored as given, at the front")
for i = 1, 500 do LT:RecordMLAward({ n = i }) end
check(#GuildOS.db.lootHistory == 500 and GuildOS.db.lootHistory[1].n == 500 and GuildOS.db.lootHistory[500].n == 1,
  "the history keeps its newest 500")

print(("retail-loot: %d checks passed"):format(checks))
