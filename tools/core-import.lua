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
  function GetServerTime() return 1790000000 end
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
  check(alfa[K("Ana")].role == "rdps" and alfa[K("Ana")].note == "x" and alfa[K("Ana")].src == "discord",
    G("somebody already on the core and on the Discord is taken over as the Discord's, role and note as the officer left them (#138)"))
  check(table.concat(GuildOS.db.cores["Nucleo Alfa"].discordWaiting or {}, ",") == "Rias,Rozzi (Connor)",
    G("who waits for a character is kept, by their Discord name"))
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
  check(#sent == 2 and sent[1].domain == "core.roster" and sent[1].act == "discordList"
    and sent[1].data.coreName == "Nucleo Alfa" and sent[2].data.coreName == "alfa-2",
    G("each Discord core goes to the other officers, under an action a client from before #138 ignores"))
  local d = sent[1].data
  check(type(d.list) == "table" and #d.list == 2 and d.list[1].key == "Ana-Firemaw" and d.add == nil
    and d.tag == "nucleo-alfa" and table.concat(d.waiting or {}, ",") == "Rias,Rozzi (Connor)",
    G("as the Discord's whole list for it, whose it is, and who waits (#138)"))
  check(d.members == nil, G("never under `members`, which a client from before #135 takes for the whole roster"))
  sent = {}
  CM:SendDiscordChanges()
  check(#sent == 0, G("and once"))

  -- ── Another officer's client: the whole list, whatever it missed (#138) ──
  local mine = GuildOS.db.cores["Nucleo Alfa"].members
  mine[K("Pug")] = { name = "Pug", class = "MAGE", role = "rdps", note = "" }   -- added here while away
  mine[K("Velho")] = { name = "Velho", class = "MAGE", role = "rdps", note = "", src = "discord" }
  mine[K("Ana")].src = nil                                                       -- still the officer's here
  mine[K("Bruno")] = nil                                                         -- a change it missed
  GuildOS.db.cores["Nucleo Alfa"].discordTag = nil
  handlers["core.roster"]({ act = "discordList", data = d }, "Officer-Firemaw")
  check(CM:IsFromDiscord("Nucleo Alfa"), G("the receiver learns the core is the Discord's"))
  check(mine[K("Pug")] and mine[K("Bruno")] and mine[K("Bruno")].src == "discord" and mine[K("Velho")] == nil
    and mine[K("Ana")].src == "discord", G("the receiver converges: the missed one in, the stale one out, the pug kept, Ana taken over"))
  GuildOS.db.cores["Nucleo Alfa"] = nil                                          -- deleted here
  handlers["core.roster"]({ act = "discordList", data = d }, "Officer-Firemaw")
  local back = GuildOS.db.cores["Nucleo Alfa"]
  check(back and back.members[K("Ana")] and back.members[K("Bruno")], G("a core deleted here comes back with its Discord people, not empty"))
  -- The same tag on another core here hands it over, with the Discord's people (#138).
  CM:Create("Duplicado")
  GuildOS.db.cores["Duplicado"].discordTag = "nucleo-alfa"
  GuildOS.db.cores["Duplicado"].members[K("Ana")] = { name = "Ana", class = "PRIEST", role = "healer", note = "", src = "discord" }
  GuildOS.db.cores["Duplicado"].members[K("Pug2")] = { name = "Pug2", class = "MAGE", role = "rdps", note = "" }
  handlers["core.roster"]({ act = "discordList", data = d }, "Officer-Firemaw")
  local dup = GuildOS.db.cores["Duplicado"]
  check(not CM:IsFromDiscord("Duplicado") and dup.members[K("Ana")] == nil and dup.members[K("Pug2")],
    G("a second core holding the tag lets it go, and the Discord's people with it; its pug stays"))
  -- An older list than the newest this client applied is skipped: a stopped companion rolls nobody back.
  local newer = { coreName = "Nucleo Alfa", list = d.list, size = 20, tag = "nucleo-alfa", at = 2000 }
  handlers["core.roster"]({ act = "discordList", data = newer }, "Officer-Firemaw")
  check(GuildOS.db.discordAt == 2000, G("the guild keeps how new the lists it applied are"))
  local older = { coreName = "Nucleo Alfa", list = { { key = "Ana-Firemaw", name = "Ana" } }, size = 20, tag = "nucleo-alfa", at = 1000 }
  handlers["core.roster"]({ act = "discordList", data = older }, "Officer-Firemaw")
  check(GuildOS.db.cores["Nucleo Alfa"].members[K("Bruno")], G("an older list does not take Bruno off"))
  older.coreName = "Core Alfa"
  handlers["core.roster"]({ act = "discordList", data = older }, "Officer-Firemaw")
  check(GuildOS.db.cores["Core Alfa"] == nil and CM:IsFromDiscord("Nucleo Alfa") and GuildOS.db.cores["Nucleo Alfa"].members[K("Bruno")],
    G("nor under another name: the older list takes neither the tag nor anybody"))
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Nucleo Alfa", list = {}, tag = "nucleo-alfa" } },
    "Officer-Firemaw")
  check(GuildOS.db.cores["Nucleo Alfa"].members[K("Bruno")], G("another officer's list that says nothing of when is older than any"))
  handlers["core.roster"]({ act = "discordList", data = { coreName = 5, list = d.list, tag = "x" } }, "Officer-Firemaw")
  check(GuildOS.db.cores[5] == nil, G("a core name that is not text makes nothing"))
  -- A sender's core name that is another Discord core's here: the list goes to the core holding its tag.
  CM:Create("Alpha")
  GuildOS.db.cores["Alpha"].discordTag = "alpha"
  GuildOS.db.cores["Alpha"].members[K("Bia")] = { name = "Bia", class = "MAGE", role = "rdps", note = "", src = "discord" }
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Alpha", list = d.list, size = 20, tag = "nucleo-alfa", at = 3000 } },
    "Officer-Firemaw")
  check(GuildOS.db.cores["Alpha"].discordTag == "alpha" and GuildOS.db.cores["Alpha"].members[K("Bia")]
    and CM:IsFromDiscord("Nucleo Alfa") and GuildOS.db.cores["Nucleo Alfa"].members[K("Bruno")],
    G("Alpha stays Alpha's, Bia on it; Núcleo Alfa's list goes to the core holding it"))
  -- Only a link moves a tag: a newer list under another name lands on the core holding it here.
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Velho", list = d.list, size = 20, tag = "nucleo-alfa", at = 3500 } },
    "Officer-Firemaw")
  check(GuildOS.db.cores["Velho"] == nil and CM:IsFromDiscord("Nucleo Alfa"), G("a list under another name moves nothing"))
  -- An officer's hand link reaches this client, however old the lists it came with: the core of that
  -- name takes the tag and the Discord's people, as they are here.
  local nucleoAlfa = GuildOS.db.cores["Nucleo Alfa"].members
  nucleoAlfa[K("Pug3")] = { name = "Pug3", class = "MAGE", role = "rdps", note = "" }
  nucleoAlfa[K("Bruno")].note = "MT heals"
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Velho", list = { { key = "Ana-Firemaw", name = "Ana" } }, size = 20,
    tag = "nucleo-alfa", at = 1000, linkAt = 1789000000 } }, "Officer-Firemaw")
  local velhoHere = GuildOS.db.cores["Velho"]
  check(CM:IsFromDiscord("Velho") and velhoHere.members[K("Bruno")] and velhoHere.members[K("Bruno")].note == "MT heals"
    and not CM:IsFromDiscord("Nucleo Alfa") and nucleoAlfa[K("Bruno")] == nil and nucleoAlfa[K("Pug3")],
    G("the link moves the tag and the Discord's people, note and all, and not the older list; the pug stays"))
  -- Another officer who missed the link sends its routine list under the old name: the link holds.
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Nucleo Alfa", list = d.list, size = 20, tag = "nucleo-alfa", at = 4000 } },
    "Officer-Firemaw")
  check(CM:IsFromDiscord("Velho") and not CM:IsFromDiscord("Nucleo Alfa") and velhoHere.members[K("Bruno")].note == "MT heals",
    G("a routine list does not undo a link"))
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Nucleo Alfa", list = d.list, tag = "nucleo-alfa", at = 4000,
    linkAt = 1788000000 } }, "Officer-Firemaw")
  check(CM:IsFromDiscord("Velho"), G("nor does an older link"))
  back = velhoHere
  -- An officer still on 0.73.0 sends the change alone, with no time: it lands, on the core holding the
  -- tag here whatever the sender calls it, only while this client has no newer list to judge it by.
  local zed = { coreName = "Nucleo Alfa", add = { { key = "Zed-Firemaw", name = "Zed", class = "MAGE" } }, remove = {}, size = 20, tag = "nucleo-alfa" }
  handlers["core.roster"]({ act = "discord", data = zed }, "Officer-Firemaw")
  check(back.members[K("Zed")] == nil, G("a 0.73.0 change, once this client has a list it can date, is older"))
  GuildOS.db.discordAt = nil
  handlers["core.roster"]({ act = "discord", data = zed }, "Officer-Firemaw")
  check(back.members[K("Zed")] and back.members[K("Zed")].src == "discord" and not CM:IsFromDiscord("Nucleo Alfa"),
    G("the 0.73.0 change still applies before that, to the core holding the tag"))
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Velho", list = d.list, tag = "nucleo-alfa", at = 1e300 } },
    "Officer-Firemaw")
  check(GuildOS.db.discordAt == 1790000000, G("a time past the realm's clock counts as now"))
  -- Closed on the Discord since: an older list that still carries the link does not link the core again.
  handlers["core.roster"]({ act = "discord", data = { coreName = "Velho", tag = false, at = 1790000000 } }, "Officer-Firemaw")
  local stale = { coreName = "Velho", list = d.list, tag = "nucleo-alfa", at = 1000, linkAt = 1789500000 }
  handlers["core.roster"]({ act = "discordList", data = stale }, "Officer-Firemaw")
  check(not CM:IsFromDiscord("Velho"), G("an older list's link to a tag no core here holds links nothing"))
  stale.at = 1790000000
  handlers["core.roster"]({ act = "discordList", data = stale }, "Officer-Firemaw")
  check(CM:IsFromDiscord("Velho"), G("a fresh one does"))
  local hand = GuildOS.db.cores["Nucleo Alfa"].members
  handlers["core.roster"]({ act = "update", data = { coreName = "Nucleo Alfa", members = { [K("Solo")] = { name = "Solo" } } } },
    "Officer-Firemaw")
  check(hand ~= GuildOS.db.cores["Nucleo Alfa"].members and GuildOS.db.cores["Nucleo Alfa"].members[K("Solo")],
    G("an edit by hand still sends the whole roster, as before"))

  -- ── Again: nothing new, nothing said ──────────────────────────────────
  CM = load(game)
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  printed = {}
  GuildOS.State.discordCores = nil
  CM:ImportInbox()
  check(not said("Cores from Discord:") and #(GuildOS.State.discordCores or {}) == 2,
    G("an unchanged Discord says nothing, and still sends its lists so every officer converges"))
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
  -- The site's time for the package, when it sends one, over the companion PC's clock (guildos-web #126).
  CM = load(game)
  GuildOSInboxAck = { at = 5000 }
  GuildOSInbox = { "GOSCORE1:" .. LD:EncodeForPrint(LD:CompressDeflate(
    '{"fmt":"GOSCORE1","v":1,"guild":"Nucleo BR","realm":null,"cores":[],"unlinked":0,"at":7000}')) }
  CM:Initialize()
  check(GuildOS.db.discordAt == 7000, G("the package's own time is the one the guild keeps"))
  -- From the first package the site dates, a PC's clock no longer counts: not the mark it left (a
  -- clock running ahead would hold back every site package), nor an inbox from before the site dated
  -- them (a companion stopped since).
  CM = load(game)
  GuildOS.db.discordAt = 9000
  CM:Initialize()
  GuildOSInbox = { "GOSCORE1:" .. LD:EncodeForPrint(LD:CompressDeflate(
    '{"fmt":"GOSCORE1","v":1,"guild":"Nucleo BR","realm":null,"cores":[{"tag":"x","name":"x","size":10,"members":[]}],"unlinked":0,"at":7000}')) }
  CM:ImportInbox()
  check(CM:IsFromDiscord("x") and GuildOS.db.discordAt == 7000, G("a mark from a PC's clock gives way to the site's first"))
  GuildOSInbox, GuildOSInboxAck = { FIXTURE }, { at = 9500 }
  CM:ImportInbox()
  check(GuildOS.db.cores["nucleo-alfa"] == nil and GuildOS.db.cores["Núcleo Alfa"] == nil and GuildOS.db.discordAt == 7000,
    G("and an inbox the site did not date is from before: nothing of it is taken"))
  GuildOSInboxAck = nil

  -- ── An inbox older than the lists this client has: not imported over them, not sent (#138) ──
  CM = load(game)
  GuildOSInbox = { FIXTURE }
  GuildOSInboxAck = { at = 5000 }
  CM:Initialize()
  local nucleo = GuildOS.db.cores["Núcleo Alfa"]
  check(nucleo and GuildOS.db.discordAt == 5000, G("the guild keeps when the inbox it imported was written"))
  nucleo.members[K("Bruno")] = nil
  GuildOS.db.discordAt = 9000                                                   -- a newer list came from an officer
  printed, GuildOS.State.discordCores = {}, nil
  CM:ImportInbox()
  check(nucleo.members[K("Bruno")] == nil and nucleo.discordTag == "nucleo-alfa", G("the stale inbox puts nothing back"))
  check(GuildOS.State.discordCores == nil and not said("Cores from Discord:"), G("and nothing of it is sent or said"))
  CM:ImportFromSite({ guild = "Nucleo BR", unlinked = 0, cores = {} }, 1000)
  check(CM:IsFromDiscord("Núcleo Alfa") and CM:IsFromDiscord("alfa-2"), G("an older empty package gives no core back"))
  -- A release another officer sends, newer, is kept: the older inbox does not link the core again.
  CM:InitSync()
  handlers["core.roster"]({ act = "discord", data = { coreName = "Núcleo Alfa", tag = false, at = 9500 } }, "Officer-Firemaw")
  check(not CM:IsFromDiscord("Núcleo Alfa") and GuildOS.db.discordAt == 9500, G("the release lands and marks how new it is"))
  CM:ImportInbox()
  check(not CM:IsFromDiscord("Núcleo Alfa"), G("and an older inbox does not take the core back"))
  handlers["core.roster"]({ act = "discord", data = { coreName = "alfa-2", tag = false, at = 9000 } }, "Officer-Firemaw")
  check(CM:IsFromDiscord("alfa-2"), G("an older release is skipped"))
  GuildOSInboxAck = nil

  -- ── Not this guild, or the companion off: nothing, and once it says why (#138) ──
  CM = load(game)
  GUILD = "Outra Guilda"
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(next(GuildOS.db.cores) == nil and not said("Cores from Discord:"), G("another guild's cores never land in this one's"))
  check(said("are for Nucleo BR, not this guild"), G("and the chat says whose they are"))
  printed = {}
  CM:ImportInbox()
  check(not said("are for Nucleo BR"), G("once, not at every login"))
  CM = load(game)
  GuildOS.db.settings.companion = false
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(next(GuildOS.db.cores) == nil, G("with the companion off, nothing is imported"))
  check(said("/gos web on"), G("and the chat says how to turn it on"))
  printed = {}
  CM:ImportInbox()
  check(not said("/gos web on"), G("once"))
  CM = load(game)
  GUILD = "Outra Guilda"
  GuildOS.db.settings.companion = false
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(said("are for Nucleo BR") and not said("/gos web on"), G("an alt in another guild hears whose they are, not to switch anything on"))
  -- The site's spelling of the name, capitals aside, is this guild (#144): the game's "NUCLEO br".
  CM = load(game)
  GUILD = "NUCLEO br"
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(GuildOS.db.cores["Núcleo Alfa"] and not said("are for"), G("a name that differs only in capitals is this guild's"))

  -- ── Deleting the active core leaves no active core to make again, empty (#138) ──
  CM = load(game)
  CM:Create("Ativo")
  GuildOS.db.raidTracker.currentGroupTag = "Ativo"
  CM:Delete("Ativo")
  check(CM:GetActiveName() == "" and GuildOS.db.cores["Ativo"] == nil, G("the active core deleted is no longer active"))
  CM:Create("Outro"); GuildOS.db.raidTracker.currentGroupTag = "Outro"
  CM:Create("Fora"); CM:Delete("Fora")
  check(CM:GetActiveName() == "Outro", G("deleting another core leaves the active one alone"))
  -- Inside a raid: the raid, the announced core and an officer's pick let go of it too.
  local tag = "Raide"
  GuildOS.RaidTracker = { currentGroupTag = tag, currentRaid = { groupTag = tag }, coreAnnounced = tag, gracePick = tag,
    GetCurrentGroup = function(self) return self.currentGroupTag end,
    SetGroupTag = function(self, t) self.currentGroupTag = t end }
  GuildOS.db.raidTracker.corePick = { tag = tag }
  CM:Create(tag); CM:Delete(tag)
  local RT = GuildOS.RaidTracker
  check(RT.currentGroupTag == "" and RT.currentRaid.groupTag == "" and RT.coreAnnounced == nil and RT.gracePick == nil
    and GuildOS.db.raidTracker.corePick == nil, G("a /reload inside the raid does not bring the deleted core back"))
  GuildOS.RaidTracker = nil

  -- ── Linking a game core of another name to a Discord core (#138) ──────
  CM = load(game)
  CM:Create("Core Alfa Velho")
  GuildOS.db.cores["Core Alfa Velho"].members[K("Ana")] = { name = "Ana", class = "PRIEST", role = "healer", note = "" }
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(GuildOS.db.cores["Núcleo Alfa"] and CM:IsFromDiscord("Núcleo Alfa"), G("a name that does not reduce to the tag gets a core of its own"))
  local catalog = CM:DiscordCatalog()
  check(#catalog == 2 and catalog[1].name == "Alfa" and catalog[2].tag == "nucleo-alfa", G("the Discord's cores, as the last import saw them"))
  GuildOS.db.settings.companion = false                                         -- the link needs no inbox
  GuildOS.db.cores["Núcleo Alfa"].members[K("Bruno")].note = "kept"
  CM:LinkDiscord("Core Alfa Velho", "nucleo-alfa")
  GuildOS.db.settings.companion = true
  local velho = GuildOS.db.cores["Core Alfa Velho"]
  check(CM:IsFromDiscord("Core Alfa Velho") and not CM:IsFromDiscord("Núcleo Alfa"), G("linked: the old core is the Discord's, the one made for it no longer"))
  check(velho.members[K("Ana")].src == "discord" and velho.members[K("Bruno")] and velho.members[K("Bruno")].src == "discord"
    and velho.members[K("Bruno")].note == "kept" and CM:GetRaidSize("Core Alfa Velho") == CM:GetRaidSize("Núcleo Alfa"),
    G("and its people come in at once, as they were, the officer's entry taken over, with the core's size"))
  check(next(GuildOS.db.cores["Núcleo Alfa"].members) == nil, G("the core made for it gives the Discord's people back: no two cores with the same people"))
  local told = false
  for _, s in ipairs(sent) do
    if s.act == "discordList" and s.data.coreName == "Core Alfa Velho" and #s.data.list == 2 and s.data.linkAt == 1790000000
      and s.data.list[1].slot then told = true end
  end
  check(told, G("and the other officers hear the link at once"))
  GuildOSInbox = { FIXTURE }
  CM:ImportInbox()
  check(CM:IsFromDiscord("Core Alfa Velho") and not CM:IsFromDiscord("Núcleo Alfa"), G("the next import keeps to the link"))
  check(CM:LinkDiscord("alfa-2", "nucleo-alfa") == false and GuildOS.db.cores["alfa-2"].discordTag == "alfa-2",
    G("a core already another Discord core's is not linked"))
  -- The core holding the tag deleted: the inbox makes it again first, or nothing is linked and the chat says why.
  CM:Create("Sozinho")
  GuildOS.db.cores["Core Alfa Velho"] = nil
  GuildOS.db.settings.companion, printed = false, {}
  check(CM:LinkDiscord("Sozinho", "nucleo-alfa") == false and not CM:IsFromDiscord("Sozinho") and said("/gos web on"),
    G("with no core holding the tag and no inbox to bring it, nothing is linked, and the chat says why"))
  GuildOS.db.settings.companion = true
  check(CM:LinkDiscord("Sozinho", "nucleo-alfa") and CM:IsFromDiscord("Sozinho") and not CM:IsFromDiscord("Núcleo Alfa")
    and GuildOS.db.cores["Sozinho"].members[K("Bruno")], G("with the inbox, the core is made again and its people move to the link"))
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

  -- ── A core linked by hand is never taken by another Discord core of its name (#138) ──
  CM = load(game)
  CM:Create("Alpha")
  GuildOS.db.cores["Alpha"].discordTag = "nucleo-alfa"
  GuildOS.db.cores["Alpha"].members[K("Pug")] = { name = "Pug", class = "MAGE", role = "rdps", note = "pug" }
  CM:ImportFromSite({ guild = "Nucleo BR", unlinked = 0, cores = {
    { tag = "nucleo-alfa", name = "Núcleo Alfa", size = 20, members = { { key = "Ana-Firemaw", name = "Ana" } } },
    { tag = "alpha", name = "Alpha", size = 10, members = { { key = "Bia-Firemaw", name = "Bia" } } } } })
  check(GuildOS.db.cores["Alpha"].discordTag == "nucleo-alfa" and GuildOS.db.cores["Alpha"].members[K("Pug")].note == "pug",
    G("Alpha stays Núcleo Alfa's, its pug and note untouched"))
  check(GuildOS.db.cores["alpha"] and GuildOS.db.cores["alpha"].discordTag == "alpha" and GuildOS.db.cores["alpha"].members[K("Bia")],
    G("and the Discord's Alpha gets a core of its own, under its tag"))

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
