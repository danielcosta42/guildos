-- Winter Veil's snow globe in the game (issue #437; the site's specs/119), run against the real CompanionImport and
-- WinterVeil under stubbed WoW APIs.
--
-- The site holds the event, the pairs and every rarity; the addon reads two blocks and tells the site what the player
-- asked. This proves: the relay (§13) is gone and an old block's `carriers`/`relay` are read past; the guild's block
-- and a person's block (GOSVEIL1 v2) are read to their shape and refused when they are not theirs; GOSVEIL1 alone
-- (its `event`, no `mine`) shows the tab and lets a player join; a note is held to the site's rules before it is sent,
-- and the caprice hint is the site's rule on the clean note; on the guild channel a player speaks only for themselves,
-- keyed as this client keys them whatever realm their client answers, and never about wrapping or opening; a globe
-- wrapped here is "waiting to sync" until the site's block holds it, with a warning a day before a deadline; a request
-- to open never carries a rarity; the export (GOSCOMP1.veil: joins, leaves, wrap, open) stays within the site's limits
-- and stops repeating what the site already has; and the event is cleaned once per block, not on every call.
--
--   luajit -e 'ADDON="."' tools/winter-veil.lua
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
local NOW = 1765800000
local GUILD = "Curva-Mor"
local ME = "Chehul"
function GetServerTime() return NOW end
function GetTime() return 0 end
function IsInGuild() return true end
function GetGuildInfo() return GUILD, "Member", 3 end
function GetRealmName() return "Nightslayer" end
function UnitName() return ME end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function() end }
end
local roster = { { "Thalindra-Nightslayer", true }, { "Kaelthos-Nightslayer", true } }
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) local r = roster[i]; return r[1], nil, nil, nil, nil, nil, nil, nil, r[2] end

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
  VERSION = "1.42.0",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true } },
  Client = { isAnniversary = true, defaultRaidSize = 25 },
  Compat = {
    PlayerName = function() return ME end,
  },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
function GuildOS:Print() end
function GuildOS:IsOfficer() return false end
dofile(ADDON .. "/Core/Utils.lua")

