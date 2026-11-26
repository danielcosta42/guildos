-- The guild's block into the game (issue #215; guildos-web #259), run against the real Core, Compat,
-- Utils, CompanionExport, CompanionImport, Founding, Milestones and Digest under a stubbed client,
-- with a GOSGILD1 the site's own encoder made: tools/guild-fixture.txt, from
-- packages/goscomp/test/make-guild.ts in guildos-web. Regenerate it there if the format changes.
--
-- What this holds: a block is read only for this guild, under a week old, with the companion on, and
-- is shown and never run; the digest says five lines at most, each once, with no colour or link, and
-- with nothing from the site it stays as it was; an event the site tells is not told twice; the
-- site's founding is kept by the same order as the GM's, and only the GM's client tells the guild.
-- The alliance's GOSALLY1 (tools/ally-fixture.txt, with tools/ally-guild-fixture.txt's GOSGILD1 code): read
-- only for this guild, this game, under a week old, held to its caps (16 guilds, 1000 members, 2000 recipes,
-- 30 raids, 256 KiB, the inflated size), every field checked; in memory only; the directory maps recipe spell
-- ids to the items "who crafts this?" asks by, and it counts only for the site's code in force.
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
-- The recruiting strings (specs/071), made by the site's own encoders: a GOSGILD1 with a recruitAd, and the
-- public GOSRECR1 list for Forever and for retail. See tools/recruit-beacon.lua.
local GUILD_AD = io.open(ADDON .. "/tools/guild-ad-fixture.txt", "rb"):read("*a")
local RECRUIT = io.open(ADDON .. "/tools/recruit-fixture.txt", "rb"):read("*a")
local RECRUIT_RETAIL = io.open(ADDON .. "/tools/recruit-retail-fixture.txt", "rb"):read("*a")

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
dofile(ADDON .. "/Modules/GuildFinder.lua")
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

-- ── The recruiting ad and the public list (specs/071) ─────────────────────
fresh()
GuildOSInbox = { GUILD_AD }
local own = Import:OwnRecruitAd()
check(own and own.n == "Ashen Vow" and own.p == "We raid Tuesdays" and own.v == NOW - DAY, "the block carries the guild's own ad")
check(table.concat(own.ct, "+") == "Chehul Costa+Mira Thornwood" and own.u == "ashen-vow-normal-us", "with its contacts and slug")
check(own.heard == nil and own.verified == nil, "and it is nobody's heard-of or verified")
check(Import:GuildBlock() ~= nil, "the same block still reads for the rest")
local ownX = own.x
NOW = ownX - 1
check(Import:OwnRecruitAd() ~= nil, "the ad lives until its x")
NOW = ownX
check(Import:OwnRecruitAd() == nil, "and is nil from x on, with the block still good for a week")
check(Import:GuildBlock() ~= nil, "the block itself is")
NOW = LAUNCH + 20 * DAY
GUILD = "Outra Guilda"
check(Import:OwnRecruitAd() == nil, "another guild's ad is not mine")
GUILD = "Ashen Vow"
GuildOSInbox = { FIXTURE }
check(Import:OwnRecruitAd() == nil, "a block with no ad has none")
GuildOS.db.settings.companion = false
GuildOSInbox = { GUILD_AD }
check(Import:OwnRecruitAd() == nil, "with the companion off there is no block, so no ad")
GuildOS.db.settings.companion = true

