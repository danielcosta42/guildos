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
function M:CreateMaskTexture() local t = newFrame("MaskTexture", self); return t end
function M:AddMaskTexture(m) self.mask = m end
function M:SetTexCoord(...) self.texCoord = { ... } end
function M:SetDesaturated(v) self.desaturated = v end
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
for _, name in ipairs({ "SetShadowOffset", "SetShadowColor", "SetHorizTile", "SetVertTile",
                        "SetJustifyV", "SetClipsChildren", "UnregisterEvent",
                        -- A popup's (tools/raid-start-ui.lua: the raid owner's prompt)
                        "SetFrameStrata", "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
                        "Raise",
                        -- The Guild chat card's box and feed (#449)
                        "SetTextInsets", "SetAutoFocus", "SetNumeric", "SetMultiLine", "SetHyperlinksEnabled",
                        "SetFocus" }) do
  M[name] = function() end
end
function M:HasFocus() return false end
function M:SetMaxLetters(n) self.maxLetters = n end
function M:SetMaxBytes(n) self.maxBytes = n end
function M:ClearFocus() self.focusCleared = true end
function M:SetVerticalScroll(v) self.vscroll = v end
function M:GetVerticalScroll() return self.vscroll or 0 end
function M:GetVerticalScrollRange() return 0 end
-- Text is 6px a character, colour codes left out; a wrapped line breaks at its width, 12px a line.
local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function chars(s) local _, n = plain(s):gsub("[^\128-\191]", ""); return n end
-- The game's font (Friz Quadrata) is wider than Alegreya Sans: 7px a character in it, so a layout that measures
-- its text is tried with the wider face too ("Use the game's font", Settings > Interface).
local function charW(fs) return fs.font == STANDARD_TEXT_FONT and 7 or 6 end
function M:GetStringWidth() return chars(self.text) * charW(self) end
function M:GetStringHeight()
  if (self.text or "") == "" then return 0 end
  if self.wordWrap == false or (self.w or 0) <= 0 then return 12 end
  return math.ceil(chars(self.text) * charW(self) / self.w) * 12
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
  GuildOSDB = { gameFont = opts.gameFont or nil }
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
  dofile(ADDON .. "/UI/Spacing.lua")
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

