-- The welcome claim on a client that is not an officer (issue #77), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua and
-- Modules/RecruitmentSystem.lua.
--
-- Recruitment:Initialize, which creates the welcome tables, runs for officers only and five
-- seconds after login. The claim an officer sends after a welcome reaches every client in the
-- guild, and CommSystem wrote into a table a member never had: a Lua error on every member
-- running Guild OS, each time an officer welcomed somebody.
--
--   luajit -e 'ADDON="."' tools/welcome-claim.lua
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
-- The sender is an officer of this guild: since issue #78 nobody else's claim counts.
function IsInGuild() return true end
-- Two more officers for the race between officers (issue #128), one sorting before this client's
-- "Bishop Who" and one after.
local ROSTER = { { "Preaseance Rezplease", 0 }, { "Ana Lima-Realm", 1 }, { "Zeca Rocha-Realm", 1 }, { "Bishop-Realm", 1 } }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) if ROSTER[i] then return ROSTER[i][1], "Officer", ROSTER[i][2] end end
function GetGuildInfo() return "Guild", "Officer", 1 end

-- The wire: what the officer's client compressed and encoded, the stubs hand back as is.
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

-- A member: Recruitment was never initialized, the way OFFICER_START leaves it.
check(R._welcomedRecently == nil, "a member's client never had the welcome table, as in game")
local ok, err = pcall(CS.OnMessageReceived, CS, "S:WC:Ragged Angel", "GUILD", "Preaseance Rezplease")
check(ok, "a member receiving an officer's welcome claim does not raise (" .. tostring(err) .. ")")
check(R._welcomedRecently and R._welcomedRecently["Ragged Angel"] and R._welcomedRecently["Ragged Angel_sent"],
  "and the claim is recorded, so this client would stand down too")

-- The intent next to it already coped; it still does.
ok, err = pcall(CS.OnMessageReceived, CS, "S:WI:Ragged Angel", "GUILD", "Preaseance Rezplease")
check(ok, "a member receiving a welcome intent does not raise (" .. tostring(err) .. ")")
check(R._welcomeIntents["Ragged Angel"]["Preaseance Rezplease"], "and the intent is recorded")

-- An officer's claim table, once it exists, keeps what it had.
R._welcomedRecently = { ["Old Name"] = true }
CS:OnMessageReceived("S:WC:New Name", "GUILD", "Preaseance Rezplease")
check(R._welcomedRecently["Old Name"] and R._welcomedRecently["New Name"], "a claim adds to the table, it does not replace it")

-- ── Two officers who each thought they won (issue #128) ─────────────────
-- The tie-break gives the officers 2 seconds to hear each other's intents, and an addon message
-- can take longer behind the guild's sync traffic: both queue the popup. On Forever it waits for a
-- click, so the claims they exchange settle it before anyone presses Send, the same on both sides.
R._welcomedRecently, R._welcomeIntents = {}, {}
local shown, hidden = 0, 0
R.ShowWelcomePopup = function(self)
  if #(self._pendingWelcomes or {}) == 0 then hidden = hidden + 1 else shown = shown + 1 end
end
local sent = {}
function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end
GuildOS.db = { recruitment = { welcomeMessage = "Bem-vindo!" } }
R:QueueWelcome("Xayide Kholin")
R:QueueWelcome("Ves Pin")
CS:OnMessageReceived("S:WC:Xayide Kholin", "GUILD", "Zeca Rocha-Realm")
check(#R._pendingWelcomes == 2, "a claim from an officer who sorts after this one leaves the popup: that one stands down")
CS:OnMessageReceived("S:WC:Xayide Kholin", "GUILD", "Ana Lima-Realm")
check(#R._pendingWelcomes == 1 and R._pendingWelcomes[1] == "Ves Pin" and shown == 3,
  "one from an officer who sorts before takes that member off the popup, and leaves the other")
CS:OnMessageReceived("S:WC:Ves Pin", "GUILD", "Ana Lima")
check(#R._pendingWelcomes == 0 and hidden == 1, "and with nobody left to welcome, the popup goes")
check(R:SendPendingWelcome() == false and #sent == 0, "so a click then sends nothing")
R:QueueWelcome("Bota Sagres")
CS:OnMessageReceived("S:WC:Bota Sagres", "WHISPER", "Ana Lima-Realm")
CS:OnMessageReceived("S:WC:Bota Sagres", "GUILD", "Intruso Qualquer-Realm")
check(#R._pendingWelcomes == 1, "a claim whispered, or from somebody who is not an officer, takes nothing away")
-- Names are compared without the realm, as the roster check reads them: "Bishop" sorts before
-- "Bishop Who", though "Bishop-Realm" would not.
CS:OnMessageReceived("S:WC:Bota Sagres", "GUILD", "Bishop-Realm")
check(#R._pendingWelcomes == 0, "the realm plays no part in who sorts first")

print(("welcome-claim: %d checks passed"):format(checks))
