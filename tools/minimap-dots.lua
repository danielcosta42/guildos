-- The guild map's drawing (issues #271, #449), run against the real Modules/GuildMap.lua and UI/GuildMap.lua
-- (with Core, Compat and Utils) under a stub frame API and a fake Outland: the minimap dots switch (on by default,
-- kept, redrawn at once), a guildmate's dot at their real bearing and distance, none in an instance; the world
-- map's pins at the right spot on a zone and on the continent, sized by the zoom, fading when stale; the list
-- on the map; the watch the open map sends.
--
--   luajit -e 'ADDON="."' tools/minimap-dots.lua
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
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-6) end

-- ── A stub frame API ────────────────────────────────────────────────────
local function region(kind)
  local r = { kind = kind, shown = true, alpha = 1, scale = 1, w = 0, h = 0, scripts = {}, points = {}, level = 1 }
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:GetWidth() return self.w end
  function r:GetHeight() return self.h end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:SetAllPoints(o) self.all = o end
  function r:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
  function r:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  function r:SetShown(v) if v then self:Show() else self:Hide() end end
  function r:IsShown() return self.shown end
  function r:SetAlpha(a) self.alpha = a end
  function r:GetAlpha() return self.alpha end
  function r:SetScale(s) self.scale = s end
  function r:EnableMouse() end
  function r:SetScript(n, fn) self.scripts[n] = fn end
  function r:HookScript(n, fn)
    local old = self.scripts[n]
    self.scripts[n] = function(...) if old then old(...) end fn(...) end
  end
  function r:SetFrameLevel(l) self.level = l end
  function r:GetFrameLevel() return self.level end
  function r:SetFrameStrata() end
  function r:RegisterEvent() end
  function r:UnregisterAllEvents() end
  function r:SetTexture() end
  function r:SetVertexColor(...) self.color = { ... } end
  function r:SetTexCoord() end
  function r:SetText(t) self.text = t end
  function r:GetText() return self.text end
  function r:SetTextColor() end
  function r:SetJustifyH() end
  function r:SetWordWrap() end
  function r:GetStringHeight() return 12 end
  function r:GetStringWidth() return #(self.text or "") * 6 end
  function r:CreateTexture() return region("texture") end
  function r:CreateFontString() return region("font") end
  return r
end
function CreateFrame(_, _, parent)
  local f = region("frame")
  f.parent = parent
  return f
end
function hooksecurefunc(t, name, fn)
  local old = t[name]
  t[name] = function(...) local a, b = old(...); fn(...); return a, b end
end
GameTooltip = region("tooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

-- ── The client ──────────────────────────────────────────────────────────
strmatch = string.match
function GetBuildInfo() return "2.5.5", "60000", "", 20505 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function UnitFullName() return "Me", "Realm" end
function IsInGuild() return true end
Enum = { SendAddonMessageResult = {} }
local clock = 1000
function GetTime() return clock end
function time() return 1790000000 + math.floor(clock) end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return {} end }
local ROSTER = { { "Me", 70, "Shattrath City", "MAGE" }, { "Ann", 70, "Shattrath City", "PRIEST" } }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1], "Member", 1, r[2], r[4], r[3], "", "", true, 0, r[4] end
end
function GetNumGroupMembers() return 0 end
LOCALIZED_CLASS_NAMES_MALE = { PRIEST = "Priest" }

-- Outland is 10 000 yards each way; Shattrath (0.40..0.50, 0.60..0.70 of it) is 1000.
local MAPS = {
  [1945] = { name = "Outland", mapType = 2, parentMapID = 946 },
  [1955] = { name = "Shattrath City", mapType = 3, parentMapID = 1945 },
}
local function vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
CreateVector2D = vec
local me = { map = 1955, x = 0.5, y = 0.5 }
local inInstance = false
function IsInInstance() return inInstance, inInstance and "party" or "none" end
C_Map = {
  GetBestMapForUnit = function() return me.map end,
  GetPlayerMapPosition = function(map) if map == me.map then return vec(me.x, me.y) end end,
  GetMapInfo = function(id) return MAPS[id] end,
  GetMapRectOnMap = function(c, p) if c == 1955 and p == 1945 then return 0.40, 0.50, 0.60, 0.70 end end,
  GetWorldPosFromMapPos = function(map, v)
    local cx, cy = v.x, v.y
    if map == 1955 then cx, cy = 0.40 + v.x * 0.1, 0.60 + v.y * 0.1 elseif map ~= 1945 then return nil end
    return 530, vec(5000 - cy * 10000, 5000 - cx * 10000)
  end,
  GetMapPosFromWorldPos = function() return nil end,
}
Minimap = CreateFrame("Frame")
Minimap:SetSize(140, 140)
local zoom = 2
function Minimap:GetZoom() return zoom end
function IsIndoors() return false end
function GetCVar() return "0" end

