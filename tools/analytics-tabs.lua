-- Guild Analytics' tabs with "Max level only" on (issue #137), run against the real
-- Modules/GuildAnalytics.lua on stubbed frames: the Levels tab would hold one bar, so it steps
-- aside, the others close up, and a panel on Levels goes back to Class.
--
--   luajit -e 'ADDON="."' tools/analytics-tabs.lua
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

-- A frame that remembers what the panel did to it: shown, anchors, width, scripts.
local function frame(extra)
  local o = extra or {}
  o.shown = true; o.points = {}; o.w = o.w or 100; o.scripts = {}
  return setmetatable(o, { __index = function(_, k)
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "ClearAllPoints" then return function(s) s.points = {} end end
    if k == "SetPoint" then return function(s, ...) s.points[#s.points + 1] = { ... } end end
    if k == "GetWidth" then return function(s) return s.w end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    return function() return frame() end
  end })
end
function CreateFrame() return frame() end
UIParent = frame()
LOCALIZED_CLASS_NAMES_MALE, RAID_CLASS_COLORS = {}, {}
local roster = {
  { "A", "R0", nil, 60, nil, "Z", nil, nil, true, nil, "MAGE" },
  { "B", "R1", nil, 42, nil, "Z", nil, nil, true, nil, "ROGUE" },
}
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) return unpack(roster[i]) end

local col = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })
local tabs, boxes, dists = {}, {}, {}
GuildOS = {
  Client = { maxLevel = 60 }, Colors = col,
  L = setmetatable({}, { __index = function(_, k) return k end }),
  SafeCall = function(_, fn, ...) return fn(...) end,
}
GuildOS.UI = setmetatable({
  CreateTab = function(_, _, label, w)
    local t = frame({ w = w, label = label })
    t.SetActive = function(s, a) s.active = a end
    tabs[label] = t
    return t
  end,
  CreateCheckbox = function(_, _, label)
    local cb = frame({ checkbox = frame() })
    cb.checkbox.SetChecked = function() end
    boxes[label] = cb
    return cb
  end,
  CreateScrollFrame = function() return frame(), frame() end,
}, { __index = function() return function() return frame() end end })
dofile(ADDON .. "/Modules/GuildAnalytics.lua")
local A = GuildOS.GuildAnalytics
local orig = A.Distribution
A.Distribution = function(s, dim, on, r, mx) dists[#dists + 1] = { dim = dim, mx = mx }; return orig(s, dim, on, r, mx) end

local function x(t) return t.points[1] and t.points[1][2] end
A:Show()
check(tabs.Levels.shown and x(tabs.Class) == 16 and x(tabs.Levels) == 122 and x(tabs.Ranks) == 228 and x(tabs.Zones) == 334,
  "four tabs, side by side")
tabs.Levels.scripts.OnClick()
check(A._dim == "level" and tabs.Levels.active, "Levels open")
boxes["Max level only"].checkbox.onChanged(nil, true)
check(A._dim == "class" and tabs.Class.active and not tabs.Levels.active, "the filter on Levels goes back to Class")
check(not tabs.Levels.shown and x(tabs.Ranks) == 122 and x(tabs.Zones) == 228, "Levels steps aside, the others close up")
check(#tabs.Ranks.points == 1, "each refresh anchors a tab once, never on top of the last")
check(dists[#dists].dim == "class" and dists[#dists].mx == true, "and the bars count only the cap")
boxes["Max level only"].checkbox.onChanged(nil, false)
check(tabs.Levels.shown and x(tabs.Levels) == 122 and x(tabs.Ranks) == 228, "off again: Levels back in its place")
-- Closed on Levels with the filter on, and opened again: still on Class, Levels still aside.
A._dim = "level"; A._maxOnly = true
A.frame:Hide(); A:Show()
check(A._dim == "class" and not tabs.Levels.shown, "opened again with the filter on, Levels stays aside")

print(("analytics-tabs: %d checks passed"):format(checks))
