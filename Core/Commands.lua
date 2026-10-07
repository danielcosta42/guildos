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

local function helpHeader(text)
    GuildOS:Print(HELP_HEADER_COLOR .. text .. "|r")
end

local function helpLine(verb, desc)
    GuildOS:Print("  " .. HELP_CMD_COLOR .. verb .. "|r  " .. desc)
end

local function printHelp()
    GuildOS:Print(HELP_CMD_COLOR .. L["Guild OS commands (/gos or /guildos):"] .. "|r")

    helpHeader(L["General"])
    helpLine("/gos",             L["Open Guild OS"])
    helpLine("/gos open <feature>", L["Open a tab (roster, raids, loot, guild...)"])
    helpLine("/gos find <text>", L["Search members by name, class, level or note"])
    helpLine("/gos analytics",   L["Guild analytics and activity stats"])
    helpLine("/gos map",         L["Open the live guild map"])
    helpLine("/gos pug",         L["Check who you're grouped with"])
    helpLine("/gos calendar",    L["Guild calendar and events"])
    helpLine("/gos polls",       L["Guild polls"])
    helpLine("/gos bulletin",    L["Guild bulletin board"])
    helpLine("/gos cta [type] [message]", L["Call to Arms: rally the guild (officers)"])
    helpLine("/gos ally",        L["Alliance status and allied guilds"])

    helpHeader(L["Raid and loot"])
    helpLine("/gos lm",            L["Master Loot helper status"])
    helpLine("/gos points",        L["Points and DKP window"])
    if GuildOS.ConsumableChecker then  -- TBC content (ADR-0014)
        helpLine("/gos cons",      L["Check raid consumables"])
    end
    helpLine("/gos specs",         L["Scan group talent specs"])
    helpLine("/gos export <what>", L["Export roster, attendance or loot"])
    helpLine("/gos web [on|off]",  L["Copy your guild into the web companion"])
    helpLine("/gos roster",        L["Bring the raid roster in from the website"])

    helpHeader(L["Personal"])
    helpLine("/gos avail",         L["List yourself as available for a group"])
    helpLine("/gos signup <core>", L["Sign up for a raid core"])
    helpLine("/gos mentions",      L["Name mention alerts"])
    helpLine("/gos myalts",        L["Detect and link your own alts"])
    if GuildOS.AttunementTracker then  -- TBC content (ADR-0014)
        helpLine("/gos attune",    L["Your attunement progress"])
    end
    helpLine("/gos craft <item>",  L["Who can craft an item"])

    helpHeader(L["Diagnostics"])
    helpLine("/gos sync",     L["Force a full data sync"])
    helpLine("/gos selftest", L["Run the built-in self test"])
    helpLine("/gos errors",   L["Show recent errors"])
    helpLine("/gos probe",    L["Record this client's facts for the Forever beta"])
    helpLine("/gos probe chat", L["Post two test lines in guild chat to see whether an addon may post on its own"])
    helpLine("/gos debug",    L["Toggle debug output"])

    -- These verbs are refused inside their own modules for non-officers, so
    -- showing them to a member would only advertise commands that do nothing.
    if GuildOS:IsOfficer() then
        helpHeader(L["Officers"])
        helpLine("/gos ban <name>",            L["Ban a player from invites"])
        helpLine("/gos tempban <name> <days>", L["Ban a player for a number of days"])
        helpLine("/gos unban <name>",          L["Lift a ban"])
        helpLine("/gos banlist",               L["Open the ban list"])
        helpLine("/gos autoinvite",            L["Auto-invite settings"])
        helpLine("/gos note <name> <text>",    L["Add an officer note"])
        helpLine("/gos wish",                  L["Open the loot wishlist"])
        helpLine("/gos scout",                 L["Scan for unguilded recruits"])
        helpLine("/gos ally create <tag> <name>", L["Found an alliance with other guilds"])
        helpLine("/gos ally invite <officer>",    L["Invite a guild into the alliance"])
        helpLine("/gos ally leave",               L["Leave the alliance"])
    end
end

