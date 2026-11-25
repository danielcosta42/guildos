----------------------------------------------------------------------
-- Guild OS - Winter Veil's snow globe (issue #437; the site's specs/119, guildos-web#659)
--
-- The site holds the event, the draw, every pair and every rarity; this module shows them and tells the site what the
-- player asked in the game. What it knows comes from two blocks the companion writes:
--   GOSGILD1.veil   the guild's event: dates, counts, the Chimney, the officers' table, the chain after the opening
--   GOSVEIL1        this person's own: whom each of their characters drew, the globe they wrapped, the one they got,
--                   whether the site holds each one's in-game participation, and the account's Collection
-- What it tells the site goes in the export (GOSCOMP1.veil): join, leave, wrap (a scene and a note), open and plays.
-- The site sends GOSVEIL1's `event` to everybody once the event is open, so that block alone shows the tab and lets a
-- player join from the game.
--
-- Nothing here decides: the pairs, the rarity (drawn on the server when the receiver opens) and the Chimney are the
-- site's. The screen checks the note's rules first so nobody is surprised; the site refuses a line whole when it
-- breaks them. A member without the companion joins and leaves on the guild channel (an officer's export carries
-- it); wrapping and opening are the player's own export's, or the site's. There is no relay of pairs: a player without
-- the companion wraps on the site.
----------------------------------------------------------------------
local WV = {}
GuildOS.WinterVeil = WV

local DOMAIN = "veil"
WV.NOTE_MAX = 80
-- A note this long, with this many different letters, lifts the rarity one level (the site's capriceOf); shown as a
-- hint, the site decides.
WV.CAPRICE_MIN = 40
WV.CAPRICE_LETTERS = 6
-- The site's caps on one export's part (lib/veil-wire.ts): past them it refuses the part whole.
WV.EXPORT_JOINS = 100
WV.EXPORT_WRAPS = 200
WV.EXPORT_OPENS = 200
-- One play per character of the account (GOSVEIL1's `mine` holds at most 10): the site keeps those in its scope.
WV.EXPORT_PLAYS = 10
-- How long before a deadline a wrap the site has not taken yet is worth a warning.
WV.SYNC_WARN = 86400
-- The game's event starts on Dec 15, 00:00 server time (UTC-3); a play counts from then to the event's `wrapUntil`.
WV.PLAY_START_OFFSET = 3 * 3600
WV.SCENES = { "tree", "cabin", "snowman", "fire", "mountain" }
WV.RARITIES = { "common", "rare", "epic", "legendary" }

local function now() return GetServerTime() end
local function Import() return GuildOS.CompanionImport end

----------------------------------------------------------------------
-- What this client keeps: its own entry, the globes it wrapped and asked to open, what guildmates announced of
-- themselves, and the in-game play of each character of the account. A new year starts clean.
----------------------------------------------------------------------
local function store()
    local db = GuildOS.db
    if not db then return nil end
    db.winterVeil = db.winterVeil or {}
    local s = db.winterVeil
    local event = WV:Event()
    if event and s.year ~= event.year then
        db.winterVeil = { year = event.year }
        s = db.winterVeil
    end
    s.people = s.people or {}         -- [key] = { join = { volunteer, at }, left = at }
    s.wraps = s.wraps or {}           -- [receiverKey] = { scene, note, at }: the globes I wrapped here
    s.opens = s.opens or {}           -- [myKey] = at: I asked the site to open my globe
    -- The relay's leftovers (§13, gone): nothing reads them.
    s.opened, s.carried = nil, nil
    -- [key] = at: each character's first valid turn-in of a Winter Veil quest this year; one per key, at most
    -- EXPORT_PLAYS keys. The first design kept one { key, at } for the account.
    if type(s.played) ~= "table" then s.played = {} end
    if type(s.played.key) == "string" then s.played = { [s.played.key] = GuildOS.Finite(s.played.at) } end
    return s
end
WV._store = store

function WV:Event()
    local I = Import()
    return I and I.WinterVeil and I:WinterVeil() or nil
end

function WV:Personal()
    local I = Import()
    return I and I.VeilBlock and I:VeilBlock() or nil
end

-- The full name on WoW: Forever too (a first name and a surname): UnitName gives only the first.
function WV:MyKey() return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()) end

-- Days since 1970-01-01 of a civil date (proleptic Gregorian); no os/date calls, so the client's clock zone never enters.
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- The first second of the game's event for `year`: Dec 15 00:00 at UTC-3, as epoch seconds.
function WV.PlayStart(year)
    return daysFromCivil(year, 12, 15) * 86400 + WV.PLAY_START_OFFSET
end

-- "joining" | "closed" | "wrapping" | "wrapped" | "open", by the event's own clock (the site's phaseOf).
function WV.PhaseOf(e, t)
    if not e then return nil end
    t = t or now()
    if t >= e.openAt then return "open" end
    if not e.drawn then return t < e.joinUntil and "joining" or "closed" end
    return t < e.wrapUntil and "wrapping" or "wrapped"
