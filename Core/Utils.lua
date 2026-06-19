----------------------------------------------------------------------
-- BRutus Guild Manager - Utilities
-- Pure helper functions. No business logic, no persistent state writes.
----------------------------------------------------------------------
local L = BRutus.L

----------------------------------------------------------------------
-- Alt / Main linking (account-wide attunement propagation)
----------------------------------------------------------------------
function BRutus:LinkAlt(altKey, mainKey)
    if not self:IsOfficer() then return false end
    if not altKey or not mainKey or altKey == mainKey then return false end
    self.db.altLinks = self.db.altLinks or {}
    -- Prevent circular links: mainKey must not itself be an alt
    if self.db.altLinks[mainKey] then
        self:Print(L["Error: "] .. mainKey .. L[" is already an alt. Unlink it first."])
        return false
    end
    self.db.altLinks[altKey] = mainKey
    if self.CommSystem then
        self.CommSystem:BroadcastAltLinks()
    end
    return true
end

function BRutus:UnlinkAlt(altKey)
    if not self:IsOfficer() then return false end
    self.db.altLinks = self.db.altLinks or {}
    self.db.altLinks[altKey] = nil
    if self.CommSystem then
        self.CommSystem:BroadcastAltLinks()
    end
    return true
end

-- Returns all keys in the same account group as playerKey (includes playerKey itself)
function BRutus:GetLinkedChars(playerKey)
    local altLinks = (self.db and self.db.altLinks) or {}
    -- Resolve canonical main
    local mainKey = altLinks[playerKey] or playerKey
    local result = { mainKey }
    local seen = { [mainKey] = true }
    for altK, mK in pairs(altLinks) do
        if mK == mainKey and not seen[altK] then
            seen[altK] = true
            table.insert(result, altK)
        end
    end
    return result
end

----------------------------------------------------------------------
-- General helpers
----------------------------------------------------------------------
function BRutus:DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = self:DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function BRutus:GetClassColor(class)
    local c = self.ClassColors[class]
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

function BRutus:GetClassColorHex(class)
    local r, g, b = self:GetClassColor(class)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

