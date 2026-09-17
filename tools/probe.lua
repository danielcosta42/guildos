-- /guildos probe (issue #9), run against the real Core/Core.lua,
-- Core/Compat.lua and Core/Probe.lua under stubbed clients.
--
-- The probe exists for a client nobody has seen yet, so the one thing it
-- must never do is raise. This proves every entry is recorded present or
-- missing exactly as the client has it, including on a client that lacks the
-- probe's own APIs; that a raising API is recorded rather than propagated;
-- that nothing stays registered; that combat and "not in a guild" are
-- handled; that no member note is ever stored; that the summary says what the
-- record holds; and that the event list keeps up with the addon's source.
--
--   luajit -e 'ADDON="."' tools/probe.lua
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

-- ── The client the files need while they load ───────────────────────────
-- `strict` stays off while the files load, then events and templates the
-- stubbed client lacks raise the way the real ones do.
local printed, frames, calls, strict = {}, {}, {}, false
local KNOWN_EVENTS, KNOWN_TEMPLATES = {}, {}
function CreateFrame(_, _, _, template)
  if strict and template and not KNOWN_TEMPLATES[template] then
    error('Couldn\'t find inherited node "' .. template .. '"')
  end
  local f = { registered = {}, template = template }
  function f:RegisterEvent(e)
    if strict and not KNOWN_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end
    self.registered[e] = true
  end
  function f:UnregisterEvent(e)
    if strict and not KNOWN_EVENTS[e] then error('Attempt to unregister unknown event "' .. e .. '"') end
    self.registered[e] = nil
  end
  function f:SetScript() end
  function f:Hide() self.hidden = true end
  frames[#frames + 1] = f
  return f
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
local now = 1757800000
function GetServerTime() return now end
time = function() return 1111 end  -- the fallback clock, used only once GetServerTime is gone
local inGuild, inCombat = false, false
function IsInGuild() return inGuild end
function InCombatLockdown() return inCombat end
function hooksecurefunc() end
function debugstack() return "" end
function GetBuildInfo() return "1.60.0", "64210", "Sep 1 2026", 16000 end
WOW_PROJECT_ID = 2
C_Timer = { After = function() end }

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "0.53.0" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Probe.lua")
local Probe = BRutus.Probe

local function said(text)
  for _, line in ipairs(printed) do
    if tostring(line):find(text, 1, true) then return true end
  end
  return false
end

-- ── 1. The lists themselves ─────────────────────────────────────────────
local seen = {}
for _, name in ipairs(Probe.APIS) do
  check(not seen[name], "the inventory lists " .. name .. " once")
  seen[name] = true
end
check(#Probe.EVENTS == 39, "the probe checks the 39 events the addon registers")

-- Drift: the events the addon's own files register are exactly Probe.EVENTS.
-- Static reading: an event name held in a variable is out of its reach.
local EVENT_CALL = "RegisterEvent%(%s*[%w_%.%[%]]*%s*,?%s*[\"']([%u%d_]+)[\"']"
local function eventsIn(src)
  local out = {}
  for e in src:gmatch(EVENT_CALL) do out[#out + 1] = e end
  return out
end
check(#eventsIn('f:RegisterEvent("A_B")') == 1 and #eventsIn("BRutus.Compat.RegisterEvent(frames[1], 'X_Y')") == 1
  and #eventsIn('self:RegisterEvent(\n  "Z9")') == 1 and #eventsIn("pcall(frame.RegisterEvent, frame, event)") == 0,
  "the drift scan reads both quote styles, indexed frames and calls split over lines")
local registered, scanned = {}, 0
local toc = assert(io.open(ADDON .. "/GuildOS.toc", "r"))
for line in toc:lines() do
  local path = line:match("^%s*([%w_\\]+%.lua)%s*$")
  if path and not path:find("^Libs\\") then
    local f = io.open(ADDON .. "/" .. path:gsub("\\", "/"), "r")
    if f then
      scanned = scanned + 1
      for _, e in ipairs(eventsIn(f:read("*a"))) do registered[e] = true end
      f:close()
    end
  end
end
toc:close()
check(scanned > 80, "the drift scan read the addon's own files (" .. scanned .. ")")
local listed = {}
for _, e in ipairs(Probe.EVENTS) do listed[e] = true end
for e in pairs(registered) do check(listed[e], "the probe checks " .. e .. ", which the addon registers") end
for e in pairs(listed) do check(registered[e], e .. " is still registered somewhere in the addon") end

-- ── 2. A client missing about half of everything ────────────────────────
-- What the probe's own path needs stays; of the rest, odd entries exist and even ones do not.
local KEEP = {
  CreateFrame = true, GetServerTime = true, IsInGuild = true, InCombatLockdown = true, hooksecurefunc = true,
  DEFAULT_CHAT_FRAME = true, GameTooltip = true, GetGuildRosterInfo = true, IsInInstance = true,
  GetBuildInfo = true, debugstack = true,
  ["C_ChatInfo.RegisterAddonMessagePrefix"] = true, ["C_ChatInfo.SendAddonMessage"] = true, ["C_Timer.After"] = true,
}
local function setPath(name, value)
  local parts = {}
  for part in name:gmatch("[^%.]+") do parts[#parts + 1] = part end
  local t = _G
  for i = 1, #parts - 1 do
    if type(t[parts[i]]) ~= "table" then
      if value == nil then return end
      t[parts[i]] = {}
    end
    t = t[parts[i]]
  end
  if value == nil or t[parts[#parts]] == nil then t[parts[#parts]] = value end
end
for i, name in ipairs(Probe.APIS) do
  if not KEEP[name] then setPath(name, (i % 2 == 1) and {} or nil) end
end
for i, t in ipairs(Probe.TEMPLATES) do KNOWN_TEMPLATES[t[1]] = (i % 2 == 1) end
for i, e in ipairs(Probe.EVENTS) do KNOWN_EVENTS[e] = (i % 2 == 1) end

-- The stubs the checks below read. Every call that matters lands in one ordered log.
local NOTES = { "a public note", "an officer note" }
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.RegisterAddonMessagePrefix = function(p) calls[#calls + 1] = "register:" .. p end
C_ChatInfo.SendAddonMessage = function(p, text, channel)
  calls[#calls + 1] = "send:" .. p .. ":" .. text .. ":" .. channel
  return 0
end
C_ChatInfo.InChatMessagingLockdown = function() error("lockdown exploded", 0) end
function IsInInstance() return true, "raid" end
function GetGuildRosterInfo(i)
  if i == 1 then return "Ana-Firemaw", "Raider", 4, 70, "Priest", "Shattrath", NOTES[1], NOTES[2] end
end
-- Two different answers, so each field is proven to come from its own function.
function GetNormalizedRealmName() return "LivingFlame" end
function GetRealmName() return "Living Flame" end
GameTooltip = { HasScript = function(_, s) return s == "OnTooltipSetItem" or s == "OnTooltipCleared" end }
C_GameRules = { GetActiveGameMode = function() return 4 end }
issecretvalue, C_RestrictedActions = function() return false end, nil
C_Secrets = { HasSecretRestrictions = function() return true end }
C_XMLUtil = nil  -- the first runs have to build template frames to find out
C_FriendList = nil  -- a whole namespace gone
C_Map = setmetatable({}, { __index = function() error("C_Map lookup exploded") end })

local function resolve(name)
  local value = _G
  for part in name:gmatch("[^%.]+") do
    if type(value) ~= "table" then return nil end
    local ok, v = pcall(function() return value[part] end)
    if not ok then return nil end
    value = v
  end
  return value
end

-- ── 3. In combat: refuse, write nothing ─────────────────────────────────
strict = true
GuildOSDB = { probe = { at = 1 } }
local before = GuildOSDB.probe
inCombat = true
check(Probe:Run() == nil and GuildOSDB.probe == before, "in combat the probe refuses and leaves the last result")
check(said("does not run in combat"), "in combat it says why")
inCombat = false

-- ── 4. Not in a guild ───────────────────────────────────────────────────
local frameCount = #frames
printed = {}
local ok, r = pcall(Probe.Run, Probe)
check(ok and type(r) == "table", "the probe never raises on a client missing half the inventory (" .. tostring(r) .. ")")
check(GuildOSDB.probe == r and r.at == now, "the result lands in GuildOSDB.probe with a timestamp")
check(r.roster == "not in guild" and r.guildMessage == "not in guild" and #calls == 0,
  "not in a guild: roster and GUILD message say so, and nothing is registered or sent")

local missing = 0
for _, name in ipairs(Probe.APIS) do
  local expected = resolve(name) ~= nil
  check(r.apis[name] == expected, name .. " is recorded " .. (expected and "present" or "missing"))
  if not expected then missing = missing + 1 end
end
check(r.apis["C_FriendList.SendWho"] == false and r.apis["C_FriendList.GetWhoInfo"] == false,
  "a namespace that is gone makes each of its functions missing")
check(r.apis["C_Map.GetMapInfo"] == false, "a lookup that raises is recorded missing, not raised")
check(missing > #Probe.APIS * 0.3 and missing < #Probe.APIS * 0.7, "the stubbed client really misses about half the inventory")
local missingTemplates, templateFrames = 0, 0
for _, t in ipairs(Probe.TEMPLATES) do
  check(r.apis[t[1]] == KNOWN_TEMPLATES[t[1]], "template " .. t[1] .. " is recorded as the client has it")
  if not KNOWN_TEMPLATES[t[1]] then missingTemplates = missingTemplates + 1 end
end
for i = frameCount + 1, #frames do
  local f = frames[i]
  check(next(f.registered) == nil, "the probe leaves nothing registered on frame " .. i)
  if f.template then
    templateFrames = templateFrames + 1
    check(f.hidden, "the " .. f.template .. " frame the probe had to build is hidden")
  end
end
check(templateFrames == #Probe.TEMPLATES - missingTemplates, "without C_XMLUtil, one frame per template the client has")
check(r.apis["GameTooltip:OnTooltipSetItem"] == true and r.apis["GameTooltip:OnTooltipSetUnit"] == false,
  "tooltip scripts are recorded as the tooltip reports them")
for _, e in ipairs(Probe.EVENTS) do
  check(r.events[e] == KNOWN_EVENTS[e], e .. " is recorded " .. (KNOWN_EVENTS[e] and "present" or "missing"))
end
check(#r.missingApis == missing + missingTemplates + 2,  -- 2: OnTooltipSetSpell and OnTooltipSetUnit
  "the missing list holds every missing API, template and tooltip script")

check(r.build[1] == "1.60.0" and r.build[2] == "64210" and r.build[3] == "Sep 1 2026" and r.build[4] == 16000,
  "every build field is recorded")
check(r.projectId == 2 and r.client == BRutus.Client, "the project id and the client are recorded")
check(r.gameMode[1] == 4, "the game mode is recorded when C_GameRules exists")
check(r.secrets.issecretvalue == true and r.secrets.C_Secrets == true and r.secrets.C_RestrictedActions == false,
  "each Secret Values API is recorded present or missing")
check(r.secrets.restricted == true, "whether Secret Values are enforced comes from C_Secrets.HasSecretRestrictions")
check(r.chat.lockdown.error == "lockdown exploded" and r.chat.instance[2] == "raid",
  "a raising lockdown call is recorded with its error, next to the instance type")

-- The missing lists, in order, built from the stubbed client rather than read back from the record.
local expectedApis, expectedEvents = {}, {}
for _, name in ipairs(Probe.APIS) do
  if resolve(name) == nil then expectedApis[#expectedApis + 1] = name end
end
for _, t in ipairs(Probe.TEMPLATES) do
  if not KNOWN_TEMPLATES[t[1]] then expectedApis[#expectedApis + 1] = t[1] end
end
expectedApis[#expectedApis + 1] = "GameTooltip:OnTooltipSetSpell"
expectedApis[#expectedApis + 1] = "GameTooltip:OnTooltipSetUnit"
for _, e in ipairs(Probe.EVENTS) do
  if not KNOWN_EVENTS[e] then expectedEvents[#expectedEvents + 1] = e end
end
local function sameList(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end
check(sameList(r.missingApis, expectedApis), "the missing APIs are exactly the missing ones, in inventory order")
check(sameList(r.missingEvents, expectedEvents), "the missing events are exactly the missing ones, in order")

-- The summary says exactly what the record holds.
local function list(t)
  local shown = {}
  for i = 1, math.min(#t, 10) do shown[i] = t[i] end
  return table.concat(shown, ", ") .. (#t > 10 and ", ..." or "")
end
check(said(("Probe: build %s (%s), interface %s, project %s."):format("1.60.0", "64210", "16000", "2")),
  "the summary's first line: build, build number, interface and project")
check(said(("TBC Anniversary: %s. Secret Values restricted: %s. Chat lockdown here: %s (%s)."):format(
  "no", "yes", "error: lockdown exploded", "raid")), "the summary's second line: Anniversary, Secret Values, lockdown, instance")
check(said(("Missing: %d of %d APIs, %d of %d events."):format(#expectedApis,
  #Probe.APIS + #Probe.TEMPLATES + #Probe.SCRIPTS, #expectedEvents, #Probe.EVENTS)), "the summary carries the missing counts")
check(#expectedApis > 10 and said(list(expectedApis)), "the summary names the first ten missing APIs")
check(#expectedEvents > 10 and said(list(expectedEvents)), "the summary names the first ten missing events")
check(said("Saved in GuildOSDB.probe. Type /reload to write it to disk."), "the summary says where the result went")

-- ── 5. In a guild, run again ────────────────────────────────────────────
inGuild, now, calls = true, now + 60, {}
local first = r
r = Probe:Run()
check(GuildOSDB.probe == r and r ~= first and r.at == now, "a new run overwrites the last one with a new timestamp")
check(r.roster.firstName == "Ana-Firemaw" and r.roster.realm == "LivingFlame" and r.roster.realmName == "Living Flame",
  "the first roster name, GetNormalizedRealmName() and GetRealmName() are each recorded from their own function")
local registerAt, sendAt, sends = nil, nil, 0
for i, c in ipairs(calls) do
  if c == "register:GuildOSProbe" and not registerAt then registerAt = i end
  if c == "send:GuildOSProbe:probe:GUILD" then sendAt, sends = sendAt or i, sends + 1 end
end
check(sends == 1 and r.guildMessage[1] == 0, "one message goes to GUILD on the probe prefix, and its result is recorded")
check(registerAt and sendAt and registerAt < sendAt, "the probe prefix is registered before the message is sent")

local function contains(x, needle)
  return type(x) == "string" and x:find(needle, 1, true) ~= nil
end
local function holds(t, needle, visited)
  visited = visited or {}
  if visited[t] then return false end
  visited[t] = true
  for k, v in pairs(t) do
    if contains(v, needle) or contains(k, needle) then return true end
    if type(v) == "table" and holds(v, needle, visited) then return true end
  end
  return false
end
for _, note in ipairs(NOTES) do
  check(not holds(GuildOSDB, note), "no member note is stored anywhere (" .. note .. ")")
end

-- ── 6. Secret Values absent, and a client that can name its templates ───
issecretvalue, C_Secrets, C_RestrictedActions = function() return false end, nil, {}
local asked = 0
C_XMLUtil = { GetTemplateInfo = function(name)
  asked = asked + 1
  if KNOWN_TEMPLATES[name] then return { type = "Frame" } end
end }
frameCount = #frames
r = Probe:Run()
check(r.secrets.issecretvalue == true and r.secrets.C_Secrets == false and r.secrets.C_RestrictedActions == true
  and r.secrets.restricted == "missing", "each Secret Values API is read on its own; without C_Secrets, enforcement reads missing")
for _, t in ipairs(Probe.TEMPLATES) do
  check(r.apis[t[1]] == KNOWN_TEMPLATES[t[1]], "C_XMLUtil answers for template " .. t[1])
end
check(asked == #Probe.TEMPLATES and #frames - frameCount == 1,
  "with C_XMLUtil no template frame is built, only the throwaway event frame")
C_XMLUtil = { GetTemplateInfo = function() error("template lookup exploded") end }
r = Probe:Run()
check(r.apis.BackdropTemplate == false, "a raising template lookup reads missing, not raised")

-- ── 6b. The way Anniversary really answers: the API is there, restrictions are off ──
issecretvalue, C_Secrets, C_RestrictedActions = nil, { HasSecretRestrictions = function() return false end }, {}
C_ChatInfo.InChatMessagingLockdown = function() return false end
local realClient = BRutus.Client
BRutus.Client = { isAnniversary = true }
printed = {}
r = Probe:Run()
BRutus.Client = realClient
check(r.secrets.issecretvalue == false and r.secrets.C_Secrets == true and r.secrets.C_RestrictedActions == true
  and r.secrets.restricted == false, "C_Secrets present with restrictions off records false, not the API's presence")
check(said(("TBC Anniversary: %s. Secret Values restricted: %s. Chat lockdown here: %s (%s)."):format(
  "yes", "no", "no", "raid")), "on an Anniversary-like client the summary reads Anniversary yes, restricted no, lockdown no")

-- ── 7. A client without the probe's own APIs ────────────────────────────
GetServerTime, C_GameRules, C_ChatInfo, GameTooltip, IsInInstance, GetNormalizedRealmName, GetRealmName, C_XMLUtil =
  nil, nil, nil, nil, nil, nil, nil, nil
issecretvalue = function() return false end  -- C_Secrets and C_RestrictedActions are still there: all three present
printed = {}
local ok2, r2 = pcall(Probe.Run, Probe)
check(said("Chat lockdown here: missing (missing)."), "the summary shows the probe's missing APIs as missing, never as nil")
check(ok2 and type(r2) == "table", "the probe never raises when its own APIs are gone (" .. tostring(r2) .. ")")
check(r2.at == 1111, "without GetServerTime the timestamp comes from time()")
check(r2.secrets.issecretvalue == true and r2.secrets.C_Secrets == true and r2.secrets.C_RestrictedActions == true,
  "all three Secret Values APIs present are all recorded present")
check(r2.gameMode.missing and r2.chat.lockdown.missing and r2.chat.instance.missing and r2.roster.realm == "missing" and r2.roster.realmName == "missing"
  and r2.guildMessage.missing, "each of the probe's own missing APIs is recorded as missing")
check(r2.apis["GameTooltip:OnTooltipSetItem"] == false, "without GameTooltip the tooltip scripts read missing")

local realCreateFrame = CreateFrame
CreateFrame = function() error("no frames today", 0) end
local ok3, r3 = pcall(Probe.Run, Probe)
CreateFrame = realCreateFrame
check(ok3 and #r3.missingEvents == #Probe.EVENTS and r3.apis.BackdropTemplate == false,
  "a client that cannot build frames records every event and template missing, without raising")

-- The unlikely rest: CreateFrame returning nothing, no clock at all, a namespace that raises on lookup.
local realTime = time
CreateFrame, time = function() return nil end, nil
C_GameRules = setmetatable({}, { __index = function() error("rules lookup exploded") end })
local ok4, r4 = pcall(Probe.Run, Probe)
CreateFrame, time, C_GameRules = realCreateFrame, realTime, nil
check(ok4 and r4.at == 0 and r4.gameMode.missing and #r4.missingEvents == #Probe.EVENTS and r4.apis.BackdropTemplate == false,
  "no frame, no clock and a raising namespace still leave a record and never raise")

print(("probe: %d checks passed"):format(checks))
