-- Issue #324: an officer of a 700-member guild saw Guild OS take a lot of CPU. Every request from any
-- guildmate made every client answer on GUILD (an officer with ~36 backfills), and every roster event ran
-- four passes over the whole roster. Run against the real Core/Core.lua, Core/Compat.lua and
-- Modules/CommSystem.lua:
--   * GuildOS:Coalesce runs at once, holds what comes inside the window, runs the last call once at
--     its end, and nothing when nothing came;
--   * a roster burst costs two passes;
--   * a client answers one automatic request per ANSWER_GAP, a /gos sync (NOW) within NOW_GAP, and
--     every request held gets an answer;
--   * /gos sync asks with NOW, everything else with ALL;
--   * GuildOS.Perf counts, times, sorts and resets, and says what the game's profiler says.
--
--   luajit -e 'ADDON="."' tools/coalesce.lua
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

-- ── A client whose clock and timers this file moves ────────────────────
local clock, timers = 1000, {}
function GetTime() return clock end
function GetServerTime() return 1794500000 + clock end
C_Timer = {
  After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end,
  NewTicker = function() return { Cancel = function() end } end,
}
local function advance(seconds)
  local stop = clock + seconds
  while true do
    local nextI
    for i, t in ipairs(timers) do
      if t.at <= stop and (not nextI or t.at < timers[nextI].at) then nextI = i end
    end
    if not nextI then break end
    local t = table.remove(timers, nextI)
    clock = math.max(clock, t.at)
    t.fn()
  end
  clock = stop
end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70862", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Chehul", "Lightdrizzle" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Realm" end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end

local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
local LD = LibStub("LibDeflate")
LD.CompressDeflate = function(_, s) return s end
LD.EncodeForWoWAddonChannel = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
local CS = GuildOS.CommSystem
GuildOS.Compat.SendAddonMessage = function() end

