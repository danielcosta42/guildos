-- The anti-flood (issue #405), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/ModAlerts.lua and Modules/ModFlood.lua under a stubbed client.
--
-- Too many lines, the same line repeated, capitals and links each flag one alert per person while the
-- surge lasts (with its count and its lines), into the chat alerts' panel (#404) and with its dedup
-- among officers; the game's own links count as neither links nor capitals; nothing is read in a chat
-- lockdown; the limits are the officers', newest stamp wins.
--
--   luajit -e 'ADDON="."' tools/mod-flood.lua
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
local NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return NOW end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
local secret = false
function issecretvalue() return secret end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/ModAlerts.lua")
dofile(ADDON .. "/Modules/ModFlood.lua")

local M, F = GuildOS.ModAlerts, GuildOS.ModFlood
local officer = true
local officers = { Uther = true }
function GuildOS:IsOfficer() return officer end
function GuildOS:IsOfficerByName(n) return officers[(n:match("^([^-]+)"))] == true end
GuildOS.Compat.PlayerName = function() return "Arthas" end
GuildOS.Compat.InChatLockdown = function() return false end
local sent, onClaim = {}, nil
GuildOS.SyncService = {
  On = function(_, dom, fn) if dom == "modalert" then onClaim = fn end end,
  Publish = function(_, dom, act, data, opts) sent[#sent + 1] = { dom = dom, act = act, data = data, opts = opts } end,
}
local shown, touched = {}, 0
function GuildOS:ShowModAlert(a) shown[#shown + 1] = a end
GuildOS.GuildChat = { Log = function() return {} end }
GuildOS.db = { settings = {} }
M:Initialize()
F:Initialize()
M.popupUpdate = function() touched = touched + 1 end
-- Only the anti-flood here: the guild's word list is empty.
GuildOS.db.settings.modAlertRules, GuildOS.db.settings.modAlertRulesAt = {}, 1
M:Recompile()

local function say(author, msg) onEvent(nil, "CHAT_MSG_GUILD", msg, author) end
local function floods()
  local out = {}
  for _, a in ipairs(M:Feed()) do if a.kind == "flood" then out[#out + 1] = a end end
  return out
end

-- ── The pure helpers ────────────────────────────────────────────────────
local LINK = "|cffa335ee|Hitem:19019::::::::60:::::|h[THUNDERFURY, BLESSED BLADE OF THE WINDSEEKER]|h|r"
check(F.StripGameLinks("look " .. LINK .. " ok") == "look   ok", "the game's link goes, its text too")
check(F.CountLinks("visit https://x.io/a and www.y.com") == 2, "two links")
check(F.CountLinks("GOLD AT CheapGold.com NOW") == 1, "a bare domain, any case")
check(F.CountLinks("discord.gg/abc") == 1, "an invite")
check(F.CountLinks(F.StripGameLinks("|cff0070dd|Hitem:1|h[www.not.a.link]|h|r")) == 0, "a game link is not a link")
check(F.CountLinks("see you at 10.30, ok? e.g. later") == 0, "a time and an abbreviation are not links")
local pct, letters = F.Caps("COME TO KARA NOW")
check(pct == 100 and letters == 13, "all capitals")
pct, letters = F.Caps("ÉÇÃO são")
check(letters == 7 and pct == 57, "accented letters count")
pct = F.Caps(F.StripGameLinks("look at " .. LINK))
check(pct == 0, "a game link is not capitals")
check(F.InWindow({ { t = 1 }, { t = 5 }, { t = 9 } }, 10, 6) == 2 and F.InWindow({ { t = 1, h = "a" }, { t = 2, h = "b" } }, 3, 10, "a") == 1,
      "the sliding window, and by hash")
check(F.ValidLimit("n", "5") == 5 and not F.ValidLimit("n", 1) and not F.ValidLimit("secs", 601) and not F.ValidLimit("pct", 49.5),
      "limits in range only")
local cfg = F.ValidConfig({ burst = { on = false, n = 999 }, caps = { pct = 80 } })
check(cfg.burst.on == false and cfg.burst.n == 5 and cfg.caps.pct == 80 and cfg["repeat"].n == 3 and cfg.links.on,
      "a bad limit goes back to its default, a missing signal comes in on")

-- ── Too many lines ──────────────────────────────────────────────────────
for i = 1, 4 do say("Thrall", "line " .. i) end
check(#floods() == 0, "four lines in ten seconds are fine")
say("Thrall", "line 5")
local a = floods()[1]
check(a and a.signal == "burst" and a.count == 5 and #a.lines == 5 and a.lines[5] == "line 5", "the fifth is a surge, with its lines")
runTimers()
check(shown[#shown] == a and sent[#sent].dom == "modalert", "it shows once, claimed like a chat alert")
for i = 6, 14 do NOW = NOW + 1; say("Thrall", "line " .. i) end
check(#floods() == 1 and a.count == 14 and #a.lines == F.SURGE_LINES and a.lines[#a.lines] == "line 14",
      "the surge stays one alert, its count growing, its lines capped")
check(touched > 0, "the window showing it redraws")
runTimers()
check(#shown == 1, "never a second window for the same surge")
NOW = NOW + 30
say("Thrall", "back to normal")
check(#floods() == 1, "after the window, a calm line flags nothing")
for i = 1, 5 do say("Thrall", "again " .. i) end
check(#floods() == 2, "a new surge after the end is a new alert")
runTimers()

-- ── The same line repeated ──────────────────────────────────────────────
NOW = NOW + 700
F.speakers, F.speakerCount, F.surges = {}, 0, {}
say("Garrosh", "WTB carry")
NOW = NOW + 20; say("Garrosh", "wtb carry")
NOW = NOW + 20; say("Garrosh", "something else")
check(#floods() == 2, "twice is fine")
NOW = NOW + 15; say("Garrosh", "WTB CARRY")
a = floods()[1]
check(a.who == "Garrosh" and a.signal == "repeat" and a.count == 3 and a.lines[1] == "WTB carry", "three times in a minute, with its lines")
runTimers()

-- ── Capitals ────────────────────────────────────────────────────────────
NOW = NOW + 700
say("Jaina", "LOL OK")
say("Jaina", "look at my " .. LINK .. " !!")
check(#floods() == 3, "a short line in capitals and a game link in capitals are fine")
say("Jaina", "COME TO KARA NOW PLEASE")
a = floods()[1]
check(a.who == "Jaina" and a.signal == "caps" and a.count == 1, "a long line in capitals")
runTimers()

-- ── Links ───────────────────────────────────────────────────────────────
NOW = NOW + 700
say("Sylvanas", "my shop: " .. LINK)
say("Sylvanas", "check " .. LINK)
check(#floods() == 4, "the game's links never count")
say("Sylvanas", "cheap gold at goldshop.com")
check(#floods() == 4, "one link is fine")
NOW = NOW + 30
say("Sylvanas", "or https://gold.example/x")
a = floods()[1]
check(a.signal == "links" and a.count == 2 and a.lines[1] == "cheap gold at goldshop.com", "two links in a minute")
runTimers()

-- ── Another officer claimed the surge first ─────────────────────────────
NOW = NOW + 700
local nShown = #shown
for i = 1, 4 do say("Garrosh", "spam " .. i) end
local key = M.ClaimKey("Garrosh", "flood:burst\nspam 5")
onClaim({ act = "claim", data = { k = key } }, "Uther")
say("Garrosh", "spam 5")
runTimers()
check(floods()[1].by == "Uther" and #shown == nShown, "listed as alerted on the other officer's screen, not shown here")

-- ── Who is not flagged ──────────────────────────────────────────────────
NOW = NOW + 700
local n = #floods()
for i = 1, 8 do say("Arthas", "me " .. i); say("Uther", "officer " .. i) end
check(#floods() == n, "my own lines and an officer's lines are not flagged")
officer = false
for i = 1, 8 do say("Thrall", "member client " .. i) end
check(#floods() == n, "a member's client flags nothing")
officer = true
secret = true
for i = 1, 8 do say("Thrall", "secret " .. i) end
secret = false
check(#floods() == n and not F.speakers.Thrall, "nothing is read in a chat lockdown")

-- A signal off, or muted, does not count.
check(F:SetConfig({ burst = { on = false, n = 5, secs = 10 } }), "an officer switches a signal off")
for i = 1, 8 do say("Thrall", "quiet " .. i) end
check(#floods() == n, "a signal off flags nothing")
check(F:SetConfig({}), "and back on")
M.mutes["F:burst"] = NOW + 3600
NOW = NOW + 700
for i = 1, 8 do say("Thrall", "muted " .. i) end
check(#floods() == n, "a muted signal flags nothing for the hour")
M.mutes["F:burst"] = nil
runTimers()

-- ── The guild's limits ──────────────────────────────────────────────────
sent = {}
check(F:SetConfig({ burst = { on = true, n = 6, secs = 12 } }), "an officer sets the limits")
local s = GuildOS.db.settings
check(sent[1].dom == "guildcfg" and sent[1].act == "modflood" and sent[1].opts.rev == s.modFloodAt and sent[1].data.cfg.burst.n == 6,
      "they go to the guild, stamped")
check(F:GetConfig().burst.n == 6, "and are read back")
local at = s.modFloodAt
F:OnConfigSync({ act = "modflood", rev = at - 1, data = { cfg = { burst = { n = 9 } } } })
F:OnConfigSync({ act = "modflood", rev = at, data = { cfg = { burst = { n = 9 } } } })
check(F:GetConfig().burst.n == 6, "an older or tied stamp loses")
F:OnConfigSync({ act = "modflood", rev = at + 1, data = { cfg = { burst = { n = 9, secs = 9999 } } } })
check(F:GetConfig().burst.n == 9 and F:GetConfig().burst.secs == 10 and s.modFloodAt == at + 1, "a newer one wins, a bad limit at its default")
officer = false
F:OnConfigSync({ act = "modflood", rev = at + 5, data = { cfg = { burst = { n = 2 } } } })
check(F:GetConfig().burst.n == 9 and not F:SetConfig({}), "a member keeps nothing and sets nothing")
officer = true
sent = {}
M:PublishConfig()
local acts = {}
for _, e in ipairs(sent) do acts[e.act] = true end
check(acts.modflood, "the officers' regular sync carries the limits too")

-- ── Bounded memory ──────────────────────────────────────────────────────
F.speakers, F.speakerCount, F.surges = {}, 0, {}
for i = 1, F.SPEAKERS_MAX + 50 do say("P" .. i, "hi") end
check(F.speakerCount <= F.SPEAKERS_MAX, "at most 300 speakers")
for _ = 1, 80 do say("P1", "hi") end
check(#F.speakers.P1 <= F.PER_SPEAKER, "at most 50 lines each")
NOW = NOW + F.KEEP + 61
say("P2", "later")
check(F.speakers.P1 == nil, "ten minutes on, a speaker's lines are gone")
runTimers()

-- ── The self-tests the client runs ──────────────────────────────────────
local registered = {}
GuildOS.SelfTest = { Register = function(_, name, fn) registered[#registered + 1] = { name = name, fn = fn } end }
F:_RegisterTests()
check(#registered >= 3, "the self-tests register")
for _, t in ipairs(registered) do
  local ok, why = t.fn()
  check(ok, "selftest " .. t.name .. ": " .. tostring(why))
end


-- ── Review fix: capitals in other scripts ──
local F = GuildOS.ModFlood
check(F.Caps("нужны на ICC25 HC: TANK HEAL DPS, пишите в личку пожалуйста") < 70, "a Russian LFG line with acronyms is not shouting")
check(F.Caps("求组 ICC25 HC 缺 TANK HEAL DPS 来") < 70, "nor a Chinese one")
check(F.Caps("ВСЕ СЮДА БЫСТРО НА БОССА") >= 70, "Russian in capitals is")
print(("mod-flood: %d checks passed"):format(checks))
