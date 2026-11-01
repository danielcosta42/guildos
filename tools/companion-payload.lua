-- Runs the real CompanionExport against stubbed WoW APIs and prints the string
-- a player would copy out of the game.
--
-- The two halves of the GOSCOMP1 format live in different repositories, so a
-- fixture invented on the web side would only prove the decoder agrees with
-- itself. This produces the genuine article; the web repository keeps the
-- output as `packages/goscomp/test/fixtures/addon-v2.txt` and decodes it in a
-- test. The first run of this caught the addon emitting `GOSCOMP1` where the
-- decoder wanted `GOSCOMP1:`.
--
--   lua5.1 -e 'ADDON="."' tools/companion-payload.lua > /tmp/addon-v2.txt
--
-- Regenerate the fixture whenever the payload changes shape, and expect the
-- web test to need updating with it — that is the point.
--
-- With PACK set it prints the character's own pack instead (the site's specs/070):
--
--   lua5.1 -e 'ADDON="."; PACK=true' tools/companion-payload.lua > /tmp/addon-pack.txt
ADDON = ADDON or "."
package.path = ADDON .. "/?.lua;" .. package.path

-- ── WoW API surface the export touches ────────────────────────────────
local ROSTER = {
  -- fullName, rankName, rankIndex, level, ?, ?, ?, ?, online, ?, classFile
  { "Chehul-Firemaw",  "Guild Master", 0, 70, 0,0,0,0, true,  0, "HUNTER" },
  { "Fulano-Firemaw",  "Raider",       4, 70, 0,0,0,0, false, 0, "PRIEST" },
  { "Semdados-Firemaw","Trial",        6, 68, 0,0,0,0, false, 0, "MAGE"   },
}
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if not r then return nil end
  return r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11]
end
function GetGuildInfo() return "Raid Guild", "Guild Master", 0 end
-- The module hangs a PLAYER_LOGOUT frame off the file scope so the payload
-- lands in SavedVariables for the desktop companion. The stub keeps the handler,
-- so the pack's checks below fire the real one.
local logoutHandler
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function(_, _, fn) logoutHandler = fn end }
end
function GetRealmName() return "Firemaw" end
function UnitName() return "Chehul" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitLevel() return 70 end
function time() return 1754400000 end
function GetServerTime() return 1754400000 end

-- LibStub, just enough for LibDeflate to register and be fetched. It is called
-- both as LibStub("x") and as LibStub:NewLibrary("x", n), so it has to be a
-- table with __call rather than a function.
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name)
    registry[name] = registry[name] or {}
    return registry[name]
  end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
  minor = 1,
}, {
  __call = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
})

-- ── The addon's own globals ───────────────────────────────────────────
GuildOS = {
  VERSION = "0.46.0",
  -- Core/Compat.lua reads this off the client; the export only asks which game it is.
  Client = { isAnniversary = true },
  L = setmetatable({}, { __index = function(_, k) return k end }),
  -- Core/Data.lua's slot list, as far as this roster's gear goes.
  SlotIDs = { { id = 1, name = "HeadSlot" }, { id = 3, name = "ShoulderSlot" }, { id = 5, name = "ChestSlot" },
              { id = 7, name = "LegsSlot" }, { id = 15, name = "BackSlot" }, { id = 16, name = "MainHandSlot" } },
  SlotNames = { [1]="Head", [3]="Shoulder", [5]="Chest", [7]="Legs", [8]="Feet",
                [9]="Wrist", [10]="Hands", [15]="Back", [16]="Main Hand" },
  db = { members = {}, lootHistory = {}, settings = { companion = true } },
}

