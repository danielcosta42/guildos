-- TBC raid data shown on WoW: Forever (issue #92), run against the real Core/Core.lua,
-- Core/Compat.lua, Modules/Calendar.lua and Modules/CoreManager.lua, once as each game.
--
-- The calendar offered 10, 25 or 40 with 25 as the default, so a Forever guild could not
-- plan its 20-player raid; the core screen listed TBC's raid buffs, which the site's Forever
-- catalogue leaves empty on purpose; and the default roles were TBC's tank and healer first,
-- where the site's Forever roles put damage first.
--
--   luajit -e 'ADDON="."' tools/forever-raid-data.lua
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

local function load(game)
  DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
  end
  function hooksecurefunc() end
  if game == "forever" then
    function GetBuildInfo() return "1.60.1", "70205", "", 16001 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 99
  else
    function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
  end
  function GetRealmName() return "Realm" end
  function UnitName() return "Me" end
  function GetServerTime() return 1790000000 end
  function IsInGuild() return true end
  function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
  function GetGuildInfo() return "Guild", "GM", 0 end
  C_Timer = { After = function() end, NewTicker = function() end }
  Enum = { SendAddonMessageResult = {} }
  GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
  dofile(ADDON .. "/Core/Core.lua")
  dofile(ADDON .. "/Core/Compat.lua")
  dofile(ADDON .. "/Modules/Calendar.lua")
  dofile(ADDON .. "/Modules/CoreManager.lua")
  BRutus.db = { settings = {}, cores = {} }
  BRutus.Calendar:Initialize()
  return BRutus.Calendar, BRutus.CoreManager
end

local function read(path)
  local f = assert(io.open(ADDON .. "/" .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

for _, game in ipairs({ "forever", "anniversary" }) do
  local forever = game == "forever"
  local Cal, CM = load(game)
  local default = forever and 20 or 25

  -- ── The game's raid sizes ──────────────────────────────────────────
  check(table.concat(BRutus.Client.raidSizes, ",") == (forever and "10,20,40" or "10,25,40"),
    game .. ": the calendar's sizes are the game's")
  check(BRutus.Client.defaultRaidSize == default, game .. ": the default size is the game's main raid")

  -- ── The calendar falls back to it, not to 25 ──────────────────────
  local e = Cal:Create("Raid night", 1790100000, nil, "", nil, false)
  check(e and e.size == default, game .. ": an event made without a size is " .. default)
  Cal:Update(e.id, "Raid night", 1790100000, nil, "", nil, false)
  check(e.size == default, game .. ": updating it without a size keeps " .. default)
  local web = Cal:UpsertWebRaid({ raidId = "r1", startsAt = 1790200000, title = "Site raid", members = {} })
  check(web and web.size == default, game .. ": a site raid with nobody yet is " .. default)
  BRutus.db.calendar.events.nosize = { id = "nosize", title = "Old", when = 1790100000, rsvps = {} }
  Cal:Update("nosize", "Old", 1790100000, nil, "", nil, false)
  check(BRutus.db.calendar.events.nosize.size == default, game .. ": updating an event saved without a size gives it " .. default)
  local sized = Cal:UpsertWebRaid({ raidId = "r2", startsAt = 1790200000, title = "Barrow", size = 10, members = {} })
  check(sized and sized.size == 10, game .. ": a site raid keeps the site's own size, even with nobody invitable")
  local twenty = Cal._AllianceSlotDecision({ when = 1790300000 }, 20, 1790000000)
  check(twenty == (forever and "full" or "ok"), game .. ": an event with no size is full at " .. default)
  check(CM:GetRaidSize("Main") == default, game .. ": a new core starts at the same default")

  -- ── Default roles ──────────────────────────────────────────────────
  local R = CM.CLASS_DEFAULT_ROLE
  if forever then
    check(R.WARRIOR == "mdps" and R.PALADIN == "mdps" and R.SHAMAN == "mdps" and R.DRUID == "mdps"
      and R.PRIEST == "rdps" and R.ROGUE == "mdps" and R.HUNTER == "rdps" and R.MAGE == "rdps" and R.WARLOCK == "rdps",
      "forever: every class starts on damage, as the site's Forever roles do")
  else
    check(R.WARRIOR == "tank" and R.PALADIN == "healer" and R.PRIEST == "healer" and R.SHAMAN == "healer"
      and R.DRUID == "healer" and R.HUNTER == "rdps" and R.ROGUE == "mdps",
      "anniversary: the roles are TBC's, as before")
  end
  check(CM:GetRoleForClass("WARRIOR") == R.WARRIOR, game .. ": GetRoleForClass reads the same table")

  -- ── Raid buffs ─────────────────────────────────────────────────────
  CM:Create("Main")
  BRutus.db.cores.Main.members = { a = { name = "A", class = "PRIEST", role = "healer" },
                                   b = { name = "B", class = "MAGE", role = "rdps" } }
  local comp = CM:GetComposition("Main")
  if forever then
    check(#comp.buffStatus == 0, "forever: no TBC raid buffs are listed")
  else
    check(#comp.buffStatus > 0, "anniversary: the TBC raid buffs are listed, as before")
  end
end

-- ── The screens read the game's data ─────────────────────────────────
local function code(path)
  return (read(path):gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", ""))
end
local panel = code("UI/CalendarPanel.lua")
check(panel:find("local SIZES%s*=%s*BRutus%.Client%.raidSizes"), "the calendar's size button cycles through the game's sizes")
-- No 25 left as a size anywhere in the calendar's code: every one is the game's default now.
for _, path in ipairs({ "UI/CalendarPanel.lua", "Modules/Calendar.lua", "UI/AlliancePanel.lua" }) do
  check(not code(path):find("%f[%d]25%f[%D]"), path .. " holds no 25 of its own: sizes come from the game")
end
check(read("UI/CorePanel.lua"):find('if #comp.buffStatus > 0 then%s+y = MakeSectionHeader%(rightContent, L%["Raid Buffs"%]'),
  "the core screen leaves out the Raid Buffs section when the game has none")

print(("forever-raid-data: %d checks passed"):format(checks))
