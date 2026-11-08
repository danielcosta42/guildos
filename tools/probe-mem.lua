-- /gos probe mem (issue #285), run against the real Core/Core.lua, Core/Compat.lua and Core/Probe.lua.
--
-- On 2026-11-08 the addon held 16 MB after a collection and allocated 77 MB a minute standing still.
-- The probe wraps every function of every module for two minutes and counts what each one allocates:
-- every call in "incl", only the outermost in "top", so the top list adds up without counting a
-- nested call twice. It must change nothing it measures: same returns, same errors, and every
-- function back as it was when it ends.
--
--   luajit -e 'ADDON="."' tools/probe-mem.lua
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

local timers, printed, clock = {}, {}, 100
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = tostring(msg) end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetTime() return clock end
function GetServerTime() return 1762600000 end
time = os.time
function debugprofilestop() return os.clock() * 1000 end
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
C_ChatInfo = { InChatMessagingLockdown = function() return false end }
Enum = { SendAddonMessageResult = {} }
function IsInGuild() return true end
function InCombatLockdown() return false end
function GetRealmName() return "Realm" end
local addonKb = 1000
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage(name) return name == "GuildOS" and addonKb or 0 end

-- What the probe asks of the collector, passed through.
local realCollect = collectgarbage
local asked = {}
collectgarbage = function(opt, ...)
  if opt == "stop" or opt == "restart" then asked[#asked + 1] = opt end
  return realCollect(opt, ...)
end

GuildOSDB = nil
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Probe.lua")
local Probe = GuildOS.Probe

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
local function said(text)
  for _, line in ipairs(printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

-- Two modules with known appetites, a data table, and a module with a metatable (a class, or data).
GuildOS.Heavy = {}
function GuildOS.Heavy:Churn(n)
  local t = {}
  for i = 1, n do t[i] = { i, tostring(i) .. "x" } end
  return #t, "done"
end
function GuildOS.Heavy:Calls() return GuildOS.Light:Small() end
GuildOS.Light = {}
function GuildOS.Light:Small()
  local t = {}
  for i = 1, 50 do t[i] = {} end
  return 7
end
function GuildOS.Light:Boom() error("boom") end
GuildOS.db = { members = {}, fn = function() return 1 end }
GuildOS.Classy = setmetatable({ Method = function() return 3 end }, { __index = {} })
function GuildOS:OwnMethod() return "own" end

local churn, small, boom, own = GuildOS.Heavy.Churn, GuildOS.Light.Small, GuildOS.Light.Boom, GuildOS.OwnMethod
local dbFn, classy = GuildOS.db.fn, GuildOS.Classy.Method
local finishMem = Probe.FinishMem

-- ── while it runs ──────────────────────────────────────────────────────

check(Probe:RunMem() ~= nil, "the probe starts")
check(said("120"), "it says for how long it measures")
check(GuildOS.Heavy.Churn ~= churn and GuildOS.Light.Small ~= small, "module functions are wrapped")
check(GuildOS.OwnMethod ~= own, "GuildOS's own functions are wrapped")
check(Probe.FinishMem == finishMem, "the probe does not wrap itself")
check(GuildOS.db.fn == dbFn, "the saved data is not touched")
check(GuildOS.Classy.Method == classy, "a table with a metatable is not touched")
check(asked[1] == "stop", "the collector is asked to stop, so the counts are exact")
check(Probe:RunMem() == nil and said("already running"), "a second run while one runs is refused")

local n, word = GuildOS.Heavy:Churn(20000)
check(n == 20000 and word == "done", "a wrapped function returns what it returned, all of it")
check(GuildOS.Heavy:Calls() == 7, "a nested call returns through both wrappers")
local ok, err = pcall(GuildOS.Light.Boom, GuildOS.Light)
check(not ok and tostring(err):find("boom", 1, true), "an error still reaches the caller")
for _ = 1, 3 do GuildOS.Light:Small() end
check(GuildOS:OwnMethod() == "own", "GuildOS's own method still answers")
local captured = GuildOS.Heavy.Churn   -- a timer made during the run keeps the wrapper

-- ── when it ends ───────────────────────────────────────────────────────

addonKb = 1000 + 2048
advance(clock + Probe.MEM_SECONDS)
check(GuildOS.Heavy.Churn == churn and GuildOS.Light.Small == small and GuildOS.Light.Boom == boom,
  "every module function is back as it was")
check(GuildOS.OwnMethod == own, "GuildOS's own functions are back as they were")
check(asked[#asked] == "restart", "the collector is started again")
local select2 = select(2, captured(GuildOS.Heavy, 3))
check(select2 == "done", "a wrapper somebody kept passes through after the run")

local r = GuildOSDB and GuildOSDB.probeMem
check(type(r) == "table", "the result is saved in GuildOSDB.probeMem")
check(r.gcStopped == true, "it says the collector was stopped")
check(r.addonKb == 2048, "the game's own count for the addon is kept, as a reference")
check(type(r.wrapped) == "number" and r.wrapped >= 5, "it says how many functions it watched")
local sum = 0
for _, x in ipairs(r.top) do sum = sum + x.kb end
check(r.topKb and math.abs(r.topKb - sum) <= #r.top, "the headline is the sum of the outermost calls")
check(not said("2.0 MB (") and said(string.format("%.1f MB (", r.topKb / 1024)),
  "the chat says that sum, not the game's count, which the field showed negative")

local function row(list, name)
  for _, x in ipairs(list) do if x.name == name then return x end end
end
local heavyTop, lightTop = row(r.top, "Heavy:Churn"), row(r.top, "Light:Small")
check(heavyTop and heavyTop.calls == 1 and heavyTop.kb > 100, "the churning call leads, counted once")
check(r.top[1].name == "Heavy:Churn", "the top list is sorted by what each allocated")
check(lightTop and lightTop.calls == 3, "on top, only the calls nothing wrapped was around")
local lightIncl = row(r.incl, "Light:Small")
check(lightIncl and lightIncl.calls == 4, "every call, nested ones too, in incl")
check(row(r.top, "Heavy:Calls") ~= nil, "the outer call of a nest is on top")
check(row(r.top, "Light:Boom") and row(r.top, "Light:Boom").calls == 1, "a call that raised is still counted")
check(type(r.slow) == "table" and #r.slow > 0, "the slowest calls are listed too")
check(said("probeMem"), "it says where the result is")
check(said("Heavy:Churn"), "the chat names what allocated most")

io.write(string.format("probe-mem: %d checks ok\n", checks))
