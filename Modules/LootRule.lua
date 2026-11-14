----------------------------------------------------------------------
-- Guild OS - Loot Rule (issue #333)
--
-- Who gets an item, as data instead of code. A rule holds the six blocks of the loot model: who may
-- ask (`filters`), how they ask (`responses`), the order between candidates (`order`), who decides,
-- what an award changes and the items that follow another rule. This module reads `filters`, `order`
-- and, since issue #334, `responses` (the buttons a raider answers with: a roll, a bid or neither, what
-- each one costs and whether it counts for the +1), the bids' own rules, the counter accounts and the
-- effects an award has on them; the other blocks keep the behaviour of the module that owns them until
-- their own issue.
--
-- `order` is a list of criteria. Two candidates are compared by the first; a tie goes to the next.
-- Every loot system the guild could pick before this (rolls, tmb, wishlist, dkp) is a ready-made rule
-- (`FromLegacy`), built from the system and the loot settings the guild already had, so a guild that
-- updates chooses nothing and sees no change. A custom rule, once an officer saves one, replaces it.
--
-- A candidate is the row LootMaster keeps per roller: { name, rollType, roll, bid, prioOrder, softRes,
-- wishlist, recvCount, att25, dkp, pr, accts }. TradeCouncil's rows are mapped onto the same fields
-- (`FromAnswer`).
-- Pure: no UI, no chat, no events.
----------------------------------------------------------------------

local LootRule = {}
GuildOS.LootRule = LootRule
local L = GuildOS.L

LootRule.VERSION = 1
LootRule.MAX_CRITERIA = 10
LootRule.MAX_FILTERS = 10
LootRule.MAX_RESPONSES = 10
LootRule.MAX_ACCOUNTS = 6
LootRule.MAX_EFFECTS = 10
LootRule.TIME_MIN, LootRule.TIME_MAX = 5, 300   -- seconds a roll may stay open
LootRule.MAX_BID = 1000000
LootRule.WIRE_MAX = 240       -- bytes of an encoded "how to ask" an addon message has room for

local UNRANKED = 999          -- no place on a list: after everyone who has one
local PASS_RANK = 9999        -- a pass is after every answer
local FUTURE_SLACK = 300      -- seconds a peer's clock may run ahead of this one

local KEY_MAX = 8             -- characters of a response's or an account's key
local LABEL_MAX = 24          -- bytes of a button's label
local COST_MAX = 10           -- a response never multiplies a price by more
local ASKS = { roll = true, bid = true, none = true }
local RESETS = { never = true, night = true, lockout = true }
local PRICES = { table = true, fixed = true, bid = true, second = true }
local RESERVED_ACCOUNTS = { dkp = true, ep = true, gp = true }   -- the points' own (Points.lua)

-- The answers when the rule names none: main spec, then off spec, each by a roll, at the item's price,
-- and only main spec counting for the +1. What every guild had before issue #334.
local function defaultResponses()
    return {
        { key = "MS", label = "MS", ask = "roll", plus = true, cost = 1 },
        { key = "OS", label = "OS", ask = "roll", plus = false, cost = 1 },
    }
end
local DEFAULT_RESPONSES = defaultResponses()

----------------------------------------------------------------------
-- The criteria. `raw` reads a number off a candidate; `high` says the larger one comes first. `band`
-- on a rule's entry groups raw values into steps of that size before comparing, so "90% and up" tie
-- and the next criterion decides.
----------------------------------------------------------------------
local function responseRank(c, rule)
    if c.rollType == "PASS" then return PASS_RANK end
    for i, r in ipairs(rule.responses or DEFAULT_RESPONSES) do
        if r.key == c.rollType then return i end
    end
    return UNRANKED
end

-- A counter account's figure on a candidate (the +1, issue #334): LootMaster reads it off the Points
-- when the answer comes in.
local function accountOf(c, _, entry)
    return (c.accts and c.accts[entry.acct]) or 0
