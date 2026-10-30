-- Shipping with no client to try it on (issue #232), run against the real Core/Core.lua: what is off
-- until tested stays off for whoever has not chosen, a choice is kept, and a module that is off never
-- starts. The list is in the code, so one release turns it on for everybody who never chose.
--
--   luajit -e 'ADDON="."' tools/launch-flags.lua
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

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  function f:Hide() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "1.15.8", "70009", "", 11508 end
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")

local function fresh(modules) GuildOS.db = { settings = { modules = modules } } end

-- ── Nobody chose: off ───────────────────────────────────────────────
fresh({})
check(not GuildOS:IsFeatureEnabled("journal"), "the journal is off until tested")
check(not GuildOS:IsFeatureEnabled("founding"), "and so is the founding")
check(GuildOS:IsFeatureEnabled("raidTracker"), "everything else stays as it was: on")

GuildOS.db = nil
check(not GuildOS:IsFeatureEnabled("journal") and GuildOS:IsFeatureEnabled("raidTracker"), "before the db exists too, the same answer")
fresh({})

-- ── A choice is kept, both ways ─────────────────────────────────────
GuildOS:SetFeatureEnabled("journal", true)
check(GuildOS:IsFeatureEnabled("journal"), "switched on in Settings, it is on")
check(GuildOS.db.settings.modules.journal == true, "and the choice is what gets saved")
GuildOS:SetFeatureEnabled("journal", false)
check(not GuildOS:IsFeatureEnabled("journal"), "switched off again, it is off")
check(GuildOS.db.settings.modules.founding == nil, "nothing was saved for what nobody touched, so a release can still turn it on")

-- ── A module that is off does not start ─────────────────────────────
local started = 0
GuildOS.Journal = { Initialize = function() started = started + 1 end }
fresh({})
check(GuildOS:StartModule({ "Journal", feature = "journal" }) == false and started == 0, "off: never started")
fresh({ journal = true })
check(GuildOS:StartModule({ "Journal", feature = "journal" }) and started == 1, "on: started")

-- ── The real start list asks for it, and the list holds only these ──
local f = assert(io.open(ADDON .. "/Core/Core.lua", "rb"))
local source = f:read("*a")
f:close()
check(source:find('{ "Journal", feature = "journal" }', 1, true), "the journal's start asks the switch")
check(source:find('{ "DungeonLog", feature = "journal" }', 1, true), "the dungeons go with it: they write into the journal")
check(source:find('{ "Founding", feature = "founding" }', 1, true), "the founding's start asks the switch")

print("launch-flags: " .. checks .. " checks passed")
