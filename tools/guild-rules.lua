-- The guild's rules in the game (issue #407), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/CommSystem.lua, Modules/RecruitmentSystem.lua, Modules/Discipline.lua and
-- Modules/GuildRules.lua under a stubbed client.
--
-- Officers write a numbered list, capped in count and bytes, cleaned of the game's codes; every member
-- keeps the newest (stamp); /gos rules shows it, or says the guild has not written any; the welcome may end
-- with "type /gos rules" within the game's 255 bytes; a warning's template names a rule with {rule}; the
-- companion export carries `rules`.
--
--   luajit -e 'ADDON="."' tools/guild-rules.lua
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
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.5", "60000", "", 20505 end
function GetRealmName() return "Realm" end
function GetLocale() return "enUS" end
function UnitFullName() return "Arthas", "Realm" end
C_Timer = { After = function() end, NewTicker = function() end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function IsInGuild() return true end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function GetGuildInfo() return "Guild", "Officer", 1 end
local NOW = 1790000000
function GetServerTime() return NOW end
function GetTime() return NOW end
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
dofile(ADDON .. "/Modules/Discipline.lua")
dofile(ADDON .. "/Modules/GuildRules.lua")
local R, D, GR = GuildOS.Recruitment, GuildOS.Discipline, GuildOS.GuildRules

local officer = true
function GuildOS:IsOfficer() return officer end
local printed = {}
function GuildOS:Print(m) printed[#printed + 1] = m end
local sent = {}
GuildOS.SyncService = {
  On = function() end,
  Publish = function(_, dom, act, data, opts) sent[#sent + 1] = { dom = dom, act = act, data = data, opts = opts } end,
}
GuildOS.db = { settings = {}, recruitment = { welcomeMessage = "Welcome to Ordem!" } }
GR:Initialize()

-- ── Cleaning and limits ─────────────────────────────────────────────────
local r = GR.CleanRule({ title = "  No |cffff0000gold|r selling ", text = "line one\nline two|r" })
check(r and r.title == "No cffff0000goldr selling" and r.text == "line one line twor", "the game's codes and line breaks go")
check(GR.CleanRule({ title = "  ", text = "x" }) == nil and GR.CleanRule("x") == nil, "a rule needs a title")
check(#GR.CleanRule({ title = string.rep("a", 99), text = string.rep("b", 999) }).title == GR.TITLE_MAX
      and #GR.CleanRule({ title = "a", text = string.rep("b", 999) }).text == GR.TEXT_MAX, "title and text cut at their limits")
check(#GR.CleanRule({ title = string.rep("\195\169", 40) }).title <= GR.TITLE_MAX
      and not GR.CleanRule({ title = string.rep("\195\169", 40) }).title:find("\195$"), "never a half letter")
local many = {}
for i = 1, 500 do many[i] = { title = "Rule " .. i, text = string.rep("x", 250) } end
local out = GR.ValidRules(many)
local bytes = 0
for _, x in ipairs(out) do bytes = bytes + #x.title + #x.text end
check(#out <= GR.RULES_MAX and bytes <= GR.TOTAL_MAX, "a list off the network is capped in count and in bytes")
check(GR.ValidRules(nil) == nil and #GR.ValidRules({ 1, "x", { title = "ok" } }) == 1, "what is not a rule is dropped")

-- ── Officers write; nobody else ─────────────────────────────────────────
check(not GR:HasRules() and GR:ForExport() == nil, "no rules yet, nothing to export")
GR:Show()
check(printed[#printed] == "The guild has not written its rules yet.", "/gos rules with none says so")
check(GR:Add("Be kind", "No insults in /g."), "an officer adds a rule")
check(GR:Add("No gold selling", ""), "and another")
check(GR:Add("Raid times", "Wed and Sun 20:00"), "and a third")
local s = GuildOS.db.settings
check(#sent == 3 and sent[3].dom == "guildcfg" and sent[3].act == "rules" and #sent[3].data.items == 3
      and sent[3].opts.rev == s.guildRulesAt, "each change goes to the guild, stamped")
check(select(2, GR:Add("", "x")) == "empty", "a rule without a title is refused")
check(GR:MoveUp(3) and GR:Get()[2].title == "Raid times", "moved up")
check(GR:Update(2, "Raid nights", "Wed and Sun") and GR:Get()[2].title == "Raid nights", "rewritten")
check(select(2, GR:Update(9, "x", "")) == "missing", "a rule that is not there")
check(GR:Remove(3) and #GR:Get() == 2, "removed")
printed = {}
GR:Show()
check(printed[1] == "The guild's rules:" and printed[2] == "  1. Be kind - No insults in /g." and printed[3] == "  2. Raid nights - Wed and Sun",
      "/gos rules lists them, numbered")
for i = 3, GR.RULES_MAX do GR:Add("Rule " .. i, "") end
check(select(2, GR:Add("One too many", "")) == "full", "at most 15")
officer = false
check(select(2, GR:Add("Member's rule", "")) == "officer" and not GR:Remove(1) and not GR:MoveUp(2), "a member only reads")
officer = true

-- ── Every member keeps the newest ───────────────────────────────────────
officer = false
local at = s.guildRulesAt
GR:OnConfigSync({ act = "rules", rev = at - 1, data = { items = { { title = "Old" } } } })
GR:OnConfigSync({ act = "rules", rev = at, data = { items = { { title = "Tie" } } } })
check(GR:Get()[1].title == "Be kind", "an older or tied stamp loses")
GR:OnConfigSync({ act = "rules", rev = at + 1, data = { items = { { title = "New |Hitem:1|h[x]|h", text = "t" } } } })
check(#GR:Get() == 1 and not GR:Get()[1].title:find("|", 1, true) and s.guildRulesAt == at + 1, "a member takes a newer list, cleaned")
GR:OnConfigSync({ act = "rules", rev = 0 / 0, data = { items = {} } })
GR:OnConfigSync({ act = "rules", rev = at + 2, data = { items = "nope" } })
check(#GR:Get() == 1, "NaN is no stamp; what is not a list is turned away")
GR:OnConfigSync({ act = "rules", rev = NOW + 86400, data = { items = {} } })
check(#GR:Get() == 0 and s.guildRulesAt <= NOW + 300, "an emptied list wins too; a stamp far ahead is held to five minutes")
sent = {}
GR:PublishConfig()
check(#sent == 0, "a member's client never publishes")
officer = true
GR:PublishConfig()
check(#sent == 1 and sent[1].act == "rules", "an officer's regular sync sends the list it holds")
NOW = NOW + 1000
GR:Add("Be kind", "")
GR:Add("No gold selling", "")

-- ── {rule} in a warning's template ──────────────────────────────────────
local ref = GR.RefText(2, GR:Rule(2))
check(ref == "rule 2: No gold selling", "a rule reads as its number and title")
check(D.Fill("{name}, you broke {rule}.", { name = "Thrall", rule = ref }) == "Thrall, you broke rule 2: No gold selling.",
      "{rule} names the rule")
check(D.Fill("{name}, you broke {rule}.", { name = "Thrall" }) == "Thrall, you broke the guild's rules.",
      "no rule named: the guild's rules")
check(#D.Fill(string.rep("x", 250) .. " {rule}", { rule = ref }) <= 255, "still cut at 255 bytes")

-- ── The welcome ─────────────────────────────────────────────────────────
local tail = " Type /gos rules to read the guild's rules."
check(R:WelcomeMessage() == "Welcome to Ordem!", "off by default: the welcome as today")
GuildOS.db.recruitment.welcomeRules = true
check(R:WelcomeMessage() == "Welcome to Ordem!" .. tail, "on, with rules: the invitation at the end")
check(R.ChatTextProblem(R:WelcomeMessage()) == nil, "and the game takes it")
local long = string.rep("w", 255 - #tail + 1)
check(R.WelcomeWithRules(long, true, true) == long, "too long for 255 bytes: the welcome alone")
check(#R.WelcomeWithRules(string.rep("w", 255 - #tail), true, true) == 255, "exactly 255 goes")
check(R.WelcomeWithRules("Hi", true, false) == "Hi" and R.WelcomeWithRules("", true, true) == "", "no rules, or no welcome: unchanged")

-- ── The companion export ────────────────────────────────────────────────
local ex = GR:ForExport()
check(ex and ex.at == s.guildRulesAt and #ex.items == 2 and ex.items[2].n == 2 and ex.items[2].title == "No gold selling"
      and ex.items[1].text == "", "the export's shape: { at, items = { { n, title, text } } }")
local src = io.open(ADDON .. "/Modules/CompanionExport.lua"):read("*a")
check(src:find('payload.rules = GuildOS.GuildRules and optional("rules", GuildOS.GuildRules.ForExport, GuildOS.GuildRules)', 1, true),
      "the export carries it, guarded")

-- ── The self-tests the client runs ──────────────────────────────────────
local registered = {}
GuildOS.SelfTest = { Register = function(_, name, fn) registered[#registered + 1] = { name = name, fn = fn } end }
GR:_RegisterTests()
check(#registered >= 3, "the self-tests register")
for _, t in ipairs(registered) do
  local ok, why = t.fn()
  check(ok, "selftest " .. t.name .. ": " .. tostring(why))
end
print(("guild-rules: %d checks passed"):format(checks))
