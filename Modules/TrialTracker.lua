----------------------------------------------------------------------
-- Guild OS - Trial Member Tracker
-- Tracks trial/recruit members: start date, evaluation notes, status
-- Progress snapshots for iLvl and attunement tracking
--
-- The length of a trial is the guild's (issue #249): whole days, set by an officer in the Trials
-- panel and kept on every client the way the officer threshold is (guildcfg, newest stamp wins).
-- A trial's end is never read from the record: it is its start plus the guild's length, worked out
-- every time, so a change of length moves every running trial, up or down, and an officer still on a
-- version before it, who keeps sending whole trials with the end they had, cannot undo that.
----------------------------------------------------------------------
local TrialTracker = {}
GuildOS.TrialTracker = TrialTracker
local L = GuildOS.L

-- Trial status values
TrialTracker.STATUS = {
    TRIAL    = "trial",
    APPROVED = "approved",
    DENIED   = "denied",
    -- Written only by clients before #249, when their own end passed. Read as a trial nobody has
    -- decided yet: whether it is still running is worked out like any other's.
    EXPIRED  = "expired",
}

local DAY = 86400
TrialTracker.DEFAULT_DAYS = 30   -- a guild that never chose a length
TrialTracker.MIN_DAYS = 1
TrialTracker.MAX_DAYS = 90
local STAMP_FUTURE_SLACK = 300   -- seconds a stamp may run ahead of this client's clock, as the officer threshold's
-- Seconds after a login or /reload before the roster is compared: the guild's settings and the other
-- officers' trials arrive a few seconds after login (CommSystem's request answers), and a catch-up run
-- before them reads a switch or a trial list the guild has already changed.
TrialTracker.SETTLE_SECONDS = 60

-- Who a trial started for a newcomer names as its sponsor: no officer vouched for them, and the same
-- name on every client lets two officers' copies of one join meet as one (Merge).
TrialTracker.AUTO_SPONSOR = "Guild OS"

-- Session state (Rule 6): `settled`, whether this login's settle window is over (nil until Arm's timer fires).
local function session()
    GuildOS.State.trials = GuildOS.State.trials or {}
    return GuildOS.State.trials
end

-- An open Trials panel's refresh, set by the panel (UI/FeaturePanels.lua); nil while none was built.
function TrialTracker:RefreshUI()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

function TrialTracker:Initialize()
    if not GuildOS.db.trials then
        GuildOS.db.trials = {}  -- [playerKey] = { startDate, endDate, status, notes, sponsor, snapshots }
    end
    -- Migrate old trials missing snapshots
    for _, trial in pairs(GuildOS.db.trials) do
        if type(trial) == "table" and not trial.snapshots then trial.snapshots = {} end
    end
end

----------------------------------------------------------------------
-- The guild's settings: the length and the switch for new members
----------------------------------------------------------------------
-- A trial length in whole days, or nil when `v` is not one: 1 to 90, a number or digits typed in a
-- box. Anything else is refused as it is, never clamped or read for what it might have meant.
function TrialTracker.ValidDays(v)
    if type(v) == "string" then
        if not v:match("^%s*%d+%s*$") then return nil end
        v = tonumber(v)
    end
    if type(v) ~= "number" or v ~= v or v ~= math.floor(v) then return nil end   -- v ~= v: NaN
    if v < TrialTracker.MIN_DAYS or v > TrialTracker.MAX_DAYS then return nil end
    return v
end

local function settings() return GuildOS.db and GuildOS.db.settings end

-- The guild's trial length in days: the officers' choice, 30 until one is made.
function TrialTracker:GetDays()
    local s = settings()
    return (s and self.ValidDays(s.trialDays)) or self.DEFAULT_DAYS
end

-- Whether every new member starts as a trial. Off until an officer turns it on.
function TrialTracker:IsAutoOn()
    local s = settings()
    return s ~= nil and s.trialAuto == true
end

-- A stamp that only moves forward, past the one held: a clock a second behind, or two clicks in one
-- second, would otherwise stamp a change the rest of the guild turns away as old.
local function stamp(s, field)
    s[field] = math.max(GetServerTime(), (s[field] or 0) + 1)
end

-- An officer sets the guild's length; what is not 1 to 90 whole days is refused. Whether it was taken,
-- and when not why: "officer" (this client is not one) or "range" (no length of days).
function TrialTracker:SetDays(v)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local days = self.ValidDays(v)
    if not days then return false, "range" end
    local s = settings()
    s.trialDays = days
    stamp(s, "trialDaysAt")
    self:PublishConfig()
    return true
