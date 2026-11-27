-- The idle sync of the systems audit (specs/salao/audit.md, #285), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua, Modules/DataCollector.lua, Modules/RecipeTracker.lua,
-- Modules/AllianceLink.lua, Modules/AllianceChat.lua, Modules/Backup.lua and the real LibSerialize and LibDeflate:
--   * D1: no periodic REQUEST; the 5-minute push skips data that did not change; an answer and the login always send;
--   * D2: a General line costs AllianceLink and AllianceChat nothing; their roster reads and DropDeparted coalesce;
--   * D3: Anniversary's recipes go by hash: once per change, asked for when a guildmate's copy differs, never in
--     the member broadcast, and the chat line only when the count moves;
--   * D4: on WoW: Forever and retail db.recipes is built at login and never saved;
--   * D5: the Comm System switch off sends nothing, takes nothing, and /gos sync says so;
--   * D9 / D10: one collection at login, one for an equipment swap or a burst of skill-ups;
--   * D11: Restore asks first; D13: no db.lastSync default; N14 and B26 by their source.
--
--   luajit -e 'ADDON="."' tools/audit-sync.lua
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
local function read(rel)
  local fh = assert(io.open(ADDON .. "/" .. rel, "rb"), rel)
  local s = fh:read("*a")
  fh:close()
  return s
end

-- ── A TBC Anniversary client whose clock and timers this file moves ────
local clock, timers = 1000, {}
function GetTime() return clock end
function GetServerTime() return 1794500000 + clock end
function time() return 1794500000 + clock end
C_Timer = {
  After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end,
  NewTicker = function(every, fn) timers[#timers + 1] = { at = clock + every, fn = fn, every = every }
    return { Cancel = function() end } end,
}
local function advance(seconds)
  local stop = clock + seconds
  while true do
    local nextI
    for i, t in ipairs(timers) do
      if t.at <= stop and (not nextI or t.at < timers[nextI].at) then nextI = i end
    end
    if not nextI then break end
    local t = table.remove(timers, nextI)
    clock = math.max(clock, t.at)
    if t.every then timers[#timers + 1] = { at = clock + t.every, fn = t.fn, every = t.every } end
    t.fn()
  end
  clock = stop
end

strmatch = string.match
dofile(ADDON .. "/Libs/LibStub.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
local function said(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return true end end
  return false
end
local frames = {}
function CreateFrame()
  local f = { events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(_, fn) self.onEvent = fn end
  frames[#frames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
  end
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 70 end
function UnitRace() return "Orc", "Orc" end
function UnitSex() return 2 end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Member", 5 end
local ROSTER = { { "Me-Realm", 5 }, { "Bob-Realm", 5 }, { "Gm-Realm", 0 } }
local rosterReads = 0
function GetNumGuildMembers() return #ROSTER, #ROSTER end
function GetGuildRosterInfo(i)
  rosterReads = rosterReads + 1
  local r = ROSTER[i]
  if r then return r[1], "Rank", r[2], 70, "Warrior", "", "", "", true, nil, "WARRIOR" end
end
function GuildControlGetNumRanks() return 6 end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ReloadUI() end
local sent = {}
C_ChatInfo = { SendAddonMessage = function(prefix, msg, chan, target) sent[#sent + 1] = { prefix = prefix, msg = msg,
  chan = chan, target = target } return true end, RegisterAddonMessagePrefix = function() return true end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
GuildOS.Compat.SendAddonMessage = function(prefix, msg, chan, target)
  sent[#sent + 1] = { prefix = prefix, msg = msg, chan = chan, target = target }
end
check(GuildOS.DB_DEFAULTS == nil or GuildOS.DB_DEFAULTS.lastSync == nil, "D13: no db.lastSync default")
check(not read("Core/Core.lua"):find("\n    lastSync = 0,", 1, true), "D13: db.lastSync, never written, has no default")
GuildOS.db = { settings = {}, members = {}, myData = {}, recipes = {} }
GuildOS.guildKey, GuildOS.isGuilded = "Guild - Realm", true
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/DataCollector.lua")
dofile(ADDON .. "/Modules/RecipeTracker.lua")
local CS, DC, RT = GuildOS.CommSystem, GuildOS.DataCollector, GuildOS.RecipeTracker
local LibSerialize = LibStub("GuildOS-LibSerialize")
local LibDeflate = LibStub("LibDeflate")

-- What went out on the sync prefix, decoded: { t = type, data = payload, chan, target }.
local function out()
  local list = {}
  for _, s in ipairs(sent) do
    local body = s.msg:match("^S:(.*)$")
    if body then
      local payload = LibDeflate:DecompressDeflate(LibDeflate:DecodeForWoWAddonChannel(body))
      local t, data = payload:match("^(%w+):(.*)$")
      list[#list + 1] = { t = t, data = data, chan = s.chan, target = s.target }
    end
  end
  return list
end
local function count(t)
  local n = 0
  for _, m in ipairs(out()) do if m.t == t then n = n + 1 end end
  return n
end
local function from(sender, t, data, chan)
  local enc = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(t .. ":" .. data))
  CS:OnMessageReceived("S:" .. enc, chan or "GUILD", sender)
end

-- Collections counted, the real one still run.
local collected = 0
local realCollect = DC.CollectMyData
DC.CollectMyData = function(self) collected = collected + 1; return realCollect(self) end
DC.CollectGear = function() return {}, false end
DC.CollectStats = function() return {} end
DC.CalculateAvgIlvl = function() return 0 end
DC.CollectProfessions = function() return {} end

-- ── D1 / D9: the login, and the 5-minute push ───────────────────────────
GuildOS.Perf:Reset()
CS:Initialize()
DC:Initialize()
local tickers = 0
for _, t in ipairs(timers) do if t.every then tickers = tickers + 1; check(t.every ~= 600, "D1: no 10-minute REQUEST ticker") end end
check(tickers == 1, "D1: the one ticker left is the 5-minute push")
GuildOS:OnEnterWorld(true, false)
advance(70)
check(collected == 1, "D9: the login collects once, not three times (" .. collected .. ")")
check(count("BC") == 1, "the login's broadcast goes out once (" .. count("BC") .. ", " .. #sent .. " sent)")
check(count("RQ") == 3, "D1: the login pull stays (three asks in its first minute)")
local bc
for _, m in ipairs(out()) do if m.t == "BC" then bc = m end end
local okB, member = LibSerialize:Deserialize(bc.data)
check(okB and member.recipes == nil, "D3: the member broadcast carries no recipe list")
sent = {}
advance(300)
check(count("BC") == 0 and count("RQ") == 0, "D1: nothing changed, the 5-minute push sends nothing and nobody is asked")
check(GuildOS.State.perf.rows["guild sync broadcast unchanged"], "and /gos perf counts the skip")
GuildOS.db.myData.level, UnitLevel = 71, function() return 71 end
advance(300)
check(count("BC") == 1, "D1: a change goes out on the next push")
sent = {}
from("Bob-Realm", "RQ", "ALL")
advance(10)
check(count("BC") == 1, "D1: a member who logs in still gets my data, changed or not")
check(read("Modules/CommSystem.lua"):find("CommSystem:BroadcastMyData(false, true)", 1, true),
  "D1: only the timer's push asks for a change")

-- ── D1: the officer config on the 5-minute push only when it changed ─────
do
  dofile(ADDON .. "/Modules/SyncService.lua")
  local realOfficer = GuildOS.IsOfficer
  GuildOS.IsOfficer = function() return true end
  local st = GuildOS.db.settings
  st.officerMaxRank, st.officerMaxRankAt, st.lootSystem, st.lootSystemAt = 2, 100, "dkp", 100
  sent = {}
  CS:PublishOfficerConfig(true)
  local first = count("SV")
  check(first == 2, "D1: the first push sends the officer config (" .. first .. ")")
  sent = {}
  CS:PublishOfficerConfig(true)
  check(count("SV") == 0, "D1: unchanged since this session sent it: the 5-minute push sends nothing")
  st.officerMaxRank, st.officerMaxRankAt = 3, 200
  sent = {}
  CS:PublishOfficerConfig(true)
  check(count("SV") == 1, "D1: only the payload that changed goes")
  sent = {}
  CS:PublishOfficerConfig()
  check(count("SV") == 2, "D1: the answer to a request (and a manual Sync) sends it whole")
  check(GuildOS.SyncService._configScope == nil, "D1: the scope ends with the call")
  sent = {}
  GuildOS.SyncService:Publish("guildcfg", "officers", { max = 3 }, { rev = 200 })
  check(count("SV") == 1, "D1: a publish outside the officer config is never skipped")
  check(read("Modules/CommSystem.lua"):find("CommSystem:PublishOfficerConfig(true)", 1, true),
    "D1: the timer's push asks for a change")
  GuildOS.IsOfficer = realOfficer
  st.officerMaxRank, st.officerMaxRankAt, st.lootSystem, st.lootSystemAt = nil, nil, nil, nil
end

-- ── D10: an equipment swap, a burst of skill-ups ────────────────────────
collected, sent = 0, {}
advance(10)
for _ = 1, 16 do fire("PLAYER_EQUIPMENT_CHANGED") end
advance(0.5)
check(collected == 0, "D10: nothing is collected while the slots are still changing")
advance(5)
check(collected == 1 and count("BC") == 1, "D10: sixteen slot changes are one collection and one broadcast")
local skills = 0
DC.CollectProfessions = function() skills = skills + 1; return {} end
for _ = 1, 8 do fire("CHAT_MSG_SKILL"); advance(0.2) end
advance(2)
check(skills == 1, "D10: a burst of skill-ups is one profession read")

-- ── D3: Anniversary's recipes by hash ───────────────────────────────────
GetTradeSkillLine = function() return "Alchemy" end
local RECIPES = { { "Flask of Fortification", 22861 }, { "Elixir of Major Agility", 22831 } }
GetNumTradeSkills = function() return #RECIPES end
GetTradeSkillInfo = function(i) return RECIPES[i][1], "optimal" end
GetTradeSkillItemLink = function(i) return "item:" .. RECIPES[i][2] end
RT:Initialize()
sent, printed = {}, {}
RT:ScanTradeSkill()
check(count("RC") == 1 and said("Recipes scanned:"), "D3: the first scan sends the list once and says so")
sent, printed = {}, {}
RT:ScanTradeSkill()
check(count("RC") == 0 and not said("Recipes scanned:"), "D3: the same list opened again sends nothing and prints nothing")
RECIPES[3] = { "Elixir of Healing Power", 22825 }
RT:ScanTradeSkill()
check(count("RC") == 1 and said("3 Alchemy"), "D3: a new recipe sends the list, and the count moved: a line")
local hashes = RT:OwnHashes()
check(hashes and type(hashes.Alchemy) == "number", "D3: my broadcast's hashes, one per profession")
local data = DC:GetBroadcastData()
check(data.recipes == nil and data.rh and data.rh.Alchemy == hashes.Alchemy, "D3: the broadcast holds the hash, not the list")

-- A guildmate's broadcast names a list I lack: I ask by whisper; again only after REASK_AFTER.
sent = {}
local bob = { name = "Bob", class = "MAGE", level = 70, lastUpdate = time(), rh = { Tailoring = 12345 } }
from("Bob-Realm", "BC", LibSerialize:Serialize(bob))
local asks = {}
for _, m in ipairs(out()) do if m.t == "RA" then asks[#asks + 1] = m end end
check(#asks == 1 and asks[1].chan == "WHISPER" and asks[1].target == "Bob-Realm" and asks[1].data == "Tailoring",
  "D3: a list I do not hold is asked for, by whisper, from its crafter")
check(GuildOS.db.members["Bob-Realm"] and GuildOS.db.members["Bob-Realm"].rh == nil, "and the hashes are not stored as member data")
sent = {}
bob.lastUpdate = time() + 1
from("Bob-Realm", "BC", LibSerialize:Serialize(bob))
check(count("RA") == 0, "D3: the same broadcast again asks nothing before REASK_AFTER")
-- The list arrives: its hash now matches, nothing more is asked.
local list = { { name = "Bolt of Silk Cloth", itemId = 4305 } }
from("Bob-Realm", "RC", LibSerialize:Serialize({ prof = "Tailoring", recipes = list }))
bob.rh.Tailoring, bob.lastUpdate = RT.Hash(list), time() + 2
advance(RT.REASK_AFTER + 1)
sent = {}
from("Bob-Realm", "BC", LibSerialize:Serialize(bob))
check(GuildOS.db.recipeIds["Bob-Realm"].Tailoring and count("RA") == 0, "D3: a list held as announced is never asked for")
check(GuildOS.db.recipes == nil and GuildOS.db.recipeIds["Bob-Realm"].Tailoring[2] == 4305
  and GuildOS.db.recipeIds["Bob-Realm"].Tailoring.nm[1] == "Bolt of Silk Cloth",
  "memoria: the list is kept compact (a recipe with no spell ID keeps its name)")

-- Asked for mine: one answer on GUILD for everybody who asked within ASK_GATHER, then not before ANSWER_GAP.
sent = {}
from("Bob-Realm", "RA", "Alchemy", "WHISPER")
from("Cid-Realm", "RA", "Alchemy", "WHISPER")
advance(RT.ASK_GATHER + 0.5)
local answers = {}
for _, m in ipairs(out()) do if m.t == "RC" then answers[#answers + 1] = m end end
check(#answers == 1 and answers[1].chan == "GUILD", "D3: two asks, one list, on GUILD")
do   -- memoria: the answer is in the old shape, names and all, and hashes to what my broadcast announced
  local okA, sentList = LibSerialize:Deserialize(answers[1].data)
  check(okA and sentList.prof == "Alchemy" and #sentList.recipes == 3 and sentList.recipes[1].name == "Flask of Fortification"
    and sentList.recipes[1].itemId == 22861 and RT.Hash(sentList.recipes) == RT:OwnHashes().Alchemy,
    "memoria: the list goes out in the old shape, with the names its hash covers")
end
sent = {}
from("Dee-Realm", "RA", "Alchemy", "WHISPER")
advance(RT.ASK_GATHER + 0.5)
check(count("RC") == 0, "D3: asked again at once, it waits for ANSWER_GAP")
advance(RT.ANSWER_GAP)
check(count("RC") == 1, "D3: and then answers")
sent = {}
from("Dee-Realm", "RA", "Engineering", "WHISPER")
advance(RT.ANSWER_GAP)
check(count("RC") == 0, "D3: a profession I do not have gets no answer")

-- ── D5: the Comm System switch ──────────────────────────────────────────
GuildOS:SetFeatureEnabled("commSystem", false)
sent, printed = {}, {}
CS:SendMessage("BC", "x")
CS:FullSync()
check(#sent == 0 and said("Guild sync is off"), "D5: off, nothing goes out, and /gos sync says the sync is off")
local stored = GuildOS.db.members["Eve-Realm"]
for _, f in ipairs(frames) do
  if f.events.CHAT_MSG_ADDON then
    local enc = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate("BC:" .. LibSerialize:Serialize(
      { name = "Eve", class = "MAGE", lastUpdate = time() })))
    f.onEvent(f, "CHAT_MSG_ADDON", GuildOS.PREFIX, "S:" .. enc, "GUILD", "Eve-Realm")
  end
end
check(stored == nil and GuildOS.db.members["Eve-Realm"] == nil, "D5: and nothing comes in")
GuildOS:SetFeatureEnabled("commSystem", true)

-- ── B26: the bar's Sync asks for the professions and the bank too ───────
local asked = {}
GuildOS.ProfSync = { Refresh = function() asked.prof = true end }
GuildOS.GuildBank = { Ask = function() asked.bank = true end }
CS:FullSync()
check(asked.prof and asked.bank, "B26: Sync re-asks ProfSync and the guild bank")
GuildOS.ProfSync, GuildOS.GuildBank = nil, nil
for _, f in ipairs({ "UI/PointsPanel.lua", "UI/FeaturePanels.lua" }) do
  check(read(f):find('L["Send to guild"]', 1, true), "B26: " .. f .. "'s button that only sends says Send to guild")
end
check(read("UI/RecipesPanel.lua"):find('L["Open each profession once to share it."]', 1, true),
  "B28: Anniversary's Crafts tab says how a profession is shared")

-- ── D2: a General line, the roster ──────────────────────────────────────
dofile(ADDON .. "/Modules/AllianceLink.lua")
dofile(ADDON .. "/Modules/AllianceChat.lua")
local Link, Chat = GuildOS.AllianceLink, GuildOS.AllianceChat
GuildOS.Alliance = { MyGuildName = function() return "Guild" end, Get = function() return nil end }
GuildOS.Compat.HookChatSend = function() end
GuildOS.Compat.AddChatFilter = function() end
local seen = 0
Link._OnChannel = function() seen = seen + 1 end
Chat._OnChannelMessage = function() seen = seen + 1 end
frames = {}
Link:Initialize()
Chat:Initialize()
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 2000 do fire("CHAT_MSG_CHANNEL", "WTS stuff", "Trader-Realm", "", "2. Trade", "", "", 0, 2, "Trade") end
local grew = collectgarbage("count") - before
collectgarbage("restart")
check(seen == 0 and grew < 40, "D2: 2000 Trade lines reach neither handler and allocate next to nothing (" .. grew .. " KB; a table and a closure each were ~200)")
Link.ReadGuildMasterNote = function() Link._reads = (Link._reads or 0) + 1 end
for _ = 1, 20 do fire("GUILD_ROSTER_UPDATE") end
advance(Link.ROSTER_GAP + 1)
check(Link._reads == 2, "D2: twenty roster updates are two reads of the guild master's note, not twenty")
local dropped = 0
GuildOS.DropDeparted = function() dropped = dropped + 1 end
GuildOS.RefreshRosterUI = function() end
for _ = 1, 30 do GuildOS:OnGuildRosterUpdate(); advance(5) end
check(dropped <= 4, "D2: DropDeparted runs at most once a minute (" .. dropped .. " in 150 s)")

-- ── D11: Restore asks first ─────────────────────────────────────────────
dofile(ADDON .. "/Modules/Backup.lua")
local popped, popData
GuildOS.Dialogs = GuildOS.Dialogs or {}
function GuildOS:ShowDialog(name, _, _, d) popped, popData = name, d end
local reloaded = 0
ReloadUI = function() reloaded = reloaded + 1 end
GuildOSDB = { [GuildOS.guildKey] = { keep = true } }
local str = GuildOS.Backup:Export()
printed = {}
GuildOS.Backup:AskImport("garbage")
check(popped == nil and said("Restore failed"), "D11: a string that is no backup is refused before any question")
GuildOS.Backup:AskImport(str)
check(popped == "GUILDOS_RESTORE_BACKUP" and reloaded == 0, "D11: a backup asks first: nothing replaced yet")
check(GuildOS.Dialogs.GUILDOS_RESTORE_BACKUP.text:find("whole", 1, true), "and says it is the whole guild database")
GuildOS.Dialogs.GUILDOS_RESTORE_BACKUP.OnAccept({ data = popData })
check(reloaded == 1 and GuildOSDB[GuildOS.guildKey].members, "confirmed, it restores and reloads")
check(read("UI/SettingsPanel.lua"):find('F:Section(L["Whole guild database"])', 1, true),
  "D11: Settings files Backup and Restore under Whole guild database, not Your data")

-- ── D4: on WoW: Forever and retail db.recipes is no copy at all (memoria.md) ──
local prof = read("Modules/Professions.lua")
check(not prof:find("function Professions:ProjectAll()", 1, true) and not prof:find("function Professions:Project(", 1, true),
  "D4: no per-member copy is built from db.professions")
check(prof:find('if event == "PLAYER_LOGOUT" then\n        GuildOS.db.recipes = nil', 1, true), "D4: and an older view is never saved")

-- ── N14: the roster key is GuildOS:KeyOfRosterName's ────────────────────
for _, f in ipairs({ "Modules/GuildBank.lua", "Modules/CraftOrders.lua", "Modules/Professions.lua", "Modules/Founding.lua" }) do
  local s = read(f)
  check(s:find("GuildOS:KeyOfRosterName(name)", 1, true)
    and not s:find('GetPlayerKey(name:match("^([^-]+)") or name, name:match(', 1, true), "N14: " .. f .. " reads a roster key one way")
end

print(("audit-sync: %d checks passed"):format(checks))
