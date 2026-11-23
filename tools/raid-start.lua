-- The Iniciar raide stepper (issue #400; the site's #603, spec 115): one button that walks the raid's leader
-- through invite, convert, invite the rest and arrange, one click a step, each step decided from the group as it
-- is at that moment. Run against the real Utils, Compat and CompanionImport under a stubbed WoW: Forever client
-- ("Chehul Costa": UnitName gives the first name only), with a stubbed group, guild roster, combat and secrets.
--
--   luajit -e 'ADDON="."' tools/raid-start.lua
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

-- ── A secret value, as tools/secret-values.lua makes one: every use of it raises ─────────────
local SECRET_MT = {}
local function refuse() error("secret value used", 2) end
for _, k in ipairs({ "__index", "__newindex", "__concat", "__call", "__eq", "__lt", "__le", "__add", "__sub",
                     "__mul", "__div", "__mod", "__unm", "__pow", "__len" }) do
  SECRET_MT[k] = refuse
end
local function secret() return setmetatable({}, SECRET_MT) end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end

-- ── The client: WoW: Forever, no realm (the client answers "" since 2026-11-21, issue #394) ──
local NOW = 1791000000
local ME = "Chehul Costa"
function GetServerTime() return NOW end
function time() return NOW end
-- The client's clock: the invites keep who they asked by it, for a minute.
local CLOCK = 1000
function GetTime() return CLOCK end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function debugstack() return "" end
function IsInGuild() return true end
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 99, 1, 5
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function UnitFullName() return "Chehul", "Costa" end
function GetRealmName() return "" end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
StaticPopupDialogs = {}
Enum = { SendAddonMessageResult = {} }

-- The group as the client sees it: { name, raid group, the unit's second answer, the raid roster line's name }.
-- The last two are for the name shapes nobody has read on WoW: Forever yet (issue #48): a unit may answer the
-- surname apart, ("Ana", "Lima"), and a roster line the first name alone. In a group GROUP[1] is me; a party's
-- units are the others.
local GROUP, RAID = {}, false
local LEADER, ASSIST, COMBAT = true, false, false
function GetNumGroupMembers() return #GROUP end
function IsInRaid() return RAID end
function IsInGroup() return #GROUP > 0 end
function UnitName(unit)
  if unit == "player" then return "Chehul" end
  local kind, i = tostring(unit):match("^(%a+)(%d+)$")
  i = tonumber(i)
  -- As the game: raidN exists only in a raid, partyN only in a party.
  local g = (kind == "raid" and RAID and GROUP[i]) or (kind == "party" and not RAID and i and GROUP[i + 1])
  if g then return g[1], g[3] end
end
function UnitClass() return "Warrior", "WARRIOR" end
function GetRaidRosterInfo(i)
  local g = RAID and GROUP[i]
  if g then return g[4] or g[1], 0, g[2] end
end
-- Alone, nobody leads anything: the client answers false, so "alone may invite" is Compat's to say.
function UnitIsGroupLeader(unit) if unit == "player" and #GROUP > 0 then return LEADER end return false end
function UnitIsGroupAssistant(unit) if unit == "player" and #GROUP > 0 then return ASSIST end return false end
function InCombatLockdown() return COMBAT end
-- In a raid I am raid1 (GROUP[1]); a party's units are the others.
function UnitIsUnit(a, b) return a == b or (b == "player" and RAID and a == "raid1") end
local REMOVED = {}

local INVITED, CONVERTED, MOVES = {}, 0, {}
C_PartyInfo = {
  InviteUnit = function(name) INVITED[#INVITED + 1] = name end,
  ConvertToRaid = function() CONVERTED = CONVERTED + 1 end,
  UninviteUnit = function(unit) REMOVED[#REMOVED + 1] = unit end,
}
function SetRaidSubgroup(i, group)
  MOVES[#MOVES + 1] = "set:" .. GROUP[i][1] .. "->" .. group
  GROUP[i][2] = group
end
function SwapRaidSubgroup(a, b)
  MOVES[#MOVES + 1] = "swap:" .. GROUP[a][1] .. "<>" .. GROUP[b][1]
  GROUP[a][2], GROUP[b][2] = GROUP[b][2], GROUP[a][2]
end

-- The guild: { name, online }, read through GetGuildRosterInfo's first and ninth answers.
local GUILD = {}
function GetNumGuildMembers() return #GUILD end
function GetGuildRosterInfo(i)
  local r = GUILD[i]
  if r then return r[1], "Raider", 3, 60, "Warrior", "", "", "", r[2] end
end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
  minor = 1,
}, {
  __call = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
})

GuildOS = {
  VERSION = "0.0.0",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true } },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Compat.lua")
function GuildOS:Print() end
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
local Import, RS, Compat = GuildOS.CompanionImport, GuildOS.RaidStart, GuildOS.Compat
check(GuildOS.Client.game == "FOREVER" and GuildOS.Client.has.surnames, "the stub is a WoW: Forever client")
check(Compat.PlayerName() == ME, "my name is the whole one, with the surname")
check(type(RS) == "table" and type(RS.Next) == "function" and type(RS.Run) == "function", "RaidStart:Next and :Run exist")
for _, fn in ipairs({ "ConvertToRaid", "SetRaidSubgroup", "SwapRaidSubgroup", "IsLeaderOrAssist", "IsGroupLeader" }) do
  check(type(Compat[fn]) == "function", "Compat." .. fn .. " exists")
end

-- ── The plan: me and eight more from the site, and Rui, a guildmate the site never confirmed ───
local function plan(people, startsAt, id)
  local members = {}
  for _, p in ipairs(people) do
    members[#members + 1] = { key = p[1], name = p[1], class = "WARRIOR", spec = "", slot = "MELEE", group = p[2] }
  end
  return { raidId = id or "r", title = "Onyxia", startsAt = startsAt or NOW, members = members, signups = {} }
end
local TEN = plan({ { ME, 1 }, { "Ana Lima", 1 }, { "Bia Souza", 1 }, { "Caio Dias", 1 }, { "Duda Rocha", 1 },
                   { "Edu Prado", 2 }, { "Fabi Melo", 2 }, { "Gil Nunes", 2 }, { "Pug Visitante", 2 } })
TEN.signups = { { name = "Rui Novato", class = "", spec = "", slot = "RANGED", status = "yes", invite = false,
                  why = "unknown", group = 0 } }
-- Everyone but Pug is a guildmate; Duda is offline.
GUILD = { { ME, true }, { "Ana Lima", true }, { "Bia Souza", true }, { "Caio Dias", true }, { "Duda Rocha", false },
          { "Edu Prado", true }, { "Fabi Melo", true }, { "Gil Nunes", true }, { "Rui Novato", true } }

-- A fresh scenario: a minute and more after the last, so no invite of it is still waiting on its answer.
local WAIT = 60
local function reset()
  INVITED, CONVERTED, MOVES = {}, 0, {}
  LEADER, ASSIST, COMBAT = true, false, false
  CLOCK = CLOCK + WAIT + 1
end
local function has(list, name)
  for _, v in ipairs(list or {}) do if v == name then return true end end
  return false
end
local function join(list) return table.concat(list or {}, ",") end
local function person(name, group) return { name, group } end

-- ── 1. Alone: invite the first four, never me, never an offline guildmate ──────────────────────
reset()
GROUP, RAID = {}, false
local step = RS:Next(TEN)
check(step.kind == "invite4" and step.count == 4, "alone: invite4 with four (" .. step.kind .. " " .. tostring(step.count) .. ")")
check(has(step.offline, "Duda Rocha") and #step.offline == 1, "alone: the offline guildmate is named, not invited")
check(type(step.label) == "string" and step.label:find("4", 1, true), "the label says what the next click does: " .. tostring(step.label))
local done = RS:Run(TEN)
check(done.kind == "invite4" and done.count == 4, "the click invites four")
check(join(INVITED) == "Ana Lima,Bia Souza,Caio Dias,Edu Prado",
  "the first four of the plan's order, Duda skipped for being offline: " .. join(INVITED))
check(not has(INVITED, ME) and not has(INVITED, "Chehul"), "the owner is never invited, by either name")
check(CONVERTED == 0 and #MOVES == 0, "inviting converts and moves nothing")

-- ── Invites awaiting their answer: never asked twice in a minute ──────────────────────────────
-- A second click while the four have not answered invites nobody: they hold the party's seats.
INVITED = {}
step = RS:Next(TEN)
check(step.kind == "blocked" and step.reason == "Waiting for the invited to answer.",
  "a second click within the minute waits on the four (" .. step.kind .. " " .. tostring(step.reason) .. ")")
check(#step.waiting == 4 and has(step.waiting, "Ana Lima"), "the step names who it is waiting on")
RS:Run(TEN)
check(#INVITED == 0, "and its click invites nobody: " .. join(INVITED))
local n0, _, why0 = Import:InviteAll(TEN)
check(n0 == nil and why0 == "Waiting for the invited to answer.", "the old Invite says the same: " .. tostring(why0))
-- Ana accepts: a party of two. The plan outgrows it, so convert; the three still waiting are not asked again.
GROUP, RAID = { person(ME, 1), person("Ana Lima", 1) }, false
step = RS:Next(TEN)
check(step.kind == "convert" and step.count == 4, "a party of two with three waiting and four left converts (" .. step.kind .. " " .. tostring(step.count) .. ")")
RS:Run(TEN)
check(CONVERTED == 1 and #INVITED == 0, "the convert click converts only")
GROUP, RAID = { person(ME, 1), person("Ana Lima", 1) }, true
step = RS:Next(TEN)
check(step.kind == "inviteRest" and step.count == 4, "right after the convert, the rest are the four never asked (" .. tostring(step.count) .. ")")
RS:Run(TEN)
check(join(INVITED) == "Fabi Melo,Gil Nunes,Pug Visitante,Rui Novato",
  "the first wave still waiting is not asked again: " .. join(INVITED))
-- A minute on, nobody else answered: the next click asks the ones still missing again, the retry.
CLOCK = CLOCK + WAIT
INVITED = {}
step = RS:Next(TEN)
check(step.kind == "inviteRest" and step.count == 7, "after the minute, invite the rest comes back for all seven (" .. tostring(step.count) .. ")")
-- The waiting hold party seats: a party of three with two waiting and one left is more than a party, so convert.
reset()
local SIX = plan({ { ME, 1 }, { "Ana Lima", 1 }, { "Bia Souza", 1 }, { "Caio Dias", 1 }, { "Edu Prado", 2 }, { "Fabi Melo", 2 } })
GROUP, RAID = {}, false
RS:Run(SIX)
check(join(INVITED) == "Ana Lima,Bia Souza,Caio Dias,Edu Prado", "a roster of six: the first four are asked")
GROUP = { person(ME, 1), person("Ana Lima", 1), person("Bia Souza", 1) }
step = RS:Next(SIX)
check(step.kind == "convert" and step.count == 1, "three here, two waiting, one left: convert (" .. step.kind .. ")")
GROUP, RAID = {}, false

-- An owner who did not sign up is not in the plan, and still not invited.
reset()
local notMine = plan({ { "Ana Lima", 1 }, { "Bia Souza", 1 } })
RS:Run(notMine)
check(join(INVITED) == "Ana Lima,Bia Souza", "a plan without me invites only the plan")

-- ── 2. A party with somebody in it: convert, and invite nobody yet ─────────────────────────────
reset()
GROUP, RAID = { person(ME, 1), person("Ana Lima", 1) }, false
step = RS:Next(TEN)
check(step.kind == "convert", "a party of two with seven more to bring converts (" .. step.kind .. ")")
check(step.count == 7, "convert says how many are left to invite: " .. tostring(step.count))
done = RS:Run(TEN)
check(done.kind == "convert" and CONVERTED == 1 and #INVITED == 0, "the click converts once and invites nobody")
-- Not the party's leader: nothing to do but say so (a party has no assistants).
reset()
LEADER = false
step = RS:Next(TEN)
check(step.kind == "blocked" and type(step.reason) == "string" and step.reason ~= "", "not leading the party is blocked, with a reason")
RS:Run(TEN)
check(CONVERTED == 0 and #INVITED == 0, "a blocked click does nothing")

-- ── 3. A raid with people missing: invite the rest ─────────────────────────────────────────────
reset()
GROUP, RAID = { person(ME, 1), person("Ana Lima", 1), person("Bia Souza", 3) }, true
step = RS:Next(TEN)
check(step.kind == "inviteRest" and step.count == 6, "a raid of three invites the six left (" .. step.kind .. " " .. tostring(step.count) .. ")")
done = RS:Run(TEN)
check(done.count == 6 and join(INVITED) == "Caio Dias,Edu Prado,Fabi Melo,Gil Nunes,Pug Visitante,Rui Novato",
  "the rest: the guildmate the game vouches for and somebody outside the guild included: " .. join(INVITED))
check(done.here == 3, "three of the plan are already here: " .. tostring(done.here))
-- An assistant invites too.
reset()
LEADER, ASSIST = false, true
check(RS:Next(TEN).kind == "inviteRest", "an assistant of the raid gets the same step")
-- Neither leader nor assistant: blocked.
reset()
LEADER, ASSIST = false, false
step = RS:Next(TEN)
check(step.kind == "blocked" and step.reason == "Only the group's leader or an assistant can invite.",
  "neither leader nor assistant is blocked, and the reason says leader or assistant: " .. tostring(step.reason))
-- The client keeps who leads secret: blocked, never an error.
reset()
LEADER, ASSIST = secret(), secret()
local ok, got = pcall(RS.Next, RS, TEN)
check(ok and got.kind == "blocked", "a secret leader read is blocked, not an error: " .. tostring(ok and got.kind or got))
check(Compat.IsLeaderOrAssist() == false and Compat.IsGroupLeader() == false, "a secret answer counts as no")
ok = pcall(RS.Run, RS, TEN)
check(ok and #INVITED == 0, "and the click invites nobody")

-- ── 4. Everyone here, some in the wrong group: arrange ─────────────────────────────────────────
local function everyone()
  -- Caio wants 1 and is in 2; Fabi wants 2 and is in 1; Pug wants 2 and is in 3; Rui has no group and is left be.
  return { person(ME, 1), person("Ana Lima", 1), person("Bia Souza", 1), person("Caio Dias", 2),
           person("Edu Prado", 2), person("Fabi Melo", 1), person("Gil Nunes", 2), person("Pug Visitante", 3),
           person("Rui Novato", 3) }
end
reset()
GROUP, RAID = everyone(), true
step = RS:Next(TEN)
check(step.kind == "arrange" and step.count == 3, "all here, three out of place: arrange 3 (" .. step.kind .. " " .. tostring(step.count) .. ")")
check(step.label:find("3", 1, true), "the arrange label carries the count: " .. step.label)
-- In combat the game will not move anyone: blocked, with a reason, and the groups untouched.
COMBAT = true
step = RS:Next(TEN)
check(step.kind == "blocked" and step.reason == "Not during combat.", "in combat arrange is blocked with a reason: " .. tostring(step.reason))
local moved, why = Import:OrganizeGroups(TEN)
check(moved == nil and why == "Not during combat." and #MOVES == 0, "OrganizeGroups refuses in combat and moves nobody")
COMBAT = false
done = RS:Run(TEN)
check(done.kind == "arrange" and done.count == 3, "the click puts the three in place: " .. tostring(done.count))
check(join(MOVES) == "set:Caio Dias->1,set:Fabi Melo->2,set:Pug Visitante->2", "one move each, into a group with a seat: " .. join(MOVES))
check(not join(MOVES):find("Rui", 1, true), "somebody without a planned group is never moved")
-- ── 9. Everything in place: done ───────────────────────────────────────────────────────────────
step = RS:Next(TEN)
check(step.kind == "done", "everyone here and in their group: done (" .. step.kind .. ")")
check(has(step.offline, "Duda Rocha"), "done still names who was offline")

-- A no-show: Gil is asked and never comes. The button goes on to the groups and to done meanwhile, and asks him
-- again once his minute is out.
reset()
local noShow = everyone()
table.remove(noShow, 7)
GROUP, RAID = noShow, true
step = RS:Next(TEN)
check(step.kind == "inviteRest" and step.count == 1, "Gil missing: invite the rest, one (" .. step.kind .. ")")
RS:Run(TEN)
check(join(INVITED) == "Gil Nunes", "Gil is asked: " .. join(INVITED))
INVITED = {}
step = RS:Next(TEN)
check(step.kind == "arrange" and step.count == 3 and has(step.waiting, "Gil Nunes"),
  "a no-show does not hold the button: arrange while he is waiting (" .. step.kind .. ")")
RS:Run(TEN)
check(#INVITED == 0 and #MOVES == 3, "the arrange click moves the three and asks nobody")
check(RS:Next(TEN).kind == "done", "and then the raid is done while Gil has not answered")
CLOCK = CLOCK + WAIT
step = RS:Next(TEN)
check(step.kind == "inviteRest" and step.count == 1, "his minute out, invite the rest comes back: the retry (" .. step.kind .. ")")

-- ── 5. Into a full group: a swap, with the one who belongs where the mover is ─────────────────
local SWAP = plan({ { ME, 1 }, { "A1 Um", 1 }, { "A2 Dois", 1 }, { "A3 Tres", 1 }, { "D4 Quatro", 1 },
                    { "E5 Cinco", 2 }, { "F6 Seis", 2 }, { "G7 Sete", 2 }, { "H8 Oito", 2 }, { "I9 Nove", 2 } })
GUILD = {}
reset()
-- Group 1 is full and holds E5 (planned for 2) and X, who is not in the plan; group 2 is full and holds D4 (planned for 1).
GROUP, RAID = { person(ME, 1), person("D4 Quatro", 2), person("A1 Um", 1), person("A2 Dois", 1), person("X Estranho", 1),
                person("E5 Cinco", 1), person("F6 Seis", 2), person("G7 Sete", 2), person("H8 Oito", 2),
                person("I9 Nove", 2), person("A3 Tres", 3) }, true
-- A3 is in group 3 and wants 1, which is full: D4's swap places D4, and A3 then swaps with X, who is outside the plan.
step = RS:Next(SWAP)
check(step.kind == "arrange" and step.count == 3, "three out of place, groups full: arrange 3 (" .. step.kind .. " " .. tostring(step.count) .. ")")
moved = Import:OrganizeGroups(SWAP)
check(MOVES[1] == "swap:D4 Quatro<>E5 Cinco", "a full group swaps, with the one whose own group is the mover's: " .. join(MOVES))
check(MOVES[2] == "swap:A3 Tres<>X Estranho", "and with somebody outside the plan when nobody planned is left to trade: " .. join(MOVES))
check(#MOVES == 2 and moved == 3, "three placed in two swaps, nobody left out silently: " .. tostring(moved))
check(GROUP[5][2] == 3, "the stranger is moved only as a swap's other half")
check(RS:Next(SWAP).kind == "done", "after the swaps the raid is done")
-- A group full of people who belong there takes nobody, and the stepper does not ask to arrange forever.
reset()
GROUP, RAID = { person(ME, 1), person("A1 Um", 1), person("A2 Dois", 1), person("A3 Tres", 1), person("D4 Quatro", 1),
                person("E5 Cinco", 2), person("F6 Seis", 2), person("G7 Sete", 2), person("H8 Oito", 2),
                person("I9 Nove", 2) }, true
local over = plan({ { ME, 1 }, { "A1 Um", 1 }, { "A2 Dois", 1 }, { "A3 Tres", 1 }, { "D4 Quatro", 1 }, { "E5 Cinco", 1 },
                    { "F6 Seis", 2 }, { "G7 Sete", 2 }, { "H8 Oito", 2 }, { "I9 Nove", 2 } })
step = RS:Next(over)
check(step.kind == "done", "a sixth planned for a full group of the plan's own cannot be placed: done (" .. step.kind .. ")")
check(Import:OrganizeGroups(over) == 0 and #MOVES == 0, "and nobody is moved")
-- Without SwapRaidSubgroup the swap is not made, and nothing raises.
reset()
GROUP, RAID = { person(ME, 1), person("D4 Quatro", 2), person("A1 Um", 1), person("A2 Dois", 1), person("A3 Tres", 1),
                person("E5 Cinco", 1), person("F6 Seis", 2), person("G7 Sete", 2), person("H8 Oito", 2),
                person("I9 Nove", 2) }, true
local swap = SwapRaidSubgroup
SwapRaidSubgroup = nil
check(Compat.CanSwapRaidSubgroup() == false, "a client without the call cannot swap")
ok, moved = pcall(Import.OrganizeGroups, Import, SWAP)
check(ok and moved == 0 and #MOVES == 0, "no swap call: nothing placed, nothing raised: " .. tostring(moved))
step = RS:Next(SWAP)
check(step.kind == "done", "and the stepper does not offer an arrange that would move nobody (" .. step.kind .. ")")
SwapRaidSubgroup = swap
check(Compat.CanSwapRaidSubgroup() == true, "a client with it can")
-- A raid line the client keeps secret is passed over, and still holds its seat.
reset()
GROUP[11] = { secret(), 3 }
ok, moved = pcall(Import.OrganizeGroups, Import, SWAP)
check(ok and moved == 2, "a secret raid line does not raise: " .. tostring(moved))
GROUP[11] = nil

-- ── WoW: Forever's name shapes (issue #48): the surname apart, the first name alone, the hyphen ─
local function line(name, group, second, rosterName) return { name, group, second, rosterName } end
GUILD = {}
-- A unit that answers ("Ana", "Lima") is Ana Lima, and a raid roster line that says "Ana" is her too.
reset()
local ANA = plan({ { ME, 1 }, { "Ana Lima", 2 }, { "Bia Souza", 1 } })
GROUP, RAID = { person(ME, 1), line("Ana", 1, "Lima", "Ana") }, true
step = RS:Next(ANA)
check(step.kind == "inviteRest" and step.count == 1, "the unit's surname apart is joined: only Bia is left (" .. step.kind .. ")")
RS:Run(ANA)
check(join(INVITED) == "Bia Souza", "Ana Lima is not asked: " .. join(INVITED))
GROUP[3] = person("Bia Souza", 1)
step = RS:Next(ANA)
check(step.kind == "arrange" and step.count == 1, "the roster line 'Ana' is the one planned Ana: arrange 1 (" .. step.kind .. ")")
RS:Run(ANA)
check(join(MOVES) == "set:Ana->2", "and she moves to her group: " .. join(MOVES))
-- "Ana-Lima", the way the game's folders write it, is Ana Lima too, in the unit and in the roster line.
reset()
GROUP, RAID = { person(ME, 1), line("Ana-Lima", 1), person("Bia Souza", 1) }, true
step = RS:Next(ANA)
check(step.kind == "arrange" and step.count == 1, "a hyphen-joined name is the spaced one (" .. step.kind .. ")")
-- Two planned Anas: a bare "Ana" is neither of them, and both are invited.
reset()
local TWO = plan({ { ME, 1 }, { "Ana Lima", 1 }, { "Ana Souza", 2 } })
GROUP, RAID = { person(ME, 1), line("Ana", 1) }, true
step = RS:Next(TWO)
check(step.kind == "inviteRest" and step.count == 2, "two planned of one first name: a bare 'Ana' is neither (" .. tostring(step.count) .. ")")
RS:Run(TWO)
check(join(INVITED) == "Ana Lima,Ana Souza", "and both are invited: " .. join(INVITED))
-- The surname apart still tells them apart: ("Ana", "Souza") is Ana Souza, and only Ana Lima is left.
reset()
GROUP, RAID = { person(ME, 1), line("Ana", 1, "Souza") }, true
step = RS:Next(TWO)
check(step.kind == "inviteRest" and step.count == 1, "a unit's surname apart names one of two Anas (" .. tostring(step.count) .. ")")
-- Two raid lines that both read "Ana", one Ana planned: neither is known to be her, so nobody moves, and a pug of
-- that first name stays where he is.
reset()
local ONE = plan({ { ME, 1 }, { "Ana Lima", 2 } })
GROUP, RAID = { person(ME, 1), line("Ana", 1), line("Ana", 3) }, true
step = RS:Next(ONE)
check(step.kind == "done", "two lines for one planned person: no arrange (" .. step.kind .. ")")
check(Import:OrganizeGroups(ONE) == 0 and #MOVES == 0, "and neither line is moved: " .. join(MOVES))
-- TBC Anniversary and retail have no surnames: no first-name fallback, and a hyphen is no space there.
local client = GuildOS.Client
local was = { client.has.surnames, client.isAnniversary, client.isRetail }
for _, c in ipairs({ { "Anniversary", true, false }, { "retail", false, true } }) do
  reset()
  client.has.surnames, client.isAnniversary, client.isRetail = false, c[2], c[3]
  local bare = plan({ { "Ana Lima", 2 }, { "Bia Souza", 1 } })
  GROUP, RAID = { person("Chehul", 1), line("Ana", 1), line("Bia-Souza", 1) }, true
  step = RS:Next(bare)
  check(step.kind == "inviteRest" and step.count == 2,
    c[1] .. ": a bare first name and a hyphen stand for nobody planned (" .. step.kind .. " " .. tostring(step.count) .. ")")
end
client.has.surnames, client.isAnniversary, client.isRetail = was[1], was[2], was[3]

-- ── Fit to plan reads the group as the button does (issue #400, the Task 5 review's M3) ────────
-- The raid the button calls ready: the units answer the surname apart, and nobody planned is outside the plan.
reset()
REMOVED = {}
local READY = plan({ { "Ana Lima", 1 }, { "Bia Souza", 1 } })
GROUP, RAID = { line("Chehul", 1, "Costa"), line("Ana", 1, "Lima", "Ana Lima"), line("Bia", 1, "Souza", "Bia Souza") }, true
check(RS:Next(READY).kind == "done", "the raid with everyone in place is ready")
local out = Import:OutsideThePlan(READY)
check(#out == 0, "and nobody in it is outside the plan, the surname apart or not, the owner neither: " .. join(out))
-- My own unit read without the surname, and me not in the plan: never taken out of my own raid.
GROUP[1] = line("Chehul", 1)
out = Import:OutsideThePlan(READY)
check(#out == 0, "the leader read by the first name alone is still me: " .. join(out))
-- A bare first name one planned person has is that person; one two planned people share could be either, and stays.
GROUP = { person(ME, 1), line("Ana", 1), line("Pug", 2, "Visitante") }
out = Import:OutsideThePlan(READY)
check(join(out) == "Pug Visitante", "a bare 'Ana' is Ana Lima; the pug, his surname joined, is outside: " .. join(out))
GROUP = { person(ME, 1), line("Ana", 1) }
out = Import:OutsideThePlan(TWO)
check(#out == 0, "a bare 'Ana' with two Anas planned could be either: she stays: " .. join(out))
-- And the removal goes by unit, for the pug only.
GROUP = { person(ME, 1), line("Ana", 1, "Lima"), line("Pug", 2, "Visitante") }
GuildOS.db.companionRoster = READY
local removed = Import:TrimToPlan()
GuildOS.db.companionRoster = nil
check(removed == 1 and join(REMOVED) == "raid3", "fitting the group takes out the pug alone, by unit: " .. join(REMOVED))
-- A party: its units are the others, and the same reading holds.
GROUP, RAID = { person(ME, 1), line("Ana", 1, "Lima"), line("Zed", 1, "Outro") }, false
out = Import:OutsideThePlan(READY)
check(join(out) == "Zed Outro", "in a party, only who is outside the plan: " .. join(out))

-- ── 10. A roster that fits a party never converts ──────────────────────────────────────────────
local FOUR = plan({ { ME, 1 }, { "Ana Lima", 1 }, { "Bia Souza", 1 }, { "Caio Dias", 1 } })
GUILD = { { "Ana Lima", true }, { "Bia Souza", true }, { "Caio Dias", true } }
reset()
local seen = {}
for _, g in ipairs({ {}, { person(ME, 1), person("Ana Lima", 1) }, { person(ME, 1), person("Ana Lima", 1), person("Bia Souza", 1) },
                     { person(ME, 1), person("Ana Lima", 1), person("Bia Souza", 1), person("Caio Dias", 1) } }) do
  GROUP, RAID = g, false
  local s = RS:Next(FOUR)
  seen[#seen + 1] = s.kind .. ":" .. tostring(s.count)
  check(s.kind ~= "convert", "a roster of four never converts (" .. #g .. " in the group: " .. s.kind .. ")")
end
check(join(seen) == "invite4:3,invite4:2,invite4:1,done:0", "alone three, then the rest, then done: " .. join(seen))
-- Me and four more fill a party exactly: a party of two with three to come invites them, and never converts.
local FIVE = plan({ { ME, 1 }, { "Ana Lima", 1 }, { "Bia Souza", 1 }, { "Caio Dias", 1 }, { "Duda Rocha", 1 } })
GROUP, RAID = { person(ME, 1), person("Ana Lima", 1) }, false
step = RS:Next(FIVE)
check(step.kind == "invite4" and step.count == 3, "a roster of five in a party of two invites the three (" .. step.kind .. ")")
-- A pug in a full party with the plan's last still to come: that is more than a party, so convert.
GROUP = { person(ME, 1), person("Ana Lima", 1), person("Bia Souza", 1), person("Pug Visitante", 1), person("Zed Outro", 1) }
check(RS:Next(FOUR).kind == "convert", "a full party with somebody still to invite converts")
local n, _, err = Import:InviteAll(FOUR)
check(n == nil and err == "The party is full. Turn it into a raid first.", "the old Invite in a full party says so: " .. tostring(err))

-- ── The old paths act on the raid of the window ────────────────────────────────────────────────
reset()
GUILD = {}
GROUP, RAID = { person(ME, 1) }, true
local tonight = plan({ { ME, 1 }, { "Ana Lima", 2 } }, NOW + 1800, "tonight")
local later = plan({ { ME, 1 }, { "Zed Outro", 1 } }, NOW + 3 * 86400, "later")
Import._webRaids = { later, tonight }
GuildOS.db.companionRoster = later
check(Import:ActiveRoster() == tonight, "the active roster is the raid of the window, not the inbox's first")
Import:InviteAll()
check(join(INVITED) == "Ana Lima", "/gos roster invite and the Web tab invite the raid of the window: " .. join(INVITED))
reset()
Import:InviteAll(Import:Current())
check(join(INVITED) == "Zed Outro", "the paste window acts on the roster it holds")
Import._webRaids = { later }
check(Import:ActiveRoster() == later, "with no raid in the window, the kept roster as before")
Import._webRaids, GuildOS.db.companionRoster = nil, nil
check(Import:ActiveRoster() == nil, "nothing loaded, nothing active")
step = RS:Next(nil)
check(step.kind == "blocked" and type(step.reason) == "string" and step.reason ~= "", "no roster is blocked, with a reason")

-- ── The gates say leader or assistant, and read through the secret guard ───────────────────────
reset()
GROUP, RAID = { person(ME, 1), person("Ana Lima", 1) }, true
LEADER, ASSIST = false, false
local can, reason = Import:CanOrganize(TEN)
check(not can and reason == "Only the raid leader or an assistant can organise groups.", "the groups refusal says leader or assistant: " .. tostring(reason))
can, reason = Import:CanInvite(TEN)
check(not can and reason == "Only the group's leader or an assistant can invite.", "the invite refusal says leader or assistant: " .. tostring(reason))
ASSIST = true
check(Import:CanOrganize(TEN) and Import:CanInvite(TEN), "an assistant may invite and arrange")
can, reason = Import:CanTrim(TEN)
check(not can and reason == "Only the raid leader can remove people from the raid.", "removing stays the leader's alone (issue #292)")
LEADER, ASSIST = secret(), secret()
ok, can = pcall(Import.CanTrim, Import, TEN)
check(ok and not can, "a secret leader read refuses removal without raising")
ok, can = pcall(Import.CanOrganize, Import, TEN)
check(ok and not can, "and refuses arranging without raising")
LEADER, ASSIST = true, false
GROUP = {}
check(Compat.IsLeaderOrAssist() == true and Compat.IsGroupLeader() == false, "alone I may invite, and lead no group")

-- ── Compat: C_PartyInfo's convert where the client has it, the old global otherwise ────────────
reset()
check(Compat.ConvertToRaid() == true and CONVERTED == 1, "ConvertToRaid takes C_PartyInfo's")
local cpi = C_PartyInfo.ConvertToRaid
C_PartyInfo.ConvertToRaid = nil
local globalCalls = 0
ConvertToRaid = function() globalCalls = globalCalls + 1 end
check(Compat.ConvertToRaid() == true and globalCalls == 1, "and the global where C_PartyInfo has none")
ConvertToRaid, C_PartyInfo.ConvertToRaid = nil, cpi
GROUP, RAID = { person(ME, 1), person("Ana Lima", 1) }, true
check(Compat.SetRaidSubgroup(2, 4) == true and GROUP[2][2] == 4, "SetRaidSubgroup moves through Compat")
check(Compat.SwapRaidSubgroup(1, 2) == true and GROUP[1][2] == 4 and GROUP[2][2] == 1, "SwapRaidSubgroup swaps through Compat")
local set = SetRaidSubgroup
SetRaidSubgroup = nil
check(Compat.SetRaidSubgroup(1, 2) == false, "a client without the call answers false")
SetRaidSubgroup = set

-- ── The labels and the lines a click prints ────────────────────────────────────────────────────
check(RS:Label({ kind = "convert", count = 7 }):find("7", 1, true), "the convert label counts who is left")
check(RS:Label({ kind = "inviteRest", count = 6 }):find("6", 1, true), "the invite-the-rest label counts them")
check(RS:Label({ kind = "done", count = 0 }) == "Raid ready", "done says the raid is ready")
check(RS:Label({ kind = "blocked" }) == "Start raid", "blocked keeps the button's name")
local line, off = RS:Say({ kind = "invite4", count = 4, here = 1, offline = { "Duda Rocha" } })
check(line == "Invited 4, already here 1." and off == "Offline, not invited: Duda Rocha", "an invite click says how many and who was offline")
line, off = RS:Say({ kind = "convert", converted = true, count = 7, offline = {} })
check(line == "The group is a raid now. Click again to invite the rest." and off == nil, "a convert click says what comes next")
check(RS:Say({ kind = "blocked", reason = "Not during combat." }) == "Not during combat.", "a blocked click says why")
check(Import.OfflineLine({ "Ana|cffff0000x" }) == "Offline, not invited: Anacffff0000x", "a name off the network cannot colour the line")

print(string.format("raid-start: %d checks passed", checks))
