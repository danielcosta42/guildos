----------------------------------------------------------------------
-- Guild OS - Chat alerts for the officers (issue #404, epic guildos-web#609)
--
-- The guild's list of words and patterns, each with a CATEGORY (offensive language, gold/boost selling,
-- links, poaching, custom) and a SEVERITY (low only logs it on the panel; medium alerts; high alerts
-- with a sound). When a line of /g matches, the officers get the alert: who, the line, the two lines
-- before it (GuildChat's log) and the category, with Warn (#403), Ignore and Mute this pattern for 1h.
--
-- Assisted, never automatic: nothing here says anything in /g, whispers anybody or punishes anybody.
--
-- The list is the officers' (guildcfg "modrules", newest stamp wins, as the disciplinary record's term,
-- issue #402). It is compiled when it changes, never per line: a line is lowered, unaccented and split
-- into words ONCE, then each rule is one plain find on it. A rule is a whole word (or phrase) by
-- default; a Lua pattern is optional, at most 60 bytes, tested when it is added and run under pcall.
--
-- One alert per line among the officers: the first one to claim the line (a hash of who said it and
-- what, never the text) tells the others over the addon channel, and they only log it. Each officer
-- waits a moment before claiming, so a claim usually lands first; if the channel fails, each officer
-- sees their own, never twice on the same client.
--
-- Privacy: a flagged line is a person's words. The panel keeps them in memory only (the newest 50, for
-- two hours at most); the line is stored only when an officer warns, on the warning's record (#402).
--
-- Chat lockdown (WoW: Forever, retail): the lines arrive secret and are not read at all. The panel
-- says the alerts are paused while it lasts.
----------------------------------------------------------------------
local ModAlerts = {}
GuildOS.ModAlerts = ModAlerts
local L = GuildOS.L

ModAlerts.CATEGORIES = { "offense", "trade", "link", "poaching", "custom" }
ModAlerts.SEVERITIES = { "low", "med", "high" }
ModAlerts.RULES_MAX = 60          -- rules in the guild's list
ModAlerts.PATTERN_MAX = 60        -- bytes of one rule
ModAlerts.FEED_MAX = 50           -- alerts the panel keeps, in memory
ModAlerts.FEED_TTL = 2 * 3600     -- and for how long
ModAlerts.CONTEXT = 2             -- lines before the flagged one
ModAlerts.CLAIM_TTL = 60          -- seconds a claim on a line holds
ModAlerts.CLAIMS_MAX = 200
ModAlerts.CLAIM_WAIT = 1.5        -- at most this long before claiming (spread among the officers)
ModAlerts.MUTE_SECS = 3600

-- The disciplinary reason a category's warning starts on (Discipline.REASONS).
ModAlerts.REASON_OF = {
    offense = "language", trade = "trade", link = "spam", poaching = "poaching", custom = "conduct", flood = "spam",
}
local DEFAULT_SEV = { offense = "med", trade = "high", link = "med", poaching = "high", custom = "med" }
local SEV_RANK = { low = 1, med = 2, high = 3 }
local CAT_SET = {}
for _, c in ipairs(ModAlerts.CATEGORIES) do CAT_SET[c] = true end
local STAMP_FUTURE_SLACK = 300

