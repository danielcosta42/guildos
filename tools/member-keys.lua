-- Member identity without a realm (issue #8), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Core/Commands.lua and every module that used to
-- build a member key by hand, under a stubbed client.
--
-- WoW: Forever has no realms. A member key was always name .. "-" .. realm, and
-- several places built it themselves: with GetRealmName() returning nil they raised
-- (CommSystem on every incoming addon message), and LootMaster and the wishlist fell
-- back to "" in some places and "Unknown" in others, which splits one member across
-- two keys. This proves the one rule in BRutus:GetPlayerKey, that Anniversary keys
-- (tools/roster-fixture.txt included) keep 0.53.0's exact bytes, and that each of those
-- sites now gives the rule's key, with a realm and without one.
--
--   luajit -e 'ADDON="."' tools/member-keys.lua
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

-- ── The client ──────────────────────────────────────────────────────────
local NOW = 1757800000
local REALM, NORM, ME = "Firemaw", nil, "Ana"   -- GetRealmName(), GetNormalizedRealmName(), UnitName("player")
local GROUP, ROSTER = {}, {}   -- GROUP: { name, realm } per raid unit; ROSTER: guild roster full names
local LINK = "|cffa335ee|Hitem:30107::::::::70:::::|h[Vestments of the Sea-Witch]|h|r"

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:SetScript() end
  return f
end
function GetServerTime() return NOW end
function time() return NOW end
function IsInGuild() return true end
function hooksecurefunc() end
function debugstack() return "" end
-- TBC Anniversary, as Core/Compat.lua recognises it (ADR-0014), so the Anniversary-only
-- consumable check loads.
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower = string.lower
C_Timer = { After = function() end }
function GetRealmName() return REALM end
function GetNormalizedRealmName() return NORM end
function UnitName(unit)
  if unit == "player" then return ME end
  local m = GROUP[tonumber(tostring(unit):match("%d+$") or "")]
  if m then return m[1], m[2] end
end
function IsInRaid() return true end
function IsInGroup() return true end
function GetNumGroupMembers() return #GROUP end
function UnitExists(unit) return UnitName(unit) ~= nil end
function UnitIsConnected() return true end
function UnitClass() return "Priest", "PRIEST" end
function UnitBuff() return nil end
function GetSpellInfo() return nil end
function GetItemInfo() return "Vestments of the Sea-Witch", nil, 4 end
function GetInstanceInfo() return "Serpentshrine Cavern", "raid", 4, "", 25, 0, false, 548 end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  if ROSTER[i] then return ROSTER[i], "Raider", 4, 70, "Priest", "", "", "", true, 0, "PRIEST" end
end
function GetGuildInfo() return "Raid Guild" end
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Commands.lua")
for _, m in ipairs({ "CommSystem", "RaidTracker", "LootMaster", "WishlistSystem", "ConsumableChecker",
                     "PugInspector", "CompanionExport", "CompanionImport" }) do
  dofile(ADDON .. "/Modules/" .. m .. ".lua")
end
BRutus.db = { members = {}, lootHistory = {}, wishlists = {}, settings = { companion = true },
              raidTracker = { sessions = {} }, consumableChecks = { lastResults = {} }, lootMaster = {} }
BRutus.GetSetting = BRutus.GetSetting or function(self, k) return self.db.settings[k] end

local function K(...) return BRutus:GetPlayerKey(...) end
-- Runs fn with the client answering nothing: both realm functions nil, then both "".
local function realmless(fn)
  for _, r in ipairs({ false, "" }) do
    REALM, NORM = r or nil, r or nil
    fn(r and 'GetRealmName() and GetNormalizedRealmName() == ""' or "GetRealmName() and GetNormalizedRealmName() == nil")
  end
  REALM, NORM = "Firemaw", nil
end
local function sortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return table.concat(out, ",")
end

-- ── 1. With a realm, 0.53.0's bytes ─────────────────────────────────────
local function rule053(name, realm) realm = realm or GetRealmName(); return name .. "-" .. realm end
for _, realm in ipairs({ "Firemaw", "Living Flame", "Nek'Rosh", "Pyrewood Village" }) do
  REALM, NORM = realm, (realm:gsub("[%s']", ""))
  for _, name in ipairs({ "Ana", "Çlérigo", "Bob" }) do
    check(K(name) == rule053(name), name .. " on " .. realm .. " keeps its 0.53.0 key, not the normalized realm")
    check(K(name, "Spineshatter") == rule053(name, "Spineshatter"), name .. " from Spineshatter keeps its 0.53.0 key")
  end
end
REALM, NORM = "Firemaw", nil
check(K("Ana", "") == "Ana-Firemaw", "an empty realm from the caller counts as absent, so the client's realm fills it")
check(K(nil) == nil and K("") == nil and K(nil, "Firemaw") == nil, "no name gives no key, and nothing raises")

-- ── 2. The Anniversary roster fixture ───────────────────────────────────
dofile(ADDON .. "/Libs/LibDeflate.lua")
local softres = assert(io.open(ADDON .. "/Modules/SoftResSystem.lua", "rb")):read("*a"):gsub("\r\n", "\n")
BRutus.JsonDecode = assert(loadstring(assert(softres:match("(local function JsonDecode.-\nend\n)")) .. "\nreturn JsonDecode"))()
local fixture = assert(io.open(ADDON .. "/tools/roster-fixture.txt", "rb")):read("*a")
local roster, why = BRutus.CompanionImport:Parse(fixture)
check(roster and #roster.members > 0, "tools/roster-fixture.txt decodes through the real CompanionImport: " .. tostring(why))
for _, m in ipairs(roster.members) do
  local short, suffix = m.key:match("^([^-]+)") or m.key, m.key:match("-(.+)$")
  check(K(short, suffix) == rule053(short, suffix), "fixture member " .. m.key .. " keys as 0.53.0 did")
  if suffix then check(K(short, suffix) == m.key, "and rejoins to the site's key " .. m.key) end
  check(K(m.name) == rule053(m.name), "and its invite name " .. m.name .. " keys as 0.53.0 did")
end

-- ── 3. Without a realm, the name alone ──────────────────────────────────
realmless(function(how)
  check(K("Ana") == "Ana", how .. ": the key is the name alone")
  check(K("First Last") == "First Last" and K("First Last", "") == "First Last",
        how .. ": a two-part name is its own key")
  check(K("Ana", "Spineshatter") == "Ana-Spineshatter", how .. ": a realm the caller has still counts")
  for _, key in ipairs({ "Ana", "First Last", "Anne-Marie", "First Last-Suffix" }) do
    local short = key:match("^([^-]+)") or key
    local realm = key:match("-(.+)$") or GetRealmName()
    check(K(short, realm) == key, how .. ": splitting " .. key .. " on its first hyphen and rejoining gives it back")
  end
  check(K("Ana Maria") ~= K("Ana Clara") and K("Anne-Marie") ~= K("Anne-Claire"),
        how .. ": names that share a first part stay apart")
  local back = assert(loadstring("return { [" .. string.format("%q", K("First Last")) .. "] = true }"))()
  check(back[K("First Last")] == true and next(back) == "First Last", how .. ": the key survives a SavedVariables write and read")
  ROSTER = { "Bob", "First Last" }
  local rec = BRutus:GetMemberRecord("First Last")
  check(rec and rec.key == "First Last" and rec.name == "First Last",
        how .. ": the member record for a two-part name resolves, keyed by the name")
end)
for _, pair in ipairs({ { nil, "" }, { "", nil } }) do
  REALM, NORM = pair[1], pair[2]
  check(K("Ana") == "Ana", "GetRealmName() " .. tostring(pair[1]) .. " and GetNormalizedRealmName() "
        .. tostring(pair[2]) .. ": the name alone")
end
REALM, NORM = "Firemaw", nil

-- ── 4. Addon messages: mine skipped, everybody else's read and stored ───
local decoded = 0
LibStub("LibDeflate").DecodeForWoWAddonChannel = function() decoded = decoded + 1; return nil end
local CS = BRutus.CommSystem
CS.pendingMessages = CS.pendingMessages or {}
local function reads(sender)
  local before = decoded
  CS:OnMessageReceived("S:x", "GUILD", sender)
  return decoded > before
end
local payloads, stored = {}, {}
LibStub("LibSerialize").Deserialize = function(_, s) return true, payloads[s] end
local dataCollector = BRutus.DataCollector
BRutus.DataCollector = { StoreReceivedData = function(_, key) stored[#stored + 1] = key end }
local function received(sender, data)
  payloads.x = data
  CS:HandleBroadcast(sender, "x")
  return stored[#stored]
end
realmless(function(how)
  check(not reads("Ana"), how .. ": my own message is skipped")
  check(reads("Bob") and reads("First Last"), how .. ": everybody else's is read, where it used to raise")
  check(received("First Last", { name = "First Last" }) == "First Last", how .. ": a broadcast from a two-part name is stored under the rule's key")
  check(received("First Last", {}) == "First Last", how .. ": with no name in the payload, the sender's whole name is kept")
  check(received("First Last-Suffix", { name = "First Last" }) == "First Last-Suffix"
        and received("Bob-Suffix", { name = "Bob", realm = "" }) == "Bob-Suffix",
        how .. ": with no realm in the payload, a suffixed sender keeps its suffix, as the roster lists it")
  check(received("Bob", { name = "Bob", realm = "" }) == "Bob", how .. ": an empty realm and no suffix give the name alone")
end)
check(not reads("Ana") and not reads("Ana-Firemaw"), "Anniversary: my own message is skipped, with or without the realm")
check(reads("Ana-Spineshatter") and reads("Bob-Firemaw"), "Anniversary: a namesake from another realm, and everybody else, is read")
check(received("Bob-Firemaw", { name = "Bob", realm = "Firemaw" }) == "Bob-Firemaw" and received("Bob", { name = "Bob" }) == "Bob-Firemaw"
      and received("Cross-Spineshatter", { name = "Cross", realm = "Spineshatter" }) == "Cross-Spineshatter",
      "Anniversary: a broadcast keeps its key, from the payload's realm or the client's")
check(received("Cross-Spineshatter", { name = "Cross" }) == "Cross-Firemaw",
      "Anniversary: a payload with no realm takes the client's, as 0.53.0 did, whatever the sender's suffix")
REALM, NORM = "Living Flame", "LivingFlame"
check(received("Bob-LivingFlame", { name = "Bob" }) == "Bob-Living Flame"
      and received("Bob-LivingFlame", { name = "Bob", realm = "Living Flame" }) == "Bob-Living Flame",
      "Anniversary: a sender suffixed with the normalized realm keys by the client's realm, as 0.53.0 did")
REALM, NORM = "Firemaw", nil
BRutus.DataCollector = dataCollector

-- ── 5. Raid attendance ──────────────────────────────────────────────────
local RT = BRutus.RaidTracker
RT.CheckPlayerConsumes = function() return true end
local function snapshot()
  RT.currentRaid = { players = {}, snapshots = {} }
  RT:TakeSnapshot("test")
  return sortedKeys(RT.currentRaid.players), sortedKeys(RT.currentRaid.snapshots[1].members)
end
GROUP = { { "Bob" }, { "First Last", "" }, { "Cross", "Spineshatter" } }
realmless(function(how)
  local players, members = snapshot()
  check(players == "Ana,Bob,Cross-Spineshatter,First Last" and members == players,
        how .. ": the session and its snapshot key the group and me by the rule: " .. players)
end)
local players, members = snapshot()
check(players == "Ana-Firemaw,Bob-Firemaw,Cross-Spineshatter,First Last-Firemaw" and members == players,
      "Anniversary: the session and snapshot keys are unchanged: " .. players)

-- ── 6. Consumable check ─────────────────────────────────────────────────
local CC = BRutus.ConsumableChecker
check(CC ~= nil, "the consumable check loads on Anniversary")
realmless(function(how)
  check(sortedKeys(CC:CheckRaid()) == "Bob,Cross-Spineshatter,First Last", how .. ": results are keyed by the rule")
end)
check(sortedKeys(CC:CheckRaid()) == "Bob-Firemaw,Cross-Spineshatter,First Last-Firemaw",
      "Anniversary: consumable results keep their keys")

-- ── 7. Loot: context, a peer's award, my own award, a roll ──────────────
local LM = BRutus.LootMaster
local attKeys, awards, charged = {}, {}, {}
RT.GetAttendance25ManPercent = function(_, key) attKeys[#attKeys + 1] = key; return 80 end
BRutus.LootTracker = {
  RecordMLAward = function(_, e) awards[#awards + 1] = e.playerKey end,
  GetHistory = function() return {} end,
}
BRutus.IsOfficerByName = function() return true end
BRutus.IsOfficer = function() return true end
BRutus.GetLootSystem = function() return "dkp" end
BRutus.Points = {
  GetDB = function() return { config = { itemCost = 5 } } end,
  Charge = function(_, key) charged[#charged + 1] = key end,
  Get = function() return 0 end,
}
LM.QueueForTrade = function() end
LM.testMode = true

local function context(name, historyKey)
  RT.currentRaid = nil
  BRutus.db.lootHistory = { { fromML = true, playerKey = historyKey, timestamp = NOW - 60 } }
  return LM:GetPlayerContext(name).recvThisLockout, attKeys[#attKeys]
end
local function peerAward(awardedTo)
  LM:OnAddonMessage("BRutusLM", "AWARD|" .. awardedTo .. "|30107|4|Serpentshrine Cavern|" .. LINK, "RAID", "Offi-Firemaw")
  return awards[#awards]
end
local function myAward(playerName)
  LM.activeLoot = { link = LINK, itemId = 30107 }
  LM:AwardLoot(playerName, true)
  return awards[#awards], charged[#charged]
end
local function rollKey(name)
  LM.activeLoot, LM.rolls = { link = LINK }, {}
  LM:RegisterRoll(name, "OS", 42)
  return sortedKeys(LM.rolls)
end
realmless(function(how)
  local got, att = context("First Last", "First Last")
  check(got == 1 and att == "First Last", how .. ": attendance and this lockout's loot are looked up under the rule's key")
  check(peerAward("First Last") == "First Last", how .. ": an officer's award from another client is recorded under it")
  local award, charge = myAward("First Last")
  check(award == "First Last" and charge == "First Last", how .. ": my own award and its DKP charge use it too")
  check(rollKey("First Last") == "First Last", how .. ": a /roll is filed under the rule's key")
end)
local got, att = context("First Last", "First Last-Firemaw")
check(got == 1 and att == "First Last-Firemaw", "Anniversary: loot context keys are unchanged")
check(peerAward("First Last") == "First Last-Firemaw", "Anniversary: a peer's award keeps its key")
local award, charge = myAward("First Last")
check(award == "First Last-Firemaw" and charge == "First Last-Firemaw", "Anniversary: my award and DKP charge keep their key")
check(rollKey("First Last") == "First Last-Firemaw", "Anniversary: a /roll keeps its key")

-- ── 8. Wishlist ─────────────────────────────────────────────────────────
local WL = BRutus.Wishlist
local function wishlistKey()
  BRutus.db.wishlists = {}
  WL:GetMyList()
  return sortedKeys(BRutus.db.wishlists)
end
local function migratedKey()
  BRutus.db.wishlists, BRutus.db.myWishlist = {}, { { itemId = 30107 } }
  WL:Initialize()
  return sortedKeys(BRutus.db.wishlists)
end
local function delivered(historyKey)
  BRutus.db.lootHistory = { { fromML = true, playerKey = historyKey, itemId = 30107 } }
  return WL:IsItemDelivered(30107)
end
realmless(function(how)
  check(wishlistKey() == "Ana", how .. ": my wishlist is stored under the rule's key, not Ana-Unknown")
  check(migratedKey() == "Ana", how .. ": the one-time migration moves the old flat list under that same key")
  check(delivered("Ana") and not delivered("Ana-"),
        how .. ": an item awarded under that key counts as delivered, so the wishlist and loot agree")
end)
check(wishlistKey() == "Ana-Firemaw" and migratedKey() == "Ana-Firemaw" and delivered("Ana-Firemaw"),
      "Anniversary: the wishlist and its migration keep their key")

-- ── 9. Slash commands ───────────────────────────────────────────────────
local trials, notes = {}, {}
BRutus.TrialTracker = { AddTrial = function(_, key) trials[#trials + 1] = key end }
BRutus.OfficerNotes = { AddNote = function(_, key) notes[#notes + 1] = key; return true end }
local slash = SlashCmdList.GUILDOS
realmless(function(how)
  slash("trial Bob")
  slash("note Bob steady tank")
  check(trials[#trials] == "Bob" and notes[#notes] == "Bob", how .. ": /gos trial and /gos note key the member by the rule")
end)
slash("trial Bob")
slash("note Bob steady tank")
check(trials[#trials] == "Bob-Firemaw" and notes[#notes] == "Bob-Firemaw", "Anniversary: /gos trial and /gos note keep their keys")

-- ── 10. Pug inspector ───────────────────────────────────────────────────
local PI = BRutus.PugInspector
local noteKeys = {}
local function classify(name, realm, altLinks)
  local c = PI:Classify(name, {
    realm = realm, guildShort = { main = true }, altLinks = altLinks,
    noteFor = function(_, _, key) noteKeys[#noteKeys + 1] = key end,
  })
  return c.tag, noteKeys[#noteKeys]
end
local tag, noteKey = classify("First Last", "", { ["First Last"] = "Main" })
check(tag == string.format(BRutus.L["Alt of %s (guild)"], "Main") and noteKey == "First Last",
      "realm-less: a pug's alt link and notes are found under the rule's key, not First Last-")
tag, noteKey = classify("Bob", "Firemaw", { ["Bob-Firemaw"] = "Main-Firemaw" })
check(tag == string.format(BRutus.L["Alt of %s (guild)"], "Main") and noteKey == "Bob-Firemaw",
      "Anniversary: a pug's alt link and notes keep their keys")
realmless(function(how)
  check(PI:_LiveSources().realm == "", how .. ": the live classifier gets no realm, so its keys are the name alone")
end)
REALM, NORM = nil, "Suffix"
check(PI:_LiveSources().realm == "Suffix", "a client with only a normalized realm hands it to the live classifier")
REALM, NORM = "Firemaw", nil
check(PI:_LiveSources().realm == "Firemaw", "Anniversary: the live classifier's realm is the client's")

-- ── 11. Companion export ────────────────────────────────────────────────
local Companion = BRutus.Companion
realmless(function(how)
  ROSTER = { "First Last", "Bob" }
  BRutus.db.members = { ["First Last"] = { race = "Human", lastUpdate = 1 } }
  local p = Companion:BuildPayload()
  check(p and p.guildKey == "Raid Guild" and p.exportedBy == "Ana" and p.realm == nil,
        how .. ": the export's guild key and author follow the rule, and it carries no realm")
  check(p.members[1].key == "First Last" and p.members[1].race == "Human" and p.members[2].key == "Bob",
        how .. ": every roster member is keyed by the rule, and a published record is found under it")
end)
ROSTER = { "First Last-Firemaw", "Bob-Spineshatter" }
BRutus.db.members = { ["First Last-Firemaw"] = { race = "Human", lastUpdate = 1 } }
local p = Companion:BuildPayload()
check(p.guildKey == "Raid Guild-Firemaw" and p.exportedBy == "Ana-Firemaw" and p.realm == "Firemaw",
      "Anniversary: the export's guild key, author and realm are unchanged")
check(p.members[1].key == "First Last-Firemaw" and p.members[1].race == "Human" and p.members[2].key == "Bob-Spineshatter",
      "Anniversary: member keys in the export are unchanged")

-- ── 12. A roster that suffixes names on a client with only a normalized realm ──
for _, name in ipairs({ false, "" }) do
  REALM, NORM = name or nil, "Suffix"
  local how = "GetRealmName() " .. (name and '""' or "nil") .. ", GetNormalizedRealmName() \"Suffix\""
  check(K("Ana") == "Ana-Suffix", how .. ": the normalized realm fills the key, as the roster suffixes it")
  ROSTER = { "Ana-Suffix", "Bob-Suffix", "First Last-Suffix" }
  check(not reads("Ana-Suffix") and reads("Bob-Suffix"), how .. ": my own suffixed message is skipped, others read")
  check(BRutus:GetMemberRecord("First Last").key == "First Last-Suffix", how .. ": a two-part member resolves under the roster's key")
  BRutus.DataCollector = { StoreReceivedData = function(_, key) stored[#stored + 1] = key end }
  check(received("Bob-Suffix", { name = "Bob" }) == "Bob-Suffix", how .. ": a broadcast lands under the roster's key")
  BRutus.DataCollector = dataCollector
  BRutus.db.members = { ["Bob-Suffix"] = { race = "Orc", lastUpdate = 1 } }
  local ps = Companion:BuildPayload()
  check(ps.exportedBy == "Ana-Suffix" and ps.guildKey == "Raid Guild-Suffix" and ps.realm == "Suffix"
        and ps.members[2].key == "Bob-Suffix" and ps.members[2].race == "Orc",
        how .. ": the export's author, guild key, realm and rows agree with the roster")
end
REALM, NORM = "Firemaw", nil

-- ── 13. Disclosed, not solved: a roster that suffixes names, a client with no realm at all ──
-- Spec §2.3 and ADR-0018. Roster rows and a suffixed sender's broadcast carry the suffix; every key
-- built from a bare name stays bare. Pinned so the disclosure stays true until the beta shows
-- whether this state exists.
realmless(function(how)
  ROSTER = { "Ana-Suffix", "Bob-Suffix" }
  check(K("Ana") == "Ana" and reads("Ana-Suffix"), how .. ": my own key is bare, and my suffixed message is not recognised as mine")
  BRutus.DataCollector = { StoreReceivedData = function(_, key) stored[#stored + 1] = key end }
  check(received("Bob-Suffix", { name = "Bob" }) == "Bob-Suffix", how .. ": a suffixed sender's broadcast keeps the suffix")
  BRutus.DataCollector = dataCollector
  BRutus.db.members = {}
  local ps = Companion:BuildPayload()
  check(ps.members[2].key == "Bob-Suffix" and ps.exportedBy == "Ana", how .. ": the export's rows carry the suffix, its author does not")
  check(peerAward("Bob") == "Bob" and rollKey("Bob") == "Bob", how .. ": loot keys stay bare")
  slash("trial Bob")
  check(trials[#trials] == "Bob" and BRutus:GetMemberRecord("Bob-Suffix").key == "Bob",
        how .. ": /gos trial and the member record stay bare")
end)

-- ── 14. No member key is built by hand any more ─────────────────────────
-- Every Lua file the TOC loads, outside Libs. The joins that remain are not member keys,
-- or only join when a realm is there.
local ALLOWED = {
  ["Core/Utils.lua"] = 1,              -- the rule itself
  ["Core/Core.lua"] = 1,               -- the per-guild database key, not a member's
  ["Modules/Alliance.lua"] = 1,        -- a pair of guild ids
  ["Modules/GuildAnalytics.lua"] = 1,  -- a level bracket, "60-69"
  ["Modules/NoteCommand.lua"] = 1,     -- only when the author has a realm
  ["Modules/PugInspector.lua"] = 1,    -- only when there is a realm
}
local toc = assert(io.open(ADDON .. "/GuildOS.toc", "rb")):read("*a")
local scanned = 0
for line in toc:gmatch("[^\r\n]+") do
  local rel = line:match("^%s*([^#]%S*%.lua)%s*$")
  if rel and not rel:find("^Libs") then
    rel = rel:gsub("\\", "/")
    local fh = io.open(ADDON .. "/" .. rel, "rb")
    check(fh ~= nil, rel .. " is in the TOC and on disk")
    local src = fh:read("*a")
    fh:close()
    scanned = scanned + 1
    local _, joins = src:gsub('%.%.%s*["\']%-["\']%s*%.%.', "")
    local _, formats = src:gsub('["\']%%s%-%%s["\']', "")
    check(joins == (ALLOWED[rel] or 0) and formats == 0, rel .. " builds " .. joins .. " hyphen join(s) and " .. formats
          .. ' "%s-%s" format(s) by hand; expected ' .. (ALLOWED[rel] or 0) .. " and 0")
    local _, fallbacks = src:gsub('GetRealmName%(%)%s*%)?%s*or%s*["\']', "")
    local _, normalizedFallbacks = src:gsub('GetNormalizedRealmName%(%)%s*%)?%s*or%s*["\']', "")
    local _, clientFallbacks = src:gsub('GetClientRealm%(%)%s*%)?%s*or%s*["\']', "")
    check(fallbacks == (rel == "Core/Core.lua" and 1 or 0) and normalizedFallbacks == 0
          and clientFallbacks == (rel == "Modules/PugInspector.lua" and 1 or 0),
          rel .. " falls back from the client's realm to a literal")
  end
end
check(scanned > 50, "the scan read the addon's files (" .. scanned .. ")")

print("member-keys: " .. checks .. " checks passed")
