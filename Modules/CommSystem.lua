----------------------------------------------------------------------
-- Guild OS - Communication System
-- Handles addon-to-addon communication for syncing member data
----------------------------------------------------------------------
local CommSystem = {}
GuildOS.CommSystem = CommSystem
local L = GuildOS.L

local LibSerialize = LibStub("GuildOS-LibSerialize")
local LibDeflate = LibStub("LibDeflate")

-- Message types
CommSystem.MSG_TYPES = {
    BROADCAST = "BC",    -- Full data broadcast
    REQUEST   = "RQ",    -- Request data from someone
    RESPONSE  = "RS",    -- Response to a request
    PING      = "PI",    -- Presence ping
    PONG      = "PO",    -- Presence response
    VERSION   = "VR",    -- Version check
    ALT_LINK  = "AL",    -- Alt/main link table sync (officer-authored; all members store)
    SELF_ALT  = "SA",    -- member self-claim of own alts (officers replay via LinkAlt)
    RAID_DATA = "RD",    -- Raid attendance + session sync (officer only)
    RAID_DELETE = "RX",  -- Delete a raid session (officer only; sender verified)
    NOTES_ALL = "OA",    -- Bulk officer notes sync (officer only)
    WELCOME_INTENT = "WI",-- Officer declares intent to welcome a member (race coordination)
    WELCOME_CLAIM = "WC",-- Welcome message sent (suppresses remaining timers)
    SYNC_V2   = "SV",    -- SyncService v2 versioned envelope (points/events/bank/polls)
    RECRUIT_INFO = "RI", -- Recruitment status broadcast (officer → all members)
    LFG       = "LG",    -- member self-declared LFG availability (sender bound)
    RECRUIT_STATS = "RE",-- self-reported recruitment engagement (sender bound; officers aggregate).
                         -- NOT "RS": that code is already RESPONSE above; "RE" is the free code.
    MAP_POS   = "MP",    -- live guild-map position (sender bound; GUILD-only; clamped)
}

-- Throttle settings
CommSystem.THROTTLE_INTERVAL = 5  -- seconds between broadcasts
CommSystem.lastBroadcast = 0

function CommSystem:Initialize()
    -- Addon messages on Guild OS's prefix.
    local frame = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(frame, "CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        if prefix == GuildOS.PREFIX then
            CommSystem:OnMessageReceived(msg, channel, sender)
        end
    end)

    -- Periodic sync timer (every 5 minutes): PUSH our own data.
    C_Timer.NewTicker(300, function()
        if IsInGuild() then
            CommSystem:BroadcastMyData()
            if GuildOS:IsOfficer() then
                if GuildOS.TrialTracker then
                    C_Timer.After(5, function()
                        GuildOS.TrialTracker:BroadcastTrials()
                    end)
                end
                if GuildOS.RaidTracker then
                    C_Timer.After(10, function()
                        GuildOS.RaidTracker:BroadcastRaidData()
                    end)
                end
                -- Keep members' copy of the recruitment ad fresh while enabled.
                if GuildOS.Recruitment and GuildOS.db.recruitment and GuildOS.db.recruitment.enabled then
                    C_Timer.After(13, function()
                        GuildOS.Recruitment:BroadcastStatus(true)
                    end)
                end
                -- And the guild's officer threshold, for a client that missed the change (issue #81).
                C_Timer.After(15, function() GuildOS:PublishOfficerMaxRank() end)
            end
        end
    end)

    -- Periodic re-REQUEST (self-healing PULL) on a slower, jittered cadence.
    -- The 300s ticker above only broadcasts our own data; without this a client
    -- that missed a peer's one broadcast would never re-pull it within the
    -- session. Kept on a separate 10-min timer; the 0-15s jitter spreads the
    -- guild-wide REQUEST fan-out across clients (each peer's response is itself
    -- throttled to once per THROTTLE_INTERVAL, so this cannot storm the channel).
    C_Timer.NewTicker(600, function()
        if IsInGuild() then
            C_Timer.After(math.random() * 15, function()
                if IsInGuild() then CommSystem:RequestAllData() end
            end)
        end
    end)

    -- Reliable startup sync (first-open PUSH). Initialize() only runs AFTER the
    -- guild DB is resolved (via InitModules), so this fires even on a COLD login
    -- where OnEnterWorld bailed out before self.db existed. This is what makes a
    -- freshly-installed member's data reach the guild promptly instead of waiting
    -- up to 5 minutes for the first periodic tick.
    C_Timer.After(3, function()
        if not IsInGuild() then return end
        if GuildOS.DataCollector then GuildOS.DataCollector:CollectMyData() end
        if GuildOS.AttunementTracker then GuildOS.AttunementTracker:ScanAttunements() end
        C_Timer.After(2, function()
            if IsInGuild() then CommSystem:BroadcastMyData() end
        end)
    end)

    -- First-open PULL: a small staggered burst (not a single shot) so a newly
    -- installed member reliably pulls existing members' data even if the first
    -- request is dropped or peers are still loading when it goes out.
    for _, delay in ipairs({ 8, 25, 60 }) do
        C_Timer.After(delay, function()
            if IsInGuild() then CommSystem:RequestAllData() end
        end)
    end
