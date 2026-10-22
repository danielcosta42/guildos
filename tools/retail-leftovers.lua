-- What was left of TBC content where the game has none (issue #184), run against the real Core files,
-- Modules/Resistances.lua, Modules/DataCollector.lua, Modules/ExportImport.lua and the slash router
-- under a stubbed retail client, a WoW: Forever one and a TBC Anniversary one.
--
-- Attunements and consumables are absent outside Anniversary and resistance gear is gone from retail
-- (ADR-0014, ADR-0026), yet their traces stayed: a trial's "0/0 (+0)" attunements, an export column
-- of nothing, a "no consumables" penalty offered that never cost anything, a readiness target that
-- cycled through no raids, a resistance scan collected and sent on every broadcast, and two debug
-- verbs that ran anyway. This proves each one follows its module: absent where the module is, as it
-- was where the module is there.
--
--   luajit -e 'ADDON="."' tools/retail-leftovers.lua
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

local printed = {}
local function load(game)
  printed = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
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
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return 1791000000 end
  time = function() return 1791000000 end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1 end
  function GetRealmName() return "Azralon" end
  function GetNormalizedRealmName() return "Azralon" end
  function UnitName() return "Ana" end
  function UnitClass() return "Priest", "PRIEST" end
  function UnitLevel() return 80 end
  function UnitRace() return "Human", "Human" end
  function UnitSex() return 3 end
  function GetNumGuildMembers() return 1 end
  function GetGuildRosterInfo(i) if i == 1 then return "Ana-Azralon", "Officer", 1, 80, "Priest", "", "", "", true, 0, "PRIEST" end end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return true end
  GuildOS.db = { settings = { modules = {} }, members = {}, raidTracker = {} }
  dofile(ADDON .. "/Modules/DataCollector.lua")
  dofile(ADDON .. "/Modules/Resistances.lua")
  dofile(ADDON .. "/Modules/ExportImport.lua")
  dofile(ADDON .. "/Core/Commands.lua")
  local DC = GuildOS.DataCollector
  DC.CollectGear = function() return {}, false end
  DC.CollectProfessions = function() return {} end
  DC.CollectStats = function() return {} end
  DC.CalculateAvgIlvl = function() return 0 end
  DC.scans = 0
  DC.CollectResistances = function() DC.scans = DC.scans + 1; return { fire = 5 } end
  return DC
end

local function said(text)
  for _, line in ipairs(printed) do
    if tostring(line):find(text, 1, true) then return true end
  end
  return false
end
local function has(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end
local NOT_HERE = "Not available on this client."

-- ── 1. Retail: no resistance scan, no sync, no debug verbs ─────────────
local DC = load("retail")
check(GuildOS.Client.isRetail, "the stub is retail")
check(GuildOS.Resistances == nil, "the Resistances module is absent on retail")
local data = DC:CollectMyData()
check(DC.scans == 0 and data.resistances == nil, "retail collects no resistance gear")
GuildOS.db.myData.resistances = { fire = 5 }   -- held from before the update
check(DC:GetBroadcastData().resistances == nil, "and sends none, even one held from before")
printed = {}
SlashCmdList.GUILDOS("resscan")
check(said(NOT_HERE) and DC.scans == 0, "/gos resscan says it is not on this client, and scans nothing")
printed = {}
local ok = pcall(SlashCmdList.GUILDOS, "attune dumpquests")
check(ok and said(NOT_HERE) and not said("Completed quests"), "/gos attune dumpquests says it is not on this client")

-- ── 2. Retail: the exports carry no attunement or consumables column ───
local headers = GuildOS.Exporter:RosterData()
check(not has(headers, "Attunements") and has(headers, "LastSeen") and #headers == 7, "the roster export has no attunements")
local _, rows = GuildOS.Exporter:RosterData()
check(#rows == 1 and #rows[1] == #headers and rows[1][7]:match("^%d+%-%d+%-%d+$"), "and each row matches its header, last seen last")
GuildOS.Readiness = { GetReport = function()
  return { { name = "Ana", status = "ready", ilvl = 650, attDone = 0, attTotal = 0, missEnch = 1 } }
end }
headers, rows = GuildOS.Exporter:ReadinessData()
check(not has(headers, "Attune") and not has(headers, "MissingConsumes") and has(headers, "MissingEnchants"),
  "the readiness export has no attunement or consumables column")
check(#rows[1] == #headers and rows[1][4] == 1, "and its rows line up")

-- ── 3. Forever: resistances as before; attunements and consumables absent ─
DC = load("forever")
check(GuildOS.Resistances ~= nil, "Forever keeps the Resistances module")
data = DC:CollectMyData()
check(DC.scans == 1 and data.resistances and data.resistances.fire == 5, "Forever still collects resistance gear")
check(DC:GetBroadcastData().resistances ~= nil, "and sends it")
printed = {}
SlashCmdList.GUILDOS("resscan")
check(said("Resistances (max wearable)"), "/gos resscan still runs on Forever")
check(not has(GuildOS.Exporter:RosterData(), "Attunements"), "Forever has no attunements to export either")

-- ── 4. Anniversary: every column is there ─────────────────────────────
load("anniversary")
GuildOS.AttunementTracker = {
  GetGuildColumns = function() return { {}, {} } end,
  GetEffectiveAttunements = function() return { { complete = true, questsTotal = 3 } } end,
}
GuildOS.ConsumableChecker = {}
headers, rows = GuildOS.Exporter:RosterData()
check(#headers == 8 and headers[7] == "Attunements" and rows[1][7] == "1/2" and rows[1][8] == "",
  "Anniversary's roster export keeps its attunements")
GuildOS.Readiness = { GetReport = function()
  return { { name = "Ana", status = "ready", ilvl = 120, attDone = 1, attTotal = 2, missEnch = 0, missCons = 2 } }
end }
headers, rows = GuildOS.Exporter:ReadinessData()
check(table.concat(headers, ",") == "Name,Status,iLvl,Attune,MissingEnchants,MissingConsumes"
  and table.concat(rows[1], ",") == "Ana,ready,120,1/2,0,2", "and its readiness export every column")

-- ── 5. The screens ask the modules ────────────────────────────────────
local function src(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local audit = src("UI/AuditPanel.lua")
check(audit:find("local hasAttune, hasCons = GuildOS.AttunementTracker ~= nil, GuildOS.ConsumableChecker ~= nil", 1, true)
  and audit:find("if hasAttune then\n?%s*targetBtn = UI:CreateButton") and audit:find('if hasAttune then hcol(L["ATTUNE"]', 1, true)
  and audit:find('if hasCons then hcol(L["CONSUMES"]', 1, true),
  "readiness offers a raid target and the attunement and consumables columns only with their modules")
local fp = src("UI/FeaturePanels.lua")
check(fp:find('if GuildOS.ConsumableChecker then\n?%s*penalties%[#penalties %+ 1%] = { key = "NO_CONSUMES"')
  and fp:find("pen.NO_CONSUMES > 0 and GuildOS.ConsumableChecker", 1, true)
  and fp:find('if GuildOS.ConsumableChecker then Hdr(L["NO CONS"]', 1, true),
  "the raid settings, the attendance tooltip and the session detail offer consumables only with the checker")
check(fp:find('if GuildOS.AttunementTracker then[^\n]*\n%s*local hAtt'), "the trials list shows attunements only with the tracker")
check(src("UI/CorePanel.lua"):find('if GuildOS.ConsumableChecker then\n?%s*penFields%[#penFields %+ 1%] = { key = "NO_CONSUMES"'),
  "a core's penalties offer consumables only with the checker")
local md = src("UI/MemberDetail.lua")
check(md:find("if GuildOS.AttunementTracker then%s*local attColor") and
  md:find('(GuildOS.AttunementTracker and L["Linked chars share attunements account-wide."])', 1, true),
  "a member's trial and linked characters name attunements only with the tracker")

print(("retail-leftovers: %d checks passed"):format(checks))
