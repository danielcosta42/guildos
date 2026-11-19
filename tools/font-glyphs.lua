-- Characters the addon's font cannot draw (issue #391).
--
-- GuildOS draws its text in IBM Plex Sans and Mono, or in the client's own font with the "game
-- font" setting and always on Korean and Chinese clients (GuildOS:ApplyFont, Core/Data.lua). Text
-- has to draw in both, and neither has every geometric shape or dingbat: Plex has no "●" (a box
-- beside each online crafter, issue #389), the client's font no "✓" (a box on a delivered wishlist
-- item). A mark like that is a texture (|T...|t or a WHITE8x8 square), never a character. This reads every Lua file the TOC loads, comments left out,
-- and fails on any of them. Modules/ChehulNet.lua is shared verbatim with other addons and keeps the
-- client's font; Libs are third-party.
--
--   luajit -e 'ADDON="."' tools/font-glyphs.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks, fails = 0, {}
local function check(cond, what)
  checks = checks + 1
  if not cond then fails[#fails + 1] = what end
end

local MISSING = {
  "●", "○", "◉", "◦", "▪", "▫", "■", "□", "▲", "△", "▼", "▽", "▶", "▸", "►", "◀", "◂", "◄", "◆", "◇", "♦",
  "✓", "✔", "✗", "✘", "✕", "✖", "❌", "★", "☆", "⚠", "☑", "☐", "☒", "♥", "♠", "♣",
}
local EXEMPT = { ["Modules/ChehulNet.lua"] = true }

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- The source without its comments (long ones and `--` to the end of a line), strings kept: those
-- are what reaches the screen. A `--` inside a string is rare enough here to be read as a comment.
local function code(src)
  -- A long comment keeps its line breaks, so the line numbers in a failure stay true.
  src = src:gsub("(%-%-%[(=*)%[.-%]%2%])", function(c) return (c:gsub("[^\n]", "")) end)
  local out = {}
  for line in (src .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = (line:gsub("%-%-.*$", ""))
  end
  return table.concat(out, "\n")
end

-- The files the game loads: every .lua line of the TOC.
local toc = read(ADDON .. "/GuildOS.toc") or ""
local files = {}
for line in toc:gmatch("[^\r\n]+") do
  if not line:match("^%s*#") and line:match("%.lua%s*$") then
    local path = line:gsub("\\", "/"):gsub("%s+$", "")
    if not path:match("^Libs/") and not EXEMPT[path] then files[#files + 1] = path end
  end
end
check(#files > 50, "the TOC lists the addon's files: " .. #files)

for _, path in ipairs(files) do
  local src = read(ADDON .. "/" .. path)
  check(src ~= nil, path .. " is on disk")
  if src then
    local body, n, hits = code(src), 0, {}
    for line in (body .. "\n"):gmatch("(.-)\n") do
      n = n + 1
      for _, g in ipairs(MISSING) do
        if line:find(g, 1, true) then hits[#hits + 1] = string.format("%d (%s)", n, g) end
      end
    end
    check(#hits == 0, path .. " draws characters the font does not have, line " .. table.concat(hits, ", "))
  end
end

-- The guard itself: it sees a glyph in code and in a string, and not in a comment.
check(code('x = "●" -- ok'):find("●", 1, true) ~= nil, "a glyph in a string is seen")
check(code('x = 1 -- ●'):find("●", 1, true) == nil, "a glyph in a comment is not")
check(code('--[[ ✓ ]] y = 2'):find("✓", 1, true) == nil, "nor one in a long comment")
check(select(2, code("--[[ a\nb ]]\nz"):gsub("\n", "")) == 2, "a long comment keeps its line breaks")

if #fails > 0 then
  for i = 1, math.min(#fails, 20) do io.stderr:write("FAIL: " .. fails[i] .. "\n") end
  os.exit(1)
end
print(("font-glyphs: %d checks passed in %d files"):format(checks, #files))
