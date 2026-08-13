-- Feeds a real GOSROST1 string, produced by the website, through the real
-- CompanionImport under stubbed WoW APIs.
--
-- Same reason as tools/companion-payload.lua: the two halves of this format
-- live in different repositories, so the only way to know they agree is to run
-- both. That round trip caught GOSCOMP1 missing its colon.
--
--   lua5.1 -e 'ADDON="."' tools/roster-import.lua tools/roster-fixture.txt
--
-- The fixture came out of the website's own encoder
-- (packages/goscomp/test/make-roster.ts in guildos-web); regenerate it there if
-- the format changes.
ADDON = ADDON or "."
local DEFAULT_FIXTURE = "tools/roster-fixture.txt"
package.path = ADDON .. "/?.lua;" .. package.path

local rosterFile = (arg and arg[1]) or (ADDON .. "/" .. DEFAULT_FIXTURE)

-- ── WoW API surface the import touches ────────────────────────────────
-- A raid of three, one of whom is already present and one of whom is in the
-- wrong party — enough to exercise both "skip" and "move".
local RAID = {
  { "Chehul", 0, 1 },   -- name, rank, subgroup
  { "Fulano", 0, 5 },
}
function IsInRaid() return true end
function GetNumGroupMembers() return #RAID end
function GetRaidRosterInfo(i)
  local r = RAID[i]
  if not r then return nil end
  return r[1], r[2], r[3]
end
function UnitName(unit)
  if unit == "player" then return "Chehul" end
  local i = tonumber(tostring(unit):match("%d+") or "")
  return i and RAID[i] and RAID[i][1] or nil
end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end
function GetRealmName() return "Firemaw" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
-- CompanionExport hangs a PLAYER_LOGOUT frame off its file scope; this only has
-- to let the file load, since nothing here fires the event.
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function() end }
end

INVITED, MOVED = {}, {}
function InviteUnit(name) INVITED[#INVITED + 1] = name end
function SetRaidSubgroup(index, group) MOVED[#MOVED + 1] = RAID[index][1] .. "->" .. group end

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

BRutus = {
  VERSION = "0.46.0",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true } },
}
function BRutus:GetSetting(k) return self.db.settings[k] end
function BRutus:SetSetting(k, v) self.db.settings[k] = v end
function BRutus:GetPlayerKey(n, r) return n .. "-" .. (r or GetRealmName()) end
function BRutus:Print(...) print(...) end

dofile(ADDON .. "/Libs/LibDeflate.lua")

-- SoftResSystem owns the JSON decoder the import reuses. Loading the whole file
-- would drag in tooltip hooks, so lift just the decoder the same way it exports it.
local softres = io.open(ADDON .. "/Modules/SoftResSystem.lua"):read("*a")
local decoderSrc = softres:match("(local function JsonDecode.-\nend\n)")
assert(decoderSrc, "could not find JsonDecode in SoftResSystem.lua")
BRutus.JsonDecode = assert(loadstring(decoderSrc .. "\nreturn JsonDecode"))()

dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")

-- ── run ───────────────────────────────────────────────────────────────
local raw = io.open(rosterFile):read("*a")

local n, err = BRutus.CompanionImport:Load(raw)
if not n then
  io.stderr:write("LOAD FAILED: " .. tostring(err) .. "\n")
  os.exit(1)
end

local roster = BRutus.CompanionImport:Current()
print("loaded: " .. roster.title .. " (" .. n .. " members)")
for _, m in ipairs(roster.members) do
  print(string.format("  %s %s %s group=%d", m.name, m.class, m.slot, m.group))
end

local invited, skipped, ierr = BRutus.CompanionImport:InviteAll()
assert(not ierr, ierr)
print(string.format("invited=%d skipped=%d -> %s", invited, skipped, table.concat(INVITED, ",")))

local moved, gerr = BRutus.CompanionImport:OrganizeGroups()
assert(not gerr, gerr)
print(string.format("moved=%d -> %s", moved, table.concat(MOVED, ",")))

