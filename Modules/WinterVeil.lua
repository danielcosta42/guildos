----------------------------------------------------------------------
-- Guild OS - Winter Veil's snow globe (issue #437; the site's specs/119, guildos-web#659)
--
-- The site holds the event, the draw, every pair and every rarity; this module shows them and tells the site what the
-- player asked in the game. What it knows comes from two blocks the companion writes:
--   GOSGILD1.veil   the guild's event: dates, counts, the Chimney, the officers' table, the chain after the opening
--   GOSVEIL1        this person's own: whom each of their characters drew, the globe they wrapped, the one they got,
--                   the pairs they carry (sealed) for guildmates without the companion, and the account's Collection
-- What it tells the site goes in the export (GOSCOMP1.veil): join, leave, wrap (a scene and a note) and open.
--
-- Nothing here decides: the pairs, the rarity (drawn on the server when the receiver opens) and the Chimney are the
-- site's. The screen checks the note's rules first so nobody is surprised; the site refuses a line whole when it
-- breaks them. A member without the companion joins and leaves on the guild channel (an officer's export carries
-- it); wrapping and opening are the player's own export's, or the site's.
----------------------------------------------------------------------
local WV = {}
GuildOS.WinterVeil = WV

local DOMAIN = "veil"
WV.NOTE_MAX = 80
-- A note this long lifts the rarity one level (the site's CAPRICE_MIN); shown as a hint, the site decides.
WV.CAPRICE_MIN = 40
WV.RELAY_EVERY = 3600
-- The site's caps on one export's part (lib/veil-wire.ts): past them it refuses the part whole.
WV.EXPORT_JOINS = 100
WV.EXPORT_WRAPS = 200
WV.EXPORT_OPENS = 200
WV.SCENES = { "tree", "cabin", "snowman", "fire", "mountain" }
WV.RARITIES = { "common", "rare", "epic", "legendary" }

local function now() return GetServerTime() end
local function Import() return GuildOS.CompanionImport end

----------------------------------------------------------------------
-- What this client keeps: its own entry, the globes it wrapped and asked to open, what guildmates announced of
-- themselves, and the pair a carrier handed it. A new year starts clean.
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
    s.opened = s.opened or {}         -- [giverKey] = { to }: the pair a carrier whispered to me
    s.carried = s.carried or {}       -- [giverKey] = { at, got }: pairs I carry, when I last whispered them
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

-- "joining" | "closed" | "wrapping" | "wrapped" | "open", by the event's own clock (the site's phaseOf).
function WV.PhaseOf(e, t)
    if not e then return nil end
    t = t or now()
    if t >= e.openAt then return "open" end
    if not e.drawn then return t < e.joinUntil and "joining" or "closed" end
    return t < e.wrapUntil and "wrapping" or "wrapped"
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
-- Whom I give to: from my own block, or opened from a pair a carrier whispered.
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

-- Each pair I give: { to, toClass?, scene?, note?, wrapped, extra?, hosted?, rarity? }. What I wrapped here shows at once,
-- before the site's next block says it holds it.
function WV:MyGives()
    local m = self:MyEntry()
    local gives = {}
    if m and #m.gives > 0 then
        for i, g in ipairs(m.gives) do gives[i] = g end
    else
        local s, me = store(), self:MyKey()
        local opened = s and me and s.opened[me]
        if opened then gives[1] = { to = opened.to, wrapped = false } end
    end
    local s = store()
    for i, g in ipairs(gives) do
        local w = s and s.wraps[g.to]
        if w and (not g.wrapped or not g.scene) then
            gives[i] = { to = g.to, toClass = g.toClass, scene = w.scene, note = w.note, wrapped = true, extra = g.extra, hosted = g.hosted, rarity = g.rarity }
        end
    end
    return gives
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
-- The relay (§13): obfuscation, not secrecy. The same as the site's lib/veil-rules.ts, byte for byte; the harness
-- (tools/winter-veil.lua) holds the site's vector.
----------------------------------------------------------------------
local bit = _G.bit
local TWO32 = 4294967296
local function u32(x) return x % TWO32 end

function WV.Fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i)) % TWO32
        -- h * 16777619 = h * 2^24 + h * 403, each part kept under 2^53.
        h = u32(u32(bit.lshift(h, 24)) + h * 403)
    end
    return h
end

local function keystream(key, n)
    local x = WV.Fnv1a(key)
    if x == 0 then x = 0x9e3779b9 end
    local out = {}
    for i = 1, n do
        x = u32(bit.bxor(x, u32(bit.lshift(x, 13))))
        x = u32(bit.bxor(x, bit.rshift(x, 17)))
        x = u32(bit.bxor(x, u32(bit.lshift(x, 5))))
        out[i] = x % 256
    end
    return out
end

function WV.Seal(text, key)
    local ks, out = keystream(key, #text), {}
    for i = 1, #text do out[i] = string.format("%02x", bit.bxor(text:byte(i), ks[i])) end
    return table.concat(out)
end

function WV.Unseal(hex, key)
    if type(hex) ~= "string" or #hex % 2 ~= 0 or not hex:match("^%x*$") then return nil end
    local n = #hex / 2
    local ks, out = keystream(key, n), {}
    for i = 1, n do out[i] = string.char(bit.bxor(tonumber(hex:sub(2 * i - 1, 2 * i), 16), ks[i])) end
    return table.concat(out)
end

-- The site's key for a seal: "<salt>:<giver as the site spells them>". The site spells a WoW: Forever player
-- without a realm, so the realm this client added goes back off there.
function WV.SealKey(salt, giverKey)
    local spelled = giverKey
    if not GuildOS:RealmBound() then spelled = giverKey:match("^([^-]+)") or giverKey end
    return salt .. ":" .. spelled
end


-- Opens a pair a carrier whispered me; true when it was mine and read whole. The pair is the giver's target and
-- nothing else (`{"to": key}`): the wrapping is the player's own, on the site or in the game.
function WV:OpenPair(sealHex)
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and e.salt and s and me) then return false end
    local text = WV.Unseal(sealHex, WV.SealKey(e.salt, me))
    local ok, data = pcall(GuildOS.JsonDecode, text or "")
    if not ok or type(data) ~= "table" then return false end
    local to = Import().VeilKey(data.to)
    if not to then return false end
    s.opened[me] = { to = to }
    return true
