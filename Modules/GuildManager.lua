----------------------------------------------------------------------
-- Guild OS - Guild Manager (Leadership Suite)
-- Officer-gated guild leadership tools: rank changes, kicks, MOTD / Guild
-- Info editing, inactivity reports, promotion suggestions, and a local
-- action log. Business logic only — no UI frames (Rule 2 / Rule 10).
----------------------------------------------------------------------
local GuildManager = {}
GuildOS.GuildManager = GuildManager
local L = GuildOS.L

-- Cap on the locally-stored action log (ring buffer; oldest entries dropped).
local LOG_MAX = 200
-- Default inactivity threshold (days) for the purge report.
local DEFAULT_INACTIVE_DAYS = 30
GuildManager.DEFAULT_INACTIVE_DAYS = DEFAULT_INACTIVE_DAYS
-- Attendance % at/above which a non-officer member is flagged a promotion candidate in the suggestions view:
-- the "Promote regulars" preset's own threshold (#448 B8), so Suggestions and Presets never disagree.
local PROMO_ATTENDANCE_MIN = 80
local function promoAttendanceMin()
    local MP = GuildOS.ModPresets
    return (MP and MP.PromoteAttendance and MP:PromoteAttendance()) or PROMO_ATTENDANCE_MIN
end

function GuildManager:Initialize()
    if not GuildOS.db.managementLog then
        -- Ring buffer of { action, target, detail, author, timestamp }.
        GuildOS.db.managementLog = {}
    end
end

----------------------------------------------------------------------
-- Permission helpers
-- The Can* guild globals may be absent on some clients: Compat nil-guards
-- them, and a missing API resolves to "permission denied".
----------------------------------------------------------------------
function GuildManager:CanPromote()
    return GuildOS.Compat.CanGuildPromote()
end

function GuildManager:CanDemote()
    return GuildOS.Compat.CanGuildDemote()
end

function GuildManager:CanKick()
    return GuildOS.Compat.CanGuildRemove()
end

function GuildManager:CanSetMOTD()
    return (CanEditMOTD and CanEditMOTD()) and true or false
end

function GuildManager:CanSetGuildInfo()
    return (CanEditGuildInfo and CanEditGuildInfo()) and true or false
end

