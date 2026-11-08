-- The cuts of issue #285, run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/CommSystem.lua and Modules/ChatTweaks.lua.
--
-- /gos probe mem on a guild of fifty: every client asks for everybody's data every ten minutes and
-- every other client answered each ask with all it holds, so the guild's traffic grew with the square
-- of its size; GUILD_ROSTER_UPDATE came 34 times in two minutes and each one walked the whole roster
-- several times over; the chat tweaks' cache was rebuilt with the tweaks switched off.
--
--   luajit -e 'ADDON="."' tools/quiet-guild.lua
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

local timers, clock = {}, 1000
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(_, fn) self.fn = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.fn then f.fn(f, event, ...) end
  end
end
function hooksecurefunc() end
function GetTime() return clock end
function GetServerTime() return 1762600000 end
time = os.time
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Chehul", "Costa" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Realm" end
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end,
            NewTicker = function() end }
C_ChatInfo = { InChatMessagingLockdown = function() return false end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
local rosterReads = 0
function IsInGuild() return true end
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(i)
  rosterReads = rosterReads + 1
  if i == 1 then return "Chehul Costa", "Officer", 1, 60, "Druid", "", "", "", true, 0, "DRUID" end
  if i == 2 then return "Cherry Arrow", "Member", 5, 60, "Hunter", "", "", "", true, 0, "HUNTER" end
end
function GetGuildInfo() return "Guild", "Officer", 1 end

local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/ChatTweaks.lua")
GuildOS.db = { members = {}, chatTweaks = {} }
function GuildOS:IsOfficer() return false end
function GuildOS:IsFeatureEnabled() return false end

local function advance(untilT)
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > untilT then break end
    table.remove(timers, 1)
    clock = t.at
    t.fn()
  end
  clock = untilT
end

-- ── GuildOS:Throttle ───────────────────────────────────────────────────

local runs = 0
local function job() runs = runs + 1 end
GuildOS:Throttle("t", 15, job)
check(runs == 1, "the first call runs at once")
GuildOS:Throttle("t", 15, job)
GuildOS:Throttle("t", 15, job)
check(runs == 1, "calls inside the gap do not run at once")
advance(clock + 15)
check(runs == 2, "a burst inside the gap is one run, when the gap ends: the last call is never lost")
advance(clock + 60)
check(runs == 2, "nothing more runs on its own")
GuildOS:Throttle("t", 15, job)
check(runs == 3, "after the gap, a call runs at once again")
GuildOS:Throttle("other", 15, job)
check(runs == 4, "each key keeps its own gap")

-- ── answering the guild's asks ─────────────────────────────────────────

local CS = GuildOS.CommSystem
local answers = 0
function CS:BroadcastMyData() answers = answers + 1 end
local function ask(sender)
  CS:HandleRequest(sender, "ALL")
  advance(clock + 10)
end
ask("Cherry Arrow")
check(answers == 1, "somebody asking for the first time this session is answered")
ask("Cherry Arrow")
check(answers == 1, "their next ask inside the interval is the periodic pull: not answered again")
ask("Vex Morrow")
check(answers == 2, "somebody new is answered even inside the interval: a login gets the guild's data")
ask("Cherry Arrow")
check(answers == 2, "a known asker inside the interval is still not answered")
CS:HandleRequest("Cherry Arrow", "FULL")
advance(clock + 10)
check(answers == 3, "an ask by hand (/gos sync) is answered even inside the interval")
local asked
function CS:SendMessage(_, data) asked = data end
CS:RequestAllData(true)
check(asked == "FULL", "/gos sync asks by hand")
CS:RequestAllData()
check(asked == "ALL", "the periodic pull asks as before, which every version answers")
advance(clock + CS.ANSWER_INTERVAL)
ask("Cherry Arrow")
check(answers == 4, "past the interval, a known asker is answered again: the self-healing pull still heals")
check(CS.ANSWER_INTERVAL >= 300, "the interval is at least the five minutes of the periodic push")

-- ── the roster's scans ─────────────────────────────────────────────────

local scans, refreshed = 0, 0
function GuildOS:RecordFirstSeen() scans = scans + 1 end
function GuildOS:DropDeparted() end
function GuildOS:RefreshRosterUI() refreshed = refreshed + 1 end
advance(clock + 60)
GuildOS:OnGuildRosterUpdate()
check(scans == 1 and refreshed >= 1, "the first roster update scans at once")
for _ = 1, 10 do GuildOS:OnGuildRosterUpdate() end
check(scans == 1, "ten more updates inside the gap do not scan again at once")
check(refreshed >= 11, "an open roster window still follows every update")
advance(clock + 15)
check(scans == 2, "the burst ends in one scan")

-- ── the chat tweaks' cache ─────────────────────────────────────────────

GuildOS.ChatTweaks:Initialize()
rosterReads = 0
fire("GUILD_ROSTER_UPDATE")
check(rosterReads == 0, "with the chat tweaks off, the roster is not read for their cache")
GuildOS.db.chatTweaks.enabled = true
advance(clock + 60)
fire("GUILD_ROSTER_UPDATE")
check(rosterReads > 0 and GuildOS.ChatTweaks._cache["Cherry Arrow"] ~= nil, "switched on, the cache is built")
rosterReads = 0
for _ = 1, 10 do fire("GUILD_ROSTER_UPDATE") end
check(rosterReads == 0, "a burst of roster updates inside the gap does not rebuild it at once")
advance(clock + 15)
check(rosterReads > 0, "the burst ends in one rebuild")

io.write(string.format("quiet-guild: %d checks ok\n", checks))
