----------------------------------------------------------------------
-- Guild OS - Trade Council (retail, issue #185)
-- Retail has no Master Loot: every item is personal, and one that is still tradeable can be handed to
-- someone who was eligible for it. A guildmate who received such an item offers it to the raid;
-- guildmates with Guild OS answer Need, Greed or Pass, with what they wear in that slot; an officer
-- (or, under the guild's free roll, the holder) awards it; and when the holder trades it to the
-- winner, the award goes into the loot history and, where the guild runs DKP, is charged.
--
-- Wire: addon messages on PREFIX over RAID, "|"-separated, an item link always last:
--   O|id|free|secs|link   an offer, from its holder (free: 1 under the free roll, believed only where the
--                         guild's loot system is the free roll; secs: the trade time the holder's client
--                         read, 0 when it could not)
--   A|id|choice|link      an answer, N, G or P, and the equipped item it would replace ("" for none)
--   W|id|winnerKey        an award, from an officer or, when the offer is free, its holder
--   X|id                  the offer withdrawn, by its holder or an officer
--   D|id|winner|by        the holder traded the item to the award's winner; `by` gave the award
-- Only a guildmate's message is read (a pickup raid's strangers have no say in the guild's loot), and
-- Midnight holds addon messages during an encounter, so offers go out after the boss (Compat).
----------------------------------------------------------------------
if not GuildOS.Client.isRetail then return end

local TradeCouncil = {}
GuildOS.TradeCouncil = TradeCouncil
local L = GuildOS.L
local Compat = GuildOS.Compat

TradeCouncil.PREFIX = "GuildOSTC"
local CHANNEL = "RAID"
local MAX_MESSAGE = 255        -- bytes an addon message may carry
local OFFER_TTL = 7200         -- seconds: a personal item can be traded for two hours after it drops
TradeCouncil.OFFER_TTL = OFFER_TTL
local EXPIRY_SLACK = 60        -- seconds: a trade time is read in whole minutes, so up to one more may be left
local ROLL_MAX = 100
local HASH_MOD = 2147483647    -- 2^31 - 1: keeps the roll's hash an exact integer in a double
local BAGS_LAST = 4            -- backpack 0 and four bags; the reagent bag holds no gear
local MIN_QUALITY = 3          -- Rare: what the loot history keeps
local NO_WISH = 999            -- the wishlist place of somebody who has not wished for the item
-- Need before Greed before Pass.
TradeCouncil.CHOICES = { N = 1, G = 2, P = 3 }
TradeCouncil.CHOICE_LABEL = { N = L["Need"], G = L["Greed"], P = L["Pass"] }

-- Where each kind of item is worn: the inventory slots an upgrade would replace.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}

----------------------------------------------------------------------
-- Session state: GuildOS.State.tradeCouncil = { offers = { [id] = offer }, trade = { partner, items, at } }
-- An offer: { id, holder, link, itemId, free, expires, timeKnown, at, answers = { [key] = { choice,
-- equipped } }, award = { winner, by }, closed, done }. Lost on a reload, as a roll window is.
----------------------------------------------------------------------
local function state()
    local s = GuildOS.State.tradeCouncil
    if not s then
        s = { offers = {} }
        GuildOS.State.tradeCouncil = s
    end
    return s
end

local function me() return GuildOS:GetPlayerKey(Compat.PlayerName()) end

local function itemIdOf(link)
    return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

-- Whether a link from another client is one whole item link and nothing else: it is printed, stored in
-- the loot history, sent to raid chat and shown on a tooltip, where a malformed one raises.
local function wellFormed(link)
    return type(link) == "string" and link:match("^|c[^|]*|Hitem:[%-%d:]+|h%[.-%]|h|r$") ~= nil
end

local function refresh()
    if GuildOS.RefreshTradeCouncil then GuildOS:RefreshTradeCouncil() end
end

local function send(msg)
    Compat.SendAddonMessageNow(TradeCouncil.PREFIX, msg, CHANNEL)
end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function TradeCouncil:Initialize()
    state()
    Compat.RegisterAddonPrefix(self.PREFIX)
    local frame = CreateFrame("Frame")
    Compat.RegisterEvent(frame, "CHAT_MSG_ADDON")
    Compat.RegisterEvent(frame, "TRADE_SHOW")
    Compat.RegisterEvent(frame, "TRADE_PLAYER_ITEM_CHANGED")
    Compat.RegisterEvent(frame, "TRADE_ACCEPT_UPDATE")
    Compat.RegisterEvent(frame, "UI_INFO_MESSAGE")       -- "Trade complete."
    frame:SetScript("OnEvent", function(_, event, ...) TradeCouncil:OnEvent(event, ...) end)
    self.eventFrame = frame
end

-- Route one event to its handler.
function TradeCouncil:OnEvent(event, ...)
    if event == "CHAT_MSG_ADDON" then return self:OnAddonMessage(...) end
    if event == "TRADE_SHOW" then return self:OnTradeShow() end
    if event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then return self:SnapshotTrade() end
    if event == "UI_INFO_MESSAGE" then return self:OnInfoMessage(...) end
end

----------------------------------------------------------------------
-- Reading the offers
----------------------------------------------------------------------

-- One offer by id, or nil.
function TradeCouncil:Get(id)
    return state().offers[id]
end

-- The offers still open, oldest first; one whose trade time ran out is closed on the way.
function TradeCouncil:OpenOffers()
    local now, out = GetServerTime(), {}
    for _, o in pairs(state().offers) do
        if not o.closed and o.expires and now > o.expires then o.closed = true end
        if not o.closed then out[#out + 1] = o end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.id < b.id
    end)
    return out
end

-- Whether the offer is mine.
function TradeCouncil:IsMine(o)
    return o ~= nil and o.holder == me()
end

-- Whether `key` is entitled to award the offer: an officer always; its holder when the guild's loot system
-- was the free roll when it was offered. `isLocal` asks for this client's own rank, which the roster may
-- not have.
local function entitled(o, key, isLocal)
    if o.free and key == o.holder then return true end
    if isLocal then return GuildOS:IsOfficer() end
    return GuildOS:IsOfficerByName(key)
end

-- Whether `key` may award the offer now: entitled, and the offer still open.
local function mayAward(o, key, isLocal)
    if not o or o.closed or o.done then return false end
    return entitled(o, key, isLocal)
end

-- Whether I may award the offer.
function TradeCouncil:MayIAward(o)
    return mayAward(o, me(), true)
end

-- Whether I may withdraw the offer: its holder or an officer.
function TradeCouncil:MayIWithdraw(o)
    return o ~= nil and not o.closed and (self:IsMine(o) or GuildOS:IsOfficer())
end

-- A roll every screen agrees on, with no message of its own: a hash of the offer and the player,
-- 1..100. Only the holder chooses an offer's id, and the holder holds the item anyway.
function TradeCouncil.Roll(offerId, key)
    local h, s = 5381, tostring(offerId) .. "|" .. tostring(key)
    for i = 1, #s do h = (h * 33 + s:byte(i)) % HASH_MOD end
    return h % ROLL_MAX + 1
end

-- A guildmate's place on their wishlist for an item, or nil.
function TradeCouncil:WishOrder(itemId, key)
    local W = GuildOS.Wishlist
    for _, e in ipairs((W and itemId and W:GetItemInterest(itemId)) or {}) do
        if e.name == key then return e.order end
    end
    return nil
end

-- Who has the offered item on their wishlist: { { key, order, answered } }, by place.
function TradeCouncil:Wishers(o)
    local out = {}
    local W = GuildOS.Wishlist
    for _, e in ipairs((W and o and W:GetItemInterest(o.itemId)) or {}) do
        out[#out + 1] = { key = e.name, order = e.order or NO_WISH, answered = o.answers[e.name] ~= nil }
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

-- What the council weighs about a guildmate beside the answer: attendance of the raid's core, the
-- roster's when that core has no night that counts (LootMaster's figure).
function TradeCouncil:Context(key)
    local ctx = { att = 0 }
    local RT = GuildOS.RaidTracker
    if RT then
        local core = RT.GetCurrentGroup and RT:GetCurrentGroup()
        if core == "" or (core and RT:GetTotal25ManSessions(core) == 0) then core = nil end
        ctx.att = RT:GetAttendance25ManPercent(key, core) or 0
    end
    return ctx
end

-- The answers in the order an awarder reads them: Need, Greed, Pass; within each, by the guild's loot
-- system (DKP: the most points; a wishlist: the highest place), then the roll.
-- Row: { key, choice, equipped, roll, wish, points }.
function TradeCouncil:Ranked(o)
    local rows = {}
    if not o then return rows end
    local sys = GuildOS:GetLootSystem()
    local P = GuildOS.Points
    for key, a in pairs(o.answers) do
        rows[#rows + 1] = {
            key = key, choice = a.choice, equipped = a.equipped, roll = self.Roll(o.id, key),
            wish = self:WishOrder(o.itemId, key), points = P and P.GetDB and P:GetDB() and P:Get(key) or nil,
        }
    end
    local C = self.CHOICES
    table.sort(rows, function(a, b)
        if C[a.choice] ~= C[b.choice] then return C[a.choice] < C[b.choice] end
        if sys == "dkp" and (a.points or 0) ~= (b.points or 0) then return (a.points or 0) > (b.points or 0) end
        if sys == "wishlist" and (a.wish or NO_WISH) ~= (b.wish or NO_WISH) then
            return (a.wish or NO_WISH) < (b.wish or NO_WISH)
        end
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.key < b.key
    end)
    return rows
end

----------------------------------------------------------------------
-- My bags
----------------------------------------------------------------------

-- Where an item is in my bags: the slot holding this very link, else one holding the same item that
-- can still be traded. Returns bag, slot, link.
function TradeCouncil:FindInBags(link)
    local id = itemIdOf(link)
    if not id then return nil end
    local fbBag, fbSlot, fbLink
    for bag = 0, BAGS_LAST do
        for slot = 1, Compat.GetContainerNumSlots(bag) do
            local info = Compat.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id then
                if info.hyperlink == link then return bag, slot, info.hyperlink end
                if not fbBag and Compat.TradeTimeLeft(bag, slot) ~= "bound" then
                    fbBag, fbSlot, fbLink = bag, slot, info.hyperlink
                end
            end
        end
    end
    return fbBag, fbSlot, fbLink
end

-- What I can offer: the Rare-and-up items in my bags that can still be traded to the raid, a personal
-- item's window open. { { link, bag, slot, seconds } }, the soonest to close first.
function TradeCouncil:MyTradeableItems()
    local out = {}
    for bag = 0, BAGS_LAST do
        for slot = 1, Compat.GetContainerNumSlots(bag) do
            local info = Compat.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and (info.quality or 0) >= MIN_QUALITY then
                local kind, secs = Compat.TradeTimeLeft(bag, slot)
                if kind == "timed" then
                    out[#out + 1] = { link = info.hyperlink, bag = bag, slot = slot, seconds = secs }
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.seconds or OFFER_TTL) < (b.seconds or OFFER_TTL) end)
    return out
