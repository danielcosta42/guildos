-- A pug is a guest of the night, not a member of the core (issue #340; guildos-web specs/085), run
-- against the real Core, Compat, Utils, CoreManager, CompanionExport, CompanionImport and RaidTracker
-- under a stubbed client, with the site's fixture (tools/cores-fixture.txt).
--
--   * in a linked guild, "add" on a Discord core makes a guest; anywhere else, a member, as always;
--   * whoever was on a Discord core with no record from the Discord becomes a guest who stays: nobody
--     disappears;
--   * the composition and the open seats count members only; the night's raid counts both;
--   * a night's guests leave when the raid session ends, but those marked to stay;
--   * guests travel between officers as changes, never removing another officer's.
--
--   luajit -e 'ADDON="."' tools/core-guests.lua
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

local printed, sent, handlers, GROUP = {}, {}, {}, {}
local RANK, NOW = 1, 1790000000
local function load(game)
  printed, sent, handlers, GROUP, RANK, NOW = {}, {}, {}, {}, 1, 1790000000
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
  C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
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
  function GetGuildInfo() return "Nucleo BR", "Rank", RANK end
  function GetNumGuildMembers() return 0 end
  function GetGuildRosterInfo() end
  function IsInRaid() return true end
  function GetInstanceInfo() return "Molten Core", "raid", 9, "", 40, 0, false, 409 end
  function GetNumGroupMembers() return #GROUP end
  function UnitExists(u) return u == "player" or GROUP[tonumber(u:match("%d+") or "")] ~= nil end
  function UnitIsConnected() return true end
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
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  dofile(ADDON .. "/Modules/Points.lua")   -- who closes the night (Points:EndsTheNight)
  GuildOS.SyncService = {
    On = function(_, domain, fn) handlers[domain] = fn end,
    Publish = function(_, domain, act, data) sent[#sent + 1] = { domain = domain, act = act, data = data } end,
  }
  GuildOS.IsOfficerByName = function(_, who) return who ~= "Member-Firemaw" end
  local RT = GuildOS.RaidTracker
  RT.currentGroupTag = ""
  RT.CheckPlayerConsumes = function() return false end
  RT.BroadcastRaidData = function() end
  GuildOS.Compat.IsPlayer = function(u) return u == "player" end
  GuildOS.Compat.UnitIdentity = function(u)
    return GROUP[tonumber(u:match("%d+") or "")], nil, "MAGE"
  end
  GuildOSInbox, GuildOSInboxAck = nil, nil
  return GuildOS.CoreManager, RT
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function published(act)
  local out = {}
  for _, s in ipairs(sent) do if s.domain == "core.roster" and s.act == act then out[#out + 1] = s end end
  return out
end

for _, game in ipairs({ "anniversary", "forever" }) do
  local function G(what) return game .. ": " .. what end
  local K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end

  -- ── A guild without the site: "add" is a member, as always ───────────
  local CM = load(game)
  CM:Initialize()
  CM:Create("Sexta")
  check(CM:AddToRoster(K("Pug"), { name = "Pug", class = "MAGE", role = "rdps" }, "Sexta") == "member",
    G("an unlinked guild's add makes a member"))
  check(GuildOS.db.cores["Sexta"].members[K("Pug")] and count(CM:GetGuests("Sexta")) == 0, G("on the members, no guest"))
  check(#published("update") == 1 and #published("guests") == 0, G("and the whole roster goes out, as before"))

  -- ── Linked: "add" on a Discord core is a guest of the night ──────────
  CM = load(game)
  K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
  CM:Create("Nucleo Alfa")                                           -- a core from before the link,
  local before = GuildOS.db.cores["Nucleo Alfa"].members              -- with an officer's people on it
  before[K("Carla")] = { name = "Carla", class = "MAGE", role = "rdps", note = "pug" }
  before[K("Ana")] = { name = "Ana", class = "PRIEST", role = "rdps", note = "x" }
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  local core = GuildOS.db.cores["Nucleo Alfa"]
  check(CM:IsFromDiscord("Nucleo Alfa") and CM:IsLinked(), G("the import makes the core the Discord's"))
  -- Migration: Carla, whom the Discord does not have, becomes a guest who stays; Ana, whom it has, a member.
  local carla = core.guests and core.guests[K("Carla")]
  check(core.members[K("Carla")] == nil and carla and carla.stay == true and carla.note == "pug" and carla.class == "MAGE",
    G("whoever an officer had put on the core is a guest who stays, record and all"))
  check(core.members[K("Ana")] and core.members[K("Ana")].src == "discord" and not core.guests[K("Ana")],
    G("whoever the Discord has stays a member"))
  local everyone = count(core.members) + count(core.guests)
  for _, rec in pairs(core.members) do check(rec.src == "discord", G("every member of a Discord core is the Discord's")) end
  CM:MigrateGuests()
  check(count(core.members) + count(core.guests) == everyone, G("nobody disappears, and migrating again changes nothing"))

  local comp, open = CM:GetComposition("Nucleo Alfa"), CM:OpenSlots("Nucleo Alfa")
  sent = {}
  check(CM:AddToRoster(K("Zed"), { name = "Zed", class = "WARRIOR", role = "tank" }, "Nucleo Alfa") == "guest",
    G("an officer's add on a Discord core makes a guest"))
  check(core.members[K("Zed")] == nil and core.guests[K("Zed")] and not core.guests[K("Zed")].stay,
    G("apart from the members, for tonight"))
  local comp2, open2 = CM:GetComposition("Nucleo Alfa"), CM:OpenSlots("Nucleo Alfa")
  check(comp2.total == comp.total and comp2.roleCounts.tank == comp.roleCounts.tank and open2.total == open.total
    and open2.tank == open.tank, G("the composition and the open seats count members only"))
  local night = CM:RaidRoster("Nucleo Alfa")
  check(night[K("Zed")] and night[K("Carla")] and night[K("Ana")], G("the night's raid has members and guests"))
  check(#published("guests") == 1 and #published("update") == 0, G("the change goes out as a guest, not the whole roster"))
  local put = published("guests")[1].data
  check(put.coreName == "Nucleo Alfa" and put.tag == "nucleo-alfa" and put.put[K("Zed")] and put.gone == nil and put.members == nil,
    G("with the core's tag, only the guest put, and no `members` a client from before would take whole"))
  -- A core from before the link, holding no tag: the officers' still, "add" a member.
  check(not CM:Create("x"), G("refused: linked"))
  local since = GuildOS.db.coreLink.since                            -- made as before the link
  GuildOS.db.coreLink.since = nil
  CM:Create("Antigo")
  GuildOS.db.coreLink.since = since
  check(CM:AddToRoster(K("Rui"), { name = "Rui", class = "MAGE" }, "Antigo") == "member", G("a core only in the game takes members"))
  -- Who is already a member is not a guest too; at most 40 guests; a pug by name.
  local ok, why = CM:AddGuest(K("Ana"), { name = "Ana" }, "Nucleo Alfa")
  check(not ok and why == "Already on this core.", G("a member is not made a guest"))
  for i = 1, 45 do CM:AddGuest(K("G" .. i), { name = "G" .. i }, "Nucleo Alfa") end
  check(count(core.guests) == 40, G("a core holds at most 40 guests"))
  ok, why = CM:AddGuest(K("Over"), { name = "Over" }, "Nucleo Alfa")
  check(not ok and why == "A core holds at most 40 guests.", G("and says so"))
  for i = 1, 45 do CM:RemoveGuest(K("G" .. i), "Nucleo Alfa") end
  check(CM:AddGuestByName("  Pugzão-Firemaw ", "healer", "Nucleo Alfa"), G("a pug from outside the guild, by name"))
  local byName = game == "anniversary" and core.guests["Pugzão-Firemaw"] or core.guests[GuildOS:GetPlayerKey("Pugzão-Firemaw")]
  check(byName and byName.role == CM:RoleFor("WARRIOR", "healer") and byName.class == "WARRIOR", G("with the role picked: " .. tostring(byName)))
  check(not CM:AddGuestByName("|cffff0000x", nil, "Nucleo Alfa") and not CM:AddGuestByName("a", nil, "Nucleo Alfa"),
    G("a name with escapes, or too short, is refused"))
  check(not CM:AddGuest(K("Q"), {}, "Nao Existe") and GuildOS.db.cores["Nao Existe"] == nil, G("no core is made for a guest"))
  -- A sign-up accepted on a Discord core plays as a guest who stays.
  CM:AddSignup(K("Sol"), { name = "Sol", class = "PALADIN", role = "healer" }, "Nucleo Alfa")
  check(CM:AcceptSignup(K("Sol"), "Nucleo Alfa") and core.guests[K("Sol")] and core.guests[K("Sol")].stay
    and core.members[K("Sol")] == nil, G("a sign-up accepted on a Discord core is a guest who stays"))
  -- The receipt names the guests (#347).
  local receipt = GuildOS.Companion.CoreReceipt()
  local shown
  for _, c in ipairs(receipt.cores) do if c.tag == "nucleo-alfa" then shown = table.concat(c.guests, ",") end end
  check(shown and shown:find("Zed", 1, true) and shown:find("Carla", 1, true), G("the upload's receipt names the night's guests: " .. tostring(shown)))

  -- ── The Discord later has the guest: a member, no longer a guest ──────
  CM:SyncDiscordCore("Nucleo Alfa", { { key = "Ana-Firemaw", name = "Ana" }, { key = "Zed-Firemaw", name = "Zed", class = "WARRIOR" } },
    nil, "nucleo-alfa")
  check(core.members[K("Zed")] and core.members[K("Zed")].src == "discord" and core.guests[K("Zed")] == nil,
    G("one or the other, never both"))
  CM:AddGuest(K("Zed2"), { name = "Zed2" }, "Nucleo Alfa")

  -- ── Between officers: changes, never another officer's guest removed ──
  local carry = {}
  for _, s in ipairs(published("guests")) do carry[#carry + 1] = s end
  CM = load(game)
  K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  local other = GuildOS.db.cores["Núcleo Alfa"]
  CM:AddGuest(K("Meu"), { name = "Meu" }, "Núcleo Alfa")          -- this officer's own guest
  for _, s in ipairs(carry) do handlers["core.roster"]({ act = s.act, data = s.data }, "Officer-Firemaw") end
  check(other.guests[K("Zed2")] and other.guests[K("Sol")] and other.guests[K("Meu")], G("another officer's guests land beside this one's"))
  check(other.guests[K("G1")] == nil and other.guests[K("G40")] == nil, G("a guest removed there is removed here"))
  handlers["core.roster"]({ act = "guests", data = { coreName = "Núcleo Alfa", gone = { K("Zed2") } } }, "Officer-Firemaw")
  check(other.guests[K("Zed2")] == nil and other.guests[K("Meu")], G("a removal takes off only whom it names"))
  handlers["core.roster"]({ act = "guests", data = { coreName = "Núcleo Alfa", put = { [K("Fake")] = { name = "Fake" } } } }, "Member-Firemaw")
  check(other.guests[K("Fake")] == nil, G("a member's message is ignored"))
  handlers["core.roster"]({ act = "guests", data = { coreName = "Inventado", tag = "", put = { [K("Fake")] = { name = "Fake" } } } }, "Officer-Firemaw")
  check(GuildOS.db.cores["Inventado"] == nil, G("a core this client lacks is not made for guests"))
  handlers["core.roster"]({ act = "guests", data = { coreName = "Outro Nome", tag = "nucleo-alfa",
    put = { [K("PorTag")] = { name = "PorTag", class = "NOPE", role = "nope", stay = "yes", at = 0 / 0 } } } }, "Officer-Firemaw")
  local pt = other.guests[K("PorTag")]
  check(pt and pt.class == "WARRIOR" and pt.stay == nil and pt.at == NOW, G("by its tag, whatever the sender calls it; every field checked"))
  local big = {}
  for i = 1, 60 do big[K("B" .. i)] = { name = "B" .. i } end
  big[string.rep("k", 80)] = { name = "Long" }
  big[K("Ana")] = { name = "Ana" }
  handlers["core.roster"]({ act = "guests", data = { coreName = "Núcleo Alfa", put = big } }, "Officer-Firemaw")
  check(count(other.guests) <= 40 and not other.guests[string.rep("k", 80)] and not other.guests[K("Ana")],
    G("never past 40, never a key too long, never a member"))
  handlers["core.roster"]({ act = "guests", data = { coreName = "Núcleo Alfa", put = "x", gone = 7 } }, "Officer-Firemaw")
  check(other.guests[K("Meu")], G("a message of the wrong shape changes nothing"))

  -- ── The night ends: its guests leave, but those marked to stay ────────
  CM = load(game)
  K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  CM:AddGuest(K("Hoje"), { name = "Hoje" }, "Núcleo Alfa")
  CM:AddGuest(K("Fica"), { name = "Fica" }, "Núcleo Alfa", false)
  CM:SetGuestStay(K("Fica"), "Núcleo Alfa", true)
  CM:AddGuest(K("Beta"), { name = "Beta" }, "alfa-2")
  sent = {}
  -- Rewritten (review of #340): EndNight took no session and told every officer; it now tells them only
  -- from the client that closes the night (the raid's leader, as the raid's end awards), here this one.
  local me = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
  check(CM:EndNight("Núcleo Alfa", { leader = me, snapshots = { { members = { [me] = {} } } } }) == 1,
    G("one guest of the night leaves"))
  local nucleo = GuildOS.db.cores["Núcleo Alfa"]
  check(nucleo.guests[K("Hoje")] == nil and nucleo.guests[K("Fica")], G("the one marked to stay stays"))
  check(GuildOS.db.cores["alfa-2"].guests[K("Beta")], G("another core's guests are its own night's"))
  local gone = published("guests")
  check(#gone == 1 and gone[1].data.gone[1] == K("Hoje") and gone[1].data.put == nil, G("the other officers hear who left"))
  -- Through the raid tracker: the session's end is the night's.
  local RT = GuildOS.RaidTracker
  CM:AddGuest(K("Hoje"), { name = "Hoje" }, "Núcleo Alfa")
  RT:SetGroupTag("Núcleo Alfa")
  GROUP = { "Leader" }
  RT:StartSession(409)
  RT.currentRaid.groupTag = "Núcleo Alfa"
  RT.coreSettled = true
  NOW = NOW + 3600
  RT:EndSession()
  check(nucleo.guests[K("Hoje")] == nil and nucleo.guests[K("Fica")], G("the raid session's end sends the night's guests away"))
  -- A session too short to count (a disconnect) is no end of the night.
  CM:AddGuest(K("Hoje"), { name = "Hoje" }, "Núcleo Alfa")
  RT:StartSession(409)
  RT.currentRaid.groupTag = "Núcleo Alfa"
  NOW = NOW + 60
  RT:EndSession()
  check(nucleo.guests[K("Hoje")], G("a session discarded as too short keeps them"))

  -- ── Two officers: one's session ending is not the night's end ────────
  -- Officer A leaves early (or disconnects past the hold); Ana, the raid's leader, is still raiding.
  CM = load(game)
  K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  CM:AddGuest(K("Pugtank"), { name = "Pugtank", role = "tank" }, "Núcleo Alfa")
  CM:AddGuest(K("Pugheal"), { name = "Pugheal", role = "healer" }, "Núcleo Alfa")
  local puts = published("guests")
  local leader = K("Ana")
  local session = { groupTag = "Núcleo Alfa", leader = leader,
    snapshots = { { members = { [leader] = {}, [GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())] = {} } } } }
  sent = {}
  check(CM:EndNight("Núcleo Alfa", session) == 2 and count(GuildOS.db.cores["Núcleo Alfa"].guests) == 0,
    G("officer A's session ends: the night's guests leave A's list"))
  check(#published("guests") == 0, G("and A tells nobody: the raid goes on for the others"))
  -- The leader's client: it heard A's guests, and is still raiding the core.
  local function client(raiding)
    CM = load(game)
    K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
    GuildOSInbox = { FIXTURE }
    CM:Initialize()
    for _, m in ipairs(puts) do handlers["core.roster"]({ act = m.act, data = m.data }, "OfficerA-Firemaw") end
    if raiding then GuildOS.RaidTracker.currentRaid = { groupTag = "Núcleo Alfa" } end
    return GuildOS.db.cores["Núcleo Alfa"].guests
  end
  local onLeader = client(true)
  check(onLeader[K("Pugtank")] and onLeader[K("Pugheal")], G("the leader's client has the night's guests mid-raid"))
  -- The leader ends the night: the guests leave every officer's list.
  sent = {}
  local leaderSession = { groupTag = "Núcleo Alfa", leader = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()),
    snapshots = { { members = { [GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())] = {} } } } }
  GuildOS.RaidTracker.currentRaid = nil
  check(CM:EndNight("Núcleo Alfa", leaderSession) == 2, G("the leader's client ends the night"))
  local ended = published("guests")
  check(#ended == 1 and ended[1].data.ended == true and #ended[1].data.gone == 2, G("and tells the other officers, as the night's end"))
  -- An officer still in that core's raid session (it zoned out, its hold running) keeps them; one not
  -- raiding lets them go; a removal by hand is applied even mid-raid.
  local still = client(true)
  handlers["core.roster"]({ act = ended[1].act, data = ended[1].data }, "Leader-Firemaw")
  check(still[K("Pugtank")] and still[K("Pugheal")], G("a client still raiding that core keeps its night's guests"))
  handlers["core.roster"]({ act = "guests", data = { coreName = "Núcleo Alfa", tag = "nucleo-alfa", gone = { K("Pugheal") } } },
    "Leader-Firemaw")
  check(still[K("Pugtank")] and not still[K("Pugheal")], G("but a guest taken off by hand leaves it"))
  local away = client(false)
  handlers["core.roster"]({ act = ended[1].act, data = ended[1].data }, "Leader-Firemaw")
  check(count(away) == 0, G("an officer not raiding lets them go"))
  local elsewhere = client(false)
  GuildOS.RaidTracker.currentRaid = { groupTag = "alfa-2" }
  handlers["core.roster"]({ act = ended[1].act, data = ended[1].data }, "Leader-Firemaw")
  check(count(elsewhere) == 0, G("and so does one raiding another core"))

  -- ── Migrated guests: members again when the core is given back; one person, never both ──
  CM = load(game)
  K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
  CM:Create("Nucleo Alfa")
  local mine = GuildOS.db.cores["Nucleo Alfa"].members
  mine[K("Carla")] = { name = "Carla", class = "MAGE", role = "rdps", note = "pug" }
  for i = 1, 45 do mine[K(("M%02d"):format(i))] = { name = ("M%02d"):format(i), class = "MAGE", role = "rdps", note = "" } end
  GuildOSInbox = { FIXTURE }
  CM:Initialize()
  local nc = GuildOS.db.cores["Nucleo Alfa"]
  local ours = { K("Carla") }
  for i = 1, 45 do ours[#ours + 1] = K(("M%02d"):format(i)) end
  local function kept()
    local n = 0
    for _, key in ipairs(ours) do if nc.members[key] or nc.guests[key] then n = n + 1 end end
    return n
  end
  check(count(nc.guests) == 40 and kept() == 46, G("migrating keeps the 40-guest cap: whoever is past it stays a member, nobody dropped"))
  for key, rec in pairs(nc.members) do
    check(rec.src == "discord" or not nc.guests[key], G("and nobody is both"))
  end
  local carlaWas = nc.guests[K("Carla")]
  check(carlaWas and carlaWas.migrated, G("a migrated guest is marked as one"))
  -- A whole roster from an officer on a version from before re-adds a migrated guest as a member.
  local roster = {}
  for key, rec in pairs(nc.members) do roster[key] = rec end
  roster[K("Carla")] = { name = "Carla", class = "MAGE", role = "rdps", note = "pug" }
  handlers["core.roster"]({ act = "update", data = { coreName = "Nucleo Alfa", members = roster } }, "Old-Firemaw")
  check(nc.members[K("Carla")] and not nc.guests[K("Carla")], G("a member wins: the guest record is dropped"))
  -- Carla's seat among the guests is free now: an officer adds a guest who stays.
  check(CM:AddToRoster(K("Novo"), { name = "Novo", class = "WARRIOR" }, "Nucleo Alfa") == "guest"
    and not nc.guests[K("Novo")].migrated, G("an officer's guest is no migrated one"))
  CM:SetGuestStay(K("Novo"), "Nucleo Alfa", true)
  -- The cores given back to the game: the migrated are members again; the one added as a guest stays one.
  GuildOS.db.coreLink.seenAt = NOW - 31 * 86400
  check(CM:CreateInGameAgain(), G("created in game again"))
  check(nc.members[K("Carla")] and not nc.guests[K("Carla")] and nc.members[K("Carla")].note == "pug",
    G("a migrated guest is a member again, record and all"))
  local back = 0
  for _, rec in pairs(nc.guests) do if rec.migrated then back = back + 1 end end
  check(back == 0 and nc.guests[K("Novo")] and not nc.members[K("Novo")], G("a guest added as one stays a guest"))
  check(kept() == 46, G("and nobody disappears"))

  -- ── The night's raid counts guests ───────────────────────────────────
  CM = load(game)
  K = function(name) return GuildOS:LocalMemberKey(name .. "-Firemaw") end
  CM:ImportFromSite({ guild = "Nucleo BR", realm = "Firemaw", unlinked = 0, cores = {
    { tag = "a", name = "A", size = 10, members = { { key = "M1-Firemaw", name = "M1" }, { key = "M2-Firemaw", name = "M2" } } },
    { tag = "b", name = "B", size = 10, members = { { key = "N1-Firemaw", name = "N1" }, { key = "N2-Firemaw", name = "N2" },
      { key = "N3-Firemaw", name = "N3" } } } } })
  for _, n in ipairs({ "P1", "P2" }) do CM:AddGuest(K(n), { name = n }, "A") end
  local players = { [K("M1")] = true, [K("M2")] = true, [K("P1")] = true, [K("P2")] = true, [K("N1")] = true }
  check(CM:CoreForGroup(players, 10) == "A", G("a group of A's members and its guests is A's night, not B's"))
end

print(("core-guests: %d checks passed"):format(checks))
