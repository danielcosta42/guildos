-- The dungeon log (issue #210), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/Journal.lua, Data/ForeverDungeons.lua and Modules/DungeonLog.lua.
--
-- What this holds: a run opens in a catalogued Forever dungeon; killing its final boss writes one
-- dungeon.clear into my journal, with how many of its bosses died and whether that was all of them;
-- dying and coming back inside 15 minutes is the same run, longer, after the clear, after a logout
-- or another instance is a new one; an alt never inherits a run; a secret or unknown encounter
-- changes nothing; nothing of it exists outside WoW: Forever.
--
--   luajit -e 'ADDON="."' tools/dungeon-log.lua
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

local NOW = 1794139200
local where = { type = "none", id = 0 }
local printed = {}

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
  function GetGuildInfo() return "Ashen Vow" end
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Chehul" end
  end
  function UnitClass() return "Shaman", "SHAMAN" end
  function GetRealmName() return "Normal" end
  function GetNormalizedRealmName() return "Normal" end
  function GetServerTime() return NOW end
  function GetTime() return 1 end
  function IsInGuild() return true end
  function GetInstanceInfo() return "x", where.type, 1, "Normal", 5, 0, false, where.id end
  C_Timer = { After = function() end, NewTicker = function() end }
  Enum = { SendAddonMessageResult = {} }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/Journal.lua")
  dofile(ADDON .. "/Data/ForeverDungeons.lua")
  dofile(ADDON .. "/Modules/DungeonLog.lua")
  GuildOS.db = { members = {}, settings = {}, profile = {} }
  if GuildOS.Journal then GuildOS.Journal:Initialize() end
  if GuildOS.DungeonLog then GuildOS.DungeonLog:Initialize() end
  return GuildOS
end

check(load("anniversary").DungeonLog == nil, "no dungeon log on TBC Anniversary")
check(GuildOS.ForeverDungeons == nil, "nor its catalogue")

local G = load("forever")
local D = G.DungeonLog
local clears = function()
  local n = {}
  for _, e in ipairs(G.db.journal.entries) do if e.type == "dungeon.clear" then n[#n + 1] = e end end
  return n
end
local function go(kind, id, t) where.type, where.id = kind, id; D:OnZone(t or NOW) end

-- Every catalogued dungeon with a final boss has it among its bosses.
for id, d in pairs(G.ForeverDungeons.byInstance) do
  if d.final then
    local found = false
    for _, b in ipairs(d.bosses) do if b == d.final then found = true end end
    check(found, d.name .. ": the final boss is one of its bosses")
  end
  check(type(d.id) == "string" and d.id ~= "" and type(id) == "number", d.name .. ": a stable id and an instance id")
end

-- ── A run of Ruins of Lordaeron ──────────────────────────────────────────
go("party", 2999)
local run = G.db.dungeonRun
check(run and run.instanceID == 2999 and run.runId == "2999:" .. NOW, "entering it opens a run")
D:OnEncounterEnd(3353, 1, NOW + 300)
D:OnEncounterEnd(3357, 0, NOW + 400)         -- a wipe
check(#clears() == 0, "a boss that is not the final one clears nothing")
go("none", 0, NOW + 600)                    -- died, ran back
go("party", 2999, NOW + 900)
check(G.db.dungeonRun.runId == run.runId, "back inside 15 minutes: the same run")
D:OnEncounterEnd(3355, 1, NOW + 1000)
D:OnEncounterEnd(9999, 1, NOW + 1100)       -- not this dungeon's
D:OnEncounterEnd(3354, 1, NOW + 1200)       -- Rath'mael, the final boss
local c = clears()
check(#c == 1, "the final boss is the clear")
local toasts = 0
for _, m in ipairs(printed) do if m:find("First clear of Ruins of Lordaeron for Ashen Vow!", 1, true) then toasts = toasts + 1 end end
check(toasts == 1, "the first clear this client knows of is said once")
local e = c[1]
check(e.data.dungeonId == "ruins-of-lordaeron" and e.data.runId == run.runId, "of this dungeon and this run")
check(e.data.bosses == 3 and e.data.fullClear == false, "three of five: not a full clear")
check(e.subjectKey == G:GetPlayerKey(G.Compat.PlayerName()), "about me")
D:OnEncounterEnd(3354, 1, NOW + 1300)
check(#clears() == 1, "killing it again in the same run writes nothing")

-- ── Leaving, another dungeon, secrets ───────────────────────────────────
go("none", 0, NOW + 1400)
go("party", 2999, NOW + 1400 + 16 * 60)
check(G.db.dungeonRun.runId ~= run.runId, "back after more than 15 minutes: a new run")
go("party", 2998, NOW + 5000)
check(G.db.dungeonRun.instanceID == 2998, "another dungeon is another run")
local secret = setmetatable({}, {})
G.Compat.IsSecret = function(v) return v == secret end
D:OnEncounterEnd(secret, 1, NOW + 5100)
check(next(G.db.dungeonRun.kills) == nil, "a secret encounter counts nothing")
for _, b in ipairs({ 3480, 3481, 3644, 3482 }) do D:OnEncounterEnd(b, 1, NOW + 5200) end
check(#clears() == 2 and clears()[2].data.fullClear == true and clears()[2].data.bosses == 3, "the three of Wetlands: a full clear, one faction's quest boss apart")
go("party", 3109, NOW + 6000)
D:OnEncounterEnd(3496, 1, NOW + 6100)
check(#clears() == 2, "a dungeon with no final boss known records no clear")
go("party", 9999, NOW + 7000)
check(G.db.dungeonRun == nil, "an instance off the catalogue opens no run, and ends the one there was")
go("party", 3109, NOW + 7100)
go("raid", 109, NOW + 8000)
check(G.db.dungeonRun == nil, "a raid is RaidTracker's, not a run, and ends the one there was")

-- ── Chain runs, logouts, alts ───────────────────────────────────────────
local T = NOW + 10000
go("party", 2998, T)
for _, b in ipairs({ 3480, 3481, 3482 }) do D:OnEncounterEnd(b, 1, T + 100) end
check(#clears() == 3, "the third clear")
go("none", 0, T + 200)
check(G.db.dungeonRun == nil, "leaving after the clear ends the run")
go("party", 2998, T + 300)                  -- reset and straight back in
D:OnEncounterEnd(3482, 1, T + 400)
check(#clears() == 4 and clears()[4].data.bosses == 1, "a chain run is a run of its own: its clear is written")
D:OnLogout(T + 500)
go("party", 2998, T + 86400)                -- tomorrow, logged back in there
check(G.db.dungeonRun.runId == "2998:" .. (T + 86400), "a logout inside ends the run: the next day is another")
D:OnLogout(T + 86400)
go("party", 2998, T + 86400 + 60)           -- a /reload fires the logout too
check(G.db.dungeonRun.runId == "2998:" .. (T + 86400), "a /reload inside keeps the run")
D:OnEncounterEnd(3480, 1, T + 86500)
UnitFullName = function() return "Mira", "Costa" end
go("party", 2998, T + 86600)
check(G.db.dungeonRun.who ~= clears()[1].subjectKey and next(G.db.dungeonRun.kills) == nil, "an alt never inherits a run")

-- ── Where a dungeon ends ────────────────────────────────────────────────
-- The game's own count of who ends one (issue #235), with the rest of the way a full clear.
local function runOf(instance, kills, t)
  go("none", 0, t - 2000)
  go("party", instance, t)
  for i, b in ipairs(kills) do D:OnEncounterEnd(b, 1, t + i) end
  go("none", 0, t + 100)
  return clears()[#clears()]
end
local F = NOW + 20000
local ended = runOf(2959, { 3311, 3298, 3301, 3310, 3302, 3299, 3300, 3312, 3303 }, F)
check(ended.data.dungeonId == "city-of-dalaran" and ended.data.fullClear == true and ended.data.bosses == 7, "Shade of the Archmage ends Dalaran, the summoned and the phantom apart")
local before = #clears()
runOf(2959, { 3312, 3310 }, F + 5000)
check(#clears() == before, "neither of those is an end")
ended = runOf(2999, { 3353, 3355, 3357, 3412, 3354 }, F + 10000)
check(ended.data.dungeonId == "ruins-of-lordaeron" and ended.data.fullClear == true and ended.data.bosses == 5, "Rath'mael ends Ruins, with the five of the way")
before = #clears()
runOf(2999, { 3353, 3412, 3408 }, F + 15000)
check(#clears() == before, "Bjork in the middle ends nothing")
ended = runOf(3065, { 3493, 3495, 3494, 3496 }, F + 20000)
check(ended.data.dungeonId == "hall-of-thanes" and ended.data.fullClear == true, "Durgen Dirgehammer ends the Hall of Thanes")
ended = runOf(2999, { 3353, 3355, 3357, 3354 }, F + 30000)
check(ended.data.bosses == 4 and ended.data.fullClear == false, "the end first, with one of the way to go: not yet")
before = #clears()
go("party", 2999, F + 40000)
D:OnEncounterEnd(3353, 1, F + 40001)
D:OnEncounterEnd(3355, 1, F + 40002)
D:OnEncounterEnd(3357, 1, F + 40003)
D:OnEncounterEnd(3354, 1, F + 40004)
D:OnEncounterEnd(3408, 1, F + 40005)        -- the rare: off the way, and it finishes nothing
check(clears()[#clears()].data.fullClear == false, "a rare after the end changes nothing")
D:OnEncounterEnd(3412, 1, F + 40006)
go("none", 0, F + 40100)
check(#clears() == before + 1 and clears()[#clears()].data.fullClear == true and clears()[#clears()].data.bosses == 5, "the last of the way after the end: the same clear, now a full one")

-- ── The whole registry (issue #210, Einstorm): the nine new, the classic ones, wings and alternative ids ──
local cat = G.ForeverDungeons
local newOnes, classics = 0, 0
for id, d in pairs(cat.byInstance) do
  if d.classic then classics = classics + 1 elseif #d.bosses > 0 then newOnes = newOnes + 1 end
  for _, w in ipairs(d.wings or {}) do
    local found = false
    for _, b in ipairs(w.bosses) do if b == w.final then found = true end end
    check(found and type(w.id) == "string" and w.id ~= d.id, d.name .. ": the wing " .. w.name .. " ends with one of its bosses, under its own id")
  end
  for from, to in pairs(d.alt or {}) do
    local found = false
    for _, b in ipairs(d.bosses) do if b == to then found = true end end
    check(found and from ~= to, d.name .. ": an alternative id stands for one of its bosses")
  end
  check(type(id) == "number" and id > 0, d.name .. ": an instance id")
end
check(newOnes == 9, "the nine new dungeons have bosses (" .. newOnes .. ")")
check(classics == 19, "and the nineteen classic instances (" .. classics .. ")")
for _, id in ipairs({ 2970, 2974, 2994, 3001, 3039 }) do
  check(cat.byInstance[id] and cat.byInstance[id].final, "the five the launch scan missed are there: " .. id)
end

GuildOSDB = {}
local G2 = NOW + 200000
ended = runOf(2974, { 3315, 3336, 3334 }, G2)
check(ended.data.dungeonId == "blackmaw-hold" and ended.data.bosses == 3 and ended.data.fullClear == false,
  "Varrox Bleakhoof, the guides' last, ends Blackmaw Hold; Unbound Spirit, last by the table's order, does not")
local toastsBefore = 0
for _, m in ipairs(printed) do if m:find("First clear of", 1, true) then toastsBefore = toastsBefore + 1 end end
ended = runOf(36, { 2741, 2742, 2743, 2744, 2745, 2746, 2747 }, G2 + 10000)
check(ended.data.dungeonId == "deadmines" and ended.data.fullClear == true, "a classic dungeon is a clear too: The Deadmines")
local toastsAfter = 0
for _, m in ipairs(printed) do if m:find("First clear of", 1, true) then toastsAfter = toastsAfter + 1 end end
check(toastsAfter == toastsBefore and G.db.journal.firsts.deadmines == nil, "but no guild's first: that is for the new ones")
ended = runOf(189, { 446, 447 }, G2 + 20000)
check(ended.data.dungeonId == "scarlet-monastery-library" and ended.data.fullClear == true,
  "a wing of Scarlet Monastery is its own clear, found by its boss")
before = #clears()
ended = runOf(189, { 446, 450 }, G2 + 30000)
check(#clears() == before, "once in the Library, the Cathedral's boss ends nothing")
ended = runOf(48, { 2761, 2767 }, G2 + 40000)
check(ended.data.dungeonId == "blackfathom-deeps" and ended.data.bosses == 2,
  "Blackfathom Deeps' other set of ids counts as the same bosses")

-- ── What the game sent, for the probe (Core/Probe.lua) ───────────────────
local seen = GuildOSDB.probeSeen
check(seen and seen.instances[2974] and seen.instances[189] and seen.instances[2974].n >= 1, "every instance entered is kept")
where.type, where.id = "party", 2974
G.DungeonLog:SeeEncounter(3334, "Varrox Bleakhoof", 1, 1, NOW)
where.type, where.id = "party", 36
G.DungeonLog:SeeEncounter(2747, "Edwin VanCleef", 1, 1, NOW)
where.type, where.id = "party", 48
G.DungeonLog:SeeEncounter(2767, "Aku'mai", 1, 0, NOW)
check(seen.encounters[3334] and seen.encounters[3334].kills == 1 and seen.encounters[3334].instance == 2974
  and seen.encounters[2767].wipes == 1, "and every encounter that ended, with its instance, killed or not")
G.DungeonLog:SeeEncounter(secret, "x", 1, 1, NOW)
G.DungeonLog:SeeInstance(secret, "x", "party", 1, NOW)
where.type, where.id = "party", 4242
G.DungeonLog:SeeEncounter(4243, "Somebody New", 1, 0, NOW)
G.DungeonLog:SeeInstance(4242, "A New Dungeon", "party", 1, NOW)
local rep = G.DungeonLog:SeenReport()
local st = {}
for _, i in ipairs(rep.instances) do st["I" .. i.id] = i.status end
for _, e in ipairs(rep.encounters) do st["E" .. e.id] = e.status end
check(st.I2974 == "unverified" and st.I36 == "known" and st.I48 == "unverified" and st.I4242 == "new", "instances: known, unverified, new")
check(st.E3334 == "unverified" and st.E2747 == "known" and st.E2767 == "unverified" and st.E4243 == "new",
  "encounters: a statistic's boss is known, a guide's or an alternative id unverified, the rest new")
for k in pairs(st) do check(type(k) == "string", "no secret id is kept") end
dofile(ADDON .. "/Core/Probe.lua")
local text = G.Probe.DungeonReportText(rep, "1.0", "1.60.1.71139")
check(text:find("I4242 A New Dungeon [party d1] new", 1, true) and text:find("E3334 Varrox Bleakhoof [i2974 d1 k1] unverified", 1, true)
  and text:find("E4243 Somebody New [i4242 d1 k0] new", 1, true) and text:find("E2767", 1, true),
  "the report names what is new or unverified, by id")
check(not text:find("E2747", 1, true) and text:find("confirmed", 1, true), "and only counts the confirmed")
check(#G.Probe.DungeonReportText({ instances = {}, encounters = (function()
  local l = {} for i = 1, 400 do l[i] = { id = i, name = string.rep("x", 30), status = "new", kills = 0 } end return l end)() }, "1", "b") <= 1800,
  "a long report stays one paste")

print(("dungeon-log: %d checks passed"):format(checks))
