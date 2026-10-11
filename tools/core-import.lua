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

local printed, sent, timers = {}, {}, {}
local GUILD, RANK = "Nucleo BR", 1
local function load(game)
  printed, sent, timers, GUILD, RANK = {}, {}, {}, "Nucleo BR", 1
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
  function GetGuildInfo() return GUILD, "Rank", RANK end
  function GetNumGuildMembers() return 0 end
  function GetGuildRosterInfo() end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end,
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
    On = function() end,
    Publish = function(_, domain, _, data) sent[#sent + 1] = { domain = domain, core = data.coreName } end,
  }
  return GuildOS.CoreManager
end
local function said(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return m end end
end
local function flush()
  local due = timers
  timers = {}
  for _, fn in ipairs(due) do fn() end
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

  local line = said("Cores from Discord:")
  check(line and line:find("Nucleo Alfa +1 -1", 1, true) and line:find("alfa-2 +1 -0", 1, true)
    and line:find("2 on Discord with no confirmed character on the site.", 1, true), G("one line says what changed: " .. tostring(line)))
  check(#sent == 0 and #timers == 1, G("the officers are told a moment later, not mid-login"))
  flush()
  table.sort(sent, function(a, b) return a.core < b.core end)
  check(#sent == 2 and sent[1].domain == "core.roster" and sent[1].core == "Nucleo Alfa" and sent[2].core == "alfa-2",
    G("each core that changed goes to the other officers"))

  -- ── Again: nothing new, nothing said ──────────────────────────────────
  printed, sent = {}, {}
  CM:ImportInbox()
  check(not said("Cores from Discord:") and #timers == 0, G("an unchanged Discord says nothing and sends nothing"))

  -- ── The Discord owns its people; an officer's edit keeps where they came from ──
  alfa[K("Bruno")] = nil
  CM:ImportInbox()
  check(alfa[K("Bruno")] and alfa[K("Bruno")].src == "discord", G("taken off only in the game, back at the next import"))
  CM:AddMember(K("Bruno"), { name = "Bruno", class = "ROGUE", role = "rdps" }, "Nucleo Alfa")
  check(alfa[K("Bruno")].role == "rdps" and alfa[K("Bruno")].src == "discord", G("a role changed here keeps the record the Discord's"))

  -- ── Not an officer: imported here, sent nowhere ───────────────────────
  CM = load(game)
  RANK = 5
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  check(GuildOS.db.cores["alfa-2"] and #timers == 0, G("a member's client imports for itself and sends nothing"))

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
end

print(("core-import: %d checks passed"):format(checks))