-- A night as RaidTracker actually stores one: two snapshots, one boss, and a
-- person who dropped out for the second half. The third guild member never
-- appears, because she was not there — and that is the whole point.
local NIGHT = 1754380000
GuildOS.db.raidTracker = {
  sessions = {
    [NIGHT] = {
      instanceID = 565,
      name = "Gruul's Lair",
      groupTag = "",
      startTime = NIGHT,
      endTime = NIGHT + 4 * 3600,
      encounters = {
        { id = 649, name = "Gruul the Dragonkiller",
          startTime = NIGHT + 7200, endTime = NIGHT + 7500, success = true },
        -- Ended mid-pull: no endTime, no verdict. Not a wipe — an unfinished try.
        { id = 650, name = "High King Maulgar", startTime = NIGHT + 14000 },
      },
      players = { ["Chehul-Firemaw"] = true, ["Fulano-Firemaw"] = true },
      snapshots = {
        { time = NIGHT, reason = "session_start", count = 2, members = {
            ["Chehul-Firemaw"] = { name = "Chehul", class = "HUNTER", online = true,  hasConsumes = true },
            ["Fulano-Firemaw"] = { name = "Fulano", class = "PRIEST", online = true,  hasConsumes = false },
        } },
        { time = NIGHT + 7200, reason = "encounter_start", count = 2, members = {
            ["Chehul-Firemaw"] = { name = "Chehul", class = "HUNTER", online = true,  hasConsumes = true },
            ["Fulano-Firemaw"] = { name = "Fulano", class = "PRIEST", online = false, hasConsumes = false },
        } },
      },
    },
    -- An alt run somebody marked as not a guild raid. It travels so the site can
    -- see it on the night screens, and attendance on both sides has to skip it.
    [NIGHT + 86400] = {
      instanceID = 565,
      name = "Gruul's Lair",
      groupTag = "Core 2",
      isGuildRaid = false,
      startTime = NIGHT + 86400,
      endTime = NIGHT + 86400 + 3600,
      encounters = {},
      players = { ["Chehul-Firemaw"] = true },
      snapshots = {
        { time = NIGHT + 86400, reason = "session_start", count = 1, members = {
            ["Chehul-Firemaw"] = { name = "Chehul", class = "HUNTER", online = true, hasConsumes = false },
        } },
      },
    },
  },
  deletedSessions = { [1754000000] = true },
}

