-- Readiness on WoW: Forever (issue #206), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua and Modules/Readiness.lua.
--
-- Forever has no attunements, so the door to a raid is level 60: a character at 30 in full gear is
-- not ready, and a 60 without the addon is, by level only. The guild's minimum item level and a
-- missing enchant warn and still count. CASES is the table guildos.me's readiness test runs too
-- (apps/web, guildos-web #253): change one, change both.
--
--   luajit -e 'ADDON="."' tools/readiness-forever.lua
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

-- { what, member { level, hasGear, ilvl, missEnch }, guild minimum, status, reason, level only }
local CASES = {
  { "30 in full gear", { level = 30, hasGear = true, ilvl = 60, missEnch = 0 }, nil, "notready", "level", false },
  { "59 without the addon", { level = 59, hasGear = false }, nil, "notready", "level", false },
  { "60 without the addon", { level = 60, hasGear = false }, 55, "ready", nil, true },
  { "60 under the minimum", { level = 60, hasGear = true, ilvl = 50, missEnch = 0 }, 55, "warn", "ilvl", false },
  { "60 under the minimum and an enchant missing", { level = 60, hasGear = true, ilvl = 50, missEnch = 2 }, 55, "warn", "ilvl", false },
  { "60 with an enchant missing", { level = 60, hasGear = true, ilvl = 60, missEnch = 1 }, nil, "warn", "enchants", false },
  { "60 at the minimum", { level = 60, hasGear = true, ilvl = 55, missEnch = 0 }, 55, "ready", nil, false },
  { "60 with no minimum set", { level = 60, hasGear = true, ilvl = 10, missEnch = 0 }, nil, "ready", nil, false },
}

local ROSTER = {
  { "Kael Dunmore", 30 }, { "Tess Varn", 60 }, { "Mira Thornwood", 60 }, { "Orin Vale", 60 },
}
local published = {}

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
    function UnitFullName() return "Chehul", "Costa" end
    C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
    function UnitName() return "Chehul" end
  end
  function GetRealmName() return "Normal" end
  function GetNormalizedRealmName() return "Normal" end
  function GetServerTime() return 1794139200 end
  function IsInGuild() return true end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i)
    local r = ROSTER[i]
    if r then return r[1], "Member", 5, r[2], "Mage", "", "", "", true, 0, "MAGE" end
  end
  C_Timer = { After = function() end, NewTicker = function() end }
  Enum = { SendAddonMessageResult = {} }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Modules/Readiness.lua")
  GuildOS.db = { members = {}, settings = {} }
  GuildOS.SyncService = { Publish = function(_, dom, act, data, opts) published[#published + 1] = { dom = dom, act = act, data = data, rev = opts.rev } end }
  function GuildOS:IsOfficer() return self.officer end
  return GuildOS
end

local G = load("forever")
local R = G.Readiness

-- ── The rule, case by case ──────────────────────────────────────────────
for _, c in ipairs(CASES) do
  local status, reason, levelOnly = R.ForeverStatus(c[2], c[3], 60)
  check(status == c[4] and reason == c[5] and levelOnly == c[6],
    ("%s: %s/%s/%s, want %s/%s/%s"):format(c[1], tostring(status), tostring(reason), tostring(levelOnly), c[4], tostring(c[5]), tostring(c[6])))
end

-- ── The report over the guild roster ────────────────────────────────────
-- Gear for everybody but Orin, who never published; Mira is missing an enchant.
local key = function(n) return G:GetPlayerKey(n) end
G.GearAudit = { GetGuildEnchantAudit = function()
  return { { key = key("Kael Dunmore"), missingCount = 0 }, { key = key("Tess Varn"), missingCount = 0 },
    { key = key("Mira Thornwood"), missingCount = 1 } }
end }
for _, n in ipairs({ "Kael Dunmore", "Tess Varn", "Mira Thornwood" }) do G.db.members[key(n)] = { avgIlvl = 60 } end
local by = {}
for _, row in ipairs(R:GetReport()) do by[row.name] = row end
check(by["Kael Dunmore"].status == "notready" and by["Kael Dunmore"].reason == "level", "a 30 in full gear is not ready")
check(by["Kael Dunmore"].level == 30, "and the row carries the level")
check(by["Tess Varn"].status == "ready" and not by["Tess Varn"].levelOnly, "a 60 with the addon and nothing missing is ready")
check(by["Mira Thornwood"].status == "warn" and by["Mira Thornwood"].reason == "enchants", "a missing enchant warns")
check(by["Orin Vale"].status == "ready" and by["Orin Vale"].levelOnly, "a 60 without the addon is ready, by level only")
local s = R:Summarize()
check(s.ready + s.warn == 3 and s.notready == 1, "three of four can step through the door")
check(#R:GetTargets() == 0, "no attunement targets on Forever")

-- ── The guild's minimum ─────────────────────────────────────────────────
check(R:GetMinIlvl() == nil and not R:MinIlvlKnown(), "no minimum until an officer says")
G.officer = false
check(R:SetMinIlvl(55) == false and R:GetMinIlvl() == nil, "a member cannot set it")
G.officer = true
check(R:SetMinIlvl(1001) == false, "an item level past any is refused")
check(R:SetMinIlvl(55) and R:GetMinIlvl() == 55 and R:MinIlvlKnown(), "an officer sets it")
local p = published[#published]
check(p and p.dom == "guildcfg" and p.act == "readymin" and p.data.min == 55 and p.rev == G.db.settings.readyMinIlvlAt, "and the guild is told, stamped")
by = {}
for _, row in ipairs(R:GetReport()) do by[row.name] = row end
check(by["Tess Varn"].status == "ready", "at the minimum: ready")
G.db.members[key("Tess Varn")].avgIlvl = 50
by = {}
for _, row in ipairs(R:GetReport()) do by[row.name] = row end
check(by["Tess Varn"].status == "warn" and by["Tess Varn"].reason == "ilvl", "under it: a warning, and still through the door")

local at = G.db.settings.readyMinIlvlAt
R:OnMinIlvlSync({ rev = at - 10, data = { min = 70 } })
check(R:GetMinIlvl() == 55, "an older stamp loses")
R:OnMinIlvlSync({ rev = at, data = { min = 60 } })
check(R:GetMinIlvl() == 55, "the same stamp settles on the lower minimum")
R:OnMinIlvlSync({ rev = at + 10, data = { min = 3.5 } })
check(R:GetMinIlvl() == 55, "a minimum that is no item level is ignored")
R:OnMinIlvlSync({ rev = at + 10, data = {} })
check(R:GetMinIlvl() == nil and G.db.settings.readyMinIlvlAt == at + 10, "a newer one with none clears it")
check(R:SetMinIlvl(nil) and R:MinIlvlKnown() and published[#published].data.min == nil, "an officer clears it, and that is said too")
check(R:SetMinIlvl(55) and R:SetMinIlvl(0) and R:GetMinIlvl() == nil, "zero clears it too")

-- ── The countdown (issue #207) ──────────────────────────────────────────
local OPENS = R.FOREVER_RAIDS[1].opensAt
for i = 1, 8 do ROSTER[#ROSTER + 1] = { "Sixty " .. i, 60 } end   -- 11 at 60 in all
ROSTER[#ROSTER + 1] = { "Chehul Costa", 52 }
local rows = R:GetReport()
G.CoreManager = nil
local cd = R:Countdown(rows, OPENS - 36 * 86400 + 3600)
check(cd and cd.days == 36 and not cd.open, "36 days to go: " .. tostring(cd and cd.days))
check(#cd.cores == 0 and cd.guild.ready == 11 and cd.guild.enough == 10, "no cores: the guild, 11 at 60, enough for a 10")
check(cd.me and cd.me.level == 52, "and my own line")
G.CoreManager = {
  GetAll = function() return {
    ["Ember 10"] = { raidSize = 10, members = { [key("Tess Varn")] = {}, [key("Kael Dunmore")] = {}, [key("Orin Vale")] = { status = "bench" } } },
    ["Ember 20"] = { raidSize = 20, members = { [key("Tess Varn")] = {}, [key("Mira Thornwood")] = {}, [key("Somebody Gone")] = {} } },
    ["Alpha 40"] = { raidSize = 40, members = {} },
    ["Beta 10"] = { raidSize = 10, members = {} },
  } end,
  GetRaidSize = function(_, name) return ({ ["Ember 10"] = 10, ["Ember 20"] = 20, ["Alpha 40"] = 40, ["Beta 10"] = 10 })[name] end,
}
cd = R:Countdown(rows, OPENS - 86400 * 3)
check(#cd.cores == 3 and cd.cores[1].name == "Alpha 40" and cd.cores[2].name == "Ember 20" and cd.cores[3].name == "Beta 10",
  "three cores at most, largest first")
local ember20 = cd.cores[2]
check(ember20.ready == 2 and ember20.size == 20, "a core counts its members at 60, and nobody who left the guild")
cd = R:Countdown(rows, OPENS - 86400 * 3)
for _, c in ipairs(cd.cores) do
  if c.name == "Ember 10" then check(false, "Ember 10 should have been cut as the fourth") end
end
G.CoreManager.GetAll = function() return { ["Ember 10"] = { raidSize = 10, members = { [key("Tess Varn")] = {}, [key("Orin Vale")] = { status = "bench" } } } } end
cd = R:Countdown(rows, OPENS - 86400 * 3)
check(cd.cores[1].ready == 1, "a reserve is not counted")
cd = R:Countdown(rows, OPENS + 3 * 86400)
check(cd and cd.open, "open for a week")
check(R:Countdown(rows, OPENS + 8 * 86400) == nil, "then gone")
ROSTER[#ROSTER] = nil
for _ = 1, 8 do ROSTER[#ROSTER] = nil end

-- ── Not on the other games ──────────────────────────────────────────────
published = {}
local A = load("anniversary")
A.officer = true
check(A.Readiness:SetMinIlvl(55) == false and #published == 0, "TBC Anniversary has no minimum to set")
A.Readiness:OnMinIlvlSync({ rev = 1794139200, data = { min = 55 } })
check(A.Readiness:GetMinIlvl() == nil, "nor takes one")

print(("readiness-forever: %d checks passed"):format(checks))
