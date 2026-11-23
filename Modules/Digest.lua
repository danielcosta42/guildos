----------------------------------------------------------------------
-- Guild OS - Login Digest
-- "Since your last login: N new members, X items looted, ..." — a quick
-- catch-up shown once on login (and on demand via /guildos digest).
-- Build() is pure data; the popup uses the UI factories at runtime.
----------------------------------------------------------------------
local Digest = {}
GuildOS.Digest = Digest
local L = GuildOS.L

local FEED_LINES = 5             -- lines from guildos.me in one digest
local FEED_SEEN_S = 14 * 86400   -- how long a line shown is remembered: the site sends a week of them

function Digest:Initialize()
    GuildOS.db.digest = GuildOS.db.digest or {}
    if GuildOS.db.digest.enabled == nil then GuildOS.db.digest.enabled = true end
    if GuildOS.db.digest.lastSeen == nil then GuildOS.db.digest.lastSeen = 0 end
    GuildOS.db.digest.feedSeen = GuildOS.db.digest.feedSeen or {}
end

-- What guildos.me said that this client has not shown yet (guildos-web #259), the newest first, and
-- what the block as a whole tells: an event the site says is not said again by this client's own lines.
local function fromSite()
    local seen = GuildOS.db.digest and GuildOS.db.digest.feedSeen or {}
    local unseen, told = {}, {}
    for _, item in ipairs(GuildOS.CompanionImport and GuildOS.CompanionImport:FeedLines() or {}) do
        told[item.type] = true
        told[item.type .. "|" .. item.at] = true
        if item.key then told[item.type .. "|" .. item.key] = true end
        if not seen[item.id] and #unseen < FEED_LINES then unseen[#unseen + 1] = item end
    end
    return unseen, told
end

local function myKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
end

----------------------------------------------------------------------
-- Build the digest lines for everything that changed since `since`
-- (a server timestamp). Returns an array of strings.
----------------------------------------------------------------------
-- opts.login: the login's digest, where the bulletin tells only the notices not told yet (#418); elsewhere (the
-- Activity sub-tab, /gos digest) it lists the notices posted since `since`, as it always did.
function Digest:Build(since, opts)
    since = since or GuildOS.db.digest.lastSeen or 0
    local lines = {}
    local feed, told = fromSite()

    -- New members (first observed by Guild OS since last login, after its first look at the guild)
    local newCount, newNames = 0, {}
    local newSince = math.max(since, GuildOS.db.firstSeenSince or 0)
    for key, ts in pairs(GuildOS.db.firstSeen or {}) do
        if ts and ts > newSince then
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
        for _, line in ipairs(GuildOS.Milestones:GetDigestLines(since, told)) do
            lines[#lines + 1] = line
        end
    end
    -- WoW: Forever's founding: who joined as a founder, the window, the guild's anniversaries (#209)
    if GuildOS.Founding then
        for _, line in ipairs(GuildOS.Founding:GetDigestLines(since, GetServerTime(), told)) do
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

    -- Bulletin notices. At login, the active ones this player has not been told about (issue #418), the newest
    -- few: each once, whenever it was posted, never one that has ended; ShowOnLogin marks them told. Anywhere
    -- else, the most recent few posted since `since`.
    if GuildOS.Bulletin then
        if opts and opts.login then
            for _, m in ipairs(GuildOS.Bulletin:Unseen(GetServerTime(), 3)) do
                lines[#lines + 1] = GuildOS.Bulletin.Line(m)
            end
        else
            local shown = 0
            for _, m in ipairs(GuildOS.Bulletin:GetMessages()) do
                if type(m) == "table" and (tonumber(m.ts) or 0) > since and shown < 3 then
                    lines[#lines + 1] = GuildOS.Bulletin.Line(m)
                    shown = shown + 1
                end
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
            -- Ready to review: their end, from the guild's length, has passed with no decision (#249).
            local due = GuildOS.TrialTracker:CountReady()
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

    -- WoW: Forever: what the guild earned (#216), and the officers' reminder of its setup (#217)
    if GuildOS.Achievements then
        for _, line in ipairs(GuildOS.Achievements:GetDigestLines(told)) do
            lines[#lines + 1] = line
        end
    end
    local setup = GuildOS.Activation and GuildOS.Activation:GetDigestLine(GetServerTime())
    if setup then lines[#lines + 1] = setup end
    -- Beside other news, never a reason to open the digest on its own at every login.
    local nearest = GuildOS.Achievements and GuildOS.Achievements:NextLine()
    if nearest and (#lines > 0 or #feed > 0) then lines[#lines + 1] = nearest end

    if #feed > 0 then
        lines[#lines + 1] = "|cffEDCC7B" .. L["From guildos.me"] .. "|r"
        for _, item in ipairs(feed) do lines[#lines + 1] = item.text end
    end

    return lines
end

-- The login digest showed these: they are not shown again, and what is too old to come back is forgotten.
function Digest:MarkFeedSeen(now)
    local seen = GuildOS.db.digest.feedSeen
    for _, item in ipairs((fromSite())) do seen[item.id] = now end
    for id, at in pairs(seen) do
        if now - at > FEED_SEEN_S then seen[id] = nil end
    end
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
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
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
    -- The title above and the button below: a long digest grows, never runs under the button.
    f:SetHeight(math.max(280, 44 + y + 48))

    f:Show()
    return f
end

----------------------------------------------------------------------
-- Auto-show once on login (skipped on first run and when disabled).
----------------------------------------------------------------------
function Digest:ShowOnLogin()
    local B = GuildOS.Bulletin
    -- From now on a notice that arrives is told in the chat (issue #418).
    if B then B:LoginDone() end
    if not GuildOS.db.digest or not GuildOS.db.digest.enabled then
        -- No digest: the notices not told yet get a chat line each.
        if B then B:TellInChat(GetServerTime()) end
        return
    end
    if self.shownThisSession then return end
    -- A raid owner's prompt took this login (issue #400): one popup at a time, and the raid about to start is the
    -- one that cannot wait. Nothing is marked seen: the digest shows once the prompt is put off (Later or its close,
    -- RaidStart:PromptDismissed), and after Raid ready waits for the next login, or /gos digest.
    if GuildOS.RaidStart and GuildOS.RaidStart:PromptedAtLogin() then
        self.deferred = true
        return
    end

    local since = GuildOS.db.digest.lastSeen or 0
    -- First ever run: nothing to compare against — just start the clock.
    if since == 0 then
        GuildOS.db.digest.lastSeen = GetServerTime()
        -- The board is not part of that clock: what is on it now is told in the chat.
        if B then B:TellInChat(GetServerTime()) end
        return
    end

    local lines = self:Build(since, { login = true })
    self:MarkFeedSeen(GetServerTime())
    if B then B:MarkSeen(GetServerTime()) end
    if GuildOS.Achievements then GuildOS.Achievements:MarkSeen() end
    if GuildOS.Activation then
        if GuildOS.Activation:GetDigestLine(GetServerTime()) then GuildOS.Activation:Reminded(GetServerTime()) end
    end
    GuildOS.db.digest.lastSeen = GetServerTime()
    self.shownThisSession = true
    if #lines > 0 then
        self:Show(lines)
    end
end
