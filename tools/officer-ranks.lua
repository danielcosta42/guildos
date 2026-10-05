-- The guild's officer threshold, and the channel for the officer messages left (issue #81),
-- run against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua
-- and Modules/SyncService.lua.
--
-- officerMaxRank was each account's own setting: an officer who ticked an "Officer Alt" rank
-- made that alt an officer on their account only, and since #78 every officer message from
-- the alt was dropped everywhere else. An officer's change is now stamped and published, and
-- every client keeps the newest one an officer sent over GUILD. RX, AL, RR and the officer
-- SyncService domains also ask for GUILD now, as the seven types of #78 do.
--
--   luajit -e 'ADDON="."' tools/officer-ranks.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
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
function GetTime() return 1 end
local afters, tickers = {}, {}
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end,
            NewTicker = function(every, fn) tickers[every] = fn; return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}

-- The guild. Who "I" am changes between the officer who sends and the member who receives.
local ROSTER = { { "Off", 1 }, { "Alt", 2 }, { "Mem", 5 }, { "Off2", 1 } }
local me = "Off"
function UnitName() return me end
function IsInGuild() return true end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2] end end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
end

-- The wire: serialized tables are kept by key, and the encoding hands strings back as is.
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
dofile(ADDON .. "/Modules/SyncService.lua")
local CS, SS = BRutus.CommSystem, BRutus.SyncService
CS.pendingMessages = CS.pendingMessages or {}
local sent = {}
CS.SendMessage = function(_, msgType, data, target) sent[#sent + 1] = { t = msgType, data = data, target = target } end

local function client(who)
  me = who
  BRutus.db = { settings = { officerMaxRank = 1 } }
  SS:Initialize()
  sent = {}
end
local function deliver(msg, sender, channel)
  CS:OnMessageReceived("S:" .. msg.t .. ":" .. msg.data, channel or "GUILD", sender)
end

-- ── 1. An officer's change goes out, stamped ────────────────────────────
client("Off")
check(BRutus:IsOfficer() and not BRutus:IsOfficerByName("Alt"), "by default rank 1 is an officer and rank 2 is not")
BRutus:SetOfficerMaxRank(2)
check(BRutus.db.settings.officerMaxRank == 2 and BRutus.db.settings.officerMaxRankAt == now,
  "the officer's own client takes it at once, stamped")
check(#sent == 1 and sent[1].t == "SV" and sent[1].target == nil, "and publishes it to the guild")
local change = sent[1]

-- ── 2. A member's client takes it, from an officer over GUILD ────────────
client("Mem")
check(not BRutus:IsOfficerByName("Alt"), "before the change arrives, the alt is not an officer here")
deliver(change, "Off")
check(BRutus.db.settings.officerMaxRank == 2 and BRutus:IsOfficerByName("Alt"),
  "after it, the alt is an officer here too: one threshold for the guild")

-- ── 3. Only from an officer, only over GUILD, only newer ─────────────────
client("Mem")
deliver(change, "Off", "WHISPER")
check(BRutus.db.settings.officerMaxRank == 1, "the change over a whisper is ignored")
deliver(change, "Mem")
check(BRutus.db.settings.officerMaxRank == 1, "the change from a member is ignored")
deliver(change, "Off-OtherRealm", "WHISPER")
check(BRutus.db.settings.officerMaxRank == 1, "a namesake from another realm cannot whisper it in")

client("Off")
now = now + 100
BRutus:SetOfficerMaxRank(3)
local newer = sent[1]
client("Mem")
deliver(newer, "Off")
deliver(change, "Off")
check(BRutus.db.settings.officerMaxRank == 3, "an older change arriving late does not undo a newer one")

client("Off")
SS:Publish("guildcfg", "officers", { max = 1 }, { rev = now + 999999 })   -- a stamp far in the future
local future = sent[1]
client("Mem")
deliver(future, "Off")
check(BRutus.db.settings.officerMaxRankAt == now + 300, "a stamp from the future is held to five minutes ahead")
local memberDb = BRutus.db
now = now + 400
client("Off")
BRutus:SetOfficerMaxRank(2)
local later = sent[1]
me, BRutus.db = "Mem", memberDb                     -- the same member, six minutes on
deliver(later, "Off")
check(BRutus.db.settings.officerMaxRank == 2, "so a real change made after that still wins")

-- ── 4. What a change may say ────────────────────────────────────────────
for _, bad in ipairs({ -1, 1.5, 10, "2" }) do
  client("Off")
  SS:Publish("guildcfg", "officers", { max = bad }, { rev = now })
  local msg = sent[1]
  client("Mem")
  deliver(msg, "Off")
  check(BRutus.db.settings.officerMaxRank == 1, "a threshold of " .. tostring(bad) .. " is not taken")
end

-- ── 5. Who re-sends it: officers only, and only a change somebody made ───
client("Mem")
BRutus.db.settings.officerMaxRankAt = now
BRutus:PublishOfficerMaxRank()
check(#sent == 0, "a member's client does not re-send it")
client("Off")
BRutus:PublishOfficerMaxRank()
check(#sent == 0, "an officer with no change ever made sends nothing")
BRutus.db.settings.officerMaxRankAt = now
BRutus:PublishOfficerMaxRank()
check(#sent == 1, "an officer with one re-sends it")
local function guildcfgSent()
  for _, m in ipairs(sent) do
    if m.t == "SV" and store[m.data] and store[m.data].dom == "guildcfg" then return true end
  end
  return false
end
local function runAfters()                              -- timers that schedule timers, until none is left
  for _ = 1, 5 do
    local due = afters
    afters = {}
    for _, fn in ipairs(due) do fn() end
  end
end
CS.BroadcastMyData = function() end
CS:Initialize()
sent, afters = {}, {}
tickers[300]()                                        -- the 5-minute sync firing
runAfters()
check(guildcfgSent(), "the 5-minute sync re-sends it")
sent, afters = {}, {}
CS:HandleRequest("Mem", "")
runAfters()
check(guildcfgSent(), "and so does an officer's answer to a request")

-- ── 6. RX, AL, RR and the officer SyncService domains ask for GUILD ─────
client("Mem")
local got = {}
BRutus.RaidTracker = { HandleDeleteIncoming = function() got.RX = (got.RX or 0) + 1 end }
BRutus.RaiderRoster = { HandleIncoming = function() got.RR = (got.RR or 0) + 1 end }
local links = "links"
store[links] = { Alt = "Off" }
for _, ch in ipairs({ "WHISPER", "INSTANCE_CHAT" }) do
  deliver({ t = "RX", data = "x" }, "Off", ch)
  deliver({ t = "RR", data = "x" }, "Off", ch)
  deliver({ t = "AL", data = links }, "Off", ch)
end
check(got.RX == nil and got.RR == nil and BRutus.db.altLinks == nil, "RX, RR and AL from an officer outside GUILD are dropped")
deliver({ t = "RX", data = "x" }, "Off")
deliver({ t = "RR", data = "x" }, "Off")
deliver({ t = "AL", data = links }, "Off")
check(got.RX == 1 and got.RR == 1 and BRutus.db.altLinks and BRutus.db.altLinks.Alt == "Off",
  "and handled from an officer over GUILD")

local applied = 0
SS:On("bulletin", function() applied = applied + 1 end)
local env = "env"
store[env] = { v = 2, id = "abc", dom = "bulletin", act = "snapshot", data = {} }
deliver({ t = "SV", data = env }, "Off", "WHISPER")
store[env] = { v = 2, id = "abd", dom = "bulletin", act = "snapshot", data = {} }
deliver({ t = "SV", data = env }, "Off", "INSTANCE_CHAT")
check(applied == 0, "an officer SyncService write over a whisper or a battleground is dropped")
store[env] = { v = 2, id = "abe", dom = "bulletin", act = "snapshot", data = {} }
deliver({ t = "SV", data = env }, "Off")
check(applied == 1, "and applied over GUILD")
store[env] = { v = 2, id = "def", dom = "event", act = "rsvp", data = {} }
local rsvps = 0
SS:On("event", function() rsvps = rsvps + 1 end)
deliver({ t = "SV", data = env }, "Alt")      -- another member (my own lines are skipped)
check(rsvps == 1, "a member-level action inside an officer domain is not held to the officer's rule")

-- The two domains whose handlers check the officer themselves: GUILD too.
for _, dom in ipairs({ "alliance", "core.roster" }) do
  local hits = 0
  SS:On(dom, function() hits = hits + 1 end)
  store[env] = { v = 2, id = dom .. "1", dom = dom, act = "snap", data = {} }
  deliver({ t = "SV", data = env }, "Off-OtherRealm", "WHISPER")
  check(hits == 0, dom .. " over a whisper, even from an officer's name, is dropped")
  store[env] = { v = 2, id = dom .. "2", dom = dom, act = "snap", data = {} }
  deliver({ t = "SV", data = env }, "Off")
  check(hits == 1, dom .. " over GUILD still reaches its handler")
end

-- ── 7. Changes that land in the same second, or behind a clock ──────────
-- Two officers in one second: every member settles on the lower threshold, whatever the order.
client("Off"); BRutus:SetOfficerMaxRank(3); local a = sent[1]
client("Off2"); BRutus:SetOfficerMaxRank(2); local b = sent[1]
client("Mem"); deliver(a, "Off"); deliver(b, "Off2")
local first = BRutus.db.settings.officerMaxRank
client("Mem"); deliver(b, "Off2"); deliver(a, "Off")
check(first == 2 and BRutus.db.settings.officerMaxRank == 2, "two changes in the same second settle the same everywhere")

-- The same officer clicking twice in one second: the second click is the newer one.
client("Off")
BRutus:SetOfficerMaxRank(2); local click1 = sent[1]
BRutus:SetOfficerMaxRank(3); local click2 = sent[2]
check(store[click2.data].rev > store[click1.data].rev, "the second click is stamped after the first")
client("Mem"); deliver(click1, "Off"); deliver(click2, "Off")
check(BRutus.db.settings.officerMaxRank == 3, "and the guild ends where the officer did")

-- An officer whose clock is behind the change it holds still moves the guild forward.
client("Off2"); BRutus:SetOfficerMaxRank(2); local held = sent[1]
client("Off"); deliver(held, "Off2")
local offDb = BRutus.db
now = now - 1
sent = {}
BRutus:SetOfficerMaxRank(4)
local behind = sent[1]
check(offDb.settings.officerMaxRankAt > store[held.data].rev, "a change made on a clock a second behind is still stamped later")
client("Mem"); deliver(held, "Off2"); deliver(behind, "Off")
check(BRutus.db.settings.officerMaxRank == 4, "so the rest of the guild takes it")
now = now + 1

-- ── 8. Who may change it, and a change that demotes its maker ───────────
client("Mem")
BRutus:SetOfficerMaxRank(4)
check(#sent == 0 and BRutus.db.settings.officerMaxRank == 1 and BRutus.db.settings.officerMaxRankAt == nil,
  "a member's client changes nothing and sends nothing")
client("Off")
BRutus:SetOfficerMaxRank(0)
check(#sent == 1 and not BRutus:IsOfficer(), "an officer unticking their own rank still sends the change")
local demotion = sent[1]
client("Mem"); deliver(demotion, "Off")
check(BRutus.db.settings.officerMaxRank == 0, "and the guild takes it, judging the sender by the old threshold")

-- ── 9. Stamps that are not a time ────────────────────────────────────────
for _, bad in ipairs({ 0 / 0, -math.huge, math.huge, 0, -5 }) do
  client("Off")
  SS:Publish("guildcfg", "officers", { max = 3 }, { rev = bad })
  local msg = sent[1]
  client("Mem")
  deliver(msg, "Off")
  check(BRutus.db.settings.officerMaxRank == 1 and BRutus.db.settings.officerMaxRankAt == nil,
    "a stamp of " .. tostring(bad) .. " is not taken")
end

print(("officer-ranks: %d checks passed"):format(checks))
