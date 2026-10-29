-- Retail talks to guildos.me (issue #182; guildos-web specs/056), run against the real Core, Compat,
-- Utils, GearAudit, RaidTracker, CoreManager, CompanionExport and CompanionImport under a stubbed
-- retail client: a character on Tol Barad in a guild whose home is Azralon.
--
-- The way out is payload v10: game RETAIL, the region, the guild's home realm in guildKey and realm
-- (never the exporter's: two officers on connected realms publish one guild), every person keyed by
-- their own realm, each session's difficulty, the personal loot in today's row format (issue #183),
-- and the enchant summary asking the audit. A region the
-- site has no world for publishes nothing and says why. The way back is GOSROST v3 and GOSCORE:
-- names keep the realm when it is not this character's, the invite knows who is already in the group
-- by name and realm, a planned raid matches a night only on the same difficulty, and a package of
-- cores is this guild's by its home realm.
--
--   luajit -e 'ADDON="."' tools/retail-site.lua
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

-- ── A retail client on Tol Barad, in a guild from Azralon ─────────────
local NIGHT = 1791000000
local REALM, HOME, REGION = "Tol Barad", "Azralon", 1
local NOW = NIGHT + 600
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function debugstack() return "" end
function GetServerTime() return NOW end
function time() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function IsInGuild() return true end
function GetGuildInfo() return "Jardim Escola", "Officer", 1, HOME end
function GetRealmName() return REALM end
function GetNormalizedRealmName() return (REALM:gsub("[%s%-]", "")) end
function GetCurrentRegion() return REGION end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
StaticPopupDialogs = {}
Enum = { SendAddonMessageResult = {} }

-- Who is in the group: me, Fulano from Azralon, and Ana from Gallywix — a namesake of the Ana from
-- Azralon the roster plans for.
local GROUP = { { "Chehul", nil, 1 }, { "Fulano", "Azralon", 5 }, { "Ana", "Gallywix", 1 } }
function IsInRaid() return true end
function GetNumGroupMembers() return #GROUP end
function UnitName(unit)
  if unit == "player" then return "Chehul" end
  local g = GROUP[tonumber(tostring(unit):match("%d+") or "")]
  if g then return g[1], g[2] end
end
function UnitClass() return "Druid", "DRUID" end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end
function GetRaidRosterInfo(i)
  local g = GROUP[i]
  if g then return g[2] and (g[1] .. "-" .. g[2]) or g[1], 0, g[3] end
end
local INVITED, MOVED = {}, {}
C_PartyInfo = { InviteUnit = function(name) INVITED[#INVITED + 1] = name end }
function SetRaidSubgroup(i, group)
  MOVED[#MOVED + 1] = UnitName("raid" .. i) .. "->" .. group
  GROUP[i][3] = group
end

-- The guild roster as retail writes it: every name with its realm, normalized.
local ROSTER = {
  -- fullName, rankName, rankIndex, level, ?, ?, ?, ?, online, ?, classFile
  { "Ana-Azralon",     "Guild Master", 0, 90, 0, 0, 0, 0, true,  0, "PRIEST" },
  { "Ana-Gallywix",    "Raider",       3, 90, 0, 0, 0, 0, true,  0, "MAGE" },
  { "Chehul-TolBarad", "Officer",      1, 90, 0, 0, 0, 0, true,  0, "DRUID" },
  { "Fulano-Azralon",  "Raider",       3, 90, 0, 0, 0, 0, true,  0, "WARRIOR" },
  { "Novato-Gallywix", "Trial",        5, 88, 0, 0, 0, 0, false, 0, "HUNTER" },
  { "Dup-Azralon",     "Raider",       3, 90, 0, 0, 0, 0, false, 0, "ROGUE" },
  { "Dup-Gallywix",    "Raider",       3, 90, 0, 0, 0, 0, false, 0, "ROGUE" },
  { "Zed-TolBarad",    "Raider",       3, 90, 0, 0, 0, 0, true,  0, "MAGE" },
}
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return unpack(r) end
end

-- An off hand is a weapon or a shield, by its item class (2 a weapon, 4 armour).
local WEAPON = { [222] = true }
C_Item = { GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, WEAPON[id] and 2 or 4 end }

local INSTANCE = { "The Voidspire", "raid", 15, "Heroic", 30, 0, true, 2912 }
function GetInstanceInfo() return unpack(INSTANCE) end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) return registry[name] end })
SlashCmdList = {}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
check(GuildOS.Client.isRetail and GuildOS.Client.game == "RETAIL", "the stub is a retail client")
function GuildOS:IsOfficer() return true end
GuildOS.IsOfficerByName = function() return true end
GuildOS.db = { settings = { companion = true, officerMaxRank = 1, modules = {} }, members = {}, altLinks = {}, cores = {},
               raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
GuildOS.SlotIDs = { { id = 1 }, { id = 9 }, { id = 11 }, { id = 16 }, { id = 17 } }
GuildOS.SlotNames = { [1] = "Head", [9] = "Wrist", [11] = "Finger", [16] = "Main Hand", [17] = "Off Hand" }
dofile(ADDON .. "/Libs/LibDeflate.lua")
local LD = LibStub("LibDeflate")
-- The modules this needs, loaded as the TOC loads them on retail: in its order, SoftResSystem with
-- them, which returns at once there. What a retail client lacks, this lacks too: the JSON decoder
-- once lived in SoftResSystem, and every roster from the site read as damaged on retail.
local WANT = { SoftResSystem = true, GearAudit = true, RaidTracker = true, CoreManager = true,
               CompanionExport = true, CompanionImport = true }
for line in io.lines(ADDON .. "/GuildOS.toc") do
  local m = line:match("^Modules[\\/](%w+)%.lua")
  if m and WANT[m] then
    dofile(ADDON .. "/Modules/" .. m .. ".lua")
    WANT[m] = nil
  end
end
check(next(WANT) == nil, "every module this needs is in the TOC")
check(GuildOS.SoftRes == nil and type(GuildOS.JsonDecode) == "function",
  "SoftRes is absent on retail, and the JSON decoder is not")
GuildOS.SyncService = { On = function() end, Publish = function() end }
local Companion, Import, RT, CM = GuildOS.Companion, GuildOS.CompanionImport, GuildOS.RaidTracker, GuildOS.CoreManager
check(Companion and Import, "the companion's modules are on retail")

-- ── 1. The guild's realm is its home realm ─────────────────────────────
check(GuildOS:GuildRealm() == "Azralon", "the guild's realm is its home realm, not this character's")
HOME = "Tol Barad"
check(GuildOS:GuildRealm() == "TolBarad", "normalized, as the roster writes it")
HOME = nil
check(GuildOS:GuildRealm() == "TolBarad", "a guild on this character's realm is this realm's")
HOME = "Azralon"

-- ── 2. Payload v10 ────────────────────────────────────────────────────
GuildOS.db.members["Chehul-TolBarad"] = {
  race = "Tauren", raceToken = "Tauren", sex = 2, avgIlvl = 720, lastUpdate = NIGHT - 60,
  spec = { tree = "Restoration", specID = 105, role = "HEALER", scannedAt = NIGHT - 60 },
  gear = {
    [1]  = { id = 111, name = "Helm", enchantId = 7001 },
    [9]  = { id = 112, name = "Bracers" },               -- retail has no wrist enchant
    [11] = { id = 113, name = "Ring" },                  -- a ring takes one on retail, and has none
    [16] = { id = 221, name = "Staff", enchantId = 7002 },
    [17] = { id = 333, name = "Shield" },                -- a shield takes none
  },
}
GuildOS.db.members["Ana-Gallywix"] = { lastUpdate = NIGHT - 120, avgIlvl = 700,
  gear = { [16] = { id = 221, name = "Sword", enchantId = 7002 }, [17] = { id = 222, name = "Dagger" } } }
GuildOS.db.raidTracker.sessions[NIGHT] = {
  instanceID = 2912, name = "The Voidspire", groupTag = "", startTime = NIGHT, endTime = NIGHT + 3600,
  size = 30, difficulty = 15, encounters = {},
  players = { ["Chehul-TolBarad"] = true, ["Ana-Gallywix"] = true },
  snapshots = { { time = NIGHT, members = { ["Chehul-TolBarad"] = { online = true }, ["Ana-Gallywix"] = { online = true } } } },
}

local p = assert(Companion:BuildPayload())
check(p.v >= 10 and p.game == "RETAIL" and p.region == "us", "v10 says the game and the region")
check(p.guildKey == "Jardim Escola-Azralon" and p.realm == "Azralon",
  "guildKey and realm are the guild's home realm, never the exporter's Tol Barad")
check(p.exportedBy == "Chehul-TolBarad", "the exporter is keyed by their own realm")
local by = {}
for _, m in ipairs(p.members) do by[m.key] = m end
check(p.count == #ROSTER and by["Ana-Azralon"] and by["Ana-Gallywix"] and by["Fulano-Azralon"] and by["Chehul-TolBarad"],
  "every member is keyed by their own realm, and two namesakes on connected realms are two people")
check(by["Ana-Gallywix"].name == "Ana" and by["Ana-Azralon"].class == "PRIEST" and by["Ana-Gallywix"].class == "MAGE",
  "each namesake is their own row")
local spec = by["Chehul-TolBarad"].spec
check(spec and spec.tree == "Restoration" and spec.specID == 105 and spec.role == "HEALER", "the spec keeps {tree, specID, role}")
local e = by["Chehul-TolBarad"].enchants
check(e and e.checked == 3 and #e.missing == 1 and e.missing[1] == "Finger",
  "the enchant summary asks the audit: the ring is missing one, the wrist and the shield are not asked")
local e2 = by["Ana-Gallywix"].enchants
check(e2 and e2.checked == 2 and e2.missing[1] == "Off Hand", "an off hand that is a weapon is asked")
check(#p.sessions == 1 and p.sessions[1].difficulty == 15 and p.sessions[1].instanceID == 2912, "a session carries its difficulty")
local keys = {}
for _, pl in ipairs(p.sessions[1].players) do keys[#keys + 1] = pl.key end
check(table.concat(keys, ",") == "Ana-Gallywix,Chehul-TolBarad", "a session's people keep their realms")
-- These frames say nothing about consumables (retail could not read them): they count for the player,
-- as the attendance score counts them, so the site's ratio docks nobody for it (issue #187).
check(p.sessions[1].players[1].chits == 1 and p.sessions[1].players[2].chits == 1,
  "a frame whose consumables were not read counts for the player")
check(#p.loot == 0, "no loot recorded, none sent")

-- Personal loot goes out in today's row format (issue #183): the real tracker, in a session.
dofile(ADDON .. "/Modules/LootTracker.lua")
GuildOS.LootTracker:Initialize()
RT.TakeSnapshot = function() end
RT:StartSession(2912)
GuildOS.LootTracker:OnEncounterLoot(3176, 250001, "|cnIQ4:|Hitem:250001::::::::90:::::|h[Voidforged Helm]|h|r", 1,
  "Ana-Gallywix", "MAGE")
RT.trackingActive, RT.currentRaid = false, nil
local looted = assert(Companion:BuildPayload())
local row = looted.loot[1]
check(#looted.loot == 1 and row.playerKey == "Ana-Gallywix" and row.player == "Ana-Gallywix" and row.itemId == 250001
  and row.itemName == "Voidforged Helm" and row.quality == 4 and row.timestamp == NOW and row.raid == "The Voidspire",
  "a personal item goes to the site, keyed by its player's own realm")
local fields = 0
for _ in pairs(row) do fields = fields + 1 end
check(fields == 7, "in today's row format: the seven fields the site reads, nothing more")
GuildOS.db.lootHistory = {}

-- An officer on Azralon publishes the same guild.
REALM = "Azralon"
local q = assert(Companion:BuildPayload())
check(q.guildKey == p.guildKey and q.realm == p.realm and q.exportedBy == "Chehul-Azralon",
  "an officer on another connected realm publishes the same guild")
REALM = "Tol Barad"

-- On the wire.
local text, n = Companion:Build()
check(type(text) == "string" and n == #ROSTER, "the string builds")
local json = LD:DecompressDeflate(LD:DecodeForPrint(text:sub(#"GOSCOMP1:" + 1)))
check(json:find('"region":"us"', 1, true) and json:find('"difficulty":15', 1, true) and json:find('"game":"RETAIL"', 1, true)
  and json:find('"guildKey":"Jardim Escola-Azralon"', 1, true), "the region, the difficulty, the game and the key are on the wire")

-- Each region the site has, and none it does not.
for id, region in pairs({ [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw" }) do
  REGION = id
  check(Companion:BuildPayload().region == region and Companion:Refused() == nil, "region " .. id .. " is " .. region)
end
for _, id in ipairs({ 5, 72, false }) do
  REGION = id or nil
  local none, why = Companion:BuildPayload()
  local built, err = Companion:Build()
  check(none == nil and built == nil and why == Companion:Refused() and err == why and why:find("region", 1, true),
    "region " .. tostring(id) .. ": nothing is published, and it says why")
end
local realRegion = GetCurrentRegion
GetCurrentRegion = nil
check(Companion:BuildPayload() == nil, "a client with no region API publishes nothing")
GetCurrentRegion = realRegion
GuildOS.Client.isRetail = false
check(Companion:Refused() == nil, "elsewhere the region is never asked")
GuildOS.Client.isRetail = true
REGION = 1

-- ── 3. GOSROST v3 back into the game ──────────────────────────────────
local function wire(prefix, t) return prefix .. LD:EncodeForPrint(LD:CompressDeflate(Companion.EncodeJson(t))) end
local function signup(m, extra)
  local s = { key = m.key, name = m.name, class = m.class, spec = m.spec, slot = m.slot, status = "yes", invite = true, group = m.group }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local MEMBERS = {
  { key = "Chehul-TolBarad", name = "Chehul", class = "DRUID", spec = "Restoration", slot = "HEALER", group = 1 },
  { key = "Fulano-Azralon", name = "Fulano", class = "WARRIOR", spec = "Protection", slot = "TANK", group = 2 },
  { key = "Ana-Azralon", name = "Ana", class = "PRIEST", spec = "Holy", slot = "HEALER", group = 1 },
  { key = "Zed-TolBarad", name = "Zed", class = "MAGE", spec = "Frost", slot = "RANGED", group = 3 },
}
local SIGNUPS = { signup(MEMBERS[1]), signup(MEMBERS[2]), signup(MEMBERS[3]), signup(MEMBERS[4]),
  { name = "Novato", class = "", spec = "", slot = "RANGED", status = "yes", invite = false, why = "unknown" },
  { name = "Dup", class = "", spec = "", slot = "RANGED", status = "yes", invite = false, why = "unknown" } }
local ROSTER_H = { fmt = "GOSROST1", v = 3, raidId = "raid-h", title = "Voidspire H", startsAt = NIGHT,
  instance = "The Voidspire", instanceKey = "midnight-voidspire", size = 20, difficulty = 15,
  members = MEMBERS, signups = SIGNUPS }

local PN = Import.PlainName
check(PN("Chehul-TolBarad") == "Chehul" and PN("Fulano-Azralon") == "Fulano-Azralon",
  "PlainName keeps the realm only when it is not this character's")
check(PN("Chehul") == "Chehul", "a bare name is a bare name")

check(Import:Load(wire("GOSROST1:", ROSTER_H)) == 4, "the v3 roster loads, decoded with SoftRes absent")
local r = Import:Current()
check(r.difficulty == 15 and r.instanceKey == "midnight-voidspire", "the roster keeps its difficulty")
local function namesOf(list)
  local t = {}
  for _, m in ipairs(list) do t[#t + 1] = m.name end
  return table.concat(t, ",")
end
check(namesOf(r.members) == "Chehul-TolBarad,Fulano-Azralon,Ana-Azralon,Zed-TolBarad",
  "a name is the site's Name-Realm key, whoever imports it")
-- Officers on two connected realms keep the same names, so the calendar's list of answers is one
-- list on every client and a fresher inbox does not republish it for nothing.
REALM = "Azralon"
local there = Import:Parse(wire("GOSROST1:", ROSTER_H))
check(namesOf(there.members) == namesOf(r.members) and namesOf(there.signups) == namesOf(r.signups),
  "an officer on another connected realm reads the same names")
REALM = "Tol Barad"

local rescued = Import:Rescued(r)
check(rescued.Novato == "Novato-Gallywix", "a name the site never confirmed is found on the guild roster, with its realm")
check(rescued.Dup == nil, "a name two connected realms have is nobody to guess between")

local invited, skipped, err = Import:InviteAll()
check(not err, "the invite runs: " .. tostring(err))
table.sort(INVITED)
check(table.concat(INVITED, ",") == "Ana-Azralon,Novato-Gallywix,Zed",
  "invited: Ana from Azralon (the Ana here is Gallywix's) and the rescued Novato by name and realm, Zed from my realm plain")
check(invited == 3 and skipped == 2, "me and Fulano, already here from another realm, are not invited again")

-- Zed joined from my realm, in the wrong group: the raid roster says "Zed", the site "Zed-TolBarad".
GROUP[4] = { "Zed", nil, 1 }
local moved = Import:OrganizeGroups()
table.sort(MOVED)
check(moved == 2 and table.concat(MOVED, ",") == "Fulano->2,Zed->3",
  "Fulano from Azralon and Zed from my realm move to the groups the site planned; the other Ana does not")
-- A raid member the client keeps secret is passed over, never read.
local SECRET = setmetatable({}, { __len = function() error("a secret value was read") end,
  __index = function() error("a secret value was read") end })
function issecretvalue(v) return v == SECRET end
GROUP[5], MOVED = { SECRET, nil, 4 }, {}
local ok, again = pcall(Import.OrganizeGroups, Import)
check(ok and again == 0, "a secret name in the raid does not raise: " .. tostring(again))
GROUP[4], GROUP[5], issecretvalue = nil, nil, nil

-- A leader alone, on the roster, does not invite themselves.
local group = GROUP
GROUP, INVITED = {}, {}
invited, skipped = Import:InviteAll()
for _, name in ipairs(INVITED) do check(name ~= "Chehul" and name ~= "Chehul-TolBarad", "the leader invited themselves") end
check(invited == 4 and skipped == 1, "alone: everyone but me is invited")
GROUP = group

-- ── 4. Which planned raid this night is ───────────────────────────────
INVITED = {}
GuildOSInbox, GuildOSInboxAck = { wire("GOSROST1:", ROSTER_H) }, { at = NOW }
Import._lastInbox = nil
check(Import:ConsumeInbox(), "the inbox is read on retail")
check(GuildOS.db.companionRaids[1].difficulty == 15, "the planned raid keeps its difficulty")
check(Import:RaidFor("midnight-voidspire", NIGHT, 15) == "raid-h", "the same difficulty matches")
check(Import:RaidFor("midnight-voidspire", NIGHT, 14) == nil, "Normal is another night than a Heroic planned")
check(Import:RaidFor("midnight-voidspire", NIGHT) == "raid-h", "a night with no difficulty is matched by place and time")
GuildOS.db.companionRaids[2] = { raidId = "raid-old", instanceKey = "midnight-abyss", startsAt = NIGHT }
check(Import:RaidFor("midnight-abyss", NIGHT, 16) == "raid-old", "a raid from a site before v3 has no difficulty to disagree with")

for id, key in pairs({ [2912] = "midnight-voidspire", [2939] = "midnight-dreamrift", [2913] = "midnight-queldanas",
                       [3004] = "midnight-abyss" }) do
  check(RT.RAID_KEYS[id] == key, "map " .. id .. " is the site's " .. key)
end
RT.TakeSnapshot = function() end
RT:StartSession(2912)
check(RT.currentRaid.difficulty == 15 and RT.currentRaid.raidId == "raid-h", "a Heroic night is stamped with the Heroic raid")
RT.trackingActive, RT.currentRaid = false, nil
INSTANCE[3], INSTANCE[4] = 14, "Normal"
RT:StartSession(2912)
check(RT.currentRaid.raidId == nil, "a Normal night is not stamped with the Heroic raid")
RT.trackingActive, RT.currentRaid = false, nil

-- The calendar gets the site's raids on retail too.
local cal = {}
GuildOS.Calendar = { UpsertWebRaid = function(_, roster) cal[#cal + 1] = roster end }
Import:CalendarFromInbox()
check(#cal == 1 and cal[1].raidId == "raid-h" and cal[1].difficulty == 15, "the site's raid goes on the calendar")

-- ── 5. The Discord's cores: this guild's by its home realm ─────────────
local function cores(realm)
  return { guild = "Jardim Escola", realm = realm, unlinked = 0, cores = { { tag = "alfa", name = "Alfa", size = 20,
    members = { { key = "Fulano-Azralon", name = "Fulano", class = "WARRIOR", slot = "tank" } } } } }
end
check(CM:ImportFromSite(cores("Azralon")) and CM:IsFromDiscord("Alfa"), "the guild's home realm is this guild, from Tol Barad")
check(GuildOS.db.cores["Alfa"].members["Fulano-Azralon"], "a member from another connected realm keeps their key")
local none, whose = CM:ImportFromSite(cores("Tol Barad"))
check(none == nil and whose == "Jardim Escola (Tol Barad)", "this character's own realm is not the guild's")
none, whose = CM:ImportFromSite(cores("Gallywix"))
check(none == nil and whose == "Jardim Escola (Gallywix)", "a namesake guild on another realm is not this one")
HOME = "Tol Barad"
check(CM:ImportFromSite(cores("TolBarad")), "the site's normalized realm meets a home realm the client spells with a space")
check(CM:ImportFromSite(cores("Tol Barad")), "and a realm that arrives with a space is normalized too")
HOME = "Azralon"
check(CM:ImportFromSite(cores(nil)), "a package that names no realm is taken by its guild")

print(("retail-site: %d checks passed"):format(checks))
