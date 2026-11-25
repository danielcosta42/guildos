-- Winter Veil: taking part in the game's event counts for the Chimney (guildos-web#671). Real CompanionImport and
-- WinterVeil under stubbed WoW APIs.
-- Proves: only a quest of the list, turned in (the event, never IsQuestFlaggedCompleted) inside Dec 15 00:00 (UTC-3) to
-- the wrapping deadline, by an entrant of this year's event, is kept; once; the export carries `plays`; GOSVEIL1's
-- `played` is read as untrusted and shown.
--
--   luajit -e 'ADDON="."' tools/winter-plays.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
package.path = ADDON .. "/?.lua;" .. package.path

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── WoW API surface ───────────────────────────────────────────────────
local NOW = 1765800000
local GUILD = "Curva-Mor"
local ME = "Chehul"
function GetServerTime() return NOW end
function GetTime() return 0 end
function IsInGuild() return true end
function GetGuildInfo() return GUILD, "Member", 3 end
function GetRealmName() return "Nightslayer" end
function UnitName() return ME end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function() end }
end
local roster = { { "Thalindra-Nightslayer", true }, { "Kaelthos-Nightslayer", true } }
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) local r = roster[i]; return r[1], nil, nil, nil, nil, nil, nil, nil, r[2] end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
  minor = 1,
}, {
  __call = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
})

GuildOS = {
  VERSION = "1.42.0",
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { settings = { companion = true } },
  Client = { isAnniversary = true, defaultRaidSize = 25 },
  Compat = {
    PlayerName = function() return ME end,
  },
}
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:SetSetting(k, v) self.db.settings[k] = v end
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
function GuildOS:Print() end
function GuildOS:IsOfficer() return false end
dofile(ADDON .. "/Core/Utils.lua")

local published = {}
GuildOS.SyncService = {
  Publish = function(_, dom, act, data, opts) published[#published + 1] = { dom = dom, act = act, data = data, opts = opts } end,
  On = function() end,
}

dofile(ADDON .. "/Libs/LibDeflate.lua")
local LibDeflate = LibStub("LibDeflate")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/WinterVeil.lua")
local Import, WV = GuildOS.CompanionImport, GuildOS.WinterVeil

local function pack(fmt, t)
  return fmt .. ":" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(GuildOS.Companion.EncodeJson(t)))
end
local SALT = "00112233445566778899aabbccddeeff"
local function veil(extra)
  local v = { year = 2025, joinUntil = NOW - 86400, wrapUntil = NOW + 5 * 86400, openAt = NOW + 6 * 86400, reassignDays = 3,
              drawn = true, salt = SALT, chimney = 60, counts = { entrants = 5, wrapped = 3, pairs = 5, opened = 0 } }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end
