-- One key per member on WoW: Forever, whatever realm the sender's client answers (issue #95),
-- run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua,
-- Modules/DataCollector.lua and Modules/PugInspector.lua.
--
-- Forever has no realms that set players apart: a name is unique in its region, and the guild
-- roster gives none. Yet GetRealmName() answers a name, and not the same one for everybody in a
-- guild: on the beta, "Classic Beta PvE" for one member and "Classic Beta PvE 2" for another.
-- The roster keyed a member with this client's realm and a broadcast with the sender's, so a
-- guildmate's data never met their roster line: "Player does not have Guild OS installed".
--
--   luajit -e 'ADDON="."' tools/forever-keys.lua
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

local MY_REALM = "Classic Beta PvE 2"
local ROSTER = { "Chehul Costa", "Cherry Arrow" }      -- Forever's roster: names, no realm

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
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Chehul" end
  end
  function GetRealmName() return MY_REALM end
  function GetNormalizedRealmName() return (MY_REALM:gsub("%s", "")) end
  function GetServerTime() return 1791000000 end
  function GetTime() return 1 end
  time = os.time
  function IsInGuild() return true end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i) if ROSTER[i] then return ROSTER[i], "Member", 5, 30, "Hunter", "", "", "", true, 0, "HUNTER" end end
  C_Timer = { After = function() end, NewTicker = function() end }
  Enum = { SendAddonMessageResult = {} }
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  local store = {}
  LibStub("GuildOS-LibSerialize").Serialize = function(_, t) store[#store + 1] = t; return tostring(#store) end
  LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) return store[tonumber(s)] ~= nil, store[tonumber(s)] end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/CommSystem.lua")
  dofile(ADDON .. "/Modules/DataCollector.lua")
  dofile(ADDON .. "/Modules/PugInspector.lua")
  GuildOS.db = { members = {}, settings = {} }
  return function(t) return LibStub("GuildOS-LibSerialize"):Serialize(t) end
end

-- The roster frame's own key for a roster line (UI/RosterFrame.lua BuildMemberList).
local function rosterKey(name)
  local displayName = name:match("^([^-]+)") or name
  local realm = name:match("-(.+)$") or GetRealmName()
  return GuildOS:GetPlayerKey(displayName, realm)
end

-- ── 1. Forever: the sender's realm does not split a member ──────────────
local ser = load("forever")
local expected = "Cherry Arrow-" .. MY_REALM
check(rosterKey("Cherry Arrow") == expected, "forever: the roster line's key carries this client's realm")
check(GuildOS:GetPlayerKey("Cherry Arrow", "Classic Beta PvE") == expected,
  "forever: a realm from elsewhere does not change the key")
check(GuildOS:GetPlayerKey("Cherry Arrow", "ClassicBetaPvE") == expected, "forever: nor does a normalized one")

-- A broadcast from a guildmate whose client answers another realm, sent the way 0.59.3 sends it.
GuildOS.CommSystem:HandleBroadcast("Cherry Arrow-ClassicBetaPvE",
  ser({ name = "Cherry Arrow", realm = "Classic Beta PvE", class = "HUNTER", level = 21, avgIlvl = 18,
        lastUpdate = 1790991824, addonVersion = "0.59.3" }))
local got = GuildOS.db.members[rosterKey("Cherry Arrow")]
check(got and got.avgIlvl == 18 and got.addonVersion == "0.59.3",
  "forever: her data lands on her roster line, so the roster sees Guild OS and her item level")
check(GuildOS.db.members["Cherry Arrow-Classic Beta PvE"] == nil, "forever: and not under a key the roster never asks")
local rows = GuildOS.CommSystem:GetSyncHealth()
local cherry
for _, r in ipairs(rows) do if r.name == "Cherry Arrow" then cherry = r end end
check(cherry and cherry.hasAddon and cherry.version == "0.59.3", "forever: the guild's sync health shows her with Guild OS 0.59.3")

-- The same with no suffix on the sender and no realm in the payload.
GuildOS.CommSystem:HandleBroadcast("Chehul Druida",
  ser({ name = "Chehul Druida", class = "DRUID", level = 10, lastUpdate = 1790000000 }))
check(GuildOS.db.members["Chehul Druida-" .. MY_REALM], "forever: a bare sender keys the same way")

-- A group member, as the group APIs name them: the same key as their roster line.
local seen
GuildOS.PugInspector:Classify("Cherry Arrow-ClassicBetaPvE", { realm = GuildOS:GetClientRealm() or "", guildShort = {},
  altLinks = {}, noteFor = function(_, _, key) seen = key end })
