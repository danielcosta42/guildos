----------------------------------------------------------------------
-- Guild OS - JoinRequests (specs/071-o-recrutamento in guildos-web, "O pedido")
-- A character with no guild asks a guild to take it, and an officer of that guild invites or declines.
-- Both sides live here, over the prefix the gossip already owns:
--
--   CRQ|id|character|class|level|role|guild|note   the request, repeated every REPEAT_SECONDS while the
--                                                  player is online. The id makes a repeat harmless, and it
--                                                  is what delivery, presence and the answer all hang on
--   CRA|id|state|who                               the answer. officer and member say where it got to and
--                                                  do NOT stop the repetition; invited and declined end it
--
-- The guildless side keeps its queue in GuildOSDB.recruitOutbox[character] (account-wide: a guildless
-- character has no guild db worth the name) and writes the open ones to GuildOSDB.recruitOutboxWire on
-- logout, a GOSOUTB1 for the companion to take to the site. The guild's side keeps db.joinRequests[id],
-- fifty at most, and tells the site through the export's optional `joinRequests`.
--
-- Nothing here is ever said in a public channel, and nothing off the network is believed: names and
-- notes are inert, one line and cut by character; class, level and role are closed sets.
----------------------------------------------------------------------
local JR = {}
GuildOS.JoinRequests = JR

local Compat = GuildOS.Compat
local L = GuildOS.L

local PREFIX = "ChehulRecruit"

JR.REPEAT_SECONDS = 300        -- a request goes out again this often while the player is online
JR.MAX_OPEN       = 3          -- open requests one character may have
JR.EXPIRE_SECONDS = 14 * 86400 -- as on the site
JR.MAX_STORED     = 50         -- rows a guild's client keeps
JR.ONLINE_SECONDS = 360        -- a request heard this lately belongs to somebody online: the repeat is 300

local NOTE_MAX, NAME_MAX, WHO_MAX = 120, 48, 40
local KEEP_SECONDS = 30 * 86400    -- a closed entry of the player's own queue is forgotten after this
local ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local ANSWER = { officer = 2, member = 1 }        -- where a request got to; a better one is not taken back
local ROLES = { TANK = true, HEALER = true, DPS = true }

local function now() return GetServerTime() end

local function text(v, max)
    local GF = GuildOS.GuildFinder
    return GF and GF.Text(v, max) or nil
end

local function validId(id) return type(id) == "string" and id:match("^%w+$") ~= nil and #id == 10 end

local function classSet()
    if not JR._classes then
        JR._classes = {}
        for _, c in ipairs(GuildOS.Client.classes or {}) do JR._classes[c] = true end
    end
    return JR._classes
end

-- The three facts about a person that are a closed set or a number; anything else is absent.
local function facts(class, level, role)
    class = classSet()[class] and class or nil
    level = tonumber(level)
    if not level or level ~= math.floor(level) or level < 1 or level > 100 then level = nil end
    role = ROLES[role] and role or nil
    return class, level, role
end

-- Two spellings of one character: the game writes "Chehul Costa", people type the hyphen, and on
-- retail a sender may come with its realm.
local function sameName(a, b)
    a, b = a:lower():gsub("[%s%-]+", " "), b:lower():gsub("[%s%-]+", " ")
    return a == b or a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " "
end

local function guildKey(name) return (tostring(name or ""):gsub("[,:]", " ")) end

local function tell(fn, ...)
    if fn then pcall(fn, ...) end
end

