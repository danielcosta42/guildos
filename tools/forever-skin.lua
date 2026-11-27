-- Forever skin (issue #13), run against the real Core/Data.lua.
--
-- Every existing screen reads GuildOS.Colors and sets fonts, so the skin lives
-- in two tables and one helper. This proves the tokens carry the Salão mockup's
-- values (#449), that each legacy key the old screens read points at the
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

-- ── 1. Tokens carry the Salão mockup's values (phase 3, #449) ───────────
local HANDOFF = {
  bg = "#24170d", panel = "#2a1a0d", popup = "#1a1009", well = "#120b06",
  line = "#3a2a17", lineHi = "#6b5326", text = "#f6e9cf", textSoft = "#cdb98e",
  label = "#bba57a", labelDim = "#9e8f77", disabled = "#5b5348", gold = "#ffd100",
  goldHover = "#ffe04d", goldActive = "#d9b200", onGold = "#3b2512",
  ok = "#7dd88f", danger = "#ef7b72", warn = "#e89a5a", info = "#5b93cf", epic = "#a86fe0",
  gold2 = "#ffd77a", metal2 = "#c9a24a", door = "#e6d2a5", wood = "#3b2614", crimson = "#b0261b",
  paper = "#f3e4c2", paperInk = "#3a2a17", paperSoft = "#6f5a3c", paperTitle = "#6b1d0e", paperEdge = "#b49867",
  paperLight = "#fffaf0", quiet = "#fff6de",
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
check(C.shadow == nil, "the shadow, which nothing draws any more, is gone")
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
check(fs.calls[1].file == F.ui and fs.calls[1].size == 19, "18px is Alegreya Sans, a size larger")
fs = fontString(true)
GuildOS:ApplyFont(fs, 9)
check(fs.calls[1].file == F.ui and fs.calls[1].size == 11, "9px is clamped to 11px")
fs = fontString(true)
GuildOS:ApplyFont(fs, nil)
check(fs.calls[1].file == F.ui and fs.calls[1].size == 11, "no size means 11px")
fs = fontString(true)
GuildOS:ApplyFont(fs, 15, "wordmark")
check(fs.calls[1].file == F.title and fs.calls[1].size == 15, "a role picks the file; a given size wins")
fs = fontString(true)
GuildOS:ApplyFont(fs, 8, "colHeader")
check(fs.calls[1].file == F.title and fs.calls[1].size == 10, "a title role keeps its face and is clamped to 10px")
fs = fontString(true)
GuildOS:ApplyFont(fs, nil, "countdown")
check(fs.calls[1].file == F.title and fs.calls[1].size == 36, "a role without a size uses the role size")
for _, size in ipairs({ 7, 10, 14, 22 }) do
  fs = fontString(true)
  GuildOS:ApplyFont(fs, size)
  check(fs.calls[1].flags == "", size .. "px is never outlined")
end
fs = fontString(false)
GuildOS:ApplyFont(fs, 12)
check(#fs.calls == 2 and fs.calls[2].file == STANDARD_TEXT_FONT and fs.calls[2].size == 13 and fs.calls[2].flags == "",
  "a font that fails to load falls back to the client font, still not outlined")
fs = fontString(nil)
GuildOS:ApplyFont(fs, 12)
check(#fs.calls == 1, "a client that returns nothing on success is not pushed onto the fallback")

-- ── 6. The roles: titles in Cinzel, the interface in Alegreya Sans, reading in Alegreya ──
local SCALE = {
  wordmark = { F.title, 16 }, windowTitle = { F.title, 15 }, sectionTitle = { F.title, 15 },
  colHeader = { F.title, 11 }, metricValue = { F.title, 18 }, countdown = { F.title, 36 },
  body = { F.ui, 13 }, memberName = { F.uiMedium, 13 }, itemName = { F.uiBold, 14 },
  button = { F.uiBold, 12 }, caption = { F.ui, 11 }, tableNum = { F.ui, 12 }, badge = { F.uiBold, 11 },
  reading = { F.read, 13 },
}
for role, want in pairs(SCALE) do
  local spec = F[role]
  check(type(spec) == "table" and spec.file == want[1] and spec.size == want[2],
    role .. " is " .. want[2] .. "px in " .. tostring(want[1]):match("[^\\]+$"))
  check(spec.size >= (spec.file == F.title and 10 or 11), role .. " respects its face's floor")
end
for key, spec in pairs(F) do
  check(type(spec) ~= "table" or SCALE[key], key .. " is a role the scale lists")
end
check(F.normal == F.ui and F.number == F.ui and F.sans == F.ui and F.mono == F.ui, "the old names point at Alegreya Sans")
check(F.title:find("Cinzel%-Bold%.ttf$") and F.ui:find("AlegreyaSans%-Regular%.ttf$")
  and F.uiMedium:find("AlegreyaSans%-Medium%.ttf$") and F.uiBold:find("AlegreyaSans%-Bold%.ttf$")
  and F.read:find("Alegreya%-Regular%.ttf$"), "each font file is the face and weight its name says")

-- ── 7. The fonts and textures really ship ───────────────────────────────
local function onDisk(path)
  local f = io.open(ADDON .. "/" .. path:gsub("^Interface\\AddOns\\GuildOS\\", ""):gsub("\\", "/"), "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end
-- A static instance: WoW reads only a variable font's default instance, so no file may carry an fvar table.
local function isStatic(data)
  local n = data:byte(5) * 256 + data:byte(6)
  for i = 0, n - 1 do
    if data:sub(13 + i * 16, 16 + i * 16) == "fvar" then return false end
  end
  return true
end
for _, key in ipairs({ "title", "ui", "uiMedium", "uiBold", "read" }) do
  local data = onDisk(F[key])
  check(data and #data > 10000 and data:sub(1, 4) == "\0\1\0\0", key .. " font file exists and is a TrueType font")
  check(isStatic(data), key .. " is a static font, not a variable one")
end
check(onDisk("Media/Fonts/OFL-Cinzel.txt") and onDisk("Media/Fonts/OFL-Alegreya.txt")
  and onDisk("Media/Fonts/OFL-AlegreyaSans.txt"), "the three font licences ship")
check(not onDisk("Media/Fonts/IBMPlexSans-Regular.ttf") and not onDisk("Media/Fonts/IBMPlexMono-Regular.ttf"),
  "IBM Plex no longer ships")
check(not onDisk("Media/Fonts/Spectral-Regular.ttf") and not onDisk("Media/glow-gold.tga")
  and not onDisk("Media/drop-shadow.tga"), "Spectral, the glow and the drop shadow no longer ship")

local TEXTURES = { ["corner-2.tga"] = 8, ["ring-28.tga"] = 32 }
for name, size in pairs(TEXTURES) do
  local data = onDisk("Media/" .. name)
  check(data, name .. " exists")
  local w = data:byte(13) + data:byte(14) * 256
  local h = data:byte(15) + data:byte(16) * 256
  check(data:byte(3) == 2 and data:byte(17) == 32 and w == size and h == size,
    string.format("%s is a %dx%d 32-bit uncompressed TGA", name, size, size))
end

io.write(string.format("forever-skin: %d checks passed\n", checks))
