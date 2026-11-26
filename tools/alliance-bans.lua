-- The alliance's shared bans (issue #408), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/BanList.lua and Modules/CompanionImport.lua under a stubbed client, as
-- WoW: Forever and as retail.
--
-- An officer shares a local ban with the alliance (a reason from the contract's list, required; an
-- optional note), stops sharing it, or lifts the ban; the companion export carries `banShares`. The
-- site's `allianceBans` come in through the GOSGILD1, every field checked, held in memory, matched by
-- the key a ban is filed under (the realm on retail, the name alone elsewhere, #184), shown to officers
-- only as an alert on a join, a whisper, a tooltip and before a manual invite, and never in IsBanned.
--
--   luajit -e 'ADDON="."' tools/alliance-bans.lua
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
local NOW = 1791000000
local handlers, hooks, printed, sent, dialogs = {}, {}, {}, {}, {}
local officer = true
local BLOCK

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
  handlers, hooks = {}, {}
  function CreateFrame()
    local f = setmetatable({}, { __index = function() return function() end end })
    f.SetScript = function(_, _, fn) handlers[#handlers + 1] = fn end
    return f
  end
  function hooksecurefunc() end
  function debugstack() return "" end
  function GetServerTime() return NOW end
  function GetTime() return NOW end
  time = function() return NOW end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  issecretvalue = function(v) return v == SECRET end
  function IsInGuild() return true end
  function GetGuildInfo() return "Ordem", "Officer", 1, "Azralon" end
  function GetRealmName() return "Azralon" end
  function GetNormalizedRealmName() return "Azralon" end
  function UnitName() return "Ana" end
  function UnitFullName() return "Ana", "Azralon" end
  function GetNumGuildMembers() return 0 end
  function GetGuildRosterInfo() end
  ERR_GUILD_JOIN_S = "%s has joined the guild."
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  LibStub = setmetatable({ NewLibrary = function() return {} end, GetLibrary = function() return {} end },
                         { __call = function() return {} end })
  GameTooltip = { HasScript = function() return true end, HookScript = function(_, s, fn) hooks[s] = fn end }
  SlashCmdList = {}
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  function GuildOS:IsOfficer() return officer end
  function GuildOS:Print(m) printed[#printed + 1] = m end
  function GuildOS:ShowDialog(which, a, b, data) dialogs[#dialogs + 1] = { which = which, text = a, data = data } return {} end
  GuildOS.db = { settings = { modules = {} }, members = {}, banList = {} }
  GuildOS.SyncService = {
    On = function() end,
    NextRevision = function() return 1 end,
    GetRevision = function() return 1 end,
    Publish = function(_, dom, act, data) sent[#sent + 1] = { dom = dom, act = act, data = data } end,
  }
  dofile(ADDON .. "/Modules/BanList.lua")
  dofile(ADDON .. "/Modules/CompanionImport.lua")
  local before = #handlers
  GuildOS.BanList:Initialize()
  GuildOS.BanList._ready = true
  GuildOS.BanList._onEvent = handlers[before + 1]
  function GuildOS.CompanionImport:GuildBlock() return BLOCK end
  return GuildOS.BanList, GuildOS.CompanionImport
end

-- ── 1. WoW: Forever: sharing a local ban ────────────────────────────────
local B, Import = load(false)
check(not GuildOS.Client.isRetail, "the stub is Forever")
check(B:Add("Thrall", "ninja'd the bag"), "an officer bans Thrall")
local store = GuildOS.db.banList
check(B:ForExport() == nil, "nothing shared yet: no banShares")
check(select(2, B:Share("thrall", "theft")) == "reason" and select(2, B:Share("thrall")) == "reason",
  "a reason from the list is required")
check(select(2, B:Share("nobody", "scam")) == "missing", "only a standing ban is shared")
-- A temporary ban that ran out is never shared, nor offered (audit B6); Share means the site's alliance (B7).
store.runout = { name = "Runout", reason = "r", author = "Off", ts = NOW - 100, expiry = NOW - 1 }
check(select(2, B:Share("runout", "scam")) == "expired" and not B:IsShared("runout"), "an expired temporary ban cannot be shared")
BLOCK = nil
check(not B:HasSiteAlliance() and not B:CanShare("thrall"), "no alliance on the site: nothing is offered for sharing")
BLOCK = { allianceBans = {} }
check(B:HasSiteAlliance() and B:CanShare("thrall") and not B:CanShare("runout"),
  "with one: a ban in force is offered, the one that ran out is not")
BLOCK = nil
store.runout = nil
-- Lifting from the list asks first (audit B6).
dialogs = {}
check(B:ConfirmRemoveKey("thrall", "Thrall") and not store.thrall.removed and dialogs[1].which == "GUILDOS_BAN_LIFT"
  and dialogs[1].text == "Thrall" and dialogs[1].data == "thrall", "the x asks before it lifts")
check(GuildOS.Dialogs.GUILDOS_BAN_LIFT.button1 == "Lift", "the question's yes is Lift")
dialogs = {}
officer = false
check(select(2, B:Share("thrall", "scam")) == "officer" and not B:IsShared("thrall"), "a member cannot share")
officer = true
sent = {}
check(B:Share("thrall", "ninja", "  took |cffff0000the|r bag\nand left  "), "an officer shares it")
local sh = store.thrall.share
check(sh.reason == "ninja" and sh.at == NOW and sh.note == "took cffff0000ther bag and left" and not sh.withdrawnAt,
  "the share is on the ban, its note cleaned")
check(#sent == 1 and sent[1].dom == "ban" and sent[1].data.entry.share == sh, "and goes to the officers with the ban")
check(B:IsShared("thrall"), "shared")
local long = B.CleanNote(string.rep("\195\169", 150))
check(#long <= B.SHARE_NOTE_MAX and not long:find("\195$"), "a long note is cut without a half letter")

local ex = B:ForExport()
check(ex and #ex == 1 and ex[1].key == GuildOS:GetPlayerKey("Thrall") and ex[1].name == "Thrall" and ex[1].reason == "ninja"
      and ex[1].at == NOW and ex[1].note == sh.note and ex[1].withdrawnAt == nil,
  "banShares: { key as members[].key builds it, name, reason, note, at }")
officer = false
check(B:ForExport() == nil, "a member's client sends none")
officer = true

-- Banned again: the share stays.
B:Add("Thrall", "again")
check(store.thrall.share == sh and store.thrall.reason == "again", "editing the ban keeps its share")
-- The officer's own note (#426): banned again without one (or with the box empty) keeps it; lifting it drops it.
B:Add("Thrall", "again", nil, "  my |cffff0000words|r ")
check(store.thrall.note == "my cffff0000wordsr", "the officer's note, cleaned")
B:Add("Thrall", "once more")
check(store.thrall.note == "my cffff0000wordsr" and store.thrall.reason == "once more", "banned again without a note keeps it")
B:Add("Thrall", "and again", nil, "  ")
check(store.thrall.note == "my cffff0000wordsr", "nor does an empty box")
B:Add("Thrall", "new words", nil, "other words")
check(store.thrall.note == "other words", "a new note replaces it")

NOW = NOW + 10
check(B:Unshare("thrall") and store.thrall.share.withdrawnAt == NOW and not B:IsShared("thrall"), "stop sharing")
check(not B:Unshare("thrall"), "not twice")
ex = B:ForExport()
check(ex[1].withdrawnAt == NOW, "the export says it was withdrawn")
check(B:Share("thrall", "scam") and not store.thrall.share.withdrawnAt and B:ForExport()[1].reason == "scam",
  "shared again: a fresh share")
NOW = NOW + 10
check(B:RemoveKey("thrall") and store.thrall.removed and store.thrall.share.withdrawnAt == NOW,
  "lifting the ban withdraws its share")
check(B:ForExport()[1].withdrawnAt == NOW and #B:List() == 0, "and the export still says so; the list hides it")

-- A temporary ban that ran out reads as withdrawn when it ran out.
B:Add("Zed", "temp", 5)
B:Share("zed", "harassment")
NOW = NOW + 100
local zed
for _, s in ipairs(B:ForExport()) do if s.name == "Zed" then zed = s end end
check(zed and zed.withdrawnAt == store.zed.expiry, "a temporary ban that ran out is withdrawn at its end")

-- What another officer's sync wrote is cleaned again; the list is capped and newest first.
store.bad = { name = "Bad", ts = 1, share = { reason = "nope", at = 1 } }
store.nan = { name = "Nan", ts = 1, share = { reason = "scam", at = 0 / 0 } }
store.str = { name = "Str", ts = 1, share = "scam" }
for i = 1, 250 do store["p" .. i] = { name = "P" .. i, ts = i, share = { reason = "other", at = i, note = 7 } } end
ex = B:ForExport()
check(#ex == B.SHARE_EXPORT_MAX, "at most 200 go up")
local seen = {}
for i, s in ipairs(ex) do
  seen[s.name] = true
  if i > 1 then check(ex[i - 1].at >= s.at, "newest first") end
  check(s.note == nil or type(s.note) == "string", "a note is text or absent")
end
check(not seen.Bad and not seen.Nan and not seen.Str, "a share that does not read is left out")
for k in pairs(store) do if k:find("^p%d") or k == "bad" or k == "nan" or k == "str" then store[k] = nil end end

-- The export carries it, guarded, never in the pack.
local exportSrc = assert(io.open(ADDON .. "/Modules/CompanionExport.lua", "rb")):read("*a")
check(exportSrc:find('and optional("banShares", GuildOS.BanList.ForExport, GuildOS.BanList) or nil', 1, true),
  "the export carries banShares, guarded")
local selfPart = exportSrc:match("function Companion:BuildSelf%(%)(.-)\nend\n")
check(selfPart and not selfPart:find("banShares", 1, true), "and the character's own pack never")

-- ── 2. The alliance's bans, through the import ──────────────────────────
BLOCK = nil
check(Import:AllianceBans() == nil and B:AllianceBansFor("Gul") == nil, "no block: nothing")
BLOCK = { allianceBans = {
  { id = "ck1", key = "Gul-Realm", name = "Gul", guild = "Horde |cffff0000Co", reason = "scam", at = NOW - 50, note = "sold a\nfake carry" },
  { id = "ck2", key = "Gul-Realm", name = "Gul", guild = "Other", reason = "cheating", at = NOW - 40, appeal = true },
  { id = "ck3", key = "Own-Realm", name = "Own", guild = "ORDEM", reason = "scam", at = NOW },
  { id = "bad id!", key = "X-Realm", name = "X", guild = "G", reason = "scam", at = NOW },
  { id = "ck5", key = "Y-Realm", name = "Y", guild = "G", reason = "theft", at = NOW },
  { id = "ck6", key = "Z-Realm", name = "Z", guild = "G", reason = "scam", at = 0 / 0 },
  { id = "ck7", key = string.rep("k", 65), name = "K", guild = "G", reason = "scam", at = NOW },
  { id = "ck8", key = 42, name = "N", guild = "G", reason = "scam", at = NOW },
  { id = "ck9", key = "W-Realm", guild = "G", reason = "other", at = NOW, appeal = "yes", note = 5 },
  "not a ban",
} }
local ab = Import:AllianceBans()
check(#ab == 3, "only bans whose every field reads come in; this guild's own is not another's (got " .. #ab .. ")")
check(ab[1].guild == "Horde cffff0000Co" and ab[1].note == "sold a fake carry" and ab[1].key == GuildOS:LocalMemberKey("Gul-Realm"),
  "the text is made inert, the key this client's")
check(ab[2].appeal == true and ab[3].appeal == nil and ab[3].note == nil and ab[3].name == "W", "appeal only when true; a name from the key")
local many = { allianceBans = {} }
for i = 1, 400 do many.allianceBans[i] = { id = "m" .. i, key = "M" .. i .. "-Realm", guild = "G", reason = "scam", at = NOW } end
BLOCK = many
check(#Import:AllianceBans() == B.ALLIANCE_MAX, "at most 200 read")
BLOCK = { allianceBans = ab and { { id = "ck1", key = "Gul-Realm", name = "Gul", guild = "Horde Co", reason = "scam", at = NOW - 50, note = "fake carry" },
  { id = "ck2", key = "Gul-OtherRealm", name = "Gul", guild = "Other", reason = "cheating", at = NOW - 40, appeal = true } } }

-- Matching, by the key a ban is filed under: on Forever the name alone.
local hit = B:AllianceBansFor("Gul")
check(hit and #hit == 2, "Forever: both bans on Gul, whatever realm the key was built with")
check(B:AllianceBansFor("gul-Classic Beta PvE") and #B:AllianceBansFor("gul-Classic Beta PvE") == 2, "any case, any realm suffix")
check(not B:IsBanned("Gul"), "an alliance ban never enters IsBanned: the auto-invite is not blocked")
check(store.gul == nil, "and never db.banList")
officer = false
check(B:AllianceBansFor("Gul") == nil, "a member sees nothing")
officer = true
check(B.AllianceLine(hit[2]) == "Banned in Other for Cheating (under appeal)" and B.AllianceLine(hit[1]) == "Banned in Horde Co for Scam",
  "the alert's words")

-- Held in memory, rebuilt when the block changes.
local first = select(2, B:AllianceBans())
check(select(2, B:AllianceBans()) == first, "one index per block")
local before = BLOCK
BLOCK = nil
check(B:AllianceBansFor("Gul") == nil, "the block gone (a week old, another guild's, the companion off): the bans go")
BLOCK = before

-- ── 3. The alerts ───────────────────────────────────────────────────────
local onEvent = B._onEvent
printed = {}
onEvent(nil, "CHAT_MSG_WHISPER", "hi", "Gul")
check(#printed == 2 and printed[1]:find("Alliance ban: Gul. Banned in Horde Co for Scam", 1, true) and printed[1]:find("fake carry", 1, true),
  "a whisper from Gul alerts the officer, once per ban")
printed = {}
onEvent(nil, "CHAT_MSG_WHISPER", "hi again", "Gul")
check(#printed == 0, "not again within the minute")
printed = {}
onEvent(nil, "CHAT_MSG_SYSTEM", "Gul has joined the guild.")
check(#printed == 2, "a join alerts")
printed = {}
onEvent(nil, "CHAT_MSG_WHISPER", "hi", SECRET)
onEvent(nil, "CHAT_MSG_SYSTEM", SECRET)
check(#printed == 0, "a secret line or sender: nothing touched, nothing said")
officer = false
onEvent(nil, "CHAT_MSG_SYSTEM", "Gul has joined the guild.")
check(#printed == 0, "a member is not alerted")
officer = true
local function tooltip(name)
  local tt = { lines = {} }
  function tt:GetUnit() return name, "mouseover" end
  function tt:AddLine(t) self.lines[#self.lines + 1] = t end
  function tt:Show() end
  return tt
end
GuildOS.Compat.UnitIdentity = function() return "Gul", nil end
local tt = tooltip("Gul")
hooks.OnTooltipSetUnit(tt)
check(#tt.lines == 2 and tt.lines[1]:find("Banned in Horde Co for Scam", 1, true), "the tooltip shows the alliance's bans")
officer = false
tt = tooltip("Gul")
hooks.OnTooltipSetUnit(tt)
check(#tt.lines == 0, "not to a member")
officer = true

-- Before a manual invite: held for the officer's word.
dialogs = {}
local invited = 0
local function invite() invited = invited + 1 end
check(B:HoldInvite("Gul", invite) and invited == 0, "an invite to Gul waits")
check(#dialogs == 1 and dialogs[1].which == "GUILDOS_ALLIANCE_BAN_INVITE" and dialogs[1].text:find("The alliance has banned Gul:", 1, true)
      and dialogs[1].text:find("(under appeal)", 1, true), "the alert comes first")
local def = GuildOS.Dialogs.GUILDOS_ALLIANCE_BAN_INVITE
check(def and def.button1 == "Invite anyway" and def.button2 == "Cancel", "Invite anyway / Cancel")
def.OnAccept({}, dialogs[1].data)
check(invited == 1, "Invite anyway invites")
if def.OnCancel then def.OnCancel({}, dialogs[1].data) end
check(invited == 1, "Cancel does not")
check(not B:HoldInvite("Thrall", invite) and #dialogs == 1, "somebody the alliance has not banned: no hold")
officer = false
check(not B:HoldInvite("Gul", invite), "a member's invite is never held")
officer = true

-- The guild's own ban holds a manual invite first (audit M2), alone or with the alliance's.
B:Add("Thrall", "ninja")
dialogs, invited = {}, 0
check(B:HoldInvite("Thrall", invite) and invited == 0, "an invite to somebody the guild banned waits")
check(#dialogs == 1 and dialogs[1].which == "GUILDOS_ALLIANCE_BAN_INVITE" and dialogs[1].text:find("Banned Thrall (ninja)", 1, true)
      and not dialogs[1].text:find("The alliance has banned", 1, true), "the guild's ban, its reason and who, is said")
GuildOS.Dialogs.GUILDOS_ALLIANCE_BAN_INVITE.OnAccept({}, dialogs[1].data)
check(invited == 1, "Invite anyway invites past the guild's ban")
B:Add("Gul", "scam")
dialogs = {}
check(B:HoldInvite("Gul", invite) and dialogs[1].text:find("^Banned Gul %(scam%)") and dialogs[1].text:find("The alliance has banned Gul:", 1, true),
  "both bans: the guild's first, then the alliance's")
B:RemoveKey(B:_NormalizeKey("Thrall")); B:RemoveKey(B:_NormalizeKey("Gul"))
dialogs = {}

-- Every manual guild invite asks first; the auto-invite does not.
local function src(rel) return assert(io.open(ADDON .. "/" .. rel, "rb")):read("*a") end
check(src("Modules/RecruitmentSystem.lua"):find("BL:HoldInvite(target, invite)", 1, true), "/gos recruit invite asks")
check(src("Modules/JoinRequests.lua"):find("BL:HoldInvite(name, function() JR:Invite(id, true) end)", 1, true), "a join request's Invite asks")
check(src("UI/RosterFrame.lua"):find("BL:HoldInvite(target, send)", 1, true), "the roster's invite field asks")
check(src("Core/Utils.lua"):find("BL:HoldInvite(name, send)", 1, true), "Alt+Click asks")
local auto = src("Modules/RecruitmentSystem.lua"):match("function Recruitment:_InviteNow(.-)\nend\n")
check(auto and not auto:find("HoldInvite", 1, true), "the auto-invite is never held")
local banSrc = src("Modules/BanList.lua")
local isBanned = banSrc:match("function BanList:IsBanned(.-)\nend\n")
check(isBanned and not isBanned:find("Alliance", 1, true), "IsBanned does not look at the alliance")
check(not banSrc:find("db.banList[^\n]*ally", 1, false) and not src("Modules/CompanionImport.lua"):find("db%.allianceBans"),
  "the alliance's bans are never written to the saved variables")

-- ── 4. Retail: the realm tells namesakes apart ──────────────────────────
B, Import = load(true)
check(GuildOS.Client.isRetail, "the stub is retail")
BLOCK = { allianceBans = { { id = "r1", key = "Gul-Gallywix", name = "Gul", guild = "Other", reason = "scam", at = NOW } } }
check(B:AllianceBansFor("Gul-Gallywix") and B:AllianceBansFor("gul-gallywix"), "the same key matches, in any case")
check(B:AllianceBansFor("Gul-Azralon") == nil and B:AllianceBansFor("Gul") == nil,
  "a namesake on another realm, or this realm's Gul, is somebody else")
BLOCK = { allianceBans = { { id = "r2", key = "Ana-Tol Barad", name = "Ana", guild = "Other", reason = "scam", at = NOW } } }
check(B:AllianceBansFor("Ana-TolBarad"), "a realm with a space meets the roster's")
B:Add("Bob-Gallywix", "x")
check(B:Share("bob-gallywix", "other") and B:ForExport()[1].key == "Bob-Gallywix" and B:ForExport()[1].name == "Bob",
  "retail: the export's key keeps the realm")

-- ── 5. The self-tests the client runs ───────────────────────────────────
for _, retail in ipairs({ false, true }) do
  B = load(retail)
  local registered = {}
  GuildOS.SelfTest = { Register = function(_, name, fn) registered[#registered + 1] = { name = name, fn = fn } end }
  B:_RegisterTests()
  local mine = 0
  for _, t in ipairs(registered) do
    if t.name:find("^banlist%.alliance") then mine = mine + 1 end
    local ok, why = t.fn()
    check(ok, "selftest " .. t.name .. ": " .. tostring(why))
  end
  check(mine == 2, "the alliance's self-tests register")
end

-- ── Review fixes: an old client's tombstone keeps the share as withdrawn; the key is the roster's spelling ──
do
  local BL = GuildOS.BanList
  local key = BL:_NormalizeKey("Zed")
  GuildOS.db.banList[key] = { name = "zed", ts = 1, share = { reason = "scam", at = 5 } }
  local realSync = GuildOS.SyncService
  GuildOS.SyncService = { ShouldApply = function() return true end, SetRevision = function() end }
  do
    BL:_ApplyRemote(key, { name = "zed", ts = 9, removed = true }, 999999)
    local e = GuildOS.db.banList[key]
    check(e.share and e.share.withdrawnAt, "an old client's lift keeps the share, withdrawn")
  end
  GuildOS.SyncService = realSync
  GuildOS.db.members = GuildOS.db.members or {}
  local mk = GuildOS:KeyOfRosterName("Zed")
  GuildOS.db.members[mk] = {}
  check(BL:_MemberKey("zed") == mk, "the export key is the roster's own spelling")
  GuildOS.db.members[mk] = nil
  check(BL:_MemberKey("nobody"):sub(1, 1) == "N", "a name nobody on the roster has is capitalised")
end
print(("alliance-bans: %d checks passed"):format(checks))
