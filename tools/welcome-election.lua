-- One welcome per member who joins, whoever is online (#449: "more than one officer always sends the welcome"), and
-- the welcome shared by the officers, run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/CommSystem.lua, Modules/SyncService.lua and Modules/RecruitmentSystem.lua, with officers on one guild
-- channel in simulated time: names with surnames, a client whose welcome waits for a click (WoW: Forever) and ones
-- that send it on their own, each with its own latency, one on a version before the election (its old tie-break
-- modelled here), the lowest officer online without Guild OS, the game's line read at different moments, the same
-- line twice and a /reload.
--
--   luajit -e 'ADDON="."' tools/welcome-election.lua
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

-- ── Simulated time ──────────────────────────────────────────────────────
local T, seq, events = 0, 0, {}
local cur   -- the client whose code runs now
local BASE = 1792000000
local function schedule(at, who, fn)
  seq = seq + 1
  events[#events + 1] = { at = at, seq = seq, who = who, fn = fn }
end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  function f:Hide() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Realm" end
function GetServerTime() return BASE + math.floor(T) end
function GetTime() return T end
function GetLocale() return "enUS" end
time, date = os.time, os.date
C_Timer = { After = function(d, fn) schedule(T + d, cur, fn) end,
            NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function IsInGuild() return true end
function InCombatLockdown() return false end

-- The roster every client reads: the officers (rank 1) and whether the game shows them online.
local ROSTER = {}
local function setRoster(list) ROSTER = list end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r.name, "Rank" .. r.rank, r.rank, 70, "Mage", "", "", "", r.online ~= false, 0, "MAGE" end
end

local registry, store, n = {}, {}, 0
LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, copy(store[s]) end return false end
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
local CS, SS, R = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.Recruitment
CS.pendingMessages = {}
GuildOS.Print = function() end
function GuildOS:ShowWhenClear() end
R.ShowWelcomePopup = function() end

-- ── The clients ─────────────────────────────────────────────────────────
-- Each: the character (the roster's spelling: "First Surname" where the game has surnames), whether its welcome
-- waits for a click, its latency on the guild channel, and `old` for a client before the election.
local clients = {}
local welcomes = {}   -- { from, text, at }
local SESSION = { "_welcomedRecently", "_welcomeIntents", "_pendingWelcomes", "_drawnWelcome", "_drawnBack", "_usedBack",
                  "_welcomePublishSoon", "_lastWelcomeDelay" }
function UnitFullName()
  local first, surname = cur.name:match("^(%S+) (%S+)$")
  if first then return first, surname end
  return cur.name, nil
end
function UnitName() return (cur.name:match("^(%S+)")) end
function GetGuildInfo() return "Guild", "Rank1", 1 end
function SendChatMessage(msg, chan) if chan == "GUILD" then welcomes[#welcomes + 1] = { from = cur.name, text = msg, at = T } end end
local needsClick = GuildOS.Compat.NeedsClick
GuildOS.Compat.NeedsClick = function() return cur and cur.click or false end

local function newClient(name, opts)
  opts = opts or {}
  local c = { name = name, click = opts.click, latency = opts.latency or 0.3, old = opts.old, online = true,
              db = { settings = { officerMaxRank = 1 }, sync = { rev = {} },
                     recruitment = { welcomeEnabled = true, welcomeMessage = "Welcome {name}!",
                                     welcomeMessages = { "Welcome {name}!" }, discord = "" } },
              session = {}, seen = {}, count = 0, old_intents = {}, old_sent = {} }
  clients[#clients + 1] = c
  return c
end
local function use(c)
  if cur and cur ~= c and not cur.old then
    for _, k in ipairs(SESSION) do cur.session[k] = R[k] end
    cur.seen, cur.count = SS.seenIds, SS.seenCount
  end
  cur = c
  GuildOS.db = c.db
  if not c.old then
    for _, k in ipairs(SESSION) do R[k] = c.session[k] end
    SS.seenIds, SS.seenCount = c.seen, c.count
  end
end
-- The sender as the game hands it: the surname's space as a hyphen, the realm left off.
local function senderOf(c) return (c.name:gsub(" ", "-")) end

local deliver
CS.SendMessage = function(_, msgType, data)
  local from = cur
  for _, c in ipairs(clients) do
    if c ~= from and c.online then
      schedule(T + from.latency, c, function() deliver(c, from, msgType, data) end)
    end
  end
end
-- A client before the election: it sends its intent, waits 2 s and the lowest name among the intents it heard
-- sends the claim and the welcome; a claim heard stands it down (the 1.43 code, with its raw name comparison).
local function oldJoin(c, who)
  if c.old_sent[who] then return end
  c.old_intents[who] = c.old_intents[who] or {}
  c.old_intents[who][c.name] = true
  CS:SendMessage("WI", who)
  schedule(T + 2, c, function()
    if c.old_sent[who] then return end
    local winner = c.name
    for nm in pairs(c.old_intents[who]) do if nm < winner then winner = nm end end
    if winner ~= c.name then return end
    c.old_sent[who] = true
    CS:SendMessage("WC", who)
    SendChatMessage("Welcome " .. who .. "! (old)", "GUILD")
  end)
end
deliver = function(c, from, msgType, data)
  if c.old then
    if msgType == "WI" then
      c.old_intents[data] = c.old_intents[data] or {}
      c.old_intents[data][senderOf(from)] = true
    elseif msgType == "WC" then
      c.old_sent[data] = true
    end
    return
  end
  CS:OnMessageReceived("S:" .. msgType .. ":" .. data, "GUILD", senderOf(from))
end

local function run(untilT)
  while true do
    table.sort(events, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    local e = events[1]
    if not e or e.at > untilT then break end
    table.remove(events, 1)
    T = e.at
    use(e.who)
    e.fn()
  end
  T = untilT
end

-- The game's line "X has joined the guild.", read by each client after its own delay.
local function joins(who, readDelay)
  for i, c in ipairs(clients) do
    if c.online then
      schedule(T + (readDelay and readDelay[i] or 0), c, function()
        if c.old then return oldJoin(c, who) end
        if not GuildOS.db.recruitment.welcomeEnabled then return end
        R:OnJoinWelcome(who)
      end)
    end
  end
end
-- The officers who wait for a click press it (some time later).
local function clicks()
  for _, c in ipairs(clients) do
    if c.click and c.online and not c.old then
      use(c)
      if R._pendingWelcomes and #R._pendingWelcomes > 0 then R:SendPendingWelcome() end
    end
  end
end
local function welcomesFor(who)
  local out = {}
  for _, w in ipairs(welcomes) do if w.text:find(who, 1, true) then out[#out + 1] = w end end
  return out
end
local function rosterOf(extra)
  local list = {}
  for _, c in ipairs(clients) do list[#list + 1] = { name = c.name, rank = 1, online = c.online } end
  for _, e in ipairs(extra or {}) do list[#list + 1] = e end
  list[#list + 1] = { name = "Zed Novo", rank = 5 }
  return list
end

-- ── Pure: the order every client computes alike ─────────────────────────
use(newClient("Ana Lima", { click = true, latency = 0.4 }))
check(R.StableName("Ana-Lima") == "ana lima" and R.StableName("Ana Lima") == "ana lima", "a surname, hyphen or space, is one name")
check(R.StableName("Bruno-Realm") == "bruno", "the realm plays no part")
check(R.SortsBefore("Ana Lima", "Bruno") and not R.SortsBefore("bruno", "Ana-Lima"), "the order")

-- ── 1. Three officers: a click client (lowest), a slow one, a fast one ──
local bruno = newClient("Bruno", { latency = 3 })
local carla = newClient("Carla Dias", { latency = 0.2 })
setRoster(rosterOf())
joins("Zed Novo", { 0, 1.5, 0.1 })
run(30)
clicks()
local w = welcomesFor("Zed Novo")
check(#w == 1 and w[1].from == "Ana Lima", "one welcome, from the first officer online (" .. #w .. ")")
use(carla)
check(R._lastWelcomeDelay == R.WELCOME_FIRST + 2 * R.WELCOME_STEP, "the third waits two steps more")
use(bruno)
check(R._lastWelcomeDelay == nil, "the slow one read the line after the claim came: it never even waited")
-- The same line again (read twice, a rejoin minutes later) and after a /reload: never a second welcome.
joins("Zed Novo")
run(60)
clicks()
for _, c in ipairs(clients) do c.session = {} end
use(carla); R._welcomedRecently = nil
joins("Zed Novo")
run(90)
clicks()
check(#welcomesFor("Zed Novo") == 1, "within ten minutes, the same member is not welcomed again, /reload or not")

-- ── 2. The first officer is offline: the next one sends ─────────────────
clients[1].online = false
setRoster(rosterOf())
joins("Yara Sol", { 0, 0.5, 2 })
run(130)
clicks()
w = welcomesFor("Yara Sol")
check(#w == 1 and w[1].from == "Bruno", "Ana offline: Bruno sends, alone")

-- ── 3. The first online officer runs no Guild OS: the fallback, once ────
setRoster(rosterOf({ { name = "Abel Sem", rank = 1 } }))   -- online, sorts first, never claims
joins("Xis Tres", { 0, 0.3, 0.6 })
run(200)
clicks()
w = welcomesFor("Xis Tres")
check(#w == 1 and w[1].from == "Bruno", "after the silent first, the next one sends, and only it (" .. #w .. ")")

-- ── 4. An officer on an old version, first or last ──────────────────────
clients[1].online = true
local aaron = newClient("Aaron", { old = true, latency = 0.5 })
setRoster(rosterOf())
joins("Wil Quatro", { 0.2, 0.4, 0, 0.1 })
run(260)
clicks()
w = welcomesFor("Wil Quatro")
check(#w == 1 and w[1].from == "Aaron", "the old officer first: its tie-break sends, the new ones stand down (" .. #w .. ")")
aaron.name = "Zoe Velha"
setRoster(rosterOf())
joins("Vic Cinco", { 0.1, 0, 0.2, 0.4 })
run(330)
clicks()
w = welcomesFor("Vic Cinco")
check(#w == 1 and w[1].from == "Ana Lima", "the old officer last: it hears the claim before its 2 s (" .. #w .. ")")
aaron.online = false

-- ── 5. Two officers who each think they won (the click client keeps the popup) ──
-- Ana thinks Bruno is offline and Bruno does not see Ana: both first. The claims settle it the same way on both.
local savedRoster = ROSTER
use(clients[1]); R._welcomedRecently = {}
ROSTER = { { name = "Ana Lima", rank = 1 }, { name = "Bruno", rank = 1, online = false } }
use(clients[1]); R:OnJoinWelcome("Ugo Seis")
use(bruno); bruno.click = true
ROSTER = { { name = "Ana Lima", rank = 1, online = false }, { name = "Bruno", rank = 1 } }
R:OnJoinWelcome("Ugo Seis")
ROSTER = savedRoster
run(400)
clicks()
bruno.click = nil
check(#welcomesFor("Ugo Seis") == 1, "the lower name keeps it: one welcome (" .. #welcomesFor("Ugo Seis") .. ")")

-- ── 6. The welcome is the guild's: shared, newest wins, the first run ───
use(clients[1]); SS:Initialize(); clients[1].seen, clients[1].count = SS.seenIds, SS.seenCount
for _, c in ipairs(clients) do
  if not c.old then use(c); c.db.recruitment.welcomeCfgAt, c.db.recruitment.welcomeCfgBy = nil, nil end
end
use(bruno); bruno.db.recruitment.welcomeMessages = { "Bruno's hello {name}" }; bruno.db.recruitment.welcomeMessage = "Bruno's hello {name}"
use(carla); carla.db.recruitment.welcomeMessages = { "Carla says hi {name}" }; carla.db.recruitment.welcomeMessage = "Carla says hi {name}"
use(clients[1]); clients[1].db.recruitment.welcomeMessages = {}; clients[1].db.recruitment.welcomeMessage = ""
use(bruno); R:PublishWelcome()
use(carla); R:PublishWelcome()
run(450)
for _, c in ipairs({ clients[1], bruno, carla }) do
  check(c.db.recruitment.welcomeMessage == "Bruno's hello {name}" and c.db.recruitment.welcomeCfgAt == R.MIGRATE_REV,
    "the first run settles on one officer's list everywhere (" .. c.name .. ")")
end
use(carla)
check(R:SetWelcome(1, "Carla's welcome {name}") and R:SetWelcomeBack(1, "Back, {name}! {days} days.") , "an officer edits")
carla.db.recruitment.welcomeEnabled = false
R:WelcomeChanged()
run(500)
for _, c in ipairs({ clients[1], bruno }) do
  local r = c.db.recruitment
  check(r.welcomeMessage == "Carla's welcome {name}" and r.welcomeBackMessages[1] == "Back, {name}! {days} days."
    and r.welcomeEnabled == false and r.welcomeCfgBy == "Carla Dias", "every officer has it, the switch too (" .. c.name .. ")")
end
use(bruno)
check(R:WelcomeSharedText():find("Carla Dias", 1, true), "the card says who changed it")
-- An older snapshot never wins over it.
local stale = { act = "welcome", rev = 5, data = { on = true, msgs = { "Old" }, back = {}, discord = "", rules = false, by = "Ana Lima" } }
check(not R:OnWelcomeConfigSync(stale, "Ana-Lima") and bruno.db.recruitment.welcomeMessage == "Carla's welcome {name}", "older loses")
local evil = { act = "welcome", rev = BASE + 9999, data = { on = true, msgs = { "bad | pipe" }, back = { 5 }, discord = "x", by = "Bruno" } }
R:OnWelcomeConfigSync(evil, "Bruno")
check(bruno.db.recruitment.welcomeMessage == "Carla's welcome {name}" and #bruno.db.recruitment.welcomeBackMessages == 0,
  "a text the game refuses is never taken")

needsClick = needsClick   -- kept for luacheck
print(("welcome-election: %d checks passed"):format(checks))