end

-- Chunking settings
CommSystem.CHUNK_SIZE = 230  -- Leave room for chunk header + "M:xxxx:nn:nn:"
CommSystem.pendingMessages = {}  -- [sender] = { chunks = {}, total = 0, received = 0 }

----------------------------------------------------------------------
-- Send a message to guild (with chunking for large payloads)
----------------------------------------------------------------------
function CommSystem:SendMessage(msgType, data, target, priority)
    local payload = msgType .. ":" .. (data or "")

    -- Compress
    local compressed = LibDeflate:CompressDeflate(payload)
    local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)

    local len = #encoded
    if len <= 250 then
        -- Single message, no chunking needed (prefix with "S:").
        -- Cap at 250 so "S:" + payload stays safely under the 255-byte addon-message limit.
        local msg = "S:" .. encoded
        self:SendRaw(msg, target, priority)
    else
        -- Multi-chunk: prefix each with "M:msgId:chunkIndex:totalChunks:"
        local msgId = string.format("%X", math.random(0, 0xFFFF))
        local totalChunks = math.ceil(len / self.CHUNK_SIZE)
        for i = 1, totalChunks do
            local startPos = (i - 1) * self.CHUNK_SIZE + 1
            local endPos = math.min(i * self.CHUNK_SIZE, len)
            local chunk = encoded:sub(startPos, endPos)
            local header = string.format("M:%s:%d:%d:", msgId, i, totalChunks)
            C_Timer.After((i - 1) * 0.1, function()
                self:SendRaw(header .. chunk, target, priority)
            end)
        end
    end
end

function CommSystem:SendRaw(msg, target, priority)
    if target then
        GuildOS.Compat.SendAddonMessage(GuildOS.PREFIX, msg, "WHISPER", target, "NORMAL")
    else
        GuildOS.Compat.SendAddonMessage(GuildOS.PREFIX, msg, "GUILD", nil, priority or "BULK")
    end
end

