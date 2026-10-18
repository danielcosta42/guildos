-- Member keys on retail (issue #165), run against the real Core/Utils.lua and Modules/Alliance.lua
-- under a stubbed client.
--
-- On retail a realm is part of who somebody is, as on TBC Anniversary, and a guild spans connected
-- realms: "Ana-Azralon" and "Ana-Gallywix" are two people. WoW: Forever's rule (issue #95: ignore a
-- caller's realm, use the client's) and its start-up rekey (#97) would merge them. Retail spells
-- realms the way its roster and every addon-message sender do, normalized: no spaces, no hyphens.
-- This proves the key keeps each member's own realm, normalized; that a carried key passes through;
-- that the start-up passes leave two connected-realm namesakes alone; that the alliance bridge
-- hashes the whole key; and that Forever and Anniversary keep their rules.
--
--   luajit -e 'ADDON="."' tools/retail-keys.lua
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

local REALM, NORM = "Tol Barad", "TolBarad"   -- GetRealmName(), GetNormalizedRealmName()
function GetRealmName() return REALM end
function GetNormalizedRealmName() return NORM end
function GetServerTime() return 1757800000 end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
C_Timer = { After = function() end, NewTicker = function() end }
function LibStub() return {} end   -- the alliance's wire libraries; the election never serializes
strsplit = function(sep, s)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return unpack(out)
end

GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  Compat = { IsSecret = function() return false end },
  SelfTest = { Register = function() end },
  Client = { isAnniversary = false, isRetail = true },
}
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/Alliance.lua")

-- ── 1. The key, on retail ──────────────────────────────────────────────
check(GuildOS:RealmBound() == true, "a realm is part of who somebody is on retail")
check(GuildOS:GetPlayerKey("Ana", "Azralon") == "Ana-Azralon", "a caller's realm is kept on retail")
check(GuildOS:GetPlayerKey("Ana") == "Ana-TolBarad", "with no realm, the client's, normalized")
check(GuildOS:GetPlayerKey("Ana", "") == "Ana-TolBarad", "an empty realm counts as none")
check(GuildOS:GetPlayerKey("Ana", "Tol Barad") == "Ana-TolBarad", "a realm with a space is normalized")
check(GuildOS:GetPlayerKey("Ana", "Azjol-Nerub") == "Ana-AzjolNerub", "a realm with a hyphen is normalized")
check(GuildOS:GetPlayerKey("Ana", GetRealmName()) == GuildOS:GetPlayerKey("Ana", "TolBarad"),
  "a key from GetRealmName() and one from a roster line are the same key")
check(GuildOS:GetClientRealm() == "TolBarad", "the client's realm is the normalized one on retail")
check(GuildOS:LocalMemberKey("Ana-Gallywix") == "Ana-Gallywix", "a carried key passes through on retail")

-- ── 2. Start-up leaves connected-realm namesakes apart ─────────────────
GuildOS.db = {
  members = {
    ["Ana-Azralon"] = { name = "Ana", lastUpdate = 1 },
    ["Ana-Gallywix"] = { name = "Ana", lastUpdate = 2 },
  },
  points = { standings = { ["Ana-Azralon"] = { current = 5 }, ["Ana-Gallywix"] = { current = 7 } } },
}
GuildOS:RekeyMembersToThisRealm()
GuildOS:LocalizeStoredMemberTables()
local m = GuildOS.db.members
check(m["Ana-Azralon"] and m["Ana-Gallywix"] and m["Ana-TolBarad"] == nil, "connected-realm namesakes stay two members")
check(GuildOS.db.points.standings["Ana-Azralon"].current == 5 and GuildOS.db.points.standings["Ana-Gallywix"].current == 7,
  "their points stay apart")
check(GuildOS.db.storedKeysLocalized == nil, "the Forever pass never runs on retail")

-- ── 3. The alliance bridge hashes the whole key on retail ──────────────
local A = GuildOS.Alliance
local keys = { "Ana-Azralon", "Ana-Gallywix", "Bob-Azralon" }
local best, bestHash
for _, k in ipairs(keys) do
  local h = A.Hash(k)
  if not best or h < bestHash or (h == bestHash and k < best) then best, bestHash = k, h end
end
check(A.ElectBridge(keys) == best, "the bridge election hashes the whole key on retail")

-- ── 4. Forever and Anniversary keep their rules ────────────────────────
GuildOS.Client = { isAnniversary = false }   -- a stub with no isRetail is Forever
REALM, NORM = "Classic Beta PvE", nil
check(GuildOS:RealmBound() == false, "no realm is part of anybody on Forever")
check(GuildOS:GetPlayerKey("Chehul Costa", "Other") == "Chehul Costa-Classic Beta PvE",
  "Forever ignores the caller's realm and keeps the client's bytes")
check(GuildOS:LocalMemberKey("Chehul Costa-Elsewhere") == "Chehul Costa-Classic Beta PvE", "Forever localizes a carried key")
GuildOS.Client = { isAnniversary = true }
REALM, NORM = "Tol Barad", "TolBarad"
check(GuildOS:GetPlayerKey("Ana", "Tol Barad") == "Ana-Tol Barad", "Anniversary keeps a realm's bytes")
check(GuildOS:GetPlayerKey("Ana") == "Ana-Tol Barad", "Anniversary's own realm is GetRealmName()")

print(("retail-keys: %d checks passed"):format(checks))
