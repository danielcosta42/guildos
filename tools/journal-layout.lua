-- Guild > Journal as "Highlights with art" (issue #373): the real UI/JournalPanel.lua on the real
-- Core/Core.lua, Core/Compat.lua, Core/Data.lua, Core/Style.lua, Core/Utils.lua, UI/Helpers.lua,
-- UI/Layout.lua, Data/ForeverDungeons.lua, Data/GroupActivities.lua and Modules/Journal.lua, under a
-- stubbed WoW: Forever client, in both interface styles ("guildos" and "forever").
--
-- Drawn as the Chronicle's mockup (#449 phase 3): three parchment cards, This week and the guild's firsts on
-- the left and my journal on the right from 700px, stacked below it. This week is three metric blocks side by
-- side, with the week's numbers. Each guild first is a paper box in rows that wrap (never under 180px): the
-- dungeon's Groups art on top where it has some, then its name, "date · N bosses" and who was there in their
-- class colour. My own entries are a timeline: a gold dot on a rail, the entry, its day under it. Each card
-- says so when it is empty; gold is only the chips' rule; a redraw makes no new frames; and the scroll child
-- stays under the 15000px the client draws.
--
--   luajit -e 'ADDON="."' tools/journal-layout.lua
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

-- ── A frame that keeps what the panel does to it ────────────────────────
-- A method this stub does not know raises, so a typo in the panel fails here and not in the game.
local created = 0
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
  created = created + 1
  local f = setmetatable({ kind = kind, parent = parent, children = {}, points = {}, scripts = {}, shown = true,
                           w = 0, h = 0, alpha = 1 }, meta)
  if parent then parent.children[#parent.children + 1] = f end
  return f
end
local function fire(f, script, ...) local fn = f.scripts[script]; if fn then return fn(f, ...) end end
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
function M:Hide() self.shown = false end
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
function M:SetTexCoord(...) self.texCoord = { ... } end
function M:SetAlpha(a) self.alpha = a end
function M:GetAlpha() return self.alpha end
function M:SetJustifyH(j) self.justifyH = j end
function M:SetWordWrap(v) self.wordWrap = v end
function M:SetScrollChild(c) self.scrollChild = c end
for _, name in ipairs({ "SetShadowOffset", "SetShadowColor", "EnableMouse", "SetClipsChildren", "SetHorizTile",
                        "SetVertTile", "SetAtlas", "RegisterEvent", "UnregisterEvent" }) do
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

-- ── A WoW: Forever client ───────────────────────────────────────────────
local NOW = 1790000000
local files = {}   -- the textures the client has (GetFileIDFromPath)
local function client(style)
  created = 0
  UIParent = newFrame("Frame")
  function CreateFrame(kind, name, parent)
    local f = newFrame(kind, parent)
    if name then _G[name] = f end
    return f
  end
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function hooksecurefunc() end
  function GetBuildInfo() return "1.60.1", "70707", "", 16001 end   -- no TBC nor retail project: Forever
  WOW_PROJECT_ID, WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MAINLINE = nil, nil, nil
  function GetLocale() return "enUS" end
  function GetRealmName() return "Realm" end
  function UnitName(unit) if unit == "player" then return "Ana" end end
  function UnitLevel() return 60 end
  function GetServerTime() return NOW end
  function GetTime() return 5000 end
  time = function(t) if t then return os.time(t) end return NOW end
  date = os.date
  function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  function IsInGuild() return true end
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  function GetFileIDFromPath(path) return files[path] end
  files = {}
  GuildOSDB = {}
  C_Texture = nil
  if style == "forever" then
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
  GuildOS.RecordError = function() end
  GuildOS.Print = function() end
  GuildOS.Style:Resolve()
  dofile(ADDON .. "/UI/Helpers.lua")
  dofile(ADDON .. "/UI/Layout.lua")
  dofile(ADDON .. "/Data/ForeverDungeons.lua")
  dofile(ADDON .. "/Data/GroupActivities.lua")
  dofile(ADDON .. "/Modules/Journal.lua")
  dofile(ADDON .. "/UI/JournalPanel.lua")
  GuildOS.SafeCall = function(_, fn, ...) return fn(...) end   -- an error in a redraw fails here, loudly
end

-- ── Reading it back ─────────────────────────────────────────────────────
local function same(col, c) return col and math.abs(col[1] - c.r) < 1e-6 and math.abs(col[2] - c.g) < 1e-6
  and math.abs(col[3] - c.b) < 1e-6 end
local function at(f, i) local p = f.points[i or 1]; return p and p[2], p and p[3] end   -- x, y of a ("TOPLEFT", x, y)
local function shownOf(list) local out = {}; for _, x in ipairs(list) do if x.shown then out[#out + 1] = x end end; return out end
local function walk(f, visit) visit(f); for _, c in ipairs(f.children) do walk(c, visit) end end
local function day(t) return os.date("%Y-%m-%d", t) end

-- ── The fixture: four firsts, a week, my three entries ──────────────────
local function fixture()
  local G = GuildOS
  local k = function(n) return G:GetPlayerKey(n) end
  local H = 3600
  G.db = {
    members = {
      [k("Ana")] = { class = "MAGE" }, [k("Bea")] = { class = "PRIEST" }, [k("Cid")] = { class = "WARRIOR" },
      [k("Dan")] = { class = "ROGUE", feedOptOut = true },   -- chose not to be named (guildos.me #247)
      [k("Eva")] = {},                                       -- no class known: not coloured by one
    },
    journal = {
      entries = {
        { id = "a1", subjectKey = k("Ana"), at = NOW - 48 * H, type = "member.level", data = { level = 20 } },
        { id = "b1", subjectKey = k("Bea"), at = NOW - 24 * H, type = "member.level", data = { level = 30 } },
        { id = "b2", subjectKey = k("Bea"), at = NOW - 3 * H, type = "member.level60", data = {} },
        { id = "a2", subjectKey = k("Ana"), at = NOW - 5 * H, type = "dungeon.clear",
          data = { dungeonId = "city-of-dalaran", dungeonName = "City of Dalaran", runId = "r1", bosses = 7, fullClear = true } },
        { id = "b3", subjectKey = k("Bea"), at = NOW - 5 * H + 30, type = "dungeon.clear",
          data = { dungeonId = "city-of-dalaran", runId = "r1", bosses = 7, fullClear = true } },
        { id = "c1", subjectKey = k("Cid"), at = NOW - 48 * H, type = "dungeon.clear",
          data = { dungeonId = "ruins-of-lordaeron", runId = "r2", bosses = 5, fullClear = true } },
        { id = "a3", subjectKey = k("Ana"), at = NOW - 240 * H, type = "dungeon.clear",
          data = { dungeonId = "hall-of-thanes", dungeonName = "The Hall of Thanes", runId = "r3", bosses = 4, fullClear = true } },
      },
      firsts = {
        ["excavation-site-wetlands"] = { at = NOW - 480 * H, bosses = 3, full = true, who = { [k("Dan")] = true, [k("Eva")] = true } },
        ["hall-of-thanes"] = { at = NOW - 240 * H, bosses = 4, full = true, who = { [k("Ana")] = true } },
        ["ruins-of-lordaeron"] = { at = NOW - 48 * H, bosses = 5, full = true, who = { [k("Cid")] = true } },
        ["city-of-dalaran"] = { at = NOW - 5 * H, bosses = 7, full = true, who = { [k("Ana")] = true, [k("Bea")] = true } },
      },
    },
  }
end

local function run(style)
  client(style)
  local C, L = GuildOS.Colors, GuildOS.L
  check(GuildOS.Style:Current() == "salao", style .. ": the Salão's one look on this client")
  check(GuildOS.Journal and GuildOS.CreateJournalPanel, style .. ": the journal and its panel are on WoW: Forever")
  fixture()

  -- Built hidden, as the Guild hub builds a sub-tab: nothing reads a width yet.
  local hub = newFrame("Frame", UIParent)
  hub:SetSize(1000, 600)
  local refresh = GuildOS:CreateJournalPanel(hub)
  check(type(refresh) == "function", style .. ": the builder hands the hub its redraw")
  local P = hub.journal
  local content = P.content
  local scroll = content.parent
  check(scroll.kind == "ScrollFrame" and scroll.scrollChild == content, style .. ": one scroll area")
  local sp = scroll.points
  check(#sp == 2 and sp[1][1] == "TOPLEFT" and sp[1][2] == 0 and sp[1][3] == -GuildOS.UI.GAP
    and sp[2][1] == "BOTTOMRIGHT" and sp[2][2] == 0 and sp[2][3] == 0,
    style .. ": flush with the sub-tab bar, the first line GAP down, anchored on both corners")

  -- The window shows it, 1000px wide: the scroll area takes that size.
  scroll:SetSize(1000, 560)
  local width = 1000 - GuildOS.UI.SCROLL_GUTTER
  check(content.w == width, style .. ": the content is the scroll area less the bar's gutter (" .. tostring(content.w) .. ")")

  -- The Chronicle's mockup (#449 phase 3): three parchment cards, the week and the firsts on the left, my journal
  -- on the right from 700px.
  local PAD = 14
  local lw = math.floor((width - 12) * 0.535)
  local hw, hf, hm = P.heads.week, P.heads.firsts, P.heads.mine
  check(hw.text == L["This week"] and hf.text == L["Guild firsts in dungeons"] and hm.text == L["Your journal"],
    style .. ": the three cards' titles, never upper case")
  local B = P.blocks
  check(hw.parent == B.week and hf.parent == B.firsts and hm.parent == B.mine and B.week.__look, style .. ": each the title of its card")
  check(at(B.week) == 0 and select(2, at(B.week)) == -2 and at(B.firsts) == 0 and B.week.w == lw and B.firsts.w == lw,
    style .. ": the week and the firsts in the left column")
  check(at(B.mine) == lw + 12 and select(2, at(B.mine)) == -2 and B.mine.w == width - 12 - lw,
    style .. ": my journal in the right one")
  check(select(2, at(B.firsts)) == -(2 + B.week.h + 12), style .. ": the firsts under the week")

  -- ── This week: three chips side by side ─────────────────────────────
  local week = GuildOS.Journal:ThisWeek(NOW)
  check(week.milestones == 3 and week.members == 2 and week.clears == 2, style .. ": the fixture's week (3, 2, 2)")
  local chips = P.chips
  check(#chips == 3, style .. ": three metric chips")
  local captions = { "Level milestones", "Members leveling", "Dungeon clears" }
  local values = { week.milestones, week.members, week.clears }
  local cx1, cy1 = at(chips[1])
  check(cx1 == PAD and cy1 < -30 and chips[1].parent == B.week, style .. ": the chips in the week's card, under its title")
  for i, chip in ipairs(chips) do
    local x, y = at(chip)
    check(chip.value.text == tostring(values[i]) and chip.label.text == L[captions[i]],
      style .. ": chip " .. i .. " says " .. values[i] .. " " .. captions[i])
    check(y == cy1, style .. ": chip " .. i .. " on the same line")
    check(x == cx1 + (i - 1) * (chips[1].w + 8) and chip.w == chips[1].w and x + chip.w <= lw - PAD,
      style .. ": chip " .. i .. " beside the last, as wide as the others, inside the card")
    check(same(chip.value.color, C.paperTitle) and same(chip.label.color, C.paperSoft),
      style .. ": on the paper, a dark red number and a soft caption")
    check(chip.shown, style .. ": chip " .. i .. " shown")
  end

  -- ── Guild firsts: one box each, in the left column ──────────────────
  local firsts = GuildOS.Journal:GuildFirsts()
  check(#firsts == 4, style .. ": the fixture has four firsts")
  local cards = shownOf(P.cards)
  check(#cards == 4 and not P.empty.firsts.shown, style .. ": one box per first, and no empty line")
  local inner = lw - 2 * PAD
  local cols = math.max(1, math.min(math.floor((inner + 8) / 188), math.floor((inner + 8) / 208 + 0.5)))
  local cw = math.floor((inner - 8 * (cols - 1)) / cols)
  check(cols == 2, style .. ": two boxes in a row in the left column at 1000px")
  local _, firstRowY = at(cards[1])
  check(firstRowY < -30 and cards[1].parent == B.firsts, style .. ": the boxes in their card, under its title")
  local classHex = function(cls) return GuildOS:GetClassColorHex(cls) end
  local inkHex = string.format("%02x%02x%02x", C.paperInk.r * 255, C.paperInk.g * 255, C.paperInk.b * 255)
  for i, f in ipairs(firsts) do
    local card = cards[i]
    local x, y = at(card)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    check(card.w == cw and cw >= 180, style .. ": box " .. i .. " is " .. cw .. "px wide")
    check(x == PAD + col * (cw + 8), style .. ": box " .. i .. " in column " .. col)
    if row == 0 then check(y == firstRowY, style .. ": box " .. i .. " in the first row") end
    check(x + card.w <= lw - PAD, style .. ": box " .. i .. " inside the card")
    check(card.name.text == f.name and card.name.wordWrap == false, style .. ": box " .. i .. " named " .. f.name)
    check(card.meta.text == day(f.at) .. " · " .. f.bosses .. " bosses", style .. ": box " .. i .. " has its date and bosses")
    check(same(card.name.color, C.paperTitle) and same(card.meta.color, C.paperSoft),
      style .. ": the dungeon in the paper's red, the rest softer")
    -- Every new dungeon of Forever is without art in the Groups catalogue: no band at all, not an empty
    -- block in the box's own colour over the name (review, #373).
    check(not card.art.shown and not card.band.shown and not card.rule.shown and card.band.h < 1,
      style .. ": no art: no band and no rule, the name at the box's top")
    check(card.band.points[1][1] == "TOPLEFT" and card.band.points[2][1] == "TOPRIGHT",
      style .. ": the band hangs across the box's top")
    check(card.edge and same(card.edge.color, C.paperRule), style .. ": a box is a paper box with the paper's line")
  end
  local rowTwo = cards[3]
  check(at(rowTwo) == PAD and select(2, at(rowTwo)) == firstRowY - cards[1].h - 8,
    style .. ": the third wraps to the next row, GAP under the first")
  check(cards[1].h == cards[2].h, style .. ": a row's boxes share one height")
  -- Who was there, by class: Mage Ana, Priest Bea, Warrior Cid; Eva has none and Dan opted out.
  check(firsts[1].name == "Excavation Site: Wetlands" and cards[1].who.text == "|cff" .. inkHex .. "Eva|r",
    style .. ": a member who chose not to be named is not, and one with no class takes the paper's ink")
  check(cards[2].who.text == "|cff" .. classHex("MAGE") .. "Ana|r", style .. ": Ana in the Mage colour")
  check(cards[3].who.text == "|cff" .. classHex("WARRIOR") .. "Cid|r", style .. ": Cid in the Warrior colour")
  check(cards[4].who.text == "|cff" .. classHex("MAGE") .. "Ana|r · |cff" .. classHex("PRIEST") .. "Bea|r",
    style .. ": a group, each in their class colour, between soft dots")
  check(same(cards[4].who.color, C.paperSoft) and cards[4].who.wordWrap == true, style .. ": the line wraps, soft")

  -- The art, where the Groups catalogue has it and the client has the file: the tile's crop and alpha.
  local dalaran = GuildOS.GroupActivities.byId["city-of-dalaran"]
  local wetlands = GuildOS.GroupActivities.byId["excavation-site-wetlands"]
  dalaran.art, wetlands.art = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-Test", "Interface\\LFGFrame\\UI-LFG-BACKGROUND-Missing"
  files[dalaran.art] = 4242
  refresh()
  cards = shownOf(P.cards)
  local c4 = cards[4]
  check(c4.art.shown and c4.art.texture == dalaran.art and same(c4.band.color, C.well) and c4.band.shown
    and c4.band.h == 64 and c4.rule.shown and same(c4.rule.color, C.paperRule),
    style .. ": a dungeon with art shows it in a 64px band on the well, a 1px line under it")
  check(c4.art.texCoord and c4.art.texCoord[1] == 0 and c4.art.texCoord[2] == 1 and c4.art.texCoord[3] == 0.08
    and c4.art.texCoord[4] == 0.72 and c4.art.alpha == 0.55 and c4.art.points[1][1] == "ALL" and c4.art.points[1][2] == c4.band,
    style .. ": cropped and dimmed as the tile, over the band")
  check(not cards[1].art.shown and not cards[1].band.shown,
    style .. ": art the client does not have is never drawn (it would be a green square)")
  dalaran.art, wetlands.art = nil, nil
  refresh()
  check(not shownOf(P.cards)[4].art.shown, style .. ": and art gone is gone on the next redraw")

  -- ── Your journal: a timeline ────────────────────────────────────────
  local mine = GuildOS.Journal:Mine()
  check(#mine == 3, style .. ": three entries of mine")
  local rows = {}
  for _, r in ipairs(P.rows) do if r.date.shown then rows[#rows + 1] = r end end
  check(#rows == 3 and not P.empty.mine.shown, style .. ": one timeline entry per entry, and no empty line")
  local want = { "City of Dalaran · 7 bosses", "Level 20", "The Hall of Thanes · 4 bosses" }
  local lastY, dotX
  for i, r in ipairs(rows) do
    local dx, dy = at(r.date)
    local tx, ty = at(r.text)
    local px, py = at(r.dot)
    check(r.date.text == day(mine[i].at) and r.text.text == want[i], style .. ": entry " .. i .. " is " .. want[i] .. " on its day")
    check(px == PAD and r.dot.w == 10 and r.dot.h == 10 and tx > px + 10 and dx == tx, style .. ": its dot, then the entry with its day under it")
    check(r.text.points[2][1] == "TOPRIGHT" and r.text.points[2][2] == -PAD, style .. ": the entry hangs from both sides")
    check(dy < ty and py <= ty and py > ty - 14, style .. ": the dot on the entry's line, the day under it")
    check(ty < -30 and (not lastY or ty < lastY), style .. ": under the title, newest first, downwards")
    check(same(r.date.color, C.paperSoft) and same(r.text.color, C.paperInk) and same(r.dot.color, C.metal2),
      style .. ": a soft day, an inked entry, a gold dot")
    check(dotX == nil or dotX == px, style .. ": every dot on the one rail")
    lastY, dotX = ty, px
  end
  local rail = P.rail
  local rx, ry = at(rail, 1)
  local p2 = rail.points[2]
  check(rail.shown and rail.w == 2 and same(rail.color, C.paperRule), style .. ": a line joins the entries")
  check(rx == dotX + 4 and p2[1] == "BOTTOMLEFT" and p2[2] == B.mine and p2[4] == rx
    and ry == select(2, at(rows[1].dot)) - 5 and p2[5] < select(2, at(rows[3].date)),
    style .. ": through the middle of the dots, from the first to the last entry's day")
  check(content.h > 0 and content.h < 15000, style .. ": the scroll child is as tall as what it holds (" .. content.h .. ")")

  -- ── No gold text: the chips' rule is the only gold ──────────────────
  local golds = {}
  walk(content, function(f)
    if f.color and same(f.color, C.gold) then golds[#golds + 1] = f end
    if f.bg and same(f.bg, C.gold) then golds[#golds + 1] = f end
  end)
  check(#golds == 3 and golds[1] == chips[1].rule and golds[2] == chips[2].rule and golds[3] == chips[3].rule,
    style .. ": the only gold is the three chips' rule (" .. #golds .. " gold)")

  -- ── Redraws reuse what they made ────────────────────────────────────
  local settled = created
  for _ = 1, 5 do refresh() end
  hub:Hide(); hub:Show()
  check(created == settled, style .. ": five redraws and a show make no new frame (" .. (created - settled) .. " new)")

  -- ── Narrower: one column, the boxes wrap, never under 180px ─────────
  scroll:SetSize(400, 560)
  local narrow = 400 - GuildOS.UI.SCROLL_GUTTER
  cards = shownOf(P.cards)
  check(#cards == 4 and B.mine.w == narrow and at(B.mine) == 0 and select(2, at(B.mine)) < select(2, at(B.firsts)),
    style .. ": still four boxes at 400px, my journal under the firsts")
  for i, card in ipairs(cards) do
    check(at(card) == PAD and card.w == narrow - 2 * PAD, style .. ": box " .. i .. " alone in its row at 400px")
  end
  check(at(chips[3]) + chips[3].w <= narrow - PAD and chips[1].label.w == chips[1].w - 20,
    style .. ": the three chips share a narrow width, captions cut to it")
  scroll:SetSize(612, 560)
  cards = shownOf(P.cards)
  local in600 = 600 - 2 * PAD
  local c3 = math.floor((in600 - 16) / 3)
  check(cards[1].w == c3 and at(cards[2]) == PAD + c3 + 8 and at(cards[4]) == PAD, style .. ": three in a row at 600px")
  for sw = 200, 1700, 7 do
    scroll:SetSize(sw, 560)
    local cwid = sw - GuildOS.UI.SCROLL_GUTTER
    local colW = cwid >= 700 and math.floor((cwid - 12) * 0.535) or cwid
    for i, card in ipairs(shownOf(P.cards)) do
      check(card.w >= 180 or card.w == colW - 2 * PAD, style .. ": box " .. i .. " never under 180px at " .. sw)
      check(at(card) + card.w <= colW - PAD, style .. ": box " .. i .. " inside its card at " .. sw)
    end
  end
  scroll:SetSize(1000, 560)

  -- ── Empty: each section says so ─────────────────────────────────────
  GuildOS.db.journal = { entries = {}, firsts = {} }
  refresh()
  check(#shownOf(P.cards) == 0 and P.empty.firsts.shown and P.empty.firsts.text == L["No new dungeon cleared by the guild yet."],
    style .. ": no first: the existing line, and no card")
  local anyRow = false
  for _, r in ipairs(P.rows) do anyRow = anyRow or r.date.shown or r.dot.shown or r.text.shown end
  check(not anyRow and not P.rail.shown and P.empty.mine.shown
    and P.empty.mine.text == L["Nothing yet: your milestones and dungeon clears appear here."],
    style .. ": nothing of mine: the existing line, no entry and no rail")
  check(chips[1].value.text == "0" and chips[2].value.text == "0" and chips[3].value.text == "0" and chips[1].shown,
    style .. ": a quiet week is three zeros, as the line said")
  check(P.empty.firsts.parent == B.firsts and P.empty.firsts.points[2][1] == "TOPRIGHT",
    style .. ": the empty line in its card, across it")

  -- One entry: a dot and no rail.
  GuildOS.db.journal.entries = { { id = "x", subjectKey = GuildOS:GetPlayerKey("Ana"), at = NOW - 60, type = "member.level60", data = {} } }
  refresh()
  check(P.rows[1].text.text == "Level " .. GuildOS.Client.maxLevel and P.rows[1].dot.shown and not P.rail.shown,
    style .. ": a single entry has its dot and no line to join")

  -- A month of somebody's journal past what is drawn: the rest counted, the child under 15000px.
  local many = {}
  for i = 1, 450 do
    many[i] = { id = "m" .. i, subjectKey = GuildOS:GetPlayerKey("Ana"), at = NOW - i * 60, type = "dungeon.clear",
                data = { dungeonId = "hall-of-thanes", dungeonName = "The Hall of Thanes", runId = "m" .. i, bosses = 4, fullClear = true } }
  end
  GuildOS.db.journal.entries = many
  refresh()
  local drawn = 0
  for _, r in ipairs(P.rows) do if r.date.shown then drawn = drawn + 1 end end
  check(drawn == 300 and P.more.shown and P.more.text == string.format(L["... and %d more."], 150),
    style .. ": 300 entries drawn (two lines each, #449) and the other 150 counted")
  check(content.h < 15000, style .. ": the scroll child stays under the 15000px the client draws (" .. content.h .. ")")
end

run("guildos")
run("forever")

print(("journal-layout: %d checks passed"):format(checks))
