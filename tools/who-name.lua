-- /who on both clients (issue #71), run against the real Core/Core.lua and Core/Compat.lua.
--
-- Compat.SetWhoToUI looked for C_FriendList.SetWhoToUI, but the function is SetWhoToUi (lower
-- case i) on every client, so it did nothing on either. And the roster's "Who" sent
-- "n-" .. name, which a name with a surname breaks; Forever's own UI builds the exact filter as
-- WHO_TAG_EXACT .. C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(name).
--
--   luajit -e 'ADDON="."' tools/who-name.lua
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

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  local calls = {}
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70170", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    WHO_TAG_EXACT = "x-"
    C_NameUtil = { ReplaceSurnameSeparatorWithLinkSeparator = function(n) return (n:gsub(" ", "-")) end }
    C_FriendList = { SetWhoToUi = function(v) calls[#calls + 1] = { "SetWhoToUi", v } end,
                     SendWho = function(f) calls[#calls + 1] = { "SendWho", f } end }
    SetWhoToUI = nil
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    WHO_TAG_EXACT, C_NameUtil = "x-", nil   -- Anniversary has the tag (GlobalStrings 24206), not C_NameUtil
    C_FriendList = { SetWhoToUi = function(v) calls[#calls + 1] = { "SetWhoToUi", v } end,
                     SendWho = function(f) calls[#calls + 1] = { "SendWho", f } end }
  end
  function GetRealmName() return "Realm" end
  Enum = { SendAddonMessageResult = {} }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  return GuildOS.Compat, calls
end

local C, calls = load("forever")
C.SetWhoToUI(true)
check(calls[1] and calls[1][1] == "SetWhoToUi" and calls[1][2] == true, "Forever: SetWhoToUi (lower-case i) is the one called")
check(C.WhoExact("Raikken Shadowmaster") == "x-Raikken-Shadowmaster", "Forever: the exact filter is built the way Blizzard builds it")

C, calls = load("anniversary")
C.SetWhoToUI(false)
check(calls[1] and calls[1][1] == "SetWhoToUi" and calls[1][2] == false, "Anniversary: the same function, by its real name")
check(C.WhoExact("Grefer") == "x-Grefer", "Anniversary: the exact filter is the one its own UI sends")
WHO_TAG_EXACT = nil
check(C.WhoExact("Grefer") == 'n-"Grefer"', "a client with no exact tag gets the n-\"Name\" filter")
WhoFrame = { IsVisible = function() return true end }
C.SetWhoToUI(false)
check(calls[#calls][2] == true, "giving the flag back leaves it on while Blizzard's Who list is open")
WhoFrame, LFGWhoListFrame = nil, { IsVisible = function() return true end }
C.SetWhoToUI(false)
check(calls[#calls][2] == true, "and while Forever's only Who list, LFGWhoListFrame, is open")
LFGWhoListFrame = nil

-- The roster's Who goes through it.
local f = assert(io.open(ADDON .. "/UI/RosterFrame.lua", "rb"))
local src = f:read("*a")
f:close()
check(src:find("Compat.SendWho%(GuildOS.Compat.WhoExact%(") ~= nil and not src:find('SendWho%("n%-" %.%.'),
      "the roster's Who builds its filter with WhoExact")
f = assert(io.open(ADDON .. "/Modules/RecruitmentSystem.lua", "rb"))
src = f:read("*a")
f:close()
check(src:find("SendWho%(GuildOS.Compat.WhoExact%(sender%)%)") ~= nil, "and so does the auto-invite's /who")

print(("who-name: %d checks passed"):format(checks))
