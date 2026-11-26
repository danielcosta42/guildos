-- The bulletin on the Now tab and at login, with how long a notice lasts (issue #418), run against
-- the real Libs/LibStub.lua, Libs/LibSerialize.lua, Core/Core.lua, Core/Compat.lua, Core/Utils.lua,
-- Modules/CommSystem.lua, Modules/SyncService.lua, Modules/Bulletin.lua, Modules/Digest.lua and the
-- data half of UI/Agora.lua under a stubbed client.
--
-- An officer picks how long a notice lasts when posting it: some days, or until it is removed. A
-- notice made before #418 has no end, as "until I close it". The end (`exp`) rides inside the same
-- board snapshot, so an older client reads, keeps and re-sends it untouched. The Now tab shows the
-- newest three notices still running. At login the digest tells each running notice this player has
-- not been told about, once; with the digest off, or on the first login, a chat line does, and a
-- notice that arrives after the login is told in the chat.
--
--   luajit -e 'ADDON="."' tools/bulletin-expiry.lua
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

local DAY = 86400
local NOW = 1791000000
local now, officer, printed, sent = NOW, true, {}, {}

strmatch = string.match
dofile(ADDON .. "/Libs/LibStub.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
local LS = LibStub("GuildOS-LibSerialize")

DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
function CreateFrame() local f = {}; function f:RegisterEvent() end; function f:SetScript() end; return f end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Off" end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Rank", officer and 1 or 5 end
function GetNumGuildMembers() return 0, 0 end
function GetServerTime() return now end
function GetTime() return 1 end
function GetLocale() return "enUS" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
time = function() return now end
date = os.date
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/Bulletin.lua")
dofile(ADDON .. "/Modules/Digest.lua")
GuildOS.IsOfficer = function() return officer end
GuildOS.CommSystem.SendMessage = function(_, t, data) sent[#sent + 1] = { t = t, data = data } end
GuildOS.UI = { IsFeatureAllowed = function() return true end, GetFeature = function(_, id) return id end }
GuildOS.Colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
dofile(ADDON .. "/UI/Spacing.lua"); if GuildOS.UI then rawset(GuildOS.UI, "SP", GuildOS.Spacing) end   -- the spacing standard (#449)
dofile(ADDON .. "/UI/Agora.lua")
dofile(ADDON .. "/UI/Salao.lua")
local A, B, D = GuildOS.UI.Agora, GuildOS.Bulletin, GuildOS.Digest

local function fresh(db)
  GuildOS.db = db or { sync = {}, settings = {}, members = {} }
  GuildOS.db.sync = GuildOS.db.sync or {}
  B.loginDone, D.shownThisSession, D.deferred = nil, nil, nil
  GuildOS.SyncService:Initialize()
  B:Initialize()
  D:Initialize()
  printed, sent = {}, {}
end
local function printedHas(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return true end end
  return false
end
local shownLines
D.Show = function(_, lines) shownLines = lines end

-- ── 1. Posting: how long it lasts ───────────────────────────────────────
fresh()
local opts = B:DurationOptions()
check(#opts == 6 and opts[1].value == 0 and opts[1].text == "Until I close it" and opts[2].text == "For 1 day"
  and opts[4].value == 7 and opts[4].text == "For 7 days", "the picker: until I close it, then 1, 3, 7, 14 and 30 days")
B:Post("Raid moved to Thursday", 3)
local m3 = B:GetMessages()[1]
check(m3.exp == NOW + 3 * DAY and m3.ts == NOW, "a notice for 3 days ends 3 days after it is posted")
now = NOW + 10
B:Post("Bring flasks")
local forever = B:GetMessages()[1]
check(forever.exp == nil, "a notice until I close it carries no end, as every notice before #418")
B:Post("Picked nothing", "abc")
check(B:GetMessages()[1].exp == nil, "a pick that is not a number is until I close it")
check(GuildOS.db.bulletin.seen[m3.id] and GuildOS.db.bulletin.seen[forever.id],
  "the officer's own notices are not told back to them")

-- ── 2. The wire: the end inside the same snapshot ───────────────────────
check(#sent >= 1, "a post publishes the board")
local ok, env = LS:Deserialize(sent[#sent].data)
local wired
for _, m in ipairs(ok and env.data.messages or {}) do if m.id == m3.id then wired = m end end
check(ok and env.dom == "bulletin" and env.act == "snapshot" and wired and wired.exp == NOW + 3 * DAY,
  "the board's snapshot carries the end with the notice")
-- An older client applies the snapshot as `messages = env.data.messages`: it keeps the end it does not
-- know, and the board it re-sends (its post, a backfill) still carries it.
local oldBoard = env.data.messages
table.insert(oldBoard, 1, { id = "OLD1", text = "From an older officer", author = "Old", ts = NOW + 20 })
local ok2, back = LS:Deserialize(LS:Serialize({ messages = oldBoard }))
local kept
for _, m in ipairs(ok2 and back.messages or {}) do if m.id == m3.id then kept = m end end
check(kept and kept.exp == NOW + 3 * DAY, "an older client's re-sent board keeps the end untouched")

-- A member receives it.
officer = false
fresh({ sync = {}, digest = { enabled = true, lastSeen = NOW - DAY }, settings = {}, members = {} })
GuildOS.SyncService.Validate = function() return true end
B:OnSync({ act = "snapshot", rev = 5, data = { messages = back.messages } })
check(#B:GetMessages() == 4, "the member stores the whole board")
check(#printed == 0, "before the login's digest, nothing is told in the chat")

-- ── 3. Active, the Now tab, the board ───────────────────────────────────
now = NOW + 4 * DAY
local active = B:Active(now)
check(#active == 3 and active[1].id == "OLD1", "the 3-day notice ended; the others run, the newest first")
for _, m in ipairs(active) do check(m.id ~= m3.id, "no ended notice is active") end
check(B.IsActive({ id = "x", text = "t", ts = 1 }, now), "a notice from before #418, without an end, runs until removed")
check(B.IsActive({ id = "x", text = "t", ts = 1, exp = "soon" }, now), "an end that is not a number is no end")
local rows = A:Notices()
check(#rows == 3 and rows[1].text == "From an older officer" and rows[1].id == "guild" and rows[1].sub == "bulletin"
  and rows[1].ts == NOW + 20, "the Now tab: the newest running notices, each opening the guild's bulletin")
check(#A:Notices(2) == 2, "and no more than asked")
local listed = B:Listed(now)
check(#listed == 3, "a member's board lists only the running notices")
officer = true
check(#B:Listed(now) == 4, "an officer's lists the ended one too, to remove it")
check(B.MetaText(m3, now):find("no longer shown", 1, true), "marked as no longer shown")
check(B.MetaText(m3, NOW):find("until ", 1, true), "while it runs, until when")
check(not B.MetaText(forever, now):find("until", 1, true), "a notice until I close it says no end")
officer = false
GuildOS.UI.IsFeatureAllowed = function() return false end
check(#A:Notices() == 0, "a player who cannot open the guild's tab gets no bulletin section")
GuildOS.UI.IsFeatureAllowed = function() return true end

-- ── 4. The login digest tells each running notice once ──────────────────
shownLines = nil
D:ShowOnLogin()
local told = 0
for _, l in ipairs(shownLines or {}) do if l:find("Notice:", 1, true) then told = told + 1 end end
check(told == 3, "the digest tells the three running notices (" .. told .. ")")
check(not table.concat(shownLines, "\n"):find("Raid moved to Thursday", 1, true), "never the one that ended")
check(#B:Unseen(now) == 0, "and they are told")
D.shownThisSession = nil
shownLines = nil
D:ShowOnLogin()
local again = 0
for _, l in ipairs(shownLines or {}) do if l:find("Notice:", 1, true) then again = again + 1 end end
check(again == 0, "the next login does not tell them again")

-- After the login, a new notice that arrives is a chat line; the same board again says nothing.
printed = {}
local board = {}
for _, m in ipairs(B:GetMessages()) do board[#board + 1] = m end
table.insert(board, 1, { id = "NEW1", text = "Guild meeting |cffff0000tonight|r", author = "Off", ts = now })
B:OnSync({ act = "snapshot", rev = 6, data = { messages = board } })
check(#printed == 1 and printedHas("Notice:") and printedHas("Guild meeting cffff0000tonightr"),
  "a notice that arrives after the login is told in the chat, its colour codes taken out")
B:OnSync({ act = "snapshot", rev = 7, data = { messages = board } })
check(#printed == 1, "and only once")

-- ── 5. Digest off, first login: a chat line each ────────────────────────
fresh({ sync = {}, digest = { enabled = false, lastSeen = NOW }, settings = {}, members = {},
        bulletin = { seen = {}, messages = {
          { id = "A", text = "One", author = "Off", ts = now - 30 },
          { id = "B", text = "Two", author = "Off", ts = now - 20, exp = now + DAY },
          { id = "C", text = "Gone", author = "Off", ts = now - 10, exp = now - 1 } } } })
D:ShowOnLogin()
check(#printed == 2 and printedHas("Two") and printedHas("One") and not printedHas("Gone"),
  "with the digest off, each running notice not told yet is a chat line")
printed = {}
B.loginDone = nil
D:ShowOnLogin()
check(#printed == 0, "once")

fresh({ sync = {}, settings = {}, members = {}, bulletin = { messages = {}, seen = {} } })
B:OnSync({ act = "snapshot", rev = 1, data = { messages = {
  { id = "A", text = "Welcome aboard", author = "Off", ts = now - 30 } } } })
check(#printed == 0, "a fresh install's board arriving before the login is not told yet")
D:ShowOnLogin()
check(#printed == 1 and printedHas("Welcome aboard"), "on the first login ever the board is told in the chat")

-- Upgrading: every notice already on the board counts as told, whatever the digest's clock says (it may be off,
-- or its last look long ago); only what arrives after is new.
fresh({ sync = {}, digest = { enabled = false, lastSeen = now - 400 * DAY }, settings = {}, members = {},
        bulletin = { messages = { { id = "Old", text = "Shown last time", author = "Off", ts = now - 100 },
                                  { id = "Newer", text = "Not yet", author = "Off", ts = now - 1 },
                                  { text = "No id", author = "Off", ts = now - 2 } } } })
check(#B:Unseen(now) == 0, "on the update, the notices already on the board count as told")
D:ShowOnLogin()
check(#printed == 0, "so the first login after it tells none of them")

-- A notice from the wire without an id is remembered by who, when and what: told once, not at every snapshot.
fresh({ sync = {}, settings = {}, members = {}, digest = { enabled = true, lastSeen = now - DAY },
        bulletin = { messages = {}, seen = {} } })
D:ShowOnLogin()
local noId = { messages = { { text = "Anonymous board", author = "Off", ts = now - 5 } } }
B:OnSync({ act = "snapshot", rev = 2, data = noId })
check(#printed == 1 and printedHas("Anonymous board"), "a notice without an id is told")
B:OnSync({ act = "snapshot", rev = 3, data = { messages = { { text = "Anonymous board", author = "Off", ts = now - 5 } } } })
check(#printed == 1, "and not again when the board comes back")
D.shownThisSession, shownLines = nil, nil
D:ShowOnLogin()
check(not table.concat(shownLines or {}, "\n"):find("Anonymous board", 1, true), "nor at the next login")

-- The Activity sub-tab builds the digest for the last 7 days: every notice posted in them, told or not.
local week = D:Build(now - 7 * DAY)
check(table.concat(week, "\n"):find("Anonymous board", 1, true), "Activity still lists a notice already told")

-- At most three at login: the rest are told too, never dripped login after login.
local many = {}
for i = 1, 6 do many[i] = { id = "M" .. i, text = "N" .. i, author = "Off", ts = now - i } end
fresh({ sync = {}, digest = { enabled = false, lastSeen = now }, settings = {}, members = {},
        bulletin = { messages = many, seen = {} } })
D:ShowOnLogin()
check(#printed == 3 and printedHas("N1") and printedHas("N3") and not printedHas("N4"), "three lines, the newest")
check(#B:Unseen(now) == 0, "and the older ones are not kept for the next login")

print(string.format("bulletin-expiry: %d checks passed", checks))
