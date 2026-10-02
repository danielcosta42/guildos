-- The game's font (issue #57), run against the real Core/Data.lua.
--
-- GuildOS draws its text in its own fonts (Spectral, IBM Plex Mono) and a player had no way
-- to change that. GuildOSDB.font = "game" (account-wide) makes ApplyFont use the client's own
-- font (STANDARD_TEXT_FONT), at the same sizes. Off, nothing changes.
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
BRutus = {}
dofile(ADDON .. "/Core/Data.lua")
local F = BRutus.Fonts

local function fontString()
  local fs = {}
  function fs:SetFont(file, size, flags) self.file, self.size, self.flags = file, size, flags end
  return fs
end
local function apply(size, role)
  local fs = fontString()
  local file, px = BRutus:ApplyFont(fs, size, role)
  check(fs.file == file and fs.size == px, "ApplyFont returns what it set")
  return fs
end

-- ── Off (the default): GuildOS's own fonts ──────────────────────────────
GuildOSDB = {}
check(apply(18).file == F.serif, "off: 18px is Spectral")
check(apply(11).file == F.mono, "off: 11px is IBM Plex Mono")
check(apply(nil, "colHeader").file == F.monoStrong, "off: a role keeps its file")
GuildOSDB = nil
check(apply(18).file == F.serif, "before the SavedVariables load, GuildOS's fonts")
BRutus.db = { settings = { font = "game" } }
check(apply(18).file == F.serif, "a guild's settings do not decide it: it is the account's")
BRutus.db = nil

-- ── On: the client's font, same sizes ───────────────────────────────────
GuildOSDB = { font = "game" }
local fs = apply(18)
check(fs.file == STANDARD_TEXT_FONT and fs.size == 18 and fs.flags == "", "on: 18px is the game's font at 18px, no outline")
fs = apply(11)
check(fs.file == STANDARD_TEXT_FONT and fs.size == 11, "on: 11px too")
fs = apply(7)
check(fs.file == STANDARD_TEXT_FONT and fs.size == 10, "on: nothing under 10px still")
fs = apply(nil, "countdown")
check(fs.file == STANDARD_TEXT_FONT and fs.size == 38, "on: a role keeps its size and takes the game's font")
fs = apply(11, "wordmark")
check(fs.file == STANDARD_TEXT_FONT and fs.size == 11, "on: a serif role under 14px keeps its size")

print(("game-font: %d checks passed"):format(checks))
