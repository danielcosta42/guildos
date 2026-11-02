-- /gos probe channel (specs/071-o-recrutamento in guildos-web, Task B6), run against the real
-- Core/Core.lua, Core/Compat.lua and Core/Probe.lua.
--
-- Whether an addon message may go through a created channel, measured: the probe joins a temporary
-- channel, sends from the command (a key press) and from a timer, listens for its own echo, leaves, and
-- keeps { timer, click, heard, at } in GuildOSDB.probeChannel. The channel always ends: after a verdict,
-- after an error, after a join that never came. Nothing is ever said in a chat anybody else reads.
--
--   luajit -e 'ADDON="."' tools/probe-channel.lua
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

local frames, timers, printed, sent, clock, hardware, joined, left, filters

local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.fn then f.fn(f, event, ...) end
  end
end

-- The client. `o.slowJoin`: the channel has a number only a second after the join (the game answers
-- asynchronously). `o.blockTimer`: Forever drops what a timer sends, with a result and no echo.
-- `o.joinRaises`, `o.sendRaises`: the calls themselves fail.
local function load(o)
  o = o or {}
  frames, timers, printed, sent, clock, hardware, joined, left, filters = {}, {}, {}, {}, 100, false, {}, {}, {}
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
  function GetServerTime() return 1759500000 + math.floor(clock) end
  C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
  function issecretvalue() return false end
  function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  function SendChatMessage() error("nothing here may reach a public channel") end
  function InCombatLockdown() return o.combat or false end
  function IsInGuild() return true end
  function GetRealmName() return "Realm" end
  function ChatFrame_AddMessageEventFilter(event, fn) filters[#filters + 1] = { event = event, fn = fn } end
  Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
  local number = 0
  function JoinChannelByName(name)
    if o.joinRaises then error("join refused") end
    number = number + 1
    joined[name] = { id = number + 4, at = clock }
  end
  function GetChannelName(name)
    local c = joined[name]
    if not c or (o.slowJoin and clock - c.at < 1) then return 0, "" end
    return c.id, name
  end
  function LeaveChannelByName(name) left[#left + 1] = name; joined[name] = nil end
  C_ChatInfo = {
    InChatMessagingLockdown = function() return false end,
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target)
      if o.sendRaises then error("send failed") end
      sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target, hardware = hardware }
      if channel ~= "CHANNEL" then return 0 end
      if not hardware and o.blockTimer then return 11 end   -- blocked, and nothing comes back
      timers[#timers + 1] = { at = clock + 0.1, fn = function()
        for _, c in pairs(joined) do
          if c.id == target then fire("CHAT_MSG_ADDON", prefix, o.echo and o.echo(text) or text, "CHANNEL", "Chehul-Costa") end
        end
      end }
      return 0
    end,
  }
  GuildOSDB = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Probe.lua")
  return GuildOS.Probe
end

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
local function fromCommand(Probe)
  hardware = true   -- the Enter that sent /gos probe channel
  local ok, run = pcall(Probe.RunChannel, Probe)
  hardware = false
  assert(ok, run)
  return run
end
local function stillJoined() return next(joined) ~= nil end

-- ── 1. Both attempts get through ────────────────────────────────────────
local Probe = load()
check(Probe.RunChannel, "the probe has RunChannel")
local run = fromCommand(Probe)
check(run and #sent == 1 and sent[1].channel == "CHANNEL" and sent[1].hardware and type(sent[1].target) == "number",
  "the first message goes through the channel inside the command, with the key press behind it")
check(stillJoined() and listening("CHAT_MSG_ADDON"), "the probe is in the channel and listens for its echo")
advance(clock + 3)
check(#sent == 2 and not sent[2].hardware and sent[2].channel == "CHANNEL" and sent[1].text ~= sent[2].text,
  "the second goes from a timer, and tells which is which")
check(GuildOSDB == nil or GuildOSDB.probeChannel == nil, "nothing is saved before the verdict")
advance(clock + 20)
local r = GuildOSDB.probeChannel
check(r and r.timer == true and r.click == true and r.heard.timer == true and r.heard.click == true and type(r.at) == "number",
  "timer, click, heard and when are kept in GuildOSDB.probeChannel")
