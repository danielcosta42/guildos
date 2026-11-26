-- The interface's way into chat-only commands (issue #142), run against the real Core/Core.lua,
-- Core/Compat.lua, Core/Data.lua, Core/Commands.lua, Modules/Mentions.lua and UI/FeaturePanels.lua
-- on a stubbed UI: each new button in Settings does what its command does, through the same
-- function, and the commands still do it. tools/commands-in-ui.lua checks every command has a way in.
--
--   luajit -e 'ADDON="."' tools/commands-ui-click.lua
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

-- Any frame, any field, any method: numbers where the layout does arithmetic, itself elsewhere.
local NUM = { GetWidth = 600, GetHeight = 400, GetFrameLevel = 1, GetStringHeight = 12, GetStringWidth = 40,
              GetNumChildren = 0, GetName = "GuildOSStub" }
local stub
stub = setmetatable({}, {
  __index = function(_, k)
    if NUM[k] then return function() return NUM[k] end end
    if k == "GetChildren" or k == "GetRegions" then return function() end end
    return stub
  end,
  __call = function() return stub end,
})
-- Frames the settings reach by global name (a slider's Low/High/Text): stubs too.
setmetatable(_G, { __index = function(_, k) if type(k) == "string" and k:match("^GuildOS") then return stub end end })
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = tostring(m) end }
local function said(text)
  for _, m in ipairs(printed) do if m:find(text, 1, true) then return true end end
  return false
end
function CreateFrame() return stub end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function UnitName() return "Off" end
function IsInGuild() return true end
function GetGuildInfo() return "Guild", "Rank", 1 end
function GetNumGuildMembers() return 0, 0 end
function GuildControlGetNumRanks() return 4 end
function GuildControlGetRankName(i) return "Rank" .. (i - 1) end
function GetServerTime() return 1000 end
date = os.date
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local reloaded = 0
function ReloadUI() reloaded = reloaded + 1 end
local popped, poppedData
SlashCmdList = {}
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }), VERSION = "test" }
dofile(ADDON .. "/Core/Core.lua")
function GuildOS:ShowDialog(name, _, _, data) popped, poppedData = name, data end
dofile(ADDON .. "/Core/Compat.lua")
dofile(ADDON .. "/Core/Data.lua")
dofile(ADDON .. "/Core/Commands.lua")
dofile(ADDON .. "/Modules/Mentions.lua")
function GuildOS:DateText() return "today" end

local buttons = {}
local function widget(fields)
  local w = setmetatable(fields, { __index = stub })
  function w:SetScript(_, fn) self.onClick = fn end
  function w:Hide() self.hidden = true end
  return w
