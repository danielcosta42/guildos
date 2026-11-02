----------------------------------------------------------------------
-- Guild OS - Guild Finder rules (specs/071-o-recrutamento in guildos-web, "No addon")
-- What a character with no guild sees on WoW: Forever and retail: the guilds that are recruiting,
-- filtered, ordered and read on the player's own clock. This file holds every rule; UI/GuildFinder.lua
-- only draws it (Rule 10).
--
-- An ad lives here in ONE shape, the site's GosrecrAd (packages/goscomp) with `heard` and `verified`
-- booleans added. Every source of ads (today the CR2 cache RecruitBeacon keeps; later CR3, the
-- companion's block) hands over its own records and a normalizer turns them into that shape, so a new
-- source never changes a filter or the screen.
----------------------------------------------------------------------
local GF = {}
GuildOS.GuildFinder = GF

local DAY          = 1440
local SAMPLE       = 30     -- minutes between two looks at a night, as the site does
local MAX_PITCH    = 120    -- characters (the site's cap)
local MAX_NAME     = 24     -- a guild name
local MAX_CONTACT  = 48
local MAX_LIST     = 12
local MAX_CLASSES  = 13     -- retail has thirteen; one short, the last class never sees a guild that wants them all
local MAX_ADS      = 600    -- the site's list holds 500, and what the network brings comes on top

GF.SITE = "guildos.me"

-- The site's vocabularies (apps/web/lib/recruitment.ts), in the order a menu lists them.
GF.PERIODS = { "morning", "afternoon", "night", "late" }
GF.PACES   = { "casual", "regular", "hardcore" }
GF.FOCUS   = { "RAID", "PVP", "SOCIAL", "LEVELING", "RP" }
GF.LOOTS   = { "council", "councilWishlist", "dkp", "epgp", "softres", "msos", "personal", "other" }
GF.TRIALS  = { "none", "week1", "week2", "days30", "other" }
GF.LOCALES = { "pt", "en", "es", "de", "fr", "ru", "ko", "zh-CN", "zh-TW" }

local PACE_SET, FOCUS_SET, LOOT_SET, TRIAL_SET, LOCALE_SET = {}, {}, {}, {}, {}
for _, v in ipairs(GF.PACES)   do PACE_SET[v] = true end
for _, v in ipairs(GF.FOCUS)   do FOCUS_SET[v] = true end
for _, v in ipairs(GF.LOOTS)   do LOOT_SET[v] = true end
for _, v in ipairs(GF.TRIALS)  do TRIAL_SET[v] = true end
for _, v in ipairs(GF.LOCALES) do LOCALE_SET[v] = true end

-- The game's locale codes onto the site's nine languages. Italian is the game's tenth: no ad names it.
local LOCALE_OF = {
    enUS = "en", enGB = "en", ptBR = "pt", ptPT = "pt", esES = "es", esMX = "es", deDE = "de",
    frFR = "fr", ruRU = "ru", koKR = "ko", zhCN = "zh-CN", zhTW = "zh-TW",
}
GF.LOCALE_OF = LOCALE_OF

local function now() return (GetServerTime and GetServerTime()) or time() end

----------------------------------------------------------------------
-- Text off the network: inert and one line. `max` counts characters, and a multi-byte character is
-- never cut in half (a CJK pitch cut by bytes would leave a broken sequence on screen).
----------------------------------------------------------------------
local function cutChars(s, max)
    local out, n, i = {}, 0, 1
    while i <= #s and n < max do
        local b = s:byte(i)
        local len = (b < 0x80 and 1) or (b >= 0xC2 and b < 0xE0 and 2) or (b >= 0xE0 and b < 0xF0 and 3)
                    or (b >= 0xF0 and b < 0xF5 and 4) or 0
        local whole = len > 0 and i + len - 1 <= #s
        for k = 1, whole and len - 1 or 0 do
            local c = s:byte(i + k)
            if c < 0x80 or c > 0xBF then whole = false; break end
        end
        -- A stray or truncated byte is dropped: off the network, half a character is a box on screen.
        if whole then
            out[#out + 1] = s:sub(i, i + len - 1)
            n, i = n + 1, i + len
        else
            i = i + 1
        end
    end
    return table.concat(out)
end

local function text(v, max)
    if type(v) ~= "string" then return nil end
    local s = GuildOS:SanitizeUserText(v, max * 4)   -- a character is at most four bytes
    s = cutChars(s, max)
    if s == "" then return nil end
    return s
end

GF.Text = text   -- the same clean for a request's name and note (Modules/JoinRequests.lua)

local function list(v, ok, max)
    if type(v) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, item in ipairs(v) do
        if type(item) == "string" and (not ok or ok[item]) and not seen[item] and #out < (max or MAX_LIST) then
            seen[item] = true
            out[#out + 1] = item
        end
    end
    if #out == 0 then return nil end
    return out
end

local function int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

----------------------------------------------------------------------
-- Normalize one record into the ad shape. Anything that is not an ad (no name, already expired)
-- comes back nil. Absent is absent, never an empty string or an empty list.
----------------------------------------------------------------------
function GF:Normalize(raw)
    if type(raw) ~= "table" then return nil end
    local n = text(raw.n, MAX_NAME)
    if not n then return nil end
    local ad = { n = n }

    ad.u = (type(raw.u) == "string" and raw.u:match("^[%w%-]+$") and #raw.u <= 64) and raw.u or nil
    ad.f = (raw.f == "H" or raw.f == "A") and raw.f or nil
    ad.w = (type(raw.w) == "string" and #raw.w <= 64) and text(raw.w, 64) or nil
    ad.p = text(raw.p, MAX_PITCH)

    local d = {}
    for _, day in ipairs(type(raw.d) == "table" and raw.d or {}) do
        day = int(day, 0, 6)
        if day and #d < 7 then d[#d + 1] = day end
    end
    if #d > 0 then ad.d = d end
    ad.s = int(raw.s, 0, DAY - 1)
    ad.e = int(raw.e, 0, DAY)
    ad.dt = text(raw.dt, 40)    -- the free-text days an old CR2 ad carries

    ad.pc = PACE_SET[raw.pc] and raw.pc or nil
    ad.l  = list(raw.l, LOCALE_SET)
    ad.fo = list(raw.fo, FOCUS_SET)
    ad.r  = list(raw.r, { TANK = true, HEALER = true, DPS = true })
    -- Classes are a closed set too: this game's own tokens, so nothing off the network reaches the screen.
    local classes = {}
    for _, token in ipairs(GuildOS.Client.classes) do classes[token] = true end
    ad.c  = list(raw.c, classes, MAX_CLASSES)
    ad.lo = LOOT_SET[raw.lo] and raw.lo or nil
    ad.t  = TRIAL_SET[raw.t] and raw.t or nil

    local ct = {}
    for _, c in ipairs(type(raw.ct) == "table" and raw.ct or {}) do
        c = text(c, MAX_CONTACT)
        if c and #ct < 3 then ct[#ct + 1] = c end
    end
    if #ct > 0 then ad.ct = ct end

    if type(raw.m) == "table" then
        local m = { n = int(raw.m.n, 0, 100000), nt = int(raw.m.nt, 0, 7), a = int(raw.m.a, 0, 100) }
        if m.n or m.nt or m.a then ad.m = m end
    end

    ad.v = tonumber(raw.v) or 0
    ad.x = tonumber(raw.x) or 0
    ad.heard = raw.heard and true or false
    ad.verified = raw.verified and true or false
    return ad
end

----------------------------------------------------------------------
-- The CR2 ads RecruitBeacon caches ("CR2|guild|faction|needs|days|note|langs|focus|version|expiry",
-- stored as sets) in the normalized shape. Heard, never verified.
----------------------------------------------------------------------
local CR2_LANG = { enUS = "en", ptBR = "pt", esES = "es", deDE = "de", frFR = "fr", ruRU = "ru",
                   koKR = "ko", zhCN = "zh-CN", zhTW = "zh-TW" }
GF.CR2_LANG = CR2_LANG
local CR2_LANG_ORDER = { "ptBR", "enUS", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW" }
local ROLE_ORDER = { "TANK", "HEALER", "DPS" }

function GF:FromCR2(r)
    if type(r) ~= "table" then return nil end
    local raw = { n = r.guild, f = r.faction, p = r.note, dt = r.days, v = r.version, x = r.expiry,
                  heard = true, verified = false }
    local needs, langs, focus = r.needs or {}, r.langs or {}, r.focus or {}
    raw.r, raw.c, raw.l, raw.fo = {}, {}, {}, {}
    for _, role in ipairs(ROLE_ORDER) do
        if needs[role] then raw.r[#raw.r + 1] = role end
    end
    for _, class in ipairs(GuildOS.Client.classes) do
        if needs[class] then raw.c[#raw.c + 1] = class end
    end
    for _, code in ipairs(CR2_LANG_ORDER) do
        if langs[code] then raw.l[#raw.l + 1] = CR2_LANG[code] end
    end
    for _, tok in ipairs(GF.FOCUS) do
        if focus[tok] then raw.fo[#raw.fo + 1] = tok end
    end
    -- CASUAL was a focus on the old beacon; on the site it is a pace.
    if focus.CASUAL then raw.pc = "casual" end
    if r.from and r.from ~= "" then raw.ct = { r.from } end
    return self:Normalize(raw)
end

----------------------------------------------------------------------
-- Sources: functions returning a list of records already in the ad shape (or raw, for Normalize).
-- CR2 is the first; CR3 and the companion's block add theirs.
----------------------------------------------------------------------
GF.sources = {}

function GF:AddSource(name, fn)
    for _, s in ipairs(self.sources) do
        if s.name == name then s.fn = fn; return end
    end
    self.sources[#self.sources + 1] = { name = name, fn = fn }
end

-- What RecruitBeacon heard, minus the player's own guild (GetInbox leaves it out).
function GF.HeardAds()
    local RB = GuildOS.RecruitBeacon
    local out = {}
    for _, r in ipairs(RB and RB:GetInbox() or {}) do
        out[#out + 1] = GF:FromCR2(r)
    end
    return out
end
GF:AddSource("CR2", GF.HeardAds)

-- The site's list in the person's own GOSRECR1 (the companion writes it, no token needed): verified,
-- because it came from the site and not from a peer. Normalized once per decoded list.
function GF:Directory()
    local Import = GuildOS.CompanionImport
    local data = Import and Import:RecruitDirectory()
    if not data then self._dirData, self._dirAds = nil, nil; return {} end
    if self._dirData ~= data then
        local ads = {}
        for _, raw in ipairs(data.ads) do
            if type(raw) == "table" then
                local copy = {}
                for k, v in pairs(raw) do copy[k] = v end
                copy.heard, copy.verified = false, true
                ads[#ads + 1] = self:Normalize(copy)
            end
        end
        self._dirData, self._dirAds = data, ads
    end
    return self._dirAds
end
GF:AddSource("GOSRECR1", function() return GF:Directory() end)

-- What peers handed over as a CR3, never verified here. An ad whose name and version are in the
-- person's own list is skipped: the list's copy of it is what shows, with the seal and with the list's
-- own words, so a forged ad that borrows a real name and version shows nothing of its own. No field of
-- a message can turn the seal on, because nothing in a message is looked at for it.
function GF.HeardCR3()
    local RB = GuildOS.RecruitBeacon
    local sealed = {}
    for _, ad in ipairs(GF:Directory()) do sealed[ad.n .. "|" .. ad.v] = true end
    local out = {}
    for _, ad in ipairs(RB and RB:Heard3() or {}) do
        if not sealed[ad.n .. "|" .. ad.v] then
            local copy = {}
            for k, v in pairs(ad) do copy[k] = v end
            copy.heard, copy.verified = true, false
            out[#out + 1] = copy
        end
    end
    return out
end
GF:AddSource("CR3", GF.HeardCR3)

-- Every live ad, one per guild name: the newer version wins, and at the same version the verified one.
function GF:All()
    local best, t = {}, now()
    for _, src in ipairs(self.sources) do
        local ok, got = pcall(src.fn)
        if ok and type(got) == "table" then
            for _, raw in ipairs(got) do
                local ad = self:Normalize(raw)
                if ad and ad.x > t then
                    -- A slug names one guild; without one, the name on its world. The same name on
                    -- another world is another guild, and no peer's ad may shadow it.
                    local key = ad.u or (ad.n:lower() .. "|" .. (ad.w or ""))
                    local cur = best[key]
                    if not cur or ad.v > cur.v or (ad.v == cur.v and ad.verified and not cur.verified) then
                        best[key] = ad
                    end
                end
            end
        elseif not ok then
            GuildOS:RecordError("GuildFinder source " .. src.name .. ": " .. tostring(got))
        end
    end
    -- An old client's CR2 names no slug and no world; when the same guild is here in full (same name, a
    -- faction that does not contradict it), the full ad is the one to show.
    local full = {}
    for _, ad in pairs(best) do
        if ad.u then full[#full + 1] = ad end
    end
    local out = {}
    for _, ad in pairs(best) do
        local shadowed = false
        if not ad.u and not ad.w then
            for _, other in ipairs(full) do
                if other.n:lower() == ad.n:lower() and (not ad.f or not other.f or ad.f == other.f) then shadowed = true; break end
            end
        end
        if not shadowed then out[#out + 1] = ad end
    end
    table.sort(out, function(a, b) return a.n < b.n end)   -- a stable start for Rank
    while #out > MAX_ADS do out[#out] = nil end
    return out
end

----------------------------------------------------------------------
-- Time: raid nights arrive in UTC and are read on the player's clock.
----------------------------------------------------------------------

-- Minutes the computer's clock is ahead of UTC, now (east of UTC is positive).
function GF:UtcOffset()
    local t = time()
    local u = date("!*t", t)
    u.isdst = date("*t", t).isdst
    return math.floor((t - time(u)) / 60 + 0.5)
end

local function periodOf(minute)
    local hour = math.floor(minute / 60) % 24
    return hour < 6 and "late" or hour < 12 and "morning" or hour < 18 and "afternoon" or "night"
end

-- A night at the player's clock: { { day = 0..6, from = minute, to = minute } }. `to` runs past 1440
-- when the night crosses midnight. An ad with days but no start is read at noon; one with no days has
-- no night. `offset` is minutes east of UTC and defaults to the computer's.
function GF:LocalTimes(ad, offset)
    if not ad or not ad.d or #ad.d == 0 then return {} end
    offset = offset or self:UtcOffset()
    local s = ad.s or 720
    local e = ad.e
    local length
    if not ad.s then length = SAMPLE
    elseif not e then length = SAMPLE
    else length = (e - s + DAY) % DAY; if length == 0 then length = SAMPLE end end
    local shift = math.floor((s + offset) / DAY)
    local from = s + offset - shift * DAY
    local out = {}
    for _, day in ipairs(ad.d) do
        out[#out + 1] = { day = (day + shift) % 7, from = from, to = from + length, clock = ad.s ~= nil }
    end
    table.sort(out, function(a, b) return a.day < b.day end)
    return out
end

-- Which (day, period) pairs a night touches, one look every half hour: a night that crosses midnight,
-- or a reader far enough east or west, lands in more than one, and counts in each (the site's rule).
-- An ad with no start has the day alone: its period is false.
function GF:Touches(ad, offset)
    local out, seen = {}, {}
    for _, t in ipairs(self:LocalTimes(ad, offset)) do
        if not t.clock then
            local key = t.day .. ":nil"
            if not seen[key] then seen[key] = true; out[#out + 1] = { day = t.day, period = false } end
        else
            for at = 0, (t.to - t.from) - 1, SAMPLE do
                local m = t.from + at
                local day = (t.day + math.floor(m / DAY)) % 7
                local period = periodOf(m)
                local key = day .. ":" .. period
                if not seen[key] then seen[key] = true; out[#out + 1] = { day = day, period = period } end
            end
        end
    end
    return out
end

local DAY_KEYS = { [0] = "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
GF.DAY_KEYS = DAY_KEYS

local function clock(m)
    m = m % DAY
    return string.format("%02d:%02d", math.floor(m / 60), m % 60)
end

-- "Tue and Thu · 21:00 to 00:00": days that share a window read together. Nil when the ad names no night
-- (the card then falls back to the free text an old ad carries).
function GF:Schedule(ad, offset)
    local times = self:LocalTimes(ad, offset)
    if #times == 0 then return ad and ad.dt or nil end
    local L = GuildOS.L
    local days = {}
    for _, t in ipairs(times) do days[#days + 1] = L[DAY_KEYS[t.day]] end
    -- "Tue and Thu", "Mon, Wed, Fri": two read with the word, more with commas (the mock).
    local joined = #days == 2 and string.format(L["%s and %s"], days[1], days[2]) or table.concat(days, ", ")
    local first = times[1]
    if not first.clock then return joined end
    return joined .. " \194\183 " .. string.format(L["%s to %s"], clock(first.from), clock(first.to))
end

----------------------------------------------------------------------
-- Where the player is: faction, region, class, language, and on retail the realms that can invite.
----------------------------------------------------------------------
function GF:ClientLocale()
    return LOCALE_OF[GetLocale and GetLocale() or "enUS"] or "en"
end

local function normRealm(s) return (tostring(s):lower():gsub("[%s%-']", "")) end

function GF:Context()
    local ctx = {}
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    ctx.faction = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
    ctx.region = GuildOS.Compat.Region()
    local _, class = UnitClass("player")
    ctx.class = class
    if GuildOS.Client.isRetail then
        -- A guild on a realm that is not connected to mine cannot invite me.
        ctx.realms = {}
        for _, name in ipairs(GuildOS.Compat.ConnectedRealms()) do ctx.realms[normRealm(name)] = true end
    end
    return ctx
end

-- "normal:us" onto "normal", "us"; "TolBarad:us" onto "TolBarad", "us".
local function splitWorld(w)
    if not w then return nil end
    return w:match("^(.+):(%l+)$")
end

-- Whether the finder is for this client at all: WoW: Forever and retail, never Anniversary.
function GF:Available()
    return not GuildOS.Client.isAnniversary
end

----------------------------------------------------------------------
-- Filters. Saved account-wide in GuildOSDB.guildFinder; `Current` is what is saved read together with
-- where the player is, which is what Matches and Ads take.
----------------------------------------------------------------------
function GF:Saved()
    if type(GuildOSDB) ~= "table" then return {} end
    if type(GuildOSDB.guildFinder) ~= "table" then GuildOSDB.guildFinder = {} end
    return GuildOSDB.guildFinder
end

function GF:SetFilter(key, value)
    self:Saved()[key] = value
end

function GF:Current()
    local s = self:Saved()
    local f = self:Context()
    -- false is "any language": nil means the saved choice was never made, and the client's wins.
    if s.locale == nil then f.locale = self:ClientLocale()
    elseif s.locale then f.locale = s.locale end
    f.day, f.period, f.pace, f.focus, f.loot, f.trial, f.world = s.day, s.period, s.pace, s.focus, s.loot, s.trial, s.world
    if s.wantsMe == false then f.class = nil end
    return f
end

-- One ad against one set of filters. A filter that is set and an ad that does not say: out, except
-- for language and class, where a list is what the guild wants and an empty one is "anyone".
function GF:Matches(ad, f, offset)
    f = f or {}
    if f.faction and ad.f and ad.f ~= f.faction then return false end

    local place, region = splitWorld(ad.w)
    if f.region and region and region ~= f.region then return false end
    if f.world and ad.w and ad.w ~= f.world then return false end
    if f.realms and place and not f.realms[normRealm(place)] then return false end

    if f.locale and ad.l and not tContains(ad.l, f.locale) then return false end
    if f.class and ad.c and not tContains(ad.c, f.class) then return false end
    if f.pace and ad.pc ~= f.pace then return false end
    if f.loot and ad.lo ~= f.loot then return false end
    if f.trial and ad.t ~= f.trial then return false end
    if f.focus and not (ad.fo and tContains(ad.fo, f.focus)) then return false end

    if f.day or f.period then
        local ok = false
        for _, p in ipairs(self:Touches(ad, offset)) do
            if (not f.day or p.day == f.day) and (not f.period or p.period == f.period) then ok = true; break end
        end
        if not ok then return false end
    end
    return true
end

-- Order: the ads that name the class first, then the reader's language, then whoever confirmed most
-- recently: the site's rule, word for word. `by` = { class =, locale = }; the player's own by default.
function GF:Rank(items, by)
    by = by or {}
    local class = by.class
    if class == nil then local _, c = UnitClass("player"); class = c end
    local locale = by.locale or self:ClientLocale()
    local function key(ad)
        return (ad.c and class and tContains(ad.c, class)) and 0 or 1,
               (ad.l and tContains(ad.l, locale)) and 0 or 1
    end
    local out = {}
    for i, ad in ipairs(items) do out[i] = ad end
    table.sort(out, function(a, b)
        local a1, a2 = key(a)
        local b1, b2 = key(b)
        if a1 ~= b1 then return a1 < b1 end
        if a2 ~= b2 then return a2 < b2 end
        if a.v ~= b.v then return a.v > b.v end
        return a.n < b.n
    end)
    return out
end

-- Every ad this player can act on, filtered and ranked. `filters` defaults to the saved ones.
function GF:Ads(filters, offset)
    local f = filters or self:Current()
    local out = {}
    for _, ad in ipairs(self:All()) do
        if self:Matches(ad, f, offset) then out[#out + 1] = ad end
    end
    return self:Rank(out, { class = f.class, locale = f.locale })
end

-- The worlds in the list the player could be on (region and faction already fit), for the World
-- filter: the ruleset is not something the client knows, so the menu offers the ones that exist.
function GF:Worlds(f)
    f = f or self:Current()
    local seen, out = {}, {}
    for _, ad in ipairs(self:All()) do
        local _, region = splitWorld(ad.w)
        if ad.w and not seen[ad.w] and not (f.region and region and region ~= f.region)
           and not (f.faction and ad.f and ad.f ~= f.faction) then
            seen[ad.w] = true
            out[#out + 1] = ad.w
        end
    end
    table.sort(out)
    return out
end

-- A world as its two halves: ("normal", "us") or ("TolBarad", "us"). Nil for anything else.
function GF:WorldParts(w)
    return splitWorld(w)
end

-- "The list was updated 3 h ago" from the list the companion wrote; nil with no list (or one too old).
function GF:UpdatedAgo()
    local Import = GuildOS.CompanionImport
    local data = Import and Import:RecruitDirectory()
    if not data then return nil end
    local L = GuildOS.L
    local minutes = math.max(1, math.floor((now() - (tonumber(data.at) or 0)) / 60))
    local when
    if minutes < 60 then when = string.format(L["%d min"], minutes)
    elseif minutes < 48 * 60 then when = string.format(L["%d h"], math.floor(minutes / 60))
    else when = string.format(L["%d d"], math.floor(minutes / 1440)) end
    return string.format(L["The list was updated %s ago."], when)
end

----------------------------------------------------------------------
-- The first guild of the session lights the minimap button. Only a character with no guild is
-- looking, and only where the finder exists.
----------------------------------------------------------------------
function GF:Initialize()
    local RB = GuildOS.RecruitBeacon
    if not (RB and hooksecurefunc) or self._hooked then return end
    self._hooked = true
    local function heard()
        if GF.heardThisSession or not GF:Available() or IsInGuild() then return end
        -- The filters the finder opens with, so the button never promises a guild the screen hides.
        if #GF:Ads() > 0 and GuildOS.GuildFinderHeard then
            GF.heardThisSession = true
            GuildOS:GuildFinderHeard()
        end
    end
    hooksecurefunc(RB, "Ingest", heard)
    hooksecurefunc(RB, "IngestCR3", heard)
end
