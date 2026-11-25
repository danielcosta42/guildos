-- Winter Veil's Secret Santa in the game (issue #437; the site's specs/119), run against the real CompanionImport and
-- WinterVeil under stubbed WoW APIs.
--
-- The site holds the event and the pairs; the addon reads two blocks and tells the site what happened. This proves:
-- the seal is the site's byte for byte (the vector is the site's own test's); the guild's block and a person's block
-- are read to their shape and refused when they are not theirs; a list is held to the guild's rules before it is
-- sent; a pair a carrier whispers opens only for its owner; on the guild channel a player speaks only for
-- themselves; a delivery counts only to whom I drew; and the export carries it all.
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
    AuctionPrice = function(item) return item == 9001 and 12000 or nil end,
  },
  -- A catalog of two recipes: 1001 makes item 9001 (one at a time), 1002 makes item 9002 (nobody prices it).
  ProfCatalog = { F = { out = 4, outCount = 5 }, recipes = { [1001] = { 0, 0, 0, 9001, 1 }, [1002] = { 0, 0, 0, 9002, 1 } } },
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
local SALT = "00112233445566778899aabbccddeeff"
local function veil(extra)
  local v = { year = 2025, kind = "both", cap = 2000000, joinUntil = NOW - 86400, revealAt = NOW + 10 * 86400, reassignDays = 3,
              drawn = true, salt = SALT, counts = { entrants = 5, withList = 4, delivered = 1, pairs = 5 } }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end
