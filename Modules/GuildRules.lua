----------------------------------------------------------------------
-- Guild OS - The guild's rules (issue #407, epic guildos-web#609)
--
-- Nobody can be warned for a rule they never read. The officers write the guild's rules: a numbered
-- list, each rule a short title and an optional line of text, at most 15 rules. Every member with the
-- addon gets them (guildcfg "rules", newest stamp wins, a tie keeps what is held, on every client: they
-- are for everybody to read) and reads them with /gos rules or on Guild > Rules.
--
-- Where else they show:
--   * the welcome in guild chat (RecruitmentSystem) may end with "type /gos rules", an officer's choice,
--     only when it fits the game's 255 bytes and only when the guild has rules;
--   * a warning's template may name one, {rule} (its number and title, Discipline.Fill);
--   * the companion export (GOSCOMP1) carries them for the site and the Discord bot: `rules`.
--
-- Security: every title and text is cleaned of the game's codes (no "|"), one line, cut to its limit, on
-- the way in from a box and again from the network. The list is capped by count and by bytes.
----------------------------------------------------------------------
local GuildRules = {}
GuildOS.GuildRules = GuildRules
local L = GuildOS.L

GuildRules.RULES_MAX = 15      -- rules on the list
GuildRules.TITLE_MAX = 60      -- bytes of a rule's title
GuildRules.TEXT_MAX = 250      -- bytes of a rule's text
GuildRules.TOTAL_MAX = 4000    -- bytes of the whole list (titles and texts), what may travel
local STAMP_FUTURE_SLACK = 300

local function settings() return GuildOS.db and GuildOS.db.settings end

----------------------------------------------------------------------
-- Pure helpers (unit-tested via /gos selftest and tools/guild-rules.lua)
----------------------------------------------------------------------
-- One rule off a box or the network, cleaned: { title, text }, or nil when it has no title.
function GuildRules.CleanRule(r)
    if type(r) ~= "table" then return nil end
    local title = type(r.title) == "string" and GuildOS:SanitizeUserText(r.title, GuildRules.TITLE_MAX) or ""
    if title == "" then return nil end
    local text = type(r.text) == "string" and GuildOS:SanitizeUserText(r.text, GuildRules.TEXT_MAX) or ""
    return { title = title, text = text }
end

