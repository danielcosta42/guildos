-- The fonts (the Salão's phase 3, #449; the game's font of issue #57 before), run against the real
-- Core/Data.lua.
--
-- GuildOS draws its text in the mockup's three fonts: Cinzel for titles, Alegreya Sans for the interface,
-- Alegreya for reading. The old "game font" switch is gone: one look. A title in another script than Latin
-- takes a face that has it.
--
--   luajit -e 'ADDON="."' tools/game-font.lua
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

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GuildOS = {}
dofile(ADDON .. "/Core/Data.lua")
local F = GuildOS.Fonts

local function fontString()
  local fs = {}
  function fs:SetFont(file, size, flags) self.file, self.size, self.flags = file, size, flags end
  return fs
end
local function apply(size, role)
  local fs = fontString()
  local file, px = GuildOS:ApplyFont(fs, size, role)
  check(fs.file == file and fs.size == px, "ApplyFont returns what it set")
  return fs
end

-- ── The Salão's fonts (phase 3, #449) ────────────────────────────────────
-- Cinzel Bold for titles, Alegreya Sans for the interface, Alegreya for reading. The game's font is no
-- longer anyone's choice (#445 took the switch away, phase 3 the forced game font): a saved
-- GuildOSDB.font = "game" from before draws in the addon's fonts like everyone else.
for _, db in ipairs({ {}, { font = "game" } }) do
  GuildOSDB = db
  local what = db.font and "a saved game font, ignored: " or ""
  check(apply(18).file == F.ui and F.ui:find("AlegreyaSans%-Regular"), what .. "18px is Alegreya Sans")
  check(apply(nil, "colHeader").file == F.title and F.title:find("Cinzel%-Bold"), what .. "a header is Cinzel Bold")
  check(apply(nil, "button").file == F.uiBold and F.uiBold:find("AlegreyaSans%-Bold"), what .. "a button is Alegreya Sans Bold")
  check(apply(nil, "memberName").file == F.uiMedium, what .. "a name is Alegreya Sans Medium")
  check(apply(nil, "reading").file == F.read and F.read:find("Alegreya%-Regular"), what .. "a text to read is Alegreya")
end
GuildOSDB = nil
check(apply(18).file == F.ui, "before the SavedVariables load, the same fonts")

-- Sizes: a size asked for draws one larger in Alegreya Sans (its small body), never under 11px; a title as asked,
-- never under 10px; a role's own size as it is.
local fs = apply(12)
check(fs.size == 13 and fs.flags == "", "12px asked is 13px drawn, no outline")
check(apply(7).size == 11, "nothing under the floor, 11px")
check(apply(nil, "body").size == F.body.size, "a role keeps its size")
check(apply(8, "colHeader").size == 10, "a title never under 10px")
check(apply(14, "sectionTitle").size == 14, "a title asked 14 is 14")

-- A title's text in another script draws in the interface's bold face, which has it; Latin stays in Cinzel.
local t = fontString()
GuildOS:ApplyFont(t, nil, "windowTitle")
function t:SetText(x) self.text = x end
GuildOS:SetTitleText(t, "Abaixo da Curva")
check(t.file == F.title and t.text == "Abaixo da Curva", "a Latin guild name is in Cinzel")
GuildOS:SetTitleText(t, "\208\147\208\184\208\187\209\140\208\180\208\184\209\143")
check(t.file == F.uiBold, "a Cyrillic one in Alegreya Sans Bold")
GuildOS:SetTitleText(t, "Guardi\195\181es \226\128\148 Forte")
check(t.file == F.title, "accents and a dash are still Latin")
check(GuildOS.IsLatinText("\234\184\184\235\147\156") == false, "Hangul is not")

print(("game-font: %d checks passed"):format(checks))
