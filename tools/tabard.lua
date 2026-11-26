-- The guild's tabard as the game draws it (issue #213), run against the real Core/Core.lua and
-- Core/Compat.lua, with the values the retail client gave in game on 2026-10-29 (Forever's API is the
-- same): GetGuildLogoInfo's colours as bytes and the emblem's style, GetGuildTabardFiles' six files.
--
--   luajit -e 'ADDON="."' tools/tabard.lua
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
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetRealmName() return "Normal" end
C_Timer = { After = function() end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
local Compat = GuildOS.Compat

-- What the sample guild answered: background #21dcff, border #ffffff, emblem #dfa55a, emblem 69.
local logo = { 33, 220, 255, 255, 255, 255, 223, 165, 90, 414975, 69 }
local files = { 180115, 180114, 185157, 185156, 180293, 180292 }
function GetGuildLogoInfo() return unpack(logo) end
function GetGuildTabardFiles() return unpack(files) end

local t = Compat.GuildTabard()
check(t and t.emblemStyle == 69, "the emblem's style")
check(t.background[1] == 33 and t.background[2] == 220 and t.background[3] == 255, "the background's colour")
check(t.border[1] == 255 and t.emblem[1] == 223 and t.emblem[3] == 90, "the border's and the emblem's")
check(#t.files == 6 and t.files[5] == 180293 and t.files[6] == 180292, "the six files, the border's last")

logo[2] = 219.6
check(Compat.GuildTabard().background[2] == 220, "a colour that is not a whole byte is rounded")
logo[2] = 220

local secret = {}
Compat.IsSecret = function(v) return v == secret end
logo[11] = secret
check(Compat.GuildTabard() == nil, "a secret value is no tabard")
logo[11] = 69
files[6] = nil
check(Compat.GuildTabard() == nil, "five files are no tabard")
files[6] = 180292
GetGuildTabardFiles = nil
check(Compat.GuildTabard() == nil, "a client without the call has none")

-- ── The crest's tabard (#449): which API draws it, and the probe's "tabard:" line ──────────────
Compat.IsSecret = function() return false end
GetGuildTabardFiles = function() return unpack(files) end
local inGuild = false
function IsInGuild() return inGuild end
check(Compat.GuildTabardInfo() == nil and Compat.TabardReport() == "none: not in a guild", "no guild: no tabard, and why")
inGuild = true
local info = Compat.GuildTabardInfo()
check(info and info.source == "logo" and info.emblemFile == 414975 and math.abs(info.background.g - 220 / 255) < 1e-9,
  "GetGuildLogoInfo: the colours in 0..1 and the emblem's file")
check(Compat.TabardReport() == "GetGuildLogoInfo (no masks)", "the report names it: " .. Compat.TabardReport())
-- Retail's and Forever's C_GuildInfo.GetGuildTabardInfo, its colours as ColorMixins, comes first.
local function color(r, g, b) return { GetRGB = function() return r, g, b end } end
C_GuildInfo = { GetGuildTabardInfo = function(unit)
  if unit == "player" then return { backgroundColor = color(0.1, 0.2, 0.3), borderColor = color(1, 1, 1),
    emblemColor = color(0.9, 0.8, 0.7), emblemFileID = 123, emblemStyle = 5 } end end }
info = Compat.GuildTabardInfo()
check(info.source == "info" and info.emblemFile == 123 and info.emblem.r == 0.9, "GetGuildTabardInfo first")
-- The game's own drawing (SetLargeGuildTabardTextures), on textures that take a mask.
local function tex() return { SetTexture = function(t, f) t.file = f end, GetTexture = function(t) return t.file end,
                              SetMask = function() end, Hide = function() end } end
UIParent = { CreateTexture = function() return tex() end }
SetLargeGuildTabardTextures = function(unit, em) if unit == "player" then em:SetTexture(77) end end
check(Compat.TabardReport() == "SetLargeGuildTabardTextures (masked round)", "the game's drawing, round")
local e, b2, b3 = tex(), tex(), tex()
check(Compat.SetGuildTabardTextures(e, b2, b3) and e.file == 77, "and it draws on the crest's textures")
SetLargeGuildTabardTextures = function() end
C_GuildInfo, GetGuildLogoInfo = nil, nil
check(Compat.TabardReport():find("^none: the guild's tabard did not answer %(has GetGuildTabardFiles, SetLargeGuildTabardTextures%)"),
  "APIs that answer nothing are named: " .. Compat.TabardReport())
SetLargeGuildTabardTextures, GetGuildTabardFiles = nil, nil
check(Compat.TabardReport() == "none: no tabard API on this client", "a client with none says so")
local fh = assert(io.open(ADDON .. "/Core/Probe.lua", "rb"))
local probe = fh:read("*a")
fh:close()
check(probe:find('GuildOS:Print("tabard: " .. tostring(r.tabard.used))', 1, true), "/gos debug probe prints the tabard: line")
for _, api in ipairs({ "C_GuildInfo.GetGuildTabardInfo", "GetGuildLogoInfo", "GetGuildTabardFiles", "GetGuildTabardFileNames",
                       "SetLargeGuildTabardTextures", "SetSmallGuildTabardTextures" }) do
  check(probe:find('"' .. api .. '"', 1, true), "the probe lists " .. api)
end

print(("tabard: %d checks passed"):format(checks))
