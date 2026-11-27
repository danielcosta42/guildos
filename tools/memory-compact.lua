-- The compact stores of the memory work (specs/salao/memoria.md), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Core/Commands.lua, Modules/DataCollector.lua,
-- Modules/CommSystem.lua, Modules/RecipeTracker.lua, Modules/GearAudit.lua, Modules/MemberHistory.lua and
-- Modules/Digest.lua under a stubbed TBC Anniversary client:
--   * recipes: db.recipes (the old shape) becomes db.recipeIds, every reader answers as before, a second run
--     changes nothing, a list in the old shape off the network is stored compact and hashes as its sender's;
--   * gear: row.gear becomes row.gc, the readers see the same items, the broadcast the same payload, a received
--     old payload is stored compact;
--   * the member history's ceiling of 1500, once, the present and noted members kept;
--   * the account's other guild databases: listed, never the one in use deleted, the digest's hint once.
--
--   luajit -e 'ADDON="."' tools/memory-compact.lua
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

-- A deep copy and a canonical dump, to compare stores before and after a run.
local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end
local function dump(v)
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. dump(k) .. "]=" .. dump(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- ── A TBC Anniversary client ────────────────────────────────────────────
local clock = 1000
function GetTime() return clock end
function GetServerTime() return 1794500000 + clock end
function time() return 1794500000 + clock end
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end,
  NewTicker = function() return { Cancel = function() end } end }
local function advance(s)
  clock = clock + s
  local again = true
  while again do
    again = false
    for i, t in ipairs(timers) do
      if t.at <= clock then table.remove(timers, i); t.fn(); again = true; break end
    end
  end
