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
  L = setmetatable({}, { __index = function(_, k) return k end }),
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
function BRutus:GetPlayerKey(name, realm)
  return name .. "-" .. (realm or GetRealmName())
end
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
  professions = { { name = "Leatherworking", rank = 375 }, { name = "Skinning", rank = 375 } },
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

local text, countOrErr = BRutus.Companion:Build()
if not text then
  io.stderr:write("BUILD FAILED: " .. tostring(countOrErr) .. "\n")
  os.exit(1)
end
io.stderr:write("members: " .. tostring(countOrErr) .. "  chars: " .. #text .. "\n")
io.write(text)
