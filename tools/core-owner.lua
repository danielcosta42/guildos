-- Who owns the guild's cores (issue #339; guildos-web specs/085), run against the real Core, Compat,
-- Utils, CoreManager, CompanionExport and CompanionImport under a stubbed client, with the site's
-- fixture (tools/cores-fixture.txt).
--
--   * a guild that imported a GOSCORE1 with cores is linked: the game creates no core (the panel, the
--     raid's tag, a sign-up, another officer's roster), only the import does; a guild that never did
--     creates as always;
--   * a Discord core is the Discord's: renamed there, renamed here on the next import, nights, points
--     and rule along; deleted, renamed, resized only there; its loot rule the site's while the site
--     sends one; a core from before the link stays the officers';
--   * an empty package, or the last Discord core given back, gives creating back; 30 days with no
--     package tell the officer once and offer to create in game again.
--
--   luajit -e 'ADDON="."' tools/core-owner.lua
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
local DAY = 86400

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
  function UnitClass() return "Mage", "MAGE" end
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
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function package(at, cores)
  return { guild = "Nucleo BR", realm = "Firemaw", unlinked = 0, at = at, cores = cores }
end
local function alfa(name, members)
  return { tag = "nucleo-alfa", name = name or "Núcleo Alfa", size = 10,
           members = members or { { key = "Ana-Firemaw", name = "Ana", class = "PRIEST", slot = "healer" } } }
end
local REFUSED = "This guild's cores are created on Discord, with /core criar: the game gets them from guildos.me."