end
strmatch, strlower, strsplit, tinsert, format = string.match, string.lower, nil, table.insert, string.format
function strsplit(sep, s)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return unpack(out)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
dofile(ADDON .. "/Libs/LibStub.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(_, fn) self.onEvent = fn end
  function f:Hide() end
  function f:Show() end
  frames[#frames + 1] = f
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 70 end
function UnitRace() return "Orc", "Orc" end
function UnitSex() return 2 end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Member", 5 end
local ROSTER = { { "Me-Realm", 5 }, { "Bob-Realm", 5 }, { "Cid-Realm", 5 } }
function GetNumGuildMembers() return #ROSTER, #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1], "Rank", r[2], 70, "Warrior", "", "", "", i ~= 3, nil, "WARRIOR" end
end
function GuildControlGetNumRanks() return 6 end
function ReloadUI() end
local sent = {}
C_ChatInfo = { SendAddonMessage = function(prefix, msg, chan, target) sent[#sent + 1] = { prefix = prefix, msg = msg,
  chan = chan, target = target } return true end, RegisterAddonMessagePrefix = function() return true end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
-- The client's names: spells always (game data), items only once cached.
local SPELLS = { [2149] = "Handstitched Leather Boots", [7418] = "Enchant Bracer - Minor Health",
  [3275] = "Linen Bandage", [2963] = "Bolt of Linen Cloth", [2330] = "Minor Healing Potion" }
local ITEMS = { [2302] = "Handstitched Leather Boots", [1251] = "Linen Bandage", [2996] = "Bolt of Linen Cloth" }
function GetSpellInfo(id) return SPELLS[id] end
function GetItemInfo(id)
  id = tonumber(tostring(id):match("item:(%d+)") or id)
  return ITEMS[id], nil, 4, 100
end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Utils.lua")
SlashCmdList = SlashCmdList or {}
dofile(ADDON .. "/Core/Commands.lua")
GuildOS.Compat.SendAddonMessage = function(prefix, msg, chan, target)
  sent[#sent + 1] = { prefix = prefix, msg = msg, chan = chan, target = target }
end
GuildOS.Dialogs = GuildOS.Dialogs or {}
local shown
GuildOS.ShowDialog = function(_, which, a1, _, data) shown = { which = which, text = a1, data = data } end

-- ── 1. Recipes: the old shape, as a version before memoria.md saved it ──
local ME, BOB, CID = "Me-Realm", "Bob-Realm", "Cid-Realm"
local LEGACY = {
  [ME] = {
    Leatherworking = { { name = "Handstitched Leather Boots", spellId = 2149, itemId = 2302 } },
    Enchanting = { { name = "Enchant Bracer - Minor Health", spellId = 7418 } },
  },
  [BOB] = {
    Leatherworking = { { name = "Handstitched Leather Boots", spellId = 2149, itemId = 2302 },
                       { name = "Mystery Item", itemId = 9999 } },   -- no spell ID, an item the cache lacks
    ["First Aid"] = { { name = "Linen Bandage", spellId = 3275, itemId = 1251 } },
  },
  [CID] = {
    Tailoring = { { name = "Bolt of Linen Cloth", spellId = 2963, itemId = 2996 }, { name = "Nothing Known" } },
    Leatherworking = { { name = "Handstitched Leather Boots" } },     -- a name only: enriched by name
  },
}
GuildOS.db = { settings = {}, members = {}, myData = {}, recipes = copy(LEGACY) }
GuildOS.guildKey, GuildOS.isGuilded = "Guild-Realm", true
GuildOSDB = { ["Guild-Realm"] = GuildOS.db, accountChars = { ["Alt-Realm"] = { name = "Alt" } } }
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/DataCollector.lua")
dofile(ADDON .. "/Modules/RecipeTracker.lua")
local CS, DC, RT = GuildOS.CommSystem, GuildOS.DataCollector, GuildOS.RecipeTracker
local LibSerialize = LibStub("GuildOS-LibSerialize")
check(RT.Hash(LEGACY[ME].Leatherworking) ~= nil, "the wire's hash of a list in the old shape")
local oldHash = {}
for key, profs in pairs(LEGACY) do
  for prof, list in pairs(profs) do oldHash[key .. "|" .. prof] = RT.Hash(list) end
end

-- The codec, pure.
local packed = RT.Pack(LEGACY[BOB].Leatherworking, false)
check(packed[1] == 2149 and packed[2] == 2302 and packed[3] == 0 and packed[4] == 9999 and #packed == 4,
  "two numbers a recipe, 0 where the scan had none")
check(packed.nm and packed.nm[1] == nil and packed.nm[2] == "Mystery Item",
  "a name only where no spell ID gives it back")
check(packed.h == RT.Hash(LEGACY[BOB].Leatherworking) and RT.ListHash(packed) == packed.h, "the hash the wire computes, kept")
check(RT.Count(packed) == 2 and RT.Count(LEGACY[BOB].Leatherworking) == 2 and RT.Count(nil) == 0, "Count, either shape")
local wire = RT.Wire(packed)
check(#wire == 2 and wire[1].name == "Handstitched Leather Boots" and wire[1].spellId == 2149 and wire[1].itemId == 2302
  and wire[2].name == "Mystery Item" and wire[2].spellId == nil and wire[2].itemId == 9999,
  "back to the old shape, the spell's name from the client")
local mine = RT.Pack(LEGACY[ME].Leatherworking, true)
check(mine.nm[1] == "Handstitched Leather Boots" and RT.Hash(RT.Wire(mine)) == RT.Hash(LEGACY[ME].Leatherworking),
  "an own list keeps every name: what goes out hashes as before")
check(dump(RT.Pack(packed, false)) == dump(packed), "packing a compact list again changes nothing")
local n = 0
for _, s, it, name in RT.Each(LEGACY[BOB].Leatherworking) do
  n = n + 1
  if n == 2 then check(s == nil and it == 9999 and name == "Mystery Item", "Each reads the old shape too") end
end
check(n == 2, "Each walks every recipe")

-- The migration, at the module's start.
printed = {}
RT:Initialize()
local db = GuildOS.db
check(db.recipes == nil and type(db.recipeIds) == "table" and db.schema.recipes == RT.SCHEMA,
  "db.recipes is gone, db.recipeIds holds the lists, the schema says so")
check(db.recipeIds[ME].Leatherworking.nm[1] == "Handstitched Leather Boots" and db.recipeIds[BOB]["First Aid"].nm == nil,
  "the own character's names stay, a guildmate's spell names go")
local after = dump(db.recipeIds)
RT.MigrateDB(db, RT:OwnKeys())
RT:EnrichStoredRecipes()
check(dump(db.recipeIds) == after, "a second run changes nothing")
local said = table.concat(printed, "\n")
check(said:find("enriched 1 entries", 1, true) and said:find("purged 1 old entries", 1, true),
  "the name-only recipe is enriched from the guild's names, the unknown one purged, as before")
check(db.recipeIds[CID].Leatherworking[1] == 2149 and db.recipeIds[CID].Leatherworking.h == oldHash[CID .. "|Leatherworking"],
  "enriched in place, the hash the sender announced kept")

-- What every reader answers: the same as the version before. EXPECTED is what Modules/RecipeTracker.lua before
-- memoria.md answered over this same db.recipes (run once against it, same harness, same summary()).
local function summary()
  local parts = {}
  local idx = RT:BuildRecipeIndex()
  local rows = {}
  for _, e in ipairs(idx) do
    local who = {}
    for _, c in ipairs(e.crafters) do who[#who + 1] = c.playerKey end
    table.sort(who)
    rows[#rows + 1] = string.format("%s|%s|%s|%s|%s", e.profName, e.name, tostring(e.spellId), tostring(e.itemId),
      table.concat(who, ","))
  end
  table.sort(rows)
  parts[#parts + 1] = table.concat(rows, ";")
  parts[#parts + 1] = table.concat(RT:GetAllProfessions(), ",")
  for _, item in ipairs({ 2302, 1251, 2996, 9999, 1 }) do
    RT._itemCrafterIndex = nil
    local c = RT:GetCraftersForItem(item)
    local who = {}
    for _, x in ipairs(c or {}) do who[#who + 1] = x.playerKey .. ":" .. x.profName end
    table.sort(who)
    parts[#parts + 1] = item .. "=" .. table.concat(who, ",")
  end
  for _, spell in ipairs({ 2149, 7418, 3275 }) do
    local c = RT:GetCraftersForSpell(spell)
    local who = {}
    for _, x in ipairs(c or {}) do who[#who + 1] = x.playerKey end
    table.sort(who)
    parts[#parts + 1] = "s" .. spell .. "=" .. table.concat(who, ",")
  end
  parts[#parts + 1] = "local=" .. tostring(RT:LocalCrafts(2302)) .. "," .. tostring(RT:LocalCrafts(1251))
  local hs = RT:OwnHashes() or {}
  parts[#parts + 1] = "own=" .. tostring(hs.Leatherworking == oldHash[ME .. "|Leatherworking"]) .. ","
    .. tostring(hs.Enchanting == oldHash[ME .. "|Enchanting"])
  return table.concat(parts, "\n")
end
local EXPECTED = table.concat({
  "Enchanting|Enchant Bracer - Minor Health|7418|nil|Me-Realm;First Aid|Linen Bandage|3275|1251|Bob-Realm;"
    .. "Leatherworking|Handstitched Leather Boots|2149|2302|Bob-Realm,Cid-Realm,Me-Realm;"
    .. "Leatherworking|Mystery Item|nil|9999|Bob-Realm;Tailoring|Bolt of Linen Cloth|2963|2996|Cid-Realm",
  "Enchanting,First Aid,Leatherworking,Tailoring",
  "2302=Bob-Realm:Leatherworking,Me-Realm:Leatherworking",   -- Cid's enriched recipe has no item: as before
  "1251=Bob-Realm:First Aid", "2996=Cid-Realm:Tailoring", "9999=Bob-Realm:Leatherworking", "1=",
  "s2149=Bob-Realm,Cid-Realm,Me-Realm", "s7418=Me-Realm", "s3275=Bob-Realm",
  "local=Leatherworking,nil", "own=true,true",
}, "\n")
local got = summary()
check(got == EXPECTED, "every reader answers as the old store did:\n" .. got)
local counted = 0
for key, prof in RT:EachList() do counted = counted + RT:CountOf(key, prof) end
check(counted == 7, "the recipes panel's count: 7 recipes indexed, as before (" .. counted .. ")")

-- A list in the old shape off the network (any version sends it): stored compact, hashing as its sender's.
local incoming = { { name = "Heavy Linen Bandage", spellId = 3276, itemId = 2581 }, { name = "Linen Bandage", spellId = 3275, itemId = 1251 } }
RT:HandleIncoming(BOB, LibSerialize:Serialize({ prof = "First Aid", recipes = incoming }))
local held = db.recipeIds[BOB]["First Aid"]
check(held[1] == 3276 and held[3] == 3275 and held.nm == nil and held.h == RT.Hash(incoming),
  "a received list in the old shape is kept compact, with its sender's hash")
sent = {}
GuildOS.CommSystem.SendMessage = function(_, t) sent[#sent + 1] = { t = t } end
RT:OnHashes(BOB, BOB, { ["First Aid"] = RT.Hash(incoming) })
check(#sent == 0, "the sender's announced hash matches: nothing is asked")
RT:OnHashes(BOB, BOB, { ["First Aid"] = 12345 })
check(#sent == 1 and sent[1].t == "RA", "a different hash is asked for")
-- A member broadcast of a version before audit D3, its lists inside.
DC:StoreReceivedData(CID, { name = "Cid", class = "MAGE", lastUpdate = time(),
  recipes = { Alchemy = { { name = "Minor Healing Potion", spellId = 2330, itemId = 118 } } } })
check(db.recipeIds[CID].Alchemy[1] == 2330 and db.recipeIds[CID].Alchemy[2] == 118 and db.members[CID].recipes == nil,
  "an old member broadcast's lists go to the compact store, not the member row")
-- A name only, from a client that read no IDs: the member's own earlier list gives the spell ID.
RT:Put(CID, "Alchemy", { { name = "Minor Healing Potion" } }, false)
check(db.recipeIds[CID].Alchemy[1] == 2330, "a name-only recipe takes the spell ID the member had for it")
-- My answer to an ask: the old shape, every name, hashing as my broadcast says.
local answered
RT.BroadcastRecipes = function(_, prof, list) answered = { prof = prof, list = list } end
RT:OnAsk(BOB, "Leatherworking")
advance(RT.ASK_GATHER + 1)
check(answered and answered.list[1].name == "Handstitched Leather Boots" and answered.list[1].itemId == 2302
  and RT.Hash(answered.list) == RT:OwnHashes().Leatherworking, "an answer goes in the old shape, as announced")
-- An older version ran meanwhile (a downgrade, then this one again): its db.recipes is taken in on the next read.
db.recipes = { [BOB] = { Tailoring = { { name = "Bolt of Linen Cloth", spellId = 2963, itemId = 2996 } } } }
check(RT:CountOf(BOB, "Tailoring") == 1 and db.recipes == nil and db.recipeIds[BOB]["First Aid"],
  "what an older version wrote is converted on the next read, the compact lists kept")

-- ── 2. Gear ─────────────────────────────────────────────────────────────
local G = GuildOS.Gear
local LINK = "|cffa335ee|Hitem:28830:2564:24027:24030:0:0:-12:0:70|h[Dragonspine Trophy]|h|r"
local OLDGEAR = {
  [1] = { link = LINK, id = 28830, name = "Dragonspine Trophy", quality = 4, ilvl = 125, enchantId = 2564,
          gems = { { id = 24027 }, { id = 24030 } }, suffix = -12 },
  [5] = { id = 30101, name = "Chestguard: of the Eagle", quality = 3, ilvl = 115, gems = {} },
  [16] = { id = 28438, name = "Dragonmaw", quality = 4, ilvl = 123, enchantId = 2673, gems = {} },
  [17] = { id = 28825, name = "Aldori Legacy Defender", quality = 4, ilvl = 123, gems = {} },
  [8] = { id = 1, name = "", quality = 0, ilvl = 0, gems = {} },
}
local s1 = G.Pack(OLDGEAR[1])
check(s1 == "28830:2564:24027.24030:-12:125:4\tDragonspine Trophy\t" .. LINK, "one string a slot: " .. s1)
for slot, item in pairs(OLDGEAR) do
  local back = G.Unpack(G.Pack(item))
  check(back.id == item.id and back.name == item.name and back.quality == item.quality and back.ilvl == item.ilvl
    and back.enchantId == item.enchantId and back.suffix == item.suffix and back.link == item.link
    and #back.gems == #item.gems and (item.gems[1] == nil or back.gems[1].id == item.gems[1].id),
    "slot " .. slot .. " comes back as it was")
end
check(G.Unpack("junk") == nil and G.Pack(42) == nil and G.Pack("x") == "x", "malformed input is refused")
db.members[BOB] = { name = "Bob", class = "MAGE", lastUpdate = 1, avgIlvl = 120, gear = copy(OLDGEAR) }
db.members[CID].gear = { [1] = copy(OLDGEAR[16]) }
dofile(ADDON .. "/Modules/GearAudit.lua")
local GA = GuildOS.GearAudit
local before = { missing = table.concat(GA:MissingEnchants(db.members[BOB].gear), ","),
                 avg = DC:CalculateAvgIlvl(db.members[BOB].gear) }
check(G.MigrateDB(db) == 2 and db.schema.gear == G.SCHEMA and db.members[BOB].gear == nil
  and type(db.members[BOB].gc[1]) == "string", "the rows' gear becomes one string a slot")
local gAfter = dump(db.members)
check(G.MigrateDB(db) == 0 and dump(db.members) == gAfter, "a second run changes nothing")
local view = GuildOS:MemberGear(db.members[BOB])
check(view[1].link == LINK and view[1].gems[2].id == 24030 and view[5].enchantId == nil and view[3] == nil,
  "the readers' fields, decoded on read")
check(table.concat(GA:MissingEnchants(view), ",") == before.missing and DC:CalculateAvgIlvl(view) == before.avg,
  "the enchant audit and the average item level read the same")
check(table.concat(G.Slots(view), ",") == "1,5,8,16,17", "the slots held")
local rec = GuildOS:GetMemberRecord("Bob")
check(rec and rec.gear and rec.gear[16].name == "Dragonmaw", "the member record carries the decoded gear")
-- A received payload in the old shape (the wire keeps it) is stored compact.
DC:StoreReceivedData(BOB, { name = "Bob", class = "MAGE", lastUpdate = 2,
  gear = { [1] = { id = 28830, name = "Dragonspine Trophy", quality = 4, ilvl = 125, gems = { { id = 24027 } } } } })
check(db.members[BOB].gear == nil and db.members[BOB].gc[1] == "28830::24027::125:4\tDragonspine Trophy"
  and db.members[BOB].gc[5] == nil, "a received old payload replaces the row's gear, compact")
-- My own broadcast: the same payload as before, from the compact row.
db.members[ME] = { name = "Me", class = "WARRIOR", lastUpdate = 3, gear = copy(OLDGEAR) }
db.myData = db.members[ME]
local function wireOf(gear)
  local out = {}
  for slot, item in pairs(gear) do
    local e = { id = item.id, name = item.name, quality = item.quality, ilvl = item.ilvl, enchantId = item.enchantId,
      suffix = item.suffix }
    if item.gems and #item.gems > 0 then
      e.gems = {}
      for _, gem in ipairs(item.gems) do e.gems[#e.gems + 1] = { id = gem.id } end
    end
    out[slot] = e
  end
  return out
end
local oldWire = dump(wireOf(OLDGEAR))
check(dump(DC:GetBroadcastData().gear) == oldWire, "an old-shape row broadcasts as before")
G.Normalize(db.members[ME])
check(dump(DC:GetBroadcastData().gear) == oldWire, "and the compact row broadcasts the same payload")

-- ── 3. The member history's ceiling ────────────────────────────────────
dofile(ADDON .. "/Modules/MemberHistory.lua")
local MH = GuildOS.MemberHistory
check(MH.MAX_KEYS == 1500, "MAX_KEYS is 1500")
-- A history grown to 4000 keys under the old ceiling: 1000 present members, 3000 who left (K<i> left at time i).
local h = {}
for i = 1, 4000 do
  local left = (i % 4 ~= 0) and (1000000 + i) or nil
  h["K" .. i] = { stints = { { joinAt = 1, leftAt = left } }, ranks = { { at = 1, to = "Member" } } }
end
h.K1.note = { text = "kept", ts = 1 }   -- the member who left first, with a permanent note
local hdb = { memberHistory = h }
local gone = MH.MigrateDB(hdb)
local present, keys = 0, 0
for _, r in pairs(h) do
  keys = keys + 1
  if r.stints[1].leftAt == nil then present = present + 1 end
end
check(gone == 2500 and keys == 1500, "the history is cut to 1500 keys: " .. gone .. " went, " .. keys .. " stay")
check(present == 1000 and h.K1 ~= nil and h.K2 == nil and h.K3998 ~= nil and h.K3999 ~= nil,
  "every present member stays, the noted one too, the oldest departures go first")
check(hdb.schema.history == MH.SCHEMA and MH.MigrateDB(hdb) == 0, "once: the schema says it ran")

-- ── 4. The account's guild databases ───────────────────────────────────
local NOW = time()
GuildOSDB["Old Guild-Realm"] = { members = { a = { name = "A" } }, _opened = NOW - 100 * 86400 }
GuildOSDB["_noguild-Realm"] = { settings = {} }
GuildOSDB["Recent-Other-Realm"] = { members = {}, _opened = NOW - 5 * 86400 }
GuildOS:StampGuildDBs(NOW)
check(db._opened == NOW and GuildOSDB["_noguild-Realm"]._opened == NOW and GuildOSDB["_noguild-Realm"]._openedEst,
  "the one in use is stamped now; one never stamped, first seen now")
local list = GuildOS:GuildDatabases()
check(#list == 4 and list[1].current and list[1].key == "Guild-Realm" and list[1].bytes > 0, "the one in use first, with a size")
local byKey = {}
for _, e in ipairs(list) do byKey[e.key] = e end
check(byKey["Recent-Other-Realm"].name == "Recent" and byKey["Recent-Other-Realm"].realm == "Other-Realm"
  and byKey["_noguild-Realm"].noGuild and GuildOS:GuildDBLabel(byKey["_noguild-Realm"]) == "No guild (Realm)",
  "the guild's name, its realm (dashes and all), and the guildless one")
check(GuildOS:DeleteGuildDB("Guild-Realm") == false and GuildOSDB["Guild-Realm"] == db, "the one in use is never deleted")
check(GuildOS:DeleteGuildDB("accountChars") == false and GuildOSDB.accountChars, "an account table is no guild database")
local stale = GuildOS:StaleGuildDBs(NOW)
check(#stale == 1 and stale[1] == "Old Guild-Realm", "not opened in 90 days: the old one only")
local line = GuildOS:StaleGuildDBLine(NOW)
check(line and line:find("1 guild database", 1, true), "the digest's hint")
GuildOS:MarkStaleGuildDBsTold(stale)
check(GuildOS:StaleGuildDBLine(NOW) == nil, "said once")
check(GuildOS:AskDeleteGuildDB("Guild-Realm") == false and shown == nil, "no Delete for the one in use")
local refreshed = false
check(GuildOS:AskDeleteGuildDB("Old Guild-Realm", function() refreshed = true end) and shown
  and shown.which == "GUILDOS_DELETE_GUILD_DB" and shown.text == "Old Guild (Realm)" and GuildOSDB["Old Guild-Realm"],
  "Delete asks first, naming the guild; nothing gone yet")
GuildOS.Dialogs.GUILDOS_DELETE_GUILD_DB.OnAccept({ data = shown.data })
check(GuildOSDB["Old Guild-Realm"] == nil and refreshed and GuildOSDB._staleDbTold["Old Guild-Realm"] == nil,
  "confirmed, it goes, and the page is refreshed")
check(GuildOSDB["Recent-Other-Realm"] and GuildOSDB["_noguild-Realm"], "nothing else goes")
check(GuildOS.EstimateBytes({ a = "xy", [1] = 5, t = { b = true } }) == 4 + (1 + 7 + 2 + 4) + (10 + 10) + (1 + 7) + 4 + (1 + 7 + 6),
  "the size estimate counts keys, values and their punctuation")

-- ── 5. /gos debug mem ───────────────────────────────────────────────────
printed = {}
GuildOS:PrintCompactSizes(db)
local out = table.concat(printed, "\n")
check(out:find("Recipes (compact):", 1, true) and out:find("gear compact on", 1, true) and out:find("Member history:", 1, true),
  "/gos debug mem prints the compact stores")

print("memory-compact: " .. checks .. " checks passed")
