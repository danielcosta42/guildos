-- The disciplinary record (issue #402, the site's specs/116), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua and Modules/Discipline.lua under a stubbed client.
--
-- An officer files and revokes; the record reaches the other officers and never a member; two copies of
-- one warning settle on the newer change, and on a tie on the revoked one; the term and the ladder are
-- the guild's, newest stamp wins; the export is what the site's door takes.
--
--   luajit -e 'ADDON="."' tools/discipline.lua
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
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local NOW = 1790000000
function GetServerTime() return NOW end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/Discipline.lua")

local D = GuildOS.Discipline
local officer = true
function GuildOS:IsOfficer() return officer end
GuildOS.Compat.PlayerName = function() return "Arthas" end
local sent = {}
GuildOS.SyncService = {
  On = function() end,
  Publish = function(_, dom, act, data, opts) sent[#sent + 1] = { dom = dom, act = act, data = data, rev = opts and opts.rev } end,
}
GuildOS.db = { settings = {}, altLinks = {} }
D:Initialize()

local THRALL = GuildOS:GetPlayerKey("Thrall")

-- ── Filing and revoking ─────────────────────────────────────────────────
local w = D:Add(THRALL, "language", { note = "xingou | no /g\n", excerpt = "linha |Hitem:1|h[x]|h\r" })
check(w and w.level == 1 and w.subject == THRALL and w.by == "Arthas", "an officer files a first warning")
check(w.id:match("^g%d+%-%x+$") and #w.id <= 40, "the id is the site's shape")
check(w.note == "xingou no /g", "the note is one line with no pipe")
check(w.excerpt == "linha |Hitem:1|h[x]|h ", "the excerpt keeps the game's links on one line")
check(#sent == 1 and sent[1].dom == "discipline" and sent[1].data.warnings[1].id == w.id, "and it goes to the officers")
check(sent[1].data.warnings[1].excerpt == nil and GuildOS.db.discipline.warnings[w.id].excerpt ~= nil,
      "the chat line never goes on the wire, and stays with the officer who filed it")
check(D:Add(THRALL, "spam", { excerpt = "\r\n " }) and true, "a blank line is no excerpt")
for id, e in pairs(GuildOS.db.discipline.warnings) do
  if e.reason == "spam" then check(e.excerpt == nil, "a blank chat line is dropped"); GuildOS.db.discipline.warnings[id] = nil end
end
check(D:Add(THRALL, "rude") == nil, "an unknown reason is refused")
NOW = NOW + 60
local w2 = D:Add(THRALL, "spam")
check(w2.level == 2 and D:StepOf(THRALL) == 2, "the second one is step 2")
NOW = NOW + 60
check(D:Revoke(w2.id) and D:StepOf(THRALL) == 1, "revoked, it stops counting")
check(not D:Revoke(w2.id), "a warning revoked once is not revoked again")
check(GuildOS.db.discipline.warnings[w2.id].revokedBy == "Arthas", "the revocation is a field: the warning stays")

officer = false
check(D:Add(THRALL, "spam") == nil and not D:Revoke(w.id), "a member files nothing and revokes nothing")

-- ── The term moves every warning ────────────────────────────────────────
officer = true
NOW = w.at + 31 * 86400
check(D:StepOf(THRALL) == 0, "past the 30-day term, nothing counts")
check(D:SetTerm("45") and D:StepOf(THRALL) == 1, "a longer term brings the warning back")
check(select(2, D:SetTerm(0)) == "range" and D:GetTerm() == 45, "a term out of range is refused as it is")

-- ── Sync among officers ─────────────────────────────────────────────────
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
local incoming = { id = "g1-AAAA", subject = "Jaina-Classic Beta PvE", by = "Uther", reason = "trade", at = NOW, changedAt = NOW, level = 1 }
officer = false
D:OnSync({ act = "set", data = { warnings = { incoming } } })
check(GuildOS.db.discipline.warnings["g1-AAAA"] == nil, "a member's client stores nothing it hears")
officer = true
D:OnSync({ act = "set", data = { warnings = { incoming } } })
local held = GuildOS.db.discipline.warnings["g1-AAAA"]
check(held and held.subject == GuildOS:GetPlayerKey("Jaina"), "an officer keeps it, under this client's key (#97)")
local revoked = copy(incoming); revoked.revokedAt, revoked.changedAt = NOW, NOW
D:OnSync({ act = "set", data = { warnings = { revoked } } })
D:OnSync({ act = "set", data = { warnings = { incoming } } })
check(GuildOS.db.discipline.warnings["g1-AAAA"].revokedAt == NOW, "a tie goes to the revoked copy, whichever came last")
local held2 = GuildOS.db.discipline.warnings["g1-AAAA"]
held2.excerpt = "kept here"
local newer = copy(revoked); newer.changedAt = NOW + 1; newer.revokedAt = NOW + 1
D:OnSync({ act = "set", data = { warnings = { newer } } })
check(GuildOS.db.discipline.warnings["g1-AAAA"].excerpt == "kept here", "a newer copy keeps the chat line this client holds")
local future = copy(incoming); future.id = "g3"; future.at = NOW + 3600; future.changedAt = NOW + 3600
D:OnSync({ act = "set", data = { warnings = { future } } })
check(GuildOS.db.discipline.warnings.g3 == nil, "a warning from the future is refused")
local forged = copy(incoming); forged.id = "d:123"
D:OnSync({ act = "set", data = { warnings = { forged, { id = "g2" } } } })
check(GuildOS.db.discipline.warnings["d:123"] == nil and GuildOS.db.discipline.warnings.g2 == nil, "a Discord id or a malformed one is dropped")

-- ── The guild's term and ladder off the network ─────────────────────────
local s = GuildOS.db.settings
local at = s.disciplineTermAt
D:OnConfigSync({ act = "discterm", rev = at - 10, data = { days = 7 } })
check(D:GetTerm() == 45, "an older stamp loses")
D:OnConfigSync({ act = "discterm", rev = at, data = { days = 60 } })
check(D:GetTerm() == 45, "the same second settles on the shorter term")
D:OnConfigSync({ act = "discterm", rev = at, data = { days = 10 } })
check(D:GetTerm() == 10, "the shorter term wins the tie")
D:OnConfigSync({ act = "discladder", rev = NOW + 5, data = { ladder = { { action = "kick" } } } })
check(D:GetLadder() == D.DEFAULT_LADDER, "an unknown action is refused")
D:OnConfigSync({ act = "discladder", rev = NOW + 5, data = { ladder = { { action = "none" }, { action = "tempban", days = 3 } } } })
check(#D:GetLadder() == 2 and D.RungFor(D:GetLadder(), 9).days == 3, "a ladder heard is kept, and past its end the last rung")

-- ── The account group and Discord's warnings ────────────────────────────
local ALT = GuildOS:GetPlayerKey("Thrallalt")
GuildOS.db.altLinks[ALT] = THRALL
local discord = { { id = "d:1", subject = THRALL, by = "Jaina", reason = "spam", at = NOW, changedAt = NOW, level = 1, discord = true } }
local record = D:Record(ALT, nil, discord)
check(#record == 3, "an alt's record is the whole group's, with Discord's")
check(record[1].discord and record[1].id == "d:1", "newest first, Discord's marked")

-- ── Discord's warnings, through the import ──────────────────────────────
dofile(ADDON .. "/Modules/CompanionImport.lua")
local Import = GuildOS.CompanionImport
local BLOCK = { discordWarnings = {
  { id = "d:ckx1", subject = "Thrall", by = "Ja|cffina", at = NOW, reason = "spam", level = 1, note = "linha\nquebrada" },
  { id = "d:ckx2", subject = "Thrall", by = "Jaina", at = NOW, reason = "spam", level = 2, revokedAt = NOW + 1 },
  { id = "ckx3", subject = "Thrall", by = "Jaina", at = NOW, reason = "spam", level = 1 },
  { id = "d:ckx4", subject = "Thrall", by = "Jaina", at = NOW, reason = "rude", level = 1 },
} }
function Import:GuildBlock() return BLOCK end
local dw = Import:DiscordWarnings()
check(#dw == 2 and dw[1].id == "d:ckx1" and dw[1].discord, "only Discord's ids and known reasons come in, under their own id")
check(dw[1].by == "Jacffina" and not dw[1].note:find("\n"), "the text is made inert")
check(dw[2].revokedAt == NOW + 1 and dw[2].changedAt == NOW + 1, "a revocation comes down")
check(dw[1].subject == GuildOS:GetPlayerKey("Thrall"), "keyed as this client keys the member")
check(D:DiscordWarnings()[1].id == "d:ckx1", "and the record reads them from the import")

-- ── The backfill is bounded ─────────────────────────────────────────────
local bstore = {}
for i = 1, 150 do bstore["b" .. i] = { id = "b" .. i, changedAt = NOW - i * 3600 } end
bstore.old = { id = "old", changedAt = NOW - 400 * 86400 }
local bset = D:BackfillSet(bstore, NOW, 30)
check(#bset == D.BACKFILL_MAX and bset[1].id == "b1", "the newest 100, newest first")
for _, e in ipairs(bset) do check(e.id ~= "old", "nothing outside the term and a month") end

-- ── The export ──────────────────────────────────────────────────────────
local out = D:ForExport()
check(out.termDays == 10 and out.termAt == s.disciplineTermAt, "the term goes with its stamp")
check(#out.warnings == 3 and out.warnings[1].changedAt >= out.warnings[#out.warnings].changedAt, "newest change first")
for _, e in ipairs(out.warnings) do check(not e.discord, "Discord's never go back up") end
-- What the site's door (cleanDiscipline) takes, field by field.
local ALLOWED = { id = 1, subject = 1, by = 1, at = 1, reason = 1, note = 1, excerpt = 1, level = 1, revokedAt = 1, revokedBy = 1, changedAt = 1 }
local function int(v) return type(v) == "number" and v == math.floor(v) and v >= 1 and v <= 4294967295 end
for _, e in ipairs(out.warnings) do
  for f in pairs(e) do check(ALLOWED[f], "the door knows every field: " .. f) end
  check(e.id:match("^[%w:_%-]+$") and #e.id <= 40 and not e.id:find("^d:"), "id")
  check(int(e.at) and int(e.changedAt) and e.changedAt >= e.at and e.level >= 1 and e.level <= 10, "times and level")
  check(e.revokedAt == nil or (int(e.revokedAt) and e.changedAt >= e.revokedAt), "revokedAt")
  check(e.note == nil or (#e.note <= 200 and e.note:match("%S") and not e.note:find("[|%c]")), "note")
  check(e.excerpt == nil or (#e.excerpt <= 255 and e.excerpt:match("%S") and not e.excerpt:find("%c")), "excerpt")
  check(not e.subject:find("|", 1, true) and not e.by:find("|", 1, true), "names")
end
for i = 1, D.EXPORT_MAX + 5 do
  GuildOS.db.discipline.warnings["g9-" .. i] = { id = "g9-" .. i, subject = THRALL, by = "Arthas", reason = "other", at = NOW - 10000, changedAt = NOW - 10000 + i, level = 1 }
end
out = D:ForExport()
local ids = {}
for _, e in ipairs(out.warnings) do ids[e.id] = true end
check(#out.warnings == D.EXPORT_MAX and ids["g9-" .. (D.EXPORT_MAX + 5)] and not ids["g9-1"], "at most 500, the newest")
officer = false
check(D:ForExport() == nil, "a member's client exports none")

-- ── Pruning ─────────────────────────────────────────────────────────────
officer = true
local st = { a = { id = "a", at = 1, changedAt = 1, excerpt = "x" }, b = { id = "b", at = NOW, changedAt = NOW, excerpt = "y" },
             c = { id = "c", at = NOW - 100 * 86400, changedAt = NOW - 100 * 86400, excerpt = "z" } }
check(D:Prune(NOW, st) == 1 and st.a == nil, "past 400 days a warning goes")
check(st.b.excerpt == "y" and st.c.excerpt == nil and st.c.id == "c", "past 90 days only the chat line goes")

-- ── The self-tests the client runs ──────────────────────────────────────
local registered = {}
GuildOS.SelfTest = { Register = function(_, name, fn) registered[#registered + 1] = { name = name, fn = fn } end }
D:_RegisterTests()
for _, t in ipairs(registered) do
  local ok, why = t.fn()
  check(ok, "selftest " .. t.name .. ": " .. tostring(why))
end

print(("discipline: %d checks passed"):format(checks))