end

----------------------------------------------------------------------
-- Taking part in the game's event: turning in one of Data/WinterVeilQuests.lua's quests (an event, QUEST_TURNED_IN:
-- IsQuestFlaggedCompleted stays true from earlier years). It counts for the Chimney, only for the one who played, only
-- from Dec 15 to the wrapping deadline, only if this person is in the event. The first one of each character is kept,
-- for at most EXPORT_PLAYS characters.
----------------------------------------------------------------------
function WV.IsPlayQuest(questID)
    local list = GuildOS.WinterVeilQuests
    return type(questID) == "number" and type(list) == "table" and list[questID] ~= nil
end

-- Pure: is `t` inside the window of event `e`.
function WV.InPlayWindow(e, t)
    if not (e and type(e.year) == "number" and type(e.wrapUntil) == "number") then return false end
    return t >= WV.PlayStart(e.year) and t < e.wrapUntil
end

-- Returns true when this turn-in was recorded now.
function WV:OnQuestTurnedIn(questID)
    if not WV.IsPlayQuest(questID) then return false end
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s and me) or s.played[me] then return false end
    if not WV.InPlayWindow(e, now()) or not self:Joined() then return false end
    local n = 0
    for _ in pairs(s.played) do n = n + 1 end
    if n >= WV.EXPORT_PLAYS then return false end
    s.played[me] = now()
    return true
end

-- Did this character's play get recorded here?
function WV:Played()
    local s, me = store(), self:MyKey()
    return s ~= nil and me ~= nil and s.played[me] ~= nil
end

-- Did the site's block say this character's participation is already registered (`mine[i].played`)?
function WV:PlaySeen()
    local m = self:MyEntry()
    return m ~= nil and m.played == true
end