local function inbox(gild, personal)
  GuildOSInbox = {}
  if gild then GuildOSInbox[#GuildOSInbox + 1] = pack("GOSGILD1", { fmt = "GOSGILD1", v = 1, guild = GUILD, realm = "Nightslayer", at = NOW - 60, veil = gild }) end
  if personal then
    local p = { fmt = "GOSVEIL1", v = 2, guild = GUILD, realm = "Nightslayer", at = NOW - 60, year = 2025, mine = {}, relay = {}, collection = {} }
    for k, x in pairs(personal) do p[k] = x end
    GuildOSInbox[#GuildOSInbox + 1] = pack("GOSVEIL1", p)
  end
  Import._blockRaw, Import._veilRaw = nil, nil
end
local ME_KEY = "Chehul-Nightslayer"
local function personal(gives, got, extra)
  local p = { mine = { { key = ME_KEY, volunteer = false, gives = gives or {}, got = got } } }
  for k, x in pairs(extra or {}) do p[k] = x end
  return p
end


-- The list of the data file, the real one, must load and stay well-formed.
GuildOS.WinterVeilQuests = nil
dofile(ADDON .. "/Data/WinterVeilQuests.lua")
check(type(GuildOS.WinterVeilQuests) == "table", "the data file defines the list")
for id, name in pairs(GuildOS.WinterVeilQuests) do
  check(math.type == nil and type(id) == "number" and id == math.floor(id) and id > 0 and type(name) == "string" and name ~= "", "each quest is [questID] = name: " .. tostring(id))
end
-- The tests use their own list; the real one may be empty.
GuildOS.WinterVeilQuests = { [7021] = "Test quest", [7043] = "Another" }

-- 2025-12-15 00:00 at UTC-3 = 03:00 UTC.
local START = 1765767600
check(WV.PlayStart(2025) == START, "the window starts Dec 15 00:00 UTC-3 (" .. WV.PlayStart(2025) .. ")")
check(WV.PlayStart(2026) == 1797303600, "and for 2026")
local WRAP = START + 10 * 86400
local function ev(extra) return veil(extra) end
local function setup(t, e, joined, personal_)
  NOW = t
  inbox(ev(e or { year = 2025, wrapUntil = WRAP, openAt = WRAP + 86400 }), personal_ or { mine = {} })
  GuildOS.db.winterVeil = nil
  if joined ~= false then WV._store().people[ME_KEY] = { join = { volunteer = false, at = START - 100 } } end
end

setup(START + 10)
check(WV:OnQuestTurnedIn(7021) == true and WV:Played(), "a quest of the list inside the window, joined: kept")
local pl = WV._store().played
check(pl.key == ME_KEY and pl.at == START + 10, "as { key, at } of this character")
NOW = START + 500
check(WV:OnQuestTurnedIn(7043) == false and WV._store().played.at == START + 10, "only the first is kept")
local out = WV:ForExport()
check(#out.plays == 1 and out.plays[1].key == ME_KEY and out.plays[1].at == START + 10, "the export carries plays = { { key, at } }")
local keys = 0
for _ in pairs(out.plays[1]) do keys = keys + 1 end
check(keys == 2, "and no quest ID")
local json = GuildOS.Companion.EncodeJson(out)
check(json:find('"plays"', 1, true) and not json:find("7021", 1, true), "the JSON has plays, never the quest")

setup(START + 10)
check(WV:OnQuestTurnedIn(9999) == false and not WV:Played(), "a quest outside the list is not a play")
check(WV:OnQuestTurnedIn(nil) == false and WV:OnQuestTurnedIn("7021") == false, "nor a quest ID that is not a number")
setup(START - 1)
check(WV:OnQuestTurnedIn(7021) == false and not WV:Played(), "before Dec 15 00:00 UTC-3: no")
setup(START)
check(WV:OnQuestTurnedIn(7021) == true, "at the very start: yes")
setup(WRAP - 1)
check(WV:OnQuestTurnedIn(7021) == true, "the last second before the wrapping deadline: yes")
setup(WRAP)
check(WV:OnQuestTurnedIn(7021) == false and not WV:Played(), "at the deadline: no")
setup(WRAP + 5 * 86400)
check(WV:OnQuestTurnedIn(7021) == false, "after it: no")
check(#WV:ForExport().plays == 0, "and the export carries none")

setup(START + 10, nil, false)
check(WV:OnQuestTurnedIn(7021) == false and not WV:Played(), "not signed up: no")
setup(START + 10)
WV._store().people[ME_KEY] = { left = START }
check(WV:OnQuestTurnedIn(7021) == false, "left the event: no")
NOW = START + 10
inbox(nil)
GuildOS.db.winterVeil = nil
check(WV:Event() == nil and WV:OnQuestTurnedIn(7021) == false, "no event for this person: no")
-- The site's block carries me as an entrant: that is signing up too.
setup(START + 10, nil, false, personal({}, nil))
check(WV:Joined() and WV:OnQuestTurnedIn(7021) == true, "an entry in the site's own block counts as signed up")

-- Another year starts clean.
setup(START + 10)
WV:OnQuestTurnedIn(7021)
setup(WV.PlayStart(2026) + 10, { year = 2026, wrapUntil = WV.PlayStart(2026) + 86400 * 10, openAt = WV.PlayStart(2026) + 86400 * 11 })
GuildOS.db.winterVeil = { year = 2025, played = { key = ME_KEY, at = START + 10 } }
check(not WV:Played() and #WV:ForExport().plays == 0, "last year's participation does not carry over")

-- The empty list: nothing is ever recorded.
GuildOS.WinterVeilQuests = {}
setup(START + 10)
check(WV:OnQuestTurnedIn(7021) == false and not WV:Played(), "an empty list records nothing")
GuildOS.WinterVeilQuests = nil
check(WV:OnQuestTurnedIn(7021) == false, "and a missing one does not raise")
GuildOS.WinterVeilQuests = { [7021] = "Test quest" }

-- The event handler: QUEST_TURNED_IN reaches OnQuestTurnedIn (the real module's frame), IsQuestFlaggedCompleted never does.
do
  local handler, registered
  function CreateFrame()
    return { RegisterEvent = function(_, ev) registered = registered or {}; registered[ev] = true end,
             SetScript = function(_, n, fn) if n == "OnEvent" then handler = fn end end }
  end
  GuildOS.Compat.RegisterEvent = function(f, ev) f:RegisterEvent(ev) end
  WV:Initialize()
  check(registered and registered.QUEST_TURNED_IN, "the module listens to QUEST_TURNED_IN")
  setup(START + 10)
  handler({}, "QUEST_TURNED_IN", 7021, 100, 50)
  check(WV:Played(), "the event records it")
  local src = io.open(ADDON .. "/Modules/WinterVeil.lua"):read("*a")
  check(not src:gsub("%-%-[^\n]*", ""):find("IsQuestFlaggedCompleted", 1, true), "IsQuestFlaggedCompleted is not called")
end

-- ── GOSVEIL1 `played` ─────────────────────────────────────────────────
setup(START + 10, nil, true, { mine = {}, played = true })
check(WV:PlaySeen() == true, "played = true is read")
for _, bad in ipairs({ "true", 1, "yes", {}, false }) do
  setup(START + 10, nil, true, { mine = {}, played = bad })
  check(WV:PlaySeen() == false, "played = " .. tostring(type(bad) == "table" and "{}" or bad) .. " is not true")
end
setup(START + 10, nil, true, { mine = {} })
check(WV:PlaySeen() == false, "absent is false")

-- ── The panel shows it ────────────────────────────────────────────────
do
  local Frame = {}
  Frame.__index = function(_, k) if type(k) == "string" and k:sub(1, 1) == "_" then return nil end return Frame[k] or function(self) return self end end
  local function new() return setmetatable({ shown = true, scripts = {}, text = "" }, Frame) end
  function Frame:SetText(t) self.text = t end
  function Frame:GetText() return self.text end
  function Frame:SetShown(v) self.shown = v and true or false end
  function Frame:Show() self.shown = true end
  function Frame:Hide() self.shown = false end
  function Frame:SetScript(n, fn) self.scripts[n] = fn end
  function Frame:CreateTexture() return new() end
  local texts = {}
  local UI = {}
  for _, name in ipairs({ "CreateTitle", "CreateText", "CreateSectionTitle", "CreateMetricChip", "CreateProgressBar", "CreateButton", "CreatePanel", "SetButtonVariant" }) do
    UI[name] = function(_, a, b)
      local f = new()
      if type(b) == "string" then f.text = b elseif type(a) == "string" then f.text = a end
      texts[#texts + 1] = f
      return f
    end
  end
  UI.CreateCheckbox = function() local f = new(); f.checkbox = new(); return f end
  UI.CreateTextArea = function() local f = new(); f.edit = new(); return f end
  UI.CreateTab = function() local f = new(); function f:SetActive() end; return f end
  GuildOS.UI = UI
  GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  GuildOS.QualityColors = GuildOS.Colors
  GuildOS.L = setmetatable({}, { __index = function(_, k) return k end })
  function CreateFrame() return new() end
  function date(...) return os.date(...) end
  function GuildOS:IsOfficer() return false end
  dofile(ADDON .. "/UI/WinterVeilPanel.lua")
  local panel = GuildOS:CreateWinterVeilPanel(new())
  local function say(text)
    for _, f in ipairs(texts) do if f.shown and f.text and tostring(f.text):find(text, 1, true) then return true end end
    return false
  end
  local function draw() local ok, err = pcall(panel.Draw); check(ok, "the panel draws: " .. tostring(err)) end

  setup(START + 10, nil, true, personal({ { to = "Thalindra-Nightslayer" } }))
  draw()
  check(say("In-game participation: not yet"), "no play yet: the panel says not yet")
  setup(START + 10, nil, true, personal({ { to = "Thalindra-Nightslayer" } }, nil, { played = true }))
  draw()
  check(say("In-game participation: registered"), "the site's block says played: registered")
  setup(START + 10, nil, true, personal({ { to = "Thalindra-Nightslayer" } }))
  WV:OnQuestTurnedIn(7021)
  draw()
  check(say("In-game participation: registered"), "a play kept here shows as registered")
end

print(string.format("winter-plays: %d checks passed", checks))
