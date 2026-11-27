-- The recruitment ad's post round (#449), run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/RecruitEngagement.lua, Modules/RecruitmentSystem.lua and Modules/ActionQueue.lua, as each game.
--
-- On WoW: Forever the ad went to [3] and [4] and not to the channel the maintainer had added by hand,
-- "LookingforGuild" (their LookingForGuild, /5): one click posted to every channel in a loop, and a channel line
-- there wants a key press. Now:
--   * Anniversary posts to every channel on the click, as before;
--   * Forever and retail (Compat.NeedsHardware("channel")) post the first channel on the click and queue each of
--     the rest in the officer action queue, one per key press; unless the probe heard a second channel line from
--     one key press come back, then all at once;
--   * a saved name finds the joined channel in any case, and AddChannel saves the game's spelling;
--   * the same channel saved twice is posted to once;
--   * every round ends with one line: "Sent to: [3] ... · Not joined: ... · Waiting for a key press: ...";
--   * the consent popup's button says "Post (1 of 3)" where a click carries one channel;
--   * a channel whose echo never came back (the server's flood limit) goes back for the next click of Post, alone and
--     inside the same round (no new cooldown, no post counted), and where a channel line wants a key press it waits in
--     the action queue too; the server's "throttled" during a round holds the rest of it for the next click.
--
--   luajit -e 'ADDON="."' tools/recruit-post-round.lua
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
-- `joined`: { { num, name } ... } the channels the player is in. `list`: whether the client answers GetChannelList
-- (else only GetChannelName by number).
local function load(game, joined, channels, list)
  env = { sent = {}, printed = {}, joined = joined, clock = 1000 }
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) env.printed[#env.printed + 1] = tostring(m) end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  WOW_PROJECT_MAINLINE = nil
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "71139", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  elseif game == "retail" then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 5, 1, 1
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  function GetLocale() return "enUS" end
  function GetRealmName() return "Realm" end
  function UnitName() return "Chehul" end
  function GetServerTime() return 1790000000 end
  function GetTime() return env.clock end
  time = function() return 1790000000 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  function InCombatLockdown() return false end
  function GetGuildInfo() return "Guild", "Officer", 1 end
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  GuildOSDB = {}
  C_Timer = { After = function() end, NewTicker = function() end }
  C_ChatInfo = { GetChannelInfoFromIdentifier = function() return nil end }
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
  dofile(ADDON .. "/Modules/ActionQueue.lua")
  function SendChatMessage(msg, chan, _, num) env.sent[#env.sent + 1] = { msg = msg, chan = chan, num = num } end
  -- The game answers a name exactly as the channel is named (the case-insensitive match is the addon's), and a
  -- number with that channel's number and name.
  function GetChannelName(id)
    for _, ch in ipairs(env.joined) do
      if (type(id) == "number" and ch[1] == id) or ch[2] == id then return ch[1], ch[2] end
    end
    return 0
  end
  if list ~= false then
    function GetChannelList()
      local out = {}
      for _, ch in ipairs(env.joined) do out[#out + 1] = ch[1]; out[#out + 1] = ch[2]; out[#out + 1] = false end
      return unpack(out)
    end
  else
    GetChannelList = nil
  end
  GuildOS.db = { recruitment = { enabled = true, message = "Filhos da Horda recruta", channels = channels } }
  function GuildOS:IsOfficer() return true end
  return GuildOS.Recruitment, GuildOS.ActionQueue
end

local function nums()
  local out = {}
  for i, s in ipairs(env.sent) do out[i] = tostring(s.num) end
  return table.concat(out, ",")
end
local function last() return ((env.printed[#env.printed] or ""):gsub("^|cff%x+%[Guild OS%]|r ", "")) end
local function has(s, part) return s:find(part, 1, true) ~= nil end

local MAINTAINER = { { 3, "LookingForGroup" }, { 4, "Trade" }, { 5, "LookingForGuild" } }
local SAVED = { "LookingForGroup", "Trade", "LookingforGuild" }

-- ── Anniversary: every channel on the click ────────────────────────────
local R, AQ = load("anniversary", MAINTAINER, SAVED)
check(R:PostsPerClick() == math.huge, "Anniversary: one click carries every channel")
R:DoSendRecruitmentMessage()
check(nums() == "3,4,5" and AQ:Pending() == 0, "Anniversary posts to all three at once, LookingforGuild included")
check(has(last(), "Sent to: [3] LookingForGroup, [4] Trade, [5] LookingForGuild") and not has(last(), "Waiting"),
  "and says where: " .. last())
check(R:PostButtonText(3) == "Post", "the popup's button is plain Post")

-- ── Forever and retail: one click posts everywhere too (the maintainer, #449) ──
for _, game in ipairs({ "forever", "retail" }) do
  R, AQ = load(game, MAINTAINER, SAVED)
  check(R:PostsPerClick() == math.huge and R:PostButtonText(3) == "Post", game .. ": one click carries every channel")
  R:DoSendRecruitmentMessage()
  check(nums() == "3,4,5" and AQ:Pending() == 0, game .. ": all three at once, nothing queued")
end

-- ── Not joined, and only the parts that apply ──────────────────────────
R, AQ = load("forever", { { 3, "LookingForGroup" } }, { "LookingForGroup", "General" })
R:DoSendRecruitmentMessage()
check(nums() == "3" and AQ:Pending() == 0, "a channel the player is not in is neither posted nor queued")
check(last() == "Sent to: [3] LookingForGroup \194\183 Not joined: General", "the line: " .. last())
R, AQ = load("anniversary", {}, { "General" })
R:DoSendRecruitmentMessage()
check(nums() == "" and has(env.printed[#env.printed - 1] or "", "Not joined: General")
  and has(last(), "No valid channels found"), "nothing joined: it says which and why")
check(R:RoundSummary({}) == nil, "a round with nothing to say prints no line")

-- ── Case-insensitive resolution ────────────────────────────────────────
R = load("forever", MAINTAINER, {})
local name, num = R:ResolveChannel("LookingforGuild")
check(name == "LookingForGuild" and num == 5, "LookingforGuild finds the joined LookingForGuild")
name, num = R:ResolveChannel("  lookingforgroup ")
check(name == "LookingForGroup" and num == 3, "any case, any spaces around")
name, num = R:ResolveChannel("Gildenrekrutierung")
check(num == 0, "a channel the player is not in has no number")
R = load("forever", MAINTAINER, {}, false)
name, num = R:ResolveChannel("LOOKINGFORGUILD")
check(name == "LookingForGuild" and num == 5, "without GetChannelList, the channels are read by number")
R = load("anniversary", { { 2, "Trade - City" } }, {})
name, num = R:ResolveChannel("trade")
check(num == 2, "a zone channel's full name answers to its shortcut in any case")
local joinedList = GuildOS.Compat.JoinedChannels()
check(#joinedList == 1 and joinedList[1].num == 2 and joinedList[1].name == "Trade - City", "Compat.JoinedChannels")

-- AddChannel saves the game's spelling of a joined channel, and a channel not joined as typed.
R = load("forever", MAINTAINER, {})
local list = {}
check(R:AddChannel(list, "lookingforguild") and list[1] == "LookingForGuild", "added as the game names it")
check(not R:AddChannel(list, "LOOKINGFORGUILD") and #list == 1, "and not twice in another case")
check(R:AddChannel(list, "myChannel") and list[2] == "myChannel", "a channel not joined is kept as typed")

-- ── The same channel saved twice ───────────────────────────────────────
R, AQ = load("forever", MAINTAINER, { "LookingforGuild", "LookingForGuild", "lookingforguild", "Trade" })
local names, joinedN = R:_ResolveChannels(GuildOS.db.recruitment)
check(#names == 2 and joinedN == 2 and names[1] == "LookingForGuild", "listed once in the popup")
check(R:PostButtonText(joinedN) == "Post", "and the button is plain Post")
R:DoSendRecruitmentMessage()
AQ:Next(true)
check(nums() == "5,4" and AQ:Pending() == 0, "posted to once: LookingForGuild, then Trade")
R, AQ = load("anniversary", MAINTAINER, { "LookingForGroup", "lookingForGroup", "Trade" })
R:DoSendRecruitmentMessage()
check(nums() == "3,4", "Anniversary too")

-- ── The consent popup asks the module for its button ───────────────────
local f = assert(io.open(ADDON .. "/Modules/RecruitmentSystem.lua", "rb"))
local src = f:read("*a")
f:close()
check(src:find("f.postBtn.label:SetText(self:PostButtonText(joined))", 1, true), "ShowSendPopup sets the button's count")

-- The game takes a line and the channel may still not show it (#449): each post waits for its own echo.
do
  load("forever", { { 3, "LookingForGroup" }, { 5, "LookingForGuild" } }, { "LookingForGroup", "LookingForGuild" }, true)
  local R = GuildOS.Recruitment
  local script, afters = nil, {}
  CreateFrame = function()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript(_, fn) script = fn end
    return f
  end
  R._echoFrame, R._echo = nil, nil
  local realAfter = GuildOS.Compat.After
  GuildOS.Compat.After = function(_, fn) afters[#afters + 1] = fn end
  local me = GuildOS.Compat.PlayerName()
  R:_WatchEcho({ { num = 3, name = "LookingForGroup" }, { num = 5, name = "LookingForGuild" } })
  script(nil, "CHAT_MSG_CHANNEL", "the ad", me, "", "3. LookingForGroup", "", "", 0, 3)
  script(nil, "CHAT_MSG_CHANNEL", "spam", "Someone", "", "5. LookingForGuild", "", "", 0, 5)
  for _, fn in ipairs(afters) do fn() end
  check(has(last(), "Not shown in: [5] LookingForGuild") and not has(last(), "[3]"),
    "a post whose line never came back is said to have been dropped; one that did is not: " .. last())
  GuildOS.Compat.After = realAfter
end

-- ── A channel that did not show the line goes back for the next click (the server's flood limit) ──
-- One click still posts everywhere. The channels whose echo never came back are the next click's, alone, as part
-- of the same round: no new cooldown, no new post counted. Where a channel line wants a key press they also wait in
-- the action queue. A "throttled" answer during a round holds the rest of it for the next click.
local function rig(game)
  local R2, AQ2 = load(game, MAINTAINER, SAVED)
  local scripts, afters = {}, {}
  CreateFrame = function()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(_, fn) self.fn = fn end
    scripts[#scripts + 1] = f
    return f
  end
  GuildOS.Compat.After = function(_, fn) afters[#afters + 1] = fn end
  local posts = 0
  GuildOS.RecruitEngagement.RecordPost = function() posts = posts + 1 end
  local function fire(event, ...)
    for _, f in ipairs(scripts) do if f.events[event] and f.fn then f.fn(f, event, ...) end end
  end
  local function echo(num)
    fire("CHAT_MSG_CHANNEL", "the ad", GuildOS.Compat.PlayerName(), "", num .. ". x", "", "", 0, num)
  end
  local function timeout()
    local due = afters
    afters = {}
    for _, fn in ipairs(due) do fn() end
  end
  return R2, AQ2, fire, echo, timeout, function() return posts end
end

do
  local R2, AQ2, _, echo, timeout, posts = rig("anniversary")
  R2:DoSendRecruitmentMessage()
  check(nums() == "3,4,5" and posts() == 1, "Anniversary: one click, every channel, one post counted")
  local roundAt = R2._lastSendAt
  echo(3)
  timeout()
  check(has(last(), "Not shown in: [4] Trade, [5] LookingForGuild \226\128\148 click Post again to send there"),
    "the line says which channels did not show it and that the next click sends there: " .. last())
  local retry = R2:RetryChannels()
  check(retry and #retry == 2 and retry[1] == "Trade" and retry[2] == "LookingForGuild", "those two wait for the next click")
  check(AQ2:Pending() == 0, "where a click carries every channel nothing waits in the queue")
  env.sent = {}
  env.clock = env.clock + 6   -- well inside SEND_MIN_GAP
  R2:DoSendRecruitmentMessage()
  check(nums() == "4,5", "the next click posts only to them, inside the round's gap: " .. nums())
  check(R2._lastSendAt == roundAt and posts() == 1, "and is the same round: no new cooldown, no new post counted")
  check(R2:RetryChannels() == nil, "nothing waits any more")
  check(has(last(), "Sent to: [4] Trade, [5] LookingForGuild"), "its line: " .. last())
  echo(4); echo(5)
  timeout()
  check(R2:RetryChannels() == nil, "both showed it this time")
  env.sent = {}
  R2:DoSendRecruitmentMessage()
  check(nums() == "", "a further click inside the gap is still refused")
  env.clock = env.clock + R2.SEND_MIN_GAP
  R2:DoSendRecruitmentMessage()
  check(nums() == "3,4,5" and posts() == 2, "past it, a new round to every channel")
  -- A retry not taken goes stale: then the next click is a new round again.
  timeout()
  check(R2:RetryChannels() and #R2:RetryChannels() == 3, "none showed it")
  env.clock = env.clock + R2.RETRY_KEEP + R2.SEND_MIN_GAP
  env.sent = {}
  check(R2:RetryChannels() == nil, "after RETRY_KEEP it is forgotten")
  R2:DoSendRecruitmentMessage()
  check(nums() == "3,4,5" and posts() == 3, "and the next click is a whole round")
end

for _, game in ipairs({ "forever", "retail" }) do
  local R2, AQ2, _, echo, timeout, posts = rig(game)
  check(GuildOS.Compat.NeedsHardware("channel"), game .. ": a channel line wants a key press")
  R2:DoSendRecruitmentMessage()
  check(nums() == "3,4,5" and AQ2:Pending() == 0, game .. ": one click, every channel")
  echo(3); echo(5)
  timeout()
  check(has(last(), "Not shown in: [4] Trade"), game .. ": " .. last())
  check(AQ2:Pending() == 1 and AQ2:Peek().name == "Trade", game .. ": Trade waits in the action queue for a key press")
  env.sent = {}
  AQ2:Next(true)
  check(nums() == "4" and posts() == 1 and R2:RetryChannels() == nil, game .. ": the key press posts there, same round, nothing left")
  -- Or the click of Post takes it, and the queue's copy goes with it.
  timeout()
  check(AQ2:Pending() == 1 and R2:RetryChannels(), game .. ": dropped again, waiting again")
  env.sent = {}
  env.clock = env.clock + 6
  R2:DoSendRecruitmentMessage()
  check(nums() == "4" and AQ2:Pending() == 0 and posts() == 1, game .. ": a click of Post sends it once, the queue's copy is gone")
end

-- The server's "throttled" during a round: the rest of the round waits for the next click.
do
  local R2, AQ2, fire, echo, timeout, posts = rig("anniversary")
  local realSend = SendChatMessage
  local once = true
  SendChatMessage = function(...)
    realSend(...)
    if once then once = false; fire("CHAT_MSG_CHANNEL_NOTICE", "THROTTLED", "", "", "3. LookingForGroup") end
  end
  R2:DoSendRecruitmentMessage()
  check(nums() == "3", "after the throttled notice nothing more goes in that round: " .. nums())
  check(has(last(), "Held, the server is limiting chat: Trade, LookingForGuild"), "the line says which wait: " .. last())
  check(posts() == 1 and AQ2:Pending() == 0, "the round counted once")
  env.sent = {}
  env.clock = env.clock + 1
  R2:DoSendRecruitmentMessage()
  check(nums() == "" and has(last(), "limiting your chat"), "a click during the hold sends nothing and says why")
  env.clock = env.clock + R2.THROTTLE_HOLD
  echo(3)
  timeout()
  R2:DoSendRecruitmentMessage()
  check(nums() == "4,5" and posts() == 1, "after the hold the next click sends the held channels alone, same round: " .. nums())
  SendChatMessage = realSend
  -- The chat's own throttle error holds too.
  ERR_CHAT_THROTTLED = "The number of messages that can be sent to this channel is limited."
  fire("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
  check(R2:_Throttled(), "ERR_CHAT_THROTTLED holds the channel lines too")
  ERR_CHAT_THROTTLED = nil
end

-- Forever: a queued channel's key press during the hold keeps it for later instead of sending.
do
  local R2, AQ2, fire, echo, timeout = rig("forever")
  R2:DoSendRecruitmentMessage()
  echo(3); echo(4)
  timeout()
  check(AQ2:Pending() == 1, "LookingForGuild waits for a key press")
  fire("CHAT_MSG_CHANNEL_NOTICE", "THROTTLED", "", "", "3. LookingForGroup")
  env.sent = {}
  AQ2:Next(true)
  check(nums() == "" and AQ2:Pending() == 1 and R2:RetryChannels()[1] == "LookingForGuild",
    "the key press in the hold sends nothing; the channel waits for the next one")
  env.clock = env.clock + R2.THROTTLE_HOLD
  AQ2:Next(true)
  check(nums() == "5" and AQ2:Pending() == 0 and R2:RetryChannels() == nil, "after it, the key press posts it")
end

print(("recruit-post-round: %d checks passed"):format(checks))
