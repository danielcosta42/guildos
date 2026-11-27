-- The Iniciar raide button on screen (issue #400; the site's #603, spec 115): the owner's prompt, the Now tab's next
-- raid and the Web tab, run against the real UI/WebPanel.lua, UI/Agora.lua, Helpers and CompanionImport on
-- tools/dashboard-layout.lua's stub frames (a method the stub does not know raises) under a WoW: Forever client.
-- One label and one gate in all three: the step's label, greyed with the reason under it while it cannot run, never
-- hidden in the prompt; "Raid ready" closes the prompt and is a state elsewhere; the Now tab shows the button only
-- while a raid of the site is in its window and this player may lead its invites; the Web tab's Invite and Groups
-- are the one button now.
--
--   luajit -e 'ADDON="."' tools/raid-start-ui.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
SALAO_KIT = true
local kit = dofile(ADDON .. "/tools/salao-layout.lua")
SALAO_KIT = nil
local check, fire, flush = kit.check, kit.fire, kit.flush

kit.client({ style = "forever", officer = true })
local NOW = kit.NOW
-- The kit's client predates surnames: WoW: Forever's are on (Compat read C_PlayerInfo at load).
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
GuildOS.Client.has.surnames = true

-- ── The client around the button: me, Chehul Costa, and a group the test sets ────────────────
-- The group: { first name, surname, raid group }; GROUP[1] is me.
local GROUP, RAID, LEADER = {}, false, true
function UnitName(unit)
  if unit == "player" then return "Chehul" end
  local kind, i = tostring(unit):match("^(%a+)(%d+)$")
  i = tonumber(i)
  local g = (kind == "raid" and GROUP[i]) or (kind == "party" and i and GROUP[i + 1])
  if g then return g[1], g[2] end
end
function UnitFullName() return "Chehul", "Costa" end
function UnitClass() return "Warrior", "WARRIOR" end
function GetNumGroupMembers() return #GROUP end
function IsInRaid() return RAID end
function IsInGroup() return #GROUP > 0 end
function UnitIsGroupLeader(unit) return unit == "player" and #GROUP > 0 and LEADER end
function UnitIsGroupAssistant() return false end
function UnitIsUnit(a, b) return a == b or (b == "player" and RAID and a == "raid1") end
function InCombatLockdown() return false end
function GetRaidRosterInfo(i)
  local g = RAID and GROUP[i]
  if g then return g[1] .. " " .. g[2], 0, g[3] end
end
local INVITED = {}
C_PartyInfo = { InviteUnit = function(name) INVITED[#INVITED + 1] = name end }
C_GuildInfo = { GuildRoster = function() end }
function GetNumGuildMembers() return 0 end
function UIFrameFadeIn() end   -- a popup's fade-in (Helpers:StylePopup)

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
  minor = 1,
}, {
  __call = function(_, name, silent)
    if registry[name] or silent then return registry[name] end
    error("no lib " .. name)
  end,
})
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/Modules/CompanionExport.lua")
dofile(ADDON .. "/Modules/CompanionImport.lua")
dofile(ADDON .. "/UI/WebPanel.lua")
local Import, UI = GuildOS.CompanionImport, GuildOS.UI
check(GuildOS.Client.game == "FOREVER" and GuildOS.Compat.PlayerName() == "Chehul Costa", "the stub is Chehul Costa on WoW: Forever")
check(type(UI.CreateRaidStepper) == "function" and type(GuildOS.ShowRaidPrompt) == "function", "the button and the prompt exist")

-- A redraw that raises fails here, loudly, not in /gos errors. The home cards are not this test's.
GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end
GuildOS.db.settings.companion = true
GuildOS.Companion.Build = function() return "GOSCOMP1:x", 3 end

local ONYXIA = { raidId = "ony", title = "Onyxia", startsAt = NOW + 20 * 60, size = 10, owners = { "Chehul Costa" },
                 members = { { key = "Ana Lima", name = "Ana Lima", class = "WARRIOR", slot = "MELEE", group = 1 } },
                 signups = {} }
local function reset()
  INVITED = {}
  Import._asked = {}
  GROUP, RAID, LEADER = {}, false, true
end

-- ── The Salão (#445) ──────────────────────────────────────────────────────────────────────────────
reset()
Import._webRaids = { ONYXIA }
local now = kit.newFrame("Frame", UIParent)
now:Hide()
GuildOS:CreateSalaoPanel(now)
now:Show()
now:SetSize(976, 516)
flush()
local start = now.startRaid
check(start and start:IsVisible(), "the Now tab shows the button while a raid of the site is in its window")
check(start.label.text == "Invite (1)" and start:IsEnabled(), "with the step's label, on: " .. tostring(start.label.text))
check(now.startFor:IsVisible() and now.startFor.text == "Onyxia", "and the raid's name, the card showing no raid: " .. tostring(now.startFor.text))
check(start.why:IsVisible() and (start.why.text or "") == "", "nothing standing in the way, nothing said under it")
fire(start, "OnClick")
check(INVITED[1] == "Ana Lima", "its click invites: " .. table.concat(INVITED, ","))
check(start:IsVisible() and not start:IsEnabled() and start.label.text == "Start raid",
  "while she has not answered, the button is greyed, not hidden: " .. tostring(start.label.text))
check(start.why.text == "Waiting for the invited to answer.", "and says why under it: " .. tostring(start.why.text))
-- In somebody else's group, this player leads no invites: the Now tab shows no button.
GROUP, LEADER = { { "Chehul", "Costa" }, { "Ana", "Lima" } }, false
now.Refresh()
check(not start:IsVisible(), "in a group led by somebody else, the Now tab has no button")
-- No raid in the window: no button either.
reset()
Import._webRaids = { { raidId = "far", title = "BWL", startsAt = NOW + 5 * 3600, members = {}, signups = {} } }
now.Refresh()
check(not start:IsVisible() and not now.startFor:IsVisible(), "a raid five hours away puts no button on the Now tab")

-- ── The owner's prompt ───────────────────────────────────────────────────────────────────────
reset()
Import._webRaids = { ONYXIA }
GuildOS:ShowRaidPrompt(ONYXIA)
local p = _G.GuildOSRaidPromptFrame
check(p and p:IsVisible(), "the prompt shows")
check(p.title.text == "Onyxia", "with the raid's name: " .. tostring(p.title.text))
check(p.when.text == "Starts in 20 min · 1 going", "when it starts and how many are coming: " .. tostring(p.when.text))
check(p.go.label.text == "Invite (1)" and p.go:IsEnabled(), "and the button, with the step's label: " .. tostring(p.go.label.text))
check(p.later and p.later.label.text == "Later", "and Later")
-- Blocked: in a group, not its leader. Greyed, with the reason, never hidden.
GROUP, LEADER = { { "Chehul", "Costa" }, { "Ana", "Lima" } }, false
GuildOS:RefreshRaidSteppers()
check(p.go:IsVisible() and not p.go:IsEnabled(), "a step that cannot run leaves the prompt's button greyed, not hidden")
check(p.go.why.text == "Only the group's leader or an assistant can invite.", "with the reason under it: " .. tostring(p.go.why.text))
-- Who the prompt says was put off (Later, the close button): the login's digest then has its turn.
local putOff = {}
local RS = GuildOS.RaidStart
local dismissed = RS.PromptDismissed
RS.PromptDismissed = function(_, roster) putOff[#putOff + 1] = roster end
-- Ready: everyone in place. "Raid ready", and its click closes the prompt.
GROUP, RAID, LEADER = { { "Chehul", "Costa", 1 }, { "Ana", "Lima", 1 } }, true, true
GuildOS:RefreshRaidSteppers()
check(p.go.label.text == "Raid ready" and p.go:IsEnabled(), "a raid in place reads Raid ready: " .. tostring(p.go.label.text))
fire(p.go, "OnClick")
check(not p:IsVisible(), "and its click closes the prompt")
check(GuildOS:RaidPromptShowing() == nil, "and then no prompt is up")
check(#putOff == 0, "Raid ready does not put the prompt off: the digest keeps waiting")
-- Later closes it too.
reset()
GuildOS:ShowRaidPrompt(ONYXIA)
check(p:IsVisible() and GuildOS:RaidPromptShowing() == ONYXIA, "a second prompt shows again, and says for which raid")
fire(p.later, "OnClick")
check(not p:IsVisible(), "Later closes the prompt")
check(#putOff == 1 and putOff[1] == ONYXIA, "and puts it off")
GuildOS:ShowRaidPrompt(ONYXIA)
fire(p.close, "OnClick")
check(not p:IsVisible() and #putOff == 2, "the close button puts it off too")
RS.PromptDismissed = dismissed
-- A long offline list stays above Later: two lines at most.
check(p.go.why.maxLines == 2, "the prompt's reason line keeps to two lines: " .. tostring(p.go.why.maxLines))
-- A copy of the prompt's raid pasted since the inbox was read (new people, a moved start): the prompt acts on it.
reset()
GuildOS:ShowRaidPrompt(ONYXIA)
GuildOS.db.companionRoster = { raidId = "ony", title = "Onyxia", startsAt = NOW + 40 * 60, size = 10, pasted = true,
  members = { { key = "Ana Lima", name = "Ana Lima", group = 1 }, { key = "Bia Souza", name = "Bia Souza", group = 1 } },
  signups = {} }
GuildOS:RefreshRaidSteppers()
check(p.go.label.text == "Invite (2)" and p.when.text == "Starts in 40 min · 2 going",
  "the prompt reads the pasted copy of its raid: " .. tostring(p.go.label.text) .. " / " .. tostring(p.when.text))
GuildOS.db.companionRoster = nil
p:Hide()
-- A prompt in the game closes the digest still open, rather than stacking on it.
GuildOS.Digest = { frame = kit.newFrame("Frame", UIParent) }
GuildOS:ShowRaidPrompt(ONYXIA)
check(p:IsVisible() and not GuildOS.Digest.frame:IsVisible(), "the prompt does not stack on the digest")
p:Hide()

-- ── The Web tab ──────────────────────────────────────────────────────────────────────────────
reset()
Import._webRaids = { ONYXIA }
-- The address box of the first-run steps is an edit box, which the kit has not; it is not this test's.
UI.CreateInput = function(_, parent)
  local box = kit.newFrame("EditBox", parent)
  box.HighlightText, box.SetFocus, box.ClearFocus = function() end, function() end, function() end
  return box
end
local host = kit.newFrame("Frame", UIParent)
host:SetSize(800, 600)
local web = GuildOS:CreateWebPanel(host)
web:Hide()
web:Show()
flush()
check(kit.button(web, "Invite (1)") ~= nil, "the Web tab has the button, with the step's label")
check(kit.button(web, "Invite") == nil and kit.button(web, "Groups") == nil, "in place of the Invite and Groups buttons")
check(kit.button(web, "Bring roster") and kit.button(web, "Fit to plan") and kit.button(web, "Raid plan"),
  "and keeps Bring roster, Fit to plan and Raid plan")
check(web.state.enabled.start == true, "the panel's state says the button is on")
fire(kit.button(web, "Invite (1)"), "OnClick")
check(INVITED[1] == "Ana Lima", "its click invites: " .. table.concat(INVITED, ","))
web:Refresh()
check(web.state.enabled.start == false and web.state.reason == "Waiting for the invited to answer.",
  "then the button is off and the panel says why: " .. tostring(web.state.reason))
-- Ready is a state here, not a click.
GROUP, RAID, LEADER = { { "Chehul", "Costa", 1 }, { "Ana", "Lima", 1 } }, true, true
web:Refresh()
local ready = kit.button(web, "Raid ready")
check(ready ~= nil and not ready:IsEnabled(), "on the Web tab Raid ready is a state, off")
-- One Refresh lays the tab out once: the button's own repaint inside it does not lay it out again.
local relayouts, relayout = 0, web.Relayout
web.Relayout = function(...) relayouts = relayouts + 1; return relayout(...) end
web:Refresh()
check(relayouts == 1, "a Refresh lays the tab out once (" .. relayouts .. ")")
-- A burst of group changes refreshes it once at once and once at its end; combat, at once.
local refreshes, refresh = 0, web.Refresh
web.Refresh = function(...) refreshes = refreshes + 1; return refresh(...) end
local onEvent = web.scripts.OnEvent
onEvent(web, "GROUP_ROSTER_UPDATE")
onEvent(web, "GROUP_ROSTER_UPDATE")
onEvent(web, "GROUP_ROSTER_UPDATE")
check(refreshes == 1, "three group changes in a row refresh the tab once now (" .. refreshes .. ")")
flush()
check(refreshes == 2, "and once more when the burst ends (" .. refreshes .. ")")
onEvent(web, "PLAYER_REGEN_DISABLED")
check(refreshes == 3, "combat refreshes it at once")
web.Refresh, web.Relayout = refresh, relayout
-- Nothing loaded: what to do about it, not that no raid starts now.
reset()
Import._webRaids, GuildOS.db.companionRoster = nil, nil
web:Refresh()
check(web.state.reason == "Import a roster first." and web.state.enabled.start == false,
  "with nothing loaded the line says to import a roster: " .. tostring(web.state.reason))
-- The site's raids all another guild's: the line says whose.
Import._foreignLine = "The website's raids are for the guild Outra, not Chama."
web:Refresh()
check(web.state.reason == Import._foreignLine, "the site's raids for another guild: the line says so: " .. tostring(web.state.reason))
-- With a roster in hand (one pasted, another guild's included), its own step says what stands in the way.
GuildOS.db.companionRoster = ONYXIA
GROUP, LEADER = { { "Chehul", "Costa" }, { "Ana", "Lima" } }, false
web:Refresh()
check(web.state.reason == "Only the group's leader or an assistant can invite.",
  "a roster in hand has the step's own reason, not the foreign line: " .. tostring(web.state.reason))
Import._foreignLine, GuildOS.db.companionRoster = nil, nil

print(string.format("raid-start-ui: %d checks passed", kit.count()))
