----------------------------------------------------------------------
-- Guild OS - Trade Council (retail, issue #185)
-- Retail has no Master Loot: every item is personal, and one that is still tradeable can be handed to
-- someone who was eligible for it. A guildmate who received such an item offers it to the raid;
-- guildmates with Guild OS answer Need, Greed or Pass, with what they wear in that slot, and a Need or
-- Greed rolls the server's /roll; an officer (or, under the guild's free roll, the holder) awards it;
-- and when the holder trades it to the winner, the award goes into the loot history and, where the
-- guild runs DKP, is charged by the officer who gave it.
--
-- Wire: addon messages on PREFIX over RAID, "|"-separated, an item link always last:
--   O|id|free|secs|drop|link  an offer, from its holder (free: 1 under the free roll, believed only where
--                             the guild's loot system is the free roll; secs: the trade time the holder's
--                             client read, 0 when it could not; drop: when the item dropped, as the
--                             holder's history has it, the time every client stamps the award's row with)
--   A|id|choice|link          an answer, N, G or P, and the equipped item it would replace ("" for none)
--   W|id|winnerKey            an award, from an officer or, when the offer is free, its holder
--   X|id                      the offer withdrawn, by its holder or an officer
--   D|id|winner|by            the holder traded the item to the award's winner; `by` gave the award
-- Only a guildmate's message is read (a pickup raid's strangers have no say in the guild's loot), a link
-- only when it is one item link, and a holder's D only for an award this client saw given. Midnight
-- holds addon messages during an encounter, so offers go out after the boss (Compat).
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
local ROLL_WAIT = 10           -- seconds after an answer in which its player's next /roll 1-100 is its roll
local NO_ROLL = -1             -- ranks an answer whose roll was not seen after every one whose roll was
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
-- Session state: GuildOS.State.tradeCouncil = { offers = { [id] = offer }, trade = { partner, items },
-- seq }. An offer: { id, holder, link, itemId, free, dropTs, expires, timeKnown, at, answers = { [key] =
-- { choice, equipped, roll, rolled, awaitAt, awaitSeq } }, awards = { [awarder] = winner },
-- award = { winner, by }, closed, done }. Lost on a reload, as a roll window is.
----------------------------------------------------------------------
local function state()
    local s = GuildOS.State.tradeCouncil
    if not s then
        s = { offers = {}, seq = 0 }
        GuildOS.State.tradeCouncil = s
    end
    return s
end

local function me() return GuildOS:GetPlayerKey(Compat.PlayerName()) end

local function itemIdOf(link)
    return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

-- Whether a link from another client is one item link and nothing else: it is printed, stored in the
-- loot history (and uploaded), sent to raid chat and shown on a tooltip. No control character; the colour
-- one of a link's two (|cffRRGGBB, retail's |cnIQn:); inside the brackets no "|" but the crafted-quality
-- atlas at a chat icon's size, and no bracket, so nothing else hides in it.
local QUALITY_ATLAS = "|A:Professions%-ChatIcon%-Quality%-[%w%-]+:%d%d?:%d%d?:?%-?%d?%d?:?%-?%d?%d?|a"
local function wellFormed(link)
    if type(link) ~= "string" or link:find("%c") then return false end
    local name = link:match("^|c%x%x%x%x%x%x%x%x|Hitem:[%-%d:]+|h%[(.-)%]|h|r$")
        or link:match("^|cnIQ%d:|Hitem:[%-%d:]+|h%[(.-)%]|h|r$")
    if not name then return false end
    return not (name:gsub(QUALITY_ATLAS, "")):find("[|%[%]]")
end

local function refresh()
    if GuildOS.RefreshTradeCouncil then GuildOS:RefreshTradeCouncil() end
end

-- `onSent`, optional: what has to follow the message once it has really gone out (Compat).
local function send(msg, onSent)
    Compat.SendAddonMessageNow(TradeCouncil.PREFIX, msg, CHANNEL, nil, onSent)
