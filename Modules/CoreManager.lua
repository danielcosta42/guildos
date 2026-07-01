----------------------------------------------------------------------
-- Guild OS - Core Manager
-- Manages multiple raid cores, each with independent loot rules,
-- attendance penalties, and a DKP/points pool.
--
-- The "active core" is always the current RaidTracker groupTag.
-- CoreManager enriches that existing concept with per-core configs.
----------------------------------------------------------------------
local CoreManager = {}
BRutus.CoreManager = CoreManager
local L = BRutus.L

CoreManager.CLASS_DEFAULT_ROLE = {
    WARRIOR="tank",  PALADIN="healer", HUNTER="rdps",  ROGUE="mdps",
    PRIEST="healer", SHAMAN="healer",  MAGE="rdps",    WARLOCK="rdps", DRUID="healer",
}
local CLASS_DEFAULT_ROLE = CoreManager.CLASS_DEFAULT_ROLE  -- internal alias

CoreManager.ROLE_LABELS = { tank="Tank", healer="Healer", mdps="Melee", rdps="Ranged" }
CoreManager.ROLE_SHORT  = { tank="T",    healer="H",      mdps="M",     rdps="R" }
CoreManager.ROLE_COLORS = {
    tank   = { r=0.40, g=0.60, b=1.00 },
    healer = { r=0.20, g=0.90, b=0.30 },
    mdps   = { r=1.00, g=0.50, b=0.10 },
    rdps   = { r=1.00, g=0.85, b=0.10 },
}
CoreManager.ROLE_CYCLE = { "tank", "healer", "mdps", "rdps" }

-- Composition targets per raid format (T + H + M + R must sum to the size)
CoreManager.RAID_TARGETS = {
    [10] = { tank=2, healer=2, mdps=3, rdps=3 },
    [25] = { tank=2, healer=6, mdps=9, rdps=8 },
}

function CoreManager:GetRoleForClass(class)
    return self.CLASS_DEFAULT_ROLE[class] or "rdps"
end

function CoreManager:GetRaidSize(coreName)
    local core = self:GetCore(coreName)
    return (core and core.raidSize) or 25
end

function CoreManager:SetRaidSize(coreName, size)
    local core = self:GetCore(coreName)
    if core then core.raidSize = (size == 10) and 10 or 25 end
end

-- Penalty fallbacks when a core hasn't overridden them
local DEFAULT_PENALTIES = { LATE = 10, LEFT_EARLY = 10, NO_CONSUMES = 10 }

-- Loot config fallbacks
local DEFAULT_LOOT = {
    lootMethod       = "roll",  -- "roll" | "dkp" | "tmb"
    rollDuration     = 30,
    autoAnnounce     = true,
    wishlistOnlyMode = false,
    minAttendancePct = 0,
    attTiebreaker    = true,
    recvPenalty      = true,
    lootThreshold    = 3,
    disenchanter     = "",
    dkpMinBid        = 0,
    dkpBidTime       = 30,
}

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function CoreManager:Initialize()
    if not BRutus.db.cores          then BRutus.db.cores          = {} end
    if not BRutus.db.raidLeaderRanks then BRutus.db.raidLeaderRanks = {} end
    self:InitSync()
end

----------------------------------------------------------------------
-- Core CRUD
----------------------------------------------------------------------
function CoreManager:GetAll()
    return BRutus.db.cores or {}
end

function CoreManager:Exists(name)
    return name and name ~= "" and BRutus.db.cores[name] ~= nil
end

-- Creates a new core with all sub-tables initialized.
-- Returns true on success, or false + error message on failure.
function CoreManager:Create(name)
    if not name or name == "" then
        return false, L["Name cannot be empty."]
    end
    if BRutus.db.cores[name] then
        return false, L["A core with that name already exists."]
    end
    BRutus.db.cores[name] = {
        name       = name,
        lootMaster = {},
        attendance = { penalties = {} },
        points     = {
            mode         = "dkp",
            config       = {},
            standings    = {},
            log          = {},
            appliedOps   = {},
            appliedCount = 0,
        },
        members    = {},
    }
    return true
