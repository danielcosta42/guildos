-- What the guild earned and its setup, in the game (issues #216, #217; guildos-web #245, #244), run
-- against the real Core, Compat, Utils, CompanionExport, CompanionImport, Achievements, Activation and
-- Digest under a stubbed client. The block is built here through LibDeflate as the site writes it:
-- tools/guild-block.lua reads the site's own string.
--
-- What this holds: the addon judges no rule and shows what the block says; with no block the tab has
-- nothing and the digest stays as it was; the setup card is for the GM and officers, reads two steps by
-- itself and three from the site, hides for 30 days for who clicked, reminds every 3 days at most, and
-- celebrates once. Only on Forever.
--
--   luajit -e 'ADDON="."' tools/guild-achievements.lua
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
local NOW = 1793750400 + 20 * DAY
local myRank = 0
local printed = {}

local function load(game)
  printed, myRank = {}, 0
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
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
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return "Ashen Vow", "Rank", myRank end
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
  dofile(ADDON .. "/Modules/Activation.lua")
  dofile(ADDON .. "/Modules/Achievements.lua")
  dofile(ADDON .. "/Modules/Digest.lua")
  function GuildOS:IsOnGuildDB() return true end
  GuildOS.db = { settings = { companion = true, officerMaxRank = 1 }, members = {}, firstSeen = {}, digest = { lastSeen = NOW - DAY } }
  GuildOSDB = {}
  GuildOSInbox = nil
  GuildOSInboxAck = nil
  GuildOS.Digest:Initialize()
  return GuildOS
end

-- A GOSGILD1 as the site writes it, from JSON: this is what the addon reads.
local function inbox(json)
  local LD = LibStub("LibDeflate")
  GuildOSInbox = { "GOSGILD1:" .. LD:EncodeForPrint(LD:CompressDeflate(json)) }
  GuildOSInboxAck = { at = NOW - 3600, members = 1 }
  GuildOS.CompanionImport._blockRaw = nil
end

local function has(lines, text)
  for _, l in ipairs(lines) do if l:find(text, 1, true) then return true end end
  return false
end

local HEAD = '{"fmt":"GOSGILD1","v":1,"guild":"Ashen Vow","realm":null,"at":' .. (NOW - 3600)

-- ── Only on Forever ─────────────────────────────────────────────────────
check(load("anniversary").Achievements == nil and GuildOS.Activation == nil, "no achievements nor activation on TBC")

local G = load("forever")
local A, S, D = G.Achievements, G.Activation, G.Digest
S:Initialize()

-- ── Nothing from the site ───────────────────────────────────────────────
check(A:Renown() == nil, "no block: no renown")
check(#A:Earned() == 0 and #A:Next() == 0, "and nothing to list")
check(#D:Build(NOW - DAY) == 1 and has(D:Build(NOW - DAY), "Set up Guild OS"), "the digest: only the officers' reminder")

-- ── Achievements ────────────────────────────────────────────────────────
inbox(HEAD .. [[,"achievements":{"renown":135,"level":2,"earned":[
  {"id":"level.first_60","title":"First to Sixty","at":]] .. (NOW - 60) .. [[,"key":"Mira Thornwood"},
  {"id":"founding.charter","title":"Charter |cffff0000Signed","at":]] .. (NOW - 10 * DAY) .. [[},
  {"title":7}
],"next":[{"title":"Ready for Ten I","current":8,"target":10},{"title":"x"}]}}]])
local level, points = A:Renown()
check(level == 2 and points == 135, "the renown as the site says it")
local earned = A:Earned()
check(#earned == 2, "a row the site sent badly is dropped")
check(not earned[2].title:find("|", 1, true), "no colour reaches a line of ours")
check(A:Of(G:LocalMemberKey("Mira Thornwood"))[1] == "First to Sixty", "a member's own, for the tooltip")
check(#A:Of(G:LocalMemberKey("Nobody Here")) == 0, "and nobody else's")
check(#A:Next() == 1 and A:Next()[1].target == 10, "the nearest, with a bad row out")
check(not has(D:Build(NOW - DAY), "Achievement:"), "the first time, everything the guild already had is no news")
A:MarkSeen()
inbox(HEAD .. [[,"feed":[{"id":"f1","type":"achievement.earned","at":]] .. (NOW - 30) .. [[,"text":"Achievement: Rare One"}],"achievements":{"renown":135,"level":2,"earned":[
  {"id":"level.first_60","title":"First to Sixty","at":]] .. (NOW - 60) .. [[,"key":"Mira Thornwood"},
  {"id":"founding.charter","title":"Charter Signed","at":]] .. (NOW - 10 * DAY) .. [[},
  {"id":"craft.late","title":"Told Late","at":]] .. (NOW - 5 * DAY) .. [[},
  {"id":"rare.one","title":"Rare One","at":]] .. (NOW - 30) .. [[}
],"next":[{"title":"Ready for Ten I","current":8,"target":10}]}}]])
local lines = D:Build(NOW - DAY)
check(has(lines, "Achievement: Told Late"), "new to this client, whatever the fact's own date")
check(not has(lines, "Achievement: Charter"), "what was said is not said again")
check(not has(lines, "Achievement: First to Sixty"), "nor what was already there")
local rare = 0
for _, l in ipairs(lines) do if l:find("Rare One", 1, true) then rare = rare + 1 end end
check(rare == 1, "a rare one the site's feed tells is told once")
check(has(lines, "Next: Ready for Ten I (8/10)"), "and the nearest, beside the news")
A:MarkSeen()
GuildOS.db.digest.feedSeen.f1 = NOW
GuildOS.db.activation.hiddenUntil = NOW + DAY
check(#D:Build(NOW - DAY) == 0, "with nothing else to say the nearest does not open the digest")
GuildOS.db.activation.hiddenUntil = nil

GuildOS.db.settings.modules = { achievements = false }
check(A:Renown() == nil, "switched off: nothing")
GuildOS.db.settings.modules = nil

GuildOS.db.settings.companion = false
check(A:Renown() == nil, "the companion off: nothing")
GuildOS.db.settings.companion = true

-- ── Activation ──────────────────────────────────────────────────────────
inbox(HEAD .. [[,"activation":{"steps":{"publish":true,"bot":true,"account":false,"members":false,"run":false},"members":2}}]])
local r = S:Read(NOW)
check(r.done == 2 and r.steps.bot and not r.steps.run, "the steps the site knows")
check(r.staleDays == nil, "said an hour ago")

GuildOS.db.members = {}
for i = 1, 5 do GuildOS.db.members["M" .. i] = { lastUpdate = NOW - DAY } end
check(S:Read(NOW).steps.members, "the client counts who runs the addon by itself")
GuildOS.db.members.M1.lastUpdate = NOW - 31 * DAY
check(not S:Read(NOW).steps.members, "and only the last 30 days")

GuildOSInbox, GuildOSInboxAck = nil, nil
GuildOS.CompanionImport._blockRaw = nil
GuildOSDB.__companionAt = NOW - DAY
r = S:Read(NOW)
check(r.steps.publish and not r.steps.bot and r.done == 1, "with no inbox, what the client knows")

inbox(HEAD .. [[,"activation":{"steps":{"publish":true,"bot":false,"account":false,"members":false,"run":false},"members":0}}]])
GuildOSInboxAck = { at = NOW - 4 * DAY, members = 1 }
check(S:Read(NOW).staleDays == 4, "an inbox over three days old says so")

check(S:ShouldShow(NOW), "the GM sees it")
myRank = 1
check(S:ShouldShow(NOW), "an officer too")
myRank = 5
check(not S:ShouldShow(NOW), "a member does not")
check(S:GetDigestLine(NOW) == nil, "nor the reminder")
myRank = 0

S:Hide(NOW)
check(not S:ShouldShow(NOW + 29 * DAY) and S:GetDigestLine(NOW) == nil, "hidden for who clicked, card and reminder")
check(S:ShouldShow(NOW + 30 * DAY), "and back after 30 days")
GuildOS.db.activation.hiddenUntil = nil

check(S:GetDigestLine(NOW) ~= nil, "the reminder")
D.Show = function() end
GuildOS.db.digest.lastSeen = NOW - DAY
D:ShowOnLogin()
check(GuildOS.db.activation.remindedAt == NOW, "the login digest counts it")
check(S:GetDigestLine(NOW + 2 * DAY) == nil, "at most every three days")
check(S:GetDigestLine(NOW + 3 * DAY) ~= nil, "and then again")

inbox(HEAD .. [[,"activation":{"steps":{"publish":true,"bot":true,"account":true,"members":true,"run":true},"members":9,"activatedAt":]] .. NOW .. [[}}]])
check(S:Read(NOW).activated and not S:ShouldShow(NOW), "activated: no card")
S:Celebrate()
check(#printed == 1 and printed[1]:find("set up for your guild", 1, true), "celebrated")
S:Celebrate()
check(#printed == 1, "once")
GuildOS.db.settings.companion = false
check(S:Read(NOW).activated and not S:ShouldShow(NOW), "the companion off does not un-activate the guild")
GuildOS.db.settings.companion = true

print(("guild-achievements: %d checks passed"):format(checks))
