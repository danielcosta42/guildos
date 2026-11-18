-- The Now cards' recruitment card with the module switched off (issue #84), run against the real
-- UI/Dashboard.lua and the Helpers it draws with, on tools/dashboard-layout.lua's stub client (#377).
--
-- With Recruitment off in Settings, the card still said "Guild is recruiting" and offered a
-- green "Helping" button (or the officer's "Broadcast now") for popups that would never come.
-- Since #377 both are ghost links, and "Helping" is the selected one.
--
--   luajit -e 'ADDON="."' tools/dashboard-recruit.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
DASHBOARD_KIT = true
local kit = dofile(ADDON .. "/tools/dashboard-layout.lua")
DASHBOARD_KIT = nil
local check = kit.check

kit.client({ style = "guildos" })
-- Whether this member may post (Recruitment:MemberMayPost: in a guild, within the officers' rank).
local mayPost = true
GuildOS.Recruitment = { MemberMayPost = function() return mayPost end, SetParticipation = function() end }

local panel
local function show(modules, rank, ad, participate)
  kit.setRank(rank)
  GuildOS.db = { settings = { modules = modules }, recruitParticipate = participate }
  if ad ~= false then GuildOS.db.guildRecruitment = { enabled = true, message = "We recruit" } end
  panel = kit.newFrame("Frame", UIParent)
  panel:SetSize(640, 516)
  local refresh = GuildOS:CreateDashboardPanel(panel)
  local ok, err = pcall(refresh)
  check(ok, "the dashboard draws (" .. tostring(err) .. ")")
end
local function said(text) return kit.shows(panel, text) end
local function offered(label) return kit.button(panel, label) end

-- ── 1. Module on: the card as it was ────────────────────────────────────
show({}, 5)
check(said("Guild is recruiting") and offered("Help spread it") and not offered("Helping"),
  "module on: a member who never chose sees the ad and is offered to help; helping is opt-in (#150)")
check(offered("Help spread it").variant == "ghost" and not offered("Help spread it").__selected, "as a ghost link")
show({}, 5, nil, true)
check(offered("Helping") and offered("Helping").__selected, "one who said they help sees Helping, the selected one")
mayPost = false
show({}, 5, nil, true)
check(not offered("Helping") and not offered("Help spread it"),
  "one past the officers' rank, or with no guild, is offered nothing")
mayPost = true
show({}, 0)
check(said("Guild is recruiting") and offered("Broadcast now") and offered("Broadcast now").variant == "ghost",
  "module on: an officer sees the ad and Broadcast now")

-- ── 2. Module off: says so, offers nothing ──────────────────────────────
for _, who in ipairs({ { 5, "a member" }, { 0, "an officer" } }) do
  show({ recruitment = false }, who[1])
  check(said("The Recruitment module is off. Turn it on in Settings > Modules."),
    "module off: " .. who[2] .. " is told the module is off and where to turn it on")
  check(not said("Guild is recruiting") and not offered("Helping")
    and not offered("Help spread it") and not offered("Broadcast now"),
    "module off: " .. who[2] .. " gets no ad and no button for popups that will not come")
end

-- Module off and no ad either: still the module, not the hidden tab, is named.
show({ recruitment = false }, 0, false)
check(said("The Recruitment module is off") and not said("Set it up in the Recruitment tab"),
  "module off with no ad: an officer is pointed at Settings, not at the tab the switch hid")

print(("dashboard-recruit: %d checks passed"):format(kit.count()))
