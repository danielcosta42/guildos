-- A member with the Recruitment module switched off (issue #79), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua and Modules/RecruitmentSystem.lua.
--
-- Switching the module off skips InitParticipation, but an officer's ad still arrives through
-- ApplyIncoming and started the popup ticker anyway, with a hint pointing at a tab the switch
-- had hidden; switched off while the popups ran, they kept coming. The ad is still kept and
-- relayed; the popups stay off. And an officer whose rank arrived late, already running the
-- member's popups, does not get the officer's on top of them.
--
--   luajit -e 'ADDON="."' tools/recruit-module-off.lua
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

local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = tostring(msg) end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  function f:Hide() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function IsInGuild() return true end
local myRank = 5
function GetGuildInfo() return "Guild", "Rank", myRank end
function CanGuildInvite() return false end
local ROSTER = { { "Officer", 0 }, { "Me", 5 } }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) local r = ROSTER[i]; if r then return r[1], "Rank", r[2] end end
function time() return 1000 end
local tickers, delayed = 0, {}
C_Timer = { After = function(_, fn) delayed[#delayed + 1] = fn end,
            NewTicker = function(period, fn)
              tickers = tickers + 1
              local t = { live = true, fn = fn, period = period }
              function t:Cancel() if self.live then self.live = false; tickers = tickers - 1 end end
              return t
            end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
ERR_GUILD_JOIN_S = "%s has joined the guild."
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
LibStub("GuildOS-LibSerialize").Serialize = function() return "serialized" end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
local R = GuildOS.Recruitment
local popups = 0
R.ShowSendPopup = function() popups = popups + 1 end
local relayed = {}
GuildOS.CommSystem = { SendMessage = function(_, t) relayed[#relayed + 1] = t end, MSG_TYPES = {} }

local AD = { enabled = true, message = "We are recruiting", channels = {}, interval = 120,
             updatedAt = 900, updatedBy = "Officer" }
local function member(modules)
  myRank = 5
  GuildOS.db = { settings = { modules = modules } }
  if R.memberTicker then R.memberTicker:Cancel() end
  R.memberTicker, R._autoCapReached, R._autoPopups = nil, nil, nil
  printed, relayed, popups = {}, {}, 0
end

-- ── 1. Module on: the officer's ad starts the popups, as it always did ───
member({})
check(not GuildOS:IsOfficer() and GuildOS:IsFeatureEnabled("recruitment"), "the stub is a member with the module on")
R:ApplyIncoming(AD, "Officer", "GUILD")
check(R:IsMemberRecruitActive() and tickers == 1, "with the module on, the officer's ad starts the popup ticker")
R:_AutoTick()
check(popups == 1, "and its tick shows a popup")

-- ── 2. Module off: the ad is kept and relayed, no popups, no hint ────────
member({ recruitment = false })
R:ApplyIncoming(AD, "Officer", "GUILD")
check(not R:IsMemberRecruitActive() and tickers == 0, "with the module off, the officer's ad starts no popups")
check(#printed == 0, "and no hint points at the tab the switch hid")
check(GuildOS.db.guildRecruitment and GuildOS.db.guildRecruitment.message == "We are recruiting",
  "the ad itself is kept, for when the module comes back on")
R:RespondToSync()
check(relayed[1] == "RI", "and it is still relayed to the guild")

-- ── 3. Switched off while the popups ran: the next tick stops them, quietly ──
member({})
R:ApplyIncoming(AD, "Officer", "GUILD")
check(R:IsMemberRecruitActive(), "the popups run while the module is on")
GuildOS.db.settings.modules.recruitment = false
printed = {}
R:_AutoTick()
check(popups == 0 and not R:IsMemberRecruitActive() and tickers == 0,
  "the first tick after switching it off shows nothing and stops the ticker")
check(#printed == 0, "without a word")

-- ── 4. An officer whose rank arrived late: one ticker, not two ──────────
member({})
myRank = nil                                     -- the rank not loaded yet: treated as a member
R:ApplyIncoming(AD, "Officer", "GUILD")
check(R:IsMemberRecruitActive() and tickers == 1, "before the rank, the member's popups run")
myRank = 0
GuildOS.db.recruitment = { enabled = true, message = "Officer ad", channels = { "LookingForGroup" }, interval = 120,
                          welcomeEnabled = false, welcomeMessage = "Hi" }
printed = {}
R:Initialize()
check(not R:IsMemberRecruitActive() and tickers == 1,
  "once the officer stage starts, the member's popups stop and only the officer's ticker runs")
local saidStopped = false
for _, line in ipairs(printed) do
  if line:find("stopped", 1, true) then saidStopped = true end
end
check(not saidStopped, "the member's popups go without a \"stopped\" line next to the officer's \"started\"")
if R.ticker then R.ticker:Cancel(); R.ticker = nil end

-- With the officer's own ad off, the member's popups still stop: nothing would, later.
member({})
myRank = nil
R:ApplyIncoming(AD, "Officer", "GUILD")
check(R:IsMemberRecruitActive() and tickers == 1, "again the member's popups run before the rank")
myRank = 0
GuildOS.db.recruitment = { enabled = false, message = "Officer ad", channels = { "LookingForGroup" }, interval = 120,
                          welcomeEnabled = false, welcomeMessage = "Hi" }
R:Initialize()
check(not R:IsMemberRecruitActive() and tickers == 0,
  "an officer whose own ad is off ends up with no ticker at all, not the member's")

-- ── 5. The officer's own popups (issue #84) ────────────────────────────
if R.ticker then R.ticker:Cancel(); R.ticker = nil end
member({ recruitment = false })
myRank = 0
GuildOS.db.recruitment = { enabled = false, message = "Officer ad", channels = { "LookingForGroup" }, interval = 120,
                          welcomeEnabled = false, welcomeMessage = "Hi" }
printed = {}
check(R:StartAutoRecruit() == false and R.ticker == nil and tickers == 0,
  "module off: /gos recruit on starts no officer popups")
check(GuildOS.db.recruitment.enabled == false and printed[#printed]
  and printed[#printed]:find("The Recruitment module is off. Turn it on in Settings > General > Modules.", 1, true),
  "and says why, leaving the officer's setting as it was")

GuildOS.db.settings.modules.recruitment = nil
delayed = {}
check(R:StartAutoRecruit() and R.ticker and tickers == 1, "module on: the officer's popups start")
GuildOS.db.settings.modules.recruitment = false
printed, popups = {}, 0
for _, fn in ipairs(delayed) do fn() end                -- the first popup, two seconds in
check(popups == 0, "switched off before the first popup: it does not show")
check(R.ticker ~= nil, "and the officer's ticker keeps running, silent")
R.ticker.fn()                                           -- a regular tick
check(popups == 0 and #printed == 0 and GuildOS.db.recruitment.enabled == true,
  "nor does any tick while it is off, without a word, and the officer's setting stays on")
GuildOS.db.settings.modules.recruitment = nil
R.ticker.fn()
check(popups == 1, "switched back on in the same session: the next tick shows a popup again")

-- /gos recruit interval with the module off: the guild's recruitment is not switched off.
GuildOS.db.settings.modules.recruitment = false
printed, relayed = {}, {}
R:HandleCommand({ "interval", "300" })
check(GuildOS.db.recruitment.enabled == true and GuildOS.db.recruitment.interval == 300 and #relayed == 0,
  "module off: changing the interval keeps recruitment on and broadcasts nothing")
local saidStoppedNow = false
for _, line in ipairs(printed) do
  if line:find("stopped", 1, true) then saidStoppedNow = true end
end
check(not saidStoppedNow and printed[#printed]:find("The Recruitment module is off", 1, true),
  "and says the module is off, not that recruitment stopped")
check(R.ticker and R.ticker.period == 300 and tickers == 1,
  "the silent ticker takes the new period, so the module comes back at 300s")

-- Module on: changing the interval leaves one ticker, at the new period.
GuildOS.db.settings.modules.recruitment = nil
R:HandleCommand({ "interval", "240" })
check(R.ticker and R.ticker.period == 240 and tickers == 1, "module on: the interval change leaves one ticker, at 240s")

-- Recruitment off: changing the interval does not start it.
R:StopAutoRecruit()
R:HandleCommand({ "interval", "180" })
check(R.ticker == nil and tickers == 0 and GuildOS.db.recruitment.enabled == false,
  "recruitment off: changing the interval only changes the interval")
GuildOS.db.recruitment.enabled = true

-- No settings at all, the module off since login: the refusal names the module.
GuildOS.db.settings.modules.recruitment = false
local saved = GuildOS.db.recruitment
GuildOS.db.recruitment = nil
printed = {}
R:HandleCommand({ "on" })
check(printed[#printed] and printed[#printed]:find("The Recruitment module is off", 1, true),
  "module off since login: /gos recruit on says the module is off")
GuildOS.db.recruitment = saved

print(("recruit-module-off: %d checks passed"):format(checks))
