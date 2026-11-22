----------------------------------------------------------------------
-- Guild OS - Anti-flood for the officers (issue #405, epic guildos-web#609)
--
-- Spam in /g becomes one flagged entry on the same panel as the chat alerts (#404), with Warn. Nothing
-- here silences anybody: the game has no guild mute, and the equivalent (the punishment rank) is the
-- officer's, through #403.
--
-- Four signals, each on or off with the guild's limits (guildcfg "modflood", newest stamp wins):
--   burst   N lines in X seconds (5 in 10)
--   repeat  the same line N times in X seconds (3 in 60)
--   caps    a line of at least M letters, P% of them capitals (12, 70%)
--   links   N links in X seconds (2 in 60)
-- The game's own links (an item, a spell, an achievement: |H...|h[...]|h) never count as a link nor as
-- capitals. A surge is ONE alert per person and signal while it lasts (it ends X seconds after its last
-- line), with the count and its lines; the officers settle who shows it the way #404 does.
--
-- What is kept per speaker is in memory only and bounded: their last 50 lines (time, a hash, the link
-- count and the text, to show a surge's lines), for ten minutes at most. Nothing of it is ever stored.
----------------------------------------------------------------------
local ModFlood = {}
GuildOS.ModFlood = ModFlood
local L = GuildOS.L

ModFlood.SIGNALS = { "burst", "repeat", "caps", "links" }
ModFlood.DEFAULTS = {
    burst = { on = true, n = 5, secs = 10 },
    ["repeat"] = { on = true, n = 3, secs = 60 },
    caps = { on = true, pct = 70, min = 12 },
    links = { on = true, n = 2, secs = 60 },
}
-- What each limit may be.
ModFlood.RANGE = { n = { 2, 50 }, secs = { 5, 600 }, pct = { 50, 100 }, min = { 5, 100 } }
ModFlood.KEEP = 600            -- seconds of a speaker's lines kept (the longest window)
ModFlood.PER_SPEAKER = 50      -- lines of one speaker kept
ModFlood.SPEAKERS_MAX = 300    -- speakers tracked at once
ModFlood.SURGE_LINES = 10      -- lines a surge's alert carries
local STAMP_FUTURE_SLACK = 300

local function settings() return GuildOS.db and GuildOS.db.settings end

----------------------------------------------------------------------
-- Pure helpers (unit-tested via /gos selftest and tools/mod-flood.lua)
----------------------------------------------------------------------
-- The line without the game's codes, and without the game's links at all (their text included).
function ModFlood.StripGameLinks(s)
    s = tostring(s or "")
    if not s:find("|", 1, true) then return s end
    return (s:gsub("|H.-|h.-|h", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- A bare domain ("cheapgold.com/x"): a word, a dot, one of these, then the end of the word. Made once.
local DOMAIN_PATTERNS = {}
for _, tld in ipairs({ "com", "net", "org", "gg", "io", "tv", "ru", "br", "de", "fr", "me", "co", "xyz", "shop", "info" }) do
    DOMAIN_PATTERNS[#DOMAIN_PATTERNS + 1] = "%f[%w][%w%-]+%." .. tld .. "%f[^%w][^%s]*"
end

-- How many links outside the game a line carries (on a line already stripped of the game's links).
function ModFlood.CountLinks(s)
    s = tostring(s or "")
    if not s:find(".", 1, true) then return 0 end   -- every kind below has a dot: most lines stop here
    s = s:lower()
    local n, k = 0
    s, k = s:gsub("https?://[^%s]+", " "); n = n + k
    s, k = s:gsub("www%.[^%s]+", " "); n = n + k
    for _, pat in ipairs(DOMAIN_PATTERNS) do
        s, k = s:gsub(pat, " "); n = n + k
    end
    return n
end

-- The share of capitals among a line's letters (ASCII and accented Latin), and how many letters it has.
-- On a line already stripped of the game's links.
function ModFlood.Caps(s)
    s = tostring(s or "")
    local _, up = s:gsub("%u", "")
    local _, low = s:gsub("%l", "")
    local _, upA = s:gsub("\195[\128-\158]", "")
    local _, lowA = s:gsub("\195[\159-\191]", "")
    -- Every other letter counts too, or a Russian, Chinese or Korean line with a few raid acronyms reads as
    -- all capitals: Cyrillic capitals (А-Я, Ё) as capitals, any other multi-byte letter as not.
    local _, upC = s:gsub("\208[\128-\175]", "")
    local _, other = s:gsub("[\196-\244]", "")
    -- A CJK or Hangul character says as much as a short word: it weighs three letters.
    local _, wide = s:gsub("[\227-\237]", "")
    up, low = up + upA + upC, low + lowA + (other - upC) + wide * 2
    local letters = up + low
    if letters == 0 then return 0, 0 end
    return math.floor(up * 100 / letters), letters
end

-- How many entries of a speaker's list (oldest first, each with `t`) fall inside the last `secs`
-- seconds, only those whose hash is `h` when given. The sliding window.
function ModFlood.InWindow(list, now, secs, h)
    local n, cut = 0, now - secs
    for i = #list, 1, -1 do
        local e = list[i]
        if e.t <= cut then break end
        if h == nil or e.h == h then n = n + 1 end
    end
    return n
end

-- A whole number in a limit's range, or nil (a number or digits typed in a box).
function ModFlood.ValidLimit(kind, v)
    if type(v) == "string" then
        if not v:match("^%s*%d+%s*$") then return nil end
        v = tonumber(v)
    end
    local r = ModFlood.RANGE[kind]
    if not r or type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < r[1] or v > r[2] then return nil end
    return v
end

-- The guild's limits off the network or the settings, cleaned: every signal present, a missing or bad
-- limit back to its default. Nil when it is not a table.
function ModFlood.ValidConfig(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for _, sig in ipairs(ModFlood.SIGNALS) do
        local d, given = ModFlood.DEFAULTS[sig], type(t[sig]) == "table" and t[sig] or {}
        local c = { on = (given.on == nil and d.on) or (given.on == true) }
        for kind, default in pairs(d) do
            if kind ~= "on" then c[kind] = ModFlood.ValidLimit(kind, given[kind]) or default end
        end
        out[sig] = c
    end
    return out
end

----------------------------------------------------------------------
-- The guild's limits
----------------------------------------------------------------------
-- Cleaned once per change, not per line.
function ModFlood:GetConfig()
    if self._cfg then return self._cfg end
    local s = settings()
    self._cfg = (s and self.ValidConfig(s.modFlood)) or self.ValidConfig({})
    return self._cfg
end

-- An officer saves the limits. True, or false and "officer".
function ModFlood:SetConfig(t)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local s = settings()
    s.modFlood = self.ValidConfig(t)
    self._cfg = nil
    s.modFloodAt = math.max(GetServerTime(), (s.modFloodAt or 0) + 1)
    self:PublishConfig()
    if GuildOS.ModAlerts then GuildOS.ModAlerts:Refresh() end
    return true
end

function ModFlood:PublishConfig()
    local s = settings()
    if not (s and s.modFloodAt and GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    GuildOS.SyncService:Publish("guildcfg", "modflood", { cfg = self:GetConfig() }, { rev = s.modFloodAt })
end

-- From an officer over GUILD (SyncService checked it): newest stamp wins, a tie keeps what is held.
function ModFlood:OnConfigSync(env)
    local data = type(env) == "table" and env.data
    local s = settings()
    if type(data) ~= "table" or not s or not GuildOS:IsOfficer() or env.act ~= "modflood" then return end
    local at = GuildOS.Finite(env.rev)
    if not (at and at > 0) then return end
    at = math.min(at, GetServerTime() + STAMP_FUTURE_SLACK)
    local cfg = self.ValidConfig(data.cfg)
    if not cfg or (s.modFloodAt and at <= s.modFloodAt) then return end
    s.modFlood, s.modFloodAt = cfg, at
    self._cfg = nil
    if GuildOS.ModAlerts then GuildOS.ModAlerts:Refresh() end
end

----------------------------------------------------------------------
-- The lines
----------------------------------------------------------------------
function ModFlood:Initialize()
    self.speakers, self.speakerCount, self.surges = {}, 0, {}
    self:_RegisterTests()
end

local function shortName(author)
    return author and (author:match("^([^-]+)") or author) or "?"
end

function ModFlood:_Prune(now)
    local cut = now - self.KEEP
    for who, list in pairs(self.speakers) do
        while list[1] and list[1].t <= cut do table.remove(list, 1) end
        if #list == 0 then self.speakers[who] = nil; self.speakerCount = self.speakerCount - 1 end
    end
    for k, sg in pairs(self.surges) do
        if sg.untilT <= now then self.surges[k] = nil end
    end
end

-- Which signals this line fires, with the speaker's list already holding it. Pure on its arguments.
function ModFlood.Fired(cfg, list, now, entry, capsPct, letters)
    local out = {}
    local b = cfg.burst
    if b.on and ModFlood.InWindow(list, now, b.secs) >= b.n then out[#out + 1] = "burst" end
    local r = cfg["repeat"]
    if r.on and ModFlood.InWindow(list, now, r.secs, entry.h) >= r.n then
        out[#out + 1] = "repeat"
    end
    local c = cfg.caps
    if c.on and letters >= c.min and capsPct >= c.pct then out[#out + 1] = "caps" end
    local k = cfg.links
    if k.on and entry.links > 0 then
        local total = 0
        local cut = now - k.secs
        for i = #list, 1, -1 do
            if list[i].t <= cut then break end
            total = total + list[i].links
        end
        if total >= k.n then out[#out + 1] = "links" end
    end
    return out
end

-- A line of /g (from ModAlerts: an officer's client, chat readable, alerts on). `folded` is the line
-- ModAlerts already lowered, for the repeat's hash.
function ModFlood:OnLine(msg, author, now, folded)
    if not self.speakers then return end
    -- Once a minute, before this speaker's list is taken: a prune may drop an emptied one.
    if now - (self.lastPrune or 0) >= 60 then self.lastPrune = now; self:_Prune(now) end
    local who = tostring(author or "?")
    local list = self.speakers[who]
    if not list then
        if self.speakerCount >= self.SPEAKERS_MAX then self:_Prune(now) end
        if self.speakerCount >= self.SPEAKERS_MAX then return end
        list = {}
        self.speakers[who] = list
        self.speakerCount = self.speakerCount + 1
    end
    local M = GuildOS.ModAlerts
    local bare = self.StripGameLinks(msg)
    local entry = {
        t = now, h = (M and M.Hash or tostring)(strtrim(folded or tostring(msg):lower())),
        links = self.CountLinks(bare), m = GuildOS:CutBytes((tostring(msg):gsub("%c", " ")), 255),
    }
    list[#list + 1] = entry
    while #list > self.PER_SPEAKER do table.remove(list, 1) end
    local cfg = self:GetConfig()
    local pct, letters = 0, 0
    if cfg.caps.on then pct, letters = self.Caps(bare) end
    local fired = self.Fired(cfg, list, now, entry, pct, letters)
    if #fired == 0 or not M then return end
    -- An officer's own line, or an officer's: as the alerts say (#404).
    if not M:_FromWatched(author) then return end
    self:_Surge(fired, msg, author, now, cfg)
end

-- One alert per person while the surge lasts (it ends a window after its last flagged line): a new
-- flagged line inside it adds to that alert, whichever signal it fired. `fired` in SIGNALS' order, so
-- every officer's client names the surge, and claims it, alike.
function ModFlood:_Surge(fired, msg, author, now, cfg)
    local M = GuildOS.ModAlerts
    local live = {}
    for _, sig in ipairs(fired) do
        if (M.mutes["F:" .. sig] or 0) <= now then live[#live + 1] = sig end
    end
    if #live == 0 then return end
    local secs = 0
    for _, sig in ipairs(live) do secs = math.max(secs, cfg[sig].secs or 60) end   -- caps has no window: a minute
    local line = GuildOS:CutBytes((tostring(msg):gsub("%c", " ")), 255)
    local sg = self.surges[author]
    if sg and sg.untilT > now then
        local a = sg.alert
        a.count = a.count + 1
        a.lines[#a.lines + 1] = line
        while #a.lines > self.SURGE_LINES do table.remove(a.lines, 1) end
        a.line = line
        for _, sig in ipairs(live) do
            if not a.seen[sig] then a.seen[sig] = true; a.signals[#a.signals + 1] = sig end
        end
        sg.untilT = now + secs
        M:Touch(a)
        return
    end
    -- The surge's lines so far: the window's of its first signal (the repeated one only, for a repeat;
    -- the ones with links, for links), the newest last.
    local sig = live[1]
    local lines, list = {}, self.speakers[author] or {}
    if sig ~= "caps" then
        local h = sig == "repeat" and list[#list] and list[#list].h or nil
        local cut = now - (cfg[sig].secs or 60)
        for i = #list, 1, -1 do
            local e = list[i]
            if e.t <= cut then break end
            if (h == nil or e.h == h) and (sig ~= "links" or e.links > 0) then table.insert(lines, 1, e.m) end
        end
    end
    if #lines == 0 then lines[1] = line end
    local count = #lines
    while #lines > self.SURGE_LINES do table.remove(lines, 1) end
    local seen = {}
    for _, x in ipairs(live) do seen[x] = true end
    local a = {
        kind = "flood", signal = sig, signals = live, seen = seen, cat = "flood", sev = "med", rule = "F:" .. sig,
        who = shortName(author), key = GuildOS:KeyOfRosterName(author), line = line,
        lines = lines, count = count,
        claim = M.ClaimKey(author, "flood:" .. sig .. "\n" .. tostring(msg)),
    }
    self.surges[author] = { alert = a, untilT = now + secs }
    M:Deliver(a, now)
end

local SIGNAL_TEXT = {
    burst = L["too many lines"], ["repeat"] = L["the same line repeated"], caps = L["in capitals"], links = L["links"],
}
function ModFlood.SignalText(sig) return SIGNAL_TEXT[sig] or tostring(sig or "?") end

----------------------------------------------------------------------
-- Self-tests (pure logic only)
----------------------------------------------------------------------
function ModFlood:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    local F = ModFlood

    S:Register("modflood.sliding_window", function()
        local list = { { t = 1 }, { t = 5 }, { t = 9 }, { t = 10 } }
        if F.InWindow(list, 10, 10) ~= 4 then return false, "all inside" end
        if F.InWindow(list, 11, 10) ~= 3 then return false, "the first slid out" end
        if F.InWindow(list, 30, 10) ~= 0 then return false, "after the end" end
        return true
    end)

    S:Register("modflood.caps", function()
        local pct, letters = F.Caps("COME TO KARA NOW")
        if pct ~= 100 or letters ~= 13 then return false, "all capitals" end
        pct = F.Caps(F.StripGameLinks("look |cffa335ee|Hitem:19019|h[THUNDERFURY BLESSED BLADE]|h|r ok"))
        if pct ~= 0 then return false, "a game link is not capitals" end
        return true
    end)

    S:Register("modflood.links", function()
        if F.CountLinks("visit https://x.io and www.y.com") ~= 2 then return false, "two links" end
        if F.CountLinks("gold at cheapgold.com now") ~= 1 then return false, "a bare domain" end
        if F.CountLinks(F.StripGameLinks("|cff0070dd|Hitem:1|h[www.not.a.link]|h|r")) ~= 0 then return false, "a game link" end
        if F.CountLinks("see you at 10.30, ok?") ~= 0 then return false, "not a link" end
        return true
    end)
end
