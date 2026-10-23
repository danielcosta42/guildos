-- The raid's consumables on retail (issue #187), run against the real Core/Compat.lua,
-- Data/ConsumablesRetail.lua, Modules/ConsumableChecker.lua, Modules/RaidTracker.lua and
-- Modules/Readiness.lua under a stubbed retail client, with a WoW: Forever one and a TBC Anniversary
-- one beside it.
--
-- Retail had no consumable check: the TBC table was all there was. It comes with Midnight's flask,
-- food and augment rune by spell id (tools/consumable_catalog.py, from the client's own data) and my
-- own weapon's oil. Midnight keeps auras secret in combat and in instances, so the check reads out of
-- combat (the ready check, before the pull), and whatever it could not read is unknown, never missing:
-- no "missing" line, no penalty. A snapshot the pull takes in combat answers with the reading from the
-- ready check. This proves all of it, that the score and the site count an unknown snapshot alike,
-- that Forever still has no check, and that Anniversary's TBC verdict is the one it always was.
--
--   luajit -e 'ADDON="."' tools/retail-consumables.lua
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
local FLASK, FOOD, HEARTY, RUNE = 1235108, 1232318, 1233703, 1264426   -- Midnight's, from the catalog
local OTHER = 1126                                                     -- a raid buff (Mark of the Wild)
local TBC_FLASK, TBC_FOOD = 28521, 33254

local frames, clock, combat, aurasSecret, weapon = {}, 1000, false, false, true
local GROUP, AURAS = {}, {}

local function load(game)
  frames, clock, combat, aurasSecret, weapon = {}, 1000, false, false, true
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  if game == "retail" then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  elseif game == "forever" then
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  else
    function GetBuildInfo() return "2.5.6", "70006", "", 20506 end
    WOW_PROJECT_ID = 5
  end
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = f
    return f
  end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return 1791000000 end
  function GetTime() return clock end
  time = function() return 1791000000 end
  function GetRealmName() return "Azralon" end
  function GetNormalizedRealmName() return "Azralon" end
  function IsInGuild() return true end
  function IsInRaid() return #GROUP > 0 end
  function GetNumGroupMembers() return #GROUP end
  local function member(unit) return GROUP[tonumber(tostring(unit):match("^raid(%d+)$") or "")] end
  function UnitExists(unit) return unit == "player" or member(unit) ~= nil end
  function UnitIsConnected() return true end
  function UnitName(unit)
    if unit == "player" then return "Ana" end
    local m = member(unit)
    if m then return m[1], m[2] end
  end
  function UnitClass() return "Mage", "MAGE" end
  function UnitIsUnit(a, b) return b == "player" and (a == "player" or (member(a) and member(a)[1] == "Ana")) end
  function InCombatLockdown() return combat end
  issecretvalue = function(v) return v == SECRET end
  C_Secrets = { ShouldAurasBeSecret = function() return aurasSecret end }
  C_UnitAuras = { GetBuffDataByIndex = function(unit, i)
    local list = AURAS[unit] or (member(unit) and AURAS[member(unit)[1]])
    local a = list and list[i]
    if a == nil then return nil end
    if a == SECRET then return SECRET end
    return { name = "Buff " .. tostring(a), spellId = a }
  end }
  C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id } end }
  function GetWeaponEnchantInfo() return weapon end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:Print() end
  function GuildOS:IsOfficer() return true end
  GuildOS.db = { settings = { modules = {} }, members = {}, consumableChecks = { lastResults = {} },
                 raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
  dofile(ADDON .. "/Data/ConsumablesRetail.lua")
  dofile(ADDON .. "/Modules/ConsumableChecker.lua")
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  dofile(ADDON .. "/Modules/Readiness.lua")
  return GuildOS.ConsumableChecker
end

local function fire(event)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
  end
end
local function joined(list) return table.concat(list or {}, ",") end

-- ── 1. Retail has the check, with Midnight's buffs ─────────────────────
local CC = load("retail")
check(GuildOS.Client.isRetail and CC ~= nil, "the consumable check exists on retail")
check(GuildOS.ConsumableCatalog.build == "12.1.5.70448", "Midnight's buffs, generated from 12.1.5.70448")
check(CC.CONSUMABLES.flask.buffs[FLASK] and CC.CONSUMABLES.food.buffs[FOOD] and CC.CONSUMABLES.food.buffs[HEARTY]
  and CC.CONSUMABLES.rune.buffs[RUNE], "a Midnight flask, a Well Fed, a Hearty Well Fed and the augment rune are known")
check(not CC.CONSUMABLES.flask.buffs[TBC_FLASK] and not CC.CONSUMABLES.battleElixir,
  "no TBC flask, and no elixirs: Midnight has none")
local catalog = GuildOS.ConsumableCatalog
check(#catalog.flask == 4 and #catalog.rune == 1 and #catalog.food > 50, "four flasks, one rune and the expansion's food")

-- ── 2. What Compat reads ──────────────────────────────────────────────
AURAS = { player = { OTHER, FLASK } }
local ids, complete = GuildOS.Compat.UnitBuffIDs("player")
check(joined(ids) == OTHER .. "," .. FLASK and complete == true, "a unit's buff ids, all of them")
AURAS.player = { OTHER, SECRET, FLASK }
ids, complete = GuildOS.Compat.UnitBuffIDs("player")
check(joined(ids) == OTHER .. "," .. FLASK and complete == false, "a buff the client keeps secret is passed over: the list is partial")
check(GuildOS.Compat.UnitBuffIDs(SECRET) == nil, "a secret unit token reads nothing")
AURAS.player = {}
check(GuildOS.Compat.UnitBuffIDs("player") == nil, "a unit showing no buff at all reads nothing: its auras did not arrive")
-- Retail has no 40-buff cap: forty read and a forty-first there is a partial list.
local many = {}
for i = 1, 40 do many[i] = OTHER end
AURAS.player = many
ids, complete = GuildOS.Compat.UnitBuffIDs("player")
check(#ids == 40 and complete == true, "exactly forty buffs are the whole list")
many[41] = FLASK
ids, complete = GuildOS.Compat.UnitBuffIDs("player")
check(#ids == 40 and complete == false, "a forty-first makes the list partial")
GROUP = {}
local past = CC:ReadUnit("player")
check(past.flask == nil, "so a flask past slot forty is unknown, never missing")
many[41] = SECRET
ids, complete = GuildOS.Compat.UnitBuffIDs("player")
check(complete == false, "a secret forty-first too")
AURAS.player = { FLASK }
combat = true
check(GuildOS.Compat.UnitBuffIDs("player") == nil and GuildOS.Compat.MainHandTempEnchant() == nil,
  "in combat nothing is read")
combat, aurasSecret = false, true
check(GuildOS.Compat.UnitBuffIDs("player") == nil, "nor while the client says auras are secret")
aurasSecret = SECRET
check(GuildOS.Compat.UnitBuffIDs("player") == nil, "nor when even that answer is secret")
aurasSecret = false
check(GuildOS.Compat.MainHandTempEnchant() == true, "my weapon's temporary enchant is read")
weapon = SECRET
check(GuildOS.Compat.MainHandTempEnchant() == nil, "a secret answer about it is unknown")
weapon = nil
check(GuildOS.Compat.MainHandTempEnchant() == false, "and none is none")
weapon = true

-- ── 3. /gos cons on retail ────────────────────────────────────────────
-- raid1 is me; Bia has everything; Cid has a raid buff and no flask; Dan's buffs are partly secret and
-- none is a flask; Eva is out of range (no aura reached the client).
GROUP = { { "Ana" }, { "Bia" }, { "Cid" }, { "Dan" }, { "Eva", "Gallywix" } }
AURAS = { Ana = { FLASK, FOOD, RUNE }, Bia = { OTHER, FLASK, HEARTY, RUNE }, Cid = { OTHER, FOOD },
          Dan = { OTHER, SECRET, FOOD }, Eva = {} }
local res = CC:CheckRaid()
local key = function(n, r) return GuildOS:GetPlayerKey(n, r) end
local ana, bia, cid, dan, eva = res[key("Ana")], res[key("Bia")], res[key("Cid")], res[key("Dan")], res[key("Eva", "Gallywix")]
check(ana and #ana.missing == 0 and #ana.unknown == 0 and ana.buffs.weapon and ana.buffs.flask.id == FLASK,
  "I have my flask, food, rune and my weapon's oil, all read")
check(ana.buffs.flask.name == "Spell " .. FLASK, "a buff is named by the client")
check(bia and #bia.missing == 0 and #bia.unknown == 0 and bia.buffs.food.id == HEARTY,
  "a Hearty Well Fed is food; nobody else's weapon is asked")
check(joined(cid.missing) == "Flask,Augment Rune" and #cid.unknown == 0 and cid.buffs.food,
  "all of Cid's buffs were read: no flask and no rune are missing")
check(#dan.missing == 0 and joined(dan.unknown) == "Flask,Augment Rune" and dan.buffs.food,
  "Dan's buffs are partly secret: the food found counts, the flask and rune are unknown, never missing")
check(#eva.missing == 0 and joined(eva.unknown) == "Flask,Food Buff,Augment Rune" and next(eva.buffs) == nil,
  "out of range, everything is unknown")
check(CC:GetMissingCount(res) == 1 and CC:GetUnknownCount(res) == 2, "one raider missing something, two unread")
local problems, total, ready, unread = CC:Tally(res)
check(#problems == 1 and problems[1].name == "Cid" and total == 5 and ready == 2 and unread == 2,
  "the popup lists Cid, counts Ana and Bia ready, and Dan and Eva as neither")
problems, total, ready, unread = CC:Tally(nil)
check(#problems == 0 and total == 0 and ready == 0 and unread == 0, "no check yet: nothing to tally")
weapon = false
res = CC:CheckRaid()
check(joined(res[key("Ana")].missing) == "Weapon Buff", "my weapon without its oil is missing")
weapon = true
combat = true
res = CC:CheckRaid()
check(CC:GetMissingCount(res) == 0 and CC:GetUnknownCount(res) == 5, "in combat nobody is missing anything: all unknown")
combat = false
-- The announce: what is missing goes to the raid, and nothing while an encounter locks the chat.
res = CC:CheckRaid()
local said = {}
function SendChatMessage(msg) said[#said + 1] = msg end
CC:ReportToChat("RAID")
check(#said == 2 and said[2]:find("Cid: Flask, Augment Rune", 1, true), "the announce names what is missing, not what is unread")
said = {}
C_ChatInfo = { InChatMessagingLockdown = function() return true end }
CC:ReportToChat("RAID")
check(#said == 0, "in an encounter's chat lockdown nothing is sent (it would be dropped)")
C_ChatInfo = nil
-- Nobody missing but some unread: no "All OK!" goes to the raid, the officer is told locally.
combat = true
local unreadRes = CC:CheckRaid()
combat = false
CC.lastCheck, GuildOS.db.consumableChecks.lastResults = unreadRes, unreadRes
said = {}
CC:ReportToChat("RAID")
check(#said == 0, "with everyone unread, no All OK! is announced")
-- A ready check ending in combat (timed out after the pull) keeps the last readings.
res = CC:CheckRaid()
CC.lastCheck, GuildOS.db.consumableChecks.lastResults = res, res
combat = true
CC:OnReadyCheck()
combat = false
check(CC:GetLastResults() == res, "a ready check ending in combat does not replace the readings")
GROUP = {}
check(CC:CheckRaid(true) == nil, "outside a raid a quiet check reads nothing and says nothing")

-- ── 4. The snapshot's verdict, and the ready check before the pull ─────
GROUP = { { "Ana" }, { "Bia" }, { "Cid" }, { "Dan" }, { "Eva", "Gallywix" } }
GuildOS.State.consumables.reads = {}
local RT = GuildOS.RaidTracker
check(RT:CheckPlayerConsumes("raid2", key("Bia")) == true, "flask and food read: true")
check(RT:CheckPlayerConsumes("raid3", key("Cid")) == false, "no flask, read: false")
check(RT:CheckPlayerConsumes("raid4", key("Dan")) == nil, "a flask unknown and the food there: unknown")
check(RT:CheckPlayerConsumes("raid5", key("Eva", "Gallywix")) == nil, "nothing read: unknown")
-- A reading is never wiped by a later one that could not read.
GuildOS.State.consumables.reads = {}
CC:Remember("Zed", true)
CC:Remember("Zed", nil)
check(CC:Recent("Zed") == true, "an unread verdict leaves the good reading in place")
GuildOS.State.consumables.reads = {}
CC:Initialize()
local finished = false
for _, f in ipairs(frames) do if f.events.READY_CHECK and f.events.READY_CHECK_FINISHED then finished = true end end
check(finished, "retail listens to the ready check's start and its end")
-- Cid has no food when the check starts, and eats in answer to it; Bia is out of range by its end.
AURAS.Cid = { OTHER }
fire("READY_CHECK")
check(RT:CheckPlayerConsumes("raid3", key("Cid")) == false, "at the start Cid is read without his food")
AURAS.Cid, AURAS.Bia = { OTHER, FLASK, FOOD }, {}
clock = clock + 20
fire("READY_CHECK_FINISHED")
combat, clock = true, clock + 30
check(RT:CheckPlayerConsumes("raid3", key("Cid")) == true,
  "the pull's snapshot, in combat, answers with what the end of the ready check read: Cid ate")
check(RT:CheckPlayerConsumes("raid2", key("Bia")) == true, "Bia, unread at the end, keeps the start's reading")
check(RT:CheckPlayerConsumes("raid5", key("Eva", "Gallywix")) == nil, "and what was never read stays unknown")
clock = clock + 600
check(RT:CheckPlayerConsumes("raid3", key("Cid")) == nil, "ten minutes on, that reading no longer answers")
combat = false
AURAS.Cid, AURAS.Bia = { OTHER, FOOD }, { OTHER, FLASK, HEARTY, RUNE }

-- ── 5. The score: unknown is never missing, and the site counts alike ──
-- One night, four snapshots. Ana: four unknown. Bia: two unknown, two without. Cid: one unknown,
-- three without. Dan: all with.
local T = 1791000000
local ROWS = { Ana = { nil, nil, nil, nil }, Bia = { nil, nil, false, false }, Cid = { nil, false, false, false },
               Dan = { true, true, true, true } }
local snaps, players = {}, {}
for i = 1, 4 do
  local members = {}
  for name, row in pairs(ROWS) do
    members[name] = { name = name, class = "MAGE", online = true, hasConsumes = row[i] }
    players[name] = true
  end
  snaps[i] = { time = T + i * 300, members = members }
end
GuildOS.db.raidTracker.sessions = { [T] = { instanceID = 2912, difficulty = 15, groupTag = "", startTime = T,
  players = players, snapshots = snaps, isGuildRaid = true } }
RT.GetPenalties = function() return { LATE = 10, LEFT_EARLY = 10, NO_CONSUMES = 25 } end
RT:RebuildAttendanceFromSessions()
local att = GuildOS.db.raidTracker.attendance[""] or {}
local function score(n) return att[n] and att[n].totalScore end
check(score("Ana") == 100 and score("Dan") == 100, "never read, or always there: no penalty")
check(score("Bia") == 100, "two unknown and two without: the unknown count for the player, half is not under half")
check(score("Cid") == 75, "three of four without: docked")
-- The site's rule on CompanionExport's count (chits: every snapshot not known to be without).
local function source(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
check(source("Modules/CompanionExport.lua"):find("if m.hasConsumes ~= false then p.chits = (p.chits or 0) + 1 end", 1, true),
  "the export counts an unread snapshot for the player, as the score does")
check(source("UI/FeaturePanels.lua"):find("if snap.members[key].hasConsumes ~= false then consumeHits = consumeHits + 1 end", 1, true),
  "and so does the session detail's NO CONS count")
local hud = source("UI/RaidHUD.lua")
check(hud:find("local problems, total, ready, unread = CC:Tally(results)", 1, true)
  and hud:find("elseif #problems == 0 and unread > 0 then", 1, true),
  "the popup tallies through the checker and says when raiders were unread rather than 'everyone is prepared'")
for name, row in pairs(ROWS) do
  local chits = 0
  for i = 1, 4 do if row[i] ~= false then chits = chits + 1 end end
  local siteDocks = chits / 4 < 0.5
  check(siteDocks == (score(name) < 100), name .. ": the site and the game agree on the penalty")
end

-- ── 6. Readiness ──────────────────────────────────────────────────────
GROUP = { { "Ana" }, { "Cid" }, { "Eva", "Gallywix" }, { "Eva" }, { "Fay", "Gallywix" } }
AURAS = { Ana = { FLASK, FOOD, RUNE }, Cid = { OTHER, FOOD }, Eva = {} }
local ROSTER = { "Ana-Azralon", "Cid-Azralon", "Eva-Gallywix", "Eva-Azralon", "Fay-Azralon" }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) if ROSTER[i] then return ROSTER[i], "", 1, 90, "", "", "", "", true, 0, "MAGE" end end
-- Eva-Azralon is in range and readable; her namesake from Gallywix is not.
C_UnitAuras.GetBuffDataByIndex = function(unit, i)
  local m = GROUP[tonumber(unit:match("(%d+)$"))]
  local list = ((m[1] == "Eva" and not m[2]) or m[1] == "Fay") and { OTHER, FLASK, FOOD, RUNE } or AURAS[m[1]]
  local a = list and list[i]
  if a ~= nil then return { spellId = a } end
end
CC:CheckRaid()
local rows = {}
for _, r in ipairs(GuildOS.Readiness:GetReport()) do rows[r.key] = r end
check(rows[key("Ana")].missCons == 0, "read and complete: nothing missing")
check(rows[key("Cid")].missCons == 2 and rows[key("Cid")].status == "warn", "read and missing two: needs a look")
check(rows[key("Eva", "Gallywix")].missCons == nil, "nothing read: no count, never 'all missing'")
check(rows[key("Eva")].missCons == 0, "a namesake on another realm is her own raider, by key")
check(rows[key("Fay")].missCons == nil, "not in the raid: no count, though a Fay from Gallywix is")

-- ── 7. Forever has none; Anniversary's verdict is TBC's ───────────────
CC = load("forever")
check(not GuildOS.Client.isRetail and not GuildOS.Client.isAnniversary and CC == nil, "WoW: Forever has no consumable check")
check(GuildOS.RaidTracker:CheckPlayerConsumes("player", "Ana") == true, "and its snapshots dock nobody")
CC = load("anniversary")
check(GuildOS.Client.isAnniversary and CC ~= nil and CC.CONSUMABLES.battleElixir, "Anniversary keeps TBC's table")
C_UnitAuras.GetBuffDataByIndex = function(_, i) return ({ { name = "F", spellId = TBC_FLASK } })[i] end
check(GuildOS.RaidTracker:CheckPlayerConsumes("player", "Ana") == false, "a TBC flask without food: false")
C_UnitAuras.GetBuffDataByIndex = function(_, i)
  return ({ { name = "F", spellId = TBC_FLASK }, { name = "W", spellId = TBC_FOOD } })[i]
end
check(GuildOS.RaidTracker:CheckPlayerConsumes("player", "Ana") == true, "flask and food: true, as always")
combat = true
check(GuildOS.RaidTracker:CheckPlayerConsumes("player", "Ana") == true, "and Anniversary reads in combat as it always did")
CC:Initialize()
local readyCheck = false
for _, f in ipairs(frames) do if f.events.READY_CHECK then readyCheck = true end end
check(not readyCheck, "Anniversary registers no ready check")

print(("retail-consumables: %d checks passed"):format(checks))
