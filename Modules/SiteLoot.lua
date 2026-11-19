----------------------------------------------------------------------
-- Guild OS — SiteLoot
-- The raid's soft reserves, priorities and wishlists as the site sent them (GOSROST1 v6; CompanionImport
-- keeps them already in this addon's own shapes), one entry per raid:
--
--   entry = { startsAt, instanceKey, instanceKeys?, difficulty, softres, prios, priosHidden?, wishlists }
--
-- Every entry of the last inbox read is in memory (CompanionImport:SiteRaids, rebuilt from Inbox.lua at each
-- login); the ones whose night has begun are also saved (db.siteLoot = { raids = { [raidId] = entry } }), so a
-- /reload in the middle of a night keeps them after the site stops serving the raid. This module reads both.
--
-- It only answers "what does the site hold for the raid this client is in": the readers (SoftRes, LootMaster,
-- Wishlist) choose between that and the game's own tables, which nothing here ever writes.
--
--   * Active: the raid the player is in is one of the entries and now is inside that raid's night window
--     (LootRule's: two hours before the start, eight after). The raid is the one RaidTracker stamped on the
--     session when the group zoned in (it survives a /reload), so two groups of one guild in the same
--     instance, half an hour apart, each keep their own sheet for the whole night. A stamped raid the site
--     sent no loot for has no sheet: the game's tables, never another raid's. Only a session with no stamp
--     at all takes the nearest start (CompanionImport:RaidFor over every place of each raid, ties by start
--     and then raidId). No match, and every reader uses the game's tables.
--   * ListInForce / ListsFromSite / PriosFromSite: "the site is the source", for the wishlist editor and the
--     lines that say so. They ignore whether the player is in the raid, and hold only (R18) while the
--     companion's own stamp (GuildOSInboxAck.at, the last answer it had from the site, rewritten at least
--     hourly while it runs) is three days old or less, read live: a companion turned off gives the game its
--     editor back within three days, however often the old Inbox.lua is read again. A missing or broken
--     stamp is no source at all. And only (R20) for raids whose every place this client can stamp: a raid
--     whose map id nobody has yet never uses the site's data, so it locks nothing either.
----------------------------------------------------------------------
local SiteLoot = {}
GuildOS.SiteLoot = SiteLoot

local SITE_MAX_AGE = 3 * 86400

-- Every entry, the saved ones and the ones in memory (the fresher wins), by raidId; nil with none.
local function raidsOf()
    local out, any = {}, false
    local s = GuildOS.db and GuildOS.db.siteLoot
    for id, e in pairs(type(s) == "table" and type(s.raids) == "table" and s.raids or {}) do
        if type(e) == "table" then out[id], any = e, true end
    end
    local Import = GuildOS.CompanionImport
    for id, e in pairs(Import and Import.SiteRaids and Import:SiteRaids() or {}) do
        if type(e) == "table" then out[id], any = e, true end
    end
    return any and out or nil
end

-- The entry of the raid this client is in, and its id; nil when it is in none of them tonight.
function SiteLoot:ActiveRaid(now)
    local raids = raidsOf()
    local RT, Import, LR = GuildOS.RaidTracker, GuildOS.CompanionImport, GuildOS.LootRule
    if not (raids and Import and LR) then return nil end
    now = now or GetServerTime()
    -- The raid the session was stamped with at zone-in, when the site sent an entry for it.
    local stamped = RT and RT.currentRaid and RT.currentRaid.raidId
    if stamped then
        local own = raids[stamped]
        if type(own) == "table" and LR.InWindow(own.startsAt, now) then return stamped, own end
        return nil   -- no entry, or its night is over: never another raid's sheet
    end
    if not GetInstanceInfo then return nil end
    local _, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local key = RT and instanceID and RT:RaidKeyOf(instanceID)
    if not key then return nil end
    -- No stamp: the nearest start, with the candidates in a fixed order so a tie never depends on pairs().
    local list = {}
    for id, e in pairs(raids) do
        list[#list + 1] = { raidId = id, instanceKey = e.instanceKey, instanceKeys = e.instanceKeys,
            startsAt = tonumber(e.startsAt) or 0, difficulty = e.difficulty }
    end
    table.sort(list, function(a, b)
        if a.startsAt ~= b.startsAt then return a.startsAt < b.startsAt end
        return a.raidId < b.raidId
    end)
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

-- Whether tonight's priorities are the site's and its holder core keeps them from its members (R21): then no
-- line in the raid's chat may name a place of them.
function SiteLoot:PriosHidden()
    local _, e = self:ActiveRaid()
    return e ~= nil and type(e.prios) == "table" and e.priosHidden == true
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

-- How old the companion's last answer from the site is, in seconds, by its own stamp; nil when there is no
-- stamp, or one that is not a plain number (a companion that does not own this client's folder writes none).
local function sourceAge()
    local Import = GuildOS.CompanionImport
    local ack = _G.GuildOSInboxAck
    if not (Import and type(ack) == "table" and type(ack.at) == "number") then return nil end
    local at = GuildOS.Finite(Import:Ack())
    return at and time() - at or nil
end

-- Whether the site's word on lists still stands: the companion answered from the site in the last three days.
local function fresh()
    local age = sourceAge()
    return age ~= nil and age <= SITE_MAX_AGE
end

-- Whether this client can stamp a session with every place of the entry (R20): else the site's data is never
-- used there, and the entry says nothing about the source of anybody's list.
local function stampable(e)
    local RT = GuildOS.RaidTracker
    if not (RT and RT.MakesKey and RT:MakesKey(e.instanceKey)) then return false end
    for _, k in ipairs(type(e.instanceKeys) == "table" and e.instanceKeys or {}) do
        if not RT:MakesKey(k) then return false end
    end
    return true
end

-- The entries that speak for the source now, soonest first (by start, then raidId): fresh, stampable, and in
-- their night or still to come.
local function speaking(now)
    local raids = fresh() and raidsOf()
    local LR = GuildOS.LootRule
    local out = {}
    if not (raids and LR) then return out end
    for id, e in pairs(raids) do
        local startsAt = tonumber(e.startsAt)
        if startsAt and (LR.InWindow(startsAt, now) or now < startsAt) and stampable(e) then
            out[#out + 1] = { id = id, startsAt = startsAt, entry = e }
        end
    end
    table.sort(out, function(a, b)
        if a.startsAt ~= b.startsAt then return a.startsAt < b.startsAt end
        return a.id < b.id
    end)
    return out
end

-- The site's list in force for this person (R23): the one of the soonest raid, in its night or still to come,
-- that holds their key. { name, class, wishlist = { {itemId, order, isOffspec} } }, or nil.
function SiteLoot:ListInForce(storeKey, now)
    for _, s in ipairs(speaking(now or GetServerTime())) do
        local lists = s.entry.wishlists
        if type(lists) == "table" and type(lists[storeKey]) == "table" then return lists[storeKey] end
    end
    return nil
end

-- The site is the source of this person's wishlist: some raid of its, tonight or to come, holds one.
function SiteLoot:ListsFromSite(storeKey, now)
    return self:ListInForce(storeKey, now) ~= nil
end

-- Some raid of the site's, tonight or to come, plays by the site's priorities (R22: the game's prio editor
-- stays the game's, and says that those nights use the site's).
function SiteLoot:PriosFromSite(now)
    for _, s in ipairs(speaking(now or GetServerTime())) do
        if type(s.entry.prios) == "table" then return true end
    end
    return false
end