-- ── v2: everyone who answered ─────────────────────────────────────────
--
-- `members` is frozen at "who can be invited" and the two assertions above already
-- proved the invite and group behaviour is what it always was. This is the list
-- beside it, which is the whole point of v2: eighteen invitable names used to
-- arrive and the three people who fell out on the way were indistinguishable from
-- three who never signed up.
local sign = roster.signups
assert(sign, "the v2 fixture decoded without a signups list")
assert(#sign == 8, "expected eight answers, got " .. #sign)
assert(roster.size == 10, "the raid size did not travel")
assert(roster.instanceKey == "kara", "the instance key did not travel")

local by = {}
for _, s in ipairs(sign) do by[s.name] = s end

-- Exactly the invitable, and in the same order. If these two ever drift, an addon
-- that only reads `members` is being lied to.
local invitable = {}
for _, s in ipairs(sign) do
  if s.invite then invitable[#invitable + 1] = s.name end
end
assert(#invitable == #roster.members, "members and the invitable slice disagree on size")
for i, m in ipairs(roster.members) do
  assert(m.name == invitable[i], "members drifted out of order at " .. i)
end

assert(by["Novato"] and by["Novato"].invite == false, "an unconfirmed character is invitable")
assert(by["Novato"].why == "unknown", "no reason given for the one name a leader can fix")
assert(by["Vex"].wait == 1 and by["Tarn"].wait == 2, "standby lost its order")
assert(by["Gorn"].why == "no" and by["Mira"].why == "tentative", "the reasons did not survive")
print(string.format("v2: %d answers, %d invitable, %d on standby",
  #sign, #invitable, (by["Vex"] and 1 or 0) + (by["Tarn"] and 1 or 0)))

-- ── which planned raid is this night ──────────────────────────────────
--
-- The other direction. RaidTracker asks this when a session opens, and the answer
-- is what stops the website having to guess from an instance name and a clock.
BRutus.db.companionRaids = {
  { raidId = "raid-abc", instanceKey = "kara", startsAt = 1754604000 },
  { raidId = "raid-xyz", instanceKey = "gruul", startsAt = 1754604000 },
}
local RF = function(k, t) return BRutus.CompanionImport:RaidFor(k, t) end

assert(RF("kara", 1754604000) == "raid-abc", "the raid did not match at its own start")
assert(RF("kara", 1754604000 - 3600) == "raid-abc", "an hour early is still the same night")
assert(RF("kara", 1754604000 + 7 * 3600) == "raid-abc", "seven hours in is still the same night")
assert(RF("gruul", 1754604000) == "raid-xyz", "the key picked the wrong raid")

-- Outside the window, and outside the catalogue. Both have to answer nothing:
-- a night attached to the wrong raid accuses the right person on the wrong evening,
-- which is worse than no attendance at all.
assert(RF("kara", 1754604000 - 3 * 3600) == nil, "three hours early matched anyway")
assert(RF("kara", 1754604000 + 9 * 3600) == nil, "nine hours late matched anyway")
assert(RF("swp", 1754604000) == nil, "an instance nobody booked matched")
assert(RF(nil, 1754604000) == nil, "a missing key matched")
print("stamp: the window agrees with the website's, and refuses everything outside it")

-- ── what the site said back ───────────────────────────────────────────
_G.GuildOSInboxAck = { at = 1755291600, members = 137 }
local ackAt, ackN = BRutus.CompanionImport:Ack()
assert(ackAt == 1755291600 and ackN == 137, "the acknowledgement did not come through")
_G.GuildOSInboxAck = { at = 0 }
assert(BRutus.CompanionImport:Ack() == nil, "an empty acknowledgement was reported as one")
_G.GuildOSInboxAck = nil
assert(BRutus.CompanionImport:Ack() == nil, "no acknowledgement produced one anyway")
print("ack: present when it is, absent when it is not")

-- The gate has to hold on both entry points.
BRutus.Companion:SetEnabled(false)
local _, offErr = BRutus.CompanionImport:Parse(raw)
assert(offErr and offErr:find("off"), "import ran with the companion switched off")
local _, _, offErr2 = BRutus.CompanionImport:InviteAll()
assert(offErr2 and offErr2:find("off"), "invite ran with the companion switched off")
print("gate: holds when the companion is off")