local function run(style, gameFont)
  kit.client({ style = style, officer = true, gameFont = gameFont })
  local C = GuildOS.Colors
  GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end
  check(GuildOS.Style:Current() == "salao", style .. ": the Salão's one look on this client")
  fixture()
  local P = build(976, 516)
  local cards = P.cards

  check(P.scroll.kind == "ScrollFrame" and P.scroll.scrollChild == P.content, style .. ": one scroll area")
  for _, key in ipairs({ "forYou", "board", "wall" }) do
    local c = cards[key]
    check(c.__paper and same(c.__look.fill.color, C.paper) and same(c.title.color, C.paperTitle)
      and c.title.font == GuildOS:FontFace(GuildOS.Fonts.title),
      style .. ": " .. key .. " is parchment, its title Cinzel in the dark red")
  end
  check(not cards.fire.__paper and same(cards.fire.title.color, C.gold2),
    style .. ": by the fire is the dark card, its title in the soft gold")
  check(cards.board.link.label.text == "Calendar" and cards.fire.link.label.text == "Members"
    and cards.wall.link.label.text == "Activity", style .. ": each card's link at its title's right")
  cards.fire.link.scripts.OnClick(cards.fire.link)
  check(kit.opened[1] == "roster", style .. ": By the fire's link opens the members")

  local you = shownRows(cards.forYou)
  check(#you == 3 and you[1].main.text == "1 trial(s) ready to review" and you[1].btn.shown,
    style .. ": For you, three lines at most, the urgent one first, each with its button")
  check(you[1].mark.text == "1" and you[1].icon.shown and you[1].btn.variant == "primary" and you[2].btn.variant == "secondary"
    and you[2].btn.__onPaper, style .. ": a coloured square with the count, the first button crimson, the rest quiet")
  you[1].btn.scripts.OnClick(you[1].btn)
  check(kit.opened and kit.opened[1] == "trials", style .. ": the button opens the screen that owns the line")

  local function notes(card)
    local out = {}
    for _, n in ipairs(card.notes) do if n.shown then out[#out + 1] = n end end
    return out
  end
  local board = notes(cards.board)
  check(board[1] and board[1].main.text == "Karazhan" and board[1].meta.text == "You are going" and board[1].pin
    and board[1].outline[1].shown and same(board[1].outline[1].color, { r = 0x3e / 255, g = 0x8e / 255, b = 0x41 / 255 }),
    style .. ": the notice board pins the next event, its time and this player's answer, outlined green")
  board[1].scripts.OnClick(board[1])
  check(kit.opened[1] == "guild" and kit.opened[2] == "calendar" and kit.opened[3] == KARAZHAN,
    style .. ": a click opens the calendar on that day")

  -- The allied guilds' open raids (guildos.me's GOSALLY1, Alliance:OpenRaids) take their place in time.
  local keepAlly = GuildOS.Alliance
  GuildOS.Alliance = { OpenRaids = function() return {
    { guild = "Iron Pact", title = "Gruul", when = NOW + 3600, going = 11, size = 25 },
    { guild = "Silver Hand", title = "Started", when = NOW - 60, going = 2, size = 10 } } end }
  P.Refresh()
  board = notes(cards.board)
  check(board[1] and board[1].main.text == "Gruul" and board[1].meta.text:find("[Iron Pact]", 1, true)
    and board[1].meta.text:find("11/25", 1, true) and not board[1].outline[1].shown
    and board[2].main.text == "Karazhan", style .. ": an allied open raid sits on the board in time, its guild and count shown")
  check(board[1].points[1][3] == board[2].points[1][3] and board[2].points[1][2] > board[1].points[1][2],
    style .. ": the notes side by side, three to a row")
  local begun = false
  for _, r in ipairs(board) do begun = begun or r.main.text:find("Started", 1, true) ~= nil end
  check(not begun, style .. ": one already begun is not on the board")
  board[1].scripts.OnClick(board[1])
  check(kit.opened[1] == "alliance" and kit.opened[2] == "hall", style .. ": a click opens the Salão's Alliance, where it says how to sign up")
  GuildOS.Alliance = keepAlly
  P.Refresh()

  local wall = shownRows(cards.wall)
  check(#wall == 5 and wall[1].glyph.shown and wall[1].glyph.letter.text == "N" and wall[1].side.text ~= "",
    style .. ": the guild wall keeps to five lines, each a glyph with its first letter and its time")
  local faces = {}
  for _, b in ipairs(cards.fire.faces) do if b.shown then faces[#faces + 1] = b end end
  check(#faces == 2 and faces[1].avatar.letter.text == "M" and faces[2].name.text == "M3" and cards.fire.away.shown
    and cards.fire.away.avatar.letter.text == "+1" and cards.fire.away.name.text == "away",
    style .. ": by the fire, a round avatar per guildmate online and the dashed disc of who is away")
  check(cards.fire.count.shown and cards.fire.count.text == "online now \194\183 2",
    style .. ": by the fire says how many are online now at its title")
  check(cards.fire.hint.mouse and type(cards.fire.hint.scripts.OnEnter) == "function",
    style .. ": and its title has a tooltip saying what the card is")
  check(not cards.chimney.shown, style .. ": no Winter Veil event, no Chimney")
  check(cards.board.points[1][2] == 0 and cards.fire.points[1][2] > 0, style .. ": wide, two columns")

  P:SetSize(600, 516)
  flush()
  P.Refresh()
  check(cards.fire.points[1][2] == 0 and cards.fire.points[1][3] < cards.board.points[1][3],
    style .. ": narrow, one column, the fire under the board")
  P:SetSize(976, 516)
  flush()

  -- The bulletin's newest notices (1.39.0, #418): three boxes under the notes, newest first, never a fourth;
  -- the card is as tall as all three at both widths, each box under the one before.
  local keepB, keepDbB = GuildOS.Bulletin, GuildOS.db.bulletin
  GuildOS.db.bulletin = {}
  GuildOS.Bulletin = { Active = function(_, _, limit)
    local all = {}
    for i = 1, 4 do all[i] = { ts = NOW - i, text = "Notice " .. i .. string.rep(" a long line of text", i) } end
    local out = {}
    for i = 1, math.min(limit or 4, 4) do out[i] = all[i] end
    return out
  end }
  for _, w in ipairs({ 976, 600 }) do
    P:SetSize(w, 516)
    flush()
    P.Refresh()
    local nb = cards.board.notices
    check(#nb == 3 and nb[1].shown and nb[2].shown and nb[3].shown and nb[1].text.text:find("^Notice 1")
      and nb[3].text.text:find("^Notice 3"), style .. " @" .. w .. ": the board shows the three newest notices")
    check(nb[2].points[1][3] < nb[1].points[1][3] - nb[1].h + 1 and nb[3].points[1][3] < nb[2].points[1][3] - nb[2].h + 1,
      style .. " @" .. w .. ": each notice under the one before, never over it")
    check(-nb[3].points[1][3] + nb[3].h <= cards.board.h, style .. " @" .. w .. ": the card is tall enough for all three")
    nb[2].scripts.OnClick(nb[2])
    check(kit.opened[1] == "guild" and kit.opened[2] == "bulletin", style .. ": a notice opens the bulletin")
  end
  GuildOS.Bulletin = { Active = function() return { { ts = NOW, text = "Only one" } } end }
  P.Refresh()
  check(cards.board.notices[1].shown and not cards.board.notices[2].shown and not cards.board.notices[3].shown,
    style .. ": one notice, one box")
  GuildOS.Bulletin, GuildOS.db.bulletin = keepB, keepDbB
  P:SetSize(976, 516)
  flush()
  P.Refresh()

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
  -- One entrant, or none yet (#449): a stocking drawn as one (its foot and cuff), or a line saying none hangs yet.
  phase = "wrapping"
  WV.Event = function() return { counts = { entrants = 1, wrapped = 0 } } end
  P.Refresh()
  local one = cards.chimney.stockings[1]
  check(one.shown and one.foot.shown and one.cuff.shown and not cards.chimney.stockings[2].shown,
    style .. ": one entrant, one stocking with its foot and cuff, not a bare block")
  WV.Event = function() return { counts = { entrants = 0 } } end
  P.Refresh()
  check(cards.chimney.shown and not one.shown and cards.chimney.line.text:find("No stockings yet", 1, true),
    style .. ": nobody yet: the Chimney says no stockings hang yet")
  GuildOS.WinterVeil = nil

  -- The Guild chat (#449): under the board, the last lines of /g, newest at the bottom; an officer's channel only
  -- for an officer, marked; Enter sends to /g and clears the box; the link opens Salão › Chat.
  local sent = {}
  local guildLog = {
    { n = "Lunara", c = "DRUID", t = NOW - 600, m = "flask anyone?" },
    { n = "Oruk", c = "SHAMAN", t = NOW - 60, m = "bank has 3" },
  }
  local listeners = {}
  GuildOS.GuildChat = {
    Locked = function() return false end, Watch = function() end,
    Streams = function() return { { kind = "guild" }, { kind = "officer", id = "o" } } end,
    Entries = function(_, st) if st and st.kind == "officer" then return { { n = "Kael", c = "MAGE", t = NOW - 300, m = "promote Oruk" } } end return guildLog end,
    OnRefresh = function(_, fn) listeners[#listeners + 1] = fn end,
    Send = function(_, text, st) sent[#sent + 1] = { text, st }; return true end,
  }
  P = build(976, 516)
  cards = P.cards
  local chat = cards.chat
  check(chat.shown and not chat.__paper and chat.points[1][2] == 0 and chat.points[1][3] < cards.board.points[1][3],
    style .. ": the Guild chat is a dark card in the left column, under the notice board")
  check(chat.h >= 180, style .. ": filling the column's height: " .. tostring(chat.h))
  local ln = chat.shownLines
  check(#ln == 3 and ln[1].name == "Lunara" and ln[2].officer and ln[3].name == "Oruk",
    style .. ": its lines oldest first, the newest at the bottom, the officers' line among them for an officer")
  check(kit.shows(chat, "Officer") and kit.shows(chat, "promote Oruk"), style .. ": an officer's line is marked")
  check(chat.lines[1].avatar.letter.text == "L" and chat.lines[3].time.text ~= "", style .. ": each with its avatar and time")
  check(chat.say.maxBytes == 241 and chat.say.maxLetters == nil, "the box takes what /g keeps: 240 bytes, never 255 letters")
  chat.say:SetText("on my way")
  chat.say.scripts.OnEnterPressed(chat.say)
  check(sent[1] and sent[1][1] == "on my way" and sent[1][2] == nil and chat.say:GetText() == "",
    style .. ": Enter says it in /g and clears the box")
  guildLog[#guildLog + 1] = { n = "Velyra", c = "PRIEST", t = NOW, m = "thanks!" }
  for _, fn in ipairs(listeners) do fn() end
  flush()
  check(#chat.shownLines == 4 and chat.shownLines[4].name == "Velyra", style .. ": a new line of /g shows at once")
  chat.link.scripts.OnClick(chat.link)
  check(kit.opened[1] == "guild" and kit.opened[2] == "chat", style .. ": its Chat link opens Salão › Chat")
  kit.setRank(5)
  P.Refresh()
  check(#chat.shownLines == 3 and not kit.shows(chat, "promote Oruk"), style .. ": a member never sees the officers' lines")
  kit.setRank(0)
  P:SetSize(600, 516)
  flush()
  P.Refresh()
  check(chat.points[1][2] == 0 and cards.fire.points[1][3] < chat.points[1][3], style .. ": narrow, the chat under the board, the right column under it")
  P:SetSize(976, 516)
  flush()
  GuildOS.GuildChat = nil

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
-- The same Home with the game's font ticked (Discord 1556991354478010459): every text in the game's face, and
-- every check above still holds with its wider letters.
do
  local seen = 0
  run("guildos", true)
  check(GuildOS.Style.gameFont == true and GuildOS:UsesGameFont(), "game font: read once at load from GuildOSDB.gameFont")
  local panel = kit.newFrame("Frame", UIParent)
  GuildOS:CreateSalaoPanel(panel)
  panel:SetSize(976, 516)
  kit.flush()
  panel.Refresh()
  kit.walk(panel, function(f)
    if f.kind == "FontString" and f.font then
      seen = seen + 1
      check(f.font == STANDARD_TEXT_FONT, "game font: every text of the Home draws in the game's font (" .. tostring(f.font) .. ")")
    end
  end)
  check(seen > 20, "game font: the Home's texts were checked (" .. seen .. ")")
end

-- Groups now (#449): the guild's open groups on the Hall, from the real Modules/LFGBoard.lua, Modules/Groups.lua
-- and Modules/GroupQuests.lua: a summary, the groups that fit first (a role of mine at my level, a quest in my
-- log), Find a group opening Raids › Groups; with none open a line and the button, never an empty card. Under By
-- the fire, in the first view, the Guild chat where it was. Its lines are made once; a change on the board
-- repaints it, a second after the first of a burst.
for _, style in ipairs({ "guildos", "forever" }) do
  kit.client({ style = style, officer = true })
  GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end
  fixture()
  local P0 = build(976, 516)
  check(not P0.cards.groups.shown, style .. ": no Groups module, no Groups now card")
  local chatY0, fireY0 = P0.cards.chat.points[1][3], P0.cards.fire.points[1][3]

  function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
  local passThrough = { Serialize = function(_, t) return t end, Deserialize = function(_, d) return true, d end }
  LibStub = function() return passThrough end
  C_QuestLog = {
    GetNumQuestLogEntries = function() return 1 end,
    GetInfo = function() return { title = "Wanted: Worg Master Kruush", questID = 10809, level = 60, suggestedGroup = 3 } end,
  }
  GuildOS.CommSystem = { MSG_TYPES = { LFG = "LG", LFG_GROUP = "GF", LFG_JOIN = "GJ" }, SendMessage = function() end }
  dofile(ADDON .. "/Data/GroupActivities.lua")
  dofile(ADDON .. "/Modules/LFGBoard.lua")
  dofile(ADDON .. "/Modules/GroupQuests.lua")
  dofile(ADDON .. "/Modules/Groups.lua")
  local B, G = GuildOS.LFGBoard, GuildOS.Groups
  B:Initialize()
  G:Initialize()
  local function key(n) return GuildOS:GetPlayerKey(n, "Realm") end

  local P = build(976, 516)
  local card, fire, chat = P.cards.groups, P.cards.fire, P.cards.chat
  local function rows() local out = {} for _, r in ipairs(card.rows) do if r.shown then out[#out + 1] = r end end return out end
  check(card.shown and card.__paper and card.title.text == "Groups now", style .. ": Groups now is a parchment card")
  check(card.summary.text == "No group open right now" and #rows() == 0 and card.find.shown
    and card.find.label.text == "Find a group" and card.find.variant == "primary",
    style .. ": none open: one line and Find a group, never an empty card")
  card.find.scripts.OnClick(card.find)
  check(kit.opened and kit.opened[1] == "groups", style .. ": Find a group opens Raids › Groups")
  check(card.points[1][2] == fire.points[1][2] and card.points[1][3] < fire.points[1][3] - fire.h + 1,
    style .. ": in the right column, right under By the fire")
  check(-card.points[1][3] + card.h <= 516, style .. ": all of it in the first view at 516px (" .. (-card.points[1][3] + card.h) .. ")")
  check(chat.points[1][3] == chatY0 and fire.points[1][3] == fireY0, style .. ": the Guild chat and By the fire where they were")
  local made = #card.rows

  -- This client's catalogue: an activity for my level (60) and one for another.
  local fitAct, otherAct
  for _, sec in ipairs(GuildOS.GroupActivities.sections) do
    for _, it in ipairs(sec.items) do
      if it.min and G:FitsLevel(it.id, 60) then fitAct = fitAct or it end
      if it.min and not G:FitsLevel(it.id, 60) then otherAct = otherAct or it end
    end
  end
  check(fitAct and otherAct, style .. ": the catalogue has an activity for level 60 and one for another")
  local store = GuildOS.db.lfgGroups
  local NOW0 = GetServerTime()
  store[key("Bea")] = G:_BuildGroup({ act = otherAct.id, need = { D = 1 }, ttl = 3600 }, NOW0 - 5)
  store[key("Cid")] = G:_BuildGroup({ act = fitAct.id, need = { T = 1, D = 2 }, ttl = 3600 }, NOW0 - 60)
  store[key("Dan")] = G:_BuildGroup({ act = "elite-quests", need = { H = 1 }, ttl = 3600,
                                      quest = { id = 10809, t = "Theirs" } }, NOW0 - 600)
  store[key("Eva")] = G:_BuildGroup({ act = otherAct.id, need = { H = 1 }, ttl = 3600 }, NOW0 - 1)
  B:HandleEntry("Fay-Realm", { roles = "D", acts = { otherAct.id }, ttl = 3600 }, "GUILD")
  B:SetPref("roles", "T")
  B:Refresh()
  flush()
  local r = rows()
  check(card.summary.text == "4 groups open \194\183 1 looking", style .. ": the summary counts the groups open and who is looking: "
    .. tostring(card.summary.text))
  check(#r == 3, style .. ": three lines at most (" .. #r .. ")")
  check(r[1].main.text:find(fitAct.name, 1, true) and r[1].side.text == "for you"
    and r[2].main.text:find("Wanted: Worg Master Kruush", 1, true) and r[2].side.text == "you have this quest"
    and r[3].main.text:find(otherAct.name, 1, true) and r[3].side.text == "Eva",
    style .. ": the groups that fit first (my role, my quest), then the newest with its leader: "
    .. tostring(r[1].main.text) .. " / " .. tostring(r[2].main.text) .. " / " .. tostring(r[3].main.text))
  check(r[1].main.text:find("1 Tank, 2 DPS", 1, true) ~= nil, style .. ": each with its open spots")
  check(r[1].side.color[2] > r[1].side.color[1], style .. ": what fits me is in the green")
  check(card.find.shown and card.find.points[1][3] < r[3].points[1][3], style .. ": Find a group under the lines")
  r[2].scripts.OnClick(r[2])
  check(kit.opened[1] == "groups", style .. ": a line opens Raids › Groups too")
  check(-card.points[1][3] + card.h <= 516, style .. ": with three lines still all in the first view (" .. (-card.points[1][3] + card.h) .. ")")
  check(chat.points[1][3] == chatY0, style .. ": the Guild chat still where it was")

  -- One open, nobody looking.
  store[key("Bea")], store[key("Cid")], store[key("Dan")] = nil, nil, nil
  GuildOS.db.lfgBoard[key("Fay")] = nil
  B:Refresh()
  flush()
  check(card.summary.text == "1 group open" and #rows() == 1, style .. ": one group: one line, said so")
  store[key("Eva")] = nil
  B:Refresh()
  flush()
  check(card.summary.text == "No group open right now" and #rows() == 0 and card.find.shown,
    style .. ": the last one gone: the empty line and the button again")
  check(#card.rows == made, style .. ": no line made after the first drawing (" .. #card.rows .. ")")

  -- Switched off in Settings, the card goes.
  GuildOS.db.settings.modules.groups = false
  P.Refresh()
  check(not card.shown, style .. ": with Groups switched off there is no card")
  GuildOS.db.settings.modules.groups = nil
  for i = #B.listeners, 1, -1 do B.listeners[i] = nil end
  C_QuestLog, LibStub, GuildOS.CommSystem = nil, nil, nil
end

-- One happening, one line on the wall (#449): the game's "left the guild" and this client's roster diff file the
-- same leave twice, minutes apart; two officers' copies too. One line each.
do
  kit.client({ style = "guildos", officer = true })
  GuildOS.SafeCall = function(_, fn, ...) return true, fn(...) end
  GuildOS.db.rosterLog = { events = {
    { action = "leave", target = "Mega Mix", timestamp = NOW - 120 },
    { action = "leave", target = "Mega Mix", timestamp = NOW - 115, loc = true },
    { action = "leave", target = "mega mix", timestamp = NOW - 60 },
    { action = "join", target = "Mega Mix", timestamp = NOW - 30 },
    { action = "leave", target = "Other", timestamp = NOW - 100, loc = true },
  } }
  local feed = GuildOS.UI.Agora:Activity()
  local leaves, joins, other = 0, 0, 0
  for _, r in ipairs(feed) do
    if r.text == "Mega Mix left the guild" or r.text == "mega mix left the guild" then leaves = leaves + 1 end
    if r.text == "Mega Mix joined the guild" then joins = joins + 1 end
    if r.text == "Other left the guild" then other = other + 1 end
  end
  check(leaves == 1, "the same leave filed by the game, the roster diff and another officer is one line (" .. leaves .. ")")
  check(joins == 1, "a join after it is its own line")
  check(other == 1, "a leave only the roster diff saw still shows")
end

-- An avatar shows the class's crest cut round, the initial only when the class is unknown.
do
  local saved = CLASS_ICON_TCOORDS
  CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 } }
  local a = GuildOS.UI:CreateAvatar(kit.newFrame("Frame"), 40, false)
  a:SetMember("Jaina", "MAGE")
  check(a.icon.shown and (a.letter.text or "") == "" and a.icon.texture:find("CharacterCreate%-Classes"), "a known class: its crest, no letter")
  check(a.icon.texCoord[1] > 0.25 and a.icon.texCoord[2] < 0.5, "trimmed of the crest's own frame")
  check(a.icon.mask ~= nil, "cut round by a mask")
  a:SetMember("Jaina", "MAGE", true)
  check(a.icon.desaturated == true, "away: the crest greys out")
  a:SetMember("Xyz", "UNKNOWN")
  check(not a.icon.shown and a.letter.text == "X", "an unknown class: the initial")
  a:SetCount(5)
  check(not a.icon.shown and a.letter.text == "+5", "the count disc has no crest")
  CLASS_ICON_TCOORDS = saved
end

print(("salao-layout: %d checks passed"):format(checks))