end

-- What I wear where the item would go: the link of the item it would replace (the lower of a pair),
-- or nil.
function TradeCouncil:EquippedFor(link)
    local slots = SLOTS[Compat.EquipLoc(link) or ""]
    if not slots then return nil end
    local best, bestLevel
    for _, slot in ipairs(slots) do
        local worn = GetInventoryItemLink("player", slot)
        if Compat.IsSecret(worn) then worn = nil end
        if not worn then return nil end   -- an empty slot: nothing would be replaced
        local level = Compat.ItemLevel(worn, select(4, Compat.GetItemInfo(worn))) or 0
        if not bestLevel or level < bestLevel then best, bestLevel = worn, level end
    end
    return best
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

-- Offer a tradeable item from my bags to the raid. Returns the offer, or nil and says why.
function TradeCouncil:Offer(link)
    if not GuildOS:LootSystemActive() then
        GuildOS:Print(L["Your guild hands out loot outside Guild OS (External / Off)."])
        return nil
    end
    if not IsInRaid() then
        GuildOS:Print(L["You must be in a raid to offer loot."])
        return nil
    end
    if not itemIdOf(link) then
        GuildOS:Print(L["Usage: /gos offer <item link>"])
        return nil
    end
    local bag, slot, held = self:FindInBags(link)
    if not bag then
        GuildOS:Print(L["That item is not in your bags."])
        return nil
    end
    local kind, secs = Compat.TradeTimeLeft(bag, slot)
    if kind == "bound" then
        GuildOS:Print(L["That item can no longer be traded."])
        return nil
    end
    local mine = me()
    for _, o in pairs(state().offers) do
        if not o.closed and o.holder == mine and o.link == held then
            GuildOS:Print(L["You are already offering that item."])
            return o
        end
    end
    local now = GetServerTime()
    local o = {
        id = newId(), holder = mine, link = held, itemId = itemIdOf(held),
        free = GuildOS:GetLootSystem() == "rolls", at = now,
        expires = now + (secs and secs + EXPIRY_SLACK or OFFER_TTL), timeKnown = secs ~= nil, answers = {},
    }
    local msg = string.format("O|%s|%d|%d|%s", o.id, o.free and 1 or 0, secs or 0, held)
    if #msg > MAX_MESSAGE then
        GuildOS:Print(L["That item's link is too long to send."])
        return nil
    end
    state().offers[o.id] = o
    send(msg)
    GuildOS:Print(string.format(L["You offered %s to the raid."], held))
    if GuildOS.ShowTradeCouncil then GuildOS:ShowTradeCouncil(o.id) end
    return o
