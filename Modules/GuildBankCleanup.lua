----------------------------------------------------------------------
-- Guild OS - Guild bank cleanup (issue #380)
-- A big guild's bank fills with what nobody takes. For each item the bank holds, a verdict an
-- officer can act on, with its reasons and what it is worth:
--   sell    grey; or untouched (no withdrawal in DEMAND_DAYS) and sitting for STALE_DAYS, for
--           levels few in the guild still are; or what the bank holds past its need;
--   keep    has a need, was taken lately, or a member asked for it;
--   review  the rest.
-- Officers mark what goes (shared, domain "gbankclean"); at the bank the marked stacks come out into
-- the bags one at a time; at a vendor only what came out of the bank is sold; the next time the bank
-- opens, the gold it made goes back in.
----------------------------------------------------------------------
local Cleanup = {}
GuildOS.GuildBankCleanup = Cleanup
local L = GuildOS.L

local DEMAND_DAYS = 60        -- days of the ledger that count as "taken lately"
local STALE_DAYS = 30         -- days an item must sit in the bank before it is offered for sale
local DEMAND_KEEP = 2         -- withdrawals in DEMAND_DAYS that make an item worth keeping
local EXCESS = 1.5            -- held past this many times its need: the rest may go
local AH_FACTOR = 3           -- an auction price this many times the vendor's: sell it there
local WITHDRAW_GAP = 0.6      -- seconds between two stacks taken out of the bank
local WITHDRAW_WAIT = 3       -- seconds a stack may take to leave the bank
local SELL_GAP = 0.2          -- seconds between two stacks sold to a vendor
local OUT_DAYS = 14           -- days what came out stays sellable; after that it is the player's
local BAGS = { 0, 1, 2, 3, 4 }
local SLOTS = 98

local function now() return GetServerTime() end

-- Copper as "12g 34s 56c", for the chat.
function Cleanup.MoneyText(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local g, sv, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, sv, c) end
    if sv > 0 then return string.format("%ds %dc", sv, c) end
    return string.format("%dc", c)
end
local function Bank() return GuildOS.GuildBank end

local function state()
    local s = GuildOS.State.gbankClean
    if not s then
        s = {}
        GuildOS.State.gbankClean = s
    end
    return s
end

function Cleanup:Store()
    local db = Bank():Store()
    db.seen = db.seen or {}
    db.clean = db.clean or { marks = {} }
    db.clean.marks = db.clean.marks or {}
    db.clean.chars = db.clean.chars or {}
    return db
end

-- What this character took out of the bank and still has to sell, and the gold it owes the bank.
-- Per character: the saved variables are the account's, and an alt must never sell its own items
-- as the bank's. What came out is forgotten after OUT_DAYS.
function Cleanup:Mine()
    local chars = self:Store().clean.chars
    local key = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) or "?"
    local me = chars[key]
    if not me then
        me = { out = {}, toDeposit = 0, outAt = now() }
        chars[key] = me
    end
    if next(me.out) and now() - (me.outAt or 0) > OUT_DAYS * 86400 then me.out = {} end
    return me
end

function Cleanup:Initialize()
    self:Store()
    if GuildOS.SyncService then
        GuildOS.SyncService:On("gbankclean", function(env) Cleanup:OnSync(env) end)
    end
    if not self.frame then
        self.frame = CreateFrame("Frame")
        GuildOS.Compat.RegisterEvent(self.frame, "MERCHANT_SHOW", true)
        GuildOS.Compat.RegisterEvent(self.frame, "MERCHANT_CLOSED", true)
        self.frame:SetScript("OnEvent", function(_, event) GuildOS:SafeCall(Cleanup.OnEvent, Cleanup, event) end)
    end
end

function Cleanup:OnEvent(event)
    local s = state()
    if event == "MERCHANT_SHOW" then
        s.merchant = true
        if self.merchantOpened then GuildOS:SafeCall(self.merchantOpened) end
    elseif event == "MERCHANT_CLOSED" then
        s.merchant = false
        if s.selling then self:SellStep() end   -- closes the run; what it sold is already owed
        if self.merchantClosed then GuildOS:SafeCall(self.merchantClosed) end
    end
end

----------------------------------------------------------------------
-- How long each item has been in the bank
----------------------------------------------------------------------

