----------------------------------------------------------------------
-- BRutus Guild Manager - Trial Member Tracker
-- Tracks trial/recruit members: start date, evaluation notes, status
-- Progress snapshots for iLvl and attunement tracking
----------------------------------------------------------------------
local TrialTracker = {}
BRutus.TrialTracker = TrialTracker
local L = BRutus.L

-- Trial status values
TrialTracker.STATUS = {
    TRIAL    = "trial",
    APPROVED = "approved",
    DENIED   = "denied",
    EXPIRED  = "expired",
}

-- Default trial duration (30 days in seconds)
TrialTracker.DEFAULT_DURATION = 30 * 24 * 60 * 60

function TrialTracker:Initialize()
    if not BRutus.db.trials then
        BRutus.db.trials = {}  -- [playerKey] = { startDate, endDate, status, notes, sponsor, snapshots }
    end
    -- Migrate old trials missing snapshots
    for _, trial in pairs(BRutus.db.trials) do
        if not trial.snapshots then trial.snapshots = {} end
    end
end

function TrialTracker:AddTrial(playerKey, sponsor)
    if not BRutus:IsOfficer() then return false end

    local now = GetServerTime()
    BRutus.db.trials[playerKey] = {
        startDate = now,
        endDate = now + self.DEFAULT_DURATION,
        status = self.STATUS.TRIAL,
        notes = {},
        sponsor = sponsor or UnitName("player"),
        snapshots = {},
    }

    -- Take initial snapshot
    self:TakeSnapshot(playerKey)

    BRutus:Print(playerKey .. L[" marked as trial by "] .. (sponsor or UnitName("player")))
    self:BroadcastTrials()
    return true
end

function TrialTracker:UpdateStatus(playerKey, newStatus)
    if not BRutus:IsOfficer() then return end
    local trial = BRutus.db.trials[playerKey]
    if not trial then return end

    trial.status = newStatus
    if newStatus == self.STATUS.APPROVED or newStatus == self.STATUS.DENIED then
        trial.resolvedDate = GetServerTime()
        trial.resolvedBy = UnitName("player")
    end
    self:BroadcastTrials()
end

function TrialTracker:AddTrialNote(playerKey, text)
    if not BRutus:IsOfficer() then return end
    local trial = BRutus.db.trials[playerKey]
    if not trial then return end

    table.insert(trial.notes, {
        text = text,
        author = UnitName("player"),
        timestamp = GetServerTime(),
    })
    self:BroadcastTrials()
end

function TrialTracker:GetTrial(playerKey)
    return BRutus.db.trials[playerKey]
end

function TrialTracker:GetAllTrials()
    local result = {}
    for key, trial in pairs(BRutus.db.trials) do
        table.insert(result, { key = key, data = trial })
    end
    table.sort(result, function(a, b) return a.data.startDate > b.data.startDate end)
    return result
end

function TrialTracker:GetActiveTrials()
    local result = {}
    for key, trial in pairs(BRutus.db.trials) do
        if trial.status == self.STATUS.TRIAL then
            table.insert(result, { key = key, data = trial })
        end
    end
    table.sort(result, function(a, b) return a.data.startDate > b.data.startDate end)
    return result
end

function TrialTracker:IsTrial(playerKey)
    local trial = BRutus.db.trials[playerKey]
    return trial and trial.status == self.STATUS.TRIAL
end

function TrialTracker:GetDaysRemaining(playerKey)
    local trial = BRutus.db.trials[playerKey]
    if not trial or trial.status ~= self.STATUS.TRIAL then return nil end
    local remaining = trial.endDate - GetServerTime()
    return math.max(0, math.floor(remaining / 86400))
end

function TrialTracker:GetDaysSinceStart(playerKey)
    local trial = BRutus.db.trials[playerKey]
    if not trial then return nil end
    return math.floor((GetServerTime() - trial.startDate) / 86400)
end

