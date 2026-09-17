-- Start-up isolation (issue #6), run against the real Core/Core.lua,
-- Core/Compat.lua and UI/FeatureRegistry.lua under stubbed WoW APIs.
--
-- A new client can lack an API a module touches while it starts, or an event
-- or tooltip script a module registers. Any of those used to raise inside
-- BRutus:InitModules and leave every later module unstarted. This proves the
-- failure now stays with the module that raised, that unknown events and
-- tooltip scripts do not raise, that /guildos errors can always name what
-- failed, and that the login line appears only when something went wrong.
--
--   luajit -e 'ADDON="."' tools/startup-isolation.lua
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

-- ── WoW API surface ───────────────────────────────────────────────────
-- Only these events exist on the stub client; anything else raises the way
-- the real RegisterEvent does.
local KNOWN_EVENTS = {
  ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true,
  GUILD_ROSTER_UPDATE = true, PLAYER_GUILD_UPDATE = true,
}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e)
    if not KNOWN_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end
    self.events[e] = true
  end
  function f:SetScript() end
  return f
end

local printed, timers = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
function GetServerTime() return 1757800000 end
function IsInGuild() return false end
function hooksecurefunc() end
function debugstack() return "stack!" end
function GetBuildInfo() return "2.5.6", "1", "", 20506 end  -- Compat.lua reads it at load

-- Timers run when the test says so, not after a delay.
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers()
  local due = timers
  timers = {}
  for _, fn in ipairs(due) do fn() end
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
BRutus.UI = {}
dofile(ADDON .. "/UI/FeatureRegistry.lua")

-- Defined in files this harness does not load.
function BRutus:RegisterUtilTests() end
function BRutus:HookChatInvite() end
local officer = true
function BRutus:IsOfficer() return officer end
BRutus.db = { settings = { modules = {} } }

