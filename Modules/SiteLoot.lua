----------------------------------------------------------------------
-- Guild OS — SiteLoot
-- The raid's soft reserves, priorities and wishlists as the site sent them (GOSROST1 v6; CompanionImport
-- keeps them in db.siteLoot, already in this addon's own shapes), one entry per raid:
--
--   db.siteLoot = { at, raids = { [raidId] = { startsAt, instanceKey, difficulty, softres, prios, wishlists } } }
--
-- This module only answers "what does the site hold for the raid this client is in": the readers
-- (SoftRes, LootMaster, Wishlist) choose between that and the game's own tables, which nothing here
-- ever writes.
--
--   * Active: the raid the player is in is one of the entries (the same catalogue-key match the rest of
--     the addon uses, CompanionImport:RaidFor) and now is inside that raid's night window (LootRule's:
--     two hours before the start, eight after). Two raids of one guild in one window never share a sheet.
--     No match, and every reader uses the game's tables.
--   * ListsFromSite / PriosFromSite: "the site is the source" for the editors and the broadcasts. They
--     ignore the window and the raid and hold while the inbox was read in the last three days (R9), so an
--     inbox that stopped changing does not keep the game's editors locked for good.
----------------------------------------------------------------------
local SiteLoot = {}
GuildOS.SiteLoot = SiteLoot

local SITE_MAX_AGE = 3 * 86400

local function held()
    local s = GuildOS.db and GuildOS.db.siteLoot
    return type(s) == "table" and s or nil
end

local function raidsOf()
    local s = held()
    return s and type(s.raids) == "table" and s.raids or nil
end

-- The entry of the raid this client is in, and its id; nil when it is in none of them tonight.
function SiteLoot:ActiveRaid(now)
    local raids = raidsOf()
    if not raids or not GetInstanceInfo then return nil end
    local _, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local RT, Import, LR = GuildOS.RaidTracker, GuildOS.CompanionImport, GuildOS.LootRule
    local key = RT and instanceID and RT:RaidKeyOf(instanceID)
    if not (key and Import and LR) then return nil end
    now = now or GetServerTime()
    local list = {}
    for id, e in pairs(raids) do
        if type(e) == "table" then
            list[#list + 1] = { raidId = id, instanceKey = e.instanceKey, startsAt = e.startsAt, difficulty = e.difficulty }
        end
    end
    local id = Import:RaidFor(key, now, GuildOS.Client.isRetail and tonumber(difficultyID) or nil, list)
    local entry = id and raids[id]
    if entry and LR.InWindow(entry.startsAt, now) then return id, entry end
    return nil
end

-- Whether the player's raid is one the site sent loot for, tonight. `now` defaults to the server's clock,
-- the one LootRule:Night and the planned-raid match read.
function SiteLoot:Active(now)
    return self:ActiveRaid(now) ~= nil
end

-- What the site holds for the raid in hand, or nil when the client is in none of them.
function SiteLoot:Reserves()
    local _, e = self:ActiveRaid()
    return e and type(e.softres) == "table" and type(e.softres.items) == "table" and e.softres or nil
end

function SiteLoot:Prios()
    local _, e = self:ActiveRaid()
    return e and type(e.prios) == "table" and e.prios or nil
end

-- The table of every person the site has a list of in that raid, keyed as guildWishlists is.
function SiteLoot:Wishlists()
    local _, e = self:ActiveRaid()
    return e and type(e.wishlists) == "table" and e.wishlists or nil
end

function SiteLoot:WishlistOf(storeKey)
    local all = self:Wishlists()
    return all and all[storeKey] or nil
end

local function fresh()
    local s = held()
    local at = s and tonumber(s.at)
    return at ~= nil and time() - at <= SITE_MAX_AGE
end

-- The site is the source of this person's wishlist: some raid of its holds one, and the inbox is recent.
function SiteLoot:ListsFromSite(storeKey)
    local raids = fresh() and raidsOf()
    for _, e in pairs(raids or {}) do
        if type(e) == "table" and type(e.wishlists) == "table" and e.wishlists[storeKey] ~= nil then return true end
    end
    return false
end

-- The site is the source of the officers' priorities: some raid of its sent some, and the inbox is recent.
function SiteLoot:PriosFromSite()
    local raids = fresh() and raidsOf()
    for _, e in pairs(raids or {}) do
        if type(e) == "table" and type(e.prios) == "table" then return true end
    end
    return false
end
