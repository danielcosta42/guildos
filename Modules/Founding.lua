----------------------------------------------------------------------
-- Guild OS - Founding (issue #208, guildos.me #240)
--
-- On WoW: Forever every guild is born from nothing, on or after the launch (4 Nov 2026). The GM
-- records the day the guild was founded; everyone who joined within the 14 days after it is a
-- founding member, and the GM always is. guildos.me keeps it in the guild's book (payload v12).
--
--   `founding` (officer domain): the founding itself, highest revision wins; and an officer's
--     suggested date for the GM.
--   `foundingSelf` (member domain, guild channel only): each client says when its own character
--     joined, and nobody else's — the founders are worked out from those claims, never sent.
--
-- WoW: Forever only.
----------------------------------------------------------------------
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

local Founding = {}
GuildOS.Founding = Founding

local Compat = GuildOS.Compat

local DAY = 86400
Founding.FIRST_DAY = 1793750400   -- 2026-11-04 00:00 UTC: launch day, the earliest a guild was founded
Founding.WINDOW_DAYS = 14
local SKEW = 600                   -- a client's clock a little ahead is a clock
local PUBLISH_DELAY = 20           -- seconds after login: the guild channel is up by then
local LATER_S = DAY                -- "Later" puts the letter away for a day
local LATER_MAX = 3                -- and after three, it waits in Settings
local REVISION_MAX = 1e9           -- guildos.me takes no revision past this

local function dayOf(t) return t - t % DAY end

local function myKey() return GuildOS:GetPlayerKey(Compat.PlayerName()) end

local function senderKey(sender)
    local short = sender:match("^([^-]+)") or sender
    return GuildOS:GetPlayerKey(short, sender:match("-(.+)$"))
end

local function isInt(v) return type(v) == "number" and v == math.floor(v) end

-- The guild's own db is loaded: on launch day guilds are made mid-session, and a founding written
-- before the next login would land in the guildless db (#150).
local function onGuild() return GuildOS:IsOnGuildDB() end

-- Whether a key is the GM's on the guild roster this client holds.
local function isGMKey(key)
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and rankIndex == 0 then
            return GuildOS:GetPlayerKey(name:match("^([^-]+)") or name, name:match("-(.+)$")) == key
        end
    end
    return false
end

-- A founding day: 00:00 UTC, not before the launch, not after today.
function Founding.ValidDay(t, now)
    return isInt(t) and t == dayOf(t) and t >= Founding.FIRST_DAY and t <= dayOf(now)
end

-- The last second a founding member may join: the end of the 14th day after the founding day.
function Founding.WindowEnd(foundedAt)
    return foundedAt + (Founding.WINDOW_DAYS + 1) * DAY - 1
end

function Founding:Initialize()
    GuildOS.db.foundingJoins = GuildOS.db.foundingJoins or {}
    GuildOS.db.foundingPrompt = GuildOS.db.foundingPrompt or { later = 0, untilAt = 0 }
    if GuildOS.SyncService then
        GuildOS.SyncService:On("founding", function(env, sender) Founding:OnSync(env, sender) end)
        GuildOS.SyncService:On("foundingSelf", function(env, sender) Founding:OnSelf(env, sender) end)
    end
    Compat.After(PUBLISH_DELAY, function()
        Founding:FromSite()
        Founding:PublishSelf()
    end)
end

function Founding:Get() return GuildOS.db and GuildOS.db.founding end

function Founding:IsGM()
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

----------------------------------------------------------------------
-- The date the letter offers: the earliest the GuildOS saw anybody of today's roster (the game
-- says nothing of when somebody joined, guildos.me #240), never before the launch; else today.
----------------------------------------------------------------------
function Founding:SuggestedDay(now)
    local s = GuildOS.db.foundingSuggested
    if s and Founding.ValidDay(s.foundedAt, now) then return s.foundedAt, "declared" end
    -- `firstSeen` holds today's roster: whoever left had theirs dropped (1.0.2, DropDeparted).
    local earliest
    for _, t in pairs(GuildOS.db.firstSeen or {}) do
        if type(t) == "number" and (not earliest or t < earliest) then earliest = t end
    end
    if earliest then return math.max(Founding.FIRST_DAY, math.min(dayOf(earliest), dayOf(now))), "firstSeen" end
    return dayOf(now), "declared"
end

-- The GM records it (or corrects it). Returns whether it was taken.
function Founding:Record(foundedAt, source)
    local now = GetServerTime()
    if not onGuild() or not self:IsGM() or not Founding.ValidDay(foundedAt, now) then return false end
    local old = self:Get()
    GuildOS.db.founding = {
        foundedAt = foundedAt,
        source = source or "declared",
        declaredBy = myKey(),
        recordedAt = now,
        windowDays = Founding.WINDOW_DAYS,
        manual = old and old.manual or {},
        revision = math.min(REVISION_MAX, (old and old.revision or 0) + 1),
    }
    GuildOS.db.foundingSuggested = nil
    self:Forget()
    self:Publish()
    return true
end

-- An officer who is not the GM suggests a day; the GM's letter offers it. Kept, and sent again on
-- the officers' regular sync until the GM records one: the GM is often offline when it is made.
function Founding:Suggest(foundedAt)
    if not onGuild() or self:IsGM() or not GuildOS:IsOfficer() or not Founding.ValidDay(foundedAt, GetServerTime()) then return false end
    GuildOS.db.foundingSuggested = { foundedAt = foundedAt, by = myKey() }
    self:Publish()
    return true
end

-- What the letter's button does: the GM records, an officer suggests. "recorded", "suggested" or nil.
function Founding:Submit(foundedAt, source)
    if self:IsGM() then return self:Record(foundedAt, source) and "recorded" or nil end
    return self:Suggest(foundedAt) and "suggested" or nil
end

-- The letter's arrows: a day earlier or later, never off the founding days.
function Founding:Step(day, delta, now)
    local t = day + delta * DAY
    return Founding.ValidDay(t, now) and t or day
end

-- To the guild: when it changes, and again on the officers' regular sync (CommSystem), for a client
-- that missed it. The founding by the GM; an officer's own suggestion while nothing is recorded.
function Founding:Publish()
    if not onGuild() or not GuildOS.SyncService then return end
    local f = self:Get()
    if f and self:IsGM() then
        GuildOS.SyncService:Publish("founding", "set", { founding = f }, { rev = f.revision })
    end
    local s = GuildOS.db.foundingSuggested
    if not f and s and s.by == myKey() then
        GuildOS.SyncService:Publish("founding", "suggest", { foundedAt = s.foundedAt })
    end
end

-- A founding from outside this client, kept when it is the newest: the newest record wins (a new GM,
-- or one on a fresh install, records revision 1 again), and a tie in time keeps the higher revision.
-- Returns whether it was kept.
local function adopt(f, now)
    if not f or not Founding.ValidDay(f.foundedAt, now + SKEW) then return false end
    if not isInt(f.revision) or f.revision < 1 or f.revision > REVISION_MAX then return false end
    if not isInt(f.recordedAt) or f.recordedAt <= 0 or f.recordedAt > now + SKEW then return false end
    local held = Founding:Get()
    if held and (f.recordedAt < (held.recordedAt or 0)
        or (f.recordedAt == held.recordedAt and f.revision <= (held.revision or 0))) then return false end
    local manual = {}
    for key, m in pairs(type(f.manual) == "table" and f.manual or {}) do
        if type(key) == "string" and type(m) == "table" and type(m.reason) == "string" and m.reason ~= "" then
            manual[GuildOS:LocalMemberKey(key)] = { by = type(m.by) == "string" and GuildOS:LocalMemberKey(m.by) or nil,
                reason = m.reason, at = isInt(m.at) and m.at or nil }
        end
    end
    GuildOS.db.founding = {
        foundedAt = f.foundedAt,
        source = (f.source == "club" or f.source == "firstSeen" or f.source == "site") and f.source or "declared",
        declaredBy = type(f.declaredBy) == "string" and GuildOS:LocalMemberKey(f.declaredBy) or nil,
        recordedAt = f.recordedAt,
        windowDays = Founding.WINDOW_DAYS,
        manual = manual,
        revision = f.revision,
    }
    Founding:Forget()
    return true
end

-- The founding the site holds (guildos-web #259), by the same order. The GM's client tells the guild;
-- anybody else's keeps it, since the founding itself travels only from the GM.
function Founding:FromSite()
    local block = GuildOS.CompanionImport and GuildOS.CompanionImport:GuildBlock()
    local f = block and type(block.founding) == "table" and block.founding or nil
    if not f or not onGuild() then return end
    local manual = {}
    for _, m in ipairs(type(f.manual) == "table" and f.manual or {}) do
        if type(m) == "table" and type(m.key) == "string" then manual[m.key] = m end
    end
    f.manual = manual
    if adopt(f, GetServerTime()) then self:Publish() end
end

-- From an officer (SyncService checked the officer and the guild channel); the founding itself only
-- from the GM.
function Founding:OnSync(env, sender)
    local d = type(env.data) == "table" and env.data or nil
    if not d or not onGuild() or type(sender) ~= "string" then return end
    local now = GetServerTime()
    if env.act == "suggest" then
        if Founding.ValidDay(d.foundedAt, now) then
            GuildOS.db.foundingSuggested = { foundedAt = d.foundedAt, by = senderKey(sender) }
        end
        return
    end
    if env.act ~= "set" or not isGMKey(senderKey(sender)) then return end
    adopt(type(d.founding) == "table" and d.founding or nil, now)
end

----------------------------------------------------------------------
-- When my own character joined: the only claim a client makes (guildos.me #240). The game does not
-- say, so it is when the GuildOS first saw me in this guild, until a probe finds better (#214).
----------------------------------------------------------------------
function Founding:MyJoinedAt()
    local t = GuildOS:GetFirstSeen(myKey())
    return isInt(t) and t > 0 and t or nil, "firstSeen"
end

function Founding:PublishSelf()
    local t, src = self:MyJoinedAt()
    if not t or not onGuild() then return end
    GuildOS.db.foundingJoins[myKey()] = { joinedAt = t, src = src }
    self:Forget()
    if GuildOS.SyncService then GuildOS.SyncService:Publish("foundingSelf", "join", { joinedAt = t, src = src }) end
end

-- A member's claim about themselves: filed under who sent it, never a key the payload names.
function Founding:OnSelf(env, sender)
    local d = type(env.data) == "table" and env.data or nil
    if not d or type(sender) ~= "string" or sender == "" or not onGuild() then return end
    -- No guild on WoW: Forever is older than the launch, so nobody joined one before it.
    if not isInt(d.joinedAt) or d.joinedAt < Founding.FIRST_DAY or d.joinedAt > GetServerTime() + SKEW then return end
    GuildOS.db.foundingJoins[senderKey(sender)] = { joinedAt = d.joinedAt, src = "firstSeen" }
    self:Forget()
end

----------------------------------------------------------------------
-- The founding members, worked out the same way on every client: the GM, everyone the guild roster
-- holds whose join date (their own claim, else when this client first saw them) is within the
-- window, and the GM's manual additions. Key -> { joinedAt, src }.
-- Kept for a few seconds: the roster asks once per row (issue #209), and a change drops it.
----------------------------------------------------------------------
local cache, cacheAt
local CACHE_S = 5
function Founding:Forget() cache = nil end

function Founding:Founders()
    local t = GetTime()
    if cache and cacheAt and t - cacheAt < CACHE_S then return cache end
    cache, cacheAt = self:_Founders(), t
    return cache
end

function Founding:_Founders()
    local f = self:Get()
    if not f then return {} end
    local out, last = {}, Founding.WindowEnd(f.foundedAt)
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name then
            local key = GuildOS:GetPlayerKey(name:match("^([^-]+)") or name, name:match("-(.+)$"))
            -- The member's own claim and this client's first sighting both only bound the join from
            -- above (each is "known since"): the earlier is the better guess.
            -- Switched on with no /reload, Initialize has not made this table yet.
            local claim = (GuildOS.db.foundingJoins or {})[key]
            local joinedAt, src = claim and claim.joinedAt, claim and claim.src
            local seen = GuildOS:GetFirstSeen(key)
            if seen and (not joinedAt or seen < joinedAt) then joinedAt, src = seen, "firstSeen" end
            local manual = f.manual and f.manual[key]
            local left = GuildOS.db.foundingLeft and GuildOS.db.foundingLeft[key]
            if rankIndex == 0 or manual or (not left and joinedAt and joinedAt <= last) then
                out[key] = { joinedAt = joinedAt or f.foundedAt, src = src or "firstSeen" }
            end
        end
    end
    return out
end

-- Founders who left the guild (DropDeparted, issue #209): they keep their place in the guild's book on
-- guildos.me, and lose the badge here; coming back does not bring it back, the GM's manual
-- addition does. Called with who is in the whole roster, before their dates are dropped.
function Founding:Departed(present)
    if not self:Get() or not onGuild() then return end
    GuildOS.db.foundingLeft = GuildOS.db.foundingLeft or {}
    for key in pairs(self:_Founders()) do
        if not present[key] then GuildOS.db.foundingLeft[key] = true end
    end
    for key in pairs(GuildOS.db.foundingJoins or {}) do
        if not present[key] then GuildOS.db.foundingJoins[key] = nil end
    end
    self:Forget()
end

function Founding:IsFounder(key)
    return self:Founders()[key] ~= nil
end

-- What the companion export carries (payload v12): the founding, with founders as a list.
function Founding:ForExport()
    local f = self:Get()
    if not f then return nil end
    local founders, manual = {}, {}
    for key, v in pairs(self:Founders()) do founders[#founders + 1] = { key = key, joinedAt = v.joinedAt, src = v.src } end
    table.sort(founders, function(a, b) return a.key < b.key end)
    for key, m in pairs(f.manual or {}) do
        if type(m) == "table" then manual[#manual + 1] = { key = key, by = m.by, reason = m.reason, at = m.at } end
    end
    return {
        foundedAt = f.foundedAt, source = f.source, declaredBy = f.declaredBy, recordedAt = f.recordedAt,
        windowDays = f.windowDays, founders = founders, manual = manual, revision = f.revision,
    }
end

-- My own claim for the export's member row; nobody else's.
function Founding:JoinedAtOf(key)
    local c = GuildOS.db.foundingJoins and GuildOS.db.foundingJoins[key]
    return c and c.joinedAt or nil
end

----------------------------------------------------------------------
-- The letter (UI/Founding.lua): to the GM, while nothing is recorded, at most three times a day apart.
----------------------------------------------------------------------
function Founding:ShouldPrompt(now)
    if now < Founding.FIRST_DAY or not onGuild() or self:Get() or not self:IsGM() then return false end
    local p = GuildOS.db.foundingPrompt
    return (p.later or 0) < LATER_MAX and now >= (p.untilAt or 0)
end

function Founding:Later(now)
    local p = GuildOS.db.foundingPrompt
    p.later = (p.later or 0) + 1
    p.untilAt = now + LATER_S
end

----------------------------------------------------------------------
-- The badge (issue #209): a scroll by a founding member's name, in the roster and their card.
----------------------------------------------------------------------
Founding.BADGE = "|TInterface\\Icons\\INV_Scroll_03:12|t"

-- Days since 1970-01-01 of a UTC calendar date (H. Hinnant's days_from_civil), so an anniversary
-- needs no time zone: the client's own clock zone is not the guild's.
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- The day `months` after `t`, 00:00 UTC; a day past the month's end is its last (Jan 31 + 1 = Feb 28).
function Founding.AddMonths(t, months)
    local d = date("!*t", t)
    local m0 = d.month - 1 + months
    local y, m = d.year + math.floor(m0 / 12), m0 % 12 + 1
    local last = daysFromCivil(m == 12 and y + 1 or y, m == 12 and 1 or m + 1, 1) - daysFromCivil(y, m, 1)
    return daysFromCivil(y, m, math.min(d.day, last)) * DAY
end

-- 1, 3 and 6 months in the first year, then every 12 (guildos.me #240): the last one reached by `now`.
local function lastAnniversary(foundedAt, now)
    local found
    for _, m in ipairs({ 1, 3, 6 }) do
        local at = Founding.AddMonths(foundedAt, m)
        if at <= now then found = { months = m, at = at } end
    end
    local m = 12
    while true do
        local at = Founding.AddMonths(foundedAt, m)
        if at > now then break end
        found = { months = m, at = at }
        m = m + 12
    end
    return found
end

local function shortName(key) return (key:match("^(.-)%-[^-]*$") or key) end

-- The login digest's founding lines since `since`: who joined as a founder (three at most), the
-- window's days left or its closing, and an anniversary. `told` is what guildos.me says in this
-- digest (guildos-web #259): the closing and an anniversary it tells are not told twice.
function Founding:GetDigestLines(since, now, told)
    local L = GuildOS.L
    local f = self:Get()
    if not f then return {} end
    local out, last = {}, Founding.WindowEnd(f.foundedAt)
    local founders, count, named = self:Founders(), 0, 0
    for key, v in pairs(founders) do
        count = count + 1
        if now <= last and (v.joinedAt or 0) > (since or 0) and named < 3 and key ~= myKey() then
            named = named + 1
            out[#out + 1] = string.format(L["%s joined as a founding member"], shortName(key))
        end
    end
    if now <= last then
        out[#out + 1] = string.format(L["Founding window: %d days left · %d founding members"],
            math.max(1, math.ceil((last - now) / DAY)), count)
    elseif (since or 0) < last and not (told and told["founding.closed"]) then
        out[#out + 1] = string.format(L["Founding window closed: %d founding members"], count)
    end
    -- Since the last login, not "today": somebody back after three weeks reads it then.
    local a = lastAnniversary(f.foundedAt, now)
    if a and a.at > (since or 0) and not (told and told["guild.anniversary"]) then
        local guild = GetGuildInfo("player") or ""
        out[#out + 1] = a.months % 12 == 0 and string.format(L["%s turned %d year(s) old"], guild, a.months / 12)
            or string.format(L["%s turned %d month(s) old"], guild, a.months)
    end
    return out
end
