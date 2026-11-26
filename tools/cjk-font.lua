-- Korean and Chinese clients draw GuildOS in the client's own font (issue #103), run against the
-- real Core/Core.lua and Core/Data.lua under a stubbed client.
--
-- The Salão's fonts (Cinzel, Alegreya Sans, Alegreya; #449) have no Hangul and no Han: on koKR, zhCN and
-- zhTW every character, guild, item and zone name would draw as boxes. There the client's fonts are the only
-- ones (a title takes the client's own title face, its quest titles'); Cinzel has no Cyrillic either, so on
-- ruRU a title takes the game's. Elsewhere the addon's fonts.
--
--   luajit -e 'ADDON="."' tools/cjk-font.lua
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

STANDARD_TEXT_FONT = "Fonts\\CLIENT.TTF"
local function load(locale, setting)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
  function hooksecurefunc() end
  function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  function GetLocale() return locale end
  C_Timer = { After = function() end, NewTicker = function() end }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  GuildOSDB = { font = setting }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Locales/Locale.lua")
  dofile(ADDON .. "/Core/Data.lua")
end
local function drawn(size, role)
  local fs = { SetFont = function(s, file, px) s.file, s.px = file, px end }
  GuildOS:ApplyFont(fs, size, role)
  return fs.file, fs.px
end

local MORPHEUS = "Fonts\\MORPHEUS_LOCAL.TTF"
for _, locale in ipairs({ "koKR", "zhCN", "zhTW" }) do
  load(locale, nil)
  QuestTitleFont = nil
  local file, px = drawn(12)
  check(file == STANDARD_TEXT_FONT and px == 13, locale .. ": text is drawn in the client's font, at its size")
  check(drawn(18) == STANDARD_TEXT_FONT and drawn(nil, "badge") == STANDARD_TEXT_FONT,
    locale .. ": large sizes and font roles too")
  check(drawn(nil, "sectionTitle") == STANDARD_TEXT_FONT, locale .. ": a title too, with no quest-title font to take")
  QuestTitleFont = { GetFont = function() return MORPHEUS, 18, "" end }
  check(drawn(nil, "sectionTitle") == MORPHEUS, locale .. ": a title takes the client's own title face when it has one")
  QuestTitleFont = nil
  check(GuildOS.GameFontOnly == true, locale .. ": the setting is forced on")
end

for _, locale in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "ruRU", "itIT" }) do
  load(locale, nil)
  check(drawn(12):find("AlegreyaSans", 1, true), locale .. ": text keeps GuildOS's Alegreya Sans")
  check(drawn(nil, "tableNum"):find("AlegreyaSans", 1, true), locale .. ": numbers too")
  check(GuildOS.GameFontOnly == false, locale .. ": nothing is forced")
  QuestTitleFont = { GetFont = function() return MORPHEUS, 18, "" end }
  if locale == "ruRU" then
    check(drawn(nil, "sectionTitle") == MORPHEUS, "ruRU: Cinzel has no Cyrillic, a title takes the game's title face")
  else
    check(drawn(nil, "sectionTitle"):find("Cinzel", 1, true), locale .. ": a title is Cinzel")
  end
  QuestTitleFont = nil
  load(locale, "game")
  check(drawn(12):find("AlegreyaSans", 1, true), locale .. ": a saved game-font choice from before is gone: one look")
end

print(("cjk-font: %d checks passed"):format(checks))
