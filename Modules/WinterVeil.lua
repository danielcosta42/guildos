----------------------------------------------------------------------
-- Guild OS - Winter Veil's Secret Santa (issue #437; the site's specs/119, guildos-web#659)
--
-- The site holds the event, the draw and every pair; this module shows them and tells the site what happened in
-- the game. What it knows comes from two blocks the companion writes:
--   GOSGILD1.veil   the guild's event: rules, counts, the officers' table, the chain after the reveal
--   GOSVEIL1        this person's own: whom they drew and that one's list, their list, and the pairs they carry,
--                   sealed, for guildmates without the companion
-- What it tells the site goes in the export (GOSCOMP1.veil): entries, lists, deliveries, auction prices and the
-- bank's needs. A member without the companion reaches the site through an officer's export: every addon keeps
-- what each guildmate announced *of themselves* on the guild channel — the game says who sent a message, so a
-- player can only ever speak for their own characters.
--
-- Nothing here decides: the cap, the kind of gift and the pairs are the site's. A list that breaks the guild's
-- rules is refused by the site whole; the screen checks the same rules first so nobody is surprised.
----------------------------------------------------------------------
local WV = {}
GuildOS.WinterVeil = WV

local DOMAIN = "veil"
local DAY = 86400
WV.MAX_WISHES = 8
WV.MAX_QTY = 20
WV.PRICE_DAYS = 14
WV.PRICES_MAX = 500
WV.RELAY_EVERY = 3600
-- The site's caps on one export's part (lib/veil-wire.ts): past them it refuses the part whole.
WV.EXPORT_JOINS = 100
WV.EXPORT_LISTS = 200
WV.EXPORT_DELIVERIES = 200       -- a carrier whispers a pair again at most once an hour until its owner says they have it

local function now() return GetServerTime() end
local function Import() return GuildOS.CompanionImport end

----------------------------------------------------------------------
-- What this client keeps (per guild): its own entry and list, what guildmates announced of themselves, prices,
-- deliveries, and the pairs a carrier handed it.
----------------------------------------------------------------------
local function store()
    local db = GuildOS.db
    if not db then return nil end
    db.winterVeil = db.winterVeil or {}
    local s = db.winterVeil
    local event = WV:Event()
    -- A new year starts clean: last year's lists and pairs mean nothing to this one.
    if event and s.year ~= event.year then
        db.winterVeil = { year = event.year }
        s = db.winterVeil
    end
    s.people = s.people or {}        -- [key] = { join = { volunteer, at }, wishes = {...}, wishesAt }
    s.deliveries = s.deliveries or {} -- [giver .. ">" .. to] = { giver, to, via, recipe?, qty?, copper?, at }
    s.prices = s.prices or {}         -- [recipe] = { c, at }
    s.opened = s.opened or {}         -- [giverKey] = { to, wishes, delivered }: pairs a carrier whispered to me
    s.carried = s.carried or {}       -- [giverKey] = { at, got }: pairs I carry, when I last whispered them
    return s
end
WV._store = store

function WV:Event()
    local I = Import()
    return I and I.WinterVeil and I:WinterVeil() or nil
end

function WV:Personal()
    local I = Import()
    return I and I.VeilBlock and I:VeilBlock() or nil
end

-- The full name on WoW: Forever too (a first name and a surname): UnitName gives only the first.
function WV:MyKey() return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) end

-- "joining" | "closed" | "drawn" | "revealed", by the event's own clock.
function WV.PhaseOf(e, t)
    if not e then return nil end
    t = t or now()
    if t >= e.revealAt then return "revealed" end
    if e.drawn then return "drawn" end
    return t < e.joinUntil and "joining" or "closed"
end

----------------------------------------------------------------------
-- Prices (§6): the auction house's, of one of what a recipe makes, through Compat.AuctionPrice (Auctionator, TSM).
-- A scan anybody makes is shared: whoever has no auction addon uses a guildmate's.
----------------------------------------------------------------------
function WV.ProductOf(recipe)
    local cat = GuildOS.ProfCatalog
    local r = cat and cat.recipes and cat.recipes[recipe]
    local out = r and r[cat.F.out]
    local count = r and cat.F.outCount and r[cat.F.outCount] or 1
    return out, (tonumber(count) or 1)
