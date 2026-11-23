----------------------------------------------------------------------
-- Guild OS - Guild bank (issue #380)
-- The guild bank seen from anywhere, kept in order, and accounted for.
--
--   * Scan: whoever opens the bank with the addon reads every tab they may see, its log and the
--     money, and shares the picture (SyncService domain "gbank", over GUILD only). Each tab keeps
--     the time it was read; a newer tab replaces an older one, whoever read it.
--   * Ask: a member who logs in asks for what is newer than what they have; one member with
--     something newer answers, after a random wait that any other answer cancels.
--   * Ledger: the game keeps 25 lines per tab, with no ids and only "hours ago". Each line read is
--     paired with an equal kept line a few hours apart, and only the unpaired ones are added, so a
--     read never counts a line twice and two equal deposits in one hour stay two.
--   * Organize: one move at a time on the bank's real state (GuildBankPlan), waiting for the server,
--     only on a tab where the rank withdraws without limit (a move counts as a withdrawal) or by the GM.
--   * Needs: officers set how many of an item the bank should hold (domain "gbankneed").
--   * Requests: a member asks for an item; an officer fills or declines it (domain "gbankreq").
----------------------------------------------------------------------
local GuildBank = {}
GuildOS.GuildBank = GuildBank
local L = GuildOS.L
local Plan = GuildOS.GuildBankPlan

local SLOTS = 98                 -- slots in a tab (Compat.GUILD_BANK_SLOTS)
local MAX_TABS = 8               -- the most any client has
local MAX_COUNT = 1000           -- the most one slot can hold (a stack of 1000 reagents on retail)
local MAX_ITEM_ID = 10000000     -- above any item id the game has
local QUERY_GAP = 0.35           -- seconds between tab queries when the bank opens
local QUERY_TIMEOUT = 1.5        -- seconds a tab's query may go unanswered before the tab is looked at
local READ_AFTER = 1.5           -- seconds after the last query before the tabs are read
local LOG_KEEP = 2000            -- ledger lines kept
local MONEY_KEEP = 120           -- money readings kept
local MONEY_EVERY = 6 * 3600     -- a reading equal to the last one is kept once every six hours
local MATCH_HOURS = 3            -- two lines this far apart may still be one event, when nothing else lines up
local SAME_EVENT = 3600 + 120    -- two reads of one line: under an hour apart (whole hours), plus the read's wait
local LEDGER_V = 2              -- ledgers and histories from before this held copies (#380)
local NAMELESS_V = 1            -- ledgers from before this held a nameless copy of money lines (#414)
local PUBLISH_GAP = 60           -- seconds between two pictures this client shares unasked
local ASK_DELAY = 25             -- seconds after login before asking for the bank
local ANSWER_MIN, ANSWER_MAX = 2, 8   -- seconds an answer waits, so one member answers
local FUTURE_SLACK = 300         -- seconds a received time may be ahead of ours
local HIST_MAX = 300             -- ledger lines sent in one answer
local MOVE_DELAY = 0.45          -- seconds between two moves (what sorters found the server takes)
local HOLD_MIN = 0.05            -- seconds between picking an item up and dropping it, at least
local POLL = 0.03                -- seconds between two looks while waiting on the game
-- One move in flight at a time: the guild bank takes no second operation while one is pending (a
-- pickup then fails and the item stays in hand, as seen in game, #380; BankStack waits likewise).
local CAP_START = 1              -- moves in flight at once, at first
local CAP_MAX = 1                -- moves in flight at once, at most
local REDROP_TRIES = 3           -- drops tried again while the item stays on the cursor
-- An item shows on the cursor until the server answers its drop (0.4 to 0.8 s in game): a drop is
-- tried again only well past the answers this run has seen, never during one.
local REDROP_MIN = 0.6           -- seconds after a drop before it may be tried again, at least
local REDROP_RTT = 2             -- times the run's usual answer time
local RTT_START = 0.6            -- seconds an answer is taken to take, before the run measured one
local CAP_RAMP = 6               -- moves landed in a row before one more may fly
local VERIFY_MAX = 2             -- seconds a drop may wait for the game to say the slots changed
-- The pickup also goes through the server: the cursor can take more than 0.8 s to show the item
-- (in game, #380). The drop waits for it; a drop sent before is lost, and the item then lands in hand.
local PICKUP_MAX = 2             -- seconds the cursor may take to show a picked-up item
-- The server wants a breath after each move: an operation sent right after the last one landed is
-- ignored (a pickup not taken, a drop left in hand: one every ~4 s in game, #380). BankStack waits
-- 0.4 s after every guild bank move. The pause adapts: up after a problem, down while all goes well.
local COOLDOWN_START = 0.4       -- seconds between a move landing and the next pickup, at first
local COOLDOWN_MIN = 0.2
local COOLDOWN_MAX = 1
local COOLDOWN_UP = 0.1          -- added after each problem
local COOLDOWN_DOWN = 0.05       -- taken off after COOLDOWN_CLEAN moves in a row without one
local COOLDOWN_CLEAN = 8
local TRACE_KEEP = 400           -- lines of the organize log kept in the saved variables
local DROP_FAILS = 6             -- drops the server refused in a row before a run stops
local LOCK_TIMEOUT = 8           -- seconds a slot may stay locked before the run gives up
local INFO_WAIT = 3              -- seconds to wait for item names before a run starts anyway
local BACKOFF_MAX = 4            -- seconds, at most, before a move that did not take is tried again
local MAX_MOVES = 400            -- a run never makes more moves than this
local REQ_KEEP_DAYS = 14         -- closed requests are kept this long
local REQ_MAX = 100              -- requests kept
local REQ_OPEN_PER = 10          -- open requests one member may have
local NOTE_MAX = 80              -- characters of a request's or need's note
local NEED_MAX = 60              -- needs kept

local function now() return GetServerTime() end

-- How long to wait before trying again after `n` tries that did not take: the server throttles a
-- burst of moves, so each wait doubles, up to BACKOFF_MAX.
local function backoff(n)
    return math.min(BACKOFF_MAX, MOVE_DELAY * 2 ^ math.max(0, n))
end

-- Two names for one player: the sender of an addon message comes as "Name-Realm", my own name as
-- "Name". Compared by player key.
local function keyName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return GuildOS:GetPlayerKey(name:match("^([^-]+)") or name, name:match("^[^-]+%-(.+)$"))
end
local function sameName(a, b)
    local ka = keyName(a)
    return ka ~= nil and ka == keyName(b)
end
GuildBank.SameName = function(_, a, b) return sameName(a, b) end

-- Whether a name is mine.
function GuildBank:IsMe(name) return sameName(name, GuildOS.Compat.PlayerName()) end

local function state()
    local s = GuildOS.State.gbank
    if not s then
        s = { open = false, queried = {}, answered = {}, queue = {}, touched = {}, lastSlotsAt = 0, lastPublish = 0, answer = nil, sort = nil,
              index = nil, infoWait = {}, rank = {} }
        GuildOS.State.gbank = s
    end
    return s
end

function GuildBank:Store()
    local db = GuildOS.db.guildBank
    if not db then
        db = {}
        GuildOS.db.guildBank = db
    end
    db.tabs = db.tabs or {}
    -- Ledgers kept before LEDGER_V hold copies of recent lines that cannot be told from real
    -- repeats: started over once, refilled by the next bank read.
    if db.ledgerV ~= LEDGER_V then db.ledger, db.ledgerV, db.ledgerSince, db.lastRead = {}, LEDGER_V, now(), {} end
    db.ledger = db.ledger or {}
    db.lastRead = db.lastRead or {}
    db.money = db.money or {}
    db.needs = db.needs or {}
    db.requests = db.requests or {}
    return db
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function GuildBank:Initialize()
    local db = self:Store()
    -- Once per ledger: a nameless line kept after this may be a real deposit (a member deleted, a
    -- name the client never filled in) and must not go on a later load.
    if db.namelessV ~= NAMELESS_V then
        self:DropNameless()
        db.namelessV = NAMELESS_V
    end
    state()
    if GuildOS.SyncService then
        GuildOS.SyncService:On("gbank", function(env, sender) GuildBank:OnSync(env, sender) end)
        GuildOS.SyncService:On("gbankneed", function(env, sender) GuildBank:OnNeedSync(env, sender) end)
        GuildOS.SyncService:On("gbankreq", function(env, sender) GuildBank:OnRequestSync(env, sender) end)
    end
    if not self.frame then
        self.frame = CreateFrame("Frame")
        GuildOS.Compat.RegisterGuildBankEvents(self.frame)
        self.frame:SetScript("OnEvent", function(_, event, ...) GuildOS:SafeCall(GuildBank.OnEvent, GuildBank, event, ...) end)
    end
    self:PruneRequests()
    self:HookTooltips()
    GuildOS.Compat.After(ASK_DELAY, function() GuildOS:SafeCall(GuildBank.Ask, GuildBank) end)
end

-- Whether this client has a guild bank (WoW: Forever's servers may not open one).
function GuildBank:Available()
    return GuildOS.Compat.HasGuildBank()
end

function GuildBank:OnEvent(event, arg)
    local s = state()
    if event == "GUILDBANKFRAME_OPENED" then
        self:OnOpen()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        self:OnClose()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if GuildOS.Compat.IsGuildBankerInteraction(arg) then self:OnOpen() end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if GuildOS.Compat.IsGuildBankerInteraction(arg) then self:OnClose() end
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_ITEM_LOCK_CHANGED" then
        s.lastSlotsAt = GetTime()
        -- The answer to the tab being asked: only now does that tab read true (an empty tab read
        -- before its answer would wipe what the guild knew of it).
        if event == "GUILDBANKBAGSLOTS_CHANGED" and s.waiting then
            s.answered[s.waiting] = GetTime()
            s.waiting = nil
            GuildOS.Compat.After(QUERY_GAP, function() GuildBank:QueryNext() end)
        end
        if s.open and not s.sort and not s.waiting and #s.queue == 0 then
            GuildOS:Coalesce("gbank.reread", 2, function() GuildOS:SafeCall(GuildBank.ReadOpenTabs, GuildBank, false) end)
        end
    elseif event == "GUILDBANKLOG_UPDATE" then
        if s.open then
            GuildOS:Coalesce("gbank.log", 1.5, function() GuildOS:SafeCall(GuildBank.ReadLogs, GuildBank) end)
        end
    elseif event == "GUILDBANK_UPDATE_MONEY" then
        if s.open then self:ReadMoney() end
    elseif event == "GUILDBANK_UPDATE_TABS" then
        if s.open then self:QueryAll() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        s.index = nil
        GuildOS:Coalesce("gbank.items", 1, function() GuildBank:Refresh() end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if s.sort then self:StopSort("combat") end
    end
end

-- The bank opened: query every tab and log, then read them all.
function GuildBank:OnOpen()
    local s = state()
    if s.open then return end   -- the second event of the pair
    s.open = true
    s.queried, s.answered, s.queue, s.waiting, s.touched = {}, {}, {}, nil, {}
    s.openId = (s.openId or 0) + 1
    self:QueryAll()
    if self.bankOpened then GuildOS:SafeCall(self.bankOpened) end
    self:Refresh()
end

function GuildBank:OnClose()
    local s = state()
    if not s.open then return end
    if s.sort then self:StopSort("closed") end
    self:ReadOpenTabs(true)
    s.open = false
    if self.bankClosed then GuildOS:SafeCall(self.bankClosed) end
    self:Refresh()
end

function GuildBank:IsOpen() return state().open end

-- Ask the server for every tab this player may see, one at a time: the next is asked once the
-- last one answered (or did not, in QUERY_TIMEOUT), then the logs and money are read.
function GuildBank:QueryAll()
    local s = state()
    local n = GuildOS.Compat.GuildBankTabCount()
    s.queue = {}
    for tab = 1, math.min(n, MAX_TABS) do
        local _, _, viewable = GuildOS.Compat.GuildBankTabInfo(tab)
        if viewable then s.queue[#s.queue + 1] = tab end
    end
    if not s.waiting then self:QueryNext() end
end

function GuildBank:QueryNext()
    local s = state()
    if not s.open or s.waiting then return end
    local tab = table.remove(s.queue, 1)
    if not tab then
        GuildOS.Compat.QueryGuildBankLog(GuildOS.Compat.GuildBankMaxTabs() + 1)
        GuildOS.Compat.After(READ_AFTER, function()
            if not s.open then return end
            GuildOS:SafeCall(GuildBank.ReadOpenTabs, GuildBank, true)
            GuildOS:SafeCall(GuildBank.ReadLogs, GuildBank)
        end)
        return
    end
    s.waiting = tab
    s.queried[tab] = GetTime()
    GuildOS.Compat.QueryGuildBankTab(tab)
    GuildOS.Compat.QueryGuildBankLog(tab)
    local openId = s.openId
    GuildOS.Compat.After(QUERY_TIMEOUT, function()
        -- No word from the game: WoW: Forever sends none for a tab it already has (the bank was
        -- never saved there, #380). The tab itself answers: one holding items, or the one the bank
        -- shows, is loaded. An empty one that is neither is left as the guild knew it.
        if s.openId == openId and s.waiting == tab then
            s.waiting = nil
            -- Only items prove a tab loaded: the tab on show reads empty too until it is.
            local loaded = false
            for i = 1, SLOTS do
                if GuildOS.Compat.GuildBankSlot(tab, i) then loaded = true; break end
            end
            if loaded then s.answered[tab] = GetTime() end
            self:Trace("tab %d: no word from the game; %s", tab, loaded and "its items are there, read" or "empty, left as known")
            self:QueryNext()
        end
    end)
end

----------------------------------------------------------------------
-- Items
----------------------------------------------------------------------

-- What a link stores: the item id, and the link's own string ("item:…" or "battlepet:…") only for
-- equipment and pets, which differ from one copy to the next.
local function parseLink(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("|H(item:[^|]+)|h") or link:match("^(item:[%d:%-]+)$")
    local pet = link:match("|H(battlepet:[^|]+)|h") or link:match("^(battlepet:[%d:%-]+)$")
    if pet then return 82800, pet end   -- the pet cage's item id
    if not body then return nil end
    local id = tonumber(body:match("^item:(%d+)"))
    if not id then return nil end
    local _, _, classID = GuildOS.Compat.ItemInstant(id)
    if classID == 2 or classID == 4 then return id, body end
    return id, nil
end
GuildBank._parseLink = parseLink

-- The key an item is counted under: its link string for equipment and pets, its id otherwise.
local function keyOf(slot)
    return slot.l or tostring(slot.id)
end
GuildBank.KeyOf = keyOf

-- What the client knows of an item: { id, link, icon, name, quality, level, stack, classID, subClassID }.
-- Names and qualities arrive later for an item not yet cached; GET_ITEM_INFO_RECEIVED redraws.
function GuildBank:ItemInfo(id, l)
    local ref = l or id
    local _, icon, classID, subClassID = GuildOS.Compat.ItemInstant(ref)
    local name, quality, level, stack = GuildOS.Compat.ItemDetails(ref)
    return { id = id, l = l, icon = icon, classID = classID, subClassID = subClassID,
             name = name, quality = quality, level = level, stack = stack }
end

-- A clickable link for an item, or nil while the client does not have it.
function GuildBank:LinkOf(id, l)
    local _, link = GuildOS.Compat.GetItemInfo(l or id)
    return link
end

----------------------------------------------------------------------
-- Reading the bank (at the bank only)
----------------------------------------------------------------------

-- One tab as the game shows it now: slots[i] = { id, c, l, locked }, or nil if the data is not there.
function GuildBank:ReadTab(tab)
    local slots = {}
    for i = 1, SLOTS do
        local _, count, locked, link = GuildOS.Compat.GuildBankSlot(tab, i)
        if count then
            local id, l = parseLink(link)
            if id then slots[i] = { id = id, c = count, l = l, locked = locked } end
        end
    end
    return slots
end

-- Read every tab the server has answered for since it was queried, keep it, and share the picture
-- when `publish` (or when a while has passed).
function GuildBank:ReadOpenTabs(publish)
    local s = state()
    if not s.open then return end
    local db = self:Store()
    local me = GuildOS.Compat.PlayerName()
    local t = now()
    local changed = false
    local count = math.min(GuildOS.Compat.GuildBankTabCount(), MAX_TABS)
    db.numTabs = count
    for tab = 1, count do
        local name, icon, viewable = GuildOS.Compat.GuildBankTabInfo(tab)
        -- A tab is read only once the server answered its own query: before that the game answers
        -- an empty tab, and an empty tab would wipe what the guild knew.
        local slots = (viewable and s.answered[tab]) and self:ReadTab(tab) or nil
        -- An empty read never wipes a tab the guild saw holding items (a tab not yet loaded reads
        -- empty), unless this client emptied it itself, organizing or taking stacks out.
        if slots and next(slots) == nil and db.tabs[tab] and next(db.tabs[tab].slots or {}) ~= nil
            and not s.touched[tab] then
            slots = nil
        end
        if slots then
            for _, v in pairs(slots) do v.locked = nil end
            db.tabs[tab] = { name = name, icon = icon, ts = t, by = me, slots = slots }
            changed = true
        elseif db.tabs[tab] then
            db.tabs[tab].name = name or db.tabs[tab].name
            db.tabs[tab].icon = icon or db.tabs[tab].icon
        end
    end
    for tab = count + 1, MAX_TABS do db.tabs[tab] = nil end
    self:ReadMoney()
    if changed then
        s.index = nil
        self:Refresh()
        if publish or now() - s.lastPublish >= PUBLISH_GAP then self:PublishSnapshot() end
    end
end

function GuildBank:ReadMoney()
    local money = GuildOS.Compat.GuildBankMoney()
    if not money then return end
    local db = self:Store()
    db.moneyNow, db.moneyTs, db.moneyBy = money, now(), GuildOS.Compat.PlayerName()
    self:AddMoneyReading(db.moneyTs, money)
end

function GuildBank:AddMoneyReading(t, money)
    local list = self:Store().money
    local last = list[#list]
    if last and t <= last.t then return end
    if last and last.m == money and t - last.t < MONEY_EVERY then return end
    list[#list + 1] = { t = t, m = money }
    while #list > MONEY_KEEP do table.remove(list, 1) end
end

----------------------------------------------------------------------
-- Ledger
----------------------------------------------------------------------
local ITEM_TYPES = { deposit = "d", withdraw = "w", move = "m" }
local MONEY_TYPES = { deposit = "d", withdraw = "w", repair = "r", withdrawForTab = "w", buyTab = "b",
                      depositSummary = "s" }
GuildBank.ITEM_TYPES, GuildBank.MONEY_TYPES = ITEM_TYPES, MONEY_TYPES

local function sig(e)
    return table.concat({ e.ty or "", e.n or "", e.id or 0, e.c or 0, e.g or 0, e.t2 or 0 }, "|")
end
GuildBank._sig = sig

-- The game gives a line's name as nil until the client knows it (shown as "?"): such a line is the
-- same event as a named one that agrees in all else (#414).
local function named(e) return type(e.n) == "string" and e.n ~= "" and e.n ~= "?" end
-- What a line says but its name.
local function body(e)
    return table.concat({ e.ty or "", e.id or 0, e.c or 0, e.g or 0, e.t2 or 0 }, "|")
end
-- Whether two lines with the same body may be one event: same name, or one of them has none.
local function sameWho(a, b)
    if named(a) and named(b) then return a.n == b.n end
    return true
end
GuildBank.LEDGER_V = LEDGER_V

-- The lines of stream `k` (a tab, or 0 for money) in the ledger, in the order they were added.
function GuildBank:Stream(k)
    local out = {}
    for _, e in ipairs(self:Store().ledger) do
        if e.k == k then out[#out + 1] = e end
    end
    return out
end

-- Add a read of stream `k` (`list`, oldest first, each with an absolute time) to the ledger.
-- Lines agree when kind, name, item, count, gold and target tab do. The game's log is a window with
-- no gaps, so a read is lined up by position, a line matching only one read of the same event
-- (under SAME_EVENT apart):
--   1. the longest run at its start that matches the end of what is kept is there; what follows
--      is new (a line whose equal twin has scrolled out of the log is still new);
--   2. a read matched whole before the end (late, or a repeating pattern) adds nothing;
--   3. with neither (more lines than the log holds since the last read, a peer's history with a
--      line this client missed, or one in another order): a line an hour past everything kept is
--      a later event, so new; any other pairs with the nearest agreeing kept line within
--      MATCH_HOURS not paired already, and only the unpaired are new (two equal deposits in one
--      hour stay two). These go in at their time, so the stream's end stays the newest lines.
-- A line with no name (the game had not filled it in) agrees with one that has a name and agrees in
-- all else, and takes that name: one event read before and after its name came is one line (#414).
-- Returns how many lines were added, then how many kept lines got their name. Pure apart from the
-- ledger it writes.
function GuildBank:MergeStream(k, list)
    local kept = self:Stream(k)
    local ks, ls, newest = {}, {}, -math.huge
    for i, e in ipairs(kept) do ks[i] = body(e); newest = math.max(newest, e.t or 0) end
    for i, e in ipairs(list) do ls[i] = body(e) end
    local filled = 0
    local function fill(keptLine, read)   -- a kept line without a name takes the read's
        if not named(keptLine) and named(read) then keptLine.n = read.n; filled = filled + 1 end
    end
    local function runAt(j, n)   -- list[1..n] is kept[j..j+n-1], read again
        for i = 1, n do
            local a = kept[j + i - 1]
            if ks[j + i - 1] ~= ls[i] or not sameWho(a, list[i])
                or math.abs((a.t or 0) - (list[i].t or 0)) >= SAME_EVENT then return false end
        end
        return true
    end
    local function fillRun(j, n) for i = 1, n do fill(kept[j + i - 1], list[i]) end end
    local best = 0
    for n = math.min(#kept, #list), 1, -1 do
        if runAt(#kept - n + 1, n) then best = n; break end
    end
    local new, atEnd = {}, true
    if best == #list then fillRun(#kept - best + 1, best) end
    if best < #list then
        for j = #kept - #list, 1, -1 do
            if runAt(j, #list) then fillRun(j, #list); return 0, filled end
        end
        if best > 0 then
            fillRun(#kept - best + 1, best)
            for i = best + 1, #list do new[#new + 1] = list[i] end
        else
            atEnd = false
            local bySig, taken, tol = {}, {}, MATCH_HOURS * 3600
            for i, e in ipairs(kept) do
                bySig[ks[i]] = bySig[ks[i]] or {}
                table.insert(bySig[ks[i]], e)
            end
            -- Lines with the same name pair first, so a nameless line never takes the twin a named
            -- line needs (two equal deposits by one member stay two).
            local pickOf = {}
            for pass = 1, 2 do
                for i, e in ipairs(list) do
                    if not pickOf[i] and (e.t or 0) < newest + SAME_EVENT then
                        local pick, pickD
                        for _, c in ipairs(bySig[ls[i]] or {}) do
                            local d = math.abs((c.t or 0) - (e.t or 0))
                            -- A nameless line pairs only with a read of the same event (under
                            -- SAME_EVENT apart): further off it may be another member's equal deposit.
                            local who = pass == 1 and c.n == e.n or pass == 2 and sameWho(c, e) and d < SAME_EVENT
                            if who and not taken[c] and d <= tol and (not pickD or d < pickD) then pick, pickD = c, d end
                        end
                        if pick then taken[pick], pickOf[i] = true, pick end
                    end
                end
            end
            for i, e in ipairs(list) do
                if pickOf[i] then fill(pickOf[i], e) else new[#new + 1] = e end
            end
        end
    end
    local ledger = self:Store().ledger
    for _, e in ipairs(new) do
        local pos = #ledger + 1
        if not atEnd then
            -- Before the stream's kept lines that are newer than it.
            for i = #ledger, 1, -1 do
                local x = ledger[i]
                if x.k == k then
                    if (x.t or 0) <= (e.t or 0) then break end
                    pos = i
                end
            end
        end
        table.insert(ledger, pos, { k = k, t = e.t, ty = e.ty, n = e.n, id = e.id, c = e.c, g = e.g, t2 = e.t2 })
    end
    while #ledger > LOG_KEEP do table.remove(ledger, 1) end
    return #new, filled
end

-- Ledgers saved before #414 hold each money line twice when it was read once before its name came:
-- a line without a name and, under SAME_EVENT from it, the same line with one. Each nameless line
-- goes with the nearest such named line of its stream not taken by another (so two equal deposits by
-- one member stay two). Run once per ledger (namelessV). Returns how many lines went.
function GuildBank:DropNameless()
    local ledger = self:Store().ledger
    local groups = {}
    for _, e in ipairs(ledger) do
        local g = (e.k or 0) .. "|" .. body(e)
        groups[g] = groups[g] or { named = {}, nameless = {} }
        table.insert(named(e) and groups[g].named or groups[g].nameless, e)
    end
    local drop, tol = {}, SAME_EVENT
    for _, g in pairs(groups) do
        if #g.nameless > 0 and #g.named > 0 then
            local pairs_ = {}
            for _, u in ipairs(g.nameless) do
                for _, x in ipairs(g.named) do
                    local d = math.abs((u.t or 0) - (x.t or 0))
                    if d <= tol then pairs_[#pairs_ + 1] = { u = u, x = x, d = d } end
                end
            end
            table.sort(pairs_, function(a, b) return a.d < b.d end)
            local used = {}
            for _, p in ipairs(pairs_) do
                if not drop[p.u] and not used[p.x] then drop[p.u], used[p.x] = true, true end
            end
        end
    end
    local n = 0
    for i = #ledger, 1, -1 do
        if drop[ledger[i]] then table.remove(ledger, i); n = n + 1 end
    end
    return n
end

-- A log as the game gave it, by what it says rather than its text (a link or a name the client
-- fills in later must not make a cached log look new): the same means the client's cached log,
-- read again, whose "hours ago" are as old as when it arrived.
local function rawKey(rows)
    local parts = {}
    for i, r in ipairs(rows) do
        parts[i] = table.concat({ r.type or "", parseLink(r.link) or 0, r.count or r.amount or 0,
            r.tab1 or 0, r.tab2 or 0, r.ago or 0 }, "|")
    end
    return table.concat(parts, "\n")
end

-- Read every tab's log and the money log, add them, and share the reads that added something.
function GuildBank:ReadLogs()
    local s = state()
    if not s.open then return end
    local t = now()
    local reads = {}
    local lastRead = self:Store().lastRead
    -- A log the same as the last one read of its stream (kept across sessions: the client caches
    -- logs) has nothing new and is skipped.
    local function take(k, rows, list)
        local key = rawKey(rows)
        if key == lastRead[k] then return end
        lastRead[k] = key
        if #list == 0 then return end
        local added, filled = self:MergeStream(k, list)
        if added > 0 or filled > 0 then reads[#reads + 1] = { k = k, list = list } end
    end
    for tab = 1, math.min(GuildOS.Compat.GuildBankTabCount(), MAX_TABS) do
        if s.queried[tab] then
            local rows, list = GuildOS.Compat.GuildBankItemLog(tab), {}
            for _, row in ipairs(rows) do
                local ty = ITEM_TYPES[row.type]
                local id = parseLink(row.link)
                if ty and row.name then
                    list[#list + 1] = { t = t - row.ago * 3600, ty = ty, n = row.name, id = id, c = row.count,
                        t2 = ty == "m" and row.tab2 or nil }
                end
            end
            take(tab, rows, list)
        end
    end
    local rows, money = GuildOS.Compat.GuildBankMoneyLog(), {}
    for _, row in ipairs(rows) do
        local ty = MONEY_TYPES[row.type]
        if ty then money[#money + 1] = { t = t - row.ago * 3600, ty = ty, n = row.name, g = row.amount } end
    end
    take(0, rows, money)
    if #reads > 0 then
        self:Refresh()
        if GuildOS.SyncService then
            GuildOS.SyncService:Publish("gbank", "log", { v = LEDGER_V, reads = reads }, { priority = "BULK" })
        end
    end
end

-- Totals per member over the last `days`: { name = { di, dg, wi, wg, n } } (items and copper in,
-- items and copper out, lines).
function GuildBank:Contributions(days)
    local since = now() - days * 86400
    local out = {}
    for _, e in ipairs(self:Store().ledger) do
        if (e.t or 0) >= since and e.n and (e.ty == "d" or e.ty == "w" or e.ty == "r") then
            local r = out[e.n]
            if not r then r = { di = 0, dg = 0, wi = 0, wg = 0, n = 0 }; out[e.n] = r end
            r.n = r.n + 1
            if e.ty == "d" then
                if e.k == 0 then r.dg = r.dg + (e.g or 0) else r.di = r.di + (e.c or 0) end
            else
                if e.k == 0 then r.wg = r.wg + (e.g or 0) else r.wi = r.wi + (e.c or 0) end
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- What the bank holds (anywhere)
----------------------------------------------------------------------

-- Every item across every tab: list of { key, id, l, total, tabs = { [tab] = count } }, cached
-- until the picture changes.
function GuildBank:Index()
    local s = state()
    if s.index then return s.index end
    local byKey, list = {}, {}
    for tab, t in pairs(self:Store().tabs) do
        for _, slot in pairs(t.slots or {}) do
            local k = keyOf(slot)
            local e = byKey[k]
            if not e then
                e = { key = k, id = slot.id, l = slot.l, total = 0, tabs = {} }
                byKey[k] = e
                list[#list + 1] = e
            end
            e.total = e.total + slot.c
            e.tabs[tab] = (e.tabs[tab] or 0) + slot.c
        end
    end
    local byId = {}
    for _, e in ipairs(list) do byId[e.id] = (byId[e.id] or 0) + e.total end
    s.index = { list = list, byKey = byKey, byId = byId }
    -- When each item was first seen: the cleanup's "untouched for a month".
    if GuildOS.GuildBankCleanup then GuildOS:SafeCall(GuildOS.GuildBankCleanup.Touch, GuildOS.GuildBankCleanup, list) end
    return s.index
end

-- How many of an item id the bank holds, by the last picture.
function GuildBank:CountOf(id)
    return self:Index().byId[tonumber(id) or 0] or 0
end

-- The newest time any tab was read, and who read it.
function GuildBank:Newest()
    local ts, by = 0, nil
    for _, t in pairs(self:Store().tabs) do
        if (t.ts or 0) > ts then ts, by = t.ts, t.by end
    end
    return ts, by
end

-- Slots used and slots there are, across the tabs in the picture.
function GuildBank:Fill()
    local used, total = 0, 0
    for _, t in pairs(self:Store().tabs) do
        total = total + SLOTS
        for _ in pairs(t.slots or {}) do used = used + 1 end
    end
    return used, total
end

-- The sort key and stack size of an item, cached for the session once its name is known.
function GuildBank:RankOf(id, l)
    local s = state()
    local k = l or tostring(id)
    local r = s.rank[k]
    if r then return r.key, r.stack end
    local info = self:ItemInfo(id, l)
    local key = Plan.SortKey(info)
    if info.name then s.rank[k] = { key = key, stack = info.stack } end
    return key, info.stack
end

-- A tab as the slots[1..98] = { k, c } the planner reads, and the rank and stack tables it needs.
function GuildBank:PlanInput(slots)
    local plain, rank, stack = {}, {}, {}
    for i = 1, SLOTS do
        local s = slots[i]
        if s then
            local k = keyOf(s)
            plain[i] = { k = k, c = s.c }
            if not rank[k] then rank[k], stack[k] = self:RankOf(s.id, s.l) end
            -- An unknown stack size never merges: at least what the slot already holds fits.
            stack[k] = math.max(tonumber(stack[k]) or 1, s.c)
        end
    end
    return plain, rank, stack
end

-- What a tab of the picture looks like organized: the target slots, and the moves it would take.
function GuildBank:Preview(tab)
    local t = self:Store().tabs[tab]
    if not t then return nil end
    local plain, rank, stack = self:PlanInput(t.slots or {})
    local target = Plan.Target(plain, SLOTS, rank, stack)
    local moves, why = Plan.CountMoves(plain, SLOTS, rank, stack, MAX_MOVES, GuildOS:GetSetting("gbankSwap") ~= false)
    local byKey = {}
    for _, s in pairs(t.slots or {}) do byKey[keyOf(s)] = s end
    local out = {}
    for i, want in ipairs(target) do
        local src = byKey[want.k]
        out[i] = { id = src.id, l = src.l, c = want.c }
    end
    return out, moves, why == "full"
end

----------------------------------------------------------------------
-- Sharing the picture (domain "gbank")
----------------------------------------------------------------------

-- A tab's slots as one string: "slot,id,count[,link];…". A link never holds "," or ";".
local function encodeSlots(slots)
    local parts = {}
    for i = 1, SLOTS do
        local s = slots[i]
        if s then
            parts[#parts + 1] = s.l and string.format("%d,%d,%d,%s", i, s.id, s.c, s.l)
                or string.format("%d,%d,%d", i, s.id, s.c)
        end
    end
    return table.concat(parts, ";")
end

local function validLink(l)
    return type(l) == "string" and #l <= 255 and (l:match("^item:[%d:%-]+$") or l:match("^battlepet:[%d:%-]+$")) ~= nil
end

local function decodeSlots(str)
    local slots = {}
    if type(str) ~= "string" or #str > 40000 then return slots end
    for part in str:gmatch("[^;]+") do
        local i, id, c, l = part:match("^(%d+),(%d+),(%d+),?(.*)$")
        i, id, c = tonumber(i), tonumber(id), tonumber(c)
        if i and id and c and i >= 1 and i <= SLOTS and id > 0 and id < MAX_ITEM_ID and c >= 1 and c <= MAX_COUNT then
            slots[i] = { id = id, c = c, l = (l ~= "" and validLink(l)) and l or nil }
        end
    end
    return slots
end
GuildBank._encodeSlots, GuildBank._decodeSlots = encodeSlots, decodeSlots

local function cleanText(v, max)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[%c|]", ""):sub(1, max)
    if v == "" then return nil end
    return v
end

function GuildBank:SnapshotPayload()
    local db = self:Store()
    local tabs = {}
    for tab, t in pairs(db.tabs) do
        tabs[tab] = { n = t.name, ic = t.icon, ts = t.ts, by = t.by, s = encodeSlots(t.slots or {}) }
    end
    return { tabs = tabs, nt = db.numTabs, m = db.moneyNow, mt = db.moneyTs }
end

function GuildBank:PublishSnapshot()
    if not GuildOS.SyncService then return end
    local s = state()
    s.lastPublish = now()
    GuildOS.SyncService:Publish("gbank", "snap", self:SnapshotPayload(), { priority = "BULK" })
end

-- Take, tab by tab, what is newer than ours from a picture someone shared. Returns whether
-- anything changed.
function GuildBank:ApplySnapshot(data, sender)
    if type(data) ~= "table" or type(data.tabs) ~= "table" then return false end
    local db = self:Store()
    local limit = now() + FUTURE_SLACK
    local changed = false
    for tab, t in pairs(data.tabs) do
        tab = tonumber(tab)
        local ts = GuildOS.Finite(type(t) == "table" and t.ts)
        if ts and ts > limit then ts = nil end   -- from the future: refused
        if ts then ts = math.min(ts, now()) end   -- a little ahead (clocks differ): taken as now
        if tab and tab >= 1 and tab <= MAX_TABS and tab == math.floor(tab) and ts then
            local mine = db.tabs[tab]
            if not mine or ts > (mine.ts or 0) then
                db.tabs[tab] = { name = cleanText(t.n, 40), icon = tonumber(t.ic) or (type(t.ic) == "string" and #t.ic < 200 and t.ic) or nil,
                                 ts = ts, by = cleanText(t.by, 60) or sender, slots = decodeSlots(t.s) }
                changed = true
            end
        end
    end
    local nt = tonumber(data.nt)
    -- The tab count of whoever read last: a bought tab shows, a forged count passes with the next read.
    if changed and nt and nt >= 0 and nt <= MAX_TABS and nt == math.floor(nt) then
        db.numTabs = nt
    end
    local m, mt = GuildOS.Finite(data.m), GuildOS.Finite(data.mt)
    if m and mt and m >= 0 and mt <= limit and mt > (db.moneyTs or 0) then
        db.moneyNow, db.moneyTs, db.moneyBy = math.floor(m), mt, sender
        self:AddMoneyReading(mt, math.floor(m))
        changed = true
    end
    if changed then state().index = nil end
    return changed
end

-- A ledger read someone shared, cleaned up line by line.
local function cleanRead(read, limit)
    if type(read) ~= "table" or type(read.list) ~= "table" then return nil end
    local k = tonumber(read.k)
    if not k or k < 0 or k > MAX_TABS or k ~= math.floor(k) then return nil end
    local out = {}
    for i, e in ipairs(read.list) do
        if i > HIST_MAX then break end
        local t = GuildOS.Finite(type(e) == "table" and e.t)
        local ty = type(e) == "table" and e.ty
        if t and t <= limit and (ty == "d" or ty == "w" or ty == "m" or ty == "r" or ty == "b" or ty == "s") then
            local id = tonumber(e.id)
            out[#out + 1] = { t = math.floor(t), ty = ty, n = cleanText(e.n, 60),
                id = (id and id > 0 and id < MAX_ITEM_ID) and id or nil,
                c = GuildOS.Finite(e.c) and math.max(0, math.min(MAX_COUNT, math.floor(e.c))) or nil,
                g = GuildOS.Finite(e.g) and math.max(0, math.floor(e.g)) or nil,
                t2 = tonumber(e.t2) and math.floor(e.t2) or nil }
        end
    end
    -- In time order, lines of one time kept in the order sent (table.sort is not stable).
    for i, e in ipairs(out) do e.seq = i end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.seq < b.seq end)
    for _, e in ipairs(out) do e.seq = nil end
    return k, out
end

function GuildBank:OnSync(env, sender)
    local data = env.data
    if type(data) ~= "table" then return end
    local s = state()
    if env.act == "snap" then
        if self:ApplySnapshot(data, sender) then self:Refresh() end
        -- Someone answered at least as new as we would have: our answer is not needed.
        if s.answer and s.answer.snap then
            local newest = 0
            for _, t in pairs(data.tabs or {}) do newest = math.max(newest, GuildOS.Finite(type(t) == "table" and t.ts) or 0) end
            if newest >= s.answer.snap then s.answer.snap = nil end
        end
    elseif (env.act == "log" or env.act == "hist") and data.v ~= LEDGER_V then
        -- From an older version, whose ledger kept copies and re-dated cached logs: not taken, and
        -- not an answer.
        return
    elseif env.act == "log" or env.act == "hist" then
        local limit = now() + FUTURE_SLACK
        local added = 0
        for _, read in ipairs(type(data.reads) == "table" and data.reads or {}) do
            local k, list = cleanRead(read, limit)
            if k and #list > 0 then
                local a, f = self:MergeStream(k, list)
                added = added + a + f
            end
        end
        if added > 0 then self:Refresh() end
        if env.act == "hist" and s.answer then s.answer.hist = nil end
    elseif env.act == "reqs" then
        -- Requests a member missed, only from an officer: a member could otherwise close or rewrite
        -- anyone's request in a backfill.
        if type(data.req) == "table" and GuildOS:IsOfficerByName(sender) then
            self:MergeRequests(data.req)
            self:Refresh()
            -- Another officer answered as new as we would have: our answer is not needed.
            if s.reqAnswer and (GuildOS.Finite(data.mark) or 0) >= s.reqAnswer then s.reqAnswer = nil end
        end
    elseif env.act == "ask" then
        self:OnAsk(data, sender)
    end
end

-- What this client has, for an ask: the newest tab, the newest ledger line, the newest request change.
function GuildBank:Marks()
    local ledger = self:Store().ledger
    local newestReq = 0
    for _, r in pairs(self:Store().requests) do newestReq = math.max(newestReq, r.at or 0) end
    local newestLine = 0
    for _, e in ipairs(ledger) do if (e.t or 0) > newestLine then newestLine = e.t end end
    return (self:Newest()), newestLine, newestReq
end

-- Ask the guild for what is newer than what this client has.
function GuildBank:Ask()
    if not (GuildOS.SyncService and IsInGuild() and self:Available()) then return end
    local ts, lt, rq = self:Marks()
    GuildOS.SyncService:Publish("gbank", "ask", { ts = ts, lt = lt, rq = rq }, { priority = "BULK" })
end

-- Someone asked: answer, once a random wait passes with nobody else answering, with what is newer.
function GuildBank:OnAsk(data, sender)
    if self:IsMe(sender) then return end
    local s = state()
    local ts, lt = self:Marks()
    local theirTs, theirLt = GuildOS.Finite(data.ts) or 0, GuildOS.Finite(data.lt) or 0
    local wantSnap = ts > theirTs and ts or nil
    local wantHist = lt > theirLt + 3600 and theirLt or nil
    if GuildOS:IsOfficer() then
        local rev = GuildOS.SyncService:GetRevision("gbankneed", "needs")
        local _, _, rq = self:Marks()
        local theirRq = GuildOS.Finite(data.rq) or 0
        -- One officer answers each: any other officer's answer as new cancels ours.
        -- The cleanup's marks ride along with the needs: one officer's answer carries both.
        if rev > 0 and not s.needAnswer then
            s.needAnswer = rev
            GuildOS.Compat.After(ANSWER_MIN + math.random() * (ANSWER_MAX - ANSWER_MIN), function()
                if s.needAnswer then
                    s.needAnswer = nil
                    GuildBank:BroadcastNeeds(true)
                    if GuildOS.GuildBankCleanup then GuildOS.GuildBankCleanup:Broadcast(true) end
                end
            end)
        end
        if rq > theirRq and not s.reqAnswer then
            s.reqAnswer = rq
            GuildOS.Compat.After(ANSWER_MIN + math.random() * (ANSWER_MAX - ANSWER_MIN), function()
                if s.reqAnswer then
                    s.reqAnswer = nil
                    GuildOS.SyncService:Publish("gbank", "reqs", { req = GuildBank:Store().requests, mark = rq }, { priority = "BULK" })
                end
            end)
        end
    end
    if not (wantSnap or wantHist) or s.answer then return end
    s.answer = { snap = wantSnap, hist = wantHist and true or nil }
    GuildOS.Compat.After(ANSWER_MIN + math.random() * (ANSWER_MAX - ANSWER_MIN), function()
        local a = s.answer
        s.answer = nil
        if not a then return end
        if a.snap then self:PublishSnapshot() end
        if a.hist then self:PublishHistory(theirLt) end
    end)
end

-- The ledger since `since` (a little before, so the receiver can line it up), and the open and
-- recent requests.
function GuildBank:PublishHistory(since)
    local from = (since or 0) - MATCH_HOURS * 3600
    local streams, reads = {}, {}
    for _, e in ipairs(self:Store().ledger) do
        if (e.t or 0) >= from then
            local list = streams[e.k]
            if not list then list = {}; streams[e.k] = list; reads[#reads + 1] = { k = e.k, list = list } end
            list[#list + 1] = e
        end
    end
    for _, r in ipairs(reads) do
        while #r.list > HIST_MAX do table.remove(r.list, 1) end
    end
    GuildOS.SyncService:Publish("gbank", "hist", { v = LEDGER_V, reads = reads }, { priority = "BULK" })
end

----------------------------------------------------------------------
-- Needs (officers; domain "gbankneed")
----------------------------------------------------------------------
function GuildBank:Needs() return self:Store().needs end

-- How many the bank should hold of an item, or nil.
function GuildBank:NeedOf(id)
    local n = self:Store().needs[tonumber(id) or 0]
    return n and n.n or nil
end

function GuildBank:SetNeed(id, n, note)
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return false
    end
    id, n = tonumber(id), tonumber(n)
    if not id or id <= 0 or id >= MAX_ITEM_ID then return false end
    local needs = self:Store().needs
    if not n or n <= 0 then
        needs[id] = nil
    else
        local count = 0
        for _ in pairs(needs) do count = count + 1 end
        if not needs[id] and count >= NEED_MAX then
            GuildOS:Print(string.format(L["The bank keeps at most %d needs."], NEED_MAX))
            return false
        end
        needs[id] = { n = math.min(math.floor(n), 100000), note = cleanText(note, NOTE_MAX),
                      by = GuildOS.Compat.PlayerName(), ts = now() }
    end
    self:BroadcastNeeds()
    self:Refresh()
    return true
end

function GuildBank:BroadcastNeeds(backfill)
    if not (GuildOS:IsOfficer() and GuildOS.SyncService) then return end
    local SS = GuildOS.SyncService
    local rev = backfill and SS:GetRevision("gbankneed", "needs") or SS:NextRevision("gbankneed", "needs")
    if rev <= 0 then return end
    SS:Publish("gbankneed", "snap", { needs = self:Store().needs }, { rev = rev, priority = "BULK" })
end

function GuildBank:OnNeedSync(env)
    local SS = GuildOS.SyncService
    if env.act ~= "snap" or type(env.data) ~= "table" or type(env.data.needs) ~= "table" then return end
    local s = state()
    if s.needAnswer and (env.rev or 0) >= s.needAnswer then s.needAnswer = nil end
    if not SS:ShouldApply("gbankneed", "needs", env.rev) then return end
    local out, count = {}, 0
    for id, v in pairs(env.data.needs) do
        id = tonumber(id)
        local n = type(v) == "table" and GuildOS.Finite(v.n)
        if id and id > 0 and id < MAX_ITEM_ID and n and n > 0 and count < NEED_MAX then
            out[id] = { n = math.min(math.floor(n), 100000), note = cleanText(v.note, NOTE_MAX),
                        by = cleanText(v.by, 60), ts = GuildOS.Finite(v.ts) }
            count = count + 1
        end
    end
    self:Store().needs = out
    SS:SetRevision("gbankneed", "needs", env.rev)
    self:Refresh()
end

-- Every need with what the bank holds: { id, n, have, note, by }, the shortest first.
function GuildBank:NeedRows()
    local rows = {}
    for id, v in pairs(self:Store().needs) do
        rows[#rows + 1] = { id = id, n = v.n, have = self:CountOf(id), note = v.note, by = v.by }
    end
    table.sort(rows, function(a, b)
        local pa, pb = a.have / a.n, b.have / b.n
        if pa ~= pb then return pa < pb end
        return a.id < b.id
    end)
    return rows
end

-- What is missing, one line per item: "12x [Flask of …]", for the chat or a shopping list.
function GuildBank:ShoppingList()
    local lines = {}
    for _, r in ipairs(self:NeedRows()) do
        if r.have < r.n then
            local name = self:LinkOf(r.id) or select(1, GuildOS.Compat.ItemDetails(r.id)) or ("item:" .. r.id)
            lines[#lines + 1] = string.format("%dx %s", r.n - r.have, name)
        end
    end
    return lines
end

----------------------------------------------------------------------
-- Requests (domain "gbankreq")
----------------------------------------------------------------------
local REQ_STATES = { open = true, done = true, declined = true, cancelled = true }

function GuildBank:Requests() return self:Store().requests end

local function newId()
    return string.format("%X%04X", now(), math.random(0, 0xFFFF))
end

-- Ask the officers for `n` of an item.
function GuildBank:Request(id, n, note)
    id, n = tonumber(id), tonumber(n)
    if not id or id <= 0 or id >= MAX_ITEM_ID or not n or n <= 0 then return false end
    local open = 0
    for _, x in pairs(self:Store().requests) do if x.st == "open" and self:IsMe(x.who) then open = open + 1 end end
    if open >= REQ_OPEN_PER then
        GuildOS:Print(string.format(L["You already have %d open requests."], open))
        return false
    end
    local r = { id = newId(), who = keyName(GuildOS.Compat.PlayerName()), item = id, n = math.min(math.floor(n), MAX_COUNT),
                note = cleanText(note, NOTE_MAX), ts = now(), at = now(), st = "open" }
    self:Store().requests[r.id] = r
    self:PruneRequests()
    if GuildOS.SyncService then GuildOS.SyncService:Publish("gbankreq", "new", r) end
    self:Refresh()
    return true
end

-- Close a request: an officer fills or declines it; its author cancels it.
function GuildBank:SetRequestState(rid, st)
    local r = self:Store().requests[rid]
    if not r or not REQ_STATES[st] then return false end
    local me = GuildOS.Compat.PlayerName()
    if st == "cancelled" and not self:IsMe(r.who) then return false end
    if (st == "done" or st == "declined") and not GuildOS:IsOfficer() then return false end
    r.st, r.by, r.at = st, me, now()
    if GuildOS.SyncService then GuildOS.SyncService:Publish("gbankreq", "set", { id = rid, st = st, at = r.at }) end
    self:Refresh()
    return true
end

local function cleanRequest(v, who)
    if type(v) ~= "table" then return nil end
    local id, item, n = cleanText(v.id, 20), tonumber(v.item), GuildOS.Finite(v.n)
    if not (id and item and item > 0 and item < MAX_ITEM_ID and n and n >= 1) then return nil end
    local st = REQ_STATES[v.st] and v.st or "open"
    return { id = id, who = who or cleanText(v.who, 60), item = item, n = math.min(math.floor(n), MAX_COUNT),
             note = cleanText(v.note, NOTE_MAX), ts = math.min(GuildOS.Finite(v.ts) or now(), now()),
             at = math.min(GuildOS.Finite(v.at) or now(), now()),
             st = st, by = cleanText(v.by, 60) }
end

function GuildBank:OnRequestSync(env, sender)
    local data = env.data
    if type(data) ~= "table" then return end
    local reqs = self:Store().requests
    if env.act == "new" then
        -- Only the author's own request: the key is the sender, never what the payload says.
        local r = cleanRequest(data, sender)
        local open = 0
        for _, x in pairs(reqs) do if x.st == "open" and sameName(x.who, sender) then open = open + 1 end end
        if r and not reqs[r.id] and open < REQ_OPEN_PER then
            r.st, r.by = "open", nil
            reqs[r.id] = r
            self:PruneRequests()
            self:Refresh()
            if GuildOS:IsOfficer() and self.onNewRequest then GuildOS:SafeCall(self.onNewRequest, r) end
        end
    elseif env.act == "set" then
        local r = reqs[cleanText(data.id, 20) or ""]
        local st = data.st
        if not (r and REQ_STATES[st]) then return end
        local ok = (st == "cancelled" and sameName(sender, r.who))
            or ((st == "done" or st == "declined") and GuildOS:IsOfficerByName(sender))
        if not ok then return end
        r.st, r.by, r.at = st, sender, math.min(GuildOS.Finite(data.at) or now(), now() + FUTURE_SLACK)
        self:Refresh()
    end
end

-- Requests a member who logged in missed, from an answer: kept where newer than ours. A request's
-- author and state come as the answering member saw them; a state only an officer may set is taken
-- only while the request names an officer who set it.
function GuildBank:MergeRequests(list)
    local reqs = self:Store().requests
    local changed = false
    for _, v in pairs(list) do
        local r = cleanRequest(v)
        if r and r.who then
            local mine = reqs[r.id]
            if (r.st == "done" or r.st == "declined") and not (r.by and GuildOS:IsOfficerByName(r.by)) then r.st = "open" end
            if not mine or (r.at or 0) > (mine.at or 0) then
                reqs[r.id] = r
                changed = true
            end
        end
    end
    if changed then self:PruneRequests() end
end

function GuildBank:PruneRequests()
    local reqs = self:Store().requests
    local cutoff = now() - REQ_KEEP_DAYS * 86400
    local list = {}
    for id, r in pairs(reqs) do
        if r.st ~= "open" and (r.at or 0) < cutoff then reqs[id] = nil else list[#list + 1] = r end
    end
    if #list > REQ_MAX then
        -- Closed ones go first, then the oldest.
        table.sort(list, function(a, b)
            if (a.st == "open") ~= (b.st == "open") then return a.st ~= "open" end
            return (a.at or 0) < (b.at or 0)
        end)
        for i = 1, #list - REQ_MAX do reqs[list[i].id] = nil end
    end
end

-- Requests, open first and newest first.
function GuildBank:RequestRows()
    local rows = {}
    for _, r in pairs(self:Store().requests) do rows[#rows + 1] = r end
    table.sort(rows, function(a, b)
        if (a.st == "open") ~= (b.st == "open") then return a.st == "open" end
        return (a.ts or 0) > (b.ts or 0)
    end)
    return rows
end

----------------------------------------------------------------------
-- Organizing (at the bank)
----------------------------------------------------------------------

-- Whether this player may organize `tab`: they see it, may deposit, and withdraw without limit (to
-- the game a move is a withdrawal), or lead the guild. Returns ok, reason.
function GuildBank:CanOrganize(tab)
    if not state().open then return false, L["Open the guild bank first."] end
    local _, _, viewable, canDeposit, _, remaining = GuildOS.Compat.GuildBankTabInfo(tab)
    if not viewable then return false, L["You cannot see this tab."] end
    if GuildOS.Compat.IsGuildLeader() then return true end
    if not canDeposit then return false, L["Your rank cannot deposit in this tab."] end
    if tonumber(remaining) ~= -1 then
        return false, L["Your rank's withdrawals here are limited, and the game counts each move as one."]
    end
    return true
end

-- The tabs this player may organize now.
function GuildBank:OrganizableTabs()
    local out = {}
    for tab = 1, math.min(GuildOS.Compat.GuildBankTabCount(), MAX_TABS) do
        if self:CanOrganize(tab) then out[#out + 1] = tab end
    end
    return out
end

function GuildBank:SortState() return state().sort end

-- Organize `tabs` (a list, or one tab), one move at a time.
function GuildBank:StartSort(tabs)
    local s = state()
    if s.sort then return false end
    if type(tabs) ~= "table" then tabs = { tabs } end
    local queue = {}
    for _, tab in ipairs(tabs) do
        local ok, why = self:CanOrganize(tab)
        if ok then queue[#queue + 1] = tab
        elseif #tabs == 1 then GuildOS:Print(why); return false end
    end
    if #queue == 0 then GuildOS:Print(L["No tab here you may organize."]); return false end
    -- Never with the cleanup taking stacks out: both move the bank.
    if GuildOS.GuildBankCleanup and GuildOS.GuildBankCleanup:IsWithdrawing() then return false end
    if GuildOS.Compat.InCombat() then GuildOS:Print(L["Not in combat."]); return false end
    -- Swaps first, unless the bank refused one this session or the player switched them off.
    -- Swaps first, every run: one refused (or a pickup that failed and looked like one) must not
    -- cost every later run its swaps.
    local swaps = GuildOS:GetSetting("gbankSwap") ~= false
    s.sort = { queue = queue, tab = nil, moves = 0, total = 0, merged = 0, before = 0, report = {}, swaps = swaps }
    self:Trace("organizing %d tab(s), swaps %s", #queue, swaps and "on" or "off")
    self:NextSortTab()
    return true
end

-- The next step of `run`, in `d` seconds. Each schedule supersedes the one before: a step left over
-- from a pause, a stop or a run before this one finds the run moved on and does nothing, so two
-- loops never issue moves together.
local function schedule(run, d)
    run.tick = (run.tick or 0) + 1
    local tick = run.tick
    GuildOS.Compat.After(d, function()
        if state().sort == run and run.tick == tick then GuildOS:SafeCall(GuildBank.SortStep, GuildBank) end
    end)
end

function GuildBank:NextSortTab()
    local s = state()
    local run = s.sort
    if not run then return end
    local tab = table.remove(run.queue, 1)
    if not tab then return self:StopSort("done") end
    run.tab, run.moves, run.merged, run.lockedSince, run.fails, run.holding = tab, 0, 0, nil, 0, nil
    run.pending, run.busy, run.cap, run.clean, run.model, run.rank, run.stack = {}, {}, CAP_START, 0, nil, {}, {}
    run.cooldown = run.cooldown or COOLDOWN_START   -- kept across the tabs of one run
    s.touched[tab] = true
    GuildOS.Compat.SetGuildBankCurrentTab(tab)
    GuildOS.Compat.QueryGuildBankTab(tab)
    -- Item names first, so the order does not change mid-run as they load.
    local slots = self:ReadTab(tab)
    for _, sl in pairs(slots) do self:RankOf(sl.id, sl.l) end
    run.used = 0
    for _ in pairs(slots) do run.used = run.used + 1 end
    run.started = GetTime()
    run.waitUntil = run.started + INFO_WAIT
    schedule(run, POLL)
end

local function allNamed(self, slots)
    for _, sl in pairs(slots) do
        if not state().rank[sl.l or tostring(sl.id)] then
            self:RankOf(sl.id, sl.l)
            return false
        end
    end
    return true
end

local function sameSlot(a, b)
    if a == nil or b == nil then return a == b end
    return a.k == b.k and a.c == b.c
end

local function copyPlain(p)
    local out = {}
    for i = 1, SLOTS do
        local x = p[i]
        if x then out[i] = { k = x.k, c = x.c } end
    end
    return out
end

-- A move did not land as planned (refused, throttled, or someone else moved something): plan from
-- the real tab again, one move at a time for a while. A refused swap switches the run, and the
-- session, to moving through free slots.
function GuildBank:Resync(run, p)
    local s = state()
    if p then self:Problem(p.swap and "swap did not land" or "move did not land", p, GetTime() - p.at) end
    if p and p.swap and p.inHand and run.swaps then
        run.swaps, s.noSwap = false, true   -- noSwap: what the last run found, for the tests and /gos bank debug
        self:Trace("the bank refused a swap: moving through free slots from now on")
    else
        run.fails = (run.fails or 0) + 1
        self:Trace("a move did not land (%d in a row); back to the real tab", run.fails)
        if run.fails >= DROP_FAILS then return self:StopSort("refused") end
    end
    run.cap, run.clean, run.pending, run.busy = 1, 0, {}, {}
    if GuildOS.Compat.CursorHasItem() then GuildOS.Compat.ClearCursor() end
    schedule(run, backoff(run.fails or 0))
end

-- One step of an organize run. Moves go out back to back, without waiting for the server's answer
-- to each: the run keeps a model of the tab as it will be, plans on it, and only ever touches slots
-- no move in flight is using. Each move is checked when its two slots show what the model expected
-- (never by an event: the game's word that slots changed comes for pickups too, and late). A move
-- whose slots do not show it within VERIFY_MAX sends the run back to the real tab.
--   1. pick the item up (or split part of it off);
--   2. drop it once the cursor holds it (a drop in the same frame as its pickup is lost);
--   3. the next move goes out at once, up to `cap` in flight: 2 at first, up to CAP_MAX while every
--      move lands, back to 1 after one that did not.
-- Swaps are tried first (one move per misplaced stack); a refused one moves the run through free
-- slots instead.
function GuildBank:SortStep()
    local s = state()
    local run = s.sort
    if not run then return end
    if run.paused then return end
    if not s.open then return self:StopSort("closed") end
    if GuildOS.Compat.InCombat() then return self:StopSort("combat") end
    local tab = run.tab
    local again = function(d) schedule(run, d) end
    local now_ = GetTime()

    -- 2. The drop.
    local held = run.holding
    if held then
        local waited = now_ - held.at
        local inHand = GuildOS.Compat.CursorHasItem()
        if not inHand and waited >= PICKUP_MAX then
            -- The pickup was never taken: nothing to drop. Note what it was, let go, try again.
            run.holding = nil
            self:Problem("pickup not taken", held, waited)
            if GuildOS.Compat.CursorHasItem() then GuildOS.Compat.ClearCursor() end
            run.fails = (run.fails or 0) + 1
            if run.fails >= DROP_FAILS then return self:StopSort("refused") end
            return again(backoff(run.fails))
        end
        if inHand and (held.sameFrame or waited >= HOLD_MIN) then
            run.holding = nil
            -- Whether the pickup was taken: a swap is judged refused only when the item was in hand.
            held.inHand = GuildOS.Compat.CursorHasItem()
            GuildOS.Compat.GuildBankPickup(tab, held.move.to)
            local of, ot = run.model[held.move.from], run.model[held.move.to]
            held.origFrom = of and { k = of.k, c = of.c } or nil
            held.origTo = ot and { k = ot.k, c = ot.c } or nil
            Plan.Apply(run.model, held.move, run.stack)
            local f, t = run.model[held.move.from], run.model[held.move.to]
            held.expectFrom = f and { k = f.k, c = f.c } or nil
            held.expectTo = t and { k = t.k, c = t.c } or nil
            held.at = now_
            run.pending[#run.pending + 1] = held
            run.busy[held.move.from], run.busy[held.move.to] = true, true
            held.held = waited
            self:Trace("drop %d -> %d%s (held %.2fs%s)", held.move.from, held.move.to,
                held.swap and " (swap)" or "", waited, held.sameFrame and ", same frame" or "")
        end
        return again(POLL)
    end

    -- The tab just asked for: its slots read empty until the server answers.
    if run.moves == 0 and s.lastSlotsAt < run.started and now_ - run.started < INFO_WAIT then
        return again(POLL)
    end
    local slots = self:ReadTab(tab)
    local plain, rank, stack = self:PlanInput(slots)
    for k, v in pairs(rank) do if not run.rank[k] then run.rank[k], run.stack[k] = v, stack[k] end end
    local lockedAt, anyLocked = {}, false
    for i, sl in pairs(slots) do if sl.locked then lockedAt[i], anyLocked = true, true end end

    -- 3. Moves in flight that landed.
    local i = 1
    while i <= #run.pending do
        local p = run.pending[i]
        local f, t = p.move.from, p.move.to
        local free = not lockedAt[f] and not lockedAt[t]
        if free and sameSlot(plain[f], p.expectFrom) and sameSlot(plain[t], p.expectTo) then
            table.remove(run.pending, i)
            run.busy[f], run.busy[t] = nil, nil
            run.fails = 0
            -- A swap that landed with nothing handed back on the cursor: this bank swaps outright,
            -- and swaps may fly together from now on.
            if p.swap and run.swapDirect == nil and not GuildOS.Compat.CursorHasItem() then run.swapDirect = true end
            run.clean = (run.clean or 0) + 1
            if run.clean >= CAP_RAMP and run.cap < CAP_MAX then run.cap, run.clean = run.cap + 1, 0 end
            if p.sameFrame and not p.redrops then s.sameFrame = true end
            if not p.redrops then
                local took = now_ - p.at
                run.rtt = (run.rtt or RTT_START) * 0.7 + took * 0.3
            end
            run.readyAt = now_ + (run.cooldown or COOLDOWN_START)
            if p.redrops then
                run.streak = 0
            else
                run.streak = (run.streak or 0) + 1
                if run.streak >= COOLDOWN_CLEAN then
                    run.streak = 0
                    run.cooldown = math.max(COOLDOWN_MIN, (run.cooldown or COOLDOWN_START) - COOLDOWN_DOWN)
                end
            end
            self:Trace("landed %d -> %d (%.2fs), next in %.2fs", f, t, now_ - p.at, run.cooldown or COOLDOWN_START)
        elseif not lockedAt[t] and now_ - p.at >= math.max(REDROP_MIN, REDROP_RTT * (run.rtt or RTT_START))
            and GuildOS.Compat.CursorHasItem() and sameSlot(plain[f], p.origFrom) and sameSlot(plain[t], p.origTo)
            and (p.redrops or 0) < REDROP_TRIES then
            -- Still in hand after its drop (a drop the game did not take): drop it again. A drop in the
            -- same frame as its pickup that was not taken: this client wants a moment between them.
            if p.sameFrame and s.sameFrame ~= false then
                s.sameFrame = false
                -- Kept for the next sessions: this client never takes such a drop (WoW: Forever).
                GuildOS:SetSetting("gbankSameFrame", false)
                self:Trace("drops in the pickup's frame are not taken here: waiting for the cursor from now on")
            end
            p.redrops = (p.redrops or 0) + 1
            self:Problem("still in hand after the drop", p, now_ - p.at)
            p.at = now_
            GuildOS.Compat.GuildBankPickup(tab, t)
            return again(POLL)
        elseif now_ - p.at >= LOCK_TIMEOUT then
            -- Locked (or unanswered) for too long: give the move up, whatever the slots say.
            return self:Resync(run, p)
        elseif free and now_ - p.at >= VERIFY_MAX then
            -- Still in hand: drop it again where it was going, before giving the move up.
            if GuildOS.Compat.CursorHasItem() and (p.redrops or 0) < REDROP_TRIES then
                p.redrops = (p.redrops or 0) + 1
                p.at = now_
                GuildOS.Compat.GuildBankPickup(tab, t)
                self:Trace("still in hand: drop on %d again (%d)", t, p.redrops)
                return again(POLL)
            end
            return self:Resync(run, p)
        else
            i = i + 1
        end
    end

    -- Something on the cursor we did not pick up: a swap handing the other item back. It goes to the
    -- slot ours came from; or, with nothing to explain it, it is let go.
    if GuildOS.Compat.CursorHasItem() then
        for _, p in ipairs(run.pending) do
            local f = p.move.from
            if p.swap and plain[f] == nil and not lockedAt[f] then
                GuildOS.Compat.GuildBankPickup(tab, f)
                run.cap, run.swapDirect = 1, false
                self:Trace("the swapped item goes to %d", f)
                return again(POLL)
            end
        end
        if #run.pending == 0 then
            local ctype, cid = GuildOS.Compat.CursorInfo()
            self:Keep(string.format("PROBLEM an item arrived in hand late (cursor %s %s): let go", tostring(ctype), tostring(cid)))
            self:Trace("an item arrived in hand late: let go")
            GuildOS.Compat.ClearCursor()
        end
        return again(POLL)
    end

    if #run.pending >= run.cap then return again(POLL) end
    if #run.pending == 0 then
        -- Nothing in flight: plan from the real tab, once nothing is locked and names are known.
        if anyLocked then
            run.lockedSince = run.lockedSince or now_
            if now_ - run.lockedSince > LOCK_TIMEOUT then return self:StopSort("stuck") end
            return again(POLL)
        end
        run.lockedSince = nil
        if not allNamed(self, slots) and now_ < (run.waitUntil or 0) then return again(POLL) end
        run.model = copyPlain(plain)
    end

    -- Slots a move in flight uses, or the game shows locked: the planner works around them.
    local avoid
    if #run.pending > 0 or anyLocked then
        avoid = {}
        for k in pairs(run.busy) do avoid[k] = true end
        for k in pairs(lockedAt) do avoid[k] = true end
    end
    local move, why = Plan.PlanMove(run.model, SLOTS, run.rank, run.stack, run.swaps, avoid)
    if run.moves == 0 and #run.pending == 0 then
        run.total = Plan.CountMoves(run.model, SLOTS, run.rank, run.stack, MAX_MOVES, run.swaps)
    end
    if not move then
        if #run.pending > 0 or why == "busy" then return again(POLL) end
        if why == "full" then
            run.report[#run.report + 1] = { tab = tab, moves = run.moves, freed = 0 }
            GuildOS:Print(string.format(L["Tab %d is full: free one slot and it can be put in order."], tab))
            return self:NextSortTab()
        end
        local free = 0
        for k = 1, SLOTS do if not plain[k] then free = free + 1 end end
        run.report[#run.report + 1] = { tab = tab, moves = run.moves, freed = math.max(0, free - (SLOTS - run.used)) }
        self:Refresh()
        return self:NextSortTab()
    end
    -- Until this bank has shown it swaps outright, a swap flies alone: one that hands the other item
    -- back on the cursor must find the cursor free.
    if run.swapDirect ~= true and #run.pending > 0 then
        local swapFlying = false
        for _, p in ipairs(run.pending) do if p.swap then swapFlying = true end end
        local isSwap = run.model[move.to] ~= nil and run.model[move.to].k ~= run.model[move.from].k
        if swapFlying or isSwap then return again(POLL) end
    end
    -- Never a slot a move in flight still uses, nor one the game shows locked.
    if run.busy[move.from] or run.busy[move.to] or lockedAt[move.from] or lockedAt[move.to] then
        return again(POLL)
    end
    local src, dst = run.model[move.from], run.model[move.to]
    -- The real slot must hold what the model says, or the pickup takes another item.
    if not sameSlot(plain[move.from], src) then
        if #run.pending > 0 then return again(POLL) end
        run.model = copyPlain(plain)
        return again(POLL)
    end
    if run.moves >= MAX_MOVES then return self:StopSort("stuck") end

    -- The server's breath after the last move.
    if now_ < (run.readyAt or 0) then return again(run.readyAt - now_) end

    -- 1. The pickup.
    if GuildOS.Compat.GuildBankCurrentTab() ~= tab then GuildOS.Compat.SetGuildBankCurrentTab(tab) end
    if move.op == "split" then
        GuildOS.Compat.GuildBankSplit(tab, move.from, move.count)
        run.merged = run.merged + 1
    else
        GuildOS.Compat.GuildBankPickup(tab, move.from)
    end
    local real = slots[move.from]
    run.holding = { move = move, at = now_, swap = dst ~= nil and dst.k ~= src.k,
                    item = real and { id = real.id, l = real.l, c = real.c },
                    other = slots[move.to] and { id = slots[move.to].id, l = slots[move.to].l, c = slots[move.to].c } }
    self:Trace("%s %d (x%s) for %d: %s", move.op, move.from, tostring(move.count or src.c), move.to,
        self:Describe(run.holding.item))
    -- The cursor already holds it: drop in the same frame, as BankStack does, unless this session saw
    -- such a drop not taken. Otherwise the next steps drop it once the cursor shows it.
    if s.sameFrame == nil then s.sameFrame = GuildOS:GetSetting("gbankSameFrame") end
    if s.sameFrame ~= false and GuildOS.Compat.CursorHasItem() then
        run.holding.sameFrame = true
        run.moves = run.moves + 1
        if run.moves > run.total then run.total = run.moves end
        run.current = move
        return self:SortStep()
    end
    run.moves = run.moves + 1
    if run.moves > run.total then run.total = run.moves end
    run.current = move
    self:Refresh()
    again(HOLD_MIN)
end

function GuildBank:PauseSort(paused)
    local run = state().sort
    if not run then return end
    run.paused = paused and true or nil
    if not paused then schedule(run, MOVE_DELAY) end
    self:Refresh()
end

local STOP_TEXT = {
    done = "Organized.",
    closed = "Stopped: the bank was closed.",
    combat = "Stopped: you entered combat.",
    cancel = "Stopped.",
    stuck = "Stopped: the bank did not answer the moves. Try again in a moment.",
    refused = "Stopped: the bank refused the moves. Your rank may not move items in this tab.",
}

-- What the organize run does, step by step, while /gos bank debug is on.
function GuildBank:Trace(fmt, ...)
    if not state().debug then return end
    local line = string.format(fmt, ...)
    GuildOS:Print("|cff888888[bank]|r " .. line)
    self:Keep(line)
end

-- Keep one line in the organize log (saved variables, so it can be read after the session).
function GuildBank:Keep(line)
    local db = self:Store()
    db.trace = db.trace or {}
    db.trace[#db.trace + 1] = (date and date("%H:%M:%S ") or "") .. line
    while #db.trace > TRACE_KEEP do table.remove(db.trace, 1) end
end

-- An item as the log names it: name, id, count, class and subclass, quality.
function GuildBank:Describe(it)
    if not it or not it.id then return "nothing" end
    local info = self:ItemInfo(it.id, it.l)
    return string.format("%s (id %d, x%d, class %s/%s, q%s)", info.name or "?", it.id, it.c or 0,
        tostring(info.classID), tostring(info.subClassID), tostring(info.quality))
end

-- A move that went wrong, always kept in the log (and shown while /gos bank debug is on): what it
-- moved, from where to where, what was there, how long it waited and what the cursor said.
function GuildBank:Problem(what, h, waited)
    local m = h.move
    local run = state().sort
    if run then
        run.cooldown = math.min(COOLDOWN_MAX, (run.cooldown or COOLDOWN_START) + COOLDOWN_UP)
        run.streak = 0
        run.readyAt = GetTime() + run.cooldown
    end
    local ctype, cid = GuildOS.Compat.CursorInfo()
    local line = string.format("PROBLEM %s: tab %s, %d -> %d%s, %s onto %s, waited %.2fs (held %.2fs%s), cursor %s %s, pause now %.2fs",
        what, tostring(run and run.tab), m.from, m.to, h.swap and " (swap)" or "",
        self:Describe(h.item), self:Describe(h.other), waited or 0, h.held or 0, h.sameFrame and ", same frame" or "",
        tostring(ctype), tostring(cid), run and run.cooldown or 0)
    if state().debug then GuildOS:Print("|cffff8800[bank]|r " .. line) end
    self:Keep(line)
end

function GuildBank:StopSort(reason)
    local s = state()
    local run = s.sort
    if not run then return end
    s.sort = nil
    if GuildOS.Compat.CursorHasItem() then GuildOS.Compat.ClearCursor() end
    for _, r in ipairs(run.report) do
        GuildOS:Print(string.format(L["Tab %d organized: %d moves, %d slots freed."], r.tab, r.moves, r.freed))
    end
    if reason ~= "done" then GuildOS:Print(L[STOP_TEXT[reason] or STOP_TEXT.cancel]) end
    s.lastSlotsAt = GetTime()
    GuildOS.Compat.After(READ_AFTER, function() GuildOS:SafeCall(GuildBank.ReadOpenTabs, GuildBank, true) end)
    self:Refresh()
end

----------------------------------------------------------------------
-- The item tooltip
----------------------------------------------------------------------
local function addTooltipLines(tt)
    if GuildOS:GetSetting("gbankTooltip") == false then return end
    if not GuildOS:ShowsItemTooltipInfo(tt) then return end
    local _, link = GuildOS.Compat.TooltipItem(tt)
    local id = parseLink(link)
    if not id then return end
    local self = GuildBank
    local have = self:CountOf(id)
    local need = self:NeedOf(id)
    if have == 0 and not need then return end
    local C = GuildOS.Colors
    tt:AddDoubleLine(L["Guild bank"], tostring(have), C.gold.r, C.gold.g, C.gold.b, C.text.r, C.text.g, C.text.b)
    local e
    for _, x in ipairs(self:Index().list) do if x.id == id then e = x; break end end
    if e then
        local parts = {}
        local tabs = {}
        for tab in pairs(e.tabs) do tabs[#tabs + 1] = tab end
        table.sort(tabs)
        for _, tab in ipairs(tabs) do parts[#parts + 1] = string.format(L["Tab %d: %d"], tab, e.tabs[tab]) end
        local ts = self:Newest()
        tt:AddLine(table.concat(parts, " · ") .. " · " .. GuildOS:TimeAgo(ts), C.textSoft.r, C.textSoft.g, C.textSoft.b)
    end
    if need then
        local col = have >= need and C.ok or C.warn
        tt:AddDoubleLine(L["Bank need"], have >= need and string.format(L["%d of %d, met"], have, need)
            or string.format(L["%d short of %d"], need - have, need), C.textSoft.r, C.textSoft.g, C.textSoft.b, col.r, col.g, col.b)
    end
    tt:Show()
end

function GuildBank:HookTooltips()
    if self.tooltipHooked then return end
    self.tooltipHooked = true
    local function hook(tt) GuildOS:SafeCall(addTooltipLines, tt) end
    GuildOS.Compat.HookTooltip(GameTooltip, "OnTooltipSetItem", hook)
    GuildOS.Compat.HookTooltip(ItemRefTooltip, "OnTooltipSetItem", hook)
end

-- The item id a typed or pasted text names: an item link, an id, or the name of an item the bank
-- holds (whole name first, then the first that starts with it). nil when it names none.
function GuildBank:ParseItemInput(text)
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    if text == "" then return nil end
    local id = parseLink(text) or tonumber(text:match("^%d+$") and text)
    if id then return id end
    local want = text:lower()
    local prefix
    for _, e in ipairs(self:Index().list) do
        local name = GuildOS.Compat.ItemDetails(e.l or e.id)
        if name then
            name = name:lower()
            if name == want then return e.id end
            if not prefix and name:sub(1, #want) == want then prefix = e.id end
        end
    end
    return prefix
end

-- The class of a name from the ledger, by the roster the addon keeps, or nil.
function GuildBank:ClassOf(name)
    if type(name) ~= "string" then return nil end
    local key = keyName(name)
    local m = key and GuildOS.db.members and GuildOS.db.members[key]
    return m and m.class
end

----------------------------------------------------------------------
-- UI hooks and commands
----------------------------------------------------------------------
function GuildBank:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
    if self.barRefresh then GuildOS:SafeCall(self.barRefresh) end
end

-- /gos bank [sort [all] | stop | sync | need]
function GuildBank:HandleCommand(args)
    local verb = args[1]
    if verb == "sort" then
        if args[2] == "all" then self:StartSort(self:OrganizableTabs())
        else self:StartSort(GuildOS.Compat.GuildBankCurrentTab() or 1) end
    elseif verb == "debug" then
        local s = state()
        s.debug = not s.debug
        GuildOS:Print(s.debug and L["Bank debug on: each move of an organize run is printed."] or L["Bank debug off."])
    elseif verb == "log" then
        local db = self:Store()
        if args[2] == "clear" then
            db.trace = {}
            GuildOS:Print(L["Bank log cleared."])
            return
        end
        local lines = db.trace or {}
        local n = math.min(#lines, tonumber(args[2]) or 30)
        GuildOS:Print(string.format(L["Last %d lines of the bank log (all of it is in WTF\\...\\SavedVariables\\GuildOS.lua):"], n))
        for i = #lines - n + 1, #lines do GuildOS:Print(lines[i]) end
    elseif verb == "stop" then
        self:StopSort("cancel")
    elseif verb == "sync" then
        self:Ask()
        GuildOS:Print(L["Asked the guild for the bank."])
    elseif verb == "need" then
        for _, line in ipairs(self:ShoppingList()) do GuildOS:Print(line) end
    elseif GuildOS.UI and GuildOS.UI.OpenWindow then
        GuildOS.UI:OpenWindow("bank")
    end
end
