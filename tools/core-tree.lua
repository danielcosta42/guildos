-- Elenco e grupos in the game (issue #352; guildos-web specs/086), run against the real Core, Compat,
-- Utils, CoreManager, RaidTracker and Points under a stubbed client.
--
-- A core of the GOSCORE1 can have one parent, its elenco (`parent`, the elenco's tag) and say where its
-- points go (`pool`: "own", the default, or "parent").
--   * the import keeps both on the core, by tag, so the elenco is whichever core holds that tag here
--     (renamed, arriving later); a package from before them is no elenco and the group's own pool;
--   * a raid night goes to the group whose people are in the raid, though the elenco's roster has them
--     too; an elenco keeps a night bigger than its groups, and one where two of its groups tie;
--   * a group with the elenco's pool earns and is charged in the elenco's pool, and tells the other
--     officers so; one with its own pool, as always.
--
--   luajit -e 'ADDON="."' tools/core-tree.lua
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

local printed, sent, handlers, GROUP, NOW = {}, {}, {}, {}, 1790000000
local INSTANCE = { "Karazhan", "raid", 3, "", 10, 0, false, 532 }
local function load(game)
  printed, sent, handlers, GROUP, NOW = {}, {}, {}, {}, 1790000000
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    function f:Hide() end
    function f:Show() end
    return f
  end
  function hooksecurefunc() end
  C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Lead", "Er" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Leader" end
  end
  function GetRealmName() return "Firemaw" end
  function GetTime() return 1 end
  function GetServerTime() return NOW end
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return "Nucleo BR", "Rank", 1 end
  function GetNumGuildMembers() return 0 end
  function GetGuildRosterInfo() end
  function IsInRaid() return true end
  function GetInstanceInfo() return unpack(INSTANCE) end
  function GetNumGroupMembers() return #GROUP end
  function UnitExists(u) return u == "player" or GROUP[tonumber(u:match("%d+") or "")] ~= nil end
  function UnitIsConnected() return true end
  function UnitClass() return "Mage", "MAGE" end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.db = { settings = { companion = true, officerMaxRank = 1 }, members = {}, altLinks = {}, cores = {},
                 raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" },
                 points = { mode = "dkp", config = {}, standings = {}, log = {}, appliedOps = {}, appliedCount = 0 } }
  dofile(ADDON .. "/Modules/CoreManager.lua")
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  dofile(ADDON .. "/Modules/Points.lua")
  GuildOS.SyncService = {
    On = function(_, domain, fn) handlers[domain] = fn end,
    Publish = function(_, domain, act, data) sent[#sent + 1] = { domain = domain, act = act, data = data } end,
    NextRevision = function() return 1 end,
  }
  GuildOS.IsOfficerByName = function() return true end
  local RT = GuildOS.RaidTracker
  RT.currentGroupTag = ""
  RT.CheckPlayerConsumes = function() return false end
  RT.BroadcastRaidData = function() end
  GuildOS.Compat.IsPlayer = function(u) return u == "player" end
  GuildOS.Compat.UnitIdentity = function(u) return GROUP[tonumber(u:match("%d+") or "")], nil, "MAGE" end
  GuildOS.Compat.PlayerName = function() return game == "forever" and "Lead Er" or "Leader" end
  GuildOS.LootMaster = { LoadCfg = function() end }
  GuildOS.CoreManager:Initialize()
  GuildOS.Points:Initialize()
  return GuildOS.CoreManager, RT, GuildOS.Points
end

local function key(name) return GuildOS:GetPlayerKey(name, "Firemaw") end
local function people(names, slot)
  local out = {}
  for _, n in ipairs(names) do out[#out + 1] = { key = n .. "-Firemaw", name = n, class = "MAGE", slot = slot or "rdps" } end
  return out
end
local function names(prefix, from, to)
  local out = {}
  for i = from, to do out[#out + 1] = prefix .. i end
  return out
end
local function concat(...)
  local out = {}
  for _, t in ipairs({ ... }) do for _, v in ipairs(t) do out[#out + 1] = v end end
  return out
end
local function package(cores) return { guild = "Nucleo BR", realm = "Firemaw", unlinked = 0, at = NOW, cores = cores } end
local function group(list) GROUP = {}; for i, n in ipairs(list) do GROUP[i] = n end end
local function snapshot(list)
  local m = {}
  for _, n in ipairs(list) do m[key(n)] = true end
  return m
end

-- The elenco (a 25, or a 20 on Forever) and its two groups of 10, with all of both groups on it.
local A, B, SUBS = names("Aa", 1, 10), names("Bb", 1, 10), names("Sub", 1, 5)
local function tree(game, over)
  over = over or {}
  local big = game == "forever" and 20 or 25
  return package({
    { tag = "elenco", name = "Elenco", size = big, members = people(concat(A, B, SUBS)) },
    { tag = "kara-a", name = "Kara A", size = 10, members = people(A), parent = over.parentA or "elenco", pool = over.poolA },
    { tag = "kara-b", name = "Kara B", size = 10, members = people(B), parent = "elenco", pool = over.poolB or "parent" },
  })
end

for _, game in ipairs({ "anniversary", "forever" }) do
  local function G(what) return game .. ": " .. what end

  -- ── The import keeps the elenco and the pool ──────────────────────────
  local CM, RT, P = load(game)
  CM:ImportFromSite(tree(game))
  check(GuildOS.db.cores["Kara A"] and GuildOS.db.cores["Kara A"].discordParent == "elenco", G("a group keeps its elenco's tag"))
  check(CM:ParentOf("Kara A") == "Elenco" and CM:ParentOf("Kara B") == "Elenco", G("and the elenco is the core holding it here"))
  check(CM:ParentOf("Elenco") == nil, G("an elenco has no elenco"))
  check(GuildOS.db.cores["Kara A"].pointsPool == nil and not CM:UsesParentPool("Kara A"), G("no `pool` is the group's own"))
  check(GuildOS.db.cores["Kara B"].pointsPool == "parent" and CM:UsesParentPool("Kara B"), G("`pool` parent is the elenco's"))
  check(CM:PoolOwner("Kara A") == "Kara A" and CM:PoolOwner("Kara B") == "Elenco" and CM:PoolOwner("Elenco") == "Elenco",
    G("whose pool each one's points are"))
  local groups = CM:GroupsOf("Elenco")
  check(#groups == 2 and groups[1] == "Kara A" and groups[2] == "Kara B", G("the elenco's groups, by name"))
  local list = CM:SortedTree()
  check(#list == 3 and list[1].name == "Elenco" and list[1].depth == 0 and list[2].name == "Kara A" and list[2].depth == 1
    and list[3].name == "Kara B" and list[3].depth == 1, G("the cores screen lists the groups under their elenco"))

  -- The other officers hear it with the list, and a list that says it sets it there.
  sent = {}
  GuildOS.State.discordCores = nil
  CM:ImportPackage(tree(game, { poolA = "own" }), NOW)
  CM:SendDiscordChanges()
  local told
  for _, m in ipairs(sent) do if m.act == "discordList" and m.data.tag == "kara-b" then told = m.data end end
  check(told and told.parent == "elenco" and told.pool == "parent", G("the list sent to the other officers carries the elenco and pool"))

  -- A package from before #352: no elenco, the group's own pool.
  CM = load(game)
  local old = tree(game)
  for _, c in ipairs(old.cores) do c.parent, c.pool = nil, nil end
  CM:ImportFromSite(old)
  check(CM:ParentOf("Kara A") == nil and CM:PoolOwner("Kara B") == "Kara B" and GuildOS.db.cores["Kara B"].discordParent == nil,
    G("a package without the fields is no elenco and the own pool"))
  check(#CM:SortedTree() == 3 and CM:SortedTree()[1].depth == 0 and CM:SortedTree()[3].depth == 0, G("listed as always, by name"))
  -- And a later package that says it now sets it; one that stops saying it takes it away.
  CM:ImportFromSite(tree(game))
  check(CM:ParentOf("Kara B") == "Elenco" and CM:PoolOwner("Kara B") == "Elenco", G("a later package with the fields sets them"))
  CM:ImportFromSite(old)
  check(CM:ParentOf("Kara B") == nil and GuildOS.db.cores["Kara B"].pointsPool == nil, G("and one without them takes them away"))
  -- An officer's client from before #352 sends the list without them: what this client has stays.
  CM:ImportFromSite(tree(game))
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Kara B", list = people(B), tag = "kara-b", size = 10, at = NOW + 1 } },
    "Officer-Firemaw")
  check(CM:ParentOf("Kara B") == "Elenco" and CM:UsesParentPool("Kara B"), G("a list from a client from before leaves the elenco alone"))
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Kara B", list = people(B), tag = "kara-b", size = 10, at = NOW + 2,
    parent = "", pool = "own" } }, "Officer-Firemaw")
  check(CM:ParentOf("Kara B") == nil and not CM:UsesParentPool("Kara B"), G("one that says none takes it away"))

  -- Odd fields: a parent that is the core itself, of another type, too long; a pool that is no word.
  CM = load(game)
  CM:ImportFromSite(package({
    { tag = "solo", name = "Solo", size = 10, members = people(A), parent = "solo", pool = "parent" },
    { tag = "num", name = "Num", size = 10, members = people(B), parent = 7, pool = "parent" },
    { tag = "long", name = "Long", size = 10, members = people(SUBS), parent = string.rep("x", 65), pool = "weird" },
  }))
  check(CM:ParentOf("Solo") == nil and CM:ParentOf("Num") == nil and CM:ParentOf("Long") == nil
    and GuildOS.db.cores["Solo"].pointsPool == nil and GuildOS.db.cores["Num"].pointsPool == nil,
    G("a parent that is itself, no string or too long is none, and so is its pool"))

  -- An elenco this client does not have yet: none until it arrives, by tag; renamed, still the one.
  CM = load(game)
  local orphan = tree(game)
  table.remove(orphan.cores, 1)
  CM:ImportFromSite(orphan)
  check(GuildOS.db.cores["Kara B"].discordParent == "elenco" and CM:ParentOf("Kara B") == nil and CM:PoolOwner("Kara B") == "Kara B",
    G("an unknown elenco is none, and the pool the group's own, until it arrives"))
  check(CM:SortedTree()[1].depth == 0 and CM:SortedTree()[2].depth == 0, G("listed at the top meanwhile"))
  CM:ImportFromSite(tree(game))
  check(CM:ParentOf("Kara B") == "Elenco" and CM:PoolOwner("Kara B") == "Elenco", G("once it arrives it is the elenco"))
  local renamed = tree(game)
  renamed.cores[1].name = "Elenco TBC"
  CM:ImportFromSite(renamed)
  check(GuildOS.db.cores["Elenco TBC"] and CM:ParentOf("Kara B") == "Elenco TBC" and CM:PoolOwner("Kara B") == "Elenco TBC",
    G("the elenco renamed on Discord is still the group's elenco"))
  -- A cycle (never what the site sends) ends: no walk loops, every core is listed once.
  local cycle = tree(game)
  cycle.cores[1].parent, cycle.cores[1].pool = "kara-a", "parent"
  cycle.cores[2].pool = "parent"
  CM:ImportFromSite(cycle)
  check(#CM:SortedTree() == 3 and type(CM:PoolOwner("Kara A")) == "string", G("a cycle neither loops nor drops a core"))

  -- ── A raid night goes to the group whose people are in it ─────────────
  CM, RT = load(game)
  CM:ImportFromSite(tree(game))
  INSTANCE = { "Karazhan", "raid", 3, "", 10, 0, false, 532 }
  local me = GuildOS.Compat.PlayerName()
  group(A)
  check(CM:CoreForGroup(snapshot(A), 10) == "Kara A", G("Kara A's ten are Kara A's night, though the elenco has them all"))
  local withSub = { A[1], A[2], A[3], A[4], A[5], A[6], A[7], SUBS[1], SUBS[2], SUBS[3] }
  check(CM:CoreForGroup(snapshot(withSub), 10) == "Kara A", G("with subs from the elenco, still the group's: " ..
    tostring(CM:CoreForGroup(snapshot(withSub), 10))))
  check(CM:CoreForGroup(snapshot(B), 10) == "Kara B", G("Kara B's are Kara B's"))
  -- Equal formats (a group sized as its elenco): the elenco's roster, larger, used to win or tie.
  GuildOS.db.cores["Elenco"].raidSize = 10
  check(CM:CoreForGroup(snapshot(withSub), 10) == "Kara A", G("an elenco of the group's own size steps aside too"))
  check(CM:CoreForGroup(snapshot(A)) == "Kara A", G("and with no size from the instance"))
  GuildOS.db.cores["Elenco"].raidSize = game == "forever" and 20 or 25
  -- Half of each group: no group is the night, the elenco is.
  local mixed = { A[1], A[2], A[3], A[4], A[5], B[1], B[2], B[3], B[4], B[5] }
  check(CM:CoreForGroup(snapshot(mixed), 10) == "Elenco", G("two groups tied: the night is the elenco's"))
  -- The elenco's own night: bigger than its groups, it keeps it.
  local big = game == "forever" and 20 or 25
  local full = concat(A, B, SUBS)
  while #full > big do table.remove(full) end
  check(CM:CoreForGroup(snapshot(full), big) == "Elenco", G("a night of the elenco's format is the elenco's"))
  -- And through the tracker: the session, and so the attendance, is the group's.
  group(withSub)
  RT:SetGroupTag("Elenco")
  RT:StartSession(532)
  check(RT.currentRaid.groupTag == "Kara A" and CM:GetActiveName() == "Kara A", G("the raid's session is the group's"))
  RT:OnEncounterStart(1, "Attumen")
  check(RT.currentRaid.groupTag == "Kara A", G("and the pull settles it there"))
  RT.currentRaid, RT.trackingActive = nil, nil

  -- Cores with no elenco and no groups: as always, a tie is no core.
  CM = load(game)
  CM:ImportFromSite(package({
    { tag = "x", name = "X", size = 10, members = people(concat(A, B)) },
    { tag = "y", name = "Y", size = 10, members = people(A) },
  }))
  check(CM:CoreForGroup(snapshot(A), 10) == nil, G("two loose cores holding the same people still tie, as before"))
  check(CM:CoreForGroup(snapshot(B), 10) == "X", G("and the one that has the raid is it"))

  -- ── Points: a group with the elenco's pool earns in it ───────────────
  local P
  CM, RT, P = load(game)
  CM:ImportFromSite(tree(game))
  local ana, bia = key(A[1]), key(B[1])
  RT:SetGroupTag("Kara B")                                   -- pool "parent"
  sent = {}
  local e = P:Award(bia, 30, "Boss")
  check(e and e.core == "Elenco", G("the entry of a group with the elenco's pool names the elenco: " .. tostring(e and e.core)))
  local elenco, karaB = GuildOS.db.cores["Elenco"].points, GuildOS.db.cores["Kara B"].points
  check(elenco.standings[bia] and elenco.standings[bia].current == 30, G("and lands in the elenco's pool"))
  check(not karaB.standings[bia], G("not in the group's own"))
  check(P:Get(bia) == 30, G("the group reads the elenco's standings"))
  local delta
  for _, m in ipairs(sent) do if m.domain == "points" and m.act == "delta" then delta = m.data.entries[1] end end
  check(delta and delta.core == "Elenco", G("the other officers are told the elenco's pool"))
  P:Charge(bia, 10, "Item")
  check(elenco.standings[bia].current == 20, G("a charge comes off the elenco's pool too"))
  -- Under the group's name (an item announced in it, LootMaster's InCore) it is the elenco's too.
  P:InCore("Kara B", function() P:Award(bia, 5, "Late") end)
  check(elenco.standings[bia].current == 25 and not karaB.standings[bia], G("InCore with the group's name is the elenco's pool"))
  -- An officer whose client does not know the pool yet names the group: it lands in the elenco's here.
  handlers["points"]({ act = "delta", data = { entries = { { op = "far-1", key = bia, delta = 7, core = "Kara B", kind = "award" } } } },
    "Officer-Firemaw")
  check(elenco.standings[bia].current == 32 and not karaB.standings[bia], G("another officer's entry named for the group lands in the elenco's"))
  -- And the group's own pool from such a client never writes over the elenco's.
  GuildOS.SyncService.ShouldApply = function() return true end
  GuildOS.SyncService.SetRevision = function() end
  handlers["points"]({ act = "snapshot", rev = 9, data = { core = "Kara B", mode = "dkp", config = {}, standings = { [bia] = { current = 1 } } } },
    "Officer-Firemaw")
  check(elenco.standings[bia].current == 32, G("a snapshot of the group's own pool leaves the elenco's alone"))
  sent = {}
  P:BroadcastSnapshot("Kara B")
  check(sent[1] and sent[1].data.core == "Elenco", G("the group's snapshot is told as the elenco's"))

  -- A group with its own pool: as always.
  RT:SetGroupTag("Kara A")
  e = P:Award(ana, 40, "Boss")
  local karaA = GuildOS.db.cores["Kara A"].points
  check(e and e.core == "Kara A" and karaA.standings[ana].current == 40 and not elenco.standings[ana],
    G("a group with its own pool earns in its own"))
  -- No core at all: the guild's pool, as always.
  RT:SetGroupTag("")
  e = P:Award(ana, 3, "Boss")
  check(e and e.core == "" and GuildOS.db.points.standings[ana].current == 3, G("no core is the guild's pool"))
  -- The elenco not here (yet): the group's own pool, until it arrives.
  CM, RT, P = load(game)
  local alone = tree(game)
  table.remove(alone.cores, 1)
  CM:ImportFromSite(alone)
  RT:SetGroupTag("Kara B")
  e = P:Award(bia, 11, "Boss")
  check(e and e.core == "Kara B" and GuildOS.db.cores["Kara B"].points.standings[bia].current == 11,
    G("with the elenco unknown here the group's points stay in its own pool"))
  -- An entry naming the group by its Discord tag (CoreNamed) reaches the elenco's pool too.
  CM:ImportFromSite(tree(game))
  handlers["points"]({ act = "delta", data = { entries = { { op = "far-2", key = bia, delta = 4, core = "kara-b", kind = "award" } } } },
    "Officer-Firemaw")
  check(GuildOS.db.cores["Elenco"].points.standings[bia] and GuildOS.db.cores["Elenco"].points.standings[bia].current == 4,
    G("an entry naming the group by its tag reaches the elenco's pool"))
end

print(("core-tree: %d checks passed"):format(checks))
