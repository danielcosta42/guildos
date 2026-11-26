-- Chat and addon senders on WoW: Forever (audit M1, N1, N2, N12), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/BanList.lua, Modules/RosterLog.lua, Modules/AltAutoDetect.lua and
-- Modules/RecruitEngagement.lua under a stubbed Forever client.
--
-- Forever's names carry a surname: the roster says "Chehul Costa", chat and addon senders "Chehul-Costa". Every
-- site that cut a sender at its first hyphen read "Chehul": a ban never alerted on a whisper, an officer's sync
-- was dropped, an alt self-claim refused and recruiting stats filed under the wrong key. GuildOS:SenderName,
-- ShortName and SenderKey turn a sender into the roster's name; on Anniversary and retail nothing changes.
--
--   luajit -e 'ADDON="."' tools/sender-names.lua
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
local handlers, printed = {}, {}
local roster = {}
local store, n = {}, 0

local function load(game)
  if game == "retail" then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
    C_PlayerInfo = nil
  elseif game == "anniversary" then
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_ID = 5
    C_PlayerInfo = nil
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }   -- what makes Compat know surnames
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  handlers = {}
  function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.SetScript = function(_, _, fn) handlers[#handlers + 1] = fn end
    return f
  end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return NOW end
  function GetTime() return NOW end
  time = function() return NOW end
  function date() return "2026-11-26" end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  function GetGuildInfo() return "Ordem", "Officer", 1, nil end
  function GetRealmName() return "Classic Beta PvE" end
  function GetNormalizedRealmName() return "ClassicBetaPvE" end
  function UnitName() return "Ana" end
  function UnitFullName() return "Ana", "Lima" end
  function GetNumGuildMembers() return #roster end
  function GetGuildRosterInfo(i) local r = roster[i]; if r then return r[1], "Rank", r[2] end end
  ERR_GUILD_JOIN_S = "%s has joined the guild."
  ERR_GUILD_LEAVE_S = "%s has left the guild."
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  local registry = {}
  LibStub = setmetatable({
    NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
    GetLibrary = function(_, k) return registry[k] end,
  }, { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
  LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
  LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, store[s] end return false end
  GameTooltip = { HasScript = function() return true end, HookScript = function() end }
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return true end
  function GuildOS:Print(m) printed[#printed + 1] = m end
  GuildOS.db = { settings = { modules = {}, officerMaxRank = 1 }, members = {}, banList = {}, rosterLog = { events = {} } }
  GuildOS.SyncService = { On = function() end, NextRevision = function() return 1 end, GetRevision = function() return 1 end,
    Publish = function() end, Send = function() end }
  dofile(ADDON .. "/Modules/BanList.lua")
  dofile(ADDON .. "/Modules/RosterLog.lua")
  dofile(ADDON .. "/Modules/AltAutoDetect.lua")
  dofile(ADDON .. "/Modules/RecruitEngagement.lua")
  GuildOS.BanList._Publish = function() end
  GuildOS.BanList.Refresh = function() end
  GuildOS.BanList:_SetupDetection()
end

-- ── WoW: Forever ───────────────────────────────────────────────────────
load("forever")
check(GuildOS.Client.has.surnames, "the stub is a surname client")
check(GuildOS:SenderName("Chehul-Costa") == "Chehul Costa", "a sender's hyphen is the surname's space")
check(GuildOS:SenderName("Chehul Costa") == "Chehul Costa", "the roster's spelling stays")
check(GuildOS:SenderName("Chehul Costa-Classic Beta PvE") == "Chehul Costa", "a realm after a whole name goes")
check(GuildOS:SenderName("Chehul-ClassicBetaPvE") == "Chehul", "a hyphen before this client's own realm is the realm's")
check(GuildOS:SenderName("Chehul-Costa-ClassicBetaPvE") == "Chehul Costa", "a realm after a hyphenated surname goes")
check(GuildOS:SenderName("Chehul") == "Chehul", "a name with no surname stays")
check(GuildOS:ShortName("Chehul-Costa") == "Chehul Costa", "ShortName keeps the whole name")
check(GuildOS:SenderKey("Chehul-Costa") == GuildOS:KeyOfRosterName("Chehul Costa"), "a sender keys as its roster line")

-- Bans: one filed by an officer typing the roster's name alerts on the whisper's "Chehul-Costa".
local BL = GuildOS.BanList
BL:Add("Chehul Costa", "scam")
check(GuildOS.db.banList["chehul costa"] ~= nil, "the ban is filed under the whole name")
check(BL:IsBanned("Chehul-Costa"), "a chat sender's spelling finds it")
check(not BL:IsBanned("Chehul-Lima"), "a namesake with another surname is not banned")
check(BL:_Who("Chehul-Costa") == "Chehul Costa", "_Who names the ban as the roster does")
printed = {}
for _, fn in ipairs(handlers) do local ok, e = pcall(fn, nil, "CHAT_MSG_WHISPER", "hi", "Chehul-Costa"); if not ok then print(e) end end
local alerted = false
for _, m in ipairs(printed) do if m:find("Chehul Costa", 1, true) then alerted = true end end
check(alerted, "a whisper from the banned player alerts the officer")

-- The roster log: an event about "Chehul-Costa" is about "Chehul Costa".
check(GuildOS.RosterLog:_NormShort("Chehul-Costa") == "Chehul Costa", "the roster log keeps the surname")

-- The officer check: an officer's sender "Ana-Lima" is the roster's "Ana Lima", not every Ana.
roster = { { "Ana Lima", 1 }, { "Ana Souza", 5 }, { "Bruno Reis", 6 } }
check(GuildOS:IsOfficerByName("Ana-Lima"), "an officer with a surname is an officer")
roster = { { "Ana Souza", 1 }, { "Ana Lima", 5 } }
check(not GuildOS:IsOfficerByName("Ana-Lima"), "a namesake officer does not make a member one")
check(GuildOS:HasRankUpToByName("Ana-Lima", 5), "HasRankUpToByName matches the whole name too")

-- An alt self-claim: the sender "Chehul-Costa" may unlink their own alt.
local MAIN = GuildOS:KeyOfRosterName("Chehul Costa")
local ALT = GuildOS:KeyOfRosterName("Chehul Druida")
GuildOS.AltSync = nil
GuildOS.db.altLinks = { [ALT] = MAIN }
GuildOS.AltAutoDetect:HandleSelfClaim("Chehul-Costa", LibStub("GuildOS-LibSerialize"):Serialize({ unlink = { ALT } }))
check(GuildOS.db.altLinks[ALT] == nil, "an alt self-claim from a surname sender is applied")

-- Recruiting stats: filed under the sender's roster key.
GuildOS.RecruitEngagement:HandleStats("Chehul-Costa", LibStub("GuildOS-LibSerialize"):Serialize({}), "GUILD")
check(GuildOS.db.recruitStats and GuildOS.db.recruitStats[MAIN] ~= nil, "recruiting stats are filed under the roster key")

-- ── Anniversary and retail: as before ──────────────────────────────────
load("anniversary")
check(GuildOS:SenderName("Thrall-Benediction") == "Thrall-Benediction", "Anniversary: a sender stays as given")
check(GuildOS:ShortName("Thrall-Benediction") == "Thrall", "Anniversary: the short name is before the hyphen")
check(GuildOS.RosterLog:_NormShort("Thrall-Benediction") == "Thrall", "Anniversary: the roster log as before")
check(BL ~= GuildOS.BanList and GuildOS.BanList:_NormalizeKey("Thrall-Benediction") == "thrall", "Anniversary: ban keys as before")
roster = { { "Thrall", 1 } }
check(GuildOS:IsOfficerByName("Thrall-Benediction"), "Anniversary: the officer check as before")
load("retail")
check(GuildOS:SenderName("Thrall-Benediction") == "Thrall-Benediction", "retail: a sender stays as given")
check(GuildOS:SenderKey("Thrall-Benediction") == "Thrall-Benediction", "retail: the key keeps the realm")

print(("sender-names: %d checks passed"):format(checks))