end

-- An officer turns the switch for new members on or off. Turning it on only takes the roster as it is:
-- nobody already in the guild becomes a trial. Whether it was taken.
function TrialTracker:SetAuto(on)
    if not GuildOS:IsOfficer() then return false end
    on = on and true or false
    local s = settings()
    local was = s.trialAuto == true
    s.trialAuto = on
    stamp(s, "trialAutoAt")
    if on and not was then self:ResetBaseline() end
    self:PublishConfig()
    return true
end

-- To the guild: when it changes, and again on the officers' regular sync and their answer to a request,
-- for a client that missed it. Only a setting somebody made: a guild that never chose sends nothing.
-- Neither payload has `max`: a client before #249 reads an unknown guildcfg action as the officer
-- threshold, and one with no `max` it ignores.
function TrialTracker:PublishConfig()
    local s = settings()
    if not (s and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    if s.trialDaysAt then
        GuildOS.SyncService:Publish("guildcfg", "trialdays", { days = self:GetDays() }, { rev = s.trialDaysAt })
    end
    if s.trialAutoAt then
        GuildOS.SyncService:Publish("guildcfg", "trialauto", { on = self:IsAutoOn() }, { rev = s.trialAutoAt })
    end
end

-- A stamp off the network, held to five minutes past this client's clock, or nil when it is no time.
-- `at > 0` also turns away NaN, which compares false to everything.
local function stampOf(env)
    local at = tonumber(env.rev)
    if not (at and at > 0 and at < math.huge) then return nil end
    return math.min(at, GetServerTime() + STAMP_FUTURE_SLACK)
end

-- From an officer (SyncService checked the officer and GUILD): the newest stamp wins. Two in the same
-- second settle on the shorter length and on the switch off, the same on every client whatever the order.
function TrialTracker:OnConfigSync(env)
    local data = type(env) == "table" and env.data
    local s = settings()
    if type(data) ~= "table" or not s then return end
    local at = stampOf(env)
    if not at then return end
    if env.act == "trialdays" then
        local days = type(data.days) == "number" and self.ValidDays(data.days)
        if not days then return end
        local held = s.trialDaysAt
        if held and (at < held or (at == held and days >= self:GetDays())) then return end
        s.trialDays, s.trialDaysAt = days, at
    elseif env.act == "trialauto" then
        if type(data.on) ~= "boolean" then return end
        local held = s.trialAutoAt
        if held and (at < held or (at == held and (data.on or not self:IsAutoOn()))) then return end
        local was = self:IsAutoOn()
        s.trialAuto, s.trialAutoAt = data.on, at
        if data.on and not was then self:ResetBaseline() end
    else
        return
    end
    self:RefreshUI()
end

----------------------------------------------------------------------
-- A trial's state, worked out
----------------------------------------------------------------------
-- A trial nobody has approved or denied: running, ready to review, or of somebody who left.
function TrialTracker:IsUnresolved(trial)
    return type(trial) == "table" and (trial.status == self.STATUS.TRIAL or trial.status == self.STATUS.EXPIRED)
end

-- Whether the trial's member was missing from the last whole roster an officer's client read: `leftAt`,
-- a field and not a status, so a client before #249 carries it untouched. Cleared when they are back.
function TrialTracker:HasLeft(trial)
    return type(trial) == "table" and trial.leftAt ~= nil
end

-- When a trial ends: its start plus the guild's length. The record's own endDate is never read.
function TrialTracker:EndOf(trial)
    return (tonumber(trial.startDate) or 0) + self:GetDays() * DAY
end

-- Whether a trial waits for a decision: nobody made one, its end has passed, and its member is still here.
function TrialTracker:IsReady(trial, now)
    return self:IsUnresolved(trial) and not self:HasLeft(trial) and (now or GetServerTime()) >= self:EndOf(trial)
end

-- "trial" while it runs, "review" once it is ready to review, "left" when its member left the guild
-- with nobody having decided, "approved" or "denied" once decided, the record's own word for anything
-- else; nil when the player has no trial.
function TrialTracker:GetState(playerKey)
    local trial = GuildOS.db.trials[playerKey]
    if type(trial) ~= "table" then return nil end
    if self:IsUnresolved(trial) then
        if self:HasLeft(trial) then return "left" end
        return self:IsReady(trial) and "review" or "trial"
    end
    return trial.status
end

-- How many trials wait for a decision, nobody's who left counted.
function TrialTracker:CountReady()
    local now, n = GetServerTime(), 0
    for _, trial in pairs(GuildOS.db.trials or {}) do
        if self:IsReady(trial, now) then n = n + 1 end
    end
    return n
end

----------------------------------------------------------------------
-- Adding and deciding
----------------------------------------------------------------------
-- A new trial for `playerKey`, starting now, without telling the other officers yet. Over an older
-- trial (approved or denied, and back in the guild) it keeps that one's notes: what officers wrote stays.
local function newTrial(self, playerKey, sponsor)
    local now = GetServerTime()
    local old = GuildOS.db.trials[playerKey]
    GuildOS.db.trials[playerKey] = {
        startDate = now,
        -- Never read here (EndOf works it out): kept for clients before #249, which read it.
        endDate = now + self:GetDays() * DAY,
        status = self.STATUS.TRIAL,
        notes = type(old) == "table" and type(old.notes) == "table" and old.notes or {},
        sponsor = sponsor,
        snapshots = {},
    }

    -- Take initial snapshot
    self:TakeSnapshot(playerKey)

    GuildOS:Print(playerKey .. L[" marked as trial by "] .. sponsor)
end

function TrialTracker:AddTrial(playerKey, sponsor)
    if not GuildOS:IsOfficer() then return false end
    newTrial(self, playerKey, sponsor or GuildOS.Compat.PlayerName())
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

local function byStart(a, b)
    local sa, sb = tonumber(a.data.startDate) or 0, tonumber(b.data.startDate) or 0
    if sa ~= sb then return sa > sb end
    return a.key < b.key
end

-- Every trial: the ones ready to review first, then the running ones, then the decided, each the newest first.
function TrialTracker:GetAllTrials()
    local now, result = GetServerTime(), {}
    for key, trial in pairs(GuildOS.db.trials) do
        if type(trial) == "table" then
            -- Somebody who left sits with the decided: nothing there waits on the officers.
            local group = 3
            if self:IsUnresolved(trial) and not self:HasLeft(trial) then group = self:IsReady(trial, now) and 1 or 2 end
            table.insert(result, { key = key, data = trial, group = group })
        end
    end
    table.sort(result, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return byStart(a, b)
    end)
    return result
end

-- The trials nobody has decided yet, running and ready to review, of members still here, the newest first.
function TrialTracker:GetActiveTrials()
    local result = {}
    for key, trial in pairs(GuildOS.db.trials) do
        if self:IsUnresolved(trial) and not self:HasLeft(trial) then
            table.insert(result, { key = key, data = trial })
        end
    end
    table.sort(result, byStart)
    return result
end

-- Whether the player is on a trial nobody has decided yet (running, ready to review, or left meanwhile).
function TrialTracker:IsTrial(playerKey)
    return self:IsUnresolved(GuildOS.db.trials[playerKey])
end

-- Whole days left, rounded down, of a trial nobody has decided: 0 once it is ready to review. Nil for a
-- decided trial and for one whose member left.
function TrialTracker:GetDaysRemaining(playerKey)
    local trial = GuildOS.db.trials[playerKey]
    if not self:IsUnresolved(trial) or self:HasLeft(trial) then return nil end
    local remaining = self:EndOf(trial) - GetServerTime()
    return math.max(0, math.floor(remaining / DAY))
end

function TrialTracker:GetDaysSinceStart(playerKey)
    local trial = GuildOS.db.trials[playerKey]
    if not trial then return nil end
    return math.floor((GetServerTime() - (tonumber(trial.startDate) or 0)) / DAY)
end

-- At an officer's login: one line when trials wait for a decision. Nothing is written: a trial is ready
-- to review because of its start and the guild's length, worked out each time (issue #249).
function TrialTracker:CheckReady()
    if not GuildOS:IsOfficer() then return end
    local n = self:CountReady()
    if n > 0 then
        GuildOS:Print(string.format(L["|cffFF6600%d trial(s) ready to review.|r Approve or deny them in the Trials tab."], n))
    end
end

function TrialTracker:RemoveTrial(playerKey)
    GuildOS.db.trials[playerKey] = nil
    self:BroadcastTrials()
end

----------------------------------------------------------------------
-- New members (issue #249): with the guild's switch on, an officer's client starts a trial for
-- whoever is on the roster and was not on the one it last saw whole, whether they joined a moment ago
-- (the join line only asks for a fresh roster) or while nobody's addon watched. ScanRoster is the only
-- path that starts one, so every key comes from the roster.
----------------------------------------------------------------------
-- Whether a newcomer becomes a trial here: the switch is on, this is an officer's client with the
-- tracker on and in the guild whose database it holds, the newcomer is somebody else, not on an
-- officer rank, and has no trial at all. Not a decided one either: an officer who never saw the join
-- would otherwise reopen an approval, and somebody who comes back after a decision is the officers'
-- to put on trial again, by hand (Mark as Trial).
function TrialTracker:MayAutoTrial(playerKey, onOfficerRank)
    if not (self:IsAutoOn() and GuildOS:IsOfficer() and GuildOS:IsFeatureEnabled("trialTracker")) then return false end
    if type(playerKey) ~= "string" or playerKey == "" or onOfficerRank then return false end
    if not GuildOS:IsOnGuildDB() then return false end
    if playerKey == GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) then return false end
    return GuildOS.db.trials[playerKey] == nil
end

-- Somebody joined (RosterLog read the game's line): with the switch on, an officer's client asks for a
-- fresh roster, and ScanRoster starts the trial from it. The line's name is never made into a key: on
-- WoW: Forever it need not be the roster's spelling ("Chehul-Costa" against "Chehul Costa"), and two
-- strings for one person would be two trials. Keys come from the roster alone. Whether it asked.
function TrialTracker:OnJoin(name)
    if type(name) ~= "string" or name == "" then return false end
    if not (self:IsAutoOn() and GuildOS:IsOfficer() and GuildOS:IsFeatureEnabled("trialTracker")) then return false end
    GuildOS.Compat.GuildRoster()   -- the game throttles it; a later GUILD_ROSTER_UPDATE is as good
    return true
end

-- At every login and /reload (Core's MODULE_START): the roster is not compared for SETTLE_SECONDS, so
-- the guild's switch and the other officers' trials have arrived, and then it is, once, by itself,
-- whether a roster event comes or not.
function TrialTracker:Arm()
    local st = session()
    st.settled = nil
    GuildOS.Compat.After(self.SETTLE_SECONDS, function()
        st.settled = true
        GuildOS:SafeCall(self.ScanRoster, self)
    end)
end

-- Forget the roster seen, so the next whole one is only taken, never compared: when the switch turns on.
-- The baseline is an officer's client's: on any other (an alt on the account, which shares this
-- database) the switch going on leaves `db.trialBaselinePending`, and the next officer's look honours
-- it as a look that only takes the roster, so nobody who joined before the switch becomes a trial.
function TrialTracker:ResetBaseline()
    local db = GuildOS.db
    if not db then return end
    if not GuildOS:IsOfficer() then
        db.trialBaselinePending = true
        return
    end
    db.trialBaseline, db.trialBaselinePending = nil, nil
    self:ScanRoster()
end

-- Somebody left or was removed (RosterLog read the game's line): out of the roster seen, so coming
-- back is joining again. The only way a key leaves it, so a short roster takes nobody out; who leaves
-- while no officer's addon sees it stays in, and is not a newcomer if they come back.
function TrialTracker:OnLeave(name)
    local db = GuildOS.db
    if type(name) ~= "string" or name == "" or not db or type(db.trialBaseline) ~= "table" then return false end
    if not GuildOS:IsOfficer() then return false end
    db.trialBaseline[GuildOS:KeyOfRosterName(name)] = nil
    return true
end

-- Every undecided trial is marked by whether its member is on this whole roster: `leftAt` when missing,
-- cleared when back. Whether anything changed.
local function markLeft(self, present, now)
    local changed = false
    for key, trial in pairs(GuildOS.db.trials or {}) do
        if self:IsUnresolved(trial) then
            if present[key] then
                if trial.leftAt ~= nil then trial.leftAt, changed = nil, true end
            elseif trial.leftAt == nil then
                trial.leftAt, changed = now, true
            end
        end
    end
    return changed
end

-- On every roster update, on an officer's client only: the whole roster against the roster seen
-- (`db.trialBaseline`, keys only, kept between sessions, the account's for this guild). Whoever is new
-- to it is a newcomer, and the first look (a fresh install, the switch just turned on, a character
-- whose last look was not an officer's) only takes the roster. A non-officer client neither reads nor
-- writes it: an alt on the same account would otherwise take the officer's newcomers in. Each
-- character's last look is remembered (`db.trialScannedAsOfficer`, by character, since the account
-- shares the database): while demoted, or outside a narrowed threshold, a character's look forgets it,
-- so its first look as an officer again does not read a month of members as new. The baseline only
-- grows (OnLeave takes a key out), so a roster that comes short never reads the rest of the guild as
-- new. Nothing moves in a login's settle window (Arm), while the roster is not whole (a row missing
-- would read as gone) or while the client does not know its own rank yet. ponytail: a full pass on
-- every GUILD_ROSTER_UPDATE, like DropDeparted's.
function TrialTracker:ScanRoster()
    local db = GuildOS.db
    if not session().settled then return end
    if not (db and IsInGuild() and GuildOS:IsOnGuildDB()) then return end
    if select(3, GetGuildInfo("player")) == nil then return end
    local me = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
    local asOfficer = db.trialScannedAsOfficer
    if not GuildOS:IsOfficer() then
        if type(asOfficer) == "table" and asOfficer[me] then asOfficer[me] = nil end
        return
    end
    if type(asOfficer) ~= "table" then asOfficer = {}; db.trialScannedAsOfficer = asOfficer end
    local wasOfficer = asOfficer[me] == true
    local n = GetNumGuildMembers() or 0
    if n == 0 then return end
    local maxRank = GuildOS:GetSetting("officerMaxRank") or 1
    local rows = {}
    for i = 1, n do
        local full, _, rankIndex = GetGuildRosterInfo(i)
        if not full then return end
        rows[i] = { key = GuildOS:KeyOfRosterName(full), officer = rankIndex ~= nil and rankIndex <= maxRank }
    end
    local base, present, newcomers, shared = db.trialBaseline, {}, {}, false
    for _, r in ipairs(rows) do
        present[r.key] = true
        if type(base) == "table" then
            if base[r.key] then shared = true else newcomers[#newcomers + 1] = r end
        end
    end
    asOfficer[me] = true
    -- The first look, the first since this character was not an officer, or the first since the switch
    -- went on where only a non-officer heard it (ResetBaseline's pending mark): only the roster is taken.
    if type(base) ~= "table" or not wasOfficer or db.trialBaselinePending then
        db.trialBaselinePending = nil
        if type(base) == "table" then
            for _, r in ipairs(newcomers) do base[r.key] = true end
        else
            db.trialBaseline = present
        end
        if markLeft(self, present, GetServerTime()) then self:BroadcastTrials() end
        return
    end
    for _, r in ipairs(newcomers) do base[r.key] = true end
    -- A roster that shares nobody with the one seen is no guild of newcomers: the keys changed under it.
    if not shared then return end
    local changed = markLeft(self, present, GetServerTime())
    for _, nc in ipairs(newcomers) do
        if self:MayAutoTrial(nc.key, nc.officer) then
            newTrial(self, nc.key, self.AUTO_SPONSOR)
            changed = true
        end
    end
    if changed then self:BroadcastTrials() end
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

-- Auto-snapshot the trials nobody has decided yet (call periodically, e.g. on data sync)
function TrialTracker:UpdateSnapshots()
    if not GuildOS:IsOfficer() then return end
    local now = GetServerTime()
    for key, trial in pairs(GuildOS.db.trials) do
        if self:IsUnresolved(trial) then
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
    self:RefreshUI()
end

-- The trial to keep when two copies of one meet. Both undecided ("trial" or "expired"): the earlier
-- start, with both copies' notes and the longer snapshots, so a second officer whose catch-up started
-- the same person's trial later neither restarts it nor drops what was written (#249). An approved or
-- denied copy against one started automatically (sponsor AUTO_SPONSOR): the decision, whatever the
-- dates, with both copies' notes, so an officer whose client never saw the decision cannot reopen it.
-- Otherwise, a decided copy on either side: the more recent activity (start, last note or resolution)
-- wins, and a tie merges their notes. On receipt and in the stored-key migration (#97).
function TrialTracker:Merge(existing, incoming)
    local eu, iu = self:IsUnresolved(existing), self:IsUnresolved(incoming)
    if eu and iu then
        local keep, other = existing, incoming
        if (tonumber(incoming.startDate) or 0) < (tonumber(existing.startDate) or 0) then keep, other = incoming, existing end
        self:MergeNotes(keep, other)
        if type(other.snapshots) == "table" and (type(keep.snapshots) ~= "table" or #other.snapshots > #keep.snapshots) then
            keep.snapshots = other.snapshots
        end
        return keep
    end
    local function decided(t) return t.status == self.STATUS.APPROVED or t.status == self.STATUS.DENIED end
    local open, done = (eu and existing) or (iu and incoming), (eu and incoming) or (iu and existing)
    if open and decided(done) and open.sponsor == self.AUTO_SPONSOR then
        self:MergeNotes(done, open)
        return done
    end
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
