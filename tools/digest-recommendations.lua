-- The officers' recommendations in the login digest (specs/salao/manutencao-roster.md), run against the real
-- Modules/Digest.lua, GuildManager, MemberHistory, MemberMarks, NoteDates and RosterMaint on tools/salao-layout.lua's
-- stub frames (a method the stub does not know raises) under a TBC Anniversary client:
--   * "N to review for inactivity": alt-aware (an alt whose main was seen is not inactive), without the safe list (a
--     mark past its end counts again), only for a rank that may remove members; it replaces the old count there;
--   * "N ready for promotion": the members long in their rank (RosterMaint:StuckInRank, every one, not the first 25),
--     only for a rank that may promote;
--   * never with N = 0, never for a member, never in the Activity screen's model (Collect without recommend);
--   * at login only beside other news (no popup of their own), and nothing when the digest is off;
--   * each line opens its Officers' Room screen (Inactivity, Suggestions); the line's button is pooled with the rest
--     of the popup, a redraw makes no new one.
--
--   luajit -e 'ADDON="."' tools/digest-recommendations.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
SALAO_KIT = true
local kit = dofile(ADDON .. "/tools/salao-layout.lua")
SALAO_KIT = nil
local check = kit.check

kit.client({ style = "guildos", officer = true })
local NOW, DAY = kit.NOW, 86400
local G = GuildOS
for _, f in ipairs({ "Modules/GuildManager.lua", "Modules/MemberHistory.lua", "Modules/MemberMarks.lua",
                     "Modules/NoteDates.lua", "Modules/RosterMaint.lua", "Modules/Digest.lua" }) do
  dofile(ADDON .. "/" .. f)
end
G.IsFeatureEnabled = function() return true end
function UIFrameFadeIn() end
function UIFrameFadeOut() end
G.Compat.PlayerName = function() return "Off" end

-- { name, rankIndex, online, daysOffline }
local roster = {
  { "Off-Realm", 1, true },
  { "Idle-Realm", 3, false, 60 },
  { "Kept-Realm", 3, false, 60 },      -- on the safe list for good
  { "Expired-Realm", 3, false, 60 },   -- on it until yesterday
  { "Altie-Realm", 4, false, 60 },     -- an alt of Mainy, who is online
  { "Mainy-Realm", 3, true },          -- 400 days in the rank
}
function GetNumGuildMembers() return #roster, #roster end
function GetGuildRosterInfo(i)
  local m = roster[i]
  if not m then return nil end
  return m[1], "Rank" .. m[2], m[2], 70, "Mage", "", "", "", m[3], 0, "MAGE"
end
function GetGuildRosterLastOnline(i)
  local m = roster[i]
  if not m or m[3] then return nil end
  return 0, 0, m[4] or 0, 0
