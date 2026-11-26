----------------------------------------------------------------------
-- Guild OS - Slash Commands
-- /guildos and /gos dispatch table.
----------------------------------------------------------------------

-- Primary slash command: /guildos and /gos
SLASH_GUILDOS1 = "/guildos"
SLASH_GUILDOS2 = "/gos"


local L = GuildOS.L

----------------------------------------------------------------------
-- /gos help listing
--
-- Lives in helpers so the command branch stays a single call. Colour
-- escapes are built here and never stored inside an L[] key, so a
-- translation can never break "|cff......" / "|r".
----------------------------------------------------------------------
local HELP_HEADER_COLOR = "|cff00CCFF"   -- section headers
local HELP_CMD_COLOR    = "|cffFFD700"   -- command verbs (addon gold)
-- The diagnostics under /gos debug, as the help lists them (audit B22).
local DEBUG_VERBS = { "selftest", "errors", "perf [reset]", "probe [chat | channel | invite]", "scan", "mergeraids" }

local function helpHeader(text)
    GuildOS:Print(HELP_HEADER_COLOR .. text .. "|r")
end

local function helpLine(verb, desc)
    GuildOS:Print("  " .. HELP_CMD_COLOR .. verb .. "|r  " .. desc)
end

-- A short list (audit B22): every tab opens with /gos open, and the window holds the rest. The other
-- verbs still work; the diagnostics are under /gos debug.
local function printHelp()
    GuildOS:Print(HELP_CMD_COLOR .. L["Guild OS commands (/gos or /guildos):"] .. "|r")

    helpHeader(L["General"])
    helpLine("/gos",             L["Open Guild OS"])
    helpLine("/gos open <feature>", L["Open a tab (roster, raids, loot, guild...)"])
    helpLine("/gos find <text>", L["Search members by name, class, level or note"])
    helpLine("/gos sync",        L["Force a full data sync"])
    if GuildOS.GuildMap then helpLine("/gos map", L["Open the live guild map"]) end
    helpLine("/gos craft <item>",  L["Who can craft an item"])
    helpLine("/gos order <item>",  L["Ask the guild's crafters to make an item"])
    if GuildOS.Companion then helpLine("/gos web [on|off]", L["Copy your guild into the web companion"]) end

    helpHeader(L["Raid and loot"])
    if GuildOS.LootMaster then helpLine("/gos lm", L["Master Loot helper status"]) end  -- not on retail (ADR-0026)
    if GuildOS.Points then helpLine("/gos points", L["Points and DKP window"]) end
    if GuildOS.TradeCouncil then   -- retail's loot council by trade (issue #185)
        helpLine("/gos offer [item]", L["Offer a tradeable item to the raid, or open the loot council"])
    end
    if GuildOS.ConsumableChecker then  -- Anniversary and retail, not Forever (ADR-0014, issue #187)
        helpLine("/gos cons",      L["Check raid consumables"])
    end
    helpLine("/gos specs",         L["Scan group talent specs"])
    helpLine("/gos export <what>", GuildOS.LootTracker and L["Export roster, attendance or loot"]
        or L["Export roster or attendance"])   -- the loot history is on retail too since issue #183
    if GuildOS.CompanionImport then helpLine("/gos roster", L["Bring the raid roster in from the website"]) end
    if GuildOS.RaidStart then   -- issue #400: the Iniciar raide button's next step
        helpLine("/gos raid start", L["Start the website's raid: invite and arrange, one step a click"])
    end

    -- These verbs are refused inside their own modules for non-officers, so
    -- showing them to a member would only advertise commands that do nothing.
    if GuildOS:IsOfficer() then
        helpHeader(L["Officers"])
        helpLine("/gos ban <name>",            L["Ban a player from invites"])
        helpLine("/gos unban <name>",          L["Lift a ban"])
        helpLine("/gos warn <name> [reason]",  L["Warn a member, with one click"])
        helpLine("/gos note <name> <text>",    L["Add an officer note"])
        if GuildOS.BulkActions then
            helpLine("/gos bulk [next | skip | retry | stop]",L["Promote, demote or remove by rules, one member per click"])
        end
        if GuildOS.ActionQueue then
            helpLine("/gos queue [next | clear | bind <key>]", L["The invites and whispers waiting for a key press"])
        end
    end

    helpHeader(L["Diagnostics"])
    helpLine("/gos debug [" .. table.concat(DEBUG_VERBS, " | ") .. "]", L["Toggle debug output, or run one diagnostic"])
end

----------------------------------------------------------------------
-- What a command and a button share (#142): every /gos command has a way in
-- from the interface too, and both call the one function here, so the button
-- does exactly what the command does.
----------------------------------------------------------------------
function GuildOS:CollectMyDataNow()
    if not GuildOS.DataCollector then return end
    GuildOS.DataCollector:CollectMyData()
    GuildOS:Print(L["Data collected."])
end

function GuildOS:MergeRaidSessions()
    if not GuildOS.RaidTracker then return end
    GuildOS:Print(L["Merging duplicate raid sessions\226\128\166"])
    if GuildOS.RaidTracker:MergeDuplicateSessions() == 0 then
        GuildOS:Print(L["|cffAAAAAA[Guild OS] No duplicates found.|r"])
    end
end

-- Start-up problems first: the ring below is capped and shared with runtime
-- errors, so it can already have lost them.
function GuildOS:ShowErrors()
    local startup = GuildOS:ListStartupProblems()
    local shown = {}
    if #startup > 0 then
        GuildOS:Print(string.format(L["%d start-up problem(s):"], #startup))
        for _, line in ipairs(startup) do
            shown[line] = true
            GuildOS:Print("|cffFF8800" .. line .. "|r")
        end
    end
    -- The ring also holds the start-up problems just listed; skip those.
    local ring, rest = (GuildOS.State and GuildOS.State.errors) or {}, {}
    for _, e in ipairs(ring) do
        if not shown[e.msg] then rest[#rest + 1] = e end
    end
    if #rest == 0 then
        if #startup == 0 then GuildOS:Print(L["No errors recorded this session."]) end
    else
        GuildOS:Print(string.format(L["%d recent error(s):"], #rest))
        for i = math.max(1, #rest - 9), #rest do
            GuildOS:Print("|cffFF4444" .. (rest[i].msg or "?") .. "|r")
        end
    end
end

-- Whether this client is the Master Looter, as one line.
function GuildOS:LootMasterStatus()
    if not GuildOS.LootMaster then return nil end
    return GuildOS.LootMaster:IsMasterLooter() and L["Loot Master mode active. Open loot to start."]
        or L["You are not the Master Looter."]
end

-- The string to paste into the web companion, in a popup; or why there is none.
function GuildOS:ShowWebString()
    local C = GuildOS.Companion
    if not C then return end
    if not C:IsEnabled() then
        GuildOS:Print(L["The web companion is off. Turn it on with /gos web on."])
        return
    end
    local text, countOrErr = C:Build()
    if text then
        GuildOS:ShowExportPopup(string.format(L["Web Companion (%d members)"], countOrErr), text)
    else
        GuildOS:Print(L["|cffFF4444Export failed:|r "] .. tostring(countOrErr))
    end
end

-- Every Guild OS record of this guild, gone, and the interface reloaded.
function GuildOS:EraseGuildData()
    if GuildOS.guildKey and GuildOSDB then GuildOSDB[GuildOS.guildKey] = nil end
    ReloadUI()
end

-- /gos reset and Settings' Erase guild data: asked first, since it cannot be undone (audit C15).
function GuildOS:AskEraseGuildData()
    GuildOS.Dialogs["GUILDOS_ERASE_GUILD"] = GuildOS.Dialogs["GUILDOS_ERASE_GUILD"] or {
        text = L["Erase all Guild OS data for this guild and reload the interface? This cannot be undone."],
        button1 = L["Erase guild data"], button2 = L["Cancel"],
        OnAccept = function() GuildOS:EraseGuildData() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    GuildOS:ShowDialog("GUILDOS_ERASE_GUILD")
end

-- The verbs of what retail does not have (ADR-0026): no Master Loot, and no soft reserves (softres.it
-- runs Classic raids only). Each module is absent, so its verb says so rather than doing nothing or
-- raising. The site's verbs (web, companion, roster) are retail's too since issue #182, equity since
-- issue #183, and points, dkp and wish since issue #185.
local RETAIL_ABSENT = { "^lm$", "^lm%s", "^lootmaster$", "^softres" }

local function absentHere(msg)
    if not GuildOS.Client.isRetail then return false end
    for _, pat in ipairs(RETAIL_ABSENT) do
        if msg:match(pat) then return true end
    end
    return false
end

-- The commands of two words whose second word is a keyword: lowercased with the verb (audit C16). Any other
-- second word is a name, an item or a note, and keeps its case.
local KEYWORD_PAIRS = {
    ["probe chat"] = true, ["probe channel"] = true, ["probe invite"] = true, ["perf reset"] = true, ["lm undo"] = true,
    ["lm announce"] = true, ["raid start"] = true, ["attune debug"] = true, ["attunements debug"] = true,
    ["attune dumpquests"] = true, ["record term"] = true, ["web on"] = true, ["web off"] = true,
    ["companion on"] = true, ["companion off"] = true,
}

-- The verb in any case: "/gos Help" is "/gos help" (audit C16). After /gos debug, every word is a keyword.
local function normalize(text)
    local verb, rest = text:match("^(%S+)(.*)$")
    if not verb then return text end
    verb = verb:lower()
    if verb == "debug" then return verb .. rest:lower() end
    local gap, second, tail = rest:match("^(%s+)(%S+)(.*)$")
    if second and KEYWORD_PAIRS[verb .. " " .. second:lower()] then rest = gap .. second:lower() .. tail end
    return verb .. rest
end

-- The diagnostics' old verbs (audit B22), kept unlisted for one release: each is its /gos debug one.
local DEBUG_ALIAS = {
    scan = "scan", selftest = "selftest", errors = "errors", perf = "perf", ["perf reset"] = "perf reset",
    probe = "probe", ["probe chat"] = "probe chat", ["probe channel"] = "probe channel", ["probe invite"] = "probe invite", resscan = "resscan",
    mergeraids = "mergeraids", ["attune debug"] = "attune", ["attunements debug"] = "attune",
    ["attune dumpquests"] = "dumpquests",
}

local function handleCommand(msg)
    msg = normalize(strtrim(msg or ""))
    if DEBUG_ALIAS[msg] then msg = "debug " .. DEBUG_ALIAS[msg] end
    if absentHere(msg) then
        GuildOS:Print(L["Not available on this client."])
        return
    end
    -- Deliberately the first branch: "help", "?" and "commands" are exact
    -- literals, so this can never swallow another verb, and sitting at the top
    -- means no present or future prefix pattern below can ever swallow them.
    if msg == "help" or msg == "?" or msg == "commands" then
        printHelp()
    elseif msg == "debug scan" then
        GuildOS:CollectMyDataNow()
    elseif msg == "debug selftest" then
        if GuildOS.SelfTest then GuildOS.SelfTest:Run() end
    elseif msg == "myalts" then
        if GuildOS.AltAutoDetect then GuildOS.AltAutoDetect:PromptNow() end
    elseif msg == "myalts reset" then
        -- The account's answers to the login prompt forgotten (#449): it may ask about each character again.
        if GuildOS.AltAutoDetect then GuildOS.AltAutoDetect:ResetAnswers() end
    elseif msg == "sync" then
        if GuildOS.CommSystem then
            GuildOS.CommSystem:FullSync()
        end
    elseif msg == "debug perf" then
        GuildOS.Perf:Print()
    elseif msg == "debug perf reset" then
        GuildOS.Perf:Reset()
        GuildOS:Print(L["Performance counters zeroed."])
    elseif msg == "points" or msg == "dkp" then
        if GuildOS.ShowPointsFrame then
            GuildOS:ShowPointsFrame()
        end
    elseif msg == "equity" or msg == "lootequity" then
        if GuildOS.LootEquity then
            GuildOS.LootEquity:PrintSummary(15)
        end
    elseif msg == "digest" then
        if GuildOS.Digest then
            GuildOS.Digest:Show()
        end
    elseif msg == "backup" then
        if GuildOS.Backup then GuildOS.Backup:ShowExport() end
    elseif msg == "restore" then
        if GuildOS.Backup then GuildOS.Backup:ShowRestore() end
    elseif msg == "bank" or msg:match("^bank%s") then
        -- /gos bank [sort [all] | stop | sync | need]: the guild bank (issue #380)
        if GuildOS.GuildBank then
            local a = {}
            for w in msg:gmatch("%S+") do a[#a + 1] = w end
            table.remove(a, 1)
            GuildOS.GuildBank:HandleCommand(a)
        end
    elseif msg == "rules" then
        -- /gos rules: the guild's rules, for any member (#407).
        if GuildOS.GuildRules then GuildOS.GuildRules:Show() end
    elseif msg == "bulletin" or msg == "board" then
        if GuildOS.Bulletin then GuildOS.Bulletin:Show() end
    elseif msg == "cta" or msg:match("^cta%s") then
        -- /gos cta: the panel. /gos cta <type> [message]: send it (issue #108).
        local rest = strtrim((msg:gsub("^cta%s*", "")))
        local kind = rest:match("^(%S+)")
        local CTA = GuildOS.CallToArms
        if not kind then
            GuildOS.UI:OpenWindow("guild", "cta")
        elseif CTA and CTA:Template(kind:lower()) then
            CTA:Send(kind:lower(), rest:match("^%S+%s+(.+)$"))
        else
            GuildOS:Print(L["Usage: /gos cta [worldboss|pvp|defend|event|rally] [message]"])
        end
    elseif msg == "ally" or msg:match("^ally%s") or msg == "alliance" or msg:match("^alliance%s") then
        -- The alliance: its status and the shared /g's switch; the pact's old verbs say where
        -- alliances live now (Modules/Alliance.lua).
        if GuildOS.Alliance then
            GuildOS.Alliance:HandleCommand(msg:match("^%a+%s+(.*)$") or "")
        end
    elseif msg == "analytics" or msg == "stats" then
        if GuildOS.GuildAnalytics then GuildOS.GuildAnalytics:Show() end
    elseif msg == "polls" or msg == "poll" then
        if GuildOS.Polls then GuildOS.Polls:Show() end
    elseif msg == "calendar" or msg == "cal" or msg == "events" then
        if GuildOS.ShowCalendar then GuildOS:ShowCalendar() end
    elseif msg == "search" or msg == "find" or msg:match("^find%s") then
        if GuildOS.Search then
            local q = strtrim((msg:gsub("^find%s*", "")))
            GuildOS.Search:Show(q ~= "search" and q or "")
        end
    elseif (msg == "order" or msg:match("^order%s")) and GuildOS.ShowCraftOrderDialog then
        -- /guildos order [item link or id] — a craft order (issue #389); no item opens the Orders tab.
        local arg = strtrim((msg:gsub("^order%s*", "")))
        local itemId = tonumber(arg:match("item:(%d+)")) or tonumber(arg:match("^(%d+)$"))
        if itemId then
            GuildOS:ShowCraftFor(itemId)
        else
            GuildOS.UI:OpenWindow("recipes", "mine")
        end
    elseif msg == "craft" or msg:match("^craft%s") then
        -- /guildos craft <item link or id> — who can craft this, guild + realm.
        local arg = strtrim((msg:gsub("^craft%s*", "")))
        local itemId = tonumber(arg:match("item:(%d+)")) or tonumber(arg:match("^(%d+)$"))
        -- The Workshop's Search the realm (#449), on the item when one is given.
        if GuildOS.ShowCraftFinder and GuildOS:ShowCraftFinder(itemId) ~= false then
            return
        end
        if not itemId then
            GuildOS:Print(L["Usage: /guildos craft [item link or id]"])
        else
            local itemName = GuildOS.Compat.GetItemInfo(itemId) or ("item:" .. itemId)
            local seen = {}
            -- Guild crafters are already known locally (RecipeTracker sync).
            local guild = GuildOS.RecipeTracker and GuildOS.RecipeTracker:GetCraftersForItem(itemId)
            if guild and #guild > 0 then
                local names = {}
                for _, c in ipairs(guild) do
                    if not seen[c.playerName] then
                        seen[c.playerName] = true
                        names[#names + 1] = c.playerName
                    end
                end
                GuildOS:Print(string.format(L["Crafters for %s in guild: %s"], itemName, table.concat(names, ", ")))
            else
                GuildOS:Print(string.format(L["No guild crafter for %s - asking the realm..."], itemName))
            end
            -- Alliance: from guildos.me's directory (Alliance:FindCrafters), offline crafters included.
            if GuildOS.Alliance and GuildOS.Alliance:Get() then
                for _, c in ipairs(GuildOS.Alliance:FindCrafters(itemId)) do
                    if not seen[c.name] then
                        seen[c.name] = true
                        GuildOS:Print("   " .. string.format(L["%s of %s can craft %s (%s)"],
                            c.name, c.guild, itemName, L[c.prof or "?"])
                            .. (c.online and "" or " " .. L["(offline)"]))
                    end
                end
            end
            -- Realm-wide: answers trickle in over the mesh (out-of-guild reach).
            if GuildOS.CraftNet then
                GuildOS.CraftNet:Query(itemId, function(short, label)
                    if seen[short] then return end
                    seen[short] = true
                    GuildOS:Print("   " .. string.format(L["%s can craft %s (%s)"], short, itemName, L[label or "?"]))
                end)
            end
        end
    elseif msg == "scout" or msg == "recruitscan" then
        -- Officer: /who-scan unguilded candidates, mass-whisper a template.
        if GuildOS.RecruitScanner then GuildOS.RecruitScanner:Show() end
    elseif msg == "beacon" or msg == "recruitbeacon" then
        -- Officer: compose/toggle the guild recruitment beacon.
        if GuildOS.ShowRecruitBeacon then GuildOS:ShowRecruitBeacon() end
    elseif msg == "lfg" or msg == "recruiting" then
        -- Anyone: browse guilds recruiting nearby. With no guild, on Forever and retail, that is the
        -- guild finder; otherwise the inbox of what was heard over the mesh.
        if IsInGuild() then
            if GuildOS.ShowRecruitInbox then GuildOS:ShowRecruitInbox() end
        else
            GuildOS:OpenGuildFinder()
        end
    elseif msg == "map" or msg == "guildmap" then
        -- Anyone: the live guild map (world map pins and the list on it; issue #449).
        if GuildOS.ToggleGuildMap then GuildOS:ToggleGuildMap() end
    elseif msg == "pug" then
        -- Anyone: classify the current party/raid against what GuildOS knows.
        if GuildOS.TogglePugInspector then GuildOS:TogglePugInspector() end
    elseif msg == "minimap" then
        if GuildOS.ToggleMinimapButton then
            local shown = GuildOS:ToggleMinimapButton()
            GuildOS:Print(shown and L["Minimap button shown."] or L["Minimap button hidden."])
        end
    elseif msg == "guildbutton" then
        -- Toggle whether the guild micro button / "J" opens Guild OS or Blizzard's
        -- guild UI. Lets people keep the modern guild UI and reach Guild OS elsewhere.
        local on = not GuildOS:IsGuildButtonHijacked()
        GuildOS:SetSetting("hijackGuildButton", on)
        GuildOS:Print(on and L["Guild button now opens Guild OS."]
            or L["Guild button now opens the Blizzard guild UI. Open Guild OS from the minimap button."])
    elseif msg == "debug" then
        GuildOS.Logger.debug = not GuildOS.Logger.debug
        GuildOS:Print(GuildOS.Logger.debug and L["Debug mode ON."] or L["Debug mode OFF."])
    elseif msg == "debug resscan" then
        -- Diagnostic: run the resistance scan (equipped + bags) and print the max
        -- wearable per school, so the tooltip-based read can be verified in-game.
        local r = GuildOS.Resistances and GuildOS.DataCollector and GuildOS.DataCollector:CollectResistances()
        if not GuildOS.Resistances then
            GuildOS:Print(L["Not available on this client."])   -- no resistance gear on retail (#184)
        elseif r then
            GuildOS:Print(string.format(
                "Resistances (max wearable) - Shadow %d | Nature %d | Frost %d | Fire %d | Arcane %d",
                r.shadow or 0, r.nature or 0, r.frost or 0, r.fire or 0, r.arcane or 0))
        else
            GuildOS:Print("Resistance scan unavailable.")
        end
    elseif msg == "debug errors" then
        GuildOS:ShowErrors()
    elseif msg == "style" or msg:match("^style%s") then
        -- The interface style (#122): list, switch, or show the Forever pieces side by side.
        local arg = strtrim((msg:gsub("^style%s*", ""))):lower()
        if arg == "" then
            GuildOS.Style:PrintList()
        elseif arg == "preview" then
            GuildOS.Style:ShowPreview()
        else
            GuildOS.Style:Apply(arg)
        end
    elseif msg == "debug probe" then
        -- Client facts for the WoW: Forever beta, into GuildOSDB.probe (ADR-0015).
        if GuildOS.Probe then GuildOS.Probe:Run() end
    elseif msg == "debug probe chat" then
        -- Whether chat from a timer gets through, measured (issue #75).
        if GuildOS.Probe then GuildOS.Probe:RunChat() end
    elseif msg == "debug probe invite" then
        -- What needs a key press here, measured without inviting anybody (#449, specs/salao/convites.md).
        if GuildOS.Probe then GuildOS.Probe:RunInvite() end
    elseif msg == "debug probe channel" then
        -- Whether an addon message may go through a created channel, measured (specs/071-o-recrutamento).
        if GuildOS.Probe then GuildOS.Probe:RunChannel() end
    elseif msg == "reset" then
        GuildOS:AskEraseGuildData()
    elseif msg == "recruit" or msg:match("^recruit%s") then
        local rest = msg:gsub("^recruit%s*", "")
        local args = {}
        for word in rest:gmatch("%S+") do
            table.insert(args, word)
        end
        if GuildOS.Recruitment then
            GuildOS.Recruitment:HandleCommand(args)
        end
    elseif msg == "consumables" or msg == "cons" then
        if GuildOS.ConsumableChecker then
            local results = GuildOS.ConsumableChecker:CheckRaid()
            if results then
                local missing = GuildOS.ConsumableChecker:GetMissingCount(results)
                GuildOS:Print(string.format(L["Consumable check done. %d players missing buffs."], missing))
                -- Retail: what the client could not read is said apart, never counted as missing (#187).
                local unknown = GuildOS.ConsumableChecker:GetUnknownCount(results)
                if unknown > 0 then
                    GuildOS:Print(string.format(L["%d could not be read (out of range, or hidden by the game)."], unknown))
                end
            end
        else
            GuildOS:Print(L["Not available on this client."])
        end
    elseif msg == "consreport" then
        if GuildOS.ConsumableChecker then
            GuildOS.ConsumableChecker:ReportToChat("RAID")
        else
            GuildOS:Print(L["Not available on this client."])
        end
    elseif msg == "trial" or msg:match("^trial%s") then
        -- The roster's key, so a guildmate on a connected realm is found as the roster menu finds
        -- them: the whole rest when it is somebody (two words on Forever), else the first word, as
        -- it always was (issue #177).
        local rest = strtrim((msg:gsub("^trial%s*", "")))
        local key = GuildOS:RosterKey(rest)
        local name = rest:match("^(%S+)")
        if not key and name then key = GuildOS:RosterKey(name) or GuildOS:GetPlayerKey(name) end
        if key and GuildOS.TrialTracker then
            GuildOS.TrialTracker:AddTrial(key)
        else
            GuildOS:Print(L["Usage: /guildos trial <PlayerName>"])
        end
    elseif msg == "note" or msg:match("^note%s") then
        local rest = msg:gsub("^note%s*", "")
        -- A Forever name is two words, and the note lands on the key the roster gives (issue #49).
        local target, noteText = GuildOS:SplitNameAndText(rest)
        if target and noteText and GuildOS.OfficerNotes then
            local key = GuildOS:RosterKey(target)
            -- Somebody off the roster still gets the note (the PUG inspector reads them), but
            -- the officer is told: "Lethaniel" on Forever is nobody's sheet.
            if GuildOS.OfficerNotes:AddNote(key or GuildOS:GetPlayerKey(target), noteText) then
                GuildOS:Print(key and (L["Note added for "] .. target)
                    or string.format(L["Note added for %s, who matches no single guild member: check the full name."], target))
            end
        else
            GuildOS:Print(L["Usage: /guildos note <PlayerName> <text>"])
        end
    elseif msg == "offer" or msg:match("^offer%s") then
        -- /gos offer [item link]: retail's loot council by trade (issue #185); the link keeps its case.
        local link = strtrim((msg:gsub("^offer%s*", "")))
        if not GuildOS.TradeCouncil then
            GuildOS:Print(L["Not available on this client."])
        elseif link == "" then
            GuildOS:ShowTradeCouncil()
        else
            GuildOS.TradeCouncil:Offer(link)
        end
    elseif msg == "lm undo" then
        -- /guildos lm undo - take the last award back (issue #294), as the Master Loot window's button
        if GuildOS.LootMaster then
            local award, why = GuildOS.LootMaster:UndoLastAward()
            GuildOS:Print(award and string.format(L["|cffFFD700Undone:|r %s"], award.link) or why)
        end
    elseif msg == "lm" or msg == "lootmaster" then
        local status = GuildOS:LootMasterStatus()
        if status then GuildOS:Print(status) end
    elseif msg:match("^lm announce") then
        -- /guildos lm announce - manually announce item from target tooltip
        GuildOS:Print(L["Open loot window as Master Looter to announce items."])
    elseif msg == "web" or msg:match("^web%s") or msg == "companion" or msg:match("^companion%s") then
        -- /guildos web [on|off] - the string you paste into the web companion.
        local C = GuildOS.Companion
        local arg = C and msg:match("^%S+%s+(%S+)")
        if C and (arg == "on" or arg == "off") then
            C:SetEnabled(arg == "on")
            GuildOS:Print(arg == "on" and L["Web companion enabled."] or L["Web companion disabled."])
        else
            GuildOS:ShowWebString()
        end
    elseif msg == "roster" or msg:match("^roster%s") then
        -- /guildos roster [invite|groups|trim] — the roster the website planned: the raid of the window when
        -- there is one (issue #400), as the Web tab's buttons.
        local I = GuildOS.CompanionImport
        local sub = I and msg:match("^roster%s+(%S+)")
        if not I then
            GuildOS:Print(L["|cffFF4444Export failed:|r "] .. "CompanionImport")
        elseif sub == "invite" then
            local n, here, err, offline = I:InviteAll()
            if err then GuildOS:Print(err)
            else GuildOS:Print(string.format(L["Invited %d, already here %d."], n, here)) end
            local off = I.OfflineLine(offline)
            if off then GuildOS:Print(off) end
        elseif sub == "groups" then
            local moved, err = I:OrganizeGroups()
            if err then GuildOS:Print(err)
            else GuildOS:Print(string.format(L["Moved %d into their groups."], moved)) end
        elseif sub == "trim" then
            -- Out of the group whoever is not in the plan, after asking (issue #292).
            I:AskTrim()
        elseif sub == "plan" and GuildOS.RaidPlan then
            -- The night's notes, tasks and loot rules from the site (issue #296).
            GuildOS.RaidPlan:Show()
        else
            GuildOS:ShowImportPopup()
        end
    elseif msg == "raid start" then
        -- /guildos raid start — one step of the Iniciar raide button, as its click (issue #400): typed, it is a key
        -- press, which WoW: Forever lets an invite out of. On the raid near now (ButtonRaid: the site's, or one pasted
        -- by hand), never a kept raid days away; with none, it says no raid starts around this time. The line it
        -- prints starts with the raid's name.
        local I, RS = GuildOS.CompanionImport, GuildOS.RaidStart
        if I and RS then RS:Click(I:ButtonRaid(), true) end
    elseif msg == "exportatt" or msg == "exportattendance" then
        if GuildOS.RaidTracker then
            local json, err = GuildOS.RaidTracker:ExportForTMB()
            if json then
                GuildOS:ShowExportPopup(L["Attendance Export"], json)
            else
                GuildOS:Print(L["|cffFF4444Export failed:|r "] .. (err or L["unknown error"]))
            end
        end
    elseif msg == "export" or msg:match("^export%s") then
        -- /guildos export <roster|attendance|loot|readiness|standings|equity> [csv|tsv|discord]
        local rest = strtrim((msg:gsub("^export%s*", "")))
        local dataset, fmt = rest:match("^(%S*)%s*(%S*)$")
        dataset = (dataset and dataset ~= "") and dataset or "roster"
        fmt = (fmt and fmt ~= "") and fmt or "csv"
        local text, title = nil, nil
        if GuildOS.Exporter then
            text, title = GuildOS.Exporter:Build(dataset, fmt)
        end
        if text then
            GuildOS:ShowExportPopup(string.format("%s (%s)", title or L["Export"], fmt), text)
        elseif title == "absent" then
            GuildOS:Print(L["Not available on this client."])
        elseif title == "officer" then
            GuildOS:Print(L["|cffFF4444Officers only.|r"])
        elseif GuildOS.Exporter then
            GuildOS:Print(string.format(L["Usage: /guildos export <%s> [csv|tsv|discord]"], GuildOS.Exporter:Names()))
        end
    elseif msg == "wish" or msg:match("^wish%s") then
        if not GuildOS:IsOfficer() then
            GuildOS:Print(L["|cffFF4444Wishlist is currently available to officers only.|r"])
            return
        end
        local rest = strtrim((msg:gsub("^wish%s*", "")))
        if rest == "" or rest == "list" then
            -- Show wishlist frame
            GuildOS:ShowWishlistFrame()
        elseif rest:match("^remove%s+") then
            local link = rest:match("^remove%s+(.+)$")
            local itemId = link and tonumber(link:match("item:(%d+)"))
            if itemId and GuildOS.Wishlist then
                GuildOS.Wishlist:RemoveFromWishlist(itemId)
            else
                GuildOS:Print(L["Usage: /guildos wish remove [itemlink]"])
            end
        else
            -- Treat remainder as an item link to add
            local itemId = tonumber(rest:match("item:(%d+)"))
            if itemId and GuildOS.Wishlist then
                GuildOS.Wishlist:AddToWishlist(itemId, rest, false)
            else
                GuildOS:Print(L["Usage: /guildos wish [itemlink] | /guildos wish remove [itemlink]"])
            end
        end
    elseif msg == "debug mergeraids" then
        GuildOS:MergeRaidSessions()
    elseif msg == "specs" then
        if GuildOS.SpecChecker then
            GuildOS.SpecChecker:ScanGroup()
        end
    elseif msg == "attune" or msg == "attunements" then
        -- Print attunement status for the logged-in character to chat.
        if GuildOS.AttunementTracker then
            local atts = GuildOS.AttunementTracker:ScanAttunements()
            GuildOS:Print(L["|cffFFD700Attunements:|r"])
            for _, att in ipairs(atts) do
                if not att.alwaysComplete then
                    local status
                    if att.complete then
                        status = L["|cff00FF00Done|r"]
                    elseif att.progress and att.progress > 0 then
                        status = format("|cffFFD700%d%%|r", math.floor(att.progress * 100))
                    else
                        status = L["|cffFF4444Not started|r"]
                    end
                    GuildOS:Print(format("  [%s] %s \226\128\148 %s", att.tier, att.name, status))
                end
            end
        else
            GuildOS:Print(L["Not available on this client."])
        end
    elseif msg == "debug attune" then
        -- Debug mode: prints per-quest IsQuestFlaggedCompleted results.
        if GuildOS.AttunementTracker then
            GuildOS:Print("|cffFFD700Attunement debug (per quest):|r")
            for _, attDef in ipairs(GuildOS.AttunementTracker.ATTUNEMENTS) do
                if not attDef.alwaysComplete and attDef.finalQuestId then
                    GuildOS:Print(format("|cffAAAAAA--- %s (final=%d) ---|r", attDef.name, attDef.finalQuestId))
                    for _, q in ipairs(attDef.quests) do
                        if q.ids then
                            local anyDone = false
                            for _, qid in ipairs(q.ids) do
                                if GuildOS.AttunementTracker:IsQuestComplete(qid) then anyDone = true end
                            end
                            local col = anyDone and "|cff00FF00" or "|cffFF4444"
                            local ids = table.concat(q.ids, "/")
                            GuildOS:Print(format("  %s[%s] %s (Aldor|Scryers)|r", col, ids, q.name))
                        else
                            local done = GuildOS.AttunementTracker:IsQuestComplete(q.id)
                            local col = done and "|cff00FF00" or "|cffFF4444"
                            GuildOS:Print(format("  %s[%d] %s|r", col, q.id, q.name))
                        end
                    end
                    if attDef.keyItemId then
                        local count = GuildOS.Compat.GetItemCount(attDef.keyItemId) or 0
                        local col = count > 0 and "|cff00FF00" or "|cffFF4444"
                        GuildOS:Print(format("  %sKey item %d: %d in bags|r", col, attDef.keyItemId, count))
                    end
                end
            end
        else
            GuildOS:Print(L["Not available on this client."])
        end
    elseif msg == "debug dumpquests" and not GuildOS.AttunementTracker then
        GuildOS:Print(L["Not available on this client."])   -- TBC's attunement quests (issue #184)
    elseif msg == "debug dumpquests" then
        -- Dumps all completed quest IDs in the TBC attunement range.
        -- Covers T4/T5/T6 + some headroom for anniversary-specific hidden flags.
        GuildOS:Print("|cffFFD700Completed quests in range 9800-11500:|r")
        local found = 0
        for qid = 9800, 11500 do
            -- Compat, not the tracker: the tracker does not exist outside TBC Anniversary.
            if GuildOS.Compat.IsQuestComplete(qid) then
                -- Try to get the quest title (may be nil for hidden server-side quests)
                local title = nil
                if C_QuestLog and C_QuestLog.GetTitleForQuestID then
                    title = C_QuestLog.GetTitleForQuestID(qid)
                end
                if title and title ~= "" then
                    GuildOS:Print(format("  |cff00FF00[%d]|r %s", qid, title))
                else
                    GuildOS:Print(format("  |cff00FF00[%d]|r |cffAAAAAA(no title \226\128\148 hidden/anniversary quest)|r", qid))
                end
                found = found + 1
            end
        end
        if found == 0 then
            GuildOS:Print("|cffFF4444No completed quests found in that range.|r")
        else
            GuildOS:Print(format("|cffAAAAAA%d quests found. Run on main to compare IDs.|r", found))
        end
    elseif msg == "signup" or msg:match("^signup%s") then
        -- /gos signup <CoreName> [tank|healer|melee|ranged] [note]
        local rest     = strtrim((msg:gsub("^signup%s*", "")))
        local coreName = rest:match("^(%S+)")
        local note     = rest:match("^%S+%s+(.+)$") or ""
        -- A role word right after the core is the role (issue #94); one the class cannot play
        -- falls back to the class's own in BroadcastSignup.
        local word = note:match("^(%S+)")
        local role = word and GuildOS.CoreManager and GuildOS.CoreManager.ROLE_WORDS[word:lower()]
        if role then note = note:match("^%S+%s+(.+)$") or "" end
        if (not coreName or coreName == "") and GuildOS.ShowCoreSignupFrame then
            -- The window, as the Raids tab's button opens it: the way in at any width, and with the
            -- Raids tab switched off (#377).
            GuildOS:ShowCoreSignupFrame()
        elseif not coreName or coreName == "" then
            GuildOS:Print(L["Usage: /gos signup <CoreName> [tank|healer|melee|ranged] [note]"])
        elseif not GuildOS.CoreManager then
            GuildOS:Print(L["Core Manager not loaded."])
        elseif not GuildOS.CoreManager:Exists(coreName) then
            GuildOS:Print(string.format(L["Core \"%s\" not found."], coreName))
        else
            GuildOS.CoreManager:BroadcastSignup(coreName, note, role)
            GuildOS:Print(string.format(L["Sign-up sent for core: %s"], coreName))
        end
    elseif msg == "unsignup" or msg:match("^unsignup%s") then
        -- /gos unsignup <CoreName>  — withdraw your own application
        local coreName = strtrim((msg:gsub("^unsignup%s*", "")))
        if coreName == "" then
            GuildOS:Print(L["Usage: /gos unsignup <CoreName>"])
        elseif GuildOS.CoreManager then
            local playerKey = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
            GuildOS.CoreManager:DeclineSignup(playerKey, coreName)
            GuildOS:Print(string.format(L["Sign-up withdrawn from core: %s"], coreName))
        end
    elseif msg:match("^tempban%s") then
        -- /gos tempban <name> <days> [reason]  — officer-gated inside BanList:Add.
        local rest = strtrim((msg:gsub("^tempban%s+", "")))
        -- Forever's two-word names (issue #49): the name runs up to the days, the first all-digit
        -- word (a name never holds a digit).
        -- With a reason first: a reason that ends in a number must not swallow the name and the days.
        local name, days, reason = rest:match("^(.-)%s+(%d+)%s+(.*)$")
        if not name then name, days = rest:match("^(.-)%s+(%d+)$") end
        name = name and strtrim(name)
        if name == "" then name = nil end
        reason = reason or ""
        local numDays = days and tonumber(days)
        if name and numDays and numDays > 0 then
            if GuildOS.BanList and GuildOS.BanList:Add(name, reason, numDays * 86400) then
                GuildOS:Print(L["Temp-banned "] .. name .. " (" .. days .. L[" days)"])
            end
        else
            GuildOS:Print(L["Usage: /gos tempban <name> <days> [reason]"])
        end
    elseif msg:match("^ban%s") then
        -- /gos ban <name> [reason]  — officer-gated inside BanList:Add.
        local rest = strtrim((msg:gsub("^ban%s+", "")))
        -- "<name>: <reason>" says where the name ends (a two-word Forever name not on the roster: an
        -- ex-member, an applicant). Else a whole two-word name on the roster, as /gos warn reads it (#49).
        local name, reason = rest:match("^([^:]-)%s*:%s*(.*)$")
        if name then
            name = strtrim(name)
            if name == "" then name = nil end
        else
            name, reason = GuildOS:SplitNameAndText(rest)
            if not name and rest ~= "" then name, reason = rest, "" end
            -- A surname client and a first word alone: say how to ban a two-word name.
            if name and reason and reason ~= "" and GuildOS.Client.has.surnames and not name:find(" ", 1, true) then
                GuildOS:Print(string.format(L["Read as %s, reason \"%s\". For a two-word name: /gos ban First Last: reason"], name, reason))
            end
        end
        if name then
            if GuildOS.BanList and GuildOS.BanList:Add(name, reason) then
                GuildOS:Print(L["Banned "] .. name)
            end
        else
            GuildOS:Print(L["Usage: /gos ban <name> [reason]"])
        end
    elseif msg:match("^unban%s") then
        -- /gos unban <name>  — officer-gated inside BanList:Remove.
        local name = strtrim((msg:gsub("^unban%s+", "")))
        if name ~= "" and GuildOS.BanList and GuildOS.BanList:Remove(name) then
            GuildOS:Print(L["Unbanned "] .. name)
        elseif name ~= "" and GuildOS.BanList and GuildOS:IsOfficer() then
            GuildOS:Print(string.format(L["No ban to lift for %s."], name))   -- nothing stood there (#184)
        end
    elseif msg:match("^warn%s") then
        -- /gos warn <name> [reason]  — the Warn window (#403), officers only.
        local name, rest = GuildOS:SplitNameAndText(strtrim((msg:gsub("^warn%s+", ""))))
        name = name or strtrim((msg:gsub("^warn%s+", "")))
        local key = GuildOS:RosterKey(name)
        if not GuildOS:IsOfficer() then
            GuildOS:Print(L["|cffFF4444Officers only.|r"])
        elseif not key then
            GuildOS:Print(string.format(L["%s is not on the guild roster."], name))
        else
            local _, shown = GuildOS:RosterKey(name)
            GuildOS:ShowWarnDialog(key, shown, { reason = rest and strtrim(rest):lower() or nil })
        end
    elseif msg:match("^record%s+term%s") then
        -- /gos record term <days>  — the guild's term for warnings (#402), officers only.
        local days = strtrim((msg:gsub("^record%s+term%s+", "")))
        local ok, why = false, "range"
        if GuildOS.Discipline then ok, why = GuildOS.Discipline:SetTerm(days) end
        if ok then
            GuildOS:Print(string.format(L["Warnings now count for %d days."], GuildOS.Discipline:GetTerm()))
        elseif why == "officer" then
            GuildOS:Print(L["|cffFF4444Officers only.|r"])
        else
            GuildOS:Print(L["Usage: /gos record term <1-365>"])
        end
    elseif msg:match("^record%s") then
        -- /gos record <name>  — a member's disciplinary record (#402), officers only.
        local name = strtrim((msg:gsub("^record%s+", "")))
        local D = GuildOS.Discipline
        if not (D and GuildOS:IsOfficer()) then
            GuildOS:Print(L["|cffFF4444Officers only.|r"])
        elseif name == "" then
            GuildOS:Print(L["Usage: /gos record <name>"])
        else
            local key = GuildOS:RosterKey(name) or GuildOS:GetPlayerKey(name)
            local now, term = GetServerTime(), D:GetTerm()
            local record = D:Record(key)
            GuildOS:Print(string.format(L["%s: step %d, %d warning(s)."], name, D.Step(record, term, now), #record))
            for i = 1, math.min(5, #record) do
                local w = record[i]
                local state = w.revokedAt and L["revoked"] or (D.Active(w, term, now) and L["standing"] or L["lapsed"])
                GuildOS:Print(string.format("  %s  %s  %s (%s)", GuildOS:DateText(w.at or 0), D.ReasonText(w.reason), state, w.by or "?"))
            end
        end
    elseif msg == "bulk" or msg:match("^bulk%s") then
        -- /gos bulk [next | skip | stop] — Leadership > Bulk actions (#420). A typed command is addon code, which may
        -- not run the game's protected rank commands: `next` says who is next; the Next button or a
        -- /click GuildOSBulkNext macro acts.
        if GuildOS.BulkActions then
            GuildOS.BulkActions:Command((msg:gsub("^bulk%s*", "")))
        else
            GuildOS:Print(L["Not available on this client."])
        end
    elseif msg == "queue" or msg:match("^queue%s") then
        -- /gos queue [next | clear | bind <key>]: the officer action queue (#449). The Enter is a key press.
        if GuildOS.ActionQueue then
            GuildOS.ActionQueue:Command((msg:gsub("^queue%s*", "")))
        else
            GuildOS:Print(L["Not available on this client."])
        end
    elseif msg == "altgroup" or msg:match("^altgroup%s") then
        -- /gos altgroup <promote | demote> <name> [rank] (#424): a queue in Leadership > Bulk actions, one alt per click.
        if GuildOS.BulkActions then
            GuildOS.BulkActions:CommandGroup((msg:gsub("^altgroup%s*", "")))
        else
            GuildOS:Print(L["Not available on this client."])
        end
    elseif msg == "birthday" or msg:match("^birthday%s") or msg == "aniversario" or msg:match("^aniversario%s") then
        -- /gos birthday [DD/MM | off] (#428), Settings > Profile's Birthday; an officer adds a name first.
        if GuildOS.Birthdays then GuildOS.Birthdays:Command((msg:gsub("^%a+%s*", ""))) end
    elseif msg == "joindate" or msg:match("^joindate%s") then
        -- /gos joindate [<name> | all | import] (#429): Leadership > Notes and marks.
        if GuildOS.NoteDates then GuildOS.NoteDates:Command((msg:gsub("^joindate%s*", ""))) end
    elseif msg == "safe" or msg:match("^safe%s") then
        -- /gos safe [<name>] (#429): the safe list the bulk actions never remove or demote.
        if GuildOS.MemberMarks then GuildOS.MemberMarks:CommandSafe((msg:gsub("^safe%s*", ""))) end
    elseif msg == "nick" or msg:match("^nick%s") then
        -- /gos nick <name> [nickname] (#429): the officers' nickname, on the tooltip and in chat.
        if GuildOS.MemberMarks then GuildOS.MemberMarks:CommandNick((msg:gsub("^nick%s*", ""))) end
    elseif msg == "altlimit" or msg:match("^altlimit%s") then
        -- /gos altlimit N (#424): the groups with more than N alts, in chat.
        if GuildOS.AltSync then GuildOS.AltSync:CommandLimit((msg:gsub("^altlimit%s*", ""))) end
    elseif msg == "banlist" then
        GuildOS.UI:OpenWindow("management", "ban")
    elseif msg == "autoinvite" or msg:match("^autoinvite%s") or msg == "ai" or msg:match("^ai%s") then
        if GuildOS.Recruitment then
            local rest = strtrim((msg:gsub("^ai%s*", ""):gsub("^autoinvite%s*", "")))
            local a = {}
            for w in rest:gmatch("%S+") do a[#a + 1] = w end
            GuildOS.Recruitment:HandleAutoInviteCommand(a)
        end
    elseif msg == "mentions" or msg:match("^mentions%s") then
        if GuildOS.Mentions then
            local rest = strtrim((msg:gsub("^mentions%s*", "")))
            local a = {}
            for w in rest:gmatch("%S+") do a[#a + 1] = w end
            GuildOS.Mentions:HandleCommand(a)
        end
    elseif msg == "notecmd" or msg:match("^notecmd%s") then
        if GuildOS.NoteCommand then
            local rest = strtrim((msg:gsub("^notecmd%s*", "")))
            local a = {}; for w in rest:gmatch("%S+") do a[#a+1] = w end
            GuildOS.NoteCommand:HandleCommand(a)
        end
    elseif msg == "avail" or msg:match("^avail%s") then
        -- /gos avail [off | notify [on|off] | [tank|healer|dps|any] <text>]
        -- Anchored on "^avail%s" so it can never swallow a sibling verb.
        -- (/gos lfg is already the recruitment beacon inbox, hence "avail".)
        if GuildOS.LFGBoard then
            -- gsub returns (string, count); the extra parens drop the count so it
            -- cannot reach strtrim's optional "characters to trim" argument. The
            -- note here is free text, so "avail 10 man" must not lose its "1".
            local rest = strtrim((msg:gsub("^avail%s*", "")))
            local a = {}; for w in rest:gmatch("%S+") do a[#a+1] = w end
            GuildOS.LFGBoard:HandleCommand(a, rest)
        end
    elseif msg == "open" or msg:match("^open%s") then
        -- /gos open <feature> [sub] — one uniform way to open any feature
        -- tab. A dedicated verb rather than a bare-id fallback: several
        -- feature ids (roster, trials, dkp, alliance) are already verbs
        -- above, and "^trial" would even prefix-match "trials" and eat the
        -- "s" as a player name. "open" itself is not a prefix of, nor
        -- prefixed by, any other verb in this chain.
        local id  = msg:match("^open%s+(%S+)")
        local sub = msg:match("^open%s+%S+%s+(%S+)")
        local def = id and GuildOS.UI and GuildOS.UI.GetFeature and GuildOS.UI:GetFeature(id)
        if def and (def.tab or def.opens) then
            GuildOS.UI:OpenWindow(id, sub)
        else
            GuildOS:Print(L["Usage: /gos open <feature>. Try /gos open roster."])
        end
    else
        -- A bare /gos is the documented way to open the window. An unknown verb opens nothing and points
        -- at the listing (audit C16): a typo used to open the roster.
        local verb = string.match(msg, "%S+")   -- the first word: not a verb of the router (tools/commands-in-ui.lua)
        if verb and DEBUG_ALIAS[verb] then
            -- A diagnostic's old verb with words its alias does not know (/gos probe nonsense): where it lives now.
            GuildOS:Print(string.format(L["Moved: %s"], "|cffFFD700/gos debug " .. (verb == "probe"
                and "probe [chat | channel | invite]" or verb) .. "|r"))
        elseif msg ~= "" then
            GuildOS:Print(string.format(L["Unknown command. Type %s for the list."], "|cffFFD700/gos help|r"))
        else
            GuildOS:ToggleRoster()
        end
    end
end

-- Dispatch: /guildos and /gos (primary)
SlashCmdList["GUILDOS"] = handleCommand