local function handleCommand(msg)
    msg = strtrim(msg or "")
    -- Deliberately the first branch: "help", "?" and "commands" are exact
    -- literals, so this can never swallow another verb, and sitting at the top
    -- means no present or future prefix pattern below can ever swallow them.
    if msg == "help" or msg == "?" or msg == "commands" then
        printHelp()
    elseif msg == "scan" then
        if GuildOS.DataCollector then
            GuildOS.DataCollector:CollectMyData()
            GuildOS:Print(L["Data collected."])
        end
    elseif msg == "selftest" then
        if GuildOS.SelfTest then GuildOS.SelfTest:Run() end
    elseif msg == "myalts" then
        if GuildOS.AltAutoDetect then GuildOS.AltAutoDetect:PromptNow() end
    elseif msg == "sync" then
        if GuildOS.CommSystem then
            GuildOS.CommSystem:FullSync()
        end
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
        -- Cross-guild federation. Officer-only verbs refuse inside the module,
        -- so this stays a thin router.
        if GuildOS.Alliance then
            GuildOS.Alliance:HandleCommand(msg:match("^%a+%s+(.*)$") or "")
        end
    elseif msg == "analytics" or msg == "stats" then
        if GuildOS.GuildAnalytics then GuildOS.GuildAnalytics:Show() end
    elseif msg == "polls" or msg == "poll" then
        if GuildOS.Polls then GuildOS.Polls:Show() end
    elseif msg == "calendar" or msg == "cal" or msg == "events" then
        if GuildOS.ShowCalendar then GuildOS:ShowCalendar() end
    elseif msg == "search" or msg:match("^find") then
        if GuildOS.Search then
            local q = strtrim((msg:gsub("^find%s*", "")))
            GuildOS.Search:Show(q ~= "search" and q or "")
        end
    elseif msg:match("^craft") then
        -- /guildos craft <item link or id> — who can craft this, guild + realm.
        local arg = strtrim((msg:gsub("^craft%s*", "")))
        local itemId = tonumber(arg:match("item:(%d+)")) or tonumber(arg:match("^(%d+)$"))
        if not itemId then
            -- No item given: open the Craft Finder popup instead.
            if GuildOS.ShowCraftFinder then
                GuildOS:ShowCraftFinder()
            else
                GuildOS:Print(L["Usage: /guildos craft [item link or id]"])
            end
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
            -- Alliance: straight from the synced directory, offline crafters included.
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
        -- Anyone: browse guilds recruiting nearby (heard over the mesh).
        if GuildOS.ShowRecruitInbox then GuildOS:ShowRecruitInbox() end
    elseif msg == "map" or msg == "guildmap" then
        -- Anyone: open the live guild map (world map pins + list overlay).
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
    elseif msg == "prune" then
        local removed = GuildOS:PruneStaleData()
        GuildOS:Print(string.format(L["Pruned %d member(s) who left the guild."], removed))
    elseif msg == "debug" then
        GuildOS.Logger.debug = not GuildOS.Logger.debug
        GuildOS:Print(GuildOS.Logger.debug and L["Debug mode ON."] or L["Debug mode OFF."])
    elseif msg == "resscan" then
        -- Diagnostic: run the resistance scan (equipped + bags) and print the max
        -- wearable per school, so the tooltip-based read can be verified in-game.
        local r = GuildOS.DataCollector and GuildOS.DataCollector:CollectResistances()
        if r then
            GuildOS:Print(string.format(
                "Resistances (max wearable) - Shadow %d | Nature %d | Frost %d | Fire %d | Arcane %d",
                r.shadow or 0, r.nature or 0, r.frost or 0, r.fire or 0, r.arcane or 0))
        else
            GuildOS:Print("Resistance scan unavailable.")
        end
    elseif msg == "errors" then
        -- Start-up problems first: the ring below is capped and shared with
        -- runtime errors, so it can already have lost them.
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
    elseif msg == "probe" then
        -- Client facts for the WoW: Forever beta, into GuildOSDB.probe (ADR-0015).
        if GuildOS.Probe then GuildOS.Probe:Run() end
    elseif msg == "probe chat" then
        -- Whether chat from a timer gets through, measured (issue #75).
        if GuildOS.Probe then GuildOS.Probe:RunChat() end
    elseif msg == "reset" then
        if GuildOS.guildKey then
            if GuildOSDB then GuildOSDB[GuildOS.guildKey] = nil end
        end
        ReloadUI()
    elseif msg:match("^recruit") then
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
    elseif msg:match("^trial") then
        local rest = msg:gsub("^trial%s*", "")
        local name = rest:match("^(%S+)")
        if name and GuildOS.TrialTracker then
            local key = GuildOS:GetPlayerKey(name)
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
    elseif msg == "lm" or msg == "lootmaster" then
        if GuildOS.LootMaster then
            if GuildOS.LootMaster:IsMasterLooter() then
                GuildOS:Print(L["Loot Master mode active. Open loot to start."])
            else
                GuildOS:Print(L["You are not the Master Looter."])
            end
        end
    elseif msg:match("^lm announce") then
        -- /guildos lm announce - manually announce item from target tooltip
        GuildOS:Print(L["Open loot window as Master Looter to announce items."])
    elseif msg:match("^web") or msg:match("^companion") then
        -- /guildos web [on|off] - the string you paste into the web companion.
        local C = GuildOS.Companion
        local arg = C and msg:match("^%S+%s+(%S+)")
        if C and (arg == "on" or arg == "off") then
            C:SetEnabled(arg == "on")
            GuildOS:Print(arg == "on" and L["Web companion enabled."] or L["Web companion disabled."])
        elseif C and not C:IsEnabled() then
            GuildOS:Print(L["The web companion is off. Turn it on with /gos web on."])
        elseif C then
            local text, countOrErr = C:Build()
            if text then
                GuildOS:ShowExportPopup(
                    string.format(L["Web Companion (%d members)"], countOrErr), text)
            else
                GuildOS:Print(L["|cffFF4444Export failed:|r "] .. tostring(countOrErr))
            end
        end
    elseif msg:match("^roster") then
        -- /guildos roster [invite|groups] — the roster the website planned.
        local I = GuildOS.CompanionImport
        local sub = I and msg:match("^roster%s+(%S+)")
        if not I then
            GuildOS:Print(L["|cffFF4444Export failed:|r "] .. "CompanionImport")
        elseif sub == "invite" then
            local n, skipped, err = I:InviteAll()
            if err then GuildOS:Print(err)
            else GuildOS:Print(string.format(L["Invited %d, already here %d."], n, skipped)) end
        elseif sub == "groups" then
            local moved, err = I:OrganizeGroups()
            if err then GuildOS:Print(err)
            else GuildOS:Print(string.format(L["Moved %d into their groups."], moved)) end
        else
            GuildOS:ShowImportPopup()
        end
    elseif msg == "exportatt" or msg == "exportattendance" then
        if GuildOS.RaidTracker then
            local json, err = GuildOS.RaidTracker:ExportForTMB()
            if json then
                GuildOS:ShowExportPopup(L["Attendance Export"], json)
            else
                GuildOS:Print(L["|cffFF4444Export failed:|r "] .. (err or L["unknown error"]))
            end
        end
    elseif msg:match("^export") then
        -- /guildos export <roster|attendance|loot|readiness|standings> [csv|tsv|discord]
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
        else
            GuildOS:Print(L["Usage: /guildos export <roster|attendance|loot|readiness|standings> [csv|tsv|discord]"])
        end
    elseif msg:match("^wish") then
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
    elseif msg == "mergeraids" then
        if GuildOS.RaidTracker then
            GuildOS:Print(L["Merging duplicate raid sessions\226\128\166"])
            local count = GuildOS.RaidTracker:MergeDuplicateSessions()
            if count == 0 then
                GuildOS:Print(L["|cffAAAAAA[Guild OS] No duplicates found.|r"])
            end
        end
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
    elseif msg == "attune debug" or msg == "attunements debug" then
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
    elseif msg == "attune dumpquests" then
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
    elseif msg:match("^signup") then
        -- /gos signup <CoreName> [tank|healer|melee|ranged] [note]
        local rest     = strtrim((msg:gsub("^signup%s*", "")))
        local coreName = rest:match("^(%S+)")
        local note     = rest:match("^%S+%s+(.+)$") or ""
        -- A role word right after the core is the role (issue #94); one the class cannot play
        -- falls back to the class's own in BroadcastSignup.
        local word = note:match("^(%S+)")
        local role = word and GuildOS.CoreManager and GuildOS.CoreManager.ROLE_WORDS[word:lower()]
        if role then note = note:match("^%S+%s+(.+)$") or "" end
        if not coreName or coreName == "" then
            GuildOS:Print(L["Usage: /gos signup <CoreName> [tank|healer|melee|ranged] [note]"])
        elseif not GuildOS.CoreManager then
            GuildOS:Print(L["Core Manager not loaded."])
        elseif not GuildOS.CoreManager:Exists(coreName) then
            GuildOS:Print(string.format(L["Core \"%s\" not found."], coreName))
        else
            GuildOS.CoreManager:BroadcastSignup(coreName, note, role)
            GuildOS:Print(string.format(L["Sign-up sent for core: %s"], coreName))
        end
    elseif msg:match("^unsignup") then
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
        local name, days, reason = rest:match("^(%S+)%s+(%d+)%s*(.*)$")
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
        local name, reason = rest:match("^(%S+)%s*(.*)$")
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
        end
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
        if def and def.tab then
            GuildOS.UI:OpenWindow(id, sub)
        else
            GuildOS:Print(L["Usage: /gos open <feature>. Try /gos open roster."])
        end
    else
        -- Unknown verb: point at the listing, then keep the historic
        -- behaviour of opening the roster. A bare /gos is the documented way
        -- to open the roster and is not a typo, so it stays silent.
        if msg ~= "" then
            GuildOS:Print(string.format(L["Unknown command. Type %s for the list."], "|cffFFD700/gos help|r"))
        end
        GuildOS:ToggleRoster()
    end
end

-- Dispatch: /guildos and /gos (primary)
SlashCmdList["GUILDOS"] = handleCommand

