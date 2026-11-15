-- The upload's receipt of the cores (issue #347, the site's #519) is never one the site refuses whole,
-- run against the real Core, Compat, Utils, CoreManager, CompanionExport and CompanionImport under a
-- stubbed client:
--
--   * a core is never named in game as the site refuses: Create and Rename refuse a `|`, a control
--     character, a name over 48 bytes and constructor / prototype / __proto__, saying why;
--   * a guest is the key it was added under (with its realm); its name is cut on a character and never
--     carries a `|` or a control character, from an officer's typing, another officer's message or a
--     migrated member's record;
--   * the receipt builder, from every edge-case state below, written straight into the db (cores from
--     before these checks, the site's own names, another officer's guests), gives what the site's door
--     reads: the site's rules are re-implemented below (siteRefuses) from guildos-web
--     apps/web/lib/core-receipt.ts `cleanReceipt` / `isName`, and must be kept in step with it. What
--     it leaves out goes to /gos errors.
--
--   luajit -e 'ADDON="."' tools/core-receipt.lua
--   RECEIPTS_OUT=/path/receipts.txt luajit -e 'ADDON="."' tools/core-receipt.lua   -- also writes each
--     receipt as "label<TAB>json", to run once through the site's real cleanReceipt
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

-- ── The site's door, in Lua ─────────────────────────────────────────────
-- A mirror of guildos-web apps/web/lib/core-receipt.ts (RECEIPT_CAPS, isName, cleanReceipt). Change it
-- with that file, never to make a check here pass. Returns nil when the site keeps the receipt, else
-- the place it failed, as the site says it.
local CAPS = { cores = 50, name = 48, guests = 40, tag = 40, size = 40, members = 1000 }
local CLOCK_MAX = 4294967295   -- the site's CLOCK_MAX: 2^32 - 1, the year 2106 (site #519)
local PROTO = { __proto__ = true, constructor = true, prototype = true }

-- JavaScript decodes the upload: a byte sequence that is not UTF-8 becomes U+FFFD (three bytes).
local function decodedBytes(s)
  local i, n, out = 1, #s, 0
  while i <= n do
    local c = s:byte(i)
    local need, lo, hi = 0, 0x80, 0xBF
    if c < 0x80 then need = 0
    elseif c >= 0xC2 and c <= 0xDF then need = 1
    elseif c == 0xE0 then need, lo = 2, 0xA0
    elseif c == 0xED then need, hi = 2, 0x9F
    elseif c >= 0xE1 and c <= 0xEF then need = 2
    elseif c == 0xF0 then need, lo = 3, 0x90
    elseif c >= 0xF1 and c <= 0xF3 then need = 3
    elseif c == 0xF4 then need, hi = 3, 0x8F
    else need = -1 end
    local ok = need >= 0
    for j = 1, math.max(need, 0) do
      local b = s:byte(i + j)
      if not b or b < (j == 1 and lo or 0x80) or b > (j == 1 and hi or 0xBF) then ok = false break end
    end
    if ok then out, i = out + need + 1, i + need + 1 else out, i = out + 3, i + 1 end
  end
  return out
end
-- String.prototype.trim(): ASCII white space, U+00A0, U+1680, U+2000-200A, U+2028/9, U+202F, U+205F,
-- U+3000, U+FEFF.
local function jsTrimEmpty(s)
  local bare = s:gsub("[ \t\n\v\f\r]", ""):gsub("\194\160", ""):gsub("\225\154\128", "")
    :gsub("\226\128[\128-\138\168\169\175]", ""):gsub("\226\129\159", ""):gsub("\227\128\128", ""):gsub("\239\187\191", "")
  return bare == ""
end
local function isName(v)
  return type(v) == "string" and not jsTrimEmpty(v) and decodedBytes(v) <= CAPS.name
    and not v:find("[%z\1-\31\127|]") and not PROTO[v]