end

-- Answer an offer: "N" (Need), "G" (Greed) or "P" (Pass), with what I wear in that slot.
function TradeCouncil:Answer(id, choice)
    local o = state().offers[id]
    if not o or o.closed or not self.CHOICES[choice] or self:IsMine(o) then return end
    local equipped = choice ~= "P" and self:EquippedFor(o.link) or nil
    local msg = string.format("A|%s|%s|%s", id, choice, equipped or "")
    if #msg > MAX_MESSAGE then equipped, msg = nil, string.format("A|%s|%s|", id, choice) end
    o.answers[me()] = { choice = choice, equipped = equipped }
    send(msg)
    refresh()
end

-- Award an offer to a guildmate who asked for it: an officer, or the holder of a free-roll offer.
function TradeCouncil:Award(id, winner)
    local o = state().offers[id]
    if not o or o.closed or o.done then return end
    if not self:MayIAward(o) then
        GuildOS:Print(L["Only an officer can award this item."])
        return
    end
    local a = o.answers[winner]
    if not a or a.choice == "P" then return end
    o.award = { winner = winner, by = me() }
    send(string.format("W|%s|%s", id, winner))
    local line = string.format(L["[Loot] %s goes to %s: %s trades it to them."], o.link, winner, o.holder)
    if not Compat.SendChatMessage(line, CHANNEL) then GuildOS:Print(line) end
    if self:IsMine(o) then GuildOS:Print(string.format(L["Trade %s to %s."], o.link, winner)) end
    refresh()
