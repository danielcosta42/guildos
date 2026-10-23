-- Mythic+ and the Great Vault on retail (issue #187), run against the real Core files,
-- Modules/MythicPlus.lua and Modules/DataCollector.lua under a stubbed retail client and a stubbed
-- WoW: Forever one.
--
-- Nothing read Mythic+ or delves. Each member's own client now reads its keystone, its rating and its
-- weekly vault (raid, dungeons, and the world row a delve fills) through Compat, never a secret value,
-- keeps them in its member record and sends them with the member data, where an older addon simply
-- has none (absent, not null). The member sheet shows them, the vault only for this week, and the
-- roster offers a column for them on retail alone. Forever reads none of it.
--
--   luajit -e 'ADDON="."' tools/retail-mplus.lua
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

local SECRET = setmetatable({}, { __index = function() error("indexed a secret value") end })
local NOW, WEEK_START = 1791000000, 1790900000
local ARA_KARA = 503
local score, keyMap, keyLevel, activities, timers, sent = 2450.4, ARA_KARA, 12, nil, {}, 0
local ROSTER = { "Ana-Azralon", "Bia-Gallywix" }

local function load(retail)
  score, keyMap, keyLevel, activities, timers, sent = 2450.4, ARA_KARA, 12, nil, {}, 0
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  local frames = {}
  function CreateFrame()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = f
    return f
  end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return NOW end
  time = function() return NOW end
  function GetRealmName() return "Azralon" end
  function GetNormalizedRealmName() return "Azralon" end
  function IsInGuild() return true end
  function UnitName() return "Ana" end
  function UnitClass() return "Mage", "MAGE" end
  function UnitLevel() return 90 end
  function UnitRace() return "Human", "Human" end
  function UnitSex() return 3 end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i) if ROSTER[i] then return ROSTER[i], "Raider", 3, 90, "Mage", "", "", "", true, 0, "MAGE" end end
  issecretvalue = function(v) return v == SECRET end
  C_ChallengeMode = {
    GetOverallDungeonScore = function() return score end,
    GetMapUIInfo = function(id) if id == ARA_KARA then return "Ara-Kara, Cidade dos Ecos", id end end,
    GetDungeonScoreRarityColor = function(s) return { r = s / 10000, g = 0.5, b = 1 } end,
  }
  C_MythicPlus = { RequestMapInfo = function() GuildOS._requested = true end,
                   GetOwnedKeystoneChallengeMapID = function() return keyMap end,
                   GetOwnedKeystoneLevel = function() return keyLevel end }
  C_WeeklyRewards = { GetActivities = function() return activities end }
  C_DateAndTime = { GetWeeklyResetStartTime = function() return WEEK_START end }
  Enum = { WeeklyRewardChestThresholdType = { Activities = 1, RankedPvP = 2, Raid = 3, World = 6 },
           SendAddonMessageResult = {} }
  C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end,
              NewTicker = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return true end
  function GuildOS:RefreshRosterUI() end
  GuildOS.db = { settings = { modules = {} }, members = {} }
  dofile(ADDON .. "/Modules/DataCollector.lua")
  dofile(ADDON .. "/Modules/MythicPlus.lua")
  GuildOS.CommSystem = { BroadcastMyData = function() sent = sent + 1 end }
  local DC = GuildOS.DataCollector
  DC.CollectGear = function() return {}, false end
  DC.CollectProfessions = function() return {} end
  DC.CollectStats = function() return {} end
  DC.CalculateAvgIlvl = function() return 0 end
  return DC, GuildOS.MythicPlus, frames
end

local function runTimers()
  local list = timers
  timers = {}
  for _, fn in ipairs(list) do fn() end
end
local function fire(frames, event)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
  end
end
local function slot(kind, index, threshold, progress, level)
  return { type = kind, index = index, threshold = threshold, progress = progress, level = level, id = index }
end
-- This week: raid 5 bosses (Heroic for the first slot, Raid Finder for the second), dungeons 4 runs
-- (+12 and +10), the world row 8 activities (delve tiers 8, 8 and 6), and a PvP row nobody asked for.
local WEEK = {
  slot(3, 1, 2, 5, 15), slot(3, 2, 4, 5, 17), slot(3, 3, 6, 5, 16),
  slot(1, 1, 1, 4, 12), slot(1, 2, 4, 4, 10), slot(1, 3, 8, 4, 0),
  slot(6, 1, 2, 8, 8), slot(6, 2, 4, 8, 8), slot(6, 3, 8, 8, 6),
  slot(2, 1, 1250, 900, 0),
}