end

-- Whispers each pair I carry to its owner while they are online, once an hour at most, until they say they have it.
function WV:Relay()
    local p, s = self:Personal(), store()
    if not (p and s and GuildOS.SyncService) then return 0 end
    local online = {}
    for i = 1, GetNumGuildMembers() do
        local full, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if full and isOnline then online[GuildOS:KeyOfRosterName(full)] = full end
    end
    local sent, t = 0, now()
    for _, r in ipairs(p.relay) do
        local c = s.carried[r.giver]
        local who = online[r.giver]
        if who and not (c and (c.got or t - c.at < WV.RELAY_EVERY)) then
            -- A WoW: Forever name has a space the whisper may need as a hyphen: ChehulGossip knows which reaches.
            local target = GuildOS.ChehulGossip and GuildOS.ChehulGossip.WhisperName and GuildOS.ChehulGossip:WhisperName(who) or who
            GuildOS.SyncService:Publish(DOMAIN, "pair", { g = r.giver, s = r.seal }, { target = target })
            s.carried[r.giver] = { at = t }
            sent = sent + 1
        end
    end
    return sent
end

----------------------------------------------------------------------
-- The guild channel: each player announces their own entry and exit; the game says who sent it, so a line about
-- anybody else is dropped. A pair is whispered to its owner alone. Wrapping and opening never travel here: they would
-- tell the guild who wrapped, which only the officers' table shows.
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
    local from = sender and GuildOS:KeyOfRosterName(sender)
    if act == "pair" then
        -- Only for me, only about me, and only from the carrier the site named for me: every member holds the salt,
        -- so anybody could seal a pair under my key.
        local me = self:MyKey()
        local e = self:Event()
        local carrier = e and e.carriers and e.carriers[me]
        if d.g == me and carrier and from == carrier and type(d.s) == "string" and self:OpenPair(d.s) and GuildOS.SyncService then
            GuildOS.SyncService:Publish(DOMAIN, "got", { g = d.g }, { target = sender })
        end
        return
    end
    if act == "got" then
        if d.g == from and s.carried[from] then s.carried[from].got = true end
        return
    end
    -- What a player says of themselves.
    if not from then return end
    local at = wholeAt(d.at)
    if act == "join" and d.k == from and at then
        local held = s.people[from]
        if not (held and held.join and held.join.at >= at) and not (held and held.left and held.left >= at) then
            s.people[from] = held or {}
            s.people[from].join, s.people[from].left = { volunteer = d.v == true, at = at }, nil
        end
    elseif act == "leave" and d.k == from and at then
        local held = s.people[from]
        if not (held and ((held.join and held.join.at >= at) or (held.left and held.left >= at))) then
            s.people[from] = held or {}
            s.people[from].join, s.people[from].left = nil, at
        end
    end
end

----------------------------------------------------------------------
-- The export (GOSCOMP1.veil, the site's specs/119 §13): `{ year, joins, leaves, wrap, open }`. The site believes all
-- of it only from an officer's code for joins and leaves; wrap and open are only ever the exporter's own.
----------------------------------------------------------------------
function WV:ForExport()
    local e, s, me = self:Event(), store(), self:MyKey()
    if not (e and s) then return nil end
    local out = { year = e.year, joins = {}, leaves = {}, wrap = {}, open = {} }
    for key, p in pairs(s.people) do
        if p.join then out.joins[#out.joins + 1] = { key = key, volunteer = p.join.volunteer, at = p.join.at } end
        if p.left then out.leaves[#out.leaves + 1] = { key = key, at = p.left } end
    end
    -- `to` names the pair only when I hold two (one taken over from somebody who did not wrap); with one it is implied.
    local gives = self:MyGives()
    for to, w in pairs(s.wraps) do
        local line = { giver = me, scene = w.scene, note = w.note, at = w.at }
        if #gives > 1 then line.to = to end
        out.wrap[#out.wrap + 1] = line
    end
    if me and s.opens[me] then out.open[1] = { receiver = me, at = s.opens[me] } end
    -- Within the site's caps (the part is refused whole past them): the newest first, in a guild of hundreds.
    local function newest(list, max)
        table.sort(list, function(a, b) return a.at > b.at end)
        while #list > max do list[#list] = nil end
    end
    newest(out.joins, WV.EXPORT_JOINS)
    newest(out.leaves, WV.EXPORT_JOINS)
    newest(out.wrap, WV.EXPORT_WRAPS)
    newest(out.open, WV.EXPORT_OPENS)
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
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE", true)
    local lastRelay = 0
    f:SetScript("OnEvent", function()
        if not WV:Event() or GetTime() - lastRelay <= 60 then return end
        lastRelay = GetTime()
        GuildOS:SafeCall(function() WV:Relay() end)
    end)
end
