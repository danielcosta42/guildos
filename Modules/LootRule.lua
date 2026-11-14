----------------------------------------------------------------------
-- Guild OS - Loot Rule (issue #333)
--
-- Who gets an item, as data instead of code. A rule holds the six blocks of the loot model: who may
-- ask (`filters`), how they ask (`responses`), the order between candidates (`order`), who decides,
-- what an award changes and the items that follow another rule. This module reads `filters`, `order`
-- and, since issue #334, `responses` (the buttons a raider answers with: a roll, a bid or neither, what
-- each one costs and whether it counts for the +1), the bids' own rules, the counter accounts and the
-- effects an award has on them; the other blocks keep the behaviour of the module that owns them until
-- their own issue. Since issue #337 the rare systems too: a queue account (Suicide Kings), a bonus account
-- added to a roll (karma, SR+), a summed score, and what was paid shared among the raid (zero-sum).
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
LootRule.MAX_EXCEPTIONS = 20
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
local PRICES = { table = true, fixed = true, bid = true, second = true, fraction = true, all = true }
-- The points' own accounts (Points.lua): "dkp" is the pool's balance, "ep" and "gp" the two sides of
-- EPGP. Every rule may name them; a rule from the site also declares them (type "balance").
local POINTS_ACCOUNTS = { dkp = true, ep = true, gp = true }
local NAME_MAX = 64           -- bytes of an account's or an exception's name
local EARN_MAX = 12           -- reasons to earn one account declares
local AMOUNT_MAX = 1000000    -- the most an account's figure is set to
local DECIDERS = { auto = true, ml = true, holder = true, council = true }
local COUNCIL_KEYS = { ranks = true, names = true, anon = true, self = true, note = true, quorum = true }
local RANK_MAX = 9            -- a guild has ranks 0 to 9
local COUNCIL_NAMES_MAX = 20  -- council members a rule names one by one
local MEMBER_MAX = 48         -- bytes of a council member's name
local QUORUM_MAX = 40         -- nobody asks for more votes than a raid has players
local ROUNDS = { up = true, down = true, near = true }
local AUTOS = { boss = true, ontime = true, late = true, stayed = true, leftearly = true, raid = true }
local COUNTER_AUTOS = { boss = true, raid = true }   -- what feeds a counter by itself (Points:EarnCounters)
local NEWCOMERS = { bottom = true, random = true }   -- where a queue puts somebody it never saw
local QUEUE_END = 99999       -- the place of somebody a queue does not hold: after everyone it does
local LIST_POINTS = 10        -- what the first place of a list is worth in a score; each place after, one less
local SCORE_PARTS_MAX = 6     -- parts one score adds up
local WEIGHT_MAX = 100        -- the most a part of a score is multiplied by

-- The pieces of the contract (v1) this client does not apply yet. A rule that uses one is refused whole,
-- with "unsupported: <piece>" for a reason, so whoever sees the refusal is told what is missing.
local UNSUPPORTED = {
    upgrade = true, balance = true, counter = true, earn = true,
}
local function unsupported(piece) return "unsupported: " .. piece end

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

