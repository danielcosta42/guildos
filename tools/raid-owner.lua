-- Which raid the buttons act on, and whether it is this character's own (issue #400; the site's #603,
-- GOSROST1 v7 `owners`), run against the real Utils, Compat and CompanionImport under three stubbed clients:
-- WoW: Forever (the whole name with its surname, UnitName gives the first name only), TBC Anniversary and
-- retail (Name-Realm).
--
--   luajit -e 'ADDON="."' tools/raid-owner.lua
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

local NOW = 1791000000
function GetServerTime() return NOW end
function time() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function debugstack() return "" end
function IsInGuild() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
StaticPopupDialogs = {}
Enum = { SendAddonMessageResult = {} }

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
  minor = 1,
}, {
  __call = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
})

-- What the client's GetNormalizedRealmName answers, written out rather than worked out the way the code under test
-- works it out: the realm without its spaces and hyphens, its apostrophes kept ("Mal'Ganis" stays). The site
-- normalises the owners' realms the same way. A realm missing here fails loudly, so a new case says what the game says.
local NORMALIZED = {
  ["Classic Beta PvE"] = "ClassicBetaPvE", ["Mankrik"] = "Mankrik", ["Tol Barad"] = "TolBarad",
  ["Mal'Ganis"] = "Mal'Ganis", ["Azjol-Nerub"] = "AzjolNerub", ["Area 52"] = "Area52",
}

-- A fresh addon on the client described, as the game would load it.
local function boot(client)
  GuildOS = {
    VERSION = "0.0.0",
    L = setmetatable({}, { __index = function(_, k) return k end }),
    db = { settings = { companion = true } },
  }
  function GuildOS:GetSetting(k) return self.db.settings[k] end
  function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
  function GetBuildInfo() return client.version, "1", "", client.interface end
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = client.project, 1, 5
  C_PlayerInfo = client.surnames and { ShouldDisplaySurname = function() return true end } or nil
  function UnitName() return client.first end
  function UnitFullName() return client.first, client.second end
  function GetRealmName() return client.realm end
  function GetNormalizedRealmName() return assert(NORMALIZED[client.realm], "no normalized name for " .. client.realm) end
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  function GuildOS:Print() end
  dofile(ADDON .. "/Libs/LibDeflate.lua")
  dofile(ADDON .. "/Modules/CompanionExport.lua")
  dofile(ADDON .. "/Modules/CompanionImport.lua")
  return GuildOS.CompanionImport
end

local function raidOf(owners, startsAt, id)
  return { raidId = id or "r", startsAt = startsAt or NOW, members = {}, owners = owners }
end

-- ── WoW: Forever: "Chehul Costa", no realm, and UnitName gives "Chehul" alone ─────────────
local Import = boot({ version = "1.60.1", interface = 16001, project = 99, surnames = true,
                      first = "Chehul", second = "Costa", realm = "Classic Beta PvE" })
check(GuildOS.Client.game == "FOREVER", "the Forever stub is a Forever client")
check(Import:IsMine(raidOf({ "Chehul Costa" })), "Forever: the whole name with the surname is mine")
check(Import:IsMine(raidOf({ "Fulano Lima", "chehul COSTA" })), "Forever: case does not matter, any owner of the list")
check(not Import:IsMine(raidOf({ "Chehul" })), "Forever: the first name alone is not mine")
check(not Import:IsMine(raidOf({ "Chehul Silva" })), "Forever: another surname is not mine")
check(not Import:IsMine(raidOf({ "Chehul Costa-Classic Beta PvE" })), "Forever: a name with a realm is not the key there")
check(not Import:IsMine(raidOf(nil)), "no owners is not mine")
check(not Import:IsMine(raidOf({})), "an empty list of owners is not mine")
check(not Import:IsMine(nil), "no roster is not mine")