end

function WV:PriceOf(recipe, t)
    local s = store()
    local p = s and s.prices[recipe]
    t = t or now()
    if not p or t - p.at > WV.PRICE_DAYS * DAY then return nil end
    return p.c
end

-- Reads the price of each recipe asked from this client's auction addon, keeps the newer, and tells the guild.
function WV:ScanPrices(recipes)
    local s = store()
    if not s or not (GuildOS.Compat and GuildOS.Compat.AuctionPrice) then return 0 end
    local fresh, t = {}, now()
    for _, recipe in ipairs(recipes) do
        local item, count = WV.ProductOf(recipe)
        local c = item and GuildOS.Compat.AuctionPrice(item)
        if c and c > 0 then
            -- The price of what one craft makes: a recipe that makes five charges five auctions' worth.
            c = math.floor(c * count + 0.5)
            s.prices[recipe] = { c = c, at = t }
            fresh[#fresh + 1] = { r = recipe, c = c, at = t }
        end
    end
    if #fresh > 0 and GuildOS.SyncService then
        GuildOS.SyncService:Publish(DOMAIN, "prices", { p = fresh }, { priority = "BULK" })
    end
    return #fresh
end

----------------------------------------------------------------------
-- A wish list (§4): the same rules the site holds, checked here first.
----------------------------------------------------------------------
function WV.WishWorth(w, priceOf)
    if w.k == "gold" then return w.copper end
    local c = priceOf(w.recipe)
    return c and c * w.qty or nil
end

-- nil when the list passes, else the reason the site would give ("kind", "price", "cap", "shape").
function WV.ListRefusal(list, e, priceOf)
    if type(list) ~= "table" or #list > WV.MAX_WISHES then return "shape" end
    local golds, seen = 0, {}
    for _, w in ipairs(list) do
        if w.k == "gold" then
            golds = golds + 1
        elseif w.k == "item" then
            if seen[w.recipe] or (w.qty or 0) < 1 or w.qty > WV.MAX_QTY then return "shape" end
            seen[w.recipe] = true
        else
            return "shape"
        end
    end
    if golds > 1 then return "shape" end
    if e.kind == "item" and golds > 0 then return "kind" end
    if e.kind == "gold" and golds ~= #list then return "kind" end
    for _, w in ipairs(list) do
        local c = WV.WishWorth(w, priceOf)
        if not c then return "price" end
        if c > e.cap then return "cap" end
    end
    return nil
end

-- This player's list as this client holds it: its own edit, else what the site last sent.
function WV:MyList()
    local s, me = store(), self:MyKey()
    local mine = s and me and s.people[me]
    if mine and mine.wishes then return mine.wishes, mine.wishesAt end
    local p = self:Personal()
    for _, m in ipairs(p and p.mine or {}) do
        if m.key == me then return m.wishes, m.wishesAt end
    end
    return {}, nil
end

function WV:SetList(list)
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s and me) then return false, "event" end
    if now() >= e.revealAt then return false, "over" end
    local why = WV.ListRefusal(list, e, function(r) return self:PriceOf(r) end)
    if why then return false, why end
    s.people[me] = s.people[me] or {}
    s.people[me].wishes, s.people[me].wishesAt = list, now()
    if GuildOS.SyncService then GuildOS.SyncService:Publish(DOMAIN, "list", { k = me, w = list, at = s.people[me].wishesAt }) end
    return true
end

function WV:Join(volunteer)
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s and me) or WV.PhaseOf(e) ~= "joining" then return false end
    s.people[me] = s.people[me] or {}
    s.people[me].join = { volunteer = volunteer == true, at = now() }
    if GuildOS.SyncService then GuildOS.SyncService:Publish(DOMAIN, "join", { k = me, v = volunteer == true, at = s.people[me].join.at }) end
    return true
end

----------------------------------------------------------------------
-- Whom I give to (§5): from my own block, or opened from a pair a carrier whispered.
----------------------------------------------------------------------
function WV:MyEntry()
    local p, me = self:Personal(), self:MyKey()
    for _, m in ipairs(p and p.mine or {}) do
        if m.key == me or #p.mine == 1 then return m end
    end
    return nil
