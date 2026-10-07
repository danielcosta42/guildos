----------------------------------------------------------------------
-- Guild OS - Trial Member Tracker
-- Tracks trial/recruit members: start date, evaluation notes, status
-- Progress snapshots for iLvl and attunement tracking
----------------------------------------------------------------------
local TrialTracker = {}
GuildOS.TrialTracker = TrialTracker
local L = GuildOS.L

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
    if not GuildOS.db.trials then
        GuildOS.db.trials = {}  -- [playerKey] = { startDate, endDate, status, notes, sponsor, snapshots }
    end
    -- Migrate old trials missing snapshots
    for _, trial in pairs(GuildOS.db.trials) do
        if not trial.snapshots then trial.snapshots = {} end
    end
end

function TrialTracker:AddTrial(playerKey, sponsor)
    if not GuildOS:IsOfficer() then return false end

    local now = GetServerTime()
    GuildOS.db.trials[playerKey] = {
        startDate = now,
        endDate = now + self.DEFAULT_DURATION,
        status = self.STATUS.TRIAL,
        notes = {},
        sponsor = sponsor or GuildOS.Compat.PlayerName(),
        snapshots = {},
    }

    -- Take initial snapshot
    self:TakeSnapshot(playerKey)

    GuildOS:Print(playerKey .. L[" marked as trial by "] .. (sponsor or GuildOS.Compat.PlayerName()))
    self:BroadcastTrials()
    return true
end

function TrialTracker:UpdateStatus(playerKey, newStatus)
    if not GuildOS:IsOfficer() then return end
    local trial = GuildOS.db.trials[playerKey]
    if not trial then return end

    trial.status = newStatus
    if newStatus == self.STATUS.APPROVED or newStatus == self.STATUS.DENIED then
        trial.resolvedDate = GetServerTime()
        trial.resolvedBy = GuildOS.Compat.PlayerName()
    end
    self:BroadcastTrials()
end

function TrialTracker:AddTrialNote(playerKey, text)
    if not GuildOS:IsOfficer() then return end
    local trial = GuildOS.db.trials[playerKey]
    if not trial then return end

    table.insert(trial.notes, {
        text = text,
        author = GuildOS.Compat.PlayerName(),
        timestamp = GetServerTime(),
    })
    self:BroadcastTrials()
end

function TrialTracker:GetTrial(playerKey)
    return GuildOS.db.trials[playerKey]
end

function TrialTracker:GetAllTrials()
    local result = {}
    for key, trial in pairs(GuildOS.db.trials) do
        table.insert(result, { key = key, data = trial })
    end
    table.sort(result, function(a, b) return a.data.startDate > b.data.startDate end)
    return result
end

function TrialTracker:GetActiveTrials()
    local result = {}
    for key, trial in pairs(GuildOS.db.trials) do
        if trial.status == self.STATUS.TRIAL then
            table.insert(result, { key = key, data = trial })
        end
    end
    table.sort(result, function(a, b) return a.data.startDate > b.data.startDate end)
    return result
end

function TrialTracker:IsTrial(playerKey)
    local trial = GuildOS.db.trials[playerKey]
    return trial and trial.status == self.STATUS.TRIAL
end

function TrialTracker:GetDaysRemaining(playerKey)
    local trial = GuildOS.db.trials[playerKey]
    if not trial or trial.status ~= self.STATUS.TRIAL then return nil end
    local remaining = trial.endDate - GetServerTime()
    return math.max(0, math.floor(remaining / 86400))
end

function TrialTracker:GetDaysSinceStart(playerKey)
    local trial = GuildOS.db.trials[playerKey]
    if not trial then return nil end
    return math.floor((GetServerTime() - trial.startDate) / 86400)
end

