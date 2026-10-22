-- A spec in the alliance on retail (issue #184), run against the real Core/Compat.lua, Core/Utils.lua,
-- Modules/SpecChecker.lua, Modules/AllianceSync.lua and Modules/Alliance.lua under a stubbed retail
-- client.
--
-- The alliance roster sent a member's spec as its name, in the sender's language: an allied guild on
-- a Portuguese client showed "Sangue" to an English reader. On retail the spec has an id the client
-- names in the reader's language (SpecChecker:SpecName, issue #177). This proves the roster sends the
-- id beside the name, that the allied card and the alliance chat show it by the id, and that a row
-- from a sender without the id, or with one this client cannot name, keeps the sender's name.
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
dofile(ADDON .. "/Modules/AllianceSync.lua")
dofile(ADDON .. "/Modules/Alliance.lua")
GuildOS.db = { members = {}, altLinks = {} }
check(GuildOS.Client.isRetail, "the stub is retail")

-- ── 1. The roster sends the spec's id beside its name ──────────────────
local rows = GuildOS.AllianceSync._BuildRoster({
  ["Bo-Gallywix"] = { name = "Bo", class = "DEATHKNIGHT", level = 90, spec = { specID = 250, tree = "Sangue", role = "TANK" } },
  ["Cy-Azralon"]  = { name = "Cy", class = "PRIEST", level = 90, spec = { tree = "Holy", points = { 41, 5, 15 } } },
}, 10)
check(rows[1].n == "Bo" and rows[1].s == "Sangue" and rows[1].si == 250, "a retail spec goes out with its id")
check(rows[2].n == "Cy" and rows[2].s == "Holy" and rows[2].si == nil, "a classic spec goes out as it always did")

-- ── 2. An allied reader names it in their own language ─────────────────
local A, index = GuildOS.Alliance, {}
GuildOS.AllianceSync.MemberIndex = function() return index end
index.bo = { guild = "Outra Guilda", row = rows[1] }
check(A:MemberInfo("Bo").spec == "Blood", "the allied card names the spec in the reader's language")
index.bo = { guild = "Outra Guilda", row = { n = "Bo", s = "Sangue" } }
check(A:MemberInfo("Bo").spec == "Sangue", "a row from a sender before issue #184 keeps the sender's name")
index.bo = { guild = "Outra Guilda", row = { n = "Bo", s = "Sangue", si = 9999 } }
check(A:MemberInfo("Bo").spec == "Sangue", "and so does an id this client cannot name")

-- ── 3. One of ours speaking in the alliance channel ────────────────────
index.bo = nil
GuildOS.db.members["Dy-Azralon"] = { name = "Dy", class = "DEATHKNIGHT", level = 90,
                                     spec = { specID = 250, tree = "Sangue", role = "TANK" } }
local info = A:SpeakerInfo("Dy")
check(info and info.own and info.spec == "Blood", "our own speaker's card names the spec by its id too")

print(("retail-alliance-spec: %d checks passed"):format(checks))