end

LootRule.CRITERIA = {
    response   = { raw = responseRank },
    hardres    = { raw = function(c) return (c.softRes and c.softRes.hard) and 1 or 2 end },
    softres    = { raw = function(c) return c.softRes and 1 or 2 end },
    prio       = { raw = function(c) return c.prioOrder or UNRANKED end },
    wishlist   = { raw = function(c) return (c.wishlist and c.wishlist.order) or UNRANKED end },
    received   = { raw = function(c) return c.recvCount or 0 end },
    attendance = { raw = function(c) return c.att25 or 0 end, high = true },
    points     = { raw = function(c) return c.dkp or 0 end, high = true },
    pr         = { raw = function(c) return c.pr or 0 end, high = true },
    roll       = { raw = function(c) return c.roll or -1 end, high = true },
    bid        = { raw = function(c) return c.bid or 0 end, high = true },
    account    = { raw = accountOf, high = true },   -- `dir = "low"` on the entry turns it round
}

-- The order criteria are offered in, and their names. Names are looked up when shown, never at load.
LootRule.CRITERIA_ORDER = {
    "response", "hardres", "softres", "prio", "wishlist", "received", "attendance", "points", "pr", "roll",
}
local LABELS = {
    response   = "the answer",
    hardres    = "hard reserve",
    softres    = "soft reserve",
    prio       = "officer priority",
    wishlist   = "wishlist place",
    received   = "fewer items received",
    attendance = "attendance",
    points     = "points",
    pr         = "EP/GP priority",
    roll       = "the roll",
    bid        = "the bid",
    account    = "the counter",
}
function LootRule:Label(key)
    local label = LABELS[key]
    return label and L[label] or tostring(key)
end

-- What an entry of `order` says about a candidate, as a number where the smaller comes first.
local function rankOf(entry, c, rule)
    local crit = LootRule.CRITERIA[entry.k]
    local v = crit.raw(c, rule, entry)
    local band = entry.band
    if band and band > 0 then v = math.floor(v / band) end
    local high = crit.high
    if entry.dir then high = entry.dir ~= "low" end
    return high and -v or v
end

----------------------------------------------------------------------
-- Validation: a rule from another client or from the site is read only when every field is one this
-- client knows. A rule it cannot read whole is not applied in part.
----------------------------------------------------------------------
-- A whole number of at least `min` and at most `max`.
local function wholeIn(n, min, max)
    return type(n) == "number" and n == math.floor(n) and n >= min and n <= max
end

-- A key: 1 to 8 characters of `class` ("A-Z0-9" for a response, "a-z0-9" for an account).
local function isKey(key, class)
    return type(key) == "string" and #key >= 1 and #key <= KEY_MAX and not key:find("[^" .. class .. "]")
end

