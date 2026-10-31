-- The guild's block into the game (issue #215; guildos-web #259), run against the real Core, Compat,
-- Utils, CompanionExport, CompanionImport, Founding, Milestones and Digest under a stubbed client,
-- with a GOSGILD1 the site's own encoder made: tools/guild-fixture.txt, from
-- packages/goscomp/test/make-guild.ts in guildos-web. Regenerate it there if the format changes.
--
-- What this holds: a block is read only for this guild, under a week old, with the companion on, and
-- is shown and never run; the digest says five lines at most, each once, with no colour or link, and
-- with nothing from the site it stays as it was; an event the site tells is not told twice; the
-- site's founding is kept by the same order as the GM's, and only the GM's client tells the guild.
--
--   luajit -e 'ADDON="."' tools/guild-block.lua
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

local FIXTURE = io.open(ADDON .. "/tools/guild-fixture.txt", "rb"):read("*a")

local DAY = 86400
local LAUNCH = 1793750400
local NOW = LAUNCH + 20 * DAY
local myRank = 0
local GUILD = "Ashen Vow"
local published = {}

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Chehul", "Costa" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Normal" end
function GetNormalizedRealmName() return "Normal" end
function GetServerTime() return NOW end
function GetTime() return 1 end
date = os.date
time = os.time
function IsInGuild() return true end
function GetGuildInfo() return GUILD, "Rank", myRank end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/Founding.lua")
dofile(ADDON .. "/Modules/Milestones.lua")
dofile(ADDON .. "/Modules/Digest.lua")
function GuildOS:IsOfficer() return myRank <= 1 end
function GuildOS:IsOnGuildDB() return true end
GuildOS.SyncService = {
  On = function() end,
  Publish = function(_, domain, act, data) published[#published + 1] = { domain = domain, act = act, data = data } end,
}

local Import, Digest, Founding, Milestones = GuildOS.CompanionImport, GuildOS.Digest, GuildOS.Founding, GuildOS.Milestones

local function fresh()
  GuildOS.db = { settings = { companion = true }, members = {}, firstSeen = {}, digest = { lastSeen = LAUNCH } }
  Digest:Initialize()
  Milestones:Initialize()
  Founding:Initialize()
  published, NOW, myRank, GUILD = {}, LAUNCH + 20 * DAY, 0, "Ashen Vow"
  GuildOSInbox = { FIXTURE }
end

local function has(lines, text)
  for _, l in ipairs(lines) do if l:find(text, 1, true) then return true end end
  return false
end

-- ── The block ───────────────────────────────────────────────────────────
fresh()
local b = Import:GuildBlock()
check(b and b.guild == "Ashen Vow" and #b.feed == 6, "the site's own string reads")

GUILD = "Outra Guilda"
check(Import:GuildBlock() == nil, "another guild's block is ignored")
GUILD = "ashen VOW"
check(Import:GuildBlock() ~= nil, "capitals aside, as the cores")
GUILD = "Ashen Vow"

NOW = b.at + 7 * DAY + 1
check(Import:GuildBlock() == nil, "a block over a week old is a companion that stopped")
NOW = LAUNCH + 20 * DAY

GuildOS.db.settings.companion = false
check(Import:GuildBlock() == nil, "the companion off: nothing")
GuildOS.db.settings.companion = true

GuildOSInbox = { "GOSGILD1:notareal(block)" }
check(Import:GuildBlock() == nil, "a damaged one is dropped")
GuildOSInbox = nil
check(Import:GuildBlock() == nil, "no inbox: nothing")

-- An addon reading the block as a roster finds no roster in it, and the raids beside it stand.
GuildOSInbox = { FIXTURE }
check(Import:ConsumeInbox() == false, "the roster reader passes over it")

-- ── The digest ──────────────────────────────────────────────────────────
fresh()
local lines = Digest:Build(LAUNCH)
check(has(lines, "From guildos.me"), "the section")
check(has(lines, "reached 60 — the 1st in the guild"), "with the site's line")
check(has(lines, "The guild turned 1 month old"), "five lines")
check(not has(lines, "The guild was founded"), "and no sixth")
local bars = 0
for _, l in ipairs(lines) do
  if not l:find("From guildos.me", 1, true) and l:find("|", 1, true) then bars = bars + 1 end
end
check(bars == 0, "and no bar in any of them: without it nothing opens a colour, a link or a texture")

Digest.Show = function() end   -- the popup is the UI's; what it says is Build's
Digest:ShowOnLogin()
check(GuildOS.db.digest.feedSeen.ev1 == NOW, "the login digest marks what it showed")
Digest.shownThisSession = nil
local again = Digest:Build(LAUNCH)
check(not has(again, "reached 60 — the 1st in the guild"), "and does not say it again")
check(has(again, "The guild was founded"), "the one left out comes next")

GuildOS.db.digest.feedSeen.old = NOW - 15 * DAY
Digest:MarkFeedSeen(NOW)
check(GuildOS.db.digest.feedSeen.old == nil, "what is too old to come back is forgotten")

fresh()
GuildOSInbox = nil
check(not has(Digest:Build(LAUNCH), "From guildos.me"), "with no companion the digest is as it was")

-- ── Not said twice ──────────────────────────────────────────────────────
fresh()
local mira = GuildOS:LocalMemberKey("Mira Thornwood")
Milestones:Record("ding", mira, "Mira", "60")
Milestones:Record("ding", GuildOS:LocalMemberKey("Tess Varn"), "Tess", "60")
local both = Digest:Build(LAUNCH)
check(not has(both, "Mira reached level 60!"), "a ding the site tells is not told twice")
check(has(both, "Tess reached level 60!"), "one it does not tell is")
GuildOSInbox = nil
check(has(Digest:Build(LAUNCH), "Mira reached level 60!"), "and with no block it is told")

-- ── The founding ────────────────────────────────────────────────────────
fresh()
GuildOS.db.founding = { foundedAt = LAUNCH, source = "declared", recordedAt = LAUNCH, windowDays = 14, manual = {}, revision = 1 }
Founding:FromSite()
local f = GuildOS.db.founding
check(f.foundedAt == LAUNCH + DAY and f.source == "site" and f.revision == 5, "a newer founding from the site is kept")
check(f.manual[mira] and f.manual[mira].reason == "guildos.me", "with who was added by hand, and no reason from the site")
check(#published == 1 and published[1].domain == "founding" and published[1].act == "set", "the GM's client tells the guild")

fresh()
GuildOS.db.founding = { foundedAt = LAUNCH, source = "declared", recordedAt = LAUNCH, windowDays = 14, revision = 1,
                        manual = { [mira] = { by = "Me", reason = "Founded it with us", at = LAUNCH } } }
Founding:FromSite()
check(GuildOS.db.founding.manual[mira].reason == "Founded it with us", "a reason held here stays")

fresh()
myRank = 1
GuildOS.db.founding = { foundedAt = LAUNCH, source = "declared", recordedAt = LAUNCH, windowDays = 14, manual = {}, revision = 1 }
Founding:FromSite()
check(GuildOS.db.founding.revision == 5, "an officer's client keeps it too")
check(#published == 0, "and says nothing: the founding travels only from the GM")

fresh()
GuildOS.db.founding = { foundedAt = LAUNCH + 2 * DAY, source = "declared", recordedAt = LAUNCH + 19 * DAY + 60, windowDays = 14, manual = {}, revision = 1 }
Founding:FromSite()
check(GuildOS.db.founding.foundedAt == LAUNCH + 2 * DAY, "a newer record here stands, whatever the revision")
check(#published == 0, "and nothing is told")

fresh()
GuildOS.db.founding = { foundedAt = LAUNCH + DAY, source = "site", recordedAt = LAUNCH + 19 * DAY, windowDays = 14, manual = {}, revision = 5 }
Founding:FromSite()
check(#published == 0, "the same record is nothing to tell: no echo between site and game")

fresh()
Founding:FromSite()
check(GuildOS.db.founding and GuildOS.db.founding.revision == 5, "a client with none takes it")

-- An event the site tells, Founding does not say again; with no block it does.
fresh()
GuildOS.db.founding = { foundedAt = LAUNCH, recordedAt = LAUNCH, windowDays = 14, manual = {}, revision = 1 }
local since, at = LAUNCH + 14 * DAY, LAUNCH + 16 * DAY
check(table.concat(Founding:GetDigestLines(since, at), "\n"):find("Founding window closed", 1, true), "the closing, with nothing from the site")
check(not table.concat(Founding:GetDigestLines(since, at, { ["founding.closed"] = true }), "\n"):find("closed", 1, true), "not when the site tells it")

-- ── The first look at a guild is nobody's arrival (issue #170) ─────────────
fresh()
local ROSTER = {}
GetNumGuildMembers = function() return #ROSTER end
GetGuildRosterInfo = function(i) return ROSTER[i] end
local function newcomers() return has(Digest:Build(LAUNCH), "new member(s)") end
ROSTER = { "Ana", "Bob", "Cid" }
local whole = GetGuildRosterInfo
GetGuildRosterInfo = function(i) if i < 3 then return ROSTER[i] end end
GuildOS:RecordFirstSeen()
check(next(GuildOS.db.firstSeen) == nil, "half a roster is no first look")
GetGuildRosterInfo = whole
GuildOS:RecordFirstSeen()
check(next(GuildOS.db.firstSeen) ~= nil and not newcomers(), "a first install does not list the guild as new members")
NOW = NOW + 60
ROSTER[4] = "Dan"
GuildOS:RecordFirstSeen()
check(newcomers(), "whoever joins after it is new")
GetNumGuildMembers, GetGuildRosterInfo = function() return 0 end, function() end

print(("guild-block: %d checks passed"):format(checks))
