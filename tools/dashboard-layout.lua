-- The Now tab as the approved sketch (issue #377, Agora.dc.html), run against the real UI/Agora.lua
-- and UI/Dashboard.lua on the real Core/Core.lua, Core/Compat.lua, Core/Data.lua, Core/Style.lua,
-- Core/Utils.lua, UI/Helpers.lua and UI/Layout.lua under a stub frame API, in both interface styles:
-- "guildos" on a TBC Anniversary client and "forever" on a WoW: Forever one.
--
-- The column's sections (next raid, needs me, activity) have no box: a section title, and a 1px
-- `line` rule 12px over every title but the first. The countdown is the Mono 40 role, in paper; the
-- calendar is a ghost link. At the default window (a 976px tab) the column and the cards are three
-- equal columns, the cards a 2x3 grid of equal `panel` cells; under 780px the cards go under the
-- column, below a rule, two columns while each keeps 240px and one under that. Every card still
-- carries what it did: the answer to the next event, readiness or the raids countdown, the pulse,
-- recruitment, loot, the chat, and the guild's setup over the grid while it is due.
--
-- tools/dashboard-chat.lua, dashboard-countdown.lua and dashboard-recruit.lua load this file with
-- DASHBOARD_KIT set, for its stub client alone.
--
--   luajit -e 'ADDON="."' tools/dashboard-layout.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local kit = {}
local checks = 0
function kit.check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end
function kit.count() return checks end
local check = kit.check

-- ── A frame that keeps what the code does to it ─────────────────────────
-- A method this stub does not know raises, so a typo fails here and not in the game.
local M = {}
local VERBS = { "Set", "Get", "Is", "Has", "Clear", "Create", "Enable", "Disable", "Register", "Hook", "Show",
                "Hide", "Raise", "Lower", "Start", "Stop", "Add", "Can" }
local meta = { __index = function(_, k)
  if M[k] then return M[k] end
  if type(k) == "string" then
    for _, v in ipairs(VERBS) do
      if k:find("^" .. v .. "%u") or k == v then error("the stub has no method " .. k, 2) end
    end
  end
  return nil
end }
local function newFrame(kind, parent)
  local f = setmetatable({ kind = kind, parent = parent, children = {}, points = {}, scripts = {}, shown = true,
                           w = 0, h = 0, alpha = 1, events = {} }, meta)
  if parent then parent.children[#parent.children + 1] = f end
  return f
end
kit.newFrame = newFrame
local function fire(f, script, ...) local fn = f.scripts[script]; if fn then return fn(f, ...) end end
kit.fire = fire
local function cascade(f, script)
  if not f.shown then return end
  fire(f, script)
  for _, c in ipairs(f.children) do cascade(c, script) end
end
function M:SetSize(w, h) self.w, self.h = w, h; fire(self, "OnSizeChanged", w, h) end
function M:SetWidth(w) self.w = w; fire(self, "OnSizeChanged", self.w, self.h) end
function M:SetHeight(h) self.h = h; fire(self, "OnSizeChanged", self.w, self.h) end
function M:GetWidth() return self.w end
function M:GetHeight() return self.h end
function M:SetPoint(...) self.points[#self.points + 1] = { ... } end
function M:ClearAllPoints() self.points = {} end
function M:SetAllPoints(other) self.points = { { "ALL", other } } end
function M:GetParent() return self.parent end
function M:IsShown() return self.shown end
function M:IsVisible()
  local f = self
  while f do
    if not f.shown then return false end
    f = f.parent
  end
  return true
end
function M:Show()
  if self.shown then return end
  self.shown = true
  if not self.parent or self.parent:IsVisible() then cascade(self, "OnShow") end
end
function M:Hide()
  if not self.shown then return end
  if self:IsVisible() then cascade(self, "OnHide") end
  self.shown = false
end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:SetScript(name, fn) self.scripts[name] = fn end
function M:GetScript(name) return self.scripts[name] end
function M:HookScript(name, fn)
  local prev = self.scripts[name]
  self.scripts[name] = prev and function(...) prev(...); fn(...) end or fn
end
function M:SetFrameLevel(l) self.level = l end
function M:GetFrameLevel() return self.level or 1 end
M.GetEffectiveScale = function() return 1 end
function M:SetBackdrop(b) self.backdrop, self.backdropInfo = b, b end
function M:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
function M:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
function M:GetBackdropColor() if self.bg then return unpack(self.bg) end end
function M:GetBackdropBorderColor() if self.border then return unpack(self.border) end end
function M:CreateTexture(_, layer) local t = newFrame("Texture", self); t.layer = layer; return t end
function M:CreateFontString(_, layer) local t = newFrame("FontString", self); t.layer = layer; return t end
function M:SetFont(file, size) self.font, self.size = file, size; return true end
function M:SetText(t) self.text = t end
function M:GetText() return self.text end
function M:SetTextColor(r, g, b) self.color = { r, g, b } end
function M:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function M:SetTexture(t) self.texture = t end
function M:SetAtlas(a) self.atlas = a end
function M:SetAlpha(a) self.alpha = a end
function M:GetAlpha() return self.alpha end
function M:SetJustifyH(j) self.justifyH = j end
function M:SetWordWrap(v) self.wordWrap = v end
function M:SetScrollChild(c) self.scrollChild = c end
function M:RegisterEvent(e) self.events[e] = true end
function M:EnableMouse(v) self.mouse = v end
function M:IsEnabled() return self.disabled ~= true end
function M:IsMouseOver() return false end
local function isRegion(c) return c.kind == "Texture" or c.kind == "FontString" end
function M:GetChildren()
  local out = {}
  for _, c in ipairs(self.children) do if not isRegion(c) then out[#out + 1] = c end end
  return unpack(out)
end
function M:GetRegions()
  local out = {}
  for _, c in ipairs(self.children) do if isRegion(c) then out[#out + 1] = c end end
  return unpack(out)
end
for _, name in ipairs({ "SetShadowOffset", "SetShadowColor", "SetHorizTile", "SetVertTile", "SetTexCoord",
                        "SetJustifyV", "SetClipsChildren", "UnregisterEvent", "SetMaxLines" }) do
  M[name] = function() end
end
-- Text is 6px a character, colour codes left out; a wrapped line breaks at its width, 12px a line.
local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function chars(s) local _, n = plain(s):gsub("[^\128-\191]", ""); return n end
function M:GetStringWidth() return chars(self.text) * 6 end
function M:GetStringHeight()
  if (self.text or "") == "" then return 0 end
  if self.wordWrap == false or (self.w or 0) <= 0 then return 12 end
  return math.ceil(chars(self.text) * 6 / self.w) * 12
end

-- ── A client ─────────────────────────────────────────────────────────────
kit.NOW = 1790000000
local queue = {}
function kit.flush()
  for _ = 1, 20 do
    if #queue == 0 then return end
    local due = queue
    queue = {}
    for _, fn in ipairs(due) do fn() end
  end
end

-- `opts`: style ("guildos" or "forever"; Forever is also the client then), officer, roster (count).
function kit.client(opts)
  opts = opts or {}
  local style = opts.style or "guildos"
  local forever = style == "forever"
  queue = {}
  UIParent = newFrame("Frame")
  function CreateFrame(kind, name, parent)
    local f = newFrame(kind, parent)
    if name then _G[name] = f end
    return f
  end
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function hooksecurefunc() end
  if forever then
    function GetBuildInfo() return "1.60.1", "70707", "", 16001 end
    WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MAINLINE = nil, nil, nil
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 5, 5, 1
  end
  function GetLocale() return "enUS" end
  function GetRealmName() return "Realm" end
  function UnitName(unit) if unit == "player" then return "Ana" end end
  function UnitLevel() return 60 end
  function GetServerTime() return kit.NOW end
  function GetTime() return 5000 end
  time = function(t) if t then return os.time(t) end return kit.NOW end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end,
              NewTicker = function() return { Cancel = function() end } end }
  function IsInGuild() return true end
  local rank = opts.officer and 0 or 5
  function GetGuildInfo() return "Chama", "Rank", rank end
  kit.setRank = function(r) rank = r end
  local roster = opts.roster or 3
  function GetNumGuildMembers() return roster, roster end
  function GetGuildRosterInfo(i) return "M" .. i .. "-Realm", "Rank", 0, i == 1 and 40 or 70, "Mage", "", "", "", i ~= 2 end
  Enum = { SendAddonMessageResult = {} }
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  function GetFileIDFromPath() return nil end
  GuildOSDB = {}
  C_Texture = nil
  if forever then
    local atlases = {}
    for line in io.lines(ADDON .. "/tools/data/forever-atlas-elements.txt") do
      if line ~= "" and not line:find("^#") then atlases[(line:gsub(" %*$", "")):lower()] = true end
    end
    C_Texture = { GetAtlasInfo = function(n) return atlases[tostring(n):lower()] and { width = 32, height = 32 } or nil end }
    GuildOSDB.style = "forever"
  end
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Style.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  GuildOS.Print = function() end
  GuildOS.Style:Resolve()
  dofile(ADDON .. "/UI/Helpers.lua")
  dofile(ADDON .. "/UI/Layout.lua")
  -- No feature registry: a feature is allowed while the settings have it on (IsFeatureEnabled).
  local UI = GuildOS.UI
  UI.GetFeature = function() return nil end
  UI.IsFeatureAllowed = function() return true end
  kit.opened = nil
  UI.OpenWindow = function(_, tab, sub, filter) kit.opened = { tab, sub, filter } end
  dofile(ADDON .. "/UI/Agora.lua")
  dofile(ADDON .. "/UI/Dashboard.lua")
  -- The chat card's feed is UI/CommunityPanel.lua's, tested with Guild > Chat (tools/window-shell.lua).
  kit.feeds, kit.feedRefreshed = {}, 0
  function GuildOS:CreateGuildChatFeed(parent)
    kit.feeds[#kit.feeds + 1] = parent
    return function() kit.feedRefreshed = kit.feedRefreshed + 1 end
  end
  GuildOS.State.errors = {}
  GuildOS.db = { settings = { modules = {} }, members = {}, calendar = { events = {} } }
end

-- ── Reading it back ─────────────────────────────────────────────────────
function kit.same(col, c) return col ~= nil and math.abs(col[1] - c.r) < 1e-6 and math.abs(col[2] - c.g) < 1e-6
  and math.abs(col[3] - c.b) < 1e-6 end
function kit.at(f, i) local p = f.points[i or 1]; return p and p[2], p and p[3] end   -- x, y of ("TOPLEFT", x, y)
function kit.walk(f, visit) visit(f); for _, c in ipairs(f.children) do kit.walk(c, visit) end end
-- The text of every FontString drawn under `root` (shown, with every parent shown).
function kit.texts(root)
  local out = {}
  local function go(f)
    if not f.shown then return end
    if f.kind == "FontString" and f.text then out[#out + 1] = tostring(f.text) end
    for _, c in ipairs(f.children) do go(c) end
  end
  go(root)
  return out
end
function kit.shows(root, fragment)
  for _, t in ipairs(kit.texts(root)) do
    if t:find(fragment, 1, true) then return true end
  end
  return false
end
-- The shown Helpers buttons under `root`, by their label.
function kit.buttons(root)
  local out = {}
  local function go(f)
    if not f.shown then return end
    if f.kind == "Button" and f.label and f.label.text then out[#out + 1] = f end
    for _, c in ipairs(f.children) do go(c) end
  end
  go(root)
  return out
end
function kit.button(root, label)
  for _, b in ipairs(kit.buttons(root)) do if b.label.text == label then return b end end
end

if DASHBOARD_KIT then return kit end

-- ════════════════════════════════════════════════════════════════════════
local same, at, walk, flush = kit.same, kit.at, kit.walk, kit.flush
local NOW = kit.NOW
local KARAZHAN = NOW + 2 * 86400 + 4 * 3600

local function fixture(style)
  local G = GuildOS
  local calls = {}
  kit.rsvps = calls
  local raid = { id = "k1", title = "Karazhan", when = KARAZHAN, kind = "RAID", yes = 9 }
  kit.events = { raid }
  G.Calendar = {
    GetUpcoming = function() return kit.events end,
    NextEvent = function() return kit.events[1] end,
    GetComposition = function(_, e)
      return { yes = e.yes or 0, tentative = 2, roles = { TANK = 2, HEALER = 3, DPS = 4 } }
    end,
    MyRsvp = function(_, e) return e.mine end,
    KindLabel = function() return "Raid" end,
    IsWebEvent = function(_, e) return e.web == true end,
    Rsvp = function(_, id, status, role) calls[#calls + 1] = { id, status, role } end,
  }
  G.Readiness = {
    GetReport = function()
      return {
        { name = "Ana", online = true, ilvl = 100, attTotal = 4, attDone = 3, hasGear = true, missEnch = 0,
          missCons = 2, status = "warn" },
        { name = "Bia", online = false, ilvl = 110 },
        { name = "Caio", online = true, ilvl = 0 },
      }
    end,
  }
  G.LootTracker = { GetPlayerLoot = function()
    return {
      { itemLink = "|cffa335ee|Hitem:1|h[Crown of Ruin]|h|r", raid = "Karazhan" },
      { itemName = "Void Cloak", raid = "Gruul's Lair" },
      { itemName = "Scaled Bracers" },
    }
  end }
  G.Recruitment = { MemberMayPost = function() return true end, SetParticipation = function() end,
                    BroadcastStatus = function() end }
  G.db.guildRecruitment = { enabled = true, message = "We |cffff0000raid|r twice a week" }
  G.TrialTracker = { CountReady = function() return 1 end }
  G.db.rosterLog = { events = {} }
  for i = 1, 14 do
    G.db.rosterLog.events[i] = { action = "join", target = "N" .. i, timestamp = NOW - i * 60 }
  end
  if style == "forever" then
    G.Readiness.Countdown = function()
      return { open = false, days = 36, cap = 60, cores = { { name = "Main", ready = 7, size = 10 } },
               guild = { ready = 27, slices = { dungeons = 5, raids = { { size = 10, count = 2 } } } } }
    end
    G.Readiness.DUNGEON_GROUP = 5
  end
end

-- Build the tab as the window does: a panel, the builder, shown, then sized.
local function build(w, h)
  local panel = newFrame("Frame", UIParent)
  panel:Hide()
  GuildOS:CreateNowPanel(panel)
  panel:Show()
  panel:SetSize(w, h)
  flush()
  return panel
end

local function shownCards(home)
  local out = {}
  for _, card in ipairs(home.dash.cards) do if card.shown then out[#out + 1] = card end end
  return out
end

local function run(style)
  kit.client({ style = style, officer = true })
  local C, L, UI = GuildOS.Colors, GuildOS.L, GuildOS.UI
  -- A redraw that raises fails here, loudly, not in /gos errors.
  GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end
  check(GuildOS.Style:Current() == style, style .. ": the client draws the style asked for")
  fixture(style)
  local P = build(976, 516)
  local col, home, content = P.column, P.home, P.content

  -- ── One scroll area, anchored, its child bound to it ───────────────────
  check(P.scroll.kind == "ScrollFrame" and P.scroll.scrollChild == content and P.scroll.points[1][1] == "ALL"
    and P.scroll.points[1][2] == P, style .. ": one scroll area, anchored to the whole tab")
  check(content.w == 976 - UI.SCROLL_GUTTER, style .. ": its child as wide as the tab less the scroll bar's gutter")
  check(content.h == 516, style .. ": at the default size nothing scrolls (" .. tostring(content.h) .. ")")

  -- ── The column: sections without boxes, a rule between them ───────────
  local titles = { P.raidTitle, P.needsTitle, P.feedTitle }
  check(P.raidTitle.text == L["Next raid"] and P.needsTitle.text == L["Needs me"] and P.feedTitle.text == L["Activity"],
    style .. ": the three sections")
  local face = style == "forever" and STANDARD_TEXT_FONT or GuildOS.Fonts.sectionTitle.file
  for i, t in ipairs(titles) do
    check(t.font == face and t.size == 14 and same(t.color, C.text), style .. ": section " .. i .. " titled in Sans SemiBold 14")
  end
  check(P.raidTitle.rule == nil, style .. ": the first section has no rule over it")
  for i = 2, 3 do
    local t, r = titles[i], titles[i].rule
    check(r and r.kind == "Texture" and r.h == 1 and same(r.color, C.line) and r.shown,
      style .. ": section " .. i .. " has a 1px rule in `line`")
    local p1, p2 = r.points[1], r.points[2]
    check(p1[1] == "BOTTOMLEFT" and p1[2] == t and p1[3] == "TOPLEFT" and p1[4] == 0 and p1[5] == 12
      and p2[1] == "RIGHT" and p2[2] == col, style .. ": 12px over its title, across the column")
  end
  local boxes = {}
  walk(col, function(f)
    local opaque = (f.bg and (f.bg[4] or 1) > 0) or (f.border and (f.border[4] or 1) > 0)
    if f.kind ~= "Texture" and f.kind ~= "FontString" and opaque then boxes[#boxes + 1] = f end
  end)
  check(#boxes == 0, style .. ": no section is a box: nothing in the column has a fill or a border (" .. #boxes .. ")")
  -- The sections run down in order, each rule 16px under the last line of the section before.
  local _, ry = at(P.raidTitle)
  local _, cy = at(P.clock)
  local _, oy = at(P.openCalendar)
  local _, ny = at(P.needsTitle)
  local _, ly = at(P.needsList)
  local _, fy = at(P.feedTitle)
  check(ry == 0 and cy < ry and oy < cy - 40 and ny == oy - 26 - 16 - 12, style .. ": next raid, then needs me 28px under it")
  check(ly == ny - 14 - 4 and fy == ly - P.needsList.h - 28, style .. ": its rows under its title, then activity")

  -- ── The next raid ───────────────────────────────────────────────────────
  check(P.raidName.shown and P.raidName.text == "Karazhan" and same(P.raidName.color, C.text), style .. ": the raid's name")
  check(P.raidMeta.text == GuildOS:LocalDate(L["%a %d %b, %H:%M"], KARAZHAN) .. " · 9 going"
    and same(P.raidMeta.color, C.label), style .. ": when it is and who is going, a caption under it")
  local clock = P.clock
  check(clock.text == "2d 4h", style .. ": the countdown (" .. tostring(clock.text) .. ")")
  check(clock.size == 40 and clock.font == (style == "forever" and STANDARD_TEXT_FONT or GuildOS.Fonts.mono),
    style .. ": big, in the Mono countdown role at 40px (" .. tostring(clock.size) .. ")")
  check(same(clock.color, C.text), style .. ": in paper: gold is not a status")
  local cal = P.openCalendar
  check(cal.shown and cal.variant == "ghost" and cal.label.text == L["Open calendar"] and cal.underline.shown,
    style .. ": the calendar is a ghost link")
  check(cal.w == cal.label:GetStringWidth() + 8 and at(cal) == 0, style .. ": as wide as its label and 4px either side, flush left")
  fire(cal, "OnClick")
  check(kit.opened and kit.opened[1] == "guild" and kit.opened[2] == "calendar" and kit.opened[3] == KARAZHAN,
    style .. ": that opens the calendar on the raid's day")

  -- ── Rows: 24px, a line between them, the right-hand caption ────────────
  local need = P.needsList.rows
  check(need[1].h == 24 and need[1].mark.shown and same(need[1].mark.color, C.danger)
    and need[1].text.text == "1 trial(s) ready to review", style .. ": an urgent need, its 6px danger mark")
  check(need[2].text.text == "You have not answered: Karazhan" and same(need[2].mark.color, C.label),
    style .. ": the others a neutral mark, never gold")
  check(need[1].arrow.shown and need[1].arrow.text == ">" and need[1].arrow.points[1][1] == "RIGHT",
    style .. ": a need says on its right that it opens something")
  check(need[1].line.shown and not need[2].line.shown and need[1].line.h == 1, style .. ": a 1px line between rows, not under the last")
  local feed = P.feedList.rows
  check(feed[1].time.shown and feed[1].time.text == os.date("%H:%M", NOW - 60) and feed[1].time.points[1][1] == "RIGHT"
    and feed[1].time.justifyH == "RIGHT", style .. ": an activity row's time on its right, as a caption")
  check(feed[1].text.points[1][1] == "LEFT" and feed[1].text.points[1][4] == 0 and feed[1].text.points[2][4] == -52,
    style .. ": its text from the left edge to the time")
  local fit = math.floor((516 + fy - 14 - 4) / 24)
  local nFeed = 0
  for _, r in ipairs(feed) do if r.shown then nFeed = nFeed + 1 end end
  check(nFeed == math.min(12, fit), style .. ": activity runs to the bottom of the tab (" .. nFeed .. " rows)")

  -- ── Six equal cards, a 2x3 grid beside the column ──────────────────────
  local cards = shownCards(home)
  check(#cards == 6, style .. ": six cards")
  local want = { "NEXT EVENT", "YOUR READINESS", "GUILD PULSE", "RECRUITMENT", "YOUR LOOT", "GUILD CHAT" }
  if style == "forever" then want[2] = "RAIDS OPEN IN 36 DAYS" end
  for i, card in ipairs(cards) do
    check(card.hdr.text == L[want[i]], style .. ": card " .. i .. " is " .. want[i] .. " (" .. tostring(card.hdr.text) .. ")")
  end
  local g = 12
  local width = 976 - UI.SCROLL_GUTTER
  local colW = math.floor((width - 2 * g) / 3)
  check(col.w == colW and home.w == width - colW - g, style .. ": the column is a third of the tab, the grid the rest")
  local hp = home.points[1]
  check(hp[1] == "TOPLEFT" and hp[2] == col and hp[3] == "TOPRIGHT" and hp[4] == g and hp[5] == 0 and not P.gridRule.shown,
    style .. ": the grid 12px beside the column, its top level with it, no rule over it")
  local cw, ch = cards[1].w, cards[1].h
  check(cw == colW and ch == math.floor((516 - 2 * g) / 3), style .. ": a card as wide as the column, the tab's height in three ("
    .. cw .. "x" .. ch .. ")")
  for i, card in ipairs(cards) do
    local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
    local x, y = at(card)
    check(card.w == cw and card.h == ch, style .. ": card " .. i .. " the same size as the others")
    check(x == c * (cw + g) and y == -(r * (ch + g)), style .. ": card " .. i .. " in column " .. c .. ", row " .. r)
    check(same(card.bg, C.panel) and same(card.border, C.line) and card.backdropInfo.edgeSize == 1,
      style .. ": card " .. i .. " a `panel` surface with a 1px `line` border")
  end
  check(home.dash.cols == 2 and home.h == 3 * ch + 2 * g, style .. ": two columns, three rows")
  -- A card lights its border under the mouse as a secondary button does, not in gold.
  local hit = cards[2]
  fire(hit, "OnEnter")
  check(same(hit.border, C.label) and same(hit.arrow.color, C.text), style .. ": hovered, a card's border and arrow light up")
  fire(hit, "OnLeave")
  check(same(hit.border, C.line) and same(hit.arrow.color, C.label), style .. ": and go back")
  fire(cards[3], "OnMouseUp")
  check(kit.opened[1] == "roster", style .. ": a card opens its tab")

  -- ── What each card shows ───────────────────────────────────────────────
  local nextCard = cards[1]
  check(kit.shows(nextCard, "Karazhan") and kit.shows(nextCard, "9 going · 2 tentative  |  2T 3H 4D")
    and kit.shows(nextCard, "in 2d 4h"), style .. ": the next event, when, and who is going")
  local going, maybe, absent = kit.button(nextCard, L["Going"]), kit.button(nextCard, L["Tentative"]), kit.button(nextCard, L["Absent"])
  check(going and maybe and absent, style .. ": the three answers")
  check(going.h == 26 and going.w == going.label:GetStringWidth() + 24 and absent.w == absent.label:GetStringWidth() + 24
    and maybe.points[1][4] == going.w + 8 and absent.points[1][4] == going.w + 8 + maybe.w + 8,
    style .. ": 26px buttons, 12px either side of the label, 8px apart along the card's foot")
  local foot = going.parent
  check(foot.points[1][1] == "BOTTOMLEFT" and foot.parent == nextCard.body and foot.w == nextCard.innerW,
    style .. ": the answers sit on the card's foot, across its width")
  check(going.variant == "primary" and maybe.variant == "secondary" and absent.variant == "secondary",
    style .. ": not answered yet: Going is the screen's one primary")
  fire(going, "OnClick")
  check(kit.rsvps[1] and kit.rsvps[1][1] == "k1" and kit.rsvps[1][2] == "yes" and kit.rsvps[1][3] == "DPS",
    style .. ": and answers it")
  -- The cards refresh on their own show.
  kit.events[1].mine = { status = "tentative", role = "HEALER" }
  fire(home, "OnShow")
  going, maybe = kit.button(cards[1], L["Going"]), kit.button(cards[1], L["Tentative"])
  check(going.variant == "secondary" and maybe.__selected and same(maybe.label.color, C.gold) and not going.__selected,
    style .. ": answered: that answer is the selected one, and no button is primary")
  fire(going, "OnClick")
  check(kit.rsvps[2][2] == "yes" and kit.rsvps[2][3] == "HEALER", style .. ": a new answer keeps the role")
  kit.events[1].web = true
  fire(home, "OnShow")
  check(kit.shows(cards[1], "Sign up in Discord or on the website.") and not kit.button(cards[1], L["Going"]),
    style .. ": a raid planned on the site is answered there")
  kit.events[1].web, kit.events[1].mine = nil, nil
  fire(home, "OnShow")

  if style == "forever" then
    check(kit.shows(cards[2], "Can form") and kit.shows(cards[2], "5 groups") and kit.shows(cards[2], "2×10")
      and kit.shows(cards[2], "Main"), style .. ": the raids countdown where readiness was")
  else
    check(kit.shows(cards[2], "Attunements (3/4)") and kit.shows(cards[2], "75%"), style .. ": attunements, and how far")
    local bar
    walk(cards[2].body, function(f) if f.bar and f.shown then bar = f end end)
    check(bar and bar.w == cards[2].innerW and bar.h == 8, style .. ": on an 8px bar across the card")
    local okSq, warnSq, warnText
    walk(cards[2].body, function(f)
      if f.kind == "Texture" and f.shown and f.w == 6 and f.h == 6 then
        if same(f.color, C.ok) then okSq = f elseif same(f.color, C.warn) then warnSq = f end
      end
      if f.kind == "FontString" and f.shown and f.text == "Consumables: 2 missing" then warnText = f end
    end)
    check(okSq and warnSq and warnText and same(warnText.color, C.warn),
      style .. ": what is done a square in ok, what is missing a square and words in warn")
    check(kit.shows(cards[2], "Needs attention"), style .. ": and the verdict")
  end
  local chips = cards[3].chips
  check(chips and #chips == 3 and chips[1].value.text == "3" and chips[1].label.text == L["members"]
    and chips[2].value.text == "2" and chips[3].value.text == "105" and chips[3].label.text == L["avg iLvl"],
    style .. ": the pulse in three metric chips: members, online, average item level")
  check(same(chips[1].rule.color, C.gold) and chips[2].w == chips[1].w and at(chips[2]) == chips[1].w + 12,
    style .. ": side by side, each under its gold rule")
  check(kit.shows(cards[3], string.format(L["%d raid-ready"], 2)), style .. ": and the raid-ready count under them")
  check(kit.shows(cards[4], L["Guild is recruiting"]) and kit.shows(cards[4], "\"We cffff0000raidr twice a week\""),
    style .. ": the guild's ad, its colour codes taken out (member text)")
  local b = kit.button(cards[4], L["Broadcast now"])
  check(b and b.variant == "ghost", style .. ": an officer's broadcast, a ghost link")
  check(kit.shows(cards[5], "[Crown of Ruin]") and kit.shows(cards[5], "Gruul's Lair") and kit.shows(cards[5], "Scaled Bracers"),
    style .. ": my loot, with the raid it dropped in")
  check(kit.feeds[1] == cards[6].body and cards[6].scripts.OnMouseUp == nil, style .. ": the chat card holds the guild's chat")

  -- ── Gold: the chips' rules and the answer buttons, nothing else ────────
  local golds = {}
  walk(content, function(f)
    if f:IsVisible() and ((f.color and same(f.color, C.gold)) or (f.bg and same(f.bg, C.gold) and (f.bg[4] or 1) > 0)) then
      golds[#golds + 1] = f
    end
  end)
  local stray = 0
  for _, f in ipairs(golds) do
    local p = f
    local ok = false
    while p do
      if p == chips[1] or p == chips[2] or p == chips[3] or (p.kind == "Button" and p.status) then ok = true end
      p = p.parent
    end
    if not ok then stray = stray + 1 end
  end
  check(stray == 0, style .. ": gold only on the chips' rule and the primary answer (" .. stray .. " stray)")

  -- ── Narrower: the cards go under the column, below a rule ──────────────
  P:SetSize(700, 516)
  flush()
  local w7 = 700 - UI.SCROLL_GUTTER
  check(col.w == w7 and P.gridRule.shown, style .. ": under 780px the column takes the width, and a rule follows it")
  local rp = P.gridRule.points
  check(rp[1][1] == "TOPLEFT" and rp[2][1] == "TOPRIGHT" and rp[1][3] == -(col.h + 16) and P.gridRule.h == 1
    and same(P.gridRule.color, C.line), style .. ": a 1px rule 16px under the column, across the tab")
  local hx, hy = at(home)
  check(hx == 0 and hy == -(col.h + 16 + 12) and home.w == w7, style .. ": the grid 12px under the rule, as wide as the tab")
  cards = shownCards(home)
  local cw7 = math.floor((w7 - g) / 2)
  for i, card in ipairs(cards) do
    local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
    local x, y = at(card)
    check(card.w == cw7 and card.h == 164 and x == c * (cw7 + g) and y == -(r * (164 + g)),
      style .. ": card " .. i .. " in the 2x3 grid at 700px, 164px tall")
  end
  local stacked = 0
  for _, r in ipairs(feed) do if r.shown then stacked = stacked + 1 end end
  check(stacked == 5, style .. ": with the cards below, five rows of activity")
  check(content.h == col.h + 28 + 3 * 164 + 2 * g, style .. ": the tab scrolls to the last card (" .. content.h .. ")")

  -- A 620px window: the 8px gutter; still two columns.
  P:SetSize(588, 516)
  flush()
  cards = shownCards(home)
  local w5 = 588 - UI.SCROLL_GUTTER
  check(home.dash.cols == 2 and cards[1].w == math.floor((w5 - 8) / 2) and at(cards[2]) == cards[1].w + 8,
    style .. ": under a 620px window the gutter is 8px (UI.GAP)")
  -- Too narrow for two of 240px: one column of six.
  P:SetSize(480, 516)
  flush()
  cards = shownCards(home)
  local w4 = 480 - UI.SCROLL_GUTTER
  check(home.dash.cols == 1, style .. ": under two 240px cards, one column")
  for i, card in ipairs(cards) do
    local x, y = at(card)
    check(card.w == w4 and x == 0 and y == -((i - 1) * (164 + 8)), style .. ": card " .. i .. " alone in its row")
  end
  -- Every width the window allows: inside the tab, equal, and never two under 240px.
  for pw = 404, 1700, 9 do
    P:SetSize(pw, 516)
    flush()
    cards = shownCards(home)
    local cwid = pw - UI.SCROLL_GUTTER
    local hx2 = at(home)
    local left = (home.points[1][2] == col) and (col.w + home.points[1][4]) or hx2
    for i, card in ipairs(cards) do
      local x = at(card)
      check(card.w == cards[1].w and card.h == cards[1].h, style .. ": card " .. i .. " equal at " .. pw)
      check(left + x + card.w <= cwid, style .. ": card " .. i .. " inside the tab at " .. pw)
      check(home.dash.cols == 1 or card.w >= 240, style .. ": two columns only of 240px or more at " .. pw)
    end
  end

  -- ── Back to the default; no raid ───────────────────────────────────────
  P:SetSize(976, 516)
  flush()
  check(not P.gridRule.shown and home.points[1][2] == col, style .. ": wide again, the grid beside the column")
  kit.events = {}
  P.Refresh()
  check(clock.text == "\226\128\148" and P.raidMeta.text == L["No raid scheduled."] and not P.raidName.shown,
    style .. ": no raid: a dash, one line, no name")
  GuildOS.UI.IsFeatureAllowed = function() return false end
  P.Refresh()
  check(not P.openCalendar.shown and select(2, at(P.needsTitle)) == select(2, at(P.clock)) - 40 - 28,
    style .. ": no calendar link while the Guild tab is off, and nothing left in its place")
  GuildOS.UI.IsFeatureAllowed = function() return true end

  -- ── WoW: Forever's setup card, over the grid while due ─────────────────
  if style == "forever" then
    GuildOS.Activation = {
      STEPS = { "publish", "bot", "account", "members", "run" },
      ShouldShow = function() return true end,
      Read = function() return { done = 2, steps = { publish = true, bot = true } } end,
      Hide = function() end,
    }
    local S = build(976, 516)
    local setup = S.home.dash.setup
    check(setup and setup.shown and setup.w == S.home.w and setup.h == 150 and at(setup) == 0,
      style .. ": the guild's setup spans the grid's top")
    local six = shownCards(S.home)
    check(#six == 6, style .. ": and the six cards are all still there")
    for i, card in ipairs(six) do
      check(card.w == six[1].w and card.h == six[1].h and card.h >= 150 and select(2, at(card)) <= -(150 + 12),
        style .. ": card " .. i .. " equal, under it")
    end
    check(kit.shows(setup, "2 / 5") and kit.shows(setup, L["Publish through the companion"]),
      style .. ": with its steps")

    -- Due later, as the 10s repaint lays the grid out again, not on a tab open: filled as it comes,
    -- never an empty card until the tab is opened again (#377).
    local due = false
    GuildOS.Activation.ShouldShow = function() return due end
    local S2 = build(976, 516)
    check(not S2.home.dash.setup.shown, style .. ": not due yet, no setup card")
    due = true
    S2.Refresh()
    flush()
    check(S2.home.dash.setup.shown and kit.shows(S2.home.dash.setup, "2 / 5"),
      style .. ": due on a repaint, it shows with its steps in it")
    GuildOS.Activation = nil
  end
end

run("guildos")
run("forever")

print(("dashboard-layout: %d checks passed"):format(checks))
