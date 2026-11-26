-- A spec in the alliance room on retail (issue #184), run against the real Core/Compat.lua,
-- Core/Utils.lua, Modules/SpecChecker.lua and Modules/Alliance.lua under a stubbed retail client.
--
-- On retail a spec has an id the client names in the reader's language (SpecChecker:SpecName, issue
-- #177). This proves a speaker of our own guild in the alliance room is named by the id, not by the
-- name their client stored, and that a guildmate known only from the roster still has a class.
-- (The allied roster that sent specs between guilds went with the whisper sync, audit #448.)
--
--   luajit -e 'ADDON="."' tools/retail-alliance-spec.lua
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

function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 1, 5
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame() return setmetatable({}, { __index = function() return function() end end }) end
function GetServerTime() return 1791000000 end
time = function() return 1791000000 end
function GetRealmName() return "Azralon" end
function GetNormalizedRealmName() return "Azralon" end
function GetGuildInfo() return "Jardim Escola", "Officer", 1, "Azralon" end
function GetNumGuildMembers() return 0 end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                       { __call = function() return {} end })
-- This client is in English; spec 250 is Blood here.
function GetSpecializationInfoForSpecID(id) if id == 250 then return 250, "Blood", "", 0, "TANK" end end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), SelfTest = { Register = function() end } }
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/SpecChecker.lua")
dofile(ADDON .. "/Modules/Alliance.lua")
GuildOS.db = { members = {}, altLinks = {} }
check(GuildOS.Client.isRetail, "the stub is retail")

local A = GuildOS.Alliance
-- ── 3. One of ours speaking in the alliance channel ────────────────────
GuildOS.db.members["Dy-Azralon"] = { name = "Dy", class = "DEATHKNIGHT", level = 90,
                                     spec = { specID = 250, tree = "Sangue", role = "TANK" } }
local info = A:SpeakerInfo("Dy")
check(info and info.own and info.spec == "Blood" and info.class == "DEATHKNIGHT", "our own speaker is named by the spec's id")
check(A:SpeakerInfo("Nobody") == nil and A:SpeakerInfo("") == nil, "a speaker nothing is known of: nothing")

print(("retail-alliance-spec: %d checks passed"):format(checks))
