-- Onyxia's attunement on WoW: Forever (Ricki), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/AttunementTracker.lua, Modules/Readiness.lua, Modules/RaidTools.lua and
-- Modules/CompanionExport.lua.
--
-- What this holds: on Forever the tracker exists with one table, Onyxia's Lair, a chain per faction; the
-- character's own faction's chain is the one read; its last quest, or the Drakefire Amulet (16309) in the bags
-- or the bank, is the attunement; with no faction known only the amulet speaks. It is the readiness panel's
-- only target, a report aimed at it holds a 60 who is not attuned as not ready (never one who never published),
-- Raid Tools' Onyxia asks for it, and the companion export carries it as `{ short = "Ony", complete, progress }`.
-- TBC Anniversary keeps its own table, unchanged.
--
--   luajit -e 'ADDON="."' tools/attunement-forever.lua
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

local done, items, faction = {}, {}, "Horde"
local ROSTER = { { "Tess Varn", 60 }, { "Mira Thornwood", 60 }, { "Orin Vale", 60 }, { "Kael Dunmore", 40 } }

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "71139", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Tess", "Varn" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Tess" end
  end
  function UnitFactionGroup() return faction end
  function GetRealmName() return "Normal" end
  function GetNormalizedRealmName() return "Normal" end
  function GetServerTime() return 1796774400 end
  function IsInGuild() return true end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i)
    local r = ROSTER[i]
    if r then return r[1], "Member", 5, r[2], "Mage", "", "", "", true, 0, "MAGE" end
  end
  C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end }
  C_Item = { GetItemCount = function(id, bank) return (items[id] or 0) + (bank and (items["bank" .. id] or 0) or 0) end }
  C_Timer = { After = function() end, NewTicker = function() end }
  Enum = { SendAddonMessageResult = {} }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/AttunementTracker.lua")
  dofile(ADDON .. "/Modules/Readiness.lua")
  GuildOS.db = { members = {}, settings = {}, myData = {} }
  return GuildOS
end

-- ── TBC Anniversary keeps its table ─────────────────────────────────────
local A = load("anniversary")
check(A.AttunementTracker.ATTUNEMENTS[1].short == "Kara" and #A.AttunementTracker.ATTUNEMENTS == 8, "Anniversary: TBC's eight, as before")
check(#A.AttunementTracker.HEROIC_KEYS == 5, "and its heroic keys")

-- ── WoW: Forever: Onyxia's Lair ─────────────────────────────────────────
local G = load("forever")
local AT = G.AttunementTracker
check(AT ~= nil and #AT.ATTUNEMENTS == 1 and AT.ATTUNEMENTS[1].short == "Ony", "Forever: one table, Onyxia's Lair")
check(#AT.HEROIC_KEYS == 0, "and no heroic keys")
local ony = AT.ATTUNEMENTS[1]
check(ony.keyItemId == 16309 and ony.unverified == true, "the Drakefire Amulet confirms it; the quest ids are marked unverified")
check(#ony.factions.Horde.quests == 14 and ony.factions.Horde.finalQuestId == 6602, "the Horde's chain ends with Blood of the Black Dragon Champion")
check(#ony.factions.Alliance.quests == 16 and ony.factions.Alliance.finalQuestId == 6502, "the Alliance's with Drakefire Amulet")
local cols = AT:GetGuildColumns()
check(#cols == 1 and cols[1].short == "Ony", "the attunement grid has Onyxia's column")

local me = G:GetPlayerKey("Tess Varn")
G.db.members[me] = { lastUpdate = 1 }
local function scan() return AT:ScanAttunements()[1] end
local e = scan()
check(e.short == "Ony" and e.complete == false and e.progress == 0 and e.questsTotal == 14, "nothing done: not attuned, 0 of 14")
for _, id in ipairs({ 4903, 4941, 4974, 6566, 6567, 6568, 6569 }) do done[id] = true end
e = scan()
check(e.complete == false and e.questsDone == 7 and math.abs(e.progress - 0.5) < 1e-9, "half the Horde's chain: 7 of 14")
done[6602] = true
e = scan()
check(e.complete == true, "the last quest of the chain is the attunement")
check(G.db.members[me].attunements[1] == e and G.db.myData.attunements[1] == e, "kept on my record, which the sync sends")
done = {}
items["bank16309"] = 1
e = scan()
check(e.complete == true and e.progress == 1, "the amulet in the bank is the attunement too")
items["bank16309"] = nil
faction = "Alliance"
done[6502] = true
e = scan()
check(e.complete == true and e.questsTotal == 16, "an Alliance character reads the Alliance's chain")
faction = nil
done = {}
items[16309] = 1
e = scan()
check(e.complete == true and e.questsTotal == 0, "with no faction known only the amulet speaks, and it says yes")
items[16309] = nil
e = scan()
check(e.complete == false, "and without it, no")
faction = "Horde"

-- ── Readiness and Raid Tools ────────────────────────────────────────────
local R = G.Readiness
local targets = R:GetTargets()
check(#targets == 1 and targets[1].short == "Ony", "the readiness panel can aim at Onyxia")
local key = function(n) return G:GetPlayerKey(n) end
G.db.members[key("Tess Varn")] = { attunements = { { short = "Ony", complete = true, progress = 1 } } }
G.db.members[key("Mira Thornwood")] = { attunements = { { short = "Ony", complete = false, progress = 0.5 } } }
G.db.members[key("Kael Dunmore")] = { attunements = { { short = "Ony", complete = true, progress = 1 } } }
-- Orin never published.
local by = {}
for _, r in ipairs(R:GetReport("Ony")) do by[r.name] = r end
check(by["Tess Varn"].status == "ready" and by["Tess Varn"].targetOk == true, "an attuned 60 is ready for Onyxia")
check(by["Mira Thornwood"].status == "notready" and by["Mira Thornwood"].reason == "attune", "a 60 not attuned is not ready, for the attunement")
check(by["Orin Vale"].status == "ready" and by["Orin Vale"].targetOk == nil and by["Orin Vale"].levelOnly, "who never published keeps the level rule")
check(by["Kael Dunmore"].status == "notready" and by["Kael Dunmore"].reason == "level", "a 40 is held by the level first")
by = {}
for _, r in ipairs(R:GetReport()) do by[r.name] = r end
check(by["Mira Thornwood"].status == "ready" and by["Mira Thornwood"].attDone == 0 and by["Mira Thornwood"].attTotal == 1,
  "aimed at nothing, the rule is guildos.me's, and the row still counts 0 of 1")

dofile(ADDON .. "/Modules/RaidTools.lua")
check(G.RaidTools:Instance("forever-onyxia").attune == "Ony", "Raid Tools' Onyxia asks for the attunement")

-- ── The companion export ────────────────────────────────────────────────
dofile(ADDON .. "/Modules/CompanionExport.lua")
local out = G.Companion.AttunementsFor(key("Mira Thornwood"))
check(#out == 1 and out[1].short == "Ony" and out[1].complete == false and out[1].progress == 0.5,
  "the export carries Onyxia's attunement in the field it always had")
out = G.Companion.AttunementsFor(key("Orin Vale"))
check(#out == 0, "and nothing for who never published")

print(("attunement-forever: %d checks passed"):format(checks))
