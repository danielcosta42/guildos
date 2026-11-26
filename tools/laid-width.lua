-- A text's width where the game has not laid its frame out yet (#449), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Utils.lua, Core/Data.lua, Core/Style.lua, UI/Helpers.lua, UI/Layout.lua, UI/Kit.lua and
-- Modules/Digest.lua under a stub frame API that answers GetWidth as the game does before its next drawn frame:
-- a frame's own set width, or 0 for one placed only by its anchors.
--
-- In the game the login digest drew its round glyphs and none of its lines: each line was given
-- `f.body:GetWidth() - 34`, the body is anchored (no set width), GetWidth said 0, and a FontString with a
-- negative width draws nothing. This checks UI:LaidWidth reads the anchors, that the digest's lines get the
-- body's width, that no text is ever handed a width under 1, and that no file hands a text `x:GetWidth() - n`.
--
--   luajit -e 'ADDON="."' tools/laid-width.lua
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

local widths = {}   -- every width a FontString was given
local function frame(kind, parent)
  local f = { kind = kind, shown = true, scripts = {}, parent = parent, points = {}, kids = {}, regions = {}, w = 0, h = 0 }
  if parent then
    if kind == "FontString" or kind == "Texture" then parent.regions[#parent.regions + 1] = f
    else parent.kids[#parent.kids + 1] = f end
  end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:SetShown(on) self.shown = on and true or false end
  function f:IsShown() return self.shown end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:HookScript(name, fn) local p = self.scripts[name]; self.scripts[name] = p and function(...) p(...); fn(...) end or fn end
  function f:GetParent() return self.parent end
  function f:SetText(t) self.text_ = t end
  function f:GetText() return self.text_ end
  function f:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
    self.points[#self.points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
  end
  function f:SetAllPoints(rel)
    rel = rel or self.parent
    self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
  end
  function f:GetNumPoints() return #self.points end
  function f:GetPoint(i) local p = self.points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
  function f:ClearAllPoints() self.points = {} end
  -- The game before its layout pass: a set width, else 0.
  function f:GetWidth() return self.w end
  function f:GetHeight() return self.h end
  function f:SetWidth(w)
    self.w = w
    if self.kind == "FontString" then widths[#widths + 1] = { fs = self, w = w } end
  end
  function f:SetHeight(h) self.h = h end
  function f:SetSize(w, h) self:SetWidth(w); self.h = h end
  function f:GetStringHeight() return 14 end
  function f:GetStringWidth() return #(self.text_ or "") * 6 end
  function f:GetFrameLevel() return 1 end
  function f:IsMovable() return self.movable end
  function f:SetMovable(v) self.movable = v end
  function f:SetTextColor(r, g, b) self.color = { r, g, b } end
  function f:SetVertexColor(r, g, b) self.color = { r, g, b } end
  function f:CreateFontString() return frame("FontString", self) end
  function f:CreateTexture() return frame("Texture", self) end
  function f:GetChildren() return unpack(self.kids) end
  function f:GetRegions() return unpack(self.regions) end
  return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
end
UIParent = frame("Frame")
UIParent.w, UIParent.h = 1600, 900
function CreateFrame(kind, _, parent) return frame(kind, parent or UIParent) end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.5", "70888", "", 20505 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetLocale() return "enUS" end
function GetRealmName() return "Realm" end
function GetServerTime() return 1790000000 end
function GetTime() return 1 end
function UnitFullName() return "Lead", "" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
UISpecialFrames, SlashCmdList = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

GuildOSDB = {}
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Style.lua")
GuildOS.db = { settings = {}, digest = { enabled = true, lastSeen = 1, feedSeen = {} } }
dofile(ADDON .. "/UI/Helpers.lua")
dofile(ADDON .. "/UI/Layout.lua")
dofile(ADDON .. "/UI/Kit.lua")
dofile(ADDON .. "/Modules/Digest.lua")
local UI = GuildOS.UI

-- ── LaidWidth reads the anchors ─────────────────────────────────────────
local win = CreateFrame("Frame", nil, UIParent)
win:SetSize(380, 280)
local body = CreateFrame("Frame", nil, win)
body:SetPoint("TOPLEFT", 16, -42)
body:SetPoint("BOTTOMRIGHT", -16, 48)
check(body:GetWidth() == 0, "the stub answers as the game before its layout: an anchored frame reads 0")
check(UI:LaidWidth(body) == 348, "LaidWidth: the window's 380 less 16 on each side (got " .. UI:LaidWidth(body) .. ")")
local inner = CreateFrame("Frame", nil, body)
inner:SetAllPoints()
check(UI:LaidWidth(inner) == 348, "SetAllPoints takes the whole width, through two anchored frames")
local top = CreateFrame("Frame", nil, body)
top:SetPoint("TOPLEFT", body, "TOPLEFT", 10, 0)
top:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, 0)
check(UI:LaidWidth(top) == 328, "a left and a right corner of the same frame")
local loose = CreateFrame("Frame", nil, body)
loose:SetPoint("TOPLEFT", 4, 0)
check(UI:LaidWidth(loose) == 0, "one anchor says nothing: 0, the caller keeps its floor")
check(UI:TextWidth(loose, 30) == 40, "and TextWidth never hands a text less than its floor")
local fixed = CreateFrame("Frame", nil, body)
fixed:SetAllPoints()
fixed:SetWidth(120)
check(UI:LaidWidth(fixed) == 120, "a frame's own width wins")

-- ── The digest's lines get the body's width ─────────────────────────────
local lines = { "Raid night logged: 2 sessions", "New members: Aldren, Nyx", "14 items looted" }
widths = {}
local f = GuildOS.Digest:Show(lines)
check(f and f.body, "the digest opens")
local texts = {}
for _, r in ipairs(f.body.regions) do if r.kind == "FontString" and r.text_ then texts[r.text_] = r end end
for _, line in ipairs(lines) do
  local fs = texts[line]
  check(fs, "the line '" .. line .. "' is a text in the body")
  check(fs.w and fs.w >= 200, "the line '" .. line .. "' is laid in the body's width, not under it (got " .. tostring(fs.w) .. ")")
end
for _, rec in ipairs(widths) do
  check(rec.w >= 1, "no text is handed a width under 1 (a negative width draws nothing in the game; got " .. tostring(rec.w) .. ")")
end
f:Hide()
widths = {}
GuildOS.Digest.frame = nil
local empty = GuildOS.Digest:Show({})
for _, rec in ipairs(widths) do check(rec.w >= 1, "the empty digest's line has a width too") end
empty:Hide()

-- ── No file hands a text an anchored frame's GetWidth less something ────
local files = io.popen("ls " .. ADDON .. "/UI/*.lua " .. ADDON .. "/Modules/*.lua " .. ADDON .. "/Core/*.lua")
for path in files:lines() do
  local src = assert(io.open(path, "rb")):read("*a")
  local n = 0
  for line in src:gmatch("[^\n]+") do
    n = n + 1
    -- `x:SetWidth(y:GetWidth() - n)` with no floor: 0 before the layout pass, so negative.
    local bad = line:match("SetWidth%(%s*[%w_.]+:GetWidth%(%)%s*%-")
    if bad and not line:find("math.max", 1, true) then
      check(false, path .. ":" .. n .. " hands a width of GetWidth() less something; use UI:TextWidth/UI:LaidWidth")
    end
  end
end
files:close()

print(("laid-width: %d checks passed"):format(checks))
