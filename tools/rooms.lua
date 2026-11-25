-- The rooms (specs/salao, #445): UI/Rooms.lua's lookups over the real feature list (UI/Features.lua),
-- under a stub client. Every tab feature lands in a room; a tab another addon registers falls in the
-- Salão; a deep link finds the room that holds the feature and its sub-tab; the Officers' Room is never
-- a member's; a room with nothing to open is not drawn.
--
--   luajit -e 'ADDON="."' tools/rooms.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
local checks, fails = 0, {}
local function check(cond, what)
  checks = checks + 1
  if not cond then fails[#fails + 1] = what end
end

local officer, disabled, absent = true, {}, {}
GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  UI = {},
  Client = { isAnniversary = false, isRetail = false },
}
function GuildOS:Print() end
function GuildOS:IsOfficer() return officer end
function GuildOS:IsFeatureEnabled(id) return not disabled[id] end
function GuildOS:FeatureStartFailed() return false end
function GuildOS:LootSystemShowsDKP() return true end
function GuildOS:LootSystemShowsWishlist() return true end
GuildOS.GuildBank = { Available = function() return true end }
GuildOS.WinterVeil = { Event = function() if absent.veil then return nil end return {} end }
GuildOS.Alliance = { Get = function() return {} end }

dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Rooms.lua")
dofile(ADDON .. "/UI/Features.lua")
local UI = GuildOS.UI

local function ids(list)
  local out = {}
  for _, x in ipairs(list) do out[#out + 1] = x.id end
  return table.concat(out, ",")
end

-- ── 1. Every tab feature has a room ─────────────────────────────────────
local lost = {}
for _, id in ipairs(UI.featureOrder) do
  local def = UI.features[id]
  if def.tab and not UI:RoomOf(id) then lost[#lost + 1] = id end
end
check(#lost == 0, "every tab feature lands in a room: " .. table.concat(lost, ","))
check(ids(UI:VisibleRooms()) == "salao,raids,members,loot,workshop,chronicle,officers",
  "an officer on WoW: Forever sees the seven rooms, in order: " .. ids(UI:VisibleRooms()))
for _, r in ipairs(UI:VisibleRooms()) do check(not r.gear, "the gear's room is never on the bar") end

-- ── 2. Deep links ──────────────────────────────────────────────────────
local room, entry = UI:RoomOf("guild", "calendar")
check(room and room.id == "raids" and entry.sub == "calendar", "the calendar lives in Raids")
room, entry = UI:RoomOf("guild", "bulletin")
check(room.id == "salao" and entry.id == "bulletin", "the notices in the Salão")
room, entry = UI:RoomOf("guild", "achievements")
check(room.id == "chronicle" and entry.id == "achievements", "the achievements in the Chronicle")
room, entry = UI:RoomOf("guild")
check(room.id == "chronicle" and entry.sub == "achievements", "Guild by name opens where it did: Achievements on Forever")
GuildOS.Client.isAnniversary = true
room, entry = UI:RoomOf("guild")
check(room.id == "raids" and entry.sub == "calendar", "and the calendar where there are no achievements")
check(not UI:EntryAllowed(UI:RoomEntries("chronicle", true)[1]), "Anniversary has no Achievements entry")
check(ids(UI:RoomEntries("chronicle")) == "activity", "so its Chronicle holds the activity alone")
GuildOS.Client.isAnniversary = false
room = UI:RoomOf("management", "inactive")
check(room.id == "officers", "Leadership's sub-tabs are the Officers' Room's")
room = UI:RoomOf("settings")
check(room.id == "settings" and room.gear, "Settings is behind the gear")
check(UI:RoomOf("nope") == nil and UI:RoomOf(nil) == nil, "nothing for a feature no room holds")

-- ── 3. The Officers' Room is never a member's ──────────────────────────
officer = false
check(not UI:RoomAllowed("officers"), "a member has no Officers' Room")
check(not ids(UI:VisibleRooms()):find("officers", 1, true), "nor on the bar")
check(UI:RoomOf("management") == nil, "and a deep link to Leadership finds no room")
room, entry = UI:RoomOf("recruitment")
check(room.id == "salao" and entry.members, "a member's Recruitment is the Salão's read-only entry")
officer = true
room, entry = UI:RoomOf("recruitment")
check(room.id == "officers" and not entry.members, "an officer's is the Officers' Room's")
check(not UI:EntryAllowed({ feature = "recruitment", members = true }), "and the members' entry is not an officer's")

-- ── 4. A room with nothing to open is not drawn ────────────────────────
disabled.roster = true
check(not UI:RoomAllowed("members") and not ids(UI:VisibleRooms()):find("members", 1, true),
  "Members switched off: no Members room")
disabled.roster = nil
absent.veil = true
check(not ids(UI:RoomEntries("salao")):find("veil", 1, true), "no Winter Veil event: no Secret Santa entry")
absent.veil = nil
check(ids(UI:RoomEntries("salao")):find("veil", 1, true), "an event on: Secret Santa is a Salão entry")
local saved = UI:RoomDefault("raids", "groups")
check(saved.id == "groups", "a room opens on the entry it was left on")
check(UI:RoomDefault("raids", "gone").id == "calendar", "else on its first")

-- ── 5. Another addon's tab ─────────────────────────────────────────────
UI:RegisterFeature({ id = "extra", label = "Extra", build = function() end })
room, entry = UI:RoomOf("extra")
check(room and room.id == "salao" and entry.feature == "extra", "a tab no room names is a Salão entry")
check(ids(UI:RoomEntries("salao")):find("x:extra", 1, true), "listed after the Salão's own")

-- ── 6. An entry the window built no panel for ──────────────────────────
function UI:HasPanel(id) return id ~= "groups" end
check(ids(UI:RoomEntries("raids")) == "calendar,raids", "an entry with no panel is not offered")
check(UI:RoomDefault("raids", "groups").id == "calendar", "nor opened, even when it was saved")
function UI:HasPanel(id) return id == "groups" end
check(not UI:RoomAllowed("members"), "a room whose entries have no panel is not drawn")
UI.HasPanel = nil

if #fails > 0 then
  for _, f in ipairs(fails) do print("FAIL: " .. f) end
  os.exit(1)
end
print(("rooms: %d checks passed"):format(checks))
