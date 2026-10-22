-- A raid planned on the website, from the companion's inbox to the guild calendar (#146), run
-- against the real CompanionImport and Calendar under stubbed WoW APIs.
--
-- Two players reported the same hole from two sides: the site's raids never showed on the addon's
-- calendar, and nobody could see in game who had signed up. A raid nobody had answered yet was
-- refused as "nobody in it" before it reached the calendar, and the calendar drew the game's own
-- RSVP list for it, a second list that stayed empty and never reached the site. This proves the
-- unanswered raid lands, the site's answers travel with the event to every client, cleaned on the
-- way in, and that they are what the event counts.
--
--   luajit -e 'ADDON="."' tools/web-raid-calendar.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
package.path = ADDON .. "/?.lua;" .. package.path

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── WoW API surface ───────────────────────────────────────────────────
local NOW = 1760000000
function GetServerTime() return NOW end
function IsInGuild() return true end
function GetRealmName() return "Firemaw" end
function UnitName() return "Chehul" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function() end }
end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
  minor = 1,
}, {
  __call = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
})

GuildOS = {
  VERSION = "0.78.0",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true }, calendar = { events = {}, deleted = {} } },
  Client = { isAnniversary = true, defaultRaidSize = 25 },
  Compat = { PlayerName = function() return "Chehul" end },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
function GuildOS:Print() end
local officer = true
function GuildOS:IsOfficer() return officer end
dofile(ADDON .. "/Core/Utils.lua")

-- What went out on the guild channel, and the revisions the calendar asked for.
local published = {}
GuildOS.SyncService = {
  NextRevision = function() return #published + 1 end,
  Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end,
  ShouldApply = function() return true end,
  SetRevision = function() end,
}

dofile(ADDON .. "/Libs/LibDeflate.lua")
local LibDeflate = LibStub("LibDeflate")   -- the JSON decoder is Core/Utils.lua's (issue #182)

dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/Calendar.lua")
local Import, Cal = GuildOS.CompanionImport, GuildOS.Calendar

-- A roster the way the site writes it: JSON, deflated, printable.
local function wire(t)
  return "GOSROST1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
