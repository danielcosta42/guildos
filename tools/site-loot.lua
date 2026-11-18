-- The raid's soft reserves, priorities and wishlists from the site (GOSROST1 v6, guildos-web #556; this
-- repo's #385), run through the real CompanionImport under a stubbed client with the site's own fixture
-- (tools/roster-v6-fixture.txt, the output of its scripts/roster-v6-fixture.mts).
--
--   * the fixture parses into the addon's own shapes, in `roster.loot`;
--   * ConsumeInbox keeps them in db.siteLoot and never writes the game's tables;
--   * a hostile or broken body is refused whole (alphabet, size) or field by field (bounds), and never
--     throws or lets a NaN into a saved table;
--   * a v5 roster imports exactly as it did.
--
--   luajit -e 'ADDON="."' tools/site-loot.lua
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

function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower = string.lower
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_ID = 5
function UnitName() return "Chehul" end
function UnitClass() return "Chehul", "WARRIOR" end
function GetRealmName() return "Firemaw" end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
local SERVER = 1795000000
function GetServerTime() return SERVER end
time = os.time

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) return registry[name] end })

GuildOS = {
  VERSION = "test",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true } },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
function GuildOS:Print() end
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
local Import = GuildOS.CompanionImport
local LD = LibStub("LibDeflate")

local function slurp(path) local f = assert(io.open(ADDON .. "/" .. path, "rb")); local s = f:read("*a"); f:close(); return s end
local FIXTURE = slurp("tools/roster-v6-fixture.txt")
local V5 = slurp("tools/roster-fixture.txt")

-- A GOSROST1 built the way the site builds one, from a JSON text.
local function wire(json) return "GOSROST1:" .. LD:EncodeForPrint(LD:CompressDeflate(json)) end
-- The fixture's roster with `extra` spliced in as the v6 fields, the rest as the site sends it.
local function roster(extra)
  return wire('{"fmt":"GOSROST1","v":6,"raidId":"r1","title":"T","startsAt":1795000000,"instance":"Karazhan",'
    .. '"instanceKey":"karazhan","size":10,"members":[{"key":"Ana-Firemaw","name":"Ana","class":"MAGE","slot":"RANGED","group":1}]'
    .. (extra and ("," .. extra) or "") .. "}")
end
local function range(n, fn) local t = {} for i = 1, n do t[i] = fn(i) end return table.concat(t, ",") end

-- ── 1. The site's fixture ────────────────────────────────────────────
local r, err = Import:Parse(FIXTURE)
check(r, "the v6 fixture parses: " .. tostring(err))
check(r.raidId == "raid-556-fixture" and r.startsAt == 1795000000, "and is still the same roster")
local loot = r.loot
check(type(loot) == "table", "roster.loot is there")