-- The list: public, so it needs no companion switch.
GuildOSInbox = { RECRUIT }
local dir = Import:RecruitDirectory()
check(dir and dir.fmt == "GOSRECR1" and dir.game == "FOREVER" and #dir.ads == 3, "the site's own list reads")
check(dir.ads[1].n == "Ordem do Crepúsculo" and dir.ads[1].w == "normal:us", "ads and all")
GuildOS.db.settings.companion = false
check(Import:RecruitDirectory() ~= nil, "it is read with the companion off: it is public data")
GuildOS.db.settings.companion = true
check(Import:RecruitDirectory() == dir, "decoded once per load")
NOW = dir.at + 3 * DAY
check(Import:RecruitDirectory() ~= nil, "three days old still stands")
NOW = dir.at + 3 * DAY + 1
check(Import:RecruitDirectory() == nil, "older than three days is nil")
NOW = LAUNCH + 20 * DAY
GuildOSInbox = { RECRUIT_RETAIL }
check(Import:RecruitDirectory() == nil, "a list for the other game is nil: a client folder can hold what another install left")
GuildOSInbox = { RECRUIT_RETAIL, RECRUIT }
check(Import:RecruitDirectory() ~= nil and Import:RecruitDirectory().game == "FOREVER", "and this game's list is found beside it")
GuildOS.Client.isRetail = true
GuildOSInbox = { RECRUIT }
check(Import:RecruitDirectory() == nil, "and a Forever list read on retail is nil too")
GuildOSInbox = { RECRUIT, RECRUIT_RETAIL }
check(Import:RecruitDirectory() ~= nil and Import:RecruitDirectory().game == "RETAIL", "with retail's own list found beside it")
GuildOS.Client.isRetail = false
GuildOSInbox = { "GOSRECR1:notareal(list)" }
check(Import:RecruitDirectory() == nil, "a damaged one is dropped")
GuildOSInbox = { FIXTURE }
check(Import:RecruitDirectory() == nil, "a block is not a list")
GuildOSInbox = nil
check(Import:RecruitDirectory() == nil, "no inbox: nothing")

-- Everything that reads the inbox passes over a GOSRECR1 and still finds its own.
fresh()
GuildOSInbox = { RECRUIT }
check(Import:ConsumeInbox() == false and GuildOS.db.companionRoster == nil, "the roster reader passes over the list")
check(Import:GuildBlock() == nil and Import:CoresFromInbox() == nil, "so do the block and the cores")
GuildOSInbox = { RECRUIT, FIXTURE, GUILD_AD }
check(Import:GuildBlock() ~= nil, "the block is found behind it")
check(Import:CoresFromInbox() == nil, "no cores in there")
Import:ConsumeInbox()
check(GuildOS.db.companionRoster == nil and Import._webRaids == nil, "and no raid is made of it")
Import:CalendarFromInbox()
check(true, "the calendar reader has nothing to do with it")

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

-- ── The alliance's blocks: GOSGILD1 `alliance` and GOSALLY1 (alianca.md §3.2; the site's specs/123) ──────────
-- tools/ally-fixture.txt and tools/ally-guild-fixture.txt are made by the site's own encoders (encodeGosally,
-- encodeGosgild in guildos-web packages/goscomp) from this payload: "Ashen Vow" (Forever, realm null) in "Pacto do
-- Sul" [PACTO] v3 with "Iron Pact" (Mira Thornwood, TANK, recipes 2149 2153 7418 999999; Olaf Stone, alt of Mira,
-- recipe 2385) and "Silver Hand" (Lia Moon, HEALER); raids "Molten Core" (Iron Pact, at LAUNCH+21d, 31 of 40, led by
-- Mira) and "Onyxia" (Silver Hand, LAUNCH+20d+2h, 12 of 40); built at LAUNCH+20d-1h; the code GOS=PACTO:AbCdE12345.
local ALLY = io.open(ADDON .. "/tools/ally-fixture.txt", "rb"):read("*a")
local ALLY_GILD = io.open(ADDON .. "/tools/ally-guild-fixture.txt", "rb"):read("*a")
local LD = LibStub("LibDeflate")
local function pack(fmt, t)
  return fmt .. ":" .. LD:EncodeForPrint(LD:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
fresh()
GuildOSInbox = { ALLY_GILD, ALLY }
local ab = Import:AllianceBlock()
check(ab and ab.guild == "Ashen Vow" and ab.alliance.tag == "PACTO" and ab.alliance.version == 3
  and ab.alliance.name == "Pacto do Sul" and #ab.guilds == 3, "the site's own GOSALLY1 reads")
check(ab.guilds[1].self and #ab.guilds[1].members == 0 and #ab.guilds[2].members == 2, "our own guild carries nobody")
check(ab.raids[1].title == "Onyxia" and ab.raids[2].title == "Molten Core", "the raids, soonest first")
check(Import:AllianceBlock() == ab, "decoded once per load")
check(Import:GuildBlock().alliance.code == "GOS=PACTO:AbCdE12345", "the GOSGILD1 beside it carries the code")
GUILD = "Outra Guilda"
check(Import:AllianceBlock() == nil, "another guild's GOSALLY1 is ignored")
GUILD = "ashen VOW"
check(Import:AllianceBlock() ~= nil, "capitals aside")
GUILD = "Ashen Vow"
NOW = ab.at + 7 * DAY + 1
check(Import:AllianceBlock() == nil, "over a week old is a companion that stopped")
NOW = LAUNCH + 20 * DAY
GuildOS.db.settings.companion = false
check(Import:AllianceBlock() == nil, "the companion off: nothing")
GuildOS.db.settings.companion = true
local base = { fmt = "GOSALLY1", v = 1, guild = "Ashen Vow", at = NOW - 3600,
               alliance = { name = "Pacto do Sul", tag = "PACTO", version = 3 }, guilds = {}, raids = {} }
local function variant(extra)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(extra) do t[k] = v end
  return t
end
GuildOSInbox = { pack("GOSALLY1", variant({ realm = "Firemaw" })) }
check(Import:AllianceBlock() == nil, "on WoW: Forever a block naming a realm is another game's, and ignored")
GuildOSInbox = { pack("GOSALLY1", variant({})) }
check(Import:AllianceBlock() ~= nil, "and this game's, naming none, reads")
GuildOSInbox = { pack("GOSALLY1", variant({ v = 2 })) }
check(Import:AllianceBlock() == nil, "a v2 is a breaking change: not read")
GuildOSInbox = { (pack("GOSALLY1", variant({ fmt = "GOSGILD1" }))) }
check(Import:AllianceBlock() == nil, "a block whose fmt is another's is not one")
GuildOSInbox = { "GOSALLY1:notareal(block)" }
check(Import:AllianceBlock() == nil, "a damaged one is dropped")
GuildOSInbox = { "GOSALLY1:" .. string.rep("A", Import.ALLY_MAX + 1) }
check(Import:AllianceBlock() == nil, "a body over 256 KiB is refused before it is decoded")
GuildOSInbox = { "GOSALLY1:abc|cff$%" }
check(Import:AllianceBlock() == nil, "a body outside the print alphabet is refused")
local keepJson = Import.ALLY_JSON_MAX
Import.ALLY_JSON_MAX = 200
GuildOSInbox = { pack("GOSALLY1", variant({ guilds = { { name = "Iron Pact", members = {
  { key = "X", name = string.rep("x", 40), class = "MAGE", level = 1 },
  { key = "Y", name = string.rep("y", 40), class = "MAGE", level = 1 },
  { key = "Z", name = string.rep("z", 40), class = "MAGE", level = 1 } } } } })) }
check(Import:AllianceBlock() == nil, "a body that inflates past its cap is refused before it is parsed")
Import.ALLY_JSON_MAX = keepJson
-- Review 3: the cap stops the inflating itself. A 2 MB run deflates to a few kilobytes; read with a 100 KB cap it is
-- refused by LibDeflate:DecompressDeflateLimited before the whole of it is ever built.
local run = string.rep(" ", 2000000)
local bomb = LD:CompressDeflate('{"fmt":"GOSALLY1","pad":"' .. run .. '"}')
check(#bomb < 20000, "a 2 MB run deflates to a few kilobytes (" .. #bomb .. ")")
local res, why = LD:DecompressDeflateLimited(bomb, 100000)
check(res == nil and why == -100, "inflating stops once the output passes the cap")
check(LD:DecompressDeflateLimited(bomb, 3000000) == LD:DecompressDeflate(bomb), "under the cap it is DecompressDeflate's own")
for _, size in ipairs({ 0, 1, 32767, 32768, 65536, 98304, 98305 }) do
  local text = string.rep("ab", math.floor(size / 2)) .. string.rep("c", size % 2)
  local packed = LD:CompressDeflate(text)
  check(LD:DecompressDeflateLimited(packed, size) == text and LD:DecompressDeflateLimited(packed, size + 1) == text,
    "exactly at its cap the text comes back whole (" .. size .. ")")
  if size > 0 then check(LD:DecompressDeflateLimited(packed, size - 1) == nil, "one byte over is refused (" .. size .. ")") end
end
local stored = LD:CompressDeflate(string.rep("x", 1), { level = 0 })
check(LD:DecompressDeflateLimited(stored, 10) == "x", "a stored block reads too")
Import.ALLY_JSON_MAX = 100000
GuildOSInbox = { "GOSALLY1:" .. LD:EncodeForPrint(bomb) }
check(Import:AllianceBlock() == nil, "a GOSALLY1 made to inflate a thousandfold is refused while it inflates")
Import.ALLY_JSON_MAX = keepJson
GuildOSInbox = nil
check(Import:AllianceBlock() == nil, "no inbox: nothing")

-- Every field held to the contract, a part that fails passed over alone (pure, ReadAlliance).
local R = Import.ReadAlliance
check(R(variant({ alliance = { name = "Pacto", tag = "pacto", version = 3 } })) == nil, "a tag not of the contract: no block")
check(R(variant({ alliance = { name = "Pacto", tag = "PACTO", version = 0 } })) == nil, "nor a version under 1")
check(R(variant({ alliance = { tag = "PACTO", version = 3 } })) == nil, "nor an alliance with no name")
check(R(variant({ at = 1.5 })) == nil and R(variant({ guild = "A|cffB" })) == nil and R("x") == nil, "nor a broken head")
local many = {}
for i = 1, 20 do many[i] = { name = "G" .. i } end
check(#R(variant({ guilds = many })).guilds == 16, "at most 16 guilds")
local crowd, recipes = {}, {}
for i = 1, 1500 do crowd[i] = { key = "K" .. i, name = "N" .. i, class = "MAGE", level = 60 } end
for i = 1, 3000 do recipes[i] = i end
local hostileMembers = {
  { key = "Ok", name = "Ok", class = "MAGE", level = 60, role = "BOSS", main = "Ok" },
  { key = "Ok", name = "Twin", class = "MAGE", level = 60 },                    -- the same key twice
  { key = "Bar|r", name = "Bar", class = "MAGE", level = 60 },
  { key = string.rep("k", 65), name = "Long", class = "MAGE", level = 60 },
  { key = "Low", name = "Low", class = "mage", level = 60 },
  { key = "Neg", name = "Neg", class = "MAGE", level = -1 },
  { key = "Frac", name = "Frac", class = "MAGE", level = 1.5 },
  { key = "Str", name = "Str", class = "MAGE", level = "60" },
  { key = "Nl", name = "Line\nBreak", class = "MAGE", level = 60 },
  "not a member",
}
local hm = R(variant({ guilds = {
  { name = "Ashen Vow", members = { { key = "Spy", name = "Spy", class = "MAGE", level = 60 } } },   -- ours, not self
  { name = "Crowd", members = crowd, crafters = { { key = "K1", recipes = recipes }, { key = "K2", recipes = { 5, 5, 1.5, -3, "7", 8 } },
                                                  { key = "Nobody", recipes = { 1 } } } },
  { name = "Hostile", members = hostileMembers },
  { name = "crowd", members = {} },                                             -- the same guild again
} }))
check(#hm.guilds == 3 and #hm.guilds[1].members == 0, "our own guild never carries members, self or not; a guild twice is once")
check(#hm.guilds[2].members == 1000, "at most 1000 members a guild")
check(#hm.guilds[2].members[1].spells == 2000, "at most 2000 recipes a crafter")
check(table.concat(hm.guilds[2].members[2].spells, ",") == "5,8", "recipe ids whole, positive and once")
local h = hm.guilds[3].members
check(#h == 1 and h[1].key == "Ok" and h[1].role == nil and h[1].main == nil,
  "a member off the contract is passed over alone; a role not of the three and a main that is themselves go")
local raidsIn = {}
for i = 1, 40 do raidsIn[i] = { id = "r" .. i, guild = "Crowd", title = "R" .. i, startsAt = NOW + i, size = 25, going = 1 } end
raidsIn[1] = { id = "bad id!", guild = "Crowd", title = "x", startsAt = NOW, size = 25, going = 1 }
raidsIn[2] = { id = "mine", guild = "Ashen Vow", title = "x", startsAt = NOW, size = 25, going = 1 }
raidsIn[3] = { id = "ghost", guild = "Nowhere", title = "x", startsAt = NOW, size = 25, going = 1 }
raidsIn[4] = { id = "t", guild = "Crowd", title = "|cffff0000Red|r |Hitem:1|h[x]|h", startsAt = NOW + 4, size = 25, going = 1 }
raidsIn[5] = { id = "f", guild = "Crowd", title = "x", startsAt = NOW + 0.5, size = 25, going = 1 }
local rr = R(variant({ guilds = { { name = "Crowd" } }, raids = raidsIn })).raids
check(#rr == 26 and rr[1].id == "t" and not rr[1].title:find("|", 1, true),
  "at most 30 raids read; a bad id, our own guild's, an unknown guild's, a fractional time are passed over; titles inert")

-- In the game: the site's code drives the alliance, its block fills the directory (AllianceLink, Alliance).
dofile(ADDON .. "/Data/ProfCatalogForever.lua")
dofile(ADDON .. "/Modules/Alliance.lua")
dofile(ADDON .. "/Modules/AllianceLink.lua")
local A, Link = GuildOS.Alliance, GuildOS.AllianceLink
fresh()
GuildOSInbox = { FIXTURE, ALLY }
Link:SyncSite()
check(A:Get() == nil and #A:Directory() == 0, "a GOSALLY1 beside a GOSGILD1 with no alliance is nobody's: no directory")
GuildOSInbox = { ALLY_GILD, ALLY }
Link:SyncSite()
check(A:Get() and A:FromSite() and A:Name() == "Pacto do Sul", "the GOSGILD1's code is the alliance")
local dir = A:Directory()
check(#dir == 2 and dir[1].guild == "Iron Pact" and dir[2].guild == "Silver Hand", "the directory: the allied guilds, never ours")
local mira = dir[1].members[1]
check(mira.name == "Mira Thornwood" and mira.class == "WARRIOR" and mira.level == 60 and mira.role == "TANK",
  "a member with class, level and role")
check(mira.recipes[2302] == "Leatherworking" and mira.recipes[2303] == "Leatherworking" and mira.prof == "Leatherworking",
  "recipe spell ids mapped to the items they make, by the catalog")
local n = 0
for _ in pairs(mira.recipes) do n = n + 1 end
check(n == 2, "an enchant (no item) and an id the catalog does not know make nothing to search by")
check(dir[1].members[2].main == "Mira Thornwood" and dir[1].members[2].recipes[2568] == "Tailoring", "an alt, and their own crafts")
local fc = A:FindCrafters(2302)
check(#fc == 1 and fc[1].name == "Mira Thornwood" and fc[1].guild == "Iron Pact" and fc[1].prof == "Leatherworking"
  and fc[1].class == "WARRIOR" and not fc[1].online, "who crafts this: the allied crafter, offline too")
local orr = A:OpenRaids()
check(#orr == 2 and orr[1].title == "Onyxia" and orr[2].leader == "Mira Thornwood" and orr[2].going == 31 and orr[2].size == 40
  and orr[2].where == "Molten Core", "the open raids, soonest first, with who leads and how many go")
check(A:AsOf() == LAUNCH + 20 * DAY - 3600, "as of when the site built it")
check(A:IsMemberGuild("Silver Hand") and A:Guilds()[1].mine and #A:Guilds() == 3, "the site's guilds are the alliance's")
check(A:MemberInfo("Lia Moon").guild == "Silver Hand", "an allied character is known by guild")
check(next(GuildOS.db.members) == nil and GuildOS.db.recipes == nil, "nothing of it goes into the guild's member DB")
for k in pairs(GuildOS.db) do
  check(not k:find("^ally") or k:find("^allianceLink"), "nor a field of its own in SavedVariables: " .. k)
end
check(GuildOS.db.allianceLinkSite and GuildOS.db.allianceLinkSite.line == "GOS=PACTO:AbCdE12345",
  "only the code the site gave is remembered, for a login before the block reads")
-- TBC Anniversary has no catalog: the guild's own scans map a recipe to its item.
local cat = GuildOS.ProfCatalog
GuildOS.ProfCatalog = nil
GuildOS.db.recipes = { ["Ana"] = { Leatherworking = { { spellId = 2149, itemId = 2302 }, { spellId = 7418 } } } }
local fc2 = A:FindCrafters(2302)
check(#fc2 == 1 and fc2[1].prof == "Leatherworking" and #A:FindCrafters(2303) == 0,
  "without a catalog, what the guild scanned maps the recipe; one nobody scanned finds nobody")
GuildOS.ProfCatalog, GuildOS.db.recipes = cat, nil
-- Another key version (the block is older than the code): not this alliance's.
GuildOS.db.allianceLinkSite.version = 4
check(#A:Directory() == 0 and #A:OpenRaids() == 0, "a GOSALLY1 of another key version is not read")
GuildOS.db.allianceLinkSite.version = 3
-- The guild left: the GOSGILD1 names no alliance any more. The alliance ends, and its directory with it.
GuildOSInbox = { FIXTURE, ALLY }
Link:SyncSite()
check(A:Get() == nil and #A:Directory() == 0 and #A:OpenRaids() == 0, "the guild left: no alliance, no directory, no raids")

print(("guild-block: %d checks passed"):format(checks))
