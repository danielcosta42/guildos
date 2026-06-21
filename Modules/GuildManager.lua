----------------------------------------------------------------------
-- Guild OS - Guild Manager (Leadership Suite)
-- Officer-gated guild leadership tools: rank changes, kicks, MOTD / Guild
-- Info editing, inactivity reports, promotion suggestions, and a local
-- action log. Business logic only — no UI frames (Rule 2 / Rule 10).
----------------------------------------------------------------------
local GuildManager = {}
BRutus.GuildManager = GuildManager
local L = BRutus.L

-- Cap on the locally-stored action log (ring buffer; oldest entries dropped).
local LOG_MAX = 200
-- Default inactivity threshold (days) for the purge report.
local DEFAULT_INACTIVE_DAYS = 30
GuildManager.DEFAULT_INACTIVE_DAYS = DEFAULT_INACTIVE_DAYS
-- Attendance % at/above which a non-officer member is flagged a promotion
-- candidate in the suggestions view.
local PROMO_ATTENDANCE_MIN = 80

function GuildManager:Initialize()
    if not BRutus.db.managementLog then
        -- Ring buffer of { action, target, detail, author, timestamp }.
        BRutus.db.managementLog = {}
    end
end

----------------------------------------------------------------------
-- Permission helpers
-- The Can* guild globals may be absent on some clients, so each is
-- nil-guarded; a missing API resolves to "permission denied".
----------------------------------------------------------------------
function GuildManager:CanPromote()
    return (CanGuildPromote and CanGuildPromote()) and true or false
end

function GuildManager:CanDemote()
    return (CanGuildDemote and CanGuildDemote()) and true or false
end

function GuildManager:CanKick()
    return (CanGuildRemove and CanGuildRemove()) and true or false
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
-- Guild roster index for a short or full player name (realm-stripped match).
function GuildManager:GetRosterIndex(name)
    if not name or name == "" then return nil end
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

-- Best-effort: open the default Blizzard guild window via the pre-hook toggle
-- captured in Core:HookGuildFrame. Never calls a protected function.
function GuildManager:OpenNativeGuild()
    if BRutus._origToggleGuildFrame then
        BRutus._origToggleGuildFrame()
        return true
    end
    return false
end

-- Explain that a rank/membership change is Blizzard-protected and hand the
-- leader off to the native guild panel. Returns false (action not performed).
function GuildManager:_protectedNotice(actionLabel, name)
    local short = name and (name:match("^([^-]+)") or name) or "?"
    BRutus:Print(format(
        L["\"%s\" is Blizzard-protected \226\128\148 use the official guild panel. Target: |cffFFD700%s|r."],
        actionLabel, short))
    self:OpenNativeGuild()
    return false
end

-- All four route to the protected-action handoff (see header note above).
function GuildManager:Promote(name)
    return self:_protectedNotice(L["Promote"], name)
end

function GuildManager:Demote(name)
    return self:_protectedNotice(L["Demote"], name)
end

function GuildManager:SetRank(name)
    return self:_protectedNotice(L["Set Rank"], name)
end

function GuildManager:Kick(name)
    return self:_protectedNotice(L["Remove from guild"], name)
end

-- Set the guild Message of the Day.
function GuildManager:SetMOTD(text)
    if not self:CanSetMOTD() then
        BRutus:Print(L["|cffFF4444No permission to edit the MOTD.|r"])
        return false
    end
    if GuildSetMOTD then GuildSetMOTD(text or "") end
    self:LogAction("motd", nil, text)
    return true
end

-- Set the guild Information text.
function GuildManager:SetGuildInfo(text)
    if not self:CanSetGuildInfo() then
        BRutus:Print(L["|cffFF4444No permission to edit the guild info.|r"])
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

