-- The Salão's Home (specs/salao, #445), run against the real UI/Agora.lua and UI/Salao.lua on the real
-- Core/Core.lua, Core/Compat.lua, Core/Data.lua, Core/Style.lua, Core/Utils.lua, UI/Helpers.lua and
-- UI/Layout.lua under a stub frame API, drawn both ways: flat on a TBC Anniversary client and with the
-- client's art on a WoW: Forever one.
--
-- Four parchment cards (For you, the Notice board, By the fire, the Guild wall) in two columns from a
-- 700px tab, one under it; For you holds three lines at most, the Winter Veil one first; while an event is
-- on, the Chimney shows one stocking per entrant, filled for each who wrapped, and never a name.
--
-- tools/raid-start-ui.lua loads this file with SALAO_KIT set, for its stub client alone.
--
--   luajit -e 'ADDON="."' tools/salao-layout.lua
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
function M:SetMaxLines(n) self.maxLines = n end
function M:SetScrollChild(c) self.scrollChild = c end
function M:RegisterEvent(e) self.events[e] = true end
function M:EnableMouse(v) self.mouse = v end
function M:IsEnabled() return self.disabled ~= true end
-- As the game does: the button's own OnEnable / OnDisable, when the state changes.
function M:Enable() if self.disabled then self.disabled = nil; fire(self, "OnEnable") end end
function M:Disable() if not self.disabled then self.disabled = true; fire(self, "OnDisable") end end
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
                        "SetJustifyV", "SetClipsChildren", "UnregisterEvent",
                        -- A popup's (tools/raid-start-ui.lua: the raid owner's prompt)
                        "SetFrameStrata", "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
                        "Raise" }) do
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
  dofile(ADDON .. "/UI/Salao.lua")
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

if SALAO_KIT then return kit end

-- ════════════════════════════════════════════════════════════════════════
local same, flush = kit.same, kit.flush
local NOW = kit.NOW
local KARAZHAN = NOW + 2 * 86400 + 4 * 3600

local function fixture()
  local G = GuildOS
  kit.events = { { id = "k1", title = "Karazhan", when = KARAZHAN, kind = "RAID", mine = { status = "yes" } } }
  G.Calendar = {
    GetUpcoming = function() return kit.events end,
    MyRsvp = function(_, e) return e.mine end,
    IsWebEvent = function() return false end,
  }
  G.TrialTracker = { CountReady = function() return 1 end }
  G.GuildManager = {
    DEFAULT_INACTIVE_DAYS = 30,
    GetInactiveMembers = function() return { {}, {} } end,
    GetSuggestions = function() return { promoteCandidates = { {} } } end,
  }
  G.db.rosterLog = { events = {} }
  for i = 1, 8 do G.db.rosterLog.events[i] = { action = "join", target = "N" .. i, timestamp = NOW - i * 60 } end
  G.WinterVeil = nil
end

local function build(w, h)
  local panel = newFrame("Frame", UIParent)
  panel:Hide()
  GuildOS:CreateSalaoPanel(panel)
  panel:Show()
  panel:SetSize(w, h)
  flush()
  panel.Refresh()
  return panel
end

