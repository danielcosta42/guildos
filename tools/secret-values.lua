-- Secret Values on WoW: Forever, run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua
-- and the modules that read chat payloads and group units, under a stubbed client.
--
-- Forever runs the retail Secret Values system (its API documentation marks thousands of fields).
-- In chat messaging lockdown a CHAT_MSG_* line and its sender arrive secret; a restricted unit's
-- name, class and GUID do too, and so do stats while they are restricted. Addon code may pass a
-- secret along but not match, compare, concatenate or index with it: any of those raises, and a
-- handler that raises loses the event. This proves the two Compat helpers, that every chat handler
-- that reads a payload returns before touching a secret one — and still works on a readable one —
-- that group-unit loops skip the member they cannot read, and that a secret never reaches the
-- addon-message path.
--
-- The secret here is a table whose every metamethod raises, and the string library refuses a table
-- anyway, so an unguarded `author:match(...)` or `strlower(name)` fails exactly where the client's
-- would.
--
--   luajit -e 'ADDON="."' tools/secret-values.lua
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

-- ── A secret value ─────────────────────────────────────────────────────
local SECRET_MT = {}
local function refuse() error("secret value used", 2) end
for _, k in ipairs({ "__index", "__newindex", "__concat", "__call", "__eq", "__lt", "__le", "__add", "__sub",
                     "__mul", "__div", "__mod", "__unm", "__pow", "__len" }) do
  SECRET_MT[k] = refuse
