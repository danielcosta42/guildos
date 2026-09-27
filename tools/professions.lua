-- Professions on WoW: Forever (issue #31), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/Professions.lua, Modules/ProfSync.lua and DataCollector's hooks, under a
-- stubbed Forever client, a fixture catalog and a fake SyncService bus.
--
--   luajit -e 'ADDON="."' tools/professions.lua
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
local NOW = 1790500000
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() return {} end }
local function runTimers()
  local guard = 0
  while #timers > 0 do
    guard = guard + 1
    assert(guard < 1000, "timer loop")
    table.remove(timers, 1)()
  end
end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
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
function GetServerTime() return NOW end
function time() return NOW end
function IsInGuild() return true end
function hooksecurefunc() end
function debugstack() return "" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetRealmName() return "Classic Beta PvE 2" end
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
function UnitName(u) if u == "player" then return "Ana" end end
function UnitFullName(u) if u == "player" then return "Ana", "Silva" end end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }

-- The player's professions: GetProfessions() slots, GetProfessionInfo rows, known spells.
local SLOTS, PROFS, KNOWN = {}, {}, {}
function GetProfessions() return SLOTS[1], SLOTS[2], SLOTS[3], SLOTS[4], SLOTS[5] end
function GetProfessionInfo(i)
  local p = PROFS[i]
  if p then return p[1], 0, p[2], p[3], 0, 0, p[4], 0, -1, 0, p[1] end
end
function IsPlayerSpell(id) return KNOWN[id] == true end
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id } end }

-- The profession window: nil when closed.
local WINDOW
C_TradeSkillUI = {
  IsDataSourceChanging = function() return false end,
  IsTradeSkillLinked = function() return WINDOW and WINDOW.linked or false end,
  IsTradeSkillGuild = function() return false end,
  IsTradeSkillGuildMember = function() return false end,
  GetBaseProfessionInfo = function() return { professionID = WINDOW and WINDOW.line or 0 } end,
  GetAllRecipeIDs = function() return WINDOW and WINDOW.all or {} end,
  GetRecipeInfo = function(id)
    for _, x in ipairs(WINDOW and WINDOW.learned or {}) do
      if x == id then return { learned = true } end
    end
    return { learned = false }
  end,
}

-- The guild: roster names and the Communities roster's profession fields.
local ROSTER = { "Ana Silva", "Bob", "Cid", "Dee" }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  if ROSTER[i] then return ROSTER[i], "Member", 3, 20, "Mage", "", "", "", true, 0, "MAGE" end
end
local CLUB = {}
C_Club = {
  GetGuildClubId = function() return 7 end,
  GetClubMembers = function()
    local t = {}
    for i in ipairs(CLUB) do t[i] = i end
    return t
  end,
  GetMemberInfo = function(_, i) return CLUB[i] end,
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
dofile(ADDON .. "/Libs/LibDeflate.lua")
local Compat = BRutus.Compat

-- ── 1. Compat ───────────────────────────────────────────────────────────
check(not BRutus.Client.isAnniversary, "the stub is a Forever client")
SLOTS = { 1, nil, 2 }
check(select("#", Compat.GetProfessions()) == 5 and select(3, Compat.GetProfessions()) == 2,
      "GetProfessions passes every slot through, nils included")
PROFS[1] = { "Mineração", 21, 75, 186 }
check(select(7, Compat.GetProfessionInfo(1)) == 186 and select(3, Compat.GetProfessionInfo(1)) == 21,
      "GetProfessionInfo passes rank and skill line through")
KNOWN[2657] = true
check(Compat.IsPlayerSpell(2657) == true and Compat.IsPlayerSpell(1) == false, "IsPlayerSpell is a boolean")
check(Compat.TradeSkillLearned() == nil, "no window, no learned list")
WINDOW = { line = 186, all = { 2657, 3304 }, learned = { 2657 } }
local line, learned = Compat.TradeSkillLearned()
check(line == 186 and #learned == 1 and learned[1] == 2657, "the own window gives its line and learned IDs")
WINDOW.linked = true
check(Compat.TradeSkillLearned() == nil, "a linked (someone else's) window is ignored")
WINDOW = nil
CLUB = { { name = "Bob", profession1ID = 186, profession2ID = 0 },
         { name = "Cid", profession1ID = 164, profession2ID = 185 } }
local club = Compat.GuildMemberProfessions()
check(#club == 2 and club[1].name == "Bob" and #club[1].lines == 1 and #club[2].lines == 2,
      "the Communities roster gives each member's profession lines, zeros dropped")
issecretvalue = function(v) return v == "Cid" end
check(#Compat.GuildMemberProfessions() == 1, "a member whose fields are secret is skipped")
issecretvalue = nil
local saved = GetProfessions
GetProfessions = nil
check(select("#", Compat.GetProfessions()) == 0, "no API, nothing")
GetProfessions = saved
CLUB, SLOTS, PROFS, KNOWN = {}, {}, {}, {}

print("professions: " .. checks .. " checks passed")
