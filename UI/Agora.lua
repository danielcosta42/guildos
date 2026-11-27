----------------------------------------------------------------------
-- Guild OS - What the first screen knows (agora; issue #14)
-- The data the Salão (UI/Salao.lua, #445) draws: the next raid, what needs this
-- player, the newest notices and what just happened, each with the screen that
-- owns it, and the 28px bar's three numbers. Frame-free, so tools/window-shell.lua
-- tests it. The Now column and its cards drew this until the Salão replaced them.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local Agora = {}
UI.Agora = Agora

-- The sketch's grid (Main.dc.html): a 12px gutter, UI.GAP once the window is under 620px.
local GUTTER        = 12
local NARROW_W      = 604        -- a 620px window's content, inside its 8px padding
local RECENT        = 48 * 3600  -- how far back the activity goes
local ANSWER_WITHIN = 7 * 86400  -- a raid this close asks for an answer
local MAX_FEED      = 12
local MAX_NOTICES   = 3          -- the bulletin's newest active notices (issue #418)
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

-- The two counts that walk the whole roster (the inactive members, the promotions to review): counted again at
-- most every ROSTER_COUNTS_TTL seconds (memory audit, memoria.md). The window's title asked for them on every
-- group and roster event and every 10 s, ~200 KB of tables each time on a guild of 180; days offline and
-- attendance do not move in a minute. ResetRosterCounts drops them (a line of the roster log: a join, a leave, a
-- rank change).
local ROSTER_COUNTS_TTL = 60
local counts = { at = nil, inactive = 0, promote = 0 }
function Agora:RosterCounts(gm, days)
    local t = now()
    if counts.at and t - counts.at < ROSTER_COUNTS_TTL and t >= counts.at and counts.days == days
        and counts.gm == gm then
        return counts.inactive, counts.promote
    end
    local inactive, promote = 0, 0
    if gm and gm.GetInactiveMembers then inactive = #gm:GetInactiveMembers(days) end
    if gm and gm.GetSuggestions then
        local s = gm:GetSuggestions()
        promote = #(s.promoteCandidates or {})
    end
    counts.at, counts.days, counts.gm, counts.inactive, counts.promote = t, days, gm, inactive, promote
    return inactive, promote
end
function Agora:ResetRosterCounts() counts.at = nil end

-- What needs this player, urgent first: { text, urgent, id, sub, filter } each. Only
-- items whose screen this player can open, so every row is a way in.
function Agora:NeedsMe()
    local urgent, normal = {}, {}
    -- `count`: how many things the line stands for (a red count on the Officers' Room and its entry, #449).
    local function add(list, text, id, sub, filter, count)
        if allowed(id) then
            list[#list + 1] = { text = text, urgent = list == urgent, id = id, sub = sub, filter = filter,
                                count = count, officer = GuildOS:IsOfficer() and id ~= "guild" or nil }
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
        -- The trials ready to review, the count the login line gives (#249); the digest no longer repeats it (B10).
        if tt and tt.CountReady then
            local n = tt:CountReady()
            if n > 0 then add(urgent, string.format(L["%d trial(s) ready to review"], n), "trials", nil, nil, n) end
        end

        local gm = GuildOS.GuildManager
        local days = gm and gm.DEFAULT_INACTIVE_DAYS or 30
        local inactive, promote = Agora:RosterCounts(gm, days)
        if inactive > 0 then
            add(normal, string.format(L["%d inactive over %dd"], inactive, days), "management", "inactive", nil, inactive)
        end
        -- Promotions only: its ready trials are the ones the trials row counts.
        if promote > 0 then
            add(normal, string.format(L["%d promotions to review"], promote), "management", "suggest", nil, promote)
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
            if n > 0 then add(normal, string.format(L["%d applicants waiting"], n), "recruitment", "scanner", nil, n) end
        end
    end

    for _, item in ipairs(normal) do urgent[#urgent + 1] = item end
    return urgent
end

-- The officers' work waiting, for the Officers' Room's door and its entries (#449): the total, and a count per
-- feature and per feature:sub-tab. Only an officer's; a member gets 0 and an empty table.
function Agora:OfficerCounts()
    local total, by = 0, {}
    if not GuildOS:IsOfficer() then return 0, by end
    for _, n in ipairs(self:NeedsMe()) do
        if n.officer and n.count then
            total = total + n.count
            by[n.id] = (by[n.id] or 0) + n.count
            if n.sub then by[n.id .. ":" .. n.sub] = (by[n.id .. ":" .. n.sub] or 0) + n.count end
        end
    end
    return total, by
end

-- The bulletin's newest active notices (issue #418): { ts, text, id, sub } each, opening the board. None when this
-- player cannot open the guild's tab, or no notice is running: then the section is not drawn.
function Agora:Notices(limit)
    local B = GuildOS.Bulletin
    if not (B and B.Active and GuildOS.db and GuildOS.db.bulletin and allowed("guild")) then return {} end
    local out = {}
    for _, m in ipairs(B:Active(now(), limit or MAX_NOTICES)) do
        -- An officer's text: one line, no links or textures on the tab (#377).
        local text = GuildOS.SanitizeUserText and GuildOS:SanitizeUserText(m.text) or m.text
        out[#out + 1] = { ts = tonumber(m.ts) or 0, text = text, id = "guild", sub = "bulletin" }
    end
    return out
end

local ROSTER_SAME = 15 * 60   -- seconds within which the same roster action on the same person is one happening
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

    -- One happening, one line (#449): the game's message and this client's roster diff (`loc`), or two officers'
    -- copies, file the same join or leave twice, a few minutes apart. The same action on the same person within
    -- ROSTER_SAME seconds is one; the game's line wins over the diff.
    local events = (db.rosterLog and db.rosterLog.events) or {}
    local function sameAs(a, b)
        return a ~= b and a.action == b.action and tostring(a.target or ""):lower() == tostring(b.target or ""):lower()
            and math.abs((a.timestamp or 0) - (b.timestamp or 0)) <= ROSTER_SAME
    end
    local shown = {}
    -- A line older than the window less ROSTER_SAME is neither drawn nor anyone's copy: skipped before any work
    -- (the log holds a thousand lines, and the Hall reads this every 15 s; memoria.md).
    local oldest = since - ROSTER_SAME
    for _, e in ipairs(events) do
        local fmt = (tonumber(e.timestamp) or 0) > oldest and ROSTER_ACTION[e.action] or nil
        local dup = false
        if fmt then
            for _, o in ipairs(shown) do
                if sameAs(e, o) then dup = true break end
            end
            if not dup and e.loc then
                for _, o in ipairs(events) do
                    if not o.loc and sameAs(e, o) then dup = true break end
                end
            end
        end
        if fmt and not dup then
            shown[#shown + 1] = e
            if (e.timestamp or 0) > since then
                add(e.timestamp, string.format(fmt, e.target or "?", e.detail or ""), "management", "log", nil, e.target)
            end
        end
    end
    -- The Loot Tracker switch hides the loot history here too (audit B17).
    for _, e in ipairs(GuildOS:IsFeatureEnabled("lootTracker") and db.lootHistory or {}) do
        if (e.timestamp or 0) > since then
            add(e.timestamp, string.format(L["%s received %s"], e.player or "?", e.itemLink or e.itemName or "?"), "loot",
                "history", e.playerKey)
        end
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
