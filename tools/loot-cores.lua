-- Each core with its own loot system, rule and accounts (issue #338), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Modules/CoreManager.lua,
-- Modules/RaidTracker.lua, Modules/Points.lua, Modules/LootRule.lua, Modules/LootMaster.lua,
-- UI/FeaturePanels.lua and UI/CorePanel.lua:
--   * the loot system and the rule in force are the raid's active core's, and with no core the guild's:
--     the core's own rule, else its own loot system, else the guild's rule, else the guild's system;
--   * a core that chose nothing follows the guild, and the `lootMethod` of before changes nothing;
--   * two cores with two systems: each one's raid announces, orders and charges by its own, on its own
--     points and its own counters, and what the loot system shows follows the active core;
--   * an item keeps the rule it was announced under when another core becomes the raid's;
--   * a core's choice travels between officers with the core: the newest stamp wins, and a system or a
--     rule this client cannot read is refused whole;
--   * the answers' editor changes a core's rule and leaves the guild's alone;
--   * the core's Config tab and the editor's window draw.
--
--   luajit -e 'ADDON="."' tools/loot-cores.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. tostring(what) .. "\n")
    os.exit(1)
  end
end

-- ── A client: frames that take any call, a raid, a clock ────────────
local widgets, buttons = {}, {}
local function widget(fields)
  local w = fields or {}
  w.scripts = {}
  return setmetatable(w, { __index = function(_, k)
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    if k == "SetText" then return function(self, t) self.text = t end end
    if k == "GetText" then return function(self) return self.text or "" end end
    if k == "GetWidth" or k == "GetHeight" then return function() return 80 end end
    if k == "Hide" then return function(self) self.hidden = true end end
    if k == "Show" then return function(self) self.hidden = false end end
    if k == "IsShown" then return function(self) return not self.hidden end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return widget() end end
    if k == "GetChildren" or k == "GetRegions" then return function() return end end
    if type(k) == "string" and k:find("^%u") then return function() end end
    return nil
  end })
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
format, strlower, tinsert = string.format, string.lower, table.insert
function CreateFrame(kind) local w = widget({ kind = kind }); widgets[#widgets + 1] = w; return w end
UIParent, GameTooltip, UISpecialFrames = widget(), widget(), {}
RAID_CLASS_COLORS = {}
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetInstanceInfo() return "Karazhan", "raid", 9, "", 10, 0, false, 532 end
function GetRealmName() return "Realm" end
local NOW = 1791000000
function GetServerTime() return NOW end
function GetTime() return 100 end
time, date = os.time, os.date
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Officer", 1 end
function GetNumGuildMembers() return 0 end
function IsInRaid() return true end
function IsInGroup() return true end
function SendChatMessage() end
function GetLootMethod() return "master", 0 end
local raid = { "Lead", "Ana", "Bo", "Cy" }
function GetNumGroupMembers() return #raid end
function UnitClass() return "Mage", "MAGE" end
function UnitName(unit)
  if unit == "player" then return "Lead" end
  local i = tonumber(tostring(unit):match("^raid(%d+)$"))
  return i and raid[i] or nil
end
function UnitExists(unit) return UnitName(unit) ~= nil end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end,
  NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs, SlashCmdList = {}, {}
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Modules/CoreManager.lua")
dofile(ADDON .. "/Modules/RaidTracker.lua")
dofile(ADDON .. "/Modules/Points.lua")
dofile(ADDON .. "/Modules/LootRule.lua")
dofile(ADDON .. "/Modules/LootMaster.lua")
GuildOS.db = { settings = { lootSystem = "rolls" }, members = {}, altLinks = {}, cores = {}, lootHistory = {},
  lootMaster = { awardHistory = {} }, points = {},
  raidTracker = { sessions = {}, attendance = {}, deletedSessions = {}, currentGroupTag = "" } }
local LM, LR, P, CM, RT = GuildOS.LootMaster, GuildOS.LootRule, GuildOS.Points, GuildOS.CoreManager, GuildOS.RaidTracker
local officer = true
GuildOS.IsOfficer = function() return officer end
local officers = { ["Off-Realm"] = true }
GuildOS.IsOfficerByName = function(_, name) return officers[name] == true end
function GuildOS:ApplyFont() end
-- What the officers' sync carries, and the handlers it would call.
local published, handlers = {}, {}
GuildOS.SyncService = {
  On = function(_, dom, fn) handlers[dom] = fn end,
  ShouldApply = function() return true end, SetRevision = function() end, NextRevision = function() return 1 end,
  Publish = function(_, dom, act, data, opts)
    published[#published + 1] = { dom = dom, act = act, data = data, rev = opts and opts.rev }
  end,
}
P:Initialize()
CM:InitSync()
local function K(name) return GuildOS:GetPlayerKey(name) end

local said, sent, printed = {}, {}, {}
LM.SafeSendAddon = function(_, _, payload) sent[#sent + 1] = payload end
LM.SendEcho = function() end
LM.SafeSendChat = function(_, msg) said[#said + 1] = msg end
LM.SafeSendChatAuto = function(_, msg) said[#said + 1] = msg end
LM.IsMasterLooter = function() return true end
LM.GetPlayerContext = function() return { att25 = 100, recvThisLockout = 0 } end
LM.ShowRollFrame = function() end
LM.StopListeningForRolls = function() end
function GuildOS:Print(msg) printed[#printed + 1] = msg end
local shown = 0
function GuildOS:UpdateLootSystemUI() shown = shown + 1 end
local function quiet() said, sent, printed, published = {}, {}, {}, {} end
local function all(list) return table.concat(list, "\n") end
local function activate(name) RT:SetGroupTag(name) end

local LINK = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r"

-- ── 1. A core that chose nothing follows the guild ──────────────────
check(CM:Create("Alpha") and CM:Create("Beta") and CM:Create("Gamma"), "three cores")
-- What a core kept from the selector of before, which nothing ever read.
GuildOS.db.cores.Alpha.lootMaster.lootMethod = "dkp"
GuildOS.db.cores.Beta.lootMaster.lootMethod = "tmb"
for _, name in ipairs({ "", "Alpha", "Beta", "Gamma" }) do
  activate(name)
  check(GuildOS:GetLootSystem() == "rolls" and LR:Active().model == "rolls" and not GuildOS:LootSystemUsesPoints(),
    "with no choice of its own, " .. (name == "" and "no core" or name) .. " follows the guild: the loot method of before is not read")
end
check(CM:GetLootConfig("Alpha").lootMethod == nil and CM:GetLootSystem("Alpha") == nil, "and it is not carried over as a choice")
GuildOS.db.settings.lootSystem = "wishlist"
activate("Alpha")
check(GuildOS:GetLootSystem() == "wishlist" and LR:Active().model == "wishlist", "the guild changes, and a core that follows it does too")
GuildOS.db.settings.lootSystem = "rolls"

-- ── 2. A core's own loot system ─────────────────────────────────────
quiet()
check(GuildOS:SetLootSystem("dkp", "Alpha") == true and GuildOS:SetLootSystem("plus1", "Beta") == true, "two cores pick two systems")
check(#published >= 2 and published[1].dom == "core.roster" and published[1].act == "loot"
  and published[1].data.coreName == "Alpha" and published[1].data.sys == "dkp" and published[1].data.rule == false
  and published[1].rev == NOW and published[1].data.members == nil,
  "each choice is told to the officers with the core, stamped, under an action a client from before ignores")
activate("Alpha")
check(GuildOS:GetLootSystem() == "dkp" and LR:Active().model == "dkp" and LR:Active().order[2].k == "points",
  "Alpha's raid runs DKP")
check(GuildOS:LootSystemUsesPoints() and GuildOS:LootSystemShowsDKP() and not GuildOS:LootSystemShowsWishlist(),
  "and shows the points")
activate("Beta")
check(GuildOS:GetLootSystem() == "plus1" and LR:Active().model == "plus1" and not GuildOS:LootSystemShowsDKP(),
  "Beta's raid runs +1, and shows no points")
activate("Gamma")
check(GuildOS:GetLootSystem() == "rolls", "Gamma still follows the guild")
activate("")
check(GuildOS:GetLootSystem() == "rolls" and LR:Active().model == "rolls", "and with no core active it is the guild's")
check(GuildOS:GetLootSystem("") == "rolls" and GuildOS:GetLootSystem("Alpha") == "dkp" and GuildOS:GetLootSystem("Beta") == "plus1",
  "asked by name, each answers for itself whatever core is active")
check(GuildOS.db.settings.lootSystem == "rolls", "the guild's own choice was never touched")
check(GuildOS:SetLootSystem("auction", "Alpha") == false and GuildOS:GetLootSystem("Alpha") == "dkp", "a system this client does not offer is not saved")
check(GuildOS:SetLootSystem("dkp", "Nobody") == false and GuildOS.db.cores.Nobody == nil, "nor one for a core that does not exist, which is not made")
officer = false
check(GuildOS:SetLootSystem("rolls", "Alpha") == false and GuildOS:GetLootSystem("Alpha") == "dkp", "and only an officer picks")
officer = true

-- What the loot system shows follows the core that becomes the raid's.
shown = 0
activate("Alpha")
check(shown == 1, "a core with another system becoming active draws the loot system's tabs again")
activate("Alpha")
check(shown == 1, "the same system again draws nothing")
GuildOS.Wishlist = {}
check(GuildOS:SetLootSystem("wishlist", "Gamma") == true, "Gamma picks the wishlist")
activate("Gamma")
check(GuildOS:LootSystemShowsWishlist() and not GuildOS:LootSystemShowsDKP(), "Gamma's raid shows the wishlist")
activate("Alpha")
check(not GuildOS:LootSystemShowsWishlist() and GuildOS:LootSystemShowsDKP(), "Alpha's the points")
GuildOS.Wishlist = nil
check(GuildOS:SetLootSystem(nil, "Gamma") == true and CM:GetLootSystem("Gamma") == nil, "Follow the guild takes a core's choice back")

-- "External" for one core silences the loot master for that core's raid only.
check(GuildOS:SetLootSystem("external", "Gamma") == true, "Gamma hands its loot to another addon")
activate("Gamma")
check(not GuildOS:LootSystemActive() and not LM:IsModuleEnabled(), "in Gamma's raid the loot master is off")
activate("Alpha")
check(GuildOS:LootSystemActive() and LM:IsModuleEnabled(), "and on again in Alpha's")
GuildOS:SetLootSystem(nil, "Gamma")

-- EPGP for one core puts that core's points in EPGP, and nobody else's.
check(GuildOS:SetLootSystem("epgp", "Gamma") == true and P:GetMode("Gamma") == "epgp" and P:GetMode("Alpha") == "dkp"
  and P:GetMode("") == "dkp", "a core's EPGP moves its own pool only")
GuildOS:SetLootSystem(nil, "Gamma")

-- ── 3. The order of the four ────────────────────────────────────────
local guildRule = { v = 1, model = "custom", order = { { k = "response" }, { k = "roll" } } }
local coreRule = { v = 1, model = "custom", order = { { k = "response" }, { k = "wishlist" }, { k = "roll" } } }
check(LR:Set(guildRule) == true, "the guild keeps a rule of its own")
check(LR:For("Gamma") == guildRule and LR:For("") == guildRule, "a core with no choice follows the guild's rule")
check(LR:For("Alpha").model == "dkp", "a core's own loot system comes before the guild's rule")
check(LR:Set(coreRule, "Alpha") == true and LR:For("Alpha") == coreRule, "and a core's own rule before its own system")
check(LR:For("") == guildRule and LR:For("Beta").model == "plus1", "which is nobody else's")
check(GuildOS:GetLootSystem("Alpha") == "dkp", "its loot system stays what it chose")
activate("Alpha")
check(LR:Active() == coreRule, "the active core's rule is the one in force")
GuildOS.db.cores.Alpha.lootMaster.rule = { v = 1, order = { { k = "nonsense" } } }
check(LR:For("Alpha").model == "dkp", "a kept rule this client cannot read is passed over: the core's system stays in force")
GuildOS.db.cores.Alpha.lootMaster.rule = coreRule
local ok, why = LR:Set({ v = 1, order = {} }, "Alpha")
check(ok == false and why and LR:For("Alpha") == coreRule, "a rule that is not one is not saved on a core")
check(LR:Set(coreRule, "Nobody") == false and GuildOS.db.cores.Nobody == nil, "nor a rule for a core that does not exist")
officer = false
check(LR:Set(nil, "Alpha") == false and LR:For("Alpha") == coreRule, "and only an officer saves a core's rule")
officer = true
check(LR:IsCustom("Alpha") and not LR:IsCustom("Beta") and LR:IsCustom(), "who keeps a rule of their own is known by name")
check(LR:Set(nil, "Alpha") == true and LR:For("Alpha").model == "dkp", "nil goes back to the core's loot system")
check(LR:Set(coreRule, "Alpha") == true and GuildOS:SetLootSystem("dkp", "Alpha") == true and LR:For("Alpha").model == "dkp",
  "picking a loot system for the core puts its ready-made rule in force again")
check(LR:Set(nil) == true and LR:For("Gamma").model == "rolls", "and with no rule anywhere, the guild's loot system")

-- ── 4. Two raids, each by its own rule, points and counters ─────────
local alphaPool, betaPool = CM:GetPointsDB("Alpha"), CM:GetPointsDB("Beta")
alphaPool.config.itemCost = 20
local function announce()
  quiet()
  LM.lootWindowOpen = false
  LM:AnnounceItem(LINK, nil)
end
local function row(name) return LM.rolls[K(name)] end

activate("Alpha")
P:Award(K("Ana"), 50, "seed")
P:Award(K("Bo"), 80, "seed")
check(P:Get(K("Bo")) == 80 and betaPool.standings[K("Bo")] == nil, "Alpha's points are Alpha's")
announce()
check(said[1]:find("[DKP]", 1, true), "Alpha's raid announces a DKP roll: " .. tostring(said[1]))
LM:RegisterRoll("Ana", "MS", 99)
LM:RegisterRoll("Bo", "MS", 3)
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "Bo", "and orders by points: 80 before 50, whatever the roll")
LM:AwardLoot("Bo")
check(P:Get(K("Bo")) == 60 and all(said):find("charged 20 points", 1, true), "and charges the winner Alpha's price, on Alpha's pool")
check(alphaPool.accounts == nil, "DKP keeps no +1")

activate("Beta")
check(P:Get(K("Bo")) == 0, "in Beta's raid nobody holds Alpha's points")
announce()
check(said[1]:find("[ROLL]", 1, true) and not said[1]:find("[DKP]", 1, true), "Beta's raid announces a roll: " .. tostring(said[1]))
LM:RegisterRoll("Ana", "MS", 10)
LM:RegisterRoll("Bo", "MS", 90)
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "Bo", "with nobody at +1 the roll decides")
LM:AwardLoot("Bo")
check(P:Counter("plus1", K("Bo")) == 1 and not all(said):find("charged", 1, true), "the winner is at +1, and pays nothing")
check(betaPool.accounts.plus1 and alphaPool.accounts == nil, "the +1 is kept in Beta's pool")
announce()
LM:RegisterRoll("Ana", "MS", 10)
LM:RegisterRoll("Bo", "MS", 90)
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "Ana" and LM.activeLoot.decidedBy == "account", "so the next item goes to whoever has none")
LM:CancelRolling()
activate("Alpha")
check(P:Counter("plus1", K("Bo")) == 0, "and Alpha's raid knows nothing of Beta's +1")
-- A counter's entry from another officer lands in the pool of the core it names.
handlers.points({ act = "cdelta", data = { entries = { { op = "X-1", key = K("Cy"), core = "Beta", acct = "plus1",
  rs = "night", per = NOW, delta = 1 } } } })
check(betaPool.accounts.plus1.v[K("Cy")] == 1 and alphaPool.accounts == nil, "another officer's +1 for Beta lands in Beta's pool")

-- ── 5. An item keeps the rule it was announced under ────────────────
activate("Alpha")
announce()
local frozen = LM.activeLoot.rule
check(frozen and frozen.model == "dkp" and LM.activeLoot.system == "dkp", "an announced item holds its rule and its loot system")
activate("Beta")
check(LR:Active().model == "plus1" and LM:Rule() == frozen and LM:System() == "dkp",
  "another core becomes the raid's: the roll in progress keeps the rule it was announced with")
LM.rolls = {
  [K("Ana")] = { name = "Ana", rollType = "MS", roll = 99, dkp = 50, accts = { plus1 = 0 } },
  [K("Bo")] = { name = "Bo", rollType = "MS", roll = 3, dkp = 60, accts = { plus1 = 1 } },
}
LM:EndRolling(true)
check(LM.activeLoot.sortedResults[1].name == "Bo", "and ends by it: points decide, not Beta's +1")
check(LM:AnswerLabel("MS") == "MS" and LM:RollTime() == 30, "its answers and its time are that rule's")
check(LR:Set({ v = 1, order = { { k = "roll" } } }, "Alpha") == true and LM:Rule() == frozen,
  "nor does an officer saving another rule change it")
LR:Set(nil, "Alpha")
LM:CancelRolling()
announce()
check(LM.activeLoot.rule.model == "plus1" and said[1]:find("[ROLL]", 1, true), "the next item is announced under the new core's rule")
LM:CancelRolling()

-- ── 6. A core's choice between officers ─────────────────────────────
local function hear(data, rev, from, act)
  handlers["core.roster"]({ act = act or "loot", data = data, rev = rev }, from or "Off-Realm")
end
local stampBefore = GuildOS.db.cores.Beta.lootMaster.lootAt
hear({ coreName = "Beta", sys = "dkpbid", rule = false }, NOW + 10)
check(CM:GetLootSystem("Beta") == "dkpbid" and GuildOS.db.cores.Beta.lootMaster.lootAt == NOW + 10, "an officer's newer choice for a core is taken")
hear({ coreName = "Beta", sys = "rolls", rule = false }, stampBefore)
check(CM:GetLootSystem("Beta") == "dkpbid", "an older one is not")
hear({ coreName = "Beta", sys = "rolls", rule = false }, NOW + 10)
check(CM:GetLootSystem("Beta") == "dkpbid", "nor one of the same stamp")
hear({ coreName = "Beta", sys = "rolls", rule = false }, NOW + 20, "Ana-Realm")
check(CM:GetLootSystem("Beta") == "dkpbid", "nor one from somebody who is no officer")
hear({ coreName = "Beta", sys = "auction", rule = false }, NOW + 20)
check(CM:GetLootSystem("Beta") == "dkpbid", "a loot system this client does not offer is refused")
hear({ coreName = "Beta", sys = "rolls", rule = { v = 1, order = { { k = "parse" } } } }, NOW + 20)
check(CM:GetLootSystem("Beta") == "dkpbid" and CM:GetLootRule("Beta") == nil,
  "a rule this client cannot read is refused whole: neither it nor the system that came with it")
hear({ coreName = "Beta", sys = "rolls", rule = "roll" }, NOW + 20)
hear({ coreName = "Beta", sys = 7, rule = false }, NOW + 20)
hear({ coreName = "Beta", sys = "rolls", rule = false }, "soon")
hear({ coreName = "Beta", sys = "rolls", rule = false }, nil)
hear({ coreName = string.rep("x", 200), sys = "rolls", rule = false }, NOW + 20)
hear("Beta", NOW + 20)
check(CM:GetLootSystem("Beta") == "dkpbid", "nor anything that is not a choice")
hear({ coreName = "Delta", sys = "dkp", rule = false }, NOW + 20)
check(GuildOS.db.cores.Delta == nil, "a choice for a core this client does not have makes no core")
hear({ coreName = "Beta", sys = false, rule = coreRule }, NOW + 30)
check(CM:GetLootSystem("Beta") == nil and LR:For("Beta").order[2].k == "wishlist", "a rule that reads whole is taken, with following the guild")
hear({ coreName = "Beta", sys = "plus1", rule = false }, NOW + 9999999)
check(GuildOS.db.cores.Beta.lootMaster.lootAt == NOW + 300, "a stamp from a clock far ahead is held to this one's, so a later choice still wins")
activate("Beta")
shown = 0
NOW = NOW + 1000
hear({ coreName = "Beta", sys = "dkp", rule = false }, NOW)
check(shown == 1 and GuildOS:LootSystemShowsDKP(), "and a choice heard for the active core changes what the loot system shows")
-- The officers' regular sync says every core's choice again; a core that never chose says nothing.
quiet()
CM:PublishAllLoot()
local toldBeta, toldGamma
for _, m in ipairs(published) do
  if m.act == "loot" and m.data.coreName == "Beta" then toldBeta = m end
  if m.act == "loot" and m.data.coreName == "Gamma" then toldGamma = m end
end
check(toldBeta and toldBeta.data.sys == "dkp" and toldBeta.rev == NOW, "the regular sync repeats a core's choice with its own stamp")
check(toldGamma and toldGamma.data.sys == false, "and a core that went back to following the guild says so")
officer = false
quiet()
CM:PublishAllLoot()
check(#published == 0, "somebody who is no officer tells nothing")
officer = true
-- A roster update of always still lands.
hear({ coreName = "Beta", members = { [K("Ana")] = { name = "Ana" } } }, nil, "Off-Realm", "update")
check(GuildOS.db.cores.Beta.members[K("Ana")] ~= nil and CM:GetLootSystem("Beta") == "dkp", "the core's roster still syncs beside it")
GuildOS:SetLootSystem("plus1", "Beta")

-- ── 7. The answers' editor on a core's rule ─────────────────────────
activate("")
check(LR:SetResponseField(2, "ask", "none", "Alpha") == true, "an officer changes how Alpha's raiders answer")
check(LR:IsCustom("Alpha") and LR:For("Alpha").responses[2].ask == "none" and LR:For("Alpha").model == "custom", "Alpha keeps the changed rule")
check(not LR:IsCustom() and LR:For("").responses[2].ask == "roll" and LR:For("Beta").model == "plus1", "and the guild's and Beta's are as they were")
check(LR:AddResponse("TMOG", "Transmog", "Alpha") == true and #LR:For("Alpha").responses == 3 and #LR:For("").responses == 2,
  "an answer added to a core is that core's")
check(LR:SetTime(60, "Alpha") == true and LR:For("Alpha").time == 60 and LR:For("").time == nil, "and so is its time")
check(LR:SetCounterReset("plus1", "lockout", "Beta") == true and LR:Counters(LR:For("Beta"))[1].reset == "lockout", "Beta's counter resets per lockout")
check(LR:MoveResponse(1, 1, "Alpha") == true and LR:RemoveResponse(3, "Alpha") == true and LR:SetBidField("min", 5, "Alpha") == true
  and LR:SetPrice("table", "Alpha") == true, "every change takes the core's name")
check(LR:SetResponseField(1, "ask", "bid") == true and LR:IsCustom() and LR:For("Gamma").responses[1].ask == "bid",
  "and without one it is the guild's rule, which a core with no choice follows")
check(LR:For("Alpha").responses[1].key == "OS", "while Alpha keeps its own")
LR:Set(nil)
LR:Set(nil, "Alpha")
LR:Set(nil, "Beta")

-- ── 8. The windows draw, and their buttons reach the modules ────────
GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })
GuildOS.UI = setmetatable({
  CreateButton = function(_, _, text)
    local b = widget({ text = tostring(text), label = widget() })
    buttons[#buttons + 1] = b
    return b
  end,
  CreateCheckbox = function() return widget({ checkbox = widget() }) end,
  CreateScrollFrame = function() return widget(), widget() end,
  AttachSaveButton = function(_, box, onSave)
    box.saveButton = widget({ text = "Save" })
    box.save = function(text) box.text = text; onSave(box) end
    return box.saveButton
  end,
}, { __index = function() return function() return widget() end end })
local function button(text)
  for i = #buttons, 1, -1 do
    if buttons[i].text == text then return buttons[i] end
  end
end
local function click(text)
  local b = button(text)
  check(b and b.scripts.OnClick, "there is a button " .. text)
  b.scripts.OnClick(b)
end
dofile(ADDON .. "/UI/FeaturePanels.lua")
GuildOS.CreateRolePicker = function() return widget() end
GuildOS.ShowPointsFrame = function() end

-- The guild's loot settings show the guild's own choice, whatever core is active.
activate("Alpha")
local content = widget()
widgets, buttons = {}, {}
local drew, problem = pcall(GuildOS.RefreshSettingsPanel, GuildOS, content, "loot")
check(drew, "the loot settings draw with a core active (" .. tostring(problem) .. ")")
click("Roll")
check(LR:IsCustom() and not LR:IsCustom("Alpha") and LR:For("").responses[2].ask == "bid",
  "and their editor changes the guild's rule, not the active core's")
LR:Set(nil)

-- The same editor, in a window, on one core's rule.
widgets, buttons = {}, {}
drew, problem = pcall(GuildOS.ShowLootRuleEditor, GuildOS, "Beta")
check(drew, "the editor's window draws for a core (" .. tostring(problem) .. ")")
check(button("Add answer") and button("+1") and button("Each raid night"), "with that core's answers and its counter")
click("Each raid night")
check(LR:Counters(LR:For("Beta"))[1].reset == "night" and LR:IsCustom("Beta") and not LR:IsCustom(), "a click there changes that core's rule only")
check(button("Back to the loot system's rule"), "and offers the way back")
click("Back to the loot system's rule")
check(not LR:IsCustom("Beta"), "which is a click")

-- The core's Config tab: every loot system this client offers, and Follow the guild.
dofile(ADDON .. "/UI/CorePanel.lua")
widgets, buttons = {}, {}
local coresPanel = widget()
drew, problem = pcall(GuildOS.CreateCoresPanel, GuildOS, coresPanel)
check(drew, "the cores panel draws (" .. tostring(problem) .. ")")
coresPanel.scripts.OnShow(coresPanel)
for _, w in ipairs(widgets) do
  if w.coreName == "Gamma" and w.scripts.OnClick then w.scripts.OnClick(w) break end
end
click("Config")
check(button("Follow the guild"), "the Config tab offers Follow the guild")
for _, sys in ipairs(GuildOS:LootSystemsHere()) do
  check(button(GuildOS:LootSystemLabel(sys)), "and " .. sys.key)
end
check(not button("Roll") and not button("Import") and not button("Clear List"), "the selector of before and its TMB paste are gone")
click("DKP / Points")
check(CM:GetLootSystem("Gamma") == "dkp", "a click on a system is that core's choice")
check(button("Edit this core's loot rule"), "and its rule opens from there")
click("Follow the guild")
check(CM:GetLootSystem("Gamma") == nil, "Follow the guild is a click too")
local src = assert(io.open(ADDON .. "/UI/CorePanel.lua", "rb")):read("*a")
check(not src:find("lootMethod", 1, true) and not src:find("METHOD_CYCLE", 1, true), "nothing in the panel saves the loot method of before")

print(("loot-cores: %d checks passed"):format(checks))