end

-- Renames a core and migrates all session/attendance data.
function CoreManager:Rename(oldName, newName)
    if not oldName or not BRutus.db.cores[oldName] then
        return false, L["Core not found."]
    end
    if not newName or newName == "" then
        return false, L["Name cannot be empty."]
    end
    if BRutus.db.cores[newName] then
        return false, L["A core with that name already exists."]
    end

    BRutus.db.cores[newName] = BRutus.db.cores[oldName]
    BRutus.db.cores[newName].name = newName
    BRutus.db.cores[oldName] = nil

    -- Update any existing raid sessions tagged with the old name
    local rtDB = BRutus.db.raidTracker
    if rtDB then
        for _, session in pairs(rtDB.sessions or {}) do
            if session.groupTag == oldName then
                session.groupTag = newName
            end
        end
        -- Move the attendance bucket
        local att = rtDB.attendance or {}
        if att[oldName] then
            att[newName] = att[oldName]
            att[oldName] = nil
        end
    end

    -- Update active tag if it was the renamed one
    if BRutus.RaidTracker and BRutus.RaidTracker.currentGroupTag == oldName then
        BRutus.RaidTracker:SetGroupTag(newName)
    end

    return true
end

-- Removes the core config entry (does NOT delete sessions or attendance data).
function CoreManager:Delete(name)
    if not name or name == "" then return false end
    BRutus.db.cores[name] = nil
    return true
end

----------------------------------------------------------------------
-- Active core
----------------------------------------------------------------------
function CoreManager:GetActiveName()
    if BRutus.RaidTracker then
        return BRutus.RaidTracker:GetCurrentGroup()
    end
    return (BRutus.db.raidTracker and BRutus.db.raidTracker.currentGroupTag) or ""
end

-- Returns the core table for `name` (or the active core when name is nil).
-- Auto-creates the entry when name is non-empty and doesn't exist yet,
-- so callers never have to guard against nil.
function CoreManager:GetCore(name)
    if name == nil then name = self:GetActiveName() end
    if not name or name == "" then return nil end
    if not BRutus.db.cores[name] then
        self:Create(name)
    end
    return BRutus.db.cores[name]
end

-- Alphabetically sorted list of named core names.
function CoreManager:GetSortedNames()
    local names = {}
    for name in pairs(BRutus.db.cores or {}) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

----------------------------------------------------------------------
-- Loot master config — per-core with cascade: core → global DB → defaults
----------------------------------------------------------------------
local function lmField(core, key)
    -- 1. Per-core override
    if core and core.lootMaster and core.lootMaster[key] ~= nil then
        return core.lootMaster[key]
    end
    -- 2. Legacy global DB (keeps backward compat for guilds that already
    --    configured the global lootMaster settings before cores existed)
    local gdb = BRutus.db and BRutus.db.lootMaster
    if gdb and gdb[key] ~= nil then return gdb[key] end
    -- 3. Hard-coded default
    return DEFAULT_LOOT[key]
end

function CoreManager:GetLootConfig(coreName)
    local core = self:GetCore(coreName)
    return {
        lootMethod       = lmField(core, "lootMethod"),
        rollDuration     = lmField(core, "rollDuration"),
        autoAnnounce     = lmField(core, "autoAnnounce"),
        wishlistOnlyMode = lmField(core, "wishlistOnlyMode"),
        minAttendancePct = lmField(core, "minAttendancePct"),
        attTiebreaker    = lmField(core, "attTiebreaker"),
        recvPenalty      = lmField(core, "recvPenalty"),
        lootThreshold    = lmField(core, "lootThreshold"),
        disenchanter     = lmField(core, "disenchanter"),
        dkpMinBid        = lmField(core, "dkpMinBid"),
        dkpBidTime       = lmField(core, "dkpBidTime"),
    }
end

function CoreManager:SetLootConfigKey(key, value, coreName)
    local core = self:GetCore(coreName)
    if core then
        if not core.lootMaster then core.lootMaster = {} end
        core.lootMaster[key] = value
    else
        -- Ungrouped: persist to the legacy global lootMaster
        if BRutus.db.lootMaster then BRutus.db.lootMaster[key] = value end
    end
