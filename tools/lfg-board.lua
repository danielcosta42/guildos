-- Being seen on the LFG board (issue #243), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua and Modules/LFGBoard.lua.
--
-- The notice comes on, once, for everybody who had it off by a default they never chose; a post
-- from the board reaches guild chat unless the box is off or the client holds chat; and nothing but
-- that click ever speaks there.
--
--   luajit -e 'ADDON="."' tools/lfg-board.lua
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
  function f:UnregisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Ana" end
local NOW = 1790000000
function GetServerTime() return NOW end
time = function() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
C_Timer = { After = function() end, NewTicker = function() end }

local guilded = true
function IsInGuild() return guilded end
local said = {}
function SendChatMessage(msg, chan) said[#said + 1] = { msg = msg, chan = chan } end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")

-- The payload as a table: what crosses the wire is the addon's own business, and the board reads
-- it back through the same two calls.
local passThrough = { Serialize = function(_, t) return t end, Deserialize = function(_, d) return true, d end }
LibStub = function() return passThrough end
dofile(ADDON .. "/Modules/LFGBoard.lua")

local wire = {}
GuildOS.CommSystem = {
  MSG_TYPES = { LFG = "LFG" },
  SendMessage = function(_, _, payload) wire[#wire + 1] = payload end,
}
local printed = {}
GuildOS.Print = function(_, msg) printed[#printed + 1] = msg end
local locked = false
GuildOS.Compat.InChatLockdown = function() return locked end

local Board = GuildOS.LFGBoard
local function fresh(prefs)
  GuildOS.db = { lfgPrefs = prefs }
  Board._cd = nil
  Board:Initialize()
  said, wire, printed = {}, {}, {}
end
local function onTheBoard() return GuildOS.db.lfgBoard[GuildOS:GetPlayerKey("Ana", "Realm")] ~= nil end

-- The notice
fresh(nil)
check(GuildOS.db.lfgPrefs.notify == true, "a new install is told")
check(GuildOS.db.lfgPrefs.postToGuild == true, "the box starts ticked")

fresh({ notify = false })
check(GuildOS.db.lfgPrefs.notify == true, "the saved default of off is turned on")
GuildOS.db.lfgPrefs.notify = false
Board:Initialize()
check(GuildOS.db.lfgPrefs.notify == false, "turning it off afterwards stays off")

-- Guild chat, from the board
fresh(nil)
Board:SetAvailable("TANK", "Karazhan", 3600, true)
check(#said == 1, "a post says one line")
check(said[1].chan == "GUILD", "in guild chat")
check(said[1].msg == "[Guild OS] LFG as Tank: Karazhan", "with the role and the note: " .. said[1].msg)

fresh(nil)
Board:SetAvailable("DPS", "", 3600, true)
check(said[1].msg == "[Guild OS] LFG as DPS", "no note, no dangling colon: " .. said[1].msg)

fresh(nil)
Board:SetAvailable("ANY", "Karazhan", 3600, true)
check(said[1].msg == "[Guild OS] LFG: Karazhan", "any role is no role to name: " .. said[1].msg)

fresh(nil)
Board:SetAvailable("HEALER", "a|cffffffffb", 3600, true)
check(not said[1].msg:find("|", 1, true), "the sanitized note reaches chat, never the raw one")

fresh(nil)
Board:SetAvailable("TANK", "Karazhan", 3600, false)
check(#said == 0, "the box off says nothing in chat")
check(onTheBoard(), "and the board still has it")

fresh(nil)
guilded = false
Board:SetAvailable("TANK", "Karazhan", 3600, true)
check(#said == 0, "nothing in chat with no guild to say it to")
guilded = true

-- Only the person's own click speaks
fresh(nil)
Board:HandleCommand({ "tank", "Karazhan" }, "tank Karazhan")
check(onTheBoard(), "/gos avail posts")
check(#said == 0, "but never in guild chat")
Board:Rebroadcast()
check(#wire == 2, "a rebroadcast goes out")
check(#said == 0, "and says nothing in chat")
Board:ClearAvailable()
check(#said == 0, "nor does taking the post down")
Board:SetAvailable("TANK", "Karazhan", 3600, true)
said = {}
Board:Rebroadcast()
Board:ClearAvailable()
Board:HandleCommand({ "off" }, "off")
check(#said == 0, "nor anything after a post that did speak")

-- A client holding chat
fresh(nil)
locked = true
Board:SetAvailable("TANK", "Karazhan", 3600, true)
locked = false
check(#said == 0, "a client holding chat says nothing")
check(onTheBoard(), "and the board still has it")
Board:ClearAvailable()
Board:SetAvailable("TANK", "Karazhan", 3600, true)
check(#said == 1, "a line that never went does not count against the next")

-- Posting again soon
fresh(nil)
Board:SetAvailable("TANK", "Karazhan", 3600, true)
Board:ClearAvailable()
NOW = NOW + 299
Board:Initialize()
Board:SetAvailable("TANK", "Karazhan", 3600, true)
check(#said == 1, "a line is not repeated inside five minutes, a /reload included")
Board:ClearAvailable()
NOW = NOW + 1
Board:SetAvailable("TANK", "Karazhan", 3600, true)
check(#said == 2, "five minutes later it goes again")

-- The other end: the notice is told whatever chat did, because nothing can know a line reached anyone
fresh(nil)
Board:HandleEntry("Bea-Realm", { role = "TANK", note = "Karazhan", ttl = 3600 })
check(#printed == 1, "a post is told by the addon")
Board:HandleEntry("Cid-Realm", { role = "TANK", note = "Karazhan", ttl = 3600, age = 60 })
check(#printed == 1, "a rebroadcast is not news")
check(GuildOS.db.lfgBoard[GuildOS:GetPlayerKey("Cid", "Realm")] ~= nil, "and is on the board all the same")
GuildOS.db.lfgPrefs.notify = false
Board:HandleEntry("Dan-Realm", { role = "TANK", note = "Karazhan", ttl = 3600 })
check(#printed == 1, "somebody who turned it off is not told")

print(checks .. " checks ok")
