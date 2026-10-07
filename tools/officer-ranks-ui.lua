-- The OFFICER RANKS settings (issue #81), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Data.lua and UI/FeaturePanels.lua on a stubbed UI.
--
-- The checkboxes set the guild's threshold, not this account's. A choice made before the
-- threshold was the guild's was never stamped, so nobody sends it: a button shares it, and is
-- offered only for a real choice, never the default, which an officer who has not heard the
-- guild's yet would otherwise send over it.
--
--   luajit -e 'ADDON="."' tools/officer-ranks-ui.lua
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
function GuildControlGetNumRanks() return 4 end
function GuildControlGetRankName(i) return "Rank" .. (i - 1) end
local now = 1000
function GetServerTime() return now end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")

local buttons, boxes = {}, {}
local function widget(fields)
  local w = setmetatable(fields, { __index = stub })
  function w:SetScript(_, fn) self.onClick = fn end
  function w:Hide() self.hidden = true end
  return w
end
GuildOS.UI = setmetatable({
  GetFeature = function() return nil end,
  CreateButton = function(_, _, t) local b = widget({ text = tostring(t) }); buttons[#buttons + 1] = b; return b end,
  CreateCheckbox = function(_, _, label)
    local cb = widget({ checkbox = widget({}) })
    boxes[tostring(label)] = cb
    return cb
  end,
}, { __index = function() return function() return stub end end })
dofile(ADDON .. "/UI/FeaturePanels.lua")

local published = {}
GuildOS.SyncService = { Publish = function(_, dom, act, data, opts)
  published[#published + 1] = { dom = dom, act = act, max = data.max, rev = opts.rev }
end }

local function open(settings, rank)
  myRank = rank or 1
  GuildOS.db = { settings = settings }
  settings.modules = settings.modules or {}
  buttons, boxes, printed, published = {}, {}, {}, {}
  local ok, err = pcall(GuildOS.RefreshSettingsPanel, GuildOS, stub, "officer")
  check(ok, "the officer settings draw (" .. tostring(err) .. ")")
end
local function shareButton()
  for _, b in ipairs(buttons) do
    if b.text == "Share these ranks with the guild" then return b end
  end
end

-- ── 1. The share button: only for a choice made before #81 ──────────────
open({ officerMaxRank = 2 })
local share = shareButton()
check(share ~= nil, "a choice made before #81 (rank 2 ticked, never stamped) is offered to the guild")
share.onClick(share)
check(#published == 1 and published[1].dom == "guildcfg" and published[1].max == 2 and published[1].rev == now,
  "one click sends that choice, as it is, stamped")
check(GuildOS.db.settings.officerMaxRankAt == now and share.hidden, "and the button goes away")

open({ officerMaxRank = 1 })
check(shareButton() == nil, "the default is not offered: it would overwrite a choice this client has not heard yet")
open({})
check(shareButton() == nil, "nor is a threshold never set at all")
open({ officerMaxRank = 2, officerMaxRankAt = 900 })
check(shareButton() == nil, "nor one already stamped, from here or from the guild")

-- ── 2. The checkboxes set the guild's threshold ─────────────────────────
open({ officerMaxRank = 1, officerMaxRankAt = 900 })
local rank3 = boxes["Rank3"]
check(rank3 and rank3.checkbox.onChanged, "each rank has a checkbox")
rank3.checkbox.onChanged(nil, true)
check(GuildOS.db.settings.officerMaxRank == 3 and GuildOS.db.settings.officerMaxRankAt == now
  and #published == 1 and published[1].max == 3, "ticking rank 3 stamps and sends the guild's threshold")
local said = false
for _, m in ipairs(printed) do if m:find("Officer threshold: ranks 0-", 1, true) then said = true end end
check(said, "and says the new threshold")

-- No longer an officer while the panel is still open: nothing changes, nothing is said.
open({ officerMaxRank = 1, officerMaxRankAt = 900 })
local rank2 = boxes["Rank2"]
myRank = 5
printed, published = {}, {}
rank2.checkbox.onChanged(nil, true)
check(GuildOS.db.settings.officerMaxRank == 1 and #published == 0 and #printed == 0,
  "a client that is no longer an officer changes nothing and claims nothing")

print(("officer-ranks-ui: %d checks passed"):format(checks))
