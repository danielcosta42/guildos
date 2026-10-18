----------------------------------------------------------------------
-- Guild OS - Core Manager
-- Manages multiple raid cores, each with independent loot rules,
-- attendance penalties, and a DKP/points pool.
--
-- The "active core" is always the current RaidTracker groupTag.
-- CoreManager enriches that existing concept with per-core configs.
----------------------------------------------------------------------
local CoreManager = {}
GuildOS.CoreManager = CoreManager
local L = GuildOS.L

-- The role a class starts in. TBC's put the tanks and healers first; WoW: Forever's put damage
-- first, as the site's Forever roles do, because tank-first was wrong there (issue #92).
CoreManager.CLASS_DEFAULT_ROLE = GuildOS.Client.isAnniversary and {
    WARRIOR="tank",  PALADIN="healer", HUNTER="rdps",  ROGUE="mdps",
    PRIEST="healer", SHAMAN="healer",  MAGE="rdps",    WARLOCK="rdps", DRUID="healer",
} or {
    WARRIOR="mdps",  PALADIN="mdps",   HUNTER="rdps",  ROGUE="mdps",
    PRIEST="rdps",   SHAMAN="mdps",    MAGE="rdps",    WARLOCK="rdps", DRUID="mdps",
    -- Retail's four (ADR-0026), damage first like the rest.
    DEATHKNIGHT="mdps", DEMONHUNTER="mdps", MONK="mdps", EVOKER="rdps",
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
    -- Retail's (ADR-0026). The Demon Hunter's Devourer casts; the Hunter's Survival is melee there.
    DEATHKNIGHT = { tank=true, mdps=true },
    DEMONHUNTER = { tank=true, mdps=true, rdps=true },
    MONK        = { tank=true, healer=true, mdps=true },
    EVOKER      = { healer=true, rdps=true },
}
if GuildOS.Client.isRetail then CoreManager.CLASS_ROLES.HUNTER = { mdps=true, rdps=true } end

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
    [30] = { tank=2, healer=6,  mdps=11, rdps=11 },   -- retail's flex at its top (ADR-0026)
    [40] = { tank=4, healer=10, mdps=13, rdps=13 },
}

-- The formats this guild's game has, and the one a new core starts with: each Forever tier's
-- main raid is the 20-player one.
local function sizesOfThisGame()
    if GuildOS.Client.isAnniversary then return { 10, 25 }, GuildOS.Client.defaultRaidSize end
    if GuildOS.Client.isRetail then return GuildOS.Client.raidSizes, GuildOS.Client.defaultRaidSize end
    return { 10, 20, 40 }, GuildOS.Client.defaultRaidSize
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
    if not GuildOS.db.cores          then GuildOS.db.cores          = {} end
    if not GuildOS.db.raidLeaderRanks then GuildOS.db.raidLeaderRanks = {} end
    self:InitSync()
    GuildOS:SafeCall(self.ImportInbox, self)   -- the Discord's cores (#135)
end

----------------------------------------------------------------------
-- Core CRUD
----------------------------------------------------------------------
function CoreManager:GetAll()
    return GuildOS.db.cores or {}
end

function CoreManager:Exists(name)
    return name and name ~= "" and GuildOS.db.cores[name] ~= nil
end

