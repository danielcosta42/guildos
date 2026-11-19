-- The Crafts tab (issue #389) built and driven like a user on WoW: Forever: the catalog (the
-- Professions panel) beside the order queue, the queue a drawer in a narrow window, its cards
-- acting on the orders, an item opened from anywhere, and the count on the window's tab. Same
-- permissive frame stub as tools/professions-panel.lua.
--
--   luajit -e 'ADDON="."' tools/crafts-tab.lua
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
function IsShiftKeyDown() return false end

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
dofile(ADDON .. "/Core/Style.lua")
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
dofile(ADDON .. "/Modules/RecipeTracker.lua")
dofile(ADDON .. "/Modules/CraftOrders.lua")
dofile(ADDON .. "/UI/CraftOrdersPanel.lua")
local O = GuildOS.CraftOrders

local P = GuildOS.Professions
local ME, BOB, CID = P.OwnKey(), GuildOS:GetPlayerKey("Bob"), GuildOS:GetPlayerKey("Cid")
check(O:MyKey() == ME, "an order's key for me is the professions' key for me")
GuildOS.db = { members = {}, recipes = {}, settings = {}, professions = {
  [ME] = { src = "addon", ts = NOW, profs = {
    [186] = { rank = 21, max = 75, h = 1, n = 2, recipes = { 2657, 3304 }, extra = {} } } },
  [BOB] = { src = "addon", ts = NOW, profs = {
    [164] = { rank = 210, max = 300, spec = 9788, h = 1, n = 1, recipes = { 9950 }, extra = {} } } },
}, craftOrders = {
  -- Bob asks me for copper bars (I smelt them).
  T1 = { id = "T1", who = BOB, item = 2840, n = 4, mode = "mats", tip = 50000, to = ME, st = "open", ts = NOW - 60, at = NOW - 60 },
  -- I asked for Bob's item; he took it.
  M1 = { id = "M1", who = ME, item = 7934, n = 1, mode = "mats", tip = 0, st = "accepted", cr = BOB, acc = NOW - 30, ts = NOW - 90, at = NOW - 30 },
  -- Cid asks the guild for tin bars (I smelt them too).
  O1 = { id = "O1", who = CID, item = 3576, n = 2, mode = "own", tip = 0, st = "open", ts = NOW - 20, at = NOW - 20 },
} }

-- ── The tab ─────────────────────────────────────────────────────────────
local opened
UI = GuildOS.UI
function UI:OpenWindow(id, sub) opened = { id, sub }; return true end
local container = CreateFrame("Frame")
container:SetSize(1200, 620)
local panel = GuildOS:CreateCraftsTab(container)
check(panel and panel.state and container.queue, "the tab builds the catalog and the queue")
container.LayoutCrafts(1200)
check(container.dock.shown and not container.toggle.shown, "a wide window shows the queue beside the catalog")
container.LayoutCrafts(800)
check(not container.dock.shown and container.toggle.shown, "a narrow one folds it into a button")
container.toggle.scripts.OnClick(container.toggle)
check(container.dock.shown, "which opens it as a drawer")
container.toggle.scripts.OnClick(container.toggle)
check(not container.dock.shown, "and closes it")
container.LayoutCrafts(1200)
container.scripts.OnShow(container)
runTimers()
panel.parent:SetSize(900, 600)   -- the stub gives an anchored frame no size: the catalog's host gets one
panel:Relayout()

-- ── The queue ───────────────────────────────────────────────────────────
local q = container.queue
check(q.view == "forme", "it opens on For me while something waits there")
q.area:SetSize(280, 500)
q.area.scripts.OnSizeChanged(q.area)
q:Draw()
local function card(id)
  for _, c in ipairs(q.cards) do if c.shown and rawget(c, "data") and c.data.id == id then return c end end
end
local c = card("T1")
check(c and c.b1.label.text == "Accept" and c.b2.label.text == "Decline", "an order sent to me: Accept, or Decline")
check(showing("from Bob · sent to you"), "and says who sent it")
check(q.tabs[1].label.text == "For me 1" and q.tabs[2].label.text == "Mine 1" and q.tabs[3].label.text == "Open 1",
      "each view counts what is running in it")
