----------------------------------------------------------------------
-- BRutus Guild Manager - Raid Attendance Tracker
-- Tracks raid attendance, logs raid sessions, computes attendance %
----------------------------------------------------------------------
local RaidTracker = {}
BRutus.RaidTracker = RaidTracker
local L = BRutus.L

local _mergeDebounceTimer = nil  -- debounce handle for post-broadcast dedup

-- TBC Raid instance IDs
RaidTracker.RAID_INSTANCES = {
    [532]  = "Karazhan",
    [544]  = "Magtheridon",
    [565]  = "Gruul's Lair",
    [548]  = "Serpentshrine Cavern",
    [550]  = "Tempest Keep",
    [534]  = "Hyjal Summit",
    [564]  = "Black Temple",
    [580]  = "Sunwell Plateau",
    [509]  = "AQ20",
    [531]  = "AQ40",
    [533]  = "Naxxramas",
    [309]  = "Zul'Gurub",
    [469]  = "BWL",
    [409]  = "Molten Core",
}

-- Raids that count for attendance (25-man progression)
RaidTracker.RAID_25MAN = {
    [544] = true,  -- Magtheridon's Lair
    [565] = true,  -- Gruul's Lair
    [548] = true,  -- Serpentshrine Cavern
    [550] = true,  -- Tempest Keep
    [534] = true,  -- Hyjal Summit
    [564] = true,  -- Black Temple
    [580] = true,  -- Sunwell Plateau
}

function RaidTracker:Is25Man(instanceID)
    return self.RAID_25MAN[instanceID] == true
end

RaidTracker.currentRaid = nil
RaidTracker.trackingActive = false
RaidTracker.snapshotTimer = nil
RaidTracker.endTimer = nil       -- grace-period timer before ending a session
RaidTracker.currentGroupTag = ""  -- active raid group tag (e.g. "Core 1"); saved in DB

-- Attendance penalty weights
RaidTracker.PENALTIES = {
    LATE       = 10,  -- arrived after first snapshot
    LEFT_EARLY = 10,  -- absent from last snapshot
    NO_CONSUMES = 10, -- no consumables during raid
}
-- Max score per lockout = 100, penalties subtract from it

-- TBC weekly reset epoch: 2006-01-03 00:00 UTC (a known Tuesday)
local TUESDAY_EPOCH = 1136246400
local WEEK_SECS     = 7 * 86400

----------------------------------------------------------------------
-- Returns the TBC reset week number for a given server timestamp.
-- Week boundaries fall on Tuesday 00:00 UTC.
----------------------------------------------------------------------
function RaidTracker:GetWeekNum(timestamp)
    return math.floor(((timestamp or 0) - TUESDAY_EPOCH) / WEEK_SECS)
end

function RaidTracker:Initialize()
    if not BRutus.db.raidTracker then
        BRutus.db.raidTracker = { sessions = {}, attendance = {}, currentGroupTag = "" }
    end

    -- Ensure currentGroupTag field exists (added later)
    local rtDB = BRutus.db.raidTracker
    if rtDB.currentGroupTag == nil then rtDB.currentGroupTag = "" end
    self.currentGroupTag = rtDB.currentGroupTag

    -- Ensure deletedSessions tombstone set exists (added later)
    if rtDB.deletedSessions == nil then rtDB.deletedSessions = {} end

    -- One-time migration: detect old flat attendance structure and rebuild
    self:MigrateAttendanceIfNeeded()

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ZONE_CHANGED_NEW_AREA" then
            RaidTracker:CheckZone()
        elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
            if RaidTracker.trackingActive then
                RaidTracker:TakeSnapshot("roster_change")
            end
        elseif event == "ENCOUNTER_START" then
            local encounterID, encounterName = ...
            RaidTracker:OnEncounterStart(encounterID, encounterName)
        elseif event == "ENCOUNTER_END" then
            local encounterID, encounterName, _, _, success = ...
            RaidTracker:OnEncounterEnd(encounterID, encounterName, success)
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Runs after the world fully loads; safe to access all DB data here.
            -- Merge any leftover duplicate sessions from old sessions.
            C_Timer.After(2, function()
                RaidTracker:MergeDuplicateSessions()
            end)
            -- Only fire once per session
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
    end)
end

