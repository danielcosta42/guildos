----------------------------------------------------------------------
-- Guild OS - Now (agora; issue #14)
-- The first tab, and what the hub used to be: a live column that answers
-- when the next raid is, what needs this player and what just happened.
-- Every row opens the screen that owns it. Laid out as the approved sketch
-- (#377): the column's sections have no box and a 1px rule between them,
-- the countdown is big in Mono, and the home cards (UI/Dashboard.lua) are
-- a grid of equal cards beside the column, or under it once the tab is
-- narrow. The data half is frame-free, so tools/window-shell.lua tests it;
-- tools/dashboard-layout.lua checks the layout in both styles.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local Agora = {}
UI.Agora = Agora

local WHITE         = "Interface\\Buttons\\WHITE8x8"
-- The sketch's grid (Main.dc.html): a 12px gutter, UI.GAP once the window is under 620px.
local GUTTER        = 12
local NARROW_W      = 604        -- a 620px window's content, inside its 8px padding
local SIDE_MIN      = 780        -- from this content width the cards sit beside the column (UI.LADDER "wide")
local LINE_GAP      = 6          -- between the next raid's lines
local SECTION_GAP   = 16         -- from a section's last line down to the next one's rule
local RULE_GAP      = 12         -- CreateSectionTitle draws the rule this far over a title
local TITLE_GAP     = 4          -- under a section title, before its rows
local ROW_H         = 24         -- a list row, as a table row (Componentes.dc.html)
local MARK          = 6
local TIME_W        = 44
local ARROW_W       = 10
local STACKED_FEED  = 5          -- activity rows while the cards follow the column down
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
    for _, m in pairs((GuildOS.db and GuildOS.db.members) or {}) do
        local t = type(m) == "table" and m.lastSync
        if t and (not newest or t > newest) then newest = t end
    end
    return newest
end

-- The next raid still to start. Events made before kinds existed are raids.
function Agora:NextRaid()
    local cal = GuildOS.Calendar
    -- Its saved table exists only once Calendar has started.
    if not (cal and cal.GetUpcoming and GuildOS.db and GuildOS.db.calendar) then return nil end
    local t = now()
    for _, e in ipairs(cal:GetUpcoming(false)) do
        if (e.kind == nil or e.kind == "RAID") and (e.when or 0) > t then return e end
    end
    return nil
end

-- The raid the Iniciar raide button acts on here (issue #400), and its name when the card shows another one: the
-- site's raid in its window (CompanionImport:ButtonRaid), while this player may lead its invites (CanInvite: the
-- companion on, and alone, the group's leader or an assistant). Nil when there is none.
function Agora:StartRaid(card)
    local I = GuildOS.CompanionImport
    local roster = I and GuildOS.RaidStart and I:ButtonRaid()
    if not (roster and I:CanInvite(roster)) then return nil end
    local cal = GuildOS.Calendar
    if card and cal and cal.WebEventId and cal:WebEventId(roster) == card.id then return roster, nil end
    local title = roster.title
    if not title or title == "" then title = roster.instance or "?" end
    return roster, GuildOS.SanitizeUserText and GuildOS:SanitizeUserText(title) or title
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

    local cal, raid = GuildOS.Calendar, self:NextRaid()
    -- A raid planned on the site is answered there: asked here, nobody could ever clear it (#146).
    local inGame = raid and not (cal.IsWebEvent and cal:IsWebEvent(raid))
    if inGame and cal.MyRsvp and not cal:MyRsvp(raid) and raid.when - now() <= ANSWER_WITHIN then
        local title = raid.title or "?"   -- a member's or the site's text (#377)
        add(normal, string.format(L["You have not answered: %s"],
            GuildOS.SanitizeUserText and GuildOS:SanitizeUserText(title) or title), "guild", "calendar", raid.when)
    end

    if GuildOS:IsOfficer() then
        local tt = GuildOS.TrialTracker
        -- The trials ready to review, the count the login line and the digest give (#249).
        if tt and tt.CountReady then
            local n = tt:CountReady()
            if n > 0 then add(urgent, string.format(L["%d trial(s) ready to review"], n), "trials") end
        end

        local gm = GuildOS.GuildManager
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

        local rs = GuildOS.RecruitScanner
        if rs and rs.GetInbox then
            -- Only replies newer than the last look at the inbox are waiting: counting every one
            -- ever stored, the row never went away (issue #311).
            local readAt = tonumber(GuildOS.db and GuildOS.db.recruitScanner
                and GuildOS.db.recruitScanner.inboxReadAt) or 0
            local n = 0
            for _, e in ipairs(rs:GetInbox()) do
                if type(e) == "table" and (tonumber(e.ts) or 0) > readAt then n = n + 1 end
            end
            if n > 0 then add(normal, string.format(L["%d applicants waiting"], n), "recruitment", "scanner") end
        end
    end

    for _, item in ipairs(normal) do urgent[#urgent + 1] = item end
    return urgent
end

local ROSTER_ACTION = {
    join    = L["%s joined the guild"],
    leave   = L["%s left the guild"],
    kick    = L["%s was removed from the guild"],
    promote = L["%s was promoted to %s"],
    demote  = L["%s was demoted to %s"],
}

-- The saved key for a short name, when exactly one member has it.
local function memberKey(short)
    if not short then return nil end
    local found
    for key in pairs((GuildOS.db and GuildOS.db.members) or {}) do
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
    local since, db, out = now() - RECENT, GuildOS.db or {}, {}
    local function add(ts, text, id, sub, key, target)
        if (ts or 0) <= since then return end
        if not allowed(id) then id, sub = "roster", nil end
        out[#out + 1] = { ts = ts, text = text, id = id, sub = sub, key = key, target = target }
    end

    for _, e in ipairs((db.rosterLog and db.rosterLog.events) or {}) do
        local fmt = ROSTER_ACTION[e.action]
        if fmt then
            add(e.timestamp, string.format(fmt, e.target or "?", e.detail or ""), "management", "log", nil, e.target)
        end
    end
    for _, e in ipairs(db.lootHistory or {}) do
        add(e.timestamp, string.format(L["%s received %s"], e.player or "?", e.itemLink or e.itemName or "?"), "loot",
            "history", e.playerKey)
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

-- The gutter between the column and the cards, and between the cards (Main.dc.html).
function Agora.Gutter(width)
    return (width or 0) < NARROW_W and UI.GAP or GUTTER
end

local function newText(parent, size, role, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size, role)
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(color.r, color.g, color.b)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A single line's height, never under its font's size: the stubs and a font still loading read less.
local function lineH(fs, least)
    return math.max(least, math.ceil(fs:GetStringHeight() or 0))
end

-- A list of rows straight on the tab, no box (#377): a 1px line between rows does the separating.
local function newList(parent)
    local list = CreateFrame("Frame", nil, parent)
    list.rows = {}
    return list
end

local function stamp(ts)
    if now() - ts < 86400 then return date("%H:%M", ts) end
    return GuildOS:LocalDate("%a", ts)
end

local function acquireRow(list, i)
    local r = list.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, (1 - i) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, (1 - i) * ROW_H)

    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetTexture(WHITE)
    r.hover:SetAllPoints()
    r.hover:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
    r.hover:Hide()

    r.line = UI:CreateSeparator(r)
    r.line:SetPoint("BOTTOMLEFT", 0, 0)
    r.line:SetPoint("BOTTOMRIGHT", 0, 0)

    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetTexture(WHITE)
    r.mark:SetSize(MARK, MARK)
    r.mark:SetPoint("LEFT", 0, 0)

    -- On the right, as in the sketch: a row's time, or the ">" that says it opens something.
    r.time = newText(r, nil, "caption", C.label)
    r.time:SetPoint("RIGHT", 0, 0)
    r.time:SetWidth(TIME_W)
    r.time:SetJustifyH("RIGHT")
    r.arrow = newText(r, nil, "caption", C.label)
    r.arrow:SetPoint("RIGHT", 0, 0)
    r.arrow:SetText(">")

    r.text = newText(r, 12, nil, C.text)

    -- The loading state: a static bar where the text will be.
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetTexture(WHITE)
    r.bar:SetHeight(8)
    r.bar:SetPoint("LEFT", 0, 0)
    r.bar:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)

    r:SetScript("OnEnter", function(self) if self.go then self.hover:Show() end end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:SetScript("OnClick", function(self) if self.go then self.go() end end)
    list.rows[i] = r
    return r
end

-- Paint a row as "need", "feed", "empty" (value: the line) or "loading"
-- (value: the bar's width). Items open their screen, filtered. The last row
-- has no line under it: the next section's rule, or the tab's end, follows.
local function paintRow(r, kind, value, last)
    r.go = nil
    r.hover:Hide()
    r.mark:Hide()
    r.time:Hide()
    r.arrow:Hide()
    r.bar:Hide()
    r.text:Hide()
    r.line:SetShown(not last)
    r.text:ClearAllPoints()
    if kind == "loading" then
        r.bar:SetWidth(value)
        r.bar:Show()
    elseif kind == "empty" then
        r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.text:SetTextColor(C.label.r, C.label.g, C.label.b)
        r.text:SetText(value)
        r.text:Show()
    else
        local right
        if kind == "need" then
            -- Urgent in danger, the rest a neutral mark: gold is not a status (#361).
            local col = value.urgent and C.danger or C.label
            r.mark:SetVertexColor(col.r, col.g, col.b, 1)
            r.mark:Show()
            r.arrow:Show()
            r.text:SetPoint("LEFT", r, "LEFT", MARK + 8, 0)
            right = ARROW_W + 8
        else
            r.time:SetText(stamp(value.ts))
            r.time:Show()
            r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
            right = TIME_W + 8
        end
        r.text:SetPoint("RIGHT", r, "RIGHT", -right, 0)
        r.text:SetTextColor(C.text.r, C.text.g, C.text.b)
        r.text:SetText(value.text)
        r.text:Show()
        r.go = function()
            UI:OpenWindow(value.id, value.sub, value.filter)
            local data = value.key and GuildOS.db and GuildOS.db.members and GuildOS.db.members[value.key]
            if data and GuildOS.ShowMemberDetail then GuildOS:ShowMemberDetail(data) end
        end
    end
    r:Show()
end

local function fill(list, rows)
    for i, row in ipairs(rows) do paintRow(acquireRow(list, i), row[1], row[2], i == #rows) end
    for i = #rows + 1, #list.rows do list.rows[i]:Hide() end
    list:SetHeight(#rows * ROW_H)
end

local function place(region, y, across)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", 0, -y)
    if across then region:SetPoint("TOPRIGHT", 0, -y) end
end

function GuildOS:CreateNowPanel(panel, win)
    -- One scroll area: narrow, the cards follow the column down (#377).
    local scroll, content = UI:CreateScrollFrame(panel, "GuildOSNowScroll")
    scroll:SetAllPoints(panel)
    UI:BindScrollChildWidth(scroll, content)
    panel.scroll, panel.content = scroll, content

    local column = CreateFrame("Frame", nil, content)
    column:SetPoint("TOPLEFT", 0, 0)
    panel.column = column

    local home = CreateFrame("Frame", nil, content)
    home:SetPoint("TOPLEFT", column, "TOPRIGHT", GUTTER, 0)
    panel.home = home
    -- The rule over the cards once they are under the column.
    local gridRule = UI:CreateSeparator(content)
    gridRule:Hide()
    panel.gridRule = gridRule

    local raid, tabW, width, height = nil, 0, 0, 0

    -- Next raid: its name, when and who is going, the countdown, the way to the calendar.
    local raidTitle = UI:CreateSectionTitle(column, L["Next raid"], true)
    raidTitle:SetPoint("TOPLEFT", 0, 0)
    local raidName = newText(column, nil, "memberName", C.text)
    local raidMeta = newText(column, nil, "caption", C.label)
    local clock = newText(column, nil, "countdown", C.text)
    -- A link, as in the sketch: the screen's one primary is the answer to the next event (Dashboard).
    local openCal = UI:SetButtonVariant(UI:CreateButton(column, L["Open calendar"], 40, 26), "ghost")
    -- Its mono label and 4px either side (the sketch's "b g"): CreateButton grows only a label that spills.
    openCal:SetWidth(math.ceil(openCal.label:GetStringWidth() or 0) + 8)
    openCal:SetScript("OnClick", function() UI:OpenWindow("guild", "calendar", raid and raid.when) end)
    panel.raidTitle, panel.raidName, panel.raidMeta = raidTitle, raidName, raidMeta
    panel.clock, panel.openCalendar = clock, openCal

    -- Iniciar raide (issue #400): while a raid of the site is in its window (Import:ButtonRaid) and this player may
    -- lead its invites, the same button as the owner's prompt and the Web tab (UI/WebPanel.lua). Not the primary:
    -- that is the answer to the next event. The raid it acts on is not always the card's (an hour in, the card has
    -- moved on to the next one): then its name is said over it.
    local stepRoster, stepFor
    local startFor = newText(column, nil, "caption", C.label)
    local start = UI.CreateRaidStepper and UI:CreateRaidStepper(column, { roster = function() return stepRoster end })
    if start then
        start.why:SetWordWrap(false)   -- one line: the column's layout does not move under it
        start:Hide()
        start.why:Hide()
    end
    startFor:Hide()
    panel.startRaid, panel.startFor = start, startFor

    local needsTitle = UI:CreateSectionTitle(column, L["Needs me"])
    local needsList = newList(column)
    local feedTitle = UI:CreateSectionTitle(column, L["Activity"])
    local feedList = newList(column)
    panel.needsTitle, panel.needsList = needsTitle, needsList
    panel.feedTitle, panel.feedList = feedTitle, feedList

    local function tickClock()
        clock:SetText(raid and Agora.Clock(raid.when - now()) or DASH)
    end

    -- Data is fetched on show, on the ticker and on roster events. A resize
    -- only repaints what was fetched: officer work walks the whole roster.
    local needs, feed, loading = {}, {}, false

    local function paint()
        if width < 1 then return end
        -- Both read the tab's own width, as the ladder does: the scroll child is a gutter narrower.
        local g = Agora.Gutter(tabW)
        local side = tabW >= SIDE_MIN
        -- Beside the cards the column is one of three equal columns: span 4 of 12 (Agora.dc.html).
        local colW = side and math.floor((width - 2 * g) / 3) or width
        column:SetWidth(colW)

        local y = lineH(raidTitle, 14) + LINE_GAP
        raidName:SetShown(raid ~= nil)
        if raid then
            local comp = GuildOS.Calendar:GetComposition(raid)
            -- An event title is a member's or the site's text: no textures or links on the tab (#377).
            local title = raid.title or "?"
            raidName:SetText(GuildOS.SanitizeUserText and GuildOS:SanitizeUserText(title) or title)
            place(raidName, y, true)
            y = y + lineH(raidName, 12) + LINE_GAP
            raidMeta:SetText(GuildOS:LocalDate(L["%a %d %b, %H:%M"], raid.when) .. DOT
                .. string.format(L["%d going"], comp.yes))
        else
            raidMeta:SetText(L["No raid scheduled."])
        end
        place(raidMeta, y, true)
        y = y + lineH(raidMeta, 10) + LINE_GAP + 4
        tickClock()
        place(clock, y)
        y = y + lineH(clock, 40)
        local cal = allowed("guild")
        openCal:SetShown(cal)
        if cal then
            place(openCal, y + LINE_GAP + 2)
            y = y + LINE_GAP + 2 + openCal:GetHeight()
        end
        -- Iniciar raide: its raid's name when it is not the card's, the button, the line of why it is off.
        local stepping = start and stepRoster ~= nil or false
        startFor:SetShown(stepping and stepFor ~= nil)
        if start then
            start:SetShown(stepping)
            start.why:SetShown(stepping)
        end
        if stepping then
            if stepFor then
                startFor:SetText(stepFor)
                place(startFor, y + LINE_GAP, true)
                y = y + LINE_GAP + lineH(startFor, 10)
            end
            place(start, y + LINE_GAP + 2)
            y = y + LINE_GAP + 2 + start:GetHeight()
            place(start.why, y + 2, true)
            y = y + 2 + lineH(start.why, 10)
        end

        y = y + SECTION_GAP + RULE_GAP
        place(needsTitle, y)
        y = y + lineH(needsTitle, 14) + TITLE_GAP
        local rows = {}
        if loading then
            for _, bw in ipairs(LOADING_BARS) do rows[#rows + 1] = { "loading", bw } end
        else
            for i, item in ipairs(needs) do
                if i > MAX_NEEDS then break end
                rows[#rows + 1] = { "need", item }
            end
            if #rows == 0 then rows[1] = { "empty", L["All caught up"] } end
        end
        fill(needsList, rows)
        place(needsList, y, true)
        y = y + needsList:GetHeight()

        y = y + SECTION_GAP + RULE_GAP
        place(feedTitle, y)
        y = y + lineH(feedTitle, 14) + TITLE_GAP
        -- Beside the cards, activity runs to the bottom of the tab; under them, a few rows.
        local fit = side and math.max(1, UI:ResolveRows(height - y, ROW_H, 0)) or STACKED_FEED
        rows = {}
        for i, item in ipairs(feed) do
            if i > math.min(fit, MAX_FEED) then break end
            rows[#rows + 1] = { "feed", item }
        end
        if #rows == 0 then rows[1] = { "empty", L["Nothing in the last 48 hours."] } end
        fill(feedList, rows)
        place(feedList, y, true)
        y = y + feedList:GetHeight()
        column:SetHeight(y)

        -- The cards: beside the column sharing the tab's height, or under it below a rule.
        home:ClearAllPoints()
        local gridW, gridY
        if side then
            home:SetPoint("TOPLEFT", column, "TOPRIGHT", g, 0)
            gridW = width - colW - g
            gridRule:Hide()
        else
            gridRule:ClearAllPoints()
            gridRule:SetPoint("TOPLEFT", 0, -(y + SECTION_GAP))
            gridRule:SetPoint("TOPRIGHT", 0, -(y + SECTION_GAP))
            gridRule:Show()
            gridY = y + SECTION_GAP + RULE_GAP
            home:SetPoint("TOPLEFT", 0, -gridY)
            gridW = width
        end
        home:SetWidth(gridW)
        local gridH = home.Layout and home.Layout(gridW, side and height or nil, side, g) or 0
        home:SetHeight(math.max(1, gridH))
        content:SetHeight(math.max(1, side and math.max(height, y, gridH) or (gridY + gridH)))
    end

    local function refresh()
        local t = GuildOS.Perf:Start()
        GuildOS:SafeCall(function()
            raid = Agora:NextRaid()
            stepRoster, stepFor = Agora:StartRaid(raid)
            loading = Agora:RosterLoading()
            needs = loading and {} or Agora:NeedsMe()
            feed = Agora:Activity(MAX_FEED)
            paint()
        end)
        GuildOS.Perf:Stop("window now tab", t)
    end
    panel.Refresh = refresh

    -- The cards are built with the column: they are on the tab at every width now.
    GuildOS:SafeCall(function() GuildOS:CreateDashboardPanel(home, win) end)
    -- A card that comes or goes (the guild's setup) changes the grid's height.
    home.relayout = function() UI:Relayout(panel) end

    UI:MakeResponsive(panel, function(_, w, h)
        -- The scroll child stops short of the scroll bar (BindScrollChildWidth sets the same).
        tabW, width, height = w, math.max(0, w - UI.SCROLL_GUTTER), h
        content:SetWidth(math.max(1, width))
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
    GuildOS.Compat.RegisterEvent(panel, "GUILD_ROSTER_UPDATE")
    -- At most once every ROSTER_GAP seconds on a roster update (issue #324).
    local function visibleRefresh()
        if panel:IsVisible() then refresh() end
    end
    panel:SetScript("OnEvent", function() GuildOS:Coalesce("agora", GuildOS.ROSTER_GAP, visibleRefresh) end)
end