end
local function secret() return setmetatable({}, SECRET_MT) end
local function isSecret(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end

-- ── The client ──────────────────────────────────────────────────────────
local frames, printed = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
StaticPopupDialogs, UISpecialFrames, CLASS_ICON_TCOORDS, RAID_CLASS_COLORS = {}, {}, {}, {}
SlashCmdList = {}
function CreateFrame()
  local f = { scripts = {}, events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:Show() end
  function f:Hide() end
  frames[#frames + 1] = f
  return f
end
function GetServerTime() return 1757800000 end
function GetTime() return 1000 end
function time() return 1757800000 end
function IsInGuild() return true end
function IsInRaid() return true end
function IsInGroup() return true end
function IsInInstance() return true, "party" end
function hooksecurefunc() end
function debugstack() return "" end
function GetBuildInfo() return "1.60.1", "69893", "", 16001 end
function GetRealmName() return "Forever" end
function GetUnitName() return nil end
function CanGuildInvite() return true end
function PlaySound() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
  local out, from = {}, 1
  while true do
    local i = s:find(sep, from, true)
    if not i then out[#out + 1] = s:sub(from); break end
    out[#out + 1] = s:sub(from, i - 1)
    from = i + 1
  end
  return unpack(out)
end
tinsert, strlower, strupper, strfind = table.insert, string.lower, string.upper, string.find
ERR_GUILD_JOIN_S = "%s has joined the guild."
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

-- The group: raid1 is readable; raid2's identity is restricted.
local SECRET_UNIT = "raid2"
function GetNumGroupMembers() return 2 end
function UnitExists(unit) return unit == "raid1" or unit == "raid2" or unit == "player" end
function UnitIsConnected() return true end
function UnitName(unit)
  if unit == "player" then return "Ana" end
  if unit == "raid1" then return "Bob", "Forever" end
  if unit == SECRET_UNIT then return secret(), secret() end
end
function UnitClass(unit)
  if unit == SECRET_UNIT then return secret(), secret() end
  return "Priest", "PRIEST"
end

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
for _, m in ipairs({ "DataCollector", "SpecChecker", "LootMaster", "Mentions", "NoteCommand", "RosterLog",
                     "RecruitScanner", "BanList", "RecruitmentSystem", "RaidTracker", "SoftResSystem" }) do
  dofile(ADDON .. "/Modules/" .. m .. ".lua")
end
local Compat = BRutus.Compat
local recorded = {}
BRutus.RecordError = function(_, msg) recorded[#recorded + 1] = msg end
BRutus.Print = function(_, msg) printed[#printed + 1] = msg end
BRutus.IsOfficer = function() return true end

-- ── 1. Compat.IsSecret ──────────────────────────────────────────────────
issecretvalue = nil
check(Compat.IsSecret(secret()) == false, "without the Secret Values system nothing is secret")
issecretvalue = isSecret
check(Compat.IsSecret(secret()) == true, "a secret value is secret")
check(Compat.IsSecret("text", 3, nil) == false, "plain values and nil are not")
check(Compat.IsSecret("text", secret()) == true, "any secret among the arguments counts")
check(Compat.IsSecret(nil, nil, secret()) == true, "past nil arguments too")
check(Compat.IsSecret() == false, "no arguments is not secret")

-- ── 2. Compat.UnitIdentity ──────────────────────────────────────────────
local name, realm, class = Compat.UnitIdentity("raid1")
check(name == "Bob" and realm == "Forever" and class == "PRIEST", "a readable unit gives its name, realm and class file")
check(select("#", Compat.UnitIdentity(SECRET_UNIT)) == 0, "a restricted unit gives nothing")
local oldClass = UnitClass
UnitClass = function(unit) if unit == "raid1" then return "Priest", secret() end return oldClass(unit) end
check(select("#", Compat.UnitIdentity("raid1")) == 0, "a secret class alone makes the unit unreadable")
UnitClass = oldClass
issecretvalue = nil
check(Compat.UnitIdentity("raid1") == "Bob", "on a client without the system it is UnitName and UnitClass")
issecretvalue = isSecret

-- ── 3. A secret never reaches the addon-message path ────────────────────
local sent = 0
C_ChatInfo = { SendAddonMessage = function() sent = sent + 1 end }
recorded = {}
Compat.SendAddonMessage("GuildOS", secret(), "GUILD")
check(sent == 0, "a secret text is not sent (SendAddonMessage refuses secret arguments)")
-- On the client a secret string's type is "string", so only the guard stands before #msg.text; the
-- fake is a table, which the type check would also refuse, so the reason is what proves the guard.
check(recorded[#recorded] and recorded[#recorded]:find("result secret", 1, true), "and it is recorded as secret")
Compat.SendAddonMessage("GuildOS", "hello", "GUILD", secret())
check(sent == 0, "a secret target is not sent either")
Compat.SendAddonMessage("GuildOS", "hello", "GUILD")
check(sent == 1, "a readable message still goes")

-- ── 4. Chat handlers return before a secret payload ─────────────────────
local function handlerOf(setup)
  local before = #frames
  setup()
  for i = #frames, before + 1, -1 do
    if frames[i].scripts.OnEvent then return frames[i].scripts.OnEvent end
  end
  error("no handler registered")
end
local function fires(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and os.getenv("SV_DEBUG") then io.stderr:write(tostring(err), "\n") end
  return ok, err
end

BRutus.db = {
  mentions = { enabled = true, guild = true, officer = true, ownName = true, watchWords = { "raid" }, sound = false, log = {} },
  noteCommand = { enabled = true },
  recruitScanner = { inbox = {} },
  recruitment = { autoInvite = { enabled = true, keyword = "inv" } },
  rosterLog = { entries = {} },
  banList = { entries = {} },
  members = {},
  settings = {},
}

local mentions = handlerOf(function() BRutus.Mentions:_SetupHook() end)
check(fires(mentions, nil, "CHAT_MSG_GUILD", secret(), secret()), "Mentions: a secret line and sender do not raise")
check(fires(mentions, nil, "CHAT_MSG_GUILD", "raid tonight", secret()), "Mentions: a secret sender alone does not raise")
local mentioned
BRutus.Mentions._cd = {}  -- made by Initialize, which this test does not run
BRutus.Mentions._Record = function(_, term, sender) mentioned = { term, sender } end
check(fires(mentions, nil, "CHAT_MSG_GUILD", "raid tonight", "Bob-Forever") and mentioned
      and mentioned[1] == "raid" and mentioned[2] == "Bob", "Mentions: a readable line still records the mention")

local note = handlerOf(function() BRutus.NoteCommand:_SetupHook() end)
check(fires(note, nil, "CHAT_MSG_GUILD", secret(), secret()), "NoteCommand: a secret line does not raise")
check(fires(note, nil, "CHAT_MSG_GUILD", "!note main tank", secret()), "NoteCommand: a secret sender does not raise")
local parsed
BRutus.NoteCommand._Parse = function(_, msg) parsed = msg; return nil end
check(fires(note, nil, "CHAT_MSG_GUILD", secret(), "Bob-Forever") and parsed == nil, "NoteCommand: a secret line is never parsed")
check(fires(note, nil, "CHAT_MSG_GUILD", "!note main tank", "Bob-Forever") and parsed == "!note main tank",
      "NoteCommand: a readable line is parsed as before")

local roster = handlerOf(function() BRutus.RosterLog:_SetupDetection() end)
BRutus.RosterLog._ready = true  -- after setup, which starts it unready
check(fires(roster, nil, "CHAT_MSG_SYSTEM", secret()), "RosterLog: a secret system line does not raise")
local logged
BRutus.RosterLog._ParseSystem = function(_, msg) return { action = "join", target = msg } end
BRutus.RosterLog.Add = function(_, evt) logged = evt end
check(fires(roster, nil, "CHAT_MSG_SYSTEM", "Bob has joined the guild.") and logged and logged.action == "join",
      "RosterLog: a readable system line is still logged")

BRutus.RecruitScanner._contactCd = { Bob = true }
local scanner = handlerOf(function() BRutus.RecruitScanner:_RegisterEvents() end)
check(fires(scanner, nil, "CHAT_MSG_WHISPER", "hi", secret()), "RecruitScanner: a secret whisperer does not raise")
check(#BRutus.db.recruitScanner.inbox == 0, "RecruitScanner: and nothing unreadable lands in the inbox")
check(fires(scanner, nil, "CHAT_MSG_WHISPER", "hi there", "Bob-Forever"), "RecruitScanner: a readable whisper is handled")
check(#BRutus.db.recruitScanner.inbox == 1, "RecruitScanner: and lands in the inbox as before")

local ban = handlerOf(function() BRutus.BanList:_SetupDetection() end)
BRutus.BanList._ready = true
check(fires(ban, nil, "CHAT_MSG_SYSTEM", secret()), "BanList: a secret join line does not raise")
check(fires(ban, nil, "CHAT_MSG_WHISPER", "hello", secret()), "BanList: a secret whisperer does not raise")
local alerted = 0
BRutus.BanList.IsBanned = function() return true end
BRutus.BanList.Get = function(_, n) return { name = n } end
BRutus.BanList._Alert = function() alerted = alerted + 1 end
BRutus.BanList._ParseJoin = function() return "Bob" end
check(fires(ban, nil, "CHAT_MSG_SYSTEM", "Bob has joined the guild.") and alerted == 1, "BanList: a readable join still alerts")
check(fires(ban, nil, "CHAT_MSG_WHISPER", "hello", "Bob-Forever") and alerted == 2, "BanList: a readable whisper still alerts")

local welcome = handlerOf(function() BRutus.Recruitment:RegisterWelcomeEvent() end)
BRutus.Recruitment._rosterReady = true
check(fires(welcome, nil, "CHAT_MSG_SYSTEM", secret()), "Recruitment welcome: a secret system line does not raise")
local joined
BRutus.RecruitEngagement = { RecordJoin = function(_, who) joined = who end }
BRutus.db.recruitment.welcomeEnabled = false
check(fires(welcome, nil, "CHAT_MSG_SYSTEM", "Bob has joined the guild.") and joined == "Bob",
      "Recruitment welcome: a readable join is still credited")
local autoInvite = handlerOf(function() BRutus.Recruitment:RegisterAutoInviteEvent() end)
check(fires(autoInvite, nil, "CHAT_MSG_WHISPER", secret(), secret()), "Recruitment auto-invite: a secret whisper does not raise")
local invited
BRutus.Recruitment._MatchKeyword = function() return true end
BRutus.Recruitment._HandleKeywordWhisper = function(_, who) invited = who end
check(fires(autoInvite, nil, "CHAT_MSG_WHISPER", "inv pls", "Bob-Forever") and invited == "Bob",
      "Recruitment auto-invite: a readable whisper still invites")

local LootMaster = BRutus.LootMaster
LootMaster.listeningForRolls, LootMaster.activeLoot = true, { itemId = 1 }
LootMaster.rollPattern = "(.+) rolls (%d+) %((%d+)%-(%d+)%)"
check(fires(function() LootMaster:OnSystemMessage(secret()) end), "LootMaster: a secret roll line does not raise")
local rolled
local realProcess = LootMaster.ProcessSystemRoll
LootMaster.ProcessSystemRoll = function(_, msg) rolled = msg end
check(fires(function() LootMaster:OnSystemMessage("Bob rolls 55 (1-100)") end) and rolled == "Bob rolls 55 (1-100)",
      "LootMaster: a readable roll line is still processed")
LootMaster.ProcessSystemRoll = realProcess

-- ── 5. Group units: the unreadable member is skipped, the rest kept ─────
local RaidTracker = BRutus.RaidTracker
RaidTracker.currentRaid = { players = {}, snapshots = {} }
RaidTracker.CheckPlayerConsumes = function() return nil end
RaidTracker.BroadcastRaidData = function() end
check(fires(function() RaidTracker:TakeSnapshot("test") end), "RaidTracker: a snapshot with a restricted member does not raise")
local keys = 0
for _ in pairs(RaidTracker.currentRaid.players) do keys = keys + 1 end
check(keys == 2 and RaidTracker.currentRaid.players[BRutus:GetPlayerKey("Bob", "Forever")]
      and RaidTracker.currentRaid.players[BRutus:GetPlayerKey("Ana")],
      "RaidTracker: the readable member and the player are recorded, and the restricted one is not")

local SoftRes = BRutus.SoftRes
SoftRes.GetReserves = function() return { { name = "Bob" } } end
check(fires(function() SoftRes:GetReservesForDisplay(1) end), "SoftRes: reserves with a restricted member in the raid do not raise")

-- A trade: the pending item's player is compared with who the trade is with. Lua 5.1 never calls
-- __eq across types, so this fake cannot make that comparison raise the way the client does; what
-- it proves is that a secret name returns before anything reaches the print that would show it.
LootMaster.pendingTrades = { { player = "Bob", itemId = 1, link = "[Hood]" } }
LootMaster.FindItemInBags = function() return 0, 1 end
local oldName = UnitName
UnitName = function(unit) if unit == "NPC" then return secret() end return oldName(unit) end
printed = {}
check(fires(function() LootMaster:OnTradeShow() end), "LootMaster: a trade with a secret name returns quietly")
check(not LootMaster.pendingTrades[1].addedToTrade and #printed == 0, "LootMaster: and adds nothing to the trade")
UnitName = function(unit) if unit == "NPC" then return "Bob" end return oldName(unit) end
BRutus.Compat.UseContainerItem = function() end
check(fires(function() LootMaster:OnTradeShow() end), "LootMaster: a trade with a readable name still runs")
check(LootMaster.pendingTrades[1].addedToTrade == true, "LootMaster: and adds the pending item as before")
UnitName = oldName

-- ── 6. Own stats: a restricted stat is left out ─────────────────────────
function UnitHealthMax() return secret() end
function UnitPowerMax() return 3000 end
function UnitStat(_, i) if i == 3 then return secret() end return 50 + i end
local ok, stats = pcall(function() return BRutus.DataCollector:CollectStats() end)
check(ok, "CollectStats: restricted stats do not raise")
check(stats.health == nil and stats.stamina == nil, "CollectStats: the restricted ones are left out")
check(stats.mana == 3000 and stats.strength == 51 and stats.spirit == 55, "CollectStats: the readable ones are kept")
issecretvalue = nil
function UnitHealthMax() return 4000 end
function UnitStat(_, i) return 50 + i end
stats = BRutus.DataCollector:CollectStats()
check(stats.health == 4000 and stats.stamina == 53, "CollectStats: on a client without the system every stat is read")
issecretvalue = isSecret

print("secret-values: " .. checks .. " checks passed")
