-- The newcomer's quarantine (issue #406), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/RosterLog.lua, Modules/TrialTracker.lua, Modules/ModAlerts.lua,
-- Modules/ModFlood.lua and Modules/Newcomer.lua under a stubbed client.
--
-- In a member's first N days (RosterLog's join) any link alerts and the anti-flood's limits are halved,
-- with the badge "newcomer (day X of N)" on the officers' alerts; a member with no known join is not a
-- newcomer; a running trial counts when the guild says so; 0 days turns it off; the end is worked out,
-- never stored; the setting is the officers', newest stamp wins.
--
--   luajit -e 'ADDON="."' tools/newcomer.lua
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

-- ── The client the files need while they load ───────────────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local onEvent
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) onEvent = fn end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70124", "", 16001 end
function GetRealmName() return "Classic Beta PvE 2" end
function GetLocale() return "enUS" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local DAY = 86400
local NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return NOW end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
function issecretvalue() return false end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
dofile(ADDON .. "/Modules/TrialTracker.lua")
dofile(ADDON .. "/Modules/ModAlerts.lua")
dofile(ADDON .. "/Modules/ModFlood.lua")
dofile(ADDON .. "/Modules/Newcomer.lua")

local M, F, N = GuildOS.ModAlerts, GuildOS.ModFlood, GuildOS.Newcomer
local officer = true
function GuildOS:IsOfficer() return officer end
function GuildOS:IsOfficerByName() return false end
GuildOS.Compat.PlayerName = function() return "Arthas" end
GuildOS.Compat.InChatLockdown = function() return false end
local sent = {}
GuildOS.SyncService = {
  On = function() end,
  Publish = function(_, dom, act, data, opts) sent[#sent + 1] = { dom = dom, act = act, data = data, opts = opts } end,
}
GuildOS.GuildChat = { Log = function() return {} end }
GuildOS.db = { settings = {}, trials = {}, rosterLog = { events = {} } }
M:Initialize()
F:Initialize()
N:Initialize()
GuildOS.db.settings.modAlertRules, GuildOS.db.settings.modAlertRulesAt = {}, 1   -- the word list empty
M:Recompile()

local function say(author, msg) onEvent(nil, "CHAT_MSG_GUILD", msg, author) end
local function alertsOf(who)
  local out = {}
  for _, a in ipairs(M:Feed()) do if a.who == who then out[#out + 1] = a end end
  return out
end
local function join(name, at)
  GuildOS.RosterLog:_Insert({ action = "join", target = name, timestamp = at })
end

-- ── The pure helpers ────────────────────────────────────────────────────
local J = 1000000
check(N.DayOf(J, J, 7) == 1 and N.DayOf(J, J + DAY - 1, 7) == 1 and N.DayOf(J, J + DAY, 7) == 2, "day 1, then day 2")
check(N.DayOf(J, J + 7 * DAY - 1, 7) == 7 and N.DayOf(J, J + 7 * DAY, 7) == nil, "the last second is day 7; join + N is over")
check(N.DayOf(nil, J, 7) == nil and N.DayOf(J, J, 0) == nil, "no join, or 0 days: not a newcomer")
check(N.DayOf(J + 60, J, 7) == 1, "a join a minute ahead of this clock is day 1")
check(N.ValidDays(0) == 0 and N.ValidDays("30") == 30 and not N.ValidDays(31) and not N.ValidDays(1.5) and not N.ValidDays("7d"),
      "0 to 30 whole days")
local base = F.ValidConfig({ links = { on = false } })
local st = N.Strict(base)
check(st.burst.n == 3 and st["repeat"].n == 2 and st.caps.min == 6 and st.caps.pct == 70 and st.links.on and st.links.n == 1,
      "halved limits, any link")
check(base.burst.n == 5 and base.links.on == false, "the guild's own limits are untouched")
check(N.BadgeText({ day = 2, of = 7 }) == "newcomer (day 2 of 7)" and N.BadgeText({ trial = true }) == "newcomer (trial)"
      and N.BadgeText(nil) == nil, "the badge")
check(N:GetDays() == 7 and not N:TrialCounts(), "7 days and trials off by default")

-- ── Who is a newcomer ───────────────────────────────────────────────────
join("Thrall", NOW - 2 * DAY - 10)                 -- day 3
join("Jaina", NOW - 9 * DAY)                       -- over
check(N:Of("Thrall-Classic", NOW).day == 3 and N:Of("Thrall", NOW).of == 7, "joined two days ago: day 3 of 7")
check(N:Of("Jaina", NOW) == nil, "joined nine days ago: not any more")
check(N:Of("Garrosh", NOW) == nil, "no join on the log (in the guild before the addon): not a newcomer")
join("Jaina", NOW - DAY)                           -- she left and came back
check(N:Of("Jaina", NOW) and N:Of("Jaina", NOW).day == 2, "the latest join counts")
check(N:Of("Thrall", NOW + 5 * DAY - 11) ~= nil and N:Of("Thrall", NOW + 5 * DAY - 10) == nil, "the end is join + N, to the second")
local function hasKey(t, pat)
  for k in pairs(t) do if tostring(k):lower():find(pat) then return true end end
  return false
end
check(not hasKey(GuildOS.db.settings, "until") and not hasKey(GuildOS.db.settings, "end"), "no end is ever stored")

-- A running trial, when the guild says so.
local GKEY = GuildOS:KeyOfRosterName("Garrosh")
GuildOS.db.trials[GKEY] = { startDate = NOW - 3 * DAY, status = "trial", notes = {}, snapshots = {} }
check(N:Of("Garrosh", NOW) == nil, "a trial is not a newcomer while the switch is off")
check(N:SetConfig(7, true), "an officer turns it on")
check(N:Of("Garrosh", NOW).trial, "a running trial is a newcomer")
GuildOS.db.trials[GKEY].status = "approved"
check(N:Of("Garrosh", NOW) == nil, "a decided trial is not")
GuildOS.db.trials[GKEY].status = "trial"

-- 0 days: nobody.
check(N:SetConfig(0, true), "0 days")
check(N:Of("Thrall", NOW) == nil and N:Of("Garrosh", NOW) == nil, "0 turns it off, trials too")
check(not N:SetConfig(31, false) and N:GetDays() == 0, "31 is refused")
check(N:SetConfig(7, false), "back to 7")

-- ── Stricter alerts, on the officers' clients only ──────────────────────
-- One link: nothing for a veteran, an alert for a newcomer.
say("Garrosh", "cheap gold at goldshop.com")
check(#alertsOf("Garrosh") == 0, "a member who is no newcomer: one link is fine")
say("Thrall", "cheap gold at goldshop.com")
local a = alertsOf("Thrall")[1]
check(a and a.kind == "flood" and a.signal == "links", "a newcomer's one link alerts")
check(a.newcomer and a.newcomer.day == 3 and a.newcomer.of == 7, "with the badge's facts")
runTimers()
-- Half the burst: three lines in ten seconds.
NOW = NOW + 700
F.speakers, F.speakerCount, F.surges = {}, 0, {}
for i = 1, 3 do say("Garrosh", "line " .. i); say("Thrall", "line " .. i) end
check(#alertsOf("Garrosh") == 0, "three lines are fine for a veteran")
check(alertsOf("Thrall")[1].signal == "burst", "three lines are a burst for a newcomer")
runTimers()
-- Even with the guild's links signal off.
check(F:SetConfig({ links = { on = false, n = 2, secs = 60 } }), "the guild switches links off")
NOW = NOW + 700
say("Thrall", "visit www.example.com")
check(alertsOf("Thrall")[1].signal == "links", "a newcomer's link still alerts")
runTimers()
-- A subject alert carries the badge too.
GuildOS.db.settings.modAlertRules = { { p = "buy gold", cat = "trade", sev = "high" } }
M:Recompile()
NOW = NOW + 700
say("Thrall", "anyone buy gold?")
local subj
for _, x in ipairs(alertsOf("Thrall")) do if x.kind == "subject" then subj = x; break end end
check(subj and subj.newcomer and subj.newcomer.day >= 3, "a chat alert on a newcomer carries the badge")
runTimers()
-- A member's client reads nothing.
officer = false
local before = #M:Feed()
NOW = NOW + 700
for i = 1, 5 do say("Thrall", "member client www.x" .. i .. ".com") end
check(#M:Feed() == before, "a member's client flags nothing, badge or not")
officer = true

-- ── The guild's setting ─────────────────────────────────────────────────
sent = {}
check(N:SetConfig(10, true), "an officer sets 10 days")
local s = GuildOS.db.settings
check(sent[1] and sent[1].dom == "guildcfg" and sent[1].act == "newcomer" and sent[1].data.days == 10
      and sent[1].data.trial == true and sent[1].opts.rev == s.newcomerAt, "it goes to the guild, stamped")
local at = s.newcomerAt
N:OnConfigSync({ act = "newcomer", rev = at - 1, data = { days = 3, trial = false } })
N:OnConfigSync({ act = "newcomer", rev = at, data = { days = 3, trial = false } })
check(N:GetDays() == 10, "an older or tied stamp loses")
N:OnConfigSync({ act = "newcomer", rev = at + 1, data = { days = 99, trial = false } })
N:OnConfigSync({ act = "newcomer", rev = at + 1, data = { days = 3, trial = "yes" } })
check(N:GetDays() == 10 and s.newcomerAt == at, "a bad setting is turned away whole")
N:OnConfigSync({ act = "newcomer", rev = at + 1, data = { days = 3, trial = false } })
check(N:GetDays() == 3 and not N:TrialCounts() and s.newcomerAt == at + 1, "a newer one wins")
N:OnConfigSync({ act = "newcomer", rev = 0 / 0, data = { days = 5, trial = false } })
N:OnConfigSync({ act = "newcomer", rev = NOW + 10 * DAY, data = { days = 5, trial = false } })
check(N:GetDays() == 5 and s.newcomerAt <= NOW + 300, "NaN is no stamp; a stamp far ahead is held to five minutes")
officer = false
N:OnConfigSync({ act = "newcomer", rev = NOW + 9999, data = { days = 1, trial = false } })
check(N:GetDays() == 5 and not N:SetConfig(2, false), "a member keeps nothing and sets nothing")
officer = true
sent = {}
M:PublishConfig()
local acts = {}
for _, e in ipairs(sent) do acts[e.act] = true end
check(acts.newcomer, "the officers' regular sync carries it")

-- ── The self-tests the client runs ──────────────────────────────────────
local registered = {}
GuildOS.SelfTest = { Register = function(_, name, fn) registered[#registered + 1] = { name = name, fn = fn } end }
N:_RegisterTests()
check(#registered >= 3, "the self-tests register")
for _, t in ipairs(registered) do
  local ok, why = t.fn()
  check(ok, "selftest " .. t.name .. ": " .. tostring(why))
end
check(GuildOS.Newcomer.DayOf(1e12, 1000, 7) == nil and GuildOS.Newcomer.DayOf(math.huge, 1000, 7) == nil, "a join in the far future is unknown, never a quarantine forever")
check(GuildOS.Newcomer.DayOf(1100, 1000, 7) == 1, "a join a little ahead of this clock is day 1")
print(("newcomer: %d checks passed"):format(checks))
