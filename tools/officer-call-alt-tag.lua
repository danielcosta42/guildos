-- Calling the officers in guild chat (issue #266) and the short alt tag (issue #269), run against
-- the real Modules/Mentions.lua, Modules/AltRoster.lua and Modules/ChatTweaks.lua.
--
-- #266: somebody writes "officer" in guild chat and whoever has an officer rank gets the same alert
-- as their own name, in the client's language and in English. Nobody else does, and officer chat
-- (where every reader is an officer already) never does.
-- #269: Guild Roster Manager's tag, "Justice[Floyd]" on an alt and "Justice[M]" on a main with
-- alts, as an option next to the "(alt of Floyd)" the addon already writes.
--
--   luajit -e 'ADDON="."' tools/officer-call-alt-tag.lua
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

function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetLocale() return "enUS" end
function GetServerTime() return 1794000000 end
local handler
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) handler = fn end
  return f
end

local isOfficer = true
local printed, recorded = {}, {}
local LOCAL = {}
GuildOS = {
  L = setmetatable({}, { __index = function(_, k) return LOCAL[k] or k end }),
  Compat = {
    RegisterEvent = function(f, ev) f:RegisterEvent(ev) end,
    IsSecret = function() return false end,
    PlayerName = function() return "Zero Lima" end,
    After = function() end,
  },
  db = {},
}
function GuildOS:IsOfficer() return isOfficer end
function GuildOS:Print(m) printed[#printed + 1] = m end
function GuildOS:DeepCopy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

dofile(ADDON .. "/Modules/Mentions.lua")
dofile(ADDON .. "/Modules/AltRoster.lua")
dofile(ADDON .. "/Modules/ChatTweaks.lua")
local M, A, CT = GuildOS.Mentions, GuildOS.AltRoster, GuildOS.ChatTweaks

-- ── #266: the words ──────────────────────────────────────────────────────
check(M.DEFAULTS.officerCall == true, "calling the officers alerts officers by default")
local words = M:_OfficerWords()
local has = {}
for _, w in ipairs(words) do has[w] = true end
check(has.officer and has.officers, "English is always heard: officer and officers")
LOCAL["officer, officers"] = "oficial, oficiais"
has = {}
for _, w in ipairs(M:_OfficerWords()) do has[w] = true end
check(has.oficial and has.oficiais and has.officer, "the client's language adds its own words, English stays")
LOCAL["officer, officers"] = nil
check(M:_OfficerCall("we need an officer to invite", words) == "officer", "a call for an officer is heard")
check(M:_OfficerCall("OFFICERS, anyone online?", words) == "officers", "in capitals and with punctuation too")
check(M:_OfficerCall("officerless guilds are sad", words) == nil, "a word that only starts like it is not a call")
check(M:_OfficerCall("raid tonight", words) == nil, "an ordinary line is not a call")

-- ── #266: who hears it ───────────────────────────────────────────────────
M._cd = {}
M._Record = function(_, term, sender) recorded[#recorded + 1] = { term = term, sender = sender } end
GuildOS.db.mentions = { enabled = true, ownName = true, watchWords = {}, sound = false, guild = true, officer = true,
  officerCall = true, log = {} }
M:_SetupHook()
handler(nil, "CHAT_MSG_GUILD", "can an officer invite me?", "Justice-Realm")
check(#recorded == 1 and recorded[1].term == "officer" and recorded[1].sender == "Justice", "an officer hears the call")
isOfficer = false
handler(nil, "CHAT_MSG_GUILD", "officer please", "Floyd-Realm")
check(#recorded == 1, "a member who is no officer does not")
isOfficer = true
GuildOS.db.mentions.officerCall = false
handler(nil, "CHAT_MSG_GUILD", "officer please", "Ana-Realm")
check(#recorded == 1, "nor an officer who turned it off")
GuildOS.db.mentions.officerCall = true
handler(nil, "CHAT_MSG_OFFICER", "the officer meeting is at 9", "Bia-Realm")
check(#recorded == 1, "officer chat is read by officers only: a call there calls nobody")
handler(nil, "CHAT_MSG_GUILD", "officer?", "Zero Lima-Realm")
check(#recorded == 1, "your own line never alerts you")
handler(nil, "CHAT_MSG_GUILD", "hey Zero, are you an officer?", "Caio-Realm")
check(#recorded == 2 and recorded[2].term == "Zero", "your own name still comes first")

-- ── #269: the short tag ──────────────────────────────────────────────────
local links = { ["Floyd Alt-R"] = "Floyd-R", ["Floyd Bank-R"] = "Floyd-R" }
check(A:ShortTag("Floyd Alt-R", links) == "[Floyd]", "an alt carries its main's name in brackets")
check(A:ShortTag("Floyd-R", links) == "[M]", "a main with alts carries [M]")
check(A:ShortTag("Solo-R", links) == nil, "somebody with no alts carries nothing")
check(A:HasAlts("Floyd-R", links) and not A:HasAlts("Solo-R", links), "a main has alts, a solo player has none")
LOCAL["[M]"] = "[P]"
check(A:ShortTag("Floyd-R", links) == "[P]", "the main's letter follows the client's language")
LOCAL["[M]"] = nil

check(CT.DEFAULTS.altShort == false, "the long tag stays the default: nobody's chat changes on its own")
local long = CT:_BuildPrefix({ altTag = "alt of Floyd", shortTag = "[Floyd]" }, { altTag = true, altShort = false })
check(long:find("alt of Floyd", 1, true) and not long:find("[Floyd]", 1, true), "the long tag, as before")
local short = CT:_BuildPrefix({ altTag = "alt of Floyd", shortTag = "[Floyd]" }, { altTag = true, altShort = true })
check(short:find("[Floyd]", 1, true) and not short:find("alt of", 1, true), "the short tag replaces it")
local main = CT:_BuildPrefix({ shortTag = "[M]" }, { altTag = true, altShort = true })
check(main:find("[M]", 1, true), "a main shows [M] with the short tag")
check(CT:_BuildPrefix({ shortTag = "[M]" }, { altTag = true, altShort = false }) == "", "and nothing with the long one, as before")
check(CT:_BuildPrefix({ shortTag = "[M]" }, { altTag = false, altShort = true }) == "", "the alt tag switched off hides both")

-- ── The words the shipped languages add (review) ─────────────────────
-- In Portuguese, Spanish and Italian the word for officer is also "official": "o site oficial" would
-- ring every officer of the guild. Those languages listen for the English words only.
for _, lang in ipairs({ "ptBR", "esES", "itIT", "deDE", "frFR", "ruRU" }) do
  local raw = {}
  GuildOS.L = setmetatable({}, { __newindex = function(_, k, v) raw[k] = v end, __index = function(_, k) return raw[k] or k end })
  function GetLocale() return lang end
  dofile(ADDON .. "/Locales/" .. lang .. ".lua")
  L = GuildOS.L
  local ws = {}
  for w in tostring(raw["officer, officers"] or ""):gmatch("[^,]+") do ws[#ws + 1] = strtrim(w):lower() end
  for _, w in ipairs(ws) do
    check(not ({ oficial = true, oficiais = true, oficiales = true, ufficiale = true, ufficiali = true })[w],
      lang .. ": no word that also means official (" .. w .. ")")
  end
  check(#ws > 0, lang .. ": the line is there")
end
function GetLocale() return "enUS" end

print("officer-call-alt-tag: " .. checks .. " checks passed")