local published = {}
GuildOS.SyncService = {
  Publish = function(_, dom, act, data, opts) published[#published + 1] = { dom = dom, act = act, data = data, opts = opts } end,
  On = function() end,
}

dofile(ADDON .. "/Libs/LibDeflate.lua")
local LibDeflate = LibStub("LibDeflate")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/WinterVeil.lua")
local Import, WV = GuildOS.CompanionImport, GuildOS.WinterVeil

local function pack(fmt, t)
  return fmt .. ":" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
local function veil(extra)
  local v = { year = 2025, joinUntil = NOW - 86400, wrapUntil = NOW + 5 * 86400, openAt = NOW + 6 * 86400, reassignDays = 3,
              drawn = true, chimney = 60, counts = { entrants = 5, wrapped = 3, pairs = 5, opened = 0 } }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end
local function inbox(gild, personal)
  GuildOSInbox = {}
  if gild then GuildOSInbox[#GuildOSInbox + 1] = pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = GUILD, realm = "Nightslayer", at = NOW - 60, veil = gild }) end
  if personal then
    local p = { fmt = "GOSVEIL1", v = 2, guild = GUILD, realm = "Nightslayer", at = NOW - 60, year = 2025, mine = {}, collection = {} }
    for k, x in pairs(personal) do p[k] = x end
    GuildOSInbox[#GuildOSInbox + 1] = pack("GOSVEIL1", p)
  end
  Import._blockRaw, Import._veilRaw = nil, nil
end
local ME_KEY = "Chehul-Nightslayer"
local function personal(gives, got, extra)
  local p = { mine = { { key = ME_KEY, volunteer = false, gives = gives or {}, got = got } } }
  for k, x in pairs(extra or {}) do p[k] = x end
  return p
end

-- ── 1. The relay (§13) is gone ─────────────────────────────────────────
check(WV.Relay == nil and WV.OpenPair == nil and WV.Seal == nil and WV.Unseal == nil and WV.SealKey == nil and WV.Fnv1a == nil,
  "no relay, no seal: a player without the companion wraps on the site")
do
  local src = io.open(ADDON .. "/Modules/WinterVeil.lua"):read("*a"):gsub("%-%-[^\n]*", "")
  check(not src:find('act == "pair"', 1, true) and not src:find('"got"', 1, true) and not src:find("carriers", 1, true)
    and not src:find("%.relay") and not src:find("s%.opened%[") and not src:find("s%.carried%["), "and nothing of it is left in the module")
  check(not src:find("GUILD_ROSTER_UPDATE", 1, true), "nor the roster event that only drove it")
end

-- ── 2. The guild's block ──────────────────────────────────────────────
inbox(nil)
check(WV:Event() == nil, "no block, no event")
inbox(veil({ wrapUntil = "soon" }))
check(WV:Event() == nil, "a date that is not a number is no event")
inbox(veil({ reassignDays = 30 }))
check(WV:Event() == nil, "a term the site never sends is no event")
inbox(veil({ entrants = { { key = "Thalindra-Nightslayer", wrapped = true }, { key = "bad|key" } },
  carriers = { { giver = "Chehul-Nightslayer", carrier = "Kaelthos-Nightslayer" } }, salt = "00112233445566778899aabbccddeeff" }))
local e = WV:Event()
check(e and e.drawn and e.chimney == 60 and e.counts.wrapped == 3, "the event is read, with the Chimney")
check(#e.entrants == 1 and e.entrants[1].key == "Thalindra-Nightslayer" and e.entrants[1].wrapped, "an entrant with a key that is not one is passed over")
check(e.carriers == nil and e.salt == nil, "an older site's carriers and salt are read past, the event still whole")
inbox(veil({ carriers = "not a list", salt = 5 }))
check(WV:Event() and WV:Event().chimney == 60, "and carriers or a salt of any shape do not break it")
check(WV.PhaseOf(e, NOW) == "wrapping" and WV.PhaseOf(e, NOW + 5 * 86400 + 1) == "wrapped" and WV.PhaseOf(e, NOW + 7 * 86400) == "open", "the phase is the event's own clock")
check(WV.PhaseOf(veil({ drawn = false }) and { joinUntil = NOW + 10, wrapUntil = NOW + 20, openAt = NOW + 30, drawn = false }, NOW) == "joining", "joining before the draw")
inbox(veil({ chimney = 140 }))
check(WV:Event() == nil, "a Chimney over 100% is no event")
inbox(veil({ reveal = {
  { giver = "Kaelthos-Nightslayer", to = "Chehul-Nightslayer", scene = "cabin", rarity = "epic" },
  { giver = "Frimm", to = "Thalindra-Nightslayer", scene = "tree", rarity = "common", host = true },
  { giver = "Kaelthos-Nightslayer", to = "Thalindra-Nightslayer", scene = "castle", rarity = "epic" },
  { giver = "Kaelthos-Nightslayer", to = "Thalindra-Nightslayer", scene = "fire", rarity = "mythic" } } }))
e = WV:Event()
check(#e.reveal == 2 and e.reveal[1].scene == "cabin" and e.reveal[2].host == true and e.reveal[2].giver == "Frimm", "the chain keeps the globes whose scene and rarity are the site's, and the host's")
-- Before the site opens it to everybody, a tester's own block carries the event and the guild's says nothing.
inbox(nil, { mine = {}, event = veil() })
check(WV:Event() and WV:Event().chimney == 60, "a tester's own block carries the event before the opening")
inbox({ nothing = true }, { mine = {}, event = veil({ chimney = 10 }) })
check(WV:Event().chimney == 10, "a guild block with no valid event leaves the tester's")

-- ── 3. My block (GOSVEIL1 v2) ─────────────────────────────────────────
local OPENED = { id = "o1", year = 2025, scene = "cabin", rarity = "epic", openedAt = NOW - 100, from = "Kaelthos-Nightslayer", note = "Que o seu inverno seja quente" }
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", toClass = "MAGE", wrapped = false } }, { ready = true, ornament = OPENED },
  { collection = { OPENED, { id = "o0", year = 2024, scene = "castle", rarity = "rare", openedAt = NOW - 5000 }, { id = "o2", year = 2024, scene = "fire", rarity = "legendary", openedAt = NOW - 5000, host = true } },
    relay = { { giver = "Kaelthos-Nightslayer", seal = "6c969bcc" } } }))
local p = WV:Personal()
check(p and #p.mine == 1 and p.mine[1].gives[1].to == "Thalindra-Nightslayer" and not p.mine[1].gives[1].wrapped, "my block says whom I drew")
check(p.relay == nil, "an older site's relay is read past")
check(WV:Got().ornament.rarity == "epic" and WV:Got().ornament.from == "Kaelthos-Nightslayer", "the globe I got comes with its rarity, as the site drew it")
check(#WV:Collection() == 2 and WV:Collection()[2].host == true, "the Collection keeps the globes the site sends and drops a scene it never sends")
GuildOSInbox = { pack("GOSVEIL1", { fmt = "GOSVEIL1", v = 1, guild = GUILD, at = NOW - 60, year = 2025, mine = {}, relay = {} }) }
Import._veilRaw = nil
check(WV:Personal() == nil, "the first design's v1 block is refused")
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", scene = "volcano", note = string.rep("a", 400), wrapped = true } }))
check(WV:MyGives()[1].scene == nil and WV:MyGives()[1].note == nil, "a scene outside the five and a note past the limit are dropped")
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", note = "Feliz |cffff0000Natal|r", wrapped = true, scene = "tree" } }))
check(not WV:MyGives()[1].note:find("|", 1, true), "a note off the network opens no colour code")

-- ── 4. The note: the site's rules, checked here first ──────────────────
check(WV.CleanNote("  Feliz   Natal \n ") == "Feliz Natal", "whitespace collapses")
check(WV.CleanNote(nil) == "" and WV.CleanNote("") == "", "no note is fine")
check(WV.CleanNote(string.rep("a", 80)) and not WV.CleanNote(string.rep("a", 81)), "80 characters, not 81")
check(WV.CleanNote(string.rep("\195\169", 80)) and not WV.CleanNote(string.rep("\195\169", 81)), "a character counts once, not by its bytes")
for _, bad in ipairs({ "oi @fulano", "veja https://x.y", "www.site.pt", "ver site.com agora", "a `b`", "*forte*", "a_b", "a~b", "<b>", "[x]", "a|b", "a\\b", "#tag", "ctl\1x", "bell\127", "zero\226\128\139width", "c1\194\133x", "dir\226\128\174x", "iso\226\129\166x" }) do
  check(WV.CleanNote(bad) == nil, "the note is refused: " .. bad:gsub("%c", "?"))
end
check(WV.CleanNote("2025.me") == nil and WV.CleanNote("Natal; paz, amor!") == "Natal; paz, amor!", "a link by its end is refused, punctuation is not")

-- ── 5. Wrapping: a scene and a note, whole ────────────────────────────
inbox(veil(), personal({ { to = "Thalindra-Nightslayer", toClass = "MAGE", wrapped = false } }))
check(WV:Wrap("Kaelthos-Nightslayer", "tree", "oi") == false, "a globe for somebody I did not draw is refused")
check(select(2, WV:Wrap("Thalindra-Nightslayer", "castle", "oi")) == "scene", "a scene outside the five is refused")
check(select(2, WV:Wrap("Thalindra-Nightslayer", "tree", "oi @x")) == "note", "a note the site would refuse is refused")
check(WV:Wrap("Thalindra-Nightslayer", "cabin", "Feliz Natal!") == true, "a globe within the rules is kept")
local g = WV:MyGives()[1]
check(not g.wrapped and g.pending and g.scene == "cabin" and g.note == "Feliz Natal!", "and shows as waiting to sync, not wrapped, until the site's block holds it")
check(#WV:PendingSync() == 1 and WV:PendingSync()[1].to == "Thalindra-Nightslayer" and WV:PendingSync()[1].scene == "cabin", "PendingSync names it")
check(#published == 0 or published[#published].act ~= "wrap", "wrapping is never said on the guild channel")
check(WV:Wrap("Thalindra-Nightslayer", "fire", "Outra") == true and WV:MyGives()[1].scene == "fire", "wrapping again replaces the scene and the note")
inbox(veil({ wrapUntil = NOW - 10, openAt = NOW + 86400 }), personal({ { to = "Thalindra-Nightslayer" } }))
check(select(2, WV:Wrap("Thalindra-Nightslayer", "tree", "")) == "phase", "after the deadline nothing is wrapped")
inbox(veil(), nil)
check(select(2, WV:Wrap("Thalindra-Nightslayer", "tree", "")) == "companion", "without the companion's block the game does not wrap")
-- Two pairs (one taken over from somebody who did not wrap): the line names the receiver.
inbox(veil(), personal({ { to = "Thalindra-Nightslayer" }, { to = "Gorbash-Nightslayer", extra = true } }))
WV._store().wraps = {}
check(WV:Wrap("Gorbash-Nightslayer", "snowman", "Para o urso") == true, "the extra pair can be wrapped")
local out = WV:ForExport()
check(#out.wrap == 1 and out.wrap[1].giver == ME_KEY and out.wrap[1].to == "Gorbash-Nightslayer" and out.wrap[1].scene == "snowman" and out.wrap[1].note == "Para o urso", "with two pairs the export line names the receiver")
inbox(veil(), personal({ { to = "Thalindra-Nightslayer" } }))
WV._store().wraps = {}
WV:Wrap("Thalindra-Nightslayer", "tree", "")
out = WV:ForExport()
check(#out.wrap == 1 and out.wrap[1].to == nil and out.wrap[1].note == "", "with one pair the receiver is implied")

-- ── 6. Opening: the game asks, the site draws ─────────────────────────
inbox(veil(), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true }))
check(select(2, WV:RequestOpen()) == "phase", "nothing opens before the opening date")
inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = false }))
check(select(2, WV:RequestOpen()) == "nothing", "a globe that is not there cannot be opened")
inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true }))
check(WV:RequestOpen() == true and WV:OpenRequested(), "the receiver asks to open")
out = WV:ForExport()
check(#out.open == 1 and out.open[1].receiver == ME_KEY and out.open[1].at == NOW, "the export carries the request")
local json = GuildOS.Companion.EncodeJson(out)
check(not json:find("rarity", 1, true) and not json:find("common", 1, true), "and never a rarity: the server draws it")
check(#published == 0 or published[#published].act ~= "open", "opening is never said on the guild channel")
inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = OPENED }))
check(select(2, WV:RequestOpen()) == "nothing", "an opened globe is not asked for twice")

