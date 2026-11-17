-- A clear on its way to the guild (issue #327), run against the real Libs/ChatThrottleLib.lua,
-- Libs/LibSerialize.lua, Libs/LibDeflate.lua, Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/SyncService.lua, Modules/CommSystem.lua, Modules/Journal.lua, Data/ForeverDungeons.lua and
-- Modules/DungeonLog.lua, on a clock the harness turns.
--
-- Chuleta Maximus cleared Excavation Site with three guildmates. His client wrote the clear down, and
-- the officer's client took it when it came, yet it came fifteen hours and three of his sessions later:
-- the officer was online at the clear and stored Chuleta's member data in two sessions without it. His
-- member data reached the officer six to eighteen minutes after it was collected (one guildmate's
-- forty-nine), where most of the guild's arrives inside five seconds: GuildOS's one BULK pipe in
-- ChatThrottleLib ran that far behind on his client, the clear queued at its end, and whatever is
-- queued at a logout or a /reload is gone. Member data is sent again every five minutes and asked for
-- every ten; a journal entry went once when written and once at the next login, so one lost message
-- kept it from the guild until a login of his met the officer online.
--
-- What this holds: a clear leaves its client ahead of member data waiting in the queue, and a client
-- keeps telling the guild its own week while it is online, so an officer who was not there for it,
-- or for whom it was lost, gets it without waiting for another login.
--
--   luajit -e 'ADDON="."' tools/journal-delivery.lua
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

-- ── The clock, the timers, the wire ─────────────────────────────────────
local BASE = 1794445000
math.randomseed(327)   -- message ids: the same run every time
local clock = 0
local timers = {}
local wire = {}

function GetTime() return clock end
function GetServerTime() return BASE + math.floor(clock) end
time = function() return BASE + math.floor(clock) end
function GetFramerate() return 60 end
function securecallfunction(fn, ...) return fn(...) end
function geterrorhandler() return function(err) error(err, 0) end end
function hooksecurefunc() end
function CreateFrame()
  local f = { scripts = {}, shown = true }
  function f:RegisterEvent() end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  return f
end
C_Timer = {
  After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end,
  NewTicker = function(every, fn)
    local t = { at = clock + every, every = every, fn = fn }
    timers[#timers + 1] = t
    return { Cancel = function() t.cancelled = true end }
  end,
}
C_ChatInfo = {
  SendAddonMessage = function(prefix, text, channel)
    wire[#wire + 1] = { prefix = prefix, text = text, channel = channel, at = clock }
    return 0
  end,
  RegisterAddonMessagePrefix = function() return true end,
}
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9 } }

-- ── WoW: Forever, Chuleta's client ──────────────────────────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Chuleta", "Maximus" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function UnitClass() return "Druid", "DRUID" end
function GetRealmName() return "CAMWOW US2 Realm 5 PvE" end
function GetNormalizedRealmName() return "CAMWOW US2 Realm 5 PvE" end
function IsInGuild() return true end
function GetGuildInfo() return "Filhos da Horda" end
local where = { type = "none", id = 0 }
function GetInstanceInfo() return "x", where.type, 1, "Normal", 5, 0, false, where.id end

local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) return registry[n] end })
dofile(ADDON .. "/Libs/ChatThrottleLib.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test", PREFIX = "GUILDOS" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/Journal.lua")
dofile(ADDON .. "/Data/ForeverDungeons.lua")
dofile(ADDON .. "/Modules/DungeonLog.lua")
local G, CTL = GuildOS, ChatThrottleLib
G.IsOnGuildDB = function() return true end
local LD, LS = LibStub("LibDeflate"), LibStub("GuildOS-LibSerialize")

-- Turns the clock: the timers due, in the order they were set, then ChatThrottleLib's OnUpdate.
local function run(seconds)
  local stop = clock + seconds
  while clock < stop do
    clock = clock + 0.1
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
      if not t.cancelled then
        if t.at <= clock then
          due[#due + 1] = t
          if t.every then t.at = t.at + t.every; keep[#keep + 1] = t end
        else
          keep[#keep + 1] = t
        end
      end
    end
    timers = keep
    for _, t in ipairs(due) do t.fn() end
    if CTL.Frame.shown then CTL.Frame.scripts.OnUpdate(CTL.Frame, 0.1) end
  end
end

-- Every sync envelope that crossed the wire from message `from` on, reassembled as a receiver would.
local function envelopes(from)
  local out, parts = {}, {}
  for i = from or 1, #wire do
    local text, encoded = wire[i].text, nil
    if text:sub(1, 2) == "S:" then
      encoded = text:sub(3)
    else
      local id, idx, total, chunk = text:match("^M:(%x+):(%d+):(%d+):(.+)$")
      parts[id] = parts[id] or { n = 0 }
      parts[id][tonumber(idx)] = chunk
      parts[id].n = parts[id].n + 1
      if parts[id].n == tonumber(total) then encoded = table.concat(parts[id]); parts[id] = nil end
    end
    local decoded = encoded and LD:DecodeForWoWAddonChannel(encoded)
    local raw = decoded and LD:DecompressDeflate(decoded)
    local body = raw and raw:match("^SV:(.*)$")
    if body then
      local ok, env = LS:Deserialize(body)
      if ok then out[#out + 1] = env end
    end
  end
  return out
end

-- Whether entry `id` went out to the guild from message `from` on.
local function carried(id, from)
  for _, env in ipairs(envelopes(from)) do
    if env.dom == "journal" then
      for _, e in ipairs(env.act == "add" and { env.data.entry } or env.data.entries or {}) do
        if e.id == id then return true end
      end
    end
  end
  return false
end

local function journalSent(from)
  for _, env in ipairs(envelopes(from)) do
    if env.dom == "journal" then return true end
  end
  return false
end

-- ── The login ───────────────────────────────────────────────────────────
G.db = { members = {}, settings = {}, profile = {} }
G.SyncService:Initialize()
G.Journal:Initialize()
G.DungeonLog:Initialize()
run(60)
check(not journalSent(), "a client with nothing of its own this week says nothing at login")

-- ── Member data owed to the guild: a queue minutes deep ─────────────────
-- Forty broadcasts' worth, about 135 seconds at ChatThrottleLib's 800 bytes a second: less than the
-- six to forty-nine minutes the officer's saved variables show for these clients.
local seed = 7
local function noise(n)
  local b = {}
  for i = 1, n do
    seed = (seed * 1103515245 + 12345) % 2147483648
    b[i] = string.char(33 + seed % 90)
  end
  return table.concat(b)
end
for _ = 1, 40 do G.CommSystem:SendMessage(G.CommSystem.MSG_TYPES.BROADCAST, noise(2000)) end
run(5)

-- ── Excavation Site: Wetlands, three bosses, the last one falls ─────────
where.type, where.id = "party", 2998
G.DungeonLog:OnZone(GetServerTime())
for _, boss in ipairs({ 3480, 3481 }) do G.DungeonLog:OnEncounterEnd(boss, 1) end
local from = #wire + 1
check(G.DungeonLog:OnEncounterEnd(3482, 1) == true, "the final boss is the clear")
local clear = G.db.journal.entries[#G.db.journal.entries]
check(clear and clear.type == "dungeon.clear" and clear.subjectKey == "Chuleta Maximus-CAMWOW US2 Realm 5 PvE",
  "the clear is written down, Chuleta's, under the key the guild has for him")

-- He hearths and logs out half a minute later: what is still queued then never goes.
run(30)
check(CTL.Prio.BULK.Ring.pos ~= nil, "member data is still queued at the logout, as the officer's file shows for him")
check(carried(clear.id, from), "the clear leaves the client before a logout 30 seconds after the boss, ahead of the member data queued before it")

-- ── An officer who was not there for it ─────────────────────────────────
-- He stays instead, and an officer logs in a few minutes after the clear: the add went to nobody who
-- uploads. Member data reaches that officer inside ten minutes, by the ticker and the requests.
run(300)
local officerOnline = #wire + 1
run(15 * 60)
check(carried(clear.id, officerOnline), "an officer online for fifteen minutes after the clear gets it, with no new login")

-- The next login says it again, as it always did, and a week later it is no longer said.
local nextLogin = #wire + 1
G.Journal:Snap()
run(5)
check(carried(clear.id, nextLogin), "the next login's snapshot carries the week")
clock = clock + 8 * 86400
local weekLater = #wire + 1
run(15 * 60)
check(not journalSent(weekLater), "past a week nothing of it is said again")

print(("journal-delivery: %d checks passed"):format(checks))
