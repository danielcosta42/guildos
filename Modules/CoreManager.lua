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

-- The role a class starts in. TBC's put the tanks and healers first; WoW: Forever's put damage
-- first, as the site's Forever roles do, because tank-first was wrong there (issue #92).
CoreManager.CLASS_DEFAULT_ROLE = BRutus.Client.isAnniversary and {
    WARRIOR="tank",  PALADIN="healer", HUNTER="rdps",  ROGUE="mdps",
    PRIEST="healer", SHAMAN="healer",  MAGE="rdps",    WARLOCK="rdps", DRUID="healer",
} or {
    WARRIOR="mdps",  PALADIN="mdps",   HUNTER="rdps",  ROGUE="mdps",
    PRIEST="rdps",   SHAMAN="mdps",    MAGE="rdps",    WARLOCK="rdps", DRUID="mdps",
}

CoreManager.ROLE_LABELS = { tank=L["Tank"], healer=L["Healer"], mdps=L["Melee"], rdps=L["Ranged"] }
CoreManager.ROLE_SHORT  = { tank="T",    healer="H",      mdps="M",     rdps="R" }
CoreManager.ROLE_COLORS = {
    tank   = { r=0.40, g=0.60, b=1.00 },
    healer = { r=0.20, g=0.90, b=0.30 },
    mdps   = { r=1.00, g=0.50, b=0.10 },
    rdps   = { r=1.00, g=0.85, b=0.10 },
}
CoreManager.ROLE_CYCLE = { "tank", "healer", "mdps", "rdps" }

-- The roles each class can play, the same in both games: the site's lists, TBC's specs read as
-- roles and WoW: Forever's roles as they are. A sign-up picks one of these (issue #94).
CoreManager.CLASS_ROLES = {
    WARRIOR = { tank=true, mdps=true },
    PALADIN = { tank=true, healer=true, mdps=true },
    HUNTER  = { rdps=true },
    ROGUE   = { mdps=true },
    PRIEST  = { healer=true, rdps=true },
    SHAMAN  = { healer=true, mdps=true, rdps=true },
    MAGE    = { rdps=true },
    WARLOCK = { rdps=true },
    DRUID   = { tank=true, healer=true, mdps=true, rdps=true },
}

-- A role as somebody types it ("/gos signup Main healer"): its label or its key, any case.
CoreManager.ROLE_WORDS = { tank="tank", healer="healer", heal="healer", melee="mdps", mdps="mdps",
                           ranged="rdps", rdps="rdps" }

