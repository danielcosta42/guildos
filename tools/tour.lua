-- The guided tour's engine (UI/Tour.lua), What's new (UI/Onboarding.lua), the help hub and the officers'
-- Get started card (specs/salao/onboarding.md), against the whole addon under the room harness's stub client
-- (tools/frame-leaks.lua's, up to its counting): anchors resolve, steps whose frame is missing are skipped, the
-- callout stays inside the window at 1000 and 452 px (docked at the bottom there), the keys, combat's pause and
-- resume, the window closed, the "?" tool and its red dot, Shift-click, and the login popup's one-per-login.
--
--   luajit -e 'ADDON="."' tools/tour.lua
--
-- Exits 1 when a check failed (all are listed).
ADDON = ADDON or "."
do
  local fh = assert(io.open(ADDON .. "/tools/frame-leaks.lua", "rb"))
  local src = fh:read("*a")
  fh:close()
  local cut = src:find("-- ── Counting what is made", 1, true)
  assert(cut, "frame-leaks.lua's harness marker")
  assert(loadstring(src:sub(1, cut - 1), "=frame-leaks-harness"))()
end

local checks, fails = 0, {}
local function check(cond, what)
  checks = checks + 1
  if not cond then fails[#fails + 1] = what end
end

local UI = GuildOS.UI
local Tour = UI.Tour
local O = GuildOS.Onboarding
check(Tour and O and UI.RegisterTourAnchor and UI.TourAnchor, "the tour, its anchors and the onboarding load")

-- ── 1. Placement (pure): inside the window at 1000 and 452 ─────────────────
local inside = true
for _, ww in ipairs({ 1000, 452 }) do
  local wh = 620
  local narrow = ww < Tour.NARROW_W
  for x = 0, ww - 40, 37 do
    for y = 0, wh - 30, 31 do
      for _, ch in ipairs({ 140, 220, 320 }) do
        local cx, cy, cw, side = Tour.Place(ww, wh, { x = x, y = y, w = 40, h = 30 }, ch, narrow)
        if cx < 0 or cy < 0 or cx + cw > ww or cy + ch > wh + 1 then inside = false end
        if narrow and side ~= "bottom" and side ~= "top" then inside = false end
        if narrow and side == "bottom" and y + 15 > wh / 2 then inside = false end
        if not narrow and cw ~= Tour.CALLOUT_W then inside = false end
      end
    end
  end
end
check(inside, "the callout stays inside the window at 1000 and 452 px, 320 wide, docked at 452")
local cx, cy, _, side = Tour.Place(1000, 620, { x = 100, y = 60, w = 80, h = 30 }, 160, false)
check(side == "below" and cy >= 60 + 30 and cx >= 8, "a frame near the top: the callout below it")
_, _, _, side = Tour.Place(1000, 620, { x = 100, y = 500, w = 80, h = 30 }, 160, false)
check(side == "above", "near the bottom: above it")
_, _, _, side = Tour.Place(1000, 620, { x = 100, y = 100, w = 80, h = 420 }, 200, false)
check(side == "beside", "a tall frame: beside it")
_, cy, _, side = Tour.Place(452, 620, { x = 10, y = 10, w = 40, h = 30 }, 200, true)
check(side == "bottom" and cy + 200 <= 620, "452 px: docked at the bottom")
_, _, _, side = Tour.Place(452, 620, nil, 200, false)
check(side == "center", "no frame: centred")

-- ── 2. The window, its "?" tool and the anchors ────────────────────────────
SlashCmdList.GUILDOS("")
pcall(FLUSH)
local f = GuildOS.RosterFrame
f:SetSize(1000, 620)
pcall(FLUSH)
check(f.helpButton and f.helpButton.shown, "the title bar has its ? tool")
check(UI:TourAnchor("tool.help") == f.helpButton and UI:TourAnchor("tool.search") == f.searchButton
  and UI:TourAnchor("tool.fold") == f.minimise, "the tools are anchors")
f:OpenRoom("salao", true)
pcall(FLUSH)
-- The stub lays nothing out by anchors: the Hall is given its size, as the game would.
f.tabPanels.home:SetSize(970, 520)
f.tabPanels.home.content:SetWidth(958)
pcall(f.tabPanels.home.Refresh)
pcall(FLUSH)
check(UI:TourAnchor("door.salao") ~= nil and UI:TourAnchor("door.salao").key == "salao", "a room's door is an anchor")
for _, k in ipairs({ "salao.fire", "salao.board", "entry.salao.chat" }) do
  check(UI:TourAnchor(k) ~= nil, "the Hall's " .. k .. " resolves")
end
f:OpenRoom("officers", true)
pcall(FLUSH)
check(UI:TourAnchor("side.ban") ~= nil, "the Officers' Room's side bar entries are anchors")
check(UI:TourAnchor("recruit.post") ~= nil or UI:TourAnchor("side.recruiting") ~= nil, "the recruiting screen's card, or its entry")
check(UI:TourAnchor("nope.nothing") == nil, "an unknown key is nil")

-- Shift-click on "?": the tour's chapter for this screen.
local started
local realStart = Tour.Start
Tour.Start = function(_, track, ch) started = { track, ch } return true end
for _, e in ipairs(UI:RoomEntries("officers")) do if e.id == "ban" then f:SelectEntry("officers", e, true) end end
f:OpenHelp(true)
check(started and started[1] == "officer" and started[2] == "mod", "Shift-click ? in the Ban List: the officers' Moderation chapter")
Tour.Start = realStart
f:OpenHelp(false)
check(f.activeRoom == "settings" and f.activeEntry and f.activeEntry.id == "help", "a click on ? opens Settings › Help")

-- The red dot: three Laters, then the dot, gone once the help is opened.
GuildOSDB._onboard = nil
GuildOS.db.settings.onboarded = true
for _ = 1, 3 do O:Later() end
f:RefreshHelpDot()
check(f.helpButton.dot.shown, "after three Laters the ? carries a red dot")
f:OpenRoom("salao", true)
f:OpenHelp(false)
f:RefreshHelpDot()
check(not f.helpButton.dot.shown, "opening the help takes it away")

-- ── 3. A whole member tour at 1000 px: every step on screen or skipped, the callout inside ─
GuildOSDB._onboard = nil
-- The stub cannot place frames: a fake rectangle per frame, inside the window, stands for the client's.
local rects = {}
Tour.RectOf = function(fr, win)
  if not fr then return nil end
  if not rects[fr] then
    local n = 0
    for _ in pairs(rects) do n = n + 1 end
    rects[fr] = { x = 20 + (n * 97) % 800, y = 40 + (n * 53) % 500, w = 90, h = 28 }
  end
  local ww = win:GetWidth()
  local r = rects[fr]
  return { x = math.min(r.x, ww - r.w - 4), y = r.y, w = r.w, h = r.h }
end
local function placedInside()
  local p = Tour.state.placed
  return p and p.x >= 0 and p.y >= 0 and p.x + p.w <= p.ww and p.y + p.h <= p.wh + 1
end
check(Tour:Start("member"), "the member tour starts")
local ov = Tour.overlay
check(ov and ov.shown and ov.co.shown, "its overlay and callout show")
local seen, allInside, steps = 0, true, #Tour.state.steps
local guard = 0
while Tour.state.mode == "tour" and guard < 40 do
  guard = guard + 1
  seen = seen + 1
  local st = Tour.state.steps[Tour.state.i]
  if not (Tour.state.anchorFrame or st.picture) then allInside = false end
  if not placedInside() then allInside = false end
  if f.activeRoom ~= st.room then allInside = false end
  Tour:Next()
  pcall(FLUSH)
end
check(Tour.state.mode == "end", "the tour ends on its last card")
check(seen >= steps - 4 and seen <= steps, "every step shown or skipped (" .. seen .. " of " .. steps .. ")")
check(allInside, "each step opens its room, points at its frame (or shows its picture), the callout inside")
check(O:Progress("member").done, "the track is recorded done")
Tour:Next()   -- the end card's main button: the officers' tour for an officer
check(Tour.state.mode == "tour" and Tour.state.track == "officer", "an officer goes on to the Officers' Room tour")

-- A step whose frame is missing is skipped.
Tour:Stop()
local saved = Tour.anchors["salao.fire"]
Tour.anchors["salao.fire"] = function() return nil end
O:Progress("member").done, O:Progress("member").step = nil, 1
Tour:Start("member")
Tour:Next()
check(Tour.state.steps[Tour.state.i].id == "board", "By the fire missing: the tour goes from the Hall to the notice board")
Tour.anchors["salao.fire"] = saved

-- ── 4. The keys ─────────────────────────────────────────────────────────
local key = ov.co.scripts.OnKeyDown
local i0 = Tour.state.i
key(ov.co, "RIGHT"); pcall(FLUSH)
check(Tour.state.i == i0 + 1, "Right: next")
key(ov.co, "LEFT"); pcall(FLUSH)
check(Tour.state.i == i0, "Left: back")
key(ov.co, "ENTER"); pcall(FLUSH)
check(Tour.state.i == i0 + 1, "Enter: next")
local here = Tour.state.i

-- ── 5. Combat pauses it, the same step comes back ─────────────────────────
ov.events.scripts.OnEvent(ov.events, "PLAYER_REGEN_DISABLED")
check(not ov.shown and Tour.state.paused == "combat", "combat hides it")
ov.events.scripts.OnEvent(ov.events, "PLAYER_REGEN_ENABLED")
pcall(FLUSH)
check(ov.shown and Tour.state.i == here and not Tour.state.paused, "combat over: back on the same step")

-- The window closed pauses it; the footer offers to resume.
f:Hide()
check(Tour.state.paused == "closed" and not ov.shown, "the window closed pauses it")
f:Show()
pcall(FLUSH)
check(not ov.shown and f.tourOffer.shown, "opened again: the footer offers to resume, the tour waits")
f.tourOffer.scripts.OnClick(f.tourOffer)
pcall(FLUSH)
check(ov.shown and Tour.state.i == here, "Resume: the same step")

key(ov.co, "ESCAPE")
check(not Tour:Running() and not ov.shown, "Escape: skipped")
check(f.activeEntry and f.activeEntry.id == "help", "and the help shows where to resume it")
check(O:StartIndex("member") == here, "the progress kept for Resume")

-- ── 6. 452 px: docked at the bottom, inside ───────────────────────────────
f:SetSize(452, 620)
pcall(FLUSH)
check(f.band == "watch", "the window is in the watch band")
Tour:Start("officer", "recruit")
pcall(FLUSH)
local p = Tour.state.placed
check(p and p.x == 8 and p.w == 452 - 16 and (p.side == "bottom" or p.side == "top") and placedInside(),
  "at 452 the callout spans the window, docked")
check(UI:TourAnchor("door.officers") == f.selector, "a door at the watch band is the room selector")
Tour:Stop()
f:SetSize(1000, 620)
pcall(FLUSH)

-- ── 7. Show me (a one-step tour) ───────────────────────────────────────────
local item = O:Checklist("officer")[1]
check(Tour:ShowMe(item.go, item.title, item.desc), "Show me opens its screen with one callout")
check(f.activeRoom == item.go.room and Tour.state.mode == "one" and ov.shown, "on the item's room")
key(ov.co, "ENTER")
check(not Tour:Running(), "Got it closes it")

-- ── 8. What's new ──────────────────────────────────────────────────────────
GuildOSDB._onboard = nil
GuildOS.db.settings.onboarded = true
local w = GuildOS:ShowWhatsNew(false)
check(w and w.shown and w.kind == "whatsnew" and #w.cards == 6, "What's new: six cards for an existing user")
check(w.subText and tostring(w.subText.text):find("2.0", 1, true), "named 2.0 · the Salão")
check(w.w <= 560 and w.h >= 452, "560 wide; it only grows in height")
w.scripts.OnKeyDown(w, "RIGHT")
check(w.i == 2 and w.backBtn.shown, "Right: the next card")
w.scripts.OnKeyDown(w, "LEFT")
check(w.i == 1, "Left: back")
w.scripts.OnKeyDown(w, "ESCAPE")
check(not w.shown and GuildOSDB._onboard.later == 1, "Escape is Later, counted")
check(Tour:FooterOffer() ~= nil, "and the footer offers the tour this session")
w = GuildOS:ShowWhatsNew(false)
w.neverBtn.scripts.OnClick(w.neverBtn)
check(GuildOSDB._onboard.feature == "2.0" and not w.shown, "Got it: closed until the next release")
GuildOSDB._onboard = nil
GuildOS.db.settings.onboarded = nil
for k, v in pairs(GuildOSDB) do if GuildOS.IsGuildDBKey(k, v) and v.settings then v.settings.onboarded = nil end end
w = GuildOS:ShowWhatsNew(false)
check(w.kind == "welcome" and #w.cards == 4 and not w.neverBtn.shown, "a new player: the welcome, no Got it")
for _ = 1, 3 do w.nextBtn.scripts.OnClick(w.nextBtn) end
check(w.rolePick.shown or w.i == 4, "the roles card has its picker")
w.nextBtn.scripts.OnClick(w.nextBtn)
pcall(FLUSH)
check(not w.shown and not O:Pending() and GuildOS.db.settings.onboarded, "Take the tour: seen, onboarded")
Tour:Stop()

-- One popup per login, never in an instance.
GuildOSDB._onboard = nil
GuildOS.db.settings.onboarded = true
O.session.shown = false
local realInst = IsInInstance
IsInInstance = function() return true end
GuildOS:MaybeShowOnboarding()
pcall(FLUSH)
check(not (GuildOS.onboardingFrame and GuildOS.onboardingFrame.shown) and not O.session.shown, "inside an instance it waits")
IsInInstance = realInst
GuildOS:MaybeShowOnboarding()
for _ = 1, 3 do pcall(FLUSH) end
check(O.session.shown, "out of it, it shows")
if GuildOS.onboardingFrame then GuildOS.onboardingFrame:Hide() end
local count = 0
local realShow = GuildOS.ShowWhatsNew
GuildOS.ShowWhatsNew = function(self, ...) count = count + 1; return realShow(self, ...) end
GuildOS:MaybeShowOnboarding()
for _ = 1, 3 do pcall(FLUSH) end
check(count == 0, "at most one onboarding popup each login")
GuildOS.ShowWhatsNew = realShow

-- ── 9. The help hub and the officers' card ─────────────────────────────────
for _, e in ipairs(UI:RoomEntries("settings")) do if e.id == "help" then f:SelectEntry("settings", e, true) end end
pcall(FLUSH)
local panel = f.tabPanels.settings
local info = panel and panel.subPanels and panel.subPanels.help
check(info and info.form and info.form.help and #info.form.help.tours == 4, "Settings › Help lists the tours")
check(info and #info.form.help.tiles == 12, "and the twelve guides for an officer")
check(info and #info.form.help.links == 3 and info.form.help.links[3].url == "https://discord.gg/8XA6gmNjja"
  and info.form.help.links[2].url == "https://guildos.me/manual", "the site, the manual and the Discord as copy boxes")
local g = UI.HelpPanel:OpenGuide("moderate")
check(g and g.shown and g.item.track == "officer", "a guide opens with its picture and Show me")
g:Hide()
f:OpenRoom("salao", true)
pcall(FLUSH)
local home = f.tabPanels.home
local setup = home and home.cards and home.cards.setup
check(setup and setup.title.text == GuildOS.L["Get started"], "the Hall's officers' card is Get started")

if #fails > 0 then
  for _, x in ipairs(fails) do print("FAIL: " .. x) end
  os.exit(1)
end
print(("tour: %d checks passed"):format(checks))
