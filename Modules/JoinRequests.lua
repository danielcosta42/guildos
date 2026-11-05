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
local SPEC_ROLE = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DPS" }

local function now() return GetServerTime() end

local function text(v, max)
    local GF = GuildOS.GuildFinder
    return GF and GF.Text(v, max) or nil
end

-- The id of a request made in the game: ten letters and digits.
local function validId(id) return type(id) == "string" and id:match("^%w+$") ~= nil and #id == 10 end

-- The id of a row, which may be the site's (a UUID): the rule Import:SiteJoinRequests applies.
local function validRowId(id) return type(id) == "string" and #id <= 40 and id:match("^[%w_%-]+$") ~= nil end

-- Messages dropped for a reason that would otherwise be silent, for the Audit panel to show; and how many
-- invites went and how many times the game's "You have invited X" line came back for one, because no real
-- client has been seen to say it yet.
local dropped = { name = 0, guild = 0, invites = 0, confirmed = 0 }
function JR:Stats()
    return { name = dropped.name, guild = dropped.guild, invites = dropped.invites, confirmed = dropped.confirmed }
end

-- Everything the Audit panel counts about requests: the rows open here, this character's own asking (the ones
-- still in its queue, and of those the ones somebody answered), and the numbers above.
function JR:Audit()
    local asked, delivered = 0, 0
    local box = GuildOSDB and GuildOSDB.recruitOutbox and GuildOSDB.recruitOutbox[Compat.PlayerName()] or {}
    for _, e in pairs(box) do
        asked = asked + 1
        if e.delivered or e.status == "invited" or e.status == "declined" then delivered = delivered + 1 end
    end
    return { open = self:OpenCount(), asked = asked, delivered = delivered, invites = dropped.invites,
             confirmed = dropped.confirmed, dropped = { name = dropped.name, guild = dropped.guild } }
end

-- A request is relayed (and a closed one announced again) at most this often per row: the player repeats
-- every REPEAT_SECONDS, and a little less keeps one late timer from skipping a repetition.
JR.RELAY_GAP = 240
JR.INVITE_WAIT = 10   -- seconds the game has to say an invite went before the click is forgotten

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
    level = GuildOS.Finite(level)
    if not (level and level == math.floor(level) and level >= 1 and level <= 100) then level = nil end
    role = ROLES[role] and role or nil
    return class, level, role
end

-- Two spellings of one character: the game writes "Chehul Costa", people type the hyphen, and on
-- retail a sender may come with its realm.
local function sameName(a, b)
    a, b = a:lower():gsub("[%s%-]+", " "), b:lower():gsub("[%s%-]+", " ")
    return a == b or a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " "
end

-- The same name, whole: space and hyphen are one thing and case is none, and nothing else is.
local function sameWhole(a, b)
    return a:lower():gsub("[%s%-]+", " ") == b:lower():gsub("[%s%-]+", " ")
end

-- The confirmation of an invite names the person whole: "Ana" is not "Ana Lima" and "Ana" on this realm is
-- not "Ana-Gallywix". Space and hyphen are one thing, case is none. On retail the realm is compared when
-- both sides have one: the game leaves out this character's own.
local function sameInvited(a, b)
    a, b = a:lower():gsub("[%s%-]+", " "), b:lower():gsub("[%s%-]+", " ")
    if a == b then return true end
    if not GuildOS.Client.isRetail then return false end
    local nameA, realmA = a:match("^(%S+) (.+)$")
    local nameB, realmB = b:match("^(%S+) (.+)$")
    if realmA and realmB then return false end   -- both with a realm, and they are not the same
    return (nameA or a) == (nameB or b)
end

-- A guild name as the digest spells it, and with no case: the site and the game do not agree on it.
local function guildKey(name) return (tostring(name or ""):gsub("[,:]", " "):lower()) end

