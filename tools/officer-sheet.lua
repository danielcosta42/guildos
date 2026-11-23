-- The officer's sheet and card on the roster (issue #427), run against the real Libs/LibStub.lua,
-- Libs/LibSerialize.lua, Libs/LibDeflate.lua, Core/Core.lua, Core/Compat.lua, Core/Utils.lua, Core/Data.lua,
-- Modules/CommSystem.lua, Modules/SyncService.lua, Modules/OfficerNotes.lua and UI/OfficerSheet.lua, with
-- several clients on one guild channel and the real compression and chunking between them.
--
--   * a sheet of 800 letters, several lines, reaches another officer whole, and the newer edit wins;
--   * a sheet travels only over the OFFICER addon channel: a member's client never gets a byte of it, a
--     sheet over GUILD is refused, and a client without that channel keeps its sheets to itself;
--   * a member's client keeps nothing of it, and a member cannot write one;
--   * the officers' marks (Modules/MemberMarks.lua, #429) the same: OFFICER only, refused from GUILD, kept
--     with their writer without that channel;
--   * an officer who logs in later gets it from the spaced backfill;
--   * "ON" and "OA" read as before, and "OA" never carries a sheet;
--   * the card: a main with three alts names the three in class colour with the online ones marked,
--     officers see the sheet and the notes, members do not, and a hover never reads the roster.
--
--   luajit -e 'ADDON="."' tools/officer-sheet.lua
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

local ROSTER = { { "OffA", 1 }, { "OffB", 1 }, { "OffC", 1 }, { "Mem", 5 } }
local me = "OffA"
local now = 1791000000
local afters = {}
local rosterReads = 0

