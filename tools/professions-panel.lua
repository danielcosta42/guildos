-- The Professions panel (issue #33) built and driven like a user, against the real Core, Compat,
-- Utils, Data, UI helpers and layout, Professions and ProfDirectory, under a permissive frame
-- stub: every method it does not model is a no-op, so the run catches what the panel calls on
-- nil, formats wrongly or never reaches, not how it looks. The look is checked in game.
--
--   luajit -e 'ADDON="."' tools/professions-panel.lua
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

-- ── A permissive frame ──────────────────────────────────────────────────
local function noop() end
local Proxy = {}
-- Methods it does not model are no-ops; any other field is nil, as on a real frame.
local VERBS = { "^Set", "^Register", "^Unregister", "^Enable", "^Disable", "^Clear", "^Start", "^Stop", "^Add",
                "^Hook", "^Raise", "^Lower" }
Proxy.__index = function(_, k)
  local v = rawget(Proxy, k)
  if v ~= nil then return v end
  if type(k) == "string" then
    for _, verb in ipairs(VERBS) do if k:match(verb) then return noop end end
  end
  return nil
end
local all = {}
function Proxy.new(kind, parent)
  local o = setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, w = 0, h = 0, text = "" }, Proxy)
  all[#all + 1] = o
  return o
end
function Proxy:SetScript(n, fn) self.scripts[n] = fn end
function Proxy:GetScript(n) return self.scripts[n] end
function Proxy:HookScript(n, fn)
  local old = self.scripts[n]
  self.scripts[n] = function(...) if old then old(...) end; fn(...) end
end
function Proxy:SetSize(w, h) self.w, self.h = w, h end
function Proxy:SetWidth(w) self.w = w end
function Proxy:SetHeight(h) self.h = h end
function Proxy:GetWidth() return self.w end
function Proxy:GetHeight() return self.h end
function Proxy:SetText(t) self.text = t end
function Proxy:GetText() return self.text end
function Proxy:GetStringWidth() return #(self.text or "") * 6 end
function Proxy:Show() self.shown = true end
function Proxy:Hide() self.shown = false end
function Proxy:SetShown(v) self.shown = v and true or false end
function Proxy:IsShown() return self.shown end
function Proxy:IsVisible() return self.shown end
function Proxy:GetObjectType() return self.kind end
function Proxy:IsMouseOver() return false end
function Proxy:IsEnabled() return true end
function Proxy:GetFrameLevel() return 1 end
function Proxy:GetName() return self.name end
function Proxy:GetParent() return self.parent end
function Proxy:CreateTexture() return Proxy.new("Texture", self) end
function Proxy:CreateFontString() return Proxy.new("FontString", self) end
function Proxy:SetFont() return true end
function Proxy:SetPoint(point) self.movedTo = point end
function CreateFrame(kind, name, parent)
  local f = Proxy.new(kind, parent)
  f.name = name
  if name then _G[name] = f end
  return f
end
-- Shown, and every parent shown too.
local function visible(o)
  while o do
    if not o.shown then return false end
    o = o.parent
  end
  return true
end
local function texts()
  local out = {}
  for _, o in ipairs(all) do
    if o.kind == "FontString" and visible(o) and o.text ~= "" then out[#out + 1] = o.text end
  end
  return out
end
local function showing(pattern)
  for _, t in ipairs(texts()) do if t:find(pattern, 1, true) then return true end end
  return false
end

-- ── The client: WoW: Forever ────────────────────────────────────────────
local NOW, timers = 1790500000, {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() return {} end }
local function runTimers() while #timers > 0 do table.remove(timers, 1)() end end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
DEFAULT_CHAT_FRAME = { AddMessage = noop }
SlashCmdList, UISpecialFrames = {}, {}
UIParent, GameTooltip = Proxy.new("Frame"), Proxy.new("GameTooltip")
function GetServerTime() return NOW end
function time() return NOW end
function GetTime() return NOW end
function IsInGuild() return true end
function hooksecurefunc() end
function debugstack() return "" end
function GetRealmName() return "Classic Beta PvE 2" end
function UnitName(u) if u == "player" then return "Ana" end end
function UnitFullName(u) if u == "player" then return "Ana", "Silva" end end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id, iconID = 136000 } end }
local UNCACHED = {}
C_Item = { GetItemInfo = function(id)
  if UNCACHED[id] then return nil end
  return "Item " .. id, "|Hitem:" .. id .. "|h[Item " .. id .. "]|h", 1, 1, 1, "", "", 1, "", 134400
end }
local ROSTER, OFFLINE = { "Ana Silva", "Bob", "Cid" }, { Cid = true }
for i = 1, 9 do ROSTER[#ROSTER + 1] = "Miner" .. i end
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local n = ROSTER[i]
  if n then return n, "Member", 3, 20, "Mage", "", "", "", not OFFLINE[n], 0, n == "Bob" and "WARRIOR" or "MAGE" end
end
FauxScrollFrame_GetOffset = function() return 0 end
FauxScrollFrame_Update, FauxScrollFrame_OnVerticalScroll, FauxScrollFrame_SetOffset = noop, noop, noop
local told
ChatFrame_SendTell = function(name) told = name end

local registry = {}
LibStub = setmetatable({
  NewLibrary = function(_, name) registry[name] = registry[name] or {}; return registry[name] end,
  GetLibrary = function(_, name) return registry[name] end,
  minor = 1,
}, { __call = function(_, name) registry[name] = registry[name] or {}; return registry[name] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
GuildOS.ProfCatalog = {
  build = "fixture",
  F = { line = 1, yellow = 2, grey = 3, out = 4, outCount = 5, enchant = 6, reqSkill = 7, spec = 8, focus = 9,
        src = 10, recipeItem = 11, category = 12, reagents = 13 },
  professions = { [186] = { child = 2946, primary = true, en = "Mining" },
                  [164] = { child = 2938, primary = true, en = "Blacksmithing" },
                  [185] = { child = 2939, primary = false, en = "Cooking" } },
  specs = { [9788] = 164 },
  stations = { [3] = "Forge" },
  byLine = { [186] = { 2657, 3304 }, [164] = { 2660, 9950 }, [185] = { 2538 } },
  recipes = {
    [2657] = { 186, 1, 25, 2840, 1, 0, 0, 0, 3, 3, 0, 0, { 2770, 1 } },
    [3304] = { 186, 65, 90, 3576, 1, 0, 0, 0, 3, 1, 0, 0, { 2771, 1 } },
    [2660] = { 164, 1, 15, 2862, 1, 0, 0, 0, 0, 1, 0, 0, { 2835, 1 } },
    [9950] = { 164, 210, 230, 7934, 1, 0, 210, 9788, 0, 2, 7978, 0, {} },
    [2538] = { 185, 1, 45, 2679, 1, 0, 0, 0, 0, 1, 0, 0, { 2672, 1 } },
  },
}
dofile(ADDON .. "/Modules/Professions.lua")
dofile(ADDON .. "/Modules/ProfDirectory.lua")
dofile(ADDON .. "/UI/ProfessionsPanel.lua")
local P = GuildOS.Professions
local ME, BOB, CID = P.OwnKey(), GuildOS:GetPlayerKey("Bob"), GuildOS:GetPlayerKey("Cid")
GuildOS.db = { members = {}, recipes = {}, professions = {
  [ME] = { src = "addon", ts = NOW, profs = {
    [186] = { rank = 21, max = 75, h = 1, n = 2, recipes = { 2657, 3304 }, extra = {} } } },
  [BOB] = { src = "addon", ts = NOW, profs = {
    [164] = { rank = 210, max = 300, spec = 9788, h = 1, n = 1, recipes = { 9950 }, extra = {} } } },
  [CID] = { src = "native", ts = NOW, profs = { [164] = {} } },
} }
-- Nine more who smelt copper: the card lists eight crafters and says how many more.
for i = 1, 9 do
  GuildOS.db.professions[GuildOS:GetPlayerKey("Miner" .. i)] = { src = "addon", ts = NOW, profs = {
    [186] = { rank = 30, max = 75, h = 1, n = 1, recipes = { 2657 }, extra = {} } } }
end

-- ── The panel ───────────────────────────────────────────────────────────
local container = CreateFrame("Frame")
container:SetSize(980, 600)
local panel = GuildOS:CreateProfessionsPanel(container)
check(panel and panel.state and #panel.railButtons == 4, "the panel builds with All plus three professions")
container.scripts.OnShow(container)
runTimers()
panel:Relayout(980, 600)
local st = panel.state
check(panel.visibleRows > 0 and #st.results == 5, "All shows every recipe: " .. #st.results)
check(showing("Spell 2660") and showing("nobody"), "a recipe nobody knows says so")
check(showing("Ana Silva") and showing("Bob"), "crafters show by name")
check(showing("Spell 9788") and showing("Forge"), "requirements show the specialization and the station")
check(showing("The guild knows 3 of 5 recipes"), "the footer counts what the guild knows")
panel.railButtons[2].scripts.OnClick(panel.railButtons[2])
check(st.line == 164 and #st.results == 2 and showing("Blacksmithing"), "a profession on the rail filters the recipes")
check(showing("2 crafters · 50%"), "the rail shows crafters and coverage")
for _, t in ipairs(panel.filterTabs) do
  if t.key == "gaps" then t.scripts.OnClick(t) end
end
check(#st.results == 1 and st.results[1].id == 2660, "Nobody crafts leaves the gap")
for _, t in ipairs(panel.filterTabs) do
  if t.key == "all" then t.scripts.OnClick(t) end
end
panel.search:SetText("spell 99")
panel.search.scripts.OnTextChanged(panel.search)
check(#st.results == 1 and st.results[1].id == 9950, "the search narrows the list")
panel.search:SetText("")
panel.search.scripts.OnTextChanged(panel.search)
local row = panel.rows[1]
check(rawget(row, "data") ~= nil, "the first row holds a recipe")
for _, r in ipairs(panel.rows) do
  local d = rawget(r, "data")
  if d and d.id == 9950 then row = r end
end
row.scripts.OnEnter(row)
row.scripts.OnLeave(row)
UNCACHED[7978] = true
row.scripts.OnClick(row)
local card = _G.GuildOSRecipeCard
check(card and card.shown, "a click opens the recipe card")
check(not showing("Item 7978") and showing("Recipe item"), "an uncached recipe item shows as a plain source")
UNCACHED[7978] = nil
card:ClearAllPoints()
card:SetPoint("CENTER", UIParent, "CENTER", 40, 40)   -- the user drags it away
panel.itemEvents.scripts.OnEvent(panel.itemEvents, "GET_ITEM_INFO_RECEIVED", 7978)
runTimers()
check(card.movedTo == "CENTER", "a repaint keeps the card where the user dragged it")
check(showing("Item 7978"), "the card repaints when the item's data arrives")
check(card.h > 100 and card.h < 300, "the card is as tall as what it shows: " .. tostring(card.h))
local whispered = false
for _, o in ipairs(all) do
  local label = rawget(o, "label")
  if o.kind == "Button" and o.shown and label and label.text == "Whisper" and o.scripts.OnClick then
    o.scripts.OnClick(o)
    whispered = true
    break
  end
end
check(whispered and told == "Bob", "Whisper opens a tell to the online crafter")
local smelt
panel.railButtons[1].scripts.OnClick(panel.railButtons[1])
for _, r in ipairs(panel.rows) do
  local d = rawget(r, "data")
  if d and d.id == 2657 then smelt = r end
end
smelt.scripts.OnClick(smelt)
check(showing("+2 more crafters"), "past eight crafters the card says how many more")
local tall = card.h
check(tall > 300, "and grows to hold them: " .. tostring(tall))
container.scripts.OnHide(container)
check(not card.shown, "the card closes with the panel")
panel.railButtons[2].scripts.OnClick(panel.railButtons[2])
panel.tabCrafters.scripts.OnClick(panel.tabCrafters)
check(st.mode == "crafters" and #st.results == 2 and st.results[1].name == "Bob" and st.results[2].native,
      "Crafters lists the members, native last")
check(showing("210 / 300") and showing("no addon"), "ranks and native members show")
panel.railButtons[1].scripts.OnClick(panel.railButtons[1])
check(#st.results == 0 and showing("Pick a profession on the left."), "Crafters with All asks for a profession")
panel.railButtons[4].scripts.OnClick(panel.railButtons[4])
check(#st.results == 0 and showing("Nobody in the guild has this profession yet."), "an empty profession says so")
panel:Relayout(520, 400)
check(panel.visibleRows > 0, "a narrow window still lays out")
panel:Relayout(560, 500)
local filtersW = 0
for _, t in ipairs(panel.filterTabs) do filtersW = filtersW + t.w + 4 end
local inner = 560 - 10 * 2 - 176 - 12
check(panel.search.w < 220 and panel.search.w + filtersW + 12 <= inner,
      "the search box gives way to the filters in a narrow window: " .. tostring(panel.search.w))
local placeholderShown = false
for _, o in ipairs(all) do
  if o.kind == "FontString" and o.parent == panel.search and o.text == "Search recipes..." then placeholderShown = o.shown end
end
check(not placeholderShown, "a box too narrow for its placeholder hides it")
panel:Relayout(1200, 500)
check(panel.search.w == 220, "and takes its full width in a wide one")
panel:Relayout(900, 100)
check(panel.railRow == 20 and panel.railButtons[1].h == 18 and not panel.railButtons[1].sub.shown,
      "a short window shrinks the rail rows and drops their second line")
panel:Relayout(900, 600)
check(panel.railRow == 36 and panel.railButtons[1].sub.shown, "a tall one gives them back")

print("professions-panel: " .. checks .. " checks passed")
