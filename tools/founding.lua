-- The founding (issue #208), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/SyncService.lua and Modules/Founding.lua.
--
-- What this holds: only a day between the launch and today is a founding day; only the GM records
-- it, an officer suggests; the highest revision wins on every client; a join date is taken only
-- from the member it is about; the founding members are the GM, whoever joined inside the 14 days,
-- and nobody after; the letter comes at most three times, a day apart.
--
--   luajit -e 'ADDON="."' tools/founding.lua
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

local DAY = 86400
local LAUNCH = 1793750400              -- 2026-11-04 00:00 UTC
local NOW = LAUNCH + 20 * DAY + 3600   -- 24 Nov, 01:00
local myRank = 0
local ROSTER = {}                      -- { name, rankIndex }
local sent, store = {}, {}

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Chehul" end
  end
  function GetRealmName() return "Normal" end
  function GetNormalizedRealmName() return "Normal" end
  function GetServerTime() return NOW end
  function GetTime() return 1 end
  function IsInGuild() return true end
  function GetGuildInfo() return "Ashen Vow", "Rank", myRank end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2], 40 end end
  C_Timer = { After = function() end, NewTicker = function() end }
  Enum = { SendAddonMessageResult = {} }
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  LibStub("GuildOS-LibSerialize").Serialize = function(_, t) store[#store + 1] = t; return tostring(#store) end
  LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) return store[tonumber(s)] ~= nil, store[tonumber(s)] end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/SyncService.lua")
  dofile(ADDON .. "/Modules/Founding.lua")
  GuildOS.CommSystem = { SendMessage = function(_, _, payload) sent[#sent + 1] = store[tonumber(payload)] end }
  GuildOS.db = { members = {}, settings = {}, firstSeen = {} }
  function GuildOS:IsOfficer() return myRank <= 1 end
  function GuildOS:IsOfficerByName() return true end
  GuildOS.SyncService:Initialize()
  if GuildOS.Founding then GuildOS.Founding:Initialize() end
  return GuildOS
end

check(load("anniversary").Founding == nil, "no founding on TBC Anniversary")

local G = load("forever")
local F = G.Founding
local key = function(n) return G:GetPlayerKey(n) end

-- ── A founding day ──────────────────────────────────────────────────────
check(F.ValidDay(LAUNCH, NOW), "launch day is a founding day")
check(not F.ValidDay(LAUNCH - DAY, NOW), "the day before the launch is not")
check(not F.ValidDay(LAUNCH + 3600, NOW), "a founding day starts at 00:00 UTC")
check(not F.ValidDay(NOW - NOW % DAY + DAY, NOW), "tomorrow is not")
check(F.WindowEnd(LAUNCH) == LAUNCH + 15 * DAY - 1, "the window closes at the end of 18 Nov")

-- ── The letter ──────────────────────────────────────────────────────────
check(F:ShouldPrompt(NOW), "the GM of a guild with no founding gets the letter")
F:Later(NOW)
check(not F:ShouldPrompt(NOW + 60), "Later puts it away for a day")
check(F:ShouldPrompt(NOW + DAY), "and it comes back after it")
F:Later(NOW + DAY); F:Later(NOW + 2 * DAY)
check(not F:ShouldPrompt(NOW + 10 * DAY), "after three, it waits in Settings")

-- ── Recording ───────────────────────────────────────────────────────────
myRank = 1
check(not F:Record(LAUNCH), "an officer who is not the GM does not record")
sent = {}
check(F:Suggest(LAUNCH + DAY) and sent[1].dom == "founding" and sent[1].act == "suggest", "an officer suggests")
myRank = 0
G.SyncService:OnEnvelope("Mira Thornwood", LibStub("GuildOS-LibSerialize"):Serialize(
  { v = 2, id = "S1", dom = "founding", act = "suggest", data = { foundedAt = LAUNCH + DAY } }), "GUILD")
local day, source = F:SuggestedDay(NOW)
check(day == LAUNCH + DAY and source == "declared", "the GM's letter offers the suggested day")
check(not F:Record(LAUNCH - DAY), "a day before the launch is refused")
sent = {}
check(F:Record(LAUNCH), "the GM records")
local f = F:Get()
check(f.foundedAt == LAUNCH and f.revision == 1 and f.declaredBy == key("Chehul Costa"), "with the day, a revision and who")
check(sent[1].dom == "founding" and sent[1].act == "set" and sent[1].rev == 1, "and tells the guild")
check(not F:ShouldPrompt(NOW), "no letter once it is recorded")

-- ── From the guild ──────────────────────────────────────────────────────
local function set(rev, foundedAt)
  G.SyncService:OnEnvelope("Mira Thornwood", LibStub("GuildOS-LibSerialize"):Serialize(
    { v = 2, id = "F" .. rev .. foundedAt, dom = "founding", act = "set", rev = rev,
      data = { founding = { foundedAt = foundedAt, revision = rev, source = "declared", declaredBy = "Mira Thornwood-Elsewhere" } } }), "GUILD")
end
set(1, LAUNCH + 2 * DAY)
check(F:Get().foundedAt == LAUNCH, "a revision no higher than mine is ignored")
set(2, LAUNCH + 2 * DAY)
check(F:Get().foundedAt == LAUNCH + 2 * DAY and F:Get().revision == 2, "a higher one wins")
check(F:Get().declaredBy == key("Mira Thornwood"), "with the key in this client's shape")
set(3, LAUNCH - DAY)
check(F:Get().revision == 2, "a founding before the launch is ignored")
G.SyncService:OnEnvelope("Mira Thornwood", LibStub("GuildOS-LibSerialize"):Serialize(
  { v = 2, id = "W1", dom = "founding", act = "set", rev = 9, data = { founding = { foundedAt = LAUNCH, revision = 9 } } }), "WHISPER")
check(F:Get().revision == 2, "nor one whispered")
G.db.founding = nil
F:Record(LAUNCH)

-- ── Who joined, and the founders ────────────────────────────────────────
ROSTER = { { "Chehul Costa", 0 }, { "Mira Thornwood", 3 }, { "Tess Varn", 3 }, { "Orin Vale", 3 }, { "Late Comer", 3 } }
local function claim(sender, joinedAt)
  G.SyncService:OnEnvelope(sender, LibStub("GuildOS-LibSerialize"):Serialize(
    { v = 2, id = "J" .. sender .. joinedAt, dom = "foundingSelf", act = "join", data = { joinedAt = joinedAt, src = "firstSeen" } }), "GUILD")
end
claim("Mira Thornwood", LAUNCH + 3600)
claim("Tess Varn", LAUNCH + 14 * DAY + 80000)      -- 18 Nov, before midnight
claim("Late Comer", LAUNCH + 15 * DAY + 10)        -- 19 Nov
claim("Orin Vale", NOW + 10 * DAY)                 -- in the future: not believed
G.db.firstSeen[key("Orin Vale")] = LAUNCH + 5 * DAY
G.db.firstSeen[key("Chehul Costa")] = LAUNCH + 9 * DAY  -- the GM, seen late: a founder anyway
check(F:JoinedAtOf(key("Mira Thornwood")) == LAUNCH + 3600, "a member's own claim is kept")
check(F:JoinedAtOf(key("Orin Vale")) == nil, "a claim in the future is not")
local founders = F:Founders()
check(founders[key("Chehul Costa")], "the GM is always a founder")
check(founders[key("Mira Thornwood")] and founders[key("Tess Varn")], "whoever joined inside the 14 days is one")
check(founders[key("Orin Vale")] and founders[key("Orin Vale")].src == "firstSeen", "a member with no claim, by when this client first saw them")
check(not founders[key("Late Comer")], "the day after the window, nobody is")

local out = F:ForExport()
check(out.foundedAt == LAUNCH and out.revision >= 1 and #out.founders == 4 and type(out.manual) == "table", "the export carries it, founders as a list")

print(("founding: %d checks passed"):format(checks))