-- Two cores with different weights, because the whole reason the rules travel is
-- that an officer can change them and the site cannot assume 10/10/10.
GuildOS.CoreManager = {
  GetPenalties = function(_, coreName)
    if coreName == "Core 2" then
      return { LATE = 25, LEFT_EARLY = 5, NO_CONSUMES = 0 }
    end
    return { LATE = 10, LEFT_EARLY = 10, NO_CONSUMES = 10 }
  end,
}
-- TBC Anniversary, as the real Compat recognises it, for my own name through Compat.PlayerName (issue #26).
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")  -- the real member-key rule (issue #8), not a copy of it
function GuildOS:GetSetting(key) return self.db.settings[key] end
function GuildOS:SetSetting(key, v) self.db.settings[key] = v end
-- Core/Core.lua's answer; the pack's checks below say when it is no.
local onGuildDB = true
function GuildOS:IsOnGuildDB() return onGuildDB end

-- The real audit: the export asks it which slot needs an enchant, as the member sheet does (issue #182).
dofile(ADDON .. "/Modules/GearAudit.lua")

GuildOS.RaidTracker = {
  GetAttendance25ManPercent = function(_, key)
    return ({ ["Chehul-Firemaw"] = 92, ["Fulano-Firemaw"] = 78 })[key] or 0
  end,
}

GuildOS.AttunementTracker = {
  GetEffectiveAttunements = function(_, key)
    if key == "Chehul-Firemaw" then
      return {
        { short = "Kara",  complete = true,  progress = 1 },
        { short = "SSC",   complete = true,  progress = 1 },
        { short = "Hyjal", complete = false, progress = 0.0 },
        { short = "BT",    complete = false, progress = 7/16 },
      }
    elseif key == "Fulano-Firemaw" then
      return { { short = "Kara", complete = false, progress = 7/9 } }
    end
    return {}
  end,
}

-- Two members who published, one who never did — the third must not appear.
GuildOS.db.members["Chehul-Firemaw"] = {
  race = "Orc", avgIlvl = 132, lastUpdate = 1754399000,
  spec = { tree = "Beast Mastery", treeIndex = 1, points = { 41, 20, 0 } },
  prefRoles = { "DPS" },
  -- Alchemy has no rank: known from the guild roster only (issue #31); it is not exported.
  professions = { { name = "Leatherworking", rank = 375 }, { name = "Skinning", rank = 375 }, { name = "Alchemy" } },
  gear = {
    [1]  = { name = "Cursed Vision", enchantId = 2999 },
    [3]  = { name = "Wastewalker Shoulderpads", enchantId = 0 },   -- unenchanted
    [5]  = { name = "Netherdrake Chest", enchantId = 3245 },
    [7]  = { name = "Scaled Greaves", enchantId = nil },            -- unenchanted
    [15] = { name = "Cloak of Fire", enchantId = 2621 },
    [16] = { name = "Sunfury Bow", enchantId = 2523 },
    [17] = { name = "Off hand nobody enchants" },                   -- not audited
  },
}
GuildOS.db.members["Fulano-Firemaw"] = {
  race = "Human", avgIlvl = 128, lastUpdate = 1754398000,
  spec = { tree = "Holy", treeIndex = 2, points = { 23, 38, 0 } },
  professions = {},
  gear = nil,                                                       -- never synced gear
}

GuildOS.LootTracker = {
  GetHistory = function()
    return {
      { itemLink = "|cffa335ee|Hitem:30107::::::::70:::::|h[Vestments of the Sea-Witch]|h|r",
        itemName = "Vestments of the Sea-Witch", quality = 4,
        player = "Fulano", playerKey = "Fulano-Firemaw",
        timestamp = 1754300000, raid = "Serpentshrine Cavern" },
      -- Player-authored text with characters that would break naive JSON.
      { itemId = 32235, itemName = 'Crystal "Spire" of\tKarabor', quality = 4,
        player = "Chehul", playerKey = "Chehul-Firemaw",
        timestamp = 1754200000, raid = "Black\nTemple" },
    }
  end,
}

dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")

-- The payload says which game the client is, so the site can build a Forever guild's
-- keys itself and refuse a roster from the other game (the site's specs/036).
local anniversary = GuildOS.Companion:BuildPayload()
assert(anniversary.game == "ANNIVERSARY", "an Anniversary client did not say so")
assert(anniversary.v >= 6, "the payload that says its game is v6")
GuildOS.Client.isAnniversary = false
assert(GuildOS.Companion:BuildPayload().game == "FOREVER", "a Forever client did not say so")
GuildOS.Client.isAnniversary = true

-- v12 (issue #213): the guild's tabard as the game draws it, never on Anniversary, in the shape the
-- site reads: colours as whole bytes, the emblem's style and the six files.
GetGuildLogoInfo = function() return 33.2, 220, 255.4, 0, 0, 0, 255, 254.6, 1, 0, 42 end
GetGuildTabardFiles = function() return 1, 2, 3, 4, 5, 6 end
assert(GuildOS.Companion:BuildPayload().tabard == nil, "no tabard on Anniversary")
GuildOS.Client.isAnniversary = false
local tabardJson = GuildOS.Companion.EncodeJson(GuildOS.Companion:BuildPayload().tabard)
assert(tabardJson == '{"background":[33,220,255],"border":[0,0,0],"emblem":[255,255,1],"emblemStyle":42,"files":[1,2,3,4,5,6]}',
  "the tabard's shape: " .. tabardJson)
GuildOS.Client.isAnniversary = true
GetGuildLogoInfo, GetGuildTabardFiles = nil, nil

-- Nothing new costs the upload (issue #232): a field that fails is left out and said, the roster still
-- goes up; and what is switched off is not even asked.
do
  local recorded, asked = {}, 0
  local on = { journal = true, founding = true }
  GuildOS.RecordError = function(_, msg) recorded[#recorded + 1] = msg end
  GuildOS.IsFeatureEnabled = function(_, id) return on[id] == true end
  local boom = function() asked = asked + 1; error("no such thing on this client") end
  GuildOS.Journal = { ForExport = boom, IsOptedOut = function() return false end }
  GuildOS.Founding = { ForExport = boom, JoinedAtOf = function() return nil end }
  local tabard = GuildOS.Compat.GuildTabard
  GuildOS.Compat.GuildTabard = boom
  GuildOS.Client.isAnniversary = false
  local payload = assert(GuildOS.Companion:BuildPayload(), "the upload went with its new fields")
  assert(#payload.members > 0, "the roster still goes up")
  assert(payload.journal == nil and payload.founding == nil and payload.tabard == nil, "what failed is left out")
  assert(#recorded == 3, "and each one is in /guildos errors: " .. #recorded)
  GuildOS.Compat.GuildTabard = function() return nil end
  on.journal, on.founding, asked = false, false, 0
  payload = assert(GuildOS.Companion:BuildPayload())
  assert(asked == 0 and payload.journal == nil and payload.founding == nil, "switched off: not asked, and absent")
  on.journal, on.founding = true, true
  GuildOS.Journal = { ForExport = function() return { { id = "x" } } end, IsOptedOut = function() return false end }
  GuildOS.Founding = { ForExport = function() return { revision = 1 } end, JoinedAtOf = function() return nil end }
  payload = assert(GuildOS.Companion:BuildPayload())
  assert(#payload.journal == 1 and payload.founding.revision == 1, "switched on: they go")
  GuildOS.Compat.GuildTabard = tabard
  GuildOS.Journal, GuildOS.Founding, GuildOS.IsFeatureEnabled, GuildOS.RecordError = nil, nil, nil, nil
  GuildOS.Client.isAnniversary = true
end

-- v7 (issue #35): on Forever each member carries the profession model's lines by skill-line
-- ID -- rank, max, specialization and the recipes they know, or only the line for a member
-- known from the guild roster. Absent where there is no model, or no record of the member.
assert(anniversary.v >= 7, "the payload that carries crafting is v7")
for _, m in ipairs(anniversary.members) do
  assert(m.crafting == nil, "no profession model (Anniversary): no crafting key for " .. m.key)
end
-- The real module (it loads only on Forever), over its saved records -- a stub here once hid
-- that the export called a function this branch did not have.
GuildOS.Client.isAnniversary = false
GuildOS.db.professions = {
  ["Chehul-Firemaw"] = { src = "addon", ts = 1, profs = {
    [393] = { rank = 300, max = 300, n = 0, h = 0, recipes = {}, extra = {} },
    [165] = { rank = 285, max = 300, spec = 10656, n = 3, h = 1, recipes = { 3304, 2657 }, extra = { 999001 } } } },
  ["Fulano-Firemaw"] = { src = "native", ts = 1, profs = { [171] = {} } },
}
dofile(ADDON .. "/Modules/Professions.lua")
local forever = GuildOS.Companion:BuildPayload()
local byKey = {}
for _, m in ipairs(forever.members) do byKey[m.key] = m end
local c = byKey["Chehul-Firemaw"].crafting
assert(c and #c == 2 and c[1].line == 165 and c[2].line == 393, "crafting lists every line, by ID, in order")
assert(c[1].rank == 285 and c[1].max == 300 and c[1].spec == 10656, "a line carries rank, max and specialization")
assert(#c[1].recipes == 3 and c[1].recipes[1] == 2657 and c[1].recipes[3] == 999001,
  "and every recipe it knows, catalog and extra, sorted")
assert(#c[2].recipes == 0 and c[2].spec == nil, "a line with no recipes carries an empty list")
local n = byKey["Fulano-Firemaw"].crafting
assert(n and #n == 1 and n[1].line == 171 and n[1].native == true and n[1].rank == nil and n[1].recipes == nil,
  "a member known from the guild roster only carries the line, marked native")
for key, m in pairs(byKey) do
  if key ~= "Chehul-Firemaw" and key ~= "Fulano-Firemaw" then
    assert(m.crafting == nil, "no record of the member: no crafting key for " .. key)
  end
end

-- A changed list on its way: the previous one stands in. A list on its way with no previous
-- one: no crafting key at all, so the site keeps what another officer published.
GuildOS.db.professions["Semdados-Firemaw"] = { src = "addon", ts = 1, profs = {
  [164] = { rank = 120, max = 150, n = 4, h = 2, stale = { 2660, 2663 }, staleExtra = {} } } }
local stale = {}
for _, m in ipairs(GuildOS.Companion:BuildPayload().members) do stale[m.key] = m end
local s = stale["Semdados-Firemaw"].crafting
assert(s and #s == 1 and s[1].rank == 120 and #s[1].recipes == 2, "a stale list stands in while the new one travels")
GuildOS.db.professions["Semdados-Firemaw"].profs[164].stale = nil
for _, m in ipairs(GuildOS.Companion:BuildPayload().members) do stale[m.key] = m end
assert(stale["Semdados-Firemaw"].crafting == nil, "a list still on its way: no crafting key, the site keeps its own")
GuildOS.Professions, GuildOS.db.professions = nil, nil

-- v8 (issue #37): the look the member's addon read in the barber's chair, as {option, choice}
-- pairs; absent for everyone who has not sat in one.
assert(anniversary.v >= 8, "the payload that carries the look is v8")
GuildOS.db.members["Chehul-Firemaw"].look = { { 19, 359 }, { 9493, 78927 } }
local looks = {}
for _, m in ipairs(GuildOS.Companion:BuildPayload().members) do looks[m.key] = m.look end
assert(looks["Chehul-Firemaw"] and #looks["Chehul-Firemaw"] == 2 and looks["Chehul-Firemaw"][2][2] == 78927,
  "a member with a look carries it")
assert(looks["Fulano-Firemaw"] == nil, "a member with none carries no look key")
GuildOS.db.members["Chehul-Firemaw"].look = "junk"
for _, m in ipairs(GuildOS.Companion:BuildPayload().members) do looks[m.key] = m.look end
assert(looks["Chehul-Firemaw"] == nil, "a look that is not a list is not exported")
GuildOS.db.members["Chehul-Firemaw"].look = nil

-- v9 (issue #90): a session's raid size as the game gave it; absent for a night recorded before.
assert(anniversary.v >= 9, "the payload that carries a session's size is v9")
assert(anniversary.sessions[1].size == nil, "a night recorded before sizes were kept carries no size key")
GuildOS.db.raidTracker.sessions[NIGHT].size = 20
assert(GuildOS.Companion:BuildPayload().sessions[1].size == 20, "a night's size travels")
GuildOS.db.raidTracker.sessions[NIGHT].size = nil
GuildOS.Client.isAnniversary = true

-- v10 (issue #182) is retail's: the region, the guild's home realm and each session's difficulty
-- (tools/retail-site.lua). The other games send what they sent at v9: no region, no difficulty.
assert(anniversary.v == 12, "the payload is v12")
-- v12 (issue #205) starts the WoW: Forever guild feed: no journal outside Forever (tools/journal.lua).
assert(anniversary.journal == nil, "no journal on TBC Anniversary")

-- v11 (issue #203): the site reads "not listed" as "left the guild" only from a whole roster.
assert(anniversary.rosterComplete == true, "a whole roster says so")
-- "Show Offline Members" off is still the whole guild when every row answers: retail 12.1.5 gave
-- all 943 rows of a guild with 10 online.
GetGuildRosterShowOffline = function() return false end
assert(GuildOS.Companion:BuildPayload().rosterComplete == true, "the window's option is not the roster")
local fulano = table.remove(ROSTER, 2)
local n = #ROSTER + 1
GetNumGuildMembers = function() return n end
assert(GuildOS.Companion:BuildPayload().rosterComplete == nil, "a roster with a row missing is not whole")
GetNumGuildMembers = function() return #ROSTER end
table.insert(ROSTER, 2, fulano)
GetGuildRosterShowOffline = nil
assert(anniversary.region == nil and anniversary.sessions[1].difficulty == nil and anniversary.realm == "Firemaw",
  "Anniversary sends no region and no difficulty, and its realm is the client's")

for _, m in ipairs(anniversary.members) do
  if m.key == "Chehul-Firemaw" then
    assert(#m.professions == 2 and m.professions[1].name == "Leatherworking" and m.professions[2].name == "Skinning",
      "a profession with no rank is not exported (issue #31)")
  end
end

-- The pack (the site's specs/070). The switch is off by default because the export carries the whole
-- guild, so a member who installs the app would send nothing. With it off the addon writes only its own
-- character. One GOSCOMP1: string per file, whichever it is: the app lifts the first match, and an
-- officer's upload must never pick the pack.
local packText
do
  local Companion, LD, WIRE = GuildOS.Companion, LibStub("LibDeflate"), "GOSCOMP1:"
  local PLAYER, NOW = "Chehul-Firemaw", 1754400000

  local function opened(text)
    assert(type(text) == "string" and text:sub(1, #WIRE) == WIRE, "not a GOSCOMP1: string: " .. tostring(text))
    local json = LD:DecompressDeflate(LD:DecodeForPrint(text:sub(#WIRE + 1)))
    return assert(GuildOS.JsonDecode(json)), json
  end
  -- The app's own regex over everything that reaches the file.
  local function onDisk(t, found)
    found = found or {}
    for _, v in pairs(t) do
      if type(v) == "table" then
        onDisk(v, found)
      elseif type(v) == "string" then
        for s in v:gmatch("GOSCOMP1:[a-zA-Z0-9()]+") do found[#found + 1] = s end
      end
    end
    return found
  end
  local function logout() logoutHandler(nil, "PLAYER_LOGOUT") end
  local function switch(on) GuildOS.db.settings.companion = on end

  local saved = GuildOS.db.settings.companion
  local mine = GuildOS.db.members[PLAYER]
  GuildOSDB = { ["Raid Guild-Firemaw"] = GuildOS.db }

  -- Off, in a guild: the pack, on the schedule and in the field the export uses.
  switch(false)
  logout()
  local files = onDisk(GuildOSDB)
  assert(#files == 1 and files[1] == GuildOSDB.__companion, "switch off: one string, in __companion: " .. #files)
  assert(files[1] == files[1]:match("^GOSCOMP1:[a-zA-Z0-9()]+$"), "the app's regex lifts the whole string")
  local pack, json = opened(files[1])
  assert(pack.self == true and pack.fmt == "GOSCOMP1" and pack.v == 12 and pack.count == 1, "it says it is the pack")
  assert(pack.guildKey == "Raid Guild-Firemaw" and pack.guildName == "Raid Guild" and pack.realm == "Firemaw"
    and pack.game == "ANNIVERSARY", "it names the guild and the game, as the site's upload picks by them")
  assert(pack.exportedBy == PLAYER and pack.exportedAt == NOW and pack.addonVersion == GuildOS.VERSION, "and who, when, which addon")
  assert(#pack.members == 1 and pack.members[1].key == PLAYER and pack.members[1].lastUpdate == mine.lastUpdate,
    "one line, mine, with the stamp the site's guard reads")
  for _, field in ipairs({ "sessions", "deletedSessions", "attendanceRules", "journal", "tabard", "founding",
                           "guildConfig", "rosterComplete", "region" }) do
    assert(pack[field] == nil and not json:find('"' .. field .. '"', 1, true), "the pack carries no " .. field)
  end
  -- `loot` is the one key it cannot leave out: the decoder (packages/goscomp's assertPayload) refuses a
  -- payload with no list, and "same decoder as today" is the contract.
  assert(json:find('"loot":[]', 1, true) and #pack.loot == 0, "an empty loot list, for the decoder: no loot")
  -- Not "the guild publishes": the Web panel's "last written" and Activation's publish step read this.
  assert(GuildOSDB.__companionAt == nil, "the pack does not stamp __companionAt")

  -- The line is the export's own, byte for byte, not a copy of how it is built.
  local line
  for _, m in ipairs(Companion:BuildPayload().members) do
    if m.key == PLAYER then line = Companion.EncodeJson(m) end
  end
  assert(line and json:find(line, 1, true), "the pack's line is the export's line")

  -- The guild roster need not be loaded: a quick relog has none, and it is the person's own client.
  local rosterSize = GetNumGuildMembers
  GetNumGuildMembers = function() return 0 end
  GuildOSDB.__companion = nil
  logout()
  assert(opened(GuildOSDB.__companion).members[1].key == PLAYER, "the pack needs no guild roster")
  GetNumGuildMembers = rosterSize

  -- Not in a guild: nothing written, and what was there stays.
  local guildInfo = GetGuildInfo
  local before = GuildOSDB.__companion
  GetGuildInfo = function() return nil end
  logout()
  assert(GuildOSDB.__companion == before, "out of a guild the last string stays")
  GuildOSDB.__companion = nil
  logout()
  assert(GuildOSDB.__companion == nil, "out of a guild nothing is written")
  GetGuildInfo = guildInfo

  -- A db that is not this guild's reads as "off" whatever the guild chose: at a cold login that never
  -- resolved, or on a character who joined mid-session (#150). A pack there would replace an officer's export.
  onGuildDB = false
  GuildOSDB.__companion = "GOSCOMP1:anOfficersExport"
  logout()
  assert(GuildOSDB.__companion == "GOSCOMP1:anOfficersExport", "off the guild's db nothing is written")
  onGuildDB = true
  GuildOSDB.__companion = nil

  -- A client that has not read itself yet has nothing to say.
  GuildOS.db.members[PLAYER] = nil
  logout()
  assert(GuildOSDB.__companion == nil, "no record of me: no pack")
  GuildOS.db.members[PLAYER] = { lastUpdate = 0, avgIlvl = 0 }
  logout()
  assert(GuildOSDB.__companion == nil, "a record nothing was read into: no pack")
  GuildOS.db.members[PLAYER] = mine

  -- Absent, not empty: a default that travels is a claim, and the site would write it.
  local avgIlvl, gear, professions = mine.avgIlvl, mine.gear, mine.professions
  mine.avgIlvl, mine.gear, mine.professions = 0, nil, nil
  GetGuildInfo = function() return "Raid Guild" end
  logout()
  local m = opened(GuildOSDB.__companion).members[1]
  assert(m.avgIlvl == nil, "a cold item cache sends no average, not a zero")
  assert(m.gear == nil and m.enchants == nil and m.professions == nil, "what was not read is absent")
  assert(m.rank == nil and m.rankIndex == nil, "a rank nobody gave is absent, not \"\" and 0, which reads Guild Master")
  mine.avgIlvl, mine.gear, mine.professions = avgIlvl, gear, professions
  GetGuildInfo = guildInfo

  -- WoW: Forever: the key comes from Compat.PlayerName. UnitName gives the first name alone there, and a
  -- key built on it is nobody's line on the site (issue #26).
  local surnames = GuildOS.Client.has.surnames
  UnitFullName = function() return "Chehul", "Costa" end
  GuildOS.Client.isAnniversary, GuildOS.Client.has.surnames = false, true
  GuildOS.db.members["Chehul Costa-Firemaw"] = mine
  logout()
  local forever = opened(GuildOSDB.__companion)
  assert(forever.game == "FOREVER" and forever.members[1].key == "Chehul Costa-Firemaw"
    and forever.members[1].name == "Chehul Costa" and forever.exportedBy == "Chehul Costa-Firemaw",
    "on Forever the line is the whole name's: " .. forever.members[1].key)
  assert(forever.founding == nil and forever.journal == nil and forever.tabard == nil, "and Forever's guild fields stay out")
  GuildOS.db.members["Chehul Costa-Firemaw"] = nil
  GuildOS.Client.isAnniversary, GuildOS.Client.has.surnames, UnitFullName = true, surnames, nil

  -- On: the export replaces the pack, and the pack is gone.
  switch(true)
  logout()
  files = onDisk(GuildOSDB)
  local whole = opened(files[1])
  assert(#files == 1 and whole.self == nil and #whole.members == #ROSTER and whole.rosterComplete == true,
    "switch on: the whole export and no pack")
  assert(GuildOSDB.__companionAt == NOW, "and it stamps when it was written, as it always has")
  -- Off again: the pack replaces the export.
  switch(false)
  logout()
  files = onDisk(GuildOSDB)
  assert(#files == 1 and opened(files[1]).self == true and #opened(files[1]).members == 1, "switch off: the pack and no export")

  -- On, and the export cannot be built: a pack left over from when it was off is not the good payload
  -- the writer keeps, it is what an officer's upload must never pick.
  local build = Companion.Build
  local function boom() error("no such thing on this client") end
  switch(true)
  Companion.Build = boom
  logout()
  assert(#onDisk(GuildOSDB) == 0, "switch on, no export: the pack does not stay")
  Companion.Build = build
  logout()
  local good = GuildOSDB.__companion
  assert(opened(good).self == nil, "the export is back")
  Companion.Build = boom
  logout()
  assert(GuildOSDB.__companion == good, "and a failed build still keeps a good export, as it always has")
  Companion.Build = function() return nil, "nobody in the guild has shared anything yet" end
  logout()
  assert(GuildOSDB.__companion == good, "as does one with nothing to say")
  Companion.Build = build

  -- Wrapped: an error in the pack costs nothing, and the switch's path never reaches it.
  switch(false)
  logout()
  before = GuildOSDB.__companion
  local level = UnitLevel
  UnitLevel = boom
  assert(pcall(logout), "an error in the pack does not leave the handler")
  assert(GuildOSDB.__companion == before, "and leaves the file as it was")
  UnitLevel = level
  local buildSelf, asked = Companion.BuildSelf, 0
  Companion.BuildSelf = function() asked = asked + 1; error("no such thing on this client") end
  switch(true)
  logout()
  assert(asked == 0 and opened(GuildOSDB.__companion).self == nil, "with the switch on the pack is not even asked")
  Companion.BuildSelf = buildSelf

  packText = assert(Companion:BuildSelf())
  switch(saved)
  GuildOSDB = nil
end

local text, countOrErr = GuildOS.Companion:Build()
if not text then
  io.stderr:write("BUILD FAILED: " .. tostring(countOrErr) .. "\n")
  os.exit(1)
end
io.stderr:write("members: " .. tostring(countOrErr) .. "  chars: " .. #text .. "\n")
io.write(PACK and packText or text)
