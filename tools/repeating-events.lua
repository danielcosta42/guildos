-- Events that repeat in the addon's calendar (issue #267), run against the real Modules/Calendar.lua
-- under stubbed WoW APIs.
--
-- "Every Tuesday, every other day, every 3rd Friday, every 1st of the month." A series is plain
-- events, one per date, each carrying the rule: an addon from before this sees ordinary events, every
-- date keeps its own answers, and the id is the series' plus the date, so two officers filling the
-- same series in reach the same events instead of two copies. The calendar holds the next four weeks
-- and an officer's client fills the rest in as days pass.
--
--   luajit -e 'ADDON="."' tools/repeating-events.lua
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

-- ── WoW API surface ───────────────────────────────────────────────────
time, date = os.time, os.date
local function at(y, m, d, hh, mm) return os.time({ year = y, month = m, day = d, hour = hh or 20, min = mm or 0 }) end
local NOW = at(2026, 11, 3, 12)        -- a Tuesday
function GetServerTime() return NOW end
function IsInGuild() return true end
function GetRealmName() return "Firemaw" end
function UnitClass() return "Mage", "MAGE" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
LibStub = setmetatable({}, { __call = function() return {} end })

GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { calendar = { events = {}, deleted = {} } },
  Client = { isAnniversary = false, defaultRaidSize = 20 },
  Compat = { PlayerName = function() return "Chehul" end },
}
function GuildOS:SafeCall(fn, ...) return pcall(fn, ...) end
function GuildOS:Print() end
function GuildOS:GetPlayerKey(n, r) return n .. "-" .. r end
local officer = true
function GuildOS:IsOfficer() return officer end
local published = {}
GuildOS.SyncService = {
  NextRevision = function() return #published + 1 end,
  Publish = function(_, dom, act, data) published[#published + 1] = { dom = dom, act = act, data = data } end,
  ShouldApply = function() return true end,
  SetRevision = function() end,
}
dofile(ADDON .. "/Modules/Calendar.lua")
local Cal = GuildOS.Calendar
local function dayOf(ts) return os.date("%Y-%m-%d %H:%M", ts) end

-- ── The dates a rule makes (pure) ────────────────────────────────────
local tue = at(2026, 11, 3)            -- Tuesday 3 Nov, 20:00
local function dates(rep, first, from, to, cap)
  local out = {}
  for _, ts in ipairs(Cal._Occurrences({ rep = rep }, first, from, to, cap or 50)) do out[#out + 1] = dayOf(ts) end
  return out
end
local w = dates("weekly", tue, tue, at(2026, 11, 30, 23))
check(#w == 4 and w[1] == "2026-11-03 20:00" and w[4] == "2026-11-24 20:00", "every week: the same weekday and hour")
local b = dates("biweekly", tue, tue, at(2026, 12, 31, 23))
check(b[2] == "2026-11-17 20:00" and b[3] == "2026-12-01 20:00", "every two weeks")
local e = dates("everyother", tue, tue, at(2026, 11, 9, 23))
check(#e == 4 and e[2] == "2026-11-05 20:00" and e[4] == "2026-11-09 20:00", "every other day")
check(#dates("daily", tue, tue, at(2026, 11, 9, 23)) == 7, "every day")
local fri3 = at(2026, 11, 20)          -- the third Friday of November
local n = dates("monthnth", fri3, fri3, at(2027, 2, 28, 23))
check(n[1] == "2026-11-20 20:00" and n[2] == "2026-12-18 20:00" and n[3] == "2027-01-15 20:00" and n[4] == "2027-02-19 20:00",
  "every month on the 3rd Friday")
local first = at(2026, 12, 1)
local d = dates("monthday", first, first, at(2027, 3, 31, 23))
check(#d == 4 and d[2] == "2027-01-01 20:00" and d[4] == "2027-03-01 20:00", "every 1st of the month")
local the31 = at(2026, 12, 31)
local d31 = dates("monthday", the31, the31, at(2027, 3, 31, 23))
check(#d31 == 3 and d31[2] == "2027-01-31 20:00" and d31[3] == "2027-03-31 20:00",
  "a month without day 31 (February) is skipped, never moved")
local fifth = at(2026, 12, 29)         -- the 5th Tuesday of December
check(#dates("monthnth", fifth, fifth, at(2027, 3, 31, 23)) == 2, "a month without a 5th Tuesday is skipped (March 2027 has one)")
check(#dates("weekly", tue, at(2026, 11, 17, 12), at(2026, 11, 30, 23)) == 2, "only from where the window starts")
check(#dates("daily", tue, tue, at(2027, 12, 31), 5) == 5, "never more than the cap")
check(#dates("none", tue, tue, at(2026, 12, 31)) == 1, "a rule that does not repeat is its first date")
check(dates("weekly", tue, tue, at(2026, 11, 30, 23), 50)[1] == dayOf(tue), "the first date is the one chosen")
check(Cal.RepeatOf("monthnth", fri3).nth == 3 and Cal.RepeatOf("monthnth", fri3).wday == 6, "the rule reads the 3rd Friday off the date")

-- ── Creating a series ────────────────────────────────────────────────
local n0 = Cal:CreateSeries("Kara", tue, 10, "bring pots", "RAID", false, "weekly")
check(n0 == 4, "four weeks ahead: four events")
local evs = {}
for _, ev in pairs(Cal:GetEvents()) do evs[#evs + 1] = ev end
table.sort(evs, function(x, y) return x.when < y.when end)
check(#evs == 4 and evs[1].title == "Kara" and evs[4].when == at(2026, 11, 24), "plain events, one per date")
local sid = evs[1].series and evs[1].series.id
check(sid and evs[4].series.id == sid and evs[1].series.rep == "weekly", "each carries the rule")
check(evs[1].id == sid .. ":20261103" and evs[2].id == sid .. ":20261110", "the id is the series' and the date")
check(#published == 4 and published[1].act == "create" and published[1].data.event.series.id == sid,
  "each one goes out as an ordinary event, with its rule")
officer = false
check(Cal:CreateSeries("X", tue, 10, "", "RAID", false, "weekly") == nil, "only an officer creates a series")
officer = true

-- ── Filling in as the days pass ──────────────────────────────────────
NOW = at(2026, 11, 12, 12)
local added = Cal:TopUpSeries()
check(added == 2 and Cal:GetEvents()[sid .. ":20261201"] and Cal:GetEvents()[sid .. ":20261208"], "a week later, the next ones")
check(Cal:TopUpSeries() == 0, "twice changes nothing")
Cal:Delete(sid .. ":20261117")
check(Cal:TopUpSeries() == 0 and not Cal:GetEvents()[sid .. ":20261117"], "a date deleted by hand is not brought back")
Cal:Rsvp(sid .. ":20261124", "yes", "DPS")
check(Cal:GetEvents()[sid .. ":20261124"].rsvps["Chehul-Firemaw"].status == "yes" and
  next(Cal:GetEvents()[sid .. ":20261201"].rsvps) == nil, "every date keeps its own answers")
officer = false
NOW = at(2026, 11, 20, 12)
check(Cal:TopUpSeries() == 0, "a member's client fills nothing in")
officer = true

-- ── Changing every date from one on ──────────────────────────────────
Cal:UpdateSeries(sid .. ":20261124", "Karazhan", at(2026, 11, 24, 21, 30), 10, "new note", "RAID", nil)
local E = Cal:GetEvents()
check(E[sid .. ":20261124"].title == "Karazhan" and os.date("%H:%M", E[sid .. ":20261124"].when) == "21:30",
  "the one edited changes")
check(E[sid .. ":20261208"].title == "Karazhan" and dayOf(E[sid .. ":20261208"].when) == "2026-12-08 21:30",
  "and every later date, each on its own day at the new hour")
check(E[sid .. ":20261110"].title == "Kara", "an earlier date stays as it was")
check(E[sid .. ":20261124"].rsvps["Chehul-Firemaw"], "answers survive the change")
NOW = at(2026, 11, 26, 12)
Cal:TopUpSeries()
check(E[sid .. ":20261222"] and E[sid .. ":20261222"].title == "Karazhan" and os.date("%H:%M", E[sid .. ":20261222"].when) == "21:30",
  "dates filled in later follow the change")

-- ── Ending a series ──────────────────────────────────────────────────
Cal:EndSeries(sid .. ":20261208")
check(not E[sid .. ":20261208"] and not E[sid .. ":20261215"] and not E[sid .. ":20261222"], "that date and every later one go")
check(E[sid .. ":20261201"] and E[sid .. ":20261110"], "earlier ones stay")
NOW = at(2026, 12, 20, 12)
check(Cal:TopUpSeries() == 0, "and nothing comes back, weeks later")
check(E[sid .. ":20261201"].series.untilT and E[sid .. ":20261201"].series.untilT < at(2026, 12, 8, 21, 30),
  "the dates that stay say where it ended, for every client")

-- ── Ending writes one update and one end mark, not the whole history (review) ──
NOW = at(2026, 11, 3, 12)
local n2 = Cal:CreateSeries("Daily", at(2026, 11, 3, 18), 10, "", "OTHER", false, "daily")
check(n2 == 16, "a daily series holds what the cap allows")
local d2 = {}
for id, ev in pairs(Cal:GetEvents()) do if ev.title == "Daily" then d2[#d2 + 1] = id end end
table.sort(d2)
local sid2 = Cal:GetEvents()[d2[1]].series.id
local before = #published
Cal:EndSeries(d2[10])
local updates, ends = 0, 0
for i = before + 1, #published do
  local p = published[i]
  if p.act == "update" then updates = updates + 1 end
  if p.act == "delete" and p.data.id == sid2 and p.data.series then ends = ends + 1 end
end
check(updates == 1, "only the latest date before the end says where it ended")
check(ends == 1 and Cal:IsSeriesEnded(sid2), "and the series itself is marked ended, for every client")

-- An officer who missed the end still has a date with no mark. It is not filled in from, and what
-- that officer creates is dropped by everyone who knows the series ended.
for _, id in ipairs(d2) do
  local ev = Cal:GetEvents()[id]
  if ev then ev.series.untilT = nil end
end
NOW = at(2026, 11, 20, 12)
check(Cal:TopUpSeries() == 0, "an ended series is never filled in again")
Cal:OnSync({ act = "create", rev = 5, data = { event = { id = sid2 .. ":20261125", title = "Daily", when = at(2026, 11, 25, 18),
  series = { id = sid2, rep = "daily", first = at(2026, 11, 3, 18), hour = 18, min = 0 } } } }, "Stale-Firemaw")
check(not Cal:GetEvents()[sid2 .. ":20261125"], "a date a stale officer creates for it is dropped")
Cal:OnSync({ act = "delete", rev = 9, data = { id = "S9", series = true } }, "Other-Firemaw")
check(Cal:IsSeriesEnded("S9"), "an end another officer sends is kept")

-- ── An officer on another clock fills nothing in (review) ────────────
NOW = at(2026, 11, 3, 12)
local off = Cal:CreateSeries("Late", at(2026, 11, 4, 20), 10, "", "RAID", false, "weekly")
check(off == 4, "a series to read on another clock")
local lateSid
for _, ev in pairs(Cal:GetEvents()) do if ev.title == "Late" then lateSid = ev.series.id; ev.series.hour = 23 end end
NOW = at(2026, 11, 20, 12)
local lateBefore = 0
for _, ev in pairs(Cal:GetEvents()) do if ev.title == "Late" then lateBefore = lateBefore + 1 end end
Cal:TopUpSeries()
local lateAfter = 0
for _, ev in pairs(Cal:GetEvents()) do if ev.title == "Late" then lateAfter = lateAfter + 1 end end
check(lateSid and lateAfter == lateBefore,
  "dates that read another hour here than the series says: this client is on another clock, and fills nothing in")

-- ── A client before this edits a date: the date keeps its rule (review) ──
NOW = at(2026, 11, 3, 12)
Cal:CreateSeries("Keep", at(2026, 11, 5, 20), 10, "", "RAID", false, "weekly")
local keepId
for id, ev in pairs(Cal:GetEvents()) do if ev.title == "Keep" and id:sub(-8) == "20261112" then keepId = id end end
Cal:OnSync({ act = "update", rev = 50, data = { event = { id = keepId, title = "Keep edited", when = at(2026, 11, 12, 20) } } }, "Old-Firemaw")
check(Cal:GetEvents()[keepId].title == "Keep edited" and Cal:GetEvents()[keepId].series, "the edit lands and the rule stays")

-- ── A client before this sees plain events ───────────────────────────
local wire
for i = #published, 1, -1 do
  local ev = published[i].data.event
  if published[i].act == "update" and ev and ev.id:sub(1, #sid + 1) == sid .. ":" then wire = ev break end
end
check(wire and wire.series and wire.series.untilT, "an update carries the rule, ended")

-- ── What comes in off the guild channel is checked ───────────────────
Cal:OnSync({ act = "create", rev = 1, data = { event = { id = "in1", title = "t", when = NOW + 86400,
  series = { id = 7, rep = "weekly", first = NOW } } } }, "Other-Firemaw")
check(Cal:GetEvents().in1 and Cal:GetEvents().in1.series == nil, "a rule without a proper id is dropped, the event stays")
Cal:OnSync({ act = "create", rev = 1, data = { event = { id = "in2", title = "t", when = NOW + 86400,
  series = { id = "S2", rep = "fortnightly-ish", first = NOW } } } }, "Other-Firemaw")
check(Cal:GetEvents().in2.series == nil, "so is a repeat this client does not know")
Cal:OnSync({ act = "create", rev = 1, data = { event = { id = "S3:20261221", title = "t", when = NOW + 86400,
  series = { id = "S3", rep = "monthday", first = NOW, hour = 99, untilT = "x" } } } }, "Other-Firemaw")
local s3 = Cal:GetEvents()["S3:20261221"].series
check(s3 and s3.rep == "monthday" and s3.hour == nil and s3.untilT == nil, "a good rule is kept, its bad numbers are not")

print("repeating-events: " .. checks .. " checks passed")