-- Chinese has no spaces and Korean glues a particle to a word: there a word in their script is any
-- stretch of the line, as Mentions does (issue #106).
local NO_WORD_EDGES = { zhCN = true, zhTW = true, koKR = true }

local function settings() return GuildOS.db and GuildOS.db.settings end

ModAlerts.PREF_DEFAULTS = { enabled = true, officers = false, own = false, sound = true }

function ModAlerts:Prefs()
    GuildOS.db.modAlerts = GuildOS.db.modAlerts or {}
    local p = GuildOS.db.modAlerts
    for k, v in pairs(self.PREF_DEFAULTS) do
        if p[k] == nil then p[k] = v end
    end
    return p
end

----------------------------------------------------------------------
-- Pure helpers (unit-tested via /gos selftest and tools/mod-alerts.lua)
----------------------------------------------------------------------
-- UTF-8 Latin letters with an accent, as their bare letter (both cases: string.lower leaves them).
local FOLD = {}
do
    local function span(first, last, to)
        for b = first, last do FOLD["\195" .. string.char(b)] = to end
    end
    span(128, 133, "a"); span(160, 165, "a")
    span(135, 135, "c"); span(167, 167, "c")
    span(136, 139, "e"); span(168, 171, "e")
    span(140, 143, "i"); span(172, 175, "i")
    span(145, 145, "n"); span(177, 177, "n")
    span(146, 150, "o"); span(178, 182, "o")
    span(153, 156, "u"); span(185, 188, "u")
    span(157, 157, "y"); span(189, 189, "y"); span(191, 191, "y")
    span(159, 159, "ss")
end

-- Lower case, without accents. Other bytes as they are.
function ModAlerts.Fold(s)
    return (tostring(s or ""):lower():gsub("\195[\128-\191]", FOLD))
end

-- The line as it reads on screen: colours and textures gone, a game link as its visible text.
function ModAlerts.Plain(s)
    s = tostring(s or "")
    if not s:find("|", 1, true) then return s end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- Words separated by one space, with a space at each end, so " word " finds a whole word. Separators are
-- whitespace, punctuation and control bytes (never the bytes of an accented or CJK letter).
function ModAlerts.Words(folded)
    local t = folded:gsub("[%s%p%c]+", " ")
    if t:sub(1, 1) ~= " " then t = " " .. t end
    if t:sub(-1) ~= " " then t = t .. " " end
    return t
end

-- A line made ready once for every rule: folded, and as words.
function ModAlerts.Prepare(msg)
    local folded = ModAlerts.Fold(ModAlerts.Plain(msg))
    return folded, ModAlerts.Words(folded)
end

-- Whether a Lua pattern is usable: it compiles on every probe and does not match an empty line (".*"
-- would fire on everything). Returns nil, or why: "invalid" or "broad".
local PROBES = { "", "a", "abc 123 xyz", "%" }
function ModAlerts.CheckLuaPattern(p)
    for _, probe in ipairs(PROBES) do
        local ok, hit = pcall(string.find, probe, p)
        if not ok then return "invalid" end
        if probe == "" and hit then return "broad" end
    end
    -- A trailing lone % is malformed but only fails on a subject that reaches it.
    local tail = p:match("(%%+)$")
    if tail and #tail % 2 == 1 then return "invalid" end
    return nil
end

-- One rule off a box or the network, cleaned: { p, cat, sev, lua }; or nil and why
-- ("empty", "long", "category", "severity", "invalid", "broad").
function ModAlerts.CleanRule(r)
    if type(r) ~= "table" then return nil, "empty" end
    local p = type(r.p) == "string" and strtrim((r.p:gsub("%c", " "))) or ""
    if p == "" or p:find("|", 1, true) then return nil, "empty" end
    if #p > ModAlerts.PATTERN_MAX then return nil, "long" end
    if not CAT_SET[r.cat] then return nil, "category" end
    if not SEV_RANK[r.sev] then return nil, "severity" end
    local isLua = r.lua == true
    if isLua then
        local why = ModAlerts.CheckLuaPattern(p)
        if why then return nil, why end
    elseif not ModAlerts.Words(ModAlerts.Fold(p)):find("[^ ]") then
        return nil, "empty"
    end
    return { p = p, cat = r.cat, sev = r.sev, lua = isLua or nil }
end

-- What identifies a rule (for muting it and refusing a duplicate).
function ModAlerts.RuleKey(r)
    return (r.lua and "L:" .. r.p) or ("W:" .. ModAlerts.Fold(r.p))
end

-- A list off the network or the settings, cleaned; nil when it is not a list. Rules that do not clean
-- are dropped, duplicates too, and the list is cut at RULES_MAX.
function ModAlerts.ValidRules(t)
    if type(t) ~= "table" then return nil end
    local out, seen = {}, {}
    for i = 1, math.min(#t, ModAlerts.RULES_MAX) do
        local r = ModAlerts.CleanRule(t[i])
        if r and not seen[ModAlerts.RuleKey(r)] then
            seen[ModAlerts.RuleKey(r)] = true
            out[#out + 1] = r
        end
    end
    return out
end

-- The list before the officers chose one, in this client's language.
function ModAlerts.DefaultRules()
    local words = {
        offense = L["idiot, moron, stupid, imbecile"],
        trade = L["buy gold, sell gold, cheap gold, gold for sale, selling boost, wts boost"],
        link = L["www, http, https, discord gg"],
        poaching = L["join my guild, join our guild, come to my guild, leave this guild"],
    }
    local out = {}
    for _, cat in ipairs(ModAlerts.CATEGORIES) do
        for w in tostring(words[cat] or ""):gmatch("[^,]+") do
            out[#out + 1] = { p = strtrim(w), cat = cat, sev = DEFAULT_SEV[cat] }
        end
    end
    return ModAlerts.ValidRules(out)
end

-- The list made ready to match: highest severity first, each rule its needle or pattern. A word needle is
-- " word " (or the bare folded text where a word has no edges). Pure on `rules` and `locale`.
function ModAlerts.Compile(rules, locale)
    local out = {}
    for i, r in ipairs(rules or {}) do
        local c = { key = ModAlerts.RuleKey(r), cat = r.cat, sev = r.sev, p = r.p, order = i }
        if r.lua then
            c.pat = r.p
        else
            local folded = ModAlerts.Fold(r.p)
            if NO_WORD_EDGES[locale] and folded:find("[\128-\255]") then
                c.sub = strtrim(folded)
            else
                c.needle = ModAlerts.Words(folded)
            end
        end
        out[#out + 1] = c
    end
    table.sort(out, function(a, b)
        if a.sev ~= b.sev then return SEV_RANK[a.sev] > SEV_RANK[b.sev] end
        return a.order < b.order
    end)
    return out
end

-- The first compiled rule the prepared line matches, skipping muted ones (`muted[key]` > now) and
-- broken ones. A Lua pattern that errors is marked broken and never run again. Pure but for that mark.
function ModAlerts.Match(compiled, folded, words, muted, now)
    for _, c in ipairs(compiled) do
        if not c.broken and not (muted and (muted[c.key] or 0) > (now or 0)) then
            local hit
            if c.needle then
                hit = words:find(c.needle, 1, true)
            elseif c.sub then
                hit = folded:find(c.sub, 1, true)
            else
                local ok, at = pcall(string.find, folded, c.pat)
                if ok then hit = at else c.broken = true end
            end
            if hit then return c end
        end
    end
    return nil
end

-- A short hash of a string (djb2, 32 bits), as 8 hex digits. What goes on the wire instead of a line.
function ModAlerts.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- The claim on a line: who said it and what, never the text itself.
function ModAlerts.ClaimKey(sender, msg)
    return ModAlerts.Hash(tostring(sender or "?") .. "\n" .. tostring(msg or ""))
end

-- The lines before the flagged one, from a chat log ({ n, m } oldest first), at most `n` of them. The log
-- may or may not hold the flagged line already (GuildChat hears the same event): when its last entry is
-- that line, it is left out. Copies, so the log's own rows never travel.
function ModAlerts.Context(log, msg, n)
    local out = {}
    if type(log) ~= "table" then return out end
    local last = #log
    local clean = (tostring(msg or ""):gsub("%c", " "))
    if last > 0 and log[last].m == clean then last = last - 1 end
    for i = math.max(1, last - n + 1), last do
        local e = log[i]
        if e then out[#out + 1] = { n = e.n, m = e.m } end
    end
    return out
end

----------------------------------------------------------------------
-- The guild's list
----------------------------------------------------------------------
local function stamp(s, field)
    s[field] = math.max(GetServerTime(), (s[field] or 0) + 1)
end

function ModAlerts:GetRules()
    local s = settings()
    return (s and self.ValidRules(s.modAlertRules)) or self.DefaultRules()
end

-- Whether the officers have chosen a list (an empty one counts: nothing fires).
function ModAlerts:IsCustomList()
    local s = settings()
    return s ~= nil and s.modAlertRulesAt ~= nil
end

function ModAlerts:Recompile()
    self.compiled = self.Compile(self:GetRules(), GetLocale and GetLocale() or "enUS")
end

local function saveRules(self, rules)
    local s = settings()
    s.modAlertRules = rules
    stamp(s, "modAlertRulesAt")
    self:Recompile()
    self:PublishConfig()
    self:Refresh()
end

-- An officer adds a rule. True, or false and why ("officer", "full", "dupe", or CleanRule's).
function ModAlerts:AddRule(p, cat, sev, isLua)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local r, why = self.CleanRule({ p = p, cat = cat, sev = sev, lua = isLua and true or nil })
    if not r then return false, why end
    local rules = self:GetRules()
    if #rules >= self.RULES_MAX then return false, "full" end
    local key = self.RuleKey(r)
    for _, held in ipairs(rules) do
        if self.RuleKey(held) == key then return false, "dupe" end
    end
    rules[#rules + 1] = r
    saveRules(self, rules)
    return true
end

-- An officer removes the rule at `index` of GetRules(). Whether one went.
function ModAlerts:RemoveRule(index)
    if not GuildOS:IsOfficer() then return false end
    local rules = self:GetRules()
    if not rules[index] then return false end
    table.remove(rules, index)
    saveRules(self, rules)
    return true
end

-- Back to this client's default list, stamped as a choice so the other officers take it.
function ModAlerts:RestoreDefaults()
    if not GuildOS:IsOfficer() then return false end
    saveRules(self, self.DefaultRules())
    return true
end

function ModAlerts:PublishConfig()
    local s = settings()
    if not (s and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    if s.modAlertRulesAt then
        GuildOS.SyncService:Publish("guildcfg", "modrules", { rules = self:GetRules() }, { rev = s.modAlertRulesAt })
    end
end

local function stampOf(env)
    local at = GuildOS.Finite(env.rev)
    if not (at and at > 0) then return nil end
    return math.min(at, GetServerTime() + STAMP_FUTURE_SLACK)
end

-- From an officer over GUILD (SyncService checked it): the newest stamp wins, a tie keeps what is held.
-- Only officers keep the list: it is theirs, and a member's client never matches anything.
function ModAlerts:OnConfigSync(env)
    local data = type(env) == "table" and env.data
    local s = settings()
    if type(data) ~= "table" or not s or not GuildOS:IsOfficer() then return end
    local at = stampOf(env)
    if not at then return end
    if env.act == "modrules" then
        local rules = self.ValidRules(data.rules)
        if not rules then return end
        if s.modAlertRulesAt and at <= s.modAlertRulesAt then return end
        s.modAlertRules, s.modAlertRulesAt = rules, at
        self:Recompile()
    else
        return
    end
    self:Refresh()
end

----------------------------------------------------------------------
-- The alerts
----------------------------------------------------------------------
function ModAlerts:Initialize()
    self.feed, self.claims, self.claimCount, self.mutes, self.pending, self.nextId = {}, {}, 0, {}, {}, 0
    self:Prefs()
    self:Recompile()
    if GuildOS.SyncService then
        GuildOS.SyncService:On("modalert", function(env, sender) ModAlerts:OnClaim(env, sender) end)
    end
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    f:SetScript("OnEvent", function(_, _, msg, author)
        GuildOS:SafeCall(function() ModAlerts:OnChat(msg, author) end)
    end)
    self:_RegisterTests()
end

-- Whether the alerts are paused because the game hides the chat (instance, combat).
function ModAlerts:Paused()
    return GuildOS.Compat.InChatLockdown and GuildOS.Compat.InChatLockdown() or false
end

local function shortName(author)
    return author and (author:match("^([^-]+)") or author) or "?"
end

-- My name as chat says it: on WoW: Forever PlayerName also carries the surname (issue #26).
local function myName()
    local me = GuildOS.Compat.PlayerName() or ""
    return me:match("^%S+") or me
end

-- Whether a line from `author` is one this officer wants read (own lines, officers' lines).
function ModAlerts:_FromWatched(author)
    local prefs = self:Prefs()
    if shortName(author) == myName() and not prefs.own then return false end
    if not prefs.officers and GuildOS:IsOfficerByName(author) then return false end
    return true
end

function ModAlerts:OnChat(msg, author)
    -- Chat in lockdown: nothing of the line is readable, and nothing is tried.
    if GuildOS.Compat.IsSecret(msg, author) then
        if not self.wasPaused then self.wasPaused = true; self:Refresh() end
        return
    end
    if self.wasPaused then self.wasPaused = false; self:Refresh() end
    if not msg or not author or not GuildOS:IsOfficer() or not self:Prefs().enabled then return end
    local now = GetServerTime()
    local folded, words = self.Prepare(msg)
    local rule = self.Match(self.compiled or {}, folded, words, self.mutes, now)
    if rule and self:_FromWatched(author) then self:_Flag(msg, author, rule, now) end
    if GuildOS.ModFlood and GuildOS.ModFlood.OnLine then GuildOS.ModFlood:OnLine(msg, author, now) end
end

-- A new alert from a rule.
function ModAlerts:_Flag(msg, author, rule, now)
    local log = GuildOS.GuildChat and GuildOS.GuildChat:Log() or nil
    self:Deliver({
        kind = "subject", who = shortName(author), key = GuildOS:KeyOfRosterName(author),
        line = GuildOS:CutBytes((tostring(msg):gsub("%c", " ")), 255),
        context = self.Context(log, msg, self.CONTEXT), cat = rule.cat, sev = rule.sev, rule = rule.key,
        claim = self.ClaimKey(author, msg),
    }, now)
end

-- Into the panel, and for medium and high onto this officer's screen unless another officer claimed it.
-- `a.claim` is the line's (or the surge's) claim key. Also used by the anti-flood (#405).
function ModAlerts:Deliver(a, now)
    now = now or GetServerTime()
    self:_PruneClaims(now)
    local held = self.claims[a.claim]
    -- Already alerted (or about to be) on this client for the same line: never twice.
    if (held and held.mine) or self.pending[a.claim] then return end
    self.nextId = self.nextId + 1
    a.id, a.at, a.state = self.nextId, now, "new"
    table.insert(self.feed, 1, a)
    self:_PruneFeed(now)
    if a.sev == "low" then
        self:Refresh()
        return
    end
    if held then
        a.by = held.by
        self:Refresh()
        return
    end
    self:Refresh()
    -- Wait a moment: an officer whose claim lands first spares the others the alert.
    self.pending[a.claim] = true
    GuildOS.Compat.After(math.random() * self.CLAIM_WAIT, function()
        self.pending[a.claim] = nil
        local c = self.claims[a.claim]
        if c and not c.mine then
            a.by = c.by
            self:Refresh()
            return
        end
        self:_Claim(a.claim)
        self:_Show(a)
    end)
end

function ModAlerts:_Claim(key)
    self.claims[key] = { at = GetServerTime(), by = myName(), mine = true }
    self.claimCount = self.claimCount + 1
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("modalert", "claim", { k = key }, { priority = "ALERT" })
    end
end

-- Another officer claimed a line (SyncService checked the officer and GUILD). The key is all that
-- travels; it is checked for shape and only kept a minute.
function ModAlerts:OnClaim(env, sender)
    if not GuildOS:IsOfficer() or type(env) ~= "table" or env.act ~= "claim" then return end
    local k = type(env.data) == "table" and env.data.k
    if type(k) ~= "string" or not k:match("^%x%x%x%x%x%x%x%x$") then return end
    local by = shortName(sender)
    if by == myName() then return end
    if self.claims[k] then return end   -- first claim held wins on this client
    self.claims[k] = { at = GetServerTime(), by = by }
    self.claimCount = self.claimCount + 1
end

function ModAlerts:_PruneClaims(now)
    local cut = now - self.CLAIM_TTL
    for k, c in pairs(self.claims) do
        if c.at < cut then self.claims[k] = nil; self.claimCount = self.claimCount - 1 end
    end
    if self.claimCount > self.CLAIMS_MAX then
        wipe(self.claims)
        self.claimCount = 0
    end
end

function ModAlerts:_PruneFeed(now)
    local cut = now - self.FEED_TTL
    for i = #self.feed, 1, -1 do
        if i > self.FEED_MAX or self.feed[i].at < cut then table.remove(self.feed, i) end
    end
end

function ModAlerts:_Show(a)
    a.shown = true
    if a.sev == "high" and self:Prefs().sound and PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    if GuildOS.ShowModAlert then GuildOS:ShowModAlert(a) end
    self:Refresh()
end

-- The alerts the panel lists, newest first (pruned on the way).
function ModAlerts:Feed()
    self:_PruneFeed(GetServerTime())
    return self.feed
end

function ModAlerts:Find(id)
    for _, a in ipairs(self.feed) do
        if a.id == id then return a end
    end
    return nil
end

-- The officer's three actions. Warn opens the Warn window with the line as the warning's excerpt.
function ModAlerts:Warn(id)
    local a = self:Find(id)
    if not a or not GuildOS.ShowWarnDialog then return false end
    local line = a.line
    if a.lines and #a.lines > 0 then line = a.lines[#a.lines] end
    GuildOS:ShowWarnDialog(a.key, a.who, { excerpt = line, reason = self.REASON_OF[a.cat] })
    a.state = "warned"
    self:Refresh()
    return true
end

function ModAlerts:Ignore(id)
    local a = self:Find(id)
    if not a then return false end
    a.state = "ignored"
    self:Refresh()
    return true
end

-- Mutes the alert's rule on this client for an hour.
function ModAlerts:MuteRule(id)
    local a = self:Find(id)
    if not a or not a.rule then return false end
    self.mutes[a.rule] = GetServerTime() + self.MUTE_SECS
    a.state = "ignored"
    self:Refresh()
    return true
end

function ModAlerts:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
    if self.rulesRefresh then GuildOS:SafeCall(self.rulesRefresh) end
    if self.popupRefresh then GuildOS:SafeCall(self.popupRefresh) end
end

-- What a category and a severity read as.
local CAT_TEXT = {
    offense = L["Offensive language"], trade = L["Gold / boost selling"], link = L["Links"],
    poaching = L["Poaching"], custom = L["Custom"], flood = L["Flood"],
}
function ModAlerts.CategoryText(cat) return CAT_TEXT[cat] or tostring(cat or "?") end
local SEV_TEXT = { low = L["Low: log only"], med = L["Medium: alert"], high = L["High: alert with a sound"] }
function ModAlerts.SeverityText(sev) return SEV_TEXT[sev] or tostring(sev or "?") end

----------------------------------------------------------------------
-- Self-tests (pure logic only)
----------------------------------------------------------------------
function ModAlerts:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    local M = ModAlerts
    local function hit(rules, line)
        local folded, words = M.Prepare(line)
        local c = M.Match(M.Compile(rules, "enUS"), folded, words, nil, 0)
        return c and c.p
    end

    S:Register("modalerts.accents_and_case", function()
        local rules = { { p = "otário", cat = "offense", sev = "med" } }
        if hit(rules, "que OTARIO esse cara") ~= "otário" then return false, "unaccented, upper case" end
        if hit(rules, "Otário!") ~= "otário" then return false, "accented, punctuation" end
        return true
    end)

    S:Register("modalerts.whole_word", function()
        local rules = { { p = "gold", cat = "trade", sev = "high" }, { p = "buy gold", cat = "trade", sev = "high" } }
        if hit(rules, "goldshire anyone?") then return false, "part of a word" end
        if hit(rules, "who wants to BUY-gold?") ~= "buy gold" and hit(rules, "who wants to BUY-gold?") ~= "gold" then
            return false, "phrase across punctuation"
        end
        if hit(rules, "look at |cff1eff00|Hitem:1:0|h[Gold Ring]|h|r") ~= "gold" then return false, "a link's text reads" end
        return true
    end)

    S:Register("modalerts.lua_pattern_guarded", function()
        if M.CleanRule({ p = "[a", cat = "custom", sev = "med", lua = true }) then return false, "invalid kept" end
        if M.CleanRule({ p = "a%", cat = "custom", sev = "med", lua = true }) then return false, "trailing % kept" end
        if M.CleanRule({ p = ".*", cat = "custom", sev = "med", lua = true }) then return false, "matches everything" end
        if M.CleanRule({ p = string.rep("a", 61), cat = "custom", sev = "med" }) then return false, "too long" end
        local c = M.Compile({ { p = "%d%d%dg", cat = "trade", sev = "high", lua = true } }, "enUS")
        local folded, words = M.Prepare("500g for 10k")
        if not M.Match(c, folded, words, nil, 0) then return false, "pattern" end
        c[1].pat = "[x"   -- broken after the fact: run under pcall, then never again
        if M.Match(c, folded, words, nil, 0) or not c[1].broken then return false, "pcall" end
        return true
    end)
end
