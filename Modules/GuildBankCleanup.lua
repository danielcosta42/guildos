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
local LEVEL_SPAN = 15         -- levels above an item's required level at which it is still of use
local FEW_USERS = 0.05        -- under this share of the guild in that span, the item has few users
local AH_FACTOR = 3           -- an auction price this many times the vendor's: sell it there
local WITHDRAW_GAP = 0.6      -- seconds between two stacks taken out of the bank
local WITHDRAW_WAIT = 3       -- seconds a stack may take to leave the bank
local SELL_GAP = 0.2          -- seconds between two stacks sold to a vendor
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
    db.clean = db.clean or { marks = {}, out = {}, toDeposit = 0 }
    db.clean.marks = db.clean.marks or {}
    db.clean.out = db.clean.out or {}
    db.clean.toDeposit = db.clean.toDeposit or 0
    return db
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
        s.selling = nil
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

-- The share of the guild whose level is from `req` to `req + LEVEL_SPAN`, from the roster.
function Cleanup:LevelShare(req)
    local s = state()
    if not s.levels or (s.levelsAt or 0) < GetTime() - 60 then
        s.levels, s.levelsAt = {}, GetTime()
        for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
            local _, _, _, level = GetGuildRosterInfo(i)
            level = tonumber(level)
            if level then s.levels[#s.levels + 1] = level end
        end
    end
    local levels = s.levels
    if #levels == 0 then return 1 end
    local n = 0
    for _, lv in ipairs(levels) do if lv >= req and lv <= req + LEVEL_SPAN then n = n + 1 end end
    return n / #levels
end

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

-- The verdict on one item. `it` = { have, quality, classID, reqLevel, need, demandLines, requested,
-- days (in the bank), share (of the guild in its levels), maxLevel }. Returns the verdict, how many
-- may go, and the reasons as keys of REASON.
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

    local stale = (it.days or 0) >= STALE_DAYS and (it.demandLines or 0) == 0
    local usable = it.reqLevel and it.reqLevel > 1 and it.reqLevel < (it.maxLevel or 60)
    local fewUsers = usable and (it.share or 1) < FEW_USERS
    if stale then reasons[#reasons + 1] = "stale" end
    if fewUsers then reasons[#reasons + 1] = "lowlevel" end
    if stale and (fewUsers or it.classID == 2 or it.classID == 4) then return "sell", it.have, reasons end
    if stale or fewUsers then return "review", 0, reasons end
    reasons[#reasons + 1] = "fresh"
    return "review", 0, reasons
end

Cleanup.REASON = {
    excess = "More than the need",
    need = "Has a need",
    grey = "Grey item",
    requested = "A member asked for it",
    taken = "Taken lately",
    stale = "Untouched for a month",
    lowlevel = "Few in the guild are its level",
    fresh = "Recent",
}

-- Every item with its verdict, value and reasons, sell first and the most valuable first.
function Cleanup:Rows()
    local B = Bank()
    local index = B:Index()
    self:Touch(index.list)
    local db = self:Store()
    local demand = self:Demand(DEMAND_DAYS)
    local requested = {}
    for _, r in pairs(db.requests or {}) do if r.st == "open" then requested[r.item] = true end end
    local t = now()
    local maxLevel = GuildOS.Client.maxLevel
    local rows = {}
    for _, e in ipairs(index.list) do
        local info = B:ItemInfo(e.id, e.l)
        local sell, req = GuildOS.Compat.ItemValue(e.l or e.id)
        local d = demand[e.id]
        local it = { have = e.total, quality = info.quality, classID = info.classID, reqLevel = req,
            need = B:NeedOf(e.id), demandLines = d and d.lines or 0, requested = requested[e.id],
            days = math.floor((t - (db.seen[e.key] or t)) / 86400),
            share = req and req > 1 and self:LevelShare(req) or 1, maxLevel = maxLevel }
        local verdict, n, reasons = Cleanup.Judge(it)
        local ah = GuildOS.Compat.AuctionPrice(e.id)
        local unit = sell or 0
        local where = (ah and ah > unit * AH_FACTOR) and "ah" or "vendor"
        rows[#rows + 1] = { key = e.key, id = e.id, l = e.l, have = e.total, tabs = e.tabs, verdict = verdict,
            out = n, reasons = reasons, vendor = unit * n, vendorEach = unit, ah = ah and ah * n or nil,
            where = where, days = it.days, taken = it.demandLines, marked = db.clean.marks[e.key] ~= nil,
            noValue = sell ~= nil and unit == 0 }
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
            if r.out >= r.have then
                for _ in pairs(r.tabs or {}) do slots = slots + 1 end
            end
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
    local queue = self:Queue()
    if #queue == 0 then GuildOS:Print(L["Nothing marked to take out here."]); return false end
    s.withdraw = { queue = queue, done = 0, total = #queue }
    self:WithdrawStep()
    return true
end

function Cleanup:WithdrawStep()
    local s = state()
    local run = s.withdraw
    if not run then return end
    if not Bank():IsOpen() then return self:StopWithdraw(L["Stopped: the bank was closed."]) end
    if GuildOS.Compat.InCombat() then return self:StopWithdraw(L["Stopped: you entered combat."]) end
    local cur = run.current
    if cur then
        local _, count = GuildOS.Compat.GuildBankSlot(cur.tab, cur.slot)
        if count and GetTime() - cur.at < WITHDRAW_WAIT then
            GuildOS.Compat.After(0.1, function() GuildOS:SafeCall(Cleanup.WithdrawStep, Cleanup) end)
            return
        end
        run.current = nil
        if not count then
            -- Out of the bank and in the bags: it may now be sold.
            local outs = self:Store().clean.out
            outs[cur.id] = (outs[cur.id] or 0) + cur.c
            local marks = self:Store().clean.marks
            local m = marks[cur.key]
            if m and m.n then
                m.n = m.n - cur.c
                if m.n <= 0 then marks[cur.key] = nil end
            elseif m then
                marks[cur.key] = nil
            end
            run.done = run.done + 1
        else
            return self:StopWithdraw(L["Stopped: the bank did not let that stack out. Your rank's withdrawals may be spent."])
        end
        Bank():Refresh()
    end
    local nextOne = table.remove(run.queue, 1)
    if not nextOne then
        self:Broadcast()
        return self:StopWithdraw(string.format(L["%d stacks taken out. Sell them at any vendor with the Guild OS button."], run.done))
    end
    if freeBagSlots() == 0 then return self:StopWithdraw(L["Stopped: your bags are full."]) end
    local _, count = GuildOS.Compat.GuildBankSlot(nextOne.tab, nextOne.slot)
    if count ~= nextOne.c then
        -- The bank changed under us: skip this stack.
        GuildOS.Compat.After(WITHDRAW_GAP, function() GuildOS:SafeCall(Cleanup.WithdrawStep, Cleanup) end)
        return
    end
    if GuildOS.Compat.GuildBankCurrentTab() ~= nextOne.tab then GuildOS.Compat.SetGuildBankCurrentTab(nextOne.tab) end
    GuildOS.Compat.GuildBankAutoStore(nextOne.tab, nextOne.slot)
    nextOne.at = GetTime()
    run.current = nextOne
    Bank():Refresh()
    GuildOS.Compat.After(WITHDRAW_GAP, function() GuildOS:SafeCall(Cleanup.WithdrawStep, Cleanup) end)
end

function Cleanup:StopWithdraw(msg)
    local s = state()
    s.withdraw = nil
    if msg then GuildOS:Print(msg) end
    Bank():Refresh()
end

----------------------------------------------------------------------
-- Selling what came out (at a vendor), and the gold back in (at the bank)
----------------------------------------------------------------------

-- What came out of the bank and is still in the bags: { [id] = count }, and the vendor value.
function Cleanup:ToSell()
    local outs = self:Store().clean.out
    local inBags, value = {}, 0
    for _, bag in ipairs(BAGS) do
        for slot = 1, GuildOS.Compat.GetContainerNumSlots(bag) do
            local info = GuildOS.Compat.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and outs[id] and not info.hasNoValue then
                inBags[id] = (inBags[id] or 0) + (info.stackCount or 1)
            end
        end
    end
    local list = {}
    for id, n in pairs(outs) do
        local c = math.min(n, inBags[id] or 0)
        if c > 0 then
            list[id] = c
            value = value + (GuildOS.Compat.ItemValue(id) or 0) * c
        end
    end
    return list, value
end

function Cleanup:IsMerchantOpen() return state().merchant == true end

-- Sell, one stack at a time, only what came out of the bank: never more of an item than came out,
-- so a member's own copies stay.
function Cleanup:SellOut()
    local s = state()
    if not s.merchant then return false end
    if s.selling then return false end
    s.selling = { before = GuildOS.Compat.PlayerMoney(), sold = 0 }
    self:SellStep()
    return true
end

function Cleanup:SellStep()
    local s = state()
    local run = s.selling
    if not run or not s.merchant then return end
    local outs = self:Store().clean.out
    for _, bag in ipairs(BAGS) do
        for slot = 1, GuildOS.Compat.GetContainerNumSlots(bag) do
            local info = GuildOS.Compat.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            local c = info and (info.stackCount or 1)
            if id and outs[id] and outs[id] >= c and not info.isLocked and not info.hasNoValue then
                outs[id] = outs[id] - c
                if outs[id] <= 0 then outs[id] = nil end
                GuildOS.Compat.UseContainerItem(bag, slot)
                run.sold = run.sold + 1
                GuildOS.Compat.After(SELL_GAP, function() GuildOS:SafeCall(Cleanup.SellStep, Cleanup) end)
                return
            end
        end
    end
    -- Done: the gold it made is owed to the bank.
    GuildOS.Compat.After(SELL_GAP, function()
        local gained = math.max(0, GuildOS.Compat.PlayerMoney() - run.before)
        local db = self:Store()
        db.clean.toDeposit = (db.clean.toDeposit or 0) + gained
        s.selling = nil
        GuildOS:Print(string.format(L["Sold %d stacks for %s. Deposit it the next time you open the guild bank."], run.sold,
            Cleanup.MoneyText(gained)))
        if self.merchantRefresh then GuildOS:SafeCall(self.merchantRefresh) end
        Bank():Refresh()
    end)
end

-- The gold the cleanup made, owed to the bank.
function Cleanup:Owed() return self:Store().clean.toDeposit or 0 end

-- Put it in (at the bank), never more than the player has.
function Cleanup:DepositOwed()
    if not Bank():IsOpen() then return false end
    local owed = math.min(self:Owed(), GuildOS.Compat.PlayerMoney())
    if owed <= 0 then return false end
    GuildOS.Compat.DepositGuildBankMoney(owed)
    self:Store().clean.toDeposit = self:Owed() - owed
    GuildOS:Print(string.format(L["Deposited %s from the cleanup."], Cleanup.MoneyText(owed)))
    Bank():Refresh()
    return true
end
