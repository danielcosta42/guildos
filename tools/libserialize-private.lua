-- Guild OS serializes with its own LibSerialize (issue #87), run against the real Libs/LibStub.lua,
-- Libs/LibSerialize.lua, Core/Core.lua, Core/Compat.lua, Modules/CommSystem.lua and
-- Modules/SyncService.lua.
--
-- LibStub hands every addon the highest minor of a library. DBM-Core embeds LibSerialize 6,
-- whose number writer starts with `1 / num` to spot -0, and WoW: Forever raises on any division
-- by zero: every 0 failed to serialize, and no Guild OS message left any client with DBM on.
-- Here a "newer" LibSerialize that raises on 0 is loaded first, the way DBM's is in game.
--
--   luajit -e 'ADDON="."' tools/libserialize-private.lua
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

strmatch = string.match                                -- WoW's alias, which LibStub uses
dofile(ADDON .. "/Libs/LibStub.lua")

-- Another addon's LibSerialize, a higher minor, broken the way minor 6 is on Forever.
local theirs = LibStub:NewLibrary("LibSerialize", 6)
local function hasZero(v)
  if v == 0 then return true end
  if type(v) == "table" then
    for k, x in pairs(v) do if hasZero(k) or hasZero(x) then return true end end
  end
  return false
end
function theirs:Serialize(...)
  for i = 1, select("#", ...) do
    if hasZero((select(i, ...))) then error("LibSerialize.lua:1562: Division by zero") end
  end
  return "theirs"
end
function theirs:Deserialize() return false, "theirs" end

dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
check(LibStub("LibSerialize") == theirs, "the other addon's higher minor still owns the shared name, as in game")
local ours = LibStub("GuildOS-LibSerialize", true)
check(ours ~= nil and ours ~= theirs, "Guild OS's copy is registered under its own name, out of the other's reach")

-- ── 1. Ours round-trips the values a broadcast carries, zeros included ──
local value = { level = 60, ilvl = 0, gold = 0, prof = { rank = 0, max = 300 }, ratio = 0.5, neg = -12, big = 70000,
                name = "Chehul Costa", list = { 0, 1, 2 } }
local ok, s = pcall(ours.Serialize, ours, value)
check(ok and type(s) == "string", "a table full of zeros serializes (" .. tostring(s) .. ")")
local ok2, back = ours:Deserialize(s)
check(ok2 and back.ilvl == 0 and back.gold == 0 and back.prof.rank == 0 and back.prof.max == 300
  and back.ratio == 0.5 and back.neg == -12 and back.big == 70000 and back.name == "Chehul Costa"
  and back.list[1] == 0 and back.list[3] == 2, "and comes back the same")

-- A NaN still decodes, now that the reader makes it without dividing by zero.
local okNaN, nan = ours:Deserialize(ours:Serialize(0 / 0))
check(okNaN and nan ~= nan, "a NaN round-trips")

-- Written by DBM's real LibSerialize 6 (with its -0.0): ours reads it, so an old client still reaches a fixed one.
local SIX = "0156426c6973742a0103127a50042d302e30126e013262696718011170426e616d65c243686568756c20436f737461"
local fixture = SIX:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)
local okSix, fromSix = ours:Deserialize(fixture)
check(okSix and fromSix.n == 0 and fromSix.big == 70000 and fromSix.name == "Chehul Costa"
  and fromSix.list[1] == 0 and fromSix.z == 0 and 1 / fromSix.z < 0, "a message written by minor 6, -0.0 included, reads back")