----------------------------------------------------------------------
-- Receive a message
----------------------------------------------------------------------
-- channel is the addon-message distribution ("GUILD", "WHISPER", "PARTY", ...)
-- from CHAT_MSG_ADDON. Threaded to the type dispatch so handlers can bind trust
-- to how a message arrived, not just to who claims to have authored the body.
-- For a reassembled multi-chunk message this is the channel of the arriving
-- chunk; every chunk of one message travels over the same distribution.
function CommSystem:OnMessageReceived(msg, channel, sender)
    -- Don't process our own messages
    local myName = GuildOS.Compat.PlayerName()
    if sender == myName or sender == GuildOS:GetPlayerKey(myName) then
        return
    end

    local encoded
    local prefix = msg:sub(1, 2)

    if prefix == "S:" then
        -- Single (non-chunked) message
        encoded = msg:sub(3)
    elseif prefix == "M:" then
        -- Multi-chunk message: "M:msgId:chunkIndex:totalChunks:data"
        local msgId, idx, total, chunkData = msg:match("^M:(%x+):(%d+):(%d+):(.+)$")
        if not msgId then return end
        idx = tonumber(idx)
        total = tonumber(total)

        local key = sender .. ":" .. msgId
        if not self.pendingMessages[key] then
            self.pendingMessages[key] = { chunks = {}, total = total, received = 0 }
            -- Timeout: clean up after 30s
            C_Timer.After(30, function()
                self.pendingMessages[key] = nil
            end)
        end

        local pending = self.pendingMessages[key]
        if not pending.chunks[idx] then
            pending.chunks[idx] = chunkData
            pending.received = pending.received + 1
        end

        if pending.received < pending.total then
            return  -- Still waiting for more chunks
        end

        -- All chunks received, reassemble
        local parts = {}
        for i = 1, pending.total do
            parts[i] = pending.chunks[i] or ""
        end
        encoded = table.concat(parts)
        self.pendingMessages[key] = nil
    else
        -- Legacy (untagged) message — treat as single
        encoded = msg
    end

    -- Decode and decompress
    local decoded = LibDeflate:DecodeForWoWAddonChannel(encoded)
    if not decoded then return end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return end

    -- Parse message type
    local msgType, data = decompressed:match("^(%w+):(.*)$")
    if not msgType then return end

    if msgType == CommSystem.MSG_TYPES.BROADCAST then
        self:HandleBroadcast(sender, data)
    elseif msgType == CommSystem.MSG_TYPES.REQUEST then
        self:HandleRequest(sender, data)
    elseif msgType == CommSystem.MSG_TYPES.RESPONSE then
        self:HandleResponse(sender, data)
    elseif msgType == CommSystem.MSG_TYPES.PING then
        self:HandlePing(sender)
    elseif msgType == CommSystem.MSG_TYPES.VERSION then
        self:HandleVersionCheck(sender, data)
    elseif msgType == "WL" then
        if GuildOS.Wishlist then
            GuildOS.Wishlist:HandleWishlistBroadcast(sender, data)
        end
    elseif msgType == "LP" then
        -- Officer-set priorities, stored by everyone: only an officer's, over GUILD, replace them.
        -- The channel matters as much as the name: IsOfficerByName drops the realm, so a
        -- namesake on another realm could whisper as the officer (issue #78).
        if GuildOS.Wishlist and channel == "GUILD" and GuildOS:IsOfficerByName(sender) then
            GuildOS.Wishlist:HandleLootPriosBroadcast(sender, data)
        end
    elseif msgType == "ON" then
        -- Only an officer writes officer notes, and only an officer keeps them (issue #78).
        if GuildOS.OfficerNotes and GuildOS:IsOfficer() and channel == "GUILD" and GuildOS:IsOfficerByName(sender) then
            GuildOS.OfficerNotes:HandleIncoming(data)
        end
    elseif msgType == "RC" then
        if GuildOS.RecipeTracker then
            GuildOS.RecipeTracker:HandleIncoming(sender, data)
        end
    elseif msgType == "TR" then
        if GuildOS.TrialTracker and GuildOS:IsOfficer() and channel == "GUILD" and GuildOS:IsOfficerByName(sender) then
            GuildOS.TrialTracker:HandleIncoming(data)
        end
    elseif msgType == "RR" then
        -- Raider roster: everyone stores it (members view); HandleIncoming
        -- trusts it only when the sender is a verified officer, and only over GUILD (issue #81).
        if GuildOS.RaiderRoster and channel == "GUILD" then
            GuildOS.RaiderRoster:HandleIncoming(sender, data)
        end
    elseif msgType == CommSystem.MSG_TYPES.ALT_LINK then
        -- Officer-authored, everyone stores: members need altLinks to see
        -- alt/main grouping (True Roster, chat tags, inspector). Over GUILD only (issue #81).
        if channel == "GUILD" and GuildOS:IsOfficerByName(sender) then
            local ok, links = LibSerialize:Deserialize(data)
            if ok and type(links) == "table" then
                -- Both sides keyed this client's way: on Forever the officer's keys carry its realm (#97).
                local localized = {}
                for alt, main in pairs(links) do
                    local la, lm = GuildOS:LocalMemberKey(alt), GuildOS:LocalMemberKey(main)
                    if la ~= lm then localized[la] = lm end   -- one split person is not their own alt
                end
                GuildOS.db.altLinks = localized
            end
        end
    elseif msgType == CommSystem.MSG_TYPES.SELF_ALT then
        if GuildOS.AltAutoDetect then GuildOS.AltAutoDetect:HandleSelfClaim(sender, data) end
    elseif msgType == CommSystem.MSG_TYPES.LFG then
        if GuildOS.LFGBoard then GuildOS.LFGBoard:HandleEntry(sender, data) end
    elseif msgType == CommSystem.MSG_TYPES.RAID_DATA then
        if GuildOS:IsOfficer() and channel == "GUILD" and GuildOS:IsOfficerByName(sender) and GuildOS.RaidTracker then
            GuildOS.RaidTracker:HandleIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.RAID_DELETE then
        -- Only apply if the sender is a verified officer in the guild roster, over GUILD (issue #81)
        if channel == "GUILD" and GuildOS:IsOfficerByName(sender) and GuildOS.RaidTracker then
            GuildOS.RaidTracker:HandleDeleteIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.NOTES_ALL then
        if GuildOS:IsOfficer() and channel == "GUILD" and GuildOS:IsOfficerByName(sender) and GuildOS.OfficerNotes then
            GuildOS.OfficerNotes:HandleAllIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.SYNC_V2 then
        -- Versioned envelope (protocol v2): dedup/validation/dispatch is
        -- handled entirely by SyncService.
        if GuildOS.SyncService then
            GuildOS.SyncService:OnEnvelope(sender, data, channel)
        end
    elseif msgType == CommSystem.MSG_TYPES.WELCOME_INTENT then
        -- Another officer is also considering welcoming this member; record their intent. The
        -- welcome race is the officers', over GUILD: anybody else could win the tie-break with a
        -- low-sorting name, or suppress a welcome with a claim (issue #78).
        if GuildOS.Recruitment and data and data ~= "" and channel == "GUILD" and GuildOS:IsOfficerByName(sender) then
            GuildOS.Recruitment._welcomeIntents = GuildOS.Recruitment._welcomeIntents or {}
            GuildOS.Recruitment._welcomeIntents[data] = GuildOS.Recruitment._welcomeIntents[data] or {}
            GuildOS.Recruitment._welcomeIntents[data][sender] = true
        end
    elseif msgType == CommSystem.MSG_TYPES.WELCOME_CLAIM then
        -- Another officer already sent the welcome — suppress ours. Every client gets this, and
        -- only an officer's Recruitment:Initialize creates the table (issue #77).
        if GuildOS.Recruitment and data and data ~= "" and channel == "GUILD" and GuildOS:IsOfficerByName(sender) then
            GuildOS.Recruitment._welcomedRecently = GuildOS.Recruitment._welcomedRecently or {}
            GuildOS.Recruitment._welcomedRecently[data] = true
            GuildOS.Recruitment._welcomedRecently[data .. "_sent"] = true
        end
    elseif msgType == CommSystem.MSG_TYPES.RECRUIT_INFO then
        -- Direct officer broadcast OR a member relay. Trust is bound to the
        -- envelope (sender + channel) in Recruitment:ApplyIncoming: it must
        -- arrive over GUILD, name a current officer as author, and be sent by a
        -- current guildmate. Passing channel is what kills the whisper-injection.
        local ok, info = LibSerialize:Deserialize(data)
        if ok and GuildOS.Recruitment then
            GuildOS.Recruitment:ApplyIncoming(info, sender, channel)
        end
    elseif msgType == CommSystem.MSG_TYPES.RECRUIT_STATS then
        -- Self-reported engagement stats. Identity is the envelope sender and it
        -- must arrive over GUILD; HandleStats keys the entry by that sender and
        -- clamps every number, so a member can only file under their own name and
        -- a hostile packet cannot break the officer UI.
        if GuildOS.RecruitEngagement then
            GuildOS.RecruitEngagement:HandleStats(sender, data, channel)
        end
    elseif msgType == CommSystem.MSG_TYPES.MAP_POS then
        -- Live guild-map position. Identity is the envelope sender and it must
        -- arrive over GUILD; HandlePosition keys the entry by that sender and
        -- clamps every number, so a peer can only ever place its OWN pin and a
        -- hostile packet cannot break the map UI. channel is threaded exactly
        -- like RECRUIT_STATS so the GUILD-only rule can be enforced.
        if GuildOS.GuildMap then
            GuildOS.GuildMap:HandlePosition(sender, data, channel)
        end
    end
end

----------------------------------------------------------------------
-- Broadcast own data
----------------------------------------------------------------------
-- force=true bypasses the throttle (used for corrective re-broadcasts once a
-- cold-cache snapshot finally resolves, which would otherwise be swallowed by
-- the 5s window right after the startup broadcast).
function CommSystem:BroadcastMyData(force)
    if not IsInGuild() then return end

    -- Throttle
    local now = GetTime()
    if not force and now - self.lastBroadcast < self.THROTTLE_INTERVAL then return end
    self.lastBroadcast = now

    -- Collect fresh data
    if GuildOS.DataCollector then
        GuildOS.DataCollector:CollectMyData()
    end
    if GuildOS.AttunementTracker then
        GuildOS.AttunementTracker:ScanAttunements()
    end

    local data = GuildOS.DataCollector:GetBroadcastData()
    local serialized = LibSerialize:Serialize(data)

    self:SendMessage(self.MSG_TYPES.BROADCAST, serialized)
end

----------------------------------------------------------------------
-- Handle incoming broadcast
----------------------------------------------------------------------
function CommSystem:HandleBroadcast(sender, data)
    local ok, playerData = LibSerialize:Deserialize(data)
    if not ok or type(playerData) ~= "table" then return end

    -- Build player key: the payload's realm, else the client's, as in 0.53.0. Only a client with no
    -- realm at all takes the sender's own suffix, so it agrees with a roster that suffixes names (issue #8).
    -- On WoW: Forever GetPlayerKey takes this client's realm whatever is passed (issue #95).
    local realm = playerData.realm
    if (not realm or realm == "") and not GuildOS:GetClientRealm() then realm = sender:match("^[^-]+%-(.+)$") end
    -- The name is the sender's: a broadcast is always its own author's data, and on WoW: Forever
    -- 0.56.0 sends only the first name while the sender carries the surname (issue #26).
    local name = sender:match("^([^-]+)") or playerData.name
    playerData.name = name
    local key = GuildOS:GetPlayerKey(name, realm)

    -- Store the data
    GuildOS.DataCollector:StoreReceivedData(key, playerData)
end

----------------------------------------------------------------------
-- Request data from all online guildies
----------------------------------------------------------------------
function CommSystem:RequestAllData()
    if not IsInGuild() then return end
    self:SendMessage(self.MSG_TYPES.REQUEST, "ALL")
end

----------------------------------------------------------------------
-- Handle data request
----------------------------------------------------------------------
function CommSystem:HandleRequest(_sender, _data)
    -- Respond with a broadcast to the GUILD channel instead of a direct
    -- WHISPER to the sender.  Using WHISPER caused "No player named X"
    -- spam whenever the requester logged off between their REQUEST and our
    -- staggered response — ChatThrottleLib would keep sending each queued
    -- chunk even after the player went offline.  Broadcasting to GUILD is
    -- safe and already happens every 5 minutes anyway.
    C_Timer.After(math.random() * 3, function()  -- Stagger responses
        self:BroadcastMyData()

        -- Officers also send the alt/main link table. This REQUEST handler
        -- is what a member's automatic login-time pull (and the periodic
        -- re-REQUEST ticker) lands on, so this is what lets a member who
        -- logs in later actually converge on altLinks without an officer
        -- having to run a manual /gos sync.
        if GuildOS:IsOfficer() then
            C_Timer.After(0.5, function()
                self:BroadcastAltLinks()
            end)
        end

        -- Officers also send trial data
        if GuildOS:IsOfficer() and GuildOS.TrialTracker then
            C_Timer.After(1, function()
                GuildOS.TrialTracker:BroadcastTrials()
            end)
        end

        -- Officers also send raid attendance data
        if GuildOS:IsOfficer() and GuildOS.RaidTracker then
            C_Timer.After(2, function()
                GuildOS.RaidTracker:BroadcastRaidData()
            end)
        end

        -- And the guild's officer threshold (issue #81)
        if GuildOS:IsOfficer() then
            C_Timer.After(3, function() GuildOS:PublishOfficerMaxRank() end)
        end

        -- Share the guild recruitment config so alts/late-loggers reliably get
        -- it: officers push their own, members relay the cached copy.
        if GuildOS.Recruitment then
            C_Timer.After(2.5, function()
                GuildOS.Recruitment:RespondToSync()
            end)
        end

        -- Officers answer with the curated raider roster (login backfill).
        if GuildOS:IsOfficer() and GuildOS.RaiderRoster then
            C_Timer.After(3, function()
                GuildOS.RaiderRoster:RespondToSync()
            end)
        end

        -- Every member answers with their own live LFG listing. Availability
        -- is otherwise only ever sent once, so a guildmate who logged in after
        -- the post would see an empty board until it was posted again.
        -- Rebroadcast carries the age of the entry, not a fresh timestamp, so
        -- answering requests can never extend a listing.
        if GuildOS.LFGBoard and GuildOS.LFGBoard:AmAvailable() then
            C_Timer.After(3.5, function()
                GuildOS.LFGBoard:Rebroadcast()
            end)
        end

        -- Every member answers with its own recruitment engagement self-report,
        -- so an officer logging in converges on a fresh picture of who is active.
        if GuildOS.RecruitEngagement then
            C_Timer.After(4, function()
                GuildOS.RecruitEngagement:BroadcastStats()
            end)
        end

        -- Every member answers with its own current map position (forced past
        -- the throttle), so a guildmate logging in converges on where everyone
        -- is instead of waiting for each peer's next zone change.
        if GuildOS.GuildMap then
            C_Timer.After(4.5, function()
                GuildOS.GuildMap:Broadcast(true)
            end)
        end

        -- Officers re-broadcast their authoritative shared state (blacklist,
        -- audit trail, bulletin board) so a peer who was offline when it last
        -- changed converges on login instead of waiting for the next mutation.
        -- Each backfill preserves its stored revision and never bumps it, so
        -- the SyncService revision check (or audit id-dedup) drops it for a
        -- peer already current and applies it only for one that missed the
        -- change. Members must never re-broadcast these, hence the gate.
        if GuildOS:IsOfficer() and GuildOS.BanList then
            C_Timer.After(5, function()
                GuildOS.BanList:Backfill()
            end)
        end

        if GuildOS:IsOfficer() and GuildOS.RosterLog then
            C_Timer.After(5.5, function()
                GuildOS.RosterLog:Backfill()
            end)
        end

        if GuildOS:IsOfficer() and GuildOS.Bulletin then
            C_Timer.After(6, function()
                GuildOS.Bulletin:Backfill()
            end)
        end
    end)
end

----------------------------------------------------------------------
-- Handle data response
----------------------------------------------------------------------
function CommSystem:HandleResponse(sender, data)
    -- Same as broadcast handling
    self:HandleBroadcast(sender, data)
end

----------------------------------------------------------------------
-- Handle ping (presence check)
----------------------------------------------------------------------
function CommSystem:HandlePing(sender)
    self:SendMessage(self.MSG_TYPES.PONG, GuildOS.VERSION, sender)
end

----------------------------------------------------------------------
-- Handle version check
----------------------------------------------------------------------
function CommSystem:HandleVersionCheck(_sender, data)
    -- Could notify user of newer versions
    if data and data ~= GuildOS.VERSION then
        GuildOS:Print(L["A different Guild OS version detected: "] .. tostring(data))
    end
end

----------------------------------------------------------------------
-- Broadcast alt link table to all officers in guild
----------------------------------------------------------------------
function CommSystem:BroadcastAltLinks()
    if not GuildOS:IsOfficer() then return end
    if not IsInGuild() then return end
    local serialized = LibSerialize:Serialize(GuildOS.db.altLinks or {})
    self:SendMessage(self.MSG_TYPES.ALT_LINK, serialized)
end

----------------------------------------------------------------------
-- Full sync: broadcast all data types in one staggered sequence
-- Everyone: own data + request from peers
-- Officers: alt links, trials, raid data, officer notes
----------------------------------------------------------------------
function CommSystem:FullSync()
    if not IsInGuild() then
        GuildOS:Print(L["Not in a guild."])
        return
    end

    -- Broadcast own member data (gear, professions, attunements, recipes)
    self:BroadcastMyData()

    -- Request fresh data from all online guild members
    self:RequestAllData()

    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["Syncing data with guild..."])
        return
    end

    -- Officer-only staggered broadcasts
    GuildOS:Print(L["Syncing all guild data (officer mode)..."])

    C_Timer.After(1, function()
        self:BroadcastAltLinks()
    end)

    C_Timer.After(2, function()
        if GuildOS.TrialTracker then
            GuildOS.TrialTracker:BroadcastTrials()
        end
    end)

    C_Timer.After(3, function()
        if GuildOS.RaidTracker then
            GuildOS.RaidTracker:BroadcastRaidData()
        end
    end)

    C_Timer.After(4, function()
        if GuildOS.OfficerNotes then
            GuildOS.OfficerNotes:BroadcastAllNotes()
        end
    end)
end

----------------------------------------------------------------------
-- Sync health: who is running Guild OS, who is on an outdated version,
-- and when each member last synced data. Drives the Audit > Sync view.
-- Returns (rows, withAddonCount, outdatedCount). Each row:
-- { name, key, class, online, hasAddon, version, outdated, lastUpdate }
----------------------------------------------------------------------
function CommSystem:GetSyncHealth()
    local rows, withAddon, outdated = {}, 0, 0
    local cur = GuildOS.VERSION
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = GuildOS:GetPlayerKey(short, realm)
            local d = GuildOS.db.members[key]
            local has = (d and d.lastUpdate and d.lastUpdate > 0) and true or false
            local ver = d and d.addonVersion or nil
            local isOld = (has and ver and ver ~= cur) and true or false
            if has then withAddon = withAddon + 1 end
            if isOld then outdated = outdated + 1 end
            rows[#rows + 1] = {
                name = short, key = key, class = classFile or "", online = isOnline,
                hasAddon = has, version = ver, outdated = isOld,
                lastUpdate = (d and d.lastUpdate) or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        -- Members WITHOUT the addon first (those are the actionable ones).
        if a.hasAddon ~= b.hasAddon then return not a.hasAddon end
        return a.name:lower() < b.name:lower()
    end)
    return rows, withAddon, outdated
end
