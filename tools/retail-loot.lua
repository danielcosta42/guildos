-- Personal loot on retail (issue #183), run against the real Core, Compat, Utils, RaidTracker,
-- LootTracker, LootEquity, ExportImport, Digest and the slash router, under a stubbed retail client
-- on Tol Barad and a stubbed WoW: Forever one.
--
-- Retail has no loot to hand out: each player gets their own item. What comes back is the history.
-- LootTracker records ENCOUNTER_LOOT_RECEIVED, every player's item and not only mine, inside a
-- tracked raid session and only there, into the same history a master-loot award goes to: the
-- player keyed by their own realm, a field the client keeps secret skipping the whole record, a
-- re-fire of the same drop recorded once, and nothing under the loot master's default threshold
-- (Rare). The readers come back with it: equity, the loot and equity exports, `/gos equity`, the
-- digest. Forever records nothing from that event and its master-loot path is what it was.
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
  function UnitName() return "Chehul" end
  function GetNumGuildMembers() return 0 end
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
check(e.playerKey == "Chehul-TolBarad" and e.player == "Chehul", "a name with no realm is on this character's realm")
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
check(#history == 4 and history[1].playerKey == "Bob-TolBarad", "a realm with a space is normalized, as the roster writes it")

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

-- ── 7. Outside the raid, nothing ──────────────────────────────────────
INSTANCE[2], INSTANCE[8] = "party", 2830
RT:CheckZone()
check(RT.trackingActive and RT.endTimer ~= nil, "left the raid: the session waits out its grace")
fire("ENCOUNTER_LOOT_RECEIVED", 2950, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 9, "a dungeon boss during the raid's grace is not the raid's loot")
INSTANCE[2], INSTANCE[8] = "raid", 2912
RT:CheckZone()
GuildOS.db.settings.modules.lootTracker = false
fire("ENCOUNTER_LOOT_RECEIVED", BOSS + 3, 250001, HELM, 1, "Chehul", "DRUID")
check(#history == 9, "the Loot Tracker switched off in Settings records nothing")
GuildOS.db.settings.modules.lootTracker = nil

-- ── 8. The readers ────────────────────────────────────────────────────
check(LT:GetLootCount("Ana-Gallywix") == 3 and #LT:GetPlayerLoot("Chehul-TolBarad") == 2,
  "a member's loot, by key")
local report, total = GuildOS.LootEquity:GetReport()
local rows = {}
for _, r in ipairs(report) do rows[r.name] = r end
check(total == 9 and rows["Ana-Gallywix"].total == 3 and rows["Ana-Azralon"].total == 1 and rows.Chehul.total == 2,
  "equity counts each player, two namesakes apart")
check(rows["Ana-Gallywix"].epics == 3 and rows["Ana-Azralon"].epics == 0, "and their epics")

dofile(ADDON .. "/Modules/ExportImport.lua")
local Ex = GuildOS.Exporter
check(Ex:Has("loot") and Ex:Has("equity") and not Ex:Has("standings"), "the loot and equity exports are on retail; DKP is not")
local csv = Ex:Build("loot", "csv")
check(csv:find("Voidforged Helm", 1, true) and csv:find("Ana-Gallywix", 1, true) and csv:find("The Voidspire", 1, true),
  "the loot export lists the personal items")
check(Ex:Build("equity", "csv"):find("Ana-Gallywix", 1, true), "and the equity export")

dofile(ADDON .. "/Modules/Digest.lua")
GuildOS.Digest:Initialize()
local digest = table.concat(GuildOS.Digest:Build(NOW - 3600), "\n")
check(digest:find("9 item(s) looted", 1, true), "the digest says how many items were looted: " .. digest)

-- The verbs: equity answers; the loot suite still says it is not here.
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
for _, verb in ipairs({ "points", "dkp", "lm", "lootmaster", "wish", "softres", "export standings" }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, verb) and said(NOT_HERE), "/gos " .. verb .. " is still not on retail")
end
printed = {}
SlashCmdList.GUILDOS("help")
check(said("Export roster, attendance or loot"), "the help names the loot export on retail")

-- ── 9. Forever: the event records nothing, the master-loot path is unchanged ─
NOW = 1791000000
load(false)
check(not GuildOS.Client.isRetail and not GuildOS.Client.isAnniversary, "the stub is Forever")
LT, RT = GuildOS.LootTracker, GuildOS.RaidTracker
check(GuildOS:StartModule({ "LootTracker", feature = "lootTracker" }), "the tracker starts on Forever")
check(not listens("ENCOUNTER_LOOT_RECEIVED"), "Forever does not listen for personal loot")
RT:CheckZone()
check(RT.trackingActive, "a Forever raid is tracked")
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