function RaidTracker:CheckZone()
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType == "raid" and self.RAID_INSTANCES[instanceID] then
        -- We're inside a raid instance
        if self.endTimer then
            -- There was a pending end-of-session timer
            if self.currentRaid and self.currentRaid.instanceID == instanceID then
                -- Same raid: cancel the pending end and resume
                self.endTimer:Cancel()
                self.endTimer = nil
                BRutus:Print(L["|cffFFAA00Raid resumed — session continuing.|r"])
                self:TakeSnapshot("raid_resumed")
                return
            else
                -- Different raid: end the old session immediately then start new
                self.endTimer:Cancel()
                self.endTimer = nil
                self:EndSession()
            end
        end
        if not self.trackingActive then
            self:StartSession(instanceID)
        end
    else
        -- Outside any tracked raid instance
        if self.trackingActive and not self.endTimer then
            -- Start a 20-minute grace period before actually ending the session.
            -- This covers wipes (zone to graveyard + run back) and short DCs.
            BRutus:Print(L["|cffFFAA00Left raid zone — session ends in 20 min if you don't return.|r"])
            self.endTimer = C_Timer.NewTimer(1200, function()
                self.endTimer = nil
                RaidTracker:EndSession()
            end)
        end
    end
end

function RaidTracker:StartSession(instanceID)
    local raidName = self.RAID_INSTANCES[instanceID] or L["Unknown"]
    self.trackingActive = true
    self.currentRaid = {
        instanceID = instanceID,
        name = raidName,
        groupTag = self:GetCurrentGroup(),  -- tag this session with the active group
        startTime = GetServerTime(),
        endTime = nil,
        snapshots = {},
        encounters = {},
        players = {},
    }
    self:TakeSnapshot("session_start")

    -- Periodic snapshots every 5 minutes
    self.snapshotTimer = C_Timer.NewTicker(300, function()
        if self.trackingActive then
            self:TakeSnapshot("periodic")
        end
    end)

    BRutus:Print(L["Raid tracking started: |cffFFD700"] .. raidName .. "|r")
end

function RaidTracker:IsGuildRaid(session)
    local myGuild = GetGuildInfo("player")
    if not myGuild then return false end

    local players = session.players or {}
    local total = 0
    local guildCount = 0

    for key in pairs(players) do
        total = total + 1
        local name = key:match("^([^-]+)") or key
        local memberData = BRutus.db.members and BRutus.db.members[key]
        -- Check via member DB (fastest path — already synced)
        if memberData then
            guildCount = guildCount + 1
        else
            -- Fallback: scan guild roster for this name
            local numMembers = GetNumGuildMembers() or 0
            for i = 1, numMembers do
                local fullName = GetGuildRosterInfo(i)
                if fullName then
                    local short = fullName:match("^([^-]+)") or fullName
                    if short == name then
                        guildCount = guildCount + 1
                        break
                    end
                end
            end
        end
    end

    if total == 0 then return false end
    -- Require at least 50% guild members
    return (guildCount / total) >= 0.5
end

function RaidTracker:EndSession()
    if not self.currentRaid then return end

    self:TakeSnapshot("session_end")
    local endTime = GetServerTime()
    self.currentRaid.endTime = endTime
    self.currentRaid.duration = endTime - (self.currentRaid.startTime or endTime)
    self.trackingActive = false

    if self.snapshotTimer then
        self.snapshotTimer:Cancel()
        self.snapshotTimer = nil
    end

    -- Discard sessions shorter than 10 minutes (likely disconnects / quick zone-ins)
    local MIN_SESSION_DURATION = 600
    if self.currentRaid.duration < MIN_SESSION_DURATION then
        BRutus:Print(string.format(L["|cffFFAA00Raid session discarded (too short: %ds < %ds).|r"],
            self.currentRaid.duration, MIN_SESSION_DURATION))
        self.currentRaid = nil
        return
    end

    -- Save session
    local sessionID = self.currentRaid.startTime
    BRutus.db.raidTracker.sessions[sessionID] = self.currentRaid

    -- Only count attendance if this was a guild raid (≥50% guild members)
    if self:IsGuildRaid(self.currentRaid) then
        self.currentRaid.isGuildRaid = true
        -- Rebuild from scratch so lockout-dedup logic always applies
        self:RebuildAttendanceFromSessions()
    else
        self.currentRaid.isGuildRaid = false
        BRutus:Print(L["|cffFF9900Raid ended — less than 50% guild members, attendance not counted.|r"])
    end

    BRutus:Print(L["Raid tracking ended: |cffFFD700"] .. self.currentRaid.name .. "|r")
    self.currentRaid = nil

    -- Broadcast updated raid data to all officer clients
    C_Timer.After(1, function()
        RaidTracker:BroadcastRaidData()
    end)
end

