-- The moderation presets as saved Bulk actions rule sets (audit B8), run against the real Modules/BulkActions.lua and
-- Modules/ModPresets.lua: unknown attendance is no low attendance, the safe list and the rank limits hold, the promote
-- threshold is the one Suggestions read (80), Apply queues in Bulk actions.
--
--   lua5.1 -e 'ADDON="."' tools/mod-presets.lua
ADDON = ADDON or "."
local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then io.stderr:write("FAIL: " .. what .. "\n"); os.exit(1) end
end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), db = { settings = {} } }
GuildOS.Finite = function(v) v = tonumber(v); if v and v == v and v > -math.huge and v < math.huge then return v end end
function GuildOS:IsOfficer() return true end
function GuildOS:GetSetting(k) return self.db.settings[k] end
function GuildOS:KeyOfRosterName(n) return n end
function GuildOS:Print() end
GuildOS.Compat = { PlayerName = function() return "Me" end }
dofile(ADDON .. "/Modules/BulkActions.lua")
dofile(ADDON .. "/Modules/ModPresets.lua")
local MP, BA = GuildOS.ModPresets, GuildOS.BulkActions
GuildOS.db.modPresets = { { type = "promote_regulars", name = "x", thresholds = { minAttendance = 90 } } }
MP:Initialize()
check(MP:PromoteAttendance() == 80 and MP.TYPES.promote_regulars.defaults.minAttendance == 80,
  "the old 90% default becomes the 80% Suggestions use")
check(MP:GetAction({ type = "trial_cleanup" }) == "remove", "a clean-up is a Bulk removal")
local ctx = { myRank = 1, lowestRank = 9, meKey = "Me" }
local trials = { type = "trial_cleanup", thresholds = { minDays = 14, maxAttendance = 50 } }
local out = MP.Match(trials, {
  { key = "A", rankIndex = 8, trial = true, trialDays = 20, attendance = 10 },
  { key = "B", rankIndex = 8, trial = true, trialDays = 20 },
  { key = "C", rankIndex = 8, trial = true, trialDays = 20, attendance = 50 },
  { key = "D", rankIndex = 8, trial = true, trialDays = 5, attendance = 0 },
  { key = "E", rankIndex = 8, attendance = 0 },
}, ctx, 1)
check(#out == 1 and out[1].key == "A", "a trial with no raids tracked is not a removal; only a known low one past its days")
local purge = { type = "purge_inactive", thresholds = { days = 30, minRankIndex = 4 } }
out = MP.Match(purge, {
  { key = "A", rankIndex = 5, daysOffline = 40 }, { key = "S", rankIndex = 5, daysOffline = 40, safe = true },
  { key = "O", rankIndex = 1, daysOffline = 99 }, { key = "R", rankIndex = 3, daysOffline = 99 },
  { key = "Me", rankIndex = 6, daysOffline = 99 }, { key = "N", rankIndex = 6, daysOffline = 10 },
}, ctx, 1)
check(#out == 1 and out[1].key == "A", "the safe list, my rank, the preset's rank floor and the days all hold")
local promo = { type = "promote_regulars", thresholds = { minAttendance = 80 } }
out = MP.Match(promo, {
  { key = "A", rankIndex = 5, attendance = 80 }, { key = "B", rankIndex = 5, attendance = 79 },
  { key = "T", rankIndex = 5, attendance = 95, trial = true }, { key = "U", rankIndex = 5 },
  { key = "S", rankIndex = 5, attendance = 99, safe = true }, { key = "X", rankIndex = 2, attendance = 99 },
}, ctx, 1)
local got = {}
for _, m in ipairs(out) do got[m.key] = true end
check(got.A and got.S and not got.B and not got.T and not got.U and not got.X,
  "promotion at 80%: not a trial, not unknown, not up to my rank; the safe list may still be promoted")
-- Apply: into Bulk actions' queue.
local started
BA.StartListAndSay = function(_, action, list) started = { action, list }; return true end
BA.ListFor = function(_, keys) return keys end
check(MP:ApplyPreset(trials, { { name = "A", key = "A" } }) and started[1] == "remove" and started[2][1] == "A",
  "Apply queues the members in Bulk actions")
print(("mod-presets: %d checks passed"):format(checks))
