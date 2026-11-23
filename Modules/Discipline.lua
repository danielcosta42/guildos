----------------------------------------------------------------------
-- Guild OS - The disciplinary record (issue #402, the site's specs/116)
--
-- One record per member of every warning given in the game: why, by whom, when, the chat line that
-- led to it (if any) and the step of the guild's ladder it reached. Officers only: kept, shown and
-- synced among them (domain "discipline", officer-authoritative). A member's client drops every
-- packet of it and never stores a line.
--
-- The guild's TERM (days after which a warning stops counting, default 30, 1..365) and its LADDER
-- (what each step suggests: nothing, the punishment rank, a temporary ban) are the officers', kept on
-- every client the way the trial length is (guildcfg, newest stamp wins, issue #249). A warning's end
-- is never stored: it is its `at` plus the guild's term, worked out every time, so a change of term
-- moves every warning, up or down.
--
-- Revoking writes `revokedAt`; nothing is ever deleted by hand. Between two copies of one warning the
-- newer `changedAt` wins, and on a tie the revoked one (`Newer`): the order copies arrive in never
-- decides whether a warning stands. The site reads the same rule (specs/116).
--
-- Warnings given on Discord come down in the GOSGILD1 (`discordWarnings`, the site's): shown on the
-- record, marked, counted toward the step, and never written into this one.
--
-- Nothing here punishes anybody: a step only suggests (issue #403 asks the officer to confirm).
----------------------------------------------------------------------
local Discipline = {}
GuildOS.Discipline = Discipline
local L = GuildOS.L

Discipline.REASONS = { "language", "spam", "trade", "poaching", "conduct", "raid", "other" }
Discipline.DEFAULT_TERM = 30
Discipline.MIN_TERM, Discipline.MAX_TERM = 1, 365
Discipline.NOTE_MAX = 200          -- bytes, as the site's door takes it
Discipline.EXCERPT_MAX = 255       -- bytes: one line of the game's chat
Discipline.EXCERPT_TTL = 90 * 86400   -- a flagged line is personal data: it goes at 90 days
Discipline.KEEP = 400 * 86400      -- a warning is forgotten past the longest term and a margin
Discipline.EXPORT_MAX = 500        -- what the site reads from one upload
Discipline.BATCH = 20              -- warnings per sync envelope
-- The guild's ladder before any officer chose one: a warning, a final warning, then the suggestions.
Discipline.DEFAULT_LADDER = {
    { action = "none" }, { action = "none" }, { action = "rank" }, { action = "tempban", days = 7 },
}
Discipline.ACTIONS = { none = true, rank = true, tempban = true }
local LADDER_MAX = 10
local STAMP_FUTURE_SLACK = 300
local CLOCK_MAX = 4294967295   -- the site's ceiling on a time (2^32 - 1)
local whole

local REASON_SET = {}
for _, r in ipairs(Discipline.REASONS) do REASON_SET[r] = true end

local function settings() return GuildOS.db and GuildOS.db.settings end
local function store()
    GuildOS.db.discipline = GuildOS.db.discipline or {}
    GuildOS.db.discipline.warnings = GuildOS.db.discipline.warnings or {}
    return GuildOS.db.discipline.warnings
end

function Discipline:Initialize()
    store()
    if GuildOS.SyncService then
        GuildOS.SyncService:On("discipline", function(env, sender) Discipline:OnSync(env, sender) end)
    end
    self:_RegisterTests()
    self:Prune()
end

----------------------------------------------------------------------
-- Pure helpers (deterministic; unit-tested via /gos selftest and tools/discipline.lua)
----------------------------------------------------------------------
-- A whole number of days of term, or nil: 1 to 365, a number or digits typed in a box. Anything else is
-- refused as it is, never clamped.
function Discipline.ValidTerm(v)
    if type(v) == "string" then
        if not v:match("^%s*%d+%s*$") then return nil end
        v = tonumber(v)
    end
    if type(v) ~= "number" or v ~= v or v ~= math.floor(v) then return nil end
    if v < Discipline.MIN_TERM or v > Discipline.MAX_TERM then return nil end
    return v
end

-- Whether copy `a` of a warning beats copy `b`: the newer change, and on a tie the revoked one.
function Discipline.Newer(a, b)
    local ca, cb = tonumber(a.changedAt) or 0, tonumber(b.changedAt) or 0
    if ca ~= cb then return ca > cb end
    return a.revokedAt ~= nil and b.revokedAt == nil
end

-- Whether a warning still counts at `now`: standing and inside the term.
function Discipline.Active(w, termDays, now)
    return w.revokedAt == nil and now < (w.at or 0) + termDays * 86400
end

-- The step: how many of `list` still count.
function Discipline.Step(list, termDays, now)
    local n = 0
    for _, w in ipairs(list) do
        if Discipline.Active(w, termDays, now) then n = n + 1 end
    end
    return n
end

-- What the guild's ladder suggests at step `n` (1-based); past its end, its last rung.
function Discipline.RungFor(ladder, n)
    if n < 1 or #ladder == 0 then return nil end
    return ladder[math.min(n, #ladder)]
end

-- A ladder off the network or a box, or nil: 1 to 10 rungs, each a known action, a ban with 1..365 days.
function Discipline.ValidLadder(t)
    if type(t) ~= "table" or #t < 1 or #t > LADDER_MAX then return nil end
    local out = {}
    for i = 1, #t do
        local r = t[i]
        if type(r) ~= "table" or type(r.action) ~= "string" or not Discipline.ACTIONS[r.action] then return nil end
        if r.action == "tempban" then
            local d = Discipline.ValidTerm(r.days)
            if not d then return nil end
            out[i] = { action = "tempban", days = d }
        else
            out[i] = { action = r.action }
        end
    end
    return out
end

-- A warning off the network, cleaned, or nil. The same rules as the site's door (specs/116): an id of
-- [A-Za-z0-9:_-], never "d:" (Discord's), a known reason, times that agree with each other.
function Discipline.Clean(w)
    if type(w) ~= "table" then return nil end
    local id = w.id
    if type(id) ~= "string" or #id > 40 or not id:match("^[%w:_%-]+$") or id:find("^d:") then return nil end
    if type(w.subject) ~= "string" or w.subject == "" or #w.subject > 48 or w.subject:find("|", 1, true) then return nil end
    if type(w.by) ~= "string" or w.by == "" or #w.by > 48 or w.by:find("|", 1, true) then return nil end
    if type(w.reason) ~= "string" or not REASON_SET[w.reason] then return nil end
    local at, changedAt, level = whole(w.at), whole(w.changedAt), whole(w.level)
    if not (at and at >= 1 and changedAt and changedAt >= at and level and level >= 1 and level <= 10) then return nil end
    -- No time past this client's clock and a few minutes: a warning from the future would count forever.
    local ceiling = math.min(CLOCK_MAX, GetServerTime() + STAMP_FUTURE_SLACK)
    if changedAt > ceiling then return nil end
    local revokedAt = w.revokedAt ~= nil and whole(w.revokedAt) or nil
    if w.revokedAt ~= nil and not (revokedAt and revokedAt >= at and changedAt >= revokedAt) then return nil end
    local out = {
        id = id, subject = w.subject, by = w.by, reason = w.reason,
        at = at, changedAt = changedAt, level = level,
    }
    if type(w.note) == "string" then
        local note = GuildOS:SanitizeUserText(w.note, Discipline.NOTE_MAX)
        if note ~= "" then out.note = note end
    end
    if type(w.excerpt) == "string" then out.excerpt = Discipline.Excerpt(w.excerpt) end
    if revokedAt then
        out.revokedAt = revokedAt
        if type(w.revokedBy) == "string" and w.revokedBy ~= "" and #w.revokedBy <= 48 and not w.revokedBy:find("|", 1, true) then
            out.revokedBy = w.revokedBy
        end
    end
    return out
end

-- A reason as the officer reads it.
local REASON_TEXT = {
    language = L["Offensive language"], spam = L["Spam"], trade = L["Gold / boost selling"], poaching = L["Poaching"],
    conduct = L["Conduct"], raid = L["Raid conduct"], other = L["Other"],
}
function Discipline.ReasonText(reason)
    return REASON_TEXT[reason] or tostring(reason or "?")
end

-- A whole number off the network, or nil.
whole = function(v)
    local n = GuildOS.Finite(v)
    return n and math.floor(n) or nil
end

-- A chat line as the record keeps it: the game's own links kept, one line, at most 255 bytes, never blank.
function Discipline.Excerpt(text)
    local s = GuildOS:CutBytes((tostring(text or ""):gsub("%c", " ")), Discipline.EXCERPT_MAX)
    if strtrim(s) == "" then return nil end
    return s
end

-- A new id: made on the officer's client, unique enough in a guild, within the site's 40 characters.
function Discipline.NewId(now)
    return string.format("g%d-%04X%04X", now, math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

-- Folds `w` into `s` (a table by id). Whether it changed anything. A chat line never travels (OnTheWire),
-- so the one this client holds stays with a newer copy of the same warning.
function Discipline.Merge(s, w)
    local held = s[w.id]
    if held and not Discipline.Newer(w, held) then return false end
    if held and held.excerpt and not w.excerpt then w.excerpt = held.excerpt end
    s[w.id] = w
    return true
end

----------------------------------------------------------------------
-- The guild's term and ladder
----------------------------------------------------------------------
function Discipline:GetTerm()
    local s = settings()
    return (s and self.ValidTerm(s.disciplineTerm)) or self.DEFAULT_TERM
end

function Discipline:GetLadder()
    local s = settings()
    return (s and self.ValidLadder(s.disciplineLadder)) or self.DEFAULT_LADDER
end

-- A stamp that only moves forward past the one held (as TrialTracker's).
local function stamp(s, field)
    s[field] = math.max(GetServerTime(), (s[field] or 0) + 1)
end

-- An officer sets the term. Whether it was taken, and when not why: "officer" or "range".
function Discipline:SetTerm(v)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local days = self.ValidTerm(v)
    if not days then return false, "range" end
    local s = settings()
    s.disciplineTerm = days
    stamp(s, "disciplineTermAt")
    self:PublishConfig()
    self:Refresh()
    return true
end

function Discipline:SetLadder(t)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local ladder = self.ValidLadder(t)
    if not ladder then return false, "range" end
    local s = settings()
    s.disciplineLadder = ladder
    stamp(s, "disciplineLadderAt")
    self:PublishConfig()
    self:Refresh()
    return true
end

-- To the guild when it changes, and again on the officers' regular sync. Only a choice somebody made.
-- Neither payload has `max`: a client before this reads an unknown guildcfg action as the officer
-- threshold, and one with no `max` it ignores.
function Discipline:PublishConfig()
    local s = settings()
    if not (s and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    if s.disciplineTermAt then
        GuildOS.SyncService:Publish("guildcfg", "discterm", { days = self:GetTerm() }, { rev = s.disciplineTermAt })
    end
    if s.disciplineLadderAt then
        GuildOS.SyncService:Publish("guildcfg", "discladder", { ladder = self:GetLadder() }, { rev = s.disciplineLadderAt })
    end
    if s.disciplineTemplatesAt then
        local t = type(s.disciplineTemplates) == "table" and s.disciplineTemplates or {}
        GuildOS.SyncService:Publish("guildcfg", "disctpl", { warning = t.warning, final = t.final, punish = t.punish }, { rev = s.disciplineTemplatesAt })
    end
    if s.disciplineRankAt then
        GuildOS.SyncService:Publish("guildcfg", "discrank", { rank = s.disciplineRank or false }, { rev = s.disciplineRankAt })
    end
end

local function stampOf(env)
    local at = GuildOS.Finite(env.rev)
    if not (at and at > 0) then return nil end
    return math.min(at, GetServerTime() + STAMP_FUTURE_SLACK)
end

-- From an officer (SyncService checked the officer and GUILD): the newest stamp wins. Two in the same
-- second settle on the shorter term, and on the ladder that sorts first, on every client alike.
function Discipline:OnConfigSync(env)
    local data = type(env) == "table" and env.data
    local s = settings()
    if type(data) ~= "table" or not s then return end
    local at = stampOf(env)
    if not at then return end
    if env.act == "discterm" then
        local days = self.ValidTerm(data.days)
        if not days then return end
        local held = s.disciplineTermAt
        if held and (at < held or (at == held and days >= self:GetTerm())) then return end
        s.disciplineTerm, s.disciplineTermAt = days, at
    elseif env.act == "discladder" then
        local ladder = self.ValidLadder(data.ladder)
        if not ladder then return end
        local held = s.disciplineLadderAt
        if held and (at < held or (at == held and self.LadderKey(ladder) >= self.LadderKey(self:GetLadder()))) then return end
        s.disciplineLadder, s.disciplineLadderAt = ladder, at
    elseif env.act == "disctpl" then
        -- Newest stamp wins; the same second keeps what is held (a tie has no shorter side).
        if s.disciplineTemplatesAt and at <= s.disciplineTemplatesAt then return end
        local t = {}
        for _, k in ipairs(self.TEMPLATE_KEYS) do t[k] = self.CleanTemplate(data[k]) end
        s.disciplineTemplates, s.disciplineTemplatesAt = t, at
    elseif env.act == "discrank" then
        if s.disciplineRankAt and at <= s.disciplineRankAt then return end
        local r = type(data.rank) == "string" and GuildOS:SanitizeUserText(data.rank, 48) or ""
        s.disciplineRank, s.disciplineRankAt = r ~= "" and r or nil, at
    else
        return
    end
    self:Refresh()
end

-- A ladder as one string, for the tie between two chosen in the same second.
function Discipline.LadderKey(ladder)
    local parts = {}
    for i, r in ipairs(ladder) do parts[i] = r.action .. (r.days and (":" .. r.days) or "") end
    return table.concat(parts, ",")
end

----------------------------------------------------------------------
-- The record
----------------------------------------------------------------------
-- The warnings Discord sent down (CompanionImport), by id, in memory: never stored, never synced.
function Discipline:DiscordWarnings()
    local Import = GuildOS.CompanionImport
    local list = Import and Import.DiscordWarnings and Import:DiscordWarnings() or nil
    return list or {}
end

-- One member's record, newest first: every warning filed under any character of their account group
-- (GetLinkedChars), from the game and from Discord. Each row a copy, with `discord = true` on Discord's.
function Discipline:Record(playerKey, s, discord)
    s = s or store()
    local group = {}
    for _, k in ipairs(GuildOS:GetLinkedChars(playerKey)) do group[k] = true end
    local out = {}
    for _, w in pairs(s) do
        if group[w.subject] then
            local row = {}
            for f, v in pairs(w) do row[f] = v end
            out[#out + 1] = row
        end
    end
    for _, w in ipairs(discord or self:DiscordWarnings()) do
        if group[w.subject] then
            local row = { discord = true }
            for f, v in pairs(w) do row[f] = v end
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return out
end

-- The step a member is on now.
function Discipline:StepOf(playerKey, now)
    return self.Step(self:Record(playerKey), self:GetTerm(), now or GetServerTime())
end

-- An officer gives a warning: filed, synced, and on the record. `opts`: note, excerpt. The new warning,
-- or nil and why ("officer", "who", "reason").
function Discipline:Add(playerKey, reason, opts)
    if not GuildOS:IsOfficer() then return nil, "officer" end
    if type(playerKey) ~= "string" or playerKey == "" then return nil, "who" end
    if not REASON_SET[reason] then return nil, "reason" end
    opts = opts or {}
    local now = GetServerTime()
    local w = {
        id = self.NewId(now), subject = playerKey, by = GuildOS.Compat.PlayerName(), reason = reason,
        at = now, changedAt = now, level = math.min(10, self:StepOf(playerKey, now) + 1),
    }
    local note = opts.note and GuildOS:SanitizeUserText(opts.note, self.NOTE_MAX) or ""
    if note ~= "" then w.note = note end
    if type(opts.excerpt) == "string" then w.excerpt = self.Excerpt(opts.excerpt) end
    local clean = self.Clean(w)
    if not clean then return nil, "who" end
    store()[clean.id] = clean
    self:_Publish({ clean })
    self:Refresh()
    return clean
end

-- An officer revokes a warning given in the game. Whether it was (false: none standing by that id).
function Discipline:Revoke(id)
    if not GuildOS:IsOfficer() then return false end
    local s = store()
    local held = s[id]
    if not held or held.revokedAt then return false end
    local now = math.max(GetServerTime(), held.changedAt or 0)
    local w = {}
    for f, v in pairs(held) do w[f] = v end
    w.revokedAt, w.revokedBy, w.changedAt = now, GuildOS.Compat.PlayerName(), now
    s[id] = w
    self:_Publish({ w })
    self:Refresh()
    return true
end

-- Drops what is past keeping: a flagged line at 90 days, a warning at 400. The number dropped.
function Discipline:Prune(now, s)
    s = s or (GuildOS.db and GuildOS.db.discipline and GuildOS.db.discipline.warnings)
    if not s then return 0 end
    now = now or GetServerTime()
    local dropped = 0
    for id, w in pairs(s) do
        if (w.changedAt or w.at or 0) < now - self.KEEP then
            s[id] = nil
            dropped = dropped + 1
        elseif w.excerpt and (w.at or 0) < now - self.EXCERPT_TTL then
            w.excerpt = nil
        end
    end
    return dropped
end

----------------------------------------------------------------------
-- Warning somebody with one click (issue #403)
--
-- The officer clicks Warn, picks a reason and one of the guild's templates, and the whisper leaves on that
-- click: a hardware event, so the game allows it. Nothing is ever said in /g about anybody. When the new
-- step's rung asks for something (the punishment rank, a temporary ban) it is only SUGGESTED: a second
-- click confirms it, through the ways that already exist (GuildManager's hand-off to the game's own panel
-- for a rank, ADR-0010; BanList for a ban). Never a protected guild API here.
----------------------------------------------------------------------
Discipline.TEMPLATE_KEYS = { "warning", "final", "punish" }
Discipline.TEMPLATE_MAX = 200     -- bytes an officer may type; filled, the line is cut at 255
Discipline.WHISPER_MAX = 255      -- what SendChatMessage takes

-- The guild's templates before an officer wrote any, in this client's language.
function Discipline.DefaultTemplates()
    return {
        warning = L["{name}, this is a warning from the officers: {reason}. Please keep to the guild's rules."],
        final = L["{name}, this is a final warning: {reason}. The next one has consequences."],
        punish = L["{name}, after repeated warnings ({reason}) the officers are applying the guild's rules."],
    }
end

function Discipline:GetTemplates()
    local s = settings()
    local held = s and type(s.disciplineTemplates) == "table" and s.disciplineTemplates or {}
    local out = self.DefaultTemplates()
    for _, k in ipairs(self.TEMPLATE_KEYS) do
        if type(held[k]) == "string" and held[k] ~= "" then out[k] = held[k] end
    end
    return out
end

-- A template off the network or a box: one line, no game codes, at most 200 bytes; nil when blank.
function Discipline.CleanTemplate(t)
    if type(t) ~= "string" then return nil end
    local s = GuildOS:SanitizeUserText(t, Discipline.TEMPLATE_MAX)
    return s ~= "" and s or nil
end

-- An officer edits one template. Whether it was taken.
function Discipline:SetTemplate(key, text)
    if not GuildOS:IsOfficer() then return false end
    local known = false
    for _, k in ipairs(self.TEMPLATE_KEYS) do known = known or k == key end
    if not known then return false end
    local s = settings()
    s.disciplineTemplates = type(s.disciplineTemplates) == "table" and s.disciplineTemplates or {}
    s.disciplineTemplates[key] = self.CleanTemplate(text)   -- blank: back to the default
    stamp(s, "disciplineTemplatesAt")
    self:PublishConfig()
    return true
end

-- The guild's punishment rank, by name, as the officers set it. Nil until one is.
function Discipline:GetPunishRank()
    local s = settings()
    local r = s and s.disciplineRank
    return type(r) == "string" and r ~= "" and r or nil
end

function Discipline:SetPunishRank(name)
    if not GuildOS:IsOfficer() then return false end
    local s = settings()
    local clean = GuildOS:SanitizeUserText(name or "", 48)
    s.disciplineRank = clean ~= "" and clean or nil
    stamp(s, "disciplineRankAt")
    self:PublishConfig()
    self:Refresh()
    return true
end

-- The template a new warning at `step` starts on: a warning, then a final one, then the punishment.
function Discipline.TemplateFor(step)
    if step <= 1 then return "warning" end
    if step == 2 then return "final" end
    return "punish"
end

-- A template filled in: {name}, {reason}, {step} and {rule} (a guild rule's number and title, #407; "the
-- guild's rules" when the officer named none), one line with no game codes, cut at 255 bytes. Pure.
function Discipline.Fill(template, vars)
    local text = tostring(template or ""):gsub("{(%a+)}", function(k)
        local v = vars[k]
        if k == "rule" and (v == nil or v == "") then v = L["the guild's rules"] end
        if v == nil then return "{" .. k .. "}" end
        return tostring(v)
    end)
    return GuildOS:SanitizeUserText(text, Discipline.WHISPER_MAX)
end

-- What the new step's rung suggests, for the officer to confirm: { action = "rank", rank = name|nil } or
-- { action = "tempban", days = n }; nil when the rung asks for nothing. Pure on the ladder.
function Discipline.Suggestion(ladder, level, punishRank)
    local rung = Discipline.RungFor(ladder, level)
    if not rung or rung.action == "none" then return nil end
    if rung.action == "rank" then return { action = "rank", rank = punishRank } end
    return { action = "tempban", days = rung.days }
end

-- A guildmate as the roster has them: whether they are online now, and the whole name to whisper (with
-- the realm a connected-realm guildmate's line gives, so the whisper never goes to a namesake here).
-- Nil when the roster does not have them.
local function rosterOf(name)
    local i = GuildOS.Compat.FindGuildRosterIndex(name)
    if not i then return nil end
    local full, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    return online and true or false, full or name
end

-- The click itself. Files the warning (always), and unless `opts.silent` whispers the filled template to
-- the member. Returns the warning, and how the whisper went: "sent", "silent", "offline", "locked" (the
-- game held the chat) or "failed"; or nil and why, as Add says.
function Discipline:Warn(playerKey, name, reason, opts)
    opts = opts or {}
    local w, why = self:Add(playerKey, reason, { note = opts.note, excerpt = opts.excerpt })
    if not w then return nil, why end
    if GuildOS.RosterLog then GuildOS.RosterLog:Record("warn", name, GuildOS.Compat.PlayerName(), self.ReasonText(reason)) end
    if opts.silent then return w, "silent" end
    local online, full = rosterOf(name)
    if online == false then return w, "offline" end
    if GuildOS.Compat.InChatLockdown and GuildOS.Compat.InChatLockdown() then return w, "locked" end
    local text = self.Fill(opts.text or self:GetTemplates()[self.TemplateFor(w.level)],
        { name = name, reason = self.ReasonText(reason), step = w.level, rule = opts.rule })
    local target = GuildOS:WhisperTarget(full or name)
    if GuildOS.NoteWhisper then GuildOS:NoteWhisper(target) end
    -- The click sends it, and the WhisperQueue counts it against WoW: Forever's limit (issue #393).
    local queue = GuildOS.WhisperQueue
    if queue then return w, queue:SendNow(target, text) and "sent" or "failed" end
    return w, GuildOS.Compat.SendWhisper(text, target) and "sent" or "failed"
end

-- The officer confirmed the suggestion. "rank" hands off to the game's own guild panel (a rank change is
-- Blizzard-protected) and says which rank; "tempban" files the ban. Whether something was done.
function Discipline:ApplySuggestion(name, suggestion, reason)
    if not GuildOS:IsOfficer() or type(suggestion) ~= "table" then return false end
    if suggestion.action == "rank" then
        if not suggestion.rank then return false end
        GuildOS:Print(string.format(L["Move %s to the rank %s in the game's guild panel."], name, suggestion.rank))
        if GuildOS.GuildManager then GuildOS.GuildManager:SetRank(name) end
        return true
    elseif suggestion.action == "tempban" then
        return GuildOS.BanList ~= nil and GuildOS.BanList:Add(name, self.ReasonText(reason), suggestion.days * 86400) == true
    end
    return false
end

----------------------------------------------------------------------
-- Sync among officers (domain "discipline")
----------------------------------------------------------------------
-- What goes on the wire: the warning without its chat line. The line is personal data for officers only
-- (specs/116), and a GUILD addon message reaches every member's client; the site gets it from the export
-- of the officer who filed it.
function Discipline.OnTheWire(w)
    local out = {}
    for f, v in pairs(w) do
        if f ~= "excerpt" then out[f] = v end
    end
    return out
end

function Discipline:_Publish(list)
    if not GuildOS.SyncService or #list == 0 then return end
    for i = 1, #list, self.BATCH do
        local batch = {}
        for j = i, math.min(i + self.BATCH - 1, #list) do batch[#batch + 1] = self.OnTheWire(list[j]) end
        GuildOS.SyncService:Publish("discipline", "set", { warnings = batch })
    end
end

Discipline.BACKFILL_MAX = 100

-- What an officer re-sends on login and on the answer to a sync request: the warnings that changed within
-- the term and a month, the newest 100. Older ones count for nothing anyway, and a bounded backfill keeps
-- the guild's channel quiet (#324). Pure on `s`.
function Discipline:BackfillSet(s, now, termDays)
    local since = now - (termDays + 30) * 86400
    local list = {}
    for _, w in pairs(s) do
        if (w.changedAt or 0) >= since then list[#list + 1] = w end
    end
    table.sort(list, function(a, b)
        if a.changedAt ~= b.changedAt then return a.changedAt > b.changedAt end
        return a.id < b.id
    end)
    while #list > self.BACKFILL_MAX do list[#list] = nil end
    return list
end

-- Idempotent: a peer that holds the same or newer copy keeps it (Newer).
function Discipline:Backfill()
    if not GuildOS:IsOfficer() then return end
    self:_Publish(self:BackfillSet(store(), GetServerTime(), self:GetTerm()))
end

-- From an officer over GUILD (SyncService checked it). A member's client stores nothing.
function Discipline:OnSync(env)
    if not GuildOS:IsOfficer() then return end
    if type(env) ~= "table" or env.act ~= "set" or type(env.data) ~= "table" or type(env.data.warnings) ~= "table" then return end
    local s, changed = store(), false
    for i = 1, math.min(#env.data.warnings, self.BATCH) do
        local w = self.Clean(env.data.warnings[i])
        if w then
            w.subject = GuildOS:LocalMemberKey(w.subject)   -- as this client keys that member (#97)
            if self.Merge(s, w) then changed = true end
        end
    end
    if changed then self:Refresh() end
end

function Discipline:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- The export (GOSCOMP1.discipline, specs/116)
----------------------------------------------------------------------
-- What the site reads: the term and the newest 500 warnings by change. Officers only; nil otherwise.
function Discipline:ForExport()
    if not GuildOS:IsOfficer() then return nil end
    local s = settings() or {}
    local list = {}
    for _, w in pairs(store()) do
        local clean = self.Clean(w)
        if clean then list[#list + 1] = clean end
    end
    table.sort(list, function(a, b)
        if a.changedAt ~= b.changedAt then return a.changedAt > b.changedAt end
        return a.id < b.id
    end)
    while #list > self.EXPORT_MAX do list[#list] = nil end
    return { termDays = self:GetTerm(), termAt = math.floor(tonumber(s.disciplineTermAt) or 0), warnings = list }
end

----------------------------------------------------------------------
-- Self-tests (pure logic only; injected stores)
----------------------------------------------------------------------
function Discipline:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    local D = Discipline

    S:Register("discipline.step_counts_standing_in_term", function()
        local day = 86400
        local list = { { at = 1000 }, { at = 1000, revokedAt = 2000 }, { at = 1000 - 40 * day } }
        if D.Step(list, 30, 1000 + day) ~= 1 then return false, "one should count" end
        if D.Step(list, 365, 1000 + day) ~= 2 then return false, "a longer term brings one back" end
        if D.Active({ at = 0 }, 30, 30 * day) then return false, "the term's last second is outside" end
        return true
    end)

    S:Register("discipline.newer_ties_go_to_revoked", function()
        local standing, revoked = { changedAt = 5 }, { changedAt = 5, revokedAt = 5 }
        if not D.Newer(revoked, standing) or D.Newer(standing, revoked) then return false, "tie" end
        if not D.Newer({ changedAt = 6 }, revoked) then return false, "newer change" end
        return true
    end)

    S:Register("discipline.clean_refuses", function()
        local ok = { id = "g1-AB", subject = "Thrall", by = "Jaina", reason = "spam", at = 10, changedAt = 10, level = 1 }
        if not D.Clean(ok) then return false, "a good one" end
        local bad = {
            { id = "d:1" }, { id = "a b" }, { reason = "rude" }, { level = 0 }, { changedAt = 9 },
            { revokedAt = 11 }, { subject = "a|b" }, { at = 0 / 0 },
        }
        for i, change in ipairs(bad) do
            local w = {}
            for f, v in pairs(ok) do w[f] = v end
            for f, v in pairs(change) do w[f] = v end
            if D.Clean(w) then return false, "case " .. i end
        end
        return true
    end)

    S:Register("discipline.ladder", function()
        if D.ValidLadder({ { action = "kick" } }) then return false, "unknown action" end
        if D.ValidLadder({ { action = "tempban", days = 0 } }) then return false, "no days" end
        local l = D.ValidLadder({ { action = "none" }, { action = "tempban", days = "7" } })
        if not l or D.RungFor(l, 5).action ~= "tempban" then return false, "past the end, the last rung" end
        if D.ValidTerm("31") ~= 31 or D.ValidTerm(366) or D.ValidTerm(1.5) then return false, "term" end
        return true
    end)
end
