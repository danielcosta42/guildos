-- The officers' chat alerts (issue #404), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua and Modules/ModAlerts.lua under a stubbed client.
--
-- A line of /g that matches the guild's list alerts an officer once: matched without case or accents, as
-- whole words, a Lua pattern guarded; the officers' own lines and an officer's lines skipped; one alert per
-- line among the officers (the first claim wins, never twice on one client); low only logs; nothing is
-- read in a chat lockdown; the list is the officers', newest stamp wins; Warn hands the line to #403.
--
--   luajit -e 'ADDON="."' tools/mod-alerts.lua
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

local M = GuildOS.ModAlerts
local officer = true
local officers = { Uther = true }
function GuildOS:IsOfficer() return officer end
function GuildOS:IsOfficerByName(n) return officers[(n:match("^([^-]+)"))] == true end
GuildOS.Compat.PlayerName = function() return "Arthas" end
local lockdown = false
GuildOS.Compat.InChatLockdown = function() return lockdown end
local sent, onClaim = {}, nil
GuildOS.SyncService = {
  On = function(_, dom, fn) if dom == "modalert" then onClaim = fn end end,
  Publish = function(_, dom, act, data, opts) sent[#sent + 1] = { dom = dom, act = act, data = data, opts = opts } end,
}
local shown = {}
function GuildOS:ShowModAlert(a) shown[#shown + 1] = a end
local warned
function GuildOS:ShowWarnDialog(key, name, opts) warned = { key = key, name = name, opts = opts } end
local chatLog = {}
GuildOS.GuildChat = { Log = function() return chatLog end }
GuildOS.db = { settings = {} }
M:Initialize()

local function say(author, msg) onEvent(nil, "CHAT_MSG_GUILD", msg, author) end
local function lastSent() return sent[#sent] end

-- ── The pure helpers ────────────────────────────────────────────────────
check(M.Fold("ÁÉÍÓÚ àèìòù ÇÑ ção") == "aeiou aeiou cn cao", "accents fold, both cases")
check(M.Plain("a |cffff0000red|r |Hitem:19019|h[Thunderfury]|h |TInterface\\x:0|t b") == "a red [Thunderfury]  b",
      "colours and textures go, a link reads as its text")
local folded, words = M.Prepare("Vendo GOLD-barato!!")
check(folded == "vendo gold-barato!!" and words == " vendo gold barato ", "a line made ready once")
check(M.CleanRule({ p = "  gold ", cat = "trade", sev = "high" }).p == "gold", "a rule is trimmed")
check(select(2, M.CleanRule({ p = "x", cat = "rude", sev = "high" })) == "category", "an unknown category is refused")
check(select(2, M.CleanRule({ p = "x", cat = "trade", sev = "max" })) == "severity", "an unknown severity is refused")
check(select(2, M.CleanRule({ p = "a|cff", cat = "trade", sev = "low" })) == "empty", "no game codes in a rule")
check(select(2, M.CleanRule({ p = "!!!", cat = "trade", sev = "low" })) == "empty", "punctuation alone matches nothing")
check(select(2, M.CleanRule({ p = "(%d+", cat = "trade", sev = "low", lua = true })) == "invalid", "an unfinished capture is refused")
check(select(2, M.CleanRule({ p = "x*", cat = "trade", sev = "low", lua = true })) == "broad", "a pattern that matches nothing at all is too broad")
check(select(2, M.CleanRule({ p = string.rep("a", 61), cat = "trade", sev = "low" })) == "long", "60 bytes at most")
local vr = M.ValidRules({ { p = "Gold", cat = "trade", sev = "high" }, { p = "gold", cat = "custom", sev = "low" }, { p = "" } })
check(#vr == 1, "duplicates (by folded text) and bad rules drop")
check(M.Hash("abc") == M.Hash("abc") and M.Hash("abc") ~= M.Hash("abd") and #M.Hash("x") == 8, "the hash")
local ctx = M.Context({ { n = "A", m = "one" }, { n = "B", m = "two" }, { n = "C", m = "three" }, { n = "D", m = "bad" } }, "bad", 2)
check(#ctx == 2 and ctx[1].m == "two" and ctx[2].m == "three", "the two lines before, the flagged one left out")
ctx = M.Context({ { n = "A", m = "one" }, { n = "B", m = "two" } }, "bad", 2)
check(#ctx == 2 and ctx[2].m == "two", "and when the log does not hold it yet")
check(#M.Context({}, "x", 2) == 0, "an empty log")

-- Highest severity first.
local comp = M.Compile({ { p = "gold", cat = "custom", sev = "low" }, { p = "cheap gold", cat = "trade", sev = "high" } }, "enUS")
folded, words = M.Prepare("CHEAP gold here")
check(M.Match(comp, folded, words, nil, 0).sev == "high", "the highest severity wins")
check(M.Match(comp, folded, words, { [comp[1].key] = NOW + 10 }, NOW).sev == "low", "a muted rule is skipped")
-- CJK: no word edges.
local cjk = M.Compile({ { p = "金币", cat = "trade", sev = "high" } }, "zhCN")
folded, words = M.Prepare("便宜金币出售")
check(M.Match(cjk, folded, words, nil, 0), "a CJK word is any stretch of the line")

-- ── The default list ────────────────────────────────────────────────────
local defaults = M.DefaultRules()
check(#defaults >= 10 and M:GetRules()[1].p == defaults[1].p, "the default list before any officer chose one")
for _, r in ipairs(defaults) do check(M.CleanRule(r), "every default cleans: " .. r.p) end

-- ── Alerts ──────────────────────────────────────────────────────────────
chatLog[#chatLog + 1] = { n = "Jaina", m = "hello" }
chatLog[#chatLog + 1] = { n = "Thrall", m = "anyone up for kara?" }
say("Thrall-Classic Beta PvE 2", "I can sell gold cheap, whisper")
check(#M:Feed() == 1 and #shown == 0, "a match goes on the list at once, the window waits for the claim")
local a = M:Feed()[1]
check(a.who == "Thrall" and a.cat == "trade" and a.sev == "high" and #a.context == 2 and a.context[2].m == "anyone up for kara?",
      "who, the category and the two lines before")
runTimers()
check(#shown == 1 and shown[1] == a, "then it shows")
check(lastSent().dom == "modalert" and lastSent().act == "claim" and lastSent().data.k == a.claim, "and the claim goes to the officers")
check(not lastSent().data.k:find("gold") and lastSent().opts.priority == "ALERT", "only a hash travels, fast")
say("Thrall-Classic Beta PvE 2", "I can sell gold cheap, whisper")
runTimers()
check(#shown == 1 and #M:Feed() == 1, "the same line again on this client: never twice")

-- Another officer claims first.
local nSent = #sent
say("Garrosh", "wts boost, cheap")
local b = M:Feed()[1]
onClaim({ act = "claim", data = { k = b.claim } }, "Uther")
runTimers()
check(#shown == 1 and b.by == "Uther" and #sent == nSent, "another officer's claim landed first: only listed, no second claim")
onClaim({ act = "claim", data = { k = "not hex!" } }, "Uther")
onClaim({ act = "claim", data = { k = "0123456789" } }, "Uther")
check(M.claims["not hex!"] == nil and M.claims["0123456789"] == nil, "a claim of any other shape is dropped")
-- A claim heard before the line.
local key = M.ClaimKey("Garrosh", "buy gold now")
onClaim({ act = "claim", data = { k = key } }, "Uther")
say("Garrosh", "buy gold now")
check(M:Feed()[1].by == "Uther", "a claim heard before the line: listed as theirs")
runTimers()
check(#shown == 1, "and not shown")

-- Lines that do not fire.
local before = #M:Feed()
say("Arthas", "selling gold cheap")
say("Uther-Classic Beta PvE 2", "selling gold cheap")
say("Thrall", "goldshire is nice")
check(#M:Feed() == before, "my own line, an officer's line and part of a word do not fire")
M:Prefs().officers, M:Prefs().own = true, true
say("Uther", "sell gold here")
check(#M:Feed() == before + 1, "unless the officer asks for them")
M:Prefs().officers, M:Prefs().own = false, false
runTimers()

-- Low only logs.
M.compiled = M.Compile({ { p = "kara", cat = "custom", sev = "low" } }, "enUS")
local nShown = #shown
say("Thrall", "KARA tonight?")
runTimers()
check(M:Feed()[1].sev == "low" and #shown == nShown, "low goes on the list and nowhere else")

-- Lockdown: nothing is read.
secret = true
local refreshed = 0
M.uiRefresh = function() refreshed = refreshed + 1 end
before = #M:Feed()
say("Thrall", "kara")
check(#M:Feed() == before and refreshed == 1, "a secret line is not read, and the panel hears of the pause")
secret = false
lockdown = true
check(M:Paused(), "the panel shows the pause while the game holds the chat")
lockdown = false
M.uiRefresh = nil

-- A member's client does nothing.
officer = false
before = #M:Feed()
say("Thrall", "kara")
check(#M:Feed() == before, "a member's client matches nothing")
officer = true

-- The officer's actions.
local fid = M:Feed()[1].id
check(M:MuteRule(fid) and M.mutes[M:Feed()[1].rule] == NOW + 3600, "Mute for an hour")
say("Thrall", "kara again")
check(#M:Feed() == before, "a muted rule does not fire")
NOW = NOW + 3601
say("Thrall", "kara again")
check(#M:Feed() == before + 1, "and fires again after the hour")
check(M:Ignore(M:Feed()[1].id) and M:Feed()[1].state == "ignored", "Ignore")
check(M:Warn(a.id) and warned.key == GuildOS:KeyOfRosterName("Thrall-Classic Beta PvE 2") and warned.name == "Thrall"
      and warned.opts.excerpt == "I can sell gold cheap, whisper" and warned.opts.reason == "trade", "Warn opens #403 with the line")
check(a.state == "warned", "and marks it")

-- The list is kept in memory, bounded and short-lived.
for i = 1, 80 do say("Thrall", "kara " .. i) end
check(#M:Feed() == M.FEED_MAX, "at most 50")
NOW = NOW + M.FEED_TTL + 1
check(#M:Feed() == 0, "and for two hours")
check(GuildOS.db.modAlerts.feed == nil and GuildOS.db.settings.modAlertFeed == nil, "nothing of it on disk")

-- ── The guild's list ────────────────────────────────────────────────────
M:Recompile()
sent = {}
check(M:AddRule("noob", "offense", "med"), "an officer adds a word")
local s = GuildOS.db.settings
check(s.modAlertRulesAt == NOW and #s.modAlertRules == #defaults + 1, "stamped, on top of the defaults")
check(sent[1].dom == "guildcfg" and sent[1].act == "modrules" and sent[1].opts.rev == s.modAlertRulesAt, "and it goes to the guild")
check(select(2, M:AddRule("NOOB", "custom", "low")) == "dupe", "the same word again is refused")
check(select(2, M:AddRule("[x", "custom", "low", true)) == "invalid", "an invalid pattern is refused")
say("Thrall", "what a Noob")
check(M:Feed()[1] and M:Feed()[1].cat == "offense", "compiled at once")
check(M:RemoveRule(#M:GetRules()) and #M:GetRules() == #defaults, "an officer removes one")
while #M:GetRules() > 0 do M:RemoveRule(1) end
check(M:IsCustomList() and #M:GetRules() == 0, "an empty list is a choice")
local n = #M:Feed()
say("Thrall", "sell gold")
check(#M:Feed() == n, "and with it nothing fires")
check(M:RestoreDefaults() and #M:GetRules() == #defaults, "the defaults come back")
officer = false
check(not M:AddRule("x1x", "custom", "low") and not M:RemoveRule(1), "a member edits nothing")
officer = true

local at = s.modAlertRulesAt
M:OnConfigSync({ act = "modrules", rev = at - 5, data = { rules = { { p = "old", cat = "custom", sev = "low" } } } })
check(#M:GetRules() == #defaults, "an older list loses")
M:OnConfigSync({ act = "modrules", rev = at, data = { rules = { { p = "tie", cat = "custom", sev = "low" } } } })
check(#M:GetRules() == #defaults, "a tie keeps what is held")
M:OnConfigSync({ act = "modrules", rev = at + 1, data = { rules = { { p = "newer", cat = "custom", sev = "high" }, { p = "[x", cat = "custom", sev = "low", lua = true } } } })
check(#M:GetRules() == 1 and M:GetRules()[1].p == "newer" and s.modAlertRulesAt == at + 1, "a newer one is kept, its bad rules dropped")
M:OnConfigSync({ act = "modrules", rev = NOW + 99999, data = { rules = {} } })
check(s.modAlertRulesAt == NOW + 300, "a stamp from the future is held to a few minutes ahead")
officer = false
M:OnConfigSync({ act = "modrules", rev = NOW + 400, data = { rules = { { p = "x", cat = "custom", sev = "low" } } } })
check(#M:GetRules() == 0, "a member's client keeps no list")
officer = true

-- ── The self-tests the client runs ──────────────────────────────────────
local registered = {}
GuildOS.SelfTest = { Register = function(_, name, fn) registered[#registered + 1] = { name = name, fn = fn } end }
M:_RegisterTests()
check(#registered >= 3, "the self-tests register")
for _, t in ipairs(registered) do
  local ok, why = t.fn()
  check(ok, "selftest " .. t.name .. ": " .. tostring(why))
end

print(("mod-alerts: %d checks passed"):format(checks))