function TrialTracker:CheckExpired()
    local now = GetServerTime()
    local expired = {}
    for key, trial in pairs(GuildOS.db.trials) do
        if trial.status == self.STATUS.TRIAL and now > trial.endDate then
            trial.status = self.STATUS.EXPIRED
            table.insert(expired, key)
        end
    end
    if #expired > 0 and GuildOS:IsOfficer() then
        GuildOS:Print(string.format(L["|cffFF6600%d trial(s) expired!|r Use /guildos to review."], #expired))
    end
end

function TrialTracker:RemoveTrial(playerKey)
    GuildOS.db.trials[playerKey] = nil
    self:BroadcastTrials()
end

----------------------------------------------------------------------
-- Progress Snapshots
-- Records iLvl and attunement completion at a point in time
----------------------------------------------------------------------
function TrialTracker:TakeSnapshot(playerKey)
    local trial = GuildOS.db.trials[playerKey]
    if not trial then return end
    if not trial.snapshots then trial.snapshots = {} end

    local memberData = GuildOS.db.members[playerKey]
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
    local trial = GuildOS.db.trials[playerKey]
    if not trial or not trial.snapshots or #trial.snapshots == 0 then
        return nil
    end

    local first = trial.snapshots[1]
    local last = trial.snapshots[#trial.snapshots]
    local memberData = GuildOS.db.members[playerKey]

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
    if not GuildOS:IsOfficer() then return end
    local now = GetServerTime()
    for key, trial in pairs(GuildOS.db.trials) do
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
    if not GuildOS:IsOfficer() then return end
    if not GuildOS.CommSystem then return end
    if not IsInGuild() then return end

    local trials = GuildOS.db.trials
    if not trials or not next(trials) then return end

    local LibSerialize = LibStub("GuildOS-LibSerialize")
    local serialized = LibSerialize:Serialize(trials)
    GuildOS.CommSystem:SendMessage("TR", serialized)
end

-- Reached only through CommSystem:OnMessageReceived, which has checked the sender is an officer
-- and the channel GUILD (issue #78). Any other caller must check the same.
function TrialTracker:HandleIncoming(data)
    if not GuildOS:IsOfficer() then return end

    local LibSerialize = LibStub("GuildOS-LibSerialize")
    local ok, incomingTrials = LibSerialize:Deserialize(data)
    if not ok or type(incomingTrials) ~= "table" then return end

    if not GuildOS.db.trials then GuildOS.db.trials = {} end

    for incomingKey, incoming in pairs(incomingTrials) do
        local playerKey = GuildOS:LocalMemberKey(incomingKey)   -- the sender's key, as this client's (#97)
        local existing = GuildOS.db.trials[playerKey]
        GuildOS.db.trials[playerKey] = existing and self:Merge(existing, incoming) or incoming
    end

    -- Refresh UI if open
    GuildOS:RefreshRosterUI()
end

-- The trial to keep when two copies of one meet: the more recent activity (start, last note or
-- resolution) wins, and a tie merges their notes. On receipt and in the stored-key migration (#97).
function TrialTracker:Merge(existing, incoming)
    local function latest(t)
        local at = tonumber(t.startDate) or 0
        local last = type(t.notes) == "table" and t.notes[#t.notes]
        if type(last) == "table" and (tonumber(last.timestamp) or 0) > at then at = tonumber(last.timestamp) end
        if (tonumber(t.resolvedDate) or 0) > at then at = tonumber(t.resolvedDate) end
        return at
    end
    local it, et = latest(incoming), latest(existing)
    if it > et then return incoming end
    if it == et then
        self:MergeNotes(existing, incoming)
        -- Keep more snapshots
        if incoming.snapshots and existing.snapshots and #incoming.snapshots > #existing.snapshots then
            existing.snapshots = incoming.snapshots
        end
    end
    return existing
end

-- Merge notes from incoming into existing, avoiding duplicates
function TrialTracker:MergeNotes(existing, incoming)
    if type(incoming.notes) ~= "table" or #incoming.notes == 0 then return end
    if type(existing.notes) ~= "table" then existing.notes = {} end

    -- Build a set of existing note signatures (author+timestamp)
    local seen = {}
    for _, note in ipairs(existing.notes) do
        if type(note) == "table" then seen[(note.author or "") .. ":" .. (note.timestamp or 0)] = true end
    end

    for _, note in ipairs(incoming.notes) do
        local sig = type(note) == "table" and ((note.author or "") .. ":" .. (note.timestamp or 0))
        if sig and not seen[sig] then
            table.insert(existing.notes, note)
            seen[sig] = true
        end
    end

    -- Re-sort notes by timestamp (anything that is not a note sorts first, as time 0)
    local function at(n) return type(n) == "table" and tonumber(n.timestamp) or 0 end
    table.sort(existing.notes, function(a, b) return at(a) < at(b) end)
end