function RaidTracker:TakeSnapshot(reason)
    if not self.currentRaid then return end

    local members = {}
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then return end

    local isRaid = IsInRaid()
    for i = 1, numMembers do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) then
            local name, realm = UnitName(unit)
            if name then
                realm = realm and realm ~= "" and realm or GetRealmName()
                local key = name .. "-" .. realm
                members[key] = {
                    name = name,
                    class = select(2, UnitClass(unit)) or "UNKNOWN",
                    online = UnitIsConnected(unit),
                    hasConsumes = self:CheckPlayerConsumes(unit),
                }
                self.currentRaid.players[key] = true
            end
        end
    end

    -- Include self
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myKey = myName .. "-" .. myRealm
    members[myKey] = {
        name = myName,
        class = select(2, UnitClass("player")),
        online = true,
        hasConsumes = self:CheckPlayerConsumes("player"),
    }
    self.currentRaid.players[myKey] = true

    table.insert(self.currentRaid.snapshots, {
        time = GetServerTime(),
        reason = reason,
        members = members,
        count = self:CountTable(members),
    })
end

----------------------------------------------------------------------
-- Check if a unit has at least flask/elixir + food active
----------------------------------------------------------------------
function RaidTracker:CheckPlayerConsumes(unit)
    if not BRutus.ConsumableChecker then return true end

    local CC = BRutus.ConsumableChecker
    local hasFlaskOrElixir = false
    local hasFood = false

    -- Check flask
    for buffID in pairs(CC.CONSUMABLES.flask.buffs) do
        if CC:UnitHasBuff(unit, buffID) then
            hasFlaskOrElixir = true
            break
        end
    end

    -- If no flask, check battle elixir as alternative
    if not hasFlaskOrElixir then
        for buffID in pairs(CC.CONSUMABLES.battleElixir.buffs) do
            if CC:UnitHasBuff(unit, buffID) then
                hasFlaskOrElixir = true
                break
            end
        end
    end

    -- Check food
    for buffID in pairs(CC.CONSUMABLES.food.buffs) do
        if CC:UnitHasBuff(unit, buffID) then
            hasFood = true
            break
        end
    end

    return hasFlaskOrElixir and hasFood
end

function RaidTracker:OnEncounterStart(encounterID, encounterName)
    if not self.currentRaid then return end
    self:TakeSnapshot("encounter_start")
    -- Guard: ignore duplicate ENCOUNTER_START for the same fight (can fire twice
    -- on some TBC bosses such as Magtheridon due to phase transitions).
    for _, enc in ipairs(self.currentRaid.encounters) do
        if enc.id == encounterID and enc.endTime == nil then
            return  -- already tracking this encounter
        end
    end
    table.insert(self.currentRaid.encounters, {
        id        = encounterID,
        name      = encounterName,
        startTime = GetServerTime(),
        endTime   = nil,
        success   = nil,
    })
end

function RaidTracker:OnEncounterEnd(encounterID, encounterName, success)
    if not self.currentRaid then return end
    self:TakeSnapshot("encounter_end")

    -- Update the last encounter with this ID
    for i = #self.currentRaid.encounters, 1, -1 do
        local enc = self.currentRaid.encounters[i]
        if enc.id == encounterID and not enc.endTime then
            enc.endTime = GetServerTime()
            enc.success = (success == 1)
            break
        end
    end

    local status = (success == 1) and L["|cff00ff00KILL|r"] or L["|cffff3333WIPE|r"]
    BRutus:Print(encounterName .. " - " .. status)
end

----------------------------------------------------------------------
-- Raid Group management
-- groupTag is a persistent per-officer label ("Core 1", "Core 2", …).
-- It tags sessions so attendance is tracked independently per group.
----------------------------------------------------------------------
function RaidTracker:GetCurrentGroup()
    return self.currentGroupTag or ""
end

function RaidTracker:SetGroupTag(name)
    name = name or ""
    self.currentGroupTag = name
    if BRutus.db and BRutus.db.raidTracker then
        BRutus.db.raidTracker.currentGroupTag = name
    end
end

-- Returns the group tag where the player has the most raids recorded.
-- Used to auto-select the correct denominator when no group is specified.
function RaidTracker:GetPlayerGroup(playerKey)
    local att = BRutus.db.raidTracker and BRutus.db.raidTracker.attendance or {}
    local bestGroup = ""
    local bestRaids = 0
    for groupTag, groupAtt in pairs(att) do
        if type(groupAtt) == "table" then
            local data = groupAtt[playerKey]
            if data and (data.raids or 0) > bestRaids then
                bestRaids = data.raids or 0
                bestGroup = groupTag
            end
        end
    end
    return bestGroup
end

----------------------------------------------------------------------
-- Attendance accessors (all group-aware)
-- groupTag = nil → auto-detect from the player's primary group
----------------------------------------------------------------------
function RaidTracker:GetAttendance(playerKey, groupTag)
    local att = BRutus.db.raidTracker and BRutus.db.raidTracker.attendance or {}
    if not groupTag then groupTag = self:GetPlayerGroup(playerKey) end
    local groupAtt = att[groupTag]
    if groupAtt and groupAtt[playerKey] then
        return groupAtt[playerKey]
    end
    return { raids = 0, lastRaid = 0 }
