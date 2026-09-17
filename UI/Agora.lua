----------------------------------------------------------------------
-- Guild OS - Now (agora; issue #14)
-- The first tab, and what the hub used to be: a live column that answers
-- when the next raid is, what needs this player and what just happened.
-- Every row opens the screen that owns it. While the tab is wide enough,
-- the home cards (UI/Dashboard.lua) sit beside the column; #15 redesigns
-- them. The data half is frame-free, so tools/window-shell.lua tests it.
----------------------------------------------------------------------
local UI = BRutus.UI
local C  = BRutus.Colors
local L  = BRutus.L

local Agora = {}
UI.Agora = Agora

local WHITE         = "Interface\\Buttons\\WHITE8x8"
local COLUMN_W      = 296
local HOME_MIN      = 780        -- tab width from which the home cards sit beside the column
local GAP           = 8
local CARD_PAD      = 10
local TITLE_ROW     = 24         -- a card's title line, and the space under it
local ROW_H         = 26
local MARK          = 6
local TIME_W        = 44
local RECENT        = 48 * 3600  -- how far back the activity goes
local ANSWER_WITHIN = 7 * 86400  -- a raid this close asks for an answer
local MAX_NEEDS     = 5
local MAX_FEED      = 12
local LOADING_BARS  = { 180, 130, 160 }
local DASH          = "\226\128\148"
local DOT           = " \194\183 "

local function now() return (GetServerTime and GetServerTime()) or time() end
local function allowed(id) return UI:IsFeatureAllowed(UI:GetFeature(id)) end

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------

-- In a guild, but the roster has not arrived: counts would read zero.
function Agora:RosterLoading()
    return IsInGuild() and (GetNumGuildMembers() or 0) == 0
end

function Agora:OnlineCount()
    local n = 0
    for i = 1, GetNumGuildMembers() or 0 do
        local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if isOnline then n = n + 1 end
    end
    return n
end

-- The newest time any member's data arrived over sync, or nil.
function Agora:LastSync()
    local newest
    for _, m in pairs((BRutus.db and BRutus.db.members) or {}) do
        local t = type(m) == "table" and m.lastSync
        if t and (not newest or t > newest) then newest = t end
    end
    return newest
end

-- The next raid still to start. Events made before kinds existed are raids.
function Agora:NextRaid()
    local cal = BRutus.Calendar
    -- Its saved table exists only once Calendar has started.
    if not (cal and cal.GetUpcoming and BRutus.db and BRutus.db.calendar) then return nil end
    local t = now()
    for _, e in ipairs(cal:GetUpcoming(false)) do
        if (e.kind == nil or e.kind == "RAID") and (e.when or 0) > t then return e end
    end
    return nil
end

-- "4:12:38" under a day, "2d 4h" from a day out.
function Agora.Clock(dt)
    if dt <= 0 then return L["now"] end
    local d = math.floor(dt / 86400)
    if d > 0 then return string.format("%dd %dh", d, math.floor((dt % 86400) / 3600)) end
    return string.format("%d:%02d:%02d", math.floor(dt / 3600), math.floor((dt % 3600) / 60), math.floor(dt % 60))
end

-- "4h12" for the bar.
function Agora.Short(dt)
    if dt <= 0 then return L["now"] end
    local d = math.floor(dt / 86400)
    local h = math.floor((dt % 86400) / 3600)
    local m = math.floor((dt % 3600) / 60)
    if d > 0 then return string.format("%dd%dh", d, h) end
    if h > 0 then return string.format("%dh%02d", h, m) end
    return string.format("%dm", math.max(1, m))
end

-- What needs this player, urgent first: { text, urgent, id, sub, filter } each. Only
-- items whose screen this player can open, so every row is a way in.
function Agora:NeedsMe()
    local urgent, normal = {}, {}
    local function add(list, text, id, sub, filter)
        if allowed(id) then
            list[#list + 1] = { text = text, urgent = list == urgent, id = id, sub = sub, filter = filter }
        end
    end

    local cal, raid = BRutus.Calendar, self:NextRaid()
    if raid and cal.MyRsvp and not cal:MyRsvp(raid) and raid.when - now() <= ANSWER_WITHIN then
        add(normal, string.format(L["You have not answered: %s"], raid.title or "?"), "guild", "calendar", raid.when)
    end

    if BRutus:IsOfficer() then
        local tt = BRutus.TrialTracker
        if tt and tt.GetActiveTrials and tt.GetDaysRemaining then
            local n = 0
            for _, trial in ipairs(tt:GetActiveTrials()) do
                -- Whole days, rounded down: 0 is less than a day left.
                local left = tt:GetDaysRemaining(trial.key)
                if left ~= nil and left <= 0 then n = n + 1 end
            end
            if n > 0 then add(urgent, string.format(L["%d trials expiring"], n), "trials") end
        end

        local gm = BRutus.GuildManager
        if gm and gm.GetInactiveMembers then
            local days = gm.DEFAULT_INACTIVE_DAYS or 30
            local n = #gm:GetInactiveMembers(days)
            if n > 0 then add(normal, string.format(L["%d inactive over %dd"], n, days), "management", "inactive") end
        end
        if gm and gm.GetSuggestions then
            local s = gm:GetSuggestions()
            -- Promotions only: its ready trials are the ones the trials row counts.
            local n = #(s.promoteCandidates or {})
            if n > 0 then add(normal, string.format(L["%d promotions to review"], n), "management", "suggest") end
        end

        local rs = BRutus.RecruitScanner
        if rs and rs.GetInbox then
            local n = 0
            for _ in pairs(rs:GetInbox()) do n = n + 1 end
            if n > 0 then add(normal, string.format(L["%d applicants waiting"], n), "recruitment", "scanner") end
        end
    end

    for _, item in ipairs(normal) do urgent[#urgent + 1] = item end
    return urgent
end

local ROSTER_ACTION = {
    join    = "%s joined the guild",
    leave   = "%s left the guild",
    kick    = "%s was removed from the guild",
    promote = "%s was promoted to %s",
    demote  = "%s was demoted to %s",
}

-- The saved key for a short name, when exactly one member has it.
local function memberKey(short)
    if not short then return nil end
    local found
    for key in pairs((BRutus.db and BRutus.db.members) or {}) do
        if (key:match("^([^-]+)") or key) == short then
            if found then return nil end
            found = key
        end
    end
    return found
end

-- The last 48 hours in the guild, newest first: { ts, text, id, sub, key }
-- each. `id` is the screen that owns the entry when this player can open
-- it, the roster otherwise; `key` names a member whose detail opens too.
function Agora:Activity(limit)
    local since, db, out = now() - RECENT, BRutus.db or {}, {}
    local function add(ts, text, id, sub, key, target)
        if (ts or 0) <= since then return end
        if not allowed(id) then id, sub = "roster", nil end
        out[#out + 1] = { ts = ts, text = text, id = id, sub = sub, key = key, target = target }
    end

    for _, e in ipairs((db.rosterLog and db.rosterLog.events) or {}) do
        local fmt = ROSTER_ACTION[e.action]
        if fmt then
            add(e.timestamp, string.format(L[fmt], e.target or "?", e.detail or ""), "management", "log", nil, e.target)
        end
    end
    for _, e in ipairs(db.lootHistory or {}) do
        add(e.timestamp, string.format(L["%s received %s"], e.player or "?", e.itemLink or e.itemName or "?"), "loot",
            nil, e.playerKey)
    end
    for _, e in ipairs((db.milestones and db.milestones.events) or {}) do
        if e.type == "ding" then
            add(e.ts, string.format(L["%s reached level %s!"], e.name or "?", e.detail or "70"), "roster", nil, e.key)
        elseif e.type == "attune" then
            add(e.ts, string.format(L["%s completed a new attunement"], e.name or "?"), "roster", nil, e.key)
        end
    end
    -- A session is saved when it ends, so the row is a raid that was tracked.
    for _, s in pairs((db.raidTracker and db.raidTracker.sessions) or {}) do
        add(s.endTime or s.startTime, string.format(L["Raid tracked: %s"], s.name or "?"), "raids", "sessions")
    end

    table.sort(out, function(a, b) return a.ts > b.ts end)
    for i = #out, (limit or MAX_FEED) + 1, -1 do out[i] = nil end
    -- A name becomes a member only on the rows kept: the lookup walks every saved member.
    for _, item in ipairs(out) do
        if item.target then item.key = memberKey(item.target) end
        item.target = nil
    end
    return out
end

-- The 28px bar: online · time to the next raid · what needs me. Unlabelled,
-- always in that order; a dash when no raid is scheduled, gold when something
-- needs this player.
function Agora:BarText()
    local raid = self:NextRaid()
    local raidIn = raid and self.Short(raid.when - now()) or DASH
    -- Until the roster arrives, dashes rather than counts that read zero.
    if self:RosterLoading() then return DASH .. DOT .. raidIn .. DOT .. DASH end
    local pending = #self:NeedsMe()
    local p = tostring(pending)
    if pending > 0 then
        p = string.format("|cff%02x%02x%02x%d|r", math.floor(C.gold.r * 255 + 0.5),
            math.floor(C.gold.g * 255 + 0.5), math.floor(C.gold.b * 255 + 0.5), pending)
    end
    return self:OnlineCount() .. DOT .. raidIn .. DOT .. p
end

----------------------------------------------------------------------
-- The column
----------------------------------------------------------------------

local function newText(parent, size, role, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    BRutus:ApplyFont(fs, size, role)
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function newCard(parent, title)
    local card = UI:CreatePanel(parent)
    card:SetFrameLevel(parent:GetFrameLevel() + 1)
    card:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
    card.title = newText(card, 15, "sectionTitle", C.text)
    card.title:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
    card.title:SetText(title)
    return card
end

local function newList(card)
    local list = UI:CreateDarkPanel(card)
    list:SetFrameLevel(card:GetFrameLevel() + 1)
    list:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + TITLE_ROW))
    list:SetPoint("TOPRIGHT", -CARD_PAD, -(CARD_PAD + TITLE_ROW))
    list.rows = {}
    return list
end

local function stamp(ts)
    if now() - ts < 86400 then return date("%H:%M", ts) end
    return date("%a", ts)
end

local function acquireRow(list, i)
    local r = list.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", -1, -(1 + (i - 1) * ROW_H))

    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetTexture(WHITE)
    r.hover:SetAllPoints()
    r.hover:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
    r.hover:Hide()

    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(WHITE)
    r.mark:SetSize(MARK, MARK)
    r.mark:SetPoint("LEFT", 8, 0)

    r.time = newText(r, 10, "caption", C.labelDim)
    r.time:SetPoint("LEFT", 8, 0)
    r.time:SetWidth(TIME_W)

    r.text = newText(r, 11, nil, C.text)

    -- The loading state: a static bar where the text will be.
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetTexture(WHITE)
    r.bar:SetHeight(8)
    r.bar:SetPoint("LEFT", 8, 0)
    r.bar:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)

    r:SetScript("OnEnter", function(self) if self.go then self.hover:Show() end end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self) if self.go then self.go() end end)
    list.rows[i] = r
    return r
end

-- Paint a row as "need", "feed", "empty" (value: the line) or "loading"
-- (value: the bar's width). Items open their screen, filtered.
local function paintRow(r, kind, value)
    r.go = nil
    r.hover:Hide()
    r.mark:Hide()
    r.time:Hide()
    r.bar:Hide()
    r.text:Hide()
    r.text:ClearAllPoints()
    r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    if kind == "loading" then
        r.bar:SetWidth(value)
        r.bar:Show()
    elseif kind == "empty" then
        r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
        r.text:SetTextColor(C.label.r, C.label.g, C.label.b)
        r.text:SetText(value)
        r.text:Show()
    else
        if kind == "need" then
            local col = value.urgent and C.danger or C.gold
            r.mark:SetVertexColor(col.r, col.g, col.b, 1)
            r.mark:Show()
            r.text:SetPoint("LEFT", r, "LEFT", 8 + MARK + 8, 0)
            r.text:SetTextColor(C.text.r, C.text.g, C.text.b)
        else
            r.time:SetText(stamp(value.ts))
            r.time:Show()
            r.text:SetPoint("LEFT", r, "LEFT", 8 + TIME_W + 4, 0)
            r.text:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        end
        r.text:SetText(value.text)
        r.text:Show()
        r.go = function()
            UI:OpenWindow(value.id, value.sub, value.filter)
            local data = value.key and BRutus.db and BRutus.db.members and BRutus.db.members[value.key]
            if data and BRutus.ShowMemberDetail then BRutus:ShowMemberDetail(data) end
        end
    end
    r:Show()
end

local function fill(list, rows)
    for i, row in ipairs(rows) do paintRow(acquireRow(list, i), row[1], row[2]) end
    for i = #rows + 1, #list.rows do list.rows[i]:Hide() end
    list:SetHeight(2 + #rows * ROW_H)
end

function BRutus:CreateNowPanel(panel, win)
    local column = CreateFrame("Frame", nil, panel)
    column:SetPoint("TOPLEFT", 0, 0)
    column:SetPoint("BOTTOMLEFT", 0, 0)
    column:SetWidth(COLUMN_W)
    panel.column = column

    local home = CreateFrame("Frame", nil, panel)
    home:SetPoint("TOPLEFT", column, "TOPRIGHT", GAP, 0)
    home:SetPoint("BOTTOMRIGHT", 0, 0)
    home:Hide()
    panel.home = home

    local raid, height = nil, 0

    -- Next raid
    local raidCard = newCard(column, L["Next raid"])
    raidCard:SetPoint("TOPLEFT", 0, 0)
    raidCard:SetPoint("TOPRIGHT", 0, 0)
    local clock = newText(raidCard, 19, "countdown", C.gold)
    clock:SetPoint("TOPRIGHT", -CARD_PAD, -CARD_PAD)
    clock:SetJustifyH("RIGHT")
    local raidMeta = newText(raidCard, 10, "caption", C.label)
    raidMeta:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + TITLE_ROW))
    raidMeta:SetPoint("TOPRIGHT", -CARD_PAD, -(CARD_PAD + TITLE_ROW))
    local openCal = UI:SetButtonVariant(UI:CreateButton(raidCard, L["Open calendar"], 140, 26), "primary")
    openCal:SetPoint("TOPLEFT", CARD_PAD, -(CARD_PAD + TITLE_ROW + 22))
    openCal:SetScript("OnClick", function() UI:OpenWindow("guild", "calendar", raid and raid.when) end)
    raidCard:SetHeight(CARD_PAD + TITLE_ROW + 22 + 26 + CARD_PAD)
    panel.clock, panel.raidMeta, panel.openCalendar = clock, raidMeta, openCal

    -- Needs me
    local needsCard = newCard(column, L["Needs me"])
    needsCard:SetPoint("TOPLEFT", raidCard, "BOTTOMLEFT", 0, -GAP)
    needsCard:SetPoint("TOPRIGHT", raidCard, "BOTTOMRIGHT", 0, -GAP)
    local needsList = newList(needsCard)
    panel.needsList = needsList

    -- Activity: the rest of the column
    local feedCard = newCard(column, L["Activity"])
    feedCard:SetPoint("TOPLEFT", needsCard, "BOTTOMLEFT", 0, -GAP)
    feedCard:SetPoint("TOPRIGHT", needsCard, "BOTTOMRIGHT", 0, -GAP)
    feedCard:SetPoint("BOTTOM", column, "BOTTOM", 0, 0)
    local feedList = newList(feedCard)
    panel.feedList = feedList

    local function tickClock()
        clock:SetText(raid and Agora.Clock(raid.when - now()) or DASH)
    end

    -- Data is fetched on show, on the ticker and on roster events. A resize
    -- only repaints what was fetched: officer work walks the whole roster.
    local needs, feed, loading = {}, {}, false

    local function paint()
        if raid then
            local comp = BRutus.Calendar:GetComposition(raid)
            raidMeta:SetText((raid.title or "?") .. DOT .. date("%a %H:%M", raid.when)
                .. DOT .. string.format(L["%d going"], comp.yes))
        else
            raidMeta:SetText(L["No raid scheduled."])
        end
        openCal:SetShown(allowed("guild"))
        tickClock()

        local rows = {}
        if loading then
            for _, w in ipairs(LOADING_BARS) do rows[#rows + 1] = { "loading", w } end
        else
            for i, item in ipairs(needs) do
                if i > MAX_NEEDS then break end
                rows[#rows + 1] = { "need", item }
            end
            if #rows == 0 then rows[1] = { "empty", L["All caught up"] } end
        end
        fill(needsList, rows)
        needsCard:SetHeight(CARD_PAD + TITLE_ROW + needsList:GetHeight() + CARD_PAD)

        local feedH = height - raidCard:GetHeight() - needsCard:GetHeight() - 2 * GAP
        local fit = math.max(1, UI:ResolveRows(feedH, ROW_H, CARD_PAD + TITLE_ROW + 2 + CARD_PAD))
        rows = {}
        for i, item in ipairs(feed) do
            if i > fit then break end
            rows[#rows + 1] = { "feed", item }
        end
        if #rows == 0 then rows[1] = { "empty", L["Nothing in the last 48 hours."] } end
        fill(feedList, rows)
    end

    local function refresh()
        BRutus:SafeCall(function()
            raid = Agora:NextRaid()
            loading = Agora:RosterLoading()
            needs = loading and {} or Agora:NeedsMe()
            feed = Agora:Activity(MAX_FEED)
            paint()
        end)
    end
    panel.Refresh = refresh

    local homeBuilt = false
    UI:MakeResponsive(panel, function(_, w, h)
        height = h
        local wide = w >= HOME_MIN
        column:SetWidth(wide and COLUMN_W or w)
        if wide and not homeBuilt then
            homeBuilt = true
            BRutus:SafeCall(function() BRutus:CreateDashboardPanel(home, win) end)
        end
        home:SetShown(wide)
        paint()
    end)

    -- The clock ticks every second while the tab is on screen; the lists
    -- every ten, and whenever the roster changes.
    local ticks = 0
    panel:HookScript("OnShow", function()
        refresh()
        if panel.ticker then return end
        panel.ticker = C_Timer.NewTicker(1, function()
            ticks = ticks + 1
            if ticks % 10 == 0 then refresh() else tickClock() end
        end)
    end)
    panel:HookScript("OnHide", function()
        if panel.ticker then
            panel.ticker:Cancel()
            panel.ticker = nil
        end
    end)
    BRutus.Compat.RegisterEvent(panel, "GUILD_ROSTER_UPDATE")
    panel:SetScript("OnEvent", function() if panel:IsVisible() then refresh() end end)
end
