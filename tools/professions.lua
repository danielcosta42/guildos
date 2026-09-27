-- Professions on WoW: Forever (issue #31), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/Professions.lua, Modules/ProfSync.lua and DataCollector's hooks, under a
-- stubbed Forever client, a fixture catalog and a fake SyncService bus.
--
--   luajit -e 'ADDON="."' tools/professions.lua
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

-- ── The client: WoW: Forever ────────────────────────────────────────────
local NOW = 1790500000
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() return {} end }
local function runTimers()
  local guard = 0
  while #timers > 0 do
    guard = guard + 1
    assert(guard < 1000, "timer loop")
    table.remove(timers, 1)()
  end
end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(_, fn) self.onEvent = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
  end
end
function GetServerTime() return NOW end
function time() return NOW end
function IsInGuild() return true end
function hooksecurefunc() end
function debugstack() return "" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetRealmName() return "Classic Beta PvE 2" end
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
function UnitName(u) if u == "player" then return "Ana" end end
function UnitFullName(u) if u == "player" then return "Ana", "Silva" end end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }

-- The player's professions: GetProfessions() slots, GetProfessionInfo rows, known spells.
local SLOTS, PROFS, KNOWN = {}, {}, {}
function GetProfessions() return SLOTS[1], SLOTS[2], SLOTS[3], SLOTS[4], SLOTS[5] end
function GetProfessionInfo(i)
  local p = PROFS[i]
  if p then return p[1], 0, p[2], p[3], 0, 0, p[4], 0, -1, 0, p[1] end
end
function IsPlayerSpell(id) return KNOWN[id] == true end
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id } end }

-- The profession window: nil when closed.
local WINDOW
C_TradeSkillUI = {
  IsDataSourceChanging = function() return false end,
  IsTradeSkillLinked = function() return WINDOW and WINDOW.linked or false end,
  IsTradeSkillGuild = function() return false end,
  IsTradeSkillGuildMember = function() return false end,
  GetBaseProfessionInfo = function() return { professionID = WINDOW and WINDOW.line or 0 } end,
  GetAllRecipeIDs = function() return WINDOW and WINDOW.all or {} end,
  GetRecipeInfo = function(id)
    for _, x in ipairs(WINDOW and WINDOW.learned or {}) do
      if x == id then return { learned = true } end
    end
    return { learned = false }
  end,
}

-- The guild: roster names and the Communities roster's profession fields.
local ROSTER = { "Ana Silva", "Bob", "Cid", "Dee" }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  if ROSTER[i] then return ROSTER[i], "Member", 3, 20, "Mage", "", "", "", true, 0, "MAGE" end
end
local CLUB = {}
C_Club = {
  GetGuildClubId = function() return 7 end,
  GetClubMembers = function()
    local t = {}
    for i in ipairs(CLUB) do t[i] = i end
    return t
  end,
  GetMemberInfo = function(_, i) return CLUB[i] end,
}

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
local Compat = BRutus.Compat

-- ── 1. Compat ───────────────────────────────────────────────────────────
check(not BRutus.Client.isAnniversary, "the stub is a Forever client")
SLOTS = { 1, nil, 2 }
check(select("#", Compat.GetProfessions()) == 5 and select(3, Compat.GetProfessions()) == 2,
      "GetProfessions passes every slot through, nils included")
PROFS[1] = { "Mineração", 21, 75, 186 }
check(select(7, Compat.GetProfessionInfo(1)) == 186 and select(3, Compat.GetProfessionInfo(1)) == 21,
      "GetProfessionInfo passes rank and skill line through")
