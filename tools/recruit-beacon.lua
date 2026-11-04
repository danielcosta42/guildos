-- The full ad on the network (specs/071-o-recrutamento in guildos-web, Task B3), run against the real
-- Core, Compat, Utils, LibDeflate, CompanionExport, CompanionImport, GuildFinder, RecruitBeacon and
-- ChehulGossip, with the site's own strings: tools/recruit-fixture.txt (a GOSRECR1) and
-- tools/guild-ad-fixture.txt (a GOSGILD1 with a recruitAd), from tools/ in the web repo's encoders.
--
-- The rules: a CR3 lands as a normalized ad and its validity is cut to 72 hours ahead; a CR3 that is
-- expired, or a CR2 that is, deletes nothing; a version from the future is refused; the seal comes
-- from the person's own GOSRECR1 and from nothing a message says; text with a colour, a link, a line
-- break or a Han character reaches the screen inert, one line and cut by character; one sender cannot
-- fill the cache; the officer's own ad is the site's, and old clients still get a CR2.
--
--   luajit -e 'ADDON="."' tools/recruit-beacon.lua
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

local function slurp(path) return io.open(ADDON .. "/" .. path, "rb"):read("*a") end
local RECRUIT = slurp("tools/recruit-fixture.txt")
local GUILD_AD = slurp("tools/guild-ad-fixture.txt")

local HOUR, DAY = 3600, 86400
local NOW = 1793750400 + 20 * DAY
local GUILD, officer = nil, false
local sent = {}

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70245", "", 11500 end
WOW_PROJECT_ID = 99
function UnitFullName() return "Chehul", "Costa" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Normal" end
function GetNormalizedRealmName() return "Normal" end
function UnitName() return "Ana" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitFactionGroup() return "Horde" end
function GetLocale() return "enUS" end
function GetCurrentRegion() return 1 end
function GetServerTime() return NOW end
function GetTime() return 1 end
date, time = os.date, os.time
function IsInGuild() return GUILD ~= nil end
function GetGuildInfo() return GUILD, "Rank", 0 end
function GetNumGuildMembers() return 0 end
function IsInInstance() return false end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function strsplit(delim, s)
  local out, from = {}, 1
  while true do
    local at = s:find(delim, from, true)
    if not at then out[#out + 1] = s:sub(from); break end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + 1
  end
  return unpack(out)
end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) return registry[name] end })
GuildOSDB = {}

