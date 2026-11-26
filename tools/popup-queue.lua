-- The one popup queue (audit B21, and "nothing drawn over the screen opens in combat"), run against the real
-- Core/Core.lua, Core/Compat.lua and Core/Utils.lua under a stubbed client.
--
-- A popup shows at once out of combat; in combat it waits for PLAYER_REGEN_ENABLED; one at a time, the next
-- when the previous closes (or after a short delay when it gave no frame, or at most POPUP_HOLD); login popups
-- in their fixed order; a key queued twice shows once; the window up now is redrawn in place.
--
--   lua5.1 -e 'ADDON="."' tools/popup-queue.lua
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
local frames = {}
function CreateFrame()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
  end
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70124", "", 16001 end
function GetRealmName() return "Classic Beta PvE 2" end
function GetLocale() return "enUS" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return NOW end
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end }
local function runTimers(maxDelay)
  local t = timers; timers = {}
  for _, x in ipairs(t) do
    if not maxDelay or x.d <= maxDelay then x.fn() else timers[#timers + 1] = x end
  end
end
local combat = false
function InCombatLockdown() return combat end
function UnitAffectingCombat() return false end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")

-- A window: shown, hidden, with its OnHide hooks.
local function window(name)
  local w = { name = name, shown = false, hooks = {} }
  function w:IsShown() return self.shown end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false; for _, h in ipairs(self.hooks) do h(self) end end
  function w:HookScript(k, fn) if k == "OnHide" then self.hooks[#self.hooks + 1] = fn end end
  return w
end
local opened = {}
local function popup(name, w)
  return function()
    opened[#opened + 1] = name
    if w then w:Show() end
    return w
  end
end

-- Out of combat, at once.
local a = window("a")
GuildOS:ShowWhenClear("a", popup("a", a))
check(opened[1] == "a" and a.shown, "out of combat a popup shows at once")
-- One at a time: the next waits for the first to close.
local b = window("b")
GuildOS:ShowWhenClear("b", popup("b", b))
check(#opened == 1, "a second waits while the first is up")
a:Hide()
check(opened[2] == "b" and b.shown, "and shows when the first closes")
-- A popup left open holds the rest at most POPUP_HOLD seconds.
GuildOS:ShowWhenClear("c", popup("c"))
check(#opened == 2, "behind the one up")
runTimers()
check(opened[3] == "c", "a window left open lets the next one through after a while")
-- No frame given back: the next one after a short delay.
GuildOS:ShowWhenClear("d", popup("d"))
check(#opened == 3, "behind the frameless one")
runTimers()
check(opened[4] == "d", "after the short delay")
runTimers()

-- In combat: nothing opens; all of it after PLAYER_REGEN_ENABLED, one at a time, the login ones in their order.
combat = true
local dg, ob, fd = window("digest"), window("onboarding"), window("founding")
GuildOS:ShowWhenClear("cta", popup("cta"))
GuildOS:ShowWhenClear("digest", popup("digest", dg))
GuildOS:ShowWhenClear("onboarding", popup("onboarding", ob))
GuildOS:ShowWhenClear("founding", popup("founding", fd))
GuildOS:ShowWhenClear("founding", popup("founding", fd))
check(#opened == 4, "in combat nothing opens")
fire("PLAYER_REGEN_DISABLED")
check(#opened == 4, "still nothing")
combat = false
fire("PLAYER_REGEN_ENABLED")
check(opened[5] == "onboarding" and #opened == 5, "once combat ends the first login popup shows, alone")
ob:Hide()
check(opened[6] == "founding", "then the founding letter")
fd:Hide()
check(opened[7] == "digest", "then the digest")
dg:Hide()
check(opened[8] == "cta" and #opened == 8, "then the rest; a key queued twice showed once")
runTimers()

-- Combat starting between two popups holds the next one.
local e = window("e")
GuildOS:ShowWhenClear("e", popup("e", e))
GuildOS:ShowWhenClear("f", popup("f"))
combat = true
e:Hide()
check(opened[#opened] == "e", "a fight begun meanwhile holds the next")
combat = false
fire("PLAYER_REGEN_ENABLED")
check(opened[#opened] == "f", "until it ends")
runTimers()

-- The window up now is redrawn in place; a cancelled one never shows; an error never jams the queue.
local cta = window("cta")
GuildOS:ShowWhenClear("cta", popup("cta1", cta))
GuildOS:ShowWhenClear("cta", popup("cta2", cta))
check(opened[#opened] == "cta2", "the same key on screen is redrawn at once")
GuildOS:ShowWhenClear("gone", popup("gone"))
check(GuildOS:CancelWhenClear("gone") and not GuildOS:CancelWhenClear("gone"), "a queued popup is cancelled")
cta:Hide()
check(opened[#opened] == "cta2", "and never shows")
GuildOS:ShowWhenClear("boom", function() error("x") end)
runTimers()
GuildOS:ShowWhenClear("after", popup("after"))
check(opened[#opened] == "after", "a popup that errors does not jam the queue")
check(GuildOS:InCombat() == false, "InCombat reads the client")

print(("popup-queue: %d checks passed"):format(checks))
