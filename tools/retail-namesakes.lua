-- Namesakes on connected realms (issue #184), run against the real Core files, Modules/BanList.lua,
-- Modules/PugInspector.lua, Modules/GuildManager.lua, Modules/RosterLog.lua and
-- Modules/RaidTracker.lua under a stubbed retail client, and BanList and GuildManager as WoW: Forever.
--
-- A retail guild spans connected realms, and Bob-Azralon and Bob-Gallywix can both be in it. The ban
-- list was keyed by the name alone, the group inspector, the rank lookup, the roster log and the raid
-- tracker's guild check matched the name alone, so banning one Bob banned the other, and a namesake
-- from a third realm counted as a guildmate. This proves each of them tells namesakes apart on retail
-- (the whole key wins; a name without a realm is this client's realm's, or the only one there is),
-- that a ban filed under the name alone before still holds, and that Forever keeps the name alone.
--
--   luajit -e 'ADDON="."' tools/retail-namesakes.lua
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

local SECRET = {}
local ROSTER = {
  { "Bob-Azralon", 1, "WARRIOR" },
  { "Bob-Gallywix", 4, "MAGE" },
  { "Ana-Azralon", 2, "PRIEST" },
}
local handlers, alerts = {}, 0
local function load(retail)
  if retail then
    function GetBuildInfo() return "12.1.5", "70448", "", 120105 end
    WOW_PROJECT_ID = 1
  else
    function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
    WOW_PROJECT_ID = 99
  end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 5
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  handlers = {}
  function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.SetScript = function(_, _, fn) handlers[#handlers + 1] = fn end
    return f
  end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return 1791000000 end
  time = function() return 1791000000 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  issecretvalue = function(v) return v == SECRET end
  function IsInGuild() return true end
  function GetGuildInfo() return "Guild", "Officer", 1, "Azralon" end
  function GetRealmName() return "Azralon" end
  function GetNormalizedRealmName() return "Azralon" end
  function UnitName() return "Ana" end
  function GetNumGuildMembers() return #ROSTER end
  function GetGuildRosterInfo(i)
    local r = ROSTER[i]
    if r then return r[1], "Rank", r[2], 80, r[3], "", "", "", true, 0, r[3] end
  end
  ERR_GUILD_JOIN_S = "%s has joined the guild."
  ERR_GUILD_LEAVE_S = "%s has left the guild."
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return true end
  GuildOS.db = { settings = { modules = {} }, members = {}, raidTracker = {}, banList = {}, rosterLog = { events = {} } }
  for _, m in ipairs({ "BanList", "PugInspector", "GuildManager", "RosterLog", "RaidTracker" }) do
    dofile(ADDON .. "/Modules/" .. m .. ".lua")
  end
  GuildOS.BanList.Refresh = function() end
  GuildOS.BanList._Alert = function() alerts = alerts + 1 end
  return GuildOS.BanList
end

-- ── 1. Retail: a ban names one character ──────────────────────────────
local B = load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
check(B:Add("Bob-Gallywix", "ninja"), "an officer bans Bob-Gallywix")
local store = GuildOS.db.banList
check(store["bob-gallywix"] and store["bob-gallywix"].name == "Bob-Gallywix" and store.bob == nil,
  "the ban is filed under the whole key, and named with the realm")
check(B:IsBanned("Bob-Gallywix") and B:IsBanned("bob-gallywix"), "Bob-Gallywix is banned, in any case")
check(not B:IsBanned("Bob-Azralon"), "Bob-Azralon, the guildmate who shares the name, is not")
check(not B:IsBanned(B:_Who("Bob")), "nor is a Bob the game hands over without a realm: that one is on this realm")
check(B:IsBanned("Bob"), "a name some code stripped of its realm still finds the only Bob banned")
B:Add("Zed-Gallywix", "x"); B:Add("Zed-TolBarad", "y")
check(not B:IsBanned("Zed") and B:IsBanned("Zed-TolBarad"), "two Zeds banned: a bare Zed is a guess, and answers nothing")
B:Add("Cy", "typed")
check(store["cy-azralon"] and store["cy-azralon"].name == "Cy-Azralon", "a name typed without a realm is this realm's")

-- A ban filed under the name alone by a version before issue #184 still holds, on any realm.
store.thrall = { name = "Thrall", reason = "old", ts = 100 }
check(B:IsBanned("Thrall-Gallywix") and B:IsBanned("Thrall") and B:Get("Thrall-Azralon").reason == "old",
  "an old ban by name still holds for that name on every realm")
check(B:Remove("Thrall") and store.thrall.removed and store["thrall-azralon"] == nil,
  "and removing it by that name lifts the old entry, not a new one")
check(B:Remove("Bob-Gallywix") and store["bob-gallywix"].removed and not B:IsBanned("Bob-Gallywix"),
  "unbanning Bob-Gallywix lifts his ban")
B:Add("Bob-Gallywix", "again")

-- The game's own names: a whisper and a join.
B._ready = true
local onEvent = handlers[#handlers]
B:_SetupDetection()
onEvent = handlers[#handlers]
B._ready = true
alerts = 0
onEvent(nil, "CHAT_MSG_WHISPER", "hi", "Bob")
check(alerts == 0, "a whisper from this realm's Bob raises no alarm")
onEvent(nil, "CHAT_MSG_WHISPER", "hi", "Bob-Gallywix")
check(alerts == 1, "a whisper from Bob-Gallywix does")
onEvent(nil, "CHAT_MSG_SYSTEM", "Bob has joined the guild.")
check(alerts == 1, "this realm's Bob joining raises no alarm")
onEvent(nil, "CHAT_MSG_SYSTEM", "Bob-Gallywix has joined the guild.")
check(alerts == 2, "Bob-Gallywix joining does")

-- ── 2. Retail: the group inspector ─────────────────────────────────────
local PI = GuildOS.PugInspector
GuildOS.db.rosterLog.events = { { action = "leave", target = "Ana-Gallywix", timestamp = 50 } }
local function tag(name) return PI:Classify(name).tag end
check(tag("Bob") == GuildOS.L["Guildmate"], "a raid's bare Bob is this realm's guildmate, not the banned namesake")
check(tag("Bob-Gallywix") == GuildOS.L["BANNED"], "Bob-Gallywix is flagged")
check(tag("Bob-TolBarad") == GuildOS.L["Unknown (not in guild)"], "a third realm's Bob is not a guildmate")
check(tag("Ana") == GuildOS.L["Guildmate"], "this realm's Ana is a guildmate")
check(tag("Ana-Gallywix") == GuildOS.L["Ex-member"], "and the Ana who left, from another realm, an ex-member")
GuildOS.db.altLinks = { ["Cy-TolBarad"] = "Bob-TolBarad", ["Di-TolBarad"] = "Bob-Gallywix" }
check(tag("Cy-TolBarad") ~= string.format(GuildOS.L["Alt of %s (guild)"], "Bob"), "an alt of a third realm's Bob is not a guildmate's")
check(tag("Di-TolBarad") == string.format(GuildOS.L["Alt of %s (guild)"], "Bob"), "an alt of Bob-Gallywix is")

-- A raid member whose name the client keeps secret is skipped, never matched (issue #184).
function IsInRaid() return true end
function GetNumGroupMembers() return 2 end
function UnitIsUnit() return false end
function GetRaidRosterInfo(i)
  if i == 1 then return SECRET, nil, nil, nil, nil, SECRET end
  return "Bob-Gallywix", nil, nil, nil, nil, "MAGE"
end
local ok, group = pcall(PI._GroupMembers, PI)
check(ok and #group == 1 and group[1].full == "Bob-Gallywix", "a secret raid name is skipped without raising")
function IsInRaid() return false end
function IsInGroup() return true end
function UnitExists(u) return u == "party1" end
function UnitName(u) if u == "party1" then return "Bob", "Gallywix" end return "Ana" end
function UnitClass() return "Mage", "MAGE" end
GetNumGroupMembers = function() return 2 end
group = PI:_GroupMembers()
check(#group == 1 and group[1].full == "Bob-Gallywix" and group[1].name == "Bob", "a party member keeps their realm")

-- Raid Tools reads the same roster: a secret name is skipped, never matched.
dofile(ADDON .. "/Modules/RaidTools.lua")
function IsInRaid() return true end
ok, group = pcall(GuildOS.RaidTools.GetSource, GuildOS.RaidTools)
check(ok and #group == 1 and group[1].class == "MAGE", "Raid Tools skips a secret raid name without raising")
function IsInRaid() return false end

-- ── 3. Retail: ranks, the roster log and the raid's guild check ────────
local GM = GuildOS.GuildManager
check(GM:GetRosterIndex("Bob-Gallywix") == 2 and GM:GetRankIndex("Bob-Gallywix") == 4, "the rank of Bob-Gallywix is his own")
check(GM:GetRosterIndex("Bob") == nil and GM:GetRosterIndex("Ana") == 3, "a bare name is found only when it is the only one")
local RL = GuildOS.RosterLog
check(RL:_ParseSystem("Bob-Gallywix has joined the guild.").target == "Bob-Gallywix", "the log keeps a connected realm's member's realm")
check(RL:_ParseSystem("Bob has joined the guild.").target == "Bob-Azralon", "and files this realm's under the same whole key")
local RT = GuildOS.RaidTracker
check(not RT:IsGuildRaid({ players = { ["Bob-TolBarad"] = {}, ["Zed-TolBarad"] = {}, ["Ana-Azralon"] = {} } }),
  "a raid of two strangers and one guildmate is not a guild raid, whatever their names share")
check(RT:IsGuildRaid({ players = { ["Bob-Gallywix"] = {}, ["Zed-TolBarad"] = {} } }), "half of the guild is")
local src = assert(io.open(ADDON .. "/UI/RosterFrame.lua", "rb")):read("*a")
check(src:find("GM:GetRankIndex(data.fullName or data.name)", 1, true), "the roster's rank menu asks with the whole name")

-- ── 4. Forever keeps the name alone ───────────────────────────────────
B = load(false)
check(not GuildOS.Client.isRetail, "the stub is Forever")
B:Add("Bob-Gallywix", "ninja")
check(GuildOS.db.banList.bob and GuildOS.db.banList.bob.name == "Bob" and B:IsBanned("Bob-Azralon") and B:IsBanned("Bob"),
  "Forever files a ban under the name alone, as before")
check(GuildOS.GuildManager:GetRosterIndex("Bob-Gallywix") == 1, "and finds a rank by the name alone, the first hit, as before")
check(GuildOS.RosterLog:_ParseSystem("Bob-Gallywix has joined the guild.").target == "Bob", "and logs the name alone")

print(("retail-namesakes: %d checks passed"):format(checks))