local function shownRows(card)
  local out = {}
  for _, r in ipairs(card.rows) do if r.shown then out[#out + 1] = r end end
  return out
end

local function run(style)
  kit.client({ style = style, officer = true })
  local C = GuildOS.Colors
  GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end
  check(GuildOS.Style:Current() == style, style .. ": the client draws the way asked for")
  fixture()
  local P = build(976, 516)
  local cards = P.cards

  check(P.scroll.kind == "ScrollFrame" and P.scroll.scrollChild == P.content, style .. ": one scroll area")
  for _, key in ipairs({ "forYou", "board", "wall" }) do
    local c = cards[key]
    check(same(c.bg, C.paper) and same(c.title.color, C.paperInk) and c.title.font == STANDARD_TEXT_FONT,
      style .. ": " .. key .. " is parchment, its title in the paper's ink and the game's font")
  end
  check(same(cards.fire.title.color, C.gold), style .. ": by the fire is the dark card, its title in gold")

  local you = shownRows(cards.forYou)
  check(#you == 3 and you[1].main.text == "1 trial(s) ready to review" and you[1].btn.shown,
    style .. ": For you, three lines at most, the urgent one first, each with its button")
  you[1].btn.scripts.OnClick(you[1].btn)
  check(kit.opened and kit.opened[1] == "trials", style .. ": the button opens the screen that owns the line")

  local board = shownRows(cards.board)
  check(board[1] and board[1].main.text == "Karazhan" and board[1].side.text:find("You are going", 1, true),
    style .. ": the notice board shows the next event, its time and this player's answer")
  board[1].scripts.OnClick(board[1])
  check(kit.opened[1] == "guild" and kit.opened[2] == "calendar" and kit.opened[3] == KARAZHAN,
    style .. ": a click opens the calendar on that day")

  -- The allied guilds' open raids (guildos.me's GOSALLY1, Alliance:OpenRaids) take their place in time.
  local keepAlly = GuildOS.Alliance
  GuildOS.Alliance = { OpenRaids = function() return {
    { guild = "Iron Pact", title = "Gruul", when = NOW + 3600, going = 11, size = 25 },
    { guild = "Silver Hand", title = "Started", when = NOW - 60, going = 2, size = 10 } } end }
  P.Refresh()
  board = shownRows(cards.board)
  check(board[1] and board[1].main.text == "[Iron Pact] Gruul" and board[1].side.text:find("11/25", 1, true)
    and board[2].main.text == "Karazhan", style .. ": an allied open raid sits on the board in time, its guild and count shown")
  local begun = false
  for _, r in ipairs(board) do begun = begun or r.main.text:find("Started", 1, true) ~= nil end
  check(not begun, style .. ": one already begun is not on the board")
  board[1].scripts.OnClick(board[1])
  check(kit.opened[1] == "alliance" and kit.opened[2] == "hall", style .. ": a click opens the Salão's Alliance, where it says how to sign up")
  GuildOS.Alliance = keepAlly
  P.Refresh()

  check(#shownRows(cards.wall) == 5, style .. ": the guild wall keeps to five lines")
  check(not cards.chimney.shown, style .. ": no Winter Veil event, no Chimney")
  check(cards.board.points[1][2] == 0 and cards.fire.points[1][2] > 0, style .. ": wide, two columns")

  P:SetSize(600, 516)
  flush()
  P.Refresh()
  check(cards.fire.points[1][2] == 0 and cards.fire.points[1][3] < cards.board.points[1][3],
    style .. ": narrow, one column, the fire under the board")
  P:SetSize(976, 516)
  flush()

  -- Winter Veil: the line leads For you, the Chimney counts, and no name is drawn.
  local phase = "wrapping"
  local WV = {
    Event = function() return { counts = { entrants = 18, wrapped = 14, opened = 3 } } end,
    PhaseOf = function() return phase end,
    MyGives = function() return { { to = "Velyra-Realm", wrapped = false } } end,
    Joined = function() return true end,
    Got = function() return { ready = true } end,
  }
  GuildOS.WinterVeil = WV
  P.Refresh()
  you = shownRows(cards.forYou)
  check(you[1].main.text == "You drew Velyra in the Secret Santa" and you[1].btn.label.text == "Wrap" and #you == 3,
    style .. ": the Winter Veil line leads For you, still three lines")
  you[1].btn.scripts.OnClick(you[1].btn)
  check(kit.opened[1] == "winterveil", style .. ": Wrap opens the Secret Santa")
  local shownS, full = 0, 0
  for _, sk in ipairs(cards.chimney.stockings) do
    if sk.shown then
      shownS = shownS + 1
      if same(sk.color, C.danger) then full = full + 1 end
    end
  end
  check(cards.chimney.shown and shownS == 18 and full == 14, style .. ": the Chimney, one stocking per entrant, 14 filled")
  check(cards.chimney.line.text == "14 of 18 entrants wrapped their globe", style .. ": and says the count, no name")
  phase = "open"
  P.Refresh()
  check(shownRows(cards.forYou)[1].main.text == "Your snow globe arrived" and cards.chimney.title.text == "The Chimney is lit",
    style .. ": on the day, the globe to open leads, and the Chimney is lit")
  GuildOS.WinterVeil = nil

  -- WoW: Forever's countdown to the raids (#207): a card while Readiness:Countdown says so, none otherwise.
  check(not cards.countdown.shown, style .. ": no countdown when Readiness has none")
  local reports = 0
  GuildOS.Readiness = {
    GetReport = function() reports = reports + 1; return {} end,
    DUNGEON_GROUP = 5,
    Countdown = function()
      return { open = false, days = 13, cap = 60, cores = { { name = "Main", ready = 7, size = 10 } },
               guild = { ready = 27, slices = { dungeons = 5, raids = {} } } }
    end,
  }
  GuildOS.UI.Salao._cdAt = nil
  local wasRetail, wasTBC = GuildOS.Client.isRetail, GuildOS.Client.isAnniversary
  GuildOS.Client.isRetail, GuildOS.Client.isAnniversary = true, false
  P.Refresh()
  check(reports == 0 and not cards.countdown.shown, style .. ": off Forever the readiness report is never built for it")
  GuildOS.Client.isRetail, GuildOS.Client.isAnniversary = false, false
  GuildOS.UI.Salao._cdAt = nil
  P.Refresh()
  P.Refresh()
  check(reports == 1, style .. ": on Forever it is built once, and the next refreshes reuse it")
  local cd = shownRows(cards.countdown)
  check(cards.countdown.shown and cards.countdown.title.text == "Raids open in 13 days",
    style .. ": the countdown card says how many days")
  check(cd[1] and cd[1].main.text == "Main" and cd[1].side.text == "7 / 10 at 60" and cd[2].main.text == "Guild"
    and cd[2].side.text == "27 at 60", style .. ": each core at the level cap, then the guild")
  GuildOS.Readiness = nil
  GuildOS.Client.isRetail, GuildOS.Client.isAnniversary = wasRetail, wasTBC
  GuildOS.UI.Salao._cdAt, GuildOS.UI.Salao._cd = nil, nil
end

run("guildos")
run("forever")
print(("salao-layout: %d checks passed"):format(checks))
