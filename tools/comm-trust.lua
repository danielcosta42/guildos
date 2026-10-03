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
local CS, R = BRutus.CommSystem, BRutus.Recruitment
CS.pendingMessages = CS.pendingMessages or {}
check(BRutus:IsOfficer() and BRutus:IsOfficerByName(OFFICER) and not BRutus:IsOfficerByName(MEMBER),
  "the stub guild has one officer sender, one member sender, and this client is an officer")

-- The officer modules are spies: the question is only whether CommSystem hands them the message.
local got = {}
local function spy(name) return function(...) got[name] = (got[name] or 0) + 1 end end
BRutus.Wishlist     = { HandleLootPriosBroadcast = spy("LP") }
BRutus.OfficerNotes = { HandleIncoming = spy("ON"), HandleAllIncoming = spy("OA") }
BRutus.TrialTracker = { HandleIncoming = spy("TR") }
BRutus.RaidTracker  = { HandleIncoming = spy("RD") }

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

print(("comm-trust: %d checks passed"):format(checks))
