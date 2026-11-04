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

print(("tabard: %d checks passed"):format(checks))