-- The screens that show requests ask to hear when one changes. A screen that errors costs the others nothing.
local listeners = {}
function JR:Listen(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

----------------------------------------------------------------------
-- The queue of a character with no guild
----------------------------------------------------------------------
local function outbox()
    GuildOSDB.recruitOutbox = GuildOSDB.recruitOutbox or {}
    local me = Compat.PlayerName()
    GuildOSDB.recruitOutbox[me] = GuildOSDB.recruitOutbox[me] or {}
    return GuildOSDB.recruitOutbox[me]
end

-- Expires what is past fourteen days, forgets what closed long ago.
local function pruneOutbox()
    local box, n = outbox(), now()
    for id, e in pairs(box) do
        if e.status == "open" and e.at + JR.EXPIRE_SECONDS <= n then e.status = "expired" end
        if e.status ~= "open" and e.at + KEEP_SECONDS <= n then box[id] = nil end
    end
end

-- This character's requests, the latest first.
function JR:Outbox()
    pruneOutbox()
    local list = {}
    for _, e in pairs(outbox()) do list[#list + 1] = e end
    table.sort(list, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.id < b.id end)
    return list
end

-- The latest request this character made of the guild whose ad is `ad`, or nil.
function JR:Latest(ad)
    for _, e in ipairs(self:Outbox()) do
        if e.slug == ad.u then return e end
    end
end

-- Where a request stands: "stored" (nobody has answered: kept here), "officer" or "member" (delivered,
-- and to whom), "invited", "declined" or "expired". Nil for a request that is not this character's.
function JR:Status(id)
    pruneOutbox()
    local e = outbox()[id]
    if not e then return nil end
    if e.status ~= "open" then return e.status, e.by end
    return e.delivered or "stored", e.by
end

local function payloadOf(e)
    return table.concat({ "CRQ", e.id, e.character, e.class or "", e.level or "", e.role or "", e.guild, e.note or "" }, "|")
end

-- One round for one request: to the officer heard from that guild, else a member, else the contact names
-- the ad carries. Nothing is tried where this client's whisper has not been seen to arrive.
function JR:Deliver(e)
    local gossip = GuildOS.ChehulGossip
    if not (gossip and gossip:CanWhisper()) then return 0 end
    local payload, sent = payloadOf(e), 0
    local peer = gossip:PeerFor(e.guild)
    if peer then
        if gossip:Whisper(peer, payload) then sent = 1 end
    else
        for _, name in ipairs(e.ct or {}) do
            if gossip:Whisper(name, payload) then sent = sent + 1 end
        end
    end
    return sent
end

function JR:Tick()
    pruneOutbox()
    for _, e in pairs(outbox()) do
        if e.status == "open" then self:Deliver(e) end
    end
end

-- Who is asking: this character's name, class token, level and the role it prefers; what the game
-- will not say is absent.
function JR:Me()
    local _, classFile = UnitClass("player")
    local role
    local prefers = GuildOS:GetMyRoles()
    for _, r in ipairs({ "TANK", "HEALER", "DPS" }) do
        if prefers[r] then role = r; break end
    end
    local class, level
    class, level, role = facts(classFile, UnitLevel("player"), role)
    return { character = Compat.PlayerName(), class = class, level = level, role = role }
end

-- Asks `ad`'s guild to take this character. Returns the request, or nil and why: "in-guild", "no-ad",
-- "too-many" (three are open), "already" (this guild has one open).
function JR:Send(ad, note)
    if IsInGuild() then return nil, "in-guild" end
    if type(ad) ~= "table" or not ad.n or not ad.u then return nil, "no-ad" end
    pruneOutbox()
    local box, open = outbox(), 0
    for _, e in pairs(box) do
        if e.status == "open" then
            open = open + 1
            if e.slug == ad.u then return nil, "already" end
        end
    end
    if open >= self.MAX_OPEN then return nil, "too-many" end

    local id
    repeat
        id = ""
        for _ = 1, 10 do
            local at = math.random(1, #ID_ALPHABET)
            id = id .. ID_ALPHABET:sub(at, at)
        end
    until not box[id]

    local who = self:Me()
    local contacts = {}
    for _, name in ipairs(ad.ct or {}) do
        if #contacts < 3 and text(name, NAME_MAX) then contacts[#contacts + 1] = text(name, NAME_MAX) end
    end
    local e = {
        id = id, character = who.character, class = who.class, level = who.level, role = who.role,
        note = text(note, NOTE_MAX), at = now(), guild = ad.n, slug = ad.u, ct = contacts, status = "open",
    }
    box[id] = e
    self:Deliver(e)
    changed()
    return e
end

-- The queue as the companion takes it, on logout: only what is still open. Nothing when there is none.
function JR:WriteWire()
    local requests, n = {}, now()
    for _, entries in pairs(GuildOSDB.recruitOutbox or {}) do
        for _, e in pairs(entries) do
            if e.status == "open" and e.at + self.EXPIRE_SECONDS > n then
                requests[#requests + 1] = { id = e.id, slug = e.slug, character = e.character, class = e.class,
                    level = e.level, role = e.role, note = e.note, at = e.at }
            end
        end
    end
    if #requests == 0 then GuildOSDB.recruitOutboxWire = nil; return end
    table.sort(requests, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.id < b.id end)
    local wire = GuildOS.Companion:Pack("GOSOUTB1:", { fmt = "GOSOUTB1", v = 1, requests = requests })
    if wire then GuildOSDB.recruitOutboxWire = wire end
end

----------------------------------------------------------------------
-- The guild's rows
----------------------------------------------------------------------
local function store()
    GuildOS.db.joinRequests = GuildOS.db.joinRequests or {}
    return GuildOS.db.joinRequests
end

local function expireRows()
    local n = now()
    for _, r in pairs(store()) do
        if r.status == "open" and r.at + JR.EXPIRE_SECONDS <= n then r.status = "expired" end
    end
end

-- Room for one more row: drops the oldest closed one past the cap. False when all fifty are open.
local function makeRoom()
    local rows, count, oldest = store(), 0, nil
    for _, r in pairs(rows) do
        count = count + 1
        if r.status ~= "open" and (not oldest or r.at < oldest.at) then oldest = r end
    end
    if count < JR.MAX_STORED then return true end
    if not oldest then return false end
    rows[oldest.id] = nil
    return true
end

local function openFor(character)
    for _, r in pairs(store()) do
        if r.status == "open" and sameName(r.character, character) then return r end
    end
end

-- The rows, open ones first, each group the latest first.
function JR:List()
    expireRows()
    local list = {}
    for _, r in pairs(store()) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if (a.status == "open") ~= (b.status == "open") then return a.status == "open" end
        if a.at ~= b.at then return a.at > b.at end
        return a.id < b.id
    end)
    return list
end

function JR:OpenCount()
    expireRows()
    local n = 0
    for _, r in pairs(store()) do if r.status == "open" then n = n + 1 end end
    return n
end

function JR:Prune()
    expireRows()
    pruneOutbox()
end

local function me() return Compat.PlayerName() end

local function toGuild(payload)
    local mesh = _G.ChehulMesh
    if mesh then mesh:Guild(PREFIX, payload) end
end

local function answerTo(r, sender)
    local gossip = GuildOS.ChehulGossip
    local state = r.status
    if state == "open" then state = GuildOS:IsOfficer() and "officer" or "member" end
    if state == "expired" or not gossip then return end
    gossip:Whisper(sender, table.concat({ "CRA", r.id, state, me() }, "|"))
end

-- A CRQ off the network. Whispered by the player it is the player's own, and answered; over GUILD it is
-- a guild-mate passing one on, and is kept and nothing more. Either way it says the player is online.
function JR:OnCRQ(payload, sender, dist)
    if type(sender) ~= "string" or not IsInGuild() then return end
    local mine = GetGuildInfo("player")
    if not mine or mine == "" then return end
    local f = { strsplit("|", payload) }
    if #f ~= 8 or f[1] ~= "CRQ" or not validId(f[2]) or guildKey(f[7]) ~= guildKey(mine) then return end
    local character = text(f[3], NAME_MAX)
    if not character then return end
    local direct = dist ~= "GUILD"
    if direct and not sameName(character, sender) then return end
    local bans = GuildOS.BanList
    if bans and (bans:IsBanned(character) or (direct and bans:IsBanned(sender))) then return end

    local rows = store()
    local r = rows[f[2]]
    if r then
        if r.status == "open" then r.seen = now() end
    else
        -- One open request per person, however many ids: a flood of ids from one name fills nothing.
        if openFor(character) or not makeRoom() then return end
        local class, level, role = facts(f[4], f[5], f[6])
        r = { id = f[2], character = character, class = class, level = level, role = role, note = text(f[8], NOTE_MAX),
              at = now(), seen = now(), status = "open", source = "addon", relayedBy = (not direct) and sender or nil }
        rows[r.id] = r
        if GuildOS:IsOfficer() then tell(GuildOS.JoinRequestsHeard, GuildOS, r) end
    end
    if direct then
        answerTo(r, sender)
        if r.status == "open" then toGuild(payload) end
    end
    changed()
end

-- A CRA off the network. For a request this character made it is the answer; for a row in the guild's
-- db, heard over GUILD, it is a guild-mate's decision.
function JR:OnCRA(payload, _, dist)
    local _, id, state, who = strsplit("|", payload)
    if not validId(id) or not (ANSWER[state] or state == "invited" or state == "declined") then return end
    who = text(who, WHO_MAX) or ""

    local e = (not IsInGuild()) and outbox()[id] or nil
    if e then
        if e.status ~= "open" then return end
        if ANSWER[state] then
            if (ANSWER[state] or 0) >= (ANSWER[e.delivered] or 0) then e.delivered, e.by = state, who end
        else
            e.status, e.by, e.answeredAt = state, who, now()
            if state == "invited" then
                GuildOS:Print(string.format(L["Invite from %s"], e.guild))
            else
                GuildOS:Print(string.format(L["%s thanked you, but is not opening spots right now"], e.guild))
            end
        end
        changed()
        return
    end

    local r = IsInGuild() and dist == "GUILD" and store()[id] or nil
    if r and r.status == "open" and not ANSWER[state] then
        r.status, r.decidedBy, r.decidedAt = state, who, now()
        changed()
    end
end

-- An officer's decision, once: the first one stands. It is told to the guild, and to the player if heard
-- just now, who would otherwise wait for the next repetition.
function JR:Decide(id, status)
    if status ~= "invited" and status ~= "declined" then return false end
    local r = IsInGuild() and store()[id] or nil
    expireRows()
    if not r or r.status ~= "open" then return false end
    r.status, r.decidedBy, r.decidedAt = status, me(), now()
    local payload = table.concat({ "CRA", id, status, me() }, "|")
    toGuild(payload)
    local gossip = GuildOS.ChehulGossip
    if gossip and r.source == "addon" and now() - (r.seen or 0) < self.ONLINE_SECONDS then
        gossip:Whisper(r.character, payload)
    end
    changed()
    return true
end

-- Whether Invite would act: the request is open, this player may invite, and the person is there to be
-- invited. A request from the game is repeated by whoever is online, so one not heard for six minutes is
-- offline; the site cannot know, so a request from there is always live.
function JR:CanInvite(id)
    local r = IsInGuild() and store()[id] or nil
    if not r or r.status ~= "open" or not CanGuildInvite() then return false end
    if r.source == "site" then return true end
    return now() - (r.seen or 0) < self.ONLINE_SECONDS
end

-- The game's guild invite, with the name as the request gave it. Only ever called from a button's
-- OnClick: on WoW: Forever the game drops an invite that no click started (Compat.NeedsClick), and
-- there is no path here that invites by itself.
function JR:Invite(id)
    if not self:CanInvite(id) then return false end
    GuildInvite(store()[id].character)
    return self:Decide(id, "invited")
end

----------------------------------------------------------------------
-- What the site knows (GOSGILD1.joinRequests) and what it is told (the export's joinRequests)
----------------------------------------------------------------------
local FROM_SITE = { invited = "invited", joined = "invited", declined = "declined", expired = "expired" }

-- Reads the block's requests into the rows: a new open one becomes a row, a decision made on Discord
-- closes the row it names, a closed one this client never had is not worth keeping.
function JR:Refresh()
    local Import = GuildOS.CompanionImport
    local list = IsInGuild() and Import and Import.SiteJoinRequests and Import:SiteJoinRequests() or nil
    if not list then return end
    local rows = store()
    for _, s in ipairs(list) do
        local r = rows[s.id]
        if r then
            if r.status == "open" and FROM_SITE[s.status] then
                r.status = FROM_SITE[s.status]
                if r.status ~= "expired" then r.decidedBy = L["Discord"] end
            end
        elseif s.status == "open" and not openFor(s.character) and makeRoom() then
            local class, level, role = facts(s.class, s.level, s.role)
            rows[s.id] = { id = s.id, character = s.character, class = class, level = level, role = role, note = s.note,
                           at = s.at, status = "open", source = "site" }
        end
    end
    expireRows()
    changed()
end

-- The rows as the site's GoscompJoinRequest, nil with none. Expired ones are not told: the site has its
-- own clock for them.
function JR:ForExport()
    if GuildOS.Client.isAnniversary or not IsInGuild() then return nil end
    expireRows()
    local out = {}
    for _, r in pairs(store()) do
        if r.status == "open" or r.status == "invited" or r.status == "declined" then
            out[#out + 1] = { id = r.id, character = r.character, class = r.class, level = r.level, role = r.role,
                note = r.note, at = r.at, status = r.status, decidedBy = r.status ~= "open" and r.decidedBy or nil }
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.id < b.id end)
    return out
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function JR:Initialize()
    if GuildOS.Client.isAnniversary or self._started then return end
    self._started = true
    local gossip = GuildOS.ChehulGossip
    if gossip and gossip.On then
        gossip:On("CRQ", function(payload, sender, dist) JR:OnCRQ(payload, sender, dist) end)
        gossip:On("CRA", function(payload, sender, dist) JR:OnCRA(payload, sender, dist) end)
    end
    Compat.NewTicker(self.REPEAT_SECONDS, function() GuildOS:SafeCall(JR.Tick, JR) end)

    -- Entering a guild ends the asking: the queue is cleared.
    local frame = CreateFrame("Frame")
    Compat.RegisterEvent(frame, "PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function()
        if IsInGuild() then
            GuildOSDB.recruitOutbox = GuildOSDB.recruitOutbox or {}
            GuildOSDB.recruitOutbox[Compat.PlayerName()] = nil
            changed()
        end
    end)

    GuildOS:SafeCall(JR.Refresh, JR)
    pruneOutbox()
end