-- A fake module records every start function it runs; `raises` names the
-- functions that raise instead.
local started, defined = {}, {}
local function module(name, raises)
  raises = raises or {}
  local mod = {}
  for _, method in ipairs({ "Initialize", "InitParticipation", "CheckExpired" }) do
    mod[method] = function()
      if raises[method] then error(name .. ":" .. method .. " exploded") end
      started[name .. ":" .. method] = true
    end
  end
  BRutus[name] = mod
  defined[#defined + 1] = name
end
local RAISE = { Initialize = true }

local function reset()
  for _, name in ipairs(defined) do BRutus[name] = nil end
  started, defined, printed, timers = {}, {}, {}, {}
  officer = true
  BRutus.db.settings.modules = {}
  BRutus.State.errors = {}
  BRutus.State.startup = { failed = {}, failedFeatures = {}, stacks = {} }
  BRutus.State.missing = {}
end

local function boot()
  BRutus:InitModules()
  runTimers()
end

local function countPrinted(text)
  local n = 0
  for _, m in ipairs(printed) do
    if m:find(text, 1, true) then n = n + 1 end
  end
  return n
end

-- ── 1. Modules in the middle raise; everything after them still starts ──
reset()
module("DataCollector")         -- first in the list
module("Wishlist", RAISE)       -- backs the wishlist window
module("Points", RAISE)         -- has a Settings toggle and backs the DKP window
module("RecipeTracker")         -- after both failures
module("ModPresets")            -- last in the list
module("TrialTracker")          -- officer-only, with a follow-up step
boot()

check(started["DataCollector:Initialize"], "the first module started")
check(started["RecipeTracker:Initialize"], "a module after the failures started")
check(started["ModPresets:Initialize"], "the last module started")
check(started["TrialTracker:Initialize"] and started["TrialTracker:CheckExpired"],
  "officer modules, follow-up step included, started after the failures")
local startup = BRutus.State.startup
check(startup.failed.Wishlist and startup.failed.Wishlist:find("exploded", 1, true),
  "the failure is recorded against the module")
check(startup.stacks.Wishlist == "stack!", "the stack of the failure is kept")
check(BRutus:FeatureStartFailed("wishlist") == "Wishlist", "the wishlist window knows its module failed")
check(BRutus:FeatureStartFailed("points") == "Points" and BRutus:FeatureStartFailed("dkp") == "Points",
  "both the toggle and the window of a failed module are marked")
check(BRutus:FeatureStartFailed("recipes") == nil, "a module that started does not mark its window")
check(BRutus.UI:IsFeatureAllowed({ id = "wishlist" }) == false, "the window of a failed module refuses to open")
check(BRutus.UI:IsFeatureAllowed({ id = "recipes" }) == true, "the window of a module that started still opens")
local listed = table.concat(BRutus:ListStartupProblems(), "\n")
check(listed:find("Wishlist: ", 1, true) and listed:find("Points: ", 1, true),
  "/guildos errors can name every start-up failure")
check(countPrinted("2 start-up problem(s)") == 1, "one login line counts both failures")

-- ── 2. Unknown events and tooltip scripts do not raise ──────────────────
reset()
local f = CreateFrame()
check(BRutus.Compat.RegisterEvent(f, "PLAYER_LOGIN") == true and f.events.PLAYER_LOGIN, "a known event registers")
check(BRutus.Compat.RegisterEvent(f, "CRAFT_SHOW") == false, "an unknown event returns false instead of raising")
BRutus.Compat.RegisterEvent(f, "CRAFT_SHOW")
check(BRutus.State.missing["event CRAFT_SHOW"], "the unknown event is recorded")
check(#BRutus.State.errors == 1, "the same unknown event is recorded once")
check(table.concat(BRutus:ListStartupProblems(), "\n"):find("event CRAFT_SHOW", 1, true),
  "/guildos errors can name the missing event")

local tt = {
  HasScript = function(_, script) return script == "OnTooltipCleared" end,
  HookScript = function(self, script) self.hooked = script end,
}
check(BRutus.Compat.HookTooltip(tt, "OnTooltipSetItem", function() end) == false and tt.hooked == nil,
  "a tooltip script the frame lacks is skipped")
check(BRutus.State.missing["tooltip script OnTooltipSetItem"], "the missing tooltip script is recorded")
check(BRutus.Compat.HookTooltip(tt, "OnTooltipCleared", function() end) == true and tt.hooked == "OnTooltipCleared",
  "a supported tooltip script is hooked")
local before = #BRutus.State.errors
check(BRutus.Compat.HookTooltip(nil, "OnTooltipSetItem", function() end) == false, "a tooltip not built yet is skipped")
check(#BRutus.State.errors == before, "a tooltip not built yet is not reported as missing")

-- ── 3. A clean start prints nothing ─────────────────────────────────────
reset()
module("Wishlist")
module("Points")
boot()
check(started["Wishlist:Initialize"] and started["Points:Initialize"], "the modules start when nothing raises")
check(countPrinted("start-up problem") == 0, "a clean start prints no login line")

-- ── 4. Toggles and rank still decide what starts ────────────────────────
reset()
BRutus.db.settings.modules.raidTracker = false
module("RaidTracker")
module("TrialTracker")
officer = false
boot()
check(not started["RaidTracker:Initialize"], "a module switched off in Settings does not start")
check(not started["TrialTracker:Initialize"], "officer modules do not start for a member")
check(countPrinted("start-up problem") == 0, "skipped modules are not failures")

-- ── 5. A missing event alone still gets the login line ──────────────────
reset()
BRutus.Compat.RegisterEvent(CreateFrame(), "CRAFT_SHOW")   -- as a file-scope registration would
boot()
check(countPrinted("1 start-up problem(s)") == 1, "a missing event alone gets the login line")

-- ── 6. A member, not only an officer, gets the login line ───────────────
reset()
officer = false
module("Wishlist", RAISE)
boot()
check(countPrinted("1 start-up problem(s)") == 1, "a member with a failed module gets the login line")

-- ── 7. Officer modules are isolated too; `after` needs a clean start ────
reset()
module("OfficerNotes", RAISE)
module("TrialTracker")
boot()
check(started["TrialTracker:Initialize"], "an officer module after a failing one still starts")

reset()
module("TrialTracker", RAISE)
boot()
check(not started["TrialTracker:CheckExpired"], "the follow-up step does not run when Initialize failed")

reset()
module("TrialTracker", { CheckExpired = true })
boot()
check(BRutus.State.startup.failed["TrialTracker:CheckExpired"] and not BRutus.State.startup.failed.TrialTracker,
  "a failed follow-up step is recorded under its own label")

-- ── 7b. A start-up step whose error handler cannot run still does not abort ──
reset()
module("Wishlist")
BRutus.Wishlist.Initialize = function()
  error(setmetatable({}, { __tostring = function() error("unprintable") end }))
end
module("ModPresets")
boot()
check(started["ModPresets:Initialize"], "an unprintable error in one module does not stop the modules after it")
check(BRutus.State.startup.failed.Wishlist, "the unprintable error is still recorded")

-- ── 8. Two stages of one module are recorded separately ─────────────────
reset()
module("Recruitment", { InitParticipation = true, Initialize = true })
boot()
local failed = BRutus.State.startup.failed
check(failed["Recruitment:InitParticipation"] and failed.Recruitment,
  "the member stage and the officer stage each keep their own record")
check(countPrinted("2 start-up problem(s)") == 1, "both stages are counted")

io.write(string.format("startup-isolation: %d checks passed\n", checks))
