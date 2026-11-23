-- The screens reviewed in #371 draw their parts through the shared components, so they look alike and
-- stay that way. A screen that builds its own field, takes the Blizzard one, or paints text gold fails
-- here. Gold is the identity's selection, focus, primary-button and active-tab colour, not a text one:
-- a selected button gets it through UI:SetSelected, a focused field through UI:CreateInput.
--
-- The Roster tab, the Now tab, the footer and the member card are redesigned next and are not listed
-- yet; add a file here once its screen is converted.
--
--   luajit -e 'ADDON="."' tools/visual-fundamentals.lua
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

local FILES = {
  "UI/CommunityPanel.lua", "UI/CalendarPanel.lua", "UI/JournalPanel.lua", "UI/AchievementsPanel.lua",
  "Modules/Bulletin.lua", "Modules/Polls.lua", "Modules/CallToArms.lua",
  "UI/FeaturePanels.lua", "Modules/RecruitScanner.lua", "Modules/RecruitmentSystem.lua", "UI/RecruitBeacon.lua",
  "UI/LootWindow.lua", "Modules/LootMaster.lua", "UI/PointsPanel.lua", "UI/CorePanel.lua", "UI/AuditPanel.lua",
  "UI/RaiderPanel.lua", "UI/RaidToolsPanel.lua", "UI/LootCouncil.lua",
  "UI/GroupsPanel.lua", "UI/AlliancePanel.lua", "UI/ManagementPanel.lua", "UI/WebPanel.lua",
  "UI/RaidPlanPanel.lua", "UI/ProfessionsPanel.lua", "UI/RecipesPanel.lua", "UI/CraftFinder.lua",
  "UI/ModAlerts.lua", "UI/RemindPanel.lua",
}

-- Each rule: a Lua pattern a line must not match, and what it means.
local RULES = {
  { "InputBoxTemplate", "takes the Blizzard field (UI:CreateInput)" },
  { 'CreateFrame%(%s*"EditBox"', "builds its own field (UI:CreateInput)" },
  { "SetTextColor%(%s*C%.gold%.", "paints text gold" },
  { "SetTextColor%(%s*C%.accent", "paints text gold" },
  { "CreateText%(.-C%.gold%.r", "creates gold text" },
  { "CreateText%(.-C%.accent", "creates gold text" },
  { "|c[fF][fF][fF][fF][dD][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", "colours text gold inline" },
  { "|c[fF][fF][dD]9[aA]94[fF]", "colours text gold inline" },
}

local hits = {}
for _, rel in ipairs(FILES) do
  local fh = io.open(ADDON .. "/" .. rel, "rb")
  check(fh ~= nil, rel .. " exists")
  local n = 0
  for line in fh:lines() do
    n = n + 1
    local code = line:gsub("%-%-.*$", "")   -- a comment may name what it replaced
    if code:find(":Print%(") then code = "" end   -- a line printed to chat is not a screen part
    for _, rule in ipairs(RULES) do
      if code:find(rule[1]) then hits[#hits + 1] = ("%s:%d %s"):format(rel, n, rule[2]) end
    end
  end
  fh:close()
end
check(#hits == 0, #hits .. " screen part(s) drawn by hand:\n  " .. table.concat(hits, "\n  "))

-- The components the rules point at exist.
local helpers = assert(io.open(ADDON .. "/UI/Helpers.lua", "rb")):read("*a")
for _, name in ipairs({ "CreateInput", "CreateSectionTitle", "CreateTableHeader", "SetSelected" }) do
  check(helpers:find("function Helpers:" .. name .. "%("), "UI:" .. name .. " exists")
end

print(("visual-fundamentals: %d checks passed"):format(checks))
