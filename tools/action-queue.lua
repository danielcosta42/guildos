-- The officer action queue and what needs a key press (#449; specs/salao/convites.md), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/WhisperQueue.lua, Core/Probe.lua, Modules/RecruitEngagement.lua,
-- Modules/RecruitmentSystem.lua, Modules/RecruitScanner.lua and Modules/ActionQueue.lua, once as each game.
--
--   * Compat: the guild invite through C_GuildInfo.Invite, else the global; who may invite (Anniversary, retail; never
--     Forever); what needs a hardware event by default and as the probe measured it on this build.
--   * The queue: an action runs at once where none is needed, else waits; one per key press; a stale one is passed
--     over; never in combat; the binding's button takes the bulk actions' step when nothing of its own waits; the
--     toast's line names the bound key.
--   * The keyword auto-invite: queued for a key press on retail; on Anniversary at once, its /who first queued (a
--     hardware event) and the invite after the answer; on Forever the /ginvite line to copy, nothing invited.
--   * The scanner's whispers: the rest of a Forever batch wait in the queue too, one per press.
--   * /gos probe invite: a click's attempts answered, a timer's blocked or silent, kept for this build only.
--   * The binding: Bindings.xml's CLICK binding and its name.
--
--   luajit -e 'ADDON="."' tools/action-queue.lua
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

local env
local function fire(event, ...)
  for _, h in ipairs(env.handlers) do
    if h.events[event] and h.frame._fn then h.frame._fn(h.frame, event, ...) end
  end
end

local function load(game)
  env = { handlers = {}, timers = {}, sent = {}, invited = {}, groupInvited = {}, who = {}, printed = {},
          clock = 100, combat = false, hardware = false, bindings = {} }
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) env.printed[#env.printed + 1] = tostring(m) end }
  function CreateFrame()
    local f, ev = {}, {}
    function f:RegisterEvent(e) ev[e] = true end
    function f:UnregisterEvent(e) ev[e] = nil end
    function f:SetScript(_, fn) self._fn = fn; env.handlers[#env.handlers + 1] = { frame = self, events = ev } end
    function f:SetAttribute() end
    return f
  end
  function hooksecurefunc() end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  UnitFullName, C_PlayerInfo = nil, nil
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70170", "", 16001 end
    WOW_PROJECT_ID = 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  elseif game == "retail" then
    function GetBuildInfo() return "12.0.1", "65000", "", 120001 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_ID = 5
  end
  function GetRealmName() return "Realm" end
  function UnitName() return "Chehul" end
  function GetServerTime() return 1790000000 end
  function GetTime() return env.clock end
  time = function() return 1790000000 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  function GetGuildInfo() return "Filhos da Horda", "GM", 0 end
  function GetNumGuildMembers() return 1 end
  function GetGuildRosterInfo(i) if i == 1 then return "Chehul" end end
  function CanGuildInvite() return true end
  function InCombatLockdown() return env.combat end
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  ERR_GUILD_JOIN_S = "%s has joined the guild."
  C_Timer = { After = function(d, fn) env.timers[#env.timers + 1] = { at = env.clock + d, fn = fn } end,
              NewTicker = function() end }
  C_ChatInfo = nil
  function SendChatMessage(msg, chan, _, target)
    env.sent[#env.sent + 1] = { msg = msg, chan = chan, target = target, hardware = env.hardware }
  end
  -- The guild invite: retail and Anniversary have only C_GuildInfo.Invite since 10.2.6 / 2.5.5.
  GuildInvite = nil
  C_GuildInfo = { Invite = function(name)
    if game == "forever" then error("ADDON_ACTION_FORBIDDEN") end
    env.invited[#env.invited + 1] = { name = name, hardware = env.hardware }
  end }
  C_PartyInfo = { InviteUnit = function(name) env.groupInvited[#env.groupInvited + 1] = name end }
  C_FriendList = { SendWho = function(q) env.who[#env.who + 1] = { q = q, hardware = env.hardware } end,
                   SetWhoToUi = function() end, GetNumWhoResults = function() return env.whoResults and #env.whoResults or 0 end,
                   GetWhoInfo = function(i) return env.whoResults[i] end }
  function GetBindingKey(cmd) return env.bindings[cmd] end
  function GetBindingText(k) return k end
  function SetBindingClick(key, button, mouse) env.bindings["CLICK " .. button .. ":" .. mouse] = key; return true end
  function SaveBindings(set) env.saved = set end
  function GetCurrentBindingSet() return 2 end
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  GuildOSDB = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Core/WhisperQueue.lua")
  dofile(ADDON .. "/Core/Probe.lua")
  dofile(ADDON .. "/Modules/RecruitEngagement.lua")
  dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
  dofile(ADDON .. "/Modules/RecruitScanner.lua")
  dofile(ADDON .. "/Modules/ActionQueue.lua")
  GuildOS.db = { recruitment = { welcomeEnabled = true, welcomeMessage = "Bem vindo!", channels = {} },
                 recruitScanner = { template = "Hi [player]", batchMax = 10, cooldownSec = 1800 } }
  GuildOS.CommSystem = { MSG_TYPES = { WELCOME_INTENT = "WI", WELCOME_CLAIM = "WC" }, SendMessage = function() end }
  function GuildOS:IsOfficer() return true end
  GuildOS.Recruitment.ShowWelcomePopup = function() end
  GuildOS.Recruitment:Initialize()
  return GuildOS
end

local function runTimers(upTo)
  while true do
    table.sort(env.timers, function(a, b) return a.at < b.at end)
    local t = env.timers[1]
    if not t or t.at > upTo then break end
    table.remove(env.timers, 1)
    env.clock = t.at
    t.fn()
  end
  env.clock = upTo
end
local function whisper(msg, from) fire("CHAT_MSG_WHISPER", msg, from) end
local function press(AQ)          -- a key press of the binding: a hardware event
  env.hardware = true
  local r = AQ:Next()
  env.hardware = false
  return r
end
local function said(text)
  for _, line in ipairs(env.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

-- ── Compat: who may invite, and how ────────────────────────────────────
local B = load("retail")
local Compat, AQ, R = B.Compat, B.ActionQueue, B.Recruitment
check(B.Client.isRetail and Compat.AddonMayInvite() == true, "retail: an addon may invite again, one key press each")
check(Compat.NeedsClick() == true, "retail: NeedsClick holds")
check(Compat.GuildInvite("Ana") == true and env.invited[1].name == "Ana", "the invite goes through C_GuildInfo.Invite")
C_GuildInfo.Invite = nil
local viaGlobal
GuildInvite = function(n) viaGlobal = n end
check(Compat.GuildInvite("Bob") == true and viaGlobal == "Bob", "a client with only the global uses it")
GuildInvite = nil
check(Compat.GuildInvite("Cid") == false and said("Type /ginvite Cid to invite them."), "with neither, the line to type")
CanGuildInvite = function() return false end
check(Compat.AddonMayInvite() == false, "a rank that may not invite may not")
check(Compat.NeedsHardware("guildInvite") and Compat.NeedsHardware("who") and Compat.NeedsHardware("whisper"),
  "retail: guild invite, /who and whisper need a key press until the probe says otherwise")
check(not Compat.NeedsHardware("groupInvite"), "a group invite needs none (InviteUnit has no #hwevent; it works from a whisper on Forever)")

-- The probe's measurement wins, on its own build only.
GuildOSDB.probeInvite = { build = B.Client.build, results = { groupInvite = { click = true, timer = true },
                          who = { click = true, timer = false }, guildInvite = { click = false, timer = false } } }
check(not Compat.NeedsHardware("groupInvite"), "a group invite the probe saw go from a timer runs at once")
check(Compat.NeedsHardware("who"), "a /who refused from a timer and taken from a click waits for one")
check(Compat.ProbedImpossible("guildInvite") and not Compat.ProbedImpossible("who"), "refused from a click too: impossible here")
GuildOSDB.probeInvite.build = "1"
check(Compat.NeedsHardware("who") and not Compat.ProbedImpossible("guildInvite"),
  "a measurement from another build is not read")
GuildOSDB.probeInvite = nil

-- Binding: the key, shown; set from here, never in combat.
check(AQ:KeyText() == nil, "no key bound yet")
env.combat = true
check(not AQ:BindKey("CTRL-N") and env.bindings[AQ.BINDING] == nil, "no binding is changed in combat")
env.combat = false
check(AQ:BindKey("ctrl-n") and env.bindings[AQ.BINDING] == "CTRL-N" and env.saved == 2, "SetBindingClick, saved")
check(AQ:KeyText() == "CTRL-N", "and the key is read back")

-- ── The queue ──────────────────────────────────────────────────────────
local ran = {}
local function item(kind, name, extra)
  local t = { kind = kind, name = name, run = function() ran[#ran + 1] = name; return true end }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
check(AQ:Add(item("guildInvite", "Ana")) == "queued" and #ran == 0, "an action that needs a key press waits")
check(AQ:Add(item("guildInvite", "Ana")) == "queued" and AQ:Pending() == 1, "the same person and purpose once")
check(AQ:Add(item("who", "Bob")) == "queued" and AQ:Pending() == 2, "a second one queues behind")
check(AQ:PromptText() == "Press CTRL-N (or click) to invite Ana \194\183 1 more", "the toast names the key: " .. AQ:PromptText())
env.bindings[AQ.BINDING] = nil
check(AQ:PromptText() == "Click to invite Ana \194\183 1 more", "unbound, it asks for a click")
env.combat = true
check(AQ:Next() == nil and #ran == 0 and said("Not during combat."), "nothing runs in combat")
env.combat = false
check(press(AQ).name == "Ana" and #ran == 1 and AQ:Pending() == 1, "one action per key press")
check(AQ:Add(item("chat", "Cid"), true) == "ran" and ran[2] == "Cid", "from a click, an action runs at once")
AQ:Add(item("whisper", "Dan", { valid = function() return false end }))
check(AQ:Pending(true) == 1, "a stale action is not counted on the toast")
check(press(AQ).name == "Bob" and ran[3] == "Bob", "the press runs the next that applies")
check(press(AQ) == nil and AQ:Pending() == 0 and #ran == 3, "a stale one is dropped and costs nothing")
AQ:Add(item("chat", "Eve", { ownWindow = true }))
check(AQ:Peek(true) == nil and AQ:PromptText() == nil and AQ:Pending() == 1, "an action with its own window stays off the toast")
check(press(AQ).name == "Eve", "but the key press still does it")

-- The binding's button: the queue's own first, else the bulk actions' line.
local armed, after = 0, 0
B.BulkActions = { Queue = function() return {} end, Current = function() return { name = "Fred" } end,
                  Arm = function() armed = armed + 1; return "/gpromote Fred" end,
                  AfterClick = function() after = after + 1 end }
AQ:Add(item("guildInvite", "Gil"))
check(AQ:Arm(false) == "" and ran[#ran] == "Gil" and armed == 0, "with its own action waiting, the press is that one")
AQ:AfterClick(false)
check(AQ:Arm(false) == "/gpromote Fred" and armed == 1, "with none, the press runs the bulk actions' step")
AQ:AfterClick(false)
check(after == 1, "and its PostClick is the bulk actions'")
check(AQ:Arm(true) == "" and armed == 1, "only the click event that acts")
B.BulkActions = nil

-- ── Keyword auto-invite: retail queues it ──────────────────────────────
CanGuildInvite = function() return true end
C_GuildInfo.Invite = function(name) env.invited[#env.invited + 1] = { name = name, hardware = env.hardware } end
env.invited = {}
local ai = B.db.recruitment.autoInvite
ai.enabled = true
whisper("ginv", "Raikken-Realm")
check(#env.invited == 0 and AQ:Pending() == 1 and AQ:Peek().kind == "guildInvite", "retail: the whisper's invite waits for a key press")
press(AQ)
check(env.invited[1] and env.invited[1].name == "Raikken" and env.invited[1].hardware, "the press invites, inside it")
whisper("ginv", "Raikken-Realm")
check(AQ:Pending() == 0, "on cooldown afterwards: nothing queued")

-- ── Anniversary: as it was, with the /who behind a key press ──────────
B = load("anniversary")
Compat, AQ, R = B.Compat, B.ActionQueue, B.Recruitment
check(not Compat.NeedsHardware("guildInvite") and Compat.NeedsHardware("who"), "Anniversary: the invite runs at once, a /who waits")
ai = B.db.recruitment.autoInvite
ai.enabled = true
whisper("ginv", "Grefer-Realm")
check(env.invited[1] and env.invited[1].name == "Grefer" and AQ:Pending() == 0, "Anniversary: no filter, invited at once")
ai.minLevel = 60
whisper("ginv", "Hana-Realm")
check(#env.who == 0 and AQ:Pending() == 1 and AQ:Peek().kind == "who", "with a filter, the /who waits in the queue")
press(AQ)
check(#env.who == 1 and env.who[1].hardware and env.who[1].q:find("Hana", 1, true), "the press sends the /who")
env.whoResults = { { fullName = "Hana", level = 62, filename = "MAGE" } }
fire("WHO_LIST_UPDATE")
check(env.invited[2] and env.invited[2].name == "Hana", "the answer passes the filter: invited at once")
-- The probe measured /who from an event: then no key press for it.
GuildOSDB.probeInvite = { build = B.Client.build, results = { who = { click = true, timer = true } } }
whisper("ginv", "Iris-Realm")
check(#env.who == 2 and AQ:Pending() == 0, "where the probe says a /who goes from an event, it goes")
GuildOSDB.probeInvite = nil

-- ── Forever: the line to copy, never an invite ─────────────────────────
B = load("forever")
Compat, AQ, R = B.Compat, B.ActionQueue, B.Recruitment
check(Compat.AddonMayInvite() == false, "Forever: still no addon invite (#256)")
local offered = 0
AQ.onTyped = function() offered = offered + 1 end
B.db.recruitment.autoInvite.enabled = true
whisper("ginv", "Raikken Shadowmaster")
check(#env.invited == 0 and offered == 1 and AQ:NextTyped() == "Raikken Shadowmaster", "Forever: the keyword offers the line to copy")
check(AQ.TypedLine("Raikken Shadowmaster") == "/ginvite Raikken Shadowmaster", "the line is /ginvite and the whole name")
whisper("ginv", "Raikken Shadowmaster")
check(select(2, AQ:NextTyped()) == 1, "once a person")
check(AQ:DoneTyped() == nil and AQ:NextTyped() == nil, "copied: none left")

-- Forever: the scanner's batch waits in the queue too.
local S = B.RecruitScanner
S._results = { { name = "Ana", level = 60 }, { name = "Bob", level = 60 }, { name = "Cid", level = 60 } }
S._contactCd = {}
S:WhisperSelected({ "Ana", "Bob", "Cid" })
check(#env.sent == 1 and S:PendingWhispers() == 2 and AQ:Pending() == 2, "the first in the click, two in the queue")
check(AQ:Peek().name == "Bob" and AQ:PromptText():find("whisper Bob", 1, true), "the toast says whom")
S:WhisperNext()
check(AQ:Pending() == 1 and AQ:Peek().name == "Cid", "the panel's Whisper next takes it off the queue")
press(AQ)
check(#env.sent == 3 and env.sent[3].target == "Cid" and S:PendingWhispers() == 0, "the key press sends the last")

-- Forever: the welcome's key press sends it, and its popup stays its window.
R:QueueWelcome("Xayide")
check(AQ:Pending() == 1 and AQ:Peek(true) == nil, "the welcome waits, off the toast")
press(AQ)
check(env.sent[4] and env.sent[4].chan == "GUILD" and AQ:Pending() == 0, "the key press posts it")

-- ── /gos probe invite ─────────────────────────────────────────────────
B = load("retail")
local Probe = B.Probe
function B.Compat.ChannelId() return 7 end
function B.Compat.JoinChannel() end
function B.Compat.LeaveChannel() return true end
-- The client: a call made inside a key press is answered with the name in a system line; from a timer the invite
-- is blocked, the /who is silent and the whisper answered.
C_GuildInfo.Invite = function(name)
  if env.hardware then fire("CHAT_MSG_SYSTEM", "Player " .. name .. " not found.")
  else fire("ADDON_ACTION_BLOCKED", "GuildOS", "C_GuildInfo.Invite") end
end
C_PartyInfo.InviteUnit = function(name) fire("CHAT_MSG_SYSTEM", "Cannot find player '" .. name .. "'.") end
C_FriendList.SendWho = function() if env.hardware then fire("WHO_LIST_UPDATE") end end
SendChatMessage = function(msg, chan, _, target)
  if chan == "WHISPER" then fire("CHAT_MSG_SYSTEM", "No player named '" .. target .. "' is currently playing.")
  elseif env.hardware then fire("CHAT_MSG_CHANNEL", msg) end
end
env.hardware = true
local run = Probe:RunInvite()
env.hardware = false
check(run and Probe:RunInvite() == nil, "one probe at a time")
runTimers(env.clock + 20)
local out = GuildOSDB.probeInvite
check(out and out.build == B.Client.build, "kept for this build")
check(out.results.guildInvite.click == true and out.results.guildInvite.timer == false
  and out.raw.guildInvite.timer == false, "guild invite: answered from the key press, blocked from the timer")
check(out.results.who.click == true and out.results.who.timer == false and out.raw.who.timer == "silent",
  "/who: the timer's went unanswered")
check(out.results.groupInvite.timer == true and out.results.whisper.timer == true, "group invite and whisper go from a timer")
check(out.results.channel.click == true and out.raw.channel.timer == "silent", "the channel line only from the key press")
check(B.Compat.NeedsHardware("guildInvite") and not B.Compat.NeedsHardware("groupInvite") and B.Compat.NeedsHardware("who"),
  "Compat reads it")
check(type(out.tabard) == "table" and out.tabard.source == "none", "the tabard's APIs are kept with it")

-- Forever: the guild invite is not tried, and kept as refused.
B = load("forever")
function B.Compat.ChannelId() return 0 end
function B.Compat.JoinChannel() end
function B.Compat.LeaveChannel() return true end
local tried = false
C_GuildInfo.Invite = function() tried = true end
env.hardware = true
B.Probe:RunInvite()
env.hardware = false
runTimers(env.clock + 20)
out = GuildOSDB.probeInvite
check(not tried and out.results.guildInvite.click == false and out.raw.guildInvite.click:find("forbidden", 1, true),
  "Forever: no guild invite is tried, it is recorded as forbidden")
check(out.results.channel.click == nil and out.raw.channel.click == "no channel number", "a channel with no number is not tried")

-- ── The toast and the line to copy (UI/ActionQueue.lua), on stub frames ─
B = load("retail")
AQ = B.ActionQueue
local made = {}
local Stub = {}
Stub.__index = function(t, k)
  if Stub[k] then return Stub[k] end
  if type(k) == "string" and k:match("^%u") then return function() end end
end
local function stub(kind)
  local f = setmetatable({ kind = kind, shown = kind ~= "window", scripts = {}, hooks = {}, h = 0 }, Stub)
  made[#made + 1] = f
  return f
end
function Stub:Show() self.shown = true end
function Stub:Hide()
  if not self.shown then return end
  self.shown = false
  for _, fn in ipairs(self.hooks.OnHide or {}) do fn(self) end
end
function Stub:IsShown() return self.shown end
function Stub:SetText(t) self.text = t end
function Stub:GetText() return self.text end
function Stub:SetHeight(h) self.h = h end
function Stub:GetStringHeight() return 14 end
function Stub:SetScript(k, fn) self.scripts[k] = fn end
function Stub:HookScript(k, fn) self.hooks[k] = self.hooks[k] or {}; table.insert(self.hooks[k], fn) end
function Stub:SetFocus() self.focus = true end
function Stub:HighlightText() self.highlighted = true end
function Stub:GetPoint() return "TOP", nil, "TOP", 12.4, -150.6 end
CreateFrame = function(kind, name) local f = stub(kind); f.name = name; return f end
UIParent = stub("Frame")
B.Kit = { HEADER_H = 32, PAD = 16, Float = function(_, title, opts)
  local f = stub("window")
  f.header, f.body, f.title, f.opts = stub("Frame"), stub("Frame"), title, opts
  function f:SetTitle(t, sub) self.title, self.sub = t, sub end
  return f
end }
B.UI = { SP = { BODY = 13, FIELD = 26, FIELD_GAP = 12, UNIT = 4, PAD = 16 },
         CreateText = function() return stub("FontString") end,
         CreateButton = function() local b = stub("Button"); b.label = stub("FontString"); return b end,
         CreateInput = function() return stub("EditBox") end, SetButtonVariant = function() end }
local whenClear = {}
function B:ShowWhenClear(key, fn) whenClear[#whenClear + 1] = key; fn() end
function B:CancelWhenClear() end
function B:SafeCall(fn, ...) return fn(...) end
B.db.settings = {}
function B:GetSetting(k) return self.db.settings[k] end
function B:SetSetting(k, v) self.db.settings[k] = v end
dofile(ADDON .. "/UI/ActionQueue.lua")
local secure
for _, f in ipairs(made) do if f.name == "GuildOSQueueNext" then secure = f end end
check(secure and secure.scripts.PreClick and secure.scripts.PostClick, "the binding's button is made out of combat at load")
ran = {}
AQ:Add(item("guildInvite", "Ana"))
local toast
for _, f in ipairs(made) do if f.kind == "window" and f.title == "Officer queue" then toast = f end end
check(toast and toast.shown and whenClear[1] == "actionqueue", "an action that waits opens the toast, through ShowWhenClear")
local lineFS
for _, f in ipairs(made) do if f.kind == "FontString" and f.text and f.text:find("Ana", 1, true) then lineFS = f end end
check(lineFS and lineFS.text == "Click to invite Ana" and toast.h > 32, "it says what the click does, grown to the line")
toast.opts.onClose(toast)
check(not toast.shown, "the close hides it")
AQ:Remove("guildInvite:Ana")
AQ:Add(item("guildInvite", "Bob"))
check(toast.shown and lineFS.text == "Click to invite Bob", "the next action brings it back")
local go
for _, f in ipairs(made) do if f.kind == "Button" and f.scripts.OnClick and f.label and f.label.text == "Invite" then go = f end end
check(go, "its button says the action")
env.hardware = true
go.scripts.OnClick(go)
env.hardware = false
check(ran[#ran] == "Bob" and not toast.shown, "its click runs it, and with nothing left it goes")
AQ:Add(item("who", "Cid"))
env.hardware = true
secure.scripts.PreClick(secure, "LeftButton", false)
secure.scripts.PostClick(secure, "LeftButton", false)
env.hardware = false
check(ran[#ran] == "Cid", "the key press (the button's PreClick) runs the next one")
env.combat = true
fire("PLAYER_REGEN_DISABLED")
AQ:Add(item("who", "Dan"))
env.combat = false
-- Line to copy (Forever's): selected, read-only, gone on Enter, the next after it.
AQ:OfferTyped("Eva Lima")
AQ:OfferTyped("Fred Melo")
local typedWin, box
for _, f in ipairs(made) do
  if f.kind == "window" and f.title == "Invite to the guild" then typedWin = f end
  if f.kind == "EditBox" then box = f end
end
check(typedWin and typedWin.shown and box.text == "/ginvite Eva Lima" and box.focus and box.highlighted,
  "the /ginvite line, selected in its box")
box.text = "typed over"
for _, fn in ipairs(box.hooks.OnTextChanged) do fn(box, true) end
check(box.text == "/ginvite Eva Lima", "read-only: the line comes back")
box.scripts.OnEnterPressed(box)
check(AQ:NextTyped() == "Fred Melo" and typedWin.shown and box.text == "/ginvite Fred Melo", "Enter: the next one")
typedWin.opts.onClose(typedWin)
check(AQ:NextTyped() == nil and not typedWin.shown, "the close: done")

-- ── The binding ───────────────────────────────────────────────────────
local fh = assert(io.open(ADDON .. "/Bindings.xml", "rb"))
local xml = fh:read("*a")
fh:close()
check(xml:find('<Binding name="GUILDOS_TOGGLE"', 1, true), "the window's binding stays")
check(xml:find('<Binding name="CLICK GuildOSQueueNext:LeftButton"', 1, true), "the queue's binding clicks its button")
fh = assert(io.open(ADDON .. "/UI/ActionQueue.lua", "rb"))
local ui = fh:read("*a")
fh:close()
check(ui:find('_G["BINDING_NAME_CLICK GuildOSQueueNext:LeftButton"] = L["Guild OS: next in the queue"]', 1, true),
  "its name in Key Bindings is localized")
check(ui:find('"SecureActionButtonTemplate"', 1, true) and ui:find("GuildOS:ShowWhenClear(\"actionqueue\"", 1, true),
  "a secure button, and the toast never over a fight")
check(not ui:find("ChatFrame_OpenChat", 1, true) and not ui:find("ChatEdit_", 1, true),
  "the /ginvite line is never put in the chat box (#256)")

print(("action-queue: %d checks passed"):format(checks))
