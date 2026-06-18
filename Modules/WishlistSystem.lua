----------------------------------------------------------------------
-- BRutus Guild Manager - Wishlist System
-- Native per-character wishlist with guild-wide sync and item search.
-- Replaces the That's My BiS (TMB) CSV integration.
----------------------------------------------------------------------
local Wishlist = {}
BRutus.Wishlist = Wishlist
local L = BRutus.L

-- Color palette for wishlist entries
Wishlist.TypeColors = {
    wishlist = { r = 0.3,  g = 0.7,  b = 1.0 },  -- blue
}

function Wishlist:Initialize()
    if not BRutus.db.wishlists then
        BRutus.db.wishlists = {}
    end
    -- One-time migration: move flat myWishlist to per-char slot
    if BRutus.db.myWishlist and #BRutus.db.myWishlist > 0 then
        local charKey = (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
        if not BRutus.db.wishlists[charKey] or #BRutus.db.wishlists[charKey] == 0 then
            BRutus.db.wishlists[charKey] = BRutus.db.myWishlist
        end
        BRutus.db.myWishlist = nil
    end
    if not BRutus.db.guildWishlists then
        BRutus.db.guildWishlists = {}
    end
    self:RebuildItemIndex()
    self:HookTooltips()
end

----------------------------------------------------------------------
-- Static catalog of all P1/P2 raid boss drops (sourced from AtlasLootClassic).
-- Seeded into itemIndex so items appear in search even without wishers.
-- Raids: Karazhan, Gruul's Lair, Magtheridon, Serpentshrine Cavern, Tempest Keep
----------------------------------------------------------------------
local RAID_CATALOG = {
    -- Karazhan
    21882, 21903, 21904, 22545, 22559, 22560, 22561, 23809, 23857, 23862,
    23864, 23865, 23933, 24139, 28453, 28454, 28477, 28502, 28503, 28504,
    28505, 28506, 28507, 28508, 28509, 28510, 28511, 28512, 28514, 28515,
    28516, 28517, 28518, 28519, 28520, 28521, 28522, 28523, 28524, 28525,
    28528, 28529, 28530, 28545, 28565, 28566, 28567, 28568, 28569, 28570,
    28572, 28573, 28578, 28579, 28581, 28582, 28583, 28584, 28585, 28586,
    28587, 28588, 28589, 28590, 28591, 28592, 28593, 28594, 28597, 28599,
    28600, 28601, 28602, 28603, 28604, 28606, 28608, 28609, 28610, 28611,
    28612, 28621, 28631, 28633, 28647, 28649, 28652, 28653, 28654, 28655,
    28656, 28657, 28658, 28659, 28660, 28661, 28662, 28663, 28666, 28669,
    28670, 28671, 28672, 28673, 28674, 28675, 28726, 28727, 28728, 28729,
    28730, 28731, 28732, 28733, 28734, 28735, 28740, 28741, 28742, 28743,
    28744, 28745, 28746, 28747, 28748, 28749, 28750, 28751, 28752, 28753,
    28754, 28755, 28756, 28757, 28762, 28763, 28764, 28765, 28766, 28767,
    28768, 28770, 28771, 28772, 28773, 28774, 28775, 28776, 28777, 28778,
    28779, 28780, 28781, 28782, 28783, 28785, 28789, 28794, 28795, 28796,
    28797, 28799, 28800, 28801, 28802, 28803, 28804, 28810,
    -- Gruul's Lair
    28822, 28823, 28824, 28825, 28826, 28827, 28828, 28830,
    -- Magtheridon's Lair
    29434, 29458,
    -- Serpentshrine Cavern
    29753, 29754, 29755, 29756, 29757, 29758, 29759, 29760, 29761, 29762,
    29763, 29764, 29765, 29766, 29767, 29905, 29906, 29918, 29920, 29921,
    29922, 29923, 29924, 29925, 29947, 29948, 29949, 29950, 29951, 29962,
    29965, 29966, 29972, 29976, 29977, 29981, 29982, 29983, 29984, 29985,
    29986, 29987, 29988, 29989, 29990, 29991, 29992, 29993, 29994, 29995,
    29996, 29997, 29998, 30008, 30020, 30021, 30022, 30023, 30024, 30025,
    30026, 30027, 30028, 30029, 30030, 30047, 30048, 30049, 30050, 30051,
    30052, 30053, 30054, 30055, 30056, 30057, 30058, 30059, 30060, 30061,
    30062, 30063, 30064, 30065, 30066, 30067, 30068, 30075, 30079, 30080,
    30081, 30082, 30083, 30084, 30085, 30090, 30091, 30092, 30095, 30096,
    30097, 30098, 30099, 30100, 30101, 30102, 30103, 30104, 30105, 30106,
    30107, 30108, 30109, 30110, 30111, 30112, 30183, 30236, 30237, 30238,
    30239, 30240, 30241, 30242, 30243, 30244, 30245, 30246, 30247, 30248,
    30249, 30250,
    -- Tempest Keep (The Eye)
    30280, 30281, 30282, 30283, 30301, 30302, 30303, 30304, 30305, 30306,
    30307, 30308, 30311, 30312, 30313, 30314, 30316, 30317, 30318, 30319,
    30321, 30322, 30323, 30324, 30446, 30447, 30448, 30449, 30450, 30480,
    30619, 30620, 30621, 30626, 30627, 30629, 30641, 30642, 30643, 30644,
    30663, 30664, 30665, 30666, 30667, 30668, 30673, 30674, 30675, 30676,
    30677, 30678, 30680, 30681, 30682, 30683, 30684, 30685, 30686, 30687,
    30720, 31750, 31751, 32267, 32385, 32405, 32458, 32515, 32516, 32897,
    32944, 33054, 33055, 33058, 34845, 34846,
}

----------------------------------------------------------------------
-- Reverse index: itemId -> list of { name, class, type, order, isOffspec }
-- Built from guild wishlist broadcasts + seeded with RAID_CATALOG.
----------------------------------------------------------------------
function Wishlist:RebuildItemIndex()
    local index = {}
    local guild = BRutus.db and BRutus.db.guildWishlists
    if guild then
        for _, charData in pairs(guild) do
            local cc   = charData.class or ""
            local name = charData.name  or ""
            for _, item in ipairs(charData.wishlist or {}) do
                -- Skip malformed entries (e.g. old TMB-era data lacking itemId)
                if item.itemId then
                if not index[item.itemId] then index[item.itemId] = {} end
                table.insert(index[item.itemId], {
                    name      = name,
                    class     = cc,
                    type      = "wishlist",
                    order     = item.order,
                    isOffspec = item.isOffspec,
                })
                end  -- end itemId guard
            end
        end
    end

    -- Sort entries within each item by order
    for _, entries in pairs(index) do
        table.sort(entries, function(a, b)
            return (a.order or 999) < (b.order or 999)
        end)
    end

    -- Seed static catalog so all raid items appear in search
    for _, itemId in ipairs(RAID_CATALOG) do
        if not index[itemId] then
            index[itemId] = {}
        end
    end

    self.itemIndex = index
end

----------------------------------------------------------------------
-- Query: who wants a specific item
----------------------------------------------------------------------
function Wishlist:GetItemInterest(itemId)
    if not self.itemIndex then return nil end
    return self.itemIndex[itemId]
end

----------------------------------------------------------------------
-- Item metadata helpers
----------------------------------------------------------------------
function Wishlist:GetItemName(itemId)
    if not itemId then return L["Item #?"] end
    local name = GetItemInfo(itemId)
    return name or (L["Item #"] .. itemId)
end

function Wishlist:GetItemQuality(itemId)
    if not itemId then return 1 end
    local _, _, quality = GetItemInfo(itemId)
    return quality or 1
end

----------------------------------------------------------------------
-- Native Wishlist CRUD — operates on per-character wishlists[charKey]
----------------------------------------------------------------------
local WISHLIST_MAX = 50

-- Returns (and lazily creates) the wishlist table for the current character.
function Wishlist:GetMyList()
    if not BRutus.db then return {} end
    if not BRutus.db.wishlists then BRutus.db.wishlists = {} end
    local charKey = (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
    if not BRutus.db.wishlists[charKey] then
        BRutus.db.wishlists[charKey] = {}
    end
    return BRutus.db.wishlists[charKey]
end

-- Add or update an item in the player's own wishlist.
function Wishlist:AddToWishlist(itemId, itemLink, isOffspec)
    if not BRutus.db then return end
    local list = self:GetMyList()

    -- If already present, update in place
    for _, entry in ipairs(list) do
        if entry.itemId == itemId then
            entry.itemLink  = itemLink or entry.itemLink
            entry.isOffspec = isOffspec or false
            self:BroadcastMyWishlist()
            BRutus:Print(format(L["[Wishlist] Updated: %s"], itemLink or (L["Item #"] .. itemId)))
            return
        end
    end

    if #list >= WISHLIST_MAX then
        BRutus:Print(format(L["|cffFF4444[Wishlist]|r Item limit of %d reached."], WISHLIST_MAX))
        return
    end

    local name = GetItemInfo(itemId)
    if not name then
        BRutus:Print(L["|cffFF4444[Wishlist]|r Unknown item. Try again in a few seconds."])
        return
    end

    table.insert(list, {
        itemId    = itemId,
        itemLink  = itemLink or "",
        order     = #list + 1,
        isOffspec = isOffspec or false,
    })
    self:BroadcastMyWishlist()
    BRutus:Print(format(L["[Wishlist] Added #%d: %s"], #list, itemLink or name))
    if BRutus.WishlistFrame and BRutus.WishlistFrame:IsShown() then
        BRutus:RefreshWishlistFrame()
    end
end

-- Remove an item from the player's own wishlist by itemId.
-- Returns true if the local player has received this item via master-loot.
function Wishlist:IsItemDelivered(itemId)
    local history = BRutus.db and BRutus.db.lootHistory
    if not history then return false end
    local myName = UnitName("player")
    local realm  = GetRealmName() or ""
    local myKey  = myName .. "-" .. realm
    for _, entry in ipairs(history) do
        if entry.fromML and entry.playerKey == myKey then
            -- Match by itemId stored in entry, or extract from itemLink
            local entryId = entry.itemId
            if not entryId and entry.itemLink then
                entryId = tonumber(entry.itemLink:match("item:(%d+)"))
            end
            if entryId == itemId then return true end
        end
    end
    return false
end

function Wishlist:RemoveFromWishlist(itemId)
    if not BRutus.db then return end
    if self:IsItemDelivered(itemId) then
        BRutus:Print(L["|cffFF4444[Wishlist]|r This item has already been delivered and cannot be removed."])
        return
    end
    local list = self:GetMyList()
    for i = #list, 1, -1 do
        if list[i].itemId == itemId then
            local link = list[i].itemLink
            table.remove(list, i)
            for j, e in ipairs(list) do e.order = j end
            self:BroadcastMyWishlist()
            BRutus:Print(format(L["[Wishlist] Removed: %s"], link ~= "" and link or (L["Item #"] .. itemId)))
            if BRutus.WishlistFrame and BRutus.WishlistFrame:IsShown() then
                BRutus:RefreshWishlistFrame()
            end
            return
        end
    end
    BRutus:Print(L["[Wishlist] Item not found in your wishlist."])
end

-- Move an item up (-1) or down (+1) in the wishlist order.
function Wishlist:ReorderWishlist(itemId, direction)
    if not BRutus.db then return end
    if self:IsItemDelivered(itemId) then return end
    local list = self:GetMyList()
    local idx
    for i, e in ipairs(list) do
        if e.itemId == itemId then idx = i break end
    end
    if not idx then return end
    local newIdx = idx + direction
    if newIdx < 1 or newIdx > #list then return end
    list[idx], list[newIdx] = list[newIdx], list[idx]
    for i, e in ipairs(list) do e.order = i end
    self:BroadcastMyWishlist()
    if BRutus.WishlistFrame and BRutus.WishlistFrame:IsShown() then
        BRutus:RefreshWishlistFrame()
    end
end

----------------------------------------------------------------------
-- Guild broadcast — serialize and send this character's wishlist
----------------------------------------------------------------------
function Wishlist:BroadcastMyWishlist()
    if not BRutus.db then return end
    local list = self:GetMyList()
    -- Do not broadcast (or store) an empty list — would create a ghost entry in every
    -- guildie's panel showing the character with 0 items.
    if #list == 0 then return end

    local myName  = UnitName("player")
    local myClass = select(2, UnitClass("player")) or ""

    -- Store own data locally immediately (WoW does not echo addon messages back to sender)
    if not BRutus.db.guildWishlists then
        BRutus.db.guildWishlists = {}
    end
    local myKey = strlower(myName or "")
    BRutus.db.guildWishlists[myKey] = {
        name     = myName,
        class    = myClass,
        wishlist = list,
    }
    self:RebuildItemIndex()

    -- Broadcast to guild
    if BRutus.CommSystem then
        local payload = {
            name     = myName,
            class    = myClass,
            wishlist = list,
        }
        local LibSerialize = LibStub("LibSerialize")
        local serialized  = LibSerialize:Serialize(payload)
        BRutus.CommSystem:SendMessage("WL", serialized)
    end
end

-- Handle an incoming wishlist broadcast from another guild member.
function Wishlist:HandleWishlistBroadcast(sender, data)
    local LibSerialize = LibStub("LibSerialize")
    local ok, payload = LibSerialize:Deserialize(data)
    if not ok or type(payload) ~= "table" then return end

    local name     = payload.name or sender
    local class    = payload.class or ""
    local wishlist = payload.wishlist
    if not wishlist or type(wishlist) ~= "table" then return end

    -- Don't overwrite our own data with a stale broadcast of ourselves
    if strlower(name) == strlower(UnitName("player") or "") then return end

    if not BRutus.db.guildWishlists then
        BRutus.db.guildWishlists = {}
    end
    local key = strlower(name)
    BRutus.db.guildWishlists[key] = {
        name     = name,
        class    = class,
        wishlist = wishlist,
    }
    self:RebuildItemIndex()
end

----------------------------------------------------------------------
-- Tooltip hook — shows who has the hovered item on their wishlist
----------------------------------------------------------------------
function Wishlist:HookTooltips()
    local function OnTooltipSetItem(tooltip)
        if not self.itemIndex then return end

        local _, link = tooltip:GetItem()
        if not link then return end

        local itemId = tonumber(link:match("item:(%d+)"))
        if not itemId then return end

        local entries = self.itemIndex[itemId]
        if not entries or #entries == 0 then return end

        tooltip:AddLine(" ")
        tooltip:AddLine(L["On the wishlist of:"],
            self.TypeColors.wishlist.r,
            self.TypeColors.wishlist.g,
            self.TypeColors.wishlist.b)
        for _, e in ipairs(entries) do
            local cc    = BRutus.ClassColors[e.class:upper()] or BRutus.Colors.white
            local label = "#" .. e.order .. (e.isOffspec and L[" (OS)"] or "")
            tooltip:AddDoubleLine("  " .. e.name, label,
                cc.r, cc.g, cc.b, 0.7, 0.7, 0.7)
        end

        tooltip:Show()
    end

    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)

    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ShoppingTooltip1 then
        ShoppingTooltip1:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ShoppingTooltip2 then
        ShoppingTooltip2:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
end

----------------------------------------------------------------------
-- Loot Prios broadcast / receive
-- Structure: db.lootPrios[itemId] = { {name, class, order}, ... }
-- Officers set and sync prios; all members receive and store them.
----------------------------------------------------------------------
function Wishlist:BroadcastLootPrios()
    if not BRutus.CommSystem then return end
    if not BRutus.db or not BRutus.db.lootPrios then return end
    local LibSerialize = LibStub("LibSerialize")
    local serialized = LibSerialize:Serialize(BRutus.db.lootPrios)
    BRutus.CommSystem:SendMessage("LP", serialized)
end

function Wishlist:HandleLootPriosBroadcast(sender, data)
    local LibSerialize = LibStub("LibSerialize")
    local ok, payload = LibSerialize:Deserialize(data)
    if not ok or type(payload) ~= "table" then return end

    if not BRutus.db then return end
    BRutus.db.lootPrios = payload
    self:RebuildItemIndex()
    BRutus:Print(L["[Wishlist] Priorities updated by "] .. (sender or "?"))
end