-- The world map: a canvas 1000 x 800, the shown map, the zoom.
local shownMap = 1955
local canvas = CreateFrame("Frame")
canvas:SetSize(1000, 800)
local canvasScale, zoomPct = 1, 0
WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.shown = false
WorldMapFrame.ScrollContainer = CreateFrame("Frame")
function WorldMapFrame.ScrollContainer:GetCanvasScale() return canvasScale end
function WorldMapFrame:GetCanvasZoomPercent() return zoomPct end
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return shownMap end
function WorldMapFrame:SetMapID(id) shownMap = id; self:OnMapChanged() end
function WorldMapFrame:OnMapChanged() end
function ToggleWorldMap() if WorldMapFrame.shown then WorldMapFrame:Hide() else WorldMapFrame:Show() end end
function InCombatLockdown() return false end

-- ── The addon ───────────────────────────────────────────────────────────
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/GuildMap.lua")
local GM = GuildOS.GuildMap
local sent = {}
GuildOS.CommSystem = { MSG_TYPES = { MAP_POS = "MP", MAP_WATCH = "MW" },
  SendMessage = function(_, code, data) sent[#sent + 1] = { code = code, data = data } end }
-- What UI/GuildMap.lua takes from the skin (UI/Helpers.lua, Core/Style.lua): stubbed to plain frames.
local col = { r = 1, g = 1, b = 1 }
GuildOS.Colors = setmetatable({}, { __index = function() return col end })
GuildOS.ClassColors = { PRIEST = { r = 1, g = 1, b = 1 } }
GuildOS.Spacing = { PAD = 16, TOP = 42, HIT = 24, BODY = 13, META = 11, MARGIN = 8 }
GuildOS.Style = { Texture = function(_, f) return f:CreateTexture() end }
GuildOS.UI = {
  CreateAvatar = function(_, parent, size)
    local a = CreateFrame("Button", nil, parent)
    a:SetSize(size, size)
    function a:SetMember(name, class) self.member = { name, class } end
    return a
  end,
  CreateCard = function(_, parent, title)
    local c = CreateFrame("Frame", nil, parent)
    c.title = c:CreateFontString(); c.title:SetText(title); c:Hide()
    return c
  end,
  CreateCloseButton = function(_, parent) return CreateFrame("Button", nil, parent) end,
  CreateText = function(_, parent, text) local fs = parent:CreateFontString(); fs:SetText(text); return fs end,
  CreateRowSelection = function(_, row) return row:CreateTexture() end,
}
dofile(ADDON .. "/UI/GuildMap.lua")
GuildOS.db = {}

-- ── 1. The switch ───────────────────────────────────────────────────────
check(GM:IsMinimapDots() == false, "the dots are off by default: guildmates belong on the world map (2.1.1)")
GM:SetMinimapDots(true)
check(GM:IsMinimapDots() == true and GuildOS.db.guildMapPrefs.minimapDots == true, "Settings turns them on, and it is kept")
local redrawn = 0
GM.uiRefresh = function() redrawn = redrawn + 1 end
GM:SetMinimapDots(false)
check(GM:IsMinimapDots() == false and GuildOS.db.guildMapPrefs.minimapDots == false, "turned off and kept")
check(redrawn == 1, "and the minimap redraws at once, no /reload")
GM:SetMinimapDots(true)
check(GM:IsMinimapDots() == true and redrawn == 2, "and back on")
GuildOS.db = {}
check(GM:IsMinimapDots() == false, "a character that never chose does not see them (2.1.1)")
GM:SetMinimapDots(true)   -- the rest of this file draws dots: turned on, as Settings does

-- ── 2. The minimap dot at the real bearing ──────────────────────────────
local driver
-- Frames created inside the UI file are not globals: collect them through CreateFrame.
local made = {}
local realCreate = CreateFrame
function CreateFrame(...) local f = realCreate(...); made[#made + 1] = f; return f end
GuildOS._guildMapPresence = nil
GuildOS:SetupGuildMapPresence()
for _, f in ipairs(made) do if f.parent == Minimap and f.scripts.OnUpdate then driver = f end end
check(driver ~= nil, "a driver on the minimap redraws the dots")
local function dotsNow()
  driver.scripts.OnUpdate(driver, 1)
  local out = {}
  for _, f in ipairs(made) do
    if f.parent == Minimap and f ~= driver and f.shown then out[#out + 1] = f end
  end
  return out
end
-- Ann, 100 yards north and 50 east of me (Shattrath is 1000 yards: 0.1 and 0.05 of it).
GM:HandlePosition("Ann", "1955,5500,4000,,0", "GUILD")
local d = dotsNow()
check(#d == 1, "one guildmate in my zone: one dot")
local pt = d[1].points[1]
local rPx = 140 / 2 - 6
local rYd = GM:_MinimapRadius(zoom, false)
check(pt[2] == Minimap and pt[3] == "CENTER" and near(pt[4], 50 * rPx / rYd, 0.1) and near(pt[5], 100 * rPx / rYd, 0.1),
  "the dot sits at the guildmate's bearing and distance, north up")
zoom = 5
d = dotsNow()
pt = d[1].points[1]
check(near(math.sqrt(pt[4] ^ 2 + pt[5] ^ 2), rPx, 1e-3) and d[1].alpha < 1, "zoomed in past them: held at the edge, dimmer")
zoom = 2
inInstance = true
check(#dotsNow() == 0, "in an instance: no dots")
inInstance = false
GM:SetMinimapDots(false)
check(#dotsNow() == 0, "dots off: none")
GM:SetMinimapDots(true)

-- ── 3. The world map ────────────────────────────────────────────────────
sent = {}
GuildOS:ToggleGuildMap()
check(WorldMapFrame:IsShown(), "/gos map opens the world map")
local lastWatch
for _, m in ipairs(sent) do if m.code == "MW" then lastWatch = m.data end end
check(lastWatch == "1955", "and the open map watches the shown map: guildmates there start sending")
local layer
for _, f in ipairs(made) do if f.parent == canvas then layer = f end end
check(layer and layer.all == canvas, "our layer lies over the map's canvas")
layer:SetSize(1000, 800)
layer.scripts.OnUpdate(layer, 1)
local pins = {}
for _, f in ipairs(made) do if f.parent == layer and f.member and f.shown then pins[#pins + 1] = f end end
check(#pins == 1 and pins[1].member[1] == "Ann" and pins[1].member[2] == "PRIEST", "a pin for Ann, her class's avatar")
pt = pins[1].points[#pins[1].points]
check(near(pt[4], 0.55 * 1000, 0.5) and near(pt[5], -0.40 * 800, 0.5), "at her spot on the zone's map")
canvasScale, zoomPct = 2, 1
layer.scripts.OnUpdate(layer, 0.05)
pt = pins[1].points[#pins[1].points]
check(near(pins[1].scale, 1.5 / 2) and near(pt[4] * pins[1].scale, 550, 0.5), "zoomed in: a little bigger, still on the spot")
canvasScale, zoomPct = 1, 0
WorldMapFrame:SetMapID(1945)
layer.scripts.OnUpdate(layer, 1)
pt = pins[1].points[#pins[1].points]
check(pins[1].shown and near(pt[4], (0.40 + 0.055) * 1000, 0.5) and near(pt[5], -(0.60 + 0.04) * 800, 0.5),
  "on the continent: the same guildmate, where Shattrath lies on Outland")
lastWatch = nil
for _, m in ipairs(sent) do if m.code == "MW" then lastWatch = m.data end end
check(lastWatch == "1945", "and the watch follows the shown map")
pins[1].scripts.OnEnter(pins[1])
local tip = table.concat(GameTooltip.lines, "|")
check(tip:find("Ann") and tip:find("Level 70 Priest", 1, true) and tip:find("Shattrath City") and tip:find("Updated"),
  "hover: name, level and class, zone, how long ago (" .. tip .. ")")
clock = clock + 60
layer.scripts.OnUpdate(layer, 1)
check(pins[1].alpha < 1 and pins[1].alpha > 0, "a minute without news: the pin fades")
clock = clock + 70
layer.scripts.OnUpdate(layer, 1)
check(not pins[1].shown, "two minutes: it is gone")

-- The list on the map.
GM:HandlePosition("Ann", "1955,5500,4000,,0", "GUILD")
layer.scripts.OnUpdate(layer, 1)
local listCard
for _, f in ipairs(made) do if f.head then listCard = f end end
check(listCard and listCard.shown, "the guild list shows on the map")
check(listCard.head.text == "Guildmates on this map (1)", "with its count line")
GM:SetSharing(false)
layer.scripts.OnUpdate(layer, 1)
check(listCard.foot.text:find("You are not sharing your position", 1, true), "sharing off: the list says so")
GM:SetSharing(true)
WorldMapFrame:Hide()
lastWatch = nil
for _, m in ipairs(sent) do if m.code == "MW" then lastWatch = m.data end end
check(lastWatch ~= "1945", "closing the map ends its watch")

-- ── 4. Allies (site spec 123): on the world map, in my zone, never on the minimap ──────────────────────
local allyShare = true
GuildOS.Alliance = { MyGuildName = function() return "Guilda A" end, MemberInfo = function() end,
  GuildColor = function() return 0.2, 0.4, 0.6 end }
GuildOS.AllianceLink = {
  Active = function() return true end,
  Shares = function(_, item, dir) return item == "map" and (dir == "send" or allyShare) end,
  ChannelIndex = function() return 5 end, ChannelName = function() return "GOSAPACTOabc123" end,
  Throttled = function() return false end,
  Code = function(g) return g == "Guilda A" and "aaa" or "bbb" end,
  IsMe = function() return false end,
  Speaker = function(a) return (a:gsub("%-Realm$", "")) end,
  GuildOfLine = function(_, code) return code == "bbb" and "Guilda B" or nil end,
}
dofile(ADDON .. "/Modules/AllianceMap.lua")
local AM = GuildOS.AllianceMap
GM:HandlePosition("Ann", "1955,5500,4000,,0", "GUILD")
check(AM:HandleLine("Bia-Realm", "1,bbb,1955,2500,2500"), "an ally's line in my zone is kept")
WorldMapFrame:Show()
WorldMapFrame:SetMapID(1955)
layer.scripts.OnUpdate(layer, 1)
local allyPin
for _, f in ipairs(made) do
  if f.parent == layer and f.member and f.member[1] == "Bia" and f.shown then allyPin = f end
end
check(allyPin ~= nil, "the world map draws the ally")
check(allyPin.tag and allyPin.tag.text == "GB", "in its own style: the guild's initials under the pin")
pt = allyPin.points[#allyPin.points]
check(near(pt[4], 0.25 * 1000, 0.5) and near(pt[5], -0.25 * 800, 0.5), "at the ally's spot on the zone")
allyPin.scripts.OnEnter(allyPin)
tip = table.concat(GameTooltip.lines, "|")
check(tip:find("Bia", 1, true) and tip:find("Allied guild: Guilda B", 1, true), "hover names the ally and the guild (" .. tip .. ")")
local dotKeys = {}
for _, dd in ipairs(dotsNow()) do dotKeys[#dotKeys + 1] = tostring(dd.key) end
local annKey = next(GM.peers)
check(#dotKeys == 1 and dotKeys[1] == annKey, "the minimap draws the guildmate only, never the ally ("
  .. table.concat(dotKeys, ",") .. ")")
for _, k in ipairs(dotKeys) do check(not k:find("^ally:"), "no minimap dot for an ally") end
allyShare = false
layer.scripts.OnUpdate(layer, 1)
check(not allyPin.shown, "map.recv off: the ally's pin goes")
allyShare = true
WorldMapFrame:SetMapID(1945)
layer.scripts.OnUpdate(layer, 1)
check(allyPin.shown, "on the continent too, while the ally is in my zone")
me.map = 1945
layer.scripts.OnUpdate(layer, 1)
check(not allyPin.shown, "out of the ally's zone: no pin")
me.map = 1955
WorldMapFrame:Hide()

print(("minimap-dots: %d checks passed"):format(checks))