-- In a guild, and on that guild's db: a character that joined or changed guild this session has not
-- resolved to the new one yet (#150), and what it wrote would land in the wrong place.
local function inGuild() return IsInGuild() and GuildOS:IsOnGuildDB() end

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
        if e.key == (ad.u or ad.n) then return e end
    end
end

-- Where a request stands: "stored" (nobody has answered: kept here), "officer" or "member" (delivered,
-- and to whom), "invited", "declined" or "expired"; third, when it was answered. Nil for a request that
-- is not this character's.
function JR:Status(id)
    pruneOutbox()
    local e = outbox()[id]
    if not e then return nil end
    if e.status ~= "open" then return e.status, e.by, e.answeredAt end
    return e.delivered or "stored", e.by
end

-- Whether this session can reach the guild from the game at all: a whisper of ours has been seen to arrive.
function JR:CanReach()
    local gossip = GuildOS.ChehulGossip
    return gossip ~= nil and gossip:CanWhisper() == true
end

local function payloadOf(e)
    return table.concat({ "CRQ", e.id, e.character, e.class or "", e.level or "", e.role or "", e.guild, e.note or "" }, "|")
end

-- One round for one request: to the officer heard from that guild, else a member, and the contact names
-- the ad carries when nobody was heard or the one heard has not answered the round before (an addon that
-- predates this message never will). Nothing is tried where this client's whisper has not been seen to arrive.
function JR:Deliver(e)
    local gossip = GuildOS.ChehulGossip
    if not (gossip and gossip:CanWhisper()) then return 0 end
    local payload, sent = payloadOf(e), 0
    local peer = gossip:PeerFor(e.guild)
    local silent = (e.rounds or 0) >= 1 and not e.delivered
    if peer then
        e.rounds = (e.rounds or 0) + 1
        if gossip:Whisper(peer, payload) then sent = 1 end
    end
    if not peer or silent then
        for _, name in ipairs(e.ct or {}) do
            if gossip:Whisper(name, payload) then sent = sent + 1 end
        end
    end
    return sent
end

-- A character in a guild asks nobody: whatever is left of the queue goes.
local function clearOutbox()
    GuildOSDB.recruitOutbox = GuildOSDB.recruitOutbox or {}
    GuildOSDB.recruitOutbox[Compat.PlayerName()] = nil
end

function JR:Tick()
    if IsInGuild() then clearOutbox(); changed(); return end
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
    -- Nobody sets a preferred role before joining a guild: the spec the character is playing says it.
    if not role then
        local _, _, specRole = Compat.SpecOf("player")
        role = SPEC_ROLE[specRole]
    end
    local class, level
    class, level, role = facts(classFile, UnitLevel("player"), role)
    -- On retail the realm travels with the name: a namesake on a connected realm is somebody else.
    local name = Compat.PlayerName()
    if GuildOS.Client.isRetail and name and name ~= "" then name = GuildOS:KeyOfRosterName(name) or name end
    return { character = name, class = class, level = level, role = role }
end

-- Asks `ad`'s guild to take this character. Returns the request, or nil and why: "in-guild", "no-ad",
-- "too-many" (three are open), "already" (this guild has one open).
function JR:Send(ad, note)
    if IsInGuild() then return nil, "in-guild" end
    -- The slug is the site's name for the guild and a card heard by CR2 has none: the name stands in.
    if type(ad) ~= "table" or not ad.n then return nil, "no-ad" end
    local key = ad.u or ad.n
    pruneOutbox()
    local box, open = outbox(), 0
    for _, e in pairs(box) do
        if e.status == "open" then
            open = open + 1
            if e.key == key then return nil, "already" end
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
        note = text(note, NOTE_MAX), at = now(), guild = ad.n, slug = ad.u, key = key, ct = contacts, status = "open",
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
            if e.status == "open" and e.slug and e.at + self.EXPIRE_SECONDS > n then
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
    -- Off the guild's own db a write would land in the db of another guild, or of none: it lands nowhere.
    if not GuildOS:IsOnGuildDB() then return {} end
    GuildOS.db.joinRequests = GuildOS.db.joinRequests or {}
    return GuildOS.db.joinRequests
end

-- Drops what is not a row (a damaged save must not break a screen) and expires what is past its days.
local function expireRows()
    local n, rows = now(), store()
    for id, r in pairs(rows) do
        if type(r) ~= "table" or type(r.id) ~= "string" or type(r.character) ~= "string" or type(r.at) ~= "number" then
            rows[id] = nil
        elseif r.status == "open" and r.at + JR.EXPIRE_SECONDS <= n then
            r.status = "expired"
        end
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

-- The row whose request was made in the game under `id`: the site's row keeps it as `gameId`.
local function byGameId(id, character)
    for _, r in pairs(store()) do
        -- An id says nothing about whose it is: the name must still be the row's.
        if r.gameId == id and sameWhole(r.character, character) then return r end
    end
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

-- What a row tells a person who asks about it: officer or member for an open one, the decision for a
-- closed one, nothing for one that expired. And who says so.
local function answerOf(r)
    local state = r.status
    if state == "open" then return GuildOS:IsOfficer() and "officer" or "member", me() end
    if state == "invited" or state == "declined" then return state, r.decidedBy or me() end
    return nil
end

-- `id` is the one the person knows the request by: its own, when it was made in the game.
local function answerTo(r, name, id)
    local gossip = GuildOS.ChehulGossip
    local state, by = answerOf(r)
    if state and gossip then gossip:Whisper(name, table.concat({ "CRA", id or r.id, state, by }, "|")) end
end

-- A closed row whose request is heard again: a client that was offline at the decision, or the person
-- who never heard it, would otherwise make a new open row of it. An officer, or whoever decided, says it
-- again over GUILD and to the person, at most once per repetition.
local function announceAgain(r)
    if r.status ~= "invited" and r.status ~= "declined" then return end
    if not (GuildOS:IsOfficer() or r.decidedBy == me()) then return end
    if now() - (r.toldAt or 0) < JR.REPEAT_SECONDS then return end
    r.toldAt = now()
    local by = r.decidedBy or me()
    toGuild(table.concat({ "CRA", r.id, r.status, by }, "|"))
    local gossip = GuildOS.ChehulGossip
    if gossip then gossip:Whisper(r.character, table.concat({ "CRA", r.gameId or r.id, r.status, by }, "|")) end
end

-- A CRQ off the network. Whispered by the player it is the player's own, and answered; over GUILD it is
-- a guild-mate passing one on, and is kept and nothing more. Either way it says the player is online.
function JR:OnCRQ(payload, sender, dist)
    if type(sender) ~= "string" or not inGuild() then return end
    local mine = GetGuildInfo("player")
    if not mine or mine == "" then return end
    local f = { strsplit("|", payload) }
    if #f ~= 8 or f[1] ~= "CRQ" or not validId(f[2]) then return end
    if guildKey(f[7]) ~= guildKey(mine) then dropped.guild = dropped.guild + 1; return end
    local character = text(f[3], NAME_MAX)
    if not character then return end
    local direct = dist ~= "GUILD"
    if direct and not sameName(character, sender) then dropped.name = dropped.name + 1; return end
    local bans = GuildOS.BanList
    if bans and (bans:IsBanned(character) or (direct and bans:IsBanned(sender))) then return end

    local rows = store()
    -- A request the person made on the site and then in the game lives under the site's id, with the game's
    -- as `gameId`: when it was decided with the person offline, the id that comes back finds the closed row
    -- here, not an open one made new.
    local r = rows[f[2]] or byGameId(f[2], character)
    if r then
        if r.status == "open" then r.seen = now() end
    else
        -- One open request per person, however many ids. When one is open already (the person asked on
        -- the site, then in the game) the game's id is kept on it, so the answer finds its way back.
        local twin = openFor(character)
        if twin then
            twin.seen, twin.gameId = now(), f[2]
            r = twin
        else
            if not makeRoom() then return end
            local class, level, role = facts(f[4], f[5], f[6])
            r = { id = f[2], character = character, class = class, level = level, role = role, note = text(f[8], NOTE_MAX),
                  at = now(), seen = now(), status = "open", source = "addon", relayedBy = (not direct) and sender or nil }
            rows[r.id] = r
            if GuildOS:IsOfficer() then tell(GuildOS.JoinRequestsHeard, GuildOS, r) end
        end
    end
    if direct then
        answerTo(r, sender, f[2])
        if r.status == "open" and now() - (r.relayedAt or 0) >= JR.RELAY_GAP then
            r.relayedAt = now()
            toGuild(payload)
        end
    else
        announceAgain(r)
    end
    changed()
end

-- A CRA off the network. For a request this character made it is the answer; for a row in the guild's
-- db it is a decision, and only an officer's word over GUILD is one.
function JR:OnCRA(payload, sender, dist)
    local _, id, state, who = strsplit("|", payload)
    if not validRowId(id) or not (ANSWER[state] or state == "invited" or state == "declined") then return end
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

    if dist ~= "GUILD" or ANSWER[state] or not inGuild() then return end
    -- The channel and the rank both: the check reads the roster, and a row the roster could not vouch for
    -- stays open until the site's own block closes it.
    local gossip = GuildOS.ChehulGossip
    if not (gossip and gossip:IsOfficerSender(sender)) then return end
    local r = store()[id]
    if r and r.status == "open" then
        r.status, r.decidedBy, r.decidedAt = state, who, now()
        changed()
    end
end

-- Whether this character may close a request. The game's right to invite can reach below the guild's
-- officers: that person invites, and closes nothing.
function JR:CanDecide()
    return inGuild() and GuildOS:IsOfficer()
end

-- An officer's decision, once: the first one stands. It is told to the guild, and to the player if heard
-- just now, who would otherwise wait for the next repetition. A refusal says why: from the click on
-- Decline or from the game's line after an invite, it would otherwise be nothing happening.
function JR:Decide(id, status)
    if status ~= "invited" and status ~= "declined" then return false end
    if not self:CanDecide() then
        GuildOS:Print(L["Only an officer can close a request: this one stays open."])
        return false
    end
    expireRows()
    local r = store()[id]
    if not r or r.status ~= "open" then
        GuildOS:Print(L["This request is already closed."])
        return false
    end
    r.status, r.decidedBy, r.decidedAt = status, me(), now()
    toGuild(table.concat({ "CRA", id, status, me() }, "|"))
    local gossip = GuildOS.ChehulGossip
    if gossip and (r.source == "addon" or r.gameId) and now() - (r.seen or 0) < self.ONLINE_SECONDS then
        gossip:Whisper(r.character, table.concat({ "CRA", r.gameId or id, status, me() }, "|"))
    end
    changed()
    return true
end

-- Whether Invite would act: the request is open, this player may invite, and the person is there to be
-- invited. A request from the game is repeated by whoever is online, so one not heard for six minutes is
-- offline; the site cannot know, so a request from there is always live.
function JR:CanInvite(id)
    local r = inGuild() and store()[id] or nil
    if not r or r.status ~= "open" or not CanGuildInvite() then return false end
    if r.source == "site" then return true end
    return now() - (r.seen or 0) < self.ONLINE_SECONDS
end

local pending = {}   -- [id] = when the invite was sent: waiting for the game to say it went

-- The game's guild invite, with the name as the game gave it (retail: cut to the plain one on this
-- character's realm). Only ever called from the invite button (Compat.InviteButton): on WoW: Forever the
-- game lets no addon invite, so the button's own secure cover does it (#256), and there is no path here
-- that invites by itself. The row
-- is not closed here: the game's own line does that (see onSystem), so a person who is offline, or a
-- name the game refused, leaves it open for another try.
function JR:Invite(id)
    if not self:CanInvite(id) then return false end
    local Import = GuildOS.CompanionImport
    local name = store()[id].character
    if not GuildOS.Compat.GuildInvite(Import and Import.PlainName(name) or name) then return false end
    pending[id] = now()
    dropped.invites = dropped.invites + 1
    return true
end

-- "You have invited X to join your guild.": the only word the game gives that an invite went. A line the
-- client keeps secret, one for another name or one that comes late closes nothing: the error is always
-- toward not claiming what did not happen (the ingest closes the row as joined when the roster has them).
local function onSystem(_, _, msg)
    if next(pending) == nil or type(msg) ~= "string" or Compat.IsSecret(msg) or not ERR_GUILD_INVITE_S then return end
    local args = GuildOS:MatchFormat(msg, ERR_GUILD_INVITE_S)
    local name = args and args[1]
    if not name then return end
    dropped.confirmed = dropped.confirmed + 1
    local n = now()
    for id, at in pairs(pending) do
        local r = store()[id]
        if n - at > JR.INVITE_WAIT or not r or r.status ~= "open" then
            pending[id] = nil
        elseif sameInvited(r.character, name) then
            pending[id] = nil
            JR:Decide(id, "invited")
        end
    end
end

----------------------------------------------------------------------
-- What the site knows (GOSGILD1.joinRequests) and what it is told (the export's joinRequests)
----------------------------------------------------------------------
local FROM_SITE = { invited = "invited", joined = "invited", declined = "declined", expired = "expired" }

-- Reads the block's requests into the rows: a new open one becomes a row, a decision made on Discord
-- closes the row it names, a closed one this client never had is not worth keeping. It runs at the start,
-- when the rank is not known yet, and again from the officers' start, when it is: so a new row waits as
-- `unheard` until an officer's client reads it, and the officer hears of it once, as of one from the game.
function JR:Refresh()
    local Import = GuildOS.CompanionImport
    local list = inGuild() and Import and Import.SiteJoinRequests and Import:SiteJoinRequests() or nil
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
                           at = s.at, status = "open", source = s.source, unheard = true }
        end
    end
    expireRows()
    if GuildOS:IsOfficer() then
        for _, r in pairs(rows) do
            if r.unheard then
                r.unheard = nil
                if r.status == "open" then tell(GuildOS.JoinRequestsHeard, GuildOS, r) end
            end
        end
    end
    changed()
end

-- The rows as the site's GoscompJoinRequest, nil with none. Expired ones are not told: the site has its
-- own clock for them.
function JR:ForExport()
    if GuildOS.Client.isAnniversary or not inGuild() then return nil end
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
        GuildOS:SafeCall(function()
            if IsInGuild() then clearOutbox(); changed() end
        end)
    end)
    local chat = CreateFrame("Frame")
    Compat.RegisterEvent(chat, "CHAT_MSG_SYSTEM")
    chat:SetScript("OnEvent", function(...) GuildOS:SafeCall(onSystem, ...) end)

    if IsInGuild() then clearOutbox() end
    GuildOS:SafeCall(JR.Refresh, JR)
    pruneOutbox()
end
