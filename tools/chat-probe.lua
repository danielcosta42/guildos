-- /guildos probe chat and the blocked-action record (issue #75), run against the real
-- Core/Core.lua, Core/Compat.lua and Core/Probe.lua, once as each game.
--
-- When the game blocks a protected call, chat gets "Interface action failed because of an
-- AddOn" once a session, with no Lua error and no function named. ADDON_ACTION_* and
-- MACRO_ACTION_* name the function (and the addon): they go to /guildos errors, and the chat
-- probe measures a line from the command against a line from a timer by whether the game
-- echoes each one back, next to the client's own addon restriction states.
--
--   luajit -e 'ADDON="."' tools/chat-probe.lua
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

-- A secret value the way the client has it: comparing it, printing it or joining it raises.
local ffi = require("ffi")
ffi.cdef("typedef struct { int x; } gos_secret_t;")
local SECRET = ffi.metatype("gos_secret_t", {
  __eq = function() error("a secret value was compared") end,
  __tostring = function() error("a secret value was turned into text") end,
  __concat = function() error("a secret value was concatenated") end,
})()

local frames, timers, printed, sent, clock, hardware

-- The client: frames that take events, a timer queue run by hand, and a SendChatMessage that
-- behaves like the game. Forever echoes a line only when a key press is behind it and otherwise
-- blocks it, synchronously, the way ADDON_ACTION_BLOCKED is documented; Anniversary echoes
-- everything. The echo comes back a moment later, as chat does. `echo` replaces what comes back.
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.fn then f.fn(f, event, ...) end
  end
end
local function load(game, opts)
  opts = opts or {}
  frames, timers, printed, sent, clock, hardware = {}, {}, {}, {}, 100, false
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = tostring(msg) end }
  function CreateFrame()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(_, fn) self.fn = fn end
    frames[#frames + 1] = f
    return f
  end
  function hooksecurefunc() end
  function GetTime() return clock end
  function GetServerTime() return 1759500000 end
  C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
  function issecretvalue(v) return rawequal(v, SECRET) end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  C_ChatInfo = { InChatMessagingLockdown = function() return false end }
  Enum = { SendAddonMessageResult = {},
           AddOnRestrictionType = not opts.noRestrictionEnum
             and { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } or nil }
  local active = opts.restrictions or {}
  C_RestrictedActions = not opts.noRestrictionApi and {
    IsAddOnRestrictionActive = function(t)
      if opts.restrictionRaises then error("restricted") end
      return active[t] == true
    end,
  } or nil
  function SendChatMessage(text, chatType)
    sent[#sent + 1] = { text = text, chatType = chatType, hardware = hardware }
    if game == "forever" and not hardware then
      fire("ADDON_ACTION_BLOCKED", "GuildOS", "SendChatMessage")
    else
      local back = opts.echo and opts.echo(text, #sent) or text
      timers[#timers + 1] = { at = clock + 0.1, fn = function() fire("CHAT_MSG_GUILD", back, "Chehul Costa") end }
    end
  end
  function IsInGuild() return true end
  function InCombatLockdown() return false end
  function GetRealmName() return "Realm" end
  GuildOSDB = nil
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Probe.lua")
  return GuildOS.Probe
end

-- Run the timers due by `untilT`, in order, moving the clock with them.
local function advance(untilT)
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > untilT then break end
    table.remove(timers, 1)
    clock = t.at
    t.fn()
  end
  clock = untilT
end
local function said(text)
  for _, line in ipairs(printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end
local function listening(event)
  for _, f in ipairs(frames) do
    if f.events[event] then return true end
  end
  return false
end
local function recorded(text)
  local n = 0
  for _, e in ipairs(GuildOS.State.errors) do
    if e.msg:find(text, 1, true) then n = n + 1 end
  end
  return n
end
local function probeFromCommand(Probe)
  hardware = true                     -- the Enter that sent /guildos probe chat
  local run = Probe:RunChat()
  hardware = false
  return run
end

-- ── 1. Forever: the command's line goes out, the timer's is blocked ─────
local Probe = load("forever", { restrictions = { [5] = true } })
check(not listening("CHAT_MSG_GUILD"), "Forever: nothing listens to guild chat before the probe runs")
local run = probeFromCommand(Probe)
check(run and #sent == 1 and sent[1].chatType == "GUILD" and sent[1].hardware,
  "Forever: the first line goes to guild chat inside the command, with the key press behind it")
check(listening("CHAT_MSG_GUILD"), "Forever: the probe listens for its lines coming back")
advance(clock + 1)
check(#sent == 2 and not sent[2].hardware and sent[2].chatType == "GUILD",
  "Forever: the second line goes to guild chat from a timer a second later")
check(sent[1].text ~= sent[2].text and sent[1].text:find("Guild OS probe", 1, true),
  "Forever: the two lines say what they are and can be told apart")
check(GuildOSDB == nil or GuildOSDB.probeChat == nil, "Forever: nothing is saved before the verdict")
advance(clock + 10)
local r = GuildOSDB and GuildOSDB.probeChat
check(r and r.steps[1].echoed == true and r.steps[2].echoed == false,
  "Forever: the command's line came back and the timer's did not")
check(#r.blocked == 1 and r.blocked[1].addon == "GuildOS" and r.blocked[1].func == "SendChatMessage"
  and r.blocked[1].event == "ADDON_ACTION_BLOCKED" and r.blocked[1].after == 1,
  "Forever: the block is recorded with the addon, the function and when, a second in")
check(r.needsClick == true and r.assumesClick == true, "Forever: measured and assumed agree: chat needs a click")
check(r.build == "1.60.1.70205" and r.lockdown == false, "Forever: the full build and the chat lockdown state are kept")
check(type(r.restrictions) == "table" and #r.restrictions == 1 and r.restrictions[1] == "Chat",
  "Forever: the client's active addon restrictions are kept by name")
check(r.steps[2].restrictions and r.steps[2].restrictions[1] == "Chat",
  "Forever: each line keeps the restrictions active as it went")
check(not listening("CHAT_MSG_GUILD"), "Forever: the probe stops listening to guild chat when it is done")
check(said("GuildOS tried SendChatMessage") and said("Chat needs a click: yes. Guild OS assumes: yes.")
  and said("Addon restrictions: Chat.") and said("1.60.1.70205") and said("GuildOSDB.probeChat"),
  "Forever: the verdict names the block, the restrictions and the build, and says where it was saved")
check(not said("The game reported no blocked action."), "Forever: it does not also say nothing was blocked")
check(recorded("ADDON_ACTION_BLOCKED: GuildOS tried SendChatMessage") == 1,
  "Forever: the block also lands in /guildos errors, with the event")

-- A second run in the same session reads its own lines, not the first run's.
printed = {}
run = probeFromCommand(Probe)
check(run ~= nil, "Forever: once done, the probe can run again")
advance(clock + 10)
r = GuildOSDB.probeChat
check(r == run and r.steps[1].echoed == true and r.steps[2].echoed == false and #r.blocked == 1,
  "Forever: the second run's verdict is its own")
check(recorded("GuildOS tried SendChatMessage") == 1, "the same block is recorded in /guildos errors once a session")

-- ── 2. Anniversary: both lines go out ───────────────────────────────────
Probe = load("anniversary")
Probe:RunChat()
advance(clock + 10)
r = GuildOSDB.probeChat
check(r.steps[1].echoed and r.steps[2].echoed and #r.blocked == 0,
  "Anniversary: both lines come back and nothing is blocked")
check(r.needsClick == false and r.assumesClick == false, "Anniversary: measured and assumed agree: no click needed")
check(said("The game reported no blocked action.") and said("Addon restrictions: none active."),
  "Anniversary: the verdict says nothing was blocked and nothing is restricted")

-- ── 3. Guild chat the client keeps secret ───────────────────────────────
Probe = load("forever", { echo = function() return SECRET end })
probeFromCommand(Probe)
advance(clock + 10)
r = GuildOSDB.probeChat
check(r.unreadable == true and r.needsClick == "unknown" and said("Could not tell: this client keeps guild chat unreadable here."),
  "a secret echo is never read, and the verdict says the chat was unreadable")

-- Lockdown starting between the two lines: the timer's echo is secret, so it cannot be a "yes".
Probe = load("anniversary", { echo = function(text, n) return n == 1 and text or SECRET end })
Probe:RunChat()
advance(clock + 10)
check(GuildOSDB.probeChat.needsClick == "unknown", "a secret echo of the timer's line is not read as a missing one")

-- ── 4. A line from the command that does not come back either ────────────
Probe = load("anniversary", { echo = function() return "something else" end })
Probe:RunChat()
advance(clock + 10)
check(GuildOSDB.probeChat.needsClick == "unknown" and said("Could not tell: not even the line from the command came back."),
  "when even the command's line does not come back, it does not guess, and says why")

-- ── 5. When it refuses, and when the timers run late ─────────────────────
Probe = load("forever")
function IsInGuild() return false end
check(Probe:RunChat() == nil and #sent == 0, "outside a guild it sends nothing")
function IsInGuild() return true end
function InCombatLockdown() return true end
check(Probe:RunChat() == nil and #sent == 0, "in combat it sends nothing")
function InCombatLockdown() return false end
check(probeFromCommand(Probe) ~= nil, "the first run starts")
hardware = true
check(Probe:RunChat() == nil and #sent == 1, "a second run while the first is going sends nothing")
hardware = false
Probe:FinishChat()                    -- the verdict's timer firing before the line's, after a hitch
local ok = pcall(advance, clock + 10)
check(ok and #sent == 1, "the timer's line never goes out after the verdict, and nothing raises")

-- The verdict early on a client where both lines would go: it cannot call that a "yes".
Probe = load("anniversary")
Probe:RunChat()
advance(clock + 0.5)                  -- the command's echo is back, the timer's line not yet sent
Probe:FinishChat()
advance(clock + 10)
check(GuildOSDB.probeChat.needsClick == "unknown" and said("not sent")
  and said("Could not tell: the verdict came before the line from the timer went out."),
  "a timer's line that never went out is \"not sent\", and the verdict does not guess")

Probe = load("forever", { noRestrictionApi = true })
probeFromCommand(Probe)
advance(clock + 10)
check(GuildOSDB.probeChat.restrictions == "missing" and said("Addon restrictions: not on this client."),
  "a client without the restriction API says so")
Probe = load("forever", { noRestrictionEnum = true })
check(pcall(probeFromCommand, Probe), "a client with the API but not its enum does not break the command")
advance(clock + 10)
check(GuildOSDB.probeChat.restrictions == "missing", "and it says the restrictions are missing")
Probe = load("forever", { restrictionRaises = true })
check(pcall(probeFromCommand, Probe), "a restriction API that raises does not break the command")
advance(clock + 10)
check(type(GuildOSDB.probeChat.restrictions) == "table" and #GuildOSDB.probeChat.restrictions == 0,
  "and a restriction it cannot read is not listed")
Probe = load("forever", { restrictions = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true } })
probeFromCommand(Probe)
advance(clock + 10)
check(table.concat(GuildOSDB.probeChat.restrictions, ",") == "ChallengeMode,Chat,Combat,Encounter,Map,PvPMatch"
  and said("Addon restrictions: ChallengeMode, Chat, Combat, Encounter, Map, PvPMatch."),
  "several active restrictions are listed by name, sorted")

-- A restriction that starts between the two lines is kept with the line it applied to.
local live = {}
Probe = load("forever", { restrictions = live })
probeFromCommand(Probe)
live[5] = true
advance(clock + 10)
r = GuildOSDB.probeChat
check(#r.restrictions == 0 and #r.steps[1].restrictions == 0 and r.steps[2].restrictions[1] == "Chat"
  and said("Addon restrictions: none active."),
  "each line keeps the restrictions of its own moment; the printed list is the start's")

-- ── 6. Any block, any addon, any time ───────────────────────────────────
Probe = load("forever")
fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName")
check(recorded("ADDON_ACTION_FORBIDDEN: SomeOtherAddon tried CastSpellByName") == 1,
  "a block outside the probe, by another addon, is recorded too")
fire("MACRO_ACTION_BLOCKED", "SendChatMessage")
check(recorded("MACRO_ACTION_BLOCKED: macro tried SendChatMessage") == 1, "a macro's block is recorded as the macro's")
fire("ADDON_ACTION_BLOCKED", SECRET, SECRET)
check(recorded("ADDON_ACTION_BLOCKED: ? tried ?") == 1, "a block whose names are secret is recorded without reading them")
GuildOS:RecordError("a real GuildOS error")
for _ = 1, 80 do fire("ADDON_ACTION_BLOCKED", "NoisyAddon", "TargetUnit") end
check(recorded("a real GuildOS error") == 1 and recorded("NoisyAddon") == 1,
  "a noisy addon blocked eighty times takes one line and pushes no real error out")
fire("ADDON_ACTION_BLOCKED", "NoisyAddon", "FocusUnit")
fire("ADDON_ACTION_FORBIDDEN", "NoisyAddon", "TargetUnit")
check(recorded("NoisyAddon") == 3, "another function or another event from the same addon is a new line")

-- A probe running through a flood prints a few blocks and keeps them all.
printed = {}
probeFromCommand(Probe)
for _ = 1, 30 do fire("ADDON_ACTION_BLOCKED", "NoisyAddon", "TargetUnit") end
advance(clock + 10)
local blockLines = 0
for _, line in ipairs(printed) do
  if line:find("Blocked by the game", 1, true) then blockLines = blockLines + 1 end
end
check(#GuildOSDB.probeChat.blocked == 31 and blockLines == 5 and said("... and 26 more."),
  "the verdict prints five blocks and the count of the rest; the saved result keeps all of them")

-- ── 7. The command reaches it ───────────────────────────────────────────
local f = assert(io.open(ADDON .. "/Core/Commands.lua", "rb"))
local src = f:read("*a")
f:close()
check(src:find('msg == "probe chat"', 1, true) and src:find("Probe:RunChat()", 1, true),
  "/guildos probe chat runs it")

print(("chat-probe: %d checks passed"):format(checks))
