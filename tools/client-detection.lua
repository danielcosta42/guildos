-- Client detection (issue #7), run against the real Core/Core.lua,
-- Core/Compat.lua, UI/FeatureRegistry.lua, UI/Features.lua and the module
-- files that carry TBC content, under stubbed clients.
--
-- WoW: Forever is in the Classic family but has none of the TBC content, and
-- no WOW_PROJECT_ID of its own yet. This proves BRutus.Client recognises TBC
-- Anniversary only by its project id and its interface together, reports each
-- capability from the API behind it, and that attunements, consumables, the
-- raid cooldown HUD toggle and the wishlist raid catalogue exist only there,
-- without touching the player's own toggles.
--
-- ponytail: the audit sub-tab filter, the HUD gates, the member detail
-- attunement section, the /gos help lines, the Settings consumable test and
-- the command messages are one condition each and are checked in the game.
--
--   luajit -e 'ADDON="."' tools/client-detection.lua
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

-- ── WoW API surface the files touch while they load and start ────────
function CreateFrame()
  return { RegisterEvent = function() end, SetScript = function() end }
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetServerTime() return 1757800000 end
function IsInGuild() return false end
function hooksecurefunc() end
function debugstack() return "" end
C_Timer = { After = function() end }

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

-- A client is what GetBuildInfo says, its project constants and which of the
-- capability APIs exist. Compat.lua reads all of it once, when it loads.
local function client(c)
  GetBuildInfo = function() return c.version, c.build, "Sep 1 2026", c.interface end
  WOW_PROJECT_ID = c.project
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC = c.tbcProject
  local api = c.api or {}
  issecretvalue = api.secrets and function() return false end or nil
  C_ChatInfo = { InChatMessagingLockdown = api.chatLockdown and function() return false end or nil }
  C_TradeSkillUI = api.tradeSkillUI and {} or nil
  TooltipDataProcessor = api.tooltipData and {} or nil
  C_GuildInfo = { SetNote = api.guildSetNote and function() end or nil }
  dofile(ADDON .. "/Core/Compat.lua")
end

local ANNIVERSARY = { version = "2.5.6", build = "63110", interface = 20506, project = 5, tbcProject = 5 }
local FOREVER     = { version = "1.60.0", build = "64210", interface = 16000, project = 2, tbcProject = 5 }
local REUSED_ID   = { version = "1.60.1", build = "64300", interface = 16001, project = 5, tbcProject = 5 }
local UNKNOWN     = { version = "0.0.0", build = "0", interface = 20506 }  -- no WOW_PROJECT_* constants
local CLIENTS = {
  { c = ANNIVERSARY, tbc = true,  label = "TBC Anniversary" },
  { c = FOREVER,     tbc = false, label = "a 1.60 client" },
  { c = UNKNOWN,     tbc = false, label = "an unknown client" },
}

dofile(ADDON .. "/Core/Core.lua")
function BRutus:IsOfficer() return true end
function BRutus:LootSystemShowsWishlist() return true end
function BRutus:LootSystemShowsDKP() return true end

-- ── 1. Which client this is ─────────────────────────────────────────────
client(ANNIVERSARY)
local CL = BRutus.Client
check(CL.version == "2.5.6" and CL.build == "63110" and CL.date == "Sep 1 2026" and CL.interface == 20506,
  "the build fields come from GetBuildInfo")
check(CL.projectId == 5, "the project id is kept for diagnostics")
check(CL.isAnniversary == true, "TBC Anniversary is recognised")
local DOCUMENTED = { version = true, build = true, date = true, interface = true, projectId = true,
  isAnniversary = true, has = true }
for key in pairs(CL) do
  check(DOCUMENTED[key], "BRutus.Client carries no flavour guess beyond its documented fields (" .. tostring(key) .. ")")
end

client(FOREVER)
check(BRutus.Client.isAnniversary == false and BRutus.Client.projectId == 2 and BRutus.Client.interface == 16000,
  "a 1.60 client is not Anniversary")
client(REUSED_ID)
check(BRutus.Client.isAnniversary == false, "project id 5 on a 1.60 build is not Anniversary")
client({ version = "2.5.6", build = "1", interface = 20506, project = 2, tbcProject = 5 })
check(BRutus.Client.isAnniversary == false,
  "an Anniversary interface on another project id is not Anniversary, even with the constant defined")
client({ version = "2.5.6", build = "1", interface = nil, project = 5, tbcProject = 5 })
check(BRutus.Client.isAnniversary == false and BRutus.Client.interface == 0,
  "a client that reports no interface is not Anniversary")
client(UNKNOWN)
check(BRutus.Client.isAnniversary == false and BRutus.Client.projectId == nil,
  "a client without project constants is not Anniversary, even at interface 20506")

for _, edge in ipairs({ { 20499, false }, { 20500, true }, { 29999, true }, { 30000, false } }) do
  client({ version = "2.5.x", build = "1", interface = edge[1], project = 5, tbcProject = 5 })
  check(BRutus.Client.isAnniversary == edge[2],
    "interface " .. edge[1] .. (edge[2] and " is" or " is not") .. " in the Anniversary range")
end
client({ version = "2.5.6", build = "1", interface = "20506", project = 5, tbcProject = 5 })
check(BRutus.Client.interface == 20506 and BRutus.Client.isAnniversary, "an interface given as text still counts")

-- ── 2. What it can do ───────────────────────────────────────────────────
local FLAGS = { "secrets", "chatLockdown", "tradeSkillUI", "tooltipData", "guildSetNote" }
client(ANNIVERSARY)
for _, flag in ipairs(FLAGS) do
  check(BRutus.Client.has[flag] == false, flag .. " is false when its API is absent")
end
for _, only in ipairs(FLAGS) do
  client(setmetatable({ api = { [only] = true } }, { __index = ANNIVERSARY }))
  for _, flag in ipairs(FLAGS) do
    check(BRutus.Client.has[flag] == (flag == only),
      flag .. (flag == only and " follows its own API" or " ignores " .. only .. "'s API"))
  end
end
GetBuildInfo = function() return "0.0.0", "0", "", 0 end
C_ChatInfo, C_GuildInfo = nil, nil
dofile(ADDON .. "/Core/Compat.lua")
check(BRutus.Client.has.chatLockdown == false and BRutus.Client.has.guildSetNote == false,
  "a client without C_ChatInfo or C_GuildInfo at all loads and reports neither")

-- Quest completion, which /gos attune dumpquests reads on any client.
C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }
IsQuestFlaggedCompleted = function() return false end
check(BRutus.Compat.IsQuestComplete(1) == true, "C_QuestLog answers quest completion when it exists")
C_QuestLog = nil
IsQuestFlaggedCompleted = function(id) return id == 1 end
check(BRutus.Compat.IsQuestComplete(1) == true and BRutus.Compat.IsQuestComplete(2) == false,
  "without C_QuestLog, quest completion falls back to the global")