end

function WV:MyGives()
    local m = self:MyEntry()
    if m and #m.gives > 0 then return m.gives end
    local s, me = store(), self:MyKey()
    local opened = s and me and s.opened[me]
    return opened and { opened } or {}
end

----------------------------------------------------------------------
-- The relay (§12): obfuscation, not secrecy. The same as the site's lib/veil-rules.ts, byte for byte; the harness
-- (tools/winter-veil.lua) holds the site's vector.
----------------------------------------------------------------------
local bit = _G.bit
local TWO32 = 4294967296
local function u32(x) return x % TWO32 end

function WV.Fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i)) % TWO32
        -- h * 16777619 = h * 2^24 + h * 403, each part kept under 2^53.
        h = u32(u32(bit.lshift(h, 24)) + h * 403)
    end
    return h
end

local function keystream(key, n)
    local x = WV.Fnv1a(key)
    if x == 0 then x = 0x9e3779b9 end
    local out = {}
    for i = 1, n do
        x = u32(bit.bxor(x, u32(bit.lshift(x, 13))))
        x = u32(bit.bxor(x, bit.rshift(x, 17)))
        x = u32(bit.bxor(x, u32(bit.lshift(x, 5))))
        out[i] = x % 256
    end
    return out
end

function WV.Seal(text, key)
    local ks, out = keystream(key, #text), {}
    for i = 1, #text do out[i] = string.format("%02x", bit.bxor(text:byte(i), ks[i])) end
    return table.concat(out)
end

function WV.Unseal(hex, key)
    if type(hex) ~= "string" or #hex % 2 ~= 0 or not hex:match("^%x*$") then return nil end
    local n = #hex / 2
    local ks, out = keystream(key, n), {}
    for i = 1, n do out[i] = string.char(bit.bxor(tonumber(hex:sub(2 * i - 1, 2 * i), 16), ks[i])) end
    return table.concat(out)
end

-- The site's key for a seal: "<salt>:<giver as the site spells them>". The site spells a WoW: Forever player
-- without a realm, so the realm this client added goes back off there.
function WV.SealKey(salt, giverKey)
    local spelled = giverKey
    if not GuildOS:RealmBound() then spelled = giverKey:match("^([^-]+)") or giverKey end
    return salt .. ":" .. spelled
end

-- Opens a pair a carrier whispered me; true when it was mine and read whole.
function WV:OpenPair(sealHex)
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and e.salt and s and me) then return false end
    local text = WV.Unseal(sealHex, WV.SealKey(e.salt, me))
    local ok, data = pcall(GuildOS.JsonDecode, text or "")
    if not ok or type(data) ~= "table" then return false end
    local to = Import().VeilKey(data.to)
    if not to then return false end
    s.opened[me] = { to = to, wishes = Import().VeilWishes(data.wishes), delivered = data.delivered == true }
    return true
end

-- Whispers each pair I carry to its owner while they are online, once an hour at most, until they say they have it.
function WV:Relay()
    local p, s = self:Personal(), store()
    if not (p and s and GuildOS.SyncService) then return 0 end
    local online = {}
    for i = 1, GetNumGuildMembers() do
        local full, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if full and isOnline then online[GuildOS:KeyOfRosterName(full)] = full end
    end
    local sent, t = 0, now()
    for _, r in ipairs(p.relay) do
        local c = s.carried[r.giver]
        local who = online[r.giver]
        if who and not (c and (c.got or t - c.at < WV.RELAY_EVERY)) then
            -- A WoW: Forever name has a space the whisper may need as a hyphen: ChehulGossip knows which reaches.
            local target = GuildOS.ChehulGossip and GuildOS.ChehulGossip.WhisperName and GuildOS.ChehulGossip:WhisperName(who) or who
            GuildOS.SyncService:Publish(DOMAIN, "pair", { g = r.giver, s = r.seal }, { target = target })
            s.carried[r.giver] = { at = t }
            sent = sent + 1
        end
    end
    return sent
end

