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

-- Retail's damage specs that fight in melee: ChrSpecialization (12.1.5.70448) Flags bit 0x4 on a
-- Role 2 (damage) spec, the "Initial" specs of a character below level 10 included. Every other
-- damage spec is ranged: the Hunter's Beast Mastery and Marksmanship, Augmentation, Devourer (1480)
-- (issue #184).
CoreManager.MELEE_SPECS = {
    [70] = true, [71] = true, [72] = true, [103] = true, [251] = true, [252] = true, [255] = true,
    [259] = true, [260] = true, [261] = true, [263] = true, [269] = true, [577] = true,
    [1446] = true, [1450] = true, [1451] = true, [1453] = true, [1455] = true, [1456] = true,
}
local SPEC_ROLES = { TANK = "tank", HEALER = "healer" }

-- The core role a retail spec record plays ("TANK", "HEALER" or "DAMAGER", as the client names
-- it), or nil for a spec with no id: a classic one names no role.
function CoreManager:SpecRole(spec)
    local id = type(spec) == "table" and tonumber(spec.specID)
    if not id then return nil end
    if spec.role == "DAMAGER" then return self.MELEE_SPECS[id] and "mdps" or "rdps" end
    return SPEC_ROLES[spec.role]
end

-- The role a member starts in: on retail the one their scanned spec plays, when the class can
-- play it; otherwise, and on every other client, the class's own (issue #184).
function CoreManager:DefaultRole(cls, key)
    if GuildOS.Client.isRetail and key then
        local m = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
        local role = m and self:SpecRole(m.spec)
        local can = self.CLASS_ROLES[cls]
        if role and can and can[role] then return role end
    end
    return self.CLASS_DEFAULT_ROLE[cls] or "rdps"
end

-- `role` when the class can play it, else the member's own (`key`, DefaultRole): a sign-up never
-- carries a role its class cannot fill (issue #94).
function CoreManager:RoleFor(cls, role, key)
    local can = self.CLASS_ROLES[cls]
    if can and can[role] then return role end
    return self:DefaultRole(cls, key)
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

-- The role a member starts in on the core screen; `key` lets a retail spec decide (DefaultRole).
function CoreManager:GetRoleForClass(class, key)
    return self:DefaultRole(class, key)
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
    rollDuration     = 30,
    autoAnnounce     = true,
    wishlistOnlyMode = false,
    minAttendancePct = 0,
    attTiebreaker    = true,
    recvPenalty      = true,
    lootThreshold    = 3,
    disenchanter     = "",
    bank             = "",       -- the character an exception sends items "to the bank" (issue #335)
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
    self:MigrateLink()
    GuildOS:SafeCall(self.ImportInbox, self)   -- the Discord's cores (#135)
    GuildOS:SafeCall(self.MigrateGuests, self)   -- a pug on a Discord core is a guest (#340)
end

-- Whether any core here is the Discord's now.
function CoreManager:HasDiscordCores()
    for _, core in pairs(GuildOS.db.cores or {}) do
        if type(core) == "table" and core.discordTag then return true end
    end
    return false
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

----------------------------------------------------------------------
-- Who owns the guild's cores (ADR-0036; guildos-web specs/085, issue #339). A guild linked to the site
-- has its cores born on Discord (`/core criar`) and reaching the game by GOSCORE1; the game creates none.
-- A guild without the site owns them here, as always. Kept in the guild's db:
--   db.coreLink.since       when this guild became linked (an import or another officer's list with
--                           cores); nil when it is not
--   db.coreLink.seenAt      how fresh the newest package is (the inbox's ack, a paste, another officer's)
--   db.coreLink.importedAt  when this client last imported a GOSCORE1 (the upload's receipt, #347)
--   db.coreLink.toldFor     the `seenAt` the "30 days with no package" line was said for
--   db.coreLink.releasedAt  an officer chose to create cores in game again, at this realm time: a
--                           package this client RECEIVED by then (an inbox the companion wrote, another
--                           officer's list of a package seen) is older than that choice; one received
--                           later (a code pasted now, a companion back) links the guild again
----------------------------------------------------------------------
local QUIET_DAYS = 30            -- days with no new package before the game offers to create cores again
local DAY = 86400

local function linkRec()
    local link = GuildOS.db.coreLink
    if type(link) ~= "table" then
        link = {}
        GuildOS.db.coreLink = link
    end
    return link
end

-- Whether this guild's cores are the site's: it has imported, or heard from an officer, a GOSCORE1 with
-- cores, and neither an empty one nor an officer's choice has given them back since.
function CoreManager:IsLinked()
    local link = GuildOS.db and GuildOS.db.coreLink
    return type(link) == "table" and link.since ~= nil
end

-- When the newest package for a linked guild was seen (nil when not linked).
function CoreManager:LinkSeenAt()
    local link = GuildOS.db and GuildOS.db.coreLink
    if type(link) ~= "table" or not link.since then return nil end
    return link.seenAt or link.since
end

-- Whether a linked guild has had no new package for QUIET_DAYS (spec 085's open question): its
-- federation may be off with no companion left to bring the empty package.
function CoreManager:IsLinkQuiet()
    local seen = self:LinkSeenAt()
    return seen ~= nil and GetServerTime() - seen > QUIET_DAYS * DAY
end

-- A core of a guild without the site, with all sub-tables initialized. No check: the import makes
-- Discord cores through here in a linked guild too.
-- Another officer's points entries for a core this client did not have are kept (Points:ReplayWaiting):
-- a core that comes into existence here, made, imported or renamed into that name (or one it is known
-- by, Points:CoreNamed), plays them. With no name, every core that has some by now (after an import,
-- once the Discord's tag and name are on the core).
local function replayWaiting(name)
    local w, P = GuildOS.db.pointsWaiting, GuildOS.Points
    if type(w) ~= "table" or next(w) == nil or not P then return end
    if name == nil then
        if P.ReplayAllWaiting then P:ReplayAllWaiting() end
    elseif P.ReplayWaiting then
        P:ReplayWaiting(name)
    end
end

local function newCore(name)
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
    replayWaiting(name)
    return GuildOS.db.cores[name]
end

-- Creates a new core with all sub-tables initialized, as an officer asks from the panel.
-- Returns true on success, or false + error message on failure. A guild linked to the site creates
-- its cores on Discord (#339): refused here, saying where.
-- What a core's name may be (review of #347): what the site keeps of it in the upload's receipt
-- (guildos-web lib/core-receipt.ts `isName`), so a core named in game is never one the site refuses
-- whole. nil when it may, else the line saying why.
local CORE_NAME_LIMIT = 48   -- bytes
local function badCoreName(name)
    local why = GuildOS:NameProblem(name, CORE_NAME_LIMIT)
    if why == "empty" then return L["Name cannot be empty."] end
    if why == "long" then
        return string.format(L["A core's name has at most %d bytes (a letter with an accent is two)."], CORE_NAME_LIMIT)
    end
    if why then return L["A core's name cannot have | or control characters, nor be constructor, prototype or __proto__."] end
    return nil
end
CoreManager.BadCoreName = badCoreName
local ON_DEMAND_MAX = 64   -- bytes of a core's name made on demand: what an officer's message carries

function CoreManager:Create(name)
    if not name or name == "" then
        return false, L["Name cannot be empty."]
    end
    local bad = badCoreName(name)
    if bad then return false, bad end
    if GuildOS.db.cores[name] then
        return false, L["A core with that name already exists."]
    end
    if self:IsLinked() then
        return false, L["This guild's cores are created on Discord, with /core criar: the game gets them from guildos.me."]
    end
    newCore(name)
    return true
end

-- A core's table moves to another name, with its nights, attendance, points and loot rule, and the
-- raid's active core, kept pick and announcement follow. For Rename and for the Discord's own rename.
local function moveCore(oldName, newName)
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

    -- Update active tag if it was the renamed one: the tracker's and the saved one, each on its own. A
    -- rename that comes with the inbox at login runs before RaidTracker:Initialize, when the module is
    -- loaded but has read nothing yet (its tag "", no raid): only the saved state names the core then,
    -- and the raid reopened from it must find it under the new name.
    if GuildOS.RaidTracker and GuildOS.RaidTracker.currentGroupTag == oldName then
        GuildOS.RaidTracker:SetGroupTag(newName)
    end
    if rtDB and rtDB.currentGroupTag == oldName then rtDB.currentGroupTag = newName end
    -- And the raid in progress (the tracker's, and the one saved for a /reload), and an officer's pick
    -- kept for it (issue #99).
    local RT = GuildOS.RaidTracker
    local raid = RT and RT.currentRaid
    if raid and raid.groupTag == oldName then raid.groupTag = newName end
    local open = rtDB and rtDB.openSession
    if type(open) == "table" and open.groupTag == oldName then open.groupTag = newName end
    if RT and RT.coreAnnounced == oldName then RT.coreAnnounced = newName end
    if RT and RT.gracePick == oldName then RT.gracePick = newName end
    local pick = rtDB and rtDB.corePick
    if type(pick) == "table" and pick.tag == oldName then pick.tag = newName end

    -- Every other place that keeps a core by its name (review of #339: an undo after a Discord rename
    -- gave back into the guild's pool, the award still naming the old core):
    -- the awards an undo gives back into (the core's own log, and the guild's from before cores),
    -- and the pool an award was given in (#352), which for a group is its elenco's, kept in the group's log,
    local function awards(list)
        for _, award in ipairs(type(list) == "table" and list or {}) do
            if type(award) == "table" and award.core == oldName then award.core = newName end
            if type(award) == "table" and award.pool == oldName then award.pool = newName end
        end
    end
    for _, core in pairs(GuildOS.db.cores) do
        awards(type(core) == "table" and type(core.lootMaster) == "table" and core.lootMaster.awardHistory)
    end
    awards(type(GuildOS.db.lootMaster) == "table" and GuildOS.db.lootMaster.awardHistory)
    -- the item being given and the last award's core (LootMaster), the pool `InCore` is on (Points),
    local LM = GuildOS.LootMaster
    if LM and type(LM.activeLoot) == "table" and LM.activeLoot.core == oldName then LM.activeLoot.core = newName end
    if LM and type(LM.activeLoot) == "table" and LM.activeLoot.pool == oldName then LM.activeLoot.pool = newName end
    if LM and LM.lastAwardCore == oldName then LM.lastAwardCore = newName end
    if GuildOS.Points and GuildOS.Points.scope == oldName then GuildOS.Points.scope = newName end
    -- the revision of its points' snapshots (SyncService, "points:<name>"), so the next one is newer,
    local rev = GuildOS.db.sync and GuildOS.db.sync.rev
    if type(rev) == "table" and type(rev["points:" .. oldName]) == "table" then
        local from, to = rev["points:" .. oldName], rev["points:" .. newName] or {}
        for key, n in pairs(from) do
            if type(n) == "number" and n > (tonumber(to[key]) or 0) then to[key] = n end
        end
        rev["points:" .. newName], rev["points:" .. oldName] = to, nil
    end
    -- and the Discord's lists waiting to go to the other officers.
    for _, c in ipairs(type(GuildOS.State) == "table" and type(GuildOS.State.discordCores) == "table"
        and GuildOS.State.discordCores or {}) do
        if type(c) == "table" and c.name == oldName then c.name = newName end
    end
    -- Its loot rule, points, counters, queues, sign-ups and guests are the core table's own and moved with
    -- it; the night's rule (db.lootNight) is the raid's, not a core's; the loot history keeps the raid.
    -- What other officers send under the old name (kept, or from a client that has not seen the rename)
    -- is this core's, and what they sent under the new name before it was this client's lands now.
    if GuildOS.Points and GuildOS.Points.NoteRename then GuildOS.Points:NoteRename(oldName, newName) end
    replayWaiting(newName)
end

-- Renames a core and migrates all session/attendance data.
function CoreManager:Rename(oldName, newName)
    if not oldName or not GuildOS.db.cores[oldName] then
        return false, L["Core not found."]
    end
    -- A core from the site and its Discord is the site's (issue #293): its name is changed there, and
    -- the next import renames it here (#339).
    if self:IsFromDiscord(oldName) then
        return false, L["This core is managed on guildos.me and its Discord: rename it there."]
    end
    if not newName or newName == "" then
        return false, L["Name cannot be empty."]
    end
    local bad = badCoreName(newName)
    if bad then return false, bad end
    if GuildOS.db.cores[newName] then
        return false, L["A core with that name already exists."]
    end
    moveCore(oldName, newName)
    return true
end

-- Removes the core config entry (does NOT delete sessions or attendance data).
function CoreManager:Delete(name)
    if not name or name == "" then return false end
    -- The site's own core is closed on the site (issue #293): deleted here, the next import would
    -- make it again, empty of what officers set here.
    if self:IsFromDiscord(name) then
        return false, L["This core is managed on guildos.me and its Discord: close it there."]
    end
    GuildOS.db.cores[name] = nil
    -- Nor a name that points entries kept for later at it: a core made later under that name, or under
    -- a name renamed into it, is another core and must not take them (Points:CoreNamed).
    local aliases = GuildOS.db.pointsAliases
    if type(aliases) == "table" then
        aliases[name] = nil
        -- The whole chain: Kara -> Karazhan -> Kz, Kz deleted, leaves no Kara for a later Karazhan.
        local gone = { [name] = true }
        local removed = true
        while removed do
            removed = false
            for from, alias in pairs(aliases) do
                if type(alias) == "table" and gone[alias.to] then
                    aliases[from] = nil
                    gone[from] = true
                    removed = true
                end
            end
        end
    end
    -- The active core deleted is no longer active, nor the raid's, nor an officer's pick: left set,
    -- the next read of it, or a /reload inside the raid, would make it again, empty (#138).
    local RT, rtDB = GuildOS.RaidTracker, GuildOS.db.raidTracker
    if RT and RT.currentGroupTag == name then RT:SetGroupTag("") end
    -- The saved tag on its own too: before RaidTracker:Initialize the module names nothing yet.
    if rtDB and rtDB.currentGroupTag == name then rtDB.currentGroupTag = "" end
    if RT and RT.currentRaid and RT.currentRaid.groupTag == name then RT.currentRaid.groupTag = "" end
    if rtDB and type(rtDB.openSession) == "table" and rtDB.openSession.groupTag == name then rtDB.openSession.groupTag = "" end
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
            -- The night's raid is the core's members and its guests (issue #340).
            local guests = type(core.guests) == "table" and core.guests or {}
            local count = 0
            for key in pairs(players or {}) do
                if members[key] or members[altLinks[key]] or guests[key] or guests[altLinks[key]] then count = count + 1 end
            end
            if count >= 2 and count * 2 >= size then
                candidates[#candidates + 1] = { name = name, count = count, raidSize = self:GetRaidSize(name) }
            end
        end
    end
    local raidSize = isSizeOfThisGame(instanceSize) and instanceSize or size
    -- Elenco e grupos (issue #352): an elenco's roster holds its groups' people, so it covers a group's
    -- night as well as the group does, often with more of the raid on it (a sub from the elenco). A
    -- group of the raid's format with the group's people on it is the night's: its elenco steps aside.
    -- When two of its groups tie (half of each came), the night is the elenco's. An elenco whose groups
    -- are smaller than the raid (a 40 with its two 20s) keeps it. Cores with no elenco and no groups
    -- rank as always.
    local covered, pool = {}, candidates
    for _, c in ipairs(candidates) do
        if c.raidSize >= raidSize then
            for _, e in ipairs(candidates) do
                if e ~= c and self:IsAncestor(e.name, c.name) then covered[e] = true end
            end
        end
    end
    if next(covered) then
        pool = {}
        for _, c in ipairs(candidates) do if not covered[c] then pool[#pool + 1] = c end end
    end
    local best
    for _, c in ipairs(pool) do
        if not best or ranksBefore(c, best, raidSize) then best = c end
    end
    if not best then return nil end
    local tied = { best }
    for _, c in ipairs(pool) do
        if c ~= best and not ranksBefore(best, c, raidSize) then tied[#tied + 1] = c end
    end
    if #tied == 1 then return best.name, best.count, size end
    -- A tie: no roster is the raid, unless the tied are groups of one elenco here, the nearest one.
    local closest
    for e in pairs(covered) do
        local holds = true
        for _, t in ipairs(tied) do
            if not self:IsAncestor(e.name, t.name) then holds = false; break end
        end
        if holds and (not closest or self:IsAncestor(closest.name, e.name)) then closest = e end
    end
    if closest then return closest.name, closest.count, size end
    return nil
end

-- Returns the core table for `name` (or the active core when name is nil).
-- Auto-creates the entry when name is non-empty and doesn't exist yet,
-- so callers never have to guard against nil.
-- In a guild linked to the site a name no core has makes none (#339): the raid's tag, a sign-up or
-- another officer's roster for it read as no core.
function CoreManager:GetCore(name)
    if name == nil then name = self:GetActiveName() end
    if not name or name == "" then return nil end
    -- Elsewhere a name is made on demand as always, whatever the rule for a new name typed in the
    -- panel says (badCoreName gates Create and Rename only): a core named before that rule ("Kara ||
    -- Sexta", fifty bytes) is still another officer's, and its roster and points, or a raid under its
    -- tag, would be dropped here. The receipt leaves out what the site refuses. Only what no person typed:
    -- a control character, or past what an officer's message carries.
    if not GuildOS.db.cores[name] and not self:IsLinked() and type(name) == "string" and #name <= ON_DEMAND_MAX
        and not name:find("%c") then
        newCore(name)
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
        rollDuration     = lmField(core, "rollDuration"),
        autoAnnounce     = lmField(core, "autoAnnounce"),
        wishlistOnlyMode = lmField(core, "wishlistOnlyMode"),
        minAttendancePct = lmField(core, "minAttendancePct"),
        attTiebreaker    = lmField(core, "attTiebreaker"),
        recvPenalty      = lmField(core, "recvPenalty"),
        lootThreshold    = lmField(core, "lootThreshold"),
        disenchanter     = lmField(core, "disenchanter"),
        bank             = lmField(core, "bank"),
        dkpMinBid        = lmField(core, "dkpMinBid"),
        dkpBidTime       = lmField(core, "dkpBidTime"),
        -- The core's own choice (issue #338), never the guild's: nil follows the guild.
        lootSystem       = core and core.lootMaster and core.lootMaster.lootSystem or nil,
        rule             = core and core.lootMaster and core.lootMaster.rule or nil,
    }
end

----------------------------------------------------------------------
-- A core's own loot system and loot rule (issue #338). A core that chose neither follows the guild.
-- Kept beside its loot settings, under one stamp, and told to the other officers with the core:
--   core.lootMaster.lootSystem   one of GuildOS.LOOT_SYSTEMS' keys, or nil
--   core.lootMaster.rule         a loot rule (LootRule:Validate), or nil
--   core.lootMaster.lootAt       when an officer last changed either
-- The `lootMethod` field of before was read by nothing and is not carried over: no core changes
-- behaviour on update.
----------------------------------------------------------------------
local LOOT_FUTURE_SLACK = 300   -- seconds a peer's clock may run ahead of this one
local CORE_NAME_MAX = 64        -- bytes of a core's name an officer's message may carry

-- A core that exists, by name (nil: the active one), without making one.
local function coreNamed(self, coreName)
    if coreName == nil then coreName = self:GetActiveName() end
    if type(coreName) ~= "string" or coreName == "" then return nil end
    local cores = GuildOS.db and GuildOS.db.cores
    local core = cores and cores[coreName]
    return type(core) == "table" and core or nil, coreName
end

function CoreManager:GetLootSystem(coreName)
    local core = coreNamed(self, coreName)
    local sys = core and core.lootMaster and core.lootMaster.lootSystem
    return type(sys) == "string" and sys or nil
end

function CoreManager:GetLootRule(coreName)
    local core = coreNamed(self, coreName)
    local rule = core and core.lootMaster and core.lootMaster.rule
    return type(rule) == "table" and rule or nil
end

local function stampLoot(self, core, coreName)
    local lm = core.lootMaster
    lm.lootAt = math.max(GetServerTime(), (tonumber(lm.lootAt) or 0) + 1)
    self:PublishLoot(coreName)
end

-- A core's own loot system; nil goes back to following the guild. Choosing one puts its ready-made
-- rule in force again, over a rule the officers had made for the core. Officer only.
function CoreManager:SetLootSystem(coreName, sys)
    if not GuildOS:IsOfficer() then return false end
    local core, name = coreNamed(self, coreName)
    if not core or self:LootRuleFromSite(name) then return false end
    if sys ~= nil and not GuildOS:IsLootSystemHere(sys) then return false end
    core.lootMaster = core.lootMaster or {}
    core.lootMaster.lootSystem, core.lootMaster.rule = sys, nil
    stampLoot(self, core, name)
    return true
end

-- A core's own loot rule, which LootRule:Set has read whole; nil goes back to its loot system's.
function CoreManager:SetLootRule(coreName, rule)
    if not GuildOS:IsOfficer() then return false end
    local core, name = coreNamed(self, coreName)
    if not core or self:LootRuleFromSite(name) then return false end
    core.lootMaster = core.lootMaster or {}
    core.lootMaster.rule = rule
    stampLoot(self, core, name)
    return true
end

-- One core's choice to the other officers: when it changes, and again on the officers' regular sync.
-- It travels with the core's roster (domain "core.roster"), under an action a client from before
-- ignores, as it carries no `members`.
function CoreManager:PublishLoot(coreName)
    local core, name = coreNamed(self, coreName)
    local lm = core and core.lootMaster
    if not (lm and lm.lootAt and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    GuildOS.SyncService:Publish("core.roster", "loot",
        { coreName = name, sys = lm.lootSystem or false, rule = lm.rule or false }, { rev = lm.lootAt })
end

function CoreManager:PublishAllLoot()
    for _, name in ipairs(self:GetSortedNames()) do self:PublishLoot(name) end
end

-- Another officer's choice for a core (the handler has checked the officer and SyncService the
-- channel). The newest stamp wins. A loot system this client does not offer, or a rule it cannot read
-- whole, is refused whole: the core keeps what it had, system and rule. A core this client does not
-- have is not made by this message; it comes with its roster.
function CoreManager:OnLootSync(env)
    local d = env and env.data
    local at = env and tonumber(env.rev)
    if type(d) ~= "table" or type(d.coreName) ~= "string" or #d.coreName > CORE_NAME_MAX then return false end
    if not (at and at > 0 and at < math.huge) then return false end
    local core = coreNamed(self, d.coreName)
    if not core then return false end
    local sys, rule = d.sys, d.rule
    if sys == false then sys = nil end
    if rule == false then rule = nil end
    if sys ~= nil and (type(sys) ~= "string" or not GuildOS:IsLootSystemHere(sys)) then return false end
    if rule ~= nil and not (GuildOS.LootRule and GuildOS.LootRule:Validate(rule)) then return false end
    at = math.min(at, GetServerTime() + LOOT_FUTURE_SLACK)
    core.lootMaster = core.lootMaster or {}
    local lm = core.lootMaster
    if lm.lootAt and at <= lm.lootAt then return false end
    local before = GuildOS:GetLootSystem()
    lm.lootSystem, lm.rule, lm.lootAt = sys, rule, at
    if GuildOS:GetLootSystem() ~= before and GuildOS.OnLootSystemChanged then GuildOS:OnLootSystemChanged() end
    return true
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
-- A core NAMED that this client does not have (a linked guild makes none, #339: renamed or new on
-- Discord and not here yet) has no pool: nil, never the guild's, or another officer's entries for that
-- core would land in the guild's own standings. Only the raid's active tag naming no core reads as the
-- guild's: that raid is outside a core (Points:ActiveCore tags its entries "").
function CoreManager:GetPointsDB(coreName)
    local named = coreName ~= nil
    if not named then coreName = self:GetActiveName() end
    if not coreName or coreName == "" then
        return GuildOS.db.points
    end

    local core = self:GetCore(coreName)
    if not core then
        if named then return nil end
        return GuildOS.db.points
    end

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
    -- A core's points start from the guild's own settings, never from nothing: a new core used to
    -- award 0 per boss (issue #294). Only what the core never set; what it set stays its own.
    local guildCfg = (GuildOS.db.points and GuildOS.db.points.config) or {}
    for k, v in pairs(guildCfg) do
        if p.config[k] == nil then p.config[k] = v end
    end
    if not p.standings    then p.standings     = {}     end
    if not p.log          then p.log           = {}     end
    if not p.appliedOps   then p.appliedOps    = {}     end
    if p.appliedCount == nil then p.appliedCount = 0    end
    return p
end

-- Whether `coreName` names a pool here ("" is the guild's), without making a core: an undo into a core
-- that is gone has nowhere to give back to.
function CoreManager:HasPool(coreName)
    if coreName == nil or coreName == "" then return true end
    return type(GuildOS.db.cores[coreName]) == "table"
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
        -- A reserve stays one through an edit (issue #212); nil is a titular, as every older record.
        status = info.status or (type(held) == "table" and held.status or nil),
    }
    return true
end

function CoreManager:RemoveMember(playerKey, coreName)
    local core = self:GetCore(coreName)
    if core and core.members then core.members[playerKey] = nil end
end

-- A member's role and place, from the core's roster (issue #346: the role is a dropdown there, and the
-- screen wrote the field itself). Told to the other officers with the roster. A Discord core's people
-- keep the Discord's place: only their role is the officers'. Returns whether it changed.
local MEMBER_ROLES = { tank = true, healer = true, mdps = true, rdps = true }
function CoreManager:SetMemberRole(playerKey, role, coreName)
    local core = coreName and coreName ~= "" and GuildOS.db.cores[coreName]
    local mem = core and core.members and core.members[playerKey]
    if not (mem and MEMBER_ROLES[role]) then return false end
    if mem.role == role then return true end
    mem.role = role
    self:BroadcastRoster(coreName)
    return true
end

-- Titular or reserve ("bench"), for somebody the officers put on the core (issue #212).
function CoreManager:SetMemberBench(playerKey, bench, coreName)
    local core = coreName and coreName ~= "" and GuildOS.db.cores[coreName]
    local mem = core and core.members and core.members[playerKey]
    if not mem or (self:IsFromDiscord(coreName) and mem.src == "discord") then return false end
    mem.status = bench and "bench" or nil
    self:BroadcastRoster(coreName)
    return true
end

-- Where a player stands with a core, for the sign-up window's card (issue #346): on it (and in
-- reserve or not), asked (when), or neither; what the core still lacks by role, whether it is full,
-- when it raids and who leads it (where the site sent them: `schedule`, `leader` on the core) and the
-- player's presence on its nights.
--   { member, bench, pending = <ts or true>, missing = { tank, healer, mdps, rdps }, full, schedule,
--     leader, presence }
function CoreManager:SignupState(coreName, playerKey)
    local core = GuildOS.db.cores and GuildOS.db.cores[coreName]
    if type(core) ~= "table" then return nil end
    local out = {}
    local mem = core.members and core.members[playerKey]
    out.member = mem ~= nil
    out.bench = mem ~= nil and mem.status == "bench"
    local su = core.signups and core.signups[playerKey]
    out.pending = (su and (su.ts or true)) or nil
    local open = self:OpenSlots(coreName)
    out.missing = { tank = open.tank, healer = open.healer, mdps = open.mdps, rdps = open.rdps }
    out.full = self:GetComposition(coreName).total >= self:GetRaidSize(coreName)
    out.schedule = type(core.schedule) == "string" and core.schedule ~= "" and core.schedule or nil
    out.leader = type(core.leader) == "string" and core.leader ~= "" and core.leader or nil
    out.presence = self:MemberPresence(playerKey, coreName)
    return out
end

-- A member's presence on the core's nights, in percent, for the roster's column (RaidTracker's).
function CoreManager:MemberPresence(playerKey, coreName)
    local RT = GuildOS.RaidTracker
    if not (RT and RT.GetAttendancePercent) then return nil end
    return RT:GetAttendancePercent(playerKey, coreName)
end

----------------------------------------------------------------------
-- The night's guests (issue #340; ADR-0036). A pug is a guest of the night, not a member of the core:
-- in a guild linked to the site the Discord says who is on a Discord core, so whoever an officer adds
-- there is a guest, kept apart from the members:
--   core.guests[key] = { name, class, role, note, stay = true|nil, at, by }
-- The composition and the open seats count members only; the night's raid (which core a group is)
-- counts both. A guest leaves when the raid session ends, unless marked to stay. Guests travel between
-- officers as changes (`core.roster`, action "guests": `put` and `gone`), never as a whole list, so no
-- officer's guest is taken off by another's; a client from before ignores the action (no `members`).
----------------------------------------------------------------------
local GUEST_MAX = 40          -- guests a core holds, and a message may carry
local GUEST_TEXT = 48         -- bytes of a guest's name
local GUEST_NOTE = 120        -- bytes of a guest's note
local GUEST_KEY = 64          -- bytes of a key another officer's message may carry

-- Whether an officer's "add" on this core makes a guest: a Discord core of a linked guild.
function CoreManager:TakesGuests(coreName)
    return self:IsLinked() and self:IsFromDiscord(coreName)
end

-- A core's guests by key; an empty table for a core that has none, or does not exist (none is made).
function CoreManager:GetGuests(coreName)
    local core = coreNamed(self, coreName)
    if not core then return {} end
    if type(core.guests) ~= "table" then core.guests = {} end
    return core.guests
end

local function countOf(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- A guest's record from what an officer typed or sent, every field checked. The key (with the realm)
-- is who the guest is; the name is only how they are shown, cut on a character, never with a `|` or a
-- control character in it: one that has them, or none, is the key's own name. nil for a key that
-- cannot be anyone's name.
local function guestRecord(self, key, info, stay)
    info = type(info) == "table" and info or {}
    if type(key) ~= "string" or key == "" or key:find("[%c|]") then return nil end
    local cls = self.CLASS_ROLES[info.class] and info.class or "WARRIOR"
    local name = type(info.name) == "string" and info.name or ""
    if name:find("[%c|]") or not GuildOS:IsUtf8(name) or strtrim(name) == "" then name = key:match("^([^-]+)") or key end
    local note = type(info.note) == "string" and info.note or ""
    return {
        name = GuildOS:Utf8Cut(name, GUEST_TEXT),
        class = cls,
        role = self:RoleFor(cls, info.role, key),
        note = GuildOS:Utf8Cut(note, GUEST_NOTE),
        stay = stay == true or nil,
        -- A member made a guest by MigrateGuests, not added as one: a member again once the core is no
        -- longer the Discord's (release).
        migrated = info.migrated == true or nil,
        at = math.floor(GuildOS.Finite(info.at) or GetServerTime()),
        by = type(info.by) == "string" and info.by:sub(1, GUEST_KEY) or nil,
    }
end

-- The change to the other officers: the guests put on the core (by key) and the keys taken off.
-- `endAt`: the gone are the night's end (EndNight) at that time, which a client still raiding that core
-- lets pass, and which takes off only the guests put on before it (OnGuestsSync).
local function publishGuests(self, coreName, put, gone, endAt)
    if not (GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    local core = GuildOS.db.cores[coreName]
    GuildOS.SyncService:Publish("core.roster", "guests", {
        coreName = coreName, tag = type(core) == "table" and core.discordTag or nil, put = put, gone = gone,
        ended = endAt and true or nil, endAt = endAt,
    })
end

-- Adds or updates a guest of the night on a core that exists; `stay` keeps them past the night. A member
-- of the core is not made a guest too. Returns true, or false and why.
function CoreManager:AddGuest(playerKey, info, coreName, stay)
    local core, name = coreNamed(self, coreName)
    if not core or type(playerKey) ~= "string" or playerKey == "" then return false, L["Core not found."] end
    if type(core.members) == "table" and core.members[playerKey] then return false, L["Already on this core."] end
    local guests = self:GetGuests(name)
    if not guests[playerKey] and countOf(guests) >= GUEST_MAX then
        return false, string.format(L["A core holds at most %d guests."], GUEST_MAX)
    end
    local rec = guestRecord(self, playerKey, info, stay)
    if not rec then return false, L["Type the guest's name."] end
    rec.by = rec.by or GuildOS.Compat.PlayerName()
    guests[playerKey] = rec
    publishGuests(self, name, { [playerKey] = rec }, nil)
    return true
end

function CoreManager:RemoveGuest(playerKey, coreName)
    local core, name = coreNamed(self, coreName)
    if not (core and type(core.guests) == "table" and core.guests[playerKey]) then return false end
    core.guests[playerKey] = nil
    publishGuests(self, name, nil, { playerKey })
    return true
end

-- Marks a guest to stay past the night, or to leave with it.
function CoreManager:SetGuestStay(playerKey, coreName, stay)
    local core, name = coreNamed(self, coreName)
    local rec = core and type(core.guests) == "table" and core.guests[playerKey]
    if not rec then return false end
    rec.stay = stay and true or nil
    publishGuests(self, name, { [playerKey] = rec }, nil)
    return true
end

-- An officer's "add" in the core's roster (issue #340): a guest on a Discord core of a linked guild, a
-- member everywhere else, as always (then the whole roster goes to the other officers, as before).
-- Returns "guest" or "member", or false and why.
function CoreManager:AddToRoster(playerKey, info, coreName)
    if self:TakesGuests(coreName) then
        local ok, why = self:AddGuest(playerKey, info, coreName, false)
        if not ok then return false, why end
        return "guest"
    end
    local ok, why = self:AddMember(playerKey, info, coreName)
    if not ok then return false, why end
    self:BroadcastRoster(coreName)
    return "member"
end

-- A guest by the name an officer typed (issue #340): a pug is often from outside the guild, so not in the
-- guild roster's picker. "Name" or "Name-Realm"; the class is the one this client knows for them, else
-- the default. Returns true, or false and why.
function CoreManager:AddGuestByName(text, role, coreName)
    local name = strtrim(tostring(text or ""))
    if #name < 2 or #name > GUEST_TEXT or name:find("[%c|]") then return false, L["Type the guest's name."] end
    local key = GuildOS:RealmBound() and GuildOS:KeyOfRosterName(name) or GuildOS:GetPlayerKey(name)
    if not key then return false, L["Type the guest's name."] end
    local known = GuildOS.db.members and GuildOS.db.members[key]
    local cls = known and self.CLASS_ROLES[known.class] and known.class or "WARRIOR"
    return self:AddGuest(key, { name = name:match("^([^-]+)") or name, class = cls, role = role }, coreName, false)
end

-- Who plays the core's night: its members and its guests, by key (a member's record wins).
function CoreManager:RaidRoster(coreName)
    local out = {}
    local core = coreNamed(self, coreName)
    if not core then return out end
    for key, rec in pairs(type(core.guests) == "table" and core.guests or {}) do out[key] = rec end
    for key, rec in pairs(type(core.members) == "table" and core.members or {}) do out[key] = rec end
    return out
end

-- The raid session of a core ended on this client (RaidTracker:EndSession, `session`): its guests leave
-- here, but those marked to stay, and every officer's client that ends it tells the others, as the
-- night's end. Only one client was told before (the one the raid's end awards pick), and when that one
-- ran no addon nobody heard: the officers who did not raid kept the night's guests for good. An
-- officer's session ends for reasons of its own (left early, a disconnect past the hold, another zone)
-- while the raid goes on for the others: a client still raiding that core lets it pass, and each end
-- takes off only the guests put on before it, so N officers ending one night take each guest off once
-- and a late one never takes off a guest of the next night (OnGuestsSync). Returns how many.
function CoreManager:EndNight(coreName, session)
    local core, name = coreNamed(self, coreName)
    if not (core and type(core.guests) == "table") then return 0 end
    local gone = {}
    for key, rec in pairs(core.guests) do
        if type(rec) ~= "table" or not rec.stay then gone[#gone + 1] = key end
    end
    table.sort(gone)
    for _, key in ipairs(gone) do core.guests[key] = nil end
    local endAt = math.floor(GuildOS.Finite(type(session) == "table" and session.endTime) or GetServerTime())
    if #gone > 0 then publishGuests(self, name, nil, gone, endAt) end
    return #gone
end

-- Whether this client is in a raid session of the core `coreName` now (the hold after leaving included).
local function raidingCore(coreName)
    local RT = GuildOS.RaidTracker
    local raid = RT and RT.currentRaid
    return type(raid) == "table" and raid.groupTag == coreName
end

-- Whoever is on a Discord core with no record from the Discord is a guest (issue #340): an officer put
-- them there before the core was the Discord's, or a client from before sent them. They become guests
-- marked to stay, record and all, so nobody disappears. Runs at login and after every Discord list.
-- At most GUEST_MAX guests: whoever is past it, in key order, stays a member, as before.
function CoreManager:MigrateGuests(coreName)
    local names = coreName and { coreName } or self:GetSortedNames()
    local moved = 0
    for _, name in ipairs(names) do
        local core = GuildOS.db.cores[name]
        if type(core) == "table" and core.discordTag and type(core.members) == "table" and self:IsLinked() then
            local guests = self:GetGuests(name)
            local keys = {}
            for key in pairs(core.members) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, key in ipairs(keys) do
                local rec = core.members[key]
                if (type(rec) ~= "table" or rec.src ~= "discord") and (guests[key] or countOf(guests) < GUEST_MAX) then
                    rec = type(rec) == "table" and rec or {}
                    local guest = guestRecord(self, key, rec, true)
                    -- A key no guest can have stays a member: nobody disappears.
                    if guest then
                        guest.at, guest.migrated = GetServerTime(), true
                        guests[key] = guest
                        core.members[key] = nil
                        moved = moved + 1
                    end
                end
            end
        end
    end
    return moved
end

-- Another officer's change to a core's guests (the handler checked the officer): lands on the core
-- holding its tag here, else the one of its name; makes no core. Puts and takes off only the guests it
-- names, so this client's own stay. Returns whether anything changed.
local function guestKey(key)
    return type(key) == "string" and key ~= "" and #key <= GUEST_KEY and GuildOS:LocalMemberKey(key) or nil
end

local function tagHolder(tag)
    for name, core in pairs(GuildOS.db.cores) do
        if type(core) == "table" and core.discordTag == tag then return name end
    end
    return nil
end

function CoreManager:OnGuestsSync(d)
    if type(d) ~= "table" then return false end
    local name = type(d.tag) == "string" and d.tag ~= "" and tagHolder(d.tag) or d.coreName
    local core = type(name) == "string" and GuildOS.db.cores[name]
    if type(core) ~= "table" then return false end
    local guests = self:GetGuests(name)
    local changed, n = false, 0
    for key, rec in pairs(type(d.put) == "table" and d.put or {}) do
        n = n + 1
        if n > GUEST_MAX then break end
        local k = guestKey(key)
        local guest = k and type(rec) == "table" and guestRecord(self, k, rec, rec.stay == true)
        if guest and not (type(core.members) == "table" and core.members[k])
            and (guests[k] or countOf(guests) < GUEST_MAX) then
            guests[k] = guest
            changed = true
        end
    end
    -- The night's end on another client, while this one still raids that core: its guests stay here.
    local ended = d.ended == true
    local gone = type(d.gone) == "table" and not (ended and raidingCore(name)) and d.gone or {}
    -- Each end takes off the guests put on before it, once: another officer's end of the same night, or
    -- one heard late, leaves a guest put on since (the next night's) alone. A client from before sends no
    -- `endAt`: the end is when it arrives.
    local endAt = ended and (GuildOS.Finite(d.endAt) or GetServerTime()) or nil
    for i = 1, math.min(#gone, GUEST_MAX) do
        local k = guestKey(gone[i])
        if k and guests[k] and not (endAt and (tonumber(guests[k].at) or 0) > endAt) then
            guests[k] = nil
            changed = true
        end
    end
    return changed
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
    -- On a Discord core of a linked guild, who joins is the Discord's: the applicant plays as a guest
    -- who stays until they are on the Discord's list (issue #340).
    if self:TakesGuests(coreName) then
        self:AddGuest(playerKey, su, coreName, true)
    else
        self:AddMember(playerKey, su, coreName)
    end
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
-- and the core screen leaves the section out (issue #92). Retail's are Raid Tools' (below).
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

    -- Titulars only: a reserve is on the core, not in its composition (issue #212).
    local bench = 0
    for _, m in pairs(members) do
        if type(m) == "table" and m.status == "bench" then
            bench = bench + 1
        else
            total = total + 1
            local cls = (m.class or "WARRIOR"):upper()
            classCount[cls] = (classCount[cls] or 0) + 1
            classPresent[cls] = true
            local role = m.role or "rdps"
            if roleCounts[role] ~= nil then roleCounts[role] = roleCounts[role] + 1 end
        end
    end

    local coveredBuffs = {}
    for cls in pairs(classPresent) do
        for _, b in ipairs(CLASS_BUFFS_MAP[cls] or {}) do
            coveredBuffs[b] = true
        end
    end

    local buffStatus = {}
    local RT = GuildOS.RaidTools
    if GuildOS.Client.isRetail and RT then
        -- Retail's are Raid Tools' Midnight buffs, one class each, named by the client: one list
        -- for both screens (issue #184).
        for i, b in ipairs(RT:ResolveCoverage(RT.BUFFS, classCount)) do
            buffStatus[#buffStatus + 1] = { name = b.name, covered = b.covered, source = next(RT.BUFFS[i].classes) }
        end
    end
    for _, entry in ipairs(IMPORTANT_BUFFS_LIST) do
        buffStatus[#buffStatus + 1] = {
            name    = entry.name,
            covered = coveredBuffs[entry.name] == true,
            source  = entry.src,
        }
    end

    return {
        total      = total,
        bench      = bench,
        classCount = classCount,
        roleCounts = roleCounts,
        buffStatus = buffStatus,
    }
end

-- The open slots of a core (issue #212): per role, its target for the core's size less the titulars
-- playing it; the total is what the size still has room for, whatever the roles say.
function CoreManager:OpenSlots(coreName)
    local size = self:GetRaidSize(coreName)
    local T = self:RaidTargets(size)
    local comp = self:GetComposition(coreName)
    local out = { total = math.max(0, size - comp.total) }
    for _, role in ipairs({ "tank", "healer", "mdps", "rdps" }) do
        out[role] = math.max(0, (T[role] or 0) - (comp.roleCounts[role] or 0))
    end
    return out
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
        role  = self:RoleFor(cls, role, playerKey),   -- no pick: my spec's on retail (#184)
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
-- The name a Discord core has here: the Discord's, cut on a character to the 48 bytes a core's name
-- has (the site allows 32 UTF-16 characters, up to 96 bytes), its trailing spaces off.
local DISCORD_NAME_MAX = 128   -- bytes of a Discord name read at all
local function discordNameHere(name)
    if type(name) ~= "string" or name == "" or #name > DISCORD_NAME_MAX then return nil end
    local cut = strtrim(GuildOS:Utf8Cut(name, CORE_NAME_LIMIT))
    return cut ~= "" and cut or nil
end

local function coreFor(self, c)
    local want = discordNameHere(c.name) or c.name
    local held
    for _, name in ipairs(self:GetSortedNames()) do
        if GuildOS.db.cores[name].discordTag == c.tag then
            if name == want then return name, false end
            held = held or name
        end
    end
    if held then return held, false end
    local found
    for _, name in ipairs(self:GetSortedNames()) do
        -- A core linked to another Discord core is that one's, whatever its name (#138).
        if not GuildOS.db.cores[name].discordTag and CoreManager.Slug(name) == c.tag then
            if name == want then return name, false end
            found = found or name
        end
    end
    if found then return found, false end
    local name = CoreManager.Slug(c.name) == c.tag and want or c.tag
    if GuildOS.db.cores[name] then name = c.tag end
    local n = 2
    while GuildOS.db.cores[name] do
        name = string.format("%s-%d", c.tag, n)                 -- a core name, not a member key
        n = n + 1
    end
    newCore(name)
    return name, true
end

-- The Discord renamed a core (#339): the game's follows on the next import, nights, points and rule
-- along (moveCore). The link is the tag, so the core is the same one whatever it is called; the name
-- follows only when the game's core carried the Discord's previous name, so a core named by its tag
-- (a name the Discord reused) or linked by hand under another name keeps it, and only to a name no
-- other core here has. `discordName` is remembered for the next time; a core holding a tag with none
-- remembered (imported before it was kept) follows a Discord name that no longer reduces to its tag,
-- unless named by its tag. Returns the core's name now.
local function followName(self, name, discordName)
    local core = GuildOS.db.cores[name]
    -- A name past 48 bytes is followed cut (discordNameHere), never left behind for being long.
    discordName = discordNameHere(discordName)
    if type(core) ~= "table" or not discordName then return name end
    local before = core.discordName
    local follow = before and before ~= discordName and name == before
    -- A core imported by a version from before `discordName` (#339) has none: the first package after
    -- the update may already carry the new name, and recording it alone left this client on the old one
    -- forever while an officer who saw both followed. The tag is the Discord name the core was made
    -- with, reduced: a Discord name that still reduces to it is the one the core had, nothing changed
    -- there, so an officers' "Nucleo Alfa" adopted by its slug keeps its name; one that no longer does
    -- was renamed on Discord, and the core follows, whatever 1.24.0 called it here (the Discord's old
    -- name, an officers' name of the same slug). Never when named by its tag (a name the Discord
    -- reused, "alfa-2"), nor linked by hand (`linkAt`, LinkDiscord). The Discord name is recorded either
    -- way, so the next rename follows by the rule above.
    local legacy = not before and core.discordTag and not core.linkAt and name ~= discordName
    if legacy then
        local tag = core.discordTag
        follow = name ~= tag and CoreManager.Slug(discordName) ~= tag
            and not (name:sub(1, #tag + 1) == tag .. "-" and name:sub(#tag + 2):match("^%d+$"))
    end
    -- A legacy core kept under the officers' name ("Nucleo Alfa" for the Discord's "Núcleo Alfa"):
    -- nothing is recorded, so a later rename on Discord is judged by the same rule and followed by every
    -- officer, whichever package each saw first. Recorded, an officer who saw the old name first would
    -- read the next one as "not my name, not followed" while one who saw the new name first followed.
    if legacy and not follow then return name end
    -- A new name another core here has: neither followed nor recorded, so a later package tries again
    -- once that name is free (recorded, it read as already followed).
    if follow and GuildOS.db.cores[discordName] then return name end
    core.discordName = discordName
    if follow then
        moveCore(name, discordName)
        return discordName
    end
    return name
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
        role  = self:RoleFor(cls, SITE_ROLES[m.slot] and m.slot or nil, key),
        note  = "",
        src   = "discord",
        status = m.status == "bench" and "bench" or nil,
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

----------------------------------------------------------------------
-- Elenco e grupos (issue #352; guildos-web specs/086). A Discord core can have one parent, its
-- elenco: a 25 split into Karazhan groups of 10, a 40 into two 20s. The GOSCORE1 says it per core as
-- `parent`, the elenco's tag ("" or absent: none), and `pool`, "own" (the default) or "parent" (the
-- group's points land in the elenco's pool). Kept on the core by tag (`discordParent`), so the elenco
-- is whichever core holds that tag here, renamed or linked by hand; a tag no core here holds yet is no
-- elenco until it arrives. `pointsPool` is "parent" or nil (own). A tree of at most three layers
-- (40 -> 20 -> 10), never a cycle: a walk up stops at TREE_DEPTH, or at a core seen already.
----------------------------------------------------------------------
local TREE_DEPTH = 3

-- The elenco and pool a site's core entry (or another officer's list) says, checked: a tag of a few
-- dozen bytes that is not the core's own, and "parent" or nothing.
local function treeOf(c)
    local parent = c.parent
    if type(parent) ~= "string" or parent == "" or #parent > 64 or parent == c.tag then parent = nil end
    return { parent = parent, pool = (parent and c.pool == "parent") and "parent" or nil }
end

-- The elenco of the core `name` here, or nil: none, or its tag held by no core here yet.
function CoreManager:ParentOf(name)
    local core = GuildOS.db.cores and GuildOS.db.cores[name]
    local tag = type(core) == "table" and core.discordTag and core.discordParent
    if type(tag) ~= "string" then return nil end
    local parent = holderOf(tag)
    if parent == name then return nil end
    return parent
end

-- Whether the core `a` is an elenco of the core `b`, its parent or the parent's.
function CoreManager:IsAncestor(a, b)
    local seen, cur = { [b] = true }, self:ParentOf(b)
    for _ = 1, TREE_DEPTH do
        if not cur or seen[cur] then return false end
        if cur == a then return true end
        seen[cur] = true
        cur = self:ParentOf(cur)
    end
    return false
end

-- The groups of the elenco `name` here, sorted by name.
function CoreManager:GroupsOf(name)
    local out = {}
    for _, other in ipairs(self:GetSortedNames()) do
        if other ~= name and self:ParentOf(other) == name then out[#out + 1] = other end
    end
    return out
end

-- The guild's cores as the cores screen lists them: every elenco followed by its groups, each with how
-- deep it sits ({ name, depth }). A core with no elenco and no groups is listed as always, by name.
function CoreManager:SortedTree()
    local out, placed = {}, {}
    local function add(name, depth)
        if placed[name] then return end
        placed[name] = true
        out[#out + 1] = { name = name, depth = depth }
        if depth < TREE_DEPTH then
            for _, child in ipairs(self:GroupsOf(name)) do add(child, depth + 1) end
        end
    end
    for _, name in ipairs(self:GetSortedNames()) do
        if not self:ParentOf(name) then add(name, 0) end
    end
    -- A core whose walk up loops (never a tree the site sends) is under no root: listed at the top.
    for _, name in ipairs(self:GetSortedNames()) do add(name, 0) end
    return out
end

-- Whether the core `name` is a group whose points go to its elenco's pool (`pool` "parent").
function CoreManager:UsesParentPool(name)
    local core = GuildOS.db.cores and GuildOS.db.cores[name]
    return type(core) == "table" and core.pointsPool == "parent" and self:ParentOf(name) ~= nil
end

-- The core whose pool the points of the core `name` are: its own, or for a group with the elenco's pool
-- the elenco's (and up, when the elenco itself uses its parent's). "" and nil stay as they are.
function CoreManager:PoolOwner(name)
    if type(name) ~= "string" or name == "" then return name end
    local seen, cur = {}, name
    for _ = 1, TREE_DEPTH do
        seen[cur] = true
        if not self:UsesParentPool(cur) then return cur end
        local parent = self:ParentOf(cur)
        -- A cycle (never a tree the site sends) is no elenco's pool: each core keeps its own, never
        -- another's of the loop.
        if seen[parent] then return name end
        cur = parent
    end
    return cur
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
local function olderThanMark(at)
    local mark = GuildOS.db.discordAt
    return mark ~= nil and (at == nil or at < mark)
end
local function isStale(at)
    return olderThanMark(at)
end
-- An officer chose to create cores in game again (#339): a package this client received by then is older
-- than that choice. `received` is when this client got it, on the realm's clock (the inbox's ack, another
-- officer's `seenAt`), never the site's `at`: the site stamps a package with when its cores last changed,
-- the same for a fresh copy of unchanged cores, which then read as older until a core changed on Discord.
-- A code pasted is received now, after any choice this client knows (`pasted`). A release is never older
-- for it (it links nothing): see the core.roster handler.
local function beforeRelease(received, pasted)
    local link = GuildOS.db.coreLink
    local off = type(link) == "table" and link.releasedAt
    if not off or pasted then return false end
    return received == nil or received <= off
end

-- The guild is linked from now, by its own import or another officer's list (#339). `fresh` is how
-- new the package is, when known.
local function linkOn(fresh)
    local link = linkRec()
    local now = GetServerTime()
    if not link.since then link.since, link.seenAt = now, fresh or now end
    if fresh and fresh > (link.seenAt or 0) then link.seenAt = math.min(fresh, now) end
end

-- The guild's cores are the officers' again: an empty package (the federation switched off, or no
-- core left on Discord), the last Discord core given back, or an officer's choice.
local function linkOff()
    local link = linkRec()
    link.since, link.seenAt, link.toldFor = nil, nil, nil
end

-- A guild that imported before the link was kept (#339): a core holding a tag is the Discord's, so the
-- guild is linked, from now.
function CoreManager:MigrateLink()
    if not self:IsLinked() and self:HasDiscordCores() then linkOn() end
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
    core.discordTag, core.discordWaiting, core.linkAt, core.importedAt = nil, nil, nil, nil
    core.discordParent, core.pointsPool = nil, nil   -- the elenco is the Discord's too (#352)
    -- Whoever MigrateGuests made a guest is a member of the officers' core again, as before the link; a
    -- guest an officer added as one stays a guest. An officer on an earlier build of this version sent
    -- the migrated without `migrated`: they are the guests marked to stay that nobody added (AddGuest
    -- always says who, `by`; a member's record made a guest has none).
    if type(core.guests) == "table" then
        core.members = type(core.members) == "table" and core.members or {}
        for key, rec in pairs(core.guests) do
            if type(rec) == "table" and (rec.migrated or (rec.stay and rec.by == nil)) then
                if not core.members[key] then
                    core.members[key] = { name = rec.name, class = rec.class, role = rec.role, note = rec.note or "" }
                end
                core.guests[key] = nil
            end
        end
    end
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
    local core = GuildOS.db.cores[coreName] or newCore(coreName)   -- the Discord's own, linked or not
    local from = holderOf(tag)
    if from and from ~= coreName then
        local old, members = GuildOS.db.cores[from], self:GetMembers(coreName)
        for key, rec in pairs(type(old.members) == "table" and old.members or {}) do
            if type(rec) == "table" and rec.src == "discord" then
                -- Titular or reserve rides with the Discord's record (issue #212).
                if type(members[key]) == "table" then
                    members[key].src, members[key].status = "discord", rec.status
                else
                    members[key] = rec
                end
            end
        end
        core.discordWaiting = old.discordWaiting
        core.discordParent, core.pointsPool = old.discordParent, old.pointsPool   -- the elenco rides with the tag (#352)
        self:SetRaidSize(coreName, self:GetRaidSize(from))
        release(from, true)
    end
    core.discordTag, core.linkAt = tag, linkAt
    local list = {}
    for key, rec in pairs(self:GetMembers(coreName)) do
        if type(rec) == "table" and rec.src == "discord" then
            list[#list + 1] = { key = key, name = rec.name, class = rec.class, slot = rec.role, status = rec.status }
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
-- `tree` is its elenco and pool (treeOf, #352): nil leaves them as they are (a list from an officer's
-- client from before them, which says nothing of either).
-- Returns how many joined, left and were taken over.
function CoreManager:SyncDiscordCore(coreName, list, size, tag, waiting, tree)
    for name, other in pairs(GuildOS.db.cores) do
        if name ~= coreName and type(other) == "table" and other.discordTag == tag then release(name, true) end
    end
    local core = self:GetCore(coreName)
    if not core then return 0, 0, 0 end
    core.discordTag = tag
    core.discordWaiting = namesOnly(waiting)
    if type(tree) == "table" then core.discordParent, core.pointsPool = tree.parent, tree.pool end
    core.importedAt = GetServerTime()   -- when this client last took the Discord's list for it (#347)
    if tonumber(size) then self:SetRaidSize(coreName, tonumber(size)) end
    local members, incoming, added, removed, adopted = self:GetMembers(coreName), {}, 0, 0, 0
    for _, m in ipairs(list) do
        local key = type(m) == "table" and localKey(m.key)
        if key then
            incoming[key] = true
            local rec = members[key]
            -- A guest the Discord now has is a member: one or the other, never both (issue #340).
            if type(core.guests) == "table" then core.guests[key] = nil end
            if type(rec) ~= "table" then
                members[key] = discordRecord(self, key, m)
                added = added + 1
            else
                if rec.src ~= "discord" then
                    rec.src = "discord"
                    adopted = adopted + 1
                end
                -- Titular or reserve is the Discord's, as who is on the core (issue #212).
                rec.status = m.status == "bench" and "bench" or nil
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
    local core = GuildOS.db.cores[coreName]
    if not core and tag ~= false and coreName ~= "" then core = newCore(coreName) end
    if type(core) ~= "table" then return 0, 0 end
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
-- On retail the realm is the guild's home realm, normalized, whichever connected realm this
-- character is on: the site keeps the guild by it (issue #182).
-- The second answer says which: "guild", or "realm" for a guild of this name on another realm, which
-- is also how another game's package reads here (a pasted code, #347).
local function notOurs(data)
    local mine = GetGuildInfo("player")
    if type(data.guild) ~= "string" or not mine or data.guild:lower() ~= mine:lower() then return tostring(data.guild), "guild" end
    local other
    if GuildOS.Client.isRetail then
        other = type(data.realm) == "string" and data.realm:gsub("[%s%-]", "") ~= GuildOS:GuildRealm()
    elseif GuildOS.Client.isAnniversary then
        other = data.realm and data.realm ~= GetRealmName()
    end
    if other then return tostring(data.guild) .. " (" .. tostring(data.realm) .. ")", "realm" end
    return nil
end

-- Imports a decoded GOSCORE1 into this guild; `at` is how new it is (the site's time, else the inbox's). Returns every
-- Discord core as { name, added, removed, adopted, list, size, tag, waiting, at, linkAt, quiet } (quiet when
-- nothing on it changed; `released` and tag false for a core the Discord no longer sends), and how many
-- people the site had no character for. When the payload is not this guild's: nil, and whose it is.
-- When this client already has newer lists, from another officer: nothing, and true.
-- `received` is when this client got it (beforeRelease); nil is now, as a code pasted.
function CoreManager:ImportFromSite(data, at, received)
    if type(data) ~= "table" or type(data.cores) ~= "table" then return nil end
    local other = notOurs(data)
    if other then return nil, other end
    if at and isStale(at) then return {}, 0, true end
    if received ~= nil and beforeRelease(received) then return {}, 0, true end
    local cores, sent, catalog = {}, {}, {}
    for _, c in ipairs(data.cores) do
        if type(c) == "table" and type(c.tag) == "string" and c.tag ~= "" and type(c.name) == "string"
            and type(c.members) == "table" then
            catalog[#catalog + 1] = { tag = c.tag, name = c.name }
            local name, created = coreFor(self, c)
            name = followName(self, name, c.name)
            sent[c.tag] = name
            local linked = GuildOS.db.cores[name].discordTag == c.tag
            -- A package from before #352 says nothing of either: no elenco, its own pool.
            local tree = treeOf(c)
            local added, removed, adopted = self:SyncDiscordCore(name, c.members, c.size, c.tag, c.waiting, tree)
            cores[#cores + 1] = {
                name = name, added = added, removed = removed, adopted = adopted,
                list = c.members, size = self:GetRaidSize(name), tag = c.tag, waiting = namesOnly(c.waiting), at = at,
                linkAt = GuildOS.db.cores[name].linkAt, discordName = c.name,
                parent = tree.parent or "", pool = tree.pool or "own",
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
    -- Linked while the site sends cores; a package with none gives creating back to the officers (#339).
    if #catalog > 0 then linkOn() else linkOff() end
    replayWaiting()
    return cores, tonumber(data.unlinked) or 0
end

-- Why the inbox's cores were not imported, said once per guild until the reason changes (#138): an
-- import that says nothing looks exactly like one that is not working.
local function tellOnce(key, text)
    if GuildOS.db.discordTold == key then return end
    GuildOS.db.discordTold = key
    GuildOS:Print(text)
end

-- One GOSCORE1 into this guild, from the inbox or pasted by an officer (issue #347): one path, so both
-- import alike. `ackAt` is when the inbox was written (nil for a pasted code: the site dates every
-- package it gives to copy). Prints one line when something changed, and keeps every core's list in
-- the session for SendDiscordChanges. Returns what ImportFromSite returns: the cores, how many people the
-- site had no character for and whether it was older than what this client has; or nil, whose it is
-- and why ("guild", "realm"); or nil, nil, "older" for a package from before the site dated them, once
-- this client has one it dated. `pasted`: an officer pasted it now (received now, beforeRelease).
function CoreManager:ImportPackage(data, ackAt, pasted)
    local other, why = notOurs(data)
    if other then return nil, other, why end
    -- The site's time for the package when it sends one (guildos-web #126): one clock for every officer.
    -- From the first, a PC's clock no longer counts: not the mark it left (one running ahead would hold
    -- back every site package), nor an inbox from before (a companion stopped since the site dated them).
    local siteAt = tonumber(data.at)
    if siteAt and not GuildOS.db.discordSiteAt then GuildOS.db.discordAt, GuildOS.db.discordSiteAt = nil, true end
    if not siteAt and GuildOS.db.discordSiteAt then return nil, nil, "older" end
    -- Undated altogether (a pasted code from a site before #126): older than any list this client has.
    -- An officer's choice to create in game again is no list: a code pasted after it is received after it.
    if not siteAt and not ackAt and (GuildOS.db.discordAt or (not pasted and (GuildOS.db.coreLink or {}).releasedAt)) then
        return nil, nil, "older"
    end
    local wasLinked = self:IsLinked()
    if beforeRelease(sane(ackAt), pasted) then return {}, 0, true end
    local cores, unlinked, stale = self:ImportFromSite(data, sane(siteAt or ackAt))
    if not cores then return nil end
    GuildOS.db.discordTold = nil
    if stale then return cores, unlinked, stale end
    -- When this client last took the guild's cores from the site, for the upload's receipt (#347), and how
    -- fresh they are (#339): when the companion last wrote the inbox, or now for a code just copied.
    local link = linkRec()
    link.importedAt = GetServerTime()
    if self:IsLinked() then
        local fresh = sane(ackAt) or GetServerTime()
        if wasLinked then linkOn(fresh) else link.seenAt = fresh end
    end
    self:MigrateGuests()
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
    return cores, unlinked, false
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
    self:ImportPackage(data, at)
end

-- A GOSCORE1 an officer copied from the site and pasted into the roster box (issue #347), for a guild
-- where nobody runs the companion: checked and imported exactly as the inbox's (ImportPackage), and sent
-- to the officers online at once, as the inbox's is once the rank is known (the officer pasting is in
-- the game, so it is). Returns how many cores, nil and the line to show; or nil and why not.
function CoreManager:ImportPasted(raw)
    if not GuildOS:IsOfficer() then return nil, L["Only officers import the guild's cores."] end
    local data = GuildOS.CompanionImport and GuildOS.CompanionImport.ReadCores(raw)
    if not data then return nil, L["The cores code is damaged. Copy it again from guildos.me."] end
    local cores, other, why = self:ImportPackage(data, nil, true)
    if not cores then
        if why == "guild" then return nil, string.format(L["These cores are for %s, not this guild."], other) end
        if why == "realm" then return nil, string.format(L["These cores are for %s: another realm or another game."], other) end
        return nil, L["This client already has newer cores from Discord: that code is older."]
    end
    if why then return nil, L["This client already has newer cores from Discord: that code is older."] end
    self:SendDiscordChanges()
    local n = 0
    for _, c in ipairs(cores) do if not c.released then n = n + 1 end end
    return n, nil, string.format(L["Cores from Discord loaded: %d. The officers online get them too."], n)
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
            GuildOS.SyncService:Publish("core.roster", "discord", { coreName = c.name, tag = false, at = c.at, off = c.off,
                offAt = c.offAt })
        else
            GuildOS.SyncService:Publish("core.roster", "discordList", {
                coreName = c.name, list = c.list, size = c.size, tag = c.tag, waiting = c.waiting, at = c.at,
                linkAt = c.linkAt, discordName = c.discordName, seenAt = self:LinkSeenAt(),
                parent = c.parent, pool = c.pool,   -- the elenco (#352); a client from before ignores both
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
        waiting = core.discordWaiting, at = GuildOS.db.discordAt, linkAt = core.linkAt,
        parent = core.discordParent or "", pool = core.pointsPool or "own" }
    GuildOS.State.discordCores = pending
    self:SendDiscordChanges()
    return true
end

-- From OFFICER_START: a linked guild with no new package for QUIET_DAYS is told once (per package seen)
-- that its cores may be created in game again (spec 085's open question): the federation may have
-- been switched off with no companion left to bring the empty package. The panel offers the button.
function CoreManager:TellQuietLink()
    if not (self:IsLinkQuiet() and GuildOS:IsOfficer()) then return end
    local link = linkRec()
    local seen = self:LinkSeenAt()
    if link.toldFor == seen then return end
    link.toldFor = seen
    GuildOS:Print(string.format(L["No cores from Discord for %d days. If the guild no longer uses them, choose \"Create cores in game again\" in Raids > Cores."], QUIET_DAYS))
end

-- An officer gives the guild's cores back to the game (#339), as an empty package would: every
-- Discord core stays as it is, people and history, and is the officers' again; creating comes back.
-- The packages up to now are older than this choice, here and, by the releases sent, on every officer
-- online; a package the site makes later links the guild again. Returns false when not linked or
-- not an officer.
function CoreManager:CreateInGameAgain()
    if not (self:IsLinked() and GuildOS:IsOfficer()) then return false end
    local at = GuildOS.db.discordAt or GetServerTime()
    local now = GetServerTime()
    local pending = {}
    for _, name in ipairs(self:GetSortedNames()) do
        if GuildOS.db.cores[name].discordTag then
            release(name, false)
            pending[#pending + 1] = { name = name, released = true, tag = false, at = at, off = true, offAt = now }
        end
    end
    linkOff()
    linkRec().releasedAt = now
    GuildOS.State.discordCores = #pending > 0 and pending or nil
    self:SendDiscordChanges()
    if GuildOS.coresPanelRefresh then GuildOS.coresPanelRefresh() end
    return true
end

-- Whether a core's loot rule is the site's (#339, spec 085): in a linked guild, a Discord core's rule is
-- configured on guildos.me, and the site sends it with the raid's roster (GOSROST1 `lootRule`). While
-- the roster in hand carries one, the core's own rule and loot system are not changed in game.
function CoreManager:LootRuleFromSite(coreName)
    if not (self:IsLinked() and self:IsFromDiscord(coreName)) then return false end
    local roster = GuildOS.db and GuildOS.db.companionRoster
    return type(roster) == "table" and type(roster.lootRule) == "table"
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
        info.role = self:RoleFor(cls, info.role, playerKey)
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
        -- A core's own loot system and rule (issue #338).
        if env.act == "loot" then
            if GuildOS:IsOfficerByName(sender) and self:OnLootSync(env) and GuildOS.coresPanelRefresh then
                GuildOS.coresPanelRefresh()
            end
            return
        end
        -- A core's guests (issue #340): changes only, never a whole list.
        if env.act == "guests" then
            if GuildOS:IsOfficerByName(sender) and self:OnGuestsSync(d) and GuildOS.coresPanelRefresh then
                GuildOS.coresPanelRefresh()
            end
            return
        end
        if not discord and not d.members then return end
        if not GuildOS:IsOfficerByName(sender) then return end
        if discord then
            -- A list lands on the core holding its tag here, as the import's does; only a link moves a tag.
            local at, list = sane(d.at), env.act == "discordList"
            if list and (type(d.list) ~= "table" or type(d.tag) ~= "string" or d.tag == "") then return end
            -- Older than the newest this client applied, or received by the sender before an officer chose
            -- to create in game again (its `seenAt`; none from a client from before: older).
            local stale = isStale(at) or beforeRelease(sane(d.seenAt))
            -- A link to a tag no core here holds needs fresh lists: an older one would link a core the
            -- Discord has closed since.
            if list and (holderOf(d.tag) or not stale) then heardLink(self, d.coreName, d.tag, sane(d.linkAt)) end
            local giveBack = not list and d.tag == false
            if not (giveBack and olderThanMark(at) or not giveBack and stale) then
                if list then
                    local name = followName(self, (coreFor(self, { tag = d.tag, name = d.coreName })), d.discordName)
                    -- The elenco only from a client that says it (#352): one from before sends no `pool`.
                    local tree = d.pool ~= nil and treeOf(d) or nil
                    self:SyncDiscordCore(name, d.list, d.size, d.tag, d.waiting, tree)
                    linkOn(sane(d.seenAt))
                    self:MigrateGuests(name)
                    replayWaiting(name)
                else
                    self:ApplyDiscordChanges(d.coreName, d.add, d.remove, d.size, d.tag)
                    if d.tag == false then
                        -- An officer chose to create in game again: the lists up to then are older here too.
                        -- When it was chosen, on the realm's clock (`offAt`). A client from before sends only the
                        -- package's own time, the site's (when its cores last changed on Discord, often weeks
                        -- ago): taken as the choice, this client's own inbox acked before it would pass as newer
                        -- and link the guild again. Without `offAt` the choice is no older than its receipt here.
                        local offAt = sane(d.offAt) or GetServerTime()
                        if d.off == true and offAt then linkRec().releasedAt = math.max(offAt, linkRec().releasedAt or 0) end
                        if not self:HasDiscordCores() then linkOff() end
                    elseif type(d.tag) == "string" and d.tag ~= "" then
                        linkOn()
                    end
                end
                took(at)
            end
        else
            -- In a linked guild a roster for a core this client does not have makes none (#339).
            local core = self:GetCore(d.coreName)
            if core then
                core.members = GuildOS:LocalizeMemberTable(d.members)   -- this client's keys (#97)
                -- One person is never both: a client from before sends the whole roster, a migrated guest
                -- among its members; the member wins, and the guest record goes.
                for key in pairs(type(core.guests) == "table" and core.members or {}) do core.guests[key] = nil end
            end
        end
        if GuildOS.coresPanelRefresh then GuildOS.coresPanelRefresh() end
    end)
end
