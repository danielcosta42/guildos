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
--   * the consent popup's button says "Post (1 of 3)" where a click carries one channel.
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

print(("recruit-post-round: %d checks passed"):format(checks))