-- ── TBC Anniversary: Name-Realm ───────────────────────────────────────────────────────────
Import = boot({ version = "2.5.6", interface = 20506, project = 5, first = "Chehul", realm = "Mankrik" })
check(GuildOS.Client.game == "ANNIVERSARY", "the Anniversary stub is an Anniversary client")
check(Import:IsMine(raidOf({ "Chehul-Mankrik" })), "Anniversary: Name-Realm is mine")
check(Import:IsMine(raidOf({ "chehul-MANKRIK" })), "Anniversary: case does not matter")
check(not Import:IsMine(raidOf({ "Chehul-Firemaw" })), "Anniversary: the same name on another realm is not mine")
check(not Import:IsMine(raidOf({ "Chehul" })), "Anniversary: the name without its realm is not the key")

-- ── Retail: Name-Realm, the realm without spaces ──────────────────────────────────────────
Import = boot({ version = "12.1.5", interface = 120105, project = 1, first = "Chehul", realm = "Tol Barad" })
check(GuildOS.Client.game == "RETAIL", "the retail stub is a retail client")
check(Import:IsMine(raidOf({ "Chehul-TolBarad" })), "retail: Name-Realm with this character's realm is mine")
check(Import:IsMine(raidOf({ "CHEHUL-tolbarad" })), "retail: case does not matter")
check(not Import:IsMine(raidOf({ "Chehul-Azralon" })), "retail: a namesake on another realm is not mine")

-- Realms with an apostrophe, a hyphen and a space, as the site sends them: spaces and hyphens out, apostrophes kept.
local RETAIL = { version = "12.1.5", interface = 120105, project = 1, first = "Chehul" }
local function onRealm(realm)
  local c = {}
  for k, v in pairs(RETAIL) do c[k] = v end
  c.realm = realm
  return boot(c)
end
Import = onRealm("Mal'Ganis")
check(Import:IsMine(raidOf({ "Chehul-Mal'Ganis" })), "retail on Mal'Ganis: the apostrophe is kept, and it is mine")
check(Import:IsMine(raidOf({ "chehul-mal'ganis" })), "retail on Mal'Ganis: case does not matter")
check(not Import:IsMine(raidOf({ "Chehul-MalGanis" })), "retail on Mal'Ganis: without the apostrophe it is another key")
Import = onRealm("Azjol-Nerub")
check(Import:IsMine(raidOf({ "Chehul-AzjolNerub" })), "retail on Azjol-Nerub: the hyphen goes, and it is mine")
check(not Import:IsMine(raidOf({ "Chehul-Azjol-Nerub" })), "retail on Azjol-Nerub: with the hyphen kept it is not the key")
Import = onRealm("Area 52")
check(Import:IsMine(raidOf({ "Chehul-Area52" })), "retail on Area 52: the space goes, and it is mine")
check(not Import:IsMine(raidOf({ "Chehul-Area 52" })), "retail on Area 52: with the space kept it is not the key")
check(not Import:IsMine(raidOf({ "Chehul-TolBarad" })), "retail on Area 52: my name on another realm is not mine")

-- ── Parse reads `owners`: strings only, clipped, at most 12 ───────────────────────────────
local function encode(json)
  local LibDeflate = LibStub("LibDeflate")
  return "GOSROST1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json))
end
local long = string.rep("x", 100)
local parsed = Import:Parse(encode('{"fmt":"GOSROST1","v":7,"raidId":"a","title":"t","startsAt":' .. NOW ..
  ',"members":[],"owners":["Chehul-TolBarad",7,"' .. long .. '",null,{"a":1},"Ana-Azralon"]}'))