----------------------------------------------------------------------
-- Roster / rank lookups
----------------------------------------------------------------------
-- Guild roster index for a short or full player name (realm-stripped match). On retail a guild
-- spans connected realms and namesakes share it: the whole name wins, a short one only when it is
-- the only one (Compat.FindGuildRosterIndex; issue #184).
function GuildManager:GetRosterIndex(name)
    if not name or name == "" then return nil end
    if GuildOS.Client.isRetail then return (GuildOS.Compat.FindGuildRosterIndex(name)) end
    local short = name:match("^([^-]+)") or name
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local rosterName = GetGuildRosterInfo(i)
        if rosterName then
            local rShort = rosterName:match("^([^-]+)") or rosterName
            if rShort == short then return i end
        end
    end
    return nil
end

-- Current 0-based rank index for a player name, or nil if not found.
function GuildManager:GetRankIndex(name)
    local idx = self:GetRosterIndex(name)
    if not idx then return nil end
    local _, _, rankIndex = GetGuildRosterInfo(idx)
    return rankIndex
end

-- Ordered list of guild ranks as { index = <0-based>, name = <string> }.
-- GuildControl* is 1-based (1 = Guild Master); roster rankIndex is 0-based.
function GuildManager:GetRanks()
    local ranks = {}
    local num = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    for i = 1, num do
        local nm = (GuildControlGetRankName and GuildControlGetRankName(i)) or ("Rank " .. (i - 1))
        if not nm or nm == "" then nm = "Rank " .. (i - 1) end
        ranks[i] = { index = i - 1, name = nm }
    end
    return ranks
end

-- Display name for a 0-based rank index.
function GuildManager:GetRankName(rankIndex)
    if not rankIndex then return "?" end
    local nm = GuildControlGetRankName and GuildControlGetRankName(rankIndex + 1)
    if not nm or nm == "" then return "Rank " .. rankIndex end
    return nm
end

----------------------------------------------------------------------
-- Actions
--
-- IMPORTANT: GuildPromote / GuildDemote / GuildUninvite are PROTECTED
-- (restricted) functions in the Classic / TBC Anniversary client. Only
-- Blizzard's own untainted UI may call them — any addon call raises
-- ADDON_ACTION_FORBIDDEN and does nothing. There is no hardware-event
-- escape (unlike InviteUnit / RandomRoll). So GuildOS performs the
-- "intelligence" (who to promote / kick) and hands the leader off to the
-- secure Blizzard guild panel for the final click. See decisions.md ADR-0010.
----------------------------------------------------------------------

-- Best-effort: open the default Blizzard guild window. Routes through
-- GuildOS:OpenBlizzardGuildUI, which calls the native (unreplaced) toggle with
-- the hijack redirect suppressed. Never calls a protected function.
function GuildManager:OpenNativeGuild()
    if GuildOS.OpenBlizzardGuildUI then
        GuildOS:OpenBlizzardGuildUI()
        return true
    end
    return false
end

-- Explain that a rank/membership change is Blizzard-protected and hand the
-- leader off to the native guild panel. Returns false (action not performed).
function GuildManager:_protectedNotice(actionLabel, name)
    local short = name and (name:match("^([^-]+)") or name) or "?"
    GuildOS:Print(format(
        L["\"%s\" is Blizzard-protected \226\128\148 use the official guild panel. Target: |cffFFD700%s|r."],
        actionLabel, short))
    self:OpenNativeGuild()
    return false
end

-- One member's promotion, demotion or removal (audit M11): a Bulk actions queue of that one member, done by one click
-- of its Next button, the way the game takes it from an addon (ADR-0038), never the protected call. `name` is the
-- roster's name (with its realm where it has one), `key` the member key when the caller holds it; `target`, optional,
-- a 0-based rank to take them to, one step per click. Without Bulk actions, the game's guild panel as before.
-- True when the queue started; otherwise it says why.
function GuildManager:QueueRankAction(action, name, key, target)
    local BA = GuildOS.BulkActions
    if not BA then
        local label = action == "promote" and L["Promote"] or action == "demote" and L["Demote"] or L["Remove from guild"]
        return self:_protectedNotice(label, name)
    end
    key = key or (type(name) == "string" and name ~= "" and GuildOS:KeyOfRosterName(name)) or nil
    return BA:StartOneAndSay(action, key, target, name and (name:match("^([^-]+)") or name))
end

function GuildManager:Promote(name, key)
    return self:QueueRankAction("promote", name, key)
end

function GuildManager:Demote(name, key)
    return self:QueueRankAction("demote", name, key)
end

function GuildManager:Kick(name, key)
    return self:QueueRankAction("remove", name, key)
end

-- Set the guild Message of the Day.
-- On WoW: Forever only the game's own guild panel may set it: an addon's GuildSetMOTD is
-- ADDON_ACTION_FORBIDDEN, seen in game (#377). There the panel opens instead, as for a rank change.
function GuildManager:MOTDNeedsGamePanel()
    return GuildOS.Client and GuildOS.Client.game == "FOREVER" or false
end

function GuildManager:SetMOTD(text)
    if not self:CanSetMOTD() then
        GuildOS:Print(L["|cffFF4444No permission to edit the MOTD.|r"])
        return false
    end
    if self:MOTDNeedsGamePanel() then
        GuildOS:Print(L["On WoW: Forever only the game's guild panel can change the message of the day."])
        self:OpenNativeGuild()
        return false
    end
    if GuildSetMOTD then GuildSetMOTD(text or "") end
    self:LogAction("motd", nil, text)
    return true
end

-- Set the guild Information text.
function GuildManager:SetGuildInfo(text)
    if not self:CanSetGuildInfo() then
        GuildOS:Print(L["|cffFF4444No permission to edit the guild info.|r"])
        return false
    end
    if SetGuildInfoText then SetGuildInfoText(text or "") end
    self:LogAction("info", nil, L["(updated)"])
    return true
end

-- Current MOTD / Guild Info as cached by the client (may be empty until the
-- guild roster has been queried at least once this session).
function GuildManager:GetMOTD()
    return (GetGuildRosterMOTD and GetGuildRosterMOTD()) or ""
end

function GuildManager:GetGuildInfo()
    return (GetGuildInfoText and GetGuildInfoText()) or ""
end

----------------------------------------------------------------------
-- Inactivity report
----------------------------------------------------------------------
-- Days since a roster member was last online. Uses GetGuildRosterLastOnline
-- (years, months, days, hours). Returns nil for online members (API nil) or
-- when the API is unavailable.
function GuildManager:GetDaysOffline(rosterIndex)
    if not GetGuildRosterLastOnline then return nil end
    local years, months, days, hours = GetGuildRosterLastOnline(rosterIndex)
    if not years and not months and not days and not hours then
        return nil
    end
    return (years or 0) * 365 + (months or 0) * 30 + (days or 0) + (hours or 0) / 24
end

-- Roster members offline for at least `days`, sorted most-inactive first. `countAlts` (nil: the Inactivity screen's
-- setting, on by default; specs/salao/manutencao-roster.md): a character whose main or another alt of the same
-- player was seen within `days` is not inactive. Each entry carries `seen`, the group's most recently seen other
-- character ({ name, days, main }, RosterMaint.GroupSeen), when it has one, and `safe` when the member is on the
-- safe list now (MemberMarks:IsSafe: a mark past its end no longer counts). `skipSafe`: those are left out (the
-- digest's "to review" count: the officers already said to keep them).
function GuildManager:GetInactiveMembers(days, countAlts, skipSafe)
    days = days or DEFAULT_INACTIVE_DAYS
    local RM = GuildOS.RosterMaint
    local MM = GuildOS.MemberMarks
    local noteOf = RM and RM.NoteText or function(v) return type(v) == "string" and v or "" end
    local onotes = MM and GuildOS.Compat.CanViewOfficerNote()
    if countAlts == nil then countAlts = not RM or RM:CountAlts() end
    local lines = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, rankIndex, level, _, _, note, onote, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local off = (not isOnline) and self:GetDaysOffline(i) or nil
            lines[#lines + 1] = { i = i, name = name, rankName = rankName, rankIndex = rankIndex, level = level,
                class = classFile, online = isOnline, off = off, note = note, onote = onote,
                key = GuildOS:KeyOfRosterName(name), short = name:match("^([^-]+)") or name,
                days = isOnline and 0 or (off and math.floor(off)) or nil }
        end
    end
    -- The groups in one pass over the lines (never GetLinkedChars per member: it walks every link).
    local seen = {}
    if RM then
        local rows = {}
        for k, l in ipairs(lines) do rows[k] = { key = l.key, name = l.short, days = l.days } end
        seen = RM.GroupSeen(rows, GuildOS.db and GuildOS.db.altLinks)
    end
    local result = {}
    for _, l in ipairs(lines) do
        if not l.online and l.off and l.off >= days then
            local other = seen[l.key]
            local safe = MM and MM:IsSafe(l.key, noteOf(l.note), onotes and noteOf(l.onote) or nil) or false
            if not (countAlts and other and other.days < days) and not (skipSafe and safe) then
                table.insert(result, {
                    index       = l.i,
                    key         = l.key,
                    name        = l.short,
                    fullName    = l.name,
                    rankName    = l.rankName,
                    rankIndex   = l.rankIndex,
                    level       = l.level or 0,
                    class       = l.class or "",
                    daysOffline = math.floor(l.off),
                    seen        = other,
                    safe        = safe or nil,
                })
            end
        end
    end
    table.sort(result, function(a, b) return a.daysOffline > b.daysOffline end)
    return result
end

----------------------------------------------------------------------
-- Promotion / trial suggestions
-- Combines GuildOS-only data (trial progress, raid attendance) into
-- actionable leadership prompts.
----------------------------------------------------------------------
-- Returns { trialsReady = { ... }, promoteCandidates = { ... }, stuckInRank = { ... } }.
function GuildManager:GetSuggestions()
    local trialsReady, promoteCandidates = {}, {}

    -- Trials ready to review (their end, from the guild's length, has passed) → officer should approve / deny.
    if GuildOS.TrialTracker then
        for _, t in ipairs(GuildOS.TrialTracker:GetActiveTrials()) do
            if GuildOS.TrialTracker:IsReady(t.data) then
                local progress = GuildOS.TrialTracker:GetProgress(t.key)
                local att = GuildOS.RaidTracker and GuildOS.RaidTracker:GetAttendance25ManPercent(t.key) or 0
                local short = t.key:match("^([^-]+)") or t.key
                table.insert(trialsReady, {
                    key        = t.key,
                    name       = short,
                    daysSince  = GuildOS.TrialTracker:GetDaysSinceStart(t.key) or 0,
                    attendance = att,
                    ilvlDelta  = progress and progress.ilvlDelta or 0,
                })
            end
        end
        table.sort(trialsReady, function(a, b) return a.attendance > b.attendance end)
    end

    -- Non-officer, non-trial members with strong attendance → promote candidates.
    if GuildOS.RaidTracker then
        local officerMaxRank = GuildOS:GetSetting("officerMaxRank") or 1
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name, rankName, rankIndex, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
            if name then
                local short = name:match("^([^-]+)") or name
                local realm = name:match("-(.+)$") or GetRealmName()
                local key = GuildOS:GetPlayerKey(short, realm)
                local isTrial = GuildOS.TrialTracker and GuildOS.TrialTracker:IsTrial(key)
                local isOfficer = rankIndex and rankIndex <= officerMaxRank
                if not isTrial and not isOfficer then
                    local att = GuildOS.RaidTracker:GetAttendance25ManPercent(key)
                    if att and att >= promoAttendanceMin() then
                        table.insert(promoteCandidates, {
                            key        = key,
                            name       = short,
                            fullName   = name,
                            rankName   = rankName,
                            rankIndex  = rankIndex,
                            class      = classFile or "",
                            attendance = att,
                        })
                    end
                end
            end
        end
        table.sort(promoteCandidates, function(a, b) return a.attendance > b.attendance end)
    end

    -- Long in their rank (specs/salao/manutencao-roster.md): only where this rank may promote.
    local RM = GuildOS.RosterMaint
    local stuckInRank = RM and RM:StuckInRank() or {}

    return { trialsReady = trialsReady, promoteCandidates = promoteCandidates, stuckInRank = stuckInRank }
end

----------------------------------------------------------------------
-- Action log
----------------------------------------------------------------------
-- Append an entry to the local action log (capped ring buffer).
function GuildManager:LogAction(action, target, detail)
    if GuildOS.RosterLog then
        GuildOS.RosterLog:Record(action, target, GuildOS.Compat.PlayerName(), detail)
        return
    end
    local log = GuildOS.db.managementLog
    if not log then
        log = {}
        GuildOS.db.managementLog = log
    end
    local short = target and (target:match("^([^-]+)") or target) or nil
    table.insert(log, {
        action    = action,
        target    = short,
        detail    = detail,
        author    = GuildOS.Compat.PlayerName(),
        timestamp = GetServerTime(),
    })
    -- Trim the oldest entries beyond the cap.
    while #log > LOG_MAX do
        table.remove(log, 1)
    end
end

-- Return the action log newest-first (does not mutate stored order).
function GuildManager:GetLog()
    if GuildOS.RosterLog then return GuildOS.RosterLog:GetLog() end
    local log = GuildOS.db.managementLog or {}
    local out = {}
    for i = #log, 1, -1 do
        out[#out + 1] = log[i]
    end
    return out
end

function GuildManager:ClearLog()
    if GuildOS.RosterLog then
        GuildOS.RosterLog:Clear()
        return
    end
    GuildOS.db.managementLog = {}
end

----------------------------------------------------------------------
-- UI refresh helper
-- Logic modules already drive roster refreshes elsewhere (e.g. TrialTracker),
-- so mirroring that here keeps the management views live after an action.
----------------------------------------------------------------------
function GuildManager:RefreshUI()
    -- Routed through RefreshRosterUI (not a direct rf:RefreshRoster() call)
    -- because the Roster tab builds lazily now — RefreshRoster does not exist
    -- until that tab has been activated at least once, and RefreshRosterUI
    -- nil-guards for that and also covers the floating roster window.
    GuildOS:RefreshRosterUI()
    local rf = GuildOS.RosterFrame
    if not rf or not rf:IsShown() then return end
    local mp = rf.tabPanels and rf.tabPanels.management
    if mp and mp:IsShown() and mp.RefreshActive then
        mp.RefreshActive()
    end
end

----------------------------------------------------------------------
-- Action entry point (kept for the panel / context-menu call sites). A removal
-- is Blizzard-protected: it is queued in Bulk actions, one click of Next.
----------------------------------------------------------------------
function GuildManager:ConfirmKick(name, key)
    return self:Kick(name, key)
end