end

----------------------------------------------------------------------
-- TMB (That's My BiS) priority list — stored per core
----------------------------------------------------------------------
function CoreManager:GetTMBList(coreName)
    local core = self:GetCore(coreName)
    if not core then return {} end
    if not core.lootMaster then core.lootMaster = {} end
    if not core.lootMaster.tmbList then core.lootMaster.tmbList = {} end
    return core.lootMaster.tmbList
end

function CoreManager:SetTMBList(list, coreName)
    local core = self:GetCore(coreName)
    if not core then return end
    if not core.lootMaster then core.lootMaster = {} end
    core.lootMaster.tmbList = list or {}
end

-- Parses a CSV paste from TMB export: one entry per line, "player,item,priority"
-- Lines starting with # are treated as comments and skipped.
function CoreManager:ParseTMBImport(text)
    local list = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = strtrim(line)
        if line ~= "" and not line:match("^#") and not line:match("^[Cc]haracter") then
            local player, item, prio = line:match("^([^,\t]+)[,\t]([^,\t]+)[,\t]?(%d*)")
            if player and item then
                list[#list + 1] = {
                    player   = strtrim(player),
                    item     = strtrim(item),
                    priority = tonumber(prio) or 1,
                }
            end
        end
    end
    return list
end

----------------------------------------------------------------------
-- Returns the awardHistory table for the active (or named) core.
function CoreManager:GetAwardHistory(coreName)
    local core = self:GetCore(coreName)
    if core then
        if not core.lootMaster then core.lootMaster = {} end
        if not core.lootMaster.awardHistory then core.lootMaster.awardHistory = {} end
        return core.lootMaster.awardHistory
    end
    -- Ungrouped fallback
    if BRutus.db.lootMaster then
        if not BRutus.db.lootMaster.awardHistory then
            BRutus.db.lootMaster.awardHistory = {}
        end
        return BRutus.db.lootMaster.awardHistory
    end
    return {}
end

----------------------------------------------------------------------
-- Attendance penalties — per-core with fallback to defaults
----------------------------------------------------------------------
function CoreManager:GetPenalties(coreName)
    local core = self:GetCore(coreName)
    local p = core and core.attendance and core.attendance.penalties or {}
    return {
        LATE        = (p.LATE        ~= nil) and p.LATE        or DEFAULT_PENALTIES.LATE,
        LEFT_EARLY  = (p.LEFT_EARLY  ~= nil) and p.LEFT_EARLY  or DEFAULT_PENALTIES.LEFT_EARLY,
        NO_CONSUMES = (p.NO_CONSUMES ~= nil) and p.NO_CONSUMES or DEFAULT_PENALTIES.NO_CONSUMES,
    }
end

function CoreManager:SetPenalty(key, value, coreName)
    local core = self:GetCore(coreName)
    if not core then return end
    if not core.attendance           then core.attendance           = {} end
    if not core.attendance.penalties then core.attendance.penalties = {} end
    core.attendance.penalties[key] = value
end

----------------------------------------------------------------------
-- Points/DKP — per-core pool, with fallback to global db.points
-- for the "ungrouped" (empty-tag) pseudo-core.
----------------------------------------------------------------------
function CoreManager:GetPointsDB(coreName)
    if coreName == nil then coreName = self:GetActiveName() end
    if not coreName or coreName == "" then
        return BRutus.db.points
    end

    local core = self:GetCore(coreName)
    if not core then return BRutus.db.points end

    if not core.points then
        core.points = {
            mode = "dkp", config = {}, standings = {},
            log = {}, appliedOps = {}, appliedCount = 0,
        }
    end
    -- Ensure all sub-keys exist (safe migration for older entries)
    local p = core.points
    if not p.mode         then p.mode         = "dkp"  end
    if not p.config       then p.config        = {}     end
    if not p.standings    then p.standings     = {}     end
    if not p.log          then p.log           = {}     end
    if not p.appliedOps   then p.appliedOps    = {}     end
    if p.appliedCount == nil then p.appliedCount = 0    end
    return p
end

----------------------------------------------------------------------
-- Raid leader rank configuration
-- Officers always have access; this lets non-officer ranks manage cores.
----------------------------------------------------------------------
function CoreManager:GetRaidLeaderRanks()
    if not BRutus.db.raidLeaderRanks then BRutus.db.raidLeaderRanks = {} end
    return BRutus.db.raidLeaderRanks
end

function CoreManager:SetRaidLeaderRank(rankName, enabled)
    local t = self:GetRaidLeaderRanks()
    if enabled then t[rankName] = true else t[rankName] = nil end
end

function CoreManager:IsRaidLeader()
    if BRutus:IsOfficer() then return true end
    local ranks = self:GetRaidLeaderRanks()
    local myName = UnitName("player")
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank = GetGuildRosterInfo(i)
        if name and strsplit("-", name) == myName then
            return ranks[rank] == true
        end
    end
    return false
end

----------------------------------------------------------------------
-- Core roster — rich member records { name, class, role, note }
----------------------------------------------------------------------
function CoreManager:GetMembers(coreName)
    local core = self:GetCore(coreName)
    if not core then return {} end
    if not core.members then core.members = {} end
    return core.members
end

-- Adds or updates a member in one core; removes them from all other cores
-- so each player belongs to at most one core at a time.
function CoreManager:AddMember(playerKey, info, coreName)
    -- Remove from any other core
    for _, c in pairs(BRutus.db.cores or {}) do
        if c.members then c.members[playerKey] = nil end
    end
    local core = self:GetCore(coreName)
    if not core then return false, L["Core not found."] end
    if not core.members then core.members = {} end
    core.members[playerKey] = {
        name  = info.name  or playerKey,
        class = info.class or "WARRIOR",
        role  = info.role  or "rdps",
        note  = info.note  or "",
    }
    return true
end

function CoreManager:RemoveMember(playerKey, coreName)
    local core = self:GetCore(coreName)
    if core and core.members then core.members[playerKey] = nil end
end

function CoreManager:GetMemberCore(playerKey)
    for name, core in pairs(BRutus.db.cores or {}) do
        if core.members and core.members[playerKey] then
            return name
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Sign-up queue — player applications to join a core
----------------------------------------------------------------------
function CoreManager:GetSignups(coreName)
    local core = self:GetCore(coreName)
    if not core then return {} end
    if not core.signups then core.signups = {} end
    return core.signups
end

function CoreManager:AddSignup(playerKey, info, coreName)
    local core = self:GetCore(coreName)
    if not core then return false, L["Core not found."] end
    if not core.signups then core.signups = {} end
    core.signups[playerKey] = {
        name  = info.name  or playerKey,
        class = info.class or "WARRIOR",
        role  = info.role  or "rdps",
        note  = info.note  or "",
        ts    = info.ts    or time(),
    }
    return true
end

-- Accept moves the signup into the roster; decline just removes it.
function CoreManager:AcceptSignup(playerKey, coreName)
    local core = self:GetCore(coreName)
    if not core then return false end
    local su = core.signups and core.signups[playerKey]
    if not su then return false end
    self:AddMember(playerKey, su, coreName)
    core.signups[playerKey] = nil
    return true
end

function CoreManager:DeclineSignup(playerKey, coreName)
    local core = self:GetCore(coreName)
    if core and core.signups then core.signups[playerKey] = nil end
end

----------------------------------------------------------------------
-- TBC composition analysis
----------------------------------------------------------------------
local CLASS_BUFFS_MAP = {
    WARRIOR = { "Battle Shout", "Demo Shout", "Commanding Shout" },
    PALADIN = { "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom", "Auras" },
    DRUID   = { "Mark of the Wild", "Innervate", "Rebirth" },
    PRIEST  = { "Power Word: Fortitude", "Shadow Protection" },
    MAGE    = { "Arcane Brilliance" },
    WARLOCK = { "Blood Pact" },
    HUNTER  = { "Trueshot Aura" },
    SHAMAN  = { "Windfury Totem", "Mana Spring", "Strength of Earth", "Grace of Air" },
    ROGUE   = {},
}

local IMPORTANT_BUFFS_LIST = {
    { name = "Battle Shout",          src = "WARRIOR" },
    { name = "Blessing of Kings",     src = "PALADIN" },
    { name = "Blessing of Might",     src = "PALADIN" },
    { name = "Mark of the Wild",      src = "DRUID"   },
    { name = "Power Word: Fortitude", src = "PRIEST"  },
    { name = "Arcane Brilliance",     src = "MAGE"    },
    { name = "Blood Pact",            src = "WARLOCK" },
    { name = "Trueshot Aura",         src = "HUNTER"  },
    { name = "Windfury Totem",        src = "SHAMAN"  },
    { name = "Innervate",             src = "DRUID"   },
    { name = "Auras",                 src = "PALADIN" },
}

function CoreManager:GetComposition(coreName)
    local members = self:GetMembers(coreName)
    local classCount  = {}
    local roleCounts  = { tank=0, healer=0, mdps=0, rdps=0 }
    local classPresent = {}
    local total = 0

    for _, m in pairs(members) do
        total = total + 1
        local cls = (m.class or "WARRIOR"):upper()
        classCount[cls] = (classCount[cls] or 0) + 1
        classPresent[cls] = true
        local role = m.role or "rdps"
        if roleCounts[role] ~= nil then roleCounts[role] = roleCounts[role] + 1 end
    end

    local coveredBuffs = {}
    for cls in pairs(classPresent) do
        for _, b in ipairs(CLASS_BUFFS_MAP[cls] or {}) do
            coveredBuffs[b] = true
        end
    end

    local buffStatus = {}
    for _, entry in ipairs(IMPORTANT_BUFFS_LIST) do
        buffStatus[#buffStatus + 1] = {
            name    = entry.name,
            covered = coveredBuffs[entry.name] == true,
            source  = entry.src,
        }
    end

    return {
        total      = total,
        classCount = classCount,
        roleCounts = roleCounts,
        buffStatus = buffStatus,
    }
end

----------------------------------------------------------------------
-- SyncService bridge — sign-ups and roster sync between officers
----------------------------------------------------------------------
function CoreManager:BroadcastSignup(coreName, note)
    local playerName = UnitName("player")
    local _, cls     = UnitClass("player")
    local playerKey  = BRutus:GetPlayerKey(playerName, GetRealmName())
    local info = {
        name  = playerName,
        class = cls or "WARRIOR",
        role  = CLASS_DEFAULT_ROLE[cls] or "rdps",
        note  = note or "",
        ts    = time(),
    }
    -- Store locally first so the player sees "Pending" immediately
    self:AddSignup(playerKey, info, coreName)
    -- Broadcast to officers so they can persist it on their end
    if BRutus.SyncService then
        BRutus.SyncService:Publish("core.signup", "apply", {
            coreName  = coreName,
            playerKey = playerKey,
            info      = info,
        })
    end
end

function CoreManager:BroadcastRoster(coreName)
    if not BRutus.SyncService then return end
    BRutus.SyncService:Publish("core.roster", "update", {
        coreName = coreName,
        members  = self:GetMembers(coreName),
    })
end

function CoreManager:InitSync()
    if not BRutus.SyncService then return end

    -- Any player may broadcast a signup; officers store it.
    BRutus.SyncService:On("core.signup", function(env, sender)
        local d = env.data
        if not d or not d.coreName or not d.playerKey then return end
        if not BRutus:IsOfficer() then return end
        self:AddSignup(d.playerKey, d.info or {}, d.coreName)
        if BRutus.coresPanelRefresh then BRutus.coresPanelRefresh() end
    end)

    -- Officers broadcast roster updates to each other.
    BRutus.SyncService:On("core.roster", function(env, sender)
        local d = env.data
        if not d or not d.coreName or not d.members then return end
        if not BRutus:IsOfficerByName(sender) then return end
        local core = self:GetCore(d.coreName)
        if core then core.members = d.members end
        if BRutus.coresPanelRefresh then BRutus.coresPanelRefresh() end
    end)
end
