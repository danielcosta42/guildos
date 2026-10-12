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
local LibDeflate = LibStub("LibDeflate")
local softres = io.open(ADDON .. "/Modules/SoftResSystem.lua"):read("*a")
local decoderSrc = softres:match("(local function JsonDecode.-\nend\n)")
assert(decoderSrc, "could not find JsonDecode in SoftResSystem.lua")
GuildOS.JsonDecode = assert(loadstring(decoderSrc .. "\nreturn JsonDecode"))()

dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/Calendar.lua")
local Import, Cal = GuildOS.CompanionImport, GuildOS.Calendar

-- A roster the way the site writes it: JSON, deflated, printable.
local function wire(t)
  return "GOSROST1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
local function raid(id, signups)
  local members = {}
  for _, s in ipairs(signups) do
    if s.invite then
      members[#members + 1] = { key = s.name .. "-Firemaw", name = s.name, class = s.class, spec = "", slot = s.slot, group = 0 }
    end
  end
  return {
    fmt = "GOSROST1", v = 2, raidId = id, title = "Karazhan " .. id, startsAt = NOW + 86400,
    instance = "Karazhan", instanceKey = "kara", size = 10, members = members, signups = signups,
  }
end

-- ── 1. A raid nobody has answered yet reaches the calendar ───────────
local empty = wire(raid("r-empty", {}))
check(Import:Parse(empty) ~= nil, "the inbox reads an unanswered raid")
local n, err = Import:Load(empty)
check(n == nil and err == "That roster has nobody in it.", "pasted by hand, an empty roster is still refused")

local answered = wire(raid("r-full", {
  { name = "Tanky", class = "WARRIOR", slot = "TANK", status = "yes", invite = true },
  { name = "Healz", class = "PRIEST", slot = "HEALER", status = "late", invite = true },
  { name = "Pewpew", class = "MAGE", slot = "RANGED", status = "yes", invite = false, why = "wait", wait = 1 },
  { name = "Maybe", class = "ROGUE", slot = "MELEE", status = "tentative", invite = false, why = "tentative" },
  { name = "Nope", class = "HUNTER", slot = "RANGED", status = "no", invite = false, why = "no" },
  { name = "Refused", class = "MAGE", slot = "RANGED", status = "yes", invite = false, why = "refused" },
  { name = "Pending", class = "DRUID", slot = "HEALER", status = "yes", invite = false, why = "pending" },
}))
GuildOSInbox = { empty, answered }
local ok = Import:ConsumeInbox()
check(ok, "the inbox is taken")
local events = Cal:GetEvents()
check(events["web:r-empty"] ~= nil, "the unanswered raid is on the calendar")
check(events["web:r-full"] ~= nil, "and so is the answered one")
check(Import:Current().raidId == "r-empty" or Import:Current().raidId == "r-full", "the soonest is kept for the Web panel")

-- ── 2. The site's answers travel with the event ──────────────────────
local e = events["web:r-full"]
check(Cal:IsWebEvent(e) and not Cal:IsWebEvent({ id = "a1b2" }), "a web raid is told apart by its id")
local by = {}
for _, s in ipairs(e.signups) do by[s.name] = s end
check(by.Tanky and by.Tanky.status == "yes" and by.Tanky.role == "TANK", "coming, with the role")
check(by.Healz and by.Healz.status == "yes" and by.Healz.role == "HEALER", "late is coming")
check(by.Pewpew and by.Pewpew.status == "wait" and by.Pewpew.role == "DPS", "the waitlist is its own line")
check(by.Maybe and by.Maybe.status == "tentative", "tentative")
check(by.Nope and by.Nope.status == "no", "not coming")
check(by.Pending and by.Pending.status == "yes", "waiting for the officers' approval is still somebody coming")
check(by.Refused == nil, "somebody the officers refused is not on the night")
check(#events["web:r-empty"].signups == 0, "an unanswered raid carries an empty list")

local sent
for _, p in ipairs(published) do
  if p.data.event and p.data.event.id == "web:r-full" then sent = p.data.event end
end
check(sent and sent.signups and #sent.signups == #e.signups, "the list goes out with the event, to the whole guild")

-- ── 3. What the event counts is the site's answers ───────────────────
e.rsvps = { x = { status = "yes", role = "TANK" }, y = { status = "yes", role = "TANK" } }
local comp = Cal:GetComposition(e)
check(comp.yes == 3 and comp.tentative == 1 and comp.no == 1, "counted from the site, not from the game's RSVPs")
check(comp.roles.TANK == 1 and comp.roles.HEALER == 2 and comp.roles.DPS == 0, "roles of those coming")
local own = Cal:GetComposition({ id = "abc", rsvps = { x = { status = "yes", role = "TANK" } } })
check(own.yes == 1 and own.roles.TANK == 1, "an event made in game still counts its RSVPs")

-- ── 4. Republished only when something moved ────────────────────────
local before = #published
Import._lastInbox = nil
Import:ConsumeInbox()
check(#published == before, "the same answers publish nothing")
GuildOSInbox = { wire(raid("r-full", {
  { name = "Tanky", class = "WARRIOR", slot = "TANK", status = "no", invite = false, why = "no" },
})) }
Import:ConsumeInbox()
check(#published == before + 1, "a changed answer publishes the event again")
check(events["web:r-full"].signups[1].status == "no", "with the new answer")

-- ── 5. What arrives over the guild channel is checked again ──────────
local junk = {}
for i = 1, 100 do junk[#junk + 1] = { name = "P" .. i, class = "MAGE", role = "DPS", status = "yes" } end
junk[1] = { name = "|cffff0000Red|r|TInterface\\Icons\\X:64|t", class = "MAGE", role = "BOSS", status = "yes" }
junk[2] = { name = "Bad", status = "maybe" }
junk[3] = { name = 42, status = "yes" }
junk[4] = "not a table"
Cal:OnSync({ act = "update", rev = 9, data = { event = { id = "web:r-sync", title = "x", when = NOW, signups = junk } } }, "Officer-Firemaw")
local got = events["web:r-sync"].signups
check(#got == 80, "capped, so one event cannot fill the window")
check(not got[1].name:find("|", 1, true), "no escape codes in a name")
check(got[1].role == "DPS", "an unknown role reads as dps")
for _, s in ipairs(got) do
  check(s.name ~= "Bad", "an unknown status is dropped")
end
Cal:OnSync({ act = "update", rev = 10, data = { event = { id = "plain", title = "x", when = NOW, signups = { { name = "A", status = "yes" } } } } }, "Officer-Firemaw")
check(events.plain.signups == nil, "an event made in game carries no site list")

-- An officer's in-game edit of a web raid keeps the site's list on every client.
officer = true
local edited = events["web:r-full"]
Cal:Update(edited.id, "Renamed", edited.when, edited.size, edited.note, edited.kind)
check(published[#published].data.event.signups ~= nil, "an edit keeps the list in what it sends")

-- ── 6. A member's client imports nothing onto the calendar ───────────
officer = false
Import._lastInbox = nil
GuildOSInbox = { wire(raid("r-member", {})) }
Import:ConsumeInbox()
check(events["web:r-member"] == nil, "only an officer's client puts a site raid on the guild calendar")

io.write(string.format("web-raid-calendar: %d checks passed\n", checks))
