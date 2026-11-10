-- Who may send what (issue #78), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/CommSystem.lua and Modules/RecruitmentSystem.lua.
--
-- Officer-authored messages were believed from anybody who could reach the addon prefix: a
-- welcome claim or intent (suppress a new member's welcome, win the tie-break), the loot
-- priorities (overwrite every member's), and the officer notes, trials and raid data (the
-- receiver checked it was an officer, never that the sender was). Every legitimate sender of
-- these is an officer already, over GUILD, so the receiver now asks for both: an officer, as RX
-- and AL always did, and the GUILD channel, since IsOfficerByName drops the realm.
--
--   luajit -e 'ADDON="."' tools/comm-trust.lua
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
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Bishop", "Who" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Realm" end
C_Timer = { After = function() end, NewTicker = function() end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}

-- The guild: one officer, one member. This client is an officer too, so the receiver-side
-- checks pass and only the sender decides.
local OFFICER, MEMBER = "Preaseance Rezplease", "Random Member"
local ROSTER = { { OFFICER, 0 }, { MEMBER, 5 }, { "Bishop Who", 1 }, { "Preaseance Other", 5 } }
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1], "Rank", r[2] end
end
function GetGuildInfo() return "Guild", "Officer", 1 end

local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
local CS, R = GuildOS.CommSystem, GuildOS.Recruitment
CS.pendingMessages = CS.pendingMessages or {}
check(GuildOS:IsOfficer() and GuildOS:IsOfficerByName(OFFICER) and not GuildOS:IsOfficerByName(MEMBER),
  "the stub guild has one officer sender, one member sender, and this client is an officer")

-- The officer modules are spies: the question is only whether CommSystem hands them the message.
local got = {}
local function spy(name) return function(...) got[name] = (got[name] or 0) + 1 end end
GuildOS.Wishlist     = { HandleLootPriosBroadcast = spy("LP") }
GuildOS.OfficerNotes = { HandleIncoming = spy("ON"), HandleAllIncoming = spy("OA") }
GuildOS.TrialTracker = { HandleIncoming = spy("TR") }
GuildOS.RaidTracker  = { HandleIncoming = spy("RD") }

local function receive(msgType, data, sender, channel)
  CS:OnMessageReceived("S:" .. msgType .. ":" .. data, channel or "GUILD", sender)
end

-- ── 1. The officer modules' messages ────────────────────────────────────
for _, t in ipairs({ "LP", "ON", "OA", "TR", "RD" }) do
  got[t] = nil
  receive(t, "payload", MEMBER)
  check(got[t] == nil, t .. " from a member is dropped")
  receive(t, "payload", OFFICER)
  check(got[t] == 1, t .. " from an officer is handled")
end

-- Over any other channel, even from an officer's name: IsOfficerByName drops the realm, so a
-- namesake elsewhere could otherwise whisper, or speak in a battleground, as the officer.
for _, t in ipairs({ "LP", "ON", "OA", "TR", "RD" }) do
  got[t] = nil
  receive(t, "payload", OFFICER, "WHISPER")
  receive(t, "payload", OFFICER, "INSTANCE_CHAT")
  receive(t, "payload", OFFICER .. "-OtherRealm", "WHISPER")
  check(got[t] == nil, t .. " from an officer's name outside GUILD is dropped")
end

-- The shapes a name arrives in: with the realm, and a member sharing the officer's first name.
got.LP = nil
receive("LP", "payload", OFFICER .. "-Realm")
check(got.LP == 1, "an officer's name with the realm attached still counts")
receive("LP", "payload", "Preaseance Other")
check(got.LP == 1, "a member who shares only the officer's first name does not")

-- ── 2. The welcome race ─────────────────────────────────────────────────
receive("WC", "New Guy", MEMBER)
check(not (R._welcomedRecently and R._welcomedRecently["New Guy"]), "a claim from a member suppresses nobody's welcome")
receive("WI", "New Guy", MEMBER)
check(not (R._welcomeIntents and R._welcomeIntents["New Guy"]), "an intent from a member takes no part in the tie-break")
receive("WC", "New Guy", OFFICER, "WHISPER")
receive("WI", "New Guy", OFFICER, "WHISPER")
receive("WC", "New Guy", OFFICER, "INSTANCE_CHAT")
receive("WI", "New Guy", OFFICER, "INSTANCE_CHAT")
check(not (R._welcomedRecently and R._welcomedRecently["New Guy"]) and not (R._welcomeIntents and R._welcomeIntents["New Guy"]),
  "an officer's name over a whisper or a battleground is not the guild's welcome race either")
receive("WI", "New Guy", OFFICER)
receive("WC", "New Guy", OFFICER)
check(R._welcomeIntents["New Guy"][OFFICER] and R._welcomedRecently["New Guy"] and R._welcomedRecently["New Guy_sent"],
  "an officer's intent and claim over GUILD are recorded")

-- ── 3. A sole officer's sync (issue #312) ───────────────────────────────
-- The guild master is the only officer and a member broadcasts over GUILD: the member's data is
-- stored, the member reads as having the addon, and the Now tab has a last sync. Being the only
-- officer was never the cause of "sync does nothing"; the drops on the way were silent.
dofile(ADDON .. "/Modules/DataCollector.lua")
GuildOS.UI = { IsFeatureAllowed = function() return true end, GetFeature = function(_, id) return id end }
GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
dofile(ADDON .. "/UI/Agora.lua")
local A = GuildOS.UI.Agora
for i = #ROSTER, 1, -1 do ROSTER[i] = nil end
ROSTER[1], ROSTER[2] = { "Bishop Who", 0 }, { MEMBER, 5 }
function GetGuildInfo() return "Guild", "Guild Master", 0 end
GuildOS.TrialTracker = nil
GuildOS.db = GuildOS.db or {}
GuildOS.db.members, GuildOS.db.settings = {}, GuildOS.db.settings or {}
check(GuildOS:IsOfficer() and not GuildOS:IsOfficerByName(MEMBER), "this client is the guild's only officer")

local payloads = {}
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s)
  if payloads[s] then return true, payloads[s] end
  return false
