-- Who creates calendar events, and the dungeon's five (issue #283), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua, Modules/SyncService.lua and Modules/Calendar.lua.
--
-- Only an officer could create an event, and the guild's other clients dropped any event write that
-- did not come from one. The guild now says which ranks create events, stamped and published like the
-- officer threshold, and a creator who is not an officer writes only their own events. A dungeon is a
-- party of five, which the raid sizes never offered.
--
--   luajit -e 'ADDON="."' tools/event-ranks.lua
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
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
local now = 1000000
function GetServerTime() return now end
function GetTime() return 1 end
local afters, tickers = {}, {}
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function(every, fn) tickers[every] = fn; return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}

-- The guild. Who "I" am changes between the officer who sends and the member who receives.
local ROSTER = { { "Off", 1 }, { "Alt", 2 }, { "Mem", 5 }, { "Off2", 1 } }
local me = "Off"
function UnitName() return me end
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2] end end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
end

-- The wire: serialized tables are kept by key, and the encoding hands strings back as is.
local registry, store, n = {}, {}, 0
LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, store[s] end return false end
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
local CS, SS = GuildOS.CommSystem, GuildOS.SyncService
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end

local function client(who)
  me = who
  GuildOS.db = { settings = { officerMaxRank = 1 } }
  SS:Initialize()
  sent = {}
end
local function deliver(msg, sender, channel)
  CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, channel or "GUILD", sender)
end

function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
dofile(ADDON .. "/Modules/Calendar.lua")
local Cal = GuildOS.Calendar

-- ── 1. A dungeon is five ─────────────────────────────────────────────────
local raid = { 10, 20, 40 }
check(#Cal.SizesFor("DUNGEON", raid) == 1 and Cal.SizesFor("DUNGEON", raid)[1] == 5, "a dungeon offers five, and only five")
check(Cal.SizesFor("RAID", raid) == raid and Cal.SizesFor("PVP", raid) == raid, "every other kind keeps the game's raid sizes")

-- ── 2. The ranks that create events: the officers by default, the guild's ───
client("Off")
check(GuildOS:EventMaxRank() == 1 and not GuildOS:MayCreateEventsByName("Mem"), "by default the officers alone create events")
GuildOS.db.settings.officerMaxRank, GuildOS.db.settings.eventMaxRank = 3, 1
check(GuildOS:EventMaxRank() == 3, "never fewer ranks than the officers")
GuildOS.db.settings.officerMaxRank, GuildOS.db.settings.eventMaxRank = 1, nil
check(GuildOS:SetEventMaxRank(5) and GuildOS.db.settings.eventMaxRank == 5 and GuildOS.db.settings.eventMaxRankAt == now,
  "an officer's change is taken at once, stamped")
check(#sent == 1 and sent[1].t == "SV" and sent[1].target == nil, "and published to the guild")
local change = sent[1]

client("Mem")
check(not GuildOS:MayCreateEvents(), "before the change arrives, a rank 5 member creates nothing")
deliver(change, "Off")
check(GuildOS:MayCreateEvents() and GuildOS:MayCreateEventsByName("Mem"), "after it, rank 5 creates events")
check(not GuildOS:IsOfficer(), "and is no officer for it")
check(not GuildOS:SetEventMaxRank(9), "a member cannot change it")
local forged = { v = 2, id = "f1", dom = "guildcfg", act = "events", data = { max = 9 }, rev = now + 1 }
check(not SS:Validate(forged, "Mem", "GUILD"), "a member's own guildcfg is dropped")

-- ── 3. The wire takes a creator's event writes, over GUILD only ─────────────
local function env(act) return { v = 2, id = act .. "1", dom = "event", act = act, data = {} } end
check(SS:Validate(env("create"), "Mem", "GUILD") and SS:Validate(env("cancel"), "Mem", "GUILD"), "a creator's create and cancel go through")
check(not SS:Validate(env("create"), "Mem", "WHISPER"), "only over GUILD")
check(not SS:Validate(env("allyRsvp"), "Mem", "GUILD"), "seating an allied player stays an officer's")
GuildOS.db.settings.eventMaxRank = nil
check(not SS:Validate(env("create"), "Mem", "GUILD"), "with the officers alone, a member's event is dropped again")

-- ── 4. A creator writes only their own events ───────────────────────────
check(Cal.MayWriteRemote(nil, { author = "Mem" }, "Mem-Realm", false), "a creator's new event, under their own name")
check(not Cal.MayWriteRemote(nil, { author = "Off" }, "Mem-Realm", false), "never under somebody else's")
check(Cal.MayWriteRemote({ author = "Mem" }, nil, "Mem-Realm", false), "their own event: changed, cancelled, deleted")
check(not Cal.MayWriteRemote({ author = "Off" }, { author = "Mem" }, "Mem-Realm", false), "never an officer's event")
check(not Cal.MayWriteRemote({ id = "web:abc", author = "Mem" }, nil, "Mem-Realm", false), "never a raid from the site")
check(Cal.MayWriteRemote({ author = "Off" }, nil, "Off2-Realm", true), "an officer writes any event")

print(string.format("event-ranks: %d checks passed", checks))