KNOWN[2657] = true
check(Compat.IsPlayerSpell(2657) == true and Compat.IsPlayerSpell(1) == false, "IsPlayerSpell is a boolean")
check(Compat.TradeSkillLearned() == nil, "no window, no learned list")
WINDOW = { line = 186, all = { 2657, 3304 }, learned = { 2657 } }
local line, learned = Compat.TradeSkillLearned()
check(line == 186 and #learned == 1 and learned[1] == 2657, "the own window gives its line and learned IDs")
WINDOW.linked = true
check(Compat.TradeSkillLearned() == nil, "a linked (someone else's) window is ignored")
WINDOW = nil
CLUB = { { name = "Bob", profession1ID = 186, profession2ID = 0 },
         { name = "Cid", profession1ID = 164, profession2ID = 185 } }
local club = Compat.GuildMemberProfessions()
check(#club == 2 and club[1].name == "Bob" and #club[1].lines == 1 and #club[2].lines == 2,
      "the Communities roster gives each member's profession lines, zeros dropped")
issecretvalue = function(v) return v == "Cid" end
check(#Compat.GuildMemberProfessions() == 1, "a member whose fields are secret is skipped")
issecretvalue = nil
local saved = GetProfessions
GetProfessions = nil
check(select("#", Compat.GetProfessions()) == 0, "no API, nothing")
GetProfessions = saved
CLUB, SLOTS, PROFS, KNOWN = {}, {}, {}, {}

-- ── Fixture catalog and a fake SyncService bus ──────────────────────────
BRutus.ProfCatalog = {
  build = "fixture",
  F = { line = 1, yellow = 2, grey = 3, out = 4, outCount = 5, enchant = 6, reqSkill = 7, spec = 8, focus = 9,
        src = 10, recipeItem = 11, category = 12, reagents = 13 },
  professions = { [186] = { child = 2946, primary = true, en = "Mining" },
                  [164] = { child = 2938, primary = true, en = "Blacksmithing" },
                  [185] = { child = 2939, primary = false, en = "Cooking" } },
  specs = { [9788] = 164 },
  stations = {},
  byLine = { [186] = { 2657, 3304 }, [164] = { 2660, 9950 }, [185] = { 2538 } },
  recipes = {
    [2657] = { 186, 1, 25, 2840, 1, 0, 0, 0, 0, 3, 0, 0, { 2770, 1 } },
    [3304] = { 186, 65, 90, 3576, 1, 0, 0, 0, 0, 1, 0, 0, { 2771, 1 } },
    [2660] = { 164, 1, 15, 2862, 1, 0, 0, 0, 0, 1, 0, 0, { 2835, 1 } },
    [9950] = { 164, 210, 230, 7934, 1, 0, 210, 9788, 0, 2, 7978, 0, {} },
    [2538] = { 185, 1, 45, 2679, 1, 0, 0, 0, 0, 1, 0, 0, { 2672, 1 } },
  },
}
local sent = {}
BRutus.SyncService = {
  handlers = {},
  On = function(self, dom, fn) self.handlers[dom] = fn end,
  Publish = function(_, dom, act, data, opts)
    sent[#sent + 1] = { dom = dom, act = act, data = data, target = opts and opts.target }
    return "id"
  end,
}
local function sentOf(act)
  local out = {}
  for _, m in ipairs(sent) do if m.act == act then out[#out + 1] = m end end
  return out
end
math.random = function(a) return a end
BRutus.db = { members = {}, settings = {} }
dofile(ADDON .. "/Modules/Professions.lua")
local P = BRutus.Professions
check(P ~= nil, "Professions exists on Forever")
local ME = P.OwnKey()
check(ME == "Ana Silva-Classic Beta PvE 2", "my key is my whole name and the client's realm: " .. tostring(ME))

-- ── 2. Collection ───────────────────────────────────────────────────────
check(P.Hash({ 3, 1, 2 }) == P.Hash({ 1, 2, 3 }) and P.Hash({ 1 }, { 2 }) == P.Hash({ 1, 2 }),
      "the hash ignores order and where an ID sits")
check(P.IdList({ 3, 1, 3 }, 10)[1] == 1 and #P.IdList({ 3, 1, 3 }, 10) == 2, "IdList sorts and drops duplicates")
check(P.IdList({ "x" }, 10) == nil and P.IdList({ 1.5 }, 10) == nil and P.IdList({ 1, 2 }, 1) == nil
      and P.IdList("x", 10) == nil, "IdList refuses non-IDs and lists past the cap")
SLOTS = { 1, nil, 2, 3 }
PROFS[1] = { "Mineração", 21, 75, 186 }
PROFS[2] = { "Culinária", 1, 75, 185 }
PROFS[3] = { "Venenos", 10, 300, 40 }
KNOWN[2657], KNOWN[2538] = true, true
P:Initialize()
runTimers()
local rec = BRutus.db.professions[ME]
check(rec and rec.src == "addon" and rec.profs[186].rank == 21 and rec.profs[186].max == 75,
      "rank and max come from GetProfessionInfo, keyed by skill line")
check(#rec.profs[186].recipes == 1 and rec.profs[186].recipes[1] == 2657 and rec.profs[186].n == 1
      and rec.profs[186].h == P.Hash({ 2657 }), "learned recipes come from IsPlayerSpell over the catalog")
check(rec.profs[185] and rec.profs[40] == nil, "a skill line the catalog does not list (Poisons) is ignored")
local legacy = BRutus.db.members[ME].professions
check(#legacy == 2 and legacy[1].name == "Cooking" and legacy[2].name == "Mining" and legacy[2].rank == 21
      and legacy[2].maxRank == 75 and legacy[2].isPrimary == true and legacy[1].isPrimary == false,
      "the adapter writes DataCollector's shape, canonical English names")
local mine = BRutus.db.recipes[ME].Mining
check(mine and mine[1].spellId == 2657 and mine[1].itemId == 2840 and mine[1].name == "Spell 2657",
      "the adapter writes the recipe tracker's shape, localized name and output item")
SLOTS[2], PROFS[4], KNOWN[9788], KNOWN[9950] = 4, { "Ferraria", 210, 300, 164 }, true, true
fire("SKILL_LINES_CHANGED")
runTimers()
rec = BRutus.db.professions[ME]
check(rec.profs[164] and rec.profs[164].spec == 9788 and rec.profs[164].recipes[1] == 9950,
      "a specialization is read from the catalog's spells")
SLOTS[2] = nil
fire("LEARNED_SPELL_IN_SKILL_LINE")
runTimers()
check(BRutus.db.professions[ME].profs[164] == nil and #BRutus.db.members[ME].professions == 2,
      "a profession dropped disappears on the next scan")
KNOWN[3304] = true
fire("NEW_RECIPE_LEARNED", 3304)
runTimers()
rec = BRutus.db.professions[ME]
check(#rec.profs[186].recipes == 2 and rec.profs[186].h == P.Hash({ 2657, 3304 }), "a new recipe is picked up")
check(P:Scan() == false, "a scan that finds nothing new changes nothing")
WINDOW = { line = 186, all = { 2657, 3304, 999001 }, learned = { 2657, 3304, 999001 } }
KNOWN[999001] = true
fire("TRADE_SKILL_LIST_UPDATE")
runTimers()
rec = BRutus.db.professions[ME]
check(rec.profs[186].extra[1] == 999001 and rec.profs[186].n == 3
      and rec.profs[186].h == P.Hash({ 2657, 3304 }, { 999001 }),
      "the own window adds a learned recipe the catalog lacks as extra")
check(BRutus.db.recipes[ME].Mining[3].spellId == 999001, "an extra recipe reaches the recipe tracker too")
WINDOW = { line = 186, linked = true, all = { 888001 }, learned = { 888001 } }
fire("TRADE_SKILL_LIST_UPDATE")
runTimers()
check(#BRutus.db.professions[ME].profs[186].extra == 1, "someone else's window adds nothing")
WINDOW = nil
check(P:Scan() == false, "an extra still known survives a scan")
KNOWN[999001] = nil
check(P:Scan() == true and #BRutus.db.professions[ME].profs[186].extra == 0, "an extra no longer known is dropped")

-- ── 3. Native records and queries ───────────────────────────────────────
CLUB = { { name = "Bob", profession1ID = 186, profession2ID = 333 }, { name = "Ana Silva", profession1ID = 164 } }
fire("GUILD_ROSTER_UPDATE")
runTimers()
local BOB = BRutus:GetPlayerKey("Bob")
check(BRutus.db.professions[BOB] and BRutus.db.professions[BOB].src == "native"
      and BRutus.db.professions[BOB].profs[186] and BRutus.db.professions[BOB].profs[333] == nil,
      "a member without the addon gets the catalog's professions the roster names")
check(BRutus.db.professions[ME].src == "addon" and BRutus.db.professions[ME].profs[186],
      "a native record never replaces an addon one")
local bobLegacy = BRutus.db.members[BOB].professions
check(#bobLegacy == 1 and bobLegacy[1].name == "Mining" and bobLegacy[1].rank == nil, "a native profession has no rank")
CLUB[1].profession1ID = 164
fire("GUILD_ROSTER_UPDATE")
runTimers()
check(BRutus.db.professions[BOB].profs[186], "the roster is read at most once a minute")
NOW = NOW + 61
fire("GUILD_ROSTER_UPDATE")
runTimers()
check(BRutus.db.professions[BOB].profs[164] and not BRutus.db.professions[BOB].profs[186],
      "a minute later the change is read")
check(P:KnowsRecipe(ME, 2657) and not P:KnowsRecipe(BOB, 2657), "KnowsRecipe")
check(#P:CraftersOf(2657) == 1 and P:CraftersOf(2657)[1] == ME and #P:CraftersOf(1) == 0, "CraftersOf")
check(#P:Members(186) == 1 and #P:Members(164) == 1, "Members by line")
local summary = P:OwnSummary()
check(summary[186].r == 21 and summary[186].h == BRutus.db.professions[ME].profs[186].h and summary[186].n == 2,
      "the own summary carries rank, hash and count per line")
check(P:OwnLine(186).recipes[1] == 2657 and P:OwnLine(999) == nil, "OwnLine")

-- ── 4. Sync ─────────────────────────────────────────────────────────────
dofile(ADDON .. "/Modules/ProfSync.lua")
local S = BRutus.ProfSync
sent = {}
S:Initialize()
runTimers()
check(#sentOf("sum") == 1 and #sentOf("ask") == 1 and sentOf("sum")[1].target == nil,
      "login publishes my summary and asks the guild for theirs")
check(sentOf("sum")[1].data.p[186].h == BRutus.db.professions[ME].profs[186].h, "the summary is my own")
local function deliver(act, data, sender)
  BRutus.SyncService.handlers.prof({ dom = "prof", act = act, data = data }, sender)
end
local h1 = P.Hash({ 2657 })
sent = {}
deliver("sum", { p = { [186] = { r = 50, m = 75, h = h1, n = 1 } } }, "Zed")
runTimers()
check(BRutus.db.professions[BRutus:GetPlayerKey("Zed")] == nil and #sent == 0, "a sender outside the guild is ignored")
deliver("sum", { p = { [186] = { r = 50, m = 75, h = h1, n = 1 } }, key = "Dee-Classic Beta PvE 2" }, "Bob")
check(BRutus.db.professions[BOB].src == "addon" and BRutus.db.professions[BOB].profs[186].rank == 50
      and BRutus.db.professions[BOB].profs[186].recipes == nil, "a summary replaces the native record, list pending")
check(BRutus.db.professions[BRutus:GetPlayerKey("Dee")] == nil, "the key comes from the sender, not the payload")
runTimers()
local req = sentOf("req")
check(#req == 1 and req[1].target == "Bob" and req[1].data.l[1] == 186, "a new hash asks the sender for that list")
sent = {}
deliver("sum", { p = { [186] = { r = 51, m = 75, h = h1, n = 1 } } }, "Bob")
runTimers()
check(#sentOf("req") == 0, "the same hash is not asked for again at once")
NOW = NOW + 121
deliver("sum", { p = { [186] = { r = 51, m = 75, h = h1, n = 1 } } }, "Bob")
runTimers()
check(#sentOf("req") == 1, "a list that never came is asked for again after two minutes")
deliver("list", { l = 186, h = h1 + 1, r = { 2657 }, x = {} }, "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes == nil, "a list whose hash is not the summary's is refused")
deliver("list", { l = 186, h = h1, r = { 2660 }, x = {} }, "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes == nil, "a list that does not hash to its h is refused")
deliver("list", { l = 186, h = h1, r = { "x" }, x = {} }, "Bob")
deliver("list", { l = 186, h = h1, r = "x" }, "Bob")
deliver("list", "junk", "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes == nil, "malformed lists are dropped without raising")
deliver("list", { l = 186, h = h1, r = { 2657 }, x = {} }, "Bob")
check(BRutus.db.professions[BOB].profs[186].recipes[1] == 2657 and P:KnowsRecipe(BOB, 2657)
      and #P:CraftersOf(2657) == 2, "a list matching the summary is stored and indexed")
check(BRutus.db.recipes[BOB].Mining[1].itemId == 2840, "and reaches the recipe tracker's shape")
check(P:ApplyList(BOB, 186, h1, { 2657 }, {}) == false, "a list already held is not applied twice")
local before = BRutus.db.professions[BOB].profs[186].rank
deliver("sum", { p = { [186] = { r = "x", m = 75, h = h1, n = 1 } } }, "Bob")
deliver("sum", { p = { [999] = { r = 1, m = 75, h = h1, n = 1 } } }, "Bob")
deliver("sum", { p = { ["186"] = { r = 1, m = 75, h = h1, n = 1 } } }, "Bob")
local eight = {}
for i = 1, 8 do eight[i] = { r = 1, m = 75, h = h1, n = 1 } end
deliver("sum", { p = eight }, "Bob")
check(BRutus.db.professions[BOB].profs[186].rank == before, "a malformed summary changes nothing")
deliver("sum", { p = { [185] = { r = 5, m = 75, h = 1, n = 0 } } }, "Cid")
check(#BRutus.db.professions[BRutus:GetPlayerKey("Cid")].profs[185].recipes == 0, "a line with no recipes needs no list")
sent = {}
deliver("req", { l = { 186 } }, "Bob")
runTimers()
local lists = sentOf("list")
check(#lists == 1 and lists[1].target == "Bob" and lists[1].data.h == BRutus.db.professions[ME].profs[186].h
      and #lists[1].data.r == 2, "one requester gets my list by whisper")
sent = {}
deliver("req", { l = { 186 } }, "Bob")
deliver("req", { l = { 186 } }, "Cid")
runTimers()
lists = sentOf("list")
check(#lists == 1 and lists[1].target == nil, "two requesters within the window get one guild answer")
sent = {}
deliver("req", { l = { 164 } }, "Bob")
deliver("req", { l = { 186 } }, "Zed")
deliver("req", { l = "x" }, "Bob")
runTimers()
check(#sentOf("list") == 0, "a line I do not have, a stranger, or junk gets no answer")
sent = {}
deliver("ask", {}, "Cid")
runTimers()
check(#sentOf("sum") == 1, "an ask is answered with my summary")

-- ── 5. Integration points ───────────────────────────────────────────────
dofile(ADDON .. "/Modules/DataCollector.lua")
local DC = BRutus.DataCollector
local own = DC:CollectProfessions()
check(type(own) == "table" and #own == 2 and own[2].name == "Mining", "CollectProfessions reads Professions on Forever")
BRutus.db.members[ME], BRutus.db.professions[ME], P.scanned = nil, nil, false
check(#DC:CollectProfessions() == 2, "and scans first when the login scan has not run, never empty")
BRutus.db.myData = { name = "Ana Silva", realm = "Classic Beta PvE 2", lastUpdate = NOW }
check(BRutus.db.recipes[ME] ~= nil and DC:GetBroadcastData().recipes == nil,
      "the member broadcast carries no recipes on Forever")
local reminded = false
BRutus.ShowProfessionReminder = function() reminded = true end
BRutus.db.myData.professions = { { name = "Blacksmithing", rank = 210, maxRank = 300, isPrimary = true } }
BRutus:CheckProfessionFreshness()
check(not reminded, "the open-your-window reminder never shows on Forever")
ROSTER = { "Ana Silva", "Cid" }
BRutus:PruneStaleData()
check(BRutus.db.professions[BOB] == nil and BRutus.db.recipes[BOB] == nil and BRutus.db.professions[ME],
      "a member who left loses the profession record and its projection")

print("professions: " .. checks .. " checks passed")