end

-- Withdraw an offer: its holder, or an officer.
function TradeCouncil:Withdraw(id)
    local o = state().offers[id]
    if not self:MayIWithdraw(o) then return end
    o.closed = true
    send("X|" .. id)
    refresh()
end

----------------------------------------------------------------------
-- The trade
----------------------------------------------------------------------

-- The open offer of mine whose item this is: this very link, else the same item.
function TradeCouncil:MyOfferFor(link)
    local mine, id, same = me(), itemIdOf(link), nil
    for _, o in pairs(state().offers) do
        if not o.closed and o.holder == mine then
            if o.link == link then return o end
            if id and o.itemId == id then same = same or o end
        end
    end
    return same
end

-- TRADE_SHOW: who the trade is with; when it is the winner of one of my awards, say what to put in.
function TradeCouncil:OnTradeShow()
    local name, realm = Compat.TradePartner()
    local partner = name and GuildOS:GetPlayerKey(name, realm)
    state().trade = { partner = partner, items = {}, at = GetServerTime() }
    if not partner then return end
    local mine = me()
    for _, o in pairs(state().offers) do
        if not o.closed and o.holder == mine and o.award and o.award.winner == partner then
            GuildOS:Print(string.format(L["Put %s in the trade window: it goes to %s."], o.link, partner))
        end
    end
