-- The Trials panel (issue #249), run against the real Core/Core.lua, Core/Compat.lua, Core/Data.lua,
-- Core/Utils.lua, Modules/TrialTracker.lua and UI/FeaturePanels.lua on a stubbed UI.
--
-- The officer sets the guild's trial length and its switch for new members here, and a trial whose
-- time is up reads "ready to review", first in the list, with approve and deny, whatever word an older
-- client stored. tools/trial-guild.lua covers the rules; this covers the panel that drives them.
--
--   luajit -e 'ADDON="."' tools/trial-panel.lua
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

-- Any frame, any field, any method: numbers where the layout does arithmetic, itself elsewhere.
local NUM = { GetWidth = 600, GetHeight = 400, GetFrameLevel = 1, GetStringHeight = 12, GetStringWidth = 40,
              GetNumChildren = 0 }
local stub
stub = setmetatable({}, {
  __index = function(_, k)
    if NUM[k] then return function() return NUM[k] end end
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    return stub
  end,
  __call = function() return stub end,
})
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
function CreateFrame() return stub end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Off" end
function IsInGuild() return true end
local myRank = 1
function GetGuildInfo() return "Guild", "Rank", myRank end
function GetNumGuildMembers() return 0, 0 end
local DAY, T0 = 86400, 1794139200
local now = T0
function GetServerTime() return now end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/TrialTracker.lua")
function GuildOS:IsOnGuildDB() return true end
local TT = GuildOS.TrialTracker

-- What the panel draws and wires, as it draws it.
local texts, buttons, boxes, saves = {}, {}, {}, {}
local function widget(fields)
  local w = setmetatable(fields, { __index = stub })
  function w:SetScript(_, fn) self.onClick = fn end
  function w:SetChecked(v) self.checked = v end
  function w:SetText(v) self.text = v end
  function w:GetText() return self.text end
  return w
end
GuildOS.UI = setmetatable({
  GetFeature = function() return nil end,
  CreateText = function(_, _, t) local w = widget({ text = tostring(t) }); texts[#texts + 1] = w; return w end,
  CreateButton = function(_, _, t) local b = widget({ text = tostring(t) }); buttons[#buttons + 1] = b; return b end,
  CreateCheckbox = function(_, _, label)
    local cb = widget({ checkbox = widget({}) })
    boxes[tostring(label)] = cb
    return cb
  end,
  AttachSaveButton = function(_, box, fn) saves[#saves + 1] = fn; box.saveButton = stub; return stub end,
}, { __index = function() return function() return stub end end })
dofile(ADDON .. "/UI/FeaturePanels.lua")

local published = {}
GuildOS.SyncService = { Publish = function(_, dom, act, data, opts)
  published[#published + 1] = { dom = dom, act = act, data = data, rev = opts.rev }
end }

local panel
local function open(db)
  GuildOS.db = db
  db.settings = db.settings or {}
  db.settings.officerMaxRank = 1
  db.settings.modules = db.settings.modules or {}
  db.members = db.members or {}
  texts, buttons, boxes, saves, printed, published = {}, {}, {}, {}, {}, {}
  panel = widget({})
  local ok, err = pcall(GuildOS.CreateTrialsPanel, GuildOS, panel)
  check(ok, "the Trials panel builds (" .. tostring(err) .. ")")
end
local function refresh()
  texts, buttons = {}, {}
  local ok, err = pcall(GuildOS.RefreshTrialsPanel, GuildOS, panel)
  check(ok, "the Trials panel draws its rows (" .. tostring(err) .. ")")
end
local function shown(s)
  for i, w in ipairs(texts) do if w.text == s then return i end end
end
local function count(label)
  local n = 0
  for _, b in ipairs(buttons) do if b.text == label then n = n + 1 end end
  return n
end
local function typed(v)
  local box = widget({ text = v })
  saves[#saves](box)
  return box
end

-- ── 1. The settings row ─────────────────────────────────────────────────
local db = { trials = {} }
open(db)
check(shown("Trial length (days)") and boxes["Every new member starts as a trial"] and #saves == 1,
  "an officer finds the length and the switch in the Trials panel")
refresh()
check(panel.trialAutoCb.checked == false, "the switch reads off by default")
for _, bad in ipairs({ "", "0", "91", "100" }) do
  printed, published = {}, {}
  local box = typed(bad)
  check(TT:GetDays() == 30 and #published == 0 and box.text == "30", "typing \"" .. bad .. "\" changes nothing, and the box shows 30 again")
  check(printed[1] and printed[1]:find("Trial length must be a whole number of days from 1 to 90.", 1, true),
    "and the officer is told why")
end
printed = {}
typed("45")
check(TT:GetDays() == 45 and published[1].act == "trialdays" and printed[1]:find("Trials now last 45 days", 1, true),
  "45 is taken, sent to the guild, and said")
boxes["Every new member starts as a trial"].checkbox.onChanged(boxes["Every new member starts as a trial"].checkbox, true)
check(TT:IsAutoOn() and published[#published].act == "trialauto", "the checkbox turns the switch on for the guild")
myRank = 5
local cb = boxes["Every new member starts as a trial"].checkbox
cb.onChanged(cb, false)
check(TT:IsAutoOn() and cb.checked == true, "a client that is no longer an officer cannot turn it off: the box shows what holds")
printed = {}
typed("10")
check(TT:GetDays() == 45 and #printed == 0, "nor change the length, and is not told it typed a bad one")
myRank = 1

-- ── 2. The rows ─────────────────────────────────────────────────────────
now = T0 + 20 * DAY
db = { settings = { trialDays = 14 }, trials = {
  ["Run-Realm"]  = { startDate = T0 + 15 * DAY, endDate = T0 + 45 * DAY, status = "trial", notes = {}, sponsor = "Off" },
  ["Due-Realm"]  = { startDate = T0, endDate = T0 + 30 * DAY, status = "trial", notes = {}, sponsor = "Off" },
  ["Old-Realm"]  = { startDate = T0 + DAY, endDate = T0 + 2 * DAY, status = "expired", notes = {}, sponsor = "Off2" },
  ["Done-Realm"] = { startDate = T0 + 19 * DAY, status = "approved", notes = {}, sponsor = "Off", resolvedDate = T0 + 20 * DAY },
} }
open(db)
refresh()
local due, old, run, done = shown("Due"), shown("Old"), shown("Run"), shown("Done")
check(due and old and run and done and due < run and old < run and run < done,
  "ready to review first, then running, then decided")
local review = 0
for _, w in ipairs(texts) do if w.text == "READY TO REVIEW" then review = review + 1 end end
check(review == 2 and shown("TRIAL") and shown("APPROVED"), "Due and Old read ready to review, Run is a trial, Done approved")
check(not shown("EXPIRED") and not shown("expired"), "\"expired\" is never shown")
check(count("OK") == 3 and count("X") == 3, "approve and deny on every trial nobody decided, ready to review included")
check(panel.statusText.text == "3 active trials", "the count is of the trials nobody decided")
db.settings.trialDays = 60
refresh()
review = 0
for _, w in ipairs(texts) do if w.text == "READY TO REVIEW" then review = review + 1 end end
check(review == 0 and shown("TRIAL"), "the guild lengthens its trials: nobody is ready to review any more, Old included")

-- ── 3. Somebody who left: with the decided, and not counted ─────────────
db.settings.trialDays = 14
db.trials["Due-Realm"].leftAt = now
refresh()
local gone, decided = shown("Due"), shown("Done")
check(shown("LEFT THE GUILD") and gone and gone > shown("Run"), "a trial whose member left reads so, listed with the decided")
check(decided and panel.statusText.text == "2 active trials", "and is not counted among the active ones")
review = 0
for _, w in ipairs(texts) do if w.text == "READY TO REVIEW" then review = review + 1 end end
check(review == 1, "only Old is still ready to review")

-- ── 4. A setting from another officer redraws the open panel ────────────
texts = {}
panel.trialAutoCb.checked = nil
TT:OnConfigSync({ act = "trialauto", rev = now + 10, data = { on = true } })
check(TT:IsAutoOn() and panel.trialAutoCb.checked == true and shown("Run"), "the switch heard from the guild shows at once")
texts = {}
TT:OnConfigSync({ act = "trialdays", rev = now + 10, data = { days = 60 } })
check(TT:GetDays() == 60 and shown("Run") and not shown("READY TO REVIEW"), "and so does the length, with the rows redrawn")

print(("trial-panel: %d checks passed"):format(checks))