end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

local function newOffer(fields)
    fields.answers, fields.awards = {}, {}
    state().offers[fields.id] = fields
    return fields
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function TradeCouncil:Initialize()
    state()
    Compat.RegisterAddonPrefix(self.PREFIX)
    local frame = CreateFrame("Frame")
    Compat.RegisterEvent(frame, "CHAT_MSG_ADDON")
    Compat.RegisterEvent(frame, "CHAT_MSG_SYSTEM")       -- the server's /roll lines
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
    if event == "CHAT_MSG_SYSTEM" then return self:OnSystemMessage(...) end
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
    if not o or o.closed then return false end
    return entitled(o, key, isLocal)
end

-- Whether a guildmate asked for the offered item: a Need or a Greed this client saw.
local function askedFor(o, key)
    local a = o.answers[key]
    return a ~= nil and a.choice ~= "P"
end

-- Whether I may award the offer.
function TradeCouncil:MayIAward(o)
    return mayAward(o, me(), true)
end

-- Whether I may withdraw the offer: its holder or an officer.
function TradeCouncil:MayIWithdraw(o)
    return o ~= nil and not o.closed and (self:IsMine(o) or GuildOS:IsOfficer())
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
-- system (DKP: the most points; a wishlist: the highest place), then the server's roll, an answer whose
-- roll was not seen after those whose roll was. Row: { key, choice, equipped, roll, wish, points }.
function TradeCouncil:Ranked(o)
    local rows = {}
    if not o then return rows end
    local sys = GuildOS:GetLootSystem()
    local P = GuildOS.Points
    for key, a in pairs(o.answers) do
        rows[#rows + 1] = {
            key = key, choice = a.choice, equipped = a.equipped, roll = a.roll,
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
        local ar, br = a.roll or NO_ROLL, b.roll or NO_ROLL
        if ar ~= br then return ar > br end
        return a.key < b.key
    end)
    return rows
end

----------------------------------------------------------------------
-- Answers and the server's roll
----------------------------------------------------------------------

-- Whether an award this client saw names the player: their answer then stands, so the trade's D still
-- finds the Need or Greed the award was given for.
local function awardedTo(o, key)
    for _, winner in pairs(o.awards) do
        if winner == key then return true end
    end
    return false
end

-- Keep an answer. A player's first Need or Greed on an offer waits for their roll: the next /roll 1-100
-- the client sees from them within ROLL_WAIT seconds (OnSystemMessage). A later answer keeps the roll it
-- has or waits on, so a changed answer never rolls again; and once an award names the player, no change
-- is kept at all. Returns the answer and whether it now waits, or nil when the answer stands.
local function answered(o, key, choice, equipped)
    if awardedTo(o, key) then return nil end
    local prev = o.answers[key] or {}
    local a = { choice = choice, equipped = equipped, roll = prev.roll, rolled = prev.rolled,
                awaitAt = prev.awaitAt, awaitSeq = prev.awaitSeq }
    local fresh = false
    if choice ~= "P" and not a.rolled then
        local s = state()
        s.seq = (s.seq or 0) + 1
        a.rolled, a.awaitAt, a.awaitSeq, fresh = true, GetServerTime(), s.seq, true
    end
    o.answers[key] = a
    return a, fresh
end