function TrialTracker:CheckExpired()
    local now = GetServerTime()
    local expired = {}
    for key, trial in pairs(BRutus.db.trials) do
        if trial.status == self.STATUS.TRIAL and now > trial.endDate then
            trial.status = self.STATUS.EXPIRED
            table.insert(expired, key)
        end
    end
    if #expired > 0 and BRutus:IsOfficer() then
        BRutus:Print(string.format(L["|cffFF6600%d trial(s) expired!|r Use /brutus to review."], #expired))
    end
end

function TrialTracker:RemoveTrial(playerKey)
    BRutus.db.trials[playerKey] = nil
    self:BroadcastTrials()
end

----------------------------------------------------------------------
-- Progress Snapshots
-- Records iLvl and attunement completion at a point in time
----------------------------------------------------------------------
function TrialTracker:TakeSnapshot(playerKey)
    local trial = BRutus.db.trials[playerKey]
    if not trial then return end
    if not trial.snapshots then trial.snapshots = {} end

    local memberData = BRutus.db.members[playerKey]
    if not memberData then return end

    local attDone, attTotal = 0, 0
    if memberData.attunements then
        for _, att in ipairs(memberData.attunements) do
            attTotal = attTotal + 1
            if att.complete then
                attDone = attDone + 1
            end
        end
    end

    local profData = {}
    if memberData.professions then
        for _, prof in ipairs(memberData.professions) do
            table.insert(profData, { name = prof.name, rank = prof.rank, maxRank = prof.maxRank })
        end
    end

    table.insert(trial.snapshots, {
        timestamp   = GetServerTime(),
        avgIlvl     = memberData.avgIlvl or 0,
        attDone     = attDone,
        attTotal    = attTotal,
        professions = profData,
        level       = memberData.level or 0,
    })
end

function TrialTracker:GetProgress(playerKey)
    local trial = BRutus.db.trials[playerKey]
    if not trial or not trial.snapshots or #trial.snapshots == 0 then
        return nil
    end

    local first = trial.snapshots[1]
    local last = trial.snapshots[#trial.snapshots]
    local memberData = BRutus.db.members[playerKey]

    -- Current live values
    local curIlvl = memberData and memberData.avgIlvl or last.avgIlvl
    local curAttDone, curAttTotal = 0, 0
    if memberData and memberData.attunements then
        for _, att in ipairs(memberData.attunements) do
            curAttTotal = curAttTotal + 1
            if att.complete then curAttDone = curAttDone + 1 end
        end
    else
        curAttDone = last.attDone
        curAttTotal = last.attTotal
    end

    return {
        startIlvl    = first.avgIlvl,
        currentIlvl  = curIlvl,
        ilvlDelta    = curIlvl - first.avgIlvl,
        startAttDone = first.attDone,
        currentAttDone = curAttDone,
        attTotal     = curAttTotal,
        attDelta     = curAttDone - first.attDone,
        startLevel   = first.level,
        currentLevel = memberData and memberData.level or last.level,
        snapCount    = #trial.snapshots,
    }
end

-- Auto-snapshot active trials (call periodically, e.g. on data sync)
function TrialTracker:UpdateSnapshots()
    if not BRutus:IsOfficer() then return end
    local now = GetServerTime()
    for key, trial in pairs(BRutus.db.trials) do
        if trial.status == self.STATUS.TRIAL then
            if not trial.snapshots then trial.snapshots = {} end
            local lastSnap = trial.snapshots[#trial.snapshots]
            -- Take at most one snapshot per day (86400s)
            if not lastSnap or (now - lastSnap.timestamp) > 86400 then
                self:TakeSnapshot(key)
            end
        end
    end
end

----------------------------------------------------------------------
-- Trial Sync — broadcast and receive trial data between officers
----------------------------------------------------------------------
function TrialTracker:BroadcastTrials()
    if not BRutus:IsOfficer() then return end
    if not BRutus.CommSystem then return end
    if not IsInGuild() then return end

    local trials = BRutus.db.trials
    if not trials or not next(trials) then return end

    local LibSerialize = LibStub("LibSerialize")
    local serialized = LibSerialize:Serialize(trials)
    BRutus.CommSystem:SendMessage("TR", serialized)
end

function TrialTracker:HandleIncoming(data)
    if not BRutus:IsOfficer() then return end

    local LibSerialize = LibStub("LibSerialize")
    local ok, incomingTrials = LibSerialize:Deserialize(data)
    if not ok or type(incomingTrials) ~= "table" then return end

    if not BRutus.db.trials then BRutus.db.trials = {} end

    for playerKey, incoming in pairs(incomingTrials) do
        local existing = BRutus.db.trials[playerKey]
        if not existing then
            -- We don't have this trial at all — accept it
            BRutus.db.trials[playerKey] = incoming
        else
            -- Merge: keep the one with more recent activity
            -- Compare by most recent note timestamp, resolvedDate, or startDate
            local incomingTime = incoming.startDate or 0
            local existingTime = existing.startDate or 0

            -- Check latest note
            if incoming.notes and #incoming.notes > 0 then
                local lastNote = incoming.notes[#incoming.notes]
                if lastNote.timestamp and lastNote.timestamp > incomingTime then
                    incomingTime = lastNote.timestamp
                end
            end
            if existing.notes and #existing.notes > 0 then
                local lastNote = existing.notes[#existing.notes]
                if lastNote.timestamp and lastNote.timestamp > existingTime then
                    existingTime = lastNote.timestamp
                end
            end

            -- Check resolved date
            if incoming.resolvedDate and incoming.resolvedDate > incomingTime then
                incomingTime = incoming.resolvedDate
            end
            if existing.resolvedDate and existing.resolvedDate > existingTime then
                existingTime = existing.resolvedDate
            end

            if incomingTime > existingTime then
                -- Incoming is more recent — replace
                BRutus.db.trials[playerKey] = incoming
            elseif incomingTime == existingTime then
                -- Same base — merge notes we don't have
                self:MergeNotes(existing, incoming)
                -- Keep more snapshots
                if incoming.snapshots and existing.snapshots and #incoming.snapshots > #existing.snapshots then
                    existing.snapshots = incoming.snapshots
                end
            end
            -- If existingTime > incomingTime, we already have newer data — skip
        end
    end

    -- Refresh UI if open
    if BRutus.RosterFrame and BRutus.RosterFrame:IsShown() then
        BRutus.RosterFrame:RefreshRoster()
    end
end

-- Merge notes from incoming into existing, avoiding duplicates
function TrialTracker:MergeNotes(existing, incoming)
    if not incoming.notes or #incoming.notes == 0 then return end
    if not existing.notes then existing.notes = {} end

    -- Build a set of existing note signatures (author+timestamp)
    local seen = {}
    for _, note in ipairs(existing.notes) do
        seen[(note.author or "") .. ":" .. (note.timestamp or 0)] = true
    end

    for _, note in ipairs(incoming.notes) do
        local sig = (note.author or "") .. ":" .. (note.timestamp or 0)
        if not seen[sig] then
            table.insert(existing.notes, note)
            seen[sig] = true
        end
    end

    -- Re-sort notes by timestamp
    table.sort(existing.notes, function(a, b)
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)
end