strmatch = string.match
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  function f:Hide() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function GetServerTime() return now end
function GetTime() return now end
function GetLocale() return "enUS" end
time = os.time
date = os.date
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
-- A chunk goes out at once; anything later (a backfill's next envelope, a chunk's timeout) waits for runAfters.
C_Timer = { After = function(d, fn) if d < 1 then fn() else afters[#afters + 1] = fn end end,
            NewTicker = function() return { Cancel = function() end } end,
            NewTimer = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
function UnitName() return me end
function UnitLevel() return 70 end
function UnitClass() return "Warrior", "WARRIOR" end
function IsInGuild() return true end
function InCombatLockdown() return false end
function GetNumGuildMembers() rosterReads = rosterReads + 1; return #ROSTER end
function GetGuildRosterInfo(i)
  rosterReads = rosterReads + 1
  local r = ROSTER[i]
  if r then return r[1] .. "-Realm", "Rank" .. r[2], r[2], 70, "Warrior", "", "", "", true, 0, "WARRIOR" end
end
function GetGuildInfo()
  for _, r in ipairs(ROSTER) do if r[1] == me then return "Guild", "Rank", r[2] end end
end
function GuildControlGetNumRanks() return 7 end
function GuildControlGetRankName(i) return "Rank" .. (i - 1) end
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
                      PRIEST = { r = 1, g = 1, b = 1 }, ROGUE = { r = 1, g = 0.96, b = 0.41 } }

dofile(ADDON .. "/Libs/LibStub.lua")
dofile(ADDON .. "/Libs/LibSerialize.lua")
dofile(ADDON .. "/Libs/LibDeflate.lua")
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Modules/CommSystem.lua")
dofile(ADDON .. "/Modules/SyncService.lua")
dofile(ADDON .. "/Modules/OfficerNotes.lua")
dofile(ADDON .. "/Modules/MemberMarks.lua")
GuildOS.UI = GuildOS.UI or {}
dofile(ADDON .. "/UI/OfficerSheet.lua")
local CS, SS, ON, RC = GuildOS.CommSystem, GuildOS.SyncService, GuildOS.OfficerNotes, GuildOS.RosterCard
local MM = GuildOS.MemberMarks
CS.pendingMessages = {}
GuildOS.State = GuildOS.State or {}
GuildOS.State.comm = GuildOS.State.comm or {}
GuildOS.Compat.CanViewOfficerNote = function() return true end

-- Every message a client hands the comm layer, with its channel: a sheet must only ever go over OFFICER.
local LSer = LibStub("GuildOS-LibSerialize")
local sheetChannels = {}
local marksChannels = {}   -- the same for the officers' marks (#429)
do
  local realSend = CS.SendMessage
  CS.SendMessage = function(self, t, data, target, prio, kind, channel)
    if t == "SV" then
      local ok, env = LSer:Deserialize(data)
      if ok and type(env) == "table" and env.dom == "osheet" then
        local c = target and "WHISPER" or (channel or "GUILD")
        sheetChannels[c] = (sheetChannels[c] or 0) + 1
      elseif ok and type(env) == "table" and env.dom == "marks" then
        local c = target and "WHISPER" or (channel or "GUILD")
        marksChannels[c] = (marksChannels[c] or 0) + 1
      end
    end
    return realSend(self, t, data, target, prio, kind, channel)
  end
end

-- ── The clients ─────────────────────────────────────────────────────────
local clients, wire, online = {}, {}, {}
local function newClient(name)
  clients[name] = { db = { settings = { officerMaxRank = 1 }, officerNotes = {} }, seen = {}, count = 0, pending = {} }
  online[name] = true
end
local function use(name)
  local c = clients[name]
  me = name
  GuildOS.db = c.db
  SS.seenIds, SS.seenCount = c.seen, c.count
  CS.pendingMessages = c.pending
  ON._sheetBackfillAt, ON._sheetBackfilling = c.bfAt, c.bfOn
end
local function save()
  local c = clients[me]
  c.count, c.bfAt, c.bfOn = SS.seenCount, ON._sheetBackfillAt, ON._sheetBackfilling
end
-- What leaves a client: the real chunks, as the game would carry them.
GuildOS.Compat.SendAddonMessage = function(_, msg, channel, target)
  check(#msg <= 255, "every chunk fits the game's 255 bytes")
  wire[#wire + 1] = { msg = msg, channel = channel, from = me, target = target }
end
-- Who the game hands an OFFICER addon message: the ranks that hear officer chat (here the officers' rank).
local function hearsOfficer(name)
  for _, r in ipairs(ROSTER) do if r[1] == name then return r[2] <= 1 end end
  return false
end
local memberGot = {}   -- every channel a message reached the member's client by
local function flush()
  local guard = 0
  while #wire > 0 do
    guard = guard + 1
    check(guard < 200, "the channel settles")
    local batch = wire
    wire = {}
    for _, m in ipairs(batch) do
      for name in pairs(clients) do
        if online[name] and name ~= m.from and (m.channel ~= "OFFICER" or hearsOfficer(name)) then
          if name == "Mem" then memberGot[m.channel] = (memberGot[m.channel] or 0) + 1 end
          use(name)
          CS:OnMessageReceived(m.msg, m.channel, m.from .. "-Realm")
          save()
        end
      end
    end
  end
end
local function runAfters(who)
  use(who)
  while #afters > 0 do
    local fn = table.remove(afters, 1)
    fn()
  end
  save()
end
local function as(name, fn) use(name); local r = fn(); save(); return r end

local K = function(name) return GuildOS:GetPlayerKey(name, "Realm") end

-- ── 0. Pure helpers ─────────────────────────────────────────────────────
check(ON.CleanSheetText("a|cffff0000b|r\r\nc\1d  ") == "acffff0000br\nc d", "escapes and control characters go, line breaks stay")
check(ON.CleanSheetText("a\n\n\n\n\n\nb") == "a\n\n\nb", "no more than three line breaks in a row")
local han = string.rep("\228\184\173", 1200)   -- 1200 letters of Han, three bytes each
check(GuildOS:Utf8Len(ON.CleanSheetText(han)) == ON.SHEET_MAX and #ON.CleanSheetText(han) == 3 * ON.SHEET_MAX,
  "a sheet is cut at SHEET_MAX letters, never in the middle of one")
check(ON.SheetWins(5, { text = "a" }, 4, { text = "b" }) and not ON.SheetWins(3, { text = "a" }, 4, { text = "b" }),
  "the higher revision wins")
check(ON.SheetWins(4, { text = "a" }, 4, { text = "b" }) ~= ON.SheetWins(4, { text = "b" }, 4, { text = "a" }),
  "at one revision, two sheets settle the same way everywhere")
local head, more = ON.SheetHead("one\ntwo\nthree\nfour\nfive", 4, 100)
check(head == "one\ntwo\nthree\nfour" and more, "the card's head: the first lines, and that there is more")
local head2, more2 = ON.SheetHead("short", 4, 100)
check(head2 == "short" and not more2, "a short sheet is whole on the card")

-- ── 1. 800 letters from A reach B whole ─────────────────────────────────
for _, n in ipairs({ "OffA", "OffB", "OffC", "Mem" }) do newClient(n) end
online.OffC = false   -- logs in later
for _, n in ipairs({ "OffA", "OffB", "OffC", "Mem" }) do as(n, function() SS:Initialize(); ON:Initialize() end) end

-- Text that does not compress away: 16 lines of pseudo-random letters.
local seed, lines = 7, {}
local function letter() seed = (seed * 1103515245 + 12345) % 2147483648; return string.char(97 + seed % 26) end
for i = 1, 16 do
  local w = {}
  for j = 1, 40 do w[j] = letter() end
  lines[i] = string.format("L%02d ", i) .. table.concat(w)
end
local text800 = table.concat(lines, "\n")
text800 = text800 .. string.rep("z", 800 - #text800)
check(#text800 == 800, "the test sheet is 800 letters")
local MAIN = K("Mem")
check(as("OffA", function() return ON:SetSheet(MAIN, text800) end), "officer A writes the sheet")
local chunks = #wire
check(chunks > 1, "the sheet goes out in several chunks (" .. chunks .. ")")
flush()
local b = as("OffB", function() return ON:GetSheet(MAIN) end)
check(b and b.text == text800 and b.author == "OffA", "officer B holds the whole 800 letters, line breaks and all")
check(clients.Mem.db.officerNotes[MAIN] == nil, "a member's client keeps nothing of it")
check(as("Mem", function() return ON:GetSheet(MAIN) end) == nil, "and a member reads nothing")

-- ── 2. The newer edit wins ──────────────────────────────────────────────
local oldA = { k = MAIN, x = text800, a = "OffA", t = now, r = clients.OffA.db.officerNotes[MAIN].sheet.rev }
now = now + 60
check(as("OffB", function() return ON:SetSheet(MAIN, "B's newer text") end), "officer B edits it later")
flush()
check(as("OffA", function() return ON:GetSheet(MAIN).text end) == "B's newer text", "A's copy takes B's newer edit")
as("OffA", function() SS:Publish(ON.SHEET_DOMAIN, "set", { sheets = { oldA } }, { priority = "BULK" }) end)
flush()
check(as("OffB", function() return ON:GetSheet(MAIN).text end) == "B's newer text", "an older copy sent again never rolls it back")

-- ── 3. A member cannot write one ────────────────────────────────────────
as("Mem", function() SS:Publish(ON.SHEET_DOMAIN, "set", { sheets = { { k = MAIN, x = "forged", a = "Mem", t = now, r = now + 999 } } }) end)
flush()
check(as("OffA", function() return ON:GetSheet(MAIN).text end) == "B's newer text", "a member's sheet is dropped by every officer")
check(not as("Mem", function() return ON:SetSheet(MAIN, "mine") end), "and a member's client refuses to write one")

-- ── 4. An officer who logs in later gets it from the backfill ───────────
as("OffA", function() ON:SetSheet(K("OffB"), "second") ; ON:SetSheet(K("OffA"), "third") end)
flush()
online.OffC = true
wire = {}
as("OffB", function() ON:BackfillSheets() end)
check(#afters >= 1, "a backfill of three sheets sends the third one later, spaced (#324)")
flush()
runAfters("OffB")
flush()
check(as("OffC", function() return ON:GetSheet(MAIN).text end) == "B's newer text"
  and as("OffC", function() return ON:GetSheet(K("OffA")).text end) == "third", "officer C gets every sheet")
wire = {}
as("OffB", function() ON:BackfillSheets() end)
check(#wire == 0, "a second backfill within ten minutes sends nothing")
as("OffB", function() ON:BackfillSheets(true) end)
check(#wire > 0, "a /gos sync sends them again")
flush(); runAfters("OffB"); flush()

-- ── 4b. Only the officers' channel carries a sheet ───────────────────────
check((sheetChannels.OFFICER or 0) > 0 and sheetChannels.GUILD == nil and sheetChannels.WHISPER == nil,
  "every sheet envelope went over OFFICER, none over GUILD or a whisper")
check(memberGot.OFFICER == nil, "the member's client never got a single OFFICER message")
-- A sheet over GUILD, even in an officer's name, is refused.
local env = { v = 2, id = "FEED0001", av = "test", dom = "osheet", act = "set", ts = now, pv = 1, src = "local",
              data = { sheets = { { k = MAIN, x = "over guild", a = "OffA", t = now, r = now + 99999 } } } }
as("OffA", function() CS:SendMessage("SV", LSer:Serialize(env)) end)
flush()
check(as("OffB", function() return ON:GetSheet(MAIN).text end) == "B's newer text", "a sheet over GUILD is refused")
-- A client without the OFFICER channel (WoW: Forever until checked): the sheet stays there.
local realChan = GuildOS.Compat.OfficerAddonChannel
GuildOS.Compat.OfficerAddonChannel = function() return nil end
wire = {}
check(as("OffA", function() return ON:SetSheet(K("OffC"), "local only") end), "without OFFICER the sheet is still saved")
as("OffA", function() ON:BackfillSheets(true) end)
check(#wire == 0 and #afters == 0, "and nothing is sent, nor any backfill")
check(as("OffA", function() return ON:GetSheet(K("OffC")).text end) == "local only", "it stays on that client")
GuildOS.Compat.OfficerAddonChannel = realChan

-- ── 5. "ON" and "OA" as before; "OA" never carries a sheet ──────────────
local LS = LibStub("GuildOS-LibSerialize")
as("OffA", function() ON:AddNote(MAIN, "Dated note") end)
check(#wire >= 1, "a dated note still goes out")
flush()
check(as("OffB", function() return ON:GetNotes(MAIN)[1].text end) == "Dated note", "\"ON\" reads as before")
-- A client before #427 sends ON with { target, note }: read the same.
local oldOn = LS:Serialize({ target = MAIN, note = { text = "Old client note", author = "OffC", timestamp = now - 5 } })
as("OffB", function() CS.SendMessage(CS, "ON", oldOn) end)
flush()
local function hasNote(who, t)
  for _, n in ipairs(as(who, function() return ON:GetNotes(MAIN) end)) do if n.text == t then return true end end
  return false
end
check(hasNote("OffA", "Old client note") and not hasNote("Mem", "Old client note"), "a note from an old client is read, by officers only")
local sentOA
local realSend = CS.SendMessage
CS.SendMessage = function(self, t, data, ...) if t == "OA" then sentOA = data end return realSend(self, t, data, ...) end
as("OffA", function() ON:BroadcastAllNotes() end)
CS.SendMessage = realSend
local okOA, oa = LS:Deserialize(sentOA)
check(okOA and oa[MAIN] and oa[MAIN].notes and oa[MAIN].sheet == nil, "\"OA\" carries the notes and no sheet")
flush()
local forged = LS:Serialize({ [MAIN] = { notes = {}, tags = {}, sheet = { text = "from OA", rev = now + 9999 } } })
as("OffC", function() ON:HandleAllIncoming(forged) end)
check(as("OffC", function() return ON:GetSheet(MAIN).text end) == "B's newer text", "a sheet inside \"OA\" is never taken")

-- ── 6. The card ─────────────────────────────────────────────────────────
local links = { [K("AltX")] = MAIN, [K("AltY")] = MAIN, [K("AltZ")] = MAIN }
local idx = RC.NewIndex(links)
RC.IndexRow(idx, MAIN, "Mem", "WARRIOR", true)
RC.IndexRow(idx, K("AltX"), "AltX", "MAGE", true)
RC.IndexRow(idx, K("AltY"), "AltY", "PRIEST", false)
RC.IndexRow(idx, K("AltZ"), "AltZ", "ROGUE", true)
local al = RC.AltLines(idx, MAIN)
check(al and #al == 4 and al[1] == string.format("Alts (%d):", 3), "a main with three alts says three")
local function hex(c) return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
check(al[2]:find(hex(RAID_CLASS_COLORS.MAGE) .. "AltX", 1, true) and al[2]:find("(online)", 1, true), "AltX in the mage's colour, online")
check(al[3]:find(hex(RAID_CLASS_COLORS.PRIEST) .. "AltY", 1, true) and not al[3]:find("(online)", 1, true), "AltY in the priest's colour, not online")
check(al[4]:find(hex(RAID_CLASS_COLORS.ROGUE) .. "AltZ", 1, true) and al[4]:find("(online)", 1, true), "AltZ in the rogue's colour, online")
local alt = RC.AltLines(idx, K("AltY"))
check(alt[1]:find("Mem", 1, true) and #alt == 4 and alt[2]:find("Other alts", 1, true), "an alt names its main and the main's other alts")

local function card(who, data)
  use(who)
  local out = {}
  local tip = { AddLine = function(_, t) out[#out + 1] = t end }
  rosterReads = 0
  RC:AddLines(tip, data, idx)
  save()
  return table.concat(out, "\n"), rosterReads
end
local data = { key = MAIN, officerNote = "game note" }
local offCard, reads = card("OffA", data)
check(reads == 0, "a hover never reads the roster")
check(offCard:find("Officer sheet", 1, true) and offCard:find("B's newer text", 1, true), "an officer's card starts the sheet")
check(offCard:find("Dated note", 1, true) and offCard:find("Officer note: game note", 1, true), "and shows the notes and the game's officer note")
check(offCard:find("AltX", 1, true), "and the alts")
local memCard = card("Mem", data)
check(memCard:find("AltX", 1, true) and not memCard:find("Officer sheet", 1, true) and not memCard:find("Dated note", 1, true)
  and not memCard:find("game note", 1, true), "a member's card shows the alts and nothing of the officers'")
-- The birthday hook (#428): only when the module is there.
GuildOS.Birthdays = { TooltipLine = function(_, key) return key == MAIN and "Birthday: 12/03" or nil end }
check((card("Mem", data)):find("Birthday: 12/03", 1, true), "the birthday line shows when its module gives one")
GuildOS.Birthdays = nil

-- The source: the roster builds the index once per refresh, and the card reads it.
local function src(p) local f = assert(io.open(ADDON .. "/" .. p, "rb")); local s = f:read("*a"); f:close(); return s end
local roster = src("UI/RosterFrame.lua")
check(roster:find("GuildOS.RosterCard.NewIndex(GuildOS.db.altLinks)", 1, true)
  and roster:find("RosterCard:AddLines(tip, data, row.host and row.host.tipIndex)", 1, true), "the roster indexes once and the card reads it")
check(roster:find('key = "joined"', 1, true), "the roster has a Joined column")
local export = src("Modules/CompanionExport.lua")
check(not export:find("officerNotes", 1, true) and not export:find("GetSheet", 1, true) and not export:find("OfficerNotes", 1, true),
  "the sheet is never exported to the site")

-- ── 7. The officers' marks (#429) go the same way ───────────────────────
for _, n in ipairs({ "OffA", "OffB", "OffC", "Mem" }) do as(n, function() MM:Initialize() end) end
memberGot = {}
check(as("OffA", function() return MM:SetNick(MAIN, "Big Mem") end), "officer A gives the member a nickname")
check(as("OffA", function() return MM:SetSafe(K("OffB"), true) end), "and marks B safe")
flush()
check(as("OffB", function() return MM:Nick(MAIN) end) == "Big Mem" and as("OffC", function() return MM:IsMarkedSafe(K("OffB")) end),
  "the other officers get the marks")
check((marksChannels.OFFICER or 0) > 0 and marksChannels.GUILD == nil and marksChannels.WHISPER == nil,
  "every marks envelope went over OFFICER, none over GUILD or a whisper")
check(memberGot.OFFICER == nil and memberGot.GUILD == nil, "the member's client got no marks envelope at all")
check(clients.Mem.db.memberMarks == nil or next(clients.Mem.db.memberMarks.nick or {}) == nil, "and keeps none")
wire = {}
as("OffA", function() MM:Backfill() end)
check(#wire > 0, "the login backfill goes out too")
flush()
check(memberGot.OFFICER == nil and memberGot.GUILD == nil and marksChannels.GUILD == nil, "over OFFICER only")
-- Marks over GUILD, even in an officer's name, are refused.
local menv = { v = 2, id = "FEED0002", av = "test", dom = "marks", act = "set", ts = now, pv = 1, src = "local",
               data = { items = { { s = "nick", k = MAIN, v = "Forged", t = now + 100, b = "OffA" } } } }
as("OffA", function() CS:SendMessage("SV", LSer:Serialize(menv)) end)
flush()
check(as("OffB", function() return MM:Nick(MAIN) end) == "Big Mem", "marks over GUILD are refused")
-- Without the OFFICER channel the marks stay on the writer's client, and nothing is sent.
GuildOS.Compat.OfficerAddonChannel = function() return nil end
wire = {}
check(as("OffA", function() return MM:SetNick(K("OffC"), "Cee") end), "without OFFICER a nickname is still saved")
as("OffA", function() MM:Backfill() end)
check(#wire == 0 and as("OffA", function() return MM:Nick(K("OffC")) end) == "Cee", "kept here, nothing sent")
GuildOS.Compat.OfficerAddonChannel = realChan

check(memberGot.OFFICER == nil, "after everything, the member's client still never got an OFFICER message")
print(string.format("officer-sheet: %d checks passed", checks))
