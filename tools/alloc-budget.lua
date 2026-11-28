-- Garbage per minute stays under a budget (memory audit, third pass: specs/salao/memoria.md). The maintainer
-- measured 166.7 MB of Guild OS memory in game on WoW: Forever (a guild of 180), 36 MB after a full collection:
-- about 130 MB was garbage the addon made faster than the client's incremental collector cleaned it, and the
-- client's addon counter includes it. This runs the whole addon (every file the TOC loads) under a stubbed
-- WoW: Forever client with a real clock: frames' OnUpdate at 60 frames a second, C_Timer timers and tickers,
-- the events a guild of 180 (35 online) makes, the chat filters on every line for two chat frames, the tooltip
-- hooks while hovering, the server's guild chat history (C_Club, a new table per answer as the client's), and
-- every addon message this client sends played back as the same traffic from the other Guild OS users online.
-- Then:
--   * idle (in a city, the window closed): garbage per minute under IDLE_BUDGET_KB, twice;
--   * the same with the window open on the Members tab: under MEMBERS_BUDGET_KB;
--   * active (a raid of 20, combat, auras, tooltips, a busy trade channel and guild chat, Chat Tweaks on, the
--     window open on the Hall): under ACTIVE_BUDGET_KB;
--   * the memory left after a full collection does not grow from one idle stretch to the next;
--   * what the hot paths now refill (the roster's entries, the marks' scan, the card's index, the inactive list,
--     the countdown's levels, the map's roster) answers as a fresh one did, and a raid's roster storm makes at
--     most one snapshot every RaidTracker.ROSTER_SNAP_GAP.
-- The budgets are KB a simulated minute. Before the third pass this run measured about 370-510 idle, 4,100 on the
-- Members tab and 20,200 active under LuaJIT (600 / 5,900 / 27,100 under Lua 5.1); after it about 40-120,
-- 350-600 and 1,450-1,850. They leave room over that, and are documented in memoria.md.
--
--   luajit -e 'ADDON="."' tools/alloc-budget.lua
--   ALLOC_PROFILE=1 lua5.1 -e 'ADDON="."' tools/alloc-budget.lua    (per function and per trigger, KB a minute)
--   ALLOC_MINUTES=n: minutes a stretch (default 3)
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local IDLE_BUDGET_KB = 600
local MEMBERS_BUDGET_KB = 1500
local ACTIVE_BUDGET_KB = 4000
local RETAINED_GROWTH_KB = 256
local PROFILE = os.getenv("ALLOC_PROFILE") == "1"
local MINUTES = tonumber(os.getenv("ALLOC_MINUTES") or "") or 3
local FPS = 60

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

-- ── Clock and timers ─────────────────────────────────────────────────────
local START = 1794500000
local clock = 1000            -- GetTime
local serverOffset = START - clock
function GetTime() return clock end
function GetServerTime() return math.floor(clock + serverOffset) end
local osTime = os.time
function time(t) if t then return osTime(t) end return math.floor(clock + serverOffset) end
function debugprofilestop() return os.clock() * 1000 end

