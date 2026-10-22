-- What retail does not have (issue #165), run against the real Core files, the loot and site modules,
-- the slash router and the raid tracker, under a stubbed retail client.
--
-- Retail is personal loot only, so the loot suite is absent there, the way TBC content is absent
-- outside Anniversary (ADR-0014): the module file returns before defining its global. So is the look
-- read in the barber's chair, which the site takes from the Armory on retail. This proves each one is
-- absent on retail; that a slash verb reaching one says so instead of raising or saying nothing; that
-- the site's modules and verbs are there since issue #182; and that a boss whose name Midnight keeps
-- secret neither raises nor is printed.
--
-- ponytail: the interface gates (the core's loot rules, the Settings quick buttons and officer tests,
-- the roster's wishlist button, the export chooser) are one module check each and are checked in game.
--
--   luajit -e 'ADDON="."' tools/retail-absent.lua
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

-- ── A retail client ──────────────────────────────────────────────────
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
local SECRET = setmetatable({}, { __tostring = function() error("a secret value was read") end })
function issecretvalue(v) return v == SECRET end
function CreateFrame()
  return setmetatable({}, { __index = function() return function() end end })
end
function hooksecurefunc() end
function debugstack() return "" end
function GetServerTime() return 1791000000 end
time = os.time
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetRealmName() return "Azralon" end
function GetNormalizedRealmName() return "Azralon" end
function UnitName() return "Ana" end
function GetInstanceInfo() return "Raid", "raid", 14, "Normal", 30 end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                       { __call = function() return {} end })
SlashCmdList = {}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
check(GuildOS.Client.isRetail, "the stub is a retail client")
function GuildOS:IsOfficer() return true end
GuildOS.db = { settings = { modules = {} }, members = {}, raidTracker = {} }

-- ── 1. The loot suite and the site are absent ─────────────────────────
local ABSENT = {
  { "LootMaster", "LootMaster" }, { "LootTracker", "LootTracker" }, { "LootEquity", "LootEquity" },
  { "Points", "Points" }, { "SoftResSystem", "SoftRes" }, { "WishlistSystem", "Wishlist" }, { "Look", "Look" },
}
for _, m in ipairs(ABSENT) do
  dofile(ADDON .. "/Modules/" .. m[1] .. ".lua")
  check(GuildOS[m[2]] == nil, m[1] .. " is absent on retail")
end
check(GuildOS:StartModule({ "LootMaster" }) == false and next(GuildOS.State.startup.failed) == nil,
  "an absent module is skipped at start-up, not failed")
-- The site is retail's since issue #182.
GuildOS.JsonDecode = function() end
for _, m in ipairs({ { "CompanionExport", "Companion" }, { "CompanionImport", "CompanionImport" } }) do
  dofile(ADDON .. "/Modules/" .. m[1] .. ".lua")
  check(GuildOS[m[2]] ~= nil, m[1] .. " is on retail (issue #182)")
end

-- ── 2. Its slash verbs say so ─────────────────────────────────────────
dofile(ADDON .. "/Core/Commands.lua")
local NOT_HERE = "Not available on this client."
for _, verb in ipairs({ "points", "dkp", "equity", "lootequity", "lm", "lootmaster", "lm announce",
                        "wish", "wish list", "softres" }) do
  printed = {}
  local ok, err = pcall(SlashCmdList.GUILDOS, verb)
  check(ok, "/gos " .. verb .. " does not raise on retail: " .. tostring(err))
  local said = false
  for _, line in ipairs(printed) do
    if line:find(NOT_HERE, 1, true) then said = true end
  end
  check(said, "/gos " .. verb .. " says it is not on this client")
end
printed = {}
check(pcall(SlashCmdList.GUILDOS, "help"), "/gos help does not raise on retail")
local help = table.concat(printed, "\n")
for _, gone in ipairs({ "/gos lm", "/gos points", "/gos wish" }) do
  check(not help:find(gone, 1, true), gone .. " is not in retail's help")
end
check(help:find("/gos web", 1, true) and help:find("/gos roster", 1, true), "the site's commands are in retail's help (issue #182)")
-- And they answer as anywhere else, never that they are missing: the companion off, how to turn it on.
GuildOS.db.settings.companion = false
for _, case in ipairs({ { "web", "/gos web on" }, { "companion", "/gos web on" }, { "roster invite", "Import a roster first." } }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, case[1]), "/gos " .. case[1] .. " does not raise on retail")
  local all = table.concat(printed, " ")
  check(not all:find(NOT_HERE, 1, true) and all:find(case[2], 1, true), "/gos " .. case[1] .. " answers on retail: " .. all)
end
check(help:find("/gos specs", 1, true) ~= nil, "the rest of the help is still there")
check(help:find("Export roster or attendance", 1, true) and not help:find("attendance or loot", 1, true),
  "the export help names no loot on retail (issue #177)")

-- The loot exports are absent too, and the usage line lists what retail has (issue #177).
dofile(ADDON .. "/Modules/ExportImport.lua")
GuildOS.ShowExportPopup = function() end
for _, what in ipairs({ "loot", "equity", "standings" }) do
  printed = {}
  check(pcall(SlashCmdList.GUILDOS, "export " .. what) and table.concat(printed, " "):find(NOT_HERE, 1, true),
    "/gos export " .. what .. " says it is not on this client")
end
check(GuildOS.Exporter:Has("roster") and not GuildOS.Exporter:Has("loot"), "the roster export is here, the loot one is not")
printed = {}
SlashCmdList.GUILDOS("export nonsense")
check(table.concat(printed, " "):find("Usage: /guildos export <roster|attendance|readiness> [csv|tsv|discord]", 1, true),
  "the usage line lists only retail's exports")

-- ── 3. A secret boss name ─────────────────────────────────────────────
dofile(ADDON .. "/Modules/RaidTracker.lua")
local RT = GuildOS.RaidTracker
RT.currentRaid = { encounters = {}, snapshots = {}, players = {} }
RT.TakeSnapshot = function() end
check(pcall(RT.OnEncounterStart, RT, 3001, SECRET), "a secret boss name on the pull does not raise")
printed = {}
local ok, err = pcall(RT.OnEncounterEnd, RT, 3001, SECRET, 1)
check(ok, "a secret boss name on the kill does not raise: " .. tostring(err))
check(RT.currentRaid.encounters[1].name ~= SECRET, "a secret name is never stored")
check(RT.currentRaid.encounters[1].success == true, "the kill is still recorded")

print(("retail-absent: %d checks passed"):format(checks))
