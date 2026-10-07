-- The loot master's raid lines on WoW: Forever (issue #63), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua and Modules/LootMaster.lua, once as each game.
--
-- Forever drops a chat line an addon sends without a click behind it (#61). The loot master
-- sends from clicks (announce, award, cancel, DE), and also from events and timers: the
-- countdown, "[WINNER]" when time runs out, and the per-roll "MS converted to OS" and prio or
-- wishlist lines. On Forever those print for the loot master only, the countdown is not
-- scheduled (the raiders' popup counts down), and ending the roll by its button still announces.
--
--   luajit -e 'ADDON="."' tools/loot-click.lua
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

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70170", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  function GetRealmName() return "Realm" end
  function UnitName() return "Chehul" end
  function GetServerTime() return 1790000000 end
  function GetTime() return 1000 end
  time = function() return 1790000000 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function strlower(s) return s:lower() end
  function IsInRaid() return true end
  function GetNumGroupMembers() return 0 end
  function IsInGuild() return true end
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  local timers = {}
  C_Timer = { After = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end,
              NewTimer = function(d, fn) timers[#timers + 1] = { d = d, fn = fn }; return { Cancel = function() end } end,
              NewTicker = function() end }
  local sent = {}
  function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/LootMaster.lua")
  local LM = GuildOS.LootMaster
  GuildOS.db = { lootMaster = {}, lootPrios = { [30627] = { { name = "Ana", order = 1 } } } }
  local printed = {}
  function GuildOS:Print(m) printed[#printed + 1] = m end
  -- What a roll needs around it, kept to the lines under test.
  LM.GetPlayerContext = function() return { att25 = 40, recvThisLockout = 0 } end
  LM.GetCfg = function() return { minAttendancePct = 50 } end
  LM.StopListeningForRolls = function() end
  LM.ROLL_DURATION = 30
  LM.activeLoot = { link = "[Tsunami Talisman]", itemId = 30627, startTime = 0, endTime = 30 }
  LM.rolls = {}
  return LM, sent, timers, printed
end

-- ── Forever ─────────────────────────────────────────────────────────────
local LM, sent, timers, printed = load("forever")
LM:ScheduleCountdownWarnings()
check(#timers == 0, "Forever: no countdown is scheduled; the raiders' popup counts down")
LM:RegisterRoll("Bob", "MS", 77)
check(#sent == 0, "Forever: a roll arriving sends no 'MS converted to OS' line, where the game would drop it")
check(printed[#printed]:find("MS converted to OS"), "the loot master still reads it")
LM:RegisterRoll("Ana", "OS", 50)
check(#sent == 0 and printed[#printed]:find("Official Prio"), "nor the prio line")
GuildOS.Wishlist = { GetItemInterest = function() return { { name = "Cid", order = 2 } } end }
LM:RegisterRoll("Cid", "OS", 40)
check(#sent == 0 and printed[#printed]:find("Wishlist"), "nor the wishlist line")
GuildOS.Wishlist = nil
LM:EndRolling()
check(#sent == 0 and printed[#printed]:find("WINNER"), "time running out ends the roll and tells the loot master only")
LM.activeLoot = { link = "[Tsunami Talisman]", itemId = 30627, startTime = 0, endTime = 30 }
LM.rolls = {}
LM:EndRolling()
check(#sent == 0 and printed[#printed]:find("No roll received"), "and so does the line for a roll nobody answered")
LM.activeLoot = { link = "[Tsunami Talisman]", itemId = 30627, startTime = 0, endTime = 30 }
LM.rolls = { ["Ana-Realm"] = { name = "Ana", rollType = "MS", roll = 90 } }
LM:EndRolling(true)
check(#sent == 1 and sent[1].chan == "RAID_WARNING" and sent[1].msg:find("WINNER"),
      "the End Rolling button announces the winner, from its click")
LM:SafeSendChat("[Loot] Ana delivered", "RAID")
check(#sent == 2, "a line sent from a click goes out as before")
-- The End Rolling button is the one place that ends a roll by a click: it must say so.
local f = assert(io.open(ADDON .. "/Modules/LootMaster.lua", "rb"))
local src = f:read("*a")
f:close()
local onClick = src:match('endBtn:SetScript%("OnClick", function%(%)(.-)end%)')
check(onClick and onClick:find("EndRolling%(true%)"), "the End Rolling button ends the roll as a click")

-- ── Anniversary: as it was ──────────────────────────────────────────────
LM, sent, timers = load("anniversary")
LM:ScheduleCountdownWarnings()
check(#timers == 5, "Anniversary: the countdown is scheduled, five lines")
LM:RegisterRoll("Bob", "MS", 77)
check(#sent == 1 and sent[1].msg:find("MS converted to OS"), "Anniversary: the roll's line goes out")
LM:EndRolling()
check(sent[#sent].chan == "RAID_WARNING", "and time running out announces the winner")

print(("loot-click: %d checks passed"):format(checks))