-- ── 7. Waiting to sync, and the warning before a deadline ─────────────
do
  local WRAPU = NOW + 5 * 86400
  local ev = veil({ wrapUntil = WRAPU, reassignDays = 3 })
  inbox(ev, personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  WV._store().wraps = {}
  check(#WV:PendingSync() == 0 and WV:SyncWarning() == nil, "nothing wrapped here, nothing waiting")
  WV:Wrap("Thalindra-Nightslayer", "tree", "Boas festas")
  check(#WV:PendingSync() == 1 and WV:SyncWarning() == nil, "wrapped here, five days to go: waiting, no warning yet")
  local RA = WV.ReassignAt(WV:Event())
  check(RA == WRAPU - 3 * 86400, "the reassignment is reassignDays before the deadline (the site's reassignAt)")
  local w = WV.SyncWarningAt(WV:Event(), 1, RA - 3600)
  check(w and w.kind == "reassign" and w.at == RA and w.left == 3600, "an hour before the reassignment: warned, about the reassignment")
  check(WV.SyncWarningAt(WV:Event(), 1, RA - 86400) == nil, "a whole day before: not yet")
  w = WV.SyncWarningAt(WV:Event(), 1, WRAPU - 600)
  check(w and w.kind == "wrapUntil" and w.left == 600, "past the reassignment, ten minutes before the deadline: warned, about the deadline")
  check(WV.SyncWarningAt(WV:Event(), 1, WRAPU + 1) == nil, "past the deadline: nothing left to warn of")
  check(WV.SyncWarningAt(WV:Event(), 0, RA - 3600) == nil, "nothing waiting: no warning")
  local saved = NOW
  NOW = RA - 7200
  inbox(ev, personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  check(WV:SyncWarning() and WV:SyncWarning().kind == "reassign", "SyncWarning() says it now, from the wrap kept here")
  -- The site's block now holds it, as wrapped here.
  inbox(ev, personal({ { to = "Thalindra-Nightslayer", wrapped = true, scene = "tree", note = "Boas festas" } }))
  check(#WV:PendingSync() == 0 and WV:SyncWarning() == nil and WV:MyGives()[1].wrapped and not WV:MyGives()[1].pending, "once the site holds it: wrapped, nothing waiting")
  -- Wrapped again here with another scene: waiting again, wrapped on the site meanwhile.
  WV:Wrap("Thalindra-Nightslayer", "fire", "Boas festas")
  g = WV:MyGives()[1]
  check(g.wrapped and g.pending and g.scene == "fire", "wrapped again here: the site's globe stands, the new one waits")
  NOW = saved
end

-- ── 8. The guild channel: a player speaks only for themselves ─────────
local s = WV._store()
WV:OnEnvelope({ act = "join", data = { k = "Thalindra-Nightslayer", v = false, at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(s.people["Thalindra-Nightslayer"] == nil, "an entry announced for somebody else is dropped")
WV:OnEnvelope({ act = "join", data = { k = "Kaelthos-Nightslayer", v = true, at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(s.people["Kaelthos-Nightslayer"].join.volunteer == true, "a player's own entry is kept")
WV:OnEnvelope({ act = "leave", data = { k = "Kaelthos-Nightslayer", at = NOW - 9 } }, "Kaelthos-Nightslayer")
check(s.people["Kaelthos-Nightslayer"].join ~= nil, "an older leave does not undo a newer entry")
WV:OnEnvelope({ act = "leave", data = { k = "Kaelthos-Nightslayer", at = NOW - 1 } }, "Kaelthos-Nightslayer")
check(s.people["Kaelthos-Nightslayer"].join == nil and s.people["Kaelthos-Nightslayer"].left == NOW - 1, "a newer one does")
WV:OnEnvelope({ act = "wrap", data = { g = "Kaelthos-Nightslayer", sc = "tree", n = "x", at = NOW - 5 } }, "Kaelthos-Nightslayer")
WV:OnEnvelope({ act = "open", data = { r = "Kaelthos-Nightslayer", at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(next(s.wraps) == nil or s.wraps["Kaelthos-Nightslayer"] == nil, "a line about wrapping or opening is not a thing of the channel")
WV:OnEnvelope({ act = "join", data = { k = "Gorbash-Nightslayer", v = false, at = NOW + 4000 } }, "Gorbash-Nightslayer")
check(s.people["Gorbash-Nightslayer"] == nil, "a stamp from the future is dropped")
local sent = #published
WV:OnEnvelope({ act = "pair", data = { g = ME_KEY, s = "00" } }, "Kaelthos-Nightslayer")
WV:OnEnvelope({ act = "got", data = { g = "Kaelthos-Nightslayer" } }, "Kaelthos-Nightslayer")
check(WV._store().opened == nil and WV._store().carried == nil and #published == sent, "the relay's pair and got are dropped, unanswered")

-- ── 9. Joining, and the export within the site's limits ───────────────
inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), { mine = {} })
check(WV:Join(true) == true and WV:Joined(), "I can join before it closes")
check(published[#published].act == "join" and published[#published].data.k == ME_KEY, "and say so, as myself")
out = WV:ForExport()
check(out.year == 2025 and #out.joins >= 1 and #out.leaves >= 0, "the export names the year and the entries")
check(WV:Leave() == true and not WV:Joined(), "I can leave before the draw")
inbox(veil({ drawn = true }), { mine = {} })
check(WV:Join(false) == false and WV:Leave() == false, "and neither after it")
inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), { mine = {} })
-- All newer than the site's block (NOW - 60): an older line is one the site already has (§11).
for i = 1, 150 do GuildOS.db.winterVeil.people["P" .. i .. "-Nightslayer"] = { join = { volunteer = false, at = NOW - (i % 50) } } end
check(#WV:ForExport().joins == 100, "a guild of hundreds stays within the site's cap, newest first")
local enc = GuildOS.Companion.EncodeJson(WV:ForExport())
check(not enc:find('"prices"', 1, true) and not enc:find('"needs"', 1, true) and not enc:find('"deliveries"', 1, true), "nothing of the first design is in the export")
check(not WV.RecordDelivery and not WV.ScanPrices and not WV.SetList, "and the module has none of it")

-- ── 11. Forever: clients of one guild answer different realms, or none ─
do
  local saved = GuildOS.Client
  GuildOS.Client = {}   -- WoW: Forever (no realm sets players apart)
  inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), { mine = {} })
  GuildOS.db.winterVeil = nil
  local st = WV._store()
  local LOCAL = GuildOS:LocalMemberKey("Ana Lima")
  check(LOCAL == "Ana Lima-Nightslayer", "this client keys Ana as Ana Lima-Nightslayer")
  -- Ana's client answers "Classic Beta PvE 2"; the game's sender carries no realm, or that one.
  WV:OnEnvelope({ act = "join", data = { k = "Ana Lima-Classic Beta PvE 2", v = true, at = NOW - 30 } }, "Ana Lima")
  check(st.people[LOCAL] and st.people[LOCAL].join.volunteer == true, "a join keyed on another realm is kept, as this client keys Ana")
  check(st.people["Ana Lima-Classic Beta PvE 2"] == nil, "and not under the other realm")
  WV:OnEnvelope({ act = "leave", data = { k = "Ana Lima", at = NOW - 10 } }, "Ana Lima-Classic Beta PvE")
  check(st.people[LOCAL].join == nil and st.people[LOCAL].left == NOW - 10, "a leave with no realm, from a sender with a third one, is hers too")
  WV:OnEnvelope({ act = "join", data = { k = "Bia Souza-Classic Beta PvE 2", at = NOW - 5 } }, "Ana Lima")
  check(st.people[GuildOS:LocalMemberKey("Bia Souza")] == nil, "a line about somebody else is still dropped")
  WV:OnEnvelope({ act = "join", data = { k = "bad|key", at = NOW - 5 } }, "bad")
  WV:OnEnvelope({ act = "join", data = { k = 5, at = NOW - 5 } }, "Ana Lima")
  check(st.people["bad"] == nil and st.people["bad|key"] == nil, "a key that is not one is dropped")
  GuildOS.Client = saved
end

-- ── 12. The export stops repeating what the site already has ──────────
do
  inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), { mine = {} })
  GuildOS.db.winterVeil = nil
  local st = WV._store()
  check(WV:Join(false), "I join")
  st.people["Old-Nightslayer"] = { join = { volunteer = false, at = NOW - 3600 } }     -- before the site's block (NOW - 60)
  st.people["Gone-Nightslayer"] = { left = NOW - 3600 }
  st.people["New-Nightslayer"] = { join = { volunteer = true, at = NOW - 10 } }
  local function has(list, key) for _, r in ipairs(list) do if r.key == key then return true end end return false end
  out = WV:ForExport()
  check(has(out.joins, ME_KEY) and has(out.joins, "New-Nightslayer"), "my join and a newer one go")
  check(not has(out.joins, "Old-Nightslayer") and not has(out.leaves, "Gone-Nightslayer"), "a join or leave older than the site's block does not")
  -- The site's block now lists my entry: my own join goes no more.
  inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), personal({}))
  out = WV:ForExport()
  check(not has(out.joins, ME_KEY) and has(out.joins, "New-Nightslayer"), "once the site shows my entry, my join is not sent again")
  check(WV:Joined(), "and I am still in")
  -- I leave after that: the leave goes.
  check(WV:Leave(), "I leave")
  out = WV:ForExport()
  check(has(out.leaves, ME_KEY), "and the leave is sent while the site still lists me")
  -- A newer block stops the rest.
  local was = NOW
  NOW = NOW + 3600
  inbox(veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }), { mine = {} })
  out = WV:ForExport()
  check(#out.joins == 0 and #out.leaves == 0, "a block newer than every line: nothing of the channel is sent again")
  NOW = was
end

-- ── 13. GOSVEIL1 alone (its `event`, no `mine`): the tab shows and I can join ─
do
  GuildOSInbox = { pack("GOSVEIL1", { fmt = "GOSVEIL1", v = 2, guild = GUILD, at = NOW - 60, year = 2025, collection = {},
    event = veil({ drawn = false, joinUntil = NOW + 86400, wrapUntil = NOW + 5 * 86400 }) }) }
  Import._blockRaw, Import._veilRaw = nil, nil
  GuildOS.db.winterVeil = nil
  check(WV:Event() ~= nil and WV.PhaseOf(WV:Event()) == "joining", "the event comes from GOSVEIL1 alone")
  check(WV:Personal() and #WV:Personal().mine == 0 and WV:MyEntry() == nil and not WV:Joined(), "with no `mine`: not in yet")
  local cond
  GuildOS.UI = GuildOS.UI or {}
  local reg = GuildOS.UI.RegisterFeature
  GuildOS.UI.RegisterFeature = function(_, def) if def.id == "winterveil" then cond = def.condition end end
  local okF = pcall(dofile, ADDON .. "/UI/Features.lua")
  GuildOS.UI.RegisterFeature = reg
  check(cond and cond() == true, "the Winter Veil tab's condition holds (Features loaded: " .. tostring(okF) .. ")")
  local before = #published
  check(WV:Join(true) == true and WV:Joined(), "and I join from the game")
  check(#published == before + 1 and published[#published].act == "join", "said on the channel")
  out = WV:ForExport()
  check(#out.joins == 1 and out.joins[1].key == ME_KEY and out.joins[1].volunteer == true, "and carried by my export")
  GuildOS.db.winterVeil = nil
end

-- ── 14. The caprice: the site's rule on the clean note ─────────────────
check(WV.CAPRICE_MIN == 40 and WV.CAPRICE_LETTERS == 6, "40 characters and 6 different letters")
check(WV.Caprice("Que o seu inverno seja quente e cheio de paz!") == true, "a real note of 45 characters is a caprice")
check(WV.Caprice(string.rep("a", 80)) == false, "80 times the same letter is not")
check(WV.Caprice(string.rep("abcde ", 8)) == false, "five letters repeated to 48 characters are not")
check(WV.Caprice(string.rep("abcdef ", 6)) == true, "six letters to 42 characters are")
check(WV.Caprice(string.rep("aAbBcC", 7)) == false, "capitals are not other letters")
check(WV.Caprice("Feliz       Natal      para     voce      ok") == false, "spaces collapse first: 26 clean characters are not 40")
check(WV.Caprice(string.rep("1234567890", 5)) == false, "digits are not letters")
check(WV.Caprice(string.rep("abcdefgh", 5) .. " @x") == false, "a note the site refuses is no caprice")
check(WV.Caprice("\195\169\195\137\195\160\195\128\195\167\195\135" .. string.rep("ab", 20)) == false, "é/É, à/À, ç/Ç fold to three letters: with a and b, five")
check(WV.Caprice("\195\169\195\137\195\160\195\128\195\167\195\135\195\177" .. string.rep("ab", 20)) == true, "and ñ makes six")
check(WV.Caprice(string.rep("\226\128\148\240\159\142\132", 45)) == false, "dashes and emoji are not letters")
-- ── 15. The event is cleaned once per block, not on every call ─────────
do
  local many = {}
  for i = 1, 1000 do many[i] = { key = "P" .. i .. "-Nightslayer", wrapped = i % 2 == 0 } end
  inbox(veil({ entrants = many }), personal({}))
  local first = WV:Event()
  check(#first.entrants == 1000 and rawequal(WV:Event(), first), "the same block gives the same cleaned event")
  local t0 = os.clock()
  for _ = 1, 2000 do WV:Event() end
  check(os.clock() - t0 < 0.5, "two thousand calls (a roster update and a key each) are cheap: " .. (os.clock() - t0))
  inbox(veil({ chimney = 20 }), personal({}))
  check(not rawequal(WV:Event(), first) and WV:Event().chimney == 20, "a new block is cleaned anew")
  inbox(nil, { mine = {}, event = veil({ chimney = 30 }) })
  check(WV:Event().chimney == 30, "and with no guild block the person's event is read")
end

-- ── 10. The panel draws every state without an error, and shows what the site said ──
do
  local Frame = {}
  -- Unknown methods are no-ops; a field the panel keeps for itself ("_seen") is nil until set, as on a real frame.
  Frame.__index = function(_, k) if type(k) == "string" and k:sub(1, 1) == "_" then return nil end return Frame[k] or function(self) return self end end
  local function new() return setmetatable({ shown = true, scripts = {}, text = "" }, Frame) end
  -- The game fires OnTextChanged when SetText is called, even with the same text: the stub does too, and counts how deep
  -- the handlers nest, so a draw that sets the text of its own edit box and re-enters itself is caught (the game would
  -- end it with a C stack overflow, which SafeCall swallows).
  local depth, maxDepth = 0, 0
  function Frame:SetText(t)
    self.text = t
    local hooks = rawget(self, "hooks")
    local hook = hooks and hooks.OnTextChanged
    if hook then
      depth = depth + 1; maxDepth = math.max(maxDepth, depth)
      if depth <= 30 then pcall(hook, self, false) end
      depth = depth - 1
    end
  end
  function Frame:GetText() return self.text end
  function Frame:SetShown(v) self.shown = v and true or false end
  function Frame:Show() self.shown = true end
  function Frame:Hide() self.shown = false end
  function Frame:SetScript(n, fn) self.scripts[n] = fn end
  function Frame:HookScript(name, fn) local h = rawget(self, "hooks"); if not h then h = {}; self.hooks = h end; h[name] = fn end
  function Frame:SetTexture(t) self.tex = t end
  function Frame:CreateTexture() return new() end
  function Frame:SetEnabled(v) self.enabled = v end
  local tabs, texts = {}, {}
  local UI = {}
  for _, name in ipairs({ "CreateTitle", "CreateText", "CreateHeaderText", "CreateSectionTitle", "CreateMetricChip", "CreateProgressBar", "CreateButton",
                          "CreateCheckbox", "CreatePanel", "SetButtonVariant" }) do
    UI[name] = function(_, a, b)
      local f = new()
      if type(b) == "string" then f.text = b elseif type(a) == "string" then f.text = a end
      texts[#texts + 1] = f
      return f
    end
  end
  UI.CreateCheckbox = function() local f = new(); f.checkbox = new(); return f end
  local areas = {}
  UI.CreateTextArea = function() local f = new(); f.edit = new(); areas[#areas + 1] = f; return f end
  UI.CreateTab = function(_, _, text) local f = new(); f.tabName = text; function f:SetActive() end; tabs[text] = f; return f end
  GuildOS.UI = UI
  GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  GuildOS.QualityColors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  GuildOS.L = setmetatable({}, { __index = function(_, k) return k end })
  function CreateFrame() return new() end
  function date(...) return os.date(...) end
  local officer = false
  function GuildOS:IsOfficer() return officer end
  -- The panel draws through the Winter Veil effects, the Chimney and the shelf (guildos-web#673).
  for _, f in ipairs({ "VeilFx", "VeilChimney", "VeilShelf", "WinterVeilPanel" }) do dofile(ADDON .. "/UI/" .. f .. ".lua") end
  local container = new()
  local panel = GuildOS:CreateWinterVeilPanel(container)
  local function say(text)
    for _, f in ipairs(texts) do if f.shown and f.text and tostring(f.text):find(text, 1, true) then return true end end
    return false
  end
  local function draw() local ok, err = pcall(panel.Draw); check(ok, "the panel draws: " .. tostring(err)) end
  local function tab(name) tabs[name].scripts.OnClick(); end

  inbox(nil); draw()
  check(true, "no event, no error")
  inbox(veil({ drawn = false, joinUntil = NOW + 86400 }), { mine = {} }); draw()
  check(say("Join the Secret Santa"), "before joining closes, it offers to join")
  inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } })); draw()
  check(say("YOU DREW") and say("Wrap"), "after the draw it shows whom I drew and the wrapping")
  -- The count and the caprice hint are the clean note's, as the site counts it.
  local box = areas[#areas].edit
  box.text = "Feliz" .. string.rep(" ", 40) .. "Natal"
  draw()
  check(say("11/80") and not say("Caprice note: the rarity is drawn twice"), "45 raw characters that clean to 11 count 11, and are no caprice")
  box.text = string.rep("a", 45)
  draw()
  check(say("45/80") and not say("Caprice note: the rarity is drawn twice"), "45 times one letter: no caprice hint")
  box.text = "Que o seu inverno seja quente e cheio de paz!"
  draw()
  check(say("Caprice note: the rarity is drawn twice"), "a real long note: the hint")
  box.text = ""
  inbox(veil({ chimney = 100 }), personal({ { to = "Thalindra-Nightslayer", wrapped = true, scene = "fire", note = "oi" } })); draw()
  check(say("DOUBLE ODDS") and say("FULL"), "a full Chimney says the odds are better")

  inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer", rarity = "rare" } }, { ready = true }))
  GuildOS.db.winterVeil.opens = {}
  draw()
  check(say("Open the globe") and say("Yours for"), "at the opening the receiver is offered the globe, and sees the rarity of the one given")
  inbox(veil({ wrapUntil = NOW - 86400, openAt = NOW - 10 }), personal({ { to = "Thalindra-Nightslayer" } }, { ready = true, ornament = OPENED })); draw()
  check(say("Epic") and say("Que o seu inverno seja quente"), "an opened globe shows its rarity and note, as the site drew them")
  check(say("Asked: waiting for the site") == false, "the request is not shown once the site has answered")
  tab("Collection"); draw()
  check(say("COLLECTION"), "the Collection tab draws")
  tab("The guild's chain"); draw()
  check(say("THE GUILD'S CHAIN"), "the chain tab draws")
  officer = true; tab("Organize"); draw()
  check(say("PARTICIPANTS"), "the officers' table draws")
  tab("My secret friend"); draw()

  -- The link to the page says the guild's key, encoded; without a key it is the public page.
  inbox(veil({ guildKey = "us:Curva Mor" }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  check(GuildOS.WinterVeil:Event().guildKey == "us:Curva Mor", "the event carries the guild's key")
  inbox(veil({ guildKey = "bad|key" }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  check(GuildOS.WinterVeil:Event().guildKey == nil, "a key that is not one line is dropped")
  local hadCompanion = GuildOS.WinterVeil.HasCompanion
  GuildOS.WinterVeil.HasCompanion = function() return false end
  inbox(veil({ guildKey = "us:Curva Mor" }), personal({ { to = "Thalindra-Nightslayer", wrapped = false } })); draw()
  check(say("guildos.me/guild/us%3ACurva%20Mor/winter-veil"), "a player without the companion is sent to the guild's page of the event")
  inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } })); draw()
  check(say("guildos.me/winter-veil"), "and, with no key, to the public page")
  GuildOS.WinterVeil.HasCompanion = hadCompanion

  -- A wrap kept here with an empty note (allowed: the note is optional): a panel just opened fills its note box from
  -- it, and must not re-enter itself through the box's OnTextChanged (the game fires it on SetText, same text or not).
  GuildOS.db.winterVeil.wraps["Thalindra-Nightslayer"] = { scene = "fire", note = "", at = NOW }
  inbox(veil(), personal({ { to = "Thalindra-Nightslayer", wrapped = false } }))
  local fresh = GuildOS:CreateWinterVeilPanel(new())
  maxDepth = 0
  local okf, errf = pcall(fresh.Draw)
  check(okf, "a panel with a locally wrapped globe of an empty note draws: " .. tostring(errf))
  check(maxDepth <= 2, "and does not re-enter itself through the note box (depth " .. maxDepth .. ")")
end

print(string.format("winter-veil: %d checks passed", checks))
