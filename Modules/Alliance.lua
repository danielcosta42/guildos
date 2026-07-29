----------------------------------------------------------------------
-- Guild OS - Alliance (cross-guild federation)
--
-- Lets 5 to 12 guilds federate WITHOUT merging: they share a chat channel, a
-- calendar, an LFG pool and a crafter directory while staying independent.
-- Design: docs/superpowers/specs/2026-07-29-alliance-design.md
--
-- WHY IT LOOKS LIKE THIS: there is no reliable cross-guild addon bus on this
-- client. CHANNEL addon sends are gated for timer traffic (see LibChehulMesh
-- header), YELL is zone- AND layer-local, GUILD only reaches your own guild.
-- The only reliable directed cross-guild bus is WHISPER. So the whole feature
-- is an EMBASSY model: one elected "bridge" client per guild whispers the other
-- guilds, and republishes what it learns inside its own guild over SyncService.
-- A regular member never sends anything cross-guild.
--
-- TRUST: the root of trust is a signed list of CHARACTER NAMES (ambassadors).
-- A whisper sender cannot be forged in WoW, so that is enough: no crypto, no
-- server. A change claimed on behalf of guild X is only accepted when it was
-- whispered by a name currently listed under X in the pact.
--
-- This file owns the pact, the trust checks, bridge election and the
-- INV/ACK/PACT/LEAVE wire ops. Domain data sync lives in AllianceSync.lua.
----------------------------------------------------------------------
local Alliance = {}
GuildOS.Alliance = Alliance
local L = BRutus.L

local LibSerialize = LibStub("LibSerialize")
local LibDeflate   = LibStub("LibDeflate")

-- Open protocol on the shared mesh transport, same family style as CraftNet
-- ("ChehulCraft"/CC1) and RecruitBeacon ("ChehulRecruit"/CR2).
Alliance.PREFIX = "ChehulAlly"
Alliance.PROTO  = "AL1"

-- Caps. Headroom over the expected 5 to 12 guilds, not a target.
Alliance.TAG_MAX         = 12
Alliance.NAME_MAX        = 32
Alliance.GUILD_NAME_MAX  = 24
Alliance.MAX_GUILDS      = 16
Alliance.MAX_AMBASSADORS = 8

-- Seconds the current bridge is held before a new winner may take over. Stops
-- the role from flapping while the guild roster churns on login.
Alliance.BRIDGE_HOLD = 30

local function shortName(name)
    return (Ambiguate and Ambiguate(name or "", "short")) or name
end

----------------------------------------------------------------------
-- Pure helpers. Everything below this line is deterministic and pinned by
-- /gos selftest, because several of these MUST agree across clients.
----------------------------------------------------------------------

-- "brcore" -> "BRCORE". Returns "" when nothing usable is left, which every
-- caller treats as "not a valid tag".
function Alliance.NormalizeTag(tag)
    local s = tostring(tag or ""):upper():gsub("[^A-Z0-9]", "")
    if #s > Alliance.TAG_MAX then
        s = s:sub(1, Alliance.TAG_MAX)
    end
    return s
end

-- The custom chat channel the alliance auto-joins. nil when the tag is unusable.
function Alliance.ChannelName(tag)
    local t = Alliance.NormalizeTag(tag)
    if t == "" then
        return nil
    end
    return "GOS" .. t
end

-- djb2. PART OF THE PROTOCOL: every client must compute the same number, or two
-- clients disagree about who the bridge is and the guild syncs twice (or never).
-- Do NOT replace this with anything that varies by client, locale or table order.
function Alliance.Hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 2147483648
    end
    return h
end

-- Pure. Given every online GuildOS client of this guild as "Name-Realm" keys,
-- return the one that acts as the bridge. Lowest hash wins; a collision is
-- broken by the key itself, so the answer never depends on table order.
function Alliance.ElectBridge(onlineKeys)
    if type(onlineKeys) ~= "table" then
        return nil
    end
    local best, bestHash
    for _, key in ipairs(onlineKeys) do
        if type(key) == "string" and key ~= "" then
            local h = Alliance.Hash(key)
            if not best or h < bestHash or (h == bestHash and key < best) then
                best, bestHash = key, h
            end
        end
    end
    return best
end

-- Pure. Hold `prev` until the hold window has passed, so the role does not
-- flap while people are still loading in.
function Alliance._DebouncedBridge(prev, candidate, prevAt, now, hold)
    if candidate == nil then
        return nil
    end
    if prev == nil then
        return candidate
    end
    if candidate == prev then
        return prev
    end
    if (now or 0) - (prevAt or 0) >= (hold or Alliance.BRIDGE_HOLD) then
        return candidate
    end
    return prev
end

local function countGuilds(pact)
    local n = 0
    if pact and type(pact.guilds) == "table" then
        for _ in pairs(pact.guilds) do
            n = n + 1
        end
    end
    return n
end

-- The wire copy of a pact. `blocked` is a LOCAL ignore list and must never
-- travel: leaking it would tell guild C that guild A blocked it.
function Alliance.SerializePact(pact)
    if type(pact) ~= "table" then
        return nil
    end
    local out = BRutus:DeepCopy(pact)
    out.blocked = nil
    return out
end

