-- Specs on retail (issue #166), run against the real Core/Compat.lua, Core/Utils.lua and
-- Modules/SpecChecker.lua under a stubbed retail client.
--
-- Retail has no talent tabs to count and no classic trees side by side: a character has one spec,
-- which C_SpecializationInfo names, with its role, in the reader's language. This proves my own
-- spec and an inspected one are read from it, stored on the member's key with the client's name and
-- role, labelled by the name alone, and that no talent-tab or trait-tree call is made.
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
C_Timer = { After = function(_, fn) fn() end }
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

print(("retail-spec: %d checks passed"):format(checks))