end
local deflate = LibStub("LibDeflate")
deflate.DecodeForWoWAddonChannel = function(_, s) if s:find("^CORRUPT") then return nil end return s end
local timers = {}
C_Timer.After = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local function printedHas(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return true end end
  return false
end
local function runTimers(delay)
  local due = {}
  for i = #timers, 1, -1 do if timers[i].d == delay then due[#due + 1] = table.remove(timers, i) end end
  for _, t in ipairs(due) do t.fn() end
end

time = function() return 1790000000 end
function GetServerTime() return 1790000000 end
-- What FullSync sends is not the question here; what it reports is.
CS.BroadcastMyData, CS.RequestAllData = function() end, function() end
check(A:LastSync() == nil, "before any broadcast there is no last sync")
CS:FullSync()
check(printedHas("Syncing all guild data (officer mode)..."), "the officer's sync says it started")
payloads.member = { name = "Random", class = "PRIEST", level = 60, lastUpdate = 100 }
receive("BC", "member", MEMBER, "GUILD")
local mkey = GuildOS:GetPlayerKey("Random Member", "Realm")
check(GuildOS.db.members[mkey] and (GuildOS.db.members[mkey].lastSync or 0) > 0,
  "the member's broadcast over GUILD is stored with a sync time")
local rows, withAddon = CS:GetSyncHealth()
local memberRow
for _, r in ipairs(rows) do if r.name == "Random Member" then memberRow = r end end
check(memberRow and memberRow.hasAddon and withAddon == 1, "and the member reads as having the addon")
check(A:LastSync() ~= nil, "and the Now tab has a last sync")

local n = CS:SyncCounters()
check(n.received == 1 and n.stored == 1 and n.dropped == 0, "the broadcast is counted received and stored")

-- Dropped on the way: each counted under its reason, not silent.
CS:OnMessageReceived("S:CORRUPT", "GUILD", MEMBER)
n = CS:SyncCounters()
check(n.received == 2 and n.dropped == 1 and n.topReason == "decode" and n.senders[MEMBER].reasons.decode == 1,
  "a corrupted message counts as a drop, decode, under its sender")
payloads.noclass = { name = "Random" }
receive("BC", "noclass", MEMBER, "GUILD")
payloads.older = { name = "Random", class = "PRIEST", lastUpdate = 50 }
receive("BC", "older", MEMBER, "GUILD")
n = CS:SyncCounters()
check(n.dropped == 3 and n.senders[MEMBER].reasons.rejected == 1 and n.senders[MEMBER].reasons.stale == 1,
  "a payload missing its class is rejected, an older one stale")
CS:OnMessageReceived("M:1A:1:2:half", "GUILD", MEMBER)
runTimers(30)
n = CS:SyncCounters()
check(n.senders[MEMBER].reasons.chunks == 1 and CS.pendingMessages[MEMBER .. ":1A"] == nil,
  "a message still missing a chunk after 30 s counts as chunks lost")
CS:OnMessageReceived("M:1B:1:2:S", "GUILD", MEMBER)
CS:OnMessageReceived("M:1B:2:2:A:x", "GUILD", MEMBER)
runTimers(30)
check(CS:SyncCounters().senders[MEMBER].reasons.chunks == 1, "a message whose chunks all came is not a loss")

-- Ten seconds after the sync, one line says what came in.
runTimers(10)
check(printedHas("Sync: data from 1 member(s) arrived; 1 member(s) have Guild OS."), "the sync reports what arrived")
check(not printedHas("No member data arrived."), "with data in, no hint")
printed = {}
CS:FullSync()
runTimers(10)
check(printedHas("Sync: data from 0 member(s) arrived; 1 member(s) have Guild OS.")
  and printedHas("/guildos errors"), "a sync nothing answered says so, and points at /guildos errors")

-- Bounded: past MAX_STAT_SENDERS only the totals grow.
for i = 1, CS.MAX_STAT_SENDERS + 20 do CS:OnMessageReceived("S:CORRUPT", "GUILD", "Spam" .. i) end
local senders = 0
for _ in pairs(CS:SyncCounters().senders) do senders = senders + 1 end
check(senders <= CS.MAX_STAT_SENDERS, "the per-sender table stays bounded")

print(("comm-trust: %d checks passed"):format(checks))