local function raid(id, signups, startsAt)
  local members = {}
  for _, s in ipairs(signups) do
    if s.invite then
      members[#members + 1] = { key = s.name .. "-Firemaw", name = s.name, class = s.class, spec = "", slot = s.slot, group = 0 }
    end
  end
  return {
    fmt = "GOSROST1", v = 2, raidId = id, title = "Karazhan " .. id, startsAt = startsAt or NOW + 86400,
    instance = "Karazhan", instanceKey = "kara", size = 10, members = members, signups = signups,
  }
end

-- ── 1. A raid nobody has answered yet reaches the calendar ───────────
local empty = wire(raid("r-empty", {}, NOW + 3600))   -- a leftover on an earlier night
check(Import:Parse(empty) ~= nil, "the inbox reads an unanswered raid")
local n, err = Import:Load(empty)
check(n == nil and err == "That roster has nobody in it.", "pasted by hand, an empty roster is still refused")

local FULL = {
  { name = "Tanky", class = "WARRIOR", slot = "TANK", status = "yes", invite = true },
  { name = "Healz", class = "PRIEST", slot = "HEALER", status = "late", invite = true },
  { name = "Pewpew", class = "MAGE", slot = "RANGED", status = "yes", invite = false, why = "wait", wait = 1 },
  { name = "Maybe", class = "ROGUE", slot = "MELEE", status = "tentative", invite = false, why = "tentative" },
  { name = "Nope", class = "HUNTER", slot = "RANGED", status = "no", invite = false, why = "no" },
  { name = "Refused", class = "MAGE", slot = "RANGED", status = "yes", invite = false, why = "refused" },
  { name = "Pending", class = "DRUID", slot = "HEALER", status = "yes", invite = false, why = "pending" },
  { name = "Unknown", class = "PALADIN", slot = "MELEE", status = "yes", invite = false, why = "unknown" },
}
local answered = wire(raid("r-full", FULL))
GuildOSInbox = { empty, answered }
GuildOSInboxAck = { at = NOW - 600, members = 2 }
check(Import:ConsumeInbox(), "the inbox is taken")
check(Import:Current().raidId == "r-full", "the Web panel acts on the soonest raid somebody answered, not an earlier empty one")
local events = Cal:GetEvents()
check(next(events) == nil, "nothing goes on the calendar before the rank is known")
Import:CalendarFromInbox()
check(events["web:r-empty"] ~= nil, "the unanswered raid is on the calendar")
check(events["web:r-full"] ~= nil, "and so is the answered one")

-- With nobody having answered anything, the Web panel still has a raid: the soonest.
Import._lastInbox = nil
GuildOSInbox = { wire(raid("r-a", {}, NOW + 7200)), wire(raid("r-b", {}, NOW + 3600)) }
Import:ConsumeInbox()
check(Import:Current().raidId == "r-b", "all unanswered: the soonest of all")

-- ── 2. The site's answers travel with the event, grouped as the Discord post groups them ──
local e = events["web:r-full"]
check(Cal:IsWebEvent(e) and not Cal:IsWebEvent({ id = "a1b2" }), "a web raid is told apart by its id")
local by = {}
for _, x in ipairs(e.signups) do by[x.name] = x end
check(by.Tanky and by.Tanky.status == "yes" and by.Tanky.role == "TANK", "coming, with the role")
check(by.Healz and by.Healz.status == "yes" and by.Healz.role == "HEALER", "late is coming")
check(by.Unknown and by.Unknown.status == "yes", "a character no export has confirmed is still coming")
check(by.Pending and by.Pending.status == "pending", "waiting for the officers' approval is its own line")
check(by.Pewpew and by.Pewpew.status == "wait" and by.Pewpew.role == "DPS", "the waitlist is its own line")
check(by.Maybe and by.Maybe.status == "tentative", "tentative")
check(by.Nope and by.Nope.status == "no", "not coming")
check(by.Refused and by.Refused.status == "no", "refused by the officers is out, as the post shows it")
check(e.signupsAt == NOW - 600, "stamped with when the site gave it")
check(#events["web:r-empty"].signups == 0, "an unanswered raid carries an empty list")

local function lastSent(id)
  for i = #published, 1, -1 do
    local ev = published[i].data.event
    if ev and ev.id == id then return ev end
  end
end
local sent = lastSent("web:r-full")
check(sent and #sent.signups == #e.signups and sent.signupsAt == e.signupsAt, "the list goes out with the event, to the whole guild")

-- ── 3. What the event counts is the site's answers, and the allied seats ──
e.rsvps = { x = { status = "yes", role = "TANK" }, y = { status = "yes", role = "TANK", ally = true } }
local comp = Cal:GetComposition(e)
check(comp.yes == 4, "the site's three coming and the allied seat; the game's own RSVP is not counted")
check(comp.pending == 1 and comp.tentative == 1 and comp.no == 2 and comp.wait == 1, "the rest by status")
check(comp.roles.TANK == 2 and comp.roles.HEALER == 1 and comp.roles.DPS == 1, "roles of those coming")
local own = Cal:GetComposition({ id = "abc", rsvps = { x = { status = "yes", role = "TANK" } } })
check(own.yes == 1 and own.roles.TANK == 1, "an event made in game still counts its RSVPs")
e.rsvps = {}

-- ── 4. Forward only: republished when the site said something newer ──
local before = #published
Import._lastInbox = nil
GuildOSInbox = { answered }
Import:ConsumeInbox(); Import:CalendarFromInbox()
check(#published == before, "the same answers publish nothing")
Import._lastInbox = nil
GuildOSInboxAck = { at = NOW - 300, members = 2 }   -- the companion's hourly rewrite, nothing changed
Import:ConsumeInbox(); Import:CalendarFromInbox()
check(#published == before, "the same answers said again later publish nothing either")
check(events["web:r-full"].signupsAt == NOW - 300, "only the time moves, here")

local changed = wire(raid("r-full", { { name = "Tanky", class = "WARRIOR", slot = "TANK", status = "no", invite = false, why = "no" } }))
Import._lastInbox = nil
GuildOSInbox = { changed }
GuildOSInboxAck = { at = NOW - 1200, members = 0 }   -- an old inbox, left behind by a stopped companion
Import:ConsumeInbox(); Import:CalendarFromInbox()
check(#published == before, "an older inbox takes back nobody's answer")
check(#events["web:r-full"].signups == #FULL, "and the list stays as it was")

Import._lastInbox = nil
GuildOSInboxAck = { at = NOW - 60, members = 0 }
Import:ConsumeInbox(); Import:CalendarFromInbox()
check(#published == before + 1, "a newer answer publishes the event again")
check(events["web:r-full"].signups[1].status == "no" and events["web:r-full"].signupsAt == NOW - 60, "with the new answer and its time")

Import._lastInbox = nil
GuildOSInboxAck = { at = NOW + 86400, members = 0 }  -- a PC clock a day ahead
GuildOSInbox = { answered }
Import:ConsumeInbox(); Import:CalendarFromInbox()
check(events["web:r-full"].signupsAt == NOW, "clamped to now: a clock ahead cannot freeze the list")

-- ── 5. What arrives over the guild channel is checked, and also moves forward only ──
local junk = {}
for i = 1, 100 do junk[#junk + 1] = { name = "P" .. i, class = "MAGE", role = "DPS", status = "yes" } end
junk[1] = { name = "|cffff0000Red|r|TInterface\\Icons\\X:64|t", class = "MAGE", role = "BOSS", status = "yes" }
junk[2] = { name = "Bad", status = "maybe" }
junk[3] = { name = 42, status = "yes" }
junk[4] = "not a table"
Cal:OnSync({ act = "update", rev = 9, data = { event = { id = "web:r-sync", title = "x", when = NOW, signups = junk, signupsAt = NOW - 30 } } }, "Officer-Firemaw")
local got = events["web:r-sync"].signups
check(#got == 80, "capped, so one event cannot fill the window")
check(not got[1].name:find("|", 1, true), "no escape codes in a name")
check(got[1].role == "DPS", "an unknown role reads as dps")
for _, x in ipairs(got) do
  check(x.name ~= "Bad", "an unknown status is dropped")
end
Cal:OnSync({ act = "update", rev = 10, data = { event = { id = "web:r-sync", title = "x", when = NOW, signups = { { name = "Old", status = "yes" } }, signupsAt = NOW - 3000 } } }, "Officer2-Firemaw")
check(events["web:r-sync"].signups[1].name ~= "Old", "an older list from another officer takes nothing back")
Cal:OnSync({ act = "update", rev = 11, data = { event = { id = "web:r-sync", title = "renamed", when = NOW } } }, "OldClient-Firemaw")
check(events["web:r-sync"].title == "renamed" and #events["web:r-sync"].signups == 80, "an edit from a client that sends no list keeps the list")
Cal:OnSync({ act = "update", rev = 12, data = { event = { id = "plain", title = "x", when = NOW, signups = { { name = "A", status = "yes" } } } } }, "Officer-Firemaw")
check(events.plain.signups == nil, "an event made in game carries no site list")

-- A list stored raw by a client before this one is cleaned when read, not trusted.
events["web:raw"] = { id = "web:raw", when = NOW, signups = { { name = "NoRole", status = "yes" }, { name = "|Bad|", status = "yes", role = "TANK" } } }
local clean = Cal:WebSignups(events["web:raw"])
check(#clean == 2 and clean[1].role == "DPS" and not clean[2].name:find("|", 1, true), "read through the same cleaning")
check(Cal:GetComposition(events["web:raw"]).yes == 2, "and counted without error")

-- An officer's in-game edit of a web raid keeps the site's list in what it sends.
officer = true
local edited = events["web:r-full"]
Cal:Update(edited.id, "Renamed", edited.when, edited.size, edited.note, edited.kind)
check(published[#published].data.event.signups ~= nil and published[#published].data.event.signupsAt ~= nil, "an edit sends the list and its time")

-- ── 6. A member's client imports nothing onto the calendar ───────────
officer = false
Import._lastInbox = nil
GuildOSInbox = { wire(raid("r-member", {})) }
Import:ConsumeInbox(); Import:CalendarFromInbox()
check(events["web:r-member"] == nil, "only an officer's client puts a site raid on the guild calendar")

io.write(string.format("web-raid-calendar: %d checks passed\n", checks))
