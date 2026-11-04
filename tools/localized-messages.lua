-- Localized system messages read back into their arguments (issue #160), run against the real
-- Core/Utils.lua and Modules/RosterLog.lua.
--
-- A client's global strings are format strings, and German numbers its arguments:
-- "%1$s wurde von %2$s aus der Gilde geworfen." The roster log turned only "%s" into a capture,
-- so "%1$s" became "%1%$s", and "%1" in a Lua pattern is a back-reference to a capture that does
-- not exist: "invalid capture index" on every system message, a player going offline included.
-- A language may also put the arguments in another order, so they are read back by their number.
--
--   luajit -e 'ADDON="."' tools/localized-messages.lua
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

GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
dofile(ADDON .. "/Core/Utils.lua")
dofile(ADDON .. "/Modules/RosterLog.lua")
local R = GuildOS.RosterLog
local M = function(msg, fmt) return GuildOS:MatchFormat(msg, fmt) end

-- The reader itself.
local a = M("Alice has been kicked out of the guild by Bob.", "%s has been kicked out of the guild by %s.")
check(a and a[1] == "Alice" and a[2] == "Bob", "English: the arguments in order")
a = M("Alice wurde von Bob aus der Gilde geworfen.", "%1$s wurde von %2$s aus der Gilde geworfen.")
check(a and a[1] == "Alice" and a[2] == "Bob", "German: numbered arguments")
a = M("Bob hat Alice zum Offizier befördert.", "%2$s hat %1$s zum %3$s befördert.")
check(a and a[1] == "Alice" and a[2] == "Bob" and a[3] == "Offizier", "a language that says them in another order gives them back by number")
a = M("Alice würfelt. Ergebnis: 57 (1-100)", "%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)")
check(a and a[1] == "Alice" and a[2] == "57" and a[3] == "1" and a[4] == "100", "numbered numbers, as a roll is written")
a = M("Alice rolls 57 (1-100).", "%s rolls %d (%d-%d).")
check(a and a[1] == "Alice" and a[2] == "57" and a[4] == "100", "the format's own ( ) . - are text, not pattern")
check(M("Alice rolls 57 (1-100)!", "%s rolls %d (%d-%d).") == nil, "and the dot is a dot, not any character")
check(M("Alice ist jetzt offline.", "%1$s wurde von %2$s aus der Gilde geworfen.") == nil, "another message is nil, not an error")
check(M("x", nil) == nil and M(nil, "%s") == nil, "nothing to read is nil")

-- The roster log, on a German client: the line of the report itself.
ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
ERR_GUILD_LEAVE_S = "%s hat die Gilde verlassen."
ERR_GUILD_REMOVE_SS = "%1$s wurde von %2$s aus der Gilde geworfen."
ERR_GUILD_PROMOTE_SSS = "%1$s hat %2$s zum %3$s befördert."
ERR_GUILD_DEMOTE_SSS = "%1$s hat %2$s zum %3$s degradiert."
local ok, evt = pcall(R._ParseSystem, R, "HXYXYXdo D*****da ist jetzt offline.")
check(ok, "the report's own line no longer raises: " .. tostring(evt))
check(evt == nil, "and going offline is nobody's kick")
evt = R:_ParseSystem("Alice-Firemaw wurde von Bob aus der Gilde geworfen.")
check(evt and evt.action == "kick" and evt.target == "Alice" and evt.author == "Bob", "a German kick: who, and by whom")
evt = R:_ParseSystem("Bob hat Alice zum Offizier befördert.")
check(evt and evt.action == "promote" and evt.author == "Bob" and evt.target == "Alice" and evt.detail == "Offizier", "a German promotion")
evt = R:_ParseSystem("Carla ist der Gilde beigetreten.")
check(evt and evt.action == "join" and evt.target == "Carla", "a German join")

-- And on an English client, as before.
ERR_GUILD_JOIN_S = "%s has joined the guild."
ERR_GUILD_LEAVE_S = "%s has left the guild."
ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."
evt = R:_ParseSystem("Alice has been kicked out of the guild by Bob.")
check(evt and evt.action == "kick" and evt.target == "Alice" and evt.author == "Bob", "an English kick")
evt = R:_ParseSystem("Bob has demoted Alice to Initiate.")
check(evt and evt.action == "demote" and evt.author == "Bob" and evt.target == "Alice" and evt.detail == "Initiate", "an English demotion")
check(R:_ParseSystem("Alice has come online.") == nil, "an online notice is nothing")

-- ── The game's own strings, build 1.60.1.70707, with their grammar (issue #106) ──
local KO_ROLL = "%s님이 주사위를 굴려 %d|1이;가; 나왔습니다. (%d-%d)"
a = M("철수님이 주사위를 굴려 57이 나왔습니다. (1-100)", KO_ROLL)
check(a and a[1] == "철수" and a[2] == "57" and a[3] == "1" and a[4] == "100", "koKR: a roll, whichever particle the number took")
a = M("철수님이 주사위를 굴려 100가 나왔습니다. (1-100)", KO_ROLL)
check(a and a[2] == "100", "koKR: the other particle too")
a = M("영희가 철수를 길드에서 추방했습니다.", "%2$s|1이;가; %1$s|1을;를; 길드에서 추방했습니다.")
check(a and a[1] == "철수" and a[2] == "영희", "koKR: a kick, the names without their particles")
a = M("가가가 나나를 길드에서 추방했습니다.", "%2$s|1이;가; %1$s|1을;를; 길드에서 추방했습니다.")
check(a and a[1] == "나나" and a[2] == "가가", "koKR: a name ending like a particle loses only the particle")
a = M("철수님이 영희님의 등급을 부관으로 올렸습니다.", "%s님이 %s님의 등급을 %s|1으로;로; 올렸습니다.")
check(a and a[1] == "철수" and a[2] == "영희" and a[3] == "부관", "koKR: a promotion, the rank without its particle")
a = M("Ольга исключает из гильдии Бориса.", "%2$s исключает из гильдии |3-3(%1$s).")
check(a and a[1] == "Бориса" and a[2] == "Ольга", "ruRU: a declined name is read as the game wrote it")
a = M("Ольга производит Бориса в звание \"Рыцарь\".", "%s производит |3-3(%s) в звание \"%s\".")
check(a and a[1] == "Ольга" and a[2] == "Бориса" and a[3] == "Рыцарь", "ruRU: a promotion")
a = M("Alice a rétrogradé Bob au grade d'Initié.", "%s a rétrogradé %s au grade |2 %s.")
check(a and a[1] == "Alice" and a[2] == "Bob" and a[3] == "Initié", "frFR: a demotion, the rank without d'")
a = M("Alice a rétrogradé Bob au grade de Recrue.", "%s a rétrogradé %s au grade |2 %s.")
check(a and a[3] == "Recrue", "frFR: and without de")
a = M("철수掷出57（1-100）", "%s掷出%d（%d-%d）")
check(a and a[1] == "철수" and a[2] == "57", "zhCN: a roll, in full-width brackets")
a = M("Alice würfelt. Ergebnis: 57 (1-100)", "%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)")
check(a and a[1] == "Alice", "deDE: a roll, numbered")
check(M("Material für die Schmiede abgeschlossen.", "%1$s wurde von %2$s aus der Gilde geworfen.") == nil,
  "deDE: the quest line of issue #118 is no guild message")

-- ── Dates: the order is the client language's (issue #170) ────────────────
date = os.date
local LAUNCH = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
for lang, want in pairs({ ptBR = "04/11", deDE = "04/11", enGB = "04/11", enUS = "11/04", koKR = "11/04", zhTW = "11/04" }) do
  GetLocale = function() return lang end
  check(GuildOS:DateText(LAUNCH) == want, lang .. ": " .. GuildOS:DateText(LAUNCH))
  check(GuildOS:DateText(LAUNCH, "/%Y") == want .. "/2026", lang .. ": what comes after it follows")
end

print(("localized-messages: %d checks passed"):format(checks))
