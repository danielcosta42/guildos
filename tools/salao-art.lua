-- The Salão's art (specs/salao/fase3.md, #449): every texture the look names, and every Media/Salao file the
-- source refers to, is on disk and is a TGA WoW draws: 32-bit, uncompressed, top-left origin, power-of-two
-- sides. A file the client cannot read draws as a green square in game, or nothing; this catches it here.
-- tools/salao_art.py draws them (`--check` says whether the files on disk are what it draws).
--
--   luajit -e 'ADDON="."' tools/salao-art.lua
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

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), Dialogs = {} }
dofile(ADDON .. "/Core/Style.lua")
local S = GuildOS.Style

local function isPot(n)
  local p = 1
  while p < n do p = p * 2 end
  return p == n
end

-- A Media/Salao path as the client names it, on disk.
local function onDisk(path)
  local rel = path:gsub("^Interface\\AddOns\\GuildOS\\", ""):gsub("\\", "/")
  local f = io.open(ADDON .. "/" .. rel, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function tga(name, data)
  check(data ~= nil, name .. " is on disk")
  check(#data >= 18, name .. " has a TGA header")
  local idLen, cmap, kind = data:byte(1), data:byte(2), data:byte(3)
  local w = data:byte(13) + data:byte(14) * 256
  local h = data:byte(15) + data:byte(16) * 256
  local depth, desc = data:byte(17), data:byte(18)
  check(kind == 2 and cmap == 0 and idLen == 0, name .. " is an uncompressed true-colour TGA")
  check(depth == 32 and desc == 0x28, name .. " is 32-bit with 8 alpha bits, top-left origin")
  check(isPot(w) and isPot(h) and w <= 512 and h <= 512, string.format("%s is %dx%d, power-of-two sides", name, w, h))
  check(#data == 18 + w * h * 4, name .. " holds every pixel")
  return w * h * 4 + 18
end

-- Every texture the look names.
local total, n = 0, 0
for name, path in pairs(S.ART) do
  check(path:find("^Interface\\AddOns\\GuildOS\\Media\\Salao\\") and path:find("%.tga$"), name .. " is a Media/Salao TGA")
  total = total + tga(name, onDisk(path))
  n = n + 1
end
check(n >= 20, "the look names its textures (" .. n .. ")")
-- The Members list's marks (#449): a round chip each, drawn at 32px and shown at 18.
for _, name in ipairs({ "mark-crest", "mark-warn", "mark-banner" }) do
  local data = S.ART[name] and onDisk(S.ART[name])
  check(data ~= nil and data:byte(13) == 32 and data:byte(15) == 32, name .. " is named by the look, 32x32")
end
check(total < 1.5 * 1024 * 1024, string.format("the art stays small: %d KB", math.floor(total / 1024)))

-- Every Media\Salao file a Lua file names directly, and every Style.ART name the source asks for.
local p = io.popen('git -C "' .. ADDON .. '" ls-files "*.lua"')
local files = {}
for line in p:lines() do if not line:find("^tools/") and not line:find("^Libs/") then files[#files + 1] = line end end
p:close()
check(#files > 100, "the scan covers the addon's files")
local direct, asked = 0, 0
for _, rel in ipairs(files) do
  local fh = io.open(ADDON .. "/" .. rel, "rb")
  local src = fh:read("*a")
  fh:close()
  for name in src:gmatch("Media\\\\Salao\\\\([%w%-_]+)") do
    direct = direct + 1
    check(onDisk("Media\\Salao\\" .. name .. (name:find("%.tga$") and "" or ".tga")), rel .. " names Media/Salao/" .. name .. ", which ships")
  end
  for name in src:gmatch('Style:Texture%([^,]+,%s*"([%w%-]+)"') do
    asked = asked + 1
    check(S.ART[name] ~= nil, rel .. " asks for the art \"" .. name .. "\", which the look names")
  end
  for name in src:gmatch('Style%.ART%.([%w_]+)') do
    asked = asked + 1
    check(S.ART[name] ~= nil, rel .. " reads Style.ART." .. name .. ", which the look names")
  end
  for name in src:gmatch('Style:Nine%([^,]+,%s*"([%w%-]+)"') do
    asked = asked + 1
    check(S.ART[name] ~= nil, rel .. " lays out the art \"" .. name .. "\" in nine, which the look names")
  end
  for name in src:gmatch('Style:Three%([^,]+,%s*"([%w%-]+)"') do
    asked = asked + 1
    check(S.ART[name] ~= nil, rel .. " lays out the art \"" .. name .. "\" in three, which the look names")
  end
end
check(asked > 20, "the source asks for the art by name (" .. asked .. " times)")

-- The onboarding's paintings (UI.Picture, #449): every key UI/Onboarding.lua lists is a 512x256 TGA in
-- Media/Salao/onboarding, every picture the source asks for is one of them, and the help's guides each
-- have their own.
do
  local fh = io.open(ADDON .. "/UI/Onboarding.lua", "rb")
  local ui = fh:read("*a")
  fh:close()
  local list = ui:match("Picture%.KEYS = {}%s*for _, key in ipairs%(({.-})%) do")
  check(list ~= nil, "UI/Onboarding.lua lists the paintings' keys")
  local keys, nk, bytes = {}, 0, 0
  for key in list:gmatch('"([%w%-]+)"') do
    keys[key] = true
    nk = nk + 1
    local name = "onboarding/" .. key
    bytes = bytes + tga(name, onDisk(S.ART_DIR .. "onboarding\\" .. key .. ".tga"))
    local data = onDisk(S.ART_DIR .. "onboarding\\" .. key .. ".tga")
    check(data:byte(13) + data:byte(14) * 256 == 512 and data:byte(15) + data:byte(16) * 256 == 256,
      name .. " is 512x256, the shape UI.Picture crops from")
  end
  check(nk >= 20, "the pictures are paintings (" .. nk .. ")")
  local guide = {}
  for id, key in ui:match("Picture%.GUIDE = (%b{})"):gmatch('([%w_]+)%s*=%s*"([%w%-]+)"') do
    check(keys[key], "the guide " .. id .. "'s painting " .. key .. " is listed")
    guide[id] = key
  end
  -- Every `ill` the source names.
  local q = io.popen('git -C "' .. ADDON .. '" ls-files "Modules/*.lua" "UI/*.lua"')
  local asked = 0
  for rel in q:lines() do
    local f2 = io.open(ADDON .. "/" .. rel, "rb")
    local src = f2:read("*a")
    f2:close()
    for key in src:gmatch('ill%s*=%s*"([%w%-]+)"') do
      asked = asked + 1
      check(keys[key], rel .. " asks for the picture \"" .. key .. "\", which has a painting")
    end
  end
  q:close()
  check(asked >= 25, "the cards, the tour and the guides ask for pictures (" .. asked .. ")")
  -- The guides: no two show the same painting.
  local mf = io.open(ADDON .. "/Modules/Onboarding.lua", "rb")
  local mod = mf:read("*a")
  mf:close()
  local guides = mod:match("O%.GUIDES = (%b{})")
  local seen, ng = {}, 0
  for id, ill in guides:gmatch('id%s*=%s*"([%w_]+)",%s*ill%s*=%s*"([%w%-]+)"') do
    local key = guide[id] or ill
    check(not seen[key], "the guide " .. id .. " has its own painting (" .. key .. " is also " .. tostring(seen[key]) .. "'s)")
    seen[key] = id
    ng = ng + 1
  end
  check(ng >= 12, "every guide is checked (" .. ng .. ")")
  check(io.open(ADDON .. "/tools/onboarding_art.py", "rb") ~= nil, "the script that paints them is in tools/")
  print(("salao-art: %d onboarding paintings, %d KB"):format(nk, math.floor(bytes / 1024)))
end

-- The fonts' licences and the art's script ship beside them.
check(io.open(ADDON .. "/tools/salao_art.py", "rb") ~= nil, "the script that draws the art is in tools/")
for _, lic in ipairs({ "OFL-Cinzel.txt", "OFL-Alegreya.txt", "OFL-AlegreyaSans.txt" }) do
  local f = io.open(ADDON .. "/Media/Fonts/" .. lic, "rb")
  check(f and f:read("*a"):find("SIL Open Font License", 1, true), lic .. " ships")
  if f then f:close() end
end

print(("salao-art: %d checks passed, %d textures, %d KB"):format(checks, n, math.floor(total / 1024)))
