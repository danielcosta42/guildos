-- The game's font (issue #57), run against the real Core/Data.lua.
--
-- GuildOS draws its text in its own fonts (IBM Plex Sans and Mono) and a player had no way
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

-- ── Off (the default): GuildOS's own fonts ──────────────────────────────
GuildOSDB = {}
check(apply(18).file == F.sans, "off: 18px is IBM Plex Sans")
check(apply(11, "caption").file == F.mono, "off: a mono role is IBM Plex Mono")
check(apply(nil, "colHeader").file == F.monoStrong, "off: a role keeps its file")
GuildOSDB = nil
check(apply(18).file == F.sans, "before the SavedVariables load, GuildOS's fonts")
GuildOS.db = { settings = { font = "game" } }
check(apply(18).file == F.sans, "a guild's settings do not decide it: it is the account's")
GuildOS.db = nil

-- ── On: the client's font, same sizes ───────────────────────────────────
GuildOSDB = { font = "game" }
local fs = apply(18)
check(fs.file == STANDARD_TEXT_FONT and fs.size == 18 and fs.flags == "", "on: 18px is the game's font at 18px, no outline")
fs = apply(11)
check(fs.file == STANDARD_TEXT_FONT and fs.size == 11, "on: 11px too")
fs = apply(7)
check(fs.file == STANDARD_TEXT_FONT and fs.size == 11, "on: nothing under the sans floor, 11px, still")
fs = apply(nil, "countdown")
check(fs.file == STANDARD_TEXT_FONT and fs.size == 40, "on: a role keeps its size and takes the game's font")
fs = apply(11, "wordmark")
check(fs.file == STANDARD_TEXT_FONT and fs.size == 11, "on: a role asked smaller keeps the size asked")

print(("game-font: %d checks passed"):format(checks))
