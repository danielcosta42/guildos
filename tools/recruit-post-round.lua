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
--   * every round ends with one line: "Posted in: [3] ... · Not joined: ... · Waiting for a key press: ...";
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
check(has(last(), "Posted in: [3] LookingForGroup, [4] Trade, [5] LookingForGuild") and not has(last(), "Waiting"),
  "and says where: " .. last())
check(R:PostButtonText(3) == "Post", "the popup's button is plain Post")

-- ── Forever: the first now, the rest one per key press ─────────────────
R, AQ = load("forever", MAINTAINER, SAVED)
check(R:PostsPerClick() == 1, "Forever: one channel line per key press")
check(R:PostButtonText(3) == "Post (1 of 3)" and R:PostButtonText(1) == "Post", "the popup's button: Post (1 of 3)")
R:DoSendRecruitmentMessage()
check(nums() == "3" and AQ:Pending() == 2, "the click posts to the first channel, the other two wait")
check(last() == "Posted in: [3] LookingForGroup \194\183 Waiting for a key press: Trade, LookingForGuild",
  "the round's line: " .. last())
local item = AQ:Peek(true)
check(item and item.kind == "channel" and item.name == "Trade", "the next one is Trade, a channel action")
local prompt = AQ:PromptText()
check(has(prompt, "post the ad in Trade") and has(prompt, "1 more"), "the toast: " .. prompt)
AQ:Next(true)
check(nums() == "3,4" and AQ:Pending() == 1, "one key press posts to Trade, and only to Trade")
check(last() == "Posted in: [4] Trade \194\183 Waiting for a key press: LookingForGuild", "and says what is left: " .. last())
check(has(AQ:PromptText(), "post the ad in LookingForGuild") and not has(AQ:PromptText(), "more"),
  "the toast now names LookingForGuild alone")
AQ:Next(true)
check(nums() == "3,4,5" and AQ:Pending() == 0, "the next key press posts to LookingForGuild, the one that was missed")
check(last() == "Posted in: [5] LookingForGuild", "and the line ends the round: " .. last())
check(env.sent[3].msg == "Filhos da Horda recruta" and env.sent[3].chan == "CHANNEL", "the same ad, to the channel")

-- A new round replaces what the last one left waiting.
R, AQ = load("forever", MAINTAINER, SAVED)
R:DoSendRecruitmentMessage()
R._lastSendAt = nil
env.clock = env.clock + 600
R:DoSendRecruitmentMessage()
check(nums() == "3,3" and AQ:Pending() == 2, "a second round queues its channels once, not twice")

-- The player left a queued channel before its key press.
R, AQ = load("forever", MAINTAINER, SAVED)
R:DoSendRecruitmentMessage()
env.joined = { { 3, "LookingForGroup" }, { 5, "LookingForGuild" } }
AQ:Next(true)
check(nums() == "3" and last() == "Not joined: Trade \194\183 Waiting for a key press: LookingForGuild",
  "a channel left meanwhile is named as not joined: " .. last())

-- The probe heard a second channel line from one key press: then all at once.
R, AQ = load("forever", MAINTAINER, SAVED)
GuildOSDB.probeInvite = { build = GuildOS.Client.build, results = { channelTwice = { click = true } } }
check(R:PostsPerClick() == math.huge and R:PostButtonText(3) == "Post", "a measured second line lifts the limit")
R:DoSendRecruitmentMessage()
check(nums() == "3,4,5" and AQ:Pending() == 0, "and the round posts everywhere on the click")
GuildOSDB.probeInvite = { build = "1", results = { channelTwice = { click = true } } }
check(R:PostsPerClick() == 1, "a measurement from another build does not count")

-- Retail also wants a key press per channel line.
R, AQ = load("retail", MAINTAINER, SAVED)
R:DoSendRecruitmentMessage()
check(nums() == "3" and AQ:Pending() == 2, "retail: the first now, the rest queued")

-- ── Not joined, and only the parts that apply ──────────────────────────
R, AQ = load("forever", { { 3, "LookingForGroup" } }, { "LookingForGroup", "General" })
R:DoSendRecruitmentMessage()
check(nums() == "3" and AQ:Pending() == 0, "a channel the player is not in is neither posted nor queued")
check(last() == "Posted in: [3] LookingForGroup \194\183 Not joined: General", "the line: " .. last())
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
check(R:PostButtonText(joinedN) == "Post (1 of 2)", "and counted once on its button")
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

print(("recruit-post-round: %d checks passed"):format(checks))
