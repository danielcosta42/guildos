-- The Achievements tab as "Insignia and collection" draws it (issue #373), run against the real
-- Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Core/Style.lua, UI/Helpers.lua,
-- UI/Layout.lua and UI/AchievementsPanel.lua under a stubbed client, in both interface styles.
--
-- What this holds: the header is the insignia (64px), its title (or the guild's name) with "Renown N"
-- under it and the points as the metric chip on the right; NEAREST is one card per Next() entry, side
-- by side and wrapping, each with its title, its bar and "current / target"; EARNED is a collection:
-- a numbered series is one row of tier pills with the tier Next() is counting drawn dim after them,
-- "Prefix: part" titles share their prefix's row, the rest are a row each, every row dated by its
-- newest. The titles are the guild's real ones.
--
--   luajit -e 'ADDON="."' tools/achievements-layout.lua
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

-- ── A client: frames and textures that remember what was done to them ────
local function newRegion(kind, parent)
  local r = { kind = kind, parent = parent, children = {}, points = {}, scripts = {}, w = 0, h = 0, shown = true }
  if parent then parent.children[#parent.children + 1] = r end
  return setmetatable(r, { __index = function(_, k)
    if k:match("^[a-z_]") then return nil end   -- a field nobody set is nil; only methods answer
    return function(self, ...)
      local a = { ... }
      if k == "SetAtlas" then self.atlas = a[1]
      elseif k == "SetTexture" then self.texture = a[1]
      elseif k == "SetVertexColor" or k == "SetTextColor" or k == "SetColorTexture" then self.color = a
      elseif k == "SetBackdrop" then self.backdrop, self.backdropInfo, self.bg, self.border = a[1], a[1], { 1, 1, 1, 1 }, { 1, 1, 1, 1 }
      elseif k == "SetBackdropColor" then self.bg = a
      elseif k == "SetBackdropBorderColor" then self.border = a
      elseif k == "GetBackdropColor" then if self.bg then return unpack(self.bg) end
      elseif k == "GetBackdropBorderColor" then if self.border then return unpack(self.border) end
      elseif k == "GetEffectiveScale" then return 1
      elseif k == "SetSize" then self.w, self.h = a[1], a[2]
      elseif k == "SetWidth" then self.w = a[1]
      elseif k == "SetHeight" then self.h = a[1]
      elseif k == "GetWidth" then return self.w
      elseif k == "GetHeight" then return self.h
      elseif k == "SetPoint" then self.points[#self.points + 1] = a
      elseif k == "ClearAllPoints" then self.points = {}
      elseif k == "Show" then self.shown = true
      elseif k == "Hide" then self.shown = false
      elseif k == "SetShown" then self.shown = a[1] and true or false
      elseif k == "IsShown" then return self.shown
      elseif k == "SetText" then self.text = a[1]
      elseif k == "GetText" then return self.text
      elseif k == "SetFont" then self.font = a[1]; return true
      elseif k == "GetStringWidth" then return #(self.text or "") * 6
      elseif k == "GetStringHeight" then return 14
      elseif k == "SetMaxLines" then self.maxLines = a[1]
      elseif k == "SetScript" then self.scripts[a[1]] = a[2]
      elseif k == "HookScript" then
        local prev = self.scripts[a[1]]
        self.scripts[a[1]] = prev and function(...) prev(...); a[2](...) end or a[2]
      elseif k == "CreateTexture" or k == "CreateFontString" then
        local t = newRegion(k, self); t.layer = a[2]; return t
      elseif k == "SetFrameLevel" then self.level = a[1]
      elseif k == "GetFrameLevel" then return 1
      end
    end
  end })
end

-- Loads the client and the addon's files in `style` ("guildos" or "forever").
local errors
local function load(style)
  errors = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame(kind, _, parent)
    local f = newRegion(kind, parent)
    if kind == "ScrollFrame" then   -- UIPanelScrollFrameTemplate's scroll bar and its children
      local bar = newRegion("Slider", f)
      bar.ScrollUpButton, bar.ScrollDownButton = newRegion("Button", bar), newRegion("Button", bar)
      bar.ThumbTexture = newRegion("Texture", bar)
      bar.GetMinMaxValues = function() return 0, 0 end
      bar.GetValue = function() return 0 end
      f.ScrollBar = bar
    end
    return f
  end
  UIParent = newRegion("Frame")
  function hooksecurefunc() end
  function GetBuildInfo() return "1.60.1", "70235", "", 16001 end
  WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  function GetLocale() return "enUS" end
  function GetRealmName() return "Realm" end
  function UnitName() return "Ana" end
  function GetServerTime() return 1790000000 end
  function GetTime() return 1 end
  function IsInGuild() return true end
  function GetGuildInfo() return "Ashen Vow", "Rank", 0 end
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  date = os.date
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  Enum = { SendAddonMessageResult = {} }
  UISpecialFrames, SlashCmdList = {}, {}
  -- The Forever client has every atlas the style names; that is all "forever" asks of it.
  C_Texture = style == "forever" and { GetAtlasInfo = function() return { width = 32, height = 32 } end } or {}
  GuildOSDB = { style = style }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Core/Utils.lua")
  dofile(ADDON .. "/Core/Data.lua")
  dofile(ADDON .. "/Core/Style.lua")
  GuildOS.RecordError = function(_, msg) errors[#errors + 1] = tostring(msg) end
  GuildOS.db = { settings = {} }
  GuildOS.Style:Resolve()
  dofile(ADDON .. "/UI/Helpers.lua")
  dofile(ADDON .. "/UI/Layout.lua")
  dofile(ADDON .. "/UI/AchievementsPanel.lua")
  return GuildOS.Style
end

local function same(col, c) return col and math.abs(col[1] - c.r) < 1e-6 and math.abs(col[2] - c.g) < 1e-6
  and math.abs(col[3] - c.b) < 1e-6 end
local function point(region, name)
  for _, p in ipairs(region.points) do if p[1] == name then return p end end
end
-- Every region under `root`, depth first.
local function walk(root, fn)
  for _, c in ipairs(root.children) do
    fn(c)
    walk(c, fn)
  end
end
-- Shown, and so is every frame between it and `root`: a title in a hidden section box is not seen.
local function visible(region, root)
  while region and region ~= root do
    if not region.shown then return false end
    region = region.parent
  end
  return true
end
local function shownText(root, text)
  local found
  walk(root, function(c) if c.kind == "CreateFontString" and c.text == text and visible(c, root) then found = found or c end end)
  return found
end

-- ── The guild's real titles ─────────────────────────────────────────────
local DAY = 86400
local T = 1793750400
local function ago(d) return T - d * DAY end
local function ymd(t) return os.date("%Y-%m-%d", t) end
-- Newest first, as Achievements:Earned() gives them.
local EARNED = {
  { id = "1",  title = "Oficina Completa I",                       at = ago(1) },
  { id = "2",  title = "Biblioteca Viva III",                      at = ago(2) },
  { id = "3",  title = "Desbravadores: Excavation Site: Wetlands", at = ago(3) },
  { id = "4",  title = "Nove Vidas em Dalaran",                    at = ago(4) },
  { id = "5",  title = "Quarenta para Onyxia III",                 at = ago(5) },
  { id = "6",  title = "Biblioteca Viva II",                       at = ago(6) },
  { id = "7",  title = "Desbravadores: City of Dalaran",           at = ago(7) },
  { id = "8",  title = "Bandeira Hasteada",                        at = ago(8) },
  { id = "9",  title = "Quarenta para Onyxia II",                  at = ago(9) },
  { id = "10", title = "Tudo nos Trinques",                        at = ago(10) },
  { id = "11", title = "Biblioteca Viva I",                        at = ago(11) },
  { id = "12", title = "Desbravadores: Ruins of Lordaeron",        at = ago(12) },
  { id = "13", title = "Quarenta para Onyxia I",                   at = ago(13) },
  { id = "14", title = "Carta Assinada",                           at = ago(14) },
  { id = "15", title = "Pioneiros do Forever",                     at = ago(15) },
  { id = "16", title = "Os Primeiros Dez",                         at = ago(16) },
}
-- Oficina Completa II is the real one; the other three are this harness's, to fill a second row of
-- cards and to give one a title of two lines.
local NEXT = {
  { title = "Oficina Completa II", current = 3, target = 5 },
  { title = "Desbravadores: Shadowfang Keep", current = 0, target = 1 },
  { title = "Uma Noite Inteira em Naxxramas com a Guilda Toda Presente", current = 7, target = 10 },
  { title = "Mestres do Ofício", current = 12, target = 12 },
}
local TEX = "Interface\\AddOns\\GuildOS\\Media\\renown-horde-3"

-- ── 1. The collection, as a pure function ───────────────────────────────
load("guildos")
local rows = GuildOS:AchievementCollection(EARNED, NEXT)
local function labels(list)
  local out = {}
  for _, t in ipairs(list or {}) do out[#out + 1] = t.label end
  return table.concat(out, " ")
end
check(#rows == 10, "16 earned make 10 rows: 3 series, 1 group, 6 singles (got " .. #rows .. ")")
local want = {
  { "series", "Oficina Completa",      "I",        "II", ago(1) },
  { "series", "Biblioteca Viva",       "I II III", nil,  ago(2) },
  { "group",  "Desbravadores",         "Ruins of Lordaeron · City of Dalaran · Excavation Site: Wetlands", nil, ago(3) },
  { "single", "Nove Vidas em Dalaran", nil,        nil,  ago(4) },
  { "series", "Quarenta para Onyxia",  "I II III", nil,  ago(5) },
  { "single", "Bandeira Hasteada",     nil,        nil,  ago(8) },
  { "single", "Tudo nos Trinques",     nil,        nil,  ago(10) },
  { "single", "Carta Assinada",        nil,        nil,  ago(14) },
  { "single", "Pioneiros do Forever",  nil,        nil,  ago(15) },
  { "single", "Os Primeiros Dez",      nil,        nil,  ago(16) },
}
for i, w in ipairs(want) do
  local r = rows[i] or {}
  check(r.kind == w[1] and r.name == w[2], ("row %d is the %s %q (got %s %q)"):format(i, w[1], w[2], tostring(r.kind), tostring(r.name)))
  if w[1] == "series" then
    check(labels(r.tiers) == w[3], ("%s has the tiers %s (got %s)"):format(w[2], w[3], labels(r.tiers)))
    check((r.following and r.following.label) == w[4], ("%s's next tier is %s"):format(w[2], tostring(w[4])))
  elseif w[1] == "group" then
    check(table.concat(r.parts, " · ") == w[3], "the group's parts, in the order they were earned: " .. table.concat(r.parts, " · "))
  end
  check(r.at == w[5], ("%s is dated by its newest (%s)"):format(w[2], ymd(w[5])))
end
check(rows[1].following.entry == NEXT[1], "the next tier carries its Next() entry")

-- The edges the real titles do not show.
local function one(title, nearest) return GuildOS:AchievementCollection({ { title = title, at = 5 } }, nearest)[1] end
check(one("Os Primeiros Dez").kind == "single" and one("Fase IIII").kind == "single" and one("Rei Mix").kind == "single"
  and one("XIV").kind == "single", "a word that only looks like a numeral, or a numeral alone, is not a series")
check(one("Arena IX").kind == "series" and one("Arena IX").tiers[1].n == 9, "IX is tier 9")
local skip = GuildOS:AchievementCollection({ { title = "Biblioteca Viva I", at = 1 } },
  { { title = "Biblioteca Viva IV", current = 0, target = 1 }, { title = "Biblioteca Viva II", current = 0, target = 1 } })[1]
check(skip.following and skip.following.label == "II", "with two tiers counted, the lowest past what was earned is next")
local stale = GuildOS:AchievementCollection({ { title = "Biblioteca Viva III", at = 1 } },
  { { title = "Biblioteca Viva II", current = 1, target = 1 } })[1]
check(stale.following == nil, "a tier at or under the earned one is not next")
local twice = GuildOS:AchievementCollection({ { title = "Biblioteca Viva II", at = 9 }, { title = "Biblioteca Viva II", at = 3 } })
check(#twice == 1 and #twice[1].tiers == 1 and twice[1].at == 9, "a tier earned twice is one pill, dated by the newest")
check(#GuildOS:AchievementCollection({}, NEXT) == 0, "nothing earned: no rows, whatever is next")
check(one("Desbravadores: Ruins of Lordaeron").kind == "group", "a lone prefix title is still its group")
check(one(": nothing").kind == "single", "a colon with nothing before it is no prefix")

-- ── 2. The tab, in each interface style ────────────────────────────────
local CONTENT_W = 812
local function build(data, scrollW)
  GuildOS.Achievements = data
  GuildOS.State.errors = {}
  local parent = newRegion("Frame", UIParent)
  local refresh = GuildOS:CreateAchievementsPanel(parent)
  local scroll, content
  for _, c in ipairs(parent.children) do if c.kind == "ScrollFrame" then scroll = c end end
  for _, c in ipairs(scroll.children) do if c.kind == "Frame" then content = c end end
  if scrollW then
    scroll.w = scrollW
    scroll.scripts.OnSizeChanged(scroll)
  end
  return { parent = parent, scroll = scroll, content = content, refresh = refresh }
end
local function data(over)
  over = over or {}
  return {
    Renown = over.Renown or function() return 7, 1240 end,
    Insignia = over.Insignia or function() return TEX, "Guardiões do Forte" end,
    Next = over.Next or function() return NEXT end,
    Earned = over.Earned or function() return EARNED end,
  }
end

for _, style in ipairs({ "guildos", "forever" }) do
  local S = load(style)
  check(S:Current() == style, style .. ": the style is in use")
  local C, UI = GuildOS.Colors, GuildOS.UI
  local gutter = UI.SCROLL_GUTTER
  local tab = build(data(), CONTENT_W + gutter)
  local content = tab.content
  check(#errors == 0, style .. ": the tab draws without an error (" .. table.concat(errors, "; ") .. ")")
  local sp = point(tab.scroll, "TOPLEFT")
  check(sp and sp[2] == 0 and sp[3] == -UI.GAP, style .. ": flush with the sub-tab bar, the first line GAP down")
  check(content.w == CONTENT_W, style .. ": the content keeps the scroll frame's width less the gutter")

  -- The header.
  local insignia
  walk(content, function(c) if c.kind == "CreateTexture" and c.texture == TEX then insignia = c end end)
  check(insignia and insignia.shown and insignia.w == 64 and insignia.h == 64, style .. ": the insignia, 64px")
  local ip = insignia and point(insignia, "TOPLEFT")
  check(ip and ip[2] == 0 and ip[3] == 0, style .. ": at the top left")
  local name = shownText(content, "Guardiões do Forte")
  check(name and point(name, "TOPLEFT")[2] == 64 + 12, style .. ": its title beside it")
  local renown = shownText(content, "Renown 7")
  check(renown and point(renown, "TOPLEFT")[3] < point(name, "TOPLEFT")[3], style .. ": \"Renown 7\" under the title")
  local chip
  walk(content, function(c) if c.rule and c.value and c.label then chip = c end end)
  check(chip and chip.shown and chip.value.text == "1240" and chip.label.text == "points", style .. ": the points as the metric chip")
  local cp = chip and point(chip, "TOPRIGHT")
  check(cp and cp[2] == 0 and cp[3] == 0, style .. ": on the right")
  check(chip.w >= #"1240" * 6 or chip.w >= 34, style .. ": as wide as its value")
  check(same(chip.rule.color, C.gold), style .. ": its rule is the metric's gold")
  check(point(name, "TOPRIGHT")[2] <= -(chip.w + UI.GAP), style .. ": the title stops short of the chip")

  -- The nearest cards: one per entry, three to a row at this width, the fourth wrapping.
  local cards = content.cards
  check(#cards == #NEXT, style .. ": one card per Next() entry (got " .. #cards .. ")")
  local cardW = math.floor((CONTENT_W - 2 * UI.GAP) / 3)
  local top = point(cards[1], "TOPLEFT")[3]
  for i, card in ipairs(cards) do
    local n, p = NEXT[i], point(card, "TOPLEFT")
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    check(card.shown and card.w == cardW, style .. ": card " .. i .. " is " .. cardW .. " wide (got " .. tostring(card.w) .. ")")
    check(p[2] == col * (cardW + UI.GAP) and p[3] == top - row * (card.h + UI.GAP),
      style .. ": card " .. i .. " in column " .. col .. ", row " .. row)
    check(card.title.text == n.title and card.title.maxLines == 2, style .. ": card " .. i .. " has its title, two lines at most")
    local count = ("%d / %d"):format(n.current, n.target)
    check(card.count.text == count and card.count.font == (GuildOS.Style.gameFont and STANDARD_TEXT_FONT or GuildOS.Fonts.mono),
      style .. ": card " .. i .. " says " .. count .. " in the number font")
    local bar = card.bar
    check(bar.shown and bar.w == cardW - 20 - #count * 6 - UI.GAP, style .. ": card " .. i .. "'s bar runs up to the numbers")
    local fill = math.max(1, (bar.w - 2) * (n.current / n.target))
    check(math.abs(bar.bar.w - fill) < 1e-6, style .. ": card " .. i .. "'s bar is filled to " .. n.current .. "/" .. n.target)
    check(not card.__nine, style .. ": card " .. i .. " is a flat surface")
  end
  check(same(cards[4].bar.bar.color, C.ok) and same(cards[1].bar.bar.color, C.textSoft),
    style .. ": a done bar is ok, one under way is textSoft")
  check(point(cards[1], "TOPLEFT")[3] < -64, style .. ": the cards start under the header")

  -- The collection.
  local drawn = content.rows
  check(#drawn == 10, style .. ": ten earned rows (got " .. #drawn .. ")")
  for i, w in ipairs(want) do
    local d = drawn[i]
    check(d.name.shown and d.name.text == w[2] and same(d.name.color, C.text), style .. ": row " .. i .. " is " .. w[2])
    check(d.date.text == ymd(w[5]), style .. ": " .. w[2] .. " dated " .. ymd(w[5]))
    check(point(d.date, "TOPRIGHT")[2] == 0 and point(d.date, "TOPRIGHT")[3] == point(d.name, "TOPLEFT")[3],
      style .. ": " .. w[2] .. "'s date on the right, on its line")
    if w[1] == "series" then
      local got, x = {}, 200 + UI.GAP
      for j, pill in ipairs(d.pills) do
        got[#got + 1] = pill.label.text
        local p = point(pill, "TOPLEFT")
        check(pill.shown and p[2] == x and p[3] == point(d.name, "TOPLEFT")[3] + 1,
          style .. ": " .. w[2] .. "'s pill " .. j .. " follows the one before it, on the name's line")
        x = x + pill.w + 4
        if pill.earned then
          check(same(pill.label.color, C.text) and same(pill.border, C.lineHi), style .. ": an earned tier is text on lineHi")
        else
          check(same(pill.label.color, C.label) and same(pill.border, C.line), style .. ": the next tier is dim, label on line")
        end
      end
      local expect = w[3] .. (w[4] and (" " .. w[4]) or "")
      check(table.concat(got, " ") == expect, style .. ": " .. w[2] .. " shows [" .. expect .. "] (got " .. table.concat(got, " ") .. ")")
      check(d.pills[#d.pills].earned == (w[4] == nil), style .. ": " .. w[2] .. (w[4] and " ends on its next tier" or " has no next tier"))
    elseif w[1] == "group" then
      check(d.parts.text == w[3] and same(d.parts.color, C.textSoft) and point(d.parts, "TOPLEFT")[2] == 200 + UI.GAP,
        style .. ": the group's parts beside its name, joined by \" · \"")
    else
      check(#d.pills == 0 and not d.parts and point(d.name, "TOPRIGHT")[2] == -(80 + UI.GAP),
        style .. ": " .. w[2] .. " is a row of its own, up to the date")
    end
  end
  check(point(drawn[1].name, "TOPLEFT")[3] < point(cards[4], "TOPLEFT")[3] - cards[4].h, style .. ": EARNED comes after the cards")
  check(content.h > 0 and content.h < 15000, style .. ": the scroll child is " .. content.h .. "px, well under 15000")
  check(shownText(content, "NEAREST") and shownText(content, "EARNED"), style .. ": both sections have their titles")

  -- Gold is the metric's rule only: no text of the screen is gold.
  local gold = {}
  walk(content, function(c)
    if c.kind == "CreateFontString" and c.shown and same(c.color, C.gold) then gold[#gold + 1] = tostring(c.text) end
  end)
  check(#gold == 0, style .. ": no gold text (" .. table.concat(gold, ", ") .. ")")

  -- A redraw takes its frames again.
  local before = 0
  walk(content, function() before = before + 1 end)
  tab.refresh(); tab.refresh()
  local after = 0
  walk(content, function() after = after + 1 end)
  check(after == before and #content.rows == 10 and #content.cards == 4, style .. ": a redraw makes no new frames")

  -- Narrower: two cards to a row.
  tab.scroll.w = 430 + gutter
  tab.scroll.scripts.OnSizeChanged(tab.scroll)
  local p3 = point(content.cards[3], "TOPLEFT")
  check(content.cards[1].w == math.floor((430 - UI.GAP) / 2) and p3[2] == 0 and p3[3] < point(content.cards[1], "TOPLEFT")[3],
    style .. ": at 430px two cards to a row, the third wrapping")
  check(point(content.rows[1].pills[1], "TOPLEFT")[2] == math.floor(430 * 0.4) + UI.GAP,
    style .. ": a narrow screen gives the name column 40% of it")

  -- Built hidden, the width unknown: cards stack, hung by both sides, until it is laid out.
  tab = build(data(), nil)
  check(#errors == 0 and #tab.content.cards == 4, style .. ": built hidden it draws")
  local c1 = tab.content.cards[1]
  check(point(c1, "TOPLEFT") and point(c1, "TOPRIGHT") and point(tab.content.cards[2], "TOPLEFT")[3] < point(c1, "TOPLEFT")[3],
    style .. ": a card per row, hung by both sides")
  tab.scroll.w = CONTENT_W + gutter
  tab.scroll.scripts.OnSizeChanged(tab.scroll)
  check(tab.content.cards[1].w == cardW and not point(tab.content.cards[1], "TOPRIGHT"), style .. ": and laid out once it has a size")

  -- The header without an insignia, without a title, without either.
  tab = build(data({ Insignia = function() return nil, nil end }), CONTENT_W + gutter)
  insignia = nil
  walk(tab.content, function(c) if c.kind == "CreateTexture" and c.texture and c.shown and c.w == 64 then insignia = c end end)
  name = shownText(tab.content, "Ashen Vow")
  check(not insignia and name and point(name, "TOPLEFT")[2] == 0 and point(name, "TOPLEFT")[3] == 0,
    style .. ": no insignia nor title: the guild's name, at the top left")
  check(shownText(tab.content, "Renown 7"), style .. ": with the renown under it")
  tab = build(data({ Insignia = function() return TEX, nil end }), CONTENT_W + gutter)
  check(shownText(tab.content, "Ashen Vow") and point(shownText(tab.content, "Ashen Vow"), "TOPLEFT")[2] == 76,
    style .. ": an insignia with no title: the guild's name beside it")
  local realGuild = GetGuildInfo
  GetGuildInfo = function() return nil end
  tab = build(data({ Insignia = function() return nil, nil end }), CONTENT_W + gutter)
  GetGuildInfo = realGuild
  local only = shownText(tab.content, "Renown 7")
  local count = 0
  walk(tab.content, function(c) if c.kind == "CreateFontString" and c.shown and c.text == "Renown 7" then count = count + 1 end end)
  check(only and count == 1, style .. ": with neither, the renown alone is the heading")

  -- Empty states, with the screen's strings.
  tab = build(data({ Renown = function() return nil end }), CONTENT_W + gutter)
  local shownFrames = 0
  walk(tab.content, function(c) if c.shown and c.kind ~= "CreateFontString" and c.kind ~= "CreateTexture" and c.parent == tab.content then shownFrames = shownFrames + 1 end end)
  check(shownText(tab.content, "Achievements come from guildos.me: the web companion brings them here when your guild has them.")
    and not shownText(tab.content, "NEAREST") and not shownText(tab.content, "EARNED") and shownFrames == 0,
    style .. ": no block: the line saying where they come from, and nothing else")
  tab = build(data({ Next = function() return {} end, Earned = function() return {} end }), CONTENT_W + gutter)
  check(not shownText(tab.content, "NEAREST") and #tab.content.cards == 0, style .. ": nothing near: no NEAREST")
  check(shownText(tab.content, "EARNED") and shownText(tab.content, "Nothing earned yet.") and #tab.content.rows == 0,
    style .. ": nothing earned: EARNED says so")
  check(#errors == 0, style .. ": no errors along the way (" .. table.concat(errors, "; ") .. ")")
end

-- ── 3. Tooltips (#373, as approved) ────────────────────────────────────
-- Each achievement shows, under the cursor, its title, what it asks when the site sends that, then when
-- and by whom it was earned, or how far along it is. A group lists its parts with their days.
load("guildos")
local C = GuildOS.Colors
local tip = {}
GameTooltip = {
  SetOwner = function(_, owner) tip = { owner = owner, lines = {} } end,
  AddLine = function(_, text, r, g, b) tip.lines[#tip.lines + 1] = { text = text, color = { r, g, b } } end,
  AddDoubleLine = function(_, left, right) tip.lines[#tip.lines + 1] = { text = left, right = right } end,
  Show = function() tip.shown = true end,
  Hide = function() tip.shown = false end,
}
GuildOS.db.members = GuildOS.db.members or {}
GuildOS.db.members["Ana-Realm"] = { name = "Ana", class = "MAGE" }
local earnedTip = {}
for i, e in ipairs(EARNED) do earnedTip[i] = { id = e.id, title = e.title, at = e.at } end
earnedTip[2].rule, earnedTip[2].key = "Receitas diferentes conhecidas pela guilda: 400", "Ana-Realm"   -- Biblioteca Viva III
local nextTip = { { title = "Oficina Completa II", current = 3, target = 5, rule = "Alguem em cada uma das 6 profissoes" } }
local tipTab = build(data({ Earned = function() return earnedTip end, Next = function() return nextTip end }), 900)
local function rowNamed(name)
  for _, d in ipairs(tipTab.content.rows) do if d.name.text == name then return d end end
end

local bv = rowNamed("Biblioteca Viva")
local pillIII = bv and bv.pills[3]
check(pillIII and pillIII.scripts.OnEnter and pillIII.scripts.OnLeave, "a tier's pill answers the cursor")
pillIII.scripts.OnEnter(pillIII)
check(tip.shown and tip.owner == pillIII and tip.lines[1].text == "Biblioteca Viva III" and same(tip.lines[1].color, C.text)
  and tip.lines[2].text == "Receitas diferentes conhecidas pela guilda: 400" and same(tip.lines[2].color, C.textSoft),
  "its tooltip: the tier's title, then what it asks")
check(tip.lines[4].text == "Earned " .. ymd(EARNED[2].at) and tip.lines[5].text:find("Ana", 1, true)
  and tip.lines[5].text:find("^by "), "then when it was earned and by whom")
pillIII.scripts.OnLeave(pillIII)
check(not tip.shown, "and it goes when the cursor leaves")
local pillI = bv.pills[1]
pillI.scripts.OnEnter(pillI)
check(tip.lines[1].text == "Biblioteca Viva I" and tip.lines[3].text == "Earned " .. ymd(EARNED[11].at) and #tip.lines == 3,
  "each pill is its own tier; without a rule or a member, just the title and the day")

local oficina = rowNamed("Oficina Completa")
local following = oficina and oficina.pills[#oficina.pills]
check(following and not following.earned, "the series' next tier is a pill too")
following.scripts.OnEnter(following)
check(tip.lines[1].text == "Oficina Completa II" and tip.lines[2].text == nextTip[1].rule and tip.lines[4].text == "3 / 5  (60%)",
  "the next tier's pill tells how far along it is")

local card = tipTab.content.cards[1]
card.scripts.OnEnter(card)
check(tip.owner == card and tip.lines[1].text == "Oficina Completa II" and tip.lines[4].text == "3 / 5  (60%)",
  "a nearest card shows the same")

local group = rowNamed("Desbravadores")
group.hit.scripts.OnEnter(group.hit)
check(tip.lines[1].text == "Desbravadores" and #tip.lines == 4 and tip.lines[2].text == "Ruins of Lordaeron"
  and tip.lines[2].right == ymd(EARNED[12].at) and tip.lines[4].text == "Excavation Site: Wetlands",
  "a group's row lists its parts, oldest first, each with its day")

local single = rowNamed("Bandeira Hasteada")
single.hit.scripts.OnEnter(single.hit)
check(tip.lines[1].text == "Bandeira Hasteada" and tip.lines[3].text == "Earned " .. ymd(EARNED[8].at),
  "a single's row shows its own")
bv.hit.scripts.OnEnter(bv.hit)
check(tip.lines[1].text == "Biblioteca Viva III", "a series' row, off its pills, shows its newest tier")
check(bv.hit.points[1][1] == "TOPLEFT" and bv.hit.points[2][1] == "TOPRIGHT" and pillIII.level and bv.hit.level
  and pillIII.level > bv.hit.level, "the row's hover area spans it, under the pills, so a pill wins under the cursor")
GameTooltip = nil

print(("achievements-layout: %d checks passed"):format(checks))