end

-- Count unique guild-raid lockouts for a group (or all groups if nil).
function RaidTracker:GetTotalSessions(groupTag)
    local seen = {}
    for _, session in pairs(BRutus.db.raidTracker.sessions) do
        -- isGuildRaid ~= false: include old sessions without the flag (legacy data)
        if session.isGuildRaid ~= false then
            local sg = session.groupTag or ""
            if not groupTag or sg == groupTag then
                local key = sg .. "|" .. (session.instanceID or 0) .. "_" .. self:GetWeekNum(session.startTime or 0)
                seen[key] = true
            end
        end
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    return count
end

-- Count unique 25-man guild-raid lockouts for a group (or all groups if nil).
function RaidTracker:GetTotal25ManSessions(groupTag)
    local seen = {}
    for _, session in pairs(BRutus.db.raidTracker.sessions) do
        -- isGuildRaid ~= false: include old sessions without the flag (legacy data)
        if session.isGuildRaid ~= false and self:Is25Man(session.instanceID) then
            local sg = session.groupTag or ""
            if not groupTag or sg == groupTag then
                local key = sg .. "|" .. session.instanceID .. "_" .. self:GetWeekNum(session.startTime or 0)
                seen[key] = true
            end
        end
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    return count
end

function RaidTracker:GetAttendancePercent(playerKey, groupTag)
    if not groupTag then groupTag = self:GetPlayerGroup(playerKey) end
    local total = self:GetTotalSessions(groupTag)
    if total == 0 then return 0 end
    local att = self:GetAttendance(playerKey, groupTag)
    if att.raids == 0 then return 0 end
    if att.totalScore then
        return math.floor(att.totalScore / (total * 100) * 100 + 0.5)
    end
    return math.floor((att.raids / total) * 100 + 0.5)
end

function RaidTracker:GetAttendance25ManPercent(playerKey, groupTag)
    if not groupTag then groupTag = self:GetPlayerGroup(playerKey) end
    local total = self:GetTotal25ManSessions(groupTag)
    if total == 0 then return 0 end
    local att = self:GetAttendance(playerKey, groupTag)
    local raids25 = att.raids25 or 0
    if raids25 == 0 then return 0 end
    if att.totalScore25 then
        return math.floor(att.totalScore25 / (total * 100) * 100 + 0.5)
    end
    return math.floor((raids25 / total) * 100 + 0.5)
end

-- Consecutive most-recent 25-man guild raids the player missed (capped).
-- A simple "recent form" signal: counts recent guild 25-man sessions newer
-- than the player's last attended raid, stopping at the first they attended.
function RaidTracker:GetMissedStreak(playerKey, groupTag, cap)
    cap = cap or 5
    local att = self:GetAttendance(playerKey, groupTag)
    local lastRaid = att.lastRaid or 0
    local sessions = self:GetRecentSessions(cap, true, true)
    local missed = 0
    for _, s in ipairs(sessions) do
        local t = s.id or (s.data and s.data.startTime) or 0
        if t > lastRaid then
            missed = missed + 1
        else
            break
        end
    end
    return missed
end

