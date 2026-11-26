-- The owner's prompt before the raid (issue #400; the site's #603, spec 115): when it is shown and that it is shown
-- once. At login or /reload from half an hour before the start to an hour after it, in the game a quarter of an hour
-- before it, once per raid and start (kept in the guild's SavedVariables, a week), only to the owner, only for a raid
-- of the guild this character is in (GOSROST1 v7 `guild`). Also: the login digest gives way to the prompt, the
-- guild roster is asked for at most every 30 seconds while a button shows, a click says its step and repaints the
-- buttons, and the Raid plan follows the raid the buttons act on.
--
-- Run against the real Utils, Compat, CompanionImport, RaidPlan and Digest under a stubbed WoW: Forever client
-- ("Chehul Costa": UnitName gives the first name only) whose inbox holds encoded GOSROST1 blocks, with a clock and
-- timers the test moves by hand.
--
--   luajit -e 'ADDON="."' tools/raid-prompt.lua
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

-- ── The client: WoW: Forever, no realm, in the guild "Filhos da Horda" ────────────────────
local START = 1791000000            -- the raid's start
local MIN, H, DAY = 60, 3600, 86400
local NOW = START
function GetServerTime() return NOW end
function time() return NOW end
local CLOCK = 1000
function GetTime() return CLOCK end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function debugstack() return "" end
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 99, 1, 5
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function UnitName(unit) if unit == "player" then return "Chehul" end end
function UnitFullName() return "Chehul", "Costa" end
function UnitClass() return "Warrior", "WARRIOR" end
function GetRealmName() return "" end
local GUILD = "Filhos da Horda"
function IsInGuild() return GUILD ~= nil end
function GetGuildInfo(unit) if unit == "player" and GUILD then return GUILD, "Officer", 1 end end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function GetNumGroupMembers() return 0 end
function IsInRaid() return false end
function IsInGroup() return false end
function UnitIsGroupLeader() return false end
function UnitIsGroupAssistant() return false end
function InCombatLockdown() return false end
local INVITED = {}
C_PartyInfo = { InviteUnit = function(name) INVITED[#INVITED + 1] = name end }
local ROSTER_ASKS = 0
C_GuildInfo = { GuildRoster = function() ROSTER_ASKS = ROSTER_ASKS + 1 end }

-- Timers the test fires by hand: each { at = the server time it is due, fn }.
local TIMERS = {}
C_Timer = {
  After = function(delay, fn) TIMERS[#TIMERS + 1] = { at = NOW + delay, fn = fn } end,
  NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function() return { Cancel = function() end } end,
}
StaticPopupDialogs = {}
Enum = { SendAddonMessageResult = {} }

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
local PRINTED = {}
function GuildOS:Print(msg) PRINTED[#PRINTED + 1] = msg end
function GuildOS:SafeCall(fn, ...) return true, fn(...) end
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/RaidPlan.lua")
dofile(ADDON .. "/Modules/Digest.lua")
local Import, RS, Plan, Digest = GuildOS.CompanionImport, GuildOS.RaidStart, GuildOS.RaidPlan, GuildOS.Digest
check(GuildOS.Client.game == "FOREVER" and GuildOS.Compat.PlayerName() == "Chehul Costa", "the stub is Chehul Costa on WoW: Forever")
for _, fn in ipairs({ "OnLogin", "PromptedAtLogin", "PromptedSet", "Due", "Click", "AskGuildRoster" }) do
  check(type(RS[fn]) == "function", "RaidStart:" .. fn .. " exists")
end

-- The prompt the UI would show: who it was shown for, in order, and the one on screen (OPEN, until the test closes it).
local SHOWN, OPEN = {}, nil
function GuildOS:ShowRaidPrompt(roster)
  SHOWN[#SHOWN + 1] = roster.raidId .. "@" .. roster.startsAt
  OPEN = roster
end
function GuildOS:RaidPromptShowing() return OPEN end
-- The prompt and the digest go through the one popup queue (audit B21; the queue itself is tools/popup-queue.lua):
-- here it shows at once, out of combat, and the keys it was given are kept.
local QUEUED = {}
function GuildOS:ShowWhenClear(key, fn) QUEUED[key] = (QUEUED[key] or 0) + 1; fn() end
local REPAINTS = 0
function GuildOS:RefreshRaidSteppers() REPAINTS = REPAINTS + 1 end

-- ── The inbox: GOSROST1 v7 blocks, encoded as the companion leaves them ────────────────────
local function json(v)
  if type(v) == "table" then
    if v[1] ~= nil or next(v) == nil then
      local parts = {}
      for i, x in ipairs(v) do parts[i] = json(x) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = json(k) .. ":" .. json(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then
    return '"' .. v:gsub('[\\"]', "\\%0") .. '"'
  end
  return tostring(v)
end
local function block(t)
  local LibDeflate = LibStub("LibDeflate")
  local data = { fmt = "GOSROST1", v = 7, raidId = t.id, title = t.title or "Onyxia", startsAt = t.at, size = 10,
                 members = t.members or { { key = "Ana Lima", name = "Ana Lima", class = "WARRIOR", slot = "MELEE", group = 1 } },
                 owners = t.owners or { "Chehul Costa" }, guild = t.guild, instanceKey = t.instanceKey }
  return "GOSROST1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json(data)))
end

-- A new session, at `now`, with these blocks in Inbox.lua: what Core's InitModules does (the inbox read), then the
-- prompt's turn. SavedVariables (GuildOS.db) carry over; everything else is the session's.
local function login(now, blocks)
  NOW, CLOCK = now, CLOCK + 2 * DAY
  TIMERS, SHOWN, PRINTED, OPEN = {}, {}, {}, nil
  Import._lastInbox, Import._webRaids, Import._foreignLine, Import._foreignSaid = nil, nil, nil, nil
  RS._armed, RS._loginPrompt = nil, nil
  Digest.deferred, Digest.shownThisSession = nil, nil
  _G.GuildOSInbox = blocks
  Import:ConsumeInbox()
  return RS:OnLogin()
end
-- The clock moves on to `to`, and every timer due by then fires, in order.
local function advance(to)
  NOW = to
  table.sort(TIMERS, function(a, b) return a.at < b.at end)
  local due = {}
  for i = #TIMERS, 1, -1 do
    if TIMERS[i].at <= to then table.insert(due, 1, TIMERS[i]); table.remove(TIMERS, i) end
  end
  for _, t in ipairs(due) do t.fn() end
end
local function fresh() GuildOS.db = { settings = { companion = true } } end
local function shown() return table.concat(SHOWN, ",") end

-- ── 1. Login twenty minutes before: the prompt, once ────────────────────────────────────────
fresh()
login(START - 20 * MIN, { block({ id = "ony", at = START }) })
check(shown() == "ony@" .. START, "a login twenty minutes before the start prompts the owner: " .. shown())
check(RS:PromptedAtLogin(), "and says so, for the digest")
check(GuildOS.db.raidPrompted["ony:" .. START] == START - 20 * MIN, "remembered by raidId:startsAt, in SavedVariables")
advance(START - 15 * MIN)
check(#SHOWN == 1, "its quarter-hour timer asks nothing more: " .. shown())
advance(START + 2 * H)
check(#SHOWN == 1, "nor does anything later: " .. shown())
check(#INVITED == 0, "the login's prompt invites nobody: on WoW: Forever an invite is a click's, the button's")

-- ── 2. A second login for the same raid and start ───────────────────────────────────────────
login(START - 10 * MIN, { block({ id = "ony", at = START }) })
check(#SHOWN == 0 and not RS:PromptedAtLogin(), "a second login for the same raid and start does not prompt: " .. shown())
login(START + 30 * MIN, { block({ id = "ony", at = START }) })
check(#SHOWN == 0, "nor a /reload half an hour into the raid")

-- ── 3. The raid moved: another start asks again ─────────────────────────────────────────────
login(START + H - 20 * MIN, { block({ id = "ony", at = START + H }) })
check(shown() == "ony@" .. (START + H), "the same raid moved an hour later prompts again: " .. shown())

-- ── 4. Login forty-five minutes before: nothing yet, then the quarter-hour timer ───────────────
fresh()
login(START - 45 * MIN, { block({ id = "bwl", at = START }) })
check(#SHOWN == 0 and not RS:PromptedAtLogin(), "a login forty-five minutes before does not prompt: " .. shown())
check(#TIMERS == 1 and TIMERS[1].at == START - 15 * MIN, "it arms one timer, for a quarter of an hour before the start")
advance(START - 16 * MIN)
check(#SHOWN == 0, "a minute before the timer, still nothing")
advance(START - 15 * MIN)
check(shown() == "bwl@" .. START, "the quarter-hour timer prompts: " .. shown())
check(not RS:PromptedAtLogin(), "a timer's prompt is not the login's")
check(#INVITED == 0, "and a timer invites nobody either: only a click does")
login(START - 5 * MIN, { block({ id = "bwl", at = START }) })
check(#SHOWN == 0, "and the login after it does not prompt again")

-- A raid a day away still gets its timer; one shown on another character meanwhile is not asked again.
fresh()
login(START - DAY, { block({ id = "far", at = START }) })
check(#SHOWN == 0 and #TIMERS == 1 and TIMERS[1].at == START - 15 * MIN, "a raid a day away gets its timer too")
GuildOS.db.raidPrompted["far:" .. START] = START - 20 * MIN   -- the owner's other character was asked
advance(START - 15 * MIN)
check(#SHOWN == 0, "a timer whose prompt another login showed asks nothing")

-- ── 5. Login an hour and a half after the start: too late ──────────────────────────────────────
fresh()
login(START + 90 * MIN, { block({ id = "mc", at = START }) })
check(#SHOWN == 0 and #TIMERS == 0, "a login an hour and a half after the start neither prompts nor arms: " .. shown())

-- ── The edges of the login window: from thirty minutes before to an hour after ─────────────────
fresh()
login(START - 30 * MIN, { block({ id = "e1", at = START }) })
check(#SHOWN == 1, "thirty minutes before is inside")
fresh()
login(START - 30 * MIN - 1, { block({ id = "e2", at = START }) })
check(#SHOWN == 0 and #TIMERS == 1, "a second more is outside, and waits for its timer")
fresh()
login(START + H, { block({ id = "e3", at = START }) })
check(#SHOWN == 1, "an hour after is inside")
fresh()
login(START + H + 1, { block({ id = "e4", at = START }) })
check(#SHOWN == 0, "a second more is outside")
fresh()
login(START - 10 * MIN, { block({ id = "e5", at = START }) })
check(#SHOWN == 1 and #TIMERS == 0, "ten minutes before prompts, and arms no timer already past")

-- Two owned raids inside the window: the nearest is the login's; the other still has its timer.
fresh()
login(START - 20 * MIN, { block({ id = "late", at = START + 5 * MIN }), block({ id = "near", at = START }) })
check(shown() == "near@" .. START, "two in the window: the nearest prompts: " .. shown())
OPEN = nil   -- put off
advance(START - 10 * MIN)
check(shown() == "near@" .. START .. ",late@" .. (START + 5 * MIN), "and the other at its quarter hour: " .. shown())
OPEN = nil
advance(START + H)
check(#SHOWN == 2, "and neither again: " .. shown())

-- A second raid's quarter hour while the first raid's prompt is still being worked: it waits, two minutes at a time.
fresh()
login(START - 20 * MIN, { block({ id = "first", at = START }), block({ id = "second", at = START + 10 * MIN }) })
check(shown() == "first@" .. START, "the first raid prompts at login")
advance(START - 5 * MIN)
check(#SHOWN == 1 and OPEN and OPEN.raidId == "first", "the second's quarter hour leaves the first's prompt in place: " .. shown())
check(#TIMERS == 1 and TIMERS[1].at == START - 3 * MIN, "and asks again two minutes later")
check(GuildOS.db.raidPrompted["second:" .. (START + 10 * MIN)] == nil, "not marked shown meanwhile")
advance(START - 3 * MIN)
check(#SHOWN == 1, "still waiting while the first's step is not done: " .. shown())
OPEN = nil   -- the first is put off
advance(START - MIN)
check(shown() == "first@" .. START .. ",second@" .. (START + 10 * MIN), "then the second prompts: " .. shown())
-- The first raid ready (nothing left to do): the second takes its place at once.
fresh()
login(START - 20 * MIN, { block({ id = "ready", at = START, members = {} }), block({ id = "next", at = START + 10 * MIN }) })
check(shown() == "ready@" .. START and RS:Next(OPEN).kind == "done", "a first raid whose step is done")
advance(START - 5 * MIN)
check(shown() == "ready@" .. START .. ",next@" .. (START + 10 * MIN), "gives its place to the second: " .. shown())
check(#INVITED == 0, "no timer, retry or prompt invites anybody")
-- The first raid's prompt is up, but a pasted copy of that raid has nothing left to do: the second takes its place.
fresh()
login(START - 20 * MIN, { block({ id = "first", at = START }), block({ id = "second", at = START + 10 * MIN }) })
Import:Load(block({ id = "first", at = START, members = { { key = "Chehul Costa", name = "Chehul Costa", group = 1 } } }))
advance(START - 5 * MIN)
check(shown() == "first@" .. START .. ",second@" .. (START + 10 * MIN),
  "the first's step read on its pasted copy is done: the second prompts at once: " .. shown())
-- A second raid kept waiting past the hour after its start asks nothing: that late, the prompt would be news of a raid
-- long under way. The retries stop there.
fresh()
login(START - 20 * MIN, { block({ id = "long", at = START }), block({ id = "after", at = START + 10 * MIN }) })
for t = START - 5 * MIN, START + 71 * MIN, 2 * MIN do advance(t) end
check(shown() == "long@" .. START, "an hour past the second's start, it never prompted: " .. shown())
check(#TIMERS == 0, "and stopped asking")
OPEN = nil
advance(START + 2 * H)
check(#SHOWN == 1 and GuildOS.db.raidPrompted["after:" .. (START + 10 * MIN)] == nil,
  "not even once the first is put off, and it is not marked shown")

-- ── 6. Not mine: never ─────────────────────────────────────────────────────────────────────────
fresh()
login(START - 20 * MIN, { block({ id = "theirs", at = START, owners = { "Fulano Lima", "Chehul" } }) })
check(#SHOWN == 0 and #TIMERS == 0, "a raid whose owners are others (my first name alone is not me) never prompts")
login(START - 45 * MIN, { block({ id = "theirs", at = START, owners = { "Fulano Lima" } }) })
advance(START)
check(#SHOWN == 0, "nor from its timer")
login(START - 20 * MIN, { block({ id = "nobody", at = START, owners = {} }) })
check(#SHOWN == 0, "a raid with no owners never prompts")

-- ── 7. Another guild's roster: never acted on ──────────────────────────────────────────────────
fresh()
login(START - 20 * MIN, { block({ id = "other", at = START, guild = "Horda Unida" }) })
check(#SHOWN == 0 and #TIMERS == 0, "another guild's raid never prompts")
check(Import._webRaids == nil and Import:ButtonRaid() == nil and Import:ActiveRoster() == nil,
  "it is not read at all: no raid for the buttons")
check(GuildOS.db.companionRoster == nil and GuildOS.db.companionRaids == nil, "nor kept, nor matched to a night")
local upserted = {}
GuildOS.Calendar = { UpsertWebRaid = function(_, roster) upserted[#upserted + 1] = roster.raidId end }
Import:CalendarFromInbox()
check(#upserted == 0, "nor put on the calendar")
login(START - 20 * MIN, { block({ id = "other", at = START, guild = "Horda Unida" }),
                          block({ id = "ours", at = START + 10 * MIN, guild = "FILHOS DA HORDA" }),
                          block({ id = "old", at = START + 20 * MIN }) })
check(shown() == "ours@" .. (START + 10 * MIN), "this guild's raid prompts, the name compared without case: " .. shown())
check(#Import._webRaids == 2 and Import:ButtonRaid().raidId == "ours", "the buttons act on this guild's raid only")
upserted = {}
Import:CalendarFromInbox()
check(table.concat(upserted, ",") == "ours,old", "the calendar gets this guild's raid and the one from an older site: "
  .. table.concat(upserted, ","))
GuildOS.Calendar = nil
GUILD = nil
login(START - 20 * MIN, { block({ id = "ours2", at = START, guild = "Filhos da Horda" }) })
check(#SHOWN == 0 and Import._webRaids == nil, "a character with no guild acts on no raid that names one")
GUILD = "Filhos da Horda"
-- Pasted by hand, another guild's roster is taken (a federation core's leader in guild B running guild A's raid, the
-- site's spec 089; ruling R9), with a line saying whose it is. The buttons act on it; the calendar, the prompt and
-- the raid tracker's nights, which read the inbox's raids, never see it.
fresh()
login(START - 20 * MIN, { block({ id = "ours3", at = START + 40 * MIN, instanceKey = "onyxia" }) })
PRINTED, SHOWN, INVITED = {}, {}, {}
local n = Import:Load(block({ id = "core", at = START, guild = "Horda |cffff0000Unida", instanceKey = "onyxia" }))
check(n == 1 and GuildOS.db.companionRoster.raidId == "core", "a pasted roster of another guild loads")
check(PRINTED[1] == "That roster is a raid of the guild Horda cffff0000Unida: the raid buttons act on it, and it stays off this guild's calendar.",
  "with a line saying whose raid it is, the name made inert: " .. tostring(PRINTED[1]))
check(Import:ButtonRaid().raidId == "core" and Import:ActiveRoster().raidId == "core", "the buttons act on it")
local res = RS:Click(Import:ButtonRaid())
check(res.kind == "invite4" and INVITED[1] == "Ana Lima", "and its click invites its people: " .. tostring(res.kind))
upserted = {}
GuildOS.Calendar = { UpsertWebRaid = function(_, roster) upserted[#upserted + 1] = roster.raidId end }
Import:CalendarFromInbox()
check(table.concat(upserted, ",") == "ours3", "the calendar gets the inbox's raid of this guild, not the pasted one: "
  .. table.concat(upserted, ","))
GuildOS.Calendar = nil
SHOWN = {}
RS:OnLogin()
check(#SHOWN == 0 and not RS:Due(GuildOS.db.companionRoster), "it never prompts, though its owners name me")
check(#GuildOS.db.companionRaids == 1 and GuildOS.db.companionRaids[1].raidId == "ours3"
  and Import:RaidFor("onyxia", START) == "ours3", "and the raid tracker's nights hold the inbox's raid, never the pasted one")
check(Import:Load(block({ id = "pasted", at = START, guild = "Filhos da Horda" })) == 1, "this guild's is loaded")
-- ── The guild's name as the site compares it: capitals aside past ASCII, the brackets aside ───────
local Same, Fold = GuildOS.SameGuildName, GuildOS.FoldCase
check(Same("Ébano Negro", "ébano negro") and Same("ÉBANO NEGRO", "Ébano Negro"), "Latin-1 capitals fold: Ébano Negro")
check(Same("ОРДЕН СВЕТА", "орден света") and Same("Орден Света", "оРДЕН сВЕТА"), "Cyrillic capitals fold: Орден Света")
check(Same("ЁЛКА ЂАК", "ёлка ђак") and Same("ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞ", "àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþ"),
  "every Latin-1 capital and Ѐ-Џ fold too")
check(Fold("×") == "×" and Fold("÷") == "÷", "the × and ÷ signs are not letters")
check(not Same("Ébano Negro", "Ebano Negro"), "an accent is another letter, as on the site")
check(not Same("Орден Света", "Орден Тьмы") and not Same("Filhos da Horda", "Horda Unida"), "another guild is another guild")
check(Same("  <Filhos da Horda>  ", "filhos da horda") and Same("<>", "<>") and not Same("<>", ""),
  "the brackets around the whole name go, as on the site; a name of brackets alone keeps them")
check(not Same("Filhos  da Horda", "Filhos da Horda"), "inner spaces count, as on the site (bareGuildName only trims)")
check(not Same(nil, "x") and not Same("x", 7), "no name is no guild")
-- End to end: a guild with accents, and a Cyrillic one, keep their raids.
fresh()
GUILD = "ébano negro"
login(START - 20 * MIN, { block({ id = "eb", at = START, guild = "Ébano Negro" }) })
check(shown() == "eb@" .. START and Import:ButtonRaid().raidId == "eb", "a guild named with an accent keeps its raids")
check(GuildOS.db.companionRaids ~= nil and Import:ForeignLine() == nil, "matched to its nights, and nothing said")
GUILD = "Орден Света"
login(START - 20 * MIN, { block({ id = "ru", at = START, guild = "ОРДЕН СВЕТА" }) })
check(shown() == "ru@" .. START, "a Cyrillic guild keeps its raids, capitals aside")
-- The guild's block reads the same way.
local LibDeflate = LibStub("LibDeflate")
_G.GuildOSInbox = { "GOSGILD1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json({ fmt = "GOSGILD1", guild = "орден света", at = NOW }))) }
check(Import:GuildBlock() ~= nil, "the guild's block is read for a Cyrillic guild, capitals aside")
GUILD = "Орден Тьмы"
check(Import:GuildBlock() == nil, "and not for another guild")

-- ── A site whose raids are all another guild's says so, once a session ──────────────────────────
fresh()
GUILD = "Filhos da Horda"
login(START - 20 * MIN, { block({ id = "o1", at = START, guild = "Horda |cffff0000Unida" }), block({ id = "o2", at = START, guild = "Outra" }) })
local said = "The website's raids are for the guild Horda cffff0000Unida, not Filhos da Horda."
check(#SHOWN == 0 and #PRINTED == 1 and PRINTED[1] == said, "said in chat, the site's guild and this one named, inert: " .. tostring(PRINTED[1]))
check(Import:ForeignLine() == said, "and kept for the Web tab's reason line")
Import._lastInbox = nil
Import:ConsumeInbox()
check(#PRINTED == 1, "once a session, however often the inbox is read")
-- Read again with one raid of this guild in it, the line is gone.
_G.GuildOSInbox = { block({ id = "o3", at = START, guild = "Outra" }), block({ id = "ours", at = START + 5 * MIN }) }
Import._lastInbox = nil
Import:ConsumeInbox()
check(#PRINTED == 1 and Import:ForeignLine() == nil, "an inbox with one raid of this guild says nothing, and keeps no line")
GUILD = nil
login(START - 20 * MIN, { block({ id = "o4", at = START, guild = "Outra" }) })
check(#PRINTED == 0 and Import:ForeignLine() == "The website's raids are for the guild Outra, and this character is in none.",
  "a character with no guild is told so on the Web tab, and not in chat at every login: " .. tostring(PRINTED[1]))
GUILD = "Filhos da Horda"

-- Parse reads the guild: a string, cut.
local parsed = Import:Parse(block({ id = "p", at = START, guild = string.rep("x", 200) }))
check(parsed and #parsed.guild == 96, "Parse cuts the guild name to 96 bytes")
parsed = Import:Parse(block({ id = "p", at = START }))
check(parsed and parsed.guild == nil, "a roster that names no guild has none")

-- ── 8. What is over a week old is forgotten ─────────────────────────────────────────────────────
fresh()
GuildOS.db.raidPrompted = { ["old:1"] = START - 8 * DAY, ["recent:1"] = START - 6 * DAY, ["junk:1"] = "x" }
login(START - 2 * H, { block({ id = "x", at = START }) })
local set = GuildOS.db.raidPrompted
check(set["old:1"] == nil and set["junk:1"] == nil, "a prompt shown over a week ago is forgotten, and junk with it")
check(set["recent:1"] == START - 6 * DAY, "one shown six days ago is kept")

-- ── The digest gives way to the login's prompt ──────────────────────────────────────────────────
local digestShown
Digest.Build = function() return { "a line" } end
Digest.MarkFeedSeen = function() end
Digest.Show = function() digestShown = true end
fresh()
GuildOS.db.digest = { enabled = true, lastSeen = START - DAY, feedSeen = {} }
login(START - 20 * MIN, { block({ id = "d", at = START }) })
digestShown = false
Digest.shownThisSession = nil
Digest:ShowOnLogin()
check(not digestShown and GuildOS.db.digest.lastSeen == START - DAY, "with the prompt up, the digest waits, its news untouched")
-- Raid ready closes the prompt and tells nobody: the digest keeps waiting, for the next login.
local loginRoster = OPEN
RS:PromptDismissed({ raidId = "another", startsAt = START })
check(not digestShown, "putting off another raid's prompt does not bring the login's digest")
-- Later, or the close button: the digest has its turn now.
RS:PromptDismissed(loginRoster)
check(digestShown and GuildOS.db.digest.lastSeen == NOW, "the login's prompt put off: the digest shows")
check(not RS:PromptedAtLogin(), "and the login's prompt is no longer up")
-- Put off before the digest's own moment: it simply comes at its time.
GuildOS.db.digest.lastSeen = START - DAY
login(START - 25 * MIN, { block({ id = "d2", at = START }) })
digestShown = false
RS:PromptDismissed(OPEN)
check(not digestShown, "put off before the digest's turn, nothing shows early")
Digest:ShowOnLogin()
check(digestShown, "and the digest shows at its turn")
login(START + 2 * H, { block({ id = "d", at = START }) })
Digest.shownThisSession = nil
Digest:ShowOnLogin()
check(digestShown and GuildOS.db.digest.lastSeen == NOW, "with no prompt, the digest shows as before")

-- ── Later asks again later (audit B18); the close button does not ───────────────────────────────
fresh()
login(START - 14 * MIN, { block({ id = "l", at = START }) })
check(#SHOWN == 1, "the login's prompt shows")
local laterRoster = OPEN
OPEN = nil
RS:PromptDismissed(laterRoster, true)
advance(START - 5 * MIN)
check(#SHOWN == 1, "Later: nothing before ten minutes")
advance(START - 4 * MIN)
check(#SHOWN == 2 and SHOWN[2] == "l@" .. START, "Later: the prompt asks again ten minutes on")
OPEN = nil
RS:PromptDismissed(laterRoster, false)
advance(START + 30 * MIN)
check(#SHOWN == 2, "the close button puts it off for good, as before")
RS:PromptDismissed(laterRoster, true)
OPEN = nil
advance(START + 45 * MIN)
check(#SHOWN == 3, "Later again: asks again")
OPEN = nil
NOW = START + 55 * MIN
RS:PromptDismissed(laterRoster, true)
advance(START + 3 * H)
check(#SHOWN == 3, "but never past an hour after the start")

-- ── A click, from any button or /gos raid start: the step, said, and the buttons repainted ───────
fresh()
login(START - 20 * MIN, { block({ id = "c", at = START }) })
PRINTED, INVITED, REPAINTS = {}, {}, 0
local result = RS:Click(Import:ActiveRoster())
check(result.kind == "invite4" and INVITED[1] == "Ana Lima", "a click invites, alone: " .. tostring(result.kind))
check(PRINTED[1] == "Invited 1, already here 0.", "and says it: " .. tostring(PRINTED[1]))
check(REPAINTS == 1, "and every button on screen reads the group again")
-- /gos raid start: on the raid near now only, its line after the raid's name; none near, it says so.
SlashCmdList = SlashCmdList or {}
dofile(ADDON .. "/Core/Commands.lua")
PRINTED, INVITED = {}, {}
CLOCK = CLOCK + DAY   -- Ana's invite has had its minute
SlashCmdList.GUILDOS("raid start")
check(INVITED[1] == "Ana Lima" and PRINTED[1] == "Onyxia · Invited 1, already here 0.",
  "/gos raid start invites on the raid near now, and names it: " .. tostring(PRINTED[1]))
GuildOS.db.companionRoster = { raidId = "far", title = "Far", startsAt = START + 3 * DAY, members = { { name = "Zed Outro" } } }
Import._webRaids = { GuildOS.db.companionRoster }
PRINTED, INVITED = {}, {}
SlashCmdList.GUILDOS("raid start")
check(#INVITED == 0 and PRINTED[1] == "No raid from the site starts around this time.",
  "with only a raid days away it invites nobody and says no raid starts now: " .. tostring(PRINTED[1]))

-- ── The guild roster is asked for while a button shows, at most every thirty seconds ─────────────
ROSTER_ASKS = 0
CLOCK = CLOCK + DAY
check(RS:AskGuildRoster() and ROSTER_ASKS == 1, "a button shown asks the server for the guild roster")
CLOCK = CLOCK + 29
check(not RS:AskGuildRoster() and ROSTER_ASKS == 1, "not again within thirty seconds")
CLOCK = CLOCK + 1
check(RS:AskGuildRoster() and ROSTER_ASKS == 2, "and again after them")
GUILD = nil
CLOCK = CLOCK + 60
check(not RS:AskGuildRoster() and ROSTER_ASKS == 2, "never with no guild")
GUILD = "Filhos da Horda"

-- ── The Raid plan is the plan of the raid the buttons act on ─────────────────────────────────────
fresh()
GuildOS.db.companionRoster = { raidId = "kept", title = "Kept", startsAt = START + 3 * DAY, members = {},
                               plan = { notes = { { boss = "Kept boss", text = "k" } } } }
Import._webRaids = { { raidId = "tonight", title = "Tonight", startsAt = START, members = {},
                       plan = { notes = { { boss = "Onyxia", text = "o" } } } } }
NOW = START - 10 * MIN
local plan, roster = Plan:Current()
check(roster and roster.raidId == "tonight" and plan and plan.notes[1].boss == "Onyxia",
  "the plan is tonight's, the raid of the buttons, not the kept roster's: " .. tostring(roster and roster.raidId))
NOW = START + 5 * H
plan, roster = Plan:Current()
check(roster and roster.raidId == "kept", "outside the window, the kept roster's, as before")
Import._webRaids = nil

check((QUEUED.raidprompt or 0) > 0 and (QUEUED.digest or 0) > 0, "the prompt and the digest went through the popup queue")
print(string.format("raid-prompt: %d checks passed", checks))
