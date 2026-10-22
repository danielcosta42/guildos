-- Specs on retail (issue #166), run against the real Core/Compat.lua, Core/Utils.lua and
-- Modules/SpecChecker.lua under a stubbed retail client.
--
-- Retail has no talent tabs to count and no classic trees side by side: a character has one spec,
-- which C_SpecializationInfo names, with its role, in the reader's language. This proves my own
-- spec and an inspected one are read from it, stored on the member's key with the client's name and
-- role, labelled by the name alone, and that no talent-tab or trait-tree call is made. And
-- (issue #184) that an inspect also brings the item level of a guildmate without the addon, never
-- over newer data their own addon sent, and that my spec change is sent at once.
--
--   luajit -e 'ADDON="."' tools/retail-spec.lua
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
function GetServerTime() return 1791000000 end
time = function() return 1791000000 end
C_Timer = { After = function(_, fn) fn() end }
-- The inspected average (issue #184): raid1 wears 247.6 on average.
C_PaperDollInfo = { GetInspectItemLevel = function(u) return u == "raid1" and 247.6 or 0 end }
function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
function GetRealmName() return "Azralon" end
function GetNormalizedRealmName() return "Azralon" end

-- The player is a Holy Priest; raid1 is a Blood Death Knight from a connected realm.
local UNITS = { player = { "Ana", nil, "PRIEST" }, raid1 = { "Bo", "Gallywix", "DEATHKNIGHT" } }
function UnitName(u) return UNITS[u][1], UNITS[u][2] end
function UnitClass(u) return UNITS[u][3], UNITS[u][3] end
function UnitIsUnit(a, b) return a == b end
function IsInRaid() return true end
function IsInGroup() return true end
function GetNumGroupMembers() return 1 end
function UnitExists(u) return UNITS[u] ~= nil end
function UnitIsConnected() return true end
function CanInspect() return true end
function NotifyInspect() end
local SPECS = { [65] = { "Holy", "HEALER" }, [250] = { "Blood", "TANK" } }
C_SpecializationInfo = {
  GetSpecialization = function() return 1 end,
  GetSpecializationInfo = function(i) if i == 1 then return 65, "Holy", "", 0, "HEALER" end end,
  GetInspectSpecialization = function(u) return u == "raid1" and 250 or 0 end,
}
function GetSpecializationInfoForSpecID(id)
  local s = SPECS[id]
  if s then return id, s[1], "", 0, s[2] end
end
-- Retail has neither; a call to either is a test failure.
function GetNumTalentTabs() error("a talent tab was asked for on retail") end
C_ClassTalents = setmetatable({}, { __index = function() error("a trait tree was asked for on retail") end })

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), SelfTest = { Register = function() end } }
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/SpecChecker.lua")
function GuildOS:Print() end
GuildOS.db = { members = {} }
check(GuildOS.Client.isRetail, "the stub is retail")

-- ── 1. Compat reads a spec ─────────────────────────────────────────────
local id, name, role = GuildOS.Compat.SpecOf("player")
check(id == 65 and name == "Holy" and role == "HEALER", "my spec: its id, name and role")
id, name, role = GuildOS.Compat.SpecOf("raid1")
check(id == 250 and name == "Blood" and role == "TANK", "an inspected spec: its id, name and role")
C_SpecializationInfo.GetInspectSpecialization = function() return 0 end
check(GuildOS.Compat.SpecOf("raid1") == nil, "no spec yet is nothing")
C_SpecializationInfo.GetInspectSpecialization = function(u) return u == "raid1" and 250 or 0 end

-- ── 2. My own spec ─────────────────────────────────────────────────────
local SC = GuildOS.SpecChecker
local spec = SC:CollectOwnSpec()
check(spec and spec.specID == 65 and spec.tree == "Holy" and spec.role == "HEALER", "my spec is collected on retail")
check(GuildOS.db.members["Ana-Azralon"] and GuildOS.db.members["Ana-Azralon"].spec == spec, "and kept on my own key")
check(SC:GetSpecLabel("Ana-Azralon") == "Holy", "labelled by its name alone")
check(spec.points == nil, "with no tree points to draw")

-- ── 3. An inspected spec ───────────────────────────────────────────────
SC:ScanGroup()
SC:OnInspectReady()
local bo = GuildOS.db.members["Bo-Gallywix"]
check(bo and bo.spec and bo.spec.specID == 250 and bo.spec.tree == "Blood" and bo.spec.role == "TANK",
  "an inspected spec lands on the member's own realm key")
check(SC:GetSpecLabel("Bo-Gallywix") == "Blood", "and is labelled by its name")

-- ── 4. A synced spec reads in my language (issue #177) ─────────────────
-- A guildmate on a Portuguese client sent "Sangue"; this client names spec 250 itself.
GuildOS.db.members["Cy-Azralon"] = { spec = { specID = 250, tree = "Sangue", role = "TANK" } }
check(SC:GetSpecLabel("Cy-Azralon") == "Blood", "a synced spec is labelled by its id, in the reader's language")
check(SC:SpecName({ specID = 9999, tree = "Sangue" }) == "Sangue", "an id the client cannot name keeps the sender's name")
check(SC:SpecName({ tree = "Holy", points = { 41, 5, 15 } }) == "Holy" and SC:SpecName(nil) == nil,
  "a classic spec keeps its tree name")
local roster = io.open(ADDON .. "/UI/RosterFrame.lua", "rb"):read("*a")
check(roster:find("GuildOS.SpecChecker:SpecName(spec)", 1, true) ~= nil, "the roster's spec column reads the same name")

-- ── 5. The inspect brings the item level (issue #184) ──────────────────
check(bo.avgIlvl == 247, "an inspected guildmate without the addon gets the game's average item level")
check(bo.lastUpdate == nil, "and no addon stamp: their own first broadcast still lands")
local NOW = time()
local function inspectBo()
  SC:ScanGroup()
  SC:OnInspectReady()
  return GuildOS.db.members["Bo-Gallywix"]
end
GuildOS.db.members["Bo-Gallywix"] = { avgIlvl = 250, lastUpdate = NOW }
check(inspectBo().avgIlvl == 250, "their own addon's data from this very moment is not overwritten")
GuildOS.db.members["Bo-Gallywix"] = { avgIlvl = 240, lastUpdate = NOW - 3600 }
bo = inspectBo()
check(bo.avgIlvl == 247 and bo.lastUpdate == NOW - 3600, "an hour-old broadcast is: the inspect is newer, and the stamp stays")
C_PaperDollInfo.GetInspectItemLevel = function() return 0 end
GuildOS.db.members["Bo-Gallywix"] = { avgIlvl = 240 }
check(inspectBo().avgIlvl == 240 and inspectBo().spec.specID == 250, "no reading yet keeps what was there, and the spec still lands")
local SECRET = {}
issecretvalue = function(v) return v == SECRET end
C_PaperDollInfo.GetInspectItemLevel = function() return SECRET end
check(GuildOS.Compat.InspectItemLevel("raid1") == nil, "a secret item level is never read")
issecretvalue = nil
C_PaperDollInfo.GetInspectItemLevel = function() return 247.6 end
GuildOS.Client.isRetail = false
check(GuildOS.Compat.InspectItemLevel("raid1") == nil, "on another client the inspect gives no item level")
GuildOS.Client.isRetail = true

-- ── 6. My spec change goes out now (issue #184) ────────────────────────
local registered, handler = {}, nil
function CreateFrame()
  return { RegisterEvent = function(_, e) registered[e] = true end, SetScript = function(_, _, fn) handler = fn end }
end
local timers = {}
C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
SC:Initialize()
check(registered.PLAYER_SPECIALIZATION_CHANGED and registered.INSPECT_READY, "retail listens for my spec changing")
local broadcasts = {}
GuildOS.CommSystem = { BroadcastMyData = function(_, force) broadcasts[#broadcasts + 1] = force end }
timers = {}
handler(nil, "PLAYER_SPECIALIZATION_CHANGED", "party1")
check(#timers == 0, "a party member's spec change sends nothing of mine")
handler(nil, "PLAYER_SPECIALIZATION_CHANGED", "player")
handler(nil, "PLAYER_SPECIALIZATION_CHANGED", "player")
check(#timers == 1, "a burst of swaps waits once")
timers[1]()
check(#broadcasts == 1 and broadcasts[1] == true, "and then my data goes out past the throttle")
timers = {}
handler(nil, "PLAYER_SPECIALIZATION_CHANGED", "player")
check(#timers == 1, "the next swap is heard again")

print(("retail-spec: %d checks passed"):format(checks))
