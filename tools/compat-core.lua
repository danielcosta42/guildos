-- Version-sensitive calls go through Core/Compat.lua (issue #10), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/DataCollector.lua, Modules/SpecChecker.lua,
-- Modules/CommSystem.lua, Modules/LootMaster.lua, Modules/ConsumableChecker.lua,
-- Modules/CompanionExport.lua and tools/compat-guard.lua, under a stubbed TBC Anniversary client.
--
-- The loop that matters on beta day one (the roster, your own character, sync with the other
-- officers) called these APIs directly. One missing talent or profession function stopped
-- collection, and with it the broadcast and the companion export; sends ignored their result,
-- so a chat lockdown dropped sync without a trace. This proves each wrapper with the namespaced
-- API, the old global and neither; that collection completes with those fields absent and the
-- other officers follow; that sends hold, retry or record by result; and that the guard CI runs
-- finds these APIs reached by name outside Compat.
--
--   luajit -e 'ADDON="."' tools/compat-core.lua
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

-- ── The client ──────────────────────────────────────────────────────────
local frames, timers = {}, {}
local HOOD = "|cffa335ee|Hitem:30107:2999:0:0:0:0:0:0:70|h[Hood]|h|r"
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
function CreateFrame()
  local f = { scripts = {}, events = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  frames[#frames + 1] = f
  return f
end
function GetServerTime() return 1757800000 end
function GetTime() return 1000 end
function time() return 1757800000 end
function IsInGuild() return true end
function IsInRaid() return true end
function IsInGroup() return true end
function hooksecurefunc() end
function debugstack() return "" end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetBuildInfo() return "2.5.6", "1", "", 20506 end
function UnitName(unit)
  if unit == "player" then return "Ana" end
  if unit == "raid1" or unit == "NPC" then return "Bob" end
end
function GetUnitName() return nil end
function GetRealmName() return "Firemaw" end
function UnitClass() return "Priest", "PRIEST" end
function UnitLevel() return 70 end
function UnitRace() return "Human", "Human" end
function UnitSex() return 3 end
function GetNumGroupMembers() return 1 end
function UnitExists(unit) return unit == "raid1" end
function UnitIsConnected() return true end
function CanInspect() return true end
function NotifyInspect() end
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
tinsert, strlower = table.insert, string.lower
C_Timer = { After = function(d, fn) timers[#timers + 1] = { d, fn } end }
-- Read once when Compat.lua loads. Codes other than the fallbacks, so the names are proven to be read.
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 13, ChannelThrottle = 18, GeneralError = 9,
                                    AddOnMessageLockdown = 21 } }
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
for _, m in ipairs({ "DataCollector", "SpecChecker", "CommSystem", "LootMaster", "ConsumableChecker", "CompanionExport" }) do
  dofile(ADDON .. "/Modules/" .. m .. ".lua")
end
local Compat = BRutus.Compat
local errors = {}
BRutus.RecordError = function(_, msg) errors[#errors + 1] = msg end
BRutus.PREFIX = BRutus.PREFIX or "GuildOS"
BRutus.db = { members = {}, settings = { companion = true }, raidTracker = { sessions = {} },
              consumableChecks = { lastResults = {} } }
BRutus.SlotIDs = { { id = 1, name = "HeadSlot" }, { id = 5, name = "ChestSlot" } }

-- ── 1. Wrappers: namespaced API, old global, neither ────────────────────
C_Item = { GetItemInfo = function(i) return "ns:" .. i, "nslink", 4, 110 end }
GetItemInfo = function(i) return "g:" .. i, "glink", 3, 100 end
local n, l, q, lvl = Compat.GetItemInfo(7)
check(n == "ns:7" and l == "nslink" and q == 4 and lvl == 110, "GetItemInfo prefers C_Item and passes every return through")
C_Item = nil
n, l, q = Compat.GetItemInfo(7)
check(n == "g:7" and l == "glink" and q == 3, "without C_Item it uses the global")
GetItemInfo = nil
check(select("#", Compat.GetItemInfo(7)) == 0, "with neither it returns nothing and does not raise")

C_Spell = {
  GetSpellInfo = function(id) return { name = "Flask", iconID = 99, castTime = 0, minRange = 1, maxRange = 5, spellID = id } end,
  GetSpellTexture = function() return 1234 end,
}
GetSpellInfo = function() return "global", "Rank 1", 1 end
GetSpellTexture = function() return 5678 end
local sn, rank, icon, cast, minR, maxR, sid = Compat.GetSpellInfo(28521)
check(sn == "Flask" and rank == nil and icon == 99 and cast == 0 and minR == 1 and maxR == 5 and sid == 28521,
      "GetSpellInfo maps C_Spell's table to the global's order")
check(Compat.GetSpellTexture(1) == 1234, "GetSpellTexture prefers C_Spell")
C_Spell.GetSpellInfo = function() return nil end
check(Compat.GetSpellInfo(1) == nil, "an unknown spell from C_Spell gives nil")
C_Spell = nil
check(Compat.GetSpellInfo(1) == "global" and Compat.GetSpellTexture(1) == 5678, "without C_Spell both use the globals")
GetSpellInfo, GetSpellTexture = nil, nil
check(Compat.GetSpellInfo(1) == nil and Compat.GetSpellTexture(1) == nil, "with neither both give nil")

C_UnitAuras = { GetBuffDataByIndex = function(_, i)
  if i > 1 then return nil end
  return { name = "Well Fed", icon = 7, applications = 3, dispelName = "Magic", duration = 900, expirationTime = 1000,
           sourceUnit = "player", isStealable = false, nameplateShowPersonal = false, spellId = 33254 }
end }
UnitBuff = function() return "global buff" end
local aura = { Compat.UnitBuff("player", 1) }
check(aura[1] == "Well Fed" and aura[2] == 7 and aura[3] == 3 and aura[4] == "Magic" and aura[5] == 900
      and aura[6] == 1000 and aura[7] == "player" and aura[10] == 33254,
      "UnitBuff maps C_UnitAuras' aura data to UnitBuff's order, every position through spellId tenth")
check(Compat.UnitBuff("player", 2) == nil, "past the last aura it gives nil")
C_UnitAuras = nil
check(Compat.UnitBuff("player", 1) == "global buff", "without C_UnitAuras it uses the global")
UnitBuff = nil
check(Compat.UnitBuff("player", 1) == nil, "with neither it gives nil")

local used = {}
C_Container = {
  GetContainerNumSlots = function() return 16 end,
  GetContainerItemLink = function(b, s) return "nslink" .. b .. s end,
  GetContainerItemInfo = function() return { itemID = 30107, hyperlink = "x" } end,
  UseContainerItem = function(b, s) used[#used + 1] = "ns" .. b .. s end,
}
GetContainerNumSlots = function() return 12 end
GetContainerItemLink = function() return "glink" end
GetContainerItemInfo = function() return 111, 2, false, 4, false, false, "|Hitem:30107:|h" end
UseContainerItem = function(b, s) used[#used + 1] = "g" .. b .. s end
check(Compat.GetContainerNumSlots(0) == 16 and Compat.GetContainerItemLink(1, 2) == "nslink12"
      and Compat.GetContainerItemInfo(0, 1).itemID == 30107, "bag calls prefer C_Container")
Compat.UseContainerItem(0, 3)
check(used[1] == "ns03", "UseContainerItem prefers C_Container")
C_Container = nil
local info = Compat.GetContainerItemInfo(0, 1)
check(Compat.GetContainerNumSlots(0) == 12 and Compat.GetContainerItemLink(1, 2) == "glink"
      and info.itemID == 30107 and info.hyperlink == "|Hitem:30107:|h" and info.stackCount == 2 and info.quality == 4,
      "without C_Container they use the globals, and item info becomes the namespaced table")
Compat.UseContainerItem(0, 4)
check(used[2] == "g04", "UseContainerItem falls back to the global")
GetContainerItemInfo = function() return nil end
check(Compat.GetContainerItemInfo(0, 9) == nil, "an empty slot gives nil")
GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo, UseContainerItem = nil, nil, nil, nil
check(Compat.GetContainerNumSlots(0) == 0 and Compat.GetContainerItemLink(0, 1) == nil
      and Compat.GetContainerItemInfo(0, 1) == nil and Compat.UseContainerItem(0, 1) == nil,
      "with neither, a bag has no slots and nothing raises")

local tabArgs, talentInspect
GetNumTalentTabs = function(...) tabArgs = select("#", ...); return 3 end
GetNumTalents = function(tab, inspect) talentInspect = inspect; return tab * 10 end
GetTalentInfo = function(tab, i, inspect) return "t" .. tab .. i .. tostring(inspect), "icon", 1, 2, 5, 5 end
GetNumSkillLines = function() return 2 end
GetSkillLineInfo = function(i) return "Skill" .. i, false, nil, 300 end
check(Compat.GetNumTalentTabs() == 3 and tabArgs == 0, "own talent tabs call the global with no argument, as before")
check(Compat.GetNumTalentTabs(true) == 3 and tabArgs == 1, "inspect passes its flag")
check(Compat.GetNumTalents(2, true) == 20 and talentInspect == true and Compat.GetTalentInfo(1, 4, true) == "t14true",
      "GetNumTalents and GetTalentInfo pass the inspect flag through")
check(Compat.GetNumSkillLines() == 2 and select(4, Compat.GetSkillLineInfo(1)) == 300, "skill-line calls pass through")
GetNumTalentTabs, GetNumTalents, GetTalentInfo, GetNumSkillLines, GetSkillLineInfo = nil, nil, nil, nil, nil
local tabs, why = Compat.GetNumTalentTabs()
check(tabs == nil and why == "no-api", "no talent API: nil, no-api")
check(select(2, Compat.GetNumTalents(1)) == "no-api" and Compat.GetTalentInfo(1, 1) == nil, "the other talent calls too")
check(select(2, Compat.GetNumSkillLines()) == "no-api" and Compat.GetSkillLineInfo(1) == nil, "no skill-line API: nil, no-api")

local registered = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function(p) registered[#registered + 1] = "ns:" .. p; return true end }
RegisterAddonMessagePrefix = function(p) registered[#registered + 1] = "g:" .. p; return true end
Compat.RegisterAddonPrefix("GuildOS")
C_ChatInfo = {}
Compat.RegisterAddonPrefix("BRutusLM")
RegisterAddonMessagePrefix = nil
Compat.RegisterAddonPrefix("x")
check(registered[1] == "ns:GuildOS" and registered[2] == "g:BRutusLM" and #registered == 2,
      "the addon prefix registers through C_ChatInfo, else the old global, else not at all")
local roster = {}
C_GuildInfo = { GuildRoster = function() roster[#roster + 1] = "ns" end }
GuildRoster = function() roster[#roster + 1] = "g" end
Compat.GuildRoster(); C_GuildInfo = nil; Compat.GuildRoster(); GuildRoster = nil; Compat.GuildRoster()
check(roster[1] == "ns" and roster[2] == "g" and #roster == 2, "the roster request prefers C_GuildInfo")
check(Compat.NewTimer == nil, "the NewTimer shim nobody called is gone")

-- ── 2. Sends: held, retried or recorded by result ───────────────────────
local sent, LOCK = {}, false
local ctl = { SendAddonMessage = function(_, prio, prefix, text, chattype, target, queue, cb)
  sent[#sent + 1] = { prio = prio, prefix = prefix, text = text, chattype = chattype, target = target, queue = queue, cb = cb }
end }
ChatThrottleLib = ctl
C_ChatInfo = { InChatMessagingLockdown = function() return LOCK end }
local function last() return sent[#sent] end
local function runPolls()
  for _, t in ipairs(timers) do if t[1] == Compat.HELD_POLL then t[2]() end end
end

Compat.SendAddonMessage("GuildOS", "a", "GUILD")
check(#sent == 1 and last().prio == "BULK" and last().prefix == "GuildOS" and last().chattype == "GUILD",
      "a send goes through ChatThrottleLib, BULK by default")
last().cb(nil, true, 0)
check(#Compat._held == 0 and #errors == 0 and #timers == 0, "success: nothing held, retried or recorded")

Compat.SendAddonMessage("GuildOS", "b", "GUILD")
last().cb(nil, false, 21)
check(#Compat._held == 1 and Compat._held[1].text == "b", "a lockdown result holds the message")
Compat.SendAddonMessage("GuildOS", "c", "GUILD")
check(#sent == 2 and #Compat._held == 2, "later sends wait behind a held one, so the order stays")

local flusher
for _, f in ipairs(frames) do if f.events.PLAYER_REGEN_ENABLED and f.events.ZONE_CHANGED_NEW_AREA then flusher = f end end
check(flusher and flusher.scripts.OnEvent, "the flush listens for combat ending and zone changes")
LOCK = true
flusher.scripts.OnEvent(flusher, "PLAYER_REGEN_ENABLED")
check(#sent == 2 and #Compat._held == 2, "nothing goes out while the lockdown lasts")
LOCK = false
flusher.scripts.OnEvent(flusher, "PLAYER_REGEN_ENABLED")
check(#sent == 4 and sent[3].text == "b" and sent[4].text == "c" and #Compat._held == 0,
      "once combat ends, held messages go out in order")
sent[3].cb(nil, true, 0); sent[4].cb(nil, true, 0)

LOCK = true
Compat.SendAddonMessage("GuildOS", "d", "GUILD")
check(#sent == 4 and #Compat._held == 1, "already in lockdown: held without trying")
LOCK = false
flusher.scripts.OnEvent(flusher, "ZONE_CHANGED_NEW_AREA")
check(#sent == 5 and last().text == "d", "and sent on a zone change")
last().cb(nil, true, 0)

runPolls()
timers = {}
LOCK = true
Compat.SendAddonMessage("GuildOS", "p", "GUILD")
check(#Compat._held == 1 and #timers == 1 and timers[1][1] == Compat.HELD_POLL and Compat.HELD_POLL == 2,
      "holding a message starts a 2-second poll")
timers[1][2]()
check(#Compat._held == 1 and #timers == 2, "still locked at the poll: held again, and polled again")
LOCK = false
local sentBefore = #sent
timers[2][2]()
check(#sent == sentBefore + 1 and last().text == "p" and #Compat._held == 0 and #timers == 2,
      "a lockdown that lifts with neither combat ending nor a zone change is caught by the poll, which then stops")
last().cb(nil, true, 0)

local function polls()
  local armed = 0
  for _, t in ipairs(timers) do if t[1] == Compat.HELD_POLL then armed = armed + 1 end end
  return armed
end
timers = {}
LOCK = true
for i = 1, 5 do Compat.SendAddonMessage("GuildOS", "s" .. i, "GUILD") end
check(#Compat._held == 5 and polls() == 1, "five held messages arm one poll, not five")
timers[1][2]()
check(#Compat._held == 5 and polls() == 2, "a poll that finds the lockdown still on arms exactly one more")
LOCK = false
timers[2][2]()
check(#Compat._held == 0 and polls() == 2 and last().text == "s5", "once it lifts, all five go out and the poll stops")
for i = #sent - 4, #sent do sent[i].cb(nil, true, 0) end

timers = {}
Compat.SendAddonMessage("GuildOS", "e", "GUILD")
for attempt, delay in ipairs({ 1, 2, 4, 8 }) do
  last().cb(nil, false, 18)
  check(#timers == attempt and timers[attempt][1] == delay, "channel throttle: retry " .. attempt .. " after " .. delay .. "s")
  timers[attempt][2]()
  check(last().text == "e", "the retry resends the same message")
end
last().cb(nil, false, 18)
check(#timers == 4 and #errors == 1 and errors[1]:find("result 18", 1, true), "after four retries it is recorded and dropped")

Compat.SendAddonMessage("GuildOS", "f", "GUILD"); last().cb(nil, false, 9)
Compat.SendAddonMessage("GuildOS", "g", "GUILD"); last().cb(nil, false, 9)
check(#errors == 2 and errors[2]:find("result 9", 1, true) and #timers == 4 and #Compat._held == 0,
      "any other failure is recorded once per result and never retried")

sentBefore = #sent
Compat.SendAddonMessage("GuildOS", string.rep("x", 256), "GUILD")
check(#sent == sentBefore and #Compat._held == 0 and #errors == 3 and errors[3]:find("result invalid", 1, true),
      "a message over 255 bytes is recorded and never queued or sent")
Compat.SendAddonMessage("GuildOS", "x", "GUILD", nil, "URGENT")
Compat.SendAddonMessage(string.rep("p", 17), "x", "GUILD")
Compat.SendAddonMessage("GuildOS", nil, "GUILD")
Compat.SendAddonMessage("GuildOS", "x", nil)
Compat.SendAddonMessage("", "x", "GUILD")
Compat.SendAddonMessage(42, "x", "GUILD")
check(#sent == sentBefore and #Compat._held == 0 and #errors == 3,
      "an unknown priority, a prefix over 16 bytes, empty or not a string, no text or no channel is refused the same way, recorded once")

LOCK = true
Compat.SendAddonMessage("GuildOS", "r1", "GUILD")
Compat.SendAddonMessage("GuildOS", "r2", "GUILD")
LOCK = false
ChatThrottleLib = { SendAddonMessage = function(self, prio, prefix, text, ...)
  if text == "r1" then error("refused", 0) end
  return ctl.SendAddonMessage(self, prio, prefix, text, ...)
end }
Compat.FlushHeldMessages()
ChatThrottleLib = ctl
check(last().text == "r2" and #Compat._held == 0 and #errors == 4 and errors[4]:find("result error", 1, true),
      "a held message that raises is recorded, and the ones behind it still go")
last().cb(nil, true, 0)

LOCK = true
for i = 1, Compat.HELD_MAX + 5 do Compat.SendAddonMessage("GuildOS", "h" .. i, "GUILD") end
check(#Compat._held == Compat.HELD_MAX and Compat._held[1].text == "h6", "the held queue keeps the newest 200")
LOCK, Compat._held = false, {}

ChatThrottleLib = nil
local direct = {}
C_ChatInfo.SendAddonMessage = function(_, text) direct[#direct + 1] = text; return 21 end
Compat.SendAddonMessage("GuildOS", "i", "GUILD")
check(#direct == 1 and #Compat._held == 1, "without ChatThrottleLib the client's own result still holds a lockdown")
Compat._held = {}
C_ChatInfo.SendAddonMessage = function() return true end
Compat.SendAddonMessage("GuildOS", "j", "GUILD")
check(#Compat._held == 0 and #errors == 4, "and a plain true counts as sent")
ChatThrottleLib, C_ChatInfo.SendAddonMessage = ctl, nil
local errorsBefore, timersBefore = #errors, #timers
Compat.SendAddonMessage("GuildOS", "u", "GUILD")
last().cb(nil, false, 13)
check(#timers == timersBefore and #errors == errorsBefore + 1 and errors[#errors]:find("result 13", 1, true),
      "an AddonMessageThrottle reaching ChatThrottleLib's callback is recorded, not retried: ChatThrottleLib re-queues its own")

-- Without the names in Enum, the retail codes: 11 is the lockdown, 8 the channel throttle.
local savedCompat, savedEnum = BRutus.Compat, Enum
Enum = nil
dofile(ADDON .. "/Core/Compat.lua")
local Bare = BRutus.Compat
BRutus.Compat, Enum = savedCompat, savedEnum
Bare.SendAddonMessage("GuildOS", "k", "GUILD")
last().cb(nil, false, 11)
check(#Bare._held == 1, "without Enum's names, result 11 holds the message as a lockdown")
Bare._held = {}
timers = {}
Bare.SendAddonMessage("GuildOS", "t", "GUILD")
last().cb(nil, false, 8)
check(#timers == 1 and timers[1][1] == 1 and #Bare._held == 0, "and result 8 is retried as a channel throttle")
timers = {}
C_ChatInfo.SendAddonMessage = function() return 3 end
Bare.SendAddonMessageNow("GuildOS", "v", "RAID")
C_ChatInfo.SendAddonMessage = nil
check(#timers == 1 and timers[1][1] == 1, "and result 3 on a message sent now is retried, as ChatThrottleLib would")

-- ── 3. Every sender goes through it ─────────────────────────────────────
BRutus.CommSystem:SendRaw("S:hello")
check(last().prefix == BRutus.PREFIX and last().text == "S:hello" and last().chattype == "GUILD" and last().prio == "BULK",
      "guild sync sends through Compat, BULK by default")
BRutus.CommSystem:SendRaw("S:urgent", nil, "ALERT")
check(last().prio == "ALERT", "a sync priority is kept")
BRutus.CommSystem:SendRaw("S:psst", "Bob")
check(last().chattype == "WHISPER" and last().target == "Bob" and last().prio == "NORMAL", "a whisper to one officer keeps its target")
last().cb(nil, false, 21)
check(#Compat._held == 1 and Compat._held[1].text == "S:psst", "a sync message caught by a lockdown is held, not lost")
Compat._held = {}

local loot = {}
C_ChatInfo.SendAddonMessage = function(prefix, text, channel) loot[#loot + 1] = prefix .. "|" .. channel .. "|" .. text; return true end
local ctlSends = #sent
BRutus.LootMaster.testMode = false
BRutus.LootMaster:SafeSendAddon("BRutusLM", "AWARD|Ana|1|4||link", "RAID")
check(#loot == 1 and loot[1] == "BRutusLM|RAID|AWARD|Ana|1|4||link" and #sent == ctlSends,
      "loot messages go out at once, past ChatThrottleLib's queue, as before #10")
C_ChatInfo.SendAddonMessage = function() return 21 end
BRutus.LootMaster:SafeSendAddon("BRutusLM", "AWARD|Bob|1|4||link", "RAID")
check(#Compat._held == 1 and Compat._held[1].now and #sent == ctlSends, "a lockdown still holds a loot message, and it stays on the direct path")
Compat._held = {}
timers = {}
local tries = 0
C_ChatInfo.SendAddonMessage = function(_, text)
  tries = tries + 1
  if tries == 1 then return 13 end
  loot[#loot + 1] = text
  return true
end
BRutus.LootMaster:SafeSendAddon("BRutusLM", "AWARD|Cy|1|4||link", "RAID")
check(tries == 1 and #timers == 1 and timers[1][1] == 1 and #Compat._held == 0,
      "a loot message the client throttles is retried after a second, as ChatThrottleLib would have done")
timers[1][2]()
check(tries == 2 and loot[#loot] == "AWARD|Cy|1|4||link", "and delivered on the retry")
C_ChatInfo.SendAddonMessage = nil

-- ── 4. Own character: absent fields instead of a stopped collection ─────
local DC = BRutus.DataCollector
DC.CollectStats = function() return { stamina = 1 } end   -- not touched by #10
function GetInventoryItemLink(_, slot) if slot == 1 then return HOOD end end
GetItemInfo = function(link) return "Hood", link, 4, 120, 70, "Armor", "Cloth", 1, "INVTYPE_BAG" end
local bagReads = {}
C_Container = { GetContainerNumSlots = function() return 2 end,
                GetContainerItemLink = function(b, s) bagReads[#bagReads + 1] = b .. ":" .. s; return nil end }
local function talents(on)
  if on then
    GetNumTalentTabs = function() return 3 end
    GetNumTalents = function() return 2 end
    GetTalentInfo = function(tab, i) return "T" .. i, "icon", 1, i, tab == 2 and 5 or 0, 5 end
  else
    GetNumTalentTabs, GetNumTalents, GetTalentInfo = nil, nil, nil
  end
end
local function skills(on)
  if on then
    GetNumSkillLines = function() return 1 end
    GetSkillLineInfo = function() return "Tailoring", false, nil, 375, nil, nil, 375 end
  else
    GetNumSkillLines, GetSkillLineInfo = nil, nil
  end
end

talents(true); skills(true)
local d = DC:CollectMyData()
check(d.spec and d.spec.treeIndex == 2 and d.professions and #d.professions == 1 and d.gear[1].name == "Hood",
      "with every API: spec, professions and gear are collected")
check(#bagReads == 10 and bagReads[10] == "4:2", "the resistance scan reads every slot of the five bags through Compat")
local b = DC:GetBroadcastData()
check(type(b.professions) == "table" and #b.professions == 1 and b.absent == nil and d.absent == nil,
      "and the broadcast carries the professions, with no absent marker, as in 0.53.0")

skills(false)
d = DC:CollectMyData()
check(d.professions == nil and d.spec and d.gear[1].name == "Hood", "no skill-line API: professions absent, the rest collected")
b = DC:GetBroadcastData()
check(b.professions == nil and b.gear ~= nil and b.absent and b.absent.professions and not b.absent.spec,
      "the broadcast leaves the professions field out and names it as absent")

talents(false)
d = DC:CollectMyData()
check(d.spec == nil and not DC._snapshotIncomplete and d.gear[1].name == "Hood" and d.absent.spec and d.absent.professions,
      "no talent API: the saved spec is removed, no re-collect is waited for, gear still collected, both named absent")

GetNumTalentTabs = function() return 0 end   -- the API is there; the talents have not loaded yet
BRutus.db.members[BRutus:GetPlayerKey("Ana")].spec = { tree = "Holy" }
skills(true)
d = DC:CollectMyData()
check(d.spec and d.spec.tree == "Holy" and DC._snapshotIncomplete and d.absent == nil,
      "talents not loaded yet: the old spec stays, a re-collect is flagged, and nothing is named absent")

local bobKey = BRutus:GetPlayerKey("Bob")
BRutus.db.members[bobKey] = { name = "Bob", class = "PRIEST", lastUpdate = 1, spec = { tree = "Holy" },
                              professions = { { name = "Tailoring", rank = 375 } } }
DC:StoreReceivedData(bobKey, { name = "Bob", class = "PRIEST", lastUpdate = 2, absent = { spec = true, professions = true } })
check(BRutus.db.members[bobKey].spec == nil and BRutus.db.members[bobKey].professions == nil,
      "another officer drops the spec and professions it still held for a member whose client cannot collect them")
DC:StoreReceivedData(bobKey, { name = "Bob", class = "PRIEST", lastUpdate = 3, spec = { tree = "Shadow" }, professions = {} })
check(BRutus.db.members[bobKey].spec.tree == "Shadow" and type(BRutus.db.members[bobKey].professions) == "table"
      and BRutus.db.members[bobKey].absent == nil, "a later broadcast with both fields restores them and clears the marker")

local SC = BRutus.SpecChecker
local tabInspect
GetNumTalentTabs = function(inspect) tabInspect = inspect; return 3 end
GetNumTalents = function() return 2 end
GetTalentInfo = function(tab, i, inspect)
  return "T" .. i, "icon", 1, i, ((inspect and tab == 3) or (not inspect and tab == 1)) and 5 or 0, 5
end
SC:ScanGroup()
SC:OnInspectReady()
check(tabInspect == true and BRutus.db.members[bobKey].spec.treeIndex == 3,
      "an inspected raider's talents are read with the inspect flag: their tree 3, not the inspector's tree 1")
check(DC:CollectMyData().spec.treeIndex == 1, "and my own spec still reads my own talents")
talents(true)

-- ── 5. The export: absent, not empty ────────────────────────────────────
local ROSTER = { "Ana-Firemaw", "Bob-Firemaw", "Cy-Firemaw", "Dee-Firemaw" }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) if ROSTER[i] then return ROSTER[i], "Raider", 4, 70, "", "", "", "", true, 0, "PRIEST" end end
function GetGuildInfo() return "Raid Guild" end
local members = BRutus.db.members
BRutus.RaidTracker, BRutus.AttunementTracker, BRutus.LootTracker, BRutus.GearAudit = nil, nil, nil, nil
BRutus.db.members = {
  ["Ana-Firemaw"] = { lastUpdate = 1, professions = { { name = "Tailoring", rank = 375 } } },
  ["Bob-Firemaw"] = { lastUpdate = 1 },                     -- published from a client with no skill-line API
  ["Dee-Firemaw"] = { lastUpdate = 1, professions = {} },   -- published, and has no profession
}
local p = BRutus.Companion:BuildPayload()
local byKey = {}
for _, m in ipairs(p.members) do byKey[m.key] = m end
check(#byKey["Ana-Firemaw"].professions == 1, "a published professions list travels")
check(byKey["Bob-Firemaw"].professions == nil and not BRutus.Companion.EncodeJson(byKey["Bob-Firemaw"]):find('"professions"', 1, true),
      "a record published without a skill-line API has no professions field in the export")
check(type(byKey["Dee-Firemaw"].professions) == "table" and #byKey["Dee-Firemaw"].professions == 0,
      "a published empty list stays an empty list")
check(type(byKey["Cy-Firemaw"].professions) == "table" and #byKey["Cy-Firemaw"].professions == 0
      and BRutus.Companion.EncodeJson(byKey["Cy-Firemaw"]):find('"professions":[]', 1, true),
      "a member who never published keeps the empty list, as in 0.53.0")
BRutus.db.members = members

-- ── 6. The loot master's bags and trades ────────────────────────────────
local LM = BRutus.LootMaster
local placed = {}
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 2 and 3 or 1 end,
  GetContainerItemInfo = function(bag, slot) return { itemID = (bag == 2 and slot == 3) and 30107 or 1 } end,
  GetContainerItemLink = function(bag, slot) if bag == 2 and slot == 3 then return HOOD end end,
  UseContainerItem = function(bag, slot) placed[#placed + 1] = bag .. ":" .. slot end,
}
local bag, slot = LM:FindItemInBags(30107)
check(bag == 2 and slot == 3 and LM:FindItemInBags(99) == nil,
      "the loot master finds an item in the last slot of a bag through Compat, and nothing it does not carry")
LM.pendingTrades = { { player = "Bob", itemId = 30107, link = HOOD } }
LM:OnTradeShow()
check(placed[1] == "2:3" and LM.pendingTrades[1].addedToTrade, "opening a trade with the winner places the item through Compat")
local announced
LM.AnnounceItem = function(_, link) announced = link end
LM.testMode, LM.activeLoot = true, nil
LM:RollFromBag(2, 3)
check(announced == HOOD, "a roll from the bags reads the item link through Compat and announces it")

-- ── 7. The roster request and the consumable check ──────────────────────
local asked, opened = {}, false
C_GuildInfo = { GuildRoster = function() asked[#asked + 1] = "ns" end }
BRutus.UI = { ToggleMain = function() opened = true end }
BRutus:ToggleRoster()
check(asked[1] == "ns" and opened, "opening the window requests the guild roster through Compat")
local CC = BRutus.ConsumableChecker
check(CC ~= nil, "the consumable check loads on Anniversary")
C_UnitAuras = { GetBuffDataByIndex = function(unit, i)
  if unit == "raid1" and i == 1 then return { name = "Flask of Blinding Light", spellId = 28521 } end
end }
C_Spell, GetSpellInfo = nil, function() return nil end
local found = CC:CheckRaid()[bobKey]
check(found and found.buffs.flask and found.buffs.flask.id == 28521, "the consumable check reads a raider's buffs through Compat")
C_UnitAuras = { GetBuffDataByIndex = function(unit, i)
  if unit == "raid1" and i == 1 then return { name = "Frasco da Luz Cegante" } end
end }
GetSpellInfo = function(id) return id == 28521 and "Frasco da Luz Cegante" or nil end
found = CC:CheckRaid()[bobKey]
check(found and found.buffs.flask and found.buffs.flask.id == 28521,
      "and matches a buff by the localized name Compat.GetSpellInfo gives")

-- ── 8. The guard CI runs ────────────────────────────────────────────────
COMPAT_GUARD_LIBRARY = true
local G = dofile(ADDON .. "/tools/compat-guard.lua")
COMPAT_GUARD_LIBRARY = nil
local hits = G.run(ADDON)
check(#hits == 0, "no version-sensitive call is left outside Core/Compat.lua: " .. table.concat(hits, "; "))
local exempt = 0
for _ in pairs(G.EXEMPT) do exempt = exempt + 1 end
check(exempt == 3 and G.EXEMPT["Core/Compat.lua"] and G.EXEMPT["Core/Probe.lua"] and G.EXEMPT["Modules/ChehulNet.lua"],
      "exempt: Compat, Probe (API names as strings) and ChehulNet (shared verbatim), nothing else")
local TREE = {
  ["root/GuildOS.toc"] = "## Title: x\nCore\\A.lua\nModules\\B.lua\nUI\\C.lua\nLibs\\D.lua\nCore\\Missing.lua\nCore\\Compat.lua\n",
  ["root/Core/A.lua"] = "GetItemInfo(1)\n",
  ["root/Modules/B.lua"] = "local x = 1\nC_Container.UseContainerItem(0, 1)\n",
  ["root/UI/C.lua"] = "UnitBuff('player', 1)\n",
  ["root/Libs/D.lua"] = "GetItemInfo(1)\n",
  ["root/Core/Compat.lua"] = "GetItemInfo(1)\n",
}
local planted = G.run("root", function(path) return TREE[path] end)
table.sort(planted)
check(table.concat(planted, ";") == "Core/A.lua:1: GetItemInfo;Core/Missing.lua:0: listed in the TOC but missing;"
      .. "Modules/B.lua:2: C_Container;UI/C.lua:1: UnitBuff",
      "the guard reads every TOC file in Core, Modules and UI, skips Libs and Compat, and fails on a missing one: "
      .. table.concat(planted, ";"))
check(#G.files(ADDON) > 80, "and the addon's own TOC lists its files (" .. #G.files(ADDON) .. ")")
local function flags(src) return #G.scan("x.lua", src) end
for _, call in ipairs({
  "GetItemInfo(1)", "GetSpellInfo(1)", "GetSpellTexture(1)", "UnitBuff('player', 1)", "GetNumTalentTabs()",
  "GetNumTalents(1)", "GetTalentInfo(1, 1)", "GetNumSkillLines()", "GetSkillLineInfo(1)", "GetContainerNumSlots(0)",
  "GetContainerItemLink(0, 1)", "GetContainerItemInfo(0, 1)", "UseContainerItem(0, 1)", "GuildRoster()",
  "RegisterAddonMessagePrefix('p')", "SendAddonMessage('p', 'x', 'GUILD')", "if GetItemInfo then end",
  "local a = x and GetSpellInfo(1)", [[local s = "Item: " .. GetItemInfo(id)]], "_G.GetItemInfo(1)",
  [[_G["GetItemInfo"](1)]], "local C = C_Container; C.UseContainerItem(0, 1)", [[C_Item["GetItemInfo"](1)]],
  "if C_Spell then end", "C_UnitAuras.GetBuffDataByIndex('player', 1)", "local CTL = ChatThrottleLib",
  "ChatThrottleLib.SendAddonMessage(ChatThrottleLib, 'BULK', 'p', 'x', 'GUILD')",
  "ChatThrottleLib:SendAddonMessage('BULK', 'p', 'x', 'GUILD')", "C_GuildInfo.GuildRoster()",
  "C_ChatInfo.RegisterAddonMessagePrefix('p')", "C_ChatInfo.SendAddonMessage('p', 'x', 'GUILD')",
  "local ci = C_ChatInfo; ci.SendAddonMessage('p', 'x', 'GUILD')",
  [[C_ChatInfo["SendAddonMessage"]('p', 'x', 'GUILD')]], [[C_ChatInfo["RegisterAddonMessagePrefix"]('p')]],
  [[C_GuildInfo["GuildRoster"]()]], "local G = _G; G.GetItemInfo(id)", "getfenv(0).UnitBuff('player', 1)",
  [[rawget(_G, "GetItemInfo")]], "local Compat = C_ChatInfo", "C_ChatInfo.SendAddonMessageLogged('p', 'x', 'GUILD')",
  [[local s = "x"..GetItemInfo(id)]], [[_G[ "GetItemInfo" ](1)]], [[_G["C_Item"].GetItemInfo(1)]],
}) do
  check(flags(call) >= 1, "the guard flags " .. call)
end
for _, src in ipairs({
  "-- GetItemInfo(1)", "--[[ UnitBuff('player', 1)\nGetSpellInfo(2) ]]", "--[==[ C_Item.GetItemInfo(1) ]==]",
  "local s = 'GetItemInfo(1)'", [[local s = "C_Container.UseContainerItem(0, 1)"]], [[local s = "a\"GetItemInfo(1)"]],
  "local s = [[GuildRoster()]]", "local s = [=[ C_Spell.GetSpellInfo(1) ]=]", [[local s = '_G["GetItemInfo"]']],
  [[-- _G["GetItemInfo"](1)]], "BRutus.Compat.GetItemInfo(1)", "Compat.UnitBuff('player', 1)", "tip:GetSpellInfo(1)",
  "local MyGetItemInfo = 1", "GetItemInfoInstant(1)", "C_ChatInfo.InChatMessagingLockdown()",
  "BRutus.Compat.SendAddonMessage('p', 'x', 'GUILD')", "self.Compat.GuildRoster()",
  "BRutus.Compat.SendAddonMessageNow('p', 'x', 'RAID')", "local f = _G[name]",
  "BRutus.Compat\n  .SendAddonMessage('p', 'x', 'GUILD')", "local Compat = BRutus.Compat", "_G.SLASH_GUILDOS1 = '/guildos'",
  "local f = _G[frameName .. i]",
}) do
  check(flags(src) == 0, "the guard ignores " .. src:gsub("\n", " "))
end
local h = G.scan("x.lua", "--[[\nline two\n]]\nlocal s = 'a'\nGetItemInfo(1)")
check(#h == 1 and h[1] == "x.lua:5: GetItemInfo", "a hit names its file and line, past a block comment: " .. tostring(h[1]))
local release = assert(io.open(ADDON .. "/.github/workflows/release.yml", "rb")):read("*a"):gsub("\r\n", "\n")
local lint = release:match("\n  lint:\n(.-)\n  release:\n")
check(lint and lint:find("\n        run: lua5.1 tools/compat-guard.lua\n", 1, true), "CI's lint job runs the guard")

-- The command line CI runs: exit 1 on a planted tree on disk, 0 on the addon.
local sep = package.config:sub(1, 1)
local windows = sep == "\\"
local interp, argi = "luajit", -1
while arg and arg[argi] do interp, argi = arg[argi], argi - 1 end
local plantedRoot = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. sep .. "compat-guard-cli-" .. os.time()
os.execute((windows and 'mkdir "%s"' or 'mkdir -p "%s"'):format(plantedRoot .. sep .. "Core"))
local function put(rel, text)
  local fh = assert(io.open(plantedRoot .. sep .. rel, "wb"))
  fh:write(text)
  fh:close()
end
put("GuildOS.toc", "Core\\Bad.lua\n")
put("Core" .. sep .. "Bad.lua", "GetItemInfo(1)\n")
local function exitCode(a, _, c)
  if type(a) == "number" then return a end
  return c or (a and 0 or 1)
end
local function cli(root)
  local cmd = string.format('"%s" -e "ROOT=[[%s]]" "%s" >%s 2>&1', interp, root, ADDON .. "/tools/compat-guard.lua",
                            windows and "NUL" or "/dev/null")
  if windows then cmd = '"' .. cmd .. '"' end
  return exitCode(os.execute(cmd))
end
local plantedExit, cleanExit = cli(plantedRoot), cli(ADDON)
os.execute((windows and 'rmdir /s /q "%s"' or 'rm -rf "%s"'):format(plantedRoot))
check(plantedExit ~= 0 and cleanExit == 0,
      "the guard's command line exits non-zero on a planted violation and 0 on the addon (" .. plantedExit .. ", " .. cleanExit .. ")")

-- ── 9. The shims nobody called are wired in ─────────────────────────────
local function source(rel) return assert(io.open(ADDON .. "/" .. rel, "rb")):read("*a") end
check(source("Core/Core.lua"):find("Compat.RegisterAddonPrefix(self.PREFIX)", 1, true)
      and source("Core/Core.lua"):find("Compat.RegisterAddonPrefix(self.LEGACY_PREFIX)", 1, true)
      and source("Modules/LootMaster.lua"):find('Compat.RegisterAddonPrefix("BRutusLM")', 1, true),
      "RegisterAddonPrefix registers the sync prefix, the legacy BRutus prefix and the loot prefix")
check(select(2, source("Modules/CommSystem.lua"):gsub("Compat%.SendAddonMessage%(", "")) == 2
      and source("Modules/LootMaster.lua"):find("Compat.SendAddonMessageNow(", 1, true),
      "SendAddonMessage carries sync, and SendAddonMessageNow carries loot")
check(source("Core/Commands.lua"):find("Compat.IsQuestComplete(", 1, true), "IsQuestComplete answers /gos attunement checks")

print("compat-core: " .. checks .. " checks passed")
