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
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
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
-- Banter is common and seldom a matter for an officer: offence only logs; poaching alerts (audit B2).
local DEFAULT_SEV = { offense = "low", trade = "high", link = "med", poaching = "med", custom = "med" }
local SEV_RANK = { low = 1, med = 2, high = 3 }
local CAT_SET = {}
for _, c in ipairs(ModAlerts.CATEGORIES) do CAT_SET[c] = true end
local STAMP_FUTURE_SLACK = 300

-- Chinese has no spaces and Korean glues a particle to a word: there a word in their script is any
-- stretch of the line, as Mentions does (issue #106).

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
-- Cyrillic capitals fold too (А-П, Р-Я, Ё): a ruRU guild's words have case as well.
local function cyrillic(b1, b2)
    local c = b2:byte()
    if b1 == "\208" and c >= 144 and c <= 159 then return "\208" .. string.char(c + 32) end
    if b1 == "\208" and c >= 160 and c <= 175 then return "\209" .. string.char(c - 32) end
    if b1 == "\208" and c == 129 then return "\209\145" end
    return b1 .. b2
end
-- The accents and the Cyrillic capitals alone, leaving ASCII as it is: what a Lua pattern gets, since
-- lowering it would turn "%A" into "%a".
function ModAlerts.FoldWide(s)
    return (tostring(s or ""):gsub("\195[\128-\191]", FOLD):gsub("(\208)([\128-\191])", cyrillic))
end
function ModAlerts.Fold(s)
    return ModAlerts.FoldWide(tostring(s or ""):lower())
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
-- Lua's matcher backtracks: two unbounded repetitions (".-.-", ".*%d+") take exponential time on an
-- ordinary line, and one officer's rule would freeze every officer's client on every /g line. One is
-- allowed (quadratic on a 255-byte line, nothing). Counted with the escapes and the [sets] taken out.
function ModAlerts.Repetitions(p)
    local bare = p:gsub("%%.", "x"):gsub("%[.-%]", "x")
    local _, n = bare:gsub("[%*%+%-]", "")
    return n
end
function ModAlerts.CheckLuaPattern(p)
    if ModAlerts.Repetitions(p) > 1 then return "slow" end
    -- Matching runs on the folded line (lower case, no accents): an ASCII capital outside an escape could
    -- never match. Accents and Cyrillic are folded in the pattern itself (FoldWide).
    if p:gsub("%%.", ""):find("%u") then return "case" end
    for _, probe in ipairs(PROBES) do
        local ok, hit = pcall(string.find, probe, p)
        if not ok then return "invalid" end
        -- Whatever matches these matches nearly every line ("." or "%a" or ".+").
        if hit and probe ~= "%" then return "broad" end
    end
    -- A trailing lone % is malformed but only fails on a subject that reaches it.
    local tail = p:match("(%%+)$")
    if tail and #tail % 2 == 1 then return "invalid" end
    return nil
end

-- Plain-language ways to write a rule, for officers who never wrote a Lua pattern: each turns the text
-- typed into the rule that would otherwise be written by hand. "word" is a whole word (no pattern), "part"
-- the text anywhere, even inside a longer word, "spaced" the letters with a space or a symbol allowed
-- between them ("g.o.l.d", "g o l d"), "lua" the pattern as typed.
ModAlerts.MODES = { "word", "part", "spaced", "lua" }
local MAGIC = "([%^%$%(%)%%%.%[%]%*%+%-%?])"
function ModAlerts.Escape(s) return (tostring(s or ""):gsub(MAGIC, "%%%1")) end
-- The rule's pattern, whether it is a Lua pattern, and its kind (kept so the list can read it back).
function ModAlerts.FromMode(mode, text)
    text = strtrim(tostring(text or ""))
    if mode == "part" then return ModAlerts.Escape(ModAlerts.Fold(text)), true, "part" end
    if mode == "spaced" then
        local bare = ModAlerts.Fold(text):gsub("[%s%p]+", "")
        -- A letter of more than one byte cannot be split from its neighbours byte by byte.
        if bare:find("[\128-\255]") or #bare < 2 then return ModAlerts.Escape(ModAlerts.Fold(text)), true, "part" end
        local parts = {}
        for ch in bare:gmatch(".") do parts[#parts + 1] = ch end
        return table.concat(parts, "%W?"), true, "spaced"
    end
    if mode == "lua" then return text, true, nil end
    return text, false, nil
end

-- Ready-made patterns, in words: what an officer most often wants to catch.
ModAlerts.TEMPLATES = {
    { id = "gold",    p = "%d%d%d+ ?g",       text = L["A price in gold (500g, 1000 g)"] },
    { id = "www",     p = "www%.",            text = L["A website address (www.)"] },
    { id = "com",     p = "%a%.com",          text = L["A .com address"] },
    { id = "discord", p = "discord%.gg",      text = L["A Discord invite"] },
    { id = "number",  p = "%d%d%d%d%d%d%d%d", text = L["A long number (8 digits or more)"] },
}

-- How the list shows a rule: the text an officer would recognise, and how it matches (nil: a whole word).
function ModAlerts.Describe(r)
    if r.k == "part" then return (r.p:gsub("%%(.)", "%1")), L["inside other words too"] end
    if r.k == "spaced" then return (r.p:gsub("%%W%?", "")), L["even spaced or with symbols"] end
    if r.lua then
        for _, t in ipairs(ModAlerts.TEMPLATES) do
            if t.p == r.p then return t.text, L["ready-made"] end
        end
        return r.p, L["Lua pattern"]
    end
    return r.p, nil
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
    local kind = isLua and (r.k == "part" or r.k == "spaced") and r.k or nil
    return { p = p, cat = r.cat, sev = r.sev, lua = isLua or nil, k = kind }
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

-- The list before the officers chose one, in this client's language. No default link words: a link is the
-- anti-flood's (3 in 120 s), or one link would raise two alerts (audit B1).
function ModAlerts.DefaultRules()
    local words = {
        offense = L["idiot, moron, stupid, imbecile"],
        trade = L["buy gold, sell gold, cheap gold, gold for sale, selling boost, wts boost"],
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
-- " word " (or the bare folded text where a word has no edges: CJK and Hangul, by the word's own script).
-- Pure on `rules`.
function ModAlerts.Compile(rules)
    local out = {}
    for i, r in ipairs(rules or {}) do
        local c = { key = ModAlerts.RuleKey(r), cat = r.cat, sev = r.sev, p = r.p, order = i }
        if r.lua then
            c.pat = ModAlerts.FoldWide(r.p)
        else
            local folded = ModAlerts.Fold(r.p)
            -- A word in a script with no spaces between words (CJK, Hangul) has no edges, whatever language
            -- the client that reads it speaks.
            if folded:find("[\227-\237]") then
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
                local ok, at = pcall(string.find, folded:sub(1, 255), c.pat)
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
function ModAlerts:AddRule(p, cat, sev, isLua, kind)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local r, why = self.CleanRule({ p = p, cat = cat, sev = sev, lua = isLua and true or nil, k = kind })
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

-- An officer changes the severity of the rule at `index` of GetRules() (audit B5). True, or false and why
-- ("officer", "missing", "severity").
function ModAlerts:SetRuleSeverity(index, sev)
    if not GuildOS:IsOfficer() then return false, "officer" end
    if not SEV_RANK[sev] then return false, "severity" end
    local rules = self:GetRules()
    if not rules[index] then return false, "missing" end
    rules[index].sev = sev
    saveRules(self, rules)
    return true
end

-- The severity after `sev`, round: low, medium, high, low. What a click on a rule's severity sets.
function ModAlerts.NextSeverity(sev)
    local i = SEV_RANK[sev] or 0
    return ModAlerts.SEVERITIES[i % #ModAlerts.SEVERITIES + 1]
end

-- One list for every officer (audit B5): until an officer chooses one, each matches the defaults of their own
-- language. The first save of anything on the Alert rules tab (a rule, the anti-flood's limits, the newcomers')
-- stamps this officer's defaults as the guild's list, so every officer matches the same one from then on.
function ModAlerts:SeedShared()
    if self:IsCustomList() or not GuildOS:IsOfficer() then return false end
    saveRules(self, self:GetRules())
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
    if GuildOS.ModFlood then GuildOS.ModFlood:PublishConfig() end   -- and the anti-flood's limits (#405)
    if GuildOS.Newcomer then GuildOS.Newcomer:PublishConfig() end   -- and the newcomer's quarantine (#406)
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
    self:_SetupCatchUp()
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
    self:_Check(msg, author, GetServerTime())
end

-- One line through the rules and the anti-flood, at the time it was said. `context`: the lines before it,
-- when they are not in this client's own /g log (a line from the server's history, #411).
function ModAlerts:_Check(msg, author, now, context)
    local folded, words = self.Prepare(msg)
    local rule = self.Match(self.compiled or {}, folded, words, self.mutes, now)
    if rule and self:_FromWatched(author) then self:_Flag(msg, author, rule, now, context) end
    -- The anti-flood (#405) reads the same line, here, after the same checks.
    if GuildOS.ModFlood and GuildOS.ModFlood.OnLine then GuildOS.ModFlood:OnLine(msg, author, now, folded) end
end

----------------------------------------------------------------------
-- What was said while this officer was away (#411)
--
-- Where the server keeps the guild's chat (Forever, retail: Compat.GuildChatHistory), an officer's login
-- reads the /g lines said since this character was last seen online (at most 24 hours and 300 lines),
-- through the same rules and the same anti-flood, each at the time it was said. Their alerts go only into
-- the panel, marked "while you were away": no window, no sound, no claim on the wire (the officers who were
-- online then already had theirs). TBC Anniversary keeps no such history: nothing happens there. Only the
-- time last seen is stored, per character; the lines stay in memory as #404's do.
----------------------------------------------------------------------
ModAlerts.AWAY_MAX_LINES = 300
ModAlerts.AWAY_MAX_SECS = 24 * 3600
ModAlerts.AWAY_RETRIES = 5

local function seenKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) or "?"
end

-- The time this character was last seen online, or nil.
function ModAlerts:SeenAt()
    local s = GuildOS.db.modSeen
    return type(s) == "table" and GuildOS.Finite(s[seenKey()]) or nil
end

function ModAlerts:MarkSeen(now)
    GuildOS.db.modSeen = type(GuildOS.db.modSeen) == "table" and GuildOS.db.modSeen or {}
    GuildOS.db.modSeen[seenKey()] = math.floor(now or GetServerTime())
end

-- The lines of `history` (the server's, oldest or newest first) said after `since` and up to `upTo`, oldest
-- first, at most AWAY_MAX_LINES (the newest of them), each with the lines before it as its context. Pure.
function ModAlerts.AwayLines(history, since, upTo)
    local sorted = {}
    for _, e in ipairs(type(history) == "table" and history or {}) do
        local t = type(e) == "table" and GuildOS.Finite(e.t)
        if t and type(e.m) == "string" and type(e.n) == "string" then sorted[#sorted + 1] = e end
    end
    table.sort(sorted, function(a, b) return a.t < b.t end)
    local out = {}
    for i, e in ipairs(sorted) do
        if e.t > since and e.t <= upTo then
            local ctx = {}
            for j = math.max(1, i - ModAlerts.CONTEXT), i - 1 do ctx[#ctx + 1] = { n = sorted[j].n, m = sorted[j].m } end
            out[#out + 1] = { t = e.t, n = e.n, m = e.m, context = ctx }
        end
    end
    while #out > ModAlerts.AWAY_MAX_LINES do table.remove(out, 1) end
    return out
end

ModAlerts.AWAY_FEED_MAX = 30   -- alerts a catch-up may add: the panel keeps room for the live ones

-- The catch-up itself, on its own anti-flood state (old and live lines never mix in a window or a surge).
-- Returns how many lines were read and whether the server's history reached back far enough; or nil and why
-- ("member", "off", "none", "locked").
function ModAlerts:CatchUp(loginAt)
    if not GuildOS:IsOfficer() then return nil, "member" end
    if not self:Prefs().enabled then return nil, "off" end
    if not GuildOS.Compat.GuildChatHistory then return nil, "none" end
    local history, why = GuildOS.Compat.GuildChatHistory(self.AWAY_MAX_LINES)
    if why == "locked" then return nil, "locked" end
    if type(history) ~= "table" then return nil, "none" end
    loginAt = loginAt or GetServerTime()
    local since = math.max(self:SeenAt() or 0, loginAt - self.AWAY_MAX_SECS)
    local oldest
    for _, e in ipairs(history) do
        local t = type(e) == "table" and GuildOS.Finite(e.t)
        if t and (not oldest or t < oldest) then oldest = t end
    end
    -- The client holds only what it was sent: reaching back is the oldest held at or before `since`, or as
    -- many lines as the catch-up reads at most.
    local complete = (oldest ~= nil and oldest <= since) or #history >= self.AWAY_MAX_LINES
    local lines = self.AwayLines(history, since, loginAt)
    local F = GuildOS.ModFlood
    local live
    if F then
        live = { F.speakers, F.surges, F.speakerCount, F.lastPrune }
        F.speakers, F.surges, F.speakerCount, F.lastPrune = {}, {}, 0, nil
    end
    self.catchingUp, self.awaySeen, self.awayAdded = true, {}, 0
    local ok = GuildOS:SafeCall(function()
        for _, l in ipairs(lines) do
            if not GuildOS.Compat.IsSecret(l.m, l.n) then self:_Check(l.m, l.n, l.t, l.context) end
        end
    end)
    self.catchingUp, self.awaySeen = false, nil
    if F then F.speakers, F.surges, F.speakerCount, F.lastPrune = live[1], live[2], live[3], live[4] end
    self:Refresh()
    return ok and #lines or 0, complete
end

-- On an officer's login (or at once when the module starts after it, a late guild name): a little after the
-- world loads, a few tries — in a chat lockdown, and asking the server for older lines while what it sent does
-- not reach back. The time seen moves only once a catch-up really ran: a logout, a reload or a lockdown that
-- outlasts the tries before then keeps the old time, and the next login covers the gap.
function ModAlerts:_SetupCatchUp()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_ENTERING_WORLD")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_LOGOUT")
    local started = false
    local function start()
        if started then return end
        started = true
        local loginAt = GetServerTime()
        local tries = 0
        local function done()
            ModAlerts.caughtUp = true
            ModAlerts:MarkSeen(loginAt)
            GuildOS.Compat.NewTicker(60, function()
                GuildOS:SafeCall(function() if ModAlerts.caughtUp then ModAlerts:MarkSeen() end end)
            end)
        end
        local function attempt()
            tries = tries + 1
            local n, flag = ModAlerts:CatchUp(loginAt)
            if n == nil and flag ~= "locked" then return done() end    -- member, off, no history: nothing to cover
            local last = tries >= ModAlerts.AWAY_RETRIES
            if n == nil then                                            -- locked: try later; never mark seen
                if not last then GuildOS.Compat.After(30, function() GuildOS:SafeCall(attempt) end) end
                return
            end
            if flag or last then return done() end                      -- reached back, or the server has no more
            if GuildOS.Compat.RequestOlderGuildChat then GuildOS.Compat.RequestOlderGuildChat(ModAlerts.AWAY_MAX_LINES) end
            ModAlerts:_ForgetAway()                                     -- read again whole once the older lines came
            GuildOS.Compat.After(10, function() GuildOS:SafeCall(attempt) end)
        end
        GuildOS.Compat.After(15, function() GuildOS:SafeCall(attempt) end)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGOUT" then
            GuildOS:SafeCall(function() if ModAlerts.caughtUp then ModAlerts:MarkSeen() end end)
            return
        end
        start()
    end)
    -- Started after the world already loaded (the modules wait for a late guild name): at once.
    if IsLoggedIn and IsLoggedIn() then start() end
end

-- Drops the away alerts of a partial read, before it is read again with the older lines.
function ModAlerts:_ForgetAway()
    for i = #self.feed, 1, -1 do
        if self.feed[i].away then table.remove(self.feed, i) end
    end
end

-- A new alert from a rule.
function ModAlerts:_Flag(msg, author, rule, now, context)
    local log = GuildOS.GuildChat and GuildOS.GuildChat:Log() or nil
    self:Deliver({
        kind = "subject", who = shortName(author), key = GuildOS:KeyOfRosterName(author),
        line = GuildOS:CutBytes((tostring(msg):gsub("%c", " ")), 255),
        context = context or self.Context(log, msg, self.CONTEXT), cat = rule.cat, sev = rule.sev, rule = rule.key,
        claim = self.ClaimKey(author, msg),
        newcomer = GuildOS.Newcomer and GuildOS.Newcomer:Of(author, now) or nil,   -- the badge (#406)
    }, now)
end

-- Into the panel, and for medium and high onto this officer's screen unless another officer claimed it.
-- `a.claim` is the line's (or the surge's) claim key. Also used by the anti-flood (#405).
function ModAlerts:Deliver(a, now)
    now = now or GetServerTime()
    local clock = GetServerTime()
    self:_PruneClaims(clock)
    local held = self.claims[a.claim]
    -- Already alerted (or about to be) on this client for the same line: never twice.
    if (held and held.mine) or self.pending[a.claim] then return end
    if self.catchingUp then
        if self.awaySeen[a.claim] or self.awayAdded >= self.AWAY_FEED_MAX then return end
        self.awaySeen[a.claim], self.awayAdded = true, self.awayAdded + 1
    end
    self.nextId = self.nextId + 1
    -- `at` is when it was alerted (what the panel keeps it by), `said` when the line was said.
    a.id, a.at, a.said, a.state = self.nextId, clock, now, "new"
    -- Older than any live alert: an away one goes below them.
    if self.catchingUp then self.feed[#self.feed + 1] = a else table.insert(self.feed, 1, a) end
    self:_PruneFeed(GetServerTime())
    -- Said while this officer was away (#411): into the panel only, no window, no sound, no claim; one per line
    -- (a spammer's repeats are one alert), at most AWAY_FEED_MAX, and drawn once at the end.
    if self.catchingUp then
        a.away = true
        return
    end
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
        -- In combat or an instance: the panel only, and unclaimed, so an officer out of it gets the window.
        if self:InFight() then return self:_Hold(a) end
        self:_Claim(a.claim)
        self:_Show(a)
    end)
end

----------------------------------------------------------------------
-- In combat or an instance (audit B4): an alert goes to the panel only, with no window over the raid frames
-- and no raid-warning sound, and one chat line sums them up once combat ends.
----------------------------------------------------------------------
function ModAlerts:InFight()
    if GuildOS:InCombat() then return true end
    if IsInInstance and IsInInstance() then return true end
    return false
end

function ModAlerts:_Hold(a)
    a.held = true
    self.heldCount = (self.heldCount or 0) + 1
    if not self.fightFrame then
        local f = CreateFrame("Frame")
        self.fightFrame = f
        GuildOS.Compat.RegisterEvent(f, "PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function() GuildOS:SafeCall(ModAlerts.FightEnded, ModAlerts) end)
    end
    self:Refresh()
end

-- Combat ended: one line for what was held, never a window. Returns how many it summed up.
function ModAlerts:FightEnded()
    local n = self.heldCount or 0
    if n == 0 or GuildOS:InCombat() then return 0 end
    self.heldCount = 0
    GuildOS:Print(string.format(L["%d chat alert(s) during combat: see Leadership > Chat alerts."], n))
    return n
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
    self:_PruneClaims(GetServerTime())
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
    -- Two hours old, any alert goes. Past the cap the oldest go, but never the one the window shows now (its
    -- buttons find it by id).
    for i = #self.feed, 1, -1 do
        local e = self.feed[i]
        if e.at < cut then table.remove(self.feed, i) end
    end
    for i = #self.feed, 1, -1 do
        if #self.feed <= self.FEED_MAX then break end
        if self.feed[i] ~= self.onScreen then table.remove(self.feed, i) end
    end
end

-- The alert's window, through the one popup queue (audit B21): never two at once, never in combat.
function ModAlerts:_Show(a)
    a.shown = true
    self.onScreen = a
    GuildOS:ShowWhenClear("modalert", function()
        if a.state ~= "new" then return nil end   -- acted on from the panel while it waited
        if a.sev == "high" and self:Prefs().sound and PlaySound then
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
        end
        if GuildOS.ShowModAlert then GuildOS:ShowModAlert(a) end
        return GuildOS.modAlertFrame
    end)
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

-- An alert that grew (a surge's new line, #405): the window showing it redraws.
function ModAlerts:Touch(a)
    if self.popupUpdate then GuildOS:SafeCall(self.popupUpdate, a) end
    self:Refresh()
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
