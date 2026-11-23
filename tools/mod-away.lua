-- The chat alerts catch up on what was said while the officer was away (issue #411), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/ModAlerts.lua and Modules/ModFlood.lua under a
-- stubbed client whose server keeps the guild's chat (WoW: Forever, retail).
--
--   luajit -e 'ADDON="."' tools/mod-away.lua
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

-- ── The client ──────────────────────────────────────────────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local handlers = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(_, fn) self.fn = fn end
  handlers[#handlers + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(handlers) do
    if f.events[event] and f.fn then f.fn(f, event, ...) end
  end
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70124", "", 16001 end
function GetRealmName() return "Classic Beta PvE 2" end
function GetLocale() return "enUS" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return NOW end
local timers, tickers = {}, {}
C_Timer = {
  After = function(_, fn) timers[#timers + 1] = fn end,
  NewTicker = function(_, fn) tickers[#tickers + 1] = fn return { Cancel = function() end } end,
}
local function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
function issecretvalue() return false end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/ModAlerts.lua")
dofile(ADDON .. "/Modules/ModFlood.lua")

local M, F = GuildOS.ModAlerts, GuildOS.ModFlood
local officer = true
function GuildOS:IsOfficer() return officer end
function GuildOS:IsOfficerByName() return false end
GuildOS.Compat.PlayerName = function() return "Arthas" end
local lockdown = false
GuildOS.Compat.InChatLockdown = function() return lockdown end
local history = {}
GuildOS.Compat.GuildChatHistory = function()
  if lockdown then return nil, "locked" end
  return history
end
local sent = {}
GuildOS.SyncService = { On = function() end, Publish = function(_, dom) sent[#sent + 1] = dom end }
local shown = {}
function GuildOS:ShowModAlert(a) shown[#shown + 1] = a end
GuildOS.GuildChat = { Log = function() return {} end }
GuildOS.db = { settings = {} }
M:Initialize()
F:Initialize()

local H = 3600
local function line(t, n, m) return { t = t, n = n, m = m } end

-- ── The pure window ─────────────────────────────────────────────────────
local hist = { line(NOW - 30, "B", "late"), line(NOW - 10 * H, "A", "early"), line(NOW + 5, "C", "after login"), line(NOW - 2 * H, "D", "middle") }
local away = M.AwayLines(hist, NOW - 11 * H, NOW)
check(#away == 3 and away[1].m == "early" and away[3].m == "late", "oldest first, inside the window, nothing after the login")
check(#away[3].context == 2 and away[3].context[2].m == "middle", "each line keeps the lines before it as its context")
local many = {}
for i = 1, 400 do many[i] = line(NOW - 400 + i, "A", "x" .. i) end
local cut = M.AwayLines(many, 0, NOW)
check(#cut == M.AWAY_MAX_LINES and cut[#cut].m == "x400", "at most 300, the newest")
check(#M.AwayLines({ { t = 0 / 0, n = "A", m = "x" }, "junk", { t = NOW - 1, n = 5, m = "x" } }, 0, NOW) == 0, "a malformed line is skipped")

-- ── The login: the server's lines go through the rules, into the panel only ──
history = {
  line(NOW - 30 * H, "Old", "buy gold cheap"),        -- older than 24 hours: not read
  line(NOW - 2 * H, "Seller", "buy gold cheap here"), -- a trade rule
  line(NOW - 1 * H, "Nice", "good night all"),
}
fire("PLAYER_ENTERING_WORLD")
check(#M:Feed() == 0, "nothing before the world settles")
runTimers()
local feed = M:Feed()
check(#feed == 1 and feed[1].who == "Seller", "the line said while away is alerted; the one past 24 hours is not")
check(feed[1].away == true and feed[1].said == NOW - 2 * H, "marked as while away, with the time it was said")
check(#shown == 0 and #sent == 0, "no window, no sound, no claim on the wire")
check(M:SeenAt() == NOW, "the time seen is kept at login")
check(#tickers == 1, "and every minute after")

-- A second login event in the same session does nothing again.
fire("PLAYER_ENTERING_WORLD")
runTimers()
check(#M:Feed() == 1, "once a session")

-- The anti-flood reads the lines at the time they were said: a burst while away is one surge.
M.feed = {}
local burst = {}
for i = 1, 6 do burst[i] = line(NOW + 100 + i, "Spammer", "lol " .. i) end
history = burst
NOW = NOW + 200
local n = M:CatchUp(NOW)
check(n == 6, "six lines read since the last seen")
local surge
for _, a in ipairs(M:Feed()) do if a.kind ~= "subject" and a.who == "Spammer" then surge = a end end
check(surge and surge.away and (surge.count or 0) >= 1, "a burst said while away is a flood alert, marked away")
check(#shown == 0, "still no window")

-- Only since the last time seen: what this officer already heard is not read twice.
M:MarkSeen(NOW)
check(M:CatchUp(NOW) == 0, "nothing new since the last seen")

-- ── Who and when ────────────────────────────────────────────────────────
officer = false
check(select(2, M:CatchUp(NOW)) == "member", "a member's client reads nothing")
officer = true
lockdown = true
check(select(2, M:CatchUp(NOW)) == "locked", "the game holding the chat: try later")
lockdown = false
GuildOS.Compat.GuildChatHistory = function() return nil end
check(select(2, M:CatchUp(NOW)) == "none", "no history kept by the server (TBC Anniversary): nothing")
M:Prefs().enabled = false
check(select(2, M:CatchUp(NOW)) == "off", "alerts off: nothing")
M:Prefs().enabled = true

-- Logging out keeps the time seen.
NOW = NOW + 500
fire("PLAYER_LOGOUT")
check(M:SeenAt() == NOW, "the logout keeps the time seen")

-- The live path is untouched: a line heard now still alerts with its window.
M.catchingUp = false
M.feed = {}
fire("CHAT_MSG_GUILD", "buy gold cheap now", "Seller")
runTimers()
check(#M:Feed() == 1 and not M:Feed()[1].away, "a live line is a live alert")

print(("mod-away: %d checks passed"):format(checks))
