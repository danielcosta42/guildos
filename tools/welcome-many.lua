-- Several welcome messages, one drawn for each welcome (issue #419), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua and
-- Modules/RecruitmentSystem.lua.
--
-- The officer writes a few welcomes so the guild chat does not read the same line for every
-- newcomer. The one they had becomes the first of the list; each welcome draws one, never the one
-- sent last while there is another; the Forever popup shows the line its click posts; and a client
-- from before #419 still reads and writes the first one, `welcomeMessage`.
--
--   luajit -e 'ADDON="."' tools/welcome-many.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Bishop", "Who" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Realm" end
C_Timer = { After = function() end, NewTicker = function() end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function IsInGuild() return true end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function GetGuildInfo() return "Guild", "Officer", 1 end
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
local R = GuildOS.Recruitment

local printed, sent = {}, {}
function GuildOS:Print(m) printed[#printed + 1] = m end
function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end
R.ShowWelcomePopup = function() end

-- ── The draw, pure ───────────────────────────────────────────────────────
local function first() return 1 end
local function last(n) return n end
check(R.PickWelcome({}, nil) == nil and R.PickWelcome(nil, nil) == nil, "no welcome, nothing drawn")
check(R.PickWelcome({ "A" }, "A", first) == "A", "one welcome: always that one, even after itself")
check(R.PickWelcome({ "A", "B" }, "A", first) == "B" and R.PickWelcome({ "A", "B" }, "B", last) == "A",
  "two: never the one sent last")
check(R.PickWelcome({ "A", "B", "C" }, "B", last) == "C" and R.PickWelcome({ "A", "B", "C" }, "B", first) == "A",
  "three: drawn among the other two")
check(R.PickWelcome({ "A", "A" }, "A", first) == "A", "the same text twice: it can only be that")
local seen = {}
for _ = 1, 200 do seen[R.PickWelcome({ "A", "B", "C" }, nil)] = true end
check(seen.A and seen.B and seen.C, "with math.random, every one of them comes out")

-- ── The list: today's welcome is its first ───────────────────────────────
check(#R.WelcomeList(nil) == 0 and #R.WelcomeList({}) == 0, "no settings, no list")
local l = R.WelcomeList({ welcomeMessage = "Hi" })
check(#l == 1 and l[1] == "Hi", "a db from before #419: its welcome is the list")
l = R.WelcomeList({ welcomeMessage = "Edited", welcomeMessages = { "Old", "", "Two" } })
check(#l == 2 and l[1] == "Edited" and l[2] == "Two",
  "welcomeMessage wins the first place (set by an older client), empty ones left out")

-- Initialize writes the list from the welcome the officer had, nothing lost.
GuildOS.db = { recruitment = { welcomeMessage = "Welcome to Ordem!", channels = { "Trade" }, message = "Join!" } }
function R:HookChatInvite() end
function R:RegisterWelcomeEvent() end
function R:RegisterAutoInviteEvent() end
local okInit, errInit = pcall(R.Initialize, R)
check(okInit, "Initialize runs: " .. tostring(errInit))
local r = GuildOS.db.recruitment
check(type(r.welcomeMessages) == "table" and #r.welcomeMessages == 1 and r.welcomeMessages[1] == "Welcome to Ordem!"
  and r.welcomeMessage == "Welcome to Ordem!", "the migration: today's welcome becomes the first of the list")

-- ── Editing it ───────────────────────────────────────────────────────────
check(R:SetWelcome(2, "Glad you are here!") == true and #r.welcomeMessages == 2, "a second one is added")
check(R:SetWelcome(9, "Make yourself at home") == true and r.welcomeMessages[3] == "Make yourself at home",
  "a place past the end adds at the end")
local okBad, why = R:SetWelcome(2, "Hi | there")
check(okBad == false and why ~= nil and r.welcomeMessages[2] == "Glad you are here!", "a text the game refuses is not kept")
check(R:SetWelcome(1, "Welcome, friend!") == true and r.welcomeMessage == "Welcome, friend!" and r.welcomeMessages[1] == "Welcome, friend!",
  "editing the first writes welcomeMessage too, for an older client")
check(R:RemoveWelcome(1) == true and r.welcomeMessage == "Glad you are here!" and #r.welcomeMessages == 2,
  "removing the first: the next one takes its place, in welcomeMessage too")
check(R:RemoveWelcome(5) == false and #r.welcomeMessages == 2, "a place not on the list removes nothing")
check(R:RemoveWelcome(2) == true and R:RemoveWelcome(1) == false and #r.welcomeMessages == 1,
  "the last welcome stays")
for i = 2, R.WELCOME_MAX do R:SetWelcome(i, "W" .. i) end
check(#R.WelcomeList(r) == R.WELCOME_MAX and R:SetWelcome(R.WELCOME_MAX + 1, "One more") == false,
  "at most " .. R.WELCOME_MAX)

-- /gos recruit welcome msg still sets the first one.
R:HandleCommand({ "welcome", "msg", "Hello", "there" })
check(r.welcomeMessage == "Hello there" and r.welcomeMessages[1] == "Hello there", "/gos recruit welcome msg sets the first")

-- ── Sending: one drawn, never twice in a row ─────────────────────────────
r.welcomeMessages = { "One", "Two" }
r.welcomeMessage = "One"
r.welcomeLast = nil
R._drawnWelcome = nil
local lastSent
for n = 1, 30 do
  R:QueueWelcome("Newbie" .. n)
  local shown = R:WelcomeMessage()
  check(shown == R:WelcomeMessage(), "the popup and the click show the same draw")
  check(R:SendPendingWelcome() == true, "the click sends")
  local msg = sent[#sent].msg
  check(msg == shown, "what the popup showed is what went")
  check(msg ~= lastSent, "never the same welcome twice in a row (" .. n .. ")")
  lastSent = msg
end
-- Sent on its own (Anniversary): the timer reads WelcomeMessage, then SendWelcomeText.
local a = R:WelcomeMessage()
check(R:SendWelcomeText(a, "Ana") == true and R:WelcomeMessage() ~= a, "the timed welcome draws the other one next")
-- A send the game refuses keeps the draw: the next try is the same line.
function SendChatMessage() error("Invalid escape code in chat message") end
local b = R:WelcomeMessage()
check(R:SendWelcomeText(b, "Ana") == false and R:WelcomeMessage() == b, "a welcome that did not go is not counted")
function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end
-- A draw taken off the list is drawn again.
R._drawnWelcome = "Two"
r.welcomeMessages = { "One", "Three" }
check(R:WelcomeMessage() ~= "Two", "a welcome removed after its draw is not sent")

-- The rules' invitation (#407) ends whichever was drawn.
GuildOS.GuildRules = { HasRules = function() return true end }
r.welcomeRules = true
check(R:WelcomeMessage():find("Type /gos rules", 1, true) ~= nil, "the rules' invitation ends the drawn welcome")

-- {name} and {guild} in a welcome (#449).
do
  local F = R.FillWelcome
  local realGI = GetGuildInfo
  GetGuildInfo = function() return "Filhos da Horda" end
  check(F("Welcome {name}!", "Ana-Realm") == "Welcome Ana!", "{name} becomes the name without its realm")
  check(F("Bem-vindo {Nome} à {guild}", "Bob") == "Bem-vindo Bob à Filhos da Horda", "any case, {nome} too, and {guild}")
  check(F("Welcome {name}!", { "Ana", "Bob" }) == "Welcome Ana, Bob!", "several who joined at once, by commas")
  check(F("Welcome, {name}!", nil) == "Welcome,!" or F("Welcome {name}!", nil) == "Welcome!", "nobody to name leaves no stray space")
  check(F("Hi {unknown}", "Ana") == "Hi {unknown}", "an unknown placeholder stays as written")
  GetGuildInfo = realGI
end
print("welcome-many: " .. checks .. " checks passed")
