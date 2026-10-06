-- Recruitment posts to the channels as the client names them (issue #112), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/RecruitEngagement.lua and
-- Modules/RecruitmentSystem.lua, as each game and in several languages.
--
-- The preset channels were English names, and a French client calls LookingForGroup
-- "RechercheDeGroupe": GetChannelName("LookingForGroup") is 0 there, and the post went nowhere.
-- The names now come from the game's ChatChannels table for the client's language, and a preset
-- named in any language (saved earlier, typed, or sent by an officer on an English client) posts
-- to this client's channel of that kind.
--
--   luajit -e 'ADDON="."' tools/recruit-channels.lua
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

-- `joined`: the channels the player is in, by the name the client gives them, with their numbers.
local function load(game, locale, joined, channels)
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
  function GetLocale() return locale end
  function GetRealmName() return "Realm" end
  function UnitName() return "Chehul" end
  function GetServerTime() return 1790000000 end
  function GetTime() return 1000 end
  time = function() return 1790000000 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1 end
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
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
  local sent = {}
  function SendChatMessage(msg, chan, _, num) sent[#sent + 1] = { msg = msg, chan = chan, num = num } end
  function GetChannelName(name) return joined[name] or 0 end
  BRutus.db = { recruitment = { message = "Guild is recruiting", channels = channels } }
  function BRutus:IsOfficer() return true end
  return BRutus.Recruitment, sent
end
local function same(a, b) return table.concat(a, "|") == table.concat(b, "|") end
local function nums(sent)
  local out = {}
  for i, s in ipairs(sent) do out[i] = s.num end
  return table.concat(out, ",")
end

-- ── A French client ─────────────────────────────────────────────────────
local FR = { Commerce = 2, RechercheDeGroupe = 4, RecrutementDeGuilde = 5, MonCanal = 6 }
local R, sent = load("anniversary", "frFR", FR, { "LookingForGroup", "Trade" })
check(same(R:PresetChannels(), { "Commerce", "RechercheDeGroupe", "RecrutementDeGuilde" }),
  "a French client is offered its channels by their French names")
R:DoSendRecruitmentMessage()
check(nums(sent) == "4,2", "the English names saved before post to the French channels of that kind")
local names, joinedN = R:_ResolveChannels(BRutus.db.recruitment)
check(same(names, { "RechercheDeGroupe", "Commerce" }) and joinedN == 2,
  "and the member's consent popup names them as the client does")

R, sent = load("anniversary", "frFR", FR, { "Gildenrekrutierung", "MonCanal", "commerce" })
R:DoSendRecruitmentMessage()
check(nums(sent) == "5,6,2", "a preset in another language (an officer's German), a channel of one's own, any case")

-- Typed in French by hand while the English default was still saved: one channel, one post.
R, sent = load("anniversary", "frFR", FR, { "LookingForGroup", "RechercheDeGroupe" })
R:DoSendRecruitmentMessage()
check(nums(sent) == "4", "the same channel saved in two languages is posted to once")
names, joinedN = R:_ResolveChannels(BRutus.db.recruitment)
check(same(names, { "RechercheDeGroupe" }) and joinedN == 1, "and named once in the consent popup")

R = load("anniversary", "frFR", FR, {})
R:Initialize()
check(same(BRutus.db.recruitment.channels, { "RechercheDeGroupe" }), "a new setup starts on the French LookingForGroup")

-- The same channel twice in two languages is one channel.
R = load("anniversary", "frFR", FR, { "LookingForGroup" })
local list = BRutus.db.recruitment.channels
check(not R:AddChannel(list, "RechercheDeGroupe") and #list == 1, "adding a channel already there in English adds nothing")
check(R:RemoveChannel(list, "RechercheDeGroupe") and #list == 0, "and removing it by its French name takes the English one out")
check(R:AddChannel(list, "MonCanal") and R:HasChannel(list, "moncanal") and not R:HasChannel(list, "Commerce"),
  "a channel of one's own is added, and found in any case")

-- ── Every language, as the game names them ──────────────────────────────
local ANNIVERSARY = {
  enUS = { "Trade", "LookingForGroup", "GuildRecruitment" },
  deDE = { "Handel", "SucheNachGruppe", "Gildenrekrutierung" },
  esES = { "Comercio", "BuscandoGrupo", "BuscaHermandad" },
  esMX = { "Comercio", "BuscarGrupo", "BuscaHermandad" },
  frFR = { "Commerce", "RechercheDeGroupe", "RecrutementDeGuilde" },
  ptBR = { "Comércio", "ProcurandoGrupo", "RecrutamentoDeGuilda" },
  ruRU = { "Торговля", "ПоискСпутников", "Гильдии" },
  koKR = { "거래", "파티찾기", "길드모집" },
  zhCN = { "交易", "寻求组队", "公会招募" },
  zhTW = { "交易", "尋求組隊", "公會招募" },
}
for loc, want in pairs(ANNIVERSARY) do
  R = load("anniversary", loc, {}, {})
  check(same(R:PresetChannels(), want), "Anniversary " .. loc .. ": " .. table.concat(want, ", "))
end
-- Forever has no GuildRecruitment, its Spanish LookingForGroup is BuscarGrupo, and its Russian
-- one is named with a space (the channel's name, not its shortcut: it is no zone channel).
local FOREVER = {
  enUS = { "Trade", "LookingForGroup" }, esES = { "Comercio", "BuscarGrupo" }, frFR = { "Commerce", "RechercheDeGroupe" },
  ptBR = { "Comércio", "ProcurandoGrupo" }, zhTW = { "交易", "尋求組隊" }, ruRU = { "Торговля", "Поиск спутников" },
}
for loc, want in pairs(FOREVER) do
  R = load("forever", loc, {}, {})
  check(same(R:PresetChannels(), want), "Forever " .. loc .. ": " .. table.concat(want, ", "))
end
R, sent = load("forever", "esES", { BuscarGrupo = 3 }, { "BuscandoGrupo" })
R:DoSendRecruitmentMessage()
check(nums(sent) == "3", "Forever in Spanish: Anniversary's BuscandoGrupo posts to BuscarGrupo")
R, sent = load("forever", "ruRU", { ["Поиск спутников"] = 3 }, { "LookingForGroup", "ПоискСпутников" })
R:DoSendRecruitmentMessage()
check(nums(sent) == "3", "Forever in Russian: LookingForGroup, or its Anniversary name, posts to Поиск спутников")
-- On Forever a GuildRecruitment can only be a channel somebody made, and it is left as named.
R, sent = load("forever", "frFR", { GuildRecruitment = 7 }, { "GuildRecruitment" })
R:DoSendRecruitmentMessage()
check(nums(sent) == "7", "Forever: a channel called GuildRecruitment is posted to as named, not as a French preset")
R = load("anniversary", "enGB", {}, {})
check(same(R:PresetChannels(), ANNIVERSARY.enUS), "a language the table does not have reads English")

-- The panel's buttons are this client's names, and it asks the module what is on: no English
-- channel name is written anywhere outside the table.
for _, path in ipairs({ "UI/RosterFrame.lua", "Modules/RecruitmentSystem.lua", "Core/Commands.lua" }) do
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local src = f:read("*a")
  f:close()
  -- Comments aside, and the table itself and the default it is asked for.
  src = src:gsub("%-%-[^\n]*", ""):gsub("Recruitment%.CHANNELS = %b{}", "")
           :gsub('self:ChannelName%("LookingForGroup"%)', "")
  for _, name in ipairs({ '"Trade"', '"LookingForGroup"', '"GuildRecruitment"' }) do
    check(not src:find(name, 1, true), path .. " names no channel " .. name .. " in English")
  end
  if path == "UI/RosterFrame.lua" then
    check(src:find("Recruitment:PresetChannels()", 1, true) and src:find("Recruitment:HasChannel(chs, b._ch)", 1, true),
      "the panel offers the client's channels and asks the module which are on")
  end
end

print(("recruit-channels: %d checks passed"):format(checks))
