----------------------------------------------------------------------
-- Guild OS - Without GuildOS: the officers' list and the reminder (issue #422;
-- Leadership > Without GuildOS)
--
-- Who in the guild this client never heard GuildOS from (the roster's "no
-- GuildOS": no `lastUpdate` in db.members, the same test as the roster and the
-- bulk actions), since when, and a polite reminder whispered to ONE member per
-- click of the officer. Who linked their Discord on guildos.me comes in the
-- officer's GOSGILD1 (`discordLinked`, CompanionImport:DiscordLinked): with it
-- the list also holds who has GuildOS but no Discord, and says which each one
-- lacks; without it (an older site, a member's code) it is as before, GuildOS
-- only, and the panel says the site does not tell.
--
-- One member is reminded at most once every N days (default 7), whoever of the
-- officers clicks: the date goes to the other officers (domain "reminder",
-- officer-authoritative). The whisper leaves on the click itself (a timer's is
-- dropped on WoW: Forever, Compat.NeedsClick), never two within GAP seconds,
-- and none for HOLD seconds after the game said "You are doing that too fast"
-- (ERR_GENERIC_THROTTLE, #393: the server throttles whispers, ours and the
-- realm bus's alike). A reminder the game throttled right after it left does
-- not count: its date is rolled back and nothing is filed.
--
-- With the officer's box ticked, the reminder is also filed on the member's
-- disciplinary record (#402) as a warning of reason "other": the record holds
-- warnings only, so it counts toward the ladder's step, and the box says so.
----------------------------------------------------------------------
local Reminder = {}
GuildOS.AddonReminder = Reminder
local L = GuildOS.L

Reminder.DEFAULT_DAYS = 7
Reminder.MIN_DAYS, Reminder.MAX_DAYS = 1, 90
Reminder.TEMPLATE_MAX = 200     -- bytes an officer may type; filled, the line is cut at 255
Reminder.WHISPER_MAX = 255      -- what SendChatMessage takes
Reminder.GAP = 10               -- seconds between two reminders of this client: six a minute at most
Reminder.HOLD = 60              -- seconds without any after the game's "too fast"
Reminder.WATCH = 3              -- seconds after a reminder within which "too fast" means it did not go
Reminder.KEEP = 90 * 86400      -- a reminder's date is forgotten after this
local STAMP_FUTURE_SLACK = 300

local function short(name)
    return name and (name:match("^([^-]+)") or name) or "?"
end

local function state()
    GuildOS.State.reminder = GuildOS.State.reminder or {}
    return GuildOS.State.reminder
end

local function store()
    GuildOS.db.reminders = GuildOS.db.reminders or {}
    return GuildOS.db.reminders
end

-- The game's "too fast" lines, as this client spells them.
local function isThrottle(msg)
    if type(msg) ~= "string" then return false end
    for _, k in ipairs({ "ERR_GENERIC_THROTTLE", "ERR_CHAT_THROTTLED" }) do
        local s = _G[k]
        if type(s) == "string" and s ~= "" and msg == s then return true end
    end
    return false
end

function Reminder:Initialize()
    store()
    state()
    self:Prune()
    if GuildOS.SyncService then
        GuildOS.SyncService:On("reminder", function(env) Reminder:OnSync(env) end)
    end
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "UI_ERROR_MESSAGE")
    f:SetScript("OnEvent", function(_, _, a1, a2)
        if isThrottle(a1) or isThrottle(a2) then GuildOS:SafeCall(Reminder.OnThrottle, Reminder) end
    end)
end

----------------------------------------------------------------------
-- Settings (the officer's own)
----------------------------------------------------------------------
-- A whole number of days, 1 to 90, a number or digits typed in a box; nil otherwise (never clamped).
function Reminder.ValidDays(v)
    if type(v) == "string" then
        if not v:match("^%s*%d+%s*$") then return nil end
        v = tonumber(v)
    end
    if type(v) ~= "number" or v ~= v or v ~= math.floor(v) then return nil end
    if v < Reminder.MIN_DAYS or v > Reminder.MAX_DAYS then return nil end
    return v
end

function Reminder:GetDays()
    return self.ValidDays(GuildOS:GetSetting("reminderDays")) or self.DEFAULT_DAYS
end

function Reminder:SetDays(v)
    local d = self.ValidDays(v)
    if not d then return false end
    GuildOS:SetSetting("reminderDays", d)
    return true
end

function Reminder.DefaultTemplate()
    return L["Hi {name}! The officers of {guild} use the GuildOS addon for raids, loot and the calendar. Could you install it when you have a moment? Thank you!"]
end

-- The "without Discord" variant: for who has GuildOS but did not link Discord on guildos.me.
function Reminder.DefaultDiscordTemplate()
    return L["Hi {name}! The officers of {guild} use guildos.me with Discord for raids and signups. Could you link your Discord there when you have a moment? Thank you!"]
end

-- Filled into {discord} for who lacks both (and put after a text that has no {discord}).
function Reminder.DiscordHint()
    return L["Also link your Discord on guildos.me."]
end

-- A template off a box: one line, no game codes, at most 200 bytes; nil when blank.
function Reminder.CleanTemplate(t)
    if type(t) ~= "string" then return nil end
    local s = GuildOS:SanitizeUserText(t, Reminder.TEMPLATE_MAX)
    return s ~= "" and s or nil
end

-- `kind` "discord" is the "without Discord" text; anything else the GuildOS one.
local function templateOf(kind)
    if kind == "discord" then return "reminderDiscordTemplate", Reminder.DefaultDiscordTemplate end
    return "reminderTemplate", Reminder.DefaultTemplate
end

function Reminder:GetTemplate(kind)
    local setting, default = templateOf(kind)
    return self.CleanTemplate(GuildOS:GetSetting(setting)) or default()
end

-- Blank (or the default itself) goes back to the default, in whatever language the client then runs.
function Reminder:SetTemplate(text, kind)
    local setting, default = templateOf(kind)
    local clean = self.CleanTemplate(text)
    if clean == default() then clean = nil end
    GuildOS:SetSetting(setting, clean)
end

--- What member `m` lacks: "both", "addon" (GuildOS), "discord", or nil (nothing).
function Reminder.KindOf(m)
    if not m then return nil end
    if not m.hasAddon then return m.noDiscord and "both" or "addon" end
    return m.noDiscord and "discord" or nil
end

--- The whisper for member `m` (name, guild): the GuildOS text, the Discord one, or for who lacks both the GuildOS
--- text with {discord} filled with the hint (put at its end when it has no {discord}). Pure.
function Reminder.TextFor(kind, templates, vars)
    local hint = kind == "both" and Reminder.DiscordHint() or ""
    local t = tostring((kind == "discord" and templates.discord or templates.addon) or "")
    if hint ~= "" and not t:find("{discord}", 1, true) then t = t .. " {discord}" end
    local v = {}
    for k, x in pairs(vars) do v[k] = x end
    v.discord = hint
    return strtrim(Reminder.Fill(t, v))
end

function Reminder:GetLogDiscipline()
    return GuildOS:GetSetting("reminderLog") == true
end

function Reminder:SetLogDiscipline(on)
    GuildOS:SetSetting("reminderLog", on and true or nil)
end

-- {name} and {guild} filled in, one line with no game codes, cut at 255 bytes. Pure.
function Reminder.Fill(template, vars)
    local text = tostring(template or ""):gsub("{(%a+)}", function(k)
        local v = vars[k]
        if v == nil then return "{" .. k .. "}" end
        return tostring(v)
    end)
    return GuildOS:SanitizeUserText(text, Reminder.WHISPER_MAX)
end

----------------------------------------------------------------------
-- The list (pure parts; tools/addon-reminder.lua)
----------------------------------------------------------------------
-- Whole days between `at` and `now`, or nil without `at`.
local function daysSince(at, now)
    at = GuildOS.Finite(at)
    if not at or at <= 0 then return nil end
    return math.max(0, math.floor((now - at) / 86400))
end
Reminder.DaysSince = daysSince

--- The members of `list` that `f` keeps: { text (part of the name, any case), rank (0-based; any when nil or
--- negative), online (online only), hideRecent (not those reminded within `days`), lacks ("addon": without
--- GuildOS, "discord": without Discord, "both": without either; anything else: all) }. Longest without GuildOS
--- first (the earliest seen), then by name.
function Reminder.Filter(list, f, now, days)
    f = type(f) == "table" and f or {}
    local text = type(f.text) == "string" and strtrim(f.text):lower() or ""
    local rank = GuildOS.Finite(f.rank)
    local out = {}
    for _, m in ipairs(list or {}) do
        local keep = true
        if text ~= "" and not (m.name or ""):lower():find(text, 1, true) then keep = false end
        if keep and rank and rank >= 0 and m.rankIndex ~= rank then keep = false end
        if keep and f.online and not m.online then keep = false end
        if keep and f.hideRecent and m.remindedAt and now - m.remindedAt < days * 86400 then keep = false end
        if keep and f.lacks == "addon" and m.hasAddon then keep = false end
        if keep and f.lacks == "discord" and not m.noDiscord then keep = false end
        if keep and f.lacks == "both" and (m.hasAddon or not m.noDiscord) then keep = false end
        if keep then out[#out + 1] = m end
    end
    table.sort(out, function(a, b)
        local sa, sb = a.since or math.huge, b.since or math.huge
        if sa ~= sb then return sa < sb end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return out
end

--- Whether member `m` may be reminded now, and when not why: "addon" (heard since, and nothing else lacking), "offline", "recent" (within
--- `days`, with the seconds left as a second value), "wait" (this client's gap, seconds left), "throttle" (the
--- game said too fast, seconds left). `t`: { now = server time, clock = GetTime(), last = clock of the last
--- reminder, holdUntil = clock }.
function Reminder.Check(m, t, days)
    if not m then return false, "gone" end
    if not Reminder.KindOf(m) then return false, "addon" end
    if not m.online then return false, "offline" end
    if m.remindedAt and t.now - m.remindedAt < days * 86400 then
        return false, "recent", m.remindedAt + days * 86400 - t.now
    end
    if t.holdUntil and t.clock < t.holdUntil then return false, "throttle", t.holdUntil - t.clock end
    if t.last and t.clock - t.last < Reminder.GAP then return false, "wait", Reminder.GAP - (t.clock - t.last) end
    return true
end

----------------------------------------------------------------------
-- The live roster
----------------------------------------------------------------------
-- Roster line `i` as the list reads it, or nil. `linked`: the site's set of keys with Discord (lower case), or
-- nil when the site does not say, and then `noDiscord` is nil for everyone.
local function memberAt(i, now, linked)
    local name, rankName, rankIndex, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
    if not name then return nil end
    local key = GuildOS:KeyOfRosterName(name)
    local d = (GuildOS.db.members or {})[key]
    local GM = GuildOS.GuildManager
    local off = (not online and GM) and GM:GetDaysOffline(i) or nil
    local since = GuildOS:GetFirstSeen(key)
    return {
        key = key, fullName = name, name = short(name),
        rankIndex = rankIndex, rankName = rankName or "?", level = level or 0,
        class = classFile or "", online = online and true or false,
        daysOffline = off and math.floor(off) or nil,
        hasAddon = (d and (tonumber(d.lastUpdate) or 0) > 0) and true or false,
        since = since, sinceDays = daysSince(since, now),
        remindedAt = GuildOS.Finite(store()[key]),
        noDiscord = linked and not linked[GuildOS:LocalMemberKey(key):lower()] or nil,
    }
end

--- The site's set of who linked Discord (CompanionImport:DiscordLinked), or nil when it does not say.
function Reminder:Linked()
    local I = GuildOS.CompanionImport
    return I and I.DiscordLinked and I:DiscordLinked() or nil
end

--- Everyone on the roster this client never heard GuildOS from, or (when the site says) without Discord, oneself aside.
function Reminder:Collect(now)
    now = now or GetServerTime()
    local me = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName())
    local linked = self:Linked()
    local out = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local m = memberAt(i, now, linked)
        if m and self.KindOf(m) and m.key ~= me then out[#out + 1] = m end
    end
    return out
end

--- One member read again from the roster by key, or nil when they left.
function Reminder:Member(key, now)
    now = now or GetServerTime()
    for i = 1, GetNumGuildMembers() or 0 do
        local name = GetGuildRosterInfo(i)
        if name and GuildOS:KeyOfRosterName(name) == key then return memberAt(i, now, self:Linked()) end
    end
    return nil
end

--- The list as the panel shows it: Collect, then Filter with the officer's days.
function Reminder:List(f, now)
    now = now or GetServerTime()
    return self.Filter(self:Collect(now), f, now, self:GetDays())
end

-- The clocks Check reads.
function Reminder:Times(now)
    local s = state()
    return { now = now or GetServerTime(), clock = GetTime(), last = s.last, holdUntil = s.holdUntil }
end

--- Whether `m` may be reminded now (Check against this client's clocks and the officer's days).
function Reminder:CanRemind(m, now)
    return self.Check(m, self:Times(now), self:GetDays())
end

----------------------------------------------------------------------
-- The click
----------------------------------------------------------------------
--- Whispers the reminder to the member keyed `key`, from the officer's click. Returns true, or false and why:
--- "officer", "gone", "locked" (the game holds the chat), "failed", or what Check says.
function Reminder:Remind(key)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local now = GetServerTime()
    local m = self:Member(key, now)
    local ok, why, left = self:CanRemind(m, now)
    if not ok then return false, why, left end
    if GuildOS.Compat.InChatLockdown and GuildOS.Compat.InChatLockdown() then return false, "locked" end
    local kind = self.KindOf(m)
    local text = self.TextFor(kind, { addon = self:GetTemplate(), discord = self:GetTemplate("discord") },
        { name = m.name, guild = GetGuildInfo("player") or "" })
    local target = GuildOS:WhisperTarget(m.fullName)
    if GuildOS.NoteWhisper then GuildOS:NoteWhisper(target) end
    -- The click sends it, and the WhisperQueue counts it against WoW: Forever's limit (issue #393), as Discipline's warning.
    local queue = GuildOS.WhisperQueue
    local went
    if queue then went = queue:SendNow(target, text) else went = GuildOS.Compat.SendWhisper(text, target) end
    if not went then return false, "failed" end

    local s, held = state(), store()
    local before = held[key]
    held[key] = now
    s.last = GetTime()
    local sent = { key = key, name = m.name, at = now, clock = s.last, before = before, log = self:GetLogDiscipline(), kind = kind }
    s.pending = sent
    -- The game's "too fast" comes back within a moment; only once it did not is the reminder counted.
    GuildOS.Compat.After(self.WATCH, function() GuildOS:SafeCall(Reminder.Settle, Reminder, sent) end)
    self:Refresh()
    return true
end

--- The game said "too fast": nothing for HOLD seconds, and a reminder that left just now did not go.
function Reminder:OnThrottle()
    local s = state()
    local clock = GetTime()
    s.holdUntil = clock + self.HOLD
    local p = s.pending
    if p and not p.settled and clock - p.clock <= self.WATCH then
        p.throttled = true
        p.settled = true
        s.pending = nil
        local held = store()
        if held[p.key] == p.at then held[p.key] = p.before end
        GuildOS:Print(string.format(L["The game said the reminder to %s went too fast: it did not count. Try again in a minute."], p.name))
    end
    self:Refresh()
end

-- WATCH seconds after a reminder with no "too fast": it went. To the other officers, and on the record when asked.
function Reminder:Settle(sent)
    if sent.settled then return end
    sent.settled = true
    local s = state()
    if s.pending == sent then s.pending = nil end
    if GuildOS.SyncService then GuildOS.SyncService:Publish("reminder", "sent", { key = sent.key, at = sent.at }) end
    if sent.log and GuildOS.Discipline then
        local note = (sent.kind == "discord" and L["Reminded to link Discord on guildos.me (whisper)."])
            or (sent.kind == "both" and L["Reminded to install GuildOS and link Discord (whisper)."])
            or L["Reminded to install GuildOS (whisper)."]
        GuildOS.Discipline:Add(sent.key, "other", { note = note })
    end
    self:Refresh()
end

----------------------------------------------------------------------
-- Among officers (domain "reminder": SyncService checked the sender is an officer, over GUILD)
----------------------------------------------------------------------
function Reminder:OnSync(env)
    if not GuildOS:IsOfficer() then return end
    local data = type(env) == "table" and env.act == "sent" and env.data
    if type(data) ~= "table" then return end
    local key, at = data.key, GuildOS.Finite(data.at)
    if type(key) ~= "string" or key == "" or #key > 64 or key:find("|", 1, true) then return end
    local now = GetServerTime()
    if not at or at <= 0 or at > now + STAMP_FUTURE_SLACK or at < now - self.KEEP then return end
    key = GuildOS:LocalMemberKey(key)
    local held = store()
    if (GuildOS.Finite(held[key]) or 0) >= at then return end
    held[key] = math.floor(math.min(at, now))
    self:Refresh()
end

-- Drops the dates past keeping (and anything that is not one). The number dropped.
function Reminder:Prune(now)
    now = now or GetServerTime()
    local held, dropped = store(), 0
    for key, at in pairs(held) do
        local n = GuildOS.Finite(at)
        if type(key) ~= "string" or not n or n < now - self.KEEP then
            held[key] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

function Reminder:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

-- What a refusal says to the officer.
function Reminder.WhyText(why, left)
    local secs = math.max(1, math.ceil(tonumber(left) or 0))
    if why == "officer" then return L["Only officers can do this."] end
    if why == "gone" then return L["No longer in the guild."] end
    if why == "addon" then return L["GuildOS heard from them since."] end
    if why == "offline" then return L["Offline: a whisper would not reach them."] end
    if why == "recent" then return string.format(L["Reminded recently: again in %d day(s)."], math.max(1, math.ceil(secs / 86400))) end
    if why == "wait" then return string.format(L["One reminder at a time: wait %d s."], secs) end
    if why == "throttle" then return string.format(L["The game said whispers went too fast: wait %d s."], secs) end
    if why == "locked" then return L["The game holds the chat right now."] end
    return L["The whisper did not go."]
end