end
GuildOS.UI = setmetatable({
  GetFeature = function() return nil end,
  CreateButton = function(_, _, t) local b = widget({ text = tostring(t) }); buttons[#buttons + 1] = b; return b end,
  CreateCheckbox = function() return widget({ checkbox = widget({}) }) end,
}, { __index = function() return function() return stub end end })
dofile(ADDON .. "/UI/Spacing.lua"); if GuildOS.UI then rawset(GuildOS.UI, "SP", GuildOS.Spacing) end   -- the spacing standard (#449)
dofile(ADDON .. "/UI/FeaturePanels.lua")
dofile(ADDON .. "/UI/SettingsPanel.lua")
GuildOS.CreateRolePicker = function() return stub end

local function button(text)
  for _, b in ipairs(buttons) do if b.text == text then return b end end
end
local function open(category)
  buttons, printed = {}, {}
  local ok, err = pcall(GuildOS.RefreshSettingsPanel, GuildOS, setmetatable({}, getmetatable(stub)), category)
  check(ok, "the " .. category .. " settings draw (" .. tostring(err) .. ")")
end

-- What each button reaches, recorded.
local did = {}
GuildOS.DataCollector = { CollectMyData = function() did.scan = true end }
GuildOS.SelfTest = { Run = function() did.selftest = true end }
GuildOS.Probe = { Run = function() did.probe = true end, RunChat = function() did.probeChat = true end }
-- The style module draws its own picker in General; only the preview is watched.
GuildOS.Style = setmetatable({ ShowPreview = function() did.preview = true end,
                                BuildPicker = function(_, _, y) return y end },
  { __index = function() return function() return stub end end })
GuildOS.guildKey = "Guild-Realm"
GuildOSDB = { ["Guild-Realm"] = { members = {} }, ["Other-Realm"] = { members = {} } }
GuildOS.State.startup.failed["Modules/Broken.lua"] = "boom"
GuildOS.State.errors = { { msg = "late error" } }
GuildOS.db = { settings = {}, mentions = { watchWords = { "raid", "boss" }, log = { { ts = 0, sender = "Ana", msg = "oi Off" } } } }

-- ── Settings → Data and support: diagnostics and erasing, for everyone (#367) ──
open("data")
for _, t in ipairs({ "Collect my data", "View Errors", "Self-test", "Probe the client", "Probe chat", "Style preview",
                     "Erase guild data" }) do
  check(button(t) and button(t).onClick, "About has " .. t)
end
button("Collect my data").onClick()
check(did.scan and said("Data collected."), "Collect my data collects, as /gos scan")
printed = {}
button("View Errors").onClick()
check(said("Modules/Broken.lua: boom") and said("late error"), "View Errors lists the start-up problems too, as /gos errors")
button("Self-test").onClick(); button("Probe the client").onClick(); button("Style preview").onClick()
check(did.selftest and did.probe and did.preview, "the diagnostics run what their commands run")
button("Probe chat").onClick()
check(popped == "GUILDOS_PROBE_CHAT" and not did.probeChat, "the chat probe posts in guild chat: it asks first")
GuildOS.Dialogs.GUILDOS_PROBE_CHAT.OnAccept()
check(did.probeChat, "and runs once confirmed")
button("Erase guild data").onClick()
check(popped == "GUILDOS_ERASE_GUILD" and reloaded == 0 and GuildOSDB["Guild-Realm"], "erasing asks first, and nothing is gone yet")
GuildOS.Dialogs.GUILDOS_ERASE_GUILD.OnAccept()
check(GuildOSDB["Guild-Realm"] == nil and GuildOSDB["Other-Realm"] and reloaded == 1, "confirmed: this guild's data only, then a reload")

-- ── Settings → Chat and alerts: the mentions log and clearing the words ─
open("chat")
check(button("Recent mentions") and button("Clear watch-words"), "Mentions has its log and its clear button")
button("Recent mentions").onClick()
check(said("--- Recent mentions ---") and said("oi Off") and not said("Usage:"), "the log, without the command's usage line")
button("Clear watch-words").onClick()
check(popped == "GUILDOS_CLEAR_WORDS" and #GuildOS.db.mentions.watchWords == 2, "clearing every word asks first")
local redrawn = false
poppedData.after = function() redrawn = true end
GuildOS.Dialogs.GUILDOS_CLEAR_WORDS.OnAccept({ data = poppedData })
check(#GuildOS.db.mentions.watchWords == 0 and redrawn, "confirmed: emptied, as /gos mentions clearwords, and the chips redrawn")

-- ── The commands still do the same, through the same functions ──────────
printed = {}
SlashCmdList.GUILDOS("errors")
check(said("Modules/Broken.lua: boom"), "/gos errors")
GuildOS.LootMaster = { IsMasterLooter = function() return false end }
printed = {}
SlashCmdList.GUILDOS("lm")
check(said("You are not the Master Looter.") and GuildOS:LootMasterStatus() == "You are not the Master Looter.", "/gos lm and the Loot tab's line")
GuildOS.RaidTracker = { MergeDuplicateSessions = function() return 0 end }
printed = {}
SlashCmdList.GUILDOS("mergeraids")
check(said("No duplicates found."), "/gos mergeraids")
local shown
GuildOS.ShowExportPopup = function(_, title) shown = title end
GuildOS.Companion = { IsEnabled = function() return false end, Build = function() return "GOSCOMP1:x", 3 end }
printed = {}
SlashCmdList.GUILDOS("web")
check(said("/gos web on") and not shown, "/gos web, the companion off: how to turn it on")
GuildOS.Companion.IsEnabled = function() return true end
GuildOS:ShowWebString()
check(shown == "Web Companion (3 members)", "the Web tab's button shows the paste text")

-- A bare /gos signup opens the sign-up window (#377): with its button moved from the footer to the Raids tab,
-- the command is the way in at any width and with Raids switched off.
local opened = 0
local realSignup = GuildOS.ShowCoreSignupFrame
GuildOS.ShowCoreSignupFrame = function() opened = opened + 1 end
printed = {}
SlashCmdList.GUILDOS("signup")
check(opened == 1 and not said("Usage: /gos signup"), "/gos signup alone opens the sign-up window")
GuildOS.ShowCoreSignupFrame = realSignup

-- /gos reset asks first, as the Settings button does (audit C15).
GuildOSDB["Guild-Realm"], popped, reloaded = { members = {} }, nil, 0
SlashCmdList.GUILDOS("reset")
check(popped == "GUILDOS_ERASE_GUILD" and reloaded == 0 and GuildOSDB["Guild-Realm"], "/gos reset asks, and nothing is gone yet")
GuildOS.Dialogs.GUILDOS_ERASE_GUILD.OnAccept()
check(GuildOSDB["Guild-Realm"] == nil and reloaded == 1, "confirmed, it erases this guild's data and reloads")

-- The verb in any case; an unknown one opens nothing and says how to list them (audit C16).
local toggled = 0
GuildOS.ToggleRoster = function() toggled = toggled + 1 end
printed = {}
SlashCmdList.GUILDOS("ERRORS")
check(said("Modules/Broken.lua: boom"), "/gos ERRORS is /gos errors")
printed = {}
SlashCmdList.GUILDOS("Debug Errors")
check(said("Modules/Broken.lua: boom"), "/gos debug errors, in any case")
printed = {}
SlashCmdList.GUILDOS("nonsense")
check(toggled == 0 and said("Unknown command."), "an unknown verb opens nothing and points at /gos help")
SlashCmdList.GUILDOS("")
check(toggled == 1, "a bare /gos still opens the window")
-- No prefix swallows its neighbour (audit B22): "crafts" is not /gos craft, "trials" not /gos trial.
local crafted = 0
GuildOS.ShowCraftFinder = function() crafted = crafted + 1 end
printed = {}
SlashCmdList.GUILDOS("crafts")
check(crafted == 0 and said("Unknown command."), "/gos crafts is not /gos craft")
SlashCmdList.GUILDOS("Craft")
check(crafted == 1, "/gos Craft is /gos craft")

-- The help is short (audit B22): the diagnostics are one /gos debug line.
printed = {}
SlashCmdList.GUILDOS("help")
check(said("/gos open <feature>") and said("/gos find <text>") and said("/gos debug [selftest"), "the help keeps open, find and debug")
check(not said("/gos selftest") and not said("/gos probe chat") and not said("/gos map"), "and leaves the rest to the window")

-- The diagnostics' old top-level verbs still run them (audit B22; the maintainer typed /gos probe in game and read
-- "Unknown command"): /gos probe and its three kinds, in any case, are their /gos debug ones.
do
  local ran = {}
  GuildOS.Probe = { Run = function() ran[#ran + 1] = "probe" end, RunChat = function() ran[#ran + 1] = "chat" end,
                    RunChannel = function() ran[#ran + 1] = "channel" end, RunInvite = function() ran[#ran + 1] = "invite" end }
  printed = {}
  for _, cmd in ipairs({ "probe", "Probe Chat", "probe channel", "probe invite", "debug probe invite", "  probe  " }) do
    SlashCmdList.GUILDOS(cmd)
  end
  check(table.concat(ran, ",") == "probe,chat,channel,invite,invite,probe" and not said("Unknown command."),
    "/gos probe [chat | channel | invite] run the probes: " .. table.concat(ran, ","))
  printed = {}
  SlashCmdList.GUILDOS("probe nonsense")
  check(said("/gos debug probe"), "an unknown kind of probe says where the probes are")
  GuildOS.Probe = nil
end

print(("commands-ui-click: %d checks passed"):format(checks))