end
local function isInt(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end
local function onlyKeys(o, keys)
  local ok = {}
  for _, k in ipairs(keys) do ok[k] = true end
  for k in pairs(o) do if not ok[k] then return k end end
end
local function isList(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end
local function isTag(t)
  if t == "" then return true end
  return #t <= CAPS.tag and t:find("^[a-z0-9%-]+$") ~= nil and not t:find("^%-") and not t:find("%-$")
    and not t:find("%-%-") and not PROTO[t]
end
local function siteRefuses(raw)
  if type(raw) ~= "table" then return "not an object" end
  local extra = onlyKeys(raw, { "at", "linkedAt", "cores" })
  if extra then return "unknown key " .. tostring(extra) end
  if not isInt(raw.at, 1, CLOCK_MAX) then return "at" end
  if not isInt(raw.linkedAt, 0, CLOCK_MAX) then return "linkedAt" end
  if not isList(raw.cores) then return "cores" end
  if #raw.cores > CAPS.cores then return "cores: more than " .. CAPS.cores end
  local tags, names = {}, {}
  for i, c in ipairs(raw.cores) do
    local at = ("cores[%d]"):format(i - 1)
    if type(c) ~= "table" then return at end
    local odd = onlyKeys(c, { "tag", "name", "size", "members", "fromDiscord", "guests", "importedAt" })
    if odd then return at .. ": unknown key " .. tostring(odd) end
    if type(c.tag) ~= "string" or not isTag(c.tag) then return at .. ".tag" end
    if c.tag ~= "" and tags[c.tag] then return at .. ".tag repeated" end
    if not isName(c.name) then return at .. ".name" end
    if names[c.name] then return at .. ".name repeated" end
    if not isInt(c.size, 1, CAPS.size) then return at .. ".size" end
    if not isInt(c.members, 0, CAPS.members) then return at .. ".members" end
    if not isInt(c.fromDiscord, 0, c.members) then return at .. ".fromDiscord" end
    if not isInt(c.importedAt, 0, CLOCK_MAX) then return at .. ".importedAt" end
    if c.tag == "" and c.importedAt ~= 0 then return at .. ": a core only in the game was never imported" end
    local guests = c.guests == nil and {} or c.guests
    if not isList(guests) or #guests > CAPS.guests then return at .. ".guests" end
    local seen = {}
    for j, g in ipairs(guests) do
      if not isName(g) or seen[g] then return ("%s.guests[%d]"):format(at, j - 1) end
      seen[g] = true
    end
    if c.tag ~= "" then tags[c.tag] = true end
    names[c.name] = true
  end
  return nil
end

-- The mirror itself refuses what the site refuses (the reviewer's states, through the real door).
check(siteRefuses({ at = 5, linkedAt = 0, cores = {} }) == nil, "the mirror keeps an empty receipt")
local function one(core)
  local c = { tag = "", name = "Alfa", size = 10, members = 0, fromDiscord = 0, guests = {}, importedAt = 0 }
  for k, v in pairs(core) do c[k] = v end
  return { at = 5, linkedAt = 0, cores = { c } }
end
check(siteRefuses(one({ name = "Kara || Sexta" })) == "cores[0].name", "the mirror refuses a pipe")
check(siteRefuses(one({ name = "constructor" })) == "cores[0].name", "and an object's own key")
check(siteRefuses(one({ name = ("a"):rep(49) })) == "cores[0].name", "and 49 bytes")
check(siteRefuses(one({ name = "a" .. ("é"):rep(23) .. "\195" })) == "cores[0].name", "and a character cut in two")
check(siteRefuses(one({ name = "\194\160 " })) == "cores[0].name", "and a name of spaces")
check(siteRefuses(one({ guests = { "Foo", "Foo" } })) == "cores[0].guests[1]", "and a guest twice")
check(siteRefuses(one({ tag = "", importedAt = 3 })) ~= nil, "and an import of a core only in the game")

-- ── The addon under a stubbed client ────────────────────────────────────
local printed, sent, handlers = {}, {}, {}
local NOW, recorded = 1790000000, {}
local function load(game)
  printed, sent, handlers, NOW, recorded = {}, {}, {}, 1790000000, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    function f:Hide() end
    function f:Show() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Lead", "Er" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Leader" end
  end
  function GetRealmName() return "Firemaw" end
  function GetTime() return 1 end
  function GetServerTime() return NOW end
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return "Nucleo BR", "Rank", 1 end
  function GetNumGuildMembers() return 0 end
  function GetGuildRosterInfo() end
  function UnitClass() return "Mage", "MAGE" end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  C_Timer = { After = function() end,
              NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  local registry = {}
  LibStub = setmetatable({
    NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
    GetLibrary = function(_, name) return registry[name] end,
    minor = 1,
  }, { __call = function(_, name) return registry[name] end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.db = { settings = { companion = true, officerMaxRank = 1 }, members = {}, altLinks = {}, cores = {},
                 raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
  dofile(ADDON .. "/Libs/LibDeflate.lua")
  dofile(ADDON .. "/Modules/CompanionExport.lua")
  dofile(ADDON .. "/Modules/CompanionImport.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  GuildOS.SyncService = {
    On = function(_, domain, fn) handlers[domain] = fn end,
    Publish = function(_, domain, act, data) sent[#sent + 1] = { domain = domain, act = act, data = data } end,
  }
  GuildOS.IsOfficerByName = function() return true end
  GuildOS.RecordError = function(_, msg) recorded[#recorded + 1] = msg end
  GuildOSInbox, GuildOSInboxAck = nil, nil
  GuildOS.CoreManager:Initialize()
  return GuildOS.CoreManager
end
local function package(cores) return { guild = "Nucleo BR", realm = "Firemaw", unlinked = 0, at = 1000, cores = cores } end
local function alfa() return { tag = "nucleo-alfa", name = "Núcleo Alfa", size = 10,
  members = { { key = "Ana-Firemaw", name = "Ana", class = "PRIEST", slot = "healer" } } } end

local out = os.getenv("RECEIPTS_OUT") and io.open(os.getenv("RECEIPTS_OUT"), "w")
local states = 0
local function sweep(label, wantCores, wantLeft)
  local receipt = GuildOS.Companion.CoreReceipt()
  states = states + 1
  local why = siteRefuses(receipt)
  check(why == nil, label .. ": the site keeps the receipt (" .. tostring(why) .. "): " .. GuildOS.Companion.EncodeJson(receipt))
  if wantCores then check(#receipt.cores == wantCores, label .. ": " .. wantCores .. " cores sent, got " .. #receipt.cores) end
  if wantLeft then
    local said = recorded[#recorded] or ""
    check(said:find(wantLeft, 1, true) ~= nil, label .. ": /gos errors says what was left out: " .. said)
  end
  if out then out:write(label, "\t", GuildOS.Companion.EncodeJson(receipt), "\n") end
  return receipt
end

for _, game in ipairs({ "anniversary", "forever" }) do
  local function G(what) return game .. ": " .. what end

  -- ── At the source: a core's name ──────────────────────────────────────
  local CM = load(game)
  local LONG = "Raide de Quinta-feira da Guilda Nucleo BR Grupo A1"   -- 50 bytes
  for _, bad in ipairs({ "Kara || Sexta", "Kara\nSexta", "Kara\127", LONG, ("é"):rep(25), "constructor", "prototype",
                         "__proto__", "Alfa\226\128", "   " }) do
    local ok, why = CM:Create(bad)
    check(not ok and type(why) == "string" and GuildOS.db.cores[bad] == nil, G("no core is created as " .. bad:gsub("%c", "?")))
  end
  local _, why = CM:Create(LONG)
  check(why == "A core's name has at most 48 bytes (a letter with an accent is two).", G("the long name says why"))
  _, why = CM:Create("Kara || Sexta")
  check(why == "A core's name cannot have | or control characters, nor be constructor, prototype or __proto__.",
    G("the pipe says why"))
  check(CM:Create(("é"):rep(24)) and CM:Create("Núcleo Ômega"), G("48 bytes of accents, and accents, are a name"))
  check(CM:Create("Kara"), G("a plain name is created"))
  for _, bad in ipairs({ "Kara | Sexta", LONG, "constructor" }) do
    check(not CM:Rename("Kara", bad) and GuildOS.db.cores.Kara and not GuildOS.db.cores[bad], G("nor renamed to " .. bad))
  end
  check(CM:GetCore("constructor") == nil and GuildOS.db.cores.constructor == nil, G("a raid tag no core may have makes none"))
  handlers["core.roster"]({ act = "update", data = { coreName = "Raid | x", members = {} } }, "Officer-Firemaw")
  check(GuildOS.db.cores["Raid | x"] == nil, G("nor another officer's roster under it"))
  sweep(G("cores named in game"), 3)

  -- ── At the source: a guest ────────────────────────────────────────────
  CM = load(game)
  CM:ImportFromSite(package({ alfa() }), 1000)
  check(CM:AddGuestByName("Foo-Gehennas", "rdps", "Núcleo Alfa") and CM:AddGuestByName("Foo", "rdps", "Núcleo Alfa"),
    G("two pugs named Foo, of two realms"))
  local guests = GuildOS.db.cores["Núcleo Alfa"].guests
  check(guests[GuildOS:GetPlayerKey("Foo", "Gehennas")] and guests[GuildOS:GetPlayerKey("Foo")], G("are two guests, by key"))
  check(not CM:AddGuestByName("Bob|cff", "rdps", "Núcleo Alfa"), G("a typed name with a pipe is refused"))
  handlers["core.roster"]({ act = "guests", data = { coreName = "Núcleo Alfa", tag = "nucleo-alfa", put = {
    ["Bob-Firemaw"] = { name = "Bob|cffff0000", class = "MAGE" }, ["Cy|x-Firemaw"] = { name = "Cy" },
    ["Di-Firemaw"] = { name = "Di\0" }, ["Ed-Firemaw"] = { name = ("ж"):rep(30) } } } }, "Officer-Firemaw")
  local bob = guests[GuildOS:LocalMemberKey("Bob-Firemaw")]
  check(bob and bob.name == "Bob", G("another officer's guest named with a pipe is shown by the key's name"))
  check(guests[GuildOS:LocalMemberKey("Cy|x-Firemaw")] == nil, G("a key with a pipe is no guest"))
  check(guests[GuildOS:LocalMemberKey("Di-Firemaw")].name == "Di", G("nor a control character"))
  local ed = guests[GuildOS:LocalMemberKey("Ed-Firemaw")].name
  check(#ed == 48 and GuildOS:IsUtf8(ed), G("a long Cyrillic name is cut on a character"))
  local r = sweep(G("namesakes and a peer's pipe"), 1)
  local shown = table.concat(r.cores[1].guests, ",")
  check(shown:find("Foo-Firemaw", 1, true) and shown:find("Foo-Gehennas", 1, true) and not shown:find("Foo,", 1, true),
    G("two guests of one name are sent with their realms, both: " .. shown))
  -- A migrated pug: a member's record from before, long and multibyte.
  CM = load(game)
  GuildOS.db.cores["Alfa"] = { name = "Alfa", discordTag = "alfa",
    members = { ["X-Firemaw"] = { name = "a" .. ("é"):rep(24), class = "MAGE" }, ["Y|z-Firemaw"] = { name = "Y" } } }
  CM:Initialize()
  local x = GuildOS.db.cores.Alfa.guests["X-Firemaw"]
  check(x and #x.name == 47 and GuildOS:IsUtf8(x.name), G("a migrated guest's long name is cut on a character"))
  check(GuildOS.db.cores.Alfa.members["Y|z-Firemaw"] and not GuildOS.db.cores.Alfa.guests["Y|z-Firemaw"],
    G("a member whose key no guest can have stays a member"))
  sweep(G("migrated long multibyte guest"), 1)

  -- ── The receipt: whatever the db holds ────────────────────────────────
  -- Cores written straight into the db: from before these checks, or named by the site.
  local function state(label, cores, wantCores, wantLeft, extra)
    load(game)
    GuildOS.db.cores = cores
    if extra then extra() end
    return sweep(G(label), wantCores, wantLeft)
  end
  local function core(name, more)
    local c = { name = name, members = {} }
    for k, v in pairs(more or {}) do c[k] = v end
    return c
  end
  state("empty", {}, 0)
  state("a pipe, a control character, DEL", { ["Kara || Sexta"] = core("x"), ["Kara\tSexta"] = core("x"),
    ["Kara\127"] = core("x"), ["Kara"] = core("x") }, 1, "3 core(s) and 0 guest(s)")
  state("two long names sharing 48 bytes", { [LONG] = core(LONG), [LONG:sub(1, -2) .. "2"] = core("x") }, 1,
    "1 core(s) and 0 guest(s)")
  state("a long name cut to one already there", { [LONG] = core(LONG), [LONG:sub(1, 48)] = core("x") }, 1)
  state("the object's own words", { constructor = core("x"), prototype = core("x"), __proto__ = core("x"), Ok = core("x") }, 1)
  state("blank names", { ["   "] = core("x"), ["\194\160"] = core("x"), ["\227\128\128"] = core("x") }, 0)
  state("a long multibyte name", { [("é"):rep(30)] = core("x"), [("한"):rep(20)] = core("x") }, 2)
  state("broken UTF-8", { ["Alfa\195"] = core("x"), ["\255Beta"] = core("x"), ["\237\160\128"] = core("x") }, 0)
  local many = {}
  for i = 1, 60 do many[("Core %02d"):format(i)] = core("x") end
  state("sixty cores", many, 50)
  state("bad, repeated and object tags", {
    A = core("A", { discordTag = "nucleo-alfa", importedAt = 5 }), B = core("B", { discordTag = "nucleo-alfa", importedAt = 5 }),
    C = core("C", { discordTag = "Bad Tag" }), D = core("D", { discordTag = "constructor" }),
    E = core("E", { discordTag = ("a"):rep(41) }), F = core("F", { discordTag = "-x" }), G = core("G", { discordTag = "ok-2" }) }, 2)
  state("odd figures", {
    Zero = core("Zero", { raidSize = 0 }), Huge = core("Huge", { raidSize = 100, discordTag = "huge", importedAt = 2 ^ 40 }),
    Neg = core("Neg", { raidSize = -5, discordTag = "neg", importedAt = -1 }),
    NaN = core("NaN", { raidSize = 0 / 0, discordTag = "nan", importedAt = 0 / 0 }) }, 4)
  local crowd = {}
  for i = 1, 1200 do crowd["P" .. i .. "-Firemaw"] = { name = "P" .. i, src = (i % 2 == 0) and "discord" or nil } end
  state("1200 members, from Discord and not", { Big = core("Big", { discordTag = "big", importedAt = 9, members = crowd }),
    Only = core("Only", { members = { ["A-Firemaw"] = { src = "discord" } } }) }, 2)
  local function guestState(label, list, wantLeft)
    local r2 = state(label, { Alfa = core("Alfa", { discordTag = "alfa", importedAt = 7, guests = list }) }, 1, wantLeft)
    return r2.cores[1].guests
  end
  local g = guestState("three namesakes", { ["Foo-A"] = { name = "Foo" }, ["Foo-B"] = { name = "Foo" }, ["Foo-C"] = { name = "Foo" },
    ["Bar-A"] = { name = "Bar" } })
  check(table.concat(g, ",") == "Bar,Foo-A,Foo-B,Foo-C", G("namesakes go with their realms: " .. table.concat(g, ",")))
  g = guestState("a namesake whose realm-name is another guest's name", { ["Foo-A"] = { name = "Foo" }, ["Foo-B"] = { name = "Foo" },
    ["Zed-A"] = { name = "Foo-A" } }, "0 core(s) and 1 guest(s)")
  check(#g == 2, G("the second of two alike is left out"))
  g = guestState("guest names the site refuses", { ["Bob-A"] = { name = "Bob|cff" }, ["Cy-A"] = { name = "constructor" },
    ["constructor"] = { name = "constructor" }, ["Di-A"] = { name = "\1" }, ["Ed-A"] = { name = ("é"):rep(40) },
    ["Fi-A"] = {}, ["Gi-A"] = "not a table", ["Hu|x-A"] = { name = "Hu|x" } }, "0 core(s) and 2 guest(s)")
  check(#g == 6, G("each shown by its key's name, or left out: " .. table.concat(g, ",")))
  local longKeys = {}
  longKeys[("k"):rep(50) .. "-A"] = { name = "Same" }
  longKeys[("k"):rep(50) .. "-B"] = { name = "Same" }
  g = guestState("two namesakes whose keys cut to one", longKeys, "0 core(s) and 1 guest(s)")
  check(#g == 1, G("sent once"))
  local fifty = {}
  for i = 1, 50 do fifty["G" .. i .. "-A"] = { name = "G" .. i } end
  g = guestState("fifty guests", fifty)
  check(#g == 40, G("forty guests at most"))
  -- Past 2038 the time is kept as it is, up to the site's CLOCK_MAX (2^32 - 1, site #519), and held there.
  local r2038 = state("the clock past 2038", { A = core("A", { discordTag = "a", importedAt = 2 ^ 31 + 5 }) }, 1, nil,
    function() NOW = 2 ^ 31 + 10 end)
  check(r2038.at == 2 ^ 31 + 10 and r2038.cores[1].importedAt == 2 ^ 31 + 5
    and GuildOS.Companion.EncodeJson(r2038):find('"at":2147483658', 1, true),
    G("a time past 2038 goes as it is: " .. GuildOS.Companion.EncodeJson(r2038)))
  local r2106 = state("the clock past 2106", { A = core("A") }, 1, nil, function() NOW = 2 ^ 32 end)
  check(r2106.at == 4294967295, G("and is held at 2^32 - 1"))
  local rLink = state("a link stamp past 2106", { A = core("A") }, 1, nil, function() GuildOS.db.coreLink = { importedAt = 2 ^ 33 } end)
  check(rLink.linkedAt == 4294967295, G("a link stamp too"))
end
if out then out:close() end

print(("core-receipt: %d checks passed, %d receipts the site keeps"):format(checks, states))
