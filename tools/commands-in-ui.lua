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
  -- The diagnostics are under /gos debug (audit B22); their old verbs are unlisted aliases.
  ["debug scan"] = { { "UI/SettingsPanel.lua", "GuildOS:CollectMyDataNow()" } },
  ["debug selftest"] = { { "UI/SettingsPanel.lua", "GuildOS.SelfTest:Run()" } },
  myalts      = { { "UI/MemberDetail.lua", "GuildOS.AltAutoDetect:PromptNow()" } },
  sync        = { { "UI/Window.lua", "GuildOS.CommSystem:FullSync()" } },
  -- The points and the equity are the Loot window's Accounts and History (issue #346).
  points      = { { "UI/Features.lua", 'id = "dkp"' }, { "UI/PointsPanel.lua", "function GuildOS:BuildLootAccounts" } },
  equity      = { { "UI/LootWindow.lua", 'show("equity")' } },
  -- The record is a section of the member's sheet, with its term (issue #402).
  record      = { { "UI/MemberDetail.lua", "D:Record(playerKey)" }, { "UI/MemberDetail.lua", "D:SetTerm(" } },
  warn        = { { "UI/MemberDetail.lua", "GuildOS:ShowWarnDialog(playerKey, who)" } },
  digest      = { { "UI/SettingsPanel.lua", "GuildOS.Digest:Show()" } },
  backup      = { { "UI/SettingsPanel.lua", "GuildOS.Backup:ShowExport()" } },
  restore     = { { "UI/SettingsPanel.lua", "GuildOS.Backup:ShowRestore()" } },
  bulletin    = { { "UI/CommunityPanel.lua", "BuildBulletinSub" } },
  -- The guild's rules are the Guild hub's Rules sub-tab, for every member (issue #407).
  rules       = { { "UI/CommunityPanel.lua", "BuildGuildRulesSub" } },
  polls       = { { "UI/CommunityPanel.lua", "drawPolls(child, y)" } },
  calendar    = { { "UI/CommunityPanel.lua", "CreateCalendarSub" } },
  cta         = { { "UI/CommunityPanel.lua", "BuildCallToArmsSub" } },
  analytics   = { { "UI/RosterFrame.lua", "GuildOS.GuildAnalytics:Show()" } },
  find        = { { "UI/Window.lua", "GuildOS.Search:Show()" } },
  order       = { { "UI/CraftOrdersPanel.lua", "function GuildOS:CreateCraftsTab" },
                  { "UI/CraftFinder.lua", "GuildOS:ShowCraftOrderDialog(" } },
  craft       = { { "UI/Rooms.lua", "GuildOS:ShowCraftFinder()" } },
  scout       = { { "UI/RosterFrame.lua", "GuildOS.RecruitScanner:BuildInto(" } },
  beacon      = { { "UI/RosterFrame.lua", 'L["Edit Beacon"]' } },
  pug         = { { "UI/Minimap.lua", "GuildOS:TogglePugInspector()" } },
  minimap     = { { "UI/SettingsPanel.lua", 'L["Show minimap button"]' } },
  guildbutton = { { "UI/SettingsPanel.lua", "hijackGuildButton" } },
  debug       = { { "UI/SettingsPanel.lua", "GuildOS.Logger.debug = checked" } },
  ["debug errors"] = { { "UI/SettingsPanel.lua", "GuildOS:ShowErrors()" } },
  style       = { { "UI/StylePreview.lua", "self:Apply(id)" }, { "UI/SettingsPanel.lua", "GuildOS.Style:ShowPreview()" } },
  ["debug probe"] = { { "UI/SettingsPanel.lua", "GuildOS.Probe:Run()" } },
  ["debug probe chat"] = { { "UI/SettingsPanel.lua", "GuildOS.Probe:RunChat()" } },
  ["debug probe channel"] = { { "UI/AuditPanel.lua", "GuildOS.Probe:RunChannel()" } },
  ["debug perf"] = { { "UI/AuditPanel.lua", "GuildOS.Perf:Print()" } },
  ["debug perf reset"] = { { "UI/AuditPanel.lua", "GuildOS.Perf:Reset()" } },
  -- Asked first, from the command too (audit C15).
  reset       = { { "UI/SettingsPanel.lua", "GuildOS:AskEraseGuildData()" } },
  recruit     = { { "UI/RosterFrame.lua", 'L["Invite players who whisper the keyword"]' } },
  autoinvite  = { { "UI/RosterFrame.lua", 'L["Invite players who whisper the keyword"]' } },
  -- The Raid HUD is TBC's; on retail the readiness tab is the way in (issue #187).
  cons        = { { "UI/RaidHUD.lua", "GuildOS.ConsumableChecker:CheckRaid()" },
                  { "UI/AuditPanel.lua", "GuildOS:ShowConsumablePopup()" } },
  consreport  = { { "UI/RaidHUD.lua", 'GuildOS.ConsumableChecker:ReportToChat("RAID")' } },
  trial       = { { "UI/RosterFrame.lua", "GuildOS.TrialTracker:AddTrial(key)" } },
  note        = { { "UI/RosterFrame.lua", "GuildOS.OfficerNotes:AddNote(" } },
  lm          = { { "UI/LootWindow.lua", "GuildOS:LootMasterStatus()" } },
  -- The Master Loot window's own button (issue #294).
  ["lm undo"] = { { "Modules/LootMaster.lua", "LootMaster:UndoLastAward()" } },
  -- Retail's loot council (issue #185): an Offer button by each tradeable item and on my own loot
  -- history rows, and the council's own button in the Loot window (#367).
  offer       = { { "UI/TradeCouncil.lua", "GuildOS.TradeCouncil:Offer(" }, { "UI/LootWindow.lua", "GuildOS.TradeCouncil:Offer(link)" },
                  { "UI/LootWindow.lua", "GuildOS:ShowTradeCouncil()" } },
  web         = { { "UI/WebPanel.lua", "GuildOS:ShowWebString()" }, { "UI/WebPanel.lua", "co:SetEnabled(" } },
  roster      = { { "UI/WebPanel.lua", 'L["Bring roster"]' } },
  -- The Iniciar raide button, on the Web tab, the Now tab and the owner's prompt (issue #400).
  ["raid start"] = { { "UI/WebPanel.lua", "GuildOS.RaidStart:Click(" }, { "UI/Salao.lua", "UI:CreateRaidStepper(" } },
  exportatt   = { { "UI/SettingsPanel.lua", 'L["Test Attendance Export"]' } },
  export      = { { "UI/SettingsPanel.lua", 'L["Export Data"]' } },
  wish        = { { "UI/RosterFrame.lua", 'L["My Wishlist"]' } },
  ["debug mergeraids"] = { { "UI/AuditPanel.lua", "GuildOS:MergeRaidSessions()" } },
  specs       = { { "UI/AuditPanel.lua", "GuildOS.SpecChecker:ScanGroup()" } },
  attune      = { { "UI/AuditPanel.lua", "BuildAttuneSub" } },
  signup      = { { "UI/RosterFrame.lua", "GuildOS:ShowCoreSignupFrame()" } },   -- the Raids screen's button (#377)
  ban         = { { "UI/ManagementPanel.lua", "GuildOS.BanList:Add(" } },
  -- Leadership > Bulk actions (issue #420): its Next, Skip and Stop are the panel's buttons.
  bulk        = { { "UI/ManagementPanel.lua", "GuildOS:BuildBulkSub(p)" }, { "UI/BulkPanel.lua", "BA:Skip()" },
                  { "UI/BulkPanel.lua", "BA:Stop()" }, { "UI/BulkPanel.lua", "GuildOS.BulkActions:Arm(down)" } },
  -- A member's alts to the main's rank (issue #424): the buttons on the member's sheet.
  altgroup    = { { "UI/MemberDetail.lua", "GuildOS.BulkActions:StartGroupAndSay(playerKey" } },
  -- My birthday (issue #428): Settings > Profile's Birthday, its box and its "Show my birthday".
  birthday    = { { "UI/SettingsPanel.lua", "GuildOS.Birthdays:SetMineText(" }, { "UI/SettingsPanel.lua", "GuildOS.Birthdays:ClearMine()" } },
  -- Leadership > Notes and marks (issue #429): its buttons call what the commands call.
  joindate    = { { "UI/ManagementPanel.lua", "GuildOS:BuildMarksSub(p)" }, { "UI/MarksPanel.lua", "ND:WriteOne(" },
                  { "UI/MarksPanel.lua", "ND:ImportPlan()" }, { "UI/MarksPanel.lua", "ND:Plan()" } },
  safe        = { { "UI/MarksPanel.lua", "MM:CommandSafe(" } },
  nick        = { { "UI/MarksPanel.lua", "MM:CommandNick(" } },
  mentions    = { { "UI/SettingsPanel.lua", "GuildOS.Mentions:PrintLog()" },
                  { "UI/SettingsPanel.lua", 'GuildOS.Mentions:HandleCommand({ "clearwords" })' } },
  notecmd     = { { "UI/SettingsPanel.lua", "GuildOS.db.noteCommand.enabled = checked" } },
  avail       = { { "UI/CommunityPanel.lua", "GuildOS.LFGBoard:Show()" } },
  -- The Bank tab (issue #380); its sort and stop are the bar under the game's bank.
  bank        = { { "UI/Features.lua", 'id = "bank"' }, { "UI/GuildBankPanel.lua", "B:StartSort(B:OrganizableTabs())" } },
  ally        = { { "UI/AlliancePanel.lua", "ALLY():Create(" }, { "UI/AlliancePanel.lua", "ALLY():RequestJoin(" } },
}
local ALIAS = {
  points = { "dkp" }, equity = { "lootequity" }, bulletin = { "board" }, polls = { "poll" },
  calendar = { "cal", "events" }, analytics = { "stats" }, find = { "search" }, scout = { "recruitscan" },
  beacon = { "recruitbeacon" }, recruit = { "recruiting" }, autoinvite = { "ai" },
  cons = { "consumables" }, lm = { "lootmaster" }, web = { "companion" }, exportatt = { "exportattendance" },
  attune = { "attunements" }, signup = { "unsignup" }, ban = { "tempban", "unban", "banlist" },
  ally = { "alliance" }, birthday = { "aniversario" },
}
-- Chat-only, and why.
local CHAT_ONLY = {
  help = "prints the list of commands", commands = "help's alias",
  lfg = "opens by itself for a player with no guild",
  ["debug resscan"] = "debug: the resistance scan, printed",
  altlimit = "an audit printed in chat, as GRM's /grm altlimit (issue #424)",
  ["debug attune"] = "debug: the attunement quests, one by one", ["debug dumpquests"] = "debug: a quest-id dump",
}

-- The verbs the router matches: `msg == "x"` and `msg:match("^x")`. Any other way of telling one
-- command from another would hide it from this list, so there is none.
local src = read("Core/Commands.lua")
check(not src:find("msg:find(", 1, true) and not src:find("msg:sub(", 1, true) and not src:find("string.find(msg", 1, true)
  and not src:find('msg:match("^(', 1, true), "the router tells commands apart only by msg == and msg:match")
local verbs = {}
for v in src:gmatch('msg == "([%a ]+)"') do verbs[v] = true end
for v in src:gmatch('msg:match%("%^(%a+)') do verbs[v] = true end
check(next(verbs) ~= nil and verbs.analytics and verbs["debug probe chat"], "the router's verbs are read")

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

-- No prefix that swallows its neighbours (audit B22): a verb that takes words is matched with its space.
for _, v in ipairs({ "find", "web", "craft", "order", "wish", "trial", "recruit", "roster", "export", "signup", "unsignup" }) do
  check(not src:find('msg:match("^' .. v .. '")', 1, true), "/gos " .. v .. " is matched whole or with a space, never as a bare prefix")
end
-- The verb in any case (audit C16), and an unknown one opens nothing.
check(src:find("msg = normalize(strtrim(msg or \"\"))", 1, true), "the verb is lowercased before the router")
check(not src:find("        GuildOS:ToggleRoster()\n    end\nend", 1, true), "an unknown verb no longer opens the roster")

print(("commands-in-ui: %d checks passed"):format(checks))