-- ── 1. What Compat reads ──────────────────────────────────────────────
local DC, MP, frames = load(true)
local Compat = GuildOS.Compat
check(GuildOS.Client.isRetail and MP ~= nil, "the Mythic+ module exists on retail")
local m = Compat.MythicPlus()
check(m and m.rating == 2450 and m.key and m.key.map == ARA_KARA and m.key.level == 12, "my rating and my keystone")
keyMap, keyLevel = nil, 0
m = Compat.MythicPlus()
check(m and m.rating == 2450 and m.key == nil, "no keystone held: the key is left out, the rating stays")
keyMap, keyLevel = ARA_KARA, SECRET
check(Compat.MythicPlus() == nil, "a secret keystone: nothing, rather than a wrong 'no key'")
keyLevel, score = 12, SECRET
check(Compat.MythicPlus() == nil, "a secret rating: nothing")
score = nil
check(Compat.MythicPlus() == nil, "no rating to give: nothing")
score = 2450.4
check(Compat.ChallengeMapName(ARA_KARA) == "Ara-Kara, Cidade dos Ecos" and Compat.ChallengeMapName(1) == nil,
  "a dungeon is named by the reader's client, by its id")
local r, g, b = Compat.RatingColor(2450)
check(r == 0.245 and g == 0.5 and b == 1 and Compat.RatingColor(nil) == nil, "the rating's colour is the game's")
check(Compat.WeekStart() == WEEK_START, "the week starts at the client's last weekly reset")

