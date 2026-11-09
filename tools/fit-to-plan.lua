-- Fit the group to the plan (issue #292), run against the real Core/Core.lua, Core/Compat.lua and
-- Modules/CompanionImport.lua on WoW: Forever: who is outside the plan, that the bench and the leader
-- never are, that only the raid leader may take people out, and that the removal goes through Compat.
--
--   luajit -e 'ADDON="."' tools/fit-to-plan.lua
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
function GetBuildInfo() return "1.60.1", "70707", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function UnitFullName() return "Lead", "" end
C_PlayerInfo = { ShouldDisplaySurname = function() return false end }
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
local shown
function StaticPopup_Show(which, text) shown = { which = which, text = text } end

-- The group: the leader, two planned, one benched, one pug, one who said no on the site.
local GROUP = { "Lead", "Ana", "Bo", "Benched", "Pug", "SaidNo" }
local leader = true
function IsInRaid() return true end
function GetNumGroupMembers() return #GROUP end
function UnitIsGroupLeader() return leader end
function UnitName(unit)
  local i = tonumber(unit:match("(%d+)$"))
  if unit == "player" then return "Lead" end
  return GROUP[i], ""
end
function UnitClass() return "Warrior", "WARRIOR" end
local removed = {}
C_PartyInfo = { UninviteUnit = function(name) removed[#removed + 1] = name end, InviteUnit = function() end }

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
GuildOS.Print = function() end
local I = GuildOS.CompanionImport

GuildOS.db = { companionRoster = nil }
check(not I:CanTrim(), "no roster, nothing to fit to")

GuildOS.db.companionRoster = {
  raidId = "r1", members = { { name = "Ana", group = 1 }, { name = "Bo", group = 1 } },
  signups = {
    { name = "Ana", why = nil, invite = true },
    { name = "Bo", why = nil, invite = true },
    { name = "Benched", why = "bench", invite = false },
    { name = "SaidNo", why = "no", invite = false },
  },
}

local out = I:OutsideThePlan()
check(#out == 2 and out[1] == "Pug" and out[2] == "SaidNo", "outside the plan: the pug and who said no (" .. table.concat(out, ",") .. ")")

check(I:CanTrim(), "the raid leader may fit the group")
I:AskTrim()
check(shown and shown.which == "GUILDOS_TRIM_PLAN" and shown.text:find("Pug", 1, true) and shown.text:find("SaidNo", 1, true),
  "asked first, naming who goes")
check(#removed == 0, "and nobody removed before the answer")

StaticPopupDialogs.GUILDOS_TRIM_PLAN.OnAccept()
check(#removed == 2 and removed[1] == "Pug" and removed[2] == "SaidNo", "on yes, removed through Compat: never the leader, the planned or the bench")

leader = false
local n, why = I:TrimToPlan()
check(n == nil and why == "Only the raid leader can remove people from the raid.", "an assistant cannot")

print(("fit-to-plan: %d checks passed"):format(checks))