-- Creates a new core with all sub-tables initialized.
-- Returns true on success, or false + error message on failure.
function CoreManager:Create(name)
    if not name or name == "" then
        return false, L["Name cannot be empty."]
    end
    if GuildOS.db.cores[name] then
        return false, L["A core with that name already exists."]
    end
    GuildOS.db.cores[name] = {
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
    if not oldName or not GuildOS.db.cores[oldName] then
        return false, L["Core not found."]
    end
    if not newName or newName == "" then
        return false, L["Name cannot be empty."]
    end
    if GuildOS.db.cores[newName] then
        return false, L["A core with that name already exists."]
    end

    GuildOS.db.cores[newName] = GuildOS.db.cores[oldName]
    GuildOS.db.cores[newName].name = newName
    GuildOS.db.cores[oldName] = nil

    -- Update any existing raid sessions tagged with the old name
    local rtDB = GuildOS.db.raidTracker
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
    if GuildOS.RaidTracker and GuildOS.RaidTracker.currentGroupTag == oldName then
        GuildOS.RaidTracker:SetGroupTag(newName)
    end
    -- And the raid in progress, and an officer's pick kept for it (issue #99).
    local RT = GuildOS.RaidTracker
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
    GuildOS.db.cores[name] = nil
    -- The active core deleted is no longer active, nor the raid's, nor an officer's pick: left set,
    -- the next read of it, or a /reload inside the raid, would make it again, empty (#138).
    local RT, rtDB = GuildOS.RaidTracker, GuildOS.db.raidTracker
    if self:GetActiveName() == name then
        if RT then
            RT:SetGroupTag("")
        elseif rtDB then
            rtDB.currentGroupTag = ""
        end
    end
    if RT and RT.currentRaid and RT.currentRaid.groupTag == name then RT.currentRaid.groupTag = "" end
    if RT and RT.coreAnnounced == name then RT.coreAnnounced = nil end
    if RT and RT.gracePick == name then RT.gracePick = nil end
    if rtDB and type(rtDB.corePick) == "table" and rtDB.corePick.tag == name then rtDB.corePick = nil end
    return true
end

----------------------------------------------------------------------
-- Active core
----------------------------------------------------------------------
function CoreManager:GetActiveName()
    if GuildOS.RaidTracker then
        return GuildOS.RaidTracker:GetCurrentGroup()
    end
    return (GuildOS.db.raidTracker and GuildOS.db.raidTracker.currentGroupTag) or ""
end

-- Whether core `a` is the group's before core `b` (issue #132). A raider can be on several cores,
-- so the 40's roster holds the 10's people: one whose format holds the raid comes first, the
-- smaller format of two that do, then the one with more of the group on it.
local function ranksBefore(a, b, raidSize)
    local aFits, bFits = a.raidSize >= raidSize, b.raidSize >= raidSize
    if aFits ~= bFits then return aFits end
    if aFits and a.raidSize ~= b.raidSize then return a.raidSize < b.raidSize end
    return a.count > b.count
end

-- The core a raid group is, by roster (issue #99): of the cores with at least two people and at
-- least half the group on them (an alt counting as their main), the one that ranks first, unless
-- another ranks as high. Nil otherwise, and the active core stands.
-- `instanceSize` is the raid's maxPlayers (a session's `size`, #90): when it is one of this game's
-- formats it is the raid's format, so a 20's instance is the 20 core's however few have come in.
-- Otherwise (none, or a size no core plans for) the group's own size stands in for it.
-- Returns name, how many of the group are on its roster, and the group's size.
function CoreManager:CoreForGroup(players, instanceSize)
    local altLinks = (GuildOS.db and GuildOS.db.altLinks) or {}
    local size = 0
    for _ in pairs(players or {}) do size = size + 1 end
    local candidates = {}
    for name, core in pairs((GuildOS.db and GuildOS.db.cores) or {}) do
        local members = type(core) == "table" and core.members
        if type(members) == "table" then
            local count = 0
            for key in pairs(players or {}) do
                if members[key] or members[altLinks[key]] then count = count + 1 end
            end
            if count >= 2 and count * 2 >= size then
                candidates[#candidates + 1] = { name = name, count = count, raidSize = self:GetRaidSize(name) }
            end
        end
    end
    local raidSize = isSizeOfThisGame(instanceSize) and instanceSize or size
    local best
    for _, c in ipairs(candidates) do
        if not best or ranksBefore(c, best, raidSize) then best = c end
    end
    if not best then return nil end
    for _, c in ipairs(candidates) do
        if c ~= best and not ranksBefore(best, c, raidSize) then return nil end   -- a tie: no roster is the raid
    end
    return best.name, best.count, size
end

-- Returns the core table for `name` (or the active core when name is nil).
-- Auto-creates the entry when name is non-empty and doesn't exist yet,
-- so callers never have to guard against nil.
function CoreManager:GetCore(name)
    if name == nil then name = self:GetActiveName() end
    if not name or name == "" then return nil end
    if not GuildOS.db.cores[name] then
        self:Create(name)
    end
    return GuildOS.db.cores[name]
end

-- Alphabetically sorted list of named core names.
function CoreManager:GetSortedNames()
    local names = {}
    for name in pairs(GuildOS.db.cores or {}) do
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
    local gdb = GuildOS.db and GuildOS.db.lootMaster
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
        if GuildOS.db.lootMaster then GuildOS.db.lootMaster[key] = value end
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
    if GuildOS.db.lootMaster then
        if not GuildOS.db.lootMaster.awardHistory then
            GuildOS.db.lootMaster.awardHistory = {}
        end
        return GuildOS.db.lootMaster.awardHistory
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
    local guild = GuildOS.db.attendancePenalties or {}
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
        GuildOS.db.attendancePenalties = GuildOS.db.attendancePenalties or {}
        GuildOS.db.attendancePenalties[key] = value
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
        return GuildOS.db.points
    end

    local core = self:GetCore(coreName)
    if not core then return GuildOS.db.points end

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
    if not GuildOS.db.raidLeaderRanks then GuildOS.db.raidLeaderRanks = {} end
    return GuildOS.db.raidLeaderRanks
end

function CoreManager:SetRaidLeaderRank(rankName, enabled)
    local t = self:GetRaidLeaderRanks()
    if enabled then t[rankName] = true else t[rankName] = nil end
end

function CoreManager:IsRaidLeader()
    if GuildOS:IsOfficer() then return true end
    local ranks = self:GetRaidLeaderRanks()
    local myName = GuildOS.Compat.PlayerName()
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

-- Adds or updates a member in one core. A raider may be on several cores at once, one per
-- format (issue #132), so the others are left as they are. `src` is where the record came from,
-- "discord" for the Discord's import (#135), and an edit keeps the one it had.
function CoreManager:AddMember(playerKey, info, coreName)
    local core = self:GetCore(coreName)
    if not core then return false, L["Core not found."] end
    if not core.members then core.members = {} end
    local held = core.members[playerKey]
    core.members[playerKey] = {
        name  = info.name  or playerKey,
        class = info.class or "WARRIOR",
        role  = info.role  or "rdps",
        note  = info.note  or "",
        src   = info.src or (type(held) == "table" and held.src or nil),
    }
    return true
end

function CoreManager:RemoveMember(playerKey, coreName)
    local core = self:GetCore(coreName)
    if core and core.members then core.members[playerKey] = nil end
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
local IMPORTANT_BUFFS_LIST = not GuildOS.Client.isAnniversary and {} or {
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
    local playerName = GuildOS.Compat.PlayerName()
    local _, cls     = UnitClass("player")
    local playerKey  = GuildOS:GetPlayerKey(playerName, GetRealmName())
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
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("core.signup", "apply", {
            coreName  = coreName,
            playerKey = playerKey,
            info      = info,
        })
    end
end

----------------------------------------------------------------------
-- The Discord's cores (issue #135; guildos-web specs/041)
--
-- The Discord owns who is on a core. The site sends a guild's cores as a GOSCORE1 the companion
-- leaves in Inbox.lua: whoever came from it joins, and goes once they leave it there; whoever
-- an officer put on a core here is never touched.
----------------------------------------------------------------------
-- UTF-8 Latin letters with a mark, as their bare letter: what the site's NFD leaves once the marks
-- are dropped, generated from it for U+00C0 to U+024F. Anything else outside a-z and 0-9 is a
-- hyphen there and here ("Łódź" is "odz" on both).
local BARE = {}
for bare, marked in pairs({
    a = "ÀÁÂÃÄÅàáâãäåĀāĂăĄąǍǎǞǟǠǡǺǻȀȁȂȃȦȧ", c = "ÇçĆćĈĉĊċČč", d = "Ďď", e = "ÈÉÊËèéêëĒēĔĕĖėĘęĚěȄȅȆȇȨȩ",
    g = "ĜĝĞğĠġĢģǦǧǴǵ", h = "ĤĥȞȟ", i = "ÌÍÎÏìíîïĨĩĪīĬĭĮįİǏǐȈȉȊȋ", j = "Ĵĵǰ", k = "ĶķǨǩ", l = "ĹĺĻļĽľ",
    n = "ÑñŃńŅņŇňǸǹ", o = "ÒÓÔÕÖòóôõöŌōŎŏŐőƠơǑǒǪǫǬǭȌȍȎȏȪȫȬȭȮȯȰȱ", r = "ŔŕŖŗŘřȐȑȒȓ", s = "ŚśŜŝŞşŠšȘș",
    t = "ŢţŤťȚț", u = "ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲųƯưǓǔǕǖǗǘǙǚǛǜȔȕȖȗ", w = "Ŵŵ", y = "ÝýÿŶŷŸȲȳ", z = "ŹźŻżŽž",
}) do
    for ch in marked:gmatch("[\192-\223][\128-\191]") do BARE[ch] = bare end
end

-- A core's name as the site's `slugOf` reduces it: a Discord core's tag, when the names are one
-- ("Núcleo Alfa!" is "nucleo-alfa").
function CoreManager.Slug(name)
    local s = tostring(name or ""):gsub("[\192-\223][\128-\191]", BARE):lower()
    s = s:gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return s:sub(1, 40)
end

local SITE_ROLES = { tank = true, healer = true, mdps = true, rdps = true }

-- This game's core for a Discord core: the one already linked to its tag; else the one whose name
-- reduces to the tag, the one named as on the Discord when two do. Else one made now, named as on
-- the Discord, or by the tag when the name does not reduce to it (a name the Discord reused is
-- "alfa-2"), so its nights count on the site.
local function coreFor(self, c)
    local held
    for _, name in ipairs(self:GetSortedNames()) do
        if GuildOS.db.cores[name].discordTag == c.tag then
            if name == c.name then return name, false end
            held = held or name
        end
    end
    if held then return held, false end
    local found
    for _, name in ipairs(self:GetSortedNames()) do
        -- A core linked to another Discord core is that one's, whatever its name (#138).
        if not GuildOS.db.cores[name].discordTag and CoreManager.Slug(name) == c.tag then
            if name == c.name then return name, false end
            found = found or name
        end
    end
    if found then return found, false end
    local name = CoreManager.Slug(c.name) == c.tag and c.name or c.tag
    if GuildOS.db.cores[name] then name = c.tag end
    local n = 2
    while GuildOS.db.cores[name] do
        name = string.format("%s-%d", c.tag, n)                 -- a core name, not a member key
        n = n + 1
    end
    self:Create(name)
    return name, true
end

-- A member key as the site or another officer sent it, as this client keys that member (#97).
local function localKey(key)
    return type(key) == "string" and key ~= "" and GuildOS:LocalMemberKey(key) or nil
end

-- A Discord member's record: the class the site says, else the guild roster's, else the default;
-- the role it says when the class can play it, else the class's own.
local function discordRecord(self, key, m)
    local known = GuildOS.db.members and GuildOS.db.members[key]
    local cls = (self.CLASS_ROLES[m.class] and m.class)
        or (known and self.CLASS_ROLES[known.class] and known.class) or "WARRIOR"
    return {
        name  = type(m.name) == "string" and m.name ~= "" and m.name or key,
        class = cls,
        role  = self:RoleFor(cls, SITE_ROLES[m.slot] and m.slot or nil),
        note  = "",
        src   = "discord",
    }
end

-- Whether the Discord owns this core now: its name, its size and who of its people leave are set
-- there, and the core panel offers none of them here (#135).
function CoreManager:IsFromDiscord(coreName)
    local core = GuildOS.db.cores and GuildOS.db.cores[coreName]
    return type(core) == "table" and core.discordTag ~= nil
end

-- The Discord's cores as the last import saw them ({ tag, name }, by name), for an officer to link a
-- game core of another name to one (#138).
function CoreManager:DiscordCatalog()
    local out = {}
    for _, c in ipairs(GuildOS.db.discordCatalog or {}) do out[#out + 1] = c end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Names from the site or from another officer, kept only as names.
local function namesOnly(list)
    local out = {}
    for _, v in ipairs(type(list) == "table" and list or {}) do
        if type(v) == "string" and v ~= "" then out[#out + 1] = v end
    end
    return #out > 0 and out or nil
end

-- The game core holding a Discord core's tag here, if any. One at most: a core taking a tag takes it
-- from any other (#138).
local function holderOf(tag)
    for name, core in pairs(GuildOS.db.cores) do
        if type(core) == "table" and core.discordTag == tag then return name end
    end
    return nil
end

-- How new the Discord's lists are (#138): `at`, when the inbox they came from was written, against the
-- newest this client applied, from its own inbox or from another officer (`GuildOS.db.discordAt`). The
-- site sends every core of the guild together, so one mark for the guild settles them all, releases
-- included. A time past the realm's clock counts as now; another officer's message with none, once
-- there is a mark, as older.
-- `at` is the package's own, when the site's cores last changed on the site's clock (guildos-web #126);
-- from a site before it, when the companion wrote the inbox, on its PC's clock.
local function sane(at)
    at = tonumber(at)
    return at and at == at and math.min(at, GetServerTime()) or nil
end
local function isStale(at)
    local mark = GuildOS.db.discordAt
    return mark ~= nil and (at == nil or at < mark)
end
local function took(at)
    if at and at > (GuildOS.db.discordAt or 0) then GuildOS.db.discordAt = at end
end

-- A core is no longer the Discord's. Closed there, it stays as it is, people and all. Handed over to
-- another game core holding its tag (`moved`), the Discord's people go with the tag: left behind they
-- would be the same people on two cores, a tie no raid detection can settle (#138).
local function release(name, moved)
    local core = GuildOS.db.cores[name]
    if type(core) ~= "table" then return end
    core.discordTag, core.discordWaiting, core.linkAt = nil, nil, nil
    if moved and type(core.members) == "table" then
        for key, rec in pairs(core.members) do
            if type(rec) == "table" and rec.src == "discord" then core.members[key] = nil end
        end
    end
end

-- An officer's link (#138), made here or heard from another officer: the tag moves to `coreName` with
-- the Discord's people as they are, role and note, from the core holding it here; `linkAt` (the realm's
-- clock) says which link is the newest. Returns who is the Discord's on the core now, as the site would
-- send them.
local function moveTag(self, coreName, tag, linkAt)
    local core = self:GetCore(coreName)
    if not core then return {} end
    local from = holderOf(tag)
    if from and from ~= coreName then
        local old, members = GuildOS.db.cores[from], self:GetMembers(coreName)
        for key, rec in pairs(type(old.members) == "table" and old.members or {}) do
            if type(rec) == "table" and rec.src == "discord" then
                if type(members[key]) == "table" then members[key].src = "discord" else members[key] = rec end
            end
        end
        core.discordWaiting = old.discordWaiting
        self:SetRaidSize(coreName, self:GetRaidSize(from))
        release(from, true)
    end
    core.discordTag, core.linkAt = tag, linkAt
    local list = {}
    for key, rec in pairs(self:GetMembers(coreName)) do
        if type(rec) == "table" and rec.src == "discord" then
            list[#list + 1] = { key = key, name = rec.name, class = rec.class, slot = rec.role }
        end
    end
    return list
end

-- Another officer's link, when newer than the one this client has for the tag: the tag moves to the
-- sender's core, unless that core is another Discord core's here. A link is an officer's choice, not the
-- Discord's data: it is never judged by how new the sender's lists are.
local function heardLink(self, coreName, tag, linkAt)
    if not linkAt then return end
    local named = GuildOS.db.cores[coreName]
    if type(named) == "table" and named.discordTag and named.discordTag ~= tag then return end
    local here = holderOf(tag)
    if linkAt > (here and GuildOS.db.cores[here].linkAt or 0) then moveTag(self, coreName, tag, linkAt) end
end

-- One Discord core's people, reconciled into this game's core: as the import does it, and as another
-- officer's client sends its whole list (#138). The core is linked to `tag` (any other core here
-- holding it hands it over) and takes the Discord's size; whoever is missing joins; an officer's entry
-- for somebody the Discord has becomes the Discord's, class, role and note as the officer left them;
-- and the Discord's own people it no longer has leave. Whoever the Discord does not have, an officer
-- put there, and stays. Whether the list is newer than what this client has is the caller's to ask.
-- Returns how many joined, left and were taken over.
function CoreManager:SyncDiscordCore(coreName, list, size, tag, waiting)
    for name, other in pairs(GuildOS.db.cores) do
        if name ~= coreName and type(other) == "table" and other.discordTag == tag then release(name, true) end
    end
    local core = self:GetCore(coreName)
    if not core then return 0, 0, 0 end
    core.discordTag = tag
    core.discordWaiting = namesOnly(waiting)
    if tonumber(size) then self:SetRaidSize(coreName, tonumber(size)) end
    local members, incoming, added, removed, adopted = self:GetMembers(coreName), {}, 0, 0, 0
    for _, m in ipairs(list) do
        local key = type(m) == "table" and localKey(m.key)
        if key then
            incoming[key] = true
            local rec = members[key]
            if type(rec) ~= "table" then
                members[key] = discordRecord(self, key, m)
                added = added + 1
            elseif rec.src ~= "discord" then
                rec.src = "discord"
                adopted = adopted + 1
            end
        end
    end
    for key, rec in pairs(members) do
        if type(rec) == "table" and rec.src == "discord" and not incoming[key] then
            members[key] = nil
            removed = removed + 1
        end
    end
    return added, removed, adopted
end

-- The change alone, as an officer's client on 0.73.0 sends it, and the release of a core (tag false):
-- `add` the site's members not on the core yet, `remove` the keys whose record is the Discord's. A
-- change lands on the core holding its tag here, whatever the sender calls it, so no second core takes
-- the same people. What an officer put on the core is never touched, whoever asks. Returns how many
-- joined and left.
function CoreManager:ApplyDiscordChanges(coreName, add, remove, size, tag)
    local linking = type(tag) == "string" and tag ~= ""
    if linking then coreName = (coreFor(self, { tag = tag, name = coreName })) end
    -- A release is for a core that is here: one this client deleted is not made again for it.
    local core = tag == false and GuildOS.db.cores[coreName] or (tag ~= false and self:GetCore(coreName))
    if not core then return 0, 0 end
    if tag == false then
        release(coreName, false)
    elseif linking then
        core.discordTag = tag
    end
    if tonumber(size) then self:SetRaidSize(coreName, tonumber(size)) end
    local members, added, removed = self:GetMembers(coreName), 0, 0
    for _, m in ipairs(type(add) == "table" and add or {}) do
        local key = type(m) == "table" and localKey(m.key)
        if key and not members[key] then
            members[key] = discordRecord(self, key, m)
            added = added + 1
        end
    end
    for _, k in ipairs(type(remove) == "table" and remove or {}) do
        local key = localKey(k)
        local rec = key and members[key]
        if type(rec) == "table" and rec.src == "discord" then
            members[key] = nil
            removed = removed + 1
        end
    end
    return added, removed
end

-- Whose the package is, when it is not this guild's: its guild, and its realm on Anniversary, where
-- one Inbox.lua serves every realm of an install and a guild is its realm's. Nil when it is ours.
-- The name is the site's spelling, so capitals aside, as the game and the site's upload take it (#144).
local function notOurs(data)
    local mine = GetGuildInfo("player")
    if type(data.guild) ~= "string" or not mine or data.guild:lower() ~= mine:lower() then return tostring(data.guild) end
    if GuildOS.Client.isAnniversary and data.realm and data.realm ~= GetRealmName() then
        return tostring(data.guild) .. " (" .. tostring(data.realm) .. ")"
    end
    return nil
end

-- Imports a decoded GOSCORE1 into this guild; `at` is how new it is (the site's time, else the inbox's). Returns every
-- Discord core as { name, added, removed, adopted, list, size, tag, waiting, at, linkAt, quiet } (quiet when
-- nothing on it changed; `released` and tag false for a core the Discord no longer sends), and how many
-- people the site had no character for. When the payload is not this guild's: nil, and whose it is.
-- When this client already has newer lists, from another officer: nothing, and true.
function CoreManager:ImportFromSite(data, at)
    if type(data) ~= "table" or type(data.cores) ~= "table" then return nil end
    local other = notOurs(data)
    if other then return nil, other end
    if at and isStale(at) then return {}, 0, true end
    local cores, sent, catalog = {}, {}, {}
    for _, c in ipairs(data.cores) do
        if type(c) == "table" and type(c.tag) == "string" and c.tag ~= "" and type(c.name) == "string"
            and type(c.members) == "table" then
            catalog[#catalog + 1] = { tag = c.tag, name = c.name }
            local name, created = coreFor(self, c)
            sent[c.tag] = name
            local linked = GuildOS.db.cores[name].discordTag == c.tag
            local added, removed, adopted = self:SyncDiscordCore(name, c.members, c.size, c.tag, c.waiting)
            cores[#cores + 1] = {
                name = name, added = added, removed = removed, adopted = adopted,
                list = c.members, size = self:GetRaidSize(name), tag = c.tag, waiting = namesOnly(c.waiting), at = at,
                linkAt = GuildOS.db.cores[name].linkAt,
                quiet = not (created or not linked or added > 0 or removed > 0 or adopted > 0),
            }
        end
    end
    GuildOS.db.discordCatalog = catalog
    -- A core the Discord no longer sends (closed there, or the federation switched off) is the
    -- officers' again, as it stands.
    for _, name in ipairs(self:GetSortedNames()) do
        local tag = GuildOS.db.cores[name].discordTag
        if tag and not sent[tag] then
            release(name, false)
            cores[#cores + 1] = { name = name, released = true, tag = false, at = at }
        end
    end
    took(at)
    return cores, tonumber(data.unlinked) or 0
end

-- Why the inbox's cores were not imported, said once per guild until the reason changes (#138): an
-- import that says nothing looks exactly like one that is not working.
local function tellOnce(key, text)
    if GuildOS.db.discordTold == key then return end
    GuildOS.db.discordTold = key
    GuildOS:Print(text)
end

-- The Discord's cores the companion left in Inbox.lua, imported once this guild's db is known
-- (PLAYER_LOGIN does not wait for it), with one line saying what changed, or why nothing was. Every
-- core then waits for SendDiscordChanges, which needs the guild rank this early login lacks. An inbox
-- older than the lists another officer already sent is neither imported nor sent.
function CoreManager:ImportInbox()
    if not GuildOS.CompanionImport then return end
    local data, on, at = GuildOS.CompanionImport:CoresFromInbox()
    if not data then return end
    -- Another guild's first: an alt elsewhere is told the cores are not theirs, not to switch anything on.
    local other = notOurs(data)
    if other then
        tellOnce("guild:" .. other, string.format(L["The Discord cores in the inbox are for %s, not this guild."], other))
        return
    end
    if not on then
        tellOnce("companion-off", L["Cores from Discord are waiting in the inbox: turn the web companion on with /gos web on."])
        return
    end
    -- The site's time for the package when it sends one (guildos-web #126): one clock for every officer.
    -- From the first, a PC's clock no longer counts: not the mark it left (one running ahead would hold
    -- back every site package), nor an inbox from before (a companion stopped since the site dated them).
    local siteAt = tonumber(data.at)
    if siteAt and not GuildOS.db.discordSiteAt then GuildOS.db.discordAt, GuildOS.db.discordSiteAt = nil, true end
    if not siteAt and GuildOS.db.discordSiteAt then return end
    local cores, unlinked, stale = self:ImportFromSite(data, sane(siteAt or at))
    if not cores then return end
    GuildOS.db.discordTold = nil
    if stale then return end
    local parts = {}
    for _, c in ipairs(cores) do
        if not c.released and not c.quiet then parts[#parts + 1] = string.format("%s +%d -%d", c.name, c.added, c.removed) end
    end
    if #parts > 0 then
        local line = string.format(L["Cores from Discord: %s."], table.concat(parts, ", "))
        if unlinked > 0 then
            line = line .. " " .. string.format(L["%d on Discord with no confirmed character on the site."], unlinked)
        end
        GuildOS:Print(line)
    end
    -- ponytail: the lists wait in the session; a rank still unknown after OFFICER_START's minute
    -- drops them until the next login. Keep them in the guild's db until sent if that ever bites.
    GuildOS.State.discordCores = #cores > 0 and cores or nil
    if GuildOS.coresPanelRefresh then GuildOS.coresPanelRefresh() end
end

-- From OFFICER_START, once the rank is known and is an officer's: every Discord core goes to the other
-- officers as the Discord's whole list for it (#138), reconciled there by the same rule, so a client
-- that missed a login, or deleted the core, ends up as this one. Never an officer's own entries: the
-- whole roster would write over a pug another officer added while this client was away. The list goes
-- under an action of its own, `discordList`, which a client from before #138 ignores: 0.73.0 would take
-- it for a change with nothing in it, under the sender's name. A release keeps `discord`, which 0.73.0
-- understands. A core linked by hand says when (`linkAt`), so the link reaches every officer.
function CoreManager:SendDiscordChanges()
    local pending = GuildOS.State.discordCores
    GuildOS.State.discordCores = nil
    if not (pending and GuildOS.SyncService) then return end
    for _, c in ipairs(pending) do
        if c.released then
            GuildOS.SyncService:Publish("core.roster", "discord", { coreName = c.name, tag = false, at = c.at })
        else
            GuildOS.SyncService:Publish("core.roster", "discordList", {
                coreName = c.name, list = c.list, size = c.size, tag = c.tag, waiting = c.waiting, at = c.at,
                linkAt = c.linkAt,
            })
        end
    end
end

-- An officer linking a game core of another name to a Discord core (#138). The Discord's people move
-- from the core that held the tag, as they are, and the other officers hear now (the officer is in the
-- Config tab, so the rank is known), and later from every list this client sends. With no core here
-- holding the tag (it was deleted), the inbox makes it again first, or says why it cannot. A core
-- already another Discord core's is not linked.
function CoreManager:LinkDiscord(coreName, tag)
    local core = GuildOS.db.cores[coreName]
    if type(core) ~= "table" or type(tag) ~= "string" or tag == "" then return false end
    if core.discordTag then return core.discordTag == tag end
    if not holderOf(tag) then
        GuildOS.db.discordTold = nil
        self:ImportInbox()
        if not holderOf(tag) then return false end
    end
    local list = moveTag(self, coreName, tag, GetServerTime())
    local pending = GuildOS.State.discordCores or {}
    pending[#pending + 1] = { name = coreName, list = list, size = self:GetRaidSize(coreName), tag = tag,
        waiting = core.discordWaiting, at = GuildOS.db.discordAt, linkAt = core.linkAt }
    GuildOS.State.discordCores = pending
    self:SendDiscordChanges()
    return true
end

function CoreManager:BroadcastRoster(coreName)
    if not GuildOS.SyncService then return end
    GuildOS.SyncService:Publish("core.roster", "update", {
        coreName = coreName,
        members  = self:GetMembers(coreName),
    })
end

function CoreManager:InitSync()
    if not GuildOS.SyncService then return end

    -- Any player may broadcast a signup; officers store it.
    -- A sign-up is filed under who sent it, never under a key the payload names: that one carries
    -- the sender's realm on Forever (#97), and trusting it let anybody sign somebody else up.
    GuildOS.SyncService:On("core.signup", function(env, sender)
        local d = env.data
        if not d or not d.coreName or type(sender) ~= "string" or sender == "" then return end
        if not GuildOS:IsOfficer() then return end
        local short = sender:match("^([^-]+)") or sender
        local playerKey = GuildOS:GetPlayerKey(short, sender:match("-(.+)$"))
        local info = type(d.info) == "table" and d.info or {}
        info.name = short
        -- The class the guild roster (the server's) gives the sender, else one the payload names
        -- that exists, else warrior; the role is then one that class can play (#94).
        local rec = GuildOS:GetMemberRecord(short, sender:match("-(.+)$"))
        local cls = rec and rec.class
        if not self.CLASS_ROLES[cls] then cls = self.CLASS_ROLES[info.class] and info.class or "WARRIOR" end
        info.class = cls
        info.role = self:RoleFor(cls, info.role)
        self:AddSignup(playerKey, info, d.coreName)
        if GuildOS.coresPanelRefresh then GuildOS.coresPanelRefresh() end
    end)

    -- Officers broadcast roster updates to each other.
    -- An edit sends the whole roster. The Discord's import sends each core's whole list (`discordList`,
    -- #138) and its releases (`discord`, as 0.73.0 sent its change alone, #135), which a client from
    -- before them ignores, as they carry no `members`. Never one older than what this client has.
    GuildOS.SyncService:On("core.roster", function(env, sender)
        local d = env.data
        if type(d) ~= "table" or type(d.coreName) ~= "string" or d.coreName == "" then return end
        local discord = env.act == "discord" or env.act == "discordList"
        if not discord and not d.members then return end
        if not GuildOS:IsOfficerByName(sender) then return end
        if discord then
            -- A list lands on the core holding its tag here, as the import's does; only a link moves a tag.
            local at, list = sane(d.at), env.act == "discordList"
            if list and (type(d.list) ~= "table" or type(d.tag) ~= "string" or d.tag == "") then return end
            -- A link to a tag no core here holds needs fresh lists: an older one would link a core the
            -- Discord has closed since.
            if list and (holderOf(d.tag) or not isStale(at)) then heardLink(self, d.coreName, d.tag, sane(d.linkAt)) end
            if not isStale(at) then
                if list then
                    self:SyncDiscordCore((coreFor(self, { tag = d.tag, name = d.coreName })), d.list, d.size, d.tag, d.waiting)
                else
                    self:ApplyDiscordChanges(d.coreName, d.add, d.remove, d.size, d.tag)
                end
                took(at)
            end
        else
            local core = self:GetCore(d.coreName)
            if core then core.members = GuildOS:LocalizeMemberTable(d.members) end   -- this client's keys (#97)
        end
        if GuildOS.coresPanelRefresh then GuildOS.coresPanelRefresh() end
    end)
end