activities = WEEK
local rows = Compat.WeeklyActivities()
check(rows and #rows == 9, "the raid, dungeon and world rows' slots; the PvP row is not asked for")
check(rows[1].row == "raid" and rows[4].row == "dungeon" and rows[7].row == "world", "each slot knows its row")
local enum = Enum
Enum = nil
check(#Compat.WeeklyActivities() == 9, "a client that names no threshold types reads 12.1.5's numbers")
Enum = enum
activities = { slot(3, 1, 2, SECRET, 15) }
check(Compat.WeeklyActivities() == nil, "a secret field: nothing")
activities = SECRET
check(Compat.WeeklyActivities() == nil, "a secret list: nothing")
activities = {}
check(Compat.WeeklyActivities() == nil, "no activities yet: nothing")

-- ── 2. The vault summed up ────────────────────────────────────────────
local vault = MP:SumVault(Compat.WeeklyActivities(), NOW)   -- still none
check(vault == nil and MP:SumVault({}, NOW) == nil, "no slots, no vault")
activities = WEEK
vault = MP:SumVault(Compat.WeeklyActivities(), NOW)
check(vault.at == NOW, "stamped with when it was read")
check(vault.raid.n == 2 and vault.raid.best == 15, "raid: two slots, the best Heroic (Raid Finder's 17 is not higher)")
check(vault.dungeon.n == 2 and vault.dungeon.best == 12, "dungeons: two slots, the best +12")
check(vault.world.n == 3 and vault.world.best == 8, "world: three slots, the best delve tier 8")
local cells = MP:VaultCells(vault, WEEK_START)
local function text(cs) local out = {} for _, c in ipairs(cs) do out[#out + 1] = c.label .. "=" .. c.text end return table.concat(out, " ") end
check(text(cells) == "Raid=2/3 \194\183 H Dungeons=2/3 \194\183 +12 World=3/3 \194\183 Tier 8", "the sheet's three cells: " .. text(cells))
local stale, why = MP:VaultCells({ at = WEEK_START - 1, raid = { n = 3, best = 16 } }, WEEK_START)
check(stale == nil and why == "old", "a vault read before this week's reset is last week's, not shown as this one")
local ok, odd = pcall(MP.VaultCells, MP, { at = NOW, raid = { n = "lots", best = {} }, dungeon = "x", world = { n = 9, best = 3 } }, WEEK_START)
check(ok and text(odd) == "Raid=0/3 Dungeons=0/3 World=3/3 \194\183 Tier 3",
  "a guildmate's vault that is not numbers draws zeros, and no row passes three: " .. tostring(ok and text(odd) or odd))
check(MP:VaultCells("nonsense", WEEK_START) == nil, "and a vault that is not a table draws nothing")
check(MP:VaultCells({ at = 1, raid = { n = 1, best = 14 } }, nil) ~= nil, "with no reset to compare, the vault shows")

-- ── 3. Rating and keystone, as a reader shows them ───────────────────
check(MP:Rating({ rating = 2450.9 }) == 2450 and MP:Rating({ rating = "x" }) == nil and MP:Rating(nil) == nil,
  "the rating, or nothing")
check(MP:KeystoneText({ key = { map = ARA_KARA, level = 12 } }) == "Ara-Kara, Cidade dos Ecos +12", "the keystone, named by the reader")
check(MP:KeystoneText({ key = { map = 9999, level = 7 } }) == "Unknown dungeon +7", "a dungeon this client does not know")
check(MP:KeystoneText({ rating = 1 }) == nil and MP:KeyLevel({ key = { level = 0 } }) == nil and MP:KeyLevel({ key = "x" }) == nil,
  "no keystone, no text")

-- ── 4. My record, and what goes out ──────────────────────────────────
MP:Initialize()
check(GuildOS._requested, "the season's data is asked for at start-up")
local data = DC:CollectMyData()
check(data.mplus == nil and data.vault and data.vault.raid.n == 2,
  "before the season's data has arrived no rating is kept (a 0 would overwrite the real one); the vault is")
fire(frames, "CHALLENGE_MODE_MAPS_UPDATE")
fire(frames, "WEEKLY_REWARDS_UPDATE")
check(#timers == 1, "two events, one send waiting")
runTimers()
check(sent == 1, "it goes out through the member broadcast")
fire(frames, "CHALLENGE_MODE_COMPLETED")
runTimers()
check(sent == 2, "a run's end sends again")
data = DC:CollectMyData()
check(data.mplus and data.mplus.rating == 2450 and data.mplus.key.level == 12, "once it has, my rating and keystone are kept")
local out = DC:GetBroadcastData()
check(out.mplus and out.mplus.rating == 2450 and out.vault and out.vault.world.best == 8, "and sent with my member data")
score, activities = SECRET, nil
data = DC:CollectMyData()
check(data.mplus.rating == 2450 and data.vault.raid.n == 2, "what the client cannot give now keeps what was read, never blanked")
score, activities = 2450.4, WEEK

-- A guildmate's broadcast: theirs is stored; an older addon's, without the fields, leaves it.
DC:StoreReceivedData("Bia-Gallywix", { name = "Bia", class = "MAGE", lastUpdate = NOW,
  mplus = { rating = 3100, key = { map = ARA_KARA, level = 15 } }, vault = { at = NOW, world = { n = 1, best = 11 } } })
check(GuildOS.db.members["Bia-Gallywix"].mplus.rating == 3100, "a guildmate's Mythic+ is stored")
DC:StoreReceivedData("Bia-Gallywix", { name = "Bia", class = "MAGE", lastUpdate = NOW + 5 })
check(GuildOS.db.members["Bia-Gallywix"].mplus.rating == 3100 and GuildOS.db.members["Bia-Gallywix"].vault.world.n == 1,
  "a broadcast without them (an older addon) leaves what was there")
local rec = GuildOS:GetMemberRecord("Bia", "Gallywix")
check(rec and rec.mplus and rec.mplus.rating == 3100 and rec.vault and rec.vault.world.best == 11,
  "the member sheet's record carries them")

-- ── 5. Forever reads none of it ──────────────────────────────────────
DC, MP = load(false)
check(not GuildOS.Client.isRetail and MP == nil, "the Mythic+ module does not exist on Forever")
check(Compat ~= GuildOS.Compat and GuildOS.Compat.MythicPlus() == nil and GuildOS.Compat.WeeklyActivities() == nil,
  "Compat reads no Mythic+ or vault there")
GuildOS.db.myData = { name = "Ana", realm = "Azralon", class = "MAGE", mplus = { rating = 1 }, vault = { at = 1 } }
out = DC:GetBroadcastData()
check(out.mplus == nil and out.vault == nil, "and sends none, even one held from somewhere")
GuildOS.db.members[GuildOS:GetPlayerKey("Ana", "Azralon")] = { mplus = { rating = 1 } }
data = DC:CollectMyData()
check(data.mplus and data.mplus.rating == 1, "nor touches what is stored")

-- ── 6. Where it shows ────────────────────────────────────────────────
local function src(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local roster = src("UI/RosterFrame.lua")
check(roster:find('{ key = "mplus",', 1, true) and roster:find('offered = function() return GuildOS.MythicPlus ~= nil end', 1, true),
  "the roster's M+ column is offered only where the module is (retail)")
check(roster:find("mplus = addonData.mplus,", 1, true) and roster:find("vault = addonData.vault,", 1, true),
  "and a roster row carries them to the member sheet")
GuildOS = {}
dofile(ADDON .. "/Modules/RosterColumns.lua")
local default = table.concat(GuildOS.RosterColumns.DEFAULT, ",")
check(not default:find("mplus", 1, true), "it is optional: not in the default columns")
local sheet = src("UI/MemberDetail.lua")
check(sheet:find('if MP and (type(data.mplus) == "table" or type(data.vault) == "table") then', 1, true)
  and sheet:find("MP:VaultCells(data.vault, GuildOS.Compat.WeekStart())", 1, true),
  "the member sheet shows Mythic+ and the vault only with the module and a member's own data")
local toc = src("GuildOS.toc")
check(toc:find("Modules\\MythicPlus.lua", 1, true) and toc:find("Data\\ConsumablesRetail.lua\r?\nModules\\ConsumableChecker.lua"),
  "the TOC loads the module, and the consumables table before its checker")
check(src("Core/Core.lua"):find('{ "MythicPlus" },', 1, true), "and the module starts with the others")

print(("retail-mplus: %d checks passed"):format(checks))
