----------------------------------------------------------------------
-- Guild OS — SiteLoot
-- The raid's soft reserves, priorities and wishlists as the site sent them (GOSROST1 v6; CompanionImport
-- keeps them in db.siteLoot, already in this addon's own shapes). This module only answers "what does
-- the site hold for tonight": the readers (SoftRes, LootMaster, Wishlist) choose between that and the
-- game's own tables, which nothing here ever writes.
--
--   * Active: the night's window is LootRule's own (two hours before the start, eight after). Outside
--     it every reader uses the game's tables.
--   * ListsFromSite / PriosFromSite: "the site is the source" for the editors and the broadcasts. They
--     ignore the window and hold while the inbox was read in the last three days (R9), so an inbox that
--     stopped changing does not keep the game's editors locked for good.
----------------------------------------------------------------------
local SiteLoot = {}
GuildOS.SiteLoot = SiteLoot

local SITE_MAX_AGE = 3 * 86400

local function held()
    local s = GuildOS.db and GuildOS.db.siteLoot
    return type(s) == "table" and s or nil
end

-- Whether `now` (default: time()) is inside the night of the raid the site sent.
function SiteLoot:Active(now)
    local s = held()
    if not s then return false end
    local LR = GuildOS.LootRule
    return LR and LR.InWindow(s.startsAt, now or time()) or false
end

-- What the site holds for tonight, or nil outside the night.
function SiteLoot:Reserves()
    local s = self:Active() and held()
    return s and type(s.softres) == "table" and type(s.softres.items) == "table" and s.softres or nil
end

function SiteLoot:Prios()
    local s = self:Active() and held()
    return s and type(s.prios) == "table" and s.prios or nil
end

-- The table of every person the site has a list of tonight, keyed as guildWishlists is.
function SiteLoot:Wishlists()
    local s = self:Active() and held()
    return s and type(s.wishlists) == "table" and s.wishlists or nil
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

-- The site is the source of this person's wishlist: it holds one, and the inbox is recent.
function SiteLoot:ListsFromSite(storeKey)
    local s = held()
    return fresh() and type(s.wishlists) == "table" and s.wishlists[storeKey] ~= nil or false
end

-- The site is the source of the officers' priorities: it sent some, and the inbox is recent.
function SiteLoot:PriosFromSite()
    local s = held()
    return fresh() and type(s.prios) == "table" or false
end
