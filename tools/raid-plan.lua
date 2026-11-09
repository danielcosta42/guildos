-- The night's plan in the game (issue #296), run against the real Core/Core.lua, Core/Compat.lua,
-- Modules/CompanionImport.lua and Modules/RaidPlan.lua on WoW: Forever: a v3 block has no plan, a v4
-- one is read and cut again, my task shows when I target its boss out of combat and never without a
-- task, in combat or twice, and the raid leader says a boss's note in raid chat in lines that fit.
--
--   luajit -e 'ADDON="."' tools/raid-plan.lua
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
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70707", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function UnitFullName() return "Ana Costa", "" end
C_PlayerInfo = { ShouldDisplaySurname = function() return false end }
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}

local combat, leader, assist, raid = false, true, false, true
function InCombatLockdown() return combat end
function IsInRaid() return raid end
function UnitIsGroupLeader() return leader end
function UnitIsGroupAssistant() return assist end
local target = "Lucifron"
function UnitExists() return target ~= nil end
function UnitName(unit)
  if unit == "target" then return target end
  return "Ana Costa"
end
local said = {}
C_ChatInfo = { InChatMessagingLockdown = function() return false end }
function SendChatMessage(text, chatType) said[#said + 1] = { text = text, chatType = chatType } end

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/Modules/RaidPlan.lua")
GuildOS.Print = function() end
GuildOS.SafeCall = function(_, fn, ...) return fn(...) end
GuildOS.Companion = { IsEnabled = function() return true end }
local I, Plan = GuildOS.CompanionImport, GuildOS.RaidPlan
local shownTask
Plan.ShowTask = function(_, boss) shownTask = boss end

-- v3: no plan at all.
check(I.ReadPlan({ fmt = "GOSROST1", v = 3, members = {} }) == nil, "a v3 block carries no plan")
check(I.ReadPlan({ assignments = {}, notes = {}, loot = { version = 1 } }) == nil, "an empty plan is no plan")

-- v4, read and cut again: the inbox is untrusted whatever wrote it.
local long = string.rep("Stand in the back and decurse. ", 40)
local plan = I.ReadPlan({
  assignments = {
    { boss = "Lucifron", key = "Ana Costa", name = "Ana Costa", kind = "interrupt", target = "skull", note = "Kick the adds" },
    { boss = "Lucifron", name = "Bo", kind = "tank", note = "" },
    { boss = "Magmadar", name = "Bo", kind = "position", note = string.rep("x", 300) },
    { name = "no boss" },
  },
  notes = { { boss = "Lucifron", text = long }, { boss = "Gehennas", text = "Decurse" }, { boss = "Empty" } },
  loot = { system = "softres", rules = "1 SR, MS > OS", version = 2 },
})
check(#plan.assignments == 3, "a task with no boss is dropped")
check(#plan.assignments[3].note == 120, "a task's text is cut to 120 again")
check(#plan.notes == 2 and #plan.notes[1].text == 500, "a note is cut to 500 again; one with no text is dropped")
check(plan.loot.system == "softres" and plan.loot.version == 2, "the loot rules")

GuildOS.db = { companionRoster = { raidId = "r1", title = "MC", plan = plan } }
local bosses = Plan:Bosses()
check(table.concat(bosses, ",") == "Lucifron,Gehennas,Magmadar", "bosses: the notes' order, then a boss only a task names")
check(#Plan:MyTasks("Lucifron") == 1 and #Plan:MyTasks("Magmadar") == 0, "my tasks by my key; Bo's are not mine")
check(Plan:TaskLine(Plan:MyTasks("Lucifron")[1]) == "Interrupt · {skull} · Kick the adds", "a task as one line")

-- My task when I target its boss, out of combat, once.
combat = true
Plan:OnTargetChanged()
check(shownTask == nil, "in combat nothing opens")
combat = false
target = "lucifron"
Plan:OnTargetChanged()
check(shownTask == "Lucifron", "targeting the boss out of combat shows my task, whatever the capitals")
shownTask = nil
Plan:OnTargetChanged()
check(shownTask == nil, "once per boss per raid")
target = "Magmadar"
Plan:OnTargetChanged()
check(shownTask == nil, "a boss where I have no task shows nothing")
target = "Some Trash"
Plan:OnTargetChanged()
check(shownTask == nil, "nor does anything that is not a boss of the plan")
issecretvalue = function(v) return v == "SECRET" end
target = "SECRET"
Plan:OnTargetChanged()
check(shownTask == nil, "a secret name is read as nobody")
issecretvalue = nil

-- The raid leader says a boss's note in raid chat, in lines that fit.
local lines = Plan:AnnounceLines("Lucifron")
check(#lines >= 3 and lines[1]:sub(1, 10) == "Lucifron: ", "the note in chat lines, the boss first")
for _, l in ipairs(lines) do check(#l <= 240, "every line fits a chat message (" .. #l .. ")") end
local n = Plan:Announce("Lucifron")
check(n == #lines and #said == #lines and said[1].chatType == "RAID", "said in raid chat, every line")
said = {}
combat = true
local none, why = Plan:Announce("Lucifron")
check(none == nil and why == "Not during combat." and #said == 0, "never during combat")
combat, leader = false, false
none, why = Plan:Announce("Lucifron")
check(none == nil and why == "Only the raid leader or an assistant can say it in raid chat.", "a raider cannot")
assist = true
check(Plan:Announce("Gehennas") == 1, "an assistant can")
none, why = Plan:Announce("Magmadar")
check(none == nil and why == "This boss has no note.", "a boss with no note says so")

-- No roster, or a v3 one: nothing to show and nothing to say.
GuildOS.db.companionRoster = { raidId = "r2", title = "BWL" }
check(#Plan:Bosses() == 0 and Plan:TaskToShow("Lucifron") == nil, "a roster with no plan has nothing")

print(("raid-plan: %d checks passed"):format(checks))