-- Note when each item was first seen in the bank, and forget the ones that left. Called whenever
-- the bank's index is rebuilt.
function Cleanup:Touch(list)
    local seen = self:Store().seen
    local t = now()
    local present = {}
    for _, e in ipairs(list) do
        present[e.key] = true
        if not seen[e.key] then seen[e.key] = t end
    end
    for k in pairs(seen) do if not present[k] then seen[k] = nil end end
end

----------------------------------------------------------------------
-- The verdicts (pure, given what is passed in)
----------------------------------------------------------------------

-- Withdrawals of each item id over the last `days`: { [id] = { lines, items } }.
function Cleanup:Demand(days)
    local since = now() - days * 86400
    local out = {}
    for _, e in ipairs(Bank():Store().ledger) do
        if e.k ~= 0 and e.ty == "w" and e.id and (e.t or 0) >= since then
            local d = out[e.id]
            if not d then d = { lines = 0, items = 0 }; out[e.id] = d end
            d.lines = d.lines + 1
            d.items = d.items + (e.c or 0)
        end
    end
    return out
end

-- The level under which an item counts as low: the officers' choice, else half the game's cap
-- (30 on WoW: Forever, 35 on TBC, 45 on retail).
function Cleanup:LowBelow()
    local v = tonumber(GuildOS:GetSetting("gbankCleanLow"))
    if v and v > 1 then return v end
    return math.floor(GuildOS.Client.maxLevel / 2)
end

-- Classes that are worth nothing to a guild once below its level: consumables, gear, bags, ammo.
local LOW_SELLS = { [0] = true, [1] = true, [2] = true, [4] = true, [6] = true, [11] = true }
-- Classes worth a look below it: trade goods and reagents (crafters level on them), recipes.
local LOW_REVIEWS = { [5] = true, [7] = true, [9] = true, [19] = true }