-- ── 2. Guild OS's own modules use it ─────────────────────────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame() local f = {}; function f:RegisterEvent() end; function f:SetScript() end; return f end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetRealmName() return "Realm" end
function UnitName() return "Chehul" end
function IsInGuild() return true end
function GetTime() return 0 end                         -- a zero inside every envelope
C_Timer = { After = function() end, NewTicker = function() end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
local sent = {}
BRutus.CommSystem.SendMessage = function(_, t, data) sent[#sent + 1] = { t = t, data = data } end
BRutus.db = { sync = {} }
BRutus.SyncService:Initialize()
local id = BRutus.SyncService:Publish("bulletin", "snapshot", { count = 0 }, { rev = 0 })
check(id ~= nil and #sent == 1 and sent[1].data ~= "theirs", "a SyncService envelope with zeros in it goes out, serialized by ours")
local okEnv, env = ours:Deserialize(sent[1].data)
check(okEnv and env.dom == "bulletin" and env.data.count == 0 and env.rev == 0, "and reads back whole")

-- The call in the player's stack trace: a member's broadcast, zeros and all.
BRutus.DataCollector = { CollectMyData = function() end,
  GetBroadcastData = function() return { name = "Chehul Costa", level = 60, avgIlvl = 0, gold = 0,
                                         professions = { { name = "Mining", rank = 0, maxRank = 300 } } } end }
sent = {}
local okB, errB = pcall(BRutus.CommSystem.BroadcastMyData, BRutus.CommSystem, true)
check(okB and #sent == 1 and sent[1].t == "BC", "BroadcastMyData sends a member's data with zeros in it (" .. tostring(errB) .. ")")
local okRead, data = ours:Deserialize(sent[1].data)
check(okRead and data.avgIlvl == 0 and data.professions[1].rank == 0 and data.name == "Chehul Costa",
  "and the broadcast reads back whole")

-- No Guild OS file reaches for the shared name.
local function read(path)
  local f = io.open(ADDON .. "/" .. path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local toc = assert(read("GuildOS.toc"))
local scanned = 0
for line in toc:gmatch("[^\r\n]+") do
  local path = line:match("^%s*([%w_\\/%.%-]+%.lua)%s*$")
  if path and not path:find("^Libs") then
    local src = read(path:gsub("\\", "/"))
    if src then
      scanned = scanned + 1
      check(not src:find('["\']LibSerialize["\']') and not src:find("%[%[LibSerialize%]%]"),
        path .. " never names the shared LibSerialize, by any route")
    end
  end
end
check(scanned > 80, "the scan read the addon's files (" .. scanned .. ")")

-- ── 3. The copy itself never divides by a variable ───────────────────────
-- What broke minor 6 on Forever. A newer copy dropped in here must be checked the same way.
-- One left-to-right pass blanks strings and comments, so neither can hide nor fake an operator.
local function codeOnly(src)
  local out, i, n = {}, 1, #src
  while i <= n do
    local c = src:sub(i, i)
    local lb = src:match("^%[(=*)%[", i)
    if src:sub(i, i + 1) == "--" then
      local eq = src:match("^%-%-%[(=*)%[", i)
      if eq then
        local _, e = src:find("%]" .. eq .. "%]", i)
        i = (e or n) + 1
      else
        local e = src:find("\n", i, true)
        i = e or n + 1
      end
      out[#out + 1] = " "
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n and src:sub(j, j) ~= c do
        if src:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      out[#out + 1] = '""'
      i = j + 1
    elseif lb then
      local _, e = src:find("%]" .. lb .. "%]", i)
      out[#out + 1] = '""'
      i = (e or n) + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end
-- Every / and % followed by a nonzero numeric literal; anything else could be a zero.
local function riskyOps(src)
  local hits = {}
  for op, rhs in codeOnly(src):gmatch("([/%%])%s*([^\n]*)") do
    local k = tonumber(rhs:match("^[%w%.]+") or "")
    if not k or k == 0 then hits[#hits + 1] = op .. " " .. rhs:sub(1, 30) end
  end
  return hits
end
for _, form in ipairs({ "x = 1 / num", "x = 1/num", "x = 1 / -num", "x = 1 /-(num)", "x = num / 0", "x = num / 0.0",
                        "x = num / 0x0", "x = 1 % num", "x = 0.0/0.0", "x = 1 / t.n", "x = 1 /\n num" }) do
  check(#riskyOps(form) == 1, "the scan catches `" .. form:gsub("\n", " ") .. "`")
end
for _, safe in ipairs({ 'x = "a / b"', "x = [[a / b]]", "-- a / b", 'x = "--" .. y / 2', "x = y / 256", "x = y % 0x10" }) do
  check(#riskyOps(safe) == 0, "and leaves `" .. safe .. "` alone")
end
local lib = assert(read("Libs/LibSerialize.lua"))
local risky = riskyOps(lib)
check(#risky == 0, "the bundled LibSerialize divides and takes modulo only by nonzero constants (" .. (risky[1] or "") .. ")")

print(("libserialize-private: %d checks passed"):format(checks))
