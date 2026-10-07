----------------------------------------------------------------------
-- Guild OS - Login Digest
-- "Since your last login: N new members, X items looted, ..." — a quick
-- catch-up shown once on login (and on demand via /guildos digest).
-- Build() is pure data; the popup uses the UI factories at runtime.
----------------------------------------------------------------------
local Digest = {}
GuildOS.Digest = Digest
local L = GuildOS.L

function Digest:Initialize()
    GuildOS.db.digest = GuildOS.db.digest or {}
    if GuildOS.db.digest.enabled == nil then GuildOS.db.digest.enabled = true end
    if GuildOS.db.digest.lastSeen == nil then GuildOS.db.digest.lastSeen = 0 end
end

local function myKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
end

----------------------------------------------------------------------
-- Build the digest lines for everything that changed since `since`
-- (a server timestamp). Returns an array of strings.
----------------------------------------------------------------------
function Digest:Build(since)
    since = since or GuildOS.db.digest.lastSeen or 0
    local lines = {}

    -- New members (first observed by Guild OS since last login)
    local newCount, newNames = 0, {}
    for key, ts in pairs(GuildOS.db.firstSeen or {}) do
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

    -- Roster changes since last login (from the audit log)
    if GuildOS.RosterLog then
        local c = GuildOS.RosterLog:CountsSince(since)
        if c.kick > 0 then lines[#lines + 1] = string.format(L["%d member(s) removed"], c.kick) end
        if c.leave > 0 then lines[#lines + 1] = string.format(L["%d member(s) left"], c.leave) end
    end

    -- Raid sessions tracked since last login
    local raidCount = 0
    if GuildOS.db.raidTracker and GuildOS.db.raidTracker.sessions then
        for _, s in pairs(GuildOS.db.raidTracker.sessions) do
            if s.startTime and s.startTime > since then raidCount = raidCount + 1 end
        end
    end
    if raidCount > 0 then
        lines[#lines + 1] = string.format(L["%d raid session(s) tracked"], raidCount)
    end

    -- Loot recorded since last login
    local lootCount = 0
    for _, e in ipairs(GuildOS.db.lootHistory or {}) do
        if (e.timestamp or 0) > since then lootCount = lootCount + 1 end
    end
    if lootCount > 0 then
        lines[#lines + 1] = string.format(L["%d item(s) looted"], lootCount)
    end

    -- Your own points change since last login
    if GuildOS.Points and GuildOS.db.points and GuildOS.db.points.log then
        local mk = myKey()
        local delta = 0
        for _, e in ipairs(GuildOS.db.points.log) do
            if e.key == mk and (e.ts or 0) > since then delta = delta + (e.delta or 0) end
        end
        if delta ~= 0 then
            lines[#lines + 1] = string.format(L["Your points changed by %+d (now %d)"], delta, GuildOS.Points:Get(mk))
        end
    end

    -- Milestones & guild anniversaries
    if GuildOS.Milestones then
        for _, line in ipairs(GuildOS.Milestones:GetDigestLines(since)) do
            lines[#lines + 1] = line
        end
    end

    -- Upcoming raid reminder (event within the next 24h)
    if GuildOS.Calendar and GuildOS.Calendar.GetDigestLines then
        local calLines = GuildOS.Calendar:GetDigestLines()
        if calLines then
            for _, line in ipairs(calLines) do
                lines[#lines + 1] = "|cff4CB8FF" .. line .. "|r"
            end
        end
    end

    -- Alliance: how many allied raids are coming up in the next week. One line,
    -- and only when this guild is federated and something is actually scheduled.
    if GuildOS.Alliance and GuildOS.Alliance:Get() and GuildOS.Calendar
        and GuildOS.Calendar.AllianceEvents then
        local horizon = GetServerTime() + (7 * 86400)
        local count = 0
        for _, e in ipairs(GuildOS.Calendar:AllianceEvents()) do
            if (tonumber(e.when) or 0) <= horizon then
                count = count + 1
            end
        end
        if count > 0 then
            local gold = GuildOS.Colors.gold
            lines[#lines + 1] = string.format("|cff%02x%02x%02x", gold.r * 255, gold.g * 255, gold.b * 255) ..
                string.format(L["%d allied event(s) this week"], count) .. "|r"
        end
    end

    -- New bulletin notices (most recent few)
    if GuildOS.Bulletin then
        local shown = 0
        for _, m in ipairs(GuildOS.Bulletin:GetMessages()) do
            if (m.ts or 0) > since and shown < 3 then
                lines[#lines + 1] = "|cffEDCC7B" .. L["Notice:"] .. "|r " .. (m.text or "")
                shown = shown + 1
            end
        end
    end

    -- New polls opened since last login
    if GuildOS.Polls then
        local newPolls = 0
        for _, p in pairs(GuildOS.Polls:GetList()) do
            if not p.closed and (p.ts or 0) > since then newPolls = newPolls + 1 end
        end
        if newPolls > 0 then
            lines[#lines + 1] = string.format(L["%d new poll(s) — cast your vote"], newPolls)
        end
    end

    -- Officer-only catch-up
    if GuildOS:IsOfficer() then
        if GuildOS.TrialTracker then
            local due = 0
            for _, t in ipairs(GuildOS.TrialTracker:GetActiveTrials() or {}) do
                local rem = GuildOS.TrialTracker:GetDaysRemaining(t.key)
                if rem ~= nil and rem <= 0 then due = due + 1 end
            end
            if due > 0 then
                lines[#lines + 1] = string.format(L["%d trial(s) ready for decision"], due)
            end
        end
        if GuildOS.GuildManager and GuildOS.GuildManager.GetInactiveMembers then
            local inactive = GuildOS.GuildManager:GetInactiveMembers(GuildOS.GuildManager.DEFAULT_INACTIVE_DAYS)
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
    local UI = GuildOS.UI
    local C = GuildOS.Colors
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
            GuildOS:ToggleRoster()
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
    if not GuildOS.db.digest or not GuildOS.db.digest.enabled then return end
    if self.shownThisSession then return end

    local since = GuildOS.db.digest.lastSeen or 0
    -- First ever run: nothing to compare against — just start the clock.
    if since == 0 then
        GuildOS.db.digest.lastSeen = GetServerTime()
        return
    end

    local lines = self:Build(since)
    GuildOS.db.digest.lastSeen = GetServerTime()
    self.shownThisSession = true
    if #lines > 0 then
        self:Show(lines)
    end
end
