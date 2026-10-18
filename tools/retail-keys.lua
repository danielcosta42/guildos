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

-- ── 4b. A roster line's key, as the core picker files a guildmate (review of #165) ──
GuildOS.Client = { isAnniversary = false, isRetail = true }
REALM, NORM = "Azralon", "Azralon"
check(GuildOS:KeyOfRosterName("Bob-Gallywix") == "Bob-Gallywix", "a connected-realm guildmate keeps their realm")
check(GuildOS:KeyOfRosterName("Bob") == "Bob-Azralon", "a roster name with no realm is on mine")
check(GuildOS:KeyOfRosterName("Cid-Tol Barad") == "Cid-TolBarad", "normalized")
local corePanel = io.open(ADDON .. "/UI/CorePanel.lua", "rb"):read("*a")
check(corePanel:find("GuildOS:KeyOfRosterName(gm.full)", 1, true) ~= nil, "the core's member picker files a guildmate by that key")

-- ── 5. Officer trust is the whole key on retail (review of #165) ─────────
-- An officer's name on one connected realm is not an officer on another: an addon message from
-- Bob-Gallywix must not carry Bob-Azralon's rank. Forever keeps matching by name.
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function hooksecurefunc() end
function debugstack() return "" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local ROSTER = { { "Bob-Azralon", 0 }, { "Bob-Gallywix", 5 }, { "Cid-TolBarad", 1 } }
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2] end end
local GUILD_REALM
function GetGuildInfo() return "Guild", "Rank", 1, GUILD_REALM end
dofile(ADDON .. "/Core/Core.lua")
GuildOS.Client = { isAnniversary = false, isRetail = true }
REALM, NORM = "Azralon", "Azralon"
GuildOS.db = { settings = { officerMaxRank = 1 } }
check(GuildOS:IsOfficerByName("Bob-Azralon"), "the officer is an officer")
check(not GuildOS:IsOfficerByName("Bob-Gallywix"), "a connected-realm namesake of an officer is not one")
check(GuildOS:IsOfficerByName("Bob"), "a sender with no realm is on mine")
check(not GuildOS:IsOfficerByName("Bob-Elsewhere"), "a namesake from a realm the guild is not on is not one")
check(GuildOS:IsOfficerByName("Cid-Tol Barad"), "a realm spelt with its space is the roster's")
GuildOS.Client = { isAnniversary = false }
check(GuildOS:IsOfficerByName("Bob-Whatever"), "Forever matches by name, as it always has")

-- ── 6. One guild, one database, whichever connected realm a character is on ──
local function dbKey(retail, playerRealm, guildRealm)
  GuildOS.Client = retail and { isAnniversary = false, isRetail = true } or { isAnniversary = true }
  REALM, NORM, GUILD_REALM = playerRealm, (playerRealm:gsub(" ", "")), guildRealm
  GuildOSDB, GuildOS.guildKey, GuildOS.db = {}, nil, nil
  GuildOS:ResolveGuildDB()
  return GuildOS.guildKey
end
check(dbKey(true, "Tol Barad", nil) == "Guild-TolBarad", "on its home realm the guild's database is the home realm's")
check(dbKey(true, "Gallywix", "TolBarad") == "Guild-TolBarad", "and a character on a connected realm opens the same one")
check(dbKey(false, "Tol Barad", nil) == "Guild-Tol Barad", "Anniversary keeps its keys' bytes")

-- ── 7. Two namesakes vote twice ─────────────────────────────────────────
GuildOS.Client = { isAnniversary = false, isRetail = true }
REALM, NORM = "Azralon", "Azralon"
GuildOS.db = { polls = { list = { p1 = { id = "p1", votes = {} } } } }
dofile(ADDON .. "/Modules/Polls.lua")
GuildOS.Polls.Refresh = function() end
GuildOS.Polls:OnSync({ act = "vote", data = { id = "p1", opt = 1 } }, "Ana-Azralon")
GuildOS.Polls:OnSync({ act = "vote", data = { id = "p1", opt = 2 } }, "Ana-Gallywix")
local votes = GuildOS.db.polls.list.p1.votes
check(votes["Ana-Azralon"] == 1 and votes["Ana-Gallywix"] == 2, "connected-realm namesakes cast two votes")
GuildOS.db.calendar = { events = { e1 = { id = "e1" } }, deleted = {} }
dofile(ADDON .. "/Modules/Calendar.lua")
GuildOS.Calendar.Refresh = function() end
GuildOS.Calendar:OnSync({ act = "rsvp", data = { id = "e1", status = "yes" } }, "Ana-Azralon")
GuildOS.Calendar:OnSync({ act = "rsvp", data = { id = "e1", status = "no" } }, "Ana-Gallywix")
local rsvps = GuildOS.db.calendar.events.e1.rsvps
check(rsvps["Ana-Azralon"].status == "yes" and rsvps["Ana-Gallywix"].status == "no", "and answer an event twice")

print(("retail-keys: %d checks passed"):format(checks))
