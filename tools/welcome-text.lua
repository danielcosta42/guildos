-- The welcome that stopped after an officer edited its text (issue #270), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Modules/CommSystem.lua and
-- Modules/RecruitmentSystem.lua.
--
-- The text went out raw through SendChatMessage, and the game refuses a "|" that is not one of its
-- own codes ("Welcome! | have fun") with a Lua error nobody saw: the welcome simply never came.
-- Saving now says why a text cannot be sent, and a send that fails says so instead of vanishing.
--
--   luajit -e 'ADDON="."' tools/welcome-text.lua
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
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
function UnitFullName() return "Bishop", "Who" end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
function GetRealmName() return "Realm" end
C_Timer = { After = function() end, NewTicker = function() end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
function IsInGuild() return true end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
function GetGuildInfo() return "Guild", "Officer", 1 end
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
local R = GuildOS.Recruitment

-- ── What the game refuses ────────────────────────────────────────────────
check(R.ChatTextProblem("Welcome to the guild! Have fun") == nil, "an ordinary text is fine")
check(R.ChatTextProblem("Welcome! | have fun") ~= nil, "a lone | is refused, the likeliest cause")
check(R.ChatTextProblem("Welcome to Ordem|") ~= nil, "at the end too")
check(R.ChatTextProblem(string.rep("a", 255)) == nil, "255 characters go")
check(R.ChatTextProblem(string.rep("a", 256)) ~= nil, "256 do not")
check(R.ChatTextProblem("line one\nline two") ~= nil, "a chat message has one line")
check(R.ChatTextProblem("") ~= nil and R.ChatTextProblem(nil) ~= nil, "an empty text is nothing to send")
check(R.ChatTextProblem("Bem-vindo à guilda! Divirta-se") == nil, "accents are not a problem")

-- ── Sending ──────────────────────────────────────────────────────────────
local printed, sent = {}, {}
function GuildOS:Print(m) printed[#printed + 1] = m end
function SendChatMessage(msg, chan) sent[#sent + 1] = { msg = msg, chan = chan } end
R.ShowWelcomePopup = function() end

GuildOS.db = { recruitment = { welcomeMessage = "Welcome! | have fun" } }
R:QueueWelcome("Ragged Angel")
check(R:SendPendingWelcome() == false and #sent == 0, "a text the game would refuse is not sent")
check(printed[#printed] and printed[#printed]:find("|", 1, true) ~= nil, "and the officer is told why")
check(#R._pendingWelcomes == 1, "whoever was waiting is still waiting, for the fixed text")

GuildOS.db.recruitment.welcomeMessage = "Welcome to the guild!"
check(R:SendPendingWelcome() == true and #sent == 1 and sent[1].chan == "GUILD", "a good text goes to guild chat")

function SendChatMessage() error("Invalid escape code in chat message") end
R:QueueWelcome("Ves Pin")
local ok, res = pcall(R.SendPendingWelcome, R)
check(ok, "a send the game raises on does not raise out of the click")
check(res == false and printed[#printed]:find("Invalid escape code", 1, true) ~= nil, "it says the game's own reason")

print("welcome-text: " .. checks .. " checks passed")
