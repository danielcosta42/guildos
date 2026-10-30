-- The founding (issue #208), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/SyncService.lua and Modules/Founding.lua.
--
-- What this holds: only a day between the launch and today is a founding day; only the GM records
-- it, an officer suggests; the GM's newest record wins on every client; a join date is taken only
-- from the member it is about, never before the launch; the founding members are the GM, whoever
-- joined inside the 14 days, and nobody after; nothing is written outside the guild's own db; the
-- letter comes at most three times, a day apart, and never before the launch.
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
local onGuildDB = true
local ROSTER = { { "Chehul Costa", 0 } }   -- { name, rankIndex }
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
  date = os.date
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
  function GuildOS:IsOnGuildDB() return onGuildDB end
  GuildOS.SyncService:Initialize()
  if GuildOS.Founding then GuildOS.Founding:Initialize() end
  return GuildOS
end

check(load("anniversary").Founding == nil, "no founding on TBC Anniversary")

local G = load("forever")
local F = G.Founding
local key = function(n) return G:GetPlayerKey(n) end
local function from(sender, act, data, rev)
  G.SyncService:OnEnvelope(sender, LibStub("GuildOS-LibSerialize"):Serialize(
    { v = 2, id = "E" .. #store, dom = act == "join" and "foundingSelf" or "founding", act = act, rev = rev, data = data }), "GUILD")
end

-- ── A founding day ──────────────────────────────────────────────────────
check(F.ValidDay(LAUNCH, NOW), "launch day is a founding day")
check(not F.ValidDay(LAUNCH - DAY, NOW), "the day before the launch is not")
check(not F.ValidDay(LAUNCH + 3600, NOW), "a founding day starts at 00:00 UTC")
check(not F.ValidDay(NOW - NOW % DAY + DAY, NOW), "tomorrow is not")
check(F.WindowEnd(LAUNCH) == LAUNCH + 15 * DAY - 1, "the window closes at the end of 18 Nov")
check(F:Step(LAUNCH, -1, NOW) == LAUNCH and F:Step(LAUNCH, 1, NOW) == LAUNCH + DAY, "the arrows stay on founding days")

-- ── The letter ──────────────────────────────────────────────────────────
check(not F:ShouldPrompt(LAUNCH - 3600), "no letter before the launch")
check(F:ShouldPrompt(NOW), "the GM of a guild with no founding gets the letter")
F:Later(NOW)
check(not F:ShouldPrompt(NOW + 60), "Later puts it away for a day")
check(F:ShouldPrompt(NOW + DAY), "and it comes back after it")
F:Later(NOW + DAY); F:Later(NOW + 2 * DAY)
check(not F:ShouldPrompt(NOW + 10 * DAY), "after three, it waits in Settings")

-- ── Recording ───────────────────────────────────────────────────────────
onGuildDB = false
check(F:Submit(LAUNCH, "declared") == nil and F:Get() == nil, "nothing is written while the guild's own db is not loaded")
onGuildDB = true
myRank = 1
check(not F:Record(LAUNCH), "an officer who is not the GM does not record")
sent = {}
check(F:Submit(LAUNCH + DAY, "declared") == "suggested" and sent[1].dom == "founding" and sent[1].act == "suggest", "an officer suggests")
sent = {}
F:Publish()
check(#sent == 1 and sent[1].act == "suggest", "and suggests again on the officers' regular sync, until it is recorded")
myRank = 0
G.db.foundingSuggested = nil
from("Mira Thornwood", "suggest", { foundedAt = LAUNCH + DAY })
local day = F:SuggestedDay(NOW)
check(day == LAUNCH + DAY, "the GM's letter offers a suggested day")
check(not F:Record(LAUNCH - DAY), "a day before the launch is refused")
sent = {}
check(F:Submit(LAUNCH, "declared") == "recorded", "the GM records")
local f = F:Get()
check(f.foundedAt == LAUNCH and f.revision == 1 and f.declaredBy == key("Chehul Costa") and f.recordedAt == NOW, "with the day, a revision, who and when")
check(sent[1].dom == "founding" and sent[1].act == "set" and sent[1].rev == 1, "and tells the guild")
sent = {}
F:Publish()
check(#sent == 1 and sent[1].act == "set", "and tells it again on the officers' regular sync")
check(not F:ShouldPrompt(NOW), "no letter once it is recorded")

-- ── From the guild: only the GM's ───────────────────────────────────────
local function set(sender, rev, foundedAt, recordedAt, manual)
  from(sender, "set", { founding = { foundedAt = foundedAt, revision = rev, recordedAt = recordedAt, source = "declared",
    declaredBy = sender .. "-Elsewhere", manual = manual } }, rev)
end
set("Mira Thornwood", 5, LAUNCH + 2 * DAY, NOW + 10)
check(F:Get().foundedAt == LAUNCH, "an officer who is not the GM sets nothing")
ROSTER = { { "Mira Thornwood", 0 }, { "Chehul Costa", 1 } }   -- the guild changed hands
myRank = 1
set("Mira Thornwood", 1, LAUNCH + 2 * DAY, NOW - 10)
check(F:Get().foundedAt == LAUNCH, "an older record loses")
set("Mira Thornwood", 1, LAUNCH + 2 * DAY, NOW + 10, { ["Tess Varn-Elsewhere"] = { by = "Mira Thornwood-Elsewhere", reason = "traveling", at = NOW } })
check(F:Get().foundedAt == LAUNCH + 2 * DAY and F:Get().revision == 1, "the new GM's newer record wins, revision 1 again or not")
check(F:Get().declaredBy == key("Mira Thornwood"), "with the key in this client's shape")
check(F:Get().manual[key("Tess Varn")] and F:Get().manual[key("Tess Varn")].reason == "traveling", "and the manual additions in it too")
set("Mira Thornwood", 2, LAUNCH - DAY, NOW + 20)
check(F:Get().foundedAt == LAUNCH + 2 * DAY, "a founding before the launch is ignored")
set("Mira Thornwood", 2e9, LAUNCH + 3 * DAY, NOW + 20)
check(F:Get().foundedAt == LAUNCH + 2 * DAY, "a revision past any guildos.me takes is ignored")
G.SyncService:OnEnvelope("Mira Thornwood", LibStub("GuildOS-LibSerialize"):Serialize(
  { v = 2, id = "W1", dom = "founding", act = "set", rev = 9, data = { founding = { foundedAt = LAUNCH, revision = 9, recordedAt = NOW + 30 } } }), "WHISPER")
check(F:Get().foundedAt == LAUNCH + 2 * DAY, "nor one whispered")
G.db.founding = nil
ROSTER = { { "Chehul Costa", 0 } }
myRank = 0
F:Record(LAUNCH)

-- ── Who joined, and the founders ────────────────────────────────────────
ROSTER = { { "Chehul Costa", 0 }, { "Mira Thornwood", 3 }, { "Tess Varn", 3 }, { "Orin Vale", 3 }, { "Late Comer", 3 }, { "Early Bird", 3 } }
local function claim(sender, joinedAt) from(sender, "join", { joinedAt = joinedAt, src = "club" }) end
claim("Mira Thornwood", LAUNCH + 3600)
claim("Late Comer", LAUNCH + 15 * DAY + 10)        -- 19 Nov
claim("Orin Vale", NOW + 10 * DAY)                 -- in the future: not believed
claim("Early Bird", 1)                             -- before the launch: not believed
G.db.firstSeen[key("Orin Vale")] = LAUNCH + 5 * DAY
G.db.firstSeen[key("Chehul Costa")] = LAUNCH + 9 * DAY  -- the GM, seen late: a founder anyway
claim("Tess Varn", LAUNCH + 20 * DAY)                  -- installed late: a later claim
G.db.firstSeen[key("Tess Varn")] = LAUNCH + 2 * DAY    -- this client saw them early
check(F:JoinedAtOf(key("Mira Thornwood")) == LAUNCH + 3600, "a member's own claim is kept")
check(F:JoinedAtOf(key("Orin Vale")) == nil and F:JoinedAtOf(key("Early Bird")) == nil, "a claim in the future, or before the launch, is not")
check(G.db.foundingJoins[key("Mira Thornwood")].src == "firstSeen", "and nobody claims the game's own date before a probe finds it")
local founders = F:Founders()
check(founders[key("Chehul Costa")], "the GM is always a founder")
check(founders[key("Mira Thornwood")], "whoever joined inside the 14 days is one")
check(founders[key("Tess Varn")] and founders[key("Tess Varn")].joinedAt == LAUNCH + 2 * DAY, "the earlier of a claim and this client's sighting")
check(founders[key("Orin Vale")] and founders[key("Orin Vale")].src == "firstSeen", "a member with no claim, by when this client first saw them")
check(not founders[key("Late Comer")], "the day after the window, nobody is")
check(not founders[key("Early Bird")], "nor anybody with no date at all")

local out = F:ForExport()
check(out.foundedAt == LAUNCH and out.revision >= 1 and #out.founders == 4 and type(out.manual) == "table", "the export carries it, founders as a list")

-- ── Months, the digest and the badge (issue #209) ───────────────────────
check(F.AddMonths(LAUNCH, 1) == LAUNCH + 30 * DAY, "a month after 4 Nov is 4 Dec")
check(F.AddMonths(LAUNCH, 12) == LAUNCH + 365 * DAY, "a year after is 4 Nov 2027")
local jan31 = LAUNCH + 88 * DAY                       -- 31 Jan 2027
check(os.date("!%m-%d", jan31) == "01-31", "the fixture's 31 Jan")
check(os.date("!%m-%d", F.AddMonths(jan31, 1)) == "02-28", "a day past the month's end is its last")

local function digest(since, now) return table.concat(F:GetDigestLines(since, now), "\n") end
local inWindow = digest(LAUNCH, LAUNCH + 5 * DAY)
check(inWindow:find("Mira Thornwood joined as a founding member", 1, true), "who joined as a founder since the last login")
check(not inWindow:find("Chehul Costa joined", 1, true), "never myself")
check(inWindow:find("Founding window: 10 days left", 1, true), "the days the window has left: " .. inWindow)
local closed = digest(LAUNCH + 14 * DAY, LAUNCH + 16 * DAY)
check(closed:find("Founding window closed: 4 founding members", 1, true), "the window's closing, once: " .. closed)
check(not digest(LAUNCH + 16 * DAY, LAUNCH + 17 * DAY):find("closed", 1, true), "and not again")
local month = F.AddMonths(LAUNCH, 1)
check(digest(month - DAY, month + 3600):find("Ashen Vow turned 1 month(s) old", 1, true), "an anniversary")
check(not digest(month + 3600, month + 7200):find("turned", 1, true), "said once")
local year = F.AddMonths(LAUNCH, 12)
check(digest(year - DAY, year + 3600):find("Ashen Vow turned 1 year(s) old", 1, true), "a year is a year, not 12 months")

check(F.BADGE:find("|T", 1, true) == 1, "the badge is a texture")

-- A founder who leaves loses the badge, and coming back does not bring it back (issue #209).
local present = {}
for _, r in ipairs(ROSTER) do present[key(r[1])] = true end
present[key("Mira Thornwood")] = nil
F:Departed(present)
check(not F:IsFounder(key("Mira Thornwood")), "a founder who left has no badge")
check(G.db.foundingJoins[key("Mira Thornwood")] == nil, "and their claim is dropped")
claim("Mira Thornwood", LAUNCH + 3600)                    -- back, their client says the old date again
check(not F:IsFounder(key("Mira Thornwood")), "back in the guild: still no badge")
G.db.founding.manual[key("Mira Thornwood")] = { by = key("Chehul Costa"), reason = "came back", at = NOW }
F:Forget()
check(F:IsFounder(key("Mira Thornwood")), "the GM's manual addition brings it back")
check(F:IsFounder(key("Chehul Costa")), "and the GM is untouched")
check(F:IsFounder(key("Mira Thornwood")) and not F:IsFounder(key("Late Comer")), "the badge goes to founders only")

print(("founding: %d checks passed"):format(checks))