-- What a candidate holds on an account: the points' own ("dkp" the balance, "ep" what was earned, "gp"
-- what was spent over the base GP) or a counter (the +1, issue #334). LootMaster reads them off the
-- Points when the answer comes in. The base GP is the rule's own when it declares the account (`start`),
-- else the pool's.
local function held(c, acct, rule)
    if acct == "dkp" then return c.dkp or 0 end
    if acct == "ep" then return c.ep or 0 end
    if acct == "gp" then
        local base = c.gpBase or 0
        for _, a in ipairs(rule and rule.accounts or {}) do
            if a.key == "gp" and a.start then base = a.start end
        end
        return (c.gp or 0) + base
    end
    local has = c.accts and c.accts[acct]
    if has then return has end
    -- A queue reads the place in it (issue #337): whoever it does not hold is after everyone it does.
    for _, a in ipairs(rule and rule.accounts or {}) do
        if a.key == acct and a.type == "queue" then return QUEUE_END end
    end
    return 0
end

local function accountOf(c, rule, entry)
    return held(c, entry.acct, rule)
end

-- The roll, and with it what the candidate holds on a bonus account when the criterion names one and
-- the answer is one that counts (`plus`, issue #337): karma's "roll with karma", SR+'s main spec. An
-- answer with no roll drawn has no bonus either.
local function bonusOf(c, rule, acct)
    if not (acct and c.roll and c.rollType ~= "PASS") then return 0 end
    for _, r in ipairs(rule and rule.responses or DEFAULT_RESPONSES) do
        if r.key == c.rollType then return r.plus and math.max(0, held(c, acct, rule)) or 0 end
    end
    return 0
end

local function rollOf(c, rule, entry)
    return (c.roll or -1) + bonusOf(c, rule, entry and entry.bonus)
end

-- A place on a list as points for a score: the first is worth ten, each place after one less, and
-- past the tenth, or on no list at all, nothing.
local function listPoints(place)
    if not place then return 0 end
    return math.max(0, LIST_POINTS + 1 - place)
end

-- What each part of a score reads off a candidate, the larger the better.
local SCORE_PARTS = {
    wishlist   = function(c) return listPoints(c.wishlist and c.wishlist.order) end,
    prio       = function(c) return listPoints(c.prioOrder) end,
    attendance = function(c) return c.att25 or 0 end,
    received   = function(c) return c.recvCount or 0 end,
    account    = function(c, rule, part) return held(c, part.acct, rule) end,
}

-- A summed score (issue #337): each part times its weight, added up. No formula is written anywhere:
-- the parts are picked from a list and each has a number for a weight.
local function scoreOf(c, rule, entry)
    local total = 0
    for _, part in ipairs(entry.parts) do
        total = total + SCORE_PARTS[part.k](c, rule, part) * part.w
    end
    return total
end

-- One account over another (EP over GP): the divisor is never under 1, so a new raider divides by
-- something.
local function ratioOf(c, rule, entry)
    return held(c, entry.num, rule) / math.max(1, held(c, entry.den, rule))
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
    roll       = { raw = rollOf, high = true },
    bid        = { raw = function(c) return c.bid or 0 end, high = true },
    account    = { raw = accountOf, high = true },   -- `dir = "low"` on the entry turns it round
    ratio      = { raw = ratioOf, high = true },
    score      = { raw = scoreOf, high = true },
}
-- The fields an entry of `order` may carry beside `k` and `band`, by criterion.
local CRITERION_FIELDS = {
    account = { acct = true, dir = true }, ratio = { num = true, den = true },
    roll = { bonus = true }, score = { parts = true },
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
    ratio      = "the ratio",
    score      = "the score",
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
local function isLabel(text, max)
    return type(text) == "string" and #text >= 1 and #text <= (max or LABEL_MAX) and not text:find("[|;%c]")
end

local function flagOrNil(v) return v == nil or type(v) == "boolean" end

-- A number of at least `min` and at most `max` (never NaN).
local function numberIn(n, min, max)
    return type(n) == "number" and n == n and n >= min and n <= max
end

-- Whether every key of `t` is one of `allowed`: a field this client never heard of is a rule it cannot
-- read whole.
local function onlyKeys(t, allowed)
    for k in pairs(t) do
        if not allowed[k] then return false end
    end
    return true
end

-- A list: a table of at most `max` entries and nothing beside them, its keys exactly 1 to n with
-- none missing. Counting the keys against `#t` was not that: with a hole and a key beside the entries
-- ({ nil, a, b, extra = true }) both say 3, and a rule nothing of which had been read passed, to break
-- whoever read it next.
local function isList(t, max)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n > max then return false end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local RULE_KEYS = { v = true, model = true, time = true, responses = true, bid = true, filters = true,
    order = true, decide = true, effects = true, exceptions = true, accounts = true }
local RESPONSE_KEYS = { key = true, label = true, ask = true, plus = true, cost = true, note = true }
local FILTER_KEYS = { k = true, act = true, min = true, max = true, acct = true, from = true, to = true }
local EFFECT_KEYS = { k = true, acct = true, price = true, value = true, refund = true }
local ACCOUNT_KEYS = { key = true, type = true, name = true, start = true, cap = true, floor = true,
    decay = true, reset = true, earn = true, frozen = true, newcomer = true }
local EARN_KEYS = { key = true, auto = true, name = true, value = true, weekly = true }

-- How to ask (issue #334): up to ten answers, each a button.
local function validResponses(list)
    if not isList(list, LootRule.MAX_RESPONSES) or #list == 0 then return false end
    local seen = {}
    for _, r in ipairs(list) do
        if type(r) ~= "table" or not onlyKeys(r, RESPONSE_KEYS) then return false end
        if not isKey(r.key, "A-Z0-9") or r.key == "PASS" or seen[r.key] then return false end
        seen[r.key] = true
        if r.label ~= nil and not isLabel(r.label) then return false end
        if r.ask ~= nil and not ASKS[r.ask] then return false end
        if not (flagOrNil(r.plus) and flagOrNil(r.note)) then return false end
        if r.cost ~= nil and not numberIn(r.cost, 0, COST_MAX) then return false end
    end
    return true
end

-- The accounts a rule keeps or names. Returns them by key (the points' own are always known, declared
-- or not), or nil and why.
--   * "counter": a small whole number per character (the +1, a wait), which an award adds to, takes
--     from or empties, and which a raid attended or a boss killed can feed by itself;
--   * "balance": only the points' own, "dkp", "ep" and "gp". What the rule says of how they fill
--     between items (earn, decay, cap) is read and left to the pool's own settings in the game; the GP
--     account's `start` is the base GP the rule's ratio divides by;
--   * "bonus" (issue #337): a counter added to a roll (karma, SR+). It starts at nothing, may have a
--     cap it never grows past, and is fed like a counter;
--   * "queue" (issue #337): an ordered list of players (Suicide Kings), read by the place in it.
--     `frozen`: when the winner drops, only who is in the raid moves up and whoever is absent keeps
--     their slot; `newcomer`: somebody it never saw joins at the "bottom" or at a "random" place.
local function validAccounts(list)
    local known = { dkp = { key = "dkp", type = "balance" }, ep = { key = "ep", type = "balance" },
        gp = { key = "gp", type = "balance" } }
    if list == nil then return known end
    if not isList(list, LootRule.MAX_ACCOUNTS) then return nil, "accounts" end
    local seen = {}
    for _, a in ipairs(list) do
        if type(a) ~= "table" or not onlyKeys(a, ACCOUNT_KEYS) then return nil, "accounts" end
        if not isKey(a.key, "a-z0-9") or seen[a.key] then return nil, "accounts" end
        seen[a.key] = true
        if a.type ~= "counter" and a.type ~= "balance" and a.type ~= "queue" and a.type ~= "bonus" then
            return nil, "accounts"
        end
        if not flagOrNil(a.frozen) or (a.newcomer ~= nil and not NEWCOMERS[a.newcomer]) then return nil, "accounts" end
        if a.type ~= "queue" and (a.frozen ~= nil or a.newcomer ~= nil) then return nil, "accounts" end
        if a.name ~= nil and not isLabel(a.name, NAME_MAX) then return nil, "accounts" end
        if a.reset ~= nil and not RESETS[a.reset] then return nil, "accounts" end
        for _, f in ipairs({ "start", "cap", "floor" }) do
            if a[f] ~= nil and not numberIn(a[f], -AMOUNT_MAX, AMOUNT_MAX) then return nil, "accounts" end
        end
        local decay = a.decay
        if decay ~= nil then
            if type(decay) ~= "table" or not onlyKeys(decay, { pct = true, round = true }) then return nil, "accounts" end
            if not (numberIn(decay.pct, 0, 100) and decay.pct > 0) then return nil, "accounts" end
            if decay.round ~= nil and not ROUNDS[decay.round] then return nil, "accounts" end
        end
        local earn, earnKeys = a.earn, {}
        if earn ~= nil then
            if not isList(earn, EARN_MAX) then return nil, "accounts" end
            for _, e in ipairs(earn) do
                if type(e) ~= "table" or not onlyKeys(e, EARN_KEYS) then return nil, "accounts" end
                if not isKey(e.key, "a-z0-9") or earnKeys[e.key] then return nil, "accounts" end
                earnKeys[e.key] = true
                if e.auto ~= nil and not AUTOS[e.auto] then return nil, "accounts" end
                if e.name ~= nil and not isLabel(e.name, NAME_MAX) then return nil, "accounts" end
                if not numberIn(e.value, -AMOUNT_MAX, AMOUNT_MAX) then return nil, "accounts" end
                if e.weekly ~= nil and not (numberIn(e.weekly, 0, AMOUNT_MAX) and e.weekly > 0) then return nil, "accounts" end
            end
        end
        if a.type == "queue" then
            -- A queue is an order and nothing else: no figure to start at, to cap, to decay or to earn.
            if POINTS_ACCOUNTS[a.key] or a.start ~= nil or a.cap ~= nil or a.floor ~= nil or a.decay ~= nil
                or a.reset ~= nil or earn ~= nil then
                return nil, "accounts"
            end
        elseif a.type == "bonus" then
            if POINTS_ACCOUNTS[a.key] then return nil, "accounts" end
            if (a.start or 0) ~= 0 or (a.floor or 0) ~= 0 or a.decay ~= nil then return nil, unsupported("counter") end
            if a.cap ~= nil and not wholeIn(a.cap, 1, AMOUNT_MAX) then return nil, "accounts" end
            for _, e in ipairs(earn or {}) do
                if not (COUNTER_AUTOS[e.auto] and wholeIn(e.value, 1, 100) and e.weekly == nil) then
                    return nil, unsupported("earn")
                end
            end
        elseif a.type == "counter" then
            if POINTS_ACCOUNTS[a.key] then return nil, "accounts" end
            -- A counter starts at nothing and holds what the awards made of it.
            if (a.start or 0) ~= 0 or a.cap ~= nil or a.floor ~= nil or a.decay ~= nil then
                return nil, unsupported("counter")
            end
            for _, e in ipairs(earn or {}) do
                if not (COUNTER_AUTOS[e.auto] and wholeIn(e.value, 1, 100) and e.weekly == nil) then
                    return nil, unsupported("earn")
                end
            end
        elseif not POINTS_ACCOUNTS[a.key] then
            return nil, unsupported("balance")
        end
        known[a.key] = a
    end
    return known
end

-- Who may ask: up to ten filters. Each one names what it looks at and what it does to whoever fails
-- it: "block" keeps them out of the roll, "downgrade" reads one answer as another.
--   attendance { min }   below the attendance the guild asks for
--   account { acct, min } holding less than `min` on an account
--   points { min }       the same on the points, as this client wrote it before the contract
--   reserved             without a reserve on the item
--   received { max }     with `max` items or more received tonight
local function validFilters(list, accounts)
    if not isList(list, LootRule.MAX_FILTERS) then return false end
    for _, f in ipairs(list) do
        if type(f) ~= "table" or not onlyKeys(f, FILTER_KEYS) then return false end
        if f.k == "attendance" then
            if not numberIn(f.min, 0, 100) or f.max ~= nil or f.acct ~= nil then return false end
        elseif f.k == "account" then
            if not (type(f.acct) == "string" and accounts[f.acct]) then return false end
            if not numberIn(f.min, -AMOUNT_MAX, AMOUNT_MAX) or f.max ~= nil then return false end
        elseif f.k == "points" then
            if not numberIn(f.min, -AMOUNT_MAX, AMOUNT_MAX) or f.max ~= nil or f.acct ~= nil then return false end
        elseif f.k == "reserved" then
            if f.min ~= nil or f.max ~= nil or f.acct ~= nil then return false end
        elseif f.k == "received" then
            if not wholeIn(f.max, 0, 100) or f.min ~= nil or f.acct ~= nil then return false end
        else
            return false
        end
        if f.act == "downgrade" then
            if not (isKey(f.from, "A-Z0-9") and isKey(f.to, "A-Z0-9")) or f.from == f.to then return false end
        elseif f.act == "block" then
            if f.from ~= nil or f.to ~= nil then return false end
        else
            return false
        end
    end
    return true
end

-- The order: up to ten criteria, each once (an account's and a ratio's once per account).
local function validOrder(order, accounts)
    if not isList(order, math.huge) or #order == 0 then return false, "no order" end
    if #order > LootRule.MAX_CRITERIA then return false, "too many criteria" end
    local seen = {}
    for _, entry in ipairs(order) do
        if type(entry) ~= "table" then return false, "unknown criterion" end
        if entry.k == "upgrade" then return false, unsupported(entry.k) end
        if not LootRule.CRITERIA[entry.k] then return false, "unknown criterion" end
        local own = CRITERION_FIELDS[entry.k] or {}
        for field in pairs(entry) do
            if field ~= "k" and field ~= "band" and not own[field] then return false, "unknown criterion" end
        end
        local id = entry.k
        if entry.k == "account" then
            if not (type(entry.acct) == "string" and accounts[entry.acct]) then return false, "unknown account" end
            if entry.dir ~= nil and entry.dir ~= "high" and entry.dir ~= "low" then return false, "dir" end
            id = "account:" .. entry.acct
        elseif entry.k == "ratio" then
            if not (type(entry.num) == "string" and accounts[entry.num] and type(entry.den) == "string"
                and accounts[entry.den]) or entry.num == entry.den then
                return false, "unknown account"
            end
        elseif entry.k == "roll" and entry.bonus ~= nil then
            -- The roll with a bonus (issue #337): only an account of that kind is added to one.
            local bonus = type(entry.bonus) == "string" and accounts[entry.bonus]
            if not (bonus and bonus.type == "bonus") then return false, "unknown account" end
        elseif entry.k == "score" then
            -- A summed score (issue #337): up to six parts, each one of a list, with its weight.
            local parts = entry.parts
            if not isList(parts, SCORE_PARTS_MAX) or #parts == 0 then return false, "score" end
            local partSeen = {}
            for _, part in ipairs(parts) do
                if type(part) ~= "table" or not onlyKeys(part, { k = true, w = true, acct = true }) then return false, "score" end
                if not SCORE_PARTS[part.k] then return false, "score" end
                if not numberIn(part.w, -WEIGHT_MAX, WEIGHT_MAX) or part.w == 0 then return false, "score" end
                local partId = part.k
                if part.k == "account" then
                    if not (type(part.acct) == "string" and accounts[part.acct]) then return false, "unknown account" end
                    partId = "account:" .. part.acct
                elseif part.acct ~= nil then
                    return false, "score"
                end
                if partSeen[partId] then return false, "score" end
                partSeen[partId] = true
            end
        end
        if seen[id] then return false, "criterion twice" end
        seen[id] = true
        if entry.band ~= nil and not (numberIn(entry.band, 0, math.huge) and entry.band > 0) then
            return false, "band"
        end
    end
    return true
end

-- Who decides. "auto" (the order decides), "ml" (the master looter) and "holder" (whoever holds the
-- item) all end the way this client always did: the order names the winner and the master looter's
-- click gives the item, which does not come back. "council" (issue #336): when the answers close, the
-- council votes among the candidates and the master looter confirms who it proposes (LootCouncil).
--   council { ranks, names, anon, self, note, quorum }: who votes (guild rank indexes, and players by
--   name; with neither, the guild's officers), whether who voted for whom is hidden, whether a member
--   who is a candidate votes on that item, whether every answer needs a note, and how many votes
--   close the vote.
local function validDecide(decide)
    if type(decide) ~= "table" or not onlyKeys(decide, { by = true, council = true }) then return false, "decide" end
    if not DECIDERS[decide.by] then return false, "decide" end
    local council = decide.council
    if council == nil then return true end
    if type(council) ~= "table" or not onlyKeys(council, COUNCIL_KEYS) then return false, "decide" end
    if council.ranks ~= nil then
        if not isList(council.ranks, RANK_MAX + 1) then return false, "decide" end
        for _, rank in ipairs(council.ranks) do
            if not wholeIn(rank, 0, RANK_MAX) then return false, "decide" end
        end
    end
    if council.names ~= nil then
        if not isList(council.names, COUNCIL_NAMES_MAX) then return false, "decide" end
        for _, name in ipairs(council.names) do
            if not isLabel(name, MEMBER_MAX) or name:find("[%s,]") then return false, "decide" end
        end
    end
    if not (flagOrNil(council.anon) and flagOrNil(council.self) and flagOrNil(council.note)) then return false, "decide" end
    if council.quorum ~= nil and not wholeIn(council.quorum, 1, QUORUM_MAX) then return false, "decide" end
    return true
end

-- What an award changes, applied in order:
--   charge { acct, price, value }  what the winner pays. On the points ("dkp", "gp"; one at most): the
--       item's price ("table"), a fixed one, their bid, the second bid, or a share of what they hold
--       ("fraction" with `value` up to 1, "all"). On a counter: "fixed", "fraction" or "all" of it.
--   entry { acct = "dkp", value, refund }  everyone who asked pays `value` to be in the roll, and
--       whoever lost gets the share `refund` of it back (issue #309, now said by the rule).
--   add { acct, value }    adds to the winner's counter, when the winning answer counts (`plus`).
--   reset { acct }         empties the winner's counter.
--   bottom { acct }        the winner goes to the end of a queue, when the winning answer counts (`plus`).
--   split { acct = "dkp" } what the winner was charged for the item is shared equally among whoever is
--       in the raid (zero-sum DKP), the remainder dropped.
-- A bonus account (issue #337) takes what a counter takes: "add", "reset" and "charge".
local function validEffects(list, accounts)
    if not isList(list, LootRule.MAX_EFFECTS) then return false, "effects" end
    local charged, pointsCharged, entered, split = {}, false, false, false
    for _, e in ipairs(list) do
        if type(e) ~= "table" or not onlyKeys(e, EFFECT_KEYS) then return false, "effects" end
        local acct = accounts[e.acct]
        local counter = acct and (acct.type == "counter" or acct.type == "bonus")
        if e.k == "bottom" then
            if not (acct and acct.type == "queue") or charged["q:" .. e.acct] or e.value ~= nil or e.price ~= nil
                or e.refund ~= nil then
                return false, "effects"
            end
            charged["q:" .. e.acct] = true
        elseif e.k == "split" then
            if split or (e.acct ~= nil and e.acct ~= "dkp") or e.value ~= nil or e.price ~= nil or e.refund ~= nil then
                return false, "effects"
            end
            split = true
        elseif e.k == "add" then
            if not (counter and wholeIn(e.value, 1, 100)) or e.price ~= nil or e.refund ~= nil then return false, "effects" end
        elseif e.k == "reset" then
            if not counter or e.value ~= nil or e.price ~= nil or e.refund ~= nil then return false, "effects" end
        elseif e.k == "entry" then
            if entered or e.acct ~= "dkp" or e.price ~= nil or not wholeIn(e.value, 0, LootRule.MAX_BID) then
                return false, "effects"
            end
            if e.refund ~= nil and not numberIn(e.refund, 0, 1) then return false, "effects" end
            entered = true
        elseif e.k == "charge" then
            local key = e.acct or "dkp"
            if not PRICES[e.price] or e.refund ~= nil or charged[key] then return false, "effects" end
            if counter then
                if not (e.price == "fixed" or e.price == "fraction" or e.price == "all") then return false, "effects" end
            elseif key == "dkp" or key == "gp" then
                if pointsCharged then return false, "effects" end
                pointsCharged = true
            else
                return false, "effects"
            end
            if e.price == "fixed" then
                if not wholeIn(e.value, 0, LootRule.MAX_BID) then return false, "effects" end
            elseif e.price == "fraction" then
                if not (numberIn(e.value, 0, 1) and e.value > 0) then return false, "effects" end
            elseif e.value ~= nil then
                return false, "effects"
            end
            charged[key] = true
        else
            return false, "effects"
        end
    end
    return true
end

-- The blocks an exception may swap are checked by the same functions as the rule's own. A rule always
-- has an order; an exception's `set` (`partial`) names only the blocks it swaps.
local function validBlocks(rule, accounts, partial)
    local ok, why
    if rule.order ~= nil or not partial then
        ok, why = validOrder(rule.order, accounts)
        if not ok then return false, why end
    end
    if rule.filters ~= nil and not validFilters(rule.filters, accounts) then return false, "unknown filter" end
    if rule.responses ~= nil and not validResponses(rule.responses) then return false, "responses" end
    if rule.decide ~= nil then
        ok, why = validDecide(rule.decide)
        if not ok then return false, why end
    end
    if rule.effects ~= nil then
        ok, why = validEffects(rule.effects, accounts)
        if not ok then return false, why end
    end
    return true
end

-- The items that follow another rule (issue #335): up to twenty exceptions. `on` says which items
-- (ids, a boss's encounter, a category, a raid's instance; with more than one, all of them), and either
-- `to` gives them a fixed destination with no roll or `set` swaps the blocks it names.
local CATEGORIES = { tier = true, legendary = true, mount = true, recipe = true, boe = true, trash = true,
    unclaimed = true }
local DESTINATIONS = { bank = true, de = true }
local ITEMS_MAX = 40
local ID_MAX = 9999999
local SET_KEYS = { filters = true, responses = true, order = true, decide = true, effects = true }
local function validExceptions(list, accounts)
    if not isList(list, LootRule.MAX_EXCEPTIONS) then return false, "exceptions" end
    for _, x in ipairs(list) do
        if type(x) ~= "table" or not onlyKeys(x, { on = true, name = true, set = true, to = true }) then
            return false, "exceptions"
        end
        if x.name ~= nil and not isLabel(x.name, NAME_MAX) then return false, "exceptions" end
        local on = x.on
        if type(on) ~= "table" or next(on) == nil
            or not onlyKeys(on, { items = true, boss = true, cat = true, raid = true }) then
            return false, "exceptions"
        end
        if on.items ~= nil then
            if not isList(on.items, ITEMS_MAX) or #on.items == 0 then return false, "exceptions" end
            for _, id in ipairs(on.items) do
                if not wholeIn(id, 1, ID_MAX) then return false, "exceptions" end
            end
        end
        if on.boss ~= nil and not wholeIn(on.boss, 1, ID_MAX) then return false, "exceptions" end
        if on.raid ~= nil and not wholeIn(on.raid, 1, ID_MAX) then return false, "exceptions" end
        if on.cat ~= nil and not CATEGORIES[on.cat] then return false, "exceptions" end
        -- One or the other: an item either swaps blocks or has a fixed destination.
        if (x.set == nil) == (x.to == nil) then return false, "exceptions" end
        if x.to ~= nil and not DESTINATIONS[x.to] then return false, "exceptions" end
        if x.set ~= nil then
            if type(x.set) ~= "table" or next(x.set) == nil or not onlyKeys(x.set, SET_KEYS) then
                return false, "exceptions"
            end
            local ok, why = validBlocks(x.set, accounts, true)
            if not ok then return false, why end
        end
    end
    return true
end

-- Whether this client reads `rule` whole. A rule that is not one says why; a rule of the contract
-- that asks for a piece this client does not apply yet says "unsupported: <piece>" (`Unsupported`).
function LootRule:Validate(rule)
    if type(rule) ~= "table" then return false, "not a table" end
    if rule.v ~= self.VERSION then return false, "version" end
    if not onlyKeys(rule, RULE_KEYS) then return false, "unknown field" end
    if rule.model ~= nil and not (type(rule.model) == "string" and #rule.model <= 16 and rule.model:find("^[a-z0-9]+$")) then
        return false, "model"
    end
    local accounts, why = validAccounts(rule.accounts)
    if not accounts then return false, why end
    local ok
    ok, why = validBlocks(rule, accounts)
    if not ok then return false, why end
    if rule.time ~= nil and not wholeIn(rule.time, self.TIME_MIN, self.TIME_MAX) then return false, "time" end
    -- The bids' own rules: open or sealed, the least one may bid and by how much a bid goes up.
    local bid = rule.bid
    if bid ~= nil then
        if type(bid) ~= "table" or not flagOrNil(bid.sealed) then return false, "bid" end
        if bid.min ~= nil and not wholeIn(bid.min, 0, self.MAX_BID) then return false, "bid" end
        if bid.step ~= nil and not wholeIn(bid.step, 1, self.MAX_BID) then return false, "bid" end
    end
    if rule.exceptions ~= nil then
        ok, why = validExceptions(rule.exceptions, accounts)
        if not ok then return false, why end
    end
    return true
end

-- The piece of the contract a refusal was about ("council", "queue", ...), or nil when the rule was
-- simply not one. And that piece in words, for whoever is told.
function LootRule:Unsupported(why)
    local piece = type(why) == "string" and why:match("^unsupported: (%a+)$")
    return UNSUPPORTED[piece] and piece or nil
end

-- Each one by its own literal key, so every language file finds it.
function LootRule:UnsupportedText(piece)
    if piece == "upgrade" then return L["ordering by the size of the upgrade"] end
    if piece == "balance" then return L["a points account other than DKP, EP and GP"] end
    if piece == "counter" then return L["a counter with a start, a cap, a floor or a decay"] end
    if piece == "earn" then return L["an earning a counter cannot take"] end
    return nil
end

----------------------------------------------------------------------
-- Exceptions per item (issue #335)
--
-- An item is what LootMaster knows of it when it is announced:
--   { id, quality, classID, subclassID, bindType, threshold, boss, raid }
-- `boss` is the encounter it dropped from and `raid` the instance, when the client can say.
-- The categories the client recognises with no table typed by the guild:
--   recipe     the item's class is Recipe
--   mount      the item's class is Miscellaneous, subclass Mount
--   boe        it binds when equipped
--   legendary  its quality is legendary
--   trash      its quality is below the loot threshold of the loot settings
--   tier       it is on this game's list of tier pieces and tokens (TIER_ITEMS)
--   unclaimed  nobody asked for it: read at the roll's end, never when it is announced
-- "Not from a boss" is not part of "trash": the client does not tell a boss's loot from another's with
-- the certainty an item given away asks for.
----------------------------------------------------------------------
local CLASS_RECIPE, CLASS_MISC, SUBCLASS_MOUNT = 9, 15, 5
local BIND_ON_EQUIP, QUALITY_LEGENDARY = 2, 5

-- The tier pieces and tokens of each game, by item id. Only ids checked against the game go in here:
-- the lists start empty, and until one is filled the "tier" category matches nothing on that game.
LootRule.TIER_ITEMS = { ANNIVERSARY = {}, FOREVER = {}, RETAIL = {} }

function LootRule:Categories(item)
    local cats = {}
    if type(item) ~= "table" then return cats end
    if item.classID == CLASS_RECIPE then cats.recipe = true end
    if item.classID == CLASS_MISC and item.subclassID == SUBCLASS_MOUNT then cats.mount = true end
    if item.bindType == BIND_ON_EQUIP then cats.boe = true end
    if item.quality == QUALITY_LEGENDARY then cats.legendary = true end
    if item.quality and item.threshold and item.quality < item.threshold then cats.trash = true end
    local tier = self.TIER_ITEMS[GuildOS.Client and GuildOS.Client.game or ""]
    if tier and item.id and tier[item.id] then cats.tier = true end
    return cats
end

-- How specific an exception is: an item's own id before a boss, a boss before a category, a category
-- before a whole raid. One that names several is as specific as the most specific of them.
local function specificity(on)
    return (on.items and 1) or (on.boss and 2) or (on.cat and 3) or 4
end

-- The exception of `rule` an item follows, or nil: the most specific that matches, and among equals
-- the first. `unclaimed` asks at the roll's end for the one for an item nobody asked for; every other
-- is asked for when the item is announced.
function LootRule:ExceptionFor(rule, item, unclaimed)
    if type(item) ~= "table" then return nil end
    local cats = self:Categories(item)
    local best, bestRank
    for _, x in ipairs(rule and rule.exceptions or {}) do
        local on = x.on
        local matches = (on.cat == "unclaimed") == (unclaimed == true)
        if matches and on.items then
            matches = false
            for _, id in ipairs(on.items) do matches = matches or id == item.id end
        end
        if matches and on.boss then matches = on.boss == item.boss end
        if matches and on.raid then matches = on.raid == item.raid end
        if matches and on.cat and on.cat ~= "unclaimed" then matches = cats[on.cat] == true end
        local rank = specificity(on)
        if matches and (not bestRank or rank < bestRank) then best, bestRank = x, rank end
    end
    return best
end

-- The rule an item is played by, and the exception that says so (nil for none). An exception with a
-- fixed destination leaves the rule as it is: there is no roll to play. One that swaps blocks gives the
-- rule with those blocks swapped and every other as it was.
function LootRule:ForItem(rule, item)
    local x = self:ExceptionFor(rule, item, false)
    if not x or x.to then return rule, x end
    local played = {}
    for k, v in pairs(rule) do played[k] = v end
    for k, v in pairs(x.set) do played[k] = v end
    return played, x
end

-- A category's name. Each one by its own literal key, so every language file finds it.
function LootRule:CategoryLabel(cat)
    if cat == "tier" then return L["tier pieces"] end
    if cat == "legendary" then return L["legendaries"] end
    if cat == "mount" then return L["mounts"] end
    if cat == "recipe" then return L["recipes"] end
    if cat == "boe" then return L["bind on equip"] end
    if cat == "trash" then return L["below the loot threshold"] end
    if cat == "unclaimed" then return L["nobody asked"] end
    return tostring(cat)
end

-- An exception's name for the announce line and the editor: its own, else what it is on.
function LootRule:ExceptionLabel(x)
    if x.name then return x.name end
    local on = x.on
    if on.items then
        local ids = {}
        for i, id in ipairs(on.items) do ids[i] = tostring(id) end
        return string.format(L["item %s"], table.concat(ids, ", "))
    end
    if on.boss then return string.format(L["boss %d"], on.boss) end
    if on.cat then return self:CategoryLabel(on.cat) end
    return string.format(L["raid %d"], on.raid or 0)
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

-- The council that decides the rule's items (issue #336), or nil when something else does: its
-- settings as the rule wrote them, { ranks, names, anon, self, note, quorum }.
function LootRule:Council(rule)
    local decide = (rule or self:Active()).decide
    if not (decide and decide.by == "council") then return nil end
    return decide.council or {}
end

-- Whether an answer has to come with a note: its own flag, or the council's, which reads every note.
function LootRule:NeedsNote(response, rule)
    if response and response.note then return true end
    local council = self:Council(rule)
    return (council and council.note) and true or false
end

-- Whether the rule is played whole, with none of the shortcuts the loot systems of before take by
-- the wishlist (a roll closed to whoever is tied on it, an item given straight to its first place): a
-- council that votes, a queue, a bonus account or a summed score reads every candidate.
function LootRule:PlaysWhole(rule)
    rule = rule or self:Active()
    if self:Council(rule) or self:ShowsAccounts(rule) then return true end
    for _, entry in ipairs(rule.order or {}) do
        if entry.k == "score" then return true end
    end
    return false
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

-- The counter accounts a rule keeps: { { key, type, name, reset, earn }, ... }. The points' own
-- accounts a rule from the site declares are not counters.
-- A bonus account (issue #337) is kept as a counter is, and is one of them here.
function LootRule:Counters(rule)
    local out = {}
    for _, a in ipairs((rule or self:Active()).accounts or {}) do
        if a.type == "counter" or a.type == "bonus" then out[#out + 1] = a end
    end
    return out
end

-- The queue accounts a rule keeps (issue #337): { { key, type, name, frozen, newcomer }, ... }.
function LootRule:Queues(rule)
    local out = {}
    for _, a in ipairs((rule or self:Active()).accounts or {}) do
        if a.type == "queue" then out[#out + 1] = a end
    end
    return out
end

-- The queue `key` names in the rule, or nil.
function LootRule:Queue(key, rule)
    for _, a in ipairs(self:Queues(rule)) do
        if a.key == key then return a end
    end
    return nil
end

-- The accounts of the rule a person looks at beside the points (issue #337): its queues, its bonus
-- accounts and its counters, in the rule's order.
function LootRule:OwnAccounts(rule)
    local out = {}
    for _, a in ipairs((rule or self:Active()).accounts or {}) do
        if a.type ~= "balance" then out[#out + 1] = a end
    end
    return out
end

-- Whether the rule keeps a queue or a bonus account: what the points window is offered for even
-- where the loot system spends no points.
function LootRule:ShowsAccounts(rule)
    for _, a in ipairs((rule or self:Active()).accounts or {}) do
        if a.type == "queue" or a.type == "bonus" then return true end
    end
    return false
end

-- The bonus account the rule's roll adds, or nil.
function LootRule:RollBonus(rule)
    for _, entry in ipairs((rule or self:Active()).order or {}) do
        if entry.k == "roll" and entry.bonus then return entry.bonus end
    end
    return nil
end

-- What the roll of a candidate is added by: nothing unless the rule's roll names a bonus account and
-- the candidate's answer is one that counts.
function LootRule:BonusOf(c, rule)
    rule = rule or self:Active()
    return bonusOf(c, rule, self:RollBonus(rule))
end

-- The rule's summed score of a candidate (issue #337), or nil when it orders by none: the total and
-- its parts, { { k, acct, w, value, points }, ... }, for the window that shows them.
function LootRule:ScoreOf(c, rule)
    rule = rule or self:Active()
    for _, entry in ipairs(rule.order or {}) do
        if entry.k == "score" then
            local parts = {}
            for i, part in ipairs(entry.parts) do
                local value = SCORE_PARTS[part.k](c, rule, part)
                parts[i] = { k = part.k, acct = part.acct, w = part.w, value = value, points = value * part.w }
            end
            return scoreOf(c, rule, entry), parts
        end
    end
    return nil
end

-- A part of a score in words. Each one by its own literal key.
function LootRule:PartLabel(part, rule)
    if part.k == "wishlist" then return L["wishlist place"] end
    if part.k == "prio" then return L["officer priority"] end
    if part.k == "attendance" then return L["attendance"] end
    if part.k == "received" then return L["items received"] end
    for _, a in ipairs((rule or self:Active()).accounts or {}) do
        if a.key == part.acct then return a.name or a.key end
    end
    return tostring(part.acct or part.k):upper()
end

-- Whether the rule shares what the winner paid among the raid (zero-sum DKP, issue #337).
function LootRule:Splits(rule)
    for _, e in ipairs((rule or self:Active()).effects or {}) do
        if e.k == "split" then return true end
    end
    return false
end

-- The counter `key` names in the rule, or nil.
function LootRule:Counter(key, rule)
    for _, a in ipairs(self:Counters(rule)) do
        if a.key == key then return a end
    end
    return nil
end

-- The effect that says what the winner pays in points, or nil: the item's price, as before.
function LootRule:ChargeEffect(rule)
    rule = rule or self:Active()
    for _, e in ipairs(rule.effects or {}) do
        if e.k == "charge" and not self:Counter(e.acct, rule) then return e end
    end
    return nil
end

-- The effect that says what it costs to be in the roll, or nil: the points' own setting, as before.
function LootRule:EntryEffect(rule)
    for _, e in ipairs((rule or self:Active()).effects or {}) do
        if e.k == "entry" then return e end
    end
    return nil
end

-- What a charge on a counter takes from a winner who holds `has` on it and won with `response`.
function LootRule:CounterCharge(effect, has, response)
    local amount = effect.value or 0
    if effect.price == "fraction" then amount = has * amount
    elseif effect.price == "all" then amount = has end
    local cost = response and response.cost or 1
    return math.max(0, math.min(has, math.floor(amount * cost + 0.5)))
end

-- Whether the rule reads or moves the points: what the loot master's window and the points' own
-- screens are shown for.
function LootRule:UsesPoints(rule)
    rule = rule or self:Active()
    for _, e in ipairs(rule.order or {}) do
        if e.k == "points" or e.k == "pr" or e.k == "bid" or POINTS_ACCOUNTS[e.acct or ""]
            or POINTS_ACCOUNTS[e.num or ""] or POINTS_ACCOUNTS[e.den or ""] then
            return true
        end
    end
    for _, e in ipairs(rule.effects or {}) do
        if (e.k == "charge" or e.k == "entry") and not self:Counter(e.acct, rule) then return true end
    end
    return false
end

-- The loot system of before a rule from the site reads closest to, for the announce line and for what
-- the loot system shows: EPGP when it orders by a ratio, DKP when it reads or moves the points, the
-- wishlist when it orders by one, else the free roll.
function LootRule:SystemOf(rule)
    local wish = false
    for _, e in ipairs(rule.order or {}) do
        if e.k == "ratio" or e.k == "pr" then return "epgp" end
        wish = wish or e.k == "wishlist" or e.k == "prio"
    end
    if self:UsesPoints(rule) then return "dkp" end
    return wish and "wishlist" or "rolls"
end

-- What `winner` pays for an item whose price on the guild's table is `tablePrice`, and how that was
-- reached ("table", "fixed", "bid" or "second"). `others` are the rest of the candidates.
--   * "bid": the winner's own bid;
--   * "second": the best bid the winner beat among those who gave the same answer, plus one step, and
--     never more than the winner's own; with nobody to beat, the least one may bid;
--   * "fraction" and "all": that share of the points the winner holds (`balance`);
--   * every price is then multiplied by the answer's `cost` (off spec for half, a free answer for 0).
function LootRule:PriceFor(winner, others, tablePrice, rule, balance)
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
    elseif how == "fraction" or how == "all" then
        local has = math.max(0, balance or (winner and winner.dkp) or 0)
        price = how == "all" and has or has * (effect.value or 0)
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
            if self:NeedsNote(r, rule) then code = code:upper() end
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
    -- Suicide Kings (issue #337): main spec goes to whoever is highest on the list, with no roll, and
    -- the winner drops to the end; off spec is a free roll that moves nobody. The classic rule: whoever
    -- is not in the raid keeps their slot.
    if system == "sk" then
        rule.responses = {
            { key = "MS", label = "MS", ask = "none", plus = true, cost = 1 },
            { key = "OS", label = "OS", ask = "roll", plus = false, cost = 0 },
        }
        rule.accounts = { { key = "sk", type = "queue", name = "Suicide Kings", frozen = true, newcomer = "bottom" } }
        rule.order = { { k = "response" }, { k = "account", acct = "sk", dir = "low" }, { k = "roll" } }
        rule.effects = { { k = "bottom", acct = "sk" } }
        return rule
    end
    -- Karma (issue #337): five karma a raid attended, up to a hundred. Main spec rolls with it added
    -- and the winner loses half; off spec rolls without it and costs nothing.
    if system == "karma" then
        rule.responses[2].cost = 0
        rule.accounts = { { key = "karma", type = "bonus", name = "Karma", cap = 100,
            earn = { { key = "raid", auto = "raid", value = 5 } } } }
        rule.order = { { k = "response" }, { k = "roll", bonus = "karma" } }
        rule.effects = { { k = "charge", acct = "karma", price = "fraction", value = 0.5 } }
        return rule
    end
    -- Loot council (issue #336): nobody rolls. The candidates are listed by the answer, the wishlist,
    -- fewer items received and attendance in steps of ten, and the guild's officers vote; two votes
    -- close it. A minute to answer, as a council reads more than a roll does.
    if system == "council" then
        local top = math.max(0, math.min(RANK_MAX, math.floor(tonumber(cfg.officerMaxRank) or 1)))
        local ranks = {}
        for rank = 0, top do ranks[#ranks + 1] = rank end
        rule.responses = {
            { key = "MS", label = "MS", ask = "none", plus = true, cost = 1 },
            { key = "OS", label = "OS", ask = "none", plus = false, cost = 0.5 },
        }
        rule.time = 60
        rule.order = { { k = "response" }, { k = "wishlist" }, { k = "received" }, { k = "attendance", band = 10 } }
        rule.decide = { by = "council", council = { ranks = ranks, anon = false, self = false, note = false, quorum = 2 } }
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

-- A core that exists, by name; nil for the guild ("" or nil) and for a name no core has.
local function coreOrNil(coreName)
    local cores = GuildOS.db and GuildOS.db.cores
    if type(coreName) == "string" and coreName ~= "" and cores and type(cores[coreName]) == "table" then
        return coreName
    end
    return nil
end

-- The loot settings a ready-made rule is built from: the core's (each one the guild's where the core
-- set none), and beside them what its points ask to enter a roll.
local function legacySettings(coreName)
    local CM, LM, legacy = GuildOS.CoreManager, GuildOS.LootMaster, {}
    local active = CM and CM.GetActiveName and CM:GetActiveName() or ""
    local cfg
    if (coreName or "") == active and LM and LM.GetCfg then
        cfg = LM:GetCfg()   -- the raid's own, as the loot master reads them
    else
        cfg = (CM and CM.GetLootConfig and CM:GetLootConfig(coreName or "")) or (GuildOS.db and GuildOS.db.lootMaster)
    end
    cfg = cfg or {}
    for k, v in pairs(cfg) do legacy[k] = v end
    local P = GuildOS.Points
    local pool = P and P.GetDBForCore and GuildOS.db and GuildOS.db.points and P:GetDBForCore(coreName or "")
    legacy.entryCost = pool and pool.config and pool.config.entryCost
    -- The guild's officer threshold: who a ready-made loot council is made of (issue #336).
    legacy.officerMaxRank = GuildOS.db and GuildOS.db.settings and GuildOS.db.settings.officerMaxRank
    return legacy
end

-- The rule of a core, or of the guild ("" or nil), in this order (issue #338): the core's own rule,
-- else the ready-made rule of the core's own loot system, else the guild's rule, else the ready-made
-- rule of the guild's loot system. A core that chose nothing follows the guild; a kept rule this
-- client cannot read whole is passed over, never applied in part.
function LootRule:For(coreName)
    coreName = coreOrNil(coreName)
    local CM = GuildOS.CoreManager
    if coreName and CM and CM.GetLootRule then
        local own = CM:GetLootRule(coreName)
        if own and self:Validate(own) then return own end
        local sys = CM:GetLootSystem(coreName)
        if sys and GuildOS:IsLootSystemHere(sys) then return self:FromLegacy(sys, legacySettings(coreName)) end
    end
    local s = GuildOS.db and GuildOS.db.settings
    if s and s.lootRule and self:Validate(s.lootRule) then return s.lootRule end
    return self:FromLegacy(GuildOS.GetLootSystem and GuildOS:GetLootSystem("") or "rolls", legacySettings(coreName))
end

-- The rule in force: the raid night's own when the site sent one with the night's roster (`Night`),
-- else the one of the raid's active core, and with no core active the guild's.
function LootRule:Active()
    local night = self:Night()
    if night then return night end
    local CM = GuildOS.CoreManager
    return self:For(CM and CM.GetActiveName and CM:GetActiveName() or "")
end

----------------------------------------------------------------------
-- The raid night's rule (guildos-web#516): the site sends the rule a raid plays by with its roster
-- (GOSROST1 v5, `lootRule`), and for that night it comes before the core's and the guild's.
--   * It is taken when this client is in a raid, the roster in hand is for now (from two hours before
--     its start to eight after, the window that matches a night to its planned raid) and the rule
--     reads whole. A rule this client cannot read is refused whole (`NightStatus` says why) and the
--     core's or the guild's stays in force.
--   * Once taken it is frozen for the night (db.lootNight, a copy): a roster imported again with
--     another rule changes nothing until the night is over or the roster in hand is another raid's.
--   * A guild or a core that hands its loot to another addon ("external") takes none.
----------------------------------------------------------------------
local NIGHT_EARLY = 2 * 3600
local NIGHT_LATE = 8 * 3600

local function copyOf(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copyOf(x) end
    return out
end

local function inWindow(startsAt, now)
    startsAt = tonumber(startsAt) or 0
    return startsAt > 0 and now >= startsAt - NIGHT_EARLY and now <= startsAt + NIGHT_LATE
end

-- What the roster in hand says of its rule: the roster, whether it carries one, and whether this client
-- reads it (checked once per roster and kept, as the screens ask often).
local function rosterRule(self)
    local roster = GuildOS.db and GuildOS.db.companionRoster
    if type(roster) ~= "table" or roster.lootRule == nil then return roster, nil end
    local seen = self.nightSeen
    if not (seen and seen.roster == roster and seen.rule == roster.lootRule) then
        local ok, why = false, "not a table"
        if type(roster.lootRule) == "table" then ok, why = self:Validate(roster.lootRule) end
        seen = { roster = roster, rule = roster.lootRule, ok = ok, why = why }
        self.nightSeen = seen
    end
    return roster, seen
end

function LootRule:Night()
    local db = GuildOS.db
    if not db then return nil end
    local now = GetServerTime()
    local roster, seen = rosterRule(self)
    local kept = db.lootNight
    if type(kept) ~= "table" or type(kept.rule) ~= "table" then kept = nil end
    -- Over, or the roster in hand is now another raid's night.
    if kept and (not inWindow(kept.startsAt, now)
        or (roster and roster.raidId ~= kept.raidId and inWindow(roster.startsAt, now))) then
        kept = nil
    end
    -- A kept rule is read again once per session: this client may be an older one than kept it.
    if kept and self.nightKept ~= kept then
        if self:Validate(kept.rule) then self.nightKept = kept else kept = nil end
    end
    if not kept and seen and seen.ok and inWindow(roster.startsAt, now) and IsInRaid() then
        kept = { raidId = roster.raidId, startsAt = roster.startsAt, rule = copyOf(roster.lootRule) }
        self.nightKept = kept
    end
    db.lootNight = kept
    if not kept then return nil end
    if GuildOS.BaseLootSystem and GuildOS:BaseLootSystem() == "external" then return nil end
    return kept.rule
end

-- What to say of the rule the roster in hand carries, for the plan window:
--   nil                        the roster carries none
--   "active", rule             it is the rule in force
--   "waiting", rule            it reads whole, and is taken once the raid is on
--   "refused", nil, piece      this client cannot read it; `piece` names what is missing, when known
function LootRule:NightStatus()
    local roster, seen = rosterRule(self)
    if not seen then return nil end
    if not seen.ok then return "refused", nil, self:Unsupported(seen.why) end
    local kept = GuildOS.db and GuildOS.db.lootNight
    if self:Night() and kept and kept.raidId == roster.raidId then return "active", kept.rule end
    return "waiting", roster.lootRule
end

-- A rule's name for a person: the ready-made model it was born from. Each one by its own literal key.
function LootRule:ModelName(rule)
    local model = type(rule) == "table" and rule.model or "custom"
    if model == "rolls" then return L["Rolls (MS > OS)"] end
    if model == "plus1" then return L["MS > OS +1"] end
    if model == "softres" then return L["Soft reserve"] end
    if model == "srplus" then return L["Soft reserve +"] end
    if model == "hardres" then return L["Hard reserve"] end
    if model == "wishlist" then return L["Wishlist"] end
    if model == "council" then return L["Loot council"] end
    if model == "dkp" then return L["DKP (fixed price)"] end
    if model == "dkpbid" then return L["DKP bidding"] end
    if model == "dkpsealed" then return L["DKP sealed second-price"] end
    if model == "zerosum" then return L["Zero-sum DKP"] end
    if model == "epgp" then return L["EPGP"] end
    if model == "sk" then return L["Suicide Kings"] end
    if model == "karma" then return L["Karma"] end
    if model == "ranked" then return L["Ranked list"] end
    if model == "tmb" then return L["TMB"] end
    return L["Custom rule"]
end

----------------------------------------------------------------------
-- Who may ask: the answer a candidate's is read as. A filter that downgrades turns one answer into
-- another (main spec into off spec below the attendance the guild asks for). Returns the answer and,
-- when it changed, the filter that changed it; no answer at all (nil) when a filter keeps the candidate
-- out, as a roll that costs more points to enter than they hold.
----------------------------------------------------------------------
function LootRule:AnswerFor(c, response, rule)
    rule = rule or self:Active()
    local changed
    for _, f in ipairs(rule.filters or {}) do
        local fails
        if response == "PASS" then
            fails = false   -- a pass is nobody's to refuse
        elseif f.k == "attendance" then
            fails = (c.att25 or 0) < f.min
        elseif f.k == "points" then
            fails = (c.dkp or 0) < f.min
        elseif f.k == "account" then
            fails = held(c, f.acct, rule) < f.min
        elseif f.k == "reserved" then
            fails = not c.softRes
        elseif f.k == "received" then
            fails = (c.recvCount or 0) >= f.max
        end
        if fails and f.act == "block" then
            return nil, f   -- out of the roll: nil for an answer
        elseif fails and response == f.from then
            -- Read as another answer, which the filters after this one still judge.
            response, changed = f.to, f
        end
    end
    return response, changed
end

-- The figure the rule's ratio criterion reads off a candidate (EP over GP), or nil when it has none:
-- what the loot master's window shows as priority.
function LootRule:RatioOf(c, rule)
    rule = rule or self:Active()
    for _, entry in ipairs(rule.order or {}) do
        if entry.k == "ratio" then return ratioOf(c, rule, entry) end
    end
    return nil
end

-- What a candidate holds on the account a filter looks at, for the line that says why they are out.
function LootRule:Held(c, acct, rule)
    return held(c, acct, rule or self:Active())
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

----------------------------------------------------------------------
-- The record of an award (issue #336): why the winner got the item, small enough to keep with the
-- loot history and to send to the site (`why` on a loot entry, CompanionExport).
--   { v = 1, rule = <model, or "custom">, ruleAt = <stamp of the rule in force, 0 for a loot system's>,
--     decidedBy = <criterion key> | "council" | "ml" | "only", exception = <name, when one applied>,
--     candidates = { { name, answer, roll, bid, values = { [criterion] = figure } }, ... },
--     votes = { anon, quorum, cast = { { by, for }, ... }, tally = { [name] = n } } }
-- `candidates` are in the rule's order with the winner first, ten at most. `values` holds what each
-- criterion of the order compared beside the answer, the roll and the bid, which have their own
-- fields, then what else the row knows (reserve, list places, items received, attendance, points),
-- twelve figures at most: a reserve as 1 or 0, a place on a list (absent with none), a figure, "account:<key>" for an
-- account (a bonus account: what it added to the roll). `votes` is there only when a council voted;
-- with an anonymous council `cast` is left out.
----------------------------------------------------------------------
LootRule.WHY_VERSION = 1
LootRule.WHY_CANDIDATES = 10
local WHY_VALUES = 12             -- figures a candidate carries: the site reads no record with more

local function round2(n) return math.floor(n * 100 + 0.5) / 100 end

-- What each criterion of the rule's order compared for a candidate, as figures a person reads.
local function comparedOf(c, rule)
    local values, any, count = {}, false, 0
    for _, entry in ipairs(rule.order or {}) do
        local k, v = entry.k, nil
        local reserve = c.softRes
        if k == "hardres" then
            v = (type(reserve) == "table" and reserve.hard) and 1 or 0
        elseif k == "softres" then
            v = reserve and 1 or 0
        elseif k == "prio" then
            v = c.prioOrder
        elseif k == "wishlist" then
            v = c.wishlist and c.wishlist.order
        elseif k == "received" then
            v = c.recvCount or 0
        elseif k == "attendance" then
            v = c.att25 or 0
        elseif k == "points" then
            v = c.dkp or 0
        elseif k == "pr" then
            v = round2(c.pr or 0)
        elseif k == "account" then
            k, v = "account:" .. entry.acct, held(c, entry.acct, rule)
            if v == QUEUE_END then v = nil end
        elseif k == "ratio" then
            v = round2(ratioOf(c, rule, entry))
        elseif k == "score" then
            v = round2(scoreOf(c, rule, entry))
        elseif k == "roll" and entry.bonus then
            k, v = "account:" .. entry.bonus, bonusOf(c, rule, entry.bonus)
        end
        if type(v) == "number" and v == v and v > -math.huge and v < math.huge and count < WHY_VALUES then
            if values[k] == nil then count = count + 1 end
            values[k], any = v, true
        end
    end
    -- And what the candidate's row knows beside it, while there is room: the site replays an award
    -- under another rule from these alone (guildos-web#517), and a rule that orders by something this
    -- one did not compare could not be replayed without them.
    local reserve = c.softRes
    local facts = {
        { "softres", reserve and 1 or 0 },
        { "hardres", (type(reserve) == "table" and reserve.hard) and 1 or 0 },
        { "prio", c.prioOrder },
        { "wishlist", c.wishlist and c.wishlist.order },
        { "received", c.recvCount },
        { "attendance", c.att25 },
        { "points", c.dkp },
    }
    for _, fact in ipairs(facts) do
        local k, v = fact[1], fact[2]
        if values[k] == nil and count < WHY_VALUES and type(v) == "number" and v == v
            and v > -math.huge and v < math.huge then
            values[k], any, count = v, true, count + 1
        end
    end
    return any and values or nil
end

-- `asked`: the answer the candidate clicked, when a filter of the rule read it as another (`answer`
-- is the one the order compared). Absent when the two are the same, which is nearly always.
local function whyCandidate(c, rule)
    local answer = c.rollType or ""
    return {
        name = tostring(c.name or c.key or ""), answer = answer,
        asked = (type(c.asked) == "string" and c.asked ~= "" and c.asked ~= answer) and c.asked or nil,
        roll = tonumber(c.roll) or 0, bid = tonumber(c.bid) or 0, values = comparedOf(c, rule),
    }
end

-- The record of one award. `spec`: { rule, ruleAt, winner = <name>, sorted = <the candidates in the
-- rule's order>, decidedBy, exception = <its name>, votes }. A winner who gave no answer (an item given
-- straight from the loot window, or sent to the bank) is still the first candidate, with no answer.
function LootRule:Why(spec)
    local rule = spec.rule or self:Active()
    local candidates, winner = {}, nil
    for _, c in ipairs(spec.sorted or {}) do
        if not winner and (c.name or c.key) == spec.winner then winner = c end
    end
    candidates[1] = winner and whyCandidate(winner, rule)
        or { name = tostring(spec.winner or ""), answer = "", roll = 0, bid = 0 }
    for _, c in ipairs(spec.sorted or {}) do
        if c ~= winner and #candidates < self.WHY_CANDIDATES then
            candidates[#candidates + 1] = whyCandidate(c, rule)
        end
    end
    return {
        v = self.WHY_VERSION, rule = rule.model or "custom", ruleAt = math.floor(tonumber(spec.ruleAt) or 0),
        decidedBy = spec.decidedBy or "ml", exception = spec.exception, candidates = candidates, votes = spec.votes,
    }
end

-- What decided an award by the order alone: "only" with a single candidate, the criterion that put
-- the winner ahead of the next when the winner is the first of the order, and "ml" when the master
-- looter gave it to somebody else, or when every criterion tied and nothing in the rule told them apart.
function LootRule:WhyDecided(winnerName, sorted, rule)
    local first = sorted and sorted[1]
    if not first or (first.name or first.key) ~= winnerName then return "ml" end
    if #sorted == 1 then return "only" end
    return self:DecidedBy(first, sorted[2], rule) or "ml"
end

-- The stamp of the rule in force, for the record: the night's start for the raid night's rule, when
-- an officer last changed it for a core's or the guild's own, and 0 for the rule of a loot system.
function LootRule:Stamp()
    if self:Night() then return tonumber(GuildOS.db.lootNight.startsAt) or 0 end
    local CM = GuildOS.CoreManager
    local coreName = coreOrNil(CM and CM.GetActiveName and CM:GetActiveName() or "")
    if coreName and CM.GetLootRule then
        local own = CM:GetLootRule(coreName)
        local lm = GuildOS.db.cores[coreName].lootMaster
        if own and self:Validate(own) then return tonumber(lm and lm.lootAt) or 0 end
        local sys = CM:GetLootSystem(coreName)
        if sys and GuildOS:IsLootSystemHere(sys) then return 0 end
    end
    local s = GuildOS.db and GuildOS.db.settings
    if s and s.lootRule and self:Validate(s.lootRule) then return tonumber(s.lootRuleAt) or 0 end
    return 0
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
-- With `coreName`, that core's own rule (issue #338): kept with the core and told to the other
-- officers with it (CoreManager); `nil` goes back to what the core follows.
----------------------------------------------------------------------
function LootRule:Set(rule, coreName)
    if not GuildOS:IsOfficer() then return false, "officer" end
    if rule ~= nil then
        local ok, why = self:Validate(rule)
        if not ok then return false, why end
    end
    if coreName ~= nil and coreName ~= "" then
        local CM = GuildOS.CoreManager
        if not (coreOrNil(coreName) and CM and CM.SetLootRule and CM:SetLootRule(coreName, rule)) then
            return false, "core"
        end
    else
        local s = GuildOS.db.settings
        s.lootRule = rule
        s.lootRuleAt = math.max(GetServerTime(), (s.lootRuleAt or 0) + 1)
        self:Publish()
    end
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
-- Every one takes a last `coreName` (issue #338): the core whose rule is being changed, from its
-- Config tab; nil or "" is the guild's.
----------------------------------------------------------------------
-- Whether the guild (or the core) keeps a rule of its own, over its loot system's.
function LootRule:IsCustom(coreName)
    coreName = coreOrNil(coreName)
    if coreName then
        local own = GuildOS.CoreManager and GuildOS.CoreManager:GetLootRule(coreName)
        return (own and self:Validate(own)) and true or false
    end
    local s = GuildOS.db and GuildOS.db.settings
    return (s and s.lootRule and self:Validate(s.lootRule)) and true or false
end

-- The guild's rule (or the core's) as one to change: a copy, its answers written out.
function LootRule:Draft(coreName)
    local rule = copyOf(self:For(coreName))
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

function LootRule:AddResponse(key, label, coreName)
    local rule = self:Draft(coreName)
    key = self:CleanKey(key)
    label = strtrim(tostring(label or ""))
    rule.responses[#rule.responses + 1] = {
        key = key, label = label ~= "" and label or key, ask = "roll", plus = false, cost = 1,
    }
    fitOrder(rule)
    return self:Set(rule, coreName)
end

function LootRule:RemoveResponse(index, coreName)
    local rule = self:Draft(coreName)
    if not rule.responses[index] then return false, "responses" end
    table.remove(rule.responses, index)
    return self:Set(rule, coreName)
end

-- One place up (`by` -1) or down (+1): the order of the answers is their priority.
function LootRule:MoveResponse(index, by, coreName)
    local rule = self:Draft(coreName)
    local list, to = rule.responses, index + by
    if not (list[index] and list[to]) then return false, "responses" end
    list[index], list[to] = list[to], list[index]
    return self:Set(rule, coreName)
end

-- `field` is "label", "ask", "plus", "cost" or "note".
function LootRule:SetResponseField(index, field, value, coreName)
    local rule = self:Draft(coreName)
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
    return self:Set(rule, coreName)
end

function LootRule:SetTime(seconds, coreName)
    local rule = self:Draft(coreName)
    rule.time = tonumber(seconds)
    return self:Set(rule, coreName)
end

-- What the winner pays: "table" (the item's price, as always), "bid" (their own bid) or "second" (one
-- step over the bid they beat).
function LootRule:SetPrice(how, coreName)
    local rule = self:Draft(coreName)
    local effects = {}
    for _, e in ipairs(rule.effects or {}) do
        if e.k ~= "charge" then effects[#effects + 1] = e end
    end
    if how ~= "table" then effects[#effects + 1] = { k = "charge", acct = "dkp", price = how } end
    rule.effects = effects
    return self:Set(rule, coreName)
end

-- When a counter goes back to nothing: "night", "lockout" or "never".
function LootRule:SetCounterReset(acct, reset, coreName)
    local rule = self:Draft(coreName)
    for _, a in ipairs(rule.accounts or {}) do
        if a.key == acct then a.reset = reset end
    end
    return self:Set(rule, coreName)
end

-- Who decides (issue #336), for the rule editor: "auto" (the order), "ml" (the master looter) or
-- "council". A council chosen for the first time is the guild's officers, two votes to close.
function LootRule:SetDecide(by, coreName)
    local rule = self:Draft(coreName)
    local decide = rule.decide or {}
    decide.by = by
    if by == "council" and decide.council == nil then
        local top = GuildOS.db and GuildOS.db.settings and tonumber(GuildOS.db.settings.officerMaxRank) or 1
        local ranks = {}
        for rank = 0, math.max(0, math.min(RANK_MAX, math.floor(top))) do ranks[#ranks + 1] = rank end
        decide.council = { ranks = ranks, quorum = 2 }
    end
    rule.decide = decide
    return self:Set(rule, coreName)
end

-- One thing about the council: `field` is "anon", "self" or "note" (yes or no), "quorum" (a number;
-- nothing for none), "names" (the members named one by one, as typed: split at commas and spaces) or
-- "rank" (`value` is a guild rank index, which joins the council or leaves it).
function LootRule:SetCouncilField(field, value, coreName)
    local rule = self:Draft(coreName)
    local decide = rule.decide
    if not (decide and decide.by == "council") then return false, "decide" end
    local council = decide.council or {}
    decide.council = council
    if field == "anon" or field == "self" or field == "note" then
        council[field] = value and true or false
    elseif field == "quorum" then
        council.quorum = tonumber(value)
    elseif field == "names" then
        local names, seen = {}, {}
        for name in tostring(value or ""):gmatch("[^%s,]+") do
            if not seen[name:lower()] then
                seen[name:lower()] = true
                names[#names + 1] = name
            end
        end
        council.names = #names > 0 and names or nil
    elseif field == "rank" then
        local ranks, had = {}, false
        for _, rank in ipairs(council.ranks or {}) do
            if rank == value then had = true else ranks[#ranks + 1] = rank end
        end
        if not had then ranks[#ranks + 1] = value end
        table.sort(ranks)
        council.ranks = ranks
    else
        return false, "decide"
    end
    return self:Set(rule, coreName)
end

-- A queue's own options (issue #337): `field` is "frozen" (whoever is absent keeps their slot) or
-- "newcomer" ("bottom" or "random").
function LootRule:SetQueueField(acct, field, value, coreName)
    if not (field == "frozen" or field == "newcomer") then return false, "accounts" end
    local rule = self:Draft(coreName)
    for _, a in ipairs(rule.accounts or {}) do
        if a.key == acct and a.type == "queue" then a[field] = value end
    end
    return self:Set(rule, coreName)
end

-- `field` is "sealed", "min" or "step".
function LootRule:SetBidField(field, value, coreName)
    local rule = self:Draft(coreName)
    if not (field == "sealed" or field == "min" or field == "step") then return false, "bid" end
    rule.bid = rule.bid or {}
    if field ~= "sealed" then value = tonumber(value) end
    rule.bid[field] = value
    return self:Set(rule, coreName)
end

----------------------------------------------------------------------
-- An officer's exceptions (issue #335), for the rule editor. `spec` says which items and what happens:
--   { kind = "items" | "boss" | "cat" | "raid", value = <ids as text, an id, or a category>,
--     to = "bank" | "de"            -- a fixed destination, or
--     order = { "wishlist", ... } } -- another order: the criteria, first to last
-- Returns what `Set` returns.
----------------------------------------------------------------------
function LootRule:AddException(spec, coreName)
    if type(spec) ~= "table" then return false, "exceptions" end
    local rule = self:Draft(coreName)
    local on = {}
    if spec.kind == "items" then
        on.items = {}
        for id in tostring(spec.value or ""):gmatch("%d+") do on.items[#on.items + 1] = tonumber(id) end
    elseif spec.kind == "boss" or spec.kind == "raid" then
        on[spec.kind] = tonumber(spec.value)
    elseif spec.kind == "cat" then
        on.cat = spec.value
    else
        return false, "exceptions"
    end
    local x = { on = on }
    if spec.to then
        x.to = spec.to
    else
        local order = {}
        for i, k in ipairs(type(spec.order) == "table" and spec.order or {}) do order[i] = { k = k } end
        x.set = { order = order }
    end
    rule.exceptions = rule.exceptions or {}
    rule.exceptions[#rule.exceptions + 1] = x
    return self:Set(rule, coreName)
end

function LootRule:RemoveException(index, coreName)
    local rule = self:Draft(coreName)
    if not (rule.exceptions and rule.exceptions[index]) then return false, "exceptions" end
    table.remove(rule.exceptions, index)
    if #rule.exceptions == 0 then rule.exceptions = nil end
    return self:Set(rule, coreName)
end

-- The categories an exception may be on, in the order the editor offers them.
LootRule.CATEGORY_ORDER = { "recipe", "boe", "mount", "legendary", "tier", "trash", "unclaimed" }