-- Validate + clamp a pact that arrived from the wire. Returns nil when the
-- shape is unusable. Always drops `blocked` on the way in too, so a hostile
-- sender cannot plant entries in our local ignore list.
function Alliance.SanitizePact(raw)
    if type(raw) ~= "table" or type(raw.guilds) ~= "table" then
        return nil
    end
    local tag = Alliance.NormalizeTag(raw.tag)
    if tag == "" then
        return nil
    end

    -- Deterministic truncation: sort the keys, then keep the owner first so a
    -- pact never loses the one guild that is allowed to remove others.
    local owner = BRutus:SanitizeUserText(raw.owner, Alliance.GUILD_NAME_MAX)
    local keys = {}
    for name in pairs(raw.guilds) do
        if type(name) == "string" then
            keys[#keys + 1] = name
        end
    end
    table.sort(keys)
    if owner ~= "" then
        for i, name in ipairs(keys) do
            if name == owner and i > 1 then
                table.remove(keys, i)
                table.insert(keys, 1, name)
                break
            end
        end
    end

    local out = {
        tag      = tag,
        name     = BRutus:SanitizeUserText(raw.name, Alliance.NAME_MAX),
        owner    = owner,
        revision = tonumber(raw.revision) or 0,
        guilds   = {},
    }

    local kept = 0
    for _, name in ipairs(keys) do
        if kept >= Alliance.MAX_GUILDS then
            break
        end
        local clean = BRutus:SanitizeUserText(name, Alliance.GUILD_NAME_MAX)
        local entry = raw.guilds[name]
        if clean ~= "" and type(entry) == "table" and not out.guilds[clean] then
            local ambassadors = {}
            if type(entry.ambassadors) == "table" then
                for _, amb in ipairs(entry.ambassadors) do
                    if #ambassadors >= Alliance.MAX_AMBASSADORS then
                        break
                    end
                    local a = BRutus:SanitizeUserText(shortName(amb), Alliance.GUILD_NAME_MAX)
                    if a ~= "" then
                        ambassadors[#ambassadors + 1] = a
                    end
                end
            end
            out.guilds[clean] = {
                ambassadors = ambassadors,
                joinedAt    = tonumber(entry.joinedAt) or 0,
                addedBy     = BRutus:SanitizeUserText(entry.addedBy, Alliance.GUILD_NAME_MAX),
            }
            kept = kept + 1
        end
    end

    if kept == 0 then
        return nil
    end
    return out
end

-- Which of two pacts wins. Highest revision, then (to guarantee two clients
-- that tie still CONVERGE instead of each keeping its own copy forever) the
-- one with more guilds, then the lower owner name. Ties at second granularity
-- are already vanishingly rare since revision is GetServerTime() of the edit.
function Alliance.ResolvePact(current, incoming)
    if type(incoming) ~= "table" then
        return current
    end
    if type(current) ~= "table" then
        return incoming
    end
    local cr, ir = tonumber(current.revision) or 0, tonumber(incoming.revision) or 0
    if ir > cr then
        return incoming
    end
    if ir < cr then
        return current
    end
    local cn, inn = countGuilds(current), countGuilds(incoming)
    if inn > cn then
        return incoming
    end
    if inn < cn then
        return current
    end
    if tostring(incoming.owner or "") < tostring(current.owner or "") then
        return incoming
    end
    return current
end

-- Is `playerName` allowed to speak for `guildName`? This is the whole trust
-- model: the caller must have taken `playerName` from the comm envelope sender,
-- never from a field inside the payload.
function Alliance.IsAmbassador(pact, guildName, playerName)
    if type(pact) ~= "table" or type(pact.guilds) ~= "table" then
        return false
    end
    local entry = pact.guilds[guildName or ""]
    if type(entry) ~= "table" or type(entry.ambassadors) ~= "table" then
        return false
    end
    local who = shortName(playerName):lower()
    if who == "" then
        return false
    end
    for _, amb in ipairs(entry.ambassadors) do
        if shortName(amb):lower() == who then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- Wire codec. The blob must never contain '|' because the frame is split on
-- it; EncodeForWoWAddonChannel guarantees that (it escapes 0x7C among others).
----------------------------------------------------------------------
function Alliance.Encode(tbl)
    if type(tbl) ~= "table" then
        return nil
    end
    local ok, ser = pcall(function() return LibSerialize:Serialize(tbl) end)
    if not ok or type(ser) ~= "string" then
        return nil
    end
    local packed = LibDeflate:CompressDeflate(ser, { level = 9 })
    if not packed then
        return nil
    end
    return LibDeflate:EncodeForWoWAddonChannel(packed)
end

function Alliance.Decode(str)
    if type(str) ~= "string" or str == "" then
        return nil
    end
    local packed = LibDeflate:DecodeForWoWAddonChannel(str)
    if not packed then
        return nil
    end
    local ser = LibDeflate:DecompressDeflate(packed)
    if not ser then
        return nil
    end
    local ran, ok, tbl = pcall(function() return LibSerialize:Deserialize(ser) end)
    if not ran or not ok or type(tbl) ~= "table" then
        return nil
    end
    return tbl
end

----------------------------------------------------------------------
-- Live state
----------------------------------------------------------------------
function Alliance:Get()
    return (BRutus.db and BRutus.db.alliance) or nil
end

function Alliance:MyGuildName()
    local name = GetGuildInfo("player")
    if not name or name == "" then
        return nil
    end
    return name
end

function Alliance:MyKey()
    return BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
end

function Alliance:IsMemberGuild(guildName)
    local pact = self:Get()
    return (pact and pact.guilds and pact.guilds[guildName or ""]) ~= nil
end

function Alliance:IsBlocked(guildName)
    local pact = self:Get()
    return (pact and pact.blocked and pact.blocked[guildName or ""]) == true
end

-- Which member guild a character speaks for, resolved from the pact's ambassador
-- lists. `sender` MUST come from the comm envelope, never from a payload field.
-- nil means "not authorised to speak for anyone", which is the safe default.
function Alliance:GuildOfSender(sender, pact)
    pact = pact or self:Get()
    if not pact or type(pact.guilds) ~= "table" then
        return nil
    end
    for guildName in pairs(pact.guilds) do
        if Alliance.IsAmbassador(pact, guildName, sender) then
            return guildName
        end
    end
    return nil
end

-- Every online guildmate we know runs Guild OS, as "Name-Realm" keys. This is
-- the candidate set for bridge election, and it is identical on every client
-- because it is derived from the shared guild roster plus synced member data.
function Alliance:OnlineGuildKeys()
    local keys = {}
    if not IsInGuild or not IsInGuild() then
        return keys
    end
    local members = (BRutus.db and BRutus.db.members) or {}
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if name and isOnline then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            if members[key] and members[key].addonVersion then
                keys[#keys + 1] = key
            end
        end
    end
    return keys
end

function Alliance:CurrentBridge()
    local now = (GetServerTime and GetServerTime()) or time()
    local candidate = Alliance.ElectBridge(self:OnlineGuildKeys())
    local resolved = Alliance._DebouncedBridge(
        self._bridge, candidate, self._bridgeAt or 0, now, Alliance.BRIDGE_HOLD)
    if resolved ~= self._bridge then
        self._bridge = resolved
        self._bridgeAt = now
    end
    return resolved
end

function Alliance:AmBridge()
    return self:CurrentBridge() == self:MyKey()
end

-- Which ALLIED guild a character belongs to, from the cached roster snapshots.
-- nil for our own guildmates and for strangers. Feeds the chat tags and the
-- pug inspector, neither of which needs any new sync to work.
function Alliance:GuildOfMember(name)
    local sync = GuildOS.AllianceSync
    if not sync or not sync.MemberIndex then
        return nil
    end
    local short = shortName(name or ""):lower()
    if short == "" then
        return nil
    end
    local hit = sync:MemberIndex()[short]
    local guild = hit and hit.guild
    if not guild or guild == self:MyGuildName() then
        return nil
    end
    return guild
end

-- What the alliance already knows about an allied character, from the cached
-- roster snapshot: guild, class, level, spec, completed attunements. nil for
-- strangers and for our own guildmates.
function Alliance:MemberInfo(name)
    local sync = GuildOS.AllianceSync
    if not sync or not sync.MemberIndex then
        return nil
    end
    local short = shortName(name or ""):lower()
    local hit = short ~= "" and sync:MemberIndex()[short]
    if not hit or hit.guild == self:MyGuildName() then
        return nil
    end
    local row = hit.row or {}
    return {
        guild       = hit.guild,
        class       = row.c,
        level       = row.l,
        spec        = row.s,
        professions = row.p,
        attunements = row.a,
        main        = row.m,
    }
end

-- A player of `guildName` we have positive evidence is online RIGHT NOW, so a
-- whisper does not print "No player named X is currently playing" to the user.
-- Evidence comes from the realm-wide presence mesh, where Guild OS clients in an
-- alliance advertise their guild (see Mesh:BuildCaps).
function Alliance:PeerTarget(guildName)
    if not guildName or guildName == "" then
        return nil
    end
    local net = _G.ChehulNet
    if not net or not net.Peers then
        return nil
    end
    local mesh = GuildOS.Mesh
    local best, bestTs
    for short, peer in pairs(net:Peers()) do
        local theirGuild = mesh and mesh.GetPeerGuild and mesh:GetPeerGuild(short)
        if theirGuild == guildName and (not bestTs or (peer.ts or 0) > bestTs) then
            best, bestTs = short, peer.ts or 0
        end
    end
    return best
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------
function Alliance:Send(op, tbl, target)
    local mesh = _G.ChehulMesh
    if not mesh or not target or target == "" then
        return false
    end
    local blob = Alliance.Encode(tbl)
    if not blob then
        return false
    end
    return mesh:Whisper(self.PREFIX, self.PROTO .. "|" .. op .. "|" .. blob, target) and true or false
end

-- Whisper an op to the ambassadors of `guildName` that the presence mesh says
-- are online, capped so one action never fans out to a dozen whispers. Returns
-- how many were reached, so a caller can tell the user "nobody was online"
-- instead of silently dropping their request.
function Alliance:SendToAmbassadors(guildName, op, data, max)
    local pact = self:Get()
    local entry = pact and pact.guilds[guildName or ""]
    if not entry or type(entry.ambassadors) ~= "table" then
        return 0
    end
    local sent = 0
    for _, amb in ipairs(entry.ambassadors) do
        if sent >= (max or 3) then
            break
        end
        if self:IsPeerOnline(amb) and self:Send(op, data, amb) then
            sent = sent + 1
        end
    end
    return sent
end

-- Push the current pact to every other member guild. `allowBlind` whispers a
-- listed ambassador even without presence evidence: acceptable for a rare,
-- user-initiated action, never for the periodic tick.
function Alliance:BroadcastPact(allowBlind)
    local pact = self:Get()
    if not pact then
        return
    end
    local mine = self:MyGuildName()
    local wire = Alliance.SerializePact(pact)
    for guildName, entry in pairs(pact.guilds) do
        if guildName ~= mine and not self:IsBlocked(guildName) then
            local target = self:PeerTarget(guildName)
            if not target and allowBlind and type(entry.ambassadors) == "table" then
                target = entry.ambassadors[1]
            end
            if target then
                self:Send("PACT", wire, target)
            end
        end
    end
end

----------------------------------------------------------------------
-- Officer actions
----------------------------------------------------------------------
function Alliance:Create(tag, name)
    if not BRutus:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    if self:Get() then
        return false, L["This guild is already in an alliance."]
    end
    local myGuild = self:MyGuildName()
    if not myGuild then
        return false, L["You are not in a guild."]
    end
    local t = Alliance.NormalizeTag(tag)
    if t == "" then
        return false, L["The alliance tag must contain letters or numbers."]
    end
    local now = (GetServerTime and GetServerTime()) or time()
    local me = shortName(UnitName("player"))
    local display = BRutus:SanitizeUserText(name, Alliance.NAME_MAX)
    BRutus.db.alliance = {
        tag      = t,
        name     = (display ~= "" and display) or t,
        owner    = myGuild,
        revision = now,
        guilds   = {
            [myGuild] = { ambassadors = { me }, joinedAt = now, addedBy = me },
        },
        blocked  = {},
    }
    return true
end

function Alliance:Invite(officerName)
    if not BRutus:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    local pact = self:Get()
    if not pact then
        return false, L["This guild is not in an alliance yet."]
    end
    local target = BRutus:SanitizeUserText(officerName, Alliance.GUILD_NAME_MAX)
    if target == "" then
        return false, L["Name an officer of the guild you want to invite."]
    end
    local myGuild = self:MyGuildName()
    if not Alliance.IsAmbassador(pact, myGuild, UnitName("player")) then
        return false, L["Only an alliance ambassador can invite."]
    end
    self._invitesSent = self._invitesSent or {}
    self._invitesSent[shortName(target):lower()] = (GetServerTime and GetServerTime()) or time()
    if not self:Send("INV", Alliance.SerializePact(pact), target) then
        return false, L["Could not reach the mesh."]
    end
    return true
end

function Alliance:Leave()
    local pact = self:Get()
    if not pact then
        return false, L["This guild is not in an alliance yet."]
    end
    if not BRutus:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    local myGuild = self:MyGuildName()
    if not Alliance.IsAmbassador(pact, myGuild, UnitName("player")) then
        return false, L["Only an alliance ambassador can do that."]
    end
    local now = (GetServerTime and GetServerTime()) or time()
    local notice = { guild = myGuild, revision = now }
    for guildName, entry in pairs(pact.guilds) do
        if guildName ~= myGuild then
            local target = self:PeerTarget(guildName)
            if not target and type(entry.ambassadors) == "table" then
                target = entry.ambassadors[1]
            end
            if target then
                self:Send("LEAVE", notice, target)
            end
        end
    end
    BRutus.db.alliance = nil
    BRutus.db.allianceData = nil
    return true
end

function Alliance:RemoveGuild(guildName)
    local pact = self:Get()
    if not pact then
        return false, L["This guild is not in an alliance yet."]
    end
    if not BRutus:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    local myGuild = self:MyGuildName()
    if pact.owner ~= myGuild then
        return false, L["Only the founding guild can remove another guild."]
    end
    local clean = BRutus:SanitizeUserText(guildName, Alliance.GUILD_NAME_MAX)
    if clean == myGuild or not pact.guilds[clean] then
        return false, L["That guild is not in the alliance."]
    end
    -- Tell the guild BEFORE dropping it. BroadcastPact iterates pact.guilds, so
    -- once the entry is gone the removed guild is unreachable and would sit on a
    -- stale pact forever, still heartbeating at peers who silently drop it.
    local ejected = pact.guilds[clean]
    local target = self:PeerTarget(clean)
    if not target and type(ejected.ambassadors) == "table" then
        target = ejected.ambassadors[1]
    end
    if target then
        self:Send("EJECT", { guild = clean, by = myGuild }, target)
    end

    pact.guilds[clean] = nil
    pact.revision = (GetServerTime and GetServerTime()) or time()
    if BRutus.db.allianceData then
        BRutus.db.allianceData[clean] = nil
    end
    self:BroadcastPact(true)
    return true
end

function Alliance:Block(guildName)
    local pact = self:Get()
    if not pact then
        return false, L["This guild is not in an alliance yet."]
    end
    local clean = BRutus:SanitizeUserText(guildName, Alliance.GUILD_NAME_MAX)
    if clean == "" then
        return false, L["Name the guild to block."]
    end
    pact.blocked = pact.blocked or {}
    pact.blocked[clean] = true
    if BRutus.db.allianceData then
        BRutus.db.allianceData[clean] = nil
    end
    return true
end

function Alliance:Unblock(guildName)
    local pact = self:Get()
    if not pact or not pact.blocked then
        return false, L["This guild is not in an alliance yet."]
    end
    pact.blocked[BRutus:SanitizeUserText(guildName, Alliance.GUILD_NAME_MAX)] = nil
    return true
end

----------------------------------------------------------------------
-- Receiving. Every op is WHISPER-only, which kills party/yell injection, and
-- authority always comes from the envelope `sender`, never from the payload.
----------------------------------------------------------------------
Alliance.ops = {}   -- [op] = function(data, sender, senderGuild); AllianceSync extends this

function Alliance:RegisterOp(op, fn)
    if type(op) == "string" and type(fn) == "function" then
        Alliance.ops[op] = fn
    end
end

function Alliance:OnMessage(payload, sender, dist)
    if type(payload) ~= "string" or not sender then
        return
    end
    if dist ~= "WHISPER" then
        return   -- alliance traffic is directed only; drop anything broadcast
    end
    local proto, op, blob = strsplit("|", payload, 3)
    if proto ~= self.PROTO or not op then
        return   -- unknown protocol version: ignore silently, like the rest of the mesh
    end
    if shortName(sender) == UnitName("player") then
        return
    end
    local data = Alliance.Decode(blob)
    if type(data) ~= "table" then
        return
    end

    -- INV and ACK are the two ops that CANNOT be gated on pact membership: an
    -- invite arrives before any pact exists, and the accepting guild is by
    -- definition not in our pact yet. Their authority comes from a human
    -- clicking Accept (INV) and from an invite we ourselves sent (ACK).
    if op == "INV" then
        self:_OnInvite(data, sender)
        return
    end
    if op == "ACK" then
        self:_OnAck(data, sender)
        return
    end
    -- A join request comes from a guild that is by definition NOT in our pact,
    -- so it cannot pass the membership gate either. Human-gated like INV.
    if op == "REQ" then
        self:_OnJoinRequest(data, sender)
        return
    end

    local senderGuild = self:GuildOfSender(sender)
    if not senderGuild or self:IsBlocked(senderGuild) then
        return
    end
    if op == "PACT" then
        self:_OnPact(data, sender, senderGuild)
    elseif op == "LEAVE" then
        self:_OnLeave(sender, senderGuild)
    elseif op == "EJECT" then
        self:_OnEject(data, senderGuild)
    else
        local fn = Alliance.ops[op]
        if fn then
            BRutus:SafeCall(fn, data, sender, senderGuild)
        end
    end
end

Alliance.INVITE_COOLDOWN = 30

function Alliance:_OnInvite(raw, sender)
    if self:Get() then
        return   -- already federated; a second pact would need a human decision anyway
    end
    local pact = Alliance.SanitizePact(raw)
    if not pact then
        return
    end
    -- The inviter must be an ambassador inside the pact they are offering.
    local theirGuild = self:GuildOfSender(sender, pact)
    if not theirGuild then
        return
    end
    local now = (GetServerTime and GetServerTime()) or time()
    self._invitePrompts = self._invitePrompts or {}
    local last = self._invitePrompts[shortName(sender):lower()]
    if last and (now - last) < Alliance.INVITE_COOLDOWN then
        return
    end
    self._invitePrompts[shortName(sender):lower()] = now
    if not BRutus:IsOfficer() then
        return   -- only an officer can answer for the guild
    end
    StaticPopup_Show("GUILDOS_ALLY_INVITE",
        string.format(L["%s of %s invites your guild into the alliance %s."],
            shortName(sender), theirGuild, pact.name or pact.tag),
        nil, { pact = pact, sender = sender })
end

function Alliance:AcceptInvite(pact, sender)
    local myGuild = self:MyGuildName()
    if not myGuild or self:Get() or not pact then
        return
    end
    local now = (GetServerTime and GetServerTime()) or time()
    local me = shortName(UnitName("player"))
    pact.blocked = {}
    pact.guilds[myGuild] = pact.guilds[myGuild]
        or { ambassadors = { me }, joinedAt = now, addedBy = shortName(sender) }
    pact.revision = now
    BRutus.db.alliance = pact
    self:Send("ACK", { guild = myGuild, ambassadors = { me } }, sender)
    BRutus:Print(string.format(L["Joined the alliance %s."], pact.name or pact.tag))
end

function Alliance:_OnAck(data, sender)
    if not BRutus:IsOfficer() then
        return
    end
    self._invitesSent = self._invitesSent or {}
    if not self._invitesSent[shortName(sender):lower()] then
        return   -- unsolicited: we never invited this character
    end
    local pact = self:Get()
    if not pact then
        return
    end
    local guild = BRutus:SanitizeUserText(data.guild, Alliance.GUILD_NAME_MAX)
    if guild == "" or self:IsBlocked(guild) then
        return
    end
    local count = 0
    for _ in pairs(pact.guilds) do
        count = count + 1
    end
    if not pact.guilds[guild] and count >= Alliance.MAX_GUILDS then
        BRutus:Print(L["The alliance is full."])
        return
    end
    local ambassadors = {}
    if type(data.ambassadors) == "table" then
        for _, amb in ipairs(data.ambassadors) do
            if #ambassadors >= Alliance.MAX_AMBASSADORS then
                break
            end
            local a = BRutus:SanitizeUserText(shortName(amb), Alliance.GUILD_NAME_MAX)
            if a ~= "" then
                ambassadors[#ambassadors + 1] = a
            end
        end
    end
    -- The accepting character is always an ambassador of its own guild, even if
    -- the payload forgot to list it. Identity comes from the envelope.
    local senderShort = shortName(sender)
    local listed = false
    for _, a in ipairs(ambassadors) do
        if a:lower() == senderShort:lower() then
            listed = true
            break
        end
    end
    if not listed then
        table.insert(ambassadors, 1, senderShort)
    end

    local now = (GetServerTime and GetServerTime()) or time()
    pact.guilds[guild] = {
        ambassadors = ambassadors,
        joinedAt    = now,
        addedBy     = shortName(UnitName("player")),
    }
    pact.revision = now
    self._invitesSent[senderShort:lower()] = nil
    BRutus:Print(string.format(L["%s joined the alliance."], guild))
    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:AddSystem(string.format(L["%s joined the alliance."], guild), "info")
    end
    self:BroadcastPact(true)
end

function Alliance:_OnPact(raw, _sender, senderGuild)
    local incoming = Alliance.SanitizePact(raw)
    if not incoming then
        return
    end
    local current = self:Get()
    -- A pact change is only ever accepted DIRECT from an ambassador of a member
    -- guild, never relayed. GuildOfSender already enforced that.
    if not senderGuild then
        return
    end
    local winner = Alliance.ResolvePact(current, incoming)
    if winner == current then
        return
    end
    -- Our own guild must never be dropped by someone else's copy, and the local
    -- ignore list is ours alone.
    local myGuild = self:MyGuildName()
    if myGuild and current and current.guilds[myGuild] and not winner.guilds[myGuild] then
        winner.guilds[myGuild] = current.guilds[myGuild]
    end
    winner.blocked = (current and current.blocked) or {}
    BRutus.db.alliance = winner
end

function Alliance:_OnLeave(_sender, senderGuild)
    local pact = self:Get()
    if not pact or not pact.guilds[senderGuild] then
        return
    end
    pact.guilds[senderGuild] = nil
    pact.revision = (GetServerTime and GetServerTime()) or time()
    if BRutus.db.allianceData then
        BRutus.db.allianceData[senderGuild] = nil
    end
    BRutus:Print(string.format(L["%s left the alliance."], senderGuild))
    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:AddSystem(string.format(L["%s left the alliance."], senderGuild), "info")
    end
end

----------------------------------------------------------------------
-- Read model for the UI. Rule 10: the panel renders this and owns no logic.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Ambassadors
--
-- Without this a guild ends up with exactly ONE ambassador (whoever created or
-- accepted the pact) and freezes the day that person stops playing: it can no
-- longer invite, leave, post, or approve anything. Add/remove is an ambassador
-- action; `claim` is the escape hatch for the guild that already lost theirs.
----------------------------------------------------------------------

-- Pure. May a plain officer claim ambassadorship? Only when NOT ONE listed
-- ambassador is still on the guild roster, i.e. the guild genuinely lost them
-- all. `rosterShort` is a set of lowercased short names currently in the guild.
function Alliance._CanClaimAmbassador(ambassadors, rosterShort)
    if type(ambassadors) ~= "table" or type(rosterShort) ~= "table" then
        return false
    end
    if #ambassadors == 0 then
        return true
    end
    for _, amb in ipairs(ambassadors) do
        if rosterShort[tostring(amb):lower()] then
            return false   -- at least one is still here; no vacancy
        end
    end
    return true
end

function Alliance:_GuildRosterShortSet()
    local set = {}
    local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, total do
        local name = GetGuildRosterInfo(i)
        if name then
            set[(name:match("^([^-]+)") or name):lower()] = true
        end
    end
    return set
end

function Alliance:_MyEntry()
    local pact = self:Get()
    local mine = self:MyGuildName()
    return pact and mine and pact.guilds[mine] or nil, mine
end

function Alliance:AddAmbassador(name)
    local entry = self:_MyEntry()
    if not entry then
        return false, L["This guild is not in an alliance yet."]
    end
    if not self:CanAdminister() then
        return false, L["Only an alliance ambassador can do that."]
    end
    local clean = BRutus:SanitizeUserText(shortName(name), Alliance.GUILD_NAME_MAX)
    if clean == "" then
        return false, L["Name the character to make an ambassador."]
    end
    if not self:_GuildRosterShortSet()[clean:lower()] then
        return false, L["That character is not in this guild."]
    end
    for _, amb in ipairs(entry.ambassadors) do
        if amb:lower() == clean:lower() then
            return false, string.format(L["%s is already an ambassador."], clean)
        end
    end
    if #entry.ambassadors >= Alliance.MAX_AMBASSADORS then
        return false, L["This guild already has the maximum number of ambassadors."]
    end
    entry.ambassadors[#entry.ambassadors + 1] = clean
    self:Get().revision = (GetServerTime and GetServerTime()) or time()
    self:BroadcastPact(true)
    return true
end

function Alliance:RemoveAmbassador(name)
    local entry = self:_MyEntry()
    if not entry then
        return false, L["This guild is not in an alliance yet."]
    end
    if not self:CanAdminister() then
        return false, L["Only an alliance ambassador can do that."]
    end
    local clean = shortName(BRutus:SanitizeUserText(name, Alliance.GUILD_NAME_MAX))
    if #entry.ambassadors <= 1 then
        -- Removing the last one would lock the guild out of its own pact.
        return false, L["A guild must keep at least one ambassador."]
    end
    for i, amb in ipairs(entry.ambassadors) do
        if amb:lower() == clean:lower() then
            table.remove(entry.ambassadors, i)
            self:Get().revision = (GetServerTime and GetServerTime()) or time()
            self:BroadcastPact(true)
            return true
        end
    end
    return false, string.format(L["%s is not an ambassador."], clean)
end

function Alliance:ClaimAmbassador()
    local entry = self:_MyEntry()
    if not entry then
        return false, L["This guild is not in an alliance yet."]
    end
    if not BRutus:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    if not Alliance._CanClaimAmbassador(entry.ambassadors, self:_GuildRosterShortSet()) then
        return false, L["This guild still has an ambassador in the roster."]
    end
    entry.ambassadors[#entry.ambassadors + 1] = shortName(UnitName("player"))
    self:Get().revision = (GetServerTime and GetServerTime()) or time()
    self:BroadcastPact(true)
    return true
end

-- Class and level of our OWN guildmates, cached and rebuilt on roster change.
-- Scanning GetGuildRosterInfo per chat line would be O(roster) per message.
function Alliance:_GuildInfoMap()
    if self._rosterInfo then
        return self._rosterInfo
    end
    local map = {}
    local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, total do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            map[(name:match("^([^-]+)") or name):lower()] = { class = classFile, level = level }
        end
    end
    self._rosterInfo = map
    return map
end

-- Everything we can say about someone speaking in the alliance channel,
-- whether they are an ally or one of ours. MemberInfo deliberately answers nil
-- for our own guild (it exists to identify ALLIES), so the chat needs this
-- wider view or nobody from our own guild would ever be coloured.
function Alliance:SpeakerInfo(name)
    local short = shortName(name or "")
    if short == "" then
        return nil
    end

    local allied = self:MemberInfo(short)
    if allied then
        allied.own = false
        return allied
    end

    local myGuild = self:MyGuildName()
    local key = BRutus:GetPlayerKey(short, GetRealmName())
    local m = BRutus.db and BRutus.db.members and BRutus.db.members[key]
    if m then
        return {
            guild = myGuild,
            class = m.class,
            level = m.level,
            spec  = type(m.spec) == "table" and m.spec.tree or nil,
            own   = true,
        }
    end

    -- In the guild but with no synced data yet: the roster still knows them.
    local hit = self:_GuildInfoMap()[short:lower()]
    if hit then
        return { guild = myGuild, class = hit.class, level = hit.level, own = true }
    end
    return nil
end

-- Is this character visible on the realm-wide presence mesh right now?
function Alliance:IsPeerOnline(name)
    local net = _G.ChehulNet
    if not net or not net.Peers then
        return false
    end
    return net:Peers()[shortName(name or "")] ~= nil
end

-- Everyone in the ALLIANCE (not our own guild) who can craft `itemId`, from
-- the cached directory. Works while the crafter is offline, which is the whole
-- point of syncing the directory instead of querying live.
function Alliance:FindCrafters(itemId)
    local sync = GuildOS.AllianceSync
    local pact = self:Get()
    local out = {}
    if not sync or not pact then
        return out
    end
    local mine = self:MyGuildName()
    local store = (BRutus.db and BRutus.db.allianceData) or {}
    for guildName in pairs(pact.guilds) do
        if guildName ~= mine and not self:IsBlocked(guildName) then
            local entry = store[guildName] and store[guildName].craft
            if entry and entry.data then
                for _, c in ipairs(GuildOS.AllianceSync._ReadCraft(entry.data, itemId)) do
                    out[#out + 1] = {
                        name   = c.name,
                        guild  = guildName,
                        prof   = c.prof,
                        online = self:IsPeerOnline(c.name),
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.guild ~= b.guild then return a.guild < b.guild end
        return a.name < b.name
    end)
    return out
end

-- How many members of `guildName` the presence mesh can currently see. This is
-- an UNDERCOUNT by construction (only players running Guild OS broadcast), and
-- the UI must say so rather than passing it off as the real online count.
function Alliance:SeenCount(guildName)
    local net = _G.ChehulNet
    local mesh = GuildOS.Mesh
    if not net or not net.Peers or not mesh or not mesh.GetPeerGuild then
        return 0
    end
    local n = 0
    for short in pairs(net:Peers()) do
        if mesh:GetPeerGuild(short) == guildName then
            n = n + 1
        end
    end
    return n
end

function Alliance:Summary()
    local pact = self:Get()
    if not pact then
        return nil
    end
    local sync = GuildOS.AllianceSync
    local chat = GuildOS.AllianceChat
    local mine = self:MyGuildName()

    local names = {}
    for guildName in pairs(pact.guilds) do
        names[#names + 1] = guildName
    end
    table.sort(names)

    local out = {
        name      = pact.name or pact.tag,
        tag       = pact.tag,
        owner     = pact.owner,
        bridge    = self:CurrentBridge(),
        amBridge  = self:AmBridge(),
        channel   = Alliance.ChannelName(pact.tag),
        connected = chat and chat:IsConnected() or false,
        guilds    = {},
        members   = 0,
        seen      = 0,
    }

    for _, guildName in ipairs(names) do
        local entry = pact.guilds[guildName]
        local roster = sync and sync:Remote(guildName, "roster")
        local count = (roster and type(roster.data) == "table" and #roster.data) or 0
        local seen = self:SeenCount(guildName)
        out.members = out.members + count
        out.seen = out.seen + seen
        out.guilds[#out.guilds + 1] = {
            name        = guildName,
            isOwner     = (guildName == pact.owner),
            isMine      = (guildName == mine),
            ambassadors = entry.ambassadors or {},
            members     = count,
            seen        = seen,
            ts          = roster and roster.ts or nil,
        }
    end

    out.blocked = {}
    if pact.blocked then
        for guildName in pairs(pact.blocked) do
            out.blocked[#out.blocked + 1] = guildName
        end
        table.sort(out.blocked)
    end
    return out
end

-- True when this character may run pact-level actions (invite, kick, leave).
function Alliance:CanAdminister()
    local pact = self:Get()
    if not pact or not BRutus:IsOfficer() then
        return false
    end
    return Alliance.IsAmbassador(pact, self:MyGuildName(), UnitName("player"))
end

-- We were removed from the pact. Only the OWNER guild may do this, and the
-- payload must name us, so a random ally cannot evict anybody.
function Alliance:_OnEject(data, senderGuild)
    local pact = self:Get()
    if not pact or senderGuild ~= pact.owner then
        return
    end
    local mine = self:MyGuildName()
    local named = BRutus:SanitizeUserText(data and data.guild, Alliance.GUILD_NAME_MAX)
    if not mine or named ~= mine then
        return
    end
    BRutus.db.alliance = nil
    BRutus.db.allianceData = nil
    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:Leave()
    end
    BRutus:Print(string.format(L["%s removed this guild from the alliance."], senderGuild))
end

----------------------------------------------------------------------
-- Join requests: the reverse of an invite. A guild that knows the alliance tag
-- asks an officer of a member guild to bring them in, instead of waiting to be
-- found. Still ends in the normal human-approved invite flow.
----------------------------------------------------------------------
function Alliance:RequestJoin(tag, officerName)
    if not BRutus:IsOfficer() then
        return false, L["Only officers can do that."]
    end
    if self:Get() then
        return false, L["This guild is already in an alliance."]
    end
    local myGuild = self:MyGuildName()
    if not myGuild then
        return false, L["You are not in a guild."]
    end
    local wanted = Alliance.NormalizeTag(tag)
    if wanted == "" then
        return false, L["Name the alliance tag you want to join."]
    end
    local target = BRutus:SanitizeUserText(officerName, Alliance.GUILD_NAME_MAX)
    if target == "" then
        return false, L["Name an officer of a guild already in that alliance."]
    end
    if not self:Send("REQ", { guild = myGuild, tag = wanted }, target) then
        return false, L["Could not reach the mesh."]
    end
    return true
end

function Alliance:_OnJoinRequest(data, sender)
    local pact = self:Get()
    if not pact or not self:CanAdminister() then
        return   -- only an ambassador of a real pact can act on this
    end
    if Alliance.NormalizeTag(data and data.tag) ~= pact.tag then
        return   -- they asked for a different alliance
    end
    local guild = BRutus:SanitizeUserText(data and data.guild, Alliance.GUILD_NAME_MAX)
    if guild == "" or self:IsMemberGuild(guild) or self:IsBlocked(guild) then
        return
    end
    local now = (GetServerTime and GetServerTime()) or time()
    self._reqPrompts = self._reqPrompts or {}
    local last = self._reqPrompts[shortName(sender):lower()]
    if last and (now - last) < Alliance.INVITE_COOLDOWN then
        return
    end
    self._reqPrompts[shortName(sender):lower()] = now
    StaticPopup_Show("GUILDOS_ALLY_REQUEST",
        string.format(L["%s of %s asks to join the alliance. Invite them?"],
            shortName(sender), guild),
        nil, { sender = sender })
end

----------------------------------------------------------------------
-- Alliance bulletin
--
-- WHY IT SYNCS TWICE: a post has to reach the whole GUILD before it can reach
-- the alliance, because only the bridge builds our guild's outbound snapshot.
-- A post written by an ambassador who is not the bridge would otherwise sit on
-- that one client forever. So a post goes out on the guild channel first
-- (officer domain "allyboard"), and the bridge then publishes the agreed list.
----------------------------------------------------------------------
Alliance.BOARD_MAX      = 20
Alliance.BOARD_TEXT_MAX = 200

function Alliance:BoardStore()
    BRutus.db.allianceBoard = BRutus.db.allianceBoard or {}
    return BRutus.db.allianceBoard
end

-- Pure. Newest `cap` posts, oldest first. Ids are time-prefixed hex, so sorting
-- by id is chronological and the resulting order is identical on every client,
-- which is what keeps the change fingerprint stable.
function Alliance._BuildBoard(posts, cap)
    local out = {}
    if type(posts) ~= "table" then
        return out
    end
    cap = tonumber(cap) or Alliance.BOARD_MAX
    local sorted = {}
    for _, p in ipairs(posts) do
        if type(p) == "table" and p.id then
            sorted[#sorted + 1] = p
        end
    end
    table.sort(sorted, function(a, b) return tostring(a.id) < tostring(b.id) end)
    for i = math.max(1, #sorted - cap + 1), #sorted do
        out[#out + 1] = {
            id = sorted[i].id,
            t  = sorted[i].text,
            b  = sorted[i].by,
            ts = tonumber(sorted[i].ts) or 0,
        }
    end
    return out
end

local function trimBoard(store)
    while #store > Alliance.BOARD_MAX do
        table.remove(store, 1)
    end
end

function Alliance:PostBoard(text)
    local pact = self:Get()
    if not pact then
        return false, L["This guild is not in an alliance yet."]
    end
    if not self:CanAdminister() then
        return false, L["Only an alliance ambassador can do that."]
    end
    local clean = BRutus:SanitizeUserText(text, Alliance.BOARD_TEXT_MAX)
    if clean == "" then
        return false, L["Write something first."]
    end
    local now = (GetServerTime and GetServerTime()) or time()
    local post = {
        id   = string.format("%X%04X", now, math.random(0, 0xFFFF)),
        text = clean,
        by   = shortName(UnitName("player")),
        ts   = now,
    }
    local store = self:BoardStore()
    store[#store + 1] = post
    trimBoard(store)
    if BRutus.SyncService then
        BRutus.SyncService:Publish("allyboard", "post", { post = post })
    end
    if GuildOS.AllianceSync then
        GuildOS.AllianceSync:RefreshLocal("board")
    end
    return true
end

function Alliance:OnBoardSync(env)
    local post = env and env.data and env.data.post
    if type(post) ~= "table" or not post.id then
        return
    end
    local store = self:BoardStore()
    for _, p in ipairs(store) do
        if p.id == post.id then
            return   -- already have it
        end
    end
    store[#store + 1] = {
        id   = post.id,
        text = BRutus:SanitizeUserText(post.text, Alliance.BOARD_TEXT_MAX),
        by   = BRutus:SanitizeUserText(post.by, Alliance.GUILD_NAME_MAX),
        ts   = tonumber(post.ts) or 0,
    }
    table.sort(store, function(a, b) return tostring(a.id) < tostring(b.id) end)
    trimBoard(store)
    if GuildOS.AllianceSync then
        GuildOS.AllianceSync:RefreshLocal("board")
    end
end

-- Every post visible to us: our own guild's plus every allied guild's, newest
-- first, each tagged with the guild that wrote it.
function Alliance:BoardPosts()
    local out = {}
    local pact = self:Get()
    if not pact then
        return out
    end
    local mine = self:MyGuildName()
    for _, p in ipairs(self:BoardStore()) do
        out[#out + 1] = { id = p.id, text = p.text, by = p.by, ts = p.ts, guild = mine }
    end
    local sync = GuildOS.AllianceSync
    local store = (BRutus.db and BRutus.db.allianceData) or {}
    for guildName in pairs(pact.guilds) do
        if guildName ~= mine and not self:IsBlocked(guildName) and sync then
            local entry = store[guildName] and store[guildName].board
            if entry and type(entry.data) == "table" then
                for _, p in ipairs(entry.data) do
                    out[#out + 1] = { id = p.id, text = p.t, by = p.b, ts = p.ts, guild = guildName }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return tostring(a.id) > tostring(b.id)
    end)
    return out
end

----------------------------------------------------------------------
-- Slash command surface (/gos ally ...)
----------------------------------------------------------------------
function Alliance:PrintStatus()
    local pact = self:Get()
    if not pact then
        BRutus:Print(L["This guild is not in an alliance yet."])
        if BRutus:IsOfficer() then
            BRutus:Print(L["Start one with: /gos ally create <tag> <name>"])
        end
        return
    end

    local names = {}
    for guildName in pairs(pact.guilds) do
        names[#names + 1] = guildName
    end
    table.sort(names)
    BRutus:Print(string.format(L["Alliance %s [%s] - %d guilds"],
        pact.name or pact.tag, pact.tag, #names))
    BRutus:Print(string.format(L["Bridge: %s"], self:CurrentBridge() or L["nobody online"]))

    local sync = GuildOS.AllianceSync
    local mine = self:MyGuildName()
    for _, guildName in ipairs(names) do
        local entry = sync and sync:Remote(guildName, "roster")
        local count = (entry and type(entry.data) == "table" and #entry.data) or 0
        local age = (entry and entry.ts and BRutus:TimeAgo(entry.ts)) or L["never"]
        local suffix = ""
        if guildName == pact.owner then
            suffix = " " .. L["(owner)"]
        end
        if guildName == mine then
            suffix = suffix .. " " .. L["(you)"]
        end
        BRutus:Print(string.format("  %s%s - %d, %s", guildName, suffix, count, age))
    end

    if pact.blocked and next(pact.blocked) then
        local blocked = {}
        for guildName in pairs(pact.blocked) do
            blocked[#blocked + 1] = guildName
        end
        table.sort(blocked)
        BRutus:Print(string.format(L["Blocked: %s"], table.concat(blocked, ", ")))
    end
end

function Alliance:HandleCommand(args)
    -- Parse with match, never strtrim(gsub(...)): gsub returns a second value
    -- that strtrim takes as its charset argument, which silently truncated
    -- every argument at the digit 1 in an earlier feature.
    local input = strtrim(args or "")
    local verb, rest = input:match("^(%S+)%s*(.*)$")
    verb = (verb and verb:lower()) or ""
    rest = strtrim(rest or "")

    if verb == "" then
        return self:PrintStatus()
    end

    local ok, err
    if verb == "create" then
        local tag, name = rest:match("^(%S+)%s*(.*)$")
        if not tag then
            return BRutus:Print(L["Usage: /gos ally create <tag> <name>"])
        end
        ok, err = self:Create(tag, name)
        if ok then
            BRutus:Print(string.format(L["Alliance %s created. Invite a guild with /gos ally invite <officer>"],
                self:Get().name))
        end
    elseif verb == "invite" then
        ok, err = self:Invite(rest)
        if ok then
            BRutus:Print(string.format(L["Invite sent to %s."], rest))
        end
    elseif verb == "leave" then
        ok, err = self:Leave()
        if ok then
            BRutus:Print(L["Left the alliance."])
        end
    elseif verb == "kick" or verb == "remove" then
        ok, err = self:RemoveGuild(rest)
        if ok then
            BRutus:Print(string.format(L["%s removed from the alliance."], rest))
        end
    elseif verb == "amb" or verb == "ambassador" then
        local sub, who = rest:match("^(%S*)%s*(.*)$")
        sub = (sub and sub:lower()) or ""
        who = strtrim(who or "")
        if sub == "add" then
            ok, err = self:AddAmbassador(who)
            if ok then BRutus:Print(string.format(L["%s is now an ambassador."], who)) end
        elseif sub == "remove" or sub == "rem" then
            ok, err = self:RemoveAmbassador(who)
            if ok then BRutus:Print(string.format(L["%s is no longer an ambassador."], who)) end
        elseif sub == "claim" then
            ok, err = self:ClaimAmbassador()
            if ok then BRutus:Print(L["You are now an ambassador of this guild."]) end
        else
            local entry = self:_MyEntry()
            if not entry then
                return BRutus:Print(L["This guild is not in an alliance yet."])
            end
            BRutus:Print(string.format(L["Ambassadors: %s"], table.concat(entry.ambassadors, ", ")))
            return BRutus:Print(L["Usage: /gos ally amb [add|remove|claim] <name>"])
        end
    elseif verb == "request" or verb == "join" then
        local tag, who = rest:match("^(%S*)%s*(.*)$")
        ok, err = self:RequestJoin(tag, strtrim(who or ""))
        if ok then
            BRutus:Print(string.format(L["Join request sent to %s."], strtrim(who or "")))
        end
    elseif verb == "block" then
        ok, err = self:Block(rest)
        if ok then
            BRutus:Print(string.format(L["Ignoring %s locally. The pact is unchanged."], rest))
        end
    elseif verb == "unblock" then
        ok, err = self:Unblock(rest)
        if ok then
            BRutus:Print(string.format(L["No longer ignoring %s."], rest))
        end
    else
        return BRutus:Print(L["Usage: /gos ally [create|invite|request|amb|leave|kick|block|unblock]"])
    end

    if not ok and err then
        BRutus:Print(err)
    end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
local function registerPopups()
    if StaticPopupDialogs["GUILDOS_ALLY_INVITE"] then
        return
    end
    StaticPopupDialogs["GUILDOS_ALLY_INVITE"] = {
        text = "%s",
        button1 = L["Accept"],
        button2 = L["Decline"],
        OnAccept = function(self)
            local d = self and self.data
            if d then
                GuildOS.Alliance:AcceptInvite(d.pact, d.sender)
            end
        end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs["GUILDOS_ALLY_REQUEST"] = {
        text = "%s",
        button1 = L["Invite"],
        button2 = L["Decline"],
        OnAccept = function(self)
            local d = self and self.data
            if not d then return end
            local ok, err = GuildOS.Alliance:Invite(d.sender)
            if not ok and err then BRutus:Print(err) end
        end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function Alliance:Initialize()
    self:_RegisterTests()
    registerPopups()
    -- The roster class/level cache is only valid until the roster changes.
    local rf = CreateFrame("Frame")
    rf:RegisterEvent("GUILD_ROSTER_UPDATE")
    rf:SetScript("OnEvent", function() GuildOS.Alliance._rosterInfo = nil end)
    if BRutus.SyncService then
        BRutus.SyncService:On("allyboard", function(env) GuildOS.Alliance:OnBoardSync(env) end)
    end
    local mesh = _G.ChehulMesh
    if mesh and not self._registered then
        self._registered = true
        mesh:Register(self.PREFIX, function(payload, sender, dist)
            GuildOS.Alliance:OnMessage(payload, sender, dist)
        end)
    end
end

----------------------------------------------------------------------
-- Self tests (run with /gos selftest)
----------------------------------------------------------------------
local function samplePact()
    return {
        tag = "BRCORE", name = "Nucleo BR", owner = "Guild A", revision = 100,
        guilds = {
            ["Guild A"] = { ambassadors = { "Chehul" } },
            ["Guild B"] = { ambassadors = { "Beltrano" } },
        },
        blocked = { ["Guild C"] = true },
    }
end

function Alliance:_RegisterTests()
    if not BRutus.SelfTest then
        return
    end

    BRutus.SelfTest:Register("alliance.normalize_tag", function()
        if Alliance.NormalizeTag("brcore") ~= "BRCORE" then return false, "not uppercased" end
        if Alliance.NormalizeTag(" br-core! ") ~= "BRCORE" then return false, "punctuation kept" end
        if Alliance.NormalizeTag("abcdefghijklmno") ~= "ABCDEFGHIJKL" then return false, "not capped at 12" end
        if Alliance.NormalizeTag("...") ~= "" then return false, "empty result expected" end
        if Alliance.NormalizeTag(nil) ~= "" then return false, "nil must not error" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.channel_name", function()
        if Alliance.ChannelName("brcore") ~= "GOSBRCORE" then return false, "bad channel name" end
        if Alliance.ChannelName("...") ~= nil then return false, "empty tag must yield nil" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.hash_is_stable", function()
        local a = Alliance.Hash("Chehul-Nefarian")
        if a ~= Alliance.Hash("Chehul-Nefarian") then return false, "not deterministic" end
        if a < 0 then return false, "must be non-negative" end
        if Alliance.Hash("Chehul-Nefarian") == Alliance.Hash("Chehul-Ragnaros") then
            return false, "realm must affect the hash"
        end
        if Alliance.Hash("") ~= 5381 then return false, "djb2 seed changed" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.elect_bridge", function()
        local keys = { "Ann-R", "Bob-R", "Cid-R" }
        local first = Alliance.ElectBridge(keys)
        if not first then return false, "no bridge elected" end
        if Alliance.ElectBridge({ "Cid-R", "Ann-R", "Bob-R" }) ~= first then
            return false, "election depends on input order"
        end
        for _, k in ipairs(keys) do
            if Alliance.Hash(k) < Alliance.Hash(first) then return false, "not the lowest hash" end
        end
        if Alliance.ElectBridge({}) ~= nil then return false, "empty list must yield nil" end
        if Alliance.ElectBridge(nil) ~= nil then return false, "nil must not error" end
        if Alliance.ElectBridge({ "Solo-R" }) ~= "Solo-R" then return false, "single candidate" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.bridge_debounce", function()
        local r = Alliance._DebouncedBridge(nil, "Ann-R", 0, 100, 30)
        if r ~= "Ann-R" then return false, "first election must apply immediately" end
        r = Alliance._DebouncedBridge("Ann-R", "Bob-R", 100, 110, 30)
        if r ~= "Ann-R" then return false, "must hold the previous bridge inside the window" end
        r = Alliance._DebouncedBridge("Ann-R", "Bob-R", 100, 140, 30)
        if r ~= "Bob-R" then return false, "must switch after the hold window" end
        r = Alliance._DebouncedBridge("Ann-R", nil, 100, 140, 30)
        if r ~= nil then return false, "no candidates means no bridge" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.serialize_strips_blocked", function()
        local out = Alliance.SerializePact(samplePact())
        if out.blocked ~= nil then return false, "blocked leaked onto the wire" end
        if out.guilds["Guild A"] == nil then return false, "guilds lost" end
        local src = samplePact()
        out.guilds["Guild A"].ambassadors[1] = "Tampered"
        if src.guilds["Guild A"].ambassadors[1] ~= "Chehul" then return false, "not a deep copy" end
        if Alliance.SerializePact(nil) ~= nil then return false, "nil must not error" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.sanitize_drops_blocked", function()
        local out = Alliance.SanitizePact(samplePact())
        if not out then return false, "valid pact rejected" end
        if out.blocked ~= nil then return false, "incoming blocked was kept" end
        if out.guilds["Guild A"].ambassadors[1] ~= "Chehul" then return false, "ambassador lost" end
        if Alliance.SanitizePact(nil) ~= nil then return false, "nil must be rejected" end
        if Alliance.SanitizePact({ tag = "" }) ~= nil then return false, "tagless pact must be rejected" end
        if Alliance.SanitizePact({ tag = "X", guilds = {} }) ~= nil then return false, "empty pact must be rejected" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.sanitize_clamps", function()
        local p = samplePact()
        for i = 1, 40 do p.guilds["Filler " .. i] = { ambassadors = { "Amb" .. i } } end
        for i = 1, 30 do p.guilds["Guild A"].ambassadors[i] = "Amb" .. i end
        local out = Alliance.SanitizePact(p)
        if not out then return false, "clamped pact rejected outright" end
        local n = 0
        for _ in pairs(out.guilds) do n = n + 1 end
        if n > Alliance.MAX_GUILDS then return false, "guild cap not enforced: " .. n end
        if not out.guilds["Guild A"] then return false, "owner guild was truncated away" end
        if #out.guilds["Guild A"].ambassadors > Alliance.MAX_AMBASSADORS then
            return false, "ambassador cap not enforced"
        end
        return true
    end)

    BRutus.SelfTest:Register("alliance.resolve_pact", function()
        local cur = samplePact()
        local newer = samplePact(); newer.revision = 200
        if Alliance.ResolvePact(cur, newer).revision ~= 200 then return false, "newer must win" end
        local older = samplePact(); older.revision = 50
        if Alliance.ResolvePact(cur, older).revision ~= 100 then return false, "older must lose" end
        local tie = samplePact(); tie.owner = "Guild B"
        if Alliance.ResolvePact(cur, tie).owner ~= "Guild A" then
            return false, "tie must keep the lower owner name"
        end
        local bigger = samplePact(); bigger.guilds["Guild C"] = { ambassadors = { "Zeca" } }
        if Alliance.ResolvePact(cur, bigger).guilds["Guild C"] == nil then
            return false, "tie must prefer the fuller pact"
        end
        if Alliance.ResolvePact(nil, newer).revision ~= 200 then return false, "no current pact" end
        if Alliance.ResolvePact(cur, nil).revision ~= 100 then return false, "no incoming pact" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.encode_roundtrip", function()
        local src = { tag = "BRCORE", revision = 42, guilds = { ["G A"] = { ambassadors = { "Ann" } } } }
        local wire = Alliance.Encode(src)
        if type(wire) ~= "string" or wire == "" then return false, "encode produced nothing" end
        if wire:find("|", 1, true) then return false, "wire payload must not contain a pipe" end
        local back = Alliance.Decode(wire)
        if not back then return false, "decode failed" end
        if back.tag ~= "BRCORE" or back.revision ~= 42 then return false, "fields lost" end
        if back.guilds["G A"].ambassadors[1] ~= "Ann" then return false, "nested table lost" end
        if Alliance.Decode("not a real payload") ~= nil then return false, "garbage must decode to nil" end
        if Alliance.Decode(nil) ~= nil then return false, "nil must not error" end
        if Alliance.Encode(nil) ~= nil then return false, "encoding nil must not error" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.claim_ambassador", function()
        local C = Alliance._CanClaimAmbassador
        -- Somebody listed is still in the guild: no vacancy.
        if C({ "Chehul" }, { chehul = true }) then return false, "claim allowed while the ambassador is present" end
        if C({ "Chehul", "Fulano" }, { fulano = true }) then return false, "one present is enough to block" end
        -- Every listed ambassador has left the guild: the seat is open.
        if not C({ "Chehul" }, { someoneelse = true }) then return false, "vacancy not detected" end
        if not C({}, { anyone = true }) then return false, "empty list must allow a claim" end
        -- Case must not matter: the roster set is lowercased, the list is not.
        if C({ "CHEHUL" }, { chehul = true }) then return false, "comparison is case sensitive" end
        if C(nil, {}) then return false, "nil list must not error" end
        if C({ "A" }, nil) then return false, "nil roster must not error" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.board_build", function()
        local posts = {}
        for i = 1, 30 do
            posts[#posts + 1] = { id = string.format("%08X", i), text = "p" .. i, by = "Ann", ts = i }
        end
        local out = Alliance._BuildBoard(posts, 20)
        if #out ~= 20 then return false, "cap not enforced: " .. #out end
        -- The cap must drop the OLDEST posts, never the newest.
        if out[#out].t ~= "p30" then return false, "newest post was dropped" end
        if out[1].t ~= "p11" then return false, "wrong window kept: " .. tostring(out[1].t) end
        -- Order must not depend on the input order.
        local shuffled = { posts[5], posts[30], posts[1], posts[17] }
        local s = Alliance._BuildBoard(shuffled, 20)
        if s[1].id ~= posts[1].id or s[4].id ~= posts[30].id then
            return false, "not sorted chronologically by id"
        end
        if #Alliance._BuildBoard(nil, 20) ~= 0 then return false, "nil must not error" end
        if #Alliance._BuildBoard({ "junk", 5 }, 20) ~= 0 then return false, "malformed rows must be skipped" end
        return true
    end)

    BRutus.SelfTest:Register("alliance.is_ambassador", function()
        local p = samplePact()
        if not Alliance.IsAmbassador(p, "Guild A", "Chehul") then return false, "known ambassador rejected" end
        if not Alliance.IsAmbassador(p, "Guild A", "Chehul-Nefarian") then return false, "realm suffix broke it" end
        if Alliance.IsAmbassador(p, "Guild B", "Chehul") then return false, "wrong guild accepted" end
        if Alliance.IsAmbassador(p, "Guild Z", "Chehul") then return false, "unknown guild accepted" end
        if Alliance.IsAmbassador(nil, "Guild A", "Chehul") then return false, "nil pact accepted" end
        if Alliance.IsAmbassador(p, "Guild A", "") then return false, "empty name accepted" end
        return true
    end)
end
