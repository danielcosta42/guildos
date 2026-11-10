-- The scanner's reply inbox (issue #311), run against the real Core/Core.lua, Core/Compat.lua,
-- Core/Utils.lua, Modules/RecruitScanner.lua and UI/Agora.lua.
--
-- Every whisper reply from someone the scanner whispered was kept forever, and the Now tab counted
-- every one as "%d applicants waiting": the row never went away. Now opening the inbox view reads
-- it (only a reply after that waits), its Clear button empties it, and a reply older than two
-- weeks is dropped.
--
--   luajit -e 'ADDON="."' tools/recruit-inbox.lua
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

local NOW = 1790000000
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local handlers = {}
local function eventFrame()
  local f, ev = {}, {}
  function f:RegisterEvent(e) ev[e] = true end
  function f:UnregisterEvent(e) ev[e] = nil end
  function f:SetScript(_, fn) self._fn = fn; handlers[#handlers + 1] = { frame = self, events = ev } end
  return f
end
CreateFrame = eventFrame
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Chehul" end
function GetServerTime() return NOW end
time = function() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "GM", 0 end
function GetNumGuildMembers() return 1 end
function GetGuildRosterInfo(i) if i == 1 then return "Chehul", "GM", 0, 70, "Warrior", "", "", "", true, 0, "WARRIOR" end end
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
C_Timer = { After = function() end, NewTicker = function() end }
function SendChatMessage() end
local registry = {}
LibStub = setmetatable({ NewLibrary = function(_, n) registry[n] = registry[n] or {}; return registry[n] end,
  GetLibrary = function(_, n) return registry[n] end },
  { __call = function(_, n) registry[n] = registry[n] or {}; return registry[n] end })
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/RecruitScanner.lua")
function GuildOS:IsOfficer() return true end

-- The Now tab's data half needs only these of the UI.
local realUI = { IsFeatureAllowed = function() return true end, GetFeature = function(_, id) return id end }
GuildOS.UI, GuildOS.Colors = realUI, setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
dofile(ADDON .. "/UI/Agora.lua")
local A = realUI.Agora

local S = GuildOS.RecruitScanner
local DAY = 86400
GuildOS.db = { recruitScanner = { inbox = {
  { name = "Fresh", msg = "hi", ts = NOW - 60 },
  { name = "Week", msg = "hi", ts = NOW - 7 * DAY },
  { name = "Old", msg = "hi", ts = NOW - 15 * DAY },
  { name = "NoTime", msg = "hi" },
} } }

local function waiting()
  for _, item in ipairs(A:NeedsMe()) do
    local n = item.text:match("^(%d+) applicants waiting$")
    if n then return tonumber(n) end
  end
  return 0
end

-- ── Expiry ──────────────────────────────────────────────────────────────
S:Initialize()
local inbox = S:GetInbox()
check(#inbox == 2 and inbox[1].name == "Fresh" and inbox[2].name == "Week",
  "Initialize drops the replies older than 14 days, and one with no time")
check(waiting() == 2, "never opened, every reply is waiting")
NOW = NOW + 8 * DAY
check(#S:GetInbox() == 1 and S:GetInbox()[1].name == "Fresh", "GetInbox drops a reply as it turns 14 days old")
check(waiting() == 1, "and the Now tab stops counting it")

-- ── A new reply lands, and waits ────────────────────────────────────────
local function whisper(msg, from)
  for _, h in ipairs(handlers) do
    if h.events.CHAT_MSG_WHISPER then h.frame._fn(h.frame, "CHAT_MSG_WHISPER", msg, from) end
  end
end
S._contactCd.Ana = NOW + 1800
whisper("yes please", "Ana-Realm")
check(#S:GetInbox() == 2 and S:GetInbox()[1].name == "Ana" and S:GetInbox()[1].ts == NOW,
  "a reply from a contacted player lands first, with its time")
check(waiting() == 2, "the new reply is waiting")

-- ── The inbox view: opening it reads, Clear empties ─────────────────────
-- A frame that answers every call: what is checked is what the panel's handlers do to the inbox.
-- Every field is another such frame, and calling one as a method answers like the client would.
local node
node = function(name)
  return setmetatable({ _scripts = {} }, {
    __index = function(t, k)
      local m = node(k)
      rawset(t, k, m)
      return m
    end,
    __call = function(_, obj, a, b)
      if name == "SetScript" then rawget(obj, "_scripts")[a] = b; return end
      if name == "IsShown" then return true end
      if name == "GetText" then return "" end
      if name == "GetChildren" or name == "GetRegions" then return end
      if name and name:find("^Get") then return 100 end
      return node()
    end,
  })
end
GuildOS.UI = node()
CreateFrame = function() return node() end
local panel = node()
panel._scannerBuilt = false   -- a node answers every field; this one the build reads first
S:BuildInto(panel)
GuildOS.UI, CreateFrame = realUI, eventFrame
check(panel.tabs and panel.tabs.inbox and panel.clearBtn, "the panel has its Inbox tab and a Clear button")
check(waiting() == 2, "built on the Results view, the inbox is not read yet")

NOW = NOW + 30
panel.tabs.inbox._scripts.OnClick()
check(GuildOS.db.recruitScanner.inboxReadAt == NOW, "opening the inbox view stores when it was read")
check(waiting() == 0, "after opening it, no applicants are waiting")
check(#S:GetInbox() == 2, "reading keeps the replies")

NOW = NOW + 30
S._contactCd.Bea = NOW + 1800
whisper("is the spot open?", "Bea")
check(waiting() == 1, "a reply after the last look waits")

panel.clearBtn._scripts.OnClick()
check(#S:GetInbox() == 0, "Clear empties the inbox")
check(waiting() == 0, "and nothing waits")
NOW = NOW + 1
whisper("hello again", "Bea")
check(#S:GetInbox() == 1 and waiting() == 1, "a reply after Clear lands in the emptied inbox and waits")

print(("recruit-inbox: %d checks passed"):format(checks))
