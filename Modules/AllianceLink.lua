----------------------------------------------------------------------
-- Guild OS - The alliance, the GreenWall way (issue #348)
--
-- Modelled on GreenWall (AIE-Guild/GreenWall, the base of Greenwall Forever),
-- because it works without anybody in particular being online:
--
--   * ONE CODE, THE SAME IN EVERY GUILD of the alliance:
--
--         GOS=TAG:key
--
--     An officer of each guild pastes it once in Officers' Room > Alliance (or,
--     later, guildos.me sends it through the companion). It is NOT
--     sent between guilds: nobody has to be an ambassador. It lives in the
--     PUBLIC NOTE OF THE GUILD MASTER, which the server hands every member
--     with the roster, so a member gets it with nobody else online at all
--     (issue #431). It is 27 bytes at most, so it fits the note's 31. The old
--     form with the guilds listed (GOS=TAG:key:Guilda A;Guilda B) is still
--     read; the short one lists none: who holds the key IS the alliance, and
--     the guilds are the ones heard on the channel (Heard).
--     It is also the addon's own data (db.allianceLink), handed to the guild
--     over the GUILD channel (SyncService "allylink") for a client that cannot
--     write the note: an officer's "set" reaches whoever is online,
--     anybody who logs in asks ("ask") and is answered by any guildmate that
--     holds it ("have"), and an ask from somebody holding a NEWER copy makes
--     the others ask back, so a holder logging in hands it on too.
--     The newest revision wins, and a removal is kept as one, so an old copy
--     never brings the alliance back. Only an officer authors it: "set" is an
--     officer write, and a relayed copy counts only when the officer it names
--     is an officer on the roster.
--
--   * ONE HIDDEN CHANNEL WITH A PASSWORD, named from the code: "GOSA" .. TAG ..
--     six base-36 characters of the key's hash (ChannelNameFor), the key its
--     password. Every member joins it and it is taken out of every chat frame.
--     A new key is a new channel: the clients of a guild that was removed are
--     left alone in the old one, reading nobody (audit #448). Every guild of
--     the alliance derives the same name from the same code, pasted or the
--     site's. Clients from before this naming (GOSA .. TAG alone) do not meet
--     the new ones: the guilds of an alliance update together.
--
--   * EVERY MEMBER CARRIES THEIR OWN WORDS. When the player presses Enter on
--     a line of /g, their own client says it on the channel too, inside the
--     same key press (Compat.HookChatSend), which is the only moment the game
--     lets an addon say anything on a channel. No bridge, no whisper, no
--     route: whoever is online hears whoever is online.
--
--   * WHO RECEIVES IT DRAWS IT AS /g. The line goes through the chat frame's
--     own handler as CHAT_MSG_GUILD (Compat.ReplayChatEvent): same colour,
--     same timestamp, same name link and class colour, the speaker's guild as
--     a tag in front.
--
-- On the channel a line is "<kind><code> <guild># <text>" (protocol 2, #449): kind g for /g, a for the
-- alliance room (Modules/AllianceChat.lua), code the speaker's guild's three characters (Code), then the
-- speaker's guild by name, so every client names it even with no directory, no mesh and no list. The name
-- counts only when its code is the line's. Protocol 1, "<kind><code> <text>" with kind G or A, is still read
-- (its guild named by the list, the directory, the guilds heard or the mesh). The speaker is the channel's
-- sender, which nobody can forge.
--
-- WHERE THE CODE COMES FROM, strongest first (alianca.md §3.2, §3.3):
--   1. guildos.me's, in the companion's GOSGILD1 (`alliance.code`, SiteCode). It
--      is never written into the guild's copy, the note or the sync: it is in
--      force while the site says so, on every client the companion feeds, and
--      the last one the site gave is remembered (db.allianceLinkSite) so a login
--      before the block is readable does not drop it. A block that is read and
--      names no alliance ends it (the guild left, was removed, or the alliance
--      was dissolved): the channel is left, and the guild's own copy comes back
--      into force only when it is ANOTHER code an officer pasted, never that
--      same dead code (db.allianceLinkSiteGone) until an officer pastes it again
--      — on the client whose own block saw it end. An end relayed by an officer
--      never touches a pasted or note copy.
--      Members without the companion get it from the guild (SyncService
--      "allylink" "site"): only an officer whose own client reads it in its
--      GOSGILD1 sends it, the sync takes it from officers only, and it is
--      checked again on receipt. The highest key version wins; the end ("gone",
--      naming the dead code) travels the same way. A member's client treats a
--      relayed code as the site's, and its own block, when it has one, over any
--      relay. Never into the GM's note: it stays the site's copy.
--   2. the guild's own copy (db.allianceLink): pasted by an officer, or read
--      from the guild master's note, the newest revision winning between the two
--      as always (an officer's save writes the note too, so they agree).
-- A new key, or a code that is gone, leaves the channel this character joined
-- with the old one (LeaveStale), recorded per character since channels are.
--
-- This is the chat only. The alliance's members, crafters, raids and bans come
-- from guildos.me through the companion (specs/salao/alianca.md); nothing goes
-- between guilds by whisper any more (audit #448).
--
-- HONEST LIMITS, the same as GreenWall's: who does not run Guild OS does not
-- see the other guilds; the key is readable by every member of every guild in
-- it; a line sent by a macro does not cross, since no key was pressed.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local Link = {}
GuildOS.AllianceLink = Link
local L = GuildOS.L

Link.DIRECTIVE  = "GOS="
Link.MAX_GUILDS = 16
Link.KEY_LEN    = 10
Link.MAX_LINE   = 255     -- what the game sends in one line of chat
Link.ASK_DELAY  = 12      -- seconds after login before asking the guild for the code
Link.ANSWER_MAX = 4       -- seconds a holder waits before answering, so one answers, not all
Link.NOTE_MAX   = 31      -- what the game keeps of a public note
Link.ASK_GAP    = 30      -- seconds between two asks of ours, however many ask us back
Link.NOTE_BY    = "guild master note"   -- the author of a copy read from the GM's note
Link.LEARN_TTL  = 30 * 86400   -- a guild nobody heard from in 30 days is forgotten

Link.stats = { sent = 0, heard = 0, shown = 0, dropped = 0 }

local function shortName(name)
    local s = tostring(name or "")
    return (Ambiguate and Ambiguate(s, "short")) or s
end

-- A channel sender as this client names them (#449): on WoW: Forever the roster's "First Surname" (the channel says
-- "First-Surname": SenderName), elsewhere the name without this client's own realm and with anybody else's, so a
-- cross-realm speaker reads "Bob-Other" and a whisper to them reaches them.
local function bare(s) return (tostring(s or ""):gsub("[%s%-']", ""):lower()) end
function Link.Speaker(author)
    if type(author) ~= "string" then return "" end
    local c = GuildOS.Client
    if c and c.has and c.has.surnames then
        -- "First-Sur-Name": the first hyphen is the surname's space, the rest of it is the surname's own hyphen
        -- unless it is this client's realm (#449). A name with a space is the roster's already.
        local first, rest = author:match("^([^%s%-]+)%-(.+)$")
        if not first then return GuildOS:SenderName(author) or author end
        local sur, tail = rest:match("^(.-)%-([^%-]+)$")
        if sur and sur ~= "" and (bare(tail) == bare(GetRealmName and GetRealmName())
                                  or bare(tail) == bare(GetNormalizedRealmName and GetNormalizedRealmName())) then
            rest = sur
        end
        return first .. " " .. rest
    end
    local name, realm = author:match("^([^-]+)%-(.+)$")
    if not name then return author end
    local mine = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName and GetRealmName()
    if bare(realm) == bare(mine) or bare(realm) == bare(GetRealmName and GetRealmName()) then return name end
    return author
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

----------------------------------------------------------------------
-- Pure. Pinned by tools/alliance-link.lua
----------------------------------------------------------------------

-- A guild's three-character code on the channel. Every client computes the
-- same one from the name (Alliance.Hash is part of the protocol).
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
function Link.Code(guildName)
    local n = GuildOS.Alliance.Hash(tostring(guildName or "")) % 46656
    local out = ""
    for _ = 1, 3 do
        local d = n % 36
        out = B36:sub(d + 1, d + 1) .. out
        n = (n - d) / 36
    end
    return out
end

-- The configuration in a text, or nil. Only the first GOS= counts, anywhere
-- in a line (a note may hold other words). The short form names no guild
-- (`open`): the guilds are learned. The listed form is refused whole when two
-- names hash alike, since the lines of one would show under the other.
function Link.Parse(text)
    if type(text) ~= "string" then
        return nil
    end
    for line in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
        local at = line:find(Link.DIRECTIVE, 1, true)
        local tag, key, rest
        if at then
            tag, key, rest = line:sub(at):match("^GOS=([%w]+):([%w]+)(.*)$")
        end
        if tag then
            tag = GuildOS.Alliance.NormalizeTag(tag)
            if tag == "" or #key < 4 then
                return nil
            end
            local list = rest:match("^:(.+)$")
            local guilds, codes, order = {}, {}, {}
            if not list then
                local short = Link.DIRECTIVE .. tag .. ":" .. key
                return { tag = tag, key = key, guilds = guilds, codes = codes, order = order,
                         line = short, open = true }
            end
            for name in (list .. ";"):gmatch("([^;]*);") do
                name = trim(name)
                if name ~= "" and not guilds[name] and #order < Link.MAX_GUILDS then
                    local code = Link.Code(name)
                    if codes[code] then
                        return nil
                    end
                    guilds[name], codes[code] = code, name
                    order[#order + 1] = name
                end
            end
            if #order < 2 then
                return nil
            end
            return { tag = tag, key = key, guilds = guilds, codes = codes, order = order,
                     line = trim(line:sub(at)) }
        end
    end
    return nil
end

-- The line for a configuration: the short form, unless guilds are named.
function Link.Build(tag, key, guilds)
    local out = Link.DIRECTIVE .. GuildOS.Alliance.NormalizeTag(tag) .. ":" .. tostring(key)
    if type(guilds) == "table" and #guilds > 0 then
        out = out .. ":" .. table.concat(guilds, ";")
    end
    return out
end

-- Pure. The hidden channel of a code: letters and digits only (the game refuses "-" in a channel name), 4 + 12 + 6
-- = 22 characters at most, under the 31 the game keeps of a channel's name.
Link.CHANNEL_HASH_LEN = 6
function Link.ChannelNameFor(tag, key)
    local n = GuildOS.Alliance.Hash("chan\0" .. tostring(key or ""))
    local out = ""
    for _ = 1, Link.CHANNEL_HASH_LEN do
        local d = n % 36
        out = B36:sub(d + 1, d + 1) .. out
        n = (n - d) / 36
    end
    return "GOSA" .. GuildOS.Alliance.NormalizeTag(tag) .. out
end

function Link.NewKey()
    local out = {}
    for i = 1, Link.KEY_LEN do
        local d = math.random(1, 62)
        out[i] = ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"):sub(d, d)
    end
    return table.concat(out)
end

-- Pure. The code in a public note, or nil.
function Link.NoteLine(note)
    local cfg = Link.Parse(note)
    return cfg and cfg.open and cfg.line or nil
end

-- Pure. A public note with `line` in it: the old code replaced, the rest of the
-- note kept while it fits the 31 bytes, dropped when it does not; taken out
-- when `line` is nil.
function Link.WithNoteLine(note, line)
    local rest = trim((tostring(note or ""):gsub("GOS=[%w]+:[%w]+", "")):gsub("%s+", " "))
    if not line then
        return rest
    end
    if rest ~= "" and #rest + 1 + #line <= Link.NOTE_MAX then
        return rest .. " " .. line
    end
    return line
end

-- What only who read the key can say about `name`. Carried by the data ops.
function Link.Proof(key, name)
    return string.format("%08x", GuildOS.Alliance.Hash(tostring(key) .. "\0" .. shortName(name):lower()))
end

-- The protocol of the lines this client says (#449). 2 carries the speaker's guild by name.
Link.PROTO = 2
Link.NAME_MAX = 48   -- bytes of a guild's name on the wire (the game's 24 letters, in UTF-8)

-- Pure. Whether `guild` can ride a protocol 2 line: one line of text, no "#", 1 to NAME_MAX bytes.
function Link.WireName(guild)
    if type(guild) ~= "string" or guild == "" or #guild > Link.NAME_MAX or guild:find("[#|%c]") then return nil end
    if guild:match("^%s") or guild:match("%s$") then return nil end
    return guild
end

-- The frame in front of a line's text: "g" .. code .. " " .. guild .. "# " (protocol 2), or protocol 1's
-- "G" .. code .. " " when there is no guild name to carry.
local function frame(kind, code, guild)
    local name = Link.WireName(guild)
    if name then return kind:lower() .. code .. " " .. name .. "# " end
    return kind:upper() .. code .. " "
end

-- A line on the channel: kind, guild code, text, and the speaker's guild when given (protocol 2).
function Link.Encode(kind, code, text, guild)
    return GuildOS:CutBytes(frame(kind, code, guild) .. tostring(text or ""), Link.MAX_LINE)
end

-- Pure. Where a cut at byte `at` of `s` falls inside an item, spell or other link (|c..|H..|h[..]|h|r): the byte
-- before that link starts, so a link is never split between two lines (a broken link is refused by the server and
-- the line lost). `at` itself when it is not inside one.
function Link.LinkSafeCut(s, at)
    local pos = 1
    while true do
        local a, b = s:find("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", pos)
        if not a or a > at then return at end
        if at < b then return a - 1 end
        pos = b + 1
    end
end

-- Pure. The channel lines for one line of text: the frame costs up to 5 + the guild's name, so a line of /g
-- near the game's 255 used to lose its end (issue #431). The rest goes in a second line, cut on a UTF-8
-- boundary and never inside a link, inside the same key press.
Link.MAX_PARTS = 3
function Link.Split(kind, code, text, guild)
    local out, rest = {}, tostring(text or "")
    local room = Link.MAX_LINE - #frame(kind, code, guild)
    while rest:match("%S") and #out < Link.MAX_PARTS do
        local piece = GuildOS:CutBytes(rest, room)
        if #rest > #piece then
            -- Prefer the last space, so a word is not split in two.
            local at = piece:match("^.*()%s")
            if at and at > room / 2 then piece = piece:sub(1, at - 1) end
            local safe = Link.LinkSafeCut(rest, #piece)
            if safe > 0 then piece = rest:sub(1, safe) end
        end
        out[#out + 1] = Link.Encode(kind, code, piece, guild)
        rest = rest:sub(#piece + 1):gsub("^%s+", "")
    end
    return out
end

-- Pure. A channel line: kind ("G" or "A"), code, text, the guild it names (protocol 2) and the protocol; nil
-- when it is not one of ours.
function Link.Decode(msg)
    if type(msg) ~= "string" then
        return nil
    end
    local kind, code, guild, text = msg:match("^([ga])(%w%w%w) ([^#]+)# (.+)$")
    if kind and Link.WireName(guild) then
        return kind:upper(), code, text, guild, 2
    end
    kind, code, text = msg:match("^([GA])(%w%w%w) (.+)$")
    if kind then return kind, code, text, nil, 1 end
    return nil
end

----------------------------------------------------------------------
-- The configuration in force
----------------------------------------------------------------------
-- What this guild holds: { line, rev, by }. `line` nil is a removal, kept
-- with its revision.
function Link:Store()
    GuildOS.db.allianceLink = GuildOS.db.allianceLink or { rev = 0 }
    return GuildOS.db.allianceLink
end

-- Pure. GOSGILD1's `alliance` as the site sends it ({ code, name, version }), held to its shape since the
-- inbox is untrusted: the code exactly ^GOS=[A-Z0-9]{1,12}:[A-Za-z0-9]{10}$ (the short form, no list), the name
-- one line of 2 to 48 characters with no bar, the version a whole number from 1. { line, name, version } or nil.
function Link.ReadSiteCode(v)
    if type(v) ~= "table" or type(v.code) ~= "string" or #v.code > 27 then return nil end
    local tag, key = v.code:match("^GOS=([A-Z0-9]+):([A-Za-z0-9]+)$")
    if not tag or #tag > GuildOS.Alliance.TAG_MAX or #key ~= Link.KEY_LEN then return nil end
    local version = v.version
    if type(version) ~= "number" or version ~= math.floor(version) or version < 1 or version > 2147483647 then
        return nil
    end
    local name = type(v.name) == "string" and not v.name:find("[|\r\n]") and GuildOS:SanitizeUserText(v.name, 144) or ""
    if GuildOS:Utf8Len(name) < 2 or GuildOS:Utf8Len(name) > 48 then return nil end
    return { line = v.code, name = name, version = version }
end

-- The site's code as the companion's block says it now: (code) when it names one, (false) when a block was read
-- and names none, (nil) when there is no block to read (no inbox, the companion off, another guild's, a week
-- old, or a field that is not the contract's, which is read as saying nothing rather than as an end).
function Link:SiteCode()
    local I = GuildOS.CompanionImport
    local block = I and I.GuildBlock and I:GuildBlock()
    if type(block) ~= "table" then return nil end
    if block.alliance == nil then return false end
    return Link.ReadSiteCode(block.alliance)
end

-- Brings the remembered site code up to the block's. True when it changed (and _Changed ran).
function Link:SyncSite()
    if not GuildOS.db then return false end
    local site = self:SiteCode()
    if site == nil then return false end
    local held = GuildOS.db.allianceLinkSite
    if site then
        if held and held.line == site.line and held.name == site.name and held.version == site.version then
            -- This client's own block names it now: no longer only a relay's, so its end is told (SyncSite).
            if held.relayed then held.relayed = nil end
            return false
        end
        GuildOS.db.allianceLinkSite = site
        Link.ForgetGone()
    else
        if not held then return false end
        GuildOS.db.allianceLinkSite = nil
        -- A code this client only had from an officer's relay: dropped here, never told to the guild as an end. A
        -- block that never named it cannot say it ended (it may be older than the alliance: audit #448 review).
        if held.relayed then
            self:_Changed()
            return true
        end
        -- Seen to end by this client's own block: the only end it ever tells the guild (PublishSite), and the only
        -- one that also keeps the same code in the guild's own copy (the GM's note) from coming back.
        GuildOS.db.allianceLinkSiteGone, GuildOS.db.allianceLinkSiteGoneV = held.line, held.version
        GuildOS.db.allianceLinkSiteGoneOwn, GuildOS.db.allianceLinkSiteGoneAt = true, GetServerTime()
    end
    self:_Changed()
    self:PublishSite()
    return true
end

-- The record of the site code that ended, cleared by a new one and by an officer's own paste.
function Link.ForgetGone()
    local db = GuildOS.db
    if db then
        db.allianceLinkSiteGone, db.allianceLinkSiteGoneV, db.allianceLinkSiteGoneOwn, db.allianceLinkSiteGoneAt = nil, nil, nil, nil
    end
end

-- An officer whose own client reads the site's block tells the guild what it says: the code, or the end of the one
-- this client's own block saw end (never a code somebody asked about: audit #448 review). Nobody else ever sends it
-- (the sync takes "site" from officers only).
Link.GONE_TELL = 30 * 86400
function Link:PublishSite()
    if not (GuildOS.SyncService and GuildOS:IsOfficer()) then return false end
    local site = self:SiteCode()
    if site == nil then return false end
    if site then
        GuildOS.SyncService:Publish("allylink", "site", { line = site.line, name = site.name, version = site.version },
            { priority = "ALERT" })
        return true
    end
    local db = GuildOS.db
    if type(db.allianceLinkSiteGone) ~= "string" or not db.allianceLinkSiteGoneOwn then return false end
    -- An end is told for GONE_TELL seconds: long enough for every member's client to log in once.
    if GetServerTime() - (tonumber(db.allianceLinkSiteGoneAt) or 0) > Link.GONE_TELL then return false end
    GuildOS.SyncService:Publish("allylink", "site", { gone = db.allianceLinkSiteGone, version = db.allianceLinkSiteGoneV },
        { priority = "ALERT" })
    return true
end

-- The site's code relayed by an officer of the guild. Never over this client's own block; checked as the block's
-- is (ReadSiteCode); an older key version, or the code the site ended at a version not above the end's, never
-- replaces what is held. An end ends only the SITE code held here that it names: never a pasted code or the GM
-- note's, and nothing at all when no site code is held.
function Link:_TakeSite(d, sender)
    self._siteHeard = (GetTime and GetTime()) or 0
    local db = GuildOS.db
    if type(d) ~= "table" or not db then return false end
    if type(sender) ~= "string" or not GuildOS:IsOfficerByName(sender) then return false end
    if self:SiteCode() ~= nil then return false end   -- this client reads the site itself
    local held = db.allianceLinkSite
    if d.gone ~= nil then
        if type(d.gone) ~= "string" or not held or held.line ~= d.gone then return false end
        -- The end carries the key version it ended; one without, or of an older version, ends nothing.
        if type(d.version) ~= "number" or d.version < held.version then return false end
        db.allianceLinkSite = nil
        db.allianceLinkSiteGone, db.allianceLinkSiteGoneV, db.allianceLinkSiteGoneOwn = d.gone, held.version, nil
        self:_Changed()
        return true
    end
    local site = Link.ReadSiteCode({ code = d.line, name = d.name, version = d.version })
    if not site then return false end
    if site.line == db.allianceLinkSiteGone and site.version <= (tonumber(db.allianceLinkSiteGoneV) or math.huge) then
        return false
    end
    if held and (site.version < held.version
                 or (held.line == site.line and held.name == site.name and held.version == site.version)) then
        return false
    end
    site.relayed = true   -- not this client's own block's: SyncSite never relays its end
    db.allianceLinkSite = site
    self:_Changed()
    return true
end

-- Somebody asked (at their login): an officer whose block says otherwise than what they hold answers, after a
-- moment, unless another officer answered first. `held` is the site code the asker holds ("" for none).
function Link:_AnswerSite(held)
    if not (GuildOS.SyncService and GuildOS:IsOfficer()) then return end
    local site = self:SiteCode()
    if site == nil then return end
    held = type(held) == "string" and held or ""
    if site and held == site.line then return end
    -- An end only for the very code this officer's own block saw end: an asker names whatever it likes, and a
    -- block that says nothing of alliances (none, or a stale one) is not the end of somebody else's code.
    local db = GuildOS.db
    if not site and not (held ~= "" and held == db.allianceLinkSiteGone and db.allianceLinkSiteGoneOwn) then return end
    local asked = (GetTime and GetTime()) or 0
    self._siteHeard = nil
    GuildOS.Compat.After(math.random() * self.ANSWER_MAX, function()
        if (self._siteHeard or -1) >= asked then return end
        self:PublishSite()
    end)
end

-- Whether the code in force is the site's.
function Link:FromSite()
    local cfg = self:Config()
    return cfg ~= nil and cfg.site == true
end

function Link:Config()
    local db = GuildOS.db
    local site = db and type(db.allianceLinkSite) == "table" and db.allianceLinkSite or nil
    local line, name, version
    if site and type(site.line) == "string" then
        line, name, version = site.line, site.name, site.version
    else
        line = db and db.allianceLink and db.allianceLink.line
        if line and db.allianceLinkSiteGoneOwn and line == db.allianceLinkSiteGone then
            line = nil   -- the alliance the site ended: not brought back by the copy it left in the note
        end
    end
    -- Compared field by field: every General and Trade line asks (through _Filter), and a string built
    -- here would be one more allocation per line (audit D2).
    if line ~= self._text or name ~= self._textName or version ~= self._textVersion then
        self._text, self._textName, self._textVersion = line, name, version
        self._config = line and Link.Parse(line) or nil
        if self._config and site then
            self._config.site, self._config.name, self._config.version = true, name, version
        end
    end
    return self._config
end

-- The guilds this client heard on the alliance `tag`'s channel: { [name] = lastSeen }.
function Link:Learned(tag)
    GuildOS.db.allianceLinkLearned = GuildOS.db.allianceLinkLearned or {}
    local all = GuildOS.db.allianceLinkLearned
    if tag and type(all[tag]) ~= "table" then
        all[tag] = {}
    end
    return tag and all[tag] or all
end

-- A guild heard on the channel holds the key: only who read it is there. Only
-- an open code keeps them: a listed one says its guilds itself.
function Link:Heard(guild)
    local cfg = self:Config()
    local mine = GuildOS.Alliance:MyGuildName()
    if not cfg or not cfg.open or type(guild) ~= "string" or guild == "" or guild == mine then
        return false
    end
    -- Whole or not at all: a name cut short would hash to another code and never name its lines again.
    if GuildOS:SanitizeUserText(guild, Link.NAME_MAX) ~= guild then
        return false
    end
    local learned = self:Learned(cfg.tag)
    local now = GetServerTime()
    local fresh = learned[guild] == nil
    if fresh or now - (tonumber(learned[guild]) or 0) > 3600 then
        learned[guild] = now
    end
    if fresh then
        self._learnRev = (self._learnRev or 0) + 1
        if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
    end
    return fresh
end

-- The guild a three-character code stands for, or nil.
function Link:GuildOfCode(code)
    local cfg = self:Config()
    if not cfg then return nil end
    if cfg.codes[code] then return cfg.codes[code] end
    local mine = GuildOS.Alliance:MyGuildName()
    if mine and Link.Code(mine) == code then return mine end
    for name in pairs(self:Learned(cfg.tag)) do
        if Link.Code(name) == code then return name end
    end
    return nil
end

-- The pact the rest of the alliance reads (Alliance:Get), or nil: only while
-- the guild holds a code, and a listed one names this guild.
function Link:Pact()
    local cfg = self:Config()
    local mine = GuildOS.Alliance:MyGuildName()
    if not cfg or not mine or (not cfg.open and not cfg.guilds[mine]) then
        return nil
    end
    local p = self._pact
    if not p or p.line ~= cfg.line or p.learnRev ~= (self._learnRev or 0) or p.mine ~= mine
       or p.name ~= (cfg.name or cfg.tag) or p.site ~= cfg.site or p.version ~= cfg.version then
        local guilds = { [mine] = { ambassadors = {}, joinedAt = 0 } }
        for _, name in ipairs(cfg.order) do
            guilds[name] = { ambassadors = {}, joinedAt = 0 }
        end
        if cfg.open then
            local learned, now = self:Learned(cfg.tag), GetServerTime()
            for name, seen in pairs(learned) do
                if now - (tonumber(seen) or 0) > Link.LEARN_TTL then
                    learned[name] = nil
                else
                    guilds[name] = { ambassadors = {}, joinedAt = 0 }
                end
            end
        end
        p = {
            source = "link", line = cfg.line, open = cfg.open, mine = mine,
            learnRev = self._learnRev or 0,
            tag = cfg.tag, name = cfg.name or cfg.tag, owner = cfg.order[1] or mine, revision = 0,
            guilds = guilds, key = cfg.key, site = cfg.site, version = cfg.version,
        }
        self._pact = p
    end
    -- A guild an officer blocked here: its lines are not shown on this account (Alliance:Block).
    GuildOS.db.allianceLinkBlocked = GuildOS.db.allianceLinkBlocked or {}
    p.blocked = GuildOS.db.allianceLinkBlocked
    return p
end

function Link:Active()
    return self:Pact() ~= nil
end

function Link:ChannelName()
    local cfg = self:Pact() and self:Config()
    if not cfg then return nil end
    if cfg._chan == nil then cfg._chan = Link.ChannelNameFor(cfg.tag, cfg.key) end
    return cfg._chan
end

function Link:ChannelIndex()
    local name = self:ChannelName()
    local id = name and GetChannelName and GetChannelName(name)
    return (id and id > 0) and id or nil
end

----------------------------------------------------------------------
-- Joining. Idempotent; AllianceChat's watchdog calls it.
----------------------------------------------------------------------
-- The channel this character joined, and with which key: { name, key }. Per character, since channel
-- membership is (the guild's db is shared by the account's characters).
local function me()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName() or "?", GetRealmName())
end
function Link:_Joined(set, value)
    GuildOS.db.allianceLinkJoined = GuildOS.db.allianceLinkJoined or {}
    local all = GuildOS.db.allianceLinkJoined
    if set then all[me()] = value end
    return all[me()]
end

-- Leaves the channel this character joined when it is not the one in force any more: the alliance ended, or
-- the key changed (a guild left, or the site reset it). True when it left one with the SAME name, which is
-- joined again with the new key on the next pass, once the server has let the old one go.
function Link:LeaveStale()
    if not GuildOS.db then return false end
    local j = self:_Joined()
    if type(j) ~= "table" or type(j.name) ~= "string" then return false end
    local name = self:ChannelName()
    local cfg = name and self:Config()
    if name and j.name:lower() == name:lower() and cfg and j.key == cfg.key then return false end
    self:_Joined(true, nil)
    if GetChannelName and (GetChannelName(j.name) or 0) > 0 then
        GuildOS.Compat.LeaveChannel(j.name)
        return name ~= nil and j.name:lower() == name:lower()
    end
    return false
end

-- The hidden channel as 1.27 to 1.43 named it, "GOSA" .. TAG with no hash of the key, is the client's own
-- channel from then: left once per character when it is joined and is not the channel in force. The tags are the
-- codes this guild holds (the site's, the guild's own copy), the only ones whose old channel it can be in.
function Link:LeaveUnhashed()
    local db = GuildOS.db
    if not db or not GetChannelName then return false end
    db.allianceLinkUnhashedLeft = type(db.allianceLinkUnhashedLeft) == "table" and db.allianceLinkUnhashedLeft or {}
    local mine = db.allianceLinkUnhashedLeft[me()] or {}
    local current = (self:ChannelName() or ""):lower()
    local left = false
    for _, line in ipairs({ type(db.allianceLinkSite) == "table" and db.allianceLinkSite.line or false,
                            db.allianceLink and db.allianceLink.line or false }) do
        local cfg = line and Link.Parse(line)
        local old = cfg and ("GOSA" .. cfg.tag)
        if old and not mine[old] and old:lower() ~= current and (GetChannelName(old) or 0) > 0 then
            GuildOS.Compat.LeaveChannel(old)
            mine[old] = true
            db.allianceLinkUnhashedLeft[me()] = mine
            left = true
        end
    end
    return left
end

function Link:EnsureJoined()
    self:SyncSite()
    self:LeaveUnhashed()
    if self:LeaveStale() then
        return false
    end
    local name = self:ChannelName()
    if not name then
        return false
    end
    if not self:ChannelIndex() then
        GuildOS.Compat.JoinPrivateChannel(name, self:Config().key)
    end
    local ok = self:ChannelIndex() ~= nil
    self:_JoinTried(name, ok)
    if ok then
        GuildOS.Compat.RemoveChannelFromFrames(name)
        local j = self:_Joined()
        if not (j and j.name == name and j.key == self:Config().key) then
            self:_Joined(true, { name = name, key = self:Config().key })
        end
    end
    return ok
end

-- Why the channel could not be joined, for the screens and /gos ally status (#449): { name, reason, t } or nil.
-- `reason` is the server's notice (WRONG_PASSWORD, INVALID_NAME, BANNED, ...) or NO_ANSWER when JOIN_TRIES joins in
-- a row went unanswered. Cleared the moment the channel is joined, or when the code in force names another one.
Link.JOIN_TRIES = 3
Link.JOIN_GAP = 15   -- seconds between two counted tries
function Link:JoinError()
    local e = self._joinError
    if e and e.name ~= self:ChannelName() then
        self._joinError, self._tries = nil, 0
        return nil
    end
    return e
end

function Link:_JoinTried(name, ok)
    if ok then
        if self._joinError then
            self._joinError = nil
            if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
        end
        self._tries, self._triedAt = 0, nil
        return
    end
    -- Tries are counted JOIN_GAP apart: the watchdog, the channel list's events and a login all call this, and a
    -- burst of them before the server answers is one try, not three.
    if self._triesFor ~= name then self._tries, self._triedAt, self._triesFor = 0, nil, name end
    local now = (GetTime and GetTime()) or 0
    if self._triedAt and now - self._triedAt < Link.JOIN_GAP then return end
    self._triedAt = now
    self._tries = (self._tries or 0) + 1
    if self._tries >= Link.JOIN_TRIES and not (self._joinError and self._joinError.name == name) then
        self._joinError = { name = name, reason = "NO_ANSWER", t = GetServerTime() }
        if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
    end
end

-- The server's notices about channels (CHAT_MSG_CHANNEL_NOTICE): ours are hidden from the chat frames (_Filter),
-- so a refusal is kept here, where the screens say it with its fix. `channel` is the event's base name, or its
-- "5. Name" string when the client gives no base name.
Link.NOTICE_OK = { YOU_JOINED = true, YOU_CHANGED = true, YOU_LEFT = true, SUSPENDED = true, THROTTLED = true }
function Link:_OnNotice(notice, channel)
    local name = self:ChannelName()
    if not name or type(notice) ~= "string" or type(channel) ~= "string" then return end
    local base = channel:match("^%d+%.%s*(.+)$") or channel
    if base:lower() ~= name:lower() then return end
    if Link.NOTICE_OK[notice] then
        if notice ~= "YOU_LEFT" and self._joinError then
            self._joinError = nil
            if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
        end
        return
    end
    self._joinError = { name = name, reason = notice, t = GetServerTime() }
    if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
end

-- What a join error means to the player, and what fixes it: one localized line.
function Link.JoinErrorText(e)
    if not e then return nil end
    if e.reason == "WRONG_PASSWORD" then
        return L["The alliance channel refused the key: the guilds do not hold the same code. Every guild needs the same one, from guildos.me or pasted by an officer."]
    elseif e.reason == "INVALID_NAME" then
        return L["The server refused the alliance channel's name. Use a shorter tag, letters and digits only, and save the code again."]
    elseif e.reason == "BANNED" then
        return L["This character was banned from the alliance channel."]
    end
    return L["The alliance channel did not answer. Try /reload; if it stays, send /gos ally status to the maintainer."]
end

----------------------------------------------------------------------
-- Out: only ever inside the player's key press
----------------------------------------------------------------------
function Link:Say(kind, text)
    local pact = self:Pact()
    local index = self:ChannelIndex()
    local mine = GuildOS.Alliance:MyGuildName()
    if not pact or not index or not mine then
        return false
    end
    local ok = false
    for _, part in ipairs(Link.Split(kind, Link.Code(mine), text, mine)) do
        if GuildOS.Compat.SendChannelMessage(part, index) then
            ok = true
            self.stats.sent = self.stats.sent + 1
        else
            -- A chat lockdown (combat on WoW: Forever) or a client that refused it: the game's own /g still went.
            self.stats.unsent = (self.stats.unsent or 0) + 1
        end
    end
    return ok
end

-- A line of /g the player just sent. Officer chat and the guild's other
-- channels never come here.
function Link:OnPlayerChat(chatType, text)
    if chatType == "GUILD" then
        self:Say("G", text)
    end
end

----------------------------------------------------------------------
-- In
----------------------------------------------------------------------
-- The guild a channel line came from, or nil. `author` is the channel's
-- sender, which nobody can forge, and only who read the key is on the channel:
-- that is the whole trust, as in GreenWall. No ambassador, no roster check: a
-- synced roster can be days old (somebody changed guild, a namesake on another
-- realm, the index is by short name) and a stale one used to drop real lines in
-- silence (issue #431). Our own guild's code counts only in the room: its /g we
-- already hear from the game itself.
function Link:GuildOfLine(code, author, kind, said)
    local pact = self:Pact()
    if not pact then
        return nil
    end
    local A = GuildOS.Alliance
    local mine = A:MyGuildName()
    local guild
    -- 1. The listed code names its guilds itself.
    local cfg = self:Config()
    if cfg and cfg.codes[code] then guild = cfg.codes[code] end
    -- 2. The line names its own guild (protocol 2, #449), believed when the name is the code's.
    said = Link.WireName(said)
    if not guild and said and Link.Code(said) == code then
        guild = (mine and GuildOS.SameGuildName(said, mine)) and mine or said
    end
    -- 3. Ours, then the guilds heard before.
    if not guild then guild = self:GuildOfCode(code) end
    -- 4. The alliance's directory from guildos.me names the guilds and their members (GOSALLY1): a guild whose code
    -- the line carries, or the speaker's own guild there, before the generic "Allied guild" (#449).
    if not guild then
        local dir = A.Directory and A:Directory() or {}
        for _, g in ipairs(dir) do
            if type(g) == "table" and type(g.guild) == "string" and Link.Code(g.guild) == code then
                guild = g.guild
                break
            end
        end
        if not guild and A._DirectoryRow then
            local _, dg = A:_DirectoryRow(Link.Speaker(author))
            if type(dg) == "string" and Link.Code(dg) == code then guild = dg end
        end
    end
    if not guild and pact.open then
        -- A guild we have not met: the speaker's own presence names it.
        local mesh = GuildOS.Mesh
        local fromMesh = mesh and mesh.GetPeerGuild and mesh:GetPeerGuild(shortName(author))
        if fromMesh and Link.Code(fromMesh) == code then
            guild = fromMesh
        else
            guild = L["Allied guild"]   -- shown all the same, never dropped
        end
    end
    if not guild or A:IsBlocked(guild) then
        return nil
    end
    if guild == mine and kind ~= "A" then
        return nil
    end
    if guild ~= L["Allied guild"] then
        self:Heard(guild)   -- the line came through the key: it holds it
        A:Heard(Link.Speaker(author), guild)   -- and its speaker is on now
    end
    return guild
end

-- Whether a channel sender is this character: by the name this client gives them (Speaker), so WoW: Forever's
-- "First-Surname" is the player's "First Surname", and a namesake on another realm is not the player.
function Link.IsMe(author)
    local player = GuildOS.Compat.PlayerName() or ""
    return Link.Speaker(author):lower() == player:lower()
end

-- The last line heard from each guild this session, for /gos ally status: { [guild] = { t, who, kind, proto } }.
Link.last = {}

function Link:_OnChannel(msg, author, lang, _, target, flags, _, _, chanBaseName,
                         _, lineID, guid)
    local name = self:ChannelName()
    if not name or type(chanBaseName) ~= "string" or chanBaseName:lower() ~= name:lower() then
        return
    end
    if GuildOS.Compat.IsSecret(msg, author) or not msg or not author then
        return
    end
    if Link.IsMe(author) then
        return
    end
    self.stats.heard = self.stats.heard + 1
    local kind, code, text, said, proto = Link.Decode(msg)
    local guild = kind and self:GuildOfLine(code, author, kind, said)
    if not guild then
        self.stats.dropped = self.stats.dropped + 1
        return
    end
    local who = Link.Speaker(author)
    Link.last[guild] = { t = GetServerTime(), who = who, kind = kind, proto = proto }
    if GuildOS.Compat.IsIgnored(author) then
        return
    end
    local chat = GuildOS.AllianceChat
    if chat and chat:HiddenSet()[chat.HiddenKey(who, text)] then
        return
    end
    if kind == "A" then
        if chat then chat:PushLine(who, guild, text) end
        return
    end
    if chat and not chat:Prefs().guildBridge then
        return
    end
    self.stats.shown = self.stats.shown + 1
    local tagged = "|cff" .. GuildOS.Alliance.GuildColorHex(guild) .. "[" .. guild .. "]|r " .. text
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and GuildOS.Compat.ChatFrameShows(f, "GUILD") then
            if not GuildOS.Compat.ReplayChatEvent(f, "CHAT_MSG_GUILD", tagged, author, lang, "", target, flags,
                                                  0, 0, "", 0, lineID, guid) and f.AddMessage then
                f:AddMessage(Link.FormatPlain(guild, author, text))
            end
        end
    end
    if GuildOS.GuildChat and GuildOS.GuildChat.AddAllied then
        local class
        if guid and GetPlayerInfoByGUID and not GuildOS.Compat.IsSecret(guid) then
            local _, c = GetPlayerInfoByGUID(guid)
            if not GuildOS.Compat.IsSecret(c) then class = c end
        end
        GuildOS.GuildChat:AddAllied(guild, { n = who, m = text, c = class })
    end
end

-- Somebody joined or left the hidden channel (CHAT_MSG_CHANNEL_JOIN / _LEAVE): only who holds the key is there, so
-- a member of an allied guild the directory names is on now before they say a word, and one who left is not (#449).
function Link:_OnPresence(event, author, chanBaseName)
    if not self:_Filter(chanBaseName) or type(author) ~= "string" or author == "" or Link.IsMe(author) then return end
    local A = GuildOS.Alliance
    local who = Link.Speaker(author)
    if event == "CHAT_MSG_CHANNEL_LEAVE" then
        A:Gone(who)
    else
        local _, guild = A:_DirectoryRow(who)
        if type(guild) ~= "string" or A:IsBlocked(guild) then return end
        A:Heard(who, guild)
    end
    if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
end

-- Where a frame has no handler to replay through: the line as /g reads.
function Link.FormatPlain(guild, author, text)
    local tag = "|cff" .. GuildOS.Alliance.GuildColorHex(guild) .. "[" .. guild .. "]|r"
    local who = tag .. " |Hplayer:" .. author .. "|h[" .. Link.Speaker(author) .. "]|h"
    local head = (type(CHAT_GUILD_GET) == "string" and CHAT_GUILD_GET:find("%s", 1, true))
        and CHAT_GUILD_GET:format(who) or ("[" .. L["Guild"] .. "] " .. who .. ": ")
    return head .. text
end

-- The channel's raw lines and its join/leave notices never print: the
-- channel is the addon's wire, not a room.
function Link:_Filter(chanBaseName)
    local name = self:ChannelName()
    -- The lengths first: lowering every General line would allocate a string for each (audit D2).
    return name ~= nil and type(chanBaseName) == "string" and #chanBaseName == #name
        and chanBaseName:lower() == name:lower()
end

----------------------------------------------------------------------
-- The code, kept by the guild
----------------------------------------------------------------------
-- Pure. Does an incoming copy replace what is held? Only a newer revision.
function Link.Newer(held, rev)
    return (tonumber(rev) or 0) > (tonumber(held and held.rev) or 0)
end

function Link:_Changed()
    self._pact = nil
    self:LeaveStale()
    if self:Pact() then
        self:EnsureJoined()
    end
    if GuildOS.AllianceChat then GuildOS.AllianceChat:_Notify() end
end

-- An officer saves `line` for the guild (nil turns the alliance off). A
-- button click; the guild gets it at once over GUILD.
function Link:SetCode(line)
    if not GuildOS:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    if line then
        line = trim(line)
        local cfg = Link.Parse(line)
        local mine = GuildOS.Alliance:MyGuildName()
        if not cfg then
            return false, L["That is not an alliance code."]
        end
        if not mine or (not cfg.open and not cfg.guilds[mine]) then
            return false, L["The code does not name this guild."]
        end
        line = cfg.line
    end
    -- The guild master's note is what reaches a member with nobody online (issue #431).
    local wrote, note = self:_WriteNote(line)
    if not wrote and note then
        return false, note
    end
    local held = self:Store()
    local rev = math.max(GetServerTime(), (tonumber(held.rev) or 0) + 1)
    local by = GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
    -- An officer's own paste, even of the code the site ended, is the guild's to have.
    Link.ForgetGone()
    held.line, held.rev, held.by = line, rev, by
    held.note = wrote or nil
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("allylink", "set", { line = line, rev = rev, by = by }, { priority = "ALERT" })
    end
    self:_Changed()
    return true, wrote
end

-- The guild master's roster row: name and public note, or nil before the
-- roster has come in.
function Link.GuildMaster()
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, _, rankIndex, _, _, _, note = GetGuildRosterInfo(i)
        if rankIndex == 0 and name then
            if GuildOS.Compat.IsSecret(name, note) then return nil end
            return name, note or ""
        end
    end
    return nil
end

-- Write `line` (nil: take it out) in the guild master's public note. True when
-- it is there; false with a reason when the note holds ANOTHER code this
-- client cannot change, since that code would win at every member's login;
-- false and no reason when the note is out of reach (the game lets an addon
-- write notes on TBC Anniversary only, or no permission, or no roster yet):
-- the officer pastes it there by hand and the sync carries it meanwhile.
-- The listed form never goes in a note: it does not fit.
function Link:_WriteNote(line)
    local cfg = line and Link.Parse(line)
    if line and not (cfg and cfg.open) then
        return false
    end
    local gm, note = Link.GuildMaster()
    if not gm then
        return false
    end
    if Link.NoteLine(note) == line then
        return true   -- already there
    end
    local nextNote = Link.WithNoteLine(note, line)
    if GuildOS.Compat.CanEditPublicNote() and GuildOS.Compat.SetGuildPublicNote(gm, nextNote) then
        self._noteSeen = nil
        return true
    end
    if Link.NoteLine(note) then
        return false, L["The guild master's public note holds another alliance code. Put this one there in its place."]
    end
    return false
end

-- The guild master's note, read whenever the roster comes in: a code there is
-- the guild's, written by somebody the game let edit notes, and when the note
-- CHANGES it wins over the addon's copy. A code that WAS read from it and is
-- gone is a removal; a new guild master whose note holds none is not, until an
-- officer writes it there.
function Link:ReadGuildMasterNote()
    local gm, note = Link.GuildMaster()
    if not gm then
        return false
    end
    local seen = gm .. "\0" .. note
    if seen == self._noteSeen then
        return false
    end
    local sameGM = self._noteSeen and self._noteSeen:match("^([^%z]*)") == gm
    self._noteSeen = seen
    local line = Link.NoteLine(note)
    local held = self:Store()
    if not line and held.line and not sameGM then
        -- A new guild master, or a note that never held it: an officer's client
        -- that may write notes puts it there by itself, so nobody has to.
        self:_RepairNote()
        return false
    end
    if line then
        if held.line == line then
            held.note = true   -- the same code: nothing to hand on
            return false
        end
    elseif not held.note or not held.line or not sameGM then
        return false
    end
    held.line, held.by, held.note = line, Link.NOTE_BY, line and true or nil
    held.rev = math.max(GetServerTime(), (tonumber(held.rev) or 0) + 1)
    self:_Changed()
    return true
end

-- Where the game lets this client write notes (TBC Anniversary) and it is an
-- officer's: the guild's open code goes in the guild master's note when that
-- note holds no code at all. Never over another code, never the listed form.
function Link:_RepairNote()
    local held = self:Store()
    local cfg = held.line and Link.Parse(held.line)
    if not cfg or not cfg.open or not GuildOS:IsOfficer() or not GuildOS.Compat.CanEditPublicNote() then
        return false
    end
    local gm, note = Link.GuildMaster()
    if not gm or Link.Parse(note) then
        return false
    end
    if GuildOS.Compat.SetGuildPublicNote(gm, Link.WithNoteLine(note, cfg.line)) then
        held.note = true
        self._noteSeen = nil
        return true
    end
    return false
end

-- A copy from the guild. `trusted` is an officer's own "set"; a relayed
-- "have" counts only when the officer it names is one on the roster.
function Link:_Take(d, sender, trusted)
    if type(d) ~= "table" or not Link.Newer(self:Store(), d.rev) then
        return false
    end
    local by = type(d.by) == "string" and d.by or nil
    if trusted then
        by = by or sender
    elseif not by then
        return false
    elseif by == Link.NOTE_BY then
        -- Relayed from the guild master's note: believed when our own copy of
        -- that note says the same, which needs the roster in.
        local gm, note = Link.GuildMaster()
        if not gm then
            self._pending = { d = d, sender = sender }
            return false
        end
        if Link.NoteLine(note) ~= d.line then
            return false
        end
    elseif not GuildOS:IsOfficerByName(by) then
        -- Right after login the roster is still empty and nobody reads as an
        -- officer: the copy waits for it instead of being lost (issue #431).
        if (GetNumGuildMembers and GetNumGuildMembers() or 0) == 0 then
            self._pending = { d = d, sender = sender }
        end
        return false
    end
    local line = type(d.line) == "string" and d.line or nil
    local mine = GuildOS.Alliance:MyGuildName()
    local cfg = line and Link.Parse(line)
    if line and (not cfg or not mine or (not cfg.open and not cfg.guilds[mine])) then
        return false
    end
    local held = self:Store()
    held.line, held.rev, held.by = cfg and cfg.line or nil, tonumber(d.rev), by
    if trusted then Link.ForgetGone() end   -- an officer's own "set", as SetCode
    self:_Changed()
    return true
end

function Link:OnSync(env, sender)
    local d = env and env.data
    if type(d) ~= "table" then return end
    if env.act == "set" then
        self:_Take(d, sender, true)
    elseif env.act == "have" then
        self._answered = (tonumber(d.rev) or 0)
        self:_Take(d, sender, false)
    elseif env.act == "site" then
        self:_TakeSite(d, sender)
    elseif env.act == "ask" then
        self:_AnswerSite(d.site)
        local held = self:Store()
        if Link.Newer(held, d.rev) then
            -- They hold something newer than ours: ask, and they answer.
            self:Ask()
            return
        end
        if not Link.Newer({ rev = d.rev }, held.rev) then
            return   -- nothing newer than what they hold
        end
        -- Wait a moment: whoever answers first saves everybody else the send.
        local want = tonumber(held.rev) or 0
        self._answered = nil
        GuildOS.Compat.After(math.random() * self.ANSWER_MAX, function()
            if (self._answered or -1) >= want then return end
            local now = self:Store()
            GuildOS.SyncService:Publish("allylink", "have", { line = now.line, rev = now.rev, by = now.by })
        end)
    end
end

function Link:Ask()
    local now = GetTime and GetTime() or 0
    if self._askedAt and now - self._askedAt < Link.ASK_GAP then
        return
    end
    if GuildOS.SyncService and IsInGuild and IsInGuild() then
        self._askedAt = now
        local site = GuildOS.db.allianceLinkSite
        GuildOS.SyncService:Publish("allylink", "ask", { rev = tonumber(self:Store().rev) or 0,
                                                         site = type(site) == "table" and site.line or "" })
        -- An officer logging in tells the guild what its own block says, once a session (#449): a member who
        -- logged in while no officer was on, and asked nobody, gets the code, or its end, now.
        if not self._toldSite and GuildOS:IsOfficer() then
            self._toldSite = true
            self:PublishSite()
        end
    end
end

-- What the panel offers: the line in force, or nil.
function Link:Suggest()
    local cfg = self:Config()
    if cfg and cfg.site then
        local held = GuildOS.db and GuildOS.db.allianceLink
        return held and held.line or nil   -- the site's key is never offered to copy
    end
    return cfg and cfg.line or nil
end

-- Where the code in force came from: "site" (this client's own block), "relay" (an officer's, for a member without
-- the companion), "note" (the guild master's public note), "pasted" (an officer), or nil with none.
function Link:Source()
    local cfg = self:Config()
    if not cfg then return nil end
    if cfg.site then
        local held = GuildOS.db and GuildOS.db.allianceLinkSite
        return (held and held.relayed) and "relay" or "site"
    end
    local held = self:Store()
    return held.by == Link.NOTE_BY and "note" or "pasted"
end

-- /gos ally status (#449): what to send the maintainer when the alliance fails. English, as the debug lines are.
-- Never the key: the channel's name, whether it is joined, the code's source and key version, the protocol, the
-- counts, the guilds heard and the last line of each.
function Link:StatusReport(at)
    at = at or GetServerTime()
    local out = {}
    local cfg = self:Config()
    local db = GuildOS.db or {}
    if not cfg then
        local gone = db.allianceLinkSiteGone and (" · site code ended at v" .. tostring(db.allianceLinkSiteGoneV or "?")) or ""
        out[1] = "alliance: none" .. gone .. " · companion block: " .. tostring(self:SiteCode() == nil and "none"
            or (self:SiteCode() and "names one" or "names none"))
        return out
    end
    local index = self:ChannelIndex()
    local err = self:JoinError()
    out[#out + 1] = string.format("alliance: %s [%s] · source: %s · key version: %s · protocol %d",
        tostring(cfg.name or cfg.tag), cfg.tag, tostring(self:Source()), tostring(cfg.version or "-"), Link.PROTO)
    out[#out + 1] = string.format("channel: %s · joined: %s%s", tostring(self:ChannelName() or "-"),
        index and ("yes (#" .. index .. ")") or "no", err and (" · refused: " .. err.reason) or "")
    local chat = GuildOS.AllianceChat
    local prefs = chat and chat:Prefs() or {}
    local st = self.stats
    out[#out + 1] = string.format("shared /g: %s · room: %s · sent %d · unsent %d · heard %d · shown %d · dropped %d",
        prefs.guildBridge and "shown" or "hidden", prefs.chat and "on" or "off",
        st.sent, st.unsent or 0, st.heard, st.shown, st.dropped)
    local names, seen = {}, {}
    for name in pairs(self:Learned(cfg.tag)) do names[#names + 1] = name; seen[name] = true end
    for name in pairs(Link.last) do if not seen[name] then names[#names + 1] = name end end
    table.sort(names)
    if #names == 0 then out[#out + 1] = "guilds heard: none yet" end
    for _, name in ipairs(names) do
        local last = Link.last[name]
        out[#out + 1] = "  " .. name .. ": " .. (last and string.format("last %s %ds ago from %s (protocol %d)",
            last.kind == "A" and "room line" or "/g line", at - last.t, last.who, last.proto or 1) or "not heard this session")
    end
    return out
end

function Link:StatusLine()
    local s = self.stats
    return string.format("%s · sent %d · heard %d · shown %d · dropped %d",
        tostring(self:ChannelName() or "-"), s.sent, s.heard, s.shown, s.dropped)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
Link.ROSTER_GAP = 5   -- seconds between two reads of the guild master's note

local function rosterRead()
    GuildOS:SafeCall(function()
        Link:SyncSite()
        Link:ReadGuildMasterNote()
        local wait = Link._pending
        if wait and (GetNumGuildMembers and GetNumGuildMembers() or 0) > 0 then
            Link._pending = nil
            Link:_Take(wait.d, wait.sender, false)
        end
    end)
end

function Link:Initialize()
    GuildOS.Compat.HookChatSend(function(chatType, text)
        GuildOS:SafeCall(function() Link:OnPlayerChat(chatType, text) end)
    end)
    local function hide(_, _, _, _, _, _, _, _, _, _, chanBaseName)
        return Link:_Filter(chanBaseName)
    end
    for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE",
                              "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
        GuildOS.Compat.AddChatFilter(event, hide)
    end
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_CHANNEL")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_CHANNEL_NOTICE")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_CHANNEL_JOIN")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_CHANNEL_LEAVE")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_ENTERING_WORLD")
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    GuildOS.Compat.RegisterEvent(f, "PLAYER_GUILD_UPDATE")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_CHANNEL" then
            -- Every General and Trade line comes here: only the hidden channel's costs a table (audit D2).
            if not Link:_Filter((select(9, ...))) then return end
            local args = { ... }
            GuildOS:SafeCall(function() Link:_OnChannel(unpack(args, 1, 12)) end)
        elseif event == "CHAT_MSG_CHANNEL_JOIN" or event == "CHAT_MSG_CHANNEL_LEAVE" then
            local _, author, _, _, _, _, _, _, base = ...
            if GuildOS.Compat.IsSecret(author, base) or not Link:_Filter(base) then return end
            GuildOS:SafeCall(function() Link:_OnPresence(event, author, base) end)
        elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
            local notice, _, _, channelString, _, _, _, _, base = ...
            if GuildOS.Compat.IsSecret(notice, channelString, base) then return end
            GuildOS:SafeCall(function() Link:_OnNotice(notice, (base ~= nil and base ~= "") and base or channelString) end)
        elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
            -- The guild master's row is a pass over the roster: at most one per ROSTER_GAP (audit D2).
            GuildOS:Coalesce("allylink.roster", Link.ROSTER_GAP, rosterRead)
        elseif not Link._asked then
            -- Once a session: whatever the guild has newer than ours (a code saved
            -- while we were away, or ours lost with a reinstall) comes now.
            Link._asked = true
            GuildOS.Compat.After(Link.ASK_DELAY, function() GuildOS:SafeCall(function() Link:Ask() end) end)
        end
    end)
    if GuildOS.SyncService then
        GuildOS.SyncService:On("allylink", function(env, sender) Link:OnSync(env, sender) end)
    end
end