-- A name a button or a column shows: short, and with nothing a chat line or an addon message reads as
-- its own (a colour code's pipe, the separator of the announce message, a control character).
local function isLabel(text)
    return type(text) == "string" and #text >= 1 and #text <= LABEL_MAX and not text:find("[|;%c]")
end

local function flagOrNil(v) return v == nil or type(v) == "boolean" end

-- How to ask (issue #334): up to ten answers, each a button.
local function validResponses(list)
    if type(list) ~= "table" or #list == 0 or #list > LootRule.MAX_RESPONSES then return false end
    local seen = {}
    for _, r in ipairs(list) do
        if type(r) ~= "table" or not isKey(r.key, "A-Z0-9") or r.key == "PASS" or seen[r.key] then return false end
        seen[r.key] = true
        if r.label ~= nil and not isLabel(r.label) then return false end
        if r.ask ~= nil and not ASKS[r.ask] then return false end
        if not (flagOrNil(r.plus) and flagOrNil(r.note)) then return false end
        if r.cost ~= nil and not (type(r.cost) == "number" and r.cost >= 0 and r.cost <= COST_MAX) then
            return false
        end
    end
    return true
end

-- The counter accounts a rule keeps (the +1). The other kinds of account wait for their own issue, and
-- the points' own keys are never a counter's.
local function validAccounts(list)
    if type(list) ~= "table" or #list > LootRule.MAX_ACCOUNTS then return nil end
    local known = {}
    for _, a in ipairs(list) do
        if type(a) ~= "table" or not isKey(a.key, "a-z0-9") or RESERVED_ACCOUNTS[a.key] or known[a.key] then
            return nil
        end
        if a.type ~= "counter" then return nil end
        if a.name ~= nil and not isLabel(a.name) then return nil end
        if a.reset ~= nil and not RESETS[a.reset] then return nil end
        known[a.key] = true
    end
    return known
end

-- What an award changes: one price at most, and what it adds to a counter.
local function validEffects(list, accounts)
    if type(list) ~= "table" or #list > LootRule.MAX_EFFECTS then return false end
    local charged = false
    for _, e in ipairs(list) do
        if type(e) ~= "table" then return false end
        if e.k == "add" then
            if not (accounts[e.acct] and wholeIn(e.value, 1, 100)) then return false end
        elseif e.k == "charge" then
            if charged or not PRICES[e.price] or (e.acct ~= nil and e.acct ~= "dkp") then return false end
            if e.price == "fixed" and not wholeIn(e.value, 0, LootRule.MAX_BID) then return false end
            charged = true
        else
            return false
        end
    end
    return true
end

function LootRule:Validate(rule)
    if type(rule) ~= "table" then return false, "not a table" end
    if rule.v ~= self.VERSION then return false, "version" end
    local accounts = {}
    if rule.accounts ~= nil then
        accounts = validAccounts(rule.accounts)
        if not accounts then return false, "accounts" end
    end
    local order = rule.order
    if type(order) ~= "table" or #order == 0 then return false, "no order" end
    if #order > self.MAX_CRITERIA then return false, "too many criteria" end
    local seen = {}
    for _, entry in ipairs(order) do
        if type(entry) ~= "table" or not self.CRITERIA[entry.k] then return false, "unknown criterion" end
        -- Each criterion once, except an account's: once per account.
        local id = entry.k
        if entry.k == "account" then
            if not accounts[entry.acct] then return false, "unknown account" end
            if entry.dir ~= nil and entry.dir ~= "high" and entry.dir ~= "low" then return false, "dir" end
            id = "account:" .. entry.acct
        elseif entry.dir ~= nil or entry.acct ~= nil then
            return false, "unknown criterion"
        end
        if seen[id] then return false, "criterion twice" end
        seen[id] = true
        if entry.band ~= nil and (type(entry.band) ~= "number" or entry.band <= 0) then
            return false, "band"
        end
    end
    local filters = rule.filters
    if filters ~= nil then
        if type(filters) ~= "table" or #filters > self.MAX_FILTERS then return false, "filters" end
        for _, f in ipairs(filters) do
            local known = type(f) == "table" and type(f.min) == "number" and (
                (f.k == "attendance" and f.act == "downgrade" and type(f.from) == "string" and type(f.to) == "string")
                or (f.k == "points" and f.act == "block"))
            if not known then return false, "unknown filter" end
        end
    end
    if rule.responses ~= nil and not validResponses(rule.responses) then return false, "responses" end
    if rule.time ~= nil and not wholeIn(rule.time, self.TIME_MIN, self.TIME_MAX) then return false, "time" end
    -- The bids' own rules: open or sealed, the least one may bid and by how much a bid goes up.
    local bid = rule.bid
    if bid ~= nil then
        if type(bid) ~= "table" or not flagOrNil(bid.sealed) then return false, "bid" end
        if bid.min ~= nil and not wholeIn(bid.min, 0, self.MAX_BID) then return false, "bid" end
        if bid.step ~= nil and not wholeIn(bid.step, 1, self.MAX_BID) then return false, "bid" end
    end
    if rule.effects ~= nil and not validEffects(rule.effects, accounts) then return false, "effects" end
    return true
end

----------------------------------------------------------------------
-- How to ask (issue #334): the answers of a rule, and what each one means.
----------------------------------------------------------------------
-- The answers a rule offers, in their order. "PASS" is always one more, and never in the list.
function LootRule:Responses(rule)
    rule = rule or self:Active()
    return rule.responses or DEFAULT_RESPONSES
end

-- The answer `key` names and its place, or nil.
function LootRule:Response(key, rule)
    for i, r in ipairs(self:Responses(rule)) do
        if r.key == key then return r, i end
    end
    return nil
end

-- What a button of `r` says.
function LootRule:ResponseLabel(r)
    return r.label or r.key
end

-- Whether any answer of the rule asks for a bid.
function LootRule:HasBids(rule)
    for _, r in ipairs(self:Responses(rule)) do
        if r.ask == "bid" then return true end
    end
    return false
end

-- The bids' rules: sealed or open, the least one may bid, and the step a bid goes up by.
function LootRule:BidRules(rule)
    local bid = (rule or self:Active()).bid or {}
    return bid.sealed == true, bid.min or 0, bid.step or 1
end

-- The counter accounts a rule keeps: { { key, type, name, reset }, ... }.
function LootRule:Counters(rule)
    return (rule or self:Active()).accounts or {}
end

-- The effect that says what the winner pays, or nil: the item's price, as before.
function LootRule:ChargeEffect(rule)
    for _, e in ipairs((rule or self:Active()).effects or {}) do
        if e.k == "charge" then return e end
    end
    return nil
end

-- What `winner` pays for an item whose price on the guild's table is `tablePrice`, and how that was
-- reached ("table", "fixed", "bid" or "second"). `others` are the rest of the candidates.
--   * "bid": the winner's own bid;
--   * "second": the best bid the winner beat among those who gave the same answer, plus one step, and
--     never more than the winner's own; with nobody to beat, the least one may bid;
--   * every price is then multiplied by the answer's `cost` (off spec for half, a free answer for 0).
function LootRule:PriceFor(winner, others, tablePrice, rule)
    rule = rule or self:Active()
    local effect = self:ChargeEffect(rule)
    local how = effect and effect.price or "table"
    local price = tablePrice or 0
    if how == "fixed" then
        price = effect.value or 0
    elseif how == "bid" then
        price = (winner and winner.bid) or 0
    elseif how == "second" then
        local _, min, step = self:BidRules(rule)
        local own, best = (winner and winner.bid) or 0, nil
        for _, c in ipairs(winner and others or {}) do
            if c ~= winner and c.rollType == winner.rollType and c.bid and (not best or c.bid > best) then
                best = c.bid
            end
        end
        price = math.min(own, best and (best + step) or min)
    end
    local r = winner and self:Response(winner.rollType, rule)
    local cost = r and r.cost or 1
    return math.max(0, math.floor(price * cost + 0.5)), how
end

----------------------------------------------------------------------
-- The answers on the wire: what a raider's popup needs of the rule, in one addon message (255 bytes,
-- of which the loot master's header takes a few).
--   <time>,<o|s|->,<min>,<step>;<KEY>=<a><label>;<KEY>=<a>;...
-- `o` open bids, `s` sealed, `-` no answer bids. <a> is r (roll), b (bid) or n (neither), in capitals
-- when the answer needs a note. A label equal to its key is left out, and the last labels are left out
-- when the whole would not fit: the button then shows the key.
----------------------------------------------------------------------
local ASK_CODE = { roll = "r", bid = "b", none = "n" }
local CODE_ASK = { r = "roll", b = "bid", n = "none" }

function LootRule:Encode(rule, time)
    rule = rule or self:Active()
    local sealed, min, step = self:BidRules(rule)
    local list = self:Responses(rule)
    local head = string.format("%d,%s,%d,%d", time or rule.time or 30,
        self:HasBids(rule) and (sealed and "s" or "o") or "-", min, step)
    local labelled = #list
    while true do
        local parts = { head }
        for i, r in ipairs(list) do
            local code = ASK_CODE[r.ask or "roll"]
            if r.note then code = code:upper() end
            local label = (i <= labelled and r.label and r.label ~= r.key) and r.label or ""
            parts[#parts + 1] = r.key .. "=" .. code .. label
        end
        local text = table.concat(parts, ";")
        if #text <= self.WIRE_MAX or labelled == 0 then return text end
        labelled = labelled - 1
    end
end

-- What another client's `Encode` said, or nil when any of it is not what this client writes: an addon
-- message is read whole or not at all.
function LootRule:Decode(text)
    if type(text) ~= "string" or #text > 255 then return nil end
    local head, rest = text:match("^([^;]+);(.+)$")
    if not head then return nil end
    local time, flag, min, step = head:match("^(%d+),([os%-]),(%d+),(%d+)$")
    time, min, step = tonumber(time), tonumber(min), tonumber(step)
    if not (time and wholeIn(time, self.TIME_MIN, self.TIME_MAX)) then return nil end
    if not (wholeIn(min, 0, self.MAX_BID) and wholeIn(step, 1, self.MAX_BID)) then return nil end
    local spec = { time = time, bids = flag ~= "-", sealed = flag == "s", min = min, step = step, responses = {} }
    local seen = {}
    for part in (rest .. ";"):gmatch("([^;]*);") do
        local key, code, label = part:match("^([A-Z0-9]+)=(%a)(.*)$")
        local ask = code and CODE_ASK[code:lower()]
        if not (ask and isKey(key, "A-Z0-9")) or key == "PASS" or seen[key] then return nil end
        if label ~= "" and not isLabel(label) then return nil end
        seen[key] = true
        spec.responses[#spec.responses + 1] = {
            key = key, label = label ~= "" and label or key, ask = ask, note = code ~= code:lower(),
        }
    end
    if #spec.responses == 0 or #spec.responses > self.MAX_RESPONSES then return nil end
    -- Bids are open or sealed exactly when an answer asks for one.
    local anyBid = false
    for _, r in ipairs(spec.responses) do anyBid = anyBid or r.ask == "bid" end
    if anyBid ~= spec.bids then return nil end
    return spec
end

----------------------------------------------------------------------
-- The ready-made rules: each loot system of before, with the loot settings it read, and the models
-- issue #334 adds beside them ("plus1", "dkpbid", "dkpsealed").
----------------------------------------------------------------------
function LootRule:FromLegacy(system, cfg)
    cfg = cfg or {}
    local rule = { v = self.VERSION, model = system or "rolls", responses = defaultResponses(), filters = {} }
    local minAtt = cfg.minAttendancePct or 0
    if minAtt > 0 then
        rule.filters[1] = { k = "attendance", min = minAtt, act = "downgrade", from = "MS", to = "OS" }
    end
    -- The points economy: a roll that costs something to enter (issue #309) is closed to whoever
    -- cannot pay it.
    if system == "dkp" or system == "epgp" then
        local entry = tonumber(cfg.entryCost) or 0
        if entry > 0 and system == "dkp" then
            rule.filters[#rule.filters + 1] = { k = "points", min = entry, act = "block" }
        end
        rule.order = { { k = "response" }, { k = system == "epgp" and "pr" or "points" }, { k = "roll" } }
        return rule
    end
    -- "+1" (issue #334): main spec before off spec, then whoever won fewer main spec items tonight,
    -- then the roll. Winning with an answer that counts adds one.
    if system == "plus1" then
        rule.accounts = { { key = "plus1", type = "counter", name = "+1", reset = "night" } }
        rule.order = { { k = "response" }, { k = "account", acct = "plus1", dir = "low" }, { k = "roll" } }
        rule.effects = { { k = "add", acct = "plus1", value = 1 } }
        return rule
    end
    -- DKP by bids (issue #334): main spec before off spec, then the highest bid, then who holds more
    -- points. Open, the winner pays what they bid; sealed, one step over the bid they beat. The least
    -- bid and the time to bid are the ones the core's loot settings always had.
    if system == "dkpbid" or system == "dkpsealed" then
        for _, r in ipairs(rule.responses) do r.ask = "bid" end
        local time = tonumber(cfg.dkpBidTime)
        if time and time == math.floor(time) and time >= self.TIME_MIN and time <= self.TIME_MAX then
            rule.time = time
        end
        local min = math.floor(tonumber(cfg.dkpMinBid) or 0)
        rule.bid = { sealed = system == "dkpsealed", min = math.max(0, math.min(self.MAX_BID, min)), step = 1 }
        rule.order = { { k = "response" }, { k = "bid" }, { k = "points" } }
        rule.effects = { { k = "charge", acct = "dkp", price = system == "dkpsealed" and "second" or "bid" } }
        return rule
    end
    -- Retail has no Master Loot (TradeCouncil): the free roll reads the answer and the roll, and only
    -- the wishlist system reads the wishlist.
    if GuildOS.Client.isRetail then
        rule.order = { { k = "response" } }
        if system == "wishlist" then rule.order[2] = { k = "wishlist" } end
        rule.order[#rule.order + 1] = { k = "roll" }
        return rule
    end
    local order = { { k = "response" }, { k = "prio" }, { k = "softres" }, { k = "wishlist" } }
    if cfg.recvPenalty ~= false then order[#order + 1] = { k = "received" } end
    if cfg.attTiebreaker then order[#order + 1] = { k = "attendance" } end
    order[#order + 1] = { k = "roll" }
    rule.order = order
    return rule
end

-- The rule in force: the active core's own, else the guild's, else the one its loot system and
-- settings always meant.
function LootRule:Active()
    local cfg = (GuildOS.LootMaster and GuildOS.LootMaster.GetCfg and GuildOS.LootMaster:GetCfg()) or {}
    if cfg.rule and self:Validate(cfg.rule) then return cfg.rule end
    local s = GuildOS.db and GuildOS.db.settings
    if s and s.lootRule and self:Validate(s.lootRule) then return s.lootRule end
    -- The loot settings, and beside them what the points ask to enter a roll.
    local pool = GuildOS.Points and GuildOS.Points.GetDB and GuildOS.Points:GetDB()
    local legacy = {}
    for k, v in pairs(cfg) do legacy[k] = v end
    legacy.entryCost = pool and pool.config and pool.config.entryCost
    return self:FromLegacy(GuildOS.GetLootSystem and GuildOS:GetLootSystem() or "rolls", legacy)
end

----------------------------------------------------------------------
-- Who may ask: the answer a candidate's is read as. A filter that downgrades turns one answer into
-- another (main spec into off spec below the attendance the guild asks for). Returns the answer and,
-- when it changed, the filter that changed it; no answer at all (nil) when a filter keeps the candidate
-- out, as a roll that costs more points to enter than they hold.
----------------------------------------------------------------------
function LootRule:AnswerFor(c, response, rule)
    rule = rule or self:Active()
    for _, f in ipairs(rule.filters or {}) do
        if f.k == "attendance" and f.act == "downgrade" and response == f.from
            and (c.att25 or 0) < f.min then
            return f.to, f
        end
        -- Out of the roll: nil for an answer.
        if f.k == "points" and f.act == "block" and response ~= "PASS" and (c.dkp or 0) < f.min then
            return nil, f
        end
    end
    return response
end

----------------------------------------------------------------------
-- The order
----------------------------------------------------------------------
-- Whether `a` comes before `b`, and the criterion that said so (nil when every one tied and the name
-- settled it, so that two clients always read the same order).
function LootRule:Before(a, b, rule)
    for _, entry in ipairs(rule.order) do
        local ra, rb = rankOf(entry, a, rule), rankOf(entry, b, rule)
        if ra ~= rb then return ra < rb, entry.k end
    end
    local na, nb = tostring(a.name or a.key or ""):lower(), tostring(b.name or b.key or ""):lower()
    return na < nb, nil
end

-- `list` in the rule's order, in place. Returns it.
function LootRule:Sort(list, rule)
    rule = rule or self:Active()
    table.sort(list, function(a, b)
        if a == b then return false end
        return (self:Before(a, b, rule))
    end)
    return list
end

-- The criterion that put `first` ahead of `second`: what the winner line says decided. nil with no
-- second candidate, or when every criterion tied.
function LootRule:DecidedBy(first, second, rule)
    if not (first and second) then return nil end
    local _, key = self:Before(first, second, rule or self:Active())
    return key
end

-- A TradeCouncil answer row as a candidate: Need is the main answer and Greed the second.
local CHOICE_AS = { N = "MS", G = "OS", P = "PASS" }
function LootRule:FromAnswer(row)
    return {
        key = row.key, name = row.key, rollType = CHOICE_AS[row.choice] or row.choice, roll = row.roll,
        wishlist = row.wish and { order = row.wish } or nil, dkp = row.points, pr = row.pr, row = row,
    }
end

----------------------------------------------------------------------
-- The guild's own rule (an officer's): stamped, kept, and told to the guild where the loot system is
-- (retail, issue #185). `nil` goes back to the rule of the loot system.
----------------------------------------------------------------------
function LootRule:Set(rule)
    if not GuildOS:IsOfficer() then return false, "officer" end
    if rule ~= nil then
        local ok, why = self:Validate(rule)
        if not ok then return false, why end
    end
    local s = GuildOS.db.settings
    s.lootRule = rule
    s.lootRuleAt = math.max(GetServerTime(), (s.lootRuleAt or 0) + 1)
    self:Publish()
    if GuildOS.LootMaster and GuildOS.LootMaster.RefreshRollFrame then GuildOS.LootMaster:RefreshRollFrame() end
    return true
end

function LootRule:Publish()
    if not GuildOS.Client.isRetail then return end
    local s = GuildOS.db and GuildOS.db.settings
    if not (s and s.lootRuleAt and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    GuildOS.SyncService:Publish("guildcfg", "lootrule", { rule = s.lootRule or false }, { rev = s.lootRuleAt })
end

-- An officer's rule from the guild (SyncService has checked the officer): the newest stamp wins, and a
-- rule this client cannot read whole is left out, keeping the one it has.
function LootRule:OnSync(env)
    if not GuildOS.Client.isRetail then return end
    local data = env and env.data
    local at = env and tonumber(env.rev)
    if type(data) ~= "table" or not (at and at > 0 and at < math.huge) then return end
    local rule = data.rule
    if rule == false then rule = nil end
    if rule ~= nil and not self:Validate(rule) then return end
    at = math.min(at, GetServerTime() + FUTURE_SLACK)
    local s = GuildOS.db.settings
    if s.lootRuleAt and at <= s.lootRuleAt then return end
    s.lootRule, s.lootRuleAt = rule, at
end

----------------------------------------------------------------------
-- An officer's changes to how raiders answer (issue #334), for the loot settings: each one takes the
-- rule in force, changes one thing in a copy and saves it as the guild's own (`Set`), which refuses a
-- rule that is no longer one. Returns what `Set` returns.
----------------------------------------------------------------------
local function copyOf(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copyOf(x) end
    return out
end

-- Whether the guild keeps a rule of its own, over its loot system's.
function LootRule:IsCustom()
    local s = GuildOS.db and GuildOS.db.settings
    return (s and s.lootRule and self:Validate(s.lootRule)) and true or false
end

-- The rule in force as one to change: a copy, its answers written out.
function LootRule:Draft()
    local rule = copyOf(self:Active())
    rule.model = "custom"
    rule.responses = rule.responses or defaultResponses()
    return rule
end

-- An answer that asks for a bid or a roll is compared by it: the criterion joins the order when it is
-- not there (the bid right after the answer, the roll last), so a button an officer adds is never one
-- that decides nothing.
local function fitOrder(rule)
    local has, asks, at = {}, {}, 0
    for i, entry in ipairs(rule.order) do
        has[entry.k] = true
        if entry.k == "response" then at = i end
    end
    for _, r in ipairs(rule.responses) do asks[r.ask or "roll"] = true end
    if asks.bid and not has.bid and #rule.order < LootRule.MAX_CRITERIA then
        table.insert(rule.order, at + 1, { k = "bid" })
    end
    if asks.roll and not has.roll and #rule.order < LootRule.MAX_CRITERIA then
        rule.order[#rule.order + 1] = { k = "roll" }
    end
end

-- A key as a response's: capitals and digits, eight at most.
function LootRule:CleanKey(text)
    return (tostring(text or ""):upper():gsub("[^A-Z0-9]", ""):sub(1, KEY_MAX))
end

function LootRule:AddResponse(key, label)
    local rule = self:Draft()
    key = self:CleanKey(key)
    label = strtrim(tostring(label or ""))
    rule.responses[#rule.responses + 1] = {
        key = key, label = label ~= "" and label or key, ask = "roll", plus = false, cost = 1,
    }
    fitOrder(rule)
    return self:Set(rule)
end

function LootRule:RemoveResponse(index)
    local rule = self:Draft()
    if not rule.responses[index] then return false, "responses" end
    table.remove(rule.responses, index)
    return self:Set(rule)
end

-- One place up (`by` -1) or down (+1): the order of the answers is their priority.
function LootRule:MoveResponse(index, by)
    local rule = self:Draft()
    local list, to = rule.responses, index + by
    if not (list[index] and list[to]) then return false, "responses" end
    list[index], list[to] = list[to], list[index]
    return self:Set(rule)
end

-- `field` is "label", "ask", "plus", "cost" or "note".
function LootRule:SetResponseField(index, field, value)
    local rule = self:Draft()
    local r = rule.responses[index]
    if not r or not (field == "label" or field == "ask" or field == "plus" or field == "cost" or field == "note") then
        return false, "responses"
    end
    if field == "label" then
        value = strtrim(tostring(value or ""))
    elseif field == "cost" then
        value = tonumber(value)
        if not value then return false, "responses" end
    end
    r[field] = value
    fitOrder(rule)
    return self:Set(rule)
end

function LootRule:SetTime(seconds)
    local rule = self:Draft()
    rule.time = tonumber(seconds)
    return self:Set(rule)
end

-- What the winner pays: "table" (the item's price, as always), "bid" (their own bid) or "second" (one
-- step over the bid they beat).
function LootRule:SetPrice(how)
    local rule = self:Draft()
    local effects = {}
    for _, e in ipairs(rule.effects or {}) do
        if e.k ~= "charge" then effects[#effects + 1] = e end
    end
    if how ~= "table" then effects[#effects + 1] = { k = "charge", acct = "dkp", price = how } end
    rule.effects = effects
    return self:Set(rule)
end

-- When a counter goes back to nothing: "night", "lockout" or "never".
function LootRule:SetCounterReset(acct, reset)
    local rule = self:Draft()
    for _, a in ipairs(rule.accounts or {}) do
        if a.key == acct then a.reset = reset end
    end
    return self:Set(rule)
end

-- `field` is "sealed", "min" or "step".
function LootRule:SetBidField(field, value)
    local rule = self:Draft()
    if not (field == "sealed" or field == "min" or field == "step") then return false, "bid" end
    rule.bid = rule.bid or {}
    if field ~= "sealed" then value = tonumber(value) end
    rule.bid[field] = value
    return self:Set(rule)
end
