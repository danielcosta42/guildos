-- Guildmates' campfires (chehulnet AGENTS.md "ChehulCamp", ChehulNet v17; specs/salao/mapa.md "Fogueiras"), run
-- against the real Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/Commands.lua, Modules/ChehulNet.lua (over a
-- mesh that records what it sends), Modules/ChehulNetWire.lua, Modules/Mesh.lua, Modules/GuildMap.lua and
-- UI/GuildMap.lua, with the real AceComm-3.0, under a stubbed WoW: Forever client; then the real UI/SettingsPanel.lua
-- under the Settings harness (tools/settings-panel.lua's frames), on Forever and on Anniversary. With a Warmth
-- checkout next to this one (../warmth, or WARMTH=<path>), every camp line also goes through Warmth's own
-- Wire.Decode, and both must agree.
--
-- What it holds: the wire turns the beacon on, opt-out, with a store and a one-line notice, on Forever only; the
-- notice comes once, at the first kit lit, and the announce goes out (named on guild, ownerless on the realm); a no
-- stops it; with Warmth loaded nothing is sent; /gos campfire; the settings toggles; a camp line's decoding in
-- Warmth's real format, valid and not; only GUILD, only a guildmate on the roster, never a sighting; the end, the
-- burn-out and the quiet; the flame on the map, its tooltip and its waypoint; the layer off with Warmth and off
-- Forever; the member window's addon labels.
--
--   luajit -e 'ADDON="."' tools/guild-camps.lua
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
local frames = {}
local function region(kind)
  local r = { kind = kind, shown = true, alpha = 1, scale = 1, w = 0, h = 0, scripts = {}, points = {}, level = 1,
              events = {} }
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:GetWidth() return self.w end
  function r:GetHeight() return self.h end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:GetPoint() local p = self.points[1] or {}; return p[1], p[2], p[3], p[4], p[5] end
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
  function r:GetScript(n) return self.scripts[n] end
  function r:HookScript(n, fn)
    local old = self.scripts[n]
    self.scripts[n] = function(...) if old then old(...) end fn(...) end
  end
  function r:SetFrameLevel(l) self.level = l end
  function r:GetFrameLevel() return self.level end
  function r:SetFrameStrata() end
  function r:RegisterEvent(e) self.events[e] = true end
  function r:RegisterUnitEvent(e) self.events[e] = true end
  function r:UnregisterEvent(e) self.events[e] = nil end
  function r:UnregisterAllEvents() self.events = {} end
  function r:SetTexture(t) self.texture = t end
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
function CreateFrame(_, name, parent)
  local f = region("frame")
  f.parent = parent
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = CreateFrame("Frame")
function hooksecurefunc(t, name, fn)
  if type(t) == "string" then t, name, fn = _G, t, name end
  if type(t) ~= "table" then return end
  local old = t[name]
  if not old then return end
  t[name] = function(...) local a, b = old(...); fn(...); return a, b end
end
GameTooltip = region("tooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

-- Every frame that listens to `event` hears it.
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- ── The client: WoW: Forever 1.60.1 ─────────────────────────────────────
strmatch = string.match
function strsplit(sep, s)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return unpack(out)
end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1 -- Forever may answer the mainline id; its interface says 16001
function GetBuildInfo() return "1.60.1", "70888", "", 16001 end
function GetRealmName() return "Realm" end
function UnitName() return "Me" end
function UnitFullName() return "Me", "Realm" end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 60 end
function UnitExists() return false end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
function IsInGuild() return true end
function GetNumGroupMembers() return 0 end
function IsInInstance() return false, "none" end
function InCombatLockdown() return false end
function UnitAffectingCombat() return false end
function GetFramerate() return 60 end
Enum = { SendAddonMessageResult = {} }
local clock = 1000
function GetTime() return clock end
function time() return 1790000000 + math.floor(clock) end

local timers = {}
C_Timer = {
  After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end,
  NewTicker = function(d, fn)
    local t = { at = clock + d, every = d, fn = fn }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = t
    return t
  end,
}
local function advance(secs)
  local to = clock + secs
  while true do
    local nxt
    for _, t in ipairs(timers) do
      if not t.done and not t.cancelled and t.at <= to and (not nxt or t.at < nxt.at) then nxt = t end
    end
    if not nxt then break end
    clock = nxt.at
    if nxt.every then nxt.at = nxt.at + nxt.every else nxt.done = true end
    nxt.fn()
  end
  clock = to
end

local ROSTER = { { "Me", 60, "Elwynn Forest", "MAGE" }, { "Ann", 60, "Elwynn Forest", "PRIEST" },
                 { "Bob", 58, "Westfall", "WARRIOR" } }
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i)
  local r = ROSTER[i]
  if r then return r[1], "Member", 1, r[2], r[4], r[3], "", "", true, 0, r[4] end
end
LOCALIZED_CLASS_NAMES_MALE = { PRIEST = "Priest" }

-- Eastern Kingdoms 1415, Elwynn 1429 on it (0.40..0.50, 0.70..0.80), Westfall 1436 (0.30..0.40, 0.75..0.85).
local MAPS = {
  [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 946 },
  [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
  [1436] = { name = "Westfall", mapType = 3, parentMapID = 1415 },
}
local RECTS = { [1429] = { 0.40, 0.50, 0.70, 0.80 }, [1436] = { 0.30, 0.40, 0.75, 0.85 } }
local function vec(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
CreateVector2D = vec
local me = { map = 1429, x = 0.4, y = 0.6, wx = 0, wy = 0 }
local waypoint, superTracked
C_Map = {
  GetBestMapForUnit = function() return me.map end,
  GetPlayerMapPosition = function(map) if map == me.map then return vec(me.x, me.y) end end,
  GetMapInfo = function(id) return MAPS[id] end,
  GetMapRectOnMap = function(c, p)
    local r = RECTS[c]
    if r and MAPS[c].parentMapID == p then return r[1], r[2], r[3], r[4] end
  end,
  GetWorldPosFromMapPos = function() return nil end,
  GetMapPosFromWorldPos = function() return nil end,
  CanSetUserWaypointOnMap = function(id) return MAPS[id] ~= nil and MAPS[id].mapType == 3 end,
  SetUserWaypoint = function(p) waypoint = p end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = vec(x, y) } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) superTracked = on end }
function UnitPosition() return me.wy, me.wx, 0, 0 end
local warmth = false
C_AddOns = { IsAddOnLoaded = function(name) return name == "Warmth" and warmth end }
local KIT_SPELL = { [279981] = 1279981, [279961] = 1279961, [279974] = 1279974 }
C_Item = { GetItemSpell = function(item) return KIT_SPELL[item] and "Campfire", KIT_SPELL[item] end }
C_UnitAuras = { GetPlayerAuraBySpellID = function() return nil end }

-- What goes on the wire through the mesh (the beacon's announces).
local meshSent = {}
_G.ChehulMesh = setmetatable({ version = 11, stats = { recv = 0 },
  Guild = function(_, prefix, msg) meshSent[#meshSent + 1] = { bus = "GUILD", prefix = prefix, msg = msg } end,
  Group = function(_, prefix, msg) meshSent[#meshSent + 1] = { bus = "GROUP", prefix = prefix, msg = msg } end,
  Realm = function(_, prefix, msg) meshSent[#meshSent + 1] = { bus = "REALM", prefix = prefix, msg = msg } end,
}, { __index = function() return function() end end })
local function campsSent(kind)   -- on GUILD (the beacon also sends to the group and the realm)
  local n = 0
  for _, s in ipairs(meshSent) do
    if s.bus == "GUILD" and s.prefix == "ChehulCamp" and (not kind or s.msg:sub(1, 4) == "C2|" .. kind) then n = n + 1 end
  end
  return n
end

-- ── The addon ───────────────────────────────────────────────────────────
dofile(ADDON .. "/Libs/LibStub.lua")
function securecallfunction(fn, ...) return fn(...) end
dofile(ADDON .. "/Libs/CallbackHandler-1.0.lua")
dofile(ADDON .. "/Libs/ChatThrottleLib.lua")
local registeredPrefixes = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function(p) registeredPrefixes[p] = true; return true end,
               InChatMessagingLockdown = function() return false end }
dofile(ADDON .. "/Libs/AceComm-3.0.lua")

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
GuildOSDB = {}
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
check(GuildOS.Client.game == "FOREVER", "the stub is WoW: Forever")
local printed = {}
function GuildOS:Print(msg) printed[#printed + 1] = tostring(msg) end
local function saidSince(from, text)
  for k = from + 1, #printed do if printed[k]:find(text, 1, true) then return true end end
  return false
end
dofile(ADDON .. "/Modules/ChehulNet.lua")
local CN = _G.ChehulNet
check(CN and CN.version >= 17 and CN.EnableCamps and CN.SetCampConsent and CN.SetCampRealm and CN.CampRealmOn,
  "ChehulNet v17's beacon is there")

-- The wire, watched: what it hands EnableCamps.
local realEnable, enabled = CN.EnableCamps, {}
CN.EnableCamps = function(self, opts) enabled[#enabled + 1] = opts; return realEnable(self, opts) end
dofile(ADDON .. "/Modules/ChehulNetWire.lua")
dofile(ADDON .. "/Modules/Mesh.lua")
dofile(ADDON .. "/Modules/GuildMap.lua")
local GM = GuildOS.GuildMap
GuildOS.db = { members = {} }
GuildOS.CommSystem = { MSG_TYPES = { MAP_POS = "MP", MAP_WATCH = "MW" }, SendMessage = function() end }
GM:Initialize()

-- What UI/GuildMap.lua takes from the skin: plain frames (as tools/minimap-dots.lua).
local col = { r = 1, g = 1, b = 1 }
GuildOS.Colors = setmetatable({}, { __index = function() return col end })
GuildOS.ClassColors = { PRIEST = col }
GuildOS.Spacing = { PAD = 16, TOP = 42, HIT = 24, BODY = 13, META = 11, MARGIN = 8, FIELD = 26 }
GuildOS.Style = { Texture = function(_, f) return f:CreateTexture() end }
local function button(parent, label)
  local b = CreateFrame("Button", nil, parent)
  b.label = b:CreateFontString(); b.label:SetText(label)
  return b
end
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
  CreateButton = function(_, parent, label) return button(parent, label) end,
  SetButtonVariant = function(_, b) return b end,
}
local floats = {}
GuildOS.Kit = { PAD = 16, HEADER_H = 30, FOOT_H = 40,
  Float = function(_, title, opts)
    local f = CreateFrame("Frame", opts.name, UIParent)
    f:Hide()
    f.titleText = title
    f.body = CreateFrame("Frame", nil, f)
    f.foot = CreateFrame("Frame", nil, f)
    function f.foot:Lay(...) self.laid = { ... } end
    floats[#floats + 1] = f
    return f
  end }

-- The world map: a canvas 1000 x 800 showing Elwynn.
local shownMap = 1429
local canvas = CreateFrame("Frame")
canvas:SetSize(1000, 800)
WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.shown = false
WorldMapFrame.ScrollContainer = CreateFrame("Frame")
function WorldMapFrame.ScrollContainer:GetCanvasScale() return 1 end
function WorldMapFrame:GetCanvasZoomPercent() return 0 end
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return shownMap end
function WorldMapFrame:SetMapID(id) shownMap = id; self:OnMapChanged() end
function WorldMapFrame:OnMapChanged() end
function ToggleWorldMap() if WorldMapFrame.shown then WorldMapFrame:Hide() else WorldMapFrame:Show() end end
Minimap = CreateFrame("Frame")
Minimap:SetSize(140, 140)
function Minimap:GetZoom() return 2 end
function IsIndoors() return false end
function GetCVar() return "0" end
dofile(ADDON .. "/UI/GuildMap.lua")
function strtrim(t) return (tostring(t):gsub("^%s+", ""):gsub("%s+$", "")) end
SlashCmdList = {}
dofile(ADDON .. "/Core/Commands.lua")
local function slash(text) SlashCmdList.GUILDOS(text) end

-- ── 1. The wire: EnableCamps, opt-out, with a store and a notice, on Forever only ─
check(#enabled == 1, "the wire turns the beacon on once on Forever")
check(type(enabled[1].store) == "function" and enabled[1].default == true and type(enabled[1].notice) == "function",
  "with a store, default = true and a notice")
check(enabled[1].ask == nil, "and no question")
local store = enabled[1].store()
check(type(store) == "table" and store == GuildOSDB.camps, "the store is GuildOSDB.camps")
check(enabled[1].store() == store, "the same table each time")
check(CN:CampState() == "default", "nobody chose: on by default")

-- Elsewhere the wire never calls it (a spy that does not reach the lib).
for _, which in ipairs({ "isAnniversary", "isRetail" }) do
  local calls = 0
  local saved = CN.EnableCamps
  CN.EnableCamps = function() calls = calls + 1 end
  GuildOS.Client[which] = true
  dofile(ADDON .. "/Modules/ChehulNetWire.lua")
  GuildOS.Client[which] = false
  CN.EnableCamps = saved
  check(calls == 0, "no beacon when " .. which)
end

-- ── 2. The first kit: one chat line, once ever, and the announce ───────
local NOTICE = "Your campfire shows on the map for guildmates and players with Warmth (anonymous outside your guild and group). To turn it off: /gos campfire off"
local castFrame = CN.campFrame
check(castFrame and castFrame.events.UNIT_SPELLCAST_SUCCEEDED, "the lib listens for the kit's cast")
local function cast(spell) castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", spell) end
advance(120)
check(campsSent() == 0 and not saidSince(0, NOTICE), "nothing said at login, nothing sent")
local p0 = #printed
cast(1279961)   -- a Journeyman kit
check(saidSince(p0, NOTICE), "the first fire says so in one chat line")
check(store.noticed == true, "once ever (kept in the store)")
check(_G.GuildOSCampPrompt == nil, "and no window asks anything")
advance(2)
check(campsSent("A") == 1, "the fire lit is announced on GUILD")
local announce
for _, m in ipairs(meshSent) do if m.bus == "GUILD" and m.prefix == "ChehulCamp" then announce = m.msg end end
check(announce and announce:find("^C2|A|1429|4000|6000|%d+|2l|1|0||Me~h|$"), "in Warmth's format: " .. tostring(announce))
local decoded = GM:DecodeCamp(announce)
check(decoded and decoded.mapID == 1429 and decoded.tier == 2 and near(decoded.x, 0.4) and near(decoded.y, 0.6),
  "which this client reads back")
local realmLine
for _, m in ipairs(meshSent) do if m.bus == "REALM" then realmLine = m.msg end end
check(realmLine and realmLine:find("^C2|S|1429|4000|6000|%d+|2l$") and not realmLine:find("Me", 1, true),
  "the realm gets an ownerless sighting: " .. tostring(realmLine))
check(GM:DecodeCamp(realmLine) == nil, "which the guild map does not draw")
p0 = #printed
cast(1279961)
advance(2)
check(not saidSince(p0, NOTICE), "the notice never comes twice")

-- ── 3. /gos campfire, and Warmth ────────────────────────────────────────
local x0 = campsSent("X")
p0 = #printed
slash("campfire off")
check(store.consent == false and CN:CampState() == "off", "/gos campfire off keeps a no")
check(campsSent("X") == x0 + 1, "and ends the camp running")
check(saidSince(p0, "Campfire announce: off."), "and says so")
local s0 = campsSent()
cast(1279981); advance(30)
check(campsSent() == s0, "off: a fire lit sends nothing")
slash("campfire on")
check(store.consent == true and CN:CampState() == "on", "/gos campfire on")
slash("campfire realm off")
check(store.realm == false and not CN:CampRealmOn(), "/gos campfire realm off")
local r0 = 0
for _, m in ipairs(meshSent) do if m.bus == "REALM" then r0 = r0 + 1 end end
cast(1279974); advance(2)
local r1 = 0
for _, m in ipairs(meshSent) do if m.bus == "REALM" then r1 = r1 + 1 end end
check(r1 == r0 and campsSent("A") > 1, "realm off: guild still hears it, the realm does not")
p0 = #printed
slash("Campfire Realm On")
check(store.realm == true and CN:CampRealmOn(), "/gos campfire realm on, in any case")
check(saidSince(p0, "Whole realm, without your name: on."), "and says so")
p0 = #printed
slash("campfire status")
check(saidSince(p0, "Campfire announce: on (guild and group).") and saidSince(p0, "Whole realm, without your name: on."),
  "/gos campfire status")
p0 = #printed
slash("campfire maybe")
check(saidSince(p0, "Usage: /gos campfire"), "an unknown word prints the usage")
GuildOS.Client.isAnniversary = true
p0 = #printed
slash("campfire off")
check(saidSince(p0, "Not available on this client.") and store.consent == true, "off Forever the command does nothing")
GuildOS.Client.isAnniversary = false
local before = campsSent()
warmth = true
cast(1279974)
advance(10)
check(campsSent() == before, "with Warmth loaded nothing is announced")
slash("campfire status")
check(printed[#printed]:find("Warmth is loaded", 1, true), "and the status says Warmth announces itself")
warmth = false

-- ── 4. A camp line, decoded (Warmth's real format) ──────────────────────
local BEACON = "C2|A|1429|4000|6000|0|1l|1|0||Chehul Costa~h|"
local WARMTH = "C2|A|1429|4523|7001|90017|3v|4|75|1,2,5|Ann~f;Bob Rocha~b;Cid~j|bring wood, all welcome"
local c = GM:DecodeCamp(BEACON)
check(c and c.mapID == 1429 and near(c.x, 0.4) and near(c.y, 0.6) and c.tier == 1 and c.age == 0 and c.family,
  "the beacon's announce")
c = GM:DecodeCamp(WARMTH)
check(c and c.tier == 3 and near(c.x, 0.4523) and c.age == 75 * 60 and not c.family,
  "Warmth's own, with objects, several people and a note (age in minutes)")
check(GM:DecodeCamp("C2|A|1429|5000|5000|0|2lqz|1|5||A~c|").tier == 2, "unknown flag letters are skipped")
check(GM:DecodeCamp("C2|X").ended, "the end")
local good = "C2|A|1429|4523|7001|9001|3l|1|1||Ann~f|"
local bad = {
  "", "C2", "C2|A", "C2|X|1", "C2|J|Ann|f|0", "C2|I|Ann", "C2|T|Ann", "C2|E|1,2|3",
  "C2|S|1429|5000|5000|0|1l", "C2|V|123|1429|5000|5000|4,5|Bob",
  "C1|A|1429|5000|5000|0|1|1|5||A~c|",
  "C2|A|0|5000|5000|0|1|1|5||A~c|", "C2|A|-5|5000|5000|0|1|1|5||A~c|", "C2|A|100000|5000|5000|0|1|1|5||A~c|",
  "C2|A|1429|10001|5000|0|1|1|5||A~c|", "C2|A|1429|0.5|0.5|0|1|1|5||A~c|", "C2|A|1429|nan|5000|0|1|1|5||A~c|",
  "C2|A|1429|0|0|0|1|1|5||A~c|", "C2|A|1429|5000|5000|x|1|1|5||A~c|", "C2|A|1429|5000|5000|0|4|1|5||A~c|",
  "C2|A|1429|5000|5000|0|0|1|5||A~c|", "C2|A|1429|5000|5000|0|l|1|5||A~c|", "C2|A|1429|5000|5000|0|1L|1|5||A~c|",
  "C2|A|1429|5000|5000|0|1abcde|1|5||A~c|", "C2|A|1429|5000|5000|0|1|41|5||A~c|",
  "C2|A|1429|5000|5000|0|1|1|-5||A~c|", "C2|A|1429|5000|5000|0|1|1|1441||A~c|",
  "C2|A|1429|5000|5000|0|1|1|5|1,2,3,4|A~c|", "C2|A|1429|5000|5000|0|1|1|5|x|A~c|",
  "C2|A|1429|5000|5000|0|1|1|5||A|", "C2|A|1429|5000|5000|0|1|1|5||A~C|", "C2|A|1429|5000|5000|0|1|1|5||~c|",
  "C2|A|1429|5000|5000|0|1|1|5||" .. string.rep("a", 41) .. "~c|",
  "C2|A|1429|5000|5000|0|1|1|5||a~b;b~b;c~b;d~b;e~b;f~b;g~b;h~b;i~b;j~b|",
  "C2|A|1429|5000|5000|0|1|1|5||A~c|" .. string.rep("x", 260),
  "C2|A|1429|5000|5000|0|1|1|5||A\n~c|", "C2|A|1429\n|5000|5000|0|1|1|5||A~c|", "C2|A|1429|5000|5000|0|1|1|5||A~c", "C2|A|1429|5000|5000|0|1|1|5",
}
for _, b in ipairs(bad) do check(GM:DecodeCamp(b) == nil, "refused: " .. b:sub(1, 60)) end
check(GM:DecodeCamp(nil) == nil and GM:DecodeCamp(42) == nil, "not a string")

-- Warmth's own decoder agrees, when a checkout of it is at hand.
local WARMTH_DIR = os.getenv("WARMTH") or (ADDON .. "/../warmth")
local wf = io.open(WARMTH_DIR .. "/Core/Wire.lua")
if wf then
  wf:close()
  local W = {}
  assert(loadfile(WARMTH_DIR .. "/Core/Data.lua"))("Warmth", W)
  assert(loadfile(WARMTH_DIR .. "/Core/Wire.lua"))("Warmth", W)
  local function agree(line)
    local mine, theirs = GM:DecodeCamp(line), W.Wire.Decode(line)
    if theirs and theirs.kind == "X" then return mine ~= nil and mine.ended == true end
    if not theirs or theirs.kind ~= "A" then return mine == nil end
    return mine ~= nil and mine.mapID == theirs.map and near(mine.x, theirs.x) and near(mine.y, theirs.y)
      and mine.tier == theirs.tier and mine.age == theirs.age * 60 and (mine.family == (theirs.family == true))
  end
  for _, line in ipairs({ BEACON, WARMTH, good, announce, "C2|X", "C2|A|1429|5000|5000|0|2lqz|1|5||A~c|",
                         "C2|A|1429|5000|5000|0|1|1|5||A~c|a note\nwith a break" }) do
    check(W.Wire.Decode(line), "Warmth reads it too: " .. line:sub(1, 50))
    check(agree(line), "and both read the same: " .. line:sub(1, 50))
  end
  for _, b in ipairs(bad) do
    if not b:find("^C2|A|1429|0|0|") then check(agree(b), "both refuse, or Warmth's is not an announce: " .. string.format("%q", b:sub(1, 70))) end
  end
  check(W.Wire.Decode(W.Wire.Announce({ map = 1436, x = 0.35, y = 0.8, zuid = 0, tier = 2, n = 2, age = 3,
    objs = { 1 }, people = { { name = "Bob", class = 1 } }, note = "hi" })), "(Warmth's own builder)")
  local built = W.Wire.Announce({ map = 1436, x = 0.35, y = 0.8, zuid = 0, tier = 2, n = 2, age = 3,
    objs = { 1 }, people = { { name = "Bob", class = 1 } }, note = "hi" })
  check(agree(built), "a line Warmth builds is read here as Warmth reads it: " .. tostring(built))
else
  print("guild-camps: no Warmth checkout at " .. WARMTH_DIR .. "; Wire.Decode cross-checks skipped")
end

-- ── 5. What arrives: GUILD only, a guildmate on the roster only ─────────
check(registeredPrefixes.ChehulCamp, "the prefix is registered")
local Ace = LibStub("AceComm-3.0")
local function hear(text, channel, sender)
  Ace.frame.scripts.OnEvent(Ace.frame, "CHAT_MSG_ADDON", "ChehulCamp", text, channel, sender)
end
GM.camps = {}
local refreshed = 0
GM.uiRefresh = function() refreshed = refreshed + 1 end
hear(good, "GUILD", "Ann-Realm")
check(GM.camps["Ann-Realm"] and GM.camps["Ann-Realm"].tier == 3, "a guildmate's camp over GUILD, through AceComm")
check(refreshed > 0, "and the map redraws")
check(near(GM.camps["Ann-Realm"].lit, clock - 60), "lit when its age (in minutes) says")
for _, ch in ipairs({ "PARTY", "RAID", "WHISPER", "CHANNEL", "YELL", "SAY" }) do
  hear("C2|A|1436|5000|5000|0|1|1|5||Bob~c|", ch, "Bob-Realm")
end
check(GM.camps["Bob-Realm"] == nil, "nothing that did not come over GUILD")
hear("C2|A|1436|5000|5000|0|1|1|5||Zed~c|", "GUILD", "Zed-Realm")
check(GM.camps["Zed-Realm"] == nil, "nobody off the guild's roster")
hear("C2|A|1436|5000|5000|0|1|1|5||Me~c|", "GUILD", "Me-Realm")
check(GM.camps["Me-Realm"] == nil, "not this client's own fire")
hear("C2|A|7777|5000|5000|0|1|1|5||Bob~c|", "GUILD", "Bob-Realm")
check(GM.camps["Bob-Realm"] == nil, "not on a map this client does not know")
hear("garbage", "GUILD", "Bob-Realm")
check(GM.camps["Bob-Realm"] == nil, "nor a malformed line")
hear("C2|S|1436|3500|8000|0|1l", "GUILD", "Bob-Realm")
check(GM.camps["Bob-Realm"] == nil, "nor a sighting (S): the guild map draws named camps only")
hear("C2|A|1436|3500|8000|0|1|1|5||Bob~c|", "GUILD", "Bob-Realm")
check(GM.camps["Bob-Realm"] and GM.camps["Bob-Realm"].mapID == 1436, "Bob's camp in Westfall")
hear("C2|A|1436|3600|8000|0|1|1|5||Bob~c|", "GUILD", "Bob-Realm")
check(near(GM.camps["Bob-Realm"].x, 0.35), "a second line within CAMP_GAP is dropped")

-- ── 6. The end, the quiet, the burn-out ─────────────────────────────────
hear("C2|X", "PARTY", "Bob-Realm")
check(GM.camps["Bob-Realm"], "an end over another channel ends nothing")
hear("C2|X", "GUILD", "Bob-Realm")
check(GM.camps["Bob-Realm"] == nil, "C2|X over GUILD ends it")
check(GM.camps["Ann-Realm"], "and only the sender's")
advance(GM.CAMP_QUIET - 1); GM:Tick()
check(GM.camps["Ann-Realm"], "a camp stays CAMP_QUIET without a beat")
advance(2); GM:Tick()
check(GM.camps["Ann-Realm"] == nil, "and goes after it")
hear("C2|A|1429|4500|7500|0|1l|1|50||Ann~c|", "GUILD", "Ann-Realm")
for i = 1, 4 do
  advance(240)
  if 3000 + 240 * i < GM.CAMP_LIFE then
    hear("C2|A|1429|4500|7500|0|1l|1|" .. math.floor((3000 + 240 * i) / 60) .. "||Ann~c|", "GUILD", "Ann-Realm")
    check(GM.camps["Ann-Realm"], "a beat keeps it (" .. i .. ")")
  end
  GM:Tick()
end
check(GM.camps["Ann-Realm"] == nil, "a beacon's camp burns out CAMP_LIFE after it was lit, beats or not")
hear("C2|A|1429|4500|7500|0|1|1|70||Ann~c|", "GUILD", "Ann-Realm")
check(GM.camps["Ann-Realm"], "Warmth's own camp may be older (it lasts while it beats)")
advance(GM.CAMP_GAP); hear("C2|X", "GUILD", "Ann-Realm")
hear("C2|A|1429|4500|7500|0|1l|1|0||Ann~c|", "GUILD", "Ann-Realm")
check(GM.camps["Ann-Realm"], "a new fire")
GM.CAMP_MAX = 1
hear("C2|A|1436|3500|8000|0|1|1|5||Bob~c|", "GUILD", "Bob-Realm")
check(GM.camps["Bob-Realm"] == nil, "no more than CAMP_MAX camps kept")
GM.CAMP_MAX = 60

-- ── 7. The flame on the map, its tooltip, the waypoint ──────────────────
GuildOS:SetupGuildMapPresence()
GuildOS:ToggleGuildMap()
check(WorldMapFrame:IsShown(), "the map opens")
local layer
for _, f in ipairs(frames) do if f.parent == canvas and f.scripts.OnUpdate then layer = f end end
check(layer, "our layer sits on the canvas")
layer:SetSize(1000, 800)   -- (SetAllPoints on the canvas, in the game)
layer.scripts.OnUpdate(layer, 1)
local flame
for _, f in ipairs(frames) do
  if f.parent == layer and f.camp then flame = f end
end
check(flame and flame:IsShown() and flame.camp.key == "Ann-Realm", "a flame for Ann's camp")
check(flame.icon.texture == "Interface\\Icons\\Spell_Fire_Fire", "a game flame icon")
local pt = flame.points[#flame.points]
check(pt and near(pt[4], 0.45 * 1000) and near(pt[5], -0.75 * 800), "at the camp's spot on the shown map")
flame.scripts.OnEnter(flame)
check(GameTooltip.lines[1] == "Ann lit a campfire in Elwynn Forest · Basic level", "tooltip: " .. tostring(GameTooltip.lines[1]))
flame.scripts.OnClick(flame)
check(waypoint and waypoint.uiMapID == 1429 and near(waypoint.position.x, 0.45) and near(waypoint.position.y, 0.75)
  and superTracked == true, "a click sets the game's waypoint there, followed")
local list
for _, f in ipairs(frames) do if f.foot and f.head and f.rows then list = f end end
check(list and list.foot.text:find("Install Warmth to see the circle and build your own", 1, true),
  "the list's foot points to Warmth")
-- Journeyman and Expert read in the tooltip too.
hear("C2|A|1429|4200|7200|0|3|1|10||x~c|", "GUILD", "Bob-Realm")
local cs = GM:GetCamps()
check(#cs == 2 and GM:CampText(cs[2]) == "Bob lit a campfire in Elwynn Forest · Expert level",
  "an Expert kit; the name from the roster, never the payload")

-- ── 8. Off with Warmth, off Forever ─────────────────────────────────────
warmth = true
layer.scripts.OnUpdate(layer, 1)
check(not flame:IsShown(), "with Warmth loaded the flames go (Warmth draws them)")
check(not list.foot.text:find("Install Warmth", 1, true), "and the foot says nothing of it")
hear("C2|A|1436|3500|8000|0|1|1|5||Bob~c|", "GUILD", "Bob-Realm")
check(#GM:GetCamps() == 0, "nothing is listed for the layer")
warmth = false
layer.scripts.OnUpdate(layer, 1)
check(flame:IsShown(), "back without Warmth")
for _, which in ipairs({ "isAnniversary", "isRetail" }) do
  GuildOS.Client[which] = true
  layer.scripts.OnUpdate(layer, 1)
  check(not flame:IsShown() and #GM:GetCamps() == 0 and not GM:CampsOn(), "off when " .. which)
  GuildOS.Client[which] = false
end
-- A client off Forever never listens.
local GM2 = setmetatable({ _campComm = false }, { __index = GM })
GuildOS.Client.isAnniversary = true
GM._ListenCamps(GM2)
check(rawget(GM2, "_campComm") == false, "off Forever the prefix is not listened to")
GuildOS.Client.isAnniversary = false
GM._ListenCamps(GM2)
check(type(rawget(GM2, "_campComm")) == "table", "(and on Forever it is)")

-- ── 9. The member window's addon labels ─────────────────────────────────
check(GuildOS.Mesh.ADDON_LABELS.cf == "Warmth" and GuildOS.Mesh.ADDON_LABELS.ls == "Lodestar", "cf and ls labelled")
CN.peers = CN.peers or {}
CN.peers["Ann"] = { addons = { gos = true, cf = true, ls = true } }
local suffix = GuildOS.Mesh:PresenceSuffix("Ann-Realm")
check(suffix:find("Lodestar, Warmth", 1, true), "the member window says Ann runs Lodestar and Warmth: " .. suffix)

local mapChecks = checks

-- ── 10. The settings toggle, on the real Settings page (Forever) ────────
-- The Settings harness's frames and client, read from tools/settings-panel.lua up to its first test, on Forever.
local src = assert(io.open(ADDON .. "/tools/settings-panel.lua")):read("*a")
local cut = src:find("-- ── 1. Six pages", 1, true)
check(cut, "the Settings harness has its first test where expected")
src = src:sub(1, cut - 1)
local anniversarySrc = src
local n
src, n = src:gsub('function GetBuildInfo%(%) return "2%.5%.6", "60000", "", 20506 end\nWOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5',
  'function GetBuildInfo() return "1.60.1", "70888", "", 16001 end\nWOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = nil, 1')
check(n == 1, "the harness's client line is found (Forever swapped in)")
local consentCalls, realmCalls = {}, {}
local state, realmOn, pvp = "default", true, false
_G.ChehulNet = {
  SetCampConsent = function(_, yes) consentCalls[#consentCalls + 1] = yes; state = yes and "on" or "off" end,
  CampState = function() return state end,
  SetCampRealm = function(_, yes) realmCalls[#realmCalls + 1] = yes; realmOn = yes end,
  CampRealmOn = function() return realmOn end,
  IsPvPRealm = function() return pvp end,
}
local harness = assert(loadstring(src, "settings-panel harness"))
-- The harness's own locals (check, walk, find) are out of reach: the page is walked here.
harness()
local function walk(f, visit) visit(f); for _, ch in ipairs(f.children or {}) do walk(ch, visit) end end
local function findCheck(root, label)
  local hit
  walk(root, function(f)
    if not hit and f:IsVisible() and f.checkbox and f.label and f.label.text == label then hit = f end
  end)
  return hit
end
local function shows(root, text)
  local seen = false
  walk(root, function(f) if f.kind == "FontString" and f:IsVisible() and f.text == text then seen = true end end)
  return seen
end
check(GuildOS.Client.game == "FOREVER", "the Settings harness runs as WoW: Forever")
local parent = CreateFrame("Frame", nil, UIParent)
parent:SetSize(960, 560)
GuildOS:CreateSettingsPanel(parent)
parent.SelectSub("profile")
local box = findCheck(parent, "Announce my campfires")
check(box, "Settings › Profile › Privacy has the campfire toggle on Forever")
check(box.checkbox:GetChecked(), "ticked while nobody chose (on by default)")
local realmBox = findCheck(parent, "Also to the whole realm, without my name")
check(realmBox and realmBox.checkbox:GetChecked(), "and the realm toggle under it, ticked where the realm allows it")
check(shows(parent, "Off by default on PvP realms."), "its hint: off by default on PvP realms")
box.checkbox.onChanged(box.checkbox, false)
check(consentCalls[1] == false and not box.checkbox:GetChecked(), "unticking it calls SetCampConsent(false)")
check(not realmBox.checkbox:IsEnabled(), "and greys the realm toggle out")
box.checkbox.onChanged(box.checkbox, true)
check(consentCalls[2] == true and box.checkbox:GetChecked() and realmBox.checkbox:IsEnabled(),
  "ticking it calls SetCampConsent(true)")
realmBox.checkbox.onChanged(realmBox.checkbox, false)
check(realmCalls[1] == false and not realmBox.checkbox:GetChecked(), "the realm toggle calls SetCampRealm(false)")
realmBox.checkbox.onChanged(realmBox.checkbox, true)
check(realmCalls[2] == true and realmBox.checkbox:GetChecked(), "and SetCampRealm(true)")
-- On a PvP realm the hint says this realm is one.
pvp, realmOn = true, false
assert(loadstring(src, "settings-panel harness (PvP)"))()
parent = CreateFrame("Frame", nil, UIParent)
parent:SetSize(960, 560)
GuildOS:CreateSettingsPanel(parent)
parent.SelectSub("profile")
realmBox = findCheck(parent, "Also to the whole realm, without my name")
check(realmBox and not realmBox.checkbox:GetChecked(), "a PvP realm: the realm toggle unticked by default")
check(shows(parent, "Off by default on PvP realms, like this one."), "and its hint says this realm is one")

-- The harness's own client (TBC Anniversary): no toggle.
assert(loadstring(anniversarySrc, "settings-panel harness (Anniversary)"))()
check(GuildOS.Client.isAnniversary, "the Settings harness runs as TBC Anniversary")
parent = CreateFrame("Frame", nil, UIParent)
parent:SetSize(960, 560)
GuildOS:CreateSettingsPanel(parent)
parent.SelectSub("profile")
check(findCheck(parent, "Show login digest"), "(the Profile page is built)")
check(findCheck(parent, "Announce my campfires") == nil and findCheck(parent, "Also to the whole realm, without my name") == nil,
  "and no campfire toggles off Forever")

print(string.format("guild-camps: %d checks passed (%d map and beacon, %d settings)", checks, mapChecks, checks - mapChecks))