for _, game in ipairs({ "anniversary", "forever" }) do
  local function G(what) return game .. ": " .. what end

  -- ── A guild with no GOSCORE1: everything as before, creating included ──
  local CM = load(game)
  CM:Initialize()
  check(not CM:IsLinked() and CM:LinkSeenAt() == nil, G("a guild that never imported is not linked"))
  check(CM:Create("Raide de Sexta") and GuildOS.db.cores["Raide de Sexta"], G("an officer creates a core"))
  check(CM:GetCore("Pelo Tag") and GuildOS.db.cores["Pelo Tag"], G("the raid's tag makes one, as before"))
  handlers["core.roster"]({ act = "update", data = { coreName = "Do Outro", members = {} } }, "Officer-Firemaw")
  check(GuildOS.db.cores["Do Outro"], G("another officer's roster for a core makes it, as before"))
  check(CM:Rename("Raide de Sexta", "Raide de Sabado") and CM:Delete("Raide de Sabado"), G("renamed and deleted as before"))
  CM:SetRaidSize("Do Outro", 10)
  check(CM:GetRaidSize("Do Outro") == 10, G("and resized"))
  CM:TellQuietLink()
  check(#printed == 0, G("no line about Discord for a guild without it"))

  -- ── Linked by its import ──────────────────────────────────────────────
  CM = load(game)
  CM:Create("Antigo")                                                     -- a core from before the link
  GuildOS.db.cores["Antigo"].members[GuildOS:LocalMemberKey("Rui-Firemaw")] = { name = "Rui", class = "MAGE", role = "rdps", note = "" }
  GuildOSInbox, GuildOSInboxAck = { FIXTURE }, { at = NOW - 3600 }
  CM:Initialize()
  check(CM:IsLinked() and GuildOS.db.coreLink.since == NOW, G("an import with cores links the guild, and says when"))
  check(CM:LinkSeenAt() == NOW - 3600, G("as fresh as the companion's inbox"))
  check(GuildOS.db.coreLink.importedAt == NOW, G("and when this client imported it"))
  local ok, why = CM:Create("Novo")
  check(not ok and why == REFUSED and GuildOS.db.cores["Novo"] == nil, G("creating is refused, saying where: " .. tostring(why)))
  check(CM:GetCore("Tag Solto") == nil and GuildOS.db.cores["Tag Solto"] == nil, G("a raid tag no core has makes none"))
  -- Rewritten (review of #339): this asserted the fallback to the guild's pool, the way another officer's
  -- entries for a core this client lacks landed in the guild's own standings.
  GuildOS.db.points = { standings = {} }
  check(CM:GetPointsDB("Tag Solto") == nil and GuildOS.db.cores["Tag Solto"] == nil,
    G("a core named that this client does not have has no pool, never the guild's"))
  GuildOS.db.raidTracker.currentGroupTag = "Tag Solto"
  check(CM:GetPointsDB() == GuildOS.db.points, G("a raid under a tag no core has is outside a core: the guild's pool"))
  GuildOS.db.raidTracker.currentGroupTag = ""
  check(CM:AddMember("Ana", { name = "Ana" }, "Tag Solto") == false and GuildOS.db.cores["Tag Solto"] == nil, G("nor does adding to it"))
  handlers["core.roster"]({ act = "update", data = { coreName = "Do Outro", members = { X = { name = "X" } } } }, "Officer-Firemaw")
  check(GuildOS.db.cores["Do Outro"] == nil, G("another officer's roster that would make a core is ignored"))
  handlers["core.signup"]({ data = { coreName = "Inventado", info = {} } }, "Fulano-Firemaw")
  check(GuildOS.db.cores["Inventado"] == nil, G("and a sign-up for a core nobody has"))
  handlers["core.roster"]({ act = "update", data = { coreName = "Antigo", members = { Y = { name = "Y" } } } }, "Officer-Firemaw")
  local landed = false
  for _, m in pairs(GuildOS.db.cores["Antigo"].members) do if m.name == "Y" then landed = true end end
  check(landed, G("a roster for a core this client has still lands"))
  -- The Discord's own action still makes the core it needs (a core deleted here comes back).
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Charlie", list = {}, tag = "charlie", size = 10, at = NOW } },
    "Officer-Firemaw")
  check(GuildOS.db.cores["Charlie"] and CM:IsFromDiscord("Charlie"), G("except the discord action: the import's own way in"))

  -- A core from before the link, holding no tag, stays the officers'.
  check(not CM:IsFromDiscord("Antigo"), G("a core from before the link is no Discord core"))
  check(CM:Rename("Antigo", "Antigo 2") and GuildOS.db.cores["Antigo 2"], G("it is renamed"))
  CM:SetRaidSize("Antigo 2", 10)
  check(CM:GetRaidSize("Antigo 2") == 10, G("resized"))
  check(CM:Delete("Antigo 2") and GuildOS.db.cores["Antigo 2"] == nil, G("and deleted, as before"))
  -- The Discord's are not, as before.
  check(not CM:Rename("Núcleo Alfa", "X") and not CM:Delete("Núcleo Alfa"), G("a Discord core is neither renamed nor deleted here"))

  -- ── Another officer's points for a core this client has not got ──────
  dofile(ADDON .. "/Modules/Points.lua")
  local P = GuildOS.Points
  GuildOS.db.points = { mode = "dkp", config = {}, standings = { Guildguy = { current = 500 } }, log = {}, appliedOps = {}, appliedCount = 0 }
  P:Initialize()
  local revs = {}
  GuildOS.SyncService.ShouldApply = function(_, domain, _, rev) return rev > (revs[domain] or 0) end
  GuildOS.SyncService.SetRevision = function(_, domain, _, rev) revs[domain] = rev end
  local ph = handlers["points"]
  ph({ act = "snapshot", rev = 5, data = { core = "Alfa Nova", mode = "dkp", config = {}, standings = { Raider = { current = 42 } } } },
    "Officer-Firemaw")
  check(GuildOS.db.points.standings.Guildguy and count(GuildOS.db.points.standings) == 1,
    G("another officer's snapshot for a core this client lacks leaves the guild's pool alone"))
  local delta = { entries = { { op = "op-1", key = "Guildguy", delta = 25, core = "Alfa Nova", kind = "award", reason = "Boss" } } }
  local cdelta = { entries = { { op = "op-2", key = "Guildguy", delta = 1, core = "Alfa Nova", kind = "counter", acct = "plus",
    rs = "never", per = 0 } } }
  local qset = { entries = { { op = "op-3", acct = "q", seq = 1, core = "Alfa Nova", list = { "Guildguy" } } } }
  ph({ act = "delta", data = delta }, "Officer-Firemaw")
  ph({ act = "cdelta", data = cdelta }, "Officer-Firemaw")
  ph({ act = "qset", data = qset }, "Officer-Firemaw")
  check(GuildOS.db.points.standings.Guildguy.current == 500 and count(GuildOS.db.points.standings) == 1
    and not GuildOS.db.points.appliedOps["op-1"]
    and not GuildOS.db.points.appliedOps["op-2"] and not GuildOS.db.points.appliedOps["op-3"]
    and not (GuildOS.db.points.accounts and next(GuildOS.db.points.accounts)) and not (GuildOS.db.points.queues and next(GuildOS.db.points.queues)),
    G("nor do its points, counters and queues, which stay unapplied"))
  -- Rewritten (review of #339): this delivered the delta a second time once the core had arrived, which
  -- the wire never does (published once, no ack, and SyncService drops an envelope it has seen). Each
  -- envelope is delivered once here: what was skipped is kept, across a /reload, and played when the
  -- core arrives.
  check(GuildOS.db.pointsWaiting and #GuildOS.db.pointsWaiting["Alfa Nova"] == 3, G("the three skipped entries are kept"))
  -- A /reload: SavedVariables are what is left; the modules start again from them.
  do
    local saved = GuildOS.db
    CM = load(game)
    GuildOS.db = saved
    CM:Initialize()
    dofile(ADDON .. "/Modules/Points.lua")
    P = GuildOS.Points
    P:Initialize()
    GuildOS.SyncService.ShouldApply = function(_, domain, _, rev) return rev > (revs[domain] or 0) end
    GuildOS.SyncService.SetRevision = function(_, domain, _, rev) revs[domain] = rev end
    ph = handlers["points"]
  end
  check(#GuildOS.db.pointsWaiting["Alfa Nova"] == 3, G("and still kept after a /reload"))
  -- The core arrives (the Discord's list): the kept traffic lands on it, once, with nothing sent again.
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Alfa Nova", list = {}, tag = "alfa-nova", size = 10, at = NOW } },
    "Officer-Firemaw")
  local nova = CM:GetPointsDB("Alfa Nova")
  local _, got = next(nova.standings)
  check(got and got.current == 25 and count(nova.standings) == 1 and nova.appliedOps["op-1"]
    and GuildOS.db.points.standings.Guildguy.current == 500, G("once the core is here its entries land on it, once"))
  check(nova.appliedOps["op-2"] and nova.accounts and next(nova.accounts) and nova.appliedOps["op-3"] and nova.queues and nova.queues.q,
    G("its counters and queues too"))
  check(GuildOS.db.pointsWaiting == nil, G("and nothing is kept any more"))
  -- Renamed into existence: a core this client has under another name becomes the one the entries name.
  ph({ act = "delta", data = { entries = { { op = "op-9", key = "Guildguy", delta = 4, core = "Alfa Velha", kind = "award",
    reason = "Boss" } } } }, "Officer-Firemaw")
  GuildOS.db.cores["Alfa Hoje"] = { name = "Alfa Hoje", members = {} }   -- an officers' core from before the link
  check(CM:Rename("Alfa Hoje", "Alfa Velha") and CM:GetPointsDB("Alfa Velha").appliedOps["op-9"], G("a rename into the name plays them"))
  -- Bounded: two hundred entries a core, the oldest let go, and none older than thirty days.
  for i = 1, 210 do
    ph({ act = "delta", data = { entries = { { op = "b-" .. i, key = "Guildguy", delta = 1, core = "Longe", kind = "award" } } } },
      "Officer-Firemaw")
  end
  local kept = GuildOS.db.pointsWaiting["Longe"]
  check(#kept == 200 and kept[1].e.op == "b-11", G("two hundred kept, the oldest let go"))
  for i = 1, 8 do
    NOW = NOW + 1
    ph({ act = "delta", data = { entries = { { op = "c-" .. i, key = "Guildguy", delta = 1, core = "C" .. i, kind = "award" } } } },
      "Officer-Firemaw")
  end
  check(GuildOS.db.pointsWaiting["Longe"] == nil and GuildOS.db.pointsWaiting.C1 and GuildOS.db.pointsWaiting.C8,
    G("eight cores kept at most, the one heard of longest ago let go"))
  NOW = NOW + 31 * DAY
  P:ReplayAllWaiting()
  check(GuildOS.db.pointsWaiting == nil, G("and let go after thirty days"))
  NOW = NOW - 31 * DAY - 8
  ph({ act = "snapshot", rev = 5, data = { core = "Alfa Nova", mode = "dkp", config = {}, standings = { Raider = { current = 42 } } } },
    "Officer-Firemaw")
  _, got = next(CM:GetPointsDB("Alfa Nova").standings)
  check(got and got.current == 42 and count(GuildOS.db.points.standings) == 1,
    G("and its snapshot, the revision not spent on the skip"))
  -- The raid's tag names a core this client has not got yet: what it gives is made as 1.24.0 made it,
  -- on the guild's pool and tagged "" (points, counters, queues alike, so what the officer sees is what
  -- the others book), and the officer is told so once a raid night. Rewritten (third review of #339):
  -- this asserted entries tagged with the missing core and kept for it, which were capped, counted and
  -- queued on the guild's pool while naming the other core, and lost with it after thirty days.
  GuildOS.db.raidTracker.currentGroupTag = "Alfa Amanha"
  GuildOS.LootRule = { Active = true, Counters = function()
    return { { key = "bonus", reset = "never", earn = { { key = "k", auto = "boss", value = 1 } } } } end }
  sent, printed = {}, {}
  P:Award("Guildguy", 6, "Boss")
  local told = sent[#sent]
  check(told and told.act == "delta" and told.data.entries[1].core == "",
    G("an award on a raid core this client lacks is the guild's: " .. tostring(told and told.data.entries[1].core)))
  check(GuildOS.db.points.standings.Guildguy.current == 506 and (GuildOS.db.pointsWaiting or {})["Alfa Amanha"] == nil,
    G("and lands on the guild's pool here, kept for nothing"))
  check(P:EarnCounters("boss", { "Guildguy" }) == 1 and sent[#sent].act == "cdelta" and sent[#sent].data.entries[1].core == ""
    and GuildOS.db.points.accounts and GuildOS.db.points.accounts.bonus, G("its counters too, told as the guild's"))
  local q = P:SetQueue("q", { "Guildguy" })
  check(q and q.core == "" and GuildOS.db.points.queues and GuildOS.db.points.queues.q, G("and its queues"))
  check((GuildOS.db.pointsWaiting or {})["Alfa Amanha"] == nil, G("nothing of it waits for the core"))
  local notes = 0
  for _, m in ipairs(printed) do
    if m:find("does not have the core Alfa Amanha yet", 1, true) then notes = notes + 1 end
  end
  check(notes == 1, G("the officer is told once that the night goes to the guild's pool: " .. notes))
  GuildOS.LootRule = nil
  GuildOS.db.raidTracker.currentGroupTag = ""
  GuildOS.db.points.accounts, GuildOS.db.points.queues = nil, nil
  GuildOS.db.points.standings.Guildguy.current = 500
  -- What this client writes under a core it does not have is no one's, and told to no one.
  sent = {}
  P:InCore("Sumiu", function() P:Charge("Guildguy", 10, "x") end)
  check(GuildOS.db.points.standings.Guildguy.current == 500 and count(GuildOS.db.points.standings) == 1 and #sent == 0, G("a charge in a core this client lacks goes nowhere"))
  check(P:InCore("Sumiu", function() return P:GetDB() end) == nil, G("and reads as no pool to the loot master"))
  GuildOS.Points = nil

  -- ── The loot rule the site sends is the site's ────────────────────────
  check(CM:SetLootRule("Núcleo Alfa", { model = "rolls" }), G("with no rule from the site, the officers set the core's"))
  GuildOS.db.companionRoster = { title = "Kara", members = {}, lootRule = { model = "council" } }
  check(CM:LootRuleFromSite("Núcleo Alfa") and not CM:LootRuleFromSite("Charlie2"), G("a Discord core's rule is the site's while it sends one"))
  check(not CM:SetLootRule("Núcleo Alfa", { model = "plus1" }) and CM:GetLootRule("Núcleo Alfa").model == "rolls",
    G("not changed in game then"))
  check(not CM:SetLootSystem("Núcleo Alfa", "rolls"), G("nor its loot system"))
  GuildOS.db.companionRoster = nil
  check(CM:SetLootSystem("Núcleo Alfa", "rolls"), G("a roster with no rule leaves them to the officers"))

  -- ── Renamed on Discord, renamed here: the link is the tag ─────────────
  CM = load(game)
  CM:Initialize()
  CM:ImportFromSite(package(1000, { alfa() }), 1000)
  local core = GuildOS.db.cores["Núcleo Alfa"]
  check(core and core.discordName == "Núcleo Alfa", G("the Discord's name is remembered"))
  GuildOS.db.raidTracker.sessions[1] = { groupTag = "Núcleo Alfa" }
  GuildOS.db.raidTracker.attendance["Núcleo Alfa"] = { x = 1 }
  GuildOS.db.raidTracker.currentGroupTag = "Núcleo Alfa"
  CM:GetPointsDB("Núcleo Alfa").standings.Ana = { current = 7 }
  CM:SetLootRule("Núcleo Alfa", { model = "rolls" })
  local cores, _ = CM:ImportFromSite(package(2000, { alfa("Núcleo Beta") }), 2000)
  check(GuildOS.db.cores["Núcleo Alfa"] == nil and GuildOS.db.cores["Núcleo Beta"] == core and count(GuildOS.db.cores) == 1,
    G("the same core, under the Discord's new name, and no second core"))
  check(cores[1].name == "Núcleo Beta" and cores[1].discordName == "Núcleo Beta", G("the import reports it under the new name"))
  check(GuildOS.db.raidTracker.sessions[1].groupTag == "Núcleo Beta" and GuildOS.db.raidTracker.attendance["Núcleo Beta"]
    and GuildOS.db.raidTracker.currentGroupTag == "Núcleo Beta", G("its nights, attendance and the active core go along"))
  check(CM:GetPointsDB("Núcleo Beta").standings.Ana.current == 7 and CM:GetLootRule("Núcleo Beta").model == "rolls",
    G("and its points and loot rule"))
  -- Another officer's client hears the rename with the list.
  sent = {}
  GuildOS.State.discordCores = cores
  CM:SendDiscordChanges()
  local list = sent[1].data
  check(list.discordName == "Núcleo Beta" and list.seenAt, G("the list says the Discord's name and how fresh it is"))
  CM = load(game)
  CM:Initialize()
  handlers["core.roster"]({ act = "discordList", data = { coreName = "Núcleo Alfa", list = {}, tag = "nucleo-alfa", size = 10,
    at = 1000, discordName = "Núcleo Alfa" } }, "Officer-Firemaw")
  handlers["core.roster"]({ act = "discordList", data = list }, "Officer-Firemaw")
  check(GuildOS.db.cores["Núcleo Beta"] and GuildOS.db.cores["Núcleo Alfa"] == nil and count(GuildOS.db.cores) == 1,
    G("and renames its own core the same way"))
  check(CM:IsLinked() and CM:LinkSeenAt() == list.seenAt, G("another officer's list links this client too, as fresh as theirs"))
  -- A core imported by a version from before `discordName`: the first package after the update already
  -- carries the Discord's new name, and the core follows it, as the officer who saw both did.
  -- Rewritten (review of #339): this was a core named "Núcleo Alfa" for the tag nucleo-alfa, a name that
  -- reduces to the tag, which is also how an officer's own core adopted by its slug looks ("Nucleo
  -- Alfa", "Kara" for kara): renamed on the first package after the update with nothing changed on
  -- Discord. A name that reduces to the tag is kept; one that does not follows.
  CM = load(game)
  GuildOS.db.cores["Raide Alfa"] = { name = "Raide Alfa", members = {}, discordTag = "nucleo-alfa", raidSize = 10,
    points = { mode = "dkp", config = {}, standings = { Ana = { current = 70 } }, log = {}, appliedOps = {}, appliedCount = 0 } }
  CM:Initialize()
  CM:ImportFromSite(package(2000, { alfa("Núcleo Beta") }), 2000)
  check(GuildOS.db.cores["Núcleo Beta"] and GuildOS.db.cores["Raide Alfa"] == nil and count(GuildOS.db.cores) == 1
    and GuildOS.db.cores["Núcleo Beta"].points.standings.Ana.current == 70,
    G("a core with no Discord name remembered follows the first package's new name, points along"))
  -- Named by the officers in a way that reduces to the tag, nothing changed on Discord: kept, and the
  -- Discord's name recorded, so the next rename follows as any other.
  for _, case in ipairs({ { "Nucleo Alfa", "nucleo-alfa", "Núcleo Alfa" }, { "Kara", "kara", "Karazhan Sexta" },
                          { "Núcleo Alfa", "nucleo-alfa", "Núcleo Alfa" } }) do
    local own, tag, discord = case[1], case[2], case[3]
    CM = load(game)
    GuildOS.db.cores[own] = { name = own, discordTag = tag, importedAt = 900, members = {} }
    GuildOS.db.coreLink = { importedAt = 900 }
    CM:Initialize()
    CM:ImportFromSite(package(1000, { { tag = tag, name = discord, size = 10, members = {} } }), 1000)
    check(GuildOS.db.cores[own] and count(GuildOS.db.cores) == 1 and GuildOS.db.cores[own].discordName == discord,
      G("a legacy core named " .. own .. " for " .. tag .. " keeps its name on the first package"))
    CM:ImportFromSite(package(2000, { { tag = tag, name = "Outro Nome", size = 10, members = {} } }), 2000)
    local renamed = GuildOS.db.cores["Outro Nome"] ~= nil
    check(renamed == (own == discord), G("and follows the next rename only as any core does (" .. own .. ")"))
  end
  -- Nor when the core is named by its tag, or the name is another core's.
  CM = load(game)
  GuildOS.db.cores["alfa-2"] = { name = "alfa-2", members = {}, discordTag = "alfa" }
  GuildOS.db.cores["nucleo-alfa"] = { name = "nucleo-alfa", members = {}, discordTag = "nucleo-alfa" }
  GuildOS.db.cores["Gama"] = { name = "Gama", members = {}, discordTag = "gama" }
  GuildOS.db.cores["Delta"] = { name = "Delta", members = {} }
  CM:Initialize()
  CM:ImportFromSite(package(2000, { { tag = "alfa", name = "Alfa Nova", size = 10, members = {} }, alfa("Núcleo Beta"),
    { tag = "gama", name = "Delta", size = 10, members = {} } }), 2000)
  check(GuildOS.db.cores["alfa-2"] and GuildOS.db.cores["nucleo-alfa"] and GuildOS.db.cores["Gama"]
    and CM:IsFromDiscord("Gama") and not CM:IsFromDiscord("Delta"),
    G("a core named by its tag, or whose new name another core has, keeps its own"))

  -- A core named apart from the Discord (by its tag, or linked by hand) keeps its name.
  CM = load(game)
  CM:Initialize()
  CM:ImportFromSite(package(1000, { { tag = "alfa-2", name = "Alfa", size = 10, members = {} } }), 1000)
  CM:ImportFromSite(package(2000, { { tag = "alfa-2", name = "Bravo", size = 10, members = {} } }), 2000)
  check(GuildOS.db.cores["alfa-2"] and GuildOS.db.cores["Bravo"] == nil, G("a core named by its tag keeps it"))
  -- A new name another core here already has: the core keeps its own.
  CM = load(game)
  CM:Create("Núcleo Beta")
  CM:Initialize()
  CM:ImportFromSite(package(1000, { alfa() }), 1000)
  CM:ImportFromSite(package(2000, { alfa("Núcleo Beta") }), 2000)
  check(CM:IsFromDiscord("Núcleo Alfa") and not CM:IsFromDiscord("Núcleo Beta"), G("a name taken here is not taken over"))
  -- And once that name is free, the next package follows it.
  check(CM:Rename("Núcleo Beta", "Outra"), G("the other core renamed"))
  CM:ImportFromSite(package(3000, { alfa("Núcleo Beta") }), 3000)
  check(CM:IsFromDiscord("Núcleo Beta") and GuildOS.db.cores["Núcleo Alfa"] == nil,
    G("a later package follows the name once it is free"))
  -- A Discord name past 48 bytes (the site allows 32 UTF-16 characters: 96 bytes of Korean, 64 of
  -- emoji) is followed cut on a character, and the next rename follows from it.
  for _, long in ipairs({ ("한"):rep(30), ("\240\159\152\128"):rep(16), "Raide de Quinta-feira da Guilda Nucleo BR Grupo A1 x" }) do
    CM = load(game)
    CM:Initialize()
    CM:ImportFromSite(package(1000, { alfa() }), 1000)
    CM:ImportFromSite(package(2000, { alfa(long) }), 2000)
    local name = next(GuildOS.db.cores)
    check(count(GuildOS.db.cores) == 1 and #name <= 48 and long:sub(1, #name) == name and GuildOS:IsUtf8(name)
      and CM:IsFromDiscord(name), G("a long Discord name is followed, cut on a character: " .. #name .. " bytes"))
    CM:ImportFromSite(package(3000, { alfa("Núcleo Gama") }), 3000)
    check(GuildOS.db.cores["Núcleo Gama"] and count(GuildOS.db.cores) == 1, G("and the next rename follows from it"))
  end
  -- A core made from a long Discord name is named the same cut.
  CM = load(game)
  CM:Initialize()
  CM:ImportFromSite(package(1000, { { tag = "aaaaaaaaaa-aaaaaaaaaa-aaaaaaaaaa", name = ("Aaaaaaaaaa "):rep(3) .. ("é"):rep(20),
    size = 10, members = {} } }), 1000)
  local made = next(GuildOS.db.cores)
  check(made and (#made <= 48), G("a core made from a long Discord name has at most 48 bytes: " .. tostring(made)))

  -- The rename comes with the inbox at login (#339): CoreManager:Initialize runs before
  -- RaidTracker:Initialize, the module loaded but its tag "" and no raid. The raid saved for the
  -- /reload, its tag and the officer's pick follow all the same, and the reopened raid is the core's.
  do
    CM = load(game)
    CM:ImportFromSite(package(1000, { alfa() }), 1000)
    local rt = GuildOS.db.raidTracker
    rt.currentGroupTag = "Núcleo Alfa"
    rt.openSession = { groupTag = "Núcleo Alfa", snapshots = {}, encounters = {} }
    rt.corePick = { tag = "Núcleo Alfa" }
    dofile(ADDON .. "/Modules/RaidTracker.lua")
    check(GuildOS.RaidTracker.currentRaid == nil and GuildOS.RaidTracker:GetCurrentGroup() == "", G("the tracker not started"))
    CM:ImportFromSite(package(2000, { alfa("Núcleo Beta") }), 2000)
    check(GuildOS.db.cores["Núcleo Beta"] and rt.currentGroupTag == "Núcleo Beta" and rt.openSession.groupTag == "Núcleo Beta"
      and rt.corePick.tag == "Núcleo Beta",
      G("before the tracker starts, the saved tag, the saved raid and the pick follow the rename: "
        .. tostring(rt.currentGroupTag) .. " / " .. tostring(rt.openSession.groupTag)))
    GuildOS.RaidTracker:Initialize()
    check(GuildOS.RaidTracker:GetCurrentGroup() == "Núcleo Beta" and CM:GetCore(GuildOS.RaidTracker:GetCurrentGroup()),
      G("and the tracker starts on the core, under its new name"))
    rt.openSession = { groupTag = "Núcleo Beta", snapshots = {}, encounters = {} }
    GuildOS.RaidTracker.currentGroupTag = ""   -- as before its Initialize
    GuildOS.db.cores["Núcleo Beta"].discordTag = nil
    check(CM:Delete("Núcleo Beta") and rt.currentGroupTag == "" and rt.openSession.groupTag == "",
      G("deleted before the tracker starts, the saved tag and raid let go of it"))
    GuildOS.RaidTracker = nil
  end

  -- ── Federation switched off: creating comes back ──────────────────────
  CM = load(game)
  CM:Initialize()
  CM:ImportFromSite(package(1000, { alfa() }), 1000)
  check(CM:IsLinked(), G("linked"))
  CM:ImportFromSite(package(2000, {}), 2000)
  check(not CM:IsLinked() and not CM:IsFromDiscord("Núcleo Alfa") and GuildOS.db.cores["Núcleo Alfa"],
    G("an empty package gives the cores and creating back"))
  check(CM:Create("De Novo"), G("an officer creates again"))
  -- On a client that only heard: the last release gives creating back.
  CM = load(game)
  CM:Initialize()
  handlers["core.roster"]({ act = "discordList", data = { coreName = "A", list = {}, tag = "a", size = 10, at = 1000 } }, "Officer-Firemaw")
  handlers["core.roster"]({ act = "discordList", data = { coreName = "B", list = {}, tag = "b", size = 10, at = 1000 } }, "Officer-Firemaw")
  check(CM:IsLinked(), G("heard lists link"))
  handlers["core.roster"]({ act = "discord", data = { coreName = "A", tag = false, at = 2000 } }, "Officer-Firemaw")
  check(CM:IsLinked(), G("one release leaves the guild linked while another core is the Discord's"))
  handlers["core.roster"]({ act = "discord", data = { coreName = "B", tag = false, at = 2000 } }, "Officer-Firemaw")
  check(not CM:IsLinked() and CM:Create("Livre"), G("the last one gives creating back"))

  -- ── An older guild: linked by its tags ───────────────────────────────
  CM = load(game)
  GuildOS.db.cores["Velho"] = { name = "Velho", members = {}, discordTag = "velho" }
  CM:Initialize()
  check(CM:IsLinked() and not CM:Create("Outro"), G("a guild that imported before this version is linked"))

  -- ── 30 days with no package: told once, and offered to create again ───
  CM = load(game)
  GuildOSInbox, GuildOSInboxAck = { FIXTURE }, { at = NOW }
  CM:Initialize()
  CM:TellQuietLink()
  check(not CM:IsLinkQuiet() and #printed == 1, G("a fresh package says nothing")) -- the import's own line
  NOW = NOW + 31 * DAY
  CM:ImportInbox()                                                        -- the same inbox, every login
  check(CM:IsLinkQuiet(), G("the same inbox again is no new package: 31 days on, the link is quiet"))
  printed = {}
  RANK = 5
  CM:TellQuietLink()
  check(#printed == 0, G("a member is not told"))
  RANK = 1
  CM:TellQuietLink()
  check(said("No cores from Discord for 30 days"), G("the officer is told"))
  printed = {}
  CM:TellQuietLink()
  check(#printed == 0, G("once"))
  RANK = 5
  check(CM:CreateInGameAgain() == false and CM:IsLinked(), G("a member cannot give the cores back"))
  RANK = 1
  sent = {}
  check(CM:CreateInGameAgain(), G("an officer can"))
  check(not CM:IsLinked() and not CM:HasDiscordCores() and GuildOS.db.cores["Núcleo Alfa"]
    and next(GuildOS.db.cores["Núcleo Alfa"].members), G("every core is the officers' again, people and all"))
  check(CM:Create("Feito Aqui"), G("and creating is back"))
  local releases = 0
  for _, s in ipairs(sent) do if s.act == "discord" and s.data.tag == false and s.data.off == true then releases = releases + 1 end end
  check(releases == 2, G("the officers online hear each release, as the officer's choice"))
  CM:ImportInbox()
  check(not CM:IsLinked() and not CM:HasDiscordCores(), G("the old inbox does not link the guild again"))
  -- Rewritten (review of #339): this asserted that pasting refused a fresh copy, as the release compared
  -- the site's `at` (unchanged while no core changes on Discord) with the choice. What counts is when
  -- this client received it: a code an officer copies now and pastes links the guild again.
  local again = { fmt = "GOSCORE1", v = 1, guild = "Nucleo BR", realm = "Firemaw", unlinked = 0, at = GuildOS.db.discordAt,
    cores = { alfa() } }
  local LD = LibStub("LibDeflate")
  local n2 = GuildOS.CompanionImport:Load("GOSCORE1:" .. LD:EncodeForPrint(LD:CompressDeflate(GuildOS.Companion.EncodeJson(again))))
  check(n2 == 1 and CM:IsLinked() and CM:IsFromDiscord("Núcleo Alfa"), G("a fresh copy of the same cores, pasted, links it again"))
  check(not CM:IsLinkQuiet(), G("and is fresh"))
  check(CM:CreateInGameAgain() and not CM:IsLinked(), G("given back again"))
  CM:ImportFromSite(package(GuildOS.db.discordAt + 10, { alfa() }), GuildOS.db.discordAt + 10)
  check(CM:IsLinked(), G("a package the site makes later links it again"))
  -- The other officer: the choice reaches it, and its own old inbox does not undo it.
  local choice = {}
  for _, s in ipairs(sent) do if s.act == "discord" then choice[#choice + 1] = s end end
  CM = load(game)
  GuildOSInbox, GuildOSInboxAck = { FIXTURE }, { at = NOW }
  CM:Initialize()
  check(CM:IsLinked(), G("the other officer's client is linked"))
  for _, s in ipairs(choice) do handlers["core.roster"]({ act = s.act, data = s.data }, "Officer-Firemaw") end
  check(not CM:IsLinked() and not CM:HasDiscordCores(), G("the choice gives the cores back there"))
  CM:ImportInbox()
  check(not CM:IsLinked(), G("and its own old inbox does not link them again"))

  -- The choice from an officer on the version before (#339): `{ tag = false, off = true, at = <site at> }`
  -- with no `offAt`. The site's `at` is when the cores last changed on Discord (40 days ago here); this
  -- client's inbox was acked 35 days ago, before the choice. Taken as the choice's time, the stale inbox
  -- read after it linked the guild again against the officer's will.
  do
    CM = load(game)
    local siteAt = NOW - 40 * DAY
    CM:Initialize()
    CM:ImportPackage({ guild = "Nucleo BR", realm = "Firemaw", unlinked = 0, at = siteAt, cores = { alfa() } }, NOW - 35 * DAY)
    check(CM:IsLinked(), G("linked by its inbox"))
    handlers["core.roster"]({ act = "discord", data = { coreName = "Núcleo Alfa", tag = false, at = siteAt, off = true } },
      "Old-Firemaw")
    check(not CM:IsLinked() and GuildOS.db.coreLink.releasedAt == NOW,
      G("an old officer's release, with no offAt, is dated when it arrives: " .. tostring(GuildOS.db.coreLink.releasedAt)))
    CM:ImportPackage({ guild = "Nucleo BR", realm = "Firemaw", unlinked = 0, at = siteAt, cores = { alfa() } }, NOW - 35 * DAY)
    check(not CM:IsLinked(), G("and the inbox acked before it does not link the guild again"))
  end
end

print(("core-owner: %d checks passed"):format(checks))
