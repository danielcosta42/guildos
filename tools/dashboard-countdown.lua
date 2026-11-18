-- The countdown on the Now cards with no client to try it on (issue #232), run against the real
-- UI/Dashboard.lua and the Helpers it draws with, on tools/dashboard-layout.lua's stub client (#377):
-- when it works, the slices of the guild; when it fails, in the module or in the drawing, the card it
-- replaced, with the rest of the cards drawn and the error in /guildos errors.
--
--   luajit -e 'ADDON="."' tools/dashboard-countdown.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
DASHBOARD_KIT = true
local kit = dofile(ADDON .. "/tools/dashboard-layout.lua")
DASHBOARD_KIT = nil
local check = kit.check

kit.client({ style = "guildos" })
GuildOS.Recruitment = { MemberMayPost = function() return true end, SetParticipation = function() end }

local panel
local function shown(text) return kit.shows(panel, text) end

local function show(countdown)
  GuildOS.db = { settings = { modules = {} }, guildRecruitment = { enabled = true, message = "We recruit" } }
  GuildOS.Readiness = { GetReport = function() return {} end, Countdown = countdown }
  GuildOS.State.errors = {}
  panel = kit.newFrame("Frame", UIParent)
  panel:SetSize(640, 516)
  local refresh = GuildOS:CreateDashboardPanel(panel)
  local ok, err = pcall(refresh)
  check(ok, "the dashboard draws (" .. tostring(err) .. ")")
end

local THE_OLD_CARD = "No readiness data yet"
local THE_REST = "Guild is recruiting"

-- ── It works: the slices ──────────────────────────────────────────
local function slices(ready, s)
  return function()
    return { open = false, days = 36, cap = 60, cores = {}, guild = { ready = ready, slices = s } }
  end
end
show(slices(27, { dungeons = 5, raids = { { size = 10, count = 2 }, { size = 20, count = 1 } } }))
check(shown("Can form") and shown("5 groups"), "27 at 60: the line of what the guild can form")
check(shown("2×10") and shown("1×20"), "with each raid's size")
check(shown(THE_REST), "and the rest of the cards")
check(not shown(THE_OLD_CARD), "the old card is not there")
check(panel.dash.cards[2].hdr.text == "RAIDS OPEN IN 36 DAYS", "the card says how far off the raids are")

show(slices(3, { dungeons = 0, raids = {}, short = 2, shortSize = 5 }))
check(not shown("Can form"), "nothing to form yet: no such line")

-- ── It fails: the card it replaced ────────────────────────────────
show(function() error("no such thing on this client") end)
check(shown(THE_OLD_CARD), "the module fails: the old card")
check(panel.dash.cards[2].hdr.text == "YOUR READINESS", "under its own title")
check(shown(THE_REST), "and the rest of the cards is drawn")
check(#GuildOS.State.errors == 1, "and /guildos errors has it")

show(function() return { cap = 60 } end)
check(shown(THE_OLD_CARD), "the drawing fails on what the module gave: the old card")
check(shown(THE_REST), "and the rest of the cards is drawn")
check(#GuildOS.State.errors == 1, "and /guildos errors has it")

-- ── Off Forever: the card it always was, and no error ─────────────
show(function() return nil end)
check(shown(THE_OLD_CARD) and #GuildOS.State.errors == 0, "no countdown here: the old card, and nothing recorded")

-- ── The guild's setup (issue #217) ────────────────────────────────────
local function setup(activation)
  GuildOS.Activation = activation
  show(function() return nil end)
  GuildOS.Activation = nil
end
setup({
  STEPS = { "publish", "bot", "account", "members", "run" },
  ShouldShow = function() return true end,
  Read = function() return { done = 2, steps = { publish = true, bot = true }, staleDays = 4 } end,
})
check(shown("SET UP GUILD OS FOR YOUR GUILD"), "the card, for who it is due")
check(shown("Publish through the companion") and shown("First group run"), "with its steps")
check(shown("Verified 4 days ago"), "and how old what the site said is")
check(shown(THE_REST), "and the rest of the cards")
local s = panel.dash.setup
check(s.shown and s.w == 640 and kit.at(s) == 0 and select(2, kit.at(panel.dash.cards[1])) == -(s.h + 12),
  "over the grid, across it, the cards under it (#377)")

setup({ STEPS = {}, ShouldShow = function() return false end })
check(shown(THE_REST) and #GuildOS.State.errors == 0 and not panel.dash.setup.shown, "not due: nothing changes")
check(select(2, kit.at(panel.dash.cards[1])) == 0, "and the grid starts at the top")

setup({ STEPS = {}, ShouldShow = function() error("no such thing on this client") end })
check(shown(THE_REST), "a failure leaves the cards as they were")
check(#GuildOS.State.errors == 1, "and /guildos errors has it")

-- ── The Achievements tab (issue #216): it draws, with something and with nothing ──
dofile(ADDON .. "/UI/AchievementsPanel.lua")
GuildOS.State.errors = {}
GuildOS.Achievements = {
  Renown = function() return 7, 700 end,
  Insignia = function() return "Interface/AddOns/GuildOS/Media/renown-horde-2", "Company" end,
  Next = function() return { { title = "Ready", current = 8, target = 10 } } end,
  Earned = function() return { { title = "First", at = 1000 } } end,
}
GuildOS:CreateAchievementsPanel(kit.newFrame("Frame", UIParent))
GuildOS.Achievements.Insignia = function() return nil, nil end   -- an older site: the line alone
GuildOS:CreateAchievementsPanel(kit.newFrame("Frame", UIParent))
GuildOS.Achievements = { Renown = function() return nil end }
GuildOS:CreateAchievementsPanel(kit.newFrame("Frame", UIParent))
check(#GuildOS.State.errors == 0, "the tab draws, with a block and without one (" .. tostring(GuildOS.State.errors[1]) .. ")")

print(("dashboard-countdown: %d checks passed"):format(kit.count()))