check(seen == expected, "forever: the group inspector keys a guildmate like the roster does")

-- The in-game self-tests that key members still pass on Forever.
local selfTests = {}
GuildOS.SelfTest = { Register = function(_, name, fn) selfTests[name] = fn end }
GuildOS.PugInspector:_RegisterTests()
local okST, why = selfTests["pug.classify_keyform"]()
check(okST, "forever: the pug inspector's key-form self-test passes (" .. tostring(why) .. ")")
GuildOS.SelfTest = nil

-- ── 2. Forever: what an earlier version stored under the sender's realm ──
load("forever")
GuildOS.db.members = {
  ["Cherry Arrow-Classic Beta PvE"]  = { name = "Cherry Arrow", class = "HUNTER", lastUpdate = 300, avgIlvl = 18 },
  ["Cherry Arrow-" .. MY_REALM]      = { name = "Cherry Arrow", class = "HUNTER", lastUpdate = 100, avgIlvl = 9 },
  ["Allyah Fon-Classic Beta PvE"]    = { name = "Allyah Fon", class = "PRIEST", lastUpdate = 50 },
  ["Old One-" .. MY_REALM]           = { name = "Old One", class = "MAGE", lastUpdate = 999 },
  ["Stale Too-Classic Beta PvE"]     = { name = "Stale Too", class = "MAGE", lastUpdate = 10, look = "kept" },
  ["Stale Too-" .. MY_REALM]         = { name = "Stale Too", class = "MAGE", lastUpdate = 20 },
  ["Tie Here-Classic Beta PvE"]      = { name = "Tie Here", class = "MAGE", lastUpdate = 5, avgIlvl = 1 },
  ["Tie Here-" .. MY_REALM]          = { name = "Tie Here", class = "MAGE", lastUpdate = 5, avgIlvl = 2 },
  ["No Stamp-Classic Beta PvE"]      = { name = "No Stamp", spec = "Holy" },
  ["No Stamp-" .. MY_REALM]          = { name = "No Stamp" },
  ["Nameless-Classic Beta PvE"]      = {},
}
GuildOS.DataCollector:Initialize()                        -- the wiring: the migration runs at start-up
local m = GuildOS.db.members
check(m["Cherry Arrow-" .. MY_REALM].lastUpdate == 300 and m["Cherry Arrow-Classic Beta PvE"] == nil,
  "forever: a newer record under another realm takes the right key, the older one goes")
check(m["Allyah Fon-" .. MY_REALM] and m["Allyah Fon-Classic Beta PvE"] == nil, "forever: one alone simply moves")
check(m["Stale Too-" .. MY_REALM].lastUpdate == 20 and m["Stale Too-Classic Beta PvE"] == nil,
  "forever: an older one under another realm never overwrites a newer one")
check(m["Stale Too-" .. MY_REALM].look == "kept", "forever: but what only the older one knew is kept")
check(m["Tie Here-" .. MY_REALM].avgIlvl == 2, "forever: a tie keeps the record already on the right key")
check(m["No Stamp-" .. MY_REALM] and m["No Stamp-" .. MY_REALM].spec == "Holy" and m["No Stamp-Classic Beta PvE"] == nil,
  "forever: records with no timestamp move without raising")
check(m["Nameless-Classic Beta PvE"] ~= nil, "forever: a record with no name is left where it is")
GuildOS:RekeyMembersToThisRealm()
check(m["Stale Too-" .. MY_REALM].lastUpdate == 20, "forever: running again changes nothing")
check(m["Old One-" .. MY_REALM].lastUpdate == 999, "forever: a record already right is left alone")
local n = 0
for _ in pairs(m) do n = n + 1 end
check(n == 7, "forever: nobody is counted twice afterwards")

-- ── 3. Anniversary: realms are real, and keys keep their bytes ──────────
load("anniversary")
check(GuildOS:GetPlayerKey("Bob", "Spineshatter") == "Bob-Spineshatter", "anniversary: another realm still keys apart")
check(GuildOS:GetPlayerKey("Bob") == "Bob-" .. MY_REALM, "anniversary: no realm is this client's, as before")
GuildOS.db.members = { ["Bob-Spineshatter"] = { name = "Bob", class = "MAGE", lastUpdate = 1 } }
GuildOS:RekeyMembersToThisRealm()
check(GuildOS.db.members["Bob-Spineshatter"] ~= nil, "anniversary: the rekey leaves another realm's member where it is")

print(("forever-keys: %d checks passed"):format(checks))