-- A list off the network or the settings, cleaned; nil when it is not a list. Rules that do not clean are
-- dropped; the list stops at RULES_MAX rules or TOTAL_MAX bytes, whichever comes first.
function GuildRules.ValidRules(t)
    if type(t) ~= "table" then return nil end
    local out, bytes = {}, 0
    for i = 1, math.min(#t, GuildRules.RULES_MAX * 4) do   -- never walk a huge list from the network
        local r = GuildRules.CleanRule(t[i])
        if r then
            bytes = bytes + #r.title + #r.text
            if bytes > GuildRules.TOTAL_MAX or #out >= GuildRules.RULES_MAX then break end
            out[#out + 1] = r
        end
    end
    return out
end

-- How a rule reads when a warning names it: its number and its title ("rule 2: No gold selling").
function GuildRules.RefText(n, rule)
    if type(rule) ~= "table" or not rule.title then return nil end
    return string.format(L["rule %d: %s"], n, rule.title)
end

-- The list as chat lines: "1. Title - text".
function GuildRules.Lines(rules)
    local out = {}
    for i, r in ipairs(rules or {}) do
        local line = string.format("%d. %s", i, r.title)
        if r.text and r.text ~= "" then line = line .. " - " .. r.text end
        out[#out + 1] = line
    end
    return out
end

-- The companion export's field (GOSCOMP1 `rules`): { at = stamp, items = { { n, title, text }, ... } }.
-- Nil while the guild never wrote any.
function GuildRules.ExportShape(rules, at)
    if not at then return nil end
    local items = {}
    for i, r in ipairs(rules or {}) do items[i] = { n = i, title = r.title, text = r.text or "" } end
    return { at = at, items = items }
end

----------------------------------------------------------------------
-- The guild's list
----------------------------------------------------------------------
-- The companion export's `rules` (CompanionExport), or nil.
function GuildRules:ForExport()
    return self.ExportShape(self:Get(), self:Stamp())
end

function GuildRules:Get()
    local s = settings()
    return (s and self.ValidRules(s.guildRules)) or {}
end

function GuildRules:Stamp()
    local s = settings()
    return s and s.guildRulesAt or nil
end

function GuildRules:HasRules()
    return #self:Get() > 0
end

-- The rule at `n`, or nil.
function GuildRules:Rule(n)
    return self:Get()[tonumber(n) or 0]
end

local function save(self, rules)
    local s = settings()
    s.guildRules = self.ValidRules(rules)
    s.guildRulesAt = math.max(GetServerTime(), (s.guildRulesAt or 0) + 1)
    self:PublishConfig()
    self:Refresh()
    return true
end

-- An officer adds a rule at the end. True, or false and why ("officer", "empty", "full").
function GuildRules:Add(title, text)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local r = self.CleanRule({ title = title, text = text })
    if not r then return false, "empty" end
    local rules = self:Get()
    if #rules >= self.RULES_MAX then return false, "full" end
    rules[#rules + 1] = r
    local before = #rules
    if #self.ValidRules(rules) < before then return false, "full" end   -- the bytes ran out
    return save(self, rules)
end

-- An officer rewrites the rule at `n`. True, or false and why ("officer", "empty", "missing", "full").
function GuildRules:Update(n, title, text)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local rules = self:Get()
    if not rules[n] then return false, "missing" end
    local r = self.CleanRule({ title = title, text = text })
    if not r then return false, "empty" end
    rules[n] = r
    if #self.ValidRules(rules) < #rules then return false, "full" end
    return save(self, rules)
end

-- An officer removes the rule at `n`: the ones after it move up a number. Whether one went.
function GuildRules:Remove(n)
    if not GuildOS:IsOfficer() then return false end
    local rules = self:Get()
    if not rules[n] then return false end
    table.remove(rules, n)
    return save(self, rules)
end

-- An officer moves the rule at `n` one place up. Whether it moved.
function GuildRules:MoveUp(n)
    if not GuildOS:IsOfficer() then return false end
    local rules = self:Get()
    if not rules[n] or n <= 1 then return false end
    rules[n - 1], rules[n] = rules[n], rules[n - 1]
    return save(self, rules)
end

-- To the guild: when it changes, and on the officers' regular sync and their answer to a request. Only
-- a list somebody wrote: a guild that never did sends nothing. It carries no `max`.
function GuildRules:PublishConfig()
    local s = settings()
    if not (s and s.guildRulesAt and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    GuildOS.SyncService:Publish("guildcfg", "rules", { items = self:Get() }, { rev = s.guildRulesAt })
end

-- From an officer over GUILD (SyncService checked it): the newest stamp wins, a tie keeps what is held.
-- Kept on every client, members' too: the rules are for everybody to read.
function GuildRules:OnConfigSync(env)
    local data = type(env) == "table" and env.data
    local s = settings()
    if type(data) ~= "table" or not s or env.act ~= "rules" then return end
    local at = GuildOS.Finite(env.rev)
    if not (at and at > 0) then return end
    at = math.min(at, GetServerTime() + STAMP_FUTURE_SLACK)
    local rules = self.ValidRules(data.items)
    if not rules then return end
    if s.guildRulesAt and at <= s.guildRulesAt then return end
    s.guildRules, s.guildRulesAt = rules, at
    self:Refresh()
end

function GuildRules:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

-- /gos rules: the list in this member's chat frame, never anybody else's.
function GuildRules:Show()
    local rules = self:Get()
    if #rules == 0 then
        GuildOS:Print(L["The guild has not written its rules yet."])
        return
    end
    GuildOS:Print(L["The guild's rules:"])
    for _, line in ipairs(self.Lines(rules)) do GuildOS:Print("  " .. line) end
end

----------------------------------------------------------------------
-- Lifecycle and self-tests
----------------------------------------------------------------------
function GuildRules:Initialize()
    self:_RegisterTests()
end

function GuildRules:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    local R = GuildRules

    S:Register("guildrules.clean", function()
        local r = R.CleanRule({ title = "  No |cffff0000gold|r selling ", text = "line one\nline two" })
        if not r or r.title:find("|", 1, true) or r.text:find("\n", 1, true) then return false, "codes and lines" end
        if R.CleanRule({ title = "   ", text = "x" }) then return false, "a rule needs a title" end
        if #R.CleanRule({ title = string.rep("a", 99) }).title ~= R.TITLE_MAX then return false, "the title's limit" end
        return true
    end)

    S:Register("guildrules.limits", function()
        local many = {}
        for i = 1, 40 do many[i] = { title = "Rule " .. i, text = string.rep("x", 250) } end
        local out = R.ValidRules(many)
        if #out > R.RULES_MAX then return false, "at most 15" end
        local bytes = 0
        for _, r in ipairs(out) do bytes = bytes + #r.title + #r.text end
        if bytes > R.TOTAL_MAX then return false, "at most 4000 bytes" end
        if R.ValidRules("x") ~= nil then return false, "not a list" end
        return true
    end)

    S:Register("guildrules.ref", function()
        if R.RefText(2, { title = "Be kind" }) ~= string.format(L["rule %d: %s"], 2, "Be kind") then return false, "ref" end
        local lines = R.Lines({ { title = "A", text = "" }, { title = "B", text = "b" } })
        if lines[1] ~= "1. A" or lines[2] ~= "2. B - b" then return false, "lines" end
        return true
    end)
end