c.b1.scripts.OnClick(c.b1)
check(O:Get("T1").st == "accepted" and O:Get("T1").cr == ME, "Accept takes it")
q:Draw()
c = card("T1")
check(c and c.b1.label.text == "Whisper" and c.b2.label.text == "Give back",
      "taken, while Bob brings the materials: Whisper, or Give back")
q:Select("mine")
c = card("M1")
check(c and c.b1.label.text == "Trade" and showing("accepted by Bob"), "my order Bob took: Trade him the materials")
q:Select("open")
c = card("O1")
check(c and c.b1.label.text == "Accept" and showing("from Cid"), "an open order I can craft, from Cid")
check(showing("Crafter's materials"), "with whose materials it is made")

-- ── An item opened from anywhere ────────────────────────────────────────
check(GuildOS:ShowCraftFor(2840) and opened[1] == "recipes", "an item opens the Crafts tab")
check(panel.state.open == 2657 and panel.state.item == 2840 and panel.detail.shown, "on the recipe that makes it, opened")
check(showing("Recipes for Item 2840"), "the title says which item")
local dialog = false
GuildOS.ShowCraftOrderDialog = function() dialog = true end
GuildOS:ShowCraftFor(99999)
check(dialog, "an item the catalog does not list still gets the order dialog")
panel.railButtons[1].scripts.OnClick(panel.railButtons[1])
check(panel.state.item == nil, "the rail lets go of the item")

-- ── The filters and marks ───────────────────────────────────────────────
local function recipes()
  local out = {}
  for _, e in ipairs(panel.state.results) do if not e.__detail then out[#out + 1] = e.id end end
  return out
end
for _, t in ipairs(panel.filterTabs) do if t.key == "mine" then t.scripts.OnClick(t) end end
check(#recipes() == 2, "I craft keeps the two recipes I know: " .. table.concat(recipes(), ","))
for _, t in ipairs(panel.filterTabs) do if t.key == "orders" then t.scripts.OnClick(t) end end
local ids = recipes()
check(#ids == 3, "With orders keeps the recipes someone ordered: " .. table.concat(ids, ","))
check(showing("1 orders"), "and each says how many")

-- ── The count on the window's tab ───────────────────────────────────────
local tab = { key = "recipes", label = CreateFrame("Frame") }
tab.label:SetText("Crafts")
local laid = 0
GuildOS:PaintCraftsBadge()
check(laid == 0, "with no window yet nothing is built to paint it")
GuildOS.RosterFrame = { tabs = { tab }, LayoutTabs = function() laid = laid + 1 end }
GuildOS:PaintCraftsBadge()
check(tab.label.text == "Crafts (" .. O:InboxCount() .. ")" and laid == 1, "the tab counts what waits for me: " .. tab.label.text)
for _, o in pairs(GuildOS.db.craftOrders) do o.st = "cancelled" end
GuildOS:PaintCraftsBadge()
check(tab.label.text == "Crafts" and laid == 2, "and says nothing once nothing does")

-- ── Glyphs the font has ─────────────────────────────────────────────────
-- IBM Plex has no geometric shapes or check marks: a "●" drew as a box beside each online crafter.
-- The online mark is a texture, and the Crafts files carry none of these characters.
local MISSING = { "●", "○", "▸", "►", "◆", "✓", "✔", "★", "☆" }
for _, f in ipairs({ "UI/CraftOrdersPanel.lua", "UI/ProfessionsPanel.lua", "UI/RecipesPanel.lua",
                     "Modules/CraftOrders.lua", "Modules/RecipeTracker.lua", "UI/CraftFinder.lua" }) do
  local h = io.open(ADDON .. "/" .. f, "rb")
  local src = h:read("*a")
  h:close()
  for _, g in ipairs(MISSING) do
    check(not src:find(g, 1, true), f .. " draws no " .. g .. " (the font has no such glyph)")
  end
end
GuildOS.RosterFrame = nil
for _, o in pairs(GuildOS.db.craftOrders) do o.st = "open" end
GuildOS:ShowCraftFor(2840)
local dots = 0
for _, slot in ipairs(panel.detail.who) do if slot.dot.shown then dots = dots + 1 end end
check(dots >= 1 and not showing("●"), "an online crafter gets a drawn dot, no character")

print("crafts-tab: " .. checks .. " checks passed")
