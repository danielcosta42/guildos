-- Being seen on the LFG board (issue #243), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua and Modules/LFGBoard.lua.
--
-- The notice comes on, once, for everybody who had it off by a default they never chose; a post
-- reaches guild chat unless the box is off or the client holds chat; and nobody with the addon is
-- told the same thing twice.
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
  Board._lastGuildLine = nil
  Board:Initialize()
  said, wire, printed = {}, {}, {}
end

-- The notice
fresh(nil)
check(GuildOS.db.lfgPrefs.notify == true, "a new install is told")
check(GuildOS.db.lfgPrefs.postToGuild == true, "a new install posts to guild chat")

fresh({ notify = false })
check(GuildOS.db.lfgPrefs.notify == true, "the saved default of off is turned on")
GuildOS.db.lfgPrefs.notify = false
Board:Initialize()
check(GuildOS.db.lfgPrefs.notify == false, "turning it off afterwards stays off")

-- Guild chat
fresh(nil)
Board:SetAvailable("TANK", "Karazhan", 3600)
check(#said == 1, "a post says one line")
check(said[1].chan == "GUILD", "in guild chat")
check(said[1].msg:find("Tank", 1, true) and said[1].msg:find("Karazhan", 1, true), "with the role and the note")
check(wire[1].chat == true, "and says so to the addon, so nobody is told twice")

fresh(nil)
Board:SetAvailable("DPS", "", 3600)
check(said[1].msg:sub(-1) ~= ":" and not said[1].msg:find(": ", 1, true), "no note is no dangling colon")

fresh(nil)
GuildOS.db.lfgPrefs.postToGuild = false
Board:SetAvailable("TANK", "Karazhan", 3600)
check(#said == 0, "the box off says nothing in chat")
check(wire[1].chat == nil, "and the addon's notice is the only one")
check(GuildOS.db.lfgBoard[GuildOS:GetPlayerKey("Ana", "Realm")] ~= nil, "the board still has it")

fresh(nil)
guilded = false
Board:SetAvailable("TANK", "Karazhan", 3600)
check(#said == 0, "nothing in chat with no guild to say it to")
guilded = true

fresh(nil)
locked = true
Board:SetAvailable("TANK", "Karazhan", 3600)
locked = false
check(#said == 0, "a client holding chat says nothing")
check(wire[1].chat == nil, "so the addon's notice carries it")
check(GuildOS.db.lfgBoard[GuildOS:GetPlayerKey("Ana", "Realm")] ~= nil, "and the board still has it")

-- Posting again soon
fresh(nil)
Board:SetAvailable("TANK", "Karazhan", 3600)
Board:ClearAvailable()
NOW = NOW + 60
Board:SetAvailable("TANK", "Karazhan", 3600)
check(#said == 1, "turning it off and on in a minute does not repeat the line")
check(wire[#wire].chat == nil, "and the addon's notice carries the repeat")
NOW = NOW + 300
Board:ClearAvailable()
Board:SetAvailable("TANK", "Karazhan", 3600)
check(#said == 2, "five minutes later it goes again")

-- The other end
fresh(nil)
Board:HandleEntry("Bea-Realm", { role = "TANK", note = "Karazhan", ttl = 3600 })
check(#printed == 1, "a post with no chat line is told by the addon")
Board:HandleEntry("Cid-Realm", { role = "TANK", note = "Karazhan", ttl = 3600, chat = true })
check(#printed == 1, "one already in guild chat is not told twice")
check(GuildOS.db.lfgBoard[GuildOS:GetPlayerKey("Cid", "Realm")] ~= nil, "and is on the board all the same")

print(checks .. " checks ok")