----------------------------------------------------------------------
-- The note (the site's cleanNote): the same rules, checked here first. Nil and "note" when the site would refuse it.
----------------------------------------------------------------------
local BANNED = "[@`*_~<>%[%]|\\#]"
function WV.CharCount(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

function WV.CleanNote(raw)
    if raw == nil then return "" end
    if type(raw) ~= "string" then return nil, "note" end
    local plain = raw:gsub("[\t\n\r]", " ")
    -- control characters, C1 (U+0080-009F), zero-width and direction marks (U+200B-200F, U+2028-202E, U+2066-2069)
    if plain:find("[%z\1-\31\127]") or plain:find("\194[\128-\159]") or plain:find("\226\128[\139-\143]")
        or plain:find("\226\128[\168-\174]") or plain:find("\226\129[\166-\169]") then
        return nil, "note"
    end
    local note = plain:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if WV.CharCount(note) > WV.NOTE_MAX then return nil, "note" end
    local low = note:lower()
    if note:find(BANNED) or low:find("https?:") or low:find("www%.") then return nil, "note" end
    for _, tld in ipairs({ "com", "net", "org", "gg", "me", "io" }) do
        local from = 1
        while true do
            local a, b = low:find("%." .. tld, from)
            if not a then break end
            if not low:sub(b + 1, b + 1):find("[%w_]") then return nil, "note" end
            from = b + 1
        end
    end
    return note
end

-- The caprice (the site's capriceOf): the clean note has CAPRICE_MIN characters or more and CAPRICE_LETTERS different
-- letters or more, capitals aside. Pure; a hint only, the site decides. A note the site would refuse is no caprice.
local function foldLetter(ch)
    if #ch == 1 then return ch:find("%a") and ch:lower() or nil end
    local a, b = ch:byte(1, 2)
    if #ch == 2 then
        -- Latin-1 (U+00C0-U+00FF, but for × and ÷): capitals fold to small letters.
        if a == 195 then
            if b == 151 or b == 183 then return nil end
            if b <= 158 then b = b + 32 end
            return string.char(a, b)
        end
        -- Latin Extended-A and B, Greek, Cyrillic, Armenian, Hebrew, Arabic: each letter as itself.
        if a >= 196 and a <= 219 then return ch end
        return nil
    end
    -- CJK and Hangul (U+3040-U+D7FF): letters; the punctuation, symbols and emoji past ASCII are not.
    if #ch == 3 and a >= 227 and a <= 237 then return ch end
    return nil
end

function WV.Caprice(note)
    local clean = WV.CleanNote(note)
    if not clean or WV.CharCount(clean) < WV.CAPRICE_MIN then return false end
    local seen, n = {}, 0
    for ch in clean:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local l = foldLetter(ch)
        if l and not seen[l] then seen[l], n = true, n + 1 end
    end
    return n >= WV.CAPRICE_LETTERS
end

function WV.IsScene(id)
    for _, s in ipairs(WV.SCENES) do if s == id then return true end end
    return false
end

----------------------------------------------------------------------
-- Joining and leaving: said on the guild channel, so an officer's export carries a member who has no companion.
----------------------------------------------------------------------
function WV:Join(volunteer)
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s and me) or WV.PhaseOf(e) ~= "joining" then return false end
    s.people[me] = s.people[me] or {}
    s.people[me].join, s.people[me].left = { volunteer = volunteer == true, at = now() }, nil
    if GuildOS.SyncService then GuildOS.SyncService:Publish(DOMAIN, "join", { k = me, v = volunteer == true, at = s.people[me].join.at }) end
    return true
end

function WV:Leave()
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s and me) or WV.PhaseOf(e) ~= "joining" then return false end
    s.people[me] = s.people[me] or {}
    s.people[me].join, s.people[me].left = nil, now()
    if GuildOS.SyncService then GuildOS.SyncService:Publish(DOMAIN, "leave", { k = me, at = s.people[me].left }) end
    return true
end

-- True once this person's own entry is in: the site's block says so, or this client sent it.
function WV:Joined()
    if self:MyEntry() then return true end
    local s, me = store(), self:MyKey()
    local mine = s and me and s.people[me]
    return mine ~= nil and mine.join ~= nil
end

----------------------------------------------------------------------
-- Whom I give to: from my own block.
----------------------------------------------------------------------
function WV:MyEntry()
    local p, me = self:Personal(), self:MyKey()
    for _, m in ipairs(p and p.mine or {}) do
        if m.key == me or #p.mine == 1 then return m end
    end
    return nil
end

-- A companion is running for this person when the site's own block reached the inbox: wrapping and opening go
-- through its export, so without it the screen sends the player to the site.
function WV:HasCompanion() return self:Personal() ~= nil end

-- Each pair I give: { to, toClass?, scene?, note?, wrapped, pending?, extra?, hosted?, rarity? }. `wrapped` is the
-- site's word alone. A globe wrapped here that the site's block does not hold yet (not wrapped, or another scene or note)
-- is `pending`: its scene and note are the ones kept here, "waiting to sync" until the companion's next round.
function WV:MyGives()
    local m = self:MyEntry()
    local gives = {}
    for i, g in ipairs(m and m.gives or {}) do gives[i] = g end
    local s = store()
    for i, g in ipairs(gives) do
        local w = s and s.wraps[g.to]
        if w and not (g.wrapped and g.scene == w.scene and (g.note or "") == (w.note or "")) then
            gives[i] = { to = g.to, toClass = g.toClass, scene = w.scene, note = w.note, wrapped = g.wrapped, pending = true,
                         wrappedAt = w.at, extra = g.extra, hosted = g.hosted, rarity = g.rarity }
        end
    end
    return gives
end

-- The wraps made here that the site's block does not hold yet: { { to, scene, note, at } }, empty when all synced.
function WV:PendingSync()
    local out = {}
    for _, g in ipairs(self:MyGives()) do
        if g.pending then out[#out + 1] = { to = g.to, scene = g.scene, note = g.note, at = g.wrappedAt } end
    end
    return out
end

-- When the site reassigns a pair nobody wrapped: `reassignDays` before the wrapping deadline (the site's reassignAt).
function WV.ReassignAt(e)
    if not (e and type(e.wrapUntil) == "number" and type(e.reassignDays) == "number") then return nil end
    return e.wrapUntil - e.reassignDays * 86400
end

-- Pure: the warning for wraps still waiting to sync, or nil. The nearest deadline still ahead, when it is less than
-- SYNC_WARN away: { kind = "reassign" | "wrapUntil", at, left } (seconds left). `pending` is PendingSync()'s count.
function WV.SyncWarningAt(e, pending, t)
    if not e or (pending or 0) < 1 then return nil end
    for _, d in ipairs({ { "reassign", WV.ReassignAt(e) }, { "wrapUntil", e.wrapUntil } }) do
        local at = d[2]
        if at and t < at then
            if at - t < WV.SYNC_WARN then return { kind = d[1], at = at, left = at - t } end
            return nil
        end
    end
    return nil
end

-- The same for now: a wrap here is waiting to sync and a deadline is less than a day away.
function WV:SyncWarning()
    return WV.SyncWarningAt(self:Event(), #self:PendingSync(), now())
end

-- Wraps (or wraps again) the globe for `to`, one of whom I drew: a scene and a note, until the site's wrapping deadline.
-- Returns true, or false and why ("event", "phase", "pair", "scene", "note", "companion").
function WV:Wrap(to, scene, noteRaw)
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s and me) then return false, "event" end
    if WV.PhaseOf(e) ~= "wrapping" then return false, "phase" end
    if not self:HasCompanion() then return false, "companion" end
    local mine = false
    for _, g in ipairs(self:MyGives()) do if g.to == to then mine = true end end
    if not mine then return false, "pair" end
    if not WV.IsScene(scene) then return false, "scene" end
    local note, why = WV.CleanNote(noteRaw)
    if not note then return false, why end
    s.wraps[to] = { scene = scene, note = note, at = now() }
    return true
end

-- The receiver's request to open the globe: the site draws the rarity and says so in the next block. Nothing here
-- chooses it. Returns true, or false and why ("event", "phase", "companion", "nothing").
function WV:RequestOpen()
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s and me) then return false, "event" end
    if WV.PhaseOf(e) ~= "open" then return false, "phase" end
    if not self:HasCompanion() then return false, "companion" end
    local m = self:MyEntry()
    if not (m and m.got and m.got.ready and not m.got.ornament) then return false, "nothing" end
    s.opens[me] = s.opens[me] or now()
    return true
end

function WV:OpenRequested()
    local s, me = store(), self:MyKey()
    return s ~= nil and me ~= nil and s.opens[me] ~= nil
end

-- The globe I received: nil before it can be opened, { ready = true } once it can, { ready = true, ornament } after.
function WV:Got()
    local m = self:MyEntry()
    return m and m.got or nil
end

-- The account's Collection, newest first (the site's order).
function WV:Collection()
    local p = self:Personal()
    return p and p.collection or {}
end

----------------------------------------------------------------------
-- The guild channel: each player announces their own entry and exit; the game says who sent it, so a line about
-- anybody else is dropped. Wrapping and opening never travel here: they would tell the guild who wrapped, which only
-- the officers' table shows. A key is compared and kept as this client keys that member (LocalMemberKey): on WoW:
-- Forever two clients of one guild answer different realms ("Classic Beta PvE" and "... 2"), or none.
----------------------------------------------------------------------
local function wholeAt(v)
    local n = GuildOS.Finite(v)
    if not n or n ~= math.floor(n) or n < 1 or n > now() + 300 then return nil end
    return n
end

function WV:OnEnvelope(env, sender)
    local s = store()
    if not s or type(env) ~= "table" or type(env.data) ~= "table" then return end
    local d, act = env.data, env.act
    -- What a player says of themselves. (The relay's "pair" and "got" are gone: dropped like any other act.)
    local from = type(sender) == "string" and sender ~= "" and GuildOS:LocalMemberKey(GuildOS:KeyOfRosterName(sender)) or nil
    local k = type(d.k) == "string" and d.k ~= "" and #d.k <= 96 and not d.k:find("[|\r\n]") and GuildOS:LocalMemberKey(d.k) or nil
    if not (from and k) then return end
    local at = wholeAt(d.at)
    if act == "join" and k == from and at then
        local held = s.people[from]
        if not (held and held.join and held.join.at >= at) and not (held and held.left and held.left >= at) then
            s.people[from] = held or {}
            s.people[from].join, s.people[from].left = { volunteer = d.v == true, at = at }, nil
        end
    elseif act == "leave" and k == from and at then
        local held = s.people[from]
        if not (held and ((held.join and held.join.at >= at) or (held.left and held.left >= at))) then
            s.people[from] = held or {}
            s.people[from].join, s.people[from].left = nil, at
        end
    end
end

----------------------------------------------------------------------
-- The export (GOSCOMP1.veil, the site's specs/119 §13): `{ year, joins, leaves, wrap, open, plays }`. The site
-- believes all of it only from an officer's code for joins and leaves; wrap and open are only ever the exporter's own;
-- plays are every character of the account the site's scope allows.
-- A join or leave older than the site's newest block is one the site already had when it wrote it, and goes no more
-- (the site keeps the newest `at`); my own join goes no more once the site's block shows my entry.
----------------------------------------------------------------------
function WV:ForExport()
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s) then return nil end
    local out = { year = e.year, joins = {}, leaves = {}, wrap = {}, open = {}, plays = {} }
    local I = Import()
    local since = I and I.VeilBlockAt and I:VeilBlockAt() or 0
    local listed = self:MyEntry() ~= nil and me ~= nil
    for key, p in pairs(s.people) do
        if p.join and p.join.at >= since and not (listed and key == me) then
            out.joins[#out.joins + 1] = { key = key, volunteer = p.join.volunteer, at = p.join.at }
        end
        if p.left and p.left >= since then out.leaves[#out.leaves + 1] = { key = key, at = p.left } end
    end
    -- `to` names the pair only when I hold two (one taken over from somebody who did not wrap); with one it is implied.
    local gives = self:MyGives()
    for to, w in pairs(s.wraps) do
        local line = { giver = me, scene = w.scene, note = w.note, at = w.at }
        if #gives > 1 then line.to = to end
        out.wrap[#out.wrap + 1] = line
    end
    if me and s.opens[me] then out.open[1] = { receiver = me, at = s.opens[me] } end
    for key, at in pairs(s.played) do out.plays[#out.plays + 1] = { key = key, at = at } end
    -- Within the site's caps (the part is refused whole past them): the newest first, in a guild of hundreds.
    local function newest(list, max)
        table.sort(list, function(a, b) return a.at > b.at end)
        while #list > max do list[#list] = nil end
    end
    newest(out.joins, WV.EXPORT_JOINS)
    newest(out.leaves, WV.EXPORT_JOINS)
    newest(out.wrap, WV.EXPORT_WRAPS)
    newest(out.open, WV.EXPORT_OPENS)
    newest(out.plays, WV.EXPORT_PLAYS)
    return out
end

----------------------------------------------------------------------
-- Life
----------------------------------------------------------------------
function WV:Initialize()
    if GuildOS.SyncService then
        GuildOS.SyncService:On(DOMAIN, function(env, sender) WV:OnEnvelope(env, sender) end)
    end
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "QUEST_TURNED_IN", true)
    f:SetScript("OnEvent", function(_, event, questID)
        if event == "QUEST_TURNED_IN" then
            GuildOS:SafeCall(function() WV:OnQuestTurnedIn(questID) end)
        end
    end)
end
