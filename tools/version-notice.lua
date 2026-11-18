-- A newer Guild OS in the guild, and the message of the day on WoW: Forever (#377), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/Mesh.lua, Modules/DataCollector.lua,
-- Modules/CommSystem.lua and Modules/GuildManager.lua.
--
-- Every member's broadcast carries its addon version. The newest one above this client's is said in chat,
-- a few seconds after the first so a login's wave says only its newest, and again only for a newer one
-- still; nothing else says anything. On WoW: Forever an addon's GuildSetMOTD is forbidden (seen in
-- game), so saving the message of the day opens the game's guild panel instead.
--
--   luajit -e 'ADDON="."' tools/version-notice.lua
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

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
local interface = 16001   -- WoW: Forever
function GetBuildInfo() return "1.60.1", "70205", "", interface end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Bishop", "Who" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Realm" end
local due = {}
C_Timer = { After = function(_, fn) due[#due + 1] = fn end, NewTicker = function() end }
local function wait()   -- NOTICE_WAIT passes
  local now = due; due = {}
  for _, fn in ipairs(now) do fn() end
end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function IsInGuild() return true end
local ROSTER = { { "Bishop Who", 0 }, { "Random Member", 5 } }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2] end end
function GetGuildInfo() return "Guild", "Guild Master", 0 end
function time() return 1000 end
function GetServerTime() return 1000 end
function UnitName() return "Bishop" end
strsplit = function(sep, s)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
  return unpack(out)
end

local payloads = {}
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) return payloads[s] ~= nil, payloads[s] end

local function load(version, iface)
  interface = iface or 16001
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = version }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/Mesh.lua")
  dofile(ADDON .. "/Modules/DataCollector.lua")
  dofile(ADDON .. "/Modules/CommSystem.lua")
  dofile(ADDON .. "/Modules/GuildManager.lua")
  GuildOS.db = { members = {}, settings = {}, guildLog = {} }
  GuildOS.CommSystem._CountPayload = function() end
  for i = #printed, 1, -1 do printed[i] = nil end
  due = {}
  return GuildOS.CommSystem
end

local n = 0
local function broadcast(CS, ver, channel)
  n = n + 1
  local key = "p" .. n
  payloads[key] = { name = "Random", class = "MAGE", lastUpdate = n, addonVersion = ver }
  CS:HandleBroadcast("Random Member", key, channel or "GUILD")
end
local function said(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return true end end
  return false
end

-- ── 1. The newest version in the guild ──────────────────────────────────
-- A login's wave: a friend on 1.30.0 first, then one on 1.31.0, then one on 1.30.5. One line, the newest.
local CS = load("1.29.0")
broadcast(CS, "1.30.0")
check(#printed == 0, "the first newer version waits for the rest of the wave")
broadcast(CS, "1.31.0")
broadcast(CS, "1.30.5")
wait()
check(#printed == 1 and said("1.31.0") and said("1.29.0") and said("CurseForge") and not said("1.30"),
  "the wave says one line: the newest, this client's version and where to update")
check(GuildOS.db.members["Random Member"] or next(GuildOS.db.members), "the broadcast is still stored")
-- Later in the session: one newer than this client's but older than the newest said says nothing; a newer
-- one still says it once more.
broadcast(CS, "1.30.9"); broadcast(CS, "1.31.0"); wait()
check(#printed == 1, "a version not above the one already said says nothing")
broadcast(CS, "1.32.0"); wait()
check(#printed == 2 and printed[2]:find("1.32.0", 1, true), "a newer one later is said once more")

-- The compare is numeric, not text: 1.29.10 is newer than 1.29.9, 1.100.0 than 1.29.0.
CS = load("1.29.9"); broadcast(CS, "1.29.10"); wait()
check(#printed == 1, "1.29.10 is newer than 1.29.9")
CS = load("1.29.0"); broadcast(CS, "1.100.0"); broadcast(CS, "1.99.0"); wait()
check(#printed == 1 and said("1.100.0"), "1.100.0 is newer than 1.29.0 and than 1.99.0")

-- ── 2. What says nothing ────────────────────────────────────────────────
CS = load("1.29.0")
for _, v in ipairs({ "1.29.0", "1.28.5", "0.99.0", "1.30.0-beta1", "nan", "1.30", "v1.30.0", "", "1.30.0.1" }) do
  broadcast(CS, v)
end
broadcast(CS, nil)
broadcast(CS, { "1.30.0" })
broadcast(CS, 130)
wait()
check(#printed == 0, "the same, an older, a beta, a malformed or a missing version says nothing")
broadcast(CS, "1.30.0", "WHISPER"); wait()
check(#printed == 0, "a newer version whispered says nothing: a whisper can come from anyone")
broadcast(CS, "1.30.0"); wait()
check(#printed == 1, "and the guild's next newer one still does")

-- One guildmate stepping 1.29.1, 1.29.2, ... all session earns NOTICE_MAX lines, not one every 10s; and a
-- part longer than three digits is no version at all.
CS = load("1.29.0")
for i = 1, 20 do broadcast(CS, "1.29." .. i); wait() end
check(#printed == CS.NOTICE_MAX and CS.NOTICE_MAX == 3, "a guildmate stepping the version earns three lines a session ("
  .. #printed .. ")")
CS = load("1.29.0")
broadcast(CS, "1.29." .. string.rep("9", 400)); broadcast(CS, "1234.0.0"); wait()
check(#printed == 0, "a version with a part longer than three digits says nothing")

CS = load("test")   -- a dev build's version
broadcast(CS, "9.9.9"); wait()
check(#printed == 0, "a client whose own version is no x.y.z says nothing")

-- ── 3. The message of the day on WoW: Forever ───────────────────────────
local motdSet, nativeOpened = nil, 0
function GuildSetMOTD(text) motdSet = text end
function CanEditMOTD() return true end

load("1.29.0", 16001)
GuildOS.OpenBlizzardGuildUI = function() nativeOpened = nativeOpened + 1 end
local GM = GuildOS.GuildManager
check(GM:MOTDNeedsGamePanel(), "on WoW: Forever the message of the day needs the game's panel")
check(GM:SetMOTD("Raid at 8") == false and motdSet == nil and nativeOpened == 1,
  "saving it calls no GuildSetMOTD and opens the game's guild panel")
check(said("On WoW: Forever only the game's guild panel can change the message of the day."), "and says why")

WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
load("1.29.0", 20505)
GuildOS.OpenBlizzardGuildUI = function() nativeOpened = nativeOpened + 1 end
GM = GuildOS.GuildManager
check(not GM:MOTDNeedsGamePanel() and GM:SetMOTD("Raid at 8") == true and motdSet == "Raid at 8" and nativeOpened == 1,
  "on TBC Anniversary it is still saved from the addon")

print("version-notice: " .. checks .. " checks passed")