----------------------------------------------------------------------
-- Deliveries (§7): a mail or a trade to whom I drew is recorded on its own.
----------------------------------------------------------------------
function WV:RecordDelivery(toKey, via, copper, recipe, qty)
    local s, me = store(), self:MyKey()
    if not (s and me and toKey) then return false end
    local mine = false
    for _, g in ipairs(self:MyGives()) do if g.to == toKey then mine = true end end
    if not mine then return false end
    local id = me .. ">" .. toKey
    if s.deliveries[id] then return false end
    local d = { giver = me, to = toKey, via = via, copper = copper and copper > 0 and copper or nil, recipe = recipe, qty = qty, at = now() }
    s.deliveries[id] = d
    if GuildOS.SyncService then GuildOS.SyncService:Publish(DOMAIN, "gave", d) end
    GuildOS:Print(GuildOS.L["Winter Veil: your gift was recorded."])
    return true
end

----------------------------------------------------------------------
-- The guild channel: each player announces their own entry, list and delivery; the game says who sent it, so a
-- line about anybody else is dropped. Prices are anybody's. A pair is whispered to its owner alone.
----------------------------------------------------------------------
local function wholeAt(v)
    local n = GuildOS.Finite(v)
    if not n or n ~= math.floor(n) or n < 1 or n > now() + 300 then return nil end
    return n
end