-- The verdict on one item. `it` = { have, quality, classID, level (required, or the item's own),
-- lowBelow, need, demandLines, requested, days (in the bank, at least) }. Returns the verdict, how
-- many may go, and the reasons as keys of REASON. Nothing here waits for time to pass: a bank read
-- for the first time already has its verdicts.
function Cleanup.Judge(it)
    local reasons = {}
    if it.need and it.need > 0 then
        if it.have > it.need * EXCESS then
            reasons[#reasons + 1] = "excess"
            return "sell", it.have - it.need, reasons
        end
        reasons[#reasons + 1] = "need"
        return "keep", 0, reasons
    end
    if (it.quality or 1) == 0 then
        reasons[#reasons + 1] = "grey"
        return "sell", it.have, reasons
    end
    if it.requested then reasons[#reasons + 1] = "requested" end
    if (it.demandLines or 0) >= DEMAND_KEEP then reasons[#reasons + 1] = "taken" end
    if #reasons > 0 then return "keep", 0, reasons end

    if it.classID == 12 then
        reasons[#reasons + 1] = "quest"
        return "review", 0, reasons
    end
    local low = it.level and it.level > 0 and it.level < (it.lowBelow or 30)
    local stale = (it.days or 0) >= STALE_DAYS and (it.demandLines or 0) == 0
    if low and LOW_SELLS[it.classID] then
        reasons[#reasons + 1] = "lowlevel"
        if stale then reasons[#reasons + 1] = "stale" end
        return "sell", it.have, reasons
    end
    if low and LOW_REVIEWS[it.classID] then
        reasons[#reasons + 1] = it.classID == 9 and "lowrecipe" or "lowmat"
        if stale then reasons[#reasons + 1] = "stale" end
        return "review", 0, reasons
    end
    if stale and (it.classID == 2 or it.classID == 4) then
        reasons[#reasons + 1] = "stale"
        return "sell", it.have, reasons
    end
    if stale then
        reasons[#reasons + 1] = "stale"
        return "review", 0, reasons
    end
    reasons[#reasons + 1] = "current"
    return "keep", 0, reasons
end

Cleanup.REASON = {
    excess = "More than the need",
    need = "Has a need",
    grey = "Grey item",
    requested = "A member asked for it",
    taken = "Taken lately",
    stale = "Untouched for a month",
    lowlevel = "Below the guild's level",
    lowmat = "Low-level material: crafters still level on it",
    lowrecipe = "Low-level recipe",
    quest = "Quest item",
    current = "At the guild's level",
}

-- When each item was last deposited, by the ledger: { [id] = time }, and how far back the ledger
-- reaches. An item with no deposit in it has been in the bank at least that long.
function Cleanup:Deposits()
    local last, oldest = {}, nil
    for _, e in ipairs(Bank():Store().ledger) do
        if e.k ~= 0 then
            if not oldest or (e.t or 0) < oldest then oldest = e.t end
            if e.ty == "d" and e.id and (e.t or 0) > (last[e.id] or 0) then last[e.id] = e.t end
        end
    end
    return last, oldest
end

-- Every item with its verdict, value and reasons, sell first and the most valuable first.
function Cleanup:Rows()
    local B = Bank()
    local index = B:Index()
    self:Touch(index.list)
    local db = self:Store()
    local demand = self:Demand(DEMAND_DAYS)
    local deposits, ledgerFrom = self:Deposits()
    local requested = {}
    for _, r in pairs(db.requests or {}) do if r.st == "open" then requested[r.item] = true end end
    local t = now()
    local lowBelow = self:LowBelow()
    local stacks = {}
    for _, tab in pairs(db.tabs or {}) do
        for _, sl in pairs(tab.slots or {}) do
            local k = B.KeyOf(sl)
            stacks[k] = (stacks[k] or 0) + 1
        end
    end
    local rows = {}
    for _, e in ipairs(index.list) do
        local info = B:ItemInfo(e.id, e.l)
        local sell, req, ilvl = GuildOS.Compat.ItemValue(e.l or e.id)
        local d = demand[e.id]
        -- How long it has sat: since its last deposit in the ledger; with none there, at least as
        -- long as the ledger reaches back, or as long as this client has seen it. Not before the
        -- ledger started over has DEMAND_DAYS of withdrawals again: those went with the old one,
        -- so until then nothing is known to be untouched.
        local since = deposits[e.id]
            or math.max(math.min(ledgerFrom or t, db.seen[e.key] or t), (db.ledgerSince or 0) + (DEMAND_DAYS - STALE_DAYS) * 86400)
        local level = (req and req > 1) and req or ilvl
        local it = { have = e.total, quality = info.quality, classID = info.classID, level = level,
            lowBelow = lowBelow, need = B:NeedOf(e.id), demandLines = d and d.lines or 0,
            requested = requested[e.id], days = math.max(0, math.floor((t - since) / 86400)) }
        local verdict, n, reasons = Cleanup.Judge(it)
        local ah = GuildOS.Compat.AuctionPrice(e.id)
        local unit = sell or 0
        local where = (ah and ah > unit * AH_FACTOR) and "ah" or "vendor"
        rows[#rows + 1] = { key = e.key, id = e.id, l = e.l, have = e.total, tabs = e.tabs, verdict = verdict,
            out = n, reasons = reasons, vendor = unit * n, vendorEach = unit, ah = ah and ah * n or nil,
            where = where, days = it.days, taken = it.demandLines, marked = db.clean.marks[e.key] ~= nil,
            noValue = sell ~= nil and unit == 0, level = level, stacks = stacks[e.key] or 0 }
    end
    local order = { sell = 1, review = 2, keep = 3 }
    table.sort(rows, function(a, b)
        if a.verdict ~= b.verdict then return order[a.verdict] < order[b.verdict] end
        local va, vb = math.max(a.vendor, a.ah or 0), math.max(b.vendor, b.ah or 0)
        if va ~= vb then return va > vb end
        return a.key < b.key
    end)
    return rows
end

-- What selling every "sell" verdict would make, and the slots it would free.
function Cleanup:Summary(rows)
    local items, value, slots = 0, 0, 0
    for _, r in ipairs(rows) do
        if r.verdict == "sell" then
            items = items + 1
            value = value + math.max(r.vendor, r.ah or 0)
            if r.out >= r.have then slots = slots + (r.stacks or 0) end
        end
    end
    return items, value, slots
end

----------------------------------------------------------------------
-- Marks (officers; domain "gbankclean")
----------------------------------------------------------------------
function Cleanup:IsMarked(key) return self:Store().clean.marks[key] ~= nil end

function Cleanup:MarkedCount()
    local n = 0
    for _ in pairs(self:Store().clean.marks) do n = n + 1 end
    return n
end

-- Mark (or unmark) an item to go: `n` how many (nil: every one the bank holds).
function Cleanup:SetMark(key, on, n)
    if not GuildOS:IsOfficer() then return false end
    local marks = self:Store().clean.marks
    if on then marks[key] = { n = tonumber(n), by = GuildOS.Compat.PlayerName(), ts = now() }
    else marks[key] = nil end
    self:Broadcast()
    Bank():Refresh()
    return true
end

-- Mark every item judged "sell", each for the amount that may go.
function Cleanup:MarkSuggested()
    if not GuildOS:IsOfficer() then return 0 end
    local marks, n = self:Store().clean.marks, 0
    for _, r in ipairs(self:Rows()) do
        if r.verdict == "sell" and not marks[r.key] then
            marks[r.key] = { n = r.out < r.have and r.out or nil, by = GuildOS.Compat.PlayerName(), ts = now() }
            n = n + 1
        end
    end
    self:Broadcast()
    Bank():Refresh()
    return n
end

function Cleanup:ClearMarks()
    if not GuildOS:IsOfficer() then return end
    self:Store().clean.marks = {}
    self:Broadcast()
    Bank():Refresh()
end

function Cleanup:Broadcast(backfill)
    if not (GuildOS:IsOfficer() and GuildOS.SyncService) then return end
    local SS = GuildOS.SyncService
    local rev = backfill and SS:GetRevision("gbankclean", "marks") or SS:NextRevision("gbankclean", "marks")
    if rev <= 0 then return end
    SS:Publish("gbankclean", "snap", { marks = self:Store().clean.marks }, { rev = rev, priority = "BULK" })
end

function Cleanup:OnSync(env)
    local SS = GuildOS.SyncService
    if env.act ~= "snap" or type(env.data) ~= "table" or type(env.data.marks) ~= "table" then return end
    if not SS:ShouldApply("gbankclean", "marks", env.rev) then return end
    local out, count = {}, 0
    for key, v in pairs(env.data.marks) do
        if type(key) == "string" and #key <= 255 and type(v) == "table" and count < 500 then
            local n = GuildOS.Finite(v.n)
            out[key] = { n = n and n > 0 and math.floor(n) or nil, by = type(v.by) == "string" and v.by:sub(1, 60) or nil,
                         ts = GuildOS.Finite(v.ts) }
            count = count + 1
        end
    end
    self:Store().clean.marks = out
    SS:SetRevision("gbankclean", "marks", env.rev)
    Bank():Refresh()
end

----------------------------------------------------------------------
-- Taking the marked stacks out (at the bank)
----------------------------------------------------------------------

-- Free slots in the bags.
local function freeBagSlots()
    local free = 0
    for _, bag in ipairs(BAGS) do
        for slot = 1, GuildOS.Compat.GetContainerNumSlots(bag) do
            if not GuildOS.Compat.GetContainerItemInfo(bag, slot) then free = free + 1 end
        end
    end
    return free
end

-- The marked stacks this player may take out now: { tab, slot, key, id, c }, up to each mark's count.
function Cleanup:Queue()
    local B = Bank()
    local marks = self:Store().clean.marks
    local left = {}
    for key, m in pairs(marks) do left[key] = m.n or math.huge end
    local out = {}
    for tab = 1, math.min(GuildOS.Compat.GuildBankTabCount(), 8) do
        local _, _, viewable, _, _, remaining = GuildOS.Compat.GuildBankTabInfo(tab)
        if viewable and tonumber(remaining) ~= 0 then
            local slots = B:ReadTab(tab)
            for slot = 1, SLOTS do
                local sl = slots[slot]
                if sl then
                    local key = B.KeyOf(sl)
                    if (left[key] or 0) >= sl.c then
                        out[#out + 1] = { tab = tab, slot = slot, key = key, id = sl.id, c = sl.c }
                        left[key] = left[key] - sl.c
                    end
                end
            end
        end
    end
    return out
end

function Cleanup:IsWithdrawing() return state().withdraw ~= nil end

-- Take every marked stack out into the bags, one at a time.
function Cleanup:WithdrawMarked()
    local s = state()
    if s.withdraw then return false end
    if not Bank():IsOpen() then GuildOS:Print(L["Open the guild bank first."]); return false end
    if not GuildOS:IsOfficer() then GuildOS:Print(L["|cffFF4444Officers only.|r"]); return false end
    if Bank():SortState() then return false end   -- never with an organize run: both move the bank
    local queue = self:Queue()
    if #queue == 0 then GuildOS:Print(L["Nothing marked to take out here."]); return false end
    s.withdraw = { queue = queue, done = 0, total = #queue }
    self:WithdrawStep()
    return true
end

-- How many of an item the bags hold.
local function bagCount(id)
    local n = 0
    for _, bag in ipairs(BAGS) do
        for slot = 1, GuildOS.Compat.GetContainerNumSlots(bag) do
            local info = GuildOS.Compat.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id then n = n + (info.stackCount or 1) end
        end
    end
    return n
end

function Cleanup:WithdrawStep()
    local s = state()
    local run = s.withdraw
    if not run then return end
    if not Bank():IsOpen() then return self:StopWithdraw(L["Stopped: the bank was closed."]) end
    if GuildOS.Compat.InCombat() then return self:StopWithdraw(L["Stopped: you entered combat."]) end
    local again = function(d) GuildOS.Compat.After(d, function() GuildOS:SafeCall(Cleanup.WithdrawStep, Cleanup) end) end
    local cur = run.current
    if cur then
        -- It came out when the bags hold that many more of it; never just because the slot emptied
        -- (someone else may have moved it).
        local gained = bagCount(cur.id) - cur.bagBefore
        if gained < cur.c and GetTime() - cur.at < WITHDRAW_WAIT then return again(0.1) end
        run.current = nil
        if gained >= cur.c then
            local mine = self:Mine()
            mine.out[cur.id] = (mine.out[cur.id] or 0) + cur.c
            mine.outAt = now()
            local m = self:Store().clean.marks[cur.key]
            if m and m.n then
                m.n = m.n - cur.c
                if m.n <= 0 then self:Store().clean.marks[cur.key] = nil end
            end
            run.done, run.changed = run.done + 1, true
            run.took = run.took or {}
            run.took[cur.key] = true
            local bs = GuildOS.State.gbank
            if bs and bs.touched then bs.touched[cur.tab], bs.answered[cur.tab] = true, GetTime() end
        else
            local _, count = GuildOS.Compat.GuildBankSlot(cur.tab, cur.slot)
            if count then
                return self:StopWithdraw(L["Stopped: the bank did not let that stack out. Your rank's withdrawals may be spent."])
            end
            -- The slot emptied but nothing reached the bags: someone moved it. Skip it.
        end
        Bank():Refresh()
    end
    local nextOne = table.remove(run.queue, 1)
    if not nextOne then
        return self:StopWithdraw(string.format(L["%d stacks taken out. Sell them at any vendor with the Guild OS button."], run.done))
    end
    if freeBagSlots() == 0 then return self:StopWithdraw(L["Stopped: your bags are full."]) end
    -- Still the marked item, in the same amount: the bank may have changed since the queue was made.
    local now_ = Bank():ReadTab(nextOne.tab)[nextOne.slot]
    if not now_ or Bank().KeyOf(now_) ~= nextOne.key or now_.c ~= nextOne.c or now_.locked then
        return again(WITHDRAW_GAP)
    end
    if GuildOS.Compat.GuildBankCurrentTab() ~= nextOne.tab then GuildOS.Compat.SetGuildBankCurrentTab(nextOne.tab) end
    nextOne.bagBefore = bagCount(nextOne.id)
    GuildOS.Compat.GuildBankAutoStore(nextOne.tab, nextOne.slot)
    nextOne.at = GetTime()
    run.current = nextOne
    Bank():Refresh()
    again(WITHDRAW_GAP)
end

function Cleanup:StopWithdraw(msg)
    local s = state()
    local run = s.withdraw
    s.withdraw = nil
    if run and run.changed then
        -- A mark for every stack is done once none is left anywhere: only for items this run took,
        -- only while the bank is open, and a tab not read this visit (or not visible to this rank)
        -- counts as the guild's picture says. A tab that merely reads empty proves nothing.
        local marks = self:Store().clean.marks
        local bs = GuildOS.State.gbank
        if Bank():IsOpen() and bs then
            local left = {}
            for tab = 1, 8 do
                local _, _, viewable = GuildOS.Compat.GuildBankTabInfo(tab)
                if viewable and bs.answered[tab] then
                    for _, sl in pairs(Bank():ReadTab(tab)) do left[Bank().KeyOf(sl)] = true end
                else
                    local known = Bank():Store().tabs[tab]
                    for _, sl in pairs(known and known.slots or {}) do left[Bank().KeyOf(sl)] = true end
                end
            end
            for key in pairs(run.took or {}) do
                local m = marks[key]
                if m and not m.n and not left[key] then marks[key] = nil end
            end
        end
        -- The other officers learn what is left to take, stopped early or not.
        self:Broadcast()
    end
    if msg then GuildOS:Print(msg) end
    Bank():Refresh()
end

----------------------------------------------------------------------
-- Selling what came out (at a vendor), and the gold back in (at the bank)
----------------------------------------------------------------------

-- The stacks in the bags that may be sold as the bank's: never more of an item than this character
-- took out and still holds (what left the bags since is forgotten), and only whole stacks of it, so
-- a stack merged with the player's own copies stays. { bag, slot, id, c } and their vendor value.
function Cleanup:Sellable()
    local mine = self:Mine()
    local held = {}
    for id in pairs(mine.out) do held[id] = bagCount(id) end
    for id, n in pairs(mine.out) do
        if held[id] < n then mine.out[id] = held[id] > 0 and held[id] or nil end
    end
    local left, list, value = {}, {}, 0
    for id, n in pairs(mine.out) do left[id] = n end
    for _, bag in ipairs(BAGS) do
        for slot = 1, GuildOS.Compat.GetContainerNumSlots(bag) do
            local info = GuildOS.Compat.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            local c = info and (info.stackCount or 1)
            if id and left[id] and left[id] >= c and not info.hasNoValue then
                left[id] = left[id] - c
                list[#list + 1] = { bag = bag, slot = slot, id = id, c = c, locked = info.isLocked }
                value = value + (GuildOS.Compat.ItemValue(id) or 0) * c
            end
        end
    end
    return list, value
end

-- What the vendor bar offers: { [id] = count } and the vendor value.
function Cleanup:ToSell()
    local list, value = self:Sellable()
    local byId = {}
    for _, x in ipairs(list) do byId[x.id] = (byId[x.id] or 0) + x.c end
    return byId, value
end

function Cleanup:IsMerchantOpen() return state().merchant == true end

-- Sell, one stack at a time, only what came out of the bank.
function Cleanup:SellOut()
    local s = state()
    if not s.merchant or s.selling then return false end
    s.selling = { sold = 0, made = 0 }
    self:SellStep()
    return true
end

function Cleanup:SellStep()
    local s = state()
    local run = s.selling
    if not run then return end
    local mine = self:Mine()
    if s.merchant then
        for _, x in ipairs(self:Sellable()) do
            if not x.locked then
                mine.out[x.id] = mine.out[x.id] - x.c
                if mine.out[x.id] <= 0 then mine.out[x.id] = nil end
                GuildOS.Compat.UseContainerItem(x.bag, x.slot)
                -- Owed as it is sold, at the vendor's price: what the player spends meanwhile, or a
                -- vendor closed mid-run, never changes it.
                local made = (GuildOS.Compat.ItemValue(x.id) or 0) * x.c
                mine.toDeposit = (mine.toDeposit or 0) + made
                run.sold, run.made = run.sold + 1, run.made + made
                GuildOS.Compat.After(SELL_GAP, function() GuildOS:SafeCall(Cleanup.SellStep, Cleanup) end)
                return
            end
        end
    end
    s.selling = nil
    if run.sold > 0 then
        GuildOS:Print(string.format(L["Sold %d stacks for %s. Deposit it the next time you open the guild bank."], run.sold,
            Cleanup.MoneyText(run.made)))
    end
    if self.merchantRefresh then GuildOS:SafeCall(self.merchantRefresh) end
    Bank():Refresh()
end

-- The gold the cleanup made, owed to the bank.
function Cleanup:Owed() return self:Mine().toDeposit or 0 end

-- Put it in (at the bank), never more than the player has.
function Cleanup:DepositOwed()
    if not Bank():IsOpen() then return false end
    local owed = math.min(self:Owed(), GuildOS.Compat.PlayerMoney())
    if owed <= 0 then return false end
    GuildOS.Compat.DepositGuildBankMoney(owed)
    self:Mine().toDeposit = self:Owed() - owed
    GuildOS:Print(string.format(L["Deposited %s from the cleanup."], Cleanup.MoneyText(owed)))
    Bank():Refresh()
    return true
end
