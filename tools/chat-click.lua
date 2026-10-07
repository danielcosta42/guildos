-- Chat lines that need a click on WoW: Forever (issue #61), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/RecruitEngagement.lua, Modules/RecruitmentSystem.lua
-- and Modules/RecruitScanner.lua, once as each game.
--
-- Forever drops a chat line an addon sends from a timer: the welcome (a 2s timer after the
-- join) and the scanner's whispers (1.5s apart) never went out. There the welcome waits in a
-- popup for the officer's click, and the whispers go out one per click. Anniversary is as it was.
--
--   luajit -e 'ADDON="."' tools/chat-click.lua
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

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  local handlers = {}
  function CreateFrame()
    local f, ev = {}, {}
    function f:RegisterEvent(e) ev[e] = true end
    function f:UnregisterEvent(e) ev[e] = nil end
    function f:SetScript(_, fn) self._fn = fn; handlers[#handlers + 1] = { frame = self, events = ev } end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70170", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    UnitFullName, C_PlayerInfo = nil, nil
  end
  function GetRealmName() return "Realm" end
  function UnitName() return "Chehul" end
  function GetServerTime() return 1790000000 end
  time = function() return 1790000000 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  function GetGuildInfo() return "Filhos da Horda", "GM", 0 end
  function GetNumGuildMembers() return 1 end
  function GetGuildRosterInfo(i) if i == 1 then return "Chehul" end end
  function CanGuildInvite() return true end
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  ERR_GUILD_JOIN_S = "%s has joined the guild."
  local timers = {}
  C_Timer = { After = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end, NewTicker = function() end }
  local sent = {}
  function SendChatMessage(msg, chan, _, target) sent[#sent + 1] = { msg = msg, chan = chan, target = target } end
  local invited = {}
  function GuildInvite(name) invited[#invited + 1] = name end
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/RecruitEngagement.lua")
  dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
  dofile(ADDON .. "/Modules/RecruitScanner.lua")
  GuildOS.db = { recruitment = { welcomeEnabled = true, welcomeMessage = "Bem vindo aos Filhos da Horda!", channels = {} },
                recruitScanner = { template = "Hi [player]", batchMax = 10, cooldownSec = 1800 } }
  GuildOS.CommSystem = { MSG_TYPES = { WELCOME_INTENT = "WI", WELCOME_CLAIM = "WC" }, SendMessage = function() end }
  function GuildOS:IsOfficer() return true end
  local env = { handlers = handlers, timers = timers, sent = sent, invited = invited, shown = 0, invitePopup = 0 }
  GuildOS.Recruitment.ShowInvitePopup = function() env.invitePopup = env.invitePopup + 1 end
  -- The popup is the UI's; here it only has to be asked for.
  GuildOS.Recruitment.ShowWelcomePopup = function() env.shown = env.shown + 1 end
  function env.runTimers(upTo)
    table.sort(timers, function(a, b) return a.d < b.d end)
    local due = {}
    for i = #timers, 1, -1 do
      if timers[i].d <= upTo then table.insert(due, 1, table.remove(timers, i)) end
    end
    for _, t in ipairs(due) do t.fn() end
  end
  function env.whisper(msg, from)
    for _, h in ipairs(handlers) do
      if h.events.CHAT_MSG_WHISPER then h.frame._fn(h.frame, "CHAT_MSG_WHISPER", msg, from) end
    end
  end
  function env.join(name)
    for _, h in ipairs(handlers) do
      if h.events.CHAT_MSG_SYSTEM then h.frame._fn(h.frame, "CHAT_MSG_SYSTEM", name .. " has joined the guild.") end
    end
  end
  return GuildOS, env
end

-- ── Forever: the welcome waits for a click ──────────────────────────────
local B, env = load("forever")
local R, S = B.Recruitment, B.RecruitScanner
check(B.Compat.NeedsClick() == true, "Forever: a chat line needs a click")
R:Initialize()
env.runTimers(8)
env.join("Xayide Kholin")
env.runTimers(2)
check(#env.sent == 0, "Forever: nothing is sent from the timer, where the game would drop it")
check(env.shown == 1 and R._pendingWelcomes[1] == "Xayide Kholin", "the welcome waits in the popup")
env.join("Koda Timberstride")
env.runTimers(2)
check(#R._pendingWelcomes == 2 and env.shown == 2, "a second join joins the same popup")
check(R:SendPendingWelcome() == true, "the click sends")
check(#env.sent == 1 and env.sent[1].chan == "GUILD" and env.sent[1].msg == "Bem vindo aos Filhos da Horda!",
      "one welcome, in guild chat, for both")
check(#R._pendingWelcomes == 0, "and the popup is empty after")
check(R:SendPendingWelcome() == false and #env.sent == 1, "a second click with nobody waiting sends nothing")
R:QueueWelcome("Mata Ratos")
R:DismissPendingWelcome()
check(#R._pendingWelcomes == 0 and R:SendPendingWelcome() == false, "Not now drops who was waiting")

-- ── Forever: an auto-invite waits for a click ───────────────────────────
local ai = B.db.recruitment.autoInvite
ai.enabled, ai.minLevel, ai.classes = true, 55, { MAGE = true }   -- filters set: Forever cannot /who them
env.whisper("ginv", "Raikken Shadowmaster-Realm")
env.whisper("ginv please", "Raikken Shadowmaster-Realm")
check(#env.invited == 0, "Forever: nobody is invited from the whisper, where the game would drop it")
check(env.invitePopup >= 1 and #R._pendingInvites == 1 and R._pendingInvites[1].name == "Raikken Shadowmaster",
      "the asker waits in the popup, once, with no /who it could not run")
env.whisper("ginv", "Bran Stone-Realm")
check(R:InviteNext() == 1 and env.invited[1] == "Raikken Shadowmaster-Realm",
      "the click invites the first, by the name the whisper carried, as an Alt-click's link does")
check(R:SkipNext() == 0 and #env.invited == 1, "Skip invites nobody")
env.whisper("ginv", "Bran Stone-Realm")
check(#R._pendingInvites == 0, "and a skipped asker is not asked about again inside the cooldown")
local bans = {}
B.BanList = { IsBanned = function(_, n) return bans[n] end }
env.whisper("ginv", "Evil Guy-Realm")
bans["Evil Guy"] = true                 -- a ban that arrives while the name waits
env.whisper("ginv", "Unseen Person-Realm")
check(R:InviteNext() == 1 and #env.invited == 1, "a name banned since it was queued is not invited")
check(#R._pendingInvites == 1 and R._pendingInvites[1].name == "Unseen Person",
      "and the click does not move on to someone the popup never showed")

-- ── Forever: whispers go out one per click ──────────────────────────────
S._results = { { name = "Ana", level = 60 }, { name = "Bob", level = 60 }, { name = "Cid", level = 60 } }
S._contactCd = {}
local before, timersBefore = #env.sent, #env.timers
S:WhisperSelected({ "Ana", "Bob", "Cid" })
check(#env.sent == before + 1 and env.sent[#env.sent].chan == "WHISPER", "Forever: the first whisper goes out in the click")
check(#env.timers == timersBefore and S:PendingWhispers() == 2, "and the rest wait for the next clicks, not a timer")
check(S:WhisperNext() == 1 and S:WhisperNext() == 0, "each click sends the next")
check(#env.sent == before + 3, "three whispers in all")
check(S:WhisperNext() == 0 and #env.sent == before + 3, "and a click with none left sends nothing")
S._contactCd = {}
S:WhisperSelected({ "Ana", "Bob", "Cid" })
check(S._contactCd.Ana and not S._contactCd.Bob, "only who was whispered is on cooldown")
S._scanBusy = nil
function B:IsOfficer() return true end
GuildOS.Compat.SendWho, GuildOS.Compat.SetWhoToUI = function() end, function() end
S:Scan()
check(S:PendingWhispers() == 0, "a new scan drops a batch left half sent")
local targets = {}
for i = before + 1, before + 3 do targets[#targets + 1] = env.sent[i].target end
table.sort(targets)
check(table.concat(targets, ",") == "Ana,Bob,Cid", "each candidate once")

-- ── Anniversary: as it was ──────────────────────────────────────────────
B, env = load("anniversary")
R, S = B.Recruitment, B.RecruitScanner
check(B.Compat.NeedsClick() == false, "Anniversary: no click needed")
R:Initialize()
env.runTimers(8)
env.join("Grefer")
env.runTimers(2)
check(#env.sent == 1 and env.sent[1].chan == "GUILD" and env.shown == 0, "Anniversary: the welcome goes out on its own")
S._results = { { name = "Ana" }, { name = "Bob" } }
S._contactCd = {}
S:WhisperSelected({ "Ana", "Bob" })
check(#env.sent == 1 and S:PendingWhispers() == 0, "Anniversary: whispers are timed, none in the click")
env.runTimers(10)
check(#env.sent == 3, "and both go out")
local aiA = B.db.recruitment.autoInvite
aiA.enabled = true
env.whisper("ginv", "Grefer-Realm")
check(env.invited[1] == "Grefer" and env.invitePopup == 0, "Anniversary: the auto-invite goes out on its own")

print(("chat-click: %d checks passed"):format(checks))
