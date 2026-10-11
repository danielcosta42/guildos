-- The Discord's cores into the game (issue #135; guildos-web specs/041), run against the real
-- Core, Compat, Utils, CoreManager, CompanionExport and CompanionImport under a stubbed client,
-- with a GOSCORE1 the site's own encoder made: tools/cores-fixture.txt, from
-- packages/goscomp/test/make-cores.ts in guildos-web. Regenerate it there if the format changes.
--
-- The Discord owns who is on a core: whoever came from it is added and, once they leave it,
-- removed; whoever an officer put on a core here is never touched by the import.
--
--   luajit -e 'ADDON="."' tools/core-import.lua
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
local GUILD = "Nucleo BR"
local function load(game)
  printed, sent, handlers, GUILD = {}, {}, {}, "Nucleo BR"
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
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return GUILD, "Rank", 1 end
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
  -- SoftResSystem owns the JSON decoder the import reuses; lift just the decoder, as
  -- tools/roster-import.lua does.
  local softres = io.open(ADDON .. "/Modules/SoftResSystem.lua"):read("*a")
  local decoderSrc = assert(softres:match("(local function JsonDecode.-\nend\n)"), "no JsonDecode in SoftResSystem.lua")
  GuildOS.JsonDecode = assert(loadstring(decoderSrc .. "\nreturn JsonDecode"))()
  dofile(ADDON .. "/Modules/CompanionExport.lua")
  dofile(ADDON .. "/Modules/CompanionImport.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  GuildOS.SyncService = {
    On = function(_, domain, fn) handlers[domain] = fn end,
    Publish = function(_, domain, act, data) sent[#sent + 1] = { domain = domain, act = act, data = data } end,
  }
  GuildOS.IsOfficerByName = function() return true end
  return GuildOS.CoreManager
end
local function said(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return m end end
end

-- ── A core's name reduces as the site's slugOf does ─────────────────────
-- The expectations are slugOf's own answers (apps/web/lib/federation-cores.ts).
local CM = load("anniversary")
for name, slug in pairs({
  ["Núcleo Alfa!"] = "nucleo-alfa",
  ["  Ação & Reação "] = "acao-reacao",
  ["ÁÉÍÓÚ ç ñ"] = "aeiou-c-n",
  ["Ünïcödé"] = "unicode",
  ["ÀÂÃÄÅ ÈÊË ÌÎÏ ÒÔÕÖ ÙÛÜ Ýÿ"] = "aaaaa-eee-iii-oooo-uuu-yy",
  ["Øyvind"] = "yvind",
  [string.rep("a", 45)] = string.rep("a", 40),
  [string.rep("a", 39) .. " b"] = string.rep("a", 39) .. "-",
  ["Alfa"] = "alfa",
  ["Šampioni"] = "sampioni",
  ["Łódź"] = "odz",
  ["İstanbul"] = "istanbul",
  ["Ærøskøbing"] = "r-sk-bing",
}) do
  check(CM.Slug(name) == slug, ("slug of %q is %q, got %q"):format(name, slug, CM.Slug(name)))
end

for _, game in ipairs({ "anniversary", "forever" }) do
  local function G(what) return game .. ": " .. what end

  -- ── The fixture lands ─────────────────────────────────────────────────
  CM = load(game)
  local K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
  CM:Create("Nucleo Alfa")
  local alfa = GuildOS.db.cores["Nucleo Alfa"].members
  alfa[K("Ana")] = { name = "Ana", class = "PRIEST", role = "rdps", note = "x" }   -- put here by an officer
  alfa[K("Carla")] = { name = "Carla", class = "MAGE", role = "rdps", note = "" }  -- a pug, never on the Discord
  alfa[K("Velho")] = { name = "Velho", class = "MAGE", role = "rdps", note = "", src = "discord" }  -- left it
  GuildOSInbox = { FIXTURE }
  CM:Initialize()

  check(GuildOS.db.cores["Núcleo Alfa"] == nil, G("the game's core whose name reduces to the tag is the one, no second core"))
  check(alfa[K("Ana")].role == "rdps" and alfa[K("Ana")].note == "x" and alfa[K("Ana")].src == nil,
    G("somebody already on the core stays as the officer left them"))
  check(alfa[K("Bruno")] and alfa[K("Bruno")].src == "discord" and alfa[K("Bruno")].class == "ROGUE"
    and alfa[K("Bruno")].role == CM:RoleFor("ROGUE"), G("a newcomer from the Discord joins, with the class's role when the site names none"))
  check(alfa[K("Carla")] ~= nil, G("whoever an officer put here stays"))
  check(alfa[K("Velho")] == nil, G("whoever came from the Discord and left it goes"))
  check(CM:GetRaidSize("Nucleo Alfa") == (game == "forever" and 20 or 25), G("the Discord's size, as this game has it"))

  local reused = GuildOS.db.cores["alfa-2"]
  check(reused and GuildOS.db.cores["Alfa"] == nil, G("a reused name's core is made under its tag, so its nights count on the site"))
  check(reused.members[K("Ana")].role == "healer" and reused.members[K("Ana")].src == "discord",
    G("on a core of her own, Ana comes as the healer the site says"))
  check(CM:GetRaidSize("alfa-2") == 10, G("and the 10's size"))
  check(CM:IsFromDiscord("Nucleo Alfa") and CM:IsFromDiscord("alfa-2"), G("both are the Discord's now"))

  local line = said("Cores from Discord:")
  check(line and line:find("Nucleo Alfa +1 -1", 1, true) and line:find("alfa-2 +1 -0", 1, true)
    and line:find("2 on Discord with no confirmed character on the site.", 1, true), G("one line says what changed: " .. tostring(line)))
  check(#sent == 0, G("nothing goes out at login, before the guild rank is known"))
  CM:SendDiscordChanges()   -- what OFFICER_START runs once the rank says officer
  table.sort(sent, function(a, b) return a.data.coreName < b.data.coreName end)
  check(#sent == 2 and sent[1].domain == "core.roster" and sent[1].act == "discord"
    and sent[1].data.coreName == "Nucleo Alfa" and sent[2].data.coreName == "alfa-2",
    G("each core that changed goes to the other officers"))
  local d = sent[1].data
  check(#d.add == 1 and d.add[1].key == "Bruno-Firemaw" and #d.remove == 1 and d.remove[1] == K("Velho") and d.members == nil
    and d.tag == "nucleo-alfa", G("as the change alone, never the whole roster, and whose it is"))
  sent = {}
  CM:SendDiscordChanges()
  check(#sent == 0, G("and once"))

  -- ── Another officer's client takes the change, and only the change ────
  local mine = GuildOS.db.cores["Nucleo Alfa"].members
  mine[K("Pug")] = { name = "Pug", class = "MAGE", role = "rdps", note = "" }   -- added here while away
  mine[K("Velho")] = { name = "Velho", class = "MAGE", role = "rdps", note = "", src = "discord" }
  mine[K("Carla")].src = nil
  mine[K("Bruno")] = nil
  GuildOS.db.cores["Nucleo Alfa"].discordTag = nil
  handlers["core.roster"]({ act = "discord", data = { coreName = "Nucleo Alfa", add = d.add,
    remove = { K("Velho"), K("Pug") }, size = 20, tag = "nucleo-alfa" } }, "Officer-Firemaw")
  check(CM:IsFromDiscord("Nucleo Alfa"), G("the receiver learns the core is the Discord's"))
  check(mine[K("Pug")] and mine[K("Bruno")] and mine[K("Bruno")].src == "discord" and mine[K("Velho")] == nil,
    G("the receiver adds and removes the Discord's people, and keeps its own pug"))
  handlers["core.roster"]({ act = "update", data = { coreName = "Nucleo Alfa", members = { [K("Solo")] = { name = "Solo" } } } },
    "Officer-Firemaw")
  check(mine ~= GuildOS.db.cores["Nucleo Alfa"].members and GuildOS.db.cores["Nucleo Alfa"].members[K("Solo")],
    G("an edit by hand still sends the whole roster, as before"))

  -- ── Again: nothing new, nothing said ──────────────────────────────────
  CM = load(game)
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  printed = {}
  GuildOS.State.discordCores = nil
  CM:ImportInbox()
  check(not said("Cores from Discord:") and GuildOS.State.discordCores == nil, G("an unchanged Discord says nothing and sends nothing"))
  alfa = GuildOS.db.cores["Núcleo Alfa"].members

  -- ── The Discord owns its people; an officer's edit keeps where they came from ──
  alfa[K("Bruno")] = nil
  CM:ImportInbox()
  check(alfa[K("Bruno")] and alfa[K("Bruno")].src == "discord", G("taken off only in the game, back at the next import"))
  CM:AddMember(K("Bruno"), { name = "Bruno", class = "ROGUE", role = "rdps" }, "Núcleo Alfa")
  check(alfa[K("Bruno")].role == "rdps" and alfa[K("Bruno")].src == "discord", G("a role changed here keeps the record the Discord's"))

  -- ── A core the Discord no longer sends goes back to the officers ──────
  CM = load(game)
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  GuildOS.State.discordCores = nil
  local bruno = K("Bruno")
  CM:ImportFromSite({ guild = "Nucleo BR", unlinked = 0, cores = { { tag = "alfa-2", name = "Alfa", size = 10,
    members = { { key = "Ana-Firemaw", name = "Ana", class = "PRIEST", slot = "healer" } } } } })
  check(not CM:IsFromDiscord("Núcleo Alfa") and CM:IsFromDiscord("alfa-2"), G("closed on the Discord: the officers' again"))
  check(GuildOS.db.cores["Núcleo Alfa"].members[bruno], G("as it stands, people and all"))
  CM:ImportFromSite({ guild = "Nucleo BR", unlinked = 0, cores = {} })
  check(not CM:IsFromDiscord("alfa-2"), G("a federation switched off gives every core back"))
  printed, sent = {}, {}
  GuildOS.State.discordCores = nil
  CM:ImportFromSite({ guild = "Nucleo BR", unlinked = 0, cores = {} })
  check(next(GuildOS.db.cores["alfa-2"].members) ~= nil, G("and nothing more happens to them"))
  -- The officers who were not importing hear of it too.
  CM = load(game)
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  GuildOS.State.discordCores = CM:ImportFromSite({ guild = "Nucleo BR", unlinked = 0, cores = {} })
  sent = {}
  CM:SendDiscordChanges()
  check(#sent == 2 and sent[1].data.tag == false and sent[2].data.tag == false, G("the release goes out, core by core"))
  GuildOS.db.cores["alfa-2"].discordTag = "alfa-2"
  for _, s in ipairs(sent) do handlers["core.roster"]({ act = s.act, data = s.data }, "Officer-Firemaw") end
  check(not CM:IsFromDiscord("alfa-2"), G("and gives the core back on their clients"))
  -- The core already the Discord's stays the one, though another reduces to the tag by a closer name.
  CM = load(game)
  local pkg = { guild = "Nucleo BR", unlinked = 0, cores = { { tag = "nucleo-alfa", name = "Núcleo Alfa", size = 20,
    members = { { key = "Ana-Firemaw", name = "Ana", class = "PRIEST" } } } } }
  CM:Create("nucleo alfa")
  CM:ImportFromSite(pkg)
  CM:Create("Núcleo Alfa")
  pkg.cores[1].members[2] = { key = "Bia-Firemaw", name = "Bia", class = "MAGE" }
  CM:ImportFromSite(pkg)
  check(CM:IsFromDiscord("nucleo alfa") and GuildOS.db.cores["nucleo alfa"].members[K("Bia")]
    and not CM:IsFromDiscord("Núcleo Alfa") and next(GuildOS.db.cores["Núcleo Alfa"].members) == nil,
    G("the linked core keeps the Discord's people; a namesake made later is the officers'"))
  GuildOS.db.cores["Núcleo Alfa"].discordTag = "nucleo-alfa"
  CM:ImportFromSite(pkg)
  check(CM:IsFromDiscord("nucleo alfa") ~= CM:IsFromDiscord("Núcleo Alfa"), G("one core per tag: a second is given back"))

  -- A release never makes a core this client deleted.
  CM:InitSync()
  handlers["core.roster"]({ act = "discord", data = { coreName = "Apagado", tag = false } }, "Officer-Firemaw")
  check(GuildOS.db.cores["Apagado"] == nil, G("a release for a core that is not here makes nothing"))

  -- Through the inbox: given back, sent on, and nothing said in chat.
  CM = load(game)
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  printed = {}
  local LD = LibStub("LibDeflate")
  GuildOSInbox = { "GOSCORE1:" .. LD:EncodeForPrint(LD:CompressDeflate(
    '{"fmt":"GOSCORE1","v":1,"guild":"Nucleo BR","realm":null,"cores":[],"unlinked":0}')) }
  CM:ImportInbox()
  check(not CM:IsFromDiscord("alfa-2") and #GuildOS.State.discordCores == 2 and not said("Cores from Discord:"),
    G("an empty package gives every core back, quietly, and keeps the change to send"))

  -- ── Not this guild, or the companion off: nothing ─────────────────────
  CM = load(game)
  GUILD = "Outra Guilda"
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(next(GuildOS.db.cores) == nil and not said("Cores from Discord:"), G("another guild's cores never land in this one's"))
  CM = load(game)
  GuildOS.db.settings.companion = false
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(next(GuildOS.db.cores) == nil, G("with the companion off, nothing is imported"))
  CM = load(game)
  CM:ImportFromSite({ guild = "Nucleo BR", realm = "Outro Reino", unlinked = 0, cores = { { tag = "x", name = "x", size = 10,
    members = { { key = "Ana-Firemaw", name = "Ana" } } } } })
  if game == "anniversary" then
    check(next(GuildOS.db.cores) == nil, G("a namesake guild on another realm is not this one"))
  else
    check(GuildOS.db.cores["x"], G("Forever has no realms that set guilds apart"))
  end

  -- ── Damaged, absent, or beside the raids ──────────────────────────────
  CM = load(game)
  GuildOSInbox = { "GOSCORE1:" .. FIXTURE:sub(20, 60) }
  CM:Initialize()
  check(next(GuildOS.db.cores) == nil, G("a damaged string imports nothing, and breaks nothing"))
  GuildOSInbox = nil
  CM:ImportInbox()
  check(next(GuildOS.db.cores) == nil, G("no inbox, nothing"))
  GuildOSInbox = { FIXTURE }
  check(GuildOS.CompanionImport:ConsumeInbox() == false, G("the raid roster reader passes over the cores"))

  -- ── Two of the game's cores reduce to the tag: the one named as on the Discord ──
  CM = load(game)
  CM:Create("ALFA"); CM:Create("alfa")
  CM:ImportFromSite({ guild = "Nucleo BR", cores = { { tag = "alfa", name = "alfa", size = 10, unlinked = 0,
    members = { { key = "Ana-Firemaw", name = "Ana", class = "PRIEST" } } } } })
  check(GuildOS.db.cores["alfa"].members[K("Ana")] and not GuildOS.db.cores["ALFA"].members[K("Ana")],
    G("the core named as on the Discord, of two that reduce alike"))
  CM:ImportFromSite({ guild = "Nucleo BR", cores = { { tag = "alfa", name = "alfa", size = 10, unlinked = 0,
    members = { { key = "Bia-Firemaw", name = "Bia", class = "NOT_A_CLASS", slot = "nope" } } } } })
  local bia = GuildOS.db.cores["alfa"].members[K("Bia")]
  check(bia and bia.class == "WARRIOR" and bia.role == CM:RoleFor("WARRIOR"), G("a class or role the game does not know is not taken"))

  -- ── Forever's key is the whole name; the site sends nothing else there ──
  if game == "forever" then
    CM:ImportFromSite({ guild = "Nucleo BR", cores = { { tag = "alfa", name = "alfa", size = 20,
      members = { { key = "Chehul Costa", name = "Chehul Costa", class = "DRUID", slot = "healer" } } } } })
    local key = GuildOS:GetPlayerKey("Chehul Costa")
    check(key and GuildOS.db.cores["alfa"].members[key] and GuildOS.db.cores["alfa"].members[key].role == "healer",
      G("a first name and surname is the member this client keys by that name"))
  end
end

print(("core-import: %d checks passed"):format(checks))
