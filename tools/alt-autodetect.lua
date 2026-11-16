-- The login prompt that links one's own characters (issue #353), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua and
-- Modules/AltAutoDetect.lua.
--
-- The prompt took the highest-level character as the only acceptable main, so a group an
-- officer had linked under a lower-level main (or two characters at the same level) was
-- offered again at every login; accepting it as an officer was refused by LinkAlt and still
-- printed "Linked", and a member's accept made a loop and was wiped by the next officer list.
--
--   luajit -e 'ADDON="."' tools/alt-autodetect.lua
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

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
local now = 1000000
function GetServerTime() return now end
local clock = 1
function GetTime() return clock end
local afters = {}
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }

local ROSTER = { { "Off", 1 }, { "Main", 5 }, { "Alt", 5 }, { "Third", 5 } }
local me = "Off"
function UnitName() return me end
function UnitLevel() return 70 end
function UnitClass() return "Warrior", "WARRIOR" end
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1] .. "-Realm", "Rank", r[2] end end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
end

local registry, store, n = {}, {}, 0
LibStub = setmetatable({ NewLibrary = function(_, k) registry[k] = registry[k] or {}; return registry[k] end,
  GetLibrary = function(_, k) return registry[k] end },
  { __call = function(_, k) registry[k] = registry[k] or {}; return registry[k] end })
LibStub("GuildOS-LibSerialize").Serialize = function(_, t) n = n + 1; store["s" .. n] = t; return "s" .. n end
LibStub("GuildOS-LibSerialize").Deserialize = function(_, s) if store[s] then return true, store[s] end return false end
LibStub("LibDeflate").DecodeForWoWAddonChannel = function(_, s) return s end
LibStub("LibDeflate").DecompressDeflate = function(_, s) return s end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/AltAutoDetect.lua")
local CS, AD = GuildOS.CommSystem, GuildOS.AltAutoDetect
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end

local K = function(name) return GuildOS:GetPlayerKey(name, "Realm") end
local MAIN, ALT, THIRD = K("Main"), K("Alt"), K("Third")
local guildSet = { [MAIN] = true, [ALT] = true, [THIRD] = true }

local function client(who)
  me = who
  GuildOS.db = { settings = { officerMaxRank = 1 } }
  GuildOSDB = {}
  sent, printed, AD._resentAt = {}, {}, nil
end
local function deliver(msg, sender, channel)
  CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, channel or "GUILD", sender)