-- ── 1. GuildOS:Coalesce ───────────────────────────────────────────────
local runs = {}
local function a() runs[#runs + 1] = "a" end
local function b() runs[#runs + 1] = "b" end
check(GuildOS:Coalesce("x", 5, a) == true and #runs == 1, "the first call runs at once")
check(GuildOS:Coalesce("x", 5, a) == false and GuildOS:Coalesce("x", 5, b) == false and #runs == 1,
  "calls inside the window are held")
advance(4)
check(#runs == 1, "nothing runs before the window ends")
advance(1)
check(#runs == 2 and runs[2] == "b", "the window's end runs once, with the last call")
advance(10)
check(#runs == 2, "a window where nothing came runs nothing")
check(GuildOS:Coalesce("x", 5, a) == true and #runs == 3, "after the window a call runs at once again")
check(GuildOS:Coalesce("y", 5, b) == true and #runs == 4, "each name has its own window")
advance(10)
check(#runs == 4, "and a run at once leaves nothing behind")

-- ── 2. A roster burst costs two passes ────────────────────────────────
local passes = 0
GuildOS.RecordFirstSeen = function() passes = passes + 1 end
GuildOS.DropDeparted = function() end
for _ = 1, 10 do
  GuildOS:OnGuildRosterUpdate()
  advance(0.25)
end
check(passes == 1, "ten roster events in two and a half seconds: one pass at once")
advance(GuildOS.ROSTER_GAP)
check(passes == 2, "and one when the window ends, not ten")
check(GuildOS.State.perf.rows["roster event"].n == 10 and GuildOS.State.perf.rows["roster pass"].n == 2,
  "/gos perf counts every event and every pass")

-- ── 3. Requests: one answer a window, none lost ───────────────────────
local answers = 0
CS._Answer = function() answers = answers + 1 end
local function settle() advance(CS.ANSWER_GAP * 3) end
settle()
CS:HandleRequest("Mem", "ALL")
check(answers == 1, "the first request is answered at once")
for _ = 1, 5 do
  advance(10)
  CS:HandleRequest("Other", "ALL")
end
check(answers == 1, "five more within ANSWER_GAP are held")
advance(CS.ANSWER_GAP - 50 - 1)
check(answers == 1, "nothing goes out before the window ends")
advance(1)
check(answers == 2, "and the window's end answers them all, once")
settle()
check(answers == 2, "a window with nothing held sends nothing")

CS:HandleRequest("Mem", "")
check(answers == 3, "a request with no word (an older client) is answered like ALL")
advance(5)
CS:HandleRequest("Mem", "ALL")
advance(3)
CS:HandleRequest("Syncer", "NOW")
check(answers == 3, "a /gos sync inside NOW_GAP waits")
advance(CS.NOW_GAP - 8)
check(answers == 4, "and is answered when NOW_GAP ends, not at ANSWER_GAP")
settle()
check(answers == 4, "the ALL held before it was answered by that one, not again")

CS:HandleRequest("Mem", "ALL")
advance(CS.NOW_GAP + 1)
CS:HandleRequest("Syncer", "NOW")
check(answers == 6, "past NOW_GAP a /gos sync is answered at once")
settle()
check(answers == 6, "and nothing was left waiting")
local rows = GuildOS.State.perf.rows
check(rows["guild sync request"].n == 11 and rows["guild sync request answered"].n == 6
  and rows["guild sync request held"].n == 7, "/gos perf counts the requests, the answers and the held")

-- ── 4. /gos sync asks with NOW ────────────────────────────────────────
local asked = {}
local send = CS.SendMessage
CS.SendMessage = function(_, kind, data) asked[#asked + 1] = kind .. ":" .. tostring(data) end
CS:RequestAllData()
CS:RequestAllData(true)
CS.SendMessage = send
check(asked[1] == "RQ:ALL" and asked[2] == "RQ:NOW", "the automatic request says ALL, a /gos sync NOW")
local fh = assert(io.open(ADDON .. "/Modules/CommSystem.lua", "rb"))
local src = fh:read("*a")
fh:close()
local full = src:match("function CommSystem:FullSync%(%)(.-)\nend")
check(full and full:find("self:RequestAllData(true)", 1, true), "FullSync asks with NOW")

-- ── 5. GuildOS.Perf ───────────────────────────────────────────────────
GuildOS.Perf:Reset()
check(#GuildOS.Perf:Lines() == 3 and GuildOS.Perf:Lines()[3] == "Nothing measured yet.",
  "after a reset nothing is measured")
check(GuildOS.Perf:Lines()[2] == "This client has no addon profiler; the times below are Guild OS's own.",
  "a client with no profiler says so")
local ms = 0
debugprofilestop = function() return ms end
dofile(ADDON .. "/Core/Core.lua")   -- the clock is read when the file loads
GuildOS.Perf:Reset()
local t = GuildOS.Perf:Start()
ms = 12.4
GuildOS.Perf:Stop("slow", t, 2048)
t = GuildOS.Perf:Start()
ms = 12.9
GuildOS.Perf:Stop("fast", t)
GuildOS.Perf:Count("fast")
local lines = GuildOS.Perf:Lines()
check(lines[3]:find("^slow: 1 ") and lines[3]:find("12 ms, max 12.4", 1, true) and lines[3]:find("2.0 KB", 1, true),
  "the slowest comes first, with its total, its worst and its bytes")
check(lines[4]:find("^fast: 2 ") and lines[4]:find("max 0.5", 1, true), "counted calls add up with timed ones")

C_AddOnProfiler = {
  GetAddOnMetric = function(name, m) return name == "GuildOS" and ({ [1] = 0.5, [0] = 0.25, [4] = 9 })[m] end,
  GetOverallMetric = function(m) return m == 1 and 3 or nil end,
}
Enum.AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4 }
local cpu = GuildOS.Compat.AddOnCPU("GuildOS")
check(cpu and cpu.recent == 0.5 and cpu.session == 0.25 and cpu.peak == 9 and cpu.all == 3,
  "the game's profiler is read: now, this session, the peak and every addon")
check(GuildOS.Perf:Lines()[2]:find("0.50", 1, true), "and /gos perf says it")
C_AddOnProfiler.GetAddOnMetric = function() error("no such addon") end
check(GuildOS.Compat.AddOnCPU("GuildOS") == nil, "a profiler that raises reads as none")
C_AddOnProfiler = nil
check(GuildOS.Compat.AddOnCPU("GuildOS") == nil, "and so does a client without one")

print(string.format("coalesce: %d checks passed", checks))