-- CHAT_MSG_SYSTEM: a /roll 1-100 is the roll of its player's earliest answer still waiting for one.
-- A roll seen before the answer, of another range, or after the wait, is nobody's.
function TradeCouncil:OnSystemMessage(message)
    if Compat.IsSecret(message) or type(message) ~= "string" then return end
    local args = GuildOS:MatchFormat(message, RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
    local roll = args and tonumber(args[2])
    if not (roll and args[1] and tonumber(args[3]) == 1 and tonumber(args[4]) == ROLL_MAX) then return end
    local key = GuildOS:KeyOfRosterName(args[1])
    local now, waiting = GetServerTime(), nil
    for _, o in pairs(state().offers) do
        local a = o.answers[key]
        if a and a.awaitSeq and now - a.awaitAt <= ROLL_WAIT and (not waiting or a.awaitSeq < waiting.awaitSeq) then
            waiting = a
        end
    end
    if not waiting then return end
    waiting.roll, waiting.awaitAt, waiting.awaitSeq = roll, nil, nil
    refresh()
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
    local drop = GuildOS.LootTracker and GuildOS.LootTracker:DropOf(mine, itemIdOf(held))
    local dropTs = tonumber(drop and drop.timestamp) or now
    local id, free = newId(), GuildOS:GetLootSystem() == "rolls"
    local msg = string.format("O|%s|%d|%d|%d|%s", id, free and 1 or 0, secs or 0, dropTs, held)
    if #msg > MAX_MESSAGE then
        GuildOS:Print(L["That item's link is too long to send."])
        return nil
    end
    local o = newOffer({
        id = id, holder = mine, link = held, itemId = itemIdOf(held), free = free, at = now, dropTs = dropTs,
        expires = now + (secs and secs + EXPIRY_SLACK or OFFER_TTL), timeKnown = secs ~= nil,
    })
    send(msg)
    GuildOS:Print(string.format(L["You offered %s to the raid."], held))
    if GuildOS.ShowTradeCouncil then GuildOS:ShowTradeCouncil(o.id) end
    return o
end

-- Answer an offer: "N" (Need), "G" (Greed) or "P" (Pass), with what I wear in that slot. My first Need
-- or Greed rolls the server's /roll 1-100 once the answer has really gone out (a held or throttled answer
-- would arrive after its roll's line, and bind nothing), so every client binds it to the answer. Not in a
-- chat lockdown, where the roll's line would be secret to everyone; not once an award names me.
function TradeCouncil:Answer(id, choice)
    local o = state().offers[id]
    if not o or o.closed or not self.CHOICES[choice] or self:IsMine(o) then return end
    if Compat.InChatLockdown() then
        GuildOS:Print(L["Chat is locked during the encounter: answer once it ends."])
        return
    end
    local equipped = choice ~= "P" and self:EquippedFor(o.link) or nil
    local msg = string.format("A|%s|%s|%s", id, choice, equipped or "")
    if #msg > MAX_MESSAGE then equipped, msg = nil, string.format("A|%s|%s|", id, choice) end
    local mine = me()
    local a, fresh = answered(o, mine, choice, equipped)
    if not a then
        GuildOS:Print(L["The item was awarded to you: your answer stands."])
        return
    end
    send(msg, fresh and function()
        -- The wait runs from the answer's going out, as everyone else's does.
        local cur = o.answers[mine]
        if cur and cur.awaitSeq then cur.awaitAt = GetServerTime() end
        Compat.RandomRoll(1, ROLL_MAX)
    end or nil)
    refresh()
end

-- Award an offer to a guildmate who asked for it: an officer, or the holder of a free-roll offer.
function TradeCouncil:Award(id, winner)
    local o = state().offers[id]
    if not o or o.closed then return end
    if not self:MayIAward(o) then
        GuildOS:Print(L["Only an officer can award this item."])
        return
    end
    if not askedFor(o, winner) then return end
    local mine = me()
    o.awards[mine] = winner
    o.award = { winner = winner, by = mine }
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
    state().trade = { partner = partner, items = {} }
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

-- An award whose trade went through: into the loot history at the drop's time, and charged by the officer
-- who gave it, when that is this client and the award is the one it gave, under DKP with a cost per item.
function TradeCouncil:Complete(o)
    if o.done then return end
    o.done, o.closed = true, true
    local RT = GuildOS.RaidTracker
    local session = RT and RT.trackingActive and RT.currentRaid
    if GuildOS.LootTracker then
        GuildOS.LootTracker:RecordTradeAward({
            itemLink = o.link, itemId = o.itemId, holder = o.holder, winner = o.award.winner, timestamp = o.dropTs,
            raid = session and session.name or "", instanceID = session and session.instanceID or 0,
        })
    end
    GuildOS:Print(string.format(L["%s was traded to %s: the award is recorded."], o.link, o.award.winner))
    local mine = me()
    if o.award.by == mine and o.awards[mine] == o.award.winner then self:Charge(o) end
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
    local id, free, secs, drop, link = rest:match("^(%x+)|([01])|(%d+)|(%d+)|(.+)$")
    if not id or not wellFormed(link) or state().offers[id] then return end
    local now = GetServerTime()
    secs = tonumber(secs) or 0
    -- The drop's time is the holder's word: believed only inside the trade window it could have come from,
    -- with a minute for a holder's clock running ahead of this one — two clients a second apart must still
    -- write the same winner row (issue #185).
    drop = tonumber(drop)
    if not drop or drop > now + EXPIRY_SLACK or drop < now - OFFER_TTL - EXPIRY_SLACK then drop = now end
    newOffer({
        id = id, holder = from, link = link, itemId = itemIdOf(link), at = now, dropTs = drop,
        free = free == "1" and GuildOS:GetLootSystem() == "rolls",
        expires = now + (secs > 0 and math.min(secs + EXPIRY_SLACK, OFFER_TTL) or OFFER_TTL), timeKnown = secs > 0,
    })
    GuildOS:Print(string.format(L["%s offers %s to the raid."], GuildOS:DisplayKey(from), link))
    if GuildOS.ShowTradeCouncil then GuildOS:ShowTradeCouncil(id) end
end

-- An answer, never the holder's own; one an award already names stands (`answered`).
function HANDLERS.A(from, rest)
    local id, choice, equipped = rest:match("^(%x+)|([NGP])|(.*)$")
    local o = id and state().offers[id]
    if not o or o.closed or from == o.holder then return end
    answered(o, from, choice, wellFormed(equipped) and equipped or nil)
    refresh()
end

-- An award, from someone who may give it, to a guildmate who asked for it. Each awarder's latest award
-- is kept: a holder's D is believed only for one of them.
function HANDLERS.W(from, rest)
    local id, winner = rest:match("^(%x+)|(.+)$")
    local o = id and state().offers[id]
    if not o or not mayAward(o, from, false) or not askedFor(o, winner) or not GuildOS:IsGuildmate(winner) then
        return
    end
    o.awards[from] = winner
    o.award = { winner = winner, by = from }
    if o.holder == me() then
        GuildOS:Print(string.format(L["Trade %s to %s."], o.link, winner))
    elseif winner == me() then
        GuildOS:Print(string.format(L["You won %s: %s will trade it to you."], o.link, GuildOS:DisplayKey(o.holder)))
    end
    refresh()
end

-- An offer withdrawn.
function HANDLERS.X(from, rest)
    local o = state().offers[rest]
    if not o or not (from == o.holder or GuildOS:IsOfficerByName(from)) then return end
    o.closed = true
    refresh()
end

-- The holder's trade to the winner, with the award as the holder saw it: winner and who gave it. Believed
-- only for an award this client saw given (a W from `by` naming that winner: it was given for a Need or
-- Greed, which then stood), or, under a free roll, the holder's own to a guildmate who asked for it; and
-- to somebody still in the guild. A holder's word alone charges nobody and writes nobody a row. Every
-- client then records that one award, whichever it saw last, so two officers awarding at once charge
-- once. An offer this client already closed (its trade time read a minute apart) still records.
function HANDLERS.D(from, rest)
    local id, winner, by = rest:match("^(%x+)|([^|]+)|([^|]+)$")
    local o = id and state().offers[id]
    if not o or o.done or from ~= o.holder then return end
    local seen = o.awards[by] == winner or (o.free and by == o.holder and askedFor(o, winner))
    if not seen or not GuildOS:IsGuildmate(winner) then return end
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
