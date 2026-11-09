-- The loot defects of issue #294, run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/CoreManager.lua, Modules/Points.lua, Modules/LootMaster.lua and Modules/LootTracker.lua on
-- WoW: Forever:
--   * in DKP, the winner announced is the one the Master Loot window puts on top;
--   * the last award can be undone: its loot history line, its points and its pending trade go, and the
--     other officers forget it too;
--   * a new core's points start from the guild's settings, not from nothing;
--   * the Loot Tracker switch, off, records nothing.
--
--   luajit -e 'ADDON="."' tools/loot-undo.lua
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
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Lead", "Er" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetInstanceInfo() return "Onyxia's Lair", "raid", 9, "", 40, 0, false, 249 end
function GetRealmName() return "Realm" end
local NOW = 1791000000
function GetServerTime() return NOW end
function GetTime() return 1 end
time = os.time
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInRaid() return true end
function SendChatMessage() end
function GetLootMethod() return "master", 0 end
function GetNumGroupMembers() return 0 end
function UnitClass() return "Mage", "MAGE" end
function UnitName() return "Lead" end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CoreManager.lua")
dofile(ADDON .. "/Modules/Points.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
dofile(ADDON .. "/Modules/LootTracker.lua")
GuildOS.db = { settings = { lootSystem = "dkp" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { awardHistory = {} }, points = { config = { bossAward = 15, itemCost = 20 } },
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local CM, LM, P, LT = GuildOS.CoreManager, GuildOS.LootMaster, GuildOS.Points, GuildOS.LootTracker
P:Initialize()
GuildOS.IsOfficerByName = function() return true end

local sent = {}
LM.SafeSendAddon = function(_, _, payload) sent[#sent + 1] = payload end
LM.SafeSendChat = function() end
LM.SafeSendChatAuto = function() end
LM.StopListeningForRolls = function() end

-- ── 1. DKP: the announced winner is the window's top ───────────────
local LINK = "|cffa335ee|Hitem:16914::::::::60:::::|h[Netherwind Crown]|h|r"
LM.activeLoot = { link = LINK, itemId = 16914 }
LM.rolls = {
  ["Ana-Realm"] = { name = "Ana", rollType = "MS", roll = 99, dkp = 40, prioOrder = 1, softRes = true },
  ["Bo-Realm"] = { name = "Bo", rollType = "MS", roll = 10, dkp = 90 },
  ["Cy-Realm"] = { name = "Cy", rollType = "OS", roll = 100, dkp = 500 },
}
LM:EndRolling()
local top = LM.activeLoot.sortedResults[1]
check(top.name == "Bo", "in DKP the highest DKP among MS wins, whatever the officer prio, the reserve or the roll")
check(LM.activeLoot.sortedResults[3].name == "Cy", "and OS still comes after MS, whatever its DKP")

GuildOS.db.settings.lootSystem = "rolls"
LM.activeLoot = { link = LINK, itemId = 16914 }
LM.rolls = {
  ["Ana-Realm"] = { name = "Ana", rollType = "MS", roll = 1, dkp = 0, prioOrder = 1 },
  ["Bo-Realm"] = { name = "Bo", rollType = "MS", roll = 99, dkp = 90 },
}
LM:EndRolling()
check(LM.activeLoot.sortedResults[1].name == "Ana", "outside DKP the order is as it was: officer prio first")
GuildOS.db.settings.lootSystem = "dkp"

-- ── 2. Undo ────────────────────────────────────────────────────────
local function award(player, itemId, charged)
  local a = { link = LINK, itemId = itemId, player = player, timestamp = NOW, received = false }
  if charged then a.charged, a.chargedKey = charged, GuildOS:GetPlayerKey(player) end
  table.insert(GuildOS.db.lootMaster.awardHistory, 1, a)
  table.insert(GuildOS.db.lootHistory, 1, { itemLink = LINK, player = player, timestamp = NOW, fromML = true })
end
GuildOS.db.lootHistory = {}
LM.pendingTrades = { { player = "Bo", itemId = 16914, link = LINK } }
award("Ana", 16914)
award("Bo", 16914, 20)
local boKey = GuildOS:GetPlayerKey("Bo")
P:Charge(boKey, 20, "Netherwind Crown")
local before = P:Get(boKey)
local undone = LM:UndoLastAward()
check(undone and undone.player == "Bo", "undo takes back the newest award")
check(#GuildOS.db.lootHistory == 1 and GuildOS.db.lootHistory[1].player == "Ana", "its loot history line goes, the older one stays")
check(P:Get(boKey) == before + 20, "the points it cost go back")
check(#LM.pendingTrades == 0, "and the trade not yet made is dropped")
check(sent[#sent] == ("UNDO|Bo|16914|" .. NOW), "the other officers are told")
check(LM:UndoLastAward().player == "Ana", "a second undo takes the one before")
local none, why = LM:UndoLastAward()
check(none == nil and why == "No award to undo.", "and with nothing left, it says so")

-- A peer forgets the award it recorded on its own clock, when an officer says so.
GuildOS.db.lootHistory = { { itemLink = LINK, player = "Cy", timestamp = NOW + 40, fromML = true } }
LM:OnAddonMessage(LM.PREFIX, "UNDO|Cy|16914|" .. NOW, "RAID", "Other-Realm")
check(#GuildOS.db.lootHistory == 0, "a peer forgets the award, recorded 40 seconds apart")
GuildOS.db.lootHistory = { { itemLink = LINK, player = "Cy", timestamp = NOW, fromML = true } }
GuildOS.IsOfficerByName = function() return false end
LM:OnAddonMessage(LM.PREFIX, "UNDO|Cy|16914|" .. NOW, "RAID", "Pleb-Realm")
check(#GuildOS.db.lootHistory == 1, "but never on a non-officer's word")
GuildOS.IsOfficerByName = function() return true end

-- ── 3. A new core's points start from the guild's ──────────────────
CM:Create("Fresh")
local cfg = CM:GetPointsDB("Fresh").config
check(cfg.bossAward == 15 and cfg.itemCost == 20, "a new core awards what the guild awards, not 0")
cfg.bossAward = 5
check(CM:GetPointsDB("Fresh").config.bossAward == 5, "and what the core set stays its own")

-- ── 4. The Loot Tracker switch ─────────────────────────────────────
GuildOS.db.lootHistory = {}
GuildOS.db.settings.modules = { lootTracker = false }
LT:RecordMLAward({ itemLink = LINK, player = "Dee", timestamp = NOW, fromML = true })
check(#GuildOS.db.lootHistory == 0, "switched off, the loot history records nothing")
GuildOS.db.settings.modules = { lootTracker = true }
LT:RecordMLAward({ itemLink = LINK, player = "Dee", timestamp = NOW, fromML = true })
check(#GuildOS.db.lootHistory == 1, "switched on, it records as before")

print(("loot-undo: %d checks passed"):format(checks))