function BRutus:ColorText(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

function BRutus:FormatItemLevel(ilvl)
    if not ilvl or ilvl == 0 then return "|cff888888--|r" end
    local color
    if ilvl >= 141 then      -- T6+
        color = self.QualityColors[5]
    elseif ilvl >= 128 then   -- T5
        color = self.QualityColors[4]
    elseif ilvl >= 110 then   -- T4/Heroic
        color = self.QualityColors[3]
    elseif ilvl >= 85 then    -- Normal dungeons
        color = self.QualityColors[2]
    else
        color = self.QualityColors[1]
    end
    return self:ColorText(tostring(ilvl), color.r, color.g, color.b)
end

function BRutus:GetPlayerKey(name, realm)
    realm = realm or GetRealmName()
    return name .. "-" .. realm
end

function BRutus:TimeAgo(timestamp)
    if not timestamp or timestamp == 0 then return L["Never"] end
    local diff = time() - timestamp
    if diff < 60 then return L["Just now"]
    elseif diff < 3600 then return math.floor(diff / 60) .. L["m ago"]
    elseif diff < 86400 then return math.floor(diff / 3600) .. L["h ago"]
    else return math.floor(diff / 86400) .. L["d ago"]
    end
end

----------------------------------------------------------------------
-- Chat Player Link: Guild Invite
-- Alt+Click a player name in chat to send a guild invite
----------------------------------------------------------------------
function BRutus:HookChatInvite()
    hooksecurefunc("SetItemRef", function(link, _, button)
        if not CanGuildInvite() then return end
        if button ~= "LeftButton" or not IsAltKeyDown() then return end
        if not link then return end

        local name = link:match("^player:([^:]+)")
        if name and name ~= "" then
            GuildInvite(name)
            BRutus:Print(L["Guild invite sent to "] .. name .. L[". (Alt+Click)"])
        end
    end)
end

----------------------------------------------------------------------
-- Profession Freshness Check & Reminder
----------------------------------------------------------------------
local STALE_THRESHOLD = 86400 -- 24 hours

function BRutus:GetStaleProfessions()
    local myData = self.db and self.db.myData
    if not myData or not myData.professions then return {} end

    local scanTimes = (self.db and self.db.recipeScanTimes) or {}
    local stale = {}
    local now = time()

    local DC = self.DataCollector
    for _, prof in ipairs(myData.professions) do
        local isGathering = DC and DC.IsGatheringProfession and DC:IsGatheringProfession(prof.name)
        if prof.isPrimary and prof.name and not isGathering then
            local lastScan = scanTimes[prof.name]
            if not lastScan or (now - lastScan) > STALE_THRESHOLD then
                table.insert(stale, prof.name)
            end
        end
    end

    return stale
end

function BRutus:CheckProfessionFreshness()
    local stale = self:GetStaleProfessions()
    if #stale == 0 then return end

    self:ShowProfessionReminder(stale)
    self:Print(string.format(L["|cffFFAA00You have %d profession(s) with outdated recipe data.|r Open them to sync!"], #stale))
end

function BRutus:ShowProfessionReminder(staleProfessions)
    if self.profReminderFrame then
        self.profReminderFrame:Hide()
        self.profReminderFrame = nil
    end

    local C = self.Colors

    local frame = CreateFrame("Frame", "BRutusProfReminder", UIParent, "BackdropTemplate")
    frame:SetSize(420, 70)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -80)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.066, 0.066, 0.084, 0.95)
    frame:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.8)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Accent stripe on top
    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture("Interface\\Buttons\\WHITE8x8")
    stripe:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.9)
    stripe:SetHeight(2)
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("TOPRIGHT", -1, -1)

    -- Icon (trade skill icon)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 12, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")

    -- Title
    local titleFS = frame:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    titleFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    titleFS:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleFS:SetText(L["Guild OS — Profession Sync Required"])

    -- Description
    local profNames = table.concat(staleProfessions, ", ")
    local descFS = frame:CreateFontString(nil, "OVERLAY")
    descFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    descFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
    descFS:SetWidth(320)
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(true)
    descFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    descFS:SetText(L["Open your profession windows to update recipe data:\n|cffFFFFFF"] .. profNames .. "|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalFontObject(GameFontNormalSmall)

    local closeFS = closeBtn:CreateFontString(nil, "OVERLAY")
    closeFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    closeFS:SetPoint("CENTER", 0, 0)
    closeFS:SetText("x")
    closeFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    closeBtn:SetScript("OnEnter", function()
        closeFS:SetTextColor(C.red.r, C.red.g, C.red.b)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    end)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
        BRutus.profReminderFrame = nil
    end)

    -- Fade in
    frame:SetAlpha(0)
    frame:Show()
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.3 then
            self:SetAlpha(elapsed / 0.3)
        else
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
        end
    end)

    self.profReminderFrame = frame
    self.profReminderStale = {}
    for _, name in ipairs(staleProfessions) do
        self.profReminderStale[name] = true
    end
end

function BRutus:CheckAndDismissProfessionReminder()
    if not self.profReminderFrame or not self.profReminderStale then return end

    local scanTimes = (self.db and self.db.recipeScanTimes) or {}
    local now = time()

    for profName, _ in pairs(self.profReminderStale) do
        local lastScan = scanTimes[profName]
        if lastScan and (now - lastScan) <= STALE_THRESHOLD then
            self.profReminderStale[profName] = nil
        end
    end

    -- Check if any are still stale
    if not next(self.profReminderStale) then
        local frame = self.profReminderFrame
        -- Fade out
        local elapsed = 0
        frame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < 0.5 then
                self:SetAlpha(1 - (elapsed / 0.5))
            else
                self:Hide()
                self:SetScript("OnUpdate", nil)
                BRutus.profReminderFrame = nil
                BRutus.profReminderStale = nil
            end
        end)
        BRutus:Print(L["|cff00ff00All professions synced!|r Recipe data is up to date."])
    end
