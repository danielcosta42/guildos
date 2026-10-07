-- Settings that only a slash command could change get a screen (issue #59), run against the
-- real Core/Core.lua, Core/Compat.lua, Modules/RecruitmentSystem.lua and Modules/Mentions.lua.
--
-- The Recruitment screen and the slash commands now write through the same functions, so
-- they hold the same rules: a keyword is one word, a level is within the game's cap, a class
-- is one the game has (the command used to store typos), a channel is listed once.
--
--   luajit -e 'ADDON="."' tools/command-settings.lua
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
function GetServerTime() return 1790000000 end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
C_Timer = { After = function() end, NewTicker = function() end }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
dofile(ADDON .. "/Modules/Mentions.lua")
local R, M = GuildOS.Recruitment, GuildOS.Mentions
local printed = {}
function GuildOS:Print(msg) printed[#printed + 1] = tostring(msg) end

-- ── Auto-invite rules ───────────────────────────────────────────────────
local cfg = { keyword = "ginv", minLevel = 0, classes = {}, whoFallback = "skip" }
check(R:SetAutoInviteKeyword(cfg, "  Join please") == "join" and cfg.keyword == "join", "a keyword is its first word, lowercase")
check(R:SetAutoInviteKeyword(cfg, "   ") == nil and cfg.keyword == "join", "an empty keyword changes nothing")
check(R:SetAutoInviteKeyword(cfg, string.rep("x", 21)) == nil and cfg.keyword == "join", "nor does an overlong one")
check(R:SetAutoInviteMinLevel(cfg, 99) == 70 and cfg.minLevel == 70, "a level stops at the game's cap")
check(R:SetAutoInviteMinLevel(cfg, -3) == 0, "and starts at 0, which means any level")
check(R:SetAutoInviteMinLevel(cfg, "abc") == nil and cfg.minLevel == 0, "a non-number changes nothing")
check(R:SetAutoInviteMinLevel(cfg, 55.7) == 55, "a level is a whole number")
check(R:SetAutoInviteClass(cfg, "mage", true) and cfg.classes.MAGE == true, "a class is turned on by its token, any case")
check(not R:SetAutoInviteClass(cfg, "MAEG", true) and cfg.classes.MAEG == nil, "a class the game does not have is refused")
check(R:SetAutoInviteClass(cfg, "MAGE", false) and next(cfg.classes) == nil, "and a class is turned off")
check(R:SetAutoInviteFallback(cfg, "invite") and cfg.whoFallback == "invite", "an unconfirmed player can be invited")
check(not R:SetAutoInviteFallback(cfg, "maybe") and cfg.whoFallback == "invite", "or skipped, and nothing else")
local stored = { MAEG = true, PRIEST = true }
R:_DropUnknownClasses(stored)
check(stored.MAEG == nil and stored.PRIEST == true, "a typo the old command stored is dropped, a real class kept")

-- ── Channels: once each, whatever the case ──────────────────────────────
local chans = {}
check(R:AddChannel(chans, " MyRecruitChan ") and chans[1] == "MyRecruitChan", "a custom channel is added, trimmed")
check(not R:AddChannel(chans, "myrecruitchan") and #chans == 1, "and listed once")
check(not R:AddChannel(chans, "  ") and #chans == 1, "an empty name is no channel")
check(R:RemoveChannel(chans, "MYRECRUITCHAN") and #chans == 0, "a channel is removed whatever the case")
check(not R:RemoveChannel(chans, "Nope"), "removing one that is not there says so")

-- ── The commands go through the same rules ──────────────────────────────
GuildOS.db = {}
printed = {}
check(pcall(R.HandleCommand, R, { "status" }), "/gos recruit with no recruitment settings does not raise")
check(printed[1] and printed[1]:find("officers"), "and says who has them")
GuildOS.db.recruitment = { channels = {}, autoInvite = { keyword = "ginv", minLevel = 0, classes = {}, whoFallback = "skip" } }
local ai = GuildOS.db.recruitment.autoInvite
R:HandleAutoInviteCommand({ "class", "add", "maeg" })
check(next(ai.classes) == nil, "/gos autoinvite class add with a typo stores nothing")
R:HandleAutoInviteCommand({ "class", "add", "priest" })
check(ai.classes.PRIEST == true, "/gos autoinvite class add with a real class stores it")
R:HandleAutoInviteCommand({ "minlevel", "99" })
check(ai.minLevel == 70, "/gos autoinvite minlevel stops at the cap")
R:HandleAutoInviteCommand({ "keyword", "Join" })
check(ai.keyword == "join", "/gos autoinvite keyword")
R:HandleAutoInviteCommand({ "fallback", "invite" })
check(ai.whoFallback == "invite", "/gos autoinvite fallback")
R:HandleCommand({ "channel", "add", "Trade" })
R:HandleCommand({ "channel", "add", "trade" })
check(#GuildOS.db.recruitment.channels == 1, "/gos recruit channel add lists a channel once")

-- ── A typo stored before is gone once recruitment starts ─────────────────
function GetGuildInfo() return "Guild", "Officer", 1 end
function IsInGuild() return true end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() return nil end
function CanGuildInvite() return true end
GuildOS.db = { recruitment = { autoInvite = { classes = { MAEG = true, MAGE = true } } } }
R:Initialize()
check(GuildOS.db.recruitment.autoInvite.classes.MAEG == nil and GuildOS.db.recruitment.autoInvite.classes.MAGE,
      "Initialize drops the typo and keeps the class")

-- ── A chip stays inside its slot ────────────────────────────────────────
check(GuildOS:ChipLabel("Trade") == "Trade  x", "a short name is shown whole")
check(GuildOS:ChipLabel("need  heals") == "need heals  x", "text only tidied is not marked as cut")
check(GuildOS:ChipLabel("a very long watch phrase") == "a very long wa..  x", "a long one is cut, and says so")
check(GuildOS:ChipLabel("abcdefghijklmçao") == "abcdefghijklm..  x", "and never inside a character")

-- ── Mentions: a watch-word comes off the list the way it went on ─────────
local words = {}
M:_AddWatchWord(words, "Need Heals")
check(M:_RemoveWatchWord(words, "  need heals ") == 1 and #words == 0, "a watch-word is removed whatever the case and spaces")
check(M:_RemoveWatchWord(words, "nope") == 0, "and removing one that is not there removes nothing")

print(("command-settings: %d checks passed"):format(checks))
