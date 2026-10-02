-- The recruitment engagement screen (issue #51), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua and Modules/RecruitEngagement.lua.
--
-- Every client sends its own self-report over GUILD and officers keep what arrives. But
-- CommSystem drops a client's own messages, so the viewer's own report never arrived: on
-- Anniversary never, and on WoW: Forever not since PlayerName learned the surname — a
-- beta officer had 55 posts recorded and a screen of zeros. The viewer's own numbers now
-- come from its own client.
--
--   luajit -e 'ADDON="."' tools/recruit-engagement.lua
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
function GetBuildInfo() return "1.60.1", "70124", "", 16001 end
function GetRealmName() return "Classic Beta PvE 2" end
function UnitName() return "Chehul" end
function UnitFullName() return "Chehul", "Costa" end
function IsInGuild() return true end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }   -- what makes Compat know surnames
local NOW = 1790951000
function time() return NOW end
Enum = { SendAddonMessageResult = {} }
local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/RecruitEngagement.lua")
local RE = BRutus.RecruitEngagement

-- What the beta's SavedVariables held: posts recorded here, and a stale zero report of
-- myself from before the surname, plus another member's report that did arrive.
local me = BRutus:GetPlayerKey(BRutus.Compat.PlayerName(), GetRealmName())
check(me == "Chehul Costa-Classic Beta PvE 2", "my key carries the surname, like the envelope sender does")
local zeros = { 0, 0, 0, 0, 0, 0, 0 }
BRutus.db = {
  myRecruitStats = { posts = { NOW - 3600, NOW - 7200, NOW - 90000 }, invites = { NOW - 600 }, joins = {}, pending = {} },
  recruitStats = {
    [me] = { daily = { posts = zeros, invites = zeros, joins = zeros }, prev = {}, part = true, last = 0, receivedAt = NOW - 6 * 86400 },
    ["Cherry Arrow-Classic Beta PvE 2"] = {
      daily = { posts = { 0, 0, 2, 0, 0, 0, 0 }, invites = zeros, joins = zeros }, prev = {}, part = true, last = NOW - 3 * 86400,
      receivedAt = NOW - 3600,
    },
  },
}

local agg = RE:GetAggregate(NOW)
local mine, theirs
for _, row in ipairs(agg.rows) do
  if row.key == me then mine = row end
  if row.key:find("^Cherry Arrow") then theirs = row end
end
check(mine and mine.posts7 == 3 and mine.invites7 == 1, "my own posts and invites show, read from this client, not the dropped echo")
check(mine and not mine.stale, "and they are fresh, not the stale report from before the surname")
check(theirs and theirs.posts7 == 2, "another member's report still shows as it arrived")
check(agg.totals.posts7 == 5 and agg.totals.invites7 == 1, "and the totals add both")
check(BRutus.db.recruitStats[me].receivedAt == NOW - 6 * 86400, "nothing new is written to the received store")

print(("recruit-engagement: %d checks passed"):format(checks))