end

-- TRADE_PLAYER_ITEM_CHANGED, TRADE_ACCEPT_UPDATE: what I am handing over, kept until the trade ends.
function TradeCouncil:SnapshotTrade()
    local t = state().trade
    if not t then return end
    t.items = Compat.TradeItemLinks()
    t.at = GetServerTime()
end

-- UI_INFO_MESSAGE: a trade that went through, with what I handed over in it. However long the other
-- player took to accept: the trade is the one TRADE_SHOW opened, and it is forgotten once complete.
function TradeCouncil:OnInfoMessage(messageType, message)
    if not Compat.IsTradeComplete(messageType, message) then return end
    local t = state().trade
    state().trade = nil
    if not (t and t.partner) then return end
    self:OnTradeDone(t.partner, t.items)
end

-- What a finished trade means for my offers: an item I had offered and awarded, handed to the winner,
-- is recorded as the award; handed to anyone else it records nothing, and says so. Either way the
-- item has left my bags, so the offer is over.
function TradeCouncil:OnTradeDone(partner, links)
    for _, link in ipairs(links or {}) do
        local o = self:MyOfferFor(link)
        if o then
            if o.award and o.award.winner == partner then
                self:Complete(o)
                send(string.format("D|%s|%s|%s", o.id, partner, o.award.by))
            else
                o.closed = true
                send("X|" .. o.id)
                GuildOS:Print(string.format(L["%s went to %s, who was not awarded it: nothing was recorded."],
                    o.link, partner))
            end
        end
    end
    refresh()
end

-- An award whose trade went through: into the loot history, and charged by the officer who awarded
-- it when the guild runs DKP with a cost per item.
function TradeCouncil:Complete(o)
    if o.done then return end
    o.done, o.closed = true, true
    local RT = GuildOS.RaidTracker
    local session = RT and RT.trackingActive and RT.currentRaid
    if GuildOS.LootTracker then
        GuildOS.LootTracker:RecordTradeAward({
            itemLink = o.link, itemId = o.itemId, holder = o.holder, winner = o.award.winner,
            raid = session and session.name or "", instanceID = session and session.instanceID or 0,
        })
    end
    GuildOS:Print(string.format(L["%s was traded to %s: the award is recorded."], o.link, o.award.winner))
    if o.award.by == me() then self:Charge(o) end
end

-- Charge the winner the guild's cost per item (DKP only; an officer's client, once).
function TradeCouncil:Charge(o)
    local P = GuildOS.Points
    if not (P and GuildOS:GetLootSystem() == "dkp" and GuildOS:IsOfficer()) then return end
    local pool = P:GetDB()
    local cost = (pool and pool.config and pool.config.itemCost) or 0
    if cost <= 0 then return end
    P:Charge(o.award.winner, cost, Compat.GetItemInfo(o.link) or o.link)
    GuildOS:Print(string.format(L["[DKP] %s charged %d points for %s"], o.award.winner, cost, o.link))
