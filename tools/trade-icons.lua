-- Raid icons where the server hides them (issue #64), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/RecruitEngagement.lua and Modules/RecruitmentSystem.lua,
-- once as each game.
--
-- On WoW: Forever the ChatChannels table flags General, Trade, LocalDefense, Services and
-- TradeLocal with DisableRaidIcons, so the same recruitment message showed a skull in
-- LookingForGroup and "{rt8}" as text in Trade. The copy for those channels leaves the codes
-- out. Anniversary flags no channel, and keeps every icon.
--
--   luajit -e 'ADDON="."' tools/trade-icons.lua
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

-- Channel numbers and zone channel ids as a client in a city has them (LookingForGroup is 26).
local CHANNELS = { General = { 1, 1 }, Trade = { 2, 2 }, LookingForGroup = { 4, 26 }, MyChannel = { 5, 0 } }

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70170", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  function GetRealmName() return "Realm" end
  function UnitName() return "Chehul" end
  function GetServerTime() return 1790000000 end
  function GetTime() return 1000 end
  time = function() return 1790000000 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  C_Timer = { After = function() end, NewTicker = function() end }
  C_ChatInfo = { GetChannelInfoFromIdentifier = function(id)
    local c = CHANNELS[id]
    if not c then
      for _, v in pairs(CHANNELS) do if tostring(v[1]) == id then c = v end end
    end
    return c and { localID = c[1], zoneChannelID = c[2] } or nil
  end }
  local registry = {}
  LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
    GetLibrary = function(_, n) return registry[n] end },
    { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  -- The game's own table of icon words, as the client has it.
  ICON_TAG_LIST = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, x = 7, skull = 8,
                    caveira = 8 }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/RecruitEngagement.lua")
  dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
  local sent = {}
  function SendChatMessage(msg, chan, _, num) sent[#sent + 1] = { msg = msg, chan = chan, num = num } end
  function GetChannelName(name) return CHANNELS[name] and CHANNELS[name][1] or 0 end
  BRutus.db = { recruitment = { message = "{rt8} FILHOS DA HORDA {rt8} Guilda BR", channels = { "LookingForGroup", "Trade" } } }
  function BRutus:IsOfficer() return true end
  return BRutus, sent
end

-- ── Forever ─────────────────────────────────────────────────────────────
local B, sent = load("forever")
local R = B.Recruitment
check(R:_StripRaidIcons("{rt8} FILHOS DA HORDA {rt8} Guilda BR") == "FILHOS DA HORDA Guilda BR",
      "the {rtN} codes come out, with the space they leave")
check(R:_StripRaidIcons("{Skull} raid {caveira} hoje {star}") == "raid hoje", "and the icon words the game knows, any case")
check(R:_StripRaidIcons("LFM{rt8}Heroic") == "LFM Heroic", "a code between two words leaves them apart")
check(R:_StripRaidIcons("vagas {healer} e {rt9}") == "vagas {healer} e {rt9}", "braces that are no icon stay")
check(R:_StripRaidIcons("{rt1}{rt2}") == "", "a line of icons only is empty")

local C = B.Compat
check(C.ChannelHidesRaidIcons("Trade") and C.ChannelHidesRaidIcons("General"), "Forever: Trade and General hide raid icons")
check(not C.ChannelHidesRaidIcons("LookingForGroup") and not C.ChannelHidesRaidIcons("MyChannel"),
      "LookingForGroup and a custom channel show them")
check(C.ChannelHidesRaidIcons("Comércio", 2), "by zone channel id, so a channel named in another language is found by its number")

R:DoSendRecruitmentMessage()
check(#sent == 2, "both channels get the post")
check(sent[1].num == 4 and sent[1].msg == "{rt8} FILHOS DA HORDA {rt8} Guilda BR", "LookingForGroup keeps the skulls")
check(sent[2].num == 2 and sent[2].msg == "FILHOS DA HORDA Guilda BR", "Trade gets the text without {rt8}")

for k in pairs(sent) do sent[k] = nil end
R._lastSendAt = nil
B.db.recruitment.message = "{rt8}{rt8}"
R:DoSendRecruitmentMessage()
check(#sent == 1 and sent[1].num == 4, "a message of icons only is not posted empty to Trade")
for k in pairs(sent) do sent[k] = nil end
R._lastSendAt = nil
B.db.recruitment.channels = { "Trade" }
local printed = {}
function B:Print(m) printed[#printed + 1] = m end
R:DoSendRecruitmentMessage()
check(#sent == 0 and printed[#printed]:find("only raid icons"), "with Trade alone, nothing is posted and it says why")

-- ── Anniversary: every channel shows icons ──────────────────────────────
B, sent = load("anniversary")
R = B.Recruitment
check(not B.Compat.ChannelHidesRaidIcons("Trade"), "Anniversary: Trade shows raid icons")
R:DoSendRecruitmentMessage()
check(#sent == 2 and sent[2].msg == "{rt8} FILHOS DA HORDA {rt8} Guilda BR", "so the Trade copy keeps them")

print(("trade-icons: %d checks passed"):format(checks))
