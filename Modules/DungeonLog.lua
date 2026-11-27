----------------------------------------------------------------------
-- Guild OS - Dungeon log (issue #210, guildos.me #242)
--
-- A clear of one of WoW: Forever's new dungeons, written into my own journal: entering one of
-- them opens a run, a boss killed inside it counts, and killing its final boss is the clear —
-- one per run, however often it dies again. Not every dungeon is a line: the last of the way
-- falling after the end makes that clear a full one. Leaving after the clear, leaving for more than 15
-- minutes (a logout inside counts as leaving), or entering any other instance ends the run; dying
-- and running back before the clear keeps it. A run is one character's: the saved variables are the account's, and
-- an alt in the same guild would otherwise inherit it.
--
-- Separate from RaidTracker, which leaves dungeons alone on purpose. Each client records only its
-- own character: who else was in the group is for guildos.me to work out from everybody's clears
-- (the identity of group members can be secret on Forever).
--
-- WoW: Forever only.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
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
                local encounterID, encounterName, difficultyID, _, success = ...
                DungeonLog:SeeEncounter(encounterID, encounterName, difficultyID, success, GetServerTime())
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
    local instanceName, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType == "party" or instanceType == "raid" then
        self:SeeInstance(instanceID, instanceName, instanceType, difficultyID, now)
    end
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

-- A boss down in my run; its final boss down is the clear, written once into my journal. A wing of an instance
-- with several (Scarlet Monastery, Dire Maul) is the dungeon of the run from its first boss on.
function DungeonLog:OnEncounterEnd(encounterID, success)
    local run = GuildOS.db.dungeonRun
    if not run or run.leftAt or Compat.IsSecret(encounterID) or not (success == 1 or success == true) then return end
    local cat = GuildOS.ForeverDungeons
    if not cat then return end
    local d, id = cat:RouteOf(run.instanceID, encounterID, run.wing)
    if not d or not d.final then return end
    encounterID = id
    if d ~= cat.byInstance[run.instanceID] then run.wing = d.id end
    run.kills[encounterID] = true
    local n = 0
    for _ in pairs(run.kills) do n = n + 1 end
    if run.cleared then
        if n == #d.bosses and run.entry and GuildOS.Journal then GuildOS.Journal:Complete(run.entry, n) end
        return
    end
    if encounterID ~= d.final then return end
    run.cleared = true
    local e = GuildOS.Journal and GuildOS.Journal:Add("dungeon.clear", {
        dungeonId = d.id, dungeonName = d.name, bosses = n, fullClear = n == #d.bosses, runId = run.runId,
    })
    run.entry = e and e.id
    -- The first this client knows of, said to whoever was in it (issue #211): hopeful, local.
    local parent = cat.byInstance[run.instanceID]
    if e and not (parent and parent.classic) and GuildOS.Journal:IsFirstClear(e) then
        GuildOS:Print(string.format(GuildOS.L["First clear of %s for %s!"], d.name, GetGuildInfo("player") or ""))
    end
    return true
end

----------------------------------------------------------------------
-- What the game sent (the probe's dungeon report, Core/Probe.lua): every instance entered and every
-- encounter that ended, by id, so the registry's unverified entries (Data/ForeverDungeons.lua) can be
-- confirmed from a tester's paste. Account-wide (GuildOSDB.probeSeen): a character's alt reports too.
-- A name is kept only when it is readable; a secret id is not kept at all. At most SEEN_MAX of each.
----------------------------------------------------------------------
local SEEN_MAX = 200

local function seenStore()
    if type(GuildOSDB) ~= "table" then return nil end
    local s = GuildOSDB.probeSeen
    if type(s) ~= "table" then
        s = {}
        GuildOSDB.probeSeen = s
    end
    s.instances = type(s.instances) == "table" and s.instances or {}
    s.encounters = type(s.encounters) == "table" and s.encounters or {}
    return s
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function plainName(v)
    if v == nil or Compat.IsSecret(v) then return nil end
    v = tostring(v)
    return v ~= "" and v:sub(1, 60) or nil
end

local function sane(id)
    return type(id) == "number" and id > 0 and id == math.floor(id) and id < 1e7 and not Compat.IsSecret(id)
end

function DungeonLog:SeeInstance(instanceID, name, kind, difficultyID, now)
    if not sane(instanceID) then return end
    local s = seenStore()
    if not s then return end
    local e = s.instances[instanceID]
    if not e then
        if count(s.instances) >= SEEN_MAX then return end
        e = { n = 0 }
        s.instances[instanceID] = e
    end
    e.name = plainName(name) or e.name
    e.kind = kind
    e.difficulty = sane(difficultyID) and difficultyID or e.difficulty
    e.n = (e.n or 0) + 1
    e.at = now
end

function DungeonLog:SeeEncounter(encounterID, name, difficultyID, success, now)
    if not sane(encounterID) then return end
    local s = seenStore()
    if not s then return end
    local e = s.encounters[encounterID]
    if not e then
        if count(s.encounters) >= SEEN_MAX then return end
        e = {}
        s.encounters[encounterID] = e
    end
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    e.name = plainName(name) or e.name
    e.instance = sane(instanceID) and instanceID or e.instance
    e.difficulty = sane(difficultyID) and difficultyID or e.difficulty
    if success == 1 or success == true then e.kills = (e.kills or 0) + 1 else e.wipes = (e.wipes or 0) + 1 end
    e.at = now
end

-- What was seen, for the probe: { instances = { { id, name, kind, difficulty, status } }, encounters = { ... } },
-- each sorted by id. `status`: "known", "unverified" or "new" (not in the registry).
function DungeonLog:SeenReport()
    local s = seenStore() or { instances = {}, encounters = {} }
    local cat = GuildOS.ForeverDungeons
    local out = { instances = {}, encounters = {} }
    for id, e in pairs(s.instances) do
        out.instances[#out.instances + 1] = { id = id, name = e.name, kind = e.kind, difficulty = e.difficulty,
            status = (cat and cat:StatusOf(id)) or "new" }
    end
    for id, e in pairs(s.encounters) do
        out.encounters[#out.encounters + 1] = { id = id, name = e.name, instance = e.instance, difficulty = e.difficulty,
            kills = e.kills or 0, status = (cat and e.instance and cat:StatusOf(e.instance, id)) or "new" }
    end
    table.sort(out.instances, function(a, b) return a.id < b.id end)
    table.sort(out.encounters, function(a, b) return a.id < b.id end)
    return out
end
