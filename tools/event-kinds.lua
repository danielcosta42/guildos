-- Which kinds of event the ranks below the officers create, and the dungeon's list (issue #308), run against
-- the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua, Modules/SyncService.lua,
-- Modules/Calendar.lua and Data/ForeverDungeons.lua.
--
-- Since #283 the guild chooses which ranks create events, but not which kinds: a member who may set up a
-- dungeon run may set up a raid. The officers now tick the kinds those ranks create, stamped and published
-- on guildcfg as the ranks are, held when an event is made here and again when one arrives. Unset, every
-- kind, and a client before this never hears it: it goes on taking every kind, as it did. A Dungeon event
-- picks its dungeon from the game's list, guildos.me's own.
--
--   luajit -e 'ADDON="."' tools/event-kinds.lua
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
local function read(path)
  local f = io.open(ADDON .. "/" .. path, "rb")
  if not f then return "" end
  local s = f:read("*a")
  f:close()
  return s
end

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
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
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function UnitClass() return "Mage", "MAGE" end

-- The guild: two officers, an Alt rank and a Member rank. Who "I" am changes between sender and receiver.
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
dofile(ADDON .. "/Modules/Calendar.lua")
local CS, SS, Cal = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.Calendar
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end

-- A client of the guild where Member and above create events (#283).
local function client(who)
  me = who
  GuildOS.db = { settings = { officerMaxRank = 1, eventMaxRank = 5, eventMaxRankAt = 1 } }
  SS:Initialize()
  Cal:Initialize()
  sent, printed = {}, {}
end
local function deliver(msg, sender)
  CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, "GUILD", sender)
