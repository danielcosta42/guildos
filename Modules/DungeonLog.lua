----------------------------------------------------------------------
-- Guild OS - Dungeon log (issue #210, guildos.me #242)
--
-- A clear of one of WoW: Forever's new dungeons, written into my own journal: entering one of
-- them opens a run, a boss killed inside it counts, and killing its final boss is the clear —
-- one per run, however often it dies again. Leaving after the clear, leaving for more than 15
-- minutes (a logout inside counts as leaving), or entering any other instance ends the run; dying
-- and running back keeps it. A run is one character's: the saved variables are the account's, and
-- an alt in the same guild would otherwise inherit it.
--
-- Separate from RaidTracker, which leaves dungeons alone on purpose. Each client records only its
-- own character: who else was in the group is for guildos.me to work out from everybody's clears
-- (the identity of group members can be secret on Forever).
--
-- WoW: Forever only.
----------------------------------------------------------------------
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

local DungeonLog = {}
GuildOS.DungeonLog = DungeonLog

local Compat = GuildOS.Compat
local AWAY_S = 15 * 60

local function dungeonOf(instanceID)
    local cat = GuildOS.ForeverDungeons
    return cat and cat.byInstance[instanceID] or nil
end

function DungeonLog:Initialize()
    if not self.frame then
        self.frame = CreateFrame("Frame")
        Compat.RegisterEvent(self.frame, "PLAYER_ENTERING_WORLD")
        Compat.RegisterEvent(self.frame, "ZONE_CHANGED_NEW_AREA")
        Compat.RegisterEvent(self.frame, "ENCOUNTER_END")
        Compat.RegisterEvent(self.frame, "PLAYER_LOGOUT")
        self.frame:SetScript("OnEvent", function(_, event, ...)
            if event == "PLAYER_LOGOUT" then
                DungeonLog:OnLogout(GetServerTime())
            elseif event == "ENCOUNTER_END" then
                local encounterID, _, _, _, success = ...
                DungeonLog:OnEncounterEnd(encounterID, success)
            else
                DungeonLog:OnZone(GetServerTime())
            end
        end)
    end
    self:OnZone(GetServerTime())
end

-- Where I am now: a run opens in a catalogued dungeon, carries on after a short trip out, and ends
-- after a long one, after the clear or in any other instance. Kept in the guild's db, so a /reload
-- inside keeps it.
function DungeonLog:OnZone(now)
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    local me = GuildOS:GetPlayerKey(Compat.PlayerName())
    local run = GuildOS.db.dungeonRun
    if run and (run.who ~= me or run.leftAt and now - run.leftAt > AWAY_S) then run, GuildOS.db.dungeonRun = nil, nil end
    if instanceType == "party" and dungeonOf(instanceID) then
        if run and run.instanceID == instanceID then
            run.leftAt = nil
        else
            GuildOS.db.dungeonRun = { who = me, instanceID = instanceID, runId = instanceID .. ":" .. now, kills = {}, cleared = false }
        end
    elseif run and (run.cleared or instanceType ~= "none") then
        GuildOS.db.dungeonRun = nil
    elseif run and not run.leftAt then
        run.leftAt = now
    end
end

-- Logging out inside is leaving: tomorrow's run of the same dungeon is another run.
function DungeonLog:OnLogout(now)
    local run = GuildOS.db.dungeonRun
    if run and not run.leftAt then run.leftAt = now end
end

-- A boss down in my run; its final boss down is the clear, written once into my journal.
function DungeonLog:OnEncounterEnd(encounterID, success)
    local run = GuildOS.db.dungeonRun
    if not run or run.leftAt or Compat.IsSecret(encounterID) or not (success == 1 or success == true) then return end
    local d = dungeonOf(run.instanceID)
    if not d or not d.final then return end
    local known = false
    for _, id in ipairs(d.bosses) do
        if id == encounterID then known = true break end
    end
    if not known then return end
    run.kills[encounterID] = true
    if encounterID ~= d.final or run.cleared then return end
    run.cleared = true
    local n = 0
    for _ in pairs(run.kills) do n = n + 1 end
    if GuildOS.Journal then
        GuildOS.Journal:Add("dungeon.clear", {
            dungeonId = d.id, dungeonName = d.name, bosses = n, fullClear = n == #d.bosses, runId = run.runId,
        })
    end
    return true
end
