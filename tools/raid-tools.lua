-- Raid Tools for the raid leader (#449; specs/salao/raidtools.md), run against the real Core/Compat.lua,
-- Core/Utils.lua, Modules/RaidTools.lua and Modules/RaidHUD.lua as TBC Anniversary and as WoW: Forever.
--
-- The source of people is chosen on the spot (the group, the site's raid, the guild online) and kept; the
-- site's signups read as signed, standby, tentative or pending, declined left out, somebody in the group
-- and not signed up an extra. Roles count against what the raid needs, the raid leader's own targets
-- first. The invites ask only who signed up and is not here, never a banned or offline one, nobody twice
-- inside a minute, four alone, a party's free seats, a party too small turned into a raid, and on Forever
-- one person a click. The parties suggested keep five a party, everyone once, the tanks together, the
-- shamans spread; the moves only move who is out of place. A boss's assignments come from the raid
-- leader, else the site's plan, else the defaults, and say themselves in one to three lines. The HUD shows
-- only while its switch is on, never because combat began, and counts only the raid's own casts.
--
--   luajit -e 'ADDON="."' tools/raid-tools.lua
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

-- ── The stub client ────────────────────────────────────────────────────
local G = {}   -- the world the stubs read: group, guild, combat, invites, chat
local function reset()
  G.raid, G.party, G.combat, G.leader = false, {}, false, true
  G.guild = {}
  G.invited, G.said, G.converted, G.moves = {}, {}, 0, {}
  G.now = 1000
end

local function load(game)
  reset()
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  else
    function GetBuildInfo() return "2.5.6", "70006", "", 20506 end
    WOW_PROJECT_ID = 5
  end
  function GetRealmName() return "Realm" end
  function GetNormalizedRealmName() return "Realm" end
  function GetServerTime() return 1791000000 end
  function GetTime() return G.now end
  function UnitName() return "Ana" end
  function UnitFullName() return "Ana", "" end
  function UnitClass() return "Paladin", "PALADIN" end
  function UnitExists(u) return G.party[tonumber(u:match("%d+") or 0)] ~= nil end
  function UnitIsGroupLeader() return G.leader end
  function UnitIsGroupAssistant() return false end
  function InCombatLockdown() return G.combat end
  function IsInRaid() return G.raid end
  function IsInGroup() return G.raid or #G.party > 0 end
  function GetNumGroupMembers()
    if G.raid then return #G.party end
    return #G.party > 0 and (#G.party + 1) or 0
  end
  function GetRaidRosterInfo(i)
    local p = G.party[i]
    if not p then return nil end
    return p[1], 0, p[3] or 1, 70, p[2], p[2]
  end
  function UnitFullNameOf() end
  function GetNumGuildMembers() return #G.guild end
  function GetGuildRosterInfo(i)
    local m = G.guild[i]
    return m[1] .. "-Realm", "Raider", 1, 70, m[2], "", "", "", m[3], 0, m[2]
  end
  C_PartyInfo = {
    InviteUnit = function(name) G.invited[#G.invited + 1] = name end,
    ConvertToRaid = function() G.converted = G.converted + 1 end,
  }
  function SetRaidSubgroup(i, g) G.moves[#G.moves + 1] = { i, g } end
  function SwapRaidSubgroup(a, b) G.moves[#G.moves + 1] = { a, swap = b } end
  C_ChatInfo = { InChatMessagingLockdown = function() return false end }
  -- The game raises on a bare "|" (an escape it cannot read) and on a line past 255 bytes.
  function SendChatMessage(text, chatType)
    if G.chatDown then error("chat down") end
    if text:gsub("|[cHhrTtnA]", ""):find("|", 1, true) then error("Invalid escape code in chat message") end
    if #text > 255 then error("message too long") end
    G.said[#G.said + 1] = { text = text, chat = chatType }
  end
  C_PlayerInfo = { ShouldDisplaySurname = function() return false end }
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.Print = function() end
  GuildOS.SafeCall = function(_, fn, ...) return fn(...) end
  GuildOS.RecordMissing = function() end
  -- The party's units: UnitIdentity reads UnitFullName/UnitClass per unit.
  function UnitName(unit)
    local i = unit and tonumber(unit:match("^party(%d+)$") or "")
    if i and G.party[i] then return G.party[i][1], nil end
    return "Ana"
  end
  function UnitClass(unit)
    local i = unit and tonumber(unit:match("^party(%d+)$") or "")
    if i and G.party[i] then return G.party[i][2], G.party[i][2] end
    return "Paladin", "PALADIN"
  end
  dofile(ADDON .. "/Modules/RaidTools.lua")
  dofile(ADDON .. "/Modules/RaidHUD.lua")
  GuildOS.db = { members = {}, settings = { modules = {} } }
  return GuildOS.RaidTools, GuildOS.RaidHUD
end

local function person(name, class, role, status, inGroup)
  return { name = name, key = GuildOS:GetPlayerKey(name), class = class, role = role, status = status or "signed", inGroup = inGroup }
end

-- ── 1. What the raid needs, the roles against it ───────────────────────
local RT, HUD = load("anniversary")
check(RT:Instance("kara").size == 10 and RT:Instance("tk").size == 25 and RT:Instance("za").size == 10,
  "TBC's raids: Karazhan and Zul'Aman are 10, Tempest Keep 25")
local t = RT:Targets("tk")
check(t.size == 25 and t.tank == 3 and t.healer == 7 and t.dps == 15 and not t.edited, "a 25-man raid needs 3 tanks, 7 healers, 15 dps")
check(RT:Targets("kara").tank == 2 and RT:Targets("kara").dps == 5, "Karazhan: 2 tanks, 5 dps")
check(RT:Targets(nil, 40).tank == 4 and RT:Targets(nil, 40).healer == 10, "a raid nobody listed takes its size's targets")
RT:SetTarget("tk", "healer", 6)
t = RT:Targets("tk")
check(t.healer == 6 and t.dps == 16 and t.edited and GuildOS.db.raidTools.targets.tk.healer == 6,
  "the raid leader's own target for this raid wins, saved, and the dps follow")
RT:SetTarget("tk", "healer", nil)
check(RT:Targets("tk").healer == 7 and GuildOS.db.raidTools.targets.tk == nil, "and goes back to the default")
check(not RT:SetTarget("tk", "dps", 3), "only tanks and healers are set by hand")

local people = {
  person("Brakk", "WARRIOR", "TANK"), person("Garruk", "WARRIOR", "TANK"),
  person("Velyra", "PRIEST", "HEALER"), person("Oruk", "SHAMAN", "HEALER"),
  person("Kaelis", "MAGE", "DPS"), person("Sombra", "ROGUE", "DPS"), person("Nyx", "HUNTER", nil),
  person("Wren", "DRUID", "HEALER", "standby"), person("Pell", "MAGE", "DPS", "pending"),
  person("Pug", "ROGUE", "DPS", "extra", true),
}
local c = RT.CountRoles(people)
check(c.TANK == 2 and c.HEALER == 2 and c.DPS == 3 and c.UNKNOWN == 1 and c.total == 8,
  "the roles count who is signed up and the extras here; standby and no answer do not")
local gaps = RT.RoleGaps(c, RT:Targets("tk"))
check(gaps[1].role == "TANK" and gaps[1].short == 1 and gaps[2].short == 5 and gaps[3].short == 12,
  "and against the targets: one tank short, five healers, twelve dps")
local miss = RT.Missing(people)
check(#miss == 7, "everyone signed up and not in the group is missing")
local lines = RT.MissingLines(gaps, miss)
check(#lines >= 1 and lines[1]:find("1 tank short", 1, true) and lines[1]:find("Brakk", 1, true),
  "who is missing, said in a line: the roles short and the names")

-- Roles: the site's slot, the raiders' roster, a core seat, the class alone.
GuildOS.RaiderRoster = { EffectiveRoles = function(_, k) return k == GuildOS:GetPlayerKey("Velyra") and { HEALER = true } or {} end }
check(RT:RoleOf("x", "PALADIN", "TANK") == "TANK", "the site's slot first")
check(RT:RoleOf(GuildOS:GetPlayerKey("Velyra"), "PRIEST") == "HEALER", "then the raiders' roster")
local r, guess = RT:RoleOf("y", "MAGE")
check(r == "DPS" and guess == true, "a mage is dps by the class, a guess")
check(RT:RoleOf("z", "DRUID") == nil, "a druid nobody named has no role")

-- ── 2. The source of people ────────────────────────────────────────────
G.guild = { { "Ana", "PALADIN", true }, { "Brakk", "WARRIOR", true }, { "Offo", "MAGE", false } }
check(RT:SourceKind() == "guild", "alone and with no site raid, the guild online")
G.party = { { "Brakk", "WARRIOR" } }
check(RT:SourceKind() == "group", "in a group, the group")
local ROSTER = { raidId = 9, title = "TK", instanceKey = "tk", size = 25, startsAt = 1791000600, pasted = true, members = {},
  signups = {
    { name = "Brakk", class = "WARRIOR", slot = "TANK", invite = true },
    { name = "Velyra", class = "PRIEST", slot = "HEALER", invite = true },
    { name = "Wren", class = "DRUID", slot = "HEALER", why = "wait" },
    { name = "Tia", class = "MAGE", slot = "RANGED", why = "tentative" },
    { name = "Pell", class = "MAGE", slot = "RANGED", why = "unknown" },
    { name = "Quill", class = "MAGE", slot = "RANGED", why = "no", status = "no" },
    { name = "Bad", class = "ROGUE", slot = "MELEE", invite = true },
    { name = "Offo", class = "MAGE", slot = "RANGED", invite = true },
  },
  plan = { assignments = { { boss = "Al'ar", name = "Brakk", kind = "tank", target = "skull", note = "platform 1" } }, notes = {} } }
GuildOS.CompanionImport = { Current = function() return ROSTER end, OfThisGuild = function() return true end,
  Rescued = function() return {} end, RosterOf = function(_, id) return id == 9 and ROSTER or nil end,
  ActiveRoster = function() return nil end }
check(RT:SetSourceKind("site") and RT:SourceKind() == "site" and GuildOS.db.raidTools.source == "site",
  "the source chosen is kept")
check(not RT:SetSourceKind("nonsense") and RT:SourceKind() == "site", "and only one of the three")
local site, label = RT:People("site")
local by = {}
for _, p in ipairs(site) do by[p.name] = p end
check(label == "TK", "the site's raid is named by its title")
check(by.Brakk.status == "signed" and by.Brakk.role == "TANK" and by.Brakk.inGroup, "Brakk signed up as a tank and is here")
check(by.Velyra.status == "signed" and not by.Velyra.inGroup, "Velyra signed up and is not here")
check(by.Wren.status == "standby" and by.Tia.status == "tentative" and by.Pell.status == "pending",
  "standby, tentative and no answer read as such")
check(by.Quill == nil, "who said no is left out")
check(by.Ana and by.Ana.status == "extra" and by.Ana.inGroup, "somebody in the group and not on the raid is an extra")
check(select(1, RT:CurrentInstance("site")) == "tk", "the site's raid says which raid the targets are for")
local guildList = RT:People("guild")
check(#guildList == 2, "the guild source is who is online")
local groupList = RT:People("group")
check(#groupList == 2 and groupList[1].inGroup, "the group source is the group, me included")
local gb = {}
for _, p in ipairs(groupList) do gb[p.name] = p end
check(gb.Brakk.role == "TANK", "off the site's source, the site's slot still says the role")
RT:PickInstance("ssc")
check(select(1, RT:CurrentInstance("group")) == "ssc", "the raid picked by hand, off the site's source")

-- ── 3. Invites ─────────────────────────────────────────────────────────
GuildOS.BanList = { IsBanned = function(_, n) return n == "Bad" end, AllianceBansFor = function() return nil end,
  HoldInvite = function(_, n, go) if n == "Bad" then return true end return false end }
G.guild[#G.guild + 1] = { "Velyra", "PRIEST", true }
local res = RT:InviteStep(site)
check(res.kind == "invite" and #G.invited == 1 and G.invited[1] == "Velyra",
  "the invite asks only Velyra: Brakk is here, Bad is banned, Offo is offline, standby and no answer are not asked")
check(#res.skipped.banned == 1 and res.skipped.banned[1].name == "Bad" and #res.skipped.offline == 1,
  "and names who it passed over")
res = RT:InviteStep(site)
check(res.kind == "wait" and #G.invited == 1, "nobody is asked twice inside a minute")
G.now = G.now + 61
res = RT:InviteStep(site)
check(res.kind == "invite" and #G.invited == 2, "after a minute a click asks again")
local held = RT:InviteOne(by.Bad)
check(held and #G.invited == 2, "a banned one's own row holds the invite behind the ban's dialog")
G.combat = true
check(RT:InviteStep(site).kind == "blocked", "no invites in combat")
G.combat = false
G.leader = false
check(RT:InviteStep(site).kind == "blocked", "nor from somebody who is not the leader")
G.leader = true

-- Seats: alone four, a party too small turned into a raid, a raid everyone.
local many = {}
for i = 1, 9 do many[i] = person("P" .. i, "MAGE", "DPS") end
G.party, G.invited = {}, {}
RT._asked = {}
res = RT:InviteStep(many)
check(res.kind == "invite" and #G.invited == 4 and res.left == 5, "alone: the first four")
G.party = { { "P1", "MAGE" }, { "P2", "MAGE" } }
for _, p in ipairs(many) do p.inGroup = (p.name == "P1" or p.name == "P2") end
RT._asked = {}
res = RT:InviteStep(many)
check(res.kind == "convert" and G.converted == 1, "a party too small for the rest becomes a raid first")
G.raid = true
G.invited = {}
res = RT:InviteStep(many)
check(res.kind == "invite" and #G.invited == 7, "a raid: everyone left in one click")
G.raid, G.party = false, {}

-- ── 4. Groups ──────────────────────────────────────────────────────────
local raid = {
  person("T1", "WARRIOR", "TANK"), person("T2", "WARRIOR", "TANK"), person("T3", "PALADIN", "TANK"),
  person("H1", "PRIEST", "HEALER"), person("H2", "DRUID", "HEALER"), person("H3", "SHAMAN", "HEALER"),
  person("H4", "PALADIN", "HEALER"), person("H5", "PRIEST", "HEALER"), person("H6", "SHAMAN", "HEALER"),
  person("M1", "ROGUE", "DPS"), person("M2", "WARRIOR", "DPS"), person("M3", "ROGUE", "DPS"), person("M4", "SHAMAN", "DPS"),
  person("R1", "HUNTER", "DPS"), person("R2", "HUNTER", "DPS"), person("C1", "MAGE", "DPS"), person("C2", "MAGE", "DPS"),
  person("C3", "WARLOCK", "DPS"), person("C4", "WARLOCK", "DPS"), person("C5", "PRIEST", "DPS"), person("C6", "MAGE", "DPS"),
  person("P1", "PALADIN", "DPS"), person("S1", "SHAMAN", "DPS"), person("D1", "DRUID", "DPS"), person("C7", "MAGE", "DPS"),
}
GuildOS.db.members[GuildOS:GetPlayerKey("M4")] = { spec = "Enhancement" }
local parties = RT.SuggestGroups(raid, 5)
local seen, total, shamanParties = {}, 0, 0
for g = 1, 5 do
  check(#parties[g] <= 5, "party " .. g .. " holds five at most")
  local sh = 0
  for _, p in ipairs(parties[g]) do
    check(not seen[p.key], p.name .. " is in one party only")
    seen[p.key] = true
    total = total + 1
    if p.class == "SHAMAN" then sh = sh + 1 end
  end
  if sh > 0 then shamanParties = shamanParties + 1 end
end
check(total == 25, "all 25 have a party")
check(shamanParties == 4, "four shamans, four parties with one")
local tanksIn1 = 0
for _, p in ipairs(parties[1]) do if p.role == "TANK" then tanksIn1 = tanksIn1 + 1 end end
check(tanksIn1 == 3, "the tanks stand together in the first party")
local paladinParties = 0
for g = 1, 5 do for _, p in ipairs(parties[g]) do if p.class == "PALADIN" and p.role ~= "TANK" then paladinParties = paladinParties + 1 end end end
check(paladinParties == 2, "the paladins are placed")
check(RT.PartyCoverage({ person("a", "SHAMAN"), person("b", "PALADIN") }).totems and not RT.PartyCoverage({ person("a", "MAGE") }).totems,
  "a party's coverage: totems with a shaman, none without")
local words = RT.CoverageWords({ person("a", "MAGE") })
check(words[1].ok == false and words[2].ok == false, "a party of casters lacks totems and an aura")
check(#RT.SuggestGroups({ person("a", "MAGE") }) == 1, "one person: one party")

-- Moves: only who is out of place; a full party swaps.
local lines5 = {
  { index = 1, group = 1, key = "a" }, { index = 2, group = 1, key = "b" }, { index = 3, group = 2, key = "c" },
}
local moves = RT.PlanMoves(lines5, { a = 1, b = 2, c = 2 }, true)
check(#moves == 1 and moves[1].index == 2 and moves[1].group == 2, "only b moves; a and c are in place")
local function fullRaid()
  local full = { { index = 6, group = 1, key = "x" } }
  for i = 1, 5 do full[#full + 1] = { index = i, group = 2, key = "g2_" .. i } end
  return full
end
moves = RT.PlanMoves(fullRaid(), { x = 2, g2_3 = 1 }, true)
check(#moves == 1 and moves[1].index == 6 and moves[1].swap == 3,
  "into a full party, a swap with the one whose own party is the mover's")
check(#RT.PlanMoves(fullRaid(), { x = 2 }, false) == 0, "no swap planned where the client cannot")
check(RT:ApplyGroups({}) == nil, "apply refuses outside a raid")
G.raid = true
G.party = { { "A1", "MAGE", 1 }, { "A2", "MAGE", 1 } }
local n = RT:ApplyGroups({ {}, { { key = GuildOS:GetPlayerKey("A2") } } })
check(n == 1 and G.moves[1][1] == 2 and G.moves[1][2] == 2, "apply moves A2 to party 2 through the game")
G.combat = true
check(RT:ApplyGroups({}) == nil, "never in combat")
G.combat, G.raid, G.party = false, false, {}
local gl = RT.GroupLines({ { person("Alpha", "MAGE"), person("Beta", "MAGE") }, {}, { person("Gamma", "MAGE") } })
check(#gl == 1 and gl[1] == "G1: Alpha, Beta / G3: Gamma", "the parties said in one line, the empty ones left out, never a bare | the game refuses")

-- Saying: three lines at most, 240 bytes each, never twice in a few seconds.
local parts = {}
for i = 1, 200 do parts[i] = "Somebody" .. i end
local long = RT.Lines("Head: ", parts)
check(#long == 3, "a long announcement is three lines")
for _, l in ipairs(long) do check(#l <= 243, "each line fits the chat") end
G.said = {}
local said = RT:Say("x", { "one" })
check(said == 1 and #G.said == 0, "out of a group it is printed here, not said")
G.party = { { "Brakk", "WARRIOR" } }
check(RT:Say("y", { "a", "b" }) == 2 and G.said[1].chat == "PARTY", "in a party, the party's chat")
check(RT:Say("y", { "a" }) == nil, "not twice in a few seconds")
G.now = G.now + 9
check(RT:Say("y", { "a" }) == 1, "a few seconds later, again")
-- The parties of a full raid go to the chat (#449: " | " made the game refuse every line, "Said in 0 line(s)").
G.said, G.now = {}, G.now + 9
local full = {}
for g = 1, 5 do
  full[g] = {}
  for k = 1, 5 do full[g][k] = person("Raider" .. g .. k, "MAGE") end
end
local fullLines = RT.GroupLines(full)
check(RT:Say("groups", fullLines) == #fullLines and #G.said == #fullLines, "the groups announcement is said, every line")
-- A site's note or boss name carrying a "|" never reaches the chat raw.
local piped = RT.Lines("Boss|x: ", { "Main tank | Brakk", "Interrupt Kaelis" })
for _, l in ipairs(piped) do check(not l:find("|", 1, true), "no bare | in a line: " .. l) end
-- No line gone: an error, and the next try is not held back.
G.chatDown, G.now = true, G.now + 9
local n0, err0 = RT:Say("down", { "a" })
check(n0 == nil and err0 ~= nil, "a chat that took nothing is an error, never \"Said in 0 line(s)\"")
G.chatDown = false
check(RT:Say("down", { "a" }) == 1, "and the retry is not blocked for the next seconds")
-- One part longer than a line (25 names missing): split on its names, every line within the chat's limit,
-- never a line that is the head alone, never a cut through a character.
local many = {}
for i = 1, 25 do many[i] = { name = "Personagemlongo" .. i .. "-Realm" } end
local ml = RT.MissingLines({}, many)
check(#ml >= 2 and #ml <= 3, "25 names missing: two or three lines (" .. #ml .. ")")
for i, l in ipairs(ml) do
  check(#l <= 243, "missing line " .. i .. " fits the chat (" .. #l .. " bytes)")
  check(l ~= "Raid: " and l:gsub("%s", "") ~= "Raid:", "missing line " .. i .. " is more than the head")
end
local ul = RT.Lines("H: ", { string.rep("\195\169", 400) })
for _, l in ipairs(ul) do
  check(#l <= 243 and GuildOS:CutBytes(l, #l) == l and not l:find("[\195][^\128-\191]") and not l:find("\195$"),
    "an overlong part is cut on a whole character")
end
local rl0 = RT.ReadyLines((function() local r = {} for i = 1, 30 do r[i] = { name = "Somebodylong" .. i, cons = 1 } end return r end)())
for _, l in ipairs(rl0) do check(#l <= 243, "a ready line fits the chat") end
G.party = {}

-- ── 5. Readiness ───────────────────────────────────────────────────────
GuildOS.Readiness = { GetReport = function(_, target)
  return {
    { key = GuildOS:GetPlayerKey("Brakk"), missCons = 1, hasGear = true, missEnch = 0, targetOk = target ~= nil or nil },
    { key = GuildOS:GetPlayerKey("Velyra"), missCons = 0, hasGear = true, missEnch = 0, targetOk = (target == nil) and nil or false },
  }
end }
GuildOS.Resistances = { SCHOOLS = { { key = "arcane", label = "Arcane", target = 75 } } }
GuildOS.db.members[GuildOS:GetPlayerKey("Brakk")] = { lastUpdate = 5, resistances = { arcane = 80 } }
local rows, school = RT:ReadyRows({ person("Brakk", "WARRIOR", "TANK"), person("Velyra", "PRIEST", "HEALER"),
  person("Nobody", "MAGE", "DPS"), person("Wren", "DRUID", "HEALER", "standby") }, "tk")
check(school and school.key == "arcane" and #rows == 3, "Tempest Keep asks for arcane; standby is not checked")
local rb = {}
for _, row in ipairs(rows) do rb[row.name] = row end
check(rb.Velyra.status == "notready" and rows[1].name == "Velyra", "not attuned is not ready, and first")
check(rb.Brakk.status == "warn" and rb.Brakk.resistOk and rb.Brakk.addon, "a flask missing is to check")
check(rb.Nobody.status == "nodata" and not rb.Nobody.addon, "nothing synced and no addon: no data")
local sum = RT.ReadySummary(rows)
check(sum.warn == 1 and sum.notready == 1 and sum.nodata == 1, "the summary counts each verdict")
local rl = RT.ReadyLines(rows)
check(#rl == 1 and rl[1]:find("consumables: Brakk", 1, true) and rl[1]:find("not attuned: Velyra", 1, true)
  and rl[1]:find("no GuildOS: Velyra, Nobody", 1, true), "what is missing, in one line")

-- ── 6. Assignments ─────────────────────────────────────────────────────
GuildOS.RaidPlan = { KINDS = { tank = "Tank", interrupt = "Interrupt" }, Current = function() return ROSTER.plan, ROSTER end }
local bosses = RT:Bosses("tk", ROSTER)
check(bosses[1] == "Al'ar" and #bosses == 4, "Tempest Keep's four bosses")
local a, from = RT:Assignments("tk", "Al'ar", ROSTER)
check(from == "plan" and a[1].who == "Brakk" and a[1].task == "Tank: platform 1" and a[1].mark == "skull",
  "a boss the site planned starts from the plan")
local d, dfrom = RT:Assignments("tk", "Void Reaver", ROSTER)
check(dfrom == "default" and #d == 4 and d[1].task == "Main tank" and d[1].who == nil, "an unplanned boss starts from the default tasks")
a[2] = { task = "Interrupt", who = "Kaelis", mark = "cross" }
a[3] = { task = "", who = nil }
a[4] = { task = "  Heal MT  ", who = "Velyra", mark = "nonsense" }
check(RT:SaveAssignments("tk", "Al'ar", a), "saved")
local back, bfrom = RT:Assignments("tk", "Al'ar", ROSTER)
check(bfrom == "saved" and #back == 3 and back[3].task == "Heal MT" and back[3].mark == nil,
  "loaded back: the empty row dropped, the text trimmed, an unknown mark dropped")
local al = RT.AssignmentLines("Al'ar", back)
check(#al == 1 and al[1] == "Al'ar: Tank: platform 1 Brakk {skull} · Interrupt Kaelis {cross} · Heal MT Velyra",
  "the announcement: the boss, each task, its person and mark")
check(#RT.AssignmentLines("Al'ar", { { task = "x" } }) == 0, "nobody assigned: nothing to say")
RT:SaveAssignments("tk", "Al'ar", nil)
check(select(2, RT:Assignments("tk", "Al'ar", ROSTER)) == "plan", "forgetting a boss goes back to the plan")
local thirteen = {}
for i = 1, 13 do thirteen[i] = { task = "t" .. i, who = "W" } end
RT:SaveAssignments("ssc", "Hydross the Unstable", thirteen)
check(#GuildOS.db.raidTools.assign.ssc["Hydross the Unstable"] == 12, "twelve rows at most")

-- ── 7. The HUD ─────────────────────────────────────────────────────────
local base = { enabled = true, hidden = false, inRaid = true, lead = true, tracked = 5 }
local function with(k, v) local s = {} for kk, vv in pairs(base) do s[kk] = vv end s[k] = v return s end
check(HUD.ShouldShow(base), "on, in a raid, as its leader: shown")
check(not HUD.ShouldShow(with("enabled", false)), "switched off: never shown, combat or not")
check(not HUD.ShouldShow(with("hidden", true)), "hidden: not shown")
check(not HUD.ShouldShow(with("inRaid", false)), "out of a raid: not shown")
check(not HUD.ShouldShow(with("lead", false)) and HUD.ShouldShow(with("everyone", true)),
  "a raider sees it only when the raid leader's switch says everyone")
check(not HUD.ShouldShow(with("tracked", 0)), "nothing to track: not shown")
check(HUD:IsEnabled(), "on unless switched off")
HUD:SetEnabled(false)
check(not HUD:IsEnabled() and GuildOS.db.settings.modules.raidHUD == false, "the switch is the Settings feature's")
local st = HUD:State()
check(not HUD.ShouldShow(st), "switched off, the HUD's own state says hidden")
HUD:SetEnabled(true)
local defs = RT:TrackedCooldowns()
check(#defs > 0, "TBC tracks cooldowns")
check(HUD:OnCombatLog("SPELL_CAST_SUCCESS", "Oruk", 0x514, 2825, 100), "a raid shaman's Bloodlust starts its timer")
check(not HUD:OnCombatLog("SPELL_CAST_SUCCESS", "Stranger", 0x548, 2825, 100), "an outsider's never")
check(not HUD:OnCombatLog("SPELL_AURA_APPLIED", "Oruk", 0x514, 2825, 100), "only a cast counts")
local hrows = HUD.Rows(defs, { Oruk = "SHAMAN", Tessa = "SHAMAN", Lun = "DRUID" }, HUD.state, 160)
local bl
for _, row in ipairs(hrows) do if row.key == "bloodlust" then bl = row end end
check(bl and bl.ready == 1 and bl.total == 2 and math.floor(bl.soonest) == 540 and bl.nextIn == nil,
  "Bloodlust: one of two ready, the other back in nine minutes")
local onlyOruk = HUD.Rows(defs, { Oruk = "SHAMAN" }, HUD.state, 160)
check(onlyOruk[1].ready == 0 and math.floor(onlyOruk[1].nextIn) == 540, "none ready: when the next one is back")
check(HUD.Clock(540) == "9m" and HUD.Clock(45) == "45s", "the clock")
-- The tick redraws into the same tables (#449 review): no table made once the rows exist.
local mem = { Oruk = "SHAMAN", Tessa = "SHAMAN", Lun = "DRUID" }
local lists = HUD.CasterLists(defs, mem)
local outRows = HUD.RowsInto({}, defs, mem, lists, HUD.state, 160)
local firstRow, firstWho = outRows[1], outRows[1].who[1]
local again = HUD.RowsInto(outRows, defs, mem, lists, HUD.state, 170)
check(again == outRows and again[1] == firstRow and again[1].who[1] == firstWho and #again == #hrows,
  "the next tick fills the same rows")
-- The combat log only while the HUD shows; the raid read on a roster change, never on the tick.
do
  local registered, unregistered = 0, 0
  local oldReg = GuildOS.Compat.RegisterEvent
  GuildOS.Compat.RegisterEvent = function(_, e) if e == "COMBAT_LOG_EVENT_UNFILTERED" then registered = registered + 1 end return true end
  HUD._logFrame.UnregisterEvent = function(_, e) if e == "COMBAT_LOG_EVENT_UNFILTERED" then unregistered = unregistered + 1 end end
  local reads = 0
  local oldInfo = GetRaidRosterInfo
  GetRaidRosterInfo = function(i) reads = reads + 1; return oldInfo(i) end
  local shown = false
  HUD.frame = { IsShown = function() return shown end, SetShown = function(_, v) shown = v end }
  local oldRefresh = HUD.Refresh
  HUD.Refresh = function() end
  G.raid, G.leader, G.party = true, true, { { "Oruk", "SHAMAN" }, { "Lun", "DRUID" } }
  HUD:ListenToLog(false)
  registered, unregistered = 0, 0
  HUD:Update()
  check(shown and registered == 1 and HUD._listening, "in a raid with the HUD up, the combat log is listened to")
  check(reads == 2 and HUD._members.Oruk == "SHAMAN", "and the raid is read once, on the update")
  HUD:Update()
  check(registered == 1, "registered once, not again on every update")
  HUD.Refresh = oldRefresh
  G.raid, G.party = false, {}
  HUD.Refresh = function() end
  HUD:Update()
  check(not shown and unregistered == 1 and not HUD._listening, "out of the raid the combat log is let go")
  HUD.Refresh = oldRefresh
  HUD.frame, GetRaidRosterInfo, GuildOS.Compat.RegisterEvent = nil, oldInfo, oldReg
  G.leader = nil
end
for _, row in ipairs(hrows) do check(row.total > 0, "a row only for a cooldown somebody can cast") end
local src = assert(io.open(ADDON .. "/Modules/RaidHUD.lua", "rb")):read("*a")
check(src:find("f.link:SetShown(not combat and not collapsed)", 1, true),
  "in combat the HUD shows the cooldowns and nothing else")

-- ── 8. WoW: Forever: one invite a click, Onyxia, no HUD ─────────────────
RT, HUD = load("forever")
check(RT:Instance("tk") == nil and RT:Instance("forever-onyxia").size == 40, "Forever's raids are its own")
check(not HUD:State().enabled and not HUD.ShouldShow(HUD:State()), "no cooldown HUD off TBC (it reads the combat log, ADR-0014)")
check(#RT:TrackedCooldowns() > 0 and not GuildOS.Compat.CanReadCombatLog(),
  "Forever has the cooldown list but not a combat log to time it (Secret Values in an encounter, Compat.CanReadCombatLog)")
local fl = {}
for i = 1, 6 do fl[i] = person("F" .. i, "MAGE", "DPS") end
G.raid, G.party = true, { { "Ana", "PALADIN" } }
local fres = RT:InviteStep(fl)
check(fres.kind == "invite" and #G.invited == 1 and fres.left == 5, "Forever: one invite a click")
fres = RT:InviteStep(fl)
check(#G.invited == 2 and G.invited[2] == "F2", "the next click, the next one")

print(("raid-tools: %d checks passed"):format(checks))
