-- The loot rule (issue #333), run against the real Core/Core.lua, Modules/CoreManager.lua,
-- Modules/LootRule.lua and Modules/LootMaster.lua:
--   * every loot system of before, with every combination of the loot settings it read, is a
--     ready-made rule that puts any set of rollers in the order the code of before did;
--   * the Master Loot window and the roll's end read the same order;
--   * the attendance the guild asks for still turns a main spec answer into off spec;
--   * the winner line says what decided;
--   * bands tie what falls in the same step, and the next criterion decides;
--   * a rule this client cannot read whole is refused, and the loot system's stays in force;
--   * the guild's own rule, once an officer saves one, is the one in force.
--
--   luajit -e 'ADDON="."' tools/loot-rule.lua
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
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
GuildOS.db = { settings = { lootSystem = "rolls" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { awardHistory = {} },
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local LM, LR = GuildOS.LootMaster, GuildOS.LootRule
GuildOS.IsOfficer = function() return true end

local said = {}
LM.SafeSendAddon = function() end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.StopListeningForRolls = function() end

-- ── The order of before, as the code had it in LootMaster:EndRolling ─
local function legacyBefore(dkpMode, cfg)
  return function(a, b)
    if a.rollType ~= b.rollType then return a.rollType == "MS" end
    if dkpMode then
      local ad, bd = a.dkp or 0, b.dkp or 0
      if ad ~= bd then return ad > bd end
      return a.roll > b.roll
    end
    local aPrio, bPrio = a.prioOrder or 999, b.prioOrder or 999
    if aPrio ~= bPrio then return aPrio < bPrio end
    local aSR, bSR = a.softRes and 1 or 2, b.softRes and 1 or 2
    if aSR ~= bSR then return aSR < bSR end
    local aOrder = a.wishlist and a.wishlist.order or 999
    local bOrder = b.wishlist and b.wishlist.order or 999
    if aOrder ~= bOrder then return aOrder < bOrder end
    if cfg.recvPenalty ~= false then
      local aRecv, bRecv = a.recvCount or 0, b.recvCount or 0
      if aRecv ~= bRecv then return aRecv < bRecv end
    end
    if cfg.attTiebreaker and (a.att25 or 0) ~= (b.att25 or 0) then
      return (a.att25 or 0) > (b.att25 or 0)
    end
    return a.roll > b.roll
  end
end

-- A raid's rollers, with rolls that never tie (a tie was settled by nothing before).
local seed = 20261114
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
local function rollers(n)
  local list, rolls = {}, {}
  for i = 1, n do
    local roll
    repeat roll = 1 + rnd(1000) until not rolls[roll]
    rolls[roll] = true
    list[i] = {
      name = "P" .. i, rollType = rnd(3) == 0 and "OS" or "MS", roll = roll,
      prioOrder = rnd(4) == 0 and (1 + rnd(3)) or nil,
      softRes = rnd(3) == 0 and { hard = rnd(2) == 0 } or nil,
      wishlist = rnd(2) == 0 and { order = 1 + rnd(4) } or nil,
      recvCount = rnd(3), att25 = rnd(5) * 25, dkp = rnd(4) * 10,
    }
  end
  return list
end
local function names(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.name end
  return table.concat(out, ",")
end

local combos = 0
for _, system in ipairs({ "rolls", "tmb", "wishlist", "dkp" }) do
  for _, recv in ipairs({ true, false }) do
    for _, att in ipairs({ true, false }) do
      for _, minAtt in ipairs({ 0, 50 }) do
        local cfg = { recvPenalty = recv, attTiebreaker = att, minAttendancePct = minAtt }
        local rule = LR:FromLegacy(system, cfg)
        check(LR:Validate(rule), system .. ": the ready-made rule is one this client reads")
        for _ = 1, 40 do
          local a = rollers(12)
          local b = {}
          for i, r in ipairs(a) do b[i] = r end
          table.sort(a, legacyBefore(system == "dkp", cfg))
          LR:Sort(b, rule)
          check(names(a) == names(b), string.format(
            "%s (recv %s, att %s): the rule's order is the order of before\n  before: %s\n  rule:   %s",
            system, tostring(recv), tostring(att), names(a), names(b)))
        end
        combos = combos + 1
      end
    end
  end
end
check(combos == 32, "every system and every combination of its settings was compared")

-- ── The roll's end and the Master Loot window read the rule in force ─
local LINK = "|cffa335ee|Hitem:16914::::::::60:::::|h[Netherwind Crown]|h|r"
local function endRoll(rolls)
  said = {}
  LM.activeLoot = { link = LINK, itemId = 16914 }
  LM.rolls = rolls
  LM:EndRolling(true)
  return LM.activeLoot.sortedResults
end
local res = endRoll({
  a = { name = "Ana", rollType = "MS", roll = 5, recvCount = 0 },
  b = { name = "Bo", rollType = "MS", roll = 90, recvCount = 1 },
  c = { name = "Cy", rollType = "PASS", roll = 0 },
})
check(#res == 2 and res[1].name == "Ana", "a pass is no candidate, and fewer items received comes before the roll")
check(LM.activeLoot.decidedBy == "received", "the roll's end keeps what decided")
check(said[#said]:find("fewer items received", 1, true), "and the winner line says it: " .. tostring(said[#said]))

res = endRoll({
  a = { name = "Ana", rollType = "MS", roll = 5 },
  b = { name = "Bo", rollType = "MS", roll = 90 },
})
check(res[1].name == "Bo" and not said[#said]:find("[by", 1, true), "decided by the roll, the line says only the roll")

res = endRoll({ a = { name = "Ana", rollType = "MS", roll = 5 } })
check(res[1].name == "Ana" and LM.activeLoot.decidedBy == nil, "one candidate: nothing decided")

-- ── Who may ask: below the attendance asked, main spec is read as off spec ──
GuildOS.db.lootMaster.minAttendancePct = 50
LM.GetPlayerContext = function(_, name) return { att25 = name == "Low" and 20 or 80, recvThisLockout = 0 } end
said = {}
LM.activeLoot = { link = LINK, itemId = 16914 }
LM.rolls = {}
LM:RegisterRoll("Low", "MS", 99)
LM:RegisterRoll("High", "MS", 2)
check(LM.rolls[GuildOS:GetPlayerKey("Low")].rollType == "OS", "20% of attendance under a minimum of 50%: read as OS")
check(LM.rolls[GuildOS:GetPlayerKey("High")].rollType == "MS", "80% keeps its MS")
check(said[1] and said[1]:find("MS converted to OS", 1, true), "and the raid is told, as before")
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "High", "so the MS that stood wins over the higher roll")
GuildOS.db.lootMaster.minAttendancePct = 0

-- ── Bands ───────────────────────────────────────────────────────────
local banded = { v = 1, order = { { k = "attendance", band = 10 }, { k = "roll" } } }
check(LR:Validate(banded), "a band is part of a rule")
local list = LR:Sort({
  { name = "A", att25 = 91, roll = 10 }, { name = "B", att25 = 99, roll = 5 }, { name = "C", att25 = 89, roll = 100 },
}, banded)
check(names(list) == "A,B,C", "91% and 99% fall in the same step of 10 and the roll decides; 89% is a step below")

-- ── A rule this client cannot read whole ────────────────────────────
local function refused(rule, what) check(not LR:Validate(rule), "refused: " .. what) end
refused(nil, "nothing")
refused({ v = 2, order = { { k = "roll" } } }, "a version from the future")
refused({ v = 1, order = {} }, "no order")
refused({ v = 1, order = { { k = "parse" } } }, "a criterion this client never heard of")
refused({ v = 1, order = { { k = "roll" }, { k = "roll" } } }, "a criterion twice")
refused({ v = 1, order = { { k = "roll", band = 0 } } }, "a band of zero")
refused({ v = 1, order = { { k = "roll" } }, filters = { { k = "rank" } } }, "a filter it does not know")
refused({ v = 1, order = { { k = "roll" } }, responses = { "MS", "PASS" } }, "a pass as an answer")
local long = { v = 1, order = {} }
for i, k in ipairs(LR.CRITERIA_ORDER) do long.order[i] = { k = k } end
check(LR:Validate(long), "all nine criteria are a rule")
long.order[10] = { k = "roll" }; long.order[11] = { k = "roll" }
refused(long, "more than ten criteria")

-- ── The guild's own rule, and the core's over it ────────────────────
local rollFirst = { v = 1, order = { { k = "response" }, { k = "roll" } } }
GuildOS.db.settings.lootRule = { v = 1, order = { { k = "nonsense" } } }
check(LR:Active().model == "rolls", "a kept rule that cannot be read leaves the loot system's in force")
check(LR:Set(rollFirst) == true and LR:Active() == rollFirst, "an officer's rule is the one in force")
res = endRoll({
  a = { name = "Ana", rollType = "MS", roll = 5, prioOrder = 1 },
  b = { name = "Bo", rollType = "MS", roll = 90 },
})
check(res[1].name == "Bo", "and the roll's end follows it: no officer prio in this rule")
local ok, why = LR:Set({ v = 1, order = {} })
check(ok == false and why and LR:Active() == rollFirst, "a rule that is not one is not saved")
GuildOS.IsOfficer = function() return false end
check(LR:Set(nil) == false and LR:Active() == rollFirst, "and only an officer changes it")
GuildOS.IsOfficer = function() return true end
check(LR:Set(nil) == true and LR:Active().model == "rolls", "nil goes back to the loot system's rule")

GuildOS.db.settings.lootSystem = "dkp"
check(LR:Active().model == "dkp" and LR:Active().order[2].k == "points", "the loot system's rule follows the system")

print(("loot-rule: %d checks passed"):format(checks))