end

----------------------------------------------------------------------
-- Incoming
----------------------------------------------------------------------
local HANDLERS = {}

-- An offer from its holder. It is a free roll only when the guild's loot system says so here too: a
-- holder cannot make their own item theirs to award.
function HANDLERS.O(from, rest)
    local id, free, secs, link = rest:match("^(%x+)|([01])|(%d+)|(.+)$")
    if not id or not wellFormed(link) or state().offers[id] then return end
    local now = GetServerTime()
    secs = tonumber(secs) or 0
    state().offers[id] = {
        id = id, holder = from, link = link, itemId = itemIdOf(link), at = now,
        free = free == "1" and GuildOS:GetLootSystem() == "rolls",
        expires = now + (secs > 0 and math.min(secs + EXPIRY_SLACK, OFFER_TTL) or OFFER_TTL), timeKnown = secs > 0,
        answers = {},
    }
    GuildOS:Print(string.format(L["%s offers %s to the raid."], from, link))
    if GuildOS.ShowTradeCouncil then GuildOS:ShowTradeCouncil(id) end
end

-- An answer.
function HANDLERS.A(from, rest)
    local id, choice, equipped = rest:match("^(%x+)|([NGP])|(.*)$")
    local o = id and state().offers[id]
    if not o or o.closed or from == o.holder then return end
    o.answers[from] = { choice = choice, equipped = wellFormed(equipped) and equipped or nil }
    refresh()
end

-- An award, from someone who may give it.
function HANDLERS.W(from, rest)
    local id, winner = rest:match("^(%x+)|(.+)$")
    local o = id and state().offers[id]
    if not o or not mayAward(o, from, false) or not GuildOS:IsGuildmate(winner) then return end
    o.award = { winner = winner, by = from }
    if o.holder == me() then
        GuildOS:Print(string.format(L["Trade %s to %s."], o.link, winner))
    elseif winner == me() then
        GuildOS:Print(string.format(L["You won %s: %s will trade it to you."], o.link, o.holder))
    end
    refresh()
end

-- An offer withdrawn.
function HANDLERS.X(from, rest)
    local o = state().offers[rest]
    if not o or o.done or not (from == o.holder or GuildOS:IsOfficerByName(from)) then return end
    o.closed = true
    refresh()
end

-- The holder's trade to the winner, with the award as the holder saw it: winner and who gave it. Every
-- client records that one, whichever award it saw last, so two officers awarding at once charge once; it
-- counts when who gave it was entitled to. An offer this client already closed (its trade time read a
-- minute apart) still records.
function HANDLERS.D(from, rest)
    local id, winner, by = rest:match("^(%x+)|([^|]+)|([^|]+)$")
    local o = id and state().offers[id]
    if not o or o.done or from ~= o.holder or not GuildOS:IsGuildmate(winner) then return end
    if not entitled(o, by, by == me()) then return end
    o.award = { winner = winner, by = by }
    TradeCouncil:Complete(o)
    refresh()
end

-- CHAT_MSG_ADDON on this module's prefix, over RAID, from a guildmate.
function TradeCouncil:OnAddonMessage(prefix, msg, channel, sender)
    if Compat.IsSecret(prefix, msg, channel, sender) then return end
    if prefix ~= self.PREFIX or channel ~= CHANNEL then return end
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    local from = GuildOS:KeyOfRosterName(sender)
    if from == me() or not GuildOS:IsGuildmate(from) then return end   -- mine was applied when sent
    local kind, rest = msg:match("^(%u)|(.+)$")
    local handler = kind and HANDLERS[kind]
    if handler then handler(from, rest) end
end
