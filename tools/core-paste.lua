-- The guild's cores by a pasted code (issue #347; guildos-web specs/085): a GOSCORE1 copied from the
-- site goes into the same box as a raid's GOSROST1 and is imported exactly as the inbox's is, run
-- against the real Core, Compat, Utils, CoreManager, CompanionExport and CompanionImport under a
-- stubbed client, with the site's own fixture (tools/cores-fixture.txt).
--
--   * pasted = inbox: the same package lands the same way, one code path;
--   * every refusal says why: the companion off, not an officer, a damaged code, another guild,
--     another realm (or game), older than what this client has;
--   * newest wins by the package's `at`;
--   * whoever pasted sends the lists to the officers online at once.
--
--   luajit -e 'ADDON="."' tools/core-paste.lua
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

local FIXTURE = io.open(ADDON .. "/tools/cores-fixture.txt", "rb"):read("*a")

local printed, sent, handlers = {}, {}, {}
local GUILD, RANK, NOW = "Nucleo BR", 1, 1790000000
local function load(game)
  printed, sent, handlers, GUILD, RANK, NOW = {}, {}, {}, "Nucleo BR", 1, 1790000000
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    function f:Hide() end
    function f:Show() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Lead", "Er" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Leader" end
  end
  function GetRealmName() return "Firemaw" end
  function GetTime() return 1 end
  function GetServerTime() return NOW end
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return GUILD, "Rank", RANK end
  function GetNumGuildMembers() return 0 end
  function GetGuildRosterInfo() end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  C_Timer = { After = function() end,
              NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
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
  GuildOS.db = { settings = { companion = true, officerMaxRank = 1 }, members = {}, altLinks = {}, cores = {},
                 raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
  dofile(ADDON .. "/Libs/LibDeflate.lua")
  dofile(ADDON .. "/Modules/CompanionExport.lua")
  dofile(ADDON .. "/Modules/CompanionImport.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  GuildOS.SyncService = {
    On = function(_, domain, fn) handlers[domain] = fn end,
    Publish = function(_, domain, act, data) sent[#sent + 1] = { domain = domain, act = act, data = data } end,
  }
  GuildOS.IsOfficerByName = function() return true end
  GuildOSInbox, GuildOSInboxAck = nil, nil
  return GuildOS.CoreManager
end
local function said(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return m end end
end
local function code(json)
  local LD = LibStub("LibDeflate")
  return "GOSCORE1:" .. LD:EncodeForPrint(LD:CompressDeflate(json))
end
local function pkg(at, guild, realm, name)
  return code(('{"fmt":"GOSCORE1","v":1,"guild":"%s","realm":%s,"unlinked":0,"at":%d,"cores":[{"tag":"nucleo-alfa",'
    .. '"name":"%s","size":10,"members":[{"key":"Ana-Firemaw","name":"Ana","class":"PRIEST","slot":"healer"}]}]}')
    :format(guild or "Nucleo BR", realm and ('"' .. realm .. '"') or "null", at, name or "Núcleo Alfa"))
end
-- The guild's cores as a string, for comparing two clients' results.
local function snapshot()
  local cores = {}
  for name, c in pairs(GuildOS.db.cores) do
    local members = {}
    for k, m in pairs(c.members or {}) do members[k] = { m.name, m.class, m.role, m.src or "", m.status or "" } end
    cores[name] = { tag = c.discordTag or "", size = c.raidSize or 0, members = members, waiting = c.discordWaiting or {} }
  end
  return GuildOS.Companion.EncodeJson(cores)
end
local Import

for _, game in ipairs({ "anniversary", "forever" }) do
  local function G(what) return game .. ": " .. what end

  -- ── Pasted = inbox: the same package lands the same way ──────────────
  local CM = load(game)
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  local viaInbox = snapshot()
  check(GuildOS.db.cores["Núcleo Alfa"] ~= nil, G("the inbox imports the fixture"))

  CM = load(game)
  Import = GuildOS.CompanionImport
  CM:Initialize()
  local n, err, line = Import:Load("  copied from the site:\n" .. FIXTURE:sub(1, 40) .. "\n" .. FIXTURE:sub(41) .. "  \n")
  check(n == 2 and err == nil and line and line:find("Cores from Discord loaded: 2.", 1, true),
    G("a code pasted into the roster box, with spaces and breaks around and inside it, is the guild's cores: " .. tostring(err or line)))
  check(snapshot() == viaInbox, G("and lands exactly as the inbox's does"))
  check(said("Cores from Discord:"), G("with the same line in chat"))
  check(GuildOS.db.coreLink and GuildOS.db.coreLink.importedAt == 1790000000, G("the import is dated, for the upload's receipt"))
  check(GuildOS.db.cores["Núcleo Alfa"].importedAt == 1790000000, G("and so is each core"))

  -- Whoever pasted sends it on at once: the officer is in the game, the rank is known.
  local lists = 0
  for _, s in ipairs(sent) do
    if s.domain == "core.roster" and s.act == "discordList" then lists = lists + 1 end
  end
  check(lists == 2 and GuildOS.State.discordCores == nil, G("the lists go to the officers online at once, once"))
  -- The other officer receives them as from any inbox import.
  local received = {}
  for _, s in ipairs(sent) do received[#received + 1] = s end
  CM = load(game)
  CM:Initialize()
  for _, s in ipairs(received) do handlers["core.roster"]({ act = s.act, data = s.data }, "Officer-Firemaw") end
  check(GuildOS.db.cores["Núcleo Alfa"] and CM:IsFromDiscord("Núcleo Alfa") and CM:IsFromDiscord("alfa-2"),
    G("an officer online gets the pasted cores through core.roster"))

  -- ── Newest wins by the package's `at` ─────────────────────────────────
  CM = load(game)
  Import = GuildOS.CompanionImport
  CM:Initialize()
  check(Import:Load(pkg(7000, nil, game == "anniversary" and "Firemaw" or nil)) == 1, G("a dated package is taken"))
  check(GuildOS.db.discordAt == 7000, G("and marks how new the guild's lists are"))
  local _, older = Import:Load(pkg(6000, nil, game == "anniversary" and "Firemaw" or nil))
  check(older == "This client already has newer cores from Discord: that code is older.", G("an older one is refused, saying why"))
  check(Import:Load(pkg(8000, nil, game == "anniversary" and "Firemaw" or nil)) == 1 and GuildOS.db.discordAt == 8000,
    G("a newer one wins"))
  check(Import:Load(pkg(8000, nil, game == "anniversary" and "Firemaw" or nil)) == 1, G("the same one again changes nothing, and is no error"))
  -- A package from a site before it dated them, once this client has one the site dated: older.
  local _, undated = Import:Load(code('{"fmt":"GOSCORE1","v":1,"guild":"Nucleo BR","realm":null,"unlinked":0,"cores":[]}'))
  check(undated == "This client already has newer cores from Discord: that code is older.", G("an undated package is older than a dated one"))
  -- Lists from another officer newer than the code: the code is older.
  GuildOS.db.discordAt = 9000
  local _, behind = Import:Load(pkg(8500, nil, game == "anniversary" and "Firemaw" or nil))
  check(behind == "This client already has newer cores from Discord: that code is older.", G("older than another officer's lists"))

  -- ── After "Create cores in game again": what counts is when this client got the package ──
  -- The site stamps `at` with when its cores last changed: a fresh copy of unchanged cores carries the
  -- same `at` as the package before the choice (review of #339).
  local REALM = game == "anniversary" and "Firemaw" or nil
  CM = load(game)
  Import = GuildOS.CompanionImport
  CM:Initialize()
  check(Import:Load(pkg(7000, nil, REALM)) == 1 and CM:IsLinked(), G("pasted, linked"))
  NOW = NOW + 31 * 86400
  check(CM:IsLinkQuiet() and CM:CreateInGameAgain() and not CM:IsLinked(), G("31 days quiet, given back to the game"))
  local releases = {}
  for _, s in ipairs(sent) do if s.act == "discord" then releases[#releases + 1] = s end end
  NOW = NOW + 60
  check(Import:Load(pkg(7000, nil, REALM)) == 1 and CM:IsLinked() and CM:IsFromDiscord("Núcleo Alfa"),
    G("a fresh copy of the same cores, pasted after the choice, links the guild again"))
  check(not CM:IsLinkQuiet() and CM:LinkSeenAt() == NOW, G("as fresh as the paste"))
  -- The inbox: the one the companion wrote before the choice is older; one it writes after is not.
  CM = load(game)
  CM:Initialize()
  CM:ImportPackage(GuildOS.CompanionImport.ReadCores(pkg(7000, nil, REALM)), NOW)
  local choseAt = NOW + 31 * 86400
  NOW = choseAt
  CM:CreateInGameAgain()
  NOW = NOW + 60
  GuildOSInbox, GuildOSInboxAck = { pkg(7000, nil, REALM) }, { at = choseAt - 3600 }
  CM:ImportInbox()
  check(not CM:IsLinked(), G("the inbox written before the choice does not link the guild again"))
  GuildOSInboxAck = { at = NOW }
  CM:ImportInbox()
  check(CM:IsLinked() and CM:LinkSeenAt() == NOW, G("the companion back, writing the same package after it, does"))
  -- Another officer's list: by when that officer got the package (`seenAt`).
  CM = load(game)
  CM:Initialize()
  local base = NOW
  for _, r in ipairs(releases) do handlers["core.roster"]({ act = r.act, data = r.data }, "Officer-Firemaw") end
  local list = { coreName = "Núcleo Alfa", list = {}, tag = "nucleo-alfa", size = 10, at = 7000 }
  NOW = base + 40 * 86400
  list.seenAt = base - 60
  handlers["core.roster"]({ act = "discordList", data = list }, "Officer-Firemaw")
  check(not CM:IsLinked(), G("another officer's list of a package got before the choice is older"))
  list.seenAt = NOW - 10
  handlers["core.roster"]({ act = "discordList", data = list }, "Officer-Firemaw")
  check(CM:IsLinked() and CM:IsFromDiscord("Núcleo Alfa"), G("one got after it links the guild here too"))

  -- ── Freshness: a paste or an inbox read of the SAME package is seen ───
  CM = load(game)
  Import = GuildOS.CompanionImport
  CM:Initialize()
  local t0 = NOW
  Import:Load(pkg(7000, nil, REALM))
  NOW = t0 + 29 * 86400
  Import:Load(pkg(7000, nil, REALM))
  NOW = t0 + 31 * 86400
  check(not CM:IsLinkQuiet(), G("in a guild that pastes, the same package pasted again 29 days on is a sight of it"))
  CM = load(game)
  t0 = NOW
  GuildOSInbox, GuildOSInboxAck = { pkg(7000, nil, REALM) }, { at = t0 }
  CM:Initialize()
  NOW = t0 + 29 * 86400
  GuildOSInboxAck = { at = NOW }
  CM:ImportInbox()
  NOW = t0 + 31 * 86400
  check(not CM:IsLinkQuiet(), G("and so is the companion writing the same package again"))

  -- ── Every refusal says why ────────────────────────────────────────────
  CM = load(game)
  Import = GuildOS.CompanionImport
  CM:Initialize()
  RANK = 5
  local _, notOfficer = Import:Load(FIXTURE)
  check(notOfficer == "Only officers import the guild's cores." and next(GuildOS.db.cores) == nil, G("a member is refused, and nothing lands"))
  RANK = 1
  GUILD = "Outra Guilda"
  local _, otherGuild = Import:Load(FIXTURE)
  check(otherGuild == "These cores are for Nucleo BR, not this guild." and next(GuildOS.db.cores) == nil, G("another guild's: " .. tostring(otherGuild)))
  GUILD = "Nucleo BR"
  local _, otherRealm = Import:Load(pkg(7000, nil, "Outro Reino"))
  if game == "anniversary" then
    check(otherRealm == "These cores are for Nucleo BR (Outro Reino): another realm or another game." and next(GuildOS.db.cores) == nil,
      G("a namesake guild on another realm, or another game's: " .. tostring(otherRealm)))
  else
    check(otherRealm == nil, G("Forever has no realms that set guilds apart, as the inbox"))
    GuildOS.db.cores, GuildOS.db.discordAt, GuildOS.db.discordSiteAt, sent = {}, nil, nil, {}
  end
  local _, damaged = Import:Load("GOSCORE1:" .. FIXTURE:sub(20, 60))
  check(damaged == "The cores code is damaged. Copy it again from guildos.me.", G("a damaged code: " .. tostring(damaged)))
  local _, alphabet = Import:Load(FIXTURE:sub(1, 50) .. "!" .. FIXTURE:sub(51))
  check(alphabet == "The cores code is damaged. Copy it again from guildos.me.", G("a character outside the inbox's alphabet"))
  local _, huge = Import:Load("GOSCORE1:" .. string.rep("A", 262145))
  check(huge == "The cores code is damaged. Copy it again from guildos.me.", G("a code longer than any guild's cores"))
  local LD = LibStub("LibDeflate")
  local _, wrongFmt = Import:Load("GOSCORE1:" .. LD:EncodeForPrint(LD:CompressDeflate('{"fmt":"GOSROST1","cores":[]}')))
  check(wrongFmt == "The cores code is damaged. Copy it again from guildos.me.", G("another kind of package under the marker"))
  local _, noCores = Import:Load("GOSCORE1:" .. LD:EncodeForPrint(LD:CompressDeflate('{"fmt":"GOSCORE1","cores":"x"}')))
  check(noCores == "The cores code is damaged. Copy it again from guildos.me.", G("a package whose cores are no list"))
  GuildOS.db.settings.companion = false
  local _, off = Import:Load(FIXTURE)
  check(off == "The web companion is off. Turn it on with /gos web on.", G("the companion module off, as for a raid's roster"))
  GuildOS.db.settings.companion = true
  check(next(GuildOS.db.cores) == nil and #sent == 0, G("no refusal lands anything or sends anything"))

  -- ── The raid's roster in the same box is as before ────────────────────
  local _, roster = Import:Load("GOSROST1:abc")
  check(roster == "The roster string is damaged. Copy it again.", G("a roster string still reads as a roster"))
  check(not Import.IsCoresCode("GOSROST1:xx GOSCORE1:yy"), G("a text with both markers is a roster, as before"))
end

print(("core-paste: %d checks passed"):format(checks))