local timers = {}             -- { at, fn, every, left, obj }
local function schedule(d, fn, every, left, obj)
  local t = { at = clock + (tonumber(d) or 0), fn = fn, every = every, left = left, obj = obj }
  timers[#timers + 1] = t
  return t
end
local tickerMT = { __index = {
  Cancel = function(self) self._cancelled = true end,
  IsCancelled = function(self) return self._cancelled == true end,
} }
C_Timer = {
  After = function(d, fn) schedule(d, fn) end,
  NewTicker = function(d, fn, n)
    local o = setmetatable({}, tickerMT)
    schedule(d, fn, math.max(tonumber(d) or 0, 0.01), n, o)
    return o
  end,
  NewTimer = function(d, fn)
    local o = setmetatable({}, tickerMT)
    schedule(d, fn, nil, nil, o)
    return o
  end,
}

-- ── Measurement ──────────────────────────────────────────────────────────
-- With the collector stopped, every dispatch below adds what it allocated to its trigger's row; between
-- dispatches the harness may collect, which counts nowhere.
local TRIG = {}               -- [label] = KB
TRIGN = {}                    -- [label] = dispatches
local measuring = ALLOC_MEASURE_LOGIN == true   -- tools/inbox-perf.lua times the login burst too
local gcount = collectgarbage
local function where(fn)
  local i = debug.getinfo(fn, "S")
  return (i.short_src:gsub("^.*guildos/", ""):gsub("^%./", "")) .. ":" .. (i.linedefined or 0)
end
local whereCache = setmetatable({}, { __mode = "k" })
local function label(kind, fn)
  local w = whereCache[fn]
  if not w then w = where(fn); whereCache[fn] = w end
  return kind .. " " .. w
end
local ERRS = {}
local depth = 0               -- a dispatch inside a dispatch (a Show from a handler) is its outer one's
CURRENT = nil                 -- the outermost trigger running (the profiler's hook reads it)
local function run(kind, fn, ...)
  if not measuring or depth > 0 then
    local ok, e = pcall(fn, ...)
    if not ok then ERRS[#ERRS + 1] = kind .. ": " .. tostring(e) end
    return ok, e
  end
  local key = (PROFILE or ALLOC_LABEL) and label(kind, fn) or kind
  depth, CURRENT = 1, key
  local a = gcount("count")
  local t0 = ALLOC_TIME and os.clock()
  local ok, e = pcall(fn, ...)
  local d = gcount("count") - a
  depth, CURRENT = 0, nil
  if not ok then ERRS[#ERRS + 1] = kind .. ": " .. tostring(e) end
  if t0 then
    -- tools/inbox-perf.lua: CPU time per trigger, and its longest single dispatch (a frame's spike)
    local dt, row = os.clock() - t0, ALLOC_TIME[key]
    if not row then row = { n = 0, total = 0, max = 0 }; ALLOC_TIME[key] = row end
    row.n, row.total = row.n + 1, row.total + dt
    if dt > row.max then row.max = dt end
  end
  TRIG[key] = (TRIG[key] or 0) + d
  TRIGN[key] = (TRIGN[key] or 0) + 1
  return ok, e
end

-- ── Frames ───────────────────────────────────────────────────────────────
local FRAMES = {}
local EVENTS = {}             -- [event] = { [frame] = units or true }
local numbers = { GetWidth = 100, GetHeight = 20, GetEffectiveScale = 1, GetScale = 1, GetStringWidth = 50,
  GetStringHeight = 12, GetNumLines = 1, GetLeft = 0, GetRight = 100, GetTop = 100, GetBottom = 0,
  GetFrameLevel = 1, GetAlpha = 1, GetNumPoints = 0, GetVerticalScroll = 0, GetVerticalScrollRange = 0,
  GetValue = 0, GetID = 0, GetLineHeight = 12, GetNumChildren = 0, GetUnboundedStringWidth = 50 }
local SUBOBJ = { ScrollBar = true, ScrollUpButton = true, ScrollDownButton = true, ThumbTexture = true, Text = true }
local METHOD1 = { Show = true, Hide = true, Enable = true, Disable = true, Click = true, Raise = true, Lower = true,
  Lock = true }
local M = {}                  -- shared methods: no closure per access
local frameMT
local function adopt(parent, o)
  if type(parent) == "table" and rawget(parent, "__scripts") then
    local kids = rawget(parent, "__kids")
    if not kids then kids = {}; rawset(parent, "__kids", kids) end
    kids[#kids + 1] = o
  end
end
local function newObj(kind, name, parent)
  local o = setmetatable({ __kind = kind, __scripts = {}, __shown = true, __parent = parent }, frameMT)
  FRAMES[#FRAMES + 1] = o
  adopt(parent, o)
  if type(name) == "string" then _G[name] = o end
  return o
end
local function noop() end
for k, v in pairs(numbers) do M[k] = function() return v end end
-- Sizes are kept (the window picks its layout band from its width).
local function resized(self, w, h)
  if w == self.__w and h == self.__h then return end
  self.__w, self.__h = w, h
  local s = self.__scripts.OnSizeChanged
  if s then run("OnSizeChanged", s, self, w or 100, h or 20) end
end
function M.SetWidth(self, w) resized(self, w, self.__h) end
function M.SetHeight(self, h) resized(self, self.__w, h) end
function M.SetSize(self, w, h) resized(self, w, h) end
function M.GetWidth(self) return self.__w or 100 end
function M.GetHeight(self) return self.__h or 20 end
function M.GetSize(self) return self.__w or 100, self.__h or 20 end
function M.GetMinMaxValues() return 0, 0 end
function M.GetCursorPosition() return 0, 0 end
function M.SetScript(self, s, f) self.__scripts[s] = f end
function M.GetScript(self, s) return self.__scripts[s] end
function M.HookScript(self, s, f)
  local old = self.__scripts[s]
  if old then self.__scripts[s] = function(...) old(...); return f(...) end else self.__scripts[s] = f end
end
function M.HasScript(_, s) return not (type(s) == "string" and s:find("^OnTooltipSet")) end   -- Forever: the retail tooltip
function M.RegisterEvent(self, e) EVENTS[e] = EVENTS[e] or {}; EVENTS[e][self] = true end
function M.RegisterUnitEvent(self, e, u1, u2)
  EVENTS[e] = EVENTS[e] or {}
  EVENTS[e][self] = (u1 or u2) and { [u1 or ""] = true, [u2 or ""] = true } or true
end
function M.UnregisterEvent(self, e) if EVENTS[e] then EVENTS[e][self] = nil end end
function M.UnregisterAllEvents(self) for _, set in pairs(EVENTS) do set[self] = nil end end
function M.IsEventRegistered(self, e) return EVENTS[e] and EVENTS[e][self] and true or false end
local function child(self) return newObj("child", nil, self) end
M.CreateTexture, M.CreateFontString, M.CreateLine, M.CreateMaskTexture = child, child, child, child
M.CreateAnimationGroup, M.CreateAnimation = child, child
function M.GetFont() return STANDARD_TEXT_FONT, 12, "" end
function M.GetText(self) return self.__text end
function M.SetText(self, s) self.__text = s end
function M.IsShown(self) return self.__shown end
function M.IsVisible(self)
  local f = self
  while f do
    if not f.__shown then return false end
    f = f.__parent
  end
  return true
end
-- Shown under a visible parent, a frame and every shown frame under it get OnShow; hidden, OnHide (the client's way).
local function cascade(f, script)
  local s = f.__scripts[script]
  if s then run(script, s, f) end
  local kids = rawget(f, "__kids")
  if kids then for i = 1, #kids do if kids[i].__shown and kids[i].__parent == f then cascade(kids[i], script) end end end
end
function M.Show(self)
  if self.__shown then return end
  self.__shown = true
  if M.IsVisible(self) then cascade(self, "OnShow") end
end
function M.Hide(self)
  if not self.__shown then return end
  local was = M.IsVisible(self)
  self.__shown = false
  if was then cascade(self, "OnHide") end
end
function M.SetShown(self, v) if v then M.Show(self) else M.Hide(self) end end
function M.SetParent(self, p) self.__parent = p; adopt(p, self) end
function M.GetParent(self) return self.__parent end
function M.GetObjectType(self) return self.__kind end
function M.GetName(self) return self.__name end
function M.IsForbidden() return false end
function M.IsObjectType(self, k) return self.__kind == k end
function M.GetRegions() return nil end
function M.GetChildren() return nil end
function M.GetPoint() return nil end
local function sub(self) self.__sub = self.__sub or child(self); return self.__sub end
M.GetFontString, M.GetNormalTexture, M.GetHighlightTexture, M.GetPushedTexture = sub, sub, sub, sub
M.GetScrollChild, M.GetStatusBarTexture, M.GetThumbTexture = sub, sub, sub
-- Tooltips: what is being hovered.
local HOVER = { item = nil, unit = nil }
function M.GetItem() local it = HOVER.item; if it then return it.name, it.link, it.id end end
function M.GetUnit() local u = HOVER.unit; if u then return u.name, "mouseover", u.guid end end
function M.GetSpell() return nil end
function M.NumLines() return 4 end
frameMT = {
  __index = function(t, k)
    if type(k) ~= "string" then return nil end
    local m = M[k]
    if m then return m end
    if SUBOBJ[k] then local o = child(t); rawset(t, k, o); return o end
    if not k:match("^[A-Z][a-z]+[A-Z]") and not METHOD1[k] then return nil end   -- capitalized word: a field
    M[k] = noop
    return noop
  end,
}
function CreateFrame(kind, name, parent)
  local f = newObj(kind or "Frame", name, parent)
  f.__name = name
  return f
end
UIParent = newObj("Frame", "UIParent")
UIParent.__w, UIParent.__h = 1600, 900
WorldFrame = newObj("Frame", "WorldFrame")
Minimap = newObj("Frame", "Minimap", UIParent)
GameTooltip = newObj("GameTooltip", "GameTooltip", UIParent)
ItemRefTooltip = newObj("GameTooltip", "ItemRefTooltip", UIParent)
ShoppingTooltip1 = newObj("GameTooltip", "ShoppingTooltip1", UIParent)
ShoppingTooltip2 = newObj("GameTooltip", "ShoppingTooltip2", UIParent)
DEFAULT_CHAT_FRAME = newObj("Frame", "ChatFrame1", UIParent)
DEFAULT_CHAT_FRAME.AddMessage = noop
for i = 2, 10 do newObj("Frame", "ChatFrame" .. i, UIParent).AddMessage = noop end
GameFontNormal = newObj("Font"); GameFontHighlight = newObj("Font"); GameFontNormalSmall = newObj("Font")
GameFontHighlightSmall = newObj("Font"); GameFontDisable = newObj("Font"); QuestTitleFont = newObj("Font")
function CreateFont() return newObj("Font") end
function GetMouseFocus() return nil end
function Ambiguate(name) return type(name) == "string" and (name:gsub("%-.*$", "")) or name end
function GetFramerate() return FPS end
function GetNetStats() return 0, 0, 50, 50 end
function GetCursorPosition() return 0, 0 end

local fireBufs, fireDepth = {}, 0   -- one list a nesting level, reused: the harness makes no garbage here
local function FIRE(event, ...)
  local set = EVENTS[event]
  if not set then return end
  local unit = ...
  fireDepth = fireDepth + 1
  local list = fireBufs[fireDepth]
  if not list then list = {}; fireBufs[fireDepth] = list end
  local n = 0
  for f, units in pairs(set) do
    if units == true or (type(unit) == "string" and units[unit]) then n = n + 1; list[n] = f end
  end
  for i = 1, n do
    local f = list[i]
    list[i] = nil
    local h = f.__scripts.OnEvent
    if h then run(event, h, f, event, ...) end
  end
  fireDepth = fireDepth - 1
end

-- ── The client: WoW: Forever, an officer of a guild of 180 ───────────────
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", "70009", "Nov 1 2026", 16001 end
function GetRealmName() return "Forever" end
function GetNormalizedRealmName() return "Forever" end
local UNITS = {}              -- unit token -> { name, guid, class }
function UnitName(u)
  if u == "player" then return "Me", nil end
  local x = UNITS[u]; if x then return x.name, nil end
end
function UnitFullName(u) if u == "player" then return "Me", "Forever" end return UnitName(u) end
function UnitGUID(u) if u == "player" then return "Player-1-00000001" end local x = UNITS[u]; return x and x.guid end
function UnitClass(u) local x = UNITS[u]; local c = x and x.class or "WARRIOR"; return c, c, 1 end
function UnitClassBase(u) local x = UNITS[u]; return x and x.class or "WARRIOR", 1 end
function UnitRace() return "Human", "Human", 1 end
function UnitLevel() return 60 end
function UnitSex() return 2 end
function UnitFactionGroup() return "Alliance", "Alliance" end
function UnitExists(u) return u == "player" or UNITS[u] ~= nil end
function UnitIsPlayer(u) return u == "player" or UNITS[u] ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost() return false end
function UnitInRaid(u) return UNITS[u] and UNITS[u].raid or nil end
function UnitInParty(u) return UNITS[u] and UNITS[u].raid and true or false end
function UnitHealth() return 1000 end
function UnitHealthMax() return 1000 end
function UnitPower() return 100 end
function UnitPowerMax() return 100 end
function UnitAffectingCombat() return false end
function UnitGroupRolesAssigned() return "DAMAGER" end
function GetUnitName(u) return (UnitName(u)) end
function IsInGuild() return true end
local GROUP = { raid = false, n = 0 }
function IsInRaid() return GROUP.raid end
function IsInGroup() return GROUP.n > 0 end
function GetNumGroupMembers() return GROUP.n end
function GetRaidRosterInfo(i)
  local u = UNITS["raid" .. i]
  if u then return u.name, i == 1 and 2 or 0, math.floor((i - 1) / 5) + 1, 60, u.class, u.class, "Zone", true, false end
end
function IsInInstance() return GROUP.raid, GROUP.raid and "raid" or "none" end
function GetInstanceInfo() return "Zone", GROUP.raid and "raid" or "none", 0, "", 40, 0, false, GROUP.raid and 409 or 0 end
function InCombatLockdown() return false end
function GetGuildInfo() return "Big Guild", "Officer", 1, nil end
function GetZoneText() return "Stormwind City" end
function GetRealZoneText() return "Stormwind City" end
function GetSubZoneText() return "Trade District" end
function GetMinimapZoneText() return "Trade District" end
function GetNumGuildMembers() return #ROSTER_ROWS, ONLINE_N end
ROSTER_ROWS, ONLINE_N = {}, 0
function GetGuildRosterInfo(i)
  local r = ROSTER_ROWS[i]; if not r then return nil end
  return r.name, r.rank, r.rankIndex, r.level, r.class, r.zone, r.note, r.onote, r.online, 0, r.classFile,
    0, 0, false, false, 0, r.guid
end
function GetGuildRosterLastOnline(i) local r = ROSTER_ROWS[i]; if r and not r.online then return 0, 0, i % 20, 3 end end
function GuildControlGetNumRanks() return 8 end
function GuildControlGetRankName(i) return "Rank" .. i end
function CanEditOfficerNote() return true end
function CanEditPublicNote() return true end
function CanGuildInvite() return true end
function CanGuildRemove() return true end
function CanGuildPromote() return true end
function IsGuildLeader() return false end
function GetChannelName(name)
  if type(name) == "number" then return name, "Channel" .. name end
  return 5, name
end
function GetChannelList() return 1, "General", false, 2, "Trade", false, 5, "ChehulNet", false end
function JoinChannelByName() return 5, "ChehulNet" end
JoinTemporaryChannel = JoinChannelByName
function GetNumDisplayChannels() return 0 end
function IsAddOnLoaded() return false end
function GetAddOnMetadata(_, field) if field == "Version" then return "1.43.5" end end
function GetCVar() return nil end
function GetCVarBool() return false end
function SetCVar() end
function GetScreenWidth() return 1600 end
function GetScreenHeight() return 900 end
function GetPhysicalScreenSize() return 1920, 1080 end
function GetMoney() return 1000000 end
function GetNumSavedInstances() return 0 end
function GetNumFriends() return 0 end
function GetItemInfoInstant(id) return tonumber(id), "Armor", "Plate", "INVTYPE_CHEST", 1, 4, 4 end
function GetInventoryItemLink() return nil end
function GetInventoryItemID() return nil end
function hooksecurefunc() end
function issecurevariable() return true end
function securecall(f, ...) return f(...) end
function geterrorhandler() return function() end end
function seterrorhandler() end
function debugstack() return "" end
function PlaySound() end
function PlaySoundFile() end
function StaticPopup_Show() end
function StaticPopup_Hide() end
function ToggleDropDownMenu() end
function CloseDropDownMenus() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_CreateInfo() return {} end
function GetClassColor() return 1, 1, 1, "ffffffff" end
SlashCmdList = {}
StaticPopupDialogs = {}
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
NUM_CHAT_WINDOWS = 10
Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 } }
local POSTCALLS = {}          -- [dataType] = { fn, ... }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
  POSTCALLS[kind] = POSTCALLS[kind] or {}
  table.insert(POSTCALLS[kind], fn)
end }
local FILTERS = {}            -- [event] = { fn, ... }
function ChatFrame_AddMessageEventFilter(event, fn)
  FILTERS[event] = FILTERS[event] or {}
  table.insert(FILTERS[event], fn)
end
function ChatFrame_RemoveMessageEventFilter(event, fn)
  for i, f in ipairs(FILTERS[event] or {}) do if f == fn then table.remove(FILTERS[event], i) return end end
end
ChatFrameUtil = { AddMessageEventFilter = ChatFrame_AddMessageEventFilter,
  RemoveMessageEventFilter = ChatFrame_RemoveMessageEventFilter,
  ContainsMessageGroup = function() return true end }
-- Every addon message this client sends, to be played back as the other users' traffic.
local OUTBOX = {}
local PREFIXES = {}
local function sendAddon(prefix, msg, channel, target)
  OUTBOX[#OUTBOX + 1] = { prefix, msg, channel, target }
  return true
end
C_ChatInfo = {
  SendAddonMessage = sendAddon, SendAddonMessageLogged = sendAddon,
  RegisterAddonMessagePrefix = function(p) PREFIXES[p] = true; return true end,
  IsAddonMessagePrefixRegistered = function(p) return PREFIXES[p] == true end,
  GetRegisteredAddonMessagePrefixes = function() local o = {} for p in pairs(PREFIXES) do o[#o + 1] = p end return o end,
  InChatMessagingLockdown = function() return false end,
  SendChatMessage = function() end,
}
SendChatMessage = function() end
C_GuildInfo = { GuildRoster = function() end, CanEditOfficerNote = function() return true end,
  CanViewOfficerNote = function() return true end, IsGuildOfficer = function() return true end }
C_AddOns = { GetAddOnMemoryUsage = function() return gcount("count") end, UpdateAddOnMemoryUsage = noop,
  IsAddOnLoaded = function() return false end, GetAddOnMetadata = GetAddOnMetadata }
-- The map: the API answers a new vector each call, as the client's does (it is Lua garbage there too).
local vecMT = { __index = { GetXY = function(v) return v.x, v.y end } }
C_Map = {
  GetBestMapForUnit = function(u) if u == "player" or UNITS[u] then return 1453 end end,
  GetPlayerMapPosition = function(_, u)
    if u ~= "player" and not UNITS[u] then return nil end
    return setmetatable({ x = 0.5 + (clock % 10) / 1000, y = 0.4 }, vecMT)
  end,
  GetMapInfo = function(id) return { mapID = id, name = "Stormwind City", mapType = 3, parentMapID = 1415 } end,
  GetWorldPosFromMapPos = function() return 0, setmetatable({ x = 1, y = 2 }, vecMT) end,
}
-- The guild's channels (Forever runs the retail Communities): the server keeps 200 lines of /g, and every answer
-- is a new table, as the client's are.
CLUB_LINES = 0
Enum.ClubStreamType = { Guild = 1, Officer = 2, Other = 4 }
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetStreams = function() return { { streamId = 1, streamType = 1, name = "Guild" },
    { streamId = 2, streamType = 2, name = "Officer" } } end,
  GetMessageRanges = function() return { { oldestMessageId = { epoch = 1, position = 1 },
    newestMessageId = { epoch = 2e15, position = CLUB_LINES } } } end,
  GetMessagesBefore = function(_, _, _, max)
    local out = {}
    for i = 1, math.min(max or 0, CLUB_LINES, 200) do
      out[i] = { messageId = { epoch = (START + i) * 1e6, position = i }, destroyed = false,
        content = "line " .. i .. " of the guild chat", author = { name = "Member" .. (i % 30 + 2), classID = 1 } }
    end
    return out
  end,
  FocusStream = noop, UnfocusStream = noop, RequestMoreMessagesBefore = noop,
}
C_Container = { GetContainerNumSlots = function() return 16 end, GetContainerItemLink = noop,
  GetContainerItemInfo = noop, GetContainerItemID = noop }
C_Item = { GetItemInfo = noop, GetItemInfoInstant = GetItemInfoInstant, GetItemCount = function() return 0 end,
  GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end, IsItemDataCachedByID = function() return true end,
  RequestLoadItemDataByID = noop }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tinsert(t, ...) return table.insert(t, ...) end
tremove = table.remove
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
-- The client's strsplit is C and makes no table: neither does this one.
function strsplit(d, s, n)
  if n and n <= 1 then return s end
  local i = s:find(d, 1, true)
  if not i then return s end
  return s:sub(1, i - 1), strsplit(d, s:sub(i + #d), n and n - 1)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strjoin(d, ...) return table.concat({ ... }, d) end
strlower, strupper, strsub, strlen, strfind, strmatch, strbyte, strchar, gsub, format, strrep =
  string.lower, string.upper, string.sub, string.len, string.find, string.match, string.byte, string.char,
  string.gsub, string.format, string.rep
gmatch = string.gmatch
floor, ceil, abs, max, min, sqrt, mod = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.fmod
random = math.random
date = os.date
do local ok, b = pcall(require, "bit"); bit = bit or (ok and b) or nil end
-- The game's xpcall passes its extra arguments on (ChatThrottleLib sends through it); plain Lua 5.1's does not.
do
  local raw = xpcall
  local _, n = raw(function(...) return select("#", ...) end, function() end, 1)
  if n ~= 1 then
    xpcall = function(f, h, ...)
      local args, k = { ... }, select("#", ...)
      return raw(function() return f(unpack(args, 1, k)) end, h)
    end
  end
end

-- Any other global: a callable, indexable stub that answers nil (made once per name).
local NIL_GLOBALS = { AceComm = true, Inbox = true, PixelUtil = true, ElvUI = true, Prat = true, Chatter = true }
local stubMT = {}
local function stub() return setmetatable({}, stubMT) end
stubMT.__index = function(t, k) local s = stub(); rawset(t, k, s); return s end
stubMT.__call = function() return nil end
setmetatable(_G, { __index = function(t, k)
  if type(k) ~= "string" or k:match("^[A-Z_0-9]+$") or NIL_GLOBALS[k] or k:match("^GuildOS") or k:match("^Chehul")
    or k:match("^Lib") or k == "ChatThrottleLib" then return nil end
  local s = stub(); rawset(t, k, s); return s
end })

-- ── The guild: 180 members, 35 online ────────────────────────────────────
local CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }
local N, ONLINE = ALLOC_GUILD_N or 180, ALLOC_ONLINE or 35   -- tools/inbox-perf.lua: a guild of 500
for i = 1, N do
  ROSTER_ROWS[i] = { name = i == 1 and "Me" or ("Member" .. i), rank = "Rank" .. (i % 8), rankIndex = i % 8,
    level = 50 + i % 11, class = "Class", classFile = CLASSES[i % 9 + 1], zone = "Zone" .. (i % 40),
    note = "note " .. i, onote = (i % 3 == 0) and ("alt of Member" .. (i - 1)) or "main",
    online = i <= ONLINE, guid = string.format("Player-1-%08d", i) }
end
ONLINE_N = ONLINE
CLUB_LINES = 200

-- ── Load the addon ───────────────────────────────────────────────────────
local function tocFiles()
  local files = {}
  for line in io.lines(ADDON .. "/GuildOS.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  return files
end
for _, f in ipairs(tocFiles()) do
  local chunk, err = loadfile(ADDON .. "/" .. f)
  check(chunk ~= nil, "load " .. f .. ": " .. tostring(err))
  local ok, e = pcall(chunk, "GuildOS", {})
  check(ok, "run " .. f .. ": " .. tostring(e))
end
-- tools/inbox-perf.lua puts the companion's Inbox.lua in place here, as the client loads it with the addon.
if ALLOC_BEFORE_LOGIN then ALLOC_BEFORE_LOGIN() end

-- ── Driving the client ───────────────────────────────────────────────────
local frameDt = 1 / FPS
local function stepFrame()
  clock = clock + frameDt
  -- timers due
  local i = 1
  while i <= #timers do
    local t = timers[i]
    if t.obj and t.obj._cancelled then
      table.remove(timers, i)
    elseif t.at <= clock then
      if t.every and (not t.left or t.left > 1) then
        t.at = clock + t.every
        if t.left then t.left = t.left - 1 end
        i = i + 1
      else
        table.remove(timers, i)
      end
      run("timer", t.fn, t.obj)
    else
      i = i + 1
    end
  end
  -- OnUpdate of every visible frame
  for k = 1, #FRAMES do
    local f = FRAMES[k]
    local s = f.__scripts.OnUpdate
    if s and M.IsVisible(f) then run("OnUpdate", s, f, frameDt) end
  end
end

local function chat(event, ...)
  -- the chat frames that show the line run every filter, then the event reaches the addon's frames
  local list = FILTERS[event]
  if list then
    for c = 1, 2 do
      local cf = _G["ChatFrame" .. c]
      for k = 1, #list do run("chatfilter " .. event, list[k], cf, event, ...) end
    end
  end
  FIRE(event, ...)
end

local function hoverItem(id)
  HOVER.item = { id = id, name = "Item " .. id,
    link = string.format("|cffa335ee|Hitem:%d::::::::60:::::|h[Item %d]|h|r", id, id) }
  for _, fn in ipairs(POSTCALLS[0] or {}) do run("tooltip item", fn, GameTooltip, { type = 0, id = id }) end
end
local function hoverUnit(i)
  local r = ROSTER_ROWS[i]
  UNITS.mouseover = { name = r.name, guid = r.guid, class = r.classFile }
  HOVER.unit = { name = r.name, guid = r.guid }
  FIRE("UPDATE_MOUSEOVER_UNIT")
  for _, fn in ipairs(POSTCALLS[2] or {}) do run("tooltip unit", fn, GameTooltip, { type = 2, guid = r.guid }) end
end

local LINE = 0
local function chatArgs(text, sender, channelName, channelIndex)
  LINE = LINE + 1
  return text, sender, "Common", channelName or "", sender, "", 0, channelIndex or 0, channelName or "", 7, LINE,
    "Player-1-" .. sender
end

-- Played back: each message this client sent, as sent by `copies` other online members, through the frame
-- after it was sent. Whispers were for someone else and are not played back.
local played = 0
local function playBack(copies)
  local box = OUTBOX
  OUTBOX = {}
  for _, m in ipairs(box) do
    if m[3] ~= "WHISPER" and type(m[2]) == "string" then
      for c = 1, copies do
        local sender = "Member" .. (2 + (c * 7 + played) % (ONLINE - 1))
        FIRE("CHAT_MSG_ADDON", m[1], m[2], m[3], sender, m[3] == "CHANNEL" and "ChehulNet" or "Me", 0,
          m[3] == "CHANNEL" and 5 or 0, m[3] == "CHANNEL" and "ChehulNet" or "", 0)
      end
      played = played + 1
      PLAYED = (PLAYED or 0) + copies
    end
  end
end

-- Other addons' traffic on the same channels (boss mods, auras, quest sharing): not Guild OS's, read and dropped.
local FOREIGN = { "D5", "BigWigs", "WeakAuras", "Questie", "LGP", "CTRA", "RCLC", "Details" }

-- One simulated second of a scenario: `rate` is per minute.
local function every(perMinute, sec) return perMinute > 0 and (sec % math.max(1, math.floor(60 / perMinute + 0.5))) == 0 end
local SC = {
  idle = { roster = 4, guild = 3, channel = 10, system = 2, foreignAddon = 20, aura = 60, target = 6, tooltip = 6,
    bag = 2, zone = 0, group = 0, combat = 0, copies = 15, nameplate = 0 },
  active = { roster = 6, guild = 12, channel = 40, system = 4, foreignAddon = 120, aura = 1200, target = 60,
    tooltip = 120, bag = 30, zone = 2, group = 12, combat = 1500, copies = 20, nameplate = 120, party = 20, whisper = 6 },
}
local secs = 0
local function simSecond(sc)
  secs = secs + 1
  local s = secs
  for _ = 1, FPS do stepFrame() end
  if every(sc.roster, s) then FIRE("GUILD_ROSTER_UPDATE", false) end
  local who = "Member" .. (2 + s % (ONLINE - 1))
  if every(sc.guild, s) then
    chat("CHAT_MSG_GUILD", chatArgs("anyone up for a dungeon run tonight " .. s, who))
    CLUB_LINES = math.min(200, CLUB_LINES + 1)
    FIRE("CLUB_MESSAGE_ADDED", 1, 1, { epoch = 2e15, position = CLUB_LINES })
  end
  if every(sc.party or 0, s) then chat("CHAT_MSG_RAID", chatArgs("pull in 10 " .. s, who)) end
  for _ = 1, math.max(1, math.floor(sc.channel / 60)) do
    if every(sc.channel, s) then
      chat("CHAT_MSG_CHANNEL", chatArgs("WTS [Arcanite Bar] cheap, pst " .. s, "Rando" .. (s % 97), "2. Trade - City", 2))
    end
  end
  if every(sc.system, s) then
    chat("CHAT_MSG_SYSTEM", (s % 2 == 0) and (who .. " has come online.") or (who .. " has gone offline."))
  end
  for k = 1, math.max(1, math.floor(sc.foreignAddon / 60)) do
    if every(sc.foreignAddon, s) then
      local p = FOREIGN[(s + k) % #FOREIGN + 1]
      FIRE("CHAT_MSG_ADDON", p, "v1:" .. s .. ":some payload " .. k, GROUP.raid and "RAID" or "GUILD", who, "Me", 0, 0, "", 0)
    end
  end
  for k = 1, math.max(1, math.floor(sc.aura / 60)) do
    if every(sc.aura, s) then FIRE("UNIT_AURA", (k % 3 == 0) and "player" or ("raid" .. (k % 20 + 1)), {}) end
  end
  if every(sc.target, s) then
    local i = 2 + s % (N - 1)
    UNITS.target = { name = ROSTER_ROWS[i].name, guid = ROSTER_ROWS[i].guid, class = ROSTER_ROWS[i].classFile }
    FIRE("PLAYER_TARGET_CHANGED")
  end
  for k = 1, math.max(1, math.floor(sc.tooltip / 60)) do
    if every(sc.tooltip, s) then
      if (s + k) % 2 == 0 then hoverItem(19000 + (s * 3 + k) % 400) else hoverUnit(2 + (s + k) % (N - 1)) end
    end
  end
  if sc.nameplate > 0 then
    for k = 1, math.max(1, math.floor(sc.nameplate / 60)) do
      FIRE("NAME_PLATE_UNIT_ADDED", "nameplate" .. k); FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate" .. k)
    end
  end
  for _ = 1, math.max(1, math.floor(sc.bag / 60)) do
    if every(sc.bag, s) then FIRE("BAG_UPDATE", s % 5); FIRE("BAG_UPDATE_DELAYED") end
  end
  if every(sc.zone, s) then
    FIRE("ZONE_CHANGED"); FIRE("ZONE_CHANGED_NEW_AREA"); FIRE("ZONE_CHANGED_INDOORS")
  end
  if every(sc.group, s) then FIRE("GROUP_ROSTER_UPDATE") end
  if sc.combat > 0 then
    -- a pull every minute, 40 s of fighting
    if s % 60 == 0 then FIRE("PLAYER_REGEN_DISABLED") elseif s % 60 == 40 then FIRE("PLAYER_REGEN_ENABLED") end
    if s % 60 < 40 then
      for _ = 1, math.floor(sc.combat / 60) do FIRE("COMBAT_LOG_EVENT_UNFILTERED") end
      FIRE("UNIT_HEALTH", "target"); FIRE("UNIT_POWER_UPDATE", "player", "MANA")
    end
  end
  if every(sc.whisper or 0, s) then chat("CHAT_MSG_WHISPER", chatArgs("hey, got a minute? " .. s, who)) end
  playBack(sc.copies)
end

local function fullKB() collectgarbage("collect"); collectgarbage("collect"); return collectgarbage("count") end

-- ── Login ────────────────────────────────────────────────────────────────
FIRE("ADDON_LOADED", "GuildOS")
FIRE("PLAYER_LOGIN")
FIRE("PLAYER_ENTERING_WORLD", true, false)
FIRE("GUILD_ROSTER_UPDATE", false)
check(GuildOS.db ~= nil, "the guild db resolves")

-- The saved data the maintainer's guild has: gear and professions off the members' own broadcasts, the roster
-- log (1,100 lines over half a year), the history the roster makes.
do
  local ev = GuildOS.db.rosterLog and GuildOS.db.rosterLog.events
  if type(ev) == "table" then
    for i = 1, 1100 do
      ev[#ev + 1] = { action = (i % 3 == 0) and "promote" or "join", target = "Member" .. (i % N + 1), author = "Member2",
        detail = "Rank2", timestamp = GetServerTime() - i * 14000, id = "e" .. i }
    end
  end
  local CS = GuildOS.CommSystem
  local LS = LibStub and LibStub("GuildOS-LibSerialize", true)
  if CS and CS.HandleBroadcast and LS then
    for i = 2, 120 do
      local g = {}
      for s = 1, 18 do
        local id = 16800 + (i * 7 + s * 13) % 3000
        g[s] = { link = string.format("|cffa335ee|Hitem:%d:%d::::::::60|h[Epic %d]|h|r", id, 1800 + s, id),
          id = id, name = "Epic " .. id, quality = 4, ilvl = 66 + s, enchantId = 1800 + s }
      end
      pcall(CS.HandleBroadcast, CS, "Member" .. i, LS:Serialize({ name = "Member" .. i, realm = "Forever",
        class = CLASSES[i % 9 + 1], level = 60, race = "Human", lastUpdate = GetServerTime(), gear = g, avgIlvl = 70,
        spec = "Arms", addonVersion = "1.43.5", professions = { { name = "Mining", rank = 300, max = 300 },
          { name = "Blacksmithing", rank = 295, max = 300 } } }), "GUILD")
    end
  end
end

-- Three minutes settle the start-up work (the login scans, the first sync, the settled history scan) outside every count.
for _ = 1, 180 do simSecond(SC.idle) end
OUTBOX = {}
ERRS = {}

local function scenario(sc, minutes)
  TRIG = {}
  local total = 0
  measuring = true
  collectgarbage("collect"); collectgarbage("stop")
  for m = 1, minutes do
    for _ = 1, 60 do simSecond(sc) end
    for _, kb in pairs(TRIG) do total = total + kb end
    for k in pairs(TRIG) do TRIG[k] = 0 end
    collectgarbage("restart"); collectgarbage("collect"); collectgarbage("stop")
    if PROFILE then print(string.format("  minute %d: %.0f KB so far", m, total)) end
  end
  measuring = false
  collectgarbage("restart")
  return total / minutes
end

-- ── Per function and per trigger (ALLOC_PROFILE=1) ───────────────────────
local function profiled(name, sc, minutes)
  local SELF, BYTRIG = {}, {}
  local stack, top = {}, 0
  TRIGN = {}
  local last = 0
  local getinfo = debug.getinfo
  local keyOf = setmetatable({}, { __mode = "k" })
  local function hook(ev)
    local now = gcount("count")
    if top > 0 then
      local k, d = stack[top], now - last
      SELF[k] = (SELF[k] or 0) + d
      local t = CURRENT or "<harness>"
      BYTRIG[t] = (BYTRIG[t] or 0) + d
    end
    if ev == "call" then
      local fn = getinfo(2, "f").func
      local k = keyOf[fn]
      if not k then
        local i = getinfo(2, "S")
        if i.what == "C" then k = false else k = (i.short_src:gsub("^.*guildos/", ""):gsub("^%./", "")) .. ":" .. i.linedefined end
        keyOf[fn] = k
      end
      top = top + 1
      stack[top] = k or stack[top - 1] or "<harness>"   -- a C function's allocation is its caller's
    elseif top > 0 then
      stack[top] = nil
      top = top - 1
    end
    last = gcount("count")
  end
  TRIG = {}
  measuring = true
  collectgarbage("collect"); collectgarbage("stop")
  for _ = 1, minutes do
    for _ = 1, 60 do
      top = 0; last = gcount("count")
      debug.sethook(hook, "cr")
      simSecond(sc)
      debug.sethook()
    end
    collectgarbage("restart"); collectgarbage("collect"); collectgarbage("stop")
  end
  measuring = false
  collectgarbage("restart")
  local rows = {}
  for k, v in pairs(SELF) do rows[#rows + 1] = { k, v } end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  print(string.format("== %s: self allocation per function, KB a minute (%d min)", name, minutes))
  for i = 1, math.min(40, #rows) do print(string.format("%10.1f  %s", rows[i][2] / minutes, rows[i][1])) end
  rows = {}
  for k, v in pairs(BYTRIG) do rows[#rows + 1] = { k, v } end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  print(string.format("== %s: by trigger (what ran under it, the harness's own work apart), KB a minute", name))
  for i = 1, math.min(30, #rows) do
    local n = TRIGN[rows[i][1]] or 0
    print(string.format("%10.1f  %6d calls/min %8.2f KB/call  %s", rows[i][2] / minutes, n / minutes,
      n > 0 and rows[i][2] / n or 0, rows[i][1]))
  end
  TRIGN = {}
end

-- The active run: in a raid of 20, the window open on the Hall; its first drawing and the raid's start-up work
-- are outside the count.
local function goActive()
  GROUP.raid, GROUP.n = true, 20
  for i = 1, 20 do
    local r = ROSTER_ROWS[i + 1]
    UNITS["raid" .. i] = { name = r.name, guid = r.guid, class = r.classFile, raid = i }
  end
  FIRE("GROUP_ROSTER_UPDATE"); FIRE("ZONE_CHANGED_NEW_AREA")
  -- Chat Tweaks on, for whispers and the group too (an officer who turned it on: every line runs its filter)
  local ct = GuildOS.db.chatTweaks
  if ct then ct.enabled, ct.whisper, ct.group = true, true, true end
  local ok, e = pcall(GuildOS.UI.OpenWindow, GuildOS.UI, "home")
  check(ok, "the window opens on the Hall: " .. tostring(e))
  for _ = 1, 30 do simSecond(SC.active) end
end

-- tools/inbox-perf.lua drives its own play from here, on this client.
if ALLOC_HARNESS then
  return ALLOC_HARNESS({ simSecond = simSecond, stepFrame = stepFrame, SC = SC, FIRE = FIRE, chat = chat, chatArgs = chatArgs, check = check,
    scenario = scenario, profiled = profiled, goActive = goActive, fullKB = fullKB, errors = function() return ERRS end,
    checks = function() return checks end })
end

if PROFILE then
  profiled("idle", SC.idle, MINUTES)
  goActive()
  profiled("active", SC.active, MINUTES)
  print("errors", #ERRS, "addon messages played back", PLAYED)
  for i = 1, math.min(10, #ERRS) do print("  " .. ERRS[i]) end
  os.exit(0)
end

-- ── The checks ───────────────────────────────────────────────────────────
local r0 = fullKB()
local idle = scenario(SC.idle, MINUTES)
local r1 = fullKB()
local idle2 = scenario(SC.idle, MINUTES)
local r2 = fullKB()
check(idle < IDLE_BUDGET_KB and idle2 < IDLE_BUDGET_KB,
  string.format("idle garbage %.0f / %.0f KB a minute, budget %d", idle, idle2, IDLE_BUDGET_KB))
check(r2 - r1 < RETAINED_GROWTH_KB, string.format("retained memory grew %.0f KB over %d idle minutes", r2 - r1, MINUTES))

-- The same quiet hour with the window open on the Members tab: its roster redraws at every roster update.
local okRoster, eRoster = pcall(GuildOS.UI.OpenWindow, GuildOS.UI, "roster")
check(okRoster, "the window opens on the Members tab: " .. tostring(eRoster))
for _ = 1, 20 do simSecond(SC.idle) end
local members = scenario(SC.idle, MINUTES)
check(members < MEMBERS_BUDGET_KB, string.format("Members tab garbage %.0f KB a minute, budget %d", members, MEMBERS_BUDGET_KB))

-- What the roster built while it showed is filled again, not made anew, and a hidden roster draws nothing.
local host = GuildOS.RosterFrame
do
  local before = host.sortedMembers[1]
  host:RefreshRoster()
  check(#host.sortedMembers > 0 and host.sortedMembers[1] == before, "the roster's entries are kept between refreshes")
  local Marks = GuildOS.UI.RosterMarks
  local s1 = Marks.Scan()
  local cur1, none1 = s1.count.cur, s1.count.none
  local s2 = Marks.Scan()
  check(s2 == s1 and s2.count.cur == cur1 and s2.count.none == none1 and cur1 > 0, "the marks' scan is refilled, the same counts")
  local unique, chars = GuildOS:TrueRosterCounts()
  local tr = GuildOS:GetTrueRoster()
  check(unique == tr.uniqueCount and chars == tr.totalChars, "the tiles' counts are the true roster's")
  local RC = GuildOS.RosterCard
  local links = { ["Member4"] = "Member3", ["Member7"] = "Member3", ["Member9"] = "Member8" }
  local fresh = RC.NewIndex(links)
  local again = RC.NewIndex(links, RC.NewIndex({ ["MemberX"] = "MemberY" }))
  check(table.concat(again.altsOf.Member3, ",") == table.concat(fresh.altsOf.Member3, ",") and again.altsOf.MemberY == nil
    and #again.altsOf.Member8 == 1, "a reused index answers as a new one")
end
local okHall = pcall(GuildOS.UI.OpenWindow, GuildOS.UI, "home")
check(okHall, "back to the Hall")
GuildOS:RefreshRosterUI()
check(host.rosterDirty == true, "the roster under another tab waits for its own show")

-- Pooled answers read as fresh ones.
do
  local GM = GuildOS.GuildManager
  local a, b = GM:GetInactiveMembers(5), GM:GetInactiveMembers(5)
  local na, nb = {}, {}
  for k, m in ipairs(a) do na[k] = m.name .. ":" .. m.daysOffline end
  for k, m in ipairs(b) do nb[k] = m.name .. ":" .. m.daysOffline end
  check(#a > 0 and table.concat(na, ",") == table.concat(nb, ","), "the inactive list is the same from its kept lines")
  local R = GuildOS.Readiness
  local lv, full = R:LevelRows({}), R:GetReport()
  local byKey = {}
  for _, r in ipairs(full) do byKey[r.key] = r.level end
  local same = #lv == #full
  for _, r in ipairs(lv) do if byKey[r.key] ~= r.level then same = false end end
  check(same, "the countdown's level rows are the report's keys and levels")
  check(GuildOS:LocalDate("%H:%M", START) == date("%H:%M", START), "a date with no names is date()'s")
  -- The guild map's roster drops who left.
  local G = GuildOS.GuildMap
  local gone = table.remove(ROSTER_ROWS)
  G._rosterStale = true
  check(G:_Roster()[GuildOS:KeyOfRosterName(gone.name)] == nil and G:_Roster()[GuildOS:KeyOfRosterName("Member2")] ~= nil,
    "the map's kept roster drops a member who left")
  ROSTER_ROWS[#ROSTER_ROWS + 1] = gone
  G._rosterStale = true
end

goActive()
local active = scenario(SC.active, MINUTES)
local r3 = fullKB()

-- A raid's roster storm: one snapshot per ROSTER_SNAP_GAP, not one per event.
do
  local RT = GuildOS.RaidTracker
  local snaps, take, was = 0, RT.TakeSnapshot, RT.trackingActive
  RT.TakeSnapshot = function() snaps = snaps + 1 end
  RT.trackingActive = true
  for sec = 1, 60 do
    simSecond(SC.idle)
    if sec % 3 == 0 then FIRE("GROUP_ROSTER_UPDATE") end
  end
  RT.TakeSnapshot, RT.trackingActive = take, was
  check(snaps >= 1 and snaps <= 3, string.format("a minute of 20 group updates made %d raid snapshots, at most 3", snaps))
end

print(string.format("alloc-budget: KB a minute: idle %.0f / %.0f (budget %d), Members tab %.0f (budget %d), active %.0f (budget %d)",
  idle, idle2, IDLE_BUDGET_KB, members, MEMBERS_BUDGET_KB, active, ACTIVE_BUDGET_KB))
print(string.format("alloc-budget: retained %.0f -> %.0f -> %.0f KB idle, %.0f KB after the active run", r0, r1, r2, r3))
check(active < ACTIVE_BUDGET_KB, string.format("active garbage %.0f KB a minute, budget %d", active, ACTIVE_BUDGET_KB))
print(string.format("alloc-budget: %d checks passed (%d handler errors under the stub)", checks, #ERRS))
