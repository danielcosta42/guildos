-- Display text cut by characters, never by bytes (issue #104), run against the real Core/Utils.lua.
--
-- Labels and names were cut with string.sub, which counts bytes: a Cyrillic letter is two of
-- them and a Hangul or Han one three, so a cut fell in the middle of a letter and drew garbage.
-- That is four of the game's ten languages, and the names their players carry.
--
--   luajit -e 'ADDON="."' tools/utf8-cut.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
C_Timer = { After = function() end, NewTicker = function() end }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")

-- A string is whole UTF-8 when no character is cut.
local function whole(s)
  local i = 1
  while i <= #s do
    local c = s:byte(i)
    local n = (c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1
    if c >= 128 and c < 192 then return false end
    for k = 1, n - 1 do
      local b = s:byte(i + k)
      if not b or b < 128 or b >= 192 then return false end
    end
    i = i + n
  end
  return true
end

local cases = {
  { "Alchemy", 3, "Alc", 7 },
  { "Алхимия", 3, "Алх", 7 },          -- Cyrillic: two bytes a letter
  { "연금술", 2, "연금", 3 },            -- Hangul: three
  { "炼金术", 1, "炼", 3 },              -- Han: three
  { "Ação", 2, "Aç", 4 },               -- Latin with marks
  { "Tal 1", 8, "Tal 1", 5 },           -- shorter than the cut: whole
}
for _, c in ipairs(cases) do
  local s, n, want, len = c[1], c[2], c[3], c[4]
  local got = BRutus:Utf8Head(s, n)
  check(got == want, ("%q cut to %d characters is %q, not %q"):format(s, n, want, got))
  check(whole(got), ("%q cut to %d characters splits no letter"):format(s, n))
  check(BRutus:Utf8Len(s) == len, ("%q has %d characters"):format(s, len))
end
check(BRutus:Utf8Head(nil, 3) == "" and BRutus:Utf8Head("abc", 0) == "", "nothing, or no characters, is empty")
-- A 12-character cut of a long Korean name: the raid HUD's.
local name = "가나다라마바사아자차카타파하"
check(whole(BRutus:Utf8Head(name, 12)) and BRutus:Utf8Len(BRutus:Utf8Head(name, 12)) == 12, "a Korean name keeps 12 whole letters")

print(("utf8-cut: %d checks passed"):format(checks))