end

function BRutus:DismissProfessionReminder()
    if self.profReminderFrame then
        self.profReminderFrame:Hide()
        self.profReminderFrame = nil
        self.profReminderStale = nil
    end
end

----------------------------------------------------------------------
-- Data exports (tab-separated, paste straight into Sheets/Excel).
-- Headers stay in English on purpose so exports are a stable interchange
-- format regardless of the client locale.
----------------------------------------------------------------------
function BRutus:ExportRoster()
    local lines = { "Name\tClass\tLevel\tRank\tiLvl\tAttendance%\tAttunements\tLastSeen" }
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = self:GetPlayerKey(short, realm)
            local d = self.db.members[key] or {}
            local att = self.RaidTracker and self.RaidTracker:GetAttendance25ManPercent(key) or 0
            local attDone, attTotal = 0, 0
            if self.AttunementTracker then
                attTotal = #self.AttunementTracker:GetGuildColumns()
                for _, a in ipairs(self.AttunementTracker:GetEffectiveAttunements(key)) do
                    if a.complete and a.questsTotal and a.questsTotal > 0 then attDone = attDone + 1 end
                end
            end
            local lastSeen = (d.lastUpdate and d.lastUpdate > 0) and date("%Y-%m-%d", d.lastUpdate) or ""
            lines[#lines + 1] = table.concat({
                short, classFile or "", level or 0, rankName or "",
                d.avgIlvl or 0, att, attDone .. "/" .. attTotal, lastSeen,
            }, "\t")
        end
    end
    return table.concat(lines, "\n")
end

function BRutus:ExportLoot()
    local lines = { "Date\tItem\tPlayer\tRaid" }
    for _, e in ipairs(self.db.lootHistory or {}) do
        local itemName = (e.itemLink and GetItemInfo(e.itemLink)) or e.itemName or "?"
        local dateStr = e.timestamp and date("%Y-%m-%d %H:%M", e.timestamp) or ""
        lines[#lines + 1] = table.concat({ dateStr, itemName, e.player or "?", e.raid or "" }, "\t")
    end
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- First-seen tracking. WoW exposes no guild join date, so GuildOS
-- records when it first observed each member in the roster. This is a
-- "known to GuildOS since" date, not the true join date.
----------------------------------------------------------------------
function BRutus:RecordFirstSeen()
    if not self.db then return end
    if not self.db.firstSeen then self.db.firstSeen = {} end
    local now = GetServerTime()
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = self:GetPlayerKey(short, realm)
            if not self.db.firstSeen[key] then
                self.db.firstSeen[key] = now
            end
        end
    end
end

function BRutus:GetFirstSeen(playerKey)
    return self.db and self.db.firstSeen and self.db.firstSeen[playerKey]
end

----------------------------------------------------------------------
-- DB hygiene: drop cached data for members who left the guild.
-- Manual-only (never auto-run) to avoid data loss if the roster is mid-load.
-- Prunes the volatile caches (members gear/spec, firstSeen) but keeps officer
-- records (trials, officer notes) for historical reference.
----------------------------------------------------------------------
function BRutus:PruneStaleData()
    if not self.db then return 0 end
    local n = GetNumGuildMembers() or 0
    if n == 0 then return 0 end  -- roster not loaded yet; refuse to prune

    local roster = {}
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            roster[self:GetPlayerKey(short, realm)] = true
        end
    end

    local removed = 0
    for key in pairs(self.db.members or {}) do
        if not roster[key] then
            self.db.members[key] = nil
            removed = removed + 1
        end
    end
    for key in pairs(self.db.firstSeen or {}) do
        if not roster[key] then
            self.db.firstSeen[key] = nil
        end
    end
    return removed
end
