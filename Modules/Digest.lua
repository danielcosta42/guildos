----------------------------------------------------------------------
-- Guild OS - Login Digest
-- "Since your last login: N new members, X items looted, ..." — a quick
-- catch-up shown once on login (and on demand via /guildos digest).
-- Build() is pure data; the popup uses the UI factories at runtime.
----------------------------------------------------------------------
local Digest = {}
BRutus.Digest = Digest
local L = BRutus.L

function Digest:Initialize()
    BRutus.db.digest = BRutus.db.digest or {}
    if BRutus.db.digest.enabled == nil then BRutus.db.digest.enabled = true end
    if BRutus.db.digest.lastSeen == nil then BRutus.db.digest.lastSeen = 0 end
end

local function myKey()
    return BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
end

----------------------------------------------------------------------
-- Build the digest lines for everything that changed since `since`
-- (a server timestamp). Returns an array of strings.
----------------------------------------------------------------------
function Digest:Build(since)
    since = since or BRutus.db.digest.lastSeen or 0
    local lines = {}

    -- New members (first observed by Guild OS since last login)
    local newCount, newNames = 0, {}
    for key, ts in pairs(BRutus.db.firstSeen or {}) do
        if ts and ts > since then
            newCount = newCount + 1
            if #newNames < 3 then newNames[#newNames + 1] = key:match("^([^-]+)") or key end
        end
    end
    if newCount > 0 then
        local names = table.concat(newNames, ", ")
        if newCount > #newNames then names = names .. " +" .. (newCount - #newNames) end
        lines[#lines + 1] = string.format(L["%d new member(s): %s"], newCount, names)
    end

    -- Raid sessions tracked since last login
    local raidCount = 0
    if BRutus.db.raidTracker and BRutus.db.raidTracker.sessions then
        for _, s in pairs(BRutus.db.raidTracker.sessions) do
            if s.startTime and s.startTime > since then raidCount = raidCount + 1 end
        end
    end
    if raidCount > 0 then
        lines[#lines + 1] = string.format(L["%d raid session(s) tracked"], raidCount)
    end

    -- Loot recorded since last login
    local lootCount = 0
    for _, e in ipairs(BRutus.db.lootHistory or {}) do
        if (e.timestamp or 0) > since then lootCount = lootCount + 1 end
    end
    if lootCount > 0 then
        lines[#lines + 1] = string.format(L["%d item(s) looted"], lootCount)
    end

    -- Your own points change since last login
    if BRutus.Points and BRutus.db.points and BRutus.db.points.log then
        local mk = myKey()
        local delta = 0
        for _, e in ipairs(BRutus.db.points.log) do
            if e.key == mk and (e.ts or 0) > since then delta = delta + (e.delta or 0) end
        end
        if delta ~= 0 then
            lines[#lines + 1] = string.format(L["Your points changed by %+d (now %d)"], delta, BRutus.Points:Get(mk))
        end
    end

    -- New bulletin notices (most recent few)
    if BRutus.Bulletin then
        local shown = 0
        for _, m in ipairs(BRutus.Bulletin:GetMessages()) do
            if (m.ts or 0) > since and shown < 3 then
                lines[#lines + 1] = "|cffEDCC7B" .. L["Notice:"] .. "|r " .. (m.text or "")
                shown = shown + 1
            end
        end
    end

    -- Officer-only catch-up
    if BRutus:IsOfficer() then
        if BRutus.TrialTracker then
            local due = 0
            for _, t in ipairs(BRutus.TrialTracker:GetActiveTrials() or {}) do
                local rem = BRutus.TrialTracker:GetDaysRemaining(t.key)
                if rem ~= nil and rem <= 0 then due = due + 1 end
            end
            if due > 0 then
                lines[#lines + 1] = string.format(L["%d trial(s) ready for decision"], due)
            end
        end
        if BRutus.GuildManager and BRutus.GuildManager.GetInactiveMembers then
            local inactive = BRutus.GuildManager:GetInactiveMembers(BRutus.GuildManager.DEFAULT_INACTIVE_DAYS)
            if inactive and #inactive > 0 then
                lines[#lines + 1] = string.format(L["%d inactive member(s)"], #inactive)
            end
        end
    end

    return lines
end

----------------------------------------------------------------------
-- The popup window.
----------------------------------------------------------------------
function Digest:Show(lines)
    local UI = BRutus.UI
    local C = BRutus.Colors
    lines = lines or self:Build()

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSDigestFrame", UIParent, "BackdropTemplate")
        f:SetSize(360, 280)
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f, { shadowSize = 16 })
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
        f:SetScript("OnDragStop", function(self2) self2:StopMovingOrSizing() end)

        f.title = UI:CreateTitle(f, L["Since your last login"], 15)
        f.title:SetPoint("TOPLEFT", 16, -14)

        f.close = UI:CreateCloseButton(f)
        f.close:SetPoint("TOPRIGHT", -8, -8)
        f.close:SetScript("OnClick", function() f:Hide() end)

        f.body = CreateFrame("Frame", nil, f)
        f.body:SetPoint("TOPLEFT", 16, -44)
        f.body:SetPoint("BOTTOMRIGHT", -16, 48)

        f.openBtn = UI:CreateButton(f, L["Open Guild OS"], 140, 26)
        f.openBtn:SetPoint("BOTTOM", 0, 14)
        f.openBtn:SetScript("OnClick", function()
            f:Hide()
            BRutus:ToggleRoster()
        end)
        self.frame = f
    end

    -- (Re)populate the body
    for _, c in pairs({ f.body:GetChildren() }) do c:Hide() end
    for _, r in pairs({ f.body:GetRegions() }) do r:Hide() end

    local y = 0
    if #lines == 0 then
        local empty = UI:CreateText(f.body, L["Nothing new since your last login."], 11, C.silver.r, C.silver.g, C.silver.b)
        empty:SetPoint("TOPLEFT", 2, -y)
        empty:SetWidth(f.body:GetWidth() - 4)
    else
        for _, line in ipairs(lines) do
            local dot = UI:CreateText(f.body, "|cffEDCC7B*|r", 12, C.gold.r, C.gold.g, C.gold.b)
            dot:SetPoint("TOPLEFT", 2, -y)
            local fs = UI:CreateText(f.body, line, 11, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 18, -y)
            fs:SetWidth(f.body:GetWidth() - 22)
            fs:SetJustifyH("LEFT")
            y = y + math.max(20, (fs:GetStringHeight() or 14) + 8)
        end
    end

    f:Show()
    return f
end

----------------------------------------------------------------------
-- Auto-show once on login (skipped on first run and when disabled).
----------------------------------------------------------------------
function Digest:ShowOnLogin()
    if not BRutus.db.digest or not BRutus.db.digest.enabled then return end
    if self.shownThisSession then return end

    local since = BRutus.db.digest.lastSeen or 0
    -- First ever run: nothing to compare against — just start the clock.
    if since == 0 then
        BRutus.db.digest.lastSeen = GetServerTime()
        return
    end

    local lines = self:Build(since)
    BRutus.db.digest.lastSeen = GetServerTime()
    self.shownThisSession = true
    if #lines > 0 then
        self:Show(lines)
    end
end