IsQuestFlaggedCompleted = nil
check(BRutus.Compat.IsQuestComplete(1) == false, "without either quest API, no quest reads complete")

-- ── 3. TBC modules exist only on Anniversary ────────────────────────────
local WISHED, RAID_ITEM = 999001, 21882  -- 21882: the first Karazhan drop in the raid catalogue
BRutus.db = {
  members = {},
  settings = { modules = { consumableChecker = true } },
  guildWishlists = {
    ["Ana-Firemaw"] = { name = "Ana", class = "MAGE", wishlist = { { itemId = WISHED, order = 1 } } },
  },
}
for _, case in ipairs(CLIENTS) do
  client(case.c)
  BRutus.AttunementTracker, BRutus.ConsumableChecker, BRutus.Wishlist = nil, nil, nil
  BRutus.State.startup.failed = {}
  dofile(ADDON .. "/Modules/AttunementTracker.lua")
  dofile(ADDON .. "/Modules/ConsumableChecker.lua")
  dofile(ADDON .. "/Modules/WishlistSystem.lua")
  dofile(ADDON .. "/Modules/RaidTools.lua")
  local on = case.tbc and " exists on " or " does not exist on "
  check((BRutus.AttunementTracker ~= nil) == case.tbc, "the attunement tracker" .. on .. case.label)
  check((BRutus.ConsumableChecker ~= nil) == case.tbc, "the consumable checker" .. on .. case.label)
  check(BRutus:StartModule({ "AttunementTracker" }) == case.tbc
    and BRutus:StartModule({ "ConsumableChecker", feature = "consumableChecker" }) == case.tbc,
    "the TBC modules start only where they exist (" .. case.label .. ")")
  check(next(BRutus.State.startup.failed) == nil, "nothing is recorded as failed to start on " .. case.label)
  check(BRutus.Wishlist ~= nil, "the wishlist exists on " .. case.label)
  BRutus.Wishlist:RebuildItemIndex()
  check(BRutus.Wishlist:GetItemInterest(WISHED) ~= nil, "a wished item is searchable on " .. case.label)
  check((BRutus.Wishlist:GetItemInterest(RAID_ITEM) ~= nil) == case.tbc,
    "the TBC raid catalogue is " .. (case.tbc and "" or "not ") .. "seeded on " .. case.label)
  local cds = {}
  for _, cd in ipairs(BRutus.RaidTools:ResolveCoverage(BRutus.RaidTools.COOLDOWNS, { SHAMAN = 1, HUNTER = 1, DRUID = 1 })) do
    cds[cd.name] = cd.covered
  end
  check((cds["Bloodlust/Heroism"] ~= nil) == case.tbc and (cds["Misdirection"] ~= nil) == case.tbc,
    "Bloodlust/Heroism and Misdirection are " .. (case.tbc and "" or "not ") .. "in Raid Tools on " .. case.label)
  check(cds["Battle Rez"] == true and cds["Innervate"] == true, "generic raid cooldowns stay in Raid Tools on " .. case.label)
end

-- ── 4. The hub and the Settings list ────────────────────────────────────
BRutus.UI = {}
dofile(ADDON .. "/UI/FeatureRegistry.lua")
dofile(ADDON .. "/UI/Features.lua")
local UI = BRutus.UI
local function listed(id)
  for _, def in ipairs(UI:AllFeatures(nil)) do
    if def.id == id then return true end
  end
  return false
end
for _, case in ipairs(CLIENTS) do
  client(case.c)
  for _, id in ipairs({ "consumableChecker", "raidHUD" }) do
    check(listed(id) == case.tbc, id .. (case.tbc and " is listed on " or " is not listed on ") .. case.label)
    check(UI:IsFeatureAllowed(UI:GetFeature(id)) == case.tbc,
      id .. (case.tbc and " is allowed on " or " is refused on ") .. case.label)
  end
  for _, id in ipairs({ "lootMaster", "lootTracker", "raidTracker", "wishlist" }) do
    check(listed(id), id .. " is not TBC content and stays listed on " .. case.label)
  end
  check(BRutus.db.settings.modules.consumableChecker == true and BRutus.db.settings.modules.raidHUD == nil,
    "the player's own toggles are untouched on " .. case.label)
end

print(("client-detection: %d checks passed"):format(checks))