-- Roster members offline for at least `days`, sorted most-inactive first.
function GuildManager:GetInactiveMembers(days)
    days = days or DEFAULT_INACTIVE_DAYS
    local result = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, rankIndex, level, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and not isOnline then
            local off = self:GetDaysOffline(i)
            if off and off >= days then
                local short = name:match("^([^-]+)") or name
                table.insert(result, {
                    index       = i,
                    name        = short,
                    fullName    = name,
                    rankName    = rankName,
                    rankIndex   = rankIndex,
                    level       = level or 0,
                    class       = classFile or "",
                    daysOffline = math.floor(off),
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
-- Returns { trialsReady = { ... }, promoteCandidates = { ... } }.
function GuildManager:GetSuggestions()
    local trialsReady, promoteCandidates = {}, {}

    -- Trials whose duration has elapsed → officer should approve / deny.
    if BRutus.TrialTracker then
        for _, t in ipairs(BRutus.TrialTracker:GetActiveTrials()) do
            local daysRem = BRutus.TrialTracker:GetDaysRemaining(t.key)
            if daysRem ~= nil and daysRem <= 0 then
                local progress = BRutus.TrialTracker:GetProgress(t.key)
                local att = BRutus.RaidTracker and BRutus.RaidTracker:GetAttendance25ManPercent(t.key) or 0
                local short = t.key:match("^([^-]+)") or t.key
                table.insert(trialsReady, {
                    key        = t.key,
                    name       = short,
                    daysSince  = BRutus.TrialTracker:GetDaysSinceStart(t.key) or 0,
                    attendance = att,
                    ilvlDelta  = progress and progress.ilvlDelta or 0,
                })
            end
        end
        table.sort(trialsReady, function(a, b) return a.attendance > b.attendance end)
    end

    -- Non-officer, non-trial members with strong attendance → promote candidates.
    if BRutus.RaidTracker then
        local officerMaxRank = BRutus:GetSetting("officerMaxRank") or 1
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name, rankName, rankIndex, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
            if name then
                local short = name:match("^([^-]+)") or name
                local realm = name:match("-(.+)$") or GetRealmName()
                local key = BRutus:GetPlayerKey(short, realm)
                local isTrial = BRutus.TrialTracker and BRutus.TrialTracker:IsTrial(key)
                local isOfficer = rankIndex and rankIndex <= officerMaxRank
                if not isTrial and not isOfficer then
                    local att = BRutus.RaidTracker:GetAttendance25ManPercent(key)
                    if att and att >= PROMO_ATTENDANCE_MIN then
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

    return { trialsReady = trialsReady, promoteCandidates = promoteCandidates }
end

----------------------------------------------------------------------
-- Action log
----------------------------------------------------------------------
-- Append an entry to the local action log (capped ring buffer).
function GuildManager:LogAction(action, target, detail)
    local log = BRutus.db.managementLog
    if not log then
        log = {}
        BRutus.db.managementLog = log
    end
    local short = target and (target:match("^([^-]+)") or target) or nil
    table.insert(log, {
        action    = action,
        target    = short,
        detail    = detail,
        author    = UnitName("player"),
        timestamp = GetServerTime(),
    })
    -- Trim the oldest entries beyond the cap.
    while #log > LOG_MAX do
        table.remove(log, 1)
    end
end

-- Return the action log newest-first (does not mutate stored order).
function GuildManager:GetLog()
    local log = BRutus.db.managementLog or {}
    local out = {}
    for i = #log, 1, -1 do
        out[#out + 1] = log[i]
    end
    return out
end

function GuildManager:ClearLog()
    BRutus.db.managementLog = {}
end

----------------------------------------------------------------------
-- UI refresh helper
-- Logic modules already drive roster refreshes elsewhere (e.g. TrialTracker),
-- so mirroring that here keeps the management views live after an action.
----------------------------------------------------------------------
function GuildManager:RefreshUI()
    local rf = BRutus.RosterFrame
    if not rf or not rf:IsShown() then return end
    rf:RefreshRoster()
    local mp = rf.tabPanels and rf.tabPanels.management
    if mp and mp:IsShown() and mp.RefreshActive then
        mp.RefreshActive()
    end
end

----------------------------------------------------------------------
-- Action entry points (kept for the panel / context-menu call sites).
-- These are rank/membership changes, which are Blizzard-protected, so they
-- route to the native-panel handoff rather than executing directly.
----------------------------------------------------------------------
function GuildManager:ConfirmSetRank(name)
    self:_protectedNotice(L["Set Rank"], name)
end

function GuildManager:ConfirmKick(name)
    self:_protectedNotice(L["Remove from guild"], name)
end
