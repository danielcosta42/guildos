----------------------------------------------------------------------
-- BRutus Guild Manager - Utilities
-- Pure helper functions. No business logic, no persistent state writes.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Alt / Main linking (account-wide attunement propagation)
----------------------------------------------------------------------
function BRutus:LinkAlt(altKey, mainKey)
    if not self:IsOfficer() then return false end
    if not altKey or not mainKey or altKey == mainKey then return false end
    self.db.altLinks = self.db.altLinks or {}
    -- Prevent circular links: mainKey must not itself be an alt
    if self.db.altLinks[mainKey] then
        self:Print("Erro: " .. mainKey .. " já é um alt. Desvincule-o antes.")
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
    if not timestamp or timestamp == 0 then return "Never" end
    local diff = time() - timestamp
    if diff < 60 then return "Just now"
    elseif diff < 3600 then return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
    else return math.floor(diff / 86400) .. "d ago"
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
            BRutus:Print("Guild invite sent to " .. name .. ". (Alt+Click)")
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
    self:Print("|cffFFAA00You have " .. #stale .. " profession(s) with outdated recipe data.|r Open them to sync!")
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
    titleFS:SetText("Guild OS — Profession Sync Required")

    -- Description
    local profNames = table.concat(staleProfessions, ", ")
    local descFS = frame:CreateFontString(nil, "OVERLAY")
    descFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    descFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
    descFS:SetWidth(320)
    descFS:SetJustifyH("LEFT")
    descFS:SetWordWrap(true)
    descFS:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    descFS:SetText("Open your profession windows to update recipe data:\n|cffFFFFFF" .. profNames .. "|r")

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
        BRutus:Print("|cff00ff00All professions synced!|r Recipe data is up to date.")
    end
end

function BRutus:DismissProfessionReminder()
    if self.profReminderFrame then
        self.profReminderFrame:Hide()
        self.profReminderFrame = nil
        self.profReminderStale = nil
    end
end
