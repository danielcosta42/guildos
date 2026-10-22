-- Namesakes on connected realms (issue #184), run against the real Core files, Modules/BanList.lua,
-- Modules/PugInspector.lua, Modules/GuildManager.lua, Modules/RosterLog.lua and
-- Modules/RaidTracker.lua under a stubbed retail client, and BanList and GuildManager as WoW: Forever.
--
-- A retail guild spans connected realms, and Bob-Azralon and Bob-Gallywix can both be in it. The ban
-- list was keyed by the name alone, the group inspector, the rank lookup, the roster log and the raid
-- tracker's guild check matched the name alone, so banning one Bob banned the other, and a namesake
-- from a third realm counted as a guildmate. This proves each of them tells namesakes apart on retail
-- (the whole key wins; a name without a realm is this client's realm's, never a guess elsewhere),
-- that a ban filed under the name alone before still holds and can still be lifted, that the ban
-- list lifts the row it shows and nothing else, that every caller hands the ban list the whole name
-- it has, and that Forever keeps the name alone.
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
check(not B:IsBanned(B:_Who("Bob")) and not B:IsBanned("Bob"),
  "nor is a Bob without a realm: that one is on this realm, never a guess at the banned namesake")
B:Add("Zed-Gallywix", "x"); B:Add("Zed-TolBarad", "y")
check(not B:IsBanned("Zed") and B:IsBanned("Zed-TolBarad"), "two Zeds banned elsewhere: this realm's Zed is not")
B:Add("Cy", "typed")
check(store["cy-azralon"] and store["cy-azralon"].name == "Cy-Azralon", "a name typed without a realm is this realm's")

-- A ban filed under the name alone by a version before issue #184 still holds, on any realm, and the
-- ban list lifts exactly the row it shows (the reviewer's case: an old ban plus one of this realm's).
store.thrall = { name = "Thrall", reason = "old", ts = 100 }
check(B:IsBanned("Thrall-Gallywix") and B:IsBanned("Thrall") and B:Get("Thrall-Azralon").reason == "old",
  "an old ban by name still holds for that name on every realm")
B:Add("Thrall-Azralon", "new")
check(B:Remove("Thrall-Azralon") and store["thrall-azralon"].removed and not store.thrall.removed,
  "/gos unban with the whole name lifts that ban, not the old one")
check(B:IsBanned("Thrall-Azralon"), "and the old ban by name still holds for him: lifting his own does not lift it")
local rows = {}
for _, e in ipairs(B:List()) do rows[e.name] = e.key end
check(rows.Thrall == "thrall" and rows["Thrall-Azralon"] == nil, "the list shows the old ban, with its own key")
check(B:RemoveKey(rows.Thrall) and store.thrall.removed and not B:IsBanned("Thrall-Gallywix"),
  "its row's x lifts the old ban, and only it")
store.thrall = { name = "Thrall", reason = "old", ts = 100 }
B:Add("Thrall-Azralon", "new")
check(B:Remove("Thrall") and store.thrall.removed and not store["thrall-azralon"].removed,
  "/gos unban with the bare name lifts the old ban by name first")
check(B:Remove("Thrall") and store["thrall-azralon"].removed, "and, that one lifted, this realm's")
check(not B:Remove("Thrall") and not B:RemoveKey("thrall"), "a ban already lifted is not lifted again")
store.thrall = { name = "Thrall", reason = "old", ts = 100 }
store["thrall-azralon"] = { name = "Thrall-Azralon", reason = "temp", ts = 200, expiry = GetServerTime() - 3600 }
check(B:IsBanned("Thrall-Azralon") and B:Get("Thrall-Azralon").reason == "old",
  "a temporary ban that ran out does not hide the old ban by name, which still holds")
check(not B:Remove("Thrall-Gallywix") and B:IsBanned("Thrall-Gallywix") and store["thrall-gallywix"] == nil,
  "/gos unban Thrall-Gallywix lifts nothing when only the old ban by name holds him")
-- An old ban by name that ran out is not the one /gos unban lifts: this realm's standing one is.
store.thrall = { name = "Thrall", reason = "old temp", ts = 100, expiry = GetServerTime() - 3600 }
store["thrall-azralon"] = { name = "Thrall-Azralon", reason = "standing", ts = 200 }
check(B:Remove("Thrall") and store["thrall-azralon"].removed and not store.thrall.removed and not B:IsBanned("Thrall"),
  "/gos unban Thrall lifts this realm's standing ban, not an old ban by name that ran out")
check(not B:Remove("Zed") and store["zed-azralon"] == nil and B:IsBanned("Zed-Gallywix"),
  "/gos unban Zed with only other realms' Zeds banned lifts nothing, and writes nothing")
local said = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
dofile(ADDON .. "/Core/Commands.lua")
SlashCmdList.GUILDOS("unban Zed")
check(table.concat(said, " "):find("No ban to lift for Zed.", 1, true) and not table.concat(said, " "):find("Unbanned"),
  "and says so, never 'Unbanned'")
said = {}
SlashCmdList.GUILDOS("unban Zed-TolBarad")
check(table.concat(said, " "):find("Unbanned Zed-TolBarad", 1, true) and store["zed-tolbarad"].removed, "a real unban is said as before")
B:Add("Zed-TolBarad", "y")
for _, e in ipairs(B:List()) do rows[e.name] = e.key end
check(B:RemoveKey(rows["Bob-Gallywix"]) and store["bob-gallywix"].removed and not B:IsBanned("Bob-Gallywix"),
  "the x on Bob-Gallywix's row lifts his ban")
B:Add("Bob-Gallywix", "again")
local manage = assert(io.open(ADDON .. "/UI/ManagementPanel.lua", "rb")):read("*a")
check(manage:find("GuildOS.BanList:RemoveKey(key)", 1, true) and not manage:find("BanList:Remove(nm)", 1, true),
  "the ban list's x lifts by the row's key")

-- The game's own names: a whisper, a join and a unit's tooltip.
local tipHook, TIP = nil, {}
GameTooltip = { HasScript = function() return true end, HookScript = function(_, _, fn) tipHook = fn end }
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
function UnitName(u) if u == "mouseover" then return TIP[1], TIP[2] end return "Ana" end
function UnitClass() return "Mage", "MAGE" end
local function tooltipLines(name, realm)
  TIP = { name, realm }
  local tt = { lines = 0 }
  function tt:GetUnit() return name, "mouseover" end
  function tt:AddLine() self.lines = self.lines + 1 end
  function tt:Show() end
  tipHook(tt)
  return tt.lines
end
check(tipHook and tooltipLines("Bob", "Gallywix") == 1, "Bob-Gallywix's tooltip says he is banned")
check(tooltipLines("Bob", nil) == 0, "this realm's Bob's tooltip does not")

-- Every caller hands over the whole name it has: the keyword whisper, the popup's click, the /who scan.
StaticPopupDialogs = {}
dofile(ADDON .. "/Modules/RecruitEngagement.lua")
dofile(ADDON .. "/Modules/RecruitmentSystem.lua")
dofile(ADDON .. "/Modules/RecruitScanner.lua")
local R = GuildOS.Recruitment
GuildOS.db.recruitment = { autoInvite = { cooldownSec = 60 } }
R._OnInviteCooldown = function() return false end
local invited = {}
R._DoInvite = function(_, name, full) invited[#invited + 1] = full or name end
R._InviteNow = function(_, name, full) invited[#invited + 1] = full or name end
R:_HandleKeywordWhisper("Zed", "Zed-Gallywix")
check(#invited == 0, "a keyword whisper from Zed-Gallywix, banned, invites nobody")
R:_HandleKeywordWhisper("Zed", "Zed")
check(#invited == 1 and invited[1] == "Zed", "this realm's Zed, who shares the name, is invited")
R._pendingInvites = { { name = "Zed", full = "Zed-TolBarad" } }
R:InviteNext()
check(#invited == 1, "the popup's click does not invite a Zed banned on another realm")
local S = GuildOS.RecruitScanner
local banned = function(n) return B:IsBanned(n) end
check(not S:_CandidateOK({ name = "Zed", full = "Zed-Gallywix" }, {}, banned)
  and S:_CandidateOK({ name = "Zed", full = "Zed" }, {}, banned),
  "the /who scan leaves out the banned Zed, by the realm /who gives, and keeps this realm's")

-- The /who scan from its result to the whisper and the reply: this realm's Zed is banned, and /who
-- names a connected realm's Zed with his realm (the reviewer's case).
B:RemoveKey("zed-gallywix")
B:Add("Zed", "this realm's")
local WHO = { { fullName = "Zed", level = 80, filename = "MAGE" }, { fullName = "Zed-Gallywix", level = 80, filename = "MAGE" } }
C_FriendList = { GetNumWhoResults = function() return #WHO end, GetWhoInfo = function(i) return WHO[i] end }
GuildOS.db.recruitScanner = { template = "hi [player]", batchMax = 10, cooldownSec = 1800, inbox = {} }
S._contactCd = {}
S:_OnWhoResult()
local res = S:GetResults()
check(#res == 1 and res[1].name == "Zed" and S:Addr(res[1]) == "Zed-Gallywix",
  "the scan keeps Zed-Gallywix, under his whole name, and leaves this realm's banned Zed out")
local whispered = {}
SendChatMessage = function(msg, kind, _, target) whispered[#whispered + 1] = { msg = msg, kind = kind, target = target } end
S:WhisperSelected({ S:Addr(res[1]) })
check(#whispered == 1 and whispered[1].target == "Zed-Gallywix" and whispered[1].msg == "hi Zed",
  "the whisper goes to Zed-Gallywix, never to this realm's banned Zed, and greets him by name")
check(S._contactCd["Zed-Gallywix"] and not S._contactCd["Zed-Azralon"], "and his cooldown is his own")
S:WhisperSelected({ "Zed" })
check(#whispered == 1, "a bare Zed handed to the whisper is this realm's, banned, and is not whispered")
S:_RegisterEvents()
local onWhisper = handlers[#handlers]
onWhisper(nil, "CHAT_MSG_WHISPER", "no thanks", "Zed")
check(#GuildOS.db.recruitScanner.inbox == 0, "a whisper from this realm's Zed is not his reply")
onWhisper(nil, "CHAT_MSG_WHISPER", "sure", "Zed-Gallywix")
check(#GuildOS.db.recruitScanner.inbox == 1, "Zed-Gallywix's is")
-- The panel's checkbox selects by the same whole name the whisper sends to (not driven here: a
-- frame-built panel; read from the source).
local scannerSrc = io.open(ADDON .. "/Modules/RecruitScanner.lua", "rb"):read("*a")
check(scannerSrc:find("local who = RecruitScanner:Addr(cand)", 1, true) ~= nil,
  "the scan panel's checkbox selects a candidate by RecruitScanner:Addr")

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