end
local function envOf(msg) return store[msg.data] end
local function same(a, b) return table.concat(a or { "nil" }, ",") == table.concat(b or { "nil" }, ",") end
local function said(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return true end end
  return false
end
local s = function() return GuildOS.db.settings end

-- ── 1. Unset: every kind, as before #308 ─────────────────────────────────
client("Mem")
check(Cal:MemberKinds() == nil and Cal:KindOpenToMembers("RAID") and Cal:MayCreateKind("PVP"),
  "with nothing chosen, a rank that creates events creates every kind")
check(#Cal:CreatableKinds() == #Cal.KINDS, "and the editor offers all six")
client("Alt")
s().eventMaxRank = 1
check(#Cal:CreatableKinds() == 0 and not Cal:MayCreateKind("SOCIAL"), "a rank that creates no events creates no kind")

-- ── 2. An officer's choice: cleaned, stamped, sent with no `max` ─────────────
client("Off")
check(Cal:SetMemberKinds({ "SOCIAL", "DUNGEON", "DUNGEON", "BOGUS", 7 }), "an officer chooses the kinds")
check(same(s().eventKinds, { "DUNGEON", "SOCIAL" }) and s().eventKindsAt == now, "known kinds once each, in order, stamped")
check(#sent == 1 and sent[1].t == "SV" and sent[1].target == nil, "and published to the guild")
local change = sent[1]
local cenv = envOf(change)
check(cenv.dom == "guildcfg" and cenv.act == "eventkinds" and same(cenv.data.kinds, { "DUNGEON", "SOCIAL" }) and cenv.rev == now,
  "on guildcfg, as eventkinds, with its stamp")
check(cenv.data.max == nil, "carrying no max")
-- A client before this reads an unknown guildcfg action as the officer threshold: with no max, nothing.
GuildOS:OnOfficerMaxRankSync(cenv)
check(s().officerMaxRank == 1 and s().officerMaxRankAt == nil, "a client before #308 takes no officer threshold from it")
check(Cal:MayCreateKind("RAID") and #Cal:CreatableKinds() == 6, "the officers still create every kind")
check(Cal:SetMemberKinds({}) and same(s().eventKinds, {}) and s().eventKindsAt == now + 1,
  "none ticked is a choice too, and a second change in the same second stamps past the first")
check(not Cal:SetMemberKinds("RAID"), "a list or nothing")

-- ── 3. Held here: a member creates only an open kind ───────────────────────
client("Mem")
deliver(change, "Off")
check(same(s().eventKinds, { "DUNGEON", "SOCIAL" }) and s().eventKindsAt == now, "the member's client takes the officer's choice")
check(not Cal:MayCreateKind("RAID") and Cal:MayCreateKind("DUNGEON") and same(Cal:CreatableKinds(), { "DUNGEON", "SOCIAL" }),
  "and creates a dungeon or a social night, no raid")
check(Cal:Create("Kara", now + 3600, 10, "", "RAID") == nil and #sent == 0 and said("cannot create this type of event"),
  "a raid is refused before it is sent, with the reason")
check(Cal:Create("Old", now + 3600, 10, "") == nil, "an event with no kind is a raid, refused too")
check(Cal:CreateSeries("Kara", now + 3600, 10, "", "RAID", false, "weekly") == nil and #sent == 0, "a weekly raid too")
local run = Cal:Create("Ruins of Lordaeron", now + 3600, 5, "", "DUNGEON")
check(run and #sent == 1 and envOf(sent[1]).act == "create", "a dungeon run goes out")
local runMsg = sent[1]
sent, printed = {}, {}
check(Cal:Update(run.id, "Kara", run.when, 10, "", "RAID") == nil and #sent == 0 and Cal:GetEvents()[run.id].kind == "DUNGEON",
  "and cannot be made a raid afterwards")
check(Cal:Update(run.id, "Ruins", run.when, 5, "", "DUNGEON") and #sent == 1, "it changes as a dungeon")

-- ── 4. Held on receipt ────────────────────────────────────────────────────
-- A member's raid, from a client that never heard the choice (one before #308 sends the same).
client("Mem")
local raid = Cal:Create("Karazhan", now + 7200, 10, "", "RAID")
local raidMsg = sent[1]
check(raid and raidMsg, "a client that heard nothing still sends a member's raid")
client("Off")
local bwl = Cal:Create("BWL", now + 9000, 20, "", "RAID")
local bwlMsg = sent[1]

client("Alt")
deliver(raidMsg, "Mem")
check(Cal:GetEvents()[raid.id] ~= nil, "before the choice, a member's raid is taken, as before #308")
deliver(change, "Off")
client("Alt")
deliver(change, "Off")
deliver(raidMsg, "Mem")
check(Cal:GetEvents()[raid.id] == nil, "after it, a member's raid is dropped")
deliver(runMsg, "Mem")
check(Cal:GetEvents()[run.id] ~= nil and Cal:GetEvents()[run.id].kind == "DUNGEON", "their dungeon run is taken")
deliver(bwlMsg, "Off")
check(Cal:GetEvents()[bwl.id] ~= nil, "an officer's raid is taken whatever is ticked")

-- Their own event of a kind now closed: cancelled and deleted as before, never changed into another.
client("Alt")
deliver(raidMsg, "Mem")
deliver(change, "Off")
me = "Mem"
SS:Publish("event", "update", { event = { id = raid.id, title = "Kara 2", when = raid.when, size = 10, kind = "RAID", author = "Mem" } }, { rev = 50 })
SS:Publish("event", "cancel", { id = raid.id }, { rev = 51 })
me = "Alt"
local upd, cancel = sent[#sent - 1], sent[#sent]
deliver(upd, "Mem")
check(Cal:GetEvents()[raid.id].title == "Karazhan", "a member's edit of their own raid, now closed to them, is dropped")
deliver(cancel, "Mem")
check(Cal:GetEvents()[raid.id].canceled == true, "and cancelling it is still theirs")

-- ── 5. Newest wins; two in one second settle on the fewer kinds ─────────────
local function kindsEnv(kinds, rev) return { v = 2, id = "k" .. tostring(rev), dom = "guildcfg", act = "eventkinds", data = { kinds = kinds }, rev = rev } end
client("Alt")
Cal:OnMemberKindsSync(kindsEnv({ "RAID", "DUNGEON" }, 2000))
check(same(s().eventKinds, { "RAID", "DUNGEON" }) and s().eventKindsAt == 2000, "the first choice heard is taken")
Cal:OnMemberKindsSync(kindsEnv({ "PVP" }, 1500))
check(same(s().eventKinds, { "RAID", "DUNGEON" }), "an older one is not")
Cal:OnMemberKindsSync(kindsEnv({ "RAID", "DUNGEON", "PVP" }, 2000))
check(same(s().eventKinds, { "RAID", "DUNGEON" }), "the same second with more kinds is not")
Cal:OnMemberKindsSync(kindsEnv({ "SOCIAL" }, 2000))
check(same(s().eventKinds, { "SOCIAL" }), "the same second with fewer is")
local function settle(first, second)
  client("Alt")
  Cal:OnMemberKindsSync(kindsEnv(first, 3000))
  Cal:OnMemberKindsSync(kindsEnv(second, 3000))
  return table.concat(s().eventKinds, ",")
end
check(settle({ "FARM" }, { "SOCIAL" }) == "FARM" and settle({ "SOCIAL" }, { "FARM" }) == "FARM",
  "as many in the same second: the same one on every client, whatever the order")
-- The rule is the text, not the KINDS order (where RAID comes first): DUNGEON sorts before RAID.
check(settle({ "RAID" }, { "DUNGEON" }) == "DUNGEON" and settle({ "DUNGEON" }, { "RAID" }) == "DUNGEON",
  "the list that sorts first as text wins")
client("Alt")
Cal:OnMemberKindsSync(kindsEnv({ "PVP", "NEWKIND" }, 4000))
check(same(s().eventKinds, { "PVP" }), "a kind this client does not know is left out")
Cal:OnMemberKindsSync(kindsEnv("RAID", 5000))
Cal:OnMemberKindsSync({ v = 2, id = "x", dom = "guildcfg", act = "eventkinds", data = { kinds = { "RAID" } }, rev = 0 / 0 })
Cal:OnMemberKindsSync({ v = 2, id = "y", dom = "guildcfg", act = "eventkinds", data = { kinds = { "RAID" } } })
check(same(s().eventKinds, { "PVP" }) and s().eventKindsAt == 4000, "no list, no stamp or NaN: nothing")
Cal:OnMemberKindsSync(kindsEnv({ "RAID" }, now + 1e6))
check(s().eventKindsAt == now + 300, "a stamp from the future is held to five minutes ahead")
Cal:OnMemberKindsSync(kindsEnv({}, now + 400))
check(same(s().eventKinds, {}) and #Cal:CreatableKinds() == 0, "with none open, a member creates nothing")

-- ── 6. Only an officer changes it, over GUILD ───────────────────────────────
client("Mem")
check(not Cal:SetMemberKinds({ "RAID" }) and s().eventKinds == nil and #sent == 0, "a member cannot change it")
check(not SS:Validate(kindsEnv({ "RAID" }, now + 1), "Mem", "GUILD"), "a member's own eventkinds is dropped")
check(not SS:Validate(kindsEnv({ "RAID" }, now + 1), "Off", "WHISPER"), "an officer's counts over GUILD only")
check(SS:Validate(kindsEnv({ "RAID" }, now + 1), "Off", "GUILD"), "and is taken there")

-- ── 7. Re-sent with the ranks, and only a choice somebody made ──────────────
client("Off")
Cal:PublishMemberKinds()
check(#sent == 0, "a guild that never chose sends nothing")
Cal:SetMemberKinds({ "DUNGEON" })
sent = {}
Cal:PublishMemberKinds()
check(#sent == 1 and envOf(sent[1]).rev == s().eventKindsAt and same(envOf(sent[1]).data.kinds, { "DUNGEON" }),
  "an officer re-sends the guild's choice with its own stamp")
me = "Mem"
sent = {}
Cal:PublishMemberKinds()
check(#sent == 0, "a member never sends it")
local _, resends = read("Modules/CommSystem.lua"):gsub("GuildOS%.Calendar:PublishMemberKinds%(%)", "")
check(resends == 2, "on the officers' regular sync and in their answer to a request, next to the ranks")

-- ── 8. The dungeon's list ───────────────────────────────────────────────────
check(GuildOS.ForeverDungeons == nil and #Cal:DungeonChoices() == 0, "on TBC Anniversary there is no list: the title is typed")
GuildOS.Client.isAnniversary, GuildOS.Client.isRetail = false, false
dofile(ADDON .. "/Data/ForeverDungeons.lua")
local list = Cal:DungeonChoices()
check(same({ list[1], list[2], list[3], list[4] },
  { "City of Dalaran", "Excavation Site: Wetlands", "Ruins of Lordaeron", "The Hall of Thanes" }),
  "on WoW: Forever the game's own dungeons come first, by name")
for _, name in ipairs(list) do check(name ~= "Manor Mistmantle", "a map with no boss to clear is no night to book") end
check(#list == 16 and list[5] == "Scholomance" and list[16] == "The Deadmines",
  "then the classic ones, as guildos.me offers them (#491)")
local panel = read("UI/CalendarPanel.lua")
check(panel:find("CAL():DungeonChoices()", 1, true) and panel:find('L["Other (type a name)"]', 1, true),
  "the editor's picker is that list and Other, typed")
check(panel:find("CAL():MayCreateKind(p.kind)", 1, true) and panel:find("CAL():CreatableKinds()", 1, true),
  "and its kinds are the ones this rank creates")

print(string.format("event-kinds: %d checks passed", checks))