function WV:OnEnvelope(env, sender)
    local s = store()
    if not s or type(env) ~= "table" or type(env.data) ~= "table" then return end
    local d, act = env.data, env.act
    local from = sender and GuildOS:KeyOfRosterName(sender)
    if act == "prices" then
        for i = 1, math.min(type(d.p) == "table" and #d.p or 0, 100) do
            local x = d.p[i]
            local r, c, at = type(x) == "table" and tonumber(x.r), type(x) == "table" and GuildOS.Finite(x.c), type(x) == "table" and wholeAt(x.at)
            if r and r == math.floor(r) and r > 0 and c and c == math.floor(c) and c > 0 and c <= 1e11 and at then
                local held = s.prices[r]
                if not held or held.at < at then s.prices[r] = { c = c, at = at } end
            end
        end
        return
    end
    if act == "pair" then
        -- Only for me, only about me, and only from the carrier the site named for me: every member holds the salt,
        -- so anybody could seal a pair under my key.
        local me = self:MyKey()
        local e = self:Event()
        local carrier = e and e.carriers and e.carriers[me]
        if d.g == me and carrier and from == carrier and type(d.s) == "string" and self:OpenPair(d.s) and GuildOS.SyncService then
            GuildOS.SyncService:Publish(DOMAIN, "got", { g = d.g }, { target = sender })
        end
        return
    end
    if act == "got" then
        if d.g == from and s.carried[from] then s.carried[from].got = true end
        return
    end
    -- What a player says of themselves.
    if not from then return end
    if act == "join" and d.k == from then
        local at = wholeAt(d.at)
        if at then
            s.people[from] = s.people[from] or {}
            s.people[from].join = { volunteer = d.v == true, at = at }
        end
    elseif act == "list" and d.k == from then
        local at = wholeAt(d.at)
        local held = s.people[from]
        if at and not (held and held.wishesAt and held.wishesAt >= at) then
            s.people[from] = held or {}
            s.people[from].wishes, s.people[from].wishesAt = Import().VeilWishes(d.w), at
        end
    elseif act == "gave" and d.giver == from then
        local to, at = Import().VeilKey(d.to), wholeAt(d.at)
        if to and at and (d.via == "mail" or d.via == "trade") and not s.deliveries[from .. ">" .. to] then
            local cop = GuildOS.Finite(d.copper)
            s.deliveries[from .. ">" .. to] = { giver = from, to = to, via = d.via, at = at,
                copper = cop and cop == math.floor(cop) and cop > 0 and cop or nil,
                recipe = tonumber(d.recipe), qty = tonumber(d.qty) }
        end
    end
end

----------------------------------------------------------------------
-- The export (GOSCOMP1.veil, the site's specs/119): everything this client holds; the site believes all of it only
-- from an officer's code, and from anybody else only their own lines.
----------------------------------------------------------------------
function WV:ForExport()
    local e, s = self:Event(), store()
    if not (e and s) then return nil end
    local out = { year = e.year, joins = {}, wishes = {}, deliveries = {}, prices = {} }
    local hasPrice = false
    for key, p in pairs(s.people) do
        if p.join then out.joins[#out.joins + 1] = { key = key, volunteer = p.join.volunteer, at = p.join.at } end
        if p.wishes and p.wishesAt then out.wishes[#out.wishes + 1] = { key = key, list = p.wishes, at = p.wishesAt } end
    end
    for _, d in pairs(s.deliveries) do out.deliveries[#out.deliveries + 1] = d end
    local n = 0
    for r, p in pairs(s.prices) do
        if n < WV.PRICES_MAX and now() - p.at <= WV.PRICE_DAYS * DAY then
            out.prices[tostring(r)] = { c = p.c, at = p.at }
            n = n + 1
            hasPrice = true
        end
    end
    -- The export's encoder writes an empty table as a list, and the site reads `prices` as a map: none is no field.
    if not hasPrice then out.prices = nil end
    -- Within the site's caps (the part is refused whole past them): the newest first, in a guild of hundreds.
    local function newest(list, max, at)
        table.sort(list, function(a, b) return at(a) > at(b) end)
        while #list > max do list[#list] = nil end
    end
    newest(out.joins, WV.EXPORT_JOINS, function(x) return x.at end)
    newest(out.wishes, WV.EXPORT_LISTS, function(x) return x.at end)
    newest(out.deliveries, WV.EXPORT_DELIVERIES, function(x) return x.at end)
    -- The bank's needs, for the Chimney: an officer's client only.
    local B = GuildOS.GuildBank
    if GuildOS:IsOfficer() and B and B.Needs then
        local needs = {}
        for id, need in pairs(B:Needs() or {}) do
            if #needs < 40 and type(need) == "table" and tonumber(need.n) and need.n > 0 then
                local info = B.ItemInfo and B:ItemInfo(id) or nil
                local name = type(info) == "table" and info.name or nil
                needs[#needs + 1] = { id = id, name = type(name) == "string" and name ~= "" and name or ("#" .. id),
                                      have = B:CountOf(id) or 0, want = math.floor(need.n) }
            end
        end
        table.sort(needs, function(a, b) return a.id < b.id end)
        out.needs, out.needsAt = needs, now()
    end
    return out
end

----------------------------------------------------------------------
-- Life
----------------------------------------------------------------------
function WV:Initialize()
    if GuildOS.SyncService then
        GuildOS.SyncService:On(DOMAIN, function(env, sender) WV:OnEnvelope(env, sender) end)
    end
    local f = CreateFrame("Frame")
    local trade = {}
    GuildOS.Compat.RegisterEvent(f, "TRADE_SHOW", true)
    GuildOS.Compat.RegisterEvent(f, "TRADE_MONEY_CHANGED", true)
    GuildOS.Compat.RegisterEvent(f, "UI_INFO_MESSAGE", true)
    GuildOS.Compat.RegisterEvent(f, "MAIL_SEND_SUCCESS", true)
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE", true)
    local pendingMail
    GuildOS.Compat.HookSendMail(function(to)
        pendingMail = { to = to and GuildOS:KeyOfRosterName(to), copper = GetSendMailMoney and GetSendMailMoney() or 0 }
    end)
    local lastRelay = 0
    f:SetScript("OnEvent", function(_, event, a, b)
        if not WV:Event() then return end
        if event == "TRADE_SHOW" then
            local name, realm = GuildOS.Compat.TradePartner()
            trade = { to = name and GuildOS:GetPlayerKey(name, realm) }
        elseif event == "TRADE_MONEY_CHANGED" then
            trade.copper = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
        elseif event == "UI_INFO_MESSAGE" and GuildOS.Compat.IsTradeComplete(a, b) then
            if trade.to then GuildOS:SafeCall(function() WV:RecordDelivery(trade.to, "trade", trade.copper) end) end
            trade = {}
        elseif event == "MAIL_SEND_SUCCESS" and pendingMail then
            local m = pendingMail
            pendingMail = nil
            GuildOS:SafeCall(function() WV:RecordDelivery(m.to, "mail", m.copper) end)
        elseif event == "GUILD_ROSTER_UPDATE" and GetTime() - lastRelay > 60 then
            lastRelay = GetTime()
            GuildOS:SafeCall(function() WV:Relay() end)
        end
    end)
end