end
local canRemove, canPromote = true, true
function CanGuildRemove() return canRemove end
function CanGuildPromote() return canPromote end
function CanViewOfficerNote() return true end
G.SyncService = { Publish = function() end, On = function() end }
local whenClear = {}
G.ShowWhenClear = function(_, id, fn) whenClear[#whenClear + 1] = id; return fn() end

local K = function(n) return G:KeyOfRosterName(n) end
local function reset()
  G.db = { settings = { modules = {} }, members = {}, calendar = { events = {} },
    digest = { enabled = true, lastSeen = NOW - 2 * DAY, feedSeen = {} },
    firstSeen = {}, firstSeenSince = NOW - 60 * DAY, rosterLog = { events = {} }, lootHistory = {},
    raidTracker = { sessions = {} }, memberHistory = {},
    altLinks = { [K("Altie-Realm")] = K("Mainy-Realm") } }
  G.db.memberHistory[K("Mainy-Realm")] = { stints = { { joinAt = NOW - 400 * DAY } }, ranks = {} }
  G.db.memberHistory[K("Idle-Realm")] = { stints = { { joinAt = NOW - 20 * DAY } }, ranks = {} }
  G.MemberMarks:SetSafe(K("Kept-Realm"), true)
  -- Marked a week ago for six days: its end is past (written as an officer's copy off the network).
  G.db.memberMarks.safe[K("Expired-Realm")] = { v = true, at = NOW - 7 * DAY, by = "Off", u = NOW - DAY }
  G.Digest.shownThisSession, G.Digest.deferred = nil, nil
  whenClear = {}
end
local function has(lines, s)
  for _, l in ipairs(lines) do if tostring(l):find(s, 1, true) then return true end end
  return false
end

-- ── The lines ───────────────────────────────────────────────────────────
reset()
check(G:IsOfficer(), "an officer")
local recs = G.Digest:Recommendations()
check(#recs == 2 and recs[1].id == "inactive" and recs[1].n == 2 and recs[2].id == "promote" and recs[2].n == 1,
  "two to review (Idle and the ended mark's Expired; Kept is safe, Altie's main was seen), one ready")
local lines = G.Digest:Build(NOW - 2 * DAY)
check(has(lines, "2 to review for inactivity") and has(lines, "1 ready for promotion"), "both in the digest")
check(not has(lines, "inactive member(s)"), "the old count gives way to the recommendation")
local members
for _, g in ipairs(lines.groups) do if g.id == "members" then members = g end end
check(members and members.actions, "the members' group carries the lines' screens")
local opens = {}
for i, l in ipairs(members.lines) do
  local a = members.actions[i]
  if a then opens[#opens + 1] = (l:find("review", 1, true) and "review" or "promote") .. ">" .. a[1] .. "/" .. a[2] end
end
check(table.concat(opens, ",") == "review>management/inactive,promote>management/suggest", "each line's screen: " .. table.concat(opens, ","))
check(not has(G.Digest:Collect(NOW - 2 * DAY).members.lines, "to review"), "the Activity screen's model has none (no recommend)")

-- ── Permissions and N = 0 ───────────────────────────────────────────────
canRemove = false
lines = G.Digest:Build(NOW - 2 * DAY)
check(not has(lines, "to review") and has(lines, "3 inactive member(s)") and has(lines, "ready for promotion"),
  "a rank that may not remove: the old count, no review line")
canRemove, canPromote = true, false
lines = G.Digest:Build(NOW - 2 * DAY)
check(has(lines, "to review") and not has(lines, "ready for promotion"), "a rank that may not promote: no promotion line")
canPromote = true
G.MemberMarks:SetSafe(K("Idle-Realm"), true)
G.MemberMarks:SetSafe(K("Expired-Realm"), true)
G.db.memberHistory[K("Mainy-Realm")].stints[1].joinAt = NOW - 10 * DAY
check(#G.Digest:Recommendations() == 0, "nobody left to review, nobody long in the rank: no line")
lines = G.Digest:Build(NOW - 2 * DAY)
check(not has(lines, "to review") and not has(lines, "ready for promotion"), "N = 0 is never said")
reset()
kit.setRank(5)
check(#G.Digest:Recommendations() == 0 and not has(G.Digest:Build(NOW - 2 * DAY), "to review"), "a member gets none")
kit.setRank(0)
-- Every one long in the rank counts, not only the suggestion list's first 25.
for i = 1, 30 do
  roster[#roster + 1] = { "Vet" .. i .. "-Realm", 3, true }
  G.db.memberHistory[K("Vet" .. i .. "-Realm")] = { stints = { { joinAt = NOW - 300 * DAY } }, ranks = {} }
end
check(#G.RosterMaint:StuckInRank() == 25 and G.Digest:Recommendations()[2].n == 31, "31 ready, though the list shows 25")
for _ = 1, 30 do roster[#roster] = nil end

-- ── The login ───────────────────────────────────────────────────────────
reset()
G.Digest:ShowOnLogin()
check(#whenClear == 0, "nothing else new at login: no popup only for the recommendations")
reset()
G.db.firstSeen[K("Newbie-Realm")] = NOW - 3600
G.Digest:ShowOnLogin()
local f = G.Digest.frame
check(#whenClear == 1 and f and f:IsShown() and kit.shows(f, "2 to review for inactivity") and kit.shows(f, "1 ready for promotion"),
  "beside other news, in the same digest")
reset()
G.db.firstSeen[K("Newbie-Realm")] = NOW - 3600
G.db.digest.enabled = false
f:Hide()
G.Digest:ShowOnLogin()
check(#whenClear == 0 and not f:IsShown(), "the digest off: nothing")
-- On demand they are said even alone.
reset()
check(has(G.Digest:Build(NOW - 2 * DAY), "to review"), "/gos digest says them with nothing else new")

-- ── A click opens the screen; the popup's parts are pooled ─────────────
reset()
local function links(frame)
  local out = {}
  kit.walk(frame, function(x) if x.kind == "Button" and x.open then out[#out + 1] = x end end)
  return out
end
local function shownLinks(frame)
  local out = {}
  for _, b in ipairs(links(frame)) do if b:IsShown() then out[#out + 1] = b end end
  return out
end
f = G.Digest:Show(G.Digest:Build(NOW - 2 * DAY))
local made = #links(f)
check(made == 2 and #shownLinks(f) == 2, "one button over each recommendation line")
local review
for _, b in ipairs(shownLinks(f)) do if b.open[2] == "inactive" then review = b end end
kit.opened = nil
kit.fire(review, "OnClick")
check(kit.opened and kit.opened[1] == "management" and kit.opened[2] == "inactive" and not f:IsShown(),
  "a click closes the digest and opens Inactivity")
for _ = 1, 5 do G.Digest:Show(G.Digest:Build(NOW - 2 * DAY)) end
check(#links(f) == made, "five redraws, no new button (" .. #links(f) .. ")")
canRemove = false
G.Digest:Show(G.Digest:Build(NOW - 2 * DAY))
check(#links(f) == made and #shownLinks(f) == 1 and shownLinks(f)[1].open[2] == "suggest", "one line fewer: its button hidden, not dropped")
canRemove = true
kit.opened = nil
kit.fire(shownLinks(f)[1], "OnClick")
check(kit.opened and kit.opened[2] == "suggest", "the promotion line opens Suggestions")

print(("digest-recommendations: %d checks passed"):format(kit.count()))