local handler
_G.ChehulMesh = {
  Register = function(_, _, fn) handler = fn end,
  Guild = function(_, _, payload) sent[#sent + 1] = { via = "GUILD", payload = payload } end,
  Group = function() end,
  Realm = function(_, _, payload) sent[#sent + 1] = { via = "YELL", payload = payload } end,
  Whisper = function() return true end,
}

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/GuildFinder.lua")
dofile(ADDON .. "/Modules/ChehulGossip.lua")
dofile(ADDON .. "/Modules/RecruitBeacon.lua")
function GuildOS:IsOfficer() return officer end

local GF, RB, Gossip, Import = GuildOS.GuildFinder, GuildOS.RecruitBeacon, GuildOS.ChehulGossip, GuildOS.CompanionImport
local errors = {}
GuildOS.RecordError = function(_, msg) errors[#errors + 1] = msg end

local function reset()
  GuildOS.db = { settings = { companion = true } }
  GuildOSInbox, GUILD, officer, sent = nil, nil, false, {}
  NOW = 1793750400 + 20 * DAY
  Import._recruit, Import._blockRaw = nil, nil
end

-- A CR3 as a client puts it on the wire: the contract's order, `|` between fields.
local function wire(o)
  o = o or {}
  local function f(v) return v == nil and "" or tostring(v) end
  return table.concat({
    "CR3", f(o.n or "Guild One"), f(o.f or "H"), f(o.w or "normal:us"), f(o.p or "Raids"), f(o.d or "2,4"), f(o.s or "1260"),
    f(o.e or "1440"), f(o.pc or "regular"), f(o.l or "pt+en"), f(o.fo or "RAID"), f(o.r or "TANK"), f(o.c or "PALADIN"),
    f(o.lo or "council"), f(o.t or "week2"), f(o.ct or "Ana+Bia"), f(o.u or ("s" .. (o.n or "Guild One"):gsub("[^%w]", "-") .. "-" .. #(o.n or "Guild One"))),
    f(o.v or NOW - HOUR), f(o.x or NOW + 10 * HOUR),
  }, "|") .. (o.extra and ("|" .. o.extra) or "")
end

-- Valid UTF-8, byte by byte: a half character anywhere fails.
local function utf8ok(s)
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local n = b < 0x80 and 1 or (b >= 0xC2 and b < 0xE0) and 2 or (b >= 0xE0 and b < 0xF0) and 3 or (b >= 0xF0 and b < 0xF5) and 4 or nil
    if not n or i + n - 1 > #s then return false end
    for k = 1, n - 1 do
      local c = s:byte(i + k)
      if c < 0x80 or c > 0xBF then return false end
    end
    i = i + n
  end
  return true
end

local function heard(name)
  for _, ad in ipairs(GF:All()) do
    if ad.n == name then return ad end
  end
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ── A CR3 lands ─────────────────────────────────────────────────────────
reset()
RB:Initialize()
check(RB.IngestCR3 and RB.Cache3 and RB.AdToPayload and Gossip.Topic, "the interface the rest relies on")
check(RB:IngestCR3(wire(), "Bob") == true, "a well-formed CR3 is taken")
local ad = heard("Guild One")
check(ad and ad.f == "H" and ad.w == "normal:us" and ad.p == "Raids", "and reaches the finder")
check(table.concat(ad.d, ",") == "2,4" and ad.s == 1260 and ad.e == 1440 and ad.pc == "regular", "nights and pace")
check(table.concat(ad.l, "+") == "pt+en" and table.concat(ad.r, "+") == "TANK" and table.concat(ad.c, "+") == "PALADIN", "lists split on '+'")
check(ad.lo == "council" and ad.t == "week2" and table.concat(ad.ct, "+") == "Ana+Bia" and ad.u == "sGuild-One-9", "loot, trial, contact, slug")
check(ad.heard == true and ad.verified == false, "heard, and with no GOSRECR1 never verified")
check(RB:IngestCR3("CR3|only|three", "Bob") == false and RB:IngestCR3(nil, "Bob") == false, "short and non-string payloads are refused")
check(RB:IngestCR3(wire({ n = "" }), "Bob") == false, "no name, no ad")
check(RB:IngestCR3(wire({ n = "Bad", v = "abc" }), "Bob") == false and RB:IngestCR3(wire({ n = "Bad2", x = "" }), "Bob") == false, "a version or a validity that is no number")

-- A newer version replaces, an older does not, the same version keeps the later validity.
RB:IngestCR3(wire({ p = "Newer", v = NOW - 60 }), "Bob")
check(heard("Guild One").p == "Newer", "a newer version wins")
RB:IngestCR3(wire({ p = "Older", v = NOW - 7200 }), "Bob")
check(heard("Guild One").p == "Newer", "an older one does not")
RB:IngestCR3(wire({ p = "Same", v = NOW - 60, x = NOW + 20 * HOUR }), "Bob")
check(heard("Guild One").p == "Newer" and heard("Guild One").x == NOW + 20 * HOUR, "the same version only renews the validity")

-- ── Validity, removal, the future ───────────────────────────────────────
reset()
RB:IngestCR3(wire({ n = "Far", x = NOW + 30 * DAY }), "Bob")
check(heard("Far").x == NOW + 72 * HOUR, "x is cut to 72 hours ahead, whatever came")
RB:IngestCR3(wire({ n = "Far2", x = 1e15 }), "Bob")
check(heard("Far2").x == NOW + 72 * HOUR, "even an absurd one")

RB:IngestCR3(wire({ n = "Keep", p = "alive" }), "Bob")
RB:IngestCR3(wire({ n = "Keep", p = "takedown", v = NOW - 10, x = NOW - 1 }), "Bob")
check(heard("Keep") and heard("Keep").p == "alive", "an expired CR3 deletes nothing, and changes nothing")
RB:IngestCR3(wire({ n = "Keep", p = "zero", v = NOW - 10, x = 0 }), "Bob")
check(heard("Keep") and heard("Keep").p == "alive", "nor does a zero")
RB:Ingest("CR2|Keep|H|||||||" .. (NOW - 5) .. "|" .. (NOW - 1) .. "|Bob", "Bob")
RB:Ingest("CR2|Keep|H|||||||" .. (NOW + 5) .. "|" .. (NOW - 1) .. "|Bob", "Bob")
check(heard("Keep") and heard("Keep").p == "alive", "a CR2 past its expiry never deletes a CR3")

check(RB:IngestCR3(wire({ n = "Future", v = NOW + 5 * DAY }), "Bob") == false and not heard("Future"), "a version ahead of now is refused")
check(RB:IngestCR3(wire({ n = "Skewed", v = NOW + 60 }), "Bob") == true, "with a little allowance for a clock that is off")
for i = 1, 4 do RB:IngestCR3(wire({ n = "Forged" .. i, v = NOW + 30 * DAY + i }), "Eve") end
check(not heard("Forged1") and not heard("Forged4"), "four forged versions take nothing")
local topic = GuildOS.State.gossip.topics.CR3
check(topic and topic.digest and topic.want and topic.pull and topic.push, "the CR3 topic is registered with the gossip")
for _, e in ipairs(topic.digest()) do check(e[2] <= NOW + 600, "no seat in the digest is held by a future version") end

-- Time passes: it leaves by expiring, here and nowhere else.
reset()
RB:IngestCR3(wire({ n = "Fades", x = NOW + HOUR }), "Bob")
check(heard("Fades"), "live now")
NOW = NOW + 2 * HOUR
check(not heard("Fades"), "gone when it expires")
RB:Prune()
check(count(RB:Cache3()) == 0, "and pruned from the cache")

-- The cache has a cap.
reset()
for i = 1, RB.CACHE_CAP + 10 do RB:IngestCR3(wire({ n = "G" .. i, x = NOW + i * 60 }), "Bob") end
check(count(RB:Cache3()) == RB.CACHE_CAP, "forty at most, the soonest to expire going first")
check(RB:Cache3()["G" .. (RB.CACHE_CAP + 10)] ~= nil and RB:Cache3().G1 == nil, "the soonest")

-- ── The seal ────────────────────────────────────────────────────────────
reset()
GuildOSInbox = { RECRUIT }
local list = Import:RecruitDirectory()
check(list and #list.ads == 3, "the site's list reads")
local ordem = list.ads[1]
check(heard("Ordem do Crepúsculo") and heard("Ordem do Crepúsculo").verified == true, "an ad of the person's own list is verified")
RB:IngestCR3(wire({ n = ordem.n, v = ordem.v, p = "Forged pitch", u = "evil", x = NOW + HOUR }), "Eve")
local sealed = heard(ordem.n)
check(sealed.verified == true and sealed.p == ordem.p, "heard with name and version in the list: sealed, and what shows is the list's own")
RB:IngestCR3(wire({ n = ordem.n, v = ordem.v + 1, p = "A later one", u = ordem.u }), "Eve")
check(heard(ordem.n).verified == false and heard(ordem.n).p == "A later one", "another version is only heard")
RB:IngestCR3(wire({ n = "Claims", extra = "1" }), "Eve")
RB:IngestCR3(wire({ n = "Claims2", extra = "verified" }), "Eve")
RB:IngestCR3(wire({ n = "Claims3", v = "1|1", extra = "true" }), "Eve")
check(heard("Claims") and heard("Claims").verified == false and heard("Claims2").verified == false, "no field of a message turns the seal on")
for _, c in pairs(RB:Cache3()) do check(c.verified == nil and c.heard == nil, "and nothing about it is stored") end
GuildOSInbox = nil
check(heard(ordem.n).verified == false, "with no list every card is only heard")
GuildOSInbox = { RECRUIT }
NOW = NOW + 4 * DAY
check(heard(ordem.n) == nil or heard(ordem.n).verified == false, "a list over three days old seals nothing")
reset()

-- The list goes on from the site's own string: the digest offers it, what it holds is not asked for, and
-- what comes out of a pull is a CR3 any client takes, with no seal on the other side.
GuildOSInbox = { RECRUIT }
local listTopic = GuildOS.State.gossip.topics.CR3
local inDigest = {}
for _, e in ipairs(listTopic.digest()) do inDigest[e[1]] = e[2] end
check(inDigest[ordem.n] == ordem.v, "the digest offers the list's ads at the list's version")
check(listTopic.want(ordem.n, ordem.v) == false and listTopic.want(ordem.n, ordem.v - 1) == false, "the list has it: not wanted")
check(listTopic.want(ordem.n, ordem.v + 1) == true, "a newer one is")
local passedOn = listTopic.pull(ordem.n)
check(passedOn and passedOn:find("^CR3|"), "the list's ad comes out as a CR3")
check(count(RB:Cache3()) == 0, "and nothing of the list is copied into the cache")
GuildOSInbox = nil
check(RB:IngestCR3(passedOn, "Bob", "WHISPER") == true, "a client with no list takes it")
check(heard(ordem.n).p == ordem.p and heard(ordem.n).verified == false and heard(ordem.n).heard == true, "heard in the game, with no seal")
reset()

-- ── Text off the network ────────────────────────────────────────────────
local han = string.rep("公会招募", 60)
local cases = {
  { n = "Cor", p = "|cffff0000Red|r text" },
  { n = "Link", p = "|Hitem:1:2|h[Sword]|h" },
  { n = "Linha", p = "one\ntwo\r\nthree" },
  { n = "Han", p = han },
  { n = "Han" .. string.rep("公", 40), p = "ok" },
  { n = "Cut", p = "abc\228\184" },
  { n = "Contact", ct = "|cff00ff00Eve|r+B\nob" },
}
for _, c in ipairs(cases) do RB:IngestCR3(wire(c), "Bob") end
for _, c in pairs(RB:Cache3()) do
  for k, v in pairs(c) do
    if type(v) == "string" then
      check(not v:find("|", 1, true) and not v:find("[%c]") and utf8ok(v), "field " .. k .. " of " .. tostring(c.n) .. " is inert, one line and whole")
    end
  end
  for _, v in ipairs(c.ct or {}) do check(not v:find("|", 1, true) and not v:find("%c"), "contacts are inert") end
end
local hanAd
for _, c in pairs(RB:Cache3()) do if c.n == "Han" then hanAd = c end end
check(hanAd and GuildOS:Utf8Len(hanAd.p) == 120 and #hanAd.p == 360, "a Han pitch is cut at 120 characters, by character")
for _, c in pairs(RB:Cache3()) do
  if c.n:find("^Han.") then check(GuildOS:Utf8Len(c.n) <= 24 and utf8ok(c.n), "so is a name, at 24") end
end
-- A bar in a field shifts the rest: the message is refused or is inert, never believed.
RB:IngestCR3(wire({ n = "Shift", p = "a|b|c|d" }), "Bob")
check(heard("Shift") == nil, "a bar inside a field breaks the message, which is then refused")

-- The same lines from the site's list: the dirty fixture.
GuildOSInbox = { RECRUIT }
local dirty, big
for _, a in ipairs(GF:All()) do
  if a.n == "Sujo" then dirty = a end
  if a.n == "公会" then big = a end
end
check(dirty and not dirty.p:find("|", 1, true) and not dirty.p:find("%c") and not dirty.ct[1]:find("|", 1, true), "the list's colours, links and breaks come out inert")
check(big and GuildOS:Utf8Len(big.p) == 120 and utf8ok(big.p), "and its Han pitch is cut by character")

-- ── One sender ──────────────────────────────────────────────────────────
reset()
Gossip:Initialize()
RB:Initialize()
check(handler, "RecruitBeacon registered its handler on the mesh")
for i = 1, Gossip.SENDER_MAX + 20 do handler(wire({ n = "Flood" .. i }), "Mallory", "WHISPER") end
local flooded = 0
for k in pairs(RB:Cache3()) do if k:find("^Flood") then flooded = flooded + 1 end end
check(flooded == Gossip.SENDER_MAX, "a sender over the limit is ignored: " .. flooded)
handler(wire({ n = "Fair" }), "Carol", "WHISPER")
check(RB:Cache3().Fair ~= nil, "and the next sender is heard")
handler("CR2|Old|H||||||" .. (NOW - 1) .. "|" .. (NOW + HOUR) .. "|Bob", "Dave", "YELL")
check(RB:Cache()["Old"] ~= nil, "a CR2 still reaches its own cache")

-- ── The guild's own ad ──────────────────────────────────────────────────
reset()
GUILD, officer = "Ashen Vow", true
GuildOSInbox = { GUILD_AD }
RB:Initialize()
local own = Import:OwnRecruitAd()
check(own and own.n == "Ashen Vow" and own.v == NOW - DAY, "the block's own ad")
local oneTopic = GuildOS.State.gossip.topics.CR3
local found
for _, e in ipairs(oneTopic.digest()) do if e[1] == "Ashen Vow" then found = e end end
check(found and found[2] == own.v, "the digest holds my own guild's ad")
check(oneTopic.pull("Ashen Vow"):find("^CR3|Ashen Vow|"), "and can hand it over")

local legacy = RB:GetAd()
legacy.enabled, legacy.note, legacy.days = true, "LEGACY NOTE", "Mon"
RB:Broadcast()
local cr3s, cr2s = {}, {}
for _, m in ipairs(sent) do
  if m.payload:find("^CR3|") then cr3s[#cr3s + 1] = m else cr2s[#cr2s + 1] = m end
end
check(#cr3s >= 1 and cr3s[1].via == "GUILD" and cr3s[1].payload:find("We raid Tuesdays", 1, true), "an officer with the site's ad spreads it as a CR3, by GUILD")
for _, m in ipairs(cr3s) do check(m.via == "GUILD", "a CR3 never goes to the public chat") end
check(not table.concat((function() local t = {} for _, m in ipairs(sent) do t[#t + 1] = m.payload end return t end)(), "\n"):find("LEGACY", 1, true),
  "and not the /gos beacon one, in either protocol")
check(#cr2s >= 1 and cr2s[1].payload:find("^CR2|Ashen Vow|H|"), "old clients still get a CR2, made of the site's ad")
check(cr2s[1].payload:find("We raid Tuesdays", 1, true), "with its pitch")
local mine = RB:Cache3()["Ashen Vow"]
check(mine and mine.v == own.v, "and it is in my own cache")
local again = RB:IngestCR3(oneTopic.pull("Ashen Vow"), "Bob")
check(again ~= nil, "a pulled ad is a CR3 any client takes")

-- A peer cannot hold the slot of this guild's own ad: not by the network, and not by a cache that already has it.
check(RB:IngestCR3(wire({ n = "Ashen Vow", p = "FORGED", v = NOW + 300 }), "Mallory") == false, "a CR3 named after my own guild is refused")
local slot = RB:Cache3()["Ashen Vow"]
local forgedCopy = {}
for k, v in pairs(slot) do forgedCopy[k] = v end
forgedCopy.p, forgedCopy.v = "FORGED", NOW + 300
RB:Cache3()["Ashen Vow"] = forgedCopy
sent = {}
RB:Broadcast()
local spread = {}
for _, m in ipairs(sent) do spread[#spread + 1] = m.payload end
check(#spread >= 2 and not table.concat(spread, " "):find("FORGED", 1, true), "a forged newer ad in the slot is not spread, as a CR3 or a CR2")
check(RB:Cache3()["Ashen Vow"].p ~= "FORGED", "the site's ad takes its slot back")
RB:Cache3()["Ashen Vow"] = forgedCopy
local offered
for _, e in ipairs(oneTopic.digest()) do if e[1] == "Ashen Vow" then offered = e end end
check(offered and offered[2] == own.v, "the digest offers the site's version, not the forged one")
check(not oneTopic.pull("Ashen Vow"):find("FORGED", 1, true), "and pull hands out the site's ad")

reset()
GUILD, officer = "Ashen Vow", true
GuildOSInbox = { GUILD_AD }
RB:GetAd().enabled, RB:GetAd().note = true, "LEGACY NOTE"
NOW = NOW + 3 * DAY
check(Import:OwnRecruitAd() == nil, "past its x there is no own ad")
RB:Broadcast()
check(#sent >= 1 and sent[1].payload:find("^CR2|Ashen Vow|") and sent[1].payload:find("LEGACY NOTE", 1, true), "and the /gos beacon one is what goes")
for _, m in ipairs(sent) do check(not m.payload:find("^CR3|"), "no CR3 from an ad that expired") end

print(("recruit-beacon: %d checks passed"):format(checks))
