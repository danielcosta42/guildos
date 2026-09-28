-- The look on WoW: Forever (issue #37): read in the barber's chair, kept on the player's own
-- record, told to the guild once per change. Runs the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua and Modules/Look.lua under a stubbed Forever client and barber's chair.
--
--   luajit -e 'ADDON="."' tools/look.lua
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

-- ── The client: WoW: Forever ────────────────────────────────────────────
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() return {} end }
local function runTimers()
  while #timers > 0 do table.remove(timers, 1)() end
end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
SlashCmdList = {}
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(_, fn) self.onEvent = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
  end
end
function GetServerTime() return 1790600000 end
function time() return 1790600000 end
function hooksecurefunc(t, name, fn)
  local orig = t[name]
  t[name] = function(...) orig(...); fn(...) end
end
function debugstack() return "" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetRealmName() return "Classic Beta PvE 2" end
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
function UnitName(u) if u == "player" then return "Chehul" end end
function UnitFullName(u) if u == "player" then return "Chehul", "Shammy" end end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }

-- The barber's chair: nil when the character is not sitting in one.
local CHAIR
local function option(id, choices, current)
  local t = {}
  for i, c in ipairs(choices) do t[i] = { id = c, name = "" } end
  return { id = id, name = "", choices = t, currentChoiceIndex = current }
end
local applied = 0
C_BarberShop = {
  GetAvailableCustomizations = function() return CHAIR end,
  ApplyCustomizationChoices = function() applied = applied + 1 end,
}

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
check(not BRutus.Client.isAnniversary, "the stub is a Forever client")

BRutus.db = { members = {} }
local broadcasts = 0
BRutus.CommSystem = { BroadcastMyData = function(_, force) if force then broadcasts = broadcasts + 1 end end }
dofile(ADDON .. "/Modules/Look.lua")
local Look = BRutus.Look
check(Look ~= nil, "the module loads on Forever")
Look:Initialize()
local KEY = BRutus:GetPlayerKey(BRutus.Compat.PlayerName(), GetRealmName())

-- ── Outside the chair: nothing ──────────────────────────────────────────
check(Look.Read() == nil, "no chair, no look")
fire("BARBER_SHOP_OPEN")
runTimers()
check(BRutus.db.members[KEY] == nil and broadcasts == 0, "an empty chair writes nothing and tells nobody")

-- ── Sitting down ────────────────────────────────────────────────────────
CHAIR = {
  { name = "Principal", options = {
      option(22, { 415, 416, 422 }, 3),
      option(19, { 350, 359 }, 2),
      option(20, { 380, 387 }, nil),          -- no current choice: skipped
      { id = "x", choices = {}, currentChoiceIndex = 1 },
  } },
  { name = "Aparência", options = { option(9493, { 78923, 78927 }, 2), option(19, { 1 }, 1) } },
  "junk",
}
BRutus.db.members[KEY] = { name = "Chehul Shammy", lastUpdate = 5 }
BRutus.db.myData = BRutus.db.members[KEY]
fire("BARBER_SHOP_OPEN")
check(BRutus.db.members[KEY].look == nil, "the look is read once the chair settles, not on the event itself")
runTimers()
local look = BRutus.db.members[KEY].look
check(type(look) == "table" and #look == 3, "three options with a current choice")
check(look[1][1] == 19 and look[1][2] == 359 and look[2][1] == 22 and look[2][2] == 422
      and look[3][1] == 9493 and look[3][2] == 78927, "pairs of {option, choice}, by option, the first of an option wins")
check(BRutus.db.members[KEY].lastUpdate == 5 and BRutus.db.members[KEY].name == "Chehul Shammy",
      "the rest of the record is untouched")
check(broadcasts == 1, "the guild is told at once")
check(#chat == 1 and chat[1]:find("guildos.me", 1, true), "the player is told, once")

-- ── The same look again: quiet ──────────────────────────────────────────
fire("BARBER_SHOP_OPEN")
runTimers()
check(broadcasts == 1 and #chat == 1, "sitting down again with the same look says nothing")

-- ── Previewing, then buying ─────────────────────────────────────────────
CHAIR[1].options[1].currentChoiceIndex = 1          -- a preview: nothing is kept for it
check(BRutus.db.members[KEY].look[2][2] == 422 and broadcasts == 1, "a preview is not a look")
C_BarberShop.ApplyCustomizationChoices()            -- the purchase, still in the chair
check(applied == 1, "the game's own purchase still runs")
CHAIR = nil                                         -- the game stands the player up at once
fire("BARBER_SHOP_APPEARANCE_APPLIED")
check(BRutus.db.members[KEY].look[2][2] == 415, "the look bought is the one kept, read at the purchase")
check(broadcasts == 2 and #chat == 2, "and the guild is told again")
fire("BARBER_SHOP_APPEARANCE_APPLIED")
check(broadcasts == 2, "a second confirmation with nothing bought keeps quiet")

-- ── Leaving the chair never erases it ───────────────────────────────────
CHAIR = nil
fire("BARBER_SHOP_OPEN")
runTimers()
check(BRutus.db.members[KEY].look ~= nil and broadcasts == 2, "no chair afterwards keeps the look")

-- ── A cap on what is kept ───────────────────────────────────────────────
local many = {}
for i = 1, 50 do many[i] = option(1000 + i, { i }, 1) end
CHAIR = { { options = many } }
check(#Look.Read() == 32, "at most 32 pairs, the site's cap")

-- ── Anniversary: the module does not exist ──────────────────────────────
BRutus.Look = nil
BRutus.Client.isAnniversary = true
dofile(ADDON .. "/Modules/Look.lua")
check(BRutus.Look == nil, "no module on Anniversary")

print(("look: %d checks passed"):format(checks))
