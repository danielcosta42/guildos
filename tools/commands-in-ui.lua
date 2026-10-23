-- Every /gos command has a way in from the interface (issue #142): reads the verbs the router in
-- Core/Commands.lua matches and fails when one is neither found in the interface code below nor
-- named, with a reason, as chat-only. A new command has to say where its button is.
--
--   luajit -e 'ADDON="."' tools/commands-in-ui.lua
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

local function read(rel)
  local fh = assert(io.open(ADDON .. "/" .. rel, "rb"), rel)
  local s = fh:read("*a")
  fh:close()
  return s
end

-- Where each command is in the interface: { file, the code that is that way in (a call, a button's
-- label, a builder) }, every pair required; never a word a comment could hold. Aliases are listed
-- with their verb. A subcommand (`ally request`, `mentions add`) is reached from its verb's place.
local IN_UI = {
  open        = { { "UI/Window.lua", "SetActiveTab" } },
  scan        = { { "UI/FeaturePanels.lua", "GuildOS:CollectMyDataNow()" } },
  selftest    = { { "UI/FeaturePanels.lua", "GuildOS.SelfTest:Run()" } },
  myalts      = { { "UI/MemberDetail.lua", "GuildOS.AltAutoDetect:PromptNow()" } },
  sync        = { { "UI/Window.lua", "GuildOS.CommSystem:FullSync()" } },
  points      = { { "UI/Features.lua", 'id = "dkp"' } },
  equity      = { { "UI/FeaturePanels.lua", 'showView("equity")' } },
  digest      = { { "UI/FeaturePanels.lua", "GuildOS.Digest:Show()" } },
  backup      = { { "UI/FeaturePanels.lua", "GuildOS.Backup:ShowExport()" } },
  restore     = { { "UI/FeaturePanels.lua", "GuildOS.Backup:ShowRestore()" } },
  bulletin    = { { "UI/CommunityPanel.lua", "BuildBulletinSub" } },
  polls       = { { "UI/CommunityPanel.lua", "BuildPollsSub" } },
  calendar    = { { "UI/CommunityPanel.lua", "CreateCalendarSub" } },
  cta         = { { "UI/CommunityPanel.lua", "BuildCallToArmsSub" } },
  analytics   = { { "UI/RosterFrame.lua", "GuildOS.GuildAnalytics:Show()" } },
  find        = { { "UI/Window.lua", "GuildOS.Search:Show()" } },
  craft       = { { "UI/RecipesPanel.lua", "GuildOS:ShowCraftFinder()" },
                  { "UI/ProfessionsPanel.lua", "GuildOS:ShowCraftFinder()" } },
  scout       = { { "UI/RosterFrame.lua", "GuildOS.RecruitScanner:BuildInto(" } },
  beacon      = { { "UI/RosterFrame.lua", 'L["Edit Beacon"]' } },
  map         = { { "UI/Minimap.lua", "GuildOS:ToggleGuildMap()" } },
  pug         = { { "UI/Minimap.lua", "GuildOS:TogglePugInspector()" } },
  minimap     = { { "UI/FeaturePanels.lua", 'L["Show minimap button"]' } },
  guildbutton = { { "UI/FeaturePanels.lua", "hijackGuildButton" } },
  prune       = { { "UI/FeaturePanels.lua", "GuildOS:PruneStaleData()" } },
  debug       = { { "UI/FeaturePanels.lua", "GuildOS.Logger.debug = checked" } },
  errors      = { { "UI/FeaturePanels.lua", "GuildOS:ShowErrors()" } },
  style       = { { "UI/StylePreview.lua", "self:Apply(id)" }, { "UI/FeaturePanels.lua", "GuildOS.Style:ShowPreview()" } },
  probe       = { { "UI/FeaturePanels.lua", "GuildOS.Probe:Run()" } },
  ["probe chat"] = { { "UI/FeaturePanels.lua", "GuildOS.Probe:RunChat()" } },
  reset       = { { "UI/FeaturePanels.lua", "GuildOS:EraseGuildData()" } },
  recruit     = { { "UI/RosterFrame.lua", 'L["Invite players who whisper the keyword"]' } },
  autoinvite  = { { "UI/RosterFrame.lua", 'L["Invite players who whisper the keyword"]' } },
  cons        = { { "UI/RaidHUD.lua", "GuildOS.ConsumableChecker:CheckRaid()" } },
  consreport  = { { "UI/RaidHUD.lua", 'GuildOS.ConsumableChecker:ReportToChat("RAID")' } },
  trial       = { { "UI/RosterFrame.lua", "GuildOS.TrialTracker:AddTrial(key)" } },
  note        = { { "UI/RosterFrame.lua", "GuildOS.OfficerNotes:AddNote(" } },
  lm          = { { "UI/FeaturePanels.lua", "GuildOS:LootMasterStatus()" } },
  -- Retail's loot council (issue #185): an Offer button by each tradeable item and on my own loot
  -- history rows, and the council in Settings' quick access.
  offer       = { { "UI/TradeCouncil.lua", "GuildOS.TradeCouncil:Offer(" }, { "UI/FeaturePanels.lua", "GuildOS.TradeCouncil:Offer(entry.itemLink)" },
                  { "UI/FeaturePanels.lua", "GuildOS:ShowTradeCouncil()" } },
  web         = { { "UI/WebPanel.lua", "GuildOS:ShowWebString()" }, { "UI/WebPanel.lua", "co:SetEnabled(" } },
  roster      = { { "UI/WebPanel.lua", 'L["Bring roster"]' } },
  exportatt   = { { "UI/FeaturePanels.lua", 'L["Test Attendance Export"]' } },
  export      = { { "UI/FeaturePanels.lua", 'L["Export Data"]' } },
  wish        = { { "UI/RosterFrame.lua", 'L["My Wishlist"]' } },
  mergeraids  = { { "UI/AuditPanel.lua", "GuildOS:MergeRaidSessions()" } },
  specs       = { { "UI/AuditPanel.lua", "GuildOS.SpecChecker:ScanGroup()" } },
  attune      = { { "UI/AuditPanel.lua", "BuildAttuneSub" } },
  signup      = { { "UI/Window.lua", "GuildOS:ShowCoreSignupFrame()" } },
  ban         = { { "UI/ManagementPanel.lua", "GuildOS.BanList:Add(" } },
  mentions    = { { "UI/FeaturePanels.lua", "GuildOS.Mentions:PrintLog()" },
                  { "UI/FeaturePanels.lua", 'GuildOS.Mentions:HandleCommand({ "clearwords" })' } },
  notecmd     = { { "UI/FeaturePanels.lua", "GuildOS.db.noteCommand.enabled = checked" } },
  avail       = { { "UI/CommunityPanel.lua", "GuildOS.LFGBoard:Show()" } },
  ally        = { { "UI/AlliancePanel.lua", "ALLY():Create(" }, { "UI/AlliancePanel.lua", "ALLY():RequestJoin(" } },
}
local ALIAS = {
  points = { "dkp" }, equity = { "lootequity" }, bulletin = { "board" }, polls = { "poll" },
  calendar = { "cal", "events" }, analytics = { "stats" }, find = { "search" }, scout = { "recruitscan" },
  beacon = { "recruitbeacon" }, map = { "guildmap" }, recruit = { "recruiting" }, autoinvite = { "ai" },
  cons = { "consumables" }, lm = { "lootmaster" }, web = { "companion" }, exportatt = { "exportattendance" },
  attune = { "attunements" }, signup = { "unsignup" }, ban = { "tempban", "unban", "banlist" },
  ally = { "alliance" },
}
-- Chat-only, and why.
local CHAT_ONLY = {
  help = "prints the list of commands", commands = "help's alias",
  lfg = "opens by itself for a player with no guild",
  resscan = "debug: the resistance scan, printed",
  ["attune debug"] = "debug", ["attunements debug"] = "debug", ["attune dumpquests"] = "debug: a quest-id dump",
}

-- The verbs the router matches: `msg == "x"` and `msg:match("^x")`. Any other way of telling one
-- command from another would hide it from this list, so there is none.
local src = read("Core/Commands.lua")
check(not src:find("msg:find(", 1, true) and not src:find("msg:sub(", 1, true) and not src:find("string.find(msg", 1, true)
  and not src:find('msg:match("^(', 1, true), "the router tells commands apart only by msg == and msg:match")
local verbs = {}
for v in src:gmatch('msg == "([%a ]+)"') do verbs[v] = true end
for v in src:gmatch('msg:match%("%^(%a+)') do verbs[v] = true end
check(next(verbs) ~= nil and verbs.analytics and verbs["probe chat"], "the router's verbs are read")

local known = {}
for verb, ways in pairs(IN_UI) do
  known[verb] = true
  for _, a in ipairs(ALIAS[verb] or {}) do known[a] = true end
  for _, w in ipairs(ways) do
    local file, needle = w[1], w[2]
    check(read(file):find(needle, 1, true) ~= nil, "/gos " .. verb .. ": " .. file .. " has " .. needle)
  end
end
for verb in pairs(CHAT_ONLY) do known[verb] = true end

for verb in pairs(verbs) do
  check(known[verb], "/gos " .. verb .. " has a way in from the interface, or is named chat-only with a reason")
end
-- And nothing listed here that the router no longer has: a stale line would hide a removed command.
for verb in pairs(known) do
  check(verbs[verb], "/gos " .. verb .. " is still a command")
end

print(("commands-in-ui: %d checks passed"):format(checks))
