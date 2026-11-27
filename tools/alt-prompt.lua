-- The one question about one's own characters (#449), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/CommSystem.lua, Modules/AltSync.lua, Modules/AltAutoDetect.lua and Modules/AltDeparture.lua.
--
-- The login prompt asked again on every login, every /reload and every character of the account ("Not now" was
-- this session only), re-asked a whole group declined for good as soon as one character joined it, and asked again
-- whatever an officer did with the links. Five characters, a login and a reload each for three days, always
-- "Not now": 30 prompts before, 3 now (a day apart, never more than three times), all five in one.
--
--   luajit -e 'ADDON="."' tools/alt-prompt.lua
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

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local regen
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) regen = fn end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
local now = 1800000000
function GetServerTime() return now end
function GetTime() return now end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local afters = {}
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
local combat = false
function InCombatLockdown() return combat end

local CH = { "Ana", "Bia", "Cid", "Duda", "Eva" }
local ROSTER = { { "Off", 1 } }
for _, c in ipairs(CH) do ROSTER[#ROSTER + 1] = { c, 5 } end
ROSTER[#ROSTER + 1] = { "Stranger", 5 }
local me, guids = "Ana", {}
function UnitName() return me end
function UnitGUID() return guids[me] end
function UnitLevel() return 70 end
function UnitClass() return "Warrior", "WARRIOR" end
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1] .. "-Realm", "Rank", r[2] end end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
  return "Guild", "Rank", 5
end

local registry, store, n = {}, {}, 0
LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, store[s] end return false end
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/AltSync.lua")
dofile(ADDON .. "/Modules/AltAutoDetect.lua")
dofile(ADDON .. "/Modules/AltDeparture.lua")
local CS, AD, AS, DEP = GuildOS.CommSystem, GuildOS.AltAutoDetect, GuildOS.AltSync, GuildOS.AltDeparture
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data) sent[#sent + 1] = { t = msgType, data = data } end
GuildOS.CommSystem.BroadcastAltLinks = function() end

local K = function(name) return GuildOS:GetPlayerKey(name, "Realm") end
local KEYS = {}
for i, c in ipairs(CH) do KEYS[i] = K(c) end

-- The prompt's window: what it was asked, and the answer the player gives (nil: closed, a Not now).
local shown, answer = {}, nil
local window = { IsShown = function() return true end }
GuildOS.ShowAltPrompt = function(_, plan, manual)
  shown[#shown + 1] = { plan = plan, manual = manual }
  if answer then answer(plan) end
  return window
end

-- The popup queue (Core/Utils.lua) is the real one in section 5; elsewhere a popup gets its turn at once.
local realShow = GuildOS.ShowWhenClear
GuildOS.ShowWhenClear = function(_, _, fn) fn() end

local function account(levels)
  GuildOSDB = { accountChars = {} }
  for i, c in ipairs(CH) do
    GuildOSDB.accountChars[K(c)] = { name = c, level = (levels and levels[i]) or (70 - i), class = "WARRIOR" }
  end
  GuildOS.db = { settings = { officerMaxRank = 1 }, altLinks = {} }
  AD._asksTable = nil
end
-- One session on `who`: Initialize's timers, then the popup queue as the game would pump it.
local function session(who)
  me = who
  AD._prompted = nil
  afters = {}
  AD:_SchedulePrompt()
  local timers = afters
  afters = {}
  for _, fn in ipairs(timers) do fn() end
end
local function names(list)
  local out = {}
  for i, k in ipairs(list) do out[i] = k:match("^([^-]+)") end
  table.sort(out)
  return table.concat(out, ",")
end

-- ── 1. The spam count: five characters, a login and a reload each, three days, Not now ──
account()
shown, answer = {}, nil
for day = 1, 3 do
  for _, c in ipairs(CH) do
    session(c)   -- login
    session(c)   -- /reload
  end
  check(#shown == day, ("day %d: one prompt in the day, whatever the logins and reloads (%d)"):format(day, #shown))
  now = now + 86400
end
check(#shown == 3, "three days of Not now: 3 prompts (30 before #449)")
check(#shown[1].plan.list == 4 and shown[1].plan.main == KEYS[1] and names(shown[1].plan.list) == "Bia,Cid,Duda,Eva",
  "one prompt lists every other character of the account, under the highest level")
for day = 4, 10 do
  session(CH[day % 5 + 1])
  now = now + 86400
end
check(#shown == 3, "never more than three times in all")

-- A /reload with the window up counts as a Not now: shown, not answered, not asked again the same day.
account()
shown, answer = {}, nil
session("Ana")
session("Ana")
check(#shown == 1, "a reload mid-prompt: the next session does not ask again that day")
now = now + 86400
session("Bia")
check(#shown == 2, "the next day it does")

-- ── 2. Don't ask again is for good: every character, reload, day, main change, guild re-join ──
account()
shown = {}
answer = function(plan) AD:Decline(plan) end
session("Ana")
check(#shown == 1, "asked once")
answer = nil
for d = 1, 5 do
  for _, c in ipairs(CH) do session(c) end
  now = now + 86400
end
check(#shown == 1, "declined: no prompt on any character, any day")
GuildOS.db = { settings = { officerMaxRank = 1 }, altLinks = { [KEYS[3]] = KEYS[2] } }   -- a new guild db, another main
session("Cid")
check(#shown == 1, "a guild left and joined again, a main changed: still declined (the account's answer)")
-- A sixth character on the account: asked about alone.
ROSTER[#ROSTER + 1] = { "Fil", 5 }
GuildOSDB.accountChars[K("Fil")] = { name = "Fil", level = 10 }
GuildOS.db.altLinks = {}
session("Fil")
check(#shown == 2 and names(shown[2].plan.list) == "Fil", "a new character: the prompt names it alone, not the declined group")
local offered = {}
for _, k in ipairs(shown[2].plan.choices) do offered[k] = true end
check(not offered[K("Fil")] and offered[KEYS[1]] and shown[2].plan.main == KEYS[1], "and offers the others as its main")
table.remove(ROSTER)

-- The old "Don't ask again" (a group's signature) is kept as declined pairs.
account()
local sig = { KEYS[1], KEYS[2], KEYS[3], KEYS[4], KEYS[5] }
table.sort(sig)
GuildOSDB.altDeclined = { [table.concat(sig, "|")] = true }
shown = {}
session("Ana")
check(#shown == 0 and GuildOSDB.altDeclined == nil, "a group declined before #449 stays declined, as pairs")
AD:ResetAnswers()
session("Bia")
check(#shown == 1, "/gos myalts reset forgets the answers")

-- ── 3. Link all, and Choose... ──────────────────────────────────────────
account()
shown, sent = {}, {}
answer = function(plan) AD:Accept(plan, plan.main) end
session("Bia")
answer = nil
check(GuildOS.db.altLinks[KEYS[2]] == KEYS[1] and GuildOS.db.altLinks[KEYS[5]] == KEYS[1] and GuildOS.db.altLinks[KEYS[1]] == nil,
  "Link all: every character an alt of the main chosen, on the member's view")
local claim
for _, m in ipairs(sent) do if m.t == "SA" then claim = store[m.data] end end
check(claim and claim.main == KEYS[1] and #claim.alts == 4, "one claim to the officers, naming the member (Bia)")
for _, c in ipairs(CH) do session(c) end
now = now + 86400 * 5
GuildOS.db.altLinks = {}   -- the officers unlinked them all (or the claim ran out)
for _, c in ipairs(CH) do session(c) end
check(#shown == 1, "linked: never asked again, not even after an officer's unlink")

account()
shown = {}
answer = function(plan) AD:Accept(plan, KEYS[3], { [KEYS[1]] = true, [KEYS[2]] = true, [KEYS[4]] = true }) end
session("Ana")
answer = nil
local l = GuildOS.db.altLinks
check(l[KEYS[2]] == KEYS[3] and l[KEYS[4]] == KEYS[3] and l[KEYS[1]] == KEYS[3] and l[KEYS[5]] == nil,
  "Choose...: the ticked ones under the main picked; the main's own character (Ana) is in its group")
now = now + 86400 * 2
session("Eva")
check(#shown == 1, "an unticked character is answered: not asked again")
check(AD:_Plan(true) and names(AD:_Plan(true).list) == "Eva", "Detect my alts still offers it, whatever was answered")

-- Linked as alts of a character that is itself an alt: the whole group moves under it (a re-main, no loop).
account()
GuildOS.db.altLinks = { [KEYS[2]] = KEYS[1] }
AD:Accept({ list = { KEYS[3] }, chars = KEYS, choices = KEYS, main = KEYS[2] }, KEYS[2])
l = GuildOS.db.altLinks
check(l[KEYS[2]] == nil and l[KEYS[1]] == KEYS[2] and l[KEYS[3]] == KEYS[2], "the group re-mained under the alt chosen")

-- ── 4. What the plan leaves out ─────────────────────────────────────────
local guildSet = {}
for _, k in ipairs(KEYS) do guildSet[k] = true end
local acc = {}
for i, k in ipairs(KEYS) do acc[k] = { level = 70 - i } end
local p = AD.Plan(acc, guildSet, { [KEYS[2]] = KEYS[1], [KEYS[3]] = KEYS[1] }, {}, now)
check(p and names(p.list) == "Duda,Eva" and p.main == KEYS[1], "characters already in the main's group are not asked about")
check(AD.Plan(acc, { [KEYS[1]] = true }, {}, {}, now) == nil, "one character in the guild: nothing to ask")
local all = {}
for i = 2, 5 do all[KEYS[i]] = KEYS[1] end
check(AD.Plan(acc, guildSet, all, {}, now) == nil, "all in one group: nothing to ask")
guildSet[K("Stranger")] = true
p = AD.Plan(acc, guildSet, { [KEYS[1]] = K("Stranger") }, {}, now)
local hasStranger = false
for _, k in ipairs(p.choices) do if k == K("Stranger") then hasStranger = true end end
check(hasStranger, "a main of the group outside the account (in the guild) is offered as the main")

-- ── 5. Never in combat, after the login's popups ────────────────────────
account()
shown, answer = {}, nil
combat = true
me, AD._prompted = "Ana", nil
local stubShow = GuildOS.ShowWhenClear
GuildOS.ShowWhenClear = realShow
GuildOS._popupQueue.current, GuildOS._popupQueue.currentKey, GuildOS._popupQueue.items = nil, nil, {}
AD:OfferAtLogin()
check(#shown == 0, "in combat: nothing opens")
combat = false
regen()
check(#shown == 1, "out of combat: it opens")
check(GuildOS.POPUP_ORDER.altdetect == nil, "and queues behind the login popups (raid prompt, onboarding, founding, digest)")
GuildOS.ShowWhenClear = stubShow

-- Worked out again when it gets its turn: what changed while it waited is not asked.
account()
shown = {}
local queued
GuildOS.ShowWhenClear = function(_, _, fn) queued = fn end
me, AD._prompted = "Ana", nil
AD:OfferAtLogin()
for i = 2, 5 do GuildOS.db.altLinks[KEYS[i]] = KEYS[1] end   -- an officer's sync linked them meanwhile
check(queued() == nil and #shown == 0, "linked while it waited: no prompt, and nothing counted")
GuildOS.ShowWhenClear = stubShow

-- A client with no saved answers asks (it cannot know), with the same cap.
account()
shown = {}
for d = 1, 6 do session("Ana"); now = now + 86400 end
check(#shown == 3, "a new client: three times at most, a day apart")

-- ── 6. A renamed character keeps its links and answers ──────────────────
account()
guids["Ana"] = "Player-1-0001"
me = "Ana"
AD:RecordSelf()
GuildOS.db.settings.officerMaxRank = 5   -- an officer here, so the links are written
GuildOS.db.altLinks = { [KEYS[2]] = KEYS[1], [KEYS[3]] = KEYS[1] }
AD:_Asks()[AD.PairKey(KEYS[1], KEYS[5])] = { d = "no" }
ROSTER[2] = { "Anna", 5 }   -- Ana renamed Anna
guids["Anna"], me = "Player-1-0001", "Anna"
AD:RecordSelf()
check(GuildOSDB.accountChars[KEYS[1]] == nil and GuildOSDB.altRenamed and GuildOSDB.altRenamed.to == K("Anna"),
  "the same GUID under a new name: the old name's record goes")
AD:CheckRename()
l = GuildOS.db.altLinks
check(l[KEYS[2]] == K("Anna") and l[KEYS[3]] == K("Anna") and l[KEYS[1]] == nil, "its alts follow it to the new name")
check(AD:_Asks()[AD.PairKey(K("Anna"), KEYS[5])] and AD:_Asks()[AD.PairKey(K("Anna"), KEYS[5])].d == "no",
  "and so do the answers about it")
check(AD.PlanRename({ [KEYS[1]] = KEYS[2] }, KEYS[1], K("Anna"))[K("Anna")] == KEYS[2], "an alt renamed stays an alt of its main")
ROSTER[2] = { "Ana", 5 }
GuildOS.db.settings.officerMaxRank = 1

-- ── 7. Add alt on the sheet ─────────────────────────────────────────────
local rosterNames = { { name = "Ana", key = KEYS[1] }, { name = "Chehul Costa", key = "Chehul Costa-Realm" },
  { name = "Bob", key = "Bob-Gallywix" }, { name = "Bob", key = "Bob-Realm" } }
check(AD.FindMember(rosterNames, " ana ") == KEYS[1], "a name in any case")
check(AD.FindMember(rosterNames, "Chehul-Costa") == "Chehul Costa-Realm", "WoW: Forever's chat name is the roster's surname")
check(AD.FindMember(rosterNames, "Bob", "Main-Gallywix") == "Bob-Gallywix", "namesakes: the card's realm first")
check(AD.FindMember(rosterNames, "Nobody") == nil, "somebody not in the guild is never linked")
account()
GuildOS.db.settings.officerMaxRank = 5
me = "Off"
GuildOS.db.altLinks = { [KEYS[2]] = KEYS[1] }
check(AD:AddAlt(KEYS[2], KEYS[3]) and GuildOS.db.altLinks[KEYS[3]] == KEYS[1], "on an alt's sheet the new alt goes under its main")
check(not AD:AddAlt(KEYS[2], KEYS[1]), "the group's own main is no new alt")
GuildOS.db.settings.officerMaxRank = 1
me, sent = "Bia", {}
GuildOS.db.altLinks = { [KEYS[2]] = KEYS[1] }
AD:AddAlt(KEYS[2], KEYS[4])
claim = nil
for _, m in ipairs(sent) do if m.t == "SA" then claim = store[m.data] end end
local named = false
for _, k in ipairs(claim and claim.alts or {}) do if k == KEYS[2] then named = true end end
check(claim and claim.main == KEYS[1] and named, "a member's add goes as a claim of the whole group, naming the member")

-- ── 8. A main who is not in the guild any more ──────────────────────────
local members = {}
for i = 2, 5 do members[#members + 1] = { key = KEYS[i], name = CH[i] } end
local orphans = DEP.Orphans({ [KEYS[2]] = KEYS[1], [KEYS[3]] = KEYS[1], [KEYS[4]] = K("Stranger") }, members)
check(#orphans == 2 and orphans[1].key == KEYS[1] and #orphans[1].others == 2, "a group whose main is gone, with its alts")
check(#DEP.Orphans({ [KEYS[2]] = KEYS[1] }, members, { [KEYS[1]] = true }) == 0, "one kept is not asked about")
-- Asked at an officer's login, once a session, three times at most, never again after Keep.
account()
GuildOS.db.settings.officerMaxRank = 5
me = "Off"
table.remove(ROSTER, 2)   -- Ana gone
GuildOS.db.altLinks = { [KEYS[2]] = KEYS[1], [KEYS[3]] = KEYS[1] }
GuildOS.RosterLog = { _ready = true }
GuildOS.BulkActions = { Collect = function() local out = {} for _, r in ipairs(ROSTER) do out[#out + 1] = { key = K(r[1]), name = r[1] } end return out end }
local asked = {}
GuildOS.ShowMainLeftDialog = function(_, info) asked[#asked + 1] = info; return window end
local function officerSession()
  GuildOS.State.altDeparture = nil
  DEP:CheckOrphans()
  DEP:CheckOrphans()
end
officerSession()
check(#asked == 1 and asked[1].orphan and asked[1].key == KEYS[1] and #asked[1].others == 2, "asked once, with its alts")
officerSession(); officerSession(); officerSession()
check(#asked == 3, "three sessions at most")
GuildOS.db.altOrphans = nil
asked = {}
officerSession()
DEP:KeepOrphan(KEYS[1])
officerSession()
check(#asked == 1, "Keep: not asked again")
local ok = DEP:SetNewMain(KEYS[1], KEYS[2])
check(ok and GuildOS.db.altLinks[KEYS[2]] == nil and GuildOS.db.altLinks[KEYS[3]] == KEYS[2], "Set as main: an alt heads the group")
table.insert(ROSTER, 2, { "Ana", 5 })

-- ── 9. The companion sees the officers' links, not a member's own claim ──
account()
me = "Bia"
AS:Initialize()
AD:LinkOwnAlts(KEYS[1], { KEYS[1], KEYS[2] })
check(GuildOS.db.altLinks[KEYS[2]] == KEYS[1], "the member's view has its claim")
check(AS:BaseView()[KEYS[2]] == nil, "the officers' view, which the export reads, does not")
local src = io.open(ADDON .. "/Modules/CompanionExport.lua"):read("*a")
check(src:find("exportLinks = officersLinks()", 1, true) and src:find("AltSync:BaseView()", 1, true),
  "the export takes AltSync's view")

print(("alt-prompt: %d checks passed"):format(checks))
