-- The site's events that are not raids, from the companion's inbox to the guild calendar (guildos-web #652), run
-- against the real CompanionImport, Calendar and GameCalendar under stubbed WoW APIs.
--
-- A social night, PvP, a meetup or anything else booked on the site used to stay on the site and Discord: the
-- GOSROST1 says no kind, and every roster the addon receives goes on the calendar as a raid to invite. The site now
-- sends them apart, in the guild's GOSGILD1 (`events`), which an addon before this never reads. This proves the
-- event lands as its type, from the site, with its place and counts and nobody to invite; that what the inbox says
-- is checked (types, sizes, the id's alphabet); that it leaves the calendar when the site stops sending it inside the
-- window, and only then; that a block without the field changes nothing; and that it travels to the other clients.
--
--   luajit -e 'ADDON="."' tools/site-events.lua
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
local GUILD = "Rend"
function GetServerTime() return NOW end
function IsInGuild() return true end
function GetGuildInfo() return GUILD, "Officer", 1 end
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
function GuildOS:SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then io.stderr:write("SafeCall: " .. tostring(err) .. "\n") end
  return ok
end
function GuildOS:Print() end
local officer = true
function GuildOS:IsOfficer() return officer end
dofile(ADDON .. "/Core/Utils.lua")

local published = {}
GuildOS.SyncService = {
  NextRevision = function() return #published + 1 end,
  Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end,
  ShouldApply = function() return true end,
  SetRevision = function() end,
}

dofile(ADDON .. "/Libs/LibDeflate.lua")
local LibDeflate = LibStub("LibDeflate")

dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/Calendar.lua")
dofile(ADDON .. "/Modules/GameCalendar.lua")
local Import, Cal, GC = GuildOS.CompanionImport, GuildOS.Calendar, GuildOS.GameCalendar
local events = Cal:GetEvents()

local function pack(fmt, t)
  return fmt .. ":" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
-- The guild's block the way the site writes it; `list` nil leaves the field out (a site before #652).
local function block(list, extra)
  local t = { fmt = "GOSGILD1", v = 1, guild = GUILD, realm = "Firemaw", at = NOW - 1800, events = list }
  for k, v in pairs(extra or {}) do t[k] = v end
  return pack("GOSGILD1", t)
end
local CLOCK = { year = 2025, month = 10, day = 10, hour = 21, minute = 0 }
local function event(id, kind, startsAt, extra)
  local t = { id = id, kind = kind, title = "Noite " .. id, startsAt = startsAt, clock = CLOCK, where = "Goldshire", going = 3, maybe = 1 }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
local function inbox(list, ack, extra)
  GuildOSInbox = { block(list, extra) }
  GuildOSInboxAck = ack and { at = ack, members = 0 } or nil
  Import._blockRaw = nil
end
local function sentFor(id)
  for i = #published, 1, -1 do
    local d = published[i].data
    if (d.event and d.event.id == id) or d.id == id then return published[i] end
  end
end

-- ── 1. A site of before #652: a block with no `events`, and no block at all, change nothing ──
inbox(nil, NOW - 600)
check(Import:SiteEvents() == nil, "a block that says nothing of events is no list")
Import:CalendarFromInbox()
check(next(events) == nil and #published == 0, "and nothing reaches the calendar")
GuildOSInbox = {}
check(Import:SiteEvents() == nil, "no block, no list")

-- ── 2. The events land as their type, from the site, with the place and the counts, nobody to invite ──
inbox({
  event("e-social", "social", NOW + 86400),
  event("e-pvp", "pvp", NOW + 2 * 86400, { where = "" }),
  event("e-meet", "meetup", NOW + 3 * 86400),
  event("e-other", "other", NOW + 4 * 86400),
}, NOW - 600)
Import:CalendarFromInbox()
local social = events["web:e-social"]
check(social and social.kind == "SOCIAL" and social.title == "Noite e-social" and social.when == NOW + 86400, "a social night is a SOCIAL event")
check(events["web:e-pvp"].kind == "PVP" and events["web:e-other"].kind == "OTHER", "PvP is PVP, other is OTHER")
check(events["web:e-meet"].kind == "SOCIAL", "a meetup is a SOCIAL event in the game")
check(Cal:IsWebEvent(social) and Cal:IsSiteEvent(social), "marked as the site's")
check(social.note == "From the website. Where: %s" or social.note:find("Goldshire", 1, true), "the note says it is from the site, with its place")
check(events["web:e-pvp"].note == "From the website.", "and without a place, only that")
check(social.clock and social.clock.hour == 21, "on the guild's clock, as a raid")
check(#social.signups == 0 and next(social.rsvps) == nil, "no names: nobody to invite, nobody's answer in the game")
check(social.signupsAt == NOW - 600, "stamped with when the site gave it")
local comp = Cal:GetComposition(social)
check(comp.yes == 3 and comp.tentative == 1 and comp.roles.TANK == 0, "the site's counts are what it counts, with no roles")
check(GuildOS.db.companionRaids == nil and Import._webRaids == nil, "an event is no raid: nothing to invite, no night to match")
local out = sentFor("web:e-social")
check(out and out.act == "create" and out.data.event.site and out.data.event.site.going == 3, "it goes out to the guild, with its counts")
check(out.data.event.kind == "SOCIAL" and out.data.event.canceled == false, "its kind, and that it stands")

-- Nothing moved: nothing goes out; the hourly rewrite moves only its time.
local before = #published
inbox({ event("e-social", "social", NOW + 86400), event("e-pvp", "pvp", NOW + 2 * 86400, { where = "" }),
  event("e-meet", "meetup", NOW + 3 * 86400), event("e-other", "other", NOW + 4 * 86400) }, NOW - 300)
Import:CalendarFromInbox()
check(#published == before and social.signupsAt == NOW - 300, "the same events said again publish nothing")
-- A count moved: published again.
inbox({ event("e-social", "social", NOW + 86400, { going = 5 }), event("e-pvp", "pvp", NOW + 2 * 86400, { where = "" }),
  event("e-meet", "meetup", NOW + 3 * 86400), event("e-other", "other", NOW + 4 * 86400) }, NOW - 200)
Import:CalendarFromInbox()
check(#published == before + 1 and Cal:GetComposition(events["web:e-social"]).yes == 5, "a new count goes out")
-- An older inbox takes nothing back.
inbox({ event("e-social", "social", NOW + 86400, { going = 1 }) }, NOW - 5000)
Import:CalendarFromInbox()
check(Cal:GetComposition(events["web:e-social"]).yes == 5, "an older inbox changes nothing")
check(not events["web:e-pvp"].canceled, "and takes nothing off the calendar")

-- A member's client puts nothing on the calendar: only an officer's does, as with the raids.
officer = false
inbox({ event("e-member", "social", NOW + 86400) }, NOW - 100)
Import:CalendarFromInbox()
check(events["web:e-member"] == nil, "a member's client publishes nothing")
officer = true

-- ── 3. The inbox is untrusted: types, sizes, the id's alphabet ──
local long = string.rep("x", 400)
inbox({
  event("ok-1", "social", NOW + 86400, { title = "|cffff0000Red|r\nline", where = long }),
  event("bad id", "social", NOW + 86400),
  event(string.rep("a", 65), "social", NOW + 86400),
  event("bad-kind", "raid", NOW + 86400),
  event("bad-start", "social", "soon"),
  event("bad-nan", "social", 0 / 0),
  event("bad-count", "social", NOW + 86400, { going = -1 }),
  event("bad-frac", "social", NOW + 86400, { maybe = 1.5 }),
  event("no-title", "social", NOW + 86400, { title = "   " }),
  "not a table",
}, NOW - 100)
local list = Import:SiteEvents()
check(#list == 1 and list[1].id == "ok-1", "every entry that fails is passed over alone")
check(not list[1].title:find("|", 1, true) and not list[1].title:find("\n", 1, true), "the title made inert, one line")
check(#list[1].where <= 240, "the place held to its bytes")
local many = {}
for i = 1, 30 do many[i] = event("m" .. i, "social", NOW + i * 3600) end
inbox(many, NOW - 100)
check(#Import:SiteEvents() == Import.SITE_EVENTS_MAX, "no more than the site sends: ten")
inbox({ event("e-x", "social", NOW + 86400) }, NOW - 100, { guild = "Another" })
check(Import:SiteEvents() == nil, "another guild's block is not read")

-- ── 4. Gone from the site, gone from the calendar — only where the inbox can tell ──
-- Fresh state.
for k in pairs(events) do events[k] = nil end
local base = {
  event("g-1", "social", NOW + 86400), event("g-2", "pvp", NOW + 2 * 86400), event("g-3", "other", NOW + 3 * 86400),
}
inbox(base, NOW - 600)
Import:CalendarFromInbox()
check(events["web:g-2"] and not events["web:g-2"].canceled, "three events in")
-- The site cancels g-2: the next inbox leaves it out.
inbox({ base[1], base[3] }, NOW - 60)
Import:CalendarFromInbox()
check(events["web:g-2"].canceled, "cancelled on the site: off the calendar")
check(sentFor("web:g-2").act == "cancel", "on every client")
check(#Cal:GetUpcoming(false) == 2, "and no longer upcoming")

-- The list empty: the site has no event left in the window.
inbox({}, NOW - 30)
Import:CalendarFromInbox()
check(events["web:g-1"].canceled and events["web:g-3"].canceled, "an empty list takes every one off")

-- Sent again (moved back into the window, say): back on the calendar, on every client.
inbox({ base[1] }, NOW - 10)
Import:CalendarFromInbox()
check(not events["web:g-1"].canceled, "the site sends it again: it is back")
local back = sentFor("web:g-1")
check(back.act == "update" and back.data.event.canceled == false, "and the other clients are told it stands")

-- No block, or one with no field: nothing is taken off.
for k in pairs(events) do events[k] = nil end
inbox(base, NOW - 600); Import:CalendarFromInbox()
inbox(nil, NOW - 60); Import:CalendarFromInbox()
check(not events["web:g-1"].canceled and not events["web:g-2"].canceled, "a block without the field takes nothing off")
GuildOSInbox = {}; Import:CalendarFromInbox()
check(not events["web:g-1"].canceled, "no block takes nothing off")

-- A stopped companion's leftover (a day old), no ack, or the companion off: nothing inferred.
inbox({}, NOW - 2 * 86400); Import:CalendarFromInbox()
check(not events["web:g-1"].canceled, "an inbox two days old takes nothing off")
inbox({}, nil); Import:CalendarFromInbox()
check(not events["web:g-1"].canceled, "nor one with no date")
GuildOS.db.settings.companion = false
inbox({}, NOW - 60); Import:CalendarFromInbox()
check(not events["web:g-1"].canceled, "nor with the companion off")
GuildOS.db.settings.companion = true

-- The pure rule, at its edges.
local function ev(id, when, known) return { id = "web:" .. id, when = when, signupsAt = known or NOW - 600 } end
local info = { ids = {}, count = 0, at = NOW - 60, last = nil }
check(GC.SiteEventGone(ev("a", NOW + 86400), info, NOW), "left out of a fresh inbox, inside the window: gone")
check(not GC.SiteEventGone(ev("a", NOW + 86400), { ids = { a = true }, count = 1, at = NOW - 60 }, NOW), "listed: not gone")
check(not GC.SiteEventGone(ev("a", NOW + 29 * 86400), info, NOW), "past the 28 days: only out of the window, not gone")
check(not GC.SiteEventGone(ev("a", NOW - 4 * 3600), info, NOW), "three hours past its start: past, not gone")
check(not GC.SiteEventGone(ev("a", NOW + 86400, NOW), info, NOW), "brought by an inbox newer than this one: not gone")
check(not GC.SiteEventGone(ev("a", NOW + 86400, 0), info, NOW), "never stamped: not gone")
local full = { ids = {}, count = GC.INBOX_CAP, at = NOW - 60, last = NOW + 5 * 86400 }
check(not GC.SiteEventGone(ev("a", NOW + 6 * 86400), full, NOW), "a full inbox: one after its last may only have been pushed out")
check(GC.SiteEventGone(ev("a", NOW + 4 * 86400), full, NOW), "but one before its last is gone")
check(not GC.SiteEventGone({ id = "plain", when = NOW + 86400, signupsAt = NOW - 600 }, info, NOW), "an event made in game is never the site's to take")

-- A raid of the site is never taken off by the events' list, nor overwritten by an event of the same id.
for k in pairs(events) do events[k] = nil end
events["web:r-1"] = { id = "web:r-1", title = "Kara", when = NOW + 86400, kind = "RAID", signups = {}, signupsAt = NOW - 600, rsvps = {} }
inbox({ event("r-1", "social", NOW + 86400) }, NOW - 60)
Import:CalendarFromInbox()
check(events["web:r-1"].kind == "RAID" and events["web:r-1"].site == nil, "a raid of that id is left as it is")
inbox({}, NOW - 30); Import:CalendarFromInbox()
check(not events["web:r-1"].canceled, "and the events' list never takes a raid off")
-- Even one an officer re-kinded by hand in the game: what marks the site's events is what only they carry.
events["web:r-1"].kind = "SOCIAL"
inbox({}, NOW - 20); Import:CalendarFromInbox()
check(not events["web:r-1"].canceled, "a raid made SOCIAL by hand is still not the events' to take")

-- ── 5. Over the guild channel: checked, and cancelled or not as the sender has it ──
for k in pairs(events) do events[k] = nil end
Cal:OnSync({ act = "create", rev = 1, data = { event = { id = "web:s-1", title = "Taverna", when = NOW + 86400, kind = "SOCIAL",
  site = { where = "|cffGold|r\nshire", going = 4, maybe = -3 }, signups = { { name = "Leak", status = "yes" } }, signupsAt = NOW - 60,
  game = { title = "x", at = NOW }, gameAt = NOW } } }, "Officer-Firemaw")
local s1 = events["web:s-1"]
check(Cal:IsSiteEvent(s1) and s1.site.going == 4 and s1.site.maybe == 0, "the counts cleaned")
check(not s1.site.where:find("|", 1, true) and not s1.site.where:find("\n", 1, true), "the place made inert")
check(#s1.signups == 0 and s1.game == nil, "no names, and never in the game's own calendar")
Cal:OnSync({ act = "cancel", rev = 2, data = { id = "web:s-1" } }, "Officer-Firemaw")
check(events["web:s-1"].canceled, "cancelled from another officer's client")
Cal:OnSync({ act = "update", rev = 3, data = { event = { id = "web:s-1", title = "Taverna", when = NOW + 86400, kind = "SOCIAL",
  site = { going = 4, maybe = 0 }, canceled = false, signupsAt = NOW - 30 } } }, "Officer-Firemaw")
check(not events["web:s-1"].canceled, "and back when the site sent it again")
Cal:OnSync({ act = "update", rev = 4, data = { event = { id = "web:s-2", title = "Kara", when = NOW + 86400, kind = "RAID", signupsAt = NOW - 30 } } }, "Officer-Firemaw")
check(not Cal:IsSiteEvent(events["web:s-2"]), "a site raid is not one of its events")
Cal:OnSync({ act = "update", rev = 5, data = { event = { id = "plain", title = "x", when = NOW, site = { going = 9 } } } }, "Officer-Firemaw")
check(events.plain.site == nil, "an event made in game carries no site counts")

print(string.format("site-events: %d checks passed", checks))
