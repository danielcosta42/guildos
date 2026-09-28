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
function GetGuildInfo() return "Raid Guild" end
-- The module hangs a PLAYER_LOGOUT frame off the file scope so the payload
-- lands in SavedVariables for the desktop companion. Nothing here fires it;
-- the stub only has to let the file load.
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function() end }
end
function GetRealmName() return "Firemaw" end
function UnitName() return "Chehul" end
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
BRutus = {
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
BRutus.db.raidTracker = {
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
BRutus.CoreManager = {
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
function BRutus:GetSetting(key) return self.db.settings[key] end
function BRutus:SetSetting(key, v) self.db.settings[key] = v end

BRutus.GearAudit = { GetEnchantableSlots = function() return { 1, 3, 5, 7, 8, 9, 10, 15, 16 } end }

BRutus.RaidTracker = {
  GetAttendance25ManPercent = function(_, key)
    return ({ ["Chehul-Firemaw"] = 92, ["Fulano-Firemaw"] = 78 })[key] or 0
  end,
}

BRutus.AttunementTracker = {
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
BRutus.db.members["Chehul-Firemaw"] = {
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
BRutus.db.members["Fulano-Firemaw"] = {
  race = "Human", avgIlvl = 128, lastUpdate = 1754398000,
  spec = { tree = "Holy", treeIndex = 2, points = { 23, 38, 0 } },
  professions = {},
  gear = nil,                                                       -- never synced gear
}

BRutus.LootTracker = {
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
local anniversary = BRutus.Companion:BuildPayload()
assert(anniversary.game == "ANNIVERSARY", "an Anniversary client did not say so")
assert(anniversary.v >= 6, "the payload that says its game is v6")
BRutus.Client.isAnniversary = false
assert(BRutus.Companion:BuildPayload().game == "FOREVER", "a Forever client did not say so")
BRutus.Client.isAnniversary = true

-- v7 (issue #35): on Forever each member carries the profession model's lines by skill-line
-- ID -- rank, max, specialization and the recipes they know, or only the line for a member
-- known from the guild roster. Absent where there is no model, or no record of the member.
assert(anniversary.v >= 7, "the payload that carries crafting is v7")
for _, m in ipairs(anniversary.members) do
  assert(m.crafting == nil, "no profession model (Anniversary): no crafting key for " .. m.key)
end
-- The real module (it loads only on Forever), over its saved records -- a stub here once hid
-- that the export called a function this branch did not have.
BRutus.Client.isAnniversary = false
BRutus.db.professions = {
  ["Chehul-Firemaw"] = { src = "addon", ts = 1, profs = {
    [393] = { rank = 300, max = 300, n = 0, h = 0, recipes = {}, extra = {} },
    [165] = { rank = 285, max = 300, spec = 10656, n = 3, h = 1, recipes = { 3304, 2657 }, extra = { 999001 } } } },
  ["Fulano-Firemaw"] = { src = "native", ts = 1, profs = { [171] = {} } },
}
dofile(ADDON .. "/Modules/Professions.lua")
local forever = BRutus.Companion:BuildPayload()
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
BRutus.db.professions["Semdados-Firemaw"] = { src = "addon", ts = 1, profs = {
  [164] = { rank = 120, max = 150, n = 4, h = 2, stale = { 2660, 2663 }, staleExtra = {} } } }
local stale = {}
for _, m in ipairs(BRutus.Companion:BuildPayload().members) do stale[m.key] = m end
local s = stale["Semdados-Firemaw"].crafting
assert(s and #s == 1 and s[1].rank == 120 and #s[1].recipes == 2, "a stale list stands in while the new one travels")
BRutus.db.professions["Semdados-Firemaw"].profs[164].stale = nil
for _, m in ipairs(BRutus.Companion:BuildPayload().members) do stale[m.key] = m end
assert(stale["Semdados-Firemaw"].crafting == nil, "a list still on its way: no crafting key, the site keeps its own")
BRutus.Professions, BRutus.db.professions = nil, nil
BRutus.Client.isAnniversary = true

for _, m in ipairs(anniversary.members) do
  if m.key == "Chehul-Firemaw" then
    assert(#m.professions == 2 and m.professions[1].name == "Leatherworking" and m.professions[2].name == "Skinning",
      "a profession with no rank is not exported (issue #31)")
  end
end

local text, countOrErr = BRutus.Companion:Build()
if not text then
  io.stderr:write("BUILD FAILED: " .. tostring(countOrErr) .. "\n")
  os.exit(1)
end
io.stderr:write("members: " .. tostring(countOrErr) .. "  chars: " .. #text .. "\n")
io.write(text)
