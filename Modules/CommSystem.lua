----------------------------------------------------------------------
-- BRutus Guild Manager - Communication System
-- Handles addon-to-addon communication for syncing member data
----------------------------------------------------------------------
local CommSystem = {}
BRutus.CommSystem = CommSystem
local L = BRutus.L

local LibSerialize = LibStub("LibSerialize")
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
}

-- Throttle settings
CommSystem.THROTTLE_INTERVAL = 5  -- seconds between broadcasts
CommSystem.lastBroadcast = 0

function CommSystem:Initialize()
    -- Register for addon messages on both the new prefix and the legacy BRutus prefix
    -- so this client can receive messages from older addon versions during guild transitions.
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        if prefix == BRutus.PREFIX or prefix == BRutus.LEGACY_PREFIX then
            CommSystem:OnMessageReceived(msg, channel, sender)
        end
    end)

    -- Periodic sync timer (every 5 minutes): PUSH our own data.
    C_Timer.NewTicker(300, function()
        if IsInGuild() then
            CommSystem:BroadcastMyData()
            if BRutus:IsOfficer() then
                if BRutus.TrialTracker then
                    C_Timer.After(5, function()
                        BRutus.TrialTracker:BroadcastTrials()
                    end)
                end
                if BRutus.RaidTracker then
                    C_Timer.After(10, function()
                        BRutus.RaidTracker:BroadcastRaidData()
                    end)
                end
                -- Keep members' copy of the recruitment ad fresh while enabled.
                if BRutus.Recruitment and BRutus.db.recruitment and BRutus.db.recruitment.enabled then
                    C_Timer.After(13, function()
                        BRutus.Recruitment:BroadcastStatus(true)
                    end)
                end
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
        if BRutus.DataCollector then BRutus.DataCollector:CollectMyData() end
        if BRutus.AttunementTracker then BRutus.AttunementTracker:ScanAttunements() end
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
        ChatThrottleLib:SendAddonMessage("NORMAL", BRutus.PREFIX, msg, "WHISPER", target)
    else
        ChatThrottleLib:SendAddonMessage(priority or "BULK", BRutus.PREFIX, msg, "GUILD")
    end
end

----------------------------------------------------------------------
-- Receive a message
----------------------------------------------------------------------
function CommSystem:OnMessageReceived(msg, _, sender)
    -- Don't process our own messages
    local myName = UnitName("player")
    if sender == myName or sender == myName .. "-" .. GetRealmName() then
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
        if BRutus.Wishlist then
            BRutus.Wishlist:HandleWishlistBroadcast(sender, data)
        end
    elseif msgType == "LP" then
        if BRutus.Wishlist then
            BRutus.Wishlist:HandleLootPriosBroadcast(sender, data)
        end
    elseif msgType == "ON" then
        if BRutus.OfficerNotes then
            BRutus.OfficerNotes:HandleIncoming(data)
        end
    elseif msgType == "RC" then
        if BRutus.RecipeTracker then
            BRutus.RecipeTracker:HandleIncoming(sender, data)
        end
    elseif msgType == "TR" then
        if BRutus.TrialTracker and BRutus:IsOfficer() then
            BRutus.TrialTracker:HandleIncoming(data)
        end
    elseif msgType == "RR" then
        -- Raider roster: everyone stores it (members view); HandleIncoming
        -- trusts it only when the sender is a verified officer.
        if BRutus.RaiderRoster then
            BRutus.RaiderRoster:HandleIncoming(sender, data)
        end
    elseif msgType == CommSystem.MSG_TYPES.ALT_LINK then
        -- Officer-authored, everyone stores: members need altLinks to see
        -- alt/main grouping (True Roster, chat tags, inspector).
        if BRutus:IsOfficerByName(sender) then
            local ok, links = LibSerialize:Deserialize(data)
            if ok and type(links) == "table" then
                BRutus.db.altLinks = links
            end
        end
    elseif msgType == CommSystem.MSG_TYPES.SELF_ALT then
        if BRutus.AltAutoDetect then BRutus.AltAutoDetect:HandleSelfClaim(sender, data) end
    elseif msgType == CommSystem.MSG_TYPES.RAID_DATA then
        if BRutus:IsOfficer() and BRutus.RaidTracker then
            BRutus.RaidTracker:HandleIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.RAID_DELETE then
        -- Only apply if the sender is a verified officer in the guild roster
        if BRutus:IsOfficerByName(sender) and BRutus.RaidTracker then
            BRutus.RaidTracker:HandleDeleteIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.NOTES_ALL then
        if BRutus:IsOfficer() and BRutus.OfficerNotes then
            BRutus.OfficerNotes:HandleAllIncoming(data)
        end
    elseif msgType == CommSystem.MSG_TYPES.SYNC_V2 then
        -- Versioned envelope (protocol v2): dedup/validation/dispatch is
        -- handled entirely by SyncService.
        if BRutus.SyncService then
            BRutus.SyncService:OnEnvelope(sender, data)
        end
    elseif msgType == CommSystem.MSG_TYPES.WELCOME_INTENT then
        -- Another officer is also considering welcoming this member; record their intent
        if BRutus.Recruitment and data and data ~= "" then
            BRutus.Recruitment._welcomeIntents = BRutus.Recruitment._welcomeIntents or {}
            BRutus.Recruitment._welcomeIntents[data] = BRutus.Recruitment._welcomeIntents[data] or {}
            BRutus.Recruitment._welcomeIntents[data][sender] = true
        end
    elseif msgType == CommSystem.MSG_TYPES.WELCOME_CLAIM then
        -- Another officer already sent the welcome — suppress ours
        if BRutus.Recruitment and data and data ~= "" then
            BRutus.Recruitment._welcomedRecently[data] = true
            BRutus.Recruitment._welcomedRecently[data .. "_sent"] = true
        end
    elseif msgType == CommSystem.MSG_TYPES.RECRUIT_INFO then
        -- Direct officer broadcast OR a member relay. Trust/version checks live
        -- in Recruitment:ApplyIncoming (author must be a verified officer).
        local ok, info = LibSerialize:Deserialize(data)
        if ok and BRutus.Recruitment then
            BRutus.Recruitment:ApplyIncoming(info, sender)
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
    if BRutus.DataCollector then
        BRutus.DataCollector:CollectMyData()
    end
    if BRutus.AttunementTracker then
        BRutus.AttunementTracker:ScanAttunements()
    end

    local data = BRutus.DataCollector:GetBroadcastData()
    local serialized = LibSerialize:Serialize(data)

    self:SendMessage(self.MSG_TYPES.BROADCAST, serialized)
end

----------------------------------------------------------------------
-- Handle incoming broadcast
----------------------------------------------------------------------
function CommSystem:HandleBroadcast(sender, data)
    local ok, playerData = LibSerialize:Deserialize(data)
    if not ok or type(playerData) ~= "table" then return end

    -- Build player key
    local realm = playerData.realm or GetRealmName()
    local name = playerData.name or sender:match("^([^-]+)")
    local key = BRutus:GetPlayerKey(name, realm)

    -- Store the data
    BRutus.DataCollector:StoreReceivedData(key, playerData)
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
        if BRutus:IsOfficer() then
            C_Timer.After(0.5, function()
                self:BroadcastAltLinks()
            end)
        end

        -- Officers also send trial data
        if BRutus:IsOfficer() and BRutus.TrialTracker then
            C_Timer.After(1, function()
                BRutus.TrialTracker:BroadcastTrials()
            end)
        end

        -- Officers also send raid attendance data
        if BRutus:IsOfficer() and BRutus.RaidTracker then
            C_Timer.After(2, function()
                BRutus.RaidTracker:BroadcastRaidData()
            end)
        end

        -- Share the guild recruitment config so alts/late-loggers reliably get
        -- it: officers push their own, members relay the cached copy.
        if BRutus.Recruitment then
            C_Timer.After(2.5, function()
                BRutus.Recruitment:RespondToSync()
            end)
        end

        -- Officers answer with the curated raider roster (login backfill).
        if BRutus:IsOfficer() and BRutus.RaiderRoster then
            C_Timer.After(3, function()
                BRutus.RaiderRoster:RespondToSync()
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
    self:SendMessage(self.MSG_TYPES.PONG, BRutus.VERSION, sender)
end

----------------------------------------------------------------------
-- Handle version check
----------------------------------------------------------------------
function CommSystem:HandleVersionCheck(_sender, data)
    -- Could notify user of newer versions
    if data and data ~= BRutus.VERSION then
        BRutus:Print(L["A different Guild OS version detected: "] .. tostring(data))
    end
end

----------------------------------------------------------------------
-- Broadcast alt link table to all officers in guild
----------------------------------------------------------------------
function CommSystem:BroadcastAltLinks()
    if not BRutus:IsOfficer() then return end
    if not IsInGuild() then return end
    local serialized = LibSerialize:Serialize(BRutus.db.altLinks or {})
    self:SendMessage(self.MSG_TYPES.ALT_LINK, serialized)
end

----------------------------------------------------------------------
-- Full sync: broadcast all data types in one staggered sequence
-- Everyone: own data + request from peers
-- Officers: alt links, trials, raid data, officer notes
----------------------------------------------------------------------
function CommSystem:FullSync()
    if not IsInGuild() then
        BRutus:Print(L["Not in a guild."])
        return
    end

    -- Broadcast own member data (gear, professions, attunements, recipes)
    self:BroadcastMyData()

    -- Request fresh data from all online guild members
    self:RequestAllData()

    if not BRutus:IsOfficer() then
        BRutus:Print(L["Syncing data with guild..."])
        return
    end

    -- Officer-only staggered broadcasts
    BRutus:Print(L["Syncing all guild data (officer mode)..."])

    C_Timer.After(1, function()
        self:BroadcastAltLinks()
    end)

    C_Timer.After(2, function()
        if BRutus.TrialTracker then
            BRutus.TrialTracker:BroadcastTrials()
        end
    end)

    C_Timer.After(3, function()
        if BRutus.RaidTracker then
            BRutus.RaidTracker:BroadcastRaidData()
        end
    end)

    C_Timer.After(4, function()
        if BRutus.OfficerNotes then
            BRutus.OfficerNotes:BroadcastAllNotes()
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
    local cur = BRutus.VERSION
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local d = BRutus.db.members[key]
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
