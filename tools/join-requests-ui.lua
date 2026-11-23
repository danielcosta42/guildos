-- The "Join requests" list and its notice, drawn (issue #421): a long note is cut to one line in its
-- row, but the mouse over the row shows all of it wrapped in the tooltip, and a click opens the row
-- to the whole note, wrapped, pushing the rows below down. The notice's tooltip carries the note too.
-- The note shown is the one Modules/JoinRequests.lua kept (already clean, GuildFinder.Text).
-- Same permissive frame stub as tools/crafts-tab.lua; the module is a stand-in.
--
--   luajit -e 'ADDON="."' tools/join-requests-ui.lua
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
function Proxy:SetWordWrap(v) self.wrap = v end
function Proxy:GetStringWidth() return #(self.text or "") * 6 end
-- One 12-pixel line, or as many as the text takes at six pixels a byte when it wraps.
function Proxy:GetStringHeight()
  if not self.wrap or self.w == 0 then return 12 end
  return 12 * math.max(1, math.ceil(#(self.text or "") * 6 / self.w))
end
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
function Proxy:SetPoint(point, a, b, c, d)
  self.point = { point, a, b, c, d }
end
function CreateFrame(kind, name, parent)
  local f = Proxy.new(kind, parent)
  f.name = name
  if name then _G[name] = f end
  return f
end

-- The tooltip, which remembers its lines and whether each wraps.
local tip = Proxy.new("GameTooltip")
tip.lines = {}
function tip:SetOwner(owner) self.owner, self.lines = owner, {} end
function tip:AddLine(text, _, _, _, wrap) self.lines[#self.lines + 1] = { text = text, wrap = wrap } end
local function tipHas(text, wrapped)
  for _, l in ipairs(tip.lines) do
    if l.text == text and (wrapped == nil or (l.wrap and true or false) == wrapped) then return true end
  end
  return false
end

-- ── The client ──────────────────────────────────────────────────────────
local NOW = 1790500000
C_Timer = { After = function() end, NewTicker = function() return {} end }
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
DEFAULT_CHAT_FRAME = { AddMessage = noop }
SlashCmdList, UISpecialFrames = {}, {}
UIParent, GameTooltip = Proxy.new("Frame"), tip
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
dofile(ADDON .. "/Core/Style.lua")
dofile(ADDON .. "/UI/Helpers.lua")

-- The module, a stand-in holding three requests: a long note, none, a short one.
local LONG = ("I raid three nights a week and I am looking for a calm guild to clear the "
  .. "whole tier with, I can heal or tank"):sub(1, 120)
local list = {
  { id = "aaaaaaaaaa", character = "Marta Vilar", class = "PALADIN", level = 60, role = "HEALER", note = LONG,
    at = NOW - 60, seen = NOW, status = "open" },
  { id = "bbbbbbbbbb", character = "Ana Lima", at = NOW - 120, seen = NOW, status = "open" },
  { id = "cccccccccc", character = "Bruno Reis", note = "oi", at = NOW - 180, status = "open", source = "site" },
}
GuildOS.JoinRequests = {
  ONLINE_SECONDS = 360,
  List = function() return list end,
  OpenCount = function() return #list end,
  CanDecide = function() return true end,
  CanInvite = function() return true end,
  Listen = noop, Refresh = noop, Invite = noop, Decide = noop,
}
dofile(ADDON .. "/UI/JoinRequests.lua")

GuildOS:ShowJoinRequests()
local f = GuildOS.joinRequestsFrame
check(f and f:IsShown(), "the list opens")
local rows = {}
for _, o in ipairs(all) do
  if o.kind == "Button" and o.note then rows[#rows + 1] = o end
end
check(#rows == 3, "one row per request: " .. #rows)
local long = rows[1]
local quoted = "\226\128\156" .. LONG .. "\226\128\157"
check(long.note.text == quoted and long.note.wrap == false, "the note is one line in its row, as before")
check(long.h == 64 and rows[2].point[3] == -64 and rows[3].point[3] == -128, "rows of one line, one under the other")

-- The mouse over the row: the whole note, wrapping.
long.scripts.OnEnter(long)
check(tip.owner == long and tipHas("Marta Vilar") and tipHas(quoted, true), "the tooltip has the whole note, wrapped")
check(tipHas(long.detail.text, true) and tipHas(long.meta.text, true), "and the class, level, role and when, wrapped too")
long.scripts.OnLeave(long)
rows[2].scripts.OnEnter(rows[2])
check(tipHas("Ana Lima") and not tipHas(quoted), "a row with no note has no note in its tooltip")

-- A click opens the row to the whole note and pushes the others down; another closes it.
long.scripts.OnClick(long)
check(long.note.wrap == true and long.note.text == quoted, "a click wraps the note in the row")
check(long.h > 64, "the row grows to hold it: " .. long.h)
check(long.meta.point[2] == long.note, "the when goes under the note")
check(rows[2].point[3] == -long.h and rows[3].point[3] == -(long.h + 64), "the rows below move down")
long.scripts.OnClick(long)
check(long.note.wrap == false and long.h == 64 and rows[2].point[3] == -64, "a second click folds it back")
rows[2].scripts.OnClick(rows[2])
check(rows[2].h == 64 and rows[2].note.wrap == false, "a row with no note has nothing to open")

-- The notice: its line is cut to the box, its tooltip has all of it and the note.
GuildOS:JoinRequestsHeard(list[1])
local toast = _G.GuildOSJoinRequestToast
check(toast and toast:IsShown() and toast.who.wrap == false, "the notice is one line")
toast.scripts.OnEnter(toast)
check(tip.owner == toast and tipHas("Marta Vilar") and tipHas(quoted, true), "the notice's tooltip has the note, wrapped")

print(("join-requests-ui: %d checks passed"):format(checks))