local function inbox(gild, personal)
  GuildOSInbox = {}
  if gild then GuildOSInbox[#GuildOSInbox + 1] = pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = GUILD, realm = "Nightslayer", at = NOW - 60, veil = gild }) end
  if personal then
    local p = { fmt = "GOSVEIL1", v = 1, guild = GUILD, realm = "Nightslayer", at = NOW - 60, year = 2025, mine = {}, relay = {} }
    for k, x in pairs(personal) do p[k] = x end
    GuildOSInbox[#GuildOSInbox + 1] = pack("GOSVEIL1", p)
  end
  Import._blockRaw, Import._veilRaw = nil, nil
end

-- ── 1. The seal is the site's, byte for byte ──────────────────────────
check(WV.Fnv1a("abc") == 0x1a47e90b, "FNV-1a matches the site's")
check(WV.Seal("Winter Veil", "salt:Key") == "6c969bcc2c44b67092fb17", "the seal matches the site's frozen vector")
check(WV.Unseal(WV.Seal('{"to":"X"}', "k"), "k") == '{"to":"X"}', "a seal opens with its key")
check(WV.Unseal("zz", "k") == nil and WV.Unseal("abc", "k") == nil, "and refuses what is not hex")

-- ── 2. The guild's block ──────────────────────────────────────────────
inbox(nil)
check(WV:Event() == nil, "no block, no event")
inbox(veil({ kind = "everything" }))
check(WV:Event() == nil, "a kind the site never sends is no event")
inbox(veil({ entrants = { { key = "Thalindra-Nightslayer", list = true, gave = false }, { key = "bad|key" } } }))
local e = WV:Event()
check(e and e.cap == 2000000 and e.drawn and e.salt == SALT, "the event is read")
check(#e.entrants == 1 and e.entrants[1].key == "Thalindra-Nightslayer", "an entrant with a key that is not one is passed over")
check(WV.PhaseOf(e, NOW) == "drawn" and WV.PhaseOf(e, NOW + 11 * 86400) == "revealed", "the phase is the event's own clock")

-- Before the site opens it to everybody, a tester's own block carries the event and the guild's says nothing.
inbox(nil, { mine = {}, event = veil() })
check(WV:Event() and WV:Event().cap == 2000000, "a tester's own block carries the event before the opening")
inbox({ kind = "both" }, { mine = {}, event = veil({ cap = 3000000 }) })
check(WV:Event().cap == 3000000, "a guild block with no valid event leaves the tester's")

-- ── 3. My block, and a list held to the guild's rules ─────────────────
inbox(veil(), { mine = { { key = "Chehul-Nightslayer", volunteer = false, got = false,
  wishes = { { k = "gold", copper = 500000 } },
  gives = { { to = "Thalindra-Nightslayer", delivered = false, wishes = { { k = "item", recipe = 1001, qty = 2, copper = 24000 }, { k = "gold", copper = 1000000 } } } } } },
  relay = { { giver = "Kaelthos-Nightslayer", seal = WV.Seal('{"to":"Chehul-Nightslayer","wishes":[]}', SALT .. ":Kaelthos-Nightslayer") } } })
local p = WV:Personal()
check(p and #p.mine == 1 and p.mine[1].gives[1].to == "Thalindra-Nightslayer", "my block says whom I drew")
check(#p.relay == 1, "and the pair I carry")
check(WV:MyGives()[1].wishes[1].copper == 24000, "their list comes with what each option is worth")

WV:ScanPrices({ 1001, 1002 })
check(WV:PriceOf(1001) == 12000 and WV:PriceOf(1002) == nil, "a price is read from the auction addon, and only where it has one")
check(published[#published].act == "prices", "and shared with the guild")
check(WV:SetList({ { k = "item", recipe = 1002, qty = 1 } }) == false, "an item with no price is refused")
check(select(2, WV:SetList({ { k = "gold", copper = 3000000 } })) == "cap", "an option over the cap is refused")
check(select(2, WV:SetList({ { k = "gold", copper = 10000 }, { k = "gold", copper = 20000 } })) == "shape", "two golds are refused")
check(WV:SetList({ { k = "item", recipe = 1001, qty = 20 }, { k = "gold", copper = 500000 } }) == true, "a list within the rules is kept")
check(published[#published].act == "list" and published[#published].data.k == "Chehul-Nightslayer", "and announced as mine")
inbox(veil({ kind = "gold" }), { mine = {} })
check(select(2, WV:SetList({ { k = "item", recipe = 1001, qty = 1 } })) == "kind", "a guild of gold only takes no item")

-- ── 4. The relay: a whispered pair opens only for its owner ───────────
inbox(veil({ carriers = { { giver = "Chehul-Nightslayer", carrier = "Kaelthos-Nightslayer" } } }),
      { mine = {}, relay = { { giver = "Kaelthos-Nightslayer", seal = WV.Seal("{}", SALT .. ":Kaelthos-Nightslayer") } } })
local before = #published
check(WV:Relay() == 1 and published[#published].act == "pair" and published[#published].opts.target == "Kaelthos-Nightslayer", "I whisper the pair I carry to its owner, online")
check(WV:Relay() == 0 and #published == before + 1, "and not again within the hour")
local sealed = WV.Seal('{"to":"Thalindra-Nightslayer","wishes":[{"k":"gold","copper":100000}],"delivered":false}', SALT .. ":Chehul-Nightslayer")
local forged = WV.Seal('{"to":"Kaelthos-Nightslayer","wishes":[],"delivered":false}', SALT .. ":Chehul-Nightslayer")
WV:OnEnvelope({ act = "pair", data = { g = "Chehul-Nightslayer", s = forged } }, "Thalindra-Nightslayer")
check(#WV:MyGives() == 0, "a pair whispered by anybody but my carrier is not believed: every member holds the salt")
WV:OnEnvelope({ act = "pair", data = { g = "Chehul-Nightslayer", s = sealed } }, "Kaelthos-Nightslayer")
check(WV:MyGives()[1] and WV:MyGives()[1].to == "Thalindra-Nightslayer", "a pair whispered to me opens with the guild's salt")
check(published[#published].act == "got", "and I say I have it")
check(WV:OpenPair(WV.Seal('{"to":"X-Nightslayer"}', SALT .. ":Someone-Nightslayer")) == false or WV:MyGives()[1].to ~= "X-Nightslayer", "another's pair does not open as mine")

-- ── 5. The guild channel: a player speaks only for themselves ─────────
local s = WV._store()
WV:OnEnvelope({ act = "list", data = { k = "Thalindra-Nightslayer", w = { { k = "gold", copper = 10000 } }, at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(s.people["Thalindra-Nightslayer"] == nil, "a list about somebody else is dropped")
WV:OnEnvelope({ act = "list", data = { k = "Kaelthos-Nightslayer", w = { { k = "gold", copper = 10000 } }, at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(s.people["Kaelthos-Nightslayer"].wishes[1].copper == 10000, "a player's own list is kept")
WV:OnEnvelope({ act = "gave", data = { giver = "Thalindra-Nightslayer", to = "Chehul-Nightslayer", via = "mail", at = NOW - 5 } }, "Kaelthos-Nightslayer")
check(next(s.deliveries) == nil, "a delivery claimed for somebody else is dropped")
WV:OnEnvelope({ act = "prices", data = { p = { { r = 1002, c = 5000, at = NOW - 5 } } } }, "Kaelthos-Nightslayer")
check(WV:PriceOf(1002) == 5000, "a guildmate's scan prices what my client cannot")

-- ── 6. A delivery counts only to whom I drew, and the export carries it ──
check(WV:RecordDelivery("Kaelthos-Nightslayer", "mail", 10000) == false, "a mail to anybody else is no delivery")
check(WV:RecordDelivery("Thalindra-Nightslayer", "trade", 0) == true, "a trade to whom I drew is")
check(WV:RecordDelivery("Thalindra-Nightslayer", "mail", 10000) == false, "and only once")
WV:Join(true)
local out = WV:ForExport()
check(out and out.year == 2025, "the export names the year")
check(#out.deliveries == 1 and out.deliveries[1].giver == "Chehul-Nightslayer" and out.deliveries[1].via == "trade", "it carries my delivery")
check(out.prices["1001"] and out.prices["1001"].c == 12000, "the prices")
check(#out.wishes >= 1 and out.needs == nil, "the lists, and no bank needs from a member's client")

-- ── 7. The export as the site reads it: no price is no field (an empty table encodes as a list) ──
GuildOS.db.winterVeil.prices = {}
local json = GuildOS.Companion.EncodeJson(WV:ForExport())
check(not json:find('"prices"', 1, true), "an export with no fresh price carries no prices field")
for i = 1, 150 do GuildOS.db.winterVeil.people["P" .. i .. "-Nightslayer"] = { join = { volunteer = false, at = NOW - i } } end
check(#WV:ForExport().joins == 100, "a guild of hundreds stays within the site's cap, newest first")

print(string.format("winter-veil: %d checks passed", checks))
