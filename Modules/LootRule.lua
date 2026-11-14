----------------------------------------------------------------------
-- Guild OS - Loot Rule (issue #333)
--
-- Who gets an item, as data instead of code. A rule holds the six blocks of the loot model: who may
-- ask (`filters`), how they ask (`responses`), the order between candidates (`order`), who decides,
-- what an award changes and the items that follow another rule. This module reads `filters` and
-- `order`; the other blocks keep the behaviour of the module that owns them until their own issue.
--
-- `order` is a list of criteria. Two candidates are compared by the first; a tie goes to the next.
-- Every loot system the guild could pick before this (rolls, tmb, wishlist, dkp) is a ready-made rule
-- (`FromLegacy`), built from the system and the loot settings the guild already had, so a guild that
-- updates chooses nothing and sees no change. A custom rule, once an officer saves one, replaces it.
--
-- A candidate is the row LootMaster keeps per roller: { name, rollType, roll, prioOrder, softRes,
-- wishlist, recvCount, att25, dkp, pr }. TradeCouncil's rows are mapped onto the same fields (`FromAnswer`).
-- Pure: no UI, no chat, no events.
----------------------------------------------------------------------

local LootRule = {}
GuildOS.LootRule = LootRule
local L = GuildOS.L

LootRule.VERSION = 1
LootRule.MAX_CRITERIA = 10
LootRule.MAX_FILTERS = 10

local UNRANKED = 999          -- no place on a list: after everyone who has one
local PASS_RANK = 9999        -- a pass is after every answer
local FUTURE_SLACK = 300      -- seconds a peer's clock may run ahead of this one

-- The order of the answers when the rule names none: main spec, then off spec.
local DEFAULT_RESPONSES = { "MS", "OS" }

----------------------------------------------------------------------
-- The criteria. `raw` reads a number off a candidate; `high` says the larger one comes first. `band`
-- on a rule's entry groups raw values into steps of that size before comparing, so "90% and up" tie
-- and the next criterion decides.
----------------------------------------------------------------------
local function responseRank(c, rule)
    if c.rollType == "PASS" then return PASS_RANK end
    for i, key in ipairs(rule.responses or DEFAULT_RESPONSES) do
        if key == c.rollType then return i end
    end
    return UNRANKED
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
}
function LootRule:Label(key)
    local label = LABELS[key]
    return label and L[label] or tostring(key)
end

-- What an entry of `order` says about a candidate, as a number where the smaller comes first.
local function rankOf(entry, c, rule)
    local crit = LootRule.CRITERIA[entry.k]
    local v = crit.raw(c, rule)
    local band = entry.band
    if band and band > 0 then v = math.floor(v / band) end
    return crit.high and -v or v
end

----------------------------------------------------------------------
-- Validation: a rule from another client or from the site is read only when every field is one this
-- client knows. A rule it cannot read whole is not applied in part.
----------------------------------------------------------------------
function LootRule:Validate(rule)
    if type(rule) ~= "table" then return false, "not a table" end
    if rule.v ~= self.VERSION then return false, "version" end
    local order = rule.order
    if type(order) ~= "table" or #order == 0 then return false, "no order" end
    if #order > self.MAX_CRITERIA then return false, "too many criteria" end
    local seen = {}
    for _, entry in ipairs(order) do
        if type(entry) ~= "table" or not self.CRITERIA[entry.k] then return false, "unknown criterion" end
        if seen[entry.k] then return false, "criterion twice" end
        seen[entry.k] = true
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
    if rule.responses ~= nil then
        if type(rule.responses) ~= "table" or #rule.responses == 0 or #rule.responses > 10 then
            return false, "responses"
        end
        for _, key in ipairs(rule.responses) do
            if type(key) ~= "string" or key == "" or key == "PASS" then return false, "responses" end
        end
    end
    return true
end

----------------------------------------------------------------------
-- The ready-made rules: each loot system of before, with the loot settings it read.
----------------------------------------------------------------------
function LootRule:FromLegacy(system, cfg)
    cfg = cfg or {}
    local rule = { v = self.VERSION, model = system or "rolls", responses = { "MS", "OS" }, filters = {} }
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
