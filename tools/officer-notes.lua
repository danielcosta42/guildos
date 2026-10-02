-- Officer notes on WoW: Forever (issue #49), run against the real Core/Core.lua,
-- Core/Compat.lua and Core/Utils.lua under a stubbed guild roster.
--
-- Forever's names have a surname. `/guildos note <name> <text>` read the name as the
-- first word, so "Lethaniel Blightwood text" filed "Blightwood text" under "Lethaniel",
-- a key no sheet reads. And Forever's popup keeps its edit box at `EditBox` /
-- `GetEditBox()`, where `editBox` is nil, so the raider-note popup saved nothing.
--
--   luajit -e 'ADDON="."' tools/officer-notes.lua
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

-- ── The client the files need while they load ───────────────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.60.1", "70124", "", 16001 end
function GetRealmName() return "Classic Beta PvE 2" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }

dofile(ADDON .. "/Core/Core.lua")
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Utils.lua")

local ROSTER = {}
function GetNumGuildMembers() return #ROSTER end
function GetGuildRosterInfo(i) return ROSTER[i] end

-- ── Forever: a name is two words ────────────────────────────────────────
ROSTER = { "Lethaniel Blightwood", "Bob Costa", "Quux" }
local name, text = BRutus:SplitNameAndText("Lethaniel Blightwood Late to raid twice")
check(name == "Lethaniel Blightwood" and text == "Late to raid twice",
      "a two-word name on the roster is the name, and the rest is the note")
name, text = BRutus:SplitNameAndText("Quux brings flasks")
check(name == "Quux" and text == "brings flasks", "a one-word name still reads as before")
name, text = BRutus:SplitNameAndText("Nobody There text")
check(name == "Nobody" and text == "There text", "two words nobody on the roster has: the first word, as before")
check(BRutus:SplitNameAndText("Lethaniel Blightwood") == nil, "a name with no note is no note")

local key, shown = BRutus:RosterKey("Lethaniel Blightwood")
check(key == BRutus:GetPlayerKey("Lethaniel Blightwood", "Classic Beta PvE 2") and shown == "Lethaniel Blightwood",
      "the key is the roster frame's own: the roster name, on the player's realm")
check(BRutus:RosterKey("Lethaniel") == nil, "the first name alone is nobody")

-- ── Anniversary: Name-Realm on the roster ───────────────────────────────
ROSTER = { "Ana-Firemaw", "Bob-Spineshatter" }
name, text = BRutus:SplitNameAndText("Bob great tank")
check(name == "Bob" and text == "great tank", "Anniversary: the first word is the name")
key = BRutus:RosterKey("Bob")
check(key == BRutus:GetPlayerKey("Bob", "Spineshatter"), "a cross-realm member keeps the realm the roster gives")

-- ── The popup's edit box, on both clients ───────────────────────────────
local classicBox, foreverBox = {}, {}
check(BRutus.Compat.PopupEditBox({ editBox = classicBox }) == classicBox, "Anniversary's popup: editBox")
check(BRutus.Compat.PopupEditBox({ EditBox = foreverBox, GetEditBox = function(self) return self.EditBox end }) == foreverBox,
      "Forever's popup: GetEditBox()")
check(BRutus.Compat.PopupEditBox(nil) == nil, "no dialog, no box, no raise")

print(("officer-notes: %d checks passed"):format(checks))