function RaidTracker:GetRecentSessions(limit, only25, guildOnly)
    limit = limit or 20
    local sessions = {}
    for id, session in pairs(BRutus.db.raidTracker.sessions) do
        -- guildOnly: exclude sessions explicitly marked as non-guild raids.
        -- Sessions without the flag (legacy data) are treated as guild raids.
        local skipNonGuild = guildOnly and session.isGuildRaid == false
        if not skipNonGuild and (not only25 or self:Is25Man(session.instanceID)) then
            table.insert(sessions, { id = id, data = session })
        end
    end
    table.sort(sessions, function(a, b) return a.id > b.id end)
    local result = {}
    for i = 1, math.min(limit, #sessions) do
        result[i] = sessions[i]
    end
    return result
end

----------------------------------------------------------------------
-- Merge duplicate sessions: same instanceID within a 2-hour window
-- (repairs old DB data from before the grace-period fix was added)
--
-- IMPORTANT: we group by instanceID FIRST, then do adjacent-pair merge
-- within each group. The naive all-sessions-sorted approach fails when
-- sessions from different instances interleave chronologically (e.g.
-- Karazhan run between two Magtheridon wipe sessions).
----------------------------------------------------------------------
function RaidTracker:MergeDuplicateSessions()
    local sessions = BRutus.db.raidTracker.sessions
    if not sessions then return 0 end

    local MERGE_WINDOW = 1800  -- 30 min: covers wipe→run-back; separates distinct raid attempts
    local ENC_PROX    = 300   -- 5 min proximity = same encounter event
    local totalMerged = 0

    -- Helper: dedup an encounter list in-place (collect+sort+adjacent-dedup).
    -- Fixes any duplicates already present in a single session's data.
    local function deduplicateEncounters(encounters)
        if not encounters or #encounters <= 1 then return encounters end
        table.sort(encounters, function(x, y) return (x.startTime or 0) < (y.startTime or 0) end)
        local result = {}
        for _, enc in ipairs(encounters) do
            local isDup = false
            local encT  = enc.startTime or 0
            for i = #result, 1, -1 do
                local prev = result[i]
                if encT - (prev.startTime or 0) > ENC_PROX then break end
                if prev.id == enc.id and prev.success == enc.success then
                    isDup = true; break
                end
            end
            if not isDup then tinsert(result, enc) end
        end
        return result
    end

    -- First pass: clean up duplicate encounters within each existing session
    -- (repairs data corrupted by previous ENCOUNTER_START double-fires or bad merges).
    for _, s in pairs(sessions) do
        if s and s.encounters and #s.encounters > 1 then
            s.encounters = deduplicateEncounters(s.encounters)
        end
    end

    -- Group sessions by instanceID AND groupTag (don't merge sessions from different groups)
    local byInstance = {}
    for id, s in pairs(sessions) do
        if s and s.instanceID then
            local bucketKey = (s.groupTag or "") .. "|" .. s.instanceID
            if not byInstance[bucketKey] then
                byInstance[bucketKey] = {}
            end
            table.insert(byInstance[bucketKey], { id = id, data = s })
        end
    end

    -- For each instance, sort chronologically and merge overlapping/close sessions
    for _, list in pairs(byInstance) do
        table.sort(list, function(a, b) return a.id < b.id end)

        local changed = true
        while changed do
            changed = false
            -- Rebuild list from current sessions (removes deleted entries)
            local fresh = {}
            for _, entry in ipairs(list) do
                if sessions[entry.id] then
                    table.insert(fresh, entry)
                end
            end
            list = fresh

            for i = 1, #list - 1 do
                local a = list[i]
                local b = list[i + 1]
                if a.data and b.data then
                    local aEnd   = a.data.endTime or (a.id + (a.data.duration or 0))
                    local bStart = b.data.startTime or b.id

                    if bStart - aEnd <= MERGE_WINDOW then
                        -- Extend time range to cover both sessions
                        local newEnd = math.max(
                            a.data.endTime or a.id,
                            b.data.endTime or b.id
                        )
                        a.data.endTime  = newEnd
                        a.data.duration = newEnd - (a.data.startTime or a.id)

                        -- Merge player sets
                        for k in pairs(b.data.players or {}) do
                            a.data.players[k] = true
                        end

                        -- Normalise nil fields on old DB records
                        if not a.data.snapshots then a.data.snapshots = {} end
                        if not b.data.snapshots then b.data.snapshots = {} end

                        -- Merge encounters.
                        -- Collect all encounters from both sessions, sort by startTime,
                        -- then single-pass dedup: skip if a previous kept encounter has
                        -- the same (encounterID, success) within ENC_PROX seconds.
                        -- This avoids the mutation-while-iterating bug of the old approach
                        -- and correctly handles nil startTimes and multi-wipe scenarios.
                        if not a.data.encounters then a.data.encounters = {} end
                        if not b.data.encounters then b.data.encounters = {} end

                        local allEncs = {}
                        for _, e in ipairs(a.data.encounters) do tinsert(allEncs, e) end
                        for _, e in ipairs(b.data.encounters) do tinsert(allEncs, e) end
                        table.sort(allEncs, function(x, y)
                            return (x.startTime or 0) < (y.startTime or 0)
                        end)

                        local dedupedEncs = {}
                        for _, enc in ipairs(allEncs) do
                            local isDup = false
                            local encT  = enc.startTime or 0
                            for j = #dedupedEncs, 1, -1 do
                                local prev = dedupedEncs[j]
                                if encT - (prev.startTime or 0) > ENC_PROX then break end
                                if prev.id == enc.id and prev.success == enc.success then
                                    isDup = true; break
                                end
                            end
                            if not isDup then tinsert(dedupedEncs, enc) end
                        end
                        a.data.encounters = dedupedEncs

                        -- Merge snapshots
                        for _, snap in ipairs(b.data.snapshots) do
                            table.insert(a.data.snapshots, snap)
                        end
                        table.sort(a.data.snapshots, function(x, y)
                            return (x.time or 0) < (y.time or 0)
                        end)

                        -- Preserve isGuildRaid: if either session was a guild raid, mark merged as such
                        if b.data.isGuildRaid then
                            a.data.isGuildRaid = true
                        end

                        sessions[b.id] = nil
                        totalMerged = totalMerged + 1
                        changed = true
                        break
                    end
                end
            end
        end
    end

    if totalMerged > 0 then
        BRutus:Print(string.format(L["|cff00FF00BRutus: merged %d duplicate raid session(s).|r"], totalMerged))
    end
    -- Always rebuild so attendance stays consistent with the session DB
    self:RebuildAttendanceFromSessions()
    return totalMerged
end

----------------------------------------------------------------------
-- Rebuild attendance table from scratch using saved sessions.
-- Sessions are grouped by lockout (groupTag + instanceID + reset week)
-- so that multiple sessions in the same raid week count as ONE event,
-- and Core 1 / Core 2 lockouts are tracked independently.
----------------------------------------------------------------------
function RaidTracker:RebuildAttendanceFromSessions()
    BRutus.db.raidTracker.attendance = {}

    local lockouts = {}
    local lockoutOrder = {}
    for _, session in pairs(BRutus.db.raidTracker.sessions) do
        -- isGuildRaid ~= false: include old sessions without the flag (legacy data)
        if session.isGuildRaid ~= false then
            local weekNum    = self:GetWeekNum(session.startTime or 0)
            local groupTag   = session.groupTag or ""
            -- Each group+instance+week is its own lockout; groups never share a lockout
            local lockoutKey = groupTag .. "|" .. (session.instanceID or 0) .. "_" .. weekNum
            if not lockouts[lockoutKey] then
                lockouts[lockoutKey] = {
                    instanceID = session.instanceID,
                    groupTag   = groupTag,
                    sessions   = {},
                }
                table.insert(lockoutOrder, lockoutKey)
            end
            table.insert(lockouts[lockoutKey].sessions, session)
        end
    end

    for _, key in ipairs(lockoutOrder) do
        self:UpdateAttendanceForLockout(lockouts[key])
    end
end

----------------------------------------------------------------------
-- Compute attendance for ONE lockout.
-- Results are stored under attendance[groupTag][playerKey].
----------------------------------------------------------------------
function RaidTracker:UpdateAttendanceForLockout(lockout)
    local att        = BRutus.db.raidTracker.attendance
    local instanceID = lockout.instanceID
    local groupTag   = lockout.groupTag or ""

    -- Ensure the group sub-table exists
    if not att[groupTag] then att[groupTag] = {} end
    local groupAtt = att[groupTag]

    local allPlayers   = {}
    local allSnapshots = {}
    local lastRaid     = 0

    for _, session in ipairs(lockout.sessions) do
        for playerKey in pairs(session.players or {}) do
            allPlayers[playerKey] = true
        end
        for _, snap in ipairs(session.snapshots or {}) do
            table.insert(allSnapshots, snap)
        end
        if (session.startTime or 0) > lastRaid then
            lastRaid = session.startTime or 0
        end
    end

    table.sort(allSnapshots, function(a, b) return (a.time or 0) < (b.time or 0) end)

    local firstSnap = allSnapshots[1]
    local lastSnap  = allSnapshots[#allSnapshots]

    for playerKey in pairs(allPlayers) do
        if not groupAtt[playerKey] then
            groupAtt[playerKey] = { raids = 0, lastRaid = 0, totalScore = 0 }
        end
        if not groupAtt[playerKey].totalScore then
            groupAtt[playerKey].totalScore = groupAtt[playerKey].raids * 100
        end

        groupAtt[playerKey].raids   = groupAtt[playerKey].raids + 1
        groupAtt[playerKey].lastRaid = math.max(groupAtt[playerKey].lastRaid, lastRaid)

        local score = 100
        if firstSnap and firstSnap.members and not firstSnap.members[playerKey] then
            score = score - self.PENALTIES.LATE
        end
        if lastSnap and lastSnap.members and not lastSnap.members[playerKey] then
            score = score - self.PENALTIES.LEFT_EARLY
        end
        local consumeChecks, consumeHits = 0, 0
        for _, snap in ipairs(allSnapshots) do
            if snap.members and snap.members[playerKey] then
                consumeChecks = consumeChecks + 1
                if snap.members[playerKey].hasConsumes then
                    consumeHits = consumeHits + 1
                end
            end
        end
        if consumeChecks > 0 and (consumeHits / consumeChecks) < 0.5 then
            score = score - self.PENALTIES.NO_CONSUMES
        end
        score = math.max(0, math.min(100, score))
        groupAtt[playerKey].totalScore = groupAtt[playerKey].totalScore + score

        if self:Is25Man(instanceID) then
            groupAtt[playerKey].raids25      = (groupAtt[playerKey].raids25 or 0) + 1
            groupAtt[playerKey].totalScore25 = (groupAtt[playerKey].totalScore25 or 0) + score
        end
    end
end

function RaidTracker:DeleteSession(sessionID)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Only officers can delete raids.|r"])
        return
    end

    local session = BRutus.db.raidTracker.sessions[sessionID]
    if not session then return end

    BRutus.db.raidTracker.sessions[sessionID] = nil
    -- Tombstone so peers can't re-insert this session via broadcast
    if BRutus.db.raidTracker.deletedSessions == nil then
        BRutus.db.raidTracker.deletedSessions = {}
    end
    BRutus.db.raidTracker.deletedSessions[sessionID] = true
    -- Rebuild from scratch so attendance stays consistent
    self:RebuildAttendanceFromSessions()

    -- Broadcast the deletion to all other officer clients
    self:BroadcastDeleteSession(sessionID)
end

----------------------------------------------------------------------
-- Broadcast a session deletion to guild (officers apply it on receive)
----------------------------------------------------------------------
function RaidTracker:BroadcastDeleteSession(sessionID)
    if not BRutus:IsOfficer() then return end
    if not BRutus.CommSystem then return end
    if not IsInGuild() then return end

    local LibSerialize = LibStub("LibSerialize")
    local serialized = LibSerialize:Serialize({ sessionID = sessionID })
    BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.RAID_DELETE, serialized)
end

----------------------------------------------------------------------
-- Handle an incoming session deletion broadcast from another officer.
-- Sender is already verified as officer before this is called.
----------------------------------------------------------------------
function RaidTracker:HandleDeleteIncoming(data)
    local LibSerialize = LibStub("LibSerialize")
    local ok, payload = LibSerialize:Deserialize(data)
    if not ok or type(payload) ~= "table" then return end

    local sessionID = payload.sessionID
    if not sessionID then return end

    local raidDB = BRutus.db.raidTracker
    if not raidDB or not raidDB.sessions then return end
    if not raidDB.sessions[sessionID] then return end  -- already gone

    raidDB.sessions[sessionID] = nil
    -- Tombstone so re-broadcasts from outdated peers won't re-insert this session
    if raidDB.deletedSessions == nil then raidDB.deletedSessions = {} end
    raidDB.deletedSessions[sessionID] = true
    self:RebuildAttendanceFromSessions()

    -- Refresh UI if the raids panel is open
    if BRutus.RaidsPanelOpen then
        BRutus:RefreshRaidsPanel(
            BRutus.RaidsPanelOpen.sessionContent,
            BRutus.RaidsPanelOpen.attContent,
            BRutus.RaidsPanelOpen.statusText
        )
    end
end

function RaidTracker:CountTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

----------------------------------------------------------------------
-- Sync raid data with other officer clients
----------------------------------------------------------------------
function RaidTracker:BroadcastRaidData()
    if not BRutus:IsOfficer() then return end
    if not BRutus.CommSystem then return end
    if not IsInGuild() then return end

    local raidDB = BRutus.db.raidTracker
    if not raidDB then return end

    -- Build a compact payload: full attendance + session metadata (no snapshots)
    local payload = {
        attendance = raidDB.attendance or {},
        sessions   = {},
    }
    for sessionID, session in pairs(raidDB.sessions or {}) do
        payload.sessions[sessionID] = {
            instanceID = session.instanceID,
            name       = session.name,
            groupTag   = session.groupTag or "",
            startTime  = session.startTime,
            endTime    = session.endTime,
            players    = session.players,
            encounters = session.encounters,
        }
    end

    -- Include tombstone set so peers learn about deletions even if they
    -- missed the point-in-time RAID_DELETE message.
    payload.deletedSessions = raidDB.deletedSessions or {}

    local LibSerialize = LibStub("LibSerialize")
    local serialized = LibSerialize:Serialize(payload)
    BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.RAID_DATA, serialized)
end

function RaidTracker:HandleIncoming(data)
    if not BRutus:IsOfficer() then return end

    local LibSerialize = LibStub("LibSerialize")
    local ok, payload = LibSerialize:Deserialize(data)
    if not ok or type(payload) ~= "table" then return end

    local raidDB = BRutus.db.raidTracker
    if not raidDB.attendance then raidDB.attendance = {} end
    if not raidDB.sessions   then raidDB.sessions   = {} end

    -- Merge attendance.
    -- New format: attendance[groupTag][playerKey] = { raids, ... }
    -- Old format (peers not yet updated): attendance[playerKey] = { raids, ... }
    -- Detect by checking whether the first value is a player record (has .raids/.lastRaid).
    local function mergePlayerRecord(localGroup, playerKey, incoming)
        if type(incoming) ~= "table" then return end
        local existing = localGroup[playerKey]
        if not existing then
            localGroup[playerKey] = incoming
        else
            local inRaids = incoming.raids or 0
            local exRaids = existing.raids or 0
            if inRaids > exRaids then
                localGroup[playerKey] = incoming
            elseif inRaids == exRaids then
                if (incoming.lastRaid or 0) > (existing.lastRaid or 0) then
                    localGroup[playerKey] = incoming
                end
            end
        end
    end

    for outerKey, outerVal in pairs(payload.attendance or {}) do
        if type(outerVal) == "table" then
            if outerVal.raids ~= nil or outerVal.lastRaid ~= nil then
                -- Old flat format: outerKey is playerKey, outerVal is attendance data
                if not raidDB.attendance[""] then raidDB.attendance[""] = {} end
                mergePlayerRecord(raidDB.attendance[""], outerKey, outerVal)
            else
                -- New nested format: outerKey is groupTag, outerVal is { playerKey → data }
                if not raidDB.attendance[outerKey] then
                    raidDB.attendance[outerKey] = {}
                end
                local localGroup = raidDB.attendance[outerKey]
                for playerKey, incoming in pairs(outerVal) do
                    mergePlayerRecord(localGroup, playerKey, incoming)
                end
            end
        end
    end

    -- Apply tombstones sent by the peer (sessions they deleted)
    local deleted = raidDB.deletedSessions
    if deleted == nil then deleted = {}; raidDB.deletedSessions = deleted end
    for sessionID, _ in pairs(payload.deletedSessions or {}) do
        deleted[sessionID] = true
        raidDB.sessions[sessionID] = nil  -- purge if we still had it
    end

    -- Merge sessions: add any session we don't already have,
    -- but never re-insert sessions that have been tombstoned.
    for sessionID, session in pairs(payload.sessions or {}) do
        if not deleted[sessionID] and not raidDB.sessions[sessionID] then
            raidDB.sessions[sessionID] = session
        end
    end

    -- Deduplicate: multiple officers may have broadcast the same raid with
    -- slightly different startTimes. Run a debounced merge so all incoming
    -- broadcasts are collected before the merge pass fires.
    if _mergeDebounceTimer then
        _mergeDebounceTimer:Cancel()
    end
    _mergeDebounceTimer = C_Timer.NewTimer(3, function()
        _mergeDebounceTimer = nil
        RaidTracker:MergeDuplicateSessions()
        -- Refresh UI if the raids panel is open
        if BRutus.RaidsPanelOpen then
            BRutus:RefreshRaidsPanel(
                BRutus.RaidsPanelOpen.sessionContent,
                BRutus.RaidsPanelOpen.attContent,
                BRutus.RaidsPanelOpen.statusText
            )
        end
    end)
end

----------------------------------------------------------------------
-- Export attendance data as TMB-compatible JSON.
-- groupTag = nil → use the current active group tag.
----------------------------------------------------------------------
function RaidTracker:ExportForTMB(groupTag)
    groupTag = groupTag or self:GetCurrentGroup()
    local total = self:GetTotal25ManSessions(groupTag)
    if total == 0 then
        local label = groupTag ~= "" and groupTag or L["default"]
        return nil, L["No 25-man raids recorded for group: "] .. label
    end

    local att = BRutus.db.raidTracker.attendance or {}
    local groupAtt = att[groupTag] or {}
    local lines = {}
    table.insert(lines, "{")

    local entries = {}
    for playerKey, data in pairs(groupAtt) do
        local name = playerKey:match("^([^-]+)")
        local raids25 = data.raids25 or 0
        if name and raids25 > 0 then
            local pct = self:GetAttendance25ManPercent(playerKey, groupTag)
            table.insert(entries, {
                name = name,
                pct = pct,
                raids = raids25,
            })
        end
    end
    table.sort(entries, function(a, b) return a.name < b.name end)

    for i, e in ipairs(entries) do
        local comma = (i < #entries) and "," or ""
        table.insert(lines, string.format('  "%s": {"attendance_percentage": %d, "raids_attended": %d, "raids_total": %d}%s',
            e.name, e.pct, e.raids, total, comma))
    end

    table.insert(lines, "}")
    return table.concat(lines, "\n"), nil
end

----------------------------------------------------------------------
-- One-time migration: detect old flat attendance format and rebuild.
-- Old format: attendance[playerKey] = { raids, lastRaid, ... }
-- New format: attendance[groupTag][playerKey] = { raids, lastRaid, ... }
----------------------------------------------------------------------
function RaidTracker:MigrateAttendanceIfNeeded()
    local att = BRutus.db.raidTracker and BRutus.db.raidTracker.attendance or {}
    -- Inspect the first entry only to detect the old flat format
    local _, v = next(att)
    if type(v) == "table" and (v.raids ~= nil or v.lastRaid ~= nil or v.raids25 ~= nil) then
        BRutus:Print(L["|cffFFAA00BRutus: Old attendance format detected. Rebuilding per group…|r"])
        self:RebuildAttendanceFromSessions()
    end
end