local items = loot.softres.items
check(loot.softres.hidden == true, "the sheet's hidden flag arrives")
check(#items[29434] == 1 and #items[30104] == 2 and #items[30106] == 1, "reserves are listed per item")
check(items[29434][1].name == "Chehul Costa" and items[29434][1].class == "SHAMAN", "a Forever surname's plain name")
check(items[29434][1].note == 'for the "bis" ring only', "the note keeps its quote and loses its tab: " .. tostring(items[29434][1].note))
check(items[30104][1].name == "Chehul Costa" and items[30104][2].name == "Rias" and items[30104][2].note == "",
  "in reserve order, an absent note empty")
check(items[30104][2].plusOnes == 0 and not items[30104][2].hard, "soft: no +1, not hard")
local hard = items[30106][1]
check(hard.hard == true and hard.name == "Tank" and hard.class == "" and hard.note == "bank" and hard.plusOnes == 0,
  "a hard reserve is what SoftRes:LoadFromParsed makes of Gargul's: named by `for`, hard")

local prios = loot.prios
check(#prios[29434] == 2 and #prios[30104] == 2, "prios per item")
check(prios[29434][1].name == "Chehul Costa" and prios[29434][1].class == "SHAMAN" and prios[29434][1].order == 1, "first")
check(prios[29434][2].name == "Dora" and prios[29434][2].order == 1, "a tie shares its order")
check(prios[30104][1].name == "Dora" and prios[30104][1].order == 1 and prios[30104][2].name == "Rias"
  and prios[30104][2].order == 2, "the site's order is kept")

local wl = loot.wishlists
check(wl["chehul costa"] and wl["chehul costa"].name == "Chehul Costa" and wl["chehul costa"].class == "SHAMAN",
  "wishlists are keyed by the lowercased plain name")
check(wl["dora"] and wl["rias"], "and so are the others")
local w = wl["chehul costa"].wishlist
check(#w == 2 and w[1].itemId == 29434 and w[1].order == 1 and w[1].isOffspec == false, "an item")
check(w[2].itemId == 30104 and w[2].order == 2 and w[2].isOffspec == true, "an offspec item")
check(wl["dora"].wishlist[2].itemId == 30108 and wl["rias"].wishlist[1].itemId == 30105, "the rest")

-- On retail the key is the whole Name-Realm, as guildWishlists keeps it.
do
  local c = GuildOS.Client
  local was = { c.isRetail, c.isAnniversary }
  c.isRetail, c.isAnniversary = true, false
  local rr = Import:Parse(FIXTURE)
  c.isRetail, c.isAnniversary = was[1], was[2]
  check(rr.loot.wishlists["rias-firemaw"] and rr.loot.wishlists["rias-firemaw"].name == "Rias-Firemaw",
    "retail: the whole key, lowercased")
end

-- ── 2. ConsumeInbox ──────────────────────────────────────────────────
local function serialise(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. serialise(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function gameTables()
  return serialise({ GuildOS.db.softRes, GuildOS.db.lootPrios, GuildOS.db.wishlists, GuildOS.db.guildWishlists })
end
local function fresh(inbox)
  GuildOS.db = { settings = { companion = true },
    softRes = { items = { [1] = { { name = "Mine", class = "", note = "", plusOnes = 0 } } }, distributed = {} },
    lootPrios = { [2] = { { name = "Mine", class = "", order = 1 } } },
    wishlists = { me = { 3 } },
    guildWishlists = { ana = { name = "Ana", class = "MAGE", wishlist = { { itemId = 4, order = 1 } } } } }
  _G.GuildOSInbox, _G.GuildOSInboxFirst, Import._lastInbox = inbox, nil, nil
end

fresh({ FIXTURE })
local before = gameTables()
check(Import:ConsumeInbox() == true, "the inbox is taken")
local site = GuildOS.db.siteLoot
local entry = site and site.raids and site.raids["raid-556-fixture"]
check(entry and entry.startsAt == 1795000000 and site.at == time(), "db.siteLoot holds the raid by its id, stamped with the read")
check(entry.softres.items[30106][1].hard == true and entry.softres.hidden == true, "with the reserves")
check(entry.prios[30104][2].name == "Rias" and entry.wishlists["dora"].name == "Dora", "the prios and the wishlists")
check(gameTables() == before, "the game's own tables are untouched")
check(Import:ConsumeInbox() == false, "an unchanged inbox is skipped")

fresh({ V5 })
before = gameTables()
check(Import:ConsumeInbox() == true and GuildOS.db.companionRoster, "a v5 roster imports")
check(GuildOS.db.siteLoot == nil, "and leaves db.siteLoot nil")
check(Import:Parse(V5).loot == nil, "roster.loot is nil with none of the three")
check(gameTables() == before, "tables untouched")

-- One entry per raid, from every roster of the inbox, replaced by raidId; a raid the inbox stops listing
-- keeps its entry until its night is over (R14), and one that lists it without loot takes it away.
fresh({ wire('{"fmt":"GOSROST1","v":6,"raidId":"early","startsAt":1000,"members":[{"name":"Ana","class":"MAGE"}]}'), FIXTURE })
Import:ConsumeInbox()
check(GuildOS.db.companionRoster.raidId == "early", "the soonest roster is still the one in hand")
check(GuildOS.db.siteLoot.raids["raid-556-fixture"] and GuildOS.db.siteLoot.raids.early == nil,
  "and the loot of a later raid is kept all the same, a raid with none has no entry")
GuildOS.db.siteLoot.raids.old = { startsAt = SERVER - 9 * 3600, softres = { items = {} } }
GuildOS.db.siteLoot.raids.tonight = { startsAt = SERVER - 3600, softres = { items = {} } }
_G.GuildOSInbox = { V5 }
Import:ConsumeInbox()
local kept = GuildOS.db.siteLoot.raids
check(kept["raid-556-fixture"] and kept.tonight, "an inbox that no longer lists a raid keeps it while its night lasts")
check(kept.old == nil, "and drops what is past its window")
_G.GuildOSInbox = { wire('{"fmt":"GOSROST1","v":6,"raidId":"raid-556-fixture","startsAt":1795000000,"members":[{"name":"Ana","class":"MAGE"}]}') }
Import:ConsumeInbox()
check(GuildOS.db.siteLoot.raids["raid-556-fixture"] == nil, "a raid listed again with none loses its entry")
SERVER = SERVER + 9 * 3600
_G.GuildOSInbox = { V5, FIXTURE:sub(1, -1) .. "" }
Import._lastInbox = nil
Import:ConsumeInbox()
check(GuildOS.db.siteLoot and GuildOS.db.siteLoot.raids.tonight == nil, "later, the night is over and goes")
SERVER = 1795000000

-- ── 3. Refusals ──────────────────────────────────────────────────────
local function inboxOf(raw)
  fresh({ raw })
  before = gameTables()
  local ok, e = pcall(Import.ConsumeInbox, Import)
  check(ok, "the login does not throw: " .. tostring(e))
  check(gameTables() == before, "the game's tables stay as they were")
  return GuildOS.db.siteLoot
end

-- The whole roster is refused.
local good = FIXTURE:gsub("^GOSROST1:", "")
check(Import:Parse("GOSROST1:" .. good:sub(1, 20) .. "!" .. good:sub(21)) == nil, "a body out of the alphabet is refused")
check(Import:Parse("GOSROST1:" .. good:sub(1, 20) .. "\0" .. good:sub(21)) == nil, "a NUL in it too")
check(inboxOf("GOSROST1:" .. good:sub(1, 20) .. "|" .. good:sub(21)) == nil and GuildOS.db.companionRoster == nil,
  "an inbox of one such body imports nothing")
check(Import:Parse("GOSROST1:" .. string.rep("A", 524289)) == nil, "a body over ROSTER_MAX is refused")
local _, bigErr = Import:Parse("GOSROST1:" .. string.rep("A", 524289))
check(bigErr == "The roster string is damaged. Copy it again.", "with the answer a damaged body gets")
check(Import:Parse("GOSROST1:" .. string.rep("A", 100)) == nil, "and a short one that decodes to nothing")
check(Import:Parse("  copied:\n" .. FIXTURE:sub(1, 30) .. "\n" .. FIXTURE:sub(31) .. "  \n"), "a code pasted with breaks still reads")

-- One field at a time.
local function lootOf(extra)
  local ro, e = Import:Parse(roster(extra))
  check(ro, "the roster still imports: " .. tostring(e))
  return ro.loot, ro
end
local function wishlist(n, id) return '"wishlists":[{"key":"Ana-Firemaw","name":"Ana","class":"MAGE","items":[' .. range(n, function(i) return ('{"id":%d,"o":%d}'):format(id or i, i) end) .. ']}]' end
local function prio(id) return ('{"id":%d,"order":[{"key":"A-F","name":"A","class":"MAGE","rank":1}]}'):format(id) end
local function soft(id, rank) return ('"softres":{"soft":[{"key":"A-F","name":"A","class":"MAGE","items":[%s]}],"hard":[]}'):format(id) end

check(lootOf(wishlist(60)).wishlists.ana, "60 items in a wishlist pass")
check(lootOf(wishlist(61)) == nil, "61 refuse the wishlist")
check(lootOf(wishlist(1, 2147483647)).wishlists.ana, "the top id passes")
check(lootOf(wishlist(1, 2147483648)) == nil, "an id of 2147483648 refuses it")
check(lootOf(wishlist(1, 0)) == nil, "id 0 refuses it")
check(lootOf('"wishlists":[{"key":"A-F","name":"Ana","class":"MAGE","items":[{"id":1.5,"o":1}]}]') == nil, "a fractional id refuses it")
check(lootOf('"wishlists":[{"key":"A-F","name":"Ana","class":"MAGE","items":[{"id":"7","o":1}]}]') == nil, "a string id refuses it")
check(lootOf('"wishlists":[{"key":"A-F","name":"Ana","class":"MAGE","items":[{"id":7,"o":61}]}]') == nil, "an order over 60 refuses it")
check(lootOf('"wishlists":[{"key":"A-F","name":"Ana","class":"MAGE","items":[{"id":7,"o":0}]}]') == nil, "and 0")
check(lootOf('"wishlists":"x"') == nil and lootOf('"wishlists":[5]') == nil, "a non-table refuses it")
check(lootOf('"wishlists":[{"key":"A-F","name":"Ana","class":"MAGE","items":[{"id":7,"o":1e400}]}]') == nil, "inf refuses it")
local nan = 0 / 0
check(Import.ReadSiteLoot({ wishlists = { { key = "A-F", name = "Ana", class = "MAGE", items = { { id = 7, o = nan } } } } }) == nil, "NaN refuses it")
check(Import.ReadSiteLoot({ wishlists = { { key = "A-F", name = "Ana", class = "MAGE", items = { { id = nan, o = 1 } } } } }) == nil, "and as an id")
check(Import.ReadSiteLoot({ prios = { { id = 5, order = { { name = "A", class = "MAGE", rank = nan } } } } }) == nil, "and as a rank")

check(lootOf('"prios":[' .. range(600, prio) .. "]").prios[600], "600 prio items pass")
check(lootOf('"prios":[' .. range(601, prio) .. "]") == nil, "601 refuse the prios")
local many = range(41, function(i) return ('{"key":"P%d-F","name":"P%d","class":"MAGE","rank":%d}'):format(i, i, 1) end)
check(lootOf('"prios":[{"id":5,"order":[' .. many .. "]}]") == nil, "41 people on an item refuse them")
check(lootOf('"prios":[{"id":5,"order":[{"key":"A-F","name":"A","class":"MAGE","rank":101}]}]') == nil, "a rank of 101 refuses them")
check(lootOf('"prios":[{"id":5.5,"order":[{"key":"A-F","name":"A","class":"MAGE","rank":1}]}]') == nil, "a fractional id too")
check(lootOf('"prios":[{"id":5,"order":[{"key":"A-F","name":"","class":"MAGE","rank":1}]}]') == nil, "an empty name too")
check(lootOf('"prios":[{"id":5,"order":[{"key":"A-F","name":"' .. string.rep("n", 65) .. '","class":"MAGE","rank":1}]}]') == nil, "a name of 65 characters too")

local longItems = range(21, function(i) return tostring(1000 + i) end)
check(lootOf(soft(longItems)) == nil, "21 reserved items for a person refuse the sheet")
check(lootOf(soft("1,2,3")).softres.items[3], "a few pass")
check(lootOf(soft("2147483648")) == nil and lootOf(soft("1.5")) == nil and lootOf(soft('"1"')) == nil, "bad ids refuse the sheet")
local soft1500 = range(1500, function(i) return ('{"key":"A%d-F","name":"A%d","class":"MAGE","items":[1]}'):format(i, i) end)
check(lootOf('"softres":{"soft":[' .. soft1500 .. '],"hard":[]}').softres.items[1][1500], "1500 soft entries pass")
check(lootOf('"softres":{"soft":[' .. soft1500 .. ',{"key":"Z-F","name":"Z","class":"MAGE","items":[1]}],"hard":[]}') == nil, "1501 refuse the sheet")
local hard200 = range(200, function(i) return ('{"id":%d,"for":"X","note":"n"}'):format(i) end)
check(lootOf('"softres":{"soft":[],"hard":[' .. hard200 .. "]}").softres.items[200][1].hard, "200 hard entries pass")
check(lootOf('"softres":{"soft":[],"hard":[' .. hard200 .. ',{"id":201,"for":"X"}]}') == nil, "201 refuse the sheet")
check(lootOf('"softres":{"soft":[],"hard":[{"id":1,"for":"X"}],"hidden":true}').softres.hidden == true, "hidden alone is kept with the sheet")
check(lootOf('"softres":{"soft":[],"hard":[{"id":1}]}') == nil, "a hard reserve for nobody has nothing to say, so the sheet is empty")

-- Names and notes are cleaned, not trusted.
local dirty = lootOf('"softres":{"soft":[{"key":"A-F","name":"A|cffff0000na\\nme\\t","class":"MAGE","note":"'
  .. string.rep("x", 300) .. '|Hitem:1|h","items":[9]}],"hard":[]}').softres.items[9][1]
check(not dirty.name:find("[|%c]"), "a name carries no pipe or control character: " .. dirty.name)
check(#dirty.note <= 140 and not dirty.note:find("|", 1, true), "a note is clipped and carries no pipe")

-- A refused field never takes the others, nor the roster, with it.
local mixed, mro = lootOf(wishlist(61) .. ',"prios":[' .. prio(7) .. "]")
check(mixed.wishlists == nil and mixed.prios[7] and mro.members[1].name == "Ana", "one bad field leaves the rest")
check(lootOf('"prios":[],"wishlists":[],"softres":{"soft":[],"hard":[]}') == nil, "nothing in any of them is nothing")

-- Through the inbox: a refused field means no siteLoot, and no exception.
check(inboxOf(roster(wishlist(61))) == nil and GuildOS.db.companionRoster, "ConsumeInbox: the roster, without the loot")
check(inboxOf(roster(wishlist(2))).raids.r1.wishlists.ana, "ConsumeInbox: and with it when it holds")

print(("site-loot: %d checks passed"):format(checks))
