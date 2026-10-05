-- Which Raid Core a raid is, worked out from who is in it (issue #99), run against the real
-- Core, Compat, Utils, CoreManager, RaidTracker and LootMaster under a stubbed client.
--
-- The active core was one per client, set by hand: an officer leading several of a guild's
-- rosters had to remember to switch before each raid, or the attendance, the DKP pool and the
-- loot rules went to the wrong core without a word. Now, until the first boss is pulled, the raid
-- follows the core whose roster covers the group; the active core is what is used when none does,
-- and an officer's pick inside the raid is final for it.
--
--   luajit -e 'ADDON="."' tools/core-detect.lua
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

local printed, GROUP, NOW = {}, {}, 1791000000
local function load(game)
  printed, NOW = {}, 1791000000
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
  function GetRealmName() return "Realm" end
  function GetServerTime() return NOW end
  function GetTime() return 1 end
  time = os.time
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1 end
  function GetNumGuildMembers() return 0 end
  function GetGuildRosterInfo() end
  function IsInRaid() return true end
  function GetNumGroupMembers() return #GROUP end
  function UnitExists(u) return u == "player" or GROUP[tonumber(u:match("%d+") or "")] ~= nil end
  function UnitIsConnected() return true end
  function UnitClass() return "Mage", "MAGE" end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
              NewTimer = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  StaticPopupDialogs = {}
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  dofile(ADDON .. "/Modules/RaidTracker.lua")
  BRutus.db = { settings = {}, members = {}, altLinks = {}, cores = {},
                raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
  local RT = BRutus.RaidTracker
  RT.currentGroupTag = ""
  RT.CheckPlayerConsumes = function() return false end
  RT.BroadcastRaidData = function() end
  -- The raid's units: GROUP holds "Name" or { "Name", "Realm" }, and "player" is me.
  BRutus.Compat.IsPlayer = function(u) return u == "player" end
  BRutus.Compat.UnitIdentity = function(u)
    local e = GROUP[tonumber(u:match("%d+") or "")]
    if type(e) == "table" then return e[1], e[2], "MAGE" end
    return e, nil, "MAGE"
  end
  BRutus.Compat.PlayerName = function() return game == "forever" and "Lead Er" or "Leader" end
  local loaded = {}
  BRutus.LootMaster = { LoadCfg = function() loaded[#loaded + 1] = BRutus.CoreManager:GetActiveName() end }
  return RT, BRutus.CoreManager, loaded
end
local function key(name, realm) return BRutus:GetPlayerKey(name, realm) end
local function roster(CM, core, names)
  CM:Create(core)
  for _, n in ipairs(names) do BRutus.db.cores[core].members[key(n)] = { role = "rdps" } end
end
local function group(names) GROUP = {}; for i, n in ipairs(names) do GROUP[i] = n end end
local function said(pattern)
  for i, m in ipairs(printed) do if m:find(pattern, 1, true) then return i end end
end
local function lines(pattern)
  local n = 0
  for _, m in ipairs(printed) do if m:find(pattern, 1, true) then n = n + 1 end end
  return n
end

for _, game in ipairs({ "forever", "anniversary" }) do
  local me = game == "forever" and "Lead Er" or "Leader"
  local function G(what) return game .. ": " .. what end

  -- ── The raid goes to the core whose roster is in it ───────────────────
  local RT, CM, loaded = load(game)
  roster(CM, "Alpha", { me, "Ann", "Bob", "Cid", "Dee" })
  roster(CM, "Bravo", { me, "Eve", "Fay", "Gus", "Hal" })
  RT:SetGroupTag("Alpha")
  group({ "Eve", "Fay", "Gus", "Hal", "Pug" })
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Bravo", G("a raid whose group is Bravo's roster is Bravo's, with Alpha active"))
  check(CM:GetActiveName() == "Bravo", G("and Bravo is now the active core, so DKP and loot rules follow it"))
  check(loaded[#loaded] == "Bravo", G("the loot rules are re-read from Bravo's config"))
  check(said("Raid core: |cffFFD700Bravo|r, with 5 of the 6"), G("the chat says which core, and how many of the group are on it"))
  check(said("Raid tracking started") and said("Raid tracking started") < said("Raid core:"),
    G("the start line comes first, then which core"))
  RT:TakeSnapshot("roster_change")
  check(lines("Raid core:") == 1, G("the same answer is not said again at every snapshot"))

  -- ── Before the first pull the raid follows who showed up; the pull settles it ──
  RT, CM = load(game)
  roster(CM, "Alpha", { "A1", "A2" })
  roster(CM, "Bravo", { me, "B1", "B2", "B3", "B4", "B5" })
  group({ "A1", "A2" })
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha", G("three people forming, two on Alpha: Alpha for now"))
  group({ "A1", "A2", "B1", "B2", "B3", "B4", "B5" })
  RT:TakeSnapshot("roster_change")
  check(RT.currentRaid.groupTag == "Bravo" and CM:GetActiveName() == "Bravo",
    G("Bravo's raiders join before the pull: the raid is Bravo's"))
  RT:OnEncounterStart(1, "Boss")
  roster(CM, "Charlie", { me, "C1", "C2", "C3", "C4", "C5", "C6", "C7" })
  group({ "C1", "C2", "C3", "C4", "C5", "C6", "C7" })
  RT:TakeSnapshot("periodic")
  check(RT.currentRaid.groupTag == "Bravo" and CM:GetActiveName() == "Bravo",
    G("after the first pull the core is settled, whoever is in the group"))

  -- ── Nothing matches: the active core stands, and later snapshots ask again ──
  RT, CM = load(game)
  roster(CM, "Alpha", { me, "Ann", "Bob", "Cid", "Dee" })
  RT:SetGroupTag("Alpha")
  group({ "Eve", "Fay", "Gus", "Hal", "Pug" })
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha" and not said("Raid core:"), G("a group that is no core's roster stays on the active core, silently"))
  roster(CM, "Bravo", { "Eve", "Fay" })
  group({ "Eve", "Fay" })
  RT:TakeSnapshot("roster_change")
  check(RT.currentRaid.groupTag == "Bravo",
    G("a group still forming is asked again at the next snapshot, as it is now: those who left do not count"))

  -- ── The thresholds: two people, half the group, no tie ─────────────────
  local function tagFor(rosters, names, active)
    local rt, cm = load(game)
    for core, members in pairs(rosters) do roster(cm, core, members) end
    rt:SetGroupTag(active or "Zulu")
    group(names)
    rt:StartSession(409)
    return rt.currentRaid.groupTag
  end
  check(tagFor({ Alpha = { "Ann", "Bob" } }, { "Ann", "Bob", "P1", "P2", "P3" }) == "Zulu",
    G("a roster under half the group does not take the raid"))
  check(tagFor({ Alpha = { "Ann", "Bob" } }, { "Ann", "Bob", "P1" }) == "Alpha",
    G("exactly half the group is enough"))
  check(tagFor({ Alpha = { "Ann" } }, { "Ann" }) == "Zulu", G("one person on a roster is not a raid of it"))
  check(tagFor({ Alpha = { "Ann", "Bob" } }, { "Ann", "Bob" }) == "Alpha", G("two people are"))
  check(tagFor({ Alpha = { "Ann", "Bob", "Cid" }, Bravo = { "Ann", "Bob", "Cid" } }, { "Ann", "Bob", "Cid" }) == "Zulu",
    G("two rosters tied for the group leave the active core"))
  check(tagFor({ Alpha = { "Ann" }, Bravo = { "Bob" }, Charlie = { "C1", "C2", "C3" } }, { "Ann", "Bob", "C1", "C2", "C3" }) == "Charlie",
    G("a tie below the best does not stop the best"))

  -- ── An alt counts as their main, on their main's roster only ──────────
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob" })
  roster(CM, "Bravo", { "Cid", "Dee" })
  BRutus.db.altLinks[key("Annalt")] = key("Ann")
  group({ "Annalt", "Bob", "Cid" })
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha", G("an alt in the raid counts as their main, for their main's core alone"))

  -- ── A realm is someone's, or not, as the game says ─────────────────────
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob" })
  RT:SetGroupTag("Zulu")
  group({ { "Ann", "Elsewhere" }, { "Bob", "Elsewhere" } })
  RT:StartSession(409)
  if game == "forever" then
    check(RT.currentRaid.groupTag == "Alpha", G("a realm the client reports is no one's, as every Forever key"))
  else
    check(RT.currentRaid.groupTag == "Zulu", G("namesakes from another realm are not the roster's"))
  end

  -- ── An officer's pick inside the raid is final for it ─────────────────
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob", "Cid" })
  group({ "P1", "P2", "P3" })
  RT:StartSession(409)
  RT:PickCore("Bravo")
  check(RT.currentRaid.groupTag == "Bravo", G("picking a core during a raid moves the session to it"))
  group({ "Ann", "Bob", "Cid" })
  RT:TakeSnapshot("roster_change")
  check(RT.currentRaid.groupTag == "Bravo", G("and the roster detection does not undo the officer's pick"))
  -- A /reload or a disconnect starts the session over: the pick holds for this character in this
  -- instance while its raid goes on, and for nothing after it.
  local function reload() RT.currentRaid, RT.trackingActive = nil, false end
  NOW = NOW + 1500; RT:TakeSnapshot("periodic")
  NOW = NOW + 1500; reload()
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Bravo", G("the pick survives a /reload, however long the raid has run"))
  check(said("Raid core: |cffFFD700Bravo|r, as you set it."), G("and says it is the officer's pick"))
  reload(); NOW = NOW + 3600
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha", G("a pick its raid stopped refreshing an hour ago is not kept"))
  local function picked()
    RT, CM = load(game)
    roster(CM, "Alpha", { "Ann", "Bob", "Cid" })
    group({ "Ann", "Bob", "Cid" })
    RT:StartSession(409)
    RT:PickCore("Bravo")
  end
  picked(); reload()
  RT:StartSession(532)
  check(RT.currentRaid.groupTag == "Alpha", G("another instance is asked again"))
  reload()
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha", G("and the pick it set aside does not come back with the first instance"))
  picked(); reload()
  BRutus.Compat.PlayerName = function() return "Other Char" end
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha", G("another character on the account is asked again"))
  picked()
  RT.currentRaid.startTime = NOW - 7200
  RT:EndSession()
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha" and BRutus.db.raidTracker.corePick == nil,
    G("a raid that ended takes its pick with it: the next one in that instance is asked again"))
  picked(); reload()
  RT:PickCore("Charlie")
  group({ "P1", "P2", "P3" })
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Charlie", G("a pick made outside, after a /reload, beats the one kept from inside"))

  -- ── A pick on a wipe's run-back is the raid's once it resumes ─────────
  picked()
  RT:PickCore("Alpha")
  RT.endTimer = { Cancel = function() end }
  RT:PickCore("Delta")
  check(RT.currentRaid.groupTag == "Alpha", G("on the run-back the pick waits for the raid"))
  function GetInstanceInfo() return "Molten Core", "raid", 9, "", 40, 0, false, 409 end
  RT:CheckZone()
  check(RT.endTimer == nil and RT.currentRaid.groupTag == "Delta" and CM:GetActiveName() == "Delta"
    and BRutus.db.raidTracker.corePick.tag == "Delta", G("and takes the raid when it resumes"))
  check(said("Raid core: |cffFFD700Delta|r, as you set it."), G("saying so, so it never takes a raid silently"))

  -- ── A raid's answer is never the last raid's ──────────────────────────
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob", "Cid" })
  group({ "Ann", "Bob", "Cid" })
  RT:StartSession(409)
  RT.currentRaid.startTime = NOW - 7200
  RT:EndSession()
  RT:PickCore("Bravo")
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "Alpha", G("the next raid's group is asked again, though the last one said the same"))

  -- ── The pull itself is asked before it settles ────────────────────────
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob" })
  roster(CM, "Bravo", { "Eve", "Fay", "Gus" })
  group({ "Ann", "Bob" })
  RT:StartSession(409)
  group({ "Eve", "Fay", "Gus" })
  RT:OnEncounterStart(1, "Boss")
  check(RT.currentRaid.groupTag == "Bravo" and RT.coreSettled, G("the group at the pull is the one the raid settles on"))

  -- ── After leaving: neither a pick nor the group re-tags the raid just left ──
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob", "Cid" })
  roster(CM, "Bravo", { "Eve", "Fay", "Gus" })
  group({ "Ann", "Bob", "Cid" })
  RT:StartSession(409)
  RT.endTimer = { Cancel = function() end }   -- left the zone: the 20-minute grace period
  RT:PickCore("Bravo")
  check(RT.currentRaid.groupTag == "Alpha" and CM:GetActiveName() == "Bravo",
    G("a pick in the grace period is for the next raid, not the one just left"))
  check(BRutus.db.raidTracker.corePick == nil, G("and is not kept as that raid's"))
  RT:SetGroupTag("Alpha")
  group({ "Eve", "Fay", "Gus" })
  RT:TakeSnapshot("roster_change")
  check(RT.currentRaid.groupTag == "Alpha", G("the next raid forming outside does not re-tag the one just left"))
  RT.endTimer = nil
  RT.currentRaid.startTime = NOW - 7200
  RT:EndSession()
  local saved
  for _, s in pairs(BRutus.db.raidTracker.sessions) do saved = s end
  check(saved and saved.groupTag == "Alpha" and CM:GetActiveName() == "Alpha" and lines("Raid core:") == 1,
    G("the session's last snapshot never re-tags it"))

  -- ── Renaming a core during a raid keeps everything pointed at it ──────
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob", "Cid" })
  group({ "Ann", "Bob", "Cid" })
  RT:StartSession(409)
  CM:Rename("Alpha", "Alpha2")
  check(RT.currentRaid.groupTag == "Alpha2" and CM:GetActiveName() == "Alpha2", G("a rename moves the raid in progress"))
  check(not RT.coreSettled, G("and does not settle its core"))
  RT:TakeSnapshot("roster_change")
  check(lines("Raid core:") == 1, G("nor say the renamed core again"))
  RT:PickCore("Alpha2")
  CM:Rename("Alpha2", "Alpha3")
  check(BRutus.db.raidTracker.corePick.tag == "Alpha3", G("nor leave a kept pick on the old name"))
  RT.endTimer = { Cancel = function() end }
  RT:PickCore("Alpha3")
  CM:Rename("Alpha3", "Alpha4")
  check(RT.gracePick == "Alpha4", G("nor a run-back pick"))

  -- ── A /reload inside the raid picks the session back up at once ───────
  RT, CM = load(game)
  roster(CM, "Alpha", { "Ann", "Bob", "Cid" })
  group({ "Ann", "Bob", "Cid" })
  BRutus.db.raidTracker.corePick = { instanceID = 409, tag = "Bravo", char = me, at = NOW - 600 }
  local onEvent
  CreateFrame = function()
    return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function(_, _, fn) onEvent = fn end }
  end
  C_Timer.After = function(_, fn) fn() end
  function GetInstanceInfo() return "Molten Core", "raid", 9, "", 40, 0, false, 409 end
  RT:Initialize()
  onEvent(nil, "PLAYER_ENTERING_WORLD")
  check(RT.currentRaid and RT.currentRaid.groupTag == "Bravo" and said("as you set it"),
    G("entering the world inside a raid restarts the session, and finds the pick while it is fresh"))

  -- ── A guild with no rosters sees nothing new ──────────────────────────
  RT, CM = load(game)
  group({ "Ann", "Bob", "Cid" })
  RT:StartSession(409)
  check(RT.currentRaid.groupTag == "" and not said("Raid core:"), G("no rosters, no detection and no new line"))
  check(CM:CoreForGroup({}) == nil and CM:CoreForGroup(nil) == nil, G("an empty group is no core's"))

  -- ── A detection that breaks loses neither the snapshot nor the raid ───
  RT, CM = load(game)
  CM.CoreForGroup = function() error("boom") end
  group({ "Ann" })
  RT:StartSession(409)
  check(#RT.currentRaid.snapshots == 1 and RT.snapshotTimer, G("a failing detection still keeps the snapshot and the timer"))
end

-- ── The loot rules really are re-read ───────────────────────────────────
local RT, CM = load("forever")
dofile(ADDON .. "/Modules/LootMaster.lua")
local LM = BRutus.LootMaster
CM:Create("Alpha"); CM:Create("Bravo")
local function cfg(core, v)
  RT:SetGroupTag(core)
  LM:SaveCfgKey("rollDuration", v.roll); LM:SaveCfgKey("autoAnnounce", v.auto); LM:SaveCfgKey("wishlistOnlyMode", v.wish)
  LM:SaveCfgKey("disenchanter", v.de); LM:SaveCfgKey("lootThreshold", v.thr)
end
cfg("Alpha", { roll = 15, auto = true, wish = true, de = "Ann", thr = 4 })
cfg("Bravo", { roll = 45, auto = false, wish = false, de = "Bob", thr = 2 })
RT:SetGroupTag("Alpha")
check(LM.ROLL_DURATION == 15 and LM.AUTO_ANNOUNCE == true and LM.WISHLIST_ONLY_MODE == true and LM.disenchanter == "Ann"
  and LM.LOOT_THRESHOLD == 4, "loot: switching the active core loads all of its cached rules")
RT:SetGroupTag("Bravo")
check(LM.ROLL_DURATION == 45 and LM.AUTO_ANNOUNCE == false and LM.WISHLIST_ONLY_MODE == false and LM.disenchanter == "Bob"
  and LM.LOOT_THRESHOLD == 2, "loot: and switching back loads the other's")

print(("core-detect: %d checks passed"):format(checks))