check(not stillJoined() and #left == 1 and left[1] == run.name, "the channel is left, and it is the one that was joined")
check(not listening("CHAT_MSG_ADDON"), "and the probe stops listening")
check(said("GuildOSDB.probeChannel"), "the verdict says where it was saved")
check(sent[1].prefix == "GuildOSProbe" and run.name:find("^GOSProbe"), "on the probe's own prefix and a channel of its own")
local hide = filters[1] and filters[1].fn
check(#filters >= 1 and filters[1].event == "CHAT_MSG_CHANNEL_NOTICE", "a filter is on the channel notices")
-- The client hands arg 4 as "5. Name" and arg 9 as the base name.
check(hide(nil, nil, "x", "y", "z", "5. " .. run.name, "", 0, 0, 5, run.name) == true, "the notice of the probe's channel, as the client numbers it, is hidden")
check(hide(nil, nil, "x", "y", "z", "5. " .. run.name) == true, "and by the numbered form alone")
check(hide(nil, nil, "x", "y", "z", run.name, "", 0, 0, 5, run.name) == true, "and by the bare name")
check(not hide(nil, nil, "x", "y", "z", "1. General", "", 0, 0, 1, "General") and not hide(nil, nil, "x", "y", "z", "6. GOSProbe0001"),
  "no other channel's notice is")
check(not hide(nil, nil, "x", "y", "z", nil), "an absent channel is nobody's")
check(GuildOSDB.probeChannelOpen == nil, "nothing is kept as running after the verdict")

-- ── 2. Forever drops what a timer sends ─────────────────────────────────
Probe = load({ blockTimer = true })
run = fromCommand(Probe)
advance(clock + 20)
r = GuildOSDB.probeChannel
check(r.click == true and r.timer == false and r.heard.click == true and r.heard.timer == false,
  "a timer's message that the game drops is recorded as not sent and not heard")
check(not stillJoined(), "and the channel is left all the same")

-- ── 3. A channel with a number only a moment late ──────────────────────
Probe = load({ slowJoin = true })
run = fromCommand(Probe)
check(#sent == 0 and run.clickSkipped == "no channel number" and run.click == nil, "the command's message cannot go before the channel has a number: skipped, not refused")
check(said("press the command or the button again"), "and the player is told plainly that a second press is needed")
check(GuildOSDB.probeChannelOpen == run.name, "the open channel is kept in GuildOSDB while the probe runs")
advance(clock + 3)
check(#sent == 1 and not sent[1].hardware, "the timer's message goes once the channel has a number")
hardware = true
check(Probe:RunChannel() == run, "a second press while it runs retries the click")
hardware = false
check(#sent == 2 and sent[2].hardware and sent[2].channel == "CHANNEL", "from the new key press, which is the attempt that counts")
check(Probe:RunChannel() == nil and said("already running"), "a third has nothing to retry")
advance(clock + 20)
r = GuildOSDB.probeChannel
check(r.click == true and r.clickSkipped == nil and r.timer == true and r.heard.click == true and r.heard.timer == true,
  "the retried click is the result, and nothing is left saying it was skipped")
check(not stillJoined() and GuildOSDB.probeChannelOpen == nil, "the channel is left")

Probe = load({ slowJoin = true })
run = fromCommand(Probe)
advance(clock + 20)
r = GuildOSDB.probeChannel
check(r.click == nil and r.clickSkipped == "no channel number" and r.timer == true, "with no second press the click stays unknown, and says why")
check(said("not tried"), "and the printed line says it was not tried, not that it failed")
check(not stillJoined(), "and the channel is left")

-- A /reload inside the window loses the leave timer: the next load leaves the channel.
Probe = load()
GuildOSDB = { probeChannelOpen = "GOSProbe5555" }
joined["GOSProbe5555"] = { id = 9, at = 0 }
Probe:LeaveStaleChannel()
check(not joined["GOSProbe5555"] and GuildOSDB.probeChannelOpen == nil, "a channel left open by a /reload is left on the next load")
check(pcall(Probe.LeaveStaleChannel, Probe), "and with none open it is nothing")

-- ── 4. Hearing is not believing ─────────────────────────────────────────
Probe = load({ echo = function() return "somebody else's text" end })
run = fromCommand(Probe)
advance(clock + 20)
r = GuildOSDB.probeChannel
check(r.timer == true and r.click == true and r.heard.timer == false and r.heard.click == false,
  "only the probe's own text counts as an echo")

-- ── 5. Errors never keep the channel ────────────────────────────────────
Probe = load({ joinRaises = true })
check(pcall(Probe.RunChannel, Probe), "a join that raises does not raise out of the command")
advance(clock + 20)
r = GuildOSDB.probeChannel
check(r and r.timer == nil and r.click == nil and r.joined == false, "and the verdict says nothing was tried")
check(#left == 1 and not stillJoined(), "the channel is left even so")

Probe = load({ sendRaises = true })
check(pcall(Probe.RunChannel, Probe), "a send that raises does not raise out of the command")
advance(clock + 20)
r = GuildOSDB.probeChannel
check(r and r.timer == false and r.click == false and not stillJoined(), "the channel is left after a send that failed")

-- ── 6. Refusals, and a second run ───────────────────────────────────────
Probe = load({ combat = true })
check(Probe:RunChannel() == nil and not stillJoined() and said("combat"), "it does not run in combat")
Probe = load()
run = fromCommand(Probe)
check(Probe:RunChannel() == nil and said("already running"), "it does not run twice at once")
advance(clock + 20)
check(not stillJoined(), "the first still ends")
local again = fromCommand(Probe)
check(again and again ~= run, "and it can run again after the verdict")
advance(clock + 20)
check(not stillJoined(), "and ends again")

-- ── 7. The command ──────────────────────────────────────────────────────
local f = io.open(ADDON .. "/Core/Commands.lua", "rb")
local src = f:read("*a")
f:close()
check(src:find('msg == "probe channel"', 1, true) and src:find("Probe:RunChannel()", 1, true), "/gos probe channel runs it")

print(("probe-channel: %d checks passed"):format(checks))
