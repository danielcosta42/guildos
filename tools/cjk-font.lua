-- Korean and Chinese clients draw GuildOS in the client's own font (issue #103), run against the
-- real Core/Core.lua and Core/Data.lua under a stubbed client.
--
-- IBM Plex Mono and Spectral cover Latin and Cyrillic but no Hangul and no Han: on koKR, zhCN and
-- zhTW every character, guild, item and zone name the client gave drew as boxes unless the player found the
-- "Use the game's font" setting. There the client's font is now the only one; elsewhere nothing
-- changes, the setting included.
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
  BRutus:ApplyFont(fs, size, role)
  return fs.file, fs.px
end

for _, locale in ipairs({ "koKR", "zhCN", "zhTW" }) do
  load(locale, nil)
  local file, px = drawn(12)
  check(file == STANDARD_TEXT_FONT and px == 12, locale .. ": text is drawn in the client's font, at its size")
  check(drawn(18) == STANDARD_TEXT_FONT and drawn(nil, "badge") == STANDARD_TEXT_FONT,
    locale .. ": serif sizes and font roles too")
  check(BRutus.GameFontOnly == true, locale .. ": the setting is forced on")
end

for _, locale in ipairs({ "enUS", "ptBR", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
  load(locale, nil)
  check(drawn(12):find("IBMPlexMono", 1, true), locale .. ": small text keeps GuildOS's mono")
  check(drawn(18):find("Spectral", 1, true), locale .. ": large text keeps GuildOS's serif")
  check(BRutus.GameFontOnly == false, locale .. ": nothing is forced")
  load(locale, "game")
  check(drawn(12) == STANDARD_TEXT_FONT, locale .. ": and the player's choice of the game's font still holds")
end

print(("cjk-font: %d checks passed"):format(checks))
