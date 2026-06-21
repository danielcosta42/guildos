----------------------------------------------------------------------
-- Guild OS - Slash Commands
-- /guildos (primary) and /brutus (legacy alias) dispatch table.
----------------------------------------------------------------------

-- Primary slash command: /guildos and /gos
SLASH_GUILDOS1 = "/guildos"
SLASH_GUILDOS2 = "/gos"

-- Legacy slash commands kept for backward compatibility: /brutus and /br
SLASH_BRUTUS1 = "/brutus"
SLASH_BRUTUS2 = "/br"

local L = BRutus.L

local function handleCommand(msg)
    msg = strtrim(msg or "")
    if msg == "scan" then
        if BRutus.DataCollector then
            BRutus.DataCollector:CollectMyData()
            BRutus:Print(L["Data collected."])
        end
    elseif msg == "sync" then
        if BRutus.CommSystem then
            BRutus.CommSystem:FullSync()
        end
    elseif msg == "points" or msg == "dkp" then
        if BRutus.ShowPointsFrame then
            BRutus:ShowPointsFrame()
        end
    elseif msg == "equity" or msg == "lootequity" then
        if BRutus.LootEquity then
            BRutus.LootEquity:PrintSummary(15)
        end
    elseif msg == "digest" then
        if BRutus.Digest then
            BRutus.Digest:Show()
        end
    elseif msg == "backup" then
        if BRutus.Backup then BRutus.Backup:ShowExport() end
    elseif msg == "restore" then
        if BRutus.Backup then BRutus.Backup:ShowRestore() end
    elseif msg == "bulletin" or msg == "board" then
        if BRutus.Bulletin then BRutus.Bulletin:Show() end
    elseif msg == "minimap" then
        if BRutus.ToggleMinimapButton then
            local shown = BRutus:ToggleMinimapButton()
            BRutus:Print(shown and L["Minimap button shown."] or L["Minimap button hidden."])
        end
    elseif msg == "prune" then
        local removed = BRutus:PruneStaleData()
        BRutus:Print(string.format(L["Pruned %d member(s) who left the guild."], removed))
    elseif msg == "debug" then
        BRutus.Logger.debug = not BRutus.Logger.debug
        BRutus:Print(BRutus.Logger.debug and L["Debug mode ON."] or L["Debug mode OFF."])
    elseif msg == "errors" then
        local ring = (BRutus.State and BRutus.State.errors) or {}
        if #ring == 0 then
            BRutus:Print(L["No errors recorded this session."])
        else
            BRutus:Print(string.format(L["%d recent error(s):"], #ring))
            for i = math.max(1, #ring - 9), #ring do
                BRutus:Print("|cffFF4444" .. (ring[i].msg or "?") .. "|r")
            end
        end
    elseif msg == "reset" then
        if BRutus.guildKey then
            if GuildOSDB then GuildOSDB[BRutus.guildKey] = nil end
            if BRutusDB  then BRutusDB[BRutus.guildKey]  = nil end
        end
        ReloadUI()
    elseif msg:match("^recruit") then
        local rest = msg:gsub("^recruit%s*", "")
        local args = {}
        for word in rest:gmatch("%S+") do
            table.insert(args, word)
        end
        if BRutus.Recruitment then
            BRutus.Recruitment:HandleCommand(args)
        end
    elseif msg == "consumables" or msg == "cons" then
        if BRutus.ConsumableChecker then
            local results = BRutus.ConsumableChecker:CheckRaid()
            if results then
                local missing = BRutus.ConsumableChecker:GetMissingCount(results)
                BRutus:Print(string.format(L["Consumable check done. %d players missing buffs."], missing))
            end
        end
    elseif msg == "consreport" then
        if BRutus.ConsumableChecker then
            BRutus.ConsumableChecker:ReportToChat("RAID")
        end
    elseif msg:match("^trial") then
        local rest = msg:gsub("^trial%s*", "")
        local name = rest:match("^(%S+)")
        if name and BRutus.TrialTracker then
            local realm = GetRealmName()
            local key = name .. "-" .. realm
            BRutus.TrialTracker:AddTrial(key)
        else
            BRutus:Print(L["Usage: /guildos trial <PlayerName>"])
        end
    elseif msg:match("^note") then
        local rest = msg:gsub("^note%s*", "")
        local target, noteText = rest:match("^(%S+)%s+(.+)$")
        if target and noteText and BRutus.OfficerNotes then
            local realm = GetRealmName()
            local key = target .. "-" .. realm
            if BRutus.OfficerNotes:AddNote(key, noteText) then
                BRutus:Print(L["Note added for "] .. target)
            end
        else
            BRutus:Print(L["Usage: /guildos note <PlayerName> <text>"])
        end
    elseif msg == "lm" or msg == "lootmaster" then
        if BRutus.LootMaster then
            if BRutus.LootMaster:IsMasterLooter() then
                BRutus:Print(L["Loot Master mode active. Open loot to start."])
            else
                BRutus:Print(L["You are not the Master Looter."])
            end
        end
    elseif msg:match("^lm announce") then
        -- /guildos lm announce - manually announce item from target tooltip
        BRutus:Print(L["Open loot window as Master Looter to announce items."])
    elseif msg == "exportatt" or msg == "exportattendance" then
        if BRutus.RaidTracker then
            local json, err = BRutus.RaidTracker:ExportForTMB()
            if json then
                BRutus:ShowExportPopup(L["Attendance Export"], json)
            else
                BRutus:Print(L["|cffFF4444Export failed:|r "] .. (err or L["unknown error"]))
            end
        end
    elseif msg:match("^export") then
        -- /guildos export <roster|attendance|loot|readiness|standings> [csv|tsv|discord]
        local rest = strtrim(msg:gsub("^export%s*", ""))
        local dataset, fmt = rest:match("^(%S*)%s*(%S*)$")
        dataset = (dataset and dataset ~= "") and dataset or "roster"
        fmt = (fmt and fmt ~= "") and fmt or "csv"
        local text, title = nil, nil
        if BRutus.Exporter then
            text, title = BRutus.Exporter:Build(dataset, fmt)
        end
        if text then
            BRutus:ShowExportPopup(string.format("%s (%s)", title or L["Export"], fmt), text)
        else
            BRutus:Print(L["Usage: /guildos export <roster|attendance|loot|readiness|standings> [csv|tsv|discord]"])
        end
    elseif msg:match("^wish") then
        if not BRutus:IsOfficer() then
            BRutus:Print(L["|cffFF4444Wishlist is currently available to officers only.|r"])
            return
        end
        local rest = strtrim(msg:gsub("^wish%s*", ""))
        if rest == "" or rest == "list" then
            -- Show wishlist frame
            BRutus:ShowWishlistFrame()
        elseif rest:match("^remove%s+") then
            local link = rest:match("^remove%s+(.+)$")
            local itemId = link and tonumber(link:match("item:(%d+)"))
            if itemId and BRutus.Wishlist then
                BRutus.Wishlist:RemoveFromWishlist(itemId)
            else
                BRutus:Print(L["Usage: /guildos wish remove [itemlink]"])
            end
        else
            -- Treat remainder as an item link to add
            local itemId = tonumber(rest:match("item:(%d+)"))
            if itemId and BRutus.Wishlist then
                BRutus.Wishlist:AddToWishlist(itemId, rest, false)
            else
                BRutus:Print(L["Usage: /guildos wish [itemlink] | /guildos wish remove [itemlink]"])
            end
        end
    elseif msg == "mergeraids" then
        if BRutus.RaidTracker then
            BRutus:Print(L["Merging duplicate raid sessions\226\128\166"])
            local count = BRutus.RaidTracker:MergeDuplicateSessions()
            if count == 0 then
                BRutus:Print(L["|cffAAAAAA[Guild OS] No duplicates found.|r"])
            end
        end
    elseif msg == "specs" then
        if BRutus.SpecChecker then
            BRutus.SpecChecker:ScanGroup()
        end
    elseif msg == "attune" or msg == "attunements" then
        -- Print attunement status for the logged-in character to chat.
        if BRutus.AttunementTracker then
            local atts = BRutus.AttunementTracker:ScanAttunements()
            BRutus:Print(L["|cffFFD700Attunements:|r"])
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
                    BRutus:Print(format("  [%s] %s \226\128\148 %s", att.tier, att.name, status))
                end
            end
        end
    elseif msg == "attune debug" or msg == "attunements debug" then
        -- Debug mode: prints per-quest IsQuestFlaggedCompleted results.
        if BRutus.AttunementTracker then
            BRutus:Print("|cffFFD700Attunement debug (per quest):|r")
            for _, attDef in ipairs(BRutus.AttunementTracker.ATTUNEMENTS) do
                if not attDef.alwaysComplete and attDef.finalQuestId then
                    BRutus:Print(format("|cffAAAAAA--- %s (final=%d) ---|r", attDef.name, attDef.finalQuestId))
                    for _, q in ipairs(attDef.quests) do
                        local done = BRutus.AttunementTracker:IsQuestComplete(q.id)
                        local col = done and "|cff00FF00" or "|cffFF4444"
                        BRutus:Print(format("  %s[%d] %s|r", col, q.id, q.name))
                    end
                    if attDef.keyItemId then
                        local count = GetItemCount(attDef.keyItemId) or 0
                        local col = count > 0 and "|cff00FF00" or "|cffFF4444"
                        BRutus:Print(format("  %sKey item %d: %d in bags|r", col, attDef.keyItemId, count))
                    end
                end
            end
        end
    elseif msg == "attune dumpquests" then
        -- Dumps all completed quest IDs in the TBC attunement range.
        -- Covers T4/T5/T6 + some headroom for anniversary-specific hidden flags.
        BRutus:Print("|cffFFD700Completed quests in range 9800-11500:|r")
        local found = 0
        for qid = 9800, 11500 do
            if BRutus.AttunementTracker:IsQuestComplete(qid) then
                -- Try to get the quest title (may be nil for hidden server-side quests)
                local title = nil
                if C_QuestLog and C_QuestLog.GetTitleForQuestID then
                    title = C_QuestLog.GetTitleForQuestID(qid)
                end
                if title and title ~= "" then
                    BRutus:Print(format("  |cff00FF00[%d]|r %s", qid, title))
                else
                    BRutus:Print(format("  |cff00FF00[%d]|r |cffAAAAAA(no title \226\128\148 hidden/anniversary quest)|r", qid))
                end
                found = found + 1
            end
        end
        if found == 0 then
            BRutus:Print("|cffFF4444No completed quests found in that range.|r")
        else
            BRutus:Print(format("|cffAAAAAA%d quests found. Run on main to compare IDs.|r", found))
        end
    else
        BRutus:ToggleRoster()
    end
end

-- Dispatch: /guildos and /gos (primary)
SlashCmdList["GUILDOS"] = handleCommand

-- Dispatch: /brutus and /br (legacy alias — kept for backward compatibility)
SlashCmdList["BRUTUS"]  = handleCommand