end
local function sentOf(t)
  local out = {}
  for _, m in ipairs(sent) do if m.t == t then out[#out + 1] = m end end
  return out
end

-- ── 1. A group that already shares one main is not offered again ─────────
local acc = { [MAIN] = { level = 60 }, [ALT] = { level = 70 } }
check(AD:DetectOwnAlts(acc, guildSet, { [ALT] = MAIN }) == nil,
  "an alt that out-levelled its main: the group is linked, no prompt")
check(AD:DetectOwnAlts(acc, guildSet, { [MAIN] = ALT }) == nil, "and the other way round too")
local tie = { [MAIN] = { level = 70 }, [ALT] = { level = 70 } }
check(AD:DetectOwnAlts(tie, guildSet, { [MAIN] = ALT }) == nil and AD:DetectOwnAlts(tie, guildSet, { [ALT] = MAIN }) == nil,
  "two characters at the same level, linked either way: no prompt")
local r1, r2 = AD:DetectOwnAlts(tie, guildSet, {}), AD:DetectOwnAlts(tie, guildSet, {})
check(r1 and r2 and r1.main == r2.main and r1.main == ALT, "unlinked at the same level: the same suggestion every time")
local three = { [MAIN] = { level = 60 }, [ALT] = { level = 70 }, [THIRD] = { level = 65 } }
local r = AD:DetectOwnAlts(three, guildSet, { [ALT] = MAIN })
check(r and r.main == MAIN and #r.group == 3, "a new character joins the group under the main it already has")
r = AD:DetectOwnAlts(acc, guildSet, {})
check(r and r.main == ALT, "with no main yet, the highest level is suggested")

-- ── 2. An officer's accept links, and says so only when it did ───────────
client("Off")
GuildOS.db.altLinks = { [ALT] = MAIN }
check(AD:LinkOwnAlts(MAIN, { MAIN, ALT, THIRD }) == 1 and GuildOS.db.altLinks[THIRD] == MAIN
  and GuildOS.db.altLinks[ALT] == MAIN and GuildOS.db.altLinks[MAIN] == nil, "the officer adds the new character")
check(#sentOf("AL") == 1, "and publishes the list once")
client("Off")
GuildOS.db.altLinks = { [ALT] = MAIN, [THIRD] = MAIN }
check(AD:LinkOwnAlts(ALT, { MAIN, ALT, THIRD }) == 3, "making a current alt the main is applied, not refused")
check(GuildOS.db.altLinks[ALT] == nil and GuildOS.db.altLinks[MAIN] == ALT and GuildOS.db.altLinks[THIRD] == ALT,
  "every other character now points at the new main")
client("Off")
GuildOS.db.altLinks = { [ALT] = MAIN }
check(AD:LinkOwnAlts(MAIN, { MAIN, ALT }) == 0 and #sentOf("AL") == 0, "nothing to change: nothing sent")
AD:_RegisterPopup()
GuildOS.Dialogs.GUILDOS_ALT_AUTODETECT.OnAccept(nil, { main = MAIN, group = { MAIN, ALT } })
check(#printed == 0, "and no \"Linked\" line for a link that did not happen")

-- ── 3. A member's accept: no loop, and it survives an officer list ───────
client("Main")
GuildOS.db.altLinks = { [ALT] = MAIN }
AD:LinkOwnAlts(ALT, { MAIN, ALT })
check(GuildOS.db.altLinks[ALT] == nil and GuildOS.db.altLinks[MAIN] == ALT, "the member's view re-mains without a loop")
local claims = sentOf("SA")
check(#claims == 1, "the claim goes to the officers")
local claim = claims[1]
check(next(GuildOSDB.altPending) ~= nil, "and is kept until an officer's list carries it")

local oldList = "old"; store[oldList] = {}            -- an officer who never heard the claim
sent = {}
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(GuildOS.db.altLinks[MAIN] == ALT, "the officer's list does not wipe the member's link")
check(#sentOf("SA") == 1, "the claim is sent again, now that an officer is online")
sent = {}
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(#sentOf("SA") == 0, "once per session")
check(AD:DetectOwnAlts(acc, guildSet, GuildOS.db.altLinks) == nil, "so the prompt does not come back")

-- The officer applies it, and the list that comes back ends the claim.
local memberDb, memberAcc = GuildOS.db, GuildOSDB
client("Off")
GuildOS.db.altLinks = { [ALT] = MAIN }
deliver(claim, "Main-Realm")
check(GuildOS.db.altLinks[MAIN] == ALT and GuildOS.db.altLinks[ALT] == nil, "the officer applies the claim")
local newList = sentOf("AL")[#sentOf("AL")]
me, GuildOS.db, GuildOSDB = "Main", memberDb, memberAcc
deliver(newList, "Off-Realm")
check(next(GuildOSDB.altPending) == nil, "the officer's list carries it: the claim is done")

-- The member's own unlink or re-main after accepting replaces the claim still waiting (review of #353).
client("Main")
GuildOS.db.altLinks = {}
AD:LinkOwnAlts(ALT, { MAIN, ALT })
AD:UnlinkOwnAlt(MAIN)
check(next(GuildOSDB.altPending) == nil, "an unlink drops the waiting claim about those characters")
sent = {}
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(GuildOS.db.altLinks[MAIN] == nil and #sentOf("SA") == 0, "so the officer's list does not bring the link back")
client("Main")
GuildOS.db.altLinks = {}
AD:LinkOwnAlts(ALT, { MAIN, ALT })
AD:SetOwnMain(MAIN)
local only = 0
for _, p in pairs(GuildOSDB.altPending) do only = only + 1; check(p.main == MAIN and p.alts[1] == ALT, "the re-main is what waits now") end
check(only == 1, "a re-main replaces the waiting claim with itself")
sent = {}
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(GuildOS.db.altLinks[ALT] == MAIN and #sentOf("SA") == 1, "and it survives an officer list that never heard it")

-- Unlinking one character of a waiting group keeps the rest of the claim.
client("Main")
GuildOS.db.altLinks = {}
AD:LinkOwnAlts(MAIN, { MAIN, ALT, THIRD })
AD:UnlinkOwnAlt(THIRD)
local p1 = select(2, next(GuildOSDB.altPending))
check(p1 and p1.main == MAIN and #p1.alts == 1 and p1.alts[1] == ALT, "unlinking Third leaves Alt -> Main waiting")
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(GuildOS.db.altLinks[ALT] == MAIN and GuildOS.db.altLinks[THIRD] == nil, "an officer list keeps Alt and not Third")

-- The claim sent at login, with nobody online, is not taken as heard (review of #353).
client("Main")
GuildOS.db.altLinks = {}
AD:LinkOwnAlts(ALT, { MAIN, ALT })
AD._resentAt = nil                                 -- a new session
AD:ResendPending()
clock = clock + 600
sent = {}
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(next(GuildOSDB.altPending) ~= nil and GuildOS.db.altLinks[MAIN] == ALT and #sentOf("SA") == 1,
  "the first officer list ten minutes on gets the claim again, not a drop")

-- Re-sent this session and still missing from an officer's list a while later: the officers undid it.
client("Main")
GuildOS.db.altLinks = {}
AD:LinkOwnAlts(ALT, { MAIN, ALT })
AD:ResendPending()
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(next(GuildOSDB.altPending) ~= nil, "a list right after the claim went out may predate it: kept")
clock = clock + 60
deliver({ t = "AL", data = oldList }, "Off-Realm")
check(next(GuildOSDB.altPending) == nil and GuildOS.db.altLinks[MAIN] == nil,
  "a minute on, the officers' list stands and the claim is dropped")

-- A claim from another guild, or a month old, is left alone.
client("Main")
GuildOS.db.altLinks = {}
AD:LinkOwnAlts(ALT, { MAIN, ALT })
for _, p in pairs(GuildOSDB.altPending) do p.guild = "Other" end
sent = {}
AD:ResendPending()
check(#sentOf("SA") == 0, "a claim made in another guild is not sent here")
for _, p in pairs(GuildOSDB.altPending) do p.guild = "Guild"; p.ts = now - 31 * 86400 end
AD:ResendPending()
check(#sentOf("SA") == 0 and next(GuildOSDB.altPending) == nil, "a claim past thirty days is dropped")

print(("alt-autodetect: %d checks passed"):format(checks))
