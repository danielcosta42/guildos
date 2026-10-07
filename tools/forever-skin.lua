-- Forever skin (issue #13), run against the real Core/Data.lua.
--
-- Every existing screen reads GuildOS.Colors and sets fonts, so the skin lives
-- in two tables and one helper. This proves the tokens carry the design
-- handoff's values, that each legacy key the old screens read points at the
-- right token (as its own copy), that violet only ever means epic — in the
-- palette and in the source — that the accent picker is gone, and that
-- ApplyFont enforces the type rules. It also checks the fonts and textures
-- the skin ships are really in Media/.
--
--   luajit -e 'ADDON="."' tools/forever-skin.lua
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
local C, F = GuildOS.Colors, GuildOS.Fonts

local EPS = 1e-9
local function near(a, b) return math.abs(a - b) < EPS end
local function hex(t)
  local function byte(v) return math.floor(v * 255 + 0.5) end
  return string.format("#%02x%02x%02x", byte(t.r), byte(t.g), byte(t.b))
end

-- ── 1. Tokens carry the handoff values ──────────────────────────────────
local HANDOFF = {
  bg = "#100f16", panel = "#17161f", popup = "#1d1b26", well = "#0c0b10",
  line = "#2a2733", lineHi = "#3a3646", text = "#ece7e0", textSoft = "#a9a2b0",
  label = "#97909f", labelDim = "#6f6878", disabled = "#4b4553", gold = "#d9a94f",
  onGold = "#17130a", ok = "#7dd88f", danger = "#cf5b52", info = "#5b93cf", epic = "#a86fe0",
}
for key, want in pairs(HANDOFF) do
  check(C[key] and hex(C[key]) == want, key .. " is " .. want .. " (got " .. (C[key] and hex(C[key]) or "nil") .. ")")
  check(C[key].a == 1, key .. " is opaque")
end

-- ── 2. Legacy keys point at the token that plays their role ─────────────
local LEGACY = {
  silver = "textSoft", textDim = "label", border = "line", separator = "line",
  accent = "gold", headerBg = "panel", bg0 = "well", bg1 = "well", bg2 = "panel",
  panelDark = "well", row1 = "well", row2 = "bg", rowHover = "panel",
  red = "danger", green = "ok", blue = "info", online = "ok", offline = "disabled",
}
for key, token in pairs(LEGACY) do
  check(C[key] and hex(C[key]) == HANDOFF[token], key .. " resolves to " .. token)
  check(C[key] ~= C[token], key .. " is its own table, not " .. token .. "'s")
  -- Copies, not shared tables: tweaking a legacy key must not recolour its token.
  local before = C[token].r
  C[key].r = -1
  check(C[token].r == before, "changing " .. key .. " leaves " .. token .. " alone")
  C[key].r = before
end
check(C.border.a == 1 and C.separator.a == 1, "borders and separators are no longer translucent")
check(hex(C.white) == "#ffffff", "white stays pure for vertex resets")
check(hex(C.accentSoft) == HANDOFF.gold and near(C.accentSoft.a, 0.14), "accentSoft is a faint gold wash")
check(near(C.accentDim.r, C.gold.r * 0.54) and near(C.accentDim.g, C.gold.g * 0.54) and near(C.accentDim.b, C.gold.b * 0.54),
  "accentDim is gold dimmed on every channel")
check(C.shadow.r == 0 and C.shadow.g == 0 and C.shadow.b == 0 and near(C.shadow.a, 0.55), "the shadow is black at 0.55")
check(C.darkGold == nil, "darkGold, which nothing used, is gone")

-- ── 3. Violet only means epic, in the palette and in the source ─────────
local OLD_VIOLET = { r = 0.56, g = 0.48, b = 0.82 }
for key, col in pairs(C) do
  if key ~= "epic" and type(col) == "table" then
    check(hex(col) ~= HANDOFF.epic, key .. " is not the epic violet")
    check(hex(col) ~= hex(OLD_VIOLET), key .. " is not the old Obsidian violet")
  end
end
-- The old violet (0.56, 0.48, 0.82 = #8F7AD1) however it is spelled: three
-- decimals in a row, across lines too (0.56 / .56 / 0.561), or a hex colour
-- within 2 per channel (|cff8F7BD1, "ff8f7ad1").
local function near3(a, b, c, x, y, z, tol)
  return math.abs(a - x) <= tol and math.abs(b - y) <= tol and math.abs(c - z) <= tol
end
local function hasOldViolet(src)
  local nums = {}
  for n in src:gmatch("%d*%.?%d+") do nums[#nums + 1] = tonumber(n) end
  for i = 1, #nums - 2 do
    if near3(nums[i], nums[i + 1], nums[i + 2], 0.56, 0.48, 0.82, 0.004) then return true end
  end
  for run in src:gmatch("%x+") do
    for i = 1, #run - 5 do
      local r, g, b = tonumber(run:sub(i, i + 1), 16), tonumber(run:sub(i + 2, i + 3), 16), tonumber(run:sub(i + 4, i + 5), 16)
      if near3(r, g, b, 0x8F, 0x7A, 0xD1, 2) then return true end
    end
  end
  return false
end
check(hasOldViolet("x(0.56 , 0.48 , 0.82)") and hasOldViolet("return .56, 0.480, 0.82")
  and hasOldViolet("{ r = 0.56, g = 0.48, b = 0.82 }") and hasOldViolet("return 0.56,\n  0.48,\n  0.82")
  and hasOldViolet('"|cff8F7BD1"') and hasOldViolet('CreateColorFromHexString("ff8f7ad1")')
  and not hasOldViolet("0.57, 0.48, 0.82") and not hasOldViolet('"|cffD9A94F"'),
  "the violet scan catches it in decimals, across lines and as hex")
-- Any violet, not only the old one (issue #69): red beating green and blue leading
-- both. A blue with more green than red is info. The palette's cool neutrals lean
-- that way on purpose, by 0.048 at most (lineHi), so a token may lead by under
-- 0.055; a colour written by hand may not lead by 0.02, since any lean it needs
-- belongs to a token. The scan reads each Set*Color* call (SetColorTexture too),
-- taking the first number in each of the first three arguments, so `sel and 0.14
-- or 0` counts as 0.14.
local function isViolet(r, g, b, lead)
  return r > g and b - math.max(r, g) >= lead
end
local function colourLines(src, test)
  local hits = {}
  for pos, args in src:gmatch("()Set%a*Color%a*%s*(%b())") do
    local ch, n = {}, 0
    for arg in (args:sub(2, -2) .. ","):gmatch("([^,]*),") do
      n = n + 1
      ch[n] = tonumber(arg:match("%d*%.?%d+") or "")
      if n == 3 then break end
    end
    if ch[1] and ch[2] and ch[3] and test(ch[1], ch[2], ch[3]) then
      local _, newlines = src:sub(1, pos):gsub("\n", "")
      hits[#hits + 1] = newlines + 1
    end
  end
  return hits
end
local function violetLines(src)
  return colourLines(src, function(r, g, b) return isViolet(r, g, b, 0.02) end)
end
for key, col in pairs(C) do
  if key ~= "epic" and type(col) == "table" and col.r then
    check(not isViolet(col.r, col.g, col.b, 0.055), key .. " does not read as violet")
  end
end
check(#violetLines("b:SetBackdropColor(0.260, 0.160, 0.360, 0.7)") == 1
  and #violetLines("self:SetBackdropColor(0.160, 0.150, 0.220, 1)") == 1
  and #violetLines("x:SetVertexColor(0.56,0.48,0.82)") == 1
  and violetLines("a()\nrow:SetBackdropColor(\n  sel and 0.14 or 0,\n  sel and 0.10 or 0,\n  sel and 0.26 or 0)")[1] == 2
  and #violetLines("self:SetBackdropColor(0.160, 0.150, 0.210, 1.0)") == 1
  and #violetLines("t:SetColorTexture(0.26, 0.16, 0.36, 1)") == 1
  and #violetLines("b:SetBackdropColor (0.26, 0.16, 0.36)") == 1
  and #violetLines("fb:SetBackdropColor(0.100, 0.100, 0.130, 1.0)") == 0
  and #violetLines("x:SetTextColor(0.357, 0.576, 0.812)") == 0
  and #violetLines("fs:SetTextColor(r, 0.82, 0, 1)") == 0
  and #violetLines("bar:SetStatusBarColor(heat, 0.8, 0.2, 1)") == 0
  and #violetLines("x:SetBackdropColor(C.epic.r, C.epic.g, C.epic.b)") == 0,
  "the range scan catches violet and leaves neutrals, info, variables and tokens alone")
-- The other fills #69 took out (olive, orange, brown), so none of them is pasted back,
-- however it is spelled.
local OFF_PALETTE = { { 0.3, 0.3, 0 }, { 0.4, 0.15, 0 }, { 0.6, 0.2, 0 }, { 0.10, 0.08, 0.03 }, { 0.18, 0.14, 0.04 } }
local function offPaletteLines(src)
  return colourLines(src, function(r, g, b)
    for _, t in ipairs(OFF_PALETTE) do
      if near3(r, g, b, t[1], t[2], t[3], 0.005) then return true end
    end
    return false
  end)
end
check(#offPaletteLines("osBtn:SetBackdropColor(.30, .3, 0, 0.6)") == 1
  and #offPaletteLines("x:SetBackdropColor(0.3, 0.3, 0.05, 1)") == 0,
  "the off-palette guard reads numbers, not spellings")
local toc = assert(io.open(ADDON .. "/GuildOS.toc", "r"), "GuildOS.toc")
local scanned = 0
for line in toc:lines() do
  local path = line:match("^%s*([%w_\\/%.%-]+%.lua)%s*$")
  if path then
    local f = io.open(ADDON .. "/" .. path:gsub("\\", "/"), "r")
    if f then
      local src = f:read("*a")
      f:close()
      scanned = scanned + 1
      check(not hasOldViolet(src), path .. " has no hard-coded Obsidian violet")
      local hits = violetLines(src)
      check(#hits == 0, path .. " sets no violet by hand (line " .. table.concat(hits, ", ") .. ")")
      hits = offPaletteLines(src)
      check(#hits == 0, path .. " brings back no fill #69 removed (line " .. table.concat(hits, ", ") .. ")")
    end
  end
end
toc:close()
check(scanned > 50, "the source scan covered the addon's files (" .. scanned .. ")")

-- ── 4. The accent picker is gone ────────────────────────────────────────
check(GuildOS.ACCENT_PRESETS == nil, "no accent presets")
check(GuildOS.ApplyTheme == nil, "no ApplyTheme in Data.lua")

-- ── 5. ApplyFont enforces the type rules ────────────────────────────────
local function fontString(result)
  local fs = { calls = {} }
  function fs:SetFont(file, size, flags)
    self.calls[#self.calls + 1] = { file = file, size = size, flags = flags }
    if #self.calls == 1 then return result end
    return true
  end
  return fs
end

local fs = fontString(true)
GuildOS:ApplyFont(fs, 18)
check(fs.calls[1].file == F.serif and fs.calls[1].size == 18, "18px is Spectral")
fs = fontString(true)
GuildOS:ApplyFont(fs, 14)
check(fs.calls[1].file == F.serif, "14px is the first serif size")
fs = fontString(true)
GuildOS:ApplyFont(fs, 13)
check(fs.calls[1].file == F.mono and fs.calls[1].size == 13, "13px is IBM Plex Mono")
fs = fontString(true)
GuildOS:ApplyFont(fs, 9)
check(fs.calls[1].file == F.mono and fs.calls[1].size == 10, "9px is clamped to 10px mono")
fs = fontString(true)
GuildOS:ApplyFont(fs, 7)
check(fs.calls[1].size == 10, "7px is clamped to 10px")
fs = fontString(true)
GuildOS:ApplyFont(fs, nil)
check(fs.calls[1].file == F.mono and fs.calls[1].size == 10, "no size means 10px mono")
fs = fontString(true)
GuildOS:ApplyFont(fs, 15, "wordmark")
check(fs.calls[1].file == F.serifStrong and fs.calls[1].size == 15, "a role picks the file; a given size wins")
fs = fontString(true)
GuildOS:ApplyFont(fs, 11, "wordmark")
check(fs.calls[1].file == F.mono and fs.calls[1].size == 11, "a serif role asked under 14px reads as mono")
fs = fontString(true)
GuildOS:ApplyFont(fs, 8, "colHeader")
check(fs.calls[1].file == F.monoStrong and fs.calls[1].size == 10, "a mono role keeps its weight and is clamped to 10px")
fs = fontString(true)
GuildOS:ApplyFont(fs, nil, "countdown")
check(fs.calls[1].file == F.mono and fs.calls[1].size == 38, "a role without a size uses the role size")
for _, size in ipairs({ 7, 10, 14, 22 }) do
  fs = fontString(true)
  GuildOS:ApplyFont(fs, size)
  check(fs.calls[1].flags == "", size .. "px is never outlined")
end
fs = fontString(false)
GuildOS:ApplyFont(fs, 12)
check(#fs.calls == 2 and fs.calls[2].file == STANDARD_TEXT_FONT and fs.calls[2].size == 12 and fs.calls[2].flags == "",
  "a font that fails to load falls back to the client font, still not outlined")
fs = fontString(nil)
GuildOS:ApplyFont(fs, 12)
check(#fs.calls == 1, "a client that returns nothing on success is not pushed onto the fallback")

-- ── 6. The type scale (spec §2.3), and every role follows the floors ─────
local SCALE = {
  wordmark = { F.serifStrong, 18 }, windowTitle = { F.serif, 16 },  sectionTitle = { F.serifStrong, 15 },
  body     = { F.serif, 14 },       memberName = { F.serifStrong, 14 }, itemName   = { F.serifStrong, 17 },
  caption  = { F.mono, 10 },        tableNum   = { F.mono, 12 },      colHeader    = { F.monoStrong, 10 },
  metricValue = { F.mono, 22 },     countdown  = { F.mono, 38 },      badge        = { F.mono, 10 },
}
for role, want in pairs(SCALE) do
  local spec = F[role]
  check(type(spec) == "table" and spec.file == want[1] and spec.size == want[2],
    role .. " is " .. want[2] .. "px in " .. tostring(want[1]):match("[^\\]+$"))
  local serif = spec.file == F.serif or spec.file == F.serifStrong
  check(not serif or spec.size >= 14, role .. " does not use serif under 14px")
  check(spec.size >= 10, role .. " is at least 10px")
end
check(F.normal == F.mono and F.number == F.mono, "the old normal and number aliases are mono")
check(F.serif:find("Spectral%-Regular%.ttf$") and F.serifStrong:find("Spectral%-SemiBold%.ttf$")
  and F.mono:find("IBMPlexMono%-Regular%.ttf$") and F.monoStrong:find("IBMPlexMono%-Medium%.ttf$"),
  "each font file is the weight its name says")

-- ── 7. The fonts and textures really ship ───────────────────────────────
local function onDisk(path)
  local f = io.open(ADDON .. "/" .. path:gsub("^Interface\\AddOns\\GuildOS\\", ""):gsub("\\", "/"), "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end
for _, key in ipairs({ "serif", "serifStrong", "mono", "monoStrong" }) do
  local data = onDisk(F[key])
  check(data and #data > 10000 and data:sub(1, 4) == "\0\1\0\0", key .. " font file exists and is a TrueType font")
end
check(onDisk("Media/Fonts/OFL-Spectral.txt") and onDisk("Media/Fonts/OFL-IBMPlexMono.txt"), "both font licences ship")

local TEXTURES = { ["glow-gold.tga"] = 128, ["drop-shadow.tga"] = 128, ["corner-2.tga"] = 8, ["ring-28.tga"] = 32 }
for name, size in pairs(TEXTURES) do
  local data = onDisk("Media/" .. name)
  check(data, name .. " exists")
  local w = data:byte(13) + data:byte(14) * 256
  local h = data:byte(15) + data:byte(16) * 256
  check(data:byte(3) == 2 and data:byte(17) == 32 and w == size and h == size,
    string.format("%s is a %dx%d 32-bit uncompressed TGA", name, size, size))
end

io.write(string.format("forever-skin: %d checks passed\n", checks))