-- The roles a class can play, in ROLE_CYCLE order.
function CoreManager:RolesFor(cls)
    local can, out = self.CLASS_ROLES[cls] or {}, {}
    for _, r in ipairs(self.ROLE_CYCLE) do
        if can[r] then out[#out + 1] = r end
    end
    return out
end

-- `role` when the class can play it, else the class's own: a sign-up never carries a role its
-- class cannot fill (issue #94).
function CoreManager:RoleFor(cls, role)
    local can = self.CLASS_ROLES[cls]
    if can and can[role] then return role end
    return self.CLASS_DEFAULT_ROLE[cls] or "rdps"
end

-- Composition targets per raid format (T + H + M + R must sum to the size). TBC's raids are
-- 10 and 25 players; WoW: Forever's are 10 and 20 a tier, and Onyxia at 40 (issue #89).
CoreManager.RAID_TARGETS = {
    [10] = { tank=2, healer=2,  mdps=3,  rdps=3 },
    [20] = { tank=2, healer=5,  mdps=6,  rdps=7 },
    [25] = { tank=2, healer=6,  mdps=9,  rdps=8 },
    [40] = { tank=4, healer=10, mdps=13, rdps=13 },
}

-- The formats this guild's game has, and the one a new core starts with: each Forever tier's
-- main raid is the 20-player one.
local function sizesOfThisGame()
    if BRutus.Client.isAnniversary then return { 10, 25 }, BRutus.Client.defaultRaidSize end
    return { 10, 20, 40 }, BRutus.Client.defaultRaidSize
end

function CoreManager:RaidSizes()
    return (sizesOfThisGame())
end

local function isSizeOfThisGame(size)
    for _, s in ipairs((sizesOfThisGame())) do
        if s == size then return true end
    end
    return false
end

-- The next format after `size`, round the list. A size this game lacks counts as the default,
-- as GetRaidSize reads it, so a saved 25 on Forever (shown as 20) moves on to 40.
function CoreManager:NextRaidSize(size)
    local sizes, default = sizesOfThisGame()
    if not isSizeOfThisGame(size) then size = default end
    for i, s in ipairs(sizes) do
        if s == size then return sizes[(i % #sizes) + 1] end
    end
end

function CoreManager:RaidTargets(size)
    local _, default = sizesOfThisGame()
    return self.RAID_TARGETS[isSizeOfThisGame(size) and size or default]
end

function CoreManager:GetRoleForClass(class)
    return self.CLASS_DEFAULT_ROLE[class] or "rdps"
end

-- A size this game lacks (a 25 saved by a version that only knew TBC) reads as the default.
function CoreManager:GetRaidSize(coreName)
    local core = self:GetCore(coreName)
    local size = core and core.raidSize
    if isSizeOfThisGame(size) then return size end
    local _, default = sizesOfThisGame()
    return default
end

function CoreManager:SetRaidSize(coreName, size)
    local core = self:GetCore(coreName)
    if not core then return end
    local _, default = sizesOfThisGame()
    core.raidSize = isSizeOfThisGame(size) and size or default
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
    -- And the raid in progress, and an officer's pick kept for it (issue #99).
    local RT = BRutus.RaidTracker
    local raid = RT and RT.currentRaid
    if raid and raid.groupTag == oldName then raid.groupTag = newName end
    if RT and RT.coreAnnounced == oldName then RT.coreAnnounced = newName end
    if RT and RT.gracePick == oldName then RT.gracePick = newName end
    local pick = rtDB and rtDB.corePick
    if type(pick) == "table" and pick.tag == oldName then pick.tag = newName end

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

-- The core a raid group is, by roster (issue #99): the one with the most of the group on it, an
-- alt counting as their main, provided that is at least two people and at least half the group
-- and no other core has as many. Nil otherwise, and the active core stands.
-- Returns name, how many of the group are on its roster, and the group's size.
function CoreManager:CoreForGroup(players)
    local altLinks = (BRutus.db and BRutus.db.altLinks) or {}
    local size = 0
    for _ in pairs(players or {}) do size = size + 1 end
    local counts, best, bestCount = {}, nil, 0
    for name, core in pairs((BRutus.db and BRutus.db.cores) or {}) do
        local members = type(core) == "table" and core.members
        if type(members) == "table" then
            local count = 0
            for key in pairs(players or {}) do
                if members[key] or members[altLinks[key]] then count = count + 1 end
            end
            counts[name] = count
            if count > bestCount then best, bestCount = name, count end
        end
    end
    if not best or bestCount < 2 or bestCount * 2 < size then return nil end
    for name, count in pairs(counts) do
        if count == bestCount and name ~= best then return nil end   -- a tie: no roster is the raid
    end
    return best, bestCount, size
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
-- Attendance penalties: a core's own weight, else the guild's, else the default. The guild's
-- (`coreName` "", kept in db.attendancePenalties) score every raid outside a core and every
-- core that set none of its own (issue #55): before them a guild without cores could not
-- change a thing.
----------------------------------------------------------------------
function CoreManager:GetPenalties(coreName)
    local core = self:GetCore(coreName)
    local own = core and core.attendance and core.attendance.penalties or {}
    local guild = BRutus.db.attendancePenalties or {}
    local out = {}
    for key, default in pairs(DEFAULT_PENALTIES) do
        if own[key] ~= nil then out[key] = own[key]
        elseif guild[key] ~= nil then out[key] = guild[key]
        else out[key] = default end
    end
    return out
end

-- A weight is a whole number of points from 0 (off) to 100.
function CoreManager:SetPenalty(key, value, coreName)
    if DEFAULT_PENALTIES[key] == nil then return end
    value = math.max(0, math.min(100, math.floor(tonumber(value) or 0)))
    if coreName == "" then
        BRutus.db.attendancePenalties = BRutus.db.attendancePenalties or {}
        BRutus.db.attendancePenalties[key] = value
        return
    end
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
    local myName = BRutus.Compat.PlayerName()
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

-- TBC's raid buffs. WoW: Forever lists none, as the site's Forever catalogue does on purpose,
-- and the core screen leaves the section out (issue #92).
local IMPORTANT_BUFFS_LIST = not BRutus.Client.isAnniversary and {} or {
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
-- `role` is the one picked in the sign-up window; nil, or one the class cannot play, is the
-- class's own (issue #94).
function CoreManager:BroadcastSignup(coreName, note, role)
    local playerName = BRutus.Compat.PlayerName()
    local _, cls     = UnitClass("player")
    local playerKey  = BRutus:GetPlayerKey(playerName, GetRealmName())
    local info = {
        name  = playerName,
        class = cls or "WARRIOR",
        role  = self:RoleFor(cls, role),
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
    -- A sign-up is filed under who sent it, never under a key the payload names: that one carries
    -- the sender's realm on Forever (#97), and trusting it let anybody sign somebody else up.
    BRutus.SyncService:On("core.signup", function(env, sender)
        local d = env.data
        if not d or not d.coreName or type(sender) ~= "string" or sender == "" then return end
        if not BRutus:IsOfficer() then return end
        local short = sender:match("^([^-]+)") or sender
        local playerKey = BRutus:GetPlayerKey(short, sender:match("-(.+)$"))
        local info = type(d.info) == "table" and d.info or {}
        info.name = short
        -- The class the guild roster (the server's) gives the sender, else one the payload names
        -- that exists, else warrior; the role is then one that class can play (#94).
        local rec = BRutus:GetMemberRecord(short, sender:match("-(.+)$"))
        local cls = rec and rec.class
        if not self.CLASS_ROLES[cls] then cls = self.CLASS_ROLES[info.class] and info.class or "WARRIOR" end
        info.class = cls
        info.role = self:RoleFor(cls, info.role)
        self:AddSignup(playerKey, info, d.coreName)
        if BRutus.coresPanelRefresh then BRutus.coresPanelRefresh() end
    end)

    -- Officers broadcast roster updates to each other.
    BRutus.SyncService:On("core.roster", function(env, sender)
        local d = env.data
        if not d or not d.coreName or not d.members then return end
        if not BRutus:IsOfficerByName(sender) then return end
        local core = self:GetCore(d.coreName)
        if core then core.members = BRutus:LocalizeMemberTable(d.members) end   -- this client's keys (#97)
        if BRutus.coresPanelRefresh then BRutus.coresPanelRefresh() end
    end)
end