check(parsed and parsed.owners, "Parse keeps the owners")
check(#parsed.owners == 3, "Parse ignores what is not a string (" .. tostring(parsed and #parsed.owners) .. ")")
check(parsed.owners[1] == "Chehul-TolBarad" and #parsed.owners[2] == 64 and parsed.owners[3] == "Ana-Azralon",
  "Parse cuts each owner to 64 bytes")
local many = {}
for i = 1, 20 do many[i] = '"Pessoa' .. i .. '-Azralon"' end
parsed = Import:Parse(encode('{"fmt":"GOSROST1","v":7,"raidId":"a","title":"t","startsAt":' .. NOW ..
  ',"members":[],"owners":[' .. table.concat(many, ",") .. ']}'))
check(#parsed.owners == 12, "Parse keeps at most 12 owners")
parsed = Import:Parse(encode('{"fmt":"GOSROST1","v":6,"raidId":"a","title":"t","startsAt":' .. NOW .. ',"members":[]}'))
check(parsed and parsed.owners == nil, "a roster from a site before v7 has no owners")
parsed = Import:Parse(encode('{"fmt":"GOSROST1","v":7,"raidId":"a","title":"t","startsAt":' .. NOW ..
  ',"members":[],"owners":"Chehul-TolBarad"}'))
check(parsed and parsed.owners == nil, "owners that is not a list is nothing")

-- ── ButtonRaid: from an hour before the start to three hours after it (spec 115) ────────────
local H = 3600
Import._webRaids = {
  raidOf(nil, NOW - 5 * H, "old"),
  raidOf(nil, NOW + 2 * H, "later"),
  raidOf(nil, NOW + 30 * 60, "soon"),
  raidOf(nil, NOW + 3 * 86400, "days"),
}
GuildOS.db.companionRoster = nil
check(Import:ButtonRaid(NOW).raidId == "soon", "ButtonRaid picks the nearest inside the window")
check(Import:ButtonRaid().raidId == "soon", "ButtonRaid asks the server time without a `now`")
local function idOf(r) return r and r.raidId end
Import._webRaids = { raidOf(nil, NOW + 50 * 60, "in50") }
check(idOf(Import:ButtonRaid(NOW)) == "in50", "a raid starting in 50 minutes is the button's")
Import._webRaids = { raidOf(nil, NOW - 2 * H, "began2h") }
check(idOf(Import:ButtonRaid(NOW)) == "began2h", "a raid that began two hours ago still is: the night goes on")
Import._webRaids = { raidOf(nil, NOW + 2 * H, "in2h") }
check(Import:ButtonRaid(NOW) == nil, "a raid starting in two hours is not yet")
Import._webRaids = { raidOf(nil, NOW - 4 * H, "began4h") }
check(Import:ButtonRaid(NOW) == nil, "a raid that began four hours ago is over for the buttons")
Import._webRaids = { raidOf(nil, NOW - 5 * H, "old") }
check(Import:ButtonRaid(NOW) == nil, "a raid that began five hours ago is never the button's")
Import._webRaids = { raidOf(nil, NOW - 50 * 60, "began"), raidOf(nil, NOW + 4 * H, "far") }
check(Import:ButtonRaid(NOW).raidId == "began", "one that began 50 minutes ago still is; four hours ahead is not")
Import._webRaids = { raidOf(nil, NOW + H, "edge-ahead"), raidOf(nil, NOW - 3 * H - 60, "edge-behind") }
check(idOf(Import:ButtonRaid(NOW)) == "edge-ahead", "an hour ahead is the window's edge, and inside it")
Import._webRaids = { raidOf(nil, NOW + H + 1, "edge") }
check(Import:ButtonRaid(NOW) == nil, "just past an hour ahead is outside")
Import._webRaids = { raidOf(nil, NOW - 3 * H - 1, "edge") }
check(Import:ButtonRaid(NOW) == nil, "just past three hours behind is outside")
Import._webRaids = nil
check(Import:ButtonRaid(NOW) == nil, "nothing loaded, nothing to act on")
GuildOS.db.companionRoster = raidOf(nil, NOW + H, "kept")
check(Import:ButtonRaid(NOW).raidId == "kept", "the kept roster counts when the inbox is not loaded")
GuildOS.db.companionRoster = raidOf(nil, NOW - 6 * H, "kept-old")
check(Import:ButtonRaid(NOW) == nil, "a kept roster of six hours ago is out of the window too")
GuildOS.db.companionRoster = raidOf(nil, NOW + H, "kept")
Import._webRaids = { raidOf(nil, NOW + 10 * 60, "closer") }
check(Import:ButtonRaid(NOW).raidId == "closer", "the nearest of the inbox and the kept one wins")
GuildOS.db.companionRoster = nil
Import._webRaids = { { raidId = "zero", startsAt = 0, members = {} } }
check(Import:ButtonRaid(NOW) == nil, "a roster without a start time is outside the window")
-- Two raids as far from now, one begun and one ahead: the one under way is the button's, in either order.
Import._webRaids = { raidOf(nil, NOW + 30 * 60, "ahead"), raidOf(nil, NOW - 30 * 60, "underway") }
check(Import:ButtonRaid(NOW).raidId == "underway", "a tie goes to the raid already under way")
Import._webRaids = { raidOf(nil, NOW - 30 * 60, "underway"), raidOf(nil, NOW + 30 * 60, "ahead") }
check(Import:ButtonRaid(NOW).raidId == "underway", "a tie goes to the raid already under way, whichever comes first")
Import._webRaids = { raidOf(nil, NOW + 30 * 60, "ahead") }
GuildOS.db.companionRoster = raidOf(nil, NOW - 30 * 60, "kept-underway")
check(Import:ButtonRaid(NOW).raidId == "kept-underway", "the kept roster under way wins a tie with the inbox's")
GuildOS.db.companionRoster = nil

-- ── A roster pasted by hand is the newest word on its raid (the inbox is read at login only) ──────
local stale = { raidId = "r1", startsAt = NOW + 1800, members = { { name = "Old Layout", group = 1 } } }
local pasted = { raidId = "r1", startsAt = NOW + 1800, members = { { name = "New Layout", group = 2 } }, pasted = true }
Import._webRaids = { stale }
GuildOS.db.companionRoster = pasted
check(Import:ButtonRaid(NOW) == pasted and Import:ActiveRoster(NOW) == pasted,
  "a pasted copy of the inbox's raid wins the tie: its new groups are what the buttons act on")
local moved = { raidId = "r1", startsAt = NOW + 3000, members = {}, pasted = true }
GuildOS.db.companionRoster = moved
check(Import:ButtonRaid(NOW) == moved, "and wins with a start the site moved, though the inbox's copy is nearer")
check(Import:Freshest(stale) == moved and Import:Freshest(raidOf(nil, NOW, "other")).raidId == "other",
  "Freshest gives the pasted copy of the same raid, and leaves another raid be")
GuildOS.db.companionRoster = { raidId = "r1", startsAt = NOW + 5 * 3600, members = {}, pasted = true }
check(Import:ButtonRaid(NOW) == nil, "a pasted copy moved out of the window takes its raid out with it")
Import._webRaids = { stale, raidOf(nil, NOW + 3500, "r2") }
GuildOS.db.companionRoster = moved
check(Import:ButtonRaid(NOW) == moved, "another raid of the inbox further away does not win over the paste")
Import._webRaids = { stale, raidOf(nil, NOW + 600, "r3") }
check(Import:ButtonRaid(NOW).raidId == "r3", "one nearer, another raid, still does")
-- Another guild's: pasted by hand it counts (a federation core's raid, ruling R9); from the inbox it never does.
function GetGuildInfo() return "Filhos da Horda" end
Import._webRaids = { { raidId = "f1", startsAt = NOW + 600, members = {}, guild = "Horda Unida" } }
GuildOS.db.companionRoster = { raidId = "f2", startsAt = NOW + 1200, members = {}, guild = "Horda Unida", pasted = true }
check(Import:ButtonRaid(NOW).raidId == "f2", "another guild's raid pasted by hand is the button's; the inbox's is not")
GuildOS.db.companionRoster.pasted = nil
check(Import:ButtonRaid(NOW) == nil, "kept without being pasted, another guild's raid is nobody's button")
GetGuildInfo = nil
Import._webRaids, GuildOS.db.companionRoster = nil, nil

print(string.format("raid-owner: %d checks passed", checks))
